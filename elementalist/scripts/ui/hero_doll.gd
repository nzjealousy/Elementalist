class_name HeroDoll
extends RefCounted
## Pictures of a hero for menus: the composed look (HeroLook / HeroComposer) shown big and crisp, breathing (the idle poses) and, while
## the card or screen it sits on is "hot" (hovered or selected), casting. The picture is the figure's own cell, not the room for swings.

const IDLE_FPS := 3.0
const CAST_FPS := 7.0


## A TextureRect showing `look` facing `facing`, scaled by a whole number so the pixels stay square.
static func make(look: Dictionary, scale: int = 2, facing: String = "down") -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = HeroComposer.portrait(look, facing)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	var size := HeroComposer.portrait_size()
	rect.custom_minimum_size = Vector2(size.x * scale, size.y * scale)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var anim := DollAnim.new()
	anim.name = "DollAnim"
	anim.rect = rect
	anim.look = look
	anim.facing = facing
	rect.add_child(anim)
	return rect


## Makes a doll cast (true) or go back to breathing (false).
static func set_hot(rect: TextureRect, hot: bool) -> void:
	var anim := rect.get_node_or_null("DollAnim") as DollAnim
	if anim != null:
		anim.hot = hot


static func of_character(character: CharacterData, scale: int = 2, facing: String = "down") -> TextureRect:
	return make(HeroLook.for_character(character), scale, facing)


static func of_class(class_id: String, subclass_id: String = "", scale: int = 2, character: CharacterData = null) -> TextureRect:
	var skin := character.look_skin if character else 0
	var hair := character.look_hair if character else 1
	return make(HeroLook.for_class(class_id, subclass_id, skin, hair), scale)


## Steps a doll through its idle poses, or its cast poses while hot.
class DollAnim extends Node:
	var rect: TextureRect
	var look: Dictionary = {}
	var facing := "down"
	var hot := false
	var _time := 0.0

	func _process(delta: float) -> void:
		if rect == null or not is_instance_valid(rect) or not rect.is_visible_in_tree():
			return
		_time += delta
		var run: Vector2i = HeroComposer.CLIPS["cast" if hot else "idle"]
		var fps := HeroDoll.CAST_FPS if hot else HeroDoll.IDLE_FPS
		rect.texture = HeroComposer.portrait(look, facing, run.x + int(_time * fps) % run.y)
