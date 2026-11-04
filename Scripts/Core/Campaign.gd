extends Node
## Loads the generated campaign and answers progression questions.
##
## The level data is produced by Tools/campaign.py and validated there, so this
## script never invents layout: it only reads and exposes it.

const DATA_PATH := "res://Resources/Campaign/campaign.json"
const TOTAL_LEVELS := 500
const LEVELS_PER_REGION := 25
const REGION_UNLOCK_REQUIREMENT := 20

var regions: Array = []
var levels: Array = []
var by_id: Dictionary = {}
var loaded := false


func _ready() -> void:
	load_campaign()


func load_campaign() -> bool:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("Campaign data missing: " + DATA_PATH)
		return false
	var text := FileAccess.get_file_as_string(DATA_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Campaign data is not valid JSON.")
		return false
	regions = parsed.get("regions", [])
	levels = parsed.get("levels", [])
	by_id.clear()
	for level in levels:
		by_id[int(level["id"])] = level
	loaded = true
	return true


func level(id: int) -> Dictionary:
	return by_id.get(id, {})


func region(id: int) -> Dictionary:
	if id < 1 or id > regions.size():
		return {}
	return regions[id - 1]


func region_of_level(id: int) -> int:
	var entry := level(id)
	return int(entry.get("region", 1))


func levels_in_region(region_id: int) -> Array:
	var out: Array = []
	for entry in levels:
		if int(entry["region"]) == region_id:
			out.append(entry)
	return out


func level_ids_in_region(region_id: int) -> Array:
	var out: Array = []
	for entry in levels:
		if int(entry["region"]) == region_id:
			out.append(int(entry["id"]))
	return out


func level_label(entry: Dictionary) -> String:
	return "%d-%02d" % [int(entry.get("region", 1)), int(entry.get("local", 1))]


func level_title(entry: Dictionary) -> String:
	return "%s · %s" % [level_label(entry), String(entry.get("name", "Trail"))]


func region_name(region_id: int) -> String:
	var entry := region(region_id)
	return String(entry.get("name", "Avelora"))


func region_unlocked(region_id: int) -> bool:
	if region_id <= 1:
		return true
	var previous := level_ids_in_region(region_id - 1)
	return Save.completed_in_region(previous) >= REGION_UNLOCK_REQUIREMENT


func is_level_unlocked(id: int) -> bool:
	if id <= 1:
		return true
	if not region_unlocked(region_of_level(id)):
		return false
	if id % LEVELS_PER_REGION == 1:
		return true
	return Save.is_level_complete(id - 1)


func region_progress(region_id: int) -> Dictionary:
	var ids := level_ids_in_region(region_id)
	var done := Save.completed_in_region(ids)
	return {
		"completed": done,
		"total": ids.size(),
		"stars": Save.stars_in_region(ids),
		"max_stars": ids.size() * 3,
		"ratio": float(done) / maxf(1.0, float(ids.size())),
	}


func next_level_id() -> int:
	for entry in levels:
		var id := int(entry["id"])
		if is_level_unlocked(id) and not Save.is_level_complete(id):
			return id
	# Everything is clear: offer the last level for a victory lap.
	return int(levels[levels.size() - 1]["id"]) if not levels.is_empty() else 1


func first_level_of_region(region_id: int) -> int:
	var ids := level_ids_in_region(region_id)
	return int(ids[0]) if not ids.is_empty() else 1


func total_stars_possible() -> int:
	return levels.size() * 3


func unlocked_region_count() -> int:
	var count := 0
	for entry in regions:
		if region_unlocked(int(entry["id"])):
			count += 1
	return count


func daily_seed() -> int:
	var now := Time.get_date_dict_from_system()
	return int(now.year) * 10000 + int(now.month) * 100 + int(now.day)


func daily_level() -> Dictionary:
	# The daily challenge reuses the campaign's level shape with a seeded
	# distance and a shared seed, so every player gets the same road today.
	var seed_value := daily_seed()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var region_id := rng.randi_range(1, maxi(1, unlocked_region_count()))
	var base := level(first_level_of_region(region_id))
	var copy: Dictionary = base.duplicate(true)
	copy["id"] = 0
	copy["name"] = "Daily Route"
	copy["len"] = 520 + (seed_value % 5) * 60
	copy["spd"] = [10.5 + float(seed_value % 7) * 0.35, 15.0 + float(seed_value % 5) * 0.4]
	copy["daily_seed"] = seed_value
	return copy
