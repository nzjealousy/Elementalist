class_name MeleeRing
extends Node2D
## Shows how far a slash reaches: a faint ring at the reach and a wedge in the aim direction that
## covers the swing arc. It glows when an enemy is inside the swing, dims when there is not enough
## stamina to slash, and becomes a full circle while dodging (the spin). Child of the Player; the
## "melee_indicator" setting turns it off.

const WEDGE_STEPS := 14

var player: Node2D

var _pulse := 0.0


func _ready() -> void:
	show_behind_parent = true  # under the hero's sprite
	z_index = 1


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	if player == null or not bool(Settings.get_value("melee_indicator")):
		return
	var reach: float = player.melee_reach()
	var m: Dictionary = SkillDB.MELEE
	var spin: bool = player.is_dodging()
	var cost: float = float(m["stamina"]) * float(Game.character.derived()["melee_stamina_cost_mult"])
	var affordable: bool = player.stamina >= cost
	var base := Color(1, 1, 1) if affordable else Color(1.0, 0.45, 0.4)
	var coat: Array = player.imbue_elements() if player.imbued else []
	if not coat.is_empty() and affordable:
		base = Elements.color_of(String(coat[0])).lightened(0.25)
	var engaged := _enemy_in_swing(reach, spin)
	var alpha := 0.34 if engaged else 0.14
	alpha += 0.06 * sin(_pulse * 6.0) if engaged else 0.0

	# The reach as a very faint full ring, so you can judge distance all around.
	draw_arc(Vector2.ZERO, reach, 0.0, TAU, 40, Color(base, 0.08), 0.6)
	if spin:
		draw_arc(Vector2.ZERO, reach, 0.0, TAU, 40, Color(base, alpha + 0.12), 1.0)
		return

	var aim: float = player.aim_direction.angle()
	var half := deg_to_rad(float(m["arc_deg"])) * 0.5
	var points := PackedVector2Array([Vector2.ZERO])
	for i in WEDGE_STEPS + 1:
		points.append(Vector2.from_angle(aim - half + 2.0 * half * i / WEDGE_STEPS) * reach)
	draw_colored_polygon(points, Color(base, alpha * 0.45))
	draw_arc(Vector2.ZERO, reach, aim - half, aim + half, WEDGE_STEPS, Color(base, alpha + 0.2), 1.0)
	draw_line(Vector2.from_angle(aim - half) * (reach * 0.55), Vector2.from_angle(aim - half) * reach, Color(base, alpha + 0.1), 0.8)
	draw_line(Vector2.from_angle(aim + half) * (reach * 0.55), Vector2.from_angle(aim + half) * reach, Color(base, alpha + 0.1), 0.8)


## An enemy the next slash would hit.
func _enemy_in_swing(reach: float, spin: bool) -> bool:
	var half := deg_to_rad(float(SkillDB.MELEE["arc_deg"])) * 0.5
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null:
			continue
		var to_enemy := enemy.global_position - player.global_position
		if to_enemy.length() <= reach and (spin or absf(player.aim_direction.angle_to(to_enemy)) <= half):
			return true
	return false
