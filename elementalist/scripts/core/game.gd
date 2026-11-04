extends Node
## Global game state: the current character, loot drops and a short on-screen banner.
## A fresh game starts with a real ceremony roll; the sandbox grants every element for testing.

## Emitted when a kill drops loot (see Loot): the world spawns Pickups at `position`.
signal loot_dropped(drops: Array, position: Vector2)

var character: CharacterData
var banner_text := ""
var banner_time := 0.0
var danger := 0  # how deep the player is (the arena's wave): raises item level and rarity luck
var loot_rng := RandomNumberGenerator.new()  # tests may seed it


func _ready() -> void:
	loot_rng.randomize()
	start_new(Classes.NEUTRAL_CLASS)


## Item level of drops: the character's level plus a little for depth.
func loot_level() -> int:
	return character.level + floori(danger / 3.0)


## Luck: each wave of depth shifts drops toward better rarities.
func loot_bonus() -> float:
	return 0.1 * danger


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
	character = CharacterData.create_sandbox(class_id, Elements.MAIN, Classes.SUBCLASS_LEVEL)
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
	character.gain_xp(int(enemy.xp_reward))
	var drops := Loot.enemy_drops(loot_rng, loot_level(), loot_bonus(), String(enemy.last_element), loot_allows_spell())
	if not drops.is_empty():
		loot_dropped.emit(drops, enemy.global_position)


func _show_banner(text: String) -> void:
	banner_text = text
	banner_time = 6.0


func _process(delta: float) -> void:
	banner_time = maxf(0.0, banner_time - delta)
