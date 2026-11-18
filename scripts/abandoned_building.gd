extends "res://scripts/garage_model.gd"


func build() -> void:
	# The old floor plan remains available for stops restored from earlier saves.
	if style < 3:
		super.build()
		return

	var variant := style - 3
	paint = Shapes.material([Color("#82715d"), Color("#7f8272"), Color("#645c53"), Color("#727067")][variant])
	var depth: float = [7.2, 8.7, 7.4, 8.0][variant]
	var width: float = [7.8, 6.8, 6.6, 7.2][variant]
	var front := 4.14
	var rear := front - depth
	var middle := (front + rear) * 0.5
	var wall_top: float = [2.91, 3.45, 3.1, 3.25][variant]

	Shapes.box(self, "Foundation", Vector3(width + 0.25, 0.12, depth + 0.22), Vector3(0, -0.05, middle), concrete, true)
	Shapes.box(self, "BackWall", Vector3(width, wall_top, 0.21), Vector3(0, wall_top * 0.5, rear), paint, true)
	for side in [-1.0, 1.0]:
		Shapes.box(self, "SideWall", Vector3(0.19, wall_top, depth), Vector3(side * width * 0.5, wall_top * 0.5, middle), paint, true)
	Shapes.box(self, "Lintel", Vector3(width, wall_top - 2.34, 0.21), Vector3(0, (wall_top + 2.34) * 0.5, front), paint, true)
	for bounds in [Vector2(-width * 0.5, -2.94), Vector2(1.62, 1.88), Vector2(2.94, width * 0.5)]:
		Shapes.box(self, "FrontWall", Vector3(bounds.y - bounds.x, 2.34, 0.21), Vector3((bounds.x + bounds.y) * 0.5, 1.17, front), paint, true)

	match variant:
		0:
			# Former tire shop with a flat parapet and a fallen awning frame.
			Shapes.box(self, "FlatRoof", Vector3(width + 0.24, 0.16, depth + 0.35), Vector3(0, wall_top + 0.08, middle), dark, true)
			Shapes.box(self, "Parapet", Vector3(width + 0.13, 0.38, 0.17), Vector3(0, wall_top + 0.22, front + 0.1), paint)
			Shapes.tube(self, "BentAwning", Vector3(-3.65, 2.7, front), Vector3(-3.12, 1.25, front + 1.2), 0.04, steel)
			_add_worn_lettering("TIRES", Vector3(-0.65, wall_top - 0.1, front + 0.2))
		1:
			# Long former machine shed with a peaked roof.
			for side in [-1.0, 1.0]:
				var panel := Shapes.box(self, "GabledRoof", Vector3(width * 0.56, 0.14, depth + 0.55), Vector3(side * width * 0.25, wall_top + 0.45, middle), dark, true)
				panel.rotation.z = -side * 0.25
			Shapes.box(self, "GableCladding", Vector3(width * 0.46, 0.45, 0.14), Vector3(0, wall_top + 0.14, front), paint)
			_add_worn_lettering("MACHINE SHOP", Vector3(-0.65, 2.89, front + 0.21))
		2:
			# A storage depot with a canopy and posts.
			Shapes.box(self, "DepotRoof", Vector3(width + 0.4, 0.16, depth + 2.4), Vector3(0, wall_top + 0.08, middle + 0.89), dark, true)
			for x in [-3.13, 3.13]:
				Shapes.box(self, "CanopyPost", Vector3(0.13, wall_top, 0.14), Vector3(x, wall_top * 0.5, front + 1.9), steel, true)
		3:
			# A boarded brick repair bay with exposed courses and a capped roof.
			Shapes.box(self, "RoofCap", Vector3(width + 0.42, 0.21, depth + 0.51), Vector3(0, wall_top + 0.03, middle), dark, true)
			var mortar := Shapes.material(Color("#554a40"))
			for course in range(8):
				Shapes.box(self, "BrickCourse", Vector3(0.012, 0.024, depth - 0.18), Vector3(width * 0.5 + 0.10, 0.4 + course * 0.33, middle), mortar)
			_add_worn_lettering("REPAIRS", Vector3(-0.65, wall_top - 0.35, front + 0.2))
	_add_decay()
	_add_shelving()
	_add_workbench()
	_add_doors()
	_dress_model("station_%d" % variant, width, depth, wall_top, rear, front)


func _add_worn_lettering(title: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = title
	label.font_size = 54
	label.pixel_size = 0.005
	label.outline_size = 0
	label.modulate = Color("#5b4a3a")
	add_child(label)
	label.position = at


func add_traces(stop_index: int, vehicle_kind: int) -> void:
	if style < 3:
		return
	var profile := posmod(hash("km0:shop-traces:%d" % stop_index), 5)
	# Leave some interiors alone. Each of the others gets a single ordinary detail.
	if profile == 0:
		return
	var worn_metal := Shapes.material(Color("#70695d"), 0.40)
	if style == 5:
		_add_bench_dust()
		# An old shipping strap hangs from a mostly bare shelf.
		var strap := Shapes.material(Color("#7e7149"), 0.06)
		Shapes.box(self, "PackingStrap", Vector3(0.035, 0.009, 0.44), Vector3(2.66, 1.615, 0.94), strap).rotation.y = -0.17
		Shapes.box(self, "StrapEnd", Vector3(0.035, 0.26, 0.009), Vector3(2.68, 1.487, 1.16), strap).rotation.x = 0.14
	elif style == 3:
		_add_old_tire_marks()
		# An ordinary wheel chock set aside after use.
		var rubber := Shapes.material(Color("#49443b"))
		var chock := Vector3(-2.5, 0.065, -1.68)
		Shapes.box(self, "Chock", Vector3(0.23, 0.11, 0.30), chock, rubber).rotation.y = 0.24
		Shapes.box(self, "ChockGrip", Vector3(0.13, 0.036, 0.034), chock + Vector3(0, 0.066, 0.04), worn_metal)
	elif profile <= 2 and vehicle_kind >= 0:
		_add_open_toolbox(worn_metal)
	else:
		_add_bench_dust()
		var cloth := Shapes.material(Color("#786c57"))
		Shapes.box(self, "ShopRag", Vector3(0.22, 0.018, 0.29), Vector3(2.72, 0.977, -2.18), cloth).rotation.y = -0.29
		Shapes.tube(self, "WrenchHandle", Vector3(2.55, 0.994, -2.27), Vector3(2.74, 0.998, -2.20), 0.011, worn_metal)
		Shapes.cylinder(self, "WrenchEnd", Vector3(2.74, 0.998, -2.20), Vector3.UP, 0.032, 0.018, worn_metal, 8)


func _add_bench_dust() -> void:
	var dust := Shapes.material(Color(0.61, 0.54, 0.44, 0.28))
	dust.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Four patches leave the footprint of a small toolbox in the dust.
	for rect in [Vector4(1.18, -2.32, 0.24, 0.42), Vector4(2.0, -2.32, 0.38, 0.42),
			Vector4(1.55, -2.49, 0.50, 0.08), Vector4(1.55, -2.15, 0.50, 0.08)]:
		var patch := Shapes.box(self, "BenchDust", Vector3(rect.z, 0.002, rect.w), Vector3(rect.x, 0.972, rect.y), dust)
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_old_tire_marks() -> void:
	var skid := Shapes.material(Color(0.19, 0.16, 0.13, 0.25))
	skid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var haze := Shapes.material(Color(0.19, 0.16, 0.13, 0.09))
	haze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for side in [-1.0, 1.0]:
		var x: float = -0.66 + side * 0.8
		for i in range(8):
			var z := 1.54 + i * 0.31
			var track := Shapes.box(self, "OldTread", Vector3(0.12 + i % 3 * 0.016, 0.002, 0.21),
				Vector3(x + sin(i * 0.43) * 0.065, 0.012, z), skid if i in [3, 4, 6] else haze)
			track.rotation.y = 0.08 * side
			track.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_open_toolbox(worn_metal: Material) -> void:
	var finish := Shapes.material(Color("#69483e"), 0.28)
	var box := Node3D.new()
	box.name = "OpenToolbox"
	add_child(box)
	box.position = Vector3(2.36, 0.973, -2.35)
	box.rotation.y = -0.16
	Shapes.box(box, "Bottom", Vector3(0.39, 0.026, 0.21), Vector3(0, 0.015, 0), finish)
	for side in [-1.0, 1.0]:
		Shapes.box(box, "End", Vector3(0.023, 0.09, 0.21), Vector3(side * 0.184, 0.06, 0), finish)
		Shapes.box(box, "Rim", Vector3(0.38, 0.09, 0.02), Vector3(0, 0.06, side * 0.095), finish)
	Shapes.box(box, "Lid", Vector3(0.39, 0.026, 0.21), Vector3(0, 0.203, -0.125), finish).rotation.x = 1.21
	for x in [-0.09, -0.048, 0.02]:
		Shapes.cylinder(box, "Socket", Vector3(x, 0.045, 0.03), Vector3.UP, 0.016, 0.038, worn_metal, 8)
	Shapes.tube(box, "Ratchet", Vector3(-0.14, 0.048, -0.05), Vector3(0.11, 0.048, -0.02), 0.015, worn_metal)
