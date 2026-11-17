extends Node3D
## A house fire: flames out of the roof, windows and doorway, sparks, a column
## of smoke and flickering orange light thrown on the walls from outside.
## `heat` (0 to 1) is how far it has taken hold. Used on the house at the end
## of the road and in its ending scene; place it at the house's origin.

const CRACKLE := preload("res://assets/audio/ending/fire_crackle.wav")

## Where the flames come out, in this node's space: [centre, half-extents,
## flame size, how many]. The default fits the house at the end of the road:
## the roof, and tongues of fire out of each front window and the doorway.
var emitters: Array = [
	[Vector3(0, 6.35, 0), Vector3(2.6, 0.3, 3.5), 2.6, 260],
	[Vector3(-2.2, 5.5, 0), Vector3(0.9, 0.2, 3.6), 1.8, 90],
	[Vector3(2.2, 5.5, 0), Vector3(0.9, 0.2, 3.6), 1.8, 90],
	[Vector3(0, 3.0, 0), Vector3(3.4, 2.4, 3.6), 1.6, 90],
	[Vector3(-2.04, 1.4, 4.0), Vector3(0.35, 0.25, 0.05), 1.1, 50],
	[Vector3(2.04, 1.4, 4.0), Vector3(0.35, 0.25, 0.05), 1.1, 50],
	[Vector3(-2.04, 3.7, 4.0), Vector3(0.35, 0.25, 0.05), 1.1, 50],
	[Vector3(2.04, 3.7, 4.0), Vector3(0.35, 0.25, 0.05), 1.1, 50],
	[Vector3(0, 1.4, 3.9), Vector3(0.6, 1.1, 0.1), 1.3, 70],
]
## Where its light falls from: just outside each wall, and above the roof.
var light_spots: Array = [Vector3(0, 2.4, 5.6), Vector3(0, 2.4, -5.6), Vector3(-5.4, 2.4, 0), Vector3(5.4, 2.4, 0),
	Vector3(0, 7.5, 0)]
var heat := 0.0
var flames: Array[GPUParticles3D] = []
var embers: GPUParticles3D
var smoke: GPUParticles3D
var lights: Array[OmniLight3D] = []
var crackle: AudioStreamPlayer3D
var clock := 0.0


func _ready() -> void:
	for spot: Array in emitters:
		var tongues := _particles(spot[3], 1.0, _flame_material(spot[1], spot[2]), _flame_quad(spot[2]))
		tongues.position = spot[0]
		flames.append(tongues)
	embers = _particles(90, 3.0, _ember_material(), _soft_quad(true))
	embers.position = Vector3(0, 5.8, 0)
	(embers.draw_pass_1 as QuadMesh).size = Vector2(0.08, 0.08)
	smoke = _particles(60, 10.0, _smoke_material(), _soft_quad(false))
	smoke.position = Vector3(0, 7.0, 0)
	(smoke.draw_pass_1 as QuadMesh).size = Vector2(4.0, 4.0)
	smoke.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 80, 80))
	for i in light_spots.size():
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.48, 0.16)
		glow.omni_range = 18.0
		glow.omni_attenuation = 1.2
		glow.shadow_enabled = i == light_spots.size() - 1 and not GameSettings.low_end
		add_child(glow)
		glow.position = light_spots[i]
		lights.append(glow)
	crackle = AudioStreamPlayer3D.new()
	crackle.stream = _looped(CRACKLE)
	crackle.unit_size = 9.0
	crackle.max_distance = 140.0
	add_child(crackle)
	crackle.position.y = 3.0
	set_heat(0.0)


func set_heat(value: float) -> void:
	heat = clampf(value, 0.0, 1.0)
	var on := heat > 0.01
	for i in flames.size():
		# The roof catches last.
		var share := clampf(heat * 1.3 - (0.3 if i == 0 else 0.0), 0.0, 1.0)
		flames[i].emitting = share > 0.01
		flames[i].amount_ratio = share
	for particles in [embers, smoke]:
		particles.emitting = on
		particles.amount_ratio = heat
	if on and not crackle.playing:
		crackle.play()
	crackle.volume_db = linear_to_db(maxf(heat, 0.001)) + 2.0
	if not on:
		crackle.stop()


func _process(delta: float) -> void:
	clock += delta
	for i in lights.size():
		var flicker := 0.72 + 0.28 * sin(clock * (9.0 + i * 3.1)) * sin(clock * (4.3 + i * 1.7) + i)
		lights[i].light_energy = 4.0 * heat * flicker
		lights[i].light_volumetric_fog_energy = 0.5 * heat


func _particles(count: int, life: float, process: ParticleProcessMaterial, quad: QuadMesh) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = life
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 24, 24))
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	return particles


func _flame_quad(size: float) -> QuadMesh:
	var quad := _soft_quad(true)
	# Mixed rather than added, so the fire still shows against a bright sky.
	(quad.material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	quad.size = Vector2(0.55, 1.0) * size
	return quad


func _flame_material(extents: Vector3, size: float) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3.UP
	process.spread = 10.0
	process.initial_velocity_min = 1.2 * size
	process.initial_velocity_max = 2.2 * size
	process.gravity = Vector3(0.5, 2.5, 0)
	process.damping_min = 0.5
	process.damping_max = 1.0
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.5
	process.turbulence_noise_scale = 2.0
	process.scale_min = 0.6
	process.scale_max = 1.3
	process.scale_curve = _curve([Vector2(0, 0.5), Vector2(0.3, 1.0), Vector2(1, 0.2)])
	process.color_ramp = _ramp([[0.0, Color(1.0, 0.85, 0.45, 0.0)], [0.08, Color(1.0, 0.7, 0.28, 0.8)],
		[0.45, Color(0.98, 0.36, 0.06, 0.55)], [1.0, Color(0.25, 0.05, 0.02, 0.0)]])
	return process


func _ember_material() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(3.2, 0.6, 3.4)
	process.direction = Vector3.UP
	process.spread = 35.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 7.0
	process.gravity = Vector3(0.8, 0.6, 0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 2.0
	process.color_ramp = _ramp([[0.0, Color(1.0, 0.8, 0.4, 1.0)], [1.0, Color(1.0, 0.3, 0.05, 0.0)]])
	return process


func _smoke_material() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(2.4, 0.5, 2.6)
	process.direction = Vector3.UP
	process.spread = 10.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 3.5
	process.gravity = Vector3(1.2, 0.5, 0)
	process.scale_min = 3.0
	process.scale_max = 5.0
	process.scale_curve = _curve([Vector2(0, 0.4), Vector2(1, 2.2)])
	process.color_ramp = _ramp([[0.0, Color(0.1, 0.08, 0.07, 0.0)], [0.12, Color(0.08, 0.07, 0.06, 0.75)],
		[0.6, Color(0.14, 0.13, 0.12, 0.5)], [1.0, Color(0.2, 0.19, 0.18, 0.0)]])
	return process


func _soft_quad(glow: bool) -> QuadMesh:
	var quad := QuadMesh.new()
	var puff := StandardMaterial3D.new()
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff.vertex_color_use_as_albedo = true
	puff.disable_receive_shadows = true
	if glow:
		puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
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


func _curve(points: Array) -> CurveTexture:
	var curve := Curve.new()
	for point: Vector2 in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _ramp(stops: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(stops.map(func(s: Array) -> float: return s[0]))
	gradient.colors = PackedColorArray(stops.map(func(s: Array) -> Color: return s[1]))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _looped(stream: AudioStreamWAV) -> AudioStreamWAV:
	var copy := stream.duplicate() as AudioStreamWAV
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	copy.loop_begin = 0
	copy.loop_end = int(copy.get_length() * copy.mix_rate)
	return copy
