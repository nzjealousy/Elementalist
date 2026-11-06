class_name Projectile
extends Area2D
## Elemental bolt. Hits the first enemy or wall it touches, unless its skill gives it a trait
## (see SkillDB): pierce passes through some enemies, splash bursts on impact and hurts the enemies
## around it, homing bends toward the nearest enemy ahead, lifesteal returns part of the damage as
## health. Traits are what make each element's bolt behave differently.

const SPLASH_SHARE := 0.6      # share of the bolt's damage the enemies around a burst take
const HOMING_RANGE := 90.0     # a homing bolt looks for enemies this close...
const HOMING_CONE := 0.35      # ...and in front of it (dot product of the directions)

var velocity := Vector2.ZERO
var hit: Dictionary = {}
var extra_hits: Array = []  # a fused bolt: further hits applied in order after `hit`
var life := 1.0
var texture_id := ""
var pierce := 0             # further enemies the bolt may pass through
var splash := 0.0           # burst radius on impact (0: none)
var homing := 0.0           # turn rate in radians per second (0: straight)
var lifesteal := 0.0        # share of damage dealt that comes back to the caster as health

var _sprite: Sprite2D
var _already_hit: Array = []  # enemies a piercing bolt has passed through


func setup(vel: Vector2, hit_data: Dictionary, lifetime: float, more_hits: Array = [], traits: Dictionary = {}) -> void:
	velocity = vel
	hit = hit_data
	extra_hits = more_hits
	life = lifetime
	pierce = int(traits.get("pierce", 0))
	splash = float(traits.get("splash", 0.0))
	homing = float(traits.get("homing", 0.0))
	lifesteal = float(traits.get("lifesteal", 0.0))
	var element := String(hit_data.get("element", ""))
	texture_id = "proj_" + (element if element != "" else "martial")


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4  # world + enemies
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 3.0
	shape.shape = circle
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = AssetDB.get_texture(texture_id)
	_sprite.offset = Vector2(-5.5, 0)  # the art's bright head sits 5.5 px in front of its centre (18 px wide)
	_sprite.rotation = velocity.angle()  # the art points right
	add_child(_sprite)
	SpriteAnim.attach(_sprite, texture_id, 14.0, self)
	z_index = 5
	body_entered.connect(_on_body_entered)
	SkillFx.trail(self, String(hit.get("element", "")))


func _physics_process(delta: float) -> void:
	if homing > 0.0:
		_steer(delta)
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()


## Bends the flight toward the nearest enemy that is close and roughly ahead.
func _steer(delta: float) -> void:
	var forward := velocity.normalized()
	var best: Node2D = null
	var best_distance := HOMING_RANGE
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or enemy in _already_hit:
			continue
		var to_enemy := enemy.global_position - global_position
		var distance := to_enemy.length()
		if distance < best_distance and forward.dot(to_enemy / maxf(distance, 0.001)) > HOMING_CONE:
			best = enemy
			best_distance = distance
	if best == null:
		return
	var wanted := (best.global_position - global_position).angle()
	var turn := clampf(angle_difference(velocity.angle(), wanted), -homing * delta, homing * delta)
	velocity = velocity.rotated(turn)
	if _sprite:
		_sprite.rotation = velocity.angle()


func _on_body_entered(body: Node) -> void:
	var element := String(hit.get("element", ""))
	SkillFx.impact(get_parent(), global_position, element)
	if body is Enemy:
		if body in _already_hit:
			return
		_already_hit.append(body)
		hit["from"] = global_position - velocity.normalized() * 4.0
		var before: float = body.hp
		body.take_hit(hit.duplicate())
		for extra in extra_hits:  # fusion: each element lands in turn, so their combos fire
			extra["from"] = hit["from"]
			body.take_hit(extra)
		if lifesteal > 0.0:
			_drain(maxf(before - body.hp, 0.0))
		if splash > 0.0:
			_burst(body)
		if pierce > 0:
			pierce -= 1
			return  # keeps flying
	else:
		HitFx.burst(get_parent(), global_position, Elements.color_of(element), 5, 35.0)
	queue_free()


## The caster gets a share of the damage dealt back as health.
func _drain(dealt: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("heal") and dealt > 0.0:
		player.heal(dealt * lifesteal)


## Impact burst: the enemies near the point of impact take a share of the damage.
func _burst(except: Node) -> void:
	var element := String(hit.get("element", ""))
	SkillFx.ring(get_parent(), global_position, splash, Elements.color_of(element), 0.28, 1.5)
	Sfx.play_at("explode", global_position, 300.0, -4.0)  # as an area landing (AoeEffect): its splash hits stay quiet
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy == except or enemy.global_position.distance_to(global_position) > splash:
			continue
		var h := hit.duplicate()
		h["damage"] = float(hit.get("damage", 0.0)) * SPLASH_SHARE
		h["from"] = global_position
		h["burst"] = true
		enemy.take_hit(h)
