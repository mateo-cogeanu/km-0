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
## [model, width along the street, depth, top of the walls, porch depth]
const HOUSES := [
	["house_a", 9.0, 9.0, 6.0, 2.4], ["house_b", 10.0, 8.5, 3.3, 2.2],
	["house_c", 8.0, 10.0, 6.0, 0.0], ["shop", 11.0, 10.0, 5.6, 0.0],
]
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


func model(title: String) -> Node3D:
	if not scenes.has(title):
		scenes[title] = load("res://assets/salvage/%s.glb" % title)
	var node: Node3D = (scenes[title] as PackedScene).instantiate()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			var title_name := source.resource_name.get_slice(".", 0) if source else ""
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
			var house := place(pick[0], Vector3(side * (14.0 + depth * 0.5), floor_y, z - width * 0.5), -side * PI * 0.5)
			var paint: Color = PAINT[rng.randi_range(0, PAINT.size() - 1)]
			for mesh: GeometryInstance3D in house.find_children("*", "GeometryInstance3D", true, false):
				mesh.set_instance_shader_parameter("tint", paint)
			if pick[0] != "shop":
				# Board by board up close; from down the street, a simpler shell
				# of the same house.
				for mesh: GeometryInstance3D in house.find_children("*", "GeometryInstance3D", true, false):
					mesh.visibility_range_end = 55.0
					mesh.visibility_range_end_margin = 4.0
				var far := model(pick[0] + "_far")
				house.add_child(far)
				for mesh: GeometryInstance3D in far.find_children("*", "GeometryInstance3D", true, false):
					mesh.set_instance_shader_parameter("tint", paint)
					mesh.visibility_range_begin = 55.0
					mesh.visibility_range_begin_margin = 4.0
			# Walls you cannot walk through; a porch you can stand on. The
			# walls also hide whatever is behind them from the renderer.
			_solid(house, Vector3(width, pick[3], depth), Vector3(0, pick[3] * 0.5, 0))
			var occluder := OccluderInstance3D.new()
			var block := BoxOccluder3D.new()
			block.size = Vector3(width - 0.4, pick[3] - 0.3, depth - 0.4)
			occluder.occluder = block
			house.add_child(occluder)
			occluder.position = Vector3(0, pick[3] * 0.5, 0)
			if pick[4] > 0.0:
				_solid(house, Vector3(width * 0.86, 0.12, pick[4]), Vector3(0, 1.31, depth * 0.5 + pick[4] * 0.5))
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
