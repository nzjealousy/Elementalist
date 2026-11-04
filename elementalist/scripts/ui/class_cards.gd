class_name ClassCards
extends CanvasLayer
## Class and subclass choice as cards, in the middle of the screen (the game pauses).
##   class     opens when a Novice reaches level 3: every class is a card (click, or press 1-8)
##   subclass  opens when class mastery reaches Classes.SUBCLASS_MASTERY: the class's subclasses
## Esc postpones; the character sheet's stats tab can open the cards again any time.

const OPEN_DELAY := 0.7
const CLASS_CARD := Vector2(72, 62)
const SUBCLASS_CARD := Vector2(124, 84)
const COLUMNS := 4
const STYLE_COLORS := {"melee": Color("ff9a5a"), "ranged": Color("6fb8ff")}

var mode := ""
var _open := false
var _was_paused := false
var _theme: Theme
var _detail: Label


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("class_cards")
	_theme = UiTheme.make()
	var character := Game.character
	character.class_available.connect(_open_soon.bind("class"))
	character.subclass_available.connect(_open_soon.bind("subclass"))
	if character.can_choose_class():
		_open_soon("class")  # already waiting when the scene starts
	elif not character.available_subclasses().is_empty():
		_open_soon("subclass")


func _exit_tree() -> void:
	if _open:
		get_tree().paused = _was_paused


func is_open() -> bool:
	return _open


## Waits a moment (and for any other menu to close), then shows the cards if still needed.
func _open_soon(wanted: String) -> void:
	await get_tree().create_timer(OPEN_DELAY, true, false, true).timeout
	while get_tree().paused and not _open:
		await get_tree().create_timer(0.5, true, false, true).timeout
	if not _open and _applies(wanted):
		open(wanted)


## Whether there is still something to choose in that mode.
func _applies(wanted: String) -> bool:
	if wanted == "class":
		return Game.character.can_choose_class()
	return not Game.character.available_subclasses().is_empty()


func open(wanted: String) -> void:
	if _open or not _applies(wanted):
		return
	mode = wanted
	_open = true
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()


func close() -> void:
	_open = false
	visible = false
	get_tree().paused = _was_paused
	var in_game := get_tree().get_first_node_in_group("player") != null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (_was_paused or not in_game) else Input.MOUSE_MODE_HIDDEN


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("pause"):
		close()  # decide later
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var index: int = int(event.keycode) - int(KEY_1)
		if index >= 0 and index < _entries().size():
			_choose(index)
			get_viewport().set_input_as_handled()


## The ids on offer, in card order.
func _entries() -> Array:
	if mode == "class":
		return Classes.playable()
	return Game.character.available_subclasses()


func card_count() -> int:
	return _entries().size()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.theme = _theme
	column.add_theme_constant_override("separation", 4)
	center.add_child(column)

	var title := _label("Choose your class" if mode == "class" else "Choose a subclass for your %s" % Classes.CLASSES[Game.character.class_id]["name"], Color("ffd84a"), 9)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var grid := GridContainer.new()
	grid.columns = COLUMNS if mode == "class" else 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	var entries := _entries()
	for i in entries.size():
		grid.add_child(_card(String(entries[i]), i))
	_detail = _label("", Color(0.85, 0.88, 0.95), 6)
	_detail.custom_minimum_size = Vector2(300, 14)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_detail)
	var keys := "1-%d" % entries.size()
	var hint := _label("Click a card or press %s    Esc: decide later" % keys, Color(1, 1, 1, 0.6), 6)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _card(id: String, index: int) -> Control:
	var panel := PanelContainer.new()
	panel.theme = _theme
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var color := Color("b6ff8a")
	var info := ""
	var name_text := ""
	var lines: Array[String] = []
	if mode == "class":
		var cls: Dictionary = Classes.CLASSES[id]
		color = STYLE_COLORS.get(Classes.style_of(id), Color.WHITE)
		name_text = String(cls["name"])
		lines.append("%s - %s" % [String(cls["style"]).capitalize(), String(cls["weapon"]).capitalize()])
		lines.append(String(cls.get("tag", "")))
		info = "%s  Passive: %s.  Subclasses: %s" % [cls["desc"], Classes.passive_info(cls["passives"][0])["desc"], ", ".join(cls["subclasses"].map(func(s): return Classes.SUBCLASSES[s]["name"]))]
		panel.custom_minimum_size = CLASS_CARD
	else:
		var sub: Dictionary = Classes.SUBCLASSES[id]
		name_text = String(sub["name"])
		lines.append(String(sub["desc"]))
		lines.append("Passive: %s" % Classes.passive_info(sub["passives"][0])["name"])
		info = String(sub["desc"])
		panel.custom_minimum_size = SUBCLASS_CARD
	var box := UiTheme.frame("panel", 8, 4)  # the gold frame, tinted by melee (orange) or ranged (blue)
	var tint := Color.WHITE.lerp(color, 0.5)
	if box is StyleBoxTexture:
		box.modulate_color = tint
	panel.add_theme_stylebox_override("panel", box)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	panel.add_child(content)
	var header := _label("%d  %s" % [index + 1, name_text], color, 7)
	header.autowrap_mode = TextServer.AUTOWRAP_OFF
	content.add_child(header)
	for line in lines:
		content.add_child(_label(line, Color(0.85, 0.88, 0.95), 5))
	panel.mouse_entered.connect(func():
		_detail.text = info
		if box is StyleBoxTexture:
			box.modulate_color = tint.lightened(0.35))
	panel.mouse_exited.connect(func():
		if box is StyleBoxTexture:
			box.modulate_color = tint)
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_choose(index))
	return panel


func _choose(index: int) -> void:
	var entries := _entries()
	if index < 0 or index >= entries.size():
		return
	var id := String(entries[index])
	if mode == "class":
		Game.character.choose_class(id)
	else:
		Game.character.choose_subclass(id)
	close()


func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
