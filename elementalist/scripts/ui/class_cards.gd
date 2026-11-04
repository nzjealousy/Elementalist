class_name ClassCards
extends CanvasLayer
## Class and subclass choice as cards, in the middle of the screen (the game pauses).
##   class     opens when a Novice reaches level 3: every class is a card (click, or press 1-8)
##   subclass  opens when class mastery reaches Classes.SUBCLASS_MASTERY: the class's subclasses
## Esc postpones; the character sheet's stats tab can open the cards again any time.

const OPEN_DELAY := 0.7
const CLASS_CARD := Vector2(36, 84)
const SUBCLASS_CARD := Vector2(120, 104)
const STYLE_COLORS := {"melee": Color("ff9a5a"), "ranged": Color("6fb8ff")}

var mode := ""
var _open := false
var _was_paused := false
var _theme: Theme
var _detail: Label
var _frames: Array[CardFrame] = []
var _infos: Array[String] = []
var _hot := 0


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
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_set_hot(posmod(_hot + (1 if event.is_action_pressed("ui_right") else -1), maxi(_entries().size(), 1)))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_choose(_hot)
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
	_frames.clear()
	_infos.clear()
	_hot = 0
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.theme = _theme
	column.add_theme_constant_override("separation", 4)
	center.add_child(column)

	var title := _label("Choose your class" if mode == "class" else "Choose a subclass for your %s" % Classes.CLASSES[Game.character.class_id]["name"], Color("ffd84a"), 9)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3 if mode == "class" else 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	var entries := _entries()
	for i in entries.size():
		row.add_child(_card(String(entries[i]), i))
	_detail = _label("", Color(0.85, 0.88, 0.95), 6)
	_detail.custom_minimum_size = Vector2(290, 26)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_detail)
	var keys := "1-%d" % entries.size()
	var hint := _label("Click a card or press %s    Left/Right + Enter on a pad    Esc: decide later" % keys, Color(1, 1, 1, 0.6), 6)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	_set_hot(0)


## One card: a framed picture of the hero in the middle with the name under it. A class card is
## narrow (all eight fit in a row) and wears its own border; a subclass card is wide and carries the description.
func _card(id: String, index: int) -> Control:
	var is_class := mode == "class"
	var class_id := id if is_class else Game.character.class_id
	var look := HeroLook.for_class(class_id, "" if is_class else id, Game.character.look_skin, Game.character.look_hair)
	var card_size := CLASS_CARD if is_class else SUBCLASS_CARD
	var holder := Control.new()
	holder.custom_minimum_size = card_size
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := CardFrame.for_class(class_id)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(frame)
	_frames.append(frame)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 3
	content.offset_right = -3
	content.offset_top = 5
	content.offset_bottom = -3
	content.add_theme_constant_override("separation", 1)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(content)
	var picture := HeroDoll.make(look, 2)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(picture)
	var info := ""
	var lines: Array[String] = []
	var name_text := ""
	if is_class:
		var cls: Dictionary = Classes.CLASSES[id]
		name_text = String(cls["name"])
		lines.append(String(cls["style"]).capitalize())
		lines.append(String(cls["weapon"]).capitalize())
		info = "%s (%s)\n%s  Passive: %s.  Subclasses: %s" % [name_text, String(cls.get("tag", "")).trim_suffix("."), cls["desc"], Classes.passive_info(cls["passives"][0])["desc"], ", ".join(cls["subclasses"].map(func(s): return Classes.SUBCLASSES[s]["name"]))]
	else:
		var sub: Dictionary = Classes.SUBCLASSES[id]
		name_text = String(sub["name"])
		lines.append(String(sub["desc"]))
		lines.append("Passive: %s" % Classes.passive_info(sub["passives"][0])["name"])
		info = String(sub["desc"])
	var name_label := _label(name_text, _frame_color(class_id), 6 if is_class else 8)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(name_label)
	for line in lines:
		var label := _label(line, Color(0.85, 0.88, 0.95) if not is_class else STYLE_COLORS.get(Classes.style_of(id), Color.WHITE), 5)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if is_class:
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
		content.add_child(label)
	var number := _label(str(index + 1), Color(1, 1, 1, 0.45), 5)
	number.position = Vector2(4, 4)
	holder.add_child(number)

	holder.mouse_entered.connect(func(): _set_hot(index))
	holder.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_choose(index))
	_infos.append(info)
	return holder


func _frame_color(class_id: String) -> Color:
	return HeroLook.class_color(class_id).lerp(HeroLook.class_trim(class_id), 0.4).lerp(Color.WHITE, 0.45)


## Highlights card `index` (mouse, keys or pad) and shows its full description.
func _set_hot(index: int) -> void:
	_hot = index
	for i in _frames.size():
		_frames[i].hot = i == index
	if _detail and index >= 0 and index < _infos.size():
		_detail.text = _infos[index]


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
