extends Node3D
## The thing from the house, out in the open, any time of day: sitting on its
## haunches far off in the desert, watching you. It is only ever where you are
## not looking. Look away once you have seen it and it is gone when you look
## back; stare at it too long and its head jerks, and it is gone.

const Creature := preload("res://scripts/road_creature.gd")
const CLICKS := preload("res://assets/audio/ending/rapid_clicks.wav")
const Terrain := preload("res://scripts/roadside_terrain.gd")
const RoadEndHouse := preload("res://scripts/road_end_house.gd")

var road: Node3D
var dread: Node
var creature: Node3D
var wait := 150.0
var life := 0.0
var seen_for := 0.0
var unseen_for := 0.0
var noticed := false
var patience := 2.0
var leaving := -1.0
var crouched := false
var clock := 0.0
var click: AudioStreamPlayer3D


func _ready() -> void:
	creature = Creature.new()
	creature.name = "Watcher"
	add_child(creature)
	creature.hide()
	click = AudioStreamPlayer3D.new()
	click.stream = CLICKS
	click.unit_size = 14.0
	click.volume_db = -12.0
	click.max_distance = 120.0
	creature.add_child(click)
	click.position.y = 1.2


func watch(delta: float, player: Node3D, camera: Camera3D, allowed: bool, daylight: float, storm: float) -> void:
	clock += delta
	if creature.visible:
		_while_out(delta, player, camera, allowed)
		return
	if not allowed:
		return
	# More often at night and in a storm; half as often with fewer scares.
	var pace := lerpf(2.0, 1.0, daylight) * (2.5 if storm > 0.6 else 1.0) * (0.5 if GameSettings.reduce_scares else 1.0)
	wait -= delta * pace
	if wait <= 0.0:
		_appear(player, camera, storm)


func hide_now() -> void:
	creature.hide()
	leaving = -1.0


func _appear(player: Node3D, camera: Camera3D, storm: float) -> void:
	## Somewhere out of view, in the open, facing you.
	var near := 12.0 if storm > 0.6 else 22.0
	var far := 22.0 if storm > 0.6 else 42.0
	for attempt in 24:
		var angle := randf() * TAU
		var distance := randf_range(near, far)
		var spot := player.global_position + Vector3(sin(angle), 0, cos(angle)) * distance
		spot.y = Terrain.LEVEL
		if _in_view(camera, spot + Vector3.UP, 0.25) or not _open_ground(spot):
			continue
		creature.global_position = spot
		var to := player.global_position - spot
		creature.rotation = Vector3(0, atan2(to.x, to.z), 0)
		crouched = randf() < 0.3
		creature.tilt = randf_range(0.2, 0.5) * (-1.0 if randf() < 0.5 else 1.0)
		creature.jitter = 0.35
		creature.reset_physics_interpolation()
		creature.show()
		life = 50.0
		seen_for = 0.0
		unseen_for = 0.0
		noticed = false
		leaving = -1.0
		patience = randf_range(1.6, 3.2)
		_pose(camera)
		return
	wait = 4.0


func _while_out(delta: float, player: Node3D, camera: Camera3D, allowed: bool) -> void:
	_pose(camera)
	if leaving >= 0.0:
		# Caught staring: its head snaps, then it is not there.
		leaving += delta
		creature.tilt += delta * 9.0 * signf(creature.tilt)
		if leaving > 0.22:
			_gone(randf_range(140.0, 300.0))
		return
	var chest := creature.global_position + Vector3.UP * 0.9
	var watched := _in_view(camera, chest, 0.0) and _clear_line(player, camera)
	# Somewhere on screen is not the same as looked at: it counts as seen once
	# it has been near the middle of the view, and as stared at only there.
	var off_centre := (chest - camera.global_position).normalized().angle_to(-camera.global_basis.z)
	if watched:
		unseen_for = 0.0
		if off_centre < deg_to_rad(22.0):
			noticed = true
		if noticed and off_centre < deg_to_rad(12.0):
			seen_for += delta
	else:
		unseen_for += delta
	life -= delta
	var distance := player.global_position.distance_to(creature.global_position)
	if noticed and unseen_for > 0.12:
		# You looked away. It does not wait for you to look back.
		_gone(randf_range(120.0, 260.0))
	elif noticed and seen_for > patience:
		leaving = 0.0
		creature.jitter = 1.0
		click.pitch_scale = randf_range(0.75, 0.9)
		click.play()
	elif not allowed or distance > 100.0 or (not watched and (life <= 0.0 or distance < 10.0)):
		# Never seen, or the moment has passed: gone quietly while out of view.
		if not watched:
			_gone(randf_range(40.0, 90.0) if not noticed else randf_range(120.0, 260.0))


func _gone(next: float) -> void:
	creature.hide()
	creature.jitter = 0.35
	leaving = -1.0
	wait = next


func _pose(camera: Camera3D) -> void:
	var eye: Vector3 = creature.to_local(camera.global_position)
	var up: Array[Vector3] = [Vector3.UP, Vector3.UP]
	if crouched:
		creature.pose_contacts(Vector3(0, 0.62, 0.38), Vector3(0, 0.56, -0.36), eye,
			[Vector3(-0.24, 0, 0.62), Vector3(0.24, 0, 0.62)] as Array[Vector3], up,
			[Vector3(-0.2, 0, -0.36), Vector3(0.2, 0, -0.36)] as Array[Vector3], clock, 0.0, up)
	else:
		creature.pose_contacts(Vector3(0, 1.05, 0.2), Vector3(0, 0.45, -0.2), eye,
			[Vector3(-0.2, 0, 0.42), Vector3(0.2, 0, 0.42)] as Array[Vector3], up,
			[Vector3(-0.24, 0, -0.1), Vector3(0.24, 0, -0.1)] as Array[Vector3], clock, 0.0, up,
			Vector3(0, 0.5, -1).normalized())
	# Eyeshine after dark, in the headlights.
	var night := 1.0 - _daylight()
	creature.set_eyes(3.5 * night, 1.0)


func _in_view(camera: Camera3D, point: Vector3, margin: float) -> bool:
	## On screen, with margin (in radians) added around the edges.
	if camera.is_position_behind(point):
		return false
	var to := (point - camera.global_position).normalized()
	var forward := -camera.global_basis.z
	var half_v := deg_to_rad(camera.fov) * 0.5 + margin
	var size := camera.get_viewport().get_visible_rect().size
	var half_h := atan(tan(deg_to_rad(camera.fov) * 0.5) * size.x / maxf(size.y, 1.0)) + margin
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var across := atan2(to.dot(right), to.dot(forward))
	var rise := atan2(to.dot(up), to.dot(forward))
	return absf(across) < half_h and absf(rise) < half_v


func _clear_line(player: Node3D, camera: Camera3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, creature.global_position + Vector3.UP * 0.9, 1)
	var skip: Array[RID] = []
	if player is CollisionObject3D:
		skip.append((player as CollisionObject3D).get_rid())
	var car: Variant = player.get("active_vehicle")
	if car is CollisionObject3D and is_instance_valid(car):
		skip.append((car as CollisionObject3D).get_rid())
	query.exclude = skip
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _open_ground(spot: Vector3) -> bool:
	## Not on the road, not by the workshop, a station, the cabin or the house.
	if road == null:
		return false
	var lateral: float = spot.x - road._road_x(spot.z)
	if absf(lateral) < 9.0:
		return false
	if spot.z > -70.0 and spot.z < 40.0 and absf(spot.x) < 60.0:
		return false
	for index in road.stops:
		if (road.stops[index] as Node3D).global_position.distance_to(spot) < 26.0:
			return false
	var cabin := road.get_node_or_null("StrangerHouse") as Node3D
	if cabin and cabin.global_position.distance_to(spot) < 40.0:
		return false
	var house_z: float = RoadEndHouse.story.get("house_z", -1.0e9)
	if absf(spot.z - house_z) < 120.0:
		return false
	return true


func _daylight() -> float:
	var cycle := get_tree().current_scene.get_node_or_null("DayNightCycle") if get_tree().current_scene else null
	return cycle.daylight if cycle and "daylight" in cycle else 1.0
