extends RefCounted

const SAND := Color("#aa8b64")
const MEADOW := Color("#848d4a")
const FOREST := Color("#646f51")
const BADLANDS := Color("#ad7553")
const COLORS := [SAND, MEADOW, FOREST, BADLANDS]
const BIOME_LENGTH := 880.0
const BLEND_DISTANCE := 140.0
const WIDTH := 900.0
const LEVEL := -0.041

var terrain_material := StandardMaterial3D.new()
var plants: Dictionary = {}


func _init() -> void:
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.vertex_color_is_srgb = true
	terrain_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	terrain_material.roughness = 1.0
	plants = {
		"scrub": _mesh(SphereMesh.new(), Color("#797a46"), Vector3(0.9, 0.44, 0.8)),
		"cactus": _mesh(CylinderMesh.new(), Color("#5f794b"), Vector3(0.18, 1.65, 0.18)),
		"grass": _mesh(PrismMesh.new(), Color("#8f984c"), Vector3(0.13, 0.44, 0.08)),
		"trunk": _mesh(CylinderMesh.new(), Color("#665543"), Vector3(0.25, 2.4, 0.25)),
		"leaves": _mesh(SphereMesh.new(), Color("#586f43"), Vector3(2.55, 1.58, 2.05)),
		"pine": _mesh(CylinderMesh.new(), Color("#3f624f"), Vector3(2.2, 2.1, 2.2), true),
		"rock": _mesh(SphereMesh.new(), Color("#8f614f"), Vector3(3.8, 2.2, 3.1)),
	}


func _mesh(mesh: PrimitiveMesh, tint: Color, dimensions: Vector3, cone: bool = false) -> PrimitiveMesh:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.91
	mesh.material = material
	if mesh is SphereMesh:
		mesh.radial_segments = 7
		mesh.rings = 3
	elif mesh is CylinderMesh:
		mesh.top_radius = 0.0 if cone else 0.5
		mesh.bottom_radius = 0.5
		mesh.radial_segments = 7
		mesh.rings = 0
	# Bake proportions into the instance transform so meshes can be shared.
	mesh.set_meta("dimensions", dimensions)
	return mesh


static func _climate(z: float) -> float:
	return maxf(-z - 180.0, 0.0) / BIOME_LENGTH


static func dust_tint(z: float) -> Color:
	var climate := _climate(z)
	var region := floori(climate)
	var blend := smoothstep(1.0 - BLEND_DISTANCE / BIOME_LENGTH, 1.0, fposmod(climate, 1.0))
	# Green ground still kicks up the soil underneath the grass.
	var soils := [SAND, Color("#918166"), Color("#756852"), BADLANDS]
	return soils[region % soils.size()].lerp(soils[(region + 1) % soils.size()], blend)


static func dust_amount(z: float) -> float:
	var climate := _climate(z)
	var cover := [1.0, 0.28, 0.38, 0.88]
	var region := floori(climate)
	var blend := smoothstep(1.0 - BLEND_DISTANCE / BIOME_LENGTH, 1.0, fposmod(climate, 1.0))
	return lerpf(cover[region % cover.size()], cover[(region + 1) % cover.size()], blend)


func _add_vertex(surface: SurfaceTool, x: float, z: float, start: float, color: Color) -> void:
	surface.set_normal(Vector3.UP)
	surface.set_color(color)
	surface.add_vertex(Vector3(x, LEVEL, z - start))


func _ground_color(x: float, z: float) -> Color:
	var climate := _climate(z)
	var region := floori(climate)
	var blend := smoothstep(1.0 - BLEND_DISTANCE / BIOME_LENGTH, 1.0, fposmod(climate, 1.0))
	var color: Color = COLORS[region % COLORS.size()].lerp(COLORS[(region + 1) % COLORS.size()], blend)
	var variation := sin(x * 0.069 + z * 0.025) * cos(z * 0.036 - x * 0.021) * 0.055
	return color.lightened(maxf(variation, 0.0)).darkened(maxf(-variation, 0.0))


func populate(segment: Node3D, start: float, length: float, index: int, clear_start: bool, stop_side: float, road_x: Callable) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(8):
		var z0 := start + length * row / 8.0
		var z1 := start + length * (row + 1) / 8.0
		for column in range(30):
			var x0 := -WIDTH * 0.5 + WIDTH * column / 30.0
			var x1 := x0 + WIDTH / 30.0
			for point in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x0, z1), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]:
				_add_vertex(surface, point.x, point.y, start, _ground_color(point.x, point.y))
	var ground := MeshInstance3D.new()
	ground.name = "BiomeGround"
	ground.mesh = surface.commit()
	ground.material_override = terrain_material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	segment.add_child(ground)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("biome:%d" % index)
	var batches := {}
	var grassy_region := floori(_climate(start)) % COLORS.size() in [1, 2] or floori(_climate(start + length)) % COLORS.size() in [1, 2]
	for point in range(420 if grassy_region else 128):
		var z := rng.randf_range(start, start + length)
		var far := 38.0 if point >= 128 else 118.0
		var offset := rng.randf_range(7.3, far) * (1.0 if point % 2 == 0 else -1.0)
		var x: float = road_x.call(z) + offset
		# Leave space for the workshop, including the bays added for a full lobby.
		if clear_start and x > -24.0 and x < 40.0 and absf(z) < 44.0:
			continue
		if stop_side * offset > 0 and absf(offset) < 25.0 and absf(z - start - length * 0.5) < 12.0:
			continue
		var climate := _climate(z)
		var region := floori(climate)
		var blend := smoothstep(1.0 - BLEND_DISTANCE / BIOME_LENGTH, 1.0, fposmod(climate, 1.0))
		var biome := (region + (1 if rng.randf() < blend else 0)) % COLORS.size()
		var at := Vector3(x, LEVEL, z - start)
		var size := rng.randf_range(0.65, 1.35)
		var turn := rng.randf_range(0.0, TAU)
		var roll := rng.randf()
		if point >= 128 and biome in [1, 2]:
			_grass(batches, at, size * 0.72, turn)
			continue
		if point >= 128:
			continue
		match biome:
			0:
				if roll < 0.09:
					_instance(batches, "cactus", at + Vector3.UP * 0.81 * size, size, turn)
					for side in [-1.0, 1.0]:
						var arm := Vector3(side * 0.24, 0.76, 0).rotated(Vector3.UP, turn) * size
						_instance(batches, "cactus", at + arm, size * 0.48, turn)
						_instance(batches, "cactus", at + arm * Vector3(0.6, 0.68, 0.6), size * 0.30, turn, PI * 0.43)
				elif roll < 0.58:
					_scrub(batches, at, size, turn)
			1:
				_grass(batches, at, size, turn)
				if roll < 0.085 and absf(offset) > 16.0:
					_tree(batches, at, size, turn, false)
			2:
				_grass(batches, at, size, turn)
				if roll < 0.38 and absf(offset) > 12.0:
					_tree(batches, at, size, turn, true)
			3:
				if roll < 0.25:
					_instance(batches, "rock", at + Vector3.UP * 0.32, size, turn)
				elif roll < 0.49:
					_scrub(batches, at, size * 0.8, turn)
	for kind in batches:
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = plants[kind]
		instances.instance_count = batches[kind].size()
		for index_in_batch in instances.instance_count:
			instances.set_instance_transform(index_in_batch, batches[kind][index_in_batch])
		var visual := MultiMeshInstance3D.new()
		visual.name = kind.capitalize()
		visual.multimesh = instances
		if kind in ["grass", "scrub"]:
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		segment.add_child(visual)


func _instance(batches: Dictionary, kind: String, at: Vector3, scale: float, turn: float, tilt: float = 0.0) -> void:
	if not batches.has(kind):
		batches[kind] = []
	var dimensions: Vector3 = plants[kind].get_meta("dimensions")
	var basis := (Basis(Vector3.UP, turn) * Basis(Vector3.FORWARD, tilt)).scaled_local(dimensions * scale)
	batches[kind].append(Transform3D(basis, at))


func _scrub(batches: Dictionary, at: Vector3, size: float, turn: float) -> void:
	for lobe in [-1.0, 0.0, 1.0]:
		var offset := Vector3(lobe * 0.34, 0.15 - absf(lobe) * 0.06, 0).rotated(Vector3.UP, turn) * size
		_instance(batches, "scrub", at + offset, size * (1.0 - absf(lobe) * 0.26), turn)


func _grass(batches: Dictionary, at: Vector3, size: float, turn: float) -> void:
	for blade in range(4):
		var angle := turn + blade * 1.57
		var offset := Vector3(0.11, 0.14, 0).rotated(Vector3.UP, angle) * size
		_instance(batches, "grass", at + offset, size, angle, 0.28)


func _tree(batches: Dictionary, at: Vector3, size: float, turn: float, pine: bool) -> void:
	_instance(batches, "trunk", at + Vector3.UP * 1.05 * size, size, turn)
	if pine:
		for tier in range(3):
			_instance(batches, "pine", at + Vector3.UP * (1.65 + tier * 0.77) * size, size * (1.12 - tier * 0.22), turn)
	else:
		_instance(batches, "leaves", at + Vector3.UP * 2.27 * size, size, turn)
		_instance(batches, "leaves", at + Vector3(0.54, 2.8, 0.19) * size, size * 0.75, turn)
