extends Node
## A menu that drops you into the real game right before each ending, so you
## can play them out yourself. Not part of the shipped game (tools/ is not
## exported).

const RoadEndHouse := preload("res://scripts/road_end_house.gd")
const Notes := preload("res://scripts/story_notes.gd")
const Supply := preload("res://scripts/supply_item.gd")
const Cinematic := preload("res://scripts/ending_cinematic.gd")
const Style := preload("res://scripts/menu_style.gd")

var menu: CanvasLayer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = CanvasLayer.new()
	add_child(menu)
	var back := ColorRect.new()
	back.color = Color("#141210")
	menu.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.theme = Style.make_theme()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	menu.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := Style.label("KM0 endings", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	for choice: Array in [
			["The house: walk in", _house.bind(false)],
			["The house: walk in, carrying the flare", _house.bind(true)],
			["The way out: you've read Len's last page, keep walking", _way_out],
			["Replaced: after the house, at the workshop radio", _replaced],
			["Just watch the house scene", _watch.bind("house")],
			["Just watch the way-out scene", _watch.bind("free")],
			["Just watch the replaced scene", _watch.bind("replaced")]]:
		var button := Style.button(choice[0], 20)
		button.custom_minimum_size.x = 560
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(choice[1])
		column.add_child(button)
	(column.get_child(1) as Control).grab_focus()
	# For checking: KM0_DEMO_PICK=house picks that option straight away.
	if OS.get_environment("KM0_DEMO_PICK") == "house":
		await _house(false)
		print("house demo: player at ", _player().global_position.snapped(Vector3.ONE * 0.1), " house at ",
			(get_tree().current_scene.find_child("RoadEndHouse", true, false) as Node3D).global_position.snapped(Vector3.ONE * 0.1))
		await _frames(30)
		print("standing on floor: ", _player().is_on_floor(), " at ", _player().global_position.snapped(Vector3.ONE * 0.1))
		get_tree().quit()


func _world() -> Node:
	menu.queue_free()
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var pause := world.get_node_or_null("PauseMenu")
	if pause and pause.has_method("_close_tutorial"):
		pause._close_tutorial()
	return world


func _player() -> CharacterBody3D:
	return get_tree().get_first_node_in_group("local_player")


func _face(player: CharacterBody3D, at: Vector3) -> void:
	var eye: Vector3 = player.camera.global_position
	var to := at - eye
	player.rotation.y = atan2(-to.x, -to.z)
	player.look_rotation_x = 0.0
	player.head.rotation.x = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _house(with_flare: bool) -> void:
	RoadEndHouse.seen = false
	var world: Node = await _world()
	var player := _player()
	# Go to the end of the road and let it stream in, then stand at the turnoff.
	player.global_position = Vector3(0, 1.2, -5185)
	await _frames(90)
	var house := world.find_child("RoadEndHouse", true, false) as Node3D
	if house:
		player.global_position = house.global_position + Vector3(-11.0, 1.2, 0.0)
		await _frames(5)
		_face(player, house.global_position + Vector3(0, 1.4, 0))
	if with_flare:
		var flare: RigidBody3D = Supply.new()
		flare.kind = "flare"
		world.add_child(flare)
		flare.global_position = player.global_position
		flare.set_meta("given", true)
		player.give_item(flare)


func _way_out() -> void:
	RoadEndHouse.seen = false
	Notes.read["len_last"] = true
	await _world()
	var player := _player()
	# Back past the start of the road, just before the second call.
	player.global_position = Vector3(0, 1.2, 1660)
	await _frames(10)
	_face(player, player.global_position + Vector3(0, 0, 50))


func _replaced() -> void:
	RoadEndHouse.seen = true
	await _world()
	var player := _player()
	var radio: Node3D = get_tree().get_first_node_in_group("road_radio")
	var stand := radio.to_global(Vector3(0, 0, 1.3))
	player.global_position = Vector3(stand.x, player.global_position.y, stand.z)
	await _frames(10)
	_face(player, radio.global_position)


func _watch(kind: String) -> void:
	menu.queue_free()
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var cinematic: Control = Cinematic.create(kind)
	layer.add_child(cinematic)
	var button := Style.button("Back to the endings", 22)
	button.name = "EndButton"
	button.theme = Style.make_theme()
	button.pressed.connect(func() -> void:
		get_tree().paused = false
		get_tree().reload_current_scene())
	var lines := {
		"house": [["The headlights stayed on until the battery died.", 22], ["THE END", 30]],
		"free": [["You kept going.", 40], ["Past the workshop, past where the road began, the radio finally went quiet.", 20],
			["For the first time in days it was only the engine, and the wind, and nobody's voice but your own.", 20], ["THE END", 30]],
		"replaced": [["Somebody always comes.", 40],
			["Far back along the road, a pair of headlights turned toward the house at the end of it.", 20],
			["The kettle's on.", 20], ["THE END", 30]],
	}
	cinematic.set_card(lines[kind], button)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
