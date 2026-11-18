extends Node
## Horn, door slams and cargo in the Salvage Run.

func _ready() -> void:
	NetworkManager.story = "salvage"
	var world: Node3D = load("res://scenes/salvage.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	world.clock = 60.0
	var player: CharacterBody3D = world.local_player()
	var truck: RigidBody3D = world.get_node("Truck")
	var listener: Node3D = world.listener
	# Horn, from the bottom of the hill, with it 60 m off.
	truck.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, world.FLOOR_Y + 0.5, -46))
	truck.reset_physics_interpolation()
	listener.position = Vector3(0, listener.position.y, -105)
	listener.state = listener.State.ROAM
	listener.wander_wait = 99.0
	listener.target = listener.position
	player._enter_vehicle(truck)
	await _frames(60)
	var ev := InputEventKey.new()
	ev.keycode = KEY_H
	ev.pressed = true
	player._unhandled_input(ev)
	await _frames(30)
	print("horn: honking %s, noise %.2f, creature %s heading to %s" % [truck.honking, world.noise.vehicle_level(truck), listener.State.keys()[listener.state], listener.target.snapped(Vector3.ONE)])
	ev.pressed = false
	player._unhandled_input(ev)
	await _frames(5)
	print("horn released: honking %s, noise %.2f" % [truck.honking, world.noise.vehicle_level(truck)])
	player._exit_vehicle()
	listener.position = Vector3(0, listener.position.y, -140)
	listener.state = listener.State.ROAM
	# Doors: a slam, then easing one shut.
	var car: Node3D = world.get_node("Flooded_2")
	var door := car.get_node("DoorFL") as Area3D
	car._drag_interactable(door, 200.0)
	await _frames(3)
	world.noise.events.clear()
	car._drag_interactable(door, -200.0)
	await _frames(2)
	print("slam: events %s" % [world.noise.events.map(func(e: Dictionary) -> float: return snappedf(e["level"], 0.01))])
	car._drag_interactable(door, 200.0)
	await _frames(3)
	world.noise.events.clear()
	for i in 30:
		car._drag_interactable(door, -6.0)
		await get_tree().process_frame
	print("eased shut: events %s" % [world.noise.events.map(func(e: Dictionary) -> float: return snappedf(e["level"], 0.01))])
	# Cargo: load two batteries, a radiator and the V8 onto the truck, drive up.
	var parts: Array[RigidBody3D] = []
	for pick in [["Flooded_1", "battery"], ["Flooded_3", "battery"], ["Flooded_1", "radiator"], ["Flooded_6", "engine"]]:
		var donor: Node3D = world.get_node(pick[0])
		parts.append(donor.remove_installed_part(donor.removable_parts[pick[1]]["area"], true))
	var spots := [Vector3(-0.4, 1.45, 0.4), Vector3(0.4, 1.45, 0.4), Vector3(0, 1.45, -0.4), Vector3(0, 1.0, 1.9)]
	for i in parts.size():
		parts[i].global_position = truck.to_global(spots[i])
		await _frames(1)
		print("loaded %s: %s" % [parts[i].get_meta("vehicle_part_type"), truck.weld_object(parts[i])])
	player._enter_vehicle(truck)
	var start := truck.global_position
	if not InputMap.has_action("Throttle"):
		InputMap.add_action("Throttle")
	await _frames(120)
	Input.action_press("Throttle")
	var tilt := 0.0
	for i in 1500:
		await get_tree().physics_frame
		tilt = maxf(tilt, absf(truck.global_rotation.x))
		if truck.global_position.z > 15.0:
			break
	Input.action_release("Throttle")
	print("steepest pitch %.1f deg, speed %.1f m/s" % [rad_to_deg(tilt), truck.linear_velocity.length()])
	print("drove from %s to %s, parts still loaded: %d of 4" % [start.snapped(Vector3.ONE), truck.global_position.snapped(Vector3.ONE),
		parts.filter(func(p: RigidBody3D) -> bool: return is_instance_valid(p) and p.has_meta("welded_vehicle")).size()])
	Input.action_press("Brakes") if InputMap.has_action("Brakes") else null
	truck.linear_velocity = Vector3.ZERO
	truck.angular_velocity = Vector3.ZERO
	await _frames(60)
	player._exit_vehicle()
	for part in parts:
		truck.unweld_object(part)
		part.linear_velocity = Vector3.ZERO
		part.global_position = world.PALLET + Vector3(randf_range(-0.6, 0.6), 0.8 + parts.find(part) * 0.4, randf_range(-0.6, 0.6))
	await _frames(90)
	for part in parts:
		print("  ", part.get_meta("vehicle_part_type"), " at ", part.global_position.snapped(Vector3.ONE * 0.1), " parent ", part.get_parent().name, " layer ", part.collision_layer, " frozen ", part.freeze, " metas ", part.get_meta_list())
	print("unloaded onto pallet: ", world.delivered, " met ", world.contract_met())
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
