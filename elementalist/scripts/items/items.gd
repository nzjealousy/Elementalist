class_name Items
extends RefCounted
## Static tables and rules for gear and materials. Data only, no scene dependencies, so it is
## safe to read from anywhere (and from tests).
##
## An ITEM is a plain, JSON-safe Dictionary (so it saves and loads for free):
##   {"base": "iron_sword", "rarity": "rare", "ilvl": 4, "plus": 2,
##    "affixes": [{"mod": "max_hp_add", "value": 6.4}, ...], "enchant": "fire"}
##
## Item stats use the SAME mod names as passives (see Classes), so gear, passives and attributes
## all feed one aggregator (CharacterData.stat_mods). Here an item mod's value is an AMOUNT:
##   *_add keys   are added as they are              (max_hp_add 6 = +6 HP)
##   *_mult keys  are the bonus fraction             (melee_damage_mult 0.10 = +10%)
## Inventory.mods() converts them to passive format (1 + sum for *_mult).
##
## How big an item's numbers are:
##   base mods x level scale (ilvl) x rarity scale x upgrade scale (+N)
##   affix rolls x level scale x upgrade scale        (rarity decides HOW MANY affixes)
##   enchant mods x upgrade scale

const SLOTS := ["weapon", "head", "body", "feet", "ring", "amulet"]
const SLOT_NAMES := {
	"weapon": "Weapon", "head": "Head", "body": "Body", "feet": "Feet", "ring": "Ring", "amulet": "Amulet",
}

const MAX_PLUS := 10
const UPGRADE_STEP := 0.10  # every + adds this share of an item's stats
const LEVEL_STEP := 0.08    # every item level above 1 adds this share

const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
## affixes: random bonuses rolled; scale: multiplies the base mods; weight: drop chance;
## value: sale price multiplier; scrap: salvage yield; cost: forge price multiplier.
const RARITY := {
	"common": {"name": "Common", "color": Color("c8c8c8"), "affixes": 0, "scale": 1.0, "weight": 60.0, "value": 1, "scrap": 1, "cost": 1.0},
	"uncommon": {"name": "Uncommon", "color": Color("6fe06f"), "affixes": 1, "scale": 1.15, "weight": 28.0, "value": 2, "scrap": 2, "cost": 1.3},
	"rare": {"name": "Rare", "color": Color("5aa8ff"), "affixes": 2, "scale": 1.3, "weight": 9.0, "value": 5, "scrap": 4, "cost": 1.7},
	"epic": {"name": "Epic", "color": Color("c26bff"), "affixes": 3, "scale": 1.5, "weight": 2.5, "value": 12, "scrap": 7, "cost": 2.2},
	"legendary": {"name": "Legendary", "color": Color("ffa733"), "affixes": 4, "scale": 1.8, "weight": 0.5, "value": 30, "scrap": 12, "cost": 3.0},
}

## Display names for item mods.
const MOD_NAMES := {
	"max_hp_add": "Max HP", "max_mana_add": "Max mana", "max_stamina_add": "Max stamina",
	"hp_regen_add": "HP regen", "mana_regen_add": "Mana regen", "stamina_regen_add": "Stamina regen",
	"move_speed_mult": "Move speed", "melee_damage_mult": "Melee damage", "spell_damage_mult": "Spell damage",
	"damage_taken_mult": "Damage taken", "spell_cooldown_mult": "Spell cooldowns", "melee_range_mult": "Melee reach",
	"melee_stamina_cost_mult": "Slash stamina cost", "projectile_speed_mult": "Bolt speed",
	"fusion_damage_mult": "Fused damage", "burn_time_mult": "Burn time",
	"crit_chance_add": "Crit chance", "crit_damage_add": "Crit damage", "buff_duration_mult": "Buff duration",
	"attack_speed_mult": "Attack speed", "mana_cost_mult": "Mana costs", "dodge_cost_mult": "Dodge stamina cost",
	"kill_hp_add": "HP on kill", "kill_mana_add": "Mana on kill", "kill_stamina_add": "Stamina on kill",
}

## *_add stats that are fractions, shown as percentages.
const PERCENT_ADD := ["crit_chance_add", "crit_damage_add"]

## Mods that only matter to characters with elements (mana and spells). Characters who can never
## hold elements (sealed) are not given items that are nothing but these.
const SPELL_MODS := [
	"max_mana_add", "mana_regen_add", "spell_damage_mult", "spell_cooldown_mult",
	"fusion_damage_mult", "projectile_speed_mult", "burn_time_mult", "buff_duration_mult",
	"mana_cost_mult", "kill_mana_add",
]

## Random bonuses. "min"/"max" are the roll range at item level 1; prefix/suffix build the name.
const AFFIXES := [
	{"mod": "max_hp_add", "min": 5.0, "max": 12.0, "prefix": "Sturdy", "suffix": "of Vigor"},
	{"mod": "max_mana_add", "min": 6.0, "max": 14.0, "prefix": "Arcane", "suffix": "of the Well"},
	{"mod": "max_stamina_add", "min": 6.0, "max": 14.0, "prefix": "Hardy", "suffix": "of Endurance"},
	{"mod": "hp_regen_add", "min": 0.08, "max": 0.2, "prefix": "Mending", "suffix": "of Recovery"},
	{"mod": "mana_regen_add", "min": 0.3, "max": 0.8, "prefix": "Flowing", "suffix": "of Tides"},
	{"mod": "stamina_regen_add", "min": 2.0, "max": 4.0, "prefix": "Tireless", "suffix": "of Stamina"},
	{"mod": "move_speed_mult", "min": 0.02, "max": 0.05, "prefix": "Swift", "suffix": "of the Wind"},
	{"mod": "melee_damage_mult", "min": 0.03, "max": 0.07, "prefix": "Keen", "suffix": "of Edges"},
	{"mod": "spell_damage_mult", "min": 0.03, "max": 0.07, "prefix": "Potent", "suffix": "of Power"},
	{"mod": "damage_taken_mult", "min": -0.04, "max": -0.02, "prefix": "Warded", "suffix": "of Warding"},
	{"mod": "spell_cooldown_mult", "min": -0.05, "max": -0.02, "prefix": "Quick", "suffix": "of Haste"},
	{"mod": "melee_range_mult", "min": 0.03, "max": 0.08, "prefix": "Long", "suffix": "of Reach"},
	{"mod": "melee_stamina_cost_mult", "min": -0.08, "max": -0.03, "prefix": "Light", "suffix": "of Ease"},
	{"mod": "projectile_speed_mult", "min": 0.04, "max": 0.10, "prefix": "Flying", "suffix": "of Arrows"},
	{"mod": "fusion_damage_mult", "min": 0.04, "max": 0.10, "prefix": "Blending", "suffix": "of Fusion"},
	{"mod": "crit_chance_add", "min": 0.01, "max": 0.03, "prefix": "Deadly", "suffix": "of Precision"},
	{"mod": "crit_damage_add", "min": 0.05, "max": 0.15, "prefix": "Brutal", "suffix": "of Ruin"},
	{"mod": "attack_speed_mult", "min": 0.03, "max": 0.07, "prefix": "Rapid", "suffix": "of Speed"},
	{"mod": "mana_cost_mult", "min": -0.06, "max": -0.03, "prefix": "Frugal", "suffix": "of Thrift"},
	{"mod": "dodge_cost_mult", "min": -0.12, "max": -0.05, "prefix": "Agile", "suffix": "of Evasion"},
	{"mod": "kill_hp_add", "min": 1.0, "max": 3.0, "prefix": "Ravenous", "suffix": "of Feasting"},
	{"mod": "kill_mana_add", "min": 1.5, "max": 4.0, "prefix": "Siphoning", "suffix": "of Draining"},
	{"mod": "kill_stamina_add", "min": 3.0, "max": 7.0, "prefix": "Driven", "suffix": "of Momentum"},
]

## Gear. "mods" are amounts at item level 1, common rarity. "weapon" (weapons only) is the weapon
## type: wielding it decides which weapon mastery you train. "starter" gear is what a new
## character holds; it never drops. "craft" is the forge price (gold + materials); "min_ilvl" is
## the lowest item level at which the base drops.
const BASES := {
	# starter weapons
	"worn_sword": {"name": "Worn Sword", "slot": "weapon", "weapon": "sword", "starter": true, "mods": {"melee_damage_mult": 0.08}},
	"worn_staff": {"name": "Worn Staff", "slot": "weapon", "weapon": "staff", "starter": true, "mods": {"spell_damage_mult": 0.08, "max_mana_add": 5.0}},
	"worn_bow": {"name": "Worn Bow", "slot": "weapon", "weapon": "bow", "starter": true, "mods": {"melee_damage_mult": 0.04, "projectile_speed_mult": 0.06}},
	"worn_rod": {"name": "Worn Rod", "slot": "weapon", "weapon": "rod", "starter": true, "mods": {"max_mana_add": 8.0}},
	"worn_dagger": {"name": "Worn Dagger", "slot": "weapon", "weapon": "dagger", "starter": true, "mods": {"melee_damage_mult": 0.04, "crit_chance_add": 0.01}},
	"worn_axe": {"name": "Worn Axe", "slot": "weapon", "weapon": "axe", "starter": true, "mods": {"melee_damage_mult": 0.1}},
	"worn_tome": {"name": "Worn Tome", "slot": "weapon", "weapon": "tome", "starter": true, "mods": {"spell_damage_mult": 0.06, "mana_regen_add": 0.25}},
	# weapons
	"iron_sword": {"name": "Iron Sword", "slot": "weapon", "weapon": "sword", "min_ilvl": 2, "craft": {"scrap": 8, "gold": 30}, "mods": {"melee_damage_mult": 0.18, "melee_range_mult": 0.05}},
	"hunter_bow": {"name": "Hunter's Bow", "slot": "weapon", "weapon": "bow", "min_ilvl": 2, "craft": {"scrap": 8, "slime_gel": 3, "gold": 30}, "mods": {"melee_damage_mult": 0.08, "projectile_speed_mult": 0.12}},
	"oak_staff": {"name": "Oak Staff", "slot": "weapon", "weapon": "staff", "min_ilvl": 2, "craft": {"scrap": 8, "gold": 30}, "mods": {"spell_damage_mult": 0.15, "max_mana_add": 10.0}},
	"bone_rod": {"name": "Bone Rod", "slot": "weapon", "weapon": "rod", "min_ilvl": 2, "craft": {"scrap": 8, "slime_gel": 2, "gold": 30}, "mods": {"max_mana_add": 14.0, "spell_cooldown_mult": -0.05}},
	"steel_dagger": {"name": "Steel Dagger", "slot": "weapon", "weapon": "dagger", "min_ilvl": 2, "craft": {"scrap": 8, "gold": 30}, "mods": {"melee_damage_mult": 0.1, "crit_chance_add": 0.03}},
	"battle_axe": {"name": "Battle Axe", "slot": "weapon", "weapon": "axe", "min_ilvl": 2, "craft": {"scrap": 9, "gold": 35}, "mods": {"melee_damage_mult": 0.22, "melee_range_mult": 0.04}},
	"scribe_tome": {"name": "Scribe's Tome", "slot": "weapon", "weapon": "tome", "min_ilvl": 2, "craft": {"scrap": 8, "slime_gel": 2, "gold": 30}, "mods": {"spell_damage_mult": 0.12, "mana_regen_add": 0.6}},
	# armour and trinkets
	"leather_cap": {"name": "Leather Cap", "slot": "head", "craft": {"scrap": 4, "slime_gel": 2, "gold": 15}, "mods": {"max_hp_add": 6.0}},
	"iron_helm": {"name": "Iron Helm", "slot": "head", "min_ilvl": 3, "craft": {"scrap": 7, "gold": 25}, "mods": {"max_hp_add": 8.0, "damage_taken_mult": -0.02}},
	"scholar_hood": {"name": "Scholar's Hood", "slot": "head", "craft": {"scrap": 5, "slime_gel": 2, "gold": 20}, "mods": {"max_mana_add": 8.0, "spell_damage_mult": 0.03}},
	"padded_tunic": {"name": "Padded Tunic", "slot": "body", "craft": {"scrap": 5, "slime_gel": 3, "gold": 20}, "mods": {"max_hp_add": 10.0}},
	"chain_mail": {"name": "Chain Mail", "slot": "body", "min_ilvl": 3, "craft": {"scrap": 10, "gold": 40}, "mods": {"max_hp_add": 14.0, "damage_taken_mult": -0.03}},
	"mage_robe": {"name": "Mage Robe", "slot": "body", "craft": {"scrap": 6, "slime_gel": 3, "gold": 25}, "mods": {"max_mana_add": 12.0, "mana_regen_add": 0.4}},
	"travel_boots": {"name": "Travel Boots", "slot": "feet", "craft": {"scrap": 4, "slime_gel": 2, "gold": 15}, "mods": {"move_speed_mult": 0.04}},
	"runner_boots": {"name": "Runner Boots", "slot": "feet", "min_ilvl": 3, "craft": {"scrap": 7, "gold": 25}, "mods": {"move_speed_mult": 0.05, "stamina_regen_add": 2.0}},
	"copper_ring": {"name": "Copper Ring", "slot": "ring", "craft": {"scrap": 4, "gold": 20}, "mods": {"hp_regen_add": 0.08}},
	"silver_ring": {"name": "Silver Ring", "slot": "ring", "min_ilvl": 3, "craft": {"scrap": 6, "gold": 35}, "mods": {"melee_damage_mult": 0.03, "spell_damage_mult": 0.03}},
	"bone_amulet": {"name": "Bone Amulet", "slot": "amulet", "craft": {"scrap": 4, "slime_gel": 2, "gold": 20}, "mods": {"max_stamina_add": 8.0}},
	"lucky_charm": {"name": "Lucky Charm", "slot": "amulet", "min_ilvl": 3, "craft": {"scrap": 6, "gold": 35}, "mods": {"max_hp_add": 6.0, "kill_hp_add": 1.0}},
}

## Enchanting: infuse gear with a main element's essence. Re-enchanting replaces the old enchant.
const ENCHANTS := {
	"fire": {"name": "Flame", "mods": {"melee_damage_mult": 0.06, "burn_time_mult": 0.2}},
	"water": {"name": "Tide", "mods": {"stamina_regen_add": 2.5}},
	"earth": {"name": "Stone", "mods": {"max_hp_add": 8.0}},
	"air": {"name": "Gale", "mods": {"move_speed_mult": 0.04, "attack_speed_mult": 0.03}},
	"mineral": {"name": "Bulwark", "mods": {"damage_taken_mult": -0.03}},
}

const MATERIALS := {
	"scrap": {"name": "Scrap", "color": Color("b0b0b8")},
	"slime_gel": {"name": "Slime Gel", "color": Color("6bd66b")},
	"essence_fire": {"name": "Fire Essence", "color": Color("ff6a2b")},
	"essence_water": {"name": "Water Essence", "color": Color("3fa7ff")},
	"essence_earth": {"name": "Earth Essence", "color": Color("5fbf4a")},
	"essence_air": {"name": "Air Essence", "color": Color("d9f2ff")},
	"essence_mineral": {"name": "Mineral Essence", "color": Color("b5a58a")},
	"potion_health": {"name": "Health Potion", "color": Color("e0455a")},
	"potion_mana": {"name": "Mana Potion", "color": Color("4aa0ff")},
	# Elemental gems: dropped by bosses. Using one attunes you to its element (CharacterData.use_gem).
	"gem_fire": {"name": "Fire Gem", "color": Color("ff6a2b")},
	"gem_water": {"name": "Water Gem", "color": Color("3fa7ff")},
	"gem_earth": {"name": "Earth Gem", "color": Color("5fbf4a")},
	"gem_air": {"name": "Air Gem", "color": Color("d9f2ff")},
	"gem_mineral": {"name": "Mineral Gem", "color": Color("b5a58a")},
	"gem_light": {"name": "Light Gem", "color": Color("fff3a8")},
	"gem_dark": {"name": "Dark Gem", "color": Color("7a3fb5")},
}


# ---------- lookups ----------

static func base_of(item: Dictionary) -> Dictionary:
	return BASES[item["base"]]


static func slot_of(item: Dictionary) -> String:
	return String(base_of(item)["slot"])


## The weapon type of a weapon item ("sword", "staff", ...), "" for anything else.
static func weapon_of(item: Dictionary) -> String:
	return String(base_of(item).get("weapon", ""))


static func rarity_info(item: Dictionary) -> Dictionary:
	return RARITY[item["rarity"]]


static func rarity_color(item: Dictionary) -> Color:
	return rarity_info(item)["color"]


static func material_name(id: String) -> String:
	return String(MATERIALS[id]["name"]) if MATERIALS.has(id) else id


static func essence_of(element: String) -> String:
	return "essence_" + element


static func gem_of(element: String) -> String:
	return "gem_" + element


## The worn weapon a new character holds for a weapon type.
static func starter_for(weapon_type: String) -> String:
	for id in BASES:
		if BASES[id].get("starter", false) and BASES[id].get("weapon", "") == weapon_type:
			return id
	return ""


static func is_starter(item: Dictionary) -> bool:
	return base_of(item).get("starter", false)


## True when every stat on a base is spell-only (a staff, a mage robe).
static func is_spell_only(base_id: String) -> bool:
	for key in BASES[base_id]["mods"]:
		if not (key in SPELL_MODS):
			return false
	return true


## Gear that can be crafted or dropped (everything except starter gear), optionally one slot.
static func gear_bases(slot: String = "") -> Array:
	return BASES.keys().filter(func(id): return not BASES[id].get("starter", false) and (slot == "" or BASES[id]["slot"] == slot))


## Bases that can drop at `ilvl`; sealed characters (allow_spell false) skip spell-only gear.
static func droppable_bases(slot: String, ilvl: int, allow_spell: bool) -> Array:
	return gear_bases(slot).filter(func(id): return int(BASES[id].get("min_ilvl", 1)) <= ilvl and (allow_spell or not is_spell_only(id)))


# ---------- making items ----------

## Builds an item. Affix count comes from the rarity; `rng` makes it reproducible. Characters
## who can never use spells (allow_spell false) get no spell affixes.
static func make(base_id: String, rarity: String, ilvl: int, rng: RandomNumberGenerator, allow_spell: bool = true) -> Dictionary:
	var item := {"base": base_id, "rarity": rarity, "ilvl": maxi(ilvl, 1), "plus": 0, "affixes": [], "enchant": ""}
	var pool: Array = AFFIXES.filter(func(a): return allow_spell or not (a["mod"] in SPELL_MODS))
	for i in int(RARITY[rarity]["affixes"]):
		var pick: int = rng.randi_range(0, pool.size() - 1)
		var affix: Dictionary = pool[pick]
		pool.remove_at(pick)  # no duplicate affixes on one item
		var value := snappedf(lerpf(float(affix["min"]), float(affix["max"]), rng.randf()), 0.01)
		item["affixes"].append({"mod": affix["mod"], "value": value})
	return item


static func affix_def(mod: String) -> Dictionary:
	for affix in AFFIXES:
		if affix["mod"] == mod:
			return affix
	return {}


# ---------- reading items ----------

static func upgrade_scale(item: Dictionary) -> float:
	return 1.0 + UPGRADE_STEP * int(item["plus"])


static func level_scale(item: Dictionary) -> float:
	return 1.0 + LEVEL_STEP * (int(item["ilvl"]) - 1)


## All of an item's stat amounts after level, rarity, upgrade and enchant: mod name -> amount.
static func mods_of(item: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var up := upgrade_scale(item)
	var lvl := level_scale(item)
	var base_mods: Dictionary = base_of(item)["mods"]
	for key in base_mods:
		out[key] = float(out.get(key, 0.0)) + float(base_mods[key]) * lvl * float(rarity_info(item)["scale"]) * up
	for affix in item["affixes"]:
		out[affix["mod"]] = float(out.get(affix["mod"], 0.0)) + float(affix["value"]) * lvl * up
	if item["enchant"] != "":
		var enchant_mods: Dictionary = ENCHANTS[item["enchant"]]["mods"]
		for key in enchant_mods:
			out[key] = float(out.get(key, 0.0)) + float(enchant_mods[key]) * up
	return out


## "+12 Max HP", "+8% Melee damage", "-3% Damage taken".
static func format_mod(key: String, amount: float) -> String:
	var label := String(MOD_NAMES.get(key, key))
	if key.ends_with("_mult") or key in PERCENT_ADD:
		return "%+d%% %s" % [roundi(amount * 100.0), label]
	if absf(amount - roundf(amount)) > 0.05:
		return "%+.1f %s" % [amount, label]
	return "%+d %s" % [roundi(amount), label]


## Name with affix prefix/suffix, upgrade level and enchant: "Sturdy Iron Sword of Edges +2".
static func display_name(item: Dictionary) -> String:
	var text := String(base_of(item)["name"])
	var affixes: Array = item["affixes"]
	if affixes.size() >= 1:
		text = "%s %s" % [affix_def(affixes[0]["mod"])["prefix"], text]
	if affixes.size() >= 2:
		text = "%s %s" % [text, affix_def(affixes[1]["mod"])["suffix"]]
	if int(item["plus"]) > 0:
		text += " +%d" % int(item["plus"])
	return text


## Full multi-line description for tooltips and the gear tab.
static func describe(item: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(display_name(item))
	var kind := String(SLOT_NAMES[slot_of(item)])
	if weapon_of(item) != "":
		kind = "%s (%s)" % [kind, weapon_of(item).capitalize()]
	lines.append("%s %s, item level %d" % [rarity_info(item)["name"], kind, int(item["ilvl"])])
	var mods := mods_of(item)
	for key in mods:
		lines.append(format_mod(key, float(mods[key])))
	if item["enchant"] != "":
		lines.append("Enchanted: %s" % ENCHANTS[item["enchant"]]["name"])
	lines.append("Upgrade +%d/%d" % [int(item["plus"]), MAX_PLUS])
	return "\n".join(lines)


# ---------- value ----------

## Gold the item is worth.
static func value_of(item: Dictionary) -> int:
	return int((6 + 2 * int(item["ilvl"])) * int(rarity_info(item)["value"]) * (1.0 + 0.25 * int(item["plus"])))


## What salvaging returns: scrap by rarity and upgrade level, and a quarter of its value in gold.
static func salvage_yield(item: Dictionary) -> Dictionary:
	return {"scrap": int(rarity_info(item)["scrap"]) + int(item["plus"]), "gold": floori(value_of(item) / 4.0)}
