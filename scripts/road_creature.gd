extends Node3D

const MODEL := preload("res://assets/characters/road_creature.glb")
const EYE := preload("res://assets/characters/road_eye.gdshader")
const SIDES := ["L", "R"]

var head: Node3D
var jaw: Node3D
var hands: Array[Node3D] = []
var rig: Skeleton3D
var indices: Dictionary[String, int] = {}
var rest: Dictionary[String, Transform3D] = {}
var posed: Dictionary[String, Transform3D] = {}


func _ready() -> void:
	var model := MODEL.instantiate()
	add_child(model)
	rig = model.find_child("Skeleton3D", true, false) as Skeleton3D
	for index in rig.get_bone_count():
		var label := rig.get_bone_name(index)
		indices[label] = index
		rest[label] = rig.get_bone_global_rest(index)

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
		soles: Array[Vector3], elapsed: float, reveal: float = 0.0) -> void:
	var spine := (shoulders - pelvis).normalized()
	head.position = shoulders + Vector3(0, 0.10, 0.28)
	var forward := (gaze - head.position).normalized()
	if absf(forward.dot(Vector3.UP)) < 0.98:
		head.basis = Basis.looking_at(forward, Vector3.UP, true)
	var inspect := smoothstep(5.45, 6.22, elapsed) * (1.0 - smoothstep(6.75, 7.26, elapsed))
	var jerk := _twitch(elapsed - 1.52) * -0.65 + _twitch(elapsed - 6.29)
	head.rotate_object_local(Vector3.BACK, 0.045 * sin(elapsed * 1.45) + inspect * 0.24 + jerk * (0.16 + reveal * 0.025))
	head.rotate_object_local(Vector3.RIGHT, jerk * 0.061)

	_aim_bone("Torso", pelvis, shoulders, rest["Neck"].origin)
	_aim_bone("Neck", shoulders, head.position - head.basis.z * 0.105, rest["Head"].origin)
	var face_basis := (head.basis * rest["Head"].basis).scaled_local(Vector3.ONE * 0.86)
	_set_bone("Head", Transform3D(face_basis, head.position - head.basis.z * 0.105))
	_pose_jaw()
	for i in SIDES.size():
		var suffix: String = SIDES[i]
		var side := -1.0 if i == 0 else 1.0
		var normal := normals[i].normalized()
		var bearing := Vector3.BACK.slide(normal).normalized()
		var hand := hands[i]
		hand.basis = Basis(normal.cross(bearing).normalized(), normal, bearing)
		hand.position = palms[i] + normal * 0.023
		var wrist := hand.position - bearing * 0.057 + normal * 0.064
		var shoulder := shoulders + Vector3(side * 0.193, 0.0, 0.0)
		var elbow := _joint(shoulder, wrist, Vector3(side * 0.91, -0.20, -0.65), 0.73, 0.78)
		_aim_bone("UpperArm" + suffix, shoulder, elbow, rest["Forearm" + suffix].origin)
		_aim_bone("Forearm" + suffix, elbow, wrist, rest["Hand" + suffix].origin)
		_set_bone("Hand" + suffix, Transform3D(hand.basis * rest["Hand" + suffix].basis, wrist))
		var ankle := soles[i] + Vector3(0, 0.106, -0.04)
		var hip := pelvis + Vector3(side * 0.116, 0.0, 0.0)
		var knee := _joint(hip, ankle, Vector3(side * 0.83, 0.18, 0.74), 0.69, 0.65)
		_aim_bone("Thigh" + suffix, hip, knee, rest["Shin" + suffix].origin)
		_aim_bone("Shin" + suffix, knee, ankle, rest["Foot" + suffix].origin)
		_set_bone("Foot" + suffix, Transform3D(rest["Foot" + suffix].basis, ankle))


func set_jaw_offset(offset: float) -> void:
	jaw.position.y = offset
	_pose_jaw()


func _pose_jaw() -> void:
	var target := posed["Head"] * rest["Head"].affine_inverse() * rest["Jaw"]
	target.origin += head.basis * jaw.position
	_set_bone("Jaw", target)


func _aim_bone(label: String, start: Vector3, end: Vector3, bind_end: Vector3) -> void:
	var bind := rest[label]
	var direction := (bind_end - bind.origin).normalized()
	var span := end - start
	var rotation := Basis(Quaternion(direction, span.normalized()))
	var stretch := clampf(span.length() / bind.origin.distance_to(bind_end), 0.35, 1.62)
	_set_bone(label, Transform3D((rotation * bind.basis).scaled_local(Vector3(1.0, stretch, 1.0)), start))


func _set_bone(label: String, target: Transform3D) -> void:
	var index := indices[label]
	var parent := rig.get_bone_parent(index)
	var local := target
	if parent >= 0:
		local = posed[rig.get_bone_name(parent)].affine_inverse() * target
	posed[label] = target
	rig.set_bone_pose(index, local)


func _twitch(elapsed: float) -> float:
	return smoothstep(0, 0.042, elapsed) * (1.0 - smoothstep(0.064, 0.24, elapsed))


func _joint(start: Vector3, end: Vector3, bend: Vector3, first: float, second: float) -> Vector3:
	var span := end - start
	var distance := clampf(span.length(), 0.001, first + second - 0.002)
	var direction := span.normalized()
	var forward := (first * first + distance * distance - second * second) / (2.0 * distance)
	return start + direction * forward + bend.slide(direction).normalized() * sqrt(maxf(0, first * first - forward * forward))
