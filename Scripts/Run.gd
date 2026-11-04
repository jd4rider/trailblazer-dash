extends Node3D
## One run: campaign level, daily route or endless trail.

const MOODS := {
	1: "meadow", 2: "forest", 3: "coast", 4: "coast", 5: "forge",
	6: "meadow", 7: "aether", 8: "forest", 9: "forge", 10: "aether",
	11: "dune", 12: "forest", 13: "forge", 14: "meadow", 15: "forge",
	16: "coast", 17: "forge", 18: "aether", 19: "aether", 20: "meadow",
}

var mode := "campaign"
var level_id := 1
var level: Dictionary = {}
var region: Dictionary = {}

var player: RunnerPlayer
var camera: Camera3D
var track: TrackBuilder
var hud: RunHUD
var results: ResultsPanel
var ui_layer: CanvasLayer

var state := "ready"
var distance := 0.0
var speed := 0.0
var sparks := 0
var relics := 0
var score := 0
var elapsed := 0.0
var base_speed := 9.0
var top_speed := 12.0
var pause_panel: Control

var _penalty := 0.0
var _segment_start := 0.0
var _segment_index := 0
var _paused := false
var _overlay: Control
var _rng := RandomNumberGenerator.new()
var _pointer_down := false
var _pointer_start := Vector2.ZERO
var _pointer_ms := 0
var _last_touch_ms := -1000
var _tutorial_seen := false


func setup(args: Dictionary) -> void:
	mode = String(args.get("mode", "campaign"))
	level_id = int(args.get("level_id", 1))


func _ready() -> void:
	_rng.randomize()
	_resolve_level()
	_build_environment()
	_build_camera()
	_build_player()
	_build_track()
	_build_ui()
	_show_ready()
	Audio.play_music(String(MOODS.get(int(region.get("id", 1)), "meadow")))
	Audio.play_ambience(_ambience_bed())
	Audio.set_intensity(0.25)
	Save.flush()


func _resolve_level() -> void:
	match mode:
		"endless":
			level = Campaign.level(_endless_pick())
			region = Campaign.region(int(level.get("region", 1)))
		"daily":
			level = Campaign.daily_level()
			region = Campaign.region(int(level.get("region", 1)))
		_:
			level = Campaign.level(level_id)
			if level.is_empty():
				level = Campaign.level(1)
			region = Campaign.region(int(level.get("region", 1)))
	base_speed = float(level.get("spd", [9.0, 12.0])[0])
	top_speed = float(level.get("spd", [9.0, 12.0])[1])
	if mode == "endless":
		base_speed = 10.0
		top_speed = 13.5


func _endless_pick() -> int:
	var ids := Campaign.level_ids_in_region(_rng.randi_range(1, maxi(1, Campaign.unlocked_region_count())))
	return int(ids[_rng.randi_range(0, ids.size() - 1)])


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	var sky_color := Color(String(region.get("sky", "#9fd8ff")))
	var ground_color := Color(String(region.get("ground", "#6dbf5a")))
	sky_material.sky_top_color = sky_color.darkened(0.45)
	sky_material.sky_horizon_color = sky_color.darkened(0.1)
	sky_material.ground_horizon_color = ground_color.lightened(0.1)
	sky_material.ground_bottom_color = ground_color.darkened(0.55)
	sky_material.sun_angle_max = 22.0
	sky_material.sky_energy_multiplier = 0.7
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_energy_multiplier = 0.6
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.5
	environment.fog_enabled = true
	environment.fog_light_color = Color(String(region.get("fog", "#d9f0ff"))).darkened(0.18)
	environment.fog_density = 0.0035
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.82
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54, -36, 0)
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.shadow_enabled = Save.get_setting("quality", "auto") != "low"
	add_child(sun)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.set_script(load("res://Scripts/World/RunCamera.gd"))
	camera.set("reduced_motion", bool(Save.get_setting("reduced_motion", false)))
	add_child(camera)


func _build_player() -> void:
	var character := String(Save.data.get("profile", {}).get("character", "pip"))
	player = RunnerPlayer.new()
	player.name = "Player"
	add_child(player)
	player.setup(character, String(region.get("surface", "grass")))
	camera.set("target", player)
	player.stumbled.connect(_on_stumble)
	player.landed.connect(func() -> void:
		if camera.has_method("shake"):
			camera.call("shake", 0.25)
		if camera.has_method("dip"):
			camera.call("dip", 0.35))


func _build_track() -> void:
	track = TrackBuilder.new()
	track.name = "Track"
	add_child(track)
	track.build(level, region)
	track.position.z = 0.0


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 8
	add_child(ui_layer)
	hud = RunHUD.new()
	ui_layer.add_child(hud)
	hud.setup(level, mode)
	hud.pause_pressed.connect(_toggle_pause)


func _show_ready() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.08, 0.09, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var card := Ui.panel()
	card.custom_minimum_size = Vector2(430, 0)
	center.add_child(card)
	var inner := Ui.margin(24, 22, 24, 20)
	card.add_child(inner)
	var column := Ui.vbox(10)
	inner.add_child(column)
	column.add_child(Ui.label(Campaign.region_name(int(region.get("id", 1))).to_upper(),
		14, Ui.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	var heading := Campaign.level_title(level) if mode == "campaign" else String(level.get("name", "Daily Route"))
	column.add_child(Ui.title(heading, 32, Ui.INK, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(Ui.label("Three lanes. Swipe left or right to hop between them, up to jump the hurdles and pits, down to slide under the bars. Pick a free lane before the trains.",
		17, Ui.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	var controls := Ui.hbox(6)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_child(Ui.chip("SWIPE L / R  lanes", Color("#e6dcc7"), Ui.INK))
	controls.add_child(Ui.chip("SWIPE UP  jump", Color("#e6dcc7"), Ui.INK))
	controls.add_child(Ui.chip("SWIPE DOWN  slide", Color("#e6dcc7"), Ui.INK))
	column.add_child(controls)
	column.add_child(Ui.spacer(6))
	var run_button := Ui.button("START RUNNING", 24, true)
	run_button.pressed.connect(_start_run)
	column.add_child(run_button)
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.2)


func _start_run() -> void:
	if state != "ready":
		return
	state = "running"
	Audio.kick()
	Audio.play_sfx("gate", 1.0, -6.0)
	player.call("reset_state")
	player.set("active", true)
	_speed_penalty_reset()
	if _overlay:
		var tween := create_tween()
		tween.tween_property(_overlay, "modulate:a", 0.0, 0.2)
		tween.tween_callback(_overlay.queue_free)
		_overlay = null
	if not bool(Save.get_setting("tutorial_done", false)):
		Save.set_setting("tutorial_done", true)
		_tutorial_seen = true
		hud.flash_text("Collect the sparks. Light the beacon.", Ui.CREAM)


func _speed_penalty_reset() -> void:
	_penalty = 0.0


func _physics_process(delta: float) -> void:
	if state != "running" or _paused:
		return
	elapsed += delta
	var local := distance - _segment_start
	var progress := clampf(local / maxf(1.0, float(level.get("len", 400))), 0.0, 1.0)
	var multiplier := 1.0
	if player.has_power("speed"):
		multiplier *= 1.22
	if player.has_power("slow"):
		multiplier *= 0.88
	if _penalty > 0.0:
		multiplier *= 0.62
		_penalty -= delta
	speed = lerpf(base_speed, top_speed + _segment_index * 0.6, progress) * multiplier
	distance += speed * delta

	score += int(speed * delta * (2.0 if player.has_power("multiplier") else 1.0))
	var player_z := -(distance - _segment_start)
	# The trail bends, so the runner rides the same centreline the road, sparks and
	# obstacles were laid out along.
	player.set("graph_offset", track.curve_at(player_z))
	player.set("bank_slope", track.curve_slope(player_z))
	player.call("tick", delta, speed)
	track.update(delta, player_z, player.has_power("relic_finder"))
	# The runner and the camera stay put, so the world has to stream towards
	# them: without this the road is a frozen picture and the character runs on
	# the spot while the distance counter climbs.
	track.position.z = distance - _segment_start
	camera.call("set_speed_ratio", progress)
	camera.call("set_curve", track.curve_slope(player_z))

	_collect_sparks(player_z)
	_collect_pickups(player_z)
	_check_hazards(player_z)

	hud.update_state({
		"score": score,
		"sparks": sparks,
		"relics": relics,
		"distance": distance,
		"speed": speed,
		"hearts": maxi(0, _heart_max() - player.hits),
		"max_hearts": _heart_max(),
		"powers": player.active_powers(),
	})
	Audio.set_intensity(clampf(progress + sparks * 0.001, 0.0, 1.0))

	if mode == "endless":
		if distance - _segment_start >= float(level.get("len", 400)):
			_extend_endless()
		return
	if distance >= float(level.get("len", 400)):
		_finish_run()


func _heart_max() -> int:
	return int(level.get("hits", 2)) + 1


func _collect_sparks(player_z: float) -> void:
	var magnet := player.has_power("magnet")
	var pull_radius := 8.0 if magnet else 0.0
	for spark in track.sparks:
		if spark["collected"]:
			continue
		var z := float(spark["z"])
		if z > player_z + 30.0 or z < player_z - 14.0:
			continue
		var node: Node3D = spark["node"]
		if magnet and absf(z - player_z) < pull_radius:
			var direction := Vector3(player.position.x, 0.9, player_z) - node.position
			if direction.length() > 0.15:
				node.position += direction.normalized() * minf(direction.length(), 14.0 * get_physics_process_delta_time())
			spark["z"] = node.position.z
			z = node.position.z
		if absf(z - player_z) > 1.0:
			continue
		if absf(node.position.x - player.position.x) > 1.05:
			continue
		track.collect_spark(spark)
		var value := 2 if player.has_power("multiplier") else 1
		sparks += value
		score += 15 * value
		Audio.play_sfx("pickup_%d" % (randi() % 3), randf_range(0.96, 1.08), -10.0)


func _collect_pickups(player_z: float) -> void:
	for pickup in track.pickups:
		if pickup["taken"]:
			continue
		if absf(float(pickup["z"]) - player_z) > 1.05:
			continue
		if absf(float(pickup["x"]) - player.position.x) > 1.1:
			continue
		track.take_pickup(pickup)
		var type := String(pickup["type"])
		player.call("apply_power", type)
		score += 60
		if type == "lucky_spark":
			sparks += 20
			score += 300
		Audio.play_sfx("powerup", 1.0, -4.0)
		hud.flash_power(type)

	for relic in track.relics:
		if relic["found"]:
			continue
		if absf(float(relic["z"]) - player_z) > 1.05:
			continue
		if absf(float(relic["x"]) - player.position.x) > 1.15:
			continue
		track.take_relic(relic)
		relics += 1
		score += 250
		Audio.play_sfx("relic", 1.0, -3.0)
		hud.flash_text("Relic recovered", Color("#d8c4ff"))


func _check_hazards(player_z: float) -> void:
	# Compare lane offsets rather than world X: on a curved trail the whole lane
	# slides sideways in world space, but the lane the runner occupies does not.
	var lane_offset := player.position.x - track.curve_at(player_z)
	for hazard in track.hazards:
		if hazard["hit"]:
			continue
		var z := float(hazard["z"])
		var reach := float(hazard.get("len", 0.0))
		if reach > 0.0:
			# Long hazards (trains) are a stretch of lane, not a thin plane.
			if player_z > z + 0.7 or player_z < z - reach - 0.7:
				continue
		elif absf(z - player_z) > 1.05:
			continue
		if not bool(hazard.get("wide", false)):
			if absf(Playfield.lane_x(int(hazard["lane"])) - lane_offset) > 1.06:
				continue
		var feet := player.y
		var head := player.y + player.height()
		if head <= float(hazard["bottom"]) or feet >= float(hazard["top"]):
			continue
		if String(hazard["kind"]) == "h" and player.has_power("hover"):
			continue
		hazard["hit"] = true
		track.hide_hazard(hazard)
		if bool(hazard.get("fatal", false)):
			Audio.play_sfx("hit", 0.72, 2.0)
			camera.call("shake", 3.0)
			_fail_run()
			return
		var result := String(player.call("take_hit"))
		if result == "ignored":
			continue
		if result == "shield":
			camera.call("shake", 0.7)
			hud.flash_text("Shield held", Color("#a9e6ff"))
			continue
		_penalty = 0.9
		camera.call("shake", 1.5)
		if player.hits > int(level.get("hits", 2)):
			_fail_run()
			return


func _extend_endless() -> void:
	_segment_index += 1
	_segment_start = distance
	var next_id := _endless_pick()
	level = Campaign.level(next_id)
	region = Campaign.region(int(level.get("region", 1)))
	if track and is_instance_valid(track):
		track.queue_free()
	track = TrackBuilder.new()
	add_child(track)
	track.build(level, region)
	track.position.z = 0.0
	hud.flash_text("New country · %s" % Campaign.region_name(int(region.get("id", 1))), Ui.CREAM)
	Audio.play_sfx("gate", 0.95, -6.0)


func _on_stumble() -> void:
	if state != "running":
		return
	_penalty += 0.55
	speed = maxf(base_speed * 0.55, speed - 2.4)
	if camera.has_method("shake"):
		camera.call("shake", 1.1)
	Audio.play_sfx("hit", 1.0, -4.0)
	hud.flash_text("Stumble!", Ui.CORAL)


func _finish_run() -> void:
	if state != "running":
		return
	state = "finished"
	player.call("celebrate")
	Audio.play_sfx("beacon", 1.0, -2.0)
	Audio.play_sfx("star", 1.0, -2.0)
	camera.call("shake", 0.4)

	var stars := _stars()
	var objective_met := _objective_met()
	var perfect := player.hits == 0
	var unlocked: Array = []
	if mode == "campaign":
		unlocked = Save.complete_level(int(level.get("id", level_id)), stars, score,
			sparks, relics, elapsed, player.hits, perfect)
	elif mode == "daily":
		unlocked = Save.record_daily(score, int(distance))
	else:
		unlocked = Save.add_endless(int(distance), score)
	Arcade.track("run_complete", {
		"mode": mode,
		"level": int(level.get("id", 0)),
		"stars": stars,
		"score": score,
		"sparks": sparks,
	})
	Audio.set_intensity(1.0)
	await get_tree().create_timer(0.7).timeout
	_show_results(true, stars, objective_met, unlocked)


func _fail_run() -> void:
	if state != "running":
		return
	state = "failed"
	player.call("fall")
	camera.call("shake", 2.0)
	Audio.play_sfx("hit", 1.0, -2.0)
	var unlocked: Array = []
	if mode == "endless":
		unlocked = Save.add_endless(int(distance), score)
	elif mode == "daily":
		unlocked = Save.record_daily(score, int(distance))
	Arcade.track("run_failed", {"mode": mode, "distance": int(distance)})
	await get_tree().create_timer(0.55).timeout
	_show_results(false, 0, false, unlocked)


func _objective_met() -> bool:
	var objective: Dictionary = level.get("obj", {})
	match String(objective.get("t", "sparks")):
		"sparks":
			return sparks >= int(objective.get("n", 0))
		"relics":
			return relics >= int(objective.get("n", 0))
		"clean":
			return player.hits == 0
		"time":
			return elapsed <= float(level.get("dur", 60)) * 1.3
		_:
			return true


func _stars() -> int:
	if not _objective_met():
		return 1
	var stars := 2
	var three: Dictionary = level.get("star", {})
	match String(three.get("three", "clean")):
		"clean":
			if player.hits == 0:
				stars = 3
		"relics":
			if relics >= int(three.get("n", 3)):
				stars = 3
		"time":
			if elapsed <= float(level.get("dur", 60)) * 1.15:
				stars = 3
	return stars


func _show_results(success: bool, stars: int, objective_met: bool, unlocked: Array) -> void:
	results = ResultsPanel.new()
	ui_layer.add_child(results)
	var rows: Array = [
		["Score", Ui.format_number(score)],
		["Sparks", str(sparks)],
		["Relics", str(relics)],
		["Distance", "%d m" % int(distance)],
		["Time", Ui.format_time(elapsed)],
	]
	var title := "Beacon Lit" if success else "The Trail Won"
	if mode == "endless":
		title = "Run Ended"
		rows = [
			["Distance", "%d m" % int(distance)],
			["Best ever", "%d m" % int(Save.data["records"]["endless_best"])],
			["Score", Ui.format_number(score)],
			["Sparks", str(sparks)],
		]
	elif mode == "daily":
		title = "Daily Route Done" if success else "Daily Route Ended"
		rows = [
			["Score", Ui.format_number(score)],
			["Distance", "%d m" % int(distance)],
			["Streak", "%d days" % int(Save.data["records"]["daily_streak"])],
		]
	var subtitle := ""
	if mode == "campaign":
		subtitle = Campaign.region_name(int(region.get("id", 1)))
		if success and not objective_met:
			subtitle += " · objective missed, but the beacon is yours"
	var primary := "CONTINUE JOURNEY"
	if mode == "endless":
		primary = "RUN AGAIN"
	elif mode == "daily":
		primary = "BACK TO THE TRAIL"
	results.show_result({
		"success": success,
		"title": title,
		"subtitle": subtitle,
		"stars": stars,
		"rows": rows,
		"achievements": unlocked,
		"primary": primary,
		"allow_retry": true,
	})
	results.action.connect(_on_result_action.bind(success))


func _on_result_action(action: String, success: bool) -> void:
	match action:
		"retry":
			Router.go("run", {"mode": mode, "level_id": level_id}, false)
		"map":
			Router.go("map", {"region": int(region.get("id", 1))})
		_:
			if not success:
				Router.go("run", {"mode": mode, "level_id": level_id}, false)
			elif mode == "campaign":
				var next := int(level.get("id", level_id)) + 1
				if next > Campaign.TOTAL_LEVELS:
					Router.go("map", {"region": int(region.get("id", 1))})
				else:
					Router.go("run", {"mode": "campaign", "level_id": next})
			else:
				Router.go("map", {"region": int(region.get("id", 1))})


func _toggle_pause() -> void:
	if state != "running" and not _paused:
		return
	_paused = not _paused
	if _paused:
		Audio.ui_click()
		_show_pause()
	else:
		if pause_panel and is_instance_valid(pause_panel):
			pause_panel.queue_free()
			pause_panel = null


func _show_pause() -> void:
	pause_panel = Control.new()
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.07, 0.08, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(center)
	var card := Ui.panel()
	card.custom_minimum_size = Vector2(380, 0)
	center.add_child(card)
	var inner := Ui.margin(24, 22, 24, 20)
	card.add_child(inner)
	var column := Ui.vbox(10)
	inner.add_child(column)
	column.add_child(Ui.title("Paused", 38, Ui.INK, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(Ui.label("%s · %d m" % [Campaign.region_name(int(region.get("id", 1))), int(distance)],
		17, Ui.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	var resume := Ui.button("KEEP RUNNING", 22, true)
	resume.pressed.connect(_toggle_pause)
	column.add_child(resume)
	var restart := Ui.button("RESTART RUN", 19)
	restart.pressed.connect(func() -> void:
		Router.go("run", {"mode": mode, "level_id": level_id}, false))
	column.add_child(restart)
	var map_button := Ui.button("WORLD MAP", 19)
	map_button.pressed.connect(func() -> void:
		Router.go("map", {"region": int(region.get("id", 1))}))
	column.add_child(map_button)


func _ambience_bed() -> String:
	var tags: Array = region.get("ambience", [])
	for tag in tags:
		match String(tag):
			"birds", "meadow":
				return "birds"
			"forest", "leaves", "jungle", "insects":
				return "forest"
			"river", "water", "marsh", "frogs", "drips":
				return "water"
			"waves", "gulls", "coast", "seabirds", "harbor":
				return "waves"
			"machinery", "gears", "city", "sawmill", "engines", "timber":
				return "machinery"
			"cave", "resonance", "echo", "ruins":
				return "cave"
			"storm", "rain", "thunder":
				return "storm"
			"desert", "night":
				return "desert"
			"lava", "rumble", "steam":
				return "lava"
			"alpine", "eagle", "snow", "ice", "altitude":
				return "alpine"
			"garden", "chimes", "aether", "choir":
				return "garden"
	return "wind"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if state == "ready":
		if event.is_action_pressed("jump") or event.is_action_pressed("ui_accept"):
			_start_run()
			get_viewport().set_input_as_handled()
		return
	if state != "running" or _paused:
		return
	if event.is_action_pressed("move_left"):
		_move(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_move(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jump"):
		player.call("jump")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("slide"):
		player.call("slide")
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_pointer(touch.position, touch.pressed, true)
	elif event is InputEventScreenDrag:
		_pointer_move((event as InputEventScreenDrag).position)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		# Godot's web build also mirrors a finger as a mouse press; ignore the
		# duplicate so one swipe cannot fire twice or reset itself.
		if button.button_index == MOUSE_BUTTON_LEFT and Time.get_ticks_msec() - _last_touch_ms > 150:
			_pointer(button.position, button.pressed, false)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and Time.get_ticks_msec() - _last_touch_ms > 150:
			_pointer_move(motion.position)


func _pointer(position: Vector2, pressed: bool, is_touch: bool) -> void:
	if is_touch:
		_last_touch_ms = Time.get_ticks_msec()
	if pressed:
		# The top strip belongs to the HUD: a tap on pause must not also jump.
		if position.y < 130.0:
			_pointer_down = false
			return
		_pointer_down = true
		_pointer_start = position
		_pointer_ms = Time.get_ticks_msec()
		return
	if not _pointer_down:
		return
	_pointer_down = false
	var delta := position - _pointer_start
	if delta.length() < 26.0 and Time.get_ticks_msec() - _pointer_ms < 300:
		player.call("jump")
	else:
		_swipe(delta)


func _pointer_move(position: Vector2) -> void:
	if not _pointer_down:
		return
	var delta := position - _pointer_start
	if delta.length() < Playfield.SWIPE_THRESHOLD:
		return
	_swipe(delta)
	# Continue from here: one long drag can cross two lanes.
	_pointer_start = position


func _swipe(delta: Vector2) -> void:
	if absf(delta.x) > absf(delta.y) * 0.85:
		_move(1 if delta.x > 0.0 else -1)
	elif delta.y < 0.0:
		player.call("jump")
	else:
		player.call("slide")


func _move(direction: int) -> void:
	if player.call("move_lane", direction):
		Audio.play_sfx("ui_click", 1.15, -14.0)
