extends Node
## The car beside the workshop, and roadside trees and pines, in the real world
## light. Screenshots into KM0_CHECK_DIR.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")

var world: Node
var player: CharacterBody3D
var road: Node3D
var dir := OS.get_environment("KM0_CHECK_DIR")


func _ready() -> void:
	RoadEndHouse.seen = false
	RoadEndHouse.story = {}
	world = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var guide := world.get_node_or_null("TutorialGuide")
	if guide:
		guide.queue_free()
	var menu := world.get_node_or_null("PauseMenu")
	if menu and menu.has_method("_close_tutorial"):
		menu._close_tutorial()
	var cycle := world.get_node_or_null("DayNightCycle")
	cycle.time_of_day = float(OS.get_environment("KM0_TIME")) if OS.has_environment("KM0_TIME") else 0.4
	cycle.day_length_seconds = 0.0
	road = world.get_node("InfiniteRoad")
	road.begin_streaming()
	player = get_tree().get_first_node_in_group("local_player")
	player.set_physics_process(false)

	var car: Node3D = world.get_node("Car")
	var c := car.global_position
	var shack: Node3D = world.get_node("Shack")
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	print("car ", c, " basis z ", car.global_basis.z, " shack ", shack.global_position)
	var inside := [Vector3(-3.0, 1.6, 2.8), Vector3(2.6, 1.6, 2.8), Vector3(-3.0, 1.7, -3.2), Vector3(2.4, 2.2, -3.0)]
	for i in inside.size():
		await _view(shack.to_global(inside[i]), c + Vector3.UP * 0.5, "car_%d" % i)
	if OS.get_environment("KM0_PERF") == "1":
		await _perf("workshop_car", shack.to_global(inside[0]), c + Vector3.UP * 0.5)
	for wreck in get_tree().get_nodes_in_group("drivable"):
		if wreck != car and (wreck.global_position - c).length() < 40.0:
			var w: Vector3 = wreck.global_position
			await _view(w + Vector3(4.0, 1.6, 4.5), w + Vector3.UP * 0.6, "other_car")
			break

	var shots := {"Tree": 0, "Pine": 0, "Dead Tree": 0}
	for index in range(-1, -260, -1):
		if shots.values().all(func(n): return n >= 2):
			break
		var z: float = (index + 0.5) * road.segment_length
		player.global_position = road._sample(z, 0.0, 1.2)
		await _frames(6)
		for kind in shots:
			if shots[kind] >= 2:
				continue
			var found := _find(kind)
			if found.is_empty():
				continue
			var at: Vector3 = found[0]
			var side: float = found[1]
			var tag: String = kind.to_lower().replace(" ", "_")
			var from: Vector3 = road._sample(at.z + 14.0, 0.0, 1.7)
			from.x = at.x - side * 12.0
			await _view(from, at + Vector3.UP * 3.0, "%s_%d" % [tag, shots[kind]])
			var near := at + (from - at).normalized() * 5.5
			near.y = at.y + 1.7
			await _view(near, at + Vector3.UP * 2.6, "%s_%d_near" % [tag, shots[kind]])
			if tag == "pine" and shots[kind] == 0 and OS.get_environment("KM0_PERF") == "1":
				await _perf("forest", from, at + Vector3.UP * 3.0)
				await _perf("forest_near", near, at + Vector3.UP * 2.6)
			shots[kind] += 1
	print("shots ", shots)
	get_tree().quit()


func _find(kind: String) -> Array:
	for node in road.find_children(kind, "MultiMeshInstance3D", true, false):
		var mesh: MultiMesh = node.multimesh
		for i in mesh.instance_count:
			var at: Vector3 = node.global_transform * mesh.get_instance_transform(i).origin
			var off: float = at.x - road._sample(at.z, 0.0, 0.0).x
			if absf(off) < 30.0 and (player.global_position - at).length() < 60.0:
				return [at, signf(off)]
	return []


func _view(from: Vector3, at: Vector3, title: String) -> void:
	player.global_position = from - Vector3.UP * (player.camera.global_position.y - player.global_position.y)
	await _frames(3)
	_face(at)
	await _frames(25)
	_face(at)
	await _frames(5)
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))


func _face(at: Vector3) -> void:
	var to: Vector3 = at - player.camera.global_position
	player.rotation.y = atan2(-to.x, -to.z)
	player.look_rotation_x = atan2(to.y, Vector2(to.x, to.z).length())
	player.head.rotation.x = player.look_rotation_x


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _perf(title: String, from: Vector3, at: Vector3) -> void:
	var keep := dir
	dir = ""
	await _view(from, at, "")
	dir = keep
	var cap := Engine.max_fps
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var rid := get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(60)
	var gpu := 0.0
	var start := Time.get_ticks_usec()
	for i in 150:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var frame := (Time.get_ticks_usec() - start) / 150.0 / 1000.0
	print("perf %s: frame %5.2f ms, gpu %5.2f ms, draws %d, prims %d" % [title, frame, gpu / 150.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	Engine.max_fps = cap
