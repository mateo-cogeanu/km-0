extends "res://scripts/shack.gd"

const Garage := preload("res://scripts/abandoned_building.gd")
const Shapes := preload("res://scripts/prop_shapes.gd")
const FUEL := preload("res://scenes/fuel_canister.tscn")
const SEDAN := preload("res://scenes/car.tscn")
const BIKE := preload("res://scenes/two_wheeler.tscn")
const BATTERY := preload("res://assets/vehicles/parts/batterypack.glb")
const BIKE_ENGINE := preload("res://assets/vehicles/parts/bike_engine.tscn")
const Salvage := preload("res://scripts/roadside_salvage.gd")

# The engine also identifies the original part when Continue replays swaps.
# Keep existing profiles and their selection stable for saved stops.
const SEDAN_LOADOUTS := [
	["Stock", []],
	["V8", ["door_rl"]],
	["Electric", []],
	["Bike", ["trunk"]],
	["Stock", ["engine", "hood"]],
	["V8", ["radiator", "hood"]],
	["Stock", ["wheel_fr"]],
	["Electric", ["battery"]],
]

var stop_index: int
var saved_body_style := -1
var legacy_car_spares := false
var vehicle_owner := 1
var legacy_layout := false
var use_sedan_loadout := true
var restoring := false


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("km0:stop:%d" % stop_index)
	var garage := Garage.new()
	var old_style := rng.randi_range(0, 2)
	garage.style = old_style if legacy_layout else 3 + posmod(hash("building:%d" % stop_index), 4)
	garage.name = "GarageModel"
	add_child(garage)
	super._ready()
	var forecourt := Shapes.material(Color("#8d7d60"))
	Shapes.box(garage, "Forecourt", Vector3(7.0, 0.04, 3.1), Vector3(0.0, -0.049, 6.4), forecourt)
	if old_style == 1:
		var steel := Shapes.material(Color("#544c41"), 0.26)
		Shapes.box(garage, "DiscardedDrum", Vector3(0.45, 0.64, 0.44), Vector3(2.63, 0.28, -1.8), steel, true)
	elif old_style == 2:
		var wood := Shapes.material(Color("#78654e"))
		Shapes.box(garage, "ShippingCrate", Vector3(0.62, 0.53, 0.61), Vector3(-2.48, 0.27, -1.84), wood, true)

	var roll := rng.randf()
	var vehicle_kind := -1
	if roll < 0.59:
		vehicle_kind = rng.randi_range(0, 2)
	if legacy_layout:
		var old_block := -floori(float(stop_index) / 5.0)
		if old_block in [1, 2, 3]:
			vehicle_kind = old_block - 1
	else:
		# The first few discoveries introduce each vehicle before the randomized finds.
		var block := floori(float(stop_index) / 12.0)
		if block in [-1, -2, -3]:
			vehicle_kind = -block - 1
	garage.add_traces(stop_index, vehicle_kind)

	# Dynamic finds live outside the streamed scenery so carried and parked items survive.
	var world := get_tree().current_scene
	if world == null:
		world = get_parent().get_parent()
	var finds := Node3D.new()
	finds.name = "Finds_%d" % stop_index
	world.add_child(finds)
	finds.global_transform = global_transform

	var canister := FUEL.instantiate() as RigidBody3D
	canister.position = Vector3(2.57, 0.16, -0.97)
	canister.fuel_amount = rng.randf_range(8.0, 20.0)
	finds.add_child(canister)
	if old_style == 1 or rng.randf() < 0.45:
		var spare := FUEL.instantiate() as RigidBody3D
		spare.position = Vector3(2.47, 0.16, -1.52)
		finds.add_child(spare)

	if vehicle_kind == 2 or rng.randf() < 0.73:
		_spawn_part(finds, "SpareBattery", BATTERY, Vector3(2.76, 0.56, 0.35), Vector3(0.13, 0.073, 0.094), "aux_battery")
	if vehicle_kind < 0 and not legacy_layout:
		Salvage.add_parts(finds, garage.style, stop_index, legacy_car_spares)
	if vehicle_kind >= 0:
		var vehicle: RigidBody3D = (SEDAN if vehicle_kind == 0 else BIKE).instantiate()
		vehicle.name = ["Sedan", "Bicycle", "Motorbike"][vehicle_kind]
		vehicle.position = Vector3(-0.70, 0.18, 0.5)
		vehicle.rotation.y = PI
		vehicle.start_with_removed_panels = false
		if vehicle_kind == 0:
			vehicle.start_with_random_body_color = false
			vehicle.fuel_amount = 0.0
			if saved_body_style >= 0:
				vehicle.body_style = saved_body_style
			elif not legacy_layout and stop_index != -5:
				vehicle.body_style = posmod(hash("body-style:%d" % stop_index), 3)
			saved_body_style = vehicle.body_style
			if not legacy_layout:
				vehicle.sedan_trim = 1 + posmod(hash("trim:%d" % stop_index), 3)
				if use_sedan_loadout:
					_configure_sedan_loadout(vehicle)
		else:
			vehicle.motorized = vehicle_kind == 2
		vehicle.set_multiplayer_authority(vehicle_owner)
		finds.add_child(vehicle)
		if vehicle_kind == 0 and vehicle.starting_engine_variant == "Electric" and not restoring:
			vehicle.electric_charge = vehicle.electric_capacity * 0.2
		if vehicle_kind == 2:
			var spare_engine := _spawn_part(finds, "SpareBikeEngine", BIKE_ENGINE, Vector3(1.55, 1.17, -2.32), Vector3.ONE, "engine")
			spare_engine.set_meta("engine_variant", "Bike")


func _configure_sedan_loadout(vehicle: RigidBody3D) -> void:
	# The first find is a mostly intact V8 so players can get it going with the fuel on site.
	var profile := 1 if stop_index == -5 else posmod(hash("km0:sedan:%d" % stop_index), SEDAN_LOADOUTS.size())
	var loadout: Array = SEDAN_LOADOUTS[profile]
	vehicle.starting_engine_variant = loadout[0]
	# Restore starts with every original part present so it can replay repairs and swaps.
	if not restoring:
		vehicle.missing_starting_slots.assign(loadout[1])


func _spawn_part(parent: Node3D, title: String, model: PackedScene, at: Vector3, dimensions: Vector3, part_type: String) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 16
	body.collision_mask = 17
	body.name = title
	body.mass = 5.0
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.position = at
	body.set_meta("vehicle_part_type", part_type)
	body.add_to_group("vehicle_loose_part")
	var model_node := model.instantiate() as Node3D
	model_node.scale = dimensions
	body.add_child(model_node)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, 0.40, 0.46) if part_type == "engine" else dimensions * 2.0
	collision.shape = box
	body.add_child(collision)
	parent.add_child(body)
	body.set_meta("trip_part_id", str(parent.get_parent().get_path_to(body)))
	return body
