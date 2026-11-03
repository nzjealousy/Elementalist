extends Node
## Global game state: the current character and a short on-screen banner.
## A fresh game starts with a real ceremony roll; the sandbox grants every element for testing.

var character: CharacterData
var banner_text := ""
var banner_time := 0.0


func _ready() -> void:
	start_new(Classes.NEUTRAL_CLASS)


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
	_show_banner("Sandbox: all elements, level %d %s (subclass unlocked)" % [character.level, Classes.CLASSES[class_id]["name"]])


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


func _show_banner(text: String) -> void:
	banner_text = text
	banner_time = 6.0


func _process(delta: float) -> void:
	banner_time = maxf(0.0, banner_time - delta)
