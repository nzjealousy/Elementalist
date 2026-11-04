class_name Dungeon
extends Node2D
## The dungeon run: a randomly generated set of floors (DungeonGen), played one room at a time.
## Combat rooms spawn their waves one after another; when the last monster dies the exit door
## unlocks and walking through it fades to the next room. Treasure rooms hold a chest, forge rooms
## the forge and a free heal; both open at once. The last room of the last floor is the boss.
## Beating the boss (or dying) ends the run on a RunEndScreen; Enter starts a fresh dungeon.
##
## This node is the main scene's world. Its siblings are the Player and the HUD.

const TILE := 16
const WAVE_DELAY := 1.2   # seconds before a room's first wave, and between waves
const FADE_TIME := 0.25
const MIN_SPAWN_DISTANCE := 100.0  # monsters appear at least this far from the player

var layout: Array = []   # floors -> rooms (see DungeonGen)
var floor_index := 0     # 0-based
var room_index := 0
var room: Dictionary = {}
var state := "idle"      # fighting, clear, transition, won or dead
var wave := 0            # waves of this room already spawned
var run_time := 0.0
var with_ui := true      # the menus and the fade layer (tests turn it off)
var rng := RandomNumberGenerator.new()

var _room_node: Node2D
var _exit_door: Door
var _wave_timer := 0.0
var _boss_spawned := false
var _fade: ColorRect
var _end_screen: RunEndScreen
var _text_timer := 0.0


func _ready() -> void:
	if layout.is_empty():
		rng.randomize()
		layout = DungeonGen.generate(rng)
	Game.run_kills = 0
	Game.boss = null
	Game.loot_dropped.connect(_on_loot_dropped)
	var player := _player()
	if player:
		player.died.connect(_on_player_died)
	if with_ui:
		var parent := get_parent()
		parent.add_child.call_deferred(NewCharacterMenu.new())
		parent.add_child.call_deferred(RewardCards.new())
		parent.add_child.call_deferred(ForgeScreen.new())
		_end_screen = RunEndScreen.new()
		parent.add_child.call_deferred(_end_screen)
		var fade_layer := CanvasLayer.new()
		fade_layer.layer = 40
		_fade = ColorRect.new()
		_fade.color = Color(0, 0, 0, 0)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade_layer.add_child(_fade)
		add_child(fade_layer)
	_load_room(0, 0)


func _player() -> Node2D:
	return get_parent().get_node_or_null("Player") as Node2D


# ---------- debug keys ----------

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
		KEY_BRACKETLEFT:
			debug_clear_room()
		KEY_BRACKETRIGHT:
			debug_goto(layout.size() - 1, layout[-1].size() - 1)  # straight to the boss


## Kills everything in the room and cancels the waves still to come.
func debug_clear_room() -> void:
	if state != "fighting":
		return
	wave = room["waves"].size()
	_boss_spawned = true
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Enemy and not node.is_queued_for_deletion():
			node.take_hit({"damage": 100000.0, "element": "", "from": node.global_position})


func debug_goto(floor_number: int, room_number: int) -> void:
	_load_room(floor_number, room_number)


# ---------- rooms ----------

## Builds room `room_number` of floor `floor_number` (0-based), puts the player in it and
## starts what the room holds.
func _load_room(floor_number: int, room_number: int) -> void:
	floor_index = floor_number
	room_index = room_number
	room = layout[floor_number][room_number]
	if _room_node:
		remove_child(_room_node)  # out of the tree now, so its monsters leave the "enemies" group at once
		_room_node.queue_free()
	_room_node = Node2D.new()
	add_child(_room_node)
	_exit_door = null
	wave = 0
	_boss_spawned = false
	Game.boss = null
	Game.danger = floor_number * 3 + room_number
	_build_room()

	var player := _player()
	if player:
		var tile := DungeonGen.spawn_tile(room)
		player.global_position = Vector2(tile) * TILE + Vector2(TILE, TILE) * 0.5
		if player.has_method("set_camera_limits"):
			player.set_camera_limits(Rect2i(0, 0, int(room["cols"]) * TILE, int(room["rows"]) * TILE))
		var camera := player.get_node_or_null("Camera2D") as Camera2D
		if camera and camera.is_inside_tree():
			camera.reset_smoothing()

	match String(room["kind"]):
		"combat", "boss":
			state = "fighting"
			_wave_timer = WAVE_DELAY
		"treasure":
			var chest := Chest.new()
			chest.position = _centre()
			_room_node.add_child(chest)
			_clear_room("A treasure room. Open the chest (G).")
		"forge":
			var forge := ForgeStation.new()
			forge.position = _centre()
			_room_node.add_child(forge)
			_heal_player()
			_clear_room("A place to rest: the forge (G) and a free heal.")
	if String(room["kind"]) in ["combat", "boss"]:
		Game.say("%s\n%s" % [DungeonGen.describe(room), "Defeat the boss!" if room["kind"] == "boss" else "Clear the room to open the door"])
	_update_run_text()


func _centre() -> Vector2:
	return Vector2(int(room["cols"]), int(room["rows"])) * TILE * 0.5


func _build_room() -> void:
	var floor_tex := AssetDB.get_texture("tile_floor")
	var wall_tex := AssetDB.get_texture("tile_wall")
	var sealed_tex := AssetDB.get_texture("door_sealed")
	var cols: int = room["cols"]
	var rows: int = room["rows"]
	var exit_rect := Rect2i()
	if room["exit"] != "":
		exit_rect = DungeonGen.door_rect(room, "exit")
	var entry_rect := Rect2i()
	if room["entry"] != "":
		entry_rect = DungeonGen.door_rect(room, "entry")
	for y in rows:
		for x in cols:
			var tile := Vector2i(x, y)
			var boundary := x == 0 or y == 0 or x == cols - 1 or y == rows - 1
			if boundary and exit_rect.has_point(tile):
				_add_tile(floor_tex, tile, false)  # under the door
				continue
			if boundary:
				_add_tile(sealed_tex if entry_rect.has_point(tile) else wall_tex, tile, true)
			else:
				_add_tile(floor_tex, tile, false)
	for rect in room["obstacles"]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				_add_tile(wall_tex, Vector2i(x, y), true)
	if room["exit"] != "":
		_exit_door = Door.new()
		_exit_door.setup(Rect2(Vector2(exit_rect.position) * TILE, Vector2(exit_rect.size) * TILE), String(room["exit"]))
		_room_node.add_child(_exit_door)


func _add_tile(texture: Texture2D, tile: Vector2i, solid: bool) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(tile) * TILE
	sprite.z_index = -10
	_room_node.add_child(sprite)
	if solid:
		var body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE, TILE)
		shape.shape = rect
		body.position = Vector2(tile) * TILE + Vector2(TILE, TILE) * 0.5
		body.add_child(shape)
		_room_node.add_child(body)


# ---------- fighting ----------

func _physics_process(delta: float) -> void:
	if state in ["fighting", "clear"]:
		run_time += delta
	match state:
		"fighting":
			_tick_fight(delta)
		"clear":
			_tick_exit()
	_text_timer -= delta
	if _text_timer <= 0.0:
		_text_timer = 0.25
		_update_run_text()


func enemies_alive() -> int:
	return get_tree().get_nodes_in_group("enemies").filter(func(n): return not n.is_queued_for_deletion()).size()


func _tick_fight(delta: float) -> void:
	if _wave_timer > 0.0:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			if room["kind"] == "boss":
				_spawn_boss()
			else:
				_spawn_wave()
		return
	if enemies_alive() > 0:
		return
	if room["kind"] == "boss":
		if _boss_spawned:
			_win()
	elif wave < room["waves"].size():
		_wave_timer = WAVE_DELAY
	else:
		_clear_room("Room cleared! The door is open.")


func _spawn_wave() -> void:
	var entries: Array = room["waves"][wave]
	wave += 1
	var floor_scale := Monsters.floor_scale(int(room["floor"]))
	for entry in entries:
		var pos := _spawn_point()
		var enemy := Monsters.spawn(_room_node, String(entry["id"]), pos, String(entry["variant"]), floor_scale)
		SkillFx.ring(_room_node, pos, 12.0, Elements.color_of(String(entry["variant"])) if entry["variant"] != "" else Color("c8c8d0"), 0.5, 1.0)
		enemy.name = "%s%d" % [String(entry["id"]).capitalize(), enemy.get_instance_id()]
	if room["waves"].size() > 1:
		Game.say("Wave %d/%d" % [wave, room["waves"].size()])


func _spawn_boss() -> void:
	_boss_spawned = true
	var pos := _centre() + Vector2(0, -float(room["rows"]) * TILE * 0.25)
	var boss := Monsters.spawn(_room_node, String(room["boss"]), pos, "", Monsters.floor_scale(int(room["floor"])))
	Game.boss = boss
	SkillFx.ring(_room_node, pos, 30.0, Color("ff6a4a"), 0.8, 2.0)
	Game.say("%s awakens!" % boss.display_name)


## A free spot in the room, away from the player and from pillars.
func _spawn_point() -> Vector2:
	var player := _player()
	var size := Vector2(int(room["cols"]), int(room["rows"])) * TILE
	var pos := _centre()
	for attempt in 30:
		pos = Vector2(randf_range(3.0 * TILE, size.x - 3.0 * TILE), randf_range(3.0 * TILE, size.y - 3.0 * TILE))
		var blocked := false
		for rect in room["obstacles"]:
			blocked = blocked or Rect2(Vector2(rect.position) * TILE, Vector2(rect.size) * TILE).grow(8.0).has_point(pos)
		if not blocked and (player == null or pos.distance_to(player.global_position) >= MIN_SPAWN_DISTANCE):
			break
	return pos


func _clear_room(message: String) -> void:
	state = "clear"
	if _exit_door:
		_exit_door.unlock()
	Game.say(message)


func _heal_player() -> void:
	var player := _player()
	if player and "hp" in player:
		player.hp = player.max_hp
		player.stamina = player.max_stamina
		if player.caster:
			player.caster.mana = player.caster.max_mana
		FloatText.spawn(_room_node, player.global_position + Vector2(0, -10), "Rested", Color("7fe88a"), 9)


# ---------- moving on ----------

func _tick_exit() -> void:
	var player := _player()
	if _exit_door and _exit_door.open and player and _exit_door.contains(player.global_position):
		_go_next()


## Fades out, loads the next room (or the next floor's first) and fades back in.
func _go_next() -> void:
	state = "transition"
	_vacuum_loot()
	if _fade == null:
		_advance()
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	tween.tween_callback(_advance)
	tween.tween_property(_fade, "color:a", 0.0, FADE_TIME)


func _advance() -> void:
	if room_index + 1 < layout[floor_index].size():
		_load_room(floor_index, room_index + 1)
	elif floor_index + 1 < layout.size():
		_load_room(floor_index + 1, 0)
	else:
		_win()


## Everything still lying on the floor is picked up on the way out, so no loot is left behind.
func _vacuum_loot() -> void:
	var player := _player()
	for node in get_tree().get_nodes_in_group("pickups"):
		if node is Pickup and player:
			node.vacuum(player)


func _on_loot_dropped(drops: Array, pos: Vector2) -> void:
	if _room_node == null:
		return
	for entry in drops:
		Pickup.spawn(_room_node, pos, entry)


# ---------- the end of a run ----------

func _win() -> void:
	if state in ["won", "dead"]:
		return
	state = "won"
	_vacuum_loot()
	Game.say("The dungeon is cleared!")
	get_tree().create_timer(2.0).timeout.connect(_end.bind(true))  # tied to this node, so freeing it cancels the screen


func _on_player_died() -> void:
	if state in ["won", "dead"]:
		return
	state = "dead"
	_end(false)


func _end(won: bool) -> void:
	var lines := summary_lines(won)
	if _end_screen and is_instance_valid(_end_screen):
		_end_screen.show_result(won, lines)


func summary_lines(won: bool) -> Array:
	var minutes := floori(run_time / 60.0)
	var seconds := int(run_time) % 60
	var lines: Array = []
	lines.append(("Cleared all %d floors" % layout.size()) if won else ("Fell on floor %d, room %d" % [floor_index + 1, room_index + 1]))
	lines.append("Monsters slain: %d" % Game.run_kills)
	lines.append("Time: %d:%02d" % [minutes, seconds])
	lines.append("Level %d    Gold %d" % [Game.character.level, Game.character.inventory.gold])
	return lines


func _update_run_text() -> void:
	var text := "Floor %d/%d  Room %d/%d" % [floor_index + 1, layout.size(), room_index + 1, layout[floor_index].size()]
	if room.get("kind", "") == "combat" and state == "fighting":
		text += "  Wave %d/%d" % [maxi(wave, 1), room["waves"].size()]
	if state == "fighting":
		text += "  Enemies %d" % enemies_alive()
	elif state == "clear" and room.get("kind", "") in ["combat", "boss"]:
		text += "  Door open"
	Game.run_text = text
