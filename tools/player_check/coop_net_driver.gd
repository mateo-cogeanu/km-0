extends Node
## Two copies of the game play the road drive together (see coop_net_check.gd):
## the host flips the lobby's story to the Salvage Run and back, the guest
## sees each pick and has to ready again, then the drive starts and the two
## of them carry an engine out of the workshop car.

var role := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if role == "host":
		NetworkManager.create_lobby("DriveTest", "Hostie")
		while NetworkManager.players.size() < 2:
			await get_tree().process_frame
		await _seconds(1.0)
		NetworkManager.set_local_ready(true)
		while not NetworkManager.can_host_start():
			await get_tree().process_frame
		NetworkManager.set_lobby_story("salvage")
		_say("picked salvage: can start now %s (guest must ready again)" % NetworkManager.can_host_start())
		await _seconds(1.5)
		NetworkManager.set_lobby_story("road")
		await _seconds(0.5)
		while not NetworkManager.can_host_start():
			await get_tree().process_frame
		_say("starting %s" % NetworkManager.lobby_story)
		NetworkManager.start_game()
	else:
		await _seconds(1.5)
		NetworkManager.join_lobby("127.0.0.1", "Guesty")
		while NetworkManager.players.size() < 2 or not NetworkManager.players.has(multiplayer.get_unique_id()):
			await get_tree().process_frame
		await _seconds(0.5)
		NetworkManager.set_local_ready(true)
		var seen := []
		while seen.size() < 2:
			await get_tree().process_frame
			if (seen.is_empty() and NetworkManager.lobby_story == "salvage") or (seen.size() == 1 and NetworkManager.lobby_story == "road"):
				seen.append(NetworkManager.lobby_story)
				var me_ready := bool(NetworkManager.players[multiplayer.get_unique_id()].get("ready", false))
				_say("guest sees story %s, still ready %s" % [NetworkManager.lobby_story, me_ready])
				await _seconds(0.3)
				NetworkManager.set_local_ready(true)
	while get_tree().current_scene == null or get_tree().current_scene.get_node_or_null("InfiniteRoad") == null:
		await get_tree().process_frame
	var world: Node3D = get_tree().current_scene
	await _seconds(4.0)
	var me: CharacterBody3D = world.get_node(str(multiplayer.get_unique_id()))
	_say("story %s, cars %d" % [NetworkManager.story, get_tree().get_nodes_in_group("drivable").size()])
	var car: Node3D = world.get_node("Car_1")
	var engine: RigidBody3D
	if role == "host":
		me.global_position = car.global_position + car.global_basis.x * 1.8 + Vector3.UP * 1.0
		me.reset_physics_interpolation()
		await _seconds(1.0)
		if car.removable_parts["engine"]["installed"]:
			engine = car.remove_installed_part(car.removable_parts["engine"]["area"], true)
		else:
			for body in get_tree().get_nodes_in_group("vehicle_loose_part"):
				if String(body.get_meta("vehicle_part_type", "")) == "engine":
					engine = body
		await _seconds(0.5)
		me._begin_grab_object(engine, engine.global_position)
		me.sync_held_object_state.rpc(engine.get_path(), true)
		await _seconds(2.0)
		_say("holding engine alone: heavy %s, dragging %s, height above feet %.2f" % [me.is_heavy(engine), me.dragging_heavy(), engine.global_position.y - me.global_position.y])
		await _seconds(3.0)
		_say("with helper: helped %s, dragging %s, height above feet %.2f" % [me.carry_helped(), me.dragging_heavy(), engine.global_position.y - me.global_position.y])
		await _seconds(3.0)
		_say("helper let go: dragging %s" % me.dragging_heavy())
		me._drop_held_object()
		await _seconds(6.0)
	else:
		await _seconds(1.0)
		me.global_position = car.global_position - car.global_basis.x * 1.8 + Vector3.UP * 1.0
		me.reset_physics_interpolation()
		await _seconds(3.0)
		for body in get_tree().get_nodes_in_group("vehicle_loose_part"):
			if String(body.get_meta("vehicle_part_type", "")) == "engine" and body.has_meta("held_by"):
				engine = body
		_say("guest sees held engine: %s" % (engine != null))
		if engine:
			me.global_position = engine.global_position + Vector3(0.9, 1.0, 0.0)
			me.reset_physics_interpolation()
			await _seconds(0.3)
			me._start_helping(engine)
			for k in 9:
				await _seconds(0.3)
			_say("guest helping: %s" % (me.helping_object != null))
			me._stop_helping()
		await _seconds(4.0)
	await _seconds(1.0)
	get_tree().quit()


func _seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func _say(text: String) -> void:
	print("[%s] %s" % [role, text])
