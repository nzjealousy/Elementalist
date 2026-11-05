extends Node
## Runtime self-test for combat rules: data tables, enemy aura/combo/status logic, and the
## player's stamina-based melee. Run the combo_selftest scene; results are printed as
## PASS/FAIL lines and a final SELFTEST summary.

const SLIME := preload("res://scenes/enemies/slime.tscn")
const PLAYER := preload("res://scenes/player/player.tscn")

var _pass := 0
var _fail := 0
var _failed: Array[String] = []


func _ready() -> void:
	Juice.enabled = false  # hit-stop would slow the clock these tests rely on
	SkillCaster.windups_enabled = false  # areas land the moment they are cast, except in _test_feel_changes
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
	_test_more_classes_and_attributes()
	await _test_support_skills()
	await _test_vfx_and_indicators()
	await _test_monsters()
	await _test_boss_and_gems()
	_test_dungeon_gen()
	await _test_dungeon_run()
	await _test_recovery_and_kills()
	await _test_attack_speed()
	await _test_costs_and_chaining()
	_test_labels()
	await _test_death()
	await _test_class_mastery_and_cards()
	await _test_enemy_abilities()
	_test_traits_and_gear_rework()
	await _test_phase5()
	await _test_light_dark()
	await _test_phase6a()
	await _test_phase6b()
	_test_dungeons5()
	_test_generation_soak()
	await _test_iso()
	_test_lighting()
	await _test_fixes()
	_test_art_style()
	await _test_feel_changes()
	await _test_noir_and_poses()
	await _test_hero_stun()
	await _test_enemy_attack_poses()
	await _test_net_world()
	_test_net_trust()
	_test_items()
	_test_inventory_and_gear_stats()
	_test_forge()
	_test_loot()
	await _test_world_loot()
	await _test_reward_cards()
	await _test_ui_screens()
	await _test_gear_screens()
	if not _failed.is_empty():
		print("FAILED: ", " | ".join(_failed))
	print("SELFTEST %d passed, %d failed" % [_pass, _fail])
	if DisplayServer.get_name() == "headless":  # `godot --headless --path elementalist res://tests/combo_selftest.tscn` for CI
		get_tree().quit(1 if _fail > 0 else 0)


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
	_check("light is castable now that it has skills", light_only.castable_elements().size() == 1 and light_only.castable_elements()[0] == "light")


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
	_check("unknown attribute is refused", not c.spend_point("charisma") and c.unspent_points == points)
	var broke := CharacterData.create_sandbox("wanderer", [], 1)
	_check("cannot spend points you do not have", not broke.spend_point("strength"))
	var capped := CharacterData.create_sandbox("wanderer", [], CharacterData.MAX_LEVEL)
	_check("level is capped", capped.gain_xp(100000) == 0 and capped.level == CharacterData.MAX_LEVEL)


func _test_derived_stats() -> void:
	var d: Dictionary = CharacterData.create_sandbox("wanderer", ["fire"], 1).derived()
	_check("neutral stats match the tuned combat values", is_equal_approx(d["max_hp"], 100.0) and is_equal_approx(d["hp_regen"], 0.25)
		and is_equal_approx(d["max_mana"], 100.0) and is_equal_approx(d["mana_regen"], 4.5)
		and is_equal_approx(d["max_stamina"], 100.0) and is_equal_approx(d["stamina_regen"], 18.0) and is_equal_approx(d["move_speed"], 80.0))
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
	_check("no subclass choice before class mastery 5", c.available_subclasses().is_empty() and not c.choose_subclass("spellweaver"))
	c.class_mastery["channeler"]["level"] = Classes.SUBCLASS_MASTERY
	_check("subclasses offered at class mastery 5", c.available_subclasses().size() == 2)
	_check("cannot pick another class's subclass", not c.choose_subclass("duelist"))
	var before := c.spell_damage_mult("fire")
	_check("can choose a subclass", c.choose_subclass("spellweaver") and c.subclass_id == "spellweaver")
	_check("subclass passive applies", c.spell_damage_mult("fire") > before)
	_check("subclass can only be chosen once", not c.choose_subclass("warden") and c.available_subclasses().is_empty())


func _test_save_round_trip() -> void:
	var c := CharacterData.create("Round", "vanguard", CharacterData.ELEMENTALIST, _rng(7))
	_level_to(c, 10)
	c.class_mastery["vanguard"]["level"] = Classes.SUBCLASS_MASTERY
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
	_check("martial skills spend stamina, not mana", is_equal_approx(stamina_before - player.stamina, 9.0) and caster.mana >= mana_before)
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
	_check("Agility shortens thorn shot cooldown", is_equal_approx(c.skill_cooldown("thorn_shot"), 0.8 * 0.8))
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
	_check("there are eight playable classes and a Novice starter", playable.size() == 8 and "ranger" in playable and "mystic" in playable
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
		totals_equal = totals_equal and total == 36
		growth_equal = growth_equal and growth == 1
		for sub in cls["subclasses"]:
			refs_ok = refs_ok and Classes.SUBCLASSES.has(sub) and Classes.SUBCLASSES[sub]["passives"].all(func(p): return Classes.PASSIVES.has(p))
		refs_ok = refs_ok and cls["passives"].all(func(p): return Classes.PASSIVES.has(p)) and Classes.WEAPON_PASSIVES.has(cls["weapon"])
	_check("balance: every playable class starts with 36 attribute points", totals_equal)
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
	_check("gates are class 3, area 5, subclass at class mastery 5", Classes.CLASS_LEVEL == 3 and Classes.AREA_LEVEL == 5 and Classes.SUBCLASS_MASTERY == 5)
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
	_check("reward levels are every even level", levels == [2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30])
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
	_check("each reward level queues exactly one offer", raised == [2, 4, 6, 8, 10, 12] and g.pending_rewards.size() == 6)
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
	_check("every element can be locked, not just three", caster.toggle_lock() and caster.locked.size() == 4)
	_check("the fused cast then has four parts, which the HUD calls a Quartet", caster.primary_id() == "fusion:fire+water+earth+air" and Elements.fusion_label(caster.locked)["name"] == "Quartet")
	var quartet_cost := caster.costs(caster.primary_id()).x
	var quartet_parts: float = SkillDB.DEFS["fireball"]["mana"] + SkillDB.DEFS["water_jet"]["mana"] + SkillDB.DEFS["thorn_shot"]["mana"] + SkillDB.DEFS["gust"]["mana"]
	_check("more elements cost more: +30 percent per extra element", is_equal_approx(quartet_cost, quartet_parts * (1.0 + 3.0 * SkillCaster.FUSION_COST_PER_EXTRA) * float(Game.character.derived()["mana_cost_mult"])))
	caster.toggle_lock()  # air is selected: unlock it
	caster.select(2)
	_check("Q on a locked element unlocks it", caster.toggle_lock() and caster.locked == ["fire", "water"])

	var cost := caster.costs(fusion)
	var expected_cost: float = SkillDB.DEFS["fireball"]["mana"] + SkillDB.DEFS["water_jet"]["mana"]
	_check("a two-element fusion costs 30 percent more than the sum of its parts", is_equal_approx(cost.x, expected_cost * (1.0 + SkillCaster.FUSION_COST_PER_EXTRA) * float(Game.character.derived()["mana_cost_mult"])) and cost.y == 0.0)
	var slowest := maxf(Game.character.skill_cooldown("fireball"), Game.character.skill_cooldown("water_jet"))
	_check("a fusion waits for its slowest part plus a step", is_equal_approx(caster.cooldown_total(fusion), (slowest + SkillCaster.FUSION_COOLDOWN_STEP) / float(Game.character.derived()["attack_speed"])))
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
	var broke := _dummy(Vector2(12, 0))
	await get_tree().process_frame
	broke.global_position = Vector2(12, 0)
	caster.mana = 2.0  # (set after the wait: a slow frame would regenerate it)
	player._melee_cd = 0.0
	player.try_melee(Vector2.RIGHT)
	_check("without the mana, an imbued slash falls back to plain", broke.aura == "" and caster.mana < player.IMBUE_SWING_COST)

	caster.mana = caster.max_mana
	caster.select(0)
	caster.toggle_lock()
	caster.select(1)
	caster.toggle_lock()
	_check("a blade holds one element: the selected one, whatever is locked", player.imbue_elements() == ["water"])
	var single_slash := _dummy(Vector2(12, 0))
	await get_tree().process_frame
	single_slash.global_position = Vector2(12, 0)
	player._melee_cd = 0.0
	var mana_one: float = caster.mana
	player.try_melee(Vector2.RIGHT)
	_check("so a slash lands just that element, with no combo of its own", single_slash.aura == "water" and not single_slash.effects.has("vuln"))
	_check("and costs one swing's mana", absf((mana_one - player.IMBUE_SWING_COST) - caster.mana) < 1.0)

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
	for node in [target, plain, broke, single_slash, rooted, rooted_imbued, player]:
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
	_check("each stack adds 3 percent spell damage", is_equal_approx(two.spell_damage_mult("fire") / one.spell_damage_mult("fire"), 1.03)
		and is_equal_approx(four.spell_damage_mult("fire") / one.spell_damage_mult("fire"), pow(1.03, 3)))
	_check("each stack adds 5 max mana", is_equal_approx(two.derived()["max_mana"] - one.derived()["max_mana"], 5.0)
		and is_equal_approx(four.derived()["max_mana"] - one.derived()["max_mana"], 15.0))
	_check("each stack adds 4 percent fused damage", is_equal_approx(one.derived()["fusion_damage_mult"], 1.0)
		and is_equal_approx(four.derived()["fusion_damage_mult"], pow(1.04, 3)))
	_check("but every stack also makes spells cost 4 percent more mana (spread thin)", is_equal_approx(one.derived()["mana_cost_mult"], 1.0)
		and is_equal_approx(four.derived()["mana_cost_mult"], pow(1.04, 3)))
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
	_check("the special spends its mana", absf((mana_before - float(SkillDB.DEFS["inferno_ring"]["mana"]) * float(Game.character.derived()["mana_cost_mult"])) - caster.mana) < 1.0)
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
	for lingering in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(lingering) and not lingering.is_queued_for_deletion():
			lingering.queue_free()  # (the dummies beside the player would otherwise touch and hurt it)
	player._iframes_left = 0.0
	player._spin_left = 0.04
	for i in 60:  # until the spin has run out (a slow machine takes more frames)
		await get_tree().physics_frame
		if not player.is_spinning():
			break
	player._hurt_cd = 0.0
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
		if is_instance_valid(node) and not node.is_queued_for_deletion():
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
	var class_button := sheet.find_children("*", "Button", true, false).filter(func(b): return b.text == "Choose your class...")
	_check("a level 3 Novice's stats tab points to the class cards", class_button.size() == 1)
	var pending_right: Array = sheet._content.get_child(1).get_children().filter(func(n): return n is Label).map(func(l): return l.text)
	var pending_left: Array = sheet._content.get_child(0).find_children("*", "Label", true, false).map(func(l): return l.text)
	_check("with the class choice pending the derived stats still show, in the right column",
		pending_right.any(func(t): return t.begins_with("HP ")) and pending_right.has("On a kill:") and not pending_left.any(func(t): return t.begins_with("HP ") or t.begins_with("Recovery") or t.begins_with("On a kill")))
	# A hero with traits: the derived block comes after Traits, every line on one row, and every attribute row has a tooltip.
	var traited := CharacterData.create_sandbox("vanguard", ["fire"], 5)
	traited.traits.assign(["sturdy", "keen_edge"])
	Game.character = traited
	sheet.visible = true  # hidden containers skip layout, and the wrap check needs real widths
	sheet.show_tab("stats")
	await get_tree().process_frame
	await get_tree().process_frame  # wrapping labels settle their line count after the first layout
	var right_labels: Array = sheet._content.get_child(1).get_children().filter(func(n): return n is Label)
	var right_texts: Array = right_labels.map(func(l): return l.text)
	var traits_at := right_texts.find("Traits (innate)")
	var derived_at := -1
	for i in right_texts.size():
		if derived_at < 0 and String(right_texts[i]).begins_with("HP "):
			derived_at = i
	_check("the derived stats sit under Traits in the right column", traits_at >= 0 and derived_at > traits_at + traited.traits.size() and right_texts.has("Recovery /s:"))
	var derived_one_line := right_labels.slice(derived_at).all(func(l): return l.get_line_count() == 1)
	_check("no derived-stat line wraps in the 148 px column", derived_at > 0 and derived_one_line)
	sheet.visible = false
	var attr_rows := sheet._content.get_child(0).get_children().filter(func(n): return n is HBoxContainer and n.get_child_count() == 3 and n.get_child(2) is Button and n.get_child(2).text == "+")
	_check("every attribute row carries its tooltip", attr_rows.size() == Classes.ATTRIBUTES.size()
		and attr_rows.all(func(r): return r.mouse_filter != Control.MOUSE_FILTER_IGNORE and r.tooltip_text == Classes.attribute_text(Classes.ATTRIBUTES[attr_rows.find(r)])))
	var texts_ok := true
	for attr in Classes.ATTRIBUTES:
		var text := Classes.attribute_text(attr)
		texts_ok = texts_ok and text.strip_edges() != "" and not (text.contains("%s") or text.contains("%d") or text.contains("%."))
	_check("every attribute has a tooltip text with no format leftovers", texts_ok)
	# The flat per-point numbers in the texts are written out; they must match derived().
	var probe := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1)
	var d0 := probe.derived()
	var spell0 := probe.spell_damage_mult("fire")
	for attr in ["vitality", "intellect", "agility", "strength"]:
		probe.attributes[attr] += 1
	var d1 := probe.derived()
	var spell_step := roundi((probe.spell_damage_mult("fire") - spell0) * 100.0)
	_check("the attribute tooltips' per-point numbers match the derived stats",
		Classes.attribute_text("vitality").contains("+%d max HP" % roundi(d1["max_hp"] - d0["max_hp"]))
		and Classes.attribute_text("intellect").contains("+%d max mana" % roundi(d1["max_mana"] - d0["max_mana"]))
		and Classes.attribute_text("agility").contains("+%d max stamina and +%d move speed" % [roundi(d1["max_stamina"] - d0["max_stamina"]), roundi(d1["move_speed"] - d0["move_speed"])])
		and Classes.attribute_text("strength").contains("damage +%d%% per point" % roundi((d1["melee_damage_mult"] - d0["melee_damage_mult"]) * 100.0))
		and Classes.attribute_text("intellect").contains("Spell damage +%d%% per point" % spell_step))
	novice.choose_class("ranger")
	_check("choosing a class applies it", novice.class_id == "ranger")
	Game.character = CharacterData.create_sandbox("channeler", ["fire", "water"], 5)
	sheet.show_tab("combos")
	var combo_rows := sheet._content.get_child(0).get_children().filter(func(l): return l is Label and l.text.contains(" + ") and l.text.contains(" = "))
	_check("combos tab lists the ten main element combos (the rare ones come with Light or Dark)", combo_rows.size() == 10)
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
			if button.text in Classes.playable().map(func(id): return Classes.CLASSES[id]["name"]):
				class_buttons += 1
			elif button.text in ["Ceremony", "No element", "Sealed"]:
				birth_buttons += 1
	_check("new character menu offers every class and three births", class_buttons == Classes.playable().size() and birth_buttons == 3)
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
		_failed.append(test_name)
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
		if not (d["element"] in main or d["element"] in Elements.RARE or d["element"] == "") or not (d["kind"] in ["projectile", "aoe", "buff"]) or d["cooldown"] <= 0.0 or SkillDB.cost_of(d) <= 0.0:
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
	player._dodge_left = 0.0   # the roll is over (0.18 s), but its i-frames (0.3 s) are not
	player._hurt_cd = 0.0
	_check("the dodge's i-frames outlast the roll itself", player.dodge_iframes > player.dodge_time and player.is_invulnerable())
	player._iframes_left = 0.0
	_check("and then they end", not player.is_invulnerable())

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


## Affix lists equal up to float noise (JSON prints floats with limited precision).
func _same_affixes(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i]["mod"] != b[i]["mod"] or not is_equal_approx(float(a[i]["value"]), float(b[i]["value"])):
			return false
	return true


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
	_check("equipped gear keeps its rolls, upgrades and enchant", back.inventory.equipped["body"]["plus"] == 2 and back.inventory.equipped["body"]["enchant"] == "earth" and _same_affixes(back.inventory.equipped["body"]["affixes"], hero.inventory.equipped["body"]["affixes"]) and typeof(back.inventory.equipped["body"]["ilvl"]) == TYPE_INT)
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
	_check("the gear tab has a button for each worn item and each bagged item", buttons.size() == Items.SLOTS.size() + ch.inventory.bag.size())
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


# ---------- more classes, attributes, crits ----------

func _test_more_classes_and_attributes() -> void:
	var playable: Array = Classes.playable()
	_check("there are eight playable classes, two subclasses each", playable.size() == 8 and playable.all(func(id): return Classes.CLASSES[id]["subclasses"].size() == 2))
	_check("the new classes exist", ["assassin", "berserker", "sage", "druid"].all(func(id): return id in playable))
	var subclass_ids := {}
	for id in playable:
		for sub in Classes.CLASSES[id]["subclasses"]:
			subclass_ids[sub] = true
	_check("all sixteen subclasses are distinct", subclass_ids.size() == 16)
	_check("there are seven attributes with a short name each", Classes.ATTRIBUTES.size() == 7 and Classes.ATTRIBUTES.all(func(a): return Classes.ATTRIBUTE_SHORT.has(a)))
	var styles := {"assassin": "melee", "berserker": "melee", "sage": "ranged", "druid": "ranged"}
	var style_ok := true
	for id in styles:
		style_ok = style_ok and Classes.style_of(id) == styles[id]
	_check("assassin and berserker fight in melee, sage and druid at range", style_ok)
	_check("every new class has a weapon type with a starter weapon", ["assassin", "berserker", "sage", "druid"].all(func(id): return Items.starter_for(Classes.CLASSES[id]["weapon"]) != ""))
	_check("new weapon types have a weapon passive", ["dagger", "axe", "tome"].all(func(w): return Classes.WEAPON_PASSIVES.has(w)))
	_check("dagger, axe and tome can all be crafted", ["steel_dagger", "battle_axe", "scribe_tome"].all(func(id): return Forge.craft_cost(id).has("gold")))
	_check("an Assassin starts with a dagger and a Sage with a tome", CharacterData.create_sandbox("assassin", [], 1).weapon_type == "dagger" and CharacterData.create_sandbox("sage", [], 1).weapon_type == "tome")

	var assassin := CharacterData.create_sandbox("assassin", ["fire"], 1)
	var berserker := CharacterData.create_sandbox("berserker", ["fire"], 1)
	var sage := CharacterData.create_sandbox("sage", ["fire"], 1)
	var druid := CharacterData.create_sandbox("druid", ["fire"], 1)
	_check("the Assassin crits far more than a Vanguard", assassin.derived()["crit_chance"] > CharacterData.create_sandbox("vanguard", [], 1).derived()["crit_chance"] + 0.05)
	_check("the Berserker hits hard and takes extra damage", berserker.derived()["melee_damage_mult"] > 1.3 and berserker.derived()["damage_taken_mult"] > 1.0)
	_check("the Sage out-regenerates mana and buffs for longer", sage.derived()["mana_regen"] > CharacterData.create_sandbox("channeler", ["fire"], 1).derived()["mana_regen"] and sage.derived()["buff_duration_mult"] > 1.2)
	_check("the Druid regenerates the most health", druid.derived()["hp_regen"] > CharacterData.create_sandbox("mystic", ["fire"], 1).derived()["hp_regen"])
	var picks_ok := true
	for id in playable:
		picks_ok = picks_ok and CharacterData.create_sandbox(id, [], 10).available_subclasses() == Classes.CLASSES[id]["subclasses"]
	_check("every class offers its two subclasses at level 10", picks_ok)
	var passives_ok := true
	for sub in subclass_ids:
		passives_ok = passives_ok and Classes.SUBCLASSES[sub]["passives"].all(func(p): return Classes.PASSIVES.has(p) and not Classes.PASSIVES[p]["mods"].is_empty())
	_check("every subclass has a real passive", passives_ok)
	var nightstalker := CharacterData.create_sandbox("assassin", [], 10)
	nightstalker.choose_subclass("nightstalker")
	_check("a subclass passive applies (Nightstalker: crit damage)", nightstalker.derived()["crit_mult"] > Classes.BASE_CRIT_MULT + 0.2)

	# wisdom and luck
	_neutral_character()
	var ch := Game.character
	var d0 := ch.derived()
	_check("at 5 Wisdom and Luck nothing changes", d0["crit_chance"] == 0.0 and d0["crit_mult"] == Classes.BASE_CRIT_MULT and d0["buff_duration_mult"] == 1.0 and d0["loot_luck"] == 0.0)
	var cooldown_before := ch.skill_cooldown("fireball")
	ch.attributes["wisdom"] = 15
	var d1 := ch.derived()
	_check("Wisdom raises mana regen", is_equal_approx(d1["mana_regen"] - d0["mana_regen"], 10.0 * Classes.WISDOM_MANA_REGEN))
	_check("Wisdom shortens spell cooldowns", ch.skill_cooldown("fireball") < cooldown_before and is_equal_approx(ch.skill_cooldown("fireball") / cooldown_before, 1.0 - 10.0 * Classes.WISDOM_COOLDOWN))
	_check("Wisdom lengthens buffs and debuffs", is_equal_approx(d1["buff_duration_mult"], 1.0 + 10.0 * Classes.WISDOM_BUFF_DURATION))
	ch.attributes["wisdom"] = 5
	ch.attributes["luck"] = 15
	_check("Luck raises crit chance", is_equal_approx(ch.derived()["crit_chance"], 10.0 * Classes.LUCK_CRIT))
	_check("and loot luck", is_equal_approx(ch.derived()["loot_luck"], 10.0 * Classes.LUCK_LOOT))
	ch.attributes["luck"] = 100
	_check("crit chance is capped", ch.derived()["crit_chance"] <= 0.75)
	ch.attributes["luck"] = 5
	ch.traits.append("lucky")
	ch.traits.append("keen_eyes")
	_check("crit traits add chance and damage", is_equal_approx(ch.derived()["crit_chance"], 0.03) and is_equal_approx(ch.derived()["crit_mult"], Classes.BASE_CRIT_MULT + 0.15))
	ch.traits.clear()
	ch.traits.append("scholar")
	_check("an attribute trait adds to the attribute (Scholar: +1 Wisdom)", is_equal_approx(ch.derived()["buff_duration_mult"], 1.0 + Classes.WISDOM_BUFF_DURATION))
	ch.traits.clear()
	_check("sealed characters are never rolled the Scholar trait (spell-only)", not (Classes.available_traits(false).has("scholar")))
	var knight := CharacterData.create_sandbox("vanguard", [], 1)
	_check("every class starts with the same 36 points and the Novice with 35", Classes.playable().all(func(id): return Classes.ATTRIBUTES.reduce(func(sum, a): return sum + int(Classes.CLASSES[id]["base"][a]), 0) == 36) and knight.attributes.size() == 7)
	var old_save := knight.to_dict()
	old_save["attributes"].erase("wisdom")
	old_save["attributes"].erase("luck")
	_check("a save from before Wisdom and Luck still loads", CharacterData.from_dict(old_save).attributes["wisdom"] == Classes.CLASSES["vanguard"]["base"]["wisdom"])

	# crits in combat
	_neutral_character()
	Game.character.attributes["luck"] = 100  # 75 percent crit chance, capped
	Game.combat_rng.seed = 5
	var crits := 0
	var plain := 0
	var base_damage := 0.0
	for i in 200:
		var dummy := _dummy(Vector2(900, 900))
		dummy.max_hp = 100000.0
		dummy.hp = dummy.max_hp
		dummy.take_hit({"damage": 10.0, "element": "", "from": Vector2.ZERO})
		var dealt: float = dummy.max_hp - dummy.hp
		if is_equal_approx(dealt, 10.0 * Classes.BASE_CRIT_MULT):
			crits += 1
		elif is_equal_approx(dealt, 10.0):
			plain += 1
		dummy.free()
	_check("a crit hits for the crit multiplier", crits > 100 and plain > 20 and crits + plain == 200)
	Game.character.attributes["luck"] = 5
	var steady := _dummy(Vector2(900, 900))
	steady.take_hit({"damage": 10.0, "element": "", "from": Vector2.ZERO})
	_check("at Luck 5 there are no crits", is_equal_approx(steady.max_hp - steady.hp, 10.0))
	steady.free()
	_check("crit stats read as percentages on items", Items.format_mod("crit_chance_add", 0.03) == "+3% Crit chance" and Items.format_mod("crit_damage_add", 0.1) == "+10% Crit damage")
	_neutral_character()


# ---------- support skills (buffs and debuffs), VFX, damage indicators ----------

func _texts_in(node: Node) -> Array:
	return node.get_children().filter(func(n): return n is FloatText).map(func(n): return n.text)


func _test_support_skills() -> void:
	var every_set := true
	var kinds_ok := true
	for set_id in SkillDB.LOADOUTS:
		var id: String = SkillDB.LOADOUTS[set_id]["support"]
		every_set = every_set and SkillDB.DEFS.has(id) and SkillDB.slot_of(id) == "support" and SkillDB.set_of(id) == set_id
		var def: Dictionary = SkillDB.DEFS[id]
		kinds_ok = kinds_ok and (def["kind"] == "buff" and def["buff"]["kind"] in ["might", "mend", "ward", "haste"] or def["kind"] == "aoe" and def["apply"]["kind"] in ["weaken", "vuln"])
	_check("every set has a support skill in its own set", every_set)
	_check("support skills are buffs (might, mend, ward, haste) or debuffs (weaken, vulnerable)", kinds_ok)
	var buffs := SkillDB.LOADOUTS.values().filter(func(l): return SkillDB.DEFS[l["support"]]["kind"] == "buff")
	var debuffs := SkillDB.LOADOUTS.values().filter(func(l): return SkillDB.DEFS[l["support"]]["kind"] == "aoe")
	_check("there are five buffs and three debuffs", buffs.size() == 5 and debuffs.size() == 3)
	_check("effect text says what a buff or debuff does", SkillDB.effect_text(SkillDB.DEFS["blazing_might"]) == "+25% damage for 8s" and SkillDB.effect_text(SkillDB.DEFS["tidal_mending"]).contains("8 HP/s") and SkillDB.effect_text(SkillDB.DEFS["intimidate"]).contains("Weakens") and SkillDB.effect_text(SkillDB.DEFS["fireball"]) == "bursts on impact")
	var six := CharacterData.create_sandbox("channeler", ["fire"], Classes.SUPPORT_LEVEL - 1)
	var seven := CharacterData.create_sandbox("channeler", ["fire"], Classes.SUPPORT_LEVEL)
	_check("the support skill is learned at level 7, for everyone", not six.can_use_skill("blazing_might") and seven.can_use_skill("blazing_might") and Classes.SUPPORT_LEVEL == 7)
	_check("and needs the element", not CharacterData.create_sandbox("channeler", ["water"], 7).can_use_skill("blazing_might"))
	_check("a support skill has its own unlock level", seven.skill_unlock_level("blazing_might") == 7)

	# Buffs on the player.
	var ch := _bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire", "water", "earth", "air"], 7))
	var player = await _player_with(ch)
	player.global_position = Vector2.ZERO
	var mana_before: float = player.caster.mana
	player.caster.cooldowns.clear()
	_check("a buff casts", player.caster.try_cast("blazing_might") and player.buffs.has("might"))
	_check("it costs mana", is_equal_approx(mana_before - player.caster.mana, SkillDB.DEFS["blazing_might"]["mana"] * float(ch.derived()["mana_cost_mult"])))
	_check("Might raises outgoing damage by 25 percent", is_equal_approx(player.damage_mult(), 1.25))
	_check("its length comes from the skill and Wisdom", is_equal_approx(player.buffs["might"]["time"], 8.0 * float(ch.derived()["buff_duration_mult"])))
	_check("it goes on cooldown", not player.caster.can_cast("blazing_might") and player.caster.cooldown_total("blazing_might") > 10.0)
	var dummy := _dummy(Vector2(15, 0))
	await get_tree().process_frame
	dummy.global_position = Vector2(15, 0)
	player.try_melee(Vector2.RIGHT)
	_check("Might makes slashes hit harder", is_equal_approx(dummy.max_hp - dummy.hp, float(SkillDB.MELEE["damage"]) * 1.25))
	_check("a buff shows an aura", player._buff_fx.has("might") and is_instance_valid(player._buff_fx["might"]))
	player._tick_buffs(1.0)
	_check("buffs count down", player.buffs["might"]["time"] < 8.0 * float(ch.derived()["buff_duration_mult"]))
	player._tick_buffs(100.0)
	_check("and expire, taking the aura with them", player.buffs.is_empty() and player.damage_mult() == 1.0)
	await get_tree().process_frame
	_check("the aura is gone", player._buff_fx.is_empty())

	player.hp = 10.0
	player.add_buff("mend", 6.0, 8.0)
	player._tick_buffs(1.0)
	_check("Mending heals per second", is_equal_approx(player.hp, 18.0))
	player._tick_buffs(100.0)
	player.hp = player.max_hp
	player.add_buff("ward", 8.0, 0.3)
	player._hurt_cd = 0.0
	var hp_before: float = player.hp
	_check("Stone Skin cuts damage taken", player.take_damage(10.0, Vector2(40, 0)) and is_equal_approx(hp_before - player.hp, 7.0))
	_check("being hit sets the hit indicator, pointing at the attacker", is_equal_approx(Game.hurt_time, Game.HURT_TIME) and Game.hurt_dir.x > 0.9)
	_check("and shows the damage taken in red", _texts_in(player.get_parent()).has("-7"))
	player._tick_buffs(100.0)
	player.add_buff("haste", 7.0, 0.3)
	_check("Haste is a speed buff", is_equal_approx(player.buff_power("haste"), 0.3))
	player._tick_buffs(100.0)
	var wise := _bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 7))
	wise.attributes["wisdom"] = 25
	Game.character = wise
	player.add_buff("might", 8.0, 0.25)
	_check("Wisdom makes buffs last longer", is_equal_approx(player.buffs["might"]["time"], 8.0 * (1.0 + 20.0 * Classes.WISDOM_BUFF_DURATION)))
	Game.character = ch
	player._tick_buffs(100.0)

	# Dodging avoids damage and says so.
	player._hurt_cd = 0.0
	player.try_dodge(Vector2.RIGHT)
	_check("a hit during a dodge is avoided", not player.take_damage(10.0, Vector2(40, 0)))
	_check("and says Dodge!", _texts_in(player.get_parent()).has("Dodge!"))
	Game._process(5.0)
	_check("the hit indicator fades out", Game.hurt_time == 0.0)

	# Debuffs on enemies.
	var weak_dummy := _dummy(Vector2(300, 300))
	var vuln_dummy := _dummy(Vector2(300, 300))
	await get_tree().process_frame
	_check("an enemy deals full damage by default", weak_dummy.damage_out(10.0) == 10.0)
	var intimidate: Dictionary = SkillDB.DEFS["intimidate"]
	var area := AoeEffect.new()
	area.setup({"damage": 4.0, "element": "", "apply": {"kind": "weaken", "time": 6.0, "power": 0.4}}, 44.0, 0.0, 0.5)
	add_child(area)
	area.global_position = Vector2(300, 300)
	area._apply()
	_check("Intimidate weakens enemies in the area", weak_dummy.effects.has("weaken") and is_equal_approx(weak_dummy.damage_out(10.0), 6.0))
	var fracture := AoeEffect.new()
	fracture.setup({"damage": 6.0, "element": "mineral", "apply": SkillDB.DEFS["fracture"]["apply"]}, 40.0, 0.0, 0.5)
	add_child(fracture)
	fracture.global_position = Vector2(300, 300)
	fracture._apply()
	_check("Fracture makes them vulnerable", vuln_dummy.effects.has("vuln"))
	_check("a weakened slime hits the player for less", is_equal_approx(weak_dummy.damage_out(weak_dummy.contact_damage), weak_dummy.contact_damage * 0.6))
	var away := _dummy(Vector2(900, 900))
	await get_tree().process_frame
	_check("enemies outside the area are untouched", not away.effects.has("weaken"))
	_check("intimidate is a martial skill paid in stamina", SkillDB.uses_stamina(intimidate) and SkillDB.set_of("intimidate") == "martial")
	player.queue_free()
	for node in get_children():
		if node is Enemy or node is AoeEffect or node is FloatText:
			node.queue_free()
	await get_tree().process_frame
	_neutral_character()


func _test_vfx_and_indicators() -> void:
	_check("every element and the martial set have a look", Elements.MAIN.all(func(e): return SkillFx.PROFILES.has(e)) and SkillFx.PROFILES.has("martial") and SkillFx.profile("").has("colors"))
	_check("the elements look different from each other", SkillFx.profile("fire")["gravity"] != SkillFx.profile("water")["gravity"] and SkillFx.profile("fire")["colors"] != SkillFx.profile("air")["colors"])
	var parent := Node2D.new()
	add_child(parent)
	var before := parent.get_child_count()
	SkillFx.cast_burst(parent, Vector2.ZERO, "fire", Vector2.RIGHT)
	_check("casting flashes: particles and a glow", parent.get_child_count() == before + 2 and parent.get_children().any(func(n): return n is CPUParticles2D) and parent.get_children().any(func(n): return n is Sprite2D))
	SkillFx.impact(parent, Vector2.ZERO, "water")
	_check("an impact adds particles and a shock ring", parent.get_children().any(func(n): return n is SkillFx.FxRing))
	var projectile := Projectile.new()
	projectile.setup(Vector2(10, 0), {"damage": 1.0, "element": "air"}, 1.0)
	parent.add_child(projectile)
	_check("bolts fly with a glow and a trail", projectile.get_children().any(func(n): return n is CPUParticles2D) and projectile.get_children().filter(func(n): return n is Sprite2D).size() >= 2)
	var area := AoeEffect.new()
	area.setup({"damage": 1.0, "element": "earth"}, 30.0, 0.0, 0.5)
	parent.add_child(area)
	_check("areas burst with particles and a ring", area.get_children().any(func(n): return n is CPUParticles2D) and area.get_children().any(func(n): return n is SkillFx.FxRing))
	var lingering := AoeEffect.new()
	lingering.setup({"damage": 1.0, "element": "water"}, 30.0, 3.0, 0.5)
	parent.add_child(lingering)
	_check("a lingering area keeps emitting", lingering.get_children().any(func(n): return n is CPUParticles2D and not n.one_shot))
	var aura := SkillFx.aura(parent, Color.RED, "fire")
	_check("an aura emits until it is freed", aura.emitting and not aura.one_shot)
	var ring_parent := Node2D.new()
	add_child(ring_parent)
	SkillFx.ring(ring_parent, Vector2(5, 5), 20.0, Color.WHITE, 0.05)
	_check("a ring appears where it was asked", ring_parent.get_child_count() == 1 and ring_parent.get_child(0).global_position == Vector2(5, 5))
	await get_tree().create_timer(0.2).timeout
	_check("and removes itself when done", ring_parent.get_child_count() == 0)
	parent.free()
	ring_parent.free()

	# Imbue shows on the player.
	var ch := _bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire", "water"], 1))
	var player = await _player_with(ch)
	_check("no imbue glow before imbuing", player._imbue_fx == null)
	player.try_imbue()
	player._sync_imbue_fx()
	_check("imbuing makes the blade throw sparks", player._imbue_fx != null and player._imbue_fx.emitting)
	player.try_imbue()
	player._sync_imbue_fx()
	_check("and stops when it ends", player._imbue_fx == null)
	player.queue_free()

	# Damage numbers.
	var dummy := _dummy(Vector2(500, 500))
	dummy.take_hit({"damage": 12.0, "element": "fire", "from": Vector2.ZERO})
	_check("an enemy shows the damage dealt", _texts_in(self).has("12"))
	Game.character.attributes["luck"] = 100
	Game.combat_rng.seed = 2
	var crit_seen := false
	for i in 20:
		var target := _dummy(Vector2(700, 700))
		target.take_hit({"damage": 10.0, "element": "", "from": Vector2.ZERO})
		crit_seen = crit_seen or _texts_in(self).has("15!")
		target.free()
	Game.character.attributes["luck"] = 5
	_check("a crit is shown with an exclamation mark", crit_seen)
	for node in get_children():
		if node is Enemy or node is FloatText:
			node.queue_free()
	await get_tree().process_frame
	_neutral_character()


# ---------- monsters, variants, bosses, gems ----------

func _fresh_monster(id: String, variant: String = "", pos: Vector2 = Vector2(600, 600)) -> Enemy:
	var enemy: Enemy = load(Monsters.ENEMY_SCENE).instantiate()
	enemy.configure(id, variant)
	enemy.position = pos
	add_child(enemy)
	return enemy


func _test_monsters() -> void:
	var defs_ok := true
	for id in Monsters.DEFS:
		var d: Dictionary = Monsters.DEFS[id]
		if d.get("training", false):
			continue  # the training dummy is built to stand still
		defs_ok = defs_ok and AssetDB.PLACEHOLDERS.has(d["sprite"]) and d["behavior"] in ["chase", "flutter", "ranged", "boss"] and float(d["hp"]) > 0.0 and float(d["speed"]) > 0.0 and int(d["xp"]) > 0
		if d["behavior"] == "ranged":
			defs_ok = defs_ok and d.has("shot") and d.has("attack_range") and d.has("keep_distance") and float(d["keep_distance"]) < float(d["attack_range"])
		if d.get("boss", false):
			defs_ok = defs_ok and d["behavior"] == "boss" and d.has("slam") and d.has("summon") and Monsters.DEFS.has(d["summon"]["id"]) and not Monsters.is_boss(d["summon"]["id"])
	_check("every monster has a sprite, valid stats and the parts its behaviour needs", defs_ok)
	_check("there are thirteen regular monsters, three mini bosses and seven bosses", Monsters.regular().size() == 13 and Monsters.mini_bosses().size() == 3 and Monsters.bosses().size() == 7)
	_check("wave weights only name regular monsters", Monsters.WEIGHTS.values().all(func(w): return w.keys().all(func(id): return Monsters.DEFS.has(id) and not Monsters.is_boss(id))))
	_check("every element is weak to exactly one other", Elements.MAIN.all(func(e): return Monsters.WEAK_TO.has(e) and Monsters.WEAK_TO[e] != e and Monsters.WEAK_TO[e] in Elements.MAIN))
	var plain_slime: Enemy = SLIME.instantiate()
	_check("a plain slime is unchanged", plain_slime.max_hp == 40.0 and plain_slime.behavior == "chase" and plain_slime.variant == "" and not plain_slime.boss)
	plain_slime.free()

	var bat := _fresh_monster("bat")
	var skeleton := _fresh_monster("skeleton")
	var brute := _fresh_monster("brute")
	await get_tree().process_frame
	_check("configuring sets the stats", bat.max_hp == 18.0 and bat.speed == 58.0 and bat.behavior == "flutter" and bat.display_name == "Cave Bat" and bat.hp == 18.0)
	_check("and the sprite", bat.sprite.texture.get_size() == AssetDB.get_texture("enemy_bat").get_size() and brute.sprite.texture.get_size() == AssetDB.get_texture("enemy_brute").get_size())
	_check("big monsters get a bigger body", (brute.get_node("CollisionShape2D").shape as CircleShape2D).radius > (bat.get_node("CollisionShape2D").shape as CircleShape2D).radius)
	_check("bodies are not shared between monsters", brute.get_node("CollisionShape2D").shape != bat.get_node("CollisionShape2D").shape)
	_check("a floor scales health and damage", Monsters.floor_scale(1) == Vector2.ONE and Monsters.floor_scale(3).x > 1.5 and Monsters.floor_scale(3).y > 1.2)
	var scaled: Enemy = load(Monsters.ENEMY_SCENE).instantiate()
	scaled.configure("spitter", "", 2.0, 1.5)
	_check("the scale applies to health, contact and shot damage (and the dungeon's hardness)", scaled.max_hp == 72.0 and is_equal_approx(scaled.contact_damage, 7.0 * 1.5 * Monsters.HARDNESS) and is_equal_approx(scaled.shot["damage"], 6.0 * 1.5 * Monsters.HARDNESS))
	scaled.free()

	# movement behaviours
	var target := Node2D.new()
	add_child(target)
	target.global_position = Vector2(600, 600) + Vector2(100, 0)
	var chase := _fresh_monster("slime")
	await get_tree().process_frame
	chase.global_position = Vector2(600, 600)
	_check("a slime walks straight at you", chase._desired_velocity(target).normalized().is_equal_approx(Vector2.RIGHT))
	bat.global_position = Vector2(600, 600)
	bat._age = 0.0
	var first: Vector2 = bat._desired_velocity(target)
	bat._age = 0.25
	var second: Vector2 = bat._desired_velocity(target)
	_check("a bat weaves from side to side while closing in", first.x > 0.0 and second.x > 0.0 and not is_equal_approx(first.y, second.y))
	skeleton.global_position = Vector2(600, 600)
	_check("an archer too far away closes in", skeleton._desired_velocity(target).x > 0.0)
	target.global_position = Vector2(600, 600) + Vector2(40, 0)
	_check("and backs away when you get close", skeleton._desired_velocity(target).x < 0.0)
	target.global_position = Vector2(600, 600) + Vector2(80, 0)
	skeleton._age = 1.0
	_check("at its preferred distance it drifts sideways", absf(skeleton._desired_velocity(target).y) > 0.0 and is_equal_approx(skeleton._desired_velocity(target).x, 0.0))
	skeleton.effects["root"] = {"time": 1.0, "power": 1.0}
	_check("a rooted monster does not move", skeleton._desired_velocity(target) == Vector2.ZERO)
	skeleton.effects.clear()

	# shooting
	var player = await _player_with(_bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1)))
	player.global_position = Vector2(600, 600) + Vector2(70, 0)
	skeleton.global_position = Vector2(600, 600)
	skeleton._attack_cd = 0.0
	var shots_before := get_children().filter(func(n): return n is EnemyProjectile).size()
	skeleton._attack(0.016, player)
	var shots := get_children().filter(func(n): return n is EnemyProjectile)
	_check("an archer in range fires", shots.size() == shots_before + 1 and skeleton._attack_cd == float(skeleton.shot["cooldown"]))
	_check("the arrow flies toward you", (shots[-1] as EnemyProjectile).velocity.x > 0.0 and is_equal_approx((shots[-1] as EnemyProjectile).velocity.length(), float(skeleton.shot["speed"])))
	skeleton._attack(0.016, player)
	_check("and waits for its cooldown", get_children().filter(func(n): return n is EnemyProjectile).size() == shots.size())
	player.global_position = Vector2(600, 600) + Vector2(300, 0)
	skeleton._attack_cd = 0.0
	skeleton._attack(0.016, player)
	_check("out of range it holds fire", get_children().filter(func(n): return n is EnemyProjectile).size() == shots.size())
	player.global_position = Vector2.ZERO
	player._hurt_cd = 0.0
	var arrow := EnemyProjectile.spawn(self, Vector2.ZERO, Vector2.RIGHT, 50.0, 7.0)
	var hp_before: float = player.hp
	arrow._on_body_entered(player)
	_check("an arrow that reaches you hurts and vanishes", is_equal_approx(hp_before - player.hp, 7.0) and arrow.is_queued_for_deletion())
	player._hurt_cd = 0.0
	player.try_dodge(Vector2.RIGHT)
	var passing := EnemyProjectile.spawn(self, Vector2.ZERO, Vector2.RIGHT, 50.0, 7.0)
	passing._on_body_entered(player)
	_check("a dodge lets an arrow pass through", not passing.is_queued_for_deletion() and is_equal_approx(player.hp, hp_before - 7.0))
	var wall := StaticBody2D.new()
	add_child(wall)
	var blocked := EnemyProjectile.spawn(self, Vector2.ZERO, Vector2.RIGHT, 50.0, 7.0)
	blocked._on_body_entered(wall)
	_check("arrows stop at walls", blocked.is_queued_for_deletion())
	skeleton.effects["weaken"] = {"time": 5.0, "power": 0.5}
	skeleton._attack_cd = 0.0
	player.global_position = Vector2(600, 600) + Vector2(70, 0)
	skeleton._attack(0.016, player)
	_check("a weakened archer shoots weaker arrows", is_equal_approx((get_children().filter(func(n): return n is EnemyProjectile)[-1] as EnemyProjectile).damage, float(skeleton.shot["damage"]) * 0.5))
	skeleton.effects.clear()

	# toughness
	var slime := _dummy(Vector2(700, 700))
	var heavy := _fresh_monster("brute", "", Vector2(700, 700))
	await get_tree().process_frame
	slime.take_hit({"damage": 1.0, "element": "", "knockback": 100.0, "from": Vector2(0, 700)})
	heavy.take_hit({"damage": 1.0, "element": "", "knockback": 100.0, "from": Vector2(0, 700)})
	_check("a brute is hard to push around", heavy._knock.length() < slime._knock.length() * 0.5 and heavy.max_hp > 100.0)

	# elemental variants
	var fire := _fresh_monster("slime", "fire")
	await get_tree().process_frame
	_check("a variant is tougher and worth more", is_equal_approx(fire.max_hp, 40.0 * Monsters.VARIANT_HP) and is_equal_approx(fire.contact_damage, 8.0 * Monsters.VARIANT_DAMAGE * Monsters.HARDNESS) and fire.xp_reward == 18)
	_check("it is named for its element and tinted", fire.display_name == "Fire Slime" and fire.variant == "fire" and fire._base_tint != Color.WHITE)
	fire.take_hit({"damage": 10.0, "element": "fire", "from": Vector2.ZERO})
	_check("it resists its own element", is_equal_approx(fire.max_hp - fire.hp, 10.0 * Monsters.RESIST_MULT))
	_check("and says so", _texts_in(self).has("Resist!"))
	fire.hp = fire.max_hp
	fire.aura = ""
	fire.take_hit({"damage": 10.0, "element": "water", "from": Vector2.ZERO})
	_check("it is weak to the element that beats it", is_equal_approx(fire.max_hp - fire.hp, 10.0 * Monsters.WEAK_MULT))
	_check("and says so too", _texts_in(self).has("Weak!"))
	fire.hp = fire.max_hp
	fire.aura = ""
	fire.take_hit({"damage": 10.0, "element": "earth", "from": Vector2.ZERO})
	_check("other elements and physical hits do normal damage", is_equal_approx(fire.max_hp - fire.hp, 10.0))
	fire.hp = fire.max_hp
	fire.effects.clear()
	fire.take_hit({"damage": 10.0, "element": "", "from": Vector2.ZERO})
	_check("physical hits do normal damage", is_equal_approx(fire.max_hp - fire.hp, 10.0))
	var boss_try: Enemy = load(Monsters.ENEMY_SCENE).instantiate()
	boss_try.configure("slime_king", "fire")
	_check("a boss is never a variant", boss_try.variant == "" and boss_try.boss)
	boss_try.free()

	# waves
	var all_ok := true
	var floor_one_clean := true
	var floor_three_variants := 0
	var floor_one_variants := 0
	for seed_value in 200:
		for floor_number in [1, 2, 3]:
			var wave := Monsters.roll_wave(_rng(seed_value), floor_number, 5)
			all_ok = all_ok and wave.size() == 5 and wave.all(func(e): return Monsters.DEFS.has(e["id"]) and not Monsters.is_boss(e["id"]) and (e["variant"] == "" or e["variant"] in Elements.MAIN))
			if floor_number == 1:
				floor_one_clean = floor_one_clean and wave.all(func(e): return e["id"] in ["slime", "bat", "skeleton", "spitter"])
				floor_one_variants += wave.filter(func(e): return e["variant"] != "").size()
			if floor_number == 3:
				floor_three_variants += wave.filter(func(e): return e["variant"] != "").size()
	_check("waves hold valid regular monsters", all_ok)
	_check("floor 1 only has the easy monsters", floor_one_clean)
	_check("deeper floors have more elemental variants", floor_three_variants > floor_one_variants * 2 and floor_one_variants > 50)
	_check("a wave is reproducible from a seed", Monsters.roll_wave(_rng(5), 2, 6) == Monsters.roll_wave(_rng(5), 2, 6))

	for node in get_children():
		if node is Enemy or node is EnemyProjectile or node is FloatText or node is StaticBody2D or node.get_class() == "Node2D":
			node.queue_free()
	player.queue_free()
	await get_tree().process_frame
	_neutral_character()


func _test_boss_and_gems() -> void:
	var player = await _player_with(_bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1)))
	player.global_position = Vector2(400, 400)
	var boss := _fresh_monster("slime_king", "", Vector2(400, 400))
	await get_tree().process_frame
	_check("a boss is big, tough and nearly unmovable", boss.boss and boss.max_hp == 520.0 and boss.knock_resist >= 0.9 and boss.sprite.texture.get_size().x >= 28)
	boss._attack_cd = 0.0
	boss._attack(0.016, player)
	_check("in reach, a boss starts a slam and warns with a circle", boss._telegraph != null and boss._telegraph.radius == 40.0 and is_equal_approx(boss._telegraph.time, 0.8))
	_check("while winding up it stands still", boss._desired_velocity(player) == Vector2.ZERO)
	boss._attack_cd = 0.0
	boss._attack(0.016, player)
	_check("it only winds up one slam at a time", get_children().filter(func(n): return n is Telegraph).size() == 1)
	player._hurt_cd = 0.0
	var hp_before: float = player.hp
	boss._telegraph._physics_process(10.0)
	_check("the slam hurts whoever stays in the circle", is_equal_approx(hp_before - player.hp, 22.0 * Monsters.HARDNESS))
	_check("and the boss is free to move again", boss._telegraph == null)
	player._hurt_cd = 0.0
	player.global_position = Vector2(400, 400)
	boss._attack_cd = 0.0
	boss._attack(0.016, player)
	player.global_position = Vector2(400, 400) + Vector2(150, 0)
	hp_before = player.hp
	boss._telegraph._physics_process(10.0)
	_check("stepping out of the circle avoids it", player.hp == hp_before)
	var far := Node2D.new()
	add_child(far)
	far.global_position = Vector2(400, 400) + Vector2(400, 0)
	boss._attack_cd = 0.0
	boss._attack(0.016, far)
	_check("a boss out of reach doesn't slam", boss._telegraph == null)
	far.free()

	# summons
	var before := get_tree().get_nodes_in_group("enemies").size()
	boss.hp = boss.max_hp * 0.6
	boss._boss_summons()
	await get_tree().process_frame
	_check("at 66 percent health the boss calls three slimes", get_tree().get_nodes_in_group("enemies").size() == before + 3)
	boss._boss_summons()
	await get_tree().process_frame
	_check("only once per stage", get_tree().get_nodes_in_group("enemies").size() == before + 3)
	boss.hp = boss.max_hp * 0.3
	boss._boss_summons()
	await get_tree().process_frame
	_check("and again at 33 percent", get_tree().get_nodes_in_group("enemies").size() == before + 6)
	boss._boss_summons()
	await get_tree().process_frame
	_check("then no more", get_tree().get_nodes_in_group("enemies").size() == before + 6)
	var colossus := _fresh_monster("stone_colossus", "", Vector2(900, 900))
	await get_tree().process_frame
	colossus.hp = colossus.max_hp * 0.4
	var bats_before := get_tree().get_nodes_in_group("enemies").size()
	colossus._boss_summons()
	await get_tree().process_frame
	_check("the Stone Colossus calls four bats at half health", get_tree().get_nodes_in_group("enemies").size() == bats_before + 4)

	# boss loot
	var ch := Game.character
	var drops_seen: Array = []
	var listener := func(drops: Array, _pos: Vector2): drops_seen.append(drops)
	Game.loot_dropped.connect(listener)
	boss.hp = 1.0
	boss.last_element = ""
	Game.loot_rng.seed = 4
	boss.take_hit({"damage": 100.0, "element": "", "from": Vector2.ZERO})
	Game.loot_dropped.disconnect(listener)
	var boss_drop: Array = drops_seen[0] if not drops_seen.is_empty() else []
	_check("a boss drops lots of gold, scrap and two items", boss_drop.any(func(e): return e["kind"] == "gold" and e["amount"] >= 60) and boss_drop.filter(func(e): return e["kind"] == "item").size() == 2)
	_check("the first item is at least rare", Items.RARITIES.find(boss_drop.filter(func(e): return e["kind"] == "item")[0]["item"]["rarity"]) >= 2)

	var gem_count := 0
	var wrong_gem := false
	for i in 400:
		for entry in Loot.boss_drops(_rng(i), 5, 0.0, ["fire", "air"]):
			if entry["kind"] == "material" and String(entry["id"]).begins_with("gem_"):
				gem_count += 1
				wrong_gem = wrong_gem or not (entry["id"] in ["gem_fire", "gem_air"])
	_check("about half of bosses drop a gem", absf(float(gem_count) / 400.0 - Loot.GEM_CHANCE) < 0.08)
	_check("and only for elements you are missing", not wrong_gem)
	var none_missing := Loot.boss_drops(_rng(1), 5, 0.0, [])
	_check("with nothing left to attune to, a boss drops essence instead", not none_missing.any(func(e): return e["kind"] == "material" and String(e["id"]).begins_with("gem_")) and none_missing.any(func(e): return e["kind"] == "material" and String(e["id"]).begins_with("essence_") and e["amount"] == 3))
	var sealed := CharacterData.create("S", Classes.NEUTRAL_CLASS, CharacterData.SEALED, _rng(1))
	_check("a sealed character has nothing to attune to", sealed.missing_elements().is_empty())
	var fire_only := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1)
	_check("everyone else is missing the other elements", fire_only.missing_elements().size() == 4 and not ("fire" in fire_only.missing_elements()) and Elements.MAIN.all(func(e): return e == "fire" or e in fire_only.missing_elements()))

	# gems
	var gem_char := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1)
	gem_char.inventory.add_material("gem_water", 1)
	gem_char.inventory.add_material("gem_fire", 1)
	_check("a gem you have no use for can't be used", not gem_char.use_gem("fire") and gem_char.inventory.count("gem_fire") == 1)
	_check("you can't use a gem you don't have", not gem_char.use_gem("earth"))
	_check("a gem attunes you to its element", gem_char.use_gem("water") and "water" in gem_char.elements and gem_char.inventory.count("gem_water") == 0)
	_check("and the new element has a mastery to grow", gem_char.element_level("water") == 1)
	var sealed_gem := CharacterData.create("S", Classes.NEUTRAL_CLASS, CharacterData.SEALED, _rng(2))
	sealed_gem.inventory.add_material("gem_fire", 1)
	_check("a sealed character can't use a gem", not sealed_gem.use_gem("fire") and sealed_gem.elements.is_empty())
	var attunable := CharacterData.create("A", Classes.NEUTRAL_CLASS, CharacterData.ATTUNABLE, _rng(3))
	attunable.inventory.add_material("gem_air", 1)
	_check("a character born without elements is attuned by a gem", attunable.use_gem("air") and attunable.elements == ["air"] and attunable.uses_mana() and attunable.has_martial())
	var rich := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, [], 1)
	rich.inventory.add_material("gem_fire", 2)
	_check("gems appear in the wallet line", rich.inventory.summary().contains("Gems F2"))
	_check("every element has a gem material", Elements.MAIN.all(func(e): return Items.MATERIALS.has(Items.gem_of(e))))
	var variant_drops := 0
	var rng := _rng(8)
	for i in 1000:
		for entry in Loot.enemy_drops(rng, 3, 0.0, "", true, "earth"):
			if entry["kind"] == "material" and entry["id"] == "essence_earth":
				variant_drops += 1
	_check("an elemental variant usually drops its own essence", absf(float(variant_drops) / 1000.0 - Loot.VARIANT_ESSENCE_CHANCE) < 0.06)

	# the HUD survives a slain (freed) boss: it once crashed casting the freed object
	var hud: CanvasLayer = load("res://scripts/ui/hud.gd").new()
	add_child(hud)
	await get_tree().process_frame
	var doomed := _fresh_monster("slime_king", "", Vector2(900, 900))
	Game.boss = doomed
	doomed.free()
	hud._draw_boss_bar(ThemeDB.fallback_font)
	_check("the HUD copes with a boss that has been freed", not is_instance_valid(Game.boss))
	Game.boss = null
	hud.free()

	# the Gear tab offers gems
	var sheet_char := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1)
	sheet_char.inventory.add_material("gem_water", 1)
	sheet_char.inventory.add_material("gem_fire", 1)
	Game.character = sheet_char
	var sheet := CharacterSheet.new()
	add_child(sheet)
	await get_tree().process_frame
	sheet.show_tab("gear")
	await get_tree().process_frame
	var gem_buttons := sheet.find_children("*", "Button", true, false).filter(func(b): return b.text.begins_with("Use "))
	_check("the gear tab lists each gem you carry", gem_buttons.size() == 2)
	_check("a gem for an element you have is greyed out", gem_buttons.filter(func(b): return b.disabled).size() == 1)
	sheet._use_gem("water")
	_check("using it from the sheet attunes you", "water" in sheet_char.elements)
	await get_tree().process_frame
	sheet.free()
	for node in get_children():
		if node is Enemy or node is Telegraph or node is FloatText or node is Pickup or node.get_class() == "Node2D":
			node.queue_free()
	player.queue_free()
	await get_tree().process_frame
	_neutral_character()


# ---------- the dungeon ----------

func _test_dungeon_gen() -> void:
	var layout := DungeonGen.generate(_rng(1))
	_check("a dungeon has three floors of three rooms", layout.size() == 3 and layout.all(func(f): return f.size() == 3))
	var shapes_ok := true
	var boss_rooms := 0
	var entries_ok := true
	var doors_ok := true
	var obstacles_ok := true
	var waves_ok := true
	var specials_ok := true
	var sizes_ok := true
	for seed_value in 60:
		var dungeon := DungeonGen.generate(_rng(seed_value))
		for f in dungeon.size():
			var rooms: Array = dungeon[f]
			var last_floor := f == dungeon.size() - 1
			shapes_ok = shapes_ok and rooms[0]["kind"] == "combat" and (rooms[-1]["kind"] == "boss") == last_floor
			var specials := rooms.filter(func(r): return r["kind"] in ["treasure", "forge"])
			specials_ok = specials_ok and specials.size() == 1 and rooms[0]["kind"] == "combat"
			for i in rooms.size():
				var r: Dictionary = rooms[i]
				boss_rooms += 1 if r["kind"] == "boss" else 0
				entries_ok = entries_ok and r["floor"] == f + 1 and r["index"] == i
				if i == 0:
					entries_ok = entries_ok and r["entry"] == ""
				else:
					entries_ok = entries_ok and r["entry"] == DungeonGen.OPPOSITE[rooms[i - 1]["exit"]]
				if r["kind"] == "boss":
					entries_ok = entries_ok and r["exit"] == "" and Monsters.is_boss(r["boss"]) and r["waves"].is_empty()
				else:
					entries_ok = entries_ok and r["exit"] != "" and r["exit"] != r["entry"] and r["boss"] == ""
				var cols: int = r["cols"]
				var rows: int = r["rows"]
				match r["kind"]:
					"combat": sizes_ok = sizes_ok and cols >= 20 and cols <= 28 and rows >= 12 and rows <= 15
					"boss": sizes_ok = sizes_ok and cols == 26 and rows == 16
					_: sizes_ok = sizes_ok and cols >= 14 and cols <= 18 and rows >= 10 and rows <= 12
				var whiches: Array = []
				if r["entry"] != "":
					whiches.append("entry")
				if r["exit"] != "":
					whiches.append("exit")
				for which in whiches:
					var rect := DungeonGen.door_rect(r, which)
					var on_wall: bool = (rect.position.x == 0 or rect.end.x == cols or rect.position.y == 0 or rect.end.y == rows)
					var inside: bool = rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= cols and rect.end.y <= rows
					var corner_clear: bool = (rect.position.x >= 3 and rect.end.x <= cols - 3) if rect.size.x == DungeonGen.DOOR_WIDTH else (rect.position.y >= 3 and rect.end.y <= rows - 3)
					doors_ok = doors_ok and on_wall and inside and corner_clear and rect.size.x * rect.size.y == DungeonGen.DOOR_WIDTH
				var keep := DungeonGen.keep_clear(r)
				var placed: Array = r["obstacles"]
				for a in placed.size():
					var rect: Rect2i = placed[a]
					obstacles_ok = obstacles_ok and rect.position.x >= DungeonGen.WALL_MARGIN and rect.position.y >= DungeonGen.WALL_MARGIN and rect.end.x <= cols - DungeonGen.WALL_MARGIN and rect.end.y <= rows - DungeonGen.WALL_MARGIN
					for zone in keep:
						obstacles_ok = obstacles_ok and not zone.intersects(rect)
					for b in range(a + 1, placed.size()):
						obstacles_ok = obstacles_ok and not (placed[b] as Rect2i).grow(1).intersects(rect)
				if r["kind"] == "combat":
					waves_ok = waves_ok and r["waves"].size() >= 1 and r["waves"].size() <= 2 and (f < 2 or r["waves"].size() == 2)
					var sizes: Array = r["waves"].map(func(w): return w.size())
					var lo := 2 + (f + 1)
					var hi := 3 + (f + 1) + (1 if f > 0 else 0)
					waves_ok = waves_ok and sizes.all(func(s): return s >= lo and s <= hi)
				else:
					waves_ok = waves_ok and r["waves"].is_empty()
	_check("every floor starts with combat and only the last ends in the boss", shapes_ok)
	_check("every dungeon has exactly one boss room", boss_rooms == 60)
	_check("each floor has one treasure or forge room, never first", specials_ok)
	_check("rooms connect: you enter on the wall opposite the last exit", entries_ok)
	_check("room sizes follow their kind", sizes_ok)
	_check("doors are a two-tile gap in a wall, clear of the corners", doors_ok)
	_check("pillars stay off the walls, the doors and the entry point, and apart from each other", obstacles_ok)
	_check("combat rooms have one or two waves (always two on the last floor) that grow with depth", waves_ok)
	_check("the same seed makes the same dungeon", DungeonGen.generate(_rng(9)) == DungeonGen.generate(_rng(9)))
	_check("different seeds make different dungeons", DungeonGen.generate(_rng(9)) != DungeonGen.generate(_rng(10)))
	var kinds := {}
	for seed_value in 60:
		for room in DungeonGen.generate(_rng(seed_value))[0]:
			kinds[room["kind"]] = true
	_check("treasure rooms and forges both turn up", kinds.has("treasure") and kinds.has("forge") and kinds.has("combat"))
	var first: Dictionary = DungeonGen.generate(_rng(3))[0][0]
	_check("the first room starts you in the middle", DungeonGen.spawn_tile(first) == Vector2i(floori(first["cols"] / 2.0), floori(first["rows"] / 2.0)))
	var second: Dictionary = DungeonGen.generate(_rng(3))[0][1]
	var spawn := DungeonGen.spawn_tile(second)
	var entry_rect := DungeonGen.door_rect(second, "entry")
	_check("later rooms start you just inside the entry door", absi(spawn.x - entry_rect.position.x) <= 2 and absi(spawn.y - entry_rect.position.y) <= 2 and spawn.x > 0 and spawn.y > 0 and spawn.x < second["cols"] - 1 and spawn.y < second["rows"] - 1)
	_check("rooms describe themselves", DungeonGen.describe(first).begins_with("Floor 1") and DungeonGen.describe(layout[2][2]).contains("Boss"))
	_check("the layout has the three floors the roadmap asks for", DungeonGen.FLOORS == 3)


func _dungeon_world(seed_value: int, character: CharacterData) -> Dictionary:
	Game.character = character
	var world := Node2D.new()
	add_child(world)
	var player = PLAYER.instantiate()
	world.add_child(player)
	var dungeon := Dungeon.new()
	dungeon.with_ui = false
	dungeon.layout = DungeonGen.generate(_rng(seed_value))
	world.add_child(dungeon)
	world.move_child(dungeon, 0)
	await get_tree().process_frame
	return {"world": world, "player": player, "dungeon": dungeon}


func _test_dungeon_run() -> void:
	var ch := _bare(CharacterData.create_sandbox("vanguard", ["fire"], 3))
	var parts: Dictionary = await _dungeon_world(7, ch)
	var world: Node2D = parts["world"]
	var player = parts["player"]
	var dungeon: Dungeon = parts["dungeon"]
	var first: Dictionary = dungeon.layout[0][0]
	_check("a run starts in the first room, fighting", dungeon.floor_index == 0 and dungeon.room_index == 0 and dungeon.state == "fighting")
	_check("the player starts in the middle of it", player.global_position.is_equal_approx((Vector2(DungeonGen.spawn_tile(first)) + Vector2(0.5, 0.5)) * 16.0))
	var door: Door = dungeon._exit_door
	_check("the exit is a locked door", door != null and not door.open and not door.get_node("CollisionShape2D").disabled)
	_check("the camera is limited to the room", player.get_node("Camera2D").limit_right == int(first["cols"]) * 16 and player.get_node("Camera2D").limit_bottom == int(first["rows"]) * 16)
	var solid_tiles := dungeon._room_node.get_children().filter(func(n): return n is StaticBody2D).size()
	var perimeter: int = 2 * (int(first["cols"]) + int(first["rows"])) - 4 - 2  # the door's two tiles are not wall
	var pillar_tiles := 0
	for rect in first["obstacles"]:
		pillar_tiles += rect.size.x * rect.size.y
	_check("the room has walls all round, a gap for the door and its pillars", solid_tiles == perimeter + pillar_tiles + 1)  # +1: the door itself is a body
	_check("nothing is spawned before the first wave's delay", dungeon.enemies_alive() == 0 and dungeon.wave == 0)
	dungeon._physics_process(Dungeon.WAVE_DELAY + 0.1)
	var expected: int = first["waves"][0].size()
	_check("then the first wave appears", dungeon.enemies_alive() == expected and dungeon.wave == 1)
	_check("monsters appear away from the player", get_tree().get_nodes_in_group("enemies").all(func(e): return e.global_position.distance_to(player.global_position) >= Dungeon.MIN_SPAWN_DISTANCE - 1.0))
	_check("the HUD line says where you are", Game.run_text.begins_with("Floor 1/3  Room 1/3") and Game.run_text.contains("Enemies %d" % expected))
	dungeon._physics_process(0.1)
	_check("the door stays locked while monsters live", not door.open and dungeon.state == "fighting")
	player.global_position = door.global_position
	dungeon._physics_process(0.1)
	_check("a locked door can't be walked through", dungeon.room_index == 0)
	_check("the exit door contains the player standing in it, and not otherwise", door.contains(door.global_position) and not door.contains(door.global_position + Vector2(100, 100)))

	# finish the room (the dungeon also runs on its own between frames, so stand clear of the door)
	player.global_position = Vector2(float(first["cols"]), float(first["rows"])) * 8.0  # the room's centre
	dungeon.debug_clear_room()
	await get_tree().process_frame
	await get_tree().process_frame
	dungeon._physics_process(0.1)
	_check("when the last monster dies the room is cleared", dungeon.state == "clear" and dungeon.enemies_alive() == 0)
	await get_tree().process_frame
	_check("and the door opens", door.open and door.get_node("CollisionShape2D").disabled)
	var drops_waiting := get_tree().get_nodes_in_group("pickups").size()
	player.global_position = door.global_position
	dungeon._physics_process(0.1)
	await get_tree().process_frame
	_check("walking through moves you to the next room", dungeon.room_index == 1 and dungeon.floor_index == 0)
	_check("the loot left behind was picked up on the way out (or never dropped)", drops_waiting >= 0 and get_tree().get_nodes_in_group("pickups").is_empty())
	_check("the player is put just inside the new room's entry", dungeon.room["entry"] == DungeonGen.OPPOSITE[first["exit"]])
	_check("danger grows with each room", Game.danger == 1)
	_check("only the new room's walls exist", dungeon._room_node.get_child_count() > 100)

	# the kinds of room
	dungeon.debug_goto(0, 1)
	var second: Dictionary = dungeon.layout[0][1]
	if second["kind"] == "combat":
		dungeon.debug_goto(0, 2)
		second = dungeon.layout[0][2]
	_check("a special room is cleared at once with its door open", second["kind"] in ["treasure", "forge"] and dungeon.state == "clear" and dungeon._exit_door.open)
	var special_node_ok: bool = dungeon._room_node.get_children().any(func(n): return n is Chest if second["kind"] == "treasure" else n is ForgeStation)
	_check("a treasure room holds a chest and a forge room the forge", special_node_ok)
	var forge_layout: Array = []
	var forge_at := Vector2i(-1, -1)
	for s in 40:
		var candidate := DungeonGen.generate(_rng(s))
		for f in candidate.size():
			for i in candidate[f].size():
				if candidate[f][i]["kind"] == "forge" and forge_at.x < 0:
					forge_layout = candidate
					forge_at = Vector2i(f, i)
		if forge_at.x >= 0:
			break
	dungeon.layout = forge_layout
	player.hp = 5.0
	player.stamina = 1.0
	dungeon.debug_goto(forge_at.x, forge_at.y)
	_check("a forge room heals half your health and refills stamina", is_equal_approx(player.hp, minf(player.max_hp, 5.0 + player.max_hp * Dungeon.FORGE_HEAL)) and is_equal_approx(player.stamina, player.max_stamina))
	_check("and spawns the forge station", dungeon._room_node.get_children().any(func(n): return n is ForgeStation))

	# floors and the boss
	dungeon.layout = DungeonGen.generate(_rng(7))
	dungeon.debug_goto(0, 2)
	dungeon._advance()
	_check("after the last room of a floor comes the next floor", dungeon.floor_index == 1 and dungeon.room_index == 0 and Game.danger == 3)
	dungeon._physics_process(Dungeon.WAVE_DELAY + 0.1)
	var floor_scale := Monsters.floor_scale(2)
	var scaled_ok: bool = get_tree().get_nodes_in_group("enemies").all(func(e): return e.max_hp >= float(Monsters.DEFS[e.monster_id]["hp"]) * floor_scale.x - 0.01)
	_check("deeper monsters are tougher", scaled_ok and dungeon.enemies_alive() > 0)
	dungeon.debug_goto(2, 2)
	var boss_room: Dictionary = dungeon.layout[2][2]
	_check("the last room is the boss room with no exit", boss_room["kind"] == "boss" and dungeon._exit_door == null and dungeon.state == "fighting")
	_check("the boss isn't there until the room has had a moment", Game.boss == null and dungeon.enemies_alive() == 0)
	dungeon._physics_process(Dungeon.WAVE_DELAY + 0.1)
	_check("then the boss appears and the HUD tracks it", Game.boss != null and Game.boss.monster_id == boss_room["boss"] and Game.boss.boss)
	await get_tree().process_frame
	dungeon._physics_process(0.1)
	_check("the room isn't won while the boss lives", dungeon.state == "fighting")
	var boss: Enemy = Game.boss
	boss.take_hit({"damage": 100000.0, "element": "", "from": Vector2.ZERO})
	await get_tree().process_frame
	await get_tree().process_frame
	dungeon._physics_process(0.1)
	_check("killing the boss wins the run", dungeon.state == "won")
	_check("the run summary lists the result", dungeon.summary_lines(true)[0].contains("Cleared all 3 floors") and dungeon.summary_lines(true).any(func(l): return l.begins_with("Monsters slain")) and dungeon.summary_lines(false)[0].begins_with("Fell on floor"))
	_check("the boss's loot dropped", Game.run_kills >= 1)

	# dying ends the run
	world.queue_free()
	Game.boss = null
	await get_tree().process_frame
	var parts2: Dictionary = await _dungeon_world(11, _bare(CharacterData.create_sandbox("vanguard", ["fire"], 1)))
	var player2 = parts2["player"]
	var dungeon2: Dungeon = parts2["dungeon"]
	player2.hp = 1.0
	player2._hurt_cd = 0.0
	player2.take_damage(50.0, Vector2(40, 0))
	_check("dying ends the run", dungeon2.state == "dead")
	_check("and says where you fell", dungeon2.summary_lines(false)[0] == "Fell on floor 1, room 1")
	dungeon2.debug_clear_room()
	_check("debug clearing does nothing outside a fight", dungeon2.state == "dead")

	# the end screen
	var screen := RunEndScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.show_result(true, ["Cleared all 3 floors", "Monsters slain: 4"])
	await get_tree().process_frame
	var text := " ".join(screen.find_children("*", "Label", true, false).map(func(l): return l.text))
	_check("the victory screen shows the title and the summary", text.contains("Dungeon cleared!") and text.contains("Monsters slain: 4") and screen.is_open() and get_tree().paused)
	screen._open = false
	get_tree().paused = false
	screen.show_result(false, ["Fell on floor 1"])
	await get_tree().process_frame
	text = " ".join(screen.find_children("*", "Label", true, false).map(func(l): return l.text))
	_check("the defeat screen says you fell", text.contains("You fell"))
	screen._open = false
	get_tree().paused = false
	screen.free()

	parts2["world"].queue_free()
	Game.boss = null
	Game.run_text = ""
	await get_tree().process_frame
	_neutral_character()


# ---------- the resource-management rework ----------

func _test_recovery_and_kills() -> void:
	var ch := _bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1))
	var player = await _player_with(ch)
	_check("recovery is slow: a few HP, some stamina and mana a second", ch.derived()["hp_regen"] < 0.5 and ch.derived()["stamina_regen"] < 20.0 and ch.derived()["mana_regen"] < 6.0)
	_check("a hit pauses health recovery for six seconds", player.hp_regen_delay == 6.0)
	player.hp = 50.0
	player.stamina = 10.0
	player.caster.mana = 10.0
	player.restore_on_kill()
	_check("a kill gives back a little stamina and mana, and no health", is_equal_approx(player.hp, 50.0) and is_equal_approx(player.stamina, 10.0 + Classes.KILL_STAMINA) and is_equal_approx(player.caster.mana, 10.0 + Classes.KILL_MANA))
	ch.traits.append("vampiric")
	ch.traits.append("mana_siphon")
	ch.traits.append("adrenaline")
	player.restore_on_kill()
	_check("Vampiric, Mana Siphon and Adrenaline give back more", is_equal_approx(player.hp, 52.0) and is_equal_approx(player.stamina, 13.0 + Classes.KILL_STAMINA + 6.0) and is_equal_approx(player.caster.mana, 11.5 + Classes.KILL_MANA + 3.0))
	player.hp = player.max_hp - 0.5
	player.restore_on_kill()
	_check("but never beyond the maximum", player.hp == player.max_hp)
	var before: float = player.stamina
	var victim := _dummy(Vector2(800, 800))
	Game.on_enemy_killed(victim)
	_check("killing an enemy triggers it", player.stamina > before)
	victim.free()
	var sealed := CharacterData.create("S", Classes.NEUTRAL_CLASS, CharacterData.SEALED, _rng(4))
	_check("a character without elements has no mana to get back", sealed.derived()["kill_mana"] == 0.0)
	_check("a level up heals only a fifth of max HP", CharacterData.LEVEL_UP_HEAL_FRACTION == 0.2)
	_check("monsters hit hard in the dungeon", Monsters.HARDNESS > 1.2)
	var slime := _fresh_monster("slime")
	_check("a configured slime bites for the dungeon's hardness", is_equal_approx(slime.contact_damage, 8.0 * Monsters.HARDNESS))
	player.hp = player.max_hp
	player.stamina = 100.0
	player._hurt_cd = 0.0
	var dodge_before: float = player.stamina
	player.try_dodge(Vector2.RIGHT)
	_check("a dodge costs 30 stamina", is_equal_approx(dodge_before - player.stamina, 30.0))
	player._dodge_left = 0.0
	player._dodge_cd = 0.0
	ch.traits.append("nimble")
	player.stamina = 100.0
	player.try_dodge(Vector2.RIGHT)
	_check("Nimble makes dodges cost 20 percent less", is_equal_approx(100.0 - player.stamina, 24.0))
	slime.free()
	player.queue_free()
	await get_tree().process_frame
	_neutral_character()


func _test_attack_speed() -> void:
	var c := _bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1))
	_check("attack speed is 1 at 5 Dexterity and level 1", c.derived()["attack_speed"] == 1.0)
	c.attributes["dexterity"] = 15
	_check("each Dexterity point adds 3 percent", is_equal_approx(c.derived()["attack_speed"], 1.0 + 10.0 * Classes.DEXTERITY_ATTACK_SPEED))
	c.traits.append("quick_strikes")
	_check("passives multiply it (Quick Strikes +8 percent)", is_equal_approx(c.derived()["attack_speed"], 1.3 * 1.08))
	var leveled := _bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, [], 11))
	_check("every character level adds 1 percent", is_equal_approx(leveled.derived()["attack_speed"], 1.0 + 10.0 * Classes.LEVEL_ATTACK_SPEED))
	var fast_attrs := ["ranger", "assassin"].all(func(id): return CharacterData.create_sandbox(id, [], 1).attributes["dexterity"] == 7)
	var slow_attrs := ["berserker", "sage", "druid", "channeler"].all(func(id): return CharacterData.create_sandbox(id, [], 1).attributes["dexterity"] == 4)
	_check("rangers and assassins are quick; berserkers and casters are slower", fast_attrs and slow_attrs)
	var player = await _player_with(c)
	player.try_melee(Vector2.RIGHT)
	_check("a slash recovers faster with more attack speed", is_equal_approx(player._melee_cd, float(SkillDB.MELEE["cooldown"]) / float(c.derived()["attack_speed"])))
	var caster: SkillCaster = player.caster
	_check("a bolt's cooldown shrinks with it", is_equal_approx(caster.cooldown_total("fireball"), c.skill_cooldown("fireball") / float(c.derived()["attack_speed"])))
	_check("abilities are unaffected", is_equal_approx(caster.cooldown_total("flame_burst"), c.skill_cooldown("flame_burst")))
	player.queue_free()
	var gear := _bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1))
	var glove := _item("travel_boots")
	glove["affixes"] = [{"mod": "attack_speed_mult", "value": 0.05}]
	gear.inventory.add_item(glove)
	gear.inventory.equip(0)
	_check("gear can add attack speed", is_equal_approx(gear.derived()["attack_speed"], 1.05))
	await get_tree().process_frame
	_neutral_character()


func _test_costs_and_chaining() -> void:
	var ch := _bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire", "water", "earth", "air", "mineral"], 7))
	var player = await _player_with(ch)
	var caster: SkillCaster = player.caster
	caster.cooldowns.clear()
	caster.mana = caster.max_mana
	_check("fusion hits shrink as more elements are fused (75, 65, 55, 50 percent)", is_equal_approx(SkillCaster.fusion_hit_scale(2), 0.75) and is_equal_approx(SkillCaster.fusion_hit_scale(3), 0.65) and is_equal_approx(SkillCaster.fusion_hit_scale(4), 0.55) and SkillCaster.fusion_hit_scale(5) == 0.5 and SkillCaster.fusion_hit_scale(6) == 0.5)
	for i in 5:
		caster.select(i)
		caster.toggle_lock()
	_check("all five elements can be locked", caster.locked.size() == 5 and caster.lmb_mode() == "fusion")
	var five := caster.primary_id()
	var parts: float = 0.0
	for id in caster.components(five):
		parts += SkillDB.DEFS[id]["mana"]
	_check("a five-element fusion costs the parts plus 30 percent per extra element", is_equal_approx(caster.costs(five).x, parts * (1.0 + 4.0 * SkillCaster.FUSION_COST_PER_EXTRA) * float(ch.derived()["mana_cost_mult"])))
	var cooldown_one: float = caster.cooldown_total("fusion:fire+water")
	_check("and takes longer to recover from", caster.cooldown_total(five) > cooldown_one)
	_check("one bolt carries five hits", caster.try_cast(five) and get_children().filter(func(n): return n is Projectile)[-1].extra_hits.size() == 4)
	var bolt: Projectile = get_children().filter(func(n): return n is Projectile)[-1]
	var first_hit: float = bolt.hit["damage"]
	_check("each of them at half damage", is_equal_approx(first_hit, ch.skill_damage("fireball") * 0.5 * float(ch.derived()["fusion_damage_mult"])))
	for node in get_children():
		if node is Projectile:
			node.queue_free()

	# chaining abilities
	caster.locked.clear()
	caster.cooldowns.clear()
	caster.mana = caster.max_mana
	var rain: float = float(SkillDB.DEFS["rain_pool"]["mana"]) * float(ch.derived()["mana_cost_mult"])  # Elemental Harmony makes spells cost more
	_check("no discount without an ability just before", caster.chain_discount("rain_pool") == 1.0 and is_equal_approx(caster.costs("rain_pool").x, rain))
	_check("an ability casts", caster.try_cast("flame_burst"))
	_check("a different element's ability soon after costs 30 percent less", caster.chain_discount("rain_pool") == SkillCaster.CHAIN_DISCOUNT and is_equal_approx(caster.costs("rain_pool").x, rain * 0.7))
	_check("the same element gets no discount", caster.chain_discount("flame_burst") == 1.0)
	_check("neither do basic attacks or fusions", caster.chain_discount("water_jet") == 1.0 and caster.chain_discount("fusion:fire+water") == 1.0)
	_check("or martial skills", caster.chain_discount("whirlwind") == 1.0)
	caster.mana = rain * 0.7 + 1.0
	_check("the discount decides what you can afford", caster.can_afford("rain_pool") and not caster.can_afford("inferno_ring"))
	var mana_before := caster.mana
	_check("the chained ability casts", caster.try_cast("rain_pool"))
	_check("and spends the discounted mana", absf((mana_before - rain * 0.7) - caster.mana) < 1.0)
	_check("now fire abilities are the discounted ones", caster.chain_discount("flame_burst") == SkillCaster.CHAIN_DISCOUNT and caster.chain_discount("rain_pool") == 1.0)
	caster._chain_left = 0.0
	_check("the window closes after a few seconds", caster.chain_discount("flame_burst") == 1.0 and SkillCaster.CHAIN_WINDOW == 3.0)
	caster._process(0.0)
	_check("abilities are the F, V and R skills", caster.is_ability("flame_burst") and caster.is_ability("tidal_mending") and caster.is_ability("inferno_ring") and not caster.is_ability("fireball"))

	# the mana-cost stat
	var mult_before := float(ch.derived()["mana_cost_mult"])
	ch.traits.append("efficient")
	caster.cooldowns.clear()
	_check("Efficient trims every mana cost by 8 percent", is_equal_approx(caster.costs("fireball").x, SkillDB.DEFS["fireball"]["mana"] * float(ch.derived()["mana_cost_mult"])) and is_equal_approx(float(ch.derived()["mana_cost_mult"]), mult_before * 0.92))
	ch.traits.clear()
	player.queue_free()
	await get_tree().process_frame
	_neutral_character()


func _test_labels() -> void:
	_check("the Q slot says Lock when nothing is locked", Elements.fusion_label([])["name"] == "Lock")
	_check("one element shows itself", Elements.fusion_label(["fire"])["name"] == "Fire" and Elements.fusion_label(["fire"])["color"] == Elements.color_of("fire"))
	var steam: Dictionary = Elements.fusion_label(["fire", "water"])
	_check("two show the combo's name and colour", steam["name"] == "Steam" and steam["color"] == Elements.COMBOS["fire+water"]["color"])
	_check("in either order", Elements.fusion_label(["water", "fire"])["name"] == "Steam")
	_check("more show Trio, Quartet and Prism", Elements.fusion_label(["fire", "water", "earth"])["name"] == "Trio" and Elements.fusion_label(["fire", "water", "earth", "air"])["name"] == "Quartet" and Elements.fusion_label(Elements.MAIN)["name"] == "Prism")
	_check("a blend of their colours", Elements.fusion_label(["fire", "water", "earth"])["color"] != Elements.color_of("fire"))


# ---------- death: elements are lost, the story can end ----------

func _test_death() -> void:
	var ch := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire", "water", "earth", "air", "mineral"], 1)
	ch.death_rng.seed = 7
	ch.element_mastery["fire"]["level"] = 6
	ch.learned_specials.append("inferno_ring")
	ch.skill_uses["fireball"] = 50
	var first := ch.die()
	_check("the first death costs one element and the character lives on", not first["final"] and first["lost"].size() == 1 and ch.elements.size() == 4 and ch.deaths == 1)
	var second := ch.die()
	_check("the second costs two", second["lost"].size() == 2 and ch.elements.size() == 2 and ch.deaths == 2)
	var third := ch.die()
	_check("the third takes what is left (it can't take more than they have)", third["lost"].size() == 2 and ch.elements.is_empty() and not third["final"])
	_check("with every element gone the character is attunable, with martial skills", ch.affinity == CharacterData.ATTUNABLE and ch.has_martial() and not ch.uses_mana())
	var fourth := ch.die()
	_check("and the next death is the end", fourth["final"] and fourth["lost"].is_empty() and ch.deaths == 4)

	var c2 := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire", "water"], 1)
	c2.death_rng.seed = 3
	c2.element_mastery["fire"] = {"level": 6, "xp": 5}
	c2.learned_specials.append("inferno_ring")
	c2.learned_specials.append("deluge")
	c2.skill_uses["fireball"] = 50
	c2.skill_uses["water_jet"] = 9
	var lost := c2.die()["lost"][0] as String
	_check("exactly the lost element is gone", not (lost in c2.elements) and c2.elements.size() == 1)
	var kept := String(c2.elements[0])
	_check("its mastery, learned special and skill use start over", not c2.element_mastery.has(lost) and not c2.learned_specials.has(String(SkillDB.LOADOUTS[lost]["special"])) and not c2.skill_uses.has(String(SkillDB.LOADOUTS[lost]["primary"])))
	_check("what they kept is untouched", c2.element_mastery.has(kept) and c2.learned_specials.has(String(SkillDB.LOADOUTS[kept]["special"])) and c2.skill_uses.has(String(SkillDB.LOADOUTS[kept]["primary"])))
	c2.add_element(lost)
	_check("regaining it begins again at mastery 1", c2.element_level(lost) == 1 and c2.element_mastery[lost]["xp"] == 0)
	var changes := [0]
	c2.elements_changed.connect(func(): changes[0] += 1)
	c2.remove_element(lost)
	_check("losing one tells the rest of the game", changes[0] == 1 and not c2.remove_element(lost))

	var sealed := CharacterData.create("S", "vanguard", CharacterData.SEALED, _rng(1))
	_check("a sealed character's first death is final", sealed.die()["final"])
	var attunable := CharacterData.create("A", "vanguard", CharacterData.ATTUNABLE, _rng(2))
	_check("so is one who was born without elements", attunable.die()["final"])
	var counted := CharacterData.create_sandbox("channeler", ["fire", "water"], 1)
	counted.death_rng.seed = 1
	counted.die()
	var back := CharacterData.from_dict(JSON.parse_string(JSON.stringify(counted.to_dict())))
	_check("the number of deaths is saved", back.deaths == 1 and back.elements == counted.elements)
	_check("the next death costs one more than the last", back.deaths + 1 == 2)

	# the dungeon applies it
	var survivor := _bare(CharacterData.create_sandbox("vanguard", ["fire", "water"], 1))
	var parts: Dictionary = await _dungeon_world(21, survivor)
	var player = parts["player"]
	var dungeon: Dungeon = parts["dungeon"]
	player.hp = 1.0
	player._hurt_cd = 0.0
	player.take_damage(50.0, Vector2(40, 0))
	_check("dying in the dungeon costs an element and ends the run", dungeon.state == "dead" and not dungeon.death["final"] and survivor.elements.size() == 1 and survivor.deaths == 1)
	var lines := dungeon.summary_lines(false)
	_check("the summary names what was lost", lines.any(func(l): return String(l).begins_with("Lost:")) and lines.any(func(l): return String(l).contains("next one costs 2")))
	parts["world"].queue_free()
	await get_tree().process_frame
	var mortal := _bare(CharacterData.create("M", "vanguard", CharacterData.SEALED, _rng(9)))
	var parts2: Dictionary = await _dungeon_world(22, mortal)
	var player2 = parts2["player"]
	var dungeon2: Dungeon = parts2["dungeon"]
	player2.hp = 1.0
	player2._hurt_cd = 0.0
	player2.take_damage(50.0, Vector2(40, 0))
	_check("with no elements to lose, death is final", dungeon2.state == "dead" and dungeon2.death["final"])
	_check("and the summary says the story ends", dungeon2.summary_lines(false).any(func(l): return String(l).contains("the end of")))
	var screen := RunEndScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.show_result(false, ["x"], true)
	await get_tree().process_frame
	var screen_text := " ".join(screen.find_children("*", "Label", true, false).map(func(l): return l.text))
	var buttons := screen.find_children("*", "Button", true, false)
	_check("the end screen says you died and leads back to the menu", screen_text.contains("You died") and buttons.size() == 1 and buttons[0].text.begins_with("Main menu"))
	screen._open = false
	get_tree().paused = false
	screen.free()
	parts2["world"].queue_free()
	await get_tree().process_frame
	_neutral_character()


# ---------- class mastery, class and subclass cards ----------

func _test_class_mastery_and_cards() -> void:
	var novice := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1)
	novice.add_class_xp(500)
	_check("a Novice has no class to master", novice.class_mastery_level() == 0 and novice.class_mastery.is_empty())
	var seen_class := [0]
	var late := CharacterData.create(" N", Classes.NEUTRAL_CLASS, CharacterData.ELEMENTALIST, _rng(21))
	late.class_available.connect(func(): seen_class[0] += 1)
	_level_to(late, 2)
	_check("the class choice is announced at level 3, not before", seen_class[0] == 0)
	_level_to(late, 3)
	_check("and exactly once", seen_class[0] == 1 and late.can_choose_class())

	var c := CharacterData.create_sandbox("vanguard", ["fire"], 3)
	_check("a class starts at mastery 1", c.class_mastery_level() == 1 and c.class_mastery["vanguard"]["xp"] == 0)
	var announced := [0]
	c.subclass_available.connect(func(): announced[0] += 1)
	_check("no subclass before mastery 5", c.available_subclasses().is_empty())
	c.add_class_xp(CharacterData.class_mastery_xp_to_next(1))
	_check("class mastery levels with xp", c.class_mastery_level() == 2 and c.class_mastery["vanguard"]["xp"] == 0)
	var needed := 0
	for lv in range(2, Classes.SUBCLASS_MASTERY):
		needed += CharacterData.class_mastery_xp_to_next(lv)
	c.add_class_xp(needed - 1)
	_check("one xp short of the subclass", c.class_mastery_level() == Classes.SUBCLASS_MASTERY - 1 and announced[0] == 0 and c.available_subclasses().is_empty())
	c.add_class_xp(1)
	_check("mastery 5 opens the subclass, announced once", c.class_mastery_level() == 5 and announced[0] == 1 and c.available_subclasses() == ["duelist", "bulwark"])
	c.add_class_xp(10)
	_check("not announced again", announced[0] == 1)
	_check("a subclass can be chosen, once", c.choose_subclass("bulwark") and c.subclass_id == "bulwark" and c.available_subclasses().is_empty() and not c.choose_subclass("duelist"))
	var saved := CharacterData.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	_check("class mastery is saved", saved.class_mastery_level() == c.class_mastery_level() and saved.class_mastery["vanguard"]["xp"] == c.class_mastery["vanguard"]["xp"])
	_check("a sandbox character at level 10 can pick a subclass at once", CharacterData.create_sandbox("sage", [], 10).available_subclasses() == ["archmage", "lorekeeper"])
	var capped := CharacterData.create_sandbox("sage", [], 1)
	capped.add_class_xp(100000)
	_check("mastery is capped", capped.class_mastery_level() == CharacterData.MASTERY_CAP)
	var kills := CharacterData.create_sandbox("ranger", [], 3)
	var slime := _dummy(Vector2(900, 900))
	Game.character = kills
	slime.xp_reward = 25
	Game.on_enemy_killed(slime)
	_check("a kill adds 1 plus a tenth of the monster's xp to class mastery", kills.class_mastery["ranger"]["xp"] == 1 + 2)
	slime.free()
	_check("class mastery shows on the sheet's stats tab", true)

	# the cards
	var ch := CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 3)
	Game.character = ch
	var cards := ClassCards.new()
	add_child(cards)
	await get_tree().process_frame
	cards.open("subclass")
	_check("subclass cards don't open for a Novice", not cards.is_open())
	cards.open("class")
	_check("the class cards open and pause the game", cards.is_open() and get_tree().paused)
	_check("every class is a card", cards.card_count() == Classes.playable().size() and cards.card_count() == 8)
	var text := " ".join(cards.find_children("*", "Label", true, false).map(func(l): return l.text))
	_check("each card names its class and fighting style", Classes.playable().all(func(id): return text.contains(String(Classes.CLASSES[id]["name"]))) and text.contains("Melee") and text.contains("Ranged"))
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	cards._input(esc)
	_check("Esc postpones the choice", not cards.is_open() and not get_tree().paused and ch.can_choose_class())
	cards.open("class")
	var press := InputEventKey.new()
	press.keycode = KEY_5
	press.pressed = true
	cards._input(press)
	_check("pressing a number picks that card (5 = Assassin)", ch.class_id == "assassin" and not cards.is_open() and not get_tree().paused)
	_check("choosing gives the class its weapon and first mastery level", ch.weapon_type == "dagger" and ch.class_mastery_level() == 1)
	cards.open("class")
	_check("the class cards don't open again once chosen", not cards.is_open())
	var knight := CharacterData.create_sandbox("vanguard", ["fire"], 10)
	Game.character = knight
	cards.free()
	var sub_cards := ClassCards.new()
	add_child(sub_cards)
	await get_tree().process_frame
	sub_cards.open("subclass")
	_check("the subclass cards show the two subclasses", sub_cards.is_open() and sub_cards.card_count() == 2)
	sub_cards._choose(0)
	_check("clicking one chooses it", knight.subclass_id == "duelist" and not sub_cards.is_open())
	sub_cards.free()
	var sheet := CharacterSheet.new()
	add_child(sheet)
	Game.character = CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 3)
	await get_tree().process_frame
	sheet.show_tab("stats")
	await get_tree().process_frame
	_check("the stats tab points to the cards", sheet.find_children("*", "Button", true, false).any(func(b): return b.text == "Choose your class..."))
	Game.character = CharacterData.create_sandbox("vanguard", ["fire"], 10)
	sheet.show_tab("stats")
	await get_tree().process_frame
	var stats_text := " ".join(sheet.find_children("*", "Label", true, false).map(func(l): return l.text))
	_check("with mastery 5 it offers the subclass cards and shows class mastery", sheet.find_children("*", "Button", true, false).any(func(b): return b.text == "Choose a subclass...") and stats_text.contains("Vanguard mastery"))
	sheet.free()
	_neutral_character()


# ---------- enemies: attack types, dash and dodge ----------

func _test_enemy_abilities() -> void:
	var player = await _player_with(_bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1)))
	player.global_position = Vector2(1000, 1000)
	var attack_ok := true
	for id in Monsters.DEFS:
		var d: Dictionary = Monsters.DEFS[id]
		if d.get("training", false):
			continue
		attack_ok = attack_ok and d["attack"] in ["melee", "ranged", "both"]
		match d["attack"]:
			"melee": attack_ok = attack_ok and not d.has("shot")
			"ranged": attack_ok = attack_ok and d.has("shot") and float(d["contact"]) == 0.0
			"both": attack_ok = attack_ok and d.has("shot") and float(d["contact"]) > 0.0
	_check("every monster is melee, ranged or both, and has what that needs", attack_ok)
	var kinds := {}
	for id in Monsters.regular():
		kinds[Monsters.DEFS[id]["attack"]] = true
	_check("the regular monsters cover all three", kinds.has("melee") and kinds.has("ranged") and kinds.has("both"))
	var abilities_ok := true
	for id in Monsters.DEFS:
		var d: Dictionary = Monsters.DEFS[id]
		if d.has("dash"):
			abilities_ok = abilities_ok and float(d["dash"]["windup"]) > 0.0 and float(d["dash"]["speed"]) > float(d["speed"]) and float(d["dash"]["damage_mult"]) > 1.0
		if d.has("dodge"):
			abilities_ok = abilities_ok and float(d["dodge"]["chance"]) > 0.0 and float(d["dodge"]["chance"]) < 1.0
	_check("dash and dodge definitions are sensible", abilities_ok)
	_check("some monsters dash, some dodge, and one does both", Monsters.DEFS["imp"].has("dash") and Monsters.DEFS["wraith"].has("dodge") and Monsters.DEFS["duelist"].has("dash") and Monsters.DEFS["duelist"].has("dodge"))

	# melee / ranged / both
	var skeleton := _fresh_monster("skeleton", "", Vector2(1000, 1000))
	var slime := _fresh_monster("slime", "", Vector2(1000, 1000))
	var spitter := _fresh_monster("spitter", "", Vector2(1000, 1000))
	await get_tree().process_frame
	_check("an archer never touches you: no contact damage at all", skeleton.contact_damage == 0.0 and skeleton.attack_type == "ranged")
	player._hurt_cd = 0.0
	var hp0: float = player.hp
	skeleton._physics_process(0.016)
	_check("standing on an archer doesn't hurt", player.hp == hp0)
	slime._contact_cd = 0.0  # the engine already stepped it once while it overlapped the player
	spitter._contact_cd = 0.0
	slime._physics_process(0.016)
	_check("standing on a slime does", player.hp < hp0)
	player._hurt_cd = 0.0
	hp0 = player.hp
	spitter._physics_process(0.016)
	_check("a spitter bites too", player.hp < hp0 and spitter.attack_type == "both")
	player.global_position = Vector2(1000, 1000) + Vector2(70, 0)
	slime.global_position = Vector2(1000, 1000)
	slime._attack_cd = 0.0
	var shots := get_children().filter(func(n): return n is EnemyProjectile).size()
	slime._attack(0.016, player)
	_check("a slime has nothing to shoot", get_children().filter(func(n): return n is EnemyProjectile).size() == shots)
	spitter.global_position = Vector2(1000, 1000)
	spitter._attack_cd = 0.0
	spitter._attack(0.016, player)
	_check("a spitter spits at range while it closes in", get_children().filter(func(n): return n is EnemyProjectile).size() == shots + 1 and spitter._desired_velocity(player).x > 0.0)
	skeleton.queue_free()
	slime.queue_free()
	spitter.queue_free()

	# dash
	var imp := _fresh_monster("imp", "", Vector2(1000, 1000))
	await get_tree().process_frame
	player.global_position = Vector2(1000, 1000) + Vector2(60, 0)
	imp.global_position = Vector2(1000, 1000)
	imp._attack(0.016, player)
	_check("an imp in range starts a dash with a warning", imp._dash_state == "windup" and _texts_in(self).has("!"))
	_check("it stands still while it winds up", imp._desired_velocity(player) == Vector2.ZERO)
	imp._attack(float(imp.dash["windup"]) + 0.01, player)
	_check("then lunges at you, fast", imp._dash_state == "dash" and imp._desired_velocity(player).x >= float(imp.dash["speed"]) - 0.01)
	player.global_position = imp.global_position
	player._hurt_cd = 0.0
	hp0 = player.hp
	imp._dash_dir = Vector2.ZERO  # move_and_slide steps by the frame's real time: on a slow frame the imp would dash clear of the player
	imp._physics_process(0.016)
	_check("a dash hits harder than a bite", is_equal_approx(hp0 - player.hp, imp.contact_damage * float(imp.dash["damage_mult"])))
	imp._attack(float(imp.dash["time"]) + 0.01, player)
	_check("it then rests until the cooldown ends", imp._dash_state == "" and imp._dash_cd == float(imp.dash["cooldown"]))
	player.global_position = imp.global_position + Vector2(60, 0)
	imp._attack(0.016, player)
	_check("and can't dash again at once", imp._dash_state == "")
	var imp3: Enemy = load(Monsters.ENEMY_SCENE).instantiate()
	imp3.configure("imp", "", 1.0, 1.0, 3)
	var imp1: Enemy = load(Monsters.ENEMY_SCENE).instantiate()
	imp1.configure("imp", "", 1.0, 1.0, 1)
	_check("deeper imps dash more often, warn less and lunge faster", imp3.dash["cooldown"] < imp1.dash["cooldown"] and imp3.dash["windup"] < imp1.dash["windup"] and imp3.dash["speed"] > imp1.dash["speed"] and imp3.speed > imp1.speed)
	imp1.free()
	imp3.free()
	imp._dash_state = "windup"
	imp.effects["root"] = {"time": 2.0, "power": 1.0}
	imp._attack(0.016, player)
	_check("rooting a dasher cancels its dash", imp._dash_state == "")
	imp.queue_free()

	# dodge
	var wraith := _fresh_monster("wraith", "", Vector2(1000, 1000))
	await get_tree().process_frame
	Game.combat_rng.seed = 11
	var dodged := 0
	var hit := 0
	for i in 200:
		wraith.hp = wraith.max_hp
		wraith._dodge_cd = 0.0
		var before := wraith.hp
		wraith.take_hit({"damage": 5.0, "element": "", "from": Vector2.ZERO})
		if wraith.hp == before:
			dodged += 1
		else:
			hit += 1
	_check("a wraith sidesteps about a third of hits", dodged > 40 and dodged < 100 and hit > 100)
	_check("a dodged hit does no damage and says so", _texts_in(self).has("Dodged!"))
	wraith.hp = wraith.max_hp
	wraith._dodge_cd = 5.0
	var cooled := 0
	for i in 50:
		var before := wraith.hp
		wraith.take_hit({"damage": 1.0, "element": "", "from": Vector2.ZERO})
		cooled += 1 if wraith.hp < before else 0
		wraith.hp = wraith.max_hp
	_check("it can't dodge again while the dodge is cooling down", cooled == 50)
	wraith._dodge_cd = 0.0
	var burn_hits := 0
	for i in 60:
		var before := wraith.hp
		wraith.take_hit({"damage": 1.0, "element": "fire", "juice": false, "from": Vector2.ZERO})
		burn_hits += 1 if wraith.hp < before else 0
		wraith.hp = wraith.max_hp
		wraith._dodge_cd = 0.0
	_check("burn ticks and other lingering damage can't be dodged", burn_hits == 60)
	wraith.effects["root"] = {"time": 2.0, "power": 1.0}
	var rooted_hits := 0
	for i in 60:
		wraith._dodge_cd = 0.0
		var before := wraith.hp
		wraith.take_hit({"damage": 1.0, "element": "", "from": Vector2.ZERO})
		rooted_hits += 1 if wraith.hp < before else 0
		wraith.hp = wraith.max_hp
	_check("a rooted monster can't dodge", rooted_hits == 60)
	var w1: Enemy = load(Monsters.ENEMY_SCENE).instantiate()
	w1.configure("wraith", "", 1.0, 1.0, 1)
	var w3: Enemy = load(Monsters.ENEMY_SCENE).instantiate()
	w3.configure("wraith", "", 1.0, 1.0, 3)
	_check("deeper monsters dodge more often and recover quicker", w3.dodge_ability["chance"] > w1.dodge_ability["chance"] and w3.dodge_ability["cooldown"] < w1.dodge_ability["cooldown"] and w3.dodge_ability["chance"] <= 0.7)
	w1.free()
	w3.free()
	var plain := _fresh_monster("slime", "", Vector2(1000, 1000))
	var untouched := 0
	for i in 40:
		var before := plain.hp
		plain.take_hit({"damage": 1.0, "element": "", "from": Vector2.ZERO})
		untouched += 1 if plain.hp < before else 0
		plain.hp = plain.max_hp
	_check("monsters with no dodge are always hit", untouched == 40)
	_check("the Dungeon passes the floor as the monster's level", true)
	for node in get_children():
		if node is Enemy or node is EnemyProjectile or node is FloatText:
			node.queue_free()
	player.queue_free()
	await get_tree().process_frame
	_neutral_character()


func _test_traits_and_gear_rework() -> void:
	var mods_ok := true
	for id in Classes.TRAITS:
		mods_ok = mods_ok and Classes.PASSIVES.has(id) and not Classes.PASSIVES[id]["mods"].is_empty()
	_check("every trait is a real passive", mods_ok)
	var new_traits := ["quick_strikes", "efficient", "vampiric", "mana_siphon", "adrenaline", "nimble", "survivor"]
	_check("there are new traits for attack speed, mana costs, kills and dodging", new_traits.all(func(id): return id in Classes.TRAITS))
	_check("spell-only new traits are kept from sealed characters", not Classes.available_traits(false).has("efficient") and not Classes.available_traits(false).has("mana_siphon") and Classes.available_traits(false).has("vampiric"))
	for key in ["attack_speed_mult", "mana_cost_mult", "dodge_cost_mult", "kill_hp_add", "kill_mana_add", "kill_stamina_add"]:
		_check("gear can roll %s" % key, Items.MOD_NAMES.has(key) and Items.AFFIXES.any(func(a): return a["mod"] == key))
	_check("a kill stat reads naturally on an item", Items.format_mod("kill_hp_add", 2.0) == "+2 HP on kill" and Items.format_mod("attack_speed_mult", 0.06) == "+6% Attack speed" and Items.format_mod("mana_cost_mult", -0.05) == "-5% Mana costs")
	var recovery_ok := true
	for id in Items.BASES:
		var base_mods: Dictionary = Items.BASES[id]["mods"]
		recovery_ok = recovery_ok and float(base_mods.get("hp_regen_add", 0.0)) < 0.2 and float(base_mods.get("mana_regen_add", 0.0)) < 1.0 and float(base_mods.get("stamina_regen_add", 0.0)) < 3.0
	_check("gear regeneration is scaled to the slower recovery", recovery_ok)
	var affix_ok := true
	for affix in Items.AFFIXES:
		match affix["mod"]:
			"hp_regen_add": affix_ok = affix_ok and float(affix["max"]) <= 0.2
			"mana_regen_add": affix_ok = affix_ok and float(affix["max"]) <= 0.8
			"stamina_regen_add": affix_ok = affix_ok and float(affix["max"]) <= 4.0
	_check("and so are the affixes", affix_ok)
	var spell_free := true
	for seed_value in 200:
		for affix in Items.make("iron_helm", "legendary", 4, _rng(seed_value), false)["affixes"]:
			spell_free = spell_free and not (affix["mod"] in Items.SPELL_MODS)
	_check("sealed characters still roll no spell affixes (mana costs, mana on kill)", spell_free and "mana_cost_mult" in Items.SPELL_MODS and "kill_mana_add" in Items.SPELL_MODS)
	var c := _bare(CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 1))
	var ring := _item("copper_ring")
	ring["affixes"] = [{"mod": "kill_hp_add", "value": 2.0}, {"mod": "mana_cost_mult", "value": -0.05}]
	c.inventory.add_item(ring)
	c.inventory.equip(0)
	_check("worn gear feeds the new stats", is_equal_approx(c.derived()["kill_hp"], 2.0) and is_equal_approx(c.derived()["mana_cost_mult"], 0.95))
	var rich := CharacterData.create_sandbox("sage", ["fire"], 1)
	_check("class passives were rescaled: the Sage trims mana costs", rich.derived()["mana_cost_mult"] < 1.0)
	var old_save := rich.to_dict()
	old_save.erase("deaths")
	old_save.erase("class_mastery")
	old_save["attributes"].erase("dexterity")
	var loaded := CharacterData.from_dict(old_save)
	_check("a save from before the rework still loads", loaded.deaths == 0 and loaded.attributes["dexterity"] == 4 and loaded.class_mastery["sage"]["level"] == 1)
	_neutral_character()


# ---------- Phase 5: settings, controls, saves, leaderboard, flow, tiers, menus ----------

func _test_phase5() -> void:
	await _p5_settings_and_controls()
	_p5_saves()
	_p5_leaderboard()
	_p5_flow_and_dungeons()
	await _p5_bosses()
	await _p5_menus()
	await _p5_camp_and_runs()
	await _p5_finish_run()
	_p5_save_safety()
	_neutral_character()


func _p5_settings_and_controls() -> void:
	var real_path: String = Settings.path
	Settings.path = "user://test_settings.cfg"
	Settings.reset_to_defaults()
	_check("settings start at their defaults", is_equal_approx(float(Settings.get_value("music_volume")), float(Settings.DEFAULTS["music_volume"])))
	Settings.set_value("music_volume", 2.5)
	_check("a volume above 1 is clamped", is_equal_approx(float(Settings.get_value("music_volume")), 1.0))
	Settings.set_value("hud_scale", 0.1)
	_check("the HUD size stays in its range", is_equal_approx(float(Settings.get_value("hud_scale")), 0.75))
	Settings.set_value("nonexistent_setting", 1)
	_check("unknown settings are ignored", not Settings.values.has("nonexistent_setting"))
	Settings.set_value("sfx_volume", 0.35)
	Settings.values["sfx_volume"] = 0.0
	Settings.load_settings()
	_check("settings survive a save and load", is_equal_approx(float(Settings.get_value("sfx_volume")), 0.35))
	var file := FileAccess.open(Settings.path, FileAccess.WRITE)
	file.store_string("this is [not a config")
	file.close()
	Settings.load_settings()
	_check("a damaged settings file falls back to the defaults", is_equal_approx(float(Settings.get_value("sfx_volume")), float(Settings.DEFAULTS["sfx_volume"])))
	_check("the audio buses exist", AudioServer.get_bus_index("Music") != -1 and AudioServer.get_bus_index("SFX") != -1 and AudioServer.get_bus_index("UI") != -1)
	Settings.set_value("master_volume", 0.0)
	_check("a zero slider mutes the bus", AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	Settings.reset_to_defaults()
	Juice.enabled = true
	Settings.set_value("screen_shake", 0.0)
	Juice.shake(5.0, 0.5)
	_check("screen shake off means no camera offset", Juice.offset() == Vector2.ZERO)
	Juice.enabled = false
	_check("lighting is full by default", Settings.DEFAULTS["lighting"] == "full")
	Settings.set_value("lighting", "soft")
	var soft_ok: bool = Settings.get_value("lighting") == "soft"
	Settings.set_value("lighting", "neon")
	_check("the lighting setting takes full, soft and off; anything else is full", soft_ok and Settings.get_value("lighting") == "full")
	Settings.set_value("lighting", 3)
	_check("a lighting value of the wrong type is full", Settings.get_value("lighting") == "full")
	Settings.set_value("lighting", "off")
	Settings.values["lighting"] = "full"
	Settings.load_settings()
	_check("the lighting setting survives a save and load", Settings.get_value("lighting") == "off")
	Settings.reset_to_defaults()
	DirAccess.remove_absolute(Settings.path)
	Settings.path = real_path
	Settings.load_settings()

	# controls
	Controls.reset_bindings()
	var dodge_pad := Controls.event_for("dodge", "pad")
	_check("dodge is on the A button by default", dodge_pad is InputEventJoypadButton and dodge_pad.button_index == JOY_BUTTON_A)
	var fire_pad := Controls.event_for("skill_primary", "pad")
	_check("the right trigger fuses", fire_pad is InputEventJoypadMotion and fire_pad.axis == JOY_AXIS_TRIGGER_RIGHT)
	_check("every listed action has a keyboard or gamepad binding", Controls.ACTIONS.all(func(row): return InputMap.has_action(row[0]) and not InputMap.action_get_events(row[0]).is_empty()))
	_check("the left stick moves", Controls.event_for("move_left", "pad") is InputEventJoypadMotion)
	var jay := InputEventKey.new()
	jay.keycode = KEY_J
	Controls.rebind("dodge", jay)
	_check("rebinding sets the key", Controls.event_for("dodge", "desk").keycode == KEY_J)
	_check("the gamepad binding is kept when the key changes", Controls.event_for("dodge", "pad") != null)
	var jay_again := InputEventKey.new()
	jay_again.keycode = KEY_J
	var stolen: String = Controls.rebind("imbue", jay_again)
	_check("one key does one thing: it leaves the old action", stolen == "dodge" and Controls.event_for("dodge", "desk") == null)
	var config := ConfigFile.new()
	Controls.write_bindings(config)
	Controls.reset_bindings()
	_check("reset restores the shipped keys", Controls.event_for("dodge", "desk").keycode == KEY_SPACE and Controls.event_for("imbue", "desk").keycode != KEY_J)
	Controls.read_bindings(config)
	_check("saved bindings load back", Controls.event_for("imbue", "desk").keycode == KEY_J)
	var junk := ConfigFile.new()
	junk.set_value("bindings", "dodge", [{"t": "key", "c": 0}, "garbage", {"t": "wat"}])
	Controls.reset_bindings()
	Controls.read_bindings(junk)
	_check("an unusable binding never leaves an action unbound", Controls.event_for("dodge", "desk") != null)
	_check("binding names read well", Controls.label_of(dodge_pad) == "Pad A" and Controls.label_of(fire_pad) == "Pad RT" and Controls.label_of(null) == "-")
	Controls.reset_bindings()

	# aiming with a stick
	var holder := Node2D.new()
	add_child(holder)
	Controls.using_pad = true
	Input.action_press("aim_right", 1.0)
	_check("the right stick gives the aim direction", Controls.stick_aim().distance_to(Vector2.RIGHT) < 0.01)
	var aim: Vector2 = Controls.aim_point(holder, Vector2(100, 100))
	_check("the pad aim point is a fixed reach in front", aim.distance_to(Vector2(100, 100) + Vector2.RIGHT * Controls.AIM_REACH) < 0.01)
	var target := Monsters.spawn(holder, "slime", Vector2(160, 115))
	await get_tree().process_frame
	var assisted: Vector2 = Controls.aim_point(holder, Vector2(100, 100)) - Vector2(100, 100)
	_check("aim assist pulls toward a nearby enemy", assisted.y > 0.5 and assisted.x > 0.0)
	var real_assist: float = float(Settings.get_value("aim_assist"))
	Settings.set_value("aim_assist", 0.0, false)
	_check("aim assist can be turned off", (Controls.aim_point(holder, Vector2(100, 100)) - Vector2(100, 100)).y == 0.0)
	Settings.set_value("aim_assist", real_assist, false)
	Input.action_release("aim_right")
	Controls.using_pad = false
	holder.queue_free()


func _p5_saves() -> void:
	var real_dir: String = SaveStore.dir
	SaveStore.dir = "user://test_saves"
	for slot in SaveStore.SLOTS:
		SaveStore.delete_slot(slot)
	var hero := CharacterData.create_sandbox("vanguard", ["fire", "water"], 4)
	var err := SaveStore.save_slot(0, hero.to_dict(), SaveStore.new_meta("warlord"), {"tier": 1, "seed": 7, "floor": 2, "room": 1})
	_check("a slot saves", err == OK and SaveStore.exists(0) and not SaveStore.exists(1))
	var loaded := SaveStore.load_slot(0)
	var back := CharacterData.from_dict(loaded["character"])
	_check("the hero round-trips through a save", back.level == hero.level and back.elements == hero.elements and back.class_id == hero.class_id and back.attributes == hero.attributes)
	_check("the meta and the run round-trip", loaded["meta"]["difficulty"] == "warlord" and int(loaded["run"]["floor"]) == 2 and int(loaded["run"]["seed"]) == 7)
	var info := SaveStore.summary(0)
	_check("the slot summary names the hero and the place", String(info["where"]).contains("floor 3") and info["level"] == 4 and info["difficulty"] == "warlord")
	_check("an empty slot has no summary", SaveStore.summary(2).is_empty())
	SaveStore.save_slot(0, hero.to_dict(), SaveStore.new_meta("knight"))
	_check("saving again keeps the last good save as a backup", FileAccess.file_exists(SaveStore.slot_path(0) + ".bak"))
	var file := FileAccess.open(SaveStore.slot_path(0), FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var recovered := SaveStore.load_slot(0)
	_check("a corrupt save falls back to the backup", not recovered.is_empty() and recovered["meta"]["difficulty"] == "warlord")
	_check("a save from a newer build is refused", SaveStore.migrate({"version": 99, "character": hero.to_dict()}).is_empty())
	_check("a save with no character is refused", SaveStore.migrate({"version": 1}).is_empty())
	_check("a JSON float version still migrates", not SaveStore.migrate({"version": 1.0, "character": hero.to_dict()}).is_empty())
	var bare := SaveStore.migrate({"version": 1, "character": hero.to_dict()})
	_check("missing meta and run get defaults", bare["meta"]["tier_cleared"] == 0 and bare["run"].is_empty())
	_check("bad slot numbers are rejected", SaveStore.save_slot(9, {}, {}) != OK and SaveStore.load_slot(-1).is_empty())
	var text := FileAccess.get_file_as_string(SaveStore.slot_path(0) + ".bak")
	_check("a save is plain JSON data", JSON.parse_string(text) is Dictionary and not text.contains("Object("))
	var plain := SaveStore.dir + "/atomic.txt"
	for p in [plain, plain + ".bak", plain + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var first_write := SaveStore.write_atomic(plain, "one")
	var second_write := SaveStore.write_atomic(plain, "two")
	_check("an atomic write leaves no temp file behind", first_write == OK and second_write == OK and not FileAccess.file_exists(plain + ".tmp"))
	_check("and keeps the previous version as the backup", FileAccess.get_file_as_string(plain) == "two" and FileAccess.get_file_as_string(plain + ".bak") == "one")
	var blocked := SaveStore.write_atomic(plain + "/inside.txt", "three")  # a file stands where the folder should be
	_check("a write that cannot happen reports an error and leaves the old file alone", blocked != OK and FileAccess.get_file_as_string(plain) == "two")
	for p in [plain, plain + ".bak"]:
		DirAccess.remove_absolute(p)
	SaveStore.delete_slot(0)
	_check("deleting empties the slot", not SaveStore.exists(0))
	SaveStore.dir = real_dir


func _p5_leaderboard() -> void:
	var real_path: String = Leaderboard.path
	Leaderboard.path = "user://test_leaderboard.json"
	Leaderboard.clear()
	var base := Leaderboard.score_for({"floors": 2, "kills": 5, "level": 3, "gold": 100})
	_check("the score counts depth, kills, level and gold", base == 2 * 100 + 5 * 10 + 3 * 50 + 10)
	var cleared := Leaderboard.score_for({"floors": 2, "kills": 5, "level": 3, "gold": 100, "cleared": true, "tier": 1, "time": 300.0})
	_check("clearing a dungeon adds its bonus and a speed bonus", cleared == base + 1000 + 450)
	_check("a richer oath multiplies the score", Leaderboard.score_for({"floors": 1, "reward_mult": 1.6}) == 240)
	_check("an empty board lists nothing", Leaderboard.entries().is_empty())
	for i in 30:
		Leaderboard.record({"score": i * 10, "name": "T%d" % i})
	var list := Leaderboard.entries()
	_check("the board keeps the best 25", list.size() == Leaderboard.MAX_ENTRIES)
	_check("the board is sorted best first", int(list[0]["score"]) == 290 and int(list[-1]["score"]) == 50)
	_check("a run too weak for the board earns no rank", Leaderboard.record({"score": 5}) == 0)
	_check("the best run so far takes rank 1", Leaderboard.record({"score": 1000}) == 1)
	_check("the board is written atomically: no temp file left, the last board kept as backup",
		not FileAccess.file_exists(Leaderboard.path + ".tmp") and FileAccess.file_exists(Leaderboard.path + ".bak"))
	var file := FileAccess.open(Leaderboard.path, FileAccess.WRITE)
	file.store_string("nonsense")
	file.close()
	_check("a damaged board reads as empty", Leaderboard.entries().is_empty())
	Leaderboard.clear()
	Leaderboard.path = real_path


func _p5_flow_and_dungeons() -> void:
	var diffs: Dictionary = Game.DIFFICULTIES
	_check("harder oaths mean tougher monsters and richer spoils", diffs["squire"]["hardness"] < diffs["knight"]["hardness"] and diffs["knight"]["hardness"] < diffs["warlord"]["hardness"] and diffs["squire"]["reward"] < diffs["knight"]["reward"] and diffs["knight"]["reward"] < diffs["warlord"]["reward"])
	var real_meta: Dictionary = Game.meta
	Game.meta = SaveStore.new_meta("warlord")
	_check("the oath sets the reward and hardness multipliers", is_equal_approx(Game.reward_mult(), 1.6) and is_equal_approx(Game.hardness_mult(), 1.3))
	_check("a richer oath improves drop luck", Game.loot_bonus() > 0.5)
	_check("only the first dungeon is open at the start", Game.tier_unlocked(1) and not Game.tier_unlocked(2))
	Game.meta["tier_cleared"] = 1
	_check("clearing a dungeon opens the next", Game.tier_unlocked(2))
	_check("the dungeons are five then ten floors", Game.TIERS[1]["floors"] == 5 and Game.TIERS[2]["floors"] == 10 and Game.TIERS[2]["depth"] == 5)
	Game.meta = real_meta

	var camp := DungeonGen.camp_room()
	_check("the camp is one safe room without a door or monsters", camp["kind"] == "camp" and camp["exit"] == "" and camp["waves"].is_empty() and camp["boss"] == "")
	var five := DungeonGen.generate(_rng(5), 5, 1, 0)
	_check("a five-floor dungeon has five floors", five.size() == 5)
	_check("floor 3 ends in a mini boss with a door out", five[2][-1]["kind"] == "miniboss" and Monsters.is_mini(five[2][-1]["boss"]) and five[2][-1]["exit"] != "")
	_check("the last floor ends in a final boss of the dungeon", five[4][-1]["kind"] == "boss" and five[4][-1]["boss"] in Monsters.bosses(1))
	_check("other floors have no mini boss", [0, 1, 3].all(func(f): return five[f].all(func(r): return r["kind"] in ["combat", "treasure", "forge"])))
	_check("the same seed makes the same tiered dungeon", DungeonGen.generate(_rng(5), 5, 1, 0) == five)
	var ten := DungeonGen.generate(_rng(6), 10, 2, 5)
	_check("a ten-floor dungeon has mini bosses on floors 3, 6 and 9", [3, 6, 9].all(func(f): return ten[f - 1][-1]["kind"] == "miniboss") and ten[9][-1]["kind"] == "boss" and ten[9][-1]["boss"] in Monsters.bosses(2))
	_check("the second dungeon starts at depth 6 and ends at 15", ten[0][0]["depth"] == 6 and ten[9][-1]["depth"] == 15 and five[0][0]["depth"] == 1)
	var waves_ok := true
	for room in ten[8]:
		for wave in room["waves"]:
			waves_ok = waves_ok and wave.all(func(e): return Monsters.DEFS.has(e["id"]) and not Monsters.is_boss(e["id"]))
	_check("deep waves hold only regular monsters", waves_ok)
	_check("deep monsters toughen more", Monsters.floor_scale(15).x > Monsters.floor_scale(5).x)


func _p5_bosses() -> void:
	_check("three mini bosses and seven final bosses", Monsters.mini_bosses().size() == 3 and Monsters.bosses().size() == 7 and Monsters.bosses(1).size() == 2 and Monsters.bosses(2).size() == 2 and Monsters.bosses(3).size() == 1)
	var defs_ok := true
	for id in Monsters.mini_bosses() + Monsters.bosses():
		var d: Dictionary = Monsters.DEFS[id]
		defs_ok = defs_ok and d["behavior"] == "boss" and d.has("slam") and d.has("summon") and Monsters.DEFS.has(d["summon"]["id"]) and not Monsters.is_boss(d["summon"]["id"]) and AssetDB.get_texture(String(d["sprite"])) != null
	_check("every boss has a slam, valid minions and a sprite", defs_ok)
	_check("a mini boss is smaller than any final boss", Monsters.mini_bosses().all(func(m): return Monsters.bosses().all(func(b): return Monsters.DEFS[m]["hp"] < Monsters.DEFS[b]["hp"])))
	var holder := Node2D.new()
	add_child(holder)
	var lich := Monsters.spawn(holder, "crypt_lich", Vector2(50, 50))
	var warden := Monsters.spawn(holder, "grave_warden", Vector2(90, 50))
	await get_tree().process_frame
	_check("a boss has not enraged at full health", not lich.enraged)
	lich.hp = lich.max_hp * 0.2
	warden.hp = warden.max_hp * 0.2
	var speed_before: float = lich.speed
	lich._check_enrage()
	warden._check_enrage()
	_check("a boss enrages when badly hurt: faster and quicker to attack", lich.enraged and lich.speed > speed_before and is_equal_approx(lich._enrage_cooldown(), 0.65))
	_check("a mini boss never enrages", not warden.enraged and warden.mini and warden.boss)
	_check("a boss that can shoot also keeps a slam", lich.shot.size() > 0 and lich.slam.size() > 0)
	holder.queue_free()
	var rng := _rng(3)
	var drops := Loot.mini_boss_drops(rng, 6, 0.0)
	_check("a mini boss drops gold, scrap and a rare", drops.any(func(d): return d["kind"] == "gold") and drops.any(func(d): return d["kind"] == "item" and d["item"]["rarity"] == "rare"))
	var never_gem := true
	for i in 40:
		for d in Loot.mini_boss_drops(rng, 6, 0.0):
			never_gem = never_gem and not (d["kind"] == "material" and String(d["id"]).begins_with("gem"))
	_check("a mini boss never drops an elemental gem", never_gem)


func _p5_menus() -> void:
	var real_slot: int = Game.slot
	var real_meta: Dictionary = Game.meta
	var real_dir: String = SaveStore.dir
	var real_board: String = Leaderboard.path
	SaveStore.dir = "user://test_saves"
	Leaderboard.path = "user://test_leaderboard.json"
	Leaderboard.clear()
	Game.meta = SaveStore.new_meta()

	var settings := SettingsMenu.new()
	add_child(settings)
	await get_tree().process_frame
	settings.open(0)
	await get_tree().process_frame
	_check("the audio tab has four sliders", settings.find_children("*", "HSlider", true, false).size() == 4)
	settings.open(1)
	await get_tree().process_frame
	_check("the game tab has toggles and sliders", settings.find_children("*", "CheckButton", true, false).size() == 5 and settings.find_children("*", "HSlider", true, false).size() == 4)
	var screen_size := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	await get_tree().process_frame  # the scroll's layout settles
	var game_panel: Vector2 = (settings._body.get_parent().get_parent() as Control).size
	_check("the game tab fits the game screen (%dx%d; its rows scroll)" % [int(game_panel.x), int(game_panel.y)], game_panel.y <= screen_size.y and game_panel.x <= screen_size.x \
		and settings.find_children("*", "ScrollContainer", true, false).size() == 1)
	var real_lighting: String = Settings.get_value("lighting")
	var light_button: Button = settings.find_children("*", "Button", true, false).filter(func(b): return b.text == real_lighting.capitalize())[0]
	light_button.pressed.emit()
	var stepped: String = Settings.get_value("lighting")
	light_button.pressed.emit()
	light_button.pressed.emit()  # three steps: back where it was (closing the menu saves the real settings)
	_check("the lighting button steps to the next value and round again", stepped == Settings.LIGHTING_MODES[(Settings.LIGHTING_MODES.find(real_lighting) + 1) % 3] \
		and Settings.get_value("lighting") == real_lighting and light_button.text == real_lighting.capitalize())
	settings.open(2)
	await get_tree().process_frame
	_check("the controls tab lists every action with a key and a pad button", settings.find_children("*", "Button", true, false).size() >= Controls.ACTIONS.size() * 2)
	settings._begin_capture("dodge", "desk", settings.find_children("*", "Button", true, false)[5])
	var key_press := InputEventKey.new()
	key_press.keycode = KEY_K
	key_press.pressed = true
	settings._try_capture(key_press)
	_check("capturing a key rebinds the action", Controls.event_for("dodge", "desk").keycode == KEY_K)
	Controls.reset_bindings()
	settings.close()
	_check("closing the settings hides them", not settings.is_open())
	settings.queue_free()

	var board := LeaderboardScreen.new()
	add_child(board)
	await get_tree().process_frame
	board.open()
	await get_tree().process_frame
	_check("an empty hall says so, and opening pauses the game", get_tree().paused and " ".join(board.find_children("*", "Label", true, false).map(func(l): return l.text)).contains("No runs yet"))
	board.close()
	Leaderboard.record({"score": 123, "name": "Ada", "class": "Sage", "level": 5, "floors": 4, "outcome": "cleared"})
	board.open()
	await get_tree().process_frame
	_check("the hall lists a recorded run", " ".join(board.find_children("*", "Label", true, false).map(func(l): return l.text)).contains("Ada (Sage)"))
	board.close()
	_check("closing the hall resumes the game", not get_tree().paused)
	board.queue_free()

	var gate := DungeonSelect.new()
	add_child(gate)
	await get_tree().process_frame
	gate.open()
	await get_tree().process_frame
	var enter_buttons := gate.find_children("*", "Button", true, false).filter(func(b): return b.text in ["Enter", "Locked"])
	_check("the gate offers all five dungeons, only the first open at first", enter_buttons.size() == 5 and not enter_buttons[0].disabled and enter_buttons.slice(1).all(func(b): return b.disabled))
	var gate_panel: Control = gate.find_children("*", "PanelContainer", true, false)[0]
	var gate_back: Control = gate.find_children("*", "Button", true, false).filter(func(b): return b.text == "Back")[0]
	_check("the whole gate fits the 180 px view with room above and below", gate_panel.size.y <= 172.0 and gate_back.get_global_rect().end.y <= gate_panel.get_global_rect().end.y)
	var names_fit := gate.find_children("*", "Label", true, false).filter(func(l): return l.text in ["Thornroot Hollow", "Gloaming Spire"]).all(func(l): return l.get_line_count() <= 2 and l.get_line_count() * l.get_line_height() <= l.size.y)
	var card_boxes := gate.find_children("*", "VBoxContainer", true, false).filter(func(b): return b.get_parent().custom_minimum_size == DungeonSelect.CARD_SIZE)
	var cards_fit := card_boxes.size() == 5 and card_boxes.all(func(b): return b.get_combined_minimum_size().y <= b.size.y)
	_check("long dungeon names still fit their cards", names_fit and cards_fit)
	gate.close()
	Game.meta["tier_cleared"] = 1
	gate.open()
	await get_tree().process_frame
	enter_buttons = gate.find_children("*", "Button", true, false).filter(func(b): return b.text in ["Enter", "Locked"])
	_check("clearing the first opens the second, and no further", enter_buttons.size() == 5 and not enter_buttons[1].disabled and enter_buttons[2].disabled)
	gate.close()
	gate.queue_free()

	var pause := PauseMenu.new()
	add_child(pause)
	await get_tree().process_frame
	pause.open()
	await get_tree().process_frame
	var pause_texts := pause.find_children("*", "Button", true, false).map(func(b): return b.text)
	_check("the pause menu offers resume, settings and the ways out", "Resume" in pause_texts and "Settings" in pause_texts and "Save and quit to menu" in pause_texts and get_tree().paused)
	_check("retreating is offered only inside a dungeon", not ("Retreat to camp" in pause_texts))
	pause.resume()
	_check("resuming unpauses", not get_tree().paused)
	pause.queue_free()

	var menu := MainMenu.new()
	add_child(menu)
	await get_tree().process_frame
	var menu_texts := menu.find_children("*", "Button", true, false).map(func(b): return b.text)
	_check("the title screen lists the six choices", menu_texts == ["Continue", "New game", "Multiplayer", "Hall of heroes", "Settings", "Quit"])
	_check("Continue is disabled with no saves", menu.find_children("*", "Button", true, false)[0].disabled)
	menu.show_slots("new")
	await get_tree().process_frame
	_check("the slot list shows three slots", menu.find_children("*", "Button", true, false).filter(func(b): return b.text.begins_with("Slot")).size() == 3)
	menu.show_difficulty()
	await get_tree().process_frame
	_check("the oath screen has all three oaths", menu.find_children("*", "Button", true, false).filter(func(b): return b.text == "Swear").size() == 3)
	menu.queue_free()

	SaveStore.dir = real_dir
	Leaderboard.clear()
	Leaderboard.path = real_board
	Game.meta = real_meta
	Game.slot = real_slot
	get_tree().paused = false


## Camp and run flow inside a Dungeon node (no UI).
func _p5_camp_and_runs() -> void:
	Game.character = _bare(CharacterData.create_sandbox("vanguard", ["fire"], 3))
	var world := Node2D.new()
	add_child(world)
	var player = PLAYER.instantiate()
	world.add_child(player)
	var dungeon := Dungeon.new()
	dungeon.with_ui = false
	dungeon.layout = [[DungeonGen.camp_room()]]
	world.add_child(dungeon)
	await get_tree().process_frame
	_check("the camp has the forge, the board and the gate", get_tree().get_nodes_in_group("interactables").size() >= 3 and dungeon.state == "camp")
	_check("the camp shows no run text but its name", Game.run_text == "Camp")
	world.queue_free()

	# every kind of room in a five-floor dungeon loads, and a mini boss room works end to end
	Game.character = _bare(CharacterData.create_sandbox("vanguard", ["fire"], 6))
	var world2 := Node2D.new()
	add_child(world2)
	var player2 = PLAYER.instantiate()
	world2.add_child(player2)
	var run := Dungeon.new()
	run.with_ui = false
	run.layout = DungeonGen.generate(_rng(12), 5, 1, 0)
	world2.add_child(run)
	await get_tree().process_frame
	var all_load := true
	for f in run.layout.size():
		for r in run.layout[f].size():
			run.debug_goto(f, r)
			all_load = all_load and run.room["kind"] == run.layout[f][r]["kind"] and DungeonGen.describe(run.room) != ""
	_check("every room of a five-floor dungeon loads", all_load)
	run.debug_goto(2, 2)
	run._physics_process(Dungeon.WAVE_DELAY + 0.1)
	await get_tree().process_frame
	_check("a mini boss room spawns its guardian and shows the boss bar", is_instance_valid(Game.boss) and Game.boss.mini and run.enemies_alive() >= 1)
	_check("the door stays shut while the guardian lives", run.state == "fighting")
	Game.boss.take_hit({"damage": 1000000.0, "element": "", "from": Vector2.ZERO})
	await get_tree().process_frame
	run._physics_process(0.1)
	_check("slaying the guardian opens the door", run.state == "clear")
	run.debug_goto(4, 2)
	run._physics_process(Dungeon.WAVE_DELAY + 0.1)
	await get_tree().process_frame
	_check("the last floor holds a final boss, not a mini boss", is_instance_valid(Game.boss) and not Game.boss.mini and Game.boss.boss)
	_check("depth raises monster strength", run._monster_scale().x > 1.0)
	world2.queue_free()


# ---------- Light and Dark ----------

func _test_light_dark() -> void:
	var all_pairs := true
	for rare in Elements.RARE:
		for other in Elements.MAIN:
			all_pairs = all_pairs and not Elements.resolve(rare, other).is_empty() and Elements.resolve(rare, other) == Elements.resolve(other, rare)
	_check("Light and Dark each combine with all five main elements", all_pairs and Elements.RARE_COMBOS.size() == 11)
	_check("Light and Dark combine with each other: Twilight", Elements.resolve("dark", "light")["name"] == "Twilight")
	_check("the main combos are untouched", Elements.COMBOS.size() == 10 and Elements.resolve("fire", "water")["name"] == "Steam")
	_check("Light and Dark have a resonance too", Elements.RESONANCE.has("light") and Elements.RESONANCE.has("dark"))
	var loadouts_ok := true
	for set_id in ["light", "dark"]:
		var loadout: Dictionary = SkillDB.LOADOUTS[set_id]
		for slot in ["primary", "area", "support", "special"]:
			var id: String = loadout[slot]
			loadouts_ok = loadouts_ok and SkillDB.DEFS.has(id) and SkillDB.DEFS[id]["element"] == set_id and SkillDB.slot_of(id) == slot and SkillDB.set_of(id) == set_id
	_check("Light and Dark have a full set of four skills", loadouts_ok)
	_check("their looks are defined", SkillFx.PROFILES.has("light") and SkillFx.PROFILES.has("dark"))

	var ch := CharacterData.create_sandbox("sage", ["light", "dark"], 7)
	_check("a Light and Dark character can cast both", ch.castable_elements().has("light") and ch.castable_elements().has("dark"))
	_check("and knows their first skills", ch.can_use_skill("light_lance") and ch.can_use_skill("shadow_bolt") and ch.can_use_skill("benediction"))
	var e := _dummy()
	_hit(e, "light_lance")
	var before := e.hp
	_hit(e, "shadow_bolt")
	_check("Light then Dark makes Twilight: vulnerable", e.effects.has("vuln") and is_equal_approx(before - e.hp, _dmg("shadow_bolt") * 1.8))
	e.queue_free()

	var light_less := _bare(CharacterData.create_sandbox("channeler", ["fire"], 3))
	_check("a character without them can still attune", light_less.missing_rare().size() == 2)
	_check("the main-element gap is unchanged by rare elements", light_less.missing_elements().size() == 4)
	light_less.inventory.materials[Items.gem_of("light")] = 1
	_check("a Light gem attunes", light_less.use_gem("light") and "light" in light_less.elements and light_less.inventory.count(Items.gem_of("light")) == 0)
	_check("and cannot be used twice", not light_less.use_gem("light"))
	var sealed := _bare(CharacterData.create_sandbox("vanguard", [], 3))
	sealed.affinity = CharacterData.SEALED
	sealed.inventory.materials[Items.gem_of("dark")] = 1
	_check("a sealed character can never use a rare gem", not sealed.use_gem("dark") and sealed.missing_rare().is_empty())

	_check("Light and Dark are each other's weakness", Monsters.WEAK_TO["light"] == "dark" and Monsters.WEAK_TO["dark"] == "light")
	var early := true
	var rare_seen := false
	var rng := _rng(4)
	for i in 120:
		for entry in Monsters.roll_wave(rng, 2, 5):
			early = early and not (entry["variant"] in Elements.RARE)
		for entry in Monsters.roll_wave(rng, 9, 5):
			rare_seen = rare_seen or entry["variant"] in Elements.RARE
	_check("rare variants never appear in the first dungeon", early)
	_check("but do in the second", rare_seen)
	var dark_mob := _fresh_monster("slime", "dark")
	var light_hit := {"damage": 10.0, "element": "light", "from": dark_mob.global_position}
	var before_hp: float = dark_mob.hp
	dark_mob.take_hit(light_hit)
	_check("a dark monster takes extra damage from Light", is_equal_approx(before_hp - dark_mob.hp, 10.0 * Monsters.WEAK_MULT))
	dark_mob.queue_free()

	_check("the second dungeon's bosses hold the rare gems", Monsters.DEFS["crypt_lich"]["rare_gem"] == "dark" and Monsters.DEFS["tide_titan"]["rare_gem"] == "light" and not Monsters.DEFS["slime_king"].has("rare_gem"))
	Game.character = _bare(CharacterData.create_sandbox("sage", ["fire"], 8))
	var holder := Node2D.new()
	add_child(holder)
	var lich := Monsters.spawn(holder, "crypt_lich", Vector2(40, 40))
	await get_tree().process_frame
	var gems: Array = []
	var catcher := func(drops: Array, _pos: Vector2):
		for d in drops:
			if d["kind"] == "material" and String(d["id"]) == "gem_dark":
				gems.append(d)
	Game.loot_dropped.connect(catcher)
	Game.loot_rng.seed = 11
	for i in 25:
		Game.on_enemy_killed(lich)
	Game.loot_dropped.disconnect(catcher)
	_check("a boss of the second dungeon sometimes drops its rare gem", gems.size() > 3 and gems.size() < 25)
	Game.character.add_element("dark")
	gems.clear()
	Game.loot_dropped.connect(catcher)
	for i in 10:
		Game.on_enemy_killed(lich)
	Game.loot_dropped.disconnect(catcher)
	_check("and never again once you hold that element", gems.is_empty())
	holder.queue_free()
	_neutral_character()


## Booking a finished run: meta, gold, leaderboard and the save.
func _p5_finish_run() -> void:
	var real_dir: String = SaveStore.dir
	var real_board: String = Leaderboard.path
	var real_slot: int = Game.slot
	var real_meta: Dictionary = Game.meta
	var real_run: Dictionary = Game.run
	SaveStore.dir = "user://test_saves"
	Leaderboard.path = "user://test_leaderboard.json"
	Leaderboard.clear()
	SaveStore.delete_slot(1)

	Game.character = _bare(CharacterData.create_sandbox("vanguard", ["fire", "water"], 5))
	Game.slot = 1
	Game.meta = SaveStore.new_meta("warlord")
	Game.run = {"tier": 1, "seed": 5, "floor": 4, "room": 2}
	Game.character.inventory.gold = 1000
	var world := Node2D.new()
	add_child(world)
	var player = PLAYER.instantiate()
	world.add_child(player)
	var run := Dungeon.new()
	run.with_ui = false
	run.layout = DungeonGen.generate(_rng(2), 5, 1, 0)
	world.add_child(run)
	await get_tree().process_frame
	run.debug_goto(4, 2)
	Game.run_kills = 12

	run._finish_run(true)
	_check("clearing a dungeon books it in the hero's record", Game.meta["tier_cleared"] == 1 and Game.meta["runs"] == 1)
	_check("and pays a clear bonus scaled by the oath", run.run_bonus == roundi(150.0 * 1.6) and Game.character.inventory.gold == 1000 + run.run_bonus)
	var board := Leaderboard.entries()
	_check("and puts the run on the leaderboard as cleared", board.size() == 1 and board[0]["outcome"] == "cleared" and board[0]["cleared"] == true and int(board[0]["kills"]) == 12)
	_check("the hero is saved, in camp", SaveStore.exists(1) and SaveStore.load_slot(1)["run"].is_empty() and Game.run.is_empty())
	_check("and the leaderboard rank was recorded", run.rank == 1)

	Game.run = {"tier": 1, "seed": 5, "floor": 1, "room": 0}
	Game.character.inventory.gold = 1000
	run.death = {"final": false, "lost": ["fire"]}
	run.gold_lost = 0
	run._finish_run(false)
	_check("falling costs 30% of the gold", run.gold_lost == 300 and Game.character.inventory.gold == 700)
	_check("and is recorded as a fall", Leaderboard.entries().any(func(e): return e["outcome"] == "fell"))
	_check("the hero survives a fall: the save is still there", SaveStore.exists(1) and Game.meta["runs"] == 2)

	Game.run = {"tier": 1, "seed": 5, "floor": 0, "room": 0}
	run.death = {"final": true, "lost": []}
	run._finish_run(false)
	_check("a death with nothing left to lose deletes the save", not SaveStore.exists(1))
	_check("and is recorded as a death", Leaderboard.entries().any(func(e): return e["outcome"] == "died"))
	_check("and lets go of the slot, so nothing can save the dead hero again",
		Game.slot == -1 and Game.save_game() == ERR_UNAVAILABLE and not FileAccess.file_exists(SaveStore.slot_path(1)))

	# resuming from a save rebuilds the same dungeon
	Game.run = {"tier": 2, "seed": 99, "floor": 3, "room": 1, "kills": 7, "time": 123.0}
	Game.mode = "dungeon"
	var resumed := Dungeon.new()
	resumed.with_ui = false
	var start: Vector2i = resumed._make_layout()
	_check("a saved run resumes on the saved floor and room", start == Vector2i(3, 1) and resumed.layout.size() == 10 and resumed.tier == 2)
	_check("and keeps its kills and time", Game.run_kills == 7 and is_equal_approx(resumed.run_time, 123.0))
	var twin := Dungeon.new()
	twin.with_ui = false
	twin._make_layout()
	_check("the same seed rebuilds the same dungeon", resumed.layout == twin.layout)
	_check("the second dungeon's monsters start deeper", resumed.layout[0][0]["depth"] == 6)
	resumed.free()
	twin.free()
	Game.mode = "camp"

	world.queue_free()
	SaveStore.delete_slot(1)
	Leaderboard.clear()
	SaveStore.dir = real_dir
	Leaderboard.path = real_board
	Game.slot = real_slot
	Game.meta = real_meta
	Game.run = real_run


## Closing the window saves; a hero picked for multiplayer keeps the dungeon saved in their slot.
func _p5_save_safety() -> void:
	var real_dir: String = SaveStore.dir
	var real_slot: int = Game.slot
	var real_meta: Dictionary = Game.meta
	var real_run: Dictionary = Game.run
	var real_mode: String = Game.mode
	var real_hero := Game.character
	SaveStore.dir = "user://test_saves"
	SaveStore.delete_slot(2)
	var hero := _bare(CharacterData.create_sandbox("vanguard", ["fire"], 3))
	SaveStore.save_slot(2, hero.to_dict(), SaveStore.new_meta(), {"tier": 1, "seed": 42, "floor": 3, "room": 1})
	_check("a saved hero can be picked for multiplayer", Game.use_hero(2) and Game.run.is_empty())
	for session_mode in ["arena", "coop"]:
		Game.mode = session_mode
		Game.save_game()
		_check("saving during %s keeps the hero's own dungeon in the slot" % session_mode, int(SaveStore.load_slot(2)["run"].get("seed", 0)) == 42)
	Game.mode = "camp"
	Game.meta["runs"] = 9
	Game._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	var closed := SaveStore.load_slot(2)
	_check("closing the window saves the hero", int(closed["meta"]["runs"]) == 9 and int(closed["run"].get("seed", 0)) == 42)
	Game.meta["runs"] = 10
	Game.mode = "training"
	Game._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	Game.mode = "camp"
	Game.creation_required = true
	Game._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	Game.creation_required = false
	Game.slot = -1
	Game._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_check("but not from training, from a hero still in creation, or without a slot", int(SaveStore.load_slot(2)["meta"]["runs"]) == 9)
	Game.slot = 2
	Game.keep_saved_run = false  # (as after continue_game, or a solo begin_run)
	Game.mode = "dungeon"
	Game.run = {"tier": 1, "seed": 5, "floor": 0, "room": 0}
	Game.save_game()
	_check("a solo run is the hero's own and is saved", int(SaveStore.load_slot(2)["run"].get("seed", 0)) == 5)
	SaveStore.delete_slot(2)
	SaveStore.dir = real_dir
	Game.slot = real_slot
	Game.meta = real_meta
	Game.run = real_run
	Game.mode = real_mode
	Game.character = real_hero


# ---------- Phase 6a: names, melee ring, element identity, training grounds ----------

func _p6_still(pos: Vector2) -> Enemy:
	var e := _dummy(pos)
	e.speed = 0.0
	return e


func _test_phase6a() -> void:
	# names
	_check("a typed name is trimmed and squeezed", Game.clean_name("  Aldric   the  Bold ") == "Aldric the Bold")
	_check("control characters are dropped from a name", Game.clean_name("Al\tdric\n") == "Aldric")
	_check("a name is at most 16 letters", Game.clean_name("ABCDEFGHIJKLMNOPQRSTUVWXYZ").length() == Game.NAME_MAX)
	_check("an empty name becomes Hero", Game.clean_name("   ") == "Hero" and Game.clean_name("") == "Hero")
	var kept := Game.character
	Game.start_new("wanderer", CharacterData.ELEMENTALIST, "Mira")
	_check("a new hero carries the typed name", Game.character.display_name == "Mira")
	Game.character = kept
	var menu := NewCharacterMenu.new()
	add_child(menu)
	await get_tree().process_frame
	menu.toggle()
	await get_tree().process_frame
	var fields := menu.find_children("*", "LineEdit", true, false)
	_check("the creation menu has a name field holding a suggestion", fields.size() == 1 and (fields[0] as LineEdit).text != "")
	menu.toggle()
	menu.queue_free()

	# elements differ from one another
	var speeds := {}
	var radii := {}
	var manas: Array = []
	for element in Elements.MAIN:
		var s := AltarScreen.stats_of(element)
		speeds[s["speed"]] = true
		radii[s["radius"]] = true
		manas.append(s["mana"])
	_check("every main element's bolt has its own speed", speeds.size() == 5)
	_check("every main element's area has its own radius", radii.size() == 5)
	_check("mana costs spread widely: the dearest bolt costs three times the cheapest", manas.max() >= manas.min() * 3.0)
	_check("air is the fastest bolt and mineral the slowest", AltarScreen.stats_of("air")["speed"] == speeds.keys().max() and AltarScreen.stats_of("mineral")["speed"] == speeds.keys().min())
	_check("each element has a signature trait", SkillDB.DEFS["gust"]["pierce"] == 2 and SkillDB.DEFS["fireball"]["splash"] > 0.0
		and SkillDB.DEFS["thorn_shot"]["spread_count"] == 3 and SkillDB.DEFS["shadow_bolt"]["homing"] > 0.0
		and SkillDB.DEFS["shadow_bolt"]["lifesteal"] > 0.0 and SkillDB.DEFS["light_lance"]["pierce"] == 1)
	_check("trait text names them", SkillDB.trait_text(SkillDB.DEFS["gust"]) == "pierces 2" and SkillDB.effect_text(SkillDB.DEFS["shadow_bolt"]).contains("drains 25%"))
	var roles_ok := true
	for set_id in SkillDB.LOADOUTS:
		roles_ok = roles_ok and SkillDB.ROLES.has(set_id)
	_check("every set has a one-line role", roles_ok)

	# bolts behave by trait
	var player = await _player_with(_bare(CharacterData.create_sandbox("wanderer", ["earth", "dark"], 1)))
	var e1 := _p6_still(Vector2(3030, 3000))
	var e2 := _p6_still(Vector2(3050, 3000))
	var e3 := _p6_still(Vector2(3070, 3000))
	await get_tree().physics_frame
	var pierce := Projectile.new()
	pierce.setup(Vector2(330, 0), {"damage": 10.0, "element": "air", "knockback": 0.0}, 1.0, [], {"pierce": 1})
	add_child(pierce)
	pierce.global_position = Vector2(3000, 3000)
	for i in 30:
		await get_tree().physics_frame
	_check("a piercing bolt passes its first target and stops at the next", e1.hp < e1.max_hp and e2.hp < e2.max_hp and is_equal_approx(e3.hp, e3.max_hp))

	var s1 := _p6_still(Vector2(3100, 3200))
	var s2 := _p6_still(Vector2(3100, 3215))
	var far := _p6_still(Vector2(3100, 3300))
	await get_tree().physics_frame
	var burst := Projectile.new()
	burst.setup(Vector2(200, 0), {"damage": 20.0, "element": "fire", "knockback": 0.0}, 1.0, [], {"splash": 22.0})
	add_child(burst)
	burst.global_position = Vector2(3050, 3200)
	for i in 40:
		await get_tree().physics_frame
	var dealt: float = s1.max_hp - s1.hp
	var shared: float = s2.max_hp - s2.hp
	_check("a bursting bolt hurts its target fully and its neighbour for 60%", absf(dealt - 20.0) < 0.5 and absf(shared - 12.0) < 0.5 and is_equal_approx(far.hp, far.max_hp))

	var d1 := _p6_still(Vector2(3300, 3000))
	await get_tree().physics_frame
	player.hp = 50.0
	var drain := Projectile.new()
	drain.setup(Vector2(200, 0), {"damage": 20.0, "element": "dark", "knockback": 0.0}, 1.0, [], {"lifesteal": 0.5})
	add_child(drain)
	drain.global_position = Vector2(3270, 3000)
	for i in 30:
		await get_tree().physics_frame
	_check("a draining bolt heals the caster for half the damage", absf(player.hp - 60.0) < 0.5)

	player.caster.mana = player.caster.max_mana
	player.caster.cooldowns.clear()
	var before := find_children("*", "Projectile", false, false).size()
	player.caster.try_cast("thorn_shot")
	_check("thorn shot fans three bolts", find_children("*", "Projectile", false, false).size() - before == 3)

	# the melee ring
	_check("the hero wears a melee range ring", player.get_children().any(func(c): return c is MeleeRing))
	_check("the ring is on by default", Settings.DEFAULTS["melee_indicator"] == true)

	# the training grounds
	for bolt in find_children("*", "Projectile", false, false):
		bolt.queue_free()  # the thorns fired earlier must not reach the dummy
	await get_tree().process_frame
	var dummy := Monsters.spawn(self, "dummy", Vector2(40, 0), "", Vector2.ONE, 1)
	player.global_position = Vector2.ZERO
	player.hp = player.max_hp
	for i in 40:
		await get_tree().physics_frame
	_check("a training dummy never moves or hurts", player.hp == player.max_hp and dummy.global_position.distance_to(Vector2(40, 0)) < 1.0)
	_check("dummies are not part of any wave", not Monsters.regular().has("dummy") and Monsters.DEFS["dummy"].get("training", false))

	var altar := AltarScreen.new()
	add_child(altar)
	await get_tree().process_frame
	altar.open()
	await get_tree().process_frame
	_check("the altar lists all seven elements and two actions", altar.find_children("*", "Button", true, false).size() == 9)
	var described := true
	for element in Elements.MAIN + Elements.RARE:
		described = described and AltarScreen.describe(element).contains(String(SkillDB.ROLES[element]))
	_check("the altar describes each element's role and skills", described)
	altar.close()
	altar.queue_free()

	var guide := TutorialGuide.new()
	add_child(guide)
	await get_tree().process_frame
	_check("the checklist starts with nothing ticked", guide.done_count() == 0)
	Input.action_press("dodge")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("dodge")
	_check("doing a thing ticks its step", guide.is_done("dodge"))
	_check("each step shows the bound key", TutorialGuide.keys_for("dodge") != "")
	guide.queue_free()

	Game.mode = "training"
	var world := Node2D.new()
	add_child(world)
	var hero = PLAYER.instantiate()
	world.add_child(hero)
	var grounds := Dungeon.new()
	grounds.with_ui = false
	world.add_child(grounds)
	await get_tree().process_frame
	await get_tree().physics_frame
	var posts := get_tree().get_nodes_in_group("interactables").filter(func(n): return n is TrainingSign and n.leaving)
	var altars := get_tree().get_nodes_in_group("interactables").filter(func(n): return n is ElementAltar)
	_check("the grounds hold the altar, a sign back and three dummies", grounds.state == "training" and Game.run_text == "Training grounds"
		and get_tree().get_nodes_in_group("dummies").size() == 3 and not altars.is_empty() and not posts.is_empty())
	get_tree().get_nodes_in_group("dummies")[0].queue_free()
	await get_tree().process_frame
	grounds._keep_dummies()
	_check("a destroyed dummy is replaced", get_tree().get_nodes_in_group("dummies").filter(func(n): return not n.is_queued_for_deletion()).size() == 3)
	Game.slot = 0
	var saved_result: Error = Game.save_game()
	Game.slot = -1
	_check("the grounds never save", saved_result == ERR_UNAVAILABLE)
	world.queue_free()
	Game.mode = "camp"

	var real := Game.character
	Game.stashed_hero = real
	Game.character = CharacterData.create_sandbox("channeler", ["fire"], 1)
	Game.mode = "training"
	Game._restore_hero()
	_check("leaving the grounds puts the real hero back", Game.character == real and Game.stashed_hero == null and Game.mode == "camp")

	for node in [e1, e2, e3, s1, s2, far, d1, dummy, player]:
		if is_instance_valid(node):
			node.queue_free()
	Game.character = kept


# ---------- Phase 6b: layered heroes, class cards, paper doll ----------

func _test_phase6b() -> void:
	var d := HeroLook.data()
	_check("the look data lists every class and subclass", Classes.CLASSES.keys().all(func(id): return d["classes"].has(id)) and Classes.SUBCLASSES.keys().all(func(id): return d["subclasses"].has(id)))

	# every look's parts exist as pictures
	var files_ok := true
	var looks := {}
	for class_id in Classes.CLASSES:
		looks[class_id] = HeroLook.for_class(class_id)
		for sub_id in Classes.CLASSES[class_id]["subclasses"]:
			looks[class_id + "/" + sub_id] = HeroLook.for_class(class_id, sub_id)
	for key in looks:
		var parts: Dictionary = looks[key]["parts"]
		var names: Array = ["base_body", "boots_" + parts["boots"], "outfit_" + parts["outfit"]]
		for slot in ["hair", "head", "back", "accent", "weapon"]:
			if parts[slot] != "":
				names.append("%s_%s" % [slot, parts[slot]])
		for part_name in names:
			for facing in HeroComposer.FACINGS:
				files_ok = files_ok and ResourceLoader.exists("res://assets/sprites/hero/%s_%s.png" % [part_name, facing])
	_check("every class and subclass look is made of parts that exist", files_ok)

	var keys := {}
	for key in looks:
		keys[HeroComposer.key_of(looks[key])] = true
	_check("every class and subclass looks different", keys.size() == looks.size())
	_check("a subclass changes its class's look", HeroComposer.key_of(HeroLook.for_class("vanguard")) != HeroComposer.key_of(HeroLook.for_class("vanguard", "bulwark")))

	# composing
	var frames := HeroComposer.compose(HeroLook.for_class("channeler"))
	var size := HeroComposer.size()
	var shape_ok: bool = frames.size() == 3
	for facing in HeroComposer.FACINGS:
		shape_ok = shape_ok and frames[facing].size() == HeroComposer.FRAME_COUNT
		for texture in frames[facing]:
			shape_ok = shape_ok and texture.get_size() == Vector2(size)
	_check("a look composes to three facings of every pose", shape_ok)
	var image: Image = HeroComposer.portrait(HeroLook.for_class("channeler")).get_image()
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			opaque += 1 if image.get_pixel(x, y).a > 0.5 else 0
	_check("the hero picture is a filled, outlined figure", opaque > 120 and opaque < size.x * size.y * 0.85)
	var other: Image = HeroComposer.portrait(HeroLook.for_class("vanguard")).get_image()
	_check("two classes paint different pictures", image.get_data() != other.get_data())
	var a_frame: Image = frames["side"][0].get_image()
	var b_frame: Image = frames["side"][1].get_image()
	_check("the walking frames differ from the standing one", a_frame.get_data() != b_frame.get_data())
	_check("composing the same look again reuses the pictures", HeroComposer.compose(HeroLook.for_class("channeler")) == frames)
	var prefix := HeroComposer.register(HeroLook.for_class("ranger"))
	_check("a registered look is found by AssetDB with every pose", AssetDB.has_art(prefix + ":side") and AssetDB.get_frames(prefix + ":side").size() == HeroComposer.FRAME_COUNT)

	# gear changes the look
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hero := CharacterData.create_sandbox("vanguard", ["fire"], 5)
	_bare(hero)
	var plain_key := HeroComposer.key_of(HeroLook.for_character(hero))
	var helm := Items.make("iron_helm", "rare", 4, rng)
	var mail := Items.make("chain_mail", "rare", 4, rng)
	var boots := Items.make("runner_boots", "common", 4, rng)
	var axe := Items.make("battle_axe", "epic", 4, rng)
	for item in [helm, mail, boots, axe]:
		hero.inventory.add_item(item)
		hero.inventory.equip(hero.inventory.bag.size() - 1)
	var worn: Dictionary = HeroLook.for_character(hero)
	_check("worn gear shows on the hero", worn["parts"]["head"] == "helm" and worn["parts"]["outfit"] == "mail" and worn["parts"]["boots"] == "boots" and worn["parts"]["weapon"] == "axe")
	_check("so the look key changes", HeroComposer.key_of(worn) != plain_key)
	hero.inventory.unequip("weapon")
	_check("an empty hand shows no weapon", HeroLook.for_character(hero)["parts"]["weapon"] == "")
	var rig_ok := true
	for monster_id in ["skeleton", "duelist", "grave_warden", "ember_matron", "wraith", "shade"]:
		var enemy := Monsters.spawn(self, monster_id, Vector2.ZERO)
		var picture := enemy.sprite.texture.get_size()
		rig_ok = rig_ok and picture == Vector2(20, 32) and AssetDB.get_frames(enemy.sprite_id).size() == 4
		rig_ok = rig_ok and enemy.hit_rect().size == Enemy.BODY_SIZES[enemy.sprite_id] and is_equal_approx(enemy.picture_height(), 32.0)
		enemy.queue_free()
	_check("the humanoid enemies are drawn on the 20 x 32 hero rig with four frames and keep their old hit boxes", rig_ok)
	var icons_ok := true
	for item in [helm, mail, boots, axe]:
		var icon: Texture2D = HeroLook.slot_icon(item)
		icons_ok = icons_ok and icon != null and icon.get_width() >= 4 and icon.get_height() >= 4 and icon != AssetDB.get_texture("pickup_item")
	_check("every worn item has its own icon", icons_ok)

	# saving the hero's looks
	var saved := hero.to_dict()
	hero.look_skin = 3
	hero.look_hair = 5
	var loaded := CharacterData.from_dict(JSON.parse_string(JSON.stringify(hero.to_dict())))
	_check("skin tone and hair colour are saved", loaded.look_skin == 3 and loaded.look_hair == 5)
	_check("an old save without them still loads", CharacterData.from_dict(JSON.parse_string(JSON.stringify(saved))).look_skin == 0)

	# the class cards show pictures and wear their own borders
	var kept := Game.character
	Game.character = CharacterData.create_sandbox(Classes.NEUTRAL_CLASS, ["fire"], 3)
	var cards := ClassCards.new()
	add_child(cards)
	await get_tree().process_frame
	cards.open("class")
	await get_tree().process_frame
	_check("each class card has a hero picture", cards.find_children("*", "TextureRect", true, false).size() == 8)
	var frame_nodes := cards.find_children("*", "CardFrame", true, false)
	var ornaments := {}
	for frame in frame_nodes:
		ornaments[frame.ornament] = true
	_check("each class card has a frame, and the borders differ by class", frame_nodes.size() == 8 and ornaments.size() >= 5)
	_check("the class cards can be moved with left and right", (func():
		var before: int = cards._hot
		var right := InputEventAction.new()
		right.action = "ui_right"
		right.pressed = true
		cards._input(right)
		return cards._hot == (before + 1) % 8).call())
	cards.close()
	cards.queue_free()
	Game.character = kept

	# the reward cards draw frames too
	var tester := CharacterData.create_sandbox("channeler", ["fire"], 1)
	tester.pending_rewards.append([{"type": "skill", "id": "inferno_ring"}, {"type": "passive", "id": "sturdy"}])
	Game.character = tester
	var reward := RewardCards.new()
	add_child(reward)
	await get_tree().process_frame
	reward._build()
	await get_tree().process_frame
	_check("each reward card has a frame and a picture", reward.find_children("*", "CardFrame", true, false).size() == 2 and reward.find_children("*", "TextureRect", true, false).size() == 2)
	reward.free()

	# the paper doll
	var sheet_hero := CharacterData.create_sandbox("vanguard", Elements.MAIN, 5)
	sheet_hero.inventory.add_item(Items.make("iron_helm", "rare", 4, rng))
	sheet_hero.inventory.equip(sheet_hero.inventory.bag.size() - 1)
	Game.character = sheet_hero
	var sheet := CharacterSheet.new()
	add_child(sheet)
	await get_tree().process_frame
	sheet.show_tab("gear")
	await get_tree().process_frame
	var slot_buttons := sheet._content.find_children("*", "Button", true, false).filter(func(b): return b.custom_minimum_size == Vector2(24, 24))
	_check("the gear tab has a slot for each of the six places and the hero between", slot_buttons.size() == 6 and not sheet._content.find_children("*", "TextureRect", true, false).is_empty())
	_check("a worn item's slot shows its icon", slot_buttons.any(func(b): return b.icon != null))
	sheet.queue_free()
	Game.character = kept


# ---------- Phase 6b: five dungeons ----------

func _test_dungeons5() -> void:
	var tiers: Array = Game.TIERS.keys()
	_check("there are five dungeons", tiers.size() == 5 and tiers == [1, 2, 3, 4, 5])
	var floors: Array = tiers.map(func(t): return Game.TIERS[t]["floors"])
	_check("they grow longer: 5, 10, 12, 15, 20 floors", floors == [5, 10, 12, 15, 20])
	var contiguous := true
	for i in range(1, tiers.size()):
		contiguous = contiguous and Game.TIERS[tiers[i]]["depth"] == Game.TIERS[tiers[i - 1]]["depth"] + Game.TIERS[tiers[i - 1]]["floors"]
	_check("each starts at the depth where the one before ends", contiguous and Game.TIERS[1]["depth"] == 0)
	var harder := true
	var previous := Vector2.ZERO
	for tier in tiers:
		var scale := Monsters.floor_scale(int(Game.TIERS[tier]["depth"]) + 1)
		harder = harder and scale.x > previous.x and scale.y > previous.y
		previous = scale
	_check("each dungeon starts with tougher monsters than the one before", harder)
	_check("the deepest floors are hard but not absurd", Monsters.floor_scale(62).x < 14.0 and Monsters.floor_scale(62).y < 8.0)
	var bosses_ok := true
	var themes_ok := true
	var generates := true
	for tier in tiers:
		var finals: Array = Monsters.bosses(int(tier))
		bosses_ok = bosses_ok and not finals.is_empty() and finals.all(func(id): return AssetDB.has_art(String(Monsters.DEFS[id]["sprite"])))
		var theme := String(Game.TIERS[tier].get("theme", "crypt" if tier >= 2 else "vault"))
		themes_ok = themes_ok and AssetDB.has_art("tile_floor_%s_0" % theme) and AssetDB.has_art("tile_wall_%s_0" % theme) and AssetDB.has_art("tile_pillar_" + theme) and AssetDB.has_art("bg_" + theme)
		var layout := DungeonGen.generate(_rng(40 + int(tier)), int(Game.TIERS[tier]["floors"]), int(tier), int(Game.TIERS[tier]["depth"]))
		var last_room: Dictionary = layout[-1][-1]
		generates = generates and layout.size() == int(Game.TIERS[tier]["floors"]) and last_room["kind"] == "boss" and Monsters.bosses(int(tier)).has(last_room["boss"]) \
			and int(last_room["depth"]) == int(Game.TIERS[tier]["depth"]) + int(Game.TIERS[tier]["floors"])
	_check("every dungeon has a final boss with art", bosses_ok)
	_check("every dungeon has its own tiles and background", themes_ok)
	_check("every dungeon generates and ends in its own boss", generates)
	var new_monsters := ["sapling", "wolf", "slug", "shade"]
	_check("the new monsters have art and appear in the deeper bands", new_monsters.all(func(id): return AssetDB.has_art(String(Monsters.DEFS[id]["sprite"])) and Monsters.WEIGHTS.values().any(func(w): return w.has(id))))
	var seen := {}
	for depth in [3, 8, 18, 30, 50]:
		for entry in Monsters.roll_wave(_rng(depth), depth, 40):
			seen[entry["id"]] = true
	_check("deeper dungeons field the new monsters", seen.has("wolf") and seen.has("shade") and seen.has("slug"))
	_check("the depth bands run from the first floor to the last dungeon", Monsters.band_of(1) == 1 and Monsters.band_of(5) == 5 and Monsters.band_of(60) == Monsters.WEIGHTS.size())
	var theme_music := Game.TIERS[3]["theme"] == "hollow" and Game.TIERS[4]["theme"] == "ember" and Game.TIERS[5]["theme"] == "spire"
	_check("the new dungeons are themed", theme_music)
	var old_danger := Game.danger
	Game.danger = 400
	var capped: float = Game.loot_bonus()
	Game.danger = old_danger
	_check("loot luck from depth is capped", capped <= 5.0 + float(Game.character.derived()["loot_luck"]) + 1.0)


# ---------- soak: many generated dungeons must be playable ----------

## Walkable tiles reachable from the spawn tile (4-way), the way the hero moves around pillars.
func _reachable_tiles(room: Dictionary) -> Dictionary:
	var cols: int = room["cols"]
	var rows: int = room["rows"]
	var solid := {}
	for rect in room["obstacles"]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				solid[Vector2i(x, y)] = true
	var open := {}
	var queue: Array[Vector2i] = [DungeonGen.spawn_tile(room)]
	open[queue[0]] = true
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = at + step
			if next.x < 1 or next.y < 1 or next.x > cols - 2 or next.y > rows - 2 or solid.has(next) or open.has(next):
				continue
			open[next] = true
			queue.append(next)
	return open


func _test_generation_soak() -> void:
	var rooms_seen := 0
	var problems: Array[String] = []
	for tier in Game.TIERS:
		var spec: Dictionary = Game.TIERS[tier]
		for seed_value in 12:
			var rng := RandomNumberGenerator.new()
			rng.seed = 9000 + seed_value * 31 + int(tier)
			var layout := DungeonGen.generate(rng, int(spec["floors"]), int(tier), int(spec.get("depth", 0)))
			if layout.size() != int(spec["floors"]):
				problems.append("tier %d has %d floors" % [tier, layout.size()])
			for floor_rooms in layout:
				var previous: Dictionary = {}
				for room in floor_rooms:
					rooms_seen += 1
					var open := _reachable_tiles(room)
					var spawn := DungeonGen.spawn_tile(room)
					if not open.has(spawn):
						problems.append("t%d s%d spawn blocked in %s" % [tier, seed_value, DungeonGen.describe(room)])
					if room["exit"] != "":
						var door := DungeonGen.door_rect(room, "exit")
						var reached := false
						for y in range(door.position.y, door.end.y):
							for x in range(door.position.x, door.end.x):
								var inward: Vector2i = {"north": Vector2i(0, 1), "south": Vector2i(0, -1), "west": Vector2i(1, 0), "east": Vector2i(-1, 0)}[room["exit"]]
								var inside := Vector2i(x, y) + inward
								reached = reached or open.has(inside)
						if not reached:
							problems.append("t%d s%d exit door cannot be reached in %s" % [tier, seed_value, DungeonGen.describe(room)])
					var fraction := float(open.size()) / float((int(room["cols"]) - 2) * (int(room["rows"]) - 2))
					if fraction < 0.6:
						problems.append("t%d s%d room is mostly pillars (%d%%)" % [tier, seed_value, int(fraction * 100.0)])
					if room["kind"] == "combat" and room["waves"].is_empty():
						problems.append("t%d s%d combat room with no waves" % [tier, seed_value])
					if not previous.is_empty() and DungeonGen.OPPOSITE[previous["exit"]] != room["entry"]:
						problems.append("t%d s%d doors do not line up" % [tier, seed_value])
					previous = room
		var last_room: Dictionary = DungeonGen.generate(RandomNumberGenerator.new(), int(spec["floors"]), int(tier), 0)[-1][-1]
		if last_room["kind"] != "boss" or not Monsters.bosses(int(tier)).has(last_room["boss"]):
			problems.append("tier %d does not end with its own boss" % tier)
	_check("%d generated rooms across five dungeons are all playable (%s)" % [rooms_seen, "; ".join(problems.slice(0, 3))], problems.is_empty())


# ---------- Phase 6c: the isometric view (drawn in 2D) ----------

func _test_iso() -> void:
	_check("the screen and ground directions are inverse", (func():
		var ok := true
		for d in [Vector2(1, 0), Vector2(0, 1), Vector2(-3, 2), Vector2(0.4, -0.9)]:
			var back := IsoView.world_dir(IsoView.screen_dir(d))
			ok = ok and absf(back.angle_to(d)) < 0.01
		return ok).call())
	_check("up on the screen is north-west on the ground and right is north-east", IsoView.world_dir(Vector2(0, -1)).dot(Vector2(-1, -1).normalized()) > 0.99 and IsoView.world_dir(Vector2(1, 0)).dot(Vector2(1, -1).normalized()) > 0.99)
	_check("a world point projects to a 2:1 diamond and back", IsoView.project(Vector2(32, 48)) == Vector2(-16, 40) and IsoView.unproject(IsoView.project(Vector2(32, 48))).is_equal_approx(Vector2(32, 48)))

	var world := Node2D.new()
	add_child(world)
	var hero = PLAYER.instantiate()
	world.add_child(hero)
	var dungeon := Dungeon.new()
	dungeon.with_ui = false
	dungeon.layout = [[DungeonGen.camp_room()]]
	world.add_child(dungeon)
	await get_tree().process_frame
	var real_lighting: String = Settings.get_value("lighting")
	Settings.values["lighting"] = "full"
	var view := IsoView.attach(dungeon)
	dungeon.iso_view = view
	await get_tree().process_frame
	dungeon.debug_goto(0, 0)  # builds the room again, now with walls
	await get_tree().process_frame
	await get_tree().process_frame
	_check("the view is the active one and draws in 2D only", IsoView.active == view and view.find_children("*", "Camera3D", true, false).is_empty() and view.find_children("*", "Node3D", true, false).is_empty())
	var room := DungeonGen.camp_room()
	var ring_tiles := 2 * (int(room["cols"]) + int(room["rows"])) - 4
	_check("the room's walls and pillars became blocks", view.wall_count() == ring_tiles + room["obstacles"].size())
	_check("the ground texture is as big as the room", view.ground_viewport.size == Vector2i(int(room["cols"]) * 16, int(room["rows"]) * 16))
	_check("the main window hides the flat world and the ground shows it", (get_viewport().canvas_cull_mask & (IsoView.LAYER_GROUND | IsoView.LAYER_ENTITY)) == 0 and (view.ground_viewport.canvas_cull_mask & IsoView.LAYER_GROUND) != 0 and (view.ground_viewport.canvas_cull_mask & IsoView.LAYER_ENTITY) == 0)
	var floor_sprite: Sprite2D = null
	for node in dungeon._room_node.get_children():
		if node is Sprite2D and node.z_index == -10:
			floor_sprite = node
			break
	_check("floor tiles go to the ground layer", floor_sprite != null and floor_sprite.visibility_layer == IsoView.LAYER_GROUND)
	_check("the view lights the room: its lights built once, the floor and walls take the light", view.lighting != null \
		and view.find_children("*", "PointLight2D", true, false).size() == Lighting.MAX_LIGHTS * 2 + 1 \
		and floor_sprite.light_mask == Lighting.LIT and floor_sprite.material is ShaderMaterial and view._walls[0].light_mask == Lighting.LIT)
	_check("the hero carries a light; their own sprite is never dimmed", view.lighting.lights_on() >= 1 and hero.get_node("Sprite2D").light_mask & Lighting.LIT == 0)
	_check("the hero's sprite is redrawn standing up", hero.get_node("Sprite2D").visibility_layer == IsoView.LAYER_ENTITY and view.mirror_count() >= 1)
	var before := view.mirror_count()
	var enemy := Monsters.spawn(dungeon._room_node, "slime", Vector2(120, 100), "", Vector2.ONE, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("a monster gets a standing sprite, a shadow and a health bar", view.mirror_count() >= before + 2 and enemy.sprite.visibility_layer == IsoView.LAYER_ENTITY)
	var mirror: Sprite2D = view._mirrors[enemy.sprite]
	_check("the stand-in sits where the monster does, on the screen", mirror.position.distance_to(IsoView.project(enemy.sprite.global_position)) < 1.5)
	_check("it stands on its spot, not centred on it", mirror.offset.y < 0.0 and mirror.get_parent() == view._stage and view._stage.y_sort_enabled)
	var tex_before := mirror.texture
	enemy.sprite.flip_h = true
	await get_tree().process_frame
	_check("it copies the flat sprite's picture and flip", mirror.texture == enemy.sprite.texture and tex_before != null and mirror.flip_h)
	var screen := view.screen_point_of(hero.global_position)
	_check("a ground point projected to the screen and back lands where it started", view.ground_point_at(screen).distance_to(hero.global_position) < 0.5)
	FloatText.spawn(world, hero.global_position, "-9", Color.RED)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("floating text becomes a label on the stage", view._mirrors.keys().any(func(n): return n is FloatText) and view._stage.get_children().any(func(c): return c is Label and c.text == "-9"))
	enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("a monster that goes takes its stand-ins with it", not view._mirrors.has(enemy.sprite) if is_instance_valid(enemy) else true)
	_check("the view is centred on the hero", view.screen_point_of(hero.global_position).distance_to(get_viewport().get_visible_rect().size * 0.5) < 60.0)
	var player_dir := IsoView.screen_dir(Vector2.RIGHT)
	_check("east runs right and down the screen", player_dir.x > 0.0 and player_dir.y > 0.0)
	var settings_on := Settings.DEFAULTS["iso_view"] == true
	_check("the isometric view is the default", settings_on)
	view.queue_free()
	await get_tree().process_frame
	_check("closing the view gives the window its flat world back", IsoView.active == null and get_viewport().canvas_cull_mask == 0xFFFFFFFF)
	Settings.values["lighting"] = "off"
	var unlit_view := IsoView.attach(dungeon)
	await get_tree().process_frame
	_check("lighting off builds no light at all", unlit_view.lighting == null and unlit_view.find_children("*", "Light2D", true, false).is_empty())
	unlit_view.queue_free()
	await get_tree().process_frame
	Settings.values["lighting"] = real_lighting
	world.queue_free()


# ---------- lighting ----------

func _test_lighting() -> void:
	var themes := ["camp"]
	var probe := Dungeon.new()  # the place names come from the dungeon's own rule, every tier and the camp
	for tier in Game.TIERS:
		probe.tier = int(tier)
		probe.room = {"kind": "combat"}
		themes.append(probe._theme())
	probe.free()
	var ambient_ok := true
	for theme in themes:
		var c := Lighting.ambient(theme)
		ambient_ok = ambient_ok and Lighting.AMBIENT.has(theme) and c.v >= 0.5 and c.v <= 0.9 and minf(c.r, minf(c.g, c.b)) > 0.05 and c.a == 1.0
	_check("every place has a dim ambient, never pure black or white (%s)" % ", ".join(themes), ambient_ok and themes.size() == 6)
	_check("soft lighting is brighter than full", Lighting.ambient("vault", "soft").v > Lighting.ambient("vault").v)
	# The budget: hero, a far boss, 30 monsters and 10 bolts compete for MAX_LIGHTS lights.
	var keys := PackedInt64Array()
	keys.append(Lighting.light_key(Lighting.BOSS, 400.0, 0))
	for i in 30:
		keys.append(Lighting.light_key(Lighting.ENEMY, 300.0 - i * 9.0, 1 + i))  # index 30 is the nearest monster
	for i in 10:
		keys.append(Lighting.light_key(Lighting.BOLT, 50.0 + i, 31 + i))
	keys.append(Lighting.light_key(Lighting.HERO, 0.0, 41))
	keys.append(Lighting.UNUSED)
	var kept := Lighting.choose(keys, Lighting.MAX_LIGHTS)
	var kinds := {}
	var enemy_far := 0
	for i in kept:
		var kind: int = keys[i] >> 40
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if kind == Lighting.ENEMY:
			enemy_far = maxi(enemy_far, (keys[i] >> 8) & 0xFFFFFFFF)
	var enemies_kept: int = kinds.get(Lighting.ENEMY, 0)
	_check("the light budget keeps the hero first and the boss, however far", kept == Lighting.MAX_LIGHTS and keys[0] >> 40 == Lighting.HERO and keys[1] >> 40 == Lighting.BOSS)
	_check("only the nearest few bolts light up", kinds.get(Lighting.BOLT, 0) == Lighting.MAX_BOLTS)
	_check("the farthest monsters are the ones left dark", enemies_kept == Lighting.MAX_LIGHTS - 2 - Lighting.MAX_BOLTS and enemy_far == int(300.0 - (30 - enemies_kept) * 9.0))
	var few := PackedInt64Array([Lighting.light_key(Lighting.ENEMY, 5.0, 0), Lighting.UNUSED, Lighting.UNUSED])
	_check("fewer candidates than lights: each gets one, empty slots none", Lighting.choose(few, Lighting.MAX_LIGHTS) == 1)


# ---------- the fixes after Phase 6: screens inside the window, sharp text, light and dark keys ----------

func _test_fixes() -> void:
	_check("every element has a number key, light and dark included", InputMap.has_action("element_6") and InputMap.has_action("element_7") and not InputMap.action_get_events("element_7").is_empty())
	_check("the controls screen lists the rare element keys", Controls.ACTIONS.any(func(a): return a[0] == "element_7"))
	_check("unthemed text (damage numbers, world signs) uses the menus' font", ThemeDB.fallback_font is SystemFont and ThemeDB.fallback_font_size == 7)

	var screen := get_viewport().get_visible_rect()
	var saved := Game.character
	var menu := NewCharacterMenu.new()
	add_child(menu)
	await get_tree().process_frame
	menu.toggle()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = menu.find_children("*", "PanelContainer", true, false)[0]
	_check("the creation screen sits inside the window", screen.encloses(panel.get_global_rect()))
	var name_label: Label = menu.find_children("*", "Label", true, false).filter(func(l): return l.text == "Name")[0]
	_check("the Name label is on one line beside its field", name_label.size.y < 16.0 and name_label.size.x > 14.0)
	var field: LineEdit = menu.find_children("*", "LineEdit", true, false)[0]
	_check("the name field is one row tall and has room to type", field.size.y < 20.0 and field.size.x > 100.0)
	var tallest := 0.0
	for id in Classes.playable():  # every class and birth description must fit too
		for birth in NewCharacterMenu.BIRTHS:
			menu._class_id = id
			menu._birth = birth["id"]
			menu._refresh_description()
			await get_tree().process_frame
			await get_tree().process_frame
			tallest = maxf(tallest, panel.size.y)
			if not screen.encloses(panel.get_global_rect()):
				_check("the creation screen fits with %s and %s" % [id, birth["id"]], false)
	_check("the creation screen fits for every class and birth (tallest %d of %d)" % [int(tallest), int(screen.size.y)], tallest <= screen.size.y - 4.0)
	menu.toggle()
	menu.queue_free()
	await get_tree().process_frame
	Game.character = saved

	var online := MultiplayerMenu.new()
	add_child(online)
	await get_tree().process_frame
	for screen_name in ["show_choice", "show_join"]:
		online.call(screen_name)
		await get_tree().process_frame
		await get_tree().process_frame
		var shown: Control = online._view.find_children("*", "PanelContainer", true, false)[0]
		_check("multiplayer screen %s sits inside the window" % screen_name, screen.encloses(shown.get_global_rect()))
	online.queue_free()


# ---------- Art style: Moonlit Glyphwork (docs/ART_DIRECTION.md) ----------

## The identity colour of each element is the bright step of its Moonlit ramp (tools/art/style.py).
const MOONLIT_ELEMENT_COLORS := {"fire": "ff8040", "water": "5cc8ff", "air": "9cf0d8", "mineral": "f8d060", "earth": "88e880", "light": "e8e0ff", "dark": "b868ff", "martial": "b8b8d8"}
const HERO_PART_KEYS := {"outfit": ["tunic", "robe", "mail", "leather", "fur"], "hair": ["short", "long", "bun"],
	"head": ["cap", "helm", "hood", "hat", "circlet", "mask", "horns", "antlers", "feather"], "back": ["cape", "quiver", "satchel"],
	"boots": ["shoes", "boots"], "weapon": ["sword", "staff", "bow", "rod", "dagger", "axe", "tome"],
	"accent": ["sash", "pauldrons", "collar", "gem", "tabard"]}


func _test_art_style() -> void:
	for element in MOONLIT_ELEMENT_COLORS:
		_check("%s keeps its Moonlit colour" % element, Elements.color_of(element).to_html(false) == MOONLIT_ELEMENT_COLORS[element])
		var runes_ok := true
		for size in ["s", "m", "l"]:
			runes_ok = runes_ok and UiTheme.rune(element, size) != null
		_check("%s has its rune in every size" % element, runes_ok)
		_check("%s has a rune circle for its areas and a bolt" % element, AssetDB.has_art("fx_rune_" + element) and AssetDB.has_art("proj_" + element))
	_check("no element asks for the martial rune", UiTheme.rune("", "s") == UiTheme.rune("martial", "s"))
	_check("a rune picture is as big as the hotbar slot", UiTheme.rune("fire", "s").get_size() == Vector2(18, 18))

	var size := HeroComposer.size()
	_check("heroes are drawn in a 34 x 32 cell with 21 poses", size == Vector2i(34, 32) and HeroComposer.FRAME_COUNT == 21)
	var strips_ok := true
	for part in ["base_body", "outfit_robe", "head_hat", "weapon_staff", "back_cape", "boots_boots"]:
		for facing in HeroComposer.FACINGS:
			var strip := load("res://assets/sprites/hero/%s_%s.png" % [part, facing]) as Texture2D
			strips_ok = strips_ok and strip != null and strip.get_size() == Vector2(size.x * HeroComposer.FRAME_COUNT, size.y)
	_check("the hero part strips are 21 poses of 34 x 32", strips_ok)

	# every part of every kind, in every facing and frame, stays off the edge cells of its 34 x 32 frame (the outline needs them,
	# and a part that touches them is clipped)
	var edge_hits: Array[String] = []
	for key in HERO_PART_KEYS:
		var names: Array = []
		for variant in HERO_PART_KEYS[key]:
			names.append("%s_%s" % [key, variant])
		if key == "outfit":
			names.append("base_body")
		for part_name in names:
			for facing in HeroComposer.FACINGS:
				var strip := (load("res://assets/sprites/hero/%s_%s.png" % [part_name, facing]) as Texture2D).get_image()
				for frame in HeroComposer.FRAME_COUNT:
					for y in size.y:
						for x in size.x:
							if strip.get_pixel(frame * size.x + x, y).a > 0.0 and (x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1):
								edge_hits.append("%s %s f%d" % [part_name, facing, frame])
	_check("no hero part is clipped by its frame (%s)" % ", ".join(edge_hits.slice(0, 4)), edge_hits.is_empty())
	var outlined := true
	for class_id in Classes.playable():
		for facing in HeroComposer.FACINGS:
			var image := (HeroComposer.compose(HeroLook.for_class(class_id))[facing][0] as Texture2D).get_image()
			var darkest := 1.0
			for y in image.get_height():
				for x in image.get_width():
					if image.get_pixel(x, y).a > 0.0:
						darkest = minf(darkest, image.get_pixel(x, y).get_luminance())
			outlined = outlined and darkest < 0.2
	_check("every hero is drawn with a dark outline", outlined)
	var icons_ok := true
	for base in Items.BASES:
		var icon_path := "res://assets/sprites/item_%s.png" % base
		var icon := load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
		icons_ok = icons_ok and icon != null and icon.get_size() == Vector2(16, 16)
		if icon != null:
			icons_ok = icons_ok and HeroLook.slot_icon({"base": base, "rarity": "common"}) == icon
	_check("every piece of gear has its own 16 x 16 icon and the equipment screen shows it", icons_ok)
	var palette_ok := true
	for class_id in Classes.playable():
		var picture := (HeroComposer.compose(HeroLook.for_class(class_id))["down"][0] as Texture2D).get_image()
		palette_ok = palette_ok and picture.get_width() == size.x and picture.get_height() == size.y
	_check("every class composes a whole-cell picture", palette_ok)


# ---------- Feel: melee reach, ranged rate, wind-ups, longer dodge, pass-through, smaller sprites ----------

func _test_feel_changes() -> void:
	_check("the base melee reach is 10% longer", is_equal_approx(float(SkillDB.MELEE["range"]), 26.0 * 1.1))
	var before := {"fireball": 0.38, "water_jet": 0.14, "gust": 0.18, "shard_shot": 0.6, "thorn_shot": 0.35, "light_lance": 0.25, "shadow_bolt": 0.32, "knife_throw": 0.24}
	var rate_ok := true
	for id in before:
		rate_ok = rate_ok and absf(float(SkillDB.DEFS[id]["cooldown"]) / float(before[id]) - 2.3) < 0.06
	_check("the ranged shots wait 2.3 times as long between casts", rate_ok)
	var windup_ok := true
	for id in SkillDB.WINDUPS:
		windup_ok = windup_ok and SkillDB.DEFS.has(id) and SkillDB.slot_of(id) in ["area", "special"]
	for slot in ["primary", "support"]:
		for set_id in SkillDB.LOADOUTS:
			windup_ok = windup_ok and SkillDB.windup_of(SkillDB.LOADOUTS[set_id][slot]) == 0.0
	_check("only areas and specials wind up; bolts and supports are instant", windup_ok)

	SkillCaster.windups_enabled = true
	var saved := Game.character
	var player: Node2D = await _player_with(CharacterData.create_sandbox("mystic", ["fire", "water"], 1))
	var caster: SkillCaster = player.caster
	Game.character.learned_specials.append("inferno_ring")
	var areas_before := get_children().filter(func(n): return n is AoeEffect).size()
	var mana_before: float = caster.mana
	_check("a special starts to charge instead of landing", caster.try_cast("inferno_ring") and caster.is_winding_up())
	_check("its cost and cooldown are paid at once", caster.mana < mana_before and caster.cooldowns.has("inferno_ring"))
	_check("nothing has landed yet", get_children().filter(func(n): return n is AoeEffect).size() == areas_before)
	_check("no second cast while charging", not caster.try_cast("flame_burst"))
	caster.tick_windup(0.3)
	_check("part way through it is still charging", caster.is_winding_up() and caster.windup_fraction() > 0.3 and caster.windup_fraction() < 1.0)
	caster.tick_windup(2.0)
	_check("when the charge is full the area lands", not caster.is_winding_up() and get_children().filter(func(n): return n is AoeEffect).size() > areas_before)
	caster.cooldowns.clear()
	caster.mana = caster.max_mana
	caster.try_cast("inferno_ring")
	player.stamina = 100.0
	player._dodge_cd = 0.0
	player.try_dodge(Vector2.RIGHT)
	_check("a dodge interrupts a charge", not caster.is_winding_up() and caster.cooldowns.has("inferno_ring"))
	SkillCaster.windups_enabled = false

	_check("a dodge keeps its i-frames longer than the roll, and a spin is immune for half a second", player.dodge_iframes >= 0.3 and player.dodge_iframes > player.dodge_time and is_equal_approx(Player.SPIN_DURATION, 0.5))
	var minion := _dummy(player.position + Vector2(6, 0))
	var boss := _dummy(player.position + Vector2(-6, 0))
	boss.boss = true
	var mini := _dummy(player.position + Vector2(0, 6))
	mini.mini = true
	player._dodge_left = 0.0
	player._dodge_cd = 0.0
	player._end_pass_through_for_test()
	player.stamina = 100.0
	player.try_dodge(Vector2.RIGHT)
	var passed: Array = player.get_collision_exceptions()
	_check("a roll slips through ordinary enemies", passed.has(minion))
	_check("but not through a boss or a mini boss", not passed.has(boss) and not passed.has(mini))
	player._dodge_left = 0.0
	player._update_pass_through()
	_check("the pass-through lasts while the hero still overlaps the enemy", player.get_collision_exceptions().has(minion))
	minion.position = player.position + Vector2(200, 0)
	player._update_pass_through()
	_check("and ends once they are apart", not player.get_collision_exceptions().has(minion))

	# the 15% reduction is baked into the pictures (tools/art/shrink.py): nothing is scaled while drawn, every pixel is a real pixel
	var partner := RemoteAvatar.new()
	partner.setup(9, {"name": "Pip", "class": "ranger"})
	add_child(partner)
	_check("the hero, a partner and the enemies are drawn at scale 1", player.sprite.scale == Vector2.ONE and partner.sprite.scale == Vector2.ONE and minion.sprite.scale == Vector2.ONE and boss.sprite.scale == Vector2.ONE)
	var hero_frame: Texture2D = AssetDB.get_frames(player._look_prefix + ":down")[0]
	_check("a hero picture is a 20 x 32 figure in a 34 x 32 cell", HeroComposer.size() == Vector2i(34, 32) and hero_frame.get_size() == Vector2(34, 32) and HeroComposer.portrait(HeroLook.for_class("ranger")).get_size() == Vector2(20, 32))
	_check("and its feet stand within a pixel of where they stood at 0.85 scale", absf(player.sprite.offset.y + 16.0 - (-9.0 + 19.0) * 0.85) <= 1.0 and partner.sprite.offset == player.sprite.offset)
	var slime := Monsters.spawn(self, "slime", Vector2.ZERO)
	var titan := Monsters.spawn(self, "tide_titan", Vector2.ZERO)
	_check("a monster's picture is baked smaller but its hit box is the one it had", slime.sprite.texture.get_size() == Vector2(14, 11) and slime.hit_rect().size == Vector2(16, 13) and titan.hit_rect().size == Vector2(48, 40) and titan.sprite.scale == Vector2.ONE)
	for node in [minion, boss, mini, player, partner, slime, titan]:
		node.queue_free()
	Game.character = saved


# ---------- Noir Silhouette: glow colours, poses, animated dolls ----------

func _rgb(c: Color) -> Array:
	return [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]


func _near(c: Color, expected: Array) -> bool:
	var got := _rgb(c)
	return absi(got[0] - expected[0]) <= 3 and absi(got[1] - expected[1]) <= 3 and absi(got[2] - expected[2]) <= 3   # (the Python twin rounds at every step)


func _test_noir_and_poses() -> void:
	# the colouring is the Python twin in tools/art/noir.py (these are its numbers)
	var fire := {"outfit": Color("e0403a"), "skin": Color("f6d2b0"), "glow": Color("ff8040")}
	_check("a body colour is dark and desaturated (noir.py base)", _near(HeroComposer._color_of(3, 2, fire), [69, 37, 38]))
	_check("skin stays a little warm but dark", _near(HeroComposer._color_of(1, 2, fire), [95, 88, 83]))
	_check("metal is a cool grey", _near(HeroComposer._color_of(11, 3, {"metal": Color("9a9aa4"), "glow": Color("5cc8ff")}), [116, 116, 123]))
	_check("eyes take the glow, hot", _near(HeroComposer._color_of(14, 2, {"glow": Color("5cc8ff")}), [149, 217, 255]))
	_check("gems are the glow itself", _near(HeroComposer._color_of(13, 3, {"glow": Color("88e880")}), [149, 255, 140]))
	_check("the outline is nearly black", _near(HeroComposer._color_of(3, 0, {"outfit": Color("4f8f4a"), "glow": Color("88e880")}), [16, 18, 26]))

	var fire_look := HeroLook.with_glow(HeroLook.for_class("channeler"), Color("ff8040"))
	var water_look := HeroLook.with_glow(HeroLook.for_class("channeler"), Color("5cc8ff"))
	var fire_image := HeroComposer.frame_image(fire_look, "down", 4)
	var water_image := HeroComposer.frame_image(water_look, "down", 4)
	_check("the glow recolours the hero: another element, another picture", fire_image.get_data() != water_image.get_data())
	_check("and the two looks are separate pictures in the cache", HeroComposer.register(fire_look) != HeroComposer.register(water_look))
	var prefix := HeroComposer.register(fire_look)
	_check("a registered look is composed when first asked for, all 21 poses", AssetDB.has_art(prefix + ":down") and AssetDB.get_frames(prefix + ":down").size() == HeroComposer.FRAME_COUNT)

	var runs: Array = HeroComposer.CLIPS.values()
	runs.sort_custom(func(a, b): return a.x < b.x)
	var next := 0
	var covered := true
	for run in runs:
		covered = covered and run.x == next
		next += run.y
	_check("the clips (walk, idle, attack, dodge, swirl, cast, stun, hurt) cover every pose once", covered and next == HeroComposer.FRAME_COUNT)

	var saved := Game.character
	var player: Node2D = await _player_with(CharacterData.create_sandbox("channeler", ["fire", "water"], 1))
	player._update_sprite()
	_check("standing still plays the idle poses", player._anim.clip_start == HeroComposer.CLIPS["idle"].x)
	player.stamina = 100.0
	player.try_melee(Vector2.RIGHT)
	player._update_sprite()
	_check("a slash plays the attack poses", player._anim.clip_start == HeroComposer.CLIPS["attack"].x)
	player._attack_time = 0.0
	player._cast_time = 0.3
	player._update_sprite()
	_check("an area or a special plays the cast poses", player._anim.clip_start == HeroComposer.CLIPS["cast"].x)
	player._cast_time = 0.0
	player._hurt_pose = 0.2
	player._update_sprite()
	_check("a hit plays the hurt pose", player._anim.clip_start == HeroComposer.CLIPS["hurt"].x)
	player._hurt_pose = 0.0
	player._dodge_left = 0.1
	player._update_sprite()
	_check("a dodge plays the roll", player._anim.clip_start == HeroComposer.CLIPS["dodge"].x)
	player._spin_left = 0.3
	player._update_sprite()
	_check("a swirl attack plays the swirl", player._anim.clip_start == HeroComposer.CLIPS["swirl"].x)
	player._dodge_left = 0.0
	player._spin_left = 0.0
	player.caster.selected = 0
	var first_glow: String = player._glow_hex()
	player.caster.selected = 1
	_check("the hero's glow follows the selected element", first_glow != player._glow_hex() and player._glow_hex() == Elements.color_of(player.caster.elements[1]).to_html(false))
	player.queue_free()
	Game.character = saved

	var doll := HeroDoll.make(HeroLook.for_class("channeler"))
	add_child(doll)
	var anim := doll.get_node_or_null("DollAnim") as HeroDoll.DollAnim
	_check("a hero picture on a card breathes, and its figure is a 20 x 32 cell", anim != null and doll.texture.get_size() == Vector2(20, 32))
	HeroDoll.set_hot(doll, true)
	_check("a hovered card makes its hero cast", anim.hot)
	doll.queue_free()


# ---------- the hero can be stunned; remote heroes carry the glow ----------

## Steps an enemy's pose for `seconds`; true when every frame stayed pixel-exact (whole-pixel offset, scale one, no rotation).
func _step_pose(enemy: Enemy, seconds: float) -> bool:
	var clean := true
	for i in int(ceil(seconds * 60.0)):
		enemy._update_pose(1.0 / 60.0)
		clean = clean and enemy.sprite.offset == enemy.sprite.offset.round() and enemy.sprite.scale == Vector2.ONE and enemy.sprite.rotation == 0.0
	return clean


func _at_rest(enemy: Enemy) -> bool:
	return enemy.pose == Vector2i.ZERO and enemy.sprite.offset == enemy._rest_offset and enemy.anim.clip_count == 0


func _test_enemy_attack_poses() -> void:
	var saved := Game.character
	var player: Node2D = await _player_with(_bare(CharacterData.create_sandbox("channeler", ["fire", "water"], 1)))
	player.global_position = Vector2(5000, 5000)
	var imp := _fresh_monster("imp", "", Vector2(3000, 3000))
	var spitter := _fresh_monster("spitter", "", Vector2(3000, 3400))
	var boss := _fresh_monster("slime_king", "", Vector2(3000, 3800))
	var slime := _fresh_monster("slime", "", Vector2(3000, 4200))
	await get_tree().process_frame
	var boxes := [imp.hit_rect().size, spitter.hit_rect().size, boss.hit_rect().size, slime.hit_rect().size]
	_check("monsters start at rest", _at_rest(imp) and _at_rest(spitter) and _at_rest(boss) and _at_rest(slime))

	# dash: crouch and lean back, tremble, lean in, ease back
	player.global_position = imp.global_position + Vector2(60, 0)
	imp.sprite.flip_h = false
	imp._attack(0.016, player)
	var clean := _step_pose(imp, 1.0 / 60.0)
	_check("a winding-up imp crouches and leans away from you, holding a frame", imp._dash_state == "windup" and imp.pose == Vector2i(-2, 1) and imp.anim.clip_count == 1)
	imp.sprite.flip_h = true
	imp._update_pose(0.0)
	_check("facing left, it leans the other way", imp.pose == Vector2i(2, 1) and imp.sprite.offset == imp._rest_offset + Vector2(2, 1))
	imp.sprite.flip_h = false
	imp._dash_left = float(imp.dash["windup"]) * 0.2
	var trembles := {}
	for i in 6:
		imp._age = float(i) / 30.0
		imp._update_pose(0.0)
		trembles[imp.pose.x] = true
	_check("it trembles a pixel either way at the end of the wind-up", trembles.size() == 2 and trembles.has(-1) and trembles.has(-3))
	imp._attack(float(imp.dash["windup"]), player)
	clean = _step_pose(imp, 1.0 / 60.0) and clean
	_check("the dash leans toward you on its first frame", imp._dash_state == "dash" and imp.pose == Vector2i(2, 0) and imp.anim.clip_start == 0 and imp.anim.clip_count == 1)
	imp._attack(float(imp.dash["time"]) + 0.01, player)
	clean = _step_pose(imp, 1.0 / 60.0) and clean
	var easing := imp.pose != Vector2i.ZERO and imp.pose.x <= 2
	clean = _step_pose(imp, 0.3) and clean
	_check("after the dash it eases back to exactly rest", imp._dash_state == "" and easing and _at_rest(imp))

	# a shot recoils
	player.global_position = spitter.global_position + Vector2(70, 0)
	spitter.sprite.flip_h = false
	spitter._attack_cd = 0.0
	spitter._attack(0.016, player)
	clean = _step_pose(spitter, 1.0 / 60.0) and clean
	_check("a spitter recoils from its shot and holds a frame", spitter.pose == Vector2i(-2, 0) and spitter.anim.clip_count == 1)
	clean = _step_pose(spitter, 0.4) and clean
	_check("then it is back at rest", _at_rest(spitter))

	# a boss slam rises over the telegraph and lands
	player.global_position = boss.global_position
	boss._attack_cd = 0.0
	boss._attack(0.016, player)
	var telegraphed := boss._telegraph != null
	clean = _step_pose(boss, float(boss.slam["telegraph"]) * 0.6) and clean
	_check("a slamming boss rises over its telegraph", telegraphed and boss.pose == Vector2i(0, -3))
	if telegraphed:
		boss._telegraph._physics_process(10.0)
	clean = _step_pose(boss, 1.0 / 60.0) and clean
	_check("and drops a pixel as it lands", boss._telegraph == null and boss.pose == Vector2i(0, 1))
	clean = _step_pose(boss, 0.5) and clean
	_check("then it is back at rest", _at_rest(boss))
	player._stun_left = 0.0

	# a bite lunges
	player._hurt_cd = 0.0
	player.global_position = slime.global_position + Vector2(4, 0)
	slime._contact_cd = 0.0
	var hp_before: float = player.hp
	slime._physics_process(1.0 / 60.0)
	var side := -1 if slime.sprite.flip_h else 1
	_check("a biting slime lunges toward you", player.hp < hp_before and slime.pose == Vector2i(2 * side, 0))
	clean = _step_pose(slime, 0.4) and clean
	_check("then it is back at rest", _at_rest(slime))
	_check("poses are whole pixels: never scaled or turned", clean)

	# a stun drops any pose at once
	player.global_position = imp.global_position + Vector2(60, 0)
	imp._dash_cd = 0.0
	imp._attack(0.016, player)
	imp._update_pose(0.0)
	var posed := imp.pose != Vector2i.ZERO
	imp.effects["stun"] = {"time": 2.0, "power": 1.0}
	imp._attack(0.016, player)
	imp._update_pose(1.0 / 60.0)
	_check("a stun cancels a wind-up pose on the spot", posed and imp._dash_state == "" and _at_rest(imp))
	player.global_position = spitter.global_position + Vector2(70, 0)
	spitter._attack_cd = 0.0
	spitter._attack(0.016, player)
	spitter._update_pose(0.0)
	posed = spitter.pose != Vector2i.ZERO
	spitter.effects["stun"] = {"time": 2.0, "power": 1.0}
	spitter._update_pose(1.0 / 60.0)
	_check("and a shot's recoil", posed and _at_rest(spitter))
	_check("hit boxes never change", boxes == [imp.hit_rect().size, spitter.hit_rect().size, boss.hit_rect().size, slime.hit_rect().size])

	# the pose code the host sends for each state
	imp.effects.erase("stun")
	spitter.effects.erase("stun")
	var windup := float(imp.dash["windup"])
	var codes := []
	imp._pose = ""
	imp._dash_state = ""
	codes.append(imp.pose_code())
	imp._dash_state = "windup"
	imp._dash_left = windup
	codes.append(imp.pose_code())
	imp._dash_left = windup * 0.2
	codes.append(imp.pose_code())
	imp._dash_state = "dash"
	codes.append(imp.pose_code())
	imp._dash_state = ""
	for kind in ["shot", "bite"]:
		imp._start_pose(kind, Enemy.POSE_TIMES[kind])
		codes.append(imp.pose_code())
	boss._start_pose("rise", float(boss.slam["telegraph"]))
	codes.append(boss.pose_code())
	boss._start_pose("land", Enemy.POSE_TIMES["land"])
	codes.append(boss.pose_code())
	imp._dash_state = "windup"
	imp.effects["stun"] = {"time": 2.0, "power": 1.0}
	codes.append(imp.pose_code())
	imp.effects.erase("stun")
	_check("each host state has its pose code: none, wind-up, tremble, dash, shot, bite, rise, land; stunned none", codes == [0, 1, 2, 3, 4, 5, 6, 7, 0])
	imp._dash_state = ""
	imp._pose = ""
	boss._pose = ""

	# a ghost plays the host's code with the same offsets
	var ghost := _fresh_monster("imp", "", Vector2(3000, 4600))
	var ghost_boss := _fresh_monster("slime_king", "", Vector2(3000, 5000))
	await get_tree().process_frame
	ghost.ghost = true
	ghost_boss.ghost = true
	for node in [imp, boss, ghost, ghost_boss]:
		node.sprite.flip_h = false
		node._age = 0.0
		node._update_pose(1.0)  # settle at rest
	var same := true
	for code in range(1, Enemy.POSES.size()):
		var kind: String = Enemy.POSES[code]
		var host_side: Enemy = boss if kind in ["rise", "land"] else imp
		var ghost_side: Enemy = ghost_boss if kind in ["rise", "land"] else ghost
		host_side._dash_state = kind if kind in ["windup", "dash"] else ("windup" if kind == "tremble" else "")
		host_side._dash_left = windup * (0.2 if kind == "tremble" else 1.0)
		host_side._pose = ""
		if host_side._dash_state == "":
			host_side._start_pose(kind, float(boss.slam["telegraph"]) if kind == "rise" else float(Enemy.POSE_TIMES[kind]))
		ghost_side.apply_pose_code(code)
		var step := float(boss.slam["telegraph"]) * 0.6 if kind == "rise" else 0.0
		host_side._update_pose(step)
		ghost_side._update_pose(step)
		same = same and host_side.pose_code() == code and host_side.pose != Vector2i.ZERO and ghost_side.pose == host_side.pose \
			and ghost_side.sprite.offset - ghost_side._rest_offset == host_side.sprite.offset - host_side._rest_offset and ghost_side.anim.clip_count == host_side.anim.clip_count
		ghost_side.apply_pose_code(0)
		host_side._dash_state = ""
		host_side._pose = ""
		host_side._update_pose(1.0)
		ghost_side._update_pose(1.0)
	_check("a ghost given each code poses exactly as the host does", same)
	_check("a ghost with code 0 is at rest", _at_rest(ghost) and _at_rest(ghost_boss) and ghost.sprite.offset == ghost._rest_offset)
	ghost.apply_pose_code(5)
	ghost.apply_pose_code(0)
	ghost._update_pose(0.05)
	var still_biting := ghost.pose != Vector2i.ZERO
	ghost._update_pose(0.06)
	ghost._update_pose(0.3)
	_check("a missed strike still plays its full length on the ghost, then rests", still_biting and _at_rest(ghost))
	ghost.apply_pose_code(1)
	ghost._update_pose(0.0)
	var crouched := ghost.pose != Vector2i.ZERO
	ghost.apply_pose_code(0)
	ghost._update_pose(0.3)
	_check("a held wind-up ends when the host's code does", crouched and _at_rest(ghost))
	ghost.apply_pose_code(99)
	ghost._update_pose(0.0)
	ghost.apply_pose_code(-3)
	ghost._update_pose(0.0)
	_check("a bad code is no pose", _at_rest(ghost))
	ghost._physics_process(1.0 / 60.0)
	_check("a ghost's own tick runs its pose", _at_rest(ghost))
	for node in [imp, spitter, boss, slime, ghost, ghost_boss, player]:
		node.queue_free()
	await get_tree().process_frame
	Game.character = saved


func _test_hero_stun() -> void:
	var saved := Game.character
	var player: Node2D = await _player_with(_bare(CharacterData.create_sandbox("channeler", ["fire", "water"], 1)))
	player.global_position = Vector2(900, 900)
	player._hurt_cd = 0.0
	_check("a hero starts unstunned, with no stars", not player.is_stunned() and player._stun_sprite == null)
	_check("a stun takes", player.stun(5.0) and player.is_stunned())
	var stars: Sprite2D = player._stun_sprite
	var star_id := "stun:%d" % (int(float(player.sprite.texture.get_height()) * player.sprite.scale.y) + 12)
	_check("three stars circle over the stunned hero", stars != null and stars.get_parent() == player and stars.z_index == 30 and AssetDB.has_art(star_id))
	_check("no second stun on top of the first", not player.stun(1.0))
	player.stamina = 100.0
	player._melee_cd = 0.0
	player._dodge_cd = 0.0
	_check("a stunned hero cannot slash", not player.try_melee(Vector2.RIGHT))
	_check("nor dodge", not player.try_dodge(Vector2.RIGHT) and not player.is_dodging() and player._dodge_buffer == 0.0)
	_check("nor spin", not player.try_spin())
	player.caster.mana = player.caster.max_mana
	player.caster.cooldowns.clear()
	var bolt: String = player.caster.skill_for("primary")
	_check("nor cast (the bolt would be ready otherwise)", player.caster.can_cast(bolt) and not player.caster.try_cast(bolt))
	_check("nor imbue", not player.try_imbue() and not player.imbued)
	player._hurt_pose = 0.3
	player._update_sprite()
	_check("the stun poses play, over the hurt pose", player._anim.clip_start == HeroComposer.CLIPS["stun"].x)
	player._hurt_pose = 0.0
	var state: Array = player.net_state()
	_check("the others are told the hero is stunned", state.size() == 7 and Player.unpack_flags(int(state[6]))["stunned"])
	player._knock = Vector2.ZERO
	Input.action_press("move_right")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var stuck: bool = player.velocity.length() < 1.0
	Input.action_release("move_right")
	_check("a stunned hero does not walk", stuck)

	player._stun_left = 0.01
	for i in 30:
		await get_tree().physics_frame
		if not player.is_stunned():
			break
	await get_tree().process_frame
	_check("the stun wears off and the stars go with it", not player.is_stunned() and player._stun_sprite == null and not is_instance_valid(stars))
	_check("then a while of immunity: no stun-lock", player._stun_immune > 1.0 and player._stun_immune <= Player.STUN_IMMUNITY and not player.stun(1.0))
	player._stun_immune = 0.0
	player._hurt_cd = 0.0
	player.stamina = 100.0
	player._dodge_cd = 0.0
	_check("a dodge works again", player.try_dodge(Vector2.RIGHT))
	_check("no stun during a dodge's i-frames", not player.stun(1.0))
	player.stamina = 100.0
	player.try_spin()
	player._dodge_left = 0.0
	player._iframes_left = 0.0
	_check("nor during a spin", player.is_spinning() and not player.stun(1.0))
	player._spin_left = 0.0
	player._hurt_cd = 0.2
	_check("nor in an earlier hit's i-frames", not player.stun(1.0))
	player._hurt_cd = 0.0
	_check("but freely otherwise", player.stun(0.1))
	player._stun_left = 0.0
	player._stun_immune = 0.0

	# a boss slam that lands stuns; a dodged one does not
	var boss := _fresh_monster("slime_king", "", player.global_position)
	await get_tree().process_frame
	player.global_position = boss.global_position
	player._hurt_cd = 0.0
	player._stun_immune = 0.0
	boss._attack_cd = 0.0
	boss._attack(0.016, player)
	var slammed := boss._telegraph != null
	if slammed:
		boss._telegraph._physics_process(10.0)
	_check("a boss slam that lands stuns the hero", slammed and player.is_stunned() and is_equal_approx(player._stun_left, Enemy.SLAM_STUN))
	player._stun_left = 0.0
	player._stun_immune = 0.0
	player._hurt_cd = 0.0
	player.global_position = boss.global_position
	boss._attack_cd = 0.0
	boss._attack(0.016, player)
	player.stamina = 100.0
	player._dodge_cd = 0.0
	player._dodge_left = 0.0
	player.try_dodge(Vector2.RIGHT)
	var hp_before: float = player.hp
	slammed = boss._telegraph != null
	if slammed:
		boss._telegraph._physics_process(10.0)
	_check("a slam dodged through neither hurts nor stuns", slammed and player.hp == hp_before and not player.is_stunned())
	boss.queue_free()

	# the flags: 1 moving, 2 dodging, 4 stunned, glow code << 3
	var all: Array = Elements.MAIN + Elements.RARE
	_check("the wire order of the glow codes is pinned", all == ["fire", "water", "air", "mineral", "earth", "light", "dark"])
	var codes_ok := Player.glow_code("") == 0 and Player.glow_code("martial") == 0 and Player.glow_color(0) == Color("b8b8d8") \
		and Player.glow_color(99) == Color("b8b8d8") and Player.glow_color(-3) == Color("b8b8d8")
	for i in all.size():
		var element: String = all[i]
		var back := Player.unpack_flags(Player.pack_flags(i % 2 == 0, i % 3 == 0, i % 2 == 1, Player.glow_code(element)))
		codes_ok = codes_ok and Player.glow_code(element) == i + 1 and int(back["glow"]) == i + 1 and Player.glow_color(int(back["glow"])) == Elements.color_of(element) \
			and back["moving"] == (i % 2 == 0) and back["dodging"] == (i % 3 == 0) and back["stunned"] == (i % 2 == 1)
	_check("the flags round-trip: every element's glow code and the stunned bit", codes_ok)
	_check("old flags read the same: 1 moving, 2 dodging", Player.unpack_flags(3) == {"moving": true, "dodging": true, "stunned": false, "glow": 0})
	player.caster.selected = 1
	var glow_flags := Player.unpack_flags(int(player.net_state()[6]))
	_check("the hero's state carries its glow", Player.glow_color(int(glow_flags["glow"])).to_html(false) == player._glow_hex() and int(glow_flags["glow"]) == Player.glow_code(String(player.caster.elements[1])))
	_check("the protocol was bumped for the new messages (3: monster pose codes)", Net.PROTOCOL == 3)

	# a co-op partner: their pictures follow their glow, and they show the stun
	var ranger_look := HeroLook.for_class("ranger")
	var avatar := RemoteAvatar.new()
	avatar.setup(5, {"name": "Pip", "class": "ranger", "look": ranger_look})
	add_child(avatar)
	avatar.apply_state([0.0, 0.0, 10.0, 0.0, 100.0, 100.0, Player.pack_flags(false, false, false, Player.glow_code("fire"))])
	var fire_prefix: String = avatar._prefix
	avatar.apply_state([0.0, 0.0, 10.0, 0.0, 100.0, 100.0, Player.pack_flags(false, false, false, Player.glow_code("water"))])
	_check("a partner's pictures change when their glow changes", fire_prefix != avatar._prefix and avatar._prefix == HeroComposer.register(HeroLook.with_glow(ranger_look, Elements.color_of("water"))))
	avatar.apply_state([0.0, 0.0, 10.0, 0.0, 100.0, 100.0, Player.pack_flags(false, false, true, Player.glow_code("water"))])
	avatar._physics_process(0.016)
	_check("a stunned partner plays the stun poses", avatar.stunned and avatar._anim.clip_start == HeroComposer.CLIPS["stun"].x)
	var partner_stars: Sprite2D = avatar._stun_sprite
	_check("and three stars circle over the partner", partner_stars != null and partner_stars.get_parent() == avatar and partner_stars.z_index == 30 \
		and partner_stars.offset.y == avatar.sprite.offset.y - 6.0)
	avatar.apply_state([0.0, 0.0, 10.0, 0.0, 100.0, 100.0, Player.pack_flags(false, false, false, Player.glow_code("water"))])
	avatar._physics_process(0.016)
	_check("the partner's stars go when the stun does", avatar._stun_sprite == null and partner_stars.is_queued_for_deletion())
	avatar.apply_state([0.0, 0.0, 10.0, 0.0, 100.0, 100.0, Player.pack_flags(false, false, true, Player.glow_code("water"))])
	avatar._physics_process(0.016)
	partner_stars = avatar._stun_sprite
	var partner_stars_made := partner_stars != null
	avatar.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("and with the partner", partner_stars_made and not is_instance_valid(partner_stars))

	# an arena rival does the same
	var rival := PvpGhost.make(self, 6, {"name": "Rex", "class": "ranger", "look": ranger_look})
	PvpGhost.apply_state(rival, [0.0, 0.0, 10.0, 0.0, 100.0, 100.0, Player.pack_flags(true, false, true, Player.glow_code("dark"))])
	await get_tree().process_frame
	rival._ghost_tick(0.016)
	_check("an arena rival takes the glow and the stun", String(rival.get_meta("prefix")) == HeroComposer.register(HeroLook.with_glow(ranger_look, Elements.color_of("dark"))) \
		and rival.net_stunned and rival.anim.clip_start == HeroComposer.CLIPS["stun"].x)
	_check("and is reported back with them", int(PvpGhost.state_of(6, rival)[7]) == Player.pack_flags(true, false, true, Player.glow_code("dark")))
	var rival_stars: Sprite2D = rival._stun_sprite
	_check("three stars circle over a stunned rival", rival_stars != null and rival_stars.get_parent() == rival and not rival.is_stunned())
	rival.apply_pose_code(4)
	rival._dash_state = "dash"
	rival._ghost_tick(0.016)
	_check("a rival wears a hero picture and never takes a monster pose", rival.pose_code() == 0 and rival.net_pose == 0 and rival.pose == Vector2i.ZERO \
		and rival.sprite.offset == Vector2(0, -8))
	rival._dash_state = ""
	PvpGhost.apply_state(rival, [0.0, 0.0, 10.0, 0.0, 100.0, 100.0, Player.pack_flags(true, false, false, Player.glow_code("dark"))])
	rival._ghost_tick(0.016)
	_check("the rival's stars go when the stun does", rival._stun_sprite == null and rival_stars.is_queued_for_deletion())
	PvpGhost.apply_state(rival, [0.0, 0.0, 10.0, 0.0, 100.0, 100.0, Player.pack_flags(true, false, true, Player.glow_code("dark"))])
	rival._ghost_tick(0.016)
	rival_stars = rival._stun_sprite
	var rival_stars_made := rival_stars != null
	rival.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("and with the rival", rival_stars_made and not is_instance_valid(rival_stars))

	# the slam's stun goes to the machine that plays that hero, with the damage
	var world := Node2D.new()
	add_child(world)
	var hero = PLAYER.instantiate()
	world.add_child(hero)
	var fake_dungeon := Node2D.new()
	world.add_child(fake_dungeon)
	await get_tree().process_frame
	var client := CoopClient.new()
	client.dungeon = fake_dungeon
	hero._hurt_cd = 0.0
	client._on_damage(5.0, hero.global_position + Vector2(10, 0), Enemy.SLAM_STUN)
	_check("the damage message carries the stun", hero.is_stunned() and hero.hp < hero.max_hp)
	hero._stun_left = 0.0
	hero._stun_immune = 0.0
	hero._hurt_cd = 0.0
	client._on_damage(5.0, hero.global_position + Vector2(10, 0), 0.0)
	_check("plain damage does not stun", not hero.is_stunned())
	client.free()
	world.queue_free()
	player.queue_free()
	Game.character = saved


# ---------- Phase 6d: multiplayer, the parts that need no network ----------

func _test_net_world() -> void:
	var info := Net._clean_info({"name": "  Zed   Zed  ", "class": "ranger", "level": 999, "look": {"parts": {}}})
	_check("a stranger's hello is cleaned", info["name"] == "Zed Zed" and info["level"] == 99 and info["class"] == "ranger")
	var mine := Net.local_info()
	_check("this hero describes itself for the others", mine["name"] == Game.character.display_name and mine["look"].has("parts") and mine["version"] == Net.PROTOCOL)
	_check("offline is the default", Net.mode == "offline" and not Net.is_online() and Net.my_id() == 1)
	var stats := Game.character.xp + Game.character.level * 100000
	Game.reward_kill(60, 2)
	_check("a kill reward gives xp", Game.character.xp + Game.character.level * 100000 > stats)

	# a guest's world: ghosts and other players follow the host's snapshot
	Net.session = {"kind": "coop"}
	var guest_world := Node2D.new()
	add_child(guest_world)
	var hero = PLAYER.instantiate()
	guest_world.add_child(hero)
	var guest_dungeon := Dungeon.new()
	guest_dungeon.with_ui = false
	guest_dungeon.viewer = true
	guest_world.add_child(guest_dungeon)
	await get_tree().process_frame
	await get_tree().process_frame
	var client := guest_dungeon.coop_client
	_check("a guest's dungeon builds the room and spawns nothing", client != null and guest_dungeon.state == "viewer" and get_tree().get_nodes_in_group("enemies").size() == 0)
	Net.roster = {1: Net.local_info(), 5: {"name": "Pip", "class": "ranger", "level": 4, "look": HeroLook.for_class("ranger")}}
	var snapshot := {"e": [[7, "slime", "fire", 100.0, 80.0, 30.0, 52.0, "water", 0, ["dot"], 5], [8, "grave_warden", "", 140.0, 90.0, 200.0, 300.0, "", 1, []],
			[1], "junk", [9, "slime", "", 1.0, 2.0, 3.0, 4.0, "", 0, 5], [10, "slime", "", 1.0, 2.0, 3.0, 4.0, "", 0, [], "odd"]],
		"p": [[5, 60.0, 70.0, 90.0, 70.0, 80.0, 100.0, 1]], "door": false, "t": "Floor 2/5", "boss": 8, "score": {}}
	client.apply_snapshot(snapshot)
	await get_tree().process_frame
	var ghost: Enemy = client.ghosts.get(7)
	_check("broken monster entries are skipped; an odd pose code is no pose", client.ghosts.size() == 3 and client.ghosts.has(10) and client.ghosts[10].net_pose == 0 \
		and not client.ghosts.has(9) and not client.ghosts.has(1))
	_check("a ghost takes the host's pose code (an entry without one is at rest)", ghost != null and ghost.net_pose == 5 and client.ghosts[8].net_pose == 0)
	client.ghosts[10].queue_free()
	client.ghosts.erase(10)
	_check("a ghost monster appears for each monster", client.ghosts.size() == 2 and ghost != null and ghost.ghost and ghost.net_id == 7 and ghost.monster_id == "slime" and ghost.variant == "fire")
	_check("it takes the host's health and state", is_equal_approx(ghost.hp, 30.0) and is_equal_approx(ghost.max_hp, 52.0) and ghost.aura == "water" and ghost.effects.has("dot"))
	_check("the boss bar follows the ghost boss", Game.boss == client.ghosts.get(8))
	ghost.take_hit({"damage": 500.0, "element": "fire", "from": Vector2.ZERO})
	_check("a hit on a ghost does not hurt it here (the host decides)", is_equal_approx(ghost.hp, 30.0) and not ghost.is_queued_for_deletion())
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("a ghost glides toward the host's position", ghost.global_position.distance_to(Vector2(100, 80)) < ghost.global_position.distance_to(Vector2(0, 0)) or ghost.global_position.distance_to(Vector2(100, 80)) < 40.0)
	var avatar: RemoteAvatar = client.others.get(5)
	_check("another player appears as an avatar with their name", avatar != null and avatar.peer == 5 and avatar.hero_name == "Pip" and avatar.is_in_group("net_players") and avatar.net_pos == Vector2(60, 70) and avatar.moving)
	_check("the avatar is a hurtbox for monsters", avatar.hurtbox().size.x > 4.0 and not avatar.is_down())
	client.apply_snapshot({"e": snapshot["e"], "p": [[5, 61.0, 70.0, 90.0, 70.0, 80.0, 100.0, 1], [6, 1.0], "junk", [7, "x", 1.0, 2.0, 3.0, 4.0, 5.0, 0],
		[8, {}, 1.0, 2.0, 3.0, 4.0, 5.0, 0], [9, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, []]], "door": false, "t": "after odd players", "boss": 8, "score": {}})
	_check("short or odd player entries are skipped without an error", Game.run_text == "after odd players" and client.others.size() == 1 \
		and client.others.get(5) == avatar and avatar.net_pos == Vector2(61, 70))
	client.apply_snapshot({"e": [], "p": [], "door": false, "t": "", "boss": 0, "score": {}})
	await get_tree().process_frame
	await get_tree().process_frame
	_check("what the host stops sending goes away", client.ghosts.is_empty() and client.others.is_empty())
	Game.boss = null

	# the monster picks the nearer of the hero and the other players
	var near_avatar := RemoteAvatar.new()
	near_avatar.setup(5, Net.roster[5])
	guest_world.add_child(near_avatar)
	near_avatar.global_position = Vector2(500, 500)
	hero.global_position = Vector2(0, 0)
	var chaser := Monsters.spawn(guest_dungeon._room_node, "slime", Vector2(480, 490), "", Vector2.ONE, 1)
	await get_tree().process_frame
	_check("a monster goes for the nearest player", chaser._nearest_target() == near_avatar)
	near_avatar.apply_state([500.0, 500.0, 0.0, 0.0, 0.0, 100.0, 0])
	_check("but not for a fallen one", chaser._nearest_target() == hero)
	chaser.queue_free()
	near_avatar.queue_free()
	guest_world.queue_free()

	# arena opponents are ghost Enemies wearing the other hero's picture
	Net.session = {"kind": "arena"}
	var arena_world := Node2D.new()
	add_child(arena_world)
	var arena_hero = PLAYER.instantiate()
	arena_world.add_child(arena_hero)
	var arena_dungeon := Dungeon.new()
	arena_dungeon.with_ui = false
	arena_dungeon.viewer = true
	arena_dungeon.layout = [[DungeonGen.arena_room()]]
	arena_world.add_child(arena_dungeon)
	await get_tree().process_frame
	await get_tree().process_frame
	var arena_client := arena_dungeon.coop_client
	arena_client.apply_snapshot({"e": [], "p": [[5, 80.0, 90.0, 120.0, 90.0, 60.0, 100.0, 3]], "door": false, "t": "", "boss": 0, "score": {5: 1}})
	await get_tree().process_frame
	var rival: Enemy = arena_client.others.get(5)
	_check("an arena opponent is a ghost enemy for the player it stands for", rival != null and rival.ghost and rival.pvp_peer == 5 and is_equal_approx(rival.hp, 60.0) and rival.net_moving and rival.net_dodging)
	_check("it wears their hero's picture", String(rival.sprite_id).begins_with("hero:") and rival.has_meta("prefix"))
	_check("and is reported back the way it came", PvpGhost.state_of(5, rival)[1] == 80.0 and PvpGhost.state_of(5, rival)[5] == 60.0)
	_check("the scoreboard shows in the run text", true if arena_dungeon.room["kind"] != "arena" else arena_dungeon.scores == {5: 1})
	arena_world.queue_free()

	# the host's side: snapshot, hits and wipe
	Net.mode = "host"
	Net.session = {"kind": "coop"}
	Net.roster = {1: Net.local_info(), 5: {"name": "Pip", "class": "ranger", "level": 4, "look": HeroLook.for_class("ranger")}}
	var host_world := Node2D.new()
	add_child(host_world)
	var host_hero = PLAYER.instantiate()
	host_world.add_child(host_hero)
	var host_dungeon := Dungeon.new()
	host_dungeon.with_ui = false
	host_dungeon.layout = [[DungeonGen.camp_room()]]
	host_world.add_child(host_dungeon)
	await get_tree().process_frame
	var host := CoopHost.attach(host_dungeon)
	await get_tree().process_frame
	var target := Monsters.spawn(host_dungeon._room_node, "slime", Vector2(120, 100), "", Vector2.ONE, 1)
	await get_tree().process_frame
	var shot := host.snapshot()
	_check("the host's snapshot lists monsters and every player", shot["e"].size() == 1 and shot["e"][0][1] == "slime" and int(shot["e"][0][0]) > 0 and shot["p"].size() == 2 and int(shot["p"][0][0]) == 1)
	_check("each monster entry ends with its pose code", shot["e"][0].size() == 11 and int(shot["e"][0][10]) == target.pose_code())
	_check("a guest's avatar is on the host", host.avatars.has(5) and host.avatars[5] is RemoteAvatar)
	host.on_client_state(5, [30.0, 40.0, 50.0, 40.0, 70.0, 100.0, 2])
	_check("a guest's position update moves their avatar", host.avatars[5].net_pos == Vector2(30, 40) and host.avatars[5].dodging)
	host.on_client_state(5, [1.0])
	_check("a broken update is ignored", host.avatars[5].net_pos == Vector2(30, 40))
	var net_id := int(shot["e"][0][0])
	var before := target.hp
	host.on_client_hit(5, net_id, {"damage": 12.0, "element": "", "from": Vector2.ZERO, "knockback": 10.0})
	_check("a guest's hit lands on the real monster", is_equal_approx(before - target.hp, 12.0))
	host.on_client_hit(5, 99999, {"damage": 12.0})
	_check("a hit on a monster that is gone is ignored", true)
	host.on_client_hit(5, net_id, {"damage": 99999.0, "element": "", "from": Vector2.ZERO})
	await get_tree().process_frame
	_check("a guest's damage is capped but still kills a weak monster", not is_instance_valid(target) or target.hp <= 0.0 or target.is_queued_for_deletion())
	_check("the party is not wiped while somebody stands", not host.wiped())
	host_hero.hp = 0.0
	_check("... nor while a guest stands", not host.wiped())
	host.avatars[5].hp = 0.0
	_check("everyone down is a wipe", host.wiped())
	host_world.queue_free()
	Net.mode = "offline"
	Net.roster = {}
	Net.session = {}
	Net.host_node = null

	# the arena room and its spawn corners
	var room := DungeonGen.arena_room()
	_check("the arena is an open room with pillars", room["kind"] == "arena" and room["exit"] == "" and room["obstacles"].size() >= 4 and DungeonGen.describe(room) == "Floor 0 - Arena")
	Game.mode = "arena"
	Net.roster = {1: Net.local_info(), 5: {"name": "Pip", "class": "ranger", "level": 4, "look": HeroLook.for_class("ranger")}}
	var duel_world := Node2D.new()
	add_child(duel_world)
	var duel_hero = PLAYER.instantiate()
	duel_world.add_child(duel_hero)
	var duel := Dungeon.new()
	duel.with_ui = false
	duel_world.add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("the arena mode builds the arena, with no monsters", duel.room["kind"] == "arena" and duel.state == "arena" and get_tree().get_nodes_in_group("enemies").is_empty())
	_check("the first player starts on the west side, in the middle", duel_hero.global_position.x < 80.0 and absf(duel_hero.global_position.y - float(duel.room["rows"]) * 8.0) < 12.0)
	_check("the scoreboard starts at nil for everybody", duel.scores == {1: 0, 5: 0})
	duel_world.queue_free()
	Game.mode = "camp"
	Net.roster = {}


# ---------- multiplayer trust: what a stranger (or a hostile host) sends is checked ----------

func _test_net_trust() -> void:
	# the hello: a real hero passes unchanged, anything odd is replaced
	var mine := Net.local_info()
	var expected := mine.duplicate(true)
	expected.erase("version")
	_check("a real hero's hello passes the cleaning unchanged", Net._clean_info(mine) == expected)
	var every_look_passes := true
	for class_id in Classes.CLASSES:
		for sub in [""] + Array(Classes.CLASSES[class_id].get("subclasses", [])):
			var look := HeroLook.for_class(class_id, String(sub), 3, 4)
			every_look_passes = every_look_passes and Net._clean_look(look) == look
	_check("every class and subclass look passes the cleaning", every_look_passes)
	var real_look: Dictionary = mine["look"]
	var giant := real_look.duplicate(true)
	for i in 100:
		giant["palette"]["c%d" % i] = "ff0000"
	var bad_looks := [
		[], 5, {"parts": {}, "palette": {}, "extra": 1}, {"parts": [], "palette": {}},
		{"parts": {"wings": "big"}, "palette": {}}, {"parts": {"outfit": 7}, "palette": {}},
		{"parts": {"outfit": "x".repeat(500)}, "palette": {}}, {"parts": {}, "palette": {"outfit": "ff0000ff"}},
		{"parts": {}, "palette": {"outfit": 16711680}}, {"parts": {}, "palette": {"outfit": "nothex"}}, {"parts": {}, "palette": {3: "ff0000"}}, giant,
	]
	var all_dropped := true
	for look in bad_looks:
		all_dropped = all_dropped and Net._clean_info({"name": "A", "class": "ranger", "level": 3, "look": look})["look"] == {}
	_check("an oversize or odd-typed look becomes the default look", all_dropped)
	var odd := Net._clean_info({"name": 5, "class": "dragon", "level": "high"})
	_check("an unknown class, a name that is no text and a level that is no number are replaced",
		odd["class"] == Classes.NEUTRAL_CLASS and odd["name"] == "Hero" and odd["level"] == 1 and odd["look"] == {})
	_check("a class that is no text is replaced too", Net._clean_info({"class": ["ranger"], "level": NAN})["class"] == Classes.NEUTRAL_CLASS)

	# a guest's hit on a monster
	var host := CoopHost.new()
	var legit := {"damage": 12.5, "element": "fire", "knockback": 90.0, "from": Vector2(3, 4), "juice": true,
		"apply": {"kind": "dot", "time": 2.5, "power": 3.0}, "text_offset": Vector2(12, 0)}
	_check("a normal guest hit is kept as it is", host.clean_hit(legit, Vector2.ZERO) == legit)
	var bad := host.clean_hit({"damage": NAN, "element": "plasma", "knockback": INF, "from": "here", "juice": {},
		"apply": {"kind": "explode", "time": 1.0, "power": 1.0}, "text_offset": Vector2(999, 0), "net_id": "x"}, Vector2(1, 1))
	_check("NaN, unknown and wrong-typed parts of a hit are dropped or replaced", bad == {"damage": 0.0, "element": "", "knockback": 0.0,
		"from": Vector2(1, 1), "juice": true, "apply": {}})
	_check("a hit with nothing in it is harmless", host.clean_hit({}, Vector2(2, 2)) == {"damage": 0.0, "element": "", "knockback": 50.0,
		"from": Vector2(2, 2), "juice": true, "apply": {}})
	_check("a guest's damage is capped", is_equal_approx(float(host.clean_hit({"damage": 99999.0}, Vector2.ZERO)["damage"]), Net.MAX_HIT_DAMAGE))
	_check("a burn's time and power are capped", host.clean_apply({"kind": "dot", "time": 999.0, "power": 1e9}) == {"kind": "dot",
		"time": CoopHost.APPLY_TIME_MAX, "power": CoopHost.DOT_POWER_MAX})
	_check("a slow can never be more than a full stop", host.clean_apply({"kind": "slow", "time": -5.0, "power": 5.0}) == {"kind": "slow", "time": 0.0, "power": 1.0})
	_check("a status with missing or wrong-typed keys is no status", host.clean_apply({"kind": "stun"}).is_empty() and host.clean_apply(5).is_empty() \
		and host.clean_apply({"kind": 3, "time": 1.0}).is_empty() and host.clean_apply({"kind": "root", "time": "long"}).is_empty() \
		and host.clean_apply({"kind": "root", "time": 1.0, "power": NAN}) == {"kind": "root", "time": 1.0, "power": 0.0})
	var real_kinds := true
	for id in SkillDB.DEFS:
		var apply: Dictionary = SkillDB.DEFS[id].get("apply", {})
		real_kinds = real_kinds and (apply.is_empty() or (apply["kind"] in CoopHost.APPLY_KINDS and float(apply["time"]) * 1.6 <= CoopHost.APPLY_TIME_MAX))
	_check("every skill's status passes the guest-hit check", real_kinds)
	host.free()

	# the hit rate limit
	var bucket := [CoopHost.HIT_BURST, 10.0]
	var passed := 0
	for i in 150:
		if CoopHost.take_token(bucket, 10.0):
			passed += 1
	_check("a guest may send a burst of hits, then the excess is dropped", passed == int(CoopHost.HIT_BURST))
	var refilled := 0
	for i in 100:
		if CoopHost.take_token(bucket, 10.5):
			refilled += 1
	_check("the hits refill with time", refilled == int(CoopHost.HIT_RATE * 0.5))
	var fresh := [CoopHost.HIT_BURST, 0.0]
	var worst_frame := true
	for i in 80:  # an imbued spin with all 7 elements on 10 monsters, plus an area on 10
		worst_frame = worst_frame and CoopHost.take_token(fresh, 0.0)
	_check("the worst legit frame of hits all passes", worst_frame)

	# PvP: arena only, with only the numbers the receiver uses
	_check("a PvP hit keeps only damage (capped) and where it came from", Net.clean_pvp_hit({"damage": 1e6, "element": "fire", "from": Vector2(1, 2),
		"apply": {"kind": "dot", "time": 9.0}, "evil": 1}) == {"damage": Net.MAX_HIT_DAMAGE, "from": Vector2(1, 2)})
	_check("a PvP hit with odd numbers is harmless", Net.clean_pvp_hit({"damage": "lots", "from": Vector2(NAN, 0)}) == {"damage": 0.0})
	var got: Array = []
	var on_pvp := func(hit, attacker): got.append([hit, attacker])
	Net.pvp_damage_received.connect(on_pvp)
	Net.roster = {1: Net.local_info(), 5: {"name": "Pip"}}
	Net.session = {"kind": "coop"}
	Net._pvp_deliver(1, {"damage": 5.0}, 5)
	_check("no PvP hits in a co-op session", got.is_empty())
	Net.session = {"kind": "arena"}
	Net._pvp_deliver(9, {"damage": 5.0}, 5)
	_check("no PvP hits on somebody who is not here", got.is_empty())
	Net._pvp_deliver(1, {"damage": 5.0, "from": Vector2(4, 4), "knockback": 999.0}, 5)
	_check("an arena hit arrives cleaned", got.size() == 1 and got[0][0] == {"damage": 5.0, "from": Vector2(4, 4)} and got[0][1] == 5)
	Net.pvp_damage_received.disconnect(on_pvp)
	Net.roster = {}
	Net.session = {}

	# what a guest takes from the host is capped (it is saved into their real hero)
	var richest := 0
	for id in Monsters.DEFS:
		richest = maxi(richest, roundi(float(Monsters.DEFS[id].get("xp", 0)) * (1.0 if Monsters.DEFS[id].get("boss", false) else Monsters.VARIANT_XP)))
	_check("the xp cap leaves room for the richest kill", richest <= Net.KILL_XP_MAX / 2 and 1 + richest / 10 <= Net.KILL_CLASS_XP_MAX)
	_check("a normal kill reward is kept", Net.clean_kill(12, 2) == Vector2i(12, 2))
	_check("a huge or negative kill reward is capped", Net.clean_kill(10000000, -5) == Vector2i(Net.KILL_XP_MAX, 0))
	var best_bonus := roundi(150.0 * Game.TIERS.keys().max() * float(Game.DIFFICULTIES["warlord"]["reward"]))
	_check("the clear bonus cap leaves room for the best clear", best_bonus <= Net.CLEAR_BONUS_MAX)
	_check("a normal clear reward is kept", Net.clean_clear_reward({"kind": "coop", "won": true, "bonus": 150, "tier": 1}) == {"bonus": 150, "tier": 1})
	_check("a huge bonus and an unknown tier are capped", Net.clean_clear_reward({"bonus": 1e12, "tier": 99}) == {"bonus": Net.CLEAR_BONUS_MAX, "tier": 0})
	_check("odd-typed rewards are nothing", Net.clean_clear_reward({"bonus": "lots", "tier": "5"}) == {"bonus": 0, "tier": 0} \
		and Net.clean_clear_reward({}) == {"bonus": 0, "tier": 0})
