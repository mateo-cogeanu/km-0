extends RefCounted

const Desert := preload("res://scripts/desert_models.gd")
const GROUND := preload("res://assets/desert/desert_ground.gdshader")

const SAND := Color("#aa8b64")
const MEADOW := Color("#7b7c46")
const FOREST := Color("#5d6545")
## How much of each biome is grass (the ground shader reads it from the
## vertex alpha, 1 - grass, so meshes without colours stay bare).
const GRASSY := [0.0, 1.0, 1.0, 0.0]
const BADLANDS := Color("#ad7553")
const COLORS := [SAND, MEADOW, FOREST, BADLANDS]
const BIOME_LENGTH := 880.0
const BLEND_DISTANCE := 140.0
const WIDTH := 900.0
const LEVEL := -0.041

var terrain_material := ShaderMaterial.new()
var plants: Dictionary = {}


func _init() -> void:
	terrain_material.shader = GROUND
	terrain_material.set_shader_parameter("noise_tex", Desert.noise_texture())
	# Plants and rocks from Sources/make_roadside_props.py, standing on their origins.
	for kind in ["scrub", "scrub_b", "cactus", "cactus_b", "grass", "grass_b", "tree", "pine", "dead_tree", "rock", "rock_b"]:
		plants[kind] = Desert.mesh_of(kind)


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
	color = color.lightened(maxf(variation, 0.0)).darkened(maxf(-variation, 0.0))
	color.a = 1.0 - lerpf(GRASSY[region % GRASSY.size()], GRASSY[(region + 1) % GRASSY.size()], blend)
	return color


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
			_grass(batches, at, size * 0.9, turn, roll < (0.55 if biome == 1 else 0.7))
			continue
		if point >= 128:
			continue
		match biome:
			0:
				if roll < 0.09:
					_instance(batches, "cactus" if roll < 0.05 else "cactus_b", at, size * 0.85, turn)
				elif roll < 0.58:
					_scrub(batches, at, size, turn)
				elif roll < 0.62:
					_instance(batches, "dead_tree", at, size * 0.9, turn)
				elif roll < 0.75:
					_grass(batches, at, size * 0.8, turn)
			1:
				_grass(batches, at, size, turn, roll < 0.5)
				if roll < 0.085 and absf(offset) > 16.0:
					_tree(batches, at, size, turn, false)
			2:
				_grass(batches, at, size, turn, roll < 0.7)
				if roll < 0.38 and absf(offset) > 12.0:
					_tree(batches, at, size, turn, true)
			3:
				if roll < 0.25:
					_instance(batches, "rock" if roll < 0.13 else "rock_b", at + Vector3.DOWN * 0.15 * size, size * 1.6, turn)
				elif roll < 0.49:
					_scrub(batches, at, size * 0.8, turn)
	# Grassland: a thick sward along the verge, thinning out with distance
	# (the tufts further out are drawn only while near).
	if grassy_region:
		for point in range(1500):
			var z := rng.randf_range(start, start + length)
			var offset := pow(rng.randf(), 1.4) * 28.0 + 6.6
			offset *= 1.0 if point % 2 == 0 else -1.0
			var x: float = road_x.call(z) + offset
			if clear_start and x > -24.0 and x < 40.0 and absf(z) < 44.0:
				continue
			if stop_side * offset > 0 and absf(offset) < 25.0 and absf(z - start - length * 0.5) < 12.0:
				continue
			var climate := _climate(z)
			var blend := smoothstep(1.0 - BLEND_DISTANCE / BIOME_LENGTH, 1.0, fposmod(climate, 1.0))
			var biome := (floori(climate) + (1 if rng.randf() < blend else 0)) % COLORS.size()
			if biome not in [1, 2]:
				continue
			var roll := rng.randf()
			_grass(batches, Vector3(x, LEVEL, z - start), rng.randf_range(0.9, 1.9), rng.randf_range(0.0, TAU), roll < (0.5 if biome == 1 else 0.7))
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
		if kind in ["grass", "grass_b", "scrub", "scrub_b", "dead_tree"]:
			visual.visibility_range_end = 70.0 if kind.begins_with("grass") else 140.0
		if kind in ["grass", "grass_b", "scrub", "scrub_b"]:
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		segment.add_child(visual)


func _instance(batches: Dictionary, kind: String, at: Vector3, scale: float, turn: float, tilt: float = 0.0) -> void:
	if not batches.has(kind):
		batches[kind] = []
	var basis := (Basis(Vector3.UP, turn) * Basis(Vector3.FORWARD, tilt)).scaled_local(Vector3.ONE * scale)
	batches[kind].append(Transform3D(basis, at))


func _scrub(batches: Dictionary, at: Vector3, size: float, turn: float) -> void:
	_instance(batches, "scrub" if fmod(turn, 1.0) < 0.5 else "scrub_b", at, size * 1.1, turn)


func _grass(batches: Dictionary, at: Vector3, size: float, turn: float, green := false) -> void:
	_instance(batches, "grass_b" if green else "grass", at, size * 1.1, turn, 0.0)


func _tree(batches: Dictionary, at: Vector3, size: float, turn: float, pine: bool) -> void:
	_instance(batches, "pine" if pine else "tree", at, size * (1.0 if pine else 1.15), turn)
