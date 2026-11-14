extends RefCounted

const CarModel := preload("res://scripts/compact_car_model.gd")
const PART_MODELS := {
	"battery": preload("res://assets/vehicles/parts/batterypack.glb"),
	"radiator": preload("res://assets/vehicles/parts/radiatorassembly.glb"),
	"V8": preload("res://assets/vehicles/parts/v8engine.glb"),
	"Electric": preload("res://assets/vehicles/parts/electricmotor.glb"),
}
const DOOR_NAMES := {"door_fl": "FL_Door", "door_fr": "FR_Door", "door_rl": "RL_Door", "door_rr": "RR_Door"}
const ENGINE_SCALES := {"engine": Vector3(0.3268, 0.253, 0.3268), "radiator": Vector3(0.327, 0.253, 0.058),
	"battery": Vector3(0.196, 0.276, 0.152)}


static func add_parts(finds: Node3D, garage_style: int, stop_index: int, legacy_car_spares: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("km0:salvage:%d" % stop_index)
	# Empty buildings tend to have leftovers from the work that happened there.
	var pools := [
		["wheel_fl", "wheel_fl", "door_fr", "trunk", "battery"],
		["radiator", "battery", "engine", "hood", "door_rl"],
		["hood", "trunk", "door_rr", "wheel_fl", "battery"],
		["door_fl", "door_fr", "hood", "radiator", "engine"],
	]
	var pool: Array = pools[garage_style - 3].duplicate()
	var model := CarModel.new(Color("#857962"))
	var stock := Node3D.new()
	stock.name = "Salvage"
	finds.add_child(stock)
	var spots := [Vector3(-2.03, 0.83, -1.86), Vector3(-2.03, 0.83, 1.12), Vector3(0.15, 0.82, -0.60)]
	for i in rng.randi_range(1, 3):
		var slot: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var key: String = ["V8", "Electric"][rng.randi_range(0, 1)] if slot == "engine" else slot

		var holder := Node3D.new()
		var body_style := CarModel.SEDAN if legacy_car_spares else posmod(hash("lid:%d:%d" % [stop_index, i]), 3)
		var visual := _make_spare(holder, model, slot, key, body_style)
		holder.remove_child(visual)
		holder.free()
		visual.position = Vector3.ZERO
		var body := RigidBody3D.new()
		body.collision_layer = 16
		body.collision_mask = 17
		body.name = "Part_%d" % i
		body.mass = 12.0 if slot == "engine" else 6.0
		body.contact_monitor = true
		body.max_contacts_reported = 8
		body.set_meta("vehicle_part_type", slot)
		if slot == "trunk":
			body.set_meta("body_style", body_style)
		if slot == "engine":
			body.set_meta("engine_variant", key)
		var bounds := _bounds(visual)
		if slot == "wheel_fl":
			var wheel := Node3D.new()
			wheel.name = "WheelVisual"
			wheel.set_meta("native_wheel_radius", 0.39)
			wheel.set_meta("native_wheel_scale", Vector3.ONE)
			wheel.add_child(visual)
			visual = wheel
		body.add_child(visual)
		var hitbox := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = bounds.size.abs().max(Vector3(0.12, 0.12, 0.12))
		hitbox.shape = box
		hitbox.position = bounds.get_center()
		body.add_child(hitbox)
		body.rotation.y = PI + rng.randf_range(-0.35, 0.35)
		body.position = spots[i] - body.basis * bounds.get_center()
		body.add_to_group("vehicle_loose_part")
		stock.add_child(body)
		body.set_meta("trip_part_id", str(finds.get_parent().get_path_to(body)))


static func _make_spare(holder: Node3D, model: RefCounted, slot: String, key: String, style: int) -> Node3D:
	match slot:
		"hood":
			return model.make_hood(holder)
		"trunk":
			return model.make_tailgate(holder, style)
		"wheel_fl":
			return model.make_wheel(holder, "SpareWheel")
	if DOOR_NAMES.has(slot):
		return model.make_door(holder, DOOR_NAMES[slot])
	var part: Node = PART_MODELS[key].instantiate()
	var imported := part as MeshInstance3D
	if imported == null:
		imported = part.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var visual := MeshInstance3D.new()
	visual.name = slot.capitalize()
	visual.mesh = imported.mesh
	visual.scale = ENGINE_SCALES[slot]
	holder.add_child(visual)
	part.free()
	return visual


static func _bounds(node: Node3D, parent := Transform3D.IDENTITY) -> AABB:
	var pose := parent * node.transform
	var result := AABB()
	if node is MeshInstance3D and node.mesh:
		result = pose * node.mesh.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var bounds := _bounds(child, pose)
			if bounds.size != Vector3.ZERO:
				result = bounds if result.size == Vector3.ZERO else result.merge(bounds)
	return result
