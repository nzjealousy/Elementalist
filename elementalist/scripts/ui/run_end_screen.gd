class_name RunEndScreen
extends CanvasLayer
## Shown when a dungeon run ends: a victory after the boss, or a defeat. Pauses the game; Enter
## (or the button) starts a new dungeon with the same character.

var _open := false
var _theme: Theme


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_theme = UiTheme.make()


func _exit_tree() -> void:
	if _open:
		get_tree().paused = false


func is_open() -> bool:
	return _open


## `lines` are the run's summary, one per row.
func show_result(won: bool, lines: Array) -> void:
	_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for child in get_children():
		child.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.theme = _theme
	column.add_theme_constant_override("separation", 4)
	center.add_child(column)
	var title := _label("Dungeon cleared!" if won else "You fell", Color("ffd84a") if won else Color("ff7a7a"), 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	for line in lines:
		var row := _label(String(line), Color.WHITE, 7)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(row)
	var button := Button.new()
	button.text = "New dungeon (Enter)"
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(restart)
	column.add_child(button)


func _input(event: InputEvent) -> void:
	if _open and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		restart()
		get_viewport().set_input_as_handled()


func restart() -> void:
	_open = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label
