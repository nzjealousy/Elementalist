class_name ForgeScreen
extends CanvasLayer
## The forge menu, opened at the forge station with G (Esc or G closes; the game pauses).
## Tabs:
##   Craft     build new gear from gold and materials (rarity is rolled)
##   Upgrade   +1 to +10: every + adds 10% to the item's stats
##   Enchant   infuse an item with an element's essence for an extra bonus
##   Salvage   break bag items down into scrap and gold
## The rules live in Forge (so they are tested without any UI); this only lists and calls them.

const TABS := ["craft", "upgrade", "enchant", "salvage"]
const PANEL_SIZE := Vector2i(304, 172)
const GOLD := Color("ffd84a")
const DIM := Color(1, 1, 1, 0.4)

var _open := false
var _tab := "craft"
var _theme: Theme
var _content: VBoxContainer
var _status := ""                  # result of the last action, shown under the tabs
var _enchant_target: Dictionary = {}  # the item chosen on the Enchant tab (edited in place)


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("forge_screen")
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
	_enchant_target = {}
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_tab(_tab)


func close() -> void:
	_open = false
	visible = false
	get_tree().paused = false
	var in_game := get_tree().get_first_node_in_group("player") != null
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if in_game else Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
	return _open


func _input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


## Builds the frame (title, tab buttons, wallet, scrolling list) and fills it with `tab`.
func show_tab(tab: String) -> void:
	_tab = tab
	for child in get_children():
		child.queue_free()
	var panel := PanelContainer.new()
	panel.theme = _theme
	panel.position = Vector2(8, 4)
	panel.custom_minimum_size = Vector2(PANEL_SIZE)
	panel.clip_contents = true
	add_child(panel)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 3)
	panel.add_child(frame)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	frame.add_child(tab_row)
	var title := _label("Forge ", GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	tab_row.add_child(title)
	for id in TABS:
		var button := _button(String(id).capitalize())
		button.toggle_mode = true
		button.button_pressed = id == _tab
		button.pressed.connect(_switch_tab.bind(id))
		tab_row.add_child(button)
	var hint := _label("  Esc / G: close", Color(1, 1, 1, 0.45))
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	tab_row.add_child(hint)

	var wallet := _label(_wallet_text(), Color("e8e8f0"))
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
	match _tab:
		"craft": _fill_craft()
		"upgrade": _fill_upgrade()
		"enchant": _fill_enchant()
		"salvage": _fill_salvage()


# ---------- tabs ----------

func _fill_craft() -> void:
	var inv := Game.character.inventory
	_content.add_child(_label("New gear is rolled: usually plain, sometimes better. Item level = your level.", DIM))
	for base_id in Items.gear_bases():
		var problem := Forge.craft_problem(inv, base_id)
		var base: Dictionary = Items.BASES[base_id]
		var text := "%s (%s)  %s" % [base["name"], Items.SLOT_NAMES[base["slot"]], _cost_text(Forge.craft_cost(base_id))]
		var button := _button(text)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = problem != ""
		button.tooltip_text = problem
		button.pressed.connect(_craft.bind(base_id))
		_content.add_child(button)


func _fill_upgrade() -> void:
	var inv := Game.character.inventory
	_content.add_child(_label("+1 to +%d. Each + adds %d%% to the item's stats. Click an item to upgrade it." % [Items.MAX_PLUS, int(Items.UPGRADE_STEP * 100.0)], DIM))
	for entry in _all_items():
		var item: Dictionary = entry["item"]
		var problem := Forge.upgrade_problem(inv, item)
		var text := "%s%s" % [entry["where"], Items.display_name(item)]
		if problem == "Fully upgraded":
			text += "  (max)"
		else:
			text += "  %s" % _cost_text(Forge.upgrade_cost(item))
		var button := _item_button(item, text)
		button.disabled = problem != ""
		button.tooltip_text = problem if problem != "" else Items.describe(item)
		button.pressed.connect(_upgrade.bind(item))
		_content.add_child(button)
	if _all_items().is_empty():
		_content.add_child(_label("No gear.", DIM))


func _fill_enchant() -> void:
	var inv := Game.character.inventory
	if _enchant_target.is_empty():
		_content.add_child(_label("Step 1: choose an item to infuse. Essences drop from enemies you finish off with that element.", DIM))
		for entry in _all_items():
			var item: Dictionary = entry["item"]
			var text := "%s%s" % [entry["where"], Items.display_name(item)]
			if item["enchant"] != "":
				text += "  [%s]" % Items.ENCHANTS[item["enchant"]]["name"]
			var button := _item_button(item, text)
			button.tooltip_text = Items.describe(item)
			button.pressed.connect(_pick_enchant_target.bind(item))
			_content.add_child(button)
		return
	_content.add_child(_label("Step 2: choose an element for %s" % Items.display_name(_enchant_target), Items.rarity_color(_enchant_target)))
	for element in Items.ENCHANTS:
		var info: Dictionary = Items.ENCHANTS[element]
		var bonus := ", ".join(info["mods"].keys().map(func(k): return Items.format_mod(k, float(info["mods"][k]))))
		var button := _button("%s: %s  %s" % [info["name"], bonus, _cost_text(Forge.enchant_cost(_enchant_target, element))])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var problem := Forge.enchant_problem(inv, _enchant_target, element)
		button.disabled = problem != ""
		button.tooltip_text = problem
		button.add_theme_color_override("font_color", Elements.color_of(element).lightened(0.3))
		button.pressed.connect(_enchant.bind(element))
		_content.add_child(button)
	var back := _button("Back")
	back.pressed.connect(_pick_enchant_target.bind({}))
	_content.add_child(back)


func _fill_salvage() -> void:
	var inv := Game.character.inventory
	_content.add_child(_label("Break bag items into scrap and gold. Equipped gear is safe: take it off first.", DIM))
	for index in inv.bag.size():
		var item := inv.bag[index]
		var gain := Items.salvage_yield(item)
		var button := _item_button(item, "%s  -> %d scrap, %d gold" % [Items.display_name(item), gain["scrap"], gain["gold"]])
		button.tooltip_text = Items.describe(item)
		button.pressed.connect(_salvage.bind(index))
		_content.add_child(button)
	if inv.bag.is_empty():
		_content.add_child(_label("The bag is empty.", DIM))


# ---------- actions ----------

func _switch_tab(id: String) -> void:
	_status = ""
	_enchant_target = {}
	show_tab.call_deferred(id)


func _craft(base_id: String) -> void:
	var item := Forge.craft(Game.character.inventory, base_id, Game.character.level, Game.loot_rng, Game.loot_allows_spell())
	_status = ("Crafted %s" % Items.display_name(item)) if not item.is_empty() else "Could not craft"
	show_tab.call_deferred(_tab)


func _upgrade(item: Dictionary) -> void:
	var ok := Forge.upgrade(Game.character.inventory, item)
	_status = ("%s upgraded" % Items.display_name(item)) if ok else "Could not upgrade"
	show_tab.call_deferred(_tab)


func _pick_enchant_target(item: Dictionary) -> void:
	_enchant_target = item
	show_tab.call_deferred(_tab)


func _enchant(element: String) -> void:
	var ok := Forge.enchant(Game.character.inventory, _enchant_target, element)
	_status = ("%s enchanted: %s" % [Items.display_name(_enchant_target), Items.ENCHANTS[element]["name"]]) if ok else "Could not enchant"
	_enchant_target = {}
	show_tab.call_deferred(_tab)


func _salvage(index: int) -> void:
	var gain := Forge.salvage(Game.character.inventory, index)
	_status = ("Salvaged: +%d scrap, +%d gold" % [gain["scrap"], gain["gold"]]) if not gain.is_empty() else "Nothing to salvage"
	show_tab.call_deferred(_tab)


# ---------- helpers ----------

## Equipped items first (marked "E:"), then the bag.
func _all_items() -> Array:
	var out: Array = []
	var inv := Game.character.inventory
	for slot in Items.SLOTS:
		if inv.equipped.has(slot):
			out.append({"item": inv.equipped[slot], "where": "E: "})
	for item in inv.bag:
		out.append({"item": item, "where": ""})
	return out


func _wallet_text() -> String:
	return Game.character.inventory.summary()


## "30g 8 Scrap 3 Slime Gel".
func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in cost:
		parts.append("%dg" % int(cost[id]) if id == "gold" else "%d %s" % [int(cost[id]), Items.material_name(id)])
	return " ".join(parts)


func _item_button(item: Dictionary, text: String) -> Button:
	var button := _button(text)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override("font_color", Items.rarity_color(item))
	return button


## A button that never takes keyboard focus, so WASD stays with the game.
func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	return button


func _label(text: String, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
