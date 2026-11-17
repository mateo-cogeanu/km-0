extends Node
## Wrecks by the road, a wrecked station, and the fuel range on the dashboard.

var world: Node
var player: CharacterBody3D
var road: Node3D


func _ready() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var guide := world.get_node_or_null("TutorialGuide")
	if guide:
		guide.queue_free()
	var cycle := world.get_node_or_null("DayNightCycle")
	cycle.time_of_day = 0.42
	cycle.day_length_seconds = 0.0
	road = world.get_node("InfiniteRoad")
	road.begin_streaming()
	player = get_tree().get_first_node_in_group("local_player")
	var dir := OS.get_environment("KM0_CHECK_DIR")
	var wrecks: Node = road.wrecks
	var found := []
	for index in range(-9, -160, -1):
		if wrecks.has_wreck(index):
			found.append(index)
	print("wrecks in first 160 segments: ", found.size(), " at ", found.slice(0, 8))
	var first: int = found[0]
	player.global_position = road._sample((first + 0.5) * road.segment_length + 25.0, 0.0, 1.2)
	await _frames(40)
	var wreck := road.get_node_or_null("Road_%d/Wreck" % first) as Node3D
	var finds := world.get_node_or_null("WreckFinds_%d" % first)
	print("first wreck built: ", wreck != null, " finds: ", finds.get_children().map(func(n: Node) -> String: return n.get_class() + ":" + str(n.get("kind") if n.get("kind") != null else n.name)) if finds else [])
	print("note on it: ", wreck.find_children("*", "Node3D", false, false).filter(func(n: Node) -> bool: return n.get("note_id") != null).map(func(n: Node) -> String: return n.note_id))
	_face(wreck.global_position + Vector3.UP * 0.6)
	player.global_position = wreck.global_position + (player.global_position - wreck.global_position).normalized() * 7.0 + Vector3.UP * 1.2
	await _frames(5)
	_face(wreck.global_position + Vector3.UP * 0.5)
	for n in 2:
		await _frames(10)
		get_viewport().get_texture().get_image().save_png(dir + "/wreck.png")
	# A wrecked station.
	var wrecked := 0
	for index in range(-15, -400, -1):
		if road._has_stop(index) and -floori(float(index) / 12.0) >= 4 and posmod(hash("wrecked:%d" % index), 4) == 0:
			wrecked = index
			break
	print("first wrecked station segment ", wrecked)
	var z: float = (wrecked + 0.5) * road.segment_length
	player.global_position = road._sample(z + 60.0, 0.0, 1.2)
	await _frames(20)
	player.global_position = road._sample(z, 0.0, 1.2)
	await _frames(40)
	var stop: Node3D = road.stops.get(wrecked)
	print("station spawned: ", stop != null)
	if stop:
		var front := stop.to_global(Vector3(0, 0, 11))
		player.global_position = Vector3(front.x, 1.2, front.z)
		await _frames(5)
		_face(stop.to_global(Vector3(0, 0, 5.5)))
		player.look_rotation_x = -0.55
		player.head.rotation.x = -0.55
		for n in 2:
			await _frames(10)
			get_viewport().get_texture().get_image().save_png(dir + "/wrecked_station.png")
		var can_fuel := []
		for can in world.get_node("Finds_%d" % wrecked).get_children():
			if "fuel_amount" in can:
				can_fuel.append(snappedf(can.fuel_amount, 0.1))
		print("wrecked station petrol: ", can_fuel)
	# Fuel range on the dashboard.
	var car: Node3D
	for c in get_tree().get_nodes_in_group("drivable"):
		if "removable_parts" in c:
			car = c
	car.fuel_amount = 7.5
	print("fuel text: ", car.get_fuel_text())
	get_tree().quit()


func _face(at: Vector3) -> void:
	var to: Vector3 = at - player.camera.global_position
	player.rotation.y = atan2(-to.x, -to.z)
	player.look_rotation_x = atan2(to.y, Vector2(to.x, to.z).length())
	player.head.rotation.x = player.look_rotation_x


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
