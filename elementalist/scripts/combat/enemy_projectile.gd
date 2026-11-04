class_name EnemyProjectile
extends Area2D
## A bolt or arrow fired by an enemy. Hurts the player on touch (passing through them while they
## are invulnerable, e.g. mid-dodge) and vanishes on walls or after its lifetime.

var velocity := Vector2.ZERO
var damage := 6.0
var life := 3.0
var element := ""
var color := Color("ff7a7a")


static func spawn(parent: Node, pos: Vector2, dir: Vector2, speed: float, dmg: float, shot_element: String = "") -> EnemyProjectile:
	var shot := EnemyProjectile.new()
	shot.velocity = dir.normalized() * speed
	shot.damage = dmg
	shot.element = shot_element
	if shot_element != "":
		shot.color = Elements.color_of(shot_element)
	parent.add_child(shot)
	shot.global_position = pos
	return shot


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1  # walls and the player
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 3.0
	shape.shape = circle
	add_child(shape)
	var sprite := Sprite2D.new()
	sprite.texture = AssetDB.get_texture("proj_enemy")
	sprite.modulate = color
	add_child(sprite)
	SpriteAnim.attach(sprite, "proj_enemy", 10.0, self)
	z_index = 5
	body_entered.connect(_on_body_entered)
	SkillFx.trail(self, element)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		if body.take_damage(damage, global_position - velocity):
			SkillFx.impact(get_parent(), global_position, element)
			queue_free()
	else:
		queue_free()  # a wall
