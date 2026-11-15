extends Node
## Small wrong things along the road, long before the house.
## - At night, a tall figure sometimes stands far out in the desert ahead. Look
##   straight at it, or get close, and it is gone.
## - Inside the roadside buildings, now and then, footsteps behind you that
##   stop the moment you turn round.

const MODEL := preload("res://assets/characters/player.glb")
const STEPS := [
	preload("res://assets/audio/player/step_1.wav"), preload("res://assets/audio/player/step_2.wav"),
	preload("res://assets/audio/player/step_3.wav"), preload("res://assets/audio/player/step_4.wav"),
]

var road: Node3D
var figure: Node3D
var figure_wait := 120.0
var figure_life := 0.0
var figure_seen := 0.0
var steps_wait := 25.0
var stalker: AudioStreamPlayer3D
var stalker_steps := 0
var stalker_clock := 0.0
var stalker_from := Vector3.ZERO


func _ready() -> void:
	figure = MODEL.instantiate()
	figure.name = "DesertFigure"
	add_child(figure)
	figure.scale = Vector3(0.82, 1.18, 0.82)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.008, 0.008, 0.01)
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mesh: GeometryInstance3D in figure.find_children("*", "GeometryInstance3D", true, false):
		mesh.material_override = black
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	figure.hide()
	stalker = AudioStreamPlayer3D.new()
	stalker.unit_size = 2.0
	stalker.volume_db = -11.0
	add_child(stalker)


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	var camera := get_viewport().get_camera_3d()
	if player == null or camera == null or player.ending_locked:
		figure.hide()
		return
	_watch_figure(delta, player, camera)
	_follow_steps(delta, player, camera)


func _daylight() -> float:
	var cycle := get_tree().current_scene.get_node_or_null("DayNightCycle") if get_tree().current_scene else null
	return cycle.daylight if cycle and "daylight" in cycle else 1.0


func _watch_figure(delta: float, player: Node3D, camera: Camera3D) -> void:
	if figure.visible:
		figure_life -= delta
		var toward := (figure.global_position + Vector3.UP * 1.6 - camera.global_position)
		var looked := camera.is_position_in_frustum(figure.global_position) and toward.normalized().dot(-camera.global_basis.z) > 0.993
		figure_seen = figure_seen + delta if looked else 0.0
		var close := toward.length() < 45.0
		if figure_seen > 0.15 or close or figure_life <= 0.0 or _daylight() > 0.3:
			if not camera.is_position_in_frustum(figure.global_position) or figure_seen > 0.15 or close:
				figure.hide()
				figure_wait = randf_range(150.0, 320.0)
		return
	if _daylight() > 0.15:
		return
	figure_wait -= delta
	if figure_wait > 0.0 or road == null:
		return
	# Off to one side, well ahead along the road, facing the road.
	var ahead := player.global_position.z - randf_range(85.0, 140.0)
	var side := -1.0 if randf() < 0.5 else 1.0
	var spot: Vector3 = road._sample(ahead, side * randf_range(16.0, 34.0))
	spot.y = -0.04
	if camera.is_position_in_frustum(spot) and (spot - camera.global_position).normalized().dot(-camera.global_basis.z) > 0.9:
		figure_wait = 3.0
		return
	figure.global_position = spot
	var to_road: Vector3 = road._sample(ahead, 0.0) - spot
	figure.look_at(spot - Vector3(to_road.x, 0, to_road.z), Vector3.UP)
	figure.show()
	figure_life = 40.0
	figure_seen = 0.0


func _follow_steps(delta: float, player: Node3D, camera: Camera3D) -> void:
	if stalker_steps > 0:
		stalker_clock -= delta
		var behind := (stalker_from - camera.global_position).normalized()
		# Turn round and they stop.
		if behind.dot(-camera.global_basis.z) > 0.4:
			stalker_steps = 0
			steps_wait = randf_range(60.0, 120.0)
			return
		if stalker_clock <= 0.0:
			stalker_clock = randf_range(0.48, 0.62)
			stalker_steps -= 1
			stalker_from = stalker_from.lerp(player.global_position, 0.12)
			stalker.global_position = stalker_from + Vector3.DOWN * 0.9
			stalker.stream = STEPS[randi() % STEPS.size()]
			stalker.pitch_scale = randf_range(0.82, 0.92)
			stalker.play()
		return
	if not _inside_building(player):
		return
	steps_wait -= delta
	if steps_wait > 0.0:
		return
	steps_wait = randf_range(25.0, 45.0)
	if randf() > 0.35:
		return
	var back := player.global_basis.z
	stalker_from = player.global_position + Vector3(back.x, 0, back.z).normalized() * 3.4
	stalker_steps = randi_range(3, 6)
	stalker_clock = 0.3


func _inside_building(player: Node3D) -> bool:
	if road == null:
		return false
	for index in road.stops:
		var stop: Node3D = road.stops[index]
		if not stop.visible:
			continue
		var local := stop.to_local(player.global_position)
		if absf(local.x) < 3.1 and local.z > -2.7 and local.z < 4.0 and local.y < 3.0:
			return true
	return false
