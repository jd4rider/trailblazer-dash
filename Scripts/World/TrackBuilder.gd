class_name TrackBuilder
extends Node3D
## Replays a validated level as 3D geometry.
##
## Obstacles, sparks, crates and relics are read straight out of the campaign
## JSON. Nothing here generates layout, so the fairness report describes exactly
## what the player runs through.

const PROPS := "res://Assets/Models/props/"
const OBSTACLE_MODELS := {
	"h": "hurdle",
	"b": "overhead_bar",
	"x": "block_wall",
	"m": "boulder",
}
## Widest an obstacle may be, including its horizontal diagonal so a boulder
## turned at a random angle still clears the next lane.
const OBSTACLE_MAX_WIDTH := 2.0

const COLLISION := {
	"h": {"bottom": 0.0, "top": 1.03},
	"b": {"bottom": 1.10, "top": 3.0},
	"x": {"bottom": 0.0, "top": 2.7},
	"m": {"bottom": 0.0, "top": 1.95},
}

var level: Dictionary = {}
var region: Dictionary = {}
var hazards: Array = []
var sparks: Array = []
var pickups: Array = []
var relics: Array = []
var finish_z := -400.0
var level_length := 400.0

const TRAIN_COLORS := ["#e2564b", "#3f8fd0", "#f0b429", "#4fae86", "#8b6bd6"]

const OBSTACLE_COLORS := {
	"h": "#c8873f",
	"b": "#2f7d78",
	"x": "#8d8477",
	"m": "#7b7166",
}

var _rng := RandomNumberGenerator.new()
var _tile_materials: Dictionary = {}
var _ground_color := Color("#6dbf5a")
var _accent_color := Color("#ffd166")
var _paint_cache: Dictionary = {}

# The trail meanders: two slow sine sweeps added together, seeded per level, so
# the road, the pickups and the runner all share one centreline.
var _curve_on := false
var _curve_amp := 0.0
var _curve_freq := 0.0
var _curve_phase := 0.0
var _curve_amp2 := 0.0
var _curve_freq2 := 0.0
var _curve_phase2 := 0.0


func build(level_data: Dictionary, region_data: Dictionary) -> void:
	level = level_data
	region = region_data
	level_length = float(level.get("len", 400))
	finish_z = -level_length
	_rng.seed = int(level.get("seed", 1)) + 17
	_setup_curve()
	_build_tile_materials()
	_build_ground()
	_build_tiles()
	_build_obstacles()
	_build_trains()
	_build_gaps()
	_build_sparks()
	_build_pickups()
	_build_relics()
	_build_scenery()
	_build_markers()


## Lateral centre of the trail at a world Z. Z runs negative into the distance,
## so one function plots the road, the pickups and the runner.
func curve_at(z: float) -> float:
	if not _curve_on:
		return 0.0
	return (
		_curve_amp * sin(z * _curve_freq + _curve_phase)
		+ _curve_amp2 * sin(z * _curve_freq2 + _curve_phase2)
	)


## dX/dZ of the centreline, used to turn slabs and lean the chase camera.
func curve_slope(z: float) -> float:
	if not _curve_on:
		return 0.0
	return (
		_curve_amp * _curve_freq * cos(z * _curve_freq + _curve_phase)
		+ _curve_amp2 * _curve_freq2 * cos(z * _curve_freq2 + _curve_phase2)
	)


func _world_x(lane: int, z: float) -> float:
	return curve_at(z) + Playfield.lane_x(lane)


func _face_curve(node: Node3D, z: float) -> void:
	node.rotation.y = atan(curve_slope(z))


func _setup_curve() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(level.get("seed", 1)) * 31 + 7
	# The opening levels stay dead straight so the tutorial never tucks an
	# obstacle behind a bend; later regions sweep harder.
	_curve_on = int(level.get("local", 1)) > 2
	if not _curve_on:
		return
	var bite := clampf(float(level.get("diff", 0.0)), 0.0, 1.0)
	# Wide sweeping bends with a shorter wiggle on top, so a corner is visible far
	# enough ahead to choose a lane for it.
	_curve_amp = rng.randf_range(3.6, 6.0) * (0.75 + bite * 0.35)
	_curve_freq = rng.randf_range(0.0180, 0.0270)
	_curve_phase = rng.randf() * TAU
	_curve_amp2 = rng.randf_range(1.2, 2.4)
	_curve_freq2 = rng.randf_range(0.0400, 0.0580)
	_curve_phase2 = rng.randf() * TAU


func _material(color: Color, emissive := 0.0) -> StandardMaterial3D:
	var key := "m|%s|%.2f" % [color.to_html(), emissive]
	var material: StandardMaterial3D = _paint_cache.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.7
		material.metallic = 0.05
		if emissive > 0.0:
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = emissive
		_paint_cache[key] = material
	return material


func _surface_material(color: Color, emissive := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.metallic = 0.0
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.55
	return material


func _build_tile_materials() -> void:
	var ground := Color(String(region.get("ground", "#6dbf5a")))
	var accent := Color(String(region.get("accent", "#ffd166")))
	_ground_color = ground
	_accent_color = accent
	# The deck is lifted and the country dropped away from it: on a single-colour
	# region (a desert, a snowfield) the trail otherwise vanishes into the terrain.
	# The deck is its own warm path surface rather than a tint of the local grass:
	# on a green region or a snowfield a same-hue trail simply disappears.
	_tile_materials["tile_ground"] = _surface_material(
		accent.lerp(Color("#f4e7c8"), 0.62).lightened(0.06))
	_tile_materials["tile_edge"] = _surface_material(accent.lerp(Color("#6b4f34"), 0.7))
	_tile_materials["tile_accent"] = _surface_material(accent, true)


## The Blender props share one near-white material, so they are repainted here
## with the region palette. Materials are cached: one per colour per level.
func _paint(node: Node3D, color: Color, emissive := 0.0) -> void:
	var key := "%s|%.2f" % [color.to_html(), emissive]
	var material: StandardMaterial3D = _paint_cache.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.7
		material.metallic = 0.05
		if emissive > 0.0:
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = emissive
		_paint_cache[key] = material
	for child in node.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = material


func _scenery_color(prop: String) -> Color:
	if prop.begins_with("tree"):
		return _ground_color.darkened(0.3)
	if prop.begins_with("fern") or prop.begins_with("bush") or prop.begins_with("grass"):
		return _ground_color.darkened(0.08)
	if prop.begins_with("rock") or prop.begins_with("boulder"):
		return Color("#8b8378")
	if prop.begins_with("mushroom"):
		return Color("#dd6a4f")
	if prop.begins_with("banner") or prop.begins_with("gate") or prop.begins_with("beacon") or prop.begins_with("finish"):
		return _accent_color
	return _ground_color.lightened(0.04)


func _instance(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path)
	var node: Node3D = packed.instantiate() as Node3D
	add_child(node)
	return node


## Country either side of the trail. Without it every tree and rock hung in the
## sky beside the road.
func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var slab := BoxMesh.new()
	slab.size = Vector3(170.0, 0.8, level_length + 260.0)
	ground.mesh = slab
	var material := _material(_ground_color.darkened(0.52))
	material.roughness = 1.0
	ground.material_override = material
	# The country sits a step below the deck, which gives the trail a visible
	# kerb and makes the pits read as real holes.
	ground.position = Vector3(0, -1.0, -level_length * 0.5)
	add_child(ground)


func _build_tiles() -> void:
	# The road is built from primitives rather than the imported tile mesh: the
	# exported GLB carries near-white materials whose names do not survive import,
	# so tinting it per region silently produced a white track.
	# The trail runs towards negative Z (the player advances to -distance), so the
	# tiles step downwards in Z from just behind the start line.
	var z := 12.0
	var limit := finish_z - 60.0
	var index := 0
	while z > limit:
		var tile := Node3D.new()
		tile.name = "Tile%d" % index
		add_child(tile)
		tile.position = Vector3(curve_at(z), 0, z)
		tile.rotation.y = atan(curve_slope(z))

		var deck := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(9.4, 0.9, 13.4)
		deck.mesh = box
		deck.position = Vector3(0, -0.45, 0)
		deck.material_override = _tile_materials["tile_ground"]
		tile.add_child(deck)

		for side in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var rail_box := BoxMesh.new()
			rail_box.size = Vector3(0.6, 0.7, 13.4)
			rail.mesh = rail_box
			rail.position = Vector3(side * 4.7, 0.1, 0)
			rail.material_override = _tile_materials["tile_edge"]
			tile.add_child(rail)

		# Two dashed dividers make the three lanes readable at a glance. A single
		# centre stripe made the trail look like one wide lane.
		if index % 2 == 0:
			for divider in [-Playfield.LANE_WIDTH * 0.5, Playfield.LANE_WIDTH * 0.5]:
				var dash := MeshInstance3D.new()
				var dash_box := BoxMesh.new()
				dash_box.size = Vector3(0.24, 0.06, 3.6)
				dash.mesh = dash_box
				dash.position = Vector3(divider, 0.03, 0)
				dash.material_override = _tile_materials["tile_accent"]
				tile.add_child(dash)

		z -= 12.0
		index += 1


func _mesh_bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local := node.global_transform.affine_inverse() * mesh_instance.global_transform
		var box: AABB = local * mesh_instance.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## Shrinks a prop that is wider than a lane. Widening the lanes alone was not
## enough: the imported hurdle and overhead bar are 2.7 m and 3.3 m across.
func _fit_width(node: Node3D) -> void:
	var box := _mesh_bounds(node)
	var span := sqrt(box.size.x * box.size.x + box.size.z * box.size.z)
	if span < 0.01:
		return
	var factor := minf(1.0, OBSTACLE_MAX_WIDTH / span)
	if factor < 0.999:
		node.scale.x *= factor
		node.scale.z *= factor


func _build_obstacles() -> void:
	for row in level.get("rows", []):
		var z := float(row.get("z", 0.0))
		var cells: Array = row.get("c", [])
		for lane_index in range(min(3, cells.size())):
			var code := String(cells[lane_index])
			if code.is_empty() or not OBSTACLE_MODELS.has(code):
				continue
			var lane := lane_index - 1
			var node := _instance(PROPS + String(OBSTACLE_MODELS[code]) + ".glb")
			if node == null:
				continue
			var world_z := -z
			node.position = Vector3(_world_x(lane, world_z), 0, world_z)
			_face_curve(node, world_z)
			if code == "m":
				node.rotation.y = _rng.randf() * TAU
			if code == "x":
				node.scale = Vector3(1.0, _rng.randf_range(0.9, 1.1), 1.0)
			_fit_width(node)
			_paint(node, Color(String(OBSTACLE_COLORS.get(code, "#8d8477"))))
			hazards.append({
				"node": node,
				"lane": lane,
				"kind": code,
				"half": 0.95,
				"x": node.position.x,
				"z": world_z,
				"bottom": float(COLLISION[code]["bottom"]),
				"top": float(COLLISION[code]["top"]),
				"hit": false,
				"roll": 5.2 + _rng.randf() * 2.4,
				"spin": _rng.randf() * TAU,
			})


func _build_sparks() -> void:
	for entry in level.get("sparks", []):
		var base_z := float(entry[0])
		var lane := int(entry[1])
		var count := int(entry[2])
		for i in range(count):
			var node := _instance(PROPS + "spark.glb")
			if node == null:
				continue
			var z := -(base_z + i * 1.7)
			node.position = Vector3(_world_x(lane, z), 0.85, z)
			node.scale = Vector3.ONE * 0.8
			_paint(node, Color("#ffd166"), 0.9)
			sparks.append({
				"node": node,
				"z": z,
				"x": node.position.x,
				"collected": false,
				"phase": _rng.randf() * TAU,
				"base_y": 0.85,
			})


func _build_pickups() -> void:
	for entry in level.get("powers", []):
		var node := _instance(PROPS + "powerup_crate.glb")
		if node == null:
			continue
		var z := -float(entry[0])
		var lane := int(entry[1])
		node.position = Vector3(_world_x(lane, z), 1.0, z)
		_face_curve(node, z)
		_paint(node, _accent_color, 0.4)
		pickups.append({
			"node": node,
			"z": z,
			"x": node.position.x,
			"type": String(entry[2]),
			"taken": false,
			"phase": _rng.randf() * TAU,
		})


func _build_relics() -> void:
	for entry in level.get("relics", []):
		var node := _instance(PROPS + "relic.glb")
		if node == null:
			continue
		var z := -float(entry[0])
		var lane := int(entry[1])
		node.position = Vector3(_world_x(lane, z), 0.95, z)
		_face_curve(node, z)
		_paint(node, Color("#b99cff"), 0.6)
		var beam := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.10
		cylinder.bottom_radius = 0.32
		cylinder.height = 14.0
		cylinder.radial_segments = 8
		beam.mesh = cylinder
		var material := _surface_material(Color(1.0, 0.92, 0.66), true)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 0.92, 0.66, 0.35)
		beam.material_override = material
		beam.position = Vector3(0, 7.5, 0)
		beam.visible = false
		node.add_child(beam)
		relics.append({
			"node": node,
			"z": z,
			"x": node.position.x,
			"found": false,
			"phase": _rng.randf() * TAU,
			"beam": beam,
		})


func _build_scenery() -> void:
	var props: Array = region.get("props", [])
	if props.is_empty():
		return
	var z := 18.0
	var limit := finish_z - 40.0
	while z > limit:

		for side in [-1.0, 1.0]:
			if _rng.randf() < 0.78:
				var pick := String(props[_rng.randi_range(0, props.size() - 1)])
				var node := _instance(PROPS + pick + ".glb")
				if node == null:
					continue
				var place_z := z + _rng.randf_range(-5.0, 5.0)
				node.position = Vector3(
					curve_at(place_z) + side * _rng.randf_range(5.3, 9.8),
					-0.6,
					place_z)
				node.rotation.y = _rng.randf() * TAU
				var scale := _rng.randf_range(0.8, 1.4)
				node.scale = Vector3(scale, scale, scale)
				_paint(node, _scenery_color(pick))
		z -= 17.0

	var landmark := String(region.get("landmark", "beacon"))
	if ResourceLoader.exists(PROPS + landmark + ".glb"):
		var node := _instance(PROPS + landmark + ".glb")
		if node:
			node.position = Vector3(curve_at(finish_z * 0.5) - 7.4, -0.6, finish_z * 0.5)
			node.scale = Vector3(1.8, 1.8, 1.8)
			node.rotation.y = 0.5
			_paint(node, _accent_color, 0.35)


func _build_markers() -> void:
	var gate := _instance(PROPS + "finish_gate.glb")
	if gate:
		gate.position = Vector3(curve_at(finish_z), 0, finish_z)
		_paint(gate, _accent_color, 0.5)
	var beacon := _instance(PROPS + "beacon.glb")
	if beacon:
		beacon.position = Vector3(curve_at(finish_z - 9.0), 0, finish_z - 9.0)
		_paint(beacon, Color("#ffe9b0"), 0.8)
	for fraction in [0.34, 0.68]:
		var ring := _instance(PROPS + "gate.glb")
		if ring:
			ring.position = Vector3(curve_at(finish_z * fraction), 0, finish_z * fraction)
			ring.scale = Vector3(1.3, 1.3, 1.3)
			ring.rotation.y = PI / 2
			_paint(ring, Color("#9fe8ff"), 0.5)


## Trains are the centrepiece hazard: a whole lane, closed for twenty metres.
## They are never jumpable, so the only answer is to pick a free lane early.
func _build_trains() -> void:
	var rows: Array = level.get("rows", [])
	if rows.size() < 6:
		return
	var placed := 0
	var tries := 0
	while placed < 2 and tries < 20:
		tries += 1
		var lane := _rng.randi_range(-1, 1)
		var length := _rng.randf_range(16.0, 22.0)
		var z := _rng.randf_range(60.0, maxf(70.0, level_length - 80.0))
		if z + length > level_length - 40.0:
			continue
		if not _train_lane_is_clear(lane, z, length, rows):
			continue
		_spawn_train(lane, z, length)
		placed += 1


func _train_lane_is_clear(lane: int, z: float, length: float, rows: Array) -> bool:
	var lane_index := lane + 1
	var escape_codes := ["", "h", "b"]
	for row in rows:
		var row_z := float(row.get("z", 0.0))
		if row_z < z - 8.0 or row_z > z + length + 8.0:
			continue
		var cells: Array = row.get("c", [])
		if cells.size() < 3:
			return false
		if not String(cells[lane_index]).is_empty():
			return false
		# Somewhere to go for the whole length of the train, not just at its nose.
		var escape := false
		for other in range(3):
			if other != lane_index and escape_codes.has(String(cells[other])):
				escape = true
		if not escape:
			return false
	for entry in level.get("sparks", []):
		if int(entry[1]) != lane:
			continue
		var start := float(entry[0])
		var end := start + float(entry[2]) * 1.7
		if end > z - 3.0 and start < z + length + 3.0:
			return false
	for key in ["powers", "relics"]:
		for entry in level.get(key, []):
			var spot := float(entry[0])
			if int(entry[1]) == lane and spot > z - 4.0 and spot < z + length + 4.0:
				return false
	return true


func _spawn_train(lane: int, z: float, length: float) -> void:
	var mid := -(z + length * 0.5)
	var train := Node3D.new()
	train.name = "Train"
	train.position = Vector3(curve_at(mid) + Playfield.lane_x(lane), 0, -z)
	train.rotation.y = atan(curve_slope(mid))
	add_child(train)

	var livery := Color(String(TRAIN_COLORS[_rng.randi_range(0, TRAIN_COLORS.size() - 1)]))

	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 2.8, length)
	body.mesh = box
	body.position = Vector3(0, 1.4, -length * 0.5)
	body.material_override = _material(livery.darkened(0.1))
	train.add_child(body)

	var roof := MeshInstance3D.new()
	var roof_box := BoxMesh.new()
	roof_box.size = Vector3(2.62, 0.3, length * 0.98)
	roof.mesh = roof_box
	roof.position = Vector3(0, 2.9, -length * 0.5)
	roof.material_override = _material(livery.darkened(0.5))
	train.add_child(roof)

	# A cream waistband and a nose cap stop the car reading as one dark slab.
	var band := MeshInstance3D.new()
	var band_box := BoxMesh.new()
	band_box.size = Vector3(2.58, 0.26, length)
	band.mesh = band_box
	band.position = Vector3(0, 0.62, -length * 0.5)
	band.material_override = _material(Color("#f7f1e1"))
	train.add_child(band)

	var nose := MeshInstance3D.new()
	var nose_box := BoxMesh.new()
	nose_box.size = Vector3(2.52, 1.5, 0.16)
	nose.mesh = nose_box
	nose.position = Vector3(0, 2.1, 0.02)
	nose.material_override = _material(livery.darkened(0.55))
	train.add_child(nose)

	var lamp := MeshInstance3D.new()
	var lamp_box := BoxMesh.new()
	lamp_box.size = Vector3(0.44, 0.3, 0.1)
	lamp.mesh = lamp_box
	lamp.position = Vector3(0, 1.15, 0.09)
	lamp.material_override = _material(Color("#fff6cf"), 1.6)
	train.add_child(lamp)

	# Lit windows down both flanks so a train reads instantly at running speed.
	var panes := maxi(2, int(length / 3.0))
	for side in [-1.0, 1.0]:
		for i in range(panes):
			var pane := MeshInstance3D.new()
			var pane_box := BoxMesh.new()
			pane_box.size = Vector3(0.08, 0.72, 1.3)
			pane.mesh = pane_box
			pane.position = Vector3(side * 1.27, 1.95, -1.6 - i * 2.9)
			pane.material_override = _material(Color("#ffeec2"), 1.15)
			train.add_child(pane)

	for i in range(3):
		var chevron := MeshInstance3D.new()
		var chevron_box := BoxMesh.new()
		chevron_box.size = Vector3(2.5, 0.2, 0.1)
		chevron.mesh = chevron_box
		chevron.position = Vector3(0, 1.6 + i * 0.36, 0.1)
		chevron.material_override = _material(Color("#ffd166"), 0.45)
		train.add_child(chevron)

	hazards.append({
		"node": train,
		"lane": lane,
		"kind": "t",
		"half": 1.25,
		"x": train.position.x,
		"z": -z,
		"len": length,
		"bottom": 0.0,
		"top": 2.95,
		"hit": false,
		"wide": false,
		"fatal": true,
		"roll": 0.0,
		"spin": 0.0,
	})


## Pits cut across every lane, so the only answer is a jump. They are always
## dropped into a stretch with no obstacle row and no pickups nearby.
func _build_gaps() -> void:
	var want := 2 + _rng.randi_range(0, 2)
	var placed := 0
	var tries := 0
	while placed < want and tries < 26:
		tries += 1
		var z := _rng.randf_range(80.0, maxf(90.0, level_length - 80.0))
		if not _gap_is_clear(z):
			continue
		_spawn_gap(z)
		placed += 1


func _gap_is_clear(z: float) -> bool:
	for row in level.get("rows", []):
		if absf(float(row.get("z", 0.0)) - z) < 9.0:
			return false
	for entry in level.get("sparks", []):
		var start := float(entry[0])
		var end := start + float(entry[2]) * 1.7
		if end > z - 7.0 and start < z + 7.0:
			return false
	for key in ["powers", "relics"]:
		for entry in level.get(key, []):
			if absf(float(entry[0]) - z) < 8.0:
				return false
	return true


func _spawn_gap(z: float) -> void:
	var length := 3.0
	var node := Node3D.new()
	node.name = "Gap"
	node.position = Vector3(curve_at(-z), 0, -z)
	node.rotation.y = atan(curve_slope(-z))
	add_child(node)

	var pit := MeshInstance3D.new()
	var pit_box := BoxMesh.new()
	pit_box.size = Vector3(9.3, 0.1, length)
	pit.mesh = pit_box
	pit.position = Vector3(0, 0.045, -length * 0.5)
	pit.material_override = _material(Color("#12161d"))
	node.add_child(pit)

	var shaft := MeshInstance3D.new()
	var shaft_box := BoxMesh.new()
	shaft_box.size = Vector3(8.8, 2.6, length * 0.92)
	shaft.mesh = shaft_box
	shaft.position = Vector3(0, -1.3, -length * 0.5)
	shaft.material_override = _material(Color("#0a0d12"))
	node.add_child(shaft)

	for lip in [0.0, -length]:
		var stripe := MeshInstance3D.new()
		var stripe_box := BoxMesh.new()
		stripe_box.size = Vector3(9.3, 0.12, 0.4)
		stripe.mesh = stripe_box
		stripe.position = Vector3(0, 0.06, lip)
		stripe.material_override = _material(Color("#ffb347"), 0.75)
		node.add_child(stripe)

	hazards.append({
		"node": node,
		"lane": 0,
		"kind": "g",
		"half": 0.0,
		"x": node.position.x,
		"z": -z,
		"len": length,
		"bottom": -9.0,
		"top": 0.62,
		"hit": false,
		"wide": true,
		"fatal": true,
		"roll": 0.0,
		"spin": 0.0,
	})


func update(delta: float, player_z: float, relic_finder := false) -> void:
	var clock := Time.get_ticks_msec() * 0.001
	for spark in sparks:
		if spark["collected"]:
			continue
		var node: Node3D = spark["node"]
		if not is_instance_valid(node):
			continue

		node.rotation.y += delta * 2.4
		node.position.y = float(spark["base_y"]) + sin(clock * 2.2 + float(spark["phase"])) * 0.12
		node.visible = float(spark["z"]) < player_z + 6.0

	for pickup in pickups:
		if pickup["taken"]:
			continue
		var node: Node3D = pickup["node"]
		if not is_instance_valid(node):
			continue
		node.rotation.y += delta * 1.6
		node.position.y = 1.0 + sin(clock * 1.9 + float(pickup["phase"])) * 0.16

	for relic in relics:
		var node: Node3D = relic["node"]
		if not is_instance_valid(node):
			continue
		node.rotation.y += delta * 1.1
		(relic["beam"] as Node3D).visible = relic_finder and not relic["found"]
		node.visible = not relic["found"]

	for hazard in hazards:
		if hazard["hit"]:
			continue
		if String(hazard["kind"]) != "m":
			continue
		var node: Node3D = hazard["node"]
		if not is_instance_valid(node):
			continue
		node.position.z += float(hazard["roll"]) * delta
		hazard["z"] = node.position.z
		hazard["spin"] = float(hazard["spin"]) + delta * 3.2
		node.rotation.x = float(hazard["spin"])


## Safe-path hint used by the Wayfinder Gate tutorial moments.
func route_lane_at(distance: float) -> int:
	var target := float(distance)
	var lane := 0
	for segment in level.get("route", []):
		if float(segment[0]) > target:
			break
		lane = int(segment[1])
	return lane


func hide_hazard(hazard: Dictionary) -> void:
	var node: Node3D = hazard["node"]
	if is_instance_valid(node):
		node.visible = false


func collect_spark(spark: Dictionary) -> void:
	spark["collected"] = true
	var node: Node3D = spark["node"]
	if is_instance_valid(node):
		node.visible = false


func take_pickup(pickup: Dictionary) -> void:
	pickup["taken"] = true
	var node: Node3D = pickup["node"]
	if is_instance_valid(node):
		node.visible = false


func take_relic(relic: Dictionary) -> void:
	relic["found"] = true
	var node: Node3D = relic["node"]
	if is_instance_valid(node):
		node.visible = false
