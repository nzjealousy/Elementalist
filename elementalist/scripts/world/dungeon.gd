class_name Dungeon
extends Node2D
## The world scene's builder, in two modes (Game.mode):
##   camp      one safe room: the forge, the notice board (leaderboard) and the gate to the dungeons
##   dungeon   a randomly generated set of floors (DungeonGen), played one room at a time; the run
##             is rebuilt from its seed and saved at every room, so Continue resumes it
##
## The dungeon run: a randomly generated set of floors (DungeonGen), played one room at a time.
## Combat rooms spawn their waves one after another; when the last monster dies the exit door
## unlocks and walking through it fades to the next room. Treasure rooms hold a chest, forge rooms
## the forge and a free heal; both open at once. The last room of the last floor is the boss.
## Every third floor ends with a mini boss. Beating the last boss (or dying) ends the run on a
## RunEndScreen, records it on the leaderboard and sends the hero back to camp.
##
## This node is the main scene's world. Its siblings are the Player and the HUD.

const TILE := 16
const WAVE_DELAY := 1.2   # seconds before a room's first wave, and between waves
const FADE_TIME := 0.25
const FORGE_HEAL := 0.5   # share of max HP a forge room restores (stamina and mana are refilled)
const MIN_SPAWN_DISTANCE := 100.0  # monsters appear at least this far from the player

var layout: Array = []   # floors -> rooms (see DungeonGen)
var floor_index := 0     # 0-based
var room_index := 0
var room: Dictionary = {}
var state := "idle"      # fighting, clear, transition, won or dead
var wave := 0            # waves of this room already spawned
var run_time := 0.0
var death: Dictionary = {}  # what dying cost: {"final": bool, "lost": [elements]}
var tier := 1            # which dungeon (Game.TIERS) this run is in
var rank := 0            # leaderboard place earned by the finished run (0: none)
var run_bonus := 0       # gold for clearing the dungeon
var gold_lost := 0       # gold a fall cost
var with_ui := true      # the menus and the fade layer (tests turn it off)
var rng := RandomNumberGenerator.new()
var iso_view: IsoView   # the isometric picture (when the setting is on and the game has its UI)

var _room_node: Node2D
var _exit_door: Door
var _wave_timer := 0.0
var _boss_spawned := false
var _fade: ColorRect
var _end_screen: RunEndScreen
var _text_timer := 0.0
var _dummy_timer := 0.0
var viewer := false             # a guest in someone else's multiplayer game: builds the host's rooms, spawns nothing
var coop_host: CoopHost         # the host's side of a multiplayer session
var coop_client: CoopClient     # a guest's side
var scores: Dictionary = {}     # arena: kills per player
const REVIVE_TIME := 5.0
var _revive_left := 0.0
var _last_attacker := 0         # arena: who hit this hero last
var _net_over := false


func _ready() -> void:
	viewer = viewer or (Net.is_client() and with_ui)
	var start := Vector2i.ZERO  # floor, room to begin in (a resumed run starts where it was saved)
	if layout.is_empty():
		start = _make_layout()
	else:
		Game.run_kills = 0
	Game.boss = null
	if with_ui and bool(Settings.get_value("iso_view")):
		iso_view = IsoView.attach(self)
	Game.loot_dropped.connect(_on_loot_dropped)
	if with_ui and Net.is_host():
		coop_host = CoopHost.attach(self)
		Net.pvp_damage_received.connect(_on_host_pvp_damage)
		Net.end_received.connect(on_net_end)
	elif viewer:
		coop_client = CoopClient.attach(self)
		Net.room_received.connect(_on_net_room)
		Net.end_received.connect(on_net_end)
		Net.disconnected.connect(func(_reason): _leave_session("Connection lost"))
	if with_ui:
		Game.character.leveled_up.connect(func(_level): _fanfare("level_up"))
		Game.character.reward_ready.connect(func(_level): _fanfare("reward"))
	var player := _player()
	if player:
		player.died.connect(_on_player_died)
	if with_ui:
		var parent := get_parent()
		var creation := NewCharacterMenu.new()
		parent.add_child.call_deferred(creation)
		if Game.open_creation:
			Game.open_creation = false
			creation.toggle.call_deferred()
		parent.add_child.call_deferred(RewardCards.new())
		parent.add_child.call_deferred(DungeonSelect.new())
		parent.add_child.call_deferred(AltarScreen.new())
		parent.add_child.call_deferred(LeaderboardScreen.new())
		parent.add_child.call_deferred(PauseMenu.new())
		parent.add_child.call_deferred(ClassCards.new())
		parent.add_child.call_deferred(ForgeScreen.new())
		_end_screen = RunEndScreen.new()
		parent.add_child.call_deferred(_end_screen)
		var fade_layer := CanvasLayer.new()
		fade_layer.layer = 40
		_fade = ColorRect.new()
		_fade.color = Color(0, 0, 0, 0)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade_layer.add_child(_fade)
		add_child(fade_layer)
	_load_room(start.x, start.y)


## Builds the layout for the current Game.mode. Returns the (floor, room) to start in.
func _make_layout() -> Vector2i:
	if viewer:
		var data := Net.room_data
		layout = [[data["room"] if data.has("room") else DungeonGen.camp_room()]]
		Game.run_kills = 0
		return Vector2i.ZERO
	if Game.mode == "arena":
		layout = [[DungeonGen.arena_room()]]
		Game.run_kills = 0
		return Vector2i.ZERO
	if Game.mode == "training":
		layout = [[DungeonGen.training_room()]]
		Game.run_kills = 0
		return Vector2i.ZERO
	if Game.mode == "camp" or Game.run.is_empty():
		layout = [[DungeonGen.camp_room()]]
		Game.run_kills = 0
		return Vector2i.ZERO
	var spec: Dictionary = Game.TIERS[int(Game.run["tier"])]
	tier = int(Game.run["tier"])
	rng.seed = int(Game.run["seed"])
	layout = DungeonGen.generate(rng, int(spec["floors"]), tier, int(spec["depth"]))
	run_time = float(Game.run.get("time", 0.0))
	Game.run_kills = int(Game.run.get("kills", 0))
	return Vector2i(clampi(int(Game.run.get("floor", 0)), 0, layout.size() - 1), maxi(int(Game.run.get("room", 0)), 0))


func _player() -> Node2D:
	return get_parent().get_node_or_null("Player") as Node2D


# ---------- debug keys ----------

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not (event is InputEventKey and event.pressed and not event.echo) or Net.is_online():
		return  # (debug builds only: F5 swaps in a sandbox hero, which must never reach a shipped game)
	match event.keycode:
		KEY_F5:
			Game.start_sandbox("channeler")
			get_tree().reload_current_scene()
		KEY_F10:
			Game.attune_random()  # no restart: the player picks up the new element live
		KEY_F6:
			var screen := get_tree().get_first_node_in_group("forge_screen")  # the forge from anywhere
			if screen:
				screen.open()
		KEY_BRACKETLEFT:
			debug_clear_room()
		KEY_BRACKETRIGHT:
			debug_goto(layout.size() - 1, layout[-1].size() - 1)  # straight to the boss


## Kills everything in the room and cancels the waves still to come.
func debug_clear_room() -> void:
	if state != "fighting":
		return
	wave = room["waves"].size()
	_boss_spawned = true
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Enemy and not node.is_queued_for_deletion():
			node.take_hit({"damage": 100000.0, "element": "", "from": node.global_position})


func debug_goto(floor_number: int, room_number: int) -> void:
	_load_room(floor_number, room_number)


# ---------- rooms ----------

## Builds room `room_number` of floor `floor_number` (0-based), puts the player in it and
## starts what the room holds.
func _load_room(floor_number: int, room_number: int) -> void:
	floor_index = floor_number
	room_index = room_number
	room = layout[floor_number][room_number]
	if _room_node:
		remove_child(_room_node)  # out of the tree now, so its monsters leave the "enemies" group at once
		_room_node.queue_free()
	_room_node = Node2D.new()
	add_child(_room_node)
	_exit_door = null
	wave = 0
	_boss_spawned = false
	Game.boss = null
	Game.danger = (int(room.get("depth", floor_number + 1)) - 1) * 3 + room_number
	if iso_view:
		iso_view.begin_room(room, TILE)
	_build_room()

	var player := _player()
	if player:
		var tile := DungeonGen.spawn_tile(room)
		player.global_position = Vector2(tile) * TILE + Vector2(TILE, TILE) * 0.5
		if player.has_method("set_camera_limits"):
			player.set_camera_limits(Rect2i(0, 0, int(room["cols"]) * TILE, int(room["rows"]) * TILE))
		var camera := player.get_node_or_null("Camera2D") as Camera2D
		if camera and camera.is_inside_tree():
			camera.reset_smoothing()

	if viewer:  # a guest: the host runs the room
		state = "viewer"
		if String(room["kind"]) == "arena":
			_place_in_arena()
		_play_music()
		return
	match String(room["kind"]):
		"arena":
			_build_arena()
		"camp":
			_build_camp()
		"training":
			_build_training()
		"combat", "boss", "miniboss":
			state = "fighting"
			_wave_timer = WAVE_DELAY
		"treasure":
			var chest := Chest.new()
			chest.position = _centre()
			_room_node.add_child(chest)
			_clear_room("A treasure room. Open the chest (G).")
		"forge":
			var forge := ForgeStation.new()
			forge.position = _centre()
			_room_node.add_child(forge)
			_heal_player()
			_clear_room("A place to rest: the forge (G). Half your health, all your stamina and mana.")
	if String(room["kind"]) in ["combat", "boss", "miniboss"]:
		var goal := "Clear the room to open the door"
		if room["kind"] == "boss":
			goal = "Defeat the boss!"
		elif room["kind"] == "miniboss":
			goal = "A guardian blocks the way. Defeat it to open the door"
		Game.say("%s\n%s" % [DungeonGen.describe(room), goal])
	_update_run_text()
	_play_music()
	if coop_host:
		Net.send_room(room, floor_index, room_index, Game.run_text)
	_autosave()


func _fanfare(sound: String) -> void:
	Sfx.play(sound)
	Sfx.duck(0.9)


## Music follows the place: the camp, the vault or the crypt; a boss track in a guardian's room.
func _play_music() -> void:
	if not with_ui:
		return
	var kind := String(room.get("kind", ""))
	if kind in ["boss", "miniboss"] and state != "clear":
		Sfx.music("boss")
	else:
		Sfx.music(String({"camp": "camp", "crypt": "crypt", "spire": "crypt"}.get(_theme(), "vault")))


## The camp: heal up, stand the forge, the notice board and the gate in the room.
func _build_camp() -> void:
	var middle := _centre()
	var forge := ForgeStation.new()
	forge.position = middle + Vector2(-56, 0)
	_room_node.add_child(forge)
	var board := CampBoard.new()
	board.position = middle + Vector2(56, 0)
	_room_node.add_child(board)
	var gate := CampGate.new()
	gate.position = middle + Vector2(0, -float(room["rows"]) * TILE * 0.5 + TILE * 1.5)
	_room_node.add_child(gate)
	_heal_player(1.0)
	var post := TrainingSign.new()
	post.position = middle + Vector2(-float(room["cols"]) * TILE * 0.5 + TILE * 3.0, float(room["rows"]) * TILE * 0.5 - TILE * 2.0)
	_room_node.add_child(post)
	state = "camp"
	Game.say("The camp. The gate (north) leads to the dungeons; the sign (south-west) to the training grounds.\nYour progress is saved here.")


## The training grounds: dummies that never fight back, the altar of elements, a sign back to camp
## and the controls checklist. The hero is a sandbox copy, so nothing here is saved or lost.
func _build_training() -> void:
	var middle := _centre()
	var altar := ElementAltar.new()
	altar.position = middle + Vector2(0, -float(room["rows"]) * TILE * 0.5 + TILE * 3.0)
	_room_node.add_child(altar)
	var post := TrainingSign.new()
	post.leaving = true
	post.position = middle + Vector2(-float(room["cols"]) * TILE * 0.5 + TILE * 3.0, float(room["rows"]) * TILE * 0.5 - TILE * 2.0)
	_room_node.add_child(post)
	_keep_dummies()
	_heal_player(1.0)
	state = "training"
	if with_ui:
		get_parent().add_child.call_deferred(TutorialGuide.new())
	Game.say("The training grounds.\nTry every control on the dummies; the altar compares the elements.")


## Three dummies stand in the grounds; a destroyed one comes back after a moment.
func _keep_dummies() -> void:
	var spots := [Vector2(0.72, 0.35), Vector2(0.78, 0.65), Vector2(0.58, 0.5)]
	var alive := get_tree().get_nodes_in_group("dummies").filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion()).size()
	for i in range(alive, spots.size()):
		var size := Vector2(int(room["cols"]), int(room["rows"])) * TILE
		var dummy := Monsters.spawn(_room_node, "dummy", size * spots[i], "", Vector2.ONE, 1)
		dummy.add_to_group("dummies")


## Saves the run (not in camp, tests or the sandbox): where we are and how much health is left.
func _autosave() -> void:
	if not with_ui or Game.slot < 0 or Game.mode != "dungeon":
		return
	var player := _player()
	Game.run["floor"] = floor_index
	Game.run["room"] = room_index
	Game.run["kills"] = Game.run_kills
	Game.run["time"] = run_time
	if player and "hp" in player:
		Game.run["hp"] = clampf(float(player.hp) / maxf(float(player.max_hp), 1.0), 0.05, 1.0)
	Game.save_game()


func _centre() -> Vector2:
	return Vector2(int(room["cols"]), int(room["rows"])) * TILE * 0.5


## The look of the place: the camp, the first dungeon (vault) or the second (crypt).
func _theme() -> String:
	if room.get("kind", "") in ["camp", "training"]:
		return "camp"
	return String(Game.TIERS.get(tier, {}).get("theme", "crypt" if tier >= 2 else "vault"))


## The ground picture for a tile: one of a few variants, chosen by position so the same room always
## looks the same.
func _tile_art(kind: String, tile: Vector2i, variants: int) -> Texture2D:
	var theme := _theme()
	var pick := absi(tile.x * 7 + tile.y * 13 + tile.x * tile.y) % variants
	var id := "tile_%s_%s_%d" % [kind, theme, pick]
	return AssetDB.get_texture(id if AssetDB.has_art(id) else "tile_" + kind)


## The void around the room: a dark tiled picture under everything (tiles forever, so the camera
## never shows the edge).
func _add_background() -> void:
	var id := "bg_" + _theme()
	if not AssetDB.has_art(id):
		return
	var bg := Sprite2D.new()
	bg.texture = AssetDB.get_texture(id)
	bg.centered = false
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.region_enabled = true
	bg.region_rect = Rect2(-640, -640, 2048, 2048)
	bg.position = Vector2(-640, -640)
	bg.z_index = -20
	_room_node.add_child(bg)


func _build_room() -> void:
	_add_background()
	var sealed_tex := AssetDB.get_texture("door_sealed")
	var cols: int = room["cols"]
	var rows: int = room["rows"]
	var exit_rect := Rect2i()
	if room["exit"] != "":
		exit_rect = DungeonGen.door_rect(room, "exit")
	var entry_rect := Rect2i()
	if room["entry"] != "":
		entry_rect = DungeonGen.door_rect(room, "entry")
	var pillar_id := "tile_pillar_" + _theme()
	for y in rows:
		for x in cols:
			var tile := Vector2i(x, y)
			var boundary := x == 0 or y == 0 or x == cols - 1 or y == rows - 1
			if boundary and exit_rect.has_point(tile):
				_add_tile(_tile_art("floor", tile, 4), tile, false)  # under the door
				continue
			if boundary:
				_add_tile(sealed_tex if entry_rect.has_point(tile) else _tile_art("wall", tile, 3), tile, true)
			else:
				_add_tile(_tile_art("floor", tile, 4), tile, false)
	for rect in room["obstacles"]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var tile := Vector2i(x, y)
				_add_tile(AssetDB.get_texture(pillar_id) if AssetDB.has_art(pillar_id) else _tile_art("wall", tile, 3), tile, true)
	if room["exit"] != "":
		_exit_door = Door.new()
		_exit_door.setup(Rect2(Vector2(exit_rect.position) * TILE, Vector2(exit_rect.size) * TILE), String(room["exit"]))
		_room_node.add_child(_exit_door)


func _add_tile(texture: Texture2D, tile: Vector2i, solid: bool) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(tile) * TILE
	sprite.z_index = -10
	_room_node.add_child(sprite)
	if solid and iso_view:
		var is_pillar := texture == AssetDB.get_texture("tile_pillar_" + _theme())
		iso_view.add_wall(tile, _tile_art("wall", tile, 3) if is_pillar else texture, int(room["cols"]), int(room["rows"]), is_pillar)
	if solid:
		var body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE, TILE)
		shape.shape = rect
		body.position = Vector2(tile) * TILE + Vector2(TILE, TILE) * 0.5
		body.add_child(shape)
		_room_node.add_child(body)


# ---------- fighting ----------

func _physics_process(delta: float) -> void:
	if viewer:
		_tick_net(delta)
		return
	if coop_host:
		_tick_net(delta)
	if state in ["fighting", "clear"] and room.get("kind", "") != "camp":
		run_time += delta
	match state:
		"training":
			_dummy_timer -= delta
			if _dummy_timer <= 0.0:
				_dummy_timer = 1.5
				_keep_dummies()
		"fighting":
			_tick_fight(delta)
		"clear":
			_tick_exit()
		"arena":
			pass
	_text_timer -= delta
	if _text_timer <= 0.0:
		_text_timer = 0.25
		_update_run_text()


func enemies_alive() -> int:
	return get_tree().get_nodes_in_group("enemies").filter(func(n): return not n.is_queued_for_deletion()).size()


func _tick_fight(delta: float) -> void:
	if room["kind"] == "miniboss":
		_tick_miniboss(delta)
		return
	if _wave_timer > 0.0:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			if room["kind"] == "boss":
				_spawn_boss()
			else:
				_spawn_wave()
		return
	if enemies_alive() > 0:
		return
	if room["kind"] == "boss":
		if _boss_spawned:
			_win()
	elif wave < room["waves"].size():
		_wave_timer = WAVE_DELAY
	else:
		_clear_room("Room cleared! The door is open.")


## A mini boss room: the guardian appears, and when it falls the door opens.
func _tick_miniboss(delta: float) -> void:
	if _wave_timer > 0.0:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_spawn_boss()
		return
	if _boss_spawned and enemies_alive() == 0:
		_clear_room("The guardian falls! The door is open.")


func _spawn_wave() -> void:
	var entries: Array = room["waves"][wave]
	wave += 1
	var floor_scale := _monster_scale()
	for entry in entries:
		var pos := _spawn_point()
		var enemy := Monsters.spawn(_room_node, String(entry["id"]), pos, String(entry["variant"]), floor_scale, _depth())
		SkillFx.ring(_room_node, pos, 12.0, Elements.color_of(String(entry["variant"])) if entry["variant"] != "" else Color("c8c8d0"), 0.5, 1.0)
		enemy.name = "%s%d" % [String(entry["id"]).capitalize(), enemy.get_instance_id()]
	if room["waves"].size() > 1:
		Game.say("Wave %d/%d" % [wave, room["waves"].size()])


func _spawn_boss() -> void:
	_boss_spawned = true
	var pos := _centre() + Vector2(0, -float(room["rows"]) * TILE * 0.25)
	var boss := Monsters.spawn(_room_node, String(room["boss"]), pos, "", _monster_scale(), _depth())
	Game.boss = boss
	SkillFx.ring(_room_node, pos, 30.0, Color("ff6a4a"), 0.8, 2.0)
	Game.say("%s awakens!" % boss.display_name)
	Sfx.play("boss_roar")
	Sfx.duck(1.4)


## How deep this room is overall (the second dungeon starts where the first ends).
func _depth() -> int:
	return int(room.get("depth", room.get("floor", 1)))


## Monster (health, damage) multipliers: depth, times the chosen difficulty.
func _monster_scale() -> Vector2:
	return Monsters.floor_scale(_depth()) * Game.hardness_mult()


## A free spot in the room, away from the player and from pillars.
func _spawn_point() -> Vector2:
	var player := _player()
	var size := Vector2(int(room["cols"]), int(room["rows"])) * TILE
	var pos := _centre()
	var best := pos
	var best_distance := -1.0
	for attempt in 30:
		pos = Vector2(randf_range(3.0 * TILE, size.x - 3.0 * TILE), randf_range(3.0 * TILE, size.y - 3.0 * TILE))
		var blocked := false
		for rect in room["obstacles"]:
			blocked = blocked or Rect2(Vector2(rect.position) * TILE, Vector2(rect.size) * TILE).grow(8.0).has_point(pos)
		if blocked:
			continue
		var distance := pos.distance_to(player.global_position) if player else INF
		if distance >= MIN_SPAWN_DISTANCE:
			return pos
		if distance > best_distance:  # no good spot yet: keep the farthest free one as the fallback
			best = pos
			best_distance = distance
	return best


func _clear_room(message: String) -> void:
	state = "clear"
	_play_music()
	if _exit_door:
		_exit_door.unlock()
	Game.say(message)


func _heal_player(share: float = FORGE_HEAL) -> void:
	var player := _player()
	if player and "hp" in player:
		player.hp = minf(player.max_hp, player.hp + player.max_hp * share)  # a forge: half your health, not all of it
		player.stamina = player.max_stamina
		if player.caster:
			player.caster.mana = player.caster.max_mana
		FloatText.spawn(_room_node, player.global_position + Vector2(0, -10), "Rested", Color("7fe88a"), 9)


# ---------- moving on ----------

func _tick_exit() -> void:
	var player := _player()
	if _exit_door and _exit_door.open and player and _exit_door.contains(player.global_position):
		_go_next()
	elif _exit_door and _exit_door.open and coop_host:  # in a multiplayer game anyone at the door takes the party through
		for peer in coop_host.avatars:
			var avatar: Node2D = coop_host.avatars[peer]
			if is_instance_valid(avatar) and _exit_door.contains(avatar.global_position):
				_go_next()
				return


## Fades out, loads the next room (or the next floor's first) and fades back in.
func _go_next() -> void:
	state = "transition"
	_vacuum_loot()
	if _fade == null:
		_advance()
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	tween.tween_callback(_advance)
	tween.tween_property(_fade, "color:a", 0.0, FADE_TIME)


func _advance() -> void:
	if room_index + 1 < layout[floor_index].size():
		_load_room(floor_index, room_index + 1)
	elif floor_index + 1 < layout.size():
		_load_room(floor_index + 1, 0)
	else:
		_win()


## Everything still lying on the floor is picked up on the way out, so no loot is left behind.
func _vacuum_loot() -> void:
	var player := _player()
	for node in get_tree().get_nodes_in_group("pickups"):
		if node is Pickup and player:
			node.vacuum(player)


func _on_loot_dropped(drops: Array, pos: Vector2) -> void:
	if _room_node == null:
		return
	for entry in drops:
		Pickup.spawn(_room_node, pos, entry)


# ---------- the end of a run ----------

func _win() -> void:
	if state in ["won", "dead"]:
		return
	state = "won"
	_vacuum_loot()
	if with_ui and Game.slot >= 0 and Game.mode == "dungeon":
		_finish_run(true)
	if coop_host:
		Net.end_session({"kind": "coop", "won": true, "tier": tier, "bonus": run_bonus})
	Game.say("The dungeon is cleared!")
	get_tree().create_timer(2.0).timeout.connect(_end.bind(true))  # tied to this node, so freeing it cancels the screen


func _on_player_died() -> void:
	if state in ["won", "dead"]:
		return
	if Game.mode == "training":  # a sandbox hero cannot fall: stand them up again
		var player := _player()
		if player:
			player.hp = player.max_hp
			player.stamina = player.max_stamina
		return
	# multiplayer: a fallen hero waits a moment, then comes back (no penalty); a host left alone in a dungeon dies for real
	if with_ui and Net.is_online() and (Net.roster.size() > 1 or String(room.get("kind", "")) == "arena"):
		_net_player_down()
		return
	state = "dead"
	death = Game.character.die()
	if with_ui and Game.slot >= 0 and Game.mode == "dungeon":
		_finish_run(false)
	_end(false)


## Books the finished run: the hero's record (dungeons cleared, runs), the leaderboard, gold lost on
## a fall, and the save (a hero who died for good loses their save).
func _finish_run(won: bool) -> void:
	var meta: Dictionary = Game.meta
	var inventory := Game.character.inventory
	meta["runs"] = int(meta.get("runs", 0)) + 1
	if won:
		meta["tier_cleared"] = maxi(int(meta.get("tier_cleared", 0)), tier)
		var bonus := roundi(150.0 * tier * Game.reward_mult())
		inventory.gold += bonus
		run_bonus = bonus
	else:
		var lost := floori(inventory.gold * Game.DEATH_GOLD_LOSS)
		inventory.gold -= lost
		gold_lost = lost
	rank = Leaderboard.record({
		"name": Game.character.display_name, "class": String(Classes.CLASSES[Game.character.class_id]["name"]),
		"level": Game.character.level, "floors": _depth(), "kills": Game.run_kills, "gold": inventory.gold,
		"cleared": won, "tier": tier, "time": run_time, "reward_mult": Game.reward_mult(),
		"difficulty": String(meta.get("difficulty", "knight")),
		"outcome": "cleared" if won else ("died" if bool(death.get("final", false)) else "fell")})
	Game.run = {}
	if not won and bool(death.get("final", false)):
		SaveStore.delete_slot(Game.slot)  # permadeath: the hero is gone
		Game.slot = -1  # so no later save (autosave, pause menu, window close) writes the dead hero back
	else:
		Game.save_game()


func _end(won: bool) -> void:
	var lines := summary_lines(won)
	if _end_screen and is_instance_valid(_end_screen):
		_end_screen.show_result(won, lines, bool(death.get("final", false)))


func summary_lines(won: bool) -> Array:
	var minutes := floori(run_time / 60.0)
	var seconds := int(run_time) % 60
	var lines: Array = []
	lines.append(("Cleared all %d floors" % layout.size()) if won else ("Fell on floor %d, room %d" % [floor_index + 1, room_index + 1]))
	if won and run_bonus > 0:
		lines.append("Clear bonus: %d gold" % run_bonus)
	if not won and gold_lost > 0:
		lines.append("The fall cost %d gold" % gold_lost)
	if rank > 0:
		lines.append("Leaderboard: rank %d" % rank)
	lines.append("Monsters slain: %d" % Game.run_kills)
	lines.append("Time: %d:%02d" % [minutes, seconds])
	lines.append("Level %d    Gold %d" % [Game.character.level, Game.character.inventory.gold])
	if not won and not death.is_empty():
		if death["final"]:
			lines.append("With no elements left to lose, this is the end of %s." % Game.character.display_name)
		else:
			var lost: Array = death["lost"].map(func(e): return String(e).capitalize())
			lines.append("Lost: %s (their mastery starts over)" % ", ".join(lost))
			lines.append("Deaths so far: %d. The next one costs %d." % [Game.character.deaths, Game.character.deaths + 1])
	return lines


func _update_run_text() -> void:
	if room.get("kind", "") == "arena":
		set_net_scores(scores)
		return
	if room.get("kind", "") == "camp":
		Game.run_text = "Camp"
		return
	if room.get("kind", "") == "training":
		Game.run_text = "Training grounds"
		return
	var text := "Floor %d/%d  Room %d/%d" % [floor_index + 1, layout.size(), room_index + 1, layout[floor_index].size()]
	if room.get("kind", "") == "combat" and state == "fighting":
		text += "  Wave %d/%d" % [maxi(wave, 1), room["waves"].size()]
	if state == "fighting":
		text += "  Enemies %d" % enemies_alive()
	elif state == "clear" and room.get("kind", "") in ["combat", "boss", "miniboss"]:
		text += "  Door open"
	Game.run_text = text


# ---------- multiplayer ----------

## The arena: no monsters, everybody fights everybody. Each hero starts in their own corner.
func _build_arena() -> void:
	state = "arena"
	scores = {}
	for peer in Net.roster:
		scores[int(peer)] = 0
	_place_in_arena()
	_heal_player(1.0)
	Game.say("The arena. First to %d kills wins." % Net.ARENA_KILLS)


func _place_in_arena() -> void:
	var player := _player()
	if player == null:
		return
	var ids: Array = Net.roster.keys()
	ids.sort()
	var index := maxi(ids.find(Net.my_id()), 0)
	var cols := int(room["cols"])
	var rows := int(room["rows"])
	var corners := [Vector2(3, rows * 0.5), Vector2(cols - 4, rows * 0.5), Vector2(cols * 0.5, 3), Vector2(cols * 0.5, rows - 4)]
	player.global_position = corners[index % corners.size()] * TILE + Vector2(TILE, TILE) * 0.5


## The host's room reached a guest.
func _on_net_room(data: Dictionary) -> void:
	if not viewer:
		return
	layout = [[data["room"]]]
	_load_room(0, 0)
	Game.run_text = String(data.get("run_text", ""))


## Guests: the host says whether the exit is open.
func set_net_door(open: bool) -> void:
	if _exit_door and open and not _exit_door.open:
		_exit_door.unlock()


## Arena scoreboard in the run text.
func set_net_scores(new_scores: Dictionary) -> void:
	scores = new_scores
	if room.get("kind", "") != "arena":
		return
	var parts: Array[String] = []
	for peer in scores:
		parts.append("%s %d" % [String(Net.roster.get(int(peer), {}).get("name", "?")), int(scores[peer])])
	Game.run_text = "Arena  " + "  ".join(parts)


func note_attacker(peer: int) -> void:
	_last_attacker = peer


func _on_host_pvp_damage(hit: Dictionary, attacker: int) -> void:
	var hero := _player() as Player
	if hero == null:
		return
	_last_attacker = attacker
	hero.take_damage(float(hit.get("damage", 0.0)) * Net.PVP_DAMAGE, hit.get("from", hero.global_position + Vector2.UP))


## This hero fell in a multiplayer game: report it and sit out a few seconds.
func _net_player_down() -> void:
	var hero := _player() as Player
	if hero == null:
		return
	if String(room.get("kind", "")) == "arena":
		Net.send_pvp_down(_last_attacker)
		_last_attacker = 0
	elif viewer:
		Net.send_down()
	hero.process_mode = Node.PROCESS_MODE_DISABLED
	hero.visible = false
	_revive_left = REVIVE_TIME if String(room.get("kind", "")) != "arena" else 2.5
	Game.say("You fell. Back in %d..." % int(_revive_left))


func _tick_net(delta: float) -> void:
	var hero := _player() as Player
	if _revive_left > 0.0 and hero:
		_revive_left -= delta
		if _revive_left <= 0.0:
			hero.process_mode = Node.PROCESS_MODE_INHERIT
			hero.visible = true
			hero.hp = hero.max_hp * (1.0 if String(room.get("kind", "")) == "arena" else 0.5)
			if String(room.get("kind", "")) == "arena":
				_place_in_arena()
			else:
				var tile := DungeonGen.spawn_tile(room)
				hero.global_position = Vector2(tile) * TILE + Vector2(TILE, TILE) * 0.5
			FloatText.spawn(get_parent(), hero.global_position + Vector2(0, -10), "Back!", Color("7fe88a"), 9)
	if coop_host and not _net_over and String(room.get("kind", "")) != "arena" and coop_host.wiped() and state in ["fighting", "clear"]:
		var info := {"kind": "coop", "won": false}
		Net.end_session(info)
		on_net_end(info)


## The session is over: a result for everybody, then back to the menu (guests) or the camp (the host).
func on_net_end(info: Dictionary) -> void:
	if _net_over:
		return
	_net_over = true
	var text := ""
	if String(info.get("kind", "")) == "arena":
		text = "%s wins the arena!" % String(info.get("winner_name", "Somebody"))
	elif bool(info.get("won", false)):
		text = "The dungeon is cleared! Together."
		if viewer:  # a guest earns the clear bonus too (capped: the host's numbers go into this guest's save)
			var reward := Net.clean_clear_reward(info)
			Game.character.inventory.gold += int(reward["bonus"])
			Game.meta["tier_cleared"] = maxi(int(Game.meta.get("tier_cleared", 0)), int(reward["tier"]))
			Game.character.inventory.changed.emit()
	else:
		text = "The party fell."
	Game.say(text)
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func(): _leave_session(text))


func _leave_session(_text: String) -> void:
	if not is_inside_tree():
		return
	var was_guest := Net.is_client()
	Net.leave()
	if was_guest or viewer:
		Game.save_game()
		Game.go_to_menu()
	else:
		Game.return_to_camp()


func on_net_peer_left(_peer: int) -> void:
	pass
