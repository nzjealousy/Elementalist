class_name Inventory
extends RefCounted
## What a character carries: gold, crafting materials, a bag of unequipped gear and the six
## equipped slots. Pure data + rules (no nodes), saved with the character.
##
## Equipped gear feeds the stat system through mods() (see CharacterData.stat_mods) and the
## equipped weapon decides the character's weapon type (weapon_type()).

signal changed

const BAG_SIZE := 24

var gold := 0
var materials: Dictionary = {}     # material id -> count
var bag: Array[Dictionary] = []    # unequipped items
var equipped: Dictionary = {}      # slot -> item


# ---------- gold and materials ----------

func add_gold(amount: int) -> void:
	gold += amount
	changed.emit()


func add_material(id: String, amount: int = 1) -> void:
	materials[id] = count(id) + amount
	changed.emit()


func count(id: String) -> int:
	return int(materials.get(id, 0))


## A cost is a Dictionary of material id -> amount, with an optional "gold" entry.
func can_pay(cost: Dictionary) -> bool:
	for id in cost:
		var have := gold if id == "gold" else count(id)
		if have < int(cost[id]):
			return false
	return true


## Spends a cost. Nothing is taken if any part can't be paid.
func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	for id in cost:
		if id == "gold":
			gold -= int(cost[id])
		else:
			materials[id] = count(id) - int(cost[id])
	changed.emit()
	return true


## The first part of `cost` that can't be paid, as "Need 8 Scrap", or "" if all can.
func shortfall(cost: Dictionary) -> String:
	for id in cost:
		var have := gold if id == "gold" else count(id)
		if have < int(cost[id]):
			return "Need %d %s" % [int(cost[id]), "gold" if id == "gold" else Items.material_name(id)]
	return ""


## One short line for the HUD-sized screens: "Gold 500  Scrap 12  Gel 3  Ess F2 W1" (essence
## shown by element initial, only what you hold).
func summary() -> String:
	var parts: Array[String] = ["Gold %d" % gold]
	if count("scrap") > 0:
		parts.append("Scrap %d" % count("scrap"))
	if count("slime_gel") > 0:
		parts.append("Gel %d" % count("slime_gel"))
	var essences: Array[String] = []
	for element in Items.ENCHANTS:
		if count(Items.essence_of(element)) > 0:
			essences.append("%s%d" % [String(element)[0].to_upper(), count(Items.essence_of(element))])
	if not essences.is_empty():
		parts.append("Ess " + " ".join(essences))
	var gems: Array[String] = []
	for element in Elements.MAIN + Elements.RARE:
		if count(Items.gem_of(element)) > 0:
			gems.append("%s%d" % [String(element)[0].to_upper(), count(Items.gem_of(element))])
	if not gems.is_empty():
		parts.append("Gems " + " ".join(gems))
	return "  ".join(parts)


# ---------- bag and equipment ----------

func bag_full() -> bool:
	return bag.size() >= BAG_SIZE


func add_item(item: Dictionary) -> bool:
	if bag_full():
		return false
	bag.append(item)
	changed.emit()
	return true


## Wears bag item `index`. Whatever it replaces takes its place in the bag.
func equip(index: int) -> bool:
	if index < 0 or index >= bag.size():
		return false
	var item := bag[index]
	var slot := Items.slot_of(item)
	var old: Dictionary = equipped.get(slot, {})
	bag.remove_at(index)
	equipped[slot] = item
	if not old.is_empty():
		bag.insert(index, old)
	changed.emit()
	return true


## Takes off the item in `slot` into the bag. False if the slot is empty or the bag is full.
func unequip(slot: String) -> bool:
	if not equipped.has(slot) or bag_full():
		return false
	bag.append(equipped[slot])
	equipped.erase(slot)
	changed.emit()
	return true


## Removes bag item `index` and returns it ({} if there is none).
func take_from_bag(index: int) -> Dictionary:
	if index < 0 or index >= bag.size():
		return {}
	var item := bag[index]
	bag.remove_at(index)
	changed.emit()
	return item


## A fall loses the loot of the run: gear picked up in it (tagged "run": the run's seed, see Pickup),
## worn or not, and the materials in `found` (what that run picked up, counted in Game.run). What the hero
## owned before the run stays. Returns how many pieces and materials went.
func lose_run_loot(run_seed: int, found: Dictionary) -> int:
	var lost := 0
	for i in range(bag.size() - 1, -1, -1):
		if int(bag[i].get("run", -1)) == run_seed:
			bag.remove_at(i)
			lost += 1
	for slot in equipped.keys():
		if int(equipped[slot].get("run", -1)) == run_seed:
			equipped.erase(slot)
			lost += 1
	for id in found:
		var gone := mini(int(found[id]), count(id))  # some may have been spent since
		if gone > 0:
			materials[id] = count(id) - gone
			lost += gone
	changed.emit()
	return lost


## The wielded weapon's type, "" when no weapon is equipped.
func weapon_type() -> String:
	if not equipped.has("weapon"):
		return ""
	return Items.weapon_of(equipped["weapon"])


## Every equipped item's stats combined, in passive format: *_add summed, *_mult as 1 + sum
## (so +10% and +5% give x1.15), with a floor so stacked reductions can't reach zero.
func mods() -> Dictionary:
	var sums: Dictionary = {}
	for slot in equipped:
		var item_mods := Items.mods_of(equipped[slot])
		for key in item_mods:
			sums[key] = float(sums.get(key, 0.0)) + float(item_mods[key])
	var out: Dictionary = {}
	for key in sums:
		out[key] = maxf(1.0 + float(sums[key]), 0.4) if String(key).ends_with("_mult") else float(sums[key])
	return out


# ---------- saving ----------

func to_dict() -> Dictionary:
	return {
		"gold": gold,
		"materials": materials.duplicate(),
		"bag": bag.duplicate(true),
		"equipped": equipped.duplicate(true),
	}


## Replaces this inventory's contents from to_dict() output, including after a JSON round trip
## (which turns every integer into a float).
func load_dict(d: Dictionary) -> void:
	gold = int(d.get("gold", 0))
	materials = {}
	for id in d.get("materials", {}):
		materials[id] = int(d["materials"][id])
	bag = []
	for raw in d.get("bag", []):
		bag.append(_clean(raw))
	equipped = {}
	for slot in d.get("equipped", {}):
		equipped[slot] = _clean(d["equipped"][slot])
	changed.emit()


static func _clean(raw: Dictionary) -> Dictionary:
	var item := {
		"base": String(raw["base"]), "rarity": String(raw["rarity"]), "ilvl": int(raw["ilvl"]),
		"plus": int(raw["plus"]), "affixes": [], "enchant": String(raw.get("enchant", "")),
	}
	for affix in raw["affixes"]:
		item["affixes"].append({"mod": String(affix["mod"]), "value": float(affix["value"])})
	if raw.has("run"):
		item["run"] = int(raw["run"])
	return item
