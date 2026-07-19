class_name CubeFaceSelector
extends Control

signal face_pressed

var face_label := "Front"
var active := false


func _ready() -> void:
	custom_minimum_size = Vector2(104, 104)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_face(next_face_label: String, next_active: bool) -> void:
	face_label = next_face_label
	active = next_active
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		face_pressed.emit()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.34
	var shadow_color := Color(0.02, 0.022, 0.025, 0.22)
	var edge_color := Color(0.06, 0.065, 0.07, 1.0)
	var front_color := Color(0.86, 0.88, 0.84, 1.0) if active else Color(0.52, 0.54, 0.55, 1.0)
	var top_color := Color(0.96, 0.94, 0.82, 1.0) if active else Color(0.66, 0.67, 0.66, 1.0)
	var side_color := Color(0.68, 0.74, 0.77, 1.0) if active else Color(0.38, 0.41, 0.43, 1.0)
	var text_color := Color(0.06, 0.065, 0.07, 1.0) if active else Color(0.2, 0.22, 0.23, 1.0)

	var front := PackedVector2Array([
		center + Vector2(-radius * 0.78, -radius * 0.18),
		center + Vector2(radius * 0.08, radius * 0.14),
		center + Vector2(radius * 0.08, radius * 0.96),
		center + Vector2(-radius * 0.78, radius * 0.56),
	])
	var top := PackedVector2Array([
		center + Vector2(-radius * 0.78, -radius * 0.18),
		center + Vector2(-radius * 0.08, -radius * 0.78),
		center + Vector2(radius * 0.78, -radius * 0.46),
		center + Vector2(radius * 0.08, radius * 0.14),
	])
	var side := PackedVector2Array([
		center + Vector2(radius * 0.08, radius * 0.14),
		center + Vector2(radius * 0.78, -radius * 0.46),
		center + Vector2(radius * 0.78, radius * 0.34),
		center + Vector2(radius * 0.08, radius * 0.96),
	])

	draw_circle(center + Vector2(5, 8), radius * 1.08, shadow_color)
	draw_colored_polygon(top, top_color)
	draw_colored_polygon(side, side_color)
	draw_colored_polygon(front, front_color)
	_draw_polyline_closed(top, edge_color, 2.4)
	_draw_polyline_closed(side, edge_color, 2.4)
	_draw_polyline_closed(front, edge_color, 2.4)

	var font := get_theme_default_font()
	var font_size := 12
	var words := face_label.split(" ")
	var line_height := float(font_size) * 0.92
	var block_height := line_height * float(words.size() - 1)
	for index in range(words.size()):
		var word := String(words[index])
		var text_size := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var text_position := center - text_size * 0.5 + Vector2(-radius * 0.36, radius * 0.21 - block_height * 0.5 + line_height * float(index))
		draw_string(font, text_position, word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


func _draw_polyline_closed(points: PackedVector2Array, color: Color, width: float) -> void:
	for index in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], color, width, true)
