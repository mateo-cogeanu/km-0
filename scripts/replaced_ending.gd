extends Node
## The third ending. After the house, at any station radio, you can answer it.
## What comes out of your mouth is the broadcast: the kettle's on, you should
## come out, and Mick's cough. Then somebody new answers on channel 4.

const RoadRadio := preload("res://scripts/road_radio.gd")
const RoadEndHouse := preload("res://scripts/road_end_house.gd")
const Style := preload("res://scripts/menu_style.gd")
const CLICK := preload("res://assets/audio/player/flashlight_click.wav")
const YOUR_WORDS := preload("res://assets/audio/radio/you.wav")
const COUGH := preload("res://assets/audio/radio/mick_cough.wav")
const REPLY := preload("res://assets/audio/ending/replaced_reply.wav")
const REPLY_LINES := [
	[0.0, "Voice on channel 4: Hello? ...Hello, I hear you."],
	[2.54, "Voice on channel 4: I've been listening for days. I thought nobody was out there."],
	[6.19, "Voice on channel 4: Okay. Okay. I'm coming out."],
]

var player: Node3D
var radio: Node3D
var mouth: AudioStreamPlayer
var speaker: AudioStreamPlayer3D
var captions: Array = []
var caption_player: Node
var layer: CanvasLayer
var caption_label: Label


func start(who: Node3D, at_radio: Node3D) -> void:
	player = who
	radio = at_radio
	RoadEndHouse.story["replaced"] = true
	player.lock_for_ending(player.global_position)
	radio.dial.emission_enabled = true
	mouth = AudioStreamPlayer.new()
	mouth.bus = GameSettings.voice_bus()
	add_child(mouth)
	speaker = AudioStreamPlayer3D.new()
	speaker.bus = RoadRadio._radio_bus()
	speaker.unit_size = 2.0
	add_child(speaker)
	speaker.global_position = radio.global_position
	_build_captions()
	_face_radio()
	var steps := create_tween()
	steps.tween_interval(1.4)
	# Key the mic.
	steps.tween_callback(_click.bind(-4.0))
	steps.tween_interval(0.5)
	steps.tween_callback(_speak.bind(mouth, YOUR_WORDS, _your_lines()))
	steps.tween_interval(YOUR_WORDS.get_length() + 0.3)
	steps.tween_callback(_click.bind(-8.0))
	steps.tween_callback(func() -> void: radio.carrier.play())
	steps.tween_interval(3.2)
	steps.tween_callback(func() -> void: radio.carrier.volume_db -= 6.0)
	steps.tween_callback(_speak.bind(speaker, REPLY, REPLY_LINES))
	steps.tween_interval(REPLY.get_length() + 2.2)
	steps.tween_callback(func() -> void: radio.carrier.stop())
	steps.tween_interval(1.0)
	# You don't say anything back. You cough.
	steps.tween_callback(_speak.bind(mouth, COUGH, [[0.0, "You: [Coughs]"]]))
	steps.tween_interval(COUGH.get_length() + 0.9)
	steps.tween_callback(_end_card)


func _your_lines() -> Array:
	## The broadcast's own captions, but every line is yours now.
	var lines: Array = []
	for entry: Array in RoadRadio.LINES[RoadRadio.Broadcast.YOU]:
		var text: String = entry[1]
		if text.begins_with("Mick: "):
			text = "You: " + text.substr(6)
		lines.append([entry[0], text])
	return lines


func _face_radio() -> void:
	var camera := player.get_viewport().get_camera_3d()
	var to_radio: Vector3 = radio.global_position - camera.global_position
	var yaw := atan2(-to_radio.x, -to_radio.z)
	var pitch := atan2(to_radio.y, Vector2(to_radio.x, to_radio.z).length())
	var turn := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var from_yaw: float = player.rotation.y
	yaw = from_yaw + wrapf(yaw - from_yaw, -PI, PI)
	turn.tween_property(player, "rotation:y", yaw, 1.6)
	turn.tween_property(player, "look_rotation_x", pitch, 1.6)
	turn.tween_property(player.head, "rotation:x", pitch, 1.6)


func _click(volume: float) -> void:
	var click := AudioStreamPlayer.new()
	click.stream = CLICK
	click.volume_db = volume
	click.pitch_scale = 0.7
	add_child(click)
	click.play()
	click.finished.connect(click.queue_free)


func _speak(on: Node, stream: AudioStream, lines: Array) -> void:
	on.stream = stream
	on.play()
	captions = lines
	caption_player = on


func _process(_delta: float) -> void:
	if caption_label == null:
		return
	var line := ""
	if caption_player and caption_player.playing:
		var at: float = caption_player.get_playback_position()
		for entry: Array in captions:
			if at >= entry[0]:
				line = entry[1]
	caption_label.text = line if GameSettings.subtitles else ""
	caption_label.get_parent().visible = not caption_label.text.is_empty()


func _build_captions() -> void:
	layer = CanvasLayer.new()
	layer.layer = 19
	add_child(layer)
	var panel := PanelContainer.new()
	panel.theme = Style.make_theme()
	panel.add_theme_stylebox_override("panel", Style.box(Style.SURFACE, Style.LINE, 10))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position.y -= 60.0 * GameSettings.ui_scale
	caption_label = Style.label("", roundi(17 * GameSettings.ui_scale))
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(caption_label)
	panel.hide()


func _end_card() -> void:
	caption_label = null
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 22)
	card.modulate.a = 0.0
	layer.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for line: Array in [["Somebody always comes.", 40],
			["Far back along the road, a pair of headlights turned toward the house at the end of it.", 20],
			["The kettle's on.", 20], ["THE END", 30]]:
		var label := Style.label(line[0], roundi(line[1] * GameSettings.ui_scale))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.add_theme_color_override("font_color", Color("#c9c2b4"))
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var fade := create_tween()
	fade.tween_interval(1.5)
	fade.tween_property(card, "modulate:a", 1.0, 2.5)
