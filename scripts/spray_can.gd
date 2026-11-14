extends RigidBody3D

@export var spray_color: Color = Color(0.9, 0.08, 0.05, 1.0)

var color_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("spray_can")
	set_spray_color(spray_color)


func set_spray_color(color: Color) -> void:
	spray_color = color
	var color_part := find_child("change_color", true, false)
	if color_part == null:
		return

	if color_material == null:
		color_material = StandardMaterial3D.new()
		color_material.roughness = 0.42

	color_material.albedo_color = spray_color
	_apply_color_material_recursive(color_part)


func get_spray_color() -> Color:
	return spray_color


func _apply_color_material_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = color_material

	for child in node.get_children():
		_apply_color_material_recursive(child)
