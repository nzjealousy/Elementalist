class_name MainMenu
extends Node
## The title screen. Views: the main list (Continue, New game, Hall of heroes, Settings, Quit), a
## save-slot list for Continue / New game, and the difficulty choice for a new hero.
## Everything is built in code from UiKit, so a gamepad or the keyboard can drive it all.

const SLOT_WIDTH := 250.0

var _theme: Theme
var _layer: CanvasLayer
var _view: Control
var _settings: SettingsMenu
var _board: LeaderboardScreen
var _multiplayer: MultiplayerMenu
var _confirm := ""   # "slot<N>" or "delete<N>": a risky button waiting for its second press
var _pending_slot := -1
var _back := Callable()  # what Esc / pad B does in the view shown (nothing on the main list)


func _ready() -> void:
	_theme = UiTheme.make()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_backdrop()
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_settings = SettingsMenu.new()
	add_child(_settings)
	_settings.closed.connect(show_main)
	_board = LeaderboardScreen.new()
	add_child(_board)
	_board.closed.connect(show_main)
	_multiplayer = MultiplayerMenu.new()
	add_child(_multiplayer)
	_multiplayer.closed.connect(show_main)
	Sfx.music("menu")
	show_main()


func _build_backdrop() -> void:
	var back := CanvasLayer.new()
	back.layer = -5
	add_child(back)
	var gradient := Gradient.new()
	gradient.set_color(0, Color("0a0618"))
	gradient.set_color(1, Color("1c1838"))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 8
	texture.height = 64
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.add_child(rect)
	# Rising embers.
	var embers := CPUParticles2D.new()
	embers.position = Vector2(160, 190)
	embers.amount = 48
	embers.lifetime = 7.0
	embers.preprocess = 7.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(170, 2)
	embers.direction = Vector2(0.15, -1.0)
	embers.spread = 20.0
	embers.gravity = Vector2.ZERO
	embers.initial_velocity_min = 8.0
	embers.initial_velocity_max = 26.0
	embers.scale_amount_min = 0.6
	embers.scale_amount_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color("cfc8ff"))
	fade.set_color(1, Color(0.4, 0.35, 1.0, 0.0))
	embers.color_ramp = fade
	back.add_child(embers)


func _unhandled_input(event: InputEvent) -> void:
	if _back.is_valid() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")) and not _settings.is_open() and not _board.is_open() and not _multiplayer.is_open():
		get_viewport().set_input_as_handled()
		_back.call()


func _clear_view() -> VBoxContainer:
	_back = Callable()
	if _view:
		_view.queue_free()
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(holder)
	_view = holder
	return UiKit.column(holder, _theme, 120.0, 3)


func _title(column: VBoxContainer) -> void:
	var title := UiKit.label("ELEMENTALIST", UiTheme.GOLD, 16, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_outline_color", Color("0a0618"))
	title.add_theme_constant_override("outline_size", 3)
	column.add_child(title)
	column.add_child(UiKit.label("Elements come from the world. Skills are learned.", UiTheme.TEXT_DIM, 6, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiTheme.divider())


# ---------- the main list ----------

func show_main() -> void:
	_confirm = ""
	var column := _clear_view()
	_title(column)
	var buttons: Array = []
	var any_save := false
	for slot in SaveStore.SLOTS:
		any_save = any_save or SaveStore.exists(slot)
	var continue_button := UiKit.button("Continue", func(): show_slots("continue"), 110.0)
	continue_button.disabled = not any_save
	buttons.append(continue_button)
	buttons.append(UiKit.button("New game", func(): show_slots("new"), 110.0))
	buttons.append(UiKit.button("Multiplayer", func(): _multiplayer.open(), 110.0))
	buttons.append(UiKit.button("Hall of heroes", func(): _board.open(), 110.0))
	buttons.append(UiKit.button("Settings", func(): _settings.open(0), 110.0))
	buttons.append(UiKit.button("Quit", func(): get_tree().quit(), 110.0))
	for b in buttons:
		column.add_child(b)
	UiKit.wrap_focus(buttons.filter(func(b): return not b.disabled))
	UiKit.focus_first(column)
	var hint := UiKit.label("Gamepad: stick + A    Keyboard: arrows + Enter", UiTheme.TEXT_DIM, 5, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(hint)


# ---------- slots ----------

func show_slots(purpose: String) -> void:
	var column := _clear_view()
	column.custom_minimum_size = Vector2(SLOT_WIDTH, 0)
	column.add_child(UiTheme.heading("Choose a save slot" if purpose == "new" else "Continue which hero?", 9))
	column.add_child(UiTheme.divider())
	var buttons: Array = []
	for slot in SaveStore.SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		var info := SaveStore.summary(slot)
		var text := "Slot %d\n(empty)" % (slot + 1)
		if not info.is_empty():
			text = "Slot %d  %s, %s, level %d\n%s  -  %s  -  %d runs" % [slot + 1, info["name"], info["class"], info["level"],
				info["where"], String(Game.DIFFICULTIES.get(info["difficulty"], Game.DIFFICULTIES["knight"])["name"]), info["runs"]]
		var button := UiKit.button(text, _slot_pressed.bind(purpose, slot, not info.is_empty()), SLOT_WIDTH - 28.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if purpose == "continue" and info.is_empty():
			button.disabled = true
		if _confirm == "slot%d" % slot:
			button.text = "Slot %d: this hero will be lost. Press again to overwrite." % (slot + 1)
		row.add_child(button)
		var delete := UiKit.button("X" if _confirm != "delete%d" % slot else "?", _delete_pressed.bind(purpose, slot), 20.0)
		delete.disabled = info.is_empty()
		row.add_child(delete)
		column.add_child(row)
		buttons.append(button)
	var back := UiKit.button("Back", show_main, 70.0)
	column.add_child(back)
	_back = show_main
	UiKit.focus_first(column)


func _slot_pressed(purpose: String, slot: int, filled: bool) -> void:
	if purpose == "continue":
		if not Game.continue_game(slot):
			Game.say("That save could not be read")
		return
	if filled and _confirm != "slot%d" % slot:
		_confirm = "slot%d" % slot
		show_slots(purpose)
		return
	_pending_slot = slot
	show_difficulty()


func _delete_pressed(purpose: String, slot: int) -> void:
	if _confirm != "delete%d" % slot:
		_confirm = "delete%d" % slot
		show_slots(purpose)
		return
	SaveStore.delete_slot(slot)
	_confirm = ""
	show_slots(purpose)


# ---------- difficulty ----------

func show_difficulty() -> void:
	var column := _clear_view()
	column.add_child(UiTheme.heading("Swear your oath", 10))
	column.add_child(UiKit.label("The harder the oath, the richer the spoils. You cannot change it later.", UiTheme.TEXT_DIM, 6, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiTheme.divider())
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	column.add_child(cards)
	for id in Game.DIFFICULTIES:
		var spec: Dictionary = Game.DIFFICULTIES[id]
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(82, 0)
		box.add_child(UiKit.label(String(spec["name"]), UiTheme.GOLD, 8, HORIZONTAL_ALIGNMENT_CENTER))
		var desc := UiKit.label(String(spec["desc"]), UiTheme.TEXT, 6, HORIZONTAL_ALIGNMENT_CENTER)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(82, 36)
		box.add_child(desc)
		box.add_child(UiKit.label("Monsters x%.1f   Spoils x%.1f" % [spec["hardness"], spec["reward"]], UiTheme.TEXT_DIM, 5, HORIZONTAL_ALIGNMENT_CENTER))
		var pick := UiKit.button("Swear", func(): Game.new_game(_pending_slot, id), 80.0)
		box.add_child(pick)
		cards.add_child(box)
	var back := UiKit.button("Back", func(): show_slots("new"), 70.0)
	column.add_child(back)
	_back = show_slots.bind("new")
	UiKit.focus_first(cards)
	# The knight (the intended game) starts focused.
	for node in cards.get_children():
		if node.get_child_count() > 0 and (node.get_child(0) as Label).text == "Knight":
			(node.get_child(node.get_child_count() - 1) as Control).grab_focus.call_deferred()
