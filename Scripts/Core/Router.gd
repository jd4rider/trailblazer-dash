extends Node
## Scene router with a warm fade and a small toast system.

const SCENES := {
	"menu": "res://Scenes/MainMenu.tscn",
	"map": "res://Scenes/WorldMap.tscn",
	"run": "res://Scenes/Run.tscn",
	"characters": "res://Scenes/Characters.tscn",
	"settings": "res://Scenes/Settings.tscn",
	"collection": "res://Scenes/Collection.tscn",
}

var current_name := ""
var _host: Node = null
var _holder: Node = null
var _current: Node = null
var _layer: CanvasLayer
var _fade: ColorRect
var _toast: PanelContainer
var _toast_label: Label
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_build_overlay()


func _setup_input() -> void:
	_bind("move_left", [KEY_LEFT, KEY_A])
	_bind("move_right", [KEY_RIGHT, KEY_D])
	_bind("jump", [KEY_SPACE, KEY_UP, KEY_W])
	_bind("slide", [KEY_DOWN, KEY_S])
	_bind("pause", [KEY_ESCAPE, KEY_P])
	_bind("restart", [KEY_R])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)

	_fade = ColorRect.new()
	_fade.color = Color(0.035, 0.08, 0.09, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_layer.add_child(_fade)

	_toast = Ui.panel(Color(0.1, 0.17, 0.18, 0.95), 18)
	_toast_label = Ui.label("", 18, Ui.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.add_child(_toast_label)
	var wrapper := MarginContainer.new()
	wrapper.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	wrapper.add_theme_constant_override("margin_bottom", 36)
	wrapper.add_theme_constant_override("margin_left", 26)
	wrapper.add_theme_constant_override("margin_right", 26)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(_toast)
	_layer.add_child(wrapper)
	_toast.modulate.a = 0.0


func boot(host: Node) -> void:
	_host = host
	_holder = Node.new()
	_holder.name = "SceneHolder"
	_host.add_child(_holder)
	go("menu", {}, false)


func go(scene_name: String, args: Dictionary = {}, animate := true) -> void:
	if _busy or not SCENES.has(scene_name):
		return
	_busy = true
	if animate:
		await _fade_to(1.0, 0.16)
	if is_instance_valid(_current):
		_current.queue_free()
		_current = null
		await get_tree().process_frame
	var packed: PackedScene = load(SCENES[scene_name])
	if packed == null:
		push_error("Missing scene: " + SCENES[scene_name])
		_busy = false
		return
	_current = packed.instantiate()
	# setup() runs before the node enters the tree so _ready() can build with
	# the arguments already in place (mode, level id, and so on).
	if _current.has_method("setup"):
		_current.call("setup", args)
	_holder.add_child(_current)
	current_name = scene_name
	if animate:
		await _fade_to(0.0, 0.2)
	_busy = false


func reload(args: Dictionary = {}) -> void:
	if current_name.is_empty():
		return
	var scene_name := current_name
	var keep := args
	_busy = false
	go(scene_name, keep, false)


func back() -> void:
	Audio.ui_back()
	go("menu")


func is_busy() -> bool:
	return _busy


func _fade_to(alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", alpha, duration)
	await tween.finished


func show_toast(text: String, seconds := 2.6) -> void:
	_toast_label.text = text
	var tween := create_tween()
	tween.tween_property(_toast, "modulate:a", 1.0, 0.18)
	tween.tween_interval(seconds)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
