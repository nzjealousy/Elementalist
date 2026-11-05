class_name SaveStore
extends RefCounted
## Save slots on disk (plain JSON under user://saves/), written crash-safe and read defensively.
##
## A slot holds DATA only, never nodes or resources:
##   version     schema number; MIGRATIONS bring older files up to VERSION
##   saved_at    unix time
##   character   CharacterData.to_dict()
##   meta        the long-term state of this hero: {"difficulty", "tier_cleared", "runs", "play_time"}
##   run         the dungeon in progress, or {} in camp: {"tier", "seed", "floor", "room", "kills", "time"}
##               (the layout is rebuilt from the seed, so the file stays small)
##
## Write: temp file, keep the previous good file as .bak, then rename into place. Load: try the
## file, then the .bak; parse errors and missing keys never throw, they return {}.

const VERSION := 1
const SLOTS := 3
const MAX_BYTES := 4 * 1024 * 1024  # a save bigger than this is not ours

static var dir := "user://saves"  # tests point this at a scratch folder


static func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [dir, slot]


static func new_meta(difficulty: String = "knight") -> Dictionary:
	return {"difficulty": difficulty, "tier_cleared": 0, "runs": 0, "play_time": 0.0}


## Writes a slot atomically. Returns OK or the error to show the player.
static func save_slot(slot: int, character: Dictionary, meta: Dictionary, run: Dictionary = {}) -> Error:
	if slot < 0 or slot >= SLOTS:
		return ERR_INVALID_PARAMETER
	var payload := {"version": VERSION, "saved_at": int(Time.get_unix_time_from_system()),
		"character": character, "meta": meta, "run": run}
	return write_atomic(slot_path(slot), JSON.stringify(payload))


## Writes `text` to `path` crash-safe (saves and the leaderboard). On any failure the old file is left as it was.
static func write_atomic(path: String, text: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored := file.store_string(text)
	file.flush()
	var err := file.get_error()
	file.close()
	if not stored or err != OK:
		DirAccess.remove_absolute(tmp)  # a half-written file (disk full) must never replace the good one
		return err if err != OK else ERR_FILE_CANT_WRITE
	var backup := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		var moved := DirAccess.rename_absolute(path, backup)  # the last good save survives a crash between the renames
		if moved != OK:
			DirAccess.remove_absolute(tmp)
			return moved
	return DirAccess.rename_absolute(tmp, path)


## The slot's data, migrated to the current version, or {} when there is nothing loadable.
static func load_slot(slot: int) -> Dictionary:
	if slot < 0 or slot >= SLOTS:
		return {}
	var path := slot_path(slot)
	for candidate in [path, path + ".bak"]:
		var data := _read(candidate)
		if not data.is_empty():
			return data
	return {}


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() or text.length() > MAX_BYTES:
		return {}
	var json := JSON.new()  # (an instance, so a damaged file is a quiet {} and not an engine error)
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	return migrate(json.data)


## Brings a parsed save up to VERSION; {} if it is from a newer build or is missing what a save needs.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))  # JSON numbers load as float
	if version > VERSION:
		return {}
	while version < VERSION:
		version += 1  # (no migrations yet: version 1 is the first shipped schema)
	if not (data.get("character") is Dictionary) or not _has_character_keys(data["character"]):
		return {}
	data["version"] = VERSION
	if not (data.get("meta") is Dictionary):
		data["meta"] = new_meta()
	var meta: Dictionary = data["meta"]
	for key in new_meta():
		if not meta.has(key):
			meta[key] = new_meta()[key]
	if not (data.get("run") is Dictionary):
		data["run"] = {}
	return data


static func _has_character_keys(c: Dictionary) -> bool:
	for key in ["name", "class", "subclass", "affinity", "level", "xp", "points", "attributes", "elements",
			"element_mastery", "weapon_type", "weapon_masteries"]:
		if not c.has(key):
			return false
	return true


static func exists(slot: int) -> bool:
	return not load_slot(slot).is_empty()


static func delete_slot(slot: int) -> void:
	var path := slot_path(slot)
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## What the menu shows for a slot: {} when empty, otherwise name, class, level, place and date.
static func summary(slot: int) -> Dictionary:
	var data := load_slot(slot)
	if data.is_empty():
		return {}
	var c: Dictionary = data["character"]
	var class_id := String(c["class"])
	var class_name_text: String = Classes.CLASSES[class_id]["name"] if Classes.CLASSES.has(class_id) else class_id.capitalize()
	var run: Dictionary = data["run"]
	var meta: Dictionary = data["meta"]
	var where := "In camp"
	if not run.is_empty():
		where = "Dungeon %d, floor %d" % [int(run.get("tier", 1)), int(run.get("floor", 0)) + 1]
	return {"name": String(c["name"]), "class": class_name_text, "level": int(c["level"]),
		"elements": (c["elements"] as Array).size(), "where": where, "runs": int(meta["runs"]),
		"cleared": int(meta["tier_cleared"]), "difficulty": String(meta["difficulty"]),
		"saved_at": int(data["saved_at"])}
