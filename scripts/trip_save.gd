extends Node

const RoadEndHouse := preload("res://scripts/road_end_house.gd")

const SAVE_PATH := "user://trip.save"
const SAVE_VERSION := 1
const AUTOSAVE_SECONDS := 60.0
const MAIN := "res://scenes/main.tscn"

var save_path := SAVE_PATH
var continue_requested := false
var elapsed := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if save_trip():
		get_tree().quit()
	else:
		var world := _world()
		if world:
			world.get_node("PauseMenu").show_save_error()


func _process(delta: float) -> void:
	if get_tree().paused or NetworkManager.is_online() or _world() == null:
		return
	elapsed += delta
	if elapsed >= AUTOSAVE_SECONDS:
		elapsed = 0
		save_trip()


func has_trip() -> bool:
	return not _read_trip().is_empty()


func start_trip(resume: bool) -> void:
	continue_requested = resume
	elapsed = 0
	get_tree().change_scene_to_file(MAIN)


func _world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene and scene.scene_file_path == MAIN else null


func _read_trip() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null or file.get_length() < 4:
		return {}
	var record: Variant = file.get_var(false)
	if not record is Dictionary or record.get("version") != SAVE_VERSION:
		return {}
	if not record.get("player") is Transform3D or not record.get("stops") is Array:
		return {}
	if not record.get("vehicles") is Dictionary or not record.get("objects") is Dictionary:
		return {}
	return record


func save_trip() -> bool:
	var world := _world()
	if world == null or NetworkManager.is_online():
		return true
	var player: Node3D = world.get_node("Player")
	var vehicles: Dictionary = {}
	for car in get_tree().get_nodes_in_group("drivable"):
		var slots: Dictionary = {}
		for slot in car.removable_parts:
			var data: Dictionary = car.removable_parts[slot]
			var part: Node3D = data["part"] if is_instance_valid(data["part"]) else null
			slots[slot] = {
				"installed": data["installed"],
				"id": str(part.get_meta("trip_part_id", "")) if part else "",
			}
		vehicles[str(world.get_path_to(car))] = {
			"transform": car.global_transform,
			"engine": car.current_engine_variant,
			"fuel": car.fuel_amount,
			"charge": car.electric_charge,
			"headlights": car.headlights_enabled,
			"slots": slots,
			"paint": car.get_trip_paint(),
			"panels": car.get_trip_panel_rotations(),
		}

	var objects: Dictionary = {}
	var bodies := get_tree().get_nodes_in_group("vehicle_loose_part")
	bodies.append_array(get_tree().get_nodes_in_group("fuel_canister"))
	bodies.append_array(get_tree().get_nodes_in_group("spray_can"))
	bodies.append_array(get_tree().get_nodes_in_group("food"))
	for group in ["water", "battery_pack", "flare"]:
		bodies.append_array(get_tree().get_nodes_in_group(group))
	for body in bodies:
		if body.is_queued_for_deletion():
			continue
		var part_id := _object_id(world, body)
		var data := {"transform": body.global_transform}
		var welded_to: Variant = body.get_meta("welded_vehicle") if body.has_meta("welded_vehicle") else null
		if is_instance_valid(welded_to):
			data["welded"] = str(world.get_path_to(welded_to))
			data["wired"] = bool(body.get_meta("wired_battery", false))
		if body.is_in_group("fuel_canister"):
			data["fuel"] = body.fuel_amount
		if body.is_in_group("spray_can"):
			data["color"] = body.spray_color
		if body.get_meta("stowed", false):
			data["stowed"] = true
		if body.has_method("set_amount"):
			data["amount"] = body.amount
		if body.get_meta("given", false):
			data["given"] = true
		if body.get_meta("in_container", false):
			data["in_container"] = true
		objects[part_id] = data

	var driving := ""
	if is_instance_valid(player.active_vehicle):
		driving = str(world.get_path_to(player.active_vehicle))
	var road: Node3D = world.get_node("InfiniteRoad")
	var stop_doors := {}
	var car_body_styles := {}
	var legacy_spare_stops: Array = []
	var legacy_stops: Array = []
	var sedan_loadout_stops: Array = []
	for index in road.stops:
		stop_doors[index] = road.stops[index].get_door_state()
		if road.stops[index].legacy_car_spares:
			legacy_spare_stops.append(index)
		if road.stops[index].saved_body_style >= 0:
			car_body_styles[index] = road.stops[index].saved_body_style
		if road.stops[index].legacy_layout:
			legacy_stops.append(index)
		elif road.stops[index].use_sedan_loadout:
			sedan_loadout_stops.append(index)
	var player_pose: Transform3D = player.global_transform
	if player.ending_locked:
		player_pose.origin = player.ending_return_position
	var data := {
		"version": SAVE_VERSION,
		"player": player_pose,
		"look": player.look_rotation_x,
		"vitals": player.vitals.to_save() if player.vitals else {},
		"has_food": true,
		"has_supplies": true,
		"opened": _opened_containers(world),
		"house_seen": RoadEndHouse.seen,
		"driving": driving,
		"first_person": player.active_vehicle.first_person_camera_enabled if not driving.is_empty() else false,
		"vehicle_look": Vector2(player.active_vehicle.camera_yaw, player.active_vehicle.camera_pitch) if not driving.is_empty() else Vector2.ZERO,
		"time": world.get_node("DayNightCycle").time_of_day,
		"stops": road.stops.keys(),
		"garage_doors": world.get_node("Shack").get_door_state(),
		"stop_doors": stop_doors,
		"car_body_styles": car_body_styles,
		"legacy_spare_stops": legacy_spare_stops,
		"legacy_stops": legacy_stops,
		"sedan_loadout_stops": sedan_loadout_stops,
		"vehicles": vehicles,
		"objects": objects,
	}
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _save_failed(FileAccess.get_open_error())
	file.store_var(data, false)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temp_path, save_path)
	if error != OK:
		return _save_failed(error)
	elapsed = 0.0
	return true


func _opened_containers(world: Node) -> Array:
	var opened := []
	for box in get_tree().get_nodes_in_group("loot_box"):
		if box.opened:
			opened.append(str(world.get_path_to(box)))
	return opened


func _object_id(world: Node, body: Node) -> String:
	var id := str(body.get_meta("trip_part_id", ""))
	if id.is_empty():
		id = str(world.get_path_to(body))
		body.set_meta("trip_part_id", id)
	return id


func _save_failed(error: Error) -> bool:
	push_error("Could not save trip: %s" % error_string(error))
	return false


func restore_trip(world: Node) -> void:
	var data := _read_trip()
	if data.is_empty():
		return
	var road: Node3D = world.get_node("InfiniteRoad")
	var player: Node3D = world.get_node("Player")
	player.global_transform = data["player"]
	player.last_safe_position = player.global_position
	player.look_rotation_x = data["look"]
	if player.vitals and data.get("vitals") is Dictionary:
		player.vitals.from_save(data["vitals"])
	RoadEndHouse.seen = data.get("house_seen", false)
	player.head.rotation.x = player.look_rotation_x
	world.get_node("DayNightCycle").time_of_day = data["time"]
	world.get_node("Shack").restore_door_state(data.get("garage_doors", {}))
	var stop_doors: Dictionary = data.get("stop_doors", {})
	var legacy_stops: Array = data.get("legacy_stops", data["stops"])
	var sedan_loadout_stops: Array = data.get("sedan_loadout_stops", [])
	var car_body_styles: Dictionary = data.get("car_body_styles", {})
	var legacy_spare_stops: Array = data.get("legacy_spare_stops", data["stops"] if not data.has("car_body_styles") else [])
	for index in data["stops"]:
		road.spawn_stop(index, 1, index in legacy_stops, index in sedan_loadout_stops, true, clampi(car_body_styles.get(index, 0), 0, 2), index in legacy_spare_stops)
		road.stops[index].restore_door_state(stop_doors.get(index, {}))
	# Recreate supplied parts from older trips only if the save still uses them.
	var starter: Node3D = world.get_node("Car")
	var referenced_parts: Dictionary = data["objects"].duplicate()
	for saved in data["vehicles"].values():
		for state in saved["slots"].values():
			if state["installed"]:
				referenced_parts[state["id"]] = true
	starter._restore_legacy_workshop_parts(referenced_parts)

	var available_parts := {}
	var pending := {}
	for car_path in data["vehicles"]:
		var car: Node3D = world.get_node_or_null(car_path)
		if not car:
			continue
		var saved: Dictionary = data["vehicles"][car_path]
		car.global_transform = saved["transform"]
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.reset_physics_interpolation()
		car.fuel_amount = saved["fuel"]
		car.set_headlights_enabled(saved["headlights"])
		for slot in car.removable_parts:
			var slot_state: Dictionary = saved["slots"].get(slot, {})
			var part: Node3D = car.removable_parts[slot]["part"]
			var original_id := str(part.get_meta("trip_part_id", ""))
			if slot_state.get("installed", true) and slot_state.get("id", original_id) == original_id:
				continue
			var loose: RigidBody3D = car._remove_part_by_type(slot, true)
			if loose:
				available_parts[original_id] = loose
			if slot_state.get("installed", false):
				pending[slot_state["id"]] = [car, slot]

	for body in get_tree().get_nodes_in_group("vehicle_loose_part"):
		var part_id := _object_id(world, body)
		available_parts[part_id] = body
	for part_id in pending:
		var destination: Array = pending[part_id]
		if available_parts.has(part_id):
			var body: RigidBody3D = available_parts[part_id]
			destination[0].install_part(body, destination[1])

	var objects: Dictionary = data["objects"]
	var bodies := get_tree().get_nodes_in_group("vehicle_loose_part")
	bodies.append_array(get_tree().get_nodes_in_group("fuel_canister"))
	bodies.append_array(get_tree().get_nodes_in_group("spray_can"))
	bodies.append_array(get_tree().get_nodes_in_group("food"))
	for group in ["water", "battery_pack", "flare"]:
		bodies.append_array(get_tree().get_nodes_in_group(group))
	for body in bodies:
		if body.is_queued_for_deletion():
			continue
		var part_id := _object_id(world, body)
		if not objects.has(part_id):
			# Food came after older saves; leave it where it lies for them.
			if (body.is_in_group("food") or body.has_method("set_amount")) and not data.has("has_supplies" if body.has_method("set_amount") else "has_food"):
				continue
			body.queue_free()
			continue
		var saved: Dictionary = objects[part_id]
		body.global_transform = saved["transform"]
		if saved.has("fuel"):
			body.fuel_amount = saved["fuel"]
		if saved.has("color"):
			body.set_spray_color(saved["color"])
		if saved.has("amount"):
			body.set_amount(saved["amount"])
		if saved.get("given", false) and body.has_method("handed_over"):
			body.handed_over()
		elif saved.get("given", false):
			body.set_meta("given", true)
			body.show()
			body.freeze = false
			body.collision_layer = 16
			body.collision_mask = 17
		if saved.has("in_container") or body.get_meta("in_container", false):
			body.set_meta("in_container", saved.get("in_container", false))
		if saved.get("stowed", false):
			player.restore_stowed(body)
		if saved.has("welded"):
			var host: Node3D = world.get_node_or_null(saved["welded"])
			if host and host.weld_object(body, true) and saved.get("wired", false):
				body.set_meta("wired_battery", true)

	for car_path in data["vehicles"]:
		var car: Node3D = world.get_node_or_null(car_path)
		if car:
			var legacy_car: bool = car.wheel_model_root != null and not data.has("car_body_styles")
			car.restore_trip_paint(data["vehicles"][car_path]["paint"], legacy_car)
			car.restore_trip_panel_rotations(data["vehicles"][car_path].get("panels", {}), legacy_car)
			car._apply_engine_variant(data["vehicles"][car_path]["engine"])
			car._refresh_electric_capacity()
			car.electric_charge = data["vehicles"][car_path]["charge"]
	var vehicle: Node3D = world.get_node_or_null(data["driving"]) if not data["driving"].is_empty() else null
	if vehicle:
		player._enter_vehicle(vehicle, true)
		var look: Vector2 = data.get("vehicle_look", Vector2.ZERO)
		vehicle.camera_yaw = look.x
		vehicle.camera_pitch = look.y
		vehicle._update_camera_rotation()
		vehicle.set_first_person_camera_enabled(data.get("first_person", false))
	for path in data.get("opened", []):
		var box := world.get_node_or_null(path)
		if box:
			box.open(true)
	road._update_segments()
