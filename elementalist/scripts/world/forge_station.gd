class_name ForgeStation
extends Interactable
## The crafting station: G opens the ForgeScreen (craft, upgrade, enchant, salvage).


func _init() -> void:
	sprite_id = "forge"
	prompt = "G: forge"
	radius = 28.0


func interact() -> void:
	var screen := get_tree().get_first_node_in_group("forge_screen")
	if screen:
		screen.open()
