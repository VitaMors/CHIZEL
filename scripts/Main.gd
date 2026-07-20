extends Node3D

const ModelVolumeScript := preload("res://scripts/ModelVolume.gd")
const LassoOverlayScript := preload("res://scripts/LassoOverlay.gd")
const ReferenceOverlayScript := preload("res://scripts/ReferenceOverlay.gd")
const CubeFaceSelectorScript := preload("res://scripts/CubeFaceSelector.gd")

enum ToolMode { SELECT, CHISEL }
enum CameraMode { PERSPECTIVE, ORTHOGRAPHIC }
enum LassoMode { SUBTRACT, ADD, EXTRUDE }

const MAX_EXTRUDE_DISTANCE := 8.0
const EXTRUDE_VALUE_STEP := 0.05
const FACE_CAMERA_DISTANCE := 6.0

var volume
var model_mesh: MeshInstance3D
var grid_mesh: MeshInstance3D
var perspective_camera: Camera3D
var ortho_camera: Camera3D
var active_camera: Camera3D
var light: DirectionalLight3D
var view_light: DirectionalLight3D
var lasso_overlay
var reference_overlay
var status_label: Label
var view_label: Label
var face_selector

var tool_mode: ToolMode = ToolMode.SELECT
var camera_mode: CameraMode = CameraMode.PERSPECTIVE
var current_view: String = "Perspective"
var face_view_direction: Vector3 = Vector3(0, 0, 1)
var face_view_up: Vector3 = Vector3.UP
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
var reference_drop_zone: PanelContainer
var reference_drop_label: Label
var reference_opacity_slider: HSlider
var reference_scale_slider: HSlider
var extrude_panel: PanelContainer
var extrude_value_label: Label
var extrude_slider: HSlider
var has_pending_extrude := false
var pending_extrude_polygon_model: PackedVector2Array = PackedVector2Array()
var pending_extrude_axis_x: Vector3 = Vector3.RIGHT
var pending_extrude_axis_y: Vector3 = Vector3.UP
var pending_extrude_view_name: String = ""
var pending_extrude_original_state: Dictionary = {}
var pending_extrude_value := 0.0
var reference_states: Dictionary = {}


func _ready() -> void:
	volume = ModelVolumeScript.new(Vector3i(32, 32, 32), 0.125)
	_setup_world()
	_setup_ui()
	_setup_file_drop()
	_rebuild_model_mesh()
	_set_perspective_view()
	_set_status("Ready. Pick a face angle, then use Chisel to add, subtract, or extrude material.")


func _setup_world() -> void:
	model_material = StandardMaterial3D.new()
	model_material.vertex_color_use_as_albedo = true
	model_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	model_material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	model_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	model_material.roughness = 0.72

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
	light.light_energy = 1.25
	add_child(light)

	view_light = DirectionalLight3D.new()
	view_light.name = "Camera Fill Light"
	view_light.light_energy = 0.85
	view_light.shadow_enabled = false
	add_child(view_light)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.075, 0.08, 1)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.71, 0.74, 1)
	environment.ambient_light_energy = 0.9
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
	_add_button(left_box, "Extrude", Callable(self, "_set_lasso_extrude"))
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

	_add_section_label(left_box, "Cut Face")
	_add_button(left_box, "Perspective", Callable(self, "_set_perspective_view"))
	_setup_face_picker(left_box)
	_add_section_label(left_box, "Reference")
	_setup_reference_drop_zone(left_box)
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

	var view_badge := PanelContainer.new()
	view_badge.custom_minimum_size = Vector2(150, 72)
	var view_badge_style := StyleBoxFlat.new()
	view_badge_style.bg_color = Color(0.04, 0.05, 0.055, 0.95)
	view_badge_style.border_color = Color(0.78, 0.82, 0.86, 1.0)
	view_badge_style.set_border_width_all(1)
	view_badge_style.set_corner_radius_all(6)
	view_badge.add_theme_stylebox_override("panel", view_badge_style)
	left_box.add_child(view_badge)

	var view_badge_box := VBoxContainer.new()
	view_badge_box.add_theme_constant_override("separation", 0)
	view_badge.add_child(view_badge_box)

	var view_caption := Label.new()
	view_caption.text = "VIEW"
	view_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view_caption.add_theme_font_size_override("font_size", 10)
	view_caption.add_theme_color_override("font_color", Color(0.72, 0.78, 0.82, 1.0))
	view_badge_box.add_child(view_caption)

	view_label = Label.new()
	view_label.text = "PERSPECTIVE"
	view_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	view_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view_label.add_theme_font_size_override("font_size", 16)
	view_label.add_theme_color_override("font_color", Color(0.98, 0.98, 0.94, 1.0))
	view_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	view_label.add_theme_constant_override("outline_size", 4)
	view_badge_box.add_child(view_label)

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

	_setup_extrude_panel(root)



func _setup_face_picker(parent: Control) -> void:
	var picker_box := VBoxContainer.new()
	picker_box.custom_minimum_size = Vector2(150, 212)
	picker_box.add_theme_constant_override("separation", 4)
	parent.add_child(picker_box)

	var up_row := HBoxContainer.new()
	up_row.alignment = BoxContainer.ALIGNMENT_CENTER
	picker_box.add_child(up_row)
	_add_face_arrow_button(up_row, "^", Callable(self, "_nudge_face_view").bind(Vector2(0, 1)))

	var middle_row := HBoxContainer.new()
	middle_row.alignment = BoxContainer.ALIGNMENT_CENTER
	middle_row.add_theme_constant_override("separation", 6)
	picker_box.add_child(middle_row)
	_add_face_arrow_button(middle_row, "<", Callable(self, "_nudge_face_view").bind(Vector2(-1, 0)))
	face_selector = CubeFaceSelectorScript.new()
	face_selector.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	face_selector.custom_minimum_size = Vector2(112, 124)
	face_selector.face_pressed.connect(Callable(self, "_set_current_face_view"))
	middle_row.add_child(face_selector)
	_add_face_arrow_button(middle_row, ">", Callable(self, "_nudge_face_view").bind(Vector2(1, 0)))

	var down_row := HBoxContainer.new()
	down_row.alignment = BoxContainer.ALIGNMENT_CENTER
	picker_box.add_child(down_row)
	_add_face_arrow_button(down_row, "v", Callable(self, "_nudge_face_view").bind(Vector2(0, -1)))
	_update_face_selector()


func _setup_reference_drop_zone(parent: Control) -> void:
	reference_drop_zone = PanelContainer.new()
	reference_drop_zone.custom_minimum_size = Vector2(150, 70)
	reference_drop_zone.mouse_filter = Control.MOUSE_FILTER_PASS
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.10, 0.11, 0.82)
	panel_style.border_color = Color(0.46, 0.50, 0.54, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	reference_drop_zone.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(reference_drop_zone)

	reference_drop_label = Label.new()
	reference_drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reference_drop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reference_drop_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reference_drop_label.add_theme_font_size_override("font_size", 12)
	reference_drop_label.custom_minimum_size = Vector2(140, 60)
	reference_drop_zone.add_child(reference_drop_label)
	_update_reference_drop_zone()

func _setup_extrude_panel(parent: Control) -> void:
	extrude_panel = PanelContainer.new()
	extrude_panel.name = "Extrude Panel"
	extrude_panel.visible = false
	extrude_panel.custom_minimum_size = Vector2(320, 128)
	extrude_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	extrude_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	extrude_panel.offset_left = -350
	extrude_panel.offset_top = 18
	extrude_panel.offset_right = -24
	extrude_panel.offset_bottom = 150
	parent.add_child(extrude_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	extrude_panel.add_child(box)

	var title := Label.new()
	title.text = "Extrude"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)

	extrude_value_label = Label.new()
	extrude_value_label.text = "0.00"
	extrude_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extrude_value_label.add_theme_font_size_override("font_size", 18)
	box.add_child(extrude_value_label)

	extrude_slider = HSlider.new()
	extrude_slider.min_value = -MAX_EXTRUDE_DISTANCE
	extrude_slider.max_value = MAX_EXTRUDE_DISTANCE
	extrude_slider.step = EXTRUDE_VALUE_STEP
	extrude_slider.value = 0.0
	extrude_slider.custom_minimum_size = Vector2(280, 28)
	extrude_slider.value_changed.connect(Callable(self, "_preview_pending_extrude"))
	box.add_child(extrude_slider)

	var action_box := HBoxContainer.new()
	action_box.add_theme_constant_override("separation", 8)
	box.add_child(action_box)

	var apply_button := Button.new()
	apply_button.text = "Apply"
	apply_button.custom_minimum_size = Vector2(92, 30)
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(Callable(self, "_commit_pending_extrude"))
	action_box.add_child(apply_button)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(92, 30)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.pressed.connect(Callable(self, "_cancel_pending_extrude"))
	action_box.add_child(cancel_button)


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


func _add_face_arrow_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(34, 34)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(callback)
	parent.add_child(button)


func _input(event: InputEvent) -> void:
	if export_dialog != null and export_dialog.visible:
		return

	if reference_dialog != null and reference_dialog.visible:
		return

	if _is_pointer_over_toolbar(event):
		return

	if has_pending_extrude:
		if _is_pointer_over_extrude_panel(event):
			return
		if event is InputEventKey and event.pressed and not event.echo:
			_handle_key(event)
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
	if has_pending_extrude:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_commit_pending_extrude()
		elif event.keycode == KEY_ESCAPE:
			_cancel_pending_extrude()
		return

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
	if has_pending_extrude:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if lasso_points_screen.size() >= 3 and event.position.distance_to(lasso_points_screen[0]) < 14.0:
		_apply_lasso()
		return
	lasso_points_screen.append(event.position)
	lasso_overlay.set_points(lasso_points_screen)
	_set_status("%s point added. Enter applies the lasso; Backspace removes a point; Escape cancels." % _lasso_mode_name())


func _set_tool_select() -> void:
	_cancel_pending_extrude(false)
	tool_mode = ToolMode.SELECT
	_clear_lasso()
	lasso_overlay.set_active(false)
	_set_status("Select mode. Use the perspective camera to inspect the model.")


func _set_tool_chisel() -> void:
	_cancel_pending_extrude(false)
	tool_mode = ToolMode.CHISEL
	_clear_lasso()
	if camera_mode != CameraMode.ORTHOGRAPHIC:
		_set_cube_face_view(face_view_direction, face_view_up)
	lasso_overlay.set_active(true)
	_set_status("Chisel %s mode. Click polygon points on the selected face angle." % _lasso_mode_name())


func _set_lasso_subtract() -> void:
	_cancel_pending_extrude(false)
	lasso_mode = LassoMode.SUBTRACT
	if tool_mode != ToolMode.CHISEL:
		_set_tool_chisel()
	else:
		_clear_lasso()
		_set_status("Subtract mode. The lasso will remove material.")


func _set_lasso_add() -> void:
	_cancel_pending_extrude(false)
	lasso_mode = LassoMode.ADD
	if tool_mode != ToolMode.CHISEL:
		_set_tool_chisel()
	else:
		_clear_lasso()
		_set_status("Add mode. The lasso will fill material through the model.")


func _set_lasso_extrude() -> void:
	_cancel_pending_extrude(false)
	lasso_mode = LassoMode.EXTRUDE
	if tool_mode != ToolMode.CHISEL:
		_set_tool_chisel()
	else:
		_clear_lasso()
		_set_status("Extrude mode. Draw a lasso, then drag the extrusion value left or right.")


func _set_mirror_x(enabled: bool) -> void:
	mirror_x_enabled = enabled
	_set_status("Mirror X is on. Chisel cuts will repeat across the model centre." if enabled else "Mirror X is off.")


func _show_export_dialog() -> void:
	_export_glb_to_downloads()


func _show_reference_dialog() -> void:
	_set_status("Pick a face angle, then drop a PNG/JPG/WebP/BMP into the reference box.")


func _setup_file_drop() -> void:
	var window := get_window()
	if window != null and window.has_signal("files_dropped"):
		window.connect("files_dropped", Callable(self, "_handle_files_dropped"))


func _handle_files_dropped(files: PackedStringArray) -> void:
	if files.is_empty():
		return
	for file_path in files:
		if _is_supported_reference_file(file_path):
			_import_reference_image(file_path)
			return
	_set_status("Drop a PNG, JPG, WebP, or BMP reference image.")


func _is_supported_reference_file(path: String) -> bool:
	var lower_path := path.to_lower()
	return lower_path.ends_with(".png") or lower_path.ends_with(".jpg") or lower_path.ends_with(".jpeg") or lower_path.ends_with(".webp") or lower_path.ends_with(".bmp")


func _import_reference_image(path: String) -> void:
	var key := _current_reference_key()
	if key == "":
		_set_status("Pick a face angle before dropping a reference image.")
		return

	var image := Image.new()
	var load_error := image.load(path)
	if load_error != OK:
		_set_status("Reference image could not be loaded.")
		return

	var texture := ImageTexture.create_from_image(image)
	reference_overlay.set_reference_texture(texture)
	reference_states[key] = {
		"texture": texture,
		"scale": reference_overlay.image_scale,
		"offset": reference_overlay.image_offset,
	}
	if reference_toggle != null:
		reference_toggle.button_pressed = true
	if reference_scale_slider != null:
		reference_scale_slider.set_value_no_signal(reference_overlay.image_scale)
	_update_reference_visibility()
	_set_status("Reference image set for %s." % key)


func _current_reference_key() -> String:
	if camera_mode != CameraMode.ORTHOGRAPHIC:
		return ""
	return current_view


func _apply_reference_state_for_current_view() -> void:
	if reference_overlay == null:
		return
	var key := _current_reference_key()
	if key == "" or not reference_states.has(key):
		reference_overlay.set_reference_state(null, 1.0, Vector2.ZERO)
		if reference_scale_slider != null:
			reference_scale_slider.set_value_no_signal(1.0)
		return

	var state: Dictionary = reference_states[key] as Dictionary
	var texture: Texture2D = state.get("texture", null) as Texture2D
	var scale_value: float = float(state.get("scale", 1.0))
	var offset_value: Vector2 = state.get("offset", Vector2.ZERO) as Vector2
	reference_overlay.set_reference_state(texture, scale_value, offset_value)
	if reference_scale_slider != null:
		reference_scale_slider.set_value_no_signal(reference_overlay.image_scale)


func _save_current_reference_state() -> void:
	if reference_overlay == null or reference_overlay.reference_texture == null:
		return
	var key := _current_reference_key()
	if key == "":
		return
	reference_states[key] = {
		"texture": reference_overlay.reference_texture,
		"scale": reference_overlay.image_scale,
		"offset": reference_overlay.image_offset,
	}
	_update_reference_drop_zone()


func _set_reference_visible(_enabled: bool) -> void:
	_update_reference_visibility()


func _set_reference_opacity(value: float) -> void:
	reference_overlay.set_opacity(value)


func _set_reference_scale(value: float) -> void:
	if reference_overlay.reference_texture == null:
		return
	reference_overlay.set_image_scale(value)
	_save_current_reference_state()


func _nudge_reference(delta: Vector2) -> void:
	if reference_overlay.reference_texture == null:
		_set_status("No reference image on %s." % current_view)
		return
	reference_overlay.nudge(delta)
	_save_current_reference_state()


func _center_reference() -> void:
	if reference_overlay.reference_texture == null:
		return
	reference_overlay.center_image()
	_save_current_reference_state()


func _clear_reference() -> void:
	var key := _current_reference_key()
	if key != "" and reference_states.has(key):
		reference_states.erase(key)
	reference_overlay.clear_reference()
	_update_reference_visibility()
	_set_status("Reference image cleared for %s." % key if key != "" else "Reference image cleared.")


func _update_reference_drop_zone() -> void:
	if reference_drop_label == null:
		return
	var key := _current_reference_key()
	if key == "":
		reference_drop_label.text = "Ref Image\nPick Face"
		reference_drop_label.modulate = Color(0.62, 0.66, 0.70, 1.0)
		return
	if reference_states.has(key):
		reference_drop_label.text = "Ref Set\n%s" % key
		reference_drop_label.modulate = Color(0.86, 0.88, 0.82, 1.0)
	else:
		reference_drop_label.text = "Drop Ref\n%s" % key
		reference_drop_label.modulate = Color(0.72, 0.76, 0.80, 1.0)


func _update_reference_visibility() -> void:
	if reference_overlay == null:
		return
	reference_overlay.viewport_margin_left = maxf(left_panel.size.x, 180.0)
	_apply_reference_state_for_current_view()
	var should_show := camera_mode == CameraMode.ORTHOGRAPHIC and reference_toggle != null and reference_toggle.button_pressed and reference_overlay.reference_texture != null
	reference_overlay.set_active(should_show)
	_update_reference_drop_zone()

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
		next_up = up
	elif delta.x < 0.0:
		next_direction = (direction - axis_x).normalized()
		next_up = up
	elif delta.y > 0.0:
		next_direction = (direction + axis_y).normalized()
		next_up = (axis_y - direction).normalized()
	elif delta.y < 0.0:
		next_direction = (direction - axis_y).normalized()
		next_up = (axis_y + direction).normalized()

	_set_cube_face_view(next_direction, next_up)


func _set_cube_face_view(view_direction: Vector3, up_hint: Vector3) -> void:
	var direction: Vector3 = _normalized_view_direction(view_direction)
	var up: Vector3 = _orthogonalized_up(direction, up_hint)
	_set_orthographic_direction(_face_name_for_direction(direction), direction, up)
	_set_status("%s angle selected for lasso cuts." % current_view)


func _set_orthographic_view(view_name: String) -> void:
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
	_set_cube_face_view(camera_position.normalized(), up)


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
	if names.is_empty():
		names.append("Front")
	return "%s Angle" % " ".join(names)

func _normalized_view_direction(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.0001:
		return Vector3(0, 0, 1)
	return direction.normalized()


func _orthogonalized_up(direction: Vector3, up_hint: Vector3) -> Vector3:
	var normalized_direction := _normalized_view_direction(direction)
	var up := up_hint - normalized_direction * up_hint.dot(normalized_direction)
	if up.length_squared() < 0.0001:
		up = Vector3.FORWARD if absf(normalized_direction.dot(Vector3.UP)) > 0.9 else Vector3.UP
		up -= normalized_direction * up.dot(normalized_direction)
	return up.normalized()

func _update_perspective_camera() -> void:
	var direction := Vector3(
		cos(orbit_pitch) * sin(orbit_yaw),
		sin(orbit_pitch),
		cos(orbit_pitch) * cos(orbit_yaw)
	)
	perspective_camera.position = orbit_target + direction * orbit_distance
	perspective_camera.look_at(orbit_target, Vector3.UP)
	_update_view_light()


func _update_view_light() -> void:
	if view_light == null or active_camera == null:
		return
	view_light.global_transform = active_camera.global_transform


func _update_view_label() -> void:
	if view_label:
		view_label.text = current_view.to_upper()
	_update_face_selector()


func _update_face_selector() -> void:
	if face_selector:
		face_selector.set_face(_face_name_for_direction(face_view_direction), camera_mode == CameraMode.ORTHOGRAPHIC)

func _reset_model() -> void:
	_cancel_pending_extrude(false)
	_push_undo()
	volume.reset_cube()
	redo_stack.clear()
	_rebuild_model_mesh()
	_clear_lasso()
	_set_status("Model reset to a fresh cube.")


func _clean_solid_model() -> void:
	_cancel_pending_extrude(false)
	_push_undo()
	var removed: int = volume.clean_solid_body(false)
	if removed == 0:
		undo_stack.pop_back()
		_set_status("Model is already one clean solid body.")
		return

	redo_stack.clear()
	_rebuild_model_mesh()
	_set_status("Cleaned %d loose/thin pieces from the model." % removed)


func _undo() -> void:
	_cancel_pending_extrude(false)
	if undo_stack.is_empty():
		_set_status("Nothing to undo.")
		return
	redo_stack.append(volume.clone_state())
	volume.restore_state(undo_stack.pop_back())
	_rebuild_model_mesh()
	_set_status("Undo complete.")


func _redo() -> void:
	_cancel_pending_extrude(false)
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
	_set_status("Extrude value is 0.00. Drag left for an inset or right for an outward pull; Enter applies.")


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
		_set_status("Extrude skipped because the value stayed at 0.00.")
		return

	_push_undo()
	var changed: int = volume.extrude_surface(polygon_model, axis_x, axis_y, final_value, mirror_x_enabled, view_name)
	if changed == 0:
		undo_stack.pop_back()
		_rebuild_model_mesh()
		_set_status("The extrusion did not change the model.")
		return

	redo_stack.clear()
	_rebuild_model_mesh()
	var mirror_note := " with Mirror X" if mirror_x_enabled else ""
	_set_status("Extruded selection by %.2f%s." % [final_value, mirror_note])


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
	pending_extrude_axis_x = Vector3.RIGHT
	pending_extrude_axis_y = Vector3.UP
	pending_extrude_view_name = ""
	pending_extrude_original_state = {}
	pending_extrude_value = 0.0
	if extrude_panel:
		extrude_panel.visible = false


func _update_extrude_value_label() -> void:
	if extrude_value_label == null:
		return
	var prefix := "+" if pending_extrude_value > 0.0 else ""
	extrude_value_label.text = "%s%.2f" % [prefix, pending_extrude_value]


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
	var step: float = volume.voxel_size * 2.0
	var count: int = int(round((half_extent * 2.0) / step))

	for i in range(count + 1):
		var value: float = -half_extent + i * step
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
	match lasso_mode:
		LassoMode.ADD:
			return "Add"
		LassoMode.EXTRUDE:
			return "Extrude"
		_:
			return "Subtract"


func _export_glb_to_downloads() -> void:
	var file_name := "chizel_model.glb"
	var glb_bytes := _build_glb_buffer()
	if glb_bytes.is_empty():
		return

	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(glb_bytes, file_name, "model/gltf-binary")
		_set_status("Downloading GLB: %s" % file_name)
		return

	var downloads_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if downloads_dir == "":
		downloads_dir = OS.get_user_data_dir()
	var target_path := downloads_dir.path_join(file_name)
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		_set_status("GLB export failed. Could not write to Downloads.")
		return
	file.store_buffer(glb_bytes)
	file.close()
	_set_status("Exported GLB to Downloads: %s" % target_path)


func _export_glb(path: String) -> void:
	if not path.to_lower().ends_with(".glb"):
		path += ".glb"
	var glb_bytes := _build_glb_buffer()
	if glb_bytes.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("GLB export failed. Check the save location and try again.")
		return
	file.store_buffer(glb_bytes)
	file.close()
	_set_status("Exported GLB: %s" % path)


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
	var append_error := document.append_from_scene(export_root, state)
	if append_error != OK:
		_set_status("GLB export failed while preparing the model.")
		export_root.free()
		return PackedByteArray()

	var glb_bytes: PackedByteArray = document.generate_buffer(state)
	export_root.free()
	if glb_bytes.is_empty():
		_set_status("GLB export failed while generating the download.")
	return glb_bytes

func _is_pointer_over_toolbar(event: InputEvent) -> bool:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return event.position.x <= maxf(left_panel.size.x, 180.0)
	return false


func _is_pointer_over_extrude_panel(event: InputEvent) -> bool:
	if extrude_panel == null or not extrude_panel.visible:
		return false
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return extrude_panel.get_global_rect().has_point(event.position)
	return false
