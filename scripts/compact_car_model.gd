extends RefCounted

const Shapes := preload("res://scripts/prop_shapes.gd")
const Looks := preload("res://scripts/vehicle_looks.gd")
## Box pieces swapped for Blender parts of the same size (Sources/make_road_vehicles.py):
## name -> [part, faces the back of the car].
const PARTS := {
	"HeadlightLens": ["lens", false], "HeadlightBezel": ["lamp_bezel", false], "FrontIndicator": ["lens", false],
	"TailHousing": ["lamp_bezel", true], "BrakeLensLeft": ["lens", true], "BrakeLensRight": ["lens", true],
	"RearIndicator": ["lens", true], "ReverseHousing": ["lamp_bezel", true], "ReverseLensLeft": ["lens", true],
	"ReverseLensRight": ["lens", true], "GrilleSlat": ["grille_slat", false], "FrontPlate": ["number_plate", true],
	"RearPlate": ["number_plate", false], "MirrorHousing": ["mirror_housing", false], "ExteriorHandle": ["door_handle", false],
	"SeatBack": ["seat_back", false], "Headrest": ["headrest", false], "RearBench": ["bench", false],
	"RearBackrest": ["seat_back", false], "AirVent": ["air_vent", false], "Radio": ["radio", false], "Pedal": ["pedal", true],
}
const SEDAN := 0
const HATCHBACK := 1
const WAGON := 2
const DOORS := {"FL_Door": [-1, true], "FR_Door": [1, true], "RL_Door": [-1, false], "RR_Door": [1, false]}

var paint: StandardMaterial3D
var trim := Shapes.material(Color("#2f302d"), 0.06, 0.86)
var rubber := Shapes.material(Color("#2a2a28"), 0.0, 0.93)
var alloy := Shapes.material(Color("#7f827d"), 0.55, 0.58)
var glass: StandardMaterial3D
var headlamp := Shapes.material(Color("#d9d5bb"), 0.25, 0.29)
var amber := Shapes.material(Color("#b86c2b"), 0.22, 0.37)
var tail := Shapes.material(Color("#8f2824"), 0.16, 0.32)
var fabric := Shapes.material(Color("#514f47"), 0.0, 0.94)
var vinyl := Shapes.material(Color("#343637"), 0.0, 0.81)
var dial_ink := Shapes.material(Color("#d7d6c5"), 0.0, 0.78)


## How long it has stood in the sun: a little dust on cars still running, rust
## and bare primer on the wrecks.
var wear := 0.2


func _init(color := Color("#728b85"), age := 0.2) -> void:
	wear = age
	# Old single-stage paint: no metal flake, no clear coat, gone flat in the sun.
	paint = Shapes.material(color, 0.04, lerpf(0.5, 0.7, wear))
	Looks.age_paint(paint, wear)
	if wear > 0.5:
		paint.clearcoat_enabled = false
		paint.roughness = 0.8
		paint.metallic = 0.1
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
	_gas_cap(root, style)
	var ids := ["FL_Wheel", "FR_Wheel", "RL_Wheel", "RR_Wheel"]
	for i in ids.size():
		var wheel := make_wheel(root, ids[i])
		wheel.position = Vector3(-0.82 if i % 2 == 0 else 0.82, 0.39, WHEEL_AXLES[i / 2])
	if mechanical:
		_engine_mounts(root)
	dress(root)


func dress(root: Node) -> void:
	## Blender parts in place of the box-shaped lamps, grille, mirrors,
	## handles, plates, seats, vents and pedals; names and materials stay.
	for instance: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var piece: String = instance.get_meta("piece", instance.name)
		if PARTS.has(piece):
			Looks.reshape(instance, PARTS[piece][0], PARTS[piece][1])
			if piece == "AirVent":
				for slat in instance.get_children():
					slat.visible = false


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
	_panel(_finish(shell, body, "BodyPaint", paint, true), "body_%d_chassis" % style)
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
	# Rubbing strip and bumpers gone grey and dusty in the sun.
	var bumper_material := Shapes.material(Color("#3a3935") if style != WAGON else Color("#4a4c48"), 0.05, 0.9)
	var front_bumper := _skin(body, "FrontBumper", [[nose.y - 0.078, nose.x - 0.06, nose.x - 0.005, 0.285, bumper_top],
		[nose.y - 0.015, nose.x - 0.015, nose.x + 0.035, 0.25, bumper_top],
		[nose.y + 0.12, nose.x, nose.x + 0.049, 0.25, bumper_top - 0.012]], bumper_material)
	var rear_bumper_skin := _skin(body, "RearBumper", [[rear.y - 0.11, rear.x - 0.01, rear.x + 0.041, 0.254, 0.47],
		[rear.y + 0.025, rear.x - 0.014, rear.x + 0.024, 0.26, 0.47],
		[rear.y + 0.078, rear.x - 0.053, rear.x, 0.29, 0.46]], bumper_material)
	_panel(front_bumper, "body_%d_bumper_front" % style)
	_panel(rear_bumper_skin, "body_%d_bumper_rear" % style)
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
		var wide := style == SEDAN
		var lamp_center: float = side * (0.605 if wide else 0.69)
		var housing := Vector3(0.319 if wide else 0.156, 0.153, 0.032)
		Shapes.box(rear_lights, "TailHousing", housing, Vector3(lamp_center, 0, 0.018), trim)
		var brake_width := 0.205 if wide else 0.128
		Shapes.box(rear_lights, "BrakeLensLeft" if side < 0.0 else "BrakeLensRight", Vector3(brake_width, 0.069, 0.009),
			Vector3(lamp_center + (side * 0.045 if wide else 0.0), 0.030, 0.037), tail)
		Shapes.box(rear_lights, "RearIndicator", Vector3(brake_width, 0.041, 0.009),
			Vector3(lamp_center + (side * 0.045 if wide else 0.0), -0.036, 0.037), amber)
		var reverse_x: float = lamp_center - side * (0.109 if wide else 0.132)
		if not wide:
			Shapes.box(rear_lights, "ReverseHousing", Vector3(0.088, 0.062, 0.032),
				Vector3(reverse_x, -0.032, 0.018), trim)
		Shapes.box(rear_lights, "ReverseLensLeft" if side < 0.0 else "ReverseLensRight", Vector3(0.063, 0.041, 0.009),
			Vector3(reverse_x, -0.032, 0.037), headlamp)
	Shapes.box(body, "RearPlate", Vector3(0.32, 0.09, 0.015), Vector3(0, 0.636, rear.y + 0.014), alloy)
	Shapes.cylinder(body, "ExhaustTip", Vector3(0.60, 0.236, rear.y + 0.06), Vector3.BACK, 0.034, 0.13, alloy, 16)


func _cabin(root: Node3D, body: Node3D, style: int) -> void:
	var windows := _node(root, "Windows")
	var roof: Array = BODIES[style]["roof"]
	var front: Vector3 = roof[0]
	var back: Vector3 = roof[1]
	var rear: Vector3 = BODIES[style]["rear"]
	var roof_skin := _skin(body, "RoofPaint", [[front.z, front.x - 0.025, front.x, front.y - 0.012, front.y + 0.023],
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
	# The roof and pillars as one Blender shell; the pillar boxes stay, hidden.
	if _panel(roof_skin, "body_%d_cabin" % style):
		for child in body.get_children():
			if child is MeshInstance3D and String(child.get_meta("piece", "")) in ["FrontPillar", "CenterPillar", "RoofGutter", "RearPillar", "RearDoorJamb", "QuarterBelt"]:
				child.visible = false
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
	_panel(_finish(skin, door, "DoorSkin", paint, true), "body_%d_door_%s" % [style, title.left(2)], door.position.y)
	var bottom_front := belt_a + Vector3(0, 0.006, 0.020)
	var bottom_back := belt_b + Vector3(0, 0.006, -0.021)
	var top_front: Vector3 = BODIES[style]["roof"][0] if front else _roof_at(0.082, style)
	var top_back := _roof_at(0.011, style) if front else _rear_door_top(style)
	top_front += Vector3(0.009, -0.044, 0.014)
	top_back += Vector3(0.009, -0.044, -0.015)
	_glazing(door, "DoorGlass", [_side(bottom_front, side) - door.position, _side(bottom_back, side) - door.position,
		_side(top_back, side) - door.position, _side(top_front, side) - door.position])
	var inner_start := _side(Vector3(0.818, bottom_a.y, start + 0.009), side) - door.position
	var inner_end := _side(Vector3(0.818, bottom_b.y, end - 0.009), side) - door.position
	_plate(door, "DoorCard", [inner_start, inner_end, _side(belt_b, side) - door.position,
		_side(belt_a, side) - door.position], Vector3(-side * 0.032, 0, 0), fabric, false)
	var midpoint := (start + end) * 0.5 - door.position.z
	Shapes.box(door, "Armrest", Vector3(0.054, 0.051, 0.35), Vector3(-side * 0.063, 0.046, midpoint), vinyl)
	Shapes.box(door, "DoorPocket", Vector3(0.037, 0.113, 0.34), Vector3(-side * 0.053, -0.242, midpoint), vinyl)
	Shapes.box(door, "InsideHandleBezel", Vector3(0.025, 0.057, 0.104),
		Vector3(-side * 0.049, 0.123, midpoint - 0.187), vinyl)
	Shapes.box(door, "InsideRelease", Vector3(0.013, 0.014, 0.066),
		Vector3(-side * 0.066, 0.123, midpoint - 0.187), alloy)
	Shapes.cylinder(door, "WindowCrank", Vector3(-side * 0.054, 0.073, midpoint - 0.052), Vector3.RIGHT, 0.021, 0.021, trim, 12)
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
	dress(door)
	return door


func make_hood(parent: Node3D) -> Node3D:
	var hinge := _node(parent, "HoodTargetHinge")
	hinge.position = Vector3(0, 0.921, -0.89)
	_panel(_skin(hinge, "Hood", [[-1.19, 0.707, 0.739, -0.124, -0.092],
		[-0.69, 0.709, 0.739, -0.076, -0.041], [-0.026, 0.709, 0.739, -0.033, 0.007]], paint), "body_hood", hinge.position.y)
	return hinge


func make_tailgate(parent: Node3D, style: int) -> Node3D:
	var hinge := _node(parent, "TrunkTargetHinge")
	hinge.set_meta("body_style", style)
	var rear: Vector3 = BODIES[style]["rear"]
	if style == SEDAN:
		hinge.position = Vector3(0, rear.y, rear.z + 0.01)
		var length := rear_bumper(style) - hinge.position.z
		_panel(_skin(hinge, "Trunk", [[0.0, 0.722, 0.775, -0.038, -0.005], [length - 0.21, 0.719, 0.767, -0.06, -0.022],
			[length - 0.018, 0.702, 0.752, -0.084, -0.058]], paint), "body_%d_trunk" % style, hinge.position.y)
	else:
		var back: Vector3 = BODIES[style]["roof"][1]
		hinge.position = Vector3(0, back.y, back.z + 0.012)
		var gate := _node(hinge, "Trunk")
		var top := back - hinge.position + Vector3(-0.016, -0.021, 0.018)
		var bottom := rear - hinge.position + Vector3(-0.018, 0.004, 0.025)
		var belt := top.lerp(bottom, 0.69 if style == HATCHBACK else 0.74)
		_glazing(gate, "TailgateGlass", [_side(top, -1), top, belt, _side(belt, -1)])
		for side in [-1.0, 1.0]:
			_frame(gate, "LiftgateFrame", side, top, belt, 0.036)
		_plate(gate, "TailgatePaint", [_side(belt, -1), belt, bottom, _side(bottom, -1)], Vector3(0, -0.014, -0.028), paint, true)
		var gate_panel := gate.get_node("TailgatePaint") as MeshInstance3D
		if _panel(gate_panel, "body_%d_tailgate" % style, hinge.position.y):
			# Its own frame comes with the Blender gate.
			for child in gate.get_children():
				if child is MeshInstance3D and String(child.get_meta("piece", "")) == "LiftgateFrame":
					child.visible = false
		var handle := belt.lerp(bottom, 0.67)
		Shapes.box(gate, "TailgateHandle", Vector3(0.225, 0.032, 0.028), Vector3(0, handle.y, handle.z + 0.018), trim)
	return hinge


func _panel(instance: MeshInstance3D, title: String, lift := 0.0) -> bool:
	## Give a painted panel its Blender shell (Sources/make_car_bodies.py): the
	## node, its material, hinge and collider stay; only the mesh changes.
	if instance == null or not Looks.has_panel(title):
		return false
	instance.mesh = Looks.panel(title, lift)
	return true


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


func _gas_cap(root: Node3D, style: int) -> void:
	var panel_z := 1.307
	var panel_x := _station(panel_z, style).x + 0.001
	var hinge := _node(root, "GasCapTargetHinge")
	hinge.position = Vector3(panel_x, 0.823, panel_z - 0.064)
	var filler := _node(root, "FuelFiller")
	filler.position = Vector3(panel_x, hinge.position.y, panel_z)
	Shapes.cylinder(root, "FillerSurround", filler.position, Vector3.RIGHT, 0.064, 0.019, trim, 24)
	Shapes.cylinder(root, "FillerNeck", filler.position + Vector3.RIGHT * 0.011, Vector3.RIGHT, 0.034, 0.016, alloy, 20)
	var lid := Shapes.cylinder(hinge, "gascap", Vector3(0.022, 0, 0.064), Vector3.RIGHT, 0.061, 0.013, paint, 24)
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
	_cockpit(cabin, style)
	var roof: Array = BODIES[style]["roof"]
	var headliner_start: Vector3 = roof[0]
	var headliner_end: Vector3 = roof[1]
	var liner := Shapes.material(Color("#a29b89"), 0.0, 0.96)
	_skin(cabin, "Headliner", [[headliner_start.z + 0.035, 0.57, 0.61, headliner_start.y - 0.019, headliner_start.y + 0.004],
		[headliner_end.z - 0.042, 0.57, 0.61, headliner_end.y - 0.019, headliner_end.y + 0.004]], liner)
	for side in [-1.0, 1.0]:
		Shapes.box(cabin, "SunVisor", Vector3(0.40, 0.022, 0.13),
			Vector3(side * 0.32, headliner_start.y - 0.041, headliner_start.z + 0.065), liner)
	var mirror := Shapes.box(cabin, "RearviewMirror", Vector3(0.212, 0.071, 0.04),
		Vector3(0, headliner_start.y - 0.162, headliner_start.z - 0.13), vinyl)
	Shapes.box(mirror, "MirrorGlass", Vector3(0.184, 0.05, 0.003), Vector3(0, 0, 0.022), alloy)
	Shapes.tube(cabin, "MirrorStem", mirror.position + Vector3(0, 0.019, -0.012),
		Vector3(0, headliner_start.y - 0.04, headliner_start.z + 0.054), 0.014, trim)
	if style == SEDAN:
		Shapes.box(cabin, "ParcelShelf", Vector3(1.31, 0.04, 0.17), Vector3(0, 0.86, 1.25), fabric)
	else:
		for side in [-1.0, 1.0]:
			Shapes.box(cabin, "CargoWheelTub", Vector3(0.155, 0.248, 0.62),
				Vector3(side * 0.681, 0.631, 1.45), vinyl)


func _cockpit(cabin: Node3D, style: int) -> void:
	var cluster := Shapes.box(cabin, "InstrumentBinnacle", Vector3(0.343, 0.151, 0.188),
		Vector3(-0.411, 0.939, -0.655), vinyl)
	cluster.rotation.x = -0.17
	_dial(cluster, "SpeedNeedle", Vector3(-0.084, 0.0, 0.099), 0.055)
	_dial(cluster, "RpmNeedle", Vector3(0.050, 0.0, 0.099), 0.046)
	_dial(cluster, "FuelNeedle", Vector3(0.135, -0.002, 0.099), 0.024)
	var wheel := _node(cabin, "Steerwheel")
	wheel.position = Vector3(-0.416, 0.906, -0.393)
	wheel.rotation.x = 1.12
	var steering := MeshInstance3D.new()
	steering.name = "SteeringRim"
	steering.mesh = Looks.mesh("steering_wheel", wear)
	wheel.add_child(steering)
	Shapes.tube(cabin, "SteeringColumn", wheel.position - Vector3(0, 0.015, 0.018),
		Vector3(-0.416, 0.809, -0.585), 0.047, vinyl)
	for x in [-0.68, -0.11, 0.051, 0.655]:
		_vent(cabin, x)
	var radio := Shapes.box(cabin, "Radio", Vector3(0.252, 0.076, 0.036), Vector3(-0.021, 0.796, -0.552), vinyl)
	Shapes.box(radio, "CassetteSlot", Vector3(0.112, 0.013, 0.006), Vector3(0, 0.012, 0.021), rubber)
	for x in [-0.095, 0.095]:
		Shapes.cylinder(radio, "RadioKnob", Vector3(x, 0, 0.024), Vector3.BACK, 0.012, 0.015, alloy, 12)
	Shapes.box(cabin, "GloveBox", Vector3(0.389, 0.128, 0.028), Vector3(0.39, 0.77, -0.547), vinyl)
	Shapes.box(cabin, "GloveBoxLatch", Vector3(0.065, 0.017, 0.012), Vector3(0.39, 0.801, -0.526), trim)
	Shapes.box(cabin, "TransmissionTunnel", Vector3(0.233, 0.112, 1.16), Vector3(0, 0.454, -0.008), vinyl)
	Shapes.box(cabin, "ShiftBoot", Vector3(0.113, 0.059, 0.119), Vector3(0.005, 0.523, -0.254), rubber)
	Shapes.tube(cabin, "GearLever", Vector3(0.005, 0.545, -0.25), Vector3(0.018, 0.671, -0.22), 0.012, alloy)
	Shapes.box(cabin, "GearKnob", Vector3(0.047, 0.039, 0.045), Vector3(0.018, 0.679, -0.22), vinyl)
	Shapes.tube(cabin, "Handbrake", Vector3(0.038, 0.505, 0.25), Vector3(0.038, 0.553, -0.011), 0.024, rubber)
	for x in [-0.54, -0.43, -0.31]:
		var width := 0.032 if x > -0.4 else 0.062
		Shapes.box(cabin, "Pedal", Vector3(width, 0.074, 0.019), Vector3(x, 0.491, -0.629), rubber).rotation.x = -0.21
	var inlay := Shapes.material([Color("#514f47"), Color("#3e474b"), Color("#655748")][style], 0.0, 0.75)
	Shapes.box(cabin, "DashTrim", Vector3(0.412, 0.016, 0.013), Vector3(0.39, 0.846, -0.563), inlay)


func _dial(cluster: Node3D, title: String, center: Vector3, radius: float) -> void:
	Shapes.cylinder(cluster, "DialBezel", center, Vector3.BACK, radius, 0.016, alloy, 28)
	Shapes.cylinder(cluster, "DialFace", center + Vector3.BACK * 0.009, Vector3.BACK, radius * 0.91, 0.008, rubber, 28)
	var markings := _surface()
	for i in range(11):
		var angle := lerpf(-2.32, 2.32, i / 10.0)
		var direction := Vector3(-sin(angle), cos(angle), 0)
		var across := Vector3(direction.y, -direction.x, 0) * radius * 0.023
		var outside := center + direction * radius * 0.81 + Vector3.BACK * 0.016
		var inside := outside - direction * radius * (0.16 if i % 5 == 0 else 0.088)
		_quad(markings, outside - across, inside - across, inside + across, outside + across)
	_finish(markings, cluster, "DialMarkings", dial_ink)
	var pivot := _node(cluster, title)
	pivot.position = center + Vector3.BACK * 0.020
	pivot.rotation.z = 2.32
	Shapes.box(pivot, "Needle", Vector3(radius * 0.051, radius * 0.73, 0.003),
		Vector3(0, radius * 0.30, 0), amber)
	Shapes.cylinder(pivot, "NeedleHub", Vector3.ZERO, Vector3.BACK, radius * 0.09, 0.006, vinyl, 12)


func _vent(cabin: Node3D, x: float) -> void:
	var vent := Shapes.box(cabin, "AirVent", Vector3(0.104, 0.054, 0.021), Vector3(x, 0.85, -0.565), rubber)
	for y in [-0.014, 0.0, 0.014]:
		Shapes.box(vent, "VentSlat", Vector3(0.086, 0.004, 0.01), Vector3(0, y, 0.012), vinyl)


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
	## Tyre, tread, pressed-steel rim, hubcap and nuts from Blender; the outer
	## face looks out from the car on either side.
	var wheel := _node(parent, title)
	var tire := MeshInstance3D.new()
	tire.name = "Tire"
	tire.mesh = Looks.mesh("car_wheel", wear)
	wheel.add_child(tire)
	if title.begins_with("FL") or title.begins_with("RL"):
		tire.rotation.y = PI
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
	var built := surface.commit()
	# Painted panels and bumpers shade smoothly across their facets.
	if body_paint or title.ends_with("Bumper") or title in ["Dashboard", "SeatBase", "Headliner"]:
		# Height of this panel's origin above the car's, for where grime gathers.
		var lift := 0.0
		var node: Node = parent
		for i in 2:
			if node is Node3D and node.name != "Chassis" and node.name != "Interior":
				lift += (node as Node3D).position.y
			node = node.get_parent() if node else null
			if node == null or not (node.name in DOORS or String(node.name).ends_with("Hinge")):
				break
		built = Looks.smooth(built, 0.55, lift)
	var instance := _mesh(parent, title, built, finish)
	instance.set_meta("body_paint", body_paint)
	return instance
