extends Node
## The watcher in the desert: appears out of view, is gone once you look away
## after seeing it, and is gone if you stare at it too long.

var world: Node
var player: CharacterBody3D
var glimpse: Node3D


func _ready() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var guide := world.get_node_or_null("TutorialGuide")
	if guide:
		guide.queue_free()
	var cycle := world.get_node_or_null("DayNightCycle")
	cycle.time_of_day = float(OS.get_environment("KM0_TOD")) if OS.has_environment("KM0_TOD") else 0.4
	cycle.day_length_seconds = 0.0
	var road: Node3D = world.get_node("InfiniteRoad")
	player = get_tree().get_first_node_in_group("local_player")
	player.global_position = road._sample(-900.0, 0.0, 1.1)
	_face(player.global_position + Vector3(0, 0, -50))
	await _frames(30)
	glimpse = world.find_child("Glimpse", true, false)
	var dir := OS.get_environment("KM0_CHECK_DIR")
	# 1. Look away after seeing it.
	glimpse.wait = 0.0
	await _frames(3)
	var creature: Node3D = glimpse.creature
	print("appeared: ", creature.visible, " in view at spawn: ", glimpse._in_view(player.camera, creature.global_position + Vector3.UP, 0.0),
		" distance ", snappedf(player.global_position.distance_to(creature.global_position), 0.1))
	_face(creature.global_position + Vector3.UP * 0.8)
	await _seconds(0.6)
	print("looking at it: visible=", creature.visible, " noticed=", glimpse.noticed)
	for n in 2:
		await _frames(8)
		get_viewport().get_texture().get_image().save_png(dir + "/glimpse_seen.png")
	_face(player.global_position + (player.global_position - creature.global_position))
	await _seconds(0.3)
	print("looked away: visible=", creature.visible)
	_face(creature.global_position + Vector3.UP * 0.8)
	await _seconds(0.2)
	print("looked back: visible=", creature.visible)
	# 2. Stare too long.
	_face(player.global_position + Vector3(0, 0, -50))
	glimpse.wait = 0.0
	await _frames(3)
	_face(creature.global_position + Vector3.UP * 0.8)
	var clock := 0.0
	var vanished_at := -1.0
	while clock < 5.0:
		await get_tree().process_frame
		clock += get_process_delta_time()
		if not creature.visible and vanished_at < 0.0:
			vanished_at = clock
	print("stared: vanished after ", snappedf(vanished_at, 0.01), " s (patience ", snappedf(glimpse.patience, 0.01), ")")
	get_tree().quit()


func _face(at: Vector3) -> void:
	var to: Vector3 = at - player.camera.global_position
	player.rotation.y = atan2(-to.x, -to.z)
	player.look_rotation_x = atan2(to.y, Vector2(to.x, to.z).length())
	player.head.rotation.x = player.look_rotation_x


func _seconds(t: float) -> void:
	var clock := 0.0
	while clock < t:
		await get_tree().process_frame
		clock += get_process_delta_time()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
