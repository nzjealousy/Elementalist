class_name TutorialGuide
extends CanvasLayer
## A checklist of the controls, shown in the training grounds. Each line ticks itself off the first
## time you do the thing (so it teaches by doing), with the key or button you have bound for it
## (the pad's while you play with a pad). Finishing the list points you to the altar.
## Steps: [id, text, action or "", check]; a step with an action is done when that action is pressed,
## a step with a check is done when the player's state says so.

const STEPS := [
	["move", "Move", "move_up", ""],
	["slash", "Slash", "attack_basic", ""],
	["dodge", "Dodge (uses stamina)", "dodge", ""],
	["spin", "Dodge, then slash: a spin", "", "spin"],
	["switch", "Switch element", "element_next", ""],
	["lock", "Lock two elements", "skill_lock", "locked2"],
	["fuse", "Fire the fusion", "skill_primary", "fused"],
	["area", "Area skill", "skill_area", ""],
	["support", "Support skill", "skill_support", ""],
	["special", "Special skill", "skill_special", ""],
	["imbue", "Imbue your weapon", "imbue", ""],
	["sheet", "Open the character sheet", "character_sheet", ""],
]

const TOP := 18.0  # below the run text, even at the largest HUD size

var _done: Dictionary = {}
var _labels: Dictionary = {}
var _title: Label
var _footer: Label
var _announced := false


func _init() -> void:
	layer = 12
	add_to_group("tutorial_guide")


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.theme = UiTheme.make()
	# Top right, under the run text: on the left it sat under the HUD's status lines and, at a large HUD size, on the
	# element slots.
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -4
	panel.offset_right = -4
	panel.offset_top = TOP
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	_title = UiKit.label("Training", UiTheme.GOLD, 7)
	box.add_child(_title)
	for step in STEPS:
		var label := UiKit.label("", UiTheme.TEXT, 6)
		box.add_child(label)
		_labels[step[0]] = label
	_footer = UiKit.label("", UiTheme.GREEN, 6)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.custom_minimum_size = Vector2(100, 0)
	box.add_child(_footer)
	_refresh()


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	for step in STEPS:
		var id: String = step[0]
		if _done.has(id):
			continue
		if _step_met(step, player):
			_done[id] = true
			Sfx.ui("ui_click")
	_refresh()


func _step_met(step: Array, player: Node) -> bool:
	var action: String = step[2]
	var check: String = step[3]
	match String(step[0]):
		"move":
			return Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.3
		"spin":
			return player.has_method("is_spinning") and player.is_spinning()
		"lock":
			return player.caster != null and player.caster.locked.size() >= 2
		"fuse":
			return player.caster != null and player.caster.fusion_ready() and Input.is_action_just_pressed("skill_primary")
	if check == "" and action != "":
		return Input.is_action_just_pressed(action)
	return false


## "Dodge (uses stamina)   Space" for a step, with the binding of the device in use.
func line_for(step: Array) -> String:
	var keys := keys_for(String(step[2]))
	return "%s %s" % [step[1], ("[%s]" % keys) if keys != "" else ""]


## The key or button bound to an action, for the device in use.
static func keys_for(action: String) -> String:
	if action == "":
		return ""
	var kind := "pad" if Controls.using_pad else "desk"
	var event := Controls.event_for(action, kind)
	if event == null:
		event = Controls.event_for(action, "desk")
	return Controls.label_of(event) if event != null else ""


func is_done(id: String) -> bool:
	return _done.has(id)


func done_count() -> int:
	return _done.size()


func _refresh() -> void:
	for step in STEPS:
		var id: String = step[0]
		var label: Label = _labels[id]
		var done := _done.has(id)
		label.text = ("x " if done else "- ") + line_for(step)
		label.add_theme_color_override("font_color", UiTheme.GREEN if done else UiTheme.TEXT)
	_title.text = "Training %d/%d" % [_done.size(), STEPS.size()]
	if _done.size() == STEPS.size():
		_footer.text = "All done! Try the altar (G) and the dummies."
		if not _announced:
			_announced = true
			Game.say("Training complete!\nThe altar compares every element.")
	else:
		_footer.text = "Hit the dummies. The altar (G) compares the elements."
