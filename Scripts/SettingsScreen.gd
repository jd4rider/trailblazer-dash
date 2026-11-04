extends Control
## Settings: audio, performance, motion and access.

var _music_value: Label
var _sfx_value: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(Ui.gradient_background(Color("#123037"), Color("#08161a")))
	_build()


func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var page := Ui.vbox(14)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := Ui.margin(20, 16, 20, 30)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(page)
	scroll.add_child(margin)

	var header := Ui.hbox(10)
	var back := Ui.ghost_button("‹ MENU", 17)
	back.custom_minimum_size = Vector2(100, 44)
	back.pressed.connect(func() -> void:
		Audio.ui_back()
		Router.go("menu"))
	header.add_child(back)
	var title := Ui.title("SETTINGS", 34, Ui.CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(title)
	page.add_child(header)

	page.add_child(_audio_card())
	page.add_child(_play_card())
	page.add_child(_access_card())
	page.add_child(_save_card())
	page.add_child(_about_card())


func _card(title: String) -> VBoxContainer:
	var panel := Ui.panel()
	var inner := Ui.margin(18, 16, 18, 16)
	panel.add_child(inner)
	var column := Ui.vbox(10)
	inner.add_child(column)
	column.add_child(Ui.title(title, 22, Ui.INK))
	column.set_meta("panel", panel)
	return column


func _panel_for(column: VBoxContainer) -> Control:
	return column.get_meta("panel") as Control


func _slider_row(parent: VBoxContainer, title: String, key: String, on_change: Callable) -> Label:
	var row := Ui.vbox(4)
	var header := Ui.hbox(8)
	var label := Ui.label(title, 16, Ui.INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var value := Ui.label("", 15, Ui.INK_SOFT)
	header.add_child(value)
	row.add_child(header)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(Save.get_setting(key, 0.7))
	slider.custom_minimum_size = Vector2(0, 32)
	slider.value_changed.connect(func(next: float) -> void:
		on_change.call(next)
		value.text = "%d%%" % int(round(next * 100.0)))
	value.text = "%d%%" % int(round(slider.value * 100.0))
	row.add_child(slider)
	parent.add_child(row)
	return value


func _audio_card() -> Control:
	var column := _card("Sound")
	_slider_row(column, "Music", "music", func(next: float) -> void:
		Save.set_setting("music", next)
		Audio.apply_settings(Save.data["settings"]))
	_slider_row(column, "Effects", "sfx", func(next: float) -> void:
		Save.set_setting("sfx", next)
		Audio.apply_settings(Save.data["settings"]))
	return _panel_for(column)


func _play_card() -> Control:
	var column := _card("Play")
	var quality_row := Ui.hbox(8)
	var quality_label := Ui.label("Graphics", 16, Ui.INK)
	quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_row.add_child(quality_label)
	var options := OptionButton.new()
	options.add_item("Auto", 0)
	options.add_item("Low", 1)
	options.add_item("Medium", 2)
	options.add_item("High", 3)
	var current := String(Save.get_setting("quality", "auto"))
	var ids := {"auto": 0, "low": 1, "medium": 2, "high": 3}
	options.selected = int(ids.get(current, 0))
	options.item_selected.connect(func(index: int) -> void:
		var names := ["auto", "low", "medium", "high"]
		Save.set_setting("quality", names[index]))
	quality_row.add_child(options)
	column.add_child(quality_row)
	column.add_child(Ui.label("Low turns off shadows and heavy effects. Auto is fine on most phones.",
		14, Ui.INK_SOFT))
	_toggle(column, "Reduced motion", "reduced_motion",
		"Stops camera shake and sway. Recommended for motion sensitivity.")
	_toggle(column, "Left-handed buttons", "left_handed",
		"Mirrors the optional on-screen controls in runs.")
	return _panel_for(column)


func _access_card() -> Control:
	var column := _card("Accessibility")
	_toggle(column, "High-contrast hazards", "low_contrast_hazards",
		"Adds an outline to obstacles that are hard to read against the biome.")
	column.add_child(Ui.label("Controls: swipe, or use the arrow keys and space. Every action works with one thumb.",
		14, Ui.INK_SOFT))
	return _panel_for(column)


func _toggle(parent: VBoxContainer, title: String, key: String, blurb: String) -> void:
	var row := Ui.hbox(10)
	var text := Ui.vbox(2)
	var label := Ui.label(title, 16, Ui.INK)
	text.add_child(label)
	text.add_child(Ui.label(blurb, 13, Ui.INK_SOFT))
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var toggle := CheckButton.new()
	toggle.button_pressed = bool(Save.get_setting(key, false))
	toggle.toggled.connect(func(value: bool) -> void:
		Save.set_setting(key, value)
		if key == "reduced_motion":
			Audio.ui_click())
	row.add_child(toggle)
	parent.add_child(row)


func _save_card() -> Control:
	var column := _card("Save")
	column.add_child(Ui.label("Progress is written to this device after every trail and mirrored to the arcade when you are signed in.",
		14, Ui.INK_SOFT))
	column.add_child(Ui.label(Arcade.status_text(), 14, Ui.INK))
	var row := Ui.hbox(8)
	var sync := Ui.button("SYNC NOW", 17)
	sync.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sync.pressed.connect(func() -> void:
		Save.flush()
		Router.show_toast("Save written. Cloud sync runs through the arcade panel.")
	)
	row.add_child(sync)
	var reset := Ui.button("RESET PROGRESS", 17)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(_confirm_reset)
	row.add_child(reset)
	column.add_child(row)
	return _panel_for(column)


func _confirm_reset() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Reset progress?"
	dialog.dialog_text = "This erases campaign stars, records and unlocks on this device. It cannot be undone."
	dialog.ok_button_text = "Reset"
	dialog.cancel_button_text = "Keep my trail"
	dialog.confirmed.connect(func() -> void:
		Save.reset_progress()
		Audio.ui_back()
		Router.show_toast("Progress reset.")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _about_card() -> Control:
	var column := _card("About")
	column.add_child(Ui.label("Trailblazer Dash · v1.0.0 · a Little Joy Arcade original", 14, Ui.INK_SOFT))
	column.add_child(Ui.label("Character models, props and animations were authored for this game in Blender. Music, ambience and effects are synthesised from Tools/audio.py. Built with Godot 4.7.", 14, Ui.INK_SOFT))
	column.add_child(Ui.label("Fonts: Baloo 2 and Nunito (SIL Open Font License).", 14, Ui.INK_SOFT))
	return _panel_for(column)
