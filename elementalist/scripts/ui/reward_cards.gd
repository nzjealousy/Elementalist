class_name RewardCards
extends CanvasLayer
## Level reward popup: when a milestone reward is ready, the game pauses and 1-3 cards appear
## in the middle of the screen. Click a card (or press its number key) to claim it. Esc
## postpones: the offer stays pending and can still be claimed on the sheet's Rewards tab.
## Several waiting offers are shown one after another.

const OPEN_DELAY := 0.7  # real seconds after the level-up, so its effects play first
const CARD_SIZE := Vector2(88, 112)
const TYPE_COLORS := {"skill": Color("b6ff8a"), "passive": Color("8fe3ff")}

var _open := false
var _theme: Theme


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_theme = UiTheme.make()
	Game.character.reward_ready.connect(_on_reward_ready)
	if not Game.character.pending_rewards.is_empty():
		_open_soon()  # offers already waiting when the scene starts (e.g. the sandbox)


func _exit_tree() -> void:
	if _open:
		get_tree().paused = false


func _on_reward_ready(_level: int) -> void:
	_open_soon()


## Waits a moment (and for any other menu to close), then shows the cards.
func _open_soon() -> void:
	await get_tree().create_timer(OPEN_DELAY, true, false, true).timeout
	while get_tree().paused and not _open:
		await get_tree().create_timer(0.5, true, false, true).timeout
	if not _open and not Game.character.pending_rewards.is_empty():
		open()


func open() -> void:
	_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()


func close() -> void:
	_open = false
	visible = false
	get_tree().paused = false
	var in_game := get_tree().get_first_node_in_group("player") != null
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if in_game else Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("pause"):
		close()  # decide later: the offer stays pending
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var index: int = int(event.keycode) - int(KEY_1)
		if index >= 0 and index < 3 and not Game.character.pending_rewards.is_empty() \
				and index < Game.character.pending_rewards[0].size():
			_choose(index)
			get_viewport().set_input_as_handled()


## Builds the dimmed backdrop and one card per option of the first pending offer.
func _build() -> void:
	for child in get_children():
		child.queue_free()
	var pending := Game.character.pending_rewards
	if pending.is_empty():
		return
	var offer: Array = pending[0]

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.theme = _theme
	column.add_theme_constant_override("separation", 6)
	center.add_child(column)

	var title := _label("Choose a reward", Color("ffd84a"), 9)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(cards)
	for i in offer.size():
		cards.add_child(_card(offer[i], i))
	var keys := "1" if offer.size() == 1 else "1-%d" % offer.size()
	var footer := "Click a card or press %s    Esc: decide later" % keys
	if pending.size() > 1:
		footer += "    (%d more waiting)" % (pending.size() - 1)
	var hint := _label(footer, Color(1, 1, 1, 0.6), 6)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF  # wrapping would squeeze it to the width of one card
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _card(option: Dictionary, index: int) -> Control:
	var panel := PanelContainer.new()
	panel.theme = _theme
	panel.custom_minimum_size = CARD_SIZE
	var type: String = option["type"]
	var box := UiTheme.frame("panel", 8, 6)  # the gold frame, tinted toward the card's kind
	if box is StyleBoxTexture:
		box.modulate_color = Color.WHITE.lerp(TYPE_COLORS[type], 0.5)
	panel.add_theme_stylebox_override("panel", box)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	panel.add_child(content)
	content.add_child(_label("%d  %s" % [index + 1, type.to_upper()], TYPE_COLORS[type], 6))
	content.add_child(_label(Rewards.option_name(option), Color.WHITE, 9))
	content.add_child(_label(_describe(option), Color(0.85, 0.88, 0.95), 6))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var choose := Button.new()
	choose.text = "Choose"
	choose.focus_mode = Control.FOCUS_NONE
	choose.pressed.connect(_choose.bind(index))
	content.add_child(choose)
	return panel


## The body text of a card: what a skill does and costs, or what a passive gives.
func _describe(option: Dictionary) -> String:
	if option["type"] == "skill":
		var def: Dictionary = SkillDB.DEFS[option["id"]]
		var set_name := SkillDB.set_of(option["id"]).capitalize()
		var shape := "Area" if def["kind"] == "aoe" else "Bolt"
		return "%s special on R.\n%s, %d damage.\n%d %s, %.0fs cooldown." % [
			set_name, shape, int(def["damage"]), int(SkillDB.cost_of(def)),
			"stamina" if SkillDB.uses_stamina(def) else "mana", float(def["cooldown"]),
		]
	return String(Classes.passive_info(option["id"])["desc"]) + ".\nA permanent trait."


func _choose(index: int) -> void:
	Game.character.claim_reward(0, index)
	if Game.character.pending_rewards.is_empty():
		close()
	else:
		_build()


func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
