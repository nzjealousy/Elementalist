extends Node
## Input in one place (autoload "Controls"): gamepad bindings, rebinding, and where the player aims.
##
## Keyboard and mouse defaults come from project.godot's input map; the gamepad defaults are added
## here at start-up so the project file stays small. Rebinds are saved by Settings (the
## [bindings] section of settings.cfg: plain numbers, nothing executable).
##
## Aim: with the mouse, the aim point is the cursor. As soon as a gamepad is touched (and until the
## mouse or keyboard is used again) it is the right stick, a point AIM_REACH in front of the player,
## pulled toward the nearest enemy by the aim-assist setting.

signal device_changed(using_pad: bool)

const AIM_REACH := 70.0
const ASSIST_CONE := 0.35  # radians either side of the stick direction that aim assist considers
const ASSIST_RANGE := 150.0

## Actions the controls screen lists, in order: [action, label, group].
const ACTIONS := [
	["move_up", "Move up", "Movement"], ["move_down", "Move down", "Movement"],
	["move_left", "Move left", "Movement"], ["move_right", "Move right", "Movement"],
	["dodge", "Dodge", "Movement"],
	["skill_primary", "Fuse / main attack", "Combat"], ["attack_basic", "Slash / bolt", "Combat"],
	["skill_lock", "Lock elements (Q)", "Combat"], ["skill_area", "Area skill", "Combat"],
	["skill_support", "Support skill", "Combat"], ["skill_special", "Special skill", "Combat"],
	["imbue", "Imbue weapon", "Combat"],
	["element_prev", "Previous element", "Elements"], ["element_next", "Next element", "Elements"],
	["element_1", "Element 1", "Elements"], ["element_2", "Element 2", "Elements"],
	["element_3", "Element 3", "Elements"], ["element_4", "Element 4", "Elements"],
	["element_5", "Element 5", "Elements"],
	["interact", "Interact", "Menus"], ["inventory", "Gear", "Menus"],
	["character_sheet", "Character sheet", "Menus"], ["pause", "Pause / back", "Menus"],
]

## Gamepad defaults: action -> [kind, index (, axis sign)]. "b" is a button, "a" a stick or trigger axis.
const PAD_DEFAULTS := {
	"move_left": ["a", JOY_AXIS_LEFT_X, -1.0], "move_right": ["a", JOY_AXIS_LEFT_X, 1.0],
	"move_up": ["a", JOY_AXIS_LEFT_Y, -1.0], "move_down": ["a", JOY_AXIS_LEFT_Y, 1.0],
	"aim_left": ["a", JOY_AXIS_RIGHT_X, -1.0], "aim_right": ["a", JOY_AXIS_RIGHT_X, 1.0],
	"aim_up": ["a", JOY_AXIS_RIGHT_Y, -1.0], "aim_down": ["a", JOY_AXIS_RIGHT_Y, 1.0],
	"dodge": ["b", JOY_BUTTON_A], "skill_special": ["b", JOY_BUTTON_B],
	"skill_area": ["b", JOY_BUTTON_X], "skill_support": ["b", JOY_BUTTON_Y],
	"skill_lock": ["b", JOY_BUTTON_LEFT_SHOULDER], "attack_basic": ["b", JOY_BUTTON_RIGHT_SHOULDER],
	"skill_primary": ["a", JOY_AXIS_TRIGGER_RIGHT, 1.0], "interact": ["a", JOY_AXIS_TRIGGER_LEFT, 1.0],
	"element_prev": ["b", JOY_BUTTON_DPAD_LEFT], "element_next": ["b", JOY_BUTTON_DPAD_RIGHT],
	"inventory": ["b", JOY_BUTTON_DPAD_UP], "imbue": ["b", JOY_BUTTON_DPAD_DOWN],
	"character_sheet": ["b", JOY_BUTTON_BACK], "pause": ["b", JOY_BUTTON_START],
}

var using_pad := false
var _defaults: Dictionary = {}   # action -> Array[InputEvent] as shipped (for "reset")
var _aim_dir := Vector2.RIGHT    # last stick direction, kept while the stick rests


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in ["aim_left", "aim_right", "aim_up", "aim_down"]:
		if not InputMap.has_action(name):
			InputMap.add_action(name, 0.2)
	for action in PAD_DEFAULTS:
		if InputMap.has_action(action):
			_add_pad_default(action)
	for action in InputMap.get_actions():
		_defaults[action] = InputMap.action_get_events(action).duplicate()


func _add_pad_default(action: StringName) -> void:
	var spec: Array = PAD_DEFAULTS[action]
	if spec[0] == "b":
		var button := InputEventJoypadButton.new()
		button.button_index = spec[1]
		InputMap.action_add_event(action, button)
	else:
		var motion := InputEventJoypadMotion.new()
		motion.axis = spec[1]
		motion.axis_value = spec[2]
		InputMap.action_add_event(action, motion)


func _input(event: InputEvent) -> void:
	var pad: bool = event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5)
	var desk: bool = (event is InputEventMouseMotion and event.relative.length() > 1.0) or event is InputEventKey or event is InputEventMouseButton
	if pad and not using_pad:
		using_pad = true
		device_changed.emit(true)
	elif desk and using_pad:
		using_pad = false
		device_changed.emit(false)


# ---------- aiming ----------

## The stick direction (right stick), or the last one if the stick rests.
func stick_aim() -> Vector2:
	var raw := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", float(Settings.get_value("stick_deadzone")))
	if raw.length() > 0.1:
		_aim_dir = raw.normalized()
	return _aim_dir


## The world point the player is aiming at. `origin` is the player's position, `canvas_item` any
## node in the world (for the mouse position).
func aim_point(canvas_item: CanvasItem, origin: Vector2) -> Vector2:
	if not using_pad:
		return canvas_item.get_global_mouse_position()
	var dir := stick_aim()
	var assist := float(Settings.get_value("aim_assist"))
	if assist > 0.0:
		var best: Node2D = null
		var best_score := INF
		for node in canvas_item.get_tree().get_nodes_in_group("enemies"):
			if not (node is Node2D) or node.is_queued_for_deletion():
				continue
			var offset: Vector2 = node.global_position - origin
			var distance := offset.length()
			if distance < 4.0 or distance > ASSIST_RANGE:
				continue
			var angle := absf(dir.angle_to(offset))
			if angle < ASSIST_CONE and angle * 60.0 + distance < best_score:
				best_score = angle * 60.0 + distance
				best = node
		if best != null:
			dir = dir.slerp((best.global_position - origin).normalized(), assist).normalized()
	return origin + dir * AIM_REACH


# ---------- rebinding ----------

## The first event of that device kind bound to an action ("pad" or "desk"), or null.
func event_for(action: StringName, kind: String) -> InputEvent:
	for event in InputMap.action_get_events(action):
		if _is_pad(event) == (kind == "pad"):
			return event
	return null


static func _is_pad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


## Replaces the action's binding of the same device kind. Returns the action that lost the key
## (it is unbound there: one input does one thing) or "".
func rebind(action: StringName, event: InputEvent) -> String:
	var kind := "pad" if _is_pad(event) else "desk"
	var stolen := ""
	for other in InputMap.get_actions():
		if String(other).begins_with("ui_") or other == action:
			continue
		for existing in InputMap.action_get_events(other):
			if _is_pad(existing) == _is_pad(event) and _same_input(existing, event) and _listed(other):
				InputMap.action_erase_event(other, existing)
				stolen = String(other)
	var old := event_for(action, kind)
	while old != null:
		InputMap.action_erase_event(action, old)
		old = event_for(action, kind)
	InputMap.action_add_event(action, event)
	return stolen


func _listed(action: StringName) -> bool:
	return ACTIONS.any(func(row): return row[0] == String(action))


static func _same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.keycode == b.keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return a.axis == b.axis and signf(a.axis_value) == signf(b.axis_value)
	return false


func reset_bindings() -> void:
	for action in _defaults:
		InputMap.action_erase_events(action)
		for event in _defaults[action]:
			InputMap.action_add_event(action, event)


## Short text for a binding: "W", "Mouse 1", "Pad A", "L stick left" ...
func label_of(event: InputEvent) -> String:
	if event == null:
		return "-"
	if event is InputEventKey:
		return OS.get_keycode_string(event.keycode if event.keycode != 0 else event.physical_keycode)
	if event is InputEventMouseButton:
		return "Mouse %d" % event.button_index
	if event is InputEventJoypadButton:
		return "Pad " + _BUTTON_NAMES.get(event.button_index, str(event.button_index))
	if event is InputEventJoypadMotion:
		return "Pad " + _axis_label(event.axis, event.axis_value)
	return "?"


const _BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-up", JOY_BUTTON_DPAD_DOWN: "D-down", JOY_BUTTON_DPAD_LEFT: "D-left", JOY_BUTTON_DPAD_RIGHT: "D-right",
}


static func _axis_label(axis: int, value: float) -> String:
	match axis:
		JOY_AXIS_LEFT_X: return "L stick " + ("left" if value < 0.0 else "right")
		JOY_AXIS_LEFT_Y: return "L stick " + ("up" if value < 0.0 else "down")
		JOY_AXIS_RIGHT_X: return "R stick " + ("left" if value < 0.0 else "right")
		JOY_AXIS_RIGHT_Y: return "R stick " + ("up" if value < 0.0 else "down")
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
	return "axis %d" % axis


# ---------- persistence (Settings calls these) ----------

func write_bindings(config: ConfigFile) -> void:
	for row in ACTIONS:
		var action: String = row[0]
		var list: Array = []
		for event in InputMap.action_get_events(action):
			var entry := _to_entry(event)
			if not entry.is_empty():
				list.append(entry)
		config.set_value("bindings", action, list)


func read_bindings(config: ConfigFile) -> void:
	if not config.has_section("bindings"):
		return
	for row in ACTIONS:
		var action: String = row[0]
		if not config.has_section_key("bindings", action) or not InputMap.has_action(action):
			continue
		var saved: Variant = config.get_value("bindings", action)
		if not (saved is Array):
			continue
		var events: Array[InputEvent] = []
		for entry in saved:
			var event := _from_entry(entry)
			if event != null:
				events.append(event)
		if events.is_empty():
			continue  # an unusable entry never leaves an action unbound
		InputMap.action_erase_events(action)
		for event in events:
			InputMap.action_add_event(action, event)


static func _to_entry(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"t": "key", "c": int(event.keycode if event.keycode != 0 else event.physical_keycode)}
	if event is InputEventMouseButton:
		return {"t": "mouse", "b": int(event.button_index)}
	if event is InputEventJoypadButton:
		return {"t": "jb", "b": int(event.button_index)}
	if event is InputEventJoypadMotion:
		return {"t": "ja", "a": int(event.axis), "v": float(event.axis_value)}
	return {}


static func _from_entry(entry: Variant) -> InputEvent:
	if not (entry is Dictionary):
		return null
	match String(entry.get("t", "")):
		"key":
			var key := InputEventKey.new()
			key.keycode = int(entry.get("c", 0)) as Key
			return key if key.keycode != 0 else null
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(entry.get("b", 0)) as MouseButton
			return mouse if mouse.button_index != 0 else null
		"jb":
			var button := InputEventJoypadButton.new()
			button.button_index = int(entry.get("b", 0)) as JoyButton
			return button
		"ja":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(entry.get("a", 0)) as JoyAxis
			motion.axis_value = 1.0 if float(entry.get("v", 1.0)) >= 0.0 else -1.0
			return motion
	return null
