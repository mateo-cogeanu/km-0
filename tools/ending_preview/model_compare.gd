extends Node3D
## Renders the creature model at rest and in a crawl pose next to each other,
## with the same camera as the Blender preview render, for comparing looks.

const Creature := preload("res://scripts/road_creature.gd")
const OUT := "user://model_compare"

var shots := 0


func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.12, 0.12, 0.13)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	world.environment.ambient_light_energy = 0.5
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.4
	sun.light_cull_mask = 0xFFFFFFFF
	add_child(sun)
	var raw := (Creature.MODEL as PackedScene).instantiate() as Node3D
	raw.position = Vector3(-1.1, 0, 0)
	add_child(raw)
	var posed := Creature.new()
	posed.position = Vector3(1.1, 0, 0)
	add_child(posed)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50
	cam.look_at_from_position(Vector3(0.6, 2.6, 4.8), Vector3(0, 0.45, 0))
	cam.make_current()
	await get_tree().process_frame
	# Crawl-like pose, the same contacts road_end_house.gd uses.
	var shoulders := Vector3(0, 0.70, 0.16)
	var pelvis := Vector3(0, 0.62, -0.58)
	var palms: Array[Vector3] = [Vector3(-0.39, 0, 0.37), Vector3(0.39, 0, 0.37)]
	var normals: Array[Vector3] = [Vector3.UP, Vector3.UP]
	var feet: Array[Vector3] = [Vector3(-0.32, 0, -0.51), Vector3(0.32, 0, -0.51)]
	posed.pose_contacts(shoulders, pelvis, Vector3(0, 1.95, 1.4), palms, normals, feet, 0.0)
	for i in 4:
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT)
	get_viewport().get_texture().get_image().save_png(OUT + "/compare.png")
	cam.look_at_from_position(Vector3(0.0, 1.05, 1.6), Vector3(1.1, 0.9, 0.5))
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/face.png")
	# Straight-on and side views of the raw model's head (rest pose, +Z forward).
	cam.fov = 30
	cam.look_at_from_position(Vector3(-1.1, 0.88, 1.75), Vector3(-1.1, 0.88, 0.75))
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/front.png")
	cam.look_at_from_position(Vector3(-0.1, 0.9, 0.85), Vector3(-1.1, 0.9, 0.8))
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/side.png")
	# The game-posed copy, with the in-game skin and eye shaders.
	var face := posed.head.global_position
	cam.look_at_from_position(face + Vector3(0.25, 0.05, 0.75), face)
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/posed_front.png")
	cam.look_at_from_position(face + Vector3(-0.6, 0.15, 0.35), face)
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/posed_side.png")
	get_tree().quit()
