class_name DungeonGen
extends RefCounted
## Random dungeon layouts (pure data, so they are testable without any scene). A dungeon is
## FLOORS floors of rooms; the last floor ends in the boss room.
##
## Floors 1 to FLOORS-1:   three rooms, one of them a "special" room (treasure chest or forge
##                         and a free heal), never the first.
## Last floor:             a combat room, a special room, then the boss room.
##
## A ROOM is a Dictionary:
##   floor, index        1-based floor and 0-based room number
##   kind                "combat", "treasure", "forge" or "boss"
##   cols, rows          size in tiles (the outer ring of tiles is wall)
##   entry, exit         the wall ("north", "east", "south", "west") the player comes in by and
##                       leaves through ("" for the first room's entry and the boss room's exit)
##   door_entry, door_exit   where along that wall the door starts, in tiles
##   obstacles           Array of Rect2i (tiles): pillars to fight around
##   waves               Array of waves, each an Array of {"id", "variant"} (see Monsters)
##   boss                the boss monster id, "" for other rooms
## The exit door stays locked until the room's waves are cleared (see Dungeon).

const FLOORS := 3
const DOOR_WIDTH := 2  # tiles
const WALL_MARGIN := 3 # obstacles keep this many tiles from walls, doors and the entry point
const OPPOSITE := {"north": "south", "east": "west", "south": "north", "west": "east"}
const SIDES := ["north", "east", "south", "west"]


## All floors: an Array (one per floor) of Arrays of rooms.
static func generate(rng: RandomNumberGenerator, floors: int = FLOORS) -> Array:
	var out: Array = []
	for floor_number in range(1, floors + 1):
		out.append(_make_floor(rng, floor_number, floor_number == floors))
	return out


static func _make_floor(rng: RandomNumberGenerator, floor_number: int, last: bool) -> Array:
	var special := "treasure" if rng.randf() < 0.5 else "forge"
	var kinds: Array[String]
	if last:
		kinds = ["combat", special, "boss"]
	elif rng.randf() < 0.5:
		kinds = ["combat", special, "combat"]
	else:
		kinds = ["combat", "combat", special]
	var rooms: Array = []
	var entry := ""
	for i in kinds.size():
		var room := _make_room(rng, floor_number, i, kinds[i], entry)
		rooms.append(room)
		entry = OPPOSITE[room["exit"]] if room["exit"] != "" else ""
	return rooms


static func _make_room(rng: RandomNumberGenerator, floor_number: int, index: int, kind: String, entry: String) -> Dictionary:
	var room := {"floor": floor_number, "index": index, "kind": kind, "entry": entry, "exit": "",
		"door_entry": 0, "door_exit": 0, "obstacles": [], "waves": [], "boss": ""}
	match kind:
		"combat":
			room["cols"] = rng.randi_range(20, 28)
			room["rows"] = rng.randi_range(12, 15)
		"boss":
			room["cols"] = 26
			room["rows"] = 16
		_:
			room["cols"] = rng.randi_range(14, 18)
			room["rows"] = rng.randi_range(10, 12)
	if kind != "boss":
		var exits: Array = SIDES.filter(func(s): return s != entry)
		room["exit"] = exits[rng.randi_range(0, exits.size() - 1)]
		room["door_exit"] = _door_position(rng, room, String(room["exit"]))
	if entry != "":
		room["door_entry"] = _door_position(rng, room, entry)

	match kind:
		"combat":
			room["obstacles"] = _place_obstacles(rng, room, rng.randi_range(0, 1 + floor_number))
			var wave_count := rng.randi_range(1, 2) if floor_number < 3 else 2
			var size_range := Vector2i(2 + floor_number, 3 + floor_number + (1 if floor_number > 1 else 0))
			for w in wave_count:
				room["waves"].append(Monsters.roll_wave(rng, floor_number, rng.randi_range(size_range.x, size_range.y)))
		"boss":
			room["boss"] = Monsters.bosses()[rng.randi_range(0, Monsters.bosses().size() - 1)]
			room["obstacles"] = _place_obstacles(rng, room, 4)
	return room


## Where along a wall a door starts, in tiles: clear of the corners.
static func _door_position(rng: RandomNumberGenerator, room: Dictionary, side: String) -> int:
	var length: int = room["cols"] if side in ["north", "south"] else room["rows"]
	return rng.randi_range(3, length - 3 - DOOR_WIDTH)


## The door's tiles on the wall (a 2-tile gap).
static func door_rect(room: Dictionary, which: String) -> Rect2i:
	var side: String = room[which]
	var d: int = room["door_" + which]
	var cols: int = room["cols"]
	var rows: int = room["rows"]
	match side:
		"north": return Rect2i(d, 0, DOOR_WIDTH, 1)
		"south": return Rect2i(d, rows - 1, DOOR_WIDTH, 1)
		"west": return Rect2i(0, d, 1, DOOR_WIDTH)
		_: return Rect2i(cols - 1, d, 1, DOOR_WIDTH)


## The tile the player stands on when entering: just inside the entry door, or the room centre
## for the first room.
static func spawn_tile(room: Dictionary) -> Vector2i:
	var cols: int = room["cols"]
	var rows: int = room["rows"]
	var d: int = room["door_entry"]
	match String(room["entry"]):
		"north": return Vector2i(d + 1, 2)
		"south": return Vector2i(d + 1, rows - 3)
		"west": return Vector2i(2, d + 1)
		"east": return Vector2i(cols - 3, d + 1)
	return Vector2i(floori(cols / 2.0), floori(rows / 2.0))


## Tiles that must stay open: around the entry point and in front of each door.
static func keep_clear(room: Dictionary) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var spawn := spawn_tile(room)
	out.append(Rect2i(spawn - Vector2i(WALL_MARGIN, WALL_MARGIN), Vector2i(WALL_MARGIN * 2 + 1, WALL_MARGIN * 2 + 1)))
	for which in ["entry", "exit"]:
		if String(room[which]) == "":
			continue
		var rect := door_rect(room, which)
		out.append(rect.grow(WALL_MARGIN))
	return out


static func _place_obstacles(rng: RandomNumberGenerator, room: Dictionary, count: int) -> Array:
	var out: Array = []
	var blocked := keep_clear(room)
	var cols: int = room["cols"]
	var rows: int = room["rows"]
	for i in count:
		for attempt in 20:
			var size := Vector2i(rng.randi_range(1, 2), rng.randi_range(1, 2))
			var pos := Vector2i(rng.randi_range(WALL_MARGIN, cols - WALL_MARGIN - size.x), rng.randi_range(WALL_MARGIN, rows - WALL_MARGIN - size.y))
			var rect := Rect2i(pos, size)
			var clash := false
			for other in blocked:
				clash = clash or other.intersects(rect)
			for other in out:
				clash = clash or (other as Rect2i).grow(1).intersects(rect)
			if not clash:
				out.append(rect)
				break
	return out


## "Floor 2, room 3: combat" for banners.
static func describe(room: Dictionary) -> String:
	return "Floor %d - %s" % [room["floor"], {"combat": "Combat", "treasure": "Treasure room", "forge": "Forge and rest", "boss": "Boss"}[room["kind"]]]
