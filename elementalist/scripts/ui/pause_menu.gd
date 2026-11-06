class_name PauseMenu
extends CanvasLayer
## The pause menu (Esc / Start): resume, settings, the hall of heroes, and the ways out - save and
## leave for the main menu, retreat from a dungeon to camp (costs the run and a share of gold;
## the run's loot is kept), or quit. It opens only when nothing else is open and the game is running.

var _open := false
var _theme: Theme
var _settings: SettingsMenu
var _confirm := ""   # which dangerous button was pressed once ("retreat"), waiting for a second press
var _resume_buttons: Array = []


func _init() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("pause_menu")


func _ready() -> void:
	_theme = UiTheme.make()
	_settings = SettingsMenu.new()
	add_child(_settings)
	_settings.closed.connect(_build)


func _exit_tree() -> void:
	if _open:
		get_tree().paused = false


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if _open and not _settings.is_open() and event.is_action_pressed("ui_cancel"):  # Esc / pad B also resume
		Sfx.ui("ui_back")
		resume()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("pause"):
		return
	if _open and not _settings.is_open():
		Sfx.ui("ui_back")
		resume()
		get_viewport().set_input_as_handled()
	elif not _open and not get_tree().paused:
		open()
		get_viewport().set_input_as_handled()


func open() -> void:
	_open = true
	_confirm = ""
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()


func resume() -> void:
	_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if get_tree().get_first_node_in_group("player") else Input.MOUSE_MODE_VISIBLE


func _build() -> void:
	if not _open:
		return
	for child in get_children():
		if child != _settings:
			child.queue_free()
	var backdrop := UiKit.dim(self, 0.72)
	move_child(backdrop, 0)
	var column := UiKit.column(self, _theme, 130.0, 3)
	column.add_child(UiTheme.heading("Paused", 10))
	column.add_child(UiTheme.divider())
	var buttons: Array = []
	buttons.append(UiKit.button("Resume", resume, 110.0))
	buttons.append(UiKit.button("Settings", func(): _settings.open(0), 110.0))
	buttons.append(UiKit.button("Controls", func(): _settings.open(2), 110.0))
	buttons.append(UiKit.button("Hall of heroes", func():
		resume()
		var screen := get_tree().get_first_node_in_group("leaderboard_screen")
		if screen:
			screen.open(), 110.0))
	if Game.mode == "dungeon" and not Game.run.is_empty():
		var retreat_text := "Really? -30% gold only" if _confirm == "retreat" else "Retreat to camp"
		buttons.append(UiKit.button(retreat_text, _retreat, 110.0))
	buttons.append(UiKit.button("Leave the game" if Net.is_online() else "Save and quit to menu", _save_and_leave, 110.0))
	buttons.append(UiKit.button("Quit to desktop", _quit, 110.0))
	for b in buttons:
		column.add_child(b)
	UiKit.wrap_focus(buttons)
	UiKit.focus_first(column)


func _retreat() -> void:
	if _confirm != "retreat":
		_confirm = "retreat"
		_build()
		return
	Game.lose_run(false)  # a retreat costs only gold: the run's loot and every element stay
	Game.meta["runs"] = int(Game.meta.get("runs", 0)) + 1
	Game.return_to_camp()


func _save_and_leave() -> void:
	if Game.save_game() == OK:
		Sfx.play("save", &"UI", -6.0)
	Game.go_to_menu()


func _quit() -> void:
	Game.save_game()
	get_tree().quit()
