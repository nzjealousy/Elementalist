extends CharacterBody2D
## Player: WASD movement, mouse aim, stamina-costed dodge, melee (slash and the dodge spin),
## health, and an elemental SkillCaster. Max HP, stamina, speed, regen and damage scaling all
## come from Game.character.
##
## Melee and imbue:
##   RMB is the basic attack: a slash, or (ranged-style classes while imbued) a bolt of the
##   selected element, which the SkillCaster casts. LMB is the fused cast (SkillCaster); for a
##   melee-style character with no elements it is a straight slash instead.
##   E toggles imbue. Every slash then carries the selected element (one only), costing a little
##   mana per swing; if you can't pay, it is a plain slash.
##   Buffs (V support skills) are timed effects in `buffs`: might (+damage), mend (heal per
##   second), ward (less damage taken) and haste (speed). Their length scales with Wisdom.
##   Dodge + attack = a 360 degree spin: costs more stamina, hits all around, can be imbued,
##   and makes you immune to damage until it finishes.

signal died

const STAMINA_REGEN_DELAY := 0.8
const CAMERA_LOOK := 0.25       # the camera drifts this share of the way toward the aim point
const CAMERA_LOOK_MAX := 60.0   # ... measured from the hero, at most this far
const DODGE_BUFFER := 0.15  # a dodge pressed this early still fires once it becomes possible
const IMBUE_SWING_COST := 4.0    # mana per element per imbued slash
const SPIN_STAMINA_MULT := 1.8   # a spin costs this many slashes' worth of stamina
const SPIN_DAMAGE_MULT := 1.15
const SPIN_COOLDOWN := 0.5
const SPIN_DURATION := 0.32  # how long the spin lasts, during which you cannot be hurt

@export var speed := 80.0
@export var dodge_speed := 260.0
@export var dodge_time := 0.18
@export var dodge_iframes := 0.12  # invulnerable only for the start of the dodge
@export var dodge_cooldown := 0.4
@export var dodge_stamina_cost := 30.0
@export var max_hp := 100.0
@export var hp_regen := 0.6  # HP per second
@export var hp_regen_delay := 6.0  # seconds after a hit before regen resumes
@export var max_stamina := 100.0
@export var stamina_regen := 30.0
@export var hurt_invulnerability := 0.35

var hp := 0.0
var stamina := 0.0
var aim_direction := Vector2.RIGHT
var caster: SkillCaster
var imbued := false  # the blade is coated (see class comment); toggled with E, no timer
var buffs: Dictionary = {}  # kind -> {"time": seconds left, "power": float}

var _dodge_left := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector2.ZERO
var _dodge_buffer := 0.0
var _spun := false  # one spin per dodge
var _spin_left := 0.0  # while > 0 the spin is still going: immune to damage
var _hurt_cd := 0.0
var _hp_regen_delay := 0.0
var _melee_cd := 0.0
var _stamina_delay := 0.0
var _knock := Vector2.ZERO
var _dodge_text_cd := 0.0
var _mend_text := 0.0   # heal accumulated since the last "+N" number
var _buff_fx: Dictionary = {}  # buff kind -> its aura particles
var _imbue_fx: CPUParticles2D

@onready var sprite: Sprite2D = $Sprite2D
var _anim: SpriteAnim
@onready var camera: Camera2D = $Camera2D
var _look := Vector2.ZERO   # the camera look-ahead, smoothed


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
	Game.character.reward_ready.connect(_on_reward_ready)
	Game.character.class_chosen.connect(_on_class_chosen)
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


func _on_reward_ready(_level: int) -> void:
	FloatText.spawn(get_parent(), global_position + Vector2(0, -24), "Reward ready!", Color("ffd84a"))


func _on_class_chosen(class_id: String) -> void:
	apply_stats(true)
	FloatText.spawn(get_parent(), global_position + Vector2(0, -16), "Class: %s" % Classes.CLASSES[class_id]["name"], Color("ffd84a"))


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


func is_spinning() -> bool:
	return _spin_left > 0.0


## Immune during the start of a dodge, briefly after a hit, and for the whole of a spin.
func is_invulnerable() -> bool:
	return _dodge_left > dodge_time - dodge_iframes or _hurt_cd > 0.0 or _spin_left > 0.0


## Returns true if the hit landed (false while invulnerable), so attackers only spend
## their cooldown on hits that actually connect.
func take_damage(amount: float, from: Vector2) -> bool:
	if is_invulnerable():
		if _hurt_cd <= 0.0 and _dodge_text_cd <= 0.0:  # avoided by dodging or spinning, not by a recent hit
			FloatText.spawn(get_parent(), global_position + Vector2(0, -6), "Dodge!", Color("bfe3ff"))
			_dodge_text_cd = 0.6
		return false
	amount *= float(Game.character.derived()["damage_taken_mult"]) * (1.0 - buff_power("ward"))
	hp -= amount
	_hurt_cd = hurt_invulnerability
	_hp_regen_delay = hp_regen_delay
	_knock = (global_position - from).normalized() * 120.0
	FloatText.spawn(get_parent(), global_position + Vector2(0, -4), "-%d" % int(round(amount)), Color("ff5a5a"), 10)
	Game.player_hurt(from - global_position)
	Juice.shake(2.0, 0.2)
	Sfx.play("player_hurt")
	if hp <= 0.0:
		Sfx.play("player_die")
		Sfx.duck(1.5)
		if died.get_connections().is_empty():
			get_tree().reload_current_scene()  # no run is listening (e.g. a bare scene): just restart
		else:
			died.emit()
	return true


## Slow passive recovery, paused for a few seconds after taking damage.
func regen_hp(delta: float) -> void:
	_hp_regen_delay -= delta
	if _hp_regen_delay <= 0.0:
		hp = minf(max_hp, hp + hp_regen * delta)


# ---------- buffs ----------

const BUFF_COLORS := {
	"might": Color("ff8a3d"), "mend": Color("5fd68a"), "ward": Color("c9b78a"), "haste": Color("d9f2ff"),
}
const BUFF_NAMES := {"might": "Might", "mend": "Mending", "ward": "Stone Skin", "haste": "Haste"}


## Starts (or refreshes) a timed buff. Its length scales with Wisdom and buff passives.
func add_buff(kind: String, time: float, power: float, _element: String = "") -> void:
	var length := time * float(Game.character.derived()["buff_duration_mult"])
	buffs[kind] = {"time": length, "power": power}
	FloatText.spawn(get_parent(), global_position + Vector2(0, -14), String(BUFF_NAMES.get(kind, kind)), BUFF_COLORS.get(kind, Color.WHITE))
	SkillFx.ring(get_parent(), global_position, 16.0, BUFF_COLORS.get(kind, Color.WHITE), 0.45, 1.5)
	_sync_buff_fx()


func buff_power(kind: String) -> float:
	return float(buffs.get(kind, {}).get("power", 0.0))


## Outgoing damage multiplier from the Might buff.
func damage_mult() -> float:
	return 1.0 + buff_power("might")


func _tick_buffs(delta: float) -> void:
	if buffs.is_empty():
		return
	if buffs.has("mend"):
		var heal := buff_power("mend") * delta
		hp = minf(max_hp, hp + heal)
		_mend_text += heal
		if _mend_text >= 8.0:
			FloatText.spawn(get_parent(), global_position + Vector2(0, -8), "+%d" % int(_mend_text), Color("5fd68a"), 9)
			_mend_text = 0.0
	var expired := false
	for kind in buffs.keys():
		buffs[kind]["time"] -= delta
		if buffs[kind]["time"] <= 0.0:
			buffs.erase(kind)
			expired = true
	if expired:
		_sync_buff_fx()


## One aura of particles per active buff.
func _sync_buff_fx() -> void:
	for kind in _buff_fx.keys():
		if not buffs.has(kind):
			_buff_fx[kind].queue_free()
			_buff_fx.erase(kind)
	for kind in buffs:
		if not _buff_fx.has(kind):
			_buff_fx[kind] = SkillFx.aura(self, BUFF_COLORS.get(kind, Color.WHITE))


## While imbued, the blade throws sparks of the element (changes with the selection).
func _sync_imbue_fx() -> void:
	var wanted := imbued and not imbue_elements().is_empty()
	if wanted and _imbue_fx == null:
		_imbue_fx = SkillFx.aura(self, Elements.color_of(imbue_elements()[0]), imbue_elements()[0])
	elif not wanted and _imbue_fx != null:
		_imbue_fx.queue_free()
		_imbue_fx = null
	elif wanted:
		_imbue_fx.color = Elements.color_of(imbue_elements()[0])


# ---------- imbue ----------

## The element an imbued blade carries: always just the selected one (a blade holds a single
## element; mixing is what the fused cast on LMB is for). None for the martial set.
func imbue_elements() -> Array[String]:
	var out: Array[String] = []
	if caster.selected_element() in Game.character.castable_elements():
		out.append(caster.selected_element())
	return out


## E: toggles imbue. Only characters who have an element can imbue. Returns true if it changed.
func try_imbue() -> bool:
	if imbued:
		imbued = false
		return true
	if Game.character.castable_elements().is_empty():
		return false
	imbued = true
	FloatText.spawn(get_parent(), global_position + Vector2(0, -8), "Imbued", Color("ffd84a"))
	return true


# ---------- melee ----------

## Slash reach in pixels: the base reach scaled by class and passives (Vanguard long, Channeler short).
func melee_reach() -> float:
	return float(SkillDB.MELEE["range"]) * float(Game.character.derived()["melee_range_mult"])


## Slash in `dir` (defaults to the mouse aim): a 110 degree arc. Costs stamina. With `spin`,
## a full circle that costs SPIN_STAMINA_MULT times as much and hits SPIN_DAMAGE_MULT harder.
## While imbued the hits carry the imbued elements (one hit per element, in order, so their
## combos fire) for a little mana each; if you can't pay, it is a plain physical slash.
func try_melee(dir: Vector2 = Vector2.ZERO, spin: bool = false) -> bool:
	var m: Dictionary = SkillDB.MELEE
	var stats: Dictionary = Game.character.derived()
	var cost := float(m["stamina"]) * float(stats["melee_stamina_cost_mult"]) * (SPIN_STAMINA_MULT if spin else 1.0)
	if (_melee_cd > 0.0 and not spin) or stamina < cost:
		return false
	if dir == Vector2.ZERO:
		dir = aim_direction
	spend_stamina(cost)
	Sfx.play("spin" if spin else "slash")
	_melee_cd = (SPIN_COOLDOWN if spin else float(m["cooldown"])) / float(stats["attack_speed"])
	if spin:
		_spin_left = SPIN_DURATION  # immune until the attack finishes
	else:
		_knock += dir * 60.0  # small lunge

	var coat: Array[String] = []
	if imbued:
		coat = imbue_elements()
	var swing_mana := IMBUE_SWING_COST * coat.size()
	if not coat.is_empty():
		if caster.mana >= swing_mana:
			caster.mana -= swing_mana
		else:
			coat.clear()  # can't pay: a plain slash

	var reach := melee_reach()
	var half_arc := deg_to_rad(float(m["arc_deg"])) * 0.5
	var base_damage := float(m["damage"]) * float(stats["melee_damage_mult"]) * damage_mult() * (SPIN_DAMAGE_MULT if spin else 1.0)
	var landed := false
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null:
			continue
		var to_enemy := enemy.global_position - global_position
		if to_enemy.length() > reach or (not spin and absf(dir.angle_to(to_enemy)) > half_arc):
			continue
		landed = true
		if coat.is_empty():
			enemy.take_hit({"damage": base_damage, "element": "", "knockback": m["knockback"], "from": global_position})
			continue
		for i in coat.size():
			var primary: Dictionary = SkillDB.DEFS[SkillDB.LOADOUTS[coat[i]]["primary"]]
			enemy.take_hit({
				"damage": base_damage * (SkillCaster.FUSION_DAMAGE * float(stats["fusion_damage_mult"]) if coat.size() > 1 else 1.0),
				"element": coat[i],
				"apply": caster.status_for(primary),
				"knockback": m["knockback"],
				"from": global_position,
				"text_offset": Vector2((i - (coat.size() - 1) * 0.5) * 12.0, 0.0),
			})
	if landed:
		Game.character.add_weapon_xp(1)
		for element in coat:
			Game.character.add_element_xp(element, 1)

	var slash := SlashEffect.new()
	slash.setup(dir.angle(), reach, 360.0 if spin else float(m["arc_deg"]), Elements.color_of(coat[0]) if not coat.is_empty() else Color.WHITE,
		SPIN_DURATION if spin else SlashEffect.LIFETIME)
	add_child(slash)
	return true


## Dodge + attack: the 360 degree spin. Only while rolling, once per dodge.
func try_spin() -> bool:
	if not is_dodging() or _spun:
		return false
	if try_melee(Vector2.ZERO, true):
		_spun = true
		return true
	return false


## Starts a dodge roll in `dir` (defaults to the mouse aim). Costs stamina.
func try_dodge(dir: Vector2 = Vector2.ZERO) -> bool:
	var dodge_cost := dodge_stamina_cost * float(Game.character.derived()["dodge_cost_mult"])
	if is_dodging() or _dodge_cd > 0.0 or stamina < dodge_cost:
		return false
	_dodge_dir = dir.normalized() if dir != Vector2.ZERO else aim_direction
	_dodge_left = dodge_time
	_dodge_cd = dodge_cooldown
	_spun = false
	spend_stamina(dodge_cost)
	Sfx.play("dodge")
	return true


## What a kill gives back (see Classes.KILL_MANA and the kill_* passive stats).
func restore_on_kill() -> void:
	var d: Dictionary = Game.character.derived()
	hp = minf(max_hp, hp + float(d["kill_hp"]))
	stamina = minf(max_stamina, stamina + float(d["kill_stamina"]))
	if caster:
		caster.mana = minf(caster.max_mana, caster.mana + float(d["kill_mana"]))


## Spends stamina and pauses its regeneration briefly. Also used by martial skills.
func spend_stamina(amount: float) -> void:
	stamina -= amount
	_stamina_delay = STAMINA_REGEN_DELAY


func _on_element_changed(element: String) -> void:
	FloatText.spawn(get_parent(), global_position + Vector2(0, 2), element.capitalize(), Elements.color_of(element))


func _process(delta: float) -> void:
	# Look ahead: the camera drifts a quarter of the way toward the aim point (with a gamepad, toward the
	# stick), so you see more of where you are shooting. Smoothed, and shake rides on top.
	var look := (Controls.aim_point(self, global_position) - global_position).limit_length(CAMERA_LOOK_MAX) * CAMERA_LOOK
	_look = _look.lerp(look, 1.0 - exp(-6.0 * delta))
	camera.offset = _look.round() + Juice.offset()


## Picks the art for where the hero faces (toward the aim) and walks it while moving. The art is
## per class (player_<class>_<down|up|side>), then generic, then the old single picture.
func _update_sprite() -> void:
	var facing := "side"
	if absf(aim_direction.y) > absf(aim_direction.x) * 1.1:
		facing = "up" if aim_direction.y < 0.0 else "down"
	var id := "player_%s_%s" % [Game.character.class_id, facing]
	if not AssetDB.has_art(id):
		id = "player_" + facing
	if not AssetDB.has_art(id):
		id = "player"
	if _anim == null:
		_anim = SpriteAnim.attach(sprite, id, 9.0, self)
	_anim.set_art(id)
	_anim.playing = velocity.length() > 8.0 or is_dodging()
	sprite.flip_h = facing == "side" and aim_direction.x < 0.0


func _physics_process(delta: float) -> void:
	aim_direction = (Controls.aim_point(self, global_position) - global_position).normalized()
	_update_sprite()

	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_hurt_cd = maxf(0.0, _hurt_cd - delta)
	_dodge_text_cd = maxf(0.0, _dodge_text_cd - delta)
	_tick_buffs(delta)
	_sync_imbue_fx()
	_melee_cd = maxf(0.0, _melee_cd - delta)
	_dodge_buffer = maxf(0.0, _dodge_buffer - delta)
	regen_hp(delta)
	if Input.is_action_just_pressed("imbue"):
		try_imbue()
	_stamina_delay -= delta
	if _stamina_delay <= 0.0:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)

	_spin_left = maxf(0.0, _spin_left - delta)

	# Melee input. RMB slashes (or shoots, see SkillCaster.rmb_mode: the caster handles that),
	# and LMB slashes for melee-style characters with no elements. Attacking while dodging with
	# RMB (or a slash-LMB) is the spin.
	var rmb_held := Input.is_action_pressed("attack_basic")
	var lmb_slash := Input.is_action_pressed("skill_primary") and caster.lmb_mode() == "slash"
	if is_dodging():
		if rmb_held or lmb_slash:
			try_spin()
	elif lmb_slash or (rmb_held and caster.rmb_mode() == "slash"):
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
		velocity = input * speed * (1.0 + buff_power("haste")) + _knock
	_knock = _knock.move_toward(Vector2.ZERO, 500.0 * delta)
	move_and_slide()

	if (is_dodging() or is_spinning()) and is_invulnerable():
		sprite.modulate = Color(1, 1, 1, 0.45)
	elif _hurt_cd > 0.0:
		sprite.modulate = Color(1.0, 0.45, 0.45)
	elif imbued and not imbue_elements().is_empty():
		sprite.modulate = Color.WHITE.lerp(Elements.color_of(imbue_elements()[0]), 0.45)  # blade glow
	else:
		sprite.modulate = Color.WHITE
