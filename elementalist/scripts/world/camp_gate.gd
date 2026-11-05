class_name CampGate
extends Interactable
## The camp's way into the dungeons: G opens the DungeonSelect cards.


func _init() -> void:
	sprite_id = "portal_gate"
	prompt = "G: the dungeons"
	radius = 30.0


## The gate is a standing portal: its swirl turns (portal_gate_strip.png, tools/art/gen_portal.py).
func _ready() -> void:
	super._ready()
	SpriteAnim.attach(sprite, sprite_id, 8.0, self)


func interact() -> void:
	var screen := get_tree().get_first_node_in_group("dungeon_select")
	if screen:
		screen.open()
