class_name Classes
extends RefCounted
## Static tables for classes, subclasses, passives, traits and attribute scaling.
## Data only, no scene dependencies, so it is safe to read from anywhere (and from tests).
##
## Progression gates (same for every character):
##   level 1   primary skill (LMB) of each owned element, and the martial set
##   level 3   choose a class (until then you are a Novice)
##   level 5   area skill (F) unlocked. Q (element locking) needs two or more elements, not a level
##   (reward)  special skill (R) learned from a level reward
##   level 10  choose a subclass
##   milestone levels (see Rewards) offer a skill or passive reward
##
## PASSIVES come in four types (see CharacterData.passive_sources):
##   class    fixed, from the class and chosen subclass
##   trait    tied to the character; rolled at creation or earned as a level reward. Characters
##            with fewer other passive sources (e.g. non-elementalists) tend to roll more of
##            them (Ceremony.roll_traits)
##   element  rare: unlocked at element mastery RARE_PASSIVE_LEVEL (also weapon mastery)
##   skill    rare: unlocked by using one skill many times (see skill_passive_uses)
##
## Passive "mods" use a naming convention the aggregator relies on:
##   *_add   summed          (e.g. max_hp_add, mana_regen_add)
##   *_mult  multiplied      (e.g. melee_damage_mult, damage_taken_mult)
## Per-skill mods are named "<skill_id>_damage_mult" / "<skill_id>_cooldown_mult".

const ATTRIBUTES := ["strength", "agility", "intellect", "vitality"]
const MAX_LOCKED := 3  # elements that can be locked together (Q) to fuse into one cast
const CLASS_LEVEL := 3     # level at which a Novice chooses a class
const AREA_LEVEL := 5      # level at which area skills (Q) unlock, for everyone
const SUBCLASS_LEVEL := 10
const RARE_PASSIVE_LEVEL := 5  # element / weapon mastery level that unlocks its passive

## The class everyone starts as. All attributes 5, no growth, no passives: the baseline the
## combat numbers were tuned against, also used by tests.
const NEUTRAL_CLASS := "wanderer"

## Level at which each skill slot is learned. "special" (R) skills are learned from rewards.
const SKILL_LEVELS := {"primary": 1, "area": AREA_LEVEL}

## The attribute that governs each element's potency (status duration and strength).
const ELEMENT_ATTRIBUTE := {
	"fire": "strength", "water": "agility", "earth": "vitality", "air": "agility",
	"mineral": "strength", "light": "vitality", "dark": "intellect",
}
const POTENCY_PER_POINT := 0.03  # per attribute point above/below 5

## How much one attribute point above/below 5 changes a skill property (see SkillDB "scales").
const SCALE_RATE := {"radius": 0.03, "knockback": 0.05, "speed": 0.03, "cooldown": -0.02}

# Balance: every playable class has the same 21 attribute points when chosen and +1 per level in
# its favoured attribute, so classes differ in shape, reach and passives, not raw power.
# "melee_range" multiplies the slash's reach: fighters reach far, casters barely at all.
const CLASSES := {
	"channeler": {
		"name": "Channeler",
		"desc": "Ranged caster: shoots while imbued, slashes (short reach) when not. Huge mana, fragile.",
		"style": "ranged",
		"base": {"strength": 3, "agility": 5, "intellect": 9, "vitality": 4},
		"per_level": {"intellect": 1},
		"melee_range": 0.75,
		"weapon": "staff",
		"passives": ["arcane_focus"],
		"subclasses": ["spellweaver", "warden"],
	},
	"vanguard": {
		"name": "Vanguard",
		"desc": "Melee fighter: RMB always slashes. Elements come from imbuing the blade, fused casts and abilities. Longest reach. With no elements, LMB slashes too.",
		"style": "melee",
		"base": {"strength": 8, "agility": 4, "intellect": 3, "vitality": 6},
		"per_level": {"strength": 1},
		"melee_range": 1.4,
		"weapon": "sword",
		"passives": ["toughened"],
		"subclasses": ["duelist", "bulwark"],
	},
	"ranger": {
		"name": "Ranger",
		"desc": "Ranged skirmisher: shoots while imbued, short blade otherwise. Fast, quick bolts, modest health.",
		"style": "ranged",
		"base": {"strength": 5, "agility": 8, "intellect": 4, "vitality": 4},
		"per_level": {"agility": 1},
		"melee_range": 0.9,
		"weapon": "bow",
		"passives": ["fleet_footed"],
		"subclasses": ["sharpshooter", "pathfinder"],
	},
	"mystic": {
		"name": "Mystic",
		"desc": "Ranged hybrid: shoots while imbued, average reach otherwise. Faster spell cooldowns, sturdy.",
		"style": "ranged",
		"base": {"strength": 3, "agility": 4, "intellect": 7, "vitality": 7},
		"per_level": {"vitality": 1},
		"melee_range": 1.0,
		"weapon": "rod",
		"passives": ["attuned"],
		"subclasses": ["oracle", "spiritblade"],
	},
	"wanderer": {
		"name": "Novice",
		"desc": "No class yet. Choose one at level %d. Imbue (E) to shoot with RMB." % CLASS_LEVEL,
		"style": "ranged",
		"base": {"strength": 5, "agility": 5, "intellect": 5, "vitality": 5},
		"per_level": {},
		"melee_range": 1.0,
		"weapon": "sword",
		"passives": [],
		"subclasses": [],
		"starter": true,
	},
}

const SUBCLASSES := {
	"spellweaver": {"name": "Spellweaver", "desc": "Burst caster: +10% spell damage.", "passives": ["spellweaver_focus"]},
	"warden": {"name": "Warden", "desc": "Protective caster: -8% damage taken.", "passives": ["warden_ward"]},
	"duelist": {"name": "Duelist", "desc": "Agile fighter: slashes cost 15% less stamina, +10% reach.", "passives": ["duelist_footwork"]},
	"bulwark": {"name": "Bulwark", "desc": "Immovable fighter: -10% damage taken, +10 HP.", "passives": ["bulwark_guard"]},
	"sharpshooter": {"name": "Sharpshooter", "desc": "Faster bolts, +5% spell damage.", "passives": ["sharpshooter_aim"]},
	"pathfinder": {"name": "Pathfinder", "desc": "Tireless: +8 stamina regen, +4% speed.", "passives": ["pathfinder_stride"]},
	"oracle": {"name": "Oracle", "desc": "+2 mana regen, +20 max mana.", "passives": ["oracle_insight"]},
	"spiritblade": {"name": "Spiritblade", "desc": "+15% melee damage, +15% reach, slashes cost 10% less.", "passives": ["spiritblade_focus"]},
}

const PASSIVES := {
	# class
	"arcane_focus": {"name": "Arcane Focus", "desc": "+2 mana regen", "mods": {"mana_regen_add": 2.0}},
	"toughened": {"name": "Toughened", "desc": "+12 max HP, +10% melee damage", "mods": {"max_hp_add": 12.0, "melee_damage_mult": 1.1}},
	"fleet_footed": {"name": "Fleet-footed", "desc": "+8% move speed, +10% bolt speed", "mods": {"move_speed_mult": 1.08, "projectile_speed_mult": 1.1}},
	"attuned": {"name": "Attuned", "desc": "-7% spell cooldowns, +1 mana regen", "mods": {"spell_cooldown_mult": 0.93, "mana_regen_add": 1.0}},
	# subclass (class type)
	"spellweaver_focus": {"name": "Spellweaver Focus", "desc": "+10% spell damage", "mods": {"spell_damage_mult": 1.1}},
	"warden_ward": {"name": "Warding", "desc": "-8% damage taken", "mods": {"damage_taken_mult": 0.92}},
	"duelist_footwork": {"name": "Footwork", "desc": "-15% slash stamina cost, +10% reach", "mods": {"melee_stamina_cost_mult": 0.85, "melee_range_mult": 1.1}},
	"bulwark_guard": {"name": "Guard", "desc": "-10% damage taken, +10 max HP", "mods": {"damage_taken_mult": 0.9, "max_hp_add": 10.0}},
	"sharpshooter_aim": {"name": "Steady Aim", "desc": "+15% bolt speed, +5% spell damage", "mods": {"projectile_speed_mult": 1.15, "spell_damage_mult": 1.05}},
	"pathfinder_stride": {"name": "Long Stride", "desc": "+8 stamina regen, +4% move speed", "mods": {"stamina_regen_add": 8.0, "move_speed_mult": 1.04}},
	"oracle_insight": {"name": "Insight", "desc": "+2 mana regen, +20 max mana", "mods": {"mana_regen_add": 2.0, "max_mana_add": 20.0}},
	"spiritblade_focus": {"name": "Spirit Edge", "desc": "+15% melee damage, +15% reach, -10% slash stamina cost", "mods": {"melee_damage_mult": 1.15, "melee_range_mult": 1.15, "melee_stamina_cost_mult": 0.9}},
	# element mastery (rare)
	"ember_kindle": {"name": "Kindle", "desc": "Burns last 30% longer", "mods": {"burn_time_mult": 1.3}},
	"flow": {"name": "Flow", "desc": "+8 stamina regen", "mods": {"stamina_regen_add": 8.0}},
	"thick_skin": {"name": "Thick Skin", "desc": "+10 max HP", "mods": {"max_hp_add": 10.0}},
	"swift": {"name": "Swift", "desc": "+8% move speed", "mods": {"move_speed_mult": 1.08}},
	"hardened": {"name": "Hardened", "desc": "-6% damage taken", "mods": {"damage_taken_mult": 0.94}},
	"radiance": {"name": "Radiance", "desc": "+0.4 HP regen", "mods": {"hp_regen_add": 0.4}},
	"shadow": {"name": "Shadow", "desc": "+6% spell damage", "mods": {"spell_damage_mult": 1.06}},
	# weapon mastery (rare, counted with skill passives)
	"blade_training": {"name": "Blade Training", "desc": "-10% slash stamina cost", "mods": {"melee_stamina_cost_mult": 0.9}},
	"staff_training": {"name": "Staff Training", "desc": "+1 mana regen", "mods": {"mana_regen_add": 1.0}},
	"bow_training": {"name": "Bow Training", "desc": "+5% bolt speed", "mods": {"projectile_speed_mult": 1.05}},
	"rod_training": {"name": "Rod Training", "desc": "+10 max mana", "mods": {"max_mana_add": 10.0}},
	# traits (tied to the character: rolled at creation, or chosen as level rewards)
	"sturdy": {"name": "Sturdy", "desc": "+12 max HP", "mods": {"max_hp_add": 12.0}},
	"tireless": {"name": "Tireless", "desc": "+6 stamina regen", "mods": {"stamina_regen_add": 6.0}},
	"sharp_mind": {"name": "Sharp Mind", "desc": "+15 max mana", "mods": {"max_mana_add": 15.0}},
	"fleet": {"name": "Fleet", "desc": "+5% move speed", "mods": {"move_speed_mult": 1.05}},
	"thick_hide": {"name": "Thick Hide", "desc": "-4% damage taken", "mods": {"damage_taken_mult": 0.96}},
	"iron_will": {"name": "Iron Will", "desc": "+0.25 HP regen", "mods": {"hp_regen_add": 0.25}},
	"keen_edge": {"name": "Keen Edge", "desc": "+6% melee damage", "mods": {"melee_damage_mult": 1.06}},
	"focused": {"name": "Focused", "desc": "+5% spell damage", "mods": {"spell_damage_mult": 1.05}},
	"hardy_lungs": {"name": "Hardy Lungs", "desc": "+12 max stamina", "mods": {"max_stamina_add": 12.0}},
	"quick_hands": {"name": "Quick Hands", "desc": "-5% spell cooldowns", "mods": {"spell_cooldown_mult": 0.95}},
	"far_reach": {"name": "Far Reach", "desc": "+10% melee reach", "mods": {"melee_range_mult": 1.1}},
	"calm_mind": {"name": "Calm Mind", "desc": "+1.5 mana regen", "mods": {"mana_regen_add": 1.5}},
	"stout": {"name": "Stout", "desc": "+8 max HP, +0.15 HP regen", "mods": {"max_hp_add": 8.0, "hp_regen_add": 0.15}},
	"arcane_surge": {"name": "Arcane Surge", "desc": "+4% spell damage, -3% spell cooldowns", "mods": {"spell_damage_mult": 1.04, "spell_cooldown_mult": 0.97}},
	# multi-element (automatic: more elements, more bonus; see CharacterData.passive_sources)
	"elemental_harmony": {
		"name": "Elemental Harmony",
		"desc": "Per extra element: +4% spell damage, +10 max mana, +6% fused damage",
		"mods": {"spell_damage_mult": 1.04, "max_mana_add": 10.0, "fusion_damage_mult": 1.06},
	},
	"jack_of_all_trades": {
		"name": "Jack of All Trades", "desc": "Small bonuses to everything",
		"mods": {
			"max_hp_add": 5.0, "max_mana_add": 5.0, "max_stamina_add": 5.0, "move_speed_mult": 1.03,
			"damage_taken_mult": 0.97, "spell_damage_mult": 1.03, "melee_damage_mult": 1.03,
		},
	},
}

const TRAITS := [
	"sturdy", "tireless", "sharp_mind", "fleet", "thick_hide", "iron_will", "keen_edge",
	"focused", "hardy_lungs", "quick_hands", "far_reach", "calm_mind", "stout", "arcane_surge",
	"jack_of_all_trades",
]

## Traits that only help spellcasting. Sealed characters (no elements, no mana, ever) never get them.
const SPELL_TRAITS := ["sharp_mind", "calm_mind", "focused", "quick_hands", "arcane_surge"]

const ELEMENT_PASSIVES := {
	"fire": "ember_kindle", "water": "flow", "earth": "thick_skin", "air": "swift",
	"mineral": "hardened", "light": "radiance", "dark": "shadow",
}

const WEAPON_PASSIVES := {
	"sword": "blade_training", "staff": "staff_training", "bow": "bow_training", "rod": "rod_training",
}

const SKILL_MASTERY_PREFIX := "mastery_"

## Active automatically once a character owns two or more elements, and stacks: its mods apply
## once for every element beyond the first.
const HARMONY_PASSIVE := "elemental_harmony"


## The traits a character can roll or be offered; `allow_spell` is false for sealed characters.
static func available_traits(allow_spell: bool = true) -> Array:
	return TRAITS.filter(func(t): return allow_spell or not (t in SPELL_TRAITS))


## How a class fights: "melee" (RMB always slashes; elements come from imbuing the blade and
## from abilities) or "ranged" (RMB slashes, or shoots the selected element while imbued).
## Everyone, including the Novice, fuses locked elements with LMB.
static func style_of(class_id: String) -> String:
	return String(CLASSES[class_id].get("style", "ranged"))


## True for the Novice (the class everyone starts as); false for the four real classes.
static func is_starter(class_id: String) -> bool:
	return CLASSES[class_id].get("starter", false)


## Class ids a Novice can choose between.
static func playable() -> Array:
	return CLASSES.keys().filter(func(id): return not is_starter(id))


## Passive definition by id. Skill-mastery passives ("mastery_<skill_id>") are generated:
## +15% damage and -10% cooldown for that one skill.
static func passive_info(id: String) -> Dictionary:
	if PASSIVES.has(id):
		return PASSIVES[id]
	if id.begins_with(SKILL_MASTERY_PREFIX):
		var skill_id := id.trim_prefix(SKILL_MASTERY_PREFIX)
		var skill_name: String = SkillDB.DEFS[skill_id]["name"] if SkillDB.DEFS.has(skill_id) else skill_id
		return {
			"name": "%s Mastery" % skill_name,
			"desc": "+15% damage, -10% cooldown",
			"mods": {skill_id + "_damage_mult": 1.15, skill_id + "_cooldown_mult": 0.9},
		}
	return {"name": id, "desc": "", "mods": {}}


## Uses needed to unlock a skill's mastery passive: area and special skills are cast far less
## often than primaries.
static func skill_passive_uses(skill_id: String) -> int:
	return 120 if SkillDB.slot_of(skill_id) == "primary" else 30
