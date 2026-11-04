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


func build(level_data: Dictionary, region_data: Dictionary) -> void:
	level = level_data
	region = region_data
	level_length = float(level.get("len", 400))
	finish_z = -level_length
	_rng.seed = int(level.get("seed", 1)) + 17
	_build_tile_materials()
	_build_tiles()
	_build_obstacles()
	_build_sparks()
	_build_pickups()
	_build_relics()
	_build_scenery()
	_build_markers()


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
	_tile_materials["tile_ground"] = _surface_material(ground)
	_tile_materials["tile_edge"] = _surface_material(ground.darkened(0.32))
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


func _build_tiles() -> void:
	# The road is built from primitives rather than the imported tile mesh: the
	# exported GLB carries near-white materials whose names do not survive import,
	# so tinting it per region silently produced a white track.
	# The trail runs towards negative Z (the player advances to -distance), so the
	# tiles step downwards in Z from just behind the start line.
	var z := 10.0
	var limit := finish_z - 60.0
	var index := 0
	while z > limit:
		var tile := Node3D.new()
		tile.name = "Tile%d" % index
		add_child(tile)

		var deck := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(9.0, 0.5, 20.0)
		deck.mesh = box
		deck.position = Vector3(0, -0.25, z)
		deck.material_override = _tile_materials["tile_ground"]
		tile.add_child(deck)

		for side in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var rail_box := BoxMesh.new()
			rail_box.size = Vector3(0.6, 0.7, 20.0)
			rail.mesh = rail_box
			rail.position = Vector3(side * 4.7, 0.1, z)
			rail.material_override = _tile_materials["tile_edge"]
			tile.add_child(rail)

		if index % 2 == 0:
			var dash := MeshInstance3D.new()
			var dash_box := BoxMesh.new()
			dash_box.size = Vector3(0.35, 0.06, 5.0)
			dash.mesh = dash_box
			dash.position = Vector3(0, 0.03, z)
			dash.material_override = _tile_materials["tile_accent"]
			tile.add_child(dash)

		z -= 20.0
		index += 1


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
			node.position = Vector3(Playfield.lane_x(lane), 0, -z)
			if code == "m":
				node.rotation.y = _rng.randf() * TAU
			if code == "x":
				node.scale = Vector3(1.0, _rng.randf_range(0.9, 1.1), 1.0)
			_paint(node, Color(String(OBSTACLE_COLORS.get(code, "#8d8477"))))
			hazards.append({
				"node": node,
				"lane": lane,
				"kind": code,
				"z": -z,
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
			node.position = Vector3(Playfield.lane_x(lane), 0.85, z)
			node.scale = Vector3.ONE * 1.25
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
		node.position = Vector3(Playfield.lane_x(lane), 1.0, z)
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
		node.position = Vector3(Playfield.lane_x(lane), 0.95, z)
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
				node.position = Vector3(
					side * _rng.randf_range(5.3, 9.8),
					0,
					z + _rng.randf_range(-5.0, 5.0))
				node.rotation.y = _rng.randf() * TAU
				var scale := _rng.randf_range(0.8, 1.4)
				node.scale = Vector3(scale, scale, scale)
				_paint(node, _scenery_color(pick))
		z -= 17.0

	var landmark := String(region.get("landmark", "beacon"))
	if ResourceLoader.exists(PROPS + landmark + ".glb"):
		var node := _instance(PROPS + landmark + ".glb")
		if node:
			node.position = Vector3(-7.4, 0, finish_z * 0.5)
			node.scale = Vector3(1.8, 1.8, 1.8)
			node.rotation.y = 0.5
			_paint(node, _accent_color, 0.35)


func _build_markers() -> void:
	var gate := _instance(PROPS + "finish_gate.glb")
	if gate:
		gate.position = Vector3(0, 0, finish_z)
		_paint(gate, _accent_color, 0.5)
	var beacon := _instance(PROPS + "beacon.glb")
	if beacon:
		beacon.position = Vector3(0, 0, finish_z - 9.0)
		_paint(beacon, Color("#ffe9b0"), 0.8)
	for fraction in [0.34, 0.68]:
		var ring := _instance(PROPS + "gate.glb")
		if ring:
			ring.position = Vector3(0, 0, finish_z * fraction)
			ring.scale = Vector3(1.3, 1.3, 1.3)
			ring.rotation.y = PI / 2
			_paint(ring, Color("#9fe8ff"), 0.5)


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
