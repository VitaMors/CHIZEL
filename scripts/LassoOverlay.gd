class_name LassoOverlay
extends Control

var points: PackedVector2Array = PackedVector2Array()
var mouse_position: Vector2 = Vector2.ZERO
var active: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_points(next_points: PackedVector2Array) -> void:
	points = next_points
	queue_redraw()


func set_mouse_position(next_position: Vector2) -> void:
	mouse_position = next_position
	queue_redraw()


func set_active(next_active: bool) -> void:
	active = next_active
	queue_redraw()


func _draw() -> void:
	if not active:
		return

	var line_color := Color(0.95, 0.82, 0.35, 1.0)
	var fill_color := Color(0.95, 0.82, 0.35, 0.18)
	var handle_color := Color(1.0, 0.96, 0.75, 1.0)
	var first_color := Color(0.2, 0.85, 1.0, 1.0)

	if points.size() >= 3:
		draw_colored_polygon(points, fill_color)

	for i in range(points.size()):
		if i > 0:
			draw_line(points[i - 1], points[i], line_color, 2.0, true)
		draw_circle(points[i], 5.0, first_color if i == 0 else handle_color)
		draw_circle(points[i], 7.0, Color(line_color.r, line_color.g, line_color.b, 0.28))

	if points.size() > 0:
		draw_line(points[points.size() - 1], mouse_position, Color(line_color.r, line_color.g, line_color.b, 0.55), 1.5, true)
		if points.size() >= 3:
			draw_line(mouse_position, points[0], Color(line_color.r, line_color.g, line_color.b, 0.28), 1.0, true)
