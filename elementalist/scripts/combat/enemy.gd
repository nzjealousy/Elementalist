class_name Enemy
extends CharacterBody2D
## A monster. Holds health, an elemental aura (the last element that hit it) and timed status
## effects. Which monster it is comes from Monsters.DEFS through configure(); with no
## configuration it is a plain slime. Behaviours: chase, flutter, ranged and boss (see Monsters). Skills call take_hit() with a hit dictionary:
## {damage, element, apply: {kind, time, power}, from: Vector2, knockback: float}
##
## Combo rule: hitting an enemy whose aura is a *different* element triggers the
## combo for that pair (see Elements.COMBOS) and consumes the aura.

signal died(enemy: Enemy)

const AURA_TIME := 4.0
const VULN_MULT := 1.25
const SHATTER_MULT := 1.5  # physical hit on a rooted or stunned enemy
const ENRAGE_AT := 0.3   # a boss below this share of its health enrages
const CONTACT_MARGIN := 1.0  # px; bodies this close count as touching

@export var max_hp := 40.0
@export var speed := 30.0
@export var contact_damage := 8.0
@export var sprite_id := "enemy_slime"
@export var xp_reward := 12

var monster_id := "slime"
var level := 1               # the dungeon floor it came from: dash and dodge sharpen with it
var attack_type := "melee"   # "melee", "ranged" or "both" (see Monsters)
var dash: Dictionary = {}    # {range, cooldown, windup, time, speed, damage_mult}
var dodge_ability: Dictionary = {}  # {chance, cooldown}
var display_name := "Slime"
var behavior := "chase"
var variant := ""            # elemental variant: "" or a main element (see Monsters)
var boss := false
var rare_gem := ""    # a final boss of the second dungeon may drop this rare element's gem
var mini := false     # a mini boss: a boss-style fight at the end of every third floor
var enraged := false
var anim: SpriteAnim
var net_id := 0              # multiplayer: the host's number for this monster
var ghost := false           # multiplayer: a copy of the host's monster (or an opponent in the arena): no thinking, hits go to the host
var pvp_peer := 0            # arena: the player this ghost stands for
var net_pos := Vector2.ZERO  # where the host says it is
var net_aim := Vector2.RIGHT
var net_moving := false
var net_dodging := false
var knock_resist := 0.0      # share of knockback ignored
var attack_range := 0.0      # ranged: shoots from this far
var keep_distance := 0.0     # ranged: tries to stay about this far away
var shot: Dictionary = {}    # ranged: {damage, speed, cooldown}
var slam: Dictionary = {}    # boss: {radius, damage, cooldown, telegraph}
var summon: Dictionary = {}  # boss: {id, count, stages}

var hp := 0.0
var aura := ""
var aura_time := 0.0
var last_element := ""  # the element that most recently hit it (decides essence drops)
var aura_stacks := 0   # consecutive discrete hits of the aura's element (resonance)
var chain_count := 0   # consecutive physical hits (martial combo)
var chain_time := 0.0
var _text_offset := Vector2.ZERO
var effects: Dictionary = {}  # kind -> {"time": float, "power": float}

var _knock := Vector2.ZERO
var _flash := 0.0
var _contact_cd := 0.0
var _dot_accum := 0.0
var _fx_timer := 0.0
var _age := 0.0
var _phase := 0.0
var _attack_cd := 1.0
var _dash_state := ""   # "", "windup" (warning flash) or "dash" (the lunge)
var _dash_left := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector2.ZERO
var _dodge_cd := 0.0
var _summon_stage := 0
var _base_tint := Color.WHITE
var _telegraph: Telegraph

@onready var sprite: Sprite2D = $Sprite2D


## Turns this enemy into monster `id` (call before adding it to the tree). `hp_scale` and
## `damage_scale` are the dungeon floor's multipliers; a `variant_element` makes it an
## elemental variant: tougher, tinted, resistant to its element and weak to another.
func configure(id: String, variant_element: String = "", hp_scale: float = 1.0, damage_scale: float = 1.0, monster_level: int = 1) -> void:
	var def: Dictionary = Monsters.DEFS[id]
	monster_id = id
	display_name = String(def["name"])
	sprite_id = String(def["sprite"])
	behavior = String(def["behavior"])
	attack_type = String(def.get("attack", "melee"))
	level = monster_level
	boss = def.get("boss", false)
	mini = def.get("mini", false)
	rare_gem = String(def.get("rare_gem", ""))
	knock_resist = float(def.get("knock_resist", 0.0))
	attack_range = float(def.get("attack_range", 0.0))
	keep_distance = float(def.get("keep_distance", 0.0))
	damage_scale *= Monsters.HARDNESS
	max_hp = float(def["hp"]) * hp_scale
	speed = float(def["speed"])
	contact_damage = float(def["contact"]) * damage_scale
	xp_reward = int(def["xp"])
	var sharpen := float(monster_level - 1)  # each level: +4% speed, dash and dodge get better
	speed *= 1.0 + 0.04 * sharpen
	dash = def.get("dash", {}).duplicate()
	if not dash.is_empty():
		dash["cooldown"] = maxf(1.2, float(dash["cooldown"]) * (1.0 - 0.12 * sharpen))
		dash["windup"] = maxf(0.2, float(dash["windup"]) * (1.0 - 0.1 * sharpen))
		dash["speed"] = float(dash["speed"]) * (1.0 + 0.12 * sharpen)
	dodge_ability = def.get("dodge", {}).duplicate()
	if not dodge_ability.is_empty():
		dodge_ability["chance"] = minf(0.7, float(dodge_ability["chance"]) + 0.08 * sharpen)
		dodge_ability["cooldown"] = maxf(0.8, float(dodge_ability["cooldown"]) * (1.0 - 0.1 * sharpen))
	if attack_type == "ranged":
		contact_damage = 0.0  # it never touches you: it shoots
	shot = def.get("shot", {}).duplicate()
	if not shot.is_empty():
		shot["damage"] = float(shot["damage"]) * damage_scale
	slam = def.get("slam", {}).duplicate()
	if not slam.is_empty():
		slam["damage"] = float(slam["damage"]) * damage_scale
	summon = def.get("summon", {}).duplicate()
	if variant_element != "" and not boss:
		variant = variant_element
		max_hp *= Monsters.VARIANT_HP
		contact_damage *= Monsters.VARIANT_DAMAGE
		xp_reward = int(round(xp_reward * Monsters.VARIANT_XP))
		display_name = "%s %s" % [variant_element.capitalize(), display_name]


func _ready() -> void:
	hp = max_hp
	_phase = randf() * TAU
	_attack_cd = randf_range(0.6, 1.6)
	add_to_group("enemies")
	sprite.texture = AssetDB.get_texture(sprite_id)
	anim = SpriteAnim.attach(sprite, sprite_id, 10.0 if behavior == "flutter" else (7.0 if behavior == "ranged" else 5.0), self)
	if variant != "":
		_base_tint = Color.WHITE.lerp(Elements.color_of(variant), 0.5)
	var circle := CircleShape2D.new()  # sized to the sprite (the scene's shape is shared, so not edited)
	circle.radius = clampf(minf(sprite.texture.get_size().x, sprite.texture.get_size().y) * 0.45, 4.0, 16.0)
	$CollisionShape2D.shape = circle
	var bar := EnemyHealthBar.new()
	bar.enemy = self
	add_child(bar)


func take_hit(hit: Dictionary) -> void:
	if ghost:
		_ghost_hit(hit)
		return
	if hp <= 0.0:
		return  # already dead (e.g. a fused bolt's later hits): never reward or react twice
	_text_offset = hit.get("text_offset", Vector2.ZERO)
	if _try_dodge(hit):
		return
	var dmg: float = hit.get("damage", 0.0)
	var element: String = hit.get("element", "")
	var text_color := Elements.color_of(element)
	var label := ""
	if element != "":
		last_element = element

	var juicy: bool = hit.get("juice", true)
	if effects.has("vuln"):
		dmg *= VULN_MULT
	if variant != "" and element != "":
		if element == variant:
			dmg *= Monsters.RESIST_MULT
			label = "Resist"
			text_color = Color(0.75, 0.75, 0.8)
		elif Monsters.WEAK_TO.get(variant, "") == element:
			dmg *= Monsters.WEAK_MULT
			label = "Weak"
	if element == "" and is_rooted():
		dmg *= SHATTER_MULT
		label = "Shatter"
		text_color = Color("bfe3ff")
	var crit := false
	if juicy:  # lingering ticks never crit
		var chance := float(Game.character.derived()["crit_chance"])  # 0 at Luck 5, so tests stay deterministic
		if chance > 0.0 and Game.combat_rng.randf() < chance:
			crit = true
			dmg *= float(Game.character.derived()["crit_mult"])

	# Which combo (if any) this hit completes:
	#   different element on an aura -> the pair combo     (consumes the aura)
	#   same element, Nth discrete hit -> that resonance   (consumes the aura)
	#   Nth physical hit in a row      -> the martial Rend (aura untouched)
	var combo: Dictionary = {}
	var consumes_aura := false
	if element == "":
		if juicy:
			combo = _martial_chain()
	elif aura != "" and aura != element:
		combo = Elements.resolve(aura, element)
		consumes_aura = not combo.is_empty()
		if combo.is_empty():
			_set_aura(element)
	elif aura == element:
		aura_time = AURA_TIME
		if juicy:
			aura_stacks += 1
			if aura_stacks >= Elements.RESONANCE_HITS and Elements.RESONANCE.has(element):
				combo = Elements.RESONANCE[element]
				consumes_aura = true
	else:
		_set_aura(element)
	if not combo.is_empty():
		dmg *= float(combo["mult"])
		_add_effect(combo["effect"], combo["time"], combo["power"])
		label = combo["name"]
		text_color = combo["color"]
		if consumes_aura:
			aura = ""
			aura_time = 0.0
			aura_stacks = 0

	var apply: Dictionary = hit.get("apply", {})
	if not apply.is_empty():
		_add_effect(apply["kind"], apply["time"], apply.get("power", 1.0))

	var from: Vector2 = hit.get("from", global_position + Vector2.UP)
	var push: float = hit.get("knockback", 50.0)
	_knock = (global_position - from).normalized() * push * (1.0 - knock_resist)
	_flash = 0.12

	if juicy:
		HitFx.burst(get_parent(), global_position, text_color)
		Sfx.play_at("hit", global_position, 240.0, -2.0)
		if not combo.is_empty():
			Sfx.play_at("combo", global_position, 260.0, -3.0)
		if not combo.is_empty():
			Juice.shake(2.0, 0.2)
			Juice.hit_stop(0.07)
		elif element == "":
			Juice.shake(1.0, 0.12)
			Juice.hit_stop(0.04)
		else:
			Juice.shake(0.5, 0.08)

	_damage(dmg, text_color, crit)
	if label != "" and hp > 0.0:
		FloatText.spawn(get_parent(), global_position + Vector2(0, -8) + _text_offset, label + "!", text_color)


## A hit on a ghost: sent to the host (or, in the arena, to the player it stands for); a flash and a spark right here.
func _ghost_hit(hit: Dictionary) -> void:
	if pvp_peer != 0:
		Net.send_pvp_hit(pvp_peer, hit)
	else:
		Net.send_hit(net_id, hit)
	_flash = 0.12
	HitFx.burst(get_parent(), global_position, Elements.color_of(String(hit.get("element", ""))))
	Sfx.play_at("hit", global_position, 240.0, -2.0)


## A ghost only follows the host's numbers.
func _ghost_tick(delta: float) -> void:
	if global_position.distance_to(net_pos) > 90.0:
		global_position = net_pos
	else:
		global_position = global_position.lerp(net_pos, 1.0 - exp(-18.0 * delta))
	if pvp_peer != 0 and has_meta("prefix"):
		var look_dir := net_aim - global_position
		if IsoView.active != null:
			look_dir = IsoView.screen_dir(look_dir)
		var facing := "side"
		if absf(look_dir.y) > absf(look_dir.x) * 0.6:
			facing = "up" if look_dir.y < 0.0 else "down"
		anim.set_art("%s:%s" % [get_meta("prefix"), facing])
		anim.playing = net_moving or net_dodging
		sprite.flip_h = facing == "side" and look_dir.x < 0.0
	else:
		var target := get_tree().get_first_node_in_group("player") as Node2D
		if target:
			var toward := target.global_position - global_position
			if IsoView.active != null:
				toward = IsoView.screen_dir(toward)
			if absf(toward.x) > 2.0:
				sprite.flip_h = toward.x < 0.0
		_status_fx(delta)
	_update_tint(delta)


## The player a monster goes for: the nearest of the local hero and the other players.
func _nearest_target() -> Node2D:
	var best := get_tree().get_first_node_in_group("player") as Node2D
	var best_distance := best.global_position.distance_squared_to(global_position) if best else INF
	for node in get_tree().get_nodes_in_group("net_players"):
		var other := node as Node2D
		if other == null or other.is_queued_for_deletion() or (other.has_method("is_down") and other.is_down()):
			continue
		var distance := other.global_position.distance_squared_to(global_position)
		if distance < best_distance:
			best = other
			best_distance = distance
	return best


## A dodging monster may sidestep a discrete hit (not burn ticks) and take nothing.
func _try_dodge(hit: Dictionary) -> bool:
	if dodge_ability.is_empty() or _dodge_cd > 0.0 or is_rooted() or not hit.get("juice", true):
		return false
	if Game.combat_rng.randf() >= float(dodge_ability["chance"]):
		return false
	_dodge_cd = float(dodge_ability["cooldown"])
	var from: Vector2 = hit.get("from", global_position + Vector2.UP)
	var side := (global_position - from).normalized().orthogonal() * (1.0 if Game.combat_rng.randf() < 0.5 else -1.0)
	_knock += side * 160.0
	FloatText.spawn(get_parent(), global_position + Vector2(0, -8), "Dodged!", Color("c0c0d0"))
	SkillFx.burst(get_parent(), global_position, "air", 0.4)
	return true


## The enemy's body rectangle in world space (its sprite's footprint).
func hit_rect() -> Rect2:
	var size := sprite.texture.get_size()
	return Rect2(global_position - size * 0.5, size)


## True when this enemy's body overlaps the target's hurtbox on any side. The target needs
## a hurtbox() -> Rect2. Grown by CONTACT_MARGIN so visually touching sprites count.
func touches(target: Node2D) -> bool:
	return target.has_method("hurtbox") and hit_rect().grow(CONTACT_MARGIN).intersects(target.hurtbox())


func _set_aura(element: String) -> void:
	aura = element
	aura_time = AURA_TIME
	aura_stacks = 1


## Counts a physical hit; returns the martial combo when the chain completes.
func _martial_chain() -> Dictionary:
	chain_count = chain_count + 1 if chain_time > 0.0 else 1
	chain_time = Elements.MARTIAL_CHAIN_TIME
	if chain_count >= Elements.MARTIAL_CHAIN_HITS:
		chain_count = 0
		chain_time = 0.0
		return Elements.MARTIAL_COMBO
	return {}


## Damage this enemy deals to the player after debuffs (Weaken).
func damage_out(base: float) -> float:
	return base * (1.0 - float(effects["weaken"]["power"])) if effects.has("weaken") else base


func is_stunned() -> bool:
	return effects.has("stun")


func is_rooted() -> bool:
	return effects.has("root") or effects.has("stun")


func _add_effect(kind: String, time: float, power: float) -> void:
	var current: Dictionary = effects.get(kind, {})
	effects[kind] = {
		"time": maxf(time, current.get("time", 0.0)),
		"power": maxf(power, current.get("power", 0.0)),
	}


func _damage(amount: float, color: Color, crit: bool = false) -> void:
	hp -= amount
	if crit:
		FloatText.spawn(get_parent(), global_position + _text_offset, "%d!" % int(round(amount)), color.lightened(0.4), 12)
	else:
		FloatText.spawn(get_parent(), global_position + _text_offset, str(int(round(amount))), color)
	if hp <= 0.0:
		HitFx.burst(get_parent(), global_position, Color("9be88a"), 14, 80.0)
		Juice.hit_stop(0.05)
		Sfx.play_at("enemy_die", global_position, 260.0)
		Game.on_enemy_killed(self)
		died.emit(self)
		queue_free()


func _physics_process(delta: float) -> void:
	if ghost:
		_ghost_tick(delta)
		return
	_tick_status(delta)
	if hp <= 0.0:
		return
	_status_fx(delta)

	_age += delta
	var target := _nearest_target()
	velocity = _desired_velocity(target) + _knock
	if target:
		var toward := target.global_position - global_position
		if IsoView.active != null:
			toward = IsoView.screen_dir(toward)  # which way the player is across the screen
		if absf(toward.x) > 2.0:
			sprite.flip_h = toward.x < 0.0  # art faces right
	_knock = _knock.move_toward(Vector2.ZERO, 300.0 * delta)
	move_and_slide()

	_contact_cd = maxf(0.0, _contact_cd - delta)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	if attack_type != "ranged" and target and not is_stunned() and _contact_cd == 0.0:
		if touches(target) and target.has_method("take_damage"):
			# Only start the cooldown if the hit connected; i-frames shouldn't waste it.
			var lunge := float(dash["damage_mult"]) if _dash_state == "dash" else 1.0
			if target.take_damage(damage_out(contact_damage * lunge), global_position):
				_contact_cd = 0.9

	_attack(delta, target)
	_update_tint(delta)


## Where this monster wants to go this frame, by behaviour (zero while rooted or stunned).
func _desired_velocity(target: Node2D) -> Vector2:
	if target == null or is_rooted() or _telegraph != null:
		return Vector2.ZERO
	if _dash_state == "windup":
		return Vector2.ZERO  # braced, the warning flash
	if _dash_state == "dash":
		return _dash_dir * float(dash["speed"])
	var mult := 1.0
	if effects.has("slow"):
		mult = 1.0 - float(effects["slow"]["power"])
	var to := target.global_position - global_position
	var distance := to.length()
	var dir := to / maxf(distance, 0.001)
	match behavior:
		"flutter":  # weave across the line of approach
			return (dir * speed + dir.orthogonal() * sin(_age * 6.0 + _phase) * speed * 0.9) * mult
		"ranged":  # hold the preferred distance, drift sideways when there
			if distance > keep_distance + 12.0:
				return dir * speed * mult
			if distance < keep_distance - 14.0:
				return -dir * speed * mult
			return dir.orthogonal() * speed * 0.5 * signf(sin(_age * 0.7 + _phase)) * mult
	return dir * speed * mult


## Ranged shots, boss slams and boss summons.
func _attack(delta: float, target: Node2D) -> void:
	if boss:
		_boss_summons()
		_check_enrage()
	if target == null or is_stunned() or is_rooted():
		_dash_state = ""
		if target == null or is_stunned():
			return
	_tick_dash(delta, target)
	_attack_cd -= delta
	if _attack_cd > 0.0:
		return
	var distance := target.global_position.distance_to(global_position)
	var slam_ready := behavior == "boss" and not slam.is_empty() and _telegraph == null and distance <= float(slam["radius"]) * 1.7
	if slam_ready:  # up close a boss slams; farther away it shoots (when it has a shot)
		_attack_cd = float(slam["cooldown"]) * _enrage_cooldown()
		_telegraph = Telegraph.start(get_parent(), global_position, float(slam["radius"]), float(slam["telegraph"]), _land_slam)
		Sfx.play_at("telegraph", global_position, 300.0, -4.0)
	elif not shot.is_empty() and attack_type in ["ranged", "both"] and distance <= attack_range:
		_attack_cd = float(shot["cooldown"]) * _enrage_cooldown()
		EnemyProjectile.spawn(get_parent(), global_position, target.global_position - global_position,
			float(shot["speed"]), damage_out(float(shot["damage"])), variant)


## Imp / duelist dash: warn, then lunge at where you are.
func _tick_dash(delta: float, target: Node2D) -> void:
	if dash.is_empty():
		return
	_dash_cd = maxf(0.0, _dash_cd - delta)
	match _dash_state:
		"":
			var distance := target.global_position.distance_to(global_position)
			if _dash_cd <= 0.0 and not is_rooted() and distance <= float(dash["range"]) and distance > 22.0:
				_dash_state = "windup"
				_dash_left = float(dash["windup"])
				FloatText.spawn(get_parent(), global_position + Vector2(0, -10), "!", Color("ff6a4a"), 12)
		"windup":
			_dash_left -= delta
			if _dash_left <= 0.0:
				_dash_state = "dash"
				_dash_left = float(dash["time"])
				_dash_dir = (target.global_position - global_position).normalized()
		"dash":
			_dash_left -= delta
			SkillFx.burst(get_parent(), global_position, "", 0.15)
			if _dash_left <= 0.0:
				_dash_state = ""
				_dash_cd = float(dash["cooldown"])


## The slam hits whoever is still standing in the circle.
func _land_slam() -> void:
	var circle_centre := _telegraph.global_position if is_instance_valid(_telegraph) else global_position
	_telegraph = null
	SkillFx.ring(get_parent(), circle_centre, float(slam["radius"]), Color("ff6a4a"), 0.4, 2.0)
	HitFx.burst(get_parent(), circle_centre, Color("ff6a4a"), 16, 90.0)
	Juice.shake(3.0, 0.3)
	Sfx.play_at("slam", circle_centre, 340.0)
	var targets: Array = get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("net_players")
	for node in targets:
		var target := node as Node2D
		if target and target.global_position.distance_to(circle_centre) <= float(slam["radius"]) and target.has_method("take_damage"):
			target.take_damage(damage_out(float(slam["damage"])), circle_centre)


## Below ENRAGE_AT of its health a boss (not a mini boss) moves faster and attacks more often.
func _check_enrage() -> void:
	if not enraged and not mini and hp / max_hp <= ENRAGE_AT:
		enraged = true
		speed *= 1.25
		FloatText.spawn(get_parent(), global_position + Vector2(0, -16), "Enraged!", Color("ff5a4a"), 11)
		Sfx.play("enrage")
		Sfx.duck(1.0)
		Juice.shake(3.0, 0.4)


func _enrage_cooldown() -> float:
	return 0.65 if enraged else 1.0


## At each health fraction in summon.stages the boss calls minions around itself (once each).
func _boss_summons() -> void:
	var stages: Array = summon.get("stages", [])
	if _summon_stage < stages.size() and hp / max_hp <= float(stages[_summon_stage]):
		_summon_stage += 1
		_spawn_minions.call_deferred()


func _spawn_minions() -> void:
	if not is_inside_tree() or hp <= 0.0:
		return
	var count := int(summon["count"])
	for i in count:
		var angle := TAU * float(i) / float(count)
		Monsters.spawn(get_parent(), String(summon["id"]), global_position + Vector2.from_angle(angle) * 26.0)
	FloatText.spawn(get_parent(), global_position + Vector2(0, -14), "Summons!", Color("ff9a6a"), 10)


func _exit_tree() -> void:
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()


## Little puffs while a status is on: embers when burning, drips when slowed, and so on.
func _status_fx(delta: float) -> void:
	_fx_timer -= delta
	if _fx_timer > 0.0 or effects.is_empty():
		return
	_fx_timer = 0.3
	var looks := {"dot": "fire", "slow": "water", "root": "earth", "stun": "mineral", "vuln": "mineral", "weaken": ""}
	for kind in effects:
		if looks.has(kind):
			var element: String = looks[kind]
			SkillFx.burst(get_parent(), global_position + Vector2(0, -3), element, 0.25)
			return


func _tick_status(delta: float) -> void:
	chain_time -= delta
	aura_time -= delta
	if aura_time <= 0.0:
		aura = ""
		aura_stacks = 0
	for kind in effects.keys():
		var e: Dictionary = effects[kind]
		e["time"] -= delta
		if kind == "dot":
			_dot_accum += float(e["power"]) * delta
			if _dot_accum >= 1.0:
				var whole := floorf(_dot_accum)
				_dot_accum -= whole
				_damage(whole, Elements.color_of("fire"))
				if hp <= 0.0:
					return
		if e["time"] <= 0.0:
			effects.erase(kind)


func _update_tint(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	if _flash > 0.0:
		sprite.modulate = Color(2.5, 2.5, 2.5)
	elif _dash_state == "windup":
		sprite.modulate = Color(1.8, 0.45, 0.4)
	elif aura != "":
		sprite.modulate = _base_tint.lerp(Elements.color_of(aura), 0.55)
	else:
		sprite.modulate = _base_tint
