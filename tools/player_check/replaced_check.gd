extends Node
## After the house: tune a station radio, answer it, and watch the third ending
## through to the end card. Screenshots into KM0_CHECK_DIR.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")


func _ready() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(90)
	var menu := world.get_node_or_null("PauseMenu")
	if menu and menu.has_method("_close_tutorial"):
		menu._close_tutorial()
	RoadEndHouse.seen = true
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	var radio: Node3D = get_tree().get_first_node_in_group("road_radio")
	var stand := radio.to_global(Vector3(0, 0, 0.9))
	player.global_position = Vector3(stand.x, player.global_position.y, stand.z)
	await _frames(20)
	var eye: Vector3 = player.camera.global_position
	var to_radio := radio.global_position - eye
	player.rotation.y = atan2(-to_radio.x, -to_radio.z)
	player.look_rotation_x = atan2(to_radio.y, Vector2(to_radio.x, to_radio.z).length())
	player.head.rotation.x = player.look_rotation_x
	await _frames(5)
	print("tip before: ", player._interaction_text())
	player._handle_interaction()
	await _frames(30)
	print("tip listening: ", player._interaction_text())
	player._handle_interaction()
	var dir := OS.get_environment("KM0_CHECK_DIR")
	var shots := {120: "speaking", 900: "reply", 1300: "cough"}
	for i in 3000:
		await get_tree().process_frame
		if shots.has(i):
			get_viewport().get_texture().get_image().save_png(dir.path_join("replaced_%s.png" % shots[i]))
			var ending := world.get_node_or_null("ReplacedEnding")
			print(i, " caption: ", ending.caption_label.text if ending and ending.caption_label else "-")
		if world.find_child("EndButton", true, false):
			await _frames(260)
			get_viewport().get_texture().get_image().save_png(dir.path_join("replaced_card.png"))
			print("end card at frame ", i, " story: ", RoadEndHouse.story)
			break
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
