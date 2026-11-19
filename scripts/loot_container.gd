extends Node3D
## Something to search: a cooler, a toolbox or a cabinet drawer. Its contents
## are real items, built hidden inside it, so they save like anything else.
## Searching opens it and lets them out.

const Shapes := preload("res://scripts/prop_shapes.gd")
const FoodItem := preload("res://scripts/food_item.gd")
const Supply := preload("res://scripts/supply_item.gd")
const DRAWER := preload("res://assets/audio/player/drawer.wav")
const LID := preload("res://assets/audio/player/lid.wav")

@export_enum("cooler", "toolbox", "cabinet") var style := "cooler"
## Seeds what is inside, so the same box always holds the same things.
@export var seed_text := "box"
## Force particular contents instead of rolling them: kinds like "water",
## "batteries", "beans".
@export var contents: PackedStringArray = []

var opened := false
var lid: Node3D
var items: Array[RigidBody3D] = []
var inside := Vector3.ZERO


func _ready() -> void:
	add_to_group("loot_box")
	var shell: Material
	var size := Vector3.ZERO
	lid = Node3D.new()
	lid.name = "Lid"
	match style:
		"cooler":
			shell = Shapes.material(Color("#c9c3b4"), 0.0, 0.6)
			size = Vector3(0.6, 0.36, 0.36)
			Shapes.box(self, "Tub", Vector3(0.6, 0.32, 0.36), Vector3(0, 0.16, 0), shell, true)
			Shapes.box(self, "Stripe", Vector3(0.605, 0.06, 0.365), Vector3(0, 0.24, 0), Shapes.material(Color("#2f5d8a")))
			add_child(lid)
			lid.position = Vector3(0, 0.32, -0.18)
			Shapes.box(lid, "Top", Vector3(0.62, 0.05, 0.38), Vector3(0, 0.025, 0.18), Shapes.material(Color("#2f5d8a")))
			inside = Vector3(0, 0.05, 0)
		"toolbox":
			shell = Shapes.material(Color("#a8382c"), 0.4, 0.45)
			size = Vector3(0.48, 0.22, 0.22)
			Shapes.box(self, "Tray", Vector3(0.48, 0.18, 0.22), Vector3(0, 0.09, 0), shell, true)
			add_child(lid)
			lid.position = Vector3(0, 0.18, -0.11)
			Shapes.box(lid, "Top", Vector3(0.49, 0.04, 0.23), Vector3(0, 0.02, 0.11), shell)
			Shapes.box(lid, "Handle", Vector3(0.2, 0.025, 0.025), Vector3(0, 0.06, 0.11), Shapes.material(Color("#2a2a2a")))
			inside = Vector3(0, 0.04, 0)
		"cabinet":
			shell = Shapes.material(Color("#6d5a45"))
			size = Vector3(0.6, 0.8, 0.45)
			for side in [-1.0, 1.0]:
				Shapes.box(self, "Side", Vector3(0.03, 0.8, 0.45), Vector3(side * 0.285, 0.4, 0), shell, true)
			Shapes.box(self, "Top", Vector3(0.6, 0.03, 0.45), Vector3(0, 0.785, 0), shell, true)
			Shapes.box(self, "Back", Vector3(0.6, 0.8, 0.03), Vector3(0, 0.4, -0.21), shell, true)
			Shapes.box(self, "Base", Vector3(0.6, 0.06, 0.45), Vector3(0, 0.03, 0), shell, true)
			add_child(lid)
			lid.position = Vector3(0, 0.55, 0)
			Shapes.box(lid, "DrawerFront", Vector3(0.54, 0.22, 0.03), Vector3(0, 0, 0.21), shell)
			Shapes.box(lid, "DrawerFloor", Vector3(0.52, 0.02, 0.4), Vector3(0, -0.1, 0.01), shell, true)
			Shapes.box(lid, "Pull", Vector3(0.14, 0.025, 0.03), Vector3(0, 0.02, 0.235), Shapes.material(Color("#8a7a5a"), 0.5, 0.4))
			Shapes.box(self, "LowerDoor", Vector3(0.54, 0.38, 0.03), Vector3(0, 0.25, 0.21), shell, true)
			inside = Vector3(0, -0.085, 0.01)
	# The look comes from the models (Sources/make_road_props.py); the boxes
	# above stay for their colliders.
	for holder: Node3D in [self, lid]:
		for child in holder.get_children():
			if child is MeshInstance3D:
				child.visible = false
				child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var parts: Array = {"cooler": ["cooler_body", "cooler_lid"], "toolbox": ["toolbox_body", "toolbox_lid"], "cabinet": ["cabinet_body", "cabinet_drawer"]}[style]
	for i in 2:
		var model := (load("res://assets/desert/props/%s.glb" % parts[i]) as PackedScene).instantiate() as Node3D
		model.name = "Model"
		(self if i == 0 else lid).add_child(model)
	var target := Area3D.new()
	target.name = "SearchTarget"
	target.collision_layer = 8
	target.collision_mask = 0
	target.add_to_group("loot_container")
	add_child(target)
	var hitbox := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size + Vector3(0.04, 0.04, 0.04)
	hitbox.shape = shape
	hitbox.position.y = size.y * 0.5
	target.add_child(hitbox)
	_fill()


func title() -> String:
	return {"cooler": "the cooler", "toolbox": "the toolbox", "cabinet": "the cabinet"}[style]


func _fill() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("km0:loot:" + seed_text)
	var kinds := Array(contents)
	if kinds.is_empty():
		var pool := ["water", "water", "batteries", "beans", "soup", "chocolate", "crackers", "jerky", "soda", "apple"]
		if style == "toolbox":
			pool = ["batteries", "batteries", "chocolate", "jerky", "water"]
		for i in rng.randi_range(1, 3):
			kinds.append(pool[rng.randi_range(0, pool.size() - 1)])
	for i in kinds.size():
		var kind: String = kinds[i]
		var item: Variant
		if kind in ["water", "batteries", "flare"]:
			item = Supply.new()
			item.kind = kind
			if kind == "water":
				item.amount = [1.0, 1.0, 0.66, 0.34][rng.randi_range(0, 3)]
		else:
			item = FoodItem.new()
			item.kind = kind
		item.name = "Loot_%d" % i
		item.position = inside + Vector3(-0.15 + i * 0.13, 0.01, rng.randf_range(-0.05, 0.05))
		if kind == "water":
			item.rotation.z = PI * 0.5
			item.position.y += 0.035
		# A drawer's things ride out with the drawer.
		(lid if style == "cabinet" else self as Node3D).add_child(item)
		item.set_meta("in_container", true)
		_tuck(item, true)
		items.append(item)


func _tuck(item: RigidBody3D, hidden: bool) -> void:
	item.freeze = hidden
	item.visible = not hidden
	if hidden:
		item.set_meta("loot_layers", Vector2i(item.collision_layer, item.collision_mask))
		item.collision_layer = 0
		item.collision_mask = 0
	elif item.has_meta("loot_layers"):
		var layers: Vector2i = item.get_meta("loot_layers")
		item.collision_layer = layers.x
		item.collision_mask = layers.y
		item.remove_meta("loot_layers")


func _release() -> void:
	for item in items:
		if is_instance_valid(item) and item.get_meta("in_container", false) and not item.get_meta("stowed", false):
			item.set_meta("in_container", false)
			_tuck(item, false)


static func untuck(item: RigidBody3D) -> void:
	## Another player took this out of a box this peer never saw opened: bring
	## it back to the world (visible, colliding) so it can be seen and held.
	if item.get_meta("in_container", false) or item.has_meta("loot_layers"):
		item.set_meta("in_container", false)
		item.visible = true
		if item.has_meta("loot_layers"):
			var layers: Vector2i = item.get_meta("loot_layers")
			item.collision_layer = layers.x
			item.collision_mask = layers.y
			item.remove_meta("loot_layers")


func open(instant: bool = false) -> void:
	## In co-op the host opens it for everyone, so the lid and what's inside
	## are the same on every screen. Restoring a saved trip opens it in place.
	if opened:
		return
	if instant or not NetworkManager.is_online():
		_open_here(instant)
	elif multiplayer.is_server():
		_open_synced.rpc()
	else:
		_request_open.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_open() -> void:
	if multiplayer.is_server() and not opened:
		_open_synced.rpc()


@rpc("authority", "call_local", "reliable")
func _open_synced() -> void:
	_open_here(false)


func _open_here(instant: bool) -> void:
	if opened:
		return
	opened = true
	var turn := create_tween()
	if style == "cabinet":
		turn.tween_property(lid, "position:z", 0.32, 0.0 if instant else 0.35).set_trans(Tween.TRANS_SINE)
	else:
		turn.tween_property(lid, "rotation:x", -1.9, 0.0 if instant else 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not instant:
		turn.tween_callback(_release)
	else:
		_release()
	if not instant:
		var sound := AudioStreamPlayer3D.new()
		sound.stream = DRAWER if style == "cabinet" else LID
		sound.unit_size = 2.5
		add_child(sound)
		sound.play()
		sound.finished.connect(sound.queue_free)
