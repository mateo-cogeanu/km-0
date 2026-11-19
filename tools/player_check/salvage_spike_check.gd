extends Node
## Loads Marrow and walks a camera round it for a while, printing any frame
## that takes longer than a quarter of a second.

func _ready() -> void:
	NetworkManager.story = "salvage"
	var started := Time.get_ticks_msec()
	var world: Node3D = load("res://scenes/salvage.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	await get_tree().process_frame
	print("loaded in %d ms" % (Time.get_ticks_msec() - started))
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	var last := Time.get_ticks_msec()
	var slow := 0
	var frames := 0
	var spots := [Vector3(0, 1.8, 20), Vector3(0, -3, -60), Vector3(50, -3.6, -56), Vector3(-30, 5, -160), Vector3(90, 30, -40), Vector3(0, 2, 140)]
	while Time.get_ticks_msec() - started < 40000:
		var t := (Time.get_ticks_msec() - started) / 1000.0
		var spot: Vector3 = spots[int(t / 5.0) % spots.size()]
		cam.global_position = spot
		cam.rotation = Vector3(-0.05, t * 0.9, 0)
		await get_tree().process_frame
		frames += 1
		var now := Time.get_ticks_msec()
		if now - last > 250:
			slow += 1
			print("slow frame %d ms at %.1f s near %s" % [now - last, t, spot])
		last = now
	print("frames %d, slow %d" % [frames, slow])
	get_tree().quit()
