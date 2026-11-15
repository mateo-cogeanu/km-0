extends Node
## Plays the road-end house ending without driving there.
##
## The scene renders into an off-screen viewport, so it keeps drawing when the
## window is hidden. Set KM0_PREVIEW_FRAMES to a folder to save every frame as a
## PNG, then join them with ffmpeg. Run it with --fixed-fps 30 for real timing.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")

var view := SubViewport.new()
var frames_dir := OS.get_environment("KM0_PREVIEW_FRAMES")
var frame := 0


class PreviewPlayer extends Node3D:
	var active_vehicle: Node3D
	var camera := Camera3D.new()

	func _init() -> void:
		add_to_group("local_player")
		camera.fov = 75.0
		camera.position = Vector3(0, 0.9, 0)
		add_child(camera)

	func lock_for_ending(_return_position: Vector3) -> void:
		pass

	func aim_ending_camera(at: Vector3, amount: float) -> void:
		var target := camera.global_transform.looking_at(at)
		camera.global_basis = camera.global_basis.slerp(target.basis, clampf(amount, 0.0, 1.0))


func _ready() -> void:
	view.size = Vector2i(960, 540)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var scene := Node3D.new()
	scene.name = "Main"
	view.add_child(scene)
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	world.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.environment.glow_enabled = true
	scene.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 0.4
	scene.add_child(sun)
	# road_end_house.gd looks these up on the current scene. The sub-viewport
	# shares the root World3D, so they still light and shade the house.
	world.reparent(self)
	sun.reparent(self)
	var house := RoadEndHouse.new()
	scene.add_child(house)
	house.door_open = true
	var player := PreviewPlayer.new()
	scene.add_child(player)
	player.position = Vector3(0, 1.03, 2.2)
	player.camera.make_current()
	house.call_deferred("_on_entry", player)
	# Stop at the end card so the preview never reaches the menu or a save.
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Button:
			get_tree().quit())
	# KM0_PREVIEW_CAMERA="x,y,z,tx,ty,tz" watches from a fixed spot instead of
	# through the player's eyes.
	var spot := OS.get_environment("KM0_PREVIEW_CAMERA").split_floats(",")
	if spot.size() == 6:
		var watcher := Camera3D.new()
		watcher.fov = 60.0
		scene.add_child(watcher)
		watcher.look_at_from_position(Vector3(spot[0], spot[1], spot[2]), Vector3(spot[3], spot[4], spot[5]))
		watcher.make_current()
	if OS.has_environment("KM0_PREVIEW_MARKERS"):
		# Coloured balls on the solved joints: elbows blue, wrists red, knees
		# green, ankles yellow. Checks contacts against the walls.
		var balls := {}
		var colours := {"ForearmL": Color.BLUE, "ForearmR": Color.BLUE, "HandL": Color.RED, "HandR": Color.RED,
			"ShinL": Color.GREEN, "ShinR": Color.GREEN, "FootL": Color.YELLOW, "FootR": Color.YELLOW}
		get_tree().process_frame.connect(func() -> void:
			var c: Node3D = house.creature
			if not c or not c.posed.has("HandL"):
				return
			for label: String in colours:
				if not balls.has(label):
					var ball := MeshInstance3D.new()
					ball.mesh = SphereMesh.new()
					ball.mesh.radius = 0.035
					ball.mesh.height = 0.07
					var paint := StandardMaterial3D.new()
					paint.albedo_color = colours[label]
					paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					paint.no_depth_test = true
					ball.material_override = paint
					c.add_child(ball)
					balls[label] = ball
				balls[label].position = c.posed[label].origin)
	if OS.has_environment("KM0_PREVIEW_SKINCHECK"):
		# Skin the mesh on the CPU and report where each hand and foot's
		# vertices really end up, next to the joint they hang from.
		var check := Timer.new()
		add_child(check)
		check.timeout.connect(func() -> void:
			var c: Node3D = house.creature
			if not c or not c.visible:
				return
			var mi := c.find_child("Continuous skin", true, false) as MeshInstance3D
			var rig: Skeleton3D = c.rig
			var arrays := mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var report := {}
			for v in range(0, verts.size(), 7):
				var best := 0
				for k in 4:
					if weights[v * 4 + k] > weights[v * 4 + best]:
						best = k
				var bind_index := bones[v * 4 + best]
				var name := mi.skin.get_bind_name(bind_index)
				if not name in ["HandL", "HandR", "FootL", "FootR"]:
					continue
				var p := Vector3.ZERO
				for k in 4:
					var w := weights[v * 4 + k]
					if w > 0.0:
						var bi := bones[v * 4 + k]
						var bone := rig.find_bone(mi.skin.get_bind_name(bi))
						p += w * (rig.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bi) * verts[v])
				if not report.has(name):
					report[name] = [Vector3.ZERO, 0, 0.0]
				report[name][0] += p
				report[name][1] += 1
				report[name][2] = maxf(report[name][2], p.distance_to(c.posed[name].origin))
			var line := []
			for name: String in report:
				line.append("%s joint=%s mesh=%s far=%.2f" % [name, (c.posed[name].origin + c.position).snapped(Vector3.ONE * 0.01),
					(report[name][0] / report[name][1] + c.position).snapped(Vector3.ONE * 0.01), report[name][2]])
			print(" | ".join(line)))
		check.start(1.0)
	if OS.has_environment("KM0_PREVIEW_CLIPCHECK"):
		# Skin a sample of the body on the CPU each frame and report how deep
		# it sinks into the stairs or the floor, worst point per half second.
		var worst := [0.0, "", Vector3.ZERO]
		var clock := [0.0]
		get_tree().process_frame.connect(func() -> void:
			var c: Node3D = house.creature
			if not c or not c.visible or not c.posed.has("HandL"):
				return
			var mi := c.find_child("Continuous skin", true, false) as MeshInstance3D
			var rig: Skeleton3D = c.rig
			var arrays := mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var poses := {}
			for v in range(0, verts.size(), 11):
				var p := Vector3.ZERO
				var top := 0
				for k in 4:
					var w := weights[v * 4 + k]
					if w > 0.0:
						var bi := bones[v * 4 + k]
						if not poses.has(bi):
							poses[bi] = rig.get_bone_global_pose(rig.find_bone(mi.skin.get_bind_name(bi))) * mi.skin.get_bind_pose(bi)
						p += w * (poses[bi] * verts[v])
						if w > weights[v * 4 + top]:
							top = k
				p = house.to_local(c.to_global(p))
				var depth: float = house.ground_height(p.x, p.z) - p.y
				if depth > worst[0]:
					worst[0] = depth
					worst[1] = mi.skin.get_bind_name(bones[v * 4 + top])
					worst[2] = p
			clock[0] += 1.0 / 30.0
			if clock[0] >= 0.5:
				if worst[0] > 0.01:
					print("CLIP t=%.1f depth=%.2f bone=%s at=%s" % [Time.get_ticks_msec() / 1000.0, worst[0], worst[1], (worst[2] as Vector3).snapped(Vector3.ONE * 0.01)])
				worst[0] = 0.0
				clock[0] = 0.0)
	if OS.has_environment("KM0_PREVIEW_DEBUG"):
		var timer := Timer.new()
		add_child(timer)
		timer.timeout.connect(func() -> void:
			var c: Node3D = house.creature
			if c and c.visible:
				var parts := []
				for label in ["Torso", "Neck", "Head", "HandL", "HandR", "FootL", "FootR", "ForearmL", "ShinL"]:
					parts.append("%s=%s" % [label, (c.posed[label].origin + c.position).snapped(Vector3.ONE * 0.01)])
				print(snappedf(Time.get_ticks_msec() / 1000.0, 0.1), " ", " ".join(parts)))
		timer.start(0.5)
	if not frames_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(frames_dir)
		RenderingServer.frame_post_draw.connect(_save_frame)


func _save_frame() -> void:
	view.get_texture().get_image().save_png("%s/%05d.png" % [frames_dir, frame])
	frame += 1
