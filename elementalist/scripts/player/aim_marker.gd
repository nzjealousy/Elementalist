class_name AimMarker
extends Node2D
## Replaces the OS cursor with a crosshair and previews where the selected element's
## area skill (Q) will land, dimmed while it can't be cast.

var player: Node2D


func _ready() -> void:
	top_level = true  # draw in world coordinates, independent of the player's transform
	z_index = 90
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null or player.caster == null:
		return
	var caster: SkillCaster = player.caster
	var color := Elements.color_of(caster.selected_element()) if not caster.elements.is_empty() else Color.WHITE

	# Q preview: eight faint dots marking the radius, only while Q is castable.
	var area_id := caster.skill_for("area")
	if caster.can_cast(area_id):
		var target := caster.area_target(area_id)
		var radius := caster.area_radius(area_id)
		for i in 8:
			draw_circle(target + Vector2.from_angle(TAU * i / 8.0) * radius, 0.8, Color(color, 0.4))

	var mouse := get_global_mouse_position()
	var tick := Color(1, 1, 1, 0.95)
	draw_line(mouse + Vector2(-4, 0), mouse + Vector2(-2, 0), tick, 1.0)
	draw_line(mouse + Vector2(2, 0), mouse + Vector2(4, 0), tick, 1.0)
	draw_line(mouse + Vector2(0, -4), mouse + Vector2(0, -2), tick, 1.0)
	draw_line(mouse + Vector2(0, 2), mouse + Vector2(0, 4), tick, 1.0)
	draw_circle(mouse, 0.6, color)
