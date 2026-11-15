extends Node3D
## A cabin back the way you came, past where the road starts. Someone who
## followed the radio before you is holed up inside. He speaks with the
## system's text-to-speech voices, and offers you a road flare.

const Shapes := preload("res://scripts/prop_shapes.gd")
const PlayerBody := preload("res://scripts/player_body.gd")
const Supply := preload("res://scripts/supply_item.gd")
const Style := preload("res://scripts/menu_style.gd")

const LOCATION := Vector3(46.0, 0.0, 660.0)
## The door faces back towards the road and the workshop.
const TURN := PI

## who ("him" or "you"), what is said, and an optional cue for the scene.
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
	["him", "I ran. I don't know how far. I ended up here, and I haven't slept since."],
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
	["him", "Still here? Go on, then. I'm not going back there. Not ever."],
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
var voices := {}
var talk_spot: Area3D
var refused := false
var ask_after := false


func _ready() -> void:
	_build_cabin()
	_build_stranger()
	flare = Supply.new()
	flare.kind = "flare"
	flare.name = "Flare"
	add_child(flare)
	flare.position = Vector3(0.6, 1.0, -0.6)
	flare.freeze = true
	flare.hide()
	flare.collision_layer = 0
	_pick_voices()


func _build_cabin() -> void:
	var planks := Shapes.material(Color("#5e4a38"))
	var dark := Shapes.material(Color("#2a2420"))
	var floor_wood := Shapes.material(Color("#4a3c2f"))
	Shapes.box(self, "Floor", Vector3(5.2, 0.12, 4.2), Vector3(0, 0.02, 0), floor_wood, true)
	Shapes.box(self, "BackWall", Vector3(5.2, 2.6, 0.14), Vector3(0, 1.3, -2.05), planks, true)
	for side in [-1.0, 1.0]:
		Shapes.box(self, "SideWall", Vector3(0.14, 2.6, 4.2), Vector3(side * 2.55, 1.3, 0), planks, true)
		# The front, either side of the doorway.
		Shapes.box(self, "FrontWall", Vector3(2.1, 2.6, 0.14), Vector3(side * 1.5, 1.3, 2.05), planks, true)
	Shapes.box(self, "Lintel", Vector3(0.9, 0.5, 0.14), Vector3(0, 2.35, 2.05), planks, true)
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
	# Inside: table, chair, cot, lamp, a radio, empties.
	Shapes.box(self, "Table", Vector3(1.2, 0.06, 0.75), Vector3(-1.2, 0.78, -1.2), planks, true)
	for x in [-1.72, -0.68]:
		for z in [-1.5, -0.9]:
			Shapes.box(self, "TableLeg", Vector3(0.05, 0.76, 0.05), Vector3(x, 0.39, z), dark)
	Shapes.box(self, "Chair", Vector3(0.42, 0.05, 0.42), Vector3(-1.2, 0.46, -0.45), planks, true)
	Shapes.box(self, "ChairBack", Vector3(0.42, 0.5, 0.04), Vector3(-1.2, 0.72, -0.25), planks)
	Shapes.box(self, "Cot", Vector3(0.75, 0.38, 1.9), Vector3(1.85, 0.2, -0.9), Shapes.material(Color("#55593f")), true)
	Shapes.box(self, "Blanket", Vector3(0.74, 0.05, 1.3), Vector3(1.85, 0.42, -0.6), Shapes.material(Color("#6a3a2f")))
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
	lamp.shadow_enabled = true
	add_child(lamp)
	lamp.position = Vector3(-0.85, 1.1, -1.3)
	var tin := Shapes.material(Color("#8f8d88"), 0.75, 0.35)
	for spot in [Vector3(0.4, 0.13, 0.9), Vector3(-0.3, 0.13, 1.3), Vector3(1.2, 0.13, 0.4), Vector3(-1.9, 0.13, 0.6)]:
		var can := Shapes.cylinder(self, "EmptyCan", spot, Vector3.RIGHT, 0.042, 0.11, tin, 10)
		can.rotation.y = spot.x * 3.0


func _build_stranger() -> void:
	stranger = PlayerBody.new()
	stranger.name = "Stranger"
	add_child(stranger)
	stranger.build(false)
	stranger.position = Vector3(0.55, PlayerBody.FEET + 0.08, -0.7)
	# Older, in a worn flannel coat and work trousers.
	var recolor := {"Jacket": Color("#5a2a22"), "Jeans": Color("#5b5240"), "Hair": Color("#7a7670")}
	for mesh: MeshInstance3D in stranger.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 1
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			if material and recolor.has(material.resource_name):
				var worn := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
				worn.albedo_color = recolor[material.resource_name]
				mesh.set_surface_override_material(surface, worn)
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
	var solid := StaticBody3D.new()
	add_child(solid)
	solid.position = talk_spot.position
	var block := CollisionShape3D.new()
	block.shape = capsule
	solid.add_child(block)


func _pick_voices() -> void:
	## Two different system voices: one for him, one for you.
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	var found := DisplayServer.tts_get_voices_for_language("en")
	if found.is_empty():
		return
	var preferred_him := ["Fred", "Ralph", "Daniel", "Rocko", "Reed", "Grandpa", "Eddy"]
	var preferred_you := ["Alex", "Tom", "Aaron", "Samantha", "Evan", "Nathan"]
	voices["him"] = _choose(found, preferred_him, found[0])
	voices["you"] = _choose(found, preferred_you, found[mini(1, found.size() - 1)])
	if voices["you"] == voices["him"] and found.size() > 1:
		voices["you"] = found[1] if found[0] == voices["him"] else found[0]
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_spoken)


func _choose(found: PackedStringArray, names: Array, fallback: String) -> String:
	var voice_list := DisplayServer.tts_get_voices()
	for wanted in names:
		for entry: Dictionary in voice_list:
			if String(entry.get("name", "")).begins_with(wanted) and found.has(entry.get("id", "")):
				return entry["id"]
	return fallback


func _process(delta: float) -> void:
	var local := get_tree().get_first_node_in_group("local_player") as Node3D
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
	if offering and stranger.posed.has("HandR"):
		var hand: Transform3D = stranger.posed["HandR"]
		var palm: Vector3 = hand.origin.lerp((stranger.posed["Middle1R"] as Transform3D).origin, 0.5)
		flare.global_position = stranger.global_transform * (stranger.to_rig.affine_inverse() * palm) - Vector3.UP * 0.12
		flare.global_basis = stranger.global_basis * Basis(Vector3.RIGHT, -1.2)
	if line_index >= 0 and not choosing:
		line_timer -= delta
		if line_timer <= 0.0:
			_next_line()


func talk(who: Node3D) -> void:
	if line_index >= 0:
		_next_line()
		return
	player = who
	ask_after = not flare.get_meta("given", false)
	if flare.get_meta("given", false):
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
	if line_index >= 0 and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()
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
		offering = true
		flare.show()
	var speaker: String = line[0]
	var text: String = line[1]
	caption.text = ("Stranger: " if speaker == "him" else "You: ") + text
	line_timer = maxf(1.6, text.length() * 0.075) + 0.6
	var voice: String = voices.get(speaker, "")
	if not voice.is_empty():
		DisplayServer.tts_speak(text, voice, 80, 0.88 if speaker == "him" else 1.0, 0.92 if speaker == "him" else 1.0, line_index)
		line_timer += 4.0


func _on_spoken(id: int) -> void:
	if id == line_index and not choosing:
		line_timer = minf(line_timer, 0.45)


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
	if take:
		flare.set_meta("given", true)
		flare.freeze = false
		flare.collision_layer = 16
		offering = false
		player.give_item(flare)
		lines = TAKEN.duplicate()
	else:
		refused = true
		offering = false
		flare.hide()
		lines = REFUSED.duplicate()
	line_index = -1
	_next_line()


func _finish() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()
	line_index = -1
	choosing = false
	if not flare.get_meta("given", false):
		offering = false
		flare.hide()
	if overlay:
		overlay.queue_free()
		overlay = null
	if player:
		player.stop_talking()
