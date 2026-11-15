extends Node3D
## The player's own body (assets/characters/player.glb, built by
## Sources/make_player.py). Legs walk under you, and the hands reach for, hold
## and put down whatever you are handling, closing their fingers around it. For
## your own view the head only casts a shadow; other players see it.

const MODEL := preload("res://assets/characters/player.glb")
const Shapes := preload("res://scripts/prop_shapes.gd")
## The body sits on this render layer so your own flashlight skips it.
const BODY_LAYER := 1 << 17
## From the player's centre down to the soles.
const FEET := 1.025
## Body nodes sit a little behind the eyes, so looking down shows your chest
## and legs instead of the inside of your neck.
const BACK_OFFSET := 0.07
const FINGERS := ["Index", "Middle", "Ring", "Pinky", "Thumb"]
const SIDES := ["L", "R"]

var rig: Skeleton3D
var model: Node3D
var rest := {}
var bones := {}
var lengths := {}
var finger_rel := {}
var finger_axis := {}
var torch: Node3D
var stride := 0.0
var hand_at: Array[Vector3] = []
var to_rig := Transform3D()
var posed := {}


func build(own_view: bool) -> void:
	model = MODEL.instantiate()
	model.name = "Model"
	add_child(model)
	model.position.y = -FEET
	rig = model.find_child("Skeleton3D", true, false) as Skeleton3D
	for index in rig.get_bone_count():
		var label := rig.get_bone_name(index)
		bones[label] = index
		rest[label] = rig.get_bone_global_rest(index)
	for side in SIDES:
		lengths["UpperArm"] = rest["UpperArmR"].origin.distance_to(rest["ForearmR"].origin)
		lengths["Forearm"] = rest["ForearmR"].origin.distance_to(rest["HandR"].origin)
		lengths["Thigh"] = rest["ThighR"].origin.distance_to(rest["ShinR"].origin)
		lengths["Shin"] = rest["ShinR"].origin.distance_to(rest["FootR"].origin)
		_prepare_fingers(side)
	for mesh: GeometryInstance3D in model.find_children("*", "GeometryInstance3D", true, false):
		mesh.layers = BODY_LAYER
		var title := String(mesh.name)
		if own_view and (title.begins_with("Head") or title.begins_with("Hair") or title.begins_with("Eye") or title.begins_with("Iris")):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	to_rig = (Transform3D(Basis(), model.position) * _skeleton_offset()).affine_inverse()
	for i in 2:
		hand_at.append(rest["Hand" + SIDES[i]].origin)
	_build_torch()


func _skeleton_offset() -> Transform3D:
	var offset := Transform3D()
	var node: Node = rig
	while node and node != model:
		if node is Node3D:
			offset = (node as Node3D).transform * offset
		node = node.get_parent()
	return offset


func _prepare_fingers(side: String) -> void:
	## Each finger bone keeps its rest offset from its parent, plus the axis it
	## curls around, so a grip is just an angle.
	var hand: Transform3D = rest["Hand" + side]
	var across: Vector3 = (rest["Index1" + side].origin - rest["Pinky1" + side].origin).normalized()
	var along: Vector3 = (rest["Middle1" + side].origin - hand.origin).normalized()
	var palm_center: Vector3 = hand.origin + along * 0.06
	for finger in FINGERS:
		var first: Transform3D = rest[finger + "1" + side]
		var second: Transform3D = rest[finger + "2" + side]
		var direction: Vector3 = (second.origin - first.origin).normalized()
		var axis := across
		if finger == "Thumb":
			axis = direction.cross(palm_center - first.origin).normalized()
		# Pick the turn that brings the fingertip towards the palm.
		var inward: Vector3 = (palm_center + along * 0.04 - first.origin).normalized()
		if (Basis(axis, 0.3) * direction).dot(inward) < direction.dot(inward):
			axis = -axis
		finger_rel[finger + "1" + side] = hand.affine_inverse() * first
		finger_rel[finger + "2" + side] = first.affine_inverse() * second
		finger_axis[finger + "1" + side] = hand.basis.inverse() * axis
		finger_axis[finger + "2" + side] = first.basis.inverse() * axis


func _build_torch() -> void:
	torch = Node3D.new()
	torch.name = "Flashlight"
	add_child(torch)
	var steel := Shapes.material(Color("#2c2d30"), 0.6, 0.4)
	Shapes.cylinder(torch, "Barrel", Vector3(0, 0, -0.02), Vector3.BACK, 0.017, 0.16, steel, 12)
	Shapes.cylinder(torch, "Head", Vector3(0, 0, -0.11), Vector3.BACK, 0.025, 0.04, steel, 12)
	var lens := Shapes.material(Color("#fff6dc"))
	lens.emission_enabled = true
	lens.emission = Color("#fff1c8")
	lens.emission_energy_multiplier = 2.0
	Shapes.cylinder(torch, "Lens", Vector3(0, 0, -0.131), Vector3.BACK, 0.021, 0.004, lens, 12)
	for mesh: GeometryInstance3D in torch.find_children("*", "GeometryInstance3D", true, false):
		mesh.layers = BODY_LAYER
	torch.hide()


## info keys: velocity (local to the player), on_floor, drop (how far the head
## has sunk for a crouch), pitch, targets ([left, right]: Vector3 or null, local
## to the player), grip ([left, right] 0 to 1), torch (bool), torch_basis (the
## view's basis, local to the player), step (metres per footstep)
func animate(delta: float, info: Dictionary) -> void:
	var velocity: Vector3 = info.get("velocity", Vector3.ZERO)
	var flat := Vector3(velocity.x, 0, velocity.z)
	var speed := flat.length()
	var on_floor: bool = info.get("on_floor", true)
	var drop: float = info.get("drop", 0.0)
	var pitch: float = info.get("pitch", 0.0)
	var step: float = info.get("step", 1.0)
	var back := BACK_OFFSET + 0.1 * maxf(0.0, -pitch) / 1.4
	# One full leg cycle is two footsteps, so the legs land with the sounds.
	if on_floor and speed > 0.2:
		stride += delta * speed / step
	var stride_size := clampf(speed / 4.0, 0.0, 1.0) * 0.3 + clampf((speed - 4.0) / 6.0, 0.0, 1.0) * 0.2
	var heading := flat.normalized() if speed > 0.2 else Vector3.FORWARD
	var lean := clampf(speed / 10.0, 0.0, 1.0) * 0.14 + clampf(drop / 0.6, 0.0, 1.0) * 0.25
	var sink := drop * 0.85
	var bob := -absf(sin(stride * PI)) * 0.025 * clampf(speed / 3.4, 0.0, 1.0)
	var lean_basis := Basis(Vector3.RIGHT, -lean)
	var half_lean := Basis(Vector3.RIGHT, -lean * 0.5)
	# Spine up from the hips.
	var hips: Vector3 = rest["Hips"].origin + Vector3(0, -sink + bob, back)
	_pose_bone("Hips", Transform3D(rest["Hips"].basis, hips))
	var spine: Vector3 = hips + (rest["Spine"].origin - rest["Hips"].origin)
	_pose_bone("Spine", Transform3D(half_lean * rest["Spine"].basis, spine))
	var chest: Vector3 = spine + half_lean * (rest["Chest"].origin - rest["Spine"].origin)
	_pose_bone("Chest", Transform3D(lean_basis * rest["Chest"].basis, chest))
	var neck: Vector3 = chest + lean_basis * (rest["Neck"].origin - rest["Chest"].origin)
	_pose_bone("Neck", Transform3D(lean_basis * rest["Neck"].basis, neck))
	var head: Vector3 = neck + lean_basis * (rest["Head"].origin - rest["Neck"].origin)
	_pose_bone("Head", Transform3D(Basis(Vector3.RIGHT, clampf(pitch * 0.5, -0.5, 0.5)) * lean_basis * rest["Head"].basis, head))
	var targets: Array = info.get("targets", [null, null])
	var grips: Array = info.get("grip", [0.0, 0.0])
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var suffix: String = SIDES[i]
		# Legs.
		var phase := stride * PI + (0.0 if i == 0 else PI)
		var swing := sin(phase)
		var lift := maxf(0.0, cos(phase)) * (0.12 if speed > 0.2 else 0.0)
		var hip: Vector3 = hips + (rest["Thigh" + suffix].origin - rest["Hips"].origin)
		var ankle: Vector3 = rest["Foot" + suffix].origin + Vector3(0, 0, back) + heading * stride_size * swing + Vector3.UP * lift
		if not on_floor:
			ankle += Vector3(0, 0.2, 0.06)
		ankle = _reach(hip, ankle, lengths["Thigh"] + lengths["Shin"])
		var knee := _joint(hip, ankle, Vector3(side * 0.1, 0.0, -1.0), lengths["Thigh"], lengths["Shin"])
		_aim("Thigh" + suffix, hip, knee, "Shin" + suffix, Basis())
		_aim("Shin" + suffix, knee, ankle, "Foot" + suffix, Basis())
		var yaw := atan2(-heading.x, -heading.z) if speed > 0.2 else 0.0
		_pose_bone("Foot" + suffix, Transform3D(Basis(Vector3.UP, yaw) * rest["Foot" + suffix].basis, ankle))
		# Arms: swing opposite the legs, or reach for a target.
		var shoulder: Vector3 = chest + lean_basis * (rest["UpperArm" + suffix].origin - rest["Chest"].origin)
		var hang: Vector3 = shoulder + Vector3(side * 0.06, -0.52, 0.02) - heading * stride_size * swing * 0.5
		var aim_at: Variant = targets[i]
		var wanted: Vector3 = to_rig * (aim_at as Vector3) if aim_at != null else hang
		hand_at[i] = hand_at[i].lerp(wanted, 1.0 - exp(-(18.0 if aim_at != null else 9.0) * delta))
		var wrist := _reach(shoulder, hand_at[i], lengths["UpperArm"] + lengths["Forearm"])
		var elbow := _joint(shoulder, wrist, Vector3(side * 0.6, -0.8, 0.35), lengths["UpperArm"], lengths["Forearm"])
		_aim("UpperArm" + suffix, shoulder, elbow, "Forearm" + suffix, lean_basis)
		_aim("Forearm" + suffix, elbow, wrist, "Hand" + suffix, lean_basis)
		var reach_dir := (wrist - elbow).normalized()
		_aim("Hand" + suffix, wrist, wrist + reach_dir, "Middle1" + suffix, lean_basis)
		_curl(suffix, grips[i])
	var torch_on: bool = info.get("torch", false)
	torch.visible = torch_on
	if torch_on:
		var hand: Transform3D = posed["HandL"]
		var palm: Vector3 = hand.origin.lerp((posed["Middle1L"] as Transform3D).origin, 0.55)
		var view: Basis = info.get("torch_basis", Basis())
		torch.transform = Transform3D(view, to_rig.affine_inverse() * palm)


func _pose_bone(label: String, pose: Transform3D) -> void:
	posed[label] = pose
	rig.set_bone_global_pose_override(bones[label], pose, 1.0, true)


func _aim(label: String, start: Vector3, end: Vector3, child: String, body: Basis) -> void:
	## Turn a bone with the body, then swing it so it points at end.
	var bind: Transform3D = rest[label]
	var direction: Vector3 = body * (rest[child].origin - bind.origin).normalized()
	var wanted := (end - start).normalized()
	var swing := Basis(Quaternion(direction, wanted)) if direction.dot(wanted) > -0.999 else Basis(Vector3.RIGHT, PI)
	_pose_bone(label, Transform3D(swing * body * bind.basis, start))


func _curl(side: String, grip: float) -> void:
	var hand: Transform3D = posed["Hand" + side]
	for finger in FINGERS:
		var parent := hand
		for part in ["1", "2"]:
			var label: String = finger + part + side
			var rel: Transform3D = finger_rel[label]
			var angle := grip * (1.05 if part == "1" else 1.25) * (0.7 if finger == "Thumb" else 1.0)
			var turned := Transform3D(Basis(finger_axis[label], angle) * rel.basis, rel.origin)
			parent = parent * turned
			_pose_bone(label, parent)


func _reach(root: Vector3, target: Vector3, length: float) -> Vector3:
	var span := target - root
	var limit := length * 0.99
	return target if span.length() <= limit else root + span.normalized() * limit


func _joint(start: Vector3, end: Vector3, bend: Vector3, first: float, second: float) -> Vector3:
	var span := end - start
	var distance := clampf(span.length(), 0.001, first + second - 0.002)
	var direction := span.normalized()
	var forward := (first * first + distance * distance - second * second) / (2.0 * distance)
	var side := bend.slide(direction)
	if side.length() < 0.001:
		side = Vector3.FORWARD.slide(direction)
	return start + direction * forward + side.normalized() * sqrt(maxf(0.0, first * first - forward * forward))
