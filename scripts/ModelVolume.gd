class_name ModelVolume
extends RefCounted

const EMPTY := -1

var grid_size: Vector3i = Vector3i(32, 32, 32)
var voxel_size: float = 0.125
var voxels: PackedInt32Array = PackedInt32Array()
var cut_surfaces: Array = []
var extrude_surfaces: Array = []
var has_display_axes: bool = false
var display_axis_x: Vector3 = Vector3.RIGHT
var display_axis_y: Vector3 = Vector3.UP
var display_depth_axis: Vector3 = Vector3.FORWARD
var display_view_name: String = ""
var cut_face_hiding_enabled: bool = true
var cut_face_patch_surfaces: Array = []
var materials: Array[Color] = [
	Color(0.62, 0.63, 0.62, 1.0),
	Color(0.18, 0.19, 0.21, 1.0),
	Color(0.86, 0.86, 0.82, 1.0),
	Color(0.78, 0.52, 0.40, 1.0),
	Color(0.18, 0.12, 0.09, 1.0),
	Color(0.24, 0.38, 0.72, 1.0),
	Color(0.55, 0.58, 0.62, 1.0),
	Color(0.43, 0.27, 0.13, 1.0),
	Color(0.24, 0.55, 0.26, 1.0),
	Color(0.15, 0.45, 0.7, 1.0),
]


func _init(next_grid_size: Vector3i = Vector3i(32, 32, 32), next_voxel_size: float = 0.125) -> void:
	grid_size = next_grid_size
	voxel_size = next_voxel_size
	reset_cube()


func reset_cube() -> void:
	voxels.resize(grid_size.x * grid_size.y * grid_size.z)
	voxels.fill(0)
	cut_surfaces.clear()
	extrude_surfaces.clear()


func clone_voxels() -> PackedInt32Array:
	return voxels.duplicate()


func restore_voxels(snapshot: PackedInt32Array) -> void:
	voxels = snapshot.duplicate()
	cut_surfaces.clear()
	extrude_surfaces.clear()


func clone_state() -> Dictionary:
	return {
		"voxels": voxels.duplicate(),
		"cut_surfaces": cut_surfaces.duplicate(true),
		"extrude_surfaces": extrude_surfaces.duplicate(true),
	}


func restore_state(snapshot: Dictionary) -> void:
	voxels = snapshot.get("voxels", PackedInt32Array()).duplicate()
	cut_surfaces = snapshot.get("cut_surfaces", []).duplicate(true)
	extrude_surfaces = snapshot.get("extrude_surfaces", []).duplicate(true)


func index(x: int, y: int, z: int) -> int:
	return x + grid_size.x * (y + grid_size.y * z)


func is_in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < grid_size.x and y < grid_size.y and z < grid_size.z


func is_solid(x: int, y: int, z: int) -> bool:
	return is_in_bounds(x, y, z) and voxels[index(x, y, z)] != EMPTY


func is_full_cube() -> bool:
	for material_index in voxels:
		if material_index == EMPTY:
			return false
	return true


func voxel_center(x: int, y: int, z: int) -> Vector3:
	var half := Vector3(grid_size.x, grid_size.y, grid_size.z) * voxel_size * 0.5
	return Vector3(x + 0.5, y + 0.5, z + 0.5) * voxel_size - half


func carve_through(polygon_points: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, invert_cut: bool = false, mirror_x: bool = false, view_name: String = "") -> int:
	return apply_lasso_operation(polygon_points, axis_x, axis_y, false, invert_cut, mirror_x, view_name)


func add_through(polygon_points: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, mirror_x: bool = false, view_name: String = "") -> int:
	return apply_lasso_operation(polygon_points, axis_x, axis_y, true, false, mirror_x, view_name)


func extrude_surface(polygon_points: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, amount: float, mirror_x: bool = false, view_name: String = "") -> int:
	if polygon_points.size() < 3 or absf(amount) <= 0.0001:
		return 0

	axis_x = axis_x.normalized()
	axis_y = axis_y.normalized()
	var depth_axis := axis_x.cross(axis_y).normalized()
	var operation_view_name: String = view_name if view_name != "" else display_view_name
	var changed := _store_clipped_extrude_surfaces(polygon_points, axis_x, axis_y, depth_axis, amount, operation_view_name)
	if mirror_x:
		var mirrored_polygon := _mirrored_view_polygon(polygon_points)
		changed += _store_clipped_extrude_surfaces(mirrored_polygon, axis_x, axis_y, depth_axis, amount, operation_view_name)
	return changed


func _store_clipped_extrude_surfaces(polygon_points: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3, amount: float, view_name: String = "") -> int:
	var clipped_shapes: Array = _clip_polygon_to_solid_projection(polygon_points, axis_x, axis_y, depth_axis)
	if clipped_shapes.is_empty():
		return 0

	var total_area := 0.0
	for shape_value in clipped_shapes:
		var shape: PackedVector2Array = shape_value as PackedVector2Array
		if shape.size() < 3:
			continue
		var area: float = absf(_polygon_area(shape))
		if area <= 0.0001:
			continue
		total_area += area
		var surface_depth := _surface_depth_for_extrusion_shape(shape, axis_x, axis_y, depth_axis)
		_store_extrude_surface(shape, axis_x, axis_y, depth_axis, surface_depth, amount, view_name)

	if total_area <= 0.0001:
		return 0

	var area_steps: int = maxi(1, ceili(total_area / (voxel_size * voxel_size)))
	var depth_steps: int = maxi(1, ceili(absf(amount) / voxel_size))
	return area_steps * depth_steps


func _surface_depth_for_extrusion_shape(polygon: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3) -> float:
	var surface_depth := _projected_bound(depth_axis, false)
	for surface_value in extrude_surfaces:
		var surface: Dictionary = surface_value as Dictionary
		if not _surface_matches_axes_signed(surface, axis_x, axis_y, depth_axis):
			continue
		if float(surface.get("amount", 0.0)) <= 0.0001:
			continue
		var existing_polygon: PackedVector2Array = surface["polygon"] as PackedVector2Array
		if not _polygons_overlap(polygon, existing_polygon):
			continue
		surface_depth = maxf(surface_depth, _surface_extrusion_depth(surface))
	return surface_depth


func _surface_extrusion_depth(surface: Dictionary) -> float:
	if surface.has("extruded_depth"):
		return float(surface["extruded_depth"])
	var surface_depth: float = float(surface.get("surface_depth", surface.get("depth_max", 0.0)))
	return surface_depth + float(surface.get("amount", 0.0))


func _polygons_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var intersections: Array = Geometry2D.intersect_polygons(a, b)
	for intersection in intersections:
		var points: PackedVector2Array = intersection as PackedVector2Array
		if points.size() >= 3 and absf(_polygon_area(points)) > 0.0001:
			return true
	return false


func _mirrored_view_polygon(polygon_points: PackedVector2Array) -> PackedVector2Array:
	var mirrored_polygon := PackedVector2Array()
	for point in polygon_points:
		mirrored_polygon.append(Vector2(-point.x, point.y))
	return mirrored_polygon


func _clip_polygon_to_solid_projection(polygon_points: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3) -> Array:
	var solid_polygons: Array = _solid_projection_polygons_for_axes(axis_x, axis_y, depth_axis)
	var clipped_shapes: Array = []
	for solid_polygon_value in solid_polygons:
		var solid_polygon: PackedVector2Array = solid_polygon_value as PackedVector2Array
		var intersections: Array = Geometry2D.intersect_polygons(solid_polygon, polygon_points)
		for intersection in intersections:
			var points: PackedVector2Array = intersection as PackedVector2Array
			if points.size() >= 3 and absf(_polygon_area(points)) > 0.0001:
				clipped_shapes.append(points)
	return clipped_shapes


func _solid_projection_polygons_for_axes(axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3) -> Array:
	var polygons: Array = [_projected_cube_rect(axis_x, axis_y)]
	for surface_value in cut_surfaces:
		var surface: Dictionary = surface_value as Dictionary
		var cutter := _surface_polygon_for_axes(surface, axis_x, axis_y, depth_axis)
		if cutter.size() < 3:
			continue
		var next_polygons: Array = []
		for polygon_value in polygons:
			var source_polygon: PackedVector2Array = polygon_value as PackedVector2Array
			var clipped: Array = Geometry2D.clip_polygons(source_polygon, cutter)
			for clipped_polygon in clipped:
				var clipped_points: PackedVector2Array = clipped_polygon as PackedVector2Array
				if clipped_points.size() >= 3 and absf(_polygon_area(clipped_points)) > 0.0001:
					next_polygons.append(clipped_points)
		polygons = next_polygons
	return polygons


func _surface_polygon_for_axes(surface: Dictionary, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3) -> PackedVector2Array:
	if not _surface_matches_axes(surface, axis_x, axis_y, depth_axis):
		return PackedVector2Array()

	var stored_polygon: PackedVector2Array = surface["polygon"] as PackedVector2Array
	if _surface_matches_axes_signed(surface, axis_x, axis_y, depth_axis):
		return stored_polygon.duplicate()

	var stored_axis_x: Vector3 = surface["axis_x"] as Vector3
	var stored_axis_y: Vector3 = surface["axis_y"] as Vector3
	var transformed := PackedVector2Array()
	for point in stored_polygon:
		var world_point: Vector3 = stored_axis_x * point.x + stored_axis_y * point.y
		transformed.append(Vector2(world_point.dot(axis_x), world_point.dot(axis_y)))
	return transformed


func cut_count() -> int:
	return cut_surfaces.size()


func latest_cut_view_name() -> String:
	if cut_surfaces.is_empty():
		return ""
	var surface: Dictionary = cut_surfaces[cut_surfaces.size() - 1] as Dictionary
	return str(surface.get("view_name", ""))


func set_display_axes(axis_x: Vector3, axis_y: Vector3, view_name: String = "") -> void:
	display_axis_x = axis_x.normalized()
	display_axis_y = axis_y.normalized()
	display_depth_axis = display_axis_x.cross(display_axis_y).normalized()
	display_view_name = view_name
	has_display_axes = true


func clear_display_axes() -> void:
	has_display_axes = false
	display_view_name = ""


func apply_lasso_operation(polygon_points: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, add_material: bool = false, invert_cut: bool = false, mirror_x: bool = false, view_name: String = "") -> int:
	if polygon_points.size() < 3:
		return 0

	axis_x = axis_x.normalized()
	axis_y = axis_y.normalized()
	var depth_axis := axis_x.cross(axis_y).normalized()
	var cut_view_name: String = view_name if view_name != "" else display_view_name
	var changed := _apply_lasso_projection(polygon_points, axis_x, axis_y, add_material, invert_cut)
	var mirrored_changed := 0
	var mirrored_polygon := PackedVector2Array()
	var mirrored_axis_x := Vector3.ZERO
	var mirrored_axis_y := Vector3.ZERO
	var mirrored_depth_axis := Vector3.ZERO

	if mirror_x:
		mirrored_polygon = _mirrored_view_polygon(polygon_points)
		mirrored_axis_x = axis_x
		mirrored_axis_y = axis_y
		mirrored_depth_axis = depth_axis
		mirrored_changed = _apply_lasso_projection(mirrored_polygon, mirrored_axis_x, mirrored_axis_y, add_material, invert_cut)
		changed += mirrored_changed

	if add_material:
		if changed > 0:
			cut_surfaces.clear()
	elif not invert_cut:
		if changed <= 0:
			return 0
		if changed - mirrored_changed > 0:
			_store_cut_surface(polygon_points, axis_x, axis_y, depth_axis, cut_view_name)
		if mirror_x and mirrored_changed > 0:
			_store_cut_surface(mirrored_polygon, mirrored_axis_x, mirrored_axis_y, mirrored_depth_axis, cut_view_name)
	elif changed > 0:
		changed += clean_solid_body(false)

	return changed


func _apply_lasso_projection(polygon_points: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, add_material: bool, invert_cut: bool) -> int:
	var changed := 0
	for z in range(grid_size.z):
		for y in range(grid_size.y):
			for x in range(grid_size.x):
				var voxel_index := index(x, y, z)
				var center := voxel_center(x, y, z)
				var point := Vector2(center.dot(axis_x), center.dot(axis_y))
				var inside := Geometry2D.is_point_in_polygon(point, polygon_points)
				if inside != invert_cut:
					if add_material:
						if voxels[voxel_index] == EMPTY:
							voxels[voxel_index] = 0
							changed += 1
					elif voxels[voxel_index] != EMPTY:
						voxels[voxel_index] = EMPTY
						changed += 1
	return changed

func clean_solid_body(clear_cut_surfaces_on_change: bool = true) -> int:
	var removed := _keep_largest_connected_component()
	removed += _remove_thin_shards()
	if removed > 0 and clear_cut_surfaces_on_change:
		cut_surfaces.clear()
	return removed


func _keep_largest_connected_component() -> int:
	var visited := PackedByteArray()
	visited.resize(voxels.size())
	visited.fill(0)

	var largest_component := PackedInt32Array()
	var largest_size := 0

	for voxel_index in range(voxels.size()):
		if visited[voxel_index] == 1 or voxels[voxel_index] == EMPTY:
			continue

		var component := _flood_component(voxel_index, visited)
		if component.size() > largest_size:
			largest_size = component.size()
			largest_component = component

	if largest_size == 0:
		return 0

	var keep := PackedByteArray()
	keep.resize(voxels.size())
	keep.fill(0)
	for voxel_index in largest_component:
		keep[voxel_index] = 1

	var removed := 0
	for voxel_index in range(voxels.size()):
		if voxels[voxel_index] != EMPTY and keep[voxel_index] == 0:
			voxels[voxel_index] = EMPTY
			removed += 1

	return removed


func _flood_component(start_index: int, visited: PackedByteArray) -> PackedInt32Array:
	var component := PackedInt32Array()
	var queue := PackedInt32Array()
	var cursor := 0

	queue.append(start_index)
	visited[start_index] = 1

	while cursor < queue.size():
		var voxel_index := queue[cursor]
		cursor += 1
		component.append(voxel_index)

		var cell := _index_to_cell(voxel_index)
		for direction in _neighbor_directions():
			var neighbor := cell + direction
			if not is_in_bounds(neighbor.x, neighbor.y, neighbor.z):
				continue

			var neighbor_index := index(neighbor.x, neighbor.y, neighbor.z)
			if visited[neighbor_index] == 1 or voxels[neighbor_index] == EMPTY:
				continue

			visited[neighbor_index] = 1
			queue.append(neighbor_index)

	return component


func _remove_thin_shards() -> int:
	var total_removed := 0
	var max_passes := 8

	for _pass_index in range(max_passes):
		var to_remove := PackedInt32Array()

		for voxel_index in range(voxels.size()):
			if voxels[voxel_index] == EMPTY:
				continue

			var cell := _index_to_cell(voxel_index)
			var face_neighbors := _solid_neighbor_count(cell)
			if face_neighbors <= 1:
				to_remove.append(voxel_index)
				continue

			if face_neighbors <= 2 and _empty_opposite_axis_count(cell) >= 2:
				to_remove.append(voxel_index)

		if to_remove.is_empty():
			break

		for voxel_index in to_remove:
			if voxels[voxel_index] != EMPTY:
				voxels[voxel_index] = EMPTY
				total_removed += 1

	return total_removed


func _solid_neighbor_count(cell: Vector3i) -> int:
	var count := 0
	for direction in _neighbor_directions():
		var neighbor := cell + direction
		if is_solid(neighbor.x, neighbor.y, neighbor.z):
			count += 1
	return count


func _empty_opposite_axis_count(cell: Vector3i) -> int:
	var count := 0
	if not is_solid(cell.x - 1, cell.y, cell.z) and not is_solid(cell.x + 1, cell.y, cell.z):
		count += 1
	if not is_solid(cell.x, cell.y - 1, cell.z) and not is_solid(cell.x, cell.y + 1, cell.z):
		count += 1
	if not is_solid(cell.x, cell.y, cell.z - 1) and not is_solid(cell.x, cell.y, cell.z + 1):
		count += 1
	return count


func _index_to_cell(voxel_index: int) -> Vector3i:
	var z: int = floori(float(voxel_index) / float(grid_size.x * grid_size.y))
	var remainder := voxel_index - z * grid_size.x * grid_size.y
	var y: int = floori(float(remainder) / float(grid_size.x))
	var x := remainder - y * grid_size.x
	return Vector3i(x, y, z)


func _neighbor_directions() -> Array[Vector3i]:
	return [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0),
		Vector3i(0, -1, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
	]


func build_mesh() -> ArrayMesh:
	if extrude_surfaces.is_empty():
		return _build_cut_mesh()

	if _surface_operations_share_projection():
		var exact_surface_mesh: ArrayMesh = build_exact_surface_mesh(cut_surfaces, extrude_surfaces)
		if exact_surface_mesh.get_surface_count() > 0:
			return exact_surface_mesh

	var base_mesh: ArrayMesh = _build_cut_mesh()
	var overlay_mesh: ArrayMesh = build_extrusion_overlay_mesh(extrude_surfaces)
	return _combine_meshes([base_mesh, overlay_mesh])


func _build_cut_mesh() -> ArrayMesh:
	if cut_surfaces.is_empty():
		return build_base_poly_mesh() if is_full_cube() else build_grid_shell_mesh(false)

	if _cut_surfaces_share_projection():
		return build_exact_cut_mesh(cut_surfaces)

	if _surfaces_include_non_axis_aligned(cut_surfaces):
		return build_low_poly_mesh()

	return build_grid_shell_mesh(false)


func build_base_poly_mesh() -> ArrayMesh:
	return _mesh_from_polyhedron_faces(_cube_polyhedron_faces())


func _surfaces_can_use_exact_projection(active_surfaces: Array) -> bool:
	if active_surfaces.is_empty():
		return false

	var first_surface: Dictionary = active_surfaces[0] as Dictionary
	var first_axis_x: Vector3 = first_surface["axis_x"] as Vector3
	var first_axis_y: Vector3 = first_surface["axis_y"] as Vector3
	var first_depth_axis: Vector3 = first_surface["depth_axis"] as Vector3
	for surface_value in active_surfaces:
		var surface: Dictionary = surface_value as Dictionary
		if not _surface_matches_axes_signed(surface, first_axis_x, first_axis_y, first_depth_axis):
			return false
	return true

func _surface_projection_is_axis_aligned(surface: Dictionary) -> bool:
	var depth_axis: Vector3 = surface["depth_axis"] as Vector3
	return absf(depth_axis.x) > 0.999 or absf(depth_axis.y) > 0.999 or absf(depth_axis.z) > 0.999


func _surface_matches_axes_signed(surface: Dictionary, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3) -> bool:
	var stored_axis_x: Vector3 = surface["axis_x"] as Vector3
	var stored_axis_y: Vector3 = surface["axis_y"] as Vector3
	var stored_depth_axis: Vector3 = surface["depth_axis"] as Vector3
	return stored_axis_x.dot(axis_x) > 0.999 and stored_axis_y.dot(axis_y) > 0.999 and stored_depth_axis.dot(depth_axis) > 0.999

func _surfaces_include_non_axis_aligned(active_surfaces: Array) -> bool:
	for surface_value in active_surfaces:
		var surface: Dictionary = surface_value as Dictionary
		if not _surface_projection_is_axis_aligned(surface):
			return true
	return false


func _patch_surfaces_for_mixed_cut_mesh() -> Array:
	var patch_surfaces: Array = []
	for surface_value in cut_surfaces:
		var surface: Dictionary = surface_value as Dictionary
		if not _surface_projection_is_axis_aligned(surface):
			patch_surfaces.append(surface)
	return patch_surfaces


func _surface_operations_share_projection() -> bool:
	var operations: Array = []
	operations.append_array(cut_surfaces)
	operations.append_array(extrude_surfaces)
	if operations.is_empty():
		return false

	var first_surface: Dictionary = operations[0] as Dictionary
	var first_axis_x: Vector3 = first_surface["axis_x"] as Vector3
	var first_axis_y: Vector3 = first_surface["axis_y"] as Vector3
	var first_depth_axis: Vector3 = first_surface["depth_axis"] as Vector3
	for operation_value in operations:
		var operation: Dictionary = operation_value as Dictionary
		if not _surface_matches_axes_signed(operation, first_axis_x, first_axis_y, first_depth_axis):
			return false
	return true

func _cut_surfaces_share_projection() -> bool:
	return _surfaces_can_use_exact_projection(cut_surfaces)

func _visible_cut_surfaces() -> Array:
	if cut_surfaces.is_empty():
		return []

	var reference_surface: Dictionary = cut_surfaces[cut_surfaces.size() - 1] as Dictionary
	if has_display_axes:
		var matching_surfaces: Array = []
		for surface_value in cut_surfaces:
			var surface: Dictionary = surface_value as Dictionary
			if _surface_matches_display_view(surface):
				matching_surfaces.append(surface)
		return matching_surfaces

	var reference_axis_x: Vector3 = reference_surface["axis_x"] as Vector3
	var reference_axis_y: Vector3 = reference_surface["axis_y"] as Vector3
	var reference_depth_axis: Vector3 = reference_surface["depth_axis"] as Vector3
	var visible_surfaces: Array = []
	for surface_value in cut_surfaces:
		var surface: Dictionary = surface_value as Dictionary
		if _surface_matches_axes(surface, reference_axis_x, reference_axis_y, reference_depth_axis):
			visible_surfaces.append(surface)
	return visible_surfaces


func _latest_projection_surfaces() -> Array:
	if cut_surfaces.is_empty():
		return []

	var reference_surface: Dictionary = cut_surfaces[cut_surfaces.size() - 1] as Dictionary
	var reference_axis_x: Vector3 = reference_surface["axis_x"] as Vector3
	var reference_axis_y: Vector3 = reference_surface["axis_y"] as Vector3
	var reference_depth_axis: Vector3 = reference_surface["depth_axis"] as Vector3
	var matching_surfaces: Array = []
	for surface_value in cut_surfaces:
		var surface: Dictionary = surface_value as Dictionary
		if _surface_matches_axes_signed(surface, reference_axis_x, reference_axis_y, reference_depth_axis):
			matching_surfaces.append(surface)
	return matching_surfaces

func _surface_matches_axes(surface: Dictionary, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3) -> bool:
	var stored_axis_x: Vector3 = surface["axis_x"] as Vector3
	var stored_axis_y: Vector3 = surface["axis_y"] as Vector3
	var stored_depth_axis: Vector3 = surface["depth_axis"] as Vector3
	return absf(stored_axis_x.dot(axis_x)) > 0.999 and absf(stored_axis_y.dot(axis_y)) > 0.999 and absf(stored_depth_axis.dot(depth_axis)) > 0.999


func _surface_matches_display_view(surface: Dictionary) -> bool:
	var surface_group: String = _surface_view_group(surface)
	var display_group: String = _canonical_view_group(display_view_name)
	if display_group != "" and surface_group != "":
		return surface_group == display_group
	return _surface_matches_axes(surface, display_axis_x, display_axis_y, display_depth_axis)


func build_combined_cut_mesh() -> ArrayMesh:
	var surfaces_by_view: Dictionary = {}
	for surface_value in cut_surfaces:
		var surface: Dictionary = surface_value as Dictionary
		var key: String = _surface_axis_key(surface)
		if not surfaces_by_view.has(key):
			surfaces_by_view[key] = []
		var group: Array = surfaces_by_view[key] as Array
		group.append(surface)

	var faces: Array = _cube_polyhedron_faces()
	for key in surfaces_by_view.keys():
		var group: Array = surfaces_by_view[key] as Array
		if group.is_empty():
			continue

		var first_surface: Dictionary = group[0] as Dictionary
		var axis_x: Vector3 = first_surface["axis_x"] as Vector3
		var axis_y: Vector3 = first_surface["axis_y"] as Vector3
		var polygons: Array = _remaining_polygons_for_surfaces(group)
		var polygon: PackedVector2Array = _largest_polygon(polygons)
		if polygon.size() < 3:
			continue

		for edge_index in range(polygon.size()):
			var a: Vector2 = polygon[edge_index]
			var normal_2d: Vector2 = _outward_edge_normal_2d(polygon, edge_index)
			var plane_normal: Vector3 = (axis_x * normal_2d.x + axis_y * normal_2d.y).normalized()
			var plane_point: Vector3 = axis_x * a.x + axis_y * a.y
			faces = _clip_polyhedron_faces(faces, plane_normal, plane_point)
			if faces.is_empty():
				break
		if faces.is_empty():
			break

	return _mesh_from_polyhedron_faces(faces)


func _surface_view_group(surface: Dictionary) -> String:
	var stored_group: String = str(surface.get("view_group", ""))
	if stored_group != "":
		return stored_group
	return _canonical_view_group(str(surface.get("view_name", "")))


func _canonical_view_group(view_name: String) -> String:
	match view_name:
		"Front", "Back":
			return "FrontBack"
		"Left", "Right":
			return "LeftRight"
		"Top", "Bottom":
			return "TopBottom"
		_:
			return view_name


func _surface_axis_key(surface: Dictionary) -> String:
	var axis_x: Vector3 = surface["axis_x"] as Vector3
	var axis_y: Vector3 = surface["axis_y"] as Vector3
	var depth_axis: Vector3 = surface["depth_axis"] as Vector3
	return "%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f" % [
		axis_x.x, axis_x.y, axis_x.z,
		axis_y.x, axis_y.y, axis_y.z,
		depth_axis.x, depth_axis.y, depth_axis.z,
	]


func _remaining_polygons_for_surfaces(active_surfaces: Array) -> Array:
	var first_surface: Dictionary = active_surfaces[0] as Dictionary
	var axis_x: Vector3 = first_surface["axis_x"] as Vector3
	var axis_y: Vector3 = first_surface["axis_y"] as Vector3
	var polygons: Array = [_projected_cube_rect(axis_x, axis_y)]

	for surface in active_surfaces:
		var surface_data: Dictionary = surface as Dictionary
		var cutter: PackedVector2Array = surface_data["polygon"] as PackedVector2Array
		var next_polygons: Array = []
		for polygon in polygons:
			var source_polygon: PackedVector2Array = polygon as PackedVector2Array
			var clipped: Array = Geometry2D.clip_polygons(source_polygon, cutter)
			for clipped_polygon in clipped:
				var clipped_points: PackedVector2Array = clipped_polygon as PackedVector2Array
				if clipped_points.size() >= 3 and absf(_polygon_area(clipped_points)) > 0.0001:
					next_polygons.append(clipped_points)
		polygons = next_polygons

	return polygons


func _largest_polygon(polygons: Array) -> PackedVector2Array:
	var best_polygon := PackedVector2Array()
	var best_area: float = 0.0
	for polygon_value in polygons:
		var polygon: PackedVector2Array = polygon_value as PackedVector2Array
		if polygon.size() < 3:
			continue
		var area: float = absf(_polygon_area(polygon))
		if area > best_area:
			best_area = area
			best_polygon = polygon
	return best_polygon


func _cube_polyhedron_faces() -> Array:
	var half := Vector3(grid_size.x, grid_size.y, grid_size.z) * voxel_size * 0.5
	var x0: float = -half.x
	var x1: float = half.x
	var y0: float = -half.y
	var y1: float = half.y
	var z0: float = -half.z
	var z1: float = half.z
	return [
		[Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1)],
		[Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x0, y0, z0)],
		[Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0)],
		[Vector3(x0, y0, z1), Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1)],
		[Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)],
		[Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0)],
	]


func _clip_polyhedron_faces(faces: Array, plane_normal: Vector3, plane_point: Vector3) -> Array:
	var next_faces: Array = []
	var cap_points: Array[Vector3] = []
	var epsilon: float = 0.00001

	for face_value in faces:
		var face: Array = face_value as Array
		var clipped_face: Array = []
		for index in range(face.size()):
			var current: Vector3 = face[index]
			var previous: Vector3 = face[(index + face.size() - 1) % face.size()]
			var current_distance: float = plane_normal.dot(current - plane_point)
			var previous_distance: float = plane_normal.dot(previous - plane_point)
			var current_inside: bool = current_distance <= epsilon
			var previous_inside: bool = previous_distance <= epsilon

			if current_inside != previous_inside:
				var denominator: float = previous_distance - current_distance
				if absf(denominator) > 0.000001:
					var t: float = previous_distance / denominator
					var intersection: Vector3 = previous.lerp(current, t)
					clipped_face.append(intersection)
					_add_unique_point(cap_points, intersection)

			if current_inside:
				clipped_face.append(current)

		if clipped_face.size() >= 3:
			next_faces.append(clipped_face)

	var cap_face: Array = _ordered_cap_face(cap_points, -plane_normal)
	if cap_face.size() >= 3:
		next_faces.append(cap_face)

	return next_faces


func _add_unique_point(points: Array[Vector3], point: Vector3) -> void:
	for existing in points:
		if existing.distance_squared_to(point) < 0.000001:
			return
	points.append(point)


func _ordered_cap_face(points: Array[Vector3], normal: Vector3) -> Array:
	if points.size() < 3:
		return []

	var center := Vector3.ZERO
	for point in points:
		center += point
	center /= float(points.size())

	var axis_x := normal.cross(Vector3.UP)
	if axis_x.length_squared() < 0.000001:
		axis_x = normal.cross(Vector3.RIGHT)
	axis_x = axis_x.normalized()
	var axis_y := normal.cross(axis_x).normalized()

	var sortable: Array = []
	for point in points:
		var offset: Vector3 = point - center
		sortable.append({
			"point": point,
			"angle": atan2(offset.dot(axis_y), offset.dot(axis_x)),
		})
	sortable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["angle"]) < float(b["angle"]))

	var ordered: Array = []
	for item in sortable:
		var item_data: Dictionary = item as Dictionary
		ordered.append(item_data["point"] as Vector3)
	return ordered


func _mesh_from_polyhedron_faces(faces: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for face_value in faces:
		var face: Array = face_value as Array
		if face.size() < 3:
			continue
		var normal: Vector3 = ((face[1] as Vector3) - (face[0] as Vector3)).cross((face[2] as Vector3) - (face[0] as Vector3)).normalized()
		if normal.length_squared() <= 0.000001:
			continue
		for triangle_index in range(1, face.size() - 1):
			_append_triangle(vertices, normals, colors, indices, [face[0], face[triangle_index], face[triangle_index + 1]], normal, materials[0])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	if vertices.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func build_extrusion_overlay_mesh(active_extrusions: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for surface_value in active_extrusions:
		var surface: Dictionary = surface_value as Dictionary
		var polygon: PackedVector2Array = surface["polygon"] as PackedVector2Array
		var amount: float = float(surface.get("amount", 0.0))
		if polygon.size() < 3 or absf(amount) <= 0.0001:
			continue

		var axis_x: Vector3 = surface["axis_x"] as Vector3
		var axis_y: Vector3 = surface["axis_y"] as Vector3
		var depth_axis: Vector3 = surface["depth_axis"] as Vector3
		var surface_depth: float = float(surface.get("surface_depth", surface.get("depth_max", 0.0)))
		var extruded_depth: float = _surface_extrusion_depth(surface)
		_add_extruded_cap(vertices, normals, colors, indices, polygon, axis_x, axis_y, depth_axis, extruded_depth, depth_axis)
		_add_surface_extrusion_sides(vertices, normals, colors, indices, polygon, axis_x, axis_y, depth_axis, surface_depth, extruded_depth, amount > 0.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	if vertices.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _combine_meshes(meshes: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for mesh_value in meshes:
		var source_mesh: ArrayMesh = mesh_value as ArrayMesh
		if source_mesh == null or source_mesh.get_surface_count() == 0:
			continue

		for surface_index in range(source_mesh.get_surface_count()):
			var arrays: Array = source_mesh.surface_get_arrays(surface_index)
			var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var source_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertex_offset := vertices.size()

			vertices.append_array(source_vertices)
			normals.append_array(source_normals)
			colors.append_array(source_colors)
			for source_index in source_indices:
				indices.append(source_index + vertex_offset)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	if vertices.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func build_exact_cut_mesh(active_surfaces: Array) -> ArrayMesh:
	return build_exact_surface_mesh(active_surfaces, [])


func build_exact_surface_mesh(active_cuts: Array, active_extrusions: Array) -> ArrayMesh:
	if active_cuts.is_empty() and active_extrusions.is_empty():
		return build_base_poly_mesh()

	var first_surface: Dictionary = {}
	if not active_cuts.is_empty():
		first_surface = active_cuts[0] as Dictionary
	else:
		first_surface = active_extrusions[0] as Dictionary

	var axis_x: Vector3 = first_surface["axis_x"] as Vector3
	var axis_y: Vector3 = first_surface["axis_y"] as Vector3
	var depth_axis: Vector3 = first_surface["depth_axis"] as Vector3
	var depth_min: float = float(first_surface["depth_min"])
	var depth_max: float = float(first_surface["depth_max"])
	var polygons: Array = [_projected_cube_rect(axis_x, axis_y)]

	for surface in active_cuts:
		var surface_data: Dictionary = surface as Dictionary
		var cutter: PackedVector2Array = surface_data["polygon"] as PackedVector2Array
		var next_polygons: Array = []
		for polygon in polygons:
			var source_polygon: PackedVector2Array = polygon as PackedVector2Array
			var clipped: Array = Geometry2D.clip_polygons(source_polygon, cutter)
			for clipped_polygon in clipped:
				var clipped_points: PackedVector2Array = clipped_polygon as PackedVector2Array
				if clipped_points.size() >= 3 and absf(_polygon_area(clipped_points)) > 0.0001:
					next_polygons.append(clipped_points)
		polygons = next_polygons

	var extrusion_shapes: Array = _extrusion_shapes_for_polygons(polygons, active_extrusions)
	return _build_extruded_polygons_mesh(polygons, axis_x, axis_y, depth_axis, depth_min, depth_max, extrusion_shapes)


func _projected_cube_rect(axis_x: Vector3, axis_y: Vector3) -> PackedVector2Array:
	var half := Vector3(grid_size.x, grid_size.y, grid_size.z) * voxel_size * 0.5
	var projected_points: Array[Vector2] = []
	for x in [-half.x, half.x]:
		for y in [-half.y, half.y]:
			for z in [-half.z, half.z]:
				var point_3d := Vector3(x, y, z)
				_add_unique_projected_point(projected_points, Vector2(point_3d.dot(axis_x), point_3d.dot(axis_y)))
	return _convex_hull_2d(projected_points)


func _add_unique_projected_point(points: Array[Vector2], point: Vector2) -> void:
	for existing in points:
		if existing.distance_squared_to(point) < 0.000001:
			return
	points.append(point)


func _convex_hull_2d(points: Array[Vector2]) -> PackedVector2Array:
	if points.size() <= 3:
		return PackedVector2Array(points)

	points.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if not is_equal_approx(a.x, b.x):
			return a.x < b.x
		return a.y < b.y
	)

	var lower: Array[Vector2] = []
	for point in points:
		while lower.size() >= 2 and _cross_2d(lower[lower.size() - 1] - lower[lower.size() - 2], point - lower[lower.size() - 1]) <= 0.000001:
			lower.pop_back()
		lower.append(point)

	var upper: Array[Vector2] = []
	for index in range(points.size() - 1, -1, -1):
		var point: Vector2 = points[index]
		while upper.size() >= 2 and _cross_2d(upper[upper.size() - 1] - upper[upper.size() - 2], point - upper[upper.size() - 1]) <= 0.000001:
			upper.pop_back()
		upper.append(point)

	lower.pop_back()
	upper.pop_back()
	var hull: PackedVector2Array = PackedVector2Array()
	for point in lower:
		hull.append(point)
	for point in upper:
		hull.append(point)
	return hull


func _cross_2d(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


func _extrusion_shapes_for_polygons(polygons: Array, active_extrusions: Array) -> Array:
	var extrusion_shapes: Array = []
	for surface_value in active_extrusions:
		var surface: Dictionary = surface_value as Dictionary
		var cutter: PackedVector2Array = surface["polygon"] as PackedVector2Array
		var amount: float = float(surface.get("amount", 0.0))
		if cutter.size() < 3 or absf(amount) <= 0.0001:
			continue

		for polygon_value in polygons:
			var source_polygon: PackedVector2Array = polygon_value as PackedVector2Array
			var intersections: Array = Geometry2D.intersect_polygons(source_polygon, cutter)
			for intersection in intersections:
				var points: PackedVector2Array = intersection as PackedVector2Array
				if points.size() >= 3 and absf(_polygon_area(points)) > 0.0001:
					extrusion_shapes.append({
						"polygon": points,
						"surface_depth": float(surface.get("surface_depth", surface.get("depth_max", 0.0))),
						"extruded_depth": _surface_extrusion_depth(surface),
						"amount": amount,
					})
	return extrusion_shapes

func _surface_polygons_without_extrusion_openings(polygons: Array, extrusion_shapes: Array) -> Array:
	var top_polygons: Array = polygons.duplicate()
	for shape_value in extrusion_shapes:
		var shape: Dictionary = shape_value as Dictionary
		var cutter: PackedVector2Array = shape["polygon"] as PackedVector2Array
		var next_polygons: Array = []
		for polygon_value in top_polygons:
			var source_polygon: PackedVector2Array = polygon_value as PackedVector2Array
			var clipped: Array = Geometry2D.clip_polygons(source_polygon, cutter)
			for clipped_polygon in clipped:
				var points: PackedVector2Array = clipped_polygon as PackedVector2Array
				if points.size() >= 3 and absf(_polygon_area(points)) > 0.0001:
					next_polygons.append(points)
		top_polygons = next_polygons
	return top_polygons


func _build_extruded_polygons_mesh(polygons: Array, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3, depth_min: float, depth_max: float, extrusion_shapes: Array = []) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var top_polygons: Array = _surface_polygons_without_extrusion_openings(polygons, extrusion_shapes)

	for polygon in polygons:
		var points: PackedVector2Array = polygon as PackedVector2Array
		if points.size() < 3:
			continue
		_add_extruded_cap(vertices, normals, colors, indices, points, axis_x, axis_y, depth_axis, depth_min, -depth_axis)
		_add_extruded_sides(vertices, normals, colors, indices, points, axis_x, axis_y, depth_axis, depth_min, depth_max)

	for polygon in top_polygons:
		var points: PackedVector2Array = polygon as PackedVector2Array
		if points.size() < 3:
			continue
		_add_extruded_cap(vertices, normals, colors, indices, points, axis_x, axis_y, depth_axis, depth_max, depth_axis)

	for shape_value in extrusion_shapes:
		var shape: Dictionary = shape_value as Dictionary
		var points: PackedVector2Array = shape["polygon"] as PackedVector2Array
		var amount: float = float(shape.get("amount", 0.0))
		if points.size() < 3 or absf(amount) <= 0.0001:
			continue
		var surface_depth: float = float(shape.get("surface_depth", depth_max))
		var extruded_depth: float = float(shape.get("extruded_depth", surface_depth + amount))
		_add_extruded_cap(vertices, normals, colors, indices, points, axis_x, axis_y, depth_axis, extruded_depth, depth_axis)
		_add_surface_extrusion_sides(vertices, normals, colors, indices, points, axis_x, axis_y, depth_axis, surface_depth, extruded_depth, amount > 0.0)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	if vertices.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_extruded_cap(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, polygon: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3, depth: float, cap_normal: Vector3) -> void:
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	var area: float = _polygon_area(polygon)
	var wants_positive: bool = cap_normal.dot(depth_axis) > 0.0
	for triangle_index in range(0, triangles.size(), 3):
		var i0: int = triangles[triangle_index]
		var i1: int = triangles[triangle_index + 1]
		var i2: int = triangles[triangle_index + 2]
		if (area > 0.0) != wants_positive:
			var swap: int = i1
			i1 = i2
			i2 = swap
		var p0: Vector3 = axis_x * polygon[i0].x + axis_y * polygon[i0].y + depth_axis * depth
		var p1: Vector3 = axis_x * polygon[i1].x + axis_y * polygon[i1].y + depth_axis * depth
		var p2: Vector3 = axis_x * polygon[i2].x + axis_y * polygon[i2].y + depth_axis * depth
		_append_triangle(vertices, normals, colors, indices, [p0, p1, p2], cap_normal, materials[0])


func _add_extruded_sides(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, polygon: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3, depth_min: float, depth_max: float) -> void:
	for edge_index in range(polygon.size()):
		var a: Vector2 = polygon[edge_index]
		var b: Vector2 = polygon[(edge_index + 1) % polygon.size()]
		if a.distance_squared_to(b) <= 0.000001:
			continue
		var normal_2d: Vector2 = _outward_edge_normal_2d(polygon, edge_index)
		var side_normal: Vector3 = (axis_x * normal_2d.x + axis_y * normal_2d.y).normalized()
		var p0: Vector3 = axis_x * a.x + axis_y * a.y + depth_axis * depth_min
		var p1: Vector3 = axis_x * b.x + axis_y * b.y + depth_axis * depth_min
		var p2: Vector3 = axis_x * b.x + axis_y * b.y + depth_axis * depth_max
		var p3: Vector3 = axis_x * a.x + axis_y * a.y + depth_axis * depth_max
		_append_quad(vertices, normals, colors, indices, [p0, p1, p2, p3], side_normal, materials[0])


func _add_surface_extrusion_sides(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, polygon: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3, surface_depth: float, extruded_depth: float, is_outward: bool) -> void:
	for edge_index in range(polygon.size()):
		var a: Vector2 = polygon[edge_index]
		var b: Vector2 = polygon[(edge_index + 1) % polygon.size()]
		if a.distance_squared_to(b) <= 0.000001:
			continue
		var normal_2d: Vector2 = _outward_edge_normal_2d(polygon, edge_index)
		var side_normal: Vector3 = (axis_x * normal_2d.x + axis_y * normal_2d.y).normalized()
		if not is_outward:
			side_normal = -side_normal
		var p0: Vector3 = axis_x * a.x + axis_y * a.y + depth_axis * surface_depth
		var p1: Vector3 = axis_x * b.x + axis_y * b.y + depth_axis * surface_depth
		var p2: Vector3 = axis_x * b.x + axis_y * b.y + depth_axis * extruded_depth
		var p3: Vector3 = axis_x * a.x + axis_y * a.y + depth_axis * extruded_depth
		var quad: Array = [p0, p1, p2, p3] if is_outward else [p0, p3, p2, p1]
		_append_quad(vertices, normals, colors, indices, quad, side_normal, materials[0])


func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index_2d in range(polygon.size()):
		var a: Vector2 = polygon[index_2d]
		var b: Vector2 = polygon[(index_2d + 1) % polygon.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


func build_grid_shell_mesh(include_cut_plane_patches: bool = true, patch_surfaces: Array = []) -> ArrayMesh:
	cut_face_patch_surfaces = patch_surfaces.duplicate()
	if include_cut_plane_patches and cut_face_patch_surfaces.is_empty():
		cut_face_patch_surfaces = cut_surfaces.duplicate()
	cut_face_hiding_enabled = include_cut_plane_patches and not cut_face_patch_surfaces.is_empty()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for normal_axis in range(3):
		_build_greedy_axis(vertices, normals, colors, indices, normal_axis, 1)
		_build_greedy_axis(vertices, normals, colors, indices, normal_axis, -1)
	if cut_face_hiding_enabled:
		_add_cut_plane_patches(vertices, normals, colors, indices, cut_face_patch_surfaces)
	cut_face_hiding_enabled = true
	cut_face_patch_surfaces = []

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	if vertices.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func build_low_poly_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var padded_size := grid_size + Vector3i(3, 3, 3)
	var scalar_field := _build_scalar_field(padded_size)
	var cube_corners := [
		Vector3i(0, 0, 0),
		Vector3i(1, 0, 0),
		Vector3i(0, 1, 0),
		Vector3i(1, 1, 0),
		Vector3i(0, 0, 1),
		Vector3i(1, 0, 1),
		Vector3i(0, 1, 1),
		Vector3i(1, 1, 1),
	]
	var tetrahedra := [
		[0, 5, 1, 6],
		[0, 1, 2, 6],
		[0, 2, 3, 6],
		[0, 3, 7, 6],
		[0, 7, 4, 6],
		[0, 4, 5, 6],
	]

	for z in range(padded_size.z - 1):
		for y in range(padded_size.y - 1):
			for x in range(padded_size.x - 1):
				var corner_positions: Array[Vector3] = []
				var corner_values: Array[float] = []
				for offset in cube_corners:
					var point := Vector3i(x + offset.x, y + offset.y, z + offset.z)
					corner_positions.append(_padded_grid_to_world(point))
					corner_values.append(scalar_field[_scalar_index(point, padded_size)])

				for tetra in tetrahedra:
					var tetra_positions: Array[Vector3] = []
					var tetra_values: Array[float] = []
					for corner_index in tetra:
						tetra_positions.append(corner_positions[corner_index])
						tetra_values.append(corner_values[corner_index])
					_add_tetra_surface(vertices, normals, colors, indices, tetra_positions, tetra_values)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	if vertices.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_scalar_field(padded_size: Vector3i) -> PackedFloat32Array:
	var scalar_field := PackedFloat32Array()
	scalar_field.resize(padded_size.x * padded_size.y * padded_size.z)

	for z in range(padded_size.z):
		for y in range(padded_size.y):
			for x in range(padded_size.x):
				var solid_total := 0.0
				var sample_total := 0.0
				var cell_anchor := Vector3i(x - 1, y - 1, z - 1)

				for dz in [-1, 0]:
					for dy in [-1, 0]:
						for dx in [-1, 0]:
							var cell := cell_anchor + Vector3i(dx, dy, dz)
							sample_total += 1.0
							if is_solid(cell.x, cell.y, cell.z):
								solid_total += 1.0

				scalar_field[_scalar_index(Vector3i(x, y, z), padded_size)] = solid_total / sample_total - 0.5

	return scalar_field


func _scalar_index(point: Vector3i, padded_size: Vector3i) -> int:
	return point.x + padded_size.x * (point.y + padded_size.y * point.z)


func _padded_grid_to_world(point: Vector3i) -> Vector3:
	var half := Vector3(grid_size.x, grid_size.y, grid_size.z) * voxel_size * 0.5
	return Vector3(point.x - 1, point.y - 1, point.z - 1) * voxel_size - half


func _add_tetra_surface(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, positions: Array[Vector3], values: Array[float]) -> void:
	var inside := []
	var outside := []

	for i in range(4):
		if values[i] >= 0.0:
			inside.append(i)
		else:
			outside.append(i)

	if inside.size() == 0 or inside.size() == 4:
		return

	if inside.size() == 1:
		var a: int = inside[0]
		var tri := [
			_interpolate_surface_point(positions[a], values[a], positions[outside[0]], values[outside[0]]),
			_interpolate_surface_point(positions[a], values[a], positions[outside[1]], values[outside[1]]),
			_interpolate_surface_point(positions[a], values[a], positions[outside[2]], values[outside[2]]),
		]
		_append_surface_triangle(vertices, normals, colors, indices, tri, positions[a])
	elif inside.size() == 3:
		var a: int = outside[0]
		var tri := [
			_interpolate_surface_point(positions[a], values[a], positions[inside[0]], values[inside[0]]),
			_interpolate_surface_point(positions[a], values[a], positions[inside[2]], values[inside[2]]),
			_interpolate_surface_point(positions[a], values[a], positions[inside[1]], values[inside[1]]),
		]
		_append_surface_triangle(vertices, normals, colors, indices, tri, positions[inside[0]])
	elif inside.size() == 2:
		var p0 := _interpolate_surface_point(positions[inside[0]], values[inside[0]], positions[outside[0]], values[outside[0]])
		var p1 := _interpolate_surface_point(positions[inside[0]], values[inside[0]], positions[outside[1]], values[outside[1]])
		var p2 := _interpolate_surface_point(positions[inside[1]], values[inside[1]], positions[outside[1]], values[outside[1]])
		var p3 := _interpolate_surface_point(positions[inside[1]], values[inside[1]], positions[outside[0]], values[outside[0]])
		_append_surface_triangle(vertices, normals, colors, indices, [p0, p1, p2], positions[inside[0]])
		_append_surface_triangle(vertices, normals, colors, indices, [p0, p2, p3], positions[inside[1]])


func _interpolate_surface_point(a: Vector3, value_a: float, b: Vector3, value_b: float) -> Vector3:
	var denominator := value_a - value_b
	if absf(denominator) <= 0.00001:
		return (a + b) * 0.5
	var t: float = clampf(value_a / denominator, 0.0, 1.0)
	return a.lerp(b, t)


func _append_surface_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, triangle: Array, inside_hint: Vector3) -> void:
	var a: Vector3 = triangle[0]
	var b: Vector3 = triangle[1]
	var c: Vector3 = triangle[2]
	var normal := (b - a).cross(c - a).normalized()
	if normal.length_squared() <= 0.000001:
		return
	var center := (a + b + c) / 3.0

	if normal.dot(inside_hint - center) > 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal

	_append_triangle(vertices, normals, colors, indices, [a, b, c], normal, materials[0])


func _append_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, triangle: Array, normal: Vector3, color: Color) -> void:
	var base_index := vertices.size()
	for point in triangle:
		vertices.append(point)
		normals.append(normal)
		colors.append(color)

	indices.append(base_index)
	indices.append(base_index + 1)
	indices.append(base_index + 2)


func _build_greedy_axis(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, normal_axis: int, normal_sign: int) -> void:
	var plane_axes := _plane_axes_for_normal(normal_axis)
	var axis_a: int = plane_axes.x
	var axis_b: int = plane_axes.y
	var normal_size := _axis_size(normal_axis)
	var size_a := _axis_size(axis_a)
	var size_b := _axis_size(axis_b)

	for d in range(normal_size):
		var mask := PackedInt32Array()
		mask.resize(size_a * size_b)
		mask.fill(EMPTY)

		for b in range(size_b):
			for a in range(size_a):
				mask[a + b * size_a] = _visible_material(normal_axis, normal_sign, axis_a, axis_b, d, a, b)

		var used := PackedByteArray()
		used.resize(size_a * size_b)
		used.fill(0)

		for b in range(size_b):
			for a in range(size_a):
				var mask_index := a + b * size_a
				var material_index := mask[mask_index]
				if material_index == EMPTY or used[mask_index] == 1:
					continue

				var width := 1
				while a + width < size_a:
					var next_index := a + width + b * size_a
					if used[next_index] == 1 or mask[next_index] != material_index:
						break
					width += 1

				var height := 1
				var can_grow := true
				while b + height < size_b and can_grow:
					for offset_a in range(width):
						var next_index := a + offset_a + (b + height) * size_a
						if used[next_index] == 1 or mask[next_index] != material_index:
							can_grow = false
							break
					if can_grow:
						height += 1

				for fill_b in range(height):
					for fill_a in range(width):
						used[a + fill_a + (b + fill_b) * size_a] = 1

				_add_greedy_quad(vertices, normals, colors, indices, normal_axis, normal_sign, axis_a, axis_b, d, a, b, width, height, material_index)


func _visible_material(normal_axis: int, normal_sign: int, axis_a: int, axis_b: int, d: int, a: int, b: int) -> int:
	var cell := Vector3i.ZERO
	cell[normal_axis] = d
	cell[axis_a] = a
	cell[axis_b] = b

	if not is_solid(cell.x, cell.y, cell.z):
		return EMPTY

	var neighbor := cell
	neighbor[normal_axis] += normal_sign
	if is_solid(neighbor.x, neighbor.y, neighbor.z):
		return EMPTY

	var face_center := _face_center(cell, normal_axis, normal_sign)
	if cut_face_hiding_enabled and _should_hide_grid_face_on_cut(face_center):
		return EMPTY

	return voxels[index(cell.x, cell.y, cell.z)]


func _add_greedy_quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, normal_axis: int, normal_sign: int, axis_a: int, axis_b: int, d: int, a: int, b: int, width: int, height: int, material_index: int) -> void:
	var normal_grid := d + 1 if normal_sign > 0 else d
	var p0 := _grid_point(normal_axis, axis_a, axis_b, normal_grid, a, b)
	var p1 := _grid_point(normal_axis, axis_a, axis_b, normal_grid, a + width, b)
	var p2 := _grid_point(normal_axis, axis_a, axis_b, normal_grid, a + width, b + height)
	var p3 := _grid_point(normal_axis, axis_a, axis_b, normal_grid, a, b + height)
	var direction := Vector3.ZERO
	direction[normal_axis] = float(normal_sign)
	var color := materials[clampi(material_index, 0, materials.size() - 1)]
	var quad := [p0, p1, p2, p3] if normal_sign > 0 else [p0, p3, p2, p1]
	_append_quad(vertices, normals, colors, indices, quad, direction, color)


func _append_quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, quad: Array, normal: Vector3, color: Color) -> void:
	var base_index := vertices.size()
	for point in quad:
		vertices.append(point)
		normals.append(normal)
		colors.append(color)

	indices.append(base_index)
	indices.append(base_index + 1)
	indices.append(base_index + 2)
	indices.append(base_index)
	indices.append(base_index + 2)
	indices.append(base_index + 3)


func _grid_point(normal_axis: int, axis_a: int, axis_b: int, normal_value: int, a: int, b: int) -> Vector3:
	var grid_point := Vector3.ZERO
	grid_point[normal_axis] = float(normal_value)
	grid_point[axis_a] = float(a)
	grid_point[axis_b] = float(b)
	var half := Vector3(grid_size.x, grid_size.y, grid_size.z) * voxel_size * 0.5
	return grid_point * voxel_size - half


func _face_center(cell: Vector3i, normal_axis: int, normal_sign: int) -> Vector3:
	var center := voxel_center(cell.x, cell.y, cell.z)
	center[normal_axis] += float(normal_sign) * voxel_size * 0.5
	return center


func _store_cut_surface(polygon_points: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3, view_name: String = "") -> void:
	cut_surfaces.append({
		"polygon": polygon_points.duplicate(),
		"axis_x": axis_x,
		"axis_y": axis_y,
		"depth_axis": depth_axis,
		"depth_min": _projected_bound(depth_axis, true),
		"depth_max": _projected_bound(depth_axis, false),
		"view_name": view_name,
		"view_group": _canonical_view_group(view_name),
	})


func _store_extrude_surface(polygon_points: PackedVector2Array, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3, surface_depth: float, amount: float, view_name: String = "") -> void:
	extrude_surfaces.append({
		"polygon": polygon_points.duplicate(),
		"axis_x": axis_x,
		"axis_y": axis_y,
		"depth_axis": depth_axis,
		"depth_min": _projected_bound(depth_axis, true),
		"depth_max": _projected_bound(depth_axis, false),
		"surface_depth": surface_depth,
		"extruded_depth": surface_depth + amount,
		"amount": amount,
		"view_name": view_name,
		"view_group": _canonical_view_group(view_name),
	})

func _add_cut_plane_patches(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, active_surfaces: Array) -> void:
	for surface in active_surfaces:
		var polygon: PackedVector2Array = surface["polygon"] as PackedVector2Array
		if polygon.size() < 3:
			continue

		var axis_x: Vector3 = surface["axis_x"] as Vector3
		var axis_y: Vector3 = surface["axis_y"] as Vector3
		var depth_axis: Vector3 = surface["depth_axis"] as Vector3
		var depth_min: float = float(surface["depth_min"])
		var depth_max: float = float(surface["depth_max"])
		var depth_steps: int = max(1, ceili((depth_max - depth_min) / (voxel_size * 2.0)))

		for edge_index in range(polygon.size()):
			var a: Vector2 = polygon[edge_index]
			var b: Vector2 = polygon[(edge_index + 1) % polygon.size()]
			var edge_length: float = a.distance_to(b)
			if edge_length <= 0.001:
				continue

			var edge_steps: int = max(1, ceili(edge_length / voxel_size))
			var normal_2d: Vector2 = _outward_edge_normal_2d(polygon, edge_index)

			for edge_step in range(edge_steps):
				var t0: float = float(edge_step) / float(edge_steps)
				var t1: float = float(edge_step + 1) / float(edge_steps)
				var e0: Vector2 = a.lerp(b, t0)
				var e1: Vector2 = a.lerp(b, t1)
				var em: Vector2 = a.lerp(b, (t0 + t1) * 0.5)

				_add_cut_quad_runs(vertices, normals, colors, indices, axis_x, axis_y, depth_axis, normal_2d, e0, e1, em, depth_min, depth_max, depth_steps)


func _add_cut_quad_runs(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3, normal_2d: Vector2, e0: Vector2, e1: Vector2, em: Vector2, depth_min: float, depth_max: float, steps: int) -> void:
	var run_start: int = -1
	for depth_step in range(steps):
		var t: float = (float(depth_step) + 0.5) / float(steps)
		var depth: float = _clamped_cut_depth(lerpf(depth_min, depth_max, t), depth_min, depth_max)
		var has_boundary: bool = _edge_depth_is_boundary(axis_x, axis_y, depth_axis, normal_2d, em, depth)
		if has_boundary and run_start < 0:
			run_start = depth_step
		elif not has_boundary and run_start >= 0:
			_add_cut_quad_run(vertices, normals, colors, indices, axis_x, axis_y, depth_axis, normal_2d, e0, e1, em, depth_min, depth_max, steps, run_start, depth_step)
			run_start = -1

	if run_start >= 0:
		_add_cut_quad_run(vertices, normals, colors, indices, axis_x, axis_y, depth_axis, normal_2d, e0, e1, em, depth_min, depth_max, steps, run_start, steps)


func _add_cut_quad_run(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3, normal_2d: Vector2, e0: Vector2, e1: Vector2, em: Vector2, depth_min: float, depth_max: float, steps: int, run_start: int, run_end: int) -> void:
	var d0: float = lerpf(depth_min, depth_max, float(run_start) / float(steps))
	var d1: float = lerpf(depth_min, depth_max, float(run_end) / float(steps))
	if d1 - d0 < voxel_size * 0.2:
		return

	var p0: Vector3 = axis_x * e0.x + axis_y * e0.y + depth_axis * d0
	var p1: Vector3 = axis_x * e1.x + axis_y * e1.y + depth_axis * d0
	var p2: Vector3 = axis_x * e1.x + axis_y * e1.y + depth_axis * d1
	var p3: Vector3 = axis_x * e0.x + axis_y * e0.y + depth_axis * d1
	var plane_normal: Vector3 = (p1 - p0).cross(p3 - p0).normalized()
	if plane_normal.length_squared() <= 0.000001:
		return

	var center: Vector3 = (p0 + p1 + p2 + p3) * 0.25
	var outside_2d: Vector2 = em + normal_2d * voxel_size
	var outside_world: Vector3 = axis_x * outside_2d.x + axis_y * outside_2d.y + depth_axis * ((d0 + d1) * 0.5)
	if plane_normal.dot(outside_world - center) < 0.0:
		plane_normal = -plane_normal
		p0 += plane_normal * 0.001
		p1 += plane_normal * 0.001
		p2 += plane_normal * 0.001
		p3 += plane_normal * 0.001
		_append_quad(vertices, normals, colors, indices, [p0, p3, p2, p1], plane_normal, materials[0])
	else:
		p0 += plane_normal * 0.001
		p1 += plane_normal * 0.001
		p2 += plane_normal * 0.001
		p3 += plane_normal * 0.001
		_append_quad(vertices, normals, colors, indices, [p0, p1, p2, p3], plane_normal, materials[0])


func _should_hide_grid_face_on_cut(world_point: Vector3) -> bool:
	for surface in cut_face_patch_surfaces:
		var polygon: PackedVector2Array = surface["polygon"] as PackedVector2Array
		var axis_x: Vector3 = surface["axis_x"] as Vector3
		var axis_y: Vector3 = surface["axis_y"] as Vector3
		var depth_axis: Vector3 = surface["depth_axis"] as Vector3
		var depth_min: float = float(surface["depth_min"])
		var depth_max: float = float(surface["depth_max"])
		var point_2d: Vector2 = Vector2(world_point.dot(axis_x), world_point.dot(axis_y))
		var depth: float = _clamped_cut_depth(world_point.dot(depth_axis), depth_min, depth_max)

		for edge_index in range(polygon.size()):
			var a: Vector2 = polygon[edge_index]
			var b: Vector2 = polygon[(edge_index + 1) % polygon.size()]
			if _distance_to_segment(point_2d, a, b) > voxel_size * 2.6:
				continue
			var normal_2d: Vector2 = _outward_edge_normal_2d(polygon, edge_index)
			if _edge_depth_is_boundary(axis_x, axis_y, depth_axis, normal_2d, point_2d, depth):
				return true

	return false


func _edge_depth_is_boundary(axis_x: Vector3, axis_y: Vector3, depth_axis: Vector3, normal_2d: Vector2, point_2d: Vector2, depth: float) -> bool:
	var outside_2d: Vector2 = point_2d + normal_2d * voxel_size
	var inside_2d: Vector2 = point_2d - normal_2d * voxel_size
	var outside_cell: Vector3i = _world_to_cell(axis_x * outside_2d.x + axis_y * outside_2d.y + depth_axis * depth)
	var inside_cell: Vector3i = _world_to_cell(axis_x * inside_2d.x + axis_y * inside_2d.y + depth_axis * depth)
	if not is_in_bounds(outside_cell.x, outside_cell.y, outside_cell.z):
		return false
	if not is_in_bounds(inside_cell.x, inside_cell.y, inside_cell.z):
		return false
	return is_solid(outside_cell.x, outside_cell.y, outside_cell.z) != is_solid(inside_cell.x, inside_cell.y, inside_cell.z)


func _clamped_cut_depth(depth: float, depth_min: float, depth_max: float) -> float:
	var inset: float = voxel_size * 0.5
	return clampf(depth, depth_min + inset, depth_max - inset)


func _world_to_cell(world_point: Vector3) -> Vector3i:
	var half := Vector3(grid_size.x, grid_size.y, grid_size.z) * voxel_size * 0.5
	var grid_point := (world_point + half) / voxel_size
	return Vector3i(floori(grid_point.x), floori(grid_point.y), floori(grid_point.z))


func _projected_bound(axis: Vector3, use_min: bool) -> float:
	var half := Vector3(grid_size.x, grid_size.y, grid_size.z) * voxel_size * 0.5
	var best := INF if use_min else -INF
	for x in [-half.x, half.x]:
		for y in [-half.y, half.y]:
			for z in [-half.z, half.z]:
				var projected := Vector3(x, y, z).dot(axis)
				best = minf(best, projected) if use_min else maxf(best, projected)
	return best


func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(a + segment * t)


func _outward_edge_normal_2d(polygon: PackedVector2Array, edge_index: int) -> Vector2:
	var a: Vector2 = polygon[edge_index]
	var b: Vector2 = polygon[(edge_index + 1) % polygon.size()]
	var edge: Vector2 = b - a
	if edge.length_squared() <= 0.000001:
		return Vector2.RIGHT

	var normal: Vector2 = Vector2(edge.y, -edge.x).normalized()
	var midpoint: Vector2 = (a + b) * 0.5
	if Geometry2D.is_point_in_polygon(midpoint + normal * voxel_size, polygon):
		normal = -normal
	return normal


func _axis_size(axis: int) -> int:
	if axis == 0:
		return grid_size.x
	if axis == 1:
		return grid_size.y
	return grid_size.z


func _plane_axes_for_normal(normal_axis: int) -> Vector2i:
	if normal_axis == 0:
		return Vector2i(1, 2)
	if normal_axis == 1:
		return Vector2i(2, 0)
	return Vector2i(0, 1)
