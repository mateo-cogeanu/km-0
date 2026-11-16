extends Node
## Small wrong things along the road, long before the house.
## - At night, a tall figure sometimes stands far out in the desert ahead. Look
##   straight at it, or get close, and it is gone.
## - Inside the roadside buildings, now and then, footsteps behind you that
##   stop the moment you turn round.

const MODEL := preload("res://assets/characters/player.glb")
const Notes := preload("res://scripts/story_notes.gd")
const RoadEndHouse := preload("res://scripts/road_end_house.gd")
const Style := preload("res://scripts/menu_style.gd")
## How far back past the start of the road the calls come, and where you are free.
const CALL_AT := [1400.0, 1700.0]
const FREE_AT := 1950.0
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
var calls_made := 0
var escaping := false
var caller: AudioStreamPlayer3D


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
	_way_out(player)


func _storm() -> float:
	var weather := get_parent().get_node_or_null("Weather") if get_parent() else null
	return weather.storm_level() if weather else 0.0


func _daylight() -> float:
	var cycle := get_tree().current_scene.get_node_or_null("DayNightCycle") if get_tree().current_scene else null
	return cycle.daylight if cycle and "daylight" in cycle else 1.0


func _watch_figure(delta: float, player: Node3D, camera: Camera3D) -> void:
	if figure.visible:
		figure_life -= delta
		var toward := (figure.global_position + Vector3.UP * 1.6 - camera.global_position)
		var looked := camera.is_position_in_frustum(figure.global_position) and toward.normalized().dot(-camera.global_basis.z) > 0.993
		figure_seen = figure_seen + delta if looked else 0.0
		var close := toward.length() < (14.0 if _storm() > 0.6 else 45.0)
		var hidden_by_day := _daylight() > 0.3 and _storm() < 0.5
		if figure_seen > 0.15 or close or figure_life <= 0.0 or hidden_by_day:
			if not camera.is_position_in_frustum(figure.global_position) or figure_seen > 0.15 or close:
				figure.hide()
				figure_wait = randf_range(150.0, 320.0)
		return
	var storm := _storm()
	if _daylight() > 0.15 and storm < 0.6:
		return
	# In a dust storm it comes in the day too, and much closer.
	figure_wait -= delta * (3.0 if storm > 0.6 else 1.0)
	if figure_wait > 0.0 or road == null:
		return
	# Off to one side, well ahead along the road, facing the road.
	var ahead := player.global_position.z - (randf_range(28.0, 42.0) if storm > 0.6 else randf_range(85.0, 140.0))
	var side := -1.0 if randf() < 0.5 else 1.0
	var spot: Vector3 = road._sample(ahead, side * (randf_range(8.0, 14.0) if storm > 0.6 else randf_range(16.0, 34.0)))
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



func _way_out(player: Node3D) -> void:
	## Len's last page: go back past where the road starts and keep going,
	## whatever you hear behind you. Only for someone who read it, and who never
	## went into the house.
	if escaping or RoadEndHouse.seen or not Notes.read.has("len_last"):
		return
	var out := player.global_position.z
	if calls_made < CALL_AT.size() and out > CALL_AT[calls_made]:
		if caller == null:
			caller = AudioStreamPlayer3D.new()
			caller.unit_size = 6.0
			caller.max_distance = 80.0
			caller.volume_db = 3.0
			caller.bus = GameSettings.voice_bus()
			add_child(caller)
		var stream_path: String = ["res://assets/audio/ending/escape_wait.wav", "res://assets/audio/ending/escape_back.wav"][calls_made]
		caller.stream = load(stream_path)
		# Behind you, back the way you came.
		caller.global_position = player.global_position + Vector3(0, 1.0, -22.0)
		caller.play()
		calls_made += 1
	if out > FREE_AT:
		_escape(player)


func _escape(player: Node3D) -> void:
	escaping = true
	RoadEndHouse.story["escaped"] = true
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var white := ColorRect.new()
	white.color = Color(1, 0.98, 0.94, 0)
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(white)
	white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 22)
	card.modulate.a = 0.0
	layer.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for line: Array in [["You kept going.", 40], ["Past the workshop, past where the road began, the radio finally went quiet.", 20],
			["For the first time in days it was only the engine, and the wind, and nobody's voice but your own.", 20], ["THE END", 30]]:
		var label := Style.label(line[0], roundi(line[1] * GameSettings.ui_scale))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.add_theme_color_override("font_color", Color("#3a342c"))
		card.add_child(label)
	var button := Style.button("Main menu", roundi(22 * GameSettings.ui_scale))
	button.name = "EndButton"
	button.theme = Style.make_theme()
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func() -> void:
		TripSave.save_trip()
		get_tree().paused = false
		if NetworkManager.is_online():
			NetworkManager.leave_lobby()
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	card.add_child(button)
	var fade := create_tween()
	fade.tween_property(white, "color:a", 1.0, 5.0).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(func() -> void:
		AudioServer.set_bus_mute(0, false)
		if player.has_method("lock_for_ending"):
			player.lock_for_ending(player.global_position)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
	fade.tween_property(card, "modulate:a", 1.0, 2.0)
