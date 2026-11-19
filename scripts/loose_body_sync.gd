extends Node
## Co-op: keeps loose things (parts, cans, food, bottles) in the same place on
## every screen once nobody is holding them. Whoever last let go of a thing
## owns its motion for a few seconds; after that, and for anything nobody has
## held (knocked by a car, sliding off a roof), the host does. The owner sends
## where it is while it is moving; everyone else follows that and simulates
## nothing of their own. When it comes to rest the owner says so once, reliably.
##
## Each player's controller makes sure one of these sits at the scene root, so
## it has the same path on every peer.

const GROUPS := ["vehicle_loose_part", "fuel_canister", "spray_can", "food", "water", "battery_pack", "flare"]
const SEND_RATE := 12.0
## How long whoever let go keeps owning the thing's motion.
const OWN_AFTER_DROP := 4.0
## A follower lets go of a thing it has heard nothing about for this long.
const FOLLOW_TIMEOUT := 0.6

var _send_wait := 0.0
## Bodies this peer was sending for last tick, so it can say when they rest.
var _sending := {}
## Bodies this peer is following, with when it last heard about each.
var _following := {}


static func ensure(scene: Node) -> void:
	if scene and scene.get_node_or_null("LooseBodySync") == null:
		var sync := Node.new()
		sync.name = "LooseBodySync"
		sync.set_script(load("res://scripts/loose_body_sync.gd"))
		scene.add_child(sync)


static func mark_dropped(body: Node, by: int) -> void:
	## Called on every peer when someone lets go of a thing.
	body.set_meta("moved_by", by)
	body.set_meta("moved_until", Time.get_ticks_msec() / 1000.0 + OWN_AFTER_DROP)


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_online():
		return
	var now := Time.get_ticks_msec() / 1000.0
	# Following: hand things back to local physics when the owner goes quiet.
	for body: RigidBody3D in _following.keys():
		if not is_instance_valid(body):
			_following.erase(body)
		elif now - float(_following[body]) > FOLLOW_TIMEOUT or body.has_meta("held_by"):
			_stop_following(body)
	_send_wait -= delta
	if _send_wait > 0.0:
		return
	_send_wait = 1.0 / SEND_RATE
	var me := multiplayer.get_unique_id()
	var still_sending := {}
	for group in GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as RigidBody3D
			if body == null or not body.is_inside_tree() or _following.has(body) or body.has_meta("held_by"):
				continue
			if body.freeze or not body.visible or body.get_meta("stowed", false):
				continue
			if _owner_of(body, now) != me:
				continue
			if body.sleeping:
				if _sending.has(body):
					_rest.rpc(body.get_path(), body.global_transform)
				continue
			still_sending[body] = true
			_motion.rpc(body.get_path(), body.global_transform, body.linear_velocity, body.angular_velocity)
	# Anything that stopped being ours or vanished mid-flight: send where it ended.
	for body: RigidBody3D in _sending.keys():
		if not still_sending.has(body) and is_instance_valid(body) and body.is_inside_tree() and not body.has_meta("held_by") and not body.sleeping:
			_rest.rpc(body.get_path(), body.global_transform)
	_sending = still_sending


func _owner_of(body: Node, now: float) -> int:
	if body.has_meta("moved_by") and now < float(body.get_meta("moved_until", 0.0)):
		return int(body.get_meta("moved_by"))
	return 1


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _motion(path: NodePath, where: Transform3D, linear: Vector3, angular: Vector3) -> void:
	var body := get_node_or_null(path) as RigidBody3D
	if body == null or body.has_meta("held_by") or body.get_meta("stowed", false):
		return
	if not _following.has(body):
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
		body.set_meta("net_follow", true)
	_following[body] = Time.get_ticks_msec() / 1000.0
	body.global_transform = where
	body.linear_velocity = linear
	body.angular_velocity = angular


@rpc("any_peer", "call_remote", "reliable")
func _rest(path: NodePath, where: Transform3D) -> void:
	var body := get_node_or_null(path) as RigidBody3D
	if body == null or body.has_meta("held_by") or body.get_meta("stowed", false):
		return
	body.global_transform = where
	if _following.has(body):
		_stop_following(body)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = true


func _stop_following(body: RigidBody3D) -> void:
	_following.erase(body)
	if body.has_meta("net_follow"):
		body.remove_meta("net_follow")
		if not body.has_meta("held_by") and not body.get_meta("stowed", false):
			body.freeze = false
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.sleeping = true


static func release_follow(body: RigidBody3D) -> void:
	## A player is taking hold of something this peer was following.
	if body.has_meta("net_follow"):
		body.remove_meta("net_follow")
		body.freeze = false
