extends Node

var role := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if role == "host":
		NetworkManager.create_lobby("SalvageTest", "Hostie")
		while NetworkManager.players.size() < 2:
			await get_tree().process_frame
		await _seconds(1.0)
		NetworkManager.set_local_ready(true)
		while not NetworkManager.can_host_start():
			await get_tree().process_frame
		NetworkManager.start_game("salvage")
	else:
		await _seconds(1.5)
		NetworkManager.join_lobby("127.0.0.1", "Guesty")
		while NetworkManager.players.size() < 2 or not NetworkManager.players.has(multiplayer.get_unique_id()):
			await get_tree().process_frame
		await _seconds(0.5)
		NetworkManager.set_local_ready(true)
	while get_tree().current_scene == null or get_tree().current_scene.name != "Salvage":
		await get_tree().process_frame
	var world: Node3D = get_tree().current_scene
	await _seconds(4.0)
	var me: CharacterBody3D = world.local_player()
	var other: CharacterBody3D
	for p in world.players():
		if p != me:
			other = p
	_say("story %s, players here %d, me %s other %s" % [NetworkManager.story, world.players().size(), me.name, other.name if other else "none"])
	# Both go to the V8 at the end of the street.
	var v8: Node3D = world.get_node("Flooded_6")
	var engine: RigidBody3D
	if role == "host":
		me.global_position = v8.global_position + Vector3(-2.0, 1.2, 0.6)
		me.reset_physics_interpolation()
		await _seconds(1.0)
		engine = v8.remove_installed_part(v8.removable_parts["engine"]["area"], true)
		await _seconds(0.5)
		me._begin_grab_object(engine, engine.global_position)
		NetworkManager.multiplayer.multiplayer_peer.get_peer(2) if false else null
		me.sync_held_object_state.rpc(engine.get_path(), true)
		await _seconds(2.0)
		_say("holding engine alone: dragging %s, height %.2f" % [me.dragging_heavy(), engine.global_position.y - world.ground_height(engine.global_position.x, engine.global_position.z)])
		await _seconds(3.0)
		_say("with helper: helped %s, dragging %s, height %.2f" % [me.carry_helped(), me.dragging_heavy(), engine.global_position.y - world.ground_height(engine.global_position.x, engine.global_position.z)])
		await _seconds(3.0)
		_say("helper let go: dragging %s" % me.dragging_heavy())
		me._drop_held_object()
		await _seconds(1.0)
		# Grab the guest, then make a noise elsewhere.
		world.clock = 60.0
		var listener: Node3D = world.listener
		listener.position = Vector3(other.global_position.x, listener.position.y, other.global_position.z - 2.0)
		listener._grab(other, 0.5)
		await _seconds(1.5)
		_say("host sees guest grabbed: %s" % listener.is_taken(other))
		world.noise.add_event(Vector3(-6, -5, other.global_position.z + 25.0), 1.0)
		await _seconds(1.0)
		_say("after decoy: creature state %s" % listener.State.keys()[listener.state])
		await _seconds(2.0)
		world._end_everywhere("filled")
		await _seconds(2.0)
		_say("host ended: %s" % world.ended)
	else:
		await _seconds(1.0)
		me.global_position = v8.global_position + Vector3(-2.0, 1.2, -0.8)
		me.reset_physics_interpolation()
		await _seconds(3.0)
		for body in get_tree().get_nodes_in_group("vehicle_loose_part"):
			if String(body.get_meta("vehicle_part_type", "")) == "engine":
				engine = body
		_say("guest sees loose engine: %s held_by %s" % [engine != null, engine.get_meta("held_by") if engine and engine.has_meta("held_by") else "-"])
		if engine:
			me.global_position = engine.global_position + Vector3(0.9, 1.0, 0.0)
			me.reset_physics_interpolation()
			await _seconds(0.3)
			me._start_helping(engine)
			_say("guest started helping: %s, gap %.2f" % [me.helping_object != null, engine.global_position.distance_to(me.camera.global_position)])
		await _seconds(2.7)
		_say("guest helping: %s" % (me.helping_object != null))
		me._stop_helping()
		await _seconds(4.5)
		var listener: Node3D = world.listener
		_say("guest grabbed: locked %s, creature seen %.1f m away (host puts it 2 m)" % [me.ending_locked, listener.global_position.distance_to(me.global_position)])
		await _seconds(1.2)
		_say("guest after decoy: locked %s" % me.ending_locked)
		await _seconds(3.5)
		_say("guest ended: %s" % world.ended)
	await _seconds(1.0)
	get_tree().quit()


func _say(text: String) -> void:
	print("[%s] %s" % [role, text])


func _seconds(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout
