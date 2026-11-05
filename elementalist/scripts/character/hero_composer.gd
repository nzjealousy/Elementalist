class_name HeroComposer
extends RefCounted
## Paints a HeroLook into pictures. The part pictures (assets/sprites/hero/<part>_<variant>_<facing>.png, made by
## tools/art/gen_heroes.py) store a REGION and a SHADE per pixel instead of a colour; here the regions are stacked and every pixel
## is coloured from the look's palette in the Noir Silhouette way (docs/SPRITE_STYLES.md): near-black desaturated bodies in three
## hard tones, a nearly black outline, and everything that is magic in ONE accent colour, the look's "glow" (palette["glow"], set from
## the element the hero has selected): the eyes, the gems, the glints, and a hard rim light on the upper-left edge.
## tools/art/noir.py is the Python twin of _color_of; the self-test compares them.
##
## A part strip holds FRAME_COUNT poses (tools/art/gen_heroes.py POSES) in a cell of size() (34 x 32; the figure is the middle CELL_WIDTH
## columns, the rest is room for swings): CLIPS names the runs of frames (walk, idle, attack, dodge, swirl, cast, stun, hurt). The parts
## are drawn on a 40 x 38 grid and baked 15% smaller (tools/art/shrink.py), so a hero is drawn at scale 1, every pixel a real pixel.
##
## compose(look) -> {"down": [Texture2D x FRAME_COUNT], "up": [...], "side": [...]}, cached by look. register(look) makes the frames
## available lazily from AssetDB as "hero:<n>:<facing>" (composed the first time a facing is used) so sprites can play them with SpriteAnim.

const FACINGS := ["down", "up", "side"]
const FRAME_COUNT := 21
const CELL_WIDTH := 20
const CELL_MARGIN := 7   # columns either side of the figure's own cell
## First frame and length of each run of poses in a strip.
const CLIPS := {
	"walk": Vector2i(0, 4), "idle": Vector2i(4, 2), "attack": Vector2i(6, 3), "dodge": Vector2i(9, 2), "swirl": Vector2i(11, 4),
	"cast": Vector2i(15, 3), "stun": Vector2i(18, 2), "hurt": Vector2i(20, 1),
}
const REGION_KEYS := {1: "skin", 2: "hair", 3: "outfit", 4: "trim", 5: "pants", 6: "boots", 7: "head", 8: "headtrim",
	9: "cape", 10: "accent", 11: "metal", 12: "wood", 13: "gem"}
const DEFAULT_GLOW := "9cf0d8"
const NIGHT := Color8(16, 14, 34)

static var _parts: Dictionary = {}      # "<part>_<variant>_<facing>" -> PackedByteArray (RGBA8) of the strip
static var _composed: Dictionary = {}   # look key -> {facing: [Texture2D]}
static var _portraits: Dictionary = {}  # look key + facing + frame -> Texture2D (the figure's own cell)
static var _ids: Dictionary = {}        # look key -> id number for AssetDB


## One whole cell (the picture a strip frame has).
static func size() -> Vector2i:
	var canvas: Array = HeroLook.data()["canvas"]
	return Vector2i(int(canvas[0]), int(canvas[1]))


## The size of a portrait: the figure's own cell, without the room for swings.
static func portrait_size() -> Vector2i:
	return Vector2i(CELL_WIDTH, size().y)


## A stable text key for a look (equal looks share their pictures).
static func key_of(look: Dictionary) -> String:
	return JSON.stringify(look, "", true)


## Every frame of every facing (slow: use register() and AssetDB to play, portrait() or frame_image() for one frame).
static func compose(look: Dictionary) -> Dictionary:
	var key := key_of(look)
	if _composed.has(key):
		return _composed[key]
	var out := {}
	for facing in FACINGS:
		out[facing] = compose_facing(look, facing)
	_composed[key] = out
	return out


static func compose_facing(look: Dictionary, facing: String) -> Array:
	var frames: Array = []
	for frame in FRAME_COUNT:
		frames.append(ImageTexture.create_from_image(frame_image(look, facing, frame)))
	return frames


## Makes the look's frames available from AssetDB as "<prefix>:<facing>"; a facing is composed the first time it is asked for.
## Returns the id prefix ("hero:3") to which ":<facing>" is added.
static func register(look: Dictionary) -> String:
	var key := key_of(look)
	if _ids.has(key):
		return String(_ids[key])
	var prefix := "hero:%d" % _ids.size()
	for facing in FACINGS:
		var which: String = facing
		AssetDB.register_lazy("%s:%s" % [prefix, facing], func(): return compose_facing(look, which))
	_ids[key] = prefix
	return prefix


## One frame of the figure's own cell (the first idle pose by default), for menus: cached.
static func portrait(look: Dictionary, facing: String = "down", frame: int = 4) -> Texture2D:
	var key := "%s|%s|%d" % [key_of(look), facing, frame]
	if _portraits.has(key):
		return _portraits[key]
	var image := frame_image(look, facing, frame).get_region(Rect2i(CELL_MARGIN, 0, CELL_WIDTH, size().y))
	var texture := ImageTexture.create_from_image(image)
	_portraits[key] = texture
	return texture


## A small picture of some parts alone (an equipped helm, a sword ...), cropped to its shape. `layers` are part names
## ("head_helm", "weapon_sword"); `palette` colours them (HeroLook.slot_icon uses it when a gear base has no painted icon).
static func icon(layers: Array, palette: Dictionary) -> Texture2D:
	var key := "icon:%s:%s" % [",".join(layers), JSON.stringify(palette, "", true)]
	if _composed.has(key):
		return _composed[key]
	var canvas := size()
	var region := PackedInt32Array()
	var shade := PackedInt32Array()
	region.resize(canvas.x * canvas.y)
	shade.resize(canvas.x * canvas.y)
	var colors := _palette_colors(palette)
	for part in layers:
		var bytes := _part_bytes(part, "down")
		if bytes.is_empty():
			continue
		for y in canvas.y:
			for x in canvas.x:
				var at := (y * canvas.x * FRAME_COUNT + (int(CLIPS["idle"].x) * canvas.x + x)) * 4
				if bytes[at + 3] >= 128:
					region[y * canvas.x + x] = roundi(bytes[at] / 16.0)
					shade[y * canvas.x + x] = roundi(bytes[at + 1] / 60.0)
	var low := Vector2i(canvas.x, canvas.y)
	var high := Vector2i(-1, -1)
	for y in canvas.y:
		for x in canvas.x:
			if region[y * canvas.x + x] != 0:
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	if high.x < 0:
		return AssetDB.get_texture("pickup_item")
	var width := high.x - low.x + 3
	var height := high.y - low.y + 3
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var r := region[y * canvas.x + x]
			if r != 0:
				image.set_pixel(x - low.x + 1, y - low.y + 1, _color_of(r, shade[y * canvas.x + x], colors))
	for y in height:  # the same outline pass as a whole hero
		for x in width:
			if image.get_pixel(x, y).a > 0.0:
				continue
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + step.x
				var ny: int = y + step.y
				if nx >= 0 and ny >= 0 and nx < width and ny < height and image.get_pixel(nx, ny).a > 0.0:
					var neighbour := image.get_pixel(nx, ny)
					image.set_pixel(x, y, Color(neighbour.r * 0.25 + 6.0 / 255.0, neighbour.g * 0.25 + 5.0 / 255.0, neighbour.b * 0.25 + 16.0 / 255.0))
					break
	var texture := ImageTexture.create_from_image(image)
	_composed[key] = texture
	return texture


static func _layers(parts: Dictionary, facing: String) -> Array:
	var out: Array = []
	if parts["back"] != "":
		out.append("back_" + parts["back"])
	if facing == "up" and parts["weapon"] != "":
		out.append("weapon_" + parts["weapon"])  # behind the body
	out.append("base_body")
	out.append("boots_" + String(parts["boots"] if parts["boots"] != "" else "shoes"))
	if parts["outfit"] != "":
		out.append("outfit_" + parts["outfit"])
	if parts["accent"] != "":
		out.append("accent_" + parts["accent"])
	if parts["hair"] != "":
		out.append("hair_" + parts["hair"])
	if parts["head"] != "":
		out.append("head_" + parts["head"])
	if facing != "up" and parts["weapon"] != "":
		out.append("weapon_" + parts["weapon"])
	return out


static func _part_bytes(part: String, facing: String) -> PackedByteArray:
	var key := "%s_%s" % [part, facing]
	if not _parts.has(key):
		var path := "res://assets/sprites/hero/%s.png" % key
		var bytes := PackedByteArray()
		if ResourceLoader.exists(path):
			var image := (load(path) as Texture2D).get_image()
			image.convert(Image.FORMAT_RGBA8)
			bytes = image.get_data()
		_parts[key] = bytes
	return _parts[key]


## One pose of one facing as an image of a whole cell.
static func frame_image(look: Dictionary, facing: String, frame: int) -> Image:
	var canvas := size()
	var w := canvas.x
	var h := canvas.y
	var strip_w := w * FRAME_COUNT
	var region := PackedInt32Array()
	var shade := PackedInt32Array()
	region.resize(w * h)
	shade.resize(w * h)
	for part in _layers(look["parts"], facing):
		var bytes := _part_bytes(part, facing)
		if bytes.is_empty():
			continue
		for y in h:
			for x in w:
				var at := (y * strip_w + frame * w + x) * 4
				if bytes[at + 3] < 128:
					continue
				region[y * w + x] = roundi(bytes[at] / 16.0)
				shade[y * w + x] = roundi(bytes[at + 1] / 60.0)
	var palette := _palette_colors(look["palette"])
	var glow: Color = palette.get("glow", Color(DEFAULT_GLOW))
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var r := region[y * w + x]
			if r != 0:
				image.set_pixel(x, y, _color_of(r, shade[y * w + x], palette))
	for y in h:  # the rim: lit pixels on the figure's upper-left edge take the glow (eyes keep their own light)
		for x in w:
			var here := region[y * w + x]
			if here == 0 or here == 14 or shade[y * w + x] < 2:
				continue
			if (x == 0 or region[y * w + x - 1] == 0) or (y == 0 or region[(y - 1) * w + x] == 0):
				image.set_pixel(x, y, image.get_pixel(x, y).lerp(glow, 0.8))
	for y in h:  # the outline: empty cells next to the figure take a nearly black shade of its colour
		for x in w:
			if region[y * w + x] != 0:
				continue
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + step.x
				var ny: int = y + step.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and region[ny * w + nx] != 0:
					image.set_pixel(x, y, _color_of(region[ny * w + nx], 0, palette))
					break
	return image


static func _palette_colors(palette: Dictionary) -> Dictionary:
	var out := {}
	for key in palette:
		out[key] = Color(String(palette[key]))
	return out


## A palette colour as it appears in the dark: half the saturation, 46% of the light, a breath of night blue.
static func _noir_base(c: Color) -> Color:
	var luma := 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
	var r := (luma + (c.r - luma) * 0.5) * 0.46
	var g := (luma + (c.g - luma) * 0.5) * 0.46
	var b := (luma + (c.b - luma) * 0.5) * 0.46
	return Color(r * 0.88 + NIGHT.r * 0.12, g * 0.88 + NIGHT.g * 0.12, b * 0.88 + NIGHT.b * 0.12)


static func _scaled(c: Color, k: float, add: float = 0.0) -> Color:
	return Color(minf(c.r * k + add, 1.0), minf(c.g * k + add, 1.0), minf(c.b * k + add, 1.0))


static func _color_of(region: int, shade: int, palette: Dictionary) -> Color:
	var glow: Color = palette.get("glow", Color(DEFAULT_GLOW))
	if region == 14:  # eyes: the glow, hot
		var eye := glow.lerp(Color(1.0, 0.98, 1.0), 0.35)
		return eye if shade > 0 else Color(eye.r * 0.3 + 4.0 / 255.0, eye.g * 0.3 + 4.0 / 255.0, eye.b * 0.3 + 4.0 / 255.0)
	if region == 13:  # gems: the glow itself
		var k: float = [0.25, 0.55, 0.9, 1.1, 1.3][clampi(shade, 0, 4)]
		return _scaled(glow, k)
	var rgb: Color
	if region == 15:
		rgb = Color8(150, 146, 176)
	elif region == 11:
		rgb = _scaled(_noir_base(palette.get("metal", Color("9a9aa4"))), 1.35)
	else:
		rgb = _noir_base(palette.get(REGION_KEYS.get(region, "outfit"), Color.MAGENTA))
	match shade:
		0:  # the outline: nearly black, tinted by what it borders
			return Color(rgb.r * 0.25 + 6.0 / 255.0, rgb.g * 0.25 + 5.0 / 255.0, rgb.b * 0.25 + 16.0 / 255.0)
		1:
			return Color(rgb.r * 0.496 + 8.0 / 255.0 * 0.2, rgb.g * 0.496 + 6.0 / 255.0 * 0.2, rgb.b * 0.496 + 22.0 / 255.0 * 0.2)
		3:
			return _scaled(rgb, 1.3, 5.0 / 255.0)
		4:  # a glint takes some of the glow
			var lit := _scaled(rgb, 1.45, 8.0 / 255.0)
			return lit.lerp(glow, 0.5)
	return rgb
