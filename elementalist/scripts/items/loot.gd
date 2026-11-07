class_name Loot
extends RefCounted
## Drop tables. Everything takes a RandomNumberGenerator so drops are reproducible in tests.
##
## A drop list is an Array of Dictionaries, each one of:
##   {"kind": "gold", "amount": n}
##   {"kind": "material", "id": "scrap", "amount": n}
##   {"kind": "item", "item": <item dictionary>}
## The world turns these into Pickups; nothing is added to the inventory until it is collected.
##
## `bonus` is a luck value (the game uses 0.1 per wave): it shifts rarity weights toward the
## better rarities (each tier's weight is multiplied by 1 + bonus x tier).

const GOLD_CHANCE := 0.7
const GEL_CHANCE := 0.35
const SCRAP_CHANCE := 0.25
const ESSENCE_CHANCE := 0.25  # of the element that last hit the enemy
const GEAR_CHANCE := 0.08
const VARIANT_ESSENCE_CHANCE := 0.6  # elemental variants usually drop their own element's essence
const GEM_CHANCE := 0.5              # a boss drops an elemental gem about half the time


## Picks a key of `weights` (key -> weight) at random.
static func pick_weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for key in weights:
		total += float(weights[key])
	var roll := rng.randf() * total
	for key in weights:
		roll -= float(weights[key])
		if roll < 0.0:
			return String(key)
	return String(weights.keys()[-1])


## Rarity weights after luck and a minimum rarity ("common" for none).
static func rarity_weights(bonus: float, floor_rarity: String = "common") -> Dictionary:
	var out: Dictionary = {}
	var floor_index := Items.RARITIES.find(floor_rarity)
	for i in Items.RARITIES.size():
		if i < floor_index:
			continue
		var id: String = Items.RARITIES[i]
		out[id] = float(Items.RARITY[id]["weight"]) * (1.0 + maxf(bonus, 0.0) * i)
	return out


static func roll_rarity(rng: RandomNumberGenerator, bonus: float = 0.0, floor_rarity: String = "common") -> String:
	return pick_weighted(rng, rarity_weights(bonus, floor_rarity))


## A random piece of gear for `slot` ("" = any slot) at item level `ilvl`. {} if nothing fits.
static func roll_item(rng: RandomNumberGenerator, ilvl: int, bonus: float = 0.0, slot: String = "",
		floor_rarity: String = "common", allow_spell: bool = true) -> Dictionary:
	var bases := Items.droppable_bases(slot, ilvl, allow_spell)
	if bases.is_empty():
		return {}
	var base_id: String = bases[rng.randi_range(0, bases.size() - 1)]
	return Items.make(base_id, roll_rarity(rng, bonus, floor_rarity), ilvl, rng, allow_spell)


## What a slain enemy drops. `last_element` is the element that last hit it ("" = physical).
static func enemy_drops(rng: RandomNumberGenerator, ilvl: int, bonus: float = 0.0, last_element: String = "",
		allow_spell: bool = true, variant: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if rng.randf() < GOLD_CHANCE:
		out.append({"kind": "gold", "amount": rng.randi_range(2, 6) + ilvl})
	if rng.randf() < GEL_CHANCE:
		out.append({"kind": "material", "id": "slime_gel", "amount": 1})
	if rng.randf() < SCRAP_CHANCE:
		out.append({"kind": "material", "id": "scrap", "amount": rng.randi_range(1, 2)})
	if last_element != "" and Items.ENCHANTS.has(last_element) and rng.randf() < ESSENCE_CHANCE:
		out.append({"kind": "material", "id": Items.essence_of(last_element), "amount": 1})
	if variant != "" and Items.ENCHANTS.has(variant) and rng.randf() < VARIANT_ESSENCE_CHANCE:
		out.append({"kind": "material", "id": Items.essence_of(variant), "amount": 1})
	if rng.randf() < GEAR_CHANCE:
		var item := roll_item(rng, ilvl, bonus, "", "common", allow_spell)
		if not item.is_empty():
			out.append({"kind": "item", "item": item})
	var potion := rng.randf()  # last, so the rolls above are unchanged
	if potion < float(Potions.DROP_CHANCE["health"]):
		out.append({"kind": "material", "id": "potion_health", "amount": 1})
	elif potion < float(Potions.DROP_CHANCE["health"]) + float(Potions.DROP_CHANCE["mana"]):
		out.append({"kind": "material", "id": "potion_mana", "amount": 1})
	return out


## A boss: a lot of gold and scrap, two pieces of gear (the first at least rare) and, about half
## the time, an elemental gem for an element the character doesn't have yet (`missing` lists
## those; it is empty for sealed characters and anyone who has them all, who get extra essence).
static func boss_drops(rng: RandomNumberGenerator, ilvl: int, bonus: float = 0.0, missing: Array = [],
		allow_spell: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"kind": "gold", "amount": rng.randi_range(60, 90) + ilvl * 4})
	out.append({"kind": "material", "id": "scrap", "amount": rng.randi_range(8, 12)})
	out.append({"kind": "material", "id": "potion_health", "amount": 1})
	out.append({"kind": "material", "id": "potion_mana", "amount": 1})
	var first := roll_item(rng, ilvl, bonus + 0.5, "", "rare", allow_spell)
	if not first.is_empty():
		out.append({"kind": "item", "item": first})
	var second := roll_item(rng, ilvl, bonus + 0.5, "", "uncommon", allow_spell)
	if not second.is_empty():
		out.append({"kind": "item", "item": second})
	if not missing.is_empty():
		if rng.randf() < GEM_CHANCE:
			out.append({"kind": "material", "id": Items.gem_of(String(missing[rng.randi_range(0, missing.size() - 1)])), "amount": 1})
	else:
		out.append({"kind": "material", "id": Items.essence_of(Items.ENCHANTS.keys()[rng.randi_range(0, Items.ENCHANTS.size() - 1)]), "amount": 3})
	return out


## A mini boss: a purse, scrap, a rare, often an uncommon, and now and then an elemental essence.
static func mini_boss_drops(rng: RandomNumberGenerator, ilvl: int, bonus: float = 0.0, allow_spell: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"kind": "gold", "amount": rng.randi_range(30, 50) + ilvl * 3})
	out.append({"kind": "material", "id": "scrap", "amount": rng.randi_range(4, 7)})
	var first := roll_item(rng, ilvl, bonus + 0.4, "", "rare", allow_spell)
	if not first.is_empty():
		out.append({"kind": "item", "item": first})
	if rng.randf() < 0.5:
		var second := roll_item(rng, ilvl, bonus + 0.3, "", "uncommon", allow_spell)
		if not second.is_empty():
			out.append({"kind": "item", "item": second})
	if rng.randf() < 0.35:
		out.append({"kind": "material", "id": Items.essence_of(Items.ENCHANTS.keys()[rng.randi_range(0, Items.ENCHANTS.size() - 1)]), "amount": 2})
	return out


## A chest: gold, scrap and two pieces of gear, the first at least uncommon.
static func chest_drops(rng: RandomNumberGenerator, ilvl: int, bonus: float = 0.0, allow_spell: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"kind": "gold", "amount": rng.randi_range(20, 40) + ilvl * 2})
	out.append({"kind": "material", "id": "scrap", "amount": rng.randi_range(3, 6)})
	var first := roll_item(rng, ilvl, bonus, "", "uncommon", allow_spell)
	if not first.is_empty():
		out.append({"kind": "item", "item": first})
	var second := roll_item(rng, ilvl, bonus + 0.5, "", "common", allow_spell)
	if not second.is_empty():
		out.append({"kind": "item", "item": second})
	return out
