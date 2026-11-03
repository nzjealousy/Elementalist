class_name Enemy
extends CharacterBody2D
## Chasing enemy. Holds health, an elemental aura (the last element that hit it) and
## timed status effects. Skills call take_hit() with a hit dictionary:
## {damage, element, apply: {kind, time, power}, from: Vector2, knockback: float}
##
## Combo rule: hitting an enemy whose aura is a *different* element triggers the
## combo for that pair (see Elements.COMBOS) and consumes the aura.

signal died(enemy: Enemy)

const AURA_TIME := 4.0
const VULN_MULT := 1.25
const SHATTER_MULT := 1.5  # physical hit on a rooted or stunned enemy
const CONTACT_MARGIN := 1.0  # px; bodies this close count as touching

@export var max_hp := 40.0
@export var speed := 30.0
@export var contact_damage := 8.0
@export var sprite_id := "enemy_slime"
@export var xp_reward := 12

var hp := 0.0
var aura := ""
var aura_time := 0.0
var aura_stacks := 0   # consecutive discrete hits of the aura's element (resonance)
var chain_count := 0   # consecutive physical hits (martial combo)
var chain_time := 0.0
var _text_offset := Vector2.ZERO
var effects: Dictionary = {}  # kind -> {"time": float, "power": float}

var _knock := Vector2.ZERO
var _flash := 0.0
var _contact_cd := 0.0
var _dot_accum := 0.0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	sprite.texture = AssetDB.get_texture(sprite_id)
	var bar := EnemyHealthBar.new()
	bar.enemy = self
	add_child(bar)


func take_hit(hit: Dictionary) -> void:
	if hp <= 0.0:
		return  # already dead (e.g. a fused bolt's later hits): never reward or react twice
	_text_offset = hit.get("text_offset", Vector2.ZERO)
	var dmg: float = hit.get("damage", 0.0)
	var element: String = hit.get("element", "")
	var text_color := Elements.color_of(element)
	var label := ""

	var juicy: bool = hit.get("juice", true)
	if effects.has("vuln"):
		dmg *= VULN_MULT
	if element == "" and is_rooted():
		dmg *= SHATTER_MULT
		label = "Shatter"
		text_color = Color("bfe3ff")

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
	_knock = (global_position - from).normalized() * push
	_flash = 0.12

	if juicy:
		HitFx.burst(get_parent(), global_position, text_color)
		if not combo.is_empty():
			Juice.shake(2.0, 0.2)
			Juice.hit_stop(0.07)
		elif element == "":
			Juice.shake(1.0, 0.12)
			Juice.hit_stop(0.04)
		else:
			Juice.shake(0.5, 0.08)

	_damage(dmg, text_color)
	if label != "" and hp > 0.0:
		FloatText.spawn(get_parent(), global_position + Vector2(0, -8) + _text_offset, label + "!", text_color)


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


func _damage(amount: float, color: Color) -> void:
	hp -= amount
	FloatText.spawn(get_parent(), global_position + _text_offset, str(int(round(amount))), color)
	if hp <= 0.0:
		HitFx.burst(get_parent(), global_position, Color("9be88a"), 14, 80.0)
		Juice.hit_stop(0.05)
		Game.on_enemy_killed(self)
		died.emit(self)
		queue_free()


func _physics_process(delta: float) -> void:
	_tick_status(delta)
	if hp <= 0.0:
		return

	var target := get_tree().get_first_node_in_group("player") as Node2D
	var move := Vector2.ZERO
	if target and not is_rooted():
		var mult := 1.0
		if effects.has("slow"):
			mult = 1.0 - float(effects["slow"]["power"])
		move = (target.global_position - global_position).normalized() * speed * mult
	velocity = move + _knock
	_knock = _knock.move_toward(Vector2.ZERO, 300.0 * delta)
	move_and_slide()

	_contact_cd = maxf(0.0, _contact_cd - delta)
	if target and not is_stunned() and _contact_cd == 0.0:
		if touches(target) and target.has_method("take_damage"):
			# Only start the cooldown if the hit connected; i-frames shouldn't waste it.
			if target.take_damage(contact_damage, global_position):
				_contact_cd = 0.9

	_update_tint(delta)


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
	elif aura != "":
		sprite.modulate = Color.WHITE.lerp(Elements.color_of(aura), 0.55)
	else:
		sprite.modulate = Color.WHITE
