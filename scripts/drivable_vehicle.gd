extends "res://addons/gevp/scripts/vehicle.gd"

const CrosshairTarget := preload("res://scripts/crosshair_target.gd")

const ENGINE_MOUNT := preload("res://assets/audio/vehicle/engine_mount.wav")
const DOOR_LATCH := preload("res://assets/audio/vehicle/door_latch.wav")
const WHEEL_MOUNT := preload("res://assets/audio/vehicle/wheel_mount.wav")
const PANEL_RATTLE := preload("res://assets/audio/vehicle/panel_rattle.wav")
const WELD_SOUND_PATH := "res://assets/audio/weld.wav"
const CarModel := preload("res://scripts/compact_car_model.gd")
const PropShapes := preload("res://scripts/prop_shapes.gd")
const TireEffects := preload("res://scripts/tire_effects.gd")
const ENGINE_LOOPS := {
	"Stock": preload("res://addons/gevp/sounds/4000.wav"),
	"Bike": preload("res://addons/gevp/sounds/4000.wav"),
	"V8": preload("res://assets/audio/engines/v8_loop.wav"),
	"Electric": preload("res://assets/audio/engines/electric_loop.wav"),
}
const ENGINE_STARTS := {
	"Stock": preload("res://assets/audio/vehicle/stock_start.wav"),
	"Bike": preload("res://assets/audio/vehicle/stock_start.wav"),
	"V8": preload("res://assets/audio/vehicle/v8_start.wav"),
	"Electric": preload("res://assets/audio/vehicle/electric_start.wav"),
}
const ENTER_SOUND := preload("res://assets/audio/vehicle/enter.wav")
const EXIT_SOUND := preload("res://assets/audio/vehicle/exit.wav")

const ENGINE_MODELS := {
	"Stock": preload("res://assets/vehicles/parts/stockengine.glb"),
	"V8": preload("res://assets/vehicles/parts/v8engine.glb"),
	"Electric": preload("res://assets/vehicles/parts/electricmotor.glb"),
}
const RADIATOR_MODEL := preload("res://assets/vehicles/parts/radiatorassembly.glb")
const BATTERY_MODEL := preload("res://assets/vehicles/parts/batterypack.glb")
const BIKE_ENGINE_MODEL := preload("res://assets/vehicles/parts/bike_engine.tscn")
const AIR_FILTER_MODEL := preload("res://assets/vehicles/parts/airfilter.glb")
const COOLANT_RESERVOIR_MODEL := preload("res://assets/vehicles/parts/coolantreservoir.glb")

@export var wheel_model_root: Node3D
@export var camera_rig: Node3D
@export var driver_camera: Camera3D
@export var first_person_camera_marker: Node3D
@export var exit_point: Marker3D
@export var mouse_sensitivity: float = 0.0025
@export var min_camera_pitch: float = -75.0
@export var max_camera_pitch: float = 82.0
@export var interact_distance: float = 6.0
@export_enum("Petrol", "Diesel") var fuel_type: String = "Petrol"
@export var max_fuel: float = 60.0
@export var fuel_amount: float = 0.0
@export var idle_fuel_burn_rate: float = 0.015
@export var throttle_fuel_burn_rate: float = 0.08
@export var part_snap_distance: float = 1.35
@export var start_with_random_body_color: bool = true
@export var start_with_removed_panels: bool = true
@export_range(0, 12, 1) var minimum_missing_starting_parts: int = 2
@export_range(0, 12, 1) var maximum_missing_starting_parts: int = 4
@export_enum("Sedan", "Hatchback", "Wagon") var body_style := 0
@export_enum("Original", "Touring", "Rally", "Fleet") var sedan_trim := 0
@export var electric_battery_capacity_per_pack: float = 35.0
@export_group("Body Damage")
@export var body_deformation_enabled: bool = true
@export var minimum_deformation_speed: float = 6.0
@export var maximum_deformation_speed: float = 28.0
@export var minimum_dent_radius: float = 0.35
@export var maximum_dent_radius: float = 1.15
@export var maximum_dent_depth: float = 0.42
@export var maximum_vertex_displacement: float = 0.65

var driver: Node3D
var camera_pitch: float = deg_to_rad(18.0)
var camera_yaw: float = 0.0
var hovered_interactable: Area3D
var dragged_interactable: Area3D
var highlight_material: StandardMaterial3D
var snap_ghost_material: StandardMaterial3D
var painted_materials: Dictionary = {}
var part_closed_rotation: Dictionary = {}
var welded_objects: Dictionary = {}
var removable_parts: Dictionary = {}
var starting_engine_variant := "Stock"
var missing_starting_slots: Array[String] = []
var current_engine_variant: String = "Stock"
var base_max_torque: float = 0.0
var base_max_rpm: float = 0.0
var base_idle_fuel_burn_rate: float = 0.0
var base_throttle_fuel_burn_rate: float = 0.0
var electric_charge: float = 0.0
var electric_capacity: float = 0.0
var wired_battery_count: int = 0
var battery_wire_guide: Node3D
var protected_parts: Dictionary = {}
var weld_sound: AudioStream
var base_body_gravity_scale: float = 1.0
var base_body_linear_damp: float = 0.0
var base_body_angular_damp: float = 0.0
var base_body_freeze: bool = false
var base_body_freeze_mode: int = RigidBody3D.FREEZE_MODE_STATIC
var headlights_enabled: bool = false
var headlight_nodes: Array[Light3D] = []
var first_person_camera_enabled: bool = false
var third_person_camera_transform: Transform3D
var deformable_meshes: Array[MeshInstance3D] = []
var deformation_data: Dictionary = {}
var deformation_cooldown: float = 0.0
var seat_occupants := PackedInt32Array()
var network_controls := Vector4.ZERO
var network_input_age := 0.0
var remote_transform: Transform3D
var remote_linear_velocity: Vector3
var remote_angular_velocity: Vector3
var remote_engine_variant := ""
var remote_engine_rpm := 0.0
var remote_engine_load := 0.0
var _vehicle_network_send_elapsed := 0.0
var _vehicle_input_send_elapsed := 0.0
var audible_engine_variant := ""
var ignition_variant := ""
var ignition_remaining := 0.0
var ignition_duration := 0.0
var rear_brake_material: StandardMaterial3D
var rear_reverse_material: StandardMaterial3D
var rear_braking := false
var reverse_lamps: Array[OmniLight3D] = []
var rattle_cooldown := 0.0
var camera_mount_position := Vector3.ZERO
var dashboard_needles: Array[Node3D] = []
var camera_bump := 0.0
var camera_previous_travel := 0.0
var camera_travel_ready := false
var tire_effects: Node3D

@onready var engine_sound: AudioStreamPlayer3D = $EngineSound
@onready var engine_start_sound: AudioStreamPlayer3D = $EngineStartSound
@onready var access_sound: AudioStreamPlayer3D = $AccessSound


func _ready() -> void:
	add_to_group("drivable")
	contact_monitor = true
	max_contacts_reported = 16
	continuous_cd = true
	_capture_base_body_physics()
	_setup_highlight_material()
	_setup_snap_ghost_material()
	_setup_sound_effects()
	if wheel_model_root:
		CarModel.new().build(wheel_model_root, body_style)
		for title in ["SpeedNeedle", "RpmNeedle", "FuelNeedle"]:
			dashboard_needles.append(wheel_model_root.find_child(title, true, false) as Node3D)
	_setup_interactables()
	_setup_protected_parts()
	_setup_headlights()
	_setup_rear_lights()
	_attach_model_wheels()
	_setup_body_deformation()
	_setup_engine_bay_models()
	_setup_removable_parts()
	_assign_trip_part_ids()
	if GameSettings and not GameSettings.settings_changed.is_connected(_apply_graphics_quality):
		GameSettings.settings_changed.connect(_apply_graphics_quality)
	_apply_graphics_quality()

	if camera_rig == null and driver_camera:
		camera_rig = driver_camera.get_parent() as Node3D
	if camera_rig:
		camera_mount_position = camera_rig.position
		camera_pitch = absf(camera_rig.rotation.x)
		camera_yaw = camera_rig.rotation.y
		_update_camera_rotation()

	if driver_camera:
		driver_camera.add_to_group("driving_camera")
		third_person_camera_transform = driver_camera.transform
		driver_camera.current = false

	initialize()
	tire_effects = TireEffects.new()
	tire_effects.name = "TireEffects"
	add_child(tire_effects)
	_capture_base_vehicle_stats()
	_setup_battery_wire_guide()
	if start_with_random_body_color and not TripSave.continue_requested:
		_apply_random_body_color()
	_apply_automotive_finish()
	if sedan_trim != 0:
		_apply_sedan_trim()
	for slot in missing_starting_slots:
		_omit_starting_part(slot)
	if start_with_removed_panels and not TripSave.continue_requested:
		_remove_starting_body_panels.call_deferred()
	if NetworkManager.is_online() and not is_multiplayer_authority():
		remote_transform = global_transform
		remote_linear_velocity = linear_velocity
		remote_angular_velocity = angular_velocity
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func _exit_tree() -> void:
	for audio in [engine_sound, engine_start_sound, access_sound]:
		if audio:
			audio.stop()


func _unhandled_input(event: InputEvent) -> void:
	var local_player := get_tree().get_first_node_in_group("local_player")
	if local_player and local_player.gameplay_ui_open():
		return
	if not driver_camera or not driver_camera.current or (NetworkManager.is_online() and not seat_occupants.has(multiplayer.get_unique_id())):
		if not _has_driving_camera():
			_handle_interactable_input(event)
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var scaled_sensitivity := mouse_sensitivity * GameSettings.mouse_sensitivity_scale
		camera_yaw -= event.relative.x * scaled_sensitivity
		camera_pitch = clamp(
			camera_pitch + event.relative.y * scaled_sensitivity,
			deg_to_rad(min_camera_pitch),
			deg_to_rad(max_camera_pitch)
		)
		_update_camera_rotation()

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C and _local_seat_can_toggle_camera():
		set_first_person_camera_enabled(not first_person_camera_enabled)


func _local_seat_can_toggle_camera() -> bool:
	return not NetworkManager.is_online() or seat_occupants.find(multiplayer.get_unique_id()) == 0


func enter(player: Node3D, restoring: bool = false) -> void:
	driver = player
	_latch_entry_door(player.global_position)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_first_person_camera_enabled(false)
	if driver_camera:
		driver_camera.current = true
	if not restoring:
		_play_vehicle_access_audio(true)
		if NetworkManager.is_online() and is_multiplayer_authority():
			_play_vehicle_access_audio.rpc(true)
	else:
		ignition_variant = _get_running_engine_variant()
		audible_engine_variant = ignition_variant


func get_vehicle_title() -> String:
	return ["sedan", "hatchback", "wagon"][body_style] if wheel_model_root else "vehicle"


func seat_capacity() -> int:
	return 4 if removable_parts.has("door_fl") else 1


func request_ride() -> void:
	if multiplayer.is_server():
		_request_ride()
	else:
		_request_ride.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_ride() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _request_peer_id()
	var rider := get_tree().current_scene.get_node_or_null(str(peer_id)) as Node3D
	if rider == null or not _can_reach(peer_id) or rider.active_vehicle != null:
		return
	if linear_velocity.length() > 4.0 or not can_enter_from_position(rider.global_position):
		return
	if seat_occupants.is_empty():
		seat_occupants.resize(seat_capacity())
	var seat := seat_occupants.find(0)
	if seat == -1:
		return
	seat_occupants[seat] = peer_id
	_latch_entry_door(rider.global_position)
	_sync_seats.rpc(seat_occupants)
	_play_vehicle_access_audio.rpc(true)


func request_leave() -> void:
	if multiplayer.is_server():
		_request_leave()
	else:
		_request_leave.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_leave() -> void:
	if multiplayer.is_server():
		_release_seat(_request_peer_id())


func remove_disconnected_rider(peer_id: int) -> void:
	if multiplayer.is_server():
		_release_seat(peer_id)


func _release_seat(peer_id: int) -> void:
	var seat := seat_occupants.find(peer_id)
	if seat < 0:
		return
	seat_occupants[seat] = 0
	_sync_seats.rpc(seat_occupants)
	_play_vehicle_access_audio.rpc(false)


@rpc("authority", "call_local", "reliable")
func _sync_seats(occupants: PackedInt32Array) -> void:
	seat_occupants = occupants
	var world := get_tree().current_scene
	var next_driver := world.get_node_or_null(str(occupants[0])) as Node3D
	if driver != next_driver:
		driver = next_driver
		network_controls = Vector4.ZERO
		network_input_age = 0.0
	for rider in get_tree().get_nodes_in_group("road_stream_player"):
		var seat := occupants.find(rider.get_multiplayer_authority())
		if seat >= 0 or rider.active_vehicle == self:
			rider.set_shared_seat(self, seat)



func activate_shared_camera() -> void:
	camera_yaw = 0.0
	camera_pitch = deg_to_rad(18.0)
	_update_camera_rotation()
	set_first_person_camera_enabled(false)
	driver_camera.make_current()


func _request_peer_id() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return multiplayer.get_unique_id() if sender == 0 else sender


func _can_reach(peer_id: int, distance := 8.0) -> bool:
	var player := get_tree().current_scene.get_node_or_null(str(peer_id)) as Node3D
	return is_instance_valid(player) and player.global_position.distance_squared_to(global_position) <= distance * distance


func send_driver_controls(delta: float) -> void:
	if not is_instance_valid(driver) or not driver.is_multiplayer_authority() or seat_occupants.is_empty():
		return
	_vehicle_input_send_elapsed += delta
	if _vehicle_input_send_elapsed < 0.033:
		return
	_vehicle_input_send_elapsed = 0.0
	_receive_driver_controls.rpc_id(1, _read_driver_controls())


@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func _receive_driver_controls(controls: Vector4) -> void:
	if not multiplayer.is_server() or seat_occupants.is_empty() or seat_occupants[0] != multiplayer.get_remote_sender_id():
		return
	if controls.is_finite():
		network_controls = controls.clamp(Vector4(0, 0, -1, 0), Vector4.ONE)
		network_input_age = 0.0


func _read_driver_controls() -> Vector4:
	var world := get_tree().current_scene
	var pause_menu := world.get_node_or_null("PauseMenu") if world else null
	if pause_menu and pause_menu.gameplay_ui_open():
		return Vector4.ZERO
	return Vector4(
		_action_or_keys("Throttle", [KEY_W, KEY_UP]),
		_action_or_keys("Brakes", [KEY_S, KEY_DOWN]),
		_action_or_keys("SteerLeft", [KEY_A, KEY_LEFT]) - _action_or_keys("SteerRight", [KEY_D, KEY_RIGHT]),
		_action_or_keys("Handbrake", [KEY_SPACE])
	)


func request_work(action: String, target: Variant, value: Variant = null) -> void:
	if multiplayer.is_server():
		_request_work(action, target, value)
	else:
		_request_work.rpc_id(1, action, target, value)


@rpc("any_peer", "call_remote", "reliable")
func _request_work(action: String, target: Variant, value: Variant) -> void:
	if not multiplayer.is_server() or not _can_reach(_request_peer_id()):
		return
	var requester := get_tree().current_scene.get_node(str(_request_peer_id()))
	if requester.active_vehicle != null and (action != "lights" or requester.active_vehicle != self):
		return
	match action:
		"panel":
			if target is StringName and value is float and is_finite(value):
				var area := get_node_or_null(NodePath(target)) as Area3D
				if area and area.get_parent() == self and area.is_in_group("car_interactable") and area.collision_layer != 0:
					_drag_interactable(area, clampf(value, -170, 170))
		"paint":
			if target in ["Chassis", "FL_Door", "FR_Door", "RL_Door", "RR_Door"] and value is Vector2 and value.is_finite():
				var swatches: Array = get_tree().current_scene.get_node(str(_request_peer_id())).spray_colors
				var index := clampi(int(value.x), 0, swatches.size() - 1)
				if paint_named_part(target, swatches[index], clampf(value.y, 0, 0.15)):
					_sync_paint.rpc(get_trip_paint())
		"lights":
			toggle_headlights()
		"remove":
			if target is NodePath:
				var area := get_node_or_null(target) as Area3D
				var body := remove_installed_part(area) if area and area.get_parent() == self else null
				if body:
					var peer_id := _request_peer_id()
					if peer_id == 1:
						_grab_removed_part(body.get_path())
					else:
						_grab_removed_part.rpc_id(peer_id, body.get_path())
		"install", "fuel", "weld", "unweld", "wire":
			if target is NodePath:
				var object := get_node_or_null(target) as RigidBody3D
				if is_instance_valid(object) and object.global_position.distance_squared_to(global_position) <= 25.0:
					_work_on_object(action, object, value)


func _work_on_object(action: String, object: RigidBody3D, value: Variant) -> void:
	match action:
		"install":
			if value is Transform3D and value.is_finite() and value.origin.distance_squared_to(global_position) <= 25.0:
				var previous_position := object.global_position
				object.global_position = value.origin
				if not install_part(object):
					object.global_position = previous_position
		"fuel":
			if object.is_in_group("fuel_canister") and value is float and is_finite(value) and object.global_position.distance_to(get_gas_hole_position()) < 1.6:
				var accepted := receive_fuel(minf(object.fuel_amount, clampf(value, 0, 0.8)))
				object.fuel_amount -= accepted
				if accepted > 0.0:
					_sync_canister.rpc(object.get_path(), object.fuel_amount)
		"weld":
			var path := object.get_path()
			var pose := object.global_transform
			if can_weld_object(object) and weld_object(object):
				_sync_attachment.rpc(action, path, pose)
		"unweld", "wire":
			var path := object.get_path()
			if (unweld_object(object) if action == "unweld" else wire_battery(object)):
				_sync_attachment.rpc(action, path, object.global_transform)


@rpc("authority", "call_remote", "reliable")
func _sync_attachment(action: String, path: NodePath, pose: Transform3D) -> void:
	var object := get_node_or_null(path) as RigidBody3D
	if object == null:
		return
	match action:
		"weld":
			object.global_transform = pose
			weld_object(object)
		"unweld":
			unweld_object(object)
			object.global_transform = pose
		"wire":
			object.set_meta("wired_battery", true)
			_refresh_electric_capacity()


@rpc("authority", "call_remote", "reliable")
func _sync_canister(path: NodePath, amount: float) -> void:
	var canister := get_node_or_null(path)
	if canister and canister.is_in_group("fuel_canister"):
		canister.fuel_amount = amount


@rpc("authority", "call_remote", "reliable")
func _grab_removed_part(path: NodePath) -> void:
	var object := get_node_or_null(path) as RigidBody3D
	var player := get_tree().current_scene.get_node_or_null(str(multiplayer.get_unique_id()))
	if player and object:
		player._begin_grab_object(object, object.global_position)


@rpc("authority", "call_remote", "reliable")
func _sync_paint(paint: Dictionary) -> void:
	restore_trip_paint(paint)


@rpc("authority", "call_remote", "reliable")
func _sync_panels(panels: Dictionary) -> void:
	restore_trip_panel_rotations(panels)


func can_enter_from_position(player_position: Vector3) -> bool:
	var local_player := to_local(player_position)
	var left := local_player.x < 0.0
	var rear := NetworkManager.is_online() and local_player.z > 0.45
	var door_type := ("door_rl" if left else "door_rr") if rear else ("door_fl" if left else "door_fr")
	var area_name := ("DoorRL" if left else "DoorRR") if rear else ("DoorFL" if left else "DoorFR")
	if removable_parts.has(door_type):
		var door_data: Dictionary = removable_parts[door_type]
		if not bool(door_data.get("installed", true)):
			return true

	var area := get_node_or_null(area_name) as Area3D
	if area == null:
		return true
	var part := _get_interactable_part(area)
	if part == null:
		return true
	var open_direction := float(area.get_meta("open_direction", 1.0))
	var closed_rotation := part_closed_rotation.get(part.get_path(), part.rotation) as Vector3
	return _get_interactable_open_amount(area, part, closed_rotation, open_direction) > 0.42


func get_cabin_enclosure() -> float:
	var enclosure := 1.0
	for slot in ["door_fl", "door_fr", "door_rl", "door_rr"]:
		if not removable_parts.has(slot):
			return 0.0 # Open frame on both two-wheelers.
		var data: Dictionary = removable_parts[slot]
		var loss := 0.73 if slot in ["door_fl", "door_fr"] else 0.44
		if not data["installed"]:
			enclosure -= loss
			continue
		var area := data["area"] as Area3D
		var part := _get_interactable_part(area)
		if part:
			var closed: Vector3 = part_closed_rotation.get(part.get_path(), part.rotation)
			var opened := _get_interactable_open_amount(area, part, closed, area.get_meta("open_direction", 1.0))
			enclosure -= loss * smoothstep(0.0, 0.65, opened)
	return clampf(enclosure, 0.0, 1.0)


func exit() -> Vector3:
	if is_instance_valid(driver):
		_play_vehicle_access_audio(false)
		if NetworkManager.is_online() and is_multiplayer_authority():
			_play_vehicle_access_audio.rpc(false)
	driver = null
	ignition_variant = ""
	ignition_remaining = 0.0
	_clear_inputs()
	_update_engine_audio(0.0, "", 0.0, 0.0)

	if driver_camera:
		driver_camera.current = false

	return exit_point.global_position if exit_point else global_position + global_transform.basis.x * -3.0


@rpc("authority", "call_remote", "reliable")
func _play_vehicle_access_audio(entering: bool) -> void:
	access_sound.stream = ENTER_SOUND if entering else EXIT_SOUND
	access_sound.play()


func _physics_process(delta: float) -> void:
	if NetworkManager.is_online() and not is_multiplayer_authority():
		send_driver_controls(delta)
		global_transform = global_transform.interpolate_with(remote_transform, minf(delta * 12.0, 1.0))
		linear_velocity = remote_linear_velocity
		angular_velocity = remote_angular_velocity
		_update_engine_audio(delta, remote_engine_variant, remote_engine_rpm, remote_engine_load)
		tire_effects.update_tires(wheel_array, linear_velocity, delta, true)
		_update_rolling_feedback(delta)
		return

	network_input_age += delta
	_restore_base_body_physics()
	if global_position.y < -15.0:
		global_position.y = 2.0
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	_repair_protected_parts()
	_update_ignition(delta)
	_update_driver_inputs()
	_update_fuel(delta)
	super._physics_process(delta)
	tire_effects.update_tires(wheel_array, linear_velocity, delta, false)
	rear_braking = brake_amount > 0.08 or handbrake_input > 0.1
	_update_rolling_feedback(delta)
	var audible_variant := _get_running_engine_variant()
	_update_engine_audio(delta, audible_variant, motor_rpm, throttle_amount)
	_send_vehicle_network_state(delta, audible_variant)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if NetworkManager.is_online() and not is_multiplayer_authority():
		return

	super._integrate_forces(state)
	deformation_cooldown = maxf(deformation_cooldown - state.step, 0.0)
	if not body_deformation_enabled or deformation_cooldown > 0.0:
		return

	var strongest_speed := minimum_deformation_speed
	var impact_position := Vector3.ZERO
	var impact_normal := Vector3.ZERO
	for index in range(state.get_contact_count()):
		var local_position := state.get_contact_local_position(index)
		var local_normal := state.get_contact_local_normal(index).normalized()
		var world_offset := state.transform.basis * local_position
		var point_velocity := state.linear_velocity + state.angular_velocity.cross(world_offset)
		var collider_velocity := state.get_contact_collider_velocity_at_position(index)
		var world_normal := (state.transform.basis * local_normal).normalized()
		var impact_speed := absf((point_velocity - collider_velocity).dot(world_normal))
		var contact_impulse := state.get_contact_impulse(index).length()
		impact_speed = maxf(impact_speed, contact_impulse / maxf(mass * 0.16, 1.0))
		if impact_speed <= strongest_speed:
			continue
		strongest_speed = impact_speed
		impact_position = state.transform * local_position
		impact_normal = world_normal

	if strongest_speed > minimum_deformation_speed:
		deformation_cooldown = 0.16
		_apply_collision_deformation.call_deferred(impact_position, impact_normal, strongest_speed)


func _process(_delta: float) -> void:
	if driver_camera and driver_camera.current:
		_update_camera_suspension(_delta)
		_update_camera_rotation()
	else:
		camera_travel_ready = false
	_update_third_person_camera_collision()
	if is_multiplayer_authority():
		_repair_protected_parts()
	_update_snap_ghost_visibility()
	_update_battery_wire_guide()

	if _has_driving_camera():
		dragged_interactable = null
		_set_hovered_interactable(null)
		return

	if dragged_interactable:
		return

	_set_hovered_interactable(_find_pointed_interactable())


func _send_vehicle_network_state(delta: float, audible_variant: String) -> void:
	if not NetworkManager.is_online():
		return

	_vehicle_network_send_elapsed += delta
	if _vehicle_network_send_elapsed < 0.05:
		return

	_vehicle_network_send_elapsed = 0.0
	sync_vehicle_state.rpc(
		global_transform, linear_velocity, angular_velocity, headlights_enabled,
		audible_variant, motor_rpm, throttle_amount, fuel_amount, electric_charge,
		current_gear, _wheel_motion(), Vector3(ignition_remaining, ignition_duration, float(rear_braking))
	)


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func sync_vehicle_state(
	new_transform: Transform3D,
	new_linear_velocity: Vector3,
	new_angular_velocity: Vector3,
	new_headlights_enabled: bool,
	new_engine_variant: String,
	new_engine_rpm: float,
	new_engine_load: float,
	new_fuel: float,
	new_charge: float,
	new_gear: int,
	wheels: Array,
	feedback: Vector3
) -> void:
	remote_transform = new_transform
	remote_linear_velocity = new_linear_velocity
	remote_angular_velocity = new_angular_velocity
	remote_engine_variant = new_engine_variant
	remote_engine_rpm = new_engine_rpm
	remote_engine_load = new_engine_load
	ignition_remaining = feedback.x
	ignition_duration = feedback.y
	rear_braking = feedback.z > 0.5
	motor_rpm = new_engine_rpm
	fuel_amount = new_fuel
	electric_charge = new_charge
	current_gear = new_gear
	for i in mini(wheel_array.size(), wheels.size()):
		var wheel: Wheel = wheel_array[i]
		var motion: Vector3 = wheels[i]
		wheel.rotation.y = motion.x
		wheel.spin = motion.y
		wheel.spring_current_length = motion.z
	if headlights_enabled != new_headlights_enabled:
		set_headlights_enabled(new_headlights_enabled)


func _wheel_motion() -> Array[Vector3]:
	var motion: Array[Vector3] = []
	for wheel in wheel_array:
		motion.append(Vector3(wheel.rotation.y, wheel.spin, wheel.spring_current_length))
	return motion


func _update_driver_inputs() -> void:
	if driver == null:
		_clear_inputs()
		return

	var controls := _read_driver_controls()
	if NetworkManager.is_online() and not driver.is_multiplayer_authority():
		controls = network_controls if network_input_age < 0.4 else Vector4.ZERO
	throttle_input = controls.x if current_gear != -1 else controls.y
	brake_input = controls.y if current_gear != -1 else controls.x
	steering_input = controls.z
	handbrake_input = controls.w
	clutch_input = handbrake_input

	if not _has_drive_energy() or not _has_required_drive_parts() or ignition_remaining > 0.0:
		throttle_input = 0.0
		throttle_amount = 0.0
		clutch_input = 1.0


func _clear_inputs() -> void:
	throttle_input = 0.0
	brake_input = 0.0
	steering_input = 0.0
	handbrake_input = 0.0
	clutch_input = 0.0


func _update_ignition(delta: float) -> void:
	var variant := _get_running_engine_variant()
	if variant != ignition_variant:
		ignition_variant = variant
		var sample := ENGINE_STARTS.get(variant) as AudioStream
		ignition_duration = maxf(0.0, sample.get_length() - 0.14) if sample else 0.0
		ignition_remaining = ignition_duration
	else:
		ignition_remaining = maxf(0.0, ignition_remaining - delta)


func ignition_progress() -> float:
	return 1.0 - ignition_remaining / ignition_duration if ignition_remaining > 0.0 else 1.0


func _get_running_engine_variant() -> String:
	if not is_instance_valid(driver) or not _has_drive_energy() or not _has_required_drive_parts():
		return ""
	return current_engine_variant


func _update_engine_audio(delta: float, variant: String, rpm: float, engine_load: float) -> void:
	if variant != audible_engine_variant:
		audible_engine_variant = variant
		engine_start_sound.stop()
		var start_stream := ENGINE_STARTS.get(variant) as AudioStream
		if start_stream:
			engine_start_sound.stream = start_stream
			engine_start_sound.play()

	var blend := 1.0 - exp(-14.0 * delta)
	var stream := ENGINE_LOOPS.get(variant) as AudioStream
	var load_amount := clampf(engine_load, 0.0, 1.0)
	var target_volume := -60.0
	var target_pitch := engine_sound.pitch_scale
	if stream:
		match variant:
			"Stock":
				target_pitch = clampf(rpm / 4000.0, 0.28, 2.0)
				target_volume = lerpf(-21.0, -9.0, load_amount)
			"Bike":
				target_pitch = clampf(rpm / 3400.0, 0.45, 2.3)
				target_volume = lerpf(-24.0, -12.0, load_amount)
			"V8":
				target_pitch = lerpf(0.65, 1.75, clampf(rpm / 7800.0, 0.0, 1.0))
				target_volume = lerpf(-17.0, -6.0, load_amount)
			"Electric":
				var revs := clampf(inverse_lerp(idle_rpm, 6500.0, rpm), 0.0, 1.0)
				target_pitch = lerpf(0.48, 2.0, revs)
				target_volume = lerpf(-60.0, -17.0, maxf(load_amount, revs * 0.85))

		if engine_sound.stream != stream:
			engine_sound.stream = stream
			engine_sound.volume_db = -60.0
			engine_sound.pitch_scale = target_pitch
		if engine_start_sound.playing:
			var remaining := engine_start_sound.stream.get_length() - engine_start_sound.get_playback_position()
			target_volume -= 18.0 * clampf(remaining / 0.35, 0.0, 1.0)
		if ignition_remaining > 0.0:
			target_volume = -60.0
		if target_volume > -55.0 and not engine_sound.playing:
			engine_sound.play()

	engine_sound.pitch_scale = lerpf(engine_sound.pitch_scale, target_pitch, blend)
	engine_sound.volume_db = lerpf(engine_sound.volume_db, target_volume, blend)
	if target_volume <= -55.0 and engine_sound.volume_db <= -55.0 and engine_sound.playing:
		engine_sound.stop()


func _setup_rear_lights() -> void:
	var mount := _find_part_node("RearLightMount")
	if mount == null:
		return
	var lenses := mount.find_children("BrakeLens*", "MeshInstance3D", false, false)
	if lenses.is_empty():
		return
	var material := (lenses[0] as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	rear_brake_material = material.duplicate() as StandardMaterial3D if material else StandardMaterial3D.new()
	rear_brake_material.emission = Color("#ff3020")
	rear_brake_material.emission_energy_multiplier = 1.8
	for lens: MeshInstance3D in lenses:
		lens.material_override = rear_brake_material

	rear_reverse_material = PropShapes.material(Color("#b5ac97"), 0.1, 0.4)
	rear_reverse_material.emission = Color("#fff0d0")
	rear_reverse_material.emission_energy_multiplier = 1.9
	for lens: MeshInstance3D in mount.find_children("ReverseLens*", "MeshInstance3D", false, false):
		lens.material_override = rear_reverse_material
		var lamp := OmniLight3D.new()
		lamp.position = to_local(lens.global_position) + Vector3.BACK * 0.18
		lamp.light_color = Color("#fff0d0")
		lamp.light_energy = 0.25
		lamp.omni_range = 2.1
		lamp.visible = false
		add_child(lamp)
		reverse_lamps.append(lamp)


func _update_dashboard(delta: float) -> void:
	if not first_person_camera_enabled or not driver_camera or not driver_camera.current or dashboard_needles.is_empty():
		return
	var capacity := electric_capacity if current_engine_variant == "Electric" else max_fuel
	var remaining := electric_charge if current_engine_variant == "Electric" else fuel_amount
	var readings := Vector3(linear_velocity.length() * 3.6 / 160.0, motor_rpm / maxf(max_rpm, 1.0), remaining / maxf(capacity, 1.0))
	for i in dashboard_needles.size():
		var needle := dashboard_needles[i]
		var angle := lerpf(2.32, -2.32, clampf(readings[i], 0, 1))
		needle.rotation.z = lerpf(needle.rotation.z, angle, minf(delta * 12, 1))


func _update_rolling_feedback(delta: float) -> void:
	_update_dashboard(delta)
	if rear_brake_material:
		rear_brake_material.emission_enabled = rear_braking or headlights_enabled
		rear_brake_material.emission_energy_multiplier = 1.8 if rear_braking else 0.28
		var reversing := is_instance_valid(driver) and current_gear == -1
		rear_reverse_material.emission_enabled = reversing
		for lamp in reverse_lamps:
			lamp.visible = reversing
	rattle_cooldown = maxf(0.0, rattle_cooldown - delta)
	if rattle_cooldown > 0.0 or not is_instance_valid(driver) or linear_velocity.length_squared() < 16.0:
		return
	var view := get_viewport().get_camera_3d()
	if view == null or view.global_position.distance_squared_to(global_position) > 160.0:
		return
	for slot in ["hood", "trunk", "door_fl", "door_fr", "door_rl", "door_rr"]:
		if not removable_parts.has(slot) or not removable_parts[slot]["installed"]:
			continue
		var area: Area3D = removable_parts[slot]["area"]
		var panel := _get_interactable_part(area)
		if panel == null:
			continue
		var closed: Vector3 = part_closed_rotation.get(panel.get_path(), panel.rotation)
		var open_amount := _get_interactable_open_amount(area, panel, closed, area.get_meta("open_direction"))
		if open_amount > 0.035 and open_amount < 0.48:
			_play_sfx_3d(PANEL_RATTLE, panel.global_position, -24.0)
			rattle_cooldown = randf_range(0.48, 1.25)
			return


func _update_camera_suspension(delta: float) -> void:
	var travel := 0.0
	var count := 0
	for wheel in wheel_array:
		if wheel.installed:
			travel += wheel.spring_current_length
			count += 1
	travel /= maxi(1, count)
	var impulse := clampf((camera_previous_travel - travel) * 1.6, -0.07, 0.07) if camera_travel_ready else 0.0
	camera_previous_travel = travel
	camera_travel_ready = true
	camera_bump = clampf((camera_bump + impulse) * exp(-10.0 * delta), -0.075, 0.075)
	var speed_gain := smoothstep(1.0, 9.0, linear_velocity.length())
	camera_rig.position = _active_camera_mount() + Vector3.UP * camera_bump * speed_gain * GameSettings.camera_motion


func _active_camera_mount() -> Vector3:
	if first_person_camera_enabled and wheel_model_root and first_person_camera_marker:
		return camera_mount_position + first_person_camera_marker.position
	return camera_mount_position


func _capture_base_body_physics() -> void:
	base_body_gravity_scale = gravity_scale
	base_body_linear_damp = linear_damp
	base_body_angular_damp = angular_damp
	base_body_freeze = freeze
	base_body_freeze_mode = freeze_mode


func _restore_base_body_physics() -> void:
	gravity_scale = base_body_gravity_scale
	linear_damp = base_body_linear_damp
	angular_damp = base_body_angular_damp
	freeze = base_body_freeze
	freeze_mode = base_body_freeze_mode


func _setup_headlights() -> void:
	headlight_nodes.clear()
	for child in get_tree().get_nodes_in_group("vehicle_headlight"):
		if child is Light3D and is_ancestor_of(child):
			headlight_nodes.append(child as Light3D)
	for path in ["LeftHeadlight", "RightHeadlight"]:
		var light := get_node_or_null(path) as Light3D
		if light and not headlight_nodes.has(light):
			headlight_nodes.append(light)
	for light in headlight_nodes:
		light.visible = true
		light.set_meta("headlight_energy", 24.0)
		_configure_headlight_transform(light)

	set_headlights_enabled(false)


func _setup_body_deformation() -> void:
	deformable_meshes.clear()
	deformation_data.clear()
	if wheel_model_root == null:
		return

	for node in wheel_model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or not mesh_instance.mesh is ArrayMesh:
			continue
		var mesh_name := mesh_instance.name.to_lower()
		if not mesh_instance.get_meta("body_paint", false) and mesh_name not in ["frontbumper", "rearbumper"]:
			continue
		if mesh_name.contains("interior") or mesh_name.contains("window"):
			continue
		_make_mesh_deformable(mesh_instance)


func _make_mesh_deformable(mesh_instance: MeshInstance3D) -> void:
	var source_mesh := mesh_instance.mesh
	var runtime_mesh := ArrayMesh.new()
	var surfaces: Array = []

	for surface_index in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		if vertices.is_empty():
			continue
		var surface := {
			"primitive": source_mesh.surface_get_primitive_type(surface_index),
			"arrays": arrays,
			"original_vertices": vertices.duplicate(),
			"material": source_mesh.surface_get_material(surface_index),
			"name": source_mesh.surface_get_name(surface_index),
		}
		surfaces.append(surface)
		runtime_mesh.add_surface_from_arrays(surface["primitive"], arrays)
		var new_index := runtime_mesh.get_surface_count() - 1
		runtime_mesh.surface_set_material(new_index, surface["material"])
		runtime_mesh.surface_set_name(new_index, surface["name"])

	if surfaces.is_empty():
		return

	mesh_instance.mesh = runtime_mesh
	deformable_meshes.append(mesh_instance)
	deformation_data[mesh_instance] = surfaces


func _apply_collision_deformation(impact_position: Vector3, impact_normal: Vector3, impact_speed: float) -> void:
	if not is_inside_tree():
		return

	var strength := clampf(
		inverse_lerp(minimum_deformation_speed, maximum_deformation_speed, impact_speed),
		0.0,
		1.0
	)
	var radius := lerpf(minimum_dent_radius, maximum_dent_radius, strength)
	var depth := maximum_dent_depth * smoothstep(0.0, 1.0, strength)
	if depth <= 0.001:
		return

	for mesh_instance in deformable_meshes:
		if not is_instance_valid(mesh_instance) or not deformation_data.has(mesh_instance):
			continue
		_deform_mesh_at_point(mesh_instance, impact_position, impact_normal, radius, depth)


func _deform_mesh_at_point(
	mesh_instance: MeshInstance3D,
	impact_position: Vector3,
	impact_normal: Vector3,
	radius: float,
	depth: float
) -> void:
	var surfaces: Array = deformation_data[mesh_instance]
	var changed := false
	var local_displacement := mesh_instance.global_transform.basis.inverse() * (impact_normal * depth)

	for surface in surfaces:
		var arrays: Array = surface["arrays"]
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var original_vertices := surface["original_vertices"] as PackedVector3Array
		var surface_changed := false
		for vertex_index in range(vertices.size()):
			var world_vertex := mesh_instance.to_global(vertices[vertex_index])
			var distance := world_vertex.distance_to(impact_position)
			if distance >= radius:
				continue

			var falloff := 1.0 - smoothstep(0.0, radius, distance)
			var candidate := vertices[vertex_index] + local_displacement * falloff
			var from_original := candidate - original_vertices[vertex_index]
			if from_original.length() > maximum_vertex_displacement:
				candidate = original_vertices[vertex_index] + from_original.normalized() * maximum_vertex_displacement
			vertices[vertex_index] = candidate
			surface_changed = true

		if surface_changed:
			arrays[Mesh.ARRAY_VERTEX] = vertices
			surface["arrays"] = arrays
			changed = true

	if not changed:
		return

	var rebuilt_mesh := ArrayMesh.new()
	for surface in surfaces:
		var surface_arrays: Array = surface["arrays"]
		rebuilt_mesh.add_surface_from_arrays(surface["primitive"], surface_arrays)
		var new_index := rebuilt_mesh.get_surface_count() - 1
		rebuilt_mesh.surface_set_material(new_index, surface["material"])
		rebuilt_mesh.surface_set_name(new_index, surface["name"])
	mesh_instance.mesh = rebuilt_mesh
	_apply_graphics_quality()


func set_headlights_enabled(enabled: bool) -> void:
	headlights_enabled = enabled
	for light in headlight_nodes:
		if light == null:
			continue
		light.visible = true
		light.light_energy = float(light.get_meta("headlight_energy", 32.0)) if headlights_enabled else 0.0


func toggle_headlights() -> void:
	set_headlights_enabled(not headlights_enabled)
	print("Headlights ", "on" if headlights_enabled else "off")


func _apply_graphics_quality() -> void:
	for light in headlight_nodes:
		if light == null:
			continue
		light.shadow_enabled = false
		if light is SpotLight3D:
			var spot := light as SpotLight3D
			spot.set_meta("headlight_energy", 24.0)
			spot.light_energy = 24.0 if headlights_enabled else 0.0
			spot.light_color = Color(1.0, 0.84, 0.58, 1.0)
			spot.spot_range = 52.0
			spot.spot_angle = 27.0
			spot.spot_attenuation = 0.78
			_configure_headlight_transform(spot)


func _configure_headlight_transform(light: Light3D) -> void:
	if wheel_model_root and light.name in ["LeftHeadlight", "RightHeadlight"]:
		var lenses := wheel_model_root.find_children("HeadlightLens*", "MeshInstance3D", true, false)
		if lenses.size() == 2:
			var lens := lenses[0 if light.name == "LeftHeadlight" else 1] as Node3D
			light.position = to_local(lens.global_position) + Vector3.FORWARD * 0.024
	light.rotation_degrees = Vector3(-4.0, 0.0, 0.0)


func set_first_person_camera_enabled(enabled: bool) -> void:
	first_person_camera_enabled = enabled
	if driver_camera == null:
		return

	if first_person_camera_enabled and first_person_camera_marker:
		driver_camera.transform = first_person_camera_marker.transform
		if wheel_model_root:
			driver_camera.position = Vector3.ZERO
	else:
		driver_camera.transform = third_person_camera_transform
	if wheel_model_root and camera_rig:
		camera_rig.position = _active_camera_mount()
		_update_camera_rotation()


func _update_fuel(delta: float) -> void:
	if driver == null:
		return

	var burn_rate := idle_fuel_burn_rate + absf(throttle_input) * throttle_fuel_burn_rate
	if current_engine_variant == "Electric":
		electric_charge = maxf(electric_charge - burn_rate * delta, 0.0)
	elif fuel_amount > 0.0:
		fuel_amount = maxf(fuel_amount - burn_rate * delta, 0.0)


func get_fuel_fraction() -> float:
	if current_engine_variant == "Electric":
		if electric_capacity <= 0.0:
			return 0.0
		return clampf(electric_charge / electric_capacity, 0.0, 1.0)

	if max_fuel <= 0.0:
		return 0.0

	return clampf(fuel_amount / max_fuel, 0.0, 1.0)


func get_fuel_text() -> String:
	if current_engine_variant == "Electric":
		return "Battery %.0f%%" % (get_fuel_fraction() * 100.0)

	return "%s %.0f%%" % [fuel_type, get_fuel_fraction() * 100.0]


func can_receive_fuel() -> bool:
	return fuel_amount < max_fuel and is_gas_cap_open()


func receive_fuel(amount: float) -> float:
	if not can_receive_fuel():
		return 0.0

	var accepted := minf(maxf(amount, 0.0), max_fuel - fuel_amount)
	fuel_amount += accepted
	return accepted


func is_gas_cap_open() -> bool:
	var area := get_node_or_null("GasCapTarget") as Area3D
	if area == null:
		return false

	var part := _get_interactable_part(area)
	if part == null:
		return false

	var open_direction := float(area.get_meta("open_direction", 1.0))
	var closed_rotation := part_closed_rotation.get(part.get_path(), part.rotation) as Vector3
	return _get_interactable_open_amount(area, part, closed_rotation, open_direction) > 0.45


func get_gas_hole_position() -> Vector3:
	var cap := _find_part_node("FuelFiller")
	if cap:
		return cap.global_position

	var target := get_node_or_null("GasCapTarget") as Node3D
	return target.global_position if target else global_position


func can_weld_object(object: RigidBody3D) -> bool:
	if not is_instance_valid(object) or object == self or object.is_in_group("drivable") or object.has_meta("welded_vehicle"):
		return false

	# Loose objects do not collide with cars. Check contact with their actual shapes
	# when the player deliberately attaches one.
	var world := get_world_3d().direct_space_state
	for child in object.get_children():
		var shape := child as CollisionShape3D
		if shape == null or shape.disabled or shape.shape == null:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.collision_mask = 2 | 8
		query.collide_with_areas = false
		query.margin = 0.16
		for hit in world.intersect_shape(query):
			if hit.collider == self or hit.collider.get_meta("welded_vehicle", null) == self:
				return true
	return false


func weld_object(object: RigidBody3D, restoring: bool = false) -> bool:
	if object == null or object == self or welded_objects.has(object):
		return false

	var parent := object.get_parent()
	if parent == null:
		return false

	welded_objects[object] = {
		"parent": parent,
		"collision_layer": object.collision_layer,
		"collision_mask": object.collision_mask,
		"freeze": object.freeze,
		"freeze_mode": object.freeze_mode,
		"gravity_scale": object.gravity_scale,
		"linear_damp": object.linear_damp,
		"angular_damp": object.angular_damp,
	}

	object.set_meta("welded_vehicle", self)
	object.linear_velocity = Vector3.ZERO
	object.angular_velocity = Vector3.ZERO
	object.freeze = true
	object.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	object.gravity_scale = 0.0
	object.linear_damp = 10.0
	object.angular_damp = 10.0
	# Keep welded parts raycastable without letting them fight the car or ground.
	object.collision_layer = 8
	object.collision_mask = 0
	object.reparent(self, true)
	if not restoring:
		_play_sfx_3d(weld_sound, object.global_position)
	return true


func unweld_object(object: RigidBody3D) -> bool:
	if object == null or not welded_objects.has(object):
		return false

	var data: Dictionary = welded_objects[object]
	var parent := data.get("parent") as Node
	if parent and parent.is_inside_tree():
		object.reparent(parent, true)
	else:
		object.reparent(get_tree().current_scene, true)

	object.collision_layer = int(data.get("collision_layer", object.collision_layer))
	object.collision_mask = int(data.get("collision_mask", object.collision_mask))
	object.freeze = bool(data.get("freeze", false))
	object.freeze_mode = int(data.get("freeze_mode", object.freeze_mode))
	object.gravity_scale = float(data.get("gravity_scale", 1.0))
	object.linear_damp = float(data.get("linear_damp", 0.0))
	object.angular_damp = float(data.get("angular_damp", 0.0))
	object.remove_meta("welded_vehicle")
	if object.has_meta("wired_battery"):
		object.remove_meta("wired_battery")
	welded_objects.erase(object)
	_refresh_electric_capacity()
	return true


func _setup_highlight_material() -> void:
	highlight_material = StandardMaterial3D.new()
	highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight_material.albedo_color = Color(1, 1, 1, 0.38)
	highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_material.no_depth_test = true


func _setup_snap_ghost_material() -> void:
	snap_ghost_material = StandardMaterial3D.new()
	snap_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	snap_ghost_material.albedo_color = Color(1, 1, 1, 0.22)
	snap_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	snap_ghost_material.no_depth_test = true


func _setup_interactables() -> void:
	_register_interactable("DoorFL", ["FL_Door"], -1.0, "y", 72.0)
	_register_interactable("DoorFR", ["FR_Door"], 1.0, "y", 72.0)
	_register_interactable("DoorRL", ["RL_Door"], -1.0, "y", 72.0)
	_register_interactable("DoorRR", ["RR_Door"], 1.0, "y", 72.0)
	_register_interactable("HoodTarget", ["HoodTargetHinge"], 1.0, "x", 68.0)
	_register_interactable("TrunkTarget", ["TrunkTargetHinge"], -1.0, "x", 72.0)
	_register_interactable("GasCapTarget", ["GasCapTargetHinge"], 1.0, "y", 105.0)
	var filler := _find_part_node("FuelFiller")
	if filler:
		_create_removable_part_area(filler, "FuelFillerTarget", Vector3(0.045, 0.175, 0.175))
	_register_interactable("SeatTarget", ["Interior"], 0.0, "y", 0.0)

	var seat := get_node_or_null("SeatTarget") as Area3D
	if seat:
		seat.add_to_group("vehicle_seat")


func _setup_engine_bay_models() -> void:
	var engine := _find_part_node("Engine") as MeshInstance3D
	var radiator := _find_part_node("Radiator") as MeshInstance3D
	var battery := _find_part_node("Battery") as MeshInstance3D
	current_engine_variant = starting_engine_variant
	if engine and current_engine_variant == "Bike":
		var bike_engine := BIKE_ENGINE_MODEL.instantiate() as MeshInstance3D
		var mount := engine.get_parent_node_3d()
		bike_engine.name = engine.name
		bike_engine.transform = engine.transform
		mount.remove_child(engine)
		engine.queue_free()
		mount.add_child(bike_engine)
		engine = bike_engine
	else:
		_replace_part_mesh(engine, ENGINE_MODELS[current_engine_variant])
	_replace_part_mesh(radiator, RADIATOR_MODEL)
	_replace_part_mesh(battery, BATTERY_MODEL)

	if engine:
		var model_root := engine.get_parent_node_3d()
		var air_filter := AIR_FILTER_MODEL.instantiate() as Node3D
		air_filter.name = "AirFilter"
		air_filter.position = engine.position + Vector3(0.535, 0.0, -0.12)
		air_filter.scale = Vector3.ONE * 0.38
		model_root.add_child(air_filter)
		var reservoir := COOLANT_RESERVOIR_MODEL.instantiate() as Node3D
		reservoir.name = "CoolantReservoir"
		reservoir.position = engine.position + Vector3(0.56, 0.04, 0.24)
		reservoir.scale = Vector3.ONE * 0.38
		model_root.add_child(reservoir)


func _replace_part_mesh(part: MeshInstance3D, model: PackedScene) -> void:
	if part == null or part.mesh == null:
		return

	var instance := model.instantiate()
	# Each part asset contains one mesh, with its materials and vertices baked at the mount origin.
	var geometry := instance as MeshInstance3D
	if geometry == null:
		var meshes := instance.find_children("*", "MeshInstance3D", true, false)
		if meshes.size() == 1:
			geometry = meshes[0] as MeshInstance3D
	if geometry != null and geometry.mesh != null:
		if not part.has_meta("original_collision_size"):
			part.set_meta("original_collision_size", _safe_collision_size(part))
		part.mesh = geometry.mesh
		part.material_override = geometry.material_override
		for surface in geometry.mesh.get_surface_count():
			part.set_surface_override_material(surface, geometry.get_surface_override_material(surface))
	instance.free()


func _setup_removable_parts() -> void:
	_register_removable_part("engine", "Engine", Vector3(1.25, 0.75, 1.0))
	_register_removable_part("radiator", "Radiator", Vector3(1.25, 0.75, 0.35))
	_register_removable_part("battery", "Battery", Vector3(0.75, 0.55, 0.75))
	_register_wheel_part("wheel_fl", front_left_wheel, "FrontLeftWheel")
	_register_wheel_part("wheel_fr", front_right_wheel, "FrontRightWheel")
	_register_wheel_part("wheel_rl", rear_left_wheel, "RearLeftWheel")
	_register_wheel_part("wheel_rr", rear_right_wheel, "RearRightWheel")
	_register_removable_interactable("door_fl", "DoorFL", "FrontLeftDoor")
	_register_removable_interactable("door_fr", "DoorFR", "FrontRightDoor")
	_register_removable_interactable("door_rl", "DoorRL", "RearLeftDoor")
	_register_removable_interactable("door_rr", "DoorRR", "RearRightDoor")
	_register_removable_interactable("hood", "HoodTarget", "Hood")
	_register_removable_interactable("trunk", "TrunkTarget", "Trunk")


func _register_removable_part(part_type: String, part_name: String, area_size: Vector3) -> void:
	var part := _find_part_node(part_name)
	if part == null:
		push_warning("Missing removable car part: %s" % part_name)
		return

	var mount_transform := part.transform
	if part_type == "engine" and current_engine_variant == "Bike":
		_fit_installed_engine(part, current_engine_variant)
	var ghost := _create_snap_ghost(part, "%sSnapGhost" % part_name)
	var area := _create_removable_part_area(part, "%sRemoveTarget" % part_name, area_size)
	removable_parts[part_type] = {
		"name": part_name,
		"part": part,
		"parent": part.get_parent(),
		"closed_transform": mount_transform,
		"ghost": ghost,
		"area": area,
		"installed": true,
		"requires_hood_open": true,
	}

	area.set_meta("part_type", part_type)
	area.set_meta("part_name", part_name)
	area.set_meta("part_path", area.get_path_to(part))
	area.set_meta("visual_path", area.get_path_to(part))


func _register_wheel_part(part_type: String, wheel, part_name: String) -> void:
	if wheel == null or wheel.wheel_node == null:
		push_warning("Missing removable wheel: %s" % part_name)
		return

	var part: Node3D = wheel.wheel_node
	var native_radius := front_tire_radius if wheel == front_left_wheel or wheel == front_right_wheel else rear_tire_radius
	part.set_meta("native_wheel_radius", native_radius)
	part.set_meta("native_wheel_scale", part.scale)
	var ghost := _create_snap_ghost(part, "%sSnapGhost" % part_name)
	var area := _create_removable_part_area(part, "%sRemoveTarget" % part_name, Vector3(0.8, 0.8, 0.8))
	removable_parts[part_type] = {
		"name": part_name,
		"part": part,
		"parent": part.get_parent(),
		"closed_transform": part.transform,
		"ghost": ghost,
		"area": area,
		"installed": true,
		"requires_hood_open": false,
		"wheel": wheel,
	}

	area.set_meta("part_type", part_type)
	area.set_meta("part_name", part_name)
	area.set_meta("part_path", area.get_path_to(part))
	area.set_meta("visual_path", area.get_path_to(part))


func _register_removable_interactable(part_type: String, area_name: String, part_name: String) -> void:
	var area := get_node_or_null(area_name) as Area3D
	if area == null:
		push_warning("Missing removable panel area: %s" % area_name)
		return

	var part := _get_interactable_part(area)
	if part == null:
		push_warning("Missing removable panel part: %s" % area_name)
		return

	var ghost := _create_snap_ghost(part, "%sSnapGhost" % part_name)
	removable_parts[part_type] = {
		"name": part_name,
		"part": part,
		"parent": part.get_parent(),
		"closed_transform": part.transform,
		"ghost": ghost,
		"area": area,
		"installed": true,
		"requires_hood_open": false,
	}

	area.add_to_group("vehicle_removable_part")
	area.set_meta("part_type", part_type)
	area.set_meta("part_name", part_name)


func _create_snap_ghost(part: Node3D, ghost_name: String) -> Node3D:
	var ghost := Node3D.new()
	ghost.name = ghost_name
	add_child(ghost)
	ghost.global_transform = part.global_transform
	ghost.visible = false

	_clone_meshes_to_ghost(part, ghost)
	return ghost


func _clone_meshes_to_ghost(source: Node, target: Node3D) -> void:
	if source is MeshInstance3D:
		var source_mesh := source as MeshInstance3D
		var clone := MeshInstance3D.new()
		clone.name = "%sGhost" % source.name
		clone.mesh = source_mesh.mesh
		clone.material_overlay = snap_ghost_material
		target.add_child(clone)
		clone.global_transform = source_mesh.global_transform

	for child in source.get_children():
		if child is Node3D:
			_clone_meshes_to_ghost(child, target)


func _create_removable_part_area(part: Node3D, area_name: String, area_size: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = area_name
	area.collision_layer = 8
	area.collision_mask = 0
	area.add_to_group("vehicle_removable_part")
	add_child(area)
	area.global_position = part.global_position

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = area_size
	shape.shape = box
	area.add_child(shape)
	return area


func remove_installed_part(area: Area3D, ignore_access: bool = false) -> RigidBody3D:
	if area == null or not area.has_meta("part_type"):
		return null
	if NetworkManager.is_online() and not is_multiplayer_authority():
		return null
	var part_type := String(area.get_meta("part_type"))
	if not ignore_access and _requires_hood_open(part_type) and not _has_hood_access():
		return null
	var loose := _detach_part(part_type)
	if loose and NetworkManager.is_online():
		_sync_part_removed.rpc(part_type, loose.global_transform)
	return loose


@rpc("authority", "call_remote", "reliable")
func _sync_part_removed(slot: String, pose: Transform3D) -> void:
	var body := _detach_part(slot)
	if body:
		body.global_transform = pose


@rpc("authority", "call_remote", "reliable")
func _sync_part_installed(slot: String, loose_path: NodePath) -> void:
	var body := get_node_or_null(loose_path) as RigidBody3D
	if body and not body.is_queued_for_deletion() and body.has_meta("vehicle_part_type"):
		if install_part(body, slot):
			_play_install_feedback(slot)


func _detach_part(part_type: String) -> RigidBody3D:
	if not removable_parts.has(part_type):
		return null

	var data: Dictionary = removable_parts[part_type]
	if not bool(data.get("installed", false)):
		return null

	var part := data.get("part") as Node3D
	if part == null:
		return null

	var body := RigidBody3D.new()
	body.collision_layer = 16
	body.collision_mask = 17
	body.name = "%s_%sLoose" % [name, data.get("name", part_type)]
	body.mass = _loose_part_mass(part_type)
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.set_meta("vehicle_part_type", part_type)
	body.set_meta("source_vehicle", self)
	body.set_meta("trip_part_id", part.get_meta("trip_part_id", ""))
	if part_type == "engine":
		body.set_meta("engine_variant", current_engine_variant)
	if part_type == "trunk":
		body.set_meta("body_style", part.get_meta("body_style", body_style))
	body.add_to_group("vehicle_loose_part")
	_get_loose_part_parent().add_child(body, true)
	body.global_transform = part.global_transform.orthonormalized() if data.has("wheel") else part.global_transform
	part.reparent(body, true)
	if data.has("wheel"):
		part.scale = part.get_meta("native_wheel_scale")
		_detach_wheel_visual(data["wheel"])

	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _safe_collision_size(part)
	collision.shape = box
	body.add_child(collision)

	data["body"] = body
	_mark_part_slot_empty(part_type, data)
	return body


func _omit_starting_part(part_type: String) -> void:
	var data: Dictionary = removable_parts[part_type]
	var part: Node3D = data["part"]
	part.hide()
	part.queue_free()
	data["part"] = null
	if data.has("wheel"):
		_detach_wheel_visual(data["wheel"])
	_mark_part_slot_empty(part_type, data)


func _mark_part_slot_empty(part_type: String, data: Dictionary) -> void:
	data["installed"] = false
	(data["ghost"] as Node3D).visible = false
	var area := data["area"] as Area3D
	area.monitorable = false
	area.collision_layer = 0
	if part_type == "battery":
		_refresh_electric_capacity()


func can_install_part(body: RigidBody3D) -> bool:
	return install_blocker(body).is_empty()


func install_blocker(body: RigidBody3D) -> String:
	if not is_instance_valid(body) or body.is_queued_for_deletion() or not body.has_meta("vehicle_part_type"):
		return "Doesn’t fit this vehicle"
	var part_type := _get_install_target_part_type(body)
	if not removable_parts.has(part_type):
		if _is_wheel_part_type(str(body.get_meta("vehicle_part_type"))):
			return "Move closer to an empty wheel mount" if _get_installed_wheel_count() < wheel_array.size() else "Wheel slots occupied"
		return "Doesn’t fit this vehicle"
	if _get_loose_part_visual(body, part_type) == null:
		return "Doesn’t fit this vehicle"
	if part_type == "trunk" and body.get_meta("body_style", CarModel.SEDAN) != body_style:
		return "This rear lid fits a different body style"
	if _requires_hood_open(part_type) and not _has_hood_access():
		return "Open the hood"
	var data: Dictionary = removable_parts[part_type]
	if data["installed"]:
		return "Slot occupied"
	var snap_position := (data["ghost"] as Node3D).global_position
	if body.global_position.distance_to(snap_position) > part_snap_distance:
		return "Move closer to the mount"
	return ""


func install_part(body: RigidBody3D, restore_slot: String = "") -> bool:
	var restoring := not restore_slot.is_empty()
	if not restoring and not can_install_part(body):
		return false

	var part_type := restore_slot if restoring else _get_install_target_part_type(body)
	if not removable_parts.has(part_type):
		return false
	var data: Dictionary = removable_parts[part_type]
	var parent := data.get("parent") as Node
	var part := _get_loose_part_visual(body, part_type)
	if part == null or parent == null:
		return false
	if not restoring and NetworkManager.is_online():
		_sync_part_installed.rpc(part_type, body.get_path())

	if not part.has_meta("trip_part_id"):
		part.set_meta("trip_part_id", body.get_meta("trip_part_id", ""))
	var previous: Variant = data.get("part")
	if is_instance_valid(previous) and previous != part and previous.get_parent() == parent:
		parent.remove_child(previous)
		previous.queue_free()
	if wheel_model_root and part_type.begins_with("door_") and int(part.get_meta("body_style", -1)) != body_style:
		var color := (part.get_node("DoorSkin") as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		var door_name := _paint_target_name(str(data["area"].name))
		var replacement := CarModel.new(color.albedo_color).make_door(parent, door_name, body_style)
		replacement.set_meta("trip_part_id", part.get_meta("trip_part_id"))
		painted_materials.erase(replacement.get_node("DoorSkin").get_path())
		part = replacement
		_get_or_create_paint_material(replacement.get_node("DoorSkin")).albedo_color = color.albedo_color
	else:
		part.reparent(parent, true)
		if part_type.begins_with("door_"):
			var skin := part.get_node_or_null("DoorSkin") as MeshInstance3D
			if skin and skin.material_override is StandardMaterial3D:
				painted_materials[skin.get_path()] = skin.material_override
	part.transform = data["closed_transform"] as Transform3D
	body.queue_free()
	data["installed"] = true
	data["part"] = part
	data.erase("body")
	removable_parts[part_type] = data
	(data["ghost"] as Node3D).visible = false
	var area := data["area"] as Area3D
	area.monitorable = true
	area.collision_layer = 8
	area.set_meta("part_path", area.get_path_to(part))
	var visual := part
	if part_type in ["hood", "trunk"]:
		visual = part.get_child(0) as Node3D
	area.set_meta("visual_path", area.get_path_to(visual))
	if area.has_meta("follows_panel"):
		area.remove_meta("panel_center")
		_fit_panel_target(area, visual)
		part_closed_rotation[part.get_path()] = part.rotation
	if data.has("wheel"):
		var wheel: Wheel = data["wheel"]
		var native_radius: float = part.get_meta("native_wheel_radius")
		var native_scale: Vector3 = part.get_meta("native_wheel_scale")
		part.scale = native_scale * (wheel.tire_radius / native_radius)
		part.rotation_order = EULER_ORDER_ZXY
		_attach_wheel_visual(wheel, part)
	if part_type == "engine":
		_fit_installed_engine(part, String(body.get_meta("engine_variant", "Stock")))
		_apply_engine_variant(String(body.get_meta("engine_variant", "Stock")))
	if data.has("wheel") or part_type == "engine":
		var ghost := data["ghost"] as Node3D
		for child in ghost.get_children():
			ghost.remove_child(child)
			child.queue_free()
		ghost.global_transform = part.global_transform
		_clone_meshes_to_ghost(part, ghost)
	if part_type == "battery":
		_refresh_electric_capacity()
	if not restoring:
		_play_install_feedback(part_type)
	return true


func _play_install_feedback(slot: String) -> void:
	var part: Node3D = removable_parts[slot]["part"]
	var stream := ENGINE_MOUNT
	if _is_wheel_part_type(slot):
		stream = WHEEL_MOUNT
	elif slot.begins_with("door_") or slot in ["hood", "trunk"]:
		stream = DOOR_LATCH
	# Let the visual seat a few centimeters without moving the mount or hitbox.
	var visual: Node3D = part
	if not part is MeshInstance3D and part.get_child_count() > 0 and part.get_child(0) is Node3D:
		visual = part.get_child(0)
	var rest := visual.position
	visual.position += visual.get_parent_node_3d().global_basis.inverse() * Vector3.UP * 0.035
	var settle := visual.create_tween()
	settle.tween_property(visual, "position", rest, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_play_sfx_3d(stream, part.global_position, -8.0)


func _assign_trip_part_ids() -> void:
	var world := get_tree().current_scene
	if world == null or not world.is_ancestor_of(self):
		world = get_tree().root.get_node_or_null("Main")
	if world == null or not world.is_ancestor_of(self):
		return
	for slot in removable_parts:
		var part: Node3D = removable_parts[slot]["part"]
		part.set_meta("trip_part_id", "%s:%s" % [world.get_path_to(self), slot])


func _fit_installed_engine(part: Node3D, variant: String) -> void:
	if variant == "Bike":
		# The sedan's model root is scaled down. Keep the motorcycle engine at its original size.
		part.scale = Vector3.ONE / part.get_parent_node_3d().global_basis.get_scale().abs()


func _get_install_target_part_type(body: RigidBody3D) -> String:
	var held_part_type := String(body.get_meta("vehicle_part_type", ""))
	if not _is_wheel_part_type(held_part_type):
		return held_part_type

	return _get_nearest_empty_wheel_slot(body)


func get_wheel_snap_distance(body: RigidBody3D) -> float:
	if not can_install_part(body):
		return INF
	var slot := _get_nearest_empty_wheel_slot(body)
	if slot.is_empty():
		return INF
	var ghost: Node3D = removable_parts[slot]["ghost"]
	return body.global_position.distance_to(ghost.global_position)


func _get_nearest_empty_wheel_slot(body: RigidBody3D) -> String:
	var best_part_type := ""
	var best_distance := INF
	for part_type in removable_parts.keys():
		var candidate := String(part_type)
		if not _is_wheel_part_type(candidate):
			continue

		var data: Dictionary = removable_parts[candidate]
		if bool(data.get("installed", true)):
			continue

		var ghost := data.get("ghost") as Node3D
		if ghost == null:
			continue

		var distance := body.global_position.distance_to(ghost.global_position)
		if distance <= part_snap_distance and distance < best_distance:
			best_distance = distance
			best_part_type = candidate

	return best_part_type


func _is_wheel_part_type(part_type: String) -> bool:
	return part_type.begins_with("wheel_")


func _get_loose_part_visual(body: RigidBody3D, part_type: String) -> Node3D:
	var expected_name := _expected_loose_visual_name(part_type)
	if expected_name != "":
		return body.find_child(expected_name, true, false) as Node3D

	for child in body.get_children():
		if child is CollisionShape3D or child is Label3D:
			continue
		if _is_protected_visual(child):
			continue
		if child is Node3D:
			return child as Node3D

	return null


func _expected_loose_visual_name(part_type: String) -> String:
	match part_type:
		"engine":
			return "Engine"
		"battery":
			return "Battery"
		"radiator":
			return "Radiator"
		_:
			return ""


func _setup_protected_parts() -> void:
	for part_name in ["Interior", "Steerwheel", "Windows"]:
		var part := _find_part_node(part_name)
		if part == null or part.get_parent() == null:
			continue

		protected_parts[part_name] = {
			"part": part,
			"parent": part.get_parent(),
			"transform": part.transform,
		}


func _repair_protected_parts() -> void:
	for part_name in protected_parts.keys():
		var data: Dictionary = protected_parts[part_name]
		var part := data.get("part") as Node3D
		var parent := data.get("parent") as Node
		if part == null or parent == null or not is_instance_valid(part) or not is_instance_valid(parent):
			continue

		if part.get_parent() != parent:
			part.reparent(parent, true)
		part.transform = data["transform"] as Transform3D


func _is_protected_visual(node: Node) -> bool:
	var current := node
	while current:
		if protected_parts.has(current.name):
			return true
		current = current.get_parent()

	return false


func _detach_wheel_visual(wheel) -> void:
	if wheel == null:
		return

	wheel.installed = false
	wheel.enabled = false
	wheel.wheel_node = null


func _attach_wheel_visual(wheel, visual: Node3D) -> void:
	if wheel == null:
		return

	wheel.wheel_node = visual
	wheel.installed = true
	wheel.enabled = true


func paint_named_part(part_name: String, color: Color, amount: float) -> bool:
	var target_name := _paint_target_name(part_name)
	var part := _find_part_node(target_name)
	if part == null:
		return false

	_paint_meshes_recursive(part, color, amount, target_name)
	if target_name == "Chassis":
		_paint_gas_cap(color, amount)
		for title in ["Hood", "Trunk"]:
			var panel := _find_part_node(title)
			if panel:
				_paint_meshes_recursive(panel, color, amount, "Chassis")
	return true


func get_trip_panel_rotations() -> Dictionary:
	var rotations := {}
	for area_name in ["DoorFL", "DoorFR", "DoorRL", "DoorRR", "HoodTarget", "TrunkTarget", "GasCapTarget"]:
		var area := get_node_or_null(area_name) as Area3D
		if area and area.collision_layer != 0:
			var pivot := _get_interactable_part(area)
			if pivot:
				rotations[area_name] = pivot.rotation
	return rotations


func restore_trip_panel_rotations(rotations: Dictionary, legacy_car := false) -> void:
	for area_name in rotations:
		var area := get_node_or_null(area_name) as Area3D
		if area and area.collision_layer != 0:
			var pivot := _get_interactable_part(area)
			if pivot:
				var angle: Vector3 = rotations[area_name]
				if legacy_car and area_name in ["HoodTarget", "TrunkTarget", "GasCapTarget"]:
					angle = -angle
				pivot.rotation = angle
				_update_panel_target(area)


func get_trip_paint() -> Dictionary:
	var paint := {}
	for path in painted_materials:
		var mesh := get_node_or_null(path) as MeshInstance3D
		if mesh:
			paint[str(get_path_to(mesh))] = painted_materials[path].albedo_color
	return paint


func restore_trip_paint(paint: Dictionary, legacy_car := false) -> void:
	if legacy_car:
		var colors := {}
		for path: String in paint:
			var panel := "Chassis"
			for door: String in CarModel.DOORS:
				if path.contains("/" + door + "/"):
					panel = door
					break
			if not colors.has(panel):
				colors[panel] = paint[path]
		for panel: String in colors:
			paint_named_part(panel, colors[panel], 1.0)
		return
	for path in paint:
		var mesh := get_node_or_null(path) as MeshInstance3D
		if mesh:
			_get_or_create_paint_material(mesh).albedo_color = paint[path]


func _paint_target_name(part_name: String) -> String:
	match part_name:
		"DoorFL":
			return "FL_Door"
		"DoorFR":
			return "FR_Door"
		"DoorRL":
			return "RL_Door"
		"DoorRR":
			return "RR_Door"
		_:
			return part_name


func _paint_meshes_recursive(node: Node, color: Color, amount: float, target_name: String) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if _is_paintable_mesh(mesh_instance, target_name):
			var paint_material := _get_or_create_paint_material(mesh_instance)
			paint_material.albedo_color = paint_material.albedo_color.lerp(color, clampf(amount, 0.0, 1.0))

	for child in node.get_children():
		_paint_meshes_recursive(child, color, amount, target_name)


func _is_paintable_mesh(mesh_instance: MeshInstance3D, target_name: String) -> bool:
	if mesh_instance.has_meta("body_paint"):
		return bool(mesh_instance.get_meta("body_paint"))
	var mesh_name := mesh_instance.name.to_lower()
	if mesh_name.contains("window") or mesh_name.contains("glass"):
		return false

	if target_name == "Chassis":
		return mesh_name.contains("chassis") or mesh_name == "gascap"

	return mesh_name.contains("chassis") and mesh_name.contains(target_name.to_lower())


func _paint_gas_cap(color: Color, amount: float) -> void:
	var gas_cap := _find_part_node("gascap")
	if gas_cap == null:
		return

	_paint_meshes_recursive(gas_cap, color, amount, "Chassis")


func _apply_random_body_color() -> void:
	var rng := RandomNumberGenerator.new()
	if NetworkManager.is_online():
		rng.seed = hash(str(get_path()))
	else:
		rng.randomize()
	var color := Color.from_hsv(rng.randf(), rng.randf_range(0.55, 0.9), rng.randf_range(0.45, 0.95), 1.0)
	paint_named_part("Chassis", color, 1.0)
	for door_name in ["FL_Door", "FR_Door", "RL_Door", "RR_Door"]:
		paint_named_part(door_name, color, 1.0)


func _apply_sedan_trim() -> void:
	var tint: Color = [Color.WHITE, Color("#557375"), Color("#946745"), Color("#aba995")][sedan_trim]
	paint_named_part("Chassis", tint, 1.0)
	for door in ["FL_Door", "FR_Door", "RL_Door", "RR_Door"]:
		paint_named_part(door, tint, 1.0)
	var accessories := Node3D.new()
	accessories.name = "TrimAccessories"
	add_child(accessories)
	var rubber := PropShapes.material(Color("#242829"), 0.12)
	if sedan_trim == 3:
		for side in [-1.0, 1.0]:
			PropShapes.box(accessories, "SillGuard", Vector3(0.023, 0.048, 1.72),
				Vector3(side * 0.874, 0.257, 0.038), rubber)


func _apply_automotive_finish() -> void:
	for part_name in ["Chassis", "FL_Door", "FR_Door", "RL_Door", "RR_Door"]:
		var part := _find_part_node(part_name)
		if part:
			_apply_automotive_finish_recursive(part, part_name)


func _apply_automotive_finish_recursive(node: Node, target_name: String) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if _is_paintable_mesh(mesh_instance, target_name):
			var material := _get_or_create_paint_material(mesh_instance)
			material.metallic = 0.24
			material.roughness = 0.43
			material.metallic_specular = 0.38
			material.clearcoat_enabled = true
			material.clearcoat_roughness = 0.38

	for child in node.get_children():
		_apply_automotive_finish_recursive(child, target_name)


func _remove_starting_body_panels() -> void:
	await get_tree().physics_frame
	if not start_with_removed_panels:
		return
	var rng := RandomNumberGenerator.new()
	if NetworkManager.is_online():
		rng.seed = hash(name)
	else:
		rng.randomize()
	var available_parts: Array = removable_parts.keys()
	for index in range(available_parts.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var slot: String = available_parts[index]
		available_parts[index] = available_parts[other]
		available_parts[other] = slot
	var minimum := clampi(minimum_missing_starting_parts, 0, available_parts.size())
	var maximum := clampi(maximum_missing_starting_parts, minimum, available_parts.size())
	var missing_count := rng.randi_range(minimum, maximum)
	var spawn_points := _get_starting_part_spawn_points(missing_count, rng)

	for index in range(missing_count):
		var part_type := String(available_parts[index])
		var body := _detach_part(part_type)
		if body == null:
			continue

		var placed_transform := body.global_transform
		if index < spawn_points.size():
			placed_transform.origin = spawn_points[index]
		else:
			placed_transform.origin = global_position + Vector3(
				rng.randf_range(-5.0, 5.0),
				0.75,
				rng.randf_range(-5.0, 5.0)
			)
		placed_transform.basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * placed_transform.basis
		body.global_transform = placed_transform
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO


func _get_starting_part_spawn_points(count: int, rng: RandomNumberGenerator) -> Array[Vector3]:
	var shack := get_tree().get_first_node_in_group("starting_shack")
	if shack and NetworkManager.is_online():
		var points: Array[Vector3] = []
		var local_x: float = shack.to_local(global_position).x
		for i in count:
			points.append(shack.to_global(Vector3(local_x + (i % 2 - 0.5) * 1.8, 0.58, -4.8 - floori(i / 2.0) * 1.6)))
		return points
	if shack and shack.has_method("get_random_part_spawn_points"):
		return shack.get_random_part_spawn_points(count, rng)
	return []


func _remove_part_by_type(part_type: String, ignore_access: bool = false) -> RigidBody3D:
	if not removable_parts.has(part_type):
		return null

	var data: Dictionary = removable_parts[part_type]
	var area := data.get("area") as Area3D
	if area == null:
		return null

	return remove_installed_part(area, ignore_access)


func _get_loose_part_parent() -> Node:
	if get_tree().current_scene:
		return get_tree().current_scene
	if get_parent():
		return get_parent()

	return get_tree().root


func _setup_sound_effects() -> void:
	weld_sound = AudioStreamWAV.load_from_file(WELD_SOUND_PATH)


func _play_sfx_3d(stream: AudioStream, position: Vector3, gain := -2.0) -> void:
	if stream == null or not is_inside_tree() or get_tree().current_scene == null:
		return

	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = gain
	player.max_distance = 28.0
	get_tree().current_scene.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


func _capture_base_vehicle_stats() -> void:
	base_max_torque = max_torque
	base_max_rpm = max_rpm
	base_idle_fuel_burn_rate = idle_fuel_burn_rate
	base_throttle_fuel_burn_rate = throttle_fuel_burn_rate
	_apply_engine_variant(current_engine_variant)


func _apply_engine_variant(variant: String) -> void:
	current_engine_variant = variant
	match current_engine_variant:
		"Bike":
			fuel_type = "Petrol"
			max_torque = base_max_torque * 0.23
			max_rpm = base_max_rpm * 1.08
			idle_fuel_burn_rate = base_idle_fuel_burn_rate * 0.30
			throttle_fuel_burn_rate = base_throttle_fuel_burn_rate * 0.36
		"V8":
			fuel_type = "Diesel"
			max_torque = base_max_torque * 1.28
			max_rpm = base_max_rpm * 1.08
			idle_fuel_burn_rate = base_idle_fuel_burn_rate * 1.25
			throttle_fuel_burn_rate = base_throttle_fuel_burn_rate * 1.3
		"Electric":
			fuel_type = "Electric"
			max_torque = base_max_torque * 1.45
			max_rpm = base_max_rpm * 0.9
			idle_fuel_burn_rate = base_idle_fuel_burn_rate * 0.25
			throttle_fuel_burn_rate = base_throttle_fuel_burn_rate * 0.55
			_refresh_electric_capacity()
		_:
			current_engine_variant = "Stock"
			fuel_type = "Petrol"
			max_torque = base_max_torque
			max_rpm = base_max_rpm
			idle_fuel_burn_rate = base_idle_fuel_burn_rate
			throttle_fuel_burn_rate = base_throttle_fuel_burn_rate
	max_clutch_torque = (max_torque if current_engine_variant == "Bike" else base_max_torque) * max_clutch_torque_ratio


func _refresh_electric_capacity() -> void:
	wired_battery_count = 0
	for object in welded_objects.keys():
		if not is_instance_valid(object):
			continue
		var body := object as RigidBody3D
		if body and bool(body.get_meta("wired_battery", false)):
			wired_battery_count += 1

	var has_main_battery := false
	if removable_parts.has("battery"):
		var battery_data: Dictionary = removable_parts["battery"]
		has_main_battery = bool(battery_data.get("installed", false))

	var new_capacity := 0.0
	if has_main_battery:
		new_capacity += electric_battery_capacity_per_pack
	new_capacity += wired_battery_count * electric_battery_capacity_per_pack
	var previous_capacity := electric_capacity
	electric_capacity = new_capacity
	if electric_capacity <= 0.0:
		electric_charge = 0.0
	elif previous_capacity <= 0.0:
		electric_charge = electric_capacity
	else:
		electric_charge = clampf(electric_charge + maxf(electric_capacity - previous_capacity, 0.0), 0.0, electric_capacity)


func _has_drive_energy() -> bool:
	if current_engine_variant == "Electric":
		return electric_charge > 0.0

	return fuel_amount > 0.0


func _restore_legacy_workshop_parts(part_ids: Dictionary) -> void:
	var parts_parent := _get_loose_part_parent()
	for variant in ["V8", "Electric"]:
		if part_ids.has("%sEngineLoose" % variant):
			_spawn_engine_variant(parts_parent, variant)
	for id in ["ExtraBatteryLoose", "ExtraBatteryLoose2"]:
		if part_ids.has(id):
			_spawn_aux_battery(parts_parent, id, global_position)


func _spawn_engine_variant(parent: Node, variant: String) -> void:
	var source := _find_part_node("Engine")
	if source == null:
		return

	var body := _create_loose_clone_body(source, "%sEngineLoose" % variant, global_position, 12.0)
	body.set_meta("vehicle_part_type", "engine")
	body.set_meta("source_vehicle", self)
	body.set_meta("engine_variant", variant)
	body.add_to_group("vehicle_loose_part")
	parent.add_child(body, true)
	var visual := body.get_node("Engine") as MeshInstance3D
	visual.remove_meta("trip_part_id")
	body.set_meta("trip_part_id", str(parent.get_path_to(body)))
	_replace_part_mesh(visual, ENGINE_MODELS[variant])


func _spawn_aux_battery(parent: Node, id: String, at: Vector3) -> void:
	var source := _find_part_node("Battery")
	if source == null:
		return

	var body := _create_loose_clone_body(source, id, at, 5.0)
	body.set_meta("vehicle_part_type", "aux_battery")
	body.set_meta("source_vehicle", self)
	body.add_to_group("vehicle_loose_part")
	parent.add_child(body, true)
	body.set_meta("trip_part_id", str(parent.get_path_to(body)))


func _create_loose_clone_body(source: Node3D, body_name: String, position: Vector3, mass_value: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 16
	body.collision_mask = 17
	body.name = body_name
	body.mass = mass_value
	body.contact_monitor = true
	body.max_contacts_reported = 8
	var body_transform := source.global_transform
	body_transform.origin = position
	body.transform = body_transform

	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _safe_collision_size(source)
	collision.shape = box
	body.add_child(collision)

	var visual := source.duplicate()
	visual.name = source.name
	body.add_child(visual)
	visual.transform = Transform3D.IDENTITY
	return body


func _setup_battery_wire_guide() -> void:
	battery_wire_guide = Node3D.new()
	battery_wire_guide.name = "BatteryWireGuide"
	battery_wire_guide.visible = false
	add_child(battery_wire_guide)

	var line := MeshInstance3D.new()
	line.name = "GuideLine"
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.06, 1.2)
	line.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 1, 1, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line.material_override = material
	battery_wire_guide.add_child(line)


func can_wire_battery(body: RigidBody3D) -> bool:
	if body == null or String(body.get_meta("vehicle_part_type", "")) != "aux_battery":
		return false
	if bool(body.get_meta("wired_battery", false)):
		return false
	if body.get_meta("welded_vehicle", null) != self:
		return false
	if not _has_hood_access():
		return false

	return true


func wire_battery(body: RigidBody3D) -> bool:
	if not can_wire_battery(body):
		return false

	body.set_meta("wired_battery", true)
	_refresh_electric_capacity()
	return true


func _update_battery_wire_guide() -> void:
	if battery_wire_guide == null:
		return

	battery_wire_guide.visible = false
	if not _has_hood_access():
		return

	for object in welded_objects.keys():
		if not is_instance_valid(object):
			continue
		var body := object as RigidBody3D
		if body == null:
			continue
		if String(body.get_meta("vehicle_part_type", "")) != "aux_battery":
			continue
		if bool(body.get_meta("wired_battery", false)):
			continue

		battery_wire_guide.global_position = body.global_position + global_transform.basis.y * 0.55
		battery_wire_guide.visible = true
		return


func _get_battery_wire_position() -> Vector3:
	var battery := _find_part_node("Battery")
	if battery:
		return battery.global_position + global_transform.basis.y * 0.55

	return global_position + global_transform.basis.y * 1.0 + global_transform.basis.z * -1.2


func _get_or_create_paint_material(mesh_instance: MeshInstance3D) -> StandardMaterial3D:
	if painted_materials.has(mesh_instance.get_path()):
		return painted_materials[mesh_instance.get_path()] as StandardMaterial3D

	var material := StandardMaterial3D.new()
	var source := mesh_instance.material_override
	if source == null and mesh_instance.mesh and mesh_instance.mesh.get_surface_count() > 0:
		source = mesh_instance.get_active_material(0)

	if source is StandardMaterial3D:
		material = (source as StandardMaterial3D).duplicate() as StandardMaterial3D

	mesh_instance.material_override = material
	painted_materials[mesh_instance.get_path()] = material
	return material


func _update_snap_ghost_visibility() -> void:
	for part_type in removable_parts.keys():
		var data: Dictionary = removable_parts[part_type]
		var ghost := data.get("ghost") as Node3D
		if ghost == null:
			continue

		if bool(data.get("installed", true)):
			ghost.visible = false
			continue
		if _requires_hood_open(String(part_type)) and not _has_hood_access():
			ghost.visible = false
			continue

		var body := _find_install_body_for_part_type(String(part_type))
		if body == null or not is_instance_valid(body):
			ghost.visible = false
			continue

		ghost.visible = body.global_position.distance_to(ghost.global_position) <= part_snap_distance


func _find_install_body_for_part_type(part_type: String) -> RigidBody3D:
	var data: Dictionary = removable_parts[part_type]
	var ghost := data.get("ghost") as Node3D
	if ghost == null:
		return null

	var best_body: RigidBody3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("vehicle_loose_part"):
		var body := node as RigidBody3D
		if body == null:
			continue
		if _get_install_target_part_type(body) != part_type:
			continue
		if _get_loose_part_visual(body, part_type) == null:
			continue

		var distance := body.global_position.distance_to(ghost.global_position)
		if distance < best_distance:
			best_distance = distance
			best_body = body

	return best_body


func _requires_hood_open(part_type: String) -> bool:
	if not removable_parts.has(part_type):
		return false

	var data: Dictionary = removable_parts[part_type]
	return bool(data.get("requires_hood_open", false))


func _has_hood_access() -> bool:
	if removable_parts.has("hood"):
		var hood_data: Dictionary = removable_parts["hood"]
		if not bool(hood_data.get("installed", true)):
			return true

	return is_hood_open()


func _loose_part_mass(part_type: String) -> float:
	match part_type:
		"engine":
			return 12.0
		"hood", "trunk":
			return 7.0
		"door_fl", "door_fr", "door_rl", "door_rr":
			return 6.0
		"wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr":
			return 4.0
		_:
			return 5.0


func is_hood_open() -> bool:
	var area := get_node_or_null("HoodTarget") as Area3D
	if area == null:
		return false

	var part := _get_interactable_part(area)
	if part == null:
		return false

	var open_direction := float(area.get_meta("open_direction", 1.0))
	var closed_rotation := part_closed_rotation.get(part.get_path(), part.rotation) as Vector3
	return _get_interactable_open_amount(area, part, closed_rotation, open_direction) > 0.55


func _safe_collision_size(part: Node3D) -> Vector3:
	if part.has_meta("original_collision_size"):
		return part.get_meta("original_collision_size") as Vector3
	var bounds := _get_local_visual_bounds(part)
	var size := bounds.size.abs()
	return Vector3(maxf(size.x, 0.35), maxf(size.y, 0.25), maxf(size.z, 0.25))


func _has_required_drive_parts() -> bool:
	for part_type in ["engine", "radiator", "battery"]:
		if not removable_parts.has(part_type):
			return false

		var data: Dictionary = removable_parts[part_type]
		if not bool(data.get("installed", false)):
			return false

	return _get_installed_wheel_count() > 0


func _get_installed_wheel_count() -> int:
	var count := 0
	for part_type in removable_parts:
		if not _is_wheel_part_type(part_type):
			continue

		var data: Dictionary = removable_parts[part_type]
		if bool(data.get("installed", false)):
			count += 1

	return count


func _register_interactable(
	area_name: String,
	part_paths: Array[String],
	open_direction: float,
	open_axis: String,
	open_angle_degrees: float,
	hinge_edge: String = ""
) -> void:
	var area := get_node_or_null(area_name) as Area3D
	var part := _find_first_part_node(part_paths)

	if area == null or part == null:
		push_warning("Car interactable setup missing area or part: %s -> %s" % [area_name, ", ".join(part_paths)])
		return

	var visual_part := part
	if part.name in ["HoodTargetHinge", "TrunkTargetHinge", "GasCapTargetHinge"]:
		visual_part = part.get_child(0) as Node3D
	if hinge_edge != "":
		part = _create_hinge_pivot(area_name, part, hinge_edge)

	area.add_to_group("car_interactable")
	area.set_meta("part_path", area.get_path_to(part))
	area.set_meta("visual_path", area.get_path_to(visual_part))
	area.set_meta("open_direction", open_direction)
	area.set_meta("open_axis", open_axis)
	area.set_meta("open_angle_degrees", open_angle_degrees)
	if open_angle_degrees > 0.0:
		_fit_panel_target(area, visual_part)
	part_closed_rotation[part.get_path()] = part.rotation


func _fit_panel_target(area: Area3D, visual: Node3D) -> void:
	var bounds := _get_local_visual_bounds(visual)
	var shape := area.get_child(0) as CollisionShape3D
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3.ONE * 0.03)
	shape.shape = box
	area.set_meta("follows_panel", true)
	_update_panel_target(area, visual)


func _update_panel_target(area: Area3D, visual: Node3D = null) -> void:
	if not area.has_meta("follows_panel") or area.collision_layer == 0:
		return
	if visual == null:
		visual = _get_interactable_visual(area)
	if visual == null:
		return
	if not area.has_meta("panel_center"):
		area.set_meta("panel_center", _get_local_visual_bounds(visual).get_center())
	var shape := area.get_child(0) as CollisionShape3D
	var center: Vector3 = area.get_meta("panel_center")
	shape.global_transform = visual.global_transform * Transform3D(Basis.IDENTITY, center)


func can_target_part(area: Area3D) -> bool:
	if area.name == "FuelFillerTarget":
		return is_gas_cap_open()
	var slot := String(area.get_meta("part_type", ""))
	return not _requires_hood_open(slot) or _has_hood_access()


func _find_first_part_node(part_paths: Array[String]) -> Node3D:
	for part_path in part_paths:
		var part := _find_part_node(part_path)
		if part:
			return part

	return null


func _find_part_node(part_path: String) -> Node3D:
	var by_path := get_node_or_null(part_path) as Node3D
	if by_path:
		return by_path

	return find_child(part_path, true, false) as Node3D


func _create_hinge_pivot(area_name: String, part: Node3D, hinge_edge: String) -> Node3D:
	if part.get_parent() == null:
		return part

	var parent := part.get_parent() as Node3D
	var hinge_local := _get_hinge_local_point(part, hinge_edge)
	var hinge_parent_position := part.transform * hinge_local
	var part_global_transform := part.global_transform
	var pivot := Node3D.new()

	pivot.name = "%sHinge" % area_name
	pivot.transform = part.transform
	pivot.position = hinge_parent_position

	parent.add_child(pivot)
	part.get_parent().remove_child(part)
	pivot.add_child(part)
	part.global_transform = part_global_transform

	return pivot


func _get_hinge_local_point(part: Node3D, hinge_edge: String) -> Vector3:
	var bounds := _get_local_visual_bounds(part)
	var hinge := bounds.get_center()

	match hinge_edge:
		"min_x":
			hinge.x = bounds.position.x
		"max_x":
			hinge.x = bounds.position.x + bounds.size.x
		"min_y":
			hinge.y = bounds.position.y
		"max_y":
			hinge.y = bounds.position.y + bounds.size.y
		"min_z":
			hinge.z = bounds.position.z
		"max_z":
			hinge.z = bounds.position.z + bounds.size.z

	return hinge


func _get_local_visual_bounds(part: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := part is MeshInstance3D and (part as MeshInstance3D).mesh != null
	if has_bounds:
		bounds = (part as MeshInstance3D).mesh.get_aabb()
	for child in part.get_children():
		if not child is Node3D:
			continue

		var child_bounds := _get_local_visual_bounds(child as Node3D)
		var transformed_bounds := (child as Node3D).transform * child_bounds
		if has_bounds:
			bounds = bounds.merge(transformed_bounds)
		else:
			bounds = transformed_bounds
			has_bounds = true

	return bounds if has_bounds else AABB()


func _has_driving_camera() -> bool:
	var camera := get_viewport().get_camera_3d()
	return camera != null and camera.is_in_group("driving_camera")


func _handle_interactable_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var target := _find_pointed_interactable()
			if target and target.is_in_group("car_interactable") and float(target.get_meta("open_angle_degrees", 0.0)) > 0:
				dragged_interactable = target
		elif not event.pressed:
			dragged_interactable = null
			_set_hovered_interactable(_find_pointed_interactable())

	if event is InputEventMouseMotion and dragged_interactable:
		_drag_interactable(dragged_interactable, -event.relative.y)


func _find_pointed_interactable() -> Area3D:
	var view := get_viewport().get_camera_3d()
	if view == null:
		return null
	var player := get_tree().get_first_node_in_group("local_player")
	if player and player.gameplay_ui_open():
		return null
	var holding_can: bool = player and is_instance_valid(player.held_object) and player.held_object.is_in_group("fuel_canister")
	if player and is_instance_valid(player.held_object) and not holding_can:
		return null
	var exclusions: Array = player._raycast_exclusions() if player else []
	var hit := CrosshairTarget.cast(view, interact_distance, exclusions)
	var area := hit.get("collider") as Area3D
	if area and area.get_parent() == self and can_target_part(area):
		if not holding_can or area.name == "GasCapTarget":
			return area
	return null


func _set_hovered_interactable(area: Area3D) -> void:
	if hovered_interactable == area:
		return

	if hovered_interactable:
		_set_interactable_highlight(hovered_interactable, false)

	hovered_interactable = area

	if hovered_interactable:
		_set_interactable_highlight(hovered_interactable, true)


func _set_interactable_highlight(area: Area3D, enabled: bool) -> void:
	var part := _get_interactable_visual(area)
	if part == null:
		return

	_set_mesh_overlay_recursive(part, highlight_material if enabled else null)


func _set_mesh_overlay_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = material

	for child in node.get_children():
		_set_mesh_overlay_recursive(child, material)


func _get_interactable_part(area: Area3D) -> Node3D:
	if not area.has_meta("part_path"):
		return null

	return area.get_node_or_null(area.get_meta("part_path")) as Node3D


func _get_interactable_visual(area: Area3D) -> Node3D:
	if not area.has_meta("visual_path"):
		return _get_interactable_part(area)

	return area.get_node_or_null(area.get_meta("visual_path")) as Node3D


func _drag_interactable(area: Area3D, drag_amount: float) -> void:
	var part := _get_interactable_part(area)
	if part == null:
		return

	var open_direction := float(area.get_meta("open_direction", 1.0))
	var open_axis := String(area.get_meta("open_axis", "y"))
	var open_angle := deg_to_rad(float(area.get_meta("open_angle_degrees", 72.0)))
	var closed_rotation := part_closed_rotation.get(part.get_path(), part.rotation) as Vector3
	var current_open := _get_interactable_open_amount(area, part, closed_rotation, open_direction)
	var target_open: float = clamp(current_open + drag_amount * 0.006, 0.0, 1.0)

	if NetworkManager.is_online() and not multiplayer.is_server():
		request_work("panel", area.name, drag_amount)
		return
	part.rotation = closed_rotation
	_apply_panel_rotation(part, open_axis, open_direction * open_angle * target_open)
	_update_panel_target(area)
	if current_open > 0.08 and target_open < 0.01:
		_play_sfx_3d(DOOR_LATCH, part.global_position, -13.0)
	if NetworkManager.is_online():
		_sync_panels.rpc({str(area.name): part.rotation})


func _get_interactable_open_amount(area: Area3D, part: Node3D, closed_rotation: Vector3, open_direction: float) -> float:
	var open_axis := String(area.get_meta("open_axis", "y"))
	var open_angle := deg_to_rad(float(area.get_meta("open_angle_degrees", 72.0)))
	var delta := _get_axis_rotation(part.rotation, open_axis) - _get_axis_rotation(closed_rotation, open_axis)

	return clamp(delta / (open_direction * open_angle), 0.0, 1.0)


func _latch_entry_door(from: Vector3) -> void:
	var side := to_local(from)
	var area_name := "DoorFL" if side.x < 0.0 else "DoorFR"
	if NetworkManager.is_online() and side.z > 0.45:
		area_name = "DoorRL" if side.x < 0.0 else "DoorRR"
	var area := get_node_or_null(area_name) as Area3D
	if area == null or area.collision_layer == 0:
		return
	var part := _get_interactable_part(area)
	if part:
		part.rotation = part_closed_rotation.get(part.get_path(), part.rotation)
		_update_panel_target(area)
		if NetworkManager.is_online() and is_multiplayer_authority():
			_sync_panels.rpc({area_name: part.rotation})


func _close_all_panels() -> void:
	for area_name in ["DoorFL", "DoorFR", "DoorRL", "DoorRR", "HoodTarget", "TrunkTarget", "GasCapTarget"]:
		var area := get_node_or_null(area_name) as Area3D
		if area == null:
			continue

		var part := _get_interactable_part(area)
		if part == null:
			continue

		part.rotation = part_closed_rotation.get(part.get_path(), part.rotation) as Vector3
		_update_panel_target(area)


func _get_axis_rotation(rotation: Vector3, axis: String) -> float:
	match axis:
		"x":
			return rotation.x
		"z":
			return rotation.z
		_:
			return rotation.y


func _apply_panel_rotation(part: Node3D, axis: String, angle: float) -> void:
	match axis:
		"x":
			part.rotate_x(angle)
		"z":
			part.rotate_z(angle)
		_:
			part.rotate_y(angle)


func _attach_model_wheels() -> void:
	if wheel_model_root == null:
		return

	_reparent_model_part(["FL_Wheel", "FL"], front_left_wheel.wheel_node)
	_reparent_model_part(["FR_Wheel", "FR"], front_right_wheel.wheel_node)
	_reparent_model_part(["RL_Wheel", "RL"], rear_left_wheel.wheel_node)
	_reparent_model_part(["RR_Wheel", "RR"], rear_right_wheel.wheel_node)


func _reparent_model_part(part_names: Array[String], target: Node3D) -> void:
	if target == null:
		return

	var part: Node3D = null
	for part_name in part_names:
		part = wheel_model_root.find_child(part_name, true, false) as Node3D
		if part:
			break

	if part == null:
		push_warning("Could not find wheel model part: %s" % ", ".join(part_names))
		return

	var part_transform := part.global_transform
	part.get_parent().remove_child(part)
	target.add_child(part)
	part.global_transform = part_transform
	part.position = Vector3.ZERO


func _action_or_keys(action_name: StringName, keys: Array[int]) -> float:
	var strength := 0.0

	if InputMap.has_action(action_name):
		strength = Input.get_action_strength(action_name)

	for key in keys:
		if Input.is_key_pressed(key):
			return 1.0

	return strength


func _update_camera_rotation() -> void:
	if camera_rig == null:
		return

	if first_person_camera_enabled:
		camera_rig.rotation = Vector3(camera_pitch, camera_yaw, 0)
		return
	var forward := -global_basis.z.slide(Vector3.UP)
	var heading := atan2(-forward.x, -forward.z) if forward.length_squared() > 0.001 else 0.0
	camera_rig.global_basis = Basis(Vector3.UP, heading + camera_yaw) * Basis(Vector3.RIGHT, -camera_pitch)


func _update_third_person_camera_collision() -> void:
	if driver_camera == null or camera_rig == null or first_person_camera_enabled or not driver_camera.current:
		return

	driver_camera.transform = third_person_camera_transform
	var ray_from := camera_rig.global_position
	var desired_position := driver_camera.global_position
	var query := PhysicsRayQueryParameters3D.create(ray_from, desired_position)
	query.collision_mask = 1 | 2
	query.exclude = [get_rid()]
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var hit_position := hit.position as Vector3
	var hit_normal := hit.normal as Vector3
	driver_camera.global_position = hit_position + hit_normal * 0.28
