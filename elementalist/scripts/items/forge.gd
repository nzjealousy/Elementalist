class_name Forge
extends RefCounted
## The forge's rules: craft gear, upgrade it (+1 to +10), enchant it with an element's essence,
## and salvage unwanted gear. Static functions over an Inventory, so they are testable.
##
## Each action has a `*_problem()` that returns why it can't be done ("" when it can), which the
## forge screen uses to disable buttons and show a reason.

## Crafted gear rolls rarity from these weights (it can't be better than rare).
const CRAFT_WEIGHTS := {"common": 55.0, "uncommon": 35.0, "rare": 10.0}


# ---------- craft ----------

static func craft_cost(base_id: String) -> Dictionary:
	return Items.BASES[base_id].get("craft", {})


static func craft_problem(inv: Inventory, base_id: String) -> String:
	if craft_cost(base_id).is_empty():
		return "Can't be crafted"
	if inv.bag_full():
		return "Bag full"
	return inv.shortfall(craft_cost(base_id))


## Pays for and creates the item at item level `ilvl`. Returns {} if it can't be done.
static func craft(inv: Inventory, base_id: String, ilvl: int, rng: RandomNumberGenerator, allow_spell: bool = true) -> Dictionary:
	if craft_problem(inv, base_id) != "":
		return {}
	inv.pay(craft_cost(base_id))
	var item := Items.make(base_id, Loot.pick_weighted(rng, CRAFT_WEIGHTS), ilvl, rng, allow_spell)
	inv.add_item(item)
	return item


# ---------- upgrade ----------

static func upgrade_cost(item: Dictionary) -> Dictionary:
	var plus := int(item["plus"])
	var mult := float(Items.rarity_info(item)["cost"])
	return {"gold": int(round(20.0 * (plus + 1) * mult)), "scrap": 2 + plus}


static func upgrade_problem(inv: Inventory, item: Dictionary) -> String:
	if int(item["plus"]) >= Items.MAX_PLUS:
		return "Fully upgraded"
	return inv.shortfall(upgrade_cost(item))


## +1 on the item (always succeeds: this game is forgiving). `item` is edited in place, so it
## works for equipped and bagged items alike.
static func upgrade(inv: Inventory, item: Dictionary) -> bool:
	if upgrade_problem(inv, item) != "":
		return false
	inv.pay(upgrade_cost(item))
	item["plus"] = int(item["plus"]) + 1
	inv.changed.emit()
	return true


# ---------- enchant ----------

static func enchant_cost(item: Dictionary, element: String) -> Dictionary:
	return {
		"gold": int(round(40.0 * float(Items.rarity_info(item)["cost"]))),
		Items.essence_of(element): 1 + floori(int(item["ilvl"]) / 8.0),
	}


static func enchant_problem(inv: Inventory, item: Dictionary, element: String) -> String:
	if not Items.ENCHANTS.has(element):
		return "Unknown element"
	if item["enchant"] == element:
		return "Already enchanted"
	return inv.shortfall(enchant_cost(item, element))


## Infuses the item; an earlier enchant is replaced.
static func enchant(inv: Inventory, item: Dictionary, element: String) -> bool:
	if enchant_problem(inv, item, element) != "":
		return false
	inv.pay(enchant_cost(item, element))
	item["enchant"] = element
	inv.changed.emit()
	return true


# ---------- salvage ----------

## Breaks bag item `index` down into scrap and gold. Returns what was gained ({} if no item).
static func salvage(inv: Inventory, index: int) -> Dictionary:
	if index < 0 or index >= inv.bag.size():
		return {}
	var gain := Items.salvage_yield(inv.bag[index])
	inv.take_from_bag(index)
	inv.add_material("scrap", int(gain["scrap"]))
	inv.add_gold(int(gain["gold"]))
	return gain
