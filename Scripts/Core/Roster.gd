class_name Roster
## The eight Trailblazers. Each is an original character with its own outfit
## palette, accessory set and unlock price in stars.

const CHARACTERS := [
	{
		"id": "pip", "name": "Pip", "pronoun": "she/her",
		"blurb": "Cheerful apprentice Wayfinder. Pip mapped Sunmeadow's footpaths before she could read the old signs.",
		"outfit": "#2f7d78", "accent": "#e8a33d", "stars": 0,
	},
	{
		"id": "nova", "name": "Nova", "pronoun": "they/them",
		"blurb": "Stargazer who reads the beacon network like a constellation. Never seen without three spare lanterns.",
		"outfit": "#4a3b8f", "accent": "#ffd166", "stars": 6,
	},
	{
		"id": "bram", "name": "Bram", "pronoun": "he/him",
		"blurb": "Mountain guide. Says the Cloudpeak trail is 'basically flat' and means it affectionately.",
		"outfit": "#8a4b32", "accent": "#d8c4a0", "stars": 12,
	},
	{
		"id": "lumi", "name": "Lumi", "pronoun": "she/her",
		"blurb": "Forest listener. Knows which Whiskerwood trees creak a warning and which creak a greeting.",
		"outfit": "#3f7d4f", "accent": "#d5ff9f", "stars": 20,
	},
	{
		"id": "tiko", "name": "Tiko", "pronoun": "he/him",
		"blurb": "Clockwork City inventor. His boots have fourteen settings and only nine of them are safe.",
		"outfit": "#a8642f", "accent": "#8ee8ff", "stars": 32,
	},
	{
		"id": "mira", "name": "Mira", "pronoun": "she/her",
		"blurb": "Coastal navigator. Reads a tide by the sound it makes against a hull.",
		"outfit": "#1f6f8f", "accent": "#ffe6a1", "stars": 45,
	},
	{
		"id": "rook", "name": "Rook", "pronoun": "they/them",
		"blurb": "Ironwood mechanic who rebuilt a beacon with a hammer, a spare gear and a lot of confidence.",
		"outfit": "#5c5f66", "accent": "#ff9a4d", "stars": 60,
	},
	{
		"id": "sol", "name": "Sol", "pronoun": "he/him",
		"blurb": "The last of the first Wayfinders. Carries the original compass and very little patience.",
		"outfit": "#8a6a1f", "accent": "#fff0bf", "stars": 90,
	},
]


static func all() -> Array:
	return CHARACTERS


static func get_character(id: String) -> Dictionary:
	for entry in CHARACTERS:
		if String(entry["id"]) == id:
			return entry
	return CHARACTERS[0]


static func is_unlocked(id: String) -> bool:
	var progress_unlocked: Array = Save.data.get("progress", {}).get("unlocked", ["pip"])
	if progress_unlocked.has(id):
		return true
	var entry := get_character(id)
	return Save.total_stars() >= int(entry.get("stars", 999))


static func next_locked() -> Dictionary:
	for entry in CHARACTERS:
		if not is_unlocked(String(entry["id"])):
			return entry
	return {}


static func unlock_cost(id: String) -> int:
	return int(get_character(id).get("stars", 0))
