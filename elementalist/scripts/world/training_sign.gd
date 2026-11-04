class_name TrainingSign
extends Interactable
## A signpost that leads between the camp and the training grounds (G). In the camp it enters the
## grounds with a sandbox hero; inside the grounds the same post leads back and nothing is saved.

var leaving := false


func _init() -> void:
	sprite_id = "training_sign"
	radius = 26.0


func _ready() -> void:
	prompt = "G: back to camp" if leaving else "G: training grounds"
	super._ready()


func interact() -> void:
	if leaving:
		Game.end_training()
	else:
		Game.begin_training()
