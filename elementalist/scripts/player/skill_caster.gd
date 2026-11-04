class_name SkillCaster
extends Node
## Owns mana, cooldowns, the selected skill set and the locked elements for a caster body.
## What it can cast comes from Game.character: only owned elements (plus the martial set for
## non-elementalists), and only skills that have been learned. Elemental skills cost mana;
## martial skills cost stamina, which lives on the body (see Player.spend_stamina).
##
## Controls:
##   1-5 / mouse wheel   select a set (an element, or "martial")
##   LMB (hold)          the fused cast (lmb_mode "fusion"): ONE bolt that hits with each locked
##                       element in turn, so their combos trigger in a single shot. Disabled
##                       until 2-3 elements are locked. Characters with no elements use it as a
##                       melee attack (melee style) or a knife throw (ranged style).
##   RMB (hold)          the basic attack: a slash, or (ranged style, imbued) a bolt of the
##                       selected element for mana. Dodge + RMB is the spin (see Player).
##   Q                   lock the selected element (up to 3). Needs 2+ elements, no level.
##   F                   the selected set's area skill (level 5)
##   V                   the selected set's support skill (level 7): a buff on yourself or a
##                       debuff on enemies
##   R                   the selected set's special skill (a level reward)
##   E (Player)          imbue toggle: arms slashes with elements; lets ranged classes shoot
## Every number that scales with the character (damage, radius, knockback, speed, cooldown,
## status potency) is resolved here at cast time from CharacterData.

signal cast(skill_id: String)
signal element_changed(element: String)  # also fires for the martial set
signal lock_changed

const FUSION_PREFIX := "fusion:"
const FUSION_DAMAGE := 0.75        # each hit of a two-element fusion deals this share of its normal damage
const FUSION_COOLDOWN_STEP := 0.15  # extra cooldown per fused element beyond the first
const FUSION_COST_PER_EXTRA := 0.3  # a fusion costs (1 + this x extra elements) times the sum of its parts
const CHAIN_WINDOW := 3.0           # cast an ability of a different element within this long...
const CHAIN_DISCOUNT := 0.7         # ...and it costs this much of its mana (chaining abilities is cheaper)

var body: Node2D
var max_mana := 100.0
var mana := 100.0
var mana_regen := 9.0
var elements: Array[String] = []  # selectable sets: owned elements, then "martial" if any
var selected := 0
var locked: Array[String] = []    # elements locked together for fusion (any number of your elements)
var _chain_element := ""          # element of the last ability cast
var _chain_left := 0.0            # seconds left in which a different-element ability is discounted
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
	var had_mana := max_mana > 0.0
	max_mana = float(d["max_mana"])
	mana_regen = float(d["mana_regen"])
	if not had_mana and max_mana > 0.0:
		mana = max_mana  # the first element brings a full pool
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

## Q needs two or more castable elements: there is nothing to fuse with fewer. It is not tied
## to a level (only F and R are locked, behind a level and a reward).
func lock_available() -> bool:
	return Game.character.castable_elements().size() >= 2


## Two or more locked elements are ready to fuse into one cast.
func fusion_ready() -> bool:
	return locked.size() >= 2


## Locks the selected element, or unlocks it if already locked. False if it can't (locking not
## available, or the martial set is selected). Any number of elements can be locked, up to all of
## them; the fused cast needs two.
func toggle_lock() -> bool:
	if not lock_available():
		return false
	var element := selected_element()
	if not (element in Game.character.castable_elements()):
		return false
	if element in locked:
		locked.erase(element)
	else:
		locked.append(element)
	lock_changed.emit()
	return true


## The action LMB casts: the fusion of the locked elements ("fusion:fire+water"), the martial
## primary for characters on the martial set, or "" when LMB is disabled or is a slash.
func primary_id() -> String:
	match lmb_mode():
		"fusion":
			return FUSION_PREFIX + "+".join(locked)
		"knife":
			return String(SkillDB.LOADOUTS["martial"]["primary"])
	return ""


## What RMB shoots when it is a bolt: the selected element's primary skill ("" otherwise).
func bolt_id() -> String:
	return skill_for("primary") if rmb_mode() == "bolt" else ""


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


## What LMB does right now:
##   "fusion"  two or three elements are locked: fire them together (the only elemental LMB)
##   "locked"  the character has elements but fewer than two are locked: LMB can't be pressed
##   "slash"   no elements (or the martial set) on a melee-style class: a straight melee attack
##   "knife"   no elements (or the martial set) on a ranged-style class: the martial throw
func lmb_mode() -> String:
	if fusion_ready():
		return "fusion"
	var elemental := not Game.character.castable_elements().is_empty()
	if elemental and selected_element() != "martial":
		return "locked"
	if Classes.style_of(Game.character.class_id) == "melee" or not Game.character.has_martial():
		return "slash"
	return "knife"


## What RMB does: "slash" (melee), or "bolt" for ranged-style classes while imbued with an
## element selected. Melee-style classes always slash (imbued slashes carry the element).
func rmb_mode() -> String:
	if Classes.style_of(Game.character.class_id) == "ranged" and body.imbued \
			and selected_element() in Game.character.castable_elements():
		return "bolt"
	return "slash"


# ---------- casting ----------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("element_next"):
		select_relative(1)
	elif event.is_action_pressed("element_prev"):
		select_relative(-1)


func _process(delta: float) -> void:
	mana = minf(max_mana, mana + mana_regen * delta)
	_chain_left = maxf(0.0, _chain_left - delta)
	for id in cooldowns.keys():
		cooldowns[id] -= delta
		if cooldowns[id] <= 0.0:
			cooldowns.erase(id)
	if elements.is_empty():
		return

	for i in elements.size():
		if Input.is_action_just_pressed("element_%d" % (i + 1)):
			select(i)
	# LMB fuses locked elements (or throws knives); a slash-mode LMB is the Player's melee.
	if Input.is_action_pressed("skill_primary") and primary_id() != "":
		try_cast(primary_id())
	# RMB shoots the selected element while a ranged class is imbued (the Player slashes
	# otherwise, and spins instead whenever you are dodging).
	if Input.is_action_pressed("attack_basic") and rmb_mode() == "bolt" and not body.is_dodging():
		try_cast(bolt_id())
	if Input.is_action_just_pressed("skill_lock"):
		toggle_lock()
	if Input.is_action_just_pressed("skill_area"):
		try_cast(skill_for("area"))
	if Input.is_action_just_pressed("skill_support"):
		try_cast(skill_for("support"))
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
	total.x *= mana_multiplier(id)
	return total


## Everything that scales an action's mana: the character's mana-cost stat (passives, gear,
## Elemental Harmony's spread-thin penalty), +30% per extra element in a fusion, and the chain
## discount for abilities.
func mana_multiplier(id: String) -> float:
	var multiplier := float(Game.character.derived()["mana_cost_mult"])
	if is_fusion(id):
		multiplier *= 1.0 + FUSION_COST_PER_EXTRA * (components(id).size() - 1)
	return multiplier * chain_discount(id)


## Abilities are the F, V and R skills of an element (not the LMB/RMB attacks).
func is_ability(id: String) -> bool:
	return not is_fusion(id) and SkillDB.DEFS.has(id) and SkillDB.slot_of(id) in ["area", "support", "special"] \
		and String(SkillDB.DEFS[id]["element"]) != ""


## 0.7 for an ability of a different element than the last one, cast within CHAIN_WINDOW (so
## setting up a combo with two abilities in quick succession is cheaper); otherwise 1.0.
func chain_discount(id: String) -> float:
	if _chain_left > 0.0 and is_ability(id) and _chain_element != "" and String(SkillDB.DEFS[id]["element"]) != _chain_element:
		return CHAIN_DISCOUNT
	return 1.0


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
	var total := longest + FUSION_COOLDOWN_STEP * maxi(parts.size() - 1, 0)
	if is_fusion(id) or (SkillDB.DEFS.has(id) and SkillDB.slot_of(id) == "primary"):
		total /= float(Game.character.derived()["attack_speed"])  # attack speed: the basic attacks, not abilities
	return total


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
	if is_ability(id):
		_chain_element = String(SkillDB.DEFS[id]["element"])
		_chain_left = CHAIN_WINDOW
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
	return origin + (Controls.aim_point(body, origin) - origin).limit_length(float(SkillDB.DEFS[id]["range"]))


## Damage multiplier from the caster's "might" buff (1.0 without one).
func _might() -> float:
	return float(body.damage_mult()) if body.has_method("damage_mult") else 1.0


## Share of its normal damage each hit of an n-element fusion deals: 75% for two, down to 50%
## for five, so fusing everything is not simply the best choice.
static func fusion_hit_scale(n: int) -> float:
	return maxf(0.5, 0.85 - 0.1 * (n - 1))


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
	var mouse := Controls.aim_point(body, origin)
	var dir := (mouse - origin).normalized()
	var parent := body.get_parent()

	var hit := {
		"damage": character.skill_damage(id) * _might(),
		"element": String(def["element"]),
		"apply": status_for(def),
		"knockback": float(def.get("knockback", 50.0)) * character.skill_scale(id, "knockback"),
	}
	SkillFx.cast_burst(parent, origin + dir * 8.0, String(def["element"]), dir)
	Sfx.play("cast_" + (String(def["element"]) if String(def["element"]) != "" else "martial"), &"SFX", -2.0)
	match def["kind"]:
		"buff":
			Sfx.play("buff")
			var buff: Dictionary = def["buff"]
			body.add_buff(String(buff["kind"]), float(buff["time"]), float(buff["power"]), String(def["element"]))
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
	var dir := (Controls.aim_point(body, origin) - origin).normalized()
	var hits: Array = []
	var speed := INF
	var reach := INF
	for i in skill_ids.size():
		var id := skill_ids[i]
		var def: Dictionary = SkillDB.DEFS[id]
		hits.append({
			"damage": character.skill_damage(id) * fusion_hit_scale(skill_ids.size()) * float(stats["fusion_damage_mult"]) * _might(),
			"element": String(def["element"]),
			"apply": status_for(def),
			"knockback": float(def.get("knockback", 50.0)) * character.skill_scale(id, "knockback"),
			"text_offset": Vector2((i - (skill_ids.size() - 1) * 0.5) * 12.0, 0.0),  # keep numbers readable
		})
		SkillFx.cast_burst(body.get_parent(), origin + dir * 8.0, String(def["element"]), dir)
		speed = minf(speed, float(def["speed"]) * character.skill_scale(id, "speed"))
		reach = minf(reach, float(def["range"]))
	speed *= float(stats["projectile_speed_mult"])
	var p := Projectile.new()
	p.setup(dir * speed, hits[0], reach / speed, hits.slice(1))
	body.get_parent().add_child(p)
	p.global_position = origin + dir * 8.0
