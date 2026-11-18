extends Node
## Screenshots of Marrow from a few places, by day and by night.

func _ready() -> void:
	var dir := OS.get_environment("KM0_CHECK_DIR")
	NetworkManager.story = "salvage"
	var world: Node3D = load("res://scenes/salvage.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(90)
	world.hud.visible = false
	var player: CharacterBody3D = world.local_player()
	player.get_node("HUD").visible = false
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 70.0
	cam.make_current()
	var views := {
		"camp": [Vector3(-2, 1.8, 24), Vector3(8, 0.5, 14)],
		"hill": [Vector3(0, 1.8, 10), Vector3(0, -5.5, -70)],
		"street": [Vector3(11.0, -3.0, -52), Vector3(-2, -4.5, -95)],
		"house": [Vector3(4.0, -3.6, -66), Vector3(14, -2.5, -74)],
		"water": [Vector3(-2.0, -4.3, -78), Vector3(6, -4.8, -96)],
	}
	# The first capture of a run comes back stale: take one and throw it away.
	await _frames(20)
	get_viewport().get_texture().get_image()
	var tod := {"day": 0.38, "night": 0.03}
	for when: String in tod:
		var cycle := world.get_node("DayNightCycle")
		cycle.time_of_day = tod[when]
		cycle._update_world_lighting()
		for name: String in views:
			cam.global_position = views[name][0]
			cam.look_at(views[name][1])
			if when == "night":
				# The flashlight, as a player would have it.
				var torch := SpotLight3D.new()
				torch.light_energy = 2.4
				torch.spot_range = 22.0
				torch.spot_angle = 27.0
				torch.shadow_enabled = true
				cam.add_child(torch)
				await _frames(40)
				for n in 2:
					await _frames(6)
					get_viewport().get_texture().get_image().save_png("%s/look_%s_%s.png" % [dir, when, name])
				torch.queue_free()
			else:
				await _frames(40)
				for n in 2:
					await _frames(6)
					get_viewport().get_texture().get_image().save_png("%s/look_%s_%s.png" % [dir, when, name])
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
