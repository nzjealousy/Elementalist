extends Node
## Skill definitions (data only).
##
## Each "set" (an element, or "martial") has a "primary" (LMB), "area" (Q) and "special" (R) skill,
## see LOADOUTS. Primary unlocks at level 1 and area at level 5 (Classes.SKILL_LEVELS); a special
## is only learned by choosing it as a level reward.
##   kind "projectile": speed, range
##   kind "aoe": radius, range (max cast distance, 0 = centred on the caster), optional
##               duration + tick (lingering)
##   mana / stamina: the resource spent. Elemental skills cost mana, martial skills stamina.
##   apply: status applied on every hit {kind, time, power}
##   scales: which character attribute scales a property of this skill. Properties:
##           radius, knockback, speed, cooldown (see Classes.SCALE_RATE).
##
## An empty "element" means a martial (physical) skill: no aura, usable without elements.

const DEFS := {
	"fireball": {
		"name": "Fireball", "element": "fire", "kind": "projectile",
		"damage": 16.0, "mana": 7.0, "cooldown": 0.4, "speed": 170.0, "range": 200.0,
		"apply": {"kind": "dot", "time": 2.5, "power": 3.0},
	},
	"flame_burst": {
		"name": "Flame Burst", "element": "fire", "kind": "aoe",
		"damage": 22.0, "mana": 22.0, "cooldown": 3.5, "radius": 30.0, "range": 120.0,
		"apply": {"kind": "dot", "time": 2.5, "power": 3.0}, "knockback": 90.0,
		"scales": {"radius": "intellect"},
	},
	"water_jet": {
		"name": "Water Jet", "element": "water", "kind": "projectile",
		"damage": 11.0, "mana": 6.0, "cooldown": 0.3, "speed": 200.0, "range": 180.0,
		"apply": {"kind": "slow", "time": 2.0, "power": 0.5},
		"scales": {"speed": "agility"},
	},
	"rain_pool": {
		"name": "Rain Pool", "element": "water", "kind": "aoe",
		"damage": 4.0, "mana": 24.0, "cooldown": 5.0, "radius": 34.0, "range": 120.0,
		"duration": 3.5, "tick": 0.5, "knockback": 0.0,
		"apply": {"kind": "slow", "time": 1.0, "power": 0.5},
		"scales": {"radius": "intellect"},
	},
	"gust": {
		"name": "Gust", "element": "air", "kind": "projectile",
		"damage": 9.0, "mana": 5.0, "cooldown": 0.28, "speed": 230.0, "range": 170.0,
		"apply": {"kind": "slow", "time": 1.0, "power": 0.3}, "knockback": 110.0,
		"scales": {"speed": "agility"},
	},
	"cyclone": {
		"name": "Cyclone", "element": "air", "kind": "aoe",
		"damage": 10.0, "mana": 22.0, "cooldown": 4.0, "radius": 32.0, "range": 110.0,
		"apply": {}, "knockback": 170.0,
		"scales": {"knockback": "strength"},
	},
	"shard_shot": {
		"name": "Shard Shot", "element": "mineral", "kind": "projectile",
		"damage": 17.0, "mana": 8.0, "cooldown": 0.5, "speed": 160.0, "range": 190.0,
		"apply": {},
	},
	"stone_quake": {
		"name": "Stone Quake", "element": "mineral", "kind": "aoe",
		"damage": 14.0, "mana": 22.0, "cooldown": 4.5, "radius": 32.0, "range": 100.0,
		"apply": {"kind": "stun", "time": 0.6, "power": 1.0}, "knockback": 40.0,
		"scales": {"radius": "strength"},
	},
	"thorn_shot": {
		"name": "Thorn Shot", "element": "earth", "kind": "projectile",
		"damage": 14.0, "mana": 7.0, "cooldown": 0.45, "speed": 150.0, "range": 220.0,
		"apply": {},
		"scales": {"cooldown": "agility"},
	},
	"root_snare": {
		"name": "Root Snare", "element": "earth", "kind": "aoe",
		"damage": 8.0, "mana": 20.0, "cooldown": 5.0, "radius": 30.0, "range": 120.0,
		"apply": {"kind": "root", "time": 1.5, "power": 1.0}, "knockback": 0.0,
		"scales": {"radius": "vitality"},
	},
	# specials (R): one per set, learned only as a level reward (see Rewards)
	"inferno_ring": {
		"name": "Inferno Ring", "element": "fire", "kind": "aoe",
		"damage": 20.0, "mana": 30.0, "cooldown": 8.0, "radius": 42.0, "range": 0.0,
		"apply": {"kind": "dot", "time": 3.0, "power": 4.0}, "knockback": 140.0,
		"scales": {"radius": "intellect"},
	},
	"deluge": {
		"name": "Deluge", "element": "water", "kind": "aoe",
		"damage": 5.0, "mana": 32.0, "cooldown": 10.0, "radius": 46.0, "range": 130.0,
		"duration": 4.0, "tick": 0.5, "knockback": 0.0,
		"apply": {"kind": "slow", "time": 1.2, "power": 0.6},
		"scales": {"radius": "intellect"},
	},
	"bramble_burst": {
		"name": "Bramble Burst", "element": "earth", "kind": "aoe",
		"damage": 12.0, "mana": 28.0, "cooldown": 8.0, "radius": 38.0, "range": 0.0,
		"apply": {"kind": "root", "time": 2.0, "power": 1.0}, "knockback": 0.0,
		"scales": {"radius": "vitality"},
	},
	"tempest": {
		"name": "Tempest", "element": "air", "kind": "projectile",
		"damage": 22.0, "mana": 22.0, "cooldown": 6.0, "speed": 260.0, "range": 220.0,
		"apply": {"kind": "slow", "time": 1.5, "power": 0.4}, "knockback": 220.0,
		"scales": {"speed": "agility"},
	},
	"crystal_lance": {
		"name": "Crystal Lance", "element": "mineral", "kind": "projectile",
		"damage": 34.0, "mana": 26.0, "cooldown": 7.0, "speed": 280.0, "range": 230.0,
		"apply": {"kind": "stun", "time": 0.6, "power": 1.0}, "knockback": 60.0,
		"scales": {"speed": "agility"},
	},
	"rending_throw": {
		"name": "Rending Throw", "element": "", "kind": "projectile",
		"damage": 30.0, "stamina": 30.0, "cooldown": 6.0, "speed": 260.0, "range": 200.0,
		"apply": {}, "knockback": 100.0,
		"scales": {"speed": "agility"},
	},
	# martial (no element): learned by non-elementalists, paid for with stamina
	"knife_throw": {
		"name": "Knife Throw", "element": "", "kind": "projectile",
		"damage": 12.0, "stamina": 10.0, "cooldown": 0.35, "speed": 230.0, "range": 170.0,
		"apply": {},
		"scales": {"speed": "agility"},
	},
	"whirlwind": {
		"name": "Whirlwind", "element": "", "kind": "aoe",
		"damage": 16.0, "stamina": 28.0, "cooldown": 3.5, "radius": 28.0, "range": 0.0,
		"apply": {}, "knockback": 130.0,
		"scales": {"radius": "strength"},
	},
}

const LOADOUTS := {
	"fire": {"primary": "fireball", "area": "flame_burst", "special": "inferno_ring"},
	"water": {"primary": "water_jet", "area": "rain_pool", "special": "deluge"},
	"earth": {"primary": "thorn_shot", "area": "root_snare", "special": "bramble_burst"},
	"air": {"primary": "gust", "area": "cyclone", "special": "tempest"},
	"mineral": {"primary": "shard_shot", "area": "stone_quake", "special": "crystal_lance"},
	"martial": {"primary": "knife_throw", "area": "whirlwind", "special": "rending_throw"},
}

## Physical attack (RMB). Costs stamina, not mana, and never touches an enemy's aura.
## Deals bonus damage to rooted or stunned enemies so combos set up a payoff.
const MELEE := {
	"name": "Slash", "damage": 10.0, "stamina": 18.0, "cooldown": 0.35,
	"range": 26.0, "arc_deg": 110.0, "knockback": 90.0,
}


## "primary" or "area" for a skill id ("" if unknown).
func slot_of(skill_id: String) -> String:
	for set_id in LOADOUTS:
		for slot in LOADOUTS[set_id]:
			if LOADOUTS[set_id][slot] == skill_id:
				return slot
	return ""


## The loadout set a skill belongs to: its element, or "martial".
func set_of(skill_id: String) -> String:
	var element: String = DEFS[skill_id].get("element", "")
	return element if element != "" else "martial"


func uses_stamina(def: Dictionary) -> bool:
	return def.has("stamina")


## Cost in the skill's own resource (mana for elemental skills, stamina for martial ones).
func cost_of(def: Dictionary) -> float:
	return float(def["stamina"]) if def.has("stamina") else float(def["mana"])
