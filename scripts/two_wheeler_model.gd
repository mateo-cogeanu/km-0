extends RefCounted

const S := preload("res://scripts/prop_shapes.gd")
const TIRE_RADIUS := 0.34
const FRONT := Vector3(0, 0.34, -0.84)
const REAR := Vector3(0, 0.34, 0.84)
const HEAD := Vector3(0, 0.98, -0.52)
const CRANK := Vector3(0, 0.35, 0.06)


static func build(body: Node3D, front_wheel: Node3D, rear_wheel: Node3D, motorized: bool) -> Dictionary:
	var paint := S.material(Color("#a94e36") if motorized else Color("#366d63"), 0.32, 0.39)
	paint.clearcoat_enabled = true
	paint.clearcoat_roughness = 0.42
	var alloy := S.material(Color("#a0a6a2"), 0.75, 0.34)
	var steel := S.material(Color("#4a504e"), 0.58, 0.47)
	var rubber := S.material(Color("#242524"), 0.0, 0.93)
	var leather := S.material(Color("#3c3029") if motorized else Color("#30312d"), 0.0, 0.82)
	var red := S.material(Color("#9e3325"), 0.08, 0.27)
	var frame := Node3D.new()
	frame.name = "MotorcycleFrame" if motorized else "BicycleFrame"
	body.add_child(frame)
	var fork := Node3D.new()
	fork.name = "SteeringAssembly"
	fork.position = FRONT
	body.add_child(fork)
	_build_fork(fork, motorized, alloy, steel, rubber)
	_wheel(front_wheel, motorized, true, alloy, steel, rubber)
	_wheel(rear_wheel, motorized, false, alloy, steel, rubber)
	var pedals: Node3D
	if motorized:
		_build_motorcycle(frame, fork, paint, alloy, steel, rubber, leather, red)
	else:
		pedals = _build_bicycle(frame, paint, alloy, steel, rubber, leather, red)
	return {"fork": fork, "pedals": pedals}


static func _build_fork(fork: Node3D, motorized: bool, alloy: Material, steel: Material, rubber: Material) -> void:
	var top := HEAD - FRONT
	var width := 0.115 if motorized else 0.068
	for side in [-1.0, 1.0]:
		var offset := Vector3(side * width, 0, 0)
		var knee := top * 0.43 + offset
		S.tube(fork, "ForkLower", offset, knee, 0.042 if motorized else 0.021, steel)
		S.tube(fork, "ForkStanchion", knee, top + offset, 0.025 if motorized else 0.014, alloy)
		_axle(fork, "AxleNut", offset, 0.025, 0.025, alloy, 6)
		var grip := top + Vector3(side * 0.29, 0.105, 0.09)
		var rise := top + Vector3(side * 0.14, 0.082, 0.021)
		S.tube(fork, "BarRise", top, rise, 0.014, alloy)
		S.tube(fork, "Handlebar", rise, grip, 0.014, alloy)
		_axle(fork, "Grip", grip, 0.023 if motorized else 0.018, 0.115, rubber)
		for ring in range(6):
			_axle(fork, "GripRib", grip + Vector3(side * (ring - 2.5) * 0.015, 0, 0),
				0.024 if motorized else 0.019, 0.003, rubber)
		_axle(fork, "BarEnd", grip + Vector3(side * 0.06, 0, 0), 0.02, 0.009, steel)
		S.tube(fork, "BrakeLever", grip + Vector3(-side * 0.06, 0, -0.02),
			grip + Vector3(side * 0.043, -0.013, -0.049), 0.006, alloy)
		S.tube(fork, "BrakeLine", rise, knee + Vector3(0, 0, 0.036), 0.004, rubber)
	S.box(fork, "ForkCrown", Vector3(width * 2.5, 0.045, 0.073), top * 0.81, steel)


static func _build_bicycle(frame: Node3D, paint: Material, alloy: Material, steel: Material,
		rubber: Material, leather: Material, red: Material) -> Node3D:
	var seat_joint := Vector3(0, 0.81, 0.33)
	_axle(frame, "BottomBracket", CRANK, 0.036, 0.13, steel)
	S.tube(frame, "TopTube", HEAD + Vector3(0, -0.055, 0.01), seat_joint, 0.021, paint)
	S.tube(frame, "DownTube", HEAD + Vector3(0, -0.108, -0.02), CRANK, 0.028, paint)
	S.tube(frame, "SeatTube", CRANK, seat_joint, 0.024, paint)
	S.tube(frame, "SeatPost", seat_joint, Vector3(0, 0.92, 0.36), 0.015, alloy)
	_loft(frame, "Saddle", [[0.19, 0.945, 0.023, 0.018], [0.27, 0.953, 0.039, 0.021],
		[0.40, 0.954, 0.089, 0.027], [0.49, 0.947, 0.065, 0.021]], leather)
	for side in [-1.0, 1.0]:
		var dropout := REAR + Vector3(side * 0.063, 0, 0)
		S.tube(frame, "SeatStay", seat_joint + Vector3(side * 0.026, 0, 0), dropout, 0.012, paint)
		S.tube(frame, "ChainStay", CRANK + Vector3(side * 0.049, 0, 0), dropout, 0.015, paint)
		_axle(frame, "Dropout", dropout, 0.024, 0.014, steel)
		S.tube(frame, "RackStay", dropout, Vector3(side * 0.11, 0.75, 0.98), 0.009, steel)
		S.tube(frame, "RackRail", Vector3(side * 0.11, 0.75, 0.60), Vector3(side * 0.11, 0.75, 1.03), 0.01, steel)
	for z in [0.62, 0.73, 0.86, 1.02]:
		S.tube(frame, "RackCrossbar", Vector3(-0.11, 0.75, z), Vector3(0.11, 0.75, z), 0.008, alloy)
	S.box(frame, "RearReflector", Vector3(0.095, 0.035, 0.013), Vector3(0, 0.73, 1.045), red)

	var crank := Node3D.new()
	crank.name = "PedalAssembly"
	crank.position = CRANK
	frame.add_child(crank)
	_axle(crank, "Chainring", Vector3(0.088, 0, 0), 0.096, 0.011, steel, 32)
	_axle(crank, "ChainringFace", Vector3(0.095, 0, 0), 0.073, 0.005, alloy)
	for side in [-1.0, 1.0]:
		var at := Vector3(side * 0.14, side * 0.145, 0)
		S.tube(crank, "CrankArm", Vector3(side * 0.105, 0, 0), at, 0.017, alloy)
		S.box(crank, "PedalBody", Vector3(0.095, 0.024, 0.074), at, rubber)
		for z in [-0.037, 0.037]:
			S.box(crank, "PedalCage", Vector3(0.10, 0.018, 0.008), at + Vector3(0, 0.003, z), alloy)
	_chain(frame, CRANK, REAR, 0.091, 0.094, 0.047, steel)
	return crank


static func _build_motorcycle(frame: Node3D, fork: Node3D, paint: Material, alloy: Material, steel: Material,
		rubber: Material, leather: Material, red: Material) -> void:
	var ivory := S.material(Color("#cec2a0"), 0.18, 0.42)
	var glass := S.material(Color("#dfd5ac"), 0.28, 0.20)
	for side in [-1.0, 1.0]:
		var offset := Vector3(side * 0.11, 0, 0)
		var foot := Vector3(0, 0.25, -0.22) + offset
		var pivot := Vector3(0, 0.41, 0.30) + offset
		S.tube(frame, "DownTube", HEAD + offset * 0.72, foot, 0.033, steel)
		S.tube(frame, "EngineCradle", foot, pivot + Vector3(0, -0.09, 0), 0.028, steel)
		S.tube(frame, "SeatRail", Vector3(0, 0.80, 0.28) + offset, Vector3(0, 0.77, 0.82) + offset, 0.023, steel)
		S.tube(frame, "SeatMount", Vector3(side * 0.09, 0.78, 0.61), Vector3(side * 0.10, 0.91, 0.59), 0.015, steel)
		S.tube(frame, "Swingarm", pivot, REAR + offset, 0.029, steel)
		_axle(frame, "SwingarmBolt", pivot + Vector3(side * 0.026, 0, 0), 0.023, 0.012, alloy, 6)
		_coil_shock(frame, REAR + offset + Vector3(0, 0, -0.11), Vector3(0, 0.77, 0.56) + offset, alloy, steel)
		_axle(frame, "FootPeg", Vector3(side * 0.23, 0.34, 0.18), 0.021, 0.13, rubber)
		S.box(frame, "TankBadge", Vector3(0.01, 0.036, 0.13), Vector3(side * 0.177, 0.876, -0.245), ivory).rotation.y = side * 0.13
	_loft(frame, "PressedFuelTank", [[-0.58, 0.835, 0.071, 0.062], [-0.49, 0.861, 0.139, 0.115],
		[-0.32, 0.871, 0.18, 0.132], [-0.12, 0.842, 0.171, 0.102], [0.05, 0.803, 0.105, 0.058]], paint)
	S.cylinder(frame, "FuelCapGasket", Vector3(0, 0.999, -0.32), Vector3.UP, 0.058, 0.015, rubber, 24)
	S.cylinder(frame, "FuelCap", Vector3(0, 1.009, -0.32), Vector3.UP, 0.049, 0.016, alloy, 24)
	_loft(frame, "StitchedBenchSeat", [[0.00, 0.901, 0.080, 0.030], [0.12, 0.928, 0.134, 0.046],
		[0.38, 0.933, 0.150, 0.044], [0.67, 0.938, 0.14, 0.042], [0.79, 0.933, 0.076, 0.030]], leather)
	_loft(frame, "SideCovers", [[0.12, 0.816, 0.091, 0.035], [0.27, 0.825, 0.124, 0.069],
		[0.43, 0.83, 0.112, 0.064], [0.56, 0.841, 0.032, 0.037]], paint)
	for side in [-1.0, 1.0]:
		S.tube(frame, "SeatPiping", Vector3(side * 0.13, 0.924, 0.18), Vector3(side * 0.14, 0.929, 0.65), 0.004, steel)
	_fender(frame, REAR, 0.13, -0.86, 1.05, paint)
	_fender(fork, Vector3.ZERO, 0.11, -0.97, 0.87, paint)
	var exhaust := [Vector3(0.20, 0.45, -0.18), Vector3(0.23, 0.29, -0.08),
		Vector3(0.26, 0.27, 0.28), Vector3(0.26, 0.33, 0.95)]
	for i in range(exhaust.size() - 1):
		S.tube(frame, "ExhaustHeader", exhaust[i], exhaust[i + 1], 0.025, alloy)
		S.cylinder(frame, "PipeBend", exhaust[i], Vector3.RIGHT, 0.025, 0.046, alloy)
	S.cylinder(frame, "Muffler", Vector3(0.26, 0.323, 0.80), Vector3.BACK, 0.054, 0.53, steel, 24)
	S.cylinder(frame, "MufflerRim", Vector3(0.26, 0.323, 1.07), Vector3.BACK, 0.049, 0.025, alloy, 24)
	S.cylinder(frame, "ExhaustOutlet", Vector3(0.26, 0.323, 1.084), Vector3.BACK, 0.030, 0.006, rubber, 24)
	_chain(frame, Vector3(0, 0.38, 0.2), REAR, -0.122, 0.066, 0.104, steel)
	S.box(frame, "TailLightHousing", Vector3(0.17, 0.077, 0.059), Vector3(0, 0.73, 1.015), rubber)
	S.box(frame, "TailLightLens", Vector3(0.145, 0.055, 0.014), Vector3(0, 0.73, 1.050), red)
	var lamp := Vector3(0, 0.535, 0.12)
	S.cylinder(fork, "HeadlampBucket", lamp, Vector3.FORWARD, 0.088, 0.113, steel, 28)
	S.cylinder(fork, "HeadlampBezel", lamp + Vector3.FORWARD * 0.058, Vector3.FORWARD, 0.090, 0.018, alloy, 28)
	S.cylinder(fork, "HeadlampGlass", lamp + Vector3.FORWARD * 0.069, Vector3.FORWARD, 0.077, 0.012, glass, 28)
	for x in [-0.064, 0.064]:
		S.cylinder(fork, "GaugeHousing", Vector3(x, 0.688, 0.26), Vector3.UP, 0.051, 0.048, steel, 24)
		S.cylinder(fork, "GaugeBezel", Vector3(x, 0.714, 0.26), Vector3.UP, 0.049, 0.008, alloy, 24)
		S.cylinder(fork, "GaugeFace", Vector3(x, 0.720, 0.26), Vector3.UP, 0.042, 0.004, rubber, 24)
		S.box(fork, "GaugeNeedle", Vector3(0.003, 0.004, 0.025), Vector3(x, 0.724, 0.255), ivory).rotation.y = -0.55


static func _wheel(parent: Node3D, motorized: bool, front: bool, alloy: Material, steel: Material, rubber: Material) -> void:
	var half := 0.075 if motorized else 0.027
	var bead := 0.258 if motorized else 0.298
	_ring(parent, "PneumaticTire", [Vector2(-half * 0.70, bead), Vector2(-half, bead + 0.022),
		Vector2(-half * 0.95, 0.321), Vector2(-half * 0.52, 0.337), Vector2(0, TIRE_RADIUS),
		Vector2(half * 0.52, 0.337), Vector2(half * 0.95, 0.321), Vector2(half, bead + 0.022),
		Vector2(half * 0.70, bead)], rubber)
	var rim := half * 0.73
	_ring(parent, "Rim", [Vector2(-rim, bead - 0.018), Vector2(-rim, bead + 0.004),
		Vector2(-rim * 0.62, bead), Vector2(rim * 0.62, bead), Vector2(rim, bead + 0.004),
		Vector2(rim, bead - 0.018)], alloy)
	_axle(parent, "Hub", Vector3.ZERO, 0.059 if motorized else 0.031, half * 1.9 + 0.026, steel)
	var spokes := 24 if motorized else 28
	for i in range(spokes):
		var angle := TAU * i / spokes
		var side := -1.0 if i % 2 == 0 else 1.0
		var edge := Vector3(side * rim * 0.48, cos(angle) * (bead - 0.012), sin(angle) * (bead - 0.012))
		var origin := Vector3(side * half * 0.86, cos(angle + side * 0.47) * 0.042, sin(angle + side * 0.47) * 0.042)
		S.tube(parent, "LacedSpoke", origin, edge, 0.0042 if motorized else 0.0027, alloy)
	var disc_x := -half - 0.011
	var disc_radius := 0.129 if motorized else 0.078
	_ring(parent, "BrakeRotor", [Vector2(disc_x - 0.004, disc_radius * 0.64), Vector2(disc_x + 0.004, disc_radius * 0.64),
		Vector2(disc_x + 0.004, disc_radius), Vector2(disc_x - 0.004, disc_radius)], alloy)
	for i in range(6):
		var angle := TAU * i / 6
		_axle(parent, "RotorBolt", Vector3(disc_x - 0.005, cos(angle) * 0.062, sin(angle) * 0.062), 0.006, 0.008, steel, 6)
	if not front:
		var sprocket := 0.103 if motorized else 0.047
		var sprocket_side := -1.0 if motorized else 1.0
		_axle(parent, "RearSprocket", Vector3(sprocket_side * (half + 0.036), 0, 0), sprocket, 0.012, steel, 32)
	_tread(parent, half, motorized, rubber)


static func _tread(parent: Node3D, half: float, motorized: bool, rubber: Material) -> void:
	var tread := SurfaceTool.new()
	tread.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(48 if motorized else 36):
		var angle := TAU * i / (48 if motorized else 36)
		for side in [-1.0, 1.0]:
			var pivot: float = angle + side * 0.012
			var a := _polar(half * side * 0.20, 0.3398, pivot)
			var b := _polar(half * side * 0.76, 0.3345, pivot + 0.049)
			var c := _polar(half * side * 0.76, 0.3345, pivot + 0.082)
			var d := _polar(half * side * 0.20, 0.3398, pivot + 0.031)
			if side > 0:
				_quad(tread, a, b, c, d)
			else:
				_quad(tread, d, c, b, a)
	var compound := rubber.duplicate() as StandardMaterial3D
	compound.albedo_color = Color("#30302e")
	_finish(tread, parent, "TireTread", compound)


static func _polar(x: float, radius: float, angle: float) -> Vector3:
	return Vector3(x, cos(angle) * radius, sin(angle) * radius)


static func _ring(parent: Node3D, title: String, profile: Array[Vector2], finish: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in profile.size():
		var a := profile[row]
		var b := profile[(row + 1) % profile.size()]
		for i in range(64):
			var angle := TAU * i / 64.0
			var next := TAU * (i + 1) / 64.0
			_quad(surface, _polar(a.x, a.y, angle), _polar(b.x, b.y, angle),
				_polar(b.x, b.y, next), _polar(a.x, a.y, next))
	_finish(surface, parent, title, finish)


static func _loft(parent: Node3D, title: String, sections: Array, finish: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(sections.size() - 1):
		for i in range(32):
			var angle := TAU * i / 32.0
			var next := TAU * (i + 1) / 32.0
			_quad(surface, _section(sections[row], angle), _section(sections[row + 1], angle),
				_section(sections[row + 1], next), _section(sections[row], next))
	for row in [0, sections.size() - 1]:
		var center := Vector3(0, sections[row][1], sections[row][0])
		for i in range(32):
			var a := _section(sections[row], TAU * i / 32.0)
			var b := _section(sections[row], TAU * (i + 1) / 32.0)
			for point in ([center, a, b] if row == 0 else [center, b, a]):
				surface.add_vertex(point)
	_finish(surface, parent, title, finish)


static func _section(section: Array, angle: float) -> Vector3:
	return Vector3(cos(angle) * section[2], section[1] + sin(angle) * section[3], section[0])


static func _fender(parent: Node3D, axle: Vector3, half: float, start: float, end: float, finish: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(22):
		var a := lerpf(start, end, i / 22.0)
		var b := lerpf(start, end, (i + 1) / 22.0)
		for col in range(8):
			var x := lerpf(-half, half, col / 8.0)
			var next := lerpf(-half, half, (col + 1) / 8.0)
			var r := 0.375 - 0.034 * pow(x / half, 2)
			var rn := 0.375 - 0.034 * pow(next / half, 2)
			_quad(surface, axle + _polar(x, r, a), axle + _polar(next, rn, a),
				axle + _polar(next, rn, b), axle + _polar(x, r, b))
	var two_sided := finish.duplicate() as StandardMaterial3D
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	_finish(surface, parent, "RolledFender", two_sided)


static func _coil_shock(parent: Node3D, low: Vector3, high: Vector3, alloy: Material, steel: Material) -> void:
	var axis := (high - low).normalized()
	var across := Vector3.RIGHT
	var second := axis.cross(across).normalized()
	S.tube(parent, "ShockBody", low, low.lerp(high, 0.58), 0.025, steel)
	S.tube(parent, "DamperRod", low.lerp(high, 0.44), high, 0.013, alloy)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(60):
		for side in range(7):
			var a := _coil_vertex(low, high, across, second, i, side)
			var b := _coil_vertex(low, high, across, second, i + 1, side)
			var c := _coil_vertex(low, high, across, second, i + 1, side + 1)
			var d := _coil_vertex(low, high, across, second, i, side + 1)
			_quad(surface, a, d, c, b)
	_finish(surface, parent, "ShockSpring", alloy)


static func _coil_vertex(low: Vector3, high: Vector3, u: Vector3, v: Vector3, row: int, side: int) -> Vector3:
	var along := row / 60.0
	var turn := along * TAU * 6.0
	var section := TAU * side / 7.0
	var radial := u * cos(turn) + v * sin(turn)
	return low.lerp(high, 0.12 + along * 0.76) + radial * (0.035 + cos(section) * 0.004) + (high - low).normalized() * sin(section) * 0.004


static func _chain(parent: Node3D, front: Vector3, rear: Vector3, x: float, small: float, big: float, finish: Material) -> void:
	for side in [-1.0, 1.0]:
		var a := Vector3(x, front.y + small * side, front.z)
		var b := Vector3(x, rear.y + big * side, rear.z)
		S.tube(parent, "ChainRun", a, b, 0.006, finish)
		for i in range(18):
			S.box(parent, "ChainPlate", Vector3(0.014, 0.011, 0.022), a.lerp(b, (i + 0.5) / 18.0), finish)


static func _axle(parent: Node3D, title: String, at: Vector3, radius: float, length: float, finish: Material, sides := 16) -> void:
	S.cylinder(parent, title, at, Vector3.RIGHT, radius, length, finish, sides)


static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for vertex in [a, b, c, a, c, d]:
		surface.add_vertex(vertex)


static func _finish(surface: SurfaceTool, parent: Node3D, title: String, finish: Material) -> void:
	surface.index()
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = surface.commit()
	instance.material_override = finish
	parent.add_child(instance)
