extends Node3D

const Shapes := preload("res://scripts/prop_shapes.gd")
const Creature := preload("res://scripts/road_creature.gd")
const Style := preload("res://scripts/menu_style.gd")
const HELLO := preload("res://assets/audio/ending/hello.wav")
const ANYBODY := preload("res://assets/audio/ending/anybody.wav")
const TRICKED := preload("res://assets/audio/ending/tricked.wav")
const STEP := preload("res://assets/audio/ending/step.wav")

var boards := Shapes.material(Color("#675545"))
var floorboards := Shapes.material(Color("#504236"))
var plaster := Shapes.material(Color("#7c7162"))
var dark := Shapes.material(Color("#292524"))
var player: Node3D
var creature: Node3D
var voice: AudioStreamPlayer3D
var footfall: AudioStreamPlayer3D
var sequence: Tween
var overlay: CanvasLayer
var caption: Label
var looked := false
var previous_step := -1
var walk_start := Vector3.ZERO
var last_palms: Array[Vector3] = []
var last_feet: Array[Vector3] = []
var last_shoulders := Vector3.ZERO
var last_pelvis := Vector3.ZERO


func _ready() -> void:
	_build_house()
	var trigger := Area3D.new()
	trigger.name = "EntryTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 4
	add_child(trigger)
	trigger.position = Vector3(0, 1.0, 2.04)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.32, 2.1, 1.15)
	shape.shape = box
	trigger.add_child(shape)
	trigger.body_entered.connect(_on_entry)


func _build_house() -> void:
	Shapes.box(self, "Floor", Vector3(7.2, 0.18, 7.5), Vector3(0, -0.09, 0), floorboards, true)
	for plank in range(22):
		Shapes.box(self, "FloorSeam", Vector3(0.012, 0.003, 7.38), Vector3(-3.45 + plank * 0.32, 0.002, 0), dark)
	_wall(Vector3(0, 2.62, -3.66), Vector3(7.25, 5.24, 0.23))
	for side in [-1.0, 1.0]:
		_wall(Vector3(side * 3.53, 2.62, 0), Vector3(0.24, 5.24, 7.4))
		_wall(Vector3(side * 2.18, 1.34, 3.65), Vector3(2.78, 2.68, 0.26))
		for y in [1.28, 3.56]:
			Shapes.box(self, "WindowFrame", Vector3(1.02, 0.91, 0.14), Vector3(side * 2.04, y, 3.8), floorboards)
			Shapes.box(self, "DarkWindow", Vector3(0.82, 0.70, 0.034), Vector3(side * 2.04, y, 3.89), dark)
			Shapes.box(self, "Mullion", Vector3(0.027, 0.71, 0.034), Vector3(side * 2.04, y, 3.915), boards)
		var roof := Shapes.box(self, "Roof", Vector3(4.07, 0.18, 7.94), Vector3(side * 1.94, 5.51, 0), dark)
		roof.rotation.z = -side * 0.23
	_wall(Vector3(0, 3.79, 3.65), Vector3(7.20, 2.90, 0.26))
	Shapes.box(self, "Ceiling", Vector3(7.14, 0.16, 7.4), Vector3(0, 5.22, 0), dark)
	Shapes.box(self, "Porch", Vector3(3.15, 0.13, 1.54), Vector3(0, -0.071, 4.35), floorboards, true)
	for x in [-0.805, 0.805]:
		Shapes.box(self, "DoorJamb", Vector3(0.12, 2.58, 0.27), Vector3(x, 1.27, 3.65), floorboards)
	for y in [2.78, 5.04]:
		Shapes.box(self, "FrontSidingTrim", Vector3(7.27, 0.072, 0.060),
			Vector3(0, y, 3.802), boards)
	for side in [-1.0, 1.0]:
		for i in range(18):
			Shapes.box(self, "ClapboardSeam", Vector3(2.73, 0.011, 0.028),
				Vector3(side * 2.18, 0.28 * (i + 1), 3.785), boards)
		Shapes.box(self, "PorchPost", Vector3(0.145, 2.50, 0.145), Vector3(side * 1.47, 1.25, 4.99), boards)
	Shapes.box(self, "PorchRoof", Vector3(3.22, 0.14, 1.56), Vector3(0, 2.51, 4.43), dark)
	var open_door := Shapes.box(self, "OpenDoor", Vector3(1.44, 2.43, 0.08), Vector3(-0.956, 1.22, 3.12), boards)
	open_door.rotation.y = -1.30
	var stair_mat := Shapes.material(Color("#665346"))
	for i in range(13):
		var height := 0.207 * (i + 1)
		Shapes.box(self, "Stair", Vector3(1.41, height, 0.282), Vector3(1.80, height * 0.5, -0.10 - i * 0.27), stair_mat, true)
	Shapes.box(self, "Landing", Vector3(2.04, 0.18, 0.42), Vector3(1.67, 2.61, -3.43), floorboards, true)
	Shapes.box(self, "UpperFloor", Vector3(4.13, 0.16, 7.27), Vector3(-1.42, 2.61, 0), floorboards, true)
	_wall(Vector3(0.97, 1.5, -1.81), Vector3(0.14, 3.0, 3.55))
	_wall(Vector3(2.62, 2.4, -1.81), Vector3(0.14, 4.8, 3.55))
	Shapes.box(self, "StairTrim", Vector3(0.16, 0.14, 3.57), Vector3(0.97, 3.04, -1.81), boards)
	Shapes.box(self, "BareTable", Vector3(1.24, 0.078, 0.72), Vector3(-2.23, 0.79, -1.35), floorboards, true)
	for x in [-2.75, -1.71]:
		for z in [-1.61, -1.09]:
			Shapes.box(self, "TableLeg", Vector3(0.068, 0.74, 0.066), Vector3(x, 0.371, z), floorboards)
	_lamp(Vector3(-1.7, 2.29, 1.31), 0.72, 4.9)
	_lamp(Vector3(2.45, 2.82, -1.94), 0.46, 4.7)


func _wall(at: Vector3, size: Vector3) -> void:
	Shapes.box(self, "Wall", size, at, plaster, true)


func _lamp(at: Vector3, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color("#eed8b9")
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = true
	add_child(light)
	light.position = at


func _on_entry(body: Node3D) -> void:
	if looked or not body.is_in_group("local_player") or body.active_vehicle:
		return
	looked = true
	player = body
	player.lock_for_ending(to_global(Vector3(0, 1.03, 5.62)))
	var world_environment := get_tree().current_scene.get_node("WorldEnvironment") as WorldEnvironment
	var interior := world_environment.environment.duplicate() as Environment
	interior.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	interior.ambient_light_color = Color("#a6a7b4")
	interior.ambient_light_energy = 0.24
	player.camera.environment = interior
	_build_overlay()
	creature = Creature.new()
	add_child(creature)
	creature.position = Vector3(1.80, 2.70, -3.36)
	creature.hide()
	voice = _speaker(2.4)
	footfall = _speaker(4.5)
	sequence = create_tween()
	sequence.tween_interval(0.65)
	sequence.tween_callback(_speak.bind(HELLO, "Hello? Anybody there?", player.camera.global_position + player.camera.global_basis.z * 0.15))
	sequence.tween_interval(2.87)
	sequence.tween_callback(_begin_descent)


func _begin_descent() -> void:
	_speak(ANYBODY, "Anybody there?", creature.global_position + Vector3.UP * 1.15)
	sequence = create_tween()
	sequence.tween_interval(0.92)
	sequence.tween_callback(creature.show)
	sequence.tween_method(_descend, 0.0, 1.0, 4.25)
	sequence.tween_callback(_start_crawl)
	sequence.tween_method(_crawl, 0.0, 1.0, 2.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sequence.tween_method(_lean, 0.0, 1.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sequence.tween_method(_hold_face.bind(false), 0.0, 0.45, 0.45)
	sequence.tween_callback(_deliver_line)
	sequence.tween_method(_hold_face.bind(true), 0.0, 1.36, 1.36)
	sequence.tween_callback(_show_end)


func _descend(progress: float) -> void:
	var stride := progress * 7.0
	var center_z := lerpf(-3.04, -0.14, progress)
	var floor_y := maxf(0.0, (0.042 - center_z) / 0.27 * 0.207)
	creature.position = Vector3(1.80, floor_y, center_z)
	var palms: Array[Vector3] = []
	var normals: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT]
	var feet: Array[Vector3] = []
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var phase := stride + i * 0.5
		var reach := _contact(phase)
		var point_z := clampf(-3.02 + (reach + 0.84) * 0.42, -3.3, -0.05)
		var plant_height := _stair_height(point_z) + 0.91
		var wall_x := 1.04 if i == 0 else 2.55
		var lift := _swing(phase)
		palms.append(Vector3(wall_x - side * lift * 0.16, plant_height + lift * 0.20, point_z))
		var foot_z := clampf(-3.38 + (_contact(phase + 0.5) + 0.38) * 0.42, -3.42, 0.12)
		feet.append(Vector3(1.80 + side * 0.26, _stair_height(foot_z) + _swing(phase + 0.5) * 0.11, foot_z))
	var shoulders := Vector3(1.80, floor_y + 0.98 + sin(stride * TAU) * 0.043, center_z + 0.26)
	var pelvis := Vector3(1.80, floor_y + 0.71, center_z - 0.48)
	_pose(shoulders, pelvis, palms, normals, feet, progress * 3.65)
	_play_contact(stride * 2.0, palms[mini(1, floori(stride * 2.0) % 2)], 0.76)


func _stair_height(z: float) -> float:
	return 0.0 if z > 0.042 else clampf(floorf((0.041 - z) / 0.27) + 1.0, 1.0, 13.0) * 0.207


func _start_crawl() -> void:
	walk_start = creature.position
	previous_step = -1


func _crawl(progress: float) -> void:
	var eye := to_local(player.camera.global_position)
	var end := Vector3(eye.x, 0, eye.z - 1.03)
	var bend := Vector3(1.42, 0, 0.66)
	var start := Vector3(walk_start.x, 0, walk_start.z)
	var at := start.lerp(bend, progress).lerp(bend.lerp(end, progress), progress)
	var forward := (bend - start).lerp(end - bend, progress).normalized()
	var strides := progress * 4.0
	creature.position = at
	var palms: Array[Vector3] = []
	var normals: Array[Vector3] = [Vector3.UP, Vector3.UP]
	var feet: Array[Vector3] = []
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var phase := strides + i * 0.5
		var hand_progress := clampf((_contact(phase) + 0.12) / 4.0, 0, 1)
		var hand_path := start.lerp(bend, hand_progress).lerp(bend.lerp(end, hand_progress), hand_progress)
		var foot_progress := clampf((_contact(phase + 0.5) - 0.42) / 4.0, 0, 1)
		var foot_path := start.lerp(bend, foot_progress).lerp(bend.lerp(end, foot_progress), foot_progress)
		var hand_forward := ((bend - start).lerp(end - bend, hand_progress)).normalized()
		var hand_right := Vector3.UP.cross(hand_forward)
		var palm := hand_path + hand_forward * 0.37 + hand_right * side * 0.39 + Vector3.UP * (_swing(phase) * 0.18)
		var stair_palm := Vector3(1.04 if i == 0 else 2.55, 1.06, -0.05)
		var settle := smoothstep(0.0, 0.24, progress + float(i) * 0.03)
		palms.append(stair_palm.lerp(palm, settle))
		normals[i] = Vector3(-side, 0, 0).lerp(Vector3.UP, settle)
		var foot_forward := ((bend - start).lerp(end - bend, foot_progress)).normalized()
		var foot := foot_path - foot_forward * 0.51 + Vector3.UP.cross(foot_forward) * side * 0.32
		foot.y = (_stair_height(foot.z) if foot.x > 1.07 and foot.x < 2.52 else 0.0) + _swing(phase + 0.5) * 0.13
		feet.append(foot)
	var shoulders := at + forward * 0.16 + Vector3.UP * (0.70 + sin(strides * TAU) * 0.026)
	var pelvis := at - forward * 0.58 + Vector3.UP * 0.62
	last_palms = palms
	last_feet = feet
	last_shoulders = shoulders
	last_pelvis = pelvis
	_pose(shoulders, pelvis, palms, normals, feet, 3.65 + progress * 2.10)
	_play_contact(strides * 2.0, palms[floori(strides * 2.0) % 2], 0.96)


func _contact(phase: float) -> float:
	return floorf(phase) + smoothstep(0.58, 1.0, fposmod(phase, 1.0))


func _swing(phase: float) -> float:
	return sin(clampf((fposmod(phase, 1.0) - 0.58) / 0.42, 0.0, 1.0) * PI)


func _play_contact(phase: float, point: Vector3, pitch: float) -> void:
	var index := floori(phase)
	if index == previous_step:
		return
	previous_step = index
	footfall.global_position = to_global(point)
	footfall.pitch_scale = pitch + index % 4 * 0.055
	footfall.stream = STEP
	footfall.play()


func _pose(shoulders: Vector3, pelvis: Vector3, palms: Array[Vector3], normals: Array[Vector3], feet: Array[Vector3],
		elapsed: float, reveal: float = 0.0) -> void:
	var eye := to_local(player.camera.global_position)
	var local_palms: Array[Vector3] = [palms[0] - creature.position, palms[1] - creature.position]
	var local_feet: Array[Vector3] = [feet[0] - creature.position, feet[1] - creature.position]
	creature.pose_contacts(shoulders - creature.position, pelvis - creature.position, eye - creature.position,
		local_palms, normals, local_feet, elapsed, reveal)
	player.aim_ending_camera(creature.head.global_position + Vector3.UP * 0.22, 0.2)


func _lean(amount: float) -> void:
	_final_pose(amount, amount * 0.52)
	creature.jaw.position.y = -0.006 * amount
	if amount > 0.35 and not creature.has_node("FaceFill"):
		var fill := OmniLight3D.new()
		fill.name = "FaceFill"
		fill.light_color = Color("#e1d1cd")
		fill.light_energy = 0.64
		fill.omni_range = 1.6
		creature.add_child(fill)
		fill.global_position = player.camera.global_position


func _final_pose(amount: float, elapsed: float) -> void:
	var eye := to_local(player.camera.global_position)
	var shoulders := last_shoulders.lerp(eye + Vector3(0, -0.40, -0.82), amount)
	var pelvis := last_pelvis.lerp(last_pelvis + Vector3.UP * 0.12, amount)
	var normals: Array[Vector3] = [Vector3.UP, Vector3.UP]
	_pose(shoulders, pelvis, last_palms, normals, last_feet, 5.75 + elapsed, amount)


func _hold_face(elapsed: float, speaking: bool) -> void:
	_final_pose(1.0, elapsed + (0.97 if speaking else 0.52))
	var opening := maxf(0.0, sin(elapsed * 19.0)) * exp(-elapsed * 0.82)
	creature.jaw.position.y = -0.003 - 0.007 * opening if speaking else -0.006


func _deliver_line() -> void:
	_speak(TRICKED, "Tricked you too.", creature.jaw.global_position)


func _speaker(distance: float) -> AudioStreamPlayer3D:
	var speaker := AudioStreamPlayer3D.new()
	speaker.unit_size = distance
	speaker.max_distance = 14.0
	speaker.volume_db = 1.0
	add_child(speaker)
	return speaker


func _speak(stream: AudioStream, line: String, at: Vector3) -> void:
	voice.global_position = at
	voice.stream = stream
	voice.play()
	caption.text = line
	var timer := get_tree().create_timer(stream.get_length(), false)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(caption) and caption.text == line:
			caption.text = "")


func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 8
	add_child(overlay)
	caption = Style.label("", roundi(22 * GameSettings.ui_scale))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_constant_override("outline_size", 6)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	overlay.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_left = 16
	caption.offset_right = -16
	caption.offset_top = -100
	caption.offset_bottom = -30


func _show_end() -> void:
	var black := ColorRect.new()
	black.color = Color.BLACK
	overlay.add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.hide()
	var button := Style.button("Main menu", roundi(23 * GameSettings.ui_scale))
	button.theme = Style.make_theme()
	black.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	button.offset_left = -98 * GameSettings.ui_scale
	button.offset_right = 98 * GameSettings.ui_scale
	button.offset_top = -25 * GameSettings.ui_scale
	button.offset_bottom = 25 * GameSettings.ui_scale
	button.pressed.connect(_return_to_menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	button.grab_focus()


func _return_to_menu() -> void:
	if not TripSave.save_trip():
		var dialog := AcceptDialog.new()
		dialog.dialog_text = "Could not save your trip. Check available disk space and try again."
		overlay.add_child(dialog)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered()
		return
	get_tree().paused = false
	if NetworkManager.is_online():
		NetworkManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
