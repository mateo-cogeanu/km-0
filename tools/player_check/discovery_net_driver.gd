extends Node
## The way people actually start co-op: the guest finds the host's lobby in
## the list (no typed address), joins, both ready, the drive starts. Then each
## side checks it can see the other player, and that the other player moves.

var role := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if role == "host":
		NetworkManager.create_lobby("Found", "Hostie")
		while NetworkManager.players.size() < 2:
			await get_tree().process_frame
		_say("guest joined: %s" % NetworkManager.players)
		NetworkManager.set_local_ready(true)
		var waited := 0.0
		while not NetworkManager.can_host_start() and waited < 20.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		NetworkManager.start_game()
	else:
		var waited := 0.0
		while NetworkManager.discovered_lobbies.is_empty() and waited < 12.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		_say("guest found lobbies after %.1f s: %s" % [waited, NetworkManager.discovered_lobbies.values().map(func(l): return "%s @ %s" % [l.get("name"), l.get("address")])])
		if NetworkManager.discovered_lobbies.is_empty():
			get_tree().quit(1)
			return
		var lobby: Dictionary = NetworkManager.discovered_lobbies.values()[0]
		NetworkManager.join_lobby(str(lobby["address"]), "Guesty")
		waited = 0.0
		while not NetworkManager.players.has(multiplayer.get_unique_id()) and waited < 12.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		_say("guest in lobby after %.1f s: %s" % [waited, NetworkManager.players.has(multiplayer.get_unique_id())])
		NetworkManager.set_local_ready(true)
	var waited_scene := 0.0
	while (get_tree().current_scene == null or get_tree().current_scene.get_node_or_null("InfiniteRoad") == null) and waited_scene < 60.0:
		await get_tree().process_frame
		waited_scene += get_process_delta_time()
	var world: Node3D = get_tree().current_scene
	await _seconds(5.0)
	var me: CharacterBody3D = world.get_node_or_null(str(multiplayer.get_unique_id()))
	var other: CharacterBody3D
	for p in get_tree().get_nodes_in_group("local_player") + world.get_children():
		if p is CharacterBody3D and p != me and p.name.is_valid_int():
			other = p
	_say("in game: me %s, other %s, other visible %s, distance %.1f" % [me != null, other != null, other.is_visible_in_tree() if other else false, me.global_position.distance_to(other.global_position) if me and other else -1.0])
	var start := other.global_position if other else Vector3.ZERO
	if role == "host":
		me.global_position += Vector3(4, 0, 0)
		me.reset_physics_interpolation()
	await _seconds(3.0)
	if role == "join" and other:
		_say("guest sees host move: %.2f m" % other.global_position.distance_to(start))
	if role == "join":
		me.global_position += Vector3(0, 0, 4)
		me.reset_physics_interpolation()
	await _seconds(3.0)
	if role == "host" and other:
		_say("host sees guest move: %.2f m" % other.global_position.distance_to(start))
	await _seconds(2.0)
	get_tree().quit()


func _seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func _say(text: String) -> void:
	print("[%s] %s" % [role, text])
