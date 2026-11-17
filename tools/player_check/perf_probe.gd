extends Node
## GPU time per frame on the road, with each costly feature switched in turn,
## at your own settings. Prints milliseconds; lower is cooler.

var world: Node
var root_rid: RID


func _ready() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var guide := world.get_node_or_null("TutorialGuide")
	if guide:
		guide.queue_free()
	GameSettings.fps_cap = 0
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cycle := world.get_node_or_null("DayNightCycle")
	if cycle:
		cycle.time_of_day = 0.4
		cycle.day_length_seconds = 0.0
	var road: Node3D = world.get_node("InfiniteRoad")
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	player.global_position = road._sample(-300.0, 1.6, 1.1)
	player.look_at(road._sample(-380.0, 0.0, 1.0), Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	await _frames(120)
	root_rid = get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(root_rid, true)
	var env: Environment = world.get_node("WorldEnvironment").environment if world.has_node("WorldEnvironment") else null
	var sun: DirectionalLight3D = cycle.sun if cycle else null
	var vp := get_tree().root
	print("resolution ", vp.get_visible_rect().size, " scale ", vp.scaling_3d_scale, " msaa ", vp.msaa_3d)
	await _frames(400)
	var dir := OS.get_environment("KM0_CHECK_DIR")
	# With the new half-size SSAO from project settings, at your settings.
	var now := await _measure()
	print("now: %5.2f ms (%3.0f fps uncapped)" % [now, 1000.0 / now])
	for cap in [120, 60]:
		Engine.max_fps = cap
		await _frames(60)
		var start := Time.get_ticks_usec()
		var busy := 0.0
		for i in 120:
			await get_tree().process_frame
		var real := (Time.get_ticks_usec() - start) / 120.0 / 1000.0
		print("cap %d: one frame every %5.2f ms, GPU busy about %3.0f%% of the time" % [cap, real, minf(100.0, now / real * 100.0)])
	get_tree().paused = true
	Engine.max_fps = 120
	await _frames(30)
	var p_start := Time.get_ticks_usec()
	for i in 30:
		await get_tree().process_frame
	print("paused: %5.1f fps" % [30.0 / ((Time.get_ticks_usec() - p_start) / 1000000.0)])
	get_tree().paused = false
	get_tree().quit()


func _measure() -> float:
	await _frames(20)
	var start := Time.get_ticks_usec()
	for i in 150:
		await get_tree().process_frame
	return (Time.get_ticks_usec() - start) / 150.0 / 1000.0


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
