extends Node
## Global game state: the current character, loot drops and a short on-screen banner.
## A fresh game starts with a real ceremony roll; the sandbox grants every element for testing.

const SANDBOX_LEVEL := 10
const HURT_TIME := 0.6  # seconds the hit indicator stays on screen
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const RARE_GEM_CHANCE := 0.6  # the second dungeon's bosses: the chance of their Light or Dark gem
const DEATH_GOLD_LOSS := 0.3  # share of carried gold a fall in the dungeon costs

## Chosen when a hero is created and kept in the save. "hardness" scales monster health and damage,
## "reward" scales XP, gold and the luck of drops: the harder the oath, the better the spoils.
const DIFFICULTIES := {
	"squire": {"name": "Squire", "hardness": 0.8, "reward": 0.8,
		"desc": "Gentler monsters, smaller spoils. For learning the elements."},
	"knight": {"name": "Knight", "hardness": 1.0, "reward": 1.0,
		"desc": "The intended game. Resources are tight; death costs you."},
	"warlord": {"name": "Warlord", "hardness": 1.3, "reward": 1.6,
		"desc": "Brutal monsters, 60% richer spoils. Mistakes are paid in elements."},
}

## The dungeons of the camp's gate, in order: floors per dungeon and how deep their monsters start.
## Each is cleared once to open the next; you may go back to clear them again for loot.
const TIERS := {
	1: {"name": "The Ashen Vaults", "floors": 5, "depth": 0,
		"desc": "Five floors under a burned chapel. A warden waits on the third; the Slime King below."},
	2: {"name": "The Drowned Crypts", "floors": 10, "depth": 5,
		"desc": "Ten flooded floors. Three wardens, then the master of the crypts."},
}

## Emitted when a kill drops loot (see Loot): the world spawns Pickups at `position`.
signal loot_dropped(drops: Array, position: Vector2)

var character: CharacterData
var banner_text := ""
var banner_time := 0.0
var danger := 0  # how deep the player is (the arena's wave): raises item level and rarity luck
var loot_rng := RandomNumberGenerator.new()  # tests may seed it
var combat_rng := RandomNumberGenerator.new()  # crits
var creation_required := false  # a brand-new saved hero must pass the creation menu first
var open_creation := false  # the next scene opens the new-character menu (after a permanent death)
var run_text := ""          # "Floor 1/3  Room 2/3 ..." for the HUD (set by Dungeon)
var run_kills := 0
var boss: Node = null       # the boss being fought, for the HUD's boss bar
var hurt_time := 0.0        # > 0 while the red hit indicator is showing (HUD)
var hurt_dir := Vector2.ZERO  # screen direction the last hit came from
var slot := -1              # save slot of the hero being played (-1: none, e.g. the sandbox or tests)
var meta: Dictionary = SaveStore.new_meta()  # long-term hero state (difficulty, dungeons cleared ...)
var run: Dictionary = {}    # the dungeon in progress ({} in camp): tier, seed, floor, room, hp ...
var mode := "camp"          # "camp" or "dungeon": what the main scene builds
var _session_start := 0.0


func _ready() -> void:
	loot_rng.randomize()
	combat_rng.randomize()
	start_new(Classes.NEUTRAL_CLASS)


# ---------- saves and the flow between scenes ----------

func difficulty() -> Dictionary:
	return DIFFICULTIES.get(String(meta.get("difficulty", "knight")), DIFFICULTIES["knight"])


## XP, gold and drop-luck multiplier of the chosen difficulty.
func reward_mult() -> float:
	return float(difficulty()["reward"])


## Monster health and damage multiplier of the chosen difficulty.
func hardness_mult() -> float:
	return float(difficulty()["hardness"])


## A brand-new hero in `save_slot`: the creation menu opens in camp, which saves the hero.
func new_game(save_slot: int, difficulty_id: String) -> void:
	slot = save_slot
	meta = SaveStore.new_meta(difficulty_id)
	run = {}
	mode = "camp"
	start_new(Classes.NEUTRAL_CLASS)
	open_creation = true
	creation_required = true
	go_to_game()


## Loads a slot and enters the camp, or resumes the dungeon that was in progress. False if unreadable.
func continue_game(save_slot: int) -> bool:
	var data := SaveStore.load_slot(save_slot)
	if data.is_empty():
		return false
	slot = save_slot
	character = CharacterData.from_dict(data["character"])
	meta = data["meta"]
	run = data["run"]
	mode = "dungeon" if not run.is_empty() else "camp"
	boss = null
	go_to_game()
	return true


## Writes the current hero to its slot. Does nothing without a slot (sandbox, tests).
func save_game() -> Error:
	if slot < 0:
		return ERR_UNAVAILABLE
	var now := Time.get_ticks_msec() / 1000.0
	meta["play_time"] = float(meta.get("play_time", 0.0)) + (now - _session_start)
	_session_start = now
	return SaveStore.save_slot(slot, character.to_dict(), meta, run)


func go_to_game() -> void:
	_session_start = Time.get_ticks_msec() / 1000.0
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func go_to_menu() -> void:
	get_tree().paused = false
	slot = -1
	get_tree().change_scene_to_file(MENU_SCENE)


## From camp: enter dungeon `tier` (1-based). Saves, then rebuilds the scene as a dungeon.
func begin_run(tier: int) -> void:
	var spec: Dictionary = TIERS[tier]
	run = {"tier": tier, "seed": randi(), "floor": 0, "room": 0, "kills": 0, "time": 0.0, "hp": 1.0, "floors": int(spec["floors"])}
	mode = "dungeon"
	save_game()
	get_tree().paused = false
	get_tree().reload_current_scene()


## Back to camp: the run ends (won, fallen or abandoned) and the hero is saved.
func return_to_camp() -> void:
	run = {}
	mode = "camp"
	save_game()
	get_tree().paused = false
	get_tree().reload_current_scene()


func tier_unlocked(tier: int) -> bool:
	return tier <= 1 or int(meta.get("tier_cleared", 0)) >= tier - 1


## Item level of drops: the character's level plus a little for depth.
func loot_level() -> int:
	return character.level + floori(danger / 3.0)


## Luck: each wave of depth shifts drops toward better rarities.
func loot_bonus() -> float:
	return maxf(0.1 * danger + float(character.derived()["loot_luck"]) + (reward_mult() - 1.0), 0.0)


## Sealed characters can never use spells, so they are not given spell-only gear or affixes.
func loot_allows_spell() -> bool:
	return character.affinity != CharacterData.SEALED


## Fresh character: class chosen, then born through the ceremony (elementalists roll their
## elements and may be born with none), or created as attunable / sealed without a ceremony.
func start_new(class_id: String, affinity: String = CharacterData.ELEMENTALIST) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	character = CharacterData.create("Hero", class_id, affinity, rng)
	var class_name_text: String = Classes.CLASSES[class_id]["name"]
	var traits: Array = character.traits.map(func(t): return String(Classes.passive_info(t)["name"]))
	var born: Array = character.elements.map(func(e): return String(e).capitalize())
	var got := ", ".join(born) if not born.is_empty() else "no element"
	var kind := ""
	match character.affinity:
		CharacterData.ATTUNABLE:
			kind = "  (attunable: martial skills)"
		CharacterData.SEALED:
			kind = "  (sealed: martial skills)"
	_show_banner("%s: %s%s\nTraits: %s" % [class_name_text, got, kind, ", ".join(traits)])


## Every main element and enough levels that all skills are learned. For combat testing.
func start_sandbox(class_id: String = "channeler") -> void:
	character = CharacterData.create_sandbox(class_id, Elements.MAIN, SANDBOX_LEVEL)
	_stock_sandbox_inventory()
	_show_banner("Sandbox: all elements, level %d %s (subclass unlocked)" % [character.level, Classes.CLASSES[class_id]["name"]])


## Gold, materials and a handful of random gear so the forge and gear tab can be tried at once.
func _stock_sandbox_inventory() -> void:
	var inv := character.inventory
	inv.gold = 500
	for id in Items.MATERIALS:
		inv.materials[id] = 12
	for i in 6:
		var item := Loot.roll_item(loot_rng, character.level, 1.0)
		if not item.is_empty():
			inv.add_item(item)
	inv.changed.emit()


## Uses an elemental gem from the bag and tells the player.
func use_gem(element: String) -> bool:
	var ok := character.use_gem(element)
	_show_banner(("Attuned to %s!" % element.capitalize()) if ok else "Cannot use that gem")
	return ok


## Debug stand-in for an attunement item or story event: grants a random element not yet owned.
## Returns the element gained, or "" if none could be (sealed, or already has all five).
func attune_random() -> String:
	var missing: Array = Elements.MAIN.filter(func(e): return not (e in character.elements))
	if missing.is_empty() or not character.add_element(missing.pick_random()):
		_show_banner("Cannot gain an element")
		return ""
	var gained: String = character.elements[-1]
	_show_banner("Attuned to %s!" % gained.capitalize())
	return gained


func on_enemy_killed(enemy: Node) -> void:
	run_kills += 1
	character.gain_xp(maxi(1, roundi(float(enemy.xp_reward) * reward_mult())))
	character.add_class_xp(1 + floori(float(enemy.xp_reward) / 10.0))
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("restore_on_kill"):
		player.restore_on_kill()
	var drops: Array[Dictionary]
	if enemy.boss and enemy.mini:
		drops = Loot.mini_boss_drops(loot_rng, loot_level(), loot_bonus(), loot_allows_spell())
	elif enemy.boss:
		drops = Loot.boss_drops(loot_rng, loot_level(), loot_bonus(), character.missing_elements(), loot_allows_spell())
	else:
		drops = Loot.enemy_drops(loot_rng, loot_level(), loot_bonus(), String(enemy.last_element), loot_allows_spell(), String(enemy.variant))
	if enemy.boss and not enemy.mini and enemy.rare_gem != "" and enemy.rare_gem in character.missing_rare() and loot_rng.randf() < RARE_GEM_CHANCE:
		drops.append({"kind": "material", "id": Items.gem_of(enemy.rare_gem), "amount": 1})
	if not drops.is_empty():
		loot_dropped.emit(drops, enemy.global_position)


## Shows a short message in the middle of the screen.
func say(text: String) -> void:
	_show_banner(text)


func _show_banner(text: String) -> void:
	banner_text = text
	banner_time = 6.0


## Called when the player is hit: drives the HUD's red edge flash and direction arrow.
func player_hurt(toward_source: Vector2) -> void:
	hurt_time = HURT_TIME
	hurt_dir = toward_source.normalized() if toward_source != Vector2.ZERO else Vector2.ZERO


func _process(delta: float) -> void:
	banner_time = maxf(0.0, banner_time - delta)
	hurt_time = maxf(0.0, hurt_time - delta)
