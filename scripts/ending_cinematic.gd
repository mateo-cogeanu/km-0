extends Control
## The scenes behind the three end cards. Each is built in a world of its own,
## plays a few shots, then holds on the last one while the card's words come in.
##   "replaced"  Night. You wait on the porch of the house at the end of the
##               road while a new pair of headlights comes toward it. The
##               kettle's on.
##   "house"     Night. Your car at the end of the road with the door open, the
##               radio still murmuring, and the front door open on the dark.
##   "free"      Sunrise. Your car crossing open desert toward the sun.
## Click to skip to the last shot. The game underneath is paused meanwhile.

const Shapes := preload("res://scripts/prop_shapes.gd")
const Terrain := preload("res://scripts/roadside_terrain.gd")
const CarModel := preload("res://scripts/compact_car_model.gd")
const PlayerBody := preload("res://scripts/player_body.gd")
const RoadEndHouse := preload("res://scripts/road_end_house.gd")
const RoadRadio := preload("res://scripts/road_radio.gd")
const Style := preload("res://scripts/menu_style.gd")
const ASPHALT := preload("res://assets/buildings/asphalt.gdshader")
const DREAD := preload("res://assets/audio/ending/cine_dread.wav")
const DAWN := preload("res://assets/audio/ending/cine_dawn.wav")
const CRICKETS := preload("res://assets/audio/ending/crickets.wav")
const KETTLE := preload("res://assets/audio/ending/kettle.wav")
const WIND := preload("res://assets/audio/road/wind_exposed.wav")
const ENGINE := preload("res://assets/audio/engines/v8_loop.wav")
const GRAVEL := preload("res://assets/audio/road/gravel.wav")
const BROADCAST := preload("res://assets/audio/radio/you.wav")
const FLICKER := preload("res://assets/audio/ending/flicker.wav")
const DOOR_LATCH := preload("res://assets/audio/vehicle/door_latch.wav")
const HouseFire := preload("res://scripts/house_fire.gd")
const HELLO := preload("res://assets/audio/ending/hello.wav")
const MICK_COUGH := preload("res://assets/audio/radio/mick_cough.wav")
const CRACK := preload("res://assets/audio/ending/crack.wav")
const TORCH_CLICK := preload("res://assets/audio/player/flashlight_click.wav")

## Where the new car comes from, how fast, and where it stops (replaced).
const CRUISE := 17.0
const BRAKE := 3.52
const ARRIVE_Z := 19.0
const START_Z := 430.0

var kind := "replaced"
var container: SubViewportContainer
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var env: Environment
var sky_material: ShaderMaterial
var fade: ColorRect
var bars: Array[ColorRect] = []
var scrim: TextureRect
var words: VBoxContainer
var time := 0.0
var last_shot := -1
## [start time, Callable(seconds into the shot)]
var shots: Array = []
var text_at := 20.0
var cued := false
var car: Node3D
var car_lights: Array[SpotLight3D] = []
var wheels: Array[Node3D] = []
var car_door: Node3D
var dome: OmniLight3D
var car_z := 0.0
var car_speed := 0.0
var rolled := 0.0
var figure: Node3D
var glints: Array[MeshInstance3D] = []
var house: Node3D
var porch_lamp: OmniLight3D
var porch_glass: StandardMaterial3D
var eyes: Array[MeshInstance3D] = []
var dust: GPUParticles3D
var flares: Array[MeshInstance3D] = []
var flare_strength := 1.0
var players := {}
var flicker_done := {}
var smooth_frames := 0
var waited := 0
var wave_target: Variant = null
var head_twist_now := 0.0
var torch: SpotLight3D
var head_lens: StandardMaterial3D


static func create(which: String) -> Control:
	var cinematic: Control = load("res://scripts/ending_cinematic.gd").new()
	cinematic.kind = which
	return cinematic


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	container = SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = 2 if GameSettings.low_end else 1
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.audio_listener_enable_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED if GameSettings.low_end else Viewport.MSAA_4X
	viewport.positional_shadow_atlas_size = 4096
	viewport.positional_shadow_atlas_quad_0 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1
	viewport.positional_shadow_atlas_quad_1 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
	viewport.positional_shadow_atlas_quad_2 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
	viewport.positional_shadow_atlas_quad_3 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16
	container.add_child(viewport)
	stage = Node3D.new()
	stage.name = "Stage"
	viewport.add_child(stage)
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.04
	camera.far = 2000.0
	stage.add_child(camera)
	camera.make_current()
	_build_overlay()
	match kind:
		"free":
			_build_free()
		"house":
			_build_house_ending()
		"burn":
			_build_burn()
		_:
			_build_replaced()
	# The game behind stops drawing and stops making sound.
	get_tree().root.disable_3d = true
	get_tree().paused = true
	AudioServer.set_bus_mute(0, false)
	_update(0.0, 0.0)


func _exit_tree() -> void:
	get_tree().root.disable_3d = false


func _process(delta: float) -> void:
	_layout()
	if not _warmed_up():
		_update(0.0, 0.0)
		fade.color.a = 1.0
		return
	time += delta
	_update(time, delta)


func _warmed_up() -> bool:
	## A new world shows nothing for its first moments while the renderer gets
	## ready. Hold the clock (behind the fade) until the picture is really there.
	if smooth_frames > 0:
		return true
	waited += 1
	if waited > 600:
		smooth_frames = 1
	elif waited % 6 == 0:
		var picture := viewport.get_texture().get_image()
		if picture:
			picture.resize(16, 9, Image.INTERPOLATE_BILINEAR)
			var total := 0.0
			for y in 9:
				for x in 16:
					total += picture.get_pixel(x, y).get_luminance()
			if total / 144.0 > 0.004:
				smooth_frames = 1
	return smooth_frames > 0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not cued:
		skip()


func skip() -> void:
	## Straight to the last shot and the words.
	if time < text_at:
		var jump := text_at - time
		time = text_at
		for player: AudioStreamPlayer in players.values():
			if player.playing and player.stream == KETTLE:
				player.stop()
		_update(time, jump)


func set_card(lines: Array, button: Control) -> void:
	## Lines are [text, size]; they and the button fade in on the last shot.
	for line: Array in lines:
		var label := Style.label(line[0], roundi(line[1] * GameSettings.ui_scale))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.add_theme_color_override("font_color", Color("#efe7d8"))
		label.add_theme_constant_override("outline_size", roundi(5 * GameSettings.ui_scale))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		words.add_child(label)
	if button:
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if button is Button:
			# Centred, wide enough to hit, and focused so Enter or a pad works.
			(button as Button).alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, 220.0 * GameSettings.ui_scale)
		words.add_child(button)


# The frame ----------------------------------------------------------------------

func _build_overlay() -> void:
	# A soft dark band at the bottom for the words, letterbox bars, and a fade.
	scrim = TextureRect.new()
	var ramp := GradientTexture2D.new()
	ramp.fill_from = Vector2(0, 0)
	ramp.fill_to = Vector2(0, 1)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 0.78))
	ramp.gradient = gradient
	scrim.texture = ramp
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.modulate.a = 0.0
	add_child(scrim)
	scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scrim.anchor_top = 0.5
	scrim.offset_top = 0
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bars.append(bar)
	words = VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_END
	words.add_theme_constant_override("separation", roundi(14 * GameSettings.ui_scale))
	words.modulate.a = 0.0
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(words)
	words.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	words.anchor_top = 0.45
	fade = ColorRect.new()
	fade.color = Color(1, 0.98, 0.94) if kind == "free" else Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _layout() -> void:
	# Bars for a wide 2.2:1 frame, but never less than 7% each.
	var extent := get_viewport_rect().size
	var bar := maxf(extent.y * 0.07, (extent.y - extent.x / 2.2) * 0.5)
	for strip in bars:
		strip.anchor_left = 0.0
		strip.anchor_right = 1.0
		strip.offset_left = 0.0
		strip.offset_right = 0.0
	scrim.anchor_left = 0.0
	scrim.anchor_right = 1.0
	scrim.offset_left = 0.0
	scrim.offset_right = 0.0
	scrim.offset_bottom = 0.0
	words.anchor_left = 0.0
	words.anchor_right = 1.0
	bars[0].offset_top = 0
	bars[0].offset_bottom = bar
	bars[1].offset_top = -bar
	bars[1].offset_bottom = 0
	words.offset_left = 24
	words.offset_right = -24
	words.offset_top = 0
	words.offset_bottom = -maxf(bar * 0.35, 18.0)


func _update(t: float, delta: float) -> void:
	match kind:
		"free":
			_animate_free(t, delta)
		"house":
			_animate_house(t, delta)
		"burn":
			_animate_burn(t, delta)
		_:
			_animate_replaced(t, delta)
	var index := 0
	for i in shots.size():
		if t >= shots[i][0]:
			index = i
	if index != last_shot:
		last_shot = index
	(shots[index][1] as Callable).call(t - shots[index][0])
	for glare in flares:
		var away := camera.global_position.distance_to(glare.global_position)
		# Only from in front of the car.
		var facing := (camera.global_position - glare.global_position).normalized().dot(-glare.global_basis.z)
		glare.scale = Vector3.ONE * (0.45 + away * 0.011) * clampf(facing * 1.5, 0.0, 1.0) * flare_strength
	fade.color.a = clampf(1.0 - t / 2.6, 0.0, 1.0) if kind != "free" else clampf(1.0 - t / 3.5, 0.0, 1.0)
	if t >= text_at and not cued:
		cued = true
		var show := create_tween().set_parallel()
		show.tween_property(scrim, "modulate:a", 1.0, 2.5)
		show.tween_property(words, "modulate:a", 1.0, 3.0).set_delay(0.8)
		var focus := words.find_child("EndButton", true, false) as Control
		if focus:
			focus.grab_focus.call_deferred()


func _aim(from: Vector3, at: Vector3, roll := 0.0) -> void:
	camera.global_position = from
	camera.look_at(at, Vector3.UP)
	if roll != 0.0:
		camera.rotate_object_local(Vector3.BACK, roll)


func _ease(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


# Shared pieces ------------------------------------------------------------------

func _environment(night: bool) -> void:
	env = Environment.new()
	var sky := Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = _sky_shader()
	sky_material.set_shader_parameter("dawn", 0.0 if night else 1.0)
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0 if night else 0.78
	env.glow_enabled = true
	env.glow_intensity = 0.9 if night else 0.6
	env.glow_bloom = 0.06 if night else 0.04
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT if not night else Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 0.85 if night else 1.08
	if night:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.32, 0.4, 0.62)
		env.ambient_light_energy = 0.16
		env.fog_enabled = true
		env.fog_light_color = Color(0.05, 0.065, 0.11)
		env.fog_density = 0.006
		env.fog_sky_affect = 0.0
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.55
		env.fog_enabled = true
		env.fog_light_color = Color(0.95, 0.72, 0.52)
		env.fog_sun_scatter = 0.35
		env.fog_density = 0.0022
		env.fog_sky_affect = 0.0
	if not GameSettings.low_end:
		env.ssao_enabled = true
		env.ssao_intensity = 1.4
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.009 if night else 0.005
		env.volumetric_fog_albedo = Color(0.7, 0.74, 0.82) if night else Color(1.0, 0.86, 0.7)
		env.volumetric_fog_length = 90.0
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_sky_affect = 0.0
		env.volumetric_fog_ambient_inject = 0.0
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)


func _sky_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type sky;

uniform float dawn = 0.0;
uniform vec3 sun_dir = vec3(0.15, 0.06, -1.0);
uniform vec3 moon_dir = vec3(-0.5, 0.42, -0.75);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		total += vnoise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return total;
}

vec3 night_sky(vec3 d) {
	float h = d.y;
	vec3 col = mix(vec3(0.040, 0.050, 0.085), vec3(0.004, 0.007, 0.022), smoothstep(-0.02, 0.55, h));
	// A last trace of light low in one part of the sky.
	col += vec3(0.05, 0.045, 0.06) * pow(max(0.0, 1.0 - abs(h) * 6.0), 3.0) * (0.5 + 0.5 * dot(d.xz, vec2(-0.6, -0.8)));
	if (h > 0.0) {
		// Stars: round dots in a grid of cells on the sphere, twinkling.
		vec3 cell = floor(d * 260.0);
		float pick = hash(cell);
		vec3 centre = (cell + 0.5 + (vec3(hash(cell + 3.1), hash(cell + 7.7), hash(cell + 1.9)) - 0.5) * 0.7) / 260.0;
		float dist = length(d - normalize(centre)) * 260.0;
		float star = smoothstep(0.32, 0.0, dist) * step(0.985, pick);
		float twinkle = 0.65 + 0.35 * sin(TIME * (1.5 + pick * 4.0) + pick * 60.0);
		star *= mix(0.25, 2.2, pow((pick - 0.985) / 0.015, 3.0)) * twinkle;
		col += mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.9, 0.75), hash(cell + 9.0)) * star * smoothstep(0.0, 0.25, h);
		// A faint band of the galaxy across the sky.
		float band = exp(-pow(dot(d, normalize(vec3(0.45, 0.35, 0.82))), 2.0) * 22.0);
		float cloud = fbm(d * 7.0) * fbm(d * 19.0 + 4.0);
		col += vec3(0.11, 0.11, 0.15) * band * cloud * smoothstep(0.0, 0.3, h);
	}
	// The moon, and the glow around it.
	vec3 m = normalize(moon_dir);
	float md = dot(d, m);
	float disc = smoothstep(0.99955, 0.9997, md);
	float craters = 0.82 + 0.18 * fbm(d * 900.0);
	col = mix(col, vec3(1.6, 1.62, 1.55) * craters, disc);
	col += vec3(0.32, 0.38, 0.55) * pow(max(md, 0.0), 900.0) * 0.6;
	col += vec3(0.06, 0.08, 0.13) * pow(max(md, 0.0), 24.0);
	if (h < 0.0) {
		col = mix(col, vec3(0.012, 0.012, 0.016), smoothstep(0.0, -0.08, h));
	}
	return col;
}

vec3 dawn_sky(vec3 d) {
	float h = d.y;
	vec3 s = normalize(sun_dir);
	float toward = max(dot(d, s), 0.0);
	float side = dot(normalize(d.xz + vec2(0.0001)), normalize(s.xz)) * 0.5 + 0.5;
	vec3 top = vec3(0.16, 0.30, 0.56);
	vec3 mid = mix(vec3(0.55, 0.55, 0.66), vec3(0.98, 0.70, 0.52), side);
	vec3 low = mix(vec3(0.82, 0.62, 0.55), vec3(1.25, 0.66, 0.30), pow(side, 2.0));
	vec3 col = mix(low, mid, smoothstep(0.0, 0.12, h));
	col = mix(col, top, smoothstep(0.08, 0.7, h));
	col += vec3(1.4, 0.78, 0.36) * pow(toward, 12.0) * 0.7;
	col += vec3(1.0, 0.6, 0.3) * pow(toward, 3.0) * 0.18;
	// Thin high cloud, lit gold from underneath on the sun's side.
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.06);
		float c = fbm(vec3(uv * vec2(0.9, 2.6), TIME * 0.004));
		c = smoothstep(0.52, 0.8, c) * smoothstep(0.0, 0.08, h) * (1.0 - smoothstep(0.35, 0.9, h));
		vec3 lit = mix(vec3(0.85, 0.62, 0.62), vec3(1.6, 0.92, 0.5), pow(side, 1.5));
		col = mix(col, lit, c * 0.75);
	}
	float disc = smoothstep(0.99935, 0.99965, toward);
	col += vec3(18.0, 11.0, 6.0) * disc;
	if (h < 0.0) {
		col = mix(col, vec3(0.45, 0.32, 0.25), smoothstep(0.0, -0.06, h));
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	COLOR = mix(night_sky(d), dawn_sky(d), dawn);
}
"""
	return shader


func _celestial(direction: Vector3, color: Color, energy: float) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 140.0
	light.light_volumetric_fog_energy = 0.4
	stage.add_child(light)
	light.look_at_from_position(direction.normalized() * 10.0, Vector3.ZERO, Vector3.UP if absf(direction.normalized().y) < 0.99 else Vector3.BACK)
	return light


func _desert(z_from: float, z_to: float) -> void:
	var terrain := Terrain.new()
	for index in range(floori(z_from / 80.0), ceili(z_to / 80.0)):
		var section := Node3D.new()
		stage.add_child(section)
		section.position.z = index * 80.0
		terrain.populate(section, index * 80.0, 80.0, index, false, 0.0, func(_z: float) -> float: return 0.0)


func _scrub_near(points: Array, seed_value: int) -> void:
	## Extra bushes and stones close to where the camera sits.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for at: Vector3 in points:
		var kind_roll := rng.randf()
		var plant := MeshInstance3D.new()
		plant.mesh = preload("res://scripts/desert_models.gd").mesh_of("scrub" if kind_roll < 0.35 else "scrub_b" if kind_roll < 0.7 else "rock_b")
		stage.add_child(plant)
		plant.position = at
		plant.rotation.y = rng.randf() * TAU
		plant.scale = Vector3.ONE * (rng.randf_range(0.7, 1.2) if kind_roll < 0.7 else rng.randf_range(0.25, 0.5))


func _road(z_from: float, z_to: float) -> void:
	var length := z_to - z_from
	var asphalt := ShaderMaterial.new()
	asphalt.shader = ASPHALT
	asphalt.set_shader_parameter("noise_tex", preload("res://scripts/desert_models.gd").noise_texture())
	var strip := PlaneMesh.new()
	strip.size = Vector2(6.8, length)
	var road := MeshInstance3D.new()
	road.mesh = strip
	road.material_override = asphalt
	stage.add_child(road)
	road.position = Vector3(0, 0.0, z_from + length * 0.5)
	var gravel := Shapes.material(Color("#7c6c55"))
	var white := Shapes.material(Color("#cfcbb2"))
	var yellow := Shapes.material(Color("#c39a45"))
	for side in [-1.0, 1.0]:
		Shapes.box(stage, "Shoulder", Vector3(2.6, 0.01, length), Vector3(side * 4.7, -0.02, z_from + length * 0.5), gravel)
		Shapes.box(stage, "EdgeLine", Vector3(0.09, 0.004, length - 3.0), Vector3(side * 3.24, 0.004, z_from + length * 0.5 + 1.5), white)
	var z := z_from + 3.0
	while z + 3.4 < z_to:
		Shapes.box(stage, "CenterDash", Vector3(0.12, 0.004, 3.4), Vector3(0, 0.004, z + 1.7), yellow)
		z += 8.0
	# Where the pavement crumbles out before the house.
	Shapes.box(stage, "CrumbledEnd", Vector3(6.8, 0.012, 0.6), Vector3(0, -0.006, z_from - 0.2), gravel)
	# Telephone poles down one side, the wire sagging between them.
	var wire := Shapes.material(Color("#1a1a1a"))
	var pole_z := z_from + 14.0
	var previous := Vector3.ZERO
	while pole_z < z_to:
		var at := Vector3(-7.4, 0, pole_z)
		var pole := MeshInstance3D.new()
		pole.name = "Pole"
		pole.mesh = preload("res://scripts/desert_models.gd").mesh_of("pole")
		stage.add_child(pole)
		pole.position = at
		if previous != Vector3.ZERO:
			for x in [-0.6, 0.6]:
				var a := previous + Vector3(x, 6.78, 0)
				var b := at + Vector3(x, 6.78, 0)
				var mid := (a + b) * 0.5 + Vector3.DOWN * 0.9
				Shapes.tube(stage, "Wire", a, mid, 0.012, wire)
				Shapes.tube(stage, "Wire", mid, b, 0.012, wire)
		previous = at
		pole_z += 42.0


func _make_car(color: Color, style: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Car"
	stage.add_child(root)
	CarModel.new(color).build(root, style, false)
	var lens := StandardMaterial3D.new()
	head_lens = lens
	lens.albedo_color = Color(1, 0.97, 0.9)
	lens.emission_enabled = true
	lens.emission = Color(1, 0.94, 0.82)
	lens.emission_energy_multiplier = 9.0
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.6, 0.05, 0.04)
	red.emission_enabled = true
	red.emission = Color(1, 0.08, 0.05)
	red.emission_energy_multiplier = 4.0
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var title := String(mesh.name)
		if title.contains("HeadlightLens"):
			mesh.material_override = lens
		elif title.contains("BrakeLens"):
			mesh.material_override = red
	for side in [-1.0, 1.0]:
		var beam := SpotLight3D.new()
		beam.light_color = Color(1, 0.93, 0.8)
		beam.light_energy = 5.5
		beam.spot_range = 80.0
		beam.spot_angle = 24.0
		beam.spot_attenuation = 0.6
		beam.spot_angle_attenuation = 1.6
		beam.shadow_enabled = true
		beam.light_volumetric_fog_energy = 1.3
		root.add_child(beam)
		beam.position = Vector3(side * 0.5, 0.65, -2.15)
		beam.rotation.x = -0.035
		car_lights.append(beam)
	# Glare round each lamp, kept visible however far off the car is.
	var flare_material := StandardMaterial3D.new()
	flare_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flare_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flare_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flare_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flare_material.billboard_keep_scale = true
	flare_material.no_depth_test = false
	flare_material.albedo_color = Color(1, 0.92, 0.78, 0.9)
	flare_material.albedo_texture = (_puff_mesh(true).material as StandardMaterial3D).albedo_texture
	for side in [-1.0, 1.0]:
		var glare := MeshInstance3D.new()
		var quad := QuadMesh.new()
		glare.mesh = quad
		glare.material_override = flare_material
		glare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(glare)
		glare.position = Vector3(side * 0.5, 0.65, -2.25)
		flares.append(glare)
	var tail := OmniLight3D.new()
	tail.light_color = Color(1, 0.1, 0.06)
	tail.light_energy = 0.5
	tail.omni_range = 3.0
	root.add_child(tail)
	tail.position = Vector3(0, 0.7, 2.3)
	for title in ["FL_Wheel", "FR_Wheel", "RL_Wheel", "RR_Wheel"]:
		var wheel := root.get_node_or_null(title) as Node3D
		if wheel:
			wheels.append(wheel)
	car_door = root.get_node_or_null("FL_Door") as Node3D
	dome = OmniLight3D.new()
	dome.light_color = Color(1, 0.86, 0.62)
	dome.light_energy = 0.0
	dome.omni_range = 2.4
	dome.light_volumetric_fog_energy = 0.0
	root.add_child(dome)
	dome.position = Vector3(0, 1.2, 0.1)
	return root


func _roll_wheels(distance: float) -> void:
	rolled += distance / 0.39
	for wheel in wheels:
		wheel.rotation.x = -rolled


func _dust_trail(parent: Node3D, color: Color, amount: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 5.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 30, 160))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.8, 0.1, 0.3)
	process.direction = Vector3(0, 0.6, 1)
	process.spread = 35.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0.3, 0.12, 0)
	process.damping_min = 0.6
	process.damping_max = 1.2
	var grow := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(1, 1.0))
	grow.curve = curve
	process.scale_curve = grow
	process.scale_min = 1.4
	process.scale_max = 2.6
	var ramp := GradientTexture1D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color, 0.0))
	gradient.add_point(0.12, Color(color, 0.42))
	gradient.set_color(gradient.get_point_count() - 1, Color(color, 0.0))
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	particles.draw_pass_1 = _puff_mesh(false)
	parent.add_child(particles)
	return particles


func _puff_mesh(glow: bool) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var puff := StandardMaterial3D.new()
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff.vertex_color_use_as_albedo = true
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	puff.disable_receive_shadows = true
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = gradient
	puff.albedo_texture = soft
	quad.material = puff
	return quad


func _sound(title: String, stream: AudioStream, volume: float, bus := &"Master") -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume
	player.bus = bus
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	players[title] = player
	return player


func _loop(stream: AudioStream) -> AudioStream:
	var copy := stream.duplicate() as AudioStreamWAV
	if copy:
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		copy.loop_begin = 0
		copy.loop_end = int(copy.get_length() * copy.mix_rate)
		return copy
	return stream


func _fade_sound(title: String, target_db: float, delta: float, rate := 2.0) -> void:
	var player: AudioStreamPlayer = players.get(title)
	if player:
		player.volume_db = lerpf(player.volume_db, target_db, 1.0 - exp(-rate * delta))


func _distance_db(distance: float, near_db: float) -> float:
	return near_db - 20.0 * log(maxf(distance, 4.0) / 4.0) / log(10.0)


func _house(lit_windows: bool) -> Node3D:
	var prop: Node3D = RoadEndHouse.new()
	prop.prop_only = true
	stage.add_child(prop)
	porch_lamp = prop.get_node_or_null("PorchLamp") as OmniLight3D
	if porch_lamp:
		porch_lamp.light_energy = 1.4
		porch_lamp.omni_range = 7.0
		porch_lamp.shadow_enabled = true
	var glass := prop.get_node_or_null("PorchLampGlass") as MeshInstance3D
	if glass:
		porch_glass = (glass.material_override as StandardMaterial3D).duplicate()
		porch_glass.emission_energy_multiplier = 4.0
		glass.material_override = porch_glass
	if lit_windows:
		# Somebody's home: warm light behind the front windows.
		var warm := StandardMaterial3D.new()
		warm.albedo_color = Color(0.5, 0.32, 0.16)
		warm.emission_enabled = true
		warm.emission = Color(1.0, 0.66, 0.34)
		warm.emission_energy_multiplier = 1.8
		for mesh: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
			var box := mesh.mesh as BoxMesh
			if box and box.size.is_equal_approx(Vector3(0.82, 0.70, 0.034)) and mesh.position.z > 3.0:
				mesh.material_override = warm
	return prop


func _figure(at: Vector3, facing: float) -> Node3D:
	var body: Node3D = PlayerBody.new()
	stage.add_child(body)
	body.build(false)
	body.position = at + Vector3.UP * PlayerBody.FEET
	body.rotation.y = facing
	for mesh: GeometryInstance3D in body.find_children("*", "GeometryInstance3D", true, false):
		mesh.layers = 1
		# Its own shadow is not a person's. See _wrong_shadow.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wrong_shadow(body)
	# Points of eyeshine, the way an animal's eyes catch a light.
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.albedo_color = Color(0.52, 0.004, 0.011)
	shine.emission_enabled = true
	shine.emission = Color(0.74, 0.009, 0.018)
	shine.emission_energy_multiplier = 0.0
	for side in [-1.0, 1.0]:
		var dot := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.0032
		ball.height = 0.0064
		dot.mesh = ball
		dot.material_override = shine
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.set_meta("side", side)
		stage.add_child(dot)
		glints.append(dot)
	return body


func _wrong_shadow(body: Node3D) -> void:
	## What actually stands there, seen only in the shadow it throws: too tall,
	## too thin, head cocked, arms hanging past its knees with long fingers. It
	## does not move when the body does.
	var parts := Node3D.new()
	parts.name = "WrongShadow"
	body.add_child(parts)
	parts.scale = Vector3.ONE * 1.12
	parts.position.y = -PlayerBody.FEET * 0.12
	var ink := StandardMaterial3D.new()
	for limb: Array in [
			# Spine and neck, bent a little forward.
			[Vector3(0, -0.12, 0), Vector3(0, 0.62, 0.04), 0.11],
			[Vector3(0, 0.62, 0.04), Vector3(0.04, 0.86, -0.02), 0.035],
			# Legs, the knees bending the wrong way.
			[Vector3(-0.1, -0.1, 0), Vector3(-0.13, -0.55, 0.12), 0.05],
			[Vector3(-0.13, -0.55, 0.12), Vector3(-0.15, -1.02, -0.02), 0.04],
			[Vector3(0.1, -0.1, 0), Vector3(0.13, -0.55, 0.12), 0.05],
			[Vector3(0.13, -0.55, 0.12), Vector3(0.15, -1.02, -0.02), 0.04],
			# Arms: shoulders, an elbow bent backward, wrists down by the knees.
			[Vector3(-0.07, 0.6, 0), Vector3(-0.24, 0.58, 0.02), 0.04],
			[Vector3(-0.24, 0.58, 0.02), Vector3(-0.36, 0.1, 0.12), 0.032],
			[Vector3(-0.36, 0.1, 0.12), Vector3(-0.33, -0.48, -0.04), 0.026],
			[Vector3(0.07, 0.6, 0), Vector3(0.24, 0.58, 0.02), 0.04],
			[Vector3(0.24, 0.58, 0.02), Vector3(0.37, 0.12, 0.12), 0.032],
			[Vector3(0.37, 0.12, 0.12), Vector3(0.35, -0.46, -0.04), 0.026]]:
		var piece := Shapes.tube(parts, "Limb", limb[0], limb[1], limb[2], ink)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# Fingers, too many and too long.
	for side in [-1.0, 1.0]:
		var wrist := Vector3(side * 0.34, -0.47, -0.04)
		for finger in range(5):
			var spread := (finger - 2) * 0.035
			var tip := wrist + Vector3(side * 0.02 + spread, -0.22 - absf(spread) * 0.8, 0.02)
			var piece := Shapes.tube(parts, "Finger", wrist, tip, 0.008, ink)
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# A long head, cocked over to one side.
	var head := MeshInstance3D.new()
	var skull := SphereMesh.new()
	skull.radius = 0.1
	skull.height = 0.2
	head.mesh = skull
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parts.add_child(head)
	head.position = Vector3(0.12, 0.96, -0.02)
	head.rotation.z = -0.75
	head.scale = Vector3(0.9, 1.6, 0.95)


func _pose_figure(delta: float, pitch: float, shine: float, twist := 0.0) -> void:
	figure.animate(delta, {"velocity": Vector3.ZERO, "on_floor": true, "pitch": pitch, "targets": [null, wave_target],
		"grip": [0.15, 0.1], "step": 1.0})
	if twist != 0.0 and figure.posed.has("Head"):
		# The head turns over on its neck further than a head can.
		var neck_top: Transform3D = figure.posed["Head"]
		var forward: Vector3 = (figure.to_rig.basis * Vector3.FORWARD).normalized()
		figure._pose_bone("Head", Transform3D(Basis(forward, twist) * neck_top.basis, neck_top.origin))
		head_twist_now = twist
	var head: Transform3D = figure.posed.get("Head", Transform3D())
	var rest_head: Transform3D = figure.rest.get("Head", Transform3D())
	for dot in glints:
		var side: float = dot.get_meta("side")
		var rest_eye := Vector3(side * 0.034, 1.8866, -0.1)
		var rig_point := head * (rest_head.affine_inverse() * rest_eye)
		dot.global_position = figure.global_transform * (figure.to_rig.affine_inverse() * rig_point)
		var reach := maxf(1.0, camera.global_position.distance_to(dot.global_position) * 0.22)
		dot.scale = Vector3.ONE * reach
		(dot.material_override as StandardMaterial3D).emission_energy_multiplier = shine * 6.0 * minf(reach, 3.0)
		(dot.material_override as StandardMaterial3D).emission_energy_multiplier = shine * 3.0
		dot.visible = shine > 0.01


# The replaced ending: somebody always comes ------------------------------------

func _build_replaced() -> void:
	_environment(true)
	sky_material.set_shader_parameter("moon_dir", Vector3(-0.55, 0.38, 0.75))
	_celestial(Vector3(-0.55, 0.38, 0.75), Color(0.55, 0.64, 0.9), 0.32)
	_desert(-160.0, 560.0)
	_road(9.0, 540.0)
	_scrub_near([Vector3(-5.6, 0, 150), Vector3(-6.5, 0, 146.5), Vector3(-4.8, 0, 153.2), Vector3(5.8, 0, 12),
		Vector3(-6.0, 0, 9), Vector3(4.6, 0, 30), Vector3(-5.2, 0, 31), Vector3(6.5, 0, 40)], 41)
	house = _house(true)
	# Open the front door: warm light spills out across the porch.
	var hinge := house.get_node_or_null("FrontDoorHinge") as Node3D
	if hinge:
		hinge.rotation.y = deg_to_rad(96.0)
	var spill := OmniLight3D.new()
	spill.light_color = Color(1.0, 0.72, 0.42)
	spill.light_energy = 1.2
	spill.omni_range = 5.5
	spill.shadow_enabled = true
	house.add_child(spill)
	spill.position = Vector3(0.1, 1.8, 2.4)
	_build_kettle()
	figure = _figure(Vector3(0.55, -0.006, 4.72), PI)
	# Her flashlight, once she is out of the car.
	torch = SpotLight3D.new()
	torch.light_color = Color(0.92, 0.96, 1.0)
	torch.light_energy = 0.0
	torch.spot_range = 14.0
	torch.spot_angle = 17.0
	torch.spot_angle_attenuation = 1.4
	torch.shadow_enabled = true
	torch.light_volumetric_fog_energy = 0.6
	stage.add_child(torch)
	torch.look_at_from_position(Vector3(-2.7, 1.25, 9.4), Vector3(0.8, 1.35, 4.2), Vector3.UP)
	car = _make_car(Color("#3b4b5e"), CarModel.HATCHBACK)
	car.position = Vector3(1.75, 0, START_Z)
	dust = _dust_trail(car, Color(0.42, 0.38, 0.34), 90)
	dust.position = Vector3(0, 0.15, 2.2)
	_sound("dread", _loop(DREAD), -40.0).play()
	_sound("crickets", _loop(CRICKETS), -40.0).play()
	_sound("wind", _loop(WIND), -40.0).play()
	_sound("engine", _loop(ENGINE), -60.0).play()
	_sound("kettle", KETTLE, -6.0)
	_sound("door", DOOR_LATCH, -10.0)
	_sound("cough", MICK_COUGH, -9.0)
	_sound("crack", CRACK, -13.0)
	_sound("torch", TORCH_CLICK, -6.0)
	_sound("flicker", FLICKER, -14.0)
	text_at = 34.5
	shots = [
		[0.0, _shot_porch_behind],
		[7.0, _shot_kettle],
		[13.0, _shot_passing],
		[20.0, _shot_windshield],
		[27.0, _shot_arrival],
		[31.0, _shot_reveal],
	]


func _build_kettle() -> void:
	## A small stove inside the door with a kettle on it, steaming.
	var enamel := Shapes.material(Color("#d8d2c2"), 0.1, 0.45)
	var black := Shapes.material(Color("#1b1a19"), 0.3, 0.5)
	var steel := Shapes.material(Color("#9aa0a2"), 0.85, 0.28)
	var stove_at := Vector3(1.3, 0, 2.85)
	Shapes.box(house, "Stove", Vector3(0.62, 0.86, 0.58), stove_at + Vector3(0, 0.43, 0), enamel)
	Shapes.box(house, "StoveTop", Vector3(0.64, 0.03, 0.6), stove_at + Vector3(0, 0.875, 0), black)
	Shapes.box(house, "OvenDoor", Vector3(0.5, 0.42, 0.02), stove_at + Vector3(0.0, 0.42, 0.3), black)
	var flame := StandardMaterial3D.new()
	flame.albedo_color = Color(0.2, 0.3, 1.0)
	flame.emission_enabled = true
	flame.emission = Color(0.25, 0.45, 1.0)
	flame.emission_energy_multiplier = 3.5
	var ring := TorusMesh.new()
	ring.inner_radius = 0.06
	ring.outer_radius = 0.075
	var burner := MeshInstance3D.new()
	burner.mesh = ring
	burner.material_override = flame
	house.add_child(burner)
	burner.position = stove_at + Vector3(0.12, 0.895, -0.08)
	var kettle := Node3D.new()
	house.add_child(kettle)
	kettle.position = stove_at + Vector3(0.12, 0.9, -0.08)
	var body := MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.11
	bulb.height = 0.17
	bulb.radial_segments = 24
	bulb.rings = 12
	body.mesh = bulb
	body.material_override = steel
	kettle.add_child(body)
	body.position.y = 0.085
	Shapes.cylinder(kettle, "Lid", Vector3(0, 0.168, 0), Vector3.UP, 0.05, 0.02, steel, 18)
	Shapes.cylinder(kettle, "Knob", Vector3(0, 0.185, 0), Vector3.UP, 0.014, 0.022, black, 10)
	Shapes.tube(kettle, "Spout", Vector3(0.08, 0.07, 0), Vector3(0.17, 0.15, 0), 0.016, steel)
	Shapes.tube(kettle, "HandleA", Vector3(-0.06, 0.15, 0), Vector3(-0.03, 0.25, 0), 0.01, black)
	Shapes.tube(kettle, "HandleB", Vector3(-0.03, 0.25, 0), Vector3(0.04, 0.25, 0), 0.01, black)
	Shapes.tube(kettle, "HandleC", Vector3(0.04, 0.25, 0), Vector3(0.07, 0.15, 0), 0.01, black)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.78, 0.5)
	glow.light_energy = 0.45
	glow.omni_range = 2.4
	glow.shadow_enabled = true
	house.add_child(glow)
	glow.position = stove_at + Vector3(0.1, 1.5, -0.6)
	var steam := GPUParticles3D.new()
	steam.amount = 40
	steam.lifetime = 2.6
	steam.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.5, 1, 0)
	process.spread = 12.0
	process.initial_velocity_min = 0.25
	process.initial_velocity_max = 0.45
	process.gravity = Vector3(0, 0.12, 0)
	process.damping_min = 0.2
	process.damping_max = 0.4
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.4
	process.turbulence_noise_scale = 1.4
	var grow := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.15))
	curve.add_point(Vector2(1, 1.0))
	grow.curve = curve
	process.scale_curve = grow
	process.scale_min = 0.18
	process.scale_max = 0.3
	var ramp := GradientTexture1D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.add_point(0.15, Color(1, 0.97, 0.92, 0.32))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
	ramp.gradient = gradient
	process.color_ramp = ramp
	steam.process_material = process
	steam.draw_pass_1 = _puff_mesh(false)
	kettle.add_child(steam)
	steam.position = Vector3(0.18, 0.16, 0)


func _replaced_car(t: float) -> void:
	var cruise_time := (START_Z - 60.0) / CRUISE
	var brake_time := CRUISE / BRAKE
	if t < cruise_time:
		car_z = START_Z - CRUISE * t
		car_speed = CRUISE
	elif t < cruise_time + brake_time:
		var dt := t - cruise_time
		car_z = 60.0 - (CRUISE * dt - 0.5 * BRAKE * dt * dt)
		car_speed = CRUISE - BRAKE * dt
	else:
		car_z = ARRIVE_Z
		car_speed = 0.0


func _animate_replaced(t: float, delta: float) -> void:
	var before := car_z
	_replaced_car(t)
	car.position.z = car_z
	if delta > 0.0 and delta < 1.0:
		_roll_wheels(before - car_z)
	dust.emitting = car_speed > 2.0
	# The car's door opens: whoever it is, they are getting out.
	var door_open := clampf((t - 29.2) / 1.2, 0.0, 1.0)
	if car_door:
		car_door.rotation.y = -_ease(door_open) * 1.05
	dome.light_energy = 0.6 * door_open
	if t >= 29.2 and not flicker_done.has("door"):
		flicker_done["door"] = true
		players["door"].play()
	# The porch lamp stutters now and then.
	var buzz := 1.0
	for at in [5.2, 18.6, 34.0]:
		if t > at and t < at + 0.5:
			buzz = 0.25 if fmod(t * 23.0, 1.0) < 0.5 else 1.0
			if not flicker_done.has(at):
				flicker_done[at] = true
				players["flicker"].play()
	# As her flashlight comes on, the porch lamp gives out.
	if t > 31.0:
		buzz = 0.0 if t > 31.45 else (0.2 if fmod(t * 25.0, 1.0) < 0.5 else 1.0)
	porch_lamp.light_energy = 1.4 * buzz
	porch_glass.emission_energy_multiplier = 4.0 * buzz
	# She switches off the engine and the lights to get out.
	var lights_on := 1.0 if t < 30.0 else 0.0
	for beam in car_lights:
		beam.light_energy = 5.5 * lights_on
	head_lens.emission_energy_multiplier = 9.0 * lights_on
	flare_strength = lights_on
	# The figure does not move. Near the end its head tips, just slightly.
	var shine := clampf((t - 24.5) / 2.0, 0.0, 1.0) * clampf(1.0 - (car_z - ARRIVE_Z) / 80.0, 0.0, 1.0)
	var tip := _ease(clampf((t - 23.0) / 3.0, 0.0, 1.0))
	figure.rotation.z = 0.04 * tip
	# It lifts a hand to the car, slowly, and waves.
	var wave := clampf((t - 23.2) / 0.9, 0.0, 1.0) * clampf((27.2 - t) / 0.8, 0.0, 1.0)
	wave_target = null
	if wave > 0.0:
		wave_target = Vector3(0.18, -0.45, -0.08).lerp(Vector3(0.33 + 0.07 * sin((t - 23.2) * 3.4), 0.74, -0.2), _ease(wave))
	# She turns on her flashlight, and the wall shows what is really there.
	if t > 31.4:
		torch.light_energy = 7.0 * (0.92 + 0.08 * sin(t * 13.0) * sin(t * 4.1))
		if not flicker_done.has("torch"):
			flicker_done["torch"] = true
			players["torch"].play()
	# Early on, on the porch, it coughs: Mick's cough, exactly.
	var hunch := 0.0
	if t > 3.6 and t < 5.0:
		hunch = sin(clampf((t - 3.6) / 1.4, 0.0, 1.0) * PI) * 0.35
		if not flicker_done.has("cough"):
			flicker_done["cough"] = true
			players["cough"].play()
	# And when she opens her door, its head turns over, slowly, too far.
	var twist := 0.0
	if t > 32.2:
		twist = -1.4 * _ease(clampf((t - 32.2) / 2.4, 0.0, 1.0))
		if not flicker_done.has("crack"):
			flicker_done["crack"] = true
			players["crack"].play()
	_pose_figure(maxf(delta, 0.001), -0.05 + 0.1 * tip - hunch, shine, twist)
	# Sound.
	var inside := last_shot == 1
	_fade_sound("dread", -15.0, delta, 0.6)
	_fade_sound("crickets", -30.0 if inside else -19.0, delta)
	_fade_sound("wind", -32.0 if inside else -24.0, delta)
	var heard_from := camera.global_position.distance_to(car.global_position)
	var engine_db := _distance_db(heard_from, -2.0) if t < 28.5 else -80.0
	_fade_sound("engine", engine_db - (8.0 if inside else 0.0), delta, 6.0 if t < 28.5 else 1.5)
	players["engine"].pitch_scale = 0.62 + car_speed / CRUISE * 0.32
	var kettle: AudioStreamPlayer = players["kettle"]
	if t >= 9.0 and t < 18.0 and not kettle.playing and not flicker_done.has("kettle"):
		flicker_done["kettle"] = true
		kettle.play()
	if kettle.playing:
		kettle.volume_db = lerpf(kettle.volume_db, -4.0 if inside else -20.0, 1.0 - exp(-5.0 * delta))


func _shot_porch_behind(s: float) -> void:
	# Over its shoulder, down the long dark road. Headlights on the horizon.
	var u := s / 7.0
	_aim(Vector3(0.12, 1.6, 2.55).lerp(Vector3(0.1, 1.64, 2.95), _ease(u)), Vector3(-0.4, 1.35, 80.0))


func _shot_kettle(s: float) -> void:
	# Inside, by the stove: steam off the kettle, and through the open door the
	# figure on the porch with the headlights far beyond it.
	var u := s / 6.0
	_aim(Vector3(-0.15, 1.25, -0.45).lerp(Vector3(-0.1, 1.22, -0.1), _ease(u)), Vector3(0.55, 1.12, 20.0))


func _shot_passing(s: float) -> void:
	# Low on the shoulder: the car comes out of the dark and passes, and we turn
	# to watch it go on toward the house.
	var from := Vector3(-4.6, 0.42, 150.0) + Vector3(0, 0, -s * 0.15)
	var target := car.global_position + Vector3(0, 0.7, 0)
	var house_view := Vector3(0, 1.6, 0)
	var ahead := car_z < from.z
	var aim := target if not ahead else target.lerp(house_view, clampf((from.z - car_z) / 90.0, 0.0, 0.35))
	_aim(from, aim)


func _shot_windshield(_s: float) -> void:
	# From the driver's seat of the new car: through the glass, the house, and
	# the figure on its porch growing in the headlights.
	var eye := car.global_transform * Vector3(-0.38, 1.21, 0.22)
	var at := figure.global_position + Vector3(0, 0.62, 0)
	_aim(eye, eye.lerp(at, 0.5) + Vector3(0, -0.15, 0), 0.0)


func _shot_face(s: float) -> void:
	# In front of it: still, waiting, the light growing on its face.
	var u := s / 7.0
	_aim(Vector3(1.05, 1.7, 5.75).lerp(Vector3(0.9, 1.76, 5.35), _ease(u)), Vector3(0.55, 1.84, 4.72))


func _shot_arrival(s: float) -> void:
	# Wide from behind the car, the lit house and the figure in the beams.
	var u := clampf(s / 4.0, 0.0, 1.0)
	_aim(Vector3(5.6, 2.2, 31.0).lerp(Vector3(5.0, 2.7, 29.5), _ease(u)), Vector3(0.4, 1.7, 5.0))


func _shot_reveal(s: float) -> void:
	# Close, from where she is getting out: what it throws on the wall behind
	# it, the red in its eyes, and its head going over.
	var u := clampf(s / 16.0, 0.0, 1.0)
	_aim(Vector3(1.55, 1.4, 8.9).lerp(Vector3(1.2, 1.55, 7.4), _ease(u)), Vector3(0.3, 1.5, 4.3))


# The house ending: nobody came back --------------------------------------------

func _build_house_ending() -> void:
	_environment(true)
	sky_material.set_shader_parameter("moon_dir", Vector3(0.6, 0.3, 0.74))
	_celestial(Vector3(0.6, 0.3, 0.74), Color(0.5, 0.6, 0.9), 0.26)
	env.volumetric_fog_density = 0.022
	_desert(-160.0, 400.0)
	_road(9.0, 380.0)
	_scrub_near([Vector3(5.5, 0, 26), Vector3(-5.8, 0, 22), Vector3(6.4, 0, 44), Vector3(-6.2, 0, 60), Vector3(5.0, 0, 70)], 42)
	house = _house(false)
	# Nobody has the lamps on inside any more.
	for lamp in house.lamps:
		lamp.visible = false
	var hinge := house.get_node_or_null("FrontDoorHinge") as Node3D
	if hinge:
		hinge.rotation.y = deg_to_rad(103.0)
	car = _make_car(Color("#7e3830"), CarModel.SEDAN)
	car.position = Vector3(0.9, 0, 18.5)
	car.rotation.y = -0.12
	if car_door:
		car_door.rotation.y = -1.0
	dome.light_energy = 0.55
	# The instruments still glow; the radio is still on.
	var dash := OmniLight3D.new()
	dash.light_color = Color(0.55, 0.85, 0.7)
	dash.light_energy = 0.35
	dash.omni_range = 0.9
	dash.light_volumetric_fog_energy = 0.0
	car.add_child(dash)
	dash.position = Vector3(-0.3, 0.98, -0.6)
	# Eyes, low, in the dark of the doorway.
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.albedo_color = Color(0.52, 0.004, 0.011)
	shine.emission_enabled = true
	shine.emission = Color(0.74, 0.009, 0.018)
	shine.emission_energy_multiplier = 18.0
	for side in [-1.0, 1.0]:
		var dot := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.016
		ball.height = 0.024
		dot.mesh = ball
		dot.material_override = shine
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		house.add_child(dot)
		dot.position = Vector3(-0.18 + side * 0.055, 0.62 + side * 0.012, 2.6)
		dot.visible = false
		eyes.append(dot)
	_sound("dread", _loop(DREAD), -40.0).play()
	_sound("crickets", _loop(CRICKETS), -40.0).play()
	_sound("wind", _loop(WIND), -40.0).play()
	_sound("radio", _loop(BROADCAST), -40.0, RoadRadio._radio_bus()).play()
	_sound("flicker", FLICKER, -12.0)
	text_at = 21.5
	shots = [
		[0.0, _shot_behind_car],
		[7.0, _shot_dashboard],
		[13.0, _shot_doorway],
		[21.0, _shot_far],
	]


func _animate_house(t: float, delta: float) -> void:
	var buzz := 1.0
	for at in [3.0, 10.5, 15.2]:
		if t > at and t < at + 0.6:
			buzz = 0.2 if fmod(t * 19.0, 1.0) < 0.5 else 1.0
			if not flicker_done.has(at):
				flicker_done[at] = true
				players["flicker"].play()
	# And then it goes out, and stays out.
	if t > 23.5:
		buzz = 0.0 if t > 24.4 else (0.3 if fmod(t * 25.0, 1.0) < 0.5 else 1.0)
		if not flicker_done.has("out"):
			flicker_done["out"] = true
			players["flicker"].play()
	porch_lamp.light_energy = 1.4 * buzz
	porch_glass.emission_energy_multiplier = 4.0 * buzz
	var seen := t > 16.0
	var blink := t > 19.4 and t < 19.6
	for dot in eyes:
		dot.visible = seen and not blink
		dot.scale.y = 1.0 if not blink else 0.15
	var in_car := last_shot == 1
	_fade_sound("dread", -14.0, delta, 0.6)
	_fade_sound("crickets", -22.0 if not in_car else -30.0, delta)
	_fade_sound("wind", -26.0 if not in_car else -36.0, delta)
	_fade_sound("radio", -12.0 if in_car else -34.0, delta, 4.0)


func _shot_behind_car(s: float) -> void:
	var u := s / 7.0
	_aim(Vector3(3.4, 0.85, 33.0).lerp(Vector3(2.6, 0.95, 29.0), _ease(u)), Vector3(0.0, 1.7, 2.0))


func _shot_dashboard(s: float) -> void:
	# The driver's seat, empty. The dials still lit, the radio still talking.
	var u := s / 6.0
	var seat := car.global_transform * Vector3(-0.05, 1.12, 0.62)
	var ahead := car.global_transform * Vector3(-0.42, 0.9, -1.4)
	_aim(seat.lerp(car.global_transform * Vector3(0.02, 1.1, 0.5), _ease(u)), ahead)


func _shot_doorway(s: float) -> void:
	var u := s / 8.0
	_aim(Vector3(0.2, 1.45, 9.4).lerp(Vector3(0.05, 1.2, 6.0), _ease(u)), Vector3(-0.15, 0.85, 2.6))


func _shot_far(s: float) -> void:
	var u := clampf(s / 20.0, 0.0, 1.0)
	_aim(Vector3(-7.0, 6.0, 72.0).lerp(Vector3(-5.0, 8.0, 66.0), _ease(u)), Vector3(0.0, 1.2, 6.0))


# The way out: morning ------------------------------------------------------------

const FREE_SPEED := 13.0
const FREE_START := 70.0
var sun_dir := Vector3(0.18, 0.07, -1.0)


func _build_free() -> void:
	_environment(false)
	sky_material.set_shader_parameter("sun_dir", sun_dir)
	_celestial(sun_dir, Color(1.0, 0.74, 0.5), 2.4)
	_desert(-900.0, 200.0)
	# A faint track across the sand, two ruts worn by other cars long ago.
	var rut := Shapes.material(Color("#8a6e50"), 0.0, 1.0)
	for x in [-0.82, 0.82]:
		Shapes.box(stage, "Rut", Vector3(0.36, 0.006, 1100.0), Vector3(x, -0.036, -350.0), rut)
	_scrub_near([Vector3(3.6, -0.04, 1.5), Vector3(4.4, -0.04, -2.2), Vector3(2.4, -0.04, 6.0),
		Vector3(-3.0, -0.04, 3.0), Vector3(7.0, -0.04, -12.0), Vector3(-4.2, -0.04, -20.0)], 43)
	car = _make_car(Color("#7e3830"), CarModel.SEDAN)
	for beam in car_lights:
		beam.light_energy = 1.2
	dust = _dust_trail(car, Color(0.86, 0.68, 0.5), 140)
	dust.position = Vector3(0, 0.15, 2.2)
	_sound("dawn", _loop(DAWN), -40.0).play()
	_sound("wind", _loop(WIND), -40.0).play()
	_sound("engine", _loop(ENGINE), -60.0).play()
	_sound("gravel", _loop(GRAVEL), -60.0).play()
	text_at = 12.5
	shots = [
		[0.0, _shot_low_pass],
		[6.0, _shot_alongside],
		[12.0, _shot_into_sun],
	]


func _animate_free(t: float, delta: float) -> void:
	var before := car_z
	car_z = FREE_START - FREE_SPEED * t
	car.position = Vector3(0, -0.04 + sin(t * 9.0) * 0.006, car_z)
	car.rotation.z = sin(t * 1.7) * 0.006
	if delta > 0.0 and delta < 1.0:
		_roll_wheels(before - car_z)
	var heard := camera.global_position.distance_to(car.global_position)
	_fade_sound("dawn", -11.0, delta, 0.5)
	_fade_sound("wind", -22.0, delta)
	_fade_sound("engine", _distance_db(heard, -6.0), delta, 5.0)
	_fade_sound("gravel", _distance_db(heard, -10.0), delta, 5.0)
	players["engine"].pitch_scale = 0.78


func _shot_low_pass(s: float) -> void:
	var from := Vector3(3.2, 0.38, 2.0)
	_aim(from, car.global_position + Vector3(0, 0.6, 0) + Vector3(0, 0, -1.0 if car_z < from.z else 0.0))


func _shot_alongside(s: float) -> void:
	var at := car.global_position
	_aim(at + Vector3(-5.8, 1.0, -0.6 - s * 0.15), at + Vector3(0, 0.8, -1.2))


func _shot_into_sun(s: float) -> void:
	# Lifting up behind, letting it go on alone toward the sun.
	var start := FREE_START - FREE_SPEED * 12.0
	var u := clampf(s / 26.0, 0.0, 1.0)
	# The camera follows, slower and slower, rising, and lets it go.
	var follow := start + 11.0 - FREE_SPEED * s + 0.5 * 0.45 * minf(s, 26.0) * minf(s, 26.0)
	var from := Vector3(-1.8 - 1.5 * u, 1.7 + 6.0 * _ease(u), follow)
	_aim(from, car.global_position + Vector3(0, 0.9 - 0.4 * u, -8.0 - 20.0 * u))


# Shared: what the thing looks like when you can see it whole ---------------------

static func creature_figure() -> Node3D:
	## A black, too-thin figure: long limbs, elbows and knees bent the wrong way,
	## head cocked. Seen against fire or sky.
	var figure := Node3D.new()
	figure.name = "Thing"
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.01, 0.008, 0.008)
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for limb: Array in [
			[Vector3(0, 0.95, 0), Vector3(0, 1.75, 0.04), 0.12],
			[Vector3(0, 1.75, 0.04), Vector3(0.04, 2.0, -0.02), 0.04],
			[Vector3(-0.11, 0.95, 0), Vector3(-0.15, 0.48, 0.14), 0.055],
			[Vector3(-0.15, 0.48, 0.14), Vector3(-0.17, 0.0, -0.02), 0.045],
			[Vector3(0.11, 0.95, 0), Vector3(0.15, 0.48, 0.14), 0.055],
			[Vector3(0.15, 0.48, 0.14), Vector3(0.17, 0.0, -0.02), 0.045],
			[Vector3(-0.08, 1.72, 0), Vector3(-0.27, 1.7, 0.02), 0.045],
			[Vector3(-0.27, 1.7, 0.02), Vector3(-0.4, 1.18, 0.14), 0.035],
			[Vector3(-0.4, 1.18, 0.14), Vector3(-0.37, 0.55, -0.04), 0.03],
			[Vector3(0.08, 1.72, 0), Vector3(0.27, 1.7, 0.02), 0.045],
			[Vector3(0.27, 1.7, 0.02), Vector3(0.41, 1.2, 0.14), 0.035],
			[Vector3(0.41, 1.2, 0.14), Vector3(0.39, 0.57, -0.04), 0.03]]:
		var piece := Shapes.tube(figure, "Limb", limb[0], limb[1], limb[2], ink)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var head := MeshInstance3D.new()
	var skull := SphereMesh.new()
	skull.radius = 0.11
	skull.height = 0.22
	head.mesh = skull
	head.material_override = ink
	figure.add_child(head)
	head.position = Vector3(0.13, 2.12, -0.02)
	head.rotation.z = -0.75
	head.scale = Vector3(0.9, 1.6, 0.95)
	return figure


# Burn it: the house goes up, and the sun comes up -----------------------------------

var fire: Node3D
var burn_sun: DirectionalLight3D
var radio_crackled := false


func _build_burn() -> void:
	_environment(true)
	sky_material.set_shader_parameter("moon_dir", Vector3(0.55, 0.32, 0.77))
	sky_material.set_shader_parameter("sun_dir", Vector3(0.07, 0.035, -1.0))
	_celestial(Vector3(0.55, 0.32, 0.77), Color(0.5, 0.6, 0.9), 0.2)
	burn_sun = _celestial(Vector3(0.07, 0.06, -1.0), Color(1.0, 0.7, 0.45), 0.0)
	env.volumetric_fog_density = 0.012
	_desert(-160.0, 420.0)
	_road(9.0, 400.0)
	_scrub_near([Vector3(5.6, 0, 27), Vector3(-5.6, 0, 24), Vector3(6.2, 0, 46), Vector3(-6.0, 0, 64)], 44)
	house = _house(false)
	for lamp in house.lamps:
		lamp.visible = false
	porch_lamp.visible = false
	porch_glass.emission_energy_multiplier = 0.0
	# Scorched: every board darker.
	for mesh: MeshInstance3D in house.find_children("*", "MeshInstance3D", true, false):
		var finish := mesh.material_override as StandardMaterial3D
		if finish:
			var charred := finish.duplicate() as StandardMaterial3D
			charred.albedo_color = finish.albedo_color.darkened(0.6)
			mesh.material_override = charred
	if house.has_method("scorch"):
		house.scorch(0.6)
	fire = HouseFire.new()
	house.add_child(fire)
	fire.position = Vector3.ZERO
	fire.set_heat(1.0)
	car = _make_car(Color("#7e3830"), CarModel.SEDAN)
	car.position = Vector3(0.9, 0, 20.0)
	car.rotation.y = -0.1
	for beam in car_lights:
		beam.light_energy = 0.0
	flare_strength = 0.0
	head_lens = null
	_sound("dread", _loop(DREAD), -40.0).play()
	_sound("kettle", KETTLE, -12.0)
	_sound("radio", HELLO, -9.0, RoadRadio._radio_bus())
	_sound("dawn", _loop(DAWN), -60.0).play()
	text_at = 14.0
	shots = [
		[0.0, _shot_burn_behind_car],
		[7.0, _shot_burn_porch],
		[13.0, _shot_burn_far],
	]


func _animate_burn(t: float, delta: float) -> void:
	# Morning comes up behind the house as it burns down.
	var dawn := _ease(clampf((t - 13.0) / 22.0, 0.0, 1.0))
	sky_material.set_shader_parameter("dawn", dawn * 0.42)
	burn_sun.light_energy = 0.9 * dawn
	env.ambient_light_energy = lerpf(0.16, 0.32, dawn)
	env.tonemap_exposure = lerpf(1.0, 0.8, dawn)
	fire.set_heat(lerpf(1.0, 0.7, clampf((t - 13.0) / 24.0, 0.0, 1.0)))
	var kettle: AudioStreamPlayer = players["kettle"]
	if t > 7.4 and not flicker_done.has("kettle"):
		flicker_done["kettle"] = true
		kettle.play()
	_fade_sound("dread", lerpf(-14.0, -30.0, dawn), delta, 0.6)
	_fade_sound("dawn", lerpf(-40.0, -14.0, dawn), delta, 0.6)
	if kettle.playing:
		kettle.volume_db = lerpf(kettle.volume_db, -3.0 if last_shot == 1 else -18.0, 1.0 - exp(-4.0 * delta))
	# And then, once, faintly, the car radio.
	if t > 27.0 and not radio_crackled:
		radio_crackled = true
		players["radio"].play()


func _shot_burn_behind_car(s: float) -> void:
	var u := s / 7.0
	_aim(Vector3(3.0, 1.0, 34.0).lerp(Vector3(2.4, 1.1, 30.0), _ease(u)), Vector3(0.0, 3.0, 1.0))


func _shot_burn_porch(s: float) -> void:
	var u := s / 6.0
	_aim(Vector3(3.2, 1.4, 12.5).lerp(Vector3(2.4, 1.5, 11.0), _ease(u)), Vector3(0.0, 2.2, 3.8))


func _shot_burn_far(s: float) -> void:
	var u := clampf(s / 24.0, 0.0, 1.0)
	_aim(Vector3(-7.0, 3.5, 74.0).lerp(Vector3(-5.5, 6.0, 66.0), _ease(u)), Vector3(0.0, 3.5, 2.0))
