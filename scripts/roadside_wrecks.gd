extends Node
## Cars left at the side of the road, every few hundred metres past the first
## stations: faded, sat on flat tyres, a door hanging open. The first few have
## something written down in them; most have something worth taking: petrol,
## water, food, batteries, now and then a flare or a box to search.
## Like the stations, what is found lives outside the streamed road (in
## WreckFinds_N) so carried and moved items, and saves, keep it.

const CarModel := preload("res://scripts/compact_car_model.gd")
const Shapes := preload("res://scripts/prop_shapes.gd")
const NoteItem := preload("res://scripts/note_item.gd")
const FoodItem := preload("res://scripts/food_item.gd")
const Supply := preload("res://scripts/supply_item.gd")
const LootBox := preload("res://scripts/loot_container.gd")
const FUEL := preload("res://scenes/fuel_canister.tscn")
## The notes, in the order they are found down the road.
const NOTES := ["wreck_county", "wreck_rose", "wreck_june", "wreck_tape", "wreck_alan", "wreck_dash"]
const FIRST := -9
const EVERY := 6
const FADED := [Color("#8a8070"), Color("#7b8a86"), Color("#9a7d66"), Color("#6f7480"), Color("#a59a84"), Color("#7e6a5e")]

var road: Node3D
var finds: Dictionary = {}


func has_wreck(index: int) -> bool:
	if index > FIRST:
		return false
	for near in range(index - 1, index + 2):
		if road._has_stop(near):
			return false
	var approach: float = road.house_approach()
	if index * road.segment_length < approach + road.segment_length * 4.0:
		return false
	return posmod(hash("wreck:%d" % index), EVERY) == 0


func wreck_spot(index: int) -> Vector3:
	## Where the wreck stands, worked out the same way populate() does, so it
	## is known without the road there being streamed in.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("km0:wreck:%d" % index)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var z: float = (index + rng.randf_range(0.25, 0.75)) * road.segment_length
	var lateral: float = side * (road.road_width * 0.5 + road.shoulder_width + rng.randf_range(0.8, 2.6))
	return road._sample(z, lateral)


func ordinal(index: int) -> int:
	## How many wrecks come before this one, from the workshop out.
	var count := 0
	for k in range(FIRST, index, -1):
		if has_wreck(k):
			count += 1
	return count


func populate(segment: Node3D, index: int) -> void:
	if not has_wreck(index):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("km0:wreck:%d" % index)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var z: float = (index + rng.randf_range(0.25, 0.75)) * road.segment_length
	var lateral: float = side * (road.road_width * 0.5 + road.shoulder_width + rng.randf_range(0.8, 2.6))
	var car := Node3D.new()
	car.name = "Wreck"
	segment.add_child(car)
	CarModel.new(FADED[rng.randi_range(0, FADED.size() - 1)], 1.0).build(car, rng.randi_range(0, 2), false)
	var at: Vector3 = road._sample(z, lateral) - segment.position
	car.position = Vector3(at.x, -0.13, at.z)
	# Pulled over at an angle, nose to the desert, sagging on one corner.
	car.rotation = Vector3(rng.randf_range(-0.03, 0.03), (0.0 if rng.randf() < 0.7 else PI) + side * rng.randf_range(0.15, 0.6), side * 0.045)
	# Its own wheels, the tyres gone soft; one flat to the rim.
	var flat := rng.randi_range(0, 3)
	var wheel_names := ["FL_Wheel", "FR_Wheel", "RL_Wheel", "RR_Wheel"]
	for i in 4:
		var wheel := car.get_node_or_null(wheel_names[i]) as Node3D
		if wheel:
			wheel.position.y = 0.27 if i == flat else 0.33
			wheel.scale = Vector3(1.0, 0.72 if i == flat else 0.9, 1.0 if i == flat else 0.97)
	# Sun-crazed glass, some of it gone.
	var dirty := StandardMaterial3D.new()
	dirty.albedo_color = Color(0.42, 0.38, 0.3, 0.55)
	dirty.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dirty.roughness = 0.7
	dirty.cull_mode = BaseMaterial3D.CULL_DISABLED
	for pane: MeshInstance3D in car.find_children("*Glass", "MeshInstance3D", true, false) + car.find_children("*Screen", "MeshInstance3D", true, false):
		if rng.randf() < 0.35:
			pane.visible = false
		else:
			pane.material_override = dirty
	var door := car.get_node_or_null("FL_Door" if side > 0.0 else "FR_Door") as Node3D
	if door:
		door.rotation.y = -1.05 * (1.0 if side > 0.0 else -1.0)
	var body := StaticBody3D.new()
	car.add_child(body)
	var hitbox := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 1.3, 4.3)
	hitbox.shape = box
	body.add_child(hitbox)
	body.position = Vector3(0, 0.72, 0)
	var order := ordinal(index)
	if order < NOTES.size():
		var note := NoteItem.new()
		note.note_id = NOTES[order]
		note.name = "Note"
		car.add_child(note)
		note.position = Vector3(0.38 * (1.0 if side > 0.0 else -1.0), 0.62, 0.1)
		note.rotation.y = rng.randf_range(-0.5, 0.5)
	_want_finds.call_deferred(index)


func _want_finds(index: int) -> void:
	## Alone, the finds appear with the wreck. In co-op the host puts them
	## down for everyone at once, the first time either player comes near,
	## so a can taken on one screen isn't still sitting there on the other.
	if finds.has(index):
		return
	if not NetworkManager.is_online():
		spawn_finds(index)
	elif multiplayer.is_server():
		_spawn_finds_everywhere.rpc(index)
	else:
		_request_finds.rpc_id(1, index)


@rpc("any_peer", "call_remote", "reliable")
func _request_finds(index: int) -> void:
	if multiplayer.is_server() and has_wreck(index) and not finds.has(index):
		_spawn_finds_everywhere.rpc(index)


@rpc("authority", "call_local", "reliable")
func _spawn_finds_everywhere(index: int) -> void:
	spawn_finds(index)


func spawn_finds(index: int) -> void:
	## Once per wreck, ever (and again when a saved trip is continued).
	if finds.has(index):
		return
	var world := get_tree().current_scene
	if world == null:
		world = road.get_parent()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("km0:wreck-finds:%d" % index)
	var holder := Node3D.new()
	holder.name = "WreckFinds_%d" % index
	world.add_child(holder)
	finds[index] = holder
	# The finds wait on the road side of the wreck, by the open door.
	var origin: Vector3 = wreck_spot(index)
	var toward_road := Vector3(-signf(origin.x - road._road_x(origin.z)), 0, 0)
	holder.global_position = Vector3(origin.x, 0.0, origin.z) + toward_road * 1.6
	var count := 1 + int(rng.randf() < 0.45)
	for i in count:
		var roll := rng.randf()
		var item: Node3D
		if roll < 0.34:
			var can := FUEL.instantiate() as RigidBody3D
			can.fuel_amount = rng.randf_range(5.0, 13.0)
			item = can
		elif roll < 0.58:
			var water := Supply.new()
			water.kind = "water"
			water.amount = rng.randf_range(0.34, 1.0)
			item = water
		elif roll < 0.82:
			var food := FoodItem.new()
			var kinds := FoodItem.KINDS.keys()
			food.kind = kinds[rng.randi_range(0, kinds.size() - 1)]
			item = food
		elif roll < 0.92:
			var cells := Supply.new()
			cells.kind = "batteries"
			item = cells
		elif roll < 0.96:
			var flare := Supply.new()
			flare.kind = "flare"
			item = flare
		else:
			var box := LootBox.new()
			box.style = "toolbox"
			box.seed_text = "wreck%d:toolbox" % index
			item = box
		item.name = "Find_%d" % i
		holder.add_child(item)
		item.position = Vector3(rng.randf_range(-0.4, 0.4), 0.06, rng.randf_range(-1.2, 1.2) + i * 0.7)
		item.rotation.y = rng.randf_range(0.0, TAU)
