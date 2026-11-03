class_name Rewards
extends RefCounted
## Milestone level rewards. At each reward level the character is offered 1 to 3 options and
## picks one: a *skill* (the "special" R skill of a set they have access to) or a *passive*
## (a trait they don't have yet). Offers are rolled when the level is reached and kept until
## claimed; CharacterData.claim_reward applies the choice.
##
## Reward levels are every even level except 10 (which is when subclasses unlock):
## 2, 4, 6, 8, 12, 14, ... 30. Class (3), area skills (5) and subclass (10) are separate gates.

const MIN_OPTIONS := 1
const MAX_OPTIONS := 3
const SKILL_CHANCE := 0.5  # chance an option is a skill rather than a passive, when both exist


static func is_reward_level(level: int) -> bool:
	return level % 2 == 0 and level != Classes.SUBCLASS_LEVEL


## Rolls an offer for `character`: 1 to 3 distinct options of the form {"type", "id"}, where
## type is "skill" or "passive". Fewer if there is little left to offer; empty if nothing is.
static func generate(character: CharacterData, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var skills: Array[Dictionary] = []
	for set_id in character.castable_sets():
		var skill_id := String(SkillDB.LOADOUTS[set_id]["special"])
		if not (skill_id in character.learned_specials):
			skills.append({"type": "skill", "id": skill_id})
	var passives: Array[Dictionary] = []
	for trait_id in Classes.available_traits(character.affinity != CharacterData.SEALED):
		if not (trait_id in character.traits):
			passives.append({"type": "passive", "id": trait_id})

	var options: Array[Dictionary] = []
	var wanted := rng.randi_range(MIN_OPTIONS, MAX_OPTIONS)
	while options.size() < wanted and not (skills.is_empty() and passives.is_empty()):
		var use_skills := not skills.is_empty() and (passives.is_empty() or rng.randf() < SKILL_CHANCE)
		var pool := skills if use_skills else passives
		var index := rng.randi_range(0, pool.size() - 1)
		options.append(pool[index])
		pool.remove_at(index)
	return options


## Display name of an option, e.g. "Inferno Ring" or "Sturdy".
static func option_name(option: Dictionary) -> String:
	if option["type"] == "skill":
		return String(SkillDB.DEFS[option["id"]]["name"])
	return String(Classes.passive_info(option["id"])["name"])


## One-line description of an option for menus.
static func option_text(option: Dictionary) -> String:
	if option["type"] == "skill":
		var def: Dictionary = SkillDB.DEFS[option["id"]]
		var set_name := SkillDB.set_of(option["id"]).capitalize()
		return "Skill (R, %s): %s - %d dmg, %d %s, %.0fs cooldown" % [
			set_name, def["name"], int(def["damage"]), int(SkillDB.cost_of(def)),
			"stamina" if SkillDB.uses_stamina(def) else "mana", float(def["cooldown"]),
		]
	var passive := Classes.passive_info(option["id"])
	return "Passive: %s - %s" % [passive["name"], passive["desc"]]
