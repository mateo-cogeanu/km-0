extends RefCounted

const SEDAN_MODEL := preload("res://assets/vehicles/car_model.tscn")
const PART_MODELS := {
	"battery": preload("res://assets/vehicles/parts/batterypack.glb"),
	"radiator": preload("res://assets/vehicles/parts/radiatorassembly.glb"),
	"V8": preload("res://assets/vehicles/parts/v8engine.glb"),
	"Electric": preload("res://assets/vehicles/parts/electricmotor.glb"),
}
const BODY_NODES := {
	"hood": "Chassis_Chassis_0_001", "trunk": "Chassis_Chassis_0_002",
	"door_fl": "FL_Door", "door_fr": "FR_Door", "door_rl": "RL_Door", "door_rr": "RR_Door",
	"wheel_fl": "FL_Wheel", "battery": "Battery", "radiator": "Radiator", "engine": "Engine",
}


static func add_parts(finds: Node3D, garage_style: int, stop_index: int) -> void:
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
	var shell := SEDAN_MODEL.instantiate() as Node3D
	var stock := Node3D.new()
	stock.name = "Salvage"
	finds.add_child(stock)
	var spots := [Vector3(-2.03, 0.83, -1.86), Vector3(-2.03, 0.83, 1.12), Vector3(0.15, 0.82, -0.60)]
	for i in rng.randi_range(1, 3):
		var slot: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var key: String = ["V8", "Electric"][rng.randi_range(0, 1)] if slot == "engine" else slot
		var source := shell.find_child(BODY_NODES[slot], true, false) as Node3D
		var visual := source.duplicate() as Node3D
		if PART_MODELS.has(key):
			var replacement: Node = PART_MODELS[key].instantiate()
			var imported := replacement as MeshInstance3D
			if imported == null:
				imported = replacement.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			(visual as MeshInstance3D).mesh = imported.mesh
			replacement.free()
		# The hood and trunk bolt on by their hinge, so keep that pivot on a spare.
		if slot in ["hood", "trunk"]:
			var hinge := Node3D.new()
			hinge.name = "HoodTargetHinge" if slot == "hood" else "TrunkTargetHinge"
			var panel: MeshInstance3D = visual
			var mesh_bounds := panel.mesh.get_aabb()
			var edge := mesh_bounds.get_center()
			edge.y = mesh_bounds.end.y if slot == "hood" else mesh_bounds.position.y
			panel.transform = Transform3D(Basis.IDENTITY, -edge)
			hinge.add_child(panel)
			visual = hinge
		else:
			visual.position = Vector3.ZERO
		visual.scale *= 0.45
		var body := RigidBody3D.new()
		body.name = "Part_%d" % i
		body.mass = 12.0 if slot == "engine" else 6.0
		body.contact_monitor = true
		body.max_contacts_reported = 8
		body.set_meta("vehicle_part_type", slot)
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
	shell.free()


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
