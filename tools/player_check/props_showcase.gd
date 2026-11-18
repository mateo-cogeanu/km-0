extends Node3D
## Every small prop and loose part in a plain studio, at game scale. Screenshots
## into KM0_CHECK_DIR: a lineup per group and close-ups.

const FoodItem := preload("res://scripts/food_item.gd")
const Supply := preload("res://scripts/supply_item.gd")
const LootBox := preload("res://scripts/loot_container.gd")
const NoteItem := preload("res://scripts/note_item.gd")
const Notes := preload("res://scripts/story_notes.gd")
const PARTS := [
	["res://assets/vehicles/parts/stockengine.glb", Vector3(0.3268, 0.253, 0.3268)],
	["res://assets/vehicles/parts/v8engine.glb", Vector3(0.3268, 0.253, 0.3268)],
	["res://assets/vehicles/parts/electricmotor.glb", Vector3(0.3268, 0.253, 0.3268)],
	["res://assets/vehicles/parts/radiatorassembly.glb", Vector3(0.327, 0.253, 0.058)],
	["res://assets/vehicles/parts/batterypack.glb", Vector3(0.196, 0.276, 0.152)],
	["res://assets/vehicles/parts/batterypack.glb", Vector3(0.13, 0.073, 0.094)],
	["res://assets/vehicles/parts/airfilter.glb", Vector3.ONE * 0.38],
	["res://assets/vehicles/parts/coolantreservoir.glb", Vector3.ONE * 0.38],
	["res://assets/vehicles/parts/bike_engine.tscn", Vector3.ONE],
]

var dir := OS.get_environment("KM0_CHECK_DIR")
var cam := Camera3D.new()


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.135, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.62)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.7
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-55, -30, 0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.6
	rim.light_color = Color(0.75, 0.82, 1.0)
	rim.rotation_degrees = Vector3(-20, 150, 0)
	add_child(rim)
	var floor_body := StaticBody3D.new()
	add_child(floor_body)
	var floor_shape := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	floor_shape.shape = plane
	floor_body.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(60, 60)
	floor_mesh.mesh = plane_mesh
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.24, 0.24, 0.25)
	grey.roughness = 0.9
	floor_mesh.material_override = grey
	add_child(floor_mesh)
	add_child(cam)
	cam.fov = 30.0
	cam.make_current()
	# Row 1: the canister and spray can, food, supplies.
	var x := 0.0
	var canister: RigidBody3D = load("res://scenes/fuel_canister.tscn").instantiate()
	_place(canister, Vector3(x, 0, 0))
	var spray: RigidBody3D = load("res://scenes/spray_can.tscn").instantiate()
	_place(spray, Vector3(0.55, 0, 0.1))
	x = 0.9
	for kind in FoodItem.KINDS:
		var food: RigidBody3D = FoodItem.new()
		food.kind = kind
		_place(food, Vector3(x, 0, 0.1))
		x += 0.2
	for kind in ["water", "batteries", "flare"]:
		var item: RigidBody3D = Supply.new()
		item.kind = kind
		_place(item, Vector3(x, 0, 0.1))
		x += 0.18
	# Row 2: the loot containers, closed and open, and the notes.
	x = 0.0
	for style in ["cooler", "toolbox", "cabinet"]:
		for opened in [false, true]:
			var box: Node3D = LootBox.new()
			box.style = style
			box.seed_text = "showcase:%s" % style
			add_child(box)
			box.position = Vector3(x, 0, -4.0)
			if opened:
				box.open(true)
			x += 0.75
	var styles := {}
	for id in Notes.NOTES:
		var style: String = Notes.NOTES[id].get("style", "paper")
		if not styles.has(style):
			styles[style] = id
	x = 0.0
	for style in styles:
		var note: Node3D = NoteItem.new()
		note.note_id = styles[style]
		add_child(note)
		note.position = Vector3(x, 0, -8.0)
		x += 0.35
	# Row 3: parts at the scale the car uses.
	x = 0.0
	for part: Array in PARTS:
		var node: Node3D = load(part[0]).instantiate()
		node.scale = part[1]
		add_child(node)
		var height: float = 0.97 * part[1].y if not part[0].ends_with(".tscn") else 0.19
		node.position = Vector3(x, height, -12.0)
		x += 0.8
	for body: RigidBody3D in find_children("*", "RigidBody3D", true, false):
		body.freeze = true
	await _frames(30)
	_view(Vector3(1.75, 0.1, 0.05), 3.0, 1.2, "row_items")
	await _shot("row_items")
	_view(Vector3(1.9, 0.25, -4.0), 4.2, 2.0, "row_boxes")
	await _shot("row_boxes")
	_view(Vector3(0.7, 0.0, -8.0), 1.6, 1.3, "row_notes")
	await _shot("row_notes")
	_view(Vector3(3.2, 0.2, -12.0), 6.0, 2.6, "row_parts")
	await _shot("row_parts")
	_view(Vector3(0.25, 0.25, 0.0), 1.4, 0.7, "canister")
	await _shot("close_canister_spray")
	_view(Vector3(1.6, 0.06, 0.1), 1.6, 0.7, "food")
	await _shot("close_food")
	_view(Vector3(2.85, 0.1, 0.1), 0.9, 0.5, "supplies")
	await _shot("close_supplies")
	_view(Vector3(2.0, 0.2, -4.0), 1.3, 0.9, "boxes")
	await _shot("close_boxes_open")
	_view(Vector3(0.0, 0.25, -12.0), 1.5, 1.0, "engine")
	await _shot("close_stock_engine")
	_view(Vector3(0.8, 0.25, -12.0), 1.5, 1.0, "v8")
	await _shot("close_v8")
	get_tree().quit()


func _place(node: Node3D, at: Vector3) -> void:
	add_child(node)
	node.position = at


func _view(at: Vector3, distance: float, rise: float, _title: String) -> void:
	cam.global_position = at + Vector3(0.0, rise, distance)
	cam.look_at(at, Vector3.UP)


func _shot(title: String) -> void:
	await _frames(6)
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
