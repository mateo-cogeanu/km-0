extends Camera3D
## A short eased move from one view to another (getting in or out of a car),
## instead of a cut. Follows the target while it moves, then hands over to it.

var from_transform: Transform3D
var from_fov := 75.0
var target: Camera3D
var seconds := 0.4
var clock := 0.0


static func between(from: Camera3D, to: Camera3D, length := 0.4) -> void:
	if from == null or to == null or from == to or not from.is_inside_tree() or not to.is_inside_tree():
		return
	if GameSettings.camera_motion < 0.05:
		return
	var blend: Camera3D = (load("res://scripts/camera_blend.gd") as GDScript).new()
	blend.name = "CameraBlend"
	blend.from_transform = from.get_global_transform_interpolated()
	blend.from_fov = from.fov
	blend.target = to
	blend.seconds = length
	blend.near = minf(from.near, to.near)
	blend.far = maxf(from.far, to.far)
	blend.environment = to.environment
	blend.cull_mask = to.cull_mask
	to.get_tree().current_scene.add_child(blend)
	blend.top_level = true
	blend.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	blend.global_transform = blend.from_transform
	blend.fov = blend.from_fov
	blend.make_current()


func _process(delta: float) -> void:
	clock += delta
	if not is_instance_valid(target) or not target.is_inside_tree():
		queue_free()
		return
	var t := clampf(clock / seconds, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	global_transform = from_transform.interpolate_with(target.get_global_transform_interpolated(), eased)
	fov = lerpf(from_fov, target.fov, eased)
	if t >= 1.0:
		target.make_current()
		queue_free()
