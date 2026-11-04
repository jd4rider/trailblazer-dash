class_name ResultsPanel
extends Control
## Shared end-of-run card for campaign, endless and daily runs.

signal action(name: String)

var _built := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_result(data: Dictionary) -> void:
	if _built:
		queue_free()
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.07, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := Ui.panel()
	card.custom_minimum_size = Vector2(470, 0)
	center.add_child(card)
	var inner := Ui.margin(26, 26, 26, 22)
	card.add_child(inner)
	var column := Ui.vbox(12)
	inner.add_child(column)

	var success := bool(data.get("success", true))
	var eyebrow := Ui.label(
		String(data.get("eyebrow", "TRAIL COMPLETE" if success else "RUN OVER")),
		15, Ui.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(eyebrow)
	column.add_child(Ui.title(
		String(data.get("title", "Beacon Lit")), 40, Ui.INK, HORIZONTAL_ALIGNMENT_CENTER))

	var stars := int(data.get("stars", 0))
	if success or stars > 0:
		var row := Ui.stars_row(stars, 42)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_child(row)

	var subtitle := String(data.get("subtitle", ""))
	if not subtitle.is_empty():
		column.add_child(Ui.label(subtitle, 18, Ui.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))

	column.add_child(Ui.spacer(4))
	for row_data in data.get("rows", []):
		column.add_child(_stat_row(String(row_data[0]), String(row_data[1])))

	var achievements: Array = data.get("achievements", [])
	if not achievements.is_empty():
		var strip := Ui.hbox(6)
		strip.alignment = BoxContainer.ALIGNMENT_CENTER
		for id in achievements:
			strip.add_child(Ui.chip("NEW · " + String(id).replace("_", " ").capitalize(),
				Ui.GOLD, Ui.INK))
		column.add_child(strip)

	column.add_child(Ui.spacer(8))
	var primary := Ui.button(String(data.get("primary", "CONTINUE JOURNEY")), 23, true)
	primary.pressed.connect(func() -> void:
		Audio.ui_click()
		action.emit("primary"))
	column.add_child(primary)

	var buttons := Ui.hbox(10)
	if bool(data.get("allow_retry", true)):
		var retry := Ui.button("TRY AGAIN", 19)
		retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		retry.pressed.connect(func() -> void:
			Audio.ui_click()
			action.emit("retry"))
		buttons.add_child(retry)
	var map_button := Ui.button("WORLD MAP", 19)
	map_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_button.pressed.connect(func() -> void:
		Audio.ui_back()
		action.emit("map"))
	buttons.add_child(map_button)
	column.add_child(buttons)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)


func _stat_row(label: String, value: String) -> HBoxContainer:
	var row := Ui.hbox(8)
	var left := Ui.label(label, 18, Ui.INK_SOFT)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	row.add_child(Ui.label(value, 20, Ui.INK))
	return row
