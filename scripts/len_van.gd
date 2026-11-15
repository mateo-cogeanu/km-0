extends Node3D

const Shapes := preload("res://scripts/prop_shapes.gd")

var paint := Shapes.material(Color("#777e69"), 0.16)
var trim := Shapes.material(Color("#343534"))
var interior := Shapes.material(Color("#534b40"))
var glass := Shapes.material(Color("#526161"), 0.3, 0.35)
var steel := Shapes.material(Color("#a59d83"), 0.58)
var rubber := Shapes.material(Color("#282929"))


func _ready() -> void:
	Shapes.box(self, "Sills", Vector3(1.8, 0.48, 4.17), Vector3(0, 0.54, 0.02), paint, true)
	Shapes.box(self, "CargoBody", Vector3(1.79, 1.21, 2.49), Vector3(0, 1.32, 0.88), paint, true)
	Shapes.box(self, "CabRoof", Vector3(1.78, 0.13, 1.63), Vector3(0, 1.88, -0.8), paint)
	Shapes.box(self, "Bulkhead", Vector3(1.73, 1.08, 0.1), Vector3(0, 1.30, -0.43), interior)
	Shapes.box(self, "Bonnet", Vector3(1.81, 0.29, 0.7), Vector3(0, 0.85, -1.87), paint)
	var screen := Shapes.box(self, "Windscreen", Vector3(1.59, 0.76, 0.055), Vector3(0, 1.45, -1.57), glass)
	screen.rotation.x = -0.22
	Shapes.box(self, "Dashboard", Vector3(1.61, 0.16, 0.36), Vector3(0, 1.04, -1.43), trim)
	Shapes.box(self, "PassengerDoor", Vector3(0.091, 0.61, 1.08), Vector3(-0.85, 1.06, -0.95), paint)
	Shapes.box(self, "PassengerGlass", Vector3(0.044, 0.46, 0.97), Vector3(-0.85, 1.58, -0.95), glass)
	for side in [-1.0, 1.0]:
		for axle in [-1.46, 1.34]:
			var wheel := Vector3(side * 0.9, 0.35, axle)
			Shapes.cylinder(self, "Tyre", wheel, Vector3.RIGHT, 0.35, 0.22, rubber, 24)
			Shapes.cylinder(self, "Hub", wheel + Vector3(side * 0.116, 0, 0), Vector3.RIGHT, 0.19, 0.025, steel, 20)
		Shapes.box(self, "Headlamp", Vector3(0.35, 0.17, 0.055), Vector3(side * 0.61, 0.83, -2.24), steel)
		var tail := Shapes.material(Color("#793a2b"), 0.08)
		Shapes.box(self, "TailLamp", Vector3(0.13, 0.43, 0.045), Vector3(side * 0.75, 0.99, 2.148), tail)
		Shapes.box(self, "Seat", Vector3(0.54, 0.14, 0.48), Vector3(side * 0.42, 0.84, -0.84), interior)
		Shapes.box(self, "SeatBack", Vector3(0.54, 0.44, 0.105), Vector3(side * 0.42, 1.02, -0.62), interior).rotation.x = 0.16
	Shapes.box(self, "Grille", Vector3(0.78, 0.17, 0.055), Vector3(0, 0.83, -2.24), trim)
	for z in [-2.27, 2.15]:
		Shapes.box(self, "Bumper", Vector3(1.93, 0.17, 0.15), Vector3(0, 0.53, z), trim)
	Shapes.box(self, "RearDoorSeam", Vector3(0.014, 1.05, 0.012), Vector3(0, 1.34, 2.128), trim)
	_build_driver_door()
	_build_ignition()


func _build_driver_door() -> void:
	var door := Node3D.new()
	door.name = "OpenDriverDoor"
	door.position = Vector3(0.875, 0, -1.49)
	door.rotation.y = 1.13
	add_child(door)
	Shapes.box(door, "DoorSkin", Vector3(0.09, 0.62, 1.05), Vector3(0, 1.04, 0.53), paint)
	Shapes.box(door, "DoorCard", Vector3(0.022, 0.48, 0.92), Vector3(-0.05, 1.04, 0.53), interior)
	Shapes.tube(door, "WindowFrame", Vector3(0, 1.34, 0.06), Vector3(0, 1.80, 0.26), 0.025, trim)
	Shapes.tube(door, "WindowFrame", Vector3(0, 1.80, 0.26), Vector3(0, 1.80, 1.03), 0.025, trim)
	Shapes.tube(door, "WindowFrame", Vector3(0, 1.80, 1.03), Vector3(0, 1.34, 1.03), 0.025, trim)


func _build_ignition() -> void:
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.137
	wheel.outer_radius = 0.158
	var steering := MeshInstance3D.new()
	steering.name = "SteeringWheel"
	steering.mesh = wheel
	steering.material_override = trim
	steering.position = Vector3(0.40, 1.10, -1.19)
	steering.rotation.x = 0.96
	add_child(steering)
	var keys := Node3D.new()
	keys.name = "IgnitionKeys"
	keys.position = Vector3(0.62, 1.04, -1.23)
	add_child(keys)
	Shapes.cylinder(keys, "IgnitionBarrel", Vector3.ZERO, Vector3.BACK, 0.026, 0.025, steel)
	Shapes.box(keys, "InsertedKey", Vector3(0.019, 0.031, 0.047), Vector3(0, -0.004, 0.022), steel)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.018
	ring.outer_radius = 0.022
	var key_ring := MeshInstance3D.new()
	key_ring.mesh = ring
	key_ring.material_override = steel
	key_ring.position = Vector3(0, -0.025, 0.042)
	key_ring.rotation.x = PI / 2
	keys.add_child(key_ring)
	Shapes.box(keys, "SpareKey", Vector3(0.015, 0.054, 0.008), Vector3(0.01, -0.069, 0.041), steel).rotation.z = -0.24
	Shapes.box(keys, "BlueKeyTag", Vector3(0.031, 0.064, 0.008), Vector3(-0.02, -0.074, 0.05),
		Shapes.material(Color("#385d67"))).rotation.z = 0.27
