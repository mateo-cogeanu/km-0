extends Node
## Two copies on the road together: the host's story decides where the road
## ends for both, both clocks agree, and a station the host spawns appears on
## the guest's screen too.

var role := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if role == "host":
		NetworkManager.create_lobby("Story", "Hostie")
		while NetworkManager.players.size() < 2:
			await get_tree().process_frame
		NetworkManager.set_local_ready(true)
		while not NetworkManager.can_host_start():
			await get_tree().process_frame
		NetworkManager.start_game()
	else:
		await _seconds(1.0)
		NetworkManager.join_lobby("127.0.0.1", "Guesty")
		while not NetworkManager.players.has(multiplayer.get_unique_id()):
			await get_tree().process_frame
		NetworkManager.set_local_ready(true)
	while get_tree().current_scene == null or get_tree().current_scene.get_node_or_null("InfiniteRoad") == null:
		await get_tree().process_frame
	var world: Node3D = get_tree().current_scene
	var road: Node3D = world.get_node("InfiniteRoad")
	var cycle: Node = world.get_node("DayNightCycle")
	while not world.started:
		await get_tree().process_frame
	await _seconds(4.0)
	var me: CharacterBody3D = world.get_node(str(multiplayer.get_unique_id()))
	_say("started, locked %s, time %.3f" % [me.ending_locked, cycle.time_of_day])
	# Both walk out to the first station along the road.
	var index := -1
	for i in range(-3, -200, -1):
		if road._has_stop(i):
			index = i
			break
	me.global_position = road._sample((index + 0.5) * road.segment_length, 3.0 if role == "host" else -3.0, 1.2)
	me.reset_physics_interpolation()
	await _seconds(6.0)
	_say("station %d here: %s, finds %d" % [index, road.stops.has(index), road.stops[index].get_child_count() if road.stops.has(index) else 0])
	if role == "host":
		var story: Dictionary = road.RoadEndHouse.story
		story["heard"] = {"0": true, "1": true, "2": true, "3": true, "4": true, "5": true}
		story["nights"] = 9
	await _seconds(3.0)
	_say("house_z %s, time %.3f" % [str(road.RoadEndHouse.story.get("house_z", "none")), cycle.time_of_day])
	await _seconds(3.0)
	get_tree().quit()


func _seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func _say(text: String) -> void:
	print("[%s] %s" % [role, text])
