extends Node
## Opens the stranger's cabin door and pushes the player through the doorway,
## printing how far the player got. Screenshot into KM0_CHECK_DIR.

func _ready() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(90)
	var menu := world.get_node_or_null("PauseMenu")
	if menu and menu.has_method("_close_tutorial"):
		menu._close_tutorial()
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	var cabin: Node3D = world.get_node("InfiniteRoad/StrangerHouse")
	player.global_position = cabin.to_global(Vector3(0, 1.1, 4.0))
	await _frames(30)
	player.look_at(cabin.to_global(Vector3(0, 1.1, 0)), Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	cabin.toggle_door()
	await _frames(70)
	get_viewport().get_texture().get_image().save_png(OS.get_environment("KM0_CHECK_DIR").path_join("door.png"))
	var inward: Vector3 = cabin.global_basis * Vector3(0, 0, -1)
	for i in 120:
		player.move_and_collide(inward * 0.04)
		await get_tree().physics_frame
	print("ended inside at local ", cabin.to_local(player.global_position).snapped(Vector3.ONE * 0.01))
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
