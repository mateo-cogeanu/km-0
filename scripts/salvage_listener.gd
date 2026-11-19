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
## How deep it rides (the model's height against the water line): roaming and
## hunting it is a shape under the murk and a wake; only listening and taking
## someone does it come up.
const DEPTH := {State.ROAM: -0.3, State.HUNT: -0.4, State.LISTEN: -0.1, State.GRAB: 0.0, State.RETREAT: -0.65}
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
var depth := -0.65
var ears := 0.0
var ears_speed := 0.0
## Its head, listening: held still, then snapped to a new angle.
var head_turn := Vector2.ZERO
var head_goal := Vector2.ZERO
var head_wait := 0.0
## For each ear: how to swing it out from the head, and the axis its rays fan on.
var ear_flare := {}
var ray_axis := {}
var send_wait := 0.0
var remote_position := Vector3.ZERO
var remote_yaw := 0.0
var remote_state := State.ROAM
var clock := 0.0

## The model (salvage_listener.glb, built by Sources/make_salvage_creature.py)
## and its skeleton, posed every frame from the state.
var model: Node3D
var rig: Skeleton3D
var bones := {}
var rests := {}
var neck_raise := 0.0
var jaw_open := 0.0
var reach := 0.0
var swim := 0.0
var swim_phase := 0.0
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

func _build() -> void:
	model = (load("res://assets/characters/salvage_listener.glb") as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	rig = model.find_children("*", "Skeleton3D", true, false)[0]
	for index in rig.get_bone_count():
		bones[rig.get_bone_name(index)] = index
		rests[rig.get_bone_name(index)] = rig.get_bone_rest(index).basis.get_rotation_quaternion()
	_measure_ears()
	var skin := ShaderMaterial.new()
	skin.shader = load("res://assets/characters/listener_skin.gdshader")
	var membrane := ShaderMaterial.new()
	membrane.shader = load("res://assets/characters/listener_membrane.gdshader")
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			var title := material.resource_name if material else ""
			if title.begins_with("Wet pale skin"):
				mesh.set_surface_override_material(surface, skin)
			elif title.begins_with("Ear membrane"):
				mesh.set_surface_override_material(surface, membrane)
			elif material is BaseMaterial3D and (title.begins_with("Old ivory") or title.begins_with("Gum") or title.begins_with("Mouth")):
				var wet := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
				if title.begins_with("Old ivory"):
					# Teeth stained by years in the water.
					wet.albedo_color = Color(0.46, 0.39, 0.27)
				else:
					wet.albedo_color = wet.albedo_color.darkened(0.55)
				wet.roughness = 0.2
				wet.metallic_specular = 0.7
				mesh.set_surface_override_material(surface, wet)
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


func _measure_ears() -> void:
	## Flared, each ear swings out from the side of the head, a little up and
	## forward, like a dish turned to the sound; its six rays fan apart.
	var head_rest := rig.get_bone_global_rest(bones["Head"]).basis.orthonormalized()
	for side in ["L", "R"]:
		var ear: String = "Ear" + side
		if not bones.has(ear):
			continue
		var folded: Vector3 = (rests[ear] * Vector3.UP).normalized()
		var out := Vector3(-1.0 if side == "L" else 1.0, 0.55, 0.3).normalized()
		var wanted := (head_rest.inverse() * out).normalized()
		ear_flare[ear] = Quaternion(folded, wanted)
		var first: String = ear + "0"
		var last: String = ear + "5"
		if bones.has(first) and bones.has(last):
			var a: Vector3 = rests[first] * Vector3.UP
			var b: Vector3 = rests[last] * Vector3.UP
			ray_axis[ear] = a.cross(b).normalized()


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
		game.show_message("It's got %s!\nMake a noise somewhere else: lean on the truck's horn (H), slam a car door, throw a part." % str(victim.get("player_name")), HOLD_SECONDS)


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
	# In its jaws, out in front of it.
	var hold := rig.global_transform * rig.get_bone_global_pose(bones["Jaw"]).origin + global_basis.z * 0.25
	hold.y = maxf(hold.y - 0.6, game.water_level - 0.3) + sin(clock * 9.0) * 0.1
	victim.global_position = hold
	if "remote_position" in victim:
		victim.remote_position = hold
	if victim.is_multiplayer_authority() or not NetworkManager.is_online():
		victim.velocity = Vector3.ZERO
		victim.camera.rotation.z = sin(clock * 23.0) * 0.06


func _pose(bone: String, euler: Vector3) -> void:
	## Turn a bone from its rest pose by euler (radians, in the bone's own axes).
	if bones.has(bone):
		rig.set_bone_pose_rotation(bones[bone], rests[bone] * Quaternion.from_euler(euler))


func _animate(delta: float) -> void:
	var now: int = state
	var ease := 1.0 - exp(-3.0 * delta)
	# It sinks fast and rises slowly.
	var goal_depth: float = DEPTH[now]
	depth = lerpf(depth, goal_depth, 1.0 - exp(-(3.5 if goal_depth < depth else 1.1) * delta))
	# The ears snap open on a spring, overshoot, and shudder; they fold slowly.
	var ear_goal := 1.0 if now == State.LISTEN else (1.15 if now == State.GRAB else 0.0)
	var stiffness := 90.0 if ear_goal > ears else 14.0
	ears_speed += ((ear_goal - ears) * stiffness - ears_speed * (9.0 if ear_goal > ears else 7.5)) * delta
	ears = clampf(ears + ears_speed * delta, -0.05, 1.35)
	neck_raise = lerpf(neck_raise, 1.0 if now == State.LISTEN else (0.75 if now == State.GRAB else 0.0), 1.0 - exp(-1.6 * delta))
	jaw_open = lerpf(jaw_open, 1.0 if now == State.GRAB else (0.12 + 0.06 * sin(clock * 2.1) if now == State.LISTEN else 0.0), 1.0 - exp(-8.0 * delta))
	reach = lerpf(reach, 1.0 if now == State.GRAB else 0.0, 1.0 - exp(-6.0 * delta))
	swim = lerpf(swim, clampf(SPEED[now] / 6.5, 0.0, 1.0), ease)
	swim_phase += delta * (2.0 + 7.0 * swim)
	model.position.y = depth
	# Listening, the head holds dead still, then jerks to a new angle, as if
	# something just moved over there.
	head_wait -= delta
	if head_wait <= 0.0:
		head_wait = randf_range(0.5, 1.6)
		head_goal = Vector2(randf_range(-0.7, 0.7), randf_range(-0.35, 0.35)) if now == State.LISTEN else Vector2.ZERO
	head_turn = head_turn.lerp(head_goal, 1.0 - exp(-16.0 * delta))
	var look := head_turn.x * neck_raise
	_pose("Neck1", Vector3(-0.62 * neck_raise, 0, 0))
	_pose("Neck2", Vector3(-0.45 * neck_raise, 0, look * 0.6))
	_pose("Head", Vector3(0.95 * neck_raise + 0.04 * sin(clock * 1.3), 0, look * 0.4 + head_turn.y * neck_raise))
	_pose("Jaw", Vector3(-0.7 * jaw_open, 0, 0))
	# The ears: swung out from the head, rays fanned wide, the skin quivering.
	var shudder := sin(clock * 37.0) * 0.04 * clampf(absf(ears_speed) * 0.3 + 0.15, 0.0, 1.0) * ears
	for ear: String in ear_flare:
		var open := clampf(ears, 0.0, 1.35)
		var swing: Quaternion = Quaternion.IDENTITY.slerp(ear_flare[ear], minf(open, 1.0))
		rig.set_bone_pose_rotation(bones[ear], swing * rests[ear])
		# Unfolding, they open out larger than they lie folded.
		rig.set_bone_pose_scale(bones[ear], Vector3.ONE * (1.0 + 0.25 * minf(open, 1.2)))
		if ray_axis.has(ear):
			for n in 6:
				var ray: String = ear + str(n)
				var angle := (n - 2.5) * (0.24 * open + shudder * (1.0 + n * 0.3))
				rig.set_bone_pose_rotation(bones[ray], Quaternion(ray_axis[ear], angle) * rests[ray])
	# Swimming: a wave down the body and tail, stronger the faster it goes.
	var amp := 0.06 + 0.3 * swim
	_pose("Spine", Vector3(0, 0, sin(swim_phase) * amp * 0.25))
	_pose("Pelvis", Vector3(0, 0, sin(swim_phase - 0.8) * amp * 0.3))
	for i in 4:
		_pose("Tail%d" % (i + 1), Vector3(0, 0, sin(swim_phase - 1.6 - i * 0.9) * amp * (0.6 + i * 0.25)))
	# Reaching: the arms swing forward and the hands open.
	for side in ["L", "R"]:
		var sign := 1.0 if side == "L" else -1.0
		_pose("UpperArm" + side, Vector3(0.9 * reach + sin(swim_phase + (0.0 if side == "L" else PI)) * 0.15 * swim, 0, sign * 0.35 * reach))
		_pose("Forearm" + side, Vector3(-0.9 * reach, 0, 0))
	var speed: float = SPEED[now]
	wake.emitting = speed > 0.5 or now == State.GRAB
	wake.amount_ratio = clampf(speed / 6.5, 0.25, 1.0)
	wake.global_position = Vector3(global_position.x, game.water_level + 0.02, global_position.z)
