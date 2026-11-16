extends Node
## The stranger's flare used up at the house, then knocking on his barred door
## and, separately, talking to him with his flare gone.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")


func _ready() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	var cabin: Node3D = world.get_node("InfiniteRoad/StrangerHouse")
	# Took the flare, then lit it at the house: the node is gone.
	cabin.flare.set_meta("given", true)
	RoadEndHouse.story["flare_given"] = true
	cabin.flare.queue_free()
	RoadEndHouse.seen = true
	await _frames(2)
	cabin.use_door(player)
	for i in 900:
		await get_tree().process_frame
		if cabin.line_index < 0:
			break
	print("barred talk finished: ", cabin.line_index < 0, " talking: ", is_instance_valid(player.talking_to))
	# A trip where his flare was lost without being given (old save).
	RoadEndHouse.seen = false
	RoadEndHouse.story.erase("flare_given")
	cabin.talk(player)
	for i in 8000:
		await get_tree().process_frame
		if cabin.choosing:
			break
	print("offered again: ", cabin.choosing, " flare valid: ", is_instance_valid(cabin.flare))
	cabin._chose(true)
	print("given: ", cabin._given())
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
