class_name SpriteAnim
extends Node
## Plays a sprite-strip animation on a Sprite2D: AssetDB.get_frames(id) gives the frames, this node
## steps through them. A child of the sprite's owner; `playing` false holds the first (idle) frame.
##
##   var anim := SpriteAnim.attach(sprite, "enemy_slime", 5.0)
##   anim.set_art("player_wanderer_side")     # swap strips (keeps the phase if it is the same one)
##   anim.playing = velocity.length() > 8.0   # walk only while moving
##   anim.one_shot(...)                       # hits and bursts: play once, then free the sprite

var sprite: Sprite2D
var frames: Array = []
var fps := 6.0
var playing := true
var loop := true
var free_when_done := false
var art_id := ""

var _time := 0.0


static func attach(target: Sprite2D, id: String, frames_per_second: float = 6.0, owner_node: Node = null) -> SpriteAnim:
	var anim := SpriteAnim.new()
	anim.sprite = target
	anim.fps = frames_per_second
	(owner_node if owner_node else target.get_parent()).add_child(anim)
	anim.set_art(id)
	return anim


## Switches to another strip. Does nothing if it is already showing that art.
func set_art(id: String) -> void:
	if id == art_id:
		return
	art_id = id
	frames = AssetDB.get_frames(id)
	_time = 0.0
	_show(0)


func _process(delta: float) -> void:
	if frames.size() < 2 or not is_instance_valid(sprite):
		return
	if not playing:
		_time = 0.0
		_show(0)
		return
	_time += delta * fps
	var index := int(_time)
	if loop:
		_show(index % frames.size())
	elif index >= frames.size():
		if free_when_done:
			sprite.queue_free()
			queue_free()
		else:
			_show(frames.size() - 1)
	else:
		_show(index)


func _show(index: int) -> void:
	if is_instance_valid(sprite) and not frames.is_empty():
		sprite.texture = frames[clampi(index, 0, frames.size() - 1)]


## A one-shot effect sprite at `pos`: plays `id`'s frames once, tinted, then frees itself.
static func burst(parent: Node, id: String, pos: Vector2, tint: Color, size: float = 1.0, frames_per_second: float = 20.0, additive: bool = true) -> Sprite2D:
	if parent == null or not AssetDB.has_art(id):
		return null
	var s := Sprite2D.new()
	s.modulate = tint
	s.scale = Vector2(size, size)
	s.z_index = 45
	if additive:
		s.material = SkillFx.additive_material()
	parent.add_child(s)
	s.global_position = pos
	var anim := SpriteAnim.attach(s, id, frames_per_second, s)
	anim.loop = false
	anim.free_when_done = true
	return s
