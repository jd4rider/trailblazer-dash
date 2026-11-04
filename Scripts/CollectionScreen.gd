extends Control
## Collections: achievements, records, relics and credits.


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
	var title := Ui.title("COLLECTIONS", 32, Ui.CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(title)
	page.add_child(header)

	page.add_child(_records_card())
	page.add_child(_achievements_card())
	page.add_child(_credits_card())


func _card(title: String) -> VBoxContainer:
	var panel := Ui.panel()
	var inner := Ui.margin(18, 16, 18, 16)
	panel.add_child(inner)
	var column := Ui.vbox(9)
	inner.add_child(column)
	column.add_child(Ui.title(title, 22, Ui.INK))
	var wrapper := VBoxContainer.new()
	wrapper.add_child(panel)
	column.set_meta("wrapper", wrapper)
	return column


func _card_parent(column: VBoxContainer) -> Control:
	return (column.get_meta("wrapper") as Control)


func _records_card() -> Control:
	var column := _card("The journey so far")
	var stars := Save.total_stars()
	var rows := [
		["Trails cleared", "%d / %d" % [Save.completed_levels(), Campaign.TOTAL_LEVELS]],
		["Stars", "%d / %d" % [stars, Campaign.total_stars_possible()]],
		["Wayfinder Sparks", Ui.format_number(int(Save.data["progress"]["sparks"]))],
		["Relics recovered", str(int(Save.data["progress"]["relics"]))],
		["Regions charted", "%d / 20" % Campaign.unlocked_region_count()],
		["Endless best", "%d m" % int(Save.data["records"]["endless_best"])],
		["Daily streak", "%d days" % int(Save.data["records"]["daily_streak"])],
	]
	for row in rows:
		var line := Ui.hbox(8)
		var label := Ui.label(String(row[0]), 16, Ui.INK_SOFT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		line.add_child(Ui.label(String(row[1]), 17, Ui.INK))
		column.add_child(line)
	return _card_parent(column)


func _achievements_card() -> Control:
	var column := _card("Achievements")
	var unlocked := 0
	for entry in Save.ACHIEVEMENTS:
		var id := String(entry["id"])
		var has := Save.has_achievement(id)
		if has:
			unlocked += 1
		var row := Ui.hbox(10)
		var mark := StarIcon.make(has, 22.0, Ui.GOLD if has else Color(0.2, 0.25, 0.25, 0.25))
		row.add_child(mark)
		var text := Ui.vbox(1)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name := Ui.label(String(entry["name"]), 16, Ui.INK if has else Ui.INK_SOFT)
		text.add_child(name)
		text.add_child(Ui.label(String(entry["hint"]), 13, Ui.INK_SOFT))
		row.add_child(text)
		column.add_child(row)
	column.add_child(Ui.label("%d of %d earned" % [unlocked, Save.ACHIEVEMENTS.size()], 14, Ui.INK_SOFT))
	return _card_parent(column)


func _credits_card() -> Control:
	var column := _card("Credits")
	column.add_child(Ui.label("An original Little Joy Arcade production.", 15, Ui.INK))
	column.add_child(Ui.label("Characters, obstacles, landmarks and scenery: modelled, rigged and animated in Blender for this game (sources in Blender/).", 14, Ui.INK_SOFT))
	column.add_child(Ui.label("Music, ambience and sound effects: synthesised procedurally (Tools/audio.py), no third-party samples.", 14, Ui.INK_SOFT))
	column.add_child(Ui.label("Engine: Godot 4.7 (Compatibility renderer) · Fonts: Baloo 2 and Nunito, SIL OFL.", 14, Ui.INK_SOFT))
	return _card_parent(column)
