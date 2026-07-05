class_name ChiselOperation
extends RefCounted

var view_direction: String = "Front"
var polygon_points: PackedVector2Array = PackedVector2Array()
var cut_depth: float = 1.0
var invert_cut: bool = false
var timestamp: int = 0


func _init(next_view_direction: String = "Front", next_polygon_points: PackedVector2Array = PackedVector2Array(), next_cut_depth: float = 1.0, next_invert_cut: bool = false) -> void:
	view_direction = next_view_direction
	polygon_points = next_polygon_points
	cut_depth = next_cut_depth
	invert_cut = next_invert_cut
	timestamp = int(Time.get_unix_time_from_system())
