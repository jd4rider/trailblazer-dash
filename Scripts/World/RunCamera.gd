extends Camera3D
## Portrait-first chase camera. Reads the player's lane and the run speed, and
## never moves far enough to hide an upcoming row of obstacles.

var target: RunnerPlayer
var reduced_motion := false

var _shake := 0.0
var _speed_ratio := 0.0
var _base_offset := Vector3(0.0, 4.35, 8.6)
var _look_height := 1.25


func _ready() -> void:
	fov = Playfield.CAMERA_BASE_FOV
	near = 0.1
	far = 220.0
	position = _base_offset


func set_speed_ratio(value: float) -> void:
	_speed_ratio = clampf(value, 0.0, 1.0)


func shake(amount: float) -> void:
	if reduced_motion:
		return
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	if target == null:
		return
	var sway := target.x * 0.34
	var desired := _base_offset + Vector3(sway, 0.0, 0.0)
	if not reduced_motion:
		desired.y += sin(Time.get_ticks_msec() * 0.003) * 0.03
	position = position.lerp(desired, 1.0 - exp(-delta * 6.0))
	fov = lerpf(fov, lerpf(Playfield.CAMERA_BASE_FOV, Playfield.CAMERA_SPEED_FOV, _speed_ratio),
		1.0 - exp(-delta * 2.5))
	var look := Vector3(target.x * 0.42, _look_height, -9.0)
	if _shake > 0.0:
		var offset := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			0.0) * _shake * 0.25
		look += offset
		_shake = maxf(0.0, _shake - delta * 3.5)
	look_at(look, Vector3.UP)
