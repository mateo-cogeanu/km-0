extends Node
## Every vehicle on the desert road in one pass: the three car bodies, the
## dashboard from the driver's seat, the bicycle and motorbike, Len's van, a
## roadside wreck and the County car. Screenshots into KM0_CHECK_DIR, then
## frame time looking at the cars (KM0_PERF=0 skips it).

const SEDAN := preload("res://scenes/car.tscn")
const BIKE := preload("res://scenes/two_wheeler.tscn")
const LenVan := preload("res://scripts/len_van.gd")

var world: Node
var road: Node3D
var cam := Camera3D.new()
var dir := OS.get_environment("KM0_CHECK_DIR")


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
	cycle.time_of_day = 0.4
	cycle.day_length_seconds = 0.0
	road = world.get_node("InfiniteRoad")
	var player: Node3D = get_tree().get_first_node_in_group("local_player")
	var base: Vector3 = road._sample(-200.0, 22.0, 0.0)
	player.global_position = base + Vector3(0, 1.2, 30)
	player.set_physics_process(false)
	world.add_child(cam)
	cam.fov = 50.0
	cam.make_current()
	await _frames(30)
	var cars: Array[Node3D] = []
	var colors := [Color("#6f8a84"), Color("#8c3a2e"), Color("#c9c1a8")]
	for style in 3:
		var car: RigidBody3D = SEDAN.instantiate()
		car.body_style = style
		car.start_with_random_body_color = false
		car.start_with_removed_panels = false
		car.fuel_amount = 0.0
		car.position = base + Vector3(style * 6.5, 0.25, 0)
		car.rotation.y = 0.6
		world.add_child(car)
		cars.append(car)
		car.paint_named_part("Chassis", colors[style], 1.0)
		for door in ["FL_Door", "FR_Door", "RL_Door", "RR_Door"]:
			car.paint_named_part(door, colors[style], 1.0)
	for i in 2:
		var bike: RigidBody3D = BIKE.instantiate()
		bike.motorized = i == 1
		bike.position = base + Vector3(20.0 + i * 3.5, 0.4, 0)
		bike.rotation.y = PI * 0.5
		world.add_child(bike)
		cars.append(bike)
	var van := LenVan.new()
	world.add_child(van)
	van.global_position = base + Vector3(-8.0, 0, 0)
	van.rotation.y = 0.5
	var county_holder := Node3D.new()
	world.add_child(county_holder)
	county_holder.global_position = base + Vector3(0, 0, 14.0)
	road._add_county_car(county_holder, Vector3(0, 0, 10), Vector3(0, 0, -10))
	await _frames(120)
	for i in 3:
		var car := cars[i]
		await _view(car.to_global(Vector3(-3.6, 1.5, -4.2)), car.to_global(Vector3(0, 0.75, -0.3)), "car_%d_front" % i)
		await _view(car.to_global(Vector3(3.4, 1.4, 4.4)), car.to_global(Vector3(0, 0.75, 0.3)), "car_%d_back" % i)
	await _view(cars[0].to_global(Vector3(-0.41, 1.17, 0.12)), cars[0].to_global(Vector3(-0.41, 0.9, -0.9)), "car_0_dash")
	await _view(cars[0].to_global(Vector3(-2.3, 0.75, -1.9)), cars[0].to_global(Vector3(-0.82, 0.39, -1.4)), "car_0_wheel")
	await _view(cars[3].to_global(Vector3(2.6, 1.1, 0.4)), cars[3].to_global(Vector3(0, 0.6, 0)), "bicycle")
	await _view(cars[4].to_global(Vector3(2.6, 1.1, 0.4)), cars[4].to_global(Vector3(0, 0.6, 0)), "motorbike")
	await _view(van.to_global(Vector3(-4.2, 1.7, -5.0)), van.to_global(Vector3(0, 1.0, 0)), "van")
	await _view(van.to_global(Vector3(3.8, 2.1, -3.9)), van.to_global(Vector3(0.2, 1.1, -1.0)), "van_cab")
	var county := county_holder.get_node("CountyCar") as Node3D
	await _view(county.to_global(Vector3(-4.0, 1.6, -3.5)), county.to_global(Vector3(0, 0.7, 0)), "county")
	# The first roadside wreck.
	var wrecks: Node = road.wrecks
	var first := 0
	for index in range(-9, -160, -1):
		if wrecks.has_wreck(index):
			first = index
			break
	player.global_position = road._sample((first + 0.5) * road.segment_length, 0.0, 1.2)
	await _frames(60)
	var wreck := road.get_node_or_null("Road_%d/Wreck" % first) as Node3D
	if wreck:
		await _view(wreck.to_global(Vector3(-4.0, 1.6, -4.0)), wreck.to_global(Vector3(0, 0.6, 0)), "wreck")
		await _view(wreck.to_global(Vector3(3.5, 1.4, 3.5)), wreck.to_global(Vector3(0, 0.6, 0)), "wreck_back")
	if OS.get_environment("KM0_PERF") != "0":
		player.global_position = base + Vector3(0, 1.2, 30)
		await _frames(30)
		await _perf("cars", base + Vector3(6.5, 1.6, 10.0), base + Vector3(6.5, 0.7, 0))
	get_tree().quit()


func _view(from: Vector3, at: Vector3, title: String) -> void:
	cam.global_position = from
	cam.look_at(at)
	await _frames(12)
	if not dir.is_empty() and not title.is_empty():
		get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))


func _perf(title: String, from: Vector3, at: Vector3) -> void:
	await _view(from, at, "")
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _frames(60)
	var start := Time.get_ticks_usec()
	for i in 150:
		await get_tree().process_frame
	var frame := (Time.get_ticks_usec() - start) / 150.0 / 1000.0
	print("perf %s: frame %5.2f ms (%3.0f fps), draws %d, prims %d" % [title, frame, 1000.0 / frame,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
