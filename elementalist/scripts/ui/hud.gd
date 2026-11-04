extends CanvasLayer
## Combat HUD drawn in code and kept small: thin HP / mana / stamina / XP bars and the level and
## gold in the top-left corner, the run text top-right, the boss bar top-centre, and two groups along
## the bottom: bottom left the element tabs (1-5); bottom right the actions: Fuse (LMB), Slash / Bolt
## (RMB), the lock (Q, showing the combo name and colour), and the abilities F, V and R.
## Each corner group is drawn relative to its corner and scaled by the "HUD size" setting.

const SLOT := 18.0
const LOCK_SLOT := 26.0  # wider, so a combo's name fits
const GAP := 2.0
const BOTTOM := -22.0    # slots sit this far above the bottom edge (corner-relative)
const GOLD := Color("f2cf6a")
const FRAME := Color("4a3512")

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


## Draws the following until the next call relative to `corner`, at the HUD size setting.
func _corner(corner: Vector2) -> void:
	var scale := float(Settings.get_value("hud_scale"))
	_ctrl.draw_set_transform(corner, 0.0, Vector2(scale, scale))


func _draw_hud() -> void:
	if _player == null:
		return
	var caster: SkillCaster = _player.caster
	var character := Game.character
	var font := _hud_font()

	_corner(Vector2.ZERO)  # top-left: bars, level, gold, what needs doing
	_bar(Vector2(3, 3), Vector2(70, 5), _player.hp / _player.max_hp, Color("c8372f"))
	if character.uses_mana():  # no elements, no mana pool
		_bar(Vector2(3, 9), Vector2(70, 3), caster.mana / caster.max_mana, Color("3f7fff"))
	_bar(Vector2(3, 13), Vector2(70, 3), _player.stamina / _player.max_stamina, Color("d6b13a"))
	var xp_frac := float(character.xp) / float(CharacterData.xp_to_next(character.level))
	_bar(Vector2(3, 17), Vector2(70, 2), xp_frac, Color("a98fe8"))
	_ctrl.draw_string(font, Vector2(77, 8), "Lv %d" % character.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, GOLD)
	var inv := character.inventory
	_ctrl.draw_string(font, Vector2(77, 16), "%dg" % inv.gold, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("e8d8a0"))
	_draw_status(font, caster, character)
	_draw_buffs(font)

	_corner(Vector2(320, 0))  # top-right: where you are in the dungeon
	if Game.run_text != "":
		_ctrl.draw_string(font, Vector2(-203, 8), Game.run_text, HORIZONTAL_ALIGNMENT_RIGHT, 200.0, 6, GOLD)

	_corner(Vector2(160, 0))  # top-centre: the boss, then the banner
	_draw_boss_bar(font)
	if Game.banner_time > 0.0:
		var alpha := clampf(Game.banner_time, 0.0, 1.0)
		_ctrl.draw_multiline_string(font, Vector2(-160, 46), Game.banner_text, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 7, -1, Color(1, 0.95, 0.7, alpha))

	_corner(Vector2(0, 180))  # bottom-left: the elements
	_draw_elements(font, caster)
	_corner(Vector2(320, 180))  # bottom-right: the actions
	_draw_actions(font, caster)

	_ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hurt()


## Bottom left: the element tabs (1-5), the selected one lit, a white mark on each locked one.
func _draw_elements(font: Font, caster: SkillCaster) -> void:
	var x := 3.0
	var y := BOTTOM - 4.0
	for i in caster.elements.size():
		var element := caster.elements[i]
		var rect := Rect2(Vector2(x, y + 4.0), Vector2(SLOT, SLOT - 4.0))
		var color := Elements.color_of(element)
		var active := i == caster.selected
		_ctrl.draw_rect(rect, Color(color, 0.9 if active else 0.25))
		_ctrl.draw_rect(rect, Color.WHITE if active else FRAME, false, 1.0)
		_ctrl.draw_string(font, rect.position + Vector2(2, 8), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.BLACK if active else Color.WHITE)
		_ctrl.draw_string(font, rect.position + Vector2(2, 14), element.substr(0, 3), HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color.BLACK if active else Color.WHITE)
		if element in caster.locked:
			_ctrl.draw_rect(Rect2(rect.position + Vector2(rect.size.x - 4, 0), Vector2(4, 4)), Color.WHITE)  # locked marker
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


## The boss's name and health along the bottom, above the skill slots.
func _draw_boss_bar(font: Font) -> void:
	if not is_instance_valid(Game.boss):  # checked before any cast: a slain boss is freed
		return
	var boss := Game.boss as Enemy
	if boss == null or boss.hp <= 0.0:
		return
	_ctrl.draw_string(font, Vector2(-160, 8), boss.display_name, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 7, Color("ff9a6a"))
	_bar(Vector2(-70, 10), Vector2(140, 4), boss.hp / boss.max_hp, Color("c0392b"))


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
func _draw_hurt() -> void:
	if Game.hurt_time <= 0.0:
		return
	var strength := Game.hurt_time / Game.HURT_TIME
	var edge := Color(0.9, 0.1, 0.1, 0.35 * strength)
	_ctrl.draw_rect(Rect2(0, 0, 320, 8), edge)
	_ctrl.draw_rect(Rect2(0, 172, 320, 8), edge)
	_ctrl.draw_rect(Rect2(0, 0, 8, 180), edge)
	_ctrl.draw_rect(Rect2(312, 0, 8, 180), edge)
	if Game.hurt_dir != Vector2.ZERO:
		var centre := Vector2(160, 90) + Game.hurt_dir * 38.0
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
			_ctrl.draw_string(font, Vector2(3, y), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color(1, 1, 1, 0.4))


## LMB: "Fuse" (the fused cast), or "Slash" / "Knife" for characters with no elements. While
## fewer than two elements are locked the Fuse slot is dimmed: it can't be used.
func _lmb_slot(pos: Vector2, caster: SkillCaster) -> void:
	match caster.lmb_mode():
		"fusion":
			_fusion_slot(pos, caster, caster.primary_id())
		"knife":
			_skill_slot(pos, caster, caster.primary_id(), "LMB", "Knife")
		"slash":
			_plain_slot(pos, "LMB", "Slash", Color(0.75, 0.75, 0.78, 0.6))
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
	for i in parts.size():  # one coloured band per fused element
		_ctrl.draw_rect(Rect2(pos + Vector2(i * stripe, 0), Vector2(stripe, SLOT)), Color(Elements.color_of(parts[i]), 0.65))
	var cd := caster.cooldown_fraction(id)
	if cd > 0.0:
		_ctrl.draw_rect(Rect2(pos, Vector2(SLOT, SLOT * cd)), Color(0, 0, 0, 0.65))
	if not caster.can_afford(id):
		_ctrl.draw_rect(rect, Color(0, 0, 0.3, 0.45))
	_ctrl.draw_rect(rect, FRAME, false, 1.0)
	_ctrl.draw_string(font, pos + Vector2(2, 6), "LMB", HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color(1, 1, 1, 0.7))
	_ctrl.draw_string(font, pos + Vector2(2, 17), "Fuse", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
	_ctrl.draw_string(font, pos + Vector2(12, 6), "x%d" % parts.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color.WHITE)


## Q: shows the combination the locked elements make: the pair's combo name and colour for two
## ("Steam"), "Trio" / "Quartet" / "Prism" for more, the element itself for one, "Lock" for none.
func _lock_slot(pos: Vector2, caster: SkillCaster) -> void:
	var font := _hud_font()
	var rect := Rect2(pos, Vector2(LOCK_SLOT, SLOT))
	var available := caster.lock_available()
	var label: Dictionary = Elements.fusion_label(caster.locked)
	_ctrl.draw_rect(rect, Color(0.18, 0.2, 0.28, 0.9))
	if not caster.locked.is_empty():
		if caster.locked.size() >= 3:  # a stripe per element
			var stripe := LOCK_SLOT / caster.locked.size()
			for i in caster.locked.size():
				_ctrl.draw_rect(Rect2(pos + Vector2(i * stripe, 0), Vector2(stripe, SLOT)), Color(Elements.color_of(caster.locked[i]), 0.55))
		else:
			_ctrl.draw_rect(rect, Color(label["color"], 0.7))
	_ctrl.draw_rect(rect, FRAME, false, 1.0)
	_ctrl.draw_string(font, pos + Vector2(2, 6), "Q", HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color(1, 1, 1, 0.7))
	var text := String(label["name"]).substr(0, 8)
	var dark := not caster.locked.is_empty() and Color(label["color"]).get_luminance() > 0.6
	if not available:  # needs two elements to have anything to fuse
		text = "none" if Game.character.castable_elements().is_empty() else "2 el"
		_ctrl.draw_rect(rect, Color(0, 0, 0, 0.55))
	_ctrl.draw_string(font, pos + Vector2(2, 17), text, HORIZONTAL_ALIGNMENT_LEFT, LOCK_SLOT - 3.0, 5, Color.BLACK if dark else Color.WHITE)


## F, V and R: key at the top, the skill's name below. A gold frame marks the chain discount:
## the next ability of a different element than your last costs less mana.
func _skill_slot(pos: Vector2, caster: SkillCaster, skill_id: String, key: String, name_override: String = "") -> void:
	var def: Dictionary = SkillDB.DEFS[skill_id]
	var font := _hud_font()
	var rect := Rect2(pos, Vector2(SLOT, SLOT))
	_ctrl.draw_rect(rect, Color(Elements.color_of(SkillDB.set_of(skill_id)), 0.6))
	var cd := caster.cooldown_fraction(skill_id)
	if cd > 0.0:
		_ctrl.draw_rect(Rect2(pos, Vector2(SLOT, SLOT * cd)), Color(0, 0, 0, 0.65))
	var learned := Game.character.can_use_skill(skill_id)
	if not learned:
		_ctrl.draw_rect(rect, Color(0, 0, 0, 0.75))
	elif not caster.can_afford(skill_id):
		_ctrl.draw_rect(rect, Color(0, 0, 0.3, 0.45))
	var chained := learned and caster.chain_discount(skill_id) < 1.0
	_ctrl.draw_rect(rect, GOLD if chained else FRAME, false, 1.0)
	_ctrl.draw_string(font, pos + Vector2(2, 6), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color(1, 1, 1, 0.7))
	if learned:
		var label := name_override if name_override != "" else String(def["name"]).substr(0, 4)
		_ctrl.draw_string(font, pos + Vector2(2, 17), label, HORIZONTAL_ALIGNMENT_LEFT, SLOT - 3.0, 6, Color.WHITE)
	else:
		_ctrl.draw_string(font, pos + Vector2(2, 17), ("Lv%d" % Game.character.skill_unlock_level(skill_id)) if Game.character.skill_unlock_level(skill_id) > 0 else "Rwd", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("ffd84a"))


func _plain_slot(pos: Vector2, key: String, label: String, color: Color) -> void:
	var font := _hud_font()
	var rect := Rect2(pos, Vector2(SLOT, SLOT))
	_ctrl.draw_rect(rect, color)
	_ctrl.draw_rect(rect, FRAME, false, 1.0)
	_ctrl.draw_string(font, pos + Vector2(2, 6), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color(1, 1, 1, 0.7))
	_ctrl.draw_string(font, pos + Vector2(2, 17), label, HORIZONTAL_ALIGNMENT_LEFT, SLOT - 3.0, 6, Color.WHITE)


## The slash (RMB): grey normally, the imbued element's colour while the blade is coated.
func _melee_slot(pos: Vector2) -> void:
	var m: Dictionary = SkillDB.MELEE
	var rect := Rect2(pos, Vector2(SLOT, SLOT))
	var imbued_elements: Array[String] = _player.imbue_elements()
	var color := Color(0.75, 0.75, 0.78, 0.6)
	if _player.imbued and not imbued_elements.is_empty():
		color = Color(Elements.color_of(imbued_elements[0]), 0.85)
	_plain_slot(pos, "RMB", "Slash", color)
	if _player.stamina < float(m["stamina"]):
		_ctrl.draw_rect(rect, Color(0, 0, 0, 0.55))


func _bar(pos: Vector2, size: Vector2, frac: float, color: Color) -> void:
	_ctrl.draw_rect(Rect2(pos, size), Color(0.05, 0.03, 0.02, 0.75))
	_ctrl.draw_rect(Rect2(pos, Vector2(size.x * clampf(frac, 0.0, 1.0), size.y)), color)
	_ctrl.draw_rect(Rect2(pos - Vector2(0.5, 0.5), size + Vector2(1, 1)), FRAME, false, 1.0)
