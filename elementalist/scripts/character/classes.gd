class_name Classes
extends RefCounted
## Static tables for classes, subclasses, passives, traits and attribute scaling.
## Data only, no scene dependencies, so it is safe to read from anywhere (and from tests).
##
## PASSIVES come in four types (see CharacterData.passive_sources):
##   class    fixed, from the class and chosen subclass
##   trait    tied to the character; rolled at creation. Characters with fewer other passive
##            sources (e.g. non-elementalists) tend to roll more of them (Ceremony.roll_traits)
##   element  rare: unlocked at element mastery RARE_PASSIVE_LEVEL (also weapon mastery)
##   skill    rare: unlocked by using one skill many times (see skill_passive_uses)
##
## Passive "mods" use a naming convention the aggregator relies on:
##   *_add   summed          (e.g. max_hp_add, mana_regen_add)
##   *_mult  multiplied      (e.g. melee_damage_mult, damage_taken_mult)
## Per-skill mods are named "<skill_id>_damage_mult" / "<skill_id>_cooldown_mult".

const ATTRIBUTES := ["strength", "agility", "intellect", "vitality"]
const SUBCLASS_LEVEL := 5
const RARE_PASSIVE_LEVEL := 5  # element / weapon mastery level that unlocks its passive

## Hidden neutral class: all attributes 5, no growth, no passives. Used by tests and as the
## baseline the combat numbers were tuned against.
const NEUTRAL_CLASS := "wanderer"

## Skills every non-elementalist ("martial" set) learns, regardless of class.
const MARTIAL_LEVELS := {"primary": 1, "area": 2}

## The attribute that governs each element's potency (status duration and strength).
const ELEMENT_ATTRIBUTE := {
	"fire": "strength", "water": "agility", "earth": "vitality", "air": "agility",
	"mineral": "strength", "light": "vitality", "dark": "intellect",
}
const POTENCY_PER_POINT := 0.03  # per attribute point above/below 5

## How much one attribute point above/below 5 changes a skill property (see SkillDB "scales").
const SCALE_RATE := {"radius": 0.03, "knockback": 0.05, "speed": 0.03, "cooldown": -0.02}

# Balance: every playable class has the same 21 attribute points at level 1 and +1 per level
# in its favoured attribute, so classes differ in shape and skill timing, not raw power.
const CLASSES := {
	"channeler": {
		"name": "Channeler",
		"desc": "Ranged caster. Huge mana, fragile body, learns area spells at level 3.",
		"base": {"strength": 3, "agility": 5, "intellect": 9, "vitality": 4},
		"per_level": {"intellect": 1},
		"skill_levels": {"primary": 1, "area": 3},  # level at which each skill slot is learned
		"weapon": "staff",
		"passives": ["arcane_focus"],
		"subclasses": ["spellweaver", "warden"],
	},
	"vanguard": {
		"name": "Vanguard",
		"desc": "Frontline fighter. Tough and strong, slow to master spells (area at level 5).",
		"base": {"strength": 8, "agility": 4, "intellect": 3, "vitality": 6},
		"per_level": {"strength": 1},
		"skill_levels": {"primary": 1, "area": 5},
		"weapon": "sword",
		"passives": ["toughened"],
		"subclasses": ["duelist", "bulwark"],
	},
	"ranger": {
		"name": "Ranger",
		"desc": "Mobile skirmisher. Fast, fast projectiles, modest health (area at level 4).",
		"base": {"strength": 5, "agility": 8, "intellect": 4, "vitality": 4},
		"per_level": {"agility": 1},
		"skill_levels": {"primary": 1, "area": 4},
		"weapon": "bow",
		"passives": ["fleet_footed"],
		"subclasses": ["sharpshooter", "pathfinder"],
	},
	"mystic": {
		"name": "Mystic",
		"desc": "Attuned hybrid. Learns every spell early (area at level 2), sturdy, weak in melee.",
		"base": {"strength": 3, "agility": 4, "intellect": 7, "vitality": 7},
		"per_level": {"vitality": 1},
		"skill_levels": {"primary": 1, "area": 2},
		"weapon": "rod",
		"passives": ["attuned"],
		"subclasses": ["oracle", "spiritblade"],
	},
	"wanderer": {
		"name": "Wanderer",
		"desc": "Neutral baseline.",
		"base": {"strength": 5, "agility": 5, "intellect": 5, "vitality": 5},
		"per_level": {},
		"skill_levels": {"primary": 1, "area": 1},
		"weapon": "sword",
		"passives": [],
		"subclasses": [],
		"hidden": true,
	},
}

const SUBCLASSES := {
	"spellweaver": {"name": "Spellweaver", "desc": "Burst caster: +10% spell damage.", "passives": ["spellweaver_focus"]},
	"warden": {"name": "Warden", "desc": "Protective caster: -8% damage taken.", "passives": ["warden_ward"]},
	"duelist": {"name": "Duelist", "desc": "Agile fighter: slashes cost 15% less stamina.", "passives": ["duelist_footwork"]},
	"bulwark": {"name": "Bulwark", "desc": "Immovable fighter: -10% damage taken, +10 HP.", "passives": ["bulwark_guard"]},
	"sharpshooter": {"name": "Sharpshooter", "desc": "Faster bolts, +5% spell damage.", "passives": ["sharpshooter_aim"]},
	"pathfinder": {"name": "Pathfinder", "desc": "Tireless: +8 stamina regen, +4% speed.", "passives": ["pathfinder_stride"]},
	"oracle": {"name": "Oracle", "desc": "+2 mana regen, +20 max mana.", "passives": ["oracle_insight"]},
	"spiritblade": {"name": "Spiritblade", "desc": "+15% melee damage, slashes cost 10% less.", "passives": ["spiritblade_focus"]},
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
	"duelist_footwork": {"name": "Footwork", "desc": "-15% slash stamina cost", "mods": {"melee_stamina_cost_mult": 0.85}},
	"bulwark_guard": {"name": "Guard", "desc": "-10% damage taken, +10 max HP", "mods": {"damage_taken_mult": 0.9, "max_hp_add": 10.0}},
	"sharpshooter_aim": {"name": "Steady Aim", "desc": "+15% bolt speed, +5% spell damage", "mods": {"projectile_speed_mult": 1.15, "spell_damage_mult": 1.05}},
	"pathfinder_stride": {"name": "Long Stride", "desc": "+8 stamina regen, +4% move speed", "mods": {"stamina_regen_add": 8.0, "move_speed_mult": 1.04}},
	"oracle_insight": {"name": "Insight", "desc": "+2 mana regen, +20 max mana", "mods": {"mana_regen_add": 2.0, "max_mana_add": 20.0}},
	"spiritblade_focus": {"name": "Spirit Edge", "desc": "+15% melee damage, -10% slash stamina cost", "mods": {"melee_damage_mult": 1.15, "melee_stamina_cost_mult": 0.9}},
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
	# traits (tied to the character, rolled at creation)
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
}

const TRAITS := [
	"sturdy", "tireless", "sharp_mind", "fleet", "thick_hide",
	"iron_will", "keen_edge", "focused", "hardy_lungs", "quick_hands",
]

const ELEMENT_PASSIVES := {
	"fire": "ember_kindle", "water": "flow", "earth": "thick_skin", "air": "swift",
	"mineral": "hardened", "light": "radiance", "dark": "shadow",
}

const WEAPON_PASSIVES := {
	"sword": "blade_training", "staff": "staff_training", "bow": "bow_training", "rod": "rod_training",
}

const SKILL_MASTERY_PREFIX := "mastery_"


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


## Uses needed to unlock a skill's mastery passive: area skills are cast far less often.
static func skill_passive_uses(skill_id: String) -> int:
	return 30 if SkillDB.slot_of(skill_id) == "area" else 120
