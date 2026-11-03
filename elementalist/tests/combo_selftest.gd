extends Node
## Runtime self-test for combat rules: data tables, enemy aura/combo/status logic, and the
## player's stamina-based melee. Run the combo_selftest scene; results are printed as
## PASS/FAIL lines and a final SELFTEST summary.

const SLIME := preload("res://scenes/enemies/slime.tscn")
const PLAYER := preload("res://scenes/player/player.tscn")

var _pass := 0
var _fail := 0


func _ready() -> void:
	Juice.enabled = false  # hit-stop would slow the clock these tests rely on
	_neutral_character()
	await get_tree().process_frame
	_test_data_tables()
	_test_single_hit_sets_aura()
	_test_fire_then_water_is_steam()
	_test_same_element_refreshes()
	_test_earth_then_water_roots()
	_test_water_jet_slows()
	await _test_aura_expires()
	_test_death_signal()
	_test_health_bar_visibility()
	_test_physical_ignores_aura()
	_test_shatter_bonus()
	await _test_melee()
	await _test_dodge_and_cycling()
	await _test_contact_damage()
	await _test_contact_retry_after_iframes()
	await _test_hp_regen()
	await _test_touch_geometry()
	await _test_contact_from_every_side()
	_test_ceremony()
	_test_affinity()
	_test_skill_gating()
	_test_xp_and_levels()
	_test_derived_stats()
	_test_mastery_and_passives()
	_test_subclass()
	_test_save_round_trip()
	await _test_player_uses_character()
	await _test_kill_xp_and_weapon_mastery()
	_test_ceremony_without_element()
	await _test_martial_skills()
	_test_traits()
	_test_passive_types()
	_test_attribute_scaling()
	_test_classes()
	await _test_ui_screens()
	print("SELFTEST %d passed, %d failed" % [_pass, _fail])


## Neutral baseline: attributes all 5, no class growth or passives, owns Fire/Water/Earth.
func _neutral_character() -> void:
	Game.character = CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire", "water", "earth"], 1)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _level_to(c: CharacterData, target: int) -> void:
	while c.level < target:
		c.gain_xp(CharacterData.xp_to_next(c.level))


func _test_ceremony() -> void:
	var rng := _rng(12345)
	var rolls := 20000
	var main: Array = Elements.MAIN
	var valid := true
	var distinct := true
	var second := 0
	var third := 0
	var light := 0
	var dark := 0
	var both := 0
	var first_counts := {}
	for i in rolls:
		var r: Array[String] = Ceremony.roll(rng)
		var mains := r.filter(func(e): return e in main)
		if mains.is_empty():
			valid = false
		if mains.size() != Array(mains).duplicate().size() or _has_duplicates(mains):
			distinct = false
		if mains.size() >= 2:
			second += 1
		if mains.size() >= 3:
			third += 1
		var has_light := "light" in r
		var has_dark := "dark" in r
		light += int(has_light)
		dark += int(has_dark)
		both += int(has_light and has_dark)
		first_counts[r[0]] = int(first_counts.get(r[0], 0)) + 1
	_check("ceremony always grants at least one main element", valid)
	_check("ceremony never repeats an element", distinct)
	_check("ceremony second element is about 15 percent", absf(second / float(rolls) - 0.15) < 0.02)
	_check("ceremony third element is about 3 percent", absf(third / float(rolls) - 0.03) < 0.01)
	_check("ceremony light is about 2 percent", absf(light / float(rolls) - 0.02) < 0.008)
	_check("ceremony dark is about 2 percent", absf(dark / float(rolls) - 0.02) < 0.008)
	_check("ceremony never grants both light and dark", both == 0)
	var uniform := true
	for e in main:
		if absf(int(first_counts.get(e, 0)) / float(rolls) - 0.2) > 0.03:
			uniform = false
	_check("ceremony first element is spread evenly over the five", uniform)
	_check("ceremony is reproducible from a seed", Ceremony.roll(_rng(99)) == Ceremony.roll(_rng(99)))


func _has_duplicates(items: Array) -> bool:
	for i in items.size():
		for j in range(i + 1, items.size()):
			if items[i] == items[j]:
				return true
	return false


func _test_affinity() -> void:
	var elementalist := CharacterData.create("A", "channeler", CharacterData.ELEMENTALIST, _rng(1))
	_check("elementalist is born with elements", elementalist.elements.size() >= 1)
	var sealed := CharacterData.create("B", "vanguard", CharacterData.SEALED, _rng(1))
	_check("sealed character has no elements", sealed.elements.is_empty())
	_check("sealed character can never gain an element", not sealed.add_element("fire") and sealed.elements.is_empty())
	var attunable := CharacterData.create("C", "vanguard", CharacterData.ATTUNABLE, _rng(1))
	_check("attunable character starts with no elements", attunable.elements.is_empty())
	_check("attunable character can gain an element later", attunable.add_element("water") and attunable.elements == ["water"])
	_check("cannot gain the same element twice", not attunable.add_element("water"))
	_check("non-elementalists cannot cast", sealed.castable_elements().is_empty() and not sealed.can_use_skill("fireball"))


func _test_skill_gating() -> void:
	var c := CharacterData.create_sandbox("channeler", ["fire"], 1)
	_check("owned element's primary skill is usable at level 1", c.can_use_skill("fireball"))
	_check("area skill is locked before the class teaches it", not c.can_use_skill("flame_burst"))
	_check("skills of unowned elements are unusable", not c.can_use_skill("water_jet"))
	_level_to(c, 3)
	_check("channeler learns the area skill at level 3", c.can_use_skill("flame_burst"))
	_check("level alone does not unlock other elements", not c.can_use_skill("water_jet"))
	c.add_element("water")
	_check("gaining an element unlocks its learned skills", c.can_use_skill("water_jet") and c.can_use_skill("rain_pool"))
	var v := CharacterData.create_sandbox("vanguard", ["fire"], 4)
	_check("vanguard learns area skills later (level 5)", v.can_use_skill("fireball") and not v.can_use_skill("flame_burst"))
	_level_to(v, 5)
	_check("vanguard has the area skill at level 5", v.can_use_skill("flame_burst"))
	var all_skills_ok := true
	for element in Elements.MAIN:
		for slot in ["primary", "area"]:
			if not SkillDB.DEFS.has(SkillDB.LOADOUTS[element][slot]):
				all_skills_ok = false
	_check("every main element has real primary and area skills", all_skills_ok)
	var light_only := CharacterData.create_sandbox("channeler", ["light"], 5)
	_check("light and dark have no skills yet, so nothing is castable", light_only.castable_elements().is_empty())


func _test_xp_and_levels() -> void:
	var c := CharacterData.create_sandbox("channeler", ["fire"], 1)
	var int_before: int = c.attributes["intellect"]
	_check("level 1 needs 30 xp", CharacterData.xp_to_next(1) == 30)
	var gained := c.gain_xp(29)
	_check("29 xp is not enough to level", gained == 0 and c.level == 1)
	gained = c.gain_xp(1)
	_check("30 xp reaches level 2", gained == 1 and c.level == 2 and c.xp == 0)
	_check("level up grants free attribute points", c.unspent_points == CharacterData.FREE_POINTS_PER_LEVEL)
	_check("class growth applies on level up", c.attributes["intellect"] == int_before + 1)
	c.gain_xp(CharacterData.xp_to_next(2) + CharacterData.xp_to_next(3) + 5)
	_check("one big gain can level several times and keeps the remainder", c.level == 4 and c.xp == 5)
	_check("spending a point raises the attribute", c.spend_point("vitality") and c.unspent_points == 5)
	var points := c.unspent_points
	_check("unknown attribute is refused", not c.spend_point("luck") and c.unspent_points == points)
	var broke := CharacterData.create_sandbox("wanderer", [], 1)
	_check("cannot spend points you do not have", not broke.spend_point("strength"))
	var capped := CharacterData.create_sandbox("wanderer", [], CharacterData.MAX_LEVEL)
	_check("level is capped", capped.gain_xp(100000) == 0 and capped.level == CharacterData.MAX_LEVEL)


func _test_derived_stats() -> void:
	var d: Dictionary = CharacterData.create_sandbox("wanderer", [], 1).derived()
	_check("neutral stats match the tuned combat values", is_equal_approx(d["max_hp"], 100.0) and is_equal_approx(d["hp_regen"], 0.6)
		and is_equal_approx(d["max_mana"], 100.0) and is_equal_approx(d["mana_regen"], 9.0)
		and is_equal_approx(d["max_stamina"], 100.0) and is_equal_approx(d["stamina_regen"], 30.0) and is_equal_approx(d["move_speed"], 80.0))
	var channeler: Dictionary = CharacterData.create_sandbox("channeler", [], 1).derived()
	var vanguard: Dictionary = CharacterData.create_sandbox("vanguard", [], 1).derived()
	_check("vanguard is tougher than channeler", vanguard["max_hp"] > channeler["max_hp"])
	_check("channeler has more mana than vanguard", channeler["max_mana"] > vanguard["max_mana"])
	_check("vanguard hits harder in melee", vanguard["melee_damage_mult"] > 1.2 and channeler["melee_damage_mult"] < 1.0)
	var neutral := CharacterData.create_sandbox("wanderer", ["fire"], 1)
	var stronger := CharacterData.create_sandbox("wanderer", ["fire"], 1)
	stronger.attributes["intellect"] = 15
	_check("intellect raises spell damage", stronger.spell_damage_mult("fire") > neutral.spell_damage_mult("fire") + 0.4)


func _test_mastery_and_passives() -> void:
	var c := CharacterData.create_sandbox("wanderer", ["fire"], 1)
	_check("level 1 mastery gives no damage bonus", is_equal_approx(c.spell_damage_mult("fire"), 1.0))
	c.add_element_xp("fire", CharacterData.mastery_xp_to_next(1) - 1)
	_check("not enough xp does not level mastery", c.element_level("fire") == 1)
	c.add_element_xp("fire", 1)
	_check("element mastery levels up", c.element_level("fire") == 2)
	_check("each mastery level adds 4 percent spell damage", is_equal_approx(c.spell_damage_mult("fire"), 1.04))
	_check("no passive before the unlock level", not ("ember_kindle" in c.active_passives()))
	c.add_element_xp("fire", CharacterData.mastery_xp_to_next(2))
	c.add_element_xp("fire", CharacterData.mastery_xp_to_next(3))
	_check("element passive is still locked at mastery 4 (it is rare)", c.element_level("fire") == 4 and not ("ember_kindle" in c.active_passives()))
	c.add_element_xp("fire", CharacterData.mastery_xp_to_next(4))
	_check("reaching mastery 5 unlocks the rare element passive", c.element_level("fire") == 5 and "ember_kindle" in c.active_passives())
	_check("passive modifies derived stats", is_equal_approx(c.derived()["burn_time_mult"], 1.3))
	c.add_element_xp("water", 100)
	_check("xp for an unowned element is ignored", c.element_level("water") == 0)
	for i in 400:
		c.add_element_xp("fire", 100)
	_check("mastery is capped", c.element_level("fire") == CharacterData.MASTERY_CAP)
	var combined := CharacterData.create_sandbox("vanguard", [], 1)
	_check("class passives apply from level 1", "toughened" in combined.active_passives() and is_equal_approx(combined.derived()["max_hp"], 120.0))
	var weapon_before: float = combined.derived()["melee_damage_mult"]
	combined.add_weapon_xp(CharacterData.mastery_xp_to_next(1))
	_check("weapon mastery raises melee damage", combined.weapon_level() == 2 and combined.derived()["melee_damage_mult"] > weapon_before)
	var table_ok := true
	for id in Classes.PASSIVES:
		var mods: Dictionary = Classes.PASSIVES[id]["mods"]
		for key in mods:
			if not (String(key).ends_with("_add") or String(key).ends_with("_mult")):
				table_ok = false
	_check("every passive modifier is an _add or _mult stat", table_ok)


func _test_subclass() -> void:
	var c := CharacterData.create_sandbox("channeler", ["fire"], 4)
	_check("no subclass choice before level 5", c.available_subclasses().is_empty() and not c.choose_subclass("spellweaver"))
	_level_to(c, 5)
	_check("subclasses offered at level 5", c.available_subclasses().size() == 2)
	_check("cannot pick another class's subclass", not c.choose_subclass("duelist"))
	var before := c.spell_damage_mult("fire")
	_check("can choose a subclass", c.choose_subclass("spellweaver") and c.subclass_id == "spellweaver")
	_check("subclass passive applies", c.spell_damage_mult("fire") > before)
	_check("subclass can only be chosen once", not c.choose_subclass("warden") and c.available_subclasses().is_empty())


func _test_save_round_trip() -> void:
	var c := CharacterData.create("Round", "vanguard", CharacterData.ELEMENTALIST, _rng(7))
	_level_to(c, 6)
	c.spend_point("strength")
	c.choose_subclass("bulwark")
	c.add_element_xp(c.elements[0], 35)
	c.add_weapon_xp(12)
	var loaded := CharacterData.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	_check("save keeps identity, level and subclass", loaded.display_name == c.display_name and loaded.class_id == c.class_id
		and loaded.level == c.level and loaded.subclass_id == c.subclass_id and loaded.affinity == c.affinity)
	_check("save keeps xp, points and attributes as integers", loaded.xp == c.xp and loaded.unspent_points == c.unspent_points
		and loaded.attributes == c.attributes and typeof(loaded.attributes["strength"]) == TYPE_INT)
	_check("save keeps elements and mastery", loaded.elements == c.elements and loaded.element_mastery == c.element_mastery
		and loaded.weapon_masteries == c.weapon_masteries)
	_check("a reloaded character has identical derived stats", loaded.derived() == c.derived())


func _test_player_uses_character() -> void:
	var saved := Game.character
	Game.character = CharacterData.create_sandbox("vanguard", ["fire"], 1)
	await get_tree().process_frame
	var player: Node2D = PLAYER.instantiate()
	add_child(player)
	await get_tree().process_frame
	var d: Dictionary = Game.character.derived()
	_check("player max HP comes from the character", is_equal_approx(player.max_hp, d["max_hp"]) and is_equal_approx(player.hp, d["max_hp"]))
	_check("player stamina and speed come from the character", is_equal_approx(player.max_stamina, d["max_stamina"]) and is_equal_approx(player.speed, d["move_speed"]))
	_check("caster only offers owned elements", player.caster.elements == ["fire"])
	_check("caster casts a learned skill", player.caster.try_cast("fireball"))
	_check("caster refuses a skill the class has not taught yet", not player.caster.try_cast("flame_burst"))
	_check("caster refuses an element the character does not own", not player.caster.try_cast("water_jet"))
	_check("casting grants element mastery xp", Game.character.element_mastery["fire"]["xp"] == 1)
	var hp_before: float = player.max_hp
	Game.character.unspent_points = 1
	Game.character.spend_point("vitality")
	_check("spending a point updates the player live", is_equal_approx(player.max_hp, hp_before + 8.0))
	var leveled := [0]
	Game.character.leveled_up.connect(func(_l): leveled[0] += 1)
	player.hp = 10.0
	Game.character.gain_xp(CharacterData.xp_to_next(1))
	var expected_hp: float = 10.0 + float(player.max_hp) * CharacterData.LEVEL_UP_HEAL_FRACTION
	_check("level up heals only a share of max HP", leveled[0] == 1 and is_equal_approx(player.hp, expected_hp) and player.hp < player.max_hp)
	player.queue_free()
	await get_tree().process_frame
	var sealed := CharacterData.create("S", "vanguard", CharacterData.SEALED, _rng(1))
	Game.character = sealed
	var skill_only: Node2D = PLAYER.instantiate()
	add_child(skill_only)
	await get_tree().process_frame
	_check("a sealed player only has the martial set but still fights", skill_only.caster.elements == ["martial"] and skill_only.try_melee(Vector2.RIGHT))
	skill_only.queue_free()
	Game.character = saved
	await get_tree().process_frame


func _test_ceremony_without_element() -> void:
	var rng := _rng(777)
	var rolls := 20000
	var none := 0
	for i in rolls:
		if Ceremony.perform(rng)["elements"].is_empty():
			none += 1
	_check("about 8 percent are born without an element", absf(none / float(rolls) - Ceremony.NO_ELEMENT_CHANCE) < 0.012)
	var found_none := false
	var found_some := false
	for seed_value in 300:
		var c := CharacterData.create("T", "channeler", CharacterData.ELEMENTALIST, _rng(seed_value))
		if c.elements.is_empty():
			found_none = true
			_check("an element-less ceremony makes the character attunable with martial skills", c.affinity == CharacterData.ATTUNABLE and c.has_martial())
			break
	for seed_value in 300:
		var c := CharacterData.create("T", "channeler", CharacterData.ELEMENTALIST, _rng(seed_value))
		if not c.elements.is_empty():
			found_some = true
			_check("an elementalist born with elements is not martial", c.affinity == CharacterData.ELEMENTALIST and not c.has_martial())
			break
	_check("both ceremony outcomes occur", found_none and found_some)
	_check("every combo has a readable description", Elements.COMBOS.values().all(func(c): return Elements.describe_combo(c).begins_with("x")))


func _test_martial_skills() -> void:
	var c := CharacterData.create("M", "channeler", CharacterData.ATTUNABLE, _rng(1))
	_check("a non-elementalist can use the first martial skill at level 1", c.castable_sets() == ["martial"] and c.can_use_skill("knife_throw"))
	_check("the martial area skill is learned at level 2", not c.can_use_skill("whirlwind"))
	_level_to(c, 2)
	_check("martial area skill unlocks", c.can_use_skill("whirlwind"))
	_check("martial skills need no element and are not usable by elementalists", not CharacterData.create_sandbox("channeler", ["fire"], 5).can_use_skill("knife_throw"))
	_check("an attunable character can still be attuned later", c.add_element("fire") and c.can_use_skill("fireball"))
	_check("attuning keeps the martial skills too", c.castable_sets() == ["fire", "martial"] and c.can_use_skill("knife_throw"))
	var sealed := CharacterData.create("S", "vanguard", CharacterData.SEALED, _rng(1))
	_check("sealed characters have martial skills but can never be attuned", sealed.has_martial() and not sealed.add_element("fire"))
	var strong := CharacterData.create_sandbox("vanguard", [], 1)
	var weak := CharacterData.create_sandbox("channeler", [], 1)
	_check("martial damage scales with Strength", strong.skill_damage("knife_throw") > weak.skill_damage("knife_throw"))

	var saved := Game.character
	Game.character = CharacterData.create("M", "vanguard", CharacterData.ATTUNABLE, _rng(2))
	await get_tree().process_frame
	var player: Node2D = PLAYER.instantiate()
	add_child(player)
	await get_tree().process_frame
	var caster: SkillCaster = player.caster
	var stamina_before: float = player.stamina
	var mana_before: float = caster.mana
	_check("martial set is the only selectable set", caster.elements == ["martial"])
	_check("a martial skill casts", caster.try_cast("knife_throw"))
	_check("martial skills spend stamina, not mana", is_equal_approx(stamina_before - player.stamina, 10.0) and caster.mana >= mana_before)
	player.stamina = 5.0
	caster.cooldowns.clear()
	_check("martial skills need enough stamina", not caster.try_cast("knife_throw"))
	Game.character.add_element("water")
	_check("gaining an element updates the caster's sets live", caster.elements == ["water", "martial"])
	player.queue_free()
	await get_tree().process_frame
	Game.character = saved


func _mean_traits(other_sources: int, samples: int) -> float:
	var rng := _rng(4242 + other_sources)
	var total := 0
	for i in samples:
		total += Ceremony.roll_traits(rng, other_sources).size()
	return total / float(samples)


func _test_traits() -> void:
	var rng := _rng(5)
	var valid := true
	for i in 500:
		var rolled := Ceremony.roll_traits(rng, i % 5)
		if rolled.is_empty() or rolled.size() > Ceremony.TRAIT_MAX or _has_duplicates(rolled) or not rolled.all(func(t): return Classes.TRAITS.has(t)):
			valid = false
	_check("traits: 1 to 4, no repeats, all real", valid)
	_check("characters with fewer other passive sources roll more traits", _mean_traits(0, 3000) > _mean_traits(3, 3000) + 0.3)
	_check("every trait has a passive definition", Classes.TRAITS.all(func(t): return Classes.PASSIVES.has(t)))
	var c := CharacterData.create_sandbox("wanderer", [], 1)
	var before: float = c.derived()["max_hp"]
	c.traits = ["sturdy"]
	_check("a trait applies as a passive of type trait", c.passive_sources() == [{"id": "sturdy", "type": "trait"}] and is_equal_approx(c.derived()["max_hp"], before + 12.0))
	c.traits = ["sharp_mind", "hardy_lungs"]
	_check("traits can add mana and stamina", is_equal_approx(c.derived()["max_mana"], 115.0) and is_equal_approx(c.derived()["max_stamina"], 112.0))
	var created := CharacterData.create("T", "ranger", CharacterData.SEALED, _rng(3))
	_check("created characters get at least one trait", created.traits.size() >= 1)


func _test_passive_types() -> void:
	var c := CharacterData.create_sandbox("channeler", ["fire"], 5)
	c.traits = ["focused"]
	var types: Array = c.passive_sources().map(func(s): return s["type"])
	_check("class and trait passives are listed with their types", "class" in types and "trait" in types and not ("element" in types))
	for i in 140:
		c.add_element_xp("fire", 20)
	_check("element mastery adds an element-type passive", c.passive_sources().any(func(s): return s["type"] == "element"))

	var s := CharacterData.create_sandbox("wanderer", ["fire"], 5)
	var base_damage := s.skill_damage("flame_burst")
	var base_cooldown := s.skill_cooldown("flame_burst")
	var unlocked := []
	s.passive_unlocked.connect(func(passive_name): unlocked.append(passive_name))
	for i in Classes.skill_passive_uses("flame_burst") - 1:
		s.record_skill_use("flame_burst")
	_check("skill mastery passive is locked just before the threshold", not ("mastery_flame_burst" in s.active_passives()) and unlocked.is_empty())
	s.record_skill_use("flame_burst")
	_check("enough uses unlock a skill-type passive", "mastery_flame_burst" in s.active_passives() and unlocked == ["Flame Burst Mastery"])
	_check("skill passive is typed skill", s.passive_sources().any(func(src): return src["type"] == "skill" and src["id"] == "mastery_flame_burst"))
	_check("skill passive boosts only that skill's damage", is_equal_approx(s.skill_damage("flame_burst"), base_damage * 1.15) and is_equal_approx(s.skill_damage("rain_pool"), CharacterData.create_sandbox("wanderer", ["fire"], 5).skill_damage("rain_pool")))
	_check("skill passive shortens that skill's cooldown", is_equal_approx(s.skill_cooldown("flame_burst"), base_cooldown * 0.9))
	_check("primary skills need more uses than area skills", Classes.skill_passive_uses("fireball") > Classes.skill_passive_uses("flame_burst"))
	var weapon := CharacterData.create_sandbox("vanguard", [], 1)
	for i in 4:
		weapon.add_weapon_xp(CharacterData.mastery_xp_to_next(weapon.weapon_level()))
	_check("weapon mastery 5 unlocks a rare passive", weapon.weapon_level() == 5 and "blade_training" in weapon.active_passives())
	var round_trip := CharacterData.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	_check("skill usage and passives survive saving", round_trip.skill_uses == s.skill_uses and "mastery_flame_burst" in round_trip.active_passives())
	var traits_saved := CharacterData.create("T", "mystic", CharacterData.ELEMENTALIST, _rng(11))
	var loaded := CharacterData.from_dict(JSON.parse_string(JSON.stringify(traits_saved.to_dict())))
	_check("traits survive saving", loaded.traits == traits_saved.traits and loaded.derived() == traits_saved.derived())


func _test_attribute_scaling() -> void:
	var c := CharacterData.create_sandbox("wanderer", ["fire", "water"], 1)
	_check("fire potency is governed by Strength", is_equal_approx(c.potency_mult("fire"), 1.0))
	c.attributes["strength"] = 15
	c.attributes["agility"] = 15
	c.attributes["intellect"] = 15
	_check("more Strength means stronger fire status effects", is_equal_approx(c.potency_mult("fire"), 1.3))
	_check("water potency follows Agility instead", is_equal_approx(c.potency_mult("water"), 1.3))
	c.attributes["strength"] = 2
	_check("low Strength weakens fire potency", c.potency_mult("fire") < 1.0)
	_check("martial skills have no element potency", is_equal_approx(c.potency_mult(""), 1.0))
	_check("area radius scales with its attribute", is_equal_approx(c.skill_scale("flame_burst", "radius"), 1.3))
	_check("skills that do not scale a property are unchanged", is_equal_approx(c.skill_scale("fireball", "radius"), 1.0))
	_check("Agility shortens thorn shot cooldown", is_equal_approx(c.skill_cooldown("thorn_shot"), 0.45 * 0.8))
	_check("projectile speed scales with Agility", is_equal_approx(c.skill_scale("water_jet", "speed"), 1.3))
	var data_ok := true
	for id in SkillDB.DEFS:
		for prop in SkillDB.DEFS[id].get("scales", {}):
			if not Classes.SCALE_RATE.has(prop) or not (SkillDB.DEFS[id]["scales"][prop] in Classes.ATTRIBUTES):
				data_ok = false
	_check("every skill scaling entry names a real property and attribute", data_ok)
	var every_element := Elements.MAIN.all(func(e): return Classes.ELEMENT_ATTRIBUTE.has(e) and Classes.ELEMENT_ATTRIBUTE[e] in Classes.ATTRIBUTES)
	_check("every element has a governing attribute", every_element)


func _test_classes() -> void:
	var playable: Array = Classes.CLASSES.keys().filter(func(id): return not Classes.CLASSES[id].get("hidden", false))
	_check("there are four playable classes", playable.size() == 4 and "ranger" in playable and "mystic" in playable)
	var totals_equal := true
	var growth_equal := true
	var refs_ok := true
	for id in playable:
		var cls: Dictionary = Classes.CLASSES[id]
		var total := 0
		for attr in Classes.ATTRIBUTES:
			total += int(cls["base"][attr])
		var growth := 0
		for attr in cls["per_level"]:
			growth += int(cls["per_level"][attr])
		totals_equal = totals_equal and total == 21
		growth_equal = growth_equal and growth == 1
		for sub in cls["subclasses"]:
			refs_ok = refs_ok and Classes.SUBCLASSES.has(sub) and Classes.SUBCLASSES[sub]["passives"].all(func(p): return Classes.PASSIVES.has(p))
		refs_ok = refs_ok and cls["passives"].all(func(p): return Classes.PASSIVES.has(p)) and Classes.WEAPON_PASSIVES.has(cls["weapon"])
	_check("balance: every playable class starts with 21 attribute points", totals_equal)
	_check("balance: every playable class gains one attribute per level", growth_equal)
	_check("classes reference real subclasses, passives and weapons", refs_ok)
	var ranger := CharacterData.create_sandbox("ranger", [], 1).derived()
	var channeler := CharacterData.create_sandbox("channeler", [], 1).derived()
	var mystic := CharacterData.create_sandbox("mystic", [], 1).derived()
	var vanguard := CharacterData.create_sandbox("vanguard", [], 1).derived()
	_check("ranger is the fastest class", ranger["move_speed"] > vanguard["move_speed"] and ranger["move_speed"] > channeler["move_speed"] and ranger["move_speed"] > mystic["move_speed"])
	_check("ranger bolts fly faster", ranger["projectile_speed_mult"] > 1.0)
	_check("mystic casts faster than channeler and is sturdier", mystic["max_hp"] > channeler["max_hp"] and CharacterData.create_sandbox("mystic", ["fire"], 2).skill_cooldown("fireball") < CharacterData.create_sandbox("wanderer", ["fire"], 2).skill_cooldown("fireball"))
	_check("each class learns the area skill at its own level", CharacterData.create_sandbox("mystic", ["fire"], 2).can_use_skill("flame_burst")
		and not CharacterData.create_sandbox("ranger", ["fire"], 3).can_use_skill("flame_burst") and CharacterData.create_sandbox("ranger", ["fire"], 4).can_use_skill("flame_burst"))
	var picks: Array = CharacterData.create_sandbox("ranger", [], 5).available_subclasses()
	_check("ranger and mystic have two subclasses each", picks == ["sharpshooter", "pathfinder"] and CharacterData.create_sandbox("mystic", [], 5).available_subclasses() == ["oracle", "spiritblade"])


func _test_ui_screens() -> void:
	var saved := Game.character
	Game.character = CharacterData.create_sandbox("channeler", ["fire", "water"], 5)
	var sheet := CharacterSheet.new()
	add_child(sheet)
	await get_tree().process_frame
	var all_tabs := true
	for tab in CharacterSheet.TABS:
		sheet.show_tab(tab)
		if sheet._content.get_child_count() == 0:
			all_tabs = false
	_check("every character sheet tab builds", all_tabs)
	sheet.show_tab("combos")
	_check("combos tab lists a header and all ten combos", sheet._content.get_child(0).get_child_count() == 11)
	var lit := sheet._content.get_child(0).get_children().filter(func(l): return l is Label and l.text.contains("Steam") and not l.text.contains("needs"))
	_check("a combo the character can trigger is not marked as missing an element", lit.size() == 1)
	var locked := sheet._content.get_child(0).get_children().filter(func(l): return l is Label and l.text.contains("Magma") and l.text.contains("needs Mineral"))
	_check("a combo needing an element they lack says which one", locked.size() == 1)
	sheet.free()

	var menu := NewCharacterMenu.new()
	add_child(menu)
	await get_tree().process_frame
	menu._build()
	var class_buttons := 0
	var birth_buttons := 0
	for button in menu.find_children("*", "Button", true, false):
		if button.button_group != null:
			if button.text in ["Channeler", "Vanguard", "Ranger", "Mystic"]:
				class_buttons += 1
			elif button.text in ["Ceremony", "No element", "Sealed"]:
				birth_buttons += 1
	_check("new character menu offers all four classes and three births", class_buttons == 4 and birth_buttons == 3)
	menu.free()
	Game.character = saved


func _test_kill_xp_and_weapon_mastery() -> void:
	_neutral_character()
	await get_tree().process_frame
	var xp_before := Game.character.xp
	var e: Enemy = SLIME.instantiate()
	e.max_hp = 5.0
	e.xp_reward = 7
	add_child(e)
	_physical(e)
	_check("killing an enemy awards its xp", Game.character.xp == xp_before + 7)
	var player: Node2D = PLAYER.instantiate()
	add_child(player)
	var target := _dummy(Vector2(15, 0))
	await get_tree().process_frame
	target.global_position = Vector2(15, 0)
	player.global_position = Vector2.ZERO
	var weapon_xp: int = Game.character.weapon_masteries[Game.character.weapon_type]["xp"]
	player.try_melee(Vector2.RIGHT)
	_check("a landed slash grants weapon mastery xp", Game.character.weapon_masteries[Game.character.weapon_type]["xp"] == weapon_xp + 1)
	player._melee_cd = 0.0
	target.global_position = Vector2(80, 0)
	player.try_melee(Vector2.RIGHT)
	_check("a slash that hits nothing grants no weapon xp", Game.character.weapon_masteries[Game.character.weapon_type]["xp"] == weapon_xp + 1)
	player.queue_free()
	target.queue_free()


func _dummy(pos := Vector2.ZERO) -> Enemy:
	var e: Enemy = SLIME.instantiate()
	e.max_hp = 1000.0
	e.position = pos
	add_child(e)
	return e


func _check(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("PASS ", test_name)
	else:
		_fail += 1
		print("FAIL ", test_name)


func _dmg(skill: String) -> float:
	return SkillDB.DEFS[skill]["damage"]


func _hit(e: Enemy, skill: String) -> void:
	var d: Dictionary = SkillDB.DEFS[skill]
	e.take_hit({"damage": d["damage"], "element": d["element"], "apply": d.get("apply", {}), "knockback": 0.0})


func _physical(e: Enemy) -> void:
	e.take_hit({"damage": SkillDB.MELEE["damage"], "element": "", "knockback": 0.0})


func _test_data_tables() -> void:
	var main: Array = Elements.MAIN
	var all_pairs := true
	for i in main.size():
		for j in range(i + 1, main.size()):
			if Elements.resolve(main[i], main[j]).is_empty():
				all_pairs = false
	_check("all 10 main-element pairs have a combo", all_pairs and Elements.COMBOS.size() == 10)
	_check("combo lookup is order independent", Elements.resolve("fire", "water") == Elements.resolve("water", "fire"))
	_check("same element has no combo", Elements.resolve("fire", "fire").is_empty())
	var kinds := ["dot", "slow", "root", "stun", "vuln"]
	var combos_ok := true
	for key in Elements.COMBOS:
		var c: Dictionary = Elements.COMBOS[key]
		if not (c["effect"] in kinds) or c["mult"] <= 1.0 or c["time"] <= 0.0:
			combos_ok = false
	_check("combo definitions are valid", combos_ok)
	var skills_ok := true
	for id in SkillDB.DEFS:
		var d: Dictionary = SkillDB.DEFS[id]
		if not (d["element"] in main or d["element"] == "") or not (d["kind"] in ["projectile", "aoe"]) or d["cooldown"] <= 0.0 or SkillDB.cost_of(d) <= 0.0:
			skills_ok = false
	_check("skill definitions are valid", skills_ok)
	var loadouts_ok := true
	for element in SkillDB.LOADOUTS:
		for slot in ["primary", "area"]:
			var id: String = SkillDB.LOADOUTS[element][slot]
			if not SkillDB.DEFS.has(id) or SkillDB.set_of(id) != element:
				loadouts_ok = false
	_check("each element has a primary and area skill of its own element", loadouts_ok)


func _test_single_hit_sets_aura() -> void:
	var e := _dummy()
	_hit(e, "fireball")
	_check("fireball sets fire aura", e.aura == "fire")
	_check("fireball applies burn", e.effects.has("dot"))
	_check("fireball deals base damage", is_equal_approx(e.hp, 1000.0 - _dmg("fireball")))
	e.queue_free()


func _test_fire_then_water_is_steam() -> void:
	var e := _dummy()
	_hit(e, "fireball")
	var before := e.hp
	_hit(e, "water_jet")
	_check("steam consumes aura", e.aura == "")
	_check("steam applies vulnerable", e.effects.has("vuln"))
	_check("steam multiplies damage x1.4", is_equal_approx(before - e.hp, _dmg("water_jet") * 1.4))
	before = e.hp
	_hit(e, "thorn_shot")
	_check("vulnerable adds 25 percent", is_equal_approx(before - e.hp, _dmg("thorn_shot") * 1.25))
	e.queue_free()


func _test_same_element_refreshes() -> void:
	var e := _dummy()
	_hit(e, "fireball")
	var before := e.hp
	_hit(e, "flame_burst")
	_check("same element keeps aura", e.aura == "fire")
	_check("same element no multiplier", is_equal_approx(before - e.hp, _dmg("flame_burst")))
	e.queue_free()


func _test_earth_then_water_roots() -> void:
	var e := _dummy()
	_hit(e, "thorn_shot")
	_hit(e, "water_jet")
	_check("earth+water roots enemy", e.is_rooted())
	_check("earth+water not stunned", not e.is_stunned())
	e.queue_free()


func _test_water_jet_slows() -> void:
	var e := _dummy()
	_hit(e, "water_jet")
	_check("water jet slows", e.effects.has("slow") and is_equal_approx(e.effects["slow"]["power"], 0.5))
	e.queue_free()


func _test_aura_expires() -> void:
	var e := _dummy()
	_hit(e, "thorn_shot")
	e.aura_time = 0.01
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("aura expires", e.aura == "")
	e.queue_free()


func _test_death_signal() -> void:
	var e: Enemy = SLIME.instantiate()
	e.max_hp = 10.0
	add_child(e)
	var fired := [false]
	e.died.connect(func(_x): fired[0] = true)
	_hit(e, "fireball")
	_check("died signal fires at 0 hp", fired[0])


func _test_health_bar_visibility() -> void:
	var e := _dummy()
	var bars := e.get_children().filter(func(c): return c is EnemyHealthBar)
	_check("enemy has a health bar from spawn", bars.size() == 1)
	_check("health bar draws above other sprites", bars.size() == 1 and bars[0].z_index > 0)
	e.queue_free()


func _test_physical_ignores_aura() -> void:
	var e := _dummy()
	_hit(e, "fireball")
	_physical(e)
	_check("physical hit keeps existing aura", e.aura == "fire")
	var clean := _dummy()
	_physical(clean)
	_check("physical hit sets no aura", clean.aura == "")
	_check("physical hit deals base damage", is_equal_approx(clean.hp, 1000.0 - SkillDB.MELEE["damage"]))
	e.queue_free()
	clean.queue_free()


func _test_shatter_bonus() -> void:
	var e := _dummy()
	_hit(e, "root_snare")  # roots
	var before := e.hp
	_physical(e)
	_check("physical vs rooted deals x1.5", is_equal_approx(before - e.hp, SkillDB.MELEE["damage"] * 1.5))
	e.queue_free()


func _test_touch_geometry() -> void:
	await get_tree().process_frame
	var player: Node2D = PLAYER.instantiate()
	add_child(player)
	var slime := _dummy()
	await get_tree().process_frame
	var spots := {
		"below": Vector2(0, 13), "above": Vector2(0, -13),
		"right": Vector2(12, 0), "left": Vector2(-12, 0),
		"diagonal": Vector2(11, 12),
	}
	for name in spots:
		slime.global_position = spots[name]
		_check("slime counts as touching from %s" % name, slime.touches(player))
	slime.global_position = Vector2(0, 22)
	_check("slime several pixels away does not touch", not slime.touches(player))
	player.queue_free()
	slime.queue_free()


func _test_contact_from_every_side() -> void:
	# Rooted slimes pressed against the player's sprite edge: they can't walk closer, so the
	# contact area itself has to cover every side.
	var sides := {
		"below": Vector2(0, 13),
		"above": Vector2(0, -13),
		"right": Vector2(12, 0),
		"left": Vector2(-12, 0),
	}
	for side in sides:
		await get_tree().process_frame
		var player: Node2D = PLAYER.instantiate()
		add_child(player)
		var slime := _dummy(sides[side])
		slime._add_effect("root", 10.0, 1.0)
		for i in 20:
			await get_tree().physics_frame
		_check("slime touching from %s damages the player" % side, player.hp < player.max_hp)
		player.queue_free()
		slime.queue_free()


func _test_hp_regen() -> void:
	await get_tree().process_frame
	var player: Node2D = PLAYER.instantiate()
	add_child(player)
	player.hp = 50.0
	player._hp_regen_delay = 0.0
	player.regen_hp(1.0)
	_check("hp regenerates as a fraction per second", is_equal_approx(player.hp, 50.0 + player.hp_regen))
	player.hp = 50.0
	player._hp_regen_delay = 1.0
	player.regen_hp(0.5)
	_check("hp regen waits during the post-hit delay", player.hp == 50.0)
	player.hp = player.max_hp - 0.1
	player._hp_regen_delay = 0.0
	player.regen_hp(5.0)
	_check("hp regen caps at max", player.hp == player.max_hp)
	player._hurt_cd = 0.0
	player._dodge_left = 0.0
	player.hp = 50.0
	player.take_damage(5.0, Vector2(10, 0))
	_check("taking damage restarts the regen delay", player._hp_regen_delay == player.hp_regen_delay)
	player.queue_free()


func _test_contact_damage() -> void:
	await get_tree().process_frame  # let earlier test nodes finish freeing
	var player: Node2D = PLAYER.instantiate()
	add_child(player)
	var slime := _dummy(Vector2.ZERO)  # exactly on top of the player
	for i in 20:
		await get_tree().physics_frame
	_check("slime damages a player standing on top of it", player.hp < player.max_hp)
	player.queue_free()
	slime.queue_free()


func _test_contact_retry_after_iframes() -> void:
	await get_tree().process_frame
	var player: Node2D = PLAYER.instantiate()
	add_child(player)
	player._dodge_dir = Vector2.ZERO
	player._dodge_left = player.dodge_time  # mid-roll: i-frames active, player stays put
	var slime := _dummy(Vector2.ZERO)
	for i in 30:
		await get_tree().physics_frame
	_check("slime hits as soon as i-frames end (cooldown not wasted)", player.hp < player.max_hp)
	player.queue_free()
	slime.queue_free()


func _test_dodge_and_cycling() -> void:
	var player: Node2D = PLAYER.instantiate()
	add_child(player)
	await get_tree().process_frame
	var before: float = player.stamina
	_check("dodge succeeds with stamina", player.try_dodge(Vector2.RIGHT))
	_check("dodge costs stamina", is_equal_approx(before - player.stamina, player.dodge_stamina_cost))
	_check("dodge grants i-frames at start", player.is_invulnerable())
	_check("cannot dodge again mid-dodge", not player.try_dodge(Vector2.RIGHT))
	player._dodge_left = 0.0
	player._dodge_cd = 0.0
	player.stamina = player.dodge_stamina_cost - 1.0
	_check("dodge needs stamina", not player.try_dodge(Vector2.RIGHT))
	player.stamina = 100.0
	player._dodge_left = player.dodge_time - player.dodge_iframes - 0.01
	player._hurt_cd = 0.0
	_check("i-frames end before the dodge does", not player.is_invulnerable())

	var caster: SkillCaster = player.caster
	_check("starts on first element", caster.selected == 0)
	caster.select_relative(1)
	_check("wheel next selects second element", caster.selected_element() == "water")
	caster.select_relative(-1)
	caster.select_relative(-1)
	_check("wheel prev wraps to last element", caster.selected_element() == "earth")
	caster.select_relative(1)
	_check("wheel next wraps to first element", caster.selected_element() == "fire")
	var changes := [0]
	caster.element_changed.connect(func(_e): changes[0] += 1)
	caster.select(0)
	_check("re-selecting current element does nothing", changes[0] == 0)
	player.queue_free()


func _test_melee() -> void:
	var player: Node2D = PLAYER.instantiate()
	add_child(player)
	var front := _dummy(Vector2(15, 0))
	var behind := _dummy(Vector2(-15, 0))
	var far := _dummy(Vector2(80, 0))
	await get_tree().process_frame
	front.global_position = Vector2(15, 0)
	behind.global_position = Vector2(-15, 0)
	far.global_position = Vector2(80, 0)
	player.global_position = Vector2.ZERO
	var stamina_before: float = player.stamina
	var ok: bool = player.try_melee(Vector2.RIGHT)
	_check("melee swing succeeds with stamina", ok)
	_check("melee hits enemy in front", is_equal_approx(front.hp, 1000.0 - SkillDB.MELEE["damage"]))
	_check("melee misses enemy behind", behind.hp == 1000.0)
	_check("melee misses enemy out of range", far.hp == 1000.0)
	_check("melee costs stamina", is_equal_approx(stamina_before - player.stamina, SkillDB.MELEE["stamina"]))
	_check("melee is on cooldown immediately after", not player.try_melee(Vector2.RIGHT))
	player.stamina = 0.0
	player._melee_cd = 0.0
	_check("melee needs stamina", not player.try_melee(Vector2.RIGHT))
	player.queue_free()
	front.queue_free()
	behind.queue_free()
	far.queue_free()
