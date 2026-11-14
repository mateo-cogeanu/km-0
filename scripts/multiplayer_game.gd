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
		$Player.player_name = "Player"
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
	garage.get_node("GarageModel").add_coop_bays(ids.size() - 1)
	for index in ids.size():
		var peer_id: int = int(ids[index])
		var car := CAR_SCENE.instantiate()
		car.name = "Car_%s" % peer_id
		car.transform = global_transform.affine_inverse() * _garage_car_transform(garage, index)
		car.set_multiplayer_authority(peer_id)
		add_child(car)
		if index == 0:
			_add_workshop_batteries(car, garage)
		if $InfiniteRoad and peer_id == multiplayer.get_unique_id():
			$InfiniteRoad.target = car

		var player := PLAYER_SCENE.instantiate()
		player.name = str(peer_id)
		player.player_name = str(NetworkManager.players[peer_id].get("name", "Player"))
		_place_player(player, garage, index)
		player.set_multiplayer_authority(peer_id)
		add_child(player)

	# Select the local view after all player and car cameras have entered the viewport.
	var local_player := get_node(str(multiplayer.get_unique_id()))
	local_player.camera.make_current()
	$InfiniteRoad.begin_streaming()


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
