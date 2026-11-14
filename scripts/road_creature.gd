extends Node3D

const Shapes := preload("res://scripts/prop_shapes.gd")

var head: Node3D
var jaw: Node3D
var arms: Array[MeshInstance3D] = []
var forearms: Array[MeshInstance3D] = []
var legs: Array[MeshInstance3D] = []
var shins: Array[MeshInstance3D] = []
var skin := Shapes.material(Color("#b9aa9e"), 0.0, 0.91)
var joints := Shapes.material(Color("#7c6e6a"), 0.0, 0.96)
var mouth := Shapes.material(Color("#1c1013"), 0.0, 0.97)
var bone := Shapes.material(Color("#d9ccb0"), 0.0, 0.8)


func _ready() -> void:
	_oval(self, "Ribcage", Vector3(0, 1.86, 0), Vector3(0.46, 0.66, 0.24), skin)
	_oval(self, "Abdomen", Vector3(0, 1.52, -0.017), Vector3(0.28, 0.35, 0.20), joints)
	_oval(self, "Pelvis", Vector3(0, 1.34, -0.014), Vector3(0.36, 0.25, 0.25), skin)
	Shapes.tube(self, "Neck", Vector3(0, 2.04, 0), Vector3(0, 2.3, 0.034), 0.087, skin)
	for side in [-1.0, 1.0]:
		for rib in range(3):
			Shapes.tube(self, "Rib", Vector3(side * 0.06, 1.93 - rib * 0.09, 0.153),
				Vector3(side * 0.181, 1.98 - rib * 0.086, 0.084), 0.009, skin)
		arms.append(_limb(0.068, 0.052, 0.70))
		forearms.append(_limb(0.051, 0.035, 0.75))
		var hand := _oval(forearms.back(), "Palm", Vector3(0, 0.41, 0), Vector3(0.115, 0.151, 0.075), joints)
		for finger in range(4):
			var x := 0.018 * (finger - 1.5)
			Shapes.tube(hand, "Finger", Vector3(x, 0.05, 0), Vector3(x * 1.6, 0.16 + (finger % 2) * 0.024, -0.02), 0.009, skin)
		legs.append(_limb(0.088, 0.067, 0.68))
		shins.append(_limb(0.064, 0.04, 0.63))
		_oval(shins.back(), "Foot", Vector3(0, 0.30, 0.06), Vector3(0.11, 0.10, 0.22), skin)
	_build_head()
	pose(0.0, 0.0)


func _build_head() -> void:
	head = Node3D.new()
	head.position = Vector3(0, 2.12, 0.055)
	add_child(head)
	_oval(head, "LongSkull", Vector3(0, 0.28, 0), Vector3(0.395, 0.57, 0.335), skin)
	_oval(head, "MouthCavity", Vector3(0, 0.139, 0.125), Vector3(0.387, 0.422, 0.188), mouth)
	jaw = Node3D.new()
	_add_jaw()
	for side in [-1.0, 1.0]:
		_oval(head, "Cheek", Vector3(side * 0.156, 0.229, 0.098),
			Vector3(0.081, 0.245, 0.135), skin)
		_oval(head, "Temple", Vector3(side * 0.111, 0.407, 0.086),
			Vector3(0.139, 0.173, 0.139), skin)
	var socket := Shapes.material(Color("#09070a"), 0.0, 0.99)
	var slit := Shapes.material(Color("#b21019"))
	slit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slit.emission_enabled = true
	slit.emission = Color("#ff192c")
	slit.emission_energy_multiplier = 2.2
	for side in [-1.0, 1.0]:
		_oval(head, "BlackEye", Vector3(side * 0.094, 0.342, 0.148), Vector3(0.109, 0.131, 0.088), socket)
		_oval(head, "RedSlit", Vector3(side * 0.094, 0.342, 0.198), Vector3(0.010, 0.077, 0.008), slit)
	_build_teeth(head, Vector3(0, 0.25, 0.197), -1.0)
	_build_teeth(jaw, Vector3(0, -0.038, 0.164), 1.0)


func _add_jaw() -> void:
	head.add_child(jaw)
	jaw.position = Vector3(0, 0.075, 0.028)
	_oval(jaw, "Jaw", Vector3(0, -0.054, 0.039), Vector3(0.345, 0.159, 0.269), skin)
	_oval(jaw, "LowerMouth", Vector3(0, -0.035, 0.105), Vector3(0.328, 0.114, 0.170), mouth)


func _build_teeth(parent: Node3D, at: Vector3, direction: float) -> void:
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0007
	spike.bottom_radius = 0.0039
	spike.height = 0.029
	spike.radial_segments = 5
	spike.rings = 0
	spike.material = bone
	var rows := MultiMesh.new()
	rows.transform_format = MultiMesh.TRANSFORM_3D
	rows.mesh = spike
	rows.instance_count = 132
	var rng := RandomNumberGenerator.new()
	rng.seed = 431 if direction > 0 else 940
	for row in range(6):
		for tooth in range(22):
			var angle := lerpf(-1.29, 1.29, tooth / 21.0)
			var x := sin(angle) * (0.168 - row * 0.008)
			var y := direction * (-x * x * 2.1 + row * 0.006) + rng.randf_range(-0.004, 0.004)
			var z := cos(angle) * 0.032 - row * 0.012
			var axis := Vector3(x * -1.2, direction, rng.randf_range(-0.22, 0.22)).normalized()
			var basis := Basis(Quaternion(Vector3.UP, axis)).scaled_local(Vector3(1.0, rng.randf_range(0.52, 1.38), 1.0))
			rows.set_instance_transform(row * 22 + tooth, Transform3D(basis, at + Vector3(x, y, z)))
	var teeth := MultiMeshInstance3D.new()
	teeth.name = "Teeth"
	teeth.multimesh = rows
	parent.add_child(teeth)


func pose(phase: float, stride: float) -> void:
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var gait := sin(phase + i * PI) * stride
		var lift := maxf(0.0, cos(phase + i * PI)) * stride * 0.12
		var shoulder := Vector3(side * 0.244, 2.02, 0)
		var elbow := Vector3(side * 0.387, 1.37, -gait * 0.23 - 0.045)
		var wrist := Vector3(side * 0.31, 0.71, -gait * 0.34 + 0.04)
		var hip := Vector3(side * 0.115, 1.34, 0)
		var knee := Vector3(side * 0.141, 0.69 + lift * 0.6, gait * 0.16 + 0.05)
		var ankle := Vector3(side * 0.15, 0.07 + lift, gait * 0.29)
		_place(arms[i], shoulder, elbow)
		_place(forearms[i], elbow, wrist)
		_place(legs[i], hip, knee)
		_place(shins[i], knee, ankle)
	head.rotation.z = 0.07 + sin(phase * 0.52) * stride * 0.045


func _limb(radius_a: float, radius_b: float, length: float) -> MeshInstance3D:
	var limb := Shapes.cylinder(self, "Limb", Vector3.ZERO, Vector3.UP, radius_a, length, skin, 12)
	(limb.mesh as CylinderMesh).top_radius = radius_b
	return limb


func _place(limb: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	limb.position = (start + end) * 0.5
	limb.quaternion = Quaternion(Vector3.UP, (end - start).normalized())


func _oval(parent: Node3D, title: String, at: Vector3, size: Vector3, finish: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = title
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 10
	part.mesh = mesh
	part.material_override = finish
	parent.add_child(part)
	part.position = at
	part.scale = size
	return part
