class_name NewCharacterMenu
extends CanvasLayer
## New character screen (N, Esc to close): pick a class and how the character comes into the
## world, then Begin restarts the arena with that character. Pauses the game while open.
## This stands in for the full character creation of the story phase.

const BIRTHS := [
	{"id": CharacterData.ELEMENTALIST, "name": "Ceremony",
		"desc": "Roll your elements at the coming-of-age ceremony. 8% are born with none and become attunable."},
	{"id": CharacterData.ATTUNABLE, "name": "No element",
		"desc": "Born without elements. Learns martial skills, tends to have more traits, and can be attuned to elements later (items, story)."},
	{"id": CharacterData.SEALED, "name": "Sealed",
		"desc": "Can never hold elements. Learns martial skills and tends to have more traits."},
]

var _open := false
var _class_id := Classes.NEUTRAL_CLASS
var _birth: String = CharacterData.ELEMENTALIST
var _theme: Theme
var _description: Label
var _hero_name := ""
var _name_edit: LineEdit


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_theme = UiTheme.make()
	_hero_name = Game.random_name()  # a suggestion; type over it


func _exit_tree() -> void:
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("new_character") and Game.slot >= 0 and not Game.creation_required:
		return  # a saved hero cannot be rerolled; N is for the sandbox and tests
	if _open and event.is_action_pressed("pause") and Game.creation_required:
		get_viewport().set_input_as_handled()  # a new hero must be made before anything else
		return
	if event.is_action_pressed("new_character") or (_open and event.is_action_pressed("pause")):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_open = not _open
	visible = _open
	get_tree().paused = _open
	var in_game := get_tree().get_first_node_in_group("player") != null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (_open or not in_game) else Input.MOUSE_MODE_HIDDEN
	if _open:
		_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	var panel := PanelContainer.new()
	panel.theme = _theme
	panel.position = Vector2(30, 6)
	panel.custom_minimum_size = Vector2(260, 150)
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	panel.add_child(root)

	root.add_child(_label("New character   (Esc to cancel)", Color("ffd84a")))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 3)
	root.add_child(name_row)
	name_row.add_child(_label("Name"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = Game.NAME_MAX
	_name_edit.placeholder_text = "Your hero's name"
	_name_edit.text = _hero_name
	_name_edit.custom_minimum_size = Vector2(110, 0)
	_name_edit.text_changed.connect(func(text: String): _hero_name = text)
	_name_edit.text_submitted.connect(func(_text: String): _name_edit.release_focus())
	name_row.add_child(_name_edit)
	var dice := Button.new()
	dice.text = "Random"
	dice.focus_mode = Control.FOCUS_NONE
	dice.pressed.connect(func():
		_hero_name = Game.random_name()
		_name_edit.text = _hero_name)
	name_row.add_child(dice)
	root.add_child(_label("Class  (everyone normally starts as a Novice; pick one to skip ahead for testing)"))
	var class_row := GridContainer.new()
	class_row.columns = 5
	root.add_child(class_row)
	var class_group := ButtonGroup.new()
	class_row.add_child(_choice("Novice", class_group, _class_id == Classes.NEUTRAL_CLASS, _pick_class.bind(Classes.NEUTRAL_CLASS)))
	for id in Classes.playable():
		class_row.add_child(_choice(String(Classes.CLASSES[id]["name"]), class_group, id == _class_id, _pick_class.bind(id)))

	root.add_child(_label("Birth"))
	var birth_row := HBoxContainer.new()
	root.add_child(birth_row)
	var birth_group := ButtonGroup.new()
	for birth in BIRTHS:
		birth_row.add_child(_choice(String(birth["name"]), birth_group, birth["id"] == _birth, _pick_birth.bind(birth["id"])))

	_description = _label("", Color(0.8, 0.85, 1.0))
	_description.custom_minimum_size = Vector2(240, 44)
	root.add_child(_description)
	_refresh_description()

	var begin := Button.new()
	begin.focus_mode = Control.FOCUS_NONE
	begin.text = "Begin"
	begin.pressed.connect(_begin)
	root.add_child(begin)


func _choice(text: String, group: ButtonGroup, selected: bool, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = selected
	button.pressed.connect(callback)
	return button


func _pick_class(id: String) -> void:
	_class_id = id
	_refresh_description()


func _pick_birth(id: String) -> void:
	_birth = id
	_refresh_description()


func _refresh_description() -> void:
	var cls: Dictionary = Classes.CLASSES[_class_id]
	var birth_desc := ""
	for birth in BIRTHS:
		if birth["id"] == _birth:
			birth_desc = birth["desc"]
	var base: Dictionary = cls["base"]
	var stats: Array[String] = []
	for attr in Classes.ATTRIBUTES:
		stats.append("%s %d" % [Classes.ATTRIBUTE_SHORT[attr], base[attr]])
	_description.text = "%s\n%s\n%s" % [cls["desc"], "  ".join(stats), birth_desc]


func _begin() -> void:
	Game.start_new(_class_id, _birth, _hero_name)
	Game.creation_required = false
	Game.save_game()  # (does nothing without a save slot)
	_open = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func _label(text: String, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
