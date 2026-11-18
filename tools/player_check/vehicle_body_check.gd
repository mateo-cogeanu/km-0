extends Node
## The Blender body panels still work as panels: a dent deforms them, a door
## comes off and goes back on, spray paint saves and restores onto a new car.
## Screenshots into KM0_CHECK_DIR.

const SEDAN := preload("res://scenes/car.tscn")

var world: Node
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
	var road: Node3D = world.get_node("InfiniteRoad")
	var player: Node3D = get_tree().get_first_node_in_group("local_player")
	var base: Vector3 = road._sample(-200.0, 22.0, 0.0)
	player.global_position = base + Vector3(0, 1.2, 30)
	player.set_physics_process(false)
	world.add_child(cam)
	cam.make_current()
	for style in 3:
		var car: RigidBody3D = SEDAN.instantiate()
		car.body_style = style
		car.start_with_random_body_color = false
		car.start_with_removed_panels = false
		car.position = base + Vector3(style * 6.5, 0.3, 0)
		world.add_child(car)
		await _frames(60)
		var body := car.find_child("BodyPaint", true, false) as MeshInstance3D
		var door := car.find_child("FL_Door", true, false) as Node3D
		var skin := door.get_node("DoorSkin") as MeshInstance3D
		print("style %d: body verts %d, door verts %d, deformable %d" % [style, body.mesh.surface_get_array_len(0),
			skin.mesh.surface_get_array_len(0), car.deformable_meshes.size()])
		# A dent in the left front wing.
		var before: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		car._apply_collision_deformation(car.to_global(Vector3(-0.9, 0.62, -1.75)), car.global_basis.x, 22.0)
		var after: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var moved := 0
		var deepest := 0.0
		for i in mini(before.size(), after.size()):
			var d := before[i].distance_to(after[i])
			if d > 0.001:
				moved += 1
			deepest = maxf(deepest, d)
		print("  dent: %d vertices moved, deepest %.3f m" % [moved, deepest])
		if style == 0:
			_look(car.to_global(Vector3(-3.0, 1.2, -3.2)), car.to_global(Vector3(-0.6, 0.6, -1.4)))
			await _shot("dent")
		# Door off, and back on.
		var area: Area3D = car.removable_parts["door_fl"]["area"]
		var loose: RigidBody3D = car.remove_installed_part(area, true)
		await _frames(20)
		print("  door off: ", loose != null, " installed flag: ", car.removable_parts["door_fl"]["installed"])
		if style == 0:
			_look(car.to_global(Vector3(-3.4, 1.4, 0.5)), car.to_global(Vector3(0, 0.8, -0.4)))
			await _shot("door_off")
		var back_on: bool = car.install_part(loose, "door_fl") if loose else false
		await _frames(10)
		print("  door back: ", back_on, " installed flag: ", car.removable_parts["door_fl"]["installed"])
		# Spray paint, save, restore onto a new car.
		car.paint_named_part("FL_Door", Color("#3a6ea5"), 1.0)
		car.paint_named_part("Chassis", Color("#b8452e"), 1.0)
		var saved: Dictionary = car.get_trip_paint()
		var twin: RigidBody3D = SEDAN.instantiate()
		twin.body_style = style
		twin.start_with_random_body_color = false
		twin.start_with_removed_panels = false
		twin.position = base + Vector3(style * 6.5, 0.3, 8.0)
		world.add_child(twin)
		await _frames(30)
		twin.restore_trip_paint(saved)
		await _frames(5)
		var twin_door := twin.find_child("FL_Door", true, false).get_node("DoorSkin") as MeshInstance3D
		var twin_body := twin.find_child("BodyPaint", true, false) as MeshInstance3D
		print("  paint restored: door %s body %s (saved %d panels)" % [(twin_door.material_override as StandardMaterial3D).albedo_color.to_html(false),
			(twin_body.material_override as StandardMaterial3D).albedo_color.to_html(false), saved.size()])
		if style == 0:
			_look(twin.to_global(Vector3(-3.6, 1.5, -3.8)), twin.to_global(Vector3(0, 0.7, 0)))
			await _shot("paint_restored")
	get_tree().quit()


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)


func _shot(title: String) -> void:
	await _frames(10)
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
