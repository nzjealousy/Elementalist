class_name SkillFx
extends RefCounted
## Visual effects for skills, built from code (CPUParticles2D, a glow sprite and expanding
## rings), so no art is needed and final art can replace them later. Each element has a look:
## fire flickers upward, water drips, earth throws heavy chunks, air streaks, mineral spins
## shards and martial skills strike sparks (see PROFILES).

## amount: particles; life: seconds; speed: min/max px/s; gravity: px/s^2; size: min/max scale;
## spin: degrees/s of rotation; colors: start/end of each particle's life.
const PROFILES := {
	"fire": {"amount": 20, "life": 0.4, "speed": Vector2(6, 26), "gravity": Vector2(0, -55), "size": Vector2(1.0, 2.4), "spin": 0.0, "colors": [Color("ffd8a0"), Color("e0403a")]},
	"water": {"amount": 16, "life": 0.45, "speed": Vector2(10, 34), "gravity": Vector2(0, 70), "size": Vector2(1.0, 1.8), "spin": 0.0, "colors": [Color("e0f8ff"), Color("2a78e0")]},
	"earth": {"amount": 12, "life": 0.5, "speed": Vector2(10, 40), "gravity": Vector2(0, 110), "size": Vector2(1.6, 3.0), "spin": 200.0, "colors": [Color("d8ffc8"), Color("1a6a48")]},
	"air": {"amount": 18, "life": 0.3, "speed": Vector2(30, 75), "gravity": Vector2.ZERO, "size": Vector2(0.8, 1.4), "spin": 0.0, "colors": [Color("f0fffa"), Color("3cc0b0")]},
	"mineral": {"amount": 14, "life": 0.45, "speed": Vector2(20, 60), "gravity": Vector2(0, 40), "size": Vector2(1.4, 2.6), "spin": 520.0, "colors": [Color("fff8c0"), Color("6a4a20")]},
	"light": {"amount": 16, "life": 0.4, "speed": Vector2(8, 32), "gravity": Vector2(0, -20), "size": Vector2(0.9, 2.0), "spin": 0.0, "colors": [Color("ffffff"), Color("d8d0ff")]},
	"dark": {"amount": 16, "life": 0.5, "speed": Vector2(6, 28), "gravity": Vector2(0, -10), "size": Vector2(1.2, 2.6), "spin": 120.0, "colors": [Color("f0c8ff"), Color("3a1070")]},
	"martial": {"amount": 12, "life": 0.25, "speed": Vector2(25, 70), "gravity": Vector2.ZERO, "size": Vector2(1.0, 1.8), "spin": 0.0, "colors": [Color("e0e0f8"), Color("5c5890")]},
}

static var _glow_texture: GradientTexture2D
static var _glow_material: CanvasItemMaterial


static var _additive: CanvasItemMaterial


## One shared additive material for glowing effect sprites.
static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


static func profile(element: String) -> Dictionary:
	return PROFILES.get(element if element != "" else "martial", PROFILES["martial"])


## A soft round light, tinted per use. Additive, so overlapping glows brighten.
static func glow_sprite(color: Color, scale: float = 1.0) -> Sprite2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
		_glow_texture.width = 24
		_glow_texture.height = 24
		_glow_material = CanvasItemMaterial.new()
		_glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var sprite := Sprite2D.new()
	sprite.texture = _glow_texture
	sprite.material = _glow_material
	sprite.modulate = color
	sprite.scale = Vector2(scale, scale)
	sprite.z_index = -1
	return sprite


## Particles in the look of `element`. `one_shot` bursts once; otherwise it emits until freed.
static func particles(element: String, one_shot: bool, amount_scale: float = 1.0) -> CPUParticles2D:
	var p: Dictionary = profile(element)
	var node := CPUParticles2D.new()
	node.amount = maxi(int(float(p["amount"]) * amount_scale), 1)
	node.lifetime = float(p["life"])
	node.one_shot = one_shot
	node.explosiveness = 0.9 if one_shot else 0.0
	node.spread = 180.0
	node.gravity = p["gravity"]
	node.initial_velocity_min = float(p["speed"].x)
	node.initial_velocity_max = float(p["speed"].y)
	node.scale_amount_min = float(p["size"].x)
	node.scale_amount_max = float(p["size"].y)
	node.angular_velocity_min = -float(p["spin"])
	node.angular_velocity_max = float(p["spin"])
	node.angle_max = 360.0 if float(p["spin"]) > 0.0 else 0.0
	var ramp := Gradient.new()
	ramp.set_color(0, p["colors"][0])
	ramp.set_color(1, Color(p["colors"][1], 0.0))
	ramp.add_point(0.6, p["colors"][1])
	node.color_ramp = ramp
	node.z_index = 50
	return node


## A one-off burst of the element's particles at `pos`; frees itself.
static func burst(parent: Node, pos: Vector2, element: String, amount_scale: float = 1.0) -> void:
	if parent == null:
		return
	var node := particles(element, true, amount_scale)
	parent.add_child(node)
	node.global_position = pos
	node.emitting = true
	node.finished.connect(node.queue_free)


## The flash at a caster's hand: a cone of particles thrown along `dir`.
static func cast_burst(parent: Node, pos: Vector2, element: String, dir: Vector2) -> void:
	if parent == null:
		return
	var node := particles(element, true, 0.6)
	node.spread = 35.0
	node.direction = dir
	parent.add_child(node)
	node.global_position = pos
	node.emitting = true
	node.finished.connect(node.queue_free)
	var flash := glow_sprite(Elements.color_of(element), 0.9)
	flash.z_index = 40
	parent.add_child(flash)
	flash.global_position = pos
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.18)
	tween.tween_callback(flash.queue_free)


## A bolt's look in flight: a glowing core and a trail of the element's particles.
static func trail(projectile: Node2D, element: String) -> void:
	projectile.add_child(glow_sprite(Color(Elements.color_of(element), 0.7), 1.1))
	var node := particles(element, false, 0.8)
	node.local_coords = false
	node.spread = 40.0
	node.initial_velocity_min = 2.0
	node.initial_velocity_max = 10.0
	node.lifetime = float(profile(element)["life"]) * 0.7
	projectile.add_child(node)


## Impact: particles plus a small shock ring.
static func impact(parent: Node, pos: Vector2, element: String) -> void:
	burst(parent, pos, element, 0.7)
	SpriteAnim.burst(parent, "fx_hit", pos, Elements.color_of(element) if element != "" else Color("e8e8f0"), 0.9)
	ring(parent, pos, 9.0, Elements.color_of(element), 0.2, 1.0)


## An area skill landing: a burst across its radius, a shock ring and a flash. A lingering area
## (`duration` > 0) keeps emitting until it ends. Everything is a child of `area`, so it follows
## and is freed with it.
static func area_burst(area: Node2D, element: String, radius: float, duration: float) -> void:
	var color := Elements.color_of(element)
	ring(area, Vector2.ZERO, radius, color, 0.4, 1.5, true)
	var rune_id := "fx_rune_" + (element if element != "" else "martial")  # the element's own rune circle...
	if not AssetDB.has_art(rune_id):
		rune_id = "fx_rune"                                                  # ...or the plain one
	if AssetDB.has_art(rune_id):  # a rune circle under the area, turning while it lasts
		var rune := Sprite2D.new()
		rune.modulate = Color(color.lightened(0.2), 1.0)   # additive on a dark floor: it reads as light
		rune.material = additive_material()
		rune.scale = Vector2.ONE * (radius * 2.0 / 38.0)
		rune.z_index = 1   # relative to the area (z -5): above the floor (-10) and its faint pool
		area.add_child(rune)
		var spin := SpriteAnim.attach(rune, rune_id, 8.0, rune)
		var fade := rune.create_tween()
		fade.tween_property(rune, "modulate:a", 0.0, maxf(duration, 0.5))
		fade.tween_callback(rune.queue_free)
	var node := particles(element, duration <= 0.0, clampf(radius / 20.0, 0.8, 3.0))
	node.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	node.emission_sphere_radius = radius * 0.8
	node.spread = 180.0
	node.initial_velocity_max *= 0.6
	if duration > 0.0:
		node.lifetime = float(profile(element)["life"]) * 1.4
		node.explosiveness = 0.0
	area.add_child(node)
	node.emitting = true
	var flash := glow_sprite(Color(color, 0.5), radius / 10.0)
	flash.z_index = -1   # relative to the area (z -5): above the floor
	area.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, maxf(duration, 0.4))


## A ring that grows to `radius` and fades. `parent` owns it.
static func ring(parent: Node, pos: Vector2, radius: float, color: Color, time: float = 0.35, width: float = 1.5, local: bool = false) -> void:
	if parent == null:
		return
	var node := FxRing.new()
	node.radius = radius
	node.color = color
	node.width = width
	parent.add_child(node)
	if local:
		node.position = pos
	else:
		node.global_position = pos
	var tween := node.create_tween()
	tween.tween_property(node, "t", 1.0, time)
	tween.tween_callback(node.queue_free)


## A lasting aura of particles on `target` (a buff, or a coated blade). Returns it so the owner
## can free it when the effect ends.
static func aura(target: Node2D, color: Color, element: String = "") -> CPUParticles2D:
	var node := particles(element, false, 0.5)
	node.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	node.emission_sphere_radius = 7.0
	node.gravity = Vector2(0, -16)
	node.initial_velocity_min = 1.0
	node.initial_velocity_max = 6.0
	node.lifetime = 0.7
	node.color = color
	node.color_ramp = null
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	node.color_ramp = fade
	node.z_index = 4
	target.add_child(node)
	node.emitting = true
	return node


## Four frames of three stars circling at the top of a picture `height` px tall (it stands on its position in the isometric view, so the
## stars float above whatever it is put on). Cached by height, registered in AssetDB as "stun:<height>".
static func stun_id(height: int) -> String:
	var id := "stun:%d" % height
	if AssetDB.has_art(id):
		return id
	var frames: Array = []
	for frame in 4:
		var image := Image.create(26, height, false, Image.FORMAT_RGBA8)
		for i in 3:
			var a := (float(i) / 3.0 + float(frame) / 12.0) * TAU
			var x := int(13.0 + cos(a) * 8.0)
			var y := int(4.0 + sin(a) * 2.5)
			var near := sin(a) > 0.0   # stars in front are bright, stars behind dim
			var colour := Color("f8e08a") if near else Color("a08850")
			for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var px: Vector2i = Vector2i(x, y) + d
				if px.x >= 0 and px.y >= 0 and px.x < 26 and px.y < height:
					image.set_pixelv(px, colour)
		frames.append(ImageTexture.create_from_image(image))
	AssetDB.register_frames(id, frames)
	return id


## The charge of a skill that has a wind-up: a ring that closes round the hero, and for an area skill a growing circle where it will land.
static func charge(body: Node2D, element: String, area_radius: float, caster: Node, id: String) -> Node2D:
	var node := FxCharge.new()
	node.color = Elements.color_of(element) if element != "" else Color("b8b8d8")
	node.area_radius = area_radius
	node.caster = caster
	node.skill_id = id
	body.add_child(node)
	return node


## The charge ring: `caster.windup_fraction()` fills it; an area skill also previews its circle under the aim point.
class FxCharge extends Node2D:
	var color := Color.WHITE
	var area_radius := 0.0
	var caster: Node
	var skill_id := ""

	func _ready() -> void:
		z_index = 45

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if caster == null or not is_instance_valid(caster):
			return
		var t: float = caster.windup_fraction()
		draw_arc(Vector2.ZERO, 13.0, -PI * 0.5, -PI * 0.5 + TAU * t, 32, Color(color, 0.95), 1.5)
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 32, Color(color, 0.18), 1.0)
		if area_radius > 0.0:
			var target: Vector2 = to_local(caster.area_target(skill_id))
			draw_arc(target, area_radius * (0.35 + 0.65 * t), 0.0, TAU, 36, Color(color, 0.25 + 0.6 * t), 1.0)
			draw_circle(target, area_radius * 0.12 * t, Color(color, 0.5))


## The ring that SkillFx.ring spawns: it draws itself, `t` runs 0 -> 1.
class FxRing extends Node2D:
	var radius := 20.0
	var color := Color.WHITE
	var width := 1.5
	var t := 0.0:
		set(value):
			t = value
			queue_redraw()

	func _ready() -> void:
		z_index = 45

	func _draw() -> void:
		var r := radius * (0.25 + 0.75 * t)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(color, 0.9 * (1.0 - t)), width)
