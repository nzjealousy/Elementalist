class_name LeaderboardScreen
extends CanvasLayer
## The runs leaderboard (Leaderboard): the best ten runs on this machine. Opened from the main menu
## and from the notice board in camp. Esc / B / Back closes it.

signal closed

const SHOWN := 10
const OUTCOME_COLORS := {"cleared": Color("9ae87a"), "fell": Color("f2cf6a"), "died": Color("ff7a6a")}

var _open := false
var _theme: Theme
var _was_paused := false


func _init() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("leaderboard_screen")


func _ready() -> void:
	_theme = UiTheme.make()


func _exit_tree() -> void:
	if _open:
		get_tree().paused = _was_paused


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = _was_paused
	var in_game := get_tree().get_first_node_in_group("player") != null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (_was_paused or not in_game) else Input.MOUSE_MODE_HIDDEN
	closed.emit()


func _input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		Sfx.ui("ui_back")
		close()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	UiKit.dim(self, 0.9)
	var column := UiKit.column(self, _theme, 290.0, 2)
	column.add_child(UiTheme.heading("Hall of Heroes", 10))
	column.add_child(UiTheme.divider())
	var entries := Leaderboard.entries()
	if entries.is_empty():
		column.add_child(UiKit.label("No runs yet. Enter a dungeon and leave your mark.", UiTheme.TEXT_DIM, 7, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 1)
		column.add_child(grid)
		for head in ["#", "Hero", "Lv", "Depth", "Score", "Fate"]:
			grid.add_child(UiKit.label(head, UiTheme.GOLD_DARK, 6))
		for i in mini(entries.size(), SHOWN):
			var e: Dictionary = entries[i]
			var fate := String(e.get("outcome", "fell"))
			var cells := [str(i + 1), "%s (%s)" % [e.get("name", "?"), e.get("class", "?")], str(int(e.get("level", 1))),
				"%d" % int(e.get("floors", 0)), str(int(e.get("score", 0))), fate.capitalize()]
			for c in cells.size():
				var color: Color = OUTCOME_COLORS.get(fate, UiTheme.TEXT) if c == 5 else UiTheme.TEXT
				var label := UiKit.label(cells[c], color, 6)
				if c == 1:
					label.custom_minimum_size = Vector2(120, 0)
				grid.add_child(label)
	column.add_child(UiTheme.divider())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	row.add_child(UiKit.button("Back", close, 70.0))
	UiKit.focus_first(row)
