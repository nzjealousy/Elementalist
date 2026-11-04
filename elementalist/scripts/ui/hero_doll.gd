class_name HeroDoll
extends RefCounted
## Pictures of a hero for menus: the composed look (HeroLook / HeroComposer) shown big and crisp.

## A TextureRect showing `look` facing `facing`, scaled by a whole number so the pixels stay square.
static func make(look: Dictionary, scale: int = 2, facing: String = "down") -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = HeroComposer.portrait(look, facing)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	var size := HeroComposer.size()
	rect.custom_minimum_size = Vector2(size.x * scale, size.y * scale)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func of_character(character: CharacterData, scale: int = 2, facing: String = "down") -> TextureRect:
	return make(HeroLook.for_character(character), scale, facing)


static func of_class(class_id: String, subclass_id: String = "", scale: int = 2, character: CharacterData = null) -> TextureRect:
	var skin := character.look_skin if character else 0
	var hair := character.look_hair if character else 1
	return make(HeroLook.for_class(class_id, subclass_id, skin, hair), scale)
