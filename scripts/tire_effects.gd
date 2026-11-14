extends Node3D

const RoadAudio := preload("res://scripts/road_audio.gd")
const Terrain := preload("res://scripts/roadside_terrain.gd")
const TIRE_SOUNDS := [RoadAudio.ASPHALT, RoadAudio.GRAVEL, RoadAudio.SOIL]
const TIRE_GAIN := [0.29, 0.40, 0.32]
const TIRE_PITCH := [0.87, 0.83, 0.88]
const RANGE_SQUARED := 75.0 * 75.0

static var dust_mesh: QuadMesh

var sounds: Array[AudioStreamPlayer3D] = []
var emitters: Dictionary[Wheel, CPUParticles3D] = {}


func update_tires(wheels: Array[Wheel], velocity: Vector3, delta: float, remote: bool) -> void:
	var camera := get_viewport().get_camera_3d()
	var nearby := camera != null and camera.global_position.distance_squared_to(global_position) < RANGE_SQUARED
	var speed := Vector2(velocity.x, velocity.z).length()
	var rolling := Vector3.ZERO
	var dusty_wheels: Array[Wheel] = []
	if not nearby or speed < 0.8:
		for dust in emitters.values():
			dust.emitting = false
	else:
		for wheel in wheels:
			if not wheel.installed or not wheel.enabled:
				continue
			if remote:
				wheel.force_raycast_update()
			if not wheel.is_colliding():
				continue
			var ground := wheel.get_collider() as StaticBody3D
			if ground == null:
				continue
			var surface := _surface(ground)
			if surface < 0:
				continue
			rolling[surface] += 1.0 / wheels.size()
			if surface <= 0 or speed < 3.0:
				continue
			var at := wheel.get_collision_point()
			var cover := Terrain.dust_amount(at.z) if surface == 2 else 0.58
			var density := cover * smoothstep(3.0, 23.0, speed)
			if density < 0.02:
				continue
			var dust: CPUParticles3D = emitters.get(wheel)
			if dust == null:
				dust = _add_dust_emitter()
				emitters[wheel] = dust
			dust.global_position = at + wheel.get_collision_normal() * 0.075
			# Trail stays in world space as the wheel moves on.
			dust.direction = (-velocity.slide(Vector3.UP).normalized() * 0.38 + Vector3.UP * 0.27).normalized()
			var soil := Terrain.dust_tint(at.z) if surface == 2 else Color("#a1957e")
			soil.a = lerpf(0.05, 0.48, density)
			dust.color = soil
			dust.emitting = true
			dusty_wheels.append(wheel)
		for wheel in emitters:
			if wheel not in dusty_wheels:
				emitters[wheel].emitting = false
	var loudness := smoothstep(0.8, 26.0, speed)
	if sounds.is_empty() and rolling.length_squared() > 0.0:
		_add_sounds()
	for i in sounds.size():
		var gain: float = rolling[i] * loudness * TIRE_GAIN[i]
		var sound := sounds[i]
		if gain > 0.001 and not sound.playing:
			sound.play()
		sound.pitch_scale = lerpf(sound.pitch_scale, TIRE_PITCH[i] + minf(0.43, speed * 0.016), minf(1.0, delta * 6.0))
		RoadAudio.smooth_gain(sound, gain, 1.0 - exp(-delta * 14.0))
		if gain == 0.0 and sound.playing and sound.volume_db < -57.0:
			sound.stop()


func _surface(ground: StaticBody3D) -> int:
	if ground.is_in_group("roadside_gravel"):
		return 1
	if ground.is_in_group("roadside_soil"):
		return 2
	if ground.is_in_group("Road"):
		return 0
	return -1


func _add_sounds() -> void:
	for source in TIRE_SOUNDS:
		var sound := AudioStreamPlayer3D.new()
		sound.stream = RoadAudio.loop(source)
		sound.volume_db = -80.0
		sound.unit_size = 5.0
		sound.max_distance = 48.0
		add_child(sound)
		sounds.append(sound)


func _add_dust_emitter() -> CPUParticles3D:
	if dust_mesh == null:
		var edge := Gradient.new()
		edge.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
		edge.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		var texture := GradientTexture2D.new()
		texture.gradient = edge
		texture.width = 64
		texture.height = 64
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		material.disable_receive_shadows = true
		dust_mesh = QuadMesh.new()
		dust_mesh.size = Vector2(0.94, 0.94)
		dust_mesh.material = material
	var dust := CPUParticles3D.new()
	dust.emitting = false
	dust.mesh = dust_mesh
	dust.amount = 26
	dust.lifetime = 1.25
	dust.local_coords = false
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.spread = 28.0
	dust.gravity = Vector3(0.16, -0.08, 0.07)
	dust.initial_velocity_min = 0.38
	dust.initial_velocity_max = 1.36
	dust.damping_min = 0.32
	dust.damping_max = 0.71
	dust.scale_amount_min = 0.67
	dust.scale_amount_max = 1.28
	dust.scale_amount_curve = Curve.new()
	dust.scale_amount_curve.add_point(Vector2(0, 0.22))
	dust.scale_amount_curve.add_point(Vector2(0.75, 0.95))
	dust.scale_amount_curve.add_point(Vector2(1, 1))
	dust.color_ramp = Gradient.new()
	dust.color_ramp.offsets = PackedFloat32Array([0, 0.14, 0.52, 1])
	dust.color_ramp.colors = PackedColorArray([Color(1, 1, 1, 0.12), Color.WHITE, Color(1, 1, 1, 0.46), Color(1, 1, 1, 0)])
	add_child(dust)
	dust.top_level = true
	return dust


func _exit_tree() -> void:
	for sound in sounds:
		sound.stop()
