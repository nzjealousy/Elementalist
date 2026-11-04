class_name Pickup
extends Node2D
## Loot lying on the floor: gold, a crafting material or a piece of gear. Drifts toward the
## player when close and is collected on touch. Gear stays put while the bag is full. Vanishes
## after LIFETIME seconds.

const MAGNET_RANGE := 40.0
const MAGNET_SPEED := 150.0
const COLLECT_RANGE := 7.0
const ARM_TIME := 0.35     # a fresh drop can't be collected until it has landed
const LIFETIME := 120.0

var drop: Dictionary = {}  # one entry of a Loot drop list
var _age := 0.0
var _full_cd := 0.0
var _sprite: Sprite2D


## Creates a pickup for `entry` (see Loot) that pops out of `pos` onto the floor nearby.
static func spawn(parent: Node, pos: Vector2, entry: Dictionary) -> Pickup:
	var pickup := Pickup.new()
	pickup.drop = entry
	pickup.position = pos
	parent.add_child(pickup)
	var landing := pos + Vector2.from_angle(randf() * TAU) * randf_range(6.0, 18.0)
	pickup.create_tween().tween_property(pickup, "position", landing, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return pickup


func _ready() -> void:
	add_to_group("pickups")
	_sprite = Sprite2D.new()
	match drop["kind"]:
		"gold":
			_sprite.texture = AssetDB.get_texture("pickup_gold")
		"material":
			_sprite.texture = AssetDB.get_texture("pickup_material")
			_sprite.modulate = Items.MATERIALS[drop["id"]]["color"]
		"item":
			_sprite.texture = AssetDB.get_texture("pickup_item")
			_sprite.modulate = Items.rarity_color(drop["item"])
	add_child(_sprite)
	z_index = 5


func _physics_process(delta: float) -> void:
	_age += delta
	_full_cd = maxf(0.0, _full_cd - delta)
	_sprite.position.y = sin(_age * 5.0) * 1.2
	if _age >= LIFETIME:
		queue_free()
		return
	if _age < ARM_TIME:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var distance := player.global_position.distance_to(global_position)
	if distance <= COLLECT_RANGE:
		_collect(player)
	elif distance <= MAGNET_RANGE and _can_collect():
		global_position = global_position.move_toward(player.global_position, MAGNET_SPEED * delta)


## Picks this up wherever it lies (used on leaving a room). Gear stays if the bag is full.
func vacuum(player: Node2D) -> void:
	if is_queued_for_deletion():
		return
	_collect(player)


func _can_collect() -> bool:
	return drop["kind"] != "item" or not Game.character.inventory.bag_full()


func _collect(player: Node2D) -> void:
	var inv := Game.character.inventory
	var text := ""
	var color := Color.WHITE
	match drop["kind"]:
		"gold":
			inv.add_gold(int(drop["amount"]))
			text = "+%d gold" % int(drop["amount"])
			color = Color("ffd84a")
		"material":
			inv.add_material(drop["id"], int(drop["amount"]))
			text = "+%d %s" % [int(drop["amount"]), Items.material_name(drop["id"])]
			color = Items.MATERIALS[drop["id"]]["color"]
		"item":
			if not inv.add_item(drop["item"]):
				if _full_cd == 0.0:  # tell the player once in a while, not every frame
					FloatText.spawn(get_parent(), player.global_position + Vector2(0, -12), "Bag full", Color("ff7a7a"))
					_full_cd = 2.0
				return
			text = Items.display_name(drop["item"])
			color = Items.rarity_color(drop["item"])
	FloatText.spawn(get_parent(), player.global_position + Vector2(0, -12), text, color)
	Sfx.play("pickup_gold" if drop["kind"] == "gold" else ("pickup_gem" if String(drop.get("id", "")).begins_with("gem") else "pickup_item"), &"SFX", -4.0)
	queue_free()
