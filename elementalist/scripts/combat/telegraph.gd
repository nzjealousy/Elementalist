class_name Telegraph
extends Node2D
## A warning circle on the ground that fills up, then calls `on_done` (a boss slam lands). The
## circle stays where it was placed, so the player can step out of it.

var radius := 40.0
var time := 0.8
var on_done: Callable

var _age := 0.0


static func start(parent: Node, pos: Vector2, r: float, seconds: float, done: Callable) -> Telegraph:
	var node := Telegraph.new()
	node.radius = r
	node.time = seconds
	node.on_done = done
	parent.add_child(node)
	node.global_position = pos
	return node


func _ready() -> void:
	z_index = -4


func _physics_process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= time:
		if on_done.is_valid():
			on_done.call()
		queue_free()


func _draw() -> void:
	var t := clampf(_age / time, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.2, 0.15, 0.12))
	draw_circle(Vector2.ZERO, radius * t, Color(1.0, 0.25, 0.15, 0.2 + 0.2 * t))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(1.0, 0.35, 0.25, 0.9), 1.5)
