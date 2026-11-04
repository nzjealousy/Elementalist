class_name Monsters
extends RefCounted
## Monster definitions (data), elemental variants, wave rolling and spawning. Pure data and
## small rules; Enemy reads a definition through Enemy.configure().
##
## Attack types ("attack"): "melee" (hurts on touch), "ranged" (never touches: keeps its distance
## and shoots) or "both" (closes in AND shoots while approaching).
## Abilities: "dash" {range, cooldown, windup, time, speed, damage_mult}: after a warning flash it
## lunges at you; "dodge" {chance, cooldown}: it may sidestep a hit and take nothing. Both get
## sharper with the dungeon floor (the monster's level): see Enemy.configure.
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

## Everything monsters deal (touch, arrows, slams) is multiplied by this: the dungeon is meant to
## be punishing, a place to plan resources rather than to trade blows.
const HARDNESS := 1.35
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
		"name": "Slime", "sprite": "enemy_slime", "hp": 40.0, "speed": 30.0, "contact": 8.0, "xp": 12,
		"behavior": "chase", "attack": "melee",
	},
	"bat": {
		"name": "Cave Bat", "sprite": "enemy_bat", "hp": 18.0, "speed": 58.0, "contact": 5.0, "xp": 10,
		"behavior": "flutter", "attack": "melee",
	},
	"skeleton": {
		"name": "Skeleton Archer", "sprite": "enemy_skeleton", "hp": 32.0, "speed": 28.0, "contact": 0.0, "xp": 16,
		"behavior": "ranged", "attack": "ranged", "attack_range": 120.0, "keep_distance": 80.0,
		"shot": {"damage": 7.0, "speed": 95.0, "cooldown": 2.2},
	},
	"wisp": {
		"name": "Wisp", "sprite": "enemy_wisp", "hp": 24.0, "speed": 34.0, "contact": 0.0, "xp": 18,
		"behavior": "ranged", "attack": "ranged", "attack_range": 105.0, "keep_distance": 70.0,
		"shot": {"damage": 6.0, "speed": 70.0, "cooldown": 1.5},
	},
	"brute": {
		"name": "Stone Brute", "sprite": "enemy_brute", "hp": 130.0, "speed": 17.0, "contact": 16.0, "xp": 34,
		"behavior": "chase", "attack": "melee", "knock_resist": 0.7,
	},
	"spitter": {
		"name": "Spitter", "sprite": "enemy_spitter", "hp": 36.0, "speed": 26.0, "contact": 7.0, "xp": 16,
		"behavior": "chase", "attack": "both", "attack_range": 95.0,
		"shot": {"damage": 6.0, "speed": 80.0, "cooldown": 2.6},
	},
	"imp": {
		"name": "Imp", "sprite": "enemy_imp", "hp": 28.0, "speed": 40.0, "contact": 9.0, "xp": 20,
		"behavior": "chase", "attack": "melee",
		"dash": {"range": 85.0, "cooldown": 3.2, "windup": 0.4, "time": 0.25, "speed": 190.0, "damage_mult": 1.6},
	},
	"wraith": {
		"name": "Wraith", "sprite": "enemy_wraith", "hp": 30.0, "speed": 30.0, "contact": 0.0, "xp": 24,
		"behavior": "ranged", "attack": "ranged", "attack_range": 125.0, "keep_distance": 85.0,
		"shot": {"damage": 7.0, "speed": 75.0, "cooldown": 2.0},
		"dodge": {"chance": 0.35, "cooldown": 2.0},
	},
	"duelist": {
		"name": "Bone Duelist", "sprite": "enemy_duelist", "hp": 70.0, "speed": 36.0, "contact": 12.0, "xp": 40,
		"behavior": "chase", "attack": "both", "attack_range": 100.0,
		"shot": {"damage": 5.0, "speed": 90.0, "cooldown": 3.0},
		"dash": {"range": 90.0, "cooldown": 3.6, "windup": 0.45, "time": 0.25, "speed": 200.0, "damage_mult": 1.5},
		"dodge": {"chance": 0.3, "cooldown": 2.4},
	},
	# Mini bosses ("mini": true) guard the end of every third floor. Smaller than a boss, they drop a
	# rare and sometimes an elemental essence, but no gem.
	"grave_warden": {
		"name": "Grave Warden", "sprite": "mini_warden", "hp": 300.0, "speed": 26.0, "contact": 12.0, "xp": 110,
		"behavior": "boss", "attack": "both", "boss": true, "mini": true, "knock_resist": 0.8,
		"attack_range": 110.0, "shot": {"damage": 8.0, "speed": 90.0, "cooldown": 2.4},
		"dash": {"range": 95.0, "cooldown": 4.0, "windup": 0.45, "time": 0.25, "speed": 200.0, "damage_mult": 1.5},
		"slam": {"radius": 30.0, "damage": 16.0, "cooldown": 5.0, "telegraph": 0.8},
		"summon": {"id": "skeleton", "count": 2, "stages": [0.5]},
	},
	"ember_matron": {
		"name": "Ember Matron", "sprite": "mini_matron", "hp": 260.0, "speed": 30.0, "contact": 10.0, "xp": 120,
		"behavior": "boss", "attack": "both", "boss": true, "mini": true, "knock_resist": 0.7,
		"attack_range": 120.0, "shot": {"damage": 9.0, "speed": 100.0, "cooldown": 1.5},
		"dodge": {"chance": 0.25, "cooldown": 3.0},
		"slam": {"radius": 36.0, "damage": 18.0, "cooldown": 5.5, "telegraph": 0.8},
		"summon": {"id": "imp", "count": 3, "stages": [0.6, 0.3]},
	},
	"bog_hulk": {
		"name": "Bog Hulk", "sprite": "mini_hulk", "hp": 380.0, "speed": 20.0, "contact": 16.0, "xp": 130,
		"behavior": "boss", "attack": "both", "boss": true, "mini": true, "knock_resist": 0.9,
		"attack_range": 90.0, "shot": {"damage": 7.0, "speed": 70.0, "cooldown": 2.0},
		"slam": {"radius": 44.0, "damage": 22.0, "cooldown": 4.5, "telegraph": 0.9},
		"summon": {"id": "spitter", "count": 3, "stages": [0.5]},
	},
	"slime_king": {
		"name": "Slime King", "sprite": "boss_slime_king", "hp": 520.0, "speed": 22.0, "contact": 14.0, "xp": 200, "tier": 1,
		"behavior": "boss", "attack": "melee", "boss": true, "knock_resist": 0.9,
		"slam": {"radius": 40.0, "damage": 22.0, "cooldown": 4.5, "telegraph": 0.8},
		"summon": {"id": "slime", "count": 3, "stages": [0.66, 0.33]},
	},
	"stone_colossus": {
		"name": "Stone Colossus", "sprite": "boss_colossus", "hp": 680.0, "speed": 18.0, "contact": 18.0, "xp": 260, "tier": 1,
		"behavior": "boss", "attack": "melee", "boss": true, "knock_resist": 0.95,
		"slam": {"radius": 48.0, "damage": 28.0, "cooldown": 5.0, "telegraph": 0.9},
		"summon": {"id": "bat", "count": 4, "stages": [0.5]},
	},
	"crypt_lich": {
		"name": "Crypt Lich", "sprite": "boss_lich", "hp": 900.0, "speed": 20.0, "contact": 16.0, "xp": 420, "tier": 2,
		"behavior": "boss", "attack": "both", "boss": true, "knock_resist": 0.9,
		"attack_range": 135.0, "shot": {"damage": 11.0, "speed": 90.0, "cooldown": 1.4},
		"slam": {"radius": 52.0, "damage": 34.0, "cooldown": 5.5, "telegraph": 0.9},
		"summon": {"id": "wraith", "count": 3, "stages": [0.75, 0.5, 0.25]},
	},
	"tide_titan": {
		"name": "Tide Titan", "sprite": "boss_titan", "hp": 1100.0, "speed": 17.0, "contact": 20.0, "xp": 460, "tier": 2,
		"behavior": "boss", "attack": "both", "boss": true, "knock_resist": 0.95,
		"attack_range": 100.0, "shot": {"damage": 10.0, "speed": 80.0, "cooldown": 1.8},
		"dash": {"range": 110.0, "cooldown": 6.0, "windup": 0.6, "time": 0.3, "speed": 210.0, "damage_mult": 1.6},
		"slam": {"radius": 60.0, "damage": 38.0, "cooldown": 5.0, "telegraph": 1.0},
		"summon": {"id": "spitter", "count": 4, "stages": [0.5]},
	},
}

## Relative frequency of each regular monster by dungeon floor (1-based).
const WEIGHTS := {
	1: {"slime": 4.0, "bat": 3.0, "skeleton": 1.0, "spitter": 1.0},
	2: {"slime": 2.0, "bat": 2.0, "skeleton": 2.0, "wisp": 2.0, "brute": 1.0, "spitter": 2.0, "imp": 2.0, "wraith": 1.0},
	3: {"slime": 1.0, "bat": 1.0, "skeleton": 2.0, "wisp": 2.0, "brute": 3.0, "spitter": 2.0, "imp": 3.0, "wraith": 3.0, "duelist": 2.0},
	4: {"bat": 1.0, "skeleton": 2.0, "wisp": 2.0, "brute": 3.0, "spitter": 2.0, "imp": 3.0, "wraith": 3.0, "duelist": 3.0},
	5: {"skeleton": 1.0, "wisp": 2.0, "brute": 3.0, "imp": 3.0, "wraith": 4.0, "duelist": 4.0},
}
const VARIANT_CHANCE_PER_FLOOR := 0.15  # per depth, capped at VARIANT_CHANCE_MAX
const VARIANT_CHANCE_MAX := 0.6


static func is_boss(id: String) -> bool:
	return DEFS[id].get("boss", false)


## The final bosses (not the mini bosses) of dungeon `tier`, or of every dungeon when tier is 0.
static func bosses(tier: int = 0) -> Array:
	return DEFS.keys().filter(func(id): return is_boss(id) and not is_mini(id) and (tier == 0 or int(DEFS[id].get("tier", 1)) == tier))


static func is_mini(id: String) -> bool:
	return DEFS[id].get("mini", false)


static func mini_bosses() -> Array:
	return DEFS.keys().filter(func(id): return is_mini(id))


## The monsters that appear in ordinary waves.
static func regular() -> Array:
	return DEFS.keys().filter(func(id): return not is_boss(id))


## A random wave: `count` entries of {"id", "variant"} for a dungeon floor. Deeper floors bring
## tougher monsters and more elemental variants.
static func roll_wave(rng: RandomNumberGenerator, floor_number: int, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var weights: Dictionary = WEIGHTS[clampi(floor_number, 1, WEIGHTS.size())]
	for i in count:
		var variant := ""
		if rng.randf() < minf(VARIANT_CHANCE_PER_FLOOR * floor_number, VARIANT_CHANCE_MAX):
			variant = Elements.MAIN[rng.randi_range(0, Elements.MAIN.size() - 1)]
		out.append({"id": Loot.pick_weighted(rng, weights), "variant": variant})
	return out


## Health and damage multipliers for a floor: monsters toughen as you go deeper.
static func floor_scale(floor_number: int) -> Vector2:
	return Vector2(1.0 + 0.35 * (floor_number - 1), 1.0 + 0.2 * (floor_number - 1))


## Creates a configured monster at `pos` under `parent`.
static func spawn(parent: Node, id: String, pos: Vector2, variant: String = "", scale: Vector2 = Vector2.ONE, monster_level: int = 1) -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE) as PackedScene).instantiate()
	enemy.configure(id, variant, scale.x, scale.y, monster_level)
	enemy.position = pos
	parent.add_child(enemy)
	return enemy
