class_name CampBoard
extends Interactable
## The camp's notice board: G opens the leaderboard of the best runs.


func _init() -> void:
	sprite_id = "board"
	prompt = "G: hall of heroes"
	radius = 28.0


func interact() -> void:
	var screen := get_tree().get_first_node_in_group("leaderboard_screen")
	if screen:
		screen.open()
