extends Node3D
## The Listener (the thing in Marrow's water) on its own: no water, no town,
## a plain studio floor, in each of its forms. Screenshots into KM0_CHECK_DIR.

const Listener := preload("res://scripts/salvage_listener.gd")
const FORMS := ["ROAM", "HUNT", "LISTEN", "GRAB"]

var dir := OS.get_environment("KM0_CHECK_DIR")
var cam := Camera3D.new()


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
	key.light_energy = 1.6
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-50, -35, 0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.7
	rim.light_color = Color(0.7, 0.8, 1.0)
	rim.rotation_degrees = Vector3(-20, 150, 0)
	add_child(rim)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.22, 0.22, 0.23)
	grey.roughness = 0.9
	floor_mesh.material_override = grey
	floor_mesh.position.y = -0.75
	add_child(floor_mesh)
	add_child(cam)
	cam.fov = 35.0
	cam.make_current()
	# A stand-in for the game: the water line at 0, and no hunting.
	var stub := GDScript.new()
	stub.source_code = "extends Node3D\nvar water_level := 0.0\nvar ended := true\nvar noise: Node = null\n"
	stub.reload()
	var game := Node3D.new()
	game.set_script(stub)
	add_child(game)
	var creatures: Array[Node3D] = []
	for i in FORMS.size():
		var listener: Node3D = Listener.new()
		listener.game = game
		add_child(listener)
		listener.position = Vector3(i * 6.0, 0, 0)
		listener.rotation.y = PI * 0.5
		listener.state = listener.State[FORMS[i]]
		creatures.append(listener)
	await _frames(240)
	for creature in creatures:
		creature.wake.visible = false
	for i in FORMS.size():
		var at := creatures[i].global_position
		cam.global_position = at + Vector3(-0.1, 0.8, 8.4)
		cam.look_at(at + Vector3(-0.1, 0.05, 0))
		await _shot("form_%d_%s_side" % [i + 1, FORMS[i].to_lower()])
		cam.global_position = at + Vector3(3.4, 1.4, 2.6)
		cam.look_at(at + Vector3(1.6, 0.25, 0))
		await _shot("form_%d_%s_head" % [i + 1, FORMS[i].to_lower()])
		if FORMS[i] in ["LISTEN", "GRAB"]:
			# Face on, the way you'd meet it, and from above: the ears' spread.
			cam.global_position = at + Vector3(5.6, 0.7, 0.4)
			cam.look_at(at + Vector3(1.7, 0.45, 0))
			await _shot("form_%d_%s_front" % [i + 1, FORMS[i].to_lower()])
			cam.global_position = at + Vector3(1.9, 5.0, 0.01)
			cam.look_at(at + Vector3(1.9, 0.0, 0))
			await _shot("form_%d_%s_top" % [i + 1, FORMS[i].to_lower()])
	cam.fov = 30.0
	cam.global_position = Vector3(9.0, 6.5, 19.0)
	cam.look_at(Vector3(9.0, -0.2, 0))
	await _shot("forms_all")
	get_tree().quit()


func _shot(title: String) -> void:
	await _frames(8)
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
