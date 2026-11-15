extends Node
## Loads the real world and walks the player through the body, grabbing,
## inventory, food and flashlight, saving a screenshot at each step into the
## folder in KM0_CHECK_DIR.

var out := OS.get_environment("KM0_CHECK_DIR")
var player: CharacterBody3D


func _ready() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(120)
	var menu := get_tree().current_scene.get_node_or_null("PauseMenu")
	if menu and menu.has_method("_close_tutorial"):
		menu._close_tutorial()
	player = get_tree().get_first_node_in_group("local_player")
	await _frames(30)
	_shot("01_forward")
	_look(-1.25)
	await _frames(20)
	_shot("02_look_down")
	var food: RigidBody3D = get_tree().get_first_node_in_group("food")
	print("food: ", food.title(), " at ", food.global_position)
	var away: Vector3 = (food.get_parent() as Node3D).global_basis.z
	var from := food.global_position + Vector3(away.x, 0, away.z).normalized() * 0.75
	player.global_position = Vector3(from.x, food.global_position.y + 0.1, from.z)
	await _frames(10)
	player.look_at(Vector3(food.global_position.x, player.global_position.y, food.global_position.z), Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	_look(-0.75)
	await _frames(20)
	_shot("03_before_grab")
	player._begin_grab_object(food, food.global_position)
	await _frames(25)
	_shot("04_holding")
	print("vitals before: ", player.vitals.to_save())
	player.vitals.hunger = 40.0
	player._eat_held_object()
	print("vitals after eating: ", player.vitals.to_save())
	await _frames(10)
	var second: RigidBody3D = get_tree().get_first_node_in_group("food")
	player._begin_grab_object(second, second.global_position)
	await _frames(20)
	player._stow_held_object()
	await _frames(25)
	player.open_inventory()
	await _frames(10)
	_shot("05_inventory")
	print("inventory: ", player.inventory.items.size())
	player.close_inventory()
	var cycle := get_tree().current_scene.get_node("DayNightCycle")
	cycle.time_of_day = 0.0
	player.set_flashlight(true)
	_look(-0.2)
	await _frames(60)
	_shot("06_night_flashlight")
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	_look(-0.9)
	await _frames(40)
	_shot("07_walking_down")
	print("speed: ", Vector2(player.velocity.x, player.velocity.z).length())
	key.pressed = false
	Input.parse_input_event(key)
	player.set_flashlight(false)
	cycle.time_of_day = 0.45
	# The workshop cooler.
	var cooler: Node3D = null
	for box in get_tree().get_nodes_in_group("loot_box"):
		if box.get_parent().name == "Shack":
			cooler = box
	print("cooler: ", cooler)
	var front := cooler.global_transform * Vector3(0, 0, 1.0)
	player.global_position = Vector3(front.x, cooler.global_position.y + 1.05, front.z)
	await _frames(5)
	player.look_at(Vector3(cooler.global_position.x, player.global_position.y, cooler.global_position.z), Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	_look(-0.9)
	cooler.open()
	await _frames(40)
	_shot("08_cooler")
	var bottle: RigidBody3D = null
	for item in cooler.items:
		if item.is_in_group("water"):
			bottle = item
	player._begin_grab_object(bottle, bottle.global_position)
	await _frames(20)
	player.vitals.thirst = 30.0
	player._start_drinking()
	await _frames(45)
	_shot("09_drinking")
	await _frames(60)
	print("thirst after drinking: ", player.vitals.thirst, " bottle: ", bottle.amount)
	player._drop_held_object()
	player.vitals.fatigue = 80.0
	player._try_sleep("in the cot")
	await _frames(300)
	print("after sleep: fatigue ", player.vitals.fatigue, " time ", cycle.time_of_day)
	# The stranger, back past the start of the road.
	var cabin: Node3D = get_tree().current_scene.get_node("InfiniteRoad/StrangerHouse")
	player.global_position = cabin.to_global(Vector3(0.1, 1.06, 0.9))
	await _frames(20)
	player.look_at(cabin.to_global(Vector3(0.55, 1.06, -0.7)) * Vector3(1, 0, 1) + Vector3(0, player.global_position.y, 0), Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	_look(-0.05)
	await _frames(30)
	cabin.talk(player)
	await _frames(60)
	_shot("10_stranger")
	var guard := 0
	while not cabin.choosing and guard < 40:
		cabin._next_line()
		guard += 1
		await _frames(4)
	await _frames(10)
	_shot("11_choice")
	cabin._chose(true)
	await _frames(20)
	print("has flare: ", player.has_item("flare") != null)
	await _frames(10)
	get_tree().quit()


func _look(pitch: float) -> void:
	player.look_rotation_x = pitch
	player.head.rotation.x = pitch


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(title: String) -> void:
	get_viewport().get_texture().get_image().save_png(out.path_join(title + ".png"))
