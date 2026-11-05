class_name RemoteAvatar
extends CharacterBody2D
## Another player's hero, as seen here (co-op). It is only a picture and a hurtbox: the real hero is played on
## the other machine, which tells us where it is, where it aims and how healthy it is (apply_state).
## On the host, monsters can hurt it (take_damage): the damage goes to the machine that plays it.
## Group "net_players". Monsters pick the nearest of the local Player and these.

const HURT_COOLDOWN := 0.35

var peer := 0
var hero_name := "Hero"
var hp := 100.0
var max_hp := 100.0
var aim := Vector2.RIGHT
var moving := false
var dodging := false
var net_pos := Vector2.ZERO
var sprite: Sprite2D

var _prefix := ""
var _anim: SpriteAnim
var _hurt_cd := 0.0
var _label: Label


func setup(peer_id: int, info: Dictionary) -> void:
	peer = peer_id
	hero_name = String(info.get("name", "Hero"))
	var look: Dictionary = info.get("look", {})
	if look.has("parts") and look.has("palette"):
		_prefix = HeroComposer.register(look)
	else:
		_prefix = HeroComposer.register(HeroLook.for_class(String(info.get("class", "wanderer"))))


func _ready() -> void:
	add_to_group("net_players")
	collision_layer = 8
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 8)
	shape.shape = rect
	shape.position = Vector2(0, 4)
	add_child(shape)
	sprite = Sprite2D.new()
	sprite.offset = Vector2(0, -9)
	add_child(sprite)
	_anim = SpriteAnim.attach(sprite, _prefix + ":down", 8.0, self)
	_label = Label.new()
	_label.text = hero_name
	_label.add_theme_font_size_override("font_size", 6)
	_label.add_theme_color_override("font_color", Color("dcd8f4"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	_label.position = Vector2(-20, -24)
	add_child(_label)
	net_pos = global_position


## [x, y, aim_x, aim_y, hp, max_hp, flags] where flags has 1 = moving, 2 = dodging.
func apply_state(state: Array) -> void:
	net_pos = Vector2(float(state[0]), float(state[1]))
	aim = Vector2(float(state[2]), float(state[3]))
	hp = float(state[4])
	max_hp = maxf(float(state[5]), 1.0)
	var flags := int(state[6])
	moving = flags & 1 != 0
	dodging = flags & 2 != 0


func is_down() -> bool:
	return hp <= 0.0


func _physics_process(delta: float) -> void:
	_hurt_cd = maxf(0.0, _hurt_cd - delta)
	if global_position.distance_to(net_pos) > 80.0:
		global_position = net_pos
	else:
		global_position = global_position.lerp(net_pos, 1.0 - exp(-16.0 * delta))
	var look_dir := aim - global_position
	if IsoView.active != null:
		look_dir = IsoView.screen_dir(look_dir)
	var facing := "side"
	if absf(look_dir.y) > absf(look_dir.x) * 0.6:
		facing = "up" if look_dir.y < 0.0 else "down"
	_anim.set_art("%s:%s" % [_prefix, facing])
	_anim.playing = moving or dodging
	sprite.flip_h = facing == "side" and look_dir.x < 0.0
	sprite.modulate = Color(1, 1, 1, 0.45) if (dodging or is_down()) else Color.WHITE
	_label.visible = not is_down()


func hurtbox() -> Rect2:
	return Rect2(global_position - Player.HURTBOX_SIZE * 0.5, Player.HURTBOX_SIZE)  # the same body as on its own machine


## Monsters hit this on the host; the damage is carried out on the machine that plays the hero.
func take_damage(amount: float, from: Vector2) -> bool:
	if is_down() or dodging or _hurt_cd > 0.0:
		return false
	_hurt_cd = HURT_COOLDOWN
	Net.send_damage(peer, amount, from)
	FloatText.spawn(get_parent(), global_position + Vector2(0, -4), "-%d" % int(round(amount)), Color("ff9a5a"), 8)
	return true
