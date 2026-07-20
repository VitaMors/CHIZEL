extends Node3D

const ModelVolumeScript := preload("res://scripts/ModelVolume.gd")
const LassoOverlayScript := preload("res://scripts/LassoOverlay.gd")
const ReferenceOverlayScript := preload("res://scripts/ReferenceOverlay.gd")
const CubeFaceSelectorScript := preload("res://scripts/CubeFaceSelector.gd")

enum ToolMode { SELECT, CHISEL }
enum CameraMode { PERSPECTIVE, ORTHOGRAPHIC }
enum LassoMode { SUBTRACT, ADD, EXTRUDE }

const FACE_CAMERA_DISTANCE := 6.0
const MAX_EXTRUDE_DISTANCE := 8.0
const EXTRUDE_VALUE_STEP := 0.05
const MIN_LASSO_POINT_DISTANCE := 4.0

var volume
var model_mesh: MeshInstance3D
var grid_mesh: MeshInstance3D
var perspective_camera: Camera3D
var ortho_camera: Camera3D
var active_camera: Camera3D
var view_light: DirectionalLight3D
var model_material: StandardMaterial3D
var grid_material: StandardMaterial3D
var lasso_overlay
var reference_overlay
var left_panel: PanelContainer
var status_label: Label
var view_label: Label
var face_selector
var mirror_toggle: CheckButton
var reference_toggle: CheckButton
var reference_drop_label: Label
var reference_dialog: FileDialog
var reference_opacity_slider: HSlider
var reference_scale_slider: HSlider
var extrude_panel: PanelContainer
var extrude_value_label: Label
var extrude_slider: HSlider

var tool_mode: ToolMode = ToolMode.SELECT
var camera_mode: CameraMode = CameraMode.PERSPECTIVE
var lasso_mode: LassoMode = LassoMode.SUBTRACT
var current_view := "Perspective"
var face_view_direction := Vector3(0, 0, 1)
var face_view_up := Vector3.UP
var lasso_points_screen := PackedVector2Array()
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var mirror_x_enabled := false
var left_shift_down := false
var last_mouse_position := Vector2.ZERO
var reference_states: Dictionary = {}

var orbit_distance := 6.0
var orbit_yaw := deg_to_rad(35.0)
var orbit_pitch := deg_to_rad(-25.0)
var orbit_target := Vector3.ZERO
var is_orbiting := false
var is_panning := false

var has_pending_extrude := false
var pending_extrude_polygon_model := PackedVector2Array()
var pending_extrude_axis_x := Vector3.RIGHT
var pending_extrude_axis_y := Vector3.UP
var pending_extrude_view_name := ""
var pending_extrude_original_state: Dictionary = {}
var pending_extrude_value := 0.0


func _ready() -> void:
	volume = ModelVolumeScript.new(Vector3i(32, 32, 32), 0.125)
	_setup_world()
	_setup_ui()
	_setup_file_drop()
	_rebuild_model_mesh()
	_set_perspective_view()
	_set_status("Ready. Pick a face angle, then use Chisel. Hold Shift for grid-aligned lasso lines.")


func _setup_world() -> void:
	model_material = StandardMaterial3D.new()
	model_material.vertex_color_use_as_albedo = true
	model_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	model_material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	model_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	model_material.roughness = 0.72

	model_mesh = MeshInstance3D.new()
	model_mesh.material_override = model_material
	add_child(model_mesh)

	grid_material = StandardMaterial3D.new()
	grid_material.albedo_color = Color(0.22, 0.25, 0.27, 0.55)
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	grid_mesh = MeshInstance3D.new()
	grid_mesh.material_override = grid_material
	grid_mesh.visible = false
	add_child(grid_mesh)

	perspective_camera = Camera3D.new()
	perspective_camera.fov = 45.0
	add_child(perspective_camera)

	ortho_camera = Camera3D.new()
	ortho_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	ortho_camera.size = 5.0
	add_child(ortho_camera)

	var key_light := DirectionalLight3D.new()
	key_light.light_energy = 1.4
	key_light.rotation_degrees = Vector3(-45, 35, 0)
	key_light.shadow_enabled = false
	add_child(key_light)

	view_light = DirectionalLight3D.new()
	view_light.light_energy = 0.85
	view_light.shadow_enabled = false
	add_child(view_light)
	_update_perspective_camera()


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)

	reference_overlay = ReferenceOverlayScript.new()
	reference_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	reference_overlay.viewport_margin_left = 180.0
	root.add_child(reference_overlay)

	lasso_overlay = LassoOverlayScript.new()
	lasso_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(lasso_overlay)

	left_panel = PanelContainer.new()
	left_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.custom_minimum_size = Vector2(180, 0)
	left_panel.offset_right = 180.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.05, 0.055, 0.95)
	panel_style.border_color = Color(0.15, 0.16, 0.17, 1.0)
	panel_style.set_border_width(SIDE_RIGHT, 1)
	left_panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(left_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var title := Label.new()
	title.text = "CHIZEL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	_add_section_label(box, "Tools")
	_add_button(box, "Select", Callable(self, "_set_tool_select"))
	_add_button(box, "Chisel", Callable(self, "_set_tool_chisel"))
	_add_button(box, "Subtract", Callable(self, "_set_lasso_subtract"))
	_add_button(box, "Add", Callable(self, "_set_lasso_add"))
	_add_button(box, "Extrude", Callable(self, "_set_lasso_extrude"))
	mirror_toggle = CheckButton.new()
	mirror_toggle.text = "Mirror X"
	mirror_toggle.toggled.connect(Callable(self, "_set_mirror_x"))
	box.add_child(mirror_toggle)
	_add_button(box, "Reset Model", Callable(self, "_reset_model"))
	_add_button(box, "Clean Solid", Callable(self, "_clean_solid_model"))
	_add_button(box, "Undo", Callable(self, "_undo"))
	_add_button(box, "Redo", Callable(self, "_redo"))
	_add_button(box, "Export GLB", Callable(self, "_export_glb_to_downloads"))

	_add_section_label(box, "Cut Face")
	_add_button(box, "Perspective", Callable(self, "_set_perspective_view"))
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(150, 72)
	box.add_child(badge)
	var badge_box := VBoxContainer.new()
	badge.add_child(badge_box)
	var caption := Label.new()
	caption.text = "VIEW"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 10)
	badge_box.add_child(caption)
	view_label = Label.new()
	view_label.text = "PERSPECTIVE"
	view_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	view_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view_label.add_theme_font_size_override("font_size", 16)
	view_label.add_theme_constant_override("outline_size", 4)
	badge_box.add_child(view_label)

	var picker := VBoxContainer.new()
	picker.custom_minimum_size = Vector2(150, 212)
	box.add_child(picker)
	var up_row := HBoxContainer.new()
	up_row.alignment = BoxContainer.ALIGNMENT_CENTER
	picker.add_child(up_row)
	_add_face_arrow_button(up_row, "^", Callable(self, "_nudge_face_view").bind(Vector2(0, 1)))
	var mid_row := HBoxContainer.new()
	mid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mid_row.add_theme_constant_override("separation", 6)
	picker.add_child(mid_row)
	_add_face_arrow_button(mid_row, "<", Callable(self, "_nudge_face_view").bind(Vector2(-1, 0)))
	face_selector = CubeFaceSelectorScript.new()
	face_selector.custom_minimum_size = Vector2(112, 124)
	face_selector.face_pressed.connect(Callable(self, "_set_current_face_view"))
	mid_row.add_child(face_selector)
	_add_face_arrow_button(mid_row, ">", Callable(self, "_nudge_face_view").bind(Vector2(1, 0)))
	var down_row := HBoxContainer.new()
	down_row.alignment = BoxContainer.ALIGNMENT_CENTER
	picker.add_child(down_row)
	_add_face_arrow_button(down_row, "v", Callable(self, "_nudge_face_view").bind(Vector2(0, -1)))

	_add_section_label(box, "Reference")
	reference_toggle = CheckButton.new()
	reference_toggle.text = "Show Ref"
	reference_toggle.button_pressed = true
	reference_toggle.toggled.connect(Callable(self, "_set_reference_visible"))
	box.add_child(reference_toggle)
	var drop_zone := PanelContainer.new()
	drop_zone.custom_minimum_size = Vector2(150, 70)
	drop_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	drop_zone.gui_input.connect(Callable(self, "_on_reference_drop_zone_gui_input"))
	box.add_child(drop_zone)
	reference_drop_label = Label.new()
	reference_drop_label.text = "Drop ref image"
	reference_drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reference_drop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reference_drop_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drop_zone.add_child(reference_drop_label)
	_add_button(box, "Import Ref", Callable(self, "_open_reference_dialog"))
	_add_button(box, "Clear Ref", Callable(self, "_clear_reference_for_current_view"))
	reference_opacity_slider = HSlider.new()
	reference_opacity_slider.min_value = 0.05
	reference_opacity_slider.max_value = 1.0
	reference_opacity_slider.step = 0.05
	reference_opacity_slider.value = 0.35
	reference_opacity_slider.value_changed.connect(Callable(self, "_set_reference_opacity"))
	box.add_child(reference_opacity_slider)
	reference_scale_slider = HSlider.new()
	reference_scale_slider.min_value = 0.1
	reference_scale_slider.max_value = 4.0
	reference_scale_slider.step = 0.05
	reference_scale_slider.value = 1.0
	reference_scale_slider.value_changed.connect(Callable(self, "_set_reference_scale"))
	box.add_child(reference_scale_slider)
	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(150, 80)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 12)
	box.add_child(status_label)
	_setup_extrude_panel(root)
	_setup_reference_dialog()


func _setup_extrude_panel(root: Control) -> void:
	extrude_panel = PanelContainer.new()
	extrude_panel.visible = false
	extrude_panel.custom_minimum_size = Vector2(320, 128)
	extrude_panel.anchor_left = 0.5
	extrude_panel.anchor_right = 0.5
	extrude_panel.offset_left = -160.0
	extrude_panel.offset_right = 160.0
	extrude_panel.offset_top = 18.0
	extrude_panel.offset_bottom = 146.0
	root.add_child(extrude_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	extrude_panel.add_child(box)
	var title := Label.new()
	title.text = "Extrude"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	extrude_value_label = Label.new()
	extrude_value_label.text = "0.00"
	extrude_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extrude_value_label.add_theme_font_size_override("font_size", 24)
	box.add_child(extrude_value_label)
	extrude_slider = HSlider.new()
	extrude_slider.min_value = -MAX_EXTRUDE_DISTANCE
	extrude_slider.max_value = MAX_EXTRUDE_DISTANCE
	extrude_slider.step = EXTRUDE_VALUE_STEP
	extrude_slider.value_changed.connect(Callable(self, "_preview_pending_extrude"))
	box.add_child(extrude_slider)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_add_button(row, "Apply", Callable(self, "_commit_pending_extrude"))
	_add_button(row, "Cancel", Callable(self, "_cancel_pending_extrude"))


func _setup_reference_dialog() -> void:
	reference_dialog = FileDialog.new()
	reference_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	reference_dialog.access = FileDialog.ACCESS_FILESYSTEM
	reference_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image files"])
	reference_dialog.file_selected.connect(Callable(self, "_load_reference_image"))
	add_child(reference_dialog)


func _setup_file_drop() -> void:
	get_window().files_dropped.connect(Callable(self, "_on_files_dropped"))


func _add_section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	parent.add_child(label)


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 34)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _add_face_arrow_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(34, 30)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_SHIFT or key_event.physical_keycode == KEY_SHIFT:
			if key_event.location == KEY_LOCATION_LEFT or key_event.location == KEY_LOCATION_UNSPECIFIED:
				left_shift_down = key_event.pressed
				_refresh_lasso_preview()
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_ENTER, KEY_KP_ENTER:
					if has_pending_extrude:
						_commit_pending_extrude()
					elif tool_mode == ToolMode.CHISEL:
						_apply_lasso()
				KEY_ESCAPE:
					if has_pending_extrude:
						_cancel_pending_extrude()
					else:
						_clear_lasso()
				KEY_BACKSPACE:
					if lasso_points_screen.size() > 0:
						lasso_points_screen.remove_at(lasso_points_screen.size() - 1)
						lasso_overlay.set_points(lasso_points_screen)
						_refresh_lasso_preview()
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		last_mouse_position = motion.position
		if is_orbiting and camera_mode == CameraMode.PERSPECTIVE:
			orbit_yaw -= motion.relative.x * 0.008
			orbit_pitch = clampf(orbit_pitch - motion.relative.y * 0.008, deg_to_rad(-82.0), deg_to_rad(82.0))
			_update_perspective_camera()
		elif is_panning:
			_pan_camera(motion.relative)
		_refresh_lasso_preview()
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		last_mouse_position = mouse_event.position
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			is_orbiting = mouse_event.pressed
			return
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = mouse_event.pressed
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom_camera(-1.0)
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom_camera(1.0)
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and _should_place_lasso_point(mouse_event.position):
			_handle_lasso_mouse(mouse_event)


func _should_place_lasso_point(position: Vector2) -> bool:
	return tool_mode == ToolMode.CHISEL and camera_mode == CameraMode.ORTHOGRAPHIC and not has_pending_extrude and not _ui_contains_point(position)


func _ui_contains_point(position: Vector2) -> bool:
	return (left_panel != null and left_panel.get_global_rect().has_point(position)) or (extrude_panel != null and extrude_panel.visible and extrude_panel.get_global_rect().has_point(position))


func _handle_lasso_mouse(event: InputEventMouseButton) -> void:
	var point := _lasso_effective_screen_point(event.position)
	if lasso_points_screen.size() >= 3 and point.distance_to(lasso_points_screen[0]) < 14.0:
		_apply_lasso()
		return
	if lasso_points_screen.size() > 0 and point.distance_to(lasso_points_screen[lasso_points_screen.size() - 1]) < MIN_LASSO_POINT_DISTANCE:
		_set_status("Point skipped because it is too close to the previous point.")
		return
	lasso_points_screen.append(point)
	lasso_overlay.set_points(lasso_points_screen)
	_refresh_lasso_preview()
	var snap_note := " Shift snap is on." if _is_lasso_snap_active() else ""
	_set_status("%s point added.%s Enter applies; Backspace removes; Escape cancels." % [_lasso_mode_name(), snap_note])


func _refresh_lasso_preview() -> void:
	if lasso_overlay == null or not lasso_overlay.active:
		return
	lasso_overlay.set_mouse_position(_lasso_effective_screen_point(last_mouse_position))


func _lasso_effective_screen_point(raw_screen_point: Vector2) -> Vector2:
	if not _is_lasso_snap_active():
		return raw_screen_point
	var axis_x := ortho_camera.global_transform.basis.x.normalized()
	var axis_y := ortho_camera.global_transform.basis.y.normalized()
	var world_point := _screen_point_on_model_plane(raw_screen_point)
	var target_model := Vector2(world_point.dot(axis_x), world_point.dot(axis_y))
	var snapped_model := _snap_lasso_model_point(target_model, axis_x, axis_y)
	return _model_plane_point_to_screen(snapped_model, axis_x, axis_y)


func _is_lasso_snap_active() -> bool:
	return left_shift_down and tool_mode == ToolMode.CHISEL and camera_mode == CameraMode.ORTHOGRAPHIC


func _snap_lasso_model_point(target_model: Vector2, axis_x: Vector3, axis_y: Vector3) -> Vector2:
	var step := _lasso_grid_step()
	if step <= 0.0001:
		return target_model
	if lasso_points_screen.is_empty():
		return Vector2(round(target_model.x / step) * step, round(target_model.y / step) * step)
	var last_world := _screen_point_on_model_plane(lasso_points_screen[lasso_points_screen.size() - 1])
	var origin_model := Vector2(last_world.dot(axis_x), last_world.dot(axis_y))
	var offset := target_model - origin_model
	if offset.length_squared() <= 0.000001:
		return origin_model
	var directions := [
		Vector2.RIGHT,
		Vector2(1, 1).normalized(),
		Vector2.UP,
		Vector2(-1, 1).normalized(),
		Vector2.LEFT,
		Vector2(-1, -1).normalized(),
		Vector2.DOWN,
		Vector2(1, -1).normalized(),
	]
	var best_direction := Vector2.RIGHT
	var best_dot := -INF
	var offset_normal := offset.normalized()
	for direction in directions:
		var dot := offset_normal.dot(direction)
		if dot > best_dot:
			best_dot = dot
			best_direction = direction
	if absf(best_direction.x) > 0.5 and absf(best_direction.y) > 0.5:
		var step_count: int = maxi(1, roundi(maxf(absf(offset.x), absf(offset.y)) / step))
		return origin_model + Vector2(signf(best_direction.x), signf(best_direction.y)) * step * float(step_count)
	if absf(best_direction.x) > absf(best_direction.y):
		var step_count_x: int = maxi(1, roundi(absf(offset.x) / step))
		return origin_model + Vector2(signf(best_direction.x) * step * float(step_count_x), 0.0)
	var step_count_y: int = maxi(1, roundi(absf(offset.y) / step))
	return origin_model + Vector2(0.0, signf(best_direction.y) * step * float(step_count_y))


func _model_plane_point_to_screen(point: Vector2, axis_x: Vector3, axis_y: Vector3) -> Vector2:
	return ortho_camera.unproject_position(axis_x * point.x + axis_y * point.y)


func _lasso_grid_step() -> float:
	return volume.voxel_size * 2.0 if volume != null else 0.25


func _set_tool_select() -> void:
	_cancel_pending_extrude(false)
	tool_mode = ToolMode.SELECT
	lasso_overlay.set_active(false)
	_clear_lasso()
	_set_status("Select mode.")


func _set_tool_chisel() -> void:
	tool_mode = ToolMode.CHISEL
	if camera_mode == CameraMode.ORTHOGRAPHIC:
		lasso_overlay.set_active(true)
	_set_status("Chisel mode. Hold Shift for grid-aligned lasso lines.")


func _set_lasso_subtract() -> void:
	_set_tool_chisel()
	lasso_mode = LassoMode.SUBTRACT
	_clear_lasso()


func _set_lasso_add() -> void:
	_set_tool_chisel()
	lasso_mode = LassoMode.ADD
	_clear_lasso()


func _set_lasso_extrude() -> void:
	_set_tool_chisel()
	lasso_mode = LassoMode.EXTRUDE
	_clear_lasso()


func _set_mirror_x(enabled: bool) -> void:
	mirror_x_enabled = enabled


func _set_current_face_view() -> void:
	_set_cube_face_view(face_view_direction, face_view_up)


func _nudge_face_view(delta: Vector2) -> void:
	var direction: Vector3 = face_view_direction.normalized()
	var up: Vector3 = _orthogonalized_up(direction, face_view_up)
	var axis_x: Vector3 = up.cross(direction).normalized()
	var axis_y: Vector3 = direction.cross(axis_x).normalized()
	var next_direction := direction
	var next_up := up
	if delta.x > 0.0:
		next_direction = (direction + axis_x).normalized()
	elif delta.x < 0.0:
		next_direction = (direction - axis_x).normalized()
	elif delta.y > 0.0:
		next_direction = (direction + axis_y).normalized()
		next_up = (axis_y - direction).normalized()
	elif delta.y < 0.0:
		next_direction = (direction - axis_y).normalized()
		next_up = (axis_y + direction).normalized()
	_set_cube_face_view(next_direction, next_up)


func _set_cube_face_view(view_direction: Vector3, up_hint: Vector3) -> void:
	var direction := _normalized_view_direction(view_direction)
	var up := _orthogonalized_up(direction, up_hint)
	_set_orthographic_direction(_face_name_for_direction(direction), direction, up)


func _set_orthographic_direction(view_name: String, view_direction: Vector3, up_hint: Vector3) -> void:
	_cancel_pending_extrude(false)
	camera_mode = CameraMode.ORTHOGRAPHIC
	current_view = view_name
	active_camera = ortho_camera
	perspective_camera.current = false
	ortho_camera.current = true
	grid_mesh.visible = true
	_clear_lasso()
	face_view_direction = _normalized_view_direction(view_direction)
	face_view_up = _orthogonalized_up(face_view_direction, up_hint)
	ortho_camera.position = face_view_direction * FACE_CAMERA_DISTANCE
	ortho_camera.look_at(Vector3.ZERO, face_view_up)
	_update_view_light()
	volume.set_display_axes(ortho_camera.global_transform.basis.x.normalized(), ortho_camera.global_transform.basis.y.normalized(), current_view)
	_rebuild_model_mesh()
	_build_grid()
	if tool_mode == ToolMode.CHISEL:
		lasso_overlay.set_active(true)
	_update_view_label()
	_update_reference_visibility()
	_set_status("%s selected for lasso cuts." % current_view)


func _set_perspective_view() -> void:
	_cancel_pending_extrude(false)
	camera_mode = CameraMode.PERSPECTIVE
	current_view = "Perspective"
	active_camera = perspective_camera
	perspective_camera.current = true
	ortho_camera.current = false
	grid_mesh.visible = false
	lasso_overlay.set_active(false)
	_clear_lasso()
	volume.clear_display_axes()
	_update_perspective_camera()
	_rebuild_model_mesh()
	_update_view_label()
	_update_reference_visibility()


func _face_name_for_direction(direction: Vector3) -> String:
	var normalized_direction := _normalized_view_direction(direction)
	var components: Array = [
		{"name": "Front" if normalized_direction.z > 0.0 else "Back", "amount": absf(normalized_direction.z), "priority": 0},
		{"name": "Right" if normalized_direction.x > 0.0 else "Left", "amount": absf(normalized_direction.x), "priority": 1},
		{"name": "Top" if normalized_direction.y > 0.0 else "Bottom", "amount": absf(normalized_direction.y), "priority": 2},
	]
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var amount_delta: float = float(a["amount"]) - float(b["amount"])
		if absf(amount_delta) > 0.0001:
			return amount_delta > 0.0
		return int(a["priority"]) < int(b["priority"])
	)
	var strongest: Dictionary = components[0] as Dictionary
	var second: Dictionary = components[1] as Dictionary
	var strongest_amount: float = float(strongest["amount"])
	var second_amount: float = float(second["amount"])
	if strongest_amount >= 0.985 and second_amount <= 0.12:
		return str(strongest["name"])
	var cutoff: float = maxf(0.18, strongest_amount * 0.35)
	var names: Array[String] = []
	for component_value in components:
		var component: Dictionary = component_value as Dictionary
		if float(component["amount"]) >= cutoff:
			names.append(str(component["name"]))
	if names.size() == 1 and second_amount > 0.08:
		names.append(str(second["name"]))
	return "%s Angle" % " ".join(names)


func _normalized_view_direction(direction: Vector3) -> Vector3:
	return direction.normalized() if direction.length_squared() >= 0.0001 else Vector3(0, 0, 1)


func _orthogonalized_up(direction: Vector3, up_hint: Vector3) -> Vector3:
	var normalized_direction := _normalized_view_direction(direction)
	var up := up_hint - normalized_direction * up_hint.dot(normalized_direction)
	if up.length_squared() < 0.0001:
		up = Vector3.FORWARD if absf(normalized_direction.dot(Vector3.UP)) > 0.9 else Vector3.UP
		up -= normalized_direction * up.dot(normalized_direction)
	return up.normalized()


func _update_perspective_camera() -> void:
	var direction := Vector3(cos(orbit_pitch) * sin(orbit_yaw), sin(orbit_pitch), cos(orbit_pitch) * cos(orbit_yaw))
	perspective_camera.position = orbit_target + direction * orbit_distance
	perspective_camera.look_at(orbit_target, Vector3.UP)
	_update_view_light()


func _update_view_light() -> void:
	if view_light != null and active_camera != null:
		view_light.global_transform = active_camera.global_transform


func _update_view_label() -> void:
	if view_label:
		view_label.text = current_view.to_upper()
	if face_selector:
		face_selector.set_face(_face_name_for_direction(face_view_direction), camera_mode == CameraMode.ORTHOGRAPHIC)


func _pan_camera(relative: Vector2) -> void:
	if active_camera == null:
		return
	var axis_x := active_camera.global_transform.basis.x.normalized()
	var axis_y := active_camera.global_transform.basis.y.normalized()
	var delta := (-axis_x * relative.x + axis_y * relative.y) * 0.006 * orbit_distance
	if camera_mode == CameraMode.PERSPECTIVE:
		orbit_target += delta
		_update_perspective_camera()
	else:
		ortho_camera.position += delta
		_build_grid()


func _zoom_camera(direction: float) -> void:
	if camera_mode == CameraMode.PERSPECTIVE:
		orbit_distance = clampf(orbit_distance + direction * 0.35, 2.5, 18.0)
		_update_perspective_camera()
	else:
		ortho_camera.size = clampf(ortho_camera.size + direction * 0.35, 1.5, 12.0)
		_build_grid()
		_refresh_lasso_preview()


func _apply_lasso() -> void:
	if has_pending_extrude:
		return
	if lasso_points_screen.size() < 3:
		_clear_lasso()
		_set_status("Chisel cancelled because the lasso needs at least three points.")
		return
	var polygon_model := PackedVector2Array()
	var axis_x := ortho_camera.global_transform.basis.x.normalized()
	var axis_y := ortho_camera.global_transform.basis.y.normalized()
	for screen_point in lasso_points_screen:
		var world_point := _screen_point_on_model_plane(screen_point)
		polygon_model.append(Vector2(world_point.dot(axis_x), world_point.dot(axis_y)))
	if lasso_mode == LassoMode.EXTRUDE:
		_start_extrude_adjustment(polygon_model, axis_x, axis_y)
		return
	_push_undo()
	var changed: int = volume.add_through(polygon_model, axis_x, axis_y, mirror_x_enabled, current_view) if lasso_mode == LassoMode.ADD else volume.carve_through(polygon_model, axis_x, axis_y, false, mirror_x_enabled, current_view)
	if changed == 0:
		undo_stack.pop_back()
		_set_status("The lasso did not change any material.")
	else:
		redo_stack.clear()
		_rebuild_model_mesh()
		_set_status("Chisel changed %d pieces of material. Stored cuts: %d." % [changed, volume.cut_count()])
	_clear_lasso()


func _start_extrude_adjustment(polygon_model: PackedVector2Array, axis_x: Vector3, axis_y: Vector3) -> void:
	pending_extrude_original_state = volume.clone_state()
	pending_extrude_polygon_model = polygon_model.duplicate()
	pending_extrude_axis_x = axis_x
	pending_extrude_axis_y = axis_y
	pending_extrude_view_name = current_view
	pending_extrude_value = 0.0
	has_pending_extrude = true
	if extrude_slider:
		extrude_slider.set_value_no_signal(0.0)
	_update_extrude_value_label()
	if extrude_panel:
		extrude_panel.visible = true
	_clear_lasso()


func _preview_pending_extrude(value: float) -> void:
	if not has_pending_extrude:
		return
	pending_extrude_value = value
	volume.restore_state(pending_extrude_original_state)
	if absf(value) > 0.0001:
		volume.extrude_surface(pending_extrude_polygon_model, pending_extrude_axis_x, pending_extrude_axis_y, value, mirror_x_enabled, pending_extrude_view_name)
	_rebuild_model_mesh()
	_update_extrude_value_label()


func _commit_pending_extrude() -> void:
	if not has_pending_extrude:
		return
	var final_value := pending_extrude_value
	var original_state := pending_extrude_original_state.duplicate(true)
	var polygon_model := pending_extrude_polygon_model.duplicate()
	var axis_x := pending_extrude_axis_x
	var axis_y := pending_extrude_axis_y
	var view_name := pending_extrude_view_name
	volume.restore_state(original_state)
	_finish_pending_extrude()
	if absf(final_value) <= 0.0001:
		_rebuild_model_mesh()
		return
	_push_undo()
	var changed: int = volume.extrude_surface(polygon_model, axis_x, axis_y, final_value, mirror_x_enabled, view_name)
	if changed == 0:
		undo_stack.pop_back()
	else:
		redo_stack.clear()
	_rebuild_model_mesh()


func _cancel_pending_extrude(show_status: bool = true) -> void:
	if not has_pending_extrude:
		return
	volume.restore_state(pending_extrude_original_state)
	_finish_pending_extrude()
	_rebuild_model_mesh()
	if show_status:
		_set_status("Extrude cancelled.")


func _finish_pending_extrude() -> void:
	has_pending_extrude = false
	pending_extrude_polygon_model = PackedVector2Array()
	pending_extrude_original_state = {}
	pending_extrude_value = 0.0
	if extrude_panel:
		extrude_panel.visible = false


func _update_extrude_value_label() -> void:
	if extrude_value_label:
		var prefix := "+" if pending_extrude_value > 0.0 else ""
		extrude_value_label.text = "%s%.2f" % [prefix, pending_extrude_value]


func _screen_point_on_model_plane(screen_point: Vector2) -> Vector3:
	var plane := Plane(-ortho_camera.global_transform.basis.z.normalized(), 0.0)
	var origin := ortho_camera.project_ray_origin(screen_point)
	var direction := ortho_camera.project_ray_normal(screen_point)
	var hit = plane.intersects_ray(origin, direction)
	return Vector3.ZERO if hit == null else hit


func _clear_lasso() -> void:
	lasso_points_screen.clear()
	if lasso_overlay:
		lasso_overlay.set_points(lasso_points_screen)
		_refresh_lasso_preview()


func _rebuild_model_mesh() -> void:
	model_mesh.mesh = volume.build_mesh()
	if model_mesh.mesh != null and model_mesh.mesh.get_surface_count() > 0:
		model_mesh.mesh.surface_set_material(0, model_material)


func _build_grid() -> void:
	var axis_x := ortho_camera.global_transform.basis.x.normalized()
	var axis_y := ortho_camera.global_transform.basis.y.normalized()
	var line_vertices := PackedVector3Array()
	var half_extent := 2.5
	var step := _lasso_grid_step()
	var count := int(round((half_extent * 2.0) / step))
	for i in range(count + 1):
		var value := -half_extent + i * step
		line_vertices.append(axis_x * value + axis_y * -half_extent)
		line_vertices.append(axis_x * value + axis_y * half_extent)
		line_vertices.append(axis_x * -half_extent + axis_y * value)
		line_vertices.append(axis_x * half_extent + axis_y * value)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = line_vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	grid_mesh.mesh = mesh


func _push_undo() -> void:
	undo_stack.append(volume.clone_state())
	if undo_stack.size() > 64:
		undo_stack.pop_front()


func _undo() -> void:
	_cancel_pending_extrude(false)
	if undo_stack.is_empty():
		return
	redo_stack.append(volume.clone_state())
	volume.restore_state(undo_stack.pop_back())
	_rebuild_model_mesh()


func _redo() -> void:
	_cancel_pending_extrude(false)
	if redo_stack.is_empty():
		return
	undo_stack.append(volume.clone_state())
	volume.restore_state(redo_stack.pop_back())
	_rebuild_model_mesh()


func _reset_model() -> void:
	_cancel_pending_extrude(false)
	_push_undo()
	volume.reset_cube()
	redo_stack.clear()
	_rebuild_model_mesh()
	_clear_lasso()


func _clean_solid_model() -> void:
	_cancel_pending_extrude(false)
	_push_undo()
	var removed: int = volume.clean_solid_body(false)
	if removed == 0:
		undo_stack.pop_back()
	else:
		redo_stack.clear()
		_rebuild_model_mesh()


func _set_reference_visible(_enabled: bool) -> void:
	_update_reference_visibility()


func _open_reference_dialog() -> void:
	if camera_mode != CameraMode.ORTHOGRAPHIC:
		return
	reference_dialog.popup_centered(Vector2i(720, 520))


func _on_reference_drop_zone_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_reference_dialog()


func _on_files_dropped(files: PackedStringArray) -> void:
	if not files.is_empty():
		_load_reference_image(files[0])


func _load_reference_image(path: String) -> void:
	if camera_mode != CameraMode.ORTHOGRAPHIC:
		return
	var image := Image.new()
	if image.load(path) != OK:
		return
	var texture := ImageTexture.create_from_image(image)
	reference_overlay.set_reference_texture(texture)
	_save_reference_state_for_current_view()
	_update_reference_visibility()


func _save_reference_state_for_current_view() -> void:
	if camera_mode != CameraMode.ORTHOGRAPHIC:
		return
	reference_states[current_view] = {
		"texture": reference_overlay.reference_texture,
		"scale": reference_overlay.image_scale,
		"offset": reference_overlay.image_offset,
	}
	_update_reference_drop_zone()


func _apply_reference_state_for_current_view() -> void:
	if reference_states.has(current_view):
		var state: Dictionary = reference_states[current_view]
		reference_overlay.set_reference_state(state.get("texture", null), float(state.get("scale", 1.0)), state.get("offset", Vector2.ZERO))
		if reference_scale_slider:
			reference_scale_slider.set_value_no_signal(reference_overlay.image_scale)
	else:
		reference_overlay.clear_reference()
		if reference_scale_slider:
			reference_scale_slider.set_value_no_signal(1.0)
	_update_reference_drop_zone()


func _update_reference_visibility() -> void:
	if reference_overlay == null:
		return
	reference_overlay.viewport_margin_left = 180.0
	_apply_reference_state_for_current_view()
	var show_ref := camera_mode == CameraMode.ORTHOGRAPHIC and reference_toggle != null and reference_toggle.button_pressed and reference_overlay.reference_texture != null
	reference_overlay.set_active(show_ref)


func _update_reference_drop_zone() -> void:
	if reference_drop_label == null:
		return
	if camera_mode != CameraMode.ORTHOGRAPHIC:
		reference_drop_label.text = "Pick face angle"
	elif reference_overlay != null and reference_overlay.reference_texture != null:
		reference_drop_label.text = "Ref on\n%s" % current_view
	else:
		reference_drop_label.text = "Drop ref image\n%s" % current_view


func _clear_reference_for_current_view() -> void:
	if camera_mode == CameraMode.ORTHOGRAPHIC:
		reference_states.erase(current_view)
		reference_overlay.clear_reference()
	_update_reference_visibility()


func _set_reference_opacity(value: float) -> void:
	if reference_overlay:
		reference_overlay.set_opacity(value)


func _set_reference_scale(value: float) -> void:
	if reference_overlay:
		reference_overlay.set_image_scale(value)
		_save_reference_state_for_current_view()


func _export_glb_to_downloads() -> void:
	var file_name := "chizel_model.glb"
	var glb_bytes := _build_glb_buffer()
	if glb_bytes.is_empty():
		return
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(glb_bytes, file_name, "model/gltf-binary")
		return
	var downloads_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if downloads_dir == "":
		downloads_dir = OS.get_user_data_dir()
	var file := FileAccess.open(downloads_dir.path_join(file_name), FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(glb_bytes)
	file.close()


func _build_glb_buffer() -> PackedByteArray:
	var export_root := Node3D.new()
	export_root.name = "CHIZEL_Model"
	var export_mesh := MeshInstance3D.new()
	export_mesh.name = "Shell"
	export_mesh.mesh = model_mesh.mesh
	export_mesh.material_override = model_material
	export_root.add_child(export_mesh)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_scene(export_root, state) != OK:
		export_root.free()
		return PackedByteArray()
	var glb_bytes: PackedByteArray = document.generate_buffer(state)
	export_root.free()
	return glb_bytes


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text


func _lasso_mode_name() -> String:
	match lasso_mode:
		LassoMode.ADD:
			return "Add"
		LassoMode.EXTRUDE:
			return "Extrude"
		_:
			return "Subtract"
