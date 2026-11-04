class_name CharacterData
extends RefCounted
## Everything that defines a character: class, attributes, level/XP, owned elements and their
## mastery, weapon mastery, traits, skill usage, rewards, and which skills they may use. Pure
## data + rules, no nodes, so it can be saved, loaded and unit-tested.
##
## Progression (see Classes for the gates): everyone starts as a Novice, chooses a class at
## level 3, unlocks area skills (Q) at level 5 and a subclass at level 10. Milestone levels
## queue a reward offer (Rewards) in `pending_rewards`.
##
## Elements come from the world (the ceremony, items, story); skills are learned. A skill is
## usable only if the character owns its element AND has learned it. Characters born without
## elements ("non-elementalists") instead learn the martial set, a pair of stamina-powered
## physical skills, but may still gain elements later (attunable).
##
## Stats that scale with attributes (documented in docs/ARCHITECTURE.md):
##   derived()             HP, mana, stamina, speed, melee damage and reach, ...
##   spell_damage_mult()   Intellect, element mastery, passives
##   potency_mult()        the element's governing attribute scales status duration/strength
##   skill_scale()         a skill's own "scales" attribute scales radius/knockback/speed/cooldown

signal leveled_up(new_level: int)
signal mastery_leveled(label: String, new_level: int)
signal passive_unlocked(passive_name: String)
signal class_chosen(class_id: String)
signal reward_ready(level: int)
signal reward_claimed(reward_name: String)
signal elements_changed
signal changed

const ELEMENTALIST := "elementalist"  # rolled elements at the ceremony
const ATTUNABLE := "attunable"        # no elements at birth (martial skills); can gain them later
const SEALED := "sealed"              # can never hold elements; martial skills only

const MAX_LEVEL := 30
const MASTERY_CAP := 10
const FREE_POINTS_PER_LEVEL := 2
const LEVEL_UP_HEAL_FRACTION := 0.4  # a level-up restores this share of max HP, not all of it

var display_name := "Hero"
var class_id := Classes.NEUTRAL_CLASS
var subclass_id := ""
var affinity := ELEMENTALIST
var level := 1
var xp := 0
var unspent_points := 0
var attributes: Dictionary = {}
var elements: Array[String] = []
var element_mastery: Dictionary = {}   # element id -> {"level": int, "xp": int}
var weapon_type := "sword"             # the wielded weapon's type (the class's default if none is equipped)
var weapon_masteries: Dictionary = {}  # weapon type -> {"level": int, "xp": int}
var inventory := Inventory.new()       # gold, materials, bag and equipped gear (Phase 4)
var traits: Array[String] = []         # innate passives: rolled at creation or chosen as rewards
var skill_uses: Dictionary = {}        # skill id -> times used (unlocks skill mastery passives)
var learned_specials: Array[String] = []  # special (R) skills earned as rewards
var pending_rewards: Array = []        # unclaimed offers: each is an Array of {"type", "id"}
var reward_rng := RandomNumberGenerator.new()  # rolls reward offers (tests may seed it)


## New character. Everyone starts as a Novice unless `cls` names a real class (a shortcut for
## testing). Elementalists go through the ceremony: they may be born with elements, or with
## none (then they become attunable). Sealed and attunable characters skip it.
static func create(char_name: String, cls: String, aff: String, rng: RandomNumberGenerator) -> CharacterData:
	var c := CharacterData.new()
	c._setup(char_name, cls, aff)
	if aff == ELEMENTALIST:
		var born: Array = Ceremony.perform(rng)["elements"]
		if born.is_empty():
			c.affinity = ATTUNABLE
		for element in born:
			c.add_element(String(element))
	c.traits = Ceremony.roll_traits(rng, c.elements.size(), aff != SEALED)
	return c


## A character with chosen elements and no traits, skipping the ceremony. Used by the sandbox
## and tests. Levelling up queues the rewards for the levels skipped.
static func create_sandbox(cls: String, owned: Array, start_level: int = 1) -> CharacterData:
	var c := CharacterData.new()
	c._setup("Sandbox", cls, ELEMENTALIST)
	for element in owned:
		c.add_element(String(element))
	while c.level < start_level:
		c._level_up()
	return c


func _setup(char_name: String, cls: String, aff: String) -> void:
	display_name = char_name
	class_id = cls
	affinity = aff
	attributes = Classes.CLASSES[cls]["base"].duplicate()
	inventory.equipped["weapon"] = _starter_weapon(Classes.CLASSES[cls]["weapon"])
	inventory.changed.connect(_on_inventory_changed)
	_refresh_weapon()
	reward_rng.randomize()


# ---------- gear ----------

static func _starter_weapon(type: String) -> Dictionary:
	return Items.make(Items.starter_for(type), "common", 1, RandomNumberGenerator.new())


## The weapon type follows the equipped weapon; with none equipped it is the class's own.
## Each type trains its own mastery, so swapping weapons swaps which mastery grows.
func _refresh_weapon() -> void:
	var wielded := inventory.weapon_type()
	weapon_type = wielded if wielded != "" else String(Classes.CLASSES[class_id]["weapon"])
	if not weapon_masteries.has(weapon_type):
		weapon_masteries[weapon_type] = {"level": 1, "xp": 0}


func _on_inventory_changed() -> void:
	_refresh_weapon()
	changed.emit()


# ---------- class (chosen at level 3) ----------

func can_choose_class() -> bool:
	return level >= Classes.CLASS_LEVEL and Classes.is_starter(class_id)


## Turns a Novice into `id`. Points the player already spent are kept; the class's base
## attributes replace the Novice's and its growth is applied for the levels gained so far.
func choose_class(id: String) -> bool:
	if not can_choose_class() or not (id in Classes.playable()):
		return false
	var novice_base: Dictionary = Classes.CLASSES[class_id]["base"]
	var cls: Dictionary = Classes.CLASSES[id]
	for attr in attributes:
		var spent: int = int(attributes[attr]) - int(novice_base[attr])
		attributes[attr] = int(cls["base"][attr]) + spent + int(cls["per_level"].get(attr, 0)) * (level - 1)
	class_id = id
	# A worn starter weapon is swapped for the new class's own; anything better you found stays.
	var current: Dictionary = inventory.equipped.get("weapon", {})
	if current.is_empty() or Items.is_starter(current):
		inventory.equipped["weapon"] = _starter_weapon(cls["weapon"])
	_refresh_weapon()
	class_chosen.emit(id)
	changed.emit()
	return true


# ---------- elements ----------

## Adds an element (ceremony, item or story). Refused for sealed characters or if owned.
func add_element(id: String) -> bool:
	if affinity == SEALED or id in elements:
		return false
	elements.append(id)
	element_mastery[id] = {"level": 1, "xp": 0}
	elements_changed.emit()
	changed.emit()
	return true


## True for anyone not born an elementalist: they learn the martial skill set.
func has_martial() -> bool:
	return affinity != ELEMENTALIST


# ---------- XP and levels ----------

static func xp_to_next(lv: int) -> int:
	return int(30.0 * pow(lv, 1.4))


## Returns how many levels were gained.
func gain_xp(amount: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	xp += amount
	var gained := 0
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		_level_up()
		gained += 1
	if level >= MAX_LEVEL:
		xp = 0
	changed.emit()
	return gained


func _level_up() -> void:
	level += 1
	unspent_points += FREE_POINTS_PER_LEVEL
	var growth: Dictionary = Classes.CLASSES[class_id]["per_level"]
	for attr in growth:
		attributes[attr] += int(growth[attr])
	if Rewards.is_reward_level(level):
		var offer := Rewards.generate(self, reward_rng)
		if not offer.is_empty():
			pending_rewards.append(offer)
			reward_ready.emit(level)
	leveled_up.emit(level)


func spend_point(attr: String) -> bool:
	if unspent_points <= 0 or not attributes.has(attr):
		return false
	attributes[attr] += 1
	unspent_points -= 1
	changed.emit()
	return true


# ---------- rewards ----------

## Applies option `option_index` of the pending offer `offer_index` (a passive becomes a trait,
## a skill becomes a learned special) and discards that offer. False if it can't be applied.
func claim_reward(offer_index: int, option_index: int) -> bool:
	if offer_index < 0 or offer_index >= pending_rewards.size():
		return false
	var offer: Array = pending_rewards[offer_index]
	if option_index < 0 or option_index >= offer.size():
		return false
	var option: Dictionary = offer[option_index]
	var id := String(option["id"])
	if option["type"] == "skill":
		if id in learned_specials or not (SkillDB.set_of(id) in castable_sets()):
			return false
		learned_specials.append(id)
	else:
		if id in traits:
			return false
		traits.append(id)
	pending_rewards.remove_at(offer_index)
	reward_claimed.emit(Rewards.option_name(option))
	changed.emit()
	return true


# ---------- mastery ----------

static func mastery_xp_to_next(lv: int) -> int:
	return 20 + 10 * (lv - 1)


func element_level(id: String) -> int:
	return int(element_mastery.get(id, {"level": 0})["level"])


func weapon_level() -> int:
	return int(weapon_masteries[weapon_type]["level"])


func add_element_xp(id: String, amount: int = 1) -> void:
	if element_mastery.has(id):
		_add_mastery_xp(element_mastery[id], amount, id.capitalize(), String(Classes.ELEMENT_PASSIVES.get(id, "")))


func add_weapon_xp(amount: int = 1) -> void:
	_add_mastery_xp(weapon_masteries[weapon_type], amount, weapon_type.capitalize(), String(Classes.WEAPON_PASSIVES.get(weapon_type, "")))


func _add_mastery_xp(m: Dictionary, amount: int, label: String, passive_id: String) -> void:
	if m["level"] >= MASTERY_CAP:
		return
	m["xp"] += amount
	while m["level"] < MASTERY_CAP and m["xp"] >= mastery_xp_to_next(m["level"]):
		m["xp"] -= mastery_xp_to_next(m["level"])
		m["level"] += 1
		mastery_leveled.emit(label, m["level"])
		if m["level"] == Classes.RARE_PASSIVE_LEVEL and passive_id != "":
			passive_unlocked.emit(String(Classes.passive_info(passive_id)["name"]))
	changed.emit()


## Counts a cast. Enough uses of one skill unlock its (rare) mastery passive.
func record_skill_use(skill_id: String) -> void:
	skill_uses[skill_id] = int(skill_uses.get(skill_id, 0)) + 1
	if skill_uses[skill_id] == Classes.skill_passive_uses(skill_id):
		passive_unlocked.emit(String(Classes.passive_info(Classes.SKILL_MASTERY_PREFIX + skill_id)["name"]))
		changed.emit()


# ---------- subclass (level 10) ----------

func available_subclasses() -> Array:
	if level < Classes.SUBCLASS_LEVEL or subclass_id != "":
		return []
	return Classes.CLASSES[class_id]["subclasses"]


func choose_subclass(id: String) -> bool:
	if not (id in available_subclasses()):
		return false
	subclass_id = id
	changed.emit()
	return true


# ---------- passives and derived stats ----------

## Every active passive with its type: "class", "trait", "element" or "skill".
func passive_sources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in Classes.CLASSES[class_id]["passives"]:
		out.append({"id": id, "type": "class"})
	if subclass_id != "":
		for id in Classes.SUBCLASSES[subclass_id]["passives"]:
			out.append({"id": id, "type": "class"})
	for id in traits:
		out.append({"id": id, "type": "trait"})
	for element in elements:
		if element_level(element) >= Classes.RARE_PASSIVE_LEVEL and Classes.ELEMENT_PASSIVES.has(element):
			out.append({"id": Classes.ELEMENT_PASSIVES[element], "type": "element"})
	if weapon_level() >= Classes.RARE_PASSIVE_LEVEL and Classes.WEAPON_PASSIVES.has(weapon_type):
		out.append({"id": Classes.WEAPON_PASSIVES[weapon_type], "type": "skill"})
	for skill_id in skill_uses:
		if SkillDB.DEFS.has(skill_id) and int(skill_uses[skill_id]) >= Classes.skill_passive_uses(skill_id):
			out.append({"id": Classes.SKILL_MASTERY_PREFIX + skill_id, "type": "skill"})
	if elements.size() >= 2:  # one stack for every element beyond the first
		out.append({"id": Classes.HARMONY_PASSIVE, "type": "element", "stacks": elements.size() - 1})
	return out


func active_passives() -> Array[String]:
	var out: Array[String] = []
	for source in passive_sources():
		out.append(String(source["id"]))
	return out


## Sums *_add mods and multiplies *_mult mods across all active passives.
func stat_mods() -> Dictionary:
	var mods: Dictionary = {}
	for source in passive_sources():
		var stacks := int(source.get("stacks", 1))  # stacking passives (Harmony) apply once per stack
		var passive_mods: Dictionary = Classes.passive_info(source["id"])["mods"]
		for key in passive_mods:
			if String(key).ends_with("_mult"):
				mods[key] = float(mods.get(key, 1.0)) * pow(float(passive_mods[key]), stacks)
			else:
				mods[key] = float(mods.get(key, 0.0)) + float(passive_mods[key]) * stacks
	var gear := inventory.mods()  # already in passive format
	for key in gear:
		if String(key).ends_with("_mult"):
			mods[key] = float(mods.get(key, 1.0)) * float(gear[key])
		else:
			mods[key] = float(mods.get(key, 0.0)) + float(gear[key])
	return mods


static func _mod(mods: Dictionary, key: String) -> float:
	return float(mods.get(key, 1.0 if key.ends_with("_mult") else 0.0))


## Final gameplay stats. At all-5 attributes and no passives these equal the values the
## combat was tuned against (100 HP, 100 mana, 100 stamina, speed 80, melee reach x1.0).
func derived() -> Dictionary:
	var m := stat_mods()
	var vit := float(attributes["vitality"])
	var intel := float(attributes["intellect"])
	var agi := float(attributes["agility"])
	var str_ := float(attributes["strength"])
	var weapon_bonus := 1.0 + 0.03 * (weapon_level() - 1)
	return {
		"max_hp": 60.0 + vit * 8.0 + _mod(m, "max_hp_add"),
		"hp_regen": 0.3 + vit * 0.06 + _mod(m, "hp_regen_add"),
		"max_mana": (50.0 + intel * 10.0 + _mod(m, "max_mana_add")) if uses_mana() else 0.0,
		"mana_regen": (5.0 + intel * 0.8 + _mod(m, "mana_regen_add")) if uses_mana() else 0.0,
		"max_stamina": 70.0 + agi * 6.0 + _mod(m, "max_stamina_add"),
		"stamina_regen": 20.0 + agi * 2.0 + _mod(m, "stamina_regen_add"),
		"move_speed": (70.0 + agi * 2.0) * _mod(m, "move_speed_mult"),
		"melee_damage_mult": (1.0 + (str_ - 5.0) * 0.06) * weapon_bonus * _mod(m, "melee_damage_mult"),
		"melee_range_mult": float(Classes.CLASSES[class_id]["melee_range"]) * _mod(m, "melee_range_mult"),
		"melee_stamina_cost_mult": _mod(m, "melee_stamina_cost_mult"),
		"damage_taken_mult": _mod(m, "damage_taken_mult"),
		"burn_time_mult": _mod(m, "burn_time_mult"),
		"projectile_speed_mult": _mod(m, "projectile_speed_mult"),
		"fusion_damage_mult": _mod(m, "fusion_damage_mult"),
	}


## Mana belongs to elements: a character who owns none (sealed, or not yet attuned) has no mana
## pool at all, and gains one the moment they gain an element.
func uses_mana() -> bool:
	return not elements.is_empty()


## Damage multiplier for a spell of `element`: intellect, element mastery, passives.
func spell_damage_mult(element: String) -> float:
	var intel := float(attributes["intellect"])
	var mastery := 1.0 + 0.04 * (element_level(element) - 1) if element_level(element) > 0 else 1.0
	return (1.0 + (intel - 5.0) * 0.05) * mastery * _mod(stat_mods(), "spell_damage_mult")


## Status duration/strength multiplier for an element: its governing attribute (see
## Classes.ELEMENT_ATTRIBUTE) above or below 5. Martial skills (no element) are unaffected.
func potency_mult(element: String) -> float:
	if not Classes.ELEMENT_ATTRIBUTE.has(element):
		return 1.0
	var delta := float(attributes[Classes.ELEMENT_ATTRIBUTE[element]]) - 5.0
	return clampf(1.0 + Classes.POTENCY_PER_POINT * delta, 0.6, 1.6)


## Multiplier for one property of one skill (radius, knockback, speed, cooldown), driven by
## the attribute named in the skill's "scales" entry. 1.0 if the skill doesn't scale it.
func skill_scale(skill_id: String, prop: String) -> float:
	var scales: Dictionary = SkillDB.DEFS[skill_id].get("scales", {})
	if not scales.has(prop):
		return 1.0
	var delta := float(attributes[scales[prop]]) - 5.0
	return clampf(1.0 + float(Classes.SCALE_RATE[prop]) * delta, 0.5, 1.6)


## Damage of one cast: spells scale with Intellect/mastery, martial skills with Strength.
func skill_damage(skill_id: String) -> float:
	var def: Dictionary = SkillDB.DEFS[skill_id]
	var element := String(def.get("element", ""))
	var mult: float = float(derived()["melee_damage_mult"]) if element == "" else spell_damage_mult(element)
	return float(def["damage"]) * mult * _mod(stat_mods(), skill_id + "_damage_mult")


## Effective cooldown in seconds after attribute scaling and passives.
func skill_cooldown(skill_id: String) -> float:
	var def: Dictionary = SkillDB.DEFS[skill_id]
	var m := stat_mods()
	var cooldown := float(def["cooldown"]) * skill_scale(skill_id, "cooldown") * _mod(m, skill_id + "_cooldown_mult")
	if String(def.get("element", "")) != "":
		cooldown *= _mod(m, "spell_cooldown_mult")
	return cooldown


# ---------- skills ----------

## Elements the character owns that have a skill loadout (Light/Dark have none yet).
func castable_elements() -> Array[String]:
	var out: Array[String] = []
	for element in elements:
		if SkillDB.LOADOUTS.has(element):
			out.append(element)
	return out


## Selectable skill sets: castable elements, plus "martial" for non-elementalists.
func castable_sets() -> Array[String]:
	var out := castable_elements()
	if has_martial():
		out.append("martial")
	return out


## Level at which this skill is taught (primary 1, area 5), or 0 for specials, which are
## earned as rewards instead.
func skill_unlock_level(skill_id: String) -> int:
	var slot := SkillDB.slot_of(skill_id)
	return int(Classes.SKILL_LEVELS.get(slot, 0))


## Skills the character has been taught, for the sets they have access to.
func known_skills() -> Array[String]:
	var out: Array[String] = []
	for set_id in castable_sets():
		for slot in ["primary", "area"]:
			var skill_id: String = SkillDB.LOADOUTS[set_id][slot]
			if level >= skill_unlock_level(skill_id):
				out.append(skill_id)
		var special: String = SkillDB.LOADOUTS[set_id]["special"]
		if special in learned_specials:
			out.append(special)
	return out


func can_use_skill(skill_id: String) -> bool:
	if not SkillDB.DEFS.has(skill_id):
		return false
	var element: String = SkillDB.DEFS[skill_id].get("element", "")
	if element != "" and not (element in elements):
		return false
	return skill_id in known_skills()


# ---------- saving ----------

func to_dict() -> Dictionary:
	return {
		"name": display_name, "class": class_id, "subclass": subclass_id, "affinity": affinity,
		"level": level, "xp": xp, "points": unspent_points,
		"attributes": attributes.duplicate(),
		"elements": Array(elements),
		"element_mastery": element_mastery.duplicate(true),
		"weapon_type": weapon_type,
		"weapon_masteries": weapon_masteries.duplicate(true),
		"traits": Array(traits),
		"skill_uses": skill_uses.duplicate(),
		"learned_specials": Array(learned_specials),
		"pending_rewards": pending_rewards.duplicate(true),
		"inventory": inventory.to_dict(),
	}


## Rebuilds a character from to_dict() output, including after a JSON round trip (which
## turns every integer into a float).
static func from_dict(d: Dictionary) -> CharacterData:
	var c := CharacterData.new()
	c._setup(String(d["name"]), String(d["class"]), String(d["affinity"]))
	c.subclass_id = String(d["subclass"])
	c.level = int(d["level"])
	c.xp = int(d["xp"])
	c.unspent_points = int(d["points"])
	for attr in d["attributes"]:
		c.attributes[attr] = int(d["attributes"][attr])
	for element in d["elements"]:
		c.elements.append(String(element))
	c.element_mastery = _ints_in(d["element_mastery"])
	c.weapon_type = String(d["weapon_type"])
	c.weapon_masteries = _ints_in(d["weapon_masteries"])
	for trait_id in d.get("traits", []):
		c.traits.append(String(trait_id))
	for skill_id in d.get("skill_uses", {}):
		c.skill_uses[skill_id] = int(d["skill_uses"][skill_id])
	for skill_id in d.get("learned_specials", []):
		c.learned_specials.append(String(skill_id))
	for offer in d.get("pending_rewards", []):
		var options: Array = []
		for option in offer:
			options.append({"type": String(option["type"]), "id": String(option["id"])})
		c.pending_rewards.append(options)
	if d.has("inventory"):
		c.inventory.load_dict(d["inventory"])  # also re-derives the weapon type
	return c


static func _ints_in(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in source:
		out[key] = {"level": int(source[key]["level"]), "xp": int(source[key]["xp"])}
	return out
