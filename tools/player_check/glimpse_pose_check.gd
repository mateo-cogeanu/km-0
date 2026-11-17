extends Node
## Poses for the creature seen out in the desert, side by side, for a screenshot.

const Creature := preload("res://scripts/road_creature.gd")
var creatures: Array = []
var clock := 0.0
var cam: Camera3D


func _ready() -> void:
	var world: Node = load("res://scenes/main.tscn").instantiate()
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
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	player.global_position = road._sample(-400.0, 0.0, 1.1)
	await _frames(30)
	cam = player.camera
	var dist := float(OS.get_environment("KM0_DIST")) if OS.has_environment("KM0_DIST") else 14.0
	for i in 3:
		var c := Creature.new()
		world.add_child(c)
		var at: Vector3 = road._sample(-400.0 - dist, 14.0 + (i - 1) * 3.0)
		c.global_position = Vector3(at.x, -0.04, at.z)
		c.look_at(Vector3(player.global_position.x, -0.04, player.global_position.z), Vector3.UP, true)
		creatures.append(c)
	player.look_at(creatures[1].global_position + Vector3.UP * 1.0, Vector3.UP)
	player.rotation.x = 0
	player.head.rotation.x = -0.02
	await _frames(40)
	var dir := OS.get_environment("KM0_CHECK_DIR")
	for n in 2:
		await _frames(10)
		get_viewport().get_texture().get_image().save_png(dir + "/glimpse_pose.png")
	get_tree().quit()


func _process(delta: float) -> void:
	clock += delta
	if cam == null:
		return
	for i in creatures.size():
		var c: Node3D = creatures[i]
		var eye: Vector3 = c.to_local(cam.global_position)
		var up: Array[Vector3] = [Vector3.UP, Vector3.UP]
		match i:
			0: # crouched on all fours, watching
				c.pose_contacts(Vector3(0, 0.62, 0.38), Vector3(0, 0.56, -0.36), eye, [Vector3(-0.24, 0, 0.62), Vector3(0.24, 0, 0.62)] as Array[Vector3], up,
					[Vector3(-0.2, 0, -0.36), Vector3(0.2, 0, -0.36)] as Array[Vector3], clock, 0.0, up)
			1: # standing upright, arms hanging
				c.pose_contacts(Vector3(0, 1.66, 0.04), Vector3(0, 0.95, 0.0), eye, [Vector3(-0.36, 0.55, 0.14), Vector3(0.36, 0.55, 0.14)] as Array[Vector3],
					[Vector3.RIGHT, Vector3.LEFT] as Array[Vector3], [Vector3(-0.17, 0, 0.0), Vector3(0.17, 0, 0.0)] as Array[Vector3], clock, 0.0, up, Vector3.FORWARD)
			2: # sitting up on its haunches, hands planted
				c.pose_contacts(Vector3(0, 1.05, 0.2), Vector3(0, 0.45, -0.2), eye, [Vector3(-0.2, 0, 0.42), Vector3(0.2, 0, 0.42)] as Array[Vector3], up,
					[Vector3(-0.24, 0, -0.1), Vector3(0.24, 0, -0.1)] as Array[Vector3], clock, 0.0, up, Vector3(0, 0.5, -1).normalized())
		c.tilt = 0.35


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
