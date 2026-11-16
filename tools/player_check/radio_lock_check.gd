extends Node
## The car radio on when the ending locks the player in.


func _ready() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	player.car_radio.toggle()
	player.car_radio._show("test line")
	print("listening to car radio: ", player.listening_radio == player.car_radio)
	player.lock_for_ending(player.global_position)
	await _frames(5)
	print("car radio off after lock: ", not player.car_radio.on)
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
