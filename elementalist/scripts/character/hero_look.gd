class_name HeroLook
extends RefCounted
## What a hero looks like, worked out from who they are: the class sets the outfit, hair, head gear and
## weapon and its colours; the subclass adds an accent (a sash, shoulder plates, a gem ...), may swap the
## head gear and back item, and recolours; whatever is equipped then replaces the body, head, feet and
## weapon parts. Data lives in res://data/hero_looks.json (shared with tools/art/preview_heroes.py).
##
## A "look" is {"parts": {outfit, hair, head, back, boots, weapon, accent}, "palette": {key: "rrggbb"}};
## HeroComposer turns it into pictures.

const DATA_PATH := "res://data/hero_looks.json"
const PART_KEYS := ["outfit", "hair", "head", "back", "boots", "weapon", "accent"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var json := load(DATA_PATH) as JSON
		_data = json.data if json != null and json.data is Dictionary else {}
	return _data


## The look of a class (and subclass) with no equipment: for cards, menus and previews.
static func for_class(class_id: String, subclass_id: String = "", skin: int = 0, hair_color: int = 1) -> Dictionary:
	var d := data()
	var base: Dictionary = d["classes"].get(class_id, d["classes"]["wanderer"])
	var parts := {}
	for key in PART_KEYS:
		parts[key] = String(base.get(key, ""))
	var palette: Dictionary = base["palette"].duplicate()
	if subclass_id != "" and d["subclasses"].has(subclass_id):
		var sub: Dictionary = d["subclasses"][subclass_id]
		parts["accent"] = String(sub.get("accent", ""))
		for key in ["head", "back"]:
			if sub.has(key):
				parts[key] = String(sub[key])
		palette.merge(sub.get("palette", {}), true)
	_apply_materials(palette, "worn")
	palette["skin"] = String(d["skin_tones"][posmod(skin, d["skin_tones"].size())])
	palette["hair"] = String(d["hair_colors"][posmod(hair_color, d["hair_colors"].size())])
	return {"parts": parts, "palette": palette}


## The look of a character: class and subclass, then each equipped item over it.
static func for_character(character: CharacterData) -> Dictionary:
	var look := for_class(character.class_id, character.subclass_id, character.look_skin, character.look_hair)
	var d := data()
	var parts: Dictionary = look["parts"]
	var palette: Dictionary = look["palette"]
	var equipped: Dictionary = character.inventory.equipped
	var body := _base_of(equipped, "body")
	if d["armor"].has(body):
		parts["outfit"] = String(d["armor"][body]["outfit"])
		palette.merge(d["armor"][body]["palette"], true)
	var head := _base_of(equipped, "head")
	if d["helms"].has(head):
		parts["head"] = String(d["helms"][head]["head"])
		palette.merge(d["helms"][head]["palette"], true)
	var feet := _base_of(equipped, "feet")
	if d["boots"].has(feet):
		parts["boots"] = String(d["boots"][feet]["boots"])
		palette.merge(d["boots"][feet]["palette"], true)
	var weapon_item: Variant = equipped.get("weapon", {})
	if weapon_item is Dictionary and not weapon_item.is_empty():
		parts["weapon"] = Items.weapon_of(weapon_item)
		_apply_materials(palette, String(weapon_item["base"]).split("_")[0])
		var enchant := String(weapon_item.get("enchant", ""))
		if enchant != "":
			palette["gem"] = Elements.color_of(enchant).to_html(false)
		elif String(weapon_item.get("rarity", "common")) != "common":
			palette["gem"] = Items.rarity_color(weapon_item).to_html(false)
	else:
		parts["weapon"] = ""
	return look


static func _base_of(equipped: Dictionary, slot: String) -> String:
	var item: Variant = equipped.get(slot, {})
	return String(item.get("base", "")) if item is Dictionary else ""


static func _apply_materials(palette: Dictionary, prefix: String) -> void:
	var materials: Dictionary = data()["weapons"]
	var material: Dictionary = materials.get(prefix, materials["worn"])
	palette["metal"] = String(material["metal"])
	palette["wood"] = String(material["wood"])


## The look with its glow set: the one accent colour (a Color) that the eyes, gems, glints and rim light take (see HeroComposer).
static func with_glow(look: Dictionary, glow: Color) -> Dictionary:
	var out: Dictionary = look.duplicate(true)
	out["palette"]["glow"] = glow.to_html(false)
	return out


## A main colour for a class, for borders and tints: its outfit colour.
static func class_color(class_id: String) -> Color:
	var d := data()
	var base: Dictionary = d["classes"].get(class_id, d["classes"]["wanderer"])
	return Color(String(base["palette"]["outfit"]))


## The trim colour (gold, steel ...) that goes with it.
static func class_trim(class_id: String) -> Color:
	var d := data()
	var base: Dictionary = d["classes"].get(class_id, d["classes"]["wanderer"])
	return Color(String(base["palette"]["trim"]))


## A picture for an equipped item: its hero part alone (a helm, a robe, boots, a sword ...). Rings and amulets have
## no part and get the generic gem picture.
static func slot_icon(item: Dictionary) -> Texture2D:
	var d := data()
	var slot := String(Items.BASES[item["base"]]["slot"])
	var base := String(item["base"])
	var painted := "res://assets/sprites/item_%s.png" % base   # a drawn icon (tools/art/gen_items.py) wins over a crop of the hero part
	if ResourceLoader.exists(painted):
		return load(painted)
	var palette: Dictionary = d["classes"]["wanderer"]["palette"].duplicate()
	palette["skin"] = String(d["skin_tones"][0])
	palette["hair"] = String(d["hair_colors"][1])
	_apply_materials(palette, "worn")
	var layers: Array = []
	match slot:
		"weapon":
			layers = ["weapon_" + Items.weapon_of(item)]
			_apply_materials(palette, base.split("_")[0])
			var enchant := String(item.get("enchant", ""))
			palette["gem"] = (Elements.color_of(enchant) if enchant != "" else Items.rarity_color(item)).to_html(false)
		"head":
			if d["helms"].has(base):
				layers = ["head_" + String(d["helms"][base]["head"])]
				palette.merge(d["helms"][base]["palette"], true)
		"body":
			if d["armor"].has(base):
				layers = ["outfit_" + String(d["armor"][base]["outfit"])]
				palette.merge(d["armor"][base]["palette"], true)
		"feet":
			if d["boots"].has(base):
				layers = ["boots_" + String(d["boots"][base]["boots"])]
				palette.merge(d["boots"][base]["palette"], true)
	if layers.is_empty():
		return AssetDB.get_texture("pickup_item")
	return HeroComposer.icon(layers, palette)
