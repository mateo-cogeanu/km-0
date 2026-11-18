@tool
extends RefCounted
## The materials of the small props and engine-bay parts
## (Sources/make_road_props.py), by the names the models use. They are saved as
## files in assets/desert/props/materials/, and each prop's .glb import points
## its materials at them, so every copy of a part (including the ones the car
## swaps in) looks the same. Run save_all() from tools/player_check/prop_materials_save.gd
## after changing anything here.

const Desert := preload("res://scripts/desert_models.gd")
const FOLDER := "res://assets/desert/props/materials/"
const NOISE := FOLDER + "noise.tres"
const SHADER := preload("res://assets/desert/props/prop_surface.gdshader")

## name: [colour, settings for the weathered shader]
const WEATHERED := {
	"Can paint": [Color(0.5, 0.11, 0.08), {"metallic_base": 0.25, "roughness_base": 0.55, "peel": 0.22, "under_color": Color(0.36, 0.36, 0.34), "rust": 0.15, "bleach": 0.35, "streaks": 0.2, "dust": 0.0}],
	"Tin plate": [Color(0.66, 0.66, 0.64), {"metallic_base": 0.75, "roughness_base": 0.35, "rust": 0.12, "bleach": 0.0, "streaks": 0.0, "dust": 0.0}],
	"Label beans": [Color(0.62, 0.26, 0.15), {"bleach": 0.3, "streaks": 0.15, "dust": 0.0, "roughness_base": 0.8}],
	"Label soup": [Color(0.75, 0.6, 0.22), {"bleach": 0.3, "streaks": 0.15, "dust": 0.0, "roughness_base": 0.8}],
	"Soda paint": [Color(0.15, 0.36, 0.6), {"metallic_base": 0.4, "roughness_base": 0.4, "bleach": 0.35, "dust": 0.0, "streaks": 0.0}],
	"Paper": [Color(0.8, 0.76, 0.64), {"bleach": 0.15, "streaks": 0.25, "dust": 0.0, "roughness_base": 0.95}],
	"Cardboard": [Color(0.72, 0.48, 0.18), {"bleach": 0.35, "streaks": 0.2, "dust": 0.0, "roughness_base": 0.95}],
	"Wrapper": [Color(0.35, 0.15, 0.1), {"roughness_base": 0.5, "bleach": 0.2, "dust": 0.0, "streaks": 0.0}],
	"Foil": [Color(0.78, 0.76, 0.7), {"metallic_base": 0.9, "roughness_base": 0.3, "dust": 0.0, "bleach": 0.0, "streaks": 0.0}],
	"Apple": [Color(0.52, 0.11, 0.09), {"roughness_base": 0.45, "bleach": 0.0, "dust": 0.0, "streaks": 0.0}],
	"Stem": [Color(0.3, 0.22, 0.12), {"bleach": 0.0, "dust": 0.0, "streaks": 0.0}],
	"Leaf": [Color(0.25, 0.35, 0.15), {"bleach": 0.2, "dust": 0.0, "streaks": 0.0}],
	"Pouch": [Color(0.22, 0.3, 0.2), {"metallic_base": 0.25, "roughness_base": 0.45, "bleach": 0.2, "dust": 0.0, "streaks": 0.0}],
	"Jerky": [Color(0.35, 0.16, 0.08), {"bleach": 0.0, "dust": 0.0, "streaks": 0.0}],
	"Cap blue": [Color(0.15, 0.32, 0.6), {"roughness_base": 0.5, "bleach": 0.3, "dust": 0.0, "streaks": 0.0}],
	"Flare red": [Color(0.62, 0.12, 0.08), {"roughness_base": 0.7, "bleach": 0.35, "streaks": 0.15, "dust": 0.0}],
	"Flare cap": [Color(0.86, 0.84, 0.78), {"roughness_base": 0.6, "bleach": 0.1, "dust": 0.0, "streaks": 0.0}],
	"Flare band": [Color(0.85, 0.72, 0.2), {"bleach": 0.3, "dust": 0.0, "streaks": 0.0}],
	"Battery card": [Color(0.72, 0.2, 0.15), {"bleach": 0.35, "dust": 0.0, "streaks": 0.1}],
	"Cell": [Color(0.1, 0.1, 0.1), {"metallic_base": 0.4, "roughness_base": 0.35, "dust": 0.0, "bleach": 0.0, "streaks": 0.0}],
	"Cell top": [Color(0.75, 0.62, 0.3), {"metallic_base": 0.6, "roughness_base": 0.35, "dust": 0.0, "bleach": 0.0, "streaks": 0.0}],
	"Cooler white": [Color(0.8, 0.78, 0.72), {"roughness_base": 0.6, "bleach": 0.3, "streaks": 0.45, "dust": 0.35}],
	"Cooler blue": [Color(0.18, 0.35, 0.55), {"roughness_base": 0.6, "bleach": 0.5, "streaks": 0.3, "dust": 0.25}],
	"Toolbox red": [Color(0.6, 0.15, 0.12), {"metallic_base": 0.35, "roughness_base": 0.45, "peel": 0.22, "under_color": Color(0.4, 0.4, 0.38), "rust": 0.3, "bleach": 0.3, "streaks": 0.25, "dust": 0.2}],
	"Cabinet steel": [Color(0.42, 0.45, 0.41), {"metallic_base": 0.3, "roughness_base": 0.55, "peel": 0.35, "under_color": Color(0.5, 0.5, 0.48), "rust": 0.35, "bleach": 0.3, "streaks": 0.4, "dust": 0.3}],
	"Brass": [Color(0.6, 0.48, 0.25), {"metallic_base": 0.8, "roughness_base": 0.4, "dust": 0.0, "bleach": 0.0, "streaks": 0.0}],
	"Ink": [Color(0.1, 0.09, 0.09), {"bleach": 0.0, "dust": 0.0, "streaks": 0.0, "roughness_base": 0.7}],
	"Notebook cover": [Color(0.22, 0.28, 0.21), {"roughness_base": 0.8, "bleach": 0.3, "streaks": 0.2, "dust": 0.0}],
	"Elastic": [Color(0.08, 0.08, 0.08), {"dust": 0.0, "bleach": 0.0, "streaks": 0.0}],
	"Photo": [Color(0.14, 0.13, 0.12), {"roughness_base": 0.3, "dust": 0.0, "bleach": 0.0, "streaks": 0.0}],
	"Postcard picture": [Color(0.45, 0.55, 0.62), {"bleach": 0.35, "dust": 0.0, "streaks": 0.0}],
	"Clipboard": [Color(0.42, 0.32, 0.2), {"wood_grain": 0.6, "bleach": 0.2, "dust": 0.0, "streaks": 0.1}],
	"Rubber": [Color(0.045, 0.045, 0.045), {"roughness_base": 0.88, "bleach": 0.2, "dust": 0.15, "streaks": 0.0}],
	"Cast iron": [Color(0.25, 0.24, 0.23), {"metallic_base": 0.45, "roughness_base": 0.65, "rust": 0.18, "bleach": 0.0, "streaks": 0.15, "dust": 0.05}],
	"Cast aluminum": [Color(0.58, 0.58, 0.56), {"metallic_base": 0.6, "roughness_base": 0.55, "bleach": 0.0, "streaks": 0.2, "dust": 0.05}],
	"Machined steel": [Color(0.55, 0.56, 0.56), {"metallic_base": 0.8, "roughness_base": 0.35, "rust": 0.15, "bleach": 0.0, "streaks": 0.1, "dust": 0.0}],
	"Molded graphite": [Color(0.065, 0.065, 0.07), {"roughness_base": 0.6, "bleach": 0.25, "streaks": 0.2, "dust": 0.1}],
	"Heat stained steel": [Color(0.36, 0.3, 0.27), {"metallic_base": 0.6, "roughness_base": 0.45, "rust": 0.22, "bleach": 0.0, "streaks": 0.0, "dust": 0.0}],
	"Slate blue enamel": [Color(0.2, 0.28, 0.38), {"metallic_base": 0.2, "roughness_base": 0.45, "peel": 0.2, "under_color": Color(0.5, 0.5, 0.48), "bleach": 0.1, "streaks": 0.2, "dust": 0.0}],
	"Crimson enamel": [Color(0.5, 0.08, 0.06), {"metallic_base": 0.2, "roughness_base": 0.45, "peel": 0.2, "under_color": Color(0.5, 0.5, 0.48), "bleach": 0.1, "streaks": 0.2, "dust": 0.0}],
	"Ivory decal": [Color(0.85, 0.82, 0.72), {"bleach": 0.2, "dust": 0.0, "streaks": 0.1}],
	"High voltage orange": [Color(0.85, 0.35, 0.05), {"roughness_base": 0.55, "bleach": 0.15, "dust": 0.0, "streaks": 0.0}],
	"Service yellow": [Color(0.85, 0.7, 0.1), {"roughness_base": 0.5, "bleach": 0.15, "dust": 0.0, "streaks": 0.0}],
	"Coolant green": [Color(0.2, 0.7, 0.3), {"roughness_base": 0.2, "bleach": 0.0, "dust": 0.0, "streaks": 0.0}],
	"Copper": [Color(0.6, 0.35, 0.2), {"metallic_base": 0.8, "roughness_base": 0.4, "dust": 0.0}],
	"Can white": [Color(0.82, 0.81, 0.77), {"metallic_base": 0.3, "roughness_base": 0.4, "rust": 0.12, "bleach": 0.1, "streaks": 0.2, "dust": 0.0}],
	"Spray plastic": [Color(0.8, 0.1, 0.06), {"roughness_base": 0.45, "dust": 0.0, "bleach": 0.0, "streaks": 0.0}],
}
## Clear things: [colour with alpha, roughness].
const CLEAR := {
	"Bottle plastic": [Color(0.78, 0.86, 0.92, 0.32), 0.12],
	"Blister": [Color(0.9, 0.92, 0.95, 0.25), 0.1],
	"Reservoir nylon": [Color(0.86, 0.84, 0.76, 0.5), 0.45],
}


static func make(title: String, noise: Texture2D) -> Material:
	if CLEAR.has(title):
		var clear := StandardMaterial3D.new()
		clear.albedo_color = CLEAR[title][0]
		clear.roughness = CLEAR[title][1]
		clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		clear.cull_mode = BaseMaterial3D.CULL_DISABLED
		clear.resource_name = title
		return clear
	if title == "Dark interior":
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.01, 0.009, 0.008)
		dark.resource_name = title
		return dark
	var entry: Array = WEATHERED.get(title, [Color(0.5, 0.5, 0.5), {}])
	var made := Desert.weathered(entry[0], entry[1])
	made.shader = SHADER
	made.set_shader_parameter("noise_tex", noise)
	made.resource_name = title
	return made


static func file_for(title: String) -> String:
	return FOLDER + title.to_lower().replace(" ", "_") + ".tres"


static func titles() -> Array:
	var all := WEATHERED.keys()
	all.append_array(CLEAR.keys())
	all.append("Dark interior")
	return all


static func save_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	ResourceSaver.save(Desert.noise_texture(), NOISE)
	var noise: Texture2D = load(NOISE)
	for title: String in titles():
		ResourceSaver.save(make(title, noise), file_for(title))
