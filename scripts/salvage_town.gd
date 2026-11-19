extends Node3D
## How Marrow looks: the houses and shop down both sides of the flooded
## street, the street furniture, debris in the water, the hillside down from
## the ridge, mist on the water. Models come from Sources/make_marrow_town.py;
## this swaps in the flood shaders and adds simple collision.
## Gameplay (where the ground and water are) stays in salvage_game.gd.

const FLOODED := preload("res://assets/salvage/flooded_surface.gdshader")
const SHINGLES := preload("res://assets/salvage/shingles.gdshader")
const GROUND := preload("res://assets/salvage/ground.gdshader")
const Shapes := preload("res://scripts/prop_shapes.gd")
const DesertModels := preload("res://scripts/desert_models.gd")
## [model, width along the street, depth, top of the walls, porch depth]
const HOUSES := [
	["house_a", 9.0, 9.0, 6.0, 2.4], ["house_b", 10.0, 8.5, 3.3, 2.2],
	["house_c", 8.0, 10.0, 6.0, 0.0], ["shop", 11.0, 10.0, 5.6, 0.0],
]
## Board by board within this distance (the flashlight reaches 22 m), the
## simpler shell with painted-on boards beyond it.
const NEAR_DETAIL := 28.0
const PAINT := [Color("#6f7a76"), Color("#8c7f62"), Color("#5f6d7c"), Color("#7d6458"), Color("#76805f"), Color("#938d7f")]

var game: Node3D
var materials := {}
var flooded: Array[ShaderMaterial] = []
var scenes := {}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 1993


func set_water(level: float) -> void:
	for material in flooded:
		material.set_shader_parameter("water_y", level)


# --- Materials -----------------------------------------------------------------

func _flooded(color: Color, peel := 0.0, bricks := false, roughness := 0.85) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FLOODED
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("peel", peel)
	material.set_shader_parameter("bricks", 1.0 if bricks else 0.0)
	material.set_shader_parameter("roughness_base", roughness)
	material.set_shader_parameter("tide_y", game.FLOOR_Y + 1.6)
	flooded.append(material)
	return material


func ground_material(kind: int) -> ShaderMaterial:
	var key := "ground_%d" % kind
	if not materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = GROUND
		material.set_shader_parameter("kind", kind)
		materials[key] = material
		flooded.append(material)
	return materials[key]


func _material(title: String) -> Material:
	if materials.has(title):
		return materials[title]
	var made: Material
	match title:
		"Siding far":
			made = _flooded(Color(1, 1, 1), 0.55)
			(made as ShaderMaterial).set_shader_parameter("boards", 1.0)
		"Siding":
			made = _flooded(Color(1, 1, 1), 0.55)
		"Trim":
			made = _flooded(Color(0.82, 0.8, 0.74), 0.4)
		"Door":
			made = _flooded(Color(0.36, 0.16, 0.12), 0.5)
		"Wood":
			made = _flooded(Color(0.4, 0.33, 0.25), 0.0)
		"Concrete":
			made = _flooded(Color(0.5, 0.49, 0.46), 0.0, false, 0.92)
		"Brick":
			made = _flooded(Color(0.48, 0.24, 0.17), 0.0, true, 0.9)
		"Metal":
			made = _flooded(Color(0.3, 0.3, 0.31), 0.0, false, 0.55)
		"Rust":
			made = _flooded(Color(0.38, 0.19, 0.1), 0.0, false, 0.8)
		"Red paint":
			made = _flooded(Color(0.55, 0.1, 0.07), 0.35)
		"Sign":
			made = _flooded(Color(0.78, 0.76, 0.68), 0.3)
		"Bark":
			made = _flooded(Color(0.3, 0.27, 0.23), 0.0, false, 0.95)
		"Canvas":
			made = _flooded(Color(0.3, 0.32, 0.22), 0.0, false, 0.95)
		"Rock":
			made = _flooded(Color(0.36, 0.34, 0.31), 0.0, false, 0.9)
		"Shingles":
			made = ShaderMaterial.new()
			(made as ShaderMaterial).shader = SHINGLES
		"Glass":
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.05, 0.06, 0.06)
			glass.roughness = 0.05
			glass.metallic = 0.4
			glass.metallic_specular = 0.9
			made = glass
		"Dark interior":
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.008, 0.008, 0.008)
			dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			made = dark
		"Rubber":
			var rubber := StandardMaterial3D.new()
			rubber.albedo_color = Color(0.04, 0.04, 0.04)
			rubber.roughness = 0.8
			made = rubber
		_:
			made = _flooded(Color(0.5, 0.5, 0.5))
	materials[title] = made
	return made


func model(title: String, far := false) -> Node3D:
	if not scenes.has(title):
		scenes[title] = load("res://assets/salvage/%s.glb" % title)
	var node: Node3D = (scenes[title] as PackedScene).instantiate()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			var title_name := source.resource_name.get_slice(".", 0) if source else ""
			if far and title_name == "Siding":
				title_name = "Siding far"
			mesh.set_surface_override_material(surface, _material(title_name))
	return node


func place(title: String, at: Vector3, yaw: float, parent: Node3D = self) -> Node3D:
	var node := model(title)
	if not title.begins_with("house") and title != "shop":
		for mesh: GeometryInstance3D in node.find_children("*", "GeometryInstance3D", true, false):
			mesh.visibility_range_end = 70.0 if title in ["lamp", "pole", "tree"] else 45.0
			if title in ["tyre", "drum", "bin", "mailbox", "hydrant", "sandbags", "fence", "fence_broken"]:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.position = at
	node.rotation.y = yaw
	return node


func _solid(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	parent.add_child(body)
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)


# --- The street -------------------------------------------------------------------

func build_street() -> void:
	var floor_y: float = game.FLOOR_Y
	var kerb: float = game.KERB_TOP
	var end_z: float = game.STREET_END
	for side in [-1.0, 1.0]:
		var z := -46.0
		var count := 0
		while z > end_z + 10.0:
			var pick: Array = HOUSES[rng.randi_range(0, 2)] if count != 2 or side < 0.0 else HOUSES[3]
			var width: float = pick[1]
			var depth: float = pick[2]
			if z - width < end_z + 4.0:
				break
			var house := _house(pick, Vector3(side * (14.0 + depth * 0.5), floor_y, z - width * 0.5), -side * PI * 0.5)
			if pick[0] == "shop":
				_shop_sign(house, depth)
			# Mailbox at the kerb, a fence or a dead tree in the gap after it.
			if rng.randf() < 0.7 and pick[0] != "shop":
				place("mailbox", Vector3(side * 9.5, kerb, z - width * 0.5 + 1.8), -side * PI * 0.5)
			var gap := rng.randf_range(1.5, 4.0)
			var gap_z := z - width - gap * 0.5
			if rng.randf() < 0.5:
				place("fence" if rng.randf() < 0.5 else "fence_broken", Vector3(side * 13.6, kerb, gap_z), PI * 0.5)
			elif rng.randf() < 0.6:
				var tree := place("tree", Vector3(side * 12.8, kerb, gap_z), rng.randf_range(0.0, TAU))
				tree.scale = Vector3.ONE * rng.randf_range(0.9, 1.3)
			z -= width + gap
			count += 1
		# Street lamps along the kerb, dead.
		for k in 5:
			var lamp_z := -54.0 - k * 22.0 + (8.0 if side > 0.0 else 0.0)
			var lamp := place("lamp", Vector3(side * 9.55, kerb, lamp_z), 0.0 if side < 0.0 else PI)
			lamp.rotation.z = side * rng.randf_range(0.0, 0.06)
			_solid(lamp, Vector3(0.3, 5.0, 0.3), Vector3(0, 2.5, 0))
	# A line of poles down one side, wires sagging between them.
	var last := Vector3.INF
	for k in 5:
		var at := Vector3(-12.2, kerb, -50.0 - k * 25.0)
		var pole := place("pole", at, 0.0)
		_solid(pole, Vector3(0.3, 8.5, 0.3), Vector3(0, 4.25, 0))
		if last != Vector3.INF:
			for across in [-0.95, -0.55, 0.55, 0.95]:
				_wire(last + Vector3(across, 8.1, 0), at + Vector3(across, 8.1, 0), 0.9)
		last = at
	place("hydrant", Vector3(9.6, kerb, -68.0), 0.0)
	place("hydrant", Vector3(-9.6, kerb, -112.0), 0.0)
	var stop := place("stop_sign", Vector3(-9.8, kerb, end_z + 9.0), 0.0)
	_label(stop, "STOP", Vector3(0, 2.3, 0.06), 70, Color(0.95, 0.95, 0.9))
	# Sandbags along the kerb in front of some houses: somebody tried.
	for k in 7:
		var side := -1.0 if k % 2 == 0 else 1.0
		place("sandbags", Vector3(side * 9.3, kerb, -58.0 - k * 13.0 + rng.randf_range(-3.0, 3.0)), PI * 0.5 + rng.randf_range(-0.2, 0.2))
	for k in 4:
		place("bin", Vector3((-1.0 if k % 2 else 1.0) * 10.2, kerb, -63.0 - k * 21.0), rng.randf_range(0, TAU))
	# Things left in the water: a rowboat, tyres, drums, planks.
	var boat := place("rowboat", Vector3(1.5, game.WATER_START - 0.2, -112.0), 0.6)
	boat.rotation.z = 0.12
	for k in 9:
		var at := Vector3(rng.randf_range(-7.5, 7.5), floor_y, rng.randf_range(-50.0, end_z + 8.0))
		if k % 3 == 0:
			var tyre := place("tyre", at + Vector3(0, 0.1, 0), rng.randf_range(0, TAU))
			tyre.rotation.x = rng.randf_range(-0.4, 0.4)
		else:
			var drum := place("drum", at, rng.randf_range(0, TAU))
			if rng.randf() < 0.5:
				drum.rotation.x = PI * 0.5
				drum.position.y += 0.3
	# The storm drain at the end of the street, where the water came in.
	var wall := MeshInstance3D.new()
	var block := BoxMesh.new()
	block.size = Vector3(30, 9, 1.0)
	wall.mesh = block
	wall.material_override = _material("Concrete")
	add_child(wall)
	wall.position = Vector3(0, floor_y + 4.5, end_z - 0.2)
	_solid(wall, block.size, Vector3.ZERO)
	var dark := Shapes.box(self, "DrainMouth", Vector3(6.0, 2.4, 0.3), Vector3(0, floor_y + 1.2, end_z + 0.35), _material("Dark interior"))
	for k in 9:
		Shapes.cylinder(dark, "Bar", Vector3(-2.6 + k * 0.65, 0, 0.25), Vector3.UP, 0.04, 2.4, _material("Rust"), 6)
	_mist()


func _house(pick: Array, at: Vector3, yaw: float) -> Node3D:
	## One house (or the shop): painted, board by board up close and a simpler
	## shell from further off, walls you cannot walk through, a porch you can
	## stand on, and an occluder so it hides what is behind it.
	var width: float = pick[1]
	var depth: float = pick[2]
	var house := place(pick[0], at, yaw)
	var paint: Color = PAINT[rng.randi_range(0, PAINT.size() - 1)]
	for mesh: GeometryInstance3D in house.find_children("*", "GeometryInstance3D", true, false):
		mesh.set_instance_shader_parameter("tint", paint)
	if pick[0] != "shop":
		for mesh: GeometryInstance3D in house.find_children("*", "GeometryInstance3D", true, false):
			mesh.visibility_range_end = NEAR_DETAIL
			mesh.visibility_range_end_margin = 4.0
		var far := model(pick[0] + "_far", true)
		house.add_child(far)
		for mesh: GeometryInstance3D in far.find_children("*", "GeometryInstance3D", true, false):
			mesh.set_instance_shader_parameter("tint", paint)
			mesh.visibility_range_begin = NEAR_DETAIL
			mesh.visibility_range_begin_margin = 4.0
	_solid(house, Vector3(width, pick[3], depth), Vector3(0, pick[3] * 0.5, 0))
	var occluder := OccluderInstance3D.new()
	var block := BoxOccluder3D.new()
	block.size = Vector3(width - 0.4, pick[3] - 0.3, depth - 0.4)
	occluder.occluder = block
	house.add_child(occluder)
	occluder.position = Vector3(0, pick[3] * 0.5, 0)
	if pick[4] > 0.0:
		_solid(house, Vector3(width * 0.86, 0.12, pick[4]), Vector3(0, 1.31, depth * 0.5 + pick[4] * 0.5))
	return house


func _shop_sign(shop: Node3D, depth: float) -> void:
	_label(shop, "MARROW HARDWARE & FEED", Vector3(0, 4.45, depth * 0.5 + 0.17), 84, Color(0.22, 0.2, 0.17))


func _label(parent: Node3D, text: String, at: Vector3, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	parent.add_child(label)
	label.position = at
	return label


func _wire(a: Vector3, b: Vector3, sag: float) -> void:
	var points: Array[Vector3] = []
	for step in 9:
		var t := step / 8.0
		points.append(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
	var black := _material("Rubber")
	for step in 8:
		var from := points[step]
		var to := points[step + 1]
		var piece := Shapes.cylinder(self, "Wire", (from + to) * 0.5, to - from, 0.012, from.distance_to(to), black, 4)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _mist() -> void:
	## Low mist lying on the water, drifting.
	var mist := GPUParticles3D.new()
	mist.amount = 46
	mist.lifetime = 40.0
	mist.preprocess = 40.0
	mist.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(9.0, 0.3, 55.0)
	process.direction = Vector3(1, 0, 0.3)
	process.spread = 30.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.35
	process.gravity = Vector3.ZERO
	process.scale_min = 0.7
	process.scale_max = 1.4
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	mist.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(9.0, 2.2)
	var puff := StandardMaterial3D.new()
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff.vertex_color_use_as_albedo = true
	puff.albedo_color = Color(0.55, 0.6, 0.62, 0.07)
	puff.proximity_fade_enabled = true
	puff.proximity_fade_distance = 1.5
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var edge := Gradient.new()
	edge.set_color(0, Color(1, 1, 1, 1))
	edge.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = edge
	puff.albedo_texture = soft
	quad.material = puff
	mist.draw_pass_1 = quad
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mist.visibility_aabb = AABB(Vector3(-20, -3, -70), Vector3(40, 8, 140))
	add_child(mist)
	mist.position = Vector3(0, game.WATER_START + 0.5, -98.0)


# --- The hillside -----------------------------------------------------------------

func terrain_height(x: float, z: float) -> float:
	## The ridge on top, the hillside down to the street, a cutting for the road.
	var noise := (sin(x * 0.31 + z * 0.17) + sin(x * 0.13 - z * 0.29) * 0.7 + sin(x * 0.71 + z * 0.53) * 0.25) * 0.22
	var top := 0.0
	var slope: float = lerpf(game.FLOOR_Y - 0.3, top, smoothstep(-44.0, 10.0, z))
	var height := slope + noise * (0.25 if z > 10.0 else 1.0)
	# The camp is level ground.
	if z > 10.0 and absf(x) < 14.0:
		height = top + noise * 0.08
	# The road runs down a cutting: banks either side, below the road itself.
	var road: float = lerpf(game.FLOOR_Y, 0.0, clampf((z - game.RAMP_BOTTOM) / (game.RAMP_TOP - game.RAMP_BOTTOM), 0.0, 1.0))
	var near := absf(x)
	if z < 12.0:
		var bank := road + 0.4 + 0.9 * smoothstep(6.5, 12.0, near)
		height = lerpf(minf(road - 0.15, height), maxf(height, bank), smoothstep(6.2, 9.0, near))
	return height


func build_terrain() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := -46.0
	var z0 := -44.0
	var step := 1.5
	var nx := 62
	var nz := 62
	for i in nx:
		for j in nz:
			var corners := [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]
			var points: Array[Vector3] = []
			for c: Vector2 in corners:
				var x := x0 + c.x * step
				var z := z0 + c.y * step
				points.append(Vector3(x, terrain_height(x, z), z))
			for index in [0, 1, 2, 0, 2, 3]:
				tool.add_vertex(points[index])
	tool.generate_normals()
	var mesh := tool.commit()
	var hill := MeshInstance3D.new()
	hill.name = "Hillside"
	hill.mesh = mesh
	hill.material_override = ground_material(3)
	add_child(hill)
	var body := StaticBody3D.new()
	body.add_to_group("Dirt")
	hill.add_child(body)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	# Rocks and dead trees about the ridge and the slope.
	for k in 26:
		var x := rng.randf_range(-40.0, 40.0)
		var z := rng.randf_range(-36.0, 44.0)
		if absf(x) < 10.0 and z > -40.0 and z < 34.0:
			continue
		if rng.randf() < 0.7:
			var stone := place("rock_%d" % (k % 3), Vector3(x, terrain_height(x, z) - 0.1, z), rng.randf_range(0, TAU))
			stone.scale = Vector3.ONE * rng.randf_range(0.5, 1.6)
		else:
			place("tree", Vector3(x, terrain_height(x, z) - 0.2, z), rng.randf_range(0, TAU))
	var welcome := place("town_sign", Vector3(8.5, terrain_height(8.5, 7.0), 7.0), 0.15)
	_label(welcome, "MARROW\npop. 1,240", Vector3(0, 1.5, 0.1), 120, Color(0.2, 0.25, 0.2))
	# Someone has painted over it.
	_label(welcome, "GONE", Vector3(0.3, 1.25, 0.12), 150, Color(0.5, 0.08, 0.06)).rotation.z = 0.12


# --- The valley -------------------------------------------------------------------
## Marrow sits in a valley. Round the hillside and the street: hills and pine
## forest either side, the ridge and the road carrying on north to where it is
## closed, the railway embankment the storm drain runs under, and past it the
## lake the valley has become, out to the dam.

## The hills share grid lines with the hillside above, so they meet it edge to edge.
const CELL := 7.75
const CORE_X := Vector2(-46.0, 47.0)
const CORE_Z := Vector2(-44.0, 49.0)
const EMBANK_TOP := 3.2
const EMBANK_FRONT := -150.7
## Where anyone can go: up the hills either side, to the road block north,
## along the top of the embankment south. Past that is scenery.
const BOUNDS_X := 128.0
const BOUNDS_NORTH := 150.0
const BOUNDS_SOUTH := -163.5
const DAM_Z := -760.0

var hill_houses: Array[Vector3] = []


func valley_height(x: float, z: float) -> float:
	var ax := absf(x)
	var broad := sin(x * 0.011 + z * 0.007) + sin(x * 0.023 - z * 0.017) * 0.6 + sin(x * 0.05 + z * 0.043) * 0.3
	var height: float
	if z > CORE_Z.x:
		height = terrain_height(clampf(x, CORE_X.x, CORE_X.y), minf(z, CORE_Z.y))
		if z > CORE_Z.y:
			# The ridge climbs gently north; the road keeps a level strip.
			var rise := (z - CORE_Z.y) * 0.05
			height = rise if ax < 8.3 else height + rise + broad * 0.6 * smoothstep(8.3, 24.0, ax)
	else:
		# The valley floor under the flood, deeper past the embankment.
		height = lerpf(game.FLOOR_Y - 0.15, game.FLOOR_Y - 1.7, smoothstep(-172.0, -205.0, z))
	var width := 58.0 + maxf(0.0, -z - 180.0) * 0.15
	var hill := smoothstep(width, width + 100.0, ax)
	height += hill * (34.0 + broad * 9.0 + sin(x * 0.09 + z * 0.11) * 1.6 + sin(x * 0.17 - z * 0.13) * 0.8)
	# The far ranges that close the view all round.
	height += smoothstep(230.0, 540.0, ax) * (62.0 + broad * 22.0)
	height += smoothstep(320.0, 640.0, z) * (48.0 + broad * 14.0)
	height += smoothstep(DAM_Z + 20.0, DAM_Z - 200.0, z) * (170.0 + broad * 40.0)
	return height


func build_valley() -> void:
	# KM0_VALLEY_OFF=forest,hills,... leaves parts out, for measuring.
	var skip := OS.get_environment("KM0_VALLEY_OFF").split(",")
	for part in ["hills", "embankment", "back_rows", "hill_houses", "north_road", "forest", "lake", "bounds"]:
		if not part in skip:
			call("_build_" + part)


func _build_hills() -> void:
	## One big terrain round the hillside, smooth-shaded, with collision only
	## where people can actually walk.
	var i0 := -86
	var i1 := 98
	var j0 := -142
	var j1 := 62
	var cols := i1 - i0 + 1
	var heights := PackedFloat32Array()
	heights.resize(cols * (j1 - j0 + 1))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			heights[(j - j0) * cols + (i - i0)] = valley_height(CORE_X.x + i * CELL, CORE_Z.x + j * CELL)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	var index_of := {}
	for j in range(j0, j1):
		for i in range(i0, i1):
			var x0 := CORE_X.x + i * CELL
			var z0 := CORE_Z.x + j * CELL
			var inside_core := i >= 0 and i < 12 and j >= 0 and j < 12
			if inside_core and i > 0 and i < 11 and j > 0 and j < 11:
				continue
			# Under the street: nothing to see.
			if x0 >= -45.0 and x0 + CELL <= 45.0 and z0 >= -170.0 and z0 + CELL <= -30.0:
				continue
			var corners: Array[int] = []
			for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var gi := i + c.x
				var gj := j + c.y
				# Along the hillside's edge a dropped skirt fills any crack
				# between the two grids.
				var key := Vector3i(gi, gj, 1 if inside_core else 0)
				if not index_of.has(key):
					var h := heights[(gj - j0) * cols + (gi - i0)]
					var hl := heights[(gj - j0) * cols + maxi(gi - 1, i0) - i0]
					var hr := heights[(gj - j0) * cols + mini(gi + 1, i1) - i0]
					var hd := heights[(maxi(gj - 1, j0) - j0) * cols + gi - i0]
					var hu := heights[(mini(gj + 1, j1) - j0) * cols + gi - i0]
					index_of[key] = vertices.size()
					vertices.append(Vector3(CORE_X.x + gi * CELL, h - (1.5 if inside_core else 0.0), CORE_Z.x + gj * CELL))
					normals.append(Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized())
				corners.append(index_of[key])
			for k in [0, 1, 2, 0, 2, 3]:
				indices.append(corners[k])
			if not inside_core and x0 + CELL > -BOUNDS_X - 12.0 and x0 < BOUNDS_X + 12.0 and z0 + CELL > -178.0 and z0 < BOUNDS_NORTH + 12.0:
				for k in [0, 1, 2, 0, 2, 3]:
					faces.append(vertices[corners[k]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var hills := MeshInstance3D.new()
	hills.name = "Hills"
	hills.mesh = mesh
	hills.material_override = ground_material(3)
	hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hills)
	var body := StaticBody3D.new()
	body.add_to_group("Dirt")
	hills.add_child(body)
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	# Boulders out on the hills.
	for k in 40:
		var x := rng.randf_range(60.0, 125.0) * (-1.0 if k % 2 == 0 else 1.0)
		var z := rng.randf_range(-150.0, 140.0)
		var stone := place("rock_%d" % (k % 3), Vector3(x, valley_height(x, z) - 0.3, z), rng.randf_range(0, TAU))
		stone.scale = Vector3.ONE * rng.randf_range(1.0, 2.6)
		for mesh_part: GeometryInstance3D in stone.find_children("*", "GeometryInstance3D", true, false):
			mesh_part.visibility_range_end = 140.0
			mesh_part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_embankment() -> void:
	## The railway embankment across the valley: the storm drain at the end of
	## the street runs under it. A line on top, leaning telegraph poles.
	var floor_y: float = game.FLOOR_Y
	var profile: Array[Vector2] = [Vector2(EMBANK_FRONT, floor_y - 0.4), Vector2(-157.0, EMBANK_TOP),
		Vector2(-163.0, EMBANK_TOP), Vector2(-182.0, floor_y - 2.0)]
	var slopes := SurfaceTool.new()
	slopes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var step := 8.0
	var x := -260.0
	while x < 260.0:
		var rows: Array = []
		for at in [x, x + step]:
			var row: Array[Vector3] = []
			for n in profile.size():
				var y := profile[n].y
				# The slopes are lumpy where they have slumped.
				if n == 1 or n == 2:
					y += sin(at * 0.21) * 0.08
				row.append(Vector3(at, y, profile[n].x))
			# Mid-slope points so the faces bulge a little.
			row.insert(1, (row[0] + row[1]) * 0.5 + Vector3(0, 0.4 + sin(at * 0.37) * 0.35, 0))
			row.insert(4, (row[3] + row[4]) * 0.5 + Vector3(0, 0.6 + sin(at * 0.29 + 1.0) * 0.5, 0))
			rows.append(row)
		var a: Array = rows[0]
		var b: Array = rows[1]
		for n in a.size() - 1:
			var quad: Array[Vector3] = [a[n], b[n], b[n + 1], a[n + 1]]
			var tool := top if n == 2 else slopes
			for k in [0, 1, 2, 0, 2, 3]:
				tool.add_vertex(quad[k])
				faces.append(quad[k])
		x += step
	for pair in [[slopes, 3], [top, 2]]:
		var tool: SurfaceTool = pair[0]
		tool.index()
		tool.generate_normals()
		var piece := MeshInstance3D.new()
		piece.name = "Embankment"
		piece.mesh = tool.commit()
		piece.material_override = ground_material(pair[1])
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
	var body := StaticBody3D.new()
	body.add_to_group("Dirt")
	add_child(body)
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	# The line: sleepers, two rusted rails, a few sleepers gone or knocked askew.
	var sleeper := BoxMesh.new()
	sleeper.size = Vector3(0.26, 0.14, 2.6)
	sleeper.material = _material("Wood")
	var sleepers := MultiMesh.new()
	sleepers.transform_format = MultiMesh.TRANSFORM_3D
	sleepers.mesh = sleeper
	var spots: Array[Transform3D] = []
	var along := -255.0
	while along < 255.0:
		if rng.randf() > 0.06:
			var basis := Basis(Vector3.UP, rng.randf_range(-0.04, 0.04) + (rng.randf_range(-0.5, 0.5) if rng.randf() < 0.03 else 0.0))
			spots.append(Transform3D(basis, Vector3(along, EMBANK_TOP + 0.07, -160.0)))
		along += 0.75
	sleepers.instance_count = spots.size()
	for k in spots.size():
		sleepers.set_instance_transform(k, spots[k])
	var line := MultiMeshInstance3D.new()
	line.name = "Sleepers"
	line.multimesh = sleepers
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
	for rail_z in [-159.28, -160.72]:
		var rail := Shapes.box(self, "Rail", Vector3(510, 0.14, 0.08), Vector3(0, EMBANK_TOP + 0.21, rail_z), _material("Rust"))
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 15:
		var pole_x := -210.0 + k * 30.0 + rng.randf_range(-3.0, 3.0)
		var pole := place("pole", Vector3(pole_x, EMBANK_TOP - 0.1, -162.2), 0.0)
		pole.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.07, 0.07))
		for mesh_part: GeometryInstance3D in pole.find_children("*", "GeometryInstance3D", true, false):
			mesh_part.visibility_range_end = 0.0
			mesh_part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if absf(pole_x) < BOUNDS_X:
			_solid(pole, Vector3(0.3, 8.5, 0.3), Vector3(0, 4.25, 0))


func _build_back_rows() -> void:
	## The next street over: a row of houses behind each side of the main
	## street, facing away from it, with gaps where one has gone.
	var floor_y: float = game.FLOOR_Y
	for side in [-1.0, 1.0]:
		var z := -52.0 - rng.randf_range(0.0, 6.0)
		while z > game.STREET_END + 14.0:
			var pick: Array = HOUSES[rng.randi_range(0, 2)]
			var width: float = pick[1]
			var depth: float = pick[2]
			if rng.randf() < 0.2:
				# Washed off its footings: only the slab is left.
				Shapes.box(self, "Slab", Vector3(width, 0.5, depth), Vector3(side * (32.0 + depth * 0.5), floor_y + 0.2, z - width * 0.5), _material("Concrete"), true)
			else:
				var house := _house(pick, Vector3(side * (32.0 + depth * 0.5), floor_y, z - width * 0.5), side * PI * 0.5)
				house.rotation.z = rng.randf_range(-0.012, 0.012)
			z -= width + rng.randf_range(2.5, 9.0)
		# Its street lights, dead like the rest.
		for k in 4:
			var lamp := place("lamp", Vector3(side * 47.5, floor_y, -60.0 - k * 26.0), PI if side < 0.0 else 0.0)
			lamp.rotation.z = side * rng.randf_range(0.0, 0.1)
			for mesh_part: GeometryInstance3D in lamp.find_children("*", "GeometryInstance3D", true, false):
				mesh_part.visibility_range_end = 120.0
			_solid(lamp, Vector3(0.3, 5.0, 0.3), Vector3(0, 2.5, 0))


func _build_hill_houses() -> void:
	## A few houses up the hillsides, above the flood: on footings dug into the slope.
	var spots: Array[Vector2] = [Vector2(-78, -62), Vector2(-92, -118), Vector2(-70, 6), Vector2(-104, -20),
		Vector2(84, -84), Vector2(74, -132), Vector2(96, -36), Vector2(72, 24), Vector2(-44, 92), Vector2(52, 108)]
	for spot in spots:
		var pick: Array = HOUSES[rng.randi_range(0, 2)]
		var width: float = pick[1]
		var depth: float = pick[2]
		# Face down the slope.
		var toward := Vector2(valley_height(spot.x - 4.0, spot.y) - valley_height(spot.x + 4.0, spot.y),
			valley_height(spot.x, spot.y - 4.0) - valley_height(spot.x, spot.y + 4.0))
		var yaw := atan2(toward.x, toward.y) if toward.length() > 0.2 else 0.0
		yaw = snappedf(yaw, PI * 0.5) + rng.randf_range(-0.2, 0.2)
		var low := INF
		var high := -INF
		var basis := Basis(Vector3.UP, yaw)
		for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(0, 0, 1.6)]:
			var c: Vector3 = basis * (corner * Vector3(width * 0.5, 0, depth * 0.5 + 1.0))
			var h := valley_height(spot.x + c.x, spot.y + c.z)
			low = minf(low, h)
			high = maxf(high, h)
		var base := high + 0.2
		var house := _house(pick, Vector3(spot.x, base, spot.y), yaw)
		var footing := Shapes.box(house, "Footing", Vector3(width + 0.3, base - low + 1.2, depth + 0.3), Vector3(0, -(base - low + 1.2) * 0.5, 0), _material("Concrete"))
		footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hill_houses.append(Vector3(spot.x, base, spot.y))


func _build_north_road() -> void:
	## The road the trucks came in on, out past the camp and over the ridge,
	## closed a little way on.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := float(game.RAMP_TOP)
	var last: Array[Vector3] = []
	while z <= BOUNDS_NORTH + 160.0:
		var y: float
		if z < CORE_Z.y:
			y = maxf(maxf(terrain_height(-3.0, z), terrain_height(0.0, z)), maxf(terrain_height(3.0, z), 0.0)) + 0.08
		else:
			y = valley_height(0.0, z) + 0.06
		var row: Array[Vector3] = [Vector3(-3.2, y, z), Vector3(3.2, y, z)]
		if not last.is_empty():
			for v in [last[0], last[1], row[1], last[0], row[1], row[0]]:
				tool.add_vertex(v)
		last = row
		z += 1.5 if z < CORE_Z.y else CELL
	tool.generate_normals()
	var road := MeshInstance3D.new()
	road.name = "NorthRoad"
	road.mesh = tool.commit()
	road.material_override = ground_material(0)
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)
	# Closed: two barriers, a sign, and a pine down across it behind them.
	var block_z := BOUNDS_NORTH - 8.0
	var ground := valley_height(0.0, block_z)
	for x in [-2.2, 2.2]:
		var rail := Shapes.box(self, "Barrier", Vector3(2.6, 0.22, 0.06), Vector3(x, ground + 0.9, block_z), _material("Red paint"), true)
		for leg in [-1.1, 1.1]:
			var stand := Shapes.box(rail, "Leg", Vector3(0.08, 1.0, 0.08), Vector3(leg, -0.45, 0), _material("Wood"))
			stand.rotation.x = 0.25
	var sign_post := Shapes.box(self, "SignPost", Vector3(0.08, 1.6, 0.08), Vector3(4.2, ground + 0.8, block_z), _material("Wood"))
	_label(sign_post, "ROAD CLOSED", Vector3(0, 0.6, 0.06), 64, Color(0.92, 0.9, 0.82))
	var fallen := DesertModels.model("pine")
	add_child(fallen)
	fallen.position = Vector3(-6.0, ground + 0.3, block_z + 7.0)
	fallen.rotation = Vector3(0.0, 0.25, -PI * 0.5 + 0.06)
	_solid(self, Vector3(16.0, 1.4, 1.4), Vector3(0, ground + 0.6, block_z + 7.0))


func _build_forest() -> void:
	## Pines on the hills: full trees where anyone can get close, simple ones
	## for the far slopes, in chunks so each swaps for the other with distance.
	var near_parts := _parts_of(DesertModels.model("pine"))
	var far_parts := [[_far_pine(), Transform3D()]]
	var chunks := {}
	var spacing_near := 10.0
	var x := -660.0
	while x < 660.0:
		var z := -900.0
		while z < 430.0:
			var close := absf(x) < 220.0 and z > -320.0 and z < 260.0
			var spacing := spacing_near if close else 18.0
			var px := x + rng.randf_range(-0.4, 0.4) * spacing
			var pz := z + rng.randf_range(-0.4, 0.4) * spacing
			z += spacing
			var h := valley_height(px, pz)
			if h < game.WATER_END + 1.2:
				continue
			# Not in the town, the camp, on the road or by a house.
			if absf(px) < 52.0 and pz < CORE_Z.y + 6.0:
				continue
			if absf(px) < 12.0 and pz > CORE_Z.y:
				continue
			if absf(pz - DAM_Z) < 40.0:
				continue
			var crowded := false
			for house in hill_houses:
				if Vector2(px - house.x, pz - house.z).length() < 11.0:
					crowded = true
			if crowded:
				continue
			# Clearings and thick stands.
			var density := 0.35 + 0.45 * (0.5 + 0.5 * sin(px * 0.031 + pz * 0.023) * sin(px * 0.017 - pz * 0.041))
			if rng.randf() > density:
				continue
			var size := rng.randf_range(0.8, 1.35) * (1.0 if close else 1.25)
			var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(size, size * rng.randf_range(0.9, 1.15), size))
			basis = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.05)) * basis
			var spot := Transform3D(basis, Vector3(px, h - 0.25, pz))
			# Small chunks where the full trees swap in, big ones for the far slopes.
			var reachable := absf(px) < BOUNDS_X + 50.0 and pz > -230.0 and pz < BOUNDS_NORTH + 50.0
			var size_of := 40.0 if reachable else 220.0
			var key := Vector3i(floori(px / size_of), floori(pz / size_of), 1 if reachable else 0)
			if not chunks.has(key):
				chunks[key] = {"near": [], "far": [], "detailed": reachable}
			var chunk: Dictionary = chunks[key]
			if reachable:
				chunk["near"].append(spot)
			chunk["far"].append(spot)
		x += spacing_near if absf(x) < 220.0 else 18.0
	var forest := Node3D.new()
	forest.name = "Forest"
	add_child(forest)
	for key: Vector3i in chunks:
		var chunk: Dictionary = chunks[key]
		if chunk["detailed"]:
			for made in _multimesh(near_parts, chunk["near"], forest):
				made.visibility_range_end = 70.0
				made.visibility_range_end_margin = 8.0
		for made in _multimesh(far_parts, chunk["far"], forest):
			made.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if chunk["detailed"]:
				made.visibility_range_begin = 70.0
				made.visibility_range_begin_margin = 8.0
	# Dead trees standing in the shallows and out in the lake.
	var dead: Array[Transform3D] = []
	for k in 160:
		var px := rng.randf_range(-260.0, 260.0)
		var pz := rng.randf_range(-700.0, -175.0)
		var h := valley_height(px, pz)
		if h > game.WATER_END + 0.8 or h < game.WATER_START - 2.5:
			continue
		var size := rng.randf_range(0.9, 1.6)
		dead.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * size), Vector3(px, h - 0.4, pz)))
	for made in _multimesh(_parts_of(model("tree")), dead, forest):
		made.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _parts_of(node: Node3D) -> Array:
	## Every mesh in a model with its materials baked in and where it sits in
	## the model: [[mesh, transform], ...]. Frees the model.
	var parts := []
	for source: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := source.mesh.duplicate() as Mesh
		for surface in mesh.get_surface_count():
			var material := source.get_surface_override_material(surface)
			if material:
				mesh.surface_set_material(surface, material)
		var local := Transform3D()
		var walk: Node = source
		while walk != node:
			local = (walk as Node3D).transform * local
			walk = walk.get_parent()
		parts.append([mesh, local])
	node.free()
	return parts


func _multimesh(parts: Array, spots: Array, parent: Node3D) -> Array[MultiMeshInstance3D]:
	var made: Array[MultiMeshInstance3D] = []
	if spots.is_empty():
		return made
	for part: Array in parts:
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = part[0]
		many.instance_count = spots.size()
		for k in spots.size():
			many.set_instance_transform(k, (spots[k] as Transform3D) * (part[1] as Transform3D))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = many
		parent.add_child(instance)
		made.append(instance)
	return made


func _far_pine() -> Mesh:
	## A pine seen from far off: stacked cones of dark needles on a bare trunk,
	## shaded darker underneath each tier the way the full tree is.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 7
	var tiers := [[1.4, 2.0, 4.2], [3.0, 1.6, 3.4], [4.4, 1.15, 2.7], [5.6, 0.7, 2.0]]
	for tier: Array in tiers:
		var base: float = tier[0]
		var radius: float = tier[1]
		var tall: float = tier[2]
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var p0 := Vector3(cos(a0) * radius, base, sin(a0) * radius)
			var p1 := Vector3(cos(a1) * radius, base, sin(a1) * radius)
			var tip := Vector3(0, base + tall, 0)
			tool.set_color(Color(0.55, 0.55, 0.55))
			tool.add_vertex(p0)
			tool.set_color(Color(1, 1, 1))
			tool.add_vertex(tip)
			tool.set_color(Color(0.55, 0.55, 0.55))
			tool.add_vertex(p1)
			# The underside, dark.
			tool.set_color(Color(0.3, 0.3, 0.3))
			tool.add_vertex(p1)
			tool.add_vertex(Vector3(0, base + 0.3, 0))
			tool.add_vertex(p0)
	tool.generate_normals()
	var mesh := tool.commit()
	var needles := StandardMaterial3D.new()
	needles.albedo_color = Color(0.13, 0.19, 0.13)
	needles.vertex_color_use_as_albedo = true
	needles.roughness = 1.0
	mesh.surface_set_material(0, needles)
	return mesh


func _build_lake() -> void:
	## Past the embankment the valley is a lake, out to the dam that let go.
	var concrete := _material("Concrete")
	var floor_y: float = game.FLOOR_Y
	for side in [-1.0, 1.0]:
		var wall := Shapes.box(self, "Dam", Vector3(250.0, 52.0, 16.0), Vector3(side * 150.0, floor_y + 22.0, DAM_Z), concrete)
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The parapet along the top.
		var parapet := Shapes.box(wall, "Parapet", Vector3(250.0, 1.4, 1.0), Vector3(0, 26.7, 7.5), concrete)
		parapet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The breach: the middle gone down to a broken stub, slabs of it in the water.
	var stub := Shapes.box(self, "DamStub", Vector3(50.0, 12.0, 16.0), Vector3(0, floor_y + 2.0, DAM_Z), concrete)
	stub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 6:
		var slab := Shapes.box(self, "DamSlab", Vector3(rng.randf_range(8, 16), rng.randf_range(5, 10), rng.randf_range(5, 9)),
			Vector3(rng.randf_range(-30, 30), floor_y + rng.randf_range(-1.0, 2.0), DAM_Z + 18.0 + rng.randf_range(0, 40)), concrete)
		slab.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0, TAU), rng.randf_range(-0.6, 0.6))
		slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Roofs of the farms out in the fields, just showing.
	for k in 7:
		var at := Vector3(rng.randf_range(-90, 90), floor_y - 2.6, rng.randf_range(-260, -560))
		var farm := model(["house_a_far", "house_c_far"][k % 2], true)
		add_child(farm)
		farm.position = at
		farm.rotation = Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(0, TAU), rng.randf_range(-0.06, 0.06))
		var paint: Color = PAINT[rng.randi_range(0, PAINT.size() - 1)]
		for mesh_part: GeometryInstance3D in farm.find_children("*", "GeometryInstance3D", true, false):
			mesh_part.set_instance_shader_parameter("tint", paint)
			mesh_part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_bounds() -> void:
	## Out past the hills and the embankment is only scenery: walls nobody sees.
	var body := StaticBody3D.new()
	body.name = "Bounds"
	add_child(body)
	var span_z := BOUNDS_NORTH - BOUNDS_SOUTH
	var walls := [
		[Vector3(2.0, 200.0, span_z + 4.0), Vector3(-BOUNDS_X - 1.0, 40.0, (BOUNDS_NORTH + BOUNDS_SOUTH) * 0.5)],
		[Vector3(2.0, 200.0, span_z + 4.0), Vector3(BOUNDS_X + 1.0, 40.0, (BOUNDS_NORTH + BOUNDS_SOUTH) * 0.5)],
		[Vector3(BOUNDS_X * 2.0 + 4.0, 200.0, 2.0), Vector3(0, 40.0, BOUNDS_NORTH + 1.0)],
		[Vector3(BOUNDS_X * 2.0 + 4.0, 200.0, 2.0), Vector3(0, 40.0, BOUNDS_SOUTH - 1.0)],
	]
	for wall: Array in walls:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall[0]
		shape.shape = box
		body.add_child(shape)
		shape.position = wall[1]
