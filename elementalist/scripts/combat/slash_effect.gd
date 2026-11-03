class_name SlashEffect
extends Node2D
## Short-lived arc drawn for the physical attack. Add as a child of the attacker.

const LIFETIME := 0.14

var angle := 0.0
var radius := 24.0
var arc := deg_to_rad(110.0)
var color := Color.WHITE  # the imbued element's colour, or white for a plain slash
var lifetime := LIFETIME  # a spin lasts longer than a slash

var _age := 0.0


func setup(dir_angle: float, r: float, arc_degrees: float, slash_color: Color = Color.WHITE, duration: float = LIFETIME) -> void:
	angle = dir_angle
	radius = r
	arc = deg_to_rad(arc_degrees)
	color = slash_color
	lifetime = duration


func _ready() -> void:
	z_index = 20


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / lifetime, 0.0, 1.0)
	var sweep := angle - arc * 0.5 + arc * t
	draw_arc(Vector2.ZERO, radius * (0.6 + 0.4 * t), sweep - arc * 0.35, sweep + arc * 0.1, 10, Color(color, 1.0 - t), 2.0)
