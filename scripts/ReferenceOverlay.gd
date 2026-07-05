class_name ReferenceOverlay
extends Control

var reference_texture: Texture2D
var active := false
var opacity := 0.35
var image_scale := 1.0
var image_offset := Vector2.ZERO
var viewport_margin_left := 180.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_reference_texture(next_texture: Texture2D) -> void:
	reference_texture = next_texture
	fit_to_view()


func set_active(next_active: bool) -> void:
	active = next_active
	queue_redraw()


func set_opacity(next_opacity: float) -> void:
	opacity = clampf(next_opacity, 0.05, 1.0)
	queue_redraw()


func set_image_scale(next_scale: float) -> void:
	image_scale = clampf(next_scale, 0.05, 8.0)
	queue_redraw()


func nudge(delta: Vector2) -> void:
	image_offset += delta
	queue_redraw()


func center_image() -> void:
	image_offset = Vector2.ZERO
	queue_redraw()


func clear_reference() -> void:
	reference_texture = null
	image_offset = Vector2.ZERO
	image_scale = 1.0
	queue_redraw()


func fit_to_view() -> void:
	if reference_texture == null or size.x <= viewport_margin_left or size.y <= 0.0:
		return

	var image_size := reference_texture.get_size()
	if image_size.x <= 0.0 or image_size.y <= 0.0:
		return

	var view_size := Vector2(size.x - viewport_margin_left, size.y)
	var fit_scale := minf(view_size.x / image_size.x, view_size.y / image_size.y) * 0.72
	image_scale = clampf(fit_scale, 0.05, 8.0)
	image_offset = Vector2.ZERO
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if not active or reference_texture == null:
		return

	var image_size := reference_texture.get_size() * image_scale
	var view_origin := Vector2(viewport_margin_left, 0.0)
	var view_size := Vector2(size.x - viewport_margin_left, size.y)
	var top_left := view_origin + (view_size - image_size) * 0.5 + image_offset
	var image_rect := Rect2(top_left, image_size)
	draw_texture_rect(reference_texture, image_rect, false, Color(1.0, 1.0, 1.0, opacity))
