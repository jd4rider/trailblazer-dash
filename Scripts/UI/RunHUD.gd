class_name RunHUD
extends Control
## In-run heads-up display: score, sparks, stumbles, objective and power-ups.
## Kept to the top of the screen so nothing covers the road or the paddle.

signal pause_pressed

var mode := "campaign"
var level_label := ""
var objective_text := ""

var _score_label: Label
var _distance_label: Label
var _spark_label: Label
var _relic_label: Label
var _hearts_label: Label
var _objective_label: Label
var _power_row: HBoxContainer
var _power_key := ""
var _power_timer := 0.0
var _flash: Label
var _flash_tween: Tween


func setup(level: Dictionary, run_mode: String) -> void:
	mode = run_mode
	level_label = Campaign.level_title(level) if run_mode == "campaign" else {
		"endless": "Endless Trail",
		"daily": "Daily Route · %s" % Save.daily_date_key(),
	}.get(run_mode, "Trail")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	set_objective(level)


func _build() -> void:
	# One full-rect column with explicit offsets. Nesting it in a margin and
	# anchoring that to the top collapsed the whole HUD to minimum width.
	var column := Ui.vbox(8)
	column.add_theme_constant_override("separation", 8)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 14
	column.offset_right = -14
	column.offset_top = 10
	column.offset_bottom = -12
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var header := Ui.hbox(8)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := Ui.chip(level_label, Color(0.05, 0.09, 0.1, 0.45), Ui.CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var pause := Ui.chip("II", Color(0.06, 0.1, 0.11, 0.55), Ui.CREAM)
	var pause_button := Button.new()
	pause_button.flat = true
	pause_button.custom_minimum_size = Vector2(52, 34)
	pause_button.add_theme_stylebox_override("normal", Ui.style(Color(0, 0, 0, 0), 10))
	pause_button.add_theme_stylebox_override("hover", Ui.style(Color(1, 1, 1, 0.12), 10))
	pause_button.add_theme_stylebox_override("pressed", Ui.style(Color(1, 1, 1, 0.2), 10))
	pause_button.tooltip_text = "Pause"
	pause_button.pressed.connect(func() -> void:
		Audio.ui_click()
		pause_pressed.emit())
	pause.add_child(pause_button)
	header.add_child(pause)
	column.add_child(header)

	var stats := Ui.hbox(8)
	var score_card := Ui.inset(Color(0.05, 0.09, 0.1, 0.55), 14)
	_score_label = Ui.label("0", 24, Ui.CREAM)
	var score_pad := Ui.margin(12, 4, 12, 4)
	score_pad.add_child(_score_label)
	score_card.add_child(score_pad)
	stats.add_child(score_card)

	var spark_card := Ui.inset(Color(0.05, 0.09, 0.1, 0.55), 14)
	var spark_row := Ui.hbox(6)
	spark_row.add_child(StarIcon.make(true, 18.0, Ui.GOLD))
	_spark_label = Ui.label("0", 22, Ui.CREAM)
	spark_row.add_child(_spark_label)
	var spark_pad := Ui.margin(12, 4, 12, 4)
	spark_pad.add_child(spark_row)
	spark_card.add_child(spark_pad)
	stats.add_child(spark_card)

	var relic_card := Ui.inset(Color(0.05, 0.09, 0.1, 0.55), 14)
	_relic_label = Ui.label("REL 0", 17, Color("#d9c6ff"))
	var relic_pad := Ui.margin(12, 4, 12, 4)
	relic_pad.add_child(_relic_label)
	relic_card.add_child(relic_pad)
	stats.add_child(relic_card)

	var hearts_card := Ui.inset(Color(0.05, 0.09, 0.1, 0.55), 14)
	_hearts_label = Ui.label("LIVES 3", 17, Ui.CORAL)
	var hearts_pad := Ui.margin(12, 4, 12, 4)
	hearts_pad.add_child(_hearts_label)
	hearts_card.add_child(hearts_pad)
	stats.add_child(hearts_card)
	for card in [score_card, spark_card, relic_card, hearts_card]:
		(card as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(stats)

	var objective_card := Ui.inset(Color(0.06, 0.11, 0.12, 0.5), 14)
	objective_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective_label = Ui.label(objective_text, 16, Ui.CREAM)
	var objective_pad := Ui.margin(12, 4, 12, 4)
	objective_pad.add_child(_objective_label)
	objective_card.add_child(objective_pad)
	column.add_child(objective_card)

	_power_row = Ui.hbox(6)
	_power_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_power_row)
	column.add_child(Ui.grow())

	_distance_label = Ui.label("0 m", 15, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT)
	var distance_wrap := Ui.margin(0, 0, 20, 0)
	distance_wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	distance_wrap.offset_top = -44
	distance_wrap.offset_bottom = -14
	distance_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	distance_wrap.add_child(_distance_label)
	add_child(distance_wrap)

	_flash = Ui.label("", 30, Ui.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	# A centre-top preset is zero-width, which wrapped every flash one letter per
	# line; span the screen instead and keep the text on one line.
	_flash.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_flash.offset_left = 20
	_flash.offset_right = -20
	_flash.offset_top = 236
	_flash.offset_bottom = 300
	_flash.autowrap_mode = TextServer.AUTOWRAP_OFF
	_flash.modulate.a = 0.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)


func set_objective(level: Dictionary) -> void:
	var objective: Dictionary = level.get("obj", {})
	var kind := String(objective.get("t", "sparks"))
	var need := int(objective.get("n", 0))
	match kind:
		"sparks":
			objective_text = "Collect %d sparks before the beacon" % need
		"relics":
			objective_text = "Recover %d relics along the route" % need
		"clean":
			objective_text = "Reach the beacon without a stumble"
		"time":
			objective_text = "Reach the beacon in under %d seconds" % int(float(level.get("dur", 60)) * 1.3)
		_:
			objective_text = "Reach the beacon"
	if _objective_label:
		_objective_label.text = objective_text


func update_state(data: Dictionary) -> void:
	if _score_label == null:
		return
	_score_label.text = Ui.format_number(int(data.get("score", 0)))
	_spark_label.text = str(int(data.get("sparks", 0)))
	_relic_label.text = "REL %d" % int(data.get("relics", 0))
	_distance_label.text = "%d m · %d km/h" % [int(data.get("distance", 0)), int(float(data.get("speed", 0)) * 3.6)]
	var hearts := int(data.get("hearts", 3))
	_hearts_label.text = "LIVES %d" % maxi(0, hearts)
	var powers: Array = data.get("powers", [])
	var key := ""
	for power in powers:
		key += String(power["id"]) + ":"
	_power_timer -= get_process_delta_time()
	if key != _power_key or _power_timer <= 0.0:
		_power_key = key
		_power_timer = 0.2
		_rebuild_powers(powers)


func _rebuild_powers(powers: Array) -> void:
	for child in _power_row.get_children():
		child.queue_free()
	for power in powers:
		var id := String(power["id"])
		var seconds := float(power["time"])
		var label_text := PowerUps.glyph(id)
		if id != "shield" and seconds > 0.0:
			label_text += " %ds" % int(ceil(seconds))
		else:
			label_text += " ×%d" % int(seconds)
		_power_row.add_child(Ui.chip(label_text, PowerUps.color(id), Ui.INK))


func flash_power(id: String) -> void:
	if _flash == null:
		return
	_flash.text = "%s  %s" % [PowerUps.glyph(id), PowerUps.display_name(id).to_upper()]
	_flash.modulate.a = 1.0
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.7)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.5)


func flash_text(text: String, color := Ui.CREAM) -> void:
	if _flash == null:
		return
	_flash.text = text
	_flash.add_theme_color_override("font_color", color)
	_flash.modulate.a = 1.0
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.6)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.4)
