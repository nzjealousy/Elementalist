class_name Lighting
extends Node
## The light of the isometric view: each place is dimmed to its own ambient colour and soft round pools of light
## follow the hero, partners, their bolts, the monsters on screen, the boss, the camp's props and rare loot.
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
const FLOOR_SHADER := """
shader_type canvas_item;
uniform vec3 ambient = vec3(1.0);
uniform float tint = 0.15;
void fragment() {
	COLOR.rgb *= ambient;
}
void light() {
	LIGHT = vec4(LIGHT_COLOR.rgb * (COLOR.rgb / ambient + vec3(tint)) * LIGHT_ENERGY, LIGHT_COLOR.a);
}
"""

## Light kinds, in priority order (a lower kind always wins a pair first).
enum {HERO, PARTNER, BOSS, BOLT, ENEMY, PROP, LOOT}
const RADIUS := [64.0, 56.0, 84.0, 26.0, 26.0, 60.0, 14.0]   # by kind: the pool's half-width on the screen (px)
const ENERGY := [1.1, 0.9, 0.7, 1.2, 0.8, 0.8, 0.8]          # by kind, tuned by eye on the dark floors (a boss's pool is wide, so dimmer)

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
var _fire := PackedByteArray()
var _time := 0.0
var _hero_hex := ""
var _hero_colour := Color.WHITE
var _partner_colours := PackedColorArray()   # by glow code (Player.glow_code)
var _art_glows: Dictionary = {}              # picture id -> the colour its art glows in
var _floor_material: ShaderMaterial


func _ready() -> void:
	mode = String(Settings.get_value("lighting"))
	var shader := Shader.new()
	shader.code = FLOOR_SHADER
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = shader
	var texture := pool_texture()
	for i in MAX_LIGHTS:
		_world_lights.append(_light(self, 0, texture))
		_stage_lights.append(_light(stage, stage.layer, texture))
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
	_fire.resize(MAX_CANDIDATES)
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


## The one soft round light every pool shares: full in the middle, fading smoothly to nothing at the rim.
static func pool_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 0.85, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.0)])
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
	var keep := node is Player or node is RemoteAvatar or node is Enemy or node is Projectile \
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
	return art_glow((node as Interactable).sprite_id)


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
		if not screen.grow(RADIUS[kind]).has_point(view.screen_point_of(pos)):
			continue  # off the screen: its pool would not show
		_pos[count] = pos
		_kind[count] = kind
		_colour[count] = _colour_of(node, kind)
		_phase[count] = float(node.get_instance_id() % 997)
		_fire[count] = 1 if _colour[count].h < 0.11 or _colour[count].h > 0.97 else 0   # fire-like lights flicker
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
	if not full:
		energy *= SOFT_ENERGY  # soft: dimmer, and still
	elif kind == BOSS:
		energy *= 1.0 + 0.08 * sin(_time * TAU * 0.45 + _phase[c])   # a slow breath
	elif _fire[c] == 1:  # a gentle flicker: under +-8%, under 4 Hz (photosensitivity)
		energy *= 1.0 + 0.05 * sin(_time * TAU * 2.1 + _phase[c]) + 0.03 * sin(_time * TAU * 3.7 + _phase[c] * 1.7)
	var radius: float = RADIUS[kind]
	var floor_light := _world_lights[slot]
	floor_light.position = _pos[c]
	floor_light.color = _colour[c]
	floor_light.energy = energy
	floor_light.texture_scale = radius / TEXTURE_RADIUS * 0.70710678   # a ground circle of radius r is r * sqrt(2) wide on the screen
	var wall_light := _stage_lights[slot]
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
