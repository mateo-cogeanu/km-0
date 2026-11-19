extends Node
## Two copies of the drive (objects_net_check.gd): things in the world stay
## the same on both screens. A box one player opens is open for the other,
## with its contents; something taken out of it is seen in the taker's hands
## and then on the ground; a dropped can lands in the same place for both; a
## can one player carries is seen moving by the other; and two players can't
## grab the same can.

var role := ""
var arrived := {}
var other_said := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if role == "host":
		NetworkManager.create_lobby("Objects", "Hostie")
		while NetworkManager.players.size() < 2:
			await get_tree().process_frame
		NetworkManager.set_local_ready(true)
		while not NetworkManager.can_host_start():
			await get_tree().process_frame
		NetworkManager.start_game()
	else:
		await _seconds(1.5)
		NetworkManager.join_lobby("127.0.0.1", "Guesty")
		while not NetworkManager.players.has(multiplayer.get_unique_id()):
			await get_tree().process_frame
		await _seconds(0.5)
		NetworkManager.set_local_ready(true)
	while get_tree().current_scene == null or get_tree().current_scene.get_node_or_null("InfiniteRoad") == null:
		await get_tree().process_frame
	var world: Node3D = get_tree().current_scene
	await _seconds(3.0)
	await _barrier(1)
	var road: Node3D = world.get_node("InfiniteRoad")
	var me: CharacterBody3D = world.get_node(str(multiplayer.get_unique_id()))
	# Both walk to the same stations in the same order until one has a box.
	var box: Node3D
	var finds: Node3D
	for index in range(-5, -200, -1):
		if not road._has_stop(index):
			continue
		me.global_position = road._sample((index + 0.5) * road.segment_length, 3.0 if role == "host" else -3.0, 1.2)
		me.reset_physics_interpolation()
		var waited := 0.0
		while world.get_node_or_null("Finds_%d" % index) == null and waited < 8.0:
			await _seconds(0.2)
			waited += 0.2
		await _seconds(1.0)
		finds = world.get_node_or_null("Finds_%d" % index)
		if finds:
			box = finds.get_node_or_null("Cooler")
			if box == null:
				box = finds.get_node_or_null("Toolbox")
		if box:
			_say("at stop %d with %s" % [index, box.name])
			break
	await _barrier(2)
	# 1. The guest opens the box; both should see it open with its things out.
	if role == "join":
		box.open()
	await _seconds(2.0)
	var loot: RigidBody3D
	for item in box.items:
		if is_instance_valid(item):
			loot = item
			break
	_say("box open %s, first item %s visible %s" % [box.opened, loot.name if loot else "-", loot.is_visible_in_tree() if loot else false])
	await _barrier(3)
	# 2. The host takes it out and holds it; the guest sees it in their hands.
	if role == "host" and loot:
		me.global_position = loot.global_position + Vector3(0, 1.0, 1.0)
		me.reset_physics_interpolation()
		await _seconds(0.3)
		me._begin_grab_object(loot, loot.global_position)
	await _seconds(2.0)
	if loot:
		_say("loot held_by %s visible %s" % [loot.get_meta("held_by", "-"), loot.is_visible_in_tree()])
	await _barrier(4)
	if role == "host" and loot:
		me._drop_held_object()
	await _seconds(4.0)
	if loot:
		_say("loot after drop at %s (visible %s)" % [_v(loot.global_position), loot.is_visible_in_tree()])
		_tell.rpc("loot", loot.global_position)
	await _barrier(5)
	if loot and other_said.has("loot"):
		_say("loot gap between screens %.2f m" % loot.global_position.distance_to(other_said["loot"]))
	# 3. The host throws the stop's can; it should land in the same place.
	var can := finds.get_node_or_null("FuelCanister") as RigidBody3D
	if role == "host" and can:
		me.global_position = can.global_position + Vector3(0, 1.0, 1.0)
		me.reset_physics_interpolation()
		await _seconds(0.3)
		me._begin_grab_object(can, can.global_position)
		await _seconds(1.0)
		can.linear_velocity = Vector3(2.5, 2.0, -1.0)
		me._drop_held_object()
		can.linear_velocity = Vector3(2.5, 2.0, -1.0)
	await _seconds(6.0)
	if can:
		_tell.rpc("can", can.global_position)
	await _barrier(6)
	if can and other_said.has("can"):
		_say("thrown can gap between screens %.2f m (here %s)" % [can.global_position.distance_to(other_said["can"]), _v(can.global_position)])
	# 4. The guest carries the can; the host sees it move. The host can't grab it meanwhile.
	var start := can.global_position if can else Vector3.ZERO
	if role == "join" and can:
		me.global_position = can.global_position + Vector3(0, 1.0, 1.0)
		me.reset_physics_interpolation()
		await _seconds(0.3)
		me._begin_grab_object(can, can.global_position)
		await _seconds(0.5)
		me.global_position += Vector3(0, 0, 3.0)
		me.reset_physics_interpolation()
	await _seconds(2.0)
	if role == "host" and can:
		_say("host sees guest carry can %.2f m, host can grab it too: %s" % [can.global_position.distance_to(start), me._can_grab_body(can)])
	await _barrier(7)
	if role == "join" and can:
		me._drop_held_object()
	var spare := finds.get_node_or_null("SpareCanister")
	_say("spare canister here: %s" % (spare != null))
	await _seconds(2.0)
	await _barrier(8)
	get_tree().quit()


@rpc("any_peer", "call_remote", "reliable")
func _arrive(step: int) -> void:
	arrived[step] = true


@rpc("any_peer", "call_remote", "reliable")
func _tell(what: String, where: Vector3) -> void:
	other_said[what] = where


func _barrier(step: int) -> void:
	_arrive.rpc(step)
	var waited := 0.0
	while not arrived.has(step) and waited < 60.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if fmod(waited, 1.0) < get_process_delta_time():
			_arrive.rpc(step)


func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]


func _seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func _say(text: String) -> void:
	print("[%s] %s" % [role, text])
