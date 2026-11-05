class_name Chest
extends Interactable
## A treasure chest: open it once with G to spill gold, scrap and gear (see Loot.chest_drops).

var opened := false


func _init() -> void:
	sprite_id = "chest"
	prompt = "G: open"


func can_interact() -> bool:
	return not opened


func interact() -> void:
	opened = true
	Sfx.play("chest_open")
	SkillFx.chest_puff(get_parent(), global_position)
	sprite.texture = AssetDB.get_texture("chest_open")
	for entry in Loot.chest_drops(Game.loot_rng, Game.loot_level(), Game.loot_bonus(), Game.loot_allows_spell()):
		Pickup.spawn(get_parent(), global_position, entry)
	Juice.shake(1.0, 0.1)
