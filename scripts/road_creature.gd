extends Node3D

const MODEL := preload("res://assets/characters/road_creature.glb")
const EYE := preload("res://assets/characters/road_eye.gdshader")
const SKIN := preload("res://assets/characters/road_skin.gdshader")
const LIGHT_LAYER := 1 << 18
const SIDES := ["L", "R"]
# Shared with Sources/make_road_creature.py, which builds the rest pose to these lengths.
const HEAD_OFFSET := Vector3(0, 0.16, 0.36)
const UPPER_ARM := 0.56
const FOREARM := 0.6
const THIGH := 0.54
const SHIN := 0.52
const HEAD_PIVOT := 0.105

var head: Node3D
var jaw: Node3D
var hands: Array[Node3D] = []
var rig: Skeleton3D
var indices: Dictionary[String, int] = {}
var rest: Dictionary[String, Transform3D] = {}
var posed: Dictionary[String, Transform3D] = {}
## Extra head roll in radians, set while the creature stops to study you.
var tilt := 0.0
var torso_length := 0.744
var neck_length := 0.3
var rest_spine := Vector3.BACK


func _ready() -> void:
	var model := MODEL.instantiate()
	add_child(model)
	rig = model.find_child("Skeleton3D", true, false) as Skeleton3D
	for index in rig.get_bone_count():
		var label := rig.get_bone_name(index)
		indices[label] = index
		rest[label] = rig.get_bone_global_rest(index)
	torso_length = rest["Torso"].origin.distance_to(rest["Neck"].origin)
	neck_length = rest["Neck"].origin.distance_to(rest["Head"].origin)
	rest_spine = (rest["Neck"].origin - rest["Torso"].origin).normalized()

	var skin_material := ShaderMaterial.new()
	skin_material.shader = SKIN
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = LIGHT_LAYER
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			if material and material.resource_name.begins_with("Pale mottled skin"):
				mesh.set_surface_override_material(surface, skin_material)
	var eye_material := ShaderMaterial.new()
	eye_material.shader = EYE
	for eye: MeshInstance3D in model.find_children("Black eye*", "MeshInstance3D", true, false):
		eye.material_override = eye_material
	head = Node3D.new()
	add_child(head)
	jaw = Node3D.new()
	head.add_child(jaw)
	for side in SIDES:
		var hand := Node3D.new()
		hand.name = "Palm" + side
		add_child(hand)
		hands.append(hand)


func pose_contacts(shoulders: Vector3, pelvis: Vector3, gaze: Vector3, palms: Array[Vector3], normals: Array[Vector3],
		soles: Array[Vector3], elapsed: float, reveal: float = 0.0, sole_normals: Array[Vector3] = [],
		back: Vector3 = Vector3.UP) -> void:
	## Pose the body from where its shoulders and pelvis are, where its hands and
	## feet touch, and which way its back faces. back is UP on the floor and
	## points away from a wall the creature is clinging to.
	# Bones never change length. A target out of reach is pulled back in, so a
	# hand may hover instead of the arm stretching to meet it.
	var torso := shoulders - pelvis
	var spine := torso.normalized() if torso.length() > 0.001 else Vector3.BACK
	pelvis = shoulders - spine * torso_length
	# Everything authored in rest space (shoulder width, elbow direction, head
	# offset) turns with the body, so it works on walls and in any heading.
	var body := _frame(spine, back) * _frame(rest_spine, Vector3.UP).inverse()
	var body_up := _frame(spine, back).y
	var head_offset := body * HEAD_OFFSET
	var forward := (gaze - (shoulders + head_offset)).normalized()
	if absf(forward.dot(body_up)) < 0.98:
		head.basis = Basis.looking_at(forward, body_up, true)
	var inspect := smoothstep(5.45, 6.22, elapsed) * (1.0 - smoothstep(6.75, 7.26, elapsed))
	var jerk := _twitch(elapsed - 1.52) * -0.65 + _twitch(elapsed - 6.29)
	head.rotate_object_local(Vector3.BACK, 0.045 * sin(elapsed * 1.45) + inspect * 0.24 + jerk * (0.16 + reveal * 0.025) + tilt)
	head.rotate_object_local(Vector3.RIGHT, jerk * 0.061)
	var neck_end := shoulders + head_offset - head.basis.z * HEAD_PIVOT
	neck_end = shoulders + (neck_end - shoulders).normalized() * neck_length
	head.position = neck_end + head.basis.z * HEAD_PIVOT

	_set_bone("Torso", Transform3D(body * rest["Torso"].basis, pelvis))
	_aim_bone("Neck", shoulders, neck_end, rest["Head"].origin, body)
	_set_bone("Head", Transform3D(head.basis * rest["Head"].basis, neck_end))
	_pose_jaw()
	var heading := body * Vector3.BACK
	for i in SIDES.size():
		var suffix: String = SIDES[i]
		var side := -1.0 if i == 0 else 1.0
		var normal := normals[i].normalized()
		var hand := hands[i]
		hand.basis = _contact_basis(normal, heading)
		var shoulder := shoulders + body * Vector3(side * 0.193, 0.0, 0.0)
		var wrist := _reach(shoulder, palms[i] + normal * 0.087 - hand.basis.z * 0.057, UPPER_ARM + FOREARM)
		hand.position = wrist + hand.basis.z * 0.057 - normal * 0.064
		# Elbows splay out and back from the body.
		var elbow := _joint(shoulder, wrist, body * Vector3(side * 0.91, -0.20, -0.65), UPPER_ARM, FOREARM)
		_aim_bone("UpperArm" + suffix, shoulder, elbow, rest["Forearm" + suffix].origin, body)
		_aim_bone("Forearm" + suffix, elbow, wrist, rest["Hand" + suffix].origin, body)
		_set_bone("Hand" + suffix, Transform3D(hand.basis * rest["Hand" + suffix].basis, wrist))
		var sole_normal := sole_normals[i].normalized() if i < sole_normals.size() else Vector3.UP
		var foot_basis := _contact_basis(sole_normal, heading)
		var hip := pelvis + body * Vector3(side * 0.116, 0.0, 0.0)
		var ankle := _reach(hip, soles[i] + sole_normal * 0.106 - foot_basis.z * 0.04, THIGH + SHIN)
		var knee := _joint(hip, ankle, body * Vector3(side * 0.9, 0.1, 0.6), THIGH, SHIN)
		_aim_bone("Thigh" + suffix, hip, knee, rest["Shin" + suffix].origin, body)
		_aim_bone("Shin" + suffix, knee, ankle, rest["Foot" + suffix].origin, body)
		_set_bone("Foot" + suffix, Transform3D(foot_basis * rest["Foot" + suffix].basis, ankle))


func _frame(forward: Vector3, up: Vector3) -> Basis:
	## Right, up, forward axes for a body facing forward with its back to up.
	var right := up.cross(forward)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	return Basis(right, forward.cross(right).normalized(), forward)


func _contact_basis(normal: Vector3, heading: Vector3) -> Basis:
	## Palm or sole flat against a surface, fingers pointing along heading (or
	## up when the surface faces that way).
	var bearing := heading.slide(normal)
	if bearing.length() < 0.3:
		bearing = Vector3.UP.slide(normal)
	bearing = bearing.normalized()
	return Basis(normal.cross(bearing).normalized(), normal, bearing)


func _reach(root: Vector3, target: Vector3, length: float) -> Vector3:
	var span := target - root
	var limit := length * 0.985
	return target if span.length() <= limit else root + span.normalized() * limit


func set_jaw_offset(offset: float) -> void:
	jaw.position.y = offset
	_pose_jaw()


func _pose_jaw() -> void:
	var target := posed["Head"] * rest["Head"].affine_inverse() * rest["Jaw"]
	target.origin += head.basis * jaw.position
	_set_bone("Jaw", target)


func _aim_bone(label: String, start: Vector3, end: Vector3, bind_end: Vector3, body: Basis) -> void:
	## Turn a bone with the body, then swing it to point at end. Turning with the
	## body first keeps limbs from twisting when the creature is on a wall.
	var bind := rest[label]
	var direction := body * (bind_end - bind.origin).normalized()
	var swing := Basis(Quaternion(direction, (end - start).normalized()))
	_set_bone(label, Transform3D(swing * body * bind.basis, start))


func _set_bone(label: String, target: Transform3D) -> void:
	# Contact targets are in skeleton space. Apply them directly so each bone
	# lands exactly where the solve put it.
	posed[label] = target
	rig.set_bone_global_pose_override(indices[label], target, 1.0, true)


func _twitch(elapsed: float) -> float:
	return smoothstep(0, 0.042, elapsed) * (1.0 - smoothstep(0.064, 0.24, elapsed))


func _joint(start: Vector3, end: Vector3, bend: Vector3, first: float, second: float) -> Vector3:
	var span := end - start
	var distance := clampf(span.length(), 0.001, first + second - 0.002)
	var direction := span.normalized()
	var forward := (first * first + distance * distance - second * second) / (2.0 * distance)
	return start + direction * forward + bend.slide(direction).normalized() * sqrt(maxf(0, first * first - forward * forward))
