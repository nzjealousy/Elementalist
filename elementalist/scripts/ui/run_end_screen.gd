class_name RunEndScreen
extends CanvasLayer
## Shown when a dungeon run ends: a victory after the boss, or a defeat. Pauses the game; Enter
## (or the button) returns to camp, or to the main menu if the hero died for good.

var _open := false
var _final := false  # the character is gone for good: the button starts a new character instead
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


## `lines` are the run's summary, one per row. `final` means the character died for good.
func show_result(won: bool, lines: Array, final: bool = false) -> void:
	_final = final
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
	var title_text := "Dungeon cleared!" if won else ("You died" if final else "You fell")
	var title := _label(title_text, Color("ffd84a") if won else Color("ff7a7a"), 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	for line in lines:
		var row := _label(String(line), Color.WHITE, 7)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(row)
	var button := Button.new()
	button.text = "Main menu (Enter)" if final else ("Return to camp (Enter)" if Game.slot >= 0 else "New dungeon (Enter)")
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(110, 0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(restart)
	column.add_child(button)
	# Pad A presses it once focused (this screen has no other way out, on purpose). Not at once: A and Space also dodge,
	# and a player mashing them as the run ends would skip the summary.
	get_tree().create_timer(0.6, true, false, true).timeout.connect(func():
		if _open and is_instance_valid(button):
			button.grab_focus())


func _input(event: InputEvent) -> void:
	if _open and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()  # before the restart: the reload removes this node (and its viewport)
		restart()


func restart() -> void:
	_open = false
	get_tree().paused = false
	if _final:
		Game.go_to_menu()          # the hero is gone (the save is already deleted); start another from the menu
	elif Game.slot >= 0:
		Game.return_to_camp()      # saves, then rebuilds the scene as the camp
	else:
		get_tree().reload_current_scene()  # sandbox and tests: a fresh dungeon


func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label
