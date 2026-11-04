class_name Door
extends StaticBody2D
## A room's exit: a solid, red-barred gap in the wall until the room is cleared, then an open
## doorway. Walking into the open doorway sends the player on (see Dungeon).

const TILE := 16

var open := false
var side := "north"
var size_px := Vector2(32, 16)
var _sprites: Array[Sprite2D] = []
var _shape: CollisionShape2D


## `rect` is the doorway in world pixels.
func setup(rect: Rect2, door_side: String) -> void:
	position = rect.position + rect.size * 0.5
	size_px = rect.size
	side = door_side


func _ready() -> void:
	_shape = CollisionShape2D.new()
	_shape.name = "CollisionShape2D"
	var rectangle := RectangleShape2D.new()
	rectangle.size = size_px
	_shape.shape = rectangle
	add_child(_shape)
	var cells := int(maxf(size_px.x, size_px.y) / TILE)
	var along := Vector2.RIGHT if size_px.x > size_px.y else Vector2.DOWN
	for i in cells:
		var sprite := Sprite2D.new()
		sprite.texture = AssetDB.get_texture("door_locked")
		sprite.position = along * (float(i) - (cells - 1) * 0.5) * TILE
		sprite.z_index = -9
		add_child(sprite)
		_sprites.append(sprite)


## The room is cleared: the bars drop and the way is open.
func unlock() -> void:
	if open:
		return
	open = true
	_shape.set_deferred("disabled", true)
	for sprite in _sprites:
		sprite.texture = AssetDB.get_texture("door_open")
	SkillFx.ring(get_parent(), global_position, 16.0, Color("7fe88a"), 0.5, 1.5)
	Sfx.play("door_open", &"SFX", -4.0)


## True when `point` (e.g. the player's position) is inside the doorway.
func contains(point: Vector2) -> bool:
	return Rect2(global_position - size_px * 0.5, size_px).has_point(point)
