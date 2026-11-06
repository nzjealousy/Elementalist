extends Node
## Balance report (read-only). Measures monsters, heroes, fights, the economy and death with the game's own
## tables and functions (Monsters, Enemy.configure, Dungeon._monster_scale, DungeonGen, Game, CharacterData,
## SkillCaster, Loot, Forge, Ceremony) and prints Markdown tables to stdout. It writes no save and no file.
## Run: godot --headless --path elementalist res://tests/balance_report.tscn
## Deterministic: every roll here comes from a seeded RandomNumberGenerator. docs/BALANCE.md reads its output.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const OATHS := ["squire", "knight", "warlord"]
const HERO_LEVELS := [1, 5, 10, 15, 20, 30, 40]
const SEEDS := 24               # dungeon layouts averaged per tier
const REF_ELEMENT := "fire"     # the element every measured hero owns
const REF_RANGED := "channeler" # the reference ranged hero (fireball) for times to kill
const REF_MELEE := "vanguard"   # the reference melee hero (slash)
## The forgiving targets the owner asked for: share of max HP one hit takes at the intended level.
const TARGETS := {"normal": Vector2(0.05, 0.08), "elite": Vector2(0.10, 0.15), "guardian": Vector2(0.15, 0.20), "boss": Vector2(0.15, 0.25)}
const CONTACT_COOLDOWN := Enemy.CONTACT_COOLDOWN  # seconds between touch hits that land
## Literals that live inside game functions (no constant to read); named here with where they come from.
const CLEAR_BONUS_PER_TIER := 150.0  # Dungeon._finish_run: a clear pays 150 x tier x reward gold
const DODGE_EASE := 0.675            # Player._physics_process: the roll eases from full to 35% speed (67.5% on average)
## "Typical drop" armour: [below item level 3, from item level 3]. Uncommon, +0, affixes left out (they are random).
const TYPICAL_ARMOUR := {
	"head": ["leather_cap", "iron_helm"], "body": ["padded_tunic", "chain_mail"], "feet": ["travel_boots", "runner_boots"],
	"ring": ["copper_ring", "silver_ring"], "amulet": ["bone_amulet", "lucky_charm"],
}
const ESCAPE_DEPTHS := [1, 5, 15, 27, 42, 62]  # first floor of the game and each tier's last floor

var _enemy_scene: PackedScene
var _monster_cache := {}
var _layouts := {}       # tier -> Array of layouts (DungeonGen.generate, as Dungeon._make_layout calls it)
var _levels := {}        # oath -> tier -> floor -> hero level on reaching that floor (first clears in order)
var _tier_end := {}      # oath -> tier -> level after that tier's first clear
var _tier_xp := {}       # oath -> tier -> mean XP of one clear
var _tier_kills := {}    # tier -> mean kills of one clear
var _loot_heroes := {}   # level -> CharacterData used for loot level and luck
var _player := {}        # the Player scene's own dodge and recovery numbers
var _economy := {}       # oath -> tier -> income of one clear


func _ready() -> void:
	var saved_character := Game.character
	var saved_meta: Dictionary = Game.meta.duplicate(true)
	var saved_danger := Game.danger
	_enemy_scene = load(Monsters.ENEMY_SCENE)
	var p := PLAYER_SCENE.instantiate() as Player
	_player = {"iframes": p.dodge_iframes, "dodge_time": p.dodge_time, "dodge_speed": p.dodge_speed, "dodge_cd": p.dodge_cooldown,
		"dodge_cost": p.dodge_stamina_cost, "hurt_iframes": p.hurt_invulnerability, "regen_delay": p.hp_regen_delay}
	p.free()
	for tier in Game.TIERS:
		_layouts[tier] = _make_layouts(int(tier))
	_progress()
	for oath in OATHS:
		_economy[oath] = {}
		for tier in Game.TIERS:
			_economy[oath][tier] = _run_income(int(tier), oath)

	print("\n# Elementalist balance report\n")
	print("Every number below comes from the game's own tables and functions at run time. Oath = difficulty.")
	print("Layouts averaged per tier: %d seeded DungeonGen runs. Reference element: %s.\n" % [SEEDS, REF_ELEMENT])
	_section_dials()
	_section_monsters()
	_section_heroes()
	_section_fights()
	_section_economy()
	_section_death()
	_section_outliers()

	Game.character = saved_character
	Game.meta = saved_meta
	Game.danger = saved_danger
	print("BALANCE REPORT DONE")
	get_tree().quit(0)


# ---------- measuring ----------

func _make_layouts(tier: int) -> Array:
	var spec: Dictionary = Game.TIERS[tier]
	var out := []
	for s in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 * tier + s
		out.append(DungeonGen.generate(rng, int(spec["floors"]), tier, int(spec["depth"])))
	return out


## The first, middle and last floor of every tier.
func _samples() -> Array:
	var out := []
	for tier in Game.TIERS:
		var spec: Dictionary = Game.TIERS[tier]
		var floors := int(spec["floors"])
		for f in [1, floori((floors + 1) / 2.0), floors]:
			var depth: int = int(spec["depth"]) + int(f)
			out.append({"tier": int(tier), "floor": f, "depth": depth, "last": f == floors, "label": "T%d F%d (d%d)" % [tier, f, depth]})
	return out


## Monster (health, damage) multipliers on a floor, through the dungeon's own function.
func _scale(depth: int, oath: String) -> Vector2:
	Game.meta["difficulty"] = oath
	var dungeon := Dungeon.new()
	dungeon.room = {"depth": depth}
	var s: Vector2 = dungeon._monster_scale()
	dungeon.free()
	return s


func _monster(id: String, depth: int, oath: String, variant: String = "") -> Dictionary:
	var s := _scale(depth, oath)
	return _enemy(id, variant, s.x, s.y, depth)


## A monster as Enemy.configure makes it: its numbers read back off a real (never added) Enemy.
func _enemy(id: String, variant: String, hp_scale: float, damage_scale: float, level: int) -> Dictionary:
	var key := "%s|%s|%.5f|%.5f|%d" % [id, variant, hp_scale, damage_scale, level]
	if _monster_cache.has(key):
		return _monster_cache[key]
	var e := _enemy_scene.instantiate() as Enemy
	e.configure(id, variant, hp_scale, damage_scale, level)
	var m := {
		"id": id, "name": e.display_name, "attack": e.attack_type, "hp": e.max_hp, "touch": e.contact_damage, "speed": e.speed,
		"xp": e.xp_reward, "boss": e.boss, "mini": e.mini, "keep": e.keep_distance, "range": e.attack_range,
		"shot": float(e.shot.get("damage", 0.0)), "shot_cd": float(e.shot.get("cooldown", 0.0)), "shot_speed": float(e.shot.get("speed", 0.0)),
		"dash_mult": float(e.dash.get("damage_mult", 0.0)), "dash_cd": float(e.dash.get("cooldown", 0.0)),
		"dash_windup": float(e.dash.get("windup", 0.0)), "dash_speed": float(e.dash.get("speed", 0.0)), "dash_time": float(e.dash.get("time", 0.0)),
		"slam": float(e.slam.get("damage", 0.0)), "slam_cd": float(e.slam.get("cooldown", 0.0)),
		"slam_tele": float(e.slam.get("telegraph", 0.0)), "slam_radius": float(e.slam.get("radius", 0.0)),
		"dodge": float(e.dodge_ability.get("chance", 0.0)), "dodge_cd": float(e.dodge_ability.get("cooldown", 0.0)),
		"summon": e.summon.duplicate(),
	}
	e.enraged = true
	m["enrage_cd"] = e._enrage_cooldown()
	e.free()
	m["dash_hit"] = float(m["touch"]) * float(m["dash_mult"])
	m["lunge"] = float(m["dash_speed"]) * float(m["dash_time"])
	var flight_from: float = float(m["keep"]) if float(m["keep"]) > 0.0 else float(m["range"])
	m["flight"] = flight_from / float(m["shot_speed"]) if float(m["shot_speed"]) > 0.0 else 0.0
	if bool(m["boss"]):
		m["main"] = m["slam"]
	elif String(m["attack"]) == "ranged":
		m["main"] = m["shot"]
	else:
		m["main"] = m["touch"]
	m["heavy"] = maxf(maxf(float(m["touch"]), float(m["shot"])), maxf(float(m["dash_hit"]), float(m["slam"])))
	var dps := 0.0  # pressure if it attacks whenever it can: touch while in contact, slams up close, shots otherwise
	if float(m["touch"]) > 0.0:
		dps += float(m["touch"]) / CONTACT_COOLDOWN
	if float(m["slam"]) > 0.0:
		dps += float(m["slam"]) / float(m["slam_cd"])
	elif float(m["shot"]) > 0.0:
		dps += float(m["shot"]) / float(m["shot_cd"])
	m["dps"] = dps
	_monster_cache[key] = m
	return m


## Who dies in a room: its waves, or the guardian and the minions it summons.
func _room_kills(room: Dictionary) -> Array:
	var out := []
	match String(room["kind"]):
		"combat":
			for wave in room["waves"]:
				for entry in wave:
					out.append({"id": String(entry["id"]), "variant": String(entry["variant"]), "summon": false})
		"miniboss", "boss":
			var boss_id := String(room["boss"])
			out.append({"id": boss_id, "variant": "", "summon": false, "boss": true})
			var summon: Dictionary = Monsters.DEFS[boss_id].get("summon", {})
			for i in int(summon.get("count", 0)) * Array(summon.get("stages", [])).size():
				out.append({"id": String(summon["id"]), "variant": "", "summon": true})
	return out


func _kill_xp(kill: Dictionary, depth: int) -> int:
	if bool(kill["summon"]):
		return int(_enemy(String(kill["id"]), "", 1.0, 1.0, 1)["xp"])  # Enemy._spawn_minions: Monsters.spawn defaults
	return int(_enemy(String(kill["id"]), String(kill["variant"]), 1.0, 1.0, depth)["xp"])


## XP of one floor at the current oath, kill by kill as Game.reward_kill grants it.
func _floor_xp(rooms: Array) -> float:
	var total := 0
	for room in rooms:
		for kill in _room_kills(room):
			total += maxi(1, roundi(float(_kill_xp(kill, int(room["depth"]))) * Game.reward_mult()))
	return float(total)


## First clears of every tier in order, per oath: the level the hero has on each floor.
func _progress() -> void:
	for tier in Game.TIERS:
		var kills := 0
		for layout in _layouts[tier]:
			for rooms in layout:
				for room in rooms:
					kills += _room_kills(room).size()
		_tier_kills[tier] = float(kills) / SEEDS
	for oath in OATHS:
		Game.meta["difficulty"] = oath
		var hero := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, [REF_ELEMENT], 1)
		_levels[oath] = {}
		_tier_end[oath] = {}
		_tier_xp[oath] = {}
		for tier in Game.TIERS:
			var layouts: Array = _layouts[tier]
			_levels[oath][tier] = {}
			var tier_total := 0.0
			for f in Array(layouts[0]).size():
				_levels[oath][tier][f + 1] = hero.level
				var floor_xp := 0.0
				for layout in layouts:
					floor_xp += _floor_xp(layout[f])
				floor_xp /= layouts.size()
				tier_total += floor_xp
				hero.gain_xp(roundi(floor_xp))
			_tier_end[oath][tier] = hero.level
			_tier_xp[oath][tier] = tier_total


func _level_at(oath: String, tier: int, f: int) -> int:
	return int(_levels[oath][tier][f])


## Levels gained on a floor (the next floor's level, or the level after the tier for its last floor).
func _levels_gained(oath: String, tier: int, f: int) -> int:
	var next: int = int(_levels[oath][tier][f + 1]) if _levels[oath][tier].has(f + 1) else int(_tier_end[oath][tier])
	return next - _level_at(oath, tier, f)


func _loot_hero(level: int) -> CharacterData:
	if not _loot_heroes.has(level):
		_loot_heroes[level] = CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, [REF_ELEMENT], level)
	return _loot_heroes[level]


## Game.loot_level / loot_bonus for a hero of `level` in room `room_index` of a floor at `depth` (danger as Dungeon sets it).
func _loot_point(level: int, depth: int, room_index: int, oath: String) -> Vector2:
	Game.meta["difficulty"] = oath
	Game.character = _loot_hero(level)
	Game.danger = (depth - 1) * 3 + room_index
	return Vector2(Game.loot_level(), Game.loot_bonus())


## A hero of `cls` at `level` with the reference element; element and weapon mastery one per level up to the cap.
## gear_ilvl > 0 puts on the typical drop gear of that item level; vit spends every free point on Vitality.
func _hero(cls: String, level: int, gear_ilvl: int, vit: bool = false) -> CharacterData:
	var c := CharacterData.create_sandbox(cls, [REF_ELEMENT], level)
	while vit and c.spend_point("vitality"):
		pass
	var mastery := mini(level, CharacterData.MASTERY_CAP)
	c.element_mastery[REF_ELEMENT]["level"] = mastery
	c.weapon_masteries[c.weapon_type]["level"] = mastery
	if gear_ilvl > 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var picks := {}
		for base_id in Items.gear_bases("weapon"):
			if Items.weapon_of({"base": base_id}) == c.weapon_type:
				picks["weapon"] = base_id
		for slot in TYPICAL_ARMOUR:
			var high: String = TYPICAL_ARMOUR[slot][1]
			picks[slot] = high if int(Items.BASES[high].get("min_ilvl", 1)) <= gear_ilvl else String(TYPICAL_ARMOUR[slot][0])
		for slot in picks:
			var item := Items.make(String(picks[slot]), "uncommon", gear_ilvl, rng)
			item["affixes"] = []
			c.inventory.equipped[slot] = item
	return c


## Derived stats, skill damage and DPS of a hero, through CharacterData and a SkillCaster.
func _stats(c: CharacterData) -> Dictionary:
	var previous := Game.character
	Game.character = c
	var d := c.derived()
	var caster := SkillCaster.new()
	var bolt := String(SkillDB.LOADOUTS[REF_ELEMENT]["primary"])
	var area := String(SkillDB.LOADOUTS[REF_ELEMENT]["area"])
	var crit := 1.0 + float(d["crit_chance"]) * (float(d["crit_mult"]) - 1.0)
	var bolt_dmg := c.skill_damage(bolt)
	var bolt_cd := caster.cooldown_total(bolt)
	var bolt_cost := caster.costs(bolt).x
	var burn := caster.status_for(SkillDB.DEFS[bolt])
	var burn_dps := float(burn.get("power", 0.0)) if String(burn.get("kind", "")) == "dot" else 0.0
	var bolt_rate := 1.0 / bolt_cd
	var bolt_rate_sus := minf(bolt_rate, float(d["mana_regen"]) / bolt_cost) if bolt_cost > 0.0 else bolt_rate
	var melee: Dictionary = SkillDB.MELEE
	var slash_dmg := float(melee["damage"]) * float(d["melee_damage_mult"])
	var slash_cd := float(melee["cooldown"]) / float(d["attack_speed"])
	var slash_cost := float(melee["stamina"]) * float(d["melee_stamina_cost_mult"])
	var slashes := floorf(float(d["max_stamina"]) / slash_cost)
	# shortcut: sustained slashing = empty the bar, wait out the regen delay, refill; ignores dodges sharing the bar.
	var cycle := slashes * slash_cd + Player.STAMINA_REGEN_DELAY + slashes * slash_cost / float(d["stamina_regen"])
	var dodge_cost := float(_player["dodge_cost"]) * float(d["dodge_cost_mult"])
	var s := {
		"hp": float(d["max_hp"]), "hp_regen": float(d["hp_regen"]), "mana": float(d["max_mana"]), "mana_regen": float(d["mana_regen"]),
		"stam": float(d["max_stamina"]), "stam_regen": float(d["stamina_regen"]), "move": float(d["move_speed"]),
		"dtm": float(d["damage_taken_mult"]), "kill_hp": float(d["kill_hp"]), "crit": crit, "dodge_cost": dodge_cost,
		"dodges": floori(float(d["max_stamina"]) / dodge_cost), "buff_mult": float(d["buff_duration_mult"]),
		"slash": slash_dmg, "slash_burst": slash_dmg * crit / slash_cd, "slash_sus": slash_dmg * crit * slashes / cycle,
		"bolt": bolt_dmg, "bolt_burst": bolt_dmg * crit * bolt_rate + burn_dps, "bolt_sus": bolt_dmg * crit * bolt_rate_sus + burn_dps,
		"bolt_rate": bolt_rate_sus,
		"area": c.skill_damage(area),
	}
	s["main_sus"] = s["slash_sus"] if Classes.style_of(c.class_id) == "melee" else s["bolt_sus"]
	caster.free()
	Game.character = previous
	return s


## The regular monsters of a depth's band, weighted as waves roll them.
func _band(depth: int, oath: String) -> Dictionary:
	var weights: Dictionary = Monsters.WEIGHTS[Monsters.band_of(depth)]
	var total := 0.0
	var b := {"main": 0.0, "hp": 0.0, "dps": 0.0, "xp": 0.0, "heavy": 0.0, "heavy_name": ""}
	var touch_id := ""
	var touch_best := -1.0
	for id in weights:
		var w := float(weights[id])
		var m := _monster(String(id), depth, oath)
		total += w
		for key in ["main", "hp", "dps", "xp"]:
			b[key] = float(b[key]) + w * float(m[key])
		if float(m["heavy"]) > float(b["heavy"]):
			b["heavy"] = m["heavy"]
			b["heavy_name"] = m["name"]
		if float(m["touch"]) > touch_best:
			touch_best = float(m["touch"])
			touch_id = String(id)
	for key in ["main", "hp", "dps", "xp"]:
		b[key] = float(b[key]) / total
	var elite := _monster(touch_id, depth, oath, REF_ELEMENT)
	b["elite"] = elite["touch"]
	b["elite_name"] = elite["name"]
	b["elite_hp"] = elite["hp"]
	b["mini_slam"] = 0.0
	b["mini_hp"] = 0.0
	for id in Monsters.mini_bosses():
		var m := _monster(String(id), depth, oath)
		if float(m["slam"]) > float(b["mini_slam"]):
			b["mini_slam"] = m["slam"]
			b["mini_name"] = m["name"]
		b["mini_hp"] = maxf(float(b["mini_hp"]), float(m["hp"]))
	return b


## The tier's final boss(es) at a depth: the hardest slam among them.
func _boss(tier: int, depth: int, oath: String) -> Dictionary:
	var best := {}
	for id in Monsters.bosses(tier):
		var m := _monster(String(id), depth, oath)
		if best.is_empty() or float(m["slam"]) > float(best["slam"]):
			best = m
	return best


func _floor_stats(tier: int, f: int) -> Dictionary:
	var layouts: Array = _layouts[tier]
	var combat_rooms := 0
	var monsters := 0
	var variants := 0
	var waves := 0
	var fights := 0
	var forges := 0
	var guardians := 0
	var low := 999
	var high := 0
	for layout in layouts:
		for room in layout[f - 1]:
			match String(room["kind"]):
				"combat":
					combat_rooms += 1
					fights += 1
					var n := 0
					for wave in room["waves"]:
						waves += 1
						for entry in wave:
							n += 1
							if String(entry["variant"]) != "":
								variants += 1
					monsters += n
					low = mini(low, n)
					high = maxi(high, n)
				"miniboss":
					fights += 1
					guardians += 1
				"boss":
					fights += 1
				"forge":
					forges += 1
	return {"per_room": float(monsters) / maxi(combat_rooms, 1), "min": low, "max": high, "waves": float(waves) / maxi(combat_rooms, 1),
		"cleared": float(combat_rooms + guardians) / layouts.size(),
		"variant_share": float(variants) / maxi(monsters, 1), "fights": float(fights) / layouts.size(),
		"forge": float(forges) / layouts.size(), "combat": float(combat_rooms) / layouts.size()}


## The seven playable classes at `level` wearing typical drops of `ilvl`.
func _class_line(level: int, ilvl: int, vit: bool = false) -> Dictionary:
	var out := {}
	for cls in Classes.playable():
		out[cls] = _stats(_hero(String(cls), level, ilvl, vit))
	return out


## Gold and materials of one clear of `tier`, the hero levelled as in _progress (averaged over the layouts).
func _run_income(tier: int, oath: String) -> Dictionary:
	var t := {"kills": 0.0, "chest": 0.0, "mini": 0.0, "boss": 0.0, "bonus": 0.0, "scrap": 0.0, "gel": 0.0, "essence": 0.0,
		"gems": 0.0, "items": 0.0, "salvage_gold": 0.0, "salvage_scrap": 0.0, "value": 0.0}
	var rarities := {}
	var layouts: Array = _layouts[tier]
	Game.meta["difficulty"] = oath  # drop gold follows the oath's reward (Pickup.gold_value)
	for s in layouts.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = 50000 + 100 * tier + s + 7919 * OATHS.find(oath)
		var layout: Array = layouts[s]
		for f in layout.size():
			var level := _level_at(oath, tier, f + 1)
			var rooms: Array = layout[f]
			for ri in rooms.size():
				var room: Dictionary = rooms[ri]
				var point := _loot_point(level, int(room["depth"]), ri, oath)
				var ilvl := int(point.x)
				var bonus := point.y
				match String(room["kind"]):
					"combat":
						for kill in _room_kills(room):
							_tally(t, rarities, Loot.enemy_drops(rng, ilvl, bonus, REF_ELEMENT, true, String(kill["variant"])), "kills")
					"treasure":
						_tally(t, rarities, Loot.chest_drops(rng, ilvl, bonus, true), "chest")
					"miniboss", "boss":
						var big := String(room["kind"]) == "boss"
						for kill in _room_kills(room):
							if kill.get("boss", false):
								var drops: Array = Loot.boss_drops(rng, ilvl, bonus, Game.character.missing_elements(), true) if big \
									else Loot.mini_boss_drops(rng, ilvl, bonus, true)
								_tally(t, rarities, drops, "boss" if big else "mini")
							else:
								_tally(t, rarities, Loot.enemy_drops(rng, ilvl, bonus, REF_ELEMENT, true, ""), "boss" if big else "mini")
		t["bonus"] =float(t["bonus"]) + roundi(CLEAR_BONUS_PER_TIER * tier * Game.reward_mult())
	for key in t:
		t[key] = float(t[key]) / layouts.size()
	for key in rarities:
		rarities[key] = float(rarities[key]) / layouts.size()
	t["rarities"] = rarities
	t["gold"] = float(t["kills"]) + float(t["chest"]) + float(t["mini"]) + float(t["boss"]) + float(t["bonus"])
	return t


func _tally(t: Dictionary, rarities: Dictionary, drops: Array, gold_key: String) -> void:
	for entry in drops:
		match String(entry["kind"]):
			"gold":
				t[gold_key] = float(t[gold_key]) + Pickup.gold_value(int(entry["amount"]))
			"material":
				var id := String(entry["id"])
				var key := "scrap" if id == "scrap" else ("gel" if id == "slime_gel" else ("gems" if id.begins_with("gem_") else "essence"))
				t[key] = float(t[key]) + int(entry["amount"])
			"item":
				var item: Dictionary = entry["item"]
				var gain := Items.salvage_yield(item)
				t["items"] = float(t["items"]) + 1
				t["salvage_gold"] = float(t["salvage_gold"]) + int(gain["gold"])
				t["salvage_scrap"] = float(t["salvage_scrap"]) + int(gain["scrap"])
				t["value"] = float(t["value"]) + Items.value_of(item)
				rarities[item["rarity"]] = float(rarities.get(item["rarity"], 0.0)) + 1


# ---------- the report ----------

func _section_dials() -> void:
	print("## 0. The dials\n")
	var consts: Dictionary = Game.get_script().get_script_constant_map()
	var rows := [
		["Monsters.HARDNESS (all monster damage)", _f(Monsters.HARDNESS, 2)],
		["Variant HP / damage (touch only) / XP", "x%s / x%s / x%s" % [_f(Monsters.VARIANT_HP, 2), _f(Monsters.VARIANT_DAMAGE, 2), _f(Monsters.VARIANT_XP, 2)]],
		["Variant chance per depth, cap", "%s per depth, cap %s" % [_p(Monsters.VARIANT_CHANCE_PER_FLOOR), _p(Monsters.VARIANT_CHANCE_MAX)]],
		["Dodge i-frames / roll time / cooldown", "%s s / %s s / %s s" % [_f(_player["iframes"], 2), _f(_player["dodge_time"], 2), _f(_player["dodge_cd"], 2)]],
		["Dodge stamina cost / roll distance (approx)", "%s / %s px" % [_f(_player["dodge_cost"], 0), _f(float(_player["dodge_speed"]) * float(_player["dodge_time"]) * DODGE_EASE, 1)]],
		["I-frames after a hit / HP regen pause after a hit", "%s s / %s s" % [_f(_player["hurt_iframes"], 2), _f(_player["regen_delay"], 1)]],
		["Stamina regen pause after spending", "%s s" % _f(Player.STAMINA_REGEN_DELAY, 2)],
		["Forge room heal / level-up heal / room-clear heal", "%s / %s / %s of max HP" % [_p(Dungeon.FORGE_HEAL), _p(CharacterData.LEVEL_UP_HEAL_FRACTION), _p(Dungeon.CLEAR_HEAL)]],
		["Out-of-combat regen / max HP per level", "%s of max HP a second (plus Vitality) / +%s" % [_p(Classes.HP_REGEN_SHARE, 1), _f(CharacterData.HP_PER_LEVEL, 0)]],
		["Touch cooldown / dash wind-up floor / dash speed cap", "%s s / %s s / %s px/s" % [_f(Enemy.CONTACT_COOLDOWN, 1), _f(Enemy.DASH_WINDUP_MIN, 2), _f(Enemy.DASH_SPEED_MAX, 0)]],
		["Dodge chance cap / monster walk speed cap", "%s / %s px/s" % [_p(Enemy.DODGE_CHANCE_MAX, 0), _f(Enemy.WALK_SPEED_MAX, 0)]],
		["Slam stun / stun immunity after", "%s s / %s s" % [_f(Enemy.SLAM_STUN, 2), _f(Player.STUN_IMMUNITY, 2)]],
		["Boss enrage at / its cooldown multiplier", "%s HP / x%s" % [_p(Enemy.ENRAGE_AT), _f(float(_enemy("slime_king", "", 1, 1, 1)["enrage_cd"]), 2)]],
		["Max level", str(CharacterData.MAX_LEVEL)],
		["Game.DEATH_GOLD_LOSS", _p(float(consts["DEATH_GOLD_LOSS"])) if consts.has("DEATH_GOLD_LOSS") else "(gone)"],
	]
	_table(["Dial", "Value"], rows)
	var oath_rows := []
	for oath in OATHS:
		var o: Dictionary = Game.DIFFICULTIES[oath]
		oath_rows.append([String(o["name"]), _f(float(o["hardness"]), 2), _f(float(o["reward"]), 2),
			"x%s" % _f(float(o["hardness"]) * Monsters.HARDNESS, 3)])
	_table(["Oath", "Hardness (HP and damage)", "Reward (XP, clear bonus, luck)", "Damage with HARDNESS"], oath_rows)
	var scale_rows := []
	for depth in [1, 2, 5, 10, 11, 15, 20, 27, 30, 42, 50, 62]:
		var fs := Monsters.floor_scale(depth)
		scale_rows.append([str(depth), "x" + _f(fs.x, 2), "x" + _f(fs.y, 2), "x" + _f(fs.y * Monsters.HARDNESS, 2)])
	_table(["Depth", "floor_scale HP", "floor_scale damage", "Damage x HARDNESS (Knight)"], scale_rows)


func _section_monsters() -> void:
	print("## 1. Monsters\n")
	print("### 1a. Scale per sampled floor, by oath (HP multiplier / damage multiplier incl. HARDNESS)\n")
	var rows := []
	for s in _samples():
		var cells := [String(s["label"])]
		for oath in OATHS:
			var sc := _scale(int(s["depth"]), oath)
			cells.append("x%s / x%s" % [_f(sc.x, 2), _f(sc.y * Monsters.HARDNESS, 2)])
		rows.append(cells)
	var oath_heads := ["Where"]
	for oath in OATHS:
		oath_heads.append("%s %s" % [String(Game.DIFFICULTIES[oath]["name"]), _f(float(Game.DIFFICULTIES[oath]["hardness"]), 2)])
	_table(oath_heads, rows)

	print("### 1b. Every monster that can spawn there, Knight\n")
	print("Touch = contact damage (no warning, lands at most every %s s). Shot: damage @ cooldown, flight time from its preferred distance." % _f(CONTACT_COOLDOWN, 1))
	print("Dash: hit (touch x lunge mult) @ cooldown, wind-up. Slam: damage @ cooldown, telegraph, radius. Dodge: chance to sidestep a hit.\n")
	rows = []
	for s in _samples():
		var depth := int(s["depth"])
		var weights: Dictionary = Monsters.WEIGHTS[Monsters.band_of(depth)]
		var total := 0.0
		for id in weights:
			total += float(weights[id])
		var ids: Array = weights.keys()
		for id in Monsters.mini_bosses():
			ids.append(id)
		if bool(s["last"]):
			ids.append_array(Monsters.bosses(int(s["tier"])))
		for id in ids:
			var m := _monster(String(id), depth, "knight")
			var share := "mini" if bool(m["mini"]) else ("BOSS" if bool(m["boss"]) else _p(float(weights[id]) / total, 0))
			rows.append([String(s["label"]), String(m["name"]), share, _f(float(m["hp"]), 0), _dmg(float(m["touch"])),
				_shot(m), _dash(m), _slam(m), _f(float(m["speed"]), 0), _p(float(m["dodge"]), 0) if float(m["dodge"]) > 0.0 else "-", str(m["xp"])])
	_table(["Where", "Monster", "Share", "HP", "Touch", "Shot", "Dash", "Slam", "Speed", "Dodge", "XP"], rows)

	print("### 1c. The same floors at each oath (Squire / Knight / Warlord)\n")
	print("Normal = band-weighted main hit (touch for melee, shot for ranged). Heaviest = the band's biggest single hit (dashes count).\n")
	rows = []
	for s in _samples():
		var cells := [String(s["label"])]
		var parts := {"normal": [], "heavy": [], "hp": [], "mini": [], "boss": [], "boss_hp": []}
		for oath in OATHS:
			var b := _band(int(s["depth"]), oath)
			parts["normal"].append(_f(float(b["main"]), 1))
			parts["heavy"].append(_f(float(b["heavy"]), 1))
			parts["hp"].append(_f(float(b["hp"]), 0))
			parts["mini"].append(_f(float(b["mini_slam"]), 1))
			if bool(s["last"]):
				var boss := _boss(int(s["tier"]), int(s["depth"]), oath)
				parts["boss"].append(_f(float(boss["slam"]), 1))
				parts["boss_hp"].append(_f(float(boss["hp"]), 0))
		for key in ["normal", "heavy", "hp", "mini", "boss", "boss_hp"]:
			cells.append(" / ".join(parts[key]) if not Array(parts[key]).is_empty() else "-")
		rows.append(cells)
	_table(["Where", "Normal hit", "Heaviest hit", "Avg normal HP", "Guardian slam (max)", "Boss slam", "Boss HP"], rows)

	print("### 1d. Monsters per combat room (DungeonGen, %d layouts per tier)\n" % SEEDS)
	rows = []
	for s in _samples():
		var fs := _floor_stats(int(s["tier"]), int(s["floor"]))
		var b := _band(int(s["depth"]), "knight")
		rows.append([String(s["label"]), _f(float(fs["per_room"]), 1), "%d-%d" % [int(fs["min"]), int(fs["max"])], _f(float(fs["waves"]), 1),
			_p(float(fs["variant_share"]), 0), _f(float(fs["combat"]), 1), _f(float(b["xp"]), 1),
			_f(float(fs["per_room"]) * float(b["hp"]) * (1.0 + float(fs["variant_share"]) * (Monsters.VARIANT_HP - 1.0)), 0)])
	_table(["Where", "Monsters/room", "Range", "Waves", "Variants", "Combat rooms/floor", "Avg XP/kill", "Room HP total (Knight)"], rows)


func _section_heroes() -> void:
	print("## 2. Heroes\n")
	print("Sandbox heroes (no traits, free points unspent, no subclass) owning %s; element and weapon mastery = level, capped at %d." % [REF_ELEMENT, CharacterData.MASTERY_CAP])
	print("DPS includes expected crits and the bolt's burn. Sustained: bolt limited by mana regen, slash by emptying and refilling stamina.")
	print("Level %d is above MAX_LEVEL %d: those rows are what the growth would give, a hero cannot get there.\n" % [int(HERO_LEVELS[-1]), CharacterData.MAX_LEVEL])
	for gear in ["starter", "typical"]:
		if gear == "starter":
			print("### 2a. Starter gear (the worn class weapon only)\n")
		else:
			print("### 2b. Typical drop gear: six uncommon +0 pieces of item level = hero level, affixes left out\n")
		var rows := []
		var cls_order: Array = [Classes.NEUTRAL_CLASS] + Classes.playable()
		for cls in cls_order:
			for level in HERO_LEVELS:
				var ilvl: int = 0 if gear == "starter" else int(level)
				var st := _stats(_hero(String(cls), int(level), ilvl))
				var vit_hp := float(_stats(_hero(String(cls), int(level), ilvl, true))["hp"])
				rows.append([String(Classes.CLASSES[cls]["name"]), str(level) + ("*" if int(level) > CharacterData.MAX_LEVEL else ""),
					"%s (%s)" % [_f(float(st["hp"]), 0), _f(vit_hp, 0)], _f(float(st["hp_regen"]), 2), _f(float(st["mana"]), 0), _f(float(st["mana_regen"]), 1),
					_f(float(st["stam"]), 0), _f(float(st["stam_regen"]), 1), str(st["dodges"]), _f(float(st["move"]), 0),
					_f(float(st["slash"]), 1), "%s / %s" % [_f(float(st["slash_burst"]), 1), _f(float(st["slash_sus"]), 1)],
					_f(float(st["bolt"]), 1), "%s / %s" % [_f(float(st["bolt_burst"]), 1), _f(float(st["bolt_sus"]), 1)],
					_f(float(st["area"]), 1), _f(float(st["dtm"]), 3)])
		_table(["Class", "Lvl", "HP (all points in VIT)", "HP/s", "Mana", "Mana/s", "Stam", "Stam/s", "Dodges", "Move", "Slash", "Slash DPS burst/sust",
			"Fireball", "Fireball DPS burst/sust", "Flame Burst", "Dmg taken x"], rows)

	print("### 2c. XP curve (CharacterData.xp_to_next)\n")
	var rows := []
	var total := 0
	for level in range(1, CharacterData.MAX_LEVEL):
		var need := CharacterData.xp_to_next(level)
		total += need
		if level in [1, 2, 3, 4, 5, 7, 10, 12, 15, 18, 20, 22, 25, 27, 29]:
			rows.append([str(level), str(need), str(total)])
	_table(["Level", "XP to next", "XP from level 1 to the next"], rows)

	print("### 2d. Level reached by first clears in order (each tier cleared once, all kills, summons included)\n")
	rows = []
	for tier in Game.TIERS:
		var cells := ["T%d %s" % [tier, String(Game.TIERS[tier]["name"])], _f(float(_tier_kills[tier]), 0)]
		var xp_cells := []
		var lv_cells := []
		for oath in OATHS:
			xp_cells.append(_f(float(_tier_xp[oath][tier]), 0))
			lv_cells.append("%d -> %d" % [_level_at(oath, int(tier), 1), int(_tier_end[oath][tier])])
		cells.append(" / ".join(xp_cells))
		cells.append(" / ".join(lv_cells))
		rows.append(cells)
	_table(["Tier", "Kills", "XP of a clear (Sq / Kn / Wl)", "Level in -> out (Sq / Kn / Wl)"], rows)


func _section_fights() -> void:
	print("## 3. Fight maths (Knight, first-clear level, the seven classes in typical gear of the floor's loot level)\n")
	print("### 3a. Share of max HP one hit takes (lowest-highest across classes; hits to die for the frailest)\n")
	print("Targets (forgiving): normal %s-%s, elite %s-%s, guardian %s-%s, boss %s-%s. 'Factor' = multiply today's damage by this to land mid-target.\n" % [
		_p(TARGETS["normal"].x, 0), _p(TARGETS["normal"].y, 0), _p(TARGETS["elite"].x, 0), _p(TARGETS["elite"].y, 0),
		_p(TARGETS["guardian"].x, 0), _p(TARGETS["guardian"].y, 0), _p(TARGETS["boss"].x, 0), _p(TARGETS["boss"].y, 0)])
	var hit_rows := []
	var time_rows := []
	var heal_rows := []
	for s in _samples():
		var tier := int(s["tier"])
		var f := int(s["floor"])
		var depth := int(s["depth"])
		var level := _level_at("knight", tier, f)
		var ilvl := int(_loot_point(level, depth, 0, "knight").x)
		var heroes := _class_line(level, ilvl)
		var b := _band(depth, "knight")
		var fs := _floor_stats(tier, f)
		var hp_low := INF
		var hp_high := 0.0
		for cls in heroes:
			hp_low = minf(hp_low, float(heroes[cls]["hp"]))
			hp_high = maxf(hp_high, float(heroes[cls]["hp"]))
		var boss := _boss(tier, depth, "knight") if bool(s["last"]) else {}
		var normal := _share_cell(heroes, float(b["main"]))
		var elite := _share_cell(heroes, float(b["elite"]))
		var boss_cell := _share_cell(heroes, float(boss["slam"])) if not boss.is_empty() else "-"
		var big_hit := float(boss["slam"]) if not boss.is_empty() else float(b["mini_slam"])
		var factors := "%s / %s / %s" % [_factor(heroes, float(b["main"]), "normal"), _factor(heroes, float(b["elite"]), "elite"),
			_factor(heroes, big_hit, "boss" if not boss.is_empty() else "guardian")]
		var vit_heroes := _class_line(level, ilvl, true)
		var vit_low := INF
		var vit_high := 0.0
		for cls in vit_heroes:
			vit_low = minf(vit_low, float(vit_heroes[cls]["hp"]))
			vit_high = maxf(vit_high, float(vit_heroes[cls]["hp"]))
		hit_rows.append([String(s["label"]), str(level), str(ilvl), "%s-%s" % [_f(hp_low, 0), _f(hp_high, 0)], normal,
			_share_cell(heroes, float(b["heavy"])), elite, _share_cell(heroes, float(b["mini_slam"])), boss_cell, factors,
			"%s-%s" % [_f(vit_low, 0), _f(vit_high, 0)], _share_cell(vit_heroes, float(b["main"])), _share_cell(vit_heroes, big_hit)])

		var ranged: Dictionary = heroes[REF_RANGED]
		var melee: Dictionary = heroes[REF_MELEE]
		var per_room := float(fs["per_room"])
		var room_hp := per_room * float(b["hp"]) * (1.0 + float(fs["variant_share"]) * (Monsters.VARIANT_HP - 1.0))
		var room_dps := per_room * float(b["dps"])
		var frail_hp := hp_low
		var sturdy_hp := hp_high
		time_rows.append([String(s["label"]), "%s / %s" % [_f(float(ranged["bolt_sus"]), 1), _f(float(melee["slash_sus"]), 1)],
			_f(float(b["hp"]), 0), "%s / %s" % [_f(float(b["hp"]) / float(ranged["bolt_sus"]), 1), _f(float(b["hp"]) / float(melee["slash_sus"]), 1)],
			_f(float(boss["hp"]), 0) if not boss.is_empty() else "-",
			("%s / %s" % [_f(float(boss["hp"]) / float(ranged["bolt_sus"]), 0), _f(float(boss["hp"]) / float(melee["slash_sus"]), 0)]) if not boss.is_empty() else "-",
			_f(per_room, 1), _f(room_hp, 0), "%s / %s" % [_f(room_hp / float(ranged["bolt_sus"]), 0), _f(room_hp / float(melee["slash_sus"]), 0)],
			_f(room_dps, 1), "%s-%s" % [_f(frail_hp / room_dps, 1), _f(sturdy_hp / room_dps, 1)]])

		var gained := _levels_gained("knight", tier, f)
		var heal := float(fs["forge"]) * Dungeon.FORGE_HEAL + gained * CharacterData.LEVEL_UP_HEAL_FRACTION + float(fs["cleared"]) * Dungeon.CLEAR_HEAL
		var budget := heal / maxf(float(fs["fights"]), 1.0)
		var median := _median_share(heroes, float(b["main"]))
		var regen_low := INF
		var regen_high := 0.0
		for cls in heroes:
			var per_sec := float(heroes[cls]["hp_regen"]) / float(heroes[cls]["hp"])
			regen_low = minf(regen_low, per_sec)
			regen_high = maxf(regen_high, per_sec)
		heal_rows.append([String(s["label"]), _f(float(fs["fights"]), 1), _p(float(fs["forge"]), 0), str(gained), _p(heal, 0), _p(budget, 1),
			_f(budget / median, 1), "%s-%s" % [_f(0.1 / regen_high, 0), _f(0.1 / regen_low, 0)]])
	_table(["Where", "Lvl", "Gear ilvl", "Max HP", "Normal", "Heaviest normal", "Elite (variant)", "Guardian slam", "Boss slam",
		"Factor normal/elite/boss (guardian off the last floor)", "HP, all points in VIT", "Normal, VIT", "Boss or guardian, VIT"], hit_rows)
	print("The VIT columns are the same heroes with every free point (%d a level) spent on Vitality: the most HP a hero can have.\n" % CharacterData.FREE_POINTS_PER_LEVEL)

	print("### 3b. Time to kill and the room's pressure (%s fireball / %s slash, sustained)\n" % [Classes.CLASSES[REF_RANGED]["name"], Classes.CLASSES[REF_MELEE]["name"]])
	print("Room DPS = every monster attacking whenever it can, no dodging (an upper bound). 'Stand still' = seconds until the room kills a hero who never dodges.\n")
	_table(["Where", "Hero DPS", "Normal HP", "TTK normal (s)", "Boss HP", "TTK boss (s)", "Monsters/room", "Room HP", "Room clear (s)", "Room DPS", "Stand still (s)"], time_rows)

	print("### 3c. Healing between rooms\n")
	print("Fights/floor = combat + guardian + boss rooms. Heal/floor = chance of a forge room x %s + levels gained x %s + combat and guardian rooms cleared x %s." % [
		_p(Dungeon.FORGE_HEAL, 0), _p(CharacterData.LEVEL_UP_HEAL_FRACTION, 0), _p(Dungeon.CLEAR_HEAL, 0)])
	print("Budget = heal per fight; hits = how many median normal hits that budget covers. Regen: seconds to regain 10%% of max HP, after %s s without a hit.\n" % _f(_player["regen_delay"], 0))
	_table(["Where", "Fights/floor", "Forge chance", "Levels gained", "Heal/floor", "Budget/fight", "Normal hits/fight", "Regen 10% (s)"], heal_rows)
	_healing_sources()
	_telegraphs()
	_speeds()


func _healing_sources() -> void:
	var novice := _stats(_hero(Classes.NEUTRAL_CLASS, 10, 0))
	var deep := _stats(_hero("vanguard", 30, 60))
	var rows := []
	for id in ["tidal_mending", "benediction"]:
		var buff: Dictionary = SkillDB.DEFS[id]["buff"]
		rows.append([String(SkillDB.DEFS[id]["name"]) + " (%s support, level %d)" % [String(SkillDB.DEFS[id]["element"]), Classes.SUPPORT_LEVEL],
			"%s HP over %s s, every %s s" % [_f(float(buff["power"]) * float(buff["time"]) * float(novice["buff_mult"]), 0), _f(float(buff["time"]), 0), _f(float(SkillDB.DEFS[id]["cooldown"]), 0)]])
	rows.append(["Shadow Bolt lifesteal (dark)", _p(float(SkillDB.DEFS["shadow_bolt"]["lifesteal"]), 0) + " of damage dealt"])
	rows.append(["Bloodrage (Berserker) / Vampiric / Survivor", "%s / %s / %s HP per kill" % [_f(float(Classes.PASSIVES["bloodrage"]["mods"]["kill_hp_add"]), 0),
		_f(float(Classes.PASSIVES["vampiric"]["mods"]["kill_hp_add"]), 0), _f(float(Classes.PASSIVES["survivor"]["mods"]["kill_hp_add"]), 0)]])
	rows.append(["Lucky Charm (amulet) at item level 60, uncommon", _f(float(deep["kill_hp"]), 1) + " HP per kill"])
	rows.append(["Natural regen, Novice level 10", "%s HP/s = %s of max HP per minute" % [_f(float(novice["hp_regen"]), 2), _p(float(novice["hp_regen"]) * 60.0 / float(novice["hp"]), 1)]])
	rows.append(["Forge room / camp", "%s of max HP, all stamina and mana / everything" % _p(Dungeon.FORGE_HEAL, 0)])
	rows.append(["Level-up", _p(CharacterData.LEVEL_UP_HEAL_FRACTION, 0) + " of max HP"])
	rows.append(["Clearing a combat or guardian room", _p(Dungeon.CLEAR_HEAL, 0) + " of max HP"])
	rows.append(["Potions, drops that heal", "none exist"])
	print("Every healing source in the game:\n")
	_table(["Source", "Amount"], rows)


func _telegraphs() -> void:
	print("### 3d. Warning time versus the dodge (Knight)\n")
	var iframes := float(_player["iframes"])
	var roll := float(_player["dodge_speed"]) * float(_player["dodge_time"]) * DODGE_EASE
	print("Dodge: %s s of i-frames, rolls about %s px, %s stamina, %s s cooldown. Novice speed %s px/s.\n" % [_f(iframes, 2), _f(roll, 0),
		_f(_player["dodge_cost"], 0), _f(_player["dodge_cd"], 2), _f(float(_stats(_hero(Classes.NEUTRAL_CLASS, 1, 0))["move"]), 0)])
	var hero_speed := float(_stats(_hero(Classes.NEUTRAL_CLASS, 1, 0))["move"])
	var headers := ["Attack"]
	for depth in ESCAPE_DEPTHS:
		headers.append("d%d" % depth)
	var rows := [["Touch (every melee monster)"]]
	for depth in ESCAPE_DEPTHS:
		rows[0].append("no warning")
	for id in ["imp", "wolf", "duelist"]:
		var row := ["%s dash: wind-up, lunge" % String(Monsters.DEFS[id]["name"])]
		for depth in ESCAPE_DEPTHS:
			var m := _monster(id, depth, "knight")
			row.append("%s s, %s px" % [_f(float(m["dash_windup"]), 2), _f(float(m["lunge"]), 0)])
		rows.append(row)
	var shot_row := ["Fastest shot in band: flight"]
	for depth in ESCAPE_DEPTHS:
		var fastest := INF
		for id in Monsters.WEIGHTS[Monsters.band_of(depth)]:
			var m := _monster(String(id), depth, "knight")
			if float(m["flight"]) > 0.0:
				fastest = minf(fastest, float(m["flight"]))
		shot_row.append(_f(fastest, 2) + " s" if fastest < INF else "-")
	rows.append(shot_row)
	for id in ["slime_king", "crypt_lich", "gloaming_sovereign", "bog_hulk"]:
		var row := ["%s slam: telegraph, walk out" % String(Monsters.DEFS[id]["name"])]
		for depth in ESCAPE_DEPTHS:
			var m := _monster(id, depth, "knight")
			row.append("%s s, %s s" % [_f(float(m["slam_tele"]), 2), _f(float(m["slam_radius"]) / hero_speed, 2)])
		rows.append(row)
	_table(headers, rows)
	print("'Walk out' = slam radius / Novice speed from the very centre (an upper bound). A dodge only needs its %s s of i-frames to cover the landing.\n" % _f(iframes, 2))


func _speeds() -> void:
	print("### 3e. Speed: monsters (they speed up with depth) against the hero\n")
	var rows := []
	for s in _samples():
		var level := _level_at("knight", int(s["tier"]), int(s["floor"]))
		var heroes := _class_line(level, int(_loot_point(level, int(s["depth"]), 0, "knight").x))
		var slow := INF
		var fast := 0.0
		for cls in heroes:
			slow = minf(slow, float(heroes[cls]["move"]))
			fast = maxf(fast, float(heroes[cls]["move"]))
		var faster := []
		var top := 0.0
		var top_name := ""
		var dash_top := 0.0
		for id in Monsters.WEIGHTS[Monsters.band_of(int(s["depth"]))]:
			var m := _monster(String(id), int(s["depth"]), "knight")
			if float(m["speed"]) > slow:
				faster.append(String(m["name"]))
			if float(m["speed"]) > top:
				top = float(m["speed"])
				top_name = String(m["name"])
			dash_top = maxf(dash_top, float(m["dash_speed"]))
		rows.append([String(s["label"]), "%s-%s" % [_f(slow, 0), _f(fast, 0)], "%s %s" % [top_name, _f(top, 0)], _f(dash_top, 0) if dash_top > 0.0 else "-",
			", ".join(faster) if not faster.is_empty() else "none"])
	_table(["Where", "Hero move (classes)", "Fastest walker", "Fastest dash", "Walk faster than the slowest hero"], rows)


func _section_economy() -> void:
	print("## 4. Economy\n")
	print("### 4a. Income of one first clear, Knight (the hero's level as in 2d; every gear piece counted, mean of %d layouts)\n" % SEEDS)
	var rows := []
	for tier in Game.TIERS:
		var t: Dictionary = _economy["knight"][tier]
		var rar: Dictionary = t["rarities"]
		var mix := []
		for r in Items.RARITIES:
			if rar.has(r):
				mix.append("%s %s" % [_f(float(rar[r]), 1), String(r).substr(0, 1).to_upper()])
		rows.append(["T%d" % tier, _f(float(t["kills"]), 0), _f(float(t["chest"]), 0), _f(float(t["mini"]), 0), _f(float(t["boss"]), 0),
			_f(float(t["bonus"]), 0), _f(float(t["gold"]), 0), _f(float(t["scrap"]), 0), _f(float(t["gel"]), 0), _f(float(t["essence"]), 1),
			_f(float(t["gems"]), 2), "%s (%s)" % [_f(float(t["items"]), 1), ", ".join(mix)],
			"%s g + %s scrap" % [_f(float(t["salvage_gold"]), 0), _f(float(t["salvage_scrap"]), 0)]])
	_table(["Tier", "Gold: kills", "Chests", "Guardians", "Boss", "Clear bonus", "Gold total", "Scrap", "Gel", "Essence", "Gems", "Gear pieces",
		"Salvage all gear"], rows)
	rows = []
	for tier in Game.TIERS:
		var cells := ["T%d" % tier]
		for oath in OATHS:
			var t: Dictionary = _economy[oath][tier]
			cells.append("%s (kills %s)" % [_f(float(t["gold"]), 0), _f(float(t["kills"]), 0)])
		rows.append(cells)
	print("Gold of one clear by oath (drop gold, the clear bonus and drop luck all follow the oath's reward):\n")
	_table(["Tier", "Squire", "Knight", "Warlord"], rows)

	print("### 4b. What the forge charges (Forge.*_cost)\n")
	rows = []
	for base_id in Items.gear_bases():
		var cost := Forge.craft_cost(String(base_id))
		rows.append([String(Items.BASES[base_id]["name"]), str(cost.get("gold", 0)), str(cost.get("scrap", 0)), str(cost.get("slime_gel", 0)), str(Items.BASES[base_id].get("min_ilvl", 1))])
	_table(["Craft", "Gold", "Scrap", "Gel", "Drops from ilvl"], rows)
	rows = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var kit := {}
	for r in Items.RARITIES:
		var item := Items.make("iron_sword", String(r), 1, rng)
		var to5 := Vector2.ZERO
		var to10 := Vector2.ZERO
		for plus in Items.MAX_PLUS:
			item["plus"] = plus
			var c := Forge.upgrade_cost(item)
			to10 += Vector2(int(c["gold"]), int(c["scrap"]))
			if plus < 5:
				to5 += Vector2(int(c["gold"]), int(c["scrap"]))
		item["plus"] = 0
		var ench := []
		for ilvl in [1, 10, 30, 60]:
			item["ilvl"] = ilvl
			var e := Forge.enchant_cost(item, REF_ELEMENT)
			ench.append("%dg+%d" % [int(e["gold"]), int(e[Items.essence_of(REF_ELEMENT)])])
		kit[r] = {"to5": to5, "to10": to10}
		rows.append([String(Items.RARITY[r]["name"]), "%d g, %d scrap" % [int(to5.x), int(to5.y)], "%d g, %d scrap" % [int(to10.x), int(to10.y)], " / ".join(ench)])
	_table(["Rarity", "Upgrade +0 to +5", "Upgrade +0 to +10", "Enchant at ilvl 1 / 10 / 30 / 60 (gold + essence)"], rows)
	var unc5: Vector2 = kit["uncommon"]["to5"] * Items.SLOTS.size()
	var unc10: Vector2 = kit["uncommon"]["to10"] * Items.SLOTS.size()
	rows = []
	for tier in Game.TIERS:
		var t: Dictionary = _economy["knight"][tier]
		var scrap_in := float(t["scrap"]) + float(t["salvage_scrap"])
		var gold_in := float(t["gold"]) + float(t["salvage_gold"])
		rows.append(["T%d" % tier, "%s g, %s scrap" % [_f(gold_in, 0), _f(scrap_in, 0)],
			"%s / %s" % [_f(unc5.x / gold_in, 1), _f(unc5.y / scrap_in, 1)], "%s / %s" % [_f(unc10.x / gold_in, 1), _f(unc10.y / scrap_in, 1)]])
	print("Six uncommon pieces to +5 cost %d gold and %d scrap; to +10, %d gold and %d scrap. Clears needed (gold / scrap), salvaging every drop:\n" % [int(unc5.x), int(unc5.y), int(unc10.x), int(unc10.y)])
	_table(["Tier", "Income incl. salvage", "Clears for +5 kit", "Clears for +10 kit"], rows)


func _section_death() -> void:
	print("## 5. What a death costs today\n")
	var consts: Dictionary = Game.get_script().get_script_constant_map()
	var loss := float(consts.get("DEATH_GOLD_LOSS", 0.0))
	var rows := []
	var carried := 0.0
	for tier in Game.TIERS:
		carried += float(_economy["knight"][tier]["gold"])
		rows.append(["after T%d" % tier, _f(carried, 0), str(floori(carried * loss))])
	print("Gold: Game.DEATH_GOLD_LOSS = %s of the gold carried (Dungeon._finish_run). If nothing was spent since T1:\n" % _p(loss, 0))
	_table(["Hero has cleared", "Gold carried", "Lost on a fall"], rows)

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var counts := {}
	var rolls := 20000
	for i in rolls:
		var n: int = Array(Ceremony.perform(rng)["elements"]).size()
		counts[n] = int(counts.get(n, 0)) + 1
	rows = []
	var keys: Array = counts.keys()
	keys.sort()
	for n in keys:
		var c := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, Elements.MAIN.slice(0, mini(int(n), Elements.MAIN.size())), 1)
		if int(n) == 0:
			c.affinity = CharacterData.ATTUNABLE  # as CharacterData.create makes an elementalist born with none
		c.death_rng.seed = 5
		var losses := []
		var final_at := 0
		for death in range(1, 12):
			var result: Dictionary = c.call("die")
			if bool(result.get("final", false)):
				final_at = death
				break
			losses.append(str(Array(result.get("lost", [])).size()))
		rows.append([str(n), _p(float(counts[n]) / rolls, 1), ", ".join(losses) if not losses.is_empty() else "-", "death %d" % final_at])
	print("Elements: CharacterData.die() run live on heroes born with N elements (Ceremony.perform, %d seeded rolls):\n" % rolls)
	_table(["Born with", "Share of new heroes", "Elements lost per death", "Permadeath at"], rows)


func _section_outliers() -> void:
	print("## 6. Outliers measured\n")
	var lines := []
	var end_level := int(_tier_end["knight"][5])
	lines.append("Level cap: CharacterData.MAX_LEVEL = %d. First clears reach level %d after T3, %d after T4, %d after T5 (Knight)." % [
		CharacterData.MAX_LEVEL, int(_tier_end["knight"][3]), int(_tier_end["knight"][4]), end_level])
	for id in Monsters.bosses():
		var spec_tier := int(Monsters.DEFS[id].get("tier", 1))
		var depth := int(Game.TIERS[spec_tier]["depth"]) + int(Game.TIERS[spec_tier]["floors"])
		var summon: Dictionary = Monsters.DEFS[id]["summon"]
		var minion := _enemy(String(summon["id"]), "", 1.0, 1.0, 1)
		var native := _monster(String(summon["id"]), depth, "knight")
		lines.append("Summons: %s (depth %d) calls %s with %s HP and a %s hit; the same monster spawned on that floor has %s HP and a %s hit." % [
			String(Monsters.DEFS[id]["name"]), depth, String(minion["name"]), _f(float(minion["hp"]), 0), _f(float(minion["heavy"]), 1),
			_f(float(native["hp"]), 0), _f(float(native["heavy"]), 1)])
	for id in ["imp", "wolf", "duelist"]:
		var m := _monster(id, 62, "knight")
		lines.append("Dash at depth 62: %s winds up %s s, lunges at %s px/s for %s px (Dungeon.TILE = %d px), every %s s." % [
			String(m["name"]), _f(float(m["dash_windup"]), 2), _f(float(m["dash_speed"]), 0), _f(float(m["lunge"]), 0), Dungeon.TILE, _f(float(m["dash_cd"]), 2)])
	var ranged := _stats(_hero(REF_RANGED, 20, 40))
	var hit_rate := float(ranged["bolt_rate"])  # sustained fireballs per second, Channeler 20
	for id in ["wraith", "duelist", "shade"]:
		for depth in [5, 20, 62]:
			var m := _monster(id, depth, "knight")
			var k := float(m["dodge_cd"]) * hit_rate
			var dodged := float(m["dodge"]) / (1.0 + float(m["dodge"]) * k)
			lines.append("Dodgers: %s at depth %d sidesteps %s of hits (cooldown %s s); at %s hits/s it voids %s of them, x%s effective HP." % [
				String(m["name"]), depth, _p(float(m["dodge"]), 0), _f(float(m["dodge_cd"]), 2), _f(hit_rate, 2), _p(dodged, 0), _f(1.0 / (1.0 - dodged), 2)])
	var novice_speed := float(_stats(_hero(Classes.NEUTRAL_CLASS, 1, 0))["move"])
	for id in Monsters.regular():
		for depth in range(1, 63):
			if float(_monster(String(id), depth, "knight")["speed"]) > novice_speed:
				lines.append("Speed: %s walks faster than a %s px/s hero from depth %d." % [String(Monsters.DEFS[id]["name"]), _f(novice_speed, 0), depth])
				break
	var spitter := _monster("spitter", 10, "knight")
	var fire_spitter := _monster("spitter", 10, "knight", "fire")
	lines.append("Variants: at depth 10 a Spitter touches for %s and shoots for %s; a Fire Spitter touches for %s and still shoots for %s (VARIANT_DAMAGE skips shots)." % [
		_f(float(spitter["touch"]), 1), _f(float(spitter["shot"]), 1), _f(float(fire_spitter["touch"]), 1), _f(float(fire_spitter["shot"]), 1)])
	lines.append("XP per kill ignores depth: a Slime gives %d XP at depth 1 and at depth 62, while level 29 needs %d XP." % [
		int(_monster("slime", 62, "knight")["xp"]), CharacterData.xp_to_next(29)])
	var low_gold := float(_economy["squire"][5]["kills"])
	var high_gold := float(_economy["warlord"][5]["kills"])
	lines.append("Oath reward: T5 kill gold is %s on Squire and %s on Warlord (x%s); XP is x%s." % [
		_f(low_gold, 0), _f(high_gold, 0), _f(high_gold / maxf(low_gold, 1.0), 2), _f(float(_tier_xp["warlord"][5]) / maxf(float(_tier_xp["squire"][5]), 1.0), 2)])
	for ilvl in [10, 30, 60, 80]:
		var st := _stats(_hero("vanguard", 30, ilvl))
		lines.append("Gear defence: typical gear at item level %d gives damage taken x%s and %s HP per kill (Vanguard 30)." % [ilvl, _f(float(st["dtm"]), 3), _f(float(st["kill_hp"]), 1)])
	for line in lines:
		print("- " + String(line))
	print("")


# ---------- formatting ----------

func _share(st: Dictionary, hit: float) -> float:
	return hit * float(st["dtm"]) / float(st["hp"])


## "low-high% (n)": the share of max HP across the classes, and the hits that kill the frailest.
func _share_cell(heroes: Dictionary, hit: float) -> String:
	var low := INF
	var high := 0.0
	for cls in heroes:
		var v := _share(heroes[cls], hit)
		low = minf(low, v)
		high = maxf(high, v)
	if high <= 0.0:
		return "-"
	return "%s-%s (%d)" % [_f(low * 100.0, 1), _p(high, 1), ceili(1.0 / high)]


func _median_share(heroes: Dictionary, hit: float) -> float:
	var values := []
	for cls in heroes:
		values.append(_share(heroes[cls], hit))
	values.sort()
	return float(values[values.size() / 2])


## The damage multiplier that puts the median class in the middle of the target band.
func _factor(heroes: Dictionary, hit: float, kind: String) -> String:
	var now := _median_share(heroes, hit)
	if now <= 0.0:
		return "-"
	var target: Vector2 = TARGETS[kind]
	return "x" + _f((target.x + target.y) * 0.5 / now, 2)


func _dmg(v: float) -> String:
	return _f(v, 1) if v > 0.0 else "-"


func _shot(m: Dictionary) -> String:
	if float(m["shot"]) <= 0.0:
		return "-"
	return "%s @%ss, %ss" % [_f(float(m["shot"]), 1), _f(float(m["shot_cd"]), 1), _f(float(m["flight"]), 2)]


func _dash(m: Dictionary) -> String:
	if float(m["dash_mult"]) <= 0.0:
		return "-"
	return "%s @%ss, %ss" % [_f(float(m["dash_hit"]), 1), _f(float(m["dash_cd"]), 1), _f(float(m["dash_windup"]), 2)]


func _slam(m: Dictionary) -> String:
	if float(m["slam"]) <= 0.0:
		return "-"
	return "%s @%ss, %ss, r%s" % [_f(float(m["slam"]), 1), _f(float(m["slam_cd"]), 1), _f(float(m["slam_tele"]), 2), _f(float(m["slam_radius"]), 0)]


func _f(v: float, decimals: int = 1) -> String:
	return ("%%.%df" % decimals) % v


func _p(v: float, decimals: int = 1) -> String:
	return _f(v * 100.0, decimals) + "%"


func _table(headers: Array, rows: Array) -> void:
	var widths: Array[int] = []
	for h in headers:
		widths.append(str(h).length())
	for row in rows:
		for i in row.size():
			widths[i] = maxi(widths[i], str(row[i]).length())
	_row(headers, widths)
	var rule := []
	for w in widths:
		rule.append("-".repeat(w))
	_row(rule, widths)
	for row in rows:
		_row(row, widths)
	print("")


func _row(cells: Array, widths: Array[int]) -> void:
	var parts: Array[String] = []
	for i in cells.size():
		parts.append(str(cells[i]).rpad(widths[i]))
	print("| " + " | ".join(parts) + " |")
