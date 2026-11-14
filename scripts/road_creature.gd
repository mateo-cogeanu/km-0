extends Node3D

const Shapes := preload("res://scripts/prop_shapes.gd")

const UPPER_ARM := 0.73
const FOREARM := 0.78
const THIGH := 0.69
const SHIN := 0.65
const SIDE := [-1.0, 1.0]

const ARM_PROFILE: Array[Vector2] = [
	Vector2(0.022, 0.025), Vector2(0.093, 0.088), Vector2(0.086, 0.072), Vector2(0.070, 0.061),
	Vector2(0.054, 0.051), Vector2(0.052, 0.044), Vector2(0.061, 0.046), Vector2(0.048, 0.035),
	Vector2(0.034, 0.027), Vector2(0.026, 0.021), Vector2(0.009, 0.009),
]
const LEG_PROFILE: Array[Vector2] = [
	Vector2(0.024, 0.028), Vector2(0.104, 0.099), Vector2(0.091, 0.081), Vector2(0.072, 0.064),
	Vector2(0.055, 0.052), Vector2(0.055, 0.046), Vector2(0.064, 0.053), Vector2(0.054, 0.046),
	Vector2(0.038, 0.032), Vector2(0.028, 0.024), Vector2(0.011, 0.010),
]
const TORSO_PROFILE: Array[Vector2] = [
	Vector2(0.033, 0.046), Vector2(0.138, 0.094), Vector2(0.163, 0.116), Vector2(0.135, 0.103),
	Vector2(0.114, 0.086), Vector2(0.132, 0.102), Vector2(0.168, 0.125), Vector2(0.192, 0.129),
	Vector2(0.206, 0.113), Vector2(0.151, 0.091), Vector2(0.083, 0.064), Vector2(0.057, 0.046),
	Vector2(0.043, 0.033), Vector2(0.006, 0.006),
]

var torso: MeshInstance3D
var head: Node3D
var jaw: Node3D
var arms: Array[MeshInstance3D] = []
var legs: Array[MeshInstance3D] = []
var hands: Array[Node3D] = []
var feet: Array[Node3D] = []
var skin_detail := Shapes.material(Color("#706066"), 0.0, 0.9)
var body_skin := StandardMaterial3D.new()
var skin := Shapes.material(Color("#b9aa9e"), 0.0, 0.91)
var joints := Shapes.material(Color("#7c6e6a"), 0.0, 0.96)
var bone := Shapes.material(Color("#d9ccb0"), 0.0, 0.8)


func _ready() -> void:
	body_skin.vertex_color_use_as_albedo = true
	body_skin.vertex_color_is_srgb = true
	body_skin.roughness = 0.89
	torso = _skin_mesh(self, "TorsoSkin")
	for side: float in SIDE:
		arms.append(_skin_mesh(self, "ArmSkin"))
		legs.append(_skin_mesh(self, "LegSkin"))
		var foot := Node3D.new()
		add_child(foot)
		feet.append(foot)
		_oval(foot, "Foot", Vector3(0, 0.016, 0.027), Vector3(0.108, 0.071, 0.237), joints)
		for toe in range(3):
			_oval(foot, "Toe", Vector3((toe - 1) * 0.024, 0.015, 0.139), Vector3(0.021, 0.026, 0.069), skin)
		_build_hand(side)
	_build_head()


func _build_hand(side: float) -> void:
	var hand := Node3D.new()
	hand.name = "LeftHand" if side < 0 else "RightHand"
	add_child(hand)
	hands.append(hand)
	_oval(hand, "Palm", Vector3(0, 0, 0.014), Vector3(0.126, 0.049, 0.136), joints)
	for finger in range(5):
		var root := Vector3((finger - 2.15) * 0.023, 0.004, 0.058 if finger < 4 else 0.013)
		var spread := (finger - 1.5) * 0.034 if finger < 4 else side * 0.097
		var middle := Vector3(spread, 0.017, 0.13 - absf(finger - 1) * 0.012)
		var tip := middle + Vector3(spread * 0.41, -0.014, 0.059 if finger < 4 else 0.019)
		var finger_skin := _skin_mesh(hand, "Finger")
		var sections: Array[Vector2] = [Vector2(0.004, 0.004), Vector2(0.012, 0.010),
			Vector2(0.009, 0.008), Vector2(0.011, 0.010), Vector2(0.008, 0.007),
			Vector2(0.006, 0.005), Vector2(0.002, 0.002)]
		_skin_chain(finger_skin, root, middle, tip, sections)
		Shapes.tube(hand, "Nail", tip, tip + Vector3(0, -0.009, 0.019), 0.005, bone)


func _build_head() -> void:
	head = Node3D.new()
	head.name = "Head"
	add_child(head)
	_head_surface()
	var socket := Shapes.material(Color("#09070a"), 0.0, 0.94)
	var slit := Shapes.material(Color("#b21019"))
	slit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slit.emission_enabled = true
	slit.emission = Color("#ff192c")
	slit.emission_energy_multiplier = 2.2
	for side: float in SIDE:
		_oval(head, "BlackEye", Vector3(side * 0.062, 0.319, 0.149), Vector3(0.067, 0.041, 0.046), socket)
		_oval(head, "RedSlit", Vector3(side * 0.062, 0.319, 0.174), Vector3(0.007, 0.030, 0.005), slit)
	jaw = Node3D.new()
	jaw.name = "JawPivot"
	head.add_child(jaw)
	_build_teeth(head, Vector3(0, 0.204, 0.145), true)
	_build_teeth(jaw, Vector3(0, 0.041, 0.131), false)


func _head_surface() -> void:
	# The first loops form the throat and gums. Subsequent loops run up the face
	# and around the skull, so there are no separate cheeks or lip meshes to intersect.
	var loops := [
		Vector4(0.004, 0.006, 0.116, 0.039),
		Vector4(0.064, 0.065, 0.116, 0.052),
		Vector4(0.096, 0.080, 0.116, 0.087),
		Vector4(0.112, 0.093, 0.117, 0.145),
		Vector4(0.121, 0.100, 0.118, 0.157),
		Vector4(0.130, 0.117, 0.123, 0.143),
		Vector4(0.135, 0.200, 0.197, 0.114),
		Vector4(0.145, 0.215, 0.220, 0.062),
		Vector4(0.128, 0.206, 0.231, -0.035),
		Vector4(0.087, 0.162, 0.239, -0.115),
		Vector4(0.002, 0.005, 0.239, -0.150),
	]
	var tones := [Color("#10090e"), Color("#170d13"), Color("#2a141a"),
		Color("#46262c"), Color("#514047"), Color("#9b817c"), Color("#b3a49a"),
		Color("#b4a59c"), Color("#af9f97"), Color("#9f8f8b"), Color("#9f8f8b")]
	var facial_skin := StandardMaterial3D.new()
	facial_skin.vertex_color_use_as_albedo = true
	facial_skin.vertex_color_is_srgb = false
	facial_skin.roughness = 0.92
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var throat_end := Vector3(0, loops[0].z, loops[0].w - 0.006)
	for i in range(80):
		var a := _face_point(loops[0], 0, i)
		var b := _face_point(loops[0], 0, (i + 1) % 80)
		for point in [throat_end, a, b, throat_end, b, a]:
			mesh.set_color(tones[0])
			mesh.add_vertex(point)
	for row in range(loops.size() - 1):
		for i in range(80):
			var a := _face_point(loops[row], row, i)
			var b := _face_point(loops[row], row, (i + 1) % 80)
			var c := _face_point(loops[row + 1], row + 1, (i + 1) % 80)
			var d := _face_point(loops[row + 1], row + 1, i)
			for item in [[a, row], [b, row], [c, row + 1], [a, row], [c, row + 1], [d, row + 1]]:
				var point: Vector3 = item[0]
				var tone: Color = tones[item[1]]
				var socket_shadow := exp(-pow((absf(point.x) - 0.062) / 0.043, 2) - pow((point.y - 0.319) / 0.034, 2))
				var shade := 0.11 * absf(point.x) / 0.16
				if int(item[1]) in [5, 6, 7]:
					shade += socket_shadow * 0.49
				mesh.set_color(tone.darkened(clampf(shade, 0, 0.8)))
				mesh.add_vertex(point)
	# Keep the normal direction consistent through the lip and around the scalp.
	mesh.index()
	mesh.generate_normals()
	var face := MeshInstance3D.new()
	face.name = "Face"
	face.mesh = mesh.commit()
	face.material_override = facial_skin
	head.add_child(face)


func _face_point(loop: Vector4, row: int, index: int) -> Vector3:
	var angle := TAU * index / 80.0
	var rise := sin(angle)
	var x := signf(cos(angle)) * pow(absf(cos(angle)), 0.78) * loop.x
	var y := loop.z + rise * loop.y
	if row in [2, 3, 4]:
		y += 0.023 * pow(absf(cos(angle)), 3.0) - 0.008 * maxf(0.0, rise)
	var z := loop.w
	if row >= 3 and row <= 8:
		if row >= 5:
			# Cheekbones flare under the temples, then the jaw tapers toward the chin.
			var profile := 0.74 + 0.34 * exp(-pow((y - 0.303) / 0.071, 2.0))
			profile -= 0.12 * exp(-pow((y - 0.208) / 0.040, 2.0))
			if y < 0.096:
				profile *= lerpf(0.65, 0.93, smoothstep(-0.03, 0.096, y))
			x *= profile
		z += (1.0 - absf(cos(angle))) * 0.020
		var eye := exp(-pow((absf(x) - 0.062) / 0.039, 2.0) - pow((y - 0.319) / 0.032, 2.0))
		z -= eye * 0.035
		var brow := exp(-pow((absf(x) - 0.064) / 0.058, 2.0) - pow((y - 0.351) / 0.024, 2.0))
		z += brow * 0.035
		var bridge := exp(-pow(x / 0.025, 2.0) - pow((y - 0.295) / 0.065, 2.0))
		var nose := exp(-pow(x / 0.036, 2.0) - pow((y - 0.249) / 0.024, 2.0))
		z += bridge * 0.021 + nose * 0.029
	return Vector3(x, y, z)


func _build_teeth(parent: Node3D, at: Vector3, upper: bool) -> void:
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0007
	spike.bottom_radius = 0.0033
	spike.height = 0.022
	spike.radial_segments = 5
	spike.rings = 0
	spike.material = bone
	var rows := MultiMesh.new()
	rows.transform_format = MultiMesh.TRANSFORM_3D
	rows.mesh = spike
	rows.instance_count = 132
	var rng := RandomNumberGenerator.new()
	rng.seed = 940 if upper else 431
	var direction := -1.0 if upper else 1.0
	for row in range(6):
		for tooth in range(22):
			var angle := lerpf(-1.30, 1.30, tooth / 21.0)
			var x := sin(angle) * (0.114 - row * 0.0074)
			var y := at.y + direction * (x * x * 3.0 + row * 0.003) + rng.randf_range(-0.0018, 0.0018)
			var z := at.z + cos(angle) * 0.013 - row * 0.015
			var axis := Vector3(x * -1.4, direction, rng.randf_range(-0.09, 0.12)).normalized()
			var original_length := rng.randf_range(0.54, 1.28)
			var extension := lerpf(1.73, 1.40, row / 5.0)
			var basis := Basis(Quaternion(Vector3.UP, axis)).scaled_local(Vector3(1.0, original_length * extension, 1.0))
			# Extend toward the tip to leave the root seated at the same depth.
			var center := Vector3(x, y, z) + axis * (spike.height * original_length * (extension - 1.0) * 0.5)
			rows.set_instance_transform(row * 22 + tooth, Transform3D(basis, center))
	var teeth := MultiMeshInstance3D.new()
	teeth.name = "Teeth"
	teeth.multimesh = rows
	parent.add_child(teeth)


func pose_contacts(shoulders: Vector3, pelvis: Vector3, gaze: Vector3, palms: Array[Vector3], normals: Array[Vector3],
		soles: Array[Vector3], elapsed: float, reveal: float = 0.0) -> void:
	for i in range(2):
		var side: float = SIDE[i]
		var normal := normals[i].normalized()
		var bearing := Vector3.BACK.slide(normal).normalized()
		hands[i].basis = Basis(normal.cross(bearing).normalized(), normal, bearing)
		hands[i].position = palms[i] + normal * 0.023
		var wrist := hands[i].position - bearing * 0.057
		var shoulder := shoulders + Vector3(side * 0.135, 0.01, 0.0)
		var elbow := _joint(shoulder, wrist, Vector3(side * 0.91, -0.20, -0.65), UPPER_ARM, FOREARM)
		_skin_chain(arms[i], shoulder, elbow, wrist + bearing * 0.033, ARM_PROFILE)
		feet[i].position = soles[i]
		var ankle := soles[i] + Vector3(0, 0.058, -0.04)
		var hip := pelvis + Vector3(side * 0.116, 0.0, 0.0)
		var knee := _joint(hip, ankle, Vector3(side * 0.83, 0.18, 0.74), THIGH, SHIN)
		_skin_chain(legs[i], hip, knee, ankle - Vector3.UP * 0.032, LEG_PROFILE)
	head.position = shoulders + Vector3(0, 0.10, 0.28)
	var forward := (gaze - head.position).normalized()
	if absf(forward.dot(Vector3.UP)) < 0.98:
		head.basis = Basis.looking_at(forward, Vector3.UP, true)
	var inspect := smoothstep(5.45, 6.22, elapsed) * (1.0 - smoothstep(6.75, 7.26, elapsed))
	var jerk := _twitch(elapsed - 1.52) * -0.65 + _twitch(elapsed - 6.29)
	var tilt := 0.045 * sin(elapsed * 1.45) + inspect * 0.24 + jerk * (0.16 + reveal * 0.025)
	head.rotate_object_local(Vector3.BACK, tilt)
	head.rotate_object_local(Vector3.RIGHT, jerk * 0.061)
	var spine := (shoulders - pelvis).normalized()
	var neck_end := head.position + head.basis * Vector3(0, 0.102, -0.124)
	var body_path: Array[Vector3] = []
	for i in TORSO_PROFILE.size():
		var t := float(i) / (TORSO_PROFILE.size() - 1)
		var center := (pelvis - spine * 0.11).lerp(shoulders, minf(t / 0.69, 1.0))
		if t > 0.69:
			center = shoulders.lerp(neck_end, (t - 0.69) / 0.31)
		body_path.append(center)
	_sweep(torso, body_path, TORSO_PROFILE, true)


func _twitch(elapsed: float) -> float:
	return smoothstep(0, 0.042, elapsed) * (1.0 - smoothstep(0.064, 0.24, elapsed))


func _joint(start: Vector3, end: Vector3, bend: Vector3, first: float, second: float) -> Vector3:
	var span := end - start
	var distance := clampf(span.length(), 0.001, first + second - 0.002)
	var direction := span.normalized()
	var forward := (first * first + distance * distance - second * second) / (2.0 * distance)
	return start + direction * forward + bend.slide(direction).normalized() * sqrt(maxf(0, first * first - forward * forward))


# Each chain is one skin surface. The sections swell over muscle and taper into
# the wrists and ankles, while the bend follows the same contacts as the animation.
func _skin_mesh(parent: Node3D, title: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = title
	mesh.material_override = body_skin
	parent.add_child(mesh)
	return mesh


func _skin_chain(mesh: MeshInstance3D, start: Vector3, joint: Vector3, end: Vector3, profile: Array[Vector2]) -> void:
	var bend := minf(start.distance_to(joint), joint.distance_to(end)) * 0.23
	var before := joint.move_toward(start, bend)
	var after := joint.move_toward(end, bend)
	var centers: Array[Vector3] = []
	for i in profile.size():
		var t := float(i) / (profile.size() - 1)
		if t < 0.35:
			centers.append(start.lerp(before, t / 0.35))
		elif t > 0.65:
			centers.append(after.lerp(end, (t - 0.65) / 0.35))
		else:
			var turn := (t - 0.35) / 0.30
			centers.append(before.lerp(joint, turn).lerp(joint.lerp(after, turn), turn))
	_sweep(mesh, centers, profile, false)


func _sweep(mesh: MeshInstance3D, centers: Array[Vector3], profile: Array[Vector2], torso_surface: bool) -> void:
	const SIDES := 16
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in centers.size():
		var tangent := (centers[mini(ring + 1, centers.size() - 1)] - centers[maxi(ring - 1, 0)]).normalized()
		var across := Vector3.RIGHT.slide(tangent).normalized()
		if across.length_squared() < 0.1:
			across = Vector3.UP.slide(tangent).normalized()
		var depth := tangent.cross(across)
		for side in SIDES:
			var angle := TAU * side / SIDES
			var x := cos(angle)
			var y := sin(angle)
			var t := float(ring) / (centers.size() - 1)
			var contour := 1.0 + 0.065 * cos(3.0 * angle + t * 2.4)
			if torso_surface:
				# The front of the chest carries the ribs as shallow ridges in the skin.
				contour += 0.085 * pow(maxf(y, 0.0), 2.0) * cos(t * 34.0) * sin(PI * t)
			var point := centers[ring] + (across * x * profile[ring].x + depth * y * profile[ring].y) * contour
			var shade := 0.045 * (1.0 + cos(3.0 * angle - t * 8.0))
			shade += (0.11 if not torso_surface else 0.045) * exp(-pow((t - 0.51) / 0.11, 2.0))
			surface.set_color(Color("#baaca1").lerp(Color("#796671"), shade))
			surface.add_vertex(point)
	for ring in range(centers.size() - 1):
		for side in SIDES:
			var a := ring * SIDES + side
			var b := ring * SIDES + (side + 1) % SIDES
			for index in [a, b + SIDES, b, a, a + SIDES, b + SIDES]:
				surface.add_index(index)
	surface.generate_normals()
	mesh.mesh = surface.commit()


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
