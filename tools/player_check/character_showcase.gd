extends Node3D
## The player's body and the stranger on their own in a plain studio: front,
## side, back and a close look at the head and hands. Screenshots into
## KM0_CHECK_DIR.

const PlayerBody := preload("res://scripts/player_body.gd")

var dir := OS.get_environment("KM0_CHECK_DIR")
var cam := Camera3D.new()
var bodies: Array[Node3D] = []


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.135, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.5
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-40, -30, 0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.6
	rim.light_color = Color(0.7, 0.8, 1.0)
	rim.rotation_degrees = Vector3(-20, 150, 0)
	add_child(rim)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.22, 0.22, 0.23)
	floor_mesh.material_override = grey
	add_child(floor_mesh)
	add_child(cam)
	cam.fov = 30.0
	cam.make_current()
	for i in 2:
		var body: Node3D = PlayerBody.new()
		add_child(body)
		body.build(false)
		body.position = Vector3(i * 6.0, PlayerBody.FEET, 0)
		body.rotation.y = PI
		for mesh: GeometryInstance3D in body.find_children("*", "GeometryInstance3D", true, false):
			mesh.layers = 1
		if i == 1:
			_dress_stranger(body)
		bodies.append(body)
	for n in 30:
		for body in bodies:
			body.animate(1.0 / 60.0, {"grip": [0.25, 0.25]})
		await get_tree().process_frame
	for i in 2:
		var who := "player" if i == 0 else "stranger"
		var at := Vector3(i * 6.0, 0.95, 0)
		var out := -1.0 if i == 0 else 1.0
		for view: Array in [["front", Vector3(0, 0.1, 4.6)], ["side", Vector3(out * 4.6, 0.1, 0)], ["back", Vector3(0, 0.1, -4.6)]]:
			cam.fov = 30.0
			cam.global_position = at + view[1]
			cam.look_at(at)
			await _shot("%s_%s" % [who, view[0]])
		cam.fov = 22.0
		cam.global_position = Vector3(i * 6.0 + 0.32, 1.8, 0.85)
		cam.look_at(Vector3(i * 6.0, 1.75, 0))
		await _shot("%s_head" % who)
		cam.fov = 34.0
		cam.global_position = Vector3(i * 6.0 + 0.25, 1.15, 1.1)
		cam.look_at(Vector3(i * 6.0, 0.95, 0))
		await _shot("%s_waist" % who)
		cam.global_position = Vector3(i * 6.0 + 0.5, 0.35, 0.9)
		cam.look_at(Vector3(i * 6.0, 0.12, 0))
		await _shot("%s_boots" % who)
	get_tree().quit()


func _dress_stranger(body: Node3D) -> void:
	if body.has_method("dress_as_stranger"):
		body.dress_as_stranger()
		return
	# How stranger_house.gd dressed him before the remaster.
	var recolor := {"Jacket": Color("#5a2a22"), "Jeans": Color("#5b5240"), "Hair": Color("#7a7670")}
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name).begins_with("Beard"):
			mesh.visible = true
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			if material and recolor.has(material.resource_name):
				var worn := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
				worn.albedo_color = recolor[material.resource_name]
				mesh.set_surface_override_material(surface, worn)


func _shot(title: String) -> void:
	for n in 6:
		await get_tree().process_frame
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))
