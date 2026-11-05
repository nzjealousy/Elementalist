class_name DungeonSelect
extends CanvasLayer
## The camp gate's choice of dungeon, as cards (Game.TIERS). A dungeon opens once the one before it
## is cleared. Choosing one saves and starts the run. Esc / B / Back closes it.

var _open := false
var _theme: Theme
var _was_paused := false
var _detail: Label


func _init() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("dungeon_select")


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
		Sfx.ui("ui_back")
		close()


const ROMAN := ["I", "II", "III", "IV", "V"]
const CARD_SIZE := Vector2(58, 84)  # short enough that the whole screen fits the 180 px view
const DEFAULT_COLORS := {1: "c8503a", 2: "4aa0d8"}
const ORNAMENTS := {1: "flames", 2: "stars", 3: "leaves", 4: "spikes", 5: "rivets"}


func _build() -> void:
	for child in get_children():
		child.queue_free()
	UiKit.dim(self, 0.88)
	var column := UiKit.column(self, _theme, 304.0, 2)
	column.add_child(UiTheme.heading("The Gate", 10))
	column.add_child(UiKit.label("Choose a dungeon. Falling costs elements and 30% of your gold; clearing one pays well.", UiTheme.TEXT_DIM, 6, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiTheme.divider())
	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 3)
	column.add_child(cards)
	for tier in Game.TIERS:
		cards.add_child(_card(int(tier)))
	_detail = UiKit.label("", UiTheme.TEXT, 6, HORIZONTAL_ALIGNMENT_CENTER)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(280, 16)  # two lines of the longest description
	column.add_child(_detail)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	row.add_child(UiKit.button("Back", close, 70.0))
	UiKit.focus_first(cards)


func _card(tier: int) -> Control:
	var spec: Dictionary = Game.TIERS[tier]
	var unlocked := Game.tier_unlocked(tier)
	var cleared := int(Game.meta.get("tier_cleared", 0)) >= tier
	var tint := Color(String(spec.get("color", DEFAULT_COLORS.get(tier, "c8c8c8"))))
	if not unlocked:
		tint = tint.lerp(Color(0.35, 0.33, 0.33), 0.75)
	var holder := Control.new()
	holder.custom_minimum_size = CARD_SIZE
	var frame := CardFrame.for_kind(tint, String(ORNAMENTS.get(tier, "plain")))
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(frame)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 4
	box.offset_right = -4
	box.offset_top = 6
	box.offset_bottom = -4
	box.add_theme_constant_override("separation", 2)
	holder.add_child(box)
	box.add_child(UiKit.label(ROMAN[tier - 1], UiTheme.GOLD if unlocked else UiTheme.TEXT_DIM, 9, HORIZONTAL_ALIGNMENT_CENTER))
	var name_label := UiKit.label(String(spec["name"]).trim_prefix("The "), UiTheme.TEXT if unlocked else UiTheme.TEXT_DIM, 6, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(0, 18)  # room for a two-line name
	box.add_child(name_label)
	box.add_child(UiKit.label("%d floors" % int(spec["floors"]), UiTheme.TEXT_DIM, 5, HORIZONTAL_ALIGNMENT_CENTER))
	var status := "Cleared" if cleared else ("Locked" if not unlocked else "New")
	box.add_child(UiKit.label(status, UiTheme.GREEN if cleared else (UiTheme.RED if not unlocked else UiTheme.TEXT_DIM), 5, HORIZONTAL_ALIGNMENT_CENTER))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var enter := UiKit.button("Enter" if unlocked else "Locked", func(): Game.begin_run(tier), 0.0)
	enter.disabled = not unlocked
	var show := func():
		frame.hot = true
		_detail.text = String(spec["desc"]) if unlocked else "Clear the dungeon before it to open this one."
	enter.mouse_entered.connect(show)
	enter.focus_entered.connect(show)
	enter.mouse_exited.connect(func(): frame.hot = false)
	enter.focus_exited.connect(func(): frame.hot = false)
	box.add_child(enter)
	return holder
