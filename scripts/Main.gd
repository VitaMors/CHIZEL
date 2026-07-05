extends Node3D

const ModelVolumeScript := preload("res://scripts/ModelVolume.gd")
const LassoOverlayScript := preload("res://scripts/LassoOverlay.gd")
const ReferenceOverlayScript := preload("res://scripts/ReferenceOverlay.gd")

enum ToolMode { SELECT, CHISEL }
enum CameraMode { PERSPECTIVE, ORTHOGRAPHIC }
enum LassoMode { SUBTRACT, ADD }

var volume: ModelVolume
var model_mesh: MeshInstance3D
var grid_mesh: MeshInstance3D
var perspective_camera: Camera3D
var ortho_camera: Camera3D
var active_camera: Camera3D
var light: DirectionalLight3D
var lasso_overlay: LassoOverlay
var reference_overlay: ReferenceOverlay
var status_label: Label
var view_label: Label

var tool_mode: ToolMode = ToolMode.SELECT
var camera_mode: CameraMode = CameraMode.PERSPECTIVE
var current_view: String = "Perspective"
var lasso_points_screen: PackedVector2Array = PackedVector2Array()
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var mirror_x_enabled := false
var lasso_mode: LassoMode = LassoMode.SUBTRACT

var orbit_distance := 6.0
var orbit_yaw := deg_to_rad(35.0)
var orbit_pitch := deg_to_rad(-25.0)
var orbit_target := Vector3.ZERO
var is_orbiting := false
var is_panning := false

var grid_material: StandardMaterial3D
var model_material: StandardMaterial3D
var left_panel: PanelContainer
var mirror_toggle: CheckButton
var export_dialog: FileDialog
var reference_dialog: FileDialog
var reference_toggle: CheckButton
var reference_opacity_slider: HSlider
var reference_scale_slider: HSlider


func _ready() -> void:
	volume = ModelVolumeScript.new(Vector3i(32, 32, 32), 0.125)
	_setup_world()
	_setup_ui()
	_rebuild_model_mesh()
	_set_perspective_view()
	_set_status("Ready. Choose a blueprint view, then use Chisel to add or subtract material.")


func _setup_world() -> void:
	model_material = StandardMaterial3D.new()
	model_material.vertex_color_use_as_albedo = true
	model_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	model_material.roughness = 0.86

	model_mesh = MeshInstance3D.new()
	model_mesh.name = "Shell Model"
	model_mesh.material_override = model_material
	model_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(model_mesh)

	grid_material = StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color = Color(0.38, 0.44, 0.48, 0.22)
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	grid_mesh = MeshInstance3D.new()
	grid_mesh.name = "Modelling Grid"
	grid_mesh.material_override = grid_material
	add_child(grid_mesh)

	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 2.0
	add_child(light)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.075, 0.08, 1)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.58, 0.62, 1)
	environment.ambient_light_energy = 0.65
	world_environment.environment = environment
	add_child(world_environment)

	perspective_camera = Camera3D.new()
	perspective_camera.name = "Perspective Camera"
	perspective_camera.fov = 45
	add_child(perspective_camera)

	ortho_camera = Camera3D.new()
	ortho_camera.name = "Orthographic Camera"
	ortho_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	ortho_camera.size = 5.0
	add_child(ortho_camera)


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var root := Control.new()
	root.name = "Workspace UI"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)

	left_panel = PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(180, 0)
	left_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_right = 180
	left_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(left_panel)

	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_scroll)

	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 8)
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_box)

	var title := Label.new()
	title.text = "CHIZEL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	left_box.add_child(title)

	_add_section_label(left_box, "Tools")
	_add_button(left_box, "Select", Callable(self, "_set_tool_select"))
	_add_button(left_box, "Chisel", Callable(self, "_set_tool_chisel"))
	_add_button(left_box, "Subtract", Callable(self, "_set_lasso_subtract"))
	_add_button(left_box, "Add", Callable(self, "_set_lasso_add"))
	mirror_toggle = CheckButton.new()
	mirror_toggle.text = "Mirror X"
	mirror_toggle.custom_minimum_size = Vector2(150, 34)
	mirror_toggle.toggled.connect(Callable(self, "_set_mirror_x"))
	left_box.add_child(mirror_toggle)
	_add_button(left_box, "Reset Model", Callable(self, "_reset_model"))
	_add_button(left_box, "Clean Solid", Callable(self, "_clean_solid_model"))
	_add_button(left_box, "Undo", Callable(self, "_undo"))
	_add_button(left_box, "Redo", Callable(self, "_redo"))
	_add_button(left_box, "Export GLB", Callable(self, "_show_export_dialog"))

	_add_section_label(left_box, "Views")
	_add_button(left_box, "Perspective", Callable(self, "_set_perspective_view"))
	for view_name in ["Front", "Back", "Left", "Right", "Top", "Bottom"]:
		var callback := Callable(self, "_set_orthographic_view").bind(view_name)
		_add_button(left_box, view_name, callback)

	_add_section_label(left_box, "Reference")
	_add_button(left_box, "Import Ref", Callable(self, "_show_reference_dialog"))
	reference_toggle = CheckButton.new()
	reference_toggle.text = "Show Ref"
	reference_toggle.button_pressed = true
	reference_toggle.custom_minimum_size = Vector2(150, 34)
	reference_toggle.toggled.connect(Callable(self, "_set_reference_visible"))
	left_box.add_child(reference_toggle)

	var opacity_label := Label.new()
	opacity_label.text = "Opacity"
	opacity_label.modulate = Color(0.78, 0.82, 0.86, 1)
	left_box.add_child(opacity_label)

	reference_opacity_slider = HSlider.new()
	reference_opacity_slider.min_value = 0.05
	reference_opacity_slider.max_value = 1.0
	reference_opacity_slider.step = 0.05
	reference_opacity_slider.value = 0.35
	reference_opacity_slider.custom_minimum_size = Vector2(150, 28)
	reference_opacity_slider.value_changed.connect(Callable(self, "_set_reference_opacity"))
	left_box.add_child(reference_opacity_slider)

	var scale_label := Label.new()
	scale_label.text = "Scale"
	scale_label.modulate = Color(0.78, 0.82, 0.86, 1)
	left_box.add_child(scale_label)

	reference_scale_slider = HSlider.new()
	reference_scale_slider.min_value = 0.05
	reference_scale_slider.max_value = 8.0
	reference_scale_slider.step = 0.05
	reference_scale_slider.value = 1.0
	reference_scale_slider.custom_minimum_size = Vector2(150, 28)
	reference_scale_slider.value_changed.connect(Callable(self, "_set_reference_scale"))
	left_box.add_child(reference_scale_slider)

	var nudge_box := HBoxContainer.new()
	left_box.add_child(nudge_box)
	_add_small_button(nudge_box, "<", Callable(self, "_nudge_reference").bind(Vector2(-12, 0)))
	_add_small_button(nudge_box, "^", Callable(self, "_nudge_reference").bind(Vector2(0, -12)))
	_add_small_button(nudge_box, "v", Callable(self, "_nudge_reference").bind(Vector2(0, 12)))
	_add_small_button(nudge_box, ">", Callable(self, "_nudge_reference").bind(Vector2(12, 0)))
	_add_button(left_box, "Center Ref", Callable(self, "_center_reference"))
	_add_button(left_box, "Clear Ref", Callable(self, "_clear_reference"))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_child(spacer)

	view_label = Label.new()
	view_label.text = "Perspective"
	view_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_box.add_child(view_label)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = ""
	status_label.custom_minimum_size = Vector2(150, 80)
	left_box.add_child(status_label)

	reference_overlay = ReferenceOverlayScript.new()
	reference_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	reference_overlay.viewport_margin_left = 180.0
	root.add_child(reference_overlay)

	lasso_overlay = LassoOverlayScript.new()
	lasso_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(lasso_overlay)

	export_dialog = FileDialog.new()
	export_dialog.title = "Export GLB"
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.filters = PackedStringArray(["*.glb ; GLB model"])
	export_dialog.current_file = "chizel_model.glb"
	export_dialog.size = Vector2i(720, 480)
	export_dialog.file_selected.connect(Callable(self, "_export_glb"))
	canvas.add_child(export_dialog)

	reference_dialog = FileDialog.new()
	reference_dialog.title = "Import Reference Image"
	reference_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	reference_dialog.access = FileDialog.ACCESS_FILESYSTEM
	reference_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Image files"])
	reference_dialog.size = Vector2i(720, 480)
	reference_dialog.file_selected.connect(Callable(self, "_import_reference_image"))
	canvas.add_child(reference_dialog)


func _add_section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(0.78, 0.82, 0.86, 1)
	parent.add_child(label)


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 34)
	button.pressed.connect(callback)
	parent.add_child(button)


func _add_small_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(34, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)


func _input(event: InputEvent) -> void:
	if export_dialog != null and export_dialog.visible:
		return

	if reference_dialog != null and reference_dialog.visible:
		return

	if _is_pointer_over_toolbar(event):
		return

	if event is InputEventMouseMotion:
		lasso_overlay.set_mouse_position(event.position)
		if camera_mode == CameraMode.PERSPECTIVE:
			_handle_perspective_motion(event)

	if event is InputEventMouseButton:
		if tool_mode == ToolMode.CHISEL and camera_mode == CameraMode.ORTHOGRAPHIC:
			_handle_lasso_mouse(event)
		else:
			_handle_perspective_mouse(event)

	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _handle_key(event: InputEventKey) -> void:
	if event.ctrl_pressed and event.keycode == KEY_Z and event.shift_pressed:
		_redo()
	elif event.ctrl_pressed and event.keycode == KEY_Z:
		_undo()
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		_redo()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if tool_mode == ToolMode.CHISEL:
			_apply_lasso()
	elif event.keycode == KEY_ESCAPE:
		_clear_lasso()
	elif event.keycode == KEY_BACKSPACE:
		if lasso_points_screen.size() > 0:
			lasso_points_screen.remove_at(lasso_points_screen.size() - 1)
			lasso_overlay.set_points(lasso_points_screen)


func _handle_perspective_mouse(event: InputEventMouseButton) -> void:
	if camera_mode != CameraMode.PERSPECTIVE:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		is_orbiting = event.pressed
		is_panning = false
	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		is_panning = event.pressed
		is_orbiting = false
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		orbit_distance = max(1.8, orbit_distance * 0.9)
		_update_perspective_camera()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		orbit_distance = min(18.0, orbit_distance * 1.1)
		_update_perspective_camera()


func _handle_perspective_motion(event: InputEventMouseMotion) -> void:
	if is_orbiting:
		orbit_yaw -= event.relative.x * 0.008
		orbit_pitch = clamp(orbit_pitch - event.relative.y * 0.008, deg_to_rad(-82), deg_to_rad(82))
		_update_perspective_camera()
	elif is_panning:
		var right := perspective_camera.global_transform.basis.x
		var up := perspective_camera.global_transform.basis.y
		orbit_target += (-right * event.relative.x + up * event.relative.y) * 0.006 * orbit_distance
		_update_perspective_camera()


func _handle_lasso_mouse(event: InputEventMouseButton) -> void:
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if lasso_points_screen.size() >= 3 and event.position.distance_to(lasso_points_screen[0]) < 14.0:
		_apply_lasso()
		return
	lasso_points_screen.append(event.position)
	lasso_overlay.set_points(lasso_points_screen)
	_set_status("%s point added. Enter applies the lasso; Backspace removes a point; Escape cancels." % _lasso_mode_name())


func _set_tool_select() -> void:
	tool_mode = ToolMode.SELECT
	_clear_lasso()
	lasso_overlay.set_active(false)
	_set_status("Select mode. Use the perspective camera to inspect the model.")


func _set_tool_chisel() -> void:
	tool_mode = ToolMode.CHISEL
	_clear_lasso()
	if camera_mode != CameraMode.ORTHOGRAPHIC:
		_set_orthographic_view("Front")
	lasso_overlay.set_active(true)
	_set_status("Chisel %s mode. Click polygon points in the locked blueprint view." % _lasso_mode_name())


func _set_lasso_subtract() -> void:
	lasso_mode = LassoMode.SUBTRACT
	if tool_mode != ToolMode.CHISEL:
		_set_tool_chisel()
	else:
		_clear_lasso()
		_set_status("Subtract mode. The lasso will remove material.")


func _set_lasso_add() -> void:
	lasso_mode = LassoMode.ADD
	if tool_mode != ToolMode.CHISEL:
		_set_tool_chisel()
	else:
		_clear_lasso()
		_set_status("Add mode. The lasso will fill material through the model.")


func _set_mirror_x(enabled: bool) -> void:
	mirror_x_enabled = enabled
	_set_status("Mirror X is on. Chisel cuts will repeat across the model centre." if enabled else "Mirror X is off.")


func _show_export_dialog() -> void:
	export_dialog.current_file = "chizel_model.glb"
	export_dialog.popup_centered()


func _show_reference_dialog() -> void:
	reference_dialog.popup_centered()


func _import_reference_image(path: String) -> void:
	var image := Image.new()
	var load_error := image.load(path)
	if load_error != OK:
		_set_status("Reference image could not be loaded.")
		return

	var texture := ImageTexture.create_from_image(image)
	reference_overlay.set_reference_texture(texture)
	reference_toggle.button_pressed = true
	reference_scale_slider.value = reference_overlay.image_scale
	_update_reference_visibility()
	_set_status("Reference image imported. Use opacity, scale, and nudges to line it up.")


func _set_reference_visible(_enabled: bool) -> void:
	_update_reference_visibility()


func _set_reference_opacity(value: float) -> void:
	reference_overlay.set_opacity(value)


func _set_reference_scale(value: float) -> void:
	reference_overlay.set_image_scale(value)


func _nudge_reference(delta: Vector2) -> void:
	reference_overlay.nudge(delta)


func _center_reference() -> void:
	reference_overlay.center_image()


func _clear_reference() -> void:
	reference_overlay.clear_reference()
	_update_reference_visibility()
	_set_status("Reference image cleared.")


func _update_reference_visibility() -> void:
	if reference_overlay == null:
		return
	reference_overlay.viewport_margin_left = maxf(left_panel.size.x, 180.0)
	var should_show := camera_mode == CameraMode.ORTHOGRAPHIC and reference_toggle != null and reference_toggle.button_pressed
	reference_overlay.set_active(should_show)


func _set_perspective_view() -> void:
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


func _set_orthographic_view(view_name: String) -> void:
	camera_mode = CameraMode.ORTHOGRAPHIC
	current_view = view_name
	active_camera = ortho_camera
	perspective_camera.current = false
	ortho_camera.current = true
	grid_mesh.visible = true
	_clear_lasso()

	var camera_position := Vector3(0, 0, 6)
	var up := Vector3.UP
	match view_name:
		"Front":
			camera_position = Vector3(0, 0, 6)
		"Back":
			camera_position = Vector3(0, 0, -6)
		"Left":
			camera_position = Vector3(-6, 0, 0)
		"Right":
			camera_position = Vector3(6, 0, 0)
		"Top":
			camera_position = Vector3(0, 6, 0)
			up = Vector3.FORWARD
		"Bottom":
			camera_position = Vector3(0, -6, 0)
			up = Vector3.BACK

	ortho_camera.position = camera_position
	ortho_camera.look_at(Vector3.ZERO, up)
	volume.set_display_axes(ortho_camera.global_transform.basis.x.normalized(), ortho_camera.global_transform.basis.y.normalized(), current_view)
	_rebuild_model_mesh()
	_build_grid()
	if tool_mode == ToolMode.CHISEL:
		lasso_overlay.set_active(true)
	_update_view_label()
	_update_reference_visibility()


func _update_perspective_camera() -> void:
	var direction := Vector3(
		cos(orbit_pitch) * sin(orbit_yaw),
		sin(orbit_pitch),
		cos(orbit_pitch) * cos(orbit_yaw)
	)
	perspective_camera.position = orbit_target + direction * orbit_distance
	perspective_camera.look_at(orbit_target, Vector3.UP)


func _update_view_label() -> void:
	if view_label:
		view_label.text = current_view


func _reset_model() -> void:
	_push_undo()
	volume.reset_cube()
	redo_stack.clear()
	_rebuild_model_mesh()
	_clear_lasso()
	_set_status("Model reset to a fresh cube.")


func _clean_solid_model() -> void:
	_push_undo()
	var removed := volume.clean_solid_body()
	if removed == 0:
		undo_stack.pop_back()
		_set_status("Model is already one clean solid body.")
		return

	redo_stack.clear()
	_rebuild_model_mesh()
	_set_status("Cleaned %d loose/thin pieces from the model." % removed)


func _undo() -> void:
	if undo_stack.is_empty():
		_set_status("Nothing to undo.")
		return
	redo_stack.append(volume.clone_state())
	volume.restore_state(undo_stack.pop_back())
	_rebuild_model_mesh()
	_set_status("Undo complete.")


func _redo() -> void:
	if redo_stack.is_empty():
		_set_status("Nothing to redo.")
		return
	undo_stack.append(volume.clone_state())
	volume.restore_state(redo_stack.pop_back())
	_rebuild_model_mesh()
	_set_status("Redo complete.")


func _push_undo() -> void:
	undo_stack.append(volume.clone_state())
	if undo_stack.size() > 64:
		undo_stack.pop_front()


func _apply_lasso() -> void:
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

	_push_undo()
	var changed := 0
	if lasso_mode == LassoMode.ADD:
		changed = volume.add_through(polygon_model, axis_x, axis_y, mirror_x_enabled, current_view)
	else:
		changed = volume.carve_through(polygon_model, axis_x, axis_y, false, mirror_x_enabled, current_view)

	if changed == 0:
		undo_stack.pop_back()
		_set_status("The lasso did not change any material.")
	else:
		redo_stack.clear()
		_rebuild_model_mesh()
		var mirror_note := " with Mirror X" if mirror_x_enabled else ""
		var action := "added" if lasso_mode == LassoMode.ADD else "removed"
		var cut_note := " Latest cut: %s. Stored cuts: %d." % [volume.latest_cut_view_name(), volume.cut_count()] if lasso_mode == LassoMode.SUBTRACT else ""
		_set_status("Chisel %s %d pieces of material%s.%s" % [action, changed, mirror_note, cut_note])
	_clear_lasso()


func _screen_point_on_model_plane(screen_point: Vector2) -> Vector3:
	var plane := Plane(-ortho_camera.global_transform.basis.z.normalized(), 0.0)
	var origin := ortho_camera.project_ray_origin(screen_point)
	var direction := ortho_camera.project_ray_normal(screen_point)
	var hit = plane.intersects_ray(origin, direction)
	if hit == null:
		return Vector3.ZERO
	return hit


func _clear_lasso() -> void:
	lasso_points_screen.clear()
	if lasso_overlay:
		lasso_overlay.set_points(lasso_points_screen)


func _rebuild_model_mesh() -> void:
	model_mesh.mesh = volume.build_mesh()
	if model_mesh.mesh != null and model_mesh.mesh.get_surface_count() > 0:
		model_mesh.mesh.surface_set_material(0, model_material)


func _build_grid() -> void:
	var axis_x := ortho_camera.global_transform.basis.x.normalized()
	var axis_y := ortho_camera.global_transform.basis.y.normalized()
	var line_vertices := PackedVector3Array()
	var half_extent := 2.5
	var step := volume.voxel_size * 2.0
	var count: int = int(round((half_extent * 2.0) / step))

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


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text


func _lasso_mode_name() -> String:
	return "Add" if lasso_mode == LassoMode.ADD else "Subtract"


func _export_glb(path: String) -> void:
	if not path.to_lower().ends_with(".glb"):
		path += ".glb"

	var export_root := Node3D.new()
	export_root.name = "CHIZEL_Model"

	var export_mesh := MeshInstance3D.new()
	export_mesh.name = "Shell"
	export_mesh.mesh = model_mesh.mesh
	export_mesh.material_override = model_material
	export_root.add_child(export_mesh)

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(export_root, state)
	if append_error != OK:
		_set_status("GLB export failed while preparing the model.")
		export_root.free()
		return

	var write_error := document.write_to_filesystem(state, path)
	export_root.free()
	if write_error == OK:
		_set_status("Exported GLB: %s" % path)
	else:
		_set_status("GLB export failed. Check the save location and try again.")


func _is_pointer_over_toolbar(event: InputEvent) -> bool:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return event.position.x <= maxf(left_panel.size.x, 180.0)
	return false
