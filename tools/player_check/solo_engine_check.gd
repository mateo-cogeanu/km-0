extends Node
## Playing alone on the road, you lift an engine yourself (two-person carrying
## is for co-op).

func _ready() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 90:
		await get_tree().process_frame
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	var car: Node3D = world.get_node("Car")
	player.global_position = car.global_position + car.global_basis.x * 1.8 + Vector3.UP * 1.0
	player.reset_physics_interpolation()
	var engine: RigidBody3D
	if car.removable_parts["engine"]["installed"]:
		engine = car.remove_installed_part(car.removable_parts["engine"]["area"], true)
	else:
		for body in get_tree().get_nodes_in_group("vehicle_loose_part"):
			if String(body.get_meta("vehicle_part_type", "")) == "engine":
				engine = body
	for i in 20:
		await get_tree().process_frame
	player._begin_grab_object(engine, engine.global_position)
	for i in 120:
		await get_tree().process_frame
	print("solo: heavy %s, dragging %s, height above feet %.2f" % [player.is_heavy(engine), player.dragging_heavy(), engine.global_position.y - player.global_position.y])
	get_tree().quit()
