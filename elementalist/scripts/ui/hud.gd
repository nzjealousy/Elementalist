extends CanvasLayer
## Combat HUD drawn in code: HP / mana / stamina bars, element tabs (1-3), the selected
## element's LMB and Q skills with cooldowns, and the RMB physical attack.

const SLOT := 20.0
const GAP := 3.0

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


func _draw_hud() -> void:
	if _player == null:
		return
	var caster: SkillCaster = _player.caster
	var font := ThemeDB.fallback_font

	_bar(Vector2(4, 4), Vector2(80, 6), _player.hp / _player.max_hp, Color("d9423b"))
	_bar(Vector2(4, 12), Vector2(80, 4), caster.mana / caster.max_mana, Color("3f7fff"))
	_bar(Vector2(4, 18), Vector2(80, 4), _player.stamina / _player.max_stamina, Color("e0c040"))
	var character := Game.character
	_ctrl.draw_string(font, Vector2(88, 10), "Lv %d  HP %.1f" % [character.level, _player.hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color.WHITE)
	var xp_frac := float(character.xp) / float(CharacterData.xp_to_next(character.level))
	_bar(Vector2(4, 24), Vector2(80, 3), xp_frac, Color("ffd84a"))
	if character.unspent_points > 0:
		_ctrl.draw_string(font, Vector2(88, 20), "%d points to spend (C)" % character.unspent_points, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("ffd84a"))
	if Game.banner_time > 0.0:
		var alpha := clampf(Game.banner_time, 0.0, 1.0)
		_ctrl.draw_multiline_string(font, Vector2(0, 40), Game.banner_text, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 8, -1, Color(1, 0.95, 0.7, alpha))
	_ctrl.draw_string(font, Vector2(0, 8), "C sheet  N new character  F5 sandbox  F10 attune", HORIZONTAL_ALIGNMENT_RIGHT, 316.0, 5, Color(1, 1, 1, 0.45))

	# Layout: [1..5] element tabs, gap, LMB, Q, RMB (just RMB if no castable elements)
	var count := caster.elements.size()
	var slots := (count + 3) if count > 0 else 1
	var width := slots * (SLOT + GAP) + (GAP * 2.0 if count > 0 else 0.0)
	var x := (320.0 - width) * 0.5
	var y := 154.0
	if count == 0:
		_melee_slot(Vector2(x, y))
		return

	for i in count:
		var element := caster.elements[i]
		var rect := Rect2(Vector2(x, y + 4.0), Vector2(SLOT, SLOT - 4.0))
		var color := Elements.color_of(element)
		var active := i == caster.selected
		_ctrl.draw_rect(rect, Color(color, 0.9 if active else 0.25))
		_ctrl.draw_rect(rect, Color.WHITE if active else Color.BLACK, false, 1.0)
		_ctrl.draw_string(font, rect.position + Vector2(2, 8), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.BLACK if active else Color.WHITE)
		_ctrl.draw_string(font, rect.position + Vector2(2, 14), element.substr(0, 3), HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color.BLACK if active else Color.WHITE)
		x += SLOT + GAP

	x += GAP * 2.0
	_skill_slot(Vector2(x, y), caster, caster.skill_for("primary"), "LMB")
	x += SLOT + GAP
	_skill_slot(Vector2(x, y), caster, caster.skill_for("area"), "Q")
	x += SLOT + GAP
	_melee_slot(Vector2(x, y))


func _skill_slot(pos: Vector2, caster: SkillCaster, skill_id: String, key: String) -> void:
	var def: Dictionary = SkillDB.DEFS[skill_id]
	var font := ThemeDB.fallback_font
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
	_ctrl.draw_rect(rect, Color.BLACK, false, 1.0)
	_ctrl.draw_string(font, pos + Vector2(2, 7), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
	if learned:
		_ctrl.draw_string(font, pos + Vector2(2, 17), String(def["name"]).substr(0, 4), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
	else:
		_ctrl.draw_string(font, pos + Vector2(2, 17), "Lv%d" % Game.character.skill_unlock_level(skill_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("ffd84a"))


func _melee_slot(pos: Vector2) -> void:
	var m: Dictionary = SkillDB.MELEE
	var font := ThemeDB.fallback_font
	var rect := Rect2(pos, Vector2(SLOT, SLOT))
	_ctrl.draw_rect(rect, Color(0.75, 0.75, 0.78, 0.6))
	if _player.stamina < float(m["stamina"]):
		_ctrl.draw_rect(rect, Color(0, 0, 0, 0.55))
	_ctrl.draw_rect(rect, Color.BLACK, false, 1.0)
	_ctrl.draw_string(font, pos + Vector2(2, 7), "RMB", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
	_ctrl.draw_string(font, pos + Vector2(2, 17), String(m["name"]).substr(0, 4), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)


func _bar(pos: Vector2, size: Vector2, frac: float, color: Color) -> void:
	_ctrl.draw_rect(Rect2(pos, size), Color(0, 0, 0, 0.6))
	_ctrl.draw_rect(Rect2(pos, Vector2(size.x * clampf(frac, 0.0, 1.0), size.y)), color)
	_ctrl.draw_rect(Rect2(pos, size), Color.BLACK, false, 1.0)
