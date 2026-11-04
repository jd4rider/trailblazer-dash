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
	_test_track_extras()
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


func _mesh_width(node: Node3D) -> float:
	var out := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out.size.x


func _count_kind(hazards: Array, kind: String) -> int:
	var total := 0
	for hazard in hazards:
		if String(hazard["kind"]) == kind:
			total += 1
	return total


## Trains, pits and the curving trail are built at runtime rather than living in
## the campaign JSON, so they get their own checks on real levels.
func _feet_height(player: Node3D, body: Node3D) -> float:
	var lowest := 0.0
	var first := true
	for child in body.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local := player.global_transform.affine_inverse() * mesh_instance.global_transform
		var box: AABB = local * mesh_instance.mesh.get_aabb()
		lowest = box.position.y if first else minf(lowest, box.position.y)
		first = false
	return lowest


## A full-rect Control on the default mouse filter swallowed every swipe on a real
## phone while every headless assertion still passed.
func _pointer_blockers(node: Node, point: Vector2) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Control:
			var control := child as Control
			if control.mouse_filter == Control.MOUSE_FILTER_STOP and not (control is BaseButton):
				if control.get_global_rect().has_point(point):
					out.append("%s(%s)" % [control.get_class(), control.name])
		out.append_array(_pointer_blockers(child, point))
	return out


func _test_track_extras() -> void:
	var trains := 0
	var gaps := 0
	for id in [31, 120, 260, 400]:
		var entry := Campaign.level(id)
		check(not entry.is_empty(), "level %d exists for the track checks" % id)
		var track := TrackBuilder.new()
		add_child(track)
		track.build(entry, Campaign.region(int(entry.get("region", 1))))
		trains += _count_kind(track.hazards, "t")
		gaps += _count_kind(track.hazards, "g")
		for hazard in track.hazards:
			check(is_finite(float(hazard["z"])), "level %d hazard z is finite" % id)
			check(float(hazard["top"]) > float(hazard["bottom"]), "level %d hazard has a hit band" % id)
			# Every lane-bound hazard must sit exactly on the trail's lane centre at
			# its own Z, or a curve would put obstacles between the lanes.
			if String(hazard["kind"]) == "t" or bool(hazard.get("wide", false)):
				continue
			var expected := float(track.call("curve_at", float(hazard["z"]))) + Playfield.lane_x(int(hazard["lane"]))
			check(absf(expected - float(hazard["x"])) < 0.01,
				"level %d hazard sits on its lane" % id)
			var width := _mesh_width(hazard["node"] as Node3D)
			check(width <= 2.4,
				"level %d %s fits inside its lane (%.2f m)" % [id, String(hazard["kind"]), width])
		for i in range(60):
			var offset := absf(float(track.call("curve_at", -8.0 * i)))
			check(offset < 14.0, "level %d trail stays inside the playfield" % id)
		track.queue_free()
	check(trains > 0, "trains are placed on some levels")
	check(gaps > 0, "pits are placed on some levels")
	check(Playfield.LANE_WIDTH >= 2.8, "lanes are wide enough for three columns")
	check(Playfield.TRACK_WIDTH >= Playfield.LANE_WIDTH * 3.0, "the deck spans all three lanes")
	check(Playfield.SWIPE_THRESHOLD >= 44.0, "the swipe threshold is not twitchy")
	check(Playfield.SWIPE_AXIS_RATIO > 1.0, "a swipe locks to one axis")


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


func _settle_lane(run: Node, runner: Node) -> void:
	for i in range(90):
		if not bool(runner.call("is_changing_lane")):
			return
		await get_tree().physics_frame


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
	# A parse error in the HUD used to leave the counters missing while every
	# other assertion still passed, so check the HUD and its labels exist.
	var hud = run.get("hud")
	check(hud != null and hud.has_method("update_state"), "%s run builds a working HUD" % mode)
	check(hud != null and hud.get("_objective_label") != null, "%s HUD has its objective label" % mode)
	var track = run.get("track")
	check(track.hazards.size() > 0, "%s run has obstacles" % mode)
	check(track.sparks.size() > 0, "%s run has sparks" % mode)
	check(track.has_method("curve_at"), "%s track exposes its curve" % mode)
	check(track.has_method("curve_slope"), "%s track exposes its slope" % mode)
	run.call("_start_run")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var distance := float(run.get("distance"))
	check(distance > 0.0, "%s run advances distance" % mode)
	# Input mapping: the same touch path a finger takes, so a broken swipe shows
	# up here rather than only on a phone.
	var runner = run.get("player")
	var body = runner.get("model")
	check(body != null, "%s runner has a model" % mode)
	if body != null:
		var feet := _feet_height(runner, body)
		check(absf(feet) < 0.08, "%s runner's feet touch the trail (%.2f m)" % [mode, feet])
	var view_size: Vector2 = run.get_viewport().get_visible_rect().size
	var blockers := _pointer_blockers(hud, Vector2(view_size.x * 0.5, view_size.y * 0.66))
	check(blockers.is_empty(), "%s HUD lets swipes through (%s)" % [mode, ", ".join(blockers)])
	check(not bool(runner.get("airborne")), "%s runner starts grounded" % mode)
	# One gesture, one lane.
	run.call("_pointer", Vector2(220.0, 620.0), true, true)
	run.call("_pointer_move", Vector2(130.0, 618.0))
	await get_tree().physics_frame
	check(int(runner.get("lane")) == -1, "%s swipe left changes lane" % mode)
	# A single continuous drag used to chain a lane change every 38 px.
	for step in range(8):
		run.call("_pointer_move", Vector2(130.0 + 40.0 * (step + 1), 618.0))
	check(int(runner.get("lane")) == -1, "%s a long drag moves only one lane" % mode)
	run.call("_pointer", Vector2(450.0, 618.0), false, true)
	await _settle_lane(run, runner)
	# Flicking up mid-hop must not fire a jump.
	run.call("_pointer", Vector2(220.0, 620.0), true, true)
	run.call("_pointer_move", Vector2(300.0, 619.0))
	run.call("_pointer", Vector2(300.0, 619.0), false, true)
	run.call("_pointer", Vector2(220.0, 620.0), true, true)
	run.call("_pointer_move", Vector2(222.0, 500.0))
	check(not bool(runner.get("airborne")), "%s cannot jump while changing lane" % mode)
	run.call("_pointer", Vector2(222.0, 500.0), false, true)
	await _settle_lane(run, runner)
	check(int(runner.get("lane")) == 0, "%s swipe right returns to the centre" % mode)
	# An ambiguous diagonal does nothing rather than guessing.
	run.call("_pointer", Vector2(220.0, 620.0), true, true)
	run.call("_pointer_move", Vector2(260.0, 582.0))
	await get_tree().physics_frame
	check(int(runner.get("lane")) == 0 and not bool(runner.get("airborne")), "%s diagonal drag does nothing" % mode)
	run.call("_pointer", Vector2(260.0, 582.0), false, true)
	await _settle_lane(run, runner)
	# Up jumps, once the hop has settled.
	run.call("_pointer", Vector2(220.0, 620.0), true, true)
	run.call("_pointer_move", Vector2(222.0, 500.0))
	check(bool(runner.get("airborne")), "%s swipe up jumps" % mode)
	run.call("_pointer", Vector2(222.0, 500.0), false, true)
	await get_tree().physics_frame
	run.call("_pointer", Vector2(220.0, 620.0), true, true)
	run.call("_pointer_move", Vector2(230.0, 730.0))
	check(bool(runner.get("sliding")), "%s swipe down slides" % mode)
	run.call("_pointer", Vector2(230.0, 730.0), false, true)
	var world_x := float(runner.get("position").x)
	check(is_finite(world_x), "%s runner world position is finite" % mode)
	run.queue_free()
	await get_tree().process_frame
