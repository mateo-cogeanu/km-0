extends Node
## The roadside ground in each kind of country: grassland, pine forest, sand
## and badlands, near (looking down at your feet), mid (across the verge) and
## far (over the land from a little height). Screenshots into KM0_CHECK_DIR;
## KM0_PERF=1 also times the grassland views.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")
const Terrain := preload("res://scripts/roadside_terrain.gd")

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
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var cycle := world.get_node_or_null("DayNightCycle")
	cycle.time_of_day = float(OS.get_environment("KM0_TIME")) if OS.has_environment("KM0_TIME") else 0.4
	cycle.day_length_seconds = 0.0
	road = world.get_node("InfiniteRoad")
	road.begin_streaming()
	player = get_tree().get_first_node_in_group("local_player")
	player.set_physics_process(false)

	# The middle of each biome (biome n spans climate n..n+1).
	for biome in [["meadow", 1], ["forest", 2], ["sand", 4], ["badlands", 3]]:
		var z: float = -180.0 - (biome[1] + 0.45) * Terrain.BIOME_LENGTH
		player.global_position = road._sample(z, 0.0, 1.2)
		await _frames(30)
		var side := 1.0
		var at: Vector3 = road._sample(z, 9.0 * side, 0.0)
		await _view(road._sample(z + 2.0, 6.5 * side, 1.7), road._sample(z - 1.0, 9.5 * side, 0.0), biome[0] + "_near")
		await _view(road._sample(z + 6.0, 5.0 * side, 1.7), road._sample(z - 25.0, 30.0 * side, 0.4), biome[0] + "_mid")
		await _view(road._sample(z + 10.0, 2.0, 6.0), road._sample(z - 120.0, 90.0 * side, 0.0), biome[0] + "_far")
		if OS.get_environment("KM0_PERF") == "1" and biome[0] in ["meadow", "forest"]:
			await _perf(biome[0] + "_mid", road._sample(z + 6.0, 5.0 * side, 1.7), road._sample(z - 25.0, 30.0 * side, 0.4))
			await _perf(biome[0] + "_far", road._sample(z + 10.0, 2.0, 6.0), road._sample(z - 120.0, 90.0 * side, 0.0))
	get_tree().quit()


func _view(from: Vector3, at: Vector3, title: String) -> void:
	player.global_position = from - Vector3.UP * (player.camera.global_position.y - player.global_position.y)
	await _frames(3)
	_face(at)
	await _frames(25)
	_face(at)
	await _frames(5)
	if not dir.is_empty() and not title.is_empty():
		get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))


func _perf(title: String, from: Vector3, at: Vector3) -> void:
	await _view(from, at, "")
	var cap := Engine.max_fps
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _frames(60)
	var start := Time.get_ticks_usec()
	for i in 150:
		await get_tree().process_frame
	var frame := (Time.get_ticks_usec() - start) / 150.0 / 1000.0
	print("perf %s: frame %5.2f ms, draws %d, prims %d" % [title, frame,
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
