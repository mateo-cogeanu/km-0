extends Node
## The player's car in the workshop and out in the sun, close up on the paint,
## wheels and cabin. Screenshots into KM0_CHECK_DIR.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")

var world: Node
var player: CharacterBody3D
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
	cycle.time_of_day = 0.4
	cycle.day_length_seconds = 0.0
	world.get_node("InfiniteRoad").begin_streaming()
	player = get_tree().get_first_node_in_group("local_player")
	player.set_physics_process(false)
	for layer in world.find_children("*", "CanvasLayer", true, false):
		layer.visible = false

	var car: RigidBody3D = world.get_node("Car")
	var shack: Node3D = world.get_node("Shack")
	await _frames(30)
	var c := car.global_position
	var lowest := INF
	for tire in car.find_children("Tire", "MeshInstance3D", true, false):
		var box: AABB = (tire as MeshInstance3D).global_transform * (tire as MeshInstance3D).get_aabb()
		lowest = minf(lowest, box.position.y)
		print("tyre ", tire.get_parent().name, " size ", box.size, " centre ", snappedf((tire as MeshInstance3D).global_position.y, 0.001), " bottom ", snappedf(box.position.y, 0.001), " visible ", tire.is_visible_in_tree())
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.2, c + Vector3.DOWN * 3.0, 1, [car.get_rid()]))
	print("car y ", c.y, " lowest tyre bottom ", lowest, " floor ", hit.get("position", Vector3.INF).y, " ", hit.get("collider"))
	var inside := [Vector3(-3.0, 1.6, 2.8), Vector3(2.4, 2.2, -3.0)]
	for i in inside.size():
		await _view(shack.to_global(inside[i]), c + Vector3.UP * 0.5, "shop_%d" % i)
	var right := car.global_basis.x
	var fwd := -car.global_basis.z
	await _view(c + right * 2.2 + fwd * 1.2 + Vector3.UP * 0.9, c + right * 0.8 + fwd * 1.4 + Vector3.UP * 0.35, "wheel_close")
	await _view(c + right * 1.9 + Vector3.UP * 1.4, c - right * 0.2 + Vector3.UP * 0.6, "cabin")

	# Out in the sun on the forecourt.
	car.freeze = true
	var out := shack.to_global(Vector3(-2.0, 0.0, 12.0))
	car.global_position = out + Vector3.UP * (c.y - shack.global_position.y)
	await _frames(20)
	c = car.global_position
	right = car.global_basis.x
	fwd = -car.global_basis.z
	await _view(c + fwd * 5.0 + right * 3.5 + Vector3.UP * 1.6, c + Vector3.UP * 0.6, "sun_front")
	await _view(c - fwd * 5.0 - right * 3.5 + Vector3.UP * 1.6, c + Vector3.UP * 0.6, "sun_rear")
	await _view(c + right * 4.5 + Vector3.UP * 1.0, c + Vector3.UP * 0.6, "sun_side")
	await _view(c + right * 2.0 - fwd * 0.5 + Vector3.UP * 1.9, c + right * 0.5 + fwd * 1.0 + Vector3.UP * 0.8, "sun_close")
	await _view(c - fwd * 2.0 + right * 6.0 + Vector3.UP * 3.0, shack.global_position + Vector3.UP * 1.5, "sun_with_shack")
	get_tree().quit()


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
