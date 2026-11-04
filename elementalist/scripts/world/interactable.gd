class_name Interactable
extends Node2D
## Something in the world the player can use with the interact key (G) when standing close:
## shows a small prompt while in range. Subclasses override interact() and can_interact().

@export var sprite_id := "chest"
@export var prompt := "G: use"
@export var radius := 24.0

var sprite: Sprite2D
var _label: Label


func _ready() -> void:
	add_to_group("interactables")
	sprite = Sprite2D.new()
	sprite.texture = AssetDB.get_texture(sprite_id)
	add_child(sprite)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 6)
	_label.add_theme_color_override("font_color", Color("ffd84a"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	_label.position = Vector2(-24, -sprite.texture.get_size().y * 0.5 - 12)
	_label.z_index = 90
	_label.visible = false
	add_child(_label)


func is_near() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	return player != null and player.global_position.distance_to(global_position) <= radius


func _process(_delta: float) -> void:
	_label.text = prompt
	_label.visible = can_interact() and is_near()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and can_interact() and is_near():
		interact()
		get_viewport().set_input_as_handled()


## Whether the object can be used right now (a chest only once).
func can_interact() -> bool:
	return true


func interact() -> void:
	pass
