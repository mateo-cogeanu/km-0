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
	if not frames_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(frames_dir)
		RenderingServer.frame_post_draw.connect(_save_frame)


func _save_frame() -> void:
	view.get_texture().get_image().save_png("%s/%05d.png" % [frames_dir, frame])
	frame += 1
