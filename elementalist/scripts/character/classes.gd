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
##   (mastery) class mastery level SUBCLASS_MASTERY: choose a subclass (cards)
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

const ATTRIBUTES := ["strength", "agility", "intellect", "vitality", "wisdom", "luck", "dexterity"]
const ATTRIBUTE_SHORT := {
	"strength": "STR", "agility": "AGI", "intellect": "INT", "vitality": "VIT", "wisdom": "WIS", "luck": "LCK", "dexterity": "DEX",
}


## What an attribute does, for the character sheet's tooltip: a few short lines built from the same
## constants CharacterData.derived() / spell_damage_mult() / potency_mult() / skill_scale() use.
## The flat per-point numbers (+8 HP, +10 mana, +6 stamina, +2 move) mirror derived() literally.
static func attribute_text(attr: String) -> String:
	var lines: Array[String] = []
	match attr:
		"strength":
			lines.append("Melee and martial damage +6% per point above 5")
		"agility":
			lines.append("+6 max stamina and +2 move speed per point")
			lines.append("+%s stamina regen /s per point" % String.num(STAMINA_REGEN_PER_AGI))
		"intellect":
			lines.append("+10 max mana, +%s mana regen /s per point" % String.num(MANA_REGEN_PER_INT))
			lines.append("Spell damage +5% per point above 5")
		"vitality":
			lines.append("+8 max HP, +%s HP regen /s per point" % String.num(HP_REGEN_PER_VIT))
		"wisdom":
			lines.append("Per point above 5: +%s mana regen /s," % String.num(WISDOM_MANA_REGEN))
			lines.append("-%s%% spell cooldowns, +%s%% buff and debuff time" % [_pct(WISDOM_COOLDOWN), _pct(WISDOM_BUFF_DURATION)])
		"luck":
			lines.append("Per point above 5: +%s%% crit chance," % _pct(LUCK_CRIT))
			lines.append("+%s%% loot luck (better drops)" % _pct(LUCK_LOOT))
		"dexterity":
			lines.append("Attack speed +%s%% per point above 5" % _pct(DEXTERITY_ATTACK_SPEED))
			lines.append("(slashes, bolts, fused casts; not abilities)")
			lines.append("Each character level adds +%s%% more" % _pct(LEVEL_ATTACK_SPEED))
	var governed: Array[String] = []
	for element in ELEMENT_ATTRIBUTE:
		if ELEMENT_ATTRIBUTE[element] == attr:
			governed.append(String(element).capitalize())
	if not governed.is_empty():
		lines.append("%s potency +%s%% per point above 5" % [", ".join(governed), _pct(POTENCY_PER_POINT)])
		lines.append("  (status strength and duration)")
	var props: Array[String] = []
	for id in SkillDB.DEFS:
		var scales: Dictionary = SkillDB.DEFS[id].get("scales", {})
		for prop in scales:
			if scales[prop] == attr and not props.has(prop):
				props.append(String(prop))
	props.sort()
	if not props.is_empty():
		lines.append("Scales some skills' " + ", ".join(props))
	return "\n".join(lines)


static func _pct(fraction: float) -> String:
	return ("%.1f" % (fraction * 100.0)).trim_suffix(".0")  # 3, 1.5


## What the two newer attributes do (the other four are described in CharacterData), per point
## above 5:
##   wisdom  +0.3 mana regen, -1% spell cooldowns, +4% buff and debuff duration
##   luck    +1.5% crit chance, +5% loot luck
##   dexterity  +3% attack speed (slashes, bolts and fused casts; not abilities); every character
##              level also adds +1% attack speed
const DEXTERITY_ATTACK_SPEED := 0.03
const LEVEL_ATTACK_SPEED := 0.01
const WISDOM_MANA_REGEN := 0.3
const WISDOM_COOLDOWN := 0.01
const WISDOM_BUFF_DURATION := 0.04
const LUCK_CRIT := 0.015
const LUCK_LOOT := 0.05
const BASE_CRIT_MULT := 1.5

## Recovery during a fight is slow: resources are something to plan around. Per-second base values
## (attributes and passives add to them; see CharacterData.derived), what a kill gives back, and how
## long recovery pauses after use. Health also regains HP_REGEN_SHARE of max HP a second once out of
## combat, so a hero walks into the next room with most of it back (about 0.5% a second in all).
const HP_REGEN_BASE := 0.1
const HP_REGEN_PER_VIT := 0.03
const HP_REGEN_SHARE := 0.004
const STAMINA_REGEN_BASE := 12.0
const STAMINA_REGEN_PER_AGI := 1.2
const MANA_REGEN_BASE := 2.5
const MANA_REGEN_PER_INT := 0.4
const KILL_MANA := 1.5     # restored by every kill (plus passives); a kill is a chance to breathe
const KILL_STAMINA := 3.0
const CLASS_LEVEL := 3     # level at which a Novice chooses a class
const AREA_LEVEL := 5      # level at which area skills (Q) unlock, for everyone
const SUBCLASS_MASTERY := 5  # class mastery level that opens the subclass choice
const RARE_PASSIVE_LEVEL := 5  # element / weapon mastery level that unlocks its passive

## The class everyone starts as. All attributes 5, no growth, no passives: the baseline the
## combat numbers were tuned against, also used by tests.
const NEUTRAL_CLASS := "wanderer"

## Level at which each skill slot is learned. "special" (R) skills are learned from rewards.
const SUPPORT_LEVEL := 7  # level at which the support skill (V: a buff or debuff) is learned
const SKILL_LEVELS := {"primary": 1, "area": AREA_LEVEL, "support": SUPPORT_LEVEL}

## The attribute that governs each element's potency (status duration and strength).
const ELEMENT_ATTRIBUTE := {
	"fire": "strength", "water": "agility", "earth": "vitality", "air": "agility",
	"mineral": "strength", "light": "wisdom", "dark": "intellect",
}
const POTENCY_PER_POINT := 0.03  # per attribute point above/below 5

## How much one attribute point above/below 5 changes a skill property (see SkillDB "scales").
const SCALE_RATE := {"radius": 0.03, "knockback": 0.05, "speed": 0.03, "cooldown": -0.02}

# Balance: every playable class has the same 36 attribute points when chosen and +1 per level in
# its favoured attribute, so classes differ in shape, reach and passives, not raw power.
# "melee_range" multiplies the slash's reach: fighters reach far, casters barely at all.
const CLASSES := {
	"channeler": {
		"tag": "Caster. Huge mana, short reach.",
		"name": "Channeler",
		"desc": "Ranged caster: shoots while imbued, slashes (short reach) when not. Huge mana, fragile.",
		"style": "ranged",
		"base": {"strength": 3, "agility": 5, "intellect": 9, "vitality": 4, "wisdom": 6, "luck": 5, "dexterity": 4},
		"per_level": {"intellect": 1},
		"melee_range": 0.75,
		"weapon": "staff",
		"passives": ["arcane_focus"],
		"subclasses": ["spellweaver", "warden"],
	},
	"vanguard": {
		"tag": "Fighter. Longest reach, tough.",
		"name": "Vanguard",
		"desc": "Melee fighter: RMB always slashes. Elements come from imbuing the blade, fused casts and abilities. Longest reach. With no elements, LMB slashes too.",
		"style": "melee",
		"base": {"strength": 8, "agility": 4, "intellect": 3, "vitality": 6, "wisdom": 4, "luck": 6, "dexterity": 5},
		"per_level": {"strength": 1},
		"melee_range": 1.4,
		"weapon": "sword",
		"passives": ["toughened"],
		"subclasses": ["duelist", "bulwark"],
	},
	"ranger": {
		"tag": "Skirmisher. Fast, quick bolts.",
		"name": "Ranger",
		"desc": "Ranged skirmisher: shoots while imbued, short blade otherwise. Fast, quick bolts, modest health.",
		"style": "ranged",
		"base": {"strength": 5, "agility": 8, "intellect": 4, "vitality": 4, "wisdom": 4, "luck": 4, "dexterity": 7},
		"per_level": {"agility": 1},
		"melee_range": 0.9,
		"weapon": "bow",
		"passives": ["fleet_footed"],
		"subclasses": ["sharpshooter", "pathfinder"],
	},
	"mystic": {
		"tag": "Hybrid. Fast spells, sturdy.",
		"name": "Mystic",
		"desc": "Ranged hybrid: shoots while imbued, average reach otherwise. Faster spell cooldowns, sturdy.",
		"style": "ranged",
		"base": {"strength": 3, "agility": 4, "intellect": 7, "vitality": 7, "wisdom": 6, "luck": 4, "dexterity": 5},
		"per_level": {"vitality": 1},
		"melee_range": 1.0,
		"weapon": "rod",
		"passives": ["attuned"],
		"subclasses": ["oracle", "spiritblade"],
	},
	"assassin": {
		"tag": "Duelist. Crits, fast, fragile.",
		"name": "Assassin",
		"desc": "Melee skirmisher: dagger in hand, crits often and hits hard when it lands. Fast and fragile.",
		"style": "melee",
		"base": {"strength": 5, "agility": 8, "intellect": 3, "vitality": 3, "wisdom": 3, "luck": 7, "dexterity": 7},
		"per_level": {"agility": 1},
		"melee_range": 0.95,
		"weapon": "dagger",
		"passives": ["assassin_edge"],
		"subclasses": ["nightstalker", "trickster"],
	},
	"berserker": {
		"tag": "Bruiser. Hits hard, takes more.",
		"name": "Berserker",
		"desc": "Melee bruiser: axe, long swings and fury. Hits hard, shrugs off pain, takes a little extra.",
		"style": "melee",
		"base": {"strength": 8, "agility": 4, "intellect": 2, "vitality": 7, "wisdom": 4, "luck": 7, "dexterity": 4},
		"per_level": {"vitality": 1},
		"melee_range": 1.25,
		"weapon": "axe",
		"passives": ["bloodrage"],
		"subclasses": ["warlord", "reaver"],
	},
	"sage": {
		"tag": "Scholar. Mana, long buffs.",
		"name": "Sage",
		"desc": "Ranged scholar: a tome and a deep, fast-refilling mana pool. Buffs and debuffs last longer.",
		"style": "ranged",
		"base": {"strength": 2, "agility": 4, "intellect": 9, "vitality": 3, "wisdom": 8, "luck": 6, "dexterity": 4},
		"per_level": {"intellect": 1},
		"melee_range": 0.8,
		"weapon": "tome",
		"passives": ["scholars_calm"],
		"subclasses": ["archmage", "lorekeeper"],
	},
	"druid": {
		"tag": "Warden. Regeneration, wisdom.",
		"name": "Druid",
		"desc": "Ranged warden of growth: a staff, steady health regeneration and wisdom over raw power.",
		"style": "ranged",
		"base": {"strength": 3, "agility": 4, "intellect": 5, "vitality": 7, "wisdom": 8, "luck": 5, "dexterity": 4},
		"per_level": {"wisdom": 1},
		"melee_range": 0.9,
		"weapon": "staff",
		"passives": ["wild_growth"],
		"subclasses": ["grovekeeper", "stormcaller"],
	},
	"wanderer": {
		"name": "Novice",
		"desc": "No class yet. Choose one at level %d. Imbue (E) to shoot with RMB." % CLASS_LEVEL,
		"style": "ranged",
		"base": {"strength": 5, "agility": 5, "intellect": 5, "vitality": 5, "wisdom": 5, "luck": 5, "dexterity": 5},
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
	"pathfinder": {"name": "Pathfinder", "desc": "Tireless: +4 stamina regen, +4% speed.", "passives": ["pathfinder_stride"]},
	"oracle": {"name": "Oracle", "desc": "+1 mana regen, +20 max mana.", "passives": ["oracle_insight"]},
	"spiritblade": {"name": "Spiritblade", "desc": "+15% melee damage, +15% reach, slashes cost 10% less.", "passives": ["spiritblade_focus"]},
	"nightstalker": {"name": "Nightstalker", "desc": "Crits hit much harder, +4% move speed.", "passives": ["nightstalker_veil"]},
	"trickster": {"name": "Trickster", "desc": "+5% crit chance and +1 Luck.", "passives": ["trickster_luck"]},
	"warlord": {"name": "Warlord", "desc": "+10% melee damage, +12 max HP.", "passives": ["warlord_banner"]},
	"reaver": {"name": "Reaver", "desc": "Slashes cost 12% less stamina, +0.2 HP regen.", "passives": ["reaver_thirst"]},
	"archmage": {"name": "Archmage", "desc": "+10% spell damage, +10% fused damage.", "passives": ["archmage_power"]},
	"lorekeeper": {"name": "Lorekeeper", "desc": "-8% spell cooldowns, buffs and debuffs last 25% longer.", "passives": ["lorekeeper_notes"]},
	"grovekeeper": {"name": "Grovekeeper", "desc": "+0.25 HP regen, -7% damage taken.", "passives": ["grovekeeper_roots"]},
	"stormcaller": {"name": "Stormcaller", "desc": "+15% bolt speed, +6% spell damage.", "passives": ["stormcaller_gale"]},
}

const PASSIVES := {
	# class
	"arcane_focus": {"name": "Arcane Focus", "desc": "+1 mana regen, -4% mana costs", "mods": {"mana_regen_add": 1.0, "mana_cost_mult": 0.96}},
	"toughened": {"name": "Toughened", "desc": "+12 max HP, +10% melee damage", "mods": {"max_hp_add": 12.0, "melee_damage_mult": 1.1}},
	"fleet_footed": {"name": "Fleet-footed", "desc": "+8% move speed, +10% bolt speed", "mods": {"move_speed_mult": 1.08, "projectile_speed_mult": 1.1}},
	"attuned": {"name": "Attuned", "desc": "-7% spell cooldowns, +0.5 mana regen", "mods": {"spell_cooldown_mult": 0.93, "mana_regen_add": 0.5}},
	# subclass (class type)
	"spellweaver_focus": {"name": "Spellweaver Focus", "desc": "+10% spell damage", "mods": {"spell_damage_mult": 1.1}},
	"warden_ward": {"name": "Warding", "desc": "-8% damage taken", "mods": {"damage_taken_mult": 0.92}},
	"duelist_footwork": {"name": "Footwork", "desc": "-15% slash stamina cost, +10% reach", "mods": {"melee_stamina_cost_mult": 0.85, "melee_range_mult": 1.1}},
	"bulwark_guard": {"name": "Guard", "desc": "-10% damage taken, +10 max HP", "mods": {"damage_taken_mult": 0.9, "max_hp_add": 10.0}},
	"sharpshooter_aim": {"name": "Steady Aim", "desc": "+15% bolt speed, +5% spell damage", "mods": {"projectile_speed_mult": 1.15, "spell_damage_mult": 1.05}},
	"pathfinder_stride": {"name": "Long Stride", "desc": "+4 stamina regen, +4% move speed", "mods": {"stamina_regen_add": 4.0, "move_speed_mult": 1.04}},
	"oracle_insight": {"name": "Insight", "desc": "+1 mana regen, +20 max mana", "mods": {"mana_regen_add": 1.0, "max_mana_add": 20.0}},
	"spiritblade_focus": {"name": "Spirit Edge", "desc": "+15% melee damage, +15% reach, -10% slash stamina cost", "mods": {"melee_damage_mult": 1.15, "melee_range_mult": 1.15, "melee_stamina_cost_mult": 0.9}},
	"assassin_edge": {"name": "Assassin's Edge", "desc": "+4% crit chance, +4% move speed", "mods": {"crit_chance_add": 0.04, "move_speed_mult": 1.04}},
	"bloodrage": {"name": "Bloodrage", "desc": "+15% melee damage, +3 HP on kill, +6% damage taken", "mods": {"melee_damage_mult": 1.15, "kill_hp_add": 3.0, "damage_taken_mult": 1.06}},
	"scholars_calm": {"name": "Scholar's Calm", "desc": "+1.2 mana regen, -6% mana costs, buffs last 15% longer", "mods": {"mana_regen_add": 1.2, "mana_cost_mult": 0.94, "buff_duration_mult": 1.15}},
	"wild_growth": {"name": "Wild Growth", "desc": "+0.25 HP regen, +8 max HP", "mods": {"hp_regen_add": 0.25, "max_hp_add": 8.0}},
	"nightstalker_veil": {"name": "Veil", "desc": "+25% crit damage, +4% move speed", "mods": {"crit_damage_add": 0.25, "move_speed_mult": 1.04}},
	"trickster_luck": {"name": "Fortune", "desc": "+5% crit chance, +1 Luck", "mods": {"crit_chance_add": 0.05, "luck_add": 1.0}},
	"warlord_banner": {"name": "Banner", "desc": "+10% melee damage, +12 max HP", "mods": {"melee_damage_mult": 1.1, "max_hp_add": 12.0}},
	"reaver_thirst": {"name": "Thirst", "desc": "-12% slash stamina cost, +0.2 HP regen", "mods": {"melee_stamina_cost_mult": 0.88, "hp_regen_add": 0.2}},
	"archmage_power": {"name": "Archmage Power", "desc": "+10% spell damage, +10% fused damage", "mods": {"spell_damage_mult": 1.1, "fusion_damage_mult": 1.1}},
	"lorekeeper_notes": {"name": "Notes", "desc": "-8% spell cooldowns, buffs and debuffs last 25% longer", "mods": {"spell_cooldown_mult": 0.92, "buff_duration_mult": 1.25}},
	"grovekeeper_roots": {"name": "Roots", "desc": "+0.25 HP regen, -7% damage taken", "mods": {"hp_regen_add": 0.25, "damage_taken_mult": 0.93}},
	"stormcaller_gale": {"name": "Gale", "desc": "+15% bolt speed, +6% spell damage", "mods": {"projectile_speed_mult": 1.15, "spell_damage_mult": 1.06}},
	# element mastery (rare)
	"ember_kindle": {"name": "Kindle", "desc": "Burns last 30% longer", "mods": {"burn_time_mult": 1.3}},
	"flow": {"name": "Flow", "desc": "+4 stamina regen", "mods": {"stamina_regen_add": 4.0}},
	"thick_skin": {"name": "Thick Skin", "desc": "+10 max HP", "mods": {"max_hp_add": 10.0}},
	"swift": {"name": "Swift", "desc": "+8% move speed", "mods": {"move_speed_mult": 1.08}},
	"hardened": {"name": "Hardened", "desc": "-6% damage taken", "mods": {"damage_taken_mult": 0.94}},
	"radiance": {"name": "Radiance", "desc": "+0.2 HP regen", "mods": {"hp_regen_add": 0.2}},
	"shadow": {"name": "Shadow", "desc": "+6% spell damage", "mods": {"spell_damage_mult": 1.06}},
	# weapon mastery (rare, counted with skill passives)
	"blade_training": {"name": "Blade Training", "desc": "-10% slash stamina cost", "mods": {"melee_stamina_cost_mult": 0.9}},
	"staff_training": {"name": "Staff Training", "desc": "+0.5 mana regen", "mods": {"mana_regen_add": 0.5}},
	"bow_training": {"name": "Bow Training", "desc": "+5% bolt speed", "mods": {"projectile_speed_mult": 1.05}},
	"rod_training": {"name": "Rod Training", "desc": "+10 max mana", "mods": {"max_mana_add": 10.0}},
	"dagger_training": {"name": "Dagger Training", "desc": "+3% crit chance", "mods": {"crit_chance_add": 0.03}},
	"axe_training": {"name": "Axe Training", "desc": "+5% melee damage", "mods": {"melee_damage_mult": 1.05}},
	"tome_training": {"name": "Tome Training", "desc": "Buffs and debuffs last 10% longer", "mods": {"buff_duration_mult": 1.1}},
	# traits (tied to the character: rolled at creation, or chosen as level rewards)
	"sturdy": {"name": "Sturdy", "desc": "+12 max HP", "mods": {"max_hp_add": 12.0}},
	"tireless": {"name": "Tireless", "desc": "+3 stamina regen", "mods": {"stamina_regen_add": 3.0}},
	"sharp_mind": {"name": "Sharp Mind", "desc": "+15 max mana", "mods": {"max_mana_add": 15.0}},
	"fleet": {"name": "Fleet", "desc": "+5% move speed", "mods": {"move_speed_mult": 1.05}},
	"thick_hide": {"name": "Thick Hide", "desc": "-4% damage taken", "mods": {"damage_taken_mult": 0.96}},
	"iron_will": {"name": "Iron Will", "desc": "+0.12 HP regen", "mods": {"hp_regen_add": 0.12}},
	"keen_edge": {"name": "Keen Edge", "desc": "+6% melee damage", "mods": {"melee_damage_mult": 1.06}},
	"focused": {"name": "Focused", "desc": "+5% spell damage", "mods": {"spell_damage_mult": 1.05}},
	"hardy_lungs": {"name": "Hardy Lungs", "desc": "+12 max stamina", "mods": {"max_stamina_add": 12.0}},
	"quick_hands": {"name": "Quick Hands", "desc": "-5% spell cooldowns", "mods": {"spell_cooldown_mult": 0.95}},
	"far_reach": {"name": "Far Reach", "desc": "+10% melee reach", "mods": {"melee_range_mult": 1.1}},
	"calm_mind": {"name": "Calm Mind", "desc": "+0.8 mana regen", "mods": {"mana_regen_add": 0.8}},
	"stout": {"name": "Stout", "desc": "+8 max HP, +0.08 HP regen", "mods": {"max_hp_add": 8.0, "hp_regen_add": 0.08}},
	"arcane_surge": {"name": "Arcane Surge", "desc": "+4% spell damage, -3% spell cooldowns", "mods": {"spell_damage_mult": 1.04, "spell_cooldown_mult": 0.97}},
	"lucky": {"name": "Lucky", "desc": "+3% crit chance", "mods": {"crit_chance_add": 0.03}},
	"keen_eyes": {"name": "Keen Eyes", "desc": "+15% crit damage", "mods": {"crit_damage_add": 0.15}},
	"scholar": {"name": "Scholar", "desc": "+1 Wisdom", "mods": {"wisdom_add": 1.0}},
	"quick_strikes": {"name": "Quick Strikes", "desc": "+8% attack speed", "mods": {"attack_speed_mult": 1.08}},
	"efficient": {"name": "Efficient", "desc": "-8% mana costs", "mods": {"mana_cost_mult": 0.92}},
	"vampiric": {"name": "Vampiric", "desc": "+2 HP on kill", "mods": {"kill_hp_add": 2.0}},
	"mana_siphon": {"name": "Mana Siphon", "desc": "+3 mana on kill", "mods": {"kill_mana_add": 3.0}},
	"adrenaline": {"name": "Adrenaline", "desc": "+6 stamina on kill", "mods": {"kill_stamina_add": 6.0}},
	"nimble": {"name": "Nimble", "desc": "Dodges cost 20% less stamina", "mods": {"dodge_cost_mult": 0.8}},
	"survivor": {"name": "Survivor", "desc": "-5% damage taken, +1 HP on kill", "mods": {"damage_taken_mult": 0.95, "kill_hp_add": 1.0}},
	# multi-element (automatic: more elements, more bonus; see CharacterData.passive_sources)
	"elemental_harmony": {
		"name": "Elemental Harmony",
		"desc": "Per extra element: +3% spell damage, +5 max mana, +4% fused damage, but +4% mana costs",
		"mods": {"spell_damage_mult": 1.03, "max_mana_add": 5.0, "fusion_damage_mult": 1.04, "mana_cost_mult": 1.04},
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
	"jack_of_all_trades", "lucky", "keen_eyes", "scholar",
	"quick_strikes", "efficient", "vampiric", "mana_siphon", "adrenaline", "nimble", "survivor",
]

## Traits that only help spellcasting. Sealed characters (no elements, no mana, ever) never get them.
const SPELL_TRAITS := ["sharp_mind", "calm_mind", "focused", "quick_hands", "arcane_surge", "scholar", "efficient", "mana_siphon"]

const ELEMENT_PASSIVES := {
	"fire": "ember_kindle", "water": "flow", "earth": "thick_skin", "air": "swift",
	"mineral": "hardened", "light": "radiance", "dark": "shadow",
}

const WEAPON_PASSIVES := {
	"sword": "blade_training", "staff": "staff_training", "bow": "bow_training", "rod": "rod_training",
	"dagger": "dagger_training", "axe": "axe_training", "tome": "tome_training",
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
