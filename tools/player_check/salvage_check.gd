extends Node
## The Salvage Run, solo: the camp, the street, the creature hunting noise and
## grabbing, an engine dragged alone, the contract on the pallet.

var world: Node3D
var player: CharacterBody3D
var dir := ""


func _ready() -> void:
	dir = OS.get_environment("KM0_CHECK_DIR")
	NetworkManager.story = "salvage"
	world = load("res://scenes/salvage.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(90)
	player = world.local_player()
	print("player: ", player != null, " at ", player.global_position.snapped(Vector3.ONE * 0.1), " cars: ", get_tree().get_nodes_in_group("drivable").size())
	await _shot("salvage_camp")
	# Down into the street, looking along it.
	_place(Vector3(10.5, KERB(), -60), Vector3(0, -5, -100))
	await _frames(40)
	await _shot("salvage_street")
	var listener: Node3D = world.listener
	world.clock = 40.0
	# Wade in and splash about: it should come.
	_place(Vector3(2.0, -4.9, -80), Vector3(0, -5, -120))
	var start: Vector3 = listener.global_position
	var heard_state := []
	for i in 1200:
		player.velocity = Vector3(0, 0, -player.move_speed * 1.5)
		player.remote_velocity = player.velocity
		await get_tree().process_frame
		if i % 60 == 0:
			heard_state.append([listener.State.keys()[listener.state], snappedf(listener.global_position.distance_to(player.global_position), 0.1)])
		if listener.state == listener.State.GRAB:
			break
	print("noise while wading: ", snappedf(world.noise.player_level(player), 0.01), " listener from ", start.snapped(Vector3.ONE), " states ", heard_state)
	print("grabbed: ", listener.state == listener.State.GRAB, " victim is player: ", listener.victim == player, " locked: ", player.ending_locked)
	await _frames(20)
	_look_at_creature()
	await _shot("salvage_grab")
	# A loud noise elsewhere makes it let go.
	world.noise.add_event(Vector3(-6, -5, -130), 1.0)
	await _frames(10)
	print("after decoy: state ", listener.State.keys()[listener.state], " player free: ", not player.ending_locked)
	# Listening pose, from the pavement.
	listener.state = listener.State.LISTEN
	listener.state_time = -30.0
	listener.position = Vector3(5.0, listener.position.y, -95)
	_place(Vector3(11.0, KERB(), -88), listener.global_position + Vector3(0, 0.6, 0))
	await _frames(90)
	_place(Vector3(11.0, KERB(), -88), listener.global_position + Vector3(0, 0.6, 0))
	await _shot("salvage_listening")
	# Pull the V8 and drag it alone.
	var v8: Node3D = world.get_node("Flooded_6")
	var engine: RigidBody3D = v8.remove_installed_part(v8.removable_parts["engine"]["area"], true)
	print("v8 engine out: ", engine != null, " variant ", engine.get_meta("engine_variant") if engine else "")
	listener.position = Vector3(0, listener.position.y, -60)
	listener.state = listener.State.ROAM
	_place(engine.global_position + Vector3(0, 1.0, 2.0), engine.global_position)
	await _frames(5)
	player._begin_grab_object(engine, engine.global_position)
	var from := engine.global_position
	for i in 120:
		Input.action_press("move_forward") if InputMap.has_action("move_forward") else null
		player.velocity = Vector3(0, 0, 3.0)
		await get_tree().process_frame
	print("dragging alone: ", player.dragging_heavy(), " engine height above ground ", snappedf(engine.global_position.y - world.ground_height(engine.global_position.x, engine.global_position.z), 0.01),
		" moved ", snappedf(from.distance_to(engine.global_position), 0.1), " noise ", snappedf(world.noise.local_level, 0.01))
	player._drop_held_object()
	# Contract: put parts on the pallet.
	var parts := []
	for car_name in ["Flooded_1", "Flooded_2", "Flooded_3"]:
		var car: Node3D = world.get_node(car_name)
		for slot in (["battery", "radiator"] if car_name == "Flooded_1" else ["battery"]):
			parts.append(car.remove_installed_part(car.removable_parts[slot]["area"], true))
	parts.append(engine)
	for i in parts.size():
		var part: RigidBody3D = parts[i]
		part.global_position = world.PALLET + Vector3(-0.8 + (i % 2) * 1.2, 0.6 + (i / 2) * 0.5, -0.5 + (i % 2) * 0.8)
		part.linear_velocity = Vector3.ZERO
	_place(Vector3(3, 1.05, 14), world.PALLET)
	await _frames(90)
	print("delivered: ", world.delivered, " met: ", world.contract_met())
	await _shot("salvage_pallet")
	await _frames(30)
	print("ended: ", world.ended)
	await _shot("salvage_end")
	get_tree().quit()


func KERB() -> float:
	return -4.75 + 1.0


func _place(at: Vector3, look: Vector3) -> void:
	player.global_position = at
	player.reset_physics_interpolation()
	var to: Vector3 = look - (at + Vector3.UP * 0.7)
	player.rotation.y = atan2(-to.x, -to.z)
	player.look_rotation_x = atan2(to.y, Vector2(to.x, to.z).length())
	player.head.rotation.x = player.look_rotation_x


func _look_at_creature() -> void:
	var c: Vector3 = world.listener.global_position
	var to: Vector3 = c - player.camera.global_position
	player.rotation.y = atan2(-to.x, -to.z)


func _shot(title: String) -> void:
	for n in 2:
		await _frames(8)
		get_viewport().get_texture().get_image().save_png(dir + "/" + title + ".png")


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
