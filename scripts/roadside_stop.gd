extends "res://scripts/shack.gd"

const LenVan := preload("res://scripts/len_van.gd")
const Garage := preload("res://scripts/abandoned_building.gd")
const Shapes := preload("res://scripts/prop_shapes.gd")
const FUEL := preload("res://scenes/fuel_canister.tscn")
const SEDAN := preload("res://scenes/car.tscn")
const BIKE := preload("res://scenes/two_wheeler.tscn")
const BATTERY := preload("res://assets/vehicles/parts/batterypack.glb")
const BIKE_ENGINE := preload("res://assets/vehicles/parts/bike_engine.tscn")
const Salvage := preload("res://scripts/roadside_salvage.gd")
const SupplyItem := preload("res://scripts/supply_item.gd")
const NoteItem := preload("res://scripts/note_item.gd")

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
	_add_broadcast_stop()

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

	# A little food left behind. Its own random sequence, so stops that were
	# already saved keep the rest of their layout.
	var pantry := RandomNumberGenerator.new()
	pantry.seed = hash("km0:food:%d" % stop_index)
	var spots := [Vector3(2.2, 0.05, -1.3), Vector3(1.85, 0.05, -0.7), Vector3(2.6, 0.05, -0.25), Vector3(-2.3, 0.05, -1.55), Vector3(-1.9, 0.05, -2.0)]
	var kinds := FoodItem.KINDS.keys()
	kinds.append_array(["water", "water"])
	# Now and then, someone got here first: everything eaten, the empties
	# thrown about.
	var raided := absi(stop_index) > 6 and pantry.randf() < 0.2
	if raided:
		_add_empties(finds, pantry)
	else:
		for i in pantry.randi_range(1, 3):
			var kind: String = kinds[pantry.randi_range(0, kinds.size() - 1)]
			var food: Variant = SupplyItem.new() if kind == "water" else FoodItem.new()
			food.kind = kind
			food.name = "Food_%d" % i
			food.position = spots.pop_at(pantry.randi_range(0, spots.size() - 1))
			food.rotation.y = pantry.randf_range(0.0, TAU)
			finds.add_child(food)
	# Something to search.
	if pantry.randf() < 0.6:
		var cooler := LootBox.new()
		cooler.name = "Cooler"
		cooler.style = "cooler" if pantry.randf() < 0.6 else "cabinet"
		cooler.seed_text = "stop%d:cooler" % stop_index
		if raided:
			cooler.contents = PackedStringArray(["batteries"])
		cooler.position = Vector3(-2.35, 0, -2.25)
		finds.add_child(cooler)
	if pantry.randf() < 0.45:
		var toolbox := LootBox.new()
		toolbox.name = "Toolbox"
		toolbox.style = "toolbox"
		toolbox.seed_text = "stop%d:toolbox" % stop_index
		toolbox.position = Vector3(1.05, 0.97, -2.38)
		finds.add_child(toolbox)

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


func _add_empties(parent: Node3D, rng: RandomNumberGenerator) -> void:
	## Opened, emptied cans and torn wrappers, scattered.
	var tin := Shapes.material(Color("#8f8d88"), 0.75, 0.35)
	var inside := Shapes.material(Color("#2a2522"))
	var wrapper := Shapes.material(Color("#5a2a1e"))
	for i in rng.randi_range(5, 8):
		var at := Vector3(rng.randf_range(-2.6, 2.4), 0.04, rng.randf_range(-2.4, 0.8))
		if i % 3 == 2:
			var paper := Shapes.box(parent, "TornWrapper", Vector3(0.12, 0.004, 0.05), at - Vector3(0, 0.035, 0), wrapper)
			paper.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0, TAU), rng.randf_range(-0.2, 0.2))
			continue
		var can := Node3D.new()
		can.name = "EmptyCan"
		parent.add_child(can)
		can.position = at
		can.rotation = Vector3(PI * 0.5, rng.randf_range(0, TAU), 0) if rng.randf() < 0.7 else Vector3(0, rng.randf_range(0, TAU), 0)
		Shapes.cylinder(can, "Tin", Vector3.ZERO, Vector3.UP, 0.042, 0.11, tin, 12)
		Shapes.cylinder(can, "Open", Vector3(0, 0.054, 0), Vector3.UP, 0.036, 0.004, inside, 12)
		if not can.rotation.x:
			can.position.y = 0.055


func _add_broadcast_stop() -> void:
	var block := floori(stop_index / 12.0)
	var broadcast := RoadRadio.Broadcast.WORKSHOP
	if stop_index == -5:
		broadcast = RoadRadio.Broadcast.FIRST_GARAGE
		var van := LenVan.new()
		van.name = "LensVan"
		van.position = Vector3(-6.25, 0, 5.25)
		van.rotation.y = -0.12
		add_child(van)
		# Len left in a hurry: notebook on the seat, the last page on the dash,
		# his thermos still there.
		_add_note(van, "len_log", Vector3(0.42, 0.915, -0.88), 0.3)
		_add_note(van, "len_last", Vector3(-0.38, 1.124, -1.42), -0.2)
		var flask := Shapes.material(Color("#3a5a48"), 0.5, 0.4)
		Shapes.cylinder(van, "Thermos", Vector3(-0.42, 1.03, -0.82), Vector3.UP, 0.04, 0.24, flask, 12)
	elif block == -2:
		broadcast = RoadRadio.Broadcast.WAYSIDE
	elif block == -3:
		broadcast = RoadRadio.Broadcast.TOWER
	elif block == -4:
		broadcast = RoadRadio.Broadcast.QUIET
	elif block == -5:
		broadcast = RoadRadio.Broadcast.LAST_STOP
	if broadcast == RoadRadio.Broadcast.WORKSHOP:
		return

	var radio := RoadRadio.new()
	radio.name = "RelayRadio"
	radio.broadcast = broadcast
	radio.position = Vector3(-2.55, 1.08, -0.18)
	radio.rotation.y = PI / 2.0
	add_child(radio)
	var cabinet := Shapes.material(Color("#676559"), 0.2)
	Shapes.box(self, "RelayCabinet", Vector3(0.57, 0.99, 0.58), Vector3(-2.57, 0.495, -0.18), cabinet, true)
	if broadcast == RoadRadio.Broadcast.TOWER:
		_build_relay_tower()
		_add_relay_log()
	match broadcast:
		RoadRadio.Broadcast.WAYSIDE:
			_add_note(self, "ruth_postcard", Vector3(-2.6, 0.992, 0.05), 0.4)
		RoadRadio.Broadcast.TOWER:
			_add_note(self, "mick_scrawl", Vector3(-2.15, 0.002, 0.45), 1.1)
			_add_note(self, "len_page_tower", Vector3(-2.6, 0.992, 0.05), -0.5)
		RoadRadio.Broadcast.QUIET:
			_add_note(self, "house_photo", Vector3(-2.6, 0.992, 0.05), -0.3)
		RoadRadio.Broadcast.LAST_STOP:
			_add_note(self, "county_log", Vector3(1.65, 0.972, -2.28), 0.15)


func _add_note(parent: Node3D, id: String, at: Vector3, turn: float) -> void:
	var note := NoteItem.new()
	note.note_id = id
	note.name = "Note_" + id
	note.position = at
	note.rotation.y = turn
	parent.add_child(note)


func _add_relay_log() -> void:
	var paper := Shapes.material(Color("#b7aa8b"))
	Shapes.box(self, "CheckInSheet", Vector3(0.20, 0.003, 0.26), Vector3(-2.56, 0.994, 0.108), paper)
	var entries := Label3D.new()
	entries.name = "CheckInLog"
	entries.position = Vector3(-2.56, 0.996, 0.108)
	entries.rotation.x = -PI / 2.0
	entries.font_size = 32
	entries.pixel_size = 0.00038
	entries.outline_size = 0
	entries.modulate = Color("#3c392f")
	entries.text = """EAST ROAD  •  18:00

  LEN         —
  RUTH        —
  MICK        18:02
  JUNE        —
  ALAN        —
  ROSE        —"""
	add_child(entries)


func _build_relay_tower() -> void:
	var tower := Node3D.new()
	tower.name = "RelayTower"
	tower.position = Vector3(-5.7, 0, -1.95)
	add_child(tower)
	var steel := Shapes.material(Color("#777770"), 0.48)
	var faded_red := Shapes.material(Color("#804638"), 0.21)
	var concrete := Shapes.material(Color("#8a8271"))
	Shapes.box(tower, "Foundation", Vector3(3.3, 0.21, 3.3), Vector3(0, 0.07, 0), concrete, true)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for level in range(9):
		var base_y := 0.18 + level * 2.6
		var base_width := lerpf(1.44, 0.28, level / 9.0)
		var top_width := lerpf(1.44, 0.28, (level + 1) / 9.0)
		var finish := faded_red if level % 4 >= 2 else steel
		for i in corners.size():
			var corner: Vector2 = corners[i]
			var neighbour: Vector2 = corners[(i + 1) % corners.size()]
			var foot := Vector3(corner.x * base_width, base_y, corner.y * base_width)
			var top := Vector3(corner.x * top_width, base_y + 2.6, corner.y * top_width)
			Shapes.tube(tower, "Upright", foot, top, 0.075, finish)
			Shapes.tube(tower, "CrossBrace", foot, Vector3(neighbour.x * top_width, top.y, neighbour.y * top_width), 0.035, finish)
			Shapes.tube(tower, "HorizontalBrace", foot, Vector3(neighbour.x * base_width, base_y, neighbour.y * base_width), 0.042, steel)
	Shapes.tube(tower, "AntennaMast", Vector3(0, 23.45, 0), Vector3(0, 28.4, 0), 0.074, steel)
	for y in [24.4, 25.45, 26.5]:
		Shapes.tube(tower, "AntennaElement", Vector3(-1.45, y, 0), Vector3(1.45, y, 0), 0.032, steel)
	var red_lens := Shapes.material(Color("#bd3a21"))
	red_lens.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red_lens.emission_enabled = true
	red_lens.emission = Color("#ff3220")
	var beacon := Shapes.cylinder(tower, "Beacon", Vector3(0, 28.5, 0), Vector3.UP, 0.18, 0.24, red_lens)
	var flash := tower.create_tween().set_loops()
	flash.tween_property(beacon, "visible", false, 0.4)
	flash.tween_property(beacon, "visible", true, 1.8)


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
