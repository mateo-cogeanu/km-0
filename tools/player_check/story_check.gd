extends Node
## Walks through the story systems in the real world: a note, a dust storm,
## the car radio's choices, the barred cabin door and the way out.
## Screenshots go to KM0_CHECK_DIR.

const Notes := preload("res://scripts/story_notes.gd")
const RoadEndHouse := preload("res://scripts/road_end_house.gd")
var out := OS.get_environment("KM0_CHECK_DIR")


func _ready() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(100)
	var menu := world.get_node_or_null("PauseMenu")
	if menu and menu.has_method("_close_tutorial"):
		menu._close_tutorial()
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	var note: Node = get_tree().get_first_node_in_group("note").get_parent()
	player.read_note(note)
	await _frames(15)
	_shot("note")
	print("reading: ", player.reading(), " read: ", Notes.read.keys())
	player.close_note()
	# Outside on the road, in a storm, by day.
	world.get_node("DayNightCycle").time_of_day = 0.45
	player.global_position = Vector3(0, 1.1, -40)
	player.rotation = Vector3.ZERO
	var weather: Node = world.get_node("InfiniteRoad/Weather")
	weather.length = 200.0
	weather.left = 100.0
	await _frames(120)
	_shot("storm")
	print("storm level: ", weather.storm_level())
	var cycle: Node = world.get_node("DayNightCycle")
	var env: Environment = cycle.environment
	print("cycle storm ", cycle.storm, " fog ", env.fog_enabled, " density ", env.fog_density, " mode ", env.fog_mode, " cam env ", player.camera.environment, " world env same ", env == (world.get_node("WorldEnvironment") as WorldEnvironment).environment, " dust ", weather.dust.emitting, " ratio ", weather.dust.amount_ratio)
	env.fog_density = 0.3
	env.fog_light_energy = 1.0
	await _frames(3)
	_shot("fogtest")
	var drawn: Environment = player.camera.get_world_3d().environment
	print("drawn env is cycle env: ", drawn == env, " drawn fog ", drawn.fog_enabled if drawn else null, " density ", drawn.fog_density if drawn else null, " envs: ", get_tree().root.find_children("*", "WorldEnvironment", true, false))
	print("after force: ", env.fog_density, " sky affect ", env.fog_sky_affect, " aerial ", env.fog_aerial_perspective, " height dens ", env.fog_height_density, " height ", env.fog_height)
	weather.left = 0.0
	var radio: Node = player.car_radio
	for z in [-400.0, -1800.0, -2800.0, -3800.0, -4700.0]:
		radio.furthest = -z
		print("car radio at ", z, ": ", radio._pick())
	player.global_position = Vector3(0, 1.1, 600)
	await _frames(5)
	print("car radio behind the start: ", radio._pick())
	# After the house: the stranger keeps his door barred.
	RoadEndHouse.seen = true
	var cabin: Node3D = world.get_node("InfiniteRoad/StrangerHouse")
	player.global_position = cabin.to_global(Vector3(0, 1.06, 3.0))
	await _frames(20)
	cabin.use_door(player)
	await _frames(30)
	print("through the door: ", cabin.caption.text if cabin.caption else "", " door open: ", cabin.door_open)
	cabin._finish()
	print("radio after the house: ", radio._pick())
	# The way out, for someone who read Len's last page and never went in.
	RoadEndHouse.seen = false
	Notes.read["len_last"] = true
	player.global_position = Vector3(0, 1.1, 1980)
	await _frames(400)
	_shot("escape")
	var dread: Node = world.get_node("InfiniteRoad/RoadDread")
	print("escaped: ", dread.escaping, " calls: ", dread.calls_made)
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(title: String) -> void:
	get_viewport().get_texture().get_image().save_png(out.path_join(title + ".png"))
