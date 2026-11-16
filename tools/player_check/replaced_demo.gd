extends Node
## Playable demo of the third ending: the house already happened, and you are
## standing at the workshop radio. Tune it with E, then answer it with E.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")


func _ready() -> void:
	RoadEndHouse.seen = true
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var menu := world.get_node_or_null("PauseMenu")
	if menu and menu.has_method("_close_tutorial"):
		menu._close_tutorial()
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	var radio: Node3D = get_tree().get_first_node_in_group("road_radio")
	var stand := radio.to_global(Vector3(0, 0, 1.3))
	player.global_position = Vector3(stand.x, player.global_position.y, stand.z)
	await _frames(10)
	var eye: Vector3 = player.camera.global_position
	var to_radio := radio.global_position - eye
	player.rotation.y = atan2(-to_radio.x, -to_radio.z)
	player.look_rotation_x = atan2(to_radio.y, Vector2(to_radio.x, to_radio.z).length())
	player.head.rotation.x = player.look_rotation_x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
