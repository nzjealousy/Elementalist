class_name Monsters
extends RefCounted
## Monster definitions (data), elemental variants, wave rolling and spawning. Pure data and
## small rules; Enemy reads a definition through Enemy.configure().
##
## Behaviours:
##   chase    walks straight at the player
##   flutter  chases in a weaving line (hard to pin down)
##   ranged   keeps its distance and shoots (see "shot")
##   boss     chases; every `slam.cooldown` seconds it telegraphs a circle then slams it, and at
##            each health fraction in `summon.stages` it calls `summon.count` minions
##
## Elemental variants: any non-boss can spawn tinted with a main element. A variant has more
## health and bite, takes little damage from its own element (RESIST_MULT), extra damage from
## the element it is weak to (WEAK_TO, WEAK_MULT), and often drops its element's essence.

## Every monster is this one scene configured with a definition (loaded on use: Enemy refers
## back to this class, so a preload here would be a cycle).
const ENEMY_SCENE := "res://scenes/enemies/slime.tscn"

const RESIST_MULT := 0.4
const WEAK_MULT := 1.5
const VARIANT_HP := 1.25
const VARIANT_DAMAGE := 1.2
const VARIANT_XP := 1.5

## Each element is weak to the one that "beats" it (water douses fire, earth drinks water, fire
## burns earth, mineral grounds air, air erodes mineral).
const WEAK_TO := {"fire": "water", "water": "earth", "earth": "fire", "air": "mineral", "mineral": "air"}

const DEFS := {
	"slime": {
		"name": "Slime", "sprite": "enemy_slime", "hp": 40.0, "speed": 30.0, "contact": 8.0, "xp": 12, "behavior": "chase",
	},
	"bat": {
		"name": "Cave Bat", "sprite": "enemy_bat", "hp": 18.0, "speed": 58.0, "contact": 5.0, "xp": 10, "behavior": "flutter",
	},
	"skeleton": {
		"name": "Skeleton Archer", "sprite": "enemy_skeleton", "hp": 32.0, "speed": 28.0, "contact": 6.0, "xp": 16,
		"behavior": "ranged", "attack_range": 120.0, "keep_distance": 80.0,
		"shot": {"damage": 7.0, "speed": 95.0, "cooldown": 2.2},
	},
	"wisp": {
		"name": "Wisp", "sprite": "enemy_wisp", "hp": 24.0, "speed": 34.0, "contact": 4.0, "xp": 18,
		"behavior": "ranged", "attack_range": 105.0, "keep_distance": 70.0,
		"shot": {"damage": 6.0, "speed": 70.0, "cooldown": 1.5},
	},
	"brute": {
		"name": "Stone Brute", "sprite": "enemy_brute", "hp": 130.0, "speed": 17.0, "contact": 16.0, "xp": 34,
		"behavior": "chase", "knock_resist": 0.7,
	},
	"slime_king": {
		"name": "Slime King", "sprite": "boss_slime_king", "hp": 520.0, "speed": 22.0, "contact": 14.0, "xp": 200,
		"behavior": "boss", "boss": true, "knock_resist": 0.9,
		"slam": {"radius": 40.0, "damage": 22.0, "cooldown": 4.5, "telegraph": 0.8},
		"summon": {"id": "slime", "count": 3, "stages": [0.66, 0.33]},
	},
	"stone_colossus": {
		"name": "Stone Colossus", "sprite": "boss_colossus", "hp": 680.0, "speed": 18.0, "contact": 18.0, "xp": 260,
		"behavior": "boss", "boss": true, "knock_resist": 0.95,
		"slam": {"radius": 48.0, "damage": 28.0, "cooldown": 5.0, "telegraph": 0.9},
		"summon": {"id": "bat", "count": 4, "stages": [0.5]},
	},
}

## Relative frequency of each regular monster by dungeon floor (1-based).
const WEIGHTS := {
	1: {"slime": 5.0, "bat": 3.0, "skeleton": 1.0},
	2: {"slime": 3.0, "bat": 3.0, "skeleton": 3.0, "wisp": 2.0, "brute": 1.0},
	3: {"slime": 2.0, "bat": 2.0, "skeleton": 3.0, "wisp": 3.0, "brute": 3.0},
}
const VARIANT_CHANCE_PER_FLOOR := 0.15


static func is_boss(id: String) -> bool:
	return DEFS[id].get("boss", false)


static func bosses() -> Array:
	return DEFS.keys().filter(func(id): return is_boss(id))


## The monsters that appear in ordinary waves.
static func regular() -> Array:
	return DEFS.keys().filter(func(id): return not is_boss(id))


## A random wave: `count` entries of {"id", "variant"} for a dungeon floor. Deeper floors bring
## tougher monsters and more elemental variants.
static func roll_wave(rng: RandomNumberGenerator, floor_number: int, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var weights: Dictionary = WEIGHTS[clampi(floor_number, 1, 3)]
	for i in count:
		var variant := ""
		if rng.randf() < VARIANT_CHANCE_PER_FLOOR * floor_number:
			variant = Elements.MAIN[rng.randi_range(0, Elements.MAIN.size() - 1)]
		out.append({"id": Loot.pick_weighted(rng, weights), "variant": variant})
	return out


## Health and damage multipliers for a floor: monsters toughen as you go deeper.
static func floor_scale(floor_number: int) -> Vector2:
	return Vector2(1.0 + 0.35 * (floor_number - 1), 1.0 + 0.2 * (floor_number - 1))


## Creates a configured monster at `pos` under `parent`.
static func spawn(parent: Node, id: String, pos: Vector2, variant: String = "", scale: Vector2 = Vector2.ONE) -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE) as PackedScene).instantiate()
	enemy.configure(id, variant, scale.x, scale.y)
	enemy.position = pos
	parent.add_child(enemy)
	return enemy
