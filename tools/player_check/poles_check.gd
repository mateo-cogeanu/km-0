extends Node
## Telephone poles along the road: a look down the road by day, and a check
## that no pole stands on a stop or its driveway.

func _ready() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var menu := world.get_node_or_null("PauseMenu")
	if menu and menu.has_method("_close_tutorial"):
		menu._close_tutorial()
	var road: Node3D = world.get_node("InfiniteRoad")
	var cycle := world.get_node_or_null("DayNightCycle")
	if cycle:
		cycle.time_of_day = 0.4
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	var dir := OS.get_environment("KM0_CHECK_DIR")
	for spot: Array in [[-260.0, "poles_road"], [-1500.0, "poles_far"]]:
		var at: Vector3 = road._sample(spot[0], 1.6, 1.1)
		player.global_position = at
		await _frames(40)
		var ahead: Vector3 = road._sample(spot[0] - 60.0, -2.0, 1.4)
		player.look_at(ahead, Vector3.UP)
		player.rotation.x = 0.0
		player.rotation.z = 0.0
		player.look_rotation_x = 0.05
		player.head.rotation.x = 0.05
		await _frames(30)
		get_viewport().get_texture().get_image().save_png(dir.path_join(spot[1] + ".png"))
	# Every pole from the workshop to the house, against every stop on its side.
	var clashes := 0
	var count := 0
	var z := -42.0
	while z > road.HOUSE_APPROACH:
		if road._has_pole(z):
			count += 1
			var index := floori(z / road.segment_length)
			for near in range(index - 1, index + 2):
				if road._has_stop(near) and road._stop_side(near) < 0.0:
					var centre: float = (near + 0.5) * road.segment_length
					if absf(z - centre) < 20.0:
						clashes += 1
		z -= 42.0
	print("poles: ", count, " clashes with stops: ", clashes, " poles built near you: ", world.find_children("Pole", "MeshInstance3D", true, false).size())
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
