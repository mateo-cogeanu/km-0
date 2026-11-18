extends Node
## How loud everyone is in the Salvage Run. Every peer can work it out from
## what it already sees (players, cars and parts are all synced), so there is
## nothing extra to send: the host's copy feeds the creature, and each peer
## shows its own player how loud they are being.
##
## Levels run 0 (silent) to 1 (heard from one end of the street to the other).
## A sound of level L carries HEAR_RANGE * L metres.

const SCRAPE := preload("res://assets/audio/salvage/scrape.wav")
const HEAR_RANGE := 80.0
const ENGINES := {"Electric": 0.1, "Stock": 0.5, "V8": 0.88, "Bike": 0.3}

var game: Node3D
## Short sounds (a part dropped, a wheel pulled, a door slammed): position,
## level and how long ago.
var events: Array[Dictionary] = []
## The local player's own noise, for the meter.
var local_level := 0.0
var _last_parts := {}
var _installed := {}
var _install_check := 0.0
var _scrapes := {}


func _ready() -> void:
	add_to_group("salvage_noise")


func heard(at: Vector3, level: float) -> void:
	## A sound reported by something else (a door slammed).
	add_event(at, level, _nearest_player(at))


func _process(delta: float) -> void:
	for event in events:
		event["age"] += delta
	events = events.filter(func(e: Dictionary) -> bool: return e["age"] < 2.0)
	_watch_parts(delta)
	_install_check -= delta
	if _install_check <= 0.0:
		_install_check = 0.25
		_watch_installs()
	var me: CharacterBody3D = game.local_player()
	local_level = 0.0
	if me:
		local_level = player_level(me)
		if is_instance_valid(me.active_vehicle):
			local_level = vehicle_level(me.active_vehicle)
		for event in events:
			if event.get("by") == me and event["age"] < 0.6:
				local_level = maxf(local_level, event["level"])


func player_level(player: Node3D) -> float:
	## Moving about: quiet on dry ground, loud wading, louder running through it.
	if is_instance_valid(player.get("active_vehicle")):
		return 0.0
	var moving: Vector3 = player.velocity if player.is_multiplayer_authority() else player.remote_velocity
	var speed := Vector2(moving.x, moving.z).length()
	var level := 0.0
	if speed > 0.4:
		level = clampf(speed / float(player.move_speed), 0.0, 1.8) * 0.18
	if game.in_water(player.global_position + Vector3.DOWN * 0.9):
		level *= 2.4
	if player.has_method("dragging_heavy") and player.dragging_heavy():
		level = maxf(level, 0.62)
	return clampf(level, 0.0, 1.0)


func vehicle_level(vehicle: Node3D) -> float:
	if vehicle.get("honking"):
		return 1.0
	var running := String(vehicle.get("audible_engine_variant"))
	var level: float = ENGINES.get(running, 0.0)
	var speed := Vector2(vehicle.linear_velocity.x, vehicle.linear_velocity.z).length()
	if speed > 1.0:
		level += minf(speed / 20.0, 1.0) * 0.12
		if game.in_water(vehicle.global_position):
			level += 0.2
	return clampf(level, 0.0, 1.0)


func add_event(at: Vector3, level: float, by: Node = null) -> void:
	events.append({"pos": at, "level": level, "age": 0.0, "by": by})


func sources() -> Array[Dictionary]:
	## Everything making noise right now: [{pos, level, player}].
	var found: Array[Dictionary] = []
	for player: Node3D in game.players():
		var level := player_level(player)
		if level > 0.02:
			found.append({"pos": player.global_position, "level": level, "player": player})
	for vehicle in get_tree().get_nodes_in_group("drivable"):
		var level := vehicle_level(vehicle)
		if level > 0.02:
			found.append({"pos": vehicle.global_position, "level": level, "player": null})
	for event in events:
		var fade := 1.0 - clampf(event["age"] / 2.0, 0.0, 1.0)
		found.append({"pos": event["pos"], "level": event["level"] * fade, "player": event.get("by")})
	return found


func heard_at(listener_at: Vector3, level: float, source_at: Vector3) -> float:
	## How loud a sound is by the time it reaches the listener.
	var reach := HEAR_RANGE * level
	if reach <= 0.0:
		return 0.0
	return level * clampf(1.0 - listener_at.distance_to(source_at) / reach, 0.0, 1.0)


func _watch_parts(delta: float) -> void:
	## Dropped and thrown parts clang; an engine dragged along the ground
	## scrapes, loudly, the whole way.
	if delta <= 0.0:
		return
	var seen := {}
	for body: Node3D in get_tree().get_nodes_in_group("vehicle_loose_part"):
		if not body.is_inside_tree() or body.is_queued_for_deletion():
			continue
		seen[body] = true
		var last: Dictionary = _last_parts.get(body, {"pos": body.global_position, "speed": 0.0})
		var velocity: Vector3 = (body.global_position - last["pos"]) / delta
		var speed := velocity.length()
		if last["speed"] > 2.6 and speed < last["speed"] * 0.4:
			var holder: Node = game.get_node_or_null(str(body.get_meta("held_by"))) if body.has_meta("held_by") else null
			add_event(body.global_position, clampf(last["speed"] / 7.0, 0.3, 1.0), holder)
		_last_parts[body] = {"pos": body.global_position, "speed": speed}
		var heavy := String(body.get_meta("vehicle_part_type", "")) == "engine"
		var low: bool = body.global_position.y - game.ground_height(body.global_position.x, body.global_position.z) < 0.5
		var dragging := heavy and low and speed > 0.3 and speed < 4.0 and body.has_meta("held_by")
		_scrape(body, dragging)
		if dragging:
			var holder: Node = game.get_node_or_null(str(body.get_meta("held_by")))
			add_event(body.global_position, 0.62, holder)
			events.back()["age"] = 1.6
	for body in _last_parts.keys():
		if not seen.has(body):
			_last_parts.erase(body)
			_scrape(body, false)


func _scrape(body: Node3D, on: bool) -> void:
	var sound: AudioStreamPlayer3D = _scrapes.get(body)
	if on and sound == null and is_instance_valid(body):
		sound = AudioStreamPlayer3D.new()
		var copy := SCRAPE.duplicate() as AudioStreamWAV
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		copy.loop_end = int(copy.get_length() * copy.mix_rate)
		sound.stream = copy
		sound.unit_size = 6.0
		sound.volume_db = -3.0
		body.add_child(sound)
		sound.play()
		_scrapes[body] = sound
	elif not on and sound != null:
		if is_instance_valid(sound):
			sound.queue_free()
		_scrapes.erase(body)


func _watch_installs() -> void:
	## Pulling or fitting a part: spanners, a stuck bolt, metal on metal.
	for vehicle in get_tree().get_nodes_in_group("drivable"):
		if not "removable_parts" in vehicle:
			continue
		for slot: String in vehicle.removable_parts:
			var key := "%s/%s" % [vehicle.name, slot]
			var now := bool(vehicle.removable_parts[slot].get("installed", false))
			if _installed.has(key) and _installed[key] != now:
				var near := _nearest_player(vehicle.global_position)
				add_event(vehicle.global_position, 0.48 if slot in ["engine", "radiator"] else 0.36, near)
			_installed[key] = now


func _nearest_player(at: Vector3) -> Node3D:
	var best: Node3D = null
	for player: Node3D in game.players():
		if best == null or player.global_position.distance_to(at) < best.global_position.distance_to(at):
			best = player
	return best
