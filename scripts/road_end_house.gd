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
	Shapes.tube(self, "Banister", Vector3(1.04, 0.99, 0.02), Vector3(1.04, 3.55, -3.42), 0.043, floorboards)
	for i in range(5):
		Shapes.box(self, "Baluster", Vector3(0.07, 0.9, 0.07), Vector3(1.04, 0.66 + i * 0.59, -0.10 - i * 0.80), floorboards)
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
	_speak(ANYBODY, "Anybody there?", creature.global_position + Vector3.UP * 2.4)
	sequence = create_tween()
	sequence.tween_interval(0.92)
	sequence.tween_callback(creature.show)
	_walk_to(Vector3(1.80, 0.0, 0.17), 3.65, 13)
	_walk_to(Vector3(0.92, 0.0, 0.94), 0.72, 2)
	var eye := to_local(player.camera.global_position)
	var near := Vector3(eye.x, 0, eye.z) + Vector3(0.07, 0, -0.43)
	_walk_to(near, 1.22, 3)
	sequence.tween_method(_lean, 0.0, 1.0, 0.46)
	sequence.tween_interval(0.46)
	sequence.tween_callback(_deliver_line)
	sequence.tween_interval(1.36)
	sequence.tween_callback(_show_end)


func _walk_to(destination: Vector3, duration: float, steps: int) -> void:
	sequence.tween_callback(_start_walk)
	sequence.tween_method(_advance_walk.bind(destination, steps), 0.0, 1.0, duration)


func _start_walk() -> void:
	walk_start = creature.position
	previous_step = -1


func _advance_walk(progress: float, destination: Vector3, steps: int) -> void:
	var index := mini(steps - 1, floori(progress * steps))
	creature.position = walk_start.lerp(destination, progress)
	if steps == 13:
		creature.position.y = floorf((1.0 - progress) * 13.0) * 0.207
	var direction := destination - walk_start
	if direction.length_squared() > 0.01:
		creature.rotation.y = atan2(direction.x, direction.z)
	creature.pose(progress * PI * steps, 0.8)
	var under_ceiling := smoothstep(1.69, 0.78, creature.position.x)
	creature.head.position.y = 2.12 - under_ceiling * 0.22
	if index != previous_step:
		previous_step = index
		footfall.global_position = creature.global_position
		footfall.pitch_scale = 0.89 + (index % 4) * 0.045
		footfall.stream = STEP
		footfall.play()
	var focus := creature.global_position + Vector3.UP * 2.14
	player.aim_ending_camera(focus, 0.17 if progress < 0.5 else 0.23)


func _lean(amount: float) -> void:
	var marker: Vector3 = player.camera.global_position
	var origin := creature.global_position
	creature.rotation.y = atan2(marker.x - origin.x, marker.z - origin.z) - global_rotation.y
	creature.pose(0, 0)
	creature.head.position.y = lerpf(1.90, to_local(marker).y - 0.24, amount)
	creature.head.rotation.x = -0.17 * amount
	creature.jaw.rotation.x = 0.48 * amount
	player.aim_ending_camera(creature.head.global_position + Vector3.UP * 0.24, amount)
	if amount > 0.35 and not creature.has_node("FaceFill"):
		var fill := OmniLight3D.new()
		fill.name = "FaceFill"
		fill.light_color = Color("#e1d1cd")
		fill.light_energy = 0.83
		fill.omni_range = 1.6
		creature.add_child(fill)
		fill.global_position = marker


func _deliver_line() -> void:
	_speak(TRICKED, "Tricked you too.", creature.jaw.global_position)
	var speech := create_tween()
	speech.tween_method(func(at: float) -> void:
		creature.jaw.rotation.x = 0.39 + 0.19 * absf(sin(at * 17.0)), 0.0, 1.08, 1.08)


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
