class_name CampGate
extends Interactable
## The camp's way into the dungeons: G opens the DungeonSelect cards.


func _init() -> void:
	sprite_id = "door_open"
	prompt = "G: the dungeons"
	radius = 30.0


func interact() -> void:
	var screen := get_tree().get_first_node_in_group("dungeon_select")
	if screen:
		screen.open()
