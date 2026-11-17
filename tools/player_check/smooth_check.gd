extends Node
## How evenly the view moves while driving at 120 fps: frame-to-frame speed
## spread of the drawn camera, with physics interpolation on and off.
## Also reports the worst frame times while the road streams in.

var world: Node
var car: RigidBody3D


func _ready() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var guide := world.get_node_or_null("TutorialGuide")
	if guide:
		guide.queue_free()
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	for candidate in get_tree().get_nodes_in_group("drivable"):
		if "removable_parts" in candidate:
			car = candidate
			break
	var road: Node3D = world.get_node("InfiniteRoad")
	car.global_transform = Transform3D(Basis(), road._sample(-200.0, 0.0, 0.6))
	car.reset_physics_interpolation()
	player._enter_vehicle(car)
	await _frames(30)
	for mode in [OS.get_environment("KM0_SMOOTH_FIRST") != "off", OS.get_environment("KM0_SMOOTH_FIRST") == "off"]:
		get_tree().physics_interpolation = mode
		await _measure(mode, road)
	get_tree().quit()


func _measure(mode: bool, road: Node3D) -> void:
	GameSettings.fps_cap = 120
	Engine.max_fps = 120
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cam := get_viewport().get_camera_3d()
	var speeds: Array[float] = []
	var worst := 0.0
	var last := cam.get_global_transform_interpolated().origin
	var clock := 0.0
	var spikes := 0
	while clock < float(OS.get_environment("KM0_SMOOTH_SECONDS") if OS.has_environment("KM0_SMOOTH_SECONDS") else "8"):
		await get_tree().process_frame
		var dt := get_process_delta_time()
		clock += dt
		car.linear_velocity = Vector3(0, car.linear_velocity.y, -float(OS.get_environment("KM0_SMOOTH_SPEED") if OS.has_environment("KM0_SMOOTH_SPEED") else "25"))
		car.angular_velocity = Vector3.ZERO
		var now := cam.get_global_transform_interpolated().origin
		if clock > 1.0:
			speeds.append(Vector2(now.x - last.x, now.z - last.z).length() / dt)
			worst = maxf(worst, dt)
			if dt > 0.025:
				spikes += 1
		last = now
	var mean := 0.0
	for s in speeds:
		mean += s
	mean /= speeds.size()
	var spread := 0.0
	for s in speeds:
		spread += (s - mean) * (s - mean)
	spread = sqrt(spread / speeds.size())
	print("interpolation %s: %d frames, view speed %.1f m/s, frame-to-frame spread %.1f%%, worst frame %.1f ms, frames over 25 ms: %d" % [
		"on " if mode else "off", speeds.size(), mean, spread / mean * 100.0, worst * 1000.0, spikes])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
