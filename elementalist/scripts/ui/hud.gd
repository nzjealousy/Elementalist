extends CanvasLayer
## Combat HUD drawn in code: HP / mana / stamina / XP bars, a status line (points, pending
## choices, imbue and melee/ranged mode), the ceremony banner, the element tabs (1-5), and the
## action slots: LMB, Q (element lock), F (area), R (special), RMB (slash).

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
	var character := Game.character
	var font := ThemeDB.fallback_font

	_bar(Vector2(4, 4), Vector2(80, 6), _player.hp / _player.max_hp, Color("d9423b"))
	if character.uses_mana():  # no elements, no mana pool
		_bar(Vector2(4, 12), Vector2(80, 4), caster.mana / caster.max_mana, Color("3f7fff"))
	_bar(Vector2(4, 18), Vector2(80, 4), _player.stamina / _player.max_stamina, Color("e0c040"))
	_ctrl.draw_string(font, Vector2(88, 10), "Lv %d  HP %.1f" % [character.level, _player.hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color.WHITE)
	var xp_frac := float(character.xp) / float(CharacterData.xp_to_next(character.level))
	_bar(Vector2(4, 24), Vector2(80, 3), xp_frac, Color("ffd84a"))
	_draw_status(font, caster, character)
	if Game.banner_time > 0.0:
		var alpha := clampf(Game.banner_time, 0.0, 1.0)
		_ctrl.draw_multiline_string(font, Vector2(0, 62), Game.banner_text, HORIZONTAL_ALIGNMENT_CENTER, 320.0, 8, -1, Color(1, 0.95, 0.7, alpha))
	_ctrl.draw_string(font, Vector2(0, 8), "TAB sheet  N new  E imbue  Q lock  LMB fuse  RMB attack  F area  R special", HORIZONTAL_ALIGNMENT_RIGHT, 316.0, 5, Color(1, 1, 1, 0.45))

	# Layout: [1..5] element tabs, gap, LMB, RMB, Q, F, R (just RMB if no castable set)
	var count := caster.elements.size()
	var slots := (count + 5) if count > 0 else 1
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
		if element in caster.locked:
			_ctrl.draw_rect(Rect2(rect.position + Vector2(rect.size.x - 4, 0), Vector2(4, 4)), Color.WHITE)  # locked marker
		x += SLOT + GAP

	x += GAP * 2.0
	_lmb_slot(Vector2(x, y), caster)
	x += SLOT + GAP
	_rmb_slot(Vector2(x, y), caster)
	x += SLOT + GAP
	_lock_slot(Vector2(x, y), caster)
	x += SLOT + GAP
	_skill_slot(Vector2(x, y), caster, caster.skill_for("area"), "F")
	x += SLOT + GAP
	_skill_slot(Vector2(x, y), caster, caster.skill_for("special"), "R")


## Points to spend, pending choices, and how the character is fighting right now.
func _draw_status(font: Font, caster: SkillCaster, character: CharacterData) -> void:
	if character.unspent_points > 0:
		_ctrl.draw_string(font, Vector2(88, 18), "%d points to spend (TAB)" % character.unspent_points, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("ffd84a"))
	var todo: Array[String] = []
	if character.can_choose_class():
		todo.append("choose a class")
	if not character.available_subclasses().is_empty():
		todo.append("choose a subclass")
	if not character.pending_rewards.is_empty():
		todo.append("%d reward%s" % [character.pending_rewards.size(), "" if character.pending_rewards.size() == 1 else "s"])
	if not todo.is_empty():
		_ctrl.draw_string(font, Vector2(88, 26), "TAB: " + ", ".join(todo), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("ffd84a"))

	var elements: Array[String] = _player.imbue_elements()
	var names := "+".join(elements.map(func(e): return String(e).capitalize()))
	var text := ""
	var color := Color(1, 1, 1, 0.7)
	if _player.imbued and not elements.is_empty():
		text = "Imbued: %s" % names
		color = Elements.color_of(elements[0]).lightened(0.3)
	elif not character.castable_elements().is_empty():
		match Classes.style_of(character.class_id):
			"ranged":
				text = "Melee mode - E to imbue and shoot (RMB)"
			"melee":
				text = "E imbues the blade"
	if text != "":
		_ctrl.draw_string(font, Vector2(88, 34), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, color)
	if caster.lmb_mode() == "locked":
		var hint := "LMB needs 2-3 locked elements (Q)" if caster.lock_available() else "LMB needs 2+ elements to fuse"
		_ctrl.draw_string(font, Vector2(88, 42), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.45))


## LMB: the fused cast; a plain slash or knife throw for characters with no elements; or a
## dimmed, unusable slot while fewer than two elements are locked.
func _lmb_slot(pos: Vector2, caster: SkillCaster) -> void:
	match caster.lmb_mode():
		"fusion":
			_fusion_slot(pos, caster, caster.primary_id())
		"knife":
			_skill_slot(pos, caster, caster.primary_id(), "LMB")
		"slash":
			_plain_slot(pos, "LMB", "Slas", Color(0.75, 0.75, 0.78, 0.6))
		_:
			_plain_slot(pos, "LMB", "Q 2+", Color(0.2, 0.22, 0.3, 0.9))
			_ctrl.draw_rect(Rect2(pos, Vector2(SLOT, SLOT)), Color(0, 0, 0, 0.45))


## RMB: the slash, or the selected element's bolt for a ranged class while imbued.
func _rmb_slot(pos: Vector2, caster: SkillCaster) -> void:
	if caster.rmb_mode() == "bolt":
		_skill_slot(pos, caster, caster.bolt_id(), "RMB")
	else:
		_melee_slot(pos)


func _fusion_slot(pos: Vector2, caster: SkillCaster, id: String) -> void:
	var font := ThemeDB.fallback_font
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
	_ctrl.draw_rect(rect, Color.BLACK, false, 1.0)
	_ctrl.draw_string(font, pos + Vector2(2, 7), "LMB", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
	_ctrl.draw_string(font, pos + Vector2(2, 17), "Fuse%d" % parts.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)


## Q: shows up to three lock pips (filled = locked element).
func _lock_slot(pos: Vector2, caster: SkillCaster) -> void:
	var font := ThemeDB.fallback_font
	var rect := Rect2(pos, Vector2(SLOT, SLOT))
	var available := caster.lock_available()
	_ctrl.draw_rect(rect, Color(0.18, 0.2, 0.28, 0.9))
	_ctrl.draw_rect(rect, Color.BLACK, false, 1.0)
	_ctrl.draw_string(font, pos + Vector2(2, 7), "Q", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE if available else Color(1, 1, 1, 0.4))
	if not available:  # needs two elements to have anything to fuse
		var why := "none" if Game.character.castable_elements().is_empty() else "2 el"
		_ctrl.draw_string(font, pos + Vector2(2, 17), why, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.4))
		_ctrl.draw_rect(rect, Color(0, 0, 0, 0.55))
		return
	for i in Classes.MAX_LOCKED:
		var pip := Rect2(pos + Vector2(2 + i * 6, 11), Vector2(5, 6))
		if i < caster.locked.size():
			_ctrl.draw_rect(pip, Elements.color_of(caster.locked[i]))
		else:
			_ctrl.draw_rect(pip, Color(1, 1, 1, 0.2), false, 1.0)


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
		_ctrl.draw_string(font, pos + Vector2(2, 17), ("Lv%d" % Game.character.skill_unlock_level(skill_id)) if Game.character.skill_unlock_level(skill_id) > 0 else "Rwd", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("ffd84a"))


func _plain_slot(pos: Vector2, key: String, label: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var rect := Rect2(pos, Vector2(SLOT, SLOT))
	_ctrl.draw_rect(rect, color)
	_ctrl.draw_rect(rect, Color.BLACK, false, 1.0)
	_ctrl.draw_string(font, pos + Vector2(2, 7), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
	_ctrl.draw_string(font, pos + Vector2(2, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)


func _melee_slot(pos: Vector2) -> void:
	var m: Dictionary = SkillDB.MELEE
	var rect := Rect2(pos, Vector2(SLOT, SLOT))
	_plain_slot(pos, "RMB", String(m["name"]).substr(0, 4), Color(0.75, 0.75, 0.78, 0.6))
	if _player.stamina < float(m["stamina"]):
		_ctrl.draw_rect(rect, Color(0, 0, 0, 0.55))


func _bar(pos: Vector2, size: Vector2, frac: float, color: Color) -> void:
	_ctrl.draw_rect(Rect2(pos, size), Color(0, 0, 0, 0.6))
	_ctrl.draw_rect(Rect2(pos, Vector2(size.x * clampf(frac, 0.0, 1.0), size.y)), color)
	_ctrl.draw_rect(Rect2(pos, size), Color.BLACK, false, 1.0)
