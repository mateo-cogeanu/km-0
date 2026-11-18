extends Node
## The single-player art in one pass: the workshop, a station of each kind,
## the relay tower stop, the house at the end of the road (inside and out),
## the stranger's cabin, and the roadside. Screenshots into KM0_CHECK_DIR, then
## frame time at three places (lower is cooler). KM0_PERF=0 skips timing.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")

var world: Node
var player: CharacterBody3D
var road: Node3D
var dir := OS.get_environment("KM0_CHECK_DIR")


func _ready() -> void:
	RoadEndHouse.seen = false
	RoadEndHouse.story = {}
	world = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var guide := world.get_node_or_null("TutorialGuide")
	if guide:
		guide.queue_free()
	var menu := world.get_node_or_null("PauseMenu")
	if menu and menu.has_method("_close_tutorial"):
		menu._close_tutorial()
	var cycle := world.get_node_or_null("DayNightCycle")
	cycle.time_of_day = 0.4
	cycle.day_length_seconds = 0.0
	road = world.get_node("InfiniteRoad")
	road.begin_streaming()
	player = get_tree().get_first_node_in_group("local_player")
	player.set_physics_process(false)

	# The workshop you start in.
	var shack: Node3D = world.get_node("Shack")
	await _view(shack.to_global(Vector3(-4.5, 1.7, 13.0)), shack.to_global(Vector3(-0.3, 1.8, 0.0)), "workshop")
	await _view(shack.to_global(Vector3(-2.2, 1.6, 3.4)), shack.to_global(Vector3(1.6, 1.1, -2.8)), "workshop_inside")

	# One station of each kind, and the one with the relay tower.
	var found := {}
	var tower := 0
	for index in range(-15, -400, -1):
		if not road._has_stop(index):
			continue
		var variant := posmod(hash("building:%d" % index), 4)
		if not found.has(variant):
			found[variant] = index
		if tower == 0 and floori(index / 12.0) == -3:
			tower = index
	print("stations: ", found, " tower ", tower)
	var shown := found.values()
	shown.append(tower)
	for i in shown.size():
		var index: int = shown[i]
		var stop := await _stop(index)
		if stop == null:
			print("no station at ", index)
			continue
		var title := "tower" if i == shown.size() - 1 else "station_%d" % (posmod(hash("building:%d" % index), 4))
		await _view(stop.to_global(Vector3(-5.0, 1.7, 14.0)), stop.to_global(Vector3(-0.5, 1.9, 0.0)), title)
		if i == 0:
			await _view(stop.to_global(Vector3(-1.5, 1.6, 3.2)), stop.to_global(Vector3(1.4, 1.0, -2.6)), title + "_inside")
			await _view(stop.to_global(Vector3(9.0, 1.7, 6.0)), stop.to_global(Vector3(0.0, 1.6, -0.5)), title + "_side")
		if i == 1 and OS.get_environment("KM0_PERF") != "0":
			await _perf("station", stop.to_global(Vector3(-5.0, 1.7, 14.0)), stop.to_global(Vector3(-0.5, 1.9, 0.0)))

	# The roadside: poles, a KM post, the scrub.
	var z := -12 * 80.0 + 40.0
	await _view(road._sample(z + 30.0, 2.4, 1.7), road._sample(z - 40.0, -2.0, 1.4), "roadside")
	if OS.get_environment("KM0_PERF") != "0":
		await _perf("road", road._sample(-300.0, 1.6, 1.7), road._sample(-380.0, 0.0, 1.6))

	# The stranger's cabin, back past where the road begins.
	var cabin: Node3D = road.get_node("StrangerHouse")
	await _view(cabin.to_global(Vector3(-4.0, 1.7, 11.0)), cabin.to_global(Vector3(0, 1.6, 0)), "cabin")
	await _view(cabin.to_global(Vector3(1.6, 1.6, 1.4)), cabin.to_global(Vector3(-1.4, 1.0, -1.4)), "cabin_inside")

	# The house at the end of the road: a stand-in built away from the road, so
	# nothing of the ending starts.
	var house := RoadEndHouse.new()
	house.prop_only = true
	house.name = "HouseForPhotos"
	world.add_child(house)
	house.global_position = Vector3(400.0, 0.0, -300.0)
	await _frames(10)
	await _view(house.to_global(Vector3(-6.0, 1.7, 15.0)), house.to_global(Vector3(0, 2.8, 0)), "house")
	await _view(house.to_global(Vector3(9.0, 1.7, -9.0)), house.to_global(Vector3(0, 2.4, 0)), "house_back")
	cycle.time_of_day = 0.02
	await _frames(30)
	await _view(house.to_global(Vector3(-2.2, 1.6, 2.6)), house.to_global(Vector3(1.6, 1.4, -2.4)), "house_inside")
	await _view(house.to_global(Vector3(-0.5, 1.6, -2.4)), house.to_global(Vector3(-2.0, 1.3, 3.4)), "house_inside_front")
	if OS.get_environment("KM0_PERF") != "0":
		await _perf("house_inside", house.to_global(Vector3(-2.2, 1.6, 2.6)), house.to_global(Vector3(1.6, 1.4, -2.4)))
	get_tree().quit()


func _stop(index: int) -> Node3D:
	var z: float = (index + 0.5) * road.segment_length
	player.global_position = road._sample(z, 0.0, 1.2)
	for n in 40:
		await get_tree().process_frame
		if road.stops.has(index):
			break
	await _frames(10)
	return road.stops.get(index)


func _view(from: Vector3, at: Vector3, title: String) -> void:
	player.global_position = from - Vector3.UP * (player.camera.global_position.y - player.global_position.y)
	await _frames(3)
	_face(at)
	await _frames(25)
	_face(at)
	await _frames(5)
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))


func _perf(title: String, from: Vector3, at: Vector3) -> void:
	await _view(from, at, "")
	var cap := Engine.max_fps
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var rid := get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(60)
	var gpu := 0.0
	var start := Time.get_ticks_usec()
	for i in 150:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var frame := (Time.get_ticks_usec() - start) / 150.0 / 1000.0
	print("perf %s: frame %5.2f ms (%3.0f fps), gpu %5.2f ms, draws %d, prims %d" % [title, frame, 1000.0 / frame, gpu / 150.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	Engine.max_fps = cap


func _face(at: Vector3) -> void:
	var to: Vector3 = at - player.camera.global_position
	player.rotation.y = atan2(-to.x, -to.z)
	player.look_rotation_x = atan2(to.y, Vector2(to.x, to.z).length())
	player.head.rotation.x = player.look_rotation_x


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
