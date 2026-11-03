extends CharacterBody2D
## Player: WASD movement, mouse aim, stamina-costed dodge, stamina-based physical attack
## (RMB), health, and an elemental SkillCaster (LMB / Q / 1-5 / mouse wheel).
## Max HP, stamina, speed, regen and damage scaling all come from Game.character.

signal died

const STAMINA_REGEN_DELAY := 0.5
const DODGE_BUFFER := 0.15  # a dodge pressed this early still fires once it becomes possible

@export var speed := 80.0
@export var dodge_speed := 260.0
@export var dodge_time := 0.18
@export var dodge_iframes := 0.12  # invulnerable only for the start of the dodge
@export var dodge_cooldown := 0.4
@export var dodge_stamina_cost := 25.0
@export var max_hp := 100.0
@export var hp_regen := 0.6  # HP per second
@export var hp_regen_delay := 3.0  # seconds after a hit before regen resumes
@export var max_stamina := 100.0
@export var stamina_regen := 30.0
@export var hurt_invulnerability := 0.5

var hp := 0.0
var stamina := 0.0
var aim_direction := Vector2.RIGHT
var caster: SkillCaster

var _dodge_left := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector2.ZERO
var _dodge_buffer := 0.0
var _hurt_cd := 0.0
var _hp_regen_delay := 0.0
var _melee_cd := 0.0
var _stamina_delay := 0.0
var _knock := Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	add_to_group("player")
	sprite.texture = AssetDB.get_texture("player")
	caster = SkillCaster.new()
	caster.body = self
	caster.element_changed.connect(_on_element_changed)
	add_child(caster)
	apply_stats(true)
	stamina = max_stamina
	Game.character.changed.connect(apply_stats)
	Game.character.leveled_up.connect(_on_level_up)
	Game.character.mastery_leveled.connect(_on_mastery_leveled)
	Game.character.passive_unlocked.connect(_on_passive_unlocked)
	var marker := AimMarker.new()
	marker.player = self
	add_child(marker)


## Pulls max HP / stamina / speed / regen from the character's attributes and passives.
## Keeps your current HP fraction unless `heal` is set.
func apply_stats(heal: bool = false) -> void:
	var d: Dictionary = Game.character.derived()
	var new_max := float(d["max_hp"])
	if heal or max_hp <= 0.0:
		hp = new_max
	elif not is_equal_approx(new_max, max_hp):
		hp = clampf(hp / max_hp * new_max, 0.0, new_max)
	max_hp = new_max
	hp_regen = float(d["hp_regen"])
	max_stamina = float(d["max_stamina"])
	stamina = minf(stamina, max_stamina)
	stamina_regen = float(d["stamina_regen"])
	speed = float(d["move_speed"])
	if caster:
		caster.apply_stats()


## A level-up restores a share of max HP (CharacterData.LEVEL_UP_HEAL_FRACTION), not all of it.
func _on_level_up(new_level: int) -> void:
	apply_stats()
	hp = minf(max_hp, hp + max_hp * CharacterData.LEVEL_UP_HEAL_FRACTION)
	FloatText.spawn(get_parent(), global_position + Vector2(0, -8), "Level %d!" % new_level, Color("ffd84a"))
	Juice.shake(1.5, 0.2)


func _on_mastery_leveled(label: String, new_level: int) -> void:
	FloatText.spawn(get_parent(), global_position + Vector2(0, -8), "%s mastery %d" % [label, new_level], Color("9be8ff"))


func _on_passive_unlocked(passive_name: String) -> void:
	FloatText.spawn(get_parent(), global_position + Vector2(0, -16), "Passive: %s" % passive_name, Color("b6ff8a"))


func set_camera_limits(rect: Rect2i) -> void:
	# Called by the room before this node's _ready, so @onready vars aren't set yet.
	var cam: Camera2D = get_node("Camera2D")
	cam.limit_left = rect.position.x
	cam.limit_top = rect.position.y
	cam.limit_right = rect.end.x
	cam.limit_bottom = rect.end.y


## The player's body rectangle in world space (full sprite), used for enemy contact hits.
func hurtbox() -> Rect2:
	var size := sprite.texture.get_size()
	return Rect2(global_position - size * 0.5, size)


func is_dodging() -> bool:
	return _dodge_left > 0.0


func is_invulnerable() -> bool:
	return _dodge_left > dodge_time - dodge_iframes or _hurt_cd > 0.0


## Returns true if the hit landed (false while invulnerable), so attackers only spend
## their cooldown on hits that actually connect.
func take_damage(amount: float, from: Vector2) -> bool:
	if is_invulnerable():
		return false
	amount *= float(Game.character.derived()["damage_taken_mult"])
	hp -= amount
	_hurt_cd = hurt_invulnerability
	_hp_regen_delay = hp_regen_delay
	_knock = (global_position - from).normalized() * 120.0
	FloatText.spawn(get_parent(), global_position, str(int(round(amount))), Color("ff5a5a"))
	Juice.shake(2.0, 0.2)
	if hp <= 0.0:
		died.emit()
		get_tree().reload_current_scene()
	return true


## Slow passive recovery, paused for a few seconds after taking damage.
func regen_hp(delta: float) -> void:
	_hp_regen_delay -= delta
	if _hp_regen_delay <= 0.0:
		hp = minf(max_hp, hp + hp_regen * delta)


## Physical sweep in `dir` (defaults to the mouse aim). Costs stamina, ignores mana.
## Damage scales with Strength, weapon mastery and passives; a landed hit trains the weapon.
func try_melee(dir: Vector2 = Vector2.ZERO) -> bool:
	var m: Dictionary = SkillDB.MELEE
	var stats: Dictionary = Game.character.derived()
	var cost := float(m["stamina"]) * float(stats["melee_stamina_cost_mult"])
	if _melee_cd > 0.0 or stamina < cost:
		return false
	if dir == Vector2.ZERO:
		dir = aim_direction
	spend_stamina(cost)
	_melee_cd = float(m["cooldown"])
	_knock += dir * 60.0  # small lunge

	var half_arc := deg_to_rad(float(m["arc_deg"])) * 0.5
	var landed := false
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null:
			continue
		var to_enemy := enemy.global_position - global_position
		if to_enemy.length() <= float(m["range"]) and absf(dir.angle_to(to_enemy)) <= half_arc:
			landed = true
			enemy.take_hit({
				"damage": float(m["damage"]) * float(stats["melee_damage_mult"]),
				"element": "",
				"knockback": m["knockback"],
				"from": global_position,
			})
	if landed:
		Game.character.add_weapon_xp(1)

	var slash := SlashEffect.new()
	slash.setup(dir.angle(), float(m["range"]), float(m["arc_deg"]))
	add_child(slash)
	return true


## Starts a dodge roll in `dir` (defaults to the mouse aim). Costs stamina.
func try_dodge(dir: Vector2 = Vector2.ZERO) -> bool:
	if is_dodging() or _dodge_cd > 0.0 or stamina < dodge_stamina_cost:
		return false
	_dodge_dir = dir.normalized() if dir != Vector2.ZERO else aim_direction
	_dodge_left = dodge_time
	_dodge_cd = dodge_cooldown
	spend_stamina(dodge_stamina_cost)
	return true


## Spends stamina and pauses its regeneration briefly. Also used by martial skills.
func spend_stamina(amount: float) -> void:
	stamina -= amount
	_stamina_delay = STAMINA_REGEN_DELAY


func _on_element_changed(element: String) -> void:
	FloatText.spawn(get_parent(), global_position + Vector2(0, 2), element.capitalize(), Elements.color_of(element))


func _process(_delta: float) -> void:
	camera.offset = Juice.offset()


func _physics_process(delta: float) -> void:
	aim_direction = (get_global_mouse_position() - global_position).normalized()
	sprite.flip_h = aim_direction.x < 0.0

	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_hurt_cd = maxf(0.0, _hurt_cd - delta)
	_melee_cd = maxf(0.0, _melee_cd - delta)
	_dodge_buffer = maxf(0.0, _dodge_buffer - delta)
	regen_hp(delta)
	_stamina_delay -= delta
	if _stamina_delay <= 0.0:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)

	if Input.is_action_pressed("attack_basic"):
		try_melee()

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_just_pressed("dodge"):
		_dodge_buffer = DODGE_BUFFER
	if _dodge_buffer > 0.0 and try_dodge(input):
		_dodge_buffer = 0.0

	if is_dodging():
		_dodge_left -= delta
		# Ease out: fast burst that settles, so the end of the roll is committal.
		velocity = _dodge_dir * dodge_speed * (0.35 + 0.65 * clampf(_dodge_left / dodge_time, 0.0, 1.0))
	else:
		velocity = input * speed + _knock
	_knock = _knock.move_toward(Vector2.ZERO, 500.0 * delta)
	move_and_slide()

	if is_invulnerable() and is_dodging():
		sprite.modulate = Color(1, 1, 1, 0.45)
	elif _hurt_cd > 0.0:
		sprite.modulate = Color(1.0, 0.45, 0.45)
	else:
		sprite.modulate = Color.WHITE
