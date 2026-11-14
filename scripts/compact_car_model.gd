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
	paint = Shapes.material(color, 0.24, 0.47)
	paint.clearcoat_enabled = true
	paint.clearcoat_roughness = 0.48
	glass = Shapes.material(Color(0.20, 0.28, 0.31, 0.34), 0.16, 0.23)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED


# Each body defines its outer sheet metal, roof and rear opening in local meters.
# Wheel centers and hinge mounts stay shared so fitted parts can carry over.
const BODIES := [
	{
		"sections": [[-2.24, 0.805, 0.785], [-2.10, 0.88, 0.84], [-1.72, 0.915, 0.885],
			[-0.91, 0.905, 0.91], [0.045, 0.895, 0.92], [0.98, 0.905, 0.93],
			[1.28, 0.925, 0.945], [1.93, 0.91, 0.92], [2.22, 0.85, 0.885]],
		"roof": [Vector3(0.637, 1.515, -0.30), Vector3(0.641, 1.50, 0.70)],
		"rear": Vector3(0.779, 0.945, 1.28),
	},
	{
		"sections": [[-2.10, 0.78, 0.785], [-1.98, 0.865, 0.83], [-1.62, 0.915, 0.885],
			[-0.91, 0.905, 0.91], [0.045, 0.895, 0.92], [0.98, 0.905, 0.93],
			[1.25, 0.915, 0.93], [1.88, 0.89, 0.905], [2.00, 0.84, 0.905]],
		"roof": [Vector3(0.657, 1.58, -0.42), Vector3(0.65, 1.55, 1.02)],
		"rear": Vector3(0.770, 0.911, 1.91),
	},
	{
		"sections": [[-2.27, 0.82, 0.845], [-2.17, 0.889, 0.875], [-1.70, 0.925, 0.895],
			[-0.91, 0.905, 0.91], [0.045, 0.895, 0.92], [0.98, 0.905, 0.93],
			[1.57, 0.922, 0.944], [2.12, 0.92, 0.943], [2.32, 0.868, 0.93]],
		"roof": [Vector3(0.664, 1.61, -0.37), Vector3(0.663, 1.605, 1.86)],
		"rear": Vector3(0.788, 0.931, 2.30),
	},
]
const SILL := 0.306
const WHEEL_AXLES := [-1.4, 1.43]
const ARCH_RADIUS := 0.46
const ARCH_HUB_HEIGHT := 0.31
const ARCH_RISE := 0.41
const HOOD_FRONT := -2.08
const HOOD_BACK := -0.916
const HOOD_HALF_WIDTH := 0.739
const WINDSHIELD_BASE := Vector3(0.775, 0.915, -0.89)


static func rear_bumper(style: int) -> float:
	return BODIES[style]["sections"].back()[0]


func build(root: Node3D, style: int, mechanical := true) -> void:
	var body := _node(root, "Chassis")
	_lower_body(body, style)
	_bumpers(body, style)
	_cabin(root, body, style)
	_interior(root, style)
	for key in DOORS:
		make_door(root, key, style)
	make_hood(root)
	make_tailgate(root, style)
	_gas_cap(root)
	var ids := ["FL_Wheel", "FR_Wheel", "RL_Wheel", "RR_Wheel"]
	for i in ids.size():
		var wheel := make_wheel(root, ids[i])
		wheel.position = Vector3(-0.82 if i % 2 == 0 else 0.82, 0.39, WHEEL_AXLES[i / 2])
	if mechanical:
		_engine_mounts(root)


func _station(z: float, style: int) -> Vector2:
	var rows: Array = BODIES[style]["sections"]
	for i in range(1, rows.size()):
		var b: Array = rows[i]
		if z <= b[0]:
			var a: Array = rows[i - 1]
			return Vector2(a[1], a[2]).lerp(Vector2(b[1], b[2]), clampf(inverse_lerp(a[0], b[0], z), 0.0, 1.0))
	return Vector2(rows.back()[1], rows.back()[2])


func _lower_body(body: Node3D, style: int) -> void:
	var rows: Array = BODIES[style]["sections"]
	var cuts: Array[float] = [HOOD_FRONT - 0.008, HOOD_BACK + 0.007, -0.902, 0.045, 0.979]
	for row: Array in rows:
		cuts.append(row[0])
	for axle in WHEEL_AXLES:
		for i in range(25):
			cuts.append(axle - cos(PI * i / 24.0) * ARCH_RADIUS)
	cuts.sort()
	var shell := _surface()
	var flanges := _surface()
	var tubs := _surface()
	for i in range(cuts.size() - 1):
		var za := cuts[i]
		var zb := cuts[i + 1]
		if is_equal_approx(za, zb):
			continue
		var a := _station(za, style)
		var b := _station(zb, style)
		var lower_a := _arch_bottom(za)
		var lower_b := _arch_bottom(zb)
		for side in [-1.0, 1.0]:
			var seam_a := Vector3(side * a.x, a.y - 0.055, za)
			var seam_b := Vector3(side * b.x, b.y - 0.055, zb)
			var top_a := Vector3(side * (a.x - 0.031), a.y, za)
			var top_b := Vector3(side * (b.x - 0.031), b.y, zb)
			if za < -0.902 or za >= 0.979:
				var low_a := Vector3(side * (a.x - 0.034), lower_a, za)
				var low_b := Vector3(side * (b.x - 0.034), lower_b, zb)
				_side_quad(shell, side, low_a, low_b, seam_b, seam_a)
				_side_quad(shell, side, seam_a, seam_b, top_b, top_a)
				if lower_a > SILL + 0.001 or lower_b > SILL + 0.001:
					var inner_a := Vector3(side * 0.495, low_a.y + 0.018, za)
					var inner_b := Vector3(side * 0.495, low_b.y + 0.018, zb)
					_side_quad(tubs, -side, low_a, low_b, inner_b, inner_a)
					_side_quad(tubs, side, Vector3(inner_a.x, 0.22, za), Vector3(inner_b.x, 0.22, zb), inner_b, inner_a)
			# Engine and cargo openings have a recessed metal return around their edges.
			if za < -0.902 or za >= 0.979:
				var inside_a := _opening_edge(za, style)
				var inside_b := _opening_edge(zb, style)
				_side_quad(shell, side, top_a, top_b, _side(inside_b, side), _side(inside_a, side))
				var drop := Vector3(0, -0.045, 0)
				_side_quad(flanges, side, _side(inside_a + drop, side), _side(inside_b + drop, side),
					_side(inside_b, side), _side(inside_a, side))
	var nose_z: float = rows.front()[0]
	var end_z: float = rows.back()[0]
	for z in [nose_z, end_z]:
		var at := _station(z, style)
		var face_top := _opening_edge(z, style).y
		var face := [Vector3(-at.x + 0.03, face_top, z), Vector3(at.x - 0.03, face_top, z),
			Vector3(at.x - 0.047, SILL, z), Vector3(-at.x + 0.047, SILL, z)]
		if z == nose_z:
			face.reverse()
		_quad(shell, face[0], face[1], face[2], face[3])
	var header_edge := _opening_edge(nose_z, style)
	var hood_edge := _opening_edge(HOOD_FRONT - 0.008, style)
	_quad(shell, _side(header_edge, -1), header_edge, hood_edge, _side(hood_edge, -1))
	_finish(shell, body, "BodyPaint", paint, true)
	_finish(tubs, body, "WheelWellLiners", rubber)
	_finish(flanges, body, "PanelReturns", rubber)
	for side in [-1.0, 1.0]:
		Shapes.box(body, "DoorSill", Vector3(0.09, 0.034, 1.88), Vector3(side * 0.811, 0.324, 0.037), trim)
		Shapes.box(body, "RockerPanel", Vector3(0.16, 0.106, 1.89), Vector3(side * 0.793, 0.258, 0.038), trim)
	Shapes.box(body, "Undertray", Vector3(1.32, 0.092, 3.76), Vector3(0, 0.185, 0.02), trim)


func _arch_bottom(z: float) -> float:
	for axle in WHEEL_AXLES:
		var offset: float = z - axle
		if absf(offset) < ARCH_RADIUS:
			return maxf(SILL, ARCH_HUB_HEIGHT + ARCH_RISE * sqrt(maxf(0, 1.0 - (offset / ARCH_RADIUS) ** 2)))
	return SILL


func _opening_edge(z: float, style: int) -> Vector3:
	var at := _station(z, style)
	if z < 0.0:
		var rise := clampf(inverse_lerp(HOOD_FRONT, HOOD_BACK, z), 0, 1)
		return Vector3(minf(at.x - 0.04, HOOD_HALF_WIDTH + 0.008), lerpf(0.813, 0.913, rise), z)
	var rear: Vector3 = BODIES[style]["rear"]
	var width := rear.x + 0.009
	if style == SEDAN:
		width = lerpf(0.784, 0.764, clampf(inverse_lerp(rear.z, rear_bumper(style), z), 0, 1))
	return Vector3(minf(width, at.x - 0.041), at.y - 0.021, z)


func _bumpers(body: Node3D, style: int) -> void:
	var rows: Array = BODIES[style]["sections"]
	var nose := Vector2(rows.front()[1], rows.front()[0])
	var rear := Vector2(rows.back()[1], rows.back()[0])
	var bumper_top: float = [0.475, 0.49, 0.54][style]
	var bumper_material := trim if style != WAGON else Shapes.material(Color("#454a48"), 0.12, 0.73)
	_skin(body, "FrontBumper", [[nose.y - 0.078, nose.x - 0.06, nose.x - 0.005, 0.285, bumper_top],
		[nose.y - 0.015, nose.x - 0.015, nose.x + 0.035, 0.25, bumper_top],
		[nose.y + 0.12, nose.x, nose.x + 0.049, 0.25, bumper_top - 0.012]], bumper_material)
	_skin(body, "RearBumper", [[rear.y - 0.11, rear.x - 0.01, rear.x + 0.041, 0.254, 0.47],
		[rear.y + 0.025, rear.x - 0.014, rear.x + 0.024, 0.26, 0.47],
		[rear.y + 0.078, rear.x - 0.053, rear.x, 0.29, 0.46]], bumper_material)
	var grille_width: float = [0.62, 0.43, 0.70][style]
	var lamp_y := 0.651 if style != WAGON else 0.689
	Shapes.box(body, "GrilleRecess", Vector3(grille_width, 0.166, 0.034), Vector3(0, lamp_y, nose.y - 0.018), trim)
	if style == HATCHBACK:
		for i in range(9):
			Shapes.box(body, "GrilleSlat", Vector3(0.014, 0.125, 0.012), Vector3(i * 0.044 - 0.176, lamp_y, nose.y - 0.039), alloy)
	else:
		for i in range(3 if style == WAGON else 5):
			Shapes.box(body, "GrilleSlat", Vector3(grille_width - 0.04, 0.012, 0.010),
				Vector3(0, lamp_y - 0.056 + i * (0.054 if style == WAGON else 0.028), nose.y - 0.04), alloy)
	Shapes.box(body, "FrontPlate", Vector3(0.295, 0.09, 0.013), Vector3(0, 0.384, nose.y - 0.085), alloy)
	var rear_lights := _node(body, "RearLightMount")
	rear_lights.position = Vector3(0, 0.704, rear.y)
	for side in [-1.0, 1.0]:
		var lamp_width: float = [0.285, 0.295, 0.253][style]
		var lamp_x: float = [0.50, 0.50, 0.533][style]
		var lamp_height: float = [0.123, 0.172, 0.149][style]
		Shapes.box(body, "HeadlightBezel", Vector3(lamp_width + 0.025, lamp_height + 0.025, 0.032),
			Vector3(side * lamp_x, lamp_y, nose.y - 0.012), trim)
		Shapes.box(body, "HeadlightLens", Vector3(lamp_width, lamp_height, 0.021),
			Vector3(side * lamp_x, lamp_y, nose.y - 0.033), headlamp)
		Shapes.box(body, "FrontIndicator", Vector3(0.093, lamp_height, 0.027),
			Vector3(side * (lamp_x + lamp_width * 0.5 + 0.052), lamp_y, nose.y - 0.016), amber)
		var brake_box := Vector3(0.246, 0.108, 0.034) if style == SEDAN else Vector3(0.147, 0.132, 0.034)
		var brake_x := 0.617 if style == SEDAN else 0.705
		Shapes.box(rear_lights, "BrakeLens", brake_box, Vector3(side * brake_x, 0.031, 0.024), tail)
		Shapes.box(rear_lights, "RearIndicator", Vector3(brake_box.x, 0.041, 0.031),
			Vector3(side * brake_x, -0.049, 0.022), amber)
	Shapes.box(body, "RearPlate", Vector3(0.32, 0.09, 0.015), Vector3(0, 0.636, rear.y + 0.014), alloy)
	Shapes.cylinder(body, "ExhaustTip", Vector3(0.60, 0.236, rear.y + 0.06), Vector3.BACK, 0.034, 0.13, alloy, 16)


func _cabin(root: Node3D, body: Node3D, style: int) -> void:
	var windows := _node(root, "Windows")
	var roof: Array = BODIES[style]["roof"]
	var front: Vector3 = roof[0]
	var back: Vector3 = roof[1]
	var rear: Vector3 = BODIES[style]["rear"]
	_skin(body, "RoofPaint", [[front.z, front.x - 0.025, front.x, front.y - 0.012, front.y + 0.023],
		[front.z + 0.14, front.x - 0.028, front.x + 0.004, front.y, front.y + 0.052],
		[back.z - 0.11, back.x - 0.028, back.x + 0.004, back.y + 0.005, back.y + 0.045],
		[back.z, back.x - 0.025, back.x, back.y - 0.013, back.y + 0.022]], paint)
	_glazing(windows, "Windscreen", [_side(WINDSHIELD_BASE, -1), WINDSHIELD_BASE, front, _side(front, -1)])
	if style == SEDAN:
		_glazing(windows, "RearScreen", [_side(rear, -1), rear, back, _side(back, -1)])
	for side in [-1.0, 1.0]:
		var roof_center := _roof_at(0.045, style)
		_frame(body, "FrontPillar", side, WINDSHIELD_BASE, front, 0.039)
		_frame(body, "CenterPillar", side, Vector3(0.828, 0.938, 0.045), roof_center, 0.051)
		_frame(body, "RoofGutter", side, front, back, 0.032)
		_frame(body, "RearPillar", side, back, rear, 0.057)
		var quarter_front := Vector3(0.839, 0.938, 0.978)
		var quarter_top := _rear_door_top(style)
		var quarter_back := rear - Vector3(0.005, -0.015, 0.038)
		var border := [_side(quarter_front, side), _side(quarter_back, side),
			_side(back.lerp(rear, 0.09), side), _side(quarter_top, side)]
		if style != SEDAN:
			_glazing(windows, "CargoQuarterGlass", border)
			_frame(body, "QuarterBelt", side, quarter_front, quarter_back, 0.036)
		else:
			_glazing(windows, "RearDoorQuarterGlass", border)
		_frame(body, "RearDoorJamb", side, Vector3(0.865, 0.915, 0.976), quarter_front, 0.042)
		var trim_line := WINDSHIELD_BASE.lerp(front, 0.18)
		var blade := Vector3(side * 0.48, trim_line.y + 0.006, trim_line.z - 0.013)
		Shapes.tube(body, "WiperBlade", Vector3(side * 0.09, blade.y, blade.z), blade, 0.008, rubber)
	if style == WAGON:
		for side in [-1.0, 1.0]:
			for z in [-0.17, 1.57]:
				Shapes.box(body, "RoofRailFoot", Vector3(0.065, 0.058, 0.107), Vector3(side * 0.55, 1.665, z), trim)
			Shapes.tube(body, "RoofRail", Vector3(side * 0.55, 1.708, -0.25), Vector3(side * 0.55, 1.708, 1.65), 0.023, trim)


func _frame(body: Node3D, title: String, side: float, start: Vector3, end: Vector3, width: float) -> void:
	var a := _side(start, side)
	var b := _side(end, side)
	var strip := Shapes.box(body, title, Vector3(width, width, a.distance_to(b) + 0.014), (a + b) / 2, paint)
	strip.basis = Basis.looking_at(b - a)
	strip.set_meta("body_paint", true)


func _roof_at(z: float, style: int) -> Vector3:
	var roof: Array = BODIES[style]["roof"]
	var front: Vector3 = roof[0]
	var back: Vector3 = roof[1]
	return front.lerp(back, inverse_lerp(front.z, back.z, z))


func _rear_door_top(style: int) -> Vector3:
	if style != SEDAN:
		return _roof_at(0.831, style)
	var back: Vector3 = BODIES[style]["roof"][1]
	var rear: Vector3 = BODIES[style]["rear"]
	return back.lerp(rear, 0.25)


func make_door(parent: Node3D, title: String, style := SEDAN) -> Node3D:
	var config: Array = DOORS[title]
	var side: float = config[0]
	var front: bool = config[1]
	var door := _node(parent, title)
	door.set_meta("body_style", style)
	door.position = Vector3(side * 0.82, 0.69, -0.92 if front else 0.055)
	var start := -0.892 if front else 0.055
	var end := 0.035 if front else 0.969
	var a := _station(start, style)
	var b := _station(end, style)
	var bottom_a := Vector3(a.x - 0.031, SILL + 0.007, start)
	var bottom_b := Vector3(b.x - 0.031, SILL + 0.007, end)
	var shoulder_a := Vector3(a.x, a.y - 0.055, start)
	var shoulder_b := Vector3(b.x, b.y - 0.055, end)
	var top_a := Vector3(a.x - 0.031, a.y, start)
	var top_b := Vector3(b.x - 0.031, b.y, end)
	var skin := _surface()
	for panel in [[bottom_a, bottom_b, shoulder_b, shoulder_a], [shoulder_a, shoulder_b, top_b, top_a]]:
		_side_quad(skin, side, _side(panel[0], side) - door.position, _side(panel[1], side) - door.position,
			_side(panel[2], side) - door.position, _side(panel[3], side) - door.position)
	var belt_a := Vector3(0.836, a.y - 0.004, start)
	var belt_b := Vector3(0.836, b.y - 0.004, end)
	_side_quad(skin, side, _side(top_a, side) - door.position, _side(top_b, side) - door.position,
		_side(belt_b, side) - door.position, _side(belt_a, side) - door.position)
	_finish(skin, door, "DoorSkin", paint, true)
	var bottom_front := belt_a + Vector3(0, 0.006, 0.020)
	var bottom_back := belt_b + Vector3(0, 0.006, -0.021)
	var top_front: Vector3 = BODIES[style]["roof"][0] if front else _roof_at(0.082, style)
	var top_back := _roof_at(0.011, style) if front else _rear_door_top(style)
	top_front += Vector3(0.016, -0.027, 0.006)
	top_back += Vector3(0.016, -0.027, -0.012)
	_glazing(door, "DoorGlass", [_side(bottom_front, side) - door.position, _side(bottom_back, side) - door.position,
		_side(top_back, side) - door.position, _side(top_front, side) - door.position])
	var inner_start := _side(Vector3(0.818, bottom_a.y, start + 0.009), side) - door.position
	var inner_end := _side(Vector3(0.818, bottom_b.y, end - 0.009), side) - door.position
	_plate(door, "DoorCard", [inner_start, inner_end, _side(belt_b, side) - door.position,
		_side(belt_a, side) - door.position], Vector3(-side * 0.032, 0, 0), fabric, false)
	Shapes.box(door, "ExteriorHandle", Vector3(0.029, 0.041, 0.117),
		Vector3(side * (b.x - 0.815), 0.13, end - door.position.z - 0.12), trim)
	Shapes.tube(door, "BeltSeal", _side(belt_a, side) - door.position, _side(belt_b, side) - door.position, 0.009, rubber)
	var molding := Shapes.box(door, "SideMolding", Vector3(0.026, 0.048 if style != WAGON else 0.094, end - start - 0.015),
		Vector3(side * ((a.x + b.x) * 0.5 - 0.824), -0.143, (start + end) / 2 - door.position.z), trim)
	molding.rotation.y = side * (b.x - a.x) / (end - start)
	if front:
		var mount := Vector3(side * 0.179, 0.312, 0.215)
		Shapes.tube(door, "MirrorMount", Vector3(side * 0.044, 0.245, 0.215), mount, 0.018, trim)
		var mirror := Shapes.box(door, "MirrorHousing", Vector3(0.144, 0.080, 0.092), mount, trim)
		mirror.rotation.y = side * 0.20
		Shapes.box(mirror, "MirrorGlass", Vector3(0.122, 0.058, 0.004), Vector3(0, 0, 0.047), alloy)
	return door


func make_hood(parent: Node3D) -> Node3D:
	var hinge := _node(parent, "HoodTargetHinge")
	hinge.position = Vector3(0, 0.921, -0.89)
	_skin(hinge, "Hood", [[-1.19, 0.707, 0.739, -0.124, -0.092],
		[-0.69, 0.709, 0.739, -0.076, -0.041], [-0.026, 0.709, 0.739, -0.033, 0.007]], paint)
	return hinge


func make_tailgate(parent: Node3D, style: int) -> Node3D:
	var hinge := _node(parent, "TrunkTargetHinge")
	hinge.set_meta("body_style", style)
	var rear: Vector3 = BODIES[style]["rear"]
	if style == SEDAN:
		hinge.position = Vector3(0, rear.y, rear.z + 0.01)
		var length := rear_bumper(style) - hinge.position.z
		_skin(hinge, "Trunk", [[0.0, 0.722, 0.775, -0.038, -0.005], [length - 0.21, 0.719, 0.767, -0.06, -0.022],
			[length - 0.018, 0.702, 0.752, -0.084, -0.058]], paint)
	else:
		var back: Vector3 = BODIES[style]["roof"][1]
		hinge.position = Vector3(0, back.y, back.z + 0.012)
		var gate := _node(hinge, "Trunk")
		var top := back - hinge.position + Vector3(-0.016, -0.021, 0.018)
		var bottom := rear - hinge.position + Vector3(-0.014, -0.007, 0.011)
		var belt := top.lerp(bottom, 0.69 if style == HATCHBACK else 0.74)
		_glazing(gate, "TailgateGlass", [_side(top, -1), top, belt, _side(belt, -1)])
		_plate(gate, "TailgatePaint", [_side(belt, -1), belt, bottom, _side(bottom, -1)], Vector3(0, -0.014, -0.028), paint, true)
		var handle := belt.lerp(bottom, 0.67)
		Shapes.box(gate, "TailgateHandle", Vector3(0.225, 0.032, 0.028), Vector3(0, handle.y, handle.z + 0.018), trim)
	return hinge


func _side(point: Vector3, side: float) -> Vector3:
	return Vector3(side * point.x, point.y, point.z)


func _side_quad(surface: SurfaceTool, side: float, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	if side < 0.0:
		_quad(surface, d, c, b, a)
	else:
		_quad(surface, a, b, c, d)


static func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	return surface


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
	var upholstery := Shapes.material([Color("#585246"), Color("#454a49"), Color("#5d5146")][style], 0.0, 0.95)
	Shapes.box(cabin, "Floor", Vector3(1.59, 0.08, 2.07), Vector3(0, 0.363, 0.14), fabric)
	_skin(cabin, "Dashboard", [[-0.85, 0.74, 0.77, 0.68, 0.918], [-0.62, 0.743, 0.768, 0.65, 0.884],
		[-0.56, 0.72, 0.743, 0.685, 0.852]], trim)
	for side in [-1.0, 1.0]:
		_skin(cabin, "SeatBase", [[-0.26, 0.22, 0.24, 0.46, 0.58], [0.01, 0.239, 0.255, 0.44, 0.625],
			[0.39, 0.19, 0.22, 0.46, 0.58]], upholstery).position.x = side * 0.40
		var seat := Shapes.box(cabin, "SeatBack", Vector3(0.44, 0.50, 0.12), Vector3(side * 0.40, 0.85, 0.35), upholstery)
		seat.rotation.x = 0.16
		Shapes.box(cabin, "Headrest", Vector3(0.23, 0.14, 0.096), Vector3(side * 0.40, 1.15, 0.41), upholstery)
		Shapes.box(cabin, "Seatbelt", Vector3(0.026, 0.39, 0.014), Vector3(side * 0.581, 0.89, 0.275), trim).rotation.z = side * 0.24
	Shapes.box(cabin, "RearBench", Vector3(1.38, 0.13, 0.47), Vector3(0, 0.52, 0.93), upholstery)
	Shapes.box(cabin, "RearBackrest", Vector3(1.40, 0.36, 0.105), Vector3(0, 0.73, 1.175), upholstery).rotation.x = 0.18
	var cargo_start := 1.25
	var cargo_end := rear_bumper(style) - 0.065
	Shapes.box(cabin, "CargoMat", Vector3(1.31, 0.043, cargo_end - cargo_start),
		Vector3(0, 0.50, (cargo_start + cargo_end) / 2), rubber)
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
		["Engine", Vector3(-0.07, 0.585, -1.45), Vector3(0.3268, 0.253, 0.3268), Vector3(2.8, 2.3, 2.2)],
		["Radiator", Vector3(0, 0.555, -1.905), Vector3(0.327, 0.253, 0.058), Vector3(3.1, 2.0, 2.8)],
		["Battery", Vector3(-0.568, 0.585, -1.36), Vector3(0.196, 0.276, 0.152), Vector3(1.18, 0.89, 1.12)],
	]
	for data in mounts:
		var part := Shapes.box(root, data[0], data[3], data[1], trim)
		part.rotation.y = PI if data[0] != "Battery" else PI * 0.5
		part.scale = data[2]
	Shapes.box(root, "RadiatorSupport", Vector3(1.37, 0.04, 0.105), Vector3(0, 0.757, -2.007), trim)
	Shapes.box(root, "Firewall", Vector3(1.52, 0.36, 0.06), Vector3(0, 0.626, -0.91), trim)
	for side in [-1.0, 1.0]:
		Shapes.cylinder(root, "StrutTop", Vector3(side * 0.64, 0.751, -1.67), Vector3.UP, 0.087, 0.093, trim)
		Shapes.cylinder(root, "StrutNut", Vector3(side * 0.64, 0.799, -1.67), Vector3.UP, 0.032, 0.026, alloy, 6)


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


func _skin(parent: Node3D, title: String, sections: Array, finish: Material) -> MeshInstance3D:
	var surface := _surface()
	for row in range(sections.size() - 1):
		var a := _profile(sections[row])
		var b := _profile(sections[row + 1])
		for i in a.size():
			var next := (i + 1) % a.size()
			_quad(surface, a[i], a[next], b[next], b[i])
	for row in [0, sections.size() - 1]:
		var points := _profile(sections[row])
		var center := (points[0] + points[4]) * 0.5
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			for vertex in ([center, b, a] if row == 0 else [center, a, b]):
				surface.add_vertex(vertex)
	return _finish(surface, parent, title, finish, finish == paint)


func _profile(row: Array) -> PackedVector3Array:
	var z: float = row[0]
	var crown: float = row[1]
	var shoulder: float = row[2]
	var bottom: float = row[3]
	var top: float = row[4]
	var bevel := minf(0.028, (top - bottom) * 0.25)
	return PackedVector3Array([Vector3(-crown, top, z), Vector3(crown, top, z),
		Vector3(shoulder, top - bevel, z), Vector3(shoulder, bottom + bevel, z),
		Vector3(shoulder - bevel, bottom, z), Vector3(-shoulder + bevel, bottom, z),
		Vector3(-shoulder, bottom + bevel, z), Vector3(-shoulder, top - bevel, z)])


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
	surface.generate_normals()
	surface.index()
	var instance := _mesh(parent, title, surface.commit(), finish)
	instance.set_meta("body_paint", body_paint)
	return instance
