extends Node3D

const Shapes := preload("res://scripts/prop_shapes.gd")
const Shutter := preload("res://scripts/garage_shutter.gd")
const Desert := preload("res://scripts/desert_models.gd")
## The code-built pieces the Blender models draw instead (their colliders stay).
const SHELL_PIECES := ["Slab", "Apron", "Back", "Side", "RaisedSeam", "FrontExtension", "Header", "FrontPost", "Roof",
	"RoofSeam", "RoofFascia", "Gutter", "SignBoard", "DeadStripLamp", "BoardedWindow", "WindowBoard", "RustStreak",
	"DryGrass", "WindowFrame", "WindowPane", "Foundation", "BackWall", "SideWall", "Lintel", "FrontWall", "FlatRoof",
	"Parapet", "BentAwning", "GabledRoof", "GableCladding", "DepotRoof", "CanopyPost", "RoofCap", "BrickCourse"]
const BENCH_PIECES := ["BenchTop", "BenchLeg", "ToolDrawer", "DrawerPull", "Pegboard", "Tool"]
const SHELF_PIECES := ["Shelf", "ShelfUpright", "PartsBin"]
const BAY_SPACING := 4.25
const WORKSHOP_EXTRA_SIDE := 0.8
const WORKSHOP_EXTRA_DEPTH := 0.9

@export var starting_garage := false
@export_enum("Workshop", "Fuel stop", "Storehouse") var style := 0

var steel := Shapes.material(Color("#535b59"), 0.45)
var dark := Shapes.material(Color("#242d2a"), 0.4)
var concrete := Shapes.material(Color("#989180"))
var wood := Shapes.material(Color("#76634d"))
var cream := Shapes.material(Color("#e3cc9f"))
var paint: StandardMaterial3D


func build() -> void:
	paint = Shapes.material([Color("#626e63"), Color("#79675c"), Color("#756d55")][style], 0.2)
	var extra_side := WORKSHOP_EXTRA_SIDE if starting_garage else 0.0
	var extra_width := extra_side * 2.0
	var extra_depth := WORKSHOP_EXTRA_DEPTH if starting_garage else 0.0
	Shapes.box(self, "Slab", Vector3(6.6 + extra_width, 0.12, 7.6 + extra_depth), Vector3(0, -0.05, 0.8 - extra_depth * 0.5), concrete, true)
	Shapes.box(self, "Apron", Vector3(4.6, 0.065, 3.2), Vector3(-0.65, -0.033, 6.1), concrete, true)
	Shapes.box(self, "Back", Vector3(6.4 + extra_width, 2.95, 0.18), Vector3(0, 1.47, -2.8 - extra_depth), paint, true)
	for side in [-1.0, 1.0]:
		Shapes.box(self, "Side", Vector3(0.16, 3.0, 7.0 + extra_depth), Vector3(side * (3.16 + extra_side), 1.5, 0.7 - extra_depth * 0.5), paint, true)
		for panel in range(24 + floori(extra_depth / 0.29)):
			Shapes.box(self, "RaisedSeam", Vector3(0.052, 2.88, 0.061), Vector3(side * (3.25 + extra_side), 1.5, -2.7 - extra_depth + panel * 0.29), steel)
		if starting_garage:
			Shapes.box(self, "FrontExtension", Vector3(extra_side, 2.4, 0.2), Vector3(side * (3.16 + extra_side * 0.5), 1.2, 4.14), paint, true)

	Shapes.box(self, "Header", Vector3(6.4 + extra_width, 0.64, 0.2), Vector3(0, 2.68, 4.14), paint, true)
	for x in [-3.07, 1.77, 3.05]:
		Shapes.box(self, "FrontPost", Vector3(0.23, 2.4, 0.24), Vector3(x, 1.2, 4.14), steel, true)
	Shapes.box(self, "Roof", Vector3(7.05 + extra_width, 0.19, 7.8 + extra_depth), Vector3(0, 3.04, 0.7 - extra_depth * 0.5), dark, true)
	for index in range(23 + floori(extra_width / 0.305)):
		Shapes.box(self, "RoofSeam", Vector3(0.06, 0.055, 7.8 + extra_depth), Vector3(-3.37 - extra_side + index * 0.305, 3.16, 0.7 - extra_depth * 0.5), steel)
	Shapes.box(self, "RoofFascia", Vector3(7.1 + extra_width, 0.29, 0.14), Vector3(0, 3.08, 4.63), steel)
	Shapes.box(self, "Gutter", Vector3(7.05 + extra_width, 0.07, 0.18), Vector3(0, 2.95, 4.68), dark)

	var shop_name: String = ["KM 0   WORKSHOP", "MOTOR REPAIRS", "AUTO PARTS"][style]
	_make_sign(shop_name)
	_add_workbench(Vector3(extra_side, 0, -extra_depth))
	_add_shelving(Vector3(extra_side, 0, 0))
	if starting_garage:
		_add_service_details()
	else:
		_add_decay()
	for x in [-2.8, 1.52]:
		Shapes.box(self, "Bollard", Vector3(0.13, 0.68, 0.13), Vector3(x, 0.34, 4.68), steel, true)
		Shapes.box(self, "BollardCap", Vector3(0.14, 0.13, 0.14), Vector3(x, 0.63, 4.68), cream)

	var lamp_material := Shapes.material(Color("#91866d"))
	Shapes.box(self, "DeadStripLamp", Vector3(2.2, 0.06, 0.13), Vector3(-0.7, 2.91, 0.85), lamp_material)
	_add_doors()
	var width := 6.4 + extra_width
	_dress_model("workshop" if starting_garage else "workshop_small", width, 7.0 + extra_depth, 2.95, -2.8 - extra_depth, 4.14)
	for child in get_children():
		if child is MeshInstance3D and Desert.piece(child) in ["Bollard", "BollardCap"]:
			child.material_override = Desert.material("Steel" if Desert.piece(child) == "Bollard" else "Yellow paint")


func _dress_model(title: String, width: float, depth: float, height: float, rear: float, front: float) -> void:
	## Swap the box shell for the Blender model, keeping every collider and anchor.
	Desert.hide_boxes(self, SHELL_PIECES)
	var tint := paint.albedo_color.lerp(Color(1, 1, 1), 0.25) * 1.12
	Desert.dress(self, title, true, tint)
	for node_name in ["Workbench", "Shelving"]:
		var holder := get_node_or_null(node_name) as Node3D
		if holder:
			Desert.hide_boxes(holder, BENCH_PIECES if node_name == "Workbench" else SHELF_PIECES)
			var model := Desert.model(node_name.to_lower())
			holder.add_child(model)
			for mesh: GeometryInstance3D in model.find_children("*", "GeometryInstance3D", true, false):
				mesh.visibility_range_end = 40.0
				mesh.set_instance_shader_parameter("tint", tint)
	var shutter_node := get_node_or_null("GarageShutter")
	if shutter_node:
		for child in shutter_node.get_children():
			if child is MeshInstance3D:
				child.material_override = Desert.material("Shutter" if Desert.piece(child) == "Slat" else "Steel")
				child.set_instance_shader_parameter("tint", tint)
	var door := get_node_or_null("shack_door") as MeshInstance3D
	if door:
		door.material_override = Desert.material("Door")
		door.set_instance_shader_parameter("tint", tint)
	# The walls hide what is behind them; nothing inside, so the open shutter
	# still shows what is in there.
	var middle := (front + rear) * 0.5
	Desert.occluder(self, Vector3(width - 0.3, height - 0.2, 0.1), Vector3(0, height * 0.5, rear))
	for side in [-1.0, 1.0]:
		Desert.occluder(self, Vector3(0.1, height - 0.2, depth - 0.4), Vector3(side * (width * 0.5 - 0.05), height * 0.5, middle))


func _make_sign(title: String) -> void:
	Shapes.box(self, "SignBoard", Vector3(3.6, 0.45, 0.09), Vector3(-0.65, 2.72, 4.28), dark)
	var label := Label3D.new()
	label.text = title
	label.font_size = 53
	label.pixel_size = 0.005
	label.modulate = Color("#4a3d30")
	label.outline_size = 0
	add_child(label)
	label.position = Vector3(-0.65, 2.72, 4.332)


func _add_workbench(offset := Vector3.ZERO) -> void:
	var bench := Node3D.new()
	bench.name = "Workbench"
	add_child(bench)
	bench.position = offset
	Shapes.box(bench, "BenchTop", Vector3(2.2, 0.1, 0.63), Vector3(1.82, 0.92, -2.33), wood, true)
	for x in [0.84, 2.79]:
		for z in [-2.57, -2.1]:
			Shapes.box(bench, "BenchLeg", Vector3(0.07, 0.88, 0.07), Vector3(x, 0.44, z), dark)
	Shapes.box(bench, "ToolDrawer", Vector3(0.6, 0.23, 0.42), Vector3(2.46, 0.746, -2.32), paint)
	Shapes.box(bench, "DrawerPull", Vector3(0.24, 0.036, 0.036), Vector3(2.46, 0.773, -2.09), steel)
	Shapes.box(bench, "Pegboard", Vector3(1.68, 0.62, 0.055), Vector3(1.82, 1.47, -2.67), wood)
	for i in range(7):
		Shapes.box(bench, "Tool", Vector3(0.04, 0.14 + (i % 3) * 0.06, 0.045), Vector3(1.18 + i * 0.21, 1.47, -2.62), steel).rotation.z = 0.13 * (i - 3)


func _add_shelving(offset := Vector3.ZERO) -> void:
	var shelves := Node3D.new()
	shelves.name = "Shelving"
	add_child(shelves)
	shelves.position = offset
	for y in [0.36, 0.98, 1.58]:
		Shapes.box(shelves, "Shelf", Vector3(0.56, 0.06, 1.74), Vector3(2.76, y, 0.42), steel, true)
	for x in [2.49, 3.04]:
		for z in [-0.42, 1.26]:
			Shapes.box(shelves, "ShelfUpright", Vector3(0.042, 1.76, 0.043), Vector3(x, 0.88, z), dark)
	for z in [-0.13, 0.55]:
		Shapes.box(shelves, "PartsBin", Vector3(0.38, 0.17, 0.43), Vector3(2.78, 1.69, z), paint)


func _add_decay() -> void:
	var faded_wood := Shapes.material(Color("#877258"))
	var rust := Shapes.material(Color("#704c37"))
	var weed := Shapes.material(Color("#797146"))
	Shapes.box(self, "BoardedWindow", Vector3(0.08, 0.68, 1.32), Vector3(3.25, 1.89, 2.3), dark)
	for index in range(4):
		var plank := Shapes.box(self, "WindowBoard", Vector3(0.045, 0.65, 0.24), Vector3(3.30, 1.89, 1.87 + index * 0.28), faded_wood)
		plank.rotation.x = 0.06 * (index - 1)
	for x in [-2.65, -1.98, 0.77, 2.97]:
		Shapes.box(self, "RustStreak", Vector3(0.12, 0.32, 0.012), Vector3(x, 2.59, 4.252), rust)
	for foothold in [Vector3(-3.35, 0, 4.15), Vector3(3.33, 0, 4.34), Vector3(-2.78, 0, 6.15)]:
		for blade in range(5):
			var tip: Vector3 = foothold + Vector3(0.12 * cos(blade * 1.8), 0.18 + 0.025 * (blade % 3), 0.11 * sin(blade * 1.8))
			Shapes.tube(self, "DryGrass", foothold, tip, 0.012, weed)


func _add_service_details() -> void:
	var glass := Shapes.material(Color("#6e918b"), 0.32, 0.23)
	Shapes.box(self, "WindowFrame", Vector3(0.08, 0.74, 1.64), Vector3(-3.25 - WORKSHOP_EXTRA_SIDE, 2.06, 1.1), dark)
	for z in [0.62, 1.10, 1.58]:
		Shapes.box(self, "WindowPane", Vector3(0.025, 0.56, 0.42), Vector3(-3.30 - WORKSHOP_EXTRA_SIDE, 2.06, z), glass)
	var service_wall := Vector3(WORKSHOP_EXTRA_SIDE, 0, -WORKSHOP_EXTRA_DEPTH)
	Shapes.box(self, "PowerBox", Vector3(0.36, 0.41, 0.17), Vector3(2.61, 1.49, -2.66) + service_wall, dark)
	Shapes.tube(self, "CeilingConduit", Vector3(2.61, 1.7, -2.63) + service_wall, Vector3(2.61, 2.87, -2.63) + service_wall, 0.025, steel)
	Shapes.box(self, "ServiceMat", Vector3(0.61, 0.018, 1.52), Vector3(2.48, 0.02, -1.0), dark)
	for x in [-2.81, 1.49]:
		Shapes.box(self, "GuidePaint", Vector3(0.08, 0.008, 5.68), Vector3(x, 0.017, 1.05), cream)


func _add_doors() -> void:
	var bay := Shutter.new()
	bay.name = "GarageShutter"
	add_child(bay)
	bay.position = Vector3(-0.65, 0.015, 4.14)
	bay.build(steel, dark, cream)
	var side := Shapes.box(self, "shack_door", Vector3(1.05, 2.29, 0.1), Vector3(2.41, 1.15, 4.14), paint)
	Shapes.box(side, "Handle", Vector3(0.17, 0.06, 0.07), Vector3(0.34, -0.04, 0.08), cream)


func get_bay_x(index: int) -> float:
	return -0.65 if index == 0 else 3.30 + WORKSHOP_EXTRA_SIDE + (index - 0.5) * BAY_SPACING


func add_coop_bays(count: int) -> void:
	if count < 1:
		return
	var width := BAY_SPACING * count
	var center := get_bay_x(1) + (count - 1) * BAY_SPACING * 0.5
	var end := center + width * 0.5
	Shapes.box(self, "BaySlab", Vector3(width, 0.12, 7.38), Vector3(center, -0.05, 0.8), concrete, true)
	Shapes.box(self, "BayRoof", Vector3(width + 0.32, 0.19, 7.7), Vector3(center, 3.04, 0.8), dark, true)
	Shapes.box(self, "BayBackWall", Vector3(width, 2.95, 0.18), Vector3(center, 1.47, -2.8), paint, true)
	Shapes.box(self, "BayEndWall", Vector3(0.16, 3.0, 7.0), Vector3(end, 1.5, 0.7), paint, true)
	Shapes.box(self, "BayHeader", Vector3(width, 0.54, 0.2), Vector3(center, 2.72, 4.14), steel, true)
	for index in range(count + 1):
		var x := center - width * 0.5 + index * BAY_SPACING
		Shapes.box(self, "BayPost", Vector3(0.13, 2.5, 0.21), Vector3(x, 1.25, 4.14), steel, true)
