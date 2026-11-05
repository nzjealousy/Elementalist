class_name AltarScreen
extends CanvasLayer
## The altar of the training grounds: every element side by side, so their differences are
## visible before they are felt. One row per element with bars for mana cost, bolt speed, area
## radius and damage, plus what the element is for (SkillDB.ROLES) and what its two main skills
## do. "Take" makes that element the selected one; "Refill" restores health, stamina and mana.
## Esc / B closes it. Group "altar_screen".

const BAR_WIDTH := 34.0  # four bars, the element buttons and the description column side by side fit the 320 px view
const DETAIL_WIDTH := 84.0

var _open := false
var _was_paused := false
var _theme: Theme
var _detail: Label
var _chosen := ""


func _init() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("altar_screen")


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
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if get_tree().get_first_node_in_group("player") else Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()


## The numbers that set elements apart, per element: primary mana, bolt speed, area radius, damage.
static func stats_of(element: String) -> Dictionary:
	var set: Dictionary = SkillDB.LOADOUTS[element]
	var primary: Dictionary = SkillDB.DEFS[set["primary"]]
	var area: Dictionary = SkillDB.DEFS[set["area"]]
	return {
		"mana": float(primary["mana"]), "speed": float(primary["speed"]),
		"radius": float(area["radius"]), "damage": float(primary["damage"]) * float(primary.get("spread_count", 1)),
	}


func _build() -> void:
	for child in get_children():
		child.queue_free()
	UiKit.dim(self, 0.9)
	var column := UiKit.column(self, _theme, 308.0, 3)
	column.add_child(UiTheme.heading("Altar of Elements", 10))
	column.add_child(UiKit.label("Compare the elements, take one, and try it on the dummies.", UiTheme.TEXT_DIM, 6, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiTheme.divider())

	var maxima := {"mana": 1.0, "speed": 1.0, "radius": 1.0, "damage": 1.0}
	for element in Elements.MAIN + Elements.RARE:
		var s := stats_of(element)
		for key in maxima:
			maxima[key] = maxf(float(maxima[key]), float(s[key]))

	# The grid on the left, what the element does and the two actions on the right: seven rows and the text below them
	# would not fit the 180 px view.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	column.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 1)
	body.add_child(grid)
	grid.add_child(UiKit.label("", UiTheme.TEXT_DIM, 6))
	for title in ["Mana", "Speed", "Area", "Damage"]:
		grid.add_child(UiKit.label(title, UiTheme.TEXT_DIM, 6, HORIZONTAL_ALIGNMENT_CENTER))
	var buttons: Array = []
	for element in Elements.MAIN + Elements.RARE:
		var element_id: String = element
		var color := Elements.color_of(element_id)
		var button := UiKit.button(element_id.capitalize(), func(): _choose(element_id), 52.0)
		button.add_theme_color_override("font_color", color)
		button.add_theme_color_override("font_hover_color", color.lightened(0.3))
		button.mouse_entered.connect(_show.bind(element_id))
		button.focus_entered.connect(_show.bind(element_id))
		grid.add_child(button)
		buttons.append(button)
		var s := stats_of(element_id)
		for key in ["mana", "speed", "radius", "damage"]:
			grid.add_child(_bar(float(s[key]) / float(maxima[key]), color, "%d" % roundi(float(s[key]))))
	UiKit.wrap_focus(buttons)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 3)
	body.add_child(side)
	_detail = UiKit.label("", UiTheme.TEXT, 6)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_detail)
	_show(_current_element())
	side.add_child(UiKit.button("Refill", _refill, DETAIL_WIDTH))
	side.add_child(UiKit.button("Close", close, DETAIL_WIDTH))
	UiKit.focus_first(grid)


## A bar of `fraction` of the full width, with its number written on it.
func _bar(fraction: float, color: Color, number: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BAR_WIDTH, 10)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # level with the element's button
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.45)
	back.size = Vector2(BAR_WIDTH, 8)
	back.position = Vector2(0, 1)
	holder.add_child(back)
	var fill := ColorRect.new()
	fill.color = Color(color, 0.85)
	fill.size = Vector2(maxf(BAR_WIDTH * clampf(fraction, 0.0, 1.0), 2.0), 8)
	fill.position = Vector2(0, 1)
	holder.add_child(fill)
	var text := UiKit.label(number, Color.WHITE, 6, HORIZONTAL_ALIGNMENT_CENTER)
	text.add_theme_color_override("font_outline_color", Color.BLACK)
	text.add_theme_constant_override("outline_size", 2)
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(text)
	return holder


func _current_element() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.get("caster") != null:
		return String(player.caster.selected_element())
	return ""


## The role of an element and what its primary and area skills do.
static func describe(element: String) -> String:
	if not SkillDB.LOADOUTS.has(element):
		return ""
	var set: Dictionary = SkillDB.LOADOUTS[element]
	var primary: Dictionary = SkillDB.DEFS[set["primary"]]
	var area: Dictionary = SkillDB.DEFS[set["area"]]
	var lines: Array[String] = [String(SkillDB.ROLES.get(element, ""))]
	lines.append("%s: %.0f mana, speed %.0f, range %.0f%s" % [primary["name"], float(primary["mana"]), float(primary["speed"]), float(primary["range"]),
		(", " + SkillDB.effect_text(primary)) if SkillDB.effect_text(primary) != "" else ""])
	lines.append("%s: %.0f mana, radius %.0f%s" % [area["name"], float(area["mana"]), float(area["radius"]),
		(", " + SkillDB.effect_text(area)) if SkillDB.effect_text(area) != "" else ""])
	return "\n".join(lines)


func _show(element: String) -> void:
	if _detail:
		_detail.text = describe(element)


func _choose(element: String) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or player.get("caster") == null:
		return
	var index: int = player.caster.elements.find(element)
	if index >= 0:
		player.caster.select(index)
	_chosen = element
	_show(element)
	Game.say("Selected %s" % element.capitalize())


func _refill() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.hp = player.max_hp
	player.stamina = player.max_stamina
	if player.caster:
		player.caster.mana = player.caster.max_mana
		player.caster.cooldowns.clear()
