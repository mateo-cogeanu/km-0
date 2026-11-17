extends Node
## Engine swaps change how loud the truck is: stock, then the electric motor
## from the flooded car, then the V8.

func _ready() -> void:
	NetworkManager.story = "salvage"
	var world: Node3D = load("res://scenes/salvage.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(60)
	var player: CharacterBody3D = world.local_player()
	var truck: Node3D = world.get_node("Truck")
	player._enter_vehicle(truck)
	await _frames(240)
	print("stock: running %s noise %.2f" % [truck.audible_engine_variant, world.noise.vehicle_level(truck)])
	for donor_name in ["Flooded_4", "Flooded_6"]:
		player._exit_vehicle()
		var donor: Node3D = world.get_node(donor_name)
		var old: RigidBody3D = truck.remove_installed_part(truck.removable_parts["engine"]["area"], true)
		var swap: RigidBody3D = donor.remove_installed_part(donor.removable_parts["engine"]["area"], true)
		swap.global_position = truck.global_position + Vector3(0, 1.2, -1.5)
		await _frames(2)
		var variant: String = swap.get_meta("engine_variant")
		var fitted: bool = truck.install_part(swap, "engine")
		old.queue_free()
		player._enter_vehicle(truck)
		await _frames(240)
		print("%s engine fitted %s: running %s noise %.2f, %s" % [variant, fitted, truck.audible_engine_variant, world.noise.vehicle_level(truck), truck.get_fuel_text()])
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
