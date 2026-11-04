extends Control
## The Living Journey Map: a tall, pannable, zoomable Avelora with region
## nodes, completed routes and a bottom sheet for the selected region's levels.

const MAP_HEIGHT_FACTOR := 2.05
const NODE_RADIUS := 30.0
const NODE_HIT := 46.0

const POINTS := [
	Vector2(0.22, 0.045), Vector2(0.54, 0.075), Vector2(0.79, 0.135),
	Vector2(0.63, 0.205), Vector2(0.31, 0.245), Vector2(0.20, 0.315),
	Vector2(0.45, 0.365), Vector2(0.75, 0.405), Vector2(0.83, 0.475),
	Vector2(0.57, 0.515), Vector2(0.28, 0.555), Vector2(0.19, 0.625),
	Vector2(0.42, 0.665), Vector2(0.72, 0.705), Vector2(0.82, 0.775),
	Vector2(0.55, 0.815), Vector2(0.28, 0.855), Vector2(0.40, 0.915),
	Vector2(0.66, 0.945), Vector2(0.80, 0.985),
]

var selected_region := 1
var _zoom := 1.0
var _offset := Vector2.ZERO
var _dragging := false
var _drag_origin := Vector2.ZERO
var _drag_offset := Vector2.ZERO
var _sheet: PanelContainer
var _sheet_title: Label
var _sheet_sub: Label
var _level_grid: GridContainer
var _map_area := Rect2()
var _sheet_open := true
var _touches: Dictionary = {}
var _pinch_distance := 0.0
var _pinch_zoom := 1.0
var _actions_row: HBoxContainer


func setup(args: Dictionary) -> void:
	if args.has("region"):
		selected_region = clampi(int(args["region"]), 1, 20)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	selected_region = clampi(selected_region, 1, Campaign.unlocked_region_count())
	_build_header()
	_build_sheet()
	_center_on_selected()
	_refresh_sheet()
	Audio.play_music("aether")
	Audio.play_ambience("wind")


func _build_header() -> void:
	var bar := Ui.hbox(8)
	var wrap := Ui.margin(14, 12, 14, 0)
	wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.add_child(Ui.ghost_button("‹ MENU", 17))
	(bar.get_child(0) as Button).custom_minimum_size = Vector2(96, 42)
	(bar.get_child(0) as Button).pressed.connect(func() -> void:
		Audio.ui_back()
		Router.go("menu"))
	var title_box := Ui.vbox(0)
	var title := Ui.label("AVELORA", 30, Ui.CREAM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(title)
	var sub := Ui.label("%d of 20 regions charted" % Campaign.unlocked_region_count(),
		13, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	title_box.add_child(sub)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title_box)
	var zoom_out := Ui.ghost_button("−", 22)
	zoom_out.custom_minimum_size = Vector2(44, 42)
	zoom_out.pressed.connect(func() -> void: _set_zoom(_zoom - 0.15))
	bar.add_child(zoom_out)
	var zoom_in := Ui.ghost_button("+", 22)
	zoom_in.custom_minimum_size = Vector2(44, 42)
	zoom_in.pressed.connect(func() -> void: _set_zoom(_zoom + 0.15))
	bar.add_child(zoom_in)
	wrap.add_child(bar)
	add_child(wrap)


func _build_sheet() -> void:
	_sheet = Ui.panel()
	_sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_sheet.custom_minimum_size = Vector2(0, 300)
	_sheet.offset_top = -318
	_sheet.offset_bottom = -12
	_sheet.offset_left = 12
	_sheet.offset_right = -12
	add_child(_sheet)

	var inner := Ui.margin(18, 14, 18, 12)
	_sheet.add_child(inner)
	var column := Ui.vbox(8)
	inner.add_child(column)

	var header := Ui.hbox(8)
	_sheet_title = Ui.title("Sunmeadow Valley", 26, Ui.INK)
	_sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_sheet_title)
	var collapse := Ui.button("HIDE", 14, false, Ui.TEAL)
	collapse.custom_minimum_size = Vector2(78, 38)
	collapse.pressed.connect(_toggle_sheet)
	header.add_child(collapse)
	column.add_child(header)

	_sheet_sub = Ui.label("", 14, Ui.INK_SOFT)
	column.add_child(_sheet_sub)

	_actions_row = Ui.hbox(8)
	column.add_child(_actions_row)

	_level_grid = GridContainer.new()
	_level_grid.columns = 5
	_level_grid.add_theme_constant_override("h_separation", 7)
	_level_grid.add_theme_constant_override("v_separation", 7)
	column.add_child(_level_grid)


func _toggle_sheet() -> void:
	_sheet_open = not _sheet_open
	_sheet.visible = _sheet_open
	queue_redraw()


func _refresh_sheet() -> void:
	var region := Campaign.region(selected_region)
	if region.is_empty():
		return
	_sheet_title.text = String(region.get("name", "Avelora"))
	var progress := Campaign.region_progress(selected_region)
	var unlocked := Campaign.region_unlocked(selected_region)
	var blurb := String(region.get("tagline", ""))
	_sheet_sub.text = "%s  ·  %d/%d cleared  ·  %d / %d stars" % [
		blurb, int(progress["completed"]), int(progress["total"]),
		int(progress["stars"]), int(progress["max_stars"]),
	]
	if not unlocked:
		_sheet_sub.text = "Locked · clear %d trails in %s to open this region" % [
			Campaign.REGION_UNLOCK_REQUIREMENT,
			Campaign.region_name(selected_region - 1),
		]
	for child in _level_grid.get_children():
		child.queue_free()
	for entry in Campaign.levels_in_region(selected_region):
		var id := int(entry["id"])
		var stars := Save.level_stars(id)
		var open := Campaign.is_level_unlocked(id)
		var marks := "·"
		if stars > 0:
			marks = "*".repeat(stars)
		elif not open:
			marks = "LOCK"
		var text := "%d-%02d\n%s" % [int(entry["region"]), int(entry["local"]), marks]
		var button := Ui.button(text, 13, false, Ui.TEAL)
		button.custom_minimum_size = Vector2(58, 58)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not open:
			button.modulate = Color(1, 1, 1, 0.45)
		elif Save.is_level_complete(id):
			button.add_theme_stylebox_override("normal", Ui.style(Color("#f4e6c6"), 18, Ui.GOLD, 2))
		button.pressed.connect(func() -> void:
			if not open:
				Audio.ui_back()
				Router.show_toast("Clear %s to open this trail." % Campaign.level_label(Campaign.level(id - 1)))
				return
			Audio.ui_click()
			Router.go("run", {"mode": "campaign", "level_id": id}))
		_level_grid.add_child(button)

	for child in _actions_row.get_children():
		child.queue_free()
	var region_ids := Campaign.level_ids_in_region(selected_region)
	var next_in_region := int(region_ids[0])
	for id in region_ids:
		if Campaign.is_level_unlocked(int(id)) and not Save.is_level_complete(int(id)):
			next_in_region = int(id)
			break
	var play := Ui.button("CONTINUE  ·  %s" % Campaign.level_title(Campaign.level(next_in_region)), 18, true)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.pressed.connect(func() -> void:
		Audio.ui_click()
		Router.go("run", {"mode": "campaign", "level_id": next_in_region}))
	_actions_row.add_child(play)


func _center_on_selected() -> void:
	var target := _node_screen(selected_region - 1)
	var size := get_viewport_rect().size
	_offset.y += size.y * 0.55 - target.y
	_clamp_offset()
	queue_redraw()


func _map_size() -> Vector2:
	var width := get_viewport_rect().size.x
	return Vector2(width, width * MAP_HEIGHT_FACTOR)


func _node_position(index: int) -> Vector2:
	var point: Vector2 = POINTS[clampi(index, 0, POINTS.size() - 1)]
	var size := get_viewport_rect().size
	var content := _map_size()
	return Vector2(point.x * content.x, point.y * content.y) * _zoom + _offset


func _node_screen(index: int) -> Vector2:
	return _node_position(index)


func _clamp_offset() -> void:
	var size := get_viewport_rect().size
	var content := _map_size() * _zoom
	var min_y := -content.y + size.y * 0.62
	_offset.y = clampf(_offset.y, min_y, 40.0)
	_offset.x = clampf(_offset.x, -content.x * 0.12, content.x * 0.12)


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, 0.8, 1.7)
	_clamp_offset()
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0a1c22"))
	draw_rect(Rect2(Vector2.ZERO, size * Vector2(1, 0.4)), Color("#102c33"))
	draw_rect(Rect2(Vector2.ZERO, size * Vector2(1, 0.18)), Color("#153b40"))

	# terrain blobs: each region paints its own ground colour
	for i in range(Campaign.regions.size()):
		var region: Dictionary = Campaign.regions[i]
		var unlocked := Campaign.region_unlocked(int(region["id"]))
		var position := _node_position(i)
		if position.y < -160 or position.y > size.y + 160:
			continue
		var ground := Color(String(region.get("ground", "#6dbf5a")))
		if not unlocked:
			ground = ground.darkened(0.55).lerp(Color("#16323a"), 0.55)
		var radius := (74.0 + (i % 3) * 10.0) * _zoom
		draw_circle(position + Vector2(0, 6), radius, ground.darkened(0.22))
		draw_circle(position, radius * 0.94, ground)
		draw_circle(position + Vector2(-radius * 0.25, -radius * 0.22), radius * 0.42, ground.lightened(0.12))

	# route lines: completed legs glow gold
	for i in range(1, Campaign.regions.size()):
		var from := _node_position(i - 1)
		var to := _node_position(i)
		var region_id := int(Campaign.regions[i]["id"])
		var unlocked := Campaign.region_unlocked(region_id)
		var done := Save.completed_in_region(Campaign.level_ids_in_region(region_id)) > 0
		var color := Color(1, 1, 1, 0.14)
		if done:
			color = Color("#ffd166")
		elif unlocked:
			color = Color(1, 1, 1, 0.35)
		draw_line(from, to, Color(0.05, 0.1, 0.1, 0.35), 14.0 * _zoom)
		draw_line(from, to, color, 5.0 * _zoom)

	var next_region := Campaign.region_of_level(Campaign.next_level_id())
	for i in range(Campaign.regions.size()):
		var region: Dictionary = Campaign.regions[i]
		var id := int(region["id"])
		var position := _node_position(i)
		if position.y < -90 or position.y > size.y + 90:
			continue
		var unlocked := Campaign.region_unlocked(id)
		var progress := Campaign.region_progress(id)
		var accent := Color(String(region.get("accent", "#ffd166")))
		var fill := Color("#f8f1e2") if unlocked else Color("#2b444a")
		var ring := accent if unlocked else Color(0.5, 0.6, 0.62, 0.4)
		if id == next_region:
			var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.004) * 0.12
			draw_circle(position, NODE_RADIUS * _zoom * 1.55 * pulse, Color(accent.r, accent.g, accent.b, 0.22))
		draw_circle(position, NODE_RADIUS * _zoom, Color(0.02, 0.06, 0.07, 0.4))
		draw_circle(position, (NODE_RADIUS - 3.0) * _zoom, fill)
		draw_arc(position, (NODE_RADIUS - 3.0) * _zoom, 0, TAU, 32, ring, 3.0, true)
		var font := Ui.title_font()
		var label := str(id)
		var font_size := int(20 * _zoom)
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, position + Vector2(-text_size.x / 2.0, text_size.y * 0.35),
			label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size,
			Ui.INK if unlocked else Color(1, 1, 1, 0.5))
		if unlocked:
			var stars := int(progress["stars"])
			var pip := "*".repeat(mini(3, stars))
			draw_string(ThemeDB.fallback_font, position + Vector2(-16 * _zoom, (NODE_RADIUS + 16) * _zoom),
				pip, HORIZONTAL_ALIGNMENT_CENTER, -1, int(13 * _zoom), accent)
		else:
			draw_string(ThemeDB.fallback_font, position + Vector2(-7 * _zoom, 8 * _zoom),
				"?", HORIZONTAL_ALIGNMENT_CENTER, -1, int(20 * _zoom), Color(1, 1, 1, 0.55))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom + 0.08)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom - 0.08)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_origin = event.position
				_drag_offset = _offset
			else:
				_dragging = false
				if event.position.distance_to(_drag_origin) < 8.0:
					_tap(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_offset = _drag_offset + (event.position - _drag_origin)
		_clamp_offset()
		queue_redraw()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 2:
				_pinch_distance = _touch_distance()
				_pinch_zoom = _zoom
			elif _touches.size() == 1:
				_dragging = true
				_drag_origin = event.position
				_drag_offset = _offset
		else:
			_touches.erase(event.index)
			if _touches.size() == 0:
				_dragging = false
				if event.position.distance_to(_drag_origin) < 10.0:
					_tap(event.position)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var distance := _touch_distance()
			if _pinch_distance > 1.0:
				_set_zoom(_pinch_zoom * (distance / _pinch_distance))
		elif _dragging:
			_offset = _drag_offset + (event.position - _drag_origin)
			_clamp_offset()
			queue_redraw()


func _touch_distance() -> float:
	var values := _touches.values()
	if values.size() < 2:
		return 0.0
	return (values[0] as Vector2).distance_to(values[1] as Vector2)


func _tap(position: Vector2) -> void:
	if position.y < 66:
		return
	var best := -1
	var best_distance := NODE_HIT * _zoom
	for i in range(Campaign.regions.size()):
		var distance := position.distance_to(_node_position(i))
		if distance < best_distance:
			best_distance = distance
			best = i
	if best < 0:
		return
	var region_id := best + 1
	if not Campaign.region_unlocked(region_id):
		Audio.ui_back()
		Router.show_toast("This region is still uncharted.")
		return
	Audio.ui_click()
	selected_region = region_id
	_sheet.visible = true
	_sheet_open = true
	_refresh_sheet()
	queue_redraw()
