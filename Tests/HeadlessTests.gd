extends Node
## Headless checks for the shipped campaign data and the run scene.
##
##   godot --headless --path . Tests/Tests.tscn
##
## Exits non-zero on any failure so CI can gate on it.

var failures := 0
var checks := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func _ready() -> void:
	await get_tree().process_frame
	_test_campaign()
	_test_save()
	await _test_run_scene("campaign", 1)
	await _test_run_scene("endless", 0)
	await _test_run_scene("daily", 0)
	print("checks: %d, failures: %d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _test_campaign() -> void:
	check(Campaign.loaded, "campaign data loads")
	check(Campaign.levels.size() == 500, "500 levels are present (found %d)" % Campaign.levels.size())
	check(Campaign.regions.size() == 20, "20 regions are present")
	var total_rows := 0
	for region_id in range(1, 21):
		var ids := Campaign.level_ids_in_region(region_id)
		check(ids.size() == 25, "region %d has 25 levels (found %d)" % [region_id, ids.size()])
	for entry in Campaign.levels:
		var id := int(entry["id"])
		var length := float(entry["len"])
		var rows: Array = entry.get("rows", [])
		check(length > 150.0 and length <= 900.0, "level %d length is sane" % id)
		check(rows.size() >= 8, "level %d has obstacle rows" % id)
		total_rows += rows.size()
		var previous_z := 0.0
		var reachable := {0: true}
		var speed_range: Array = entry["spd"]
		for row in rows:
			var z := float(row["z"])
			var cells: Array = row["c"]
			check(cells.size() == 3, "level %d row has three lanes" % id)
			var free: Array = []
			for lane_index in range(3):
				if String(cells[lane_index]) != "x" and String(cells[lane_index]) != "m":
					free.append(lane_index - 1)
			check(free.size() >= 1, "level %d row at %.1f leaves a lane open" % [id, z])
			var speed := float(speed_range[0])
			var reaction := (z - previous_z) / maxf(speed, 0.001)
			check(reaction >= 0.9 or previous_z <= 0.0, "level %d row gap is fair" % id)
			var reachable_free := false
			for lane in free:
				for offset in [-1, 0, 1]:
					if reachable.has(lane + offset):
						reachable_free = true
			check(reachable_free, "level %d row at %.1f is reachable" % [id, z])
			reachable = {}
			for lane in free:
				reachable[lane] = true
			previous_z = z
		var sparks: Array = entry.get("sparks", [])
		check(sparks.size() > 3, "level %d has sparks" % id)
		var route: Array = entry.get("route", [])
		check(route.size() == rows.size(), "level %d ships a route" % id)
		var route_lane := 0
		for spark in sparks:
			var spark_z := float(spark[0])
			for route_entry in route:
				if float(route_entry[0]) > spark_z:
					break
				route_lane = int(route_entry[1])
			check(int(spark[1]) == route_lane, "level %d spark at %.0f is on the route" % [id, spark_z])
		check(not entry.get("powers", []).is_empty(), "level %d has a power-up" % id)
		check(entry.get("relics", []).size() >= 2, "level %d has relics" % id)
	check(total_rows > 3000, "campaign has enough obstacle rows (found %d)" % total_rows)
	var daily := Campaign.daily_level()
	check(not daily.is_empty(), "daily level builds")
	check(float(daily.get("len", 0)) > 300.0, "daily level has a real length")


func _test_save() -> void:
	var before := Save.total_stars()
	check(before >= 0, "stars are readable")
	var json := JSON.stringify(Save.data)
	var parsed: Variant = JSON.parse_string(json)
	check(typeof(parsed) == TYPE_DICTIONARY, "save serialises to JSON")
	check(Save.data.has("schema"), "save has a schema version")
	check(int(Save.data["schema"]) >= 2, "save schema is migrated")
	check(Roster.all().size() == 8, "eight Trailblazers are defined")
	for entry in Roster.all():
		check(not String(entry["id"]).is_empty(), "character has an id")
	check(PowerUps.ORDER.size() >= 10, "ten power-ups are defined")
	for id in PowerUps.ORDER:
		check(PowerUps.exists(id), "power-up %s exists" % id)
		check(PowerUps.display_name(id) != id, "power-up %s has a display name" % id)


func _test_run_scene(mode: String, level_id: int) -> void:
	var packed: PackedScene = load("res://Scenes/Run.tscn")
	check(packed != null, "run scene loads")
	if packed == null:
		return
	var run := packed.instantiate()
	# A parse error in Run.gd would otherwise leave a bare Node3D and silently
	# pass every gameplay assertion below.
	check(run.has_method("setup"), "%s run scene script compiles" % mode)
	if not run.has_method("setup"):
		run.free()
		return
	run.call("setup", {"mode": mode, "level_id": level_id})
	add_child(run)
	await get_tree().process_frame
	await get_tree().physics_frame
	check(run.get("level") != null and not (run.get("level") as Dictionary).is_empty(), "%s run resolves a level" % mode)
	check(run.get("track") != null, "%s run builds a track" % mode)
	check(run.get("player") != null, "%s run builds a player" % mode)
	var track = run.get("track")
	check(track.hazards.size() > 0, "%s run has obstacles" % mode)
	check(track.sparks.size() > 0, "%s run has sparks" % mode)
	run.call("_start_run")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var distance := float(run.get("distance"))
	check(distance > 0.0, "%s run advances distance" % mode)
	run.queue_free()
	await get_tree().process_frame
