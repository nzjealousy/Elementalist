class_name AoeEffect
extends Node2D
## Circular area hit. duration 0 = single instant hit; otherwise re-hits every `tick`
## seconds while it lingers (e.g. Rain Pool).

var hit: Dictionary = {}
var radius := 30.0
var duration := 0.0
var tick := 0.5
var color := Color.WHITE

var _age := 0.0
var _next_tick := 0.0


func setup(hit_data: Dictionary, r: float, dur: float, tick_time: float) -> void:
	hit = hit_data
	radius = r
	duration = dur
	tick = tick_time
	color = Elements.color_of(String(hit_data.get("element", "")))


func _ready() -> void:
	z_index = -5
	SkillFx.area_burst(self, String(hit.get("element", "")), radius, duration)
	Sfx.play_at("explode", global_position, 300.0, -4.0)  # the landing; its hits stay quiet (see _apply)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= _next_tick:
		_next_tick += tick if duration > 0.0 else 9999.0
		_apply()
	if _age >= maxf(duration, 0.35):
		queue_free()
	queue_redraw()


func _apply() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy and enemy.global_position.distance_to(global_position) <= radius:
			var h := hit.duplicate()
			h["from"] = global_position
			h["juice"] = duration <= 0.0  # lingering pools tick quietly
			h["burst"] = true  # the explode above is the sound: no "hit" per enemy on top of it
			enemy.take_hit(h)


func _draw() -> void:
	var life := maxf(duration, 0.35)
	var fade := clampf(1.0 - _age / life, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius, Color(color, 0.1 * fade))   # a faint pool: the rune circle (SkillFx) is the picture
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(color, 0.8 * fade), 1.0)
