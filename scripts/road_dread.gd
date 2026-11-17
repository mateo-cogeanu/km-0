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
const Cinematic := preload("res://scripts/ending_cinematic.gd")
## The way out, for someone with all of Len's pages who never went into the
## house: back past the start and on into the desert for twelve kilometres.
## Your own voice calls after you the whole way, a storm comes in, and halfway
## out a wheel comes off. Then it comes for you, and you have until it arrives
## to put the wheel back on.
const PAGES := ["len_last", "len_page_tower", "len_page_cabin"]
const CALLS := [
	[1400.0, "res://assets/audio/ending/escape_wait.wav", 1.0],
	[1700.0, "res://assets/audio/ending/escape_back.wav", 1.0],
	[2700.0, "res://assets/audio/ending/anybody.wav", 1.0],
	[4200.0, "res://assets/audio/ending/hello.wav", 0.94],
	[5600.0, "res://assets/audio/ending/escape_wait.wav", 0.9],
	[8200.0, "res://assets/audio/radio/you.wav", 1.0],
	[9800.0, "res://assets/audio/ending/escape_back.wav", 0.86],
	[11000.0, "res://assets/audio/radio/mick_cough.wav", 1.0],
]
const STORM_AT := 3200.0
const BREAKDOWN_AT := 6300.0
const FREE_AT := 12000.0
## How far behind it starts when the wheel comes off, and how fast it comes.
const CHASE_START := 140.0
const CHASE_SPEED := 3.2
const CHASE_SPEED_DRIVING := 13.0
const CAUGHT_AT := 2.2
const STEP_SOUND := preload("res://assets/audio/ending/step.wav")
const Creature := preload("res://scripts/road_creature.gd")
const CLICKS := preload("res://assets/audio/ending/rapid_clicks.wav")
const RATTLE := preload("res://assets/audio/ending/throat_rattle.wav")
const BREATH := preload("res://assets/audio/ending/breath_close.wav")
const HIT := preload("res://assets/audio/ending/hit.wav")
const MICK_COUGH := preload("res://assets/audio/radio/mick_cough.wav")
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
var stormed := false
var broke_down := false
var chasing := false
var chaser: Node3D
var chaser_step := 0.0
var chaser_breath: AudioStreamPlayer3D
var chaser_feet: AudioStreamPlayer3D
var chaser_clicks: AudioStreamPlayer3D
var gait := 0.0
var chase_clock := 0.0
var caught := false


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



func way_out_open() -> bool:
	if RoadEndHouse.seen or RoadEndHouse.story.get("caught", false):
		return false
	for page: String in PAGES:
		if not Notes.read.has(page):
			return false
	return true


func _way_out(player: Node3D) -> void:
	## Len's pages, put together: go back past where the road starts and keep
	## going, whatever you hear behind you.
	if escaping or caught or not way_out_open():
		return
	var out := player.global_position.z
	if calls_made < CALLS.size() and out > CALLS[calls_made][0]:
		if caller == null:
			caller = AudioStreamPlayer3D.new()
			caller.unit_size = 6.0
			caller.max_distance = 90.0
			caller.volume_db = 3.0
			caller.bus = GameSettings.voice_bus()
			add_child(caller)
		var call: Array = CALLS[calls_made]
		caller.stream = load(call[1])
		caller.pitch_scale = call[2]
		# Behind you, back the way you came.
		caller.global_position = player.global_position + Vector3(randf_range(-8.0, 8.0), 1.0, -24.0)
		caller.play()
		calls_made += 1
	if out > STORM_AT and not stormed:
		stormed = true
		var weather := get_parent().get_node_or_null("Weather") if get_parent() else null
		if weather and weather.has_method("start_storm"):
			weather.start_storm(220.0)
	if out > BREAKDOWN_AT and not broke_down:
		_break_down(player)
	if chasing:
		_chase(player, get_process_delta_time())
	if out > FREE_AT:
		_stop_chase()
		_escape(player)


func _break_down(player: Node3D) -> void:
	## Halfway out, a front wheel comes off. On foot, it simply starts coming.
	broke_down = true
	var car: Node3D = player.active_vehicle if is_instance_valid(player.active_vehicle) else null
	if car and "removable_parts" in car and car.removable_parts.has("wheel_fl"):
		var area: Area3D = car.removable_parts["wheel_fl"].get("area")
		var wheel: RigidBody3D = car.remove_installed_part(area, true) if area else null
		if wheel:
			wheel.apply_central_impulse(car.global_basis.x * -6.0 + Vector3.UP * 2.0)
		player.tip_override = "A wheel has come off. Get out and put it back on. Quickly."
		player.tip_time = 8.0
	_start_chase(player)


func _start_chase(player: Node3D) -> void:
	## The thing from the house, out in the open, coming on all fours.
	chasing = true
	chaser = Creature.new()
	chaser.name = "Chaser"
	add_child(chaser)
	chaser.jitter = 0.7
	chaser.tilt = 0.35
	chaser.elbow_flip[0] = 0.65
	chaser.elbow_flip[1] = 0.25
	var behind: Vector3 = player.global_position + Vector3(0, 0, -CHASE_START)
	chaser.global_position = Vector3(behind.x, _ground(behind.z), behind.z)
	chaser_feet = AudioStreamPlayer3D.new()
	chaser_feet.stream = STEP_SOUND
	chaser_feet.unit_size = 5.0
	chaser_feet.volume_db = -1.0
	chaser.add_child(chaser_feet)
	chaser_clicks = AudioStreamPlayer3D.new()
	chaser_clicks.stream = CLICKS
	chaser_clicks.unit_size = 6.0
	chaser_clicks.volume_db = -4.0
	chaser.add_child(chaser_clicks)
	chaser_breath = AudioStreamPlayer3D.new()
	chaser_breath.stream = RATTLE
	chaser_breath.unit_size = 5.0
	chaser.add_child(chaser_breath)
	chaser_breath.position.y = 0.6


func _ground(z: float) -> float:
	## The desert floor past the start of the road, or the road itself.
	return road._sample(z, 0.0).y if road and z < 9.0 else -0.041


func _chase(player: Node3D, delta: float) -> void:
	if chaser == null:
		return
	chase_clock += delta
	var target := player.global_position
	var flat := Vector3(target.x - chaser.global_position.x, 0, target.z - chaser.global_position.z)
	var distance := flat.length()
	var driving: bool = is_instance_valid(player.active_vehicle) and player.active_vehicle.linear_velocity.length() > 6.0
	var speed := CHASE_SPEED_DRIVING if driving else CHASE_SPEED
	# It speeds up the closer it gets.
	speed *= 1.0 + clampf((40.0 - distance) / 40.0, 0.0, 1.0) * 0.8
	var step := flat.normalized() * minf(speed * delta, distance)
	chaser.global_position += step
	chaser.global_position.y = _ground(chaser.global_position.z)
	chaser.rotation.y = lerp_angle(chaser.rotation.y, atan2(flat.x, flat.z), 1.0 - exp(-8.0 * delta))
	_gallop(player, speed, delta)
	if distance < 70.0 and not chaser_clicks.playing:
		chaser_clicks.pitch_scale = randf_range(0.85, 1.15)
		chaser_clicks.play()
	if distance < 18.0 and not chaser_breath.playing:
		chaser_breath.play()
	if distance < CAUGHT_AT:
		_caught(player)
	elif distance > CHASE_START * 3.0:
		# Left behind. It will not catch a car that keeps going.
		_stop_chase()


func _gallop(player: Node3D, speed: float, delta: float) -> void:
	## A broken, bounding run on all fours: hands and feet land in an uneven
	## rhythm, the back pitches with each bound, and the head stays fixed on you.
	var stride := 1.5 + speed * 0.06
	var before := gait
	gait = fposmod(gait + speed * delta / stride, 1.0)
	var reach := clampf(speed / 6.0, 0.25, 0.75) * 0.5
	# Front pair a little apart, the back pair half a stride behind them.
	var limbs := [[0.0, -0.24, 0.62], [0.11, 0.24, 0.62], [0.5, -0.2, -0.36], [0.63, 0.2, -0.36]]
	var points: Array[Vector3] = []
	for limb: Array in limbs:
		var phase := fposmod(gait + limb[0], 1.0)
		var along: float
		var lift := 0.0
		if phase < 0.42:
			along = lerpf(reach, -reach, phase / 0.42)
		else:
			var swing := (phase - 0.42) / 0.58
			along = lerpf(-reach, reach, swing)
			lift = sin(swing * PI) * (0.18 + reach * 0.4)
		points.append(Vector3(limb[1], lift, limb[2] + along))
		# A slap on the ground as each one lands.
		if fposmod(before + limb[0], 1.0) > 0.9 and phase < 0.1 and speed > 2.0:
			chaser_feet.pitch_scale = randf_range(0.55, 0.8)
			chaser_feet.play()
	var bound := sin(gait * TAU)
	var shoulders := Vector3(0, 0.62 + bound * 0.07 * reach * 2.0, 0.38)
	var pelvis := Vector3(0, 0.56 - bound * 0.06 * reach * 2.0, -0.36)
	var eye: Vector3 = chaser.to_local(player.camera.global_position) if "camera" in player else Vector3(0, 1.6, 4)
	var palms: Array[Vector3] = [points[0], points[1]]
	var feet: Array[Vector3] = [points[2], points[3]]
	var up: Array[Vector3] = [Vector3.UP, Vector3.UP]
	chaser.pose_contacts(shoulders, pelvis, eye, palms, up, feet, chase_clock, 0.0, up)
	chaser.set_eyes(5.0, 1.0)


func PlayerBodyFeet() -> float:
	return 1.025


func _stop_chase() -> void:
	chasing = false
	if chaser:
		chaser.queue_free()
		chaser = null


func _caught(player: Node3D) -> void:
	## It caught up. You come to at the workshop, and you are not you any more:
	## the way out is closed, and the radio will soon have a new voice on it.
	caught = true
	_stop_chase()
	RoadEndHouse.story["caught"] = true
	RoadEndHouse.seen = true
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hit := AudioStreamPlayer.new()
	hit.stream = HIT
	hit.volume_db = -2.0 if not GameSettings.reduce_scares else -14.0
	layer.add_child(hit)
	hit.play()
	var words := Style.label("It caught up.", roundi(34 * GameSettings.ui_scale))
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_theme_color_override("font_color", Color("#c9c2b4"))
	words.modulate.a = 0.0
	layer.add_child(words)
	words.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var steps := create_tween()
	steps.tween_interval(1.6)
	steps.tween_property(words, "modulate:a", 1.0, 1.5)
	steps.tween_interval(2.5)
	steps.tween_callback(func() -> void:
		if is_instance_valid(player.active_vehicle) and player.has_method("_exit_vehicle"):
			player._exit_vehicle()
		if player.held_object and player.has_method("_drop_held_object"):
			player._drop_held_object()
		var vitals: Node = player.vitals if "vitals" in player else null
		var home: Vector3 = vitals.spawn_point if vitals else Vector3(0, 1.2, 0)
		player.global_position = home
		player.velocity = Vector3.ZERO
		var cough := AudioStreamPlayer.new()
		cough.stream = MICK_COUGH
		cough.bus = GameSettings.voice_bus()
		layer.add_child(cough)
		cough.play())
	steps.tween_property(words, "modulate:a", 0.0, 1.0)
	steps.tween_property(black, "color:a", 0.0, 2.5)
	steps.tween_callback(layer.queue_free)


func _escape(player: Node3D) -> void:
	escaping = true
	RoadEndHouse.story["escaped"] = true
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var white := ColorRect.new()
	white.color = Color(1, 0.98, 0.94, 0)
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(white)
	white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fade := create_tween()
	fade.tween_property(white, "color:a", 1.0, 5.0).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(func() -> void:
		if player.has_method("lock_for_ending"):
			player.lock_for_ending(player.global_position)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# Morning, somewhere past all of it.
		var cinematic: Control = Cinematic.create("free")
		layer.add_child(cinematic)
		var button := Style.button("Main menu", roundi(22 * GameSettings.ui_scale))
		button.name = "EndButton"
		button.theme = Style.make_theme()
		button.pressed.connect(func() -> void:
			TripSave.save_trip()
			get_tree().paused = false
			if NetworkManager.is_online():
				NetworkManager.leave_lobby()
			get_tree().change_scene_to_file("res://scenes/menu.tscn"))
		cinematic.set_card([["You kept going.", 40],
				["Past the workshop, past where the road began, the radio finally went quiet.", 20],
				["For the first time in days it was only the engine, and the wind, and nobody's voice but your own.", 20],
				["THE END", 30]], button)
		white.queue_free())
