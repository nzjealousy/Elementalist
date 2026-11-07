class_name Potions
extends RefCounted
## Health and mana potions: bag materials ("potion_health", "potion_mana"), at most MAX_CARRY of each,
## drunk with H / J (pad L3 / R3), one drink per COOLDOWN seconds for both kinds. Bought from the camp
## merchant or found (rare enemy drops, always from a boss). Rules only; Player does the drinking.

const KINDS := ["health", "mana"]
const MAX_CARRY := 5
const HEAL_SHARE := 0.4    # of max HP
const MANA_SHARE := 0.5    # of max mana
const COOLDOWN := 1.5
const PRICES := {"health": 120, "mana": 100}
const DROP_CHANCE := {"health": 0.03, "mana": 0.02}   # per slain monster, one roll for both


static func id_of(kind: String) -> String:
	return "potion_" + kind


static func is_potion(material_id: String) -> bool:
	return material_id in ["potion_health", "potion_mana"]


## Why the potion can't be drunk ("" when it can). `full` = the stat it restores is already at its maximum.
static func drink_problem(inv: Inventory, kind: String, full: bool) -> String:
	if inv.count(id_of(kind)) <= 0:
		return "No %s potion" % kind
	if full:
		return "Already full"
	return ""


## Puts up to `amount` in the bag, never past MAX_CARRY. Returns how many were taken.
static func add(inv: Inventory, kind: String, amount: int = 1) -> int:
	var taken := clampi(MAX_CARRY - inv.count(id_of(kind)), 0, amount)
	if taken > 0:
		inv.add_material(id_of(kind), taken)
	return taken


static func buy_problem(inv: Inventory, kind: String) -> String:
	if inv.count(id_of(kind)) >= MAX_CARRY:
		return "Carrying %d already" % MAX_CARRY
	if inv.gold < int(PRICES[kind]):
		return "Need %d gold" % int(PRICES[kind])
	return ""


static func buy(inv: Inventory, kind: String) -> bool:
	if buy_problem(inv, kind) != "":
		return false
	inv.pay({"gold": int(PRICES[kind])})
	add(inv, kind)
	return true
