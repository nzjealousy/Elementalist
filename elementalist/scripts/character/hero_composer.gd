class_name HeroComposer
extends RefCounted
## Paints a HeroLook into pictures. The part pictures (assets/sprites/hero/<part>_<variant>_<facing>.png, made by
## tools/art/gen_heroes.py) store a REGION and a SHADE per pixel instead of a colour; here the regions
## are stacked, an outline is traced around the whole figure and every pixel is coloured from the
## look's palette through a ramp (pale highlights, cold shadows, a rim of moonlight on the upper-left edge and one ink
## outline round the figure), so one set of shapes serves every class, subclass and piece of gear.
##
## compose(look) -> {"down": [Texture2D x4], "up": [...], "side": [...]}, cached by look. register(look) also
## puts the frames in AssetDB as "hero:<n>:<facing>" so sprites can play them with SpriteAnim.

const FACINGS := ["down", "up", "side"]
const FRAME_COUNT := 4
const REGION_KEYS := {1: "skin", 2: "hair", 3: "outfit", 4: "trim", 5: "pants", 6: "boots", 7: "head", 8: "headtrim",
	9: "cape", 10: "accent", 11: "metal", 12: "wood", 13: "gem"}
const EYE_COLOR := Color(0.118, 0.086, 0.173)
const OUTLINE := Color("0a0618")   # Moonlit Glyphwork: one ink line round the whole figure
const RIM := Color("d8d0ff")       # moonlight on the lit (upper left) edge
const RIM_MIX := 0.4
const WHITE_COLOR := Color(0.988, 0.973, 0.941)

static var _parts: Dictionary = {}      # "<part>_<variant>_<facing>" -> PackedByteArray (RGBA8) of the strip
static var _composed: Dictionary = {}   # look key -> {facing: [Texture2D]}
static var _ids: Dictionary = {}        # look key -> id number for AssetDB


static func size() -> Vector2i:
	var canvas: Array = HeroLook.data()["canvas"]
	return Vector2i(int(canvas[0]), int(canvas[1]))


## A stable text key for a look (equal looks share their pictures).
static func key_of(look: Dictionary) -> String:
	return JSON.stringify(look, "", true)


static func compose(look: Dictionary) -> Dictionary:
	var key := key_of(look)
	if _composed.has(key):
		return _composed[key]
	var out := {}
	for facing in FACINGS:
		var frames: Array = []
		for frame in FRAME_COUNT:
			frames.append(ImageTexture.create_from_image(_frame_image(look, facing, frame)))
		out[facing] = frames
	_composed[key] = out
	return out


## Composes the look and registers its frames with AssetDB; returns the id prefix ("hero:3") to which
## ":<facing>" is added.
static func register(look: Dictionary) -> String:
	var key := key_of(look)
	if _ids.has(key):
		return String(_ids[key])
	var frames := compose(look)
	var prefix := "hero:%d" % _ids.size()
	for facing in FACINGS:
		AssetDB.register_frames("%s:%s" % [prefix, facing], frames[facing])
	_ids[key] = prefix
	return prefix


## The idle picture facing the viewer, for menus.
static func portrait(look: Dictionary, facing: String = "down") -> Texture2D:
	return compose(look)[facing][0]


## A small picture of some parts alone (an equipped helm, a sword ...), cropped to its shape. `layers` are part names
## ("head_helm", "weapon_sword"); `palette` colours them (HeroLook.slot_icon builds one).
static func icon(layers: Array, palette: Dictionary) -> Texture2D:
	var key := "icon:%s:%s" % [",".join(layers), JSON.stringify(palette, "", true)]
	if _composed.has(key):
		return _composed[key]
	var canvas := size()
	var region := PackedInt32Array()
	var shade := PackedInt32Array()
	region.resize(canvas.x * canvas.y)
	shade.resize(canvas.x * canvas.y)
	for part in layers:
		var bytes := _part_bytes(part, "down")
		if bytes.is_empty():
			continue
		for y in canvas.y:
			for x in canvas.x:
				var at := (y * canvas.x * FRAME_COUNT + x) * 4
				if bytes[at + 3] >= 128:
					region[y * canvas.x + x] = roundi(bytes[at] / 16.0)
					shade[y * canvas.x + x] = roundi(bytes[at + 1] / 60.0)
	var colors := _palette_colors(palette)
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
					image.set_pixel(x, y, OUTLINE)
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


static func _frame_image(look: Dictionary, facing: String, frame: int) -> Image:
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
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var r := region[y * w + x]
			if r != 0:
				image.set_pixel(x, y, _color_of(r, shade[y * w + x], palette))
	for y in h:  # the rim: lit pixels on the figure's upper-left edge pick up moonlight
		for x in w:
			var here := region[y * w + x]
			if here == 0 or here == 14 or shade[y * w + x] < 2:
				continue
			if (x == 0 or region[y * w + x - 1] == 0) or (y == 0 or region[(y - 1) * w + x] == 0):
				image.set_pixel(x, y, image.get_pixel(x, y).lerp(RIM, RIM_MIX))
	for y in h:  # the outline: empty cells next to the figure become ink
		for x in w:
			if region[y * w + x] != 0:
				continue
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + step.x
				var ny: int = y + step.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and region[ny * w + nx] != 0:
					image.set_pixel(x, y, OUTLINE)
					break
	return image


static func _palette_colors(palette: Dictionary) -> Dictionary:
	var out := {}
	for key in palette:
		out[key] = Color(String(palette[key]))
	return out


static func _color_of(region: int, shade: int, palette: Dictionary) -> Color:
	if region == 14:
		return EYE_COLOR
	var base: Color = WHITE_COLOR if region == 15 else palette.get(REGION_KEYS.get(region, "outfit"), Color.MAGENTA)
	var ramp: Dictionary = HeroLook.data()["ramp"]
	match shade:
		0:
			var add: Array = ramp["outline_add"]
			var k := float(ramp["outline_mul"])
			return Color(minf(base.r * k + float(add[0]) / 255.0, 1.0), minf(base.g * k + float(add[1]) / 255.0, 1.0), minf(base.b * k + float(add[2]) / 255.0, 1.0))
		4:
			var hc: Array = ramp["highlight_color"]
			return base.lerp(Color(float(hc[0]) / 255.0, float(hc[1]) / 255.0, float(hc[2]) / 255.0), float(ramp["highlight_mix"]))
		3:
			var m := float(ramp["light_mul"])
			return Color(minf(base.r * m, 1.0), minf(base.g * m, 1.0), minf(base.b * m, 1.0))
		1:
			var sc: Array = ramp["shadow_color"]
			var dm := float(ramp["dark_mul"])
			var dark := Color(base.r * dm, base.g * dm, base.b * dm)
			return dark.lerp(Color(float(sc[0]) / 255.0, float(sc[1]) / 255.0, float(sc[2]) / 255.0), float(ramp["shadow_mix"]))
	return base
