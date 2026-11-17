extends Node3D
## The thing in Marrow's floodwater. It never leaves the water and it cannot
## see: it goes after the loudest thing it can hear, stops where the sound
## was and listens, head up and its great ear-flaps spread, and takes anyone
## in reach who makes a sound. Stand still and silent and it may pass you by.
## A louder noise somewhere else makes it let go of whoever it has.
## Now and then it plays back a sound it has heard, somewhere you are not.
##
## The host runs it; everyone else is sent where it is and what it is doing.

const Shapes := preload("res://scripts/prop_shapes.gd")
const LISTEN := preload("res://assets/audio/salvage/listen.wav")
const SURFACE := preload("res://assets/audio/salvage/surface.wav")
const GRAB := preload("res://assets/audio/salvage/grab.wav")
const CLANG := preload("res://assets/audio/ending/hit.wav")
const SCRAPE := preload("res://assets/audio/salvage/scrape.wav")
const SPLASHES := [
	preload("res://assets/audio/salvage/splash_1.wav"), preload("res://assets/audio/salvage/splash_2.wav"),
	preload("res://assets/audio/salvage/splash_3.wav"), preload("res://assets/audio/salvage/splash_4.wav"),
]

enum State { ROAM, HUNT, LISTEN, GRAB, RETREAT }
const SPEED := {State.ROAM: 1.6, State.HUNT: 6.5, State.LISTEN: 0.0, State.GRAB: 0.0, State.RETREAT: 5.0}
const SURFACED := {State.ROAM: 0.12, State.HUNT: 0.04, State.LISTEN: 0.75, State.GRAB: 1.0, State.RETREAT: 0.0}
## It notices sounds that reach it at least this loud.
const NOTICE := 0.05
const REACH := 2.3
const HOLD_SECONDS := 3.6
const HEAD := Vector3(0, 0, 2.0)
const LAIR := Vector3(0, 0, -140)

var game: Node3D
var state := State.ROAM
var target := Vector3.ZERO
var state_time := 0.0
var wander_wait := 0.0
var mimic_wait := 70.0
var hunting: Node3D
var victim: Node3D
## Whoever it just let go of gets a few seconds to get away.
var spared: Node3D
var spared_until := 0.0
var grab_level := 0.0
var surfaced := 0.1
var ears := 0.0
var send_wait := 0.0
var remote_position := Vector3.ZERO
var remote_yaw := 0.0
var remote_state := State.ROAM
var clock := 0.0

var body: Node3D
var head: Node3D
var ear_flaps: Array[Node3D] = []
var neck: MeshInstance3D
var jaw: Node3D
var arms: Array[Node3D] = []
var wake: GPUParticles3D
var voice: AudioStreamPlayer3D
var splash: AudioStreamPlayer3D
var mimic_voice: AudioStreamPlayer3D


func _ready() -> void:
	_build()
	position = LAIR
	target = LAIR
	remote_position = position
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


static func host() -> bool:
	return not NetworkManager.is_online() or NetworkManager.multiplayer.is_server()


func is_taken(player: Node) -> bool:
	return player == victim


# --- What it looks like ----------------------------------------------------------

func _fan_mesh(side: float) -> ArrayMesh:
	## A half-open fan of skin, ragged at the rim.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 14
	var rim: Array[Vector3] = []
	for i in steps + 1:
		var angle := deg_to_rad(-20.0 + 140.0 * i / steps)
		var reach := 0.8 * (0.82 + 0.18 * sin(i * 2.7))
		rim.append(Vector3(side * cos(angle) * reach, sin(angle) * reach, -0.12 - 0.1 * sin(PI * i / steps)))
	for i in steps:
		for vertex in [Vector3.ZERO, rim[i], rim[i + 1]]:
			tool.set_normal(Vector3(0, 0, 1))
			tool.add_vertex(vertex)
	tool.generate_normals()
	return tool.commit()


func _build() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("#b5b8ad")
	skin.roughness = 0.22
	skin.metallic_specular = 0.75
	var dark := Shapes.material(Color("#2e2f2b"), 0.0, 0.4)
	var membrane := StandardMaterial3D.new()
	membrane.albedo_color = Color(0.3, 0.24, 0.23, 0.9)
	membrane.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	membrane.cull_mode = BaseMaterial3D.CULL_DISABLED
	membrane.roughness = 0.35
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	# Long and flat, made for lying just under the surface.
	var trunk := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = 0.5
	shape.height = 1.0
	trunk.mesh = shape
	trunk.material_override = skin
	body.add_child(trunk)
	trunk.scale = Vector3(1.6, 0.6, 4.6)
	# A ridge of knuckled bone down the spine: all you usually see of it.
	for i in 9:
		var knob := MeshInstance3D.new()
		var bump := SphereMesh.new()
		bump.radius = 0.09 - absf(i - 4) * 0.008
		bump.height = bump.radius * 2.6
		knob.mesh = bump
		knob.material_override = skin
		body.add_child(knob)
		knob.position = Vector3(0, 0.27 - absf(i - 4) * 0.02, 1.5 - i * 0.38)
	# Limbs folded along its sides, long fingers trailing.
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		body.add_child(arm)
		arm.position = Vector3(side * 0.6, 0.0, 1.2)
		Shapes.tube(arm, "UpperArm", Vector3.ZERO, Vector3(side * 0.5, -0.1, -0.9), 0.07, skin)
		Shapes.tube(arm, "Forearm", Vector3(side * 0.5, -0.1, -0.9), Vector3(side * 0.35, -0.15, 0.4), 0.055, skin)
		for f in 3:
			Shapes.tube(arm, "Finger", Vector3(side * 0.35, -0.15, 0.4), Vector3(side * (0.3 + f * 0.08), -0.2, 0.85 + f * 0.05), 0.018, skin)
		arms.append(arm)
	# The head: smooth, no eyes at all, a lipless slit of a mouth.
	head = Node3D.new()
	head.name = "Head"
	body.add_child(head)
	head.position = Vector3(0, 0.1, 2.15)
	neck = Shapes.tube(body, "Neck", Vector3(0, 0.05, 1.9), Vector3(0, 0.1, 2.15), 0.13, skin)
	var skull := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.32
	dome.height = 0.64
	skull.mesh = dome
	skull.material_override = skin
	head.add_child(skull)
	skull.scale = Vector3(0.8, 0.7, 1.75)
	Shapes.box(head, "Mouth", Vector3(0.42, 0.015, 0.05), Vector3(0, -0.1, 0.5), dark)
	# A long lower jaw, hinged far back, lined with needle teeth.
	jaw = Node3D.new()
	head.add_child(jaw)
	jaw.position = Vector3(0, -0.1, -0.15)
	Shapes.box(jaw, "Jaw", Vector3(0.36, 0.07, 0.7), Vector3(0, -0.03, 0.35), skin)
	Shapes.box(jaw, "Gullet", Vector3(0.3, 0.02, 0.62), Vector3(0, 0.01, 0.33), dark)
	var ivory := Shapes.material(Color("#d8d2bd"), 0.0, 0.3)
	for t in 9:
		for side in [-1.0, 1.0]:
			var tooth := Shapes.cylinder(jaw, "Tooth", Vector3(side * 0.15, 0.06, 0.1 + t * 0.07), Vector3(0, 1, 0.15), 0.012, 0.11 - absf(t - 4) * 0.008, ivory, 5)
			tooth.scale = Vector3(1, 1, 1)
	# The ears: two great folded fans of skin that open when it listens.
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		head.add_child(hinge)
		hinge.position = Vector3(side * 0.24, 0.05, -0.05)
		var fan := MeshInstance3D.new()
		fan.mesh = _fan_mesh(side)
		fan.material_override = membrane
		hinge.add_child(fan)
		# Ribs through the membrane, from the hinge to the rim.
		for r in 5:
			var angle := deg_to_rad(-20.0 + r * 35.0)
			Shapes.tube(hinge, "Rib", Vector3.ZERO, Vector3(side * cos(angle) * 0.78, sin(angle) * 0.78, -0.12), 0.013, skin)
		ear_flaps.append(hinge)
	for mesh: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Rings spreading on the water as it moves.
	wake = GPUParticles3D.new()
	wake.amount = 24
	wake.lifetime = 2.2
	wake.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 0.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	process.gravity = Vector3.ZERO
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.5, 0.0, 1.5)
	process.scale_min = 0.6
	process.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(1, 3.2))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.5))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	wake.process_material = process
	var ring := QuadMesh.new()
	ring.size = Vector2(1.6, 1.6)
	ring.orientation = PlaneMesh.FACE_Y
	var ring_material := StandardMaterial3D.new()
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.vertex_color_use_as_albedo = true
	ring_material.albedo_color = Color(0.75, 0.8, 0.82)
	var ring_texture := GradientTexture2D.new()
	ring_texture.fill = GradientTexture2D.FILL_RADIAL
	ring_texture.fill_from = Vector2(0.5, 0.5)
	ring_texture.fill_to = Vector2(1.0, 0.5)
	var band := Gradient.new()
	band.offsets = PackedFloat32Array([0.0, 0.72, 0.85, 1.0])
	band.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	ring_texture.gradient = band
	ring_material.albedo_texture = ring_texture
	ring.material = ring_material
	wake.draw_pass_1 = ring
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wake)
	voice = AudioStreamPlayer3D.new()
	voice.unit_size = 7.0
	voice.max_distance = 90.0
	add_child(voice)
	voice.position = HEAD
	splash = AudioStreamPlayer3D.new()
	splash.unit_size = 9.0
	splash.max_distance = 110.0
	add_child(splash)
	mimic_voice = AudioStreamPlayer3D.new()
	mimic_voice.unit_size = 8.0
	mimic_voice.max_distance = 120.0
	get_parent().add_child.call_deferred(mimic_voice)


# --- Thinking (host) ------------------------------------------------------------

func _process(delta: float) -> void:
	clock += delta
	if host():
		_think(delta)
		send_wait -= delta
		if send_wait <= 0.0 and NetworkManager.is_online():
			send_wait = 1.0 / 15.0
			_sync.rpc(position, rotation.y, state, victim.name if is_instance_valid(victim) else "")
	else:
		position = position.lerp(remote_position, 1.0 - exp(-10.0 * delta))
		rotation.y = lerp_angle(rotation.y, remote_yaw, 1.0 - exp(-8.0 * delta))
		state = remote_state
	position.y = game.water_level
	_animate(delta)
	_hold_victim()


func _think(delta: float) -> void:
	state_time += delta
	if game.ended:
		return
	var noise: Node = game.noise
	# What it can hear from here, loudest first.
	var loudest := {}
	var loudest_heard := 0.0
	for source in noise.sources():
		if state == State.GRAB and is_instance_valid(victim) and source.get("player") == victim:
			continue
		var heard: float = noise.heard_at(_head(), source["level"], source["pos"])
		if heard > loudest_heard:
			loudest_heard = heard
			loudest = source
	match state:
		State.RETREAT:
			_move_toward(LAIR, delta)
			if state_time > 22.0:
				_set_state(State.ROAM)
			return
		State.GRAB:
			if loudest_heard > maxf(0.2, grab_level * 0.8):
				# Something louder, somewhere else: it lets go and goes for that.
				_release(false)
				_hunt(loudest)
			elif state_time > HOLD_SECONDS:
				_release(true)
			return
	if game.clock < 35.0:
		# The first moments of the night: it is far off, down by the drain.
		_move_toward(LAIR, delta)
		return
	if loudest_heard > NOTICE:
		_hunt(loudest)
	match state:
		State.HUNT:
			if hunting and is_instance_valid(hunting) and hunting.get("active_vehicle") == null:
				target = _in_water(hunting.global_position)
			_move_toward(target, delta)
			if Vector2(position.x - target.x, position.z - target.z).length() < 1.6:
				_set_state(State.LISTEN)
				voice.stream = LISTEN
				voice.play()
		State.LISTEN:
			if state_time > 4.5:
				_set_state(State.ROAM)
		State.ROAM:
			wander_wait -= delta
			if wander_wait <= 0.0:
				wander_wait = randf_range(6.0, 14.0)
				target = _in_water(Vector3(randf_range(-7.0, 7.0), 0, randf_range(-50.0, -145.0)))
			_move_toward(target, delta)
			mimic_wait -= delta
			if mimic_wait <= 0.0:
				mimic_wait = randf_range(50.0, 100.0)
				_mimic()
	_try_grab()


func _hunt(source: Dictionary) -> void:
	var was := state
	target = _in_water(source["pos"])
	hunting = source.get("player") as Node3D
	if was != State.HUNT:
		_set_state(State.HUNT)


func _try_grab() -> void:
	## Anyone in reach who makes a sound. Silence, right next to it, works.
	if state == State.GRAB or state == State.RETREAT:
		return
	var noise: Node = game.noise
	for player: Node3D in game.players():
		if is_instance_valid(player.get("active_vehicle")) or (player == spared and clock < spared_until):
			continue
		var gap := Vector2(player.global_position.x - _head().x, player.global_position.z - _head().z).length()
		if gap > REACH:
			continue
		var level: float = noise.player_level(player)
		for event in noise.events:
			if event.get("by") == player and event["age"] < 0.5:
				level = maxf(level, event["level"])
		if level > 0.1 or (state == State.HUNT and hunting == player and gap < 1.2):
			_grab(player, level)
			return


func _grab(player: Node3D, level: float) -> void:
	victim = player
	grab_level = maxf(level, 0.3)
	_set_state(State.GRAB)
	_announce_grab(player.name)


func _release(taken: bool) -> void:
	var who := victim
	victim = null
	spared = who
	spared_until = clock + 5.0
	if is_instance_valid(who):
		if NetworkManager.is_online():
			_let_go.rpc(who.name, taken)
		else:
			_let_go(who.name, taken)
	_set_state(State.RETREAT if taken else State.HUNT)


func _set_state(next: State) -> void:
	if next == State.LISTEN or next == State.GRAB:
		if state != State.LISTEN and state != State.GRAB:
			splash.stream = SURFACE
			splash.play()
	state = next
	state_time = 0.0


func _move_toward(goal: Vector3, delta: float) -> void:
	var flat := Vector3(goal.x - position.x, 0, goal.z - position.z)
	if flat.length() < 0.2:
		return
	var step := flat.normalized() * minf(SPEED[state] * delta, flat.length())
	var next := position + step
	# It keeps to water deep enough to hide in, sliding along the edge.
	if game.water_depth(next) < 0.4:
		next = position + Vector3(step.x, 0, 0)
		if game.water_depth(next) < 0.4:
			next = position + Vector3(0, 0, step.z)
			if game.water_depth(next) < 0.4:
				return
	position = next
	rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), 1.0 - exp(-4.0 * delta))


func _in_water(point: Vector3) -> Vector3:
	## The nearest place to point it can get to.
	var spot := Vector3(clampf(point.x, -8.3, 8.3), 0, clampf(point.z, -146.0, -36.0))
	return spot


func _head() -> Vector3:
	return global_transform * HEAD


func _mimic() -> void:
	## Plays back something it heard, well away from everyone.
	for attempt in 12:
		var spot := _in_water(Vector3(randf_range(-7.0, 7.0), 0, randf_range(-50.0, -145.0)))
		var clear := true
		for player: Node3D in game.players():
			if player.global_position.distance_to(spot) < 28.0:
				clear = false
		if clear:
			spot.y = game.water_level
			var kind := randi() % 3
			if NetworkManager.is_online():
				_play_mimic.rpc(kind, spot)
			else:
				_play_mimic(kind, spot)
			return


# --- Everyone --------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _sync(at: Vector3, yaw: float, now: int, held: String) -> void:
	remote_position = at
	remote_yaw = yaw
	if now != remote_state and (now == State.LISTEN or now == State.GRAB) and remote_state != State.LISTEN and remote_state != State.GRAB:
		splash.stream = SURFACE
		splash.play()
	if now == State.LISTEN and remote_state != State.LISTEN:
		voice.stream = LISTEN
		voice.play()
	remote_state = now as State
	victim = game.get_node_or_null(held) if not held.is_empty() else null


func _announce_grab(who: String) -> void:
	if NetworkManager.is_online():
		_grabbed.rpc(who)
	else:
		_grabbed(who)


@rpc("authority", "call_local", "reliable")
func _grabbed(who: String) -> void:
	victim = game.get_node_or_null(who)
	splash.stream = GRAB
	splash.play()
	var me: Node3D = game.local_player()
	if victim == null:
		return
	if victim == me:
		if is_instance_valid(me.held_object):
			me._drop_held_object()
		if me.helping_object:
			me._stop_helping()
		me.ending_locked = true
		game.show_message("It has you.\nSomeone make a noise, anywhere else. Now.", HOLD_SECONDS)
	else:
		game.show_message("It's got %s!\nMake a noise somewhere else: the horn, a car door, throw something." % str(victim.get("player_name")), HOLD_SECONDS)


@rpc("authority", "call_local", "reliable")
func _let_go(who: String, taken: bool) -> void:
	var player := game.get_node_or_null(who) as Node3D
	if victim == player:
		victim = null
	if player == null:
		return
	var me: Node3D = game.local_player()
	if player == me:
		me.ending_locked = false
		me.velocity = Vector3.ZERO
		if taken:
			me.global_position = Vector3(randf_range(-3.0, 3.0), 1.05, 19.0)
			me.reset_physics_interpolation()
			me.vitals.damage(35.0)
			game.show_message("It dragged you under.\nYou came to on the ridge, coughing up floodwater.", 6.0)
		else:
			game.show_message("It let go. Get out of the water.", 3.0)
	elif taken:
		game.show_message("It took %s under.\nThey crawled out by the camp, half drowned." % str(player.get("player_name")), 5.0)


@rpc("authority", "call_local", "reliable")
func _play_mimic(kind: int, at: Vector3) -> void:
	mimic_voice.global_position = at
	match kind:
		0:
			for i in randi_range(4, 7):
				mimic_voice.stream = SPLASHES[randi() % SPLASHES.size()]
				mimic_voice.pitch_scale = randf_range(0.9, 1.05)
				mimic_voice.play()
				await get_tree().create_timer(randf_range(0.42, 0.55)).timeout
		1:
			mimic_voice.stream = CLANG
			mimic_voice.pitch_scale = randf_range(0.65, 0.8)
			mimic_voice.play()
		2:
			mimic_voice.stream = SCRAPE
			mimic_voice.pitch_scale = 0.9
			mimic_voice.play()
			await get_tree().create_timer(1.8).timeout
			mimic_voice.stop()


func _hold_victim() -> void:
	## Whoever it has is held against it, wherever it goes.
	if not is_instance_valid(victim) or (state != State.GRAB and remote_state != State.GRAB):
		return
	var hold := global_transform * Vector3(0, 0.3, 2.4)
	hold.y = game.water_level + 0.15 + sin(clock * 9.0) * 0.12
	victim.global_position = hold
	if "remote_position" in victim:
		victim.remote_position = hold
	if victim.is_multiplayer_authority() or not NetworkManager.is_online():
		victim.velocity = Vector3.ZERO
		victim.camera.rotation.z = sin(clock * 23.0) * 0.06


func _stretch_neck() -> void:
	var from := Vector3(0, 0.05, 1.85)
	var to := head.position + Vector3(0, -0.12, -0.2)
	var span := to - from
	var up := span.normalized()
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var length := span.length() / maxf((neck.mesh as CylinderMesh).height, 0.01)
	neck.transform = Transform3D(Basis(side, up * length, side.cross(up)), (from + to) * 0.5)


func _animate(delta: float) -> void:
	var now: int = state
	surfaced = lerpf(surfaced, SURFACED[now], 1.0 - exp(-3.0 * delta))
	ears = lerpf(ears, 1.0 if now == State.LISTEN else (0.6 if now == State.GRAB else 0.0), 1.0 - exp(-4.0 * delta))
	# Only the spine breaks the water; listening, the head rises out on its
	# neck, dripping, and turns slowly from side to side.
	body.position.y = lerpf(-0.52, -0.3, surfaced)
	body.rotation.x = -0.1 * surfaced
	head.position = Vector3(0, lerpf(0.0, 0.85, surfaced), lerpf(2.15, 2.35, surfaced))
	head.rotation.x = -0.35 * surfaced + sin(clock * 1.3) * 0.04
	head.rotation.y = sin(clock * 0.45) * 0.5 * ears
	_stretch_neck()
	head.rotation.z = sin(clock * 0.7) * 0.15 * ears
	for i in ear_flaps.size():
		var side := -1.0 if i == 0 else 1.0
		ear_flaps[i].rotation.y = side * lerpf(-1.25, 0.15, ears)
		ear_flaps[i].scale = Vector3.ONE * lerpf(0.4, 1.6, ears)
	jaw.rotation.x = lerpf(0.0, 0.75, 1.0 if now == State.GRAB else 0.0) + (0.06 * sin(clock * 3.0) if now == State.LISTEN else 0.0)
	for i in arms.size():
		var side := -1.0 if i == 0 else 1.0
		arms[i].rotation.x = -1.1 * (1.0 if now == State.GRAB else 0.0) + sin(clock * 2.0 + i) * 0.05
		arms[i].rotation.y = side * 0.4 * (1.0 if now == State.GRAB else 0.0)
	var speed: float = SPEED[now]
	wake.emitting = speed > 0.5 or now == State.GRAB
	wake.amount_ratio = clampf(speed / 6.5, 0.25, 1.0)
	wake.global_position = Vector3(global_position.x, game.water_level + 0.02, global_position.z)
