extends Node
## Frame time in the Salvage Run at your own settings, looking down the street
## at night with the flashlight on, uncapped.

func _ready() -> void:
	NetworkManager.story = "salvage"
	var world: Node3D = load("res://scenes/salvage.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(90)
	var player: CharacterBody3D = world.local_player()
	var off := OS.get_environment("KM0_OFF")
	if "mist" in off:
		for p in world.find_children("*", "GPUParticles3D", true, false):
			p.visible = false
	if "msaa" in off:
		get_viewport().msaa_3d = Viewport.MSAA_2X
	if "water" in off:
		world.water.visible = false
	if "houses" in off:
		for n in world.town.get_children():
			if n is Node3D and n.get_child_count() > 0 and n.find_children("*", "StaticBody3D", false, false).size() > 0 and String(n.name).begins_with("@") or String(n.name).begins_with("house"):
				n.visible = false
	if "town" in off:
		for n in world.town.get_children():
			if n.name != "Hillside":
				n.visible = false
	if "cars" in off:
		for c in get_tree().get_nodes_in_group("drivable"):
			c.visible = false
	if "flood" in off:
		for m in world.town.flooded:
			m.shader = preload("res://assets/salvage/shingles.gdshader")
	GameSettings.fps_cap = 0
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for spot in [["camp", Vector3(0, 1.05, 18), Vector3(0, -5, -60)], ["street", Vector3(10.5, -3.75, -52), Vector3(-2, -4.5, -100)]]:
		player.global_position = spot[1]
		player.reset_physics_interpolation()
		var to: Vector3 = spot[2] - spot[1]
		player.rotation.y = atan2(-to.x, -to.z)
		player.set_flashlight(not "torch" in off, true)
		await _frames(120)
		var total := 0.0
		var frames := 0
		var worst := 0.0
		while total < 4.0:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			total += dt
			frames += 1
			worst = maxf(worst, dt)
		print("%s: %.1f ms average (%.0f fps), worst %.1f ms, %d draw calls, %d k triangles" % [spot[0], total / frames * 1000.0, frames / total, worst * 1000.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000])
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
