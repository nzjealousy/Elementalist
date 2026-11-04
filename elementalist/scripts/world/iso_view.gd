class_name IsoView
extends Node
## The isometric view of the world, drawn entirely in 2D: 2D simulation, 2D picture seen from a slanted angle.
##
## Gameplay stays in the flat scene (positions are 2D pixels, physics is 2D). IsoView paints it for the player:
##   * the ground (floor tiles and every flat effect: telegraphs, rings, area bursts, slash arcs, the aim
##     marker, the melee range ring) is rendered by the flat scene into a SubViewport and laid on the screen
##     as a skewed picture, so a square tile becomes a 2:1 diamond;
##   * walls and pillars are blocks drawn from three faces (top, left, right) with the tile's own art;
##   * every creature, pickup, prop and projectile is an ordinary Sprite2D standing where its flat body
##     stands, with a blob shadow; text above them is a Label, health bars are small rectangles;
##   * everything that stands up lives in one y-sorted node, so whatever is nearer the bottom of the screen
##     is drawn in front (a hero walks behind a wall, in front of a pillar).
## Nothing is 3D, so text and sprites stay as sharp as in the flat game. The screen position of a world point p is
## project(p) = (x - y, (x + y) / 2): one world pixel is one screen pixel along each diagonal.
##
## The flat canvas items of the world are sorted into two visibility layers so the main window does not draw them
## twice: LAYER_GROUND goes to the ground picture, LAYER_ENTITY (the things mirrored by standing sprites) to nobody.
## The stage sits in its own CanvasLayer below the HUD and is scrolled to follow the hero.
##
## Settings "iso_view" off keeps the plain top-down picture; IsoView is then not created at all.

const TILE := 16.0
const WALL_HEIGHT := 22.0         # screen pixels a wall rises
const CURB_HEIGHT := 5.0          # the walls nearest the viewer are kept low so they never hide the room
const PILLAR_HEIGHT := 18.0
const PILLAR_RADIUS := 6.5
const LAYER_GROUND := 2
const LAYER_ENTITY := 4
const FOLLOW_SPEED := 9.0
const BACKGROUND := Color(0.03, 0.025, 0.05)
const SHADE_LEFT := Color(0.74, 0.74, 0.82)   # the face looking south-west on the screen
const SHADE_RIGHT := Color(0.5, 0.5, 0.62)    # the face looking south-east, darker
const SHADE_TOP := Color(1.0, 0.97, 0.92)

static var active: IsoView = null  # the running view (null in flat mode and in tests)

var dungeon: Node2D
var ground_viewport: SubViewport

var _layer: CanvasLayer             # the scrolling stage
var _back_layer: CanvasLayer        # the colour behind the room
var _ground: Sprite2D               # the flat floor laid on the screen as a diamond
var _stage: Node2D                  # y-sorted: walls, sprites, shadows
var _room_size := Vector2(320, 180) # world pixels
var _focus := Vector2.ZERO          # the world point the view is centred on
var _mirrors: Dictionary = {}       # CanvasItem -> CanvasItem standing in for it
var _shadows: Dictionary = {}       # mirrored sprite -> its blob shadow
var _walls: Array[Node2D] = []
var _blob: Texture2D
var _world_root: Node
var _snap := true                   # the next frame puts the view straight on the hero


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
	_build_stage()
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

## Where a world point lands on the stage (before the stage is scrolled).
static func project(p: Vector2) -> Vector2:
	return Vector2(p.x - p.y, (p.x + p.y) * 0.5)


## The world point that lands at stage point `s`: the inverse of project.
static func unproject(s: Vector2) -> Vector2:
	return Vector2(s.x * 0.5 + s.y, s.y - s.x * 0.5)


## Where a world direction points on the screen (x right, y down; the ground is foreshortened).
static func screen_dir(d: Vector2) -> Vector2:
	return project(d) * 0.70710678


## The world direction that appears as `screen` (x right, y down) on the screen: the inverse of screen_dir.
## Moving "up" on the screen is north-west on the ground, "right" is north-east.
static func world_dir(screen: Vector2) -> Vector2:
	if screen == Vector2.ZERO:
		return Vector2.ZERO
	return unproject(screen).normalized() * screen.length()


## The 2D world point under the mouse.
static func mouse_ground() -> Vector2:
	if active == null or not active.is_inside_tree():
		return Vector2.ZERO
	return active.ground_point_at(active.get_viewport().get_mouse_position())


## The world point shown at `screen_point` (viewport pixels).
func ground_point_at(screen_point: Vector2) -> Vector2:
	return unproject(screen_point - _layer.offset)


## Where a world point appears in the viewport, `height` pixels above the ground.
func screen_point_of(p: Vector2, height: float = 0.0) -> Vector2:
	return project(p) - Vector2(0.0, height) + _layer.offset


# ---------- the stage ----------

func _build_stage() -> void:
	_back_layer = CanvasLayer.new()
	_back_layer.layer = -3
	add_child(_back_layer)
	var back := ColorRect.new()
	back.color = BACKGROUND
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_layer.add_child(back)

	_layer = CanvasLayer.new()
	_layer.layer = -2
	add_child(_layer)

	ground_viewport = SubViewport.new()
	ground_viewport.world_2d = get_viewport().world_2d  # the very same flat world, drawn once more, for the floor
	ground_viewport.disable_3d = true
	ground_viewport.transparent_bg = false
	ground_viewport.canvas_cull_mask = 1 | LAYER_GROUND  # (the nodes above the world, left on layer 1, must not hide it)
	ground_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ground_viewport.size = Vector2i(_room_size)
	add_child(ground_viewport)

	_ground = Sprite2D.new()
	_ground.centered = false
	_ground.texture = ground_viewport.get_texture()
	_ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ground.transform = Transform2D(Vector2(1.0, 0.5), Vector2(-1.0, 0.5), Vector2.ZERO)  # x runs right-down, y left-down
	_ground.z_index = -100
	_layer.add_child(_ground)

	_stage = Node2D.new()
	_stage.y_sort_enabled = true
	_layer.add_child(_stage)
	_apply_room_size()


func _apply_room_size() -> void:
	ground_viewport.size = Vector2i(maxi(int(_room_size.x), 16), maxi(int(_room_size.y), 16))


# ---------- rooms ----------

## A new room is about to be built: forget the old walls and size the ground.
func begin_room(room: Dictionary, tile: int) -> void:
	for wall in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()
	_room_size = Vector2(int(room["cols"]), int(room["rows"])) * float(tile)
	_apply_room_size()
	_snap = true


## One solid tile of the room (a wall, a door's seal or a pillar) becomes a block.
func add_wall(tile: Vector2i, texture: Texture2D, cols: int, rows: int, pillar: bool = false) -> void:
	var height := PILLAR_HEIGHT if pillar else WALL_HEIGHT
	if not pillar and (tile.x == cols - 1 or tile.y == rows - 1):
		height = CURB_HEIGHT  # the near walls stay low
	var block := Block.new()
	block.texture = texture
	block.height = height
	block.pillar = pillar
	block.position = project((Vector2(tile) + Vector2(0.5, 0.5)) * TILE)
	_stage.add_child(block)
	_walls.append(block)


func wall_count() -> int:
	return _walls.size()


## A wall or pillar: its three visible faces, drawn about the block's own centre on the ground.
class Block extends Node2D:
	var texture: Texture2D
	var height := 20.0
	var pillar := false

	func _draw() -> void:
		if texture == null:
			return
		if pillar:
			_draw_column()
		else:
			_draw_box()

	## Screen offset of a corner (wx, wy are world pixels from the tile centre) `h` pixels above the ground.
	func _pt(wx: float, wy: float, h: float) -> Vector2:
		return IsoView.project(Vector2(wx, wy)) - Vector2(0.0, h)

	func _draw_box() -> void:
		var half := IsoView.TILE * 0.5
		var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		var left := PackedVector2Array([_pt(-half, half, height), _pt(half, half, height), _pt(half, half, 0.0), _pt(-half, half, 0.0)])
		draw_colored_polygon(left, IsoView.SHADE_LEFT, uv, texture)
		var right := PackedVector2Array([_pt(half, half, height), _pt(half, -half, height), _pt(half, -half, 0.0), _pt(half, half, 0.0)])
		draw_colored_polygon(right, IsoView.SHADE_RIGHT, uv, texture)
		var top := PackedVector2Array([_pt(-half, -half, height), _pt(half, -half, height), _pt(half, half, height), _pt(-half, half, height)])
		draw_colored_polygon(top, IsoView.SHADE_TOP, uv, texture)
		var edge := Color(0.0, 0.0, 0.0, 0.45)  # the outline that makes the block read against the floor
		draw_polyline(PackedVector2Array([top[3], top[2], top[1]]), edge, 1.0)
		draw_line(top[2], left[2], edge, 1.0)
		draw_line(left[3], left[2], edge, 1.0)
		draw_line(left[2], right[2], edge, 1.0)
		draw_line(right[2], right[1], edge, 1.0)

	func _draw_column() -> void:
		var rx := IsoView.PILLAR_RADIUS * 1.4142
		var ry := IsoView.PILLAR_RADIUS * 0.7071
		var steps := 12
		var body := PackedVector2Array()
		var colours := PackedColorArray()
		var uvs := PackedVector2Array()
		for i in range(steps + 1):  # the lower half of the base, left to right
			var a := PI * float(i) / float(steps)
			body.append(Vector2(-cos(a) * rx, sin(a) * ry))
			colours.append(IsoView.SHADE_LEFT.lerp(IsoView.SHADE_RIGHT, float(i) / float(steps)))
			uvs.append(Vector2(float(i) / float(steps), 1.0))
		for i in range(steps, -1, -1):  # and the lower half of the rim back
			var a := PI * float(i) / float(steps)
			body.append(Vector2(-cos(a) * rx, sin(a) * ry - height))
			colours.append(IsoView.SHADE_LEFT.lerp(IsoView.SHADE_RIGHT, float(i) / float(steps)))
			uvs.append(Vector2(float(i) / float(steps), 0.0))
		draw_polygon(body, colours, uvs, texture)
		var rim := PackedVector2Array()
		var rim_uv := PackedVector2Array()
		for i in 16:
			var a := TAU * float(i) / 16.0
			rim.append(Vector2(cos(a) * rx, sin(a) * ry - height))
			rim_uv.append(Vector2(0.5 + cos(a) * 0.4, 0.5 + sin(a) * 0.4))
		draw_colored_polygon(rim, IsoView.SHADE_TOP, rim_uv, texture)
		draw_polyline(PackedVector2Array(rim + PackedVector2Array([rim[0]])), Color(0, 0, 0, 0.4), 1.0)


## A monster's health bar on the stage.
class Bar extends Node2D:
	var fraction := 1.0
	var bar_width := 14.0

	func _draw() -> void:
		draw_rect(Rect2(-bar_width * 0.5 - 1.0, -1.0, bar_width + 2.0, 4.0), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(-bar_width * 0.5, 0.0, maxf(bar_width * fraction, 0.5), 2.0), Color("e24b3b").lerp(Color("6bd66b"), fraction))


# ---------- sorting the flat world into layers ----------

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
		or owner is Player or owner is RemoteAvatar


func _make_mirror(node: CanvasItem) -> CanvasItem:
	if node is Sprite2D:
		var sprite := Sprite2D.new()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_stage.add_child(sprite)
		var shadow := Sprite2D.new()
		shadow.texture = _blob
		shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		shadow.modulate = Color(0, 0, 0, 0.4)
		shadow.z_index = -1  # on the floor, under every standing sprite
		_stage.add_child(shadow)
		_shadows[node] = shadow
		return sprite
	if node is Label:
		var label := Label.new()
		label.z_index = 60
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(label)
		return label
	var bar := Bar.new()  # a health bar
	bar.z_index = 50
	_stage.add_child(bar)
	return bar


func mirror_count() -> int:
	return _mirrors.size()


# ---------- every frame ----------

func _process(delta: float) -> void:
	_follow_hero(delta)
	for node in _mirrors.keys():
		var mirror: CanvasItem = _mirrors[node]
		if not is_instance_valid(node) or not (node as Node).is_inside_tree():
			_drop(node)
			continue
		if node is Sprite2D:
			_update_sprite(node, mirror as Sprite2D)
		elif node is Label:
			_update_label(node, mirror as Label)
		else:
			_update_bar(node, mirror as Bar)


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
	var margin := Vector2(1.5, 1.5) * TILE
	target.x = clampf(target.x, margin.x, maxf(_room_size.x - margin.x, margin.x))
	target.y = clampf(target.y, margin.y, maxf(_room_size.y - margin.y, margin.y))
	if _snap:
		_focus = target
		_snap = false
	else:
		_focus = _focus.lerp(target, 1.0 - exp(-FOLLOW_SPEED * delta))
	var centre := get_viewport().get_visible_rect().size * 0.5
	_layer.offset = (centre - project(_focus) + Juice.offset()).round()


func _update_sprite(src: Sprite2D, mirror: Sprite2D) -> void:
	var visible_now := src.is_visible_in_tree() and src.texture != null
	mirror.visible = visible_now
	var shadow := _shadows.get(src) as Sprite2D
	if shadow:
		shadow.visible = visible_now
	if not visible_now:
		return
	var texture := src.texture
	var size_scale := Vector2(absf(src.global_scale.x), absf(src.global_scale.y))
	mirror.texture = texture
	mirror.flip_h = src.flip_h
	mirror.flip_v = src.flip_v
	mirror.scale = size_scale
	mirror.offset = Vector2(src.offset.x, -float(texture.get_height()) * 0.5)  # the picture stands on its position
	var colour := src.modulate * src.self_modulate
	mirror.modulate = colour
	mirror.material = src.material
	var parent := src.get_parent()
	var lift := 0.0
	if parent is Enemy and (parent as Enemy).behavior == "flutter":
		lift = 7.0
	elif parent is Projectile or parent is EnemyProjectile:
		lift = 5.0
	var ground := project(src.global_position)
	mirror.position = (ground - Vector2(0.0, lift)).round()
	if parent is Projectile:  # a bolt points where it flies, as seen on the screen (its art points right)
		mirror.rotation = project(Vector2.RIGHT.rotated(src.global_rotation)).angle()
		mirror.offset = src.offset
	else:
		mirror.rotation = 0.0
	if shadow:
		var span := clampf(float(texture.get_width()) * size_scale.x * 0.9, 6.0, 40.0)
		shadow.scale = Vector2(span / 16.0, span / 16.0 * 0.5)
		shadow.position = ground.round()
		shadow.modulate.a = 0.4 * colour.a


func _update_label(src: Label, mirror: Label) -> void:
	mirror.visible = src.is_visible_in_tree() and src.text != ""
	if not mirror.visible:
		return
	if mirror.text != src.text:
		mirror.text = src.text
		mirror.reset_size()
	var colour := src.get_theme_color("font_color") * src.modulate
	mirror.add_theme_font_override("font", src.get_theme_font("font"))
	mirror.add_theme_font_size_override("font_size", src.get_theme_font_size("font_size"))
	mirror.add_theme_color_override("font_color", colour)
	mirror.add_theme_color_override("font_outline_color", Color(0, 0, 0, colour.a))
	mirror.add_theme_constant_override("outline_size", src.get_theme_constant("outline_size"))
	var anchor: Vector2 = src.global_position + Vector2(src.size.x * 0.5, src.size.y)
	var up := 26.0
	if src is FloatText:  # damage numbers float up from where they appeared
		if not src.has_meta("iso_origin"):
			src.set_meta("iso_origin", src.global_position)
		var origin: Vector2 = src.get_meta("iso_origin")
		var rise := maxf(origin.y - src.global_position.y, 0.0)
		anchor = origin + Vector2(src.size.x * 0.5, src.size.y)
		up = 29.0 + rise
	else:
		var holder := src.get_parent() as Node2D
		if holder != null and holder != _world_root and holder.get_parent() != _world_root:
			anchor = holder.global_position
			up = 22.0
	mirror.position = (project(anchor) - Vector2(0.0, up) - mirror.size * 0.5).round()


func _update_bar(src: Node2D, mirror: Bar) -> void:
	var bar_src := src as EnemyHealthBar
	var enemy := bar_src.enemy
	if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
		mirror.visible = false
		return
	mirror.visible = true
	mirror.fraction = clampf(enemy.hp / maxf(enemy.max_hp, 1.0), 0.0, 1.0)
	mirror.bar_width = EnemyHealthBar.SIZE.x
	mirror.queue_redraw()
	mirror.position = (project(enemy.global_position) - Vector2(0.0, float(enemy.hit_rect().size.y) + 6.0)).round()


# ---------- helpers ----------

func _make_blob() -> Texture2D:
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			image.set_pixel(x, y, Color(1, 1, 1, clampf(1.2 - d * 1.2, 0.0, 1.0) if d < 1.0 else 0.0))
	return ImageTexture.create_from_image(image)
