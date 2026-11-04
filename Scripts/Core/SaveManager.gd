extends Node
## Local-first save data for Trailblazer Dash.
##
## Everything is written to `user://` immediately after a meaningful event and
## then mirrored to the Little Joy Arcade save when a player is signed in. The
## schema is versioned and migrated on load, and a missing or corrupt file is
## backed up rather than deleted.

signal changed
signal achievement_unlocked(id: String)

const SAVE_PATH := "user://trailblazer_save.json"
const BACKUP_PATH := "user://trailblazer_save.corrupt.json"
const SCHEMA_VERSION := 2

var data: Dictionary = {}
var _dirty := false
var _timer: Timer
var _writing := false

const ACHIEVEMENTS := [
	{"id": "first_steps", "name": "First Steps", "hint": "Finish your first run."},
	{"id": "first_beacon", "name": "Beacon Lit", "hint": "Complete Sunmeadow's first level."},
	{"id": "ten_levels", "name": "Trailblazer", "hint": "Clear ten campaign levels."},
	{"id": "hundred_levels", "name": "Long Way Round", "hint": "Clear one hundred levels."},
	{"id": "five_hundred", "name": "Heart of Avelora", "hint": "Clear all five hundred levels."},
	{"id": "relic_10", "name": "Relic Hunter", "hint": "Recover ten Wayfinder relics."},
	{"id": "relic_50", "name": "Curator", "hint": "Recover fifty relics."},
	{"id": "perfect_run", "name": "Clean Boots", "hint": "Finish a level without a stumble."},
	{"id": "three_stars", "name": "Wayfinder's Best", "hint": "Earn three stars on any level."},
	{"id": "endless_1000", "name": "One Thousand Metres", "hint": "Run 1,000m in Endless."},
	{"id": "endless_5000", "name": "Far Runner", "hint": "Run 5,000m in Endless."},
	{"id": "daily_done", "name": "Same Sky", "hint": "Finish a Daily Challenge."},
	{"id": "sparks_1000", "name": "Sparkkeeper", "hint": "Collect 1,000 Wayfinder Sparks."},
	{"id": "region_three", "name": "Past the River", "hint": "Unlock Riverstone Crossing."},
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.8
	_timer.timeout.connect(flush)
	add_child(_timer)
	load_data()


func _defaults() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"created": Time.get_unix_time_from_system(),
		"savedAt": 0,
		"profile": {"name": "Trailblazer", "character": "pip", "companion": "none"},
		"settings": {
			"music": 0.7,
			"sfx": 0.85,
			"quality": "auto",
			"reduced_motion": false,
			"left_handed": false,
			"tutorial_done": false,
			"low_contrast_hazards": false,
		},
		"progress": {
			"levels": {},
			"sparks": 0,
			"relics": 0,
			"total_score": 0,
			"unlocked": ["pip"],
			"cosmetics": [],
		},
		"records": {
			"endless_best": 0,
			"endless_score": 0,
			"daily": {},
			"daily_streak": 0,
			"runs": 0,
			"distance": 0,
			"best_time": {},
		},
		"achievements": {},
		"stats": {
			"levels_completed": 0,
			"perfect_runs": 0,
			"stumbles": 0,
			"powers": 0,
			"play_seconds": 0,
		},
	}


func load_data() -> void:
	data = _defaults()
	if not FileAccess.file_exists(SAVE_PATH):
		queue_save()
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_backup_corrupt(text)
		queue_save()
		return
	data = _merge(parsed, _defaults())
	_migrate()
	changed.emit()


func _backup_corrupt(text: String) -> void:
	push_warning("Trailblazer save could not be parsed; keeping a backup.")
	var file := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()


func _migrate() -> void:
	var schema := int(data.get("schema", 1))
	if schema < 2:
		# v2 added relics, daily streaks and playtime. Defaults already fill
		# those keys in via _merge, so the migration only stamps the version.
		if not data["records"].has("best_time"):
			data["records"]["best_time"] = {}
		if not data["settings"].has("low_contrast_hazards"):
			data["settings"]["low_contrast_hazards"] = false
	data["schema"] = SCHEMA_VERSION


func _merge(target: Dictionary, defaults: Dictionary) -> Dictionary:
	for key in defaults.keys():
		if not target.has(key):
			target[key] = defaults[key]
		elif typeof(target[key]) == TYPE_DICTIONARY and typeof(defaults[key]) == TYPE_DICTIONARY:
			_merge(target[key], defaults[key])
	return target


func queue_save() -> void:
	_dirty = true
	if _timer and _timer.is_inside_tree():
		_timer.start()


func flush() -> void:
	if _writing:
		return
	_writing = true
	data["savedAt"] = int(Time.get_unix_time_from_system() * 1000.0)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.flush()
		file.close()
		_dirty = false
		if has_node("/root/Arcade"):
			get_node("/root/Arcade").on_local_save(data)
	if has_node("/root/Audio"):
		get_node("/root/Audio").apply_settings(data["settings"])
	_writing = false


func get_setting(key: String, fallback: Variant = null) -> Variant:
	if data.has("settings") and data["settings"].has(key):
		return data["settings"][key]
	return fallback


func set_setting(key: String, value: Variant) -> void:
	data["settings"][key] = value
	queue_save()
	if has_node("/root/Audio"):
		get_node("/root/Audio").apply_settings(data["settings"])
	changed.emit()


func level_stars(id: int) -> int:
	return int(data["progress"]["levels"].get(str(id), 0))


func is_level_complete(id: int) -> bool:
	return level_stars(id) > 0


func best_time(id: int) -> float:
	return float(data["records"]["best_time"].get(str(id), 0.0))


func total_stars() -> int:
	var total := 0
	for value in data["progress"]["levels"].values():
		total += int(value)
	return total


func completed_levels() -> int:
	var total := 0
	for value in data["progress"]["levels"].values():
		if int(value) > 0:
			total += 1
	return total


func completed_in_region(level_ids: Array) -> int:
	var total := 0
	for id in level_ids:
		if is_level_complete(int(id)):
			total += 1
	return total


func stars_in_region(level_ids: Array) -> int:
	var total := 0
	for id in level_ids:
		total += level_stars(int(id))
	return total


## Records a finished run. Returns the achievement ids that were newly unlocked.
func complete_level(id: int, stars: int, score: int, sparks: int, relics: int,
		elapsed: float, stumbles: int, perfect: bool) -> Array:
	var key := str(id)
	var previous := int(data["progress"]["levels"].get(key, 0))
	if stars > previous:
		data["progress"]["levels"][key] = stars
	data["progress"]["sparks"] = int(data["progress"]["sparks"]) + sparks
	data["progress"]["relics"] = int(data["progress"]["relics"]) + relics
	data["progress"]["total_score"] = int(data["progress"]["total_score"]) + score
	data["records"]["runs"] = int(data["records"]["runs"]) + 1
	data["records"]["distance"] = int(data["records"]["distance"]) + 1
	data["stats"]["levels_completed"] = completed_levels()
	data["stats"]["stumbles"] = int(data["stats"]["stumbles"]) + stumbles
	if perfect:
		data["stats"]["perfect_runs"] = int(data["stats"]["perfect_runs"]) + 1
	if elapsed > 0:
		var old := float(data["records"]["best_time"].get(key, 0.0))
		if old <= 0.0 or elapsed < old:
			data["records"]["best_time"][key] = elapsed
	var unlocked := check_achievements()
	queue_save()
	changed.emit()
	return unlocked


func add_endless(distance: int, score: int) -> Array:
	data["records"]["endless_best"] = maxi(int(data["records"]["endless_best"]), distance)
	data["records"]["endless_score"] = maxi(int(data["records"]["endless_score"]), score)
	data["records"]["runs"] = int(data["records"]["runs"]) + 1
	data["records"]["distance"] = int(data["records"]["distance"]) + distance
	var unlocked := check_achievements()
	queue_save()
	return unlocked


func daily_date_key() -> String:
	var now := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [now.year, now.month, now.day]


func record_daily(score: int, distance: int) -> Array:
	var key := daily_date_key()
	var entry: Dictionary = data["records"]["daily"].get(key, {"best": 0, "distance": 0, "attempts": 0, "done": false})
	entry["best"] = maxi(int(entry.get("best", 0)), score)
	entry["distance"] = maxi(int(entry.get("distance", 0)), distance)
	entry["attempts"] = int(entry.get("attempts", 0)) + 1
	entry["done"] = true
	data["records"]["daily"][key] = entry
	data["records"]["daily_streak"] = _streak()
	var unlocked := check_achievements()
	queue_save()
	return unlocked


func _streak() -> int:
	var streak := 0
	var day := Time.get_unix_time_from_system()
	for i in range(60):
		var stamp := day - i * 86400
		var d := Time.get_datetime_dict_from_unix_time(int(stamp))
		var key := "%04d-%02d-%02d" % [d.year, d.month, d.day]
		var entry: Variant = data["records"]["daily"].get(key)
		if typeof(entry) != TYPE_DICTIONARY or not bool(entry.get("done", false)):
			if i == 0:
				continue
			break
		streak += 1
	return streak


func has_achievement(id: String) -> bool:
	return data["achievements"].has(id)


func unlock_achievement(id: String) -> bool:
	if data["achievements"].has(id):
		return false
	data["achievements"][id] = int(Time.get_unix_time_from_system())
	queue_save()
	achievement_unlocked.emit(id)
	if has_node("/root/Arcade"):
		get_node("/root/Arcade").achievement(id)
	return true


## Checks every rule. Cheap enough to run on each level completion.
func check_achievements() -> Array:
	var unlocked: Array = []
	var level_count := completed_levels()
	var checks := {
		"first_steps": int(data["records"]["runs"]) > 0,
		"first_beacon": is_level_complete(1),
		"ten_levels": level_count >= 10,
		"hundred_levels": level_count >= 100,
		"five_hundred": level_count >= 500,
		"relic_10": int(data["progress"]["relics"]) >= 10,
		"relic_50": int(data["progress"]["relics"]) >= 50,
		"perfect_run": int(data["stats"]["perfect_runs"]) > 0,
		"three_stars": total_stars() >= 3,
		"endless_1000": int(data["records"]["endless_best"]) >= 1000,
		"endless_5000": int(data["records"]["endless_best"]) >= 5000,
		"daily_done": data["records"]["daily"].size() > 0,
		"sparks_1000": int(data["progress"]["sparks"]) >= 1000,
		"region_three": is_level_complete(51) or completed_in_region(range(26, 51)) > 0,
	}
	for id in checks.keys():
		if checks[id] and unlock_achievement(id):
			unlocked.append(id)
	return unlocked


func unlock_character(id: String) -> bool:
	var unlocked: Array = data["progress"]["unlocked"]
	if unlocked.has(id):
		return false
	unlocked.append(id)
	queue_save()
	changed.emit()
	return true


func reset_progress() -> void:
	var profile: Dictionary = data["profile"]
	var settings: Dictionary = data["settings"]
	var created: Variant = data["created"]
	data = _defaults()
	data["profile"] = profile
	data["settings"] = settings
	data["created"] = created
	queue_save()
	changed.emit()
