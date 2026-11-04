class_name SettingsMenu
extends CanvasLayer
## Settings, in three tabs: Audio (volume sliders), Game (window, shake, numbers, HUD size, controller
## aim) and Controls (rebind keyboard/mouse and gamepad). Used by the main menu and the pause menu.
## Every change is applied at once and saved. Esc / B / the Back button closes it.

signal closed

const TABS := ["Audio", "Game", "Controls"]

var _open := false
var _tab := 0
var _theme: Theme
var _body: VBoxContainer
var _capture: Array = []        # [action, kind] while waiting for a key press
var _capture_button: Button
var _was_paused := false


func _init() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_theme = UiTheme.make()


func is_open() -> bool:
	return _open


func open(tab: int = 0) -> void:
	_open = true
	visible = true
	_tab = tab
	_capture = []
	_build()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_capture = []
	Settings.save()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if not _capture.is_empty():
		_try_capture(event)
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	UiKit.dim(self, 0.9)
	var column := UiKit.column(self, _theme, 276.0, 3)
	column.add_child(UiTheme.heading("Settings", 10))
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(tabs)
	for i in TABS.size():
		var b := UiKit.button(TABS[i], func(): open(i), 60.0)
		b.toggle_mode = true
		b.button_pressed = i == _tab
		tabs.add_child(b)
	column.add_child(UiTheme.divider())
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	column.add_child(_body)
	match _tab:
		0: _build_audio()
		1: _build_game()
		2: _build_controls()
	column.add_child(UiTheme.divider())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	row.add_child(UiKit.button("Back", close, 70.0))
	UiKit.focus_first(tabs)


# ---------- audio ----------

func _build_audio() -> void:
	_slider("Master", "master_volume")
	_slider("Music", "music_volume")
	_slider("Effects", "sfx_volume")
	_slider("Interface", "ui_volume")


func _slider(text: String, key: String, low: float = 0.0, high: float = 1.0, shown_as_percent: bool = true) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_body.add_child(row)
	var name_label := UiKit.label(text, UiTheme.TEXT, 7)
	name_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.value = float(Settings.get_value(key))
	slider.custom_minimum_size = Vector2(110, 10)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := UiKit.label("", UiTheme.GOLD, 7)
	value_label.custom_minimum_size = Vector2(30, 0)
	row.add_child(value_label)
	var show := func(v: float) -> void:
		value_label.text = ("%d%%" % roundi(v * 100.0)) if shown_as_percent else ("%.2f" % v)
	show.call(slider.value)
	slider.value_changed.connect(func(v: float):
		show.call(v)
		Settings.set_value(key, v, false)
		if key == "sfx_volume" or key == "ui_volume":
			Sfx.ui("ui_tick"))


# ---------- game ----------

func _build_game() -> void:
	_check("Fullscreen", "fullscreen")
	_check("Damage numbers", "damage_numbers")
	_check("Tips and hints", "show_tips")
	_slider("Screen shake", "screen_shake")
	_slider("HUD size", "hud_scale", 0.75, 1.5, false)
	_slider("Aim assist (pad)", "aim_assist")
	_slider("Stick deadzone", "stick_deadzone", 0.05, 0.6, false)
	var reset := UiKit.button("Reset to defaults", func():
		Settings.reset_to_defaults()
		open(1), 110.0)
	_body.add_child(reset)


func _check(text: String, key: String) -> void:
	var box := CheckButton.new()
	box.text = text
	box.button_pressed = bool(Settings.get_value(key))
	box.focus_mode = Control.FOCUS_ALL
	box.toggled.connect(func(on: bool):
		Sfx.ui("ui_click")
		Settings.set_value(key, on, false))
	_body.add_child(box)


# ---------- controls ----------

func _build_controls() -> void:
	var hint := UiKit.label("Click a binding, then press the new key or button (Esc cancels).", UiTheme.TEXT_DIM, 6)
	_body.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 74)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var group := ""
	for row_def in Controls.ACTIONS:
		if row_def[2] != group:
			group = row_def[2]
			list.add_child(UiKit.label(group, UiTheme.GOLD_DARK, 6))
		list.add_child(_binding_row(row_def[0], row_def[1]))
	var reset := UiKit.button("Reset controls", func():
		Controls.reset_bindings()
		Settings.save()
		open(2), 90.0)
	_body.add_child(reset)


func _binding_row(action: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var name_label := UiKit.label(text, UiTheme.TEXT, 6)
	name_label.custom_minimum_size = Vector2(88, 0)
	row.add_child(name_label)
	for kind in ["desk", "pad"]:
		var button := UiKit.button(Controls.label_of(Controls.event_for(action, kind)), func(): pass, 80.0)
		button.add_theme_font_size_override("font_size", 6)
		for connection in button.pressed.get_connections():
			button.pressed.disconnect(connection["callable"])
		button.pressed.connect(_begin_capture.bind(action, kind, button))
		row.add_child(button)
	return row


func _begin_capture(action: String, kind: String, button: Button) -> void:
	_capture = [action, kind]
	_capture_button = button
	button.text = "press..."


func _try_capture(event: InputEvent) -> void:
	var action: String = _capture[0]
	var kind: String = _capture[1]
	var accepted: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_capture = []
			_capture_button.text = Controls.label_of(Controls.event_for(action, kind))
			get_viewport().set_input_as_handled()
			return
		if kind == "desk":
			accepted = event
	elif event is InputEventMouseButton and event.pressed and kind == "desk":
		accepted = event
	elif event is InputEventJoypadButton and event.pressed and kind == "pad":
		accepted = event
	elif event is InputEventJoypadMotion and kind == "pad" and absf(event.axis_value) > 0.7:
		accepted = event
	if accepted == null:
		return
	get_viewport().set_input_as_handled()
	var copy: InputEvent = accepted.duplicate()
	if copy is InputEventKey:
		copy.pressed = false  # a binding is the key itself, not a press
	var stolen := Controls.rebind(action, copy)
	_capture = []
	Settings.save()
	open(2)
	if stolen != "":
		Game.say("%s was also bound to %s; that is now unbound" % [Controls.label_of(copy), stolen.replace("_", " ")])
