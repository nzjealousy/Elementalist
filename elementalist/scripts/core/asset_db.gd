extends Node
## Central sprite lookup. Everything asks for art by string ID.
## If res://assets/sprites/<id>.png exists it is used; otherwise a placeholder
## is generated, so real art can be dropped in later with no code changes.

const SPRITE_DIR := "res://assets/sprites/"

# id -> [fill colour, outline colour, size in px]
const PLACEHOLDERS := {
	"player": [Color("4aa3ff"), Color("173a66"), Vector2i(12, 16)],
	"enemy_slime": [Color("6bd66b"), Color("1d5a1d"), Vector2i(12, 10)],
	"tile_floor": [Color("3b3f4a"), Color("33363f"), Vector2i(16, 16)],
	"tile_wall": [Color("6b5a4a"), Color("2f261e"), Vector2i(16, 16)],
	"proj_fire": [Color("ff6a2b"), Color("fff2a0"), Vector2i(6, 6)],
	"proj_water": [Color("3fa7ff"), Color("d6efff"), Vector2i(6, 6)],
	"proj_earth": [Color("5fbf4a"), Color("2d5a22"), Vector2i(6, 6)],
	"proj_air": [Color("d9f2ff"), Color("8fb7cc"), Vector2i(6, 6)],
	"proj_martial": [Color("c9c9d2"), Color("55555f"), Vector2i(6, 4)],
	"proj_mineral": [Color("b5a58a"), Color("5c4f3a"), Vector2i(6, 6)],
	"pickup_gold": [Color("ffd84a"), Color("8a6a10"), Vector2i(5, 5)],
	"pickup_material": [Color("ffffff"), Color("303038"), Vector2i(5, 5)],  # tinted per material
	"pickup_item": [Color("ffffff"), Color("202028"), Vector2i(7, 7)],      # tinted per rarity
	"enemy_bat": [Color("8b5fbf"), Color("2c1a45"), Vector2i(10, 7)],
	"enemy_skeleton": [Color("e8e4d0"), Color("5a5646"), Vector2i(10, 14)],
	"enemy_wisp": [Color("7fe8ff"), Color("2a6a7a"), Vector2i(8, 8)],
	"enemy_brute": [Color("8a8f9c"), Color("33363f"), Vector2i(18, 18)],
	"boss_slime_king": [Color("4fbf4f"), Color("1d5a1d"), Vector2i(32, 26)],
	"boss_colossus": [Color("a1a6b4"), Color("3a3e4a"), Vector2i(30, 32)],
	"door_locked": [Color("8a2e2e"), Color("2f0f0f"), Vector2i(16, 16)],
	"door_open": [Color("15171c"), Color("7fe88a"), Vector2i(16, 16)],
	"door_sealed": [Color("4a4036"), Color("1f1a14"), Vector2i(16, 16)],
	"proj_enemy": [Color("ffffff"), Color("202028"), Vector2i(5, 5)],  # tinted by the shooter
	"chest": [Color("a8742c"), Color("3b2610"), Vector2i(14, 12)],
	"chest_open": [Color("6b4a1c"), Color("3b2610"), Vector2i(14, 12)],
	"forge": [Color("5b5f6e"), Color("e86a2b"), Vector2i(18, 14)],
}

var _cache: Dictionary = {}


func get_texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var path := SPRITE_DIR + id + ".png"
	var tex: Texture2D
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		tex = _make_placeholder(id)
	_cache[id] = tex
	return tex


func _make_placeholder(id: String) -> Texture2D:
	var spec: Array = PLACEHOLDERS.get(id, [Color.MAGENTA, Color.BLACK, Vector2i(16, 16)])
	var fill: Color = spec[0]
	var edge: Color = spec[1]
	var size: Vector2i = spec[2]
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	for x in size.x:
		img.set_pixel(x, 0, edge)
		img.set_pixel(x, size.y - 1, edge)
	for y in size.y:
		img.set_pixel(0, y, edge)
		img.set_pixel(size.x - 1, y, edge)
	return ImageTexture.create_from_image(img)
