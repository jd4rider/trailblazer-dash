extends Control
## The Trailblazer showroom: eight characters, one rotatable 3D preview.

var index := 0

var _viewport: SubViewport
var _model: Node3D
var _name: Label
var _subtitle: Label
var _blurb: Label
var _requirement: Label
var _bar: ProgressBar
var _action: Button
var _drag := false
var _drag_x := 0.0
var _spin := 0.0
var _auto_spin := true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(Ui.gradient_background(Color("#123037"), Color("#08161a")))
	_build_preview()
	_build_ui()
	for i in range(Roster.CHARACTERS.size()):
		if String(Roster.CHARACTERS[i]["id"]) == String(Save.data["profile"].get("character", "pip")):
			index = i
	_show_character()


func _build_preview() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	container.custom_minimum_size = Vector2(0, 540)
	container.offset_bottom = 540
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(720, 640)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	container.add_child(_viewport)

	var world := Node3D.new()
	_viewport.add_child(world)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#0d262c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#cfe3d8")
	environment.ambient_light_energy = 1.1
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	world.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -36, 0)
	key.light_energy = 1.4
	key.light_color = Color(1, 0.95, 0.85)
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 140, 0)
	rim.light_energy = 0.7
	rim.light_color = Color("#8ecbff")
	world.add_child(rim)

	var pedestal := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.25
	disc.bottom_radius = 1.4
	disc.height = 0.3
	disc.radial_segments = 32
	pedestal.mesh = disc
	pedestal.position = Vector3(0, -0.16, 0)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#324c50")
	stone.roughness = 0.6
	pedestal.material_override = stone
	world.add_child(pedestal)

	var camera := Camera3D.new()
	camera.fov = 42
	camera.position = Vector3(0, 1.5, 4.4)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0), Vector3.UP)

	container.gui_input.connect(_on_preview_input)


func _build_ui() -> void:
	var back := Ui.ghost_button("‹ MENU", 17)
	back.custom_minimum_size = Vector2(96, 42)
	back.position = Vector2(14, 12)
	back.pressed.connect(func() -> void:
		Audio.ui_back()
		Router.go("menu"))
	add_child(back)

	var arrows := Ui.hbox(10)
	arrows.set_anchors_preset(Control.PRESET_CENTER)
	arrows.position = Vector2(0, 250)
	var previous := Ui.ghost_button("‹", 26)
	previous.custom_minimum_size = Vector2(48, 48)
	previous.pressed.connect(func() -> void: _step(-1))
	arrows.add_child(previous)
	arrows.add_child(Ui.spacer(120))
	var next := Ui.ghost_button("›", 26)
	next.custom_minimum_size = Vector2(48, 48)
	next.pressed.connect(func() -> void: _step(1))
	arrows.add_child(next)
	add_child(arrows)

	var sheet := Ui.panel()
	sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_top = -520
	sheet.offset_bottom = -10
	sheet.offset_left = 12
	sheet.offset_right = -12
	add_child(sheet)

	var inner := Ui.margin(20, 18, 20, 16)
	sheet.add_child(inner)
	var column := Ui.vbox(8)
	inner.add_child(column)

	_name = Ui.title("Pip", 40, Ui.INK)
	column.add_child(_name)
	_subtitle = Ui.label("she/her · Apprentice Wayfinder", 15, Ui.INK_SOFT)
	column.add_child(_subtitle)
	_blurb = Ui.label("", 16, Ui.INK)
	column.add_child(_blurb)
	_requirement = Ui.label("", 14, Ui.INK_SOFT)
	column.add_child(_requirement)
	_bar = Ui.progress_bar(0.0, Ui.GOLD, 8)
	column.add_child(_bar)

	column.add_child(Ui.spacer(4))
	_action = Ui.button("SELECT TRAILBLAZER", 22, true)
	_action.pressed.connect(_on_action)
	column.add_child(_action)

	var hint := Ui.label("Drag the model to turn it.", 13, Ui.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(hint)


func _step(direction: int) -> void:
	Audio.ui_click()
	index = (index + direction + Roster.CHARACTERS.size()) % Roster.CHARACTERS.size()
	_show_character()


func _show_character() -> void:
	var entry: Dictionary = Roster.CHARACTERS[index]
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = CharacterVisual.spawn(String(entry["id"]), 1.5)
	if _model:
		_model.position = Vector3(0, 0.02, 0)
		_viewport.add_child(_model)
		CharacterVisual.tint_for(_model, String(entry["id"]))
		var anim := CharacterVisual.animation_player(_model)
		if anim:
			anim.play("Idle")
	_name.text = String(entry["name"])
	_subtitle.text = "%s · %s" % [String(entry["pronoun"]), _role(String(entry["id"]))]
	_blurb.text = String(entry["blurb"])
	var unlocked := Roster.is_unlocked(String(entry["id"]))
	var cost := int(entry.get("stars", 0))
	if unlocked:
		_requirement.text = "Unlocked"
		_bar.value = 1.0
	else:
		var stars := Save.total_stars()
		_requirement.text = "Needs %d stars · you have %d" % [cost, stars]
		_bar.value = float(stars) / maxf(1.0, float(cost))
	var selected := String(Save.data["profile"].get("character", "pip")) == String(entry["id"])
	_action.text = "SELECTED" if selected else ("SELECT TRAILBLAZER" if unlocked else "LOCKED")
	_action.disabled = not unlocked or selected


func _role(id: String) -> String:
	match id:
		"pip": return "Apprentice Wayfinder"
		"nova": return "Stargazer"
		"bram": return "Mountain Guide"
		"lumi": return "Forest Listener"
		"tiko": return "Inventor"
		"mira": return "Coastal Navigator"
		"rook": return "Mechanic"
		"sol": return "First Wayfinder"
	return "Trailblazer"


func _on_action() -> void:
	var entry: Dictionary = Roster.CHARACTERS[index]
	if not Roster.is_unlocked(String(entry["id"])):
		Audio.ui_back()
		Router.show_toast("Earn %d stars to unlock %s." % [int(entry.get("stars", 0)), String(entry["name"])])
		return
	Save.data["profile"]["character"] = String(entry["id"])
	Save.unlock_character(String(entry["id"]))
	Save.queue_save()
	Audio.play_sfx("powerup", 1.05, -4.0)
	Router.show_toast("%s is ready to run." % String(entry["name"]))
	_show_character()


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		_drag_x = event.position.x
	elif event is InputEventMouseMotion and _drag:
		_spin += (event.position.x - _drag_x) * 0.01
		_drag_x = event.position.x
	elif event is InputEventScreenTouch:
		_drag = event.pressed
		_drag_x = event.position.x
	elif event is InputEventScreenDrag:
		_spin += (event.position.x - _drag_x) * 0.01
		_drag_x = event.position.x


func _process(delta: float) -> void:
	if _model == null or not is_instance_valid(_model):
		return
	if not _drag:
		_spin += delta * (0.22 if _auto_spin else 0.0)
	_model.rotation.y = PI + _spin
