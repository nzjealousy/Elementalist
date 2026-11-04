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


static func entries() -> Array:
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	var out: Array = []
	if parsed is Dictionary and parsed.get("entries") is Array:
		for entry in parsed["entries"]:
			if entry is Dictionary and entry.has("score"):
				out.append(entry)
	return out


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
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version": VERSION, "entries": list}))
		file.close()
	return rank


static func clear() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
