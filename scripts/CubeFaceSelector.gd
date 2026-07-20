class_name CubeFaceSelector
extends Control

signal face_pressed

var face_label := "Front"
var active := false


func _ready() -> void:
	custom_minimum_size = Vector2(112, 124)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_face(next_face_label: String, next_active: bool) -> void:
	face_label = next_face_label
	active = next_active
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		face_pressed.emit()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var panel_color := Color(0.045, 0.05, 0.055, 0.96) if active else Color(0.035, 0.04, 0.045, 0.82)
	var border_color := Color(0.78, 0.82, 0.86, 1.0) if active else Color(0.32, 0.36, 0.39, 0.9)
	var accent_color := Color(1.0, 0.94, 0.70, 1.0) if active else Color(0.60, 0.64, 0.66, 1.0)
	var text_color := Color(0.98, 0.98, 0.94, 1.0) if active else Color(0.72, 0.76, 0.78, 1.0)
	draw_rect(rect.grow(-1.0), panel_color, true)
	draw_rect(rect.grow(-1.0), border_color, false, 1.6)

	_draw_label(text_color, accent_color)
	_draw_cube(Vector2(size.x * 0.5, size.y * 0.73), minf(size.x, size.y) * 0.20, active)


func _draw_label(text_color: Color, accent_color: Color) -> void:
	var font := get_theme_default_font()
	var label := face_label.to_upper()
	var words := label.split(" ")
	var font_size := 15
	if words.size() == 2:
		font_size = 13
	elif words.size() == 3:
		font_size = 11
	elif words.size() > 3:
		font_size = 10
	var line_height := float(font_size) * 1.02
	var block_height := line_height * float(words.size())
	var start_y := 8.0 + (44.0 - block_height) * 0.5
	for index in range(words.size()):
		var word := String(words[index])
		var text_size := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var text_position := Vector2((size.x - text_size.x) * 0.5, start_y + line_height * float(index) + text_size.y * 0.78)
		draw_string(font, text_position + Vector2(1, 1), word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.0, 0.0, 0.0, 0.88))
		draw_string(font, text_position, word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	var underline_y := 56.0
	draw_line(Vector2(size.x * 0.22, underline_y), Vector2(size.x * 0.78, underline_y), accent_color, 2.0, true)


func _draw_cube(center: Vector2, radius: float, is_active: bool) -> void:
	var shadow_color := Color(0.0, 0.0, 0.0, 0.26)
	var edge_color := Color(0.04, 0.045, 0.05, 1.0)
	var front_color := Color(0.86, 0.88, 0.84, 1.0) if is_active else Color(0.50, 0.53, 0.54, 1.0)
	var top_color := Color(0.98, 0.94, 0.72, 1.0) if is_active else Color(0.62, 0.64, 0.64, 1.0)
	var side_color := Color(0.67, 0.75, 0.80, 1.0) if is_active else Color(0.35, 0.39, 0.42, 1.0)

	var front := PackedVector2Array([
		center + Vector2(-radius * 0.82, -radius * 0.18),
		center + Vector2(radius * 0.08, radius * 0.16),
		center + Vector2(radius * 0.08, radius * 1.0),
		center + Vector2(-radius * 0.82, radius * 0.58),
	])
	var top := PackedVector2Array([
		center + Vector2(-radius * 0.82, -radius * 0.18),
		center + Vector2(-radius * 0.08, -radius * 0.82),
		center + Vector2(radius * 0.82, -radius * 0.48),
		center + Vector2(radius * 0.08, radius * 0.16),
	])
	var side := PackedVector2Array([
		center + Vector2(radius * 0.08, radius * 0.16),
		center + Vector2(radius * 0.82, -radius * 0.48),
		center + Vector2(radius * 0.82, radius * 0.34),
		center + Vector2(radius * 0.08, radius * 1.0),
	])

	draw_circle(center + Vector2(4, 6), radius * 1.2, shadow_color)
	draw_colored_polygon(top, top_color)
	draw_colored_polygon(side, side_color)
	draw_colored_polygon(front, front_color)
	_draw_polyline_closed(top, edge_color, 2.0)
	_draw_polyline_closed(side, edge_color, 2.0)
	_draw_polyline_closed(front, edge_color, 2.0)


func _draw_polyline_closed(points: PackedVector2Array, color: Color, width: float) -> void:
	for index in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], color, width, true)