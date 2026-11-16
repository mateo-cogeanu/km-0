extends Node
## Now and then a dust storm rolls over the road: brown air closes in to a few
## tens of metres, grit streams past, the wind roars. Whatever stands out in
## the desert can stand much closer while it lasts.

const STORM := preload("res://assets/audio/road/dust_storm.wav")
const HAZE := preload("res://assets/ui/dust_haze.gdshader")
const RAMP := 25.0

var wait := 0.0
var left := 0.0
var length := 0.0
var level := 0.0
var dust: GPUParticles3D
var roar: AudioStreamPlayer
var haze: MeshInstance3D
var haze_material: ShaderMaterial


func _ready() -> void:
	wait = randf_range(480.0, 840.0)
	var loop: AudioStreamWAV = STORM
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = loop.data.size() / 2
	roar = AudioStreamPlayer.new()
	roar.stream = loop
	roar.volume_db = -60.0
	add_child(roar)
	dust = GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 1600
	dust.lifetime = 2.2
	dust.local_coords = false
	dust.emitting = false
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(16, 5, 16)
	motion.direction = Vector3(1, -0.05, 0.35)
	motion.spread = 12.0
	motion.initial_velocity_min = 9.0
	motion.initial_velocity_max = 15.0
	motion.gravity = Vector3.ZERO
	motion.scale_min = 0.5
	motion.scale_max = 1.6
	dust.process_material = motion
	var mote := QuadMesh.new()
	mote.size = Vector2(0.09, 0.03)
	var grit := StandardMaterial3D.new()
	grit.albedo_color = Color(0.66, 0.53, 0.38, 0.7)
	grit.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grit.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote.material = grit
	dust.draw_pass_1 = mote
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)
	haze = MeshInstance3D.new()
	haze.name = "Haze"
	var screen := QuadMesh.new()
	screen.size = Vector2(2, 2)
	haze.mesh = screen
	haze_material = ShaderMaterial.new()
	haze_material.shader = HAZE
	haze.material_override = haze_material
	haze.extra_cull_margin = 16384.0
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	haze.visible = false
	add_child(haze)


func storm_level() -> float:
	return level


func _process(delta: float) -> void:
	var cycle := get_tree().current_scene.get_node_or_null("DayNightCycle") if get_tree().current_scene else null
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	if player == null or cycle == null:
		return
	if left > 0.0:
		left -= delta
		var since := length - left
		level = minf(1.0, minf(since, left) / RAMP)
	else:
		level = 0.0
		wait -= delta
		if wait <= 0.0 and not player.ending_locked:
			length = randf_range(150.0, 240.0)
			left = length
			wait = randf_range(900.0, 1800.0)
	if player.ending_locked:
		level = move_toward(level, 0.0, delta * 0.5)
	cycle.storm = level
	haze.visible = level > 0.01
	haze_material.set_shader_parameter("strength", level)
	var daylight: float = cycle.daylight if "daylight" in cycle else 1.0
	haze_material.set_shader_parameter("tint", Color(0.6, 0.47, 0.33) * lerpf(0.12, 1.0, daylight))
	var camera := get_viewport().get_camera_3d()
	if camera:
		dust.global_position = camera.global_position
		haze.global_position = camera.global_position
	dust.emitting = level > 0.05
	dust.amount_ratio = level * (0.35 if GameSettings.low_end else 1.0)
	var sheltered := is_instance_valid(player.active_vehicle)
	roar.volume_db = linear_to_db(maxf(level, 0.0001)) - (9.0 if sheltered else 3.0)
	if level > 0.01 and not roar.playing:
		roar.play()
	elif level <= 0.01 and roar.playing:
		roar.stop()
