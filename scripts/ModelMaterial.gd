class_name ModelMaterial
extends RefCounted

var material_name: String = "Default stone"
var color: Color = Color(0.62, 0.63, 0.62, 1.0)
var metallic: float = 0.0
var roughness: float = 0.85


func _init(next_name: String = "Default stone", next_color: Color = Color(0.62, 0.63, 0.62, 1.0), next_metallic: float = 0.0, next_roughness: float = 0.85) -> void:
	material_name = next_name
	color = next_color
	metallic = next_metallic
	roughness = next_roughness
