extends RefCounted
## The vehicles' Blender parts (Sources/make_road_vehicles.py, in
## assets/desert/vehicles/) and their materials, plus the sun-and-dust aging
## laid over car paint. Painted panels stay StandardMaterial3D so the game can
## still recolour, spray and save them; the aging rides along in textures made
## here at load time, so nothing needs shipping.

const Desert := preload("res://scripts/desert_models.gd")

static var scenes := {}
static var meshes := {}
static var looks := {}
static var textures := {}


static func _noise(key: String, frequency: float, ramp: Gradient, seed_value: int) -> NoiseTexture2D:
	if not textures.has(key):
		var source := FastNoiseLite.new()
		source.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		source.frequency = frequency
		source.fractal_octaves = 4
		source.seed = seed_value
		var texture := NoiseTexture2D.new()
		texture.width = 256
		texture.height = 256
		texture.seamless = true
		texture.noise = source
		texture.color_ramp = ramp
		textures[key] = texture
	return textures[key]


static func _ramp(points: Array) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(points.map(func(p: Array) -> float: return p[0]))
	gradient.colors = PackedColorArray(points.map(func(p: Array) -> Color: return p[1]))
	return gradient


static func _grime(wear: float) -> ImageTexture:
	## Dust (or, on wrecks, rust and bare primer) for a body panel, in panel UV2
	## space: u runs along the car, v from the roof (0) down to the sills (1).
	## The alpha says where it lies: mostly low down and in streaks under the
	## belt line; on wrecks it climbs higher. (The detail mask itself would be
	## read through UV1, so the mask lives here.)
	var key := "grime_%d" % roundi(wear * 10.0)
	if textures.has(key):
		return textures[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	noise.seed = 21
	var rusty := wear > 0.5
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var reach := lerpf(0.72, 0.35, wear)
	for y in 256:
		var v := y / 255.0
		var low := smoothstep(reach, 1.0, v)
		for x in 256:
			var n := noise.get_noise_2d(x, y * 0.35) * 0.5 + 0.5
			var grain := noise.get_noise_2d(x * 4.0 + 300.0, y * 4.0) * 0.5 + 0.5
			var streak := noise.get_noise_2d(x * 3.0, 40.0) * 0.5 + 0.5
			var amount := clampf(low * (0.55 + 0.6 * n) + smoothstep(0.62, 0.9, streak) * smoothstep(0.4, 0.8, v) * 0.35 * wear, 0.0, 1.0)
			if v < 0.04:
				amount = 0.0
			var color: Color
			if rusty:
				color = Color("#5e3420").lerp(Color("#8a5233"), grain).lerp(Color("#a8987a"), smoothstep(0.55, 0.8, n))
			else:
				color = Color("#a08a68").lerp(Color("#bba783"), grain)
			color.a = amount
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	textures[key] = texture
	return texture


static func age_paint(paint: StandardMaterial3D, wear: float) -> void:
	## Sun-faded, dusty paint: a soft mottled fade, patchy gloss, and dust (on
	## wrecks, rust and bare primer) gathered low down on each panel.
	var w := clampf(wear, 0.0, 1.0)
	paint.uv1_triplanar = true
	paint.uv1_scale = Vector3.ONE * 0.45
	var fade := lerpf(0.93, 0.72, w)
	paint.albedo_texture = _noise("fade_%d" % roundi(w * 10.0), 0.01, _ramp([[0.0, Color(fade, fade, fade * 0.98)], [1.0, Color.WHITE]]), 11)
	paint.roughness_texture = _noise("gloss", 0.015, _ramp([[0.0, Color(0.75, 0.75, 0.75)], [1.0, Color.WHITE]]), 12)
	paint.detail_enabled = true
	paint.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	paint.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	paint.detail_albedo = _grime(w)


static func material(title: String, wear := 0.0) -> Material:
	var key := "%s:%d" % [title, 1 if wear > 0.5 else 0]
	if looks.has(key):
		return looks[key]
	var made: Material
	var rusty := wear > 0.5
	match title:
		"Rubber", "Tread":
			var rubber := StandardMaterial3D.new()
			rubber.albedo_color = Color(0.05, 0.05, 0.048) if title == "Rubber" else Color(0.035, 0.035, 0.034)
			if rusty:
				rubber.albedo_color = rubber.albedo_color.lerp(Color("#8d806a"), 0.25)
			rubber.roughness = 0.9
			rubber.cull_mode = BaseMaterial3D.CULL_DISABLED
			made = rubber
		"Steel", "Chrome":
			if rusty:
				made = Desert.weathered(Color(0.32, 0.25, 0.2), {"metallic_base": 0.3, "roughness_base": 0.8, "rust": 0.9, "dust": 0.3}, true)
			else:
				var metal := StandardMaterial3D.new()
				metal.albedo_color = Color(0.6, 0.6, 0.58) if title == "Steel" else Color(0.85, 0.85, 0.83)
				metal.metallic = 0.75 if title == "Steel" else 1.0
				metal.roughness = 0.42 if title == "Steel" else 0.16
				metal.cull_mode = BaseMaterial3D.CULL_DISABLED
				made = metal
		"Gauge":
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.03, 0.03, 0.03)
			dark.roughness = 0.6
			made = dark
		"Vinyl":
			var vinyl := StandardMaterial3D.new()
			vinyl.albedo_color = Color(0.085, 0.085, 0.085)
			vinyl.roughness = 0.62
			made = vinyl
		"Upholstery":
			made = Desert.weathered(Color(0.36, 0.33, 0.28), {"bleach": 0.35, "roughness_base": 1.0, "dust": 0.0, "streaks": 0.0, "wood_grain": 0.3})
		"Carpet":
			made = Desert.weathered(Color(0.19, 0.18, 0.16), {"bleach": 0.0, "roughness_base": 1.0, "dust": 0.0, "streaks": 0.0})
		"Van paint":
			made = Desert.weathered(Color(0.5, 0.53, 0.43), {"metallic_base": 0.15, "roughness_base": 0.6, "peel": 0.35,
				"under_color": Color(0.45, 0.43, 0.4), "rust": 0.45, "bleach": 0.5, "streaks": 0.45, "dust": 0.6})
		"Lens":
			var lens := StandardMaterial3D.new()
			lens.albedo_color = Color(0.86, 0.84, 0.76)
			lens.metallic = 0.3
			lens.roughness = 0.2
			made = lens
		"Glass":
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.16, 0.2, 0.21, 0.4)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.metallic = 0.2
			glass.roughness = 0.1
			glass.cull_mode = BaseMaterial3D.CULL_DISABLED
			made = glass
		_:
			made = Desert.material(title)
	looks[key] = made
	return made


static func model(title: String, wear := 0.0) -> Node3D:
	if not scenes.has(title):
		scenes[title] = load("res://assets/desert/vehicles/%s.glb" % title)
	var node: Node3D = (scenes[title] as PackedScene).instantiate()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			mesh.set_surface_override_material(surface, material(source.resource_name.get_slice(".", 0) if source else "", wear))
	return node


static func mesh(title: String, wear := 0.0) -> Mesh:
	## The part's mesh with its own materials baked in, shared.
	var key := "%s:%d" % [title, 1 if wear > 0.5 else 0]
	if not meshes.has(key):
		var node := model(title, wear)
		var source: MeshInstance3D = node.find_children("*", "MeshInstance3D", true, false)[0]
		var copy := source.mesh.duplicate() as ArrayMesh
		for surface in copy.get_surface_count():
			copy.surface_set_material(surface, source.get_surface_override_material(surface))
		meshes[key] = copy
		node.free()
	return meshes[key]


static func unit(title: String, size: Vector3, flip_z := false) -> ArrayMesh:
	## A unit part stretched to `size` (and turned round for the back of the
	## car), for a MeshInstance3D that keeps its own material_override.
	var key := "unit:%s:%s:%s" % [title, size, flip_z]
	if meshes.has(key):
		return meshes[key]
	var source := mesh(title)
	var stretched := ArrayMesh.new()
	var scale := Vector3(size.x, size.y, size.z * (-1.0 if flip_z else 1.0))
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			vertices[i] *= scale
			normals[i] = (normals[i] / scale).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		if flip_z and arrays[Mesh.ARRAY_INDEX] != null:
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, indices.size(), 3):
				var swap := indices[i + 1]
				indices[i + 1] = indices[i + 2]
				indices[i + 2] = swap
			arrays[Mesh.ARRAY_INDEX] = indices
		stretched.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	meshes[key] = stretched
	return stretched


static func has_panel(title: String) -> bool:
	return ResourceLoader.exists("res://assets/desert/vehicles/%s.glb" % title)


static func panel(title: String, lift := 0.0) -> ArrayMesh:
	## A body panel from Sources/make_car_bodies.py, ready for a painted
	## MeshInstance3D: one surface (the paint comes from material_override), and
	## a UV2 that says how high on the car each point is, for the dust.
	var key := "panel:%s:%.3f" % [title, lift]
	if meshes.has(key):
		return meshes[key]
	if not scenes.has(title):
		scenes[title] = load("res://assets/desert/vehicles/%s.glb" % title)
	var node: Node3D = (scenes[title] as PackedScene).instantiate()
	var source: MeshInstance3D = node.find_children("*", "MeshInstance3D", true, false)[0]
	var built := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var grime := PackedVector2Array()
		grime.resize(vertices.size())
		for i in vertices.size():
			var p := vertices[i]
			grime[i] = Vector2(p.z * 0.22 + 0.5 + p.x * 0.05, clampf(1.0 - (p.y + lift - 0.25) / 1.3, 0.0, 1.0))
		arrays[Mesh.ARRAY_TEX_UV2] = grime
		arrays[Mesh.ARRAY_TANGENT] = null
		built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.free()
	meshes[key] = built
	return built


static func reshape(instance: MeshInstance3D, title: String, flip_z := false) -> void:
	## Swap a code-built box for the Blender part, same size, same material.
	var box := instance.mesh as BoxMesh
	if box:
		instance.mesh = unit(title, box.size, flip_z)


static func smooth(mesh: ArrayMesh, crease := 0.55, lift := 0.0) -> ArrayMesh:
	## Rounded shading across the facets of a panel, keeping sharp edges
	## (faces meeting at more than about 57 degrees) sharp.
	var result := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var corners := PackedVector3Array()
		if indices.is_empty():
			corners = vertices
		else:
			for index in indices:
				corners.append(vertices[index])
		var count := corners.size() - corners.size() % 3
		var face_normals := PackedVector3Array()
		face_normals.resize(count / 3)
		var by_point := {}
		for f in count / 3:
			var a := corners[f * 3]
			var b := corners[f * 3 + 1]
			var c := corners[f * 3 + 2]
			var n := (c - a).cross(b - a)
			face_normals[f] = n
			for p in [a, b, c]:
				var key := Vector3i(roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0))
				if not by_point.has(key):
					by_point[key] = []
				by_point[key].append(f)
		var normals := PackedVector3Array()
		normals.resize(count)
		for f in count / 3:
			var own := face_normals[f].normalized()
			for k in 3:
				var p := corners[f * 3 + k]
				var key := Vector3i(roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0))
				var sum := Vector3.ZERO
				for other: int in by_point[key]:
					var n := face_normals[other]
					if n.normalized().dot(own) > crease:
						sum += n
				normals[f * 3 + k] = sum.normalized() if sum.length_squared() > 0.0 else own
		# UV2 for the grime mask: along the car, and down from the roof.
		var grime := PackedVector2Array()
		grime.resize(count)
		for i in count:
			var p := corners[i]
			grime[i] = Vector2(p.z * 0.22 + 0.5 + p.x * 0.05, clampf(1.0 - (p.y + lift - 0.25) / 1.3, 0.0, 1.0))
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = corners.slice(0, count)
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_TEX_UV2] = grime
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		result.surface_set_material(surface, mesh.surface_get_material(surface))
	return result
