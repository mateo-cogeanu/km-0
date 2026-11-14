extends Node3D

const CrosshairTarget := preload("res://scripts/crosshair_target.gd")

@export var interact_distance: float = 6.0

var hovered_interactable: Area3D
var dragged_interactable: Area3D
var highlight_material: StandardMaterial3D
var part_closed_rotation: Dictionary = {}

var shutter: Node3D
var side_door: Area3D


func _ready() -> void:
	_setup_highlight_material()
	var garage := $GarageModel
	if garage.starting_garage:
		add_to_group("starting_shack")
	garage.build()
	shutter = $GarageModel/GarageShutter
	side_door = _register_door("ShackDoorTarget", "shack_door", "min_x", -1.0, 96.0)


func get_door_state() -> Dictionary:
	var pivot := _get_interactable_part(side_door)
	return {"shutter": shutter.opening, "side": pivot.rotation}


func restore_door_state(state: Dictionary) -> void:
	shutter.set_opening(state.get("shutter", 0.0))
	if state.has("side"):
		_get_interactable_part(side_door).rotation = state["side"]


func get_random_part_spawn_points(count: int, rng: RandomNumberGenerator) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if count <= 0:
		return points

	var bounds := _get_global_visual_bounds()
	if bounds.size == Vector3.ZERO:
		return points

	var padding := 1.4
	var min_x := bounds.position.x - padding
	var max_x := bounds.end.x + padding
	var min_z := bounds.position.z - padding
	var max_z := bounds.end.z + padding
	var candidates: Array[Vector3] = []

	for index in range(maxi(count * 3, 12)):
		var side := index % 4
		var position := bounds.get_center()
		match side:
			0:
				position = Vector3(rng.randf_range(min_x, max_x), bounds.end.y + 2.0, min_z)
			1:
				position = Vector3(max_x, bounds.end.y + 2.0, rng.randf_range(min_z, max_z))
			2:
				position = Vector3(rng.randf_range(min_x, max_x), bounds.end.y + 2.0, max_z)
			_:
				position = Vector3(min_x, bounds.end.y + 2.0, rng.randf_range(min_z, max_z))
		candidates.append(position)

	for index in range(candidates.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var point := candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = point
	for candidate in candidates:
		if points.size() >= count:
			break
		if _is_clear_part_position(candidate, points):
			points.append(_drop_to_ground(candidate))

	return points


func _get_global_visual_bounds() -> AABB:
	var bounds := AABB()
	var has_bounds := false
	for mesh in _get_meshes_recursive(self):
		if mesh.mesh == null:
			continue
		var mesh_bounds := mesh.global_transform * mesh.mesh.get_aabb()
		if not has_bounds:
			bounds = mesh_bounds
			has_bounds = true
		else:
			bounds = bounds.merge(mesh_bounds)
	return bounds


func _is_clear_part_position(candidate: Vector3, existing: Array[Vector3]) -> bool:
	for point in existing:
		if Vector2(point.x, point.z).distance_to(Vector2(candidate.x, candidate.z)) < 1.5:
			return false
	return true


func _drop_to_ground(position: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		position,
		Vector3(position.x, position.y - 20.0, position.z)
	)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		position.y = global_position.y + 0.5
	else:
		position.y = (hit.position as Vector3).y + 0.45
	return position


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and camera.is_in_group("driving_camera"):
		dragged_interactable = null
		_set_hovered_interactable(null)
		return
	if dragged_interactable:
		return

	if not is_visible_in_tree() or not camera or global_position.distance_squared_to(camera.global_position) > pow(interact_distance + 7.0, 2):
		_set_hovered_interactable(null)
		return
	_set_hovered_interactable(_find_pointed_interactable())


func _unhandled_input(event: InputEvent) -> void:
	var player := get_tree().get_first_node_in_group("local_player")
	if player and player.gameplay_ui_open():
		return
	var camera := get_viewport().get_camera_3d()
	if camera and camera.is_in_group("driving_camera"):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragged_interactable = _find_pointed_interactable()
		elif not event.pressed:
			dragged_interactable = null
			_set_hovered_interactable(_find_pointed_interactable())

	if event is InputEventMouseMotion and dragged_interactable:
		_drag_interactable(dragged_interactable, -event.relative.y)


func _setup_highlight_material() -> void:
	highlight_material = StandardMaterial3D.new()
	highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight_material.albedo_color = Color(1, 1, 1, 0.26)
	highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_material.no_depth_test = true


func _register_door(area_name: String, door_name: String, hinge_edge: String, open_direction: float, open_angle_degrees: float) -> Area3D:
	var visual := find_child(door_name, true, false) as Node3D
	if visual == null:
		push_warning("Missing shack door model: %s" % door_name)
		return null

	var part := _create_hinge_pivot(area_name, visual, hinge_edge)
	var area := Area3D.new()
	area.name = area_name
	area.collision_layer = 8
	area.collision_mask = 0
	area.add_to_group("shack_interactable")
	part.add_child(area)
	area.transform = visual.transform

	var area_shape := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	area_box.size = _safe_collision_size(visual) * 1.15
	area_shape.shape = area_box
	area.add_child(area_shape)

	var body := StaticBody3D.new()
	body.name = "%sBody" % door_name
	part.add_child(body)
	body.transform = visual.transform

	var body_shape := CollisionShape3D.new()
	var body_box := BoxShape3D.new()
	body_box.size = _safe_collision_size(visual)
	body_shape.shape = body_box
	body.add_child(body_shape)

	area.set_meta("part_path", area.get_path_to(part))
	area.set_meta("visual_path", area.get_path_to(visual))
	area.set_meta("open_direction", open_direction)
	area.set_meta("open_axis", "y")
	area.set_meta("open_angle_degrees", open_angle_degrees)
	part_closed_rotation[part.get_path()] = part.rotation
	return area


func _find_pointed_interactable() -> Area3D:
	var view := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("local_player")
	if view == null or (player and player.gameplay_ui_open()):
		return null
	var exclusions: Array = player._raycast_exclusions() if player else []
	var hit := CrosshairTarget.cast(view, interact_distance, exclusions)
	var area := hit.get("collider") as Area3D
	return area if area == shutter.target or area == side_door else null


func _set_hovered_interactable(area: Area3D) -> void:
	if hovered_interactable == area:
		return

	if hovered_interactable:
		_set_door_highlight(hovered_interactable, null)

	hovered_interactable = area

	if hovered_interactable:
		_set_door_highlight(hovered_interactable, highlight_material)


func _set_door_highlight(area: Area3D, material: Material) -> void:
	if area == shutter.target:
		shutter.set_door_overlay(material)
	else:
		_set_mesh_overlay_recursive(_get_interactable_visual(area), material)


func _drag_interactable(area: Area3D, drag_amount: float) -> void:
	if area == shutter.target:
		shutter.set_opening(shutter.opening + drag_amount * 0.006)
		if NetworkManager.is_online():
			_sync_shack_door.rpc(true, shutter.opening)
		return

	var part := _get_interactable_part(area)
	if part == null:
		return

	var open_direction := float(area.get_meta("open_direction", 1.0))
	var open_angle := deg_to_rad(float(area.get_meta("open_angle_degrees", 90.0)))
	var closed_rotation := part_closed_rotation.get(part.get_path(), part.rotation) as Vector3
	var current_open := _get_open_amount(part, closed_rotation, open_direction, open_angle)
	var target_open: float = clamp(current_open + drag_amount * 0.006, 0.0, 1.0)

	part.rotation = closed_rotation
	part.rotate_y(open_direction * open_angle * target_open)
	if NetworkManager.is_online():
		_sync_shack_door.rpc(false, part.rotation.y)


@rpc("any_peer", "call_remote", "reliable")
func _sync_shack_door(is_shutter: bool, value: float) -> void:
	if not is_finite(value):
		return
	if is_shutter:
		shutter.set_opening(value)
	else:
		var part := _get_interactable_part(side_door)
		if part:
			part.rotation.y = clampf(value, -TAU, TAU)


func _get_open_amount(part: Node3D, closed_rotation: Vector3, open_direction: float, open_angle: float) -> float:
	var delta := part.rotation.y - closed_rotation.y
	return clamp(delta / (open_direction * open_angle), 0.0, 1.0)


func _get_interactable_part(area: Area3D) -> Node3D:
	if not area.has_meta("part_path"):
		return null

	return area.get_node_or_null(area.get_meta("part_path")) as Node3D


func _get_interactable_visual(area: Area3D) -> Node3D:
	if not area.has_meta("visual_path"):
		return _get_interactable_part(area)

	return area.get_node_or_null(area.get_meta("visual_path")) as Node3D


func _create_hinge_pivot(area_name: String, part: Node3D, hinge_edge: String) -> Node3D:
	if part.get_parent() == null:
		return part

	var parent := part.get_parent() as Node3D
	var hinge_local := _get_hinge_local_point(part, hinge_edge)
	var hinge_parent_position := part.transform * hinge_local
	var part_global_transform := part.global_transform
	var pivot := Node3D.new()

	pivot.name = "%sHinge" % area_name
	pivot.transform = part.transform
	pivot.position = hinge_parent_position

	parent.add_child(pivot)
	part.get_parent().remove_child(part)
	pivot.add_child(part)
	part.global_transform = part_global_transform

	return pivot


func _get_hinge_local_point(part: Node3D, hinge_edge: String) -> Vector3:
	var bounds := _get_local_visual_bounds(part)
	var hinge := bounds.get_center()

	match hinge_edge:
		"min_x":
			hinge.x = bounds.position.x
		"max_x":
			hinge.x = bounds.position.x + bounds.size.x
		"min_z":
			hinge.z = bounds.position.z
		"max_z":
			hinge.z = bounds.position.z + bounds.size.z

	return hinge


func _get_local_visual_bounds(part: Node3D) -> AABB:
	if part is MeshInstance3D and (part as MeshInstance3D).mesh:
		return (part as MeshInstance3D).mesh.get_aabb()

	var bounds := AABB()
	var has_bounds := false
	for child in part.get_children():
		if not child is Node3D:
			continue

		var child_bounds := _get_local_visual_bounds(child as Node3D)
		var transformed_bounds := (child as Node3D).transform * child_bounds
		if has_bounds:
			bounds = bounds.merge(transformed_bounds)
		else:
			bounds = transformed_bounds
			has_bounds = true

	return bounds if has_bounds else AABB()


func _safe_collision_size(part: Node3D) -> Vector3:
	var bounds := _get_local_visual_bounds(part)
	var size := bounds.size.abs()
	return Vector3(maxf(size.x, 0.25), maxf(size.y, 0.25), maxf(size.z, 0.08))


func _get_meshes_recursive(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)

	for child in node.get_children():
		meshes.append_array(_get_meshes_recursive(child))

	return meshes


func _set_mesh_overlay_recursive(node: Node, material: Material) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = material

	for child in node.get_children():
		_set_mesh_overlay_recursive(child, material)
