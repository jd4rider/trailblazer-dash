extends Node3D
## Title screen: a living diorama of Avelora with the chosen Trailblazer.

var _pivot: Node3D
var _camera: Camera3D
var _model: Node3D
var _t := 0.0
var _status: Label


func _ready() -> void:
	_build_world()
	_build_ui()
	Audio.play_music("meadow")
	Audio.play_ambience("birds")
	Audio.set_intensity(0.3)
	Save.flush()


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#2b4a63")
	sky_material.sky_horizon_color = Color("#f0b97a")
	sky_material.ground_horizon_color = Color("#8fc9a2")
	sky_material.ground_bottom_color = Color("#2f5d46")
	sky_material.sun_angle_max = 18.0
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.42
	environment.fog_enabled = true
	environment.fog_light_color = Color("#f4d3a8")
	environment.fog_density = 0.0045
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.92
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -48, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := CylinderMesh.new()
	plane.top_radius = 26.0
	plane.bottom_radius = 26.0
	plane.height = 0.6
	plane.radial_segments = 40
	ground.mesh = plane
	ground.position = Vector3(0, -0.35, 0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#5fae57")
	ground_material.roughness = 0.95
	ground.material_override = ground_material
	add_child(ground)

	var pedestal := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.5
	disc.bottom_radius = 1.75
	disc.height = 0.36
	disc.radial_segments = 28
	pedestal.mesh = disc
	pedestal.position = Vector3(0, 0.05, 0)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#a89a80")
	stone.roughness = 0.8
	pedestal.material_override = stone
	add_child(pedestal)

	_model = _spawn_character()
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0, 0)
	add_child(_pivot)

	for spec in [
		{"prop": "tree_round", "pos": Vector3(-6.5, 0, -4.0), "scale": 1.5},
		{"prop": "tree_pine", "pos": Vector3(7.0, 0, -6.5), "scale": 1.3},
		{"prop": "rock_big", "pos": Vector3(-8.5, 0, 2.5), "scale": 1.0},
		{"prop": "mushroom", "pos": Vector3(4.2, 0, 3.0), "scale": 1.0},
		{"prop": "banner", "pos": Vector3(3.4, 0, -2.0), "scale": 1.2},
		{"prop": "beacon", "pos": Vector3(-4.0, 0, -9.0), "scale": 1.1},
	]:
		var path := "res://Assets/Models/props/%s.glb" % spec["prop"]
		if not ResourceLoader.exists(path):
			continue
		var packed: PackedScene = load(path)
		var node := packed.instantiate() as Node3D
		node.position = spec["pos"]
		node.scale = Vector3.ONE * float(spec["scale"])
		node.rotation.y = randf() * TAU
		add_child(node)

	_camera = Camera3D.new()
	_camera.fov = 52
	_camera.position = Vector3(0.0, 2.3, 7.4)
	add_child(_camera)
	_camera.look_at(Vector3(0, 1.05, 0), Vector3.UP)


func _spawn_character() -> Node3D:
	var character_id := String(Save.data.get("profile", {}).get("character", "pip"))
	var path := "res://Assets/Models/characters/%s.glb" % character_id
	if not ResourceLoader.exists(path):
		path = "res://Assets/Models/characters/pip.glb"
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	node.scale = Vector3(1.55, 1.55, 1.55)
	node.position = Vector3(0, 0.24, 0)
	node.rotation.y = 0.0
	add_child(node)
	_tint_character(node, Roster.get_character(character_id))
	var anim := _find_anim(node)
	if anim:
		anim.play("Idle")
		anim.speed_scale = 0.9
	return node


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim(child)
		if found:
			return found
	return null


func _tint_character(node: Node, entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var outfit := Color(String(entry.get("outfit", "#2f7d78")))
	var accent := Color(String(entry.get("accent", "#e8a33d")))
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface)
			if material == null:
				continue
			var name := material.resource_name
			if not (name.contains("jacket") or name.contains("trousers") or name.contains("hat") or name.contains("scarf") or name.contains("accent")):
				continue
			var copy := material.duplicate() as StandardMaterial3D
			if name.contains("jacket"):
				copy.albedo_color = outfit
			elif name.contains("trousers"):
				copy.albedo_color = outfit.darkened(0.22)
			elif name.contains("hat"):
				copy.albedo_color = Color("#efe3c6").lerp(accent, 0.25)
			elif name.contains("scarf") or name.contains("accent"):
				copy.albedo_color = accent
			mesh_instance.set_surface_override_material(surface, copy)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)

	var shade := Ui.gradient_background(Color(0.03, 0.08, 0.1, 0.72), Color(0.03, 0.08, 0.1, 0.05))
	shade.set_anchors_preset(Control.PRESET_TOP_WIDE)
	shade.custom_minimum_size = Vector2(0, 400)
	screen.add_child(shade)

	# A full-rect column pinned to the bottom, inside a scroll view. In the
	# arcade's shorter iframe the stack is taller than the frame, and a plain
	# VBox compresses its rows until they overlap.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 18
	scroll.offset_right = -18
	scroll.offset_bottom = -24
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	screen.add_child(scroll)

	var column := Ui.vbox(8)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(column)

	var title := Ui.title("TRAILBLAZER", 62, Ui.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.12, 0.13, 0.85))
	var title_wrap := Ui.margin(12, 54, 12, 0)
	title_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_wrap.add_child(title)
	screen.add_child(title_wrap)

	var dash := Ui.title("D A S H", 40, Ui.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	dash.add_theme_constant_override("outline_size", 12)
	dash.add_theme_color_override("font_outline_color", Color(0.05, 0.12, 0.13, 0.85))
	var dash_wrap := Ui.margin(12, 128, 12, 0)
	dash_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	dash_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dash_wrap.add_child(dash)
	screen.add_child(dash_wrap)

	var tagline := Ui.label("Restore the Wayfinder Network, one trail at a time.",
		17, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	var tag_wrap := Ui.margin(24, 186, 24, 0)
	tag_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tag_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_wrap.add_child(tagline)
	screen.add_child(tag_wrap)

	var next_id := Campaign.next_level_id()
	var next_level := Campaign.level(next_id)
	var continue_button := Ui.button("CONTINUE  ·  %s" % Campaign.level_title(next_level), 24, true)
	continue_button.pressed.connect(func() -> void:
		Audio.ui_click()
		Router.go("run", {"mode": "campaign", "level_id": next_id}))
	column.add_child(continue_button)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	_menu_button(grid, "WORLD MAP", func() -> void: Router.go("map"))
	_menu_button(grid, "ENDLESS TRAIL", func() -> void: Router.go("run", {"mode": "endless"}))
	_menu_button(grid, "DAILY ROUTE", func() -> void: Router.go("run", {"mode": "daily"}))
	_menu_button(grid, "TRAILBLAZERS", func() -> void: Router.go("characters"))
	_menu_button(grid, "COLLECTIONS", func() -> void: Router.go("collection"))

	var bottom := Ui.hbox(10)
	var settings := Ui.button("SETTINGS", 18)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.pressed.connect(func() -> void:
		Audio.ui_click()
		Router.go("settings"))
	bottom.add_child(settings)
	var arcade := Ui.button("LITTLE JOY ARCADE", 18)
	arcade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arcade.pressed.connect(func() -> void:
		Audio.ui_click()
		if Arcade.available:
			Arcade.open_arcade()
		else:
			Router.show_toast("Open this trail from littlejoyarcade.site for cloud saves.")
	)
	bottom.add_child(arcade)
	column.add_child(bottom)

	_status = Ui.label(_status_line(), 14, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_status)

	var stats := Ui.label("%d stars  ·  %d/%d trails  ·  %d relics" % [
		Save.total_stars(), Save.completed_levels(), Campaign.TOTAL_LEVELS, int(Save.data["progress"]["relics"])
	], 15, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(stats)


func _menu_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Ui.button(text, 18)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		Audio.ui_click()
		callback.call())
	parent.add_child(button)


func _status_line() -> String:
	if Arcade.available:
		return Arcade.status_text()
	return "Saving on this device · sign in at littlejoyarcade.site for cloud saves"


func _process(delta: float) -> void:
	_t += delta
	if _camera:
		_camera.position.x = sin(_t * 0.22) * 0.9
		_camera.position.y = 2.3 + sin(_t * 0.35) * 0.06
		_camera.look_at(Vector3(0, 1.05, 0), Vector3.UP)
	if _model:
		_model.rotation.y = sin(_t * 0.4) * 0.35
