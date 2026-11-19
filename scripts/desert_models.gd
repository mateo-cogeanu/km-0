extends RefCounted
## The desert road's Blender models (Sources/make_road_*.py, in
## assets/desert/): loads them, swaps in the weathering shader by material
## name, and helps the code-built buildings hand their looks over to them
## while keeping their colliders and gameplay anchors exactly where they were.

const SURFACE := preload("res://assets/desert/weathered_surface.gdshader")
const SHEET := preload("res://assets/desert/weathered_sheet.gdshader")
const FOLIAGE := preload("res://assets/desert/foliage.gdshader")
const LEAF_MASK := preload("res://assets/desert/foliage_leaves.png")
const NEEDLE_MASK := preload("res://assets/desert/foliage_needles.png")
const GRASS_MASK := preload("res://assets/desert/foliage_grass.png")
const SHINGLES := preload("res://assets/salvage/shingles.gdshader")
## Board by board within this distance, the simpler shell beyond it.
const NEAR_DETAIL := 28.0

static var scenes := {}
static var shared := {}
static var noise: NoiseTexture2D


static func noise_texture() -> NoiseTexture2D:
	## The noise every desert shader samples: made here, at load, so nothing
	## needs shipping. 32 soft features across, tiling.
	if noise == null:
		var source := FastNoiseLite.new()
		source.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
		source.frequency = 0.125
		source.fractal_type = FastNoiseLite.FRACTAL_NONE
		source.seed = 1977
		noise = NoiseTexture2D.new()
		noise.width = 256
		noise.height = 256
		noise.seamless = true
		noise.generate_mipmaps = true
		noise.noise = source
	return noise


static func weathered(color: Color, settings := {}, sheet := false) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = SHEET if sheet else SURFACE
	made.set_shader_parameter("noise_tex", noise_texture())
	made.set_shader_parameter("base_color", color)
	for key: String in settings:
		made.set_shader_parameter(key, settings[key])
	return made


static func foliage(color: Color, settings := {}) -> ShaderMaterial:
	## Leaf and needle cards (assets/desert/foliage.gdshader).
	var made := ShaderMaterial.new()
	made.shader = FOLIAGE
	made.set_shader_parameter("mask_tex", [LEAF_MASK, NEEDLE_MASK, GRASS_MASK][settings.get("kind", 0)])
	made.set_shader_parameter("base_color", color)
	for key: String in settings:
		if key != "kind":
			made.set_shader_parameter(key, settings[key])
	return made


static func make_material(title: String) -> Material:
	match title:
		"Corrugated":
			return weathered(Color(0.5, 0.52, 0.5), {"use_tint": 1.0, "metallic_base": 0.3, "roughness_base": 0.62, "rust": 0.4, "peel": 0.0, "bleach": 0.25, "streaks": 0.55}, true)
		"Corrugated far":
			return weathered(Color(0.5, 0.52, 0.5), {"use_tint": 1.0, "metallic_base": 0.3, "roughness_base": 0.62, "rust": 0.4, "bleach": 0.25, "streaks": 0.55, "ribs": 1})
		"Roof":
			return weathered(Color(0.36, 0.35, 0.33), {"metallic_base": 0.4, "roughness_base": 0.6, "rust": 0.55, "bleach": 0.45, "streaks": 0.2}, true)
		"Roof far":
			return weathered(Color(0.36, 0.35, 0.33), {"metallic_base": 0.4, "roughness_base": 0.6, "rust": 0.55, "bleach": 0.45, "ribs": 2})
		"Paint":
			return weathered(Color(0.58, 0.53, 0.46), {"use_tint": 1.0, "peel": 0.55, "under_color": Color(0.55, 0.53, 0.49), "bleach": 0.5, "streaks": 0.45})
		"Block":
			return weathered(Color(0.58, 0.56, 0.51), {"use_tint": 1.0, "peel": 0.6, "under_color": Color(0.5, 0.49, 0.46), "bleach": 0.45, "streaks": 0.5, "blocks": 1.0, "roughness_base": 0.95})
		"Brick":
			return weathered(Color(0.52, 0.29, 0.2), {"bricks": 1.0, "bleach": 0.35, "streaks": 0.4, "roughness_base": 0.92})
		"Concrete":
			return weathered(Color(0.6, 0.57, 0.51), {"bleach": 0.2, "streaks": 0.2, "roughness_base": 0.95, "dust": 0.8})
		"Steel":
			return weathered(Color(0.3, 0.31, 0.3), {"metallic_base": 0.45, "roughness_base": 0.58, "rust": 0.45, "bleach": 0.15, "streaks": 0.1, "dust": 0.2})
		"Rust":
			return weathered(Color(0.36, 0.19, 0.1), {"rust": 0.6, "dust": 0.2, "roughness_base": 0.85, "bleach": 0.1})
		"Wood":
			return weathered(Color(0.4, 0.33, 0.25), {"bleach": 0.4, "wood_grain": 1.0, "streaks": 0.25, "roughness_base": 0.95})
		"Boards":
			return weathered(Color(0.62, 0.6, 0.55), {"use_tint": 1.0, "peel": 0.45, "under_color": Color(0.42, 0.38, 0.32), "bleach": 0.55, "wood_grain": 0.4, "streaks": 0.35})
		"Boards far":
			return weathered(Color(0.7, 0.66, 0.58), {"use_tint": 1.0, "peel": 0.6, "under_color": Color(0.42, 0.38, 0.32), "bleach": 0.55, "streaks": 0.35, "boards": 1.0})
		"Trim":
			return weathered(Color(0.68, 0.65, 0.58), {"peel": 0.4, "under_color": Color(0.44, 0.4, 0.34), "bleach": 0.4, "wood_grain": 0.3})
		"Sign":
			return weathered(Color(0.82, 0.78, 0.68), {"peel": 0.35, "bleach": 0.6, "streaks": 0.5, "dust": 0.1})
		"Red paint":
			return weathered(Color(0.6, 0.14, 0.09), {"peel": 0.4, "bleach": 0.55, "rust": 0.2})
		"Yellow paint":
			return weathered(Color(0.8, 0.62, 0.22), {"peel": 0.45, "bleach": 0.5, "rust": 0.25})
		"Plaster":
			return weathered(Color(0.5, 0.45, 0.39), {"peel": 0.12, "under_color": Color(0.42, 0.38, 0.33), "bleach": 0.0, "streaks": 0.35, "dust": 0.25})
		"Floor":
			return weathered(Color(0.36, 0.29, 0.22), {"wood_grain": 1.0, "bleach": 0.0, "streaks": 0.0, "dust": 0.0, "roughness_base": 0.8})
		"Fabric":
			return weathered(Color(0.32, 0.29, 0.24), {"bleach": 0.3, "roughness_base": 1.0, "dust": 0.4})
		"Enamel":
			return weathered(Color(0.74, 0.72, 0.66), {"rust": 0.3, "roughness_base": 0.4, "bleach": 0.0})
		"Tin":
			return weathered(Color(0.6, 0.6, 0.58), {"metallic_base": 0.7, "roughness_base": 0.4, "rust": 0.3})
		"Stone":
			return weathered(Color(0.38, 0.35, 0.31), {"bleach": 0.2, "roughness_base": 0.95})
		"Rock":
			# Sun-baked sandstone: warm red-brown, desert varnish running dark
			# down the faces, the foot dusted with the ground's sand.
			return weathered(Color(0.34, 0.2, 0.13), {"bleach": 0.05, "roughness_base": 0.95, "dust": 0.1, "streaks": 0.8})
		"Bark":
			return weathered(Color(0.24, 0.19, 0.15), {"bleach": 0.2, "wood_grain": 1.0, "roughness_base": 1.0, "streaks": 0.2, "dust": 0.3})
		"Scrub":
			return foliage(Color(0.4, 0.41, 0.25), {"dry": 0.15, "crown_center": Vector3(0, 0.55, 0), "crown_size": Vector3(0.6, 0.45, 0.6), "sway": 0.015})
		"Pine bark":
			return weathered(Color(0.3, 0.19, 0.13), {"bleach": 0.15, "wood_grain": 1.0, "roughness_base": 1.0, "streaks": 0.1, "dust": 0.2})
		"Dead wood":
			return weathered(Color(0.3, 0.27, 0.23), {"bleach": 0.25, "wood_grain": 1.0, "roughness_base": 1.0, "streaks": 0.3})
		"Cactus":
			return weathered(Color(0.32, 0.43, 0.27), {"bleach": 0.35, "roughness_base": 0.8, "dust": 0.6})
		"Grass":
			return weathered(Color(0.62, 0.56, 0.36), {"bleach": 0.35, "roughness_base": 1.0, "dust": 0.0, "streaks": 0.0}, true)
		"Dry grass":
			return foliage(Color(0.36, 0.35, 0.2), {"kind": 2, "dry": 0.6, "dry_color": Color(0.5, 0.44, 0.29), "crown_center": Vector3(0, 0.05, 0), "crown_size": Vector3(0.45, 0.6, 0.45), "sway": 0.06})
		"Green grass":
			return foliage(Color(0.3, 0.36, 0.16), {"kind": 2, "dry": 0.3, "dry_color": Color(0.58, 0.52, 0.32), "crown_center": Vector3(0, 0.05, 0), "crown_size": Vector3(0.45, 0.6, 0.45), "sway": 0.06})
		"Green paint":
			return weathered(Color(0.17, 0.33, 0.23), {"peel": 0.3, "under_color": Color(0.5, 0.5, 0.48), "bleach": 0.55, "streaks": 0.3, "dust": 0.2})
		"Leaves":
			return foliage(Color(0.33, 0.4, 0.22), {"dry": 0.08, "crown_center": Vector3(0.2, 3.1, 0.1), "crown_size": Vector3(2.6, 1.1, 2.6)})
		"Needles":
			return foliage(Color(0.2, 0.3, 0.21), {"kind": 1, "dry": 0.06, "dry_color": Color(0.42, 0.36, 0.22), "crown_center": Vector3(0, 3.4, 0), "crown_size": Vector3(1.7, 2.6, 1.7), "sway": 0.03})
		"Paper":
			return weathered(Color(0.76, 0.71, 0.6), {"bleach": 0.3, "dust": 0.0})
		"Shutter":
			return weathered(Color(0.5, 0.52, 0.5), {"use_tint": 0.6, "metallic_base": 0.25, "roughness_base": 0.65, "rust": 0.5, "bleach": 0.3, "streaks": 0.4, "ribs": 2, "peel": 0.3, "under_color": Color(0.5, 0.5, 0.48)})
		"Door":
			return weathered(Color(0.62, 0.58, 0.5), {"use_tint": 1.0, "metallic_base": 0.3, "roughness_base": 0.6, "rust": 0.4, "bleach": 0.4, "peel": 0.5, "under_color": Color(0.42, 0.4, 0.37), "streaks": 0.4})
		"Shingles":
			var shingles := ShaderMaterial.new()
			shingles.shader = SHINGLES
			return shingles
		"Glass":
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.1, 0.11, 0.1, 0.45)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.roughness = 0.12
			glass.metallic = 0.3
			glass.metallic_specular = 0.9
			return glass
		"Dark interior":
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.01, 0.009, 0.008)
			dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			return dark
		"Rubber":
			return weathered(Color(0.05, 0.05, 0.045), {"bleach": 0.15, "roughness_base": 0.9, "dust": 0.15})
		"Lamp":
			var lamp := StandardMaterial3D.new()
			lamp.albedo_color = Color(0.9, 0.86, 0.76)
			return lamp
	return weathered(Color(0.5, 0.5, 0.5))


static func material(title: String, own: Dictionary = shared) -> Material:
	if not own.has(title):
		own[title] = make_material(title)
	return own[title]


static func mesh_of(title: String) -> Mesh:
	## The first mesh in a model, with its materials swapped in: for MultiMesh.
	var key := "mesh:" + title
	if not shared.has(key):
		var node := model(title)
		var found := node.find_children("*", "MeshInstance3D", true, false)
		var source: MeshInstance3D = found[0]
		var mesh := source.mesh.duplicate() as Mesh
		for surface in mesh.get_surface_count():
			mesh.surface_set_material(surface, source.get_surface_override_material(surface))
		shared[key] = mesh
		node.free()
	return shared[key]


static func model(title: String, far := false, own: Dictionary = shared) -> Node3D:
	if not scenes.has(title):
		scenes[title] = load("res://assets/desert/%s.glb" % title)
	var node: Node3D = (scenes[title] as PackedScene).instantiate()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			var title_name := source.resource_name.get_slice(".", 0) if source else ""
			if far and title_name in ["Corrugated", "Roof", "Boards"]:
				title_name += " far"
			mesh.set_surface_override_material(surface, material(title_name, own))
	return node


static func dress(parent: Node3D, title: String, has_far := true, tint := Color(1, 1, 1), own: Dictionary = shared) -> Node3D:
	## The detailed model up close and, if there is one, the simple shell past
	## NEAR_DETAIL. Returns the holder node.
	var holder := Node3D.new()
	holder.name = "Dressing"
	parent.add_child(holder)
	var near := model(title, false, own)
	holder.add_child(near)
	var far: Node3D = null
	if has_far:
		far = model(title + "_far", true, own)
		holder.add_child(far)
	for mesh: GeometryInstance3D in near.find_children("*", "GeometryInstance3D", true, false):
		mesh.set_instance_shader_parameter("tint", tint)
		if has_far:
			mesh.visibility_range_end = NEAR_DETAIL
			mesh.visibility_range_end_margin = 4.0
			mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if far:
		for mesh: GeometryInstance3D in far.find_children("*", "GeometryInstance3D", true, false):
			mesh.set_instance_shader_parameter("tint", tint)
			mesh.visibility_range_begin = NEAR_DETAIL
			mesh.visibility_range_begin_margin = 4.0
	return holder


static func hide_boxes(root: Node, names: Array, recursive := false) -> void:
	## Hide the code-built pieces the model now draws. Their colliders stay.
	for child in (root.find_children("*", "MeshInstance3D", true, false) if recursive else root.get_children()):
		if child is MeshInstance3D and piece(child) in names:
			child.visible = false
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func base_name(title: String) -> String:
	## "SideWall" and "SideWall2" are both "SideWall".
	return title.trim_prefix("@").get_slice("@", 0).rstrip("0123456789")


static func piece(node: Node) -> String:
	## What a code-built box was made as (prop_shapes.gd tags them).
	return node.get_meta("piece", base_name(node.name))


static func occluder(parent: Node3D, size: Vector3, at: Vector3) -> OccluderInstance3D:
	var occ := OccluderInstance3D.new()
	var block := BoxOccluder3D.new()
	block.size = size
	occ.occluder = block
	parent.add_child(occ)
	occ.position = at
	return occ


static func solid(parent: Node3D, size: Vector3, at: Vector3, yaw := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("Road")
	parent.add_child(body)
	body.position = at
	body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body


static func restyle(root: Node, title: String, recursive := true) -> void:
	## Give code-built pieces (shutter slats, rails) the weathered look.
	var finish := material(title)
	for child in (root.find_children("*", "MeshInstance3D", true, false) if recursive else root.get_children()):
		if child is MeshInstance3D:
			child.material_override = finish
