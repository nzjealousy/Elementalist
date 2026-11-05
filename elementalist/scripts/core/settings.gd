extends Node
## Player preferences, saved to user://settings.cfg (a ConfigFile: plain text, no objects, so a
## hand-edited or shared file cannot run anything). Autoload "Settings".
##
## Audio volumes are 0..1 sliders; Sfx maps them to bus gain. Everything else is read where it is
## used (screen shake in Juice, damage numbers in FloatText, HUD scale in Hud ...). Key and button
## bindings live in Controls, which asks Settings to persist them.

signal changed

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"master_volume": 0.8,
	"music_volume": 0.6,
	"sfx_volume": 0.8,
	"ui_volume": 0.7,
	"fullscreen": false,
	"screen_shake": 1.0,       # 0 turns shake off
	"damage_numbers": true,
	"iso_view": true,          # the isometric HD-2D picture (off: the flat top-down one); applies from the next scene
	"lighting": "full",        # "full", "soft" (brighter, dimmer pools, no flicker) or "off"; isometric view only, from the next scene
	"melee_indicator": true,   # the slash reach ring and wedge around the hero
	"hud_scale": 1.0,          # 0.75 .. 1.5
	"aim_assist": 0.5,         # controller only: pulls the aim toward the nearest enemy
	"stick_deadzone": 0.2,
	"show_tips": true,
}
const LIGHTING_MODES := ["full", "soft", "off"]

var values: Dictionary = DEFAULTS.duplicate()
var path := PATH  # tests point this somewhere else


func _ready() -> void:
	load_settings()
	apply()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant, save_now: bool = true) -> void:
	if not DEFAULTS.has(key):
		return
	values[key] = _clean(key, value)
	apply()
	if save_now:
		save()
	changed.emit()


func reset_to_defaults() -> void:
	values = DEFAULTS.duplicate()
	apply()
	save()
	changed.emit()


## Keeps a value the right type and inside its range, whatever was typed into the file.
func _clean(key: String, value: Variant) -> Variant:
	var default: Variant = DEFAULTS[key]
	if default is bool:
		return bool(value)
	if default is float:
		var number := float(value) if (value is float or value is int) else float(default)
		match key:
			"hud_scale":
				return clampf(number, 0.75, 1.5)
			"stick_deadzone":
				return clampf(number, 0.05, 0.6)
			_:
				return clampf(number, 0.0, 1.0)
	if key == "lighting":
		return value if value is String and value in LIGHTING_MODES else default
	return value


func save() -> Error:
	var config := ConfigFile.new()
	for key in values:
		config.set_value("settings", key, values[key])
	Controls.write_bindings(config)
	return config.save(path)


func load_settings() -> void:
	values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return  # first run, or a damaged file: the defaults stand
	for key in DEFAULTS:
		if config.has_section_key("settings", key):
			values[key] = _clean(key, config.get_value("settings", key))
	Controls.read_bindings(config)


## Pushes the values to the engine: window mode and audio bus volumes.
func apply() -> void:
	var window_mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if get_value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != window_mode and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(window_mode)
	if Engine.get_main_loop() != null and has_node("/root/Sfx"):
		get_node("/root/Sfx").apply_volumes()
