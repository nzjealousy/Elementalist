class_name Leaderboard
extends RefCounted
## The runs leaderboard: the best MAX_ENTRIES runs on this machine, in user://leaderboard.json.
## One entry per finished run (cleared a dungeon, fell and returned to camp, or died for good).
##
## Score rewards getting far and staying alive, scaled by the difficulty you chose:
##   floors reached x 100  +  kills x 10  +  level x 50  +  gold / 10  +  1000 per dungeon cleared
##   - time bonus (up to 500 for a fast clear)         x difficulty reward multiplier

const MAX_ENTRIES := 25
const VERSION := 1

static var path := "user://leaderboard.json"  # tests point this at a scratch file


## stats: {"floors": int, "kills": int, "level": int, "gold": int, "cleared": bool, "tier": int,
##         "time": float (seconds), "reward_mult": float}
static func score_for(stats: Dictionary) -> int:
	var score := int(stats.get("floors", 0)) * 100 + int(stats.get("kills", 0)) * 10 \
		+ int(stats.get("level", 1)) * 50 + floori(float(stats.get("gold", 0)) / 10.0)
	if bool(stats.get("cleared", false)):
		score += 1000 * int(stats.get("tier", 1))
		var minutes := float(stats.get("time", 0.0)) / 60.0
		score += int(clampf(500.0 - minutes * 10.0, 0.0, 500.0))
	return int(round(float(score) * float(stats.get("reward_mult", 1.0))))


## The board as saved: the file, else its .bak (the board before the last write, SaveStore.write_atomic), as SaveStore.load_slot.
static func entries() -> Array:
	for candidate in [path, path + ".bak"]:
		var text := FileAccess.get_file_as_string(candidate) if FileAccess.file_exists(candidate) else ""
		var json := JSON.new()
		var parsed: Variant = json.data if (not text.is_empty() and json.parse(text) == OK) else null
		if parsed is Dictionary and parsed.get("entries") is Array:
			return parsed["entries"].filter(func(entry): return entry is Dictionary and entry.has("score"))
	return []


## Adds a run and keeps the best MAX_ENTRIES. Returns the 1-based rank it earned, or 0 if it did
## not make the list.
static func record(entry: Dictionary) -> int:
	var list := entries()
	entry["score"] = int(entry.get("score", score_for(entry)))
	entry["date"] = Time.get_datetime_string_from_system(false, true)
	list.append(entry)
	list.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	var rank := list.find(entry) + 1
	if list.size() > MAX_ENTRIES:
		list.resize(MAX_ENTRIES)
	if rank > MAX_ENTRIES:
		rank = 0
	SaveStore.write_atomic(path, JSON.stringify({"version": VERSION, "entries": list}))  # a crash mid-write keeps the old board
	return rank


static func clear() -> void:
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
