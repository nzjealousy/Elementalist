class_name IsoView
extends Node3D
## The isometric HD-2D view of the world: 2D simulation, 3D picture.
##
## Gameplay stays in the 2D scene (positions are 2D pixels, physics is 2D). IsoView draws it for the player:
##   * the ground (floor tiles and every flat effect: telegraphs, rings, area bursts, slash arcs, the aim
##     marker, the melee range ring) is rendered by the 2D scene into a SubViewport and laid on a plane;
##   * walls and pillars are real 3D boxes, so they have height, take light and cast shadows;
##   * every creature, pickup, prop and projectile is an upright sprite (Sprite3D, billboard) standing
##     where its 2D body stands, with a blob shadow; text above them is Label3D, health bars are quads;
##   * a sun with shadows, cool ambient light and a warm torch around the hero light it all, seen through
##     an orthographic camera at the classic isometric angle (yaw 45, pitch 35.3 degrees).
## 1 world unit = TILE pixels (16), so a tile is one unit. The 2D canvas items of the world are sorted into
## two canvas layers so the main window does not draw them flat: LAYER_GROUND goes to the ground texture,
## LAYER_ENTITY (the things mirrored in 3D) to nobody.
##
## Settings "iso_view" off keeps the plain top-down picture; IsoView is then not created at all.

const UNIT := 16.0
const PITCH := 35.264
const YAW := 45.0
const CAMERA_SIZE := 10.5         # world units across the screen's height at the centre
const STRETCH := 1.2247           # 1 / cos(pitch): upright sprites are stretched so they keep their height on screen
const WALL_HEIGHT := 1.6
const CURB_HEIGHT := 0.4          # the walls nearest the camera are kept low so they never hide the room
const PILLAR_HEIGHT := 1.35
const LAYER_GROUND := 2
const LAYER_ENTITY := 4
const FOLLOW_SPEED := 9.0

static var active: IsoView = null  # the running view (null in flat mode and in tests)

var dungeon: Node2D
var camera: Camera3D
var ground_viewport: SubViewport
var ground_mesh: MeshInstance3D
var sun: DirectionalLight3D
var torch: OmniLight3D

var _walls: Node3D
var _room_size := Vector2(320, 180)  # pixels
var _focus := Vector2.ZERO           # the 2D point the camera looks at
var _mirrors: Dictionary = {}        # CanvasItem -> Node3D standing in for it
var _shadows: Dictionary = {}        # mirrored sprite -> its blob shadow
var _wall_materials: Dictionary = {} # Texture2D -> StandardMaterial3D
var _blob: Texture2D
var _world_root: Node
var _snap := true                    # the next frame puts the camera straight on the hero


## Builds an IsoView for `world` (the Dungeon) and puts it next to it in the scene.
static func attach(world: Node2D) -> IsoView:
	var view := IsoView.new()
	view.dungeon = world
	world.add_child(view)
	return view


func _ready() -> void:
	active = self
	_world_root = dungeon.get_parent()
	_blob = _make_blob()
	_build_scene()
	get_viewport().canvas_cull_mask = 0xFFFFFFFF & ~(LAYER_GROUND | LAYER_ENTITY)
	get_tree().node_added.connect(_on_node_added)
	_sweep(_world_root)


func _exit_tree() -> void:
	if active == self:
		active = null
	if is_inside_tree():
		var vp := get_viewport()
		if vp:
			vp.canvas_cull_mask = 0xFFFFFFFF
	if get_tree() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


# ---------- coordinates ----------

static func ground_to_3d(p: Vector2) -> Vector3:
	return Vector3(p.x / UNIT, 0.0, p.y / UNIT)


static func to_ground(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) * UNIT


## Where a world direction points on the screen (x right, y down; the ground is foreshortened).
static func screen_dir(d: Vector2) -> Vector2:
	var s := 0.70710678
	return Vector2((d.x - d.y) * s, (d.x + d.y) * s * 0.577)


## The world direction that appears as `screen` (x right, y down) on the screen: the inverse of screen_dir.
## Moving "up" on the screen is north-west on the ground, "right" is north-east.
static func world_dir(screen: Vector2) -> Vector2:
	if screen == Vector2.ZERO:
		return Vector2.ZERO
	var s := 0.70710678
	var a := screen.x / s                 # dx - dy
	var b := screen.y / (s * 0.577)       # dx + dy
	return Vector2((a + b) * 0.5, (b - a) * 0.5).normalized() * screen.length()


## The 2D world point under the mouse, found by casting a ray from the camera to the ground plane.
static func mouse_ground() -> Vector2:
	if active == null or active.camera == null or not active.is_inside_tree():
		return Vector2.ZERO
	return active.ground_point_at(active.get_viewport().get_mouse_position())


func ground_point_at(screen_point: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(screen_point)
	var dir := camera.project_ray_normal(screen_point)
	if absf(dir.y) < 0.0001:
		return _focus
	var t := -origin.y / dir.y
	return to_ground(origin + dir * t)


## Where a 2D world point appears in the window (for anything that has to line up with the picture).
func screen_point_of(p: Vector2, height: float = 0.0) -> Vector2:
	return camera.unproject_position(ground_to_3d(p) + Vector3(0, height, 0))


# ---------- the 3D scene ----------

func _build_scene() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_SIZE
	camera.near = 0.1
	camera.far = 140.0
	camera.rotation_degrees = Vector3(-PITCH, YAW, 0.0)
	camera.current = true
	add_child(camera)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	torch = OmniLight3D.new()
	torch.light_color = Color(1.0, 0.78, 0.5)
	torch.light_energy = 1.1
	torch.omni_range = 7.5
	torch.omni_attenuation = 1.4
	add_child(torch)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.025, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.78)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_env.environment = env
	add_child(world_env)

	ground_viewport = SubViewport.new()
	ground_viewport.world_2d = get_viewport().world_2d  # the very same 2D world, drawn once more, for the floor
	ground_viewport.disable_3d = true
	ground_viewport.transparent_bg = false
	ground_viewport.canvas_cull_mask = 1 | LAYER_GROUND  # (the nodes above the world, left on layer 1, must not hide it)
	ground_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ground_viewport.size = Vector2i(_room_size)
	add_child(ground_viewport)

	ground_mesh = MeshInstance3D.new()
	ground_mesh.mesh = PlaneMesh.new()
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_texture = ground_viewport.get_texture()
	ground_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ground_material.roughness = 1.0
	ground_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	ground_mesh.material_override = ground_material
	ground_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground_mesh)

	_walls = Node3D.new()
	add_child(_walls)
	_apply_room_size()


func _apply_room_size() -> void:
	ground_viewport.size = Vector2i(maxi(int(_room_size.x), 16), maxi(int(_room_size.y), 16))
	(ground_mesh.mesh as PlaneMesh).size = Vector2(_room_size.x / UNIT, _room_size.y / UNIT)
	ground_mesh.position = Vector3(_room_size.x / UNIT * 0.5, 0.0, _room_size.y / UNIT * 0.5)


# ---------- rooms ----------

## A new room is about to be built: forget the old walls and size the ground.
func begin_room(room: Dictionary, tile: int) -> void:
	for child in _walls.get_children():
		child.queue_free()
	_room_size = Vector2(int(room["cols"]), int(room["rows"])) * float(tile)
	_apply_room_size()
	_snap = true


## One solid tile of the room (a wall, a door's seal or a pillar) becomes a box.
func add_wall(tile: Vector2i, texture: Texture2D, cols: int, rows: int, pillar: bool = false) -> void:
	var height := PILLAR_HEIGHT if pillar else WALL_HEIGHT
	if not pillar and (tile.x == cols - 1 or tile.y == rows - 1):
		height = CURB_HEIGHT  # the near walls stay low
	var box := MeshInstance3D.new()
	if pillar:  # a round column
		var column := CylinderMesh.new()
		column.top_radius = 0.4
		column.bottom_radius = 0.46
		column.height = height
		column.radial_segments = 10
		box.mesh = column
	else:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, height, 1.0)
		box.mesh = mesh
	box.material_override = _wall_material(texture)
	box.position = Vector3(tile.x + 0.5, height * 0.5, tile.y + 0.5)
	_walls.add_child(box)


func wall_count() -> int:
	return _walls.get_child_count()


func _wall_material(texture: Texture2D) -> StandardMaterial3D:
	if _wall_materials.has(texture):
		return _wall_materials[texture]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_wall_materials[texture] = material
	return material


# ---------- sorting the 2D world into layers ----------

func _sweep(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_sweep(child)


func _on_node_added(node: Node) -> void:
	if not (node is CanvasItem) or node == self:
		return
	var kind := _classify(node)
	if kind == 0:
		return
	(node as CanvasItem).visibility_layer = kind
	if kind == LAYER_ENTITY:
		_mirrors[node] = _make_mirror(node)


## 0: not part of the world (menus, HUD); LAYER_ENTITY: shown as something standing up; LAYER_GROUND: flat on the floor.
func _classify(node: Node) -> int:
	if _world_root == null or not is_instance_valid(_world_root) or not _world_root.is_ancestor_of(node):
		return 0
	var up := node.get_parent()
	while up != null and up != _world_root:
		if up is CanvasLayer or up is Window:
			return 0
		up = up.get_parent()
	if node is Label:
		return LAYER_ENTITY
	if node is EnemyHealthBar:
		return LAYER_ENTITY
	if node is Sprite2D and _stands_up(node.get_parent()):
		return LAYER_ENTITY
	return LAYER_GROUND


func _stands_up(owner: Node) -> bool:
	return owner is Enemy or owner is Pickup or owner is Interactable or owner is Projectile or owner is EnemyProjectile \
		or owner is Player


func _make_mirror(node: CanvasItem) -> Node3D:
	if node is Sprite2D:
		var sprite := Sprite3D.new()
		sprite.pixel_size = 1.0 / UNIT
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.shaded = false
		sprite.double_sided = true
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		add_child(sprite)
		var shadow := Sprite3D.new()
		shadow.texture = _blob
		shadow.pixel_size = 1.0 / UNIT
		shadow.axis = Vector3.AXIS_Y
		shadow.shaded = false
		shadow.modulate = Color(0, 0, 0, 0.4)
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shadow.transparent = true
		add_child(shadow)
		_shadows[node] = shadow
		return sprite
	if node is Label:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 1.0 / UNIT
		label.no_depth_test = true
		label.fixed_size = false
		label.shaded = false
		label.double_sided = true
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.render_priority = 10
		label.outline_render_priority = 9
		add_child(label)
		return label
	var bar := Node3D.new()  # a health bar: a dark quad with a coloured fill
	for i in 2:
		var quad := MeshInstance3D.new()
		quad.mesh = QuadMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.no_depth_test = true
		material.render_priority = 8 + i
		quad.material_override = material
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar.add_child(quad)
	add_child(bar)
	return bar


func mirror_count() -> int:
	return _mirrors.size()


# ---------- every frame ----------

func _process(delta: float) -> void:
	_follow_hero(delta)
	for node in _mirrors.keys():
		var mirror: Node3D = _mirrors[node]
		if not is_instance_valid(node) or not (node as Node).is_inside_tree():
			_drop(node)
			continue
		if node is Sprite2D:
			_update_sprite(node, mirror)
		elif node is Label:
			_update_label(node, mirror)
		else:
			_update_bar(node, mirror)


func _drop(node) -> void:
	var mirror: Node = _mirrors.get(node)
	if is_instance_valid(mirror):
		mirror.queue_free()
	var shadow: Node = _shadows.get(node)
	if is_instance_valid(shadow):
		shadow.queue_free()
	_mirrors.erase(node)
	_shadows.erase(node)


func _follow_hero(delta: float) -> void:
	var hero := get_tree().get_first_node_in_group("player") as Node2D
	if hero == null:
		return
	var look: Vector2 = hero.get("_look") if hero.get("_look") != null else Vector2.ZERO
	var target := hero.global_position + look
	var margin := Vector2(1.5, 1.5) * UNIT
	target.x = clampf(target.x, margin.x, maxf(_room_size.x - margin.x, margin.x))
	target.y = clampf(target.y, margin.y, maxf(_room_size.y - margin.y, margin.y))
	if _snap:
		_focus = target
		_snap = false
	else:
		_focus = _focus.lerp(target, 1.0 - exp(-FOLLOW_SPEED * delta))
	var back := camera.global_transform.basis.z
	camera.position = ground_to_3d(_focus) + back * 40.0
	var shake := Juice.offset() / UNIT
	camera.h_offset = shake.x
	camera.v_offset = shake.y
	torch.position = ground_to_3d(hero.global_position) + Vector3(0, 1.8, 0)


func _update_sprite(src: Sprite2D, mirror: Node3D) -> void:
	var sprite := mirror as Sprite3D
	var visible_now := src.is_visible_in_tree() and src.texture != null
	sprite.visible = visible_now
	var shadow := _shadows.get(src) as Sprite3D
	if shadow:
		shadow.visible = visible_now
	if not visible_now:
		return
	var texture := src.texture
	sprite.texture = texture
	sprite.flip_h = src.flip_h
	sprite.flip_v = src.flip_v
	sprite.offset = Vector2(src.offset.x, 0.0)
	var colour := src.modulate * src.self_modulate
	sprite.modulate = colour
	var height := float(texture.get_height()) * absf(src.global_scale.y)
	var width := float(texture.get_width()) * absf(src.global_scale.x)
	sprite.scale = Vector3(absf(src.global_scale.x), absf(src.global_scale.y) * STRETCH, 1.0)
	var ground := ground_to_3d(src.global_position)
	var lift := 0.0
	if src.get_parent() is Enemy and (src.get_parent() as Enemy).behavior == "flutter":
		lift = 0.45
	sprite.position = ground + Vector3(0.0, height * 0.5 / UNIT * STRETCH + lift, 0.0)
	if shadow:
		var span := clampf(width * 0.9, 6.0, 40.0)
		shadow.scale = Vector3(span / 16.0, span / 16.0 * 0.6, 1.0)
		shadow.position = ground + Vector3(0.0, 0.03, 0.0)
		shadow.modulate.a = 0.4 * colour.a


func _update_label(src: Label, mirror: Node3D) -> void:
	var label := mirror as Label3D
	label.visible = src.is_visible_in_tree() and src.text != ""
	if not label.visible:
		return
	label.text = src.text
	label.font = src.get_theme_font("font")
	label.font_size = src.get_theme_font_size("font_size")
	var colour := src.get_theme_color("font_color") * src.modulate
	label.modulate = colour
	label.outline_modulate = Color(0, 0, 0, colour.a)
	label.outline_size = src.get_theme_constant("outline_size")
	var anchor: Vector2 = src.global_position + Vector2(src.size.x * 0.5, src.size.y)
	var height := 1.6
	var rise := 0.0
	if src is FloatText:  # damage numbers float up from where they appeared
		if not src.has_meta("iso_origin"):
			src.set_meta("iso_origin", src.global_position)
		var origin: Vector2 = src.get_meta("iso_origin")
		rise = maxf(origin.y - src.global_position.y, 0.0)
		anchor = origin + Vector2(src.size.x * 0.5, src.size.y)
		height = 1.8 + rise / UNIT
	else:
		var owner := src.get_parent() as Node2D
		if owner != null and owner != _world_root and owner.get_parent() != _world_root:
			anchor = owner.global_position
			height = 1.4
	label.position = ground_to_3d(anchor) + Vector3(0.0, height, 0.0)


func _update_bar(src: Node2D, mirror: Node3D) -> void:
	var bar_src := src as EnemyHealthBar
	var enemy := bar_src.enemy
	if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
		mirror.visible = false
		return
	var frac := clampf(enemy.hp / maxf(enemy.max_hp, 1.0), 0.0, 1.0)
	mirror.visible = true
	var height := float(enemy.hit_rect().size.y) / UNIT * STRETCH + 0.5
	mirror.position = ground_to_3d(enemy.global_position) + Vector3(0.0, height, 0.0)
	var width := EnemyHealthBar.SIZE.x / UNIT
	var back := mirror.get_child(0) as MeshInstance3D
	var fill := mirror.get_child(1) as MeshInstance3D
	(back.mesh as QuadMesh).size = Vector2(width + 0.1, 0.2)
	(fill.mesh as QuadMesh).size = Vector2(maxf(width * frac, 0.01), 0.12)
	fill.position = Vector3((width * frac - width) * 0.5, 0.0, 0.001)
	(back.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, 0.85)
	(fill.material_override as StandardMaterial3D).albedo_color = Color("e24b3b").lerp(Color("6bd66b"), frac)
	(back.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


# ---------- helpers ----------

func _make_blob() -> Texture2D:
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			image.set_pixel(x, y, Color(1, 1, 1, clampf(1.2 - d * 1.2, 0.0, 1.0) if d < 1.0 else 0.0))
	return ImageTexture.create_from_image(image)
