class_name Ui
## Shared look and feel for every screen.
##
## The UI is a warm paper layer over the 3D world: cream panels, deep teal ink,
## a mustard accent for the primary action and coral for warnings.

const INK := Color("#1e2f31")
const INK_SOFT := Color("#50625f")
const CREAM := Color("#f8f1e2")
const CREAM_DIM := Color("#e6dcc7")
const GOLD := Color("#e8a33d")
const GOLD_DEEP := Color("#c8822a")
const TEAL := Color("#2f7d78")
const TEAL_DEEP := Color("#1d5450")
const CORAL := Color("#dd6a4f")
const DEEP := Color("#0b1c20")
const WHITE_INK := Color(0.98, 0.96, 0.9)

const TITLE_FONT := "res://Assets/Fonts/Baloo2.ttf"
const BODY_FONT := "res://Assets/Fonts/Nunito-Regular.ttf"
const BOLD_FONT := "res://Assets/Fonts/Nunito-Bold.ttf"

static var _cache: Dictionary = {}


static func font(path: String) -> Font:
	if _cache.has(path):
		return _cache[path]
	var loaded: Font = null
	if ResourceLoader.exists(path):
		loaded = load(path)
	if loaded == null:
		loaded = ThemeDB.fallback_font
	_cache[path] = loaded
	return loaded


static func title_font() -> Font:
	var base := font(TITLE_FONT)
	if base == ThemeDB.fallback_font:
		var variation := FontVariation.new()
		variation.base_font = base
		variation.variation_embolden = 0.6
		return variation
	return base


static func body_font(bold := false) -> Font:
	return font(BOLD_FONT) if bold and ResourceLoader.exists(BOLD_FONT) else font(BODY_FONT)


static func style(color: Color, radius := 24, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	if border_width > 0:
		box.border_color = border
		box.set_border_width_all(border_width)
	return box


static func shadowed(color: Color, radius := 28, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var box := style(color, radius, border, 2 if border.a > 0.0 else 0)
	box.shadow_color = Color(0.02, 0.06, 0.07, 0.35)
	box.shadow_size = 16
	box.shadow_offset = Vector2(0, 8)
	return box


static func panel(color := CREAM, radius := 28) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", shadowed(color, radius))
	return node


static func inset(color: Color, radius := 18) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", style(color, radius))
	return node


static func label(text: String, size := 22, color := INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", body_font())
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.horizontal_alignment = align
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


static func title(text: String, size := 52, color := INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", title_font())
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.horizontal_alignment = align
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


static func button(text: String, size := 24, primary := false, accent := TEAL) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_override("font", body_font(true))
	node.add_theme_font_size_override("font_size", size)
	node.custom_minimum_size = Vector2(0, 58)
	node.focus_mode = Control.FOCUS_ALL
	var normal := style(GOLD if primary else CREAM, 20, Color(0, 0, 0, 0.0) if primary else accent, 2)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	normal.shadow_color = Color(0.02, 0.06, 0.07, 0.22)
	normal.shadow_size = 10
	normal.shadow_offset = Vector2(0, 5)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = (GOLD.lightened(0.08) if primary else CREAM.lightened(0.04))
	hover.border_color = accent
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = GOLD_DEEP if primary else CREAM_DIM
	pressed.shadow_size = 2
	pressed.shadow_offset = Vector2(0, 1)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), 20, GOLD, 3))
	node.add_theme_color_override("font_color", INK)
	node.add_theme_color_override("font_hover_color", INK)
	node.add_theme_color_override("font_pressed_color", INK)
	node.add_theme_color_override("font_focus_color", INK)
	return node


static func ghost_button(text: String, size := 20) -> Button:
	var node := button(text, size, false, Color(1, 1, 1, 0.35))
	node.add_theme_stylebox_override("normal", style(Color(1, 1, 1, 0.08), 18, Color(1, 1, 1, 0.25), 2))
	node.add_theme_stylebox_override("hover", style(Color(1, 1, 1, 0.16), 18, Color(1, 1, 1, 0.4), 2))
	node.add_theme_stylebox_override("pressed", style(Color(1, 1, 1, 0.2), 18))
	node.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), 18, GOLD, 3))
	node.add_theme_color_override("font_color", WHITE_INK)
	node.add_theme_color_override("font_hover_color", Color.WHITE)
	node.add_theme_color_override("font_pressed_color", Color.WHITE)
	node.add_theme_color_override("font_focus_color", Color.WHITE)
	return node


static func chip(text: String, color: Color, text_color := INK) -> PanelContainer:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", style(color, 14))
	var label_node := label(text, 17, text_color, HORIZONTAL_ALIGNMENT_CENTER)
	# A wrapping label reports almost no minimum width, so inside an HBox a chip
	# shrank to one character per line. Chips are single-line by design.
	label_node.autowrap_mode = TextServer.AUTOWRAP_OFF
	label_node.add_theme_constant_override("outline_size", 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	margin.add_child(label_node)
	holder.add_child(margin)
	return holder


static func vbox(separation := 12) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func hbox(separation := 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var node := MarginContainer.new()
	node.add_theme_constant_override("margin_left", left)
	node.add_theme_constant_override("margin_top", top)
	node.add_theme_constant_override("margin_right", right)
	node.add_theme_constant_override("margin_bottom", bottom)
	return node


static func spacer(height := 8) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node


static func grow() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node


static func gradient_background(top: Color, bottom: Color) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, top)
	gradient.set_color(1, bottom)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 32
	texture.height = 256
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func stars_row(stars: int, size := 22) -> HBoxContainer:
	var row := hbox(2)
	for i in range(3):
		row.add_child(StarIcon.make(
			i < stars, float(size), GOLD if i < stars else Color(0.15, 0.2, 0.2, 0.28)))
	return row


static func progress_bar(ratio: float, color := GOLD, height := 10) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	var background := style(Color(0, 0, 0, 0.14), height / 2)
	var fill := style(color, height / 2)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


static func format_number(value: int) -> String:
	var text := str(value)
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


static func format_time(seconds: float) -> String:
	var whole := int(round(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]
