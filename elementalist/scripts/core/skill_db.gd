extends Node
## Skill definitions (data only).
##
## Each "set" (an element, or "martial") has a "primary", "area" (F), "support" (V) and "special"
## (R) skill, see LOADOUTS. Primary unlocks at level 1, area at level 5 and support at level 7
## (Classes.SKILL_LEVELS); a special is only learned by choosing it as a level reward.
## Support skills are buffs (on yourself) or debuffs (an area that weakens enemies).
##   kind "projectile": speed, range
##   kind "buff": buff {kind, time, power}: a timed effect on the caster (see Player.add_buff):
##               might (+damage), mend (heal per second), ward (less damage taken), haste (speed)
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
		"damage": 18.0, "mana": 8.0, "cooldown": 0.87, "speed": 135.0, "range": 190.0,
		"splash": 22.0,
		"apply": {"kind": "dot", "time": 2.5, "power": 3.0},
	},
	"flame_burst": {
		"name": "Flame Burst", "element": "fire", "kind": "aoe",
		"damage": 26.0, "mana": 26.0, "cooldown": 4.0, "radius": 36.0, "range": 110.0,
		"apply": {"kind": "dot", "time": 2.5, "power": 3.0}, "knockback": 90.0,
		"scales": {"radius": "intellect"},
	},
	"water_jet": {
		"name": "Water Jet", "element": "water", "kind": "projectile",
		"damage": 8.0, "mana": 4.0, "cooldown": 0.32, "speed": 215.0, "range": 235.0,
		"apply": {"kind": "slow", "time": 2.0, "power": 0.5},
		"scales": {"speed": "agility"},
	},
	"rain_pool": {
		"name": "Rain Pool", "element": "water", "kind": "aoe",
		"damage": 3.0, "mana": 20.0, "cooldown": 5.5, "radius": 44.0, "range": 120.0,
		"duration": 4.0, "tick": 0.5, "knockback": 0.0,
		"apply": {"kind": "slow", "time": 1.0, "power": 0.5},
		"scales": {"radius": "intellect"},
	},
	"gust": {
		"name": "Gust", "element": "air", "kind": "projectile",
		"damage": 7.0, "mana": 4.0, "cooldown": 0.41, "speed": 330.0, "range": 270.0,
		"apply": {"kind": "slow", "time": 1.0, "power": 0.3}, "knockback": 120.0,
		"pierce": 2,
		"scales": {"speed": "agility"},
	},
	"cyclone": {
		"name": "Cyclone", "element": "air", "kind": "aoe",
		"damage": 8.0, "mana": 18.0, "cooldown": 4.0, "radius": 26.0, "range": 90.0,
		"apply": {}, "knockback": 230.0,
		"scales": {"knockback": "strength"},
	},
	"shard_shot": {
		"name": "Shard Shot", "element": "mineral", "kind": "projectile",
		"damage": 28.0, "mana": 12.0, "cooldown": 1.38, "speed": 105.0, "range": 150.0,
		"knockback": 70.0,
		"apply": {},
	},
	"stone_quake": {
		"name": "Stone Quake", "element": "mineral", "kind": "aoe",
		"damage": 18.0, "mana": 26.0, "cooldown": 5.0, "radius": 40.0, "range": 100.0,
		"apply": {"kind": "stun", "time": 0.6, "power": 1.0}, "knockback": 40.0,
		"scales": {"radius": "strength"},
	},
	"thorn_shot": {
		"name": "Thorn Shot", "element": "earth", "kind": "projectile",
		"damage": 6.0, "mana": 7.0, "cooldown": 0.8, "speed": 170.0, "range": 210.0,
		"spread_count": 3, "spread_deg": 16.0,
		"apply": {},
		"scales": {"cooldown": "agility"},
	},
	"root_snare": {
		"name": "Root Snare", "element": "earth", "kind": "aoe",
		"damage": 8.0, "mana": 20.0, "cooldown": 5.0, "radius": 32.0, "range": 120.0,
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
	# light and dark (rare elements). Light blinds and heals; dark drains and curses.
	"light_lance": {
		"name": "Light Lance", "element": "light", "kind": "projectile",
		"damage": 12.0, "mana": 5.0, "cooldown": 0.58, "speed": 390.0, "range": 280.0,
		"pierce": 1,
		"apply": {"kind": "weaken", "time": 2.0, "power": 0.2},
		"scales": {"speed": "agility"},
	},
	"sunburst": {
		"name": "Sunburst", "element": "light", "kind": "aoe",
		"damage": 18.0, "mana": 22.0, "cooldown": 4.0, "radius": 32.0, "range": 110.0,
		"apply": {"kind": "stun", "time": 0.4, "power": 1.0}, "knockback": 60.0,
		"scales": {"radius": "wisdom"},
	},
	"radiant_judgment": {
		"name": "Radiant Judgment", "element": "light", "kind": "aoe",
		"damage": 40.0, "mana": 34.0, "cooldown": 9.0, "radius": 48.0, "range": 0.0,
		"apply": {"kind": "vuln", "time": 4.0, "power": 1.0}, "knockback": 120.0,
		"scales": {"radius": "wisdom"},
	},
	"benediction": {
		"name": "Benediction", "element": "light", "kind": "buff",
		"damage": 0.0, "mana": 26.0, "cooldown": 18.0,
		"buff": {"kind": "mend", "time": 6.0, "power": 10.0},
	},
	"shadow_bolt": {
		"name": "Shadow Bolt", "element": "dark", "kind": "projectile",
		"damage": 13.0, "mana": 8.0, "cooldown": 0.74, "speed": 125.0, "range": 230.0,
		"homing": 2.4, "lifesteal": 0.25,
		"apply": {"kind": "dot", "time": 2.0, "power": 3.0},
		"scales": {"cooldown": "intellect"},
	},
	"void_well": {
		"name": "Void Well", "element": "dark", "kind": "aoe",
		"damage": 5.0, "mana": 24.0, "cooldown": 5.0, "radius": 30.0, "range": 120.0,
		"duration": 3.0, "tick": 0.5, "knockback": 0.0,
		"apply": {"kind": "weaken", "time": 1.0, "power": 0.3},
		"scales": {"radius": "intellect"},
	},
	"void_eclipse": {
		"name": "Void Eclipse", "element": "dark", "kind": "aoe",
		"damage": 30.0, "mana": 34.0, "cooldown": 9.0, "radius": 44.0, "range": 120.0,
		"apply": {"kind": "stun", "time": 0.8, "power": 1.0}, "knockback": 80.0,
		"scales": {"radius": "intellect"},
	},
	"dread_pact": {
		"name": "Dread Pact", "element": "dark", "kind": "aoe",
		"damage": 6.0, "mana": 24.0, "cooldown": 12.0, "radius": 40.0, "range": 110.0,
		"apply": {"kind": "weaken", "time": 6.0, "power": 0.4}, "knockback": 0.0,
		"scales": {"radius": "intellect"},
	},
	# support (V): buffs on yourself, debuffs on enemies. Level 7.
	"blazing_might": {
		"name": "Blazing Might", "element": "fire", "kind": "buff",
		"damage": 0.0, "mana": 22.0, "cooldown": 16.0,
		"buff": {"kind": "might", "time": 8.0, "power": 0.25},
	},
	"tidal_mending": {
		"name": "Tidal Mending", "element": "water", "kind": "buff",
		"damage": 0.0, "mana": 24.0, "cooldown": 18.0,
		"buff": {"kind": "mend", "time": 6.0, "power": 8.0},
	},
	"stone_skin": {
		"name": "Stone Skin", "element": "earth", "kind": "buff",
		"damage": 0.0, "mana": 20.0, "cooldown": 16.0,
		"buff": {"kind": "ward", "time": 8.0, "power": 0.3},
	},
	"tailwind": {
		"name": "Tailwind", "element": "air", "kind": "buff",
		"damage": 0.0, "mana": 18.0, "cooldown": 14.0,
		"buff": {"kind": "haste", "time": 7.0, "power": 0.3},
	},
	"fracture": {
		"name": "Fracture", "element": "mineral", "kind": "aoe",
		"damage": 6.0, "mana": 24.0, "cooldown": 12.0, "radius": 40.0, "range": 110.0,
		"apply": {"kind": "vuln", "time": 6.0, "power": 1.0}, "knockback": 0.0,
		"scales": {"radius": "intellect"},
	},
	"intimidate": {
		"name": "Intimidate", "element": "", "kind": "aoe",
		"damage": 4.0, "stamina": 24.0, "cooldown": 12.0, "radius": 44.0, "range": 0.0,
		"apply": {"kind": "weaken", "time": 6.0, "power": 0.4}, "knockback": 30.0,
		"scales": {"radius": "strength"},
	},
	# martial (no element): learned by non-elementalists, paid for with stamina
	"knife_throw": {
		"name": "Knife Throw", "element": "", "kind": "projectile",
		"damage": 12.0, "stamina": 9.0, "cooldown": 0.55, "speed": 230.0, "range": 170.0,
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
	"fire": {"primary": "fireball", "area": "flame_burst", "support": "blazing_might", "special": "inferno_ring"},
	"water": {"primary": "water_jet", "area": "rain_pool", "support": "tidal_mending", "special": "deluge"},
	"earth": {"primary": "thorn_shot", "area": "root_snare", "support": "stone_skin", "special": "bramble_burst"},
	"air": {"primary": "gust", "area": "cyclone", "support": "tailwind", "special": "tempest"},
	"mineral": {"primary": "shard_shot", "area": "stone_quake", "support": "fracture", "special": "crystal_lance"},
	"light": {"primary": "light_lance", "area": "sunburst", "support": "benediction", "special": "radiant_judgment"},
	"dark": {"primary": "shadow_bolt", "area": "void_well", "support": "dread_pact", "special": "void_eclipse"},
	"martial": {"primary": "knife_throw", "area": "whirlwind", "support": "intimidate", "special": "rending_throw"},
}

## Wind-ups: seconds between pressing an area (F) or special (R) skill and its effect. The cost and cooldown are paid at once, the hero
## moves slower while charging, and a dodge cancels it. Supports and the basic bolts are instant.
const WINDUPS := {
	"flame_burst": 0.35, "rain_pool": 0.3, "root_snare": 0.3, "cyclone": 0.35, "stone_quake": 0.5, "sunburst": 0.4, "void_well": 0.45,
	"whirlwind": 0.25, "inferno_ring": 0.6, "deluge": 0.7, "bramble_burst": 0.6, "tempest": 0.7, "crystal_lance": 0.6,
	"radiant_judgment": 0.8, "void_eclipse": 0.9, "rending_throw": 0.4,
}


static func windup_of(id: String) -> float:
	return float(WINDUPS.get(id, 0.0))


## Physical attack (RMB). Costs stamina, not mana, and never touches an enemy's aura.
## Deals bonus damage to rooted or stunned enemies so combos set up a payoff.
const MELEE := {
	"name": "Slash", "damage": 10.0, "stamina": 15.0, "cooldown": 0.26,
	"range": 28.6, "arc_deg": 110.0, "knockback": 90.0,
}


## The bolt traits a projectile skill carries (see Projectile): pierce, splash, homing, lifesteal.
func traits_of(def: Dictionary) -> Dictionary:
	var out := {}
	for key in ["pierce", "splash", "homing", "lifesteal"]:
		if def.has(key):
			out[key] = def[key]
	return out


## What a skill does beyond damage, in a few words ("fans 3 thorns", "pierces 2", "bursts on impact").
func trait_text(def: Dictionary) -> String:
	var parts: Array[String] = []
	if int(def.get("spread_count", 1)) > 1:
		parts.append("fans %d bolts" % int(def["spread_count"]))
	if int(def.get("pierce", 0)) > 0:
		parts.append("pierces %d" % int(def["pierce"]))
	if float(def.get("splash", 0.0)) > 0.0:
		parts.append("bursts on impact")
	if float(def.get("homing", 0.0)) > 0.0:
		parts.append("homes in")
	if float(def.get("lifesteal", 0.0)) > 0.0:
		parts.append("drains %d%%" % roundi(float(def["lifesteal"]) * 100.0))
	return ", ".join(parts)


## The way each element plays, shown on the altar and in the guide.
const ROLES := {
	"fire": "Heavy and slow. Bolts burst on impact and burn. Costly, hits hard.",
	"water": "Cheap and quick. A long stream that slows; wide soaking pools.",
	"air": "The fastest bolt: pierces a line of enemies and shoves them back.",
	"mineral": "Slowest and hardest hitting. Stuns; the quake is a wide stun.",
	"earth": "A fan of three thorns. Roots enemies in a wide ring.",
	"light": "A swift piercing lance that weakens. Blessings heal.",
	"dark": "A slow homing bolt that drains life. Curses wither.",
	"martial": "Stamina, not mana: knives and blows with no element.",
}


## "primary", "area", "support" or "special" for a skill id ("" if unknown).
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


## One line on what a skill does beyond damage, for menus: "+25% damage for 8s", "Weakens enemies".
func effect_text(def: Dictionary) -> String:
	if def["kind"] == "buff":
		var buff: Dictionary = def["buff"]
		var what: String = {
			"might": "+%d%% damage", "mend": "heals %d HP/s", "ward": "-%d%% damage taken", "haste": "+%d%% speed",
		}[buff["kind"]]
		var power := float(buff["power"])
		var amount: int = roundi(power * 100.0) if power < 1.0 else roundi(power)
		return (what % amount) + " for %ds" % roundi(float(buff["time"]))
	var apply: Dictionary = def.get("apply", {})
	var text := ""
	match String(apply.get("kind", "")):
		"weaken": text = "Weakens enemies (-%d%% damage)" % roundi(float(apply["power"]) * 100.0)
		"vuln": text = "Enemies take +25% damage"
	var traits := trait_text(def)
	if traits != "":
		text = (text + ", " if text != "" else "") + traits
	return text


func uses_stamina(def: Dictionary) -> bool:
	return def.has("stamina")


## Cost in the skill's own resource (mana for elemental skills, stamina for martial ones).
func cost_of(def: Dictionary) -> float:
	return float(def["stamina"]) if def.has("stamina") else float(def["mana"])
