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
	_test_progression_gates()
	_test_class_choice()
	_test_rewards()
	_test_input_bindings()
	await _test_melee_reach()
	await _test_resonance_and_chain()
	await _test_lock_and_fusion()
	await _test_styles_and_imbue()
	await _test_no_mana_and_harmony()
	await _test_special_skill()
	await _test_spin_attack()
	_test_jack_of_all_trades()
	_test_items()
	_test_inventory_and_gear_stats()
	_test_forge()
	_test_loot()
	await _test_world_loot()
	await _test_reward_cards()
	await _test_ui_screens()
	await _test_gear_screens()
	print("SELFTEST %d passed, %d failed" % [_pass, _fail])


## Neutral baseline: attributes all 5, no class growth or passives, owns Fire/Water/Earth.
func _neutral_character() -> void:
	Game.character = CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire", "water", "earth"], 1)
	# Strip the starter weapon too: the combat numbers are checked against bare stats.
	Game.character.inventory.equipped.clear()
	Game.character.inventory.changed.emit()


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
	_level_to(c, 4)
	_check("area skill is still locked at level 4", not c.can_use_skill("flame_burst"))
	_level_to(c, 5)
	_check("the area skill (Q) unlocks at level 5", c.can_use_skill("flame_burst"))
	_check("level alone does not unlock other elements", not c.can_use_skill("water_jet"))
	c.add_element("water")
	_check("gaining an element unlocks its learned skills", c.can_use_skill("water_jet") and c.can_use_skill("rain_pool"))
	_check("level never unlocks a special skill", not c.can_use_skill("inferno_ring") and not c.can_use_skill("deluge"))
	var v := CharacterData.create_sandbox("vanguard", ["fire"], 4)
	_check("every class unlocks Q at the same level", v.can_use_skill("fireball") and not v.can_use_skill("flame_burst"))
	_level_to(v, 5)
	_check("vanguard has the area skill at level 5 too", v.can_use_skill("flame_burst"))
	var all_skills_ok := true
	for element in Elements.MAIN:
		for slot in ["primary", "area", "special"]:
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
	var d: Dictionary = CharacterData.create_sandbox("wanderer", ["fire"], 1).derived()
	_check("neutral stats match the tuned combat values", is_equal_approx(d["max_hp"], 100.0) and is_equal_approx(d["hp_regen"], 0.6)
		and is_equal_approx(d["max_mana"], 100.0) and is_equal_approx(d["mana_regen"], 9.0)
		and is_equal_approx(d["max_stamina"], 100.0) and is_equal_approx(d["stamina_regen"], 30.0) and is_equal_approx(d["move_speed"], 80.0))
	var channeler: Dictionary = CharacterData.create_sandbox("channeler", ["fire"], 1).derived()
	var vanguard: Dictionary = CharacterData.create_sandbox("vanguard", ["fire"], 1).derived()
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
	var c := CharacterData.create_sandbox("channeler", ["fire"], 9)
	_check("no subclass choice before level 10", c.available_subclasses().is_empty() and not c.choose_subclass("spellweaver"))
	_level_to(c, 10)
	_check("subclasses offered at level 10", c.available_subclasses().size() == 2)
	_check("cannot pick another class's subclass", not c.choose_subclass("duelist"))
	var before := c.spell_damage_mult("fire")
	_check("can choose a subclass", c.choose_subclass("spellweaver") and c.subclass_id == "spellweaver")
	_check("subclass passive applies", c.spell_damage_mult("fire") > before)
	_check("subclass can only be chosen once", not c.choose_subclass("warden") and c.available_subclasses().is_empty())


func _test_save_round_trip() -> void:
	var c := CharacterData.create("Round", "vanguard", CharacterData.ELEMENTALIST, _rng(7))
	_level_to(c, 10)
	c.spend_point("strength")
	c.choose_subclass("bulwark")
	c.learned_specials.append("inferno_ring")
	c.add_element_xp(c.elements[0], 35)
	c.add_weapon_xp(12)
	var loaded := CharacterData.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	_check("save keeps identity, level and subclass", loaded.display_name == c.display_name and loaded.class_id == c.class_id
		and loaded.level == c.level and loaded.subclass_id == c.subclass_id and loaded.affinity == c.affinity)
	_check("save keeps xp, points and attributes as integers", loaded.xp == c.xp and loaded.unspent_points == c.unspent_points
		and loaded.attributes == c.attributes and typeof(loaded.attributes["strength"]) == TYPE_INT)
	_check("save keeps elements and mastery", loaded.elements == c.elements and loaded.element_mastery == c.element_mastery
		and loaded.weapon_masteries == c.weapon_masteries)
	_check("save keeps unclaimed rewards and learned specials", c.pending_rewards.size() > 0 and loaded.pending_rewards == c.pending_rewards
		and loaded.learned_specials == ["inferno_ring"])
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
	_check("the martial area skill is learned at level 5, like every other Q", not c.can_use_skill("whirlwind"))
	_level_to(c, 5)
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
	var c := CharacterData.create_sandbox("wanderer", ["fire"], 1)  # an element, so there is a mana pool
	var before: float = c.derived()["max_hp"]
	c.traits = ["sturdy"]
	_check("a trait applies as a passive of type trait", c.passive_sources() == [{"id": "sturdy", "type": "trait"}] and is_equal_approx(c.derived()["max_hp"], before + 12.0))
	c.traits = ["sharp_mind", "hardy_lungs"]
	_check("traits can add mana and stamina", is_equal_approx(c.derived()["max_mana"], 115.0) and is_equal_approx(c.derived()["max_stamina"], 112.0))
	var created := CharacterData.create("T", "ranger", CharacterData.SEALED, _rng(3))
	_check("created characters get at least one trait", created.traits.size() >= 1)
	var sealed_ok := true
	var attunable_gets_spell := false
	for seed_value in 200:
		var sealed := CharacterData.create("S", "vanguard", CharacterData.SEALED, _rng(seed_value))
		sealed_ok = sealed_ok and not sealed.traits.any(func(t): return t in Classes.SPELL_TRAITS)
		var attuned := CharacterData.create("A", "vanguard", CharacterData.ATTUNABLE, _rng(seed_value))
		attunable_gets_spell = attunable_gets_spell or attuned.traits.any(func(t): return t in Classes.SPELL_TRAITS)
	_check("sealed characters never roll spell-only traits (they have no mana)", sealed_ok)
	_check("attunable characters still can, since they may be attuned later", attunable_gets_spell)
	var rewards_ok := true
	var sealed_char := CharacterData.create("S", "vanguard", CharacterData.SEALED, _rng(1))
	for i in 200:
		for option in Rewards.generate(sealed_char, _rng(i)):
			rewards_ok = rewards_ok and not (option["type"] == "passive" and option["id"] in Classes.SPELL_TRAITS)
	_check("sealed characters are not offered spell-only trait rewards", rewards_ok)


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
	var playable: Array = Classes.playable()
	_check("there are four playable classes and a Novice starter", playable.size() == 4 and "ranger" in playable and "mystic" in playable
		and Classes.is_starter(Classes.NEUTRAL_CLASS) and not (Classes.NEUTRAL_CLASS in playable))
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
	var picks: Array = CharacterData.create_sandbox("ranger", [], 10).available_subclasses()
	_check("ranger and mystic have two subclasses each", picks == ["sharpshooter", "pathfinder"] and CharacterData.create_sandbox("mystic", [], 10).available_subclasses() == ["oracle", "spiritblade"])


func _test_progression_gates() -> void:
	_check("gates are class 3, area 5, subclass 10", Classes.CLASS_LEVEL == 3 and Classes.AREA_LEVEL == 5 and Classes.SUBCLASS_LEVEL == 10)
	var all_same := true
	for cls in Classes.CLASSES:
		var c := CharacterData.create_sandbox(cls, ["fire"], 4)
		var after := CharacterData.create_sandbox(cls, ["fire"], 5)
		all_same = all_same and c.can_use_skill("fireball") and not c.can_use_skill("flame_burst") and after.can_use_skill("flame_burst")
	_check("Q unlocks at level 5 for the Novice and every class", all_same)
	var sub_ok := true
	for cls in Classes.playable():
		sub_ok = sub_ok and CharacterData.create_sandbox(cls, [], 9).available_subclasses().is_empty() \
			and CharacterData.create_sandbox(cls, [], 10).available_subclasses().size() == 2
	_check("subclasses unlock at level 10 for every class", sub_ok)
	var novice := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, [], 10)
	_check("a Novice that never picked a class has no subclass to choose", novice.available_subclasses().is_empty())


func _test_class_choice() -> void:
	var c := CharacterData.create("N", Classes.NEUTRAL_CLASS, CharacterData.ELEMENTALIST, _rng(21))
	_check("everyone starts as a Novice", c.class_id == Classes.NEUTRAL_CLASS and Classes.is_starter(c.class_id))
	_level_to(c, 2)
	_check("cannot choose a class before level 3", not c.can_choose_class() and not c.choose_class("vanguard"))
	_level_to(c, 3)
	_check("a class can be chosen at level 3", c.can_choose_class())
	_check("cannot choose the Novice or an unknown class", not c.choose_class(Classes.NEUTRAL_CLASS) and not c.choose_class("paladin"))
	var chosen := []
	c.class_chosen.connect(func(id): chosen.append(id))
	for i in 3:
		c.spend_point("strength")
	_check("the player has spent points before choosing", c.attributes["strength"] == 8)
	_check("choose_class succeeds", c.choose_class("vanguard") and chosen == ["vanguard"] and c.class_id == "vanguard")
	# base 8 + 3 spent points + 1 growth for each of the 2 levels gained so far
	_check("class base, spent points and retroactive growth combine", c.attributes["strength"] == 13 and c.attributes["agility"] == 4
		and c.attributes["intellect"] == 3 and c.attributes["vitality"] == 6)
	_check("the class weapon and passives apply", c.weapon_type == "sword" and "toughened" in c.active_passives())
	_check("the class cannot be changed afterwards", not c.can_choose_class() and not c.choose_class("mystic"))
	var mage := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, [], 3)
	mage.choose_class("channeler")
	_check("a mage's intellect grows retroactively", mage.attributes["intellect"] == 9 + 2 and mage.weapon_type == "staff")
	var restored := CharacterData.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	_check("a chosen class survives saving", restored.class_id == "vanguard" and restored.attributes == c.attributes)


func _test_rewards() -> void:
	var levels := []
	for lv in range(1, 31):
		if Rewards.is_reward_level(lv):
			levels.append(lv)
	_check("reward levels are every even level except 10", levels == [2, 4, 6, 8, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30])
	var counts := {}
	var valid := true
	var c := CharacterData.create_sandbox("channeler", ["fire", "water"], 1)
	var rng := _rng(99)
	for i in 300:
		var offer := Rewards.generate(c, rng)
		counts[offer.size()] = int(counts.get(offer.size(), 0)) + 1
		var seen := []
		for option in offer:
			var key := "%s:%s" % [option["type"], option["id"]]
			valid = valid and not (key in seen) and (option["type"] in ["skill", "passive"])
			seen.append(key)
			if option["type"] == "skill":
				valid = valid and SkillDB.slot_of(option["id"]) == "special" and (SkillDB.set_of(option["id"]) in ["fire", "water"])
			else:
				valid = valid and Classes.TRAITS.has(option["id"])
	_check("offers hold 1 to 3 distinct, valid options", valid and counts.keys().all(func(n): return n >= 1 and n <= 3))
	_check("offers of every size from 1 to 3 occur", counts.has(1) and counts.has(2) and counts.has(3))
	var both := false
	for i in 100:
		var types := Rewards.generate(c, rng).map(func(o): return o["type"])
		if "skill" in types and "passive" in types:
			both = true
	_check("an offer can mix skills and passives", both)
	var no_sets := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, [], 1)
	var passive_only := Rewards.generate(no_sets, rng).all(func(o): return o["type"] == "passive")
	_check("with no element or martial set there are no skill rewards", passive_only)

	var g := CharacterData.create_sandbox("vanguard", ["fire"], 1)
	g.reward_rng.seed = 5
	var raised := []
	g.reward_ready.connect(func(lv): raised.append(lv))
	_level_to(g, 12)
	_check("each reward level queues exactly one offer", raised == [2, 4, 6, 8, 12] and g.pending_rewards.size() == 5)
	var skill_offer := -1
	var skill_option := -1
	for i in g.pending_rewards.size():
		for j in g.pending_rewards[i].size():
			if g.pending_rewards[i][j]["type"] == "skill" and skill_offer < 0:
				skill_offer = i
				skill_option = j
	if skill_offer < 0:  # force one so the claim path is always covered
		g.pending_rewards[0] = [{"type": "skill", "id": "inferno_ring"}]
		skill_offer = 0
		skill_option = 0
	var skill_id: String = g.pending_rewards[skill_offer][skill_option]["id"]
	var before := g.pending_rewards.size()
	_check("a special skill is not usable before claiming it", not g.can_use_skill(skill_id))
	_check("claiming a skill reward teaches the special", g.claim_reward(skill_offer, skill_option) and g.can_use_skill(skill_id) and skill_id in g.learned_specials)
	_check("claiming consumes that offer", g.pending_rewards.size() == before - 1)
	var passive_offer := 0
	g.pending_rewards[passive_offer] = [{"type": "passive", "id": "far_reach"}, {"type": "skill", "id": "inferno_ring"}]
	_check("claiming a passive adds a trait", g.claim_reward(passive_offer, 0) and "far_reach" in g.traits and "far_reach" in g.active_passives())
	g.pending_rewards.append([{"type": "skill", "id": "deluge"}])
	_check("cannot claim a skill for a set you don't have", not g.claim_reward(g.pending_rewards.size() - 1, 0))
	g.pending_rewards.append([{"type": "skill", "id": skill_id}])
	_check("cannot learn the same special twice", not g.claim_reward(g.pending_rewards.size() - 1, 0))
	g.pending_rewards.append([{"type": "passive", "id": "far_reach"}])
	_check("cannot take a trait you already have", not g.claim_reward(g.pending_rewards.size() - 1, 0))
	_check("bad offer or option indexes are refused", not g.claim_reward(99, 0) and not g.claim_reward(0, 99) and not g.claim_reward(-1, 0))
	var attuned := CharacterData.create_sandbox("vanguard", ["fire"], 1)
	attuned.pending_rewards.append([{"type": "skill", "id": "deluge"}])
	attuned.add_element("water")
	_check("attuning to an element makes its special claimable", attuned.claim_reward(0, 0) and attuned.can_use_skill("deluge"))
	var specials_ok := true
	for set_id in SkillDB.LOADOUTS:
		specials_ok = specials_ok and SkillDB.slot_of(SkillDB.LOADOUTS[set_id]["special"]) == "special" and SkillDB.set_of(SkillDB.LOADOUTS[set_id]["special"]) == set_id
	_check("every set has a special skill", specials_ok)


func _test_input_bindings() -> void:
	var has_key := func(action: String, key: Key) -> bool:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and (event.keycode == key or event.physical_keycode == key):
				return true
		return false
	_check("TAB opens the character sheet, not C", has_key.call("character_sheet", KEY_TAB) and not has_key.call("character_sheet", KEY_C))
	_check("E imbues the blade and R casts the special", has_key.call("imbue", KEY_E) and has_key.call("skill_special", KEY_R))
	_check("interact moved off E so it cannot clash with imbue", not has_key.call("interact", KEY_E) and has_key.call("interact", KEY_G))
	_check("Q locks elements and F casts the area skill", has_key.call("skill_lock", KEY_Q) and has_key.call("skill_area", KEY_F)
		and not has_key.call("skill_area", KEY_Q))


func _test_melee_reach() -> void:
	var saved := Game.character
	var ranges := {}
	for cls in Classes.playable():
		ranges[cls] = CharacterData.create_sandbox(cls, [], 1).derived()["melee_range_mult"]
	_check("fighters reach farther than casters", ranges["vanguard"] > ranges["mystic"] and ranges["mystic"] > ranges["ranger"]
		and ranges["ranger"] > ranges["channeler"] and ranges["channeler"] < 1.0 and ranges["vanguard"] > 1.0)
	var duelist := CharacterData.create_sandbox("vanguard", [], 10)
	duelist.choose_subclass("duelist")
	_check("a melee subclass adds reach", duelist.derived()["melee_range_mult"] > ranges["vanguard"])

	var hits := {}
	for cls in ["vanguard", "channeler"]:
		Game.character = CharacterData.create_sandbox(cls, [], 1)
		await get_tree().process_frame
		var player: Node2D = PLAYER.instantiate()
		add_child(player)
		var dummy := _dummy(Vector2(31, 0))  # past the base reach of 26, inside Vanguard's 36
		await get_tree().process_frame
		dummy.global_position = Vector2(31, 0)
		player.global_position = Vector2.ZERO
		player.try_melee(Vector2.RIGHT)
		hits[cls] = dummy.hp < dummy.max_hp
		player.queue_free()
		dummy.queue_free()
	_check("a Vanguard's slash reaches a target a Channeler's cannot", hits["vanguard"] and not hits["channeler"])
	Game.character = saved
	await get_tree().process_frame


func _player_with(character: CharacterData) -> Node2D:
	Game.character = character
	await get_tree().process_frame
	var player: Node2D = PLAYER.instantiate()
	add_child(player)
	await get_tree().process_frame
	return player


func _test_resonance_and_chain() -> void:
	var resonances_ok := true
	for element in Elements.MAIN:
		var r: Dictionary = Elements.RESONANCE.get(element, {})
		resonances_ok = resonances_ok and not r.is_empty() and float(r["mult"]) > 1.0 and r["effect"] in ["dot", "slow", "root", "stun", "vuln"]
	_check("every main element has a resonance combo", resonances_ok)

	var e := _dummy()
	_hit(e, "fireball")
	_hit(e, "fireball")
	_check("two hits of one element do not resonate yet", e.aura == "fire" and e.aura_stacks == 2)
	var before := e.hp
	_hit(e, "fireball")
	_check("the third hit of the same element triggers Blaze", e.aura == "" and e.aura_stacks == 0 and is_equal_approx(before - e.hp, _dmg("fireball") * 1.3))
	_check("resonance applies its effect", e.effects.has("dot"))
	e.queue_free()

	var pool := _dummy()
	for i in 6:
		pool.take_hit({"damage": 1.0, "element": "water", "knockback": 0.0, "juice": false})
	_check("lingering area ticks do not build resonance", pool.aura == "water" and pool.aura_stacks == 1)
	pool.queue_free()

	var mixed := _dummy()
	_hit(mixed, "fireball")
	_hit(mixed, "fireball")
	_hit(mixed, "water_jet")
	_check("a different element ends the chain with its pair combo instead", mixed.aura == "" and mixed.aura_stacks == 0 and mixed.effects.has("vuln"))
	mixed.queue_free()

	var rend := _dummy()
	_hit(rend, "thorn_shot")
	_physical(rend)
	_physical(rend)
	_check("two physical hits do not trigger Rend", rend.chain_count == 2)
	_hit(rend, "thorn_shot")
	var hp_before := rend.hp
	_physical(rend)
	_check("the third physical hit triggers Rend (x1.5, bleed)", is_equal_approx(hp_before - rend.hp, SkillDB.MELEE["damage"] * 1.5) and rend.effects.has("dot"))
	_check("an elemental hit in between does not break the chain, and Rend leaves the aura", rend.aura == "earth" and rend.chain_count == 0)
	_physical(rend)
	rend.chain_time = 0.0  # too long since the last hit
	_physical(rend)
	_check("a martial chain times out", rend.chain_count == 1)
	rend.queue_free()

	var deaths := [0]
	var prey: Enemy = SLIME.instantiate()
	prey.max_hp = 5.0
	add_child(prey)
	prey.died.connect(func(_x): deaths[0] += 1)
	var xp_before := Game.character.xp
	prey.take_hit({"damage": 50.0, "element": "fire", "knockback": 0.0})
	prey.take_hit({"damage": 50.0, "element": "water", "knockback": 0.0})
	_check("a dead enemy ignores further hits (one death, one reward)", deaths[0] == 1 and Game.character.xp == xp_before + prey.xp_reward)

	var timeout := _dummy()
	_hit(timeout, "thorn_shot")
	timeout.aura_time = 0.01
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("the aura and its resonance count expire together", timeout.aura == "" and timeout.aura_stacks == 0)
	timeout.queue_free()


func _test_lock_and_fusion() -> void:
	var saved := Game.character
	var player: Node2D = await _player_with(CharacterData.create_sandbox("channeler", ["fire", "water", "earth", "air"], 1))
	var caster: SkillCaster = player.caster
	_check("Q works with two or more elements, with no level needed", caster.lock_available() and Game.character.level == 1)
	_check("nothing locked: LMB is disabled and casts nothing", caster.lmb_mode() == "locked" and caster.primary_id() == "" and not caster.try_cast(caster.primary_id()))
	_check("Q locks the selected element", caster.toggle_lock() and caster.locked == ["fire"])
	_check("one locked element is still not enough for LMB", caster.lmb_mode() == "locked" and caster.primary_id() == "")
	caster.select(1)
	_check("a second lock makes LMB the fused cast", caster.toggle_lock() and caster.locked == ["fire", "water"])
	var fusion := caster.primary_id()
	_check("LMB is now a fusion of both", caster.lmb_mode() == "fusion" and SkillCaster.is_fusion(fusion) and fusion == "fusion:fire+water")
	caster.select(2)
	caster.toggle_lock()
	caster.select(3)
	_check("no more than three elements lock", not caster.toggle_lock() and caster.locked.size() == 3)
	caster.select(2)
	_check("Q on a locked element unlocks it", caster.toggle_lock() and caster.locked == ["fire", "water"])

	var cost := caster.costs(fusion)
	var expected_cost: float = SkillDB.DEFS["fireball"]["mana"] + SkillDB.DEFS["water_jet"]["mana"]
	_check("a fusion costs the sum of its parts", is_equal_approx(cost.x, expected_cost) and cost.y == 0.0)
	var slowest := maxf(Game.character.skill_cooldown("fireball"), Game.character.skill_cooldown("water_jet"))
	_check("a fusion waits for its slowest part plus a step", is_equal_approx(caster.cooldown_total(fusion), slowest + SkillCaster.FUSION_COOLDOWN_STEP))
	caster.mana = 3.0
	_check("a fusion needs the full mana", not caster.can_cast(fusion))
	caster.mana = caster.max_mana
	var mana_before := caster.mana
	_check("the fusion casts", caster.try_cast(fusion) and caster.cooldowns.has(fusion))
	_check("it spends the summed mana", absf((mana_before - cost.x) - caster.mana) < 1.0)
	_check("it trains every fused element", Game.character.element_mastery["fire"]["xp"] >= 1 and Game.character.element_mastery["water"]["xp"] >= 1)
	var bolts := get_children().filter(func(n): return n is Projectile)
	_check("one bolt carries a hit for each element", bolts.size() >= 1 and bolts[-1].extra_hits.size() == 1)
	var target := _dummy(Vector2(900, 900))
	await get_tree().process_frame
	var start_hp := target.hp
	bolts[-1]._on_body_entered(target)
	var expected_damage: float = Game.character.skill_damage("fireball") * SkillCaster.FUSION_DAMAGE * Game.character.derived()["fusion_damage_mult"] \
		+ Game.character.skill_damage("water_jet") * SkillCaster.FUSION_DAMAGE * Game.character.derived()["fusion_damage_mult"] * 1.4
	_check("fire then water in one bolt triggers Steam at once", target.aura == "" and target.effects.has("vuln") and is_equal_approx(start_hp - target.hp, expected_damage))
	target.queue_free()
	caster.select(0)
	caster.toggle_lock()  # unlock Fire, leaving only Water locked
	_check("dropping below two locked elements disables LMB again", caster.locked == ["water"] and caster.lmb_mode() == "locked")
	player.queue_free()

	var single: Node2D = await _player_with(CharacterData.create_sandbox("channeler", ["fire"], 5))
	_check("with one element there is nothing to fuse: Q and LMB are locked", not single.caster.lock_available() and not single.caster.toggle_lock() and single.caster.lmb_mode() == "locked")
	single.queue_free()

	var melee_sealed: Node2D = await _player_with(CharacterData.create("S", "vanguard", CharacterData.SEALED, _rng(3)))
	_check("a melee class with no elements: Q locked, LMB is a straight slash", not melee_sealed.caster.lock_available() and melee_sealed.caster.lmb_mode() == "slash" and melee_sealed.caster.primary_id() == "")
	melee_sealed.queue_free()
	var ranged_sealed: Node2D = await _player_with(CharacterData.create("S", "channeler", CharacterData.SEALED, _rng(3)))
	_check("a ranged class with no elements throws knives on LMB", ranged_sealed.caster.lmb_mode() == "knife" and not ranged_sealed.caster.lock_available())
	_check("the knife throw casts on stamina", ranged_sealed.caster.try_cast(ranged_sealed.caster.primary_id()))
	ranged_sealed.queue_free()

	var attuned: Node2D = await _player_with(CharacterData.create_sandbox("channeler", ["fire"], 5))
	Game.character.affinity = CharacterData.ATTUNABLE  # a martial set now exists beside Fire
	attuned.caster.refresh_elements()
	attuned.caster.select(1)
	_check("the martial set cannot be locked", attuned.caster.selected_element() == "martial" and not attuned.caster.toggle_lock())
	_check("on the martial set LMB is the martial attack, not the fusion lock", attuned.caster.lmb_mode() == "knife")
	attuned.queue_free()
	Game.character = saved
	await get_tree().process_frame


func _test_styles_and_imbue() -> void:
	var saved := Game.character
	var styles := {}
	for cls in Classes.CLASSES:
		styles[cls] = Classes.style_of(cls)
	_check("class styles: Vanguard melee, everyone else ranged (the Novice too)",
		styles["vanguard"] == "melee" and styles["channeler"] == "ranged" and styles["ranger"] == "ranged"
		and styles["mystic"] == "ranged" and styles[Classes.NEUTRAL_CLASS] == "ranged")

	var fighter: Node2D = await _player_with(CharacterData.create_sandbox("vanguard", ["fire", "water"], 5))
	_check("a melee class's RMB always slashes", fighter.caster.rmb_mode() == "slash")
	fighter.try_imbue()
	_check("even imbued, a melee class slashes (the slash carries the element)", fighter.imbued and fighter.caster.rmb_mode() == "slash" and fighter.caster.bolt_id() == "")
	fighter.try_imbue()
	_check("a melee class can still cast its abilities", fighter.caster.try_cast("flame_burst"))
	fighter.caster.toggle_lock()
	fighter.caster.select(1)
	fighter.caster.toggle_lock()
	_check("a melee class with elements fuses them on LMB like everyone else", fighter.caster.lmb_mode() == "fusion")
	fighter.queue_free()

	var mage: Node2D = await _player_with(CharacterData.create_sandbox("channeler", ["fire", "water"], 5))
	_check("a ranged class's RMB slashes while not imbued", not mage.imbued and mage.caster.rmb_mode() == "slash" and mage.caster.bolt_id() == "")
	_check("E turns on imbue with no upfront cost", mage.caster.mana == mage.caster.max_mana and mage.try_imbue() and mage.imbued)
	_check("imbued, RMB shoots the selected element", mage.caster.rmb_mode() == "bolt" and mage.caster.bolt_id() == "fireball")
	mage.caster.select(1)
	_check("it follows the selected element", mage.caster.bolt_id() == "water_jet")
	mage.caster.select(0)
	var mana_before: float = mage.caster.mana
	_check("the RMB bolt casts for mana", mage.caster.try_cast(mage.caster.bolt_id()) and mage.caster.mana < mana_before)
	mage.caster.cooldowns.clear()
	_check("the imbue has no cooldown and does not expire", mage.try_imbue() and not mage.imbued and mage.try_imbue() and mage.imbued and not ("imbue_left" in mage))
	mage.try_imbue()
	_check("toggling back off returns RMB to melee", mage.caster.rmb_mode() == "slash")
	mage.queue_free()

	var novice: Node2D = await _player_with(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1))
	_check("the Novice has to imbue to shoot, like a ranged class", novice.caster.rmb_mode() == "slash" and novice.try_imbue() and novice.caster.rmb_mode() == "bolt")
	novice.queue_free()
	var sealed: Node2D = await _player_with(CharacterData.create("S", "channeler", CharacterData.SEALED, _rng(2)))
	_check("a character with no element cannot imbue", not sealed.try_imbue() and not sealed.imbued and sealed.caster.rmb_mode() == "slash")
	sealed.queue_free()

	# Imbued slashes (melee class)
	var player: Node2D = await _player_with(CharacterData.create_sandbox("vanguard", ["fire", "water"], 5))
	var caster: SkillCaster = player.caster
	var target := _dummy(Vector2(12, 0))
	await get_tree().process_frame
	target.global_position = Vector2(12, 0)
	player.global_position = Vector2.ZERO
	player.try_imbue()
	var mana_start: float = caster.mana
	player.try_melee(Vector2.RIGHT)
	_check("an imbued slash marks the enemy with the selected element", target.aura == "fire" and target.effects.has("dot"))
	_check("an imbued slash costs a little mana", absf((mana_start - player.IMBUE_SWING_COST) - caster.mana) < 1.0)
	_check("imbued slashes train the element", Game.character.element_mastery["fire"]["xp"] >= 1)
	caster.select(1)
	player._melee_cd = 0.0
	var hp := target.hp
	player.try_melee(Vector2.RIGHT)
	_check("an imbued slash of a second element makes a combo with the first", target.aura == "" and target.effects.has("vuln") and hp - target.hp > 10.0)
	player.try_imbue()
	var plain := _dummy(Vector2(12, 0))
	await get_tree().process_frame
	plain.global_position = Vector2(12, 0)
	player._melee_cd = 0.0
	player.try_melee(Vector2.RIGHT)
	_check("not imbued, the slash is plain physical", plain.aura == "")
	player.try_imbue()
	caster.mana = 2.0
	var broke := _dummy(Vector2(12, 0))
	await get_tree().process_frame
	broke.global_position = Vector2(12, 0)
	player._melee_cd = 0.0
	player.try_melee(Vector2.RIGHT)
	_check("without the mana, an imbued slash falls back to plain", broke.aura == "" and caster.mana < player.IMBUE_SWING_COST)

	caster.mana = caster.max_mana
	caster.select(0)
	caster.toggle_lock()
	caster.select(1)
	caster.toggle_lock()
	_check("imbue carries every locked element", player.imbue_elements() == ["fire", "water"])
	var fused := _dummy(Vector2(12, 0))
	await get_tree().process_frame
	fused.global_position = Vector2(12, 0)
	player._melee_cd = 0.0
	var mana_fused: float = caster.mana
	player.try_melee(Vector2.RIGHT)
	_check("one fused slash lands both elements, so their combo fires", fused.aura == "" and fused.effects.has("vuln"))
	_check("each element costs mana per swing", absf((mana_fused - player.IMBUE_SWING_COST * 2.0) - caster.mana) < 1.0)

	var rooted := _dummy(Vector2(12, 0))
	var rooted_imbued := _dummy(Vector2(12, 0))
	await get_tree().process_frame
	for r in [rooted, rooted_imbued]:
		r.global_position = Vector2(12, 0)
		r._add_effect("root", 10.0, 1.0)
	caster.locked.clear()
	caster.select(0)
	player.imbued = false
	player.stamina = player.max_stamina  # the earlier slashes spent it all
	player._melee_cd = 0.0
	rooted_imbued.global_position = Vector2(500, 500)
	player.try_melee(Vector2.RIGHT)
	var plain_damage: float = rooted.max_hp - rooted.hp
	_check("a plain slash on a rooted enemy shatters", is_equal_approx(plain_damage, SkillDB.MELEE["damage"] * Game.character.derived()["melee_damage_mult"] * Enemy.SHATTER_MULT))
	rooted_imbued.global_position = Vector2(12, 0)
	rooted.global_position = Vector2(500, 500)
	caster.mana = caster.max_mana
	player.stamina = player.max_stamina
	player.try_imbue()
	player._melee_cd = 0.0
	player.try_melee(Vector2.RIGHT)
	_check("an imbued slash gives up the shatter bonus", rooted_imbued.max_hp - rooted_imbued.hp < plain_damage)
	for node in [target, plain, broke, fused, rooted, rooted_imbued, player]:
		node.queue_free()
	Game.character = saved
	await get_tree().process_frame


func _test_no_mana_and_harmony() -> void:
	var saved := Game.character
	var sealed := CharacterData.create("S", "vanguard", CharacterData.SEALED, _rng(5))
	var d := sealed.derived()
	_check("a character with no elements has no mana pool", not sealed.uses_mana() and d["max_mana"] == 0.0 and d["mana_regen"] == 0.0)
	var attunable := CharacterData.create("A", "channeler", CharacterData.ATTUNABLE, _rng(5))
	_check("so does an attunable one who has not been attuned yet", attunable.derived()["max_mana"] == 0.0)
	var player: Node2D = await _player_with(attunable)
	_check("the caster has no mana to spend", player.caster.max_mana == 0.0 and player.caster.mana == 0.0)
	Game.character.add_element("fire")
	_check("the first element brings a full mana pool", player.caster.max_mana > 0.0 and is_equal_approx(player.caster.mana, player.caster.max_mana))
	player.queue_free()
	Game.character = saved
	await get_tree().process_frame

	var one := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1)
	var two := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire", "water"], 1)
	var four := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire", "water", "earth", "air"], 1)
	_check("one element gets no harmony bonus", not (Classes.HARMONY_PASSIVE in one.active_passives()))
	var source: Dictionary = two.passive_sources().filter(func(s): return s["id"] == Classes.HARMONY_PASSIVE)[0]
	_check("every element beyond the first adds a stack", source["stacks"] == 1 and source["type"] == "element"
		and four.passive_sources().filter(func(s): return s["id"] == Classes.HARMONY_PASSIVE)[0]["stacks"] == 3)
	_check("each stack adds 4 percent spell damage", is_equal_approx(two.spell_damage_mult("fire") / one.spell_damage_mult("fire"), 1.04)
		and is_equal_approx(four.spell_damage_mult("fire") / one.spell_damage_mult("fire"), pow(1.04, 3)))
	_check("each stack adds 10 max mana", is_equal_approx(two.derived()["max_mana"] - one.derived()["max_mana"], 10.0)
		and is_equal_approx(four.derived()["max_mana"] - one.derived()["max_mana"], 30.0))
	_check("each stack adds 6 percent fused damage", is_equal_approx(one.derived()["fusion_damage_mult"], 1.0)
		and is_equal_approx(four.derived()["fusion_damage_mult"], pow(1.06, 3)))
	var reloaded := CharacterData.from_dict(JSON.parse_string(JSON.stringify(four.to_dict())))
	_check("harmony survives saving", reloaded.derived() == four.derived())


func _test_special_skill() -> void:
	var saved := Game.character
	var player: Node2D = await _player_with(CharacterData.create_sandbox("mystic", ["fire", "water"], 1))
	var caster: SkillCaster = player.caster
	_check("a special cannot be cast before it is earned", not caster.try_cast("inferno_ring"))
	Game.character.learned_specials.append("inferno_ring")
	var mana_before: float = caster.mana
	_check("an earned special casts on R", caster.skill_for("special") == "inferno_ring" and caster.try_cast("inferno_ring"))
	_check("the special spends its mana", absf((mana_before - float(SkillDB.DEFS["inferno_ring"]["mana"])) - caster.mana) < 1.0)
	player.queue_free()
	Game.character = saved
	await get_tree().process_frame


func _test_spin_attack() -> void:
	var saved := Game.character
	var player: Node2D = await _player_with(_bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1)))
	var front := _dummy(Vector2(15, 0))
	var behind := _dummy(Vector2(-15, 0))
	var far := _dummy(Vector2(80, 0))
	await get_tree().process_frame
	front.global_position = Vector2(15, 0)
	behind.global_position = Vector2(-15, 0)
	far.global_position = Vector2(80, 0)
	player.global_position = Vector2.ZERO
	_check("you cannot spin without dodging", not player.try_spin())
	_check("a dodge starts", player.try_dodge(Vector2.RIGHT))
	var stamina_before: float = player.stamina
	_check("attacking mid-dodge spins", player.try_spin())
	_check("a spin costs more stamina than a slash", is_equal_approx(stamina_before - player.stamina, SkillDB.MELEE["stamina"] * player.SPIN_STAMINA_MULT) and player.SPIN_STAMINA_MULT > 1.0)
	_check("the spin hits every direction", front.hp < front.max_hp and behind.hp < behind.max_hp)
	_check("the spin respects the reach", far.hp == far.max_hp)
	_check("the spin hits harder than a slash", is_equal_approx(front.max_hp - front.hp, SkillDB.MELEE["damage"] * player.SPIN_DAMAGE_MULT))
	_check("only one spin per dodge", not player.try_spin())
	_check("a spin makes you immune until it finishes", player.is_spinning() and is_equal_approx(player._spin_left, player.SPIN_DURATION))
	player._dodge_left = 0.0  # the dodge itself is over, but the spin is still going
	player._hurt_cd = 0.0
	var hp_before_hit: float = player.hp
	_check("immune to damage mid-spin even after the dodge ends", player.is_invulnerable() and not player.take_damage(10.0, Vector2(40, 0)) and player.hp == hp_before_hit)
	player._spin_left = 0.04
	for i in 6:
		await get_tree().physics_frame
	_check("the spin ends and immunity with it", not player.is_spinning() and not player.is_invulnerable() and player.take_damage(5.0, Vector2(40, 0)))
	player._dodge_left = 0.0
	player._dodge_cd = 0.0
	player.try_dodge(Vector2.RIGHT)
	player.stamina = 10.0
	_check("a spin needs the stamina for it", not player.try_spin())
	player.stamina = player.max_stamina
	player._dodge_left = 0.0
	player._dodge_cd = 0.0
	player.try_dodge(Vector2.RIGHT)
	player.try_imbue()
	var mana_before: float = player.caster.mana
	var imbued_hit := _dummy(Vector2(-12, 0))
	await get_tree().process_frame
	imbued_hit.global_position = Vector2(-12, 0)
	player.global_position = Vector2.ZERO
	player.try_spin()
	_check("an imbued spin carries the element all around", imbued_hit.aura == "fire" and player.caster.mana < mana_before)
	for node in [front, behind, far, imbued_hit, player]:
		node.queue_free()
	Game.character = saved
	await get_tree().process_frame


func _test_jack_of_all_trades() -> void:
	var c := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1)
	var before := c.derived()
	var spell := c.spell_damage_mult("fire")
	c.traits = ["jack_of_all_trades"]
	var after := c.derived()
	_check("the trait exists and is rollable", "jack_of_all_trades" in Classes.TRAITS and Classes.passive_info("jack_of_all_trades")["name"] == "Jack of All Trades")
	_check("it is a character trait", c.passive_sources() == [{"id": "jack_of_all_trades", "type": "trait"}])
	_check("it raises every pool a little", after["max_hp"] > before["max_hp"] and after["max_mana"] > before["max_mana"]
		and after["max_stamina"] > before["max_stamina"] and after["move_speed"] > before["move_speed"])
	_check("it improves damage and defence a little", after["melee_damage_mult"] > before["melee_damage_mult"] and c.spell_damage_mult("fire") > spell
		and after["damage_taken_mult"] < before["damage_taken_mult"])
	var seen := false
	var rng := _rng(8)
	var plain := CharacterData.create_sandbox("channeler", ["fire"], 1)
	for i in 400:
		if Rewards.generate(plain, rng).any(func(o): return o["id"] == "jack_of_all_trades"):
			seen = true
	_check("it can be offered as a level reward", seen)


func _test_reward_cards() -> void:
	var saved := Game.character
	Game.character = CharacterData.create_sandbox("channeler", ["fire"], 1)  # no offers yet, so the popup stays closed
	var cards := RewardCards.new()
	add_child(cards)
	await get_tree().process_frame
	var ch := Game.character
	ch.pending_rewards.append([{"type": "skill", "id": "inferno_ring"}, {"type": "passive", "id": "sturdy"}, {"type": "passive", "id": "far_reach"}])
	ch.pending_rewards.append([{"type": "passive", "id": "focused"}])
	cards._build()
	await get_tree().process_frame
	var choose := cards.find_children("*", "Button", true, false)
	_check("one card per option of the first offer", choose.size() == 3)
	var text := " ".join(cards.find_children("*", "Label", true, false).map(func(l): return l.text))
	_check("cards name the reward and its kind", text.contains("Inferno Ring") and text.contains("Sturdy") and text.contains("SKILL") and text.contains("PASSIVE"))
	_check("the footer says more offers wait", text.contains("1 more waiting"))
	cards._choose(1)
	_check("choosing a card claims that option", "sturdy" in ch.traits and ch.pending_rewards.size() == 1)
	await get_tree().process_frame
	_check("the next waiting offer is shown", cards.find_children("*", "Button", true, false).size() == 1)
	cards._choose(0)
	_check("claiming the last offer closes the popup", ch.pending_rewards.is_empty() and not cards._open)
	cards.free()
	Game.character = saved
	await get_tree().process_frame


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
	_check("every character sheet tab builds", all_tabs and CharacterSheet.TABS.has("rewards"))

	# Nothing may spill off the game screen, whatever a tab holds: stress it with many offers.
	var view := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	var ui_character := Game.character
	var stress := CharacterData.create_sandbox("channeler", Elements.MAIN, 10)
	for i in 8:
		stress.pending_rewards.append([{"type": "passive", "id": "sturdy"}, {"type": "passive", "id": "focused"}, {"type": "skill", "id": "inferno_ring"}])
	Game.character = stress
	var fits := true
	var widths_ok := true
	for tab in CharacterSheet.TABS:
		sheet.show_tab(tab)
		await get_tree().process_frame
		var panel: Control = sheet.get_child(sheet.get_child_count() - 1)
		var rect := panel.get_global_rect()
		fits = fits and rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= view.x and rect.end.y <= view.y
		var widths := []
		for column in sheet._content.get_children():
			widths.append(column.custom_minimum_size.x)
		widths_ok = widths_ok and CharacterSheet.tab_width(widths) <= CharacterSheet.CONTENT_WIDTH
	_check("every tab stays inside the game screen, even stuffed with content", fits)
	_check("every tab's columns fit the scroll area", widths_ok)
	Game.character = ui_character
	var reward_char := CharacterData.create_sandbox("channeler", ["fire"], 4)
	Game.character = reward_char
	var options := 0
	for offer in reward_char.pending_rewards:
		options += offer.size()
	sheet.show_tab("rewards")
	await get_tree().process_frame  # the previous tab's nodes are freed at end of frame
	var option_buttons := sheet.find_children("*", "Button", true, false).filter(func(b): return b.text.begins_with("Skill (") or b.text.begins_with("Passive:"))
	_check("the rewards tab shows one button per option", reward_char.pending_rewards.size() == 2 and option_buttons.size() == options)
	var offers_before := reward_char.pending_rewards.size()
	sheet._claim(0, 0)
	_check("claiming from the sheet uses up an offer", reward_char.pending_rewards.size() == offers_before - 1)
	await get_tree().process_frame  # let the sheet's deferred rebuild of this tab run first
	var novice := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 3)
	Game.character = novice
	sheet.show_tab("stats")
	await get_tree().process_frame
	var class_choice_buttons := sheet.find_children("*", "Button", true, false).filter(func(b): return b.text in ["Channeler", "Vanguard", "Ranger", "Mystic"])
	_check("a level 3 Novice is offered the four classes on the stats tab", class_choice_buttons.size() == 4)
	sheet._choose_class("ranger")
	_check("choosing a class from the sheet applies it", novice.class_id == "ranger")
	Game.character = CharacterData.create_sandbox("channeler", ["fire", "water"], 5)
	sheet.show_tab("combos")
	var combo_rows := sheet._content.get_child(0).get_children().filter(func(l): return l is Label and l.text.contains(" + ") and l.text.contains(" = "))
	_check("combos tab lists all ten element combos", combo_rows.size() == 10)
	var all_text := " ".join(sheet._content.get_child(0).get_children().filter(func(l): return l is Label).map(func(l): return l.text))
	_check("combos tab also lists resonance and the martial combo", all_text.contains("Resonance") and all_text.contains("Blaze") and all_text.contains("Rend"))
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


# ---------- Phase 4: items, loot, crafting ----------

## The character with no gear on, so combat numbers can be checked against bare stats.
func _bare(character: CharacterData) -> CharacterData:
	character.inventory.equipped.clear()
	character.inventory.changed.emit()
	return character


func _item(base: String, rarity: String = "common", ilvl: int = 1, seed_value: int = 1) -> Dictionary:
	return Items.make(base, rarity, ilvl, _rng(seed_value))


func _test_items() -> void:
	var valid := true
	for id in Items.BASES:
		var base: Dictionary = Items.BASES[id]
		valid = valid and base["slot"] in Items.SLOTS and not base["mods"].is_empty()
		for key in base["mods"]:
			valid = valid and Items.MOD_NAMES.has(key) and (String(key).ends_with("_add") or String(key).ends_with("_mult"))
		if base["slot"] == "weapon":
			valid = valid and Classes.WEAPON_PASSIVES.has(base["weapon"])
		for cost_id in base.get("craft", {}):
			valid = valid and (cost_id == "gold" or Items.MATERIALS.has(cost_id))
	_check("every gear base has a slot, valid stats and known craft materials", valid)
	var starters := true
	for cls in Classes.CLASSES:
		starters = starters and Items.starter_for(Classes.CLASSES[cls]["weapon"]) != ""
	_check("every class weapon type has a starter weapon", starters)
	var mods_ok := true
	for affix in Items.AFFIXES:
		mods_ok = mods_ok and Items.MOD_NAMES.has(affix["mod"]) and float(affix["min"]) < float(affix["max"])
	_check("every affix names a real stat and a valid range", mods_ok)
	var enchants_ok := true
	for element in Items.ENCHANTS:
		enchants_ok = enchants_ok and Items.MATERIALS.has(Items.essence_of(element)) and Elements.MAIN.has(element)
	_check("every enchant has an essence material", enchants_ok)
	_check("gear is never a starter", Items.gear_bases().all(func(id): return not Items.BASES[id].get("starter", false)))

	var counts_ok := true
	var distinct := true
	var in_range := true
	for rarity in Items.RARITIES:
		for seed_value in 30:
			var item := _item("iron_helm", rarity, 1, seed_value)
			counts_ok = counts_ok and item["affixes"].size() == Items.RARITY[rarity]["affixes"]
			var seen: Array = []
			for affix in item["affixes"]:
				distinct = distinct and not (affix["mod"] in seen)
				seen.append(affix["mod"])
				var def := Items.affix_def(affix["mod"])
				in_range = in_range and float(affix["value"]) >= float(def["min"]) - 0.01 and float(affix["value"]) <= float(def["max"]) + 0.01
	_check("rarity decides how many affixes an item has (0 to 4)", counts_ok)
	_check("an item never rolls the same affix twice", distinct)
	_check("affix values stay inside their range", in_range)
	_check("the same seed makes the same item", _item("iron_sword", "epic", 5, 9) == _item("iron_sword", "epic", 5, 9))
	_check("different seeds make different epics", _item("iron_sword", "epic", 5, 9) != _item("iron_sword", "epic", 5, 10))

	var plain := _item("leather_cap")
	_check("a plain item's stats are its base stats", is_equal_approx(Items.mods_of(plain)["max_hp_add"], 6.0))
	_check("higher item level means bigger stats", Items.mods_of(_item("leather_cap", "common", 6))["max_hp_add"] > 6.0)
	_check("better rarity means bigger base stats", Items.mods_of(_item("leather_cap", "legendary"))["max_hp_add"] > Items.mods_of(_item("leather_cap", "rare"))["max_hp_add"])
	var up := _item("leather_cap")
	up["plus"] = 5
	_check("each + adds 10 percent of the stats", is_equal_approx(Items.mods_of(up)["max_hp_add"], 6.0 * 1.5))
	var rolled := _item("leather_cap", "uncommon", 1, 4)
	var total := float(Items.mods_of(rolled).get("max_hp_add", 0.0))
	var affix_hp := 0.0
	for affix in rolled["affixes"]:
		if affix["mod"] == "max_hp_add":
			affix_hp += float(affix["value"])
	_check("an item's stats are its base (by rarity) plus its affixes", is_equal_approx(total, 6.0 * 1.15 + affix_hp))
	var enchanted := _item("leather_cap")
	enchanted["enchant"] = "fire"
	_check("an enchant adds its stats", is_equal_approx(Items.mods_of(enchanted)["melee_damage_mult"], 0.06) and is_equal_approx(Items.mods_of(enchanted)["burn_time_mult"], 0.2))
	_check("mods read as +12 Max HP / +8% Melee damage / -3% Damage taken", Items.format_mod("max_hp_add", 12.0) == "+12 Max HP" and Items.format_mod("melee_damage_mult", 0.08) == "+8% Melee damage" and Items.format_mod("damage_taken_mult", -0.03) == "-3% Damage taken")
	_check("a fractional stat keeps a decimal", Items.format_mod("hp_regen_add", 0.3) == "+0.3 HP regen")
	var named := _item("iron_sword", "rare", 3, 2)
	_check("a rare item is named with a prefix and a suffix", Items.display_name(named).contains("Iron Sword") and Items.display_name(named).split(" ").size() >= 4)
	named["plus"] = 3
	_check("the name shows the upgrade level", Items.display_name(named).ends_with("+3"))
	_check("the description lists the stats, rarity and upgrade", Items.describe(named).contains("Rare") and Items.describe(named).contains("Upgrade +3/10") and Items.describe(named).contains("Sword"))

	var spell_free := true
	for seed_value in 200:
		var item := Items.make("iron_helm", "legendary", 4, _rng(seed_value), false)
		for affix in item["affixes"]:
			spell_free = spell_free and not (affix["mod"] in Items.SPELL_MODS)
	_check("characters who can't use spells never roll spell affixes", spell_free)
	_check("and are never dropped spell-only gear", not Items.droppable_bases("", 9, false).any(func(id): return Items.is_spell_only(id)))
	_check("staffs and robes are spell-only, swords are not", Items.is_spell_only("oak_staff") and Items.is_spell_only("mage_robe") and not Items.is_spell_only("iron_sword"))
	_check("high-level bases wait for their item level", not Items.droppable_bases("weapon", 1, true).has("iron_sword") and Items.droppable_bases("weapon", 2, true).has("iron_sword"))

	var common := _item("iron_sword")
	var epic := _item("iron_sword", "epic")
	_check("rarer items are worth and salvage for more", Items.value_of(epic) > Items.value_of(common) and Items.salvage_yield(epic)["scrap"] > Items.salvage_yield(common)["scrap"])
	var plus3 := _item("iron_sword")
	plus3["plus"] = 3
	_check("upgrading raises the salvage yield", Items.salvage_yield(plus3)["scrap"] == Items.salvage_yield(common)["scrap"] + 3)


func _test_inventory_and_gear_stats() -> void:
	var inv := Inventory.new()
	_check("a new inventory is empty", inv.gold == 0 and inv.bag.is_empty() and inv.equipped.is_empty() and inv.mods().is_empty())
	var sword := _item("iron_sword")
	var cap := _item("leather_cap")
	inv.add_item(sword)
	inv.add_item(cap)
	_check("equipping moves an item from the bag to its slot", inv.equip(0) and inv.equipped["weapon"] == sword and inv.bag.size() == 1)
	var other := _item("hunter_bow")
	inv.add_item(other)
	_check("equipping over a worn item puts the old one back in the bag", inv.equip(inv.bag.size() - 1) and inv.equipped["weapon"] == other and inv.bag.has(sword))
	_check("a bad bag index is refused", not inv.equip(99) and not inv.equip(-1))
	_check("taking an item off returns it to the bag", inv.unequip("weapon") and not inv.equipped.has("weapon") and inv.bag.has(other))
	_check("an empty slot can't be unequipped", not inv.unequip("ring"))

	var full := Inventory.new()
	for i in Inventory.BAG_SIZE:
		full.add_item(_item("copper_ring"))
	_check("the bag holds a fixed number of items", full.bag_full() and not full.add_item(_item("copper_ring")))
	full.equipped["ring"] = _item("silver_ring")
	_check("taking off needs a free bag slot", not full.unequip("ring") and full.equipped.has("ring"))

	var wallet := Inventory.new()
	wallet.add_gold(50)
	wallet.add_material("scrap", 3)
	_check("gold and materials are counted", wallet.gold == 50 and wallet.count("scrap") == 3 and wallet.count("slime_gel") == 0)
	_check("a cost that can't be paid takes nothing", not wallet.pay({"gold": 10, "scrap": 5}) and wallet.gold == 50 and wallet.count("scrap") == 3)
	_check("a cost that can be paid is taken", wallet.pay({"gold": 10, "scrap": 2}) and wallet.gold == 40 and wallet.count("scrap") == 1)
	_check("the shortfall names what is missing", wallet.shortfall({"scrap": 4}) == "Need 4 Scrap" and wallet.shortfall({"gold": 99}) == "Need 99 gold" and wallet.shortfall({"gold": 1}) == "")

	var worn := Inventory.new()
	worn.equipped["feet"] = _item("travel_boots")
	worn.equipped["ring"] = _item("silver_ring")
	var mods := worn.mods()
	_check("bonus fractions become multipliers (1 + sum)", is_equal_approx(mods["move_speed_mult"], 1.04) and is_equal_approx(mods["melee_damage_mult"], 1.03))
	var two := Inventory.new()
	two.equipped["feet"] = _item("travel_boots")
	two.equipped["ring"] = _item("travel_boots")
	_check("the same stat on two items adds up", is_equal_approx(two.mods()["move_speed_mult"], 1.08))
	var tank := Inventory.new()
	for slot in ["head", "body", "feet", "ring", "amulet", "weapon"]:
		var heavy := _item("iron_helm", "legendary", 30)
		heavy["affixes"] = [{"mod": "damage_taken_mult", "value": -0.2}]
		tank.equipped[slot] = heavy
	_check("stacked damage reduction can never reach zero", tank.mods()["damage_taken_mult"] >= 0.4)

	# Gear feeds the character's stats.
	_neutral_character()
	var ch := Game.character
	var hp_before: float = ch.derived()["max_hp"]
	var melee_before: float = ch.derived()["melee_damage_mult"]
	ch.inventory.add_item(_item("leather_cap"))
	ch.inventory.equip(0)
	_check("equipped gear raises derived stats", is_equal_approx(ch.derived()["max_hp"], hp_before + 6.0))
	ch.inventory.add_item(_item("iron_sword"))
	ch.inventory.equip(0)
	_check("a weapon raises melee damage", is_equal_approx(ch.derived()["melee_damage_mult"], melee_before * 1.18))
	_check("and widens melee reach", is_equal_approx(ch.derived()["melee_range_mult"], 1.05))
	ch.inventory.unequip("head")
	_check("taking gear off removes its stats", is_equal_approx(ch.derived()["max_hp"], hp_before))
	var signalled := [false]
	ch.changed.connect(func(): signalled[0] = true, CONNECT_ONE_SHOT)
	ch.inventory.unequip("weapon")
	_check("changing gear tells the rest of the game (stats refresh)", signalled[0])
	ch.traits.append("keen_edge")
	ch.inventory.add_item(_item("iron_sword"))
	ch.inventory.equip(ch.inventory.bag.size() - 1)
	_check("gear multipliers stack with passives", is_equal_approx(ch.stat_mods()["melee_damage_mult"], 1.06 * 1.18))
	ch.traits.erase("keen_edge")
	ch.inventory.add_item(_item("iron_helm"))
	ch.inventory.equip(ch.inventory.bag.size() - 1)
	_check("armour reduces damage taken", ch.derived()["damage_taken_mult"] < 1.0)

	# The wielded weapon decides the weapon type and which mastery grows.
	_neutral_character()
	ch = Game.character
	_check("with no weapon the class's own type applies", ch.weapon_type == "sword")
	ch.inventory.add_item(_item("worn_staff"))
	ch.inventory.equip(0)
	_check("wielding a staff makes you a staff user", ch.weapon_type == "staff" and ch.weapon_masteries.has("staff"))
	ch.add_weapon_xp(20)
	_check("the wielded weapon's mastery grows, not the old one's", ch.weapon_level() == 2 and ch.weapon_masteries["sword"]["level"] == 1)
	ch.inventory.unequip("weapon")
	_check("taking the weapon off returns to the class's own type", ch.weapon_type == "sword")
	ch.inventory.equip(0)
	_check("swapping back keeps the earlier mastery", ch.weapon_type == "staff" and ch.weapon_masteries["staff"]["level"] == 2)

	# Starting gear.
	var born := CharacterData.create("T", "channeler", CharacterData.ELEMENTALIST, _rng(5))
	_check("a new character holds a worn weapon of their class's type", born.inventory.equipped["weapon"]["base"] == "worn_staff" and born.weapon_type == "staff")
	var novice := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 3)
	_check("the Novice starts with a worn sword", novice.inventory.equipped["weapon"]["base"] == "worn_sword")
	novice.choose_class("channeler")
	_check("choosing a class swaps the worn starter weapon for the class's own", novice.inventory.equipped["weapon"]["base"] == "worn_staff" and novice.weapon_type == "staff")
	var found := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 3)
	found.inventory.add_item(_item("iron_sword"))
	found.inventory.equip(0)
	found.choose_class("ranger")
	_check("a better weapon you found is kept when you choose a class", found.inventory.equipped["weapon"]["base"] == "iron_sword" and found.weapon_type == "sword")

	# Saving.
	var hero := CharacterData.create_sandbox("vanguard", ["fire"], 5)
	hero.inventory.gold = 321
	hero.inventory.add_material("scrap", 7)
	var epic := _item("chain_mail", "epic", 6, 11)
	epic["plus"] = 2
	epic["enchant"] = "earth"
	hero.inventory.add_item(epic)
	hero.inventory.equip(0)
	hero.inventory.add_item(_item("silver_ring", "rare", 3, 3))
	var back := CharacterData.from_dict(JSON.parse_string(JSON.stringify(hero.to_dict())))
	_check("gold, materials and the bag survive a JSON save", back.inventory.gold == 321 and typeof(back.inventory.gold) == TYPE_INT and back.inventory.count("scrap") == 7 and back.inventory.bag.size() == hero.inventory.bag.size())
	_check("equipped gear keeps its rolls, upgrades and enchant", back.inventory.equipped["body"]["plus"] == 2 and back.inventory.equipped["body"]["enchant"] == "earth" and back.inventory.equipped["body"]["affixes"] == hero.inventory.equipped["body"]["affixes"] and typeof(back.inventory.equipped["body"]["ilvl"]) == TYPE_INT)
	_check("a reloaded character has identical derived stats with gear on", back.derived() == hero.derived())
	_check("and the same weapon type", back.weapon_type == hero.weapon_type)
	var old_save := hero.to_dict()
	old_save.erase("inventory")
	_check("a save from before items existed still loads", CharacterData.from_dict(old_save).inventory != null)
	_neutral_character()


func _test_forge() -> void:
	var inv := Inventory.new()
	var poor := Forge.craft(inv, "leather_cap", 1, _rng(1))
	_check("crafting without the materials does nothing", poor.is_empty() and inv.bag.is_empty() and Forge.craft_problem(inv, "leather_cap") != "")
	_check("the problem says what is missing", Forge.craft_problem(inv, "leather_cap").begins_with("Need"))
	_check("starter gear can't be crafted", Forge.craft_problem(inv, "worn_sword") == "Can't be crafted")
	inv.gold = 100
	inv.materials = {"scrap": 10, "slime_gel": 5}
	var made := Forge.craft(inv, "leather_cap", 4, _rng(2))
	_check("crafting pays the cost and adds the item", not made.is_empty() and inv.bag.size() == 1 and inv.gold == 85 and inv.count("scrap") == 6 and inv.count("slime_gel") == 3)
	_check("crafted gear has the character's item level", made["ilvl"] == 4)
	var best := 0
	for seed_value in 200:
		var probe := Inventory.new()
		probe.gold = 100
		probe.materials = {"scrap": 10, "slime_gel": 5}
		var item := Forge.craft(probe, "leather_cap", 1, _rng(seed_value))
		best = maxi(best, Items.RARITIES.find(item["rarity"]))
	_check("crafted gear is never better than rare, but can be", best == 2)
	var full := Inventory.new()
	full.gold = 100
	full.materials = {"scrap": 10, "slime_gel": 5}
	for i in Inventory.BAG_SIZE:
		full.add_item(_item("copper_ring"))
	_check("crafting needs room in the bag", Forge.craft_problem(full, "leather_cap") == "Bag full" and Forge.craft(full, "leather_cap", 1, _rng(1)).is_empty() and full.gold == 100)

	# Upgrading.
	var up := Inventory.new()
	var sword := _item("iron_sword")
	up.gold = 100000
	up.materials = {"scrap": 1000}
	var base_damage: float = Items.mods_of(sword)["melee_damage_mult"]
	var cost := Forge.upgrade_cost(sword)
	_check("upgrading pays gold and scrap and adds a level", Forge.upgrade(up, sword) and sword["plus"] == 1 and up.gold == 100000 - int(cost["gold"]) and up.count("scrap") == 1000 - int(cost["scrap"]))
	_check("each + makes the item stronger", is_equal_approx(Items.mods_of(sword)["melee_damage_mult"], base_damage * 1.1))
	_check("later upgrades cost more", int(Forge.upgrade_cost(sword)["gold"]) > int(cost["gold"]) and int(Forge.upgrade_cost(sword)["scrap"]) > int(cost["scrap"]))
	_check("better rarities cost more to upgrade", int(Forge.upgrade_cost(_item("iron_sword", "legendary"))["gold"]) > int(Forge.upgrade_cost(_item("iron_sword"))["gold"]))
	while sword["plus"] < Items.MAX_PLUS:
		Forge.upgrade(up, sword)
	_check("an item stops at +10", sword["plus"] == Items.MAX_PLUS and not Forge.upgrade(up, sword) and Forge.upgrade_problem(up, sword) == "Fully upgraded")
	var broke := Inventory.new()
	var plain := _item("iron_sword")
	_check("upgrading needs the funds", not Forge.upgrade(broke, plain) and plain["plus"] == 0)

	# Enchanting.
	var ench := Inventory.new()
	var cap := _item("leather_cap")
	_check("enchanting needs the element's essence", not Forge.enchant(ench, cap, "fire") and cap["enchant"] == "")
	ench.gold = 200
	ench.materials = {"essence_fire": 1, "essence_water": 2}
	_check("enchanting spends the essence and the gold", Forge.enchant(ench, cap, "fire") and cap["enchant"] == "fire" and ench.count("essence_fire") == 0 and ench.gold < 200)
	_check("the same enchant twice is refused", Forge.enchant_problem(ench, cap, "fire") == "Already enchanted")
	_check("a new enchant replaces the old one", Forge.enchant(ench, cap, "water") and cap["enchant"] == "water" and not Items.mods_of(cap).has("burn_time_mult"))
	_check("only main elements can be enchanted", Forge.enchant_problem(ench, cap, "light") == "Unknown element")
	_check("higher item levels need more essence", int(Forge.enchant_cost(_item("leather_cap", "common", 20), "fire")["essence_fire"]) > int(Forge.enchant_cost(cap, "fire")["essence_fire"]))

	# Upgrading or enchanting worn gear changes the character live.
	_neutral_character()
	var ch := Game.character
	ch.inventory.gold = 500
	ch.inventory.materials = {"scrap": 20, "essence_earth": 3}
	ch.inventory.add_item(_item("leather_cap"))
	ch.inventory.equip(0)
	var hp_worn: float = ch.derived()["max_hp"]
	Forge.upgrade(ch.inventory, ch.inventory.equipped["head"])
	_check("upgrading worn gear raises the character's stats at once", is_equal_approx(ch.derived()["max_hp"], hp_worn + 0.6))
	var hp_up: float = ch.derived()["max_hp"]
	Forge.enchant(ch.inventory, ch.inventory.equipped["head"], "earth")
	_check("so does enchanting it", is_equal_approx(ch.derived()["max_hp"], hp_up + 8.0 * 1.1))

	# Salvage.
	var yard := Inventory.new()
	var scrapped := _item("iron_sword", "rare", 3)
	yard.add_item(scrapped)
	var expected := Items.salvage_yield(scrapped)
	var gain := Forge.salvage(yard, 0)
	_check("salvaging removes the item and pays scrap and gold", yard.bag.is_empty() and gain == expected and yard.count("scrap") == expected["scrap"] and yard.gold == expected["gold"])
	_check("salvaging nothing does nothing", Forge.salvage(yard, 0).is_empty())
	yard.equipped["weapon"] = _item("iron_sword")
	_check("worn gear can't be salvaged", Forge.salvage(yard, 0).is_empty() and yard.equipped.has("weapon"))
	_neutral_character()


func _test_loot() -> void:
	var w0 := Loot.rarity_weights(0.0)
	var w1 := Loot.rarity_weights(1.0)
	_check("without luck the weights are the base weights", w0["common"] == 60.0 and w0["legendary"] == 0.5)
	_check("luck leaves common alone and boosts every better tier more", w1["common"] == 60.0 and w1["rare"] > w0["rare"] and w1["legendary"] / w0["legendary"] > w1["rare"] / w0["rare"])
	_check("a rarity floor drops the lower tiers", not Loot.rarity_weights(0.0, "rare").has("common") and not Loot.rarity_weights(0.0, "rare").has("uncommon") and Loot.rarity_weights(0.0, "rare").has("legendary"))
	var rng := _rng(77)
	var counts := {}
	for i in 3000:
		var r := Loot.roll_rarity(rng)
		counts[r] = int(counts.get(r, 0)) + 1
	_check("common drops most, then uncommon, and legendaries are rare", counts["common"] > counts["uncommon"] and counts["uncommon"] > counts["rare"] and counts["rare"] > int(counts.get("legendary", 0)) and counts["common"] > 1500)
	var lucky := _rng(77)
	var lucky_rare := 0
	for i in 3000:
		if Items.RARITIES.find(Loot.roll_rarity(lucky, 2.0)) >= 2:
			lucky_rare += 1
	_check("luck gives noticeably more rare-or-better drops", lucky_rare > int(counts["rare"]) + int(counts.get("epic", 0)) + int(counts.get("legendary", 0)))
	_check("a floor is respected", Loot.roll_rarity(_rng(1), 0.0, "epic") in ["epic", "legendary"])

	var drops_rng := _rng(42)
	var gold := 0
	var gear := 0
	var fire_essence := 0
	var plain_essence := 0
	var total := 4000
	for i in total:
		for entry in Loot.enemy_drops(drops_rng, 3, 0.0, "fire"):
			if entry["kind"] == "gold":
				gold += 1
			elif entry["kind"] == "item":
				gear += 1
			elif entry["id"] == "essence_fire":
				fire_essence += 1
		for entry in Loot.enemy_drops(drops_rng, 3, 0.0, ""):
			if entry["kind"] == "material" and String(entry["id"]).begins_with("essence"):
				plain_essence += 1
	_check("about 70 percent of kills drop gold", absf(float(gold) / total - Loot.GOLD_CHANCE) < 0.04)
	_check("about 8 percent drop gear", absf(float(gear) / total - Loot.GEAR_CHANCE) < 0.03)
	_check("killing with an element drops that essence about a quarter of the time", absf(float(fire_essence) / total - Loot.ESSENCE_CHANCE) < 0.04)
	_check("physical kills drop no essence", plain_essence == 0)
	_check("light and dark leave no essence (nothing to enchant yet)", Loot.enemy_drops(_rng(1), 3, 0.0, "light").all(func(e): return e["kind"] != "material" or not String(e["id"]).begins_with("essence")))
	_check("the same seed drops the same loot", Loot.enemy_drops(_rng(5), 3, 0.5, "water") == Loot.enemy_drops(_rng(5), 3, 0.5, "water"))
	var shapes_ok := true
	for i in 300:
		for entry in Loot.enemy_drops(_rng(i), 4, 0.3, "earth"):
			match entry["kind"]:
				"gold": shapes_ok = shapes_ok and int(entry["amount"]) > 0
				"material": shapes_ok = shapes_ok and Items.MATERIALS.has(entry["id"]) and int(entry["amount"]) > 0
				"item": shapes_ok = shapes_ok and Items.BASES.has(entry["item"]["base"])
				_: shapes_ok = false
	_check("every drop is valid gold, a known material or real gear", shapes_ok)
	var chest_ok := true
	for i in 100:
		var chest := Loot.chest_drops(_rng(i), 5, 0.2)
		var items := chest.filter(func(e): return e["kind"] == "item")
		chest_ok = chest_ok and items.size() == 2 and chest.any(func(e): return e["kind"] == "gold") and chest.any(func(e): return e["kind"] == "material" and e["id"] == "scrap")
		chest_ok = chest_ok and Items.RARITIES.find(items[0]["item"]["rarity"]) >= 1
	_check("a chest always holds gold, scrap and two items (the first at least uncommon)", chest_ok)
	var sealed_ok := true
	for i in 200:
		for entry in Loot.chest_drops(_rng(i), 6, 1.0, false):
			if entry["kind"] == "item":
				sealed_ok = sealed_ok and not Items.is_spell_only(entry["item"]["base"]) and entry["item"]["affixes"].all(func(a): return not (a["mod"] in Items.SPELL_MODS))
	_check("sealed characters' drops hold nothing they can't use", sealed_ok)
	_check("a slot can be asked for", Loot.roll_item(_rng(1), 5, 0.0, "ring")["base"] in Items.gear_bases("ring"))


func _test_world_loot() -> void:
	_neutral_character()
	var ch := Game.character
	Game.danger = 0
	var drops_seen: Array = []
	var listener := func(drops: Array, _pos: Vector2): drops_seen.append_array(drops)
	Game.loot_dropped.connect(listener)
	Game.loot_rng.seed = 123
	var dummy := _dummy(Vector2(200, 200))
	dummy.last_element = "fire"
	for i in 300:
		Game.on_enemy_killed(dummy)
	Game.loot_dropped.disconnect(listener)
	_check("a kill announces its drops", not drops_seen.is_empty() and drops_seen.any(func(e): return e["kind"] == "gold"))
	_check("the element that killed it decides the essence", drops_seen.any(func(e): return e["kind"] == "material" and e["id"] == "essence_fire") and not drops_seen.any(func(e): return e["kind"] == "material" and e["id"] == "essence_water"))
	_check("drops do nothing until they are picked up", ch.inventory.gold == 0 and ch.inventory.bag.is_empty())
	var fresh := _dummy(Vector2(10, 10))
	fresh.take_hit({"damage": 1.0, "element": "water", "from": Vector2.ZERO})
	fresh.take_hit({"damage": 1.0, "element": "", "from": Vector2.ZERO})
	_check("an enemy remembers the last element that hit it", fresh.last_element == "water")
	Game.danger = 6
	_check("depth raises item level and luck", Game.loot_level() == ch.level + 2 and Game.loot_bonus() > 0.5)
	Game.danger = 0
	_check("only sealed characters are denied spell gear", Game.loot_allows_spell())

	# Pickups.
	var player = await _player_with(ch)
	player.global_position = Vector2.ZERO
	var gold_drop := Pickup.spawn(self, Vector2(60, 0), {"kind": "gold", "amount": 12})
	gold_drop._age = 1.0
	gold_drop.global_position = Vector2(30, 0)
	var before := gold_drop.global_position.distance_to(player.global_position)
	gold_drop._physics_process(0.1)
	_check("loot drifts toward a nearby player", gold_drop.global_position.distance_to(player.global_position) < before)
	var far_drop := Pickup.spawn(self, Vector2(90, 0), {"kind": "gold", "amount": 1})
	far_drop._age = 1.0
	far_drop.global_position = Vector2(90, 0)
	far_drop._physics_process(0.1)
	_check("loot far away stays put", far_drop.global_position.x == 90.0)
	gold_drop.global_position = Vector2(2, 0)
	gold_drop._physics_process(0.016)
	_check("touching gold collects it", ch.inventory.gold == 12 and gold_drop.is_queued_for_deletion())
	var scrap_drop := Pickup.spawn(self, Vector2(1, 0), {"kind": "material", "id": "scrap", "amount": 2})
	scrap_drop._age = 1.0
	scrap_drop.global_position = Vector2(1, 0)
	scrap_drop._physics_process(0.016)
	_check("materials are collected too", ch.inventory.count("scrap") == 2)
	var fresh_drop := Pickup.spawn(self, Vector2(1, 0), {"kind": "gold", "amount": 5})
	fresh_drop._physics_process(0.016)
	_check("a fresh drop can't be collected until it has landed", ch.inventory.gold == 12 and not fresh_drop.is_queued_for_deletion())
	var gear_drop := Pickup.spawn(self, Vector2(1, 0), {"kind": "item", "item": _item("iron_helm", "rare", 3)})
	gear_drop._age = 1.0
	gear_drop.global_position = Vector2(1, 0)
	gear_drop._physics_process(0.016)
	_check("gear goes into the bag", ch.inventory.bag.size() == 1 and ch.inventory.bag[0]["base"] == "iron_helm")
	while not ch.inventory.bag_full():
		ch.inventory.add_item(_item("copper_ring"))
	var blocked := Pickup.spawn(self, Vector2(1, 0), {"kind": "item", "item": _item("iron_helm")})
	blocked._age = 1.0
	blocked.global_position = Vector2(1, 0)
	blocked._physics_process(0.016)
	_check("gear stays on the floor while the bag is full", ch.inventory.bag.size() == Inventory.BAG_SIZE and not blocked.is_queued_for_deletion())
	var expired := Pickup.spawn(self, Vector2(150, 150), {"kind": "gold", "amount": 1})
	expired._age = Pickup.LIFETIME
	expired._physics_process(0.016)
	_check("old loot disappears", expired.is_queued_for_deletion())

	# Chests and the forge station.
	var chest := Chest.new()
	chest.position = Vector2(5, 0)
	add_child(chest)
	await get_tree().process_frame
	var pickups_before := get_children().filter(func(n): return n is Pickup).size()
	_check("a closed chest can be used when close", chest.can_interact() and chest.is_near())
	chest.interact()
	var pickups_after := get_children().filter(func(n): return n is Pickup).size()
	_check("opening a chest spills loot", pickups_after >= pickups_before + 4)
	_check("a chest opens only once", not chest.can_interact())
	var far_chest := Chest.new()
	far_chest.position = Vector2(500, 500)
	add_child(far_chest)
	await get_tree().process_frame
	_check("a chest out of reach can't be used", not far_chest.is_near())
	var screen := ForgeScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var station := ForgeStation.new()
	station.position = Vector2(5, 0)
	add_child(station)
	await get_tree().process_frame
	station.interact()
	_check("the forge station opens the forge screen", screen.is_open())
	screen.close()
	_check("closing it unpauses the game", not get_tree().paused and not screen.is_open())
	player.queue_free()
	for node in get_children():
		if node is Pickup or node is Interactable or node is Enemy or node is ForgeScreen:
			node.queue_free()
	await get_tree().process_frame
	_neutral_character()
	await get_tree().process_frame


func _test_gear_screens() -> void:
	_check("I is bound to the gear tab", InputMap.has_action("inventory") and InputMap.action_get_events("inventory").any(func(e): return e is InputEventKey and (e.keycode == KEY_I or e.physical_keycode == KEY_I)))
	var saved := Game.character
	var ch := CharacterData.create_sandbox("vanguard", Elements.MAIN, 5)
	ch.inventory.gold = 500
	ch.inventory.materials = {"scrap": 30, "slime_gel": 10, "essence_fire": 2}
	for i in 5:
		ch.inventory.add_item(Loot.roll_item(_rng(i), 5, 1.0))
	Game.character = ch
	var sheet := CharacterSheet.new()
	add_child(sheet)
	await get_tree().process_frame
	sheet.show_tab("gear")
	await get_tree().process_frame
	var buttons := sheet._content.find_children("*", "Button", true, false)
	_check("the gear tab has a button for each worn item and each bagged item", buttons.size() == ch.inventory.equipped.size() + ch.inventory.bag.size())
	var first_bag := ch.inventory.bag[0]
	var slot := Items.slot_of(first_bag)
	var worn_before: Dictionary = ch.inventory.equipped.get(slot, {})
	sheet._equip(0)
	await get_tree().process_frame
	_check("clicking a bag item wears it", ch.inventory.equipped[slot] == first_bag)
	if not worn_before.is_empty():
		_check("what it replaced goes back in the bag", ch.inventory.bag.has(worn_before))
	sheet._unequip(slot)
	await get_tree().process_frame
	_check("clicking a worn item takes it off", not ch.inventory.equipped.has(slot))
	sheet.free()

	var forge := ForgeScreen.new()
	add_child(forge)
	await get_tree().process_frame
	var tabs_ok := true
	for tab in ForgeScreen.TABS:
		forge.show_tab(tab)
		await get_tree().process_frame
		tabs_ok = tabs_ok and forge._content.get_child_count() > 0
	_check("every forge tab builds", tabs_ok)
	forge.show_tab("craft")
	await get_tree().process_frame
	var craft_buttons := forge._content.find_children("*", "Button", true, false)
	_check("the craft tab lists every craftable base", craft_buttons.size() == Items.gear_bases().size())
	var bag_before := ch.inventory.bag.size()
	forge._craft("leather_cap")
	await get_tree().process_frame
	_check("crafting from the screen adds the item", ch.inventory.bag.size() == bag_before + 1 and forge._status.begins_with("Crafted"))
	forge.show_tab("upgrade")
	await get_tree().process_frame
	_check("the upgrade tab lists worn and bagged gear", forge._content.find_children("*", "Button", true, false).size() == ch.inventory.equipped.size() + ch.inventory.bag.size())
	var target: Dictionary = ch.inventory.bag[0]
	forge._upgrade(target)
	await get_tree().process_frame
	_check("upgrading from the screen works", target["plus"] == 1)
	forge.show_tab("enchant")
	await get_tree().process_frame
	forge._pick_enchant_target(target)  # clicked on the enchant tab, like the real thing
	await get_tree().process_frame
	_check("the enchant tab then offers each element", forge._content.find_children("*", "Button", true, false).size() == Items.ENCHANTS.size() + 1)
	forge._enchant("fire")
	await get_tree().process_frame
	_check("enchanting from the screen works and returns to the list", target["enchant"] == "fire" and forge._enchant_target.is_empty())
	forge.show_tab("salvage")
	await get_tree().process_frame
	var bag_size := ch.inventory.bag.size()
	forge._salvage(0)
	await get_tree().process_frame
	_check("salvaging from the screen works", ch.inventory.bag.size() == bag_size - 1)
	var view := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	var fits := true
	for tab in ForgeScreen.TABS:
		forge.show_tab(tab)
		await get_tree().process_frame
		var rect: Rect2 = forge.get_child(forge.get_child_count() - 1).get_global_rect()
		fits = fits and rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= view.x and rect.end.y <= view.y
	_check("every forge tab stays inside the game screen", fits)
	forge.free()
	Game.character = saved
	await get_tree().process_frame
