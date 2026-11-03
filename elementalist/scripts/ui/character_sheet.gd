class_name CharacterSheet
extends CanvasLayer
## Character screen (TAB, Esc to close). Pauses the game while open. Tabs:
##   Stats      level, attributes (spend points), derived stats, class choice (level 3),
##              subclass choice (level 10), affinity, traits
##   Skills     skills by set with cost, cooldown and damage after the character's stats
##   Elements   mastery, and which attribute governs each element's potency
##   Passives   class / trait / element / skill passives, and progress toward the rare ones
##   Combos     all ten element combinations; the ones this character can trigger are lit
##   Rewards    milestone level rewards waiting to be claimed (pick one option per offer)
## Everything is built from Game.character each time a tab opens; nothing is cached.

const TABS := ["stats", "skills", "elements", "passives", "combos", "rewards"]
const PANEL_SIZE := Vector2i(304, 172)  # fits inside the 320x180 game view
## Column widths: a tab's columns plus gaps must fit in this (scroll area minus its scrollbar).
const CONTENT_WIDTH := 284.0
const GOLD := Color("ffd84a")
const DIM := Color(1, 1, 1, 0.4)
const TYPE_COLORS := {
	"class": Color("e8e8f0"), "trait": Color("8fe3ff"), "element": Color("ffa66b"), "skill": Color("b6ff8a"),
}

var _open := false
var _tab := "stats"
var _theme: Theme
var _content: Control  # holds the current tab; rebuilt by show_tab()


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_theme = UiTheme.make()


func _exit_tree() -> void:
	get_tree().paused = false


## _input (not _unhandled_input) so TAB still closes the sheet while a button has focus:
## Godot would otherwise use TAB to move GUI focus.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("character_sheet") or (_open and event.is_action_pressed("pause")):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_open = not _open
	visible = _open
	get_tree().paused = _open
	var in_game := get_tree().get_first_node_in_group("player") != null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (_open or not in_game) else Input.MOUSE_MODE_HIDDEN
	if _open:
		show_tab(_tab)


## Builds the frame (tab buttons + content area) and fills it with `tab`.
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
	frame.add_theme_constant_override("separation", 4)
	panel.add_child(frame)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	frame.add_child(tab_row)
	for id in TABS:
		var button := _button(String(id).capitalize())
		if id == "rewards" and not Game.character.pending_rewards.is_empty():
			button.text = "Rewards (%d)" % Game.character.pending_rewards.size()
		button.toggle_mode = true
		button.button_pressed = id == _tab
		button.pressed.connect(show_tab.bind(id))
		tab_row.add_child(button)
	var close_hint := _label("  TAB / Esc to close", Color(1, 1, 1, 0.45))
	close_hint.autowrap_mode = TextServer.AUTOWRAP_OFF  # a wrapping label here would stretch the whole row
	tab_row.add_child(close_hint)

	# The tab body scrolls inside a fixed area, so a busy tab can never spill off the screen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(292, 140)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	_content = HBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)
	match _tab:
		"stats": _fill_stats()
		"skills": _fill_skills()
		"elements": _fill_elements()
		"passives": _fill_passives()
		"combos": _fill_combos()
		"rewards": _fill_rewards()


# ---------- tabs ----------

func _fill_stats() -> void:
	var ch := Game.character
	var left := _column(124)
	var right := _column(148)
	var cls: Dictionary = Classes.CLASSES[ch.class_id]
	var title := "%s  Lv %d  %s" % [ch.display_name, ch.level, cls["name"]]
	if ch.subclass_id != "":
		title += " / " + String(Classes.SUBCLASSES[ch.subclass_id]["name"])
	left.add_child(_label(title, GOLD))
	left.add_child(_label("XP %d / %d" % [ch.xp, CharacterData.xp_to_next(ch.level)]))
	left.add_child(_label("Points to spend: %d" % ch.unspent_points, GOLD if ch.unspent_points > 0 else Color.WHITE))
	left.add_child(_spacer())
	for attr in Classes.ATTRIBUTES:
		var row := HBoxContainer.new()
		var name_label := _label(String(attr).capitalize())
		name_label.custom_minimum_size = Vector2(60, 0)
		row.add_child(name_label)
		var value_label := _label(str(ch.attributes[attr]))
		value_label.custom_minimum_size = Vector2(18, 0)
		row.add_child(value_label)
		var plus := _button("+")
		plus.disabled = ch.unspent_points <= 0
		plus.pressed.connect(_spend.bind(attr))
		row.add_child(plus)
		left.add_child(row)
	left.add_child(_spacer())
	var d := ch.derived()
	left.add_child(_label("HP %d   Mana %d   Stamina %d" % [d["max_hp"], d["max_mana"], d["max_stamina"]]))
	left.add_child(_label("Move %d   Melee x%.2f   Reach x%.2f" % [d["move_speed"], d["melee_damage_mult"], d["melee_range_mult"]]))

	right.add_child(_label(String(cls["desc"]), Color(0.8, 0.85, 1.0)))
	right.add_child(_label(_affinity_text(ch), Color(0.7, 0.9, 1.0)))
	right.add_child(_spacer())
	if ch.can_choose_class():
		right.add_child(_label("Choose your class:", GOLD))
		for id in Classes.playable():
			var button := _button(String(Classes.CLASSES[id]["name"]))
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.pressed.connect(_choose_class.bind(id))
			right.add_child(button)
			right.add_child(_label(String(Classes.CLASSES[id]["desc"]), Color(0.75, 0.75, 0.8)))
		return
	if Classes.is_starter(ch.class_id):
		right.add_child(_label("Class at level %d" % Classes.CLASS_LEVEL, DIM))
	right.add_child(_label("Traits (innate)", GOLD))
	if ch.traits.is_empty():
		right.add_child(_label("None", DIM))
	for id in ch.traits:
		var p := Classes.passive_info(id)
		right.add_child(_label("%s: %s" % [p["name"], p["desc"]], TYPE_COLORS["trait"]))
	var subclasses := ch.available_subclasses()
	if not subclasses.is_empty():
		right.add_child(_spacer())
		right.add_child(_label("Choose a subclass:", GOLD))
		for id in subclasses:
			var button := _button(String(Classes.SUBCLASSES[id]["name"]))
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.pressed.connect(_choose_subclass.bind(id))
			right.add_child(button)
			right.add_child(_label(String(Classes.SUBCLASSES[id]["desc"]), Color(0.75, 0.75, 0.8)))
	elif ch.subclass_id == "" and not Classes.is_starter(ch.class_id) and ch.level < Classes.SUBCLASS_LEVEL:
		right.add_child(_spacer())
		right.add_child(_label("Subclass at level %d" % Classes.SUBCLASS_LEVEL, DIM))


func _fill_skills() -> void:
	var ch := Game.character
	var sets: Array[String] = []
	sets.append_array(ch.elements.filter(func(e): return SkillDB.LOADOUTS.has(e)))
	if ch.has_martial():
		sets.append("martial")
	var columns := [_column(136), _column(136)]
	columns[0].add_child(_label("Skills (numbers include your stats)", GOLD))
	columns[1].add_child(_label("LMB primary   F area (Lv %d)   R special (reward)   Q locks elements" % Classes.AREA_LEVEL, DIM))
	if sets.is_empty():
		columns[0].add_child(_label("No skills: no elements and no martial training.", DIM))
	for i in sets.size():
		var col: VBoxContainer = columns[i % 2] if sets.size() > 3 else columns[0 if i < 2 else 1]
		var set_id: String = sets[i]
		col.add_child(_label(String(set_id).capitalize() if set_id != "martial" else "Martial (stamina)", Elements.color_of(set_id).lightened(0.3)))
		for slot in ["primary", "area", "special"]:
			col.add_child(_skill_line(ch, SkillDB.LOADOUTS[set_id][slot], slot))


## One compact line for a skill: key, name, cost, cooldown, damage; dim if not yet learned.
func _skill_line(ch: CharacterData, id: String, slot: String) -> Label:
	var def: Dictionary = SkillDB.DEFS[id]
	var key: String = {"primary": "LMB", "area": "F", "special": "R"}[slot]
	if not ch.can_use_skill(id):
		var how := "reward" if slot == "special" else "Lv %d" % ch.skill_unlock_level(id)
		return _label("  %s %s  (%s)" % [key, def["name"], how], DIM)
	var cost := "%d%s" % [SkillDB.cost_of(def), "st" if SkillDB.uses_stamina(def) else "mp"]
	var text := "  %s %s  %s  %.1fs  dmg %.0f" % [key, def["name"], cost, ch.skill_cooldown(id), ch.skill_damage(id)]
	for prop in def.get("scales", {}):
		text += "  %s x%.2f" % [String(prop).substr(0, 3), ch.skill_scale(id, prop)]
	return _label(text)


func _fill_elements() -> void:
	var ch := Game.character
	var col := _column(CONTENT_WIDTH)
	col.add_child(_label("Elements  (mastery +4%% spell damage per level; rare passive at level %d)" % Classes.RARE_PASSIVE_LEVEL, GOLD))
	col.add_child(_label(_affinity_text(ch), Color(0.7, 0.9, 1.0)))
	if ch.elements.is_empty():
		col.add_child(_label("No elements yet. Items or story events can attune you.", DIM))
	for element in Elements.MAIN + Elements.RARE:
		var governing: String = Classes.ELEMENT_ATTRIBUTE[element]
		var potency := ch.potency_mult(element)
		var color := Elements.color_of(element).lightened(0.3)
		if element in ch.elements:
			var m: Dictionary = ch.element_mastery[element]
			var text := "%s  mastery %d (%d/%d)   potency x%.2f from %s" % [String(element).capitalize(), m["level"], m["xp"], CharacterData.mastery_xp_to_next(m["level"]), potency, governing.capitalize()]
			if not SkillDB.LOADOUTS.has(element):
				text += "   (no skills yet)"
			col.add_child(_label(text, color))
		else:
			col.add_child(_label("%s  not attuned   (governed by %s)" % [String(element).capitalize(), governing.capitalize()], Color(color, 0.4)))


func _fill_passives() -> void:
	var ch := Game.character
	var left := _column(146)
	var right := _column(126)
	left.add_child(_label("Active passives", GOLD))
	for source in ch.passive_sources():
		var p := Classes.passive_info(source["id"])
		var rare := " (rare)" if source["type"] in ["element", "skill"] else ""
		left.add_child(_label("[%s%s] %s: %s" % [String(source["type"]).capitalize(), rare, p["name"], p["desc"]], TYPE_COLORS[source["type"]]))
	right.add_child(_label("Progress to rare passives", GOLD))
	for element in ch.elements:
		if ch.element_level(element) < Classes.RARE_PASSIVE_LEVEL and Classes.ELEMENT_PASSIVES.has(element):
			right.add_child(_label("%s mastery %d/%d" % [String(element).capitalize(), ch.element_level(element), Classes.RARE_PASSIVE_LEVEL], TYPE_COLORS["element"]))
	if ch.weapon_level() < Classes.RARE_PASSIVE_LEVEL:
		right.add_child(_label("%s mastery %d/%d" % [ch.weapon_type.capitalize(), ch.weapon_level(), Classes.RARE_PASSIVE_LEVEL], TYPE_COLORS["skill"]))
	var shown := 0
	for id in ch.known_skills():
		var need := Classes.skill_passive_uses(id)
		var uses := int(ch.skill_uses.get(id, 0))
		if uses < need and shown < 6:
			right.add_child(_label("%s %d/%d uses" % [SkillDB.DEFS[id]["name"], uses, need], TYPE_COLORS["skill"]))
			shown += 1


func _fill_combos() -> void:
	var ch := Game.character
	var col := _column(CONTENT_WIDTH)
	col.add_child(_label("Combos: hit an enemy with a second element while the first still marks it (4s)", GOLD))
	var keys := Elements.COMBOS.keys()
	keys.sort()
	for key in keys:
		var combo: Dictionary = Elements.COMBOS[key]
		var pair: Array = Array(String(key).split("+"))
		var missing: Array = pair.filter(func(e): return not (e in ch.elements))
		var text := "%s + %s = %s   %s" % [pair[0].capitalize(), pair[1].capitalize(), combo["name"], Elements.describe_combo(combo)]
		if missing.is_empty():
			col.add_child(_label(text, combo["color"].lightened(0.35)))
		else:
			col.add_child(_label("%s   (needs %s)" % [text, ", ".join(missing.map(func(e): return String(e).capitalize()))], DIM))

	col.add_child(_spacer())
	col.add_child(_label("Resonance: %d hits of the same element in a row" % Elements.RESONANCE_HITS, GOLD))
	for element in Elements.RESONANCE:
		var resonance: Dictionary = Elements.RESONANCE[element]
		var line := "%s x%d = %s   %s" % [String(element).capitalize(), Elements.RESONANCE_HITS, resonance["name"], Elements.describe_combo(resonance)]
		if element in ch.elements:
			col.add_child(_label(line, resonance["color"].lightened(0.35)))
		else:
			col.add_child(_label("%s   (needs %s)" % [line, String(element).capitalize()], DIM))

	col.add_child(_spacer())
	col.add_child(_label("Martial: %d physical hits within %.0fs (slash, spin, knives, whirlwind)" % [Elements.MARTIAL_CHAIN_HITS, Elements.MARTIAL_CHAIN_TIME], GOLD))
	var rend: Dictionary = Elements.MARTIAL_COMBO
	col.add_child(_label("Physical x%d = %s   %s" % [Elements.MARTIAL_CHAIN_HITS, rend["name"], Elements.describe_combo(rend)], rend["color"]))
	col.add_child(_label("Imbued slashes and fused bolts count as elemental hits instead.", DIM))


func _fill_rewards() -> void:
	var ch := Game.character
	var col := _column(CONTENT_WIDTH)
	col.add_child(_label("Level rewards: pick one option from each offer. Every even level except %d gives one." % Classes.SUBCLASS_LEVEL, GOLD))
	if ch.pending_rewards.is_empty():
		col.add_child(_label("Nothing to claim. Next offer at level %d." % _next_reward_level(ch.level), DIM))
		return
	for offer_index in ch.pending_rewards.size():
		var offer: Array = ch.pending_rewards[offer_index]
		col.add_child(_label("Offer %d  (%d option%s)" % [offer_index + 1, offer.size(), "" if offer.size() == 1 else "s"], Color("e8e8f0")))
		for option_index in offer.size():
			var button := _button(Rewards.option_text(offer[option_index]))
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.pressed.connect(_claim.bind(offer_index, option_index))
			col.add_child(button)


# ---------- helpers ----------

func _next_reward_level(from_level: int) -> int:
	var next := from_level + 1
	while next <= CharacterData.MAX_LEVEL and not Rewards.is_reward_level(next):
		next += 1
	return next


func _affinity_text(ch: CharacterData) -> String:
	match ch.affinity:
		CharacterData.SEALED:
			return "Sealed: can never hold elements. Martial skills."
		CharacterData.ATTUNABLE:
			return "Attunable: born without elements, learns martial skills, can be attuned by items or story."
	return "Elementalist: born with elements."


func _spend(attr: String) -> void:
	Game.character.spend_point(attr)
	show_tab.call_deferred(_tab)


func _choose_class(id: String) -> void:
	Game.character.choose_class(id)
	show_tab.call_deferred(_tab)


func _choose_subclass(id: String) -> void:
	Game.character.choose_subclass(id)
	show_tab.call_deferred(_tab)


func _claim(offer_index: int, option_index: int) -> void:
	Game.character.claim_reward(offer_index, option_index)
	show_tab.call_deferred(_tab)


func _column(width: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(width, 0)
	_content.add_child(column)
	return column


## Total width a list of column widths needs (columns plus the 12px gaps between them).
static func tab_width(column_widths: Array) -> float:
	var total := 12.0 * maxf(column_widths.size() - 1, 0.0)
	for width in column_widths:
		total += float(width)
	return total


## A button that never takes keyboard focus, so TAB/WASD stay with the game.
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


func _spacer() -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, 3)
	return s
