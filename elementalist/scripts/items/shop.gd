class_name Shop
extends RefCounted
## The camp merchant's rules: elemental gems (costly, one of each per camp visit, dearer with every
## one bought) and three rotating legendaries. Static functions over an Inventory and the hero's
## `meta`, so they are testable without any UI. Every `*_problem()` returns why a buy can't happen.

const GEM_BASE_PRICE := 600
const GEM_PRICE_STEP := 0.5          # +50% of the base per gem bought so far ...
const GEM_PRICE_MAX_STEPS := 4       # ... up to x3
const RARE_GEM_TIER := 2             # Light and Dark gems are sold once dungeon 2 is cleared
const LEGENDARY_COUNT := 3
const LEGENDARY_PRICE_MULT := 4      # x the item's value


# ---------- gems ----------

static func gem_price(bought: int) -> int:
	return int(GEM_BASE_PRICE * (1.0 + GEM_PRICE_STEP * mini(bought, GEM_PRICE_MAX_STEPS)))


## Elements whose gem is on sale: the ones the hero lacks (rare ones after dungeon 2), minus those
## already bought this visit (`sold`).
static func gem_offers(c: CharacterData, tier_cleared: int, sold: Array) -> Array[String]:
	var out: Array[String] = []
	for element in c.missing_elements():
		if not (element in sold):
			out.append(element)
	if tier_cleared >= RARE_GEM_TIER:
		for element in c.missing_rare():
			if not (element in sold):
				out.append(element)
	return out


static func gem_problem(c: CharacterData, meta: Dictionary, element: String, sold: Array) -> String:
	if not (element in gem_offers(c, int(meta.get("tier_cleared", 0)), sold)):
		return "Not for sale"
	var price := gem_price(int(meta.get("gems_bought", 0)))
	if c.inventory.gold < price:
		return "Need %d gold" % price
	return ""


## Pays and puts the gem in the materials (the hero attunes with it as with a dropped gem).
static func buy_gem(c: CharacterData, meta: Dictionary, element: String, sold: Array) -> bool:
	if gem_problem(c, meta, element, sold) != "":
		return false
	c.inventory.pay({"gold": gem_price(int(meta.get("gems_bought", 0)))})
	c.inventory.add_material(Items.gem_of(element))
	meta["gems_bought"] = int(meta.get("gems_bought", 0)) + 1
	sold.append(element)
	return true


# ---------- legendaries ----------

## Three legendaries in different slots, item level = hero level + 2 per dungeon cleared.
## Each entry: {"item": Dictionary, "price": int, "sold": bool}.
static func roll_stock(rng: RandomNumberGenerator, level: int, tier_cleared: int, allow_spell: bool) -> Array[Dictionary]:
	var slots: Array = Items.SLOTS.duplicate()
	var out: Array[Dictionary] = []
	for i in LEGENDARY_COUNT:
		var slot: String = slots.pop_at(rng.randi_range(0, slots.size() - 1))
		var ilvl := level + 2 * tier_cleared
		var bases := Items.droppable_bases(slot, ilvl, allow_spell)
		if bases.is_empty():
			bases = Items.gear_bases(slot).filter(func(id): return allow_spell or not Items.is_spell_only(id))
		if bases.is_empty():
			continue
		var item := Items.make(bases[rng.randi_range(0, bases.size() - 1)], "legendary", ilvl, rng, allow_spell)
		out.append({"item": item, "price": Items.value_of(item) * LEGENDARY_PRICE_MULT, "sold": false})
	return out


static func legendary_problem(inv: Inventory, stock: Array, index: int) -> String:
	if index < 0 or index >= stock.size() or stock[index]["sold"]:
		return "Sold"
	if inv.bag_full():
		return "Bag full"
	if inv.gold < int(stock[index]["price"]):
		return "Need %d gold" % int(stock[index]["price"])
	return ""


static func buy_legendary(inv: Inventory, stock: Array, index: int) -> bool:
	if legendary_problem(inv, stock, index) != "":
		return false
	inv.pay({"gold": int(stock[index]["price"])})
	inv.add_item(stock[index]["item"])
	stock[index]["sold"] = true
	return true
