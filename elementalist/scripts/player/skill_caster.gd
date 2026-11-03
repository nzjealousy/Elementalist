class_name SkillCaster
extends Node
## Owns mana, cooldowns and the selected skill set for a caster body. What it can cast comes
## from Game.character: only owned elements (plus the martial set for non-elementalists), and
## only skills the class has taught. Elemental skills cost mana; martial skills cost stamina,
## which lives on the body (see Player.spend_stamina).
##
## Controls: 1-5 or mouse wheel select a set, LMB (hold) casts its primary, Q its area skill.
## Every number that scales with the character (damage, radius, knockback, speed, cooldown,
## status potency) is resolved here at cast time from CharacterData.

signal cast(skill_id: String)
signal element_changed(element: String)  # also fires for the martial set

var body: Node2D
var max_mana := 100.0
var mana := 100.0
var mana_regen := 9.0
var elements: Array[String] = []  # selectable sets: owned elements, then "martial" if any
var selected := 0
var cooldowns: Dictionary = {}  # skill id -> seconds left


func _ready() -> void:
	refresh_elements()
	mana = max_mana
	Game.character.elements_changed.connect(refresh_elements)


## Re-read castable sets and mana stats from the character (e.g. after gaining an element).
func refresh_elements() -> void:
	elements = Game.character.castable_sets()
	selected = clampi(selected, 0, maxi(elements.size() - 1, 0))
	apply_stats()


func apply_stats() -> void:
	var d: Dictionary = Game.character.derived()
	max_mana = float(d["max_mana"])
	mana_regen = float(d["mana_regen"])
	mana = minf(mana, max_mana)


func selected_element() -> String:
	return elements[selected] if not elements.is_empty() else ""


func skill_for(slot: String) -> String:
	if elements.is_empty():
		return ""
	return SkillDB.LOADOUTS[selected_element()][slot]


func select(index: int) -> void:
	if index < 0 or index >= elements.size() or index == selected:
		return
	selected = index
	element_changed.emit(elements[index])


## Wraps around, so scrolling past the last set returns to the first.
func select_relative(step: int) -> void:
	if elements.is_empty():
		return
	select(posmod(selected + step, elements.size()))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("element_next"):
		select_relative(1)
	elif event.is_action_pressed("element_prev"):
		select_relative(-1)


func _process(delta: float) -> void:
	mana = minf(max_mana, mana + mana_regen * delta)
	for id in cooldowns.keys():
		cooldowns[id] -= delta
		if cooldowns[id] <= 0.0:
			cooldowns.erase(id)
	if elements.is_empty():
		return

	for i in elements.size():
		if Input.is_action_just_pressed("element_%d" % (i + 1)):
			select(i)
	if Input.is_action_pressed("skill_primary"):
		try_cast(skill_for("primary"))
	if Input.is_action_just_pressed("skill_area"):
		try_cast(skill_for("area"))


## Enough of the right resource (mana, or stamina for martial skills)?
func can_afford(id: String) -> bool:
	var def: Dictionary = SkillDB.DEFS[id]
	if SkillDB.uses_stamina(def):
		return body.stamina >= SkillDB.cost_of(def)
	return mana >= SkillDB.cost_of(def)


## False if the skill is on cooldown, too expensive, or not usable by this character
## (element not owned, or not yet learned).
func can_cast(id: String) -> bool:
	if id == "" or not Game.character.can_use_skill(id):
		return false
	return not cooldowns.has(id) and can_afford(id)


## Effective total cooldown (after attributes and passives), for the HUD overlay.
func cooldown_total(id: String) -> float:
	return Game.character.skill_cooldown(id)


func cooldown_fraction(id: String) -> float:
	return clampf(float(cooldowns.get(id, 0.0)) / cooldown_total(id), 0.0, 1.0)


func try_cast(id: String) -> bool:
	if not can_cast(id):
		return false
	var def: Dictionary = SkillDB.DEFS[id]
	if SkillDB.uses_stamina(def):
		body.spend_stamina(SkillDB.cost_of(def))
	else:
		mana -= SkillDB.cost_of(def)
	cooldowns[id] = cooldown_total(id)
	_spawn(id, def)
	_train(id, def)
	cast.emit(id)
	return true


## Area radius after attribute scaling (for the aim preview and the effect itself).
func area_radius(id: String) -> float:
	return float(SkillDB.DEFS[id]["radius"]) * Game.character.skill_scale(id, "radius")


## Where an area skill lands: under the mouse, clamped to the skill's cast range.
func area_target(id: String) -> Vector2:
	var origin := body.global_position
	return origin + (body.get_global_mouse_position() - origin).limit_length(float(SkillDB.DEFS[id]["range"]))


## Casting trains the element (or the weapon, for martial skills) and counts toward the
## skill's own mastery passive.
func _train(id: String, def: Dictionary) -> void:
	var character := Game.character
	var element := String(def["element"])
	if element == "":
		character.add_weapon_xp(1)
	else:
		character.add_element_xp(element, 1)
	character.record_skill_use(id)


func _spawn(id: String, def: Dictionary) -> void:
	var character := Game.character
	var stats: Dictionary = character.derived()
	var element := String(def["element"])
	var origin := body.global_position
	var mouse := body.get_global_mouse_position()
	var dir := (mouse - origin).normalized()
	var parent := body.get_parent()

	# Status potency: the element's governing attribute, plus burn passives for fire.
	var potency := character.potency_mult(element)
	var apply: Dictionary = def.get("apply", {}).duplicate()
	if not apply.is_empty():
		apply["time"] = float(apply["time"]) * potency
		if apply["kind"] == "dot":
			apply["time"] = float(apply["time"]) * float(stats["burn_time_mult"])
			apply["power"] = float(apply["power"]) * potency
		elif apply["kind"] == "slow":
			apply["power"] = minf(float(apply["power"]) * potency, 0.8)
	var hit := {
		"damage": character.skill_damage(id),
		"element": element,
		"apply": apply,
		"knockback": float(def.get("knockback", 50.0)) * character.skill_scale(id, "knockback"),
	}
	match def["kind"]:
		"projectile":
			var speed := float(def["speed"]) * character.skill_scale(id, "speed") * float(stats["projectile_speed_mult"])
			var p := Projectile.new()
			p.setup(dir * speed, hit, float(def["range"]) / speed)
			parent.add_child(p)
			p.global_position = origin + dir * 8.0
		"aoe":
			var a := AoeEffect.new()
			a.setup(hit, area_radius(id), def.get("duration", 0.0), def.get("tick", 0.5))
			parent.add_child(a)
			a.global_position = area_target(id)
