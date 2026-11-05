class_name HitFx
extends RefCounted
## One-shot particle bursts for impacts.


static func burst(parent: Node, pos: Vector2, color: Color, amount: int = 8, speed: float = 55.0, priority: bool = false) -> void:
	if parent == null or not SkillFx.admit(priority):  # the shared budget (SkillFx.MAX_LIVE)
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.3
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.z_index = 50
	SkillFx.launch(parent, p, pos)
