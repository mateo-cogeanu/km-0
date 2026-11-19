extends Node3D
## A cabin back the way you came, past where the road starts. Someone who
## followed the radio before you is holed up inside, and offers you a road
## flare. His lines and yours are pre-recorded by Sources/make_voices.py
## into assets/audio/stranger, named after the speaker and an MD5 of the line.

const Shapes := preload("res://scripts/prop_shapes.gd")
const PlayerBody := preload("res://scripts/player_body.gd")
const Supply := preload("res://scripts/supply_item.gd")
const Style := preload("res://scripts/menu_style.gd")
const DOOR_SOUND := preload("res://assets/audio/ending/door_open.wav")
const DOOR_RATTLE := preload("res://assets/audio/ending/door_rattle.wav")
const RoadEndHouse := preload("res://scripts/road_end_house.gd")
const Desert := preload("res://scripts/desert_models.gd")

const LOCATION := Vector3(46.0, 0.0, 660.0)
## The door faces back towards the road and the workshop.
const TURN := PI

## who ("him" or "you"), what is said, and an optional cue: "offer" holds out
## the flare; "cough" means the recording starts with a cough.
const MEETING := [
	["him", "Whoa. Easy. Stay where I can see you."],
	["you", "It's alright. I'm just driving."],
	["him", "Driving. Yeah. Following the radio, right? The voices on the radio."],
	["you", "How did you know?"],
	["him", "Because I did too. Mile after mile. They keep you going, right to the end of the road."],
	["him", "There's a house there. Lights on. I almost knocked."],
	["him", "Then I looked through the window."],
	["you", "What was in there?"],
	["him", "Something on the wall. Flat on the wall, like a spider. Smiling at me."],
	["him", "And it talked. In my voice. It called out in my own voice."],
	["him", "I ran. I don't know how far. I ended up here, and I haven't slept since.", "cough"],
	["him", "You're going there. I can see it on you. You can't help it."],
	["him", "So take this.", "offer"],
	["him", "A road flare. It's the only thing I ever saw it flinch from. When it comes close, light it. Don't wait."],
]
const TAKEN := [
	["you", "Thank you."],
	["him", "Don't thank me. Just don't look at its eyes."],
]
const REFUSED := [
	["you", "Keep it. You need it more than I do."],
	["him", "Your funeral. It'll be right here if you change your mind."],
]
const AGAIN_GIVEN := [
	["him", "Still here? Go on, then. I'm not going back there. Not ever.", "cough"],
]
## After you have been inside the house, he won't open the door.
const THROUGH_THE_DOOR := [
	["him", "Don't. Don't come in."],
	["him", "I saw you go in there. I watched from the ridge."],
	["him", "And you came back out."],
	["you", "It's me. I got out."],
	["him", "...Did you?"],
	["him", "Go away. Please. Just go away."],
]
const AGAIN_REFUSED := [
	["him", "Changed your mind?", "offer"],
]

var stranger: Node3D
var flare: RigidBody3D
var player: Node3D
var lines: Array = []
var line_index := -1
var choosing := false
var offering := false
var overlay: CanvasLayer
var caption: Label
var choices: HBoxContainer
var line_timer := 0.0
var mouth: AudioStreamPlayer3D
var ears: AudioStreamPlayer
var talk_spot: Area3D
var refused := false
var ask_after := false
var door_hinge: Node3D
var door_target: Area3D
var door_open := false


func _ready() -> void:
	_build_cabin()
	_build_stranger()
	_build_interior_light()
	_make_flare()
	mouth = AudioStreamPlayer3D.new()
	mouth.unit_size = 3.0
	mouth.volume_db = 2.0
	mouth.bus = GameSettings.voice_bus()
	add_child(mouth)
	ears = AudioStreamPlayer.new()
	ears.bus = GameSettings.voice_bus()
	ears.volume_db = -2.0
	add_child(ears)


func _build_cabin() -> void:
	var planks := Shapes.material(Color("#5e4a38"))
	var dark := Shapes.material(Color("#2a2420"))
	var floor_wood := Shapes.material(Color("#4a3c2f"))
	# Flush with the ground, so there is no step at the door.
	Shapes.box(self, "Floor", Vector3(5.2, 0.12, 4.2), Vector3(0, -0.09, 0), floor_wood, true)
	Shapes.box(self, "BackWall", Vector3(5.2, 2.6, 0.14), Vector3(0, 1.3, -2.05), planks, true)
	for side in [-1.0, 1.0]:
		Shapes.box(self, "SideWall", Vector3(0.14, 2.6, 4.2), Vector3(side * 2.55, 1.3, 0), planks, true)
		# The front, either side of a doorway wide and tall enough to walk through.
		Shapes.box(self, "FrontWall", Vector3(1.9, 2.6, 0.14), Vector3(side * 1.6, 1.3, 2.05), planks, true)
	Shapes.box(self, "Lintel", Vector3(1.3, 0.2, 0.14), Vector3(0, 2.5, 2.05), planks, true)
	_build_door(planks, dark)
	for i in range(9):
		for side in [-1.0, 1.0]:
			Shapes.box(self, "Seam", Vector3(0.02, 2.6, 0.02), Vector3(side * 2.63, 1.3, -1.9 + i * 0.47), dark)
	for side in [-1.0, 1.0]:
		var roof := Shapes.box(self, "Roof", Vector3(3.2, 0.12, 4.8), Vector3(side * 1.38, 3.05, 0), dark, true)
		roof.rotation.z = -side * 0.42
	for z in [-2.05, 2.05]:
		var gable := SurfaceTool.new()
		gable.begin(Mesh.PRIMITIVE_TRIANGLES)
		for corner in [Vector3(-2.6, 2.6, z), Vector3(2.6, 2.6, z), Vector3(0, 3.66, z)]:
			gable.add_vertex(corner)
		var mesh := MeshInstance3D.new()
		mesh.set_meta("piece", "Gable")
		mesh.mesh = gable.commit()
		var both := planks.duplicate() as StandardMaterial3D
		both.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material_override = both
		add_child(mesh)
	# A window glowing warm at night, half boarded up.
	var glow := Shapes.material(Color("#f2c27a"))
	glow.emission_enabled = true
	glow.emission = Color("#e8a85a")
	glow.emission_energy_multiplier = 1.4
	Shapes.box(self, "Window", Vector3(0.03, 0.7, 0.9), Vector3(-2.62, 1.45, -0.4), glow)
	for tilt in [0.5, -0.4]:
		var board := Shapes.box(self, "Board", Vector3(0.03, 0.12, 1.1), Vector3(-2.64, 1.45, -0.4), planks)
		board.rotation.x = tilt
	Shapes.box(self, "FrontWindow", Vector3(0.6, 0.5, 0.03), Vector3(1.6, 1.5, 2.13), glow)
	# The Blender cabin over the code-built walls, which stay for collision.
	Desert.hide_boxes(self, ["BackWall", "SideWall", "FrontWall", "Lintel", "Seam", "Roof", "Gable", "Board"])
	var dressing := Desert.model("cabin")
	dressing.name = "Dressing"
	add_child(dressing)
	for child in get_children():
		if child is MeshInstance3D and Desert.piece(child) == "Floor":
			child.material_override = Desert.material("Floor")
	Desert.solid(self, Vector3(0.55, 0.65, 0.45), Vector3(0.75, 0.33, -1.66))
	# Inside: table, chair, cot, lamp, a radio, empties.
	Shapes.box(self, "Table", Vector3(1.2, 0.06, 0.75), Vector3(-1.2, 0.78, -1.2), planks, true)
	for x in [-1.72, -0.68]:
		for z in [-1.5, -0.9]:
			Shapes.box(self, "TableLeg", Vector3(0.05, 0.76, 0.05), Vector3(x, 0.39, z), dark)
	Shapes.box(self, "Chair", Vector3(0.42, 0.05, 0.42), Vector3(-1.2, 0.46, -0.45), planks, true)
	Shapes.box(self, "ChairBack", Vector3(0.42, 0.5, 0.04), Vector3(-1.2, 0.72, -0.25), planks)
	Shapes.box(self, "Cot", Vector3(0.75, 0.38, 1.9), Vector3(1.85, 0.2, -0.9), Shapes.material(Color("#55593f")), true)
	Shapes.box(self, "Blanket", Vector3(0.74, 0.05, 1.3), Vector3(1.85, 0.42, -0.6), Shapes.material(Color("#6a3a2f")))
	var scratched := preload("res://scripts/note_item.gd").new()
	scratched.note_id = "stranger_wall"
	scratched.position = Vector3(-0.95, 0.812, -1.0)
	scratched.rotation.y = 0.5
	add_child(scratched)
	# Len came through here too, and left the last piece of the way out.
	var folded := preload("res://scripts/note_item.gd").new()
	folded.note_id = "len_page_cabin"
	folded.position = Vector3(1.75, 0.395, -1.4)
	folded.rotation.y = -0.3
	add_child(folded)
	Shapes.box(self, "RadioCase", Vector3(0.34, 0.15, 0.2), Vector3(-1.45, 0.89, -1.35), Shapes.material(Color("#343a37"), 0.2))
	Shapes.box(self, "RadioDial", Vector3(0.14, 0.025, 0.01), Vector3(-1.5, 0.92, -1.245), glow)
	var bulb := Shapes.material(Color("#fff0d0"))
	bulb.emission_enabled = true
	bulb.emission = Color("#ffd9a0")
	bulb.emission_energy_multiplier = 2.5
	Shapes.cylinder(self, "LampBase", Vector3(-0.85, 0.85, -1.3), Vector3.UP, 0.06, 0.08, dark, 10)
	Shapes.cylinder(self, "LampBulb", Vector3(-0.85, 0.98, -1.3), Vector3.UP, 0.04, 0.09, bulb, 10)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffcf95")
	lamp.light_energy = 1.3
	lamp.omni_range = 7.0
	lamp.shadow_enabled = GameSettings.lamp_shadows()
	add_child(lamp)
	lamp.position = Vector3(-0.85, 1.1, -1.3)
	var tin := Shapes.material(Color("#8f8d88"), 0.75, 0.35)
	for spot in [Vector3(0.4, 0.13, 0.9), Vector3(-0.3, 0.13, 1.3), Vector3(1.2, 0.13, 0.4), Vector3(-1.9, 0.13, 0.6)]:
		var can := Shapes.cylinder(self, "EmptyCan", spot, Vector3.RIGHT, 0.042, 0.11, tin, 10)
		can.rotation.y = spot.x * 3.0


func _build_interior_light() -> void:
	## Inside, the sky doesn't reach: a dim, warm room lit by the lamp.
	var inside := Area3D.new()
	inside.name = "Inside"
	inside.collision_layer = 0
	inside.collision_mask = 4
	add_child(inside)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.9, 2.6, 3.9)
	shape.shape = box
	shape.position = Vector3(0, 1.3, 0)
	inside.add_child(shape)
	inside.body_entered.connect(func(body: Node3D) -> void:
		if body.is_in_group("local_player") and "camera" in body:
			var world := get_tree().current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
			if world:
				var room := world.environment.duplicate() as Environment
				room.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				room.ambient_light_color = Color("#8a7766")
				room.ambient_light_energy = 0.32
				room.ambient_light_sky_contribution = 0.0
				room.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
				body.camera.environment = room)
	inside.body_exited.connect(func(body: Node3D) -> void:
		if body.is_in_group("local_player") and "camera" in body and not body.ending_locked:
			body.camera.environment = null)


func _build_door(planks: Material, dark: Material) -> void:
	door_hinge = Node3D.new()
	door_hinge.name = "DoorHinge"
	add_child(door_hinge)
	door_hinge.position = Vector3(-0.64, 0, 2.05)
	Shapes.box(door_hinge, "Door", Vector3(1.26, 2.36, 0.06), Vector3(0.63, 1.2, 0), Desert.material("Wood"), true)
	for i in 7:
		Shapes.box(door_hinge, "DoorPlank", Vector3(0.008, 2.34, 0.065), Vector3(0.05 + i * 0.18, 1.2, 0), dark)
	for y in [0.45, 1.95]:
		Shapes.box(door_hinge, "DoorBrace", Vector3(1.2, 0.1, 0.02), Vector3(0.63, y, 0.04), dark)
	Shapes.cylinder(door_hinge, "Knob", Vector3(1.12, 1.05, 0.06), Vector3.BACK, 0.035, 0.05, Shapes.material(Color("#7a6a4a"), 0.5, 0.4))
	door_target = Area3D.new()
	door_target.collision_layer = 8
	door_target.collision_mask = 0
	door_target.add_to_group("cabin_door")
	door_hinge.add_child(door_target)
	var hitbox := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.28, 2.38, 0.12)
	hitbox.shape = shape
	hitbox.position = Vector3(0.63, 1.2, 0)
	door_target.add_child(hitbox)


func use_door(who: Node3D) -> void:
	## Since the house, the door stays barred and he talks to you through it.
	if RoadEndHouse.seen and not door_open:
		var rattle := AudioStreamPlayer3D.new()
		rattle.stream = DOOR_RATTLE
		rattle.unit_size = 3.0
		add_child(rattle)
		rattle.position = Vector3(0, 1.1, 2.1)
		rattle.play()
		rattle.finished.connect(rattle.queue_free)
		if line_index < 0:
			player = who
			lines = THROUGH_THE_DOOR.duplicate()
			ask_after = false
			player.start_talking(self)
			_build_overlay()
			_next_line()
		return
	toggle_door()


func toggle_door() -> void:
	## In co-op the host swings it for everyone.
	if not NetworkManager.is_online():
		_swing_door(not door_open)
	elif multiplayer.is_server():
		_door_synced.rpc(not door_open)
	else:
		_request_door.rpc_id(1, not door_open)


@rpc("any_peer", "call_remote", "reliable")
func _request_door(open: bool) -> void:
	if multiplayer.is_server():
		_door_synced.rpc(open)


@rpc("authority", "call_local", "reliable")
func _door_synced(open: bool) -> void:
	_swing_door(open)


func _swing_door(open: bool) -> void:
	if open == door_open:
		return
	door_open = open
	var swing := create_tween()
	swing.tween_property(door_hinge, "rotation:y", deg_to_rad(100.0) if door_open else 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var creak := AudioStreamPlayer3D.new()
	creak.stream = DOOR_SOUND
	creak.unit_size = 3.0
	creak.volume_db = -6.0
	add_child(creak)
	creak.position = Vector3(0, 1.3, 2.05)
	creak.play()
	creak.finished.connect(creak.queue_free)


func _build_stranger() -> void:
	stranger = PlayerBody.new()
	stranger.name = "Stranger"
	add_child(stranger)
	stranger.build(false)
	stranger.position = Vector3(0.55, PlayerBody.FEET - 0.03, -0.7)
	# Older, in a heavy coat and work trousers (player_body.gd dresses him).
	stranger.dress_as_stranger()
	for mesh: MeshInstance3D in stranger.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 1
	talk_spot = Area3D.new()
	talk_spot.name = "TalkTarget"
	talk_spot.collision_layer = 8
	talk_spot.collision_mask = 0
	talk_spot.add_to_group("stranger")
	add_child(talk_spot)
	talk_spot.position = Vector3(0.55, 1.0, -0.7)
	var hitbox := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.9
	hitbox.shape = capsule
	talk_spot.add_child(hitbox)
	# He blocks your way, and looking at that body counts as looking at him.
	var solid := StaticBody3D.new()
	solid.add_to_group("stranger")
	add_child(solid)
	solid.position = talk_spot.position
	var block := CollisionShape3D.new()
	block.shape = capsule
	solid.add_child(block)


func _process(delta: float) -> void:
	var local := get_tree().get_first_node_in_group("local_player") as Node3D
	# Waiting on your choice: after a pause (or anything else that took the
	# mouse), give the pointer and the focus back to the choices.
	if choosing and local and local.has_method("pause_open") and not local.pause_open() and choices.get_child_count() > 0:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var focused := get_viewport().gui_get_focus_owner()
		if focused == null or not choices.is_ancestor_of(focused):
			(choices.get_child(0) as Control).grab_focus()
	var eye := Vector3.ZERO
	if local:
		eye = to_local(local.camera.global_position) if "camera" in local else to_local(local.global_position)
	var near := local != null and eye.distance_to(stranger.position) < 9.0
	# He keeps his eyes on you.
	var pitch := 0.0
	if near:
		var toward := eye - stranger.position
		var yaw := atan2(-toward.x, -toward.z)
		stranger.rotation.y = lerp_angle(stranger.rotation.y, yaw, 1.0 - exp(-4.0 * delta))
		pitch = clampf(atan2(toward.y - 0.9, Vector2(toward.x, toward.z).length()), -0.5, 0.5)
	var targets: Array = [null, null]
	if offering:
		targets[1] = Vector3(0.18, 0.15, -0.5)
	stranger.animate(delta, {"velocity": Vector3.ZERO, "on_floor": true, "pitch": pitch, "targets": targets,
		"grip": [0.15, 1.0 if offering else 0.2], "step": 1.0})
	if offering and is_instance_valid(flare) and stranger.posed.has("HandR"):
		var hand: Transform3D = stranger.posed["HandR"]
		var palm: Vector3 = hand.origin.lerp((stranger.posed["Middle1R"] as Transform3D).origin, 0.5)
		flare.global_position = stranger.global_transform * (stranger.to_rig.affine_inverse() * palm) - Vector3.UP * 0.12
		flare.global_basis = stranger.global_basis * Basis(Vector3.RIGHT, -1.2)
	if line_index >= 0 and not choosing:
		line_timer -= delta
		if line_timer <= 0.0:
			_next_line()


func _make_flare() -> void:
	## The flare he holds out. Once it is yours it can be lit, dropped or rebuilt
	## by a loaded save, so whether he gave it is kept in the story, not on it.
	flare = Supply.new()
	flare.kind = "flare"
	flare.name = "Flare"
	add_child(flare)
	flare.position = Vector3(0.6, 1.0, -0.6)
	flare.freeze = true
	flare.hide()
	flare.collision_layer = 0


func _given() -> bool:
	if RoadEndHouse.story.get("flare_given", false):
		return true
	return is_instance_valid(flare) and flare.get_meta("given", false)


func _offered_flare() -> RigidBody3D:
	if _given():
		return null
	if not is_instance_valid(flare) or flare.is_queued_for_deletion():
		_make_flare()
	return flare


func talk(who: Node3D) -> void:
	if line_index >= 0:
		_next_line()
		return
	player = who
	refused = refused or RoadEndHouse.story.get("flare_refused", false)
	ask_after = not _given()
	if not ask_after:
		lines = AGAIN_GIVEN.duplicate()
	elif refused:
		lines = AGAIN_REFUSED.duplicate()
	else:
		lines = MEETING.duplicate()
	player.start_talking(self)
	_build_overlay()
	line_index = -1
	_next_line()


func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 9
	add_child(overlay)
	var root := Control.new()
	root.theme = Style.make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption = Style.label("", roundi(22 * GameSettings.ui_scale))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	caption.add_theme_constant_override("outline_size", 6)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_left = 80
	caption.offset_right = -80
	caption.offset_top = -170
	caption.offset_bottom = -90
	choices = HBoxContainer.new()
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_theme_constant_override("separation", 18)
	root.add_child(choices)
	choices.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	choices.offset_top = -80
	choices.offset_bottom = -30
	choices.offset_left = -300
	choices.offset_right = 300


func _next_line() -> void:
	mouth.stop()
	ears.stop()
	line_index += 1
	if line_index >= lines.size():
		if ask_after:
			ask_after = false
			_offer_choice()
			return
		_finish()
		return
	var line: Array = lines[line_index]
	if line.size() > 2 and line[2] == "offer":
		var held := _offered_flare()
		if held:
			offering = true
			held.show()
	var speaker: String = line[0]
	var text: String = line[1]
	caption.text = (("Stranger: " if speaker == "him" else "You: ") + text) if GameSettings.subtitles else ""
	line_timer = maxf(1.6, text.length() * 0.075) + 0.6
	var recording := "res://assets/audio/stranger/%s_%s.wav" % [speaker, text.md5_text().substr(0, 10)]
	if ResourceLoader.exists(recording):
		var stream: AudioStream = load(recording)
		var player_for: Node = ears if speaker == "you" else mouth
		if speaker == "him":
			mouth.global_position = stranger.global_position + Vector3.UP * 0.8
		player_for.stream = stream
		player_for.play()
		line_timer = stream.get_length() + 0.45


func _offer_choice() -> void:
	choosing = true
	caption.text = ""
	for option: Array in [["Take the flare", true], ["Leave it", false]]:
		var button := Style.button(option[0], roundi(19 * GameSettings.ui_scale))
		button.pressed.connect(_chose.bind(option[1]))
		choices.add_child(button)
	choices.get_child(0).grab_focus()


func _chose(take: bool) -> void:
	choosing = false
	for button in choices.get_children():
		button.queue_free()
	if take and _offered_flare():
		RoadEndHouse.story["flare_given"] = true
		RoadEndHouse.story.erase("flare_refused")
		flare.set_meta("given", true)
		flare.freeze = false
		flare.collision_layer = 16
		offering = false
		player.give_item(flare)
		lines = TAKEN.duplicate()
	else:
		refused = true
		RoadEndHouse.story["flare_refused"] = true
		offering = false
		if is_instance_valid(flare):
			flare.hide()
		lines = REFUSED.duplicate()
	line_index = -1
	_next_line()


func _finish() -> void:
	mouth.stop()
	ears.stop()
	line_index = -1
	choosing = false
	if not _given():
		offering = false
		if is_instance_valid(flare):
			flare.hide()
	if overlay:
		overlay.queue_free()
		overlay = null
	if player:
		player.stop_talking()
