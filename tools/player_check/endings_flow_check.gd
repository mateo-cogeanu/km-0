extends Node
## The new story flow, in the real game. KM0_FLOW picks one:
##   gate   the house only appears after listening and two nights
##   chase  the way out: breakdown on foot, it comes, it catches you
##   burn   petrol on four walls, the flare, the fire, the ending
## Screenshots into KM0_CHECK_DIR.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")
const Notes := preload("res://scripts/story_notes.gd")
const Supply := preload("res://scripts/supply_item.gd")
const FUEL := preload("res://scenes/fuel_canister.tscn")

var world: Node
var dir := OS.get_environment("KM0_CHECK_DIR")


func _ready() -> void:
	RoadEndHouse.seen = false
	RoadEndHouse.story = {}
	Notes.read = {}
	world = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var menu := world.get_node_or_null("PauseMenu")
	if menu and menu.has_method("_close_tutorial"):
		menu._close_tutorial()
	match OS.get_environment("KM0_FLOW"):
		"gate":
			await _gate()
		"chase":
			await _chase()
		"burn":
			await _burn()
	get_tree().quit()


func _player() -> CharacterBody3D:
	return get_tree().get_first_node_in_group("local_player")


func _shot(title: String) -> void:
	get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))


func _gate() -> void:
	var road: Node3D = world.get_node("InfiniteRoad")
	var player := _player()
	player.global_position = road._sample(-5600.0, 0.0, 1.2)
	await _frames(120)
	print("before listening: house_z=", RoadEndHouse.story.get("house_z", "none"), " house built: ", world.find_child("RoadEndHouse", true, false) != null)
	RoadEndHouse.story["heard"] = {"1": true, "2": true, "3": true, "5": true}
	RoadEndHouse.story["nights"] = 2
	await _frames(30)
	var house_z: float = RoadEndHouse.story.get("house_z", 0.0)
	print("after: house_z=", house_z, " tip: ", player.tip_override)
	player.global_position = road._sample(house_z + 40.0, 0.0, 1.2)
	await _frames(120)
	var house := world.find_child("RoadEndHouse", true, false) as Node3D
	print("house built: ", house != null, " at z ", house.global_position.z if house else 0.0, " county car: ", world.find_child("CountyCar", true, false) != null, " can: ", road.get_node_or_null("CountyCan") != null)


func _chase() -> void:
	for page in ["len_last", "len_page_tower", "len_page_cabin"]:
		Notes.read[page] = true
	var road: Node3D = world.get_node("InfiniteRoad")
	var dread: Node = world.get_node("InfiniteRoad/RoadDread")
	var player := _player()
	print("way out open: ", dread.way_out_open())
	player.global_position = road._sample(6290.0, 0.0, 1.2)
	await _frames(20)
	player.global_position = road._sample(6320.0, 0.0, 1.2)
	await _frames(20)
	print("broke down: ", dread.broke_down, " chasing: ", dread.chasing, " calls so far: ", dread.calls_made, " stormed: ", dread.stormed)
	var start: float = dread.chaser.global_position.distance_to(player.global_position) if dread.chaser else -1.0
	print("chaser starts ", snappedf(start, 0.1), " m behind")
	var frames := 0
	while not dread.caught and frames < 3600:
		await get_tree().process_frame
		frames += 1
		if frames == 1150:
			player.look_at(dread.chaser.global_position + Vector3.UP * 0.5, Vector3.UP)
			print("chaser distance at shot: ", snappedf(dread.chaser.global_position.distance_to(player.global_position), 0.1))
			player.rotation.x = 0.0
			player.rotation.z = 0.0
			await _frames(2)
			_shot("chase")
	print("caught after ", snappedf(frames / 30.0, 0.1), " s: ", dread.caught, " seen now: ", RoadEndHouse.seen)
	await _frames(300)
	print("back at the start: ", player.global_position.snapped(Vector3.ONE * 0.1), " way out still open: ", dread.way_out_open())


func _burn() -> void:
	RoadEndHouse.story["house_z"] = -5200.0
	var road: Node3D = world.get_node("InfiniteRoad")
	var player := _player()
	player.global_position = road._sample(-5180.0, 0.0, 1.2)
	await _frames(120)
	var house := world.find_child("RoadEndHouse", true, false) as Node3D
	# Carry the can to each wall and hold R.
	var can := FUEL.instantiate() as RigidBody3D
	can.fuel_amount = 16.0
	world.add_child(can)
	_hold(player, can)
	await _frames(5)
	var spots := [Vector3(0, 0, 5.2), Vector3(0, 0, -5.2), Vector3(-5.0, 0, 0), Vector3(5.0, 0, 0)]
	for spot: Vector3 in spots:
		player.global_position = house.to_global(spot) + Vector3.UP * 1.1
		await _frames(5)
		print("wall near: ", house._wall_near(player.global_position), " tip: ", player.tip_override)
		house.handle_r(player)
		Input.action_press("ui_accept")
		var pressed := InputEventKey.new()
		pressed.keycode = KEY_R
		pressed.pressed = true
		Input.parse_input_event(pressed)
		var wall: int = house._wall_near(player.global_position)
		while house.doused[wall] < house.DOUSE_PER_WALL and can.fuel_amount > 0.0:
			house.doused[wall] = minf(house.DOUSE_PER_WALL, house.doused[wall] + can.drain_fuel(1.4 / 30.0))
			await get_tree().process_frame
	print("doused: ", house.doused, " can left: ", snappedf(can.fuel_amount, 0.1), " all: ", house._all_doused())
	player.use_up(can)
	var flare: RigidBody3D = Supply.new()
	flare.kind = "flare"
	world.add_child(flare)
	_hold(player, flare)
	player.global_position = house.to_global(Vector3(0, 0, 11.0)) + Vector3.UP * 1.1
	player.look_at(house.to_global(Vector3(0, 3.0, 0)), Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	await _frames(20)
	print("tip with flare: ", player.tip_override)
	print("lit: ", house.handle_r(player))
	await _frames(300)
	print("burn clock at the fire shot: ", snappedf(house.burn_clock, 0.1), " heat: ", snappedf(house.fire.heat, 0.01) if house.fire else -1.0)
	_shot("burn_fire")
	await _frames(100)
	_shot("burn_roof")
	var frames := 0
	while world.find_child("EndButton", true, false) == null and frames < 1200:
		await get_tree().process_frame
		frames += 1
	print("burn ending reached: ", world.find_child("EndButton", true, false) != null, " story: ", RoadEndHouse.story.get("burned", false))


func _hold(player: CharacterBody3D, item: RigidBody3D) -> void:
	item.global_position = player.camera.global_transform * Vector3(0.15, -0.21, -0.42)
	player._begin_grab_object(item, item.global_position)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
