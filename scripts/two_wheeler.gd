extends "res://scripts/drivable_vehicle.gd"

const BikeModel := preload("res://scripts/two_wheeler_model.gd")
const BIKE_ENGINE := preload("res://assets/vehicles/parts/bike_engine.tscn")

@export var motorized := false

var fork: Node3D
var pedal_crank: Node3D


func _ready() -> void:
	vehicle_mass = 185.0 if motorized else 86.0
	max_torque = 75.0 if motorized else 22.0
	max_rpm = 8200.0 if motorized else 3000.0
	motor_drag = 0.002 if motorized else 0.0006
	motor_moment = 0.28 if motorized else 0.14
	clutch_out_rpm = 2400.0 if motorized else 1250.0
	gear_ratios.assign([2.8, 1.85, 1.35, 1.02] if motorized else [2.6, 1.9, 1.35])
	final_drive = 3.2 if motorized else 2.4
	fuel_amount = 3.0 if motorized else 0.0
	max_fuel = 16.0
	idle_fuel_burn_rate = 0.004
	throttle_fuel_burn_rate = 0.025
	front_tire_radius = 0.34
	rear_tire_radius = 0.34
	front_tire_width = 0.18 if motorized else 0.075
	rear_tire_width = front_tire_width
	front_wheel_mass = 7.0 if motorized else 2.5
	rear_wheel_mass = front_wheel_mass
	front_spring_length = 0.16
	rear_spring_length = 0.16
	front_damping_ratio = 0.85
	rear_damping_ratio = 0.85
	max_steering_angle = deg_to_rad(29 if motorized else 33)
	steering_speed_decay = 0.45
	traction_control_max_slip = 1.25
	front_torque_split = 0.0
	center_of_gravity_height_offset = -0.19
	wheel_to_body_torque_multiplier = 0.0
	start_with_removed_panels = false
	start_with_random_body_color = false
	body_deformation_enabled = false
	_build_bike()
	super._ready()


func _setup_interactables() -> void:
	$SeatTarget.add_to_group("vehicle_seat")


func _setup_engine_bay_models() -> void:
	pass


func _setup_removable_parts() -> void:
	_register_wheel_part("wheel_front", front_left_wheel, "FrontWheel")
	_register_wheel_part("wheel_rear", rear_left_wheel, "RearWheel")
	for slot in ["wheel_front", "wheel_rear"]:
		var target: CollisionShape3D = removable_parts[slot]["area"].get_child(0)
		target.shape.size = Vector3(0.34, 0.68, 0.68)
	if motorized:
		_register_removable_part("engine", "Engine", Vector3(0.62, 0.51, 0.61))
		removable_parts["engine"]["requires_hood_open"] = false


func _apply_engine_variant(variant: String) -> void:
	super._apply_engine_variant(variant)
	if motorized:
		match variant:
			"V8":
				max_torque = 420.0
			"Stock":
				max_torque = 285.0
			"Electric":
				max_torque = 320.0
			"Bike":
				max_torque = base_max_torque
				max_rpm = base_max_rpm
				idle_fuel_burn_rate = base_idle_fuel_burn_rate
				throttle_fuel_burn_rate = base_throttle_fuel_burn_rate
	max_clutch_torque = max_torque * max_clutch_torque_ratio


func _capture_base_vehicle_stats() -> void:
	if motorized:
		current_engine_variant = "Bike"
	super._capture_base_vehicle_stats()


func _fit_installed_engine(part: Node3D, variant: String) -> void:
	if variant != "Bike":
		# The same installed envelope as the sedan, mounted across the bike frame.
		part.scale = Vector3(0.3268, 0.253, 0.3268)


func _get_install_target_part_type(body: RigidBody3D) -> String:
	if body.get_meta("vehicle_part_type", "") == "engine" and not motorized:
		return ""
	return super._get_install_target_part_type(body)


func _has_required_drive_parts() -> bool:
	return _get_installed_wheel_count() == 2 and (not motorized or removable_parts["engine"]["installed"])


func _has_drive_energy() -> bool:
	return not motorized or super._has_drive_energy()


func _get_running_engine_variant() -> String:
	return super._get_running_engine_variant() if motorized else ""


func _has_hood_access() -> bool:
	return motorized


func can_enter_from_position(_player_position: Vector3) -> bool:
	return not is_instance_valid(driver)


func can_receive_fuel() -> bool:
	return motorized and current_engine_variant != "Electric" and fuel_amount < max_fuel


func get_gas_hole_position() -> Vector3:
	return to_global(Vector3(0, 1.01, -0.32))


func get_fuel_text() -> String:
	return super.get_fuel_text() if motorized else "Pedal power"


func get_fuel_fraction() -> float:
	return super.get_fuel_fraction() if motorized else 1.0


func _update_fuel(delta: float) -> void:
	if motorized:
		super._update_fuel(delta)


func _update_driver_inputs() -> void:
	super._update_driver_inputs()
	if brake_input > 0.0 or handbrake_input > 0.0:
		throttle_input = 0.0
	if is_zero_approx(throttle_input):
		throttle_amount = 0.0
		clutch_input = 1.0


func can_auto_reverse() -> bool:
	return false


func process_clutch(delta: float) -> void:
	if is_zero_approx(throttle_input):
		# Disengage the drivetrain so stored engine revs cannot drive a coasting wheel.
		clutch_torque = 0.0
		tcs_active = false
		return
	super.process_clutch(delta)


func _process(delta: float) -> void:
	super._process(delta)
	fork.rotation.y = front_left_wheel.rotation.y
	if front_left_wheel.wheel_node:
		fork.position.y = front_left_wheel.position.y + front_left_wheel.wheel_node.position.y
	if pedal_crank and is_instance_valid(driver):
		pedal_crank.rotate_x(-maxf(0.0, -local_velocity.z) * throttle_amount * delta * 1.8)


func process_steering(delta: float) -> void:
	super.process_steering(delta)
	var steer_limit := lerpf(1.0, 0.29, smoothstep(4.0, 23.0, speed))
	front_left_wheel.steer(steering_amount * steer_limit, max_steering_angle)


func process_stability() -> void:
	if not vehicle_inertia:
		return
	# A roll servo lets riders lean into turns and keeps the bike upright at a stop.
	var forward := -global_basis.z
	var lean := clampf(-steering_amount * speed * 0.032, -0.31, 0.31)
	var target_up := Vector3.UP.rotated(forward, lean)
	var up_error := global_basis.y.cross(target_up)
	var roll_speed := angular_velocity.dot(forward)
	apply_torque(forward * vehicle_inertia.z * (up_error.dot(forward) * 42.0 - roll_speed * 10.0))
	var right := global_basis.x
	var pitch_speed := angular_velocity.dot(right)
	apply_torque(right * vehicle_inertia.x * (up_error.dot(right) * 38.0 - pitch_speed * 10.0))


func _build_bike() -> void:
	var model := BikeModel.build(self, front_left_wheel.wheel_node, rear_left_wheel.wheel_node, motorized)
	fork = model["fork"]
	pedal_crank = model["pedals"]
	if not motorized:
		return
	var motor := BIKE_ENGINE.instantiate() as MeshInstance3D
	motor.position = Vector3(0, 0.47, 0)
	add_child(motor)
	var headlight := SpotLight3D.new()
	headlight.add_to_group("vehicle_headlight")
	headlight.position = Vector3(0, 0.535, 0.036)
	fork.add_child(headlight)
