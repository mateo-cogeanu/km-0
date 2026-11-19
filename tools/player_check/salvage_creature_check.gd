extends Node
## Close look at the thing in the water: listening and grabbing, by day (to
## see its shape) and at night by flashlight.

func _ready() -> void:
	var dir := OS.get_environment("KM0_CHECK_DIR")
	NetworkManager.story = "salvage"
	var world: Node3D = load("res://scenes/salvage.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var player: CharacterBody3D = world.local_player()
	var listener: Node3D = world.listener
	world.clock = 40.0
	for pass_index in 2:
		var cycle := world.get_node("DayNightCycle")
		cycle.time_of_day = 0.4 if pass_index == 0 else 0.03
		cycle._update_world_lighting()
		for pose in ["LISTEN", "GRAB", "ROAM"]:
			listener.state = listener.State[pose]
			listener.state_time = -60.0
			listener.position = Vector3(3.0, listener.position.y, -95.0)
			listener.rotation.y = PI * 0.75
			player.global_position = Vector3(10.5, -3.75, -92.0)
			player.reset_physics_interpolation()
			var to: Vector3 = listener.global_position + Vector3(0, 0.3, 0) - player.camera.global_position
			player.rotation.y = atan2(-to.x, -to.z)
			player.look_rotation_x = atan2(to.y, Vector2(to.x, to.z).length())
			player.head.rotation.x = player.look_rotation_x
			player.set_flashlight(pass_index == 1, true)
			await _frames(240)
			player.rotation.y = atan2(-to.x, -to.z)
			for n in 2:
				await _frames(6)
				get_viewport().get_texture().get_image().save_png("%s/creature_%s_%s.png" % [dir, ["day", "night"][pass_index], pose])
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
