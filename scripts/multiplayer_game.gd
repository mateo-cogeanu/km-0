extends Node3D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CAR_SCENE := preload("res://scenes/car.tscn")


func _ready() -> void:
	var online := NetworkManager.is_online()
	var garage := $Shack as Node3D
	for placement in [[$FuelCanister, Vector3(3.51, 0.08, -0.86)],
			[$SprayCan, Vector3(2.86, 1.39, -3.17)]]:
		var supply: RigidBody3D = placement[0]
		supply.global_transform = garage.global_transform * Transform3D(Basis.IDENTITY, placement[1])
		supply.reset_physics_interpolation()
	if not online:
		$Car.global_transform = _garage_car_transform(garage, 0)
		$Car.reset_physics_interpolation()
		_place_player($Player, garage, 0)
		$Player.player_name = GameSettings.player_name
		if TripSave.continue_requested:
			TripSave.continue_requested = false
			$Car.start_with_removed_panels = false
			$Car.start_with_random_body_color = false
			TripSave.restore_trip.call_deferred(self)
		else:
			_add_workshop_batteries($Car, garage)
		$InfiniteRoad.begin_streaming.call_deferred()
		return
	$Player.queue_free()
	$Car.queue_free()
	await get_tree().process_frame
	var ids: Array = NetworkManager.players.keys()
	ids.sort()
	var car_count := ceili(ids.size() / 4.0)
	garage.get_node("GarageModel").add_coop_bays(car_count - 1)
	for index in car_count:
		var car := CAR_SCENE.instantiate()
		car.name = "Car_%d" % (index + 1)
		car.transform = global_transform.affine_inverse() * _garage_car_transform(garage, index)
		add_child(car)
		if index == 0:
			_add_workshop_batteries(car, garage)
			$InfiniteRoad.target = car

	for index in ids.size():
		var peer_id: int = int(ids[index])
		var player := PLAYER_SCENE.instantiate()
		player.name = str(peer_id)
		player.player_name = str(NetworkManager.players[peer_id].get("name", "Player"))
		_place_player(player, garage, index / 4)
		var offset := float(index % 4) - 1.5
		player.position += global_transform.basis.inverse() * garage.global_basis.x * offset * 0.86
		player.set_multiplayer_authority(peer_id)
		add_child(player)
	NetworkManager.player_disconnected.connect(_remove_disconnected_player)

	# Select the local view after all player and car cameras have entered the viewport.
	var local_player := get_node(str(multiplayer.get_unique_id()))
	local_player.camera.make_current()
	# Nobody moves and nothing is handed out until every machine has loaded:
	# anything the host sent before a slower machine was here would be lost.
	local_player.ending_locked = true
	local_player.tip_override = "Waiting for everyone to arrive…"
	local_player.tip_time = 60.0
	if multiplayer.is_server():
		NetworkManager.arrived_late.connect(_catch_up)
		var waited := 0.0
		while not NetworkManager.all_arrived() and waited < ARRIVAL_TIMEOUT:
			await get_tree().create_timer(0.25).timeout
			waited += 0.25
		_start_trip.rpc()
	else:
		NetworkManager.report_arrived()


const ARRIVAL_TIMEOUT := 45.0
var started := false


@rpc("authority", "call_local", "reliable")
func _start_trip() -> void:
	if started:
		return
	started = true
	NetworkManager.trip_started = true
	var local_player := get_node_or_null(str(multiplayer.get_unique_id()))
	if local_player:
		local_player.ending_locked = false
		local_player.tip_override = ""
		local_player.tip_time = 0.0
	$InfiniteRoad.begin_streaming()


func _catch_up(peer_id: int) -> void:
	## Someone loaded after the trip had already started: let them in and
	## hand them the stations already out on the road.
	_start_trip.rpc_id(peer_id)
	$InfiniteRoad.replay_stops_to(peer_id)


func _garage_car_transform(garage: Node3D, index: int) -> Transform3D:
	var bay_x: float = garage.get_node("GarageModel").get_bay_x(index)
	return garage.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(bay_x, 0.18, 0.25))


func _place_player(player: Node3D, garage: Node3D, index: int) -> void:
	var bay_x: float = garage.get_node("GarageModel").get_bay_x(index)
	var spawn := garage.global_transform * Transform3D(Basis.IDENTITY, Vector3(bay_x, 1.04, 3.34))
	player.transform = global_transform.affine_inverse() * spawn
	if player.is_inside_tree():
		player.last_safe_position = player.global_position
		player.reset_physics_interpolation()


func _add_workshop_batteries(car: Node3D, garage: Node3D) -> void:
	car._spawn_aux_battery(self, "ExtraBatteryLoose", garage.to_global(Vector3(-2.35, 0.24, -4.48)))
	car._spawn_aux_battery(self, "ExtraBatteryLoose2", garage.to_global(Vector3(-2.48, 0.24, -4.96)))


func _remove_disconnected_player(peer_id: int) -> void:
	var player := get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	for vehicle in get_tree().get_nodes_in_group("drivable"):
		vehicle.remove_disconnected_rider(peer_id)
