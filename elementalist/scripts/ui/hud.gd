extends CanvasLayer
## Combat HUD drawn in code and kept small: thin HP / mana / stamina / XP bars and the level and
## gold in the top-left corner, the run text top-right, the boss bar top-centre, and two groups along
## the bottom: bottom left the element tabs (1-5); bottom right the actions: Fuse (LMB), Slash / Bolt
## (RMB), the lock (Q, showing the combo name and colour), and the abilities F, V and R.
## Each group is drawn relative to its corner of the view (which is wider than 320 in a wide window) and scaled by the
## "HUD size" setting, capped per area by layout() so the groups never meet or leave the view.

const SLOT := 18.0
const LOCK_SLOT := 26.0  # wider, so a combo's name fits
const GAP := 2.0
const BOTTOM := -22.0    # slots sit this far above the bottom edge (corner-relative)
const TOP_LEFT_X := 77.0  # where the level and gold text start, right of the bars
const BOSS_HALF := 70.0   # half the boss bar's width at its widest
const BOSS_MIN_HALF := 50.0  # the top corners shrink before the boss bar would be narrower than this
const GOLD := UiTheme.GOLD
const FRAME := Color("3c3868")   # the quiet edge of an obsidian slab
const INK := Color("0a0618")
const SLAB := Color("16122e")

static var _font_cache: Font

var _ctrl: Control
var _player: Node


func _ready() -> void:
	_ctrl = Control.new()
	_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ctrl)
	_ctrl.draw.connect(_draw_hud)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_ctrl.queue_redraw()


static func _hud_font() -> Font:
	if _font_cache == null:
		_font_cache = UiTheme.font()
	return _font_cache


## Draws the following until the next call relative to `corner`, at `scale`.
func _corner(corner: Vector2, scale: float) -> void:
	_ctrl.draw_set_transform(corner, 0.0, Vector2(scale, scale))


## How big each area is drawn and where its groups sit, for a view of `view` size at HUD size `scale`, with
## `elements` element tabs, the level/gold text `top_left_text` px wide (after TOP_LEFT_X), the run text `run_w` px and
## the boss name `boss_w` px (unscaled). "top" scales the top row, "bottom" the bottom groups; each is the setting,
## capped only where groups would otherwise meet: the two bottom groups must fit side by side, a boss bar of at least
## BOSS_MIN_HALF must fit beside the top-left block and the boss name beside the run text. "boss_half" is the bar's
## half width (it narrows, never moves, when the top-left text reaches into it). "rects" are the groups' screen
## rectangles (for the self-test).
static func layout(view: Vector2, scale: float, elements: int, top_left_text: float, run_w: float, boss_w: float) -> Dictionary:
	var left_w := (3.0 + elements * (SLOT + GAP) - GAP + 1.0) if elements > 0 else 0.0
	var right_w := (SLOT * 5.0 + LOCK_SLOT + GAP * 5.0 if elements > 0 else SLOT) + 4.0
	var bottom := minf(scale, (view.x - 4.0) / (left_w + right_w))
	var top_left_w := TOP_LEFT_X + top_left_text
	var run_box := run_w + 3.0 if run_w > 0.0 else 0.0
	# The bar shares its rows with the top-left block, the boss name with the run text (one row each).
	var top := minf(scale, (view.x * 0.5 - 3.0) / (top_left_w + BOSS_MIN_HALF + 1.0))
	if boss_w > 0.0 and run_box > 0.0:
		top = minf(top, (view.x * 0.5 - 2.0) / (run_box + boss_w * 0.5))
	var boss_half := clampf((view.x * 0.5 - 2.0 - top_left_w * top) / top - 1.0, BOSS_MIN_HALF, BOSS_HALF)
	var centre := view.x * 0.5
	return {
		"top": top, "bottom": bottom, "boss_half": boss_half,
		"rects": {
			"top_left": Rect2(0, 0, top_left_w * top, 20.0 * top),
			"top_right": Rect2(view.x - run_box * top, 0, run_box * top, 9.0 * top),
			"boss_name": Rect2(centre - boss_w * 0.5 * top, 0, boss_w * top, 9.0 * top),
			"boss_bar": Rect2(centre - (boss_half + 1.0) * top, 9.0 * top, (boss_half + 1.0) * 2.0 * top, 6.0 * top),
			"bottom_left": Rect2(0, view.y + (BOTTOM - 1.0) * bottom, left_w * bottom, (SLOT + 2.0) * bottom),
			"bottom_right": Rect2(view.x - right_w * bottom, view.y + (BOTTOM - 1.0) * bottom, right_w * bottom, (SLOT + 2.0) * bottom),
		},
	}


## layout() for what the HUD shows now.
func _layout(view: Vector2) -> Dictionary:
	var font := _hud_font()
	var character := Game.character
	var text_w := maxf(font.get_string_size("Lv %d" % character.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x,
		font.get_string_size("%dg" % character.inventory.gold, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x)
	var run_w := font.get_string_size(Game.run_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x if Game.run_text != "" else 0.0
	var boss_w := 0.0
	if is_instance_valid(Game.boss) and Game.boss is Enemy:
		boss_w = font.get_string_size((Game.boss as Enemy).display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	return layout(view, float(Settings.get_value("hud_scale")), _player.caster.elements.size(), text_w, run_w, boss_w)


func _draw_hud() -> void:
	if _player == null:
		return
	var caster: SkillCaster = _player.caster
	var character := Game.character
	var font := _hud_font()
	var view := _ctrl.size
	var lay := _layout(view)
	var top: float = lay["top"]

	_corner(Vector2.ZERO, top)  # top-left: bars, level, gold, what needs doing
	_bar(Vector2(3, 3), Vector2(70, 5), _player.hp / _player.max_hp, Color("e0403a"))
	if character.uses_mana():  # no elements, no mana pool
		_bar(Vector2(3, 9), Vector2(70, 3), caster.mana / caster.max_mana, Color("2a78e0"))
	_bar(Vector2(3, 13), Vector2(70, 3), _player.stamina / _player.max_stamina, Color("f8d060"))
	var xp_frac := float(character.xp) / float(CharacterData.xp_to_next(character.level))
	_bar(Vector2(3, 17), Vector2(70, 2), xp_frac, Color("b868ff"))
	_ctrl.draw_string(font, Vector2(TOP_LEFT_X, 8), "Lv %d" % character.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, GOLD)
	var inv := character.inventory
	_ctrl.draw_string(font, Vector2(TOP_LEFT_X, 16), "%dg" % inv.gold, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("f8e8b8"))
	_draw_status(font, caster, character)
	_draw_buffs(font)

	_corner(Vector2(view.x, 0), top)  # top-right: where you are in the dungeon
	if Game.run_text != "":
		_ctrl.draw_string(font, Vector2(-203, 8), Game.run_text, HORIZONTAL_ALIGNMENT_RIGHT, 200.0, 6, GOLD)

	_corner(Vector2(view.x * 0.5, 0), top)  # top-centre: the boss, then the banner
	_draw_boss_bar(font, lay["boss_half"])
	if Game.banner_time > 0.0:
		var alpha := clampf(Game.banner_time, 0.0, 1.0)
		_ctrl.draw_multiline_string(font, Vector2(-view.x * 0.5 / top, 46), Game.banner_text, HORIZONTAL_ALIGNMENT_CENTER, view.x / top, 7, -1, Color(1, 0.95, 0.7, alpha))

	_corner(Vector2(0, view.y), lay["bottom"])  # bottom-left: the elements
	_draw_elements(font, caster)
	_corner(view, lay["bottom"])  # bottom-right: the actions
	_draw_actions(font, caster)

	_ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hurt(view)


## An obsidian slab under one ink outline. `lit` glows in `color` (the slot's element); otherwise a quiet stone edge.
func _slab(rect: Rect2, color: Color, lit: bool) -> void:
	_ctrl.draw_rect(rect.grow(1.0), INK)
	_ctrl.draw_rect(rect, SLAB)
	if lit:
		_ctrl.draw_rect(rect.grow(-1.0), Color(color, 0.2))
	_ctrl.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1.0)), color if lit else FRAME)       # the lit top edge
	_ctrl.draw_rect(Rect2(rect.position, Vector2(1.0, rect.size.y)), color if lit else FRAME)
	_ctrl.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 1.0), Vector2(rect.size.x, 1.0)), Color(color if lit else FRAME, 0.55))
	_ctrl.draw_rect(Rect2(rect.position + Vector2(rect.size.x - 1.0, 0), Vector2(1.0, rect.size.y)), Color(color if lit else FRAME, 0.55))


## The element's rune picture (18 px) with its top-left corner at `at`.
func _rune(element: String, at: Vector2, alpha: float = 1.0) -> void:
	var texture := UiTheme.rune(element, "s")
	if texture != null:
		_ctrl.draw_texture(texture, at, Color(1, 1, 1, alpha))


## Text with a one pixel ink shadow, so it reads on any slab (ink text on a pale slab needs none).
func _label(font: Font, at: Vector2, text: String, size: int, color: Color, width: float = -1.0) -> void:
	if color.get_luminance() > 0.2:
		_ctrl.draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, width, size, Color(INK, 0.9))
	_ctrl.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, width, size, color)


## Bottom left: the element tabs, each a rune on an obsidian slab. The selected one is lit in its colour; a locked one
## carries a small lit mark.
func _draw_elements(font: Font, caster: SkillCaster) -> void:
	var x := 3.0
	var y := BOTTOM
	for i in caster.elements.size():
		var element := caster.elements[i]
		var rect := Rect2(Vector2(x, y), Vector2(SLOT, SLOT))
		var color := Elements.color_of(element)
		var active := i == caster.selected
		_slab(rect, color, active)
		_rune(element, rect.position, 1.0 if active else 0.5)
		_label(font, rect.position + Vector2(2, 6), str(i + 1), 5, Color.WHITE if active else Color(1, 1, 1, 0.75))
		if element in caster.locked:
			var mark := Rect2(rect.position + Vector2(rect.size.x - 5, 2), Vector2(3, 3))
			_ctrl.draw_rect(mark.grow(1.0), INK)
			_ctrl.draw_rect(mark, color.lightened(0.55))
		x += SLOT + GAP


## Bottom right: Fuse (LMB), Attack (RMB), the lock (Q) showing the combo it makes, then the
## abilities F (area), V (buff or debuff) and R (special).
func _draw_actions(font: Font, caster: SkillCaster) -> void:
	var y := BOTTOM
	if caster.elements.is_empty():
		_melee_slot(Vector2(-3.0 - SLOT, y))
		return
	var widths := [SLOT, SLOT, LOCK_SLOT, SLOT, SLOT, SLOT]
	var x := -3.0 + GAP
	for width in widths:
		x -= width + GAP
	_lmb_slot(Vector2(x, y), caster)
	x += SLOT + GAP
	_rmb_slot(Vector2(x, y), caster)
	x += SLOT + GAP
	_lock_slot(Vector2(x, y), caster)
	x += LOCK_SLOT + GAP
	_skill_slot(Vector2(x, y), caster, caster.skill_for("area"), "F")
	x += SLOT + GAP
	_skill_slot(Vector2(x, y), caster, caster.skill_for("support"), "V")
	x += SLOT + GAP
	_skill_slot(Vector2(x, y), caster, caster.skill_for("special"), "R")


## The boss's name and health at the top centre; the bar reaches `half` px either side of the middle.
func _draw_boss_bar(font: Font, half: float = BOSS_HALF) -> void:
	if not is_instance_valid(Game.boss):  # checked before any cast: a slain boss is freed
		return
	var boss := Game.boss as Enemy
	if boss == null or boss.hp <= 0.0:
		return
	_ctrl.draw_string(font, Vector2(-160, 8), boss.display_name, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 7, Color("ffb080"))
	_bar(Vector2(-half, 10), Vector2(half * 2.0, 4), boss.hp / boss.max_hp, Color("e0403a"))


## Active buffs under the gold line: name and seconds left.
func _draw_buffs(font: Font) -> void:
	var y := 36.0
	for kind in _player.buffs:
		var buff: Dictionary = _player.buffs[kind]
		var color: Color = _player.BUFF_COLORS.get(kind, Color.WHITE)
		_ctrl.draw_rect(Rect2(Vector2(3, y - 4), Vector2(3, 4)), color)
		_ctrl.draw_string(font, Vector2(8, y), "%s %.0fs" % [_player.BUFF_NAMES.get(kind, kind), buff["time"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 5, color)
		y += 6.0


## The hit indicator: the screen edges flash red and an arrow points at where the hit came from.
func _draw_hurt(view: Vector2) -> void:
	if Game.hurt_time <= 0.0:
		return
	var strength := Game.hurt_time / Game.HURT_TIME
	var edge := Color(0.9, 0.1, 0.1, 0.35 * strength)
	_ctrl.draw_rect(Rect2(0, 0, view.x, 8), edge)
	_ctrl.draw_rect(Rect2(0, view.y - 8.0, view.x, 8), edge)
	_ctrl.draw_rect(Rect2(0, 0, 8, view.y), edge)
	_ctrl.draw_rect(Rect2(view.x - 8.0, 0, 8, view.y), edge)
	if Game.hurt_dir != Vector2.ZERO:
		var centre := view * 0.5 + Game.hurt_dir * 38.0
		var side := Game.hurt_dir.orthogonal()
		var tip := centre + Game.hurt_dir * 7.0
		_ctrl.draw_colored_polygon(PackedVector2Array([tip, centre + side * 5.0, centre - side * 5.0]), Color(1.0, 0.25, 0.25, 0.85 * strength))


## One gold line when something needs you (points, choices, rewards), a coloured note while the blade
## is imbued, and - if tips are on - one dim hint about what the character cannot do yet.
func _draw_status(font: Font, caster: SkillCaster, character: CharacterData) -> void:
	var todo: Array[String] = []
	if character.unspent_points > 0:
		todo.append("%d point%s" % [character.unspent_points, "" if character.unspent_points == 1 else "s"])
	if character.can_choose_class():
		todo.append("class")
	if not character.available_subclasses().is_empty():
		todo.append("subclass")
	if not character.pending_rewards.is_empty():
		todo.append("%d reward%s" % [character.pending_rewards.size(), "" if character.pending_rewards.size() == 1 else "s"])
	var y := 26.0
	if not todo.is_empty():
		_ctrl.draw_string(font, Vector2(3, y), "! TAB: " + ", ".join(todo), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, GOLD)
		y += 7.0
	var elements: Array[String] = _player.imbue_elements()
	if _player.imbued and not elements.is_empty():
		_ctrl.draw_string(font, Vector2(3, y), "Imbued: %s" % String(elements[0]).capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Elements.color_of(elements[0]).lightened(0.3))
		y += 7.0
	if Settings.get_value("show_tips"):
		var tip := ""
		if caster.lmb_mode() == "locked":
			tip = "Q locks elements; Fuse needs two" if caster.lock_available() else "Fuse needs two elements"
		elif not character.castable_elements().is_empty() and not _player.imbued and Classes.style_of(character.class_id) == "ranged":
			tip = "E imbues: RMB then shoots bolts"
		if tip != "":
			_label(font, Vector2(3, y), tip, 5, Color(1, 1, 1, 0.65))  # dim, but it must still read on a bright floor


## LMB: "Fuse" (the fused cast), or "Slash" / "Knife" for characters with no elements. While
## fewer than two elements are locked the Fuse slot is dimmed: it can't be used.
func _lmb_slot(pos: Vector2, caster: SkillCaster) -> void:
	match caster.lmb_mode():
		"fusion":
			_fusion_slot(pos, caster, caster.primary_id())
		"knife":
			_skill_slot(pos, caster, caster.primary_id(), "LMB", "Knife")
		"slash":
			_plain_slot(pos, "LMB", "Slash", Color("9090c0"))
		_:
			_plain_slot(pos, "LMB", "Fuse", Color(0.2, 0.22, 0.3, 0.9))
			_ctrl.draw_rect(Rect2(pos, Vector2(SLOT, SLOT)), Color(0, 0, 0, 0.45))


## RMB: "Bolt" (ranged class, imbued) or "Slash". The colour follows the imbued element.
func _rmb_slot(pos: Vector2, caster: SkillCaster) -> void:
	if caster.rmb_mode() == "bolt":
		_skill_slot(pos, caster, caster.bolt_id(), "RMB", "Bolt")
	else:
		_melee_slot(pos)


func _fusion_slot(pos: Vector2, caster: SkillCaster, id: String) -> void:
	var font := _hud_font()
	var rect := Rect2(pos, Vector2(SLOT, SLOT))
	var parts := caster.locked
	var stripe := SLOT / parts.size()
	_slab(rect, Elements.color_of(parts[0]), true)
	for i in parts.size():  # one coloured band per fused element
		_ctrl.draw_rect(Rect2(pos + Vector2(i * stripe, 0), Vector2(stripe, SLOT)).grow(-1.0), Color(Elements.color_of(parts[i]), 0.45))
	var cd := caster.cooldown_fraction(id)
	if cd > 0.0:
		_ctrl.draw_rect(Rect2(pos, Vector2(SLOT, SLOT * cd)), Color(INK, 0.7))
	if not caster.can_afford(id):
		_ctrl.draw_rect(rect, Color(0.05, 0.1, 0.35, 0.45))
	_label(font, pos + Vector2(2, 6), "LMB", 5, Color(1, 1, 1, 0.8))
	_label(font, pos + Vector2(2, 17), "Fuse", 6, Color.WHITE)
	_label(font, pos + Vector2(SLOT - 4.0, 6), str(parts.size()), 5, GOLD)  # how many are fused; "x2" ran into "LMB"


## Q: shows the combination the locked elements make: the pair's combo name and colour for two
## ("Steam"), "Trio" / "Quartet" / "Prism" for more, the element itself for one, "Lock" for none.
func _lock_slot(pos: Vector2, caster: SkillCaster) -> void:
	var font := _hud_font()
	var rect := Rect2(pos, Vector2(LOCK_SLOT, SLOT))
	var available := caster.lock_available()
	var label: Dictionary = Elements.fusion_label(caster.locked)
	_slab(rect, label["color"], not caster.locked.is_empty())
	if not caster.locked.is_empty():
		if caster.locked.size() >= 3:  # a stripe per element
			var stripe := LOCK_SLOT / caster.locked.size()
			for i in caster.locked.size():
				_ctrl.draw_rect(Rect2(pos + Vector2(i * stripe, 0), Vector2(stripe, SLOT)).grow(-1.0), Color(Elements.color_of(caster.locked[i]), 0.5))
		else:
			_ctrl.draw_rect(rect.grow(-1.0), Color(label["color"], 0.45))
	# A pale combo (Steam, Frost ...) lights the slab almost white: its text turns to ink there.
	var pale: bool = not caster.locked.is_empty() and caster.locked.size() < 3 and Color(label["color"]).get_luminance() > 0.6
	_label(font, pos + Vector2(2, 6), "Q", 5, INK if pale else Color(1, 1, 1, 0.8))
	var text := String(label["name"]).substr(0, 8)
	if not available:  # needs two elements to have anything to fuse
		text = "none" if Game.character.castable_elements().is_empty() else "2 el"
		_ctrl.draw_rect(rect, Color(INK, 0.55))
	_label(font, pos + Vector2(2, 17), text, 5, INK if pale and available else Color.WHITE, LOCK_SLOT - 3.0)


## F, V and R: key at the top, the skill's name below, the skill's element rune behind. A gold edge marks the chain
## discount: the next ability of a different element than your last costs less mana.
func _skill_slot(pos: Vector2, caster: SkillCaster, skill_id: String, key: String, name_override: String = "") -> void:
	var def: Dictionary = SkillDB.DEFS[skill_id]
	var font := _hud_font()
	var rect := Rect2(pos, Vector2(SLOT, SLOT))
	var element := SkillDB.set_of(skill_id)
	var learned := Game.character.can_use_skill(skill_id)
	var chained := learned and caster.chain_discount(skill_id) < 1.0
	_slab(rect, GOLD if chained else Elements.color_of(element), chained)
	_rune(element, pos, 0.55 if learned else 0.2)
	var cd := caster.cooldown_fraction(skill_id)
	if cd > 0.0:
		_ctrl.draw_rect(Rect2(pos, Vector2(SLOT, SLOT * cd)), Color(INK, 0.7))
	if not learned:
		_ctrl.draw_rect(rect, Color(INK, 0.55))
	elif not caster.can_afford(skill_id):
		_ctrl.draw_rect(rect, Color(0.05, 0.1, 0.35, 0.45))
	_label(font, pos + Vector2(2, 6), key, 5, Color(1, 1, 1, 0.85))
	if learned:
		var label := name_override if name_override != "" else String(def["name"]).substr(0, 4)
		_label(font, pos + Vector2(2, 17), label, 6, Color.WHITE, SLOT - 3.0)
	else:
		var level := Game.character.skill_unlock_level(skill_id)
		_label(font, pos + Vector2(2, 17), ("Lv%d" % level) if level > 0 else "Rwd", 6, Color("f8d060"))


func _plain_slot(pos: Vector2, key: String, label: String, color: Color, lit: bool = false) -> void:
	var font := _hud_font()
	var rect := Rect2(pos, Vector2(SLOT, SLOT))
	_slab(rect, color, lit)
	_rune("martial" if label == "Slash" or label == "Knife" else "", pos, 0.45)
	_label(font, pos + Vector2(2, 6), key, 5, Color(1, 1, 1, 0.85))
	_label(font, pos + Vector2(2, 17), label, 6, Color.WHITE, SLOT - 3.0)


## The slash (RMB): grey normally, the imbued element's colour while the blade is coated.
func _melee_slot(pos: Vector2) -> void:
	var m: Dictionary = SkillDB.MELEE
	var rect := Rect2(pos, Vector2(SLOT, SLOT))
	var imbued_elements: Array[String] = _player.imbue_elements()
	var color := Color("9090c0")
	var lit: bool = _player.imbued and not imbued_elements.is_empty()
	if lit:
		color = Elements.color_of(imbued_elements[0])
	_plain_slot(pos, "RMB", "Slash", color, lit)
	if _player.stamina < float(m["stamina"]):
		_ctrl.draw_rect(rect, Color(INK, 0.55))


func _bar(pos: Vector2, size: Vector2, frac: float, color: Color) -> void:
	frac = clampf(frac, 0.0, 1.0)
	_ctrl.draw_rect(Rect2(pos - Vector2.ONE, size + Vector2(2, 2)), INK)  # the one ink outline
	_ctrl.draw_rect(Rect2(pos, size), Color("0c0a1a"))
	var fill := Rect2(pos, Vector2(size.x * frac, size.y))
	_ctrl.draw_rect(fill, color.darkened(0.15))
	if size.y >= 3.0 and fill.size.x > 0.0:  # a lit top line and a bright tip: the bar glows rather than fills
		_ctrl.draw_rect(Rect2(fill.position, Vector2(fill.size.x, 1.0)), color.lightened(0.4))
		_ctrl.draw_rect(Rect2(fill.position + Vector2(maxf(fill.size.x - 1.0, 0.0), 0), Vector2(1.0, size.y)), color.lightened(0.55))
