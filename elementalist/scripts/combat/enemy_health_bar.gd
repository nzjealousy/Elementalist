class_name EnemyHealthBar
extends Node2D
## Always-visible health bar above an enemy. Lives in its own node so it can draw on top
## of the player and other sprites regardless of the enemy's own draw order.

const SIZE := Vector2(16, 3)

var enemy: Enemy


func _ready() -> void:
	z_index = 60


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if enemy == null:
		return
	var frac := clampf(enemy.hp / enemy.max_hp, 0.0, 1.0)
	var pos := Vector2(-SIZE.x * 0.5, -maxf(enemy.hit_rect().size.y, enemy.picture_height()) * 0.5 - SIZE.y - 3.0)
	draw_rect(Rect2(pos - Vector2.ONE, SIZE + Vector2(2, 2)), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(pos, Vector2(SIZE.x * frac, SIZE.y)), Color("e24b3b").lerp(Color("6bd66b"), frac))
	if enemy.aura != "":
		draw_circle(pos + Vector2(-5, 1.5), 2.0, Elements.color_of(enemy.aura))
