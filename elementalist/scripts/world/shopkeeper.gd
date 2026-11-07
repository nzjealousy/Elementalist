class_name Shopkeeper
extends Interactable
## The camp merchant: G opens the ShopScreen (elemental gems and legendary gear for gold).


func _init() -> void:
	sprite_id = "shopkeeper"
	prompt = "G: shop"
	radius = 30.0


func interact() -> void:
	var screen := get_tree().get_first_node_in_group("shop_screen")
	if screen:
		screen.open()
