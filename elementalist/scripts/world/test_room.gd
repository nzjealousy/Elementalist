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
	_spawn_wave()
	get_parent().add_child.call_deferred(NewCharacterMenu.new())
	get_parent().add_child.call_deferred(RewardCards.new())


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


func _spawn_wave() -> void:
	wave += 1
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
