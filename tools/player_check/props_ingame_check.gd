extends Node
## The props in the game: the starting car's engine bay with the hood taken
## off, a fuel can and a flare held in first person, and the workbench finds.
## Screenshots into KM0_CHECK_DIR.

const Supply := preload("res://scripts/supply_item.gd")
const FUEL := preload("res://scenes/fuel_canister.tscn")

var world: Node
var dir := OS.get_environment("KM0_CHECK_DIR")


func _ready() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	for title in ["TutorialGuide", "InfiniteRoad/CountyDesk"]:
		var node := world.get_node_or_null(title)
		if node:
			node.queue_free()
	var cycle := world.get_node_or_null("DayNightCycle")
	cycle.time_of_day = 0.4
	cycle.day_length_seconds = 0.0
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	player.set_physics_process(false)
	# A complete car of its own (the starting car loses random parts each run).
	var car: RigidBody3D = load("res://scenes/car.tscn").instantiate()
	car.start_with_removed_panels = false
	car.start_with_random_body_color = false
	car.name = "BayCar"
	world.add_child(car)
	car.global_position = Vector3(30.0, 0.4, -20.0)
	await _frames(30)
	var hood: RigidBody3D = car._remove_part_by_type("hood", true)
	if hood:
		hood.global_position += Vector3(0, -30, 0)
		hood.freeze = true
	car.freeze = true
	await _frames(20)
	# Aim just past the bay, so the crosshair does not highlight a part.
	var bay := car.to_global(Vector3(0, 0.6, -1.45))
	var eye := car.to_global(Vector3(0.0, 2.0, -2.7))
	_look(player, eye, bay)
	# Look a little above the bay so the crosshair's highlight falls on nothing.
	player.look_rotation_x += 0.22
	player.head.rotation.x = player.look_rotation_x
	await _shot("engine_bay")
	# Holding a fuel can, then a flare.
	var shack: Node3D = world.get_node("Shack")
	_look(player, shack.to_global(Vector3(-0.8, 1.65, 6.0)), shack.to_global(Vector3(-0.8, 1.4, 0.0)))
	await _frames(10)
	var can: RigidBody3D = FUEL.instantiate()
	world.add_child(can)
	can.global_position = player.camera.global_transform * Vector3(0.15, -0.3, -0.5)
	player._begin_grab_object(can, can.global_position + Vector3(0, 0.6, 0))
	await _shot("held_canister")
	player.held_object = null
	can.queue_free()
	var flare: RigidBody3D = Supply.new()
	flare.kind = "flare"
	world.add_child(flare)
	flare.global_position = player.camera.global_transform * Vector3(0.15, -0.21, -0.42)
	player._begin_grab_object(flare, flare.global_position)
	await _shot("held_flare")
	# The bench in the workshop, with Len's things on it.
	_look(player, shack.to_global(Vector3(2.2, 1.55, -1.0)), shack.to_global(Vector3(2.2, 0.98, -2.5)))
	await _shot("workbench_finds")
	get_tree().quit()


func _look(player: CharacterBody3D, from: Vector3, at: Vector3) -> void:
	player.global_position = from - Vector3.UP * (player.camera.global_position.y - player.global_position.y)
	var to: Vector3 = at - from
	player.rotation.y = atan2(-to.x, -to.z)
	player.look_rotation_x = atan2(to.y, Vector2(to.x, to.z).length())
	player.head.rotation.x = player.look_rotation_x


func _shot(title: String) -> void:
	await _frames(30)
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
