class_name MultiplayerMenu
extends Node
## The multiplayer screens, opened from the title screen: pick which saved hero plays, then host a game or join
## one, wait in the lobby (everyone's name and class), and the host starts a co-op dungeon or an arena duel.
## Playing needs a saved hero: the hero keeps what it earns. Built in code from UiKit like the other menus.

signal closed

const WIDTH := 250.0

var _theme: Theme
var _layer: CanvasLayer
var _view: Control
var _address := "127.0.0.1"
var _port := Net.DEFAULT_PORT
var _status := ""
var _tier := 1
var _roster_label: Label
var _start_buttons: Array = []
var _back := Callable()  # what the view's Back / Cancel / Leave button does; Esc and pad B do the same


func _ready() -> void:
	_theme = UiTheme.make()
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	Net.roster_changed.connect(_refresh_roster)
	Net.joined.connect(func(): show_lobby(false))
	Net.join_failed.connect(func(reason: String):
		_status = reason
		show_join())
	Net.disconnected.connect(func(reason: String):
		_status = reason
		show_choice())


func _exit_tree() -> void:
	for connection in Net.roster_changed.get_connections():
		if connection["callable"].get_object() == self:
			Net.roster_changed.disconnect(connection["callable"])


func is_open() -> bool:
	return _view != null


func _unhandled_input(event: InputEvent) -> void:
	if _view != null and _back.is_valid() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		Sfx.ui("ui_back")
		_back.call()


## A Back-style button that Esc and pad B press too.
func _back_button(text: String, action: Callable) -> Button:
	_back = action
	return UiKit.button(text, action, 70.0)


func _clear() -> VBoxContainer:
	_back = Callable()
	if _view:
		_view.queue_free()
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(holder)
	_view = holder
	UiKit.dim(holder, 0.94)  # hides the title list behind
	return UiKit.column(holder, _theme, WIDTH, 3)


func close() -> void:
	if _view:
		_view.queue_free()
		_view = null
	closed.emit()


# ---------- which hero ----------

func open() -> void:
	show_hero()


func show_hero() -> void:
	var column := _clear()
	column.add_child(UiTheme.heading("Multiplayer", 10))
	column.add_child(UiKit.label("Who plays? Your hero keeps what it earns here.", UiTheme.TEXT_DIM, 6, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiTheme.divider())
	var any := false
	for slot in SaveStore.SLOTS:
		var info := SaveStore.summary(slot)
		if info.is_empty():
			continue
		any = true
		var text := "%s  (%s, level %d)" % [info["name"], info["class"], info["level"]]
		var button := UiKit.button(text, func(): _use_hero(slot), WIDTH - 20.0)
		column.add_child(button)
	if not any:
		column.add_child(UiKit.label("No saved hero yet: start a new game first.", UiTheme.RED, 6, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_back_button("Back", close))
	UiKit.focus_first(column)


func _use_hero(slot: int) -> void:
	if not Game.use_hero(slot):
		_status = "That save could not be read"
		show_hero()
		return
	show_choice()


# ---------- host or join ----------

func show_choice() -> void:
	var column := _clear()
	column.add_child(UiTheme.heading("Multiplayer", 10))
	column.add_child(UiKit.label("Playing as %s (%s, level %d)" % [Game.character.display_name, Classes.CLASSES[Game.character.class_id]["name"], Game.character.level], UiTheme.GOLD, 7, HORIZONTAL_ALIGNMENT_CENTER))
	if _status != "":
		column.add_child(UiKit.label(_status, UiTheme.RED, 6, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiTheme.divider())
	column.add_child(UiKit.button("Host a game", _host, 120.0))
	column.add_child(UiKit.button("Join a game", show_join, 120.0))
	column.add_child(_back_button("Back", show_hero))
	UiKit.focus_first(column)


func _host() -> void:
	var err := Net.host(_port)
	if err != OK:
		_status = "Could not host on port %d (error %d)" % [_port, err]
		show_choice()
		return
	_status = ""
	show_lobby(true)


func show_join() -> void:
	var column := _clear()
	column.add_child(UiTheme.heading("Join a game", 10))
	column.add_child(UiKit.label("Type the host's address (the host sees it in their lobby).", UiTheme.TEXT_DIM, 6, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var address := LineEdit.new()
	address.text = _address
	address.custom_minimum_size = Vector2(120, 0)
	address.text_changed.connect(func(text: String): _address = text)
	row.add_child(address)
	var port := LineEdit.new()
	port.text = str(_port)
	port.custom_minimum_size = Vector2(36, 0)
	port.max_length = 5
	port.text_changed.connect(func(text: String): _port = clampi(int(text), 1024, 65535))
	row.add_child(port)
	column.add_child(row)
	if _status != "":
		column.add_child(UiKit.label(_status, UiTheme.RED, 6, HORIZONTAL_ALIGNMENT_CENTER))
	var go := UiKit.button("Join", func():
		var err := Net.join(_address, _port)
		if err != OK:
			_status = "Could not start joining (error %d)" % err
			show_join()
			return
		_status = ""
		_show_waiting("Connecting to %s ..." % _address), 80.0)
	column.add_child(go)
	column.add_child(_back_button("Back", show_choice))
	UiKit.focus_first(column)


func _show_waiting(text: String) -> void:
	var column := _clear()
	column.add_child(UiTheme.heading("Multiplayer", 10))
	column.add_child(UiKit.label(text, UiTheme.TEXT, 7, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_back_button("Cancel", func():
		Net.leave()
		show_choice()))
	UiKit.focus_first(column)


# ---------- the lobby ----------

func show_lobby(is_host: bool) -> void:
	var column := _clear()
	column.add_child(UiTheme.heading("Lobby" if is_host else "Waiting for the host", 10))
	if is_host:
		var addresses: Array[String] = []
		for address in IP.get_local_addresses():
			if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
				addresses.append(address)
		column.add_child(UiKit.label("Friends join with:  %s   port %d" % [addresses[0] if not addresses.is_empty() else "127.0.0.1", _port], UiTheme.GOLD, 6, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiTheme.divider())
	_roster_label = UiKit.label("", UiTheme.TEXT, 7)
	_roster_label.custom_minimum_size = Vector2(WIDTH - 30.0, 36)
	column.add_child(_roster_label)
	_start_buttons.clear()
	if is_host:
		var tiers := HBoxContainer.new()
		tiers.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_child(tiers)
		tiers.add_child(UiKit.label("Dungeon:", UiTheme.TEXT_DIM, 6))
		for tier in Game.TIERS:
			var unlocked := Game.tier_unlocked(int(tier))
			var pick := UiKit.button(["I", "II", "III", "IV", "V"][int(tier) - 1], func():
				_tier = int(tier)
				_refresh_roster(), 22.0)
			pick.disabled = not unlocked
			tiers.add_child(pick)
		var coop := UiKit.button("Start co-op dungeon", func(): Net.start_session("coop", _tier), 130.0)
		var arena := UiKit.button("Start arena duel", func(): Net.start_session("arena"), 130.0)
		_start_buttons = [coop, arena]
		column.add_child(coop)
		column.add_child(arena)
	column.add_child(_back_button("Leave", func():
		Net.leave()
		show_choice()))
	_refresh_roster()
	UiKit.focus_first(column)


func _refresh_roster() -> void:
	if _roster_label == null or not is_instance_valid(_roster_label):
		return
	var lines: Array[String] = []
	var ids: Array = Net.roster.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = Net.roster[id]
		var who := "%s  (%s, level %d)" % [info["name"], String(Classes.CLASSES.get(info["class"], {"name": "?"})["name"]), int(info["level"])]
		lines.append(("Host: " if int(id) == 1 else "") + who + ("   <- you" if int(id) == Net.my_id() else ""))
	_roster_label.text = "\n".join(lines)
	for button in _start_buttons:
		button.disabled = Net.roster.size() < 2
	if Net.is_host() and Net.roster.size() < 2 and not _start_buttons.is_empty():
		_roster_label.text += "\nWaiting for someone to join..."
