class_name StarIcon
extends Control
## A drawn star. The body fonts ship without U+2605/U+2606, so typed stars
## rendered as empty boxes in the browser build; this draws them instead.

var filled: bool = true:
	set(value):
		filled = value
		queue_redraw()

var tint: Color = Ui.GOLD:
	set(value):
		tint = value
		queue_redraw()


static func make(is_filled: bool, star_size := 22.0, color := Ui.GOLD) -> StarIcon:
	var node := StarIcon.new()
	node.filled = is_filled
	node.tint = color
	node.custom_minimum_size = Vector2(star_size, star_size)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _draw() -> void:
	var center := size * 0.5
	var outer := minf(size.x, size.y) * 0.48
	var inner := outer * 0.44
	var points := PackedVector2Array()
	for index in range(10):
		var radius := outer if index % 2 == 0 else inner
		var angle := -PI * 0.5 + float(index) * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	if filled:
		draw_colored_polygon(points, tint)
	else:
		points.append(points[0])
		draw_polyline(points, tint, maxf(1.5, outer * 0.18), true)
