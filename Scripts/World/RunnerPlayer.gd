class_name RunnerPlayer
extends Node3D
## The running Trailblazer: lanes, jump, slide, power-ups and animation.
##
## The player node sits at the origin and Run moves the track past it, so this
## script only owns lateral and vertical motion plus state effects.

signal stumbled
signal shield_absorbed
signal landed

const CHARACTER_DIR := "res://Assets/Models/characters/"

var lane := 0
var x := 0.0
var y := 0.0
var vy := 0.0
var airborne := false
var sliding := false
var surface := "grass"

var model: Node3D
var anim: AnimationPlayer
var shield_charges := 0
var hits := 0
var active := true

## Set by Run every tick: where the trail's centre is, and how hard it bends.
var graph_offset := 0.0
var bank_slope := 0.0
var lean := 0.0

var _target_x := 0.0
var _slide_left := 0.0
var _invuln := 0.0
var _stumble_left := 0.0
var _step_timer := 0.0
var _double_jump_ready := false
var _powers: Dictionary = {}
var _dust: GPUParticles3D
var _speed := 0.0


func setup(character_id: String, surface_name: String) -> void:
	surface = surface_name
	_build_model(character_id)
	_build_dust()
	visible = true


func _build_model(character_id: String) -> void:
	var path := CHARACTER_DIR + character_id + ".glb"
	if not ResourceLoader.exists(path):
		path = CHARACTER_DIR + "pip.glb"
	var packed: PackedScene = load(path)
	model = packed.instantiate() as Node3D
	model.name = "Model"
	model.scale = Vector3.ONE * 1.15
	# Blender authors the character facing -Y, which becomes +Z in glTF.
	model.rotation.y = PI
	add_child(model)
	# The Blender body is authored with its soles above the origin, so without this
	# the Trailblazer floats a third of a metre above the trail.
	model.position.y -= _foot_offset()
	anim = _find_animation_player(model)
	if anim:
		anim.play("Idle")


func _foot_offset() -> float:
	var lowest := 0.0
	var first := true
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local := global_transform.affine_inverse() * mesh_instance.global_transform
		var box: AABB = local * mesh_instance.mesh.get_aabb()
		lowest = box.position.y if first else minf(lowest, box.position.y)
		first = false
	if absf(lowest) > 2.0:
		return 0.0
	return lowest


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _build_dust() -> void:
	_dust = GPUParticles3D.new()
	_dust.name = "Dust"
	_dust.amount = 14
	_dust.lifetime = 0.55
	_dust.emitting = false
	_dust.position = Vector3(0, 0.1, 0)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 75.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 3.0
	process.gravity = Vector3(0, -7.0, 0)
	process.scale_min = 0.06
	process.scale_max = 0.18
	process.color = Color(1, 0.98, 0.9, 0.55)
	_dust.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	_dust.draw_pass_1 = mesh
	add_child(_dust)


func reset_state() -> void:
	lane = 0
	x = 0.0
	_target_x = 0.0
	y = 0.0
	vy = 0.0
	airborne = false
	sliding = false
	_slide_left = 0.0
	_invuln = 0.0
	_stumble_left = 0.0
	shield_charges = 0
	hits = 0
	_double_jump_ready = false
	_powers.clear()
	active = true
	graph_offset = 0.0
	bank_slope = 0.0
	lean = 0.0
	if model:
		model.rotation.z = 0.0
	position = Vector3.ZERO
	_play("Run", 1.0)


func tick(delta: float, speed: float) -> void:
	_speed = speed
	if not active:
		return
	if _invuln > 0.0:
		_invuln -= delta
	if _stumble_left > 0.0:
		_stumble_left -= delta
	for id in _powers.keys():
		if float(_powers[id]) > 0.0:
			_powers[id] = float(_powers[id]) - delta
			if float(_powers[id]) <= 0.0:
				_powers.erase(id)

	x = move_toward(x, _target_x, Playfield.LANE_CHANGE_SPEED * delta)
	position.x = x + graph_offset
	# Bank into lane changes and lean with the bend of the trail.
	var lateral := _target_x - x
	var want_lean := clampf(lateral * 0.14 + bank_slope * 0.55, -0.24, 0.24)
	lean = lerpf(lean, want_lean, 1.0 - exp(-delta * 9.0))
	if model != null:
		model.rotation.z = lean

	if airborne:
		vy += Playfield.GRAVITY * delta
		y += vy * delta
		if y <= 0.0:
			y = 0.0
			vy = 0.0
			airborne = false
			_dust.restart()
			_dust.emitting = true
			Audio.play_sfx("land", randf_range(0.94, 1.06), -8.0)
			landed.emit()
	position.y = y

	if sliding:
		_slide_left -= delta
		if _slide_left <= 0.0:
			sliding = false
			if not airborne:
				_play("Run", _anim_speed(speed))

	_update_animation(speed)
	_update_footsteps(delta, speed)


func _update_animation(speed: float) -> void:
	if anim == null:
		return
	if _stumble_left > 0.0:
		_play("Stumble", 1.4)
	elif sliding:
		_play("Slide", 1.2)
	elif airborne:
		_play("Jump", 1.0)
	else:
		_play("Run", _anim_speed(speed))


func _anim_speed(speed: float) -> float:
	return clampf(0.7 + speed * 0.055, 0.7, 1.9)


func _update_footsteps(delta: float, speed: float) -> void:
	if airborne or sliding or _stumble_left > 0.0:
		return
	_step_timer -= delta * clampf(speed / 11.0, 0.6, 2.0)
	if _step_timer <= 0.0:
		_step_timer = 0.31
		Audio.step(surface)


func _play(clip: String, speed_scale: float) -> void:
	if anim == null:
		return
	if anim.current_animation != clip:
		anim.play(clip)
		anim.seek(0.0)
	anim.speed_scale = speed_scale


func move_lane(direction: int) -> bool:
	var next := clampi(lane + direction, -1, 1)
	if next == lane:
		return false
	lane = next
	_target_x = Playfield.lane_x(lane)
	return true


func jump() -> bool:
	if not active:
		return false
	if not airborne:
		vy = Playfield.JUMP_VELOCITY
		airborne = true
		sliding = false
		_double_jump_ready = has_power("double_jump")
		_play("Jump", 1.0)
		Audio.play_sfx("jump", randf_range(0.96, 1.05), -6.0)
		return true
	if _double_jump_ready:
		_double_jump_ready = false
		vy = Playfield.JUMP_VELOCITY * Playfield.DOUBLE_JUMP_FACTOR
		_play("Jump", 1.15)
		Audio.play_sfx("jump", 1.12, -6.0)
		return true
	return false


func slide() -> bool:
	if not active or sliding:
		return false
	if airborne:
		# Land fast, then slide: keeps input forgiving without teleporting.
		vy = minf(vy, -Playfield.JUMP_VELOCITY)
		airborne = true
	sliding = true
	_slide_left = Playfield.LONG_SLIDE_TIME if has_power("long_slide") else Playfield.SLIDE_TIME
	_play("Slide", 1.0)
	Audio.play_sfx("slide", randf_range(0.96, 1.05), -9.0)
	return true


func height() -> float:
	return Playfield.SLIDE_HEIGHT if sliding else Playfield.STAND_HEIGHT


func apply_power(id: String) -> void:
	match id:
		"shield":
			shield_charges += 1
		"double_jump":
			_powers["double_jump"] = PowerUps.duration(id)
			_double_jump_ready = true
		"lucky_spark":
			pass
		_:
			if PowerUps.is_timed(id):
				_powers[id] = maxf(float(_powers.get(id, 0.0)), PowerUps.duration(id))


func has_power(id: String) -> bool:
	if id == "shield":
		return shield_charges > 0
	if id == "double_jump":
		return _double_jump_ready or float(_powers.get("double_jump", 0.0)) > 0.0
	return float(_powers.get(id, 0.0)) > 0.0


func power_time_left(id: String) -> float:
	if id == "shield":
		return float(shield_charges)
	return maxf(0.0, float(_powers.get(id, 0.0)))


func active_powers() -> Array:
	var out: Array = []
	if shield_charges > 0:
		out.append({"id": "shield", "time": float(shield_charges)})
	for id in _powers.keys():
		if float(_powers[id]) > 0.0:
			out.append({"id": id, "time": float(_powers[id])})
	return out


func is_invulnerable() -> bool:
	return _invuln > 0.0


func take_hit() -> String:
	if _invuln > 0.0:
		return "ignored"
	if shield_charges > 0:
		shield_charges -= 1
		_invuln = 1.1
		_stumble_left = 0.35
		shield_absorbed.emit()
		Audio.play_sfx("shield", randf_range(0.95, 1.05), -4.0)
		return "shield"
	hits += 1
	_invuln = 1.35
	_stumble_left = 0.45
	Audio.play_sfx("stumble", randf_range(0.94, 1.06), -3.0)
	stumbled.emit()
	return "stumble"


func celebrate() -> void:
	active = false
	if anim:
		anim.play("Celebrate")
		anim.speed_scale = 1.0


func fall() -> void:
	active = false
	if anim:
		anim.play("Stumble")
		anim.speed_scale = 1.0


func set_visible_model(value: bool) -> void:
	if model:
		model.visible = value
