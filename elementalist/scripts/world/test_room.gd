extends Node2D
## Test arena: tiled room with a wall border and endless enemy waves for combat testing.

const TILE := 16
const COLS := 30
const ROWS := 17
const SLIME_SCENE := preload("res://scenes/enemies/slime.tscn")
const WAVE_DELAY := 2.0

var wave := 0
var _alive := 0


func _ready() -> void:
	var player := get_parent().get_node_or_null("Player")
	if player:
		player.set_camera_limits(Rect2i(0, 0, COLS * TILE, ROWS * TILE))
	_build_room()
	var forge := ForgeStation.new()
	forge.position = Vector2(COLS * TILE * 0.5, 3.0 * TILE)
	add_child(forge)
	Game.loot_dropped.connect(_on_loot_dropped)
	Game.danger = 0
	_spawn_wave()
	get_parent().add_child.call_deferred(NewCharacterMenu.new())
	get_parent().add_child.call_deferred(RewardCards.new())
	get_parent().add_child.call_deferred(ForgeScreen.new())


## Debug shortcuts for trying characters in the arena (the story/menu comes in a later phase).
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F5:
			Game.start_sandbox("channeler")
			get_tree().reload_current_scene()
		KEY_F10:
			Game.attune_random()  # no restart: the player picks up the new element live
		KEY_F6:
			var screen := get_tree().get_first_node_in_group("forge_screen")  # the forge from anywhere
			if screen:
				screen.open()


func _build_room() -> void:
	var floor_tex := AssetDB.get_texture("tile_floor")
	var wall_tex := AssetDB.get_texture("tile_wall")
	for y in ROWS:
		for x in COLS:
			var is_wall := x == 0 or y == 0 or x == COLS - 1 or y == ROWS - 1
			var s := Sprite2D.new()
			s.texture = wall_tex if is_wall else floor_tex
			s.centered = false
			s.position = Vector2(x, y) * TILE
			s.z_index = -10
			add_child(s)
			if is_wall:
				var body := StaticBody2D.new()
				var shape := CollisionShape2D.new()
				var rect := RectangleShape2D.new()
				rect.size = Vector2(TILE, TILE)
				shape.shape = rect
				body.position = Vector2(x, y) * TILE + Vector2(TILE, TILE) * 0.5
				body.add_child(shape)
				add_child(body)


func _on_loot_dropped(drops: Array, pos: Vector2) -> void:
	for entry in drops:
		Pickup.spawn(self, pos, entry)


## Every third wave a chest appears somewhere in the room.
func _spawn_chest() -> void:
	var chest := Chest.new()
	chest.position = Vector2(randf_range(40.0, COLS * TILE - 40.0), randf_range(56.0, ROWS * TILE - 40.0))
	add_child(chest)
	var player := get_parent().get_node_or_null("Player") as Node2D
	if player:
		FloatText.spawn(self, player.global_position + Vector2(0, -24), "A chest appeared!", Color("ffd84a"))


func _spawn_wave() -> void:
	wave += 1
	Game.danger = wave
	if wave % 3 == 0:
		_spawn_chest()
	var player := get_parent().get_node_or_null("Player") as Node2D
	var count := 3 + wave
	for i in count:
		var pos := Vector2.ZERO
		for attempt in 12:
			pos = Vector2(randf_range(32.0, COLS * TILE - 32.0), randf_range(32.0, ROWS * TILE - 32.0))
			if player == null or pos.distance_to(player.global_position) > 110.0:
				break
		var enemy: Enemy = SLIME_SCENE.instantiate()
		enemy.position = pos
		enemy.died.connect(_on_enemy_died)
		add_child(enemy)
		_alive += 1


func _on_enemy_died(_enemy: Enemy) -> void:
	_alive -= 1
	if _alive <= 0:
		await get_tree().create_timer(WAVE_DELAY).timeout
		_spawn_wave()
