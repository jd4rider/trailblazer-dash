class_name PowerUps
## The power-up catalogue. Effects live in RunnerPlayer / Run; this is the data
## that the HUD, drop pools and results screen share.

const CATALOG := {
	"magnet": {
		"name": "Spark Magnet",
		"glyph": "MG",
		"color": "#e8a33d",
		"duration": 9.0,
		"blurb": "Nearby sparks drift to you.",
	},
	"shield": {
		"name": "Wayfinder Shield",
		"glyph": "SH",
		"color": "#4aa3c7",
		"duration": 0.0,
		"blurb": "Soaks up one stumble.",
	},
	"speed": {
		"name": "Trail Speed",
		"glyph": "SP",
		"color": "#dd6a4f",
		"duration": 7.0,
		"blurb": "Faster running, bigger score.",
	},
	"slow": {
		"name": "Slow Time",
		"glyph": "SL",
		"color": "#7a6cd6",
		"duration": 6.0,
		"blurb": "The world eases off for a moment.",
	},
	"double_jump": {
		"name": "Double Jump",
		"glyph": "DJ",
		"color": "#4f9d69",
		"duration": 22.0,
		"blurb": "One extra jump while it lasts.",
	},
	"hover": {
		"name": "Hover Boots",
		"glyph": "HV",
		"color": "#8ecbff",
		"duration": 7.0,
		"blurb": "Skim over low hurdles.",
	},
	"multiplier": {
		"name": "Spark Multiplier",
		"glyph": "x2",
		"color": "#ffd166",
		"duration": 12.0,
		"blurb": "Every spark counts twice.",
	},
	"relic_finder": {
		"name": "Relic Finder",
		"glyph": "RF",
		"color": "#b99cff",
		"duration": 18.0,
		"blurb": "Marks relics with a light beam.",
	},
	"long_slide": {
		"name": "Long Slide",
		"glyph": "LS",
		"color": "#86ffd0",
		"duration": 20.0,
		"blurb": "Slides last noticeably longer.",
	},
	"lucky_spark": {
		"name": "Lucky Sparks",
		"glyph": "LK",
		"color": "#ffe6a1",
		"duration": 0.0,
		"blurb": "A pocketful of sparks, right now.",
	},
}

const ORDER := ["magnet", "shield", "speed", "slow", "double_jump",
	"hover", "multiplier", "relic_finder", "long_slide", "lucky_spark"]


static func exists(id: String) -> bool:
	return CATALOG.has(id)


static func info(id: String) -> Dictionary:
	return CATALOG.get(id, {})


static func display_name(id: String) -> String:
	return String(CATALOG.get(id, {}).get("name", id))


static func duration(id: String) -> float:
	return float(CATALOG.get(id, {}).get("duration", 0.0))


static func color(id: String) -> Color:
	return Color(String(CATALOG.get(id, {}).get("color", "#ffffff")))


static func glyph(id: String) -> String:
	return String(CATALOG.get(id, {}).get("glyph", "?"))


static func is_timed(id: String) -> bool:
	return duration(id) > 0.0


## Deterministic roll for a crate. `pool` is the level's declared pool, so a
## level can never hand out something its world is not balanced for.
static func roll(pool: Array, rng: RandomNumberGenerator) -> String:
	var options: Array = []
	for id in pool:
		if CATALOG.has(String(id)):
			options.append(String(id))
	if options.is_empty():
		options = ORDER.duplicate()
	return options[rng.randi_range(0, options.size() - 1)]
