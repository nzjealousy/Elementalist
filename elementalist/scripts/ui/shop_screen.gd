class_name ShopScreen
extends CanvasLayer
## The camp merchant's menu, opened with G at the shopkeeper (Esc or G closes; the game pauses).
## Tabs:  Gems (the elements the hero lacks)  and  Legendary (three rotating items).
## The rules live in Shop (tested without any UI); this only lists and calls them.

const TABS := ["gems", "legendary"]
const PANEL_SIZE := Vector2i(304, 172)
const GOLD := Color("ffd84a")
const DIM := Color(1, 1, 1, 0.4)

var _open := false
var _tab := "gems"
var _theme: Theme
var _content: VBoxContainer
var _status := ""


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("shop_screen")
	_theme = UiTheme.make()


func _exit_tree() -> void:
	if _open:
		get_tree().paused = false


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_status = ""
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_tab(_tab)


func close() -> void:
	if _open:
		Sfx.ui("ui_back")
	_open = false
	visible = false
	get_tree().paused = false
	var in_game := get_tree().get_first_node_in_group("player") != null
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if in_game else Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
	return _open


func _input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


func show_tab(tab: String) -> void:
	var focus_at := UiKit.focused_index(self) if tab == _tab else -1
	_tab = tab
	for child in get_children():
		child.queue_free()
	var panel := PanelContainer.new()
	panel.theme = _theme
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(PANEL_SIZE)
	panel.clip_contents = true
	add_child(panel)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 3)
	panel.add_child(frame)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	frame.add_child(tab_row)
	var title := _label("Merchant ", GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	tab_row.add_child(title)
	for id in TABS:
		var button := UiKit.button(String(id).capitalize(), func(): pass)
		button.toggle_mode = true
		button.button_pressed = id == _tab
		button.pressed.connect(_switch_tab.bind(id))
		tab_row.add_child(button)
	var hint := _label("  Esc / G: close", Color(1, 1, 1, 0.45))
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	tab_row.add_child(hint)

	var wallet := _label("Gold %d" % Game.character.inventory.gold, Color("e8e8f0"))
	wallet.autowrap_mode = TextServer.AUTOWRAP_OFF
	frame.add_child(wallet)
	var status := _label(_status, Color("b6ff8a"))
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	frame.add_child(status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(292, 108)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(280, 0)
	_content.add_theme_constant_override("separation", 1)
	scroll.add_child(_content)
	if _tab == "gems":
		_fill_gems()
	else:
		_fill_legendary()
	if _open:
		UiKit.restore_focus(self, focus_at, tab_row.get_child(TABS.find(_tab) + 1))


func _fill_gems() -> void:
	var c := Game.character
	var price := Shop.gem_price(int(Game.meta.get("gems_bought", 0)))
	_content.add_child(_label("A gem attunes you to a new element for good. One of each per visit; every gem bought makes the next dearer (now %dg)." % price, DIM))
	var offers := Shop.gem_offers(c, int(Game.meta.get("tier_cleared", 0)), Game.shop_sold)
	for element in offers:
		var problem := Shop.gem_problem(c, Game.meta, element, Game.shop_sold)
		var button := UiKit.button("%s  %dg" % [Items.MATERIALS[Items.gem_of(element)]["name"], price], func(): pass)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = problem != ""
		button.tooltip_text = problem
		button.add_theme_color_override("font_color", Elements.color_of(element).lightened(0.3))
		button.pressed.connect(_buy_gem.bind(element))
		_content.add_child(button)
	if offers.is_empty():
		_content.add_child(_label("Nothing for sale: you hold every element on offer (Light and Dark come after dungeon 2).", DIM))


func _fill_legendary() -> void:
	var inv := Game.character.inventory
	_content.add_child(_label("Three legendaries, new stock each time you return to camp.", DIM))
	for index in Game.shop_stock.size():
		var entry: Dictionary = Game.shop_stock[index]
		var item: Dictionary = entry["item"]
		var problem := Shop.legendary_problem(inv, Game.shop_stock, index)
		var text := "%s  %dg" % [Items.display_name(item), int(entry["price"])]
		if entry["sold"]:
			text = "%s  (sold)" % Items.display_name(item)
		var button := UiKit.button(text, func(): pass)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = problem != ""
		button.tooltip_text = Items.describe(item) + ("" if problem == "" else "\n" + problem)
		button.add_theme_color_override("font_color", Items.rarity_color(item))
		button.pressed.connect(_buy_legendary.bind(index))
		_content.add_child(button)
	if inv.bag_full():
		_content.add_child(_label("Bag full: salvage something first.", Color("ff7a7a")))


func _switch_tab(id: String) -> void:
	_status = ""
	show_tab.call_deferred(id)


func _buy_gem(element: String) -> void:
	var ok := Shop.buy_gem(Game.character, Game.meta, element, Game.shop_sold)
	Sfx.play("forge" if ok else "error")
	_status = ("Bought the %s gem: use it from the character sheet" % element.capitalize()) if ok else "Could not buy"
	show_tab.call_deferred(_tab)


func _buy_legendary(index: int) -> void:
	var ok := Shop.buy_legendary(Game.character.inventory, Game.shop_stock, index)
	Sfx.play("forge" if ok else "error")
	_status = "Bought it: check your bag" if ok else "Could not buy"
	show_tab.call_deferred(_tab)


func _label(text: String, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
