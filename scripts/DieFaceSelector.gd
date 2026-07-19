class_name DieFaceSelector
extends Control

signal die_pressed

var face_number := 12
var active := false


func _ready() -> void:
	custom_minimum_size = Vector2(104, 104)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_face(next_face_number: int, next_active: bool) -> void:
	face_number = next_face_number
	active = next_active
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		die_pressed.emit()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.36
	var shadow_color := Color(0.02, 0.022, 0.025, 0.24)
	var edge_color := Color(0.05, 0.055, 0.06, 1.0)
	var face_color := Color(0.93, 0.9, 0.78, 1.0) if active else Color(0.55, 0.57, 0.58, 1.0)
	var side_color := Color(0.76, 0.72, 0.58, 1.0) if active else Color(0.37, 0.39, 0.4, 1.0)
	var highlight_color := Color(1.0, 0.98, 0.84, 1.0) if active else Color(0.68, 0.7, 0.71, 1.0)
	var text_color := Color(0.05, 0.055, 0.06, 1.0) if active else Color(0.2, 0.22, 0.23, 1.0)

	draw_circle(center + Vector2(4, 7), radius * 1.08, shadow_color)

	var top := center + Vector2(0, -radius * 0.92)
	var upper_right := center + Vector2(radius * 0.86, -radius * 0.28)
	var lower_right := center + Vector2(radius * 0.6, radius * 0.84)
	var lower_left := center + Vector2(-radius * 0.6, radius * 0.84)
	var upper_left := center + Vector2(-radius * 0.86, -radius * 0.28)
	var middle := center + Vector2(0, radius * 0.08)

	draw_colored_polygon(PackedVector2Array([top, upper_right, middle, upper_left]), highlight_color)
	draw_colored_polygon(PackedVector2Array([upper_right, lower_right, lower_left, middle]), side_color)
	draw_colored_polygon(PackedVector2Array([upper_left, middle, lower_left]), side_color.darkened(0.08))

	var main_face := PackedVector2Array([
		center + Vector2(0, -radius * 0.64),
		center + Vector2(radius * 0.52, -radius * 0.24),
		center + Vector2(radius * 0.42, radius * 0.42),
		center + Vector2(0, radius * 0.66),
		center + Vector2(-radius * 0.42, radius * 0.42),
		center + Vector2(-radius * 0.52, -radius * 0.24),
	])
	draw_colored_polygon(main_face, face_color)

	_draw_polyline_closed(PackedVector2Array([top, upper_right, lower_right, lower_left, upper_left]), edge_color, 3.0)
	_draw_polyline_closed(main_face, edge_color, 2.4)
	draw_line(upper_left, middle, edge_color, 1.6, true)
	draw_line(upper_right, middle, edge_color, 1.6, true)
	draw_line(lower_left, middle, edge_color, 1.4, true)
	draw_line(lower_right, middle, edge_color, 1.4, true)

	var font := get_theme_default_font()
	var font_size := 30
	var text := str(face_number)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, center - text_size * 0.5 + Vector2(0, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


func _draw_polyline_closed(points: PackedVector2Array, color: Color, width: float) -> void:
	for index in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], color, width, true)
