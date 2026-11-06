class_name Lighting
extends Node
## The light of the isometric view: each place is dimmed to its own ambient colour and soft round pools of light
## follow the hero, partners, their bolts, the monsters on screen, the boss, the exit door, the camp's props and rare loot.
##
## Only what carries the light-mask bit LIT is lit: the floor tiles (in the flat world, seen through the ground
## picture), the wall blocks and the props on the stage. They are dimmed to the ambient (the floor by its own shader,
## the stage by a "dark" light that subtracts 1 - ambient) and the pooled lights add theirs back, so a lit pixel is
## about texture * (ambient + pools). Everything else keeps the default mask and its full colour: creatures, bolts,
## loot, telegraphs and spell effects (they are in the ground picture too, but untagged), labels, health bars and the
## HUD. So the ink silhouettes' element glow pops on a darker world.
##
## Each light is a pair: one in the flat world (it lights the floor; the ground picture's skew turns its circle into
## the ground's ellipse) and one on the stage (walls and props). MAX_LIGHTS pairs are built once and reused; every
## frame the candidates are ranked (choose) and the best get a pair. IsoView builds this node, so the flat
## top-down view has no lighting at all, and neither does the setting "off".

const LIT := 1 << 5            # the light-mask bit of lit things (no other light in the game uses it)
const MAX_LIGHTS := 24         # pairs alive at once
const MAX_BOLTS := 6           # only the nearest few bolts light up
const MAX_CANDIDATES := 128
const UNUSED := 0x7FFFFFFFFFFFFFFF
const TEXTURE_RADIUS := 64.0   # the pool texture is 128 px across
const DARK_SPAN := 8192.0      # px the stage's dark light covers, centred on the origin: any room
const LIFT := 8.0              # the stage light hangs this far above the ground (it lights wall faces, not only bases)
const SOFT_AMBIENT := 0.4      # "soft": the ambient moves this share of the way back to unlit...
const SOFT_ENERGY := 0.6       # ...and the pools keep this share of their strength

## The floor: dimmed to the ambient here, and lit by the pools. The dungeon floors are near black and a plain light
## only multiplies a tile's own colour, so a pool also adds a touch of its own colour (tint): it reads as the element's light.
## Under a pool the floor's own hue is also pulled toward grey (neutral), so a warm light on a cold floor reads as warm
## light instead of a grey-pink mix of the two.
const FLOOR_SHADER := """
shader_type canvas_item;
uniform vec3 ambient = vec3(1.0);
uniform float tint = 0.15;
uniform float neutral = 0.9;
void fragment() {
	COLOR.rgb *= ambient;
}
void light() {
	vec3 lum = vec3(0.3, 0.59, 0.11);
	vec3 c = LIGHT_COLOR.rgb;
	float n = neutral * (1.0 - min(c.r, min(c.g, c.b)) / max(max(c.r, max(c.g, c.b)), 0.001));  // only a coloured light takes the floor's hue
	vec3 tile = COLOR.rgb / ambient;
	vec3 lit = mix(tile, vec3(dot(tile, lum)), n);
	LIGHT = vec4(c * (lit + vec3(tint)) * LIGHT_ENERGY + (vec3(dot(COLOR.rgb, lum)) - COLOR.rgb) * n * min(LIGHT_ENERGY, 1.0), LIGHT_COLOR.a);
}
"""

## Light kinds, in priority order (a lower kind always wins a pair first).
enum {HERO, PARTNER, BOSS, DOOR, BOLT, ENEMY, PROP, LOOT}
const RADIUS := [64.0, 56.0, 60.0, 48.0, 26.0, 26.0, 60.0, 14.0]   # by kind: the pool's half-width on the screen (px)
const ENERGY := [1.1, 0.9, 0.9, 0.9, 1.2, 0.8, 0.8, 0.8]          # by kind, tuned by eye on the dark floors

## A monster whose glow is pale (ghost, bone, lich: mixed or washed-out art) would light a flat white patch: its pool
## takes its own hue at PALE_SATURATION + 0.15 (a grey one takes a cold spectral tint) and, but for a boss, is softer.
## A barred door glows dim and cold, an open one warm, so the way out is easy to find.
const PALE_SATURATION := 0.45
const PALE_TINT := Color(0.55, 0.7, 1.0)
const SOFTER := 0.7              # energy share of a pale monster's pool and of a barred door
const DOOR_OPEN := Color(1.0, 0.78, 0.45)
const DOOR_LOCKED := Color(0.5, 0.62, 1.0)
const DOOR_INWARD := {"north": Vector2(0, 12), "south": Vector2(0, -12), "west": Vector2(12, 0), "east": Vector2(-12, 0)}  # a door's pool lies on the floor in front of it
const FLICKER := 1               # candidate flags
const SOFT := 2

## The ambient of each place (Dungeon._theme): a tint (brightest channel 1) times how bright the world stays.
const AMBIENT := {
	"camp": {"color": Color(0.78, 0.82, 1.0), "strength": 0.82},    # moonlit, cool blue-violet
	"vault": {"color": Color(1.0, 0.93, 0.86), "strength": 0.74},   # dim ash, warm grey-brown
	"crypt": {"color": Color(0.76, 0.95, 1.0), "strength": 0.72},   # deep teal
	"hollow": {"color": Color(0.84, 1.0, 0.8), "strength": 0.74},   # deep green
	"ember": {"color": Color(1.0, 0.76, 0.66), "strength": 0.72},   # dark red-brown: the lava keeps most of its red
	"spire": {"color": Color(0.9, 0.8, 1.0), "strength": 0.72},     # deep violet
}

var stage: CanvasLayer         # IsoView's scrolling layer, where the stage lights go
var view: IsoView
var mode := "full"             # Settings "lighting": "full" or "soft" ("off" never builds this node)

var _tracked: Array = []           # everything that may carry a light (see track); untyped, it may hold freed nodes
var _world_lights: Array[PointLight2D] = []
var _stage_lights: Array[PointLight2D] = []
var _dark: PointLight2D           # dims the walls and props on the stage
## The candidates of this frame, in fixed arrays so a frame allocates nothing.
var _keys := PackedInt64Array()
var _pos := PackedVector2Array()
var _colour := PackedColorArray()
var _kind := PackedInt32Array()
var _phase := PackedFloat32Array()
var _flags := PackedByteArray()  # FLICKER, SOFT
var _time := 0.0
var _hero_hex := ""
var _hero_colour := Color.WHITE
var _partner_colours := PackedColorArray()   # by glow code (Player.glow_code)
var _art_glows: Dictionary = {}              # picture id -> the colour its art glows in
var _floor_material: ShaderMaterial
var _pool: GradientTexture2D
var _boss_pool: GradientTexture2D


func _ready() -> void:
	mode = String(Settings.get_value("lighting"))
	var shader := Shader.new()
	shader.code = FLOOR_SHADER
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = shader
	_pool = pool_texture()
	_boss_pool = pool_texture(true)
	for i in MAX_LIGHTS:
		_world_lights.append(_light(self, 0, _pool))
		_stage_lights.append(_light(stage, stage.layer, _pool))
	var plain := GradientTexture2D.new()  # all white: the dark light covers everything evenly
	plain.gradient = Gradient.new()
	plain.gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE])
	plain.width = 8
	plain.height = 8
	_dark = _light(stage, stage.layer, plain)  # a positional light: a DirectionalLight2D ignores the item mask and would dim everything
	_dark.blend_mode = Light2D.BLEND_MODE_SUB
	_dark.texture_scale = DARK_SPAN / 8.0
	_dark.enabled = true
	for code in 9:
		_partner_colours.append(_bright(Player.glow_color(code)))
	_keys.resize(MAX_CANDIDATES)
	_phase.resize(MAX_CANDIDATES)
	_pos.resize(MAX_CANDIDATES)
	_colour.resize(MAX_CANDIDATES)
	_kind.resize(MAX_CANDIDATES)
	_flags.resize(MAX_CANDIDATES)
	set_theme("vault")


func _light(holder: Node, layer: int, texture: Texture2D) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = texture
	light.range_item_cull_mask = LIT
	light.range_layer_min = layer   # a light reaches only the canvas layers in its range
	light.range_layer_max = layer
	light.enabled = false
	holder.add_child(light)
	return light


## The soft round light the pools share: full in the middle, fading smoothly to nothing at the rim. A boss's is `steep`:
## a bright core that falls off fast, so the boss stands in a spot of light instead of flattening the room.
static func pool_texture(steep: bool = false) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 0.85, 1.0])
	var alphas := [1.0, 0.55, 0.2, 0.05, 0.0] if steep else [1.0, 0.8, 0.42, 0.12, 0.0]
	gradient.colors = PackedColorArray(alphas.map(func(a): return Color(1, 1, 1, a)))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = int(TEXTURE_RADIUS * 2.0)
	texture.height = int(TEXTURE_RADIUS * 2.0)
	return texture


# ---------- the place ----------

## The ambient colour of `theme` for a lighting mode ("soft" is pushed back toward unlit).
static func ambient(theme: String, lighting_mode: String = "full") -> Color:
	var entry: Dictionary = AMBIENT.get(theme, AMBIENT["vault"])
	var colour: Color = entry["color"]
	colour = Color(colour.r, colour.g, colour.b) * float(entry["strength"])
	colour.a = 1.0
	return colour.lerp(Color.WHITE, SOFT_AMBIENT) if lighting_mode == "soft" else colour


## A new room: its place's ambient, on the floor and on the stage (the dark light takes 1 - ambient off its lit pixels).
func set_theme(theme: String) -> void:
	var colour := ambient(theme, mode)
	_floor_material.set_shader_parameter("ambient", Vector3(colour.r, colour.g, colour.b))
	_dark.color = Color(1.0 - colour.r, 1.0 - colour.g, 1.0 - colour.b, 1.0)


# ---------- what carries a light ----------

## IsoView hands over every node that enters the world; the ones that can carry a light are kept, and lit floor
## tiles (Dungeon tags them LIT) get the floor's light.
func track(node: Node) -> void:
	if node is Sprite2D and (node as Sprite2D).light_mask == LIT:
		(node as Sprite2D).material = _floor_material
		return
	var keep := node is Player or node is RemoteAvatar or node is Enemy or node is Projectile or node is Door \
		or node is CampGate or node is ForgeStation or node is ElementAltar
	if node is Pickup:  # loot: only the high rarities glow
		var drop: Dictionary = (node as Pickup).drop
		keep = String(drop.get("kind", "")) == "item" and Items.RARITIES.find(String(drop["item"].get("rarity", ""))) >= 2
	if keep and not _tracked.has(node):
		_tracked.append(node)


func _kind_of(node: Node2D) -> int:
	if node is Player:
		return HERO
	if node is RemoteAvatar:
		return PARTNER
	if node is Enemy:
		var enemy := node as Enemy
		return PARTNER if enemy.pvp_peer != 0 else (BOSS if enemy.boss else ENEMY)
	if node is Projectile:
		return BOLT
	if node is Pickup:
		return LOOT
	if node is Door:
		return DOOR
	return PROP


func _colour_of(node: Node2D, kind: int) -> Color:
	match kind:
		HERO:
			var hex: String = (node as Player)._glow
			if hex != _hero_hex:  # the hero's element changed: parse the new glow once
				_hero_hex = hex
				_hero_colour = _bright(Color(hex)) if Color.html_is_valid(hex) else Color.WHITE
			return _hero_colour
		PARTNER:
			var code: int = (node as RemoteAvatar).glow if node is RemoteAvatar else (node as Enemy).net_glow
			return _partner_colours[clampi(code, 0, _partner_colours.size() - 1)]
		BOSS, ENEMY:
			var enemy := node as Enemy
			return _bright(Elements.color_of(enemy.variant)) if enemy.variant != "" else art_glow(enemy.sprite_id)
		BOLT:
			var element: String = (node as Projectile).hit.get("element", "")
			return _bright(Elements.color_of(element if element != "" else "martial"))
		LOOT:
			return _bright(Items.rarity_color((node as Pickup).drop["item"]))
		DOOR:
			return DOOR_OPEN if (node as Door).open else DOOR_LOCKED
	return art_glow((node as Interactable).sprite_id)


## The flags of a candidate light: fire-like colours flicker; a pale monster (not a boss: its steep pool is small
## already) and a barred door are softer.
static func flags_of(kind: int, colour: Color, locked: bool = false) -> int:
	var pale := colour.s < PALE_SATURATION  # white and grey have hue 0, but are no fire
	var flags := FLICKER if not pale and (colour.h < 0.11 or colour.h > 0.97) else 0
	if (kind == DOOR and locked) or (kind == ENEMY and pale):
		flags |= SOFT
	return flags


## A monster's pool colour: a pale glow is tinted (see PALE_SATURATION); any other light keeps its colour.
static func pool_colour(kind: int, colour: Color) -> Color:
	if (kind == ENEMY or kind == BOSS) and colour.s < PALE_SATURATION:
		return PALE_TINT if colour.s < 0.12 else Color.from_hsv(colour.h, PALE_SATURATION + 0.15, 1.0)
	return colour


## The colour a picture glows in: the mean of its bright, saturated pixels (read once per picture, then cached).
func art_glow(id: String) -> Color:
	if _art_glows.has(id):
		return _art_glows[id]
	var glow := Elements.color_of("martial")
	var texture := AssetDB.get_texture(id)
	var image := texture.get_image() if texture != null else null
	if image != null and not image.is_empty():
		if image.is_compressed():
			image.decompress()
		var sum := Vector3.ZERO
		var count := 0
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a > 0.5 and c.v > 0.55 and c.s > 0.35:
					sum += Vector3(c.r, c.g, c.b)
					count += 1
		if count > 0:
			glow = Color(sum.x / count, sum.y / count, sum.z / count)
	_art_glows[id] = _bright(glow)
	return _art_glows[id]


## A light colour at full value, so the kind's energy alone decides how strong it is.
static func _bright(c: Color) -> Color:
	var top := maxf(maxf(c.r, c.g), maxf(c.b, 0.01))
	return Color(c.r / top, c.g / top, c.b / top, 1.0)


# ---------- choosing ----------

## The rank of a candidate light: kind first (see the enum), then nearness to the hero; `index` rides in the low bits.
static func light_key(kind: int, distance: float, index: int) -> int:
	return (kind << 40) | (clampi(int(distance), 0, 0xFFFFFFFF) << 8) | (index & 0xFF)


## Which candidates get a light: sorts `keys` (light_key, UNUSED for empty slots) in place, most important first,
## drops bolts past the nearest `max_bolts`, packs the winners at the front and returns how many there are (<= cap).
static func choose(keys: PackedInt64Array, cap: int, max_bolts: int = MAX_BOLTS) -> int:
	keys.sort()
	var kept := 0
	var bolts := 0
	for i in keys.size():
		var key := keys[i]
		if key == UNUSED or kept >= cap:
			break
		if key >> 40 == BOLT:
			bolts += 1
			if bolts > max_bolts:
				continue
		keys[kept] = key
		kept += 1
	return kept


# ---------- every frame ----------

func _process(delta: float) -> void:
	_time += delta
	var hero := get_tree().get_first_node_in_group("player") as Node2D
	var centre := hero.global_position if hero != null else Vector2.ZERO
	var screen := get_viewport().get_visible_rect()
	_keys.fill(UNUSED)
	var count := 0
	for i in range(_tracked.size() - 1, -1, -1):
		if not is_instance_valid(_tracked[i]) or not (_tracked[i] as Node).is_inside_tree():
			_tracked.remove_at(i)
			continue
		var node: Node2D = _tracked[i]
		if count >= MAX_CANDIDATES or not node.is_visible_in_tree():
			continue
		var kind := _kind_of(node)
		var pos := node.global_position
		if kind == DOOR:
			pos += DOOR_INWARD.get((node as Door).side, Vector2.ZERO)
		if not screen.grow(RADIUS[kind]).has_point(view.screen_point_of(pos)):
			continue  # off the screen: its pool would not show
		_pos[count] = pos
		_kind[count] = kind
		var colour := _colour_of(node, kind)
		_flags[count] = flags_of(kind, colour, kind == DOOR and not (node as Door).open)
		_colour[count] = pool_colour(kind, colour)
		_phase[count] = float(node.get_instance_id() % 997)
		_keys[count] = light_key(kind, pos.distance_to(centre), count)
		count += 1
	var kept := choose(_keys, MAX_LIGHTS)
	var full := mode == "full"
	for slot in MAX_LIGHTS:
		var on := slot < kept
		_world_lights[slot].enabled = on
		_stage_lights[slot].enabled = on
		if on:
			_place(slot, int(_keys[slot] & 0xFF), full)


## Puts pair `slot` on candidate `c`.
func _place(slot: int, c: int, full: bool) -> void:
	var kind := _kind[c]
	var energy: float = ENERGY[kind]
	if _flags[c] & SOFT:
		energy *= SOFTER
	if not full:
		energy *= SOFT_ENERGY  # soft: dimmer, and still
	elif kind == BOSS:
		energy *= 1.0 + 0.08 * sin(_time * TAU * 0.45 + _phase[c])   # a slow breath
	elif _flags[c] & FLICKER:  # a gentle flicker: under +-8%, under 4 Hz (photosensitivity)
		energy *= 1.0 + 0.05 * sin(_time * TAU * 2.1 + _phase[c]) + 0.03 * sin(_time * TAU * 3.7 + _phase[c] * 1.7)
	var radius: float = RADIUS[kind]
	var texture := _boss_pool if kind == BOSS else _pool
	var floor_light := _world_lights[slot]
	var wall_light := _stage_lights[slot]
	if floor_light.texture != texture:  # set only on a change: the pairs serve every kind
		floor_light.texture = texture
		wall_light.texture = texture
	floor_light.position = _pos[c]
	floor_light.color = _colour[c]
	floor_light.energy = energy
	floor_light.texture_scale = radius / TEXTURE_RADIUS * 0.70710678   # a ground circle of radius r is r * sqrt(2) wide on the screen
	wall_light.position = IsoView.project(_pos[c]) - Vector2(0.0, LIFT)
	wall_light.color = _colour[c]
	wall_light.energy = energy
	wall_light.texture_scale = radius / TEXTURE_RADIUS


## How many lights are on (tests and the performance check).
func lights_on() -> int:
	var on := 0
	for light in _world_lights:
		on += int(light.enabled)
	return on
