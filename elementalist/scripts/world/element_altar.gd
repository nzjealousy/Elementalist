class_name ElementAltar
extends Interactable
## The altar in the training grounds: G opens the AltarScreen, which compares the elements.


func _init() -> void:
	sprite_id = "altar"
	prompt = "G: altar of elements"
	radius = 30.0


func interact() -> void:
	var screen := get_tree().get_first_node_in_group("altar_screen")
	if screen:
		screen.open()
