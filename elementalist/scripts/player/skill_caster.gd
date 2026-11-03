class_name SkillCaster
extends Node
## Owns mana, cooldowns, the selected skill set and the locked elements for a caster body.
## What it can cast comes from Game.character: only owned elements (plus the martial set for
## non-elementalists), and only skills that have been learned. Elemental skills cost mana;
## martial skills cost stamina, which lives on the body (see Player.spend_stamina).
##
## Controls:
##   1-5 / mouse wheel   select a set (an element, or "martial")
##   LMB (hold)          the "primary" action, which depends on the class style (lmb_mode):
##                         a bolt of the locked/selected element(s), or a slash
##   Q                   lock the selected element (up to 3). Locked elements fuse: LMB then
##                       fires ONE bolt that hits with each of them in turn, so their combos
##                       trigger in a single shot. Unlocks at level 5, needs an element.
##   F                   the selected set's area skill (level 5)
##   R                   the selected set's special skill (a level reward)
##   E (Player)          imbue: ranged classes shoot only while imbued (see lmb_mode)
## Every number that scales with the character (damage, radius, knockback, speed, cooldown,
## status potency) is resolved here at cast time from CharacterData.

signal cast(skill_id: String)
signal element_changed(element: String)  # also fires for the martial set
signal lock_changed

const FUSION_PREFIX := "fusion:"
const FUSION_DAMAGE := 0.75        # each hit of a fused bolt deals this share of its normal damage
const FUSION_COOLDOWN_STEP := 0.15  # extra cooldown per fused element beyond the first

var body: Node2D
var max_mana := 100.0
var mana := 100.0
var mana_regen := 9.0
var elements: Array[String] = []  # selectable sets: owned elements, then "martial" if any
var selected := 0
var locked: Array[String] = []    # elements locked together for fusion (max Classes.MAX_LOCKED)
var cooldowns: Dictionary = {}    # skill id (or fusion id) -> seconds left


func _ready() -> void:
	refresh_elements()
	mana = max_mana
	Game.character.elements_changed.connect(refresh_elements)


## Re-read castable sets and mana stats from the character (e.g. after gaining an element).
func refresh_elements() -> void:
	elements = Game.character.castable_sets()
	selected = clampi(selected, 0, maxi(elements.size() - 1, 0))
	var castable := Game.character.castable_elements()
	locked = locked.filter(func(e): return e in castable)
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


# ---------- locking and fusion (Q) ----------

## Q works from level 5 and only for characters who own at least one castable element.
func lock_available() -> bool:
	return Game.character.level >= Classes.AREA_LEVEL and not Game.character.castable_elements().is_empty()


## Locks the selected element, or unlocks it if already locked. False if it can't (locking not
## available, the martial set is selected, or three elements are already locked).
func toggle_lock() -> bool:
	if not lock_available():
		return false
	var element := selected_element()
	if not (element in Game.character.castable_elements()):
		return false
	if element in locked:
		locked.erase(element)
	elif locked.size() >= Classes.MAX_LOCKED:
		return false
	else:
		locked.append(element)
	lock_changed.emit()
	return true


## The action LMB casts: a fusion of the locked elements (2-3), the one locked element's
## primary, or the selected set's primary when nothing is locked.
func primary_id() -> String:
	if locked.size() >= 2:
		return FUSION_PREFIX + "+".join(locked)
	if locked.size() == 1:
		return SkillDB.LOADOUTS[locked[0]]["primary"]
	return skill_for("primary")


static func is_fusion(id: String) -> bool:
	return id.begins_with(FUSION_PREFIX)


## The real skill ids behind an action id (a fusion expands to each element's primary).
func components(id: String) -> Array[String]:
	var out: Array[String] = []
	if is_fusion(id):
		for element in id.trim_prefix(FUSION_PREFIX).split("+"):
			out.append(String(SkillDB.LOADOUTS[element]["primary"]))
	elif id != "":
		out.append(id)
	return out


## What LMB does right now: "bolt" (cast primary_id) or "slash" (melee). By class style:
##   melee   always slashes (elements come from imbue and abilities)
##   ranged  shoots only while imbued, otherwise slashes
##   hybrid  (the Novice) always shoots
## The martial set always "shoots" (knives are not an element). No castable set: slash.
func lmb_mode() -> String:
	if elements.is_empty():
		return "slash"
	if selected_element() == "martial" and locked.is_empty():
		return "bolt"
	match Classes.style_of(Game.character.class_id):
		"melee":
			return "slash"
		"ranged":
			return "bolt" if body.imbued else "slash"
	return "bolt"


# ---------- casting ----------

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
	if Input.is_action_pressed("skill_primary") and lmb_mode() == "bolt":
		try_cast(primary_id())  # in "slash" mode the Player handles LMB as a melee attack
	if Input.is_action_just_pressed("skill_lock"):
		toggle_lock()
	if Input.is_action_just_pressed("skill_area"):
		try_cast(skill_for("area"))
	if Input.is_action_just_pressed("skill_special"):
		try_cast(skill_for("special"))


## Total mana (x) and stamina (y) an action costs; a fusion costs the sum of its parts.
func costs(id: String) -> Vector2:
	var total := Vector2.ZERO
	for skill_id in components(id):
		var def: Dictionary = SkillDB.DEFS[skill_id]
		if SkillDB.uses_stamina(def):
			total.y += SkillDB.cost_of(def)
		else:
			total.x += SkillDB.cost_of(def)
	return total


## Enough of the right resources (mana, and stamina for martial skills)?
func can_afford(id: String) -> bool:
	var cost := costs(id)
	return mana >= cost.x and body.stamina >= cost.y


## False if the action is on cooldown, too expensive, or not usable by this character
## (element not owned, or not yet learned). Every part of a fusion must be usable.
func can_cast(id: String) -> bool:
	var parts := components(id)
	if parts.is_empty():
		return false
	for skill_id in parts:
		if not Game.character.can_use_skill(skill_id):
			return false
	return not cooldowns.has(id) and can_afford(id)


## Effective total cooldown (after attributes and passives), for the HUD overlay. A fusion
## waits for its slowest part plus a small step per extra element.
func cooldown_total(id: String) -> float:
	var longest := 0.0
	var parts := components(id)
	for skill_id in parts:
		longest = maxf(longest, Game.character.skill_cooldown(skill_id))
	return longest + FUSION_COOLDOWN_STEP * maxi(parts.size() - 1, 0)


func cooldown_fraction(id: String) -> float:
	if id == "":
		return 0.0
	return clampf(float(cooldowns.get(id, 0.0)) / cooldown_total(id), 0.0, 1.0)


func try_cast(id: String) -> bool:
	if not can_cast(id):
		return false
	var cost := costs(id)
	mana -= cost.x
	if cost.y > 0.0:
		body.spend_stamina(cost.y)
	cooldowns[id] = cooldown_total(id)
	if is_fusion(id):
		_spawn_fusion(components(id))
	else:
		_spawn(id, SkillDB.DEFS[id])
	for skill_id in components(id):
		_train(skill_id, SkillDB.DEFS[skill_id])
	cast.emit(id)
	return true


## Area radius after attribute scaling (for the aim preview and the effect itself).
func area_radius(id: String) -> float:
	return float(SkillDB.DEFS[id]["radius"]) * Game.character.skill_scale(id, "radius")


## Where an area skill lands: under the mouse, clamped to the skill's cast range.
func area_target(id: String) -> Vector2:
	var origin := body.global_position
	return origin + (body.get_global_mouse_position() - origin).limit_length(float(SkillDB.DEFS[id]["range"]))


## The status a skill applies on hit, scaled by the character: the element's potency (its
## governing attribute) and, for burns, burn passives. Also used by imbued slashes.
func status_for(def: Dictionary) -> Dictionary:
	var apply: Dictionary = def.get("apply", {}).duplicate()
	if apply.is_empty():
		return apply
	var character := Game.character
	var potency := character.potency_mult(String(def.get("element", "")))
	apply["time"] = float(apply["time"]) * potency
	if apply["kind"] == "dot":
		apply["time"] = float(apply["time"]) * float(character.derived()["burn_time_mult"])
		apply["power"] = float(apply["power"]) * potency
	elif apply["kind"] == "slow":
		apply["power"] = minf(float(apply["power"]) * potency, 0.8)
	return apply


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
	var origin := body.global_position
	var mouse := body.get_global_mouse_position()
	var dir := (mouse - origin).normalized()
	var parent := body.get_parent()

	var hit := {
		"damage": character.skill_damage(id),
		"element": String(def["element"]),
		"apply": status_for(def),
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


## One bolt carrying a hit per fused element. It flies as fast and as far as its slowest part.
func _spawn_fusion(skill_ids: Array[String]) -> void:
	var character := Game.character
	var stats: Dictionary = character.derived()
	var origin := body.global_position
	var dir := (body.get_global_mouse_position() - origin).normalized()
	var hits: Array = []
	var speed := INF
	var reach := INF
	for i in skill_ids.size():
		var id := skill_ids[i]
		var def: Dictionary = SkillDB.DEFS[id]
		hits.append({
			"damage": character.skill_damage(id) * FUSION_DAMAGE,
			"element": String(def["element"]),
			"apply": status_for(def),
			"knockback": float(def.get("knockback", 50.0)) * character.skill_scale(id, "knockback"),
			"text_offset": Vector2((i - (skill_ids.size() - 1) * 0.5) * 12.0, 0.0),  # keep numbers readable
		})
		speed = minf(speed, float(def["speed"]) * character.skill_scale(id, "speed"))
		reach = minf(reach, float(def["range"]))
	speed *= float(stats["projectile_speed_mult"])
	var p := Projectile.new()
	p.setup(dir * speed, hits[0], reach / speed, hits.slice(1))
	body.get_parent().add_child(p)
	p.global_position = origin + dir * 8.0
