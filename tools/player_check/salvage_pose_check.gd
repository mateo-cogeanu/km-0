extends Node
## Side view of the Listener's poses with the water hidden, to check the rig.

func _ready() -> void:
	var dir := OS.get_environment("KM0_CHECK_DIR")
	NetworkManager.story = "salvage"
	var world: Node3D = load("res://scenes/salvage.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var cycle := world.get_node("DayNightCycle")
	cycle.time_of_day = 0.4
	cycle._update_world_lighting()
	world.water.visible = false
	world.hud.visible = false
	var player: CharacterBody3D = world.local_player()
	player.get_node("HUD").visible = false
	var listener: Node3D = world.listener
	world.clock = 60.0
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 40.0
	for pose in ["ROAM", "HUNT", "LISTEN", "GRAB"]:
		listener.state = listener.State[pose]
		listener.state_time = -60.0
		listener.position = Vector3(0.0, listener.position.y, -95.0)
		listener.rotation.y = PI * 0.5
		listener.target = listener.position
		cam.global_position = Vector3(0.5, -4.6, -88.0)
		cam.look_at(Vector3(0.5, -5.0, -95.0))
		cam.make_current()
		await _frames(120)
		listener.rotation.y = PI * 0.5
		for n in 2:
			await _frames(6)
			get_viewport().get_texture().get_image().save_png("%s/pose_%s.png" % [dir, pose])
		cam.global_position = Vector3(3.2, -4.3, -93.5)
		cam.look_at(listener.global_position + listener.global_basis.z * 1.6 + Vector3(0, 0.4, 0))
		for n in 2:
			await _frames(6)
			get_viewport().get_texture().get_image().save_png("%s/close_%s.png" % [dir, pose])
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
