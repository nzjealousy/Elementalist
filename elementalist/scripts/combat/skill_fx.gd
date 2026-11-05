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


# ---------- the budget ----------

## One cap on the short-lived emitters of every helper here and in HitFx: an imbued spin can land ~70 hits in one frame.
## Hit sparks stop at MAX_LIVE - RESERVE; the last RESERVE slots are kept for priority effects (deaths, level-ups, bosses).
const MAX_LIVE := 48
const RESERVE := 12
static var _live: Array = []   # the emitters started here (untyped: it may hold freed ones until the next count)


## Whether a new short-lived emitter may start now.
static func admit(priority: bool = false) -> bool:
	return live_count() < (MAX_LIVE if priority else MAX_LIVE - RESERVE)


## The emitters alive now (a freed one, or one outside the tree, no longer counts).
static func live_count() -> int:
	for i in range(_live.size() - 1, -1, -1):
		if not is_instance_valid(_live[i]) or not (_live[i] as Node).is_inside_tree():
			_live.remove_at(i)
	return _live.size()


## Starts a one-shot emitter at `pos` in the flat world; it frees itself when done and counts against the cap meanwhile.
static func launch(parent: Node, node: CPUParticles2D, pos: Vector2) -> void:
	parent.add_child(node)
	node.global_position = pos
	_go(node)


## Starts a one-shot emitter that rises off the ground: in the isometric view it stands on the stage at ground point `pos`,
## `lift` px up, sorted with the bodies (in the ground picture it would slide along the floor); in the flat view it sits at
## `pos` minus the lift. With `follow` it rides along on that body (a level-up column).
static func launch_upright(parent: Node, node: CPUParticles2D, pos: Vector2, lift: float = 0.0, follow: Node2D = null) -> void:
	var view := IsoView.active
	var iso := view != null and view.is_inside_tree()
	var holder: Node2D = node
	if follow != null:
		var rider := FxFollow.new()
		rider.target = follow
		rider.iso = iso
		rider.lift = lift
		node.local_coords = true  # the specks move with the body
		rider.add_child(node)
		node.finished.connect(rider.queue_free)
		holder = rider
	if iso:
		node.z_index = 0  # sorted with the bodies
		view.add_upright(holder, pos, lift)
	else:
		parent.add_child(holder)
		holder.global_position = pos - Vector2(0.0, lift)
	_go(node)


static func _go(node: CPUParticles2D) -> void:
	node.emitting = true
	node.finished.connect(node.queue_free)
	_live.append(node)


## Plain square specks of one colour: brighter at birth, fading out. Callers shape the motion.
static func specks(color: Color, amount: int, life: float) -> CPUParticles2D:
	var node := CPUParticles2D.new()
	node.amount = maxi(amount, 1)
	node.lifetime = life
	node.one_shot = true
	node.explosiveness = 0.85
	node.spread = 180.0
	node.gravity = Vector2.ZERO
	node.scale_amount_min = 1.0
	node.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.lightened(0.35), 1.0))
	ramp.set_color(1, Color(color, 0.0))
	ramp.add_point(0.5, color)
	node.color_ramp = ramp
	node.z_index = 50
	return node


## A one-off burst of the element's particles at `pos`; frees itself.
static func burst(parent: Node, pos: Vector2, element: String, amount_scale: float = 1.0, priority: bool = false) -> void:
	if parent == null or not admit(priority):
		return
	launch(parent, particles(element, true, amount_scale), pos)


## The flash at a caster's hand: a cone of particles thrown along `dir`.
static func cast_burst(parent: Node, pos: Vector2, element: String, dir: Vector2) -> void:
	if parent == null or not admit():
		return
	var node := particles(element, true, 0.6)
	node.spread = 35.0
	node.direction = dir
	launch(parent, node, pos)
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
	if parent == null or not admit():
		return  # over budget: the ring and the flash go too
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


# ---------- events: deaths, level-ups, loot, dust ----------

const DUST := Color("a39bb0")          # floor dust: a cold grey-violet, lighter than the obsidian floors so it reads
const GOLD := Color("f8d060")          # a level-up and a chest
const REWARD := Color("b868ff")        # a reward card is ready
const COLD := Color("a8bcf0")          # the hero's last breath


## A monster falls: its last picture fades where it stood while specks of the killing element (else its variant's) rise off
## it and a small ring fades; a boss or mini boss gets more specks, two rings and a brief upward spray. Only a picture: the
## monster is freed at once as before, so loot, XP and the room's clear happen when they always did.
static func death(parent: Node, enemy: Enemy) -> void:
	if parent == null or enemy.sprite == null:
		return
	var element := enemy.last_element if enemy.last_element != "" else enemy.variant
	var color := Elements.color_of(element if element != "" else "martial")
	var big := enemy.boss or enemy.mini
	var height := enemy.picture_height()
	var width := float(enemy.sprite.texture.get_width()) if enemy.sprite.texture != null else 16.0
	var pos := enemy.global_position
	_corpse(parent, enemy, color, 0.6 if big else 0.4)
	ring(parent, pos, 22.0 if big else 10.0, color, 0.5 if big else 0.45, 1.0)
	if big:
		ring(parent, pos, 36.0, color.lightened(0.2), 0.8, 1.0)
	if not admit(true):
		return
	var motes := specks(color, 32 if big else 18, 0.75 if big else 0.5)
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(width * 0.3, height * 0.35)
	motes.direction = Vector2.UP
	motes.spread = 50.0
	motes.gravity = Vector2(0, -24)
	motes.initial_velocity_min = 3.0
	motes.initial_velocity_max = 12.0
	launch_upright(parent, motes, pos, height * 0.5)
	if big and admit(true):
		var spray := specks(color.lightened(0.15), 24, 0.8)
		spray.explosiveness = 1.0
		spray.direction = Vector2.UP
		spray.spread = 22.0
		spray.gravity = Vector2(0, 90)
		spray.initial_velocity_min = 40.0
		spray.initial_velocity_max = 80.0
		launch_upright(parent, spray, pos, height * 0.4)


## The fallen monster's picture, fading out in its element's colour. IsoView stands it up like a body (FxCorpse).
static func _corpse(parent: Node, enemy: Enemy, color: Color, time: float) -> void:
	var corpse := FxCorpse.new()
	var picture := Sprite2D.new()
	picture.texture = enemy.sprite.texture
	picture.offset = enemy.sprite.offset
	picture.flip_h = enemy.sprite.flip_h
	picture.scale = enemy.sprite.scale
	picture.modulate = enemy.sprite.modulate
	corpse.add_child(picture)
	corpse.z_index = enemy.z_index
	parent.add_child(corpse)
	corpse.global_position = enemy.global_position
	var fade := corpse.create_tween()
	fade.tween_property(picture, "modulate", Color(color.lightened(0.3), 0.0), time)
	fade.tween_callback(corpse.queue_free)


## The hero falls: cold specks drift up off them, slowly, for over a second.
static func hero_death(parent: Node, pos: Vector2) -> void:
	if parent == null or not admit(true):
		return
	var motes := specks(COLD, 36, 1.4)
	motes.explosiveness = 0.3
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(7, 9)
	motes.direction = Vector2.UP
	motes.spread = 40.0
	motes.gravity = Vector2(0, -14)
	motes.initial_velocity_min = 6.0
	motes.initial_velocity_max = 14.0
	launch_upright(parent, motes, pos, 10.0)


## A level-up (gold) or a ready reward (violet): a ring grows from the hero's feet and a column of specks rises, riding along.
static func fanfare(hero: Node2D, reward: bool) -> void:
	if hero == null or not hero.is_inside_tree() or not admit(true):
		return
	var color := REWARD if reward else GOLD
	ring(hero, Vector2.ZERO, 18.0, color, 0.8, 1.5, true)
	var column := specks(color, 20, 0.8)
	column.explosiveness = 0.3
	column.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	column.emission_rect_extents = Vector2(6, 1)
	column.direction = Vector2.UP
	column.spread = 6.0
	column.gravity = Vector2(0, -10)
	column.initial_velocity_min = 30.0
	column.initial_velocity_max = 55.0
	column.scale_amount_max = 1.5
	launch_upright(hero.get_parent(), column, hero.global_position, 0.0, hero)


## Loot collected: a tiny sparkle in its colour.
static func sparkle(parent: Node, pos: Vector2, color: Color) -> void:
	if parent == null or not admit():
		return
	var node := specks(color, 12, 0.4)
	node.explosiveness = 1.0
	node.initial_velocity_min = 20.0
	node.initial_velocity_max = 36.0
	node.gravity = Vector2(0, 30)
	node.scale_amount_max = 1.5
	launch_upright(parent, node, pos, 7.0)


## A chest opens: a small upward puff of gold specks.
static func chest_puff(parent: Node, pos: Vector2) -> void:
	if parent == null or not admit():
		return
	var node := specks(GOLD, 14, 0.55)
	node.explosiveness = 1.0
	node.direction = Vector2.UP
	node.spread = 50.0
	node.gravity = Vector2(0, 80)
	node.initial_velocity_min = 24.0
	node.initial_velocity_max = 44.0
	launch_upright(parent, node, pos, 6.0)


## A low puff of floor dust over `extents` (a dodge's feet, a door's sill). It stays on the ground picture.
static func dust(parent: Node, pos: Vector2, extents: Vector2, amount: int = 6, priority: bool = false) -> void:
	if parent == null or not admit(priority):
		return
	var node := specks(DUST, amount, 0.4)
	node.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	node.emission_rect_extents = extents
	node.initial_velocity_min = 6.0
	node.initial_velocity_max = 16.0
	node.damping_min = 20.0
	node.damping_max = 30.0
	node.scale_amount_max = 1.5
	node.z_index = 3   # just above the floor and its rings' pool, under the bodies in the flat view
	launch(parent, node, pos)


## A boss slam's dust cloud: specks born along the circle's edge roll outward and settle.
static func dust_ring(parent: Node, pos: Vector2, radius: float) -> void:
	if parent == null or not admit(true):
		return
	var node := specks(DUST, 36, 0.8)
	node.explosiveness = 1.0
	node.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	node.emission_sphere_radius = radius * 0.9
	node.initial_velocity_min = 2.0
	node.initial_velocity_max = 6.0
	node.radial_accel_min = 30.0
	node.radial_accel_max = 60.0
	node.damping_min = 10.0
	node.damping_max = 20.0
	launch(parent, node, pos)


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


## The stun stars over a stunned body, a child of `body` 12 px taller than its `picture` (`height` px). The isometric view stands it on the
## body's position; the offset lines its bottom up with the picture's in the flat view, so the stars float over the head in both.
static func stun_stars(body: Node2D, picture: Sprite2D, height: int) -> Sprite2D:
	var id := stun_id(height + 12)
	var stars := Sprite2D.new()
	stars.texture = AssetDB.get_texture(id)
	stars.z_index = 30
	stars.offset = Vector2(0.0, picture.offset.y - 6.0)
	body.add_child(stars)
	SpriteAnim.attach(stars, id, 8.0, stars)
	return stars


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


## Keeps an upright effect on a moving body: on the isometric stage (at the body's projected spot) or in the flat world.
class FxFollow extends Node2D:
	var target: Node2D
	var iso := false
	var lift := 0.0

	func _process(_delta: float) -> void:
		if not is_instance_valid(target):
			return
		if iso:
			position = (IsoView.project(target.global_position) - Vector2(0.0, lift)).round()
		else:
			global_position = target.global_position - Vector2(0.0, lift)


## The fading picture SkillFx.death leaves; IsoView stands its sprite up like a body's.
class FxCorpse extends Node2D:
	pass


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
