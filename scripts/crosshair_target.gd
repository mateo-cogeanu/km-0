extends RefCounted


static func cast(view: Camera3D, distance: float, exclusions: Array = []) -> Dictionary:
	var center := view.get_viewport().get_visible_rect().size * 0.5
	var start := view.project_ray_origin(center)
	var end := start + view.project_ray_normal(center) * distance
	var query := PhysicsRayQueryParameters3D.create(start, end, 1 | 2 | 4 | 8 | 16, exclusions)
	query.collide_with_areas = true
	query.hit_from_inside = true
	var space := view.get_world_3d().direct_space_state
	var hit := _visible_hit(space, query)
	if hit.is_empty() or not hit.collider.is_in_group("drivable"):
		return hit

	# The chassis is a simple physics box. Allow visible exterior targets on that
	# car, while preserving the body hit for anything hidden behind the car.
	query.exclude = query.exclude + [hit.collider.get_rid()]
	var detail := _visible_hit(space, query)
	if not detail.is_empty() and detail.collider is Area3D and detail.collider.get_parent() == hit.collider:
		var vehicle: Node3D = hit.collider
		var target: Area3D = detail.collider
		var depth := (detail.position as Vector3).distance_to(hit.position)
		var from_above := (vehicle.global_position - start).normalized().dot(Vector3.DOWN) > 0.4
		var engine_bay: bool = target.get_meta("part_type", "") in ["engine", "battery", "radiator"]
		var visible_bay: bool = engine_bay and from_above and vehicle.can_target_part(target)
		var accessible_seat: bool = target.is_in_group("vehicle_seat") and vehicle.can_enter_from_position(start)
		if depth < 0.3 or visible_bay or accessible_seat:
			return detail
	return hit


static func _visible_hit(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D) -> Dictionary:
	var hit := space.intersect_ray(query)
	while not hit.is_empty() and hit.collider is Area3D and hit.collider.is_in_group("vehicle_removable_part"):
		if hit.collider.get_parent().can_target_part(hit.collider):
			break
		query.exclude = query.exclude + [hit.collider.get_rid()]
		hit = space.intersect_ray(query)
	return hit
