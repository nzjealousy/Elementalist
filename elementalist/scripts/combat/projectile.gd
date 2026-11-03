class_name Projectile
extends Area2D
## Straight-line elemental bolt. Hits the first enemy or wall it touches.

var velocity := Vector2.ZERO
var hit: Dictionary = {}
var extra_hits: Array = []  # a fused bolt: further hits applied in order after `hit`
var life := 1.0
var texture_id := ""


func setup(vel: Vector2, hit_data: Dictionary, lifetime: float, more_hits: Array = []) -> void:
	velocity = vel
	hit = hit_data
	extra_hits = more_hits
	life = lifetime
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
	var sprite := Sprite2D.new()
	sprite.texture = AssetDB.get_texture(texture_id)
	add_child(sprite)
	z_index = 5
	body_entered.connect(_on_body_entered)
	_add_trail()


func _add_trail() -> void:
	var color := Elements.color_of(String(hit.get("element", "")))
	var trail := CPUParticles2D.new()
	trail.local_coords = false
	trail.amount = 16
	trail.lifetime = 0.25
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 8.0
	trail.spread = 180.0
	trail.scale_amount_min = 1.0
	trail.scale_amount_max = 1.5
	trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 1.5
	trail.color = color
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	trail.color_ramp = fade
	add_child(trail)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body is Enemy:
		hit["from"] = global_position - velocity.normalized() * 4.0
		body.take_hit(hit)
		for extra in extra_hits:  # fusion: each element lands in turn, so their combos fire
			extra["from"] = hit["from"]
			body.take_hit(extra)
	else:
		HitFx.burst(get_parent(), global_position, Elements.color_of(String(hit.get("element", ""))), 5, 35.0)
	queue_free()
