extends Node
## Audio (autoload "Sfx"): one small bus tree and two ways to play things.
##
##   Master <- Music, SFX, UI        (Settings drives each bus from a 0..1 slider)
##
##   Sfx.play("hit")        one-shot from res://assets/audio/sfx/hit.wav (+ hit_2.wav, hit_3.wav ... as
##                          variations: a random take, with a little pitch and volume jitter)
##   Sfx.play_at(...)       same, but quieter the farther from the player (no 3D positioning needed in 2D)
##   Sfx.music("dungeon")   crossfades to res://assets/audio/music/dungeon.wav (looped)
##
## Missing files are skipped silently, so the game runs the same with no audio assets.
## Sounds pass through bus names, never per-clip volume, so the sliders and any ducking just work.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const BUSES := ["Music", "SFX", "UI"]
const VOICES := 12          # simultaneous one-shots; the oldest voice is reused when all are busy
const MUSIC_FADE := 1.2
const DUCK_DB := -9.0       # music dips by this much under big hits (boss slams, level-ups)
const ERROR_GAP_MS := 300   # the "error" buzz plays at most once per this many ms

var _variants: Dictionary = {}   # name -> Array[AudioStream]
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_name := ""
var _rng := RandomNumberGenerator.new()
var _duck_tween: Tween
var _error_at := -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, &"Master")
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	apply_volumes()


func _make_music_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = &"Music"
	player.volume_db = -80.0
	add_child(player)
	return player


## Slider (0..1) to bus gain. Squared so the whole slider travel is audible; 0 is true silence.
func apply_volumes() -> void:
	_set_bus(&"Master", float(Settings.get_value("master_volume")))
	_set_bus(&"Music", float(Settings.get_value("music_volume")))
	_set_bus(&"SFX", float(Settings.get_value("sfx_volume")))
	_set_bus(&"UI", float(Settings.get_value("ui_volume")))


func _set_bus(bus_name: StringName, slider: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	var gain := clampf(slider, 0.0, 1.0)
	AudioServer.set_bus_mute(index, gain <= 0.0)
	AudioServer.set_bus_volume_linear(index, gain * gain)


# ---------- one-shots ----------

## Plays a sound effect by name. `bus` is "SFX" or "UI". Returns false if there is no such sound.
func play(sound: String, bus: StringName = &"SFX", volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	var takes := _takes(sound)
	if takes.is_empty():
		return false
	if sound == "error":  # a denied action: at most one buzz per ERROR_GAP_MS, so mashing a key cannot flood the voices
		if Time.get_ticks_msec() - _error_at < ERROR_GAP_MS:
			return false
		_error_at = Time.get_ticks_msec()
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = takes[_rng.randi_range(0, takes.size() - 1)]
	voice.bus = bus
	voice.volume_db = volume_db + _rng.randf_range(-1.5, 0.5)
	voice.pitch_scale = pitch * _rng.randf_range(0.95, 1.05)
	voice.play()
	return true


## UI clicks and the like.
func ui(sound: String) -> void:
	play(sound, &"UI")


## A world sound: louder near the player. `reach` is the distance (pixels) at which it fades out.
func play_at(sound: String, position: Vector2, reach: float = 260.0, volume_db: float = 0.0) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var distance := player.global_position.distance_to(position) if player else 0.0
	if distance >= reach:
		return
	var fade := 1.0 - distance / reach
	play(sound, &"SFX", volume_db + linear_to_db(fade * fade))


func _takes(sound: String) -> Array:
	if _variants.has(sound):
		return _variants[sound]
	var found: Array = []
	for suffix in ["", "_2", "_3", "_4", "_5"]:
		var path := "%s%s%s.wav" % [SFX_DIR, sound, suffix]
		if ResourceLoader.exists(path):
			found.append(load(path))
	_variants[sound] = found
	return found


# ---------- music ----------

## Crossfades to a looping track. "" fades out. Asking for the track already playing does nothing.
func music(track: String) -> void:
	if track == _music_name:
		return
	_music_name = track
	var path := "%s%s.wav" % [MUSIC_DIR, track]
	var incoming := _music_b
	var outgoing := _music_a
	_music_a = incoming
	_music_b = outgoing
	var tween := create_tween().set_parallel(true)
	tween.tween_property(outgoing, "volume_db", -80.0, MUSIC_FADE)
	tween.chain().tween_callback(outgoing.stop)
	if track != "" and ResourceLoader.exists(path):
		var stream := load(path) as AudioStreamWAV
		if stream:
			var bytes_per_frame := (4 if stream.stereo else 2)  # music is 16-bit PCM (tools/audio/gen_audio.py)
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = stream.data.size() / bytes_per_frame
		incoming.stream = stream
		incoming.volume_db = -80.0
		incoming.play()
		tween.tween_property(incoming, "volume_db", 0.0, MUSIC_FADE)


## Dips the music for a moment under something important, then lets it back (own bus gain, so the
## player's Music slider is left alone).
func duck(seconds: float = 0.6) -> void:
	var index := AudioServer.get_bus_index(&"Music")
	if index == -1:
		return
	if _duck_tween:
		_duck_tween.kill()
	AudioServer.set_bus_volume_linear(index, 0.0001 + db_to_linear(DUCK_DB) * pow(float(Settings.get_value("music_volume")), 2.0))
	_duck_tween = create_tween()
	_duck_tween.tween_interval(seconds)
	_duck_tween.tween_callback(apply_volumes)
