extends Node

@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var day_length_seconds: float = 420.0
@export_range(0.0, 1.0, 0.001) var time_of_day: float = 0.5
@export var moonlight_energy: float = 0.045
@export var midday_energy: float = 3.55
@export var dawn_dusk_energy: float = 1.75
@export var fill_light_energy: float = 0.68
@export var lighting_update_interval: float = 0.1
@export var enable_clouds: bool = false
@export var exposure := 1.0

var environment: Environment
var fill_light: DirectionalLight3D
var sky_dome: MeshInstance3D
var sky_dome_material: ShaderMaterial
var cloud_layer: MeshInstance3D
var cloud_material: ShaderMaterial
var cloud_offset: Vector2 = Vector2.ZERO
var lighting_update_timer: float = 0.0
var shadow_distance: float = 220.0
var sun_shadow_enabled: bool = true


func _ready() -> void:
	if world_environment:
		environment = world_environment.environment
		_setup_environment_quality()
		_setup_fill_light()
		_setup_sky_dome()
		if enable_clouds:
			_setup_cloud_layer()

	if GameSettings and not GameSettings.settings_changed.is_connected(_apply_graphics_quality):
		GameSettings.settings_changed.connect(_apply_graphics_quality)
	_apply_graphics_quality()
	_update_world_lighting()


func _process(delta: float) -> void:
	if day_length_seconds <= 0.0:
		_update_sky_dome_position()
		return

	time_of_day = wrapf(time_of_day + delta / day_length_seconds, 0.0, 1.0)
	lighting_update_timer -= delta
	if lighting_update_timer <= 0.0:
		lighting_update_timer = lighting_update_interval
		_update_world_lighting()

	if cloud_layer:
		cloud_offset += Vector2(0.0025, 0.0008) * delta
	_update_sky_dome_position()
	if cloud_layer:
		_update_cloud_layer_position()


func _setup_environment_quality() -> void:
	if environment == null:
		return

	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color(0.86, 0.92, 1.0, 1.0)
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = exposure
	environment.tonemap_white = 7.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.04
	environment.fog_enabled = true
	environment.fog_density = 0.00018
	environment.fog_sky_affect = 0.08
	environment.fog_light_energy = 0.05
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.12, 0.28, 0.58, 1.0)


func _apply_graphics_quality() -> void:
	if sun:
		match GameSettings.shadow_quality:
			0:
				sun_shadow_enabled = false
				shadow_distance = 0.0
			1:
				sun_shadow_enabled = true
				shadow_distance = 120.0
			2:
				sun_shadow_enabled = true
				shadow_distance = 220.0
			_:
				sun_shadow_enabled = true
				shadow_distance = 360.0

		sun.shadow_enabled = sun_shadow_enabled
		sun.directional_shadow_max_distance = shadow_distance
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if GameSettings.shadow_quality >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.set("shadow_opacity", 0.86)
		sun.set("directional_shadow_fade_start", 0.72)
		sun.set("shadow_bias", 0.018)
		sun.set("shadow_normal_bias", 0.8)
		# Match the project's hard shadow filter and skip the screen-space penumbra.
		sun.light_angular_distance = 0.0

	if environment:
		environment.set("ssao_enabled", GameSettings.lighting_quality >= 2)
		environment.set("ssao_radius", 1.8)
		environment.set("ssao_intensity", 0.55)
		environment.set("ssao_power", 0.85)
		environment.ssao_detail = 0.25
		environment.glow_enabled = GameSettings.lighting_quality >= 1
		environment.fog_enabled = GameSettings.lighting_quality >= 1


func _setup_fill_light() -> void:
	fill_light = DirectionalLight3D.new()
	fill_light.name = "SkyFillLight"
	fill_light.light_color = Color(0.66, 0.76, 1.0, 1.0)
	fill_light.light_energy = fill_light_energy
	fill_light.shadow_enabled = false
	fill_light.rotation_degrees = Vector3(-50.0, 145.0, 0.0)
	add_child(fill_light)


func _setup_sky_dome() -> void:
	sky_dome = MeshInstance3D.new()
	sky_dome.name = "ShaderSkyDome"
	var mesh := SphereMesh.new()
	mesh.radius = 420.0
	mesh.height = 840.0
	mesh.radial_segments = 64
	mesh.rings = 24
	sky_dome.mesh = mesh
	sky_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_dome.extra_cull_margin = 100000.0

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;

uniform float daylight = 1.0;
uniform float sun_height = 1.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, 1.0, 0.0);

varying vec3 world_dir;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	world_dir = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
}

void fragment() {
	vec3 dir = normalize(world_dir);
	float y = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	float horizon = pow(1.0 - y, 3.0);
	float zenith = pow(y, 0.72);
	float night = 1.0 - daylight;
	vec3 day_top = vec3(0.05, 0.36, 0.92);
	vec3 day_horizon = vec3(0.82, 0.94, 1.0);
	vec3 dusk_top = vec3(0.10, 0.10, 0.24);
	vec3 dusk_horizon = vec3(1.0, 0.56, 0.22);
	vec3 night_top = vec3(0.015, 0.022, 0.060);
	vec3 night_horizon = vec3(0.08, 0.10, 0.18);

	float sunset = smoothstep(-0.15, 0.2, 1.0 - abs(sun_height));
	vec3 top = mix(night_top, day_top, daylight);
	vec3 horizon_color = mix(night_horizon, day_horizon, daylight);
	horizon_color = mix(horizon_color, dusk_horizon, sunset * daylight * 0.75);
	top = mix(top, dusk_top, sunset * daylight * 0.28);

	vec3 color = mix(horizon_color, top, zenith);

	float sun_amount = max(dot(dir, normalize(sun_direction)), 0.0);
	float sun_disk = smoothstep(0.99935, 0.99988, sun_amount) * daylight;
	float sun_glow = pow(sun_amount, 120.0) * daylight;
	color += vec3(1.0, 0.78, 0.38) * sun_glow * 0.85;
	color += vec3(1.0, 0.94, 0.66) * sun_disk * 6.5;

	float moon_amount = max(dot(dir, normalize(moon_direction)), 0.0);
	float moon_disk = smoothstep(0.9989, 0.99972, moon_amount) * night;
	float moon_glow = pow(moon_amount, 180.0) * night;
	color += vec3(0.44, 0.56, 0.86) * moon_glow * 0.32;
	color += vec3(0.82, 0.88, 1.0) * moon_disk * 2.8;

	color += vec3(0.68, 0.84, 1.0) * horizon * daylight * 0.20;
	color += vec3(1.0, 0.44, 0.16) * horizon * sunset * daylight * 0.34;

	float star_noise = hash(floor(dir.xz * 1050.0 + dir.y * 240.0));
	float stars = step(0.9965, star_noise) * smoothstep(0.16, 0.88, y) * night;
	float bright_stars = step(0.9992, star_noise) * smoothstep(0.22, 0.9, y) * night;
	color += vec3(0.78, 0.86, 1.0) * stars * 0.65;
	color += vec3(1.0, 0.96, 0.82) * bright_stars * 1.4;
	ALBEDO = color;
}
"""
	sky_dome_material = ShaderMaterial.new()
	sky_dome_material.shader = shader
	sky_dome.material_override = sky_dome_material
	add_child(sky_dome)
	_update_sky_dome_position()


func _setup_cloud_layer() -> void:
	cloud_layer = MeshInstance3D.new()
	cloud_layer.name = "ProceduralCloudLayer"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(900.0, 900.0)
	cloud_layer.mesh = mesh
	cloud_layer.rotation_degrees.x = -90.0
	cloud_layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec2 cloud_offset = vec2(0.0);
uniform float daylight = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 5; i++) {
		value += noise(p) * amplitude;
		p *= 2.02;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 6.5 + cloud_offset;
	float n = fbm(p) * 0.75 + fbm(p * 2.8 + 13.0) * 0.25;
	float alpha = smoothstep(0.55, 0.78, n) * 0.58 * daylight;
	vec3 cloud_color = mix(vec3(0.72, 0.74, 0.78), vec3(1.0), daylight);
	ALBEDO = cloud_color;
	ALPHA = alpha;
}
"""
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = shader
	cloud_layer.material_override = cloud_material
	add_child(cloud_layer)
	_update_cloud_layer_position()


func _update_sky_dome_position() -> void:
	if sky_dome == null:
		return

	var camera := get_viewport().get_camera_3d()
	if camera:
		sky_dome.global_position = camera.global_position


func _update_cloud_layer_position() -> void:
	if cloud_layer == null:
		return

	var camera := get_viewport().get_camera_3d()
	var center := Vector3.ZERO
	if camera:
		center = camera.global_position
	cloud_layer.global_position = Vector3(center.x, center.y + 120.0, center.z)


func _update_world_lighting() -> void:
	var sun_height := sin((time_of_day - 0.25) * TAU)
	var daylight := smoothstep(-0.18, 0.16, sun_height)
	var warm_edge := 1.0 - absf(sun_height)
	warm_edge = clampf(warm_edge * 1.45, 0.0, 1.0)

	if sun:
		var sun_elevation: float = clampf(sun_height, 0.16, 0.95)
		var light_direction := Vector3(-0.45, -sun_elevation, -0.30).normalized()
		if sun_height < -0.05:
			light_direction = Vector3(0.35, -0.28, 0.25).normalized()
		sun.look_at(sun.global_position + light_direction, Vector3.UP)
		sun.light_energy = lerpf(moonlight_energy, midday_energy, daylight)
		sun.shadow_enabled = sun_shadow_enabled
		sun.directional_shadow_max_distance = shadow_distance
		if warm_edge > 0.1 and daylight > 0.05:
			sun.light_energy = lerpf(sun.light_energy, dawn_dusk_energy, warm_edge * 0.55)
		sun.light_negative = false
		sun.light_color = Color(0.42, 0.50, 0.82, 1.0).lerp(Color(1.0, 0.95, 0.78, 1.0), daylight)
		sun.light_color = sun.light_color.lerp(Color(1.0, 0.62, 0.26, 1.0), warm_edge * daylight * 0.52)

	if fill_light:
		fill_light.light_energy = lerpf(0.06, fill_light_energy, daylight)
		fill_light.light_color = Color(0.46, 0.56, 0.90, 1.0).lerp(Color(0.74, 0.82, 1.0, 1.0), daylight)

	if environment:
		var lighting_boost: float = [0.9, 1.0, 1.14][GameSettings.lighting_quality]
		environment.ambient_light_energy = lerpf(0.045, 0.98 * lighting_boost, daylight)
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		environment.fog_density = lerpf(0.000015, 0.00022, daylight)
		environment.fog_light_energy = lerpf(0.01, 0.10, daylight)
		environment.fog_light_color = Color(0.08, 0.10, 0.16, 1.0).lerp(Color(0.88, 0.90, 0.94, 1.0), daylight)
		environment.background_color = Color(0.003, 0.006, 0.018, 1.0).lerp(Color(0.12, 0.28, 0.58, 1.0), daylight)
		environment.background_energy_multiplier = lerpf(0.18, 1.65 * lighting_boost, daylight)

	if sky_dome_material:
		var sun_direction := Vector3(0.0, 1.0, 0.0)
		if sun:
			# A directional light points along -Z; the visible source is opposite it.
			sun_direction = sun.global_transform.basis.z.normalized()
		sky_dome_material.set_shader_parameter("daylight", daylight)
		sky_dome_material.set_shader_parameter("sun_height", sun_height)
		sky_dome_material.set_shader_parameter("sun_direction", sun_direction)
		sky_dome_material.set_shader_parameter("moon_direction", sun_direction)

	if cloud_material:
		cloud_material.set_shader_parameter("daylight", clampf(daylight + 0.18, 0.0, 1.0))
		cloud_material.set_shader_parameter("cloud_offset", cloud_offset)
