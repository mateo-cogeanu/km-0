extends CharacterBody3D

const CrosshairTarget := preload("res://scripts/crosshair_target.gd")
const Style := preload("res://scripts/menu_style.gd")
const CabinWind := preload("res://scripts/cabin_wind.gd")

@export var player_name: String = "Player"

@export var move_speed: float = 6.0
@export var sprint_speed: float = 10.0
@export var crouch_speed: float = 3.0
@export var jump_velocity: float = 5.5
@export var ground_acceleration: float = 35.0
@export var ground_friction: float = 45.0
@export var air_acceleration: float = 2.0
@export var mouse_sensitivity: float = 0.0025
@export var max_look_angle: float = 85.0
@export var grab_distance: float = 3.0
@export var grab_follow_strength: float = 32.0
@export var grab_smoothing: float = 18.0
@export var grab_max_speed: float = 12.0
@export var held_gravity_scale: float = 0.25
@export var vehicle_interact_distance: float = 5.0
@export var standing_height: float = 2.05
@export var crouching_height: float = 1.2
@export var standing_head_height: float = 0.9
@export var crouching_head_height: float = 0.3
@export var crouch_transition_speed: float = 12.0
@export var refuel_distance: float = 1.25
@export var refuel_rate: float = 8.0
@export var spray_distance: float = 5.0
@export var spray_strength: float = 1.8

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var look_rotation_x: float = 0.0
var held_object: RigidBody3D
var held_local_grab_point: Vector3
var held_original_gravity_scale: float = 1.0
var held_original_linear_damp: float = 0.0
var held_original_angular_damp: float = 0.0
var held_original_contact_monitor: bool = false
var held_original_max_contacts_reported: int = 0
var active_vehicle: Node3D
var shared_seat := -1
var name_tags: Dictionary = {}
var interaction_tip: PanelContainer
var interaction_label: Label
var radio_caption: PanelContainer
var radio_caption_label: Label
var listening_radio: Area3D
var ending_locked := false
## While locked for the ending, the mouse may still turn the head.
var ending_look := false
var ending_return_position := Vector3.ZERO
var push_send_elapsed := 0.0
var refuel_network_amount := 0.0
var spray_network_amount := 0.0
var hovered_grab_object: Node3D
var highlight_material: StandardMaterial3D
var refuel_car: Node3D
var refuel_canister: RigidBody3D
var refuel_start_fuel: float = 0.0
var refuel_target_fuel: float = 0.0
var spray_colors: Array[Color] = [
	Color(0.9, 0.08, 0.05, 1.0),
	Color(0.08, 0.23, 0.95, 1.0),
	Color(0.04, 0.72, 0.18, 1.0),
	Color(0.95, 0.88, 0.08, 1.0),
	Color(0.08, 0.08, 0.08, 1.0),
	Color(0.95, 0.95, 0.95, 1.0),
]
var spray_color_index: int = 0
var fps_label: Label
var last_safe_position: Vector3
var remote_position: Vector3
var remote_rotation_y: float
var _network_send_elapsed := 0.0
var _held_network_send_elapsed := 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var hold_point: Marker3D = $Head/Camera3D/HoldPoint
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var driving_hud: Control = $HUD/DrivingHUD
@onready var refuel_panel: Control = $HUD/RefuelPanel
@onready var refuel_fill: ColorRect = $HUD/RefuelPanel/CarBarBackground/CarBarFill
@onready var canister_fill: ColorRect = $HUD/RefuelPanel/CanisterBarBackground/CanisterBarFill
@onready var refuel_label: Label = $HUD/RefuelPanel/RefuelLabel


func _ready() -> void:
	add_to_group("road_stream_player")
	var locally_controlled := is_multiplayer_authority()
	if locally_controlled:
		camera.make_current()
	$HUD.visible = locally_controlled
	$Model.visible = not locally_controlled or not NetworkManager.is_online()
	if not locally_controlled:
		remote_position = global_position
		remote_rotation_y = rotation.y
		return
	add_to_group("local_player")
	GameSettings.player_name_changed.connect(_update_player_name)
	_create_interaction_tip()
	var wind := CabinWind.new()
	wind.name = "CabinWind"
	add_child(wind)
	last_safe_position = global_position
	_setup_highlight_material()
	_setup_fps_label()
	if GameSettings and not GameSettings.settings_changed.is_connected(_apply_ui_scale):
		GameSettings.settings_changed.connect(_apply_ui_scale)
	get_viewport().size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()
	_update_fuel_hud()
	_update_refuel_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if gameplay_ui_open() else Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not NetworkManager.is_online() or not is_multiplayer_authority():
		return
	var view := get_viewport().get_camera_3d()
	if view == null:
		return
	var bounds := get_viewport().get_visible_rect().size
	var seen := {}
	for other in get_tree().get_nodes_in_group("road_stream_player"):
		if other == self or not other.visible or other.global_position.distance_squared_to(view.global_position) > 65.0 * 65.0:
			continue
		var head_at: Vector3 = other.global_position + Vector3.UP * 0.9
		if view.is_position_behind(head_at):
			continue
		var head_screen := view.unproject_position(head_at)
		if not Rect2(Vector2.ZERO, bounds).has_point(head_screen):
			continue
		var sight := PhysicsRayQueryParameters3D.create(view.global_position, head_at, 1 | 2)
		if is_instance_valid(active_vehicle):
			sight.exclude = [active_vehicle.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
			continue
		seen[other] = true
		var label: Label = name_tags.get(other)
		if label == null:
			label = Label.new()
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_constant_override("outline_size", 5)
			label.add_theme_color_override("font_outline_color", Color(0.07, 0.06, 0.05, 0.94))
			$HUD.add_child(label)
			name_tags[other] = label
		label.text = other.player_name
		label.add_theme_font_size_override("font_size", roundi(14 * GameSettings.ui_scale))
		label.size = label.get_minimum_size()
		var above := view.unproject_position(head_at + Vector3.UP * 0.43)
		label.position = Vector2(above.x - label.size.x * 0.5, above.y - label.size.y).clamp(
			Vector2(4, 4), (bounds - label.size - Vector2(4, 4)).max(Vector2(4, 4)))
	for other in name_tags.keys():
		if not seen.has(other):
			name_tags[other].queue_free()
			name_tags.erase(other)


func _update_player_name(value: String) -> void:
	player_name = value
	if NetworkManager.is_online():
		_sync_player_name.rpc(value)


@rpc("authority", "call_remote", "reliable")
func _sync_player_name(value: String) -> void:
	player_name = value.strip_edges().substr(0, 24)


func _unhandled_input(event: InputEvent) -> void:
	if ending_locked and ending_look and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_turn_head(event.relative)
		return
	if ending_locked or not is_multiplayer_authority() or gameplay_ui_open():
		return
	if is_instance_valid(active_vehicle):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_L, KEY_H]:
			_toggle_vehicle_lights(active_vehicle)
			get_viewport().set_input_as_handled()
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
			if NetworkManager.is_online():
				active_vehicle.request_leave()
			else:
				_exit_vehicle()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_turn_head(event.relative)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_handle_interaction()

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if _try_wire_pointed_battery():
			return
		_cycle_spray_color()

	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_L or event.keycode == KEY_H):
		if _try_toggle_vehicle_headlights():
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if ending_locked:
		return
	if not is_multiplayer_authority():
		if is_instance_valid(active_vehicle):
			global_position = active_vehicle.global_position
			return
		global_position = global_position.lerp(remote_position, minf(delta * 14.0, 1.0))
		rotation.y = lerp_angle(rotation.y, remote_rotation_y, minf(delta * 14.0, 1.0))
		return
	if active_vehicle:
		_set_hovered_grab_object(null)
		global_position = active_vehicle.global_position
		_update_fuel_hud()
		_stop_refuel()
		_update_interaction_tip()
		_send_network_transform(delta)
		return

	var controls_active := not gameplay_ui_open()
	var input_direction := _get_input_direction() if controls_active else Vector3.ZERO
	var world_direction := (global_transform.basis * input_direction).normalized()
	var is_crouching := controls_active and Input.is_key_pressed(KEY_C)
	var is_sprinting := Input.is_key_pressed(KEY_SHIFT) and not is_crouching
	var target_speed := crouch_speed if is_crouching else (sprint_speed if is_sprinting else move_speed)

	_update_crouch(is_crouching, delta)

	if is_on_floor():
		_apply_ground_movement(world_direction, target_speed, delta)
	else:
		_apply_air_movement(world_direction, target_speed, delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif controls_active and Input.is_key_pressed(KEY_SPACE) and not is_crouching:
		velocity.y = jump_velocity

	var walking_velocity := velocity.slide(Vector3.UP)
	move_and_slide()
	_push_colliding_bodies(walking_velocity, delta)
	if is_on_floor() and global_position.y > -2.0:
		last_safe_position = global_position
	elif global_position.y < -12.0:
		global_position = last_safe_position + Vector3.UP
		velocity = Vector3.ZERO
	if controls_active:
		_update_held_object(delta)
		_update_spray_paint(delta)
		_update_refuel(delta)
	_update_grab_hover()
	_update_interaction_tip()
	_update_fuel_hud()
	_update_refuel_hud()
	_update_fps_label()
	_send_network_transform(delta)


func lock_for_ending(return_position: Vector3) -> void:
	ending_locked = true
	ending_return_position = return_position
	velocity = Vector3.ZERO
	if is_instance_valid(listening_radio):
		listening_radio.stop_listening()
	if is_instance_valid(held_object):
		_drop_held_object()
	$HUD.hide()


func _turn_head(relative: Vector2) -> void:
	var scaled_sensitivity := mouse_sensitivity * GameSettings.mouse_sensitivity_scale
	rotate_y(-relative.x * scaled_sensitivity)
	look_rotation_x = clamp(
		look_rotation_x - relative.y * scaled_sensitivity,
		deg_to_rad(-max_look_angle),
		deg_to_rad(max_look_angle)
	)
	head.rotation.x = look_rotation_x


func begin_ending_look() -> void:
	## Hand the camera back to the mouse from wherever the ending left it.
	var forward := -camera.global_basis.z
	global_rotation.y = atan2(-forward.x, -forward.z)
	look_rotation_x = clampf(asin(clampf(forward.y, -1.0, 1.0)), deg_to_rad(-max_look_angle), deg_to_rad(max_look_angle))
	head.rotation.x = look_rotation_x
	camera.basis = Basis()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ending_look = true


func end_ending_look() -> void:
	ending_look = false


func aim_ending_camera(at: Vector3, amount: float) -> void:
	var target := camera.global_transform.looking_at(at)
	camera.global_basis = camera.global_basis.slerp(target.basis, clampf(amount, 0.0, 1.0))


func _send_network_transform(delta: float) -> void:
	if NetworkManager.is_online():
		_network_send_elapsed += delta
		if _network_send_elapsed >= 0.05:
			_network_send_elapsed = 0.0
			sync_transform.rpc(global_position, rotation.y)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func sync_transform(new_position: Vector3, new_rotation_y: float) -> void:
	remote_position = new_position
	remote_rotation_y = new_rotation_y


func _get_input_direction() -> Vector3:
	var direction := Vector3.ZERO

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0

	return direction.normalized()


func _apply_ground_movement(direction: Vector3, target_speed: float, delta: float) -> void:
	if direction.length_squared() < 0.001:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_friction * delta)
		return

	var target_velocity := direction * target_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, ground_acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, ground_acceleration * delta)


func _apply_air_movement(direction: Vector3, target_speed: float, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var speed_in_input_direction := horizontal_velocity.dot(direction)
	var speed_to_add := target_speed - speed_in_input_direction

	if speed_to_add <= 0.0:
		return

	var acceleration_speed = min(air_acceleration * target_speed * delta, speed_to_add)
	horizontal_velocity += direction * acceleration_speed
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z


func _update_crouch(is_crouching: bool, delta: float) -> void:
	var target_height := crouching_height if is_crouching else standing_height
	var target_head_height := crouching_head_height if is_crouching else standing_head_height
	var shape := collision_shape.shape as CapsuleShape3D

	shape.height = move_toward(shape.height, target_height, crouch_transition_speed * delta)
	collision_shape.position.y = (shape.height - standing_height) * 0.5
	head.position.y = move_toward(head.position.y, target_head_height, crouch_transition_speed * delta)


func _toggle_grab() -> void:
	if held_object:
		_drop_held_object()
		return

	var result := _raycast_grab_target()

	if result.is_empty() or not result.collider is RigidBody3D:
		return

	var target := result.collider as RigidBody3D
	if not _can_grab_body(target):
		return

	_begin_grab_object(target, result.position)


func _begin_grab_object(object: RigidBody3D, grab_position: Vector3) -> void:
	if held_object != null:
		return
	if not _can_grab_body(object):
		return

	held_object = object
	held_local_grab_point = held_object.to_local(grab_position)
	held_original_gravity_scale = held_object.gravity_scale
	held_original_linear_damp = held_object.linear_damp
	held_original_angular_damp = held_object.angular_damp
	held_original_contact_monitor = held_object.contact_monitor
	held_original_max_contacts_reported = held_object.max_contacts_reported
	held_object.gravity_scale = held_gravity_scale
	held_object.linear_damp = 4.0
	held_object.angular_damp = 6.0
	held_object.contact_monitor = true
	held_object.max_contacts_reported = max(held_object.max_contacts_reported, 8)
	if _is_spray_can(held_object):
		_apply_spray_can_color(held_object, spray_colors[spray_color_index])
	if NetworkManager.is_online():
		sync_held_object_state.rpc(held_object.get_path(), true)


func _drop_held_object() -> void:
	_stop_refuel()
	if NetworkManager.is_online() and held_object != null:
		sync_held_object_transform.rpc(held_object.get_path(), held_object.global_transform, held_object.linear_velocity, held_object.angular_velocity)
		sync_held_object_state.rpc(held_object.get_path(), false)
	_restore_held_object_physics()
	held_object = null
	_held_network_send_elapsed = 0.0


func _restore_held_object_physics() -> void:
	if held_object == null:
		return

	held_object.gravity_scale = held_original_gravity_scale
	held_object.linear_damp = held_original_linear_damp
	held_object.angular_damp = held_original_angular_damp
	held_object.contact_monitor = held_original_contact_monitor
	held_object.max_contacts_reported = held_original_max_contacts_reported


func _update_held_object(delta: float) -> void:
	if held_object == null:
		return

	var grabbed_point := held_object.to_global(held_local_grab_point)
	var to_target := hold_point.global_position - grabbed_point
	var wanted_velocity := to_target * grab_follow_strength

	if wanted_velocity.length() > grab_max_speed:
		wanted_velocity = wanted_velocity.normalized() * grab_max_speed

	var blend: float = min(grab_smoothing * delta, 1.0)
	held_object.linear_velocity = held_object.linear_velocity.lerp(wanted_velocity, blend)
	held_object.angular_velocity = held_object.angular_velocity.move_toward(Vector3.ZERO, grab_smoothing * delta)
	if NetworkManager.is_online():
		_held_network_send_elapsed += delta
		if _held_network_send_elapsed >= 0.04:
			_held_network_send_elapsed = 0.0
			sync_held_object_transform.rpc(
				held_object.get_path(),
				held_object.global_transform,
				held_object.linear_velocity,
				held_object.angular_velocity
			)


@rpc("authority", "call_remote", "reliable")
func sync_held_object_state(object_path: NodePath, is_held: bool) -> void:
	var object := get_node_or_null(object_path) as RigidBody3D
	if object == null:
		return

	if is_held:
		object.freeze = true
		object.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		object.linear_velocity = Vector3.ZERO
		object.angular_velocity = Vector3.ZERO
	else:
		object.freeze = false


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func sync_held_object_transform(
	object_path: NodePath,
	new_transform: Transform3D,
	new_linear_velocity: Vector3,
	new_angular_velocity: Vector3
) -> void:
	var object := get_node_or_null(object_path) as RigidBody3D
	if object == null:
		return

	object.global_transform = new_transform
	object.linear_velocity = new_linear_velocity
	object.angular_velocity = new_angular_velocity


func _cycle_spray_color() -> void:
	if not _is_spray_can(held_object):
		return

	spray_color_index = (spray_color_index + 1) % spray_colors.size()
	_apply_spray_can_color(held_object, spray_colors[spray_color_index])


func _update_spray_paint(delta: float) -> void:
	if gameplay_ui_open() or not _is_spray_can(held_object):
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return

	var color := spray_colors[spray_color_index]
	var amount := spray_strength * delta
	if NetworkManager.is_online():
		spray_network_amount += amount
		if spray_network_amount < 0.075:
			return
		amount = spray_network_amount
		spray_network_amount = 0.0
	if _spray_paint_area(color, amount):
		return

	_spray_paint_body(color, amount)


func _spray_paint_area(color: Color, amount: float) -> bool:
	var result := _raycast_area_target(spray_distance)
	if result.is_empty() or not result.collider is Area3D:
		return false

	var area := result.collider as Area3D
	if not area.is_in_group("car_interactable"):
		return false

	var part_name := _paint_part_from_area(area)
	if part_name == "":
		return false

	var car := area.get_parent() as Node3D
	if car == null or not car.has_method("paint_named_part"):
		return false

	return _paint_vehicle(car, part_name, color, amount)


func _spray_paint_body(color: Color, amount: float) -> bool:
	var result := _raycast_body_target(spray_distance)
	if result.is_empty() or not result.collider is Node3D:
		return false

	var car := result.collider as Node3D
	car = _vehicle_from_target(car)
	if car == null:
		return false

	return _paint_vehicle(car, "Chassis", color, amount)


func _paint_vehicle(car: Node3D, part_name: String, color: Color, amount: float) -> bool:
	if NetworkManager.is_online():
		car.request_work("paint", part_name, Vector2(spray_color_index, amount))
		return true
	return car.paint_named_part(part_name, color, amount)


func _paint_part_from_area(area: Area3D) -> String:
	match area.name:
		"DoorFL":
			return "FL_Door"
		"DoorFR":
			return "FR_Door"
		"DoorRL":
			return "RL_Door"
		"DoorRR":
			return "RR_Door"
		_:
			return ""


func _is_spray_can(object: Node) -> bool:
	return object != null and object.is_in_group("spray_can")


func _apply_spray_can_color(object: Node, color: Color) -> void:
	if object == null:
		return
	if object.has_method("set_spray_color"):
		object.call("set_spray_color", color)
		return

	var color_part := object.find_child("change_color", true, false)
	if color_part:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		_set_mesh_override_recursive(color_part, material)


func _setup_highlight_material() -> void:
	highlight_material = StandardMaterial3D.new()
	highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight_material.albedo_color = Color(1, 1, 1, 0.35)
	highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_material.no_depth_test = true


func _setup_fps_label() -> void:
	fps_label = Label.new()
	fps_label.name = "FpsLabel"
	fps_label.visible = false
	fps_label.position = Vector2(22, 18)
	fps_label.pivot_offset = -fps_label.position
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	$HUD.add_child(fps_label)


func _apply_ui_scale() -> void:
	if radio_caption:
		_layout_radio_caption()
	var hud_scale := Vector2.ONE * GameSettings.ui_scale
	$HUD/Crosshair.scale = hud_scale
	driving_hud.scale = Vector2.ONE * minf(GameSettings.ui_scale, get_viewport().get_visible_rect().size.x / 242.0)
	refuel_panel.scale = hud_scale
	fps_label.scale = hud_scale


func _update_fps_label() -> void:
	if fps_label == null:
		return

	fps_label.visible = GameSettings.show_fps
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _set_mesh_override_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material

	for child in node.get_children():
		_set_mesh_override_recursive(child, material)


func _update_grab_hover() -> void:
	if held_object or is_instance_valid(active_vehicle) or gameplay_ui_open():
		_set_hovered_grab_object(null)
		return

	var result := _raycast_grab_target()

	if result.is_empty() or not result.collider is RigidBody3D:
		_set_hovered_grab_object(null)
		return

	var target := result.collider as RigidBody3D
	if not _can_grab_body(target):
		_set_hovered_grab_object(null)
		return

	_set_hovered_grab_object(target)


func _set_hovered_grab_object(object: Node3D) -> void:
	if hovered_grab_object == object:
		return

	if hovered_grab_object:
		_set_mesh_overlay_recursive(hovered_grab_object, null)

	hovered_grab_object = object

	if hovered_grab_object:
		_set_mesh_overlay_recursive(hovered_grab_object, highlight_material)


func _can_grab_body(body: RigidBody3D) -> bool:
	if body == null:
		return false
	if body.is_in_group("drivable"):
		return false
	if body.has_meta("welded_vehicle"):
		return false

	return true


func _set_mesh_overlay_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = material

	for child in node.get_children():
		_set_mesh_overlay_recursive(child, material)


func _handle_interaction() -> void:
	if active_vehicle:
		_exit_vehicle()
		return

	if held_object and _try_install_vehicle_part():
		return

	if held_object and _try_start_refuel():
		return

	if held_object and _try_weld_held_object():
		return

	if held_object:
		_drop_held_object()
		return

	var radio_hit := _crosshair_hit(grab_distance)
	var radio := radio_hit.get("collider") as Area3D
	if radio and radio.is_in_group("house_front_door"):
		radio.get_parent().request_open_door()
		return
	if radio and radio.is_in_group("road_radio"):
		if is_instance_valid(listening_radio) and listening_radio != radio:
			listening_radio.stop_listening()
		radio.toggle_listening(self)
		return

	if _try_enter_vehicle():
		return

	if _try_remove_vehicle_part():
		return

	if _try_unweld_pointed_object():
		return

	_toggle_grab()


func _try_enter_vehicle() -> bool:
	var hit := _raycast_area_target(vehicle_interact_distance)
	if hit.is_empty():
		return false

	var target := hit.collider as Area3D
	if target == null:
		return false
	var seat_target := target.is_in_group("vehicle_seat")
	var door_target := target.name in [&"DoorFL", &"DoorFR", &"DoorRL", &"DoorRR"]
	if not seat_target and not door_target:
		return false

	var car := target.get_parent() as Node3D
	if car == null or not car.is_in_group("drivable"):
		return false
	if not car.can_enter_from_position(global_position):
		return false
	if NetworkManager.is_online():
		if car.seat_occupants.size() == car.seat_capacity() and not car.seat_occupants.has(0):
			return false
		car.request_ride()
	else:
		_enter_vehicle(car)
	return true


func set_shared_seat(vehicle: Node3D, seat: int) -> void:
	var previous_seat := shared_seat
	shared_seat = seat
	if seat < 0:
		active_vehicle = null
		collision_shape.set_deferred("disabled", false)
		show()
		var side := -1.0 if previous_seat % 2 == 0 else 1.0
		var outside := vehicle.to_global(Vector3(side * 1.7, 1.0, 0.0))
		global_position = outside if _is_exit_position_clear(outside) else _find_safe_exit_position(vehicle, outside)
		remote_position = global_position
		if is_multiplayer_authority():
			_reset_standing_shape()
			velocity = Vector3.ZERO
			camera.make_current()
			$HUD/Crosshair.show()
			_update_fuel_hud()
		return
	if active_vehicle == vehicle:
		return
	active_vehicle = vehicle
	global_position = vehicle.global_position
	collision_shape.set_deferred("disabled", true)
	hide()
	if is_multiplayer_authority():
		_set_hovered_grab_object(null)
		$HUD/Crosshair.hide()
		vehicle.activate_shared_camera()


func _enter_vehicle(car: Node3D, restoring: bool = false) -> void:
	active_vehicle = car
	_set_hovered_grab_object(null)
	$HUD/Crosshair.hide()
	camera.current = false
	collision_shape.disabled = true
	hide()
	active_vehicle.call("enter", self, restoring)


func _exit_vehicle() -> void:
	var vehicle := active_vehicle
	var exit_position: Vector3 = active_vehicle.call("exit") as Vector3
	active_vehicle = null
	$HUD/Crosshair.show()
	velocity = Vector3.ZERO

	_reset_standing_shape()
	global_position = _find_safe_exit_position(vehicle, exit_position)
	collision_shape.disabled = false
	show()
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_fuel_hud()


func _reset_standing_shape() -> void:
	var shape := collision_shape.shape as CapsuleShape3D
	shape.height = standing_height
	collision_shape.position.y = 0.0
	head.position.y = standing_head_height


func _find_safe_exit_position(vehicle: Node3D, requested_position: Vector3) -> Vector3:
	if vehicle == null:
		return requested_position

	var away := requested_position - vehicle.global_position
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = -vehicle.global_transform.basis.x
		away.y = 0.0
	away = away.normalized()

	var base_height := requested_position.y
	var distances: Array[float] = [3.5, 4.5, 5.5, 6.5, 8.0]
	for distance in distances:
		var candidate: Vector3 = vehicle.global_position + away * distance
		candidate.y = base_height
		if _is_exit_position_clear(candidate):
			return candidate

	var fallback := vehicle.global_position + away * 8.0
	fallback.y = base_height + 0.35
	return fallback


func _is_exit_position_clear(position: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.transform = Transform3D(Basis.IDENTITY, position + collision_shape.position)
	query.collision_mask = collision_mask
	query.exclude = [self]
	query.margin = 0.08

	return get_world_3d().direct_space_state.intersect_shape(query, 8).is_empty()


func _try_weld_held_object() -> bool:
	_stop_refuel()
	var car := _find_touching_vehicle(held_object)
	if car == null or not car.has_method("weld_object"):
		return false

	var object := held_object
	if NetworkManager.is_online():
		_drop_held_object()
		_set_hovered_grab_object(null)
		car.request_work("weld", object.get_path())
		return true
	_restore_held_object_physics()
	held_object = null
	_set_hovered_grab_object(null)
	return bool(car.call("weld_object", object))


func _try_install_vehicle_part() -> bool:
	if held_object == null or not held_object.has_meta("vehicle_part_type"):
		return false

	var destination := _pointed_vehicle(vehicle_interact_distance)
	if destination == null or not destination.can_install_part(held_object):
		return false

	var object := held_object
	if NetworkManager.is_online():
		var pose := object.global_transform
		_drop_held_object()
		_set_hovered_grab_object(null)
		destination.request_work("install", object.get_path(), pose)
		return true
	_restore_held_object_physics()
	held_object = null
	_set_hovered_grab_object(null)
	return destination.install_part(object)


func _try_wire_pointed_battery() -> bool:
	if held_object != null:
		return false

	var result := _raycast_grab_target()
	if result.is_empty() or not result.collider is RigidBody3D:
		return false

	var battery := result.collider as RigidBody3D
	if String(battery.get_meta("vehicle_part_type", "")) != "aux_battery":
		return false

	var car := battery.get_meta("welded_vehicle", null) as Node3D
	if car == null or not car.has_method("can_wire_battery") or not car.has_method("wire_battery"):
		return false
	if not bool(car.call("can_wire_battery", battery)):
		return false

	if NetworkManager.is_online():
		car.request_work("wire", battery.get_path())
		return true
	return bool(car.call("wire_battery", battery))


func _try_remove_vehicle_part() -> bool:
	var result := _raycast_area_target(vehicle_interact_distance)
	if result.is_empty() or not result.collider is Area3D:
		return false

	var area := result.collider as Area3D
	if not area.is_in_group("vehicle_removable_part"):
		return false

	var car := area.get_parent() as Node3D
	if car == null or not car.has_method("remove_installed_part") or not car.can_target_part(area):
		return false

	if NetworkManager.is_online():
		car.request_work("remove", car.get_path_to(area))
		return true
	var loose_part := car.call("remove_installed_part", area) as RigidBody3D
	if loose_part == null:
		return false

	_begin_grab_object(loose_part, result.position)
	return true


func _try_start_refuel() -> bool:
	if held_object == null or not held_object.is_in_group("fuel_canister"):
		return false

	var car := _find_refuel_car()
	if car == null:
		return false

	refuel_car = car
	refuel_canister = held_object
	refuel_start_fuel = _get_car_fuel_amount(refuel_car)
	refuel_target_fuel = _get_car_max_fuel(refuel_car)
	_update_refuel_hud()
	return true


func _find_refuel_car() -> Node3D:
	var hit := _crosshair_hit(vehicle_interact_distance)
	var target := hit.get("collider") as Node3D
	var car := _vehicle_from_target(target)
	if car == null or not car.can_receive_fuel():
		return null
	var filler := car.get_gas_hole_position() as Vector3
	if target.name != "FuelFillerTarget" and target != car.get_node_or_null("GasCapTarget"):
		# With the cap swung aside, aim at the filler on the car itself.
		if (hit["position"] as Vector3).distance_to(filler) > 0.65:
			return null
		if target != car and (not target is Area3D or target.name != "SeatTarget" or car.seat_capacity() != 1):
			return null
	return car if held_object.global_position.distance_to(filler) <= refuel_distance else null


func _try_toggle_vehicle_headlights() -> bool:
	if active_vehicle and active_vehicle.has_method("toggle_headlights"):
		_toggle_vehicle_lights(active_vehicle)
		return true

	var car := _pointed_vehicle(vehicle_interact_distance)
	if car == null or not car.has_method("toggle_headlights"):
		return false

	_toggle_vehicle_lights(car)
	return true


func _toggle_vehicle_lights(car: Node3D) -> void:
	if NetworkManager.is_online():
		car.request_work("lights", "")
	else:
		car.toggle_headlights()


func _pointed_vehicle(distance: float) -> Node3D:
	return _vehicle_from_target(_crosshair_hit(distance).get("collider") as Node3D)


func _vehicle_from_target(target: Node3D) -> Node3D:
	if target is Area3D:
		target = target.get_parent() as Node3D
	return target if target and target.is_in_group("drivable") else null


func _update_refuel(delta: float) -> void:
	if refuel_car == null:
		return

	if held_object != refuel_canister or refuel_canister == null:
		_stop_refuel()
		return

	if _find_refuel_car() != refuel_car:
		_stop_refuel()
		return

	var hole_position := refuel_car.call("get_gas_hole_position") as Vector3
	if refuel_canister.global_position.distance_to(hole_position) > refuel_distance:
		_stop_refuel()
		return

	if not refuel_canister.has_method("drain_fuel"):
		_stop_refuel()
		return

	var requested := refuel_rate * delta
	if NetworkManager.is_online() and not multiplayer.is_server():
		refuel_network_amount += requested
		if refuel_network_amount >= 0.55:
			refuel_car.request_work("fuel", refuel_canister.get_path(), refuel_network_amount)
			refuel_network_amount = 0.0
		return
	var available := float(refuel_canister.call("drain_fuel", requested))
	if available <= 0.0:
		_stop_refuel()
		return

	var accepted := float(refuel_car.call("receive_fuel", available))
	if NetworkManager.is_online() and accepted > 0.0:
		refuel_car._sync_canister.rpc(refuel_canister.get_path(), refuel_canister.fuel_amount + available - accepted)
	var leftover := available - accepted
	if leftover > 0.0:
		refuel_canister.fuel_amount += leftover

	if accepted <= 0.0 or _get_car_fuel_fraction(refuel_car) >= 0.999:
		_stop_refuel()


func _stop_refuel() -> void:
	refuel_network_amount = 0.0
	refuel_car = null
	refuel_canister = null
	refuel_start_fuel = 0.0
	refuel_target_fuel = 0.0
	_update_refuel_hud()


func _find_touching_vehicle(object: RigidBody3D) -> Node3D:
	var target := _crosshair_hit(grab_distance).get("collider") as Node3D
	var car := _vehicle_from_target(target)
	if target and target.has_meta("welded_vehicle"):
		car = target.get_meta("welded_vehicle") as Node3D
	if car == null or object == null:
		return null
	return car if car.can_weld_object(object) else null


func _try_unweld_pointed_object() -> bool:
	var result := _raycast_grab_target()
	if result.is_empty() or not result.collider is RigidBody3D:
		return false

	var object := result.collider as RigidBody3D
	if not object.has_meta("welded_vehicle"):
		return false

	var car := object.get_meta("welded_vehicle") as Node3D
	if car == null or not car.has_method("unweld_object"):
		return false

	if NetworkManager.is_online():
		car.request_work("unweld", object.get_path())
		return true
	return bool(car.call("unweld_object", object))


func _crosshair_hit(distance: float) -> Dictionary:
	return CrosshairTarget.cast(camera, distance, _raycast_exclusions())


func _raycast_grab_target() -> Dictionary:
	var hit := _crosshair_hit(grab_distance)
	return hit if hit.get("collider") is RigidBody3D else {}


func _raycast_area_target(distance: float) -> Dictionary:
	var hit := _crosshair_hit(distance)
	return hit if hit.get("collider") is Area3D else {}


func _raycast_body_target(distance: float) -> Dictionary:
	var hit := _crosshair_hit(distance)
	return hit if _vehicle_from_target(hit.get("collider") as Node3D) else {}


func _raycast_exclusions() -> Array:
	var exclusions := [get_rid()]
	if is_instance_valid(held_object):
		exclusions.append(held_object.get_rid())
	return exclusions


func gameplay_ui_open() -> bool:
	var world := get_tree().current_scene
	var pause_menu := world.get_node_or_null("PauseMenu") if world else null
	return pause_menu != null and pause_menu.gameplay_ui_open()


func _create_interaction_tip() -> void:
	interaction_tip = PanelContainer.new()
	interaction_tip.name = "InteractionTip"
	interaction_tip.theme = Style.make_theme()
	interaction_tip.add_theme_stylebox_override("panel", Style.box(Style.SURFACE, Style.LINE, 8))
	interaction_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_label = Style.label("", 15)
	interaction_tip.add_child(interaction_label)
	$HUD.add_child(interaction_tip)
	interaction_tip.hide()


func can_listen_to_radio(at: Vector3) -> bool:
	return not is_instance_valid(active_vehicle) and camera.global_position.distance_squared_to(at) <= 36.0


func show_radio_caption(radio: Area3D, message: String) -> void:
	listening_radio = radio
	if radio_caption == null:
		radio_caption = PanelContainer.new()
		radio_caption.theme = Style.make_theme()
		radio_caption.add_theme_stylebox_override("panel", Style.box(Style.SURFACE, Style.LINE, 10))
		radio_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		radio_caption_label = Style.label("", 17)
		radio_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		radio_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		radio_caption.add_child(radio_caption_label)
		$HUD.add_child(radio_caption)
	radio_caption_label.text = message
	if message.is_empty():
		radio_caption.hide()
		return
	_layout_radio_caption()


func clear_radio_caption(radio: Area3D) -> void:
	if listening_radio == radio:
		listening_radio = null
		if radio_caption:
			radio_caption.hide()


func _layout_radio_caption() -> void:
	var extent := get_viewport().get_visible_rect().size
	var ui_scale: float = GameSettings.ui_scale
	radio_caption_label.custom_minimum_size.x = minf(600.0, (extent.x - 52.0) / ui_scale)
	radio_caption.reset_size()
	radio_caption.scale = Vector2.ONE * ui_scale
	var scaled := radio_caption.size * ui_scale
	radio_caption.position = Vector2((extent.x - scaled.x) * 0.5, extent.y - scaled.y - 60.0)
	radio_caption.visible = not radio_caption_label.text.is_empty() and not gameplay_ui_open()


func _update_interaction_tip() -> void:
	if is_instance_valid(listening_radio) and radio_caption:
		radio_caption.visible = not radio_caption_label.text.is_empty() and not gameplay_ui_open()
	var tip := "" if gameplay_ui_open() else _interaction_text()
	interaction_tip.visible = not tip.is_empty()
	if tip.is_empty():
		return
	interaction_label.text = tip
	interaction_tip.size = interaction_tip.get_combined_minimum_size()
	var viewport_size := get_viewport().get_visible_rect().size
	var fit := clampf((viewport_size.x - 32.0) / interaction_tip.size.x, 0.01, GameSettings.ui_scale)
	interaction_tip.scale = Vector2.ONE * fit
	var top := 16.0
	if GameSettings.show_fps:
		top += 30.0 * GameSettings.ui_scale
	interaction_tip.position = Vector2(16.0, top)


func _interaction_text() -> String:
	if is_instance_valid(active_vehicle):
		if NetworkManager.is_online() and shared_seat > 0:
			return "Mouse  Look around   ·   E  Exit"
		return "C  Change camera   ·   L  Headlights   ·   E  Exit"
	var hit := _crosshair_hit(vehicle_interact_distance)
	var target := hit.get("collider") as Node3D
	var car := _vehicle_from_target(target)
	if is_instance_valid(held_object):
		if car and held_object.has_meta("vehicle_part_type") and held_object.get_meta("vehicle_part_type") != "aux_battery":
			var reason: String = car.install_blocker(held_object)
			if reason.is_empty():
				return "E  Install %s" % _object_title(held_object)
			if not _find_touching_vehicle(held_object):
				return "%s   ·   E  Drop" % reason
			return "%s   ·   E  Weld" % reason
		if held_object.is_in_group("fuel_canister") and car:
			if _find_refuel_car():
				return "E  Refuel"
			if target.name == "GasCapTarget" and not car.is_gas_cap_open():
				return "Hold left mouse and drag  Open fuel door"
			if not car.is_gas_cap_open() and car.seat_capacity() == 4:
				return "Open the fuel door on the right rear quarter panel   ·   E  Drop can"
			if car.can_receive_fuel():
				return "Aim the can at the open fuel filler   ·   E  Drop can"
		if _is_spray_can(held_object) and car:
			return "Hold left mouse  Paint   ·   R  Change color   ·   E  Drop"
		if _find_touching_vehicle(held_object):
			return "E  Weld %s to vehicle" % _object_title(held_object)
		return "E  Drop %s" % _object_title(held_object)
	if target == null:
		return ""
	if target.is_in_group("road_radio") and camera.global_position.distance_squared_to(hit["position"]) <= grab_distance * grab_distance:
		return "E  Turn off radio" if target == listening_radio else "E  Tune radio"
	if target.is_in_group("house_front_door") and camera.global_position.distance_squared_to(hit["position"]) <= grab_distance * grab_distance:
		return "E  Open front door"
	if target.is_in_group("shack_interactable"):
		return "Hold left mouse and drag  Move %s" % ("shutter" if target.name == "GarageDoorTarget" else "door")
	if target is Area3D and car:
		var door := target.name in [&"DoorFL", &"DoorFR", &"DoorRL", &"DoorRR"]
		if (door or target.is_in_group("vehicle_seat")) and car.can_enter_from_position(global_position):
			if NetworkManager.is_online() and car.seat_occupants.size() == car.seat_capacity() and not car.seat_occupants.has(0):
				return "All seats occupied"
			return "E  Enter %s" % car.get_vehicle_title()
		if target.name == "GasCapTarget":
			return "Hold left mouse and drag  Move fuel door"
		if target.name == "FuelFillerTarget":
			return "Fuel filler   ·   Bring a gas can"
		if car.can_target_part(target):
			var slot := String(target.get_meta("part_type", ""))
			if slot in ["hood", "trunk"] or door:
				return "Hold left mouse and drag  Move %s   ·   E  Remove" % _part_title(slot)
			if target.is_in_group("vehicle_removable_part"):
				return "E  Remove %s" % _part_title(slot)
	if car:
		return "L  Toggle headlights"
	if target is RigidBody3D and camera.global_position.distance_to(hit["position"]) <= grab_distance:
		if target.has_meta("welded_vehicle"):
			var vehicle: Node3D = target.get_meta("welded_vehicle")
			if vehicle.can_wire_battery(target):
				return "R  Wire battery   ·   E  Unweld"
			return "E  Unweld %s" % _object_title(target)
		if _can_grab_body(target):
			return "E  Pick up %s" % _object_title(target)
	return ""


func _object_title(object: Node3D) -> String:
	if object.is_in_group("fuel_canister"):
		return "fuel can"
	if _is_spray_can(object):
		return "spray can"
	return _part_title(String(object.get_meta("vehicle_part_type", "object")))


func _part_title(slot: String) -> String:
	if slot.begins_with("door_"):
		return "door"
	if slot.begins_with("wheel_"):
		return "wheel"
	if slot == "aux_battery":
		return "auxiliary battery"
	return slot.replace("_", " ")


func _push_colliding_bodies(walking_velocity: Vector3, delta: float) -> void:
	push_send_elapsed += delta
	if walking_velocity.length_squared() < 0.1:
		return
	var online := NetworkManager.is_online()
	if online and push_send_elapsed < 0.05:
		return
	for index in get_slide_collision_count():
		var contact := get_slide_collision(index)
		var body := contact.get_collider() as RigidBody3D
		if body == null or body == held_object or body.has_meta("welded_vehicle"):
			continue
		var direction := -contact.get_normal().slide(Vector3.UP).normalized()
		var approach := walking_velocity.dot(direction)
		if approach < 0.25 or absf(contact.get_normal().y) > 0.65:
			continue
		var strength := clampf(approach / 6.0, 0.16, 1.0)
		if online:
			push_send_elapsed = 0.0
			if multiplayer.is_server():
				_apply_shared_push(body, direction, strength)
			else:
				_request_push.rpc_id(1, body.get_path(), direction, strength)
		elif not body.freeze:
			_apply_push(body, direction, strength, delta)
		return


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _request_push(path: NodePath, direction: Vector3, strength: float) -> void:
	if not multiplayer.is_server() or not direction.is_finite() or not is_finite(strength):
		return
	var body := get_node_or_null(path) as RigidBody3D
	if body and body.global_position.distance_squared_to(global_position) <= 16.0:
		_apply_shared_push(body, direction.slide(Vector3.UP).normalized(), clampf(strength, 0.0, 1.0))


func _apply_shared_push(body: RigidBody3D, direction: Vector3, strength: float) -> void:
	if body.freeze or active_vehicle or body.has_meta("welded_vehicle"):
		return
	_apply_push(body, direction, strength, 0.05)
	if not body.is_in_group("drivable"):
		_sync_pushed_body.rpc(body.get_path(), body.global_transform, body.linear_velocity)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _sync_pushed_body(path: NodePath, pose: Transform3D, motion: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var body := get_node_or_null(path) as RigidBody3D
	if body and not body.freeze:
		body.global_transform = pose
		body.linear_velocity = motion


func _apply_push(body: RigidBody3D, direction: Vector3, strength: float, delta: float) -> void:
	var acceleration := 1.6 if body.is_in_group("drivable") else 11.0
	if body.linear_velocity.dot(direction) < 2.0:
		body.apply_central_impulse(direction * body.mass * acceleration * strength * delta)


func _update_fuel_hud() -> void:
	driving_hud.show_vehicle(active_vehicle)


func _update_refuel_hud() -> void:
	if refuel_panel == null:
		return

	var is_refueling := refuel_car != null and refuel_canister != null
	refuel_panel.visible = is_refueling
	if not is_refueling:
		return

	refuel_fill.scale.x = _get_refuel_progress_fraction()
	canister_fill.scale.x = _get_canister_fuel_fraction(refuel_canister)
	refuel_label.text = "Refueling %.0f%%" % (_get_car_fuel_fraction(refuel_car) * 100.0)


func _get_refuel_progress_fraction() -> float:
	if refuel_car == null or refuel_target_fuel <= refuel_start_fuel:
		return 0.0

	var current := _get_car_fuel_amount(refuel_car)
	return clampf((current - refuel_start_fuel) / (refuel_target_fuel - refuel_start_fuel), 0.0, 1.0)


func _get_car_fuel_fraction(car: Node3D) -> float:
	return float(car.call("get_fuel_fraction")) if car and car.has_method("get_fuel_fraction") else 0.0


func _get_car_fuel_amount(car: Node3D) -> float:
	return float(car.get("fuel_amount")) if car else 0.0


func _get_car_max_fuel(car: Node3D) -> float:
	return float(car.get("max_fuel")) if car else 1.0


func _get_canister_fuel_fraction(canister: Node) -> float:
	return float(canister.call("get_fuel_fraction")) if canister and canister.has_method("get_fuel_fraction") else 0.0
