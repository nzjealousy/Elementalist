class_name Ceremony
extends RefCounted
## The coming-of-age ceremony: decides which elements a new character is born with, and
## rolls their innate traits. Takes an RNG so results are reproducible in tests and (later)
## seedable for saves.
##
## perform():
##   8% of people are born with no element. They become "attunable": they learn martial
##   skills instead, and can still gain elements later through items or story.
##   Everyone else gets roll():
##     1 main element, guaranteed (uniform over the five)
##     15% chance of a 2nd main element, then 20% each for a 3rd, 4th, 5th (3rd overall = 3%)
##     2% chance each of Light and Dark (opposed: if both come up, one is dropped at random)
##
## roll_traits(): traits are the passives tied to the character. A character with few other
## passive sources (few elements) is more likely to roll several of them.

const NO_ELEMENT_CHANCE := 0.08
const SECOND_CHANCE := 0.15
const FURTHER_CHANCE := 0.20
const RARE_CHANCE := 0.02

const TRAIT_BASE_CHANCE := 0.65  # chance of a 2nd trait when there are no other passive sources
const TRAIT_CHANCE_PER_SOURCE := 0.2  # each other passive source lowers that chance
const TRAIT_MIN_CHANCE := 0.1
const TRAIT_MAX := 4


## Full ceremony. Returns {"elements": Array[String]} (empty = born without elements).
static func perform(rng: RandomNumberGenerator) -> Dictionary:
	var elements: Array[String] = []
	if rng.randf() >= NO_ELEMENT_CHANCE:
		elements = roll(rng)
	return {"elements": elements}


## The element roll for someone who is born with elements (always at least one main element).
static func roll(rng: RandomNumberGenerator) -> Array[String]:
	var pool: Array = Elements.MAIN.duplicate()
	var result: Array[String] = []

	var first: String = pool[rng.randi_range(0, pool.size() - 1)]
	result.append(first)
	pool.erase(first)

	var chance := SECOND_CHANCE
	while not pool.is_empty() and rng.randf() < chance:
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		result.append(pick)
		pool.erase(pick)
		chance = FURTHER_CHANCE

	var light := rng.randf() < RARE_CHANCE
	var dark := rng.randf() < RARE_CHANCE
	if light and dark:
		if rng.randf() < 0.5:
			light = false
		else:
			dark = false
	if light:
		result.append("light")
	if dark:
		result.append("dark")
	return result


## Always at least one trait; more with a falling chance. `other_sources` is how many other
## passive sources the character has (elements, mostly), which lowers the chance of extras.
static func roll_traits(rng: RandomNumberGenerator, other_sources: int, allow_spell: bool = true) -> Array[String]:
	var pool: Array = Classes.available_traits(allow_spell)
	var result: Array[String] = []
	var chance := clampf(TRAIT_BASE_CHANCE - TRAIT_CHANCE_PER_SOURCE * other_sources, TRAIT_MIN_CHANCE, TRAIT_BASE_CHANCE)
	while true:
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		result.append(pick)
		pool.erase(pick)
		if result.size() >= TRAIT_MAX or pool.is_empty() or rng.randf() >= chance:
			break
		chance *= 0.6
	return result
