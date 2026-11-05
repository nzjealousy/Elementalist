class_name RewardCards
extends CanvasLayer
## Level reward popup: when a milestone reward is ready, the game pauses and 1-3 cards appear
## in the middle of the screen. Click a card (or press its number key) to claim it. Esc
## postpones: the offer stays pending and can still be claimed on the sheet's Rewards tab.
## Several waiting offers are shown one after another.

const OPEN_DELAY := 0.7  # real seconds after the level-up, so its effects play first
const CARD_SIZE := Vector2(88, 112)
const TYPE_COLORS := {"skill": Color("88e880"), "passive": Color("5cc8ff")}

var _open := false
var _theme: Theme
var _frames: Array[CardFrame] = []
var _buttons: Array[Button] = []


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
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
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
	_frames.clear()
	_buttons.clear()

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

	var title := _label("Choose a reward", UiTheme.GOLD, 9)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(cards)
	for i in offer.size():
		cards.add_child(_card(offer[i], i))
	if not _buttons.is_empty():
		_buttons[0].grab_focus.call_deferred()
		_set_hot(0)
	var keys := "1" if offer.size() == 1 else "1-%d" % offer.size()
	var footer := "Click a card or press %s    Esc: decide later" % keys
	if pending.size() > 1:
		footer += "    (%d more waiting)" % (pending.size() - 1)
	var hint := _label(footer, Color(1, 1, 1, 0.6), 6)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF  # wrapping would squeeze it to the width of one card
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _card(option: Dictionary, index: int) -> Control:
	var type: String = option["type"]
	var color: Color = TYPE_COLORS[type]
	var holder := Control.new()
	holder.custom_minimum_size = CARD_SIZE
	var frame := CardFrame.for_kind(color, "stars" if type == "passive" else "flames")
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(frame)
	_frames.append(frame)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 6
	content.offset_right = -6
	content.offset_top = 6
	content.offset_bottom = -5
	content.add_theme_constant_override("separation", 2)
	holder.add_child(content)
	var kind := _label("%d  %s" % [index + 1, type.to_upper()], color, 6)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(kind)
	var picture := TextureRect.new()
	picture.texture = _icon_for(option)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(0, 30)
	picture.modulate = _icon_tint(option)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(picture)
	var name_label := _label(Rewards.option_name(option), Color.WHITE, 8)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(name_label)
	var body := _label(_describe(option), Color(0.85, 0.88, 0.95), 5)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(body)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var choose := UiKit.button("Choose", _choose.bind(index))
	choose.focus_mode = Control.FOCUS_ALL
	choose.mouse_entered.connect(func(): _set_hot(index))
	choose.focus_entered.connect(func(): _set_hot(index))
	content.add_child(choose)
	_buttons.append(choose)
	return holder


## A picture for a card: the skill's element rune, or a gem-like diamond for a passive.
func _icon_for(option: Dictionary) -> Texture2D:
	if option["type"] == "skill":
		var set_id := SkillDB.set_of(option["id"])
		var rune := UiTheme.rune(set_id, "m")
		return rune if rune != null else AssetDB.get_texture("proj_" + set_id)
	return AssetDB.get_texture("pickup_material")


func _icon_tint(option: Dictionary) -> Color:
	if option["type"] == "skill":
		return Color.WHITE
	return TYPE_COLORS["passive"]


func _set_hot(index: int) -> void:
	for i in _frames.size():
		_frames[i].hot = i == index


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
