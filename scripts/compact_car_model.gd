extends RefCounted

const Shapes := preload("res://scripts/prop_shapes.gd")
const SEDAN := 0
const HATCHBACK := 1
const WAGON := 2
const DOORS := {"FL_Door": [-1, true], "FR_Door": [1, true], "RL_Door": [-1, false], "RR_Door": [1, false]}

var paint: StandardMaterial3D
var trim := Shapes.material(Color("#303331"), 0.12, 0.78)
var rubber := Shapes.material(Color("#222323"), 0.0, 0.92)
var alloy := Shapes.material(Color("#a3a8a4"), 0.68, 0.44)
var glass: StandardMaterial3D
var headlamp := Shapes.material(Color("#d9d5bb"), 0.25, 0.29)
var amber := Shapes.material(Color("#b86c2b"), 0.22, 0.37)
var tail := Shapes.material(Color("#8f2824"), 0.16, 0.32)
var fabric := Shapes.material(Color("#514f47"), 0.0, 0.94)


func _init(color := Color("#728b85")) -> void:
	paint = Shapes.material(color, 0.4, 0.44)
	paint.clearcoat_enabled = true
	paint.clearcoat_roughness = 0.48
	glass = Shapes.material(Color(0.23, 0.34, 0.37, 0.43), 0.16, 0.23)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED


static func rear_bumper(style: int) -> float:
	return 1.91 if style == HATCHBACK else (2.19 if style == WAGON else 2.12)


func build(root: Node3D, style: int, mechanical := true) -> void:
	var rear := rear_bumper(style)
	var body := _node(root, "Chassis")
	_skin(body, "BodyPaint", _body_sections(rear), paint, [Vector2(-1.4, 0.41), Vector2(1.43, 0.42)])
	_bumpers(body, rear, style)
	for side in [-1.0, 1.0]:
		Shapes.box(body, "RockerPanel", Vector3(0.13, 0.13, 1.93), Vector3(side * 0.832, 0.27, 0.038), trim)
	Shapes.box(body, "Undertray", Vector3(1.47, 0.095, 3.51), Vector3(0, 0.178, -0.02), trim)
	_cabin(root, style)
	_interior(root, style)
	for key in DOORS:
		make_door(root, key)
	make_hood(root)
	make_tailgate(root, style)
	_gas_cap(root)
	for i in range(4):
		var sides := [-1, 1, -1, 1]
		var ids := ["FL_Wheel", "FR_Wheel", "RL_Wheel", "RR_Wheel"]
		var wheel := make_wheel(root, ids[i])
		wheel.position = Vector3(sides[i] * 0.82, 0.39, -1.4 if i < 2 else 1.43)
	if mechanical:
		_engine_mounts(root)


func _body_sections(rear: float) -> Array:
	return [
		[-2.16, 0.78, 0.82, 0.30, 0.74], [-2.04, 0.83, 0.88, 0.24, 0.83],
		[-1.73, 0.86, 0.92, 0.22, 0.91], [-0.91, 0.85, 0.915, 0.22, 0.95],
		[0.55, 0.84, 0.91, 0.22, 0.94], [1.19, 0.84, 0.92, 0.23, 0.94],
		[rear - 0.11, 0.82, 0.88, 0.25, 0.91], [rear, 0.775, 0.82, 0.32, 0.83],
	]


func _bumpers(body: Node3D, rear: float, style: int) -> void:
	_skin(body, "FrontBumper", [[-2.23, 0.75, 0.80, 0.28, 0.49], [-2.15, 0.813, 0.85, 0.25, 0.51],
		[-2.04, 0.835, 0.867, 0.258, 0.51]], trim)
	_skin(body, "RearBumper", [[rear - 0.11, 0.814, 0.88, 0.26, 0.50], [rear + 0.035, 0.79, 0.846, 0.25, 0.50],
		[rear + 0.095, 0.73, 0.79, 0.29, 0.47]], trim)
	Shapes.box(body, "GrilleRecess", Vector3(0.61, 0.19, 0.045), Vector3(0, 0.642, -2.164), trim)
	if style == HATCHBACK:
		for i in range(13):
			Shapes.box(body, "GrilleSlat", Vector3(0.013, 0.145, 0.019), Vector3(-0.265 + i * 0.044, 0.642, -2.192), trim)
	else:
		for i in range(4):
			Shapes.box(body, "GrilleSlat", Vector3(0.57, 0.012, 0.019), Vector3(0, 0.577 + i * 0.042, -2.192), alloy)
	Shapes.box(body, "FrontPlate", Vector3(0.30, 0.087, 0.018), Vector3(0, 0.392, -2.235), alloy)
	for i in range(6):
		var x := -0.085 + i * 0.033
		Shapes.box(body, "PlateStamp", Vector3(0.013, 0.042, 0.004), Vector3(x, 0.392, -2.246), trim)
	Shapes.box(body, "RearPlate", Vector3(0.32, 0.092, 0.023), Vector3(0, 0.65, rear + 0.013), alloy)
	var rear_lights := _node(body, "RearLightMount")
	rear_lights.position = Vector3(0, 0.725, rear)
	for side in [-1, 1]:
		var x := float(side)
		var lens_height := 0.122 if style == HATCHBACK else 0.155
		var lens := Shapes.box(body, "HeadlightLens", Vector3(0.315, lens_height, 0.050), Vector3(x * 0.52, 0.654, -2.14), headlamp)
		lens.rotation.y = x * -0.105
		Shapes.box(body, "FrontIndicator", Vector3(0.103, 0.146, 0.053), Vector3(x * 0.726, 0.654, -2.108), amber).rotation.y = x * -0.21
		Shapes.box(rear_lights, "BrakeLens", Vector3(0.27, 0.15, 0.066), Vector3(x * 0.61, 0, 0.013), tail)
		Shapes.box(rear_lights, "RearIndicator", Vector3(0.089, 0.136, 0.059), Vector3(x * 0.778, 0, -0.012), amber)
	Shapes.cylinder(body, "ExhaustTip", Vector3(0.60, 0.245, rear + 0.064), Vector3.BACK, 0.037, 0.14, alloy, 18)


func _cabin(root: Node3D, style: int) -> void:
	var body := root.get_node("Chassis") as Node3D
	var windows := _node(root, "Windows")
	var back_top := 0.84 if style == SEDAN else (1.02 if style == HATCHBACK else 1.58)
	var back_low := 1.26 if style == SEDAN else (1.63 if style == HATCHBACK else 1.96)
	var rear_height := 1.59 if style != WAGON else 1.66
	_skin(body, "RoofPaint", [[-0.50, 0.637, 0.66, 1.55, 1.615], [-0.37, 0.645, 0.669, 1.57, 1.675],
		[0.54, 0.645, 0.670, 1.57, 1.68], [back_top, 0.622, 0.652, rear_height - 0.045, rear_height]], paint)
	var front := [Vector3(-0.805, 0.961, -0.91), Vector3(0.805, 0.961, -0.91),
		Vector3(0.643, 1.567, -0.465), Vector3(-0.643, 1.567, -0.465)]
	_glazing(windows, "Windscreen", front)
	if style == SEDAN:
		_glazing(windows, "RearScreen", [Vector3(-0.78, 0.951, back_low), Vector3(-0.622, rear_height - 0.055, back_top),
			Vector3(0.622, rear_height - 0.055, back_top), Vector3(0.78, 0.951, back_low)])
	for side in [-1.0, 1.0]:
		var front_bottom := Vector3(side * 0.805, 0.96, -0.91)
		var front_top := Vector3(side * 0.652, 1.576, -0.46)
		Shapes.tube(body, "FrontPillar", front_bottom, front_top, 0.027, paint).set_meta("body_paint", true)
		Shapes.tube(body, "CenterPillar", Vector3(side * 0.823, 0.935, 0.03), Vector3(side * 0.661, 1.579, 0.03), 0.025, trim)
		Shapes.tube(body, "RoofGutter", front_top, Vector3(side * 0.637, rear_height - 0.048, back_top), 0.017, trim)
		Shapes.tube(body, "RearPillar", Vector3(side * 0.637, rear_height - 0.053, back_top),
			Vector3(side * 0.795, 0.933, back_low), 0.043, paint).set_meta("body_paint", true)
		if style != SEDAN:
			_glazing(windows, "CargoQuarterGlass", [Vector3(side * 0.806, 0.99, 1.06),
				Vector3(side * 0.78, 1.01, back_low - 0.09), Vector3(side * 0.653, rear_height - 0.092, back_top - 0.06),
				Vector3(side * 0.678, 1.46, 0.91)])
			_plate(body, "CargoQuarterPanel", [Vector3(side * 0.846, 0.92, 0.955),
				Vector3(side * 0.807, 0.92, back_low), Vector3(side * 0.78, 1.01, back_low - 0.09),
				Vector3(side * 0.806, 0.99, 1.06)], Vector3(-side * 0.02, 0, 0), paint, true)
	for side in [-1.0, 1.0]:
		Shapes.tube(body, "WiperArm", Vector3(side * 0.53, 0.983, -0.926), Vector3(side * 0.21, 1.09, -0.825), 0.009, trim)
		Shapes.tube(body, "WiperBlade", Vector3(side * 0.05, 1.108, -0.817), Vector3(side * 0.57, 1.083, -0.849), 0.009, rubber)
	if style == WAGON:
		for side in [-1.0, 1.0]:
			for z in [0.0, 1.38]:
				Shapes.box(body, "RoofRailFoot", Vector3(0.065, 0.062, 0.11), Vector3(side * 0.54, 1.678, z), trim)
			Shapes.tube(body, "RoofRail", Vector3(side * 0.54, 1.731, -0.12), Vector3(side * 0.54, 1.731, 1.49), 0.024, trim)


func make_door(parent: Node3D, title: String) -> Node3D:
	var config: Array = DOORS[title]
	var side: float = config[0]
	var front: bool = config[1]
	var door := _node(parent, title)
	door.position = Vector3(side * 0.82, 0.69, -0.92 if front else 0.055)
	var length := 0.955 if front else 0.895
	var width_at_rear := 0.096 if front else 0.091
	var panel := [Vector3(side * 0.06, -0.38, 0.015), Vector3(side * (width_at_rear - 0.02), -0.38, length - 0.032),
		Vector3(side * width_at_rear, 0.239, length - 0.014), Vector3(side * 0.058, 0.252, 0.017)]
	_plate(door, "DoorSkin", panel, Vector3(side * -0.075, 0, 0), paint, true)
	var bottom_front := Vector3(side * -0.005, 0.267, 0.038)
	var bottom_back := Vector3(side * 0.002, 0.255, length - 0.038)
	var top_front := Vector3(side * -0.149, 0.871, 0.46 if front else 0.035)
	var top_back := Vector3(side * -0.153, 0.860 if front else 0.770, length - (0.041 if front else 0.18))
	_glazing(door, "DoorGlass", [bottom_front, bottom_back, top_back, top_front])
	Shapes.box(door, "DoorCard", Vector3(0.035, 0.345, length - 0.105), Vector3(-side * 0.029, 0.012, length * 0.5), fabric)
	Shapes.box(door, "ExteriorHandle", Vector3(0.031, 0.037, 0.126), Vector3(side * 0.102, 0.137, length - 0.16), trim)
	Shapes.box(door, "HandleInset", Vector3(0.007, 0.012, 0.092), Vector3(side * 0.121, 0.138, length - 0.16), alloy)
	Shapes.box(door, "SideMolding", Vector3(0.029, 0.054, length - 0.051), Vector3(side * 0.088, -0.129, length * 0.5), trim)
	if front:
		var mount := Vector3(side * 0.18, 0.374, 0.20)
		Shapes.tube(door, "MirrorMount", Vector3(side * 0.028, 0.30, 0.22), mount, 0.022, trim)
		var mirror := Shapes.box(door, "MirrorHousing", Vector3(0.156, 0.080, 0.097), mount, trim)
		mirror.rotation.y = side * 0.2
		Shapes.box(mirror, "MirrorGlass", Vector3(0.129, 0.061, 0.004), Vector3(0, 0, 0.05), alloy)
	return door


func make_hood(parent: Node3D) -> Node3D:
	var hinge := _node(parent, "HoodTargetHinge")
	hinge.position = Vector3(0, 0.961, -0.88)
	var hood := _skin(hinge, "Hood", [[-1.24, 0.765, 0.79, -0.19, -0.145], [-1.08, 0.80, 0.831, -0.117, -0.062],
		[-0.82, 0.808, 0.856, -0.063, -0.009], [-0.04, 0.80, 0.84, -0.024, 0.016]], paint)
	for side in [-1.0, 1.0]:
		Shapes.tube(hood, "PressedCrease", Vector3(side * 0.46, -0.10, -1.09), Vector3(side * 0.61, 0.012, -0.13), 0.005, paint).set_meta("body_paint", true)
	return hinge


func make_tailgate(parent: Node3D, style: int) -> Node3D:
	var hinge := _node(parent, "TrunkTargetHinge")
	hinge.set_meta("body_style", style)
	if style == SEDAN:
		hinge.position = Vector3(0, 0.942, 1.26)
		_skin(hinge, "Trunk", [[0.015, 0.758, 0.782, -0.036, 0.010], [0.59, 0.743, 0.777, -0.051, -0.008],
			[0.84, 0.72, 0.751, -0.08, -0.042]], paint)
	else:
		var roof_end := 1.02 if style == HATCHBACK else 1.58
		var height := 1.59 if style == HATCHBACK else 1.66
		hinge.position = Vector3(0, height - 0.055, roof_end)
		var gate := _node(hinge, "Trunk")
		var end := rear_bumper(style) - roof_end
		var shoulder := 0.57 if style == HATCHBACK else 0.35
		_glazing(gate, "TailgateGlass", [Vector3(-0.613, -0.037, 0.016), Vector3(0.613, -0.037, 0.016),
			Vector3(0.741, -0.48, shoulder), Vector3(-0.741, -0.48, shoulder)])
		_plate(gate, "TailgatePaint", [Vector3(-0.752, -0.477, shoulder), Vector3(0.752, -0.477, shoulder),
			Vector3(0.75, -0.703, end - 0.012), Vector3(-0.75, -0.703, end - 0.012)], Vector3(0, -0.035, -0.034), paint, true)
		Shapes.box(gate, "TailgateHandle", Vector3(0.23, 0.041, 0.036), Vector3(0, -0.55, lerpf(shoulder, end, 0.36)), trim)
	return hinge


func _gas_cap(root: Node3D) -> void:
	var hinge := _node(root, "GasCapTargetHinge")
	hinge.position = Vector3(0.892, 0.801, 1.23)
	var filler := _node(root, "FuelFiller")
	filler.position = Vector3(0.883, 0.801, 1.307)
	Shapes.cylinder(root, "FillerRecess", filler.position, Vector3.RIGHT, 0.058, 0.016, trim, 20)
	var lid := Shapes.box(hinge, "gascap", Vector3(0.019, 0.122, 0.146), Vector3(0.012, 0, 0.077), paint)
	lid.set_meta("body_paint", true)


func _interior(root: Node3D, style: int) -> void:
	var cabin := _node(root, "Interior")
	Shapes.box(cabin, "Floor", Vector3(1.59, 0.08, 2.07), Vector3(0, 0.363, 0.14), fabric)
	_skin(cabin, "Dashboard", [[-0.85, 0.74, 0.77, 0.68, 0.918], [-0.62, 0.743, 0.768, 0.65, 0.884],
		[-0.56, 0.72, 0.743, 0.685, 0.852]], trim)
	for side in [-1.0, 1.0]:
		_skin(cabin, "SeatBase", [[-0.26, 0.22, 0.24, 0.46, 0.58], [0.01, 0.239, 0.255, 0.44, 0.625],
			[0.39, 0.19, 0.22, 0.46, 0.58]], fabric).position.x = side * 0.40
		var seat := Shapes.box(cabin, "SeatBack", Vector3(0.44, 0.50, 0.12), Vector3(side * 0.40, 0.85, 0.35), fabric)
		seat.rotation.x = 0.16
		Shapes.box(cabin, "Headrest", Vector3(0.23, 0.14, 0.096), Vector3(side * 0.40, 1.15, 0.41), fabric)
		Shapes.box(cabin, "Seatbelt", Vector3(0.026, 0.39, 0.014), Vector3(side * 0.581, 0.89, 0.275), trim).rotation.z = side * 0.24
	Shapes.box(cabin, "RearBench", Vector3(1.38, 0.13, 0.47), Vector3(0, 0.52, 0.93), fabric)
	Shapes.box(cabin, "RearBackrest", Vector3(1.40, 0.36, 0.105), Vector3(0, 0.73, 1.175), fabric).rotation.x = 0.18
	if style != SEDAN:
		Shapes.box(cabin, "CargoMat", Vector3(1.37, 0.035, 0.66), Vector3(0, 0.57, 1.55), rubber)
	var wheel := _node(cabin, "Steerwheel")
	wheel.position = Vector3(-0.42, 0.94, -0.44)
	wheel.rotation.x = 0.76
	var ring := TorusMesh.new()
	ring.inner_radius = 0.149
	ring.outer_radius = 0.17
	ring.rings = 26
	ring.ring_segments = 10
	_mesh(wheel, "SteeringRim", ring, rubber)
	Shapes.box(wheel, "SteeringHorn", Vector3(0.15, 0.039, 0.084), Vector3.ZERO, trim)
	for x in [-0.12, 0.12]:
		Shapes.box(wheel, "SteeringSpoke", Vector3(0.09, 0.025, 0.037), Vector3(x, 0, 0), trim)
	for x in [-0.48, -0.36]:
		Shapes.cylinder(cabin, "InstrumentDial", Vector3(x, 0.898, -0.570), Vector3.BACK, 0.044, 0.012, rubber, 20)
		Shapes.box(cabin, "InstrumentNeedle", Vector3(0.0025, 0.029, 0.004), Vector3(x, 0.898, -0.560), amber).rotation.z = 0.64
	Shapes.box(cabin, "Radio", Vector3(0.20, 0.071, 0.03), Vector3(0, 0.795, -0.555), rubber)
	for x in [-0.067, 0.067]:
		Shapes.cylinder(cabin, "RadioKnob", Vector3(x, 0.795, -0.531), Vector3.BACK, 0.011, 0.021, alloy, 12)
	Shapes.tube(cabin, "GearLever", Vector3(0, 0.489, -0.25), Vector3(0, 0.68, -0.31), 0.013, alloy)
	Shapes.box(cabin, "GearKnob", Vector3(0.047, 0.039, 0.044), Vector3(0, 0.684, -0.31), rubber)


func _engine_mounts(root: Node3D) -> void:
	var mounts := [
		["Engine", Vector3(-0.07, 0.682, -1.45), Vector3(0.3268, 0.253, 0.3268), Vector3(2.8, 2.3, 2.2)],
		["Radiator", Vector3(0, 0.647, -1.905), Vector3(0.327, 0.253, 0.058), Vector3(3.1, 2.0, 2.8)],
		["Battery", Vector3(-0.568, 0.647, -1.36), Vector3(0.196, 0.276, 0.152), Vector3(1.18, 0.89, 1.12)],
	]
	for data in mounts:
		var part := Shapes.box(root, data[0], data[3], data[1], trim)
		part.rotation.y = PI if data[0] != "Battery" else PI * 0.5
		part.scale = data[2]
	Shapes.box(root, "Firewall", Vector3(1.52, 0.36, 0.06), Vector3(0, 0.626, -0.91), trim)
	for side in [-1.0, 1.0]:
		Shapes.cylinder(root, "StrutTop", Vector3(side * 0.64, 0.79, -1.67), Vector3.UP, 0.087, 0.093, trim)
		Shapes.cylinder(root, "StrutNut", Vector3(side * 0.64, 0.839, -1.67), Vector3.UP, 0.032, 0.026, alloy, 6)


func make_wheel(parent: Node3D, title: String) -> Node3D:
	var wheel := _node(parent, title)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := [Vector2(-0.096, 0.270), Vector2(-0.109, 0.321), Vector2(-0.103, 0.372),
		Vector2(-0.075, 0.384), Vector2(0, 0.390), Vector2(0.075, 0.384), Vector2(0.103, 0.372),
		Vector2(0.109, 0.321), Vector2(0.096, 0.270)]
	for j in profile.size():
		var a: Vector2 = profile[j]
		var b: Vector2 = profile[(j + 1) % profile.size()]
		for i in range(48):
			var theta := TAU * i / 48.0
			var next := TAU * (i + 1) / 48.0
			_quad(surface, _polar(a, theta), _polar(b, theta), _polar(b, next), _polar(a, next))
	_finish(surface, wheel, "Tire", rubber)
	var tread := SurfaceTool.new()
	tread.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(48):
		var theta := TAU * i / 48.0
		for side in [-1.0, 1.0]:
			var a := _polar(Vector2(side * 0.02, 0.3897), theta)
			var b := _polar(Vector2(side * 0.084, 0.3850), theta + side * 0.075)
			var c := _polar(Vector2(side * 0.084, 0.3850), theta + side * 0.075 + 0.035)
			var d := _polar(Vector2(side * 0.02, 0.3897), theta + 0.035)
			if side > 0.0:
				_quad(tread, a, b, c, d)
			else:
				_quad(tread, d, c, b, a)
	_finish(tread, wheel, "TreadBlocks", trim)
	Shapes.cylinder(wheel, "SteelRim", Vector3.ZERO, Vector3.RIGHT, 0.281, 0.174, alloy, 36)
	for side in [-1.0, 1.0]:
		Shapes.cylinder(wheel, "WheelDish", Vector3(side * 0.088, 0, 0), Vector3.RIGHT, 0.249, 0.012, trim, 32)
		for i in range(12):
			var angle := TAU * i / 12.0
			var spoke := Shapes.box(wheel, "PressedSpoke", Vector3(0.018, 0.145, 0.051),
				Vector3(side * 0.098, cos(angle) * 0.155, sin(angle) * 0.155), alloy)
			spoke.rotation.x = angle
		Shapes.cylinder(wheel, "CenterCap", Vector3(side * 0.11, 0, 0), Vector3.RIGHT, 0.086, 0.026, alloy, 24)
		for i in range(4):
			var angle := TAU * i / 4.0
			Shapes.cylinder(wheel, "LugNut", Vector3(side * 0.129, cos(angle) * 0.053, sin(angle) * 0.053),
				Vector3.RIGHT, 0.014, 0.015, trim, 6)
	return wheel


func _polar(p: Vector2, theta: float) -> Vector3:
	return Vector3(p.x, cos(theta) * p.y, sin(theta) * p.y)


func _skin(parent: Node3D, title: String, sections: Array, finish: Material, arches: Array[Vector2] = []) -> MeshInstance3D:
	# Eight points across each section form the crown, shoulders, and sills.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array[Array] = []
	for i in range(sections.size() - 1):
		var a: Array = sections[i]
		var b: Array = sections[i + 1]
		var steps := maxi(1, ceili((b[0] - a[0]) / 0.07)) if not arches.is_empty() else 1
		for step in range(steps):
			var row := []
			for field in range(5):
				row.append(lerpf(a[field], b[field], float(step) / steps))
			rows.append(row)
	rows.append(sections.back())
	for row in range(rows.size() - 1):
		var a := _profile(rows[row], arches)
		var b := _profile(rows[row + 1], arches)
		for i in a.size():
			var next := (i + 1) % a.size()
			var z: float = rows[row][0]
			if not arches.is_empty():
				if i == 0 and z > -2.04 and z < sections.back()[0] - 0.09:
					continue
				if z >= -0.90 and z < 0.96 and i in [1, 2, 6, 7]:
					continue
			_quad(surface, a[i], a[next], b[next], b[i])
	for row in [0, rows.size() - 1]:
		var points := _profile(rows[row], arches)
		var center := (points[0] + points[4]) * 0.5
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			for vertex in ([center, b, a] if row == 0 else [center, a, b]):
				surface.add_vertex(vertex)
	return _finish(surface, parent, title, finish, finish == paint)


func _profile(row: Array, arches: Array[Vector2]) -> PackedVector3Array:
	var z: float = row[0]
	var crown: float = row[1]
	var shoulder: float = row[2]
	var bottom: float = row[3]
	var top: float = row[4]
	for arch in arches:
		var along := absf(z - arch.x)
		if along < arch.y:
			bottom = maxf(bottom, 0.39 + sqrt(arch.y * arch.y - along * along))
	var rise := minf(0.09, (top - bottom) * 0.38)
	return PackedVector3Array([Vector3(-crown, top, z), Vector3(crown, top, z),
		Vector3(shoulder, top - rise, z), Vector3(shoulder * 0.974, bottom + rise * 0.33, z),
		Vector3(shoulder * 0.90, bottom, z), Vector3(-shoulder * 0.90, bottom, z),
		Vector3(-shoulder * 0.974, bottom + rise * 0.33, z), Vector3(-shoulder, top - rise, z)])


func _glazing(parent: Node3D, title: String, corners: Array) -> void:
	# Trace the seal in rubber before adding the pane.
	for i in corners.size():
		Shapes.tube(parent, title + "Seal", corners[i], corners[(i + 1) % corners.size()], 0.011, rubber)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(surface, corners[0], corners[1], corners[2], corners[3])
	_finish(surface, parent, title, glass)


func _plate(parent: Node3D, title: String, corners: Array, inset: Vector3, finish: Material, body_paint: bool) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(surface, corners[0], corners[1], corners[2], corners[3])
	_quad(surface, corners[3] + inset, corners[2] + inset, corners[1] + inset, corners[0] + inset)
	for i in corners.size():
		var next := (i + 1) % corners.size()
		_quad(surface, corners[next], corners[i], corners[i] + inset, corners[next] + inset)
	var two_sided := finish.duplicate() as StandardMaterial3D
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	_finish(surface, parent, title, two_sided, body_paint)


static func _node(parent: Node3D, title: String) -> Node3D:
	var result := Node3D.new()
	result.name = title
	parent.add_child(result)
	return result


static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for point in [a, b, c, a, c, d]:
		surface.add_vertex(point)


static func _mesh(parent: Node3D, title: String, mesh: Mesh, finish: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = mesh
	instance.material_override = finish
	parent.add_child(instance)
	return instance


static func _finish(surface: SurfaceTool, parent: Node3D, title: String, finish: Material, body_paint := false) -> MeshInstance3D:
	surface.index()
	surface.generate_normals()
	var instance := _mesh(parent, title, surface.commit(), finish)
	instance.set_meta("body_paint", body_paint)
	return instance
