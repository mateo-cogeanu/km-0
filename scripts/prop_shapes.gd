extends RefCounted


static func material(color: Color, metallic: float = 0.0, roughness: float = 0.82) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = roughness
	return result


static func box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, finish: Material, solid: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.material_override = finish
	parent.add_child(visual)
	visual.position = at
	if solid:
		var body := StaticBody3D.new()
		body.add_to_group("Road")
		visual.add_child(body)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
	return visual


static func cylinder(parent: Node3D, node_name: String, at: Vector3, axis: Vector3, radius: float, length: float, finish: Material, sides: int = 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.height = length
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.radial_segments = sides
	mesh.rings = 0
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.material_override = finish
	parent.add_child(visual)
	visual.position = at
	visual.quaternion = Quaternion(Vector3.UP, axis.normalized())
	return visual


static func tube(parent: Node3D, node_name: String, from: Vector3, to: Vector3, radius: float, finish: Material) -> MeshInstance3D:
	return cylinder(parent, node_name, (from + to) * 0.5, to - from, radius, from.distance_to(to), finish, 10)
