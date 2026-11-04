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
	sprite.offset = Vector2(-3.5, 0)  # the art's bright head sits in front of its centre
	sprite.rotation = velocity.angle()  # the art points right
	add_child(sprite)
	SpriteAnim.attach(sprite, texture_id, 14.0, self)
	z_index = 5
	body_entered.connect(_on_body_entered)
	SkillFx.trail(self, String(hit.get("element", "")))


func _physics_process(delta: float) -> void:
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	SkillFx.impact(get_parent(), global_position, String(hit.get("element", "")))
	if body is Enemy:
		hit["from"] = global_position - velocity.normalized() * 4.0
		body.take_hit(hit)
		for extra in extra_hits:  # fusion: each element lands in turn, so their combos fire
			extra["from"] = hit["from"]
			body.take_hit(extra)
	else:
		HitFx.burst(get_parent(), global_position, Elements.color_of(String(hit.get("element", ""))), 5, 35.0)
	queue_free()
