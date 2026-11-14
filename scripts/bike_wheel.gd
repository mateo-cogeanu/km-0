extends "res://addons/gevp/scripts/wheel.gd"


func get_suspension_speed(compression: float, delta: float) -> float:
	return clampf(super.get_suspension_speed(compression, delta), -1800.0, 1800.0)


func limit_suspension_force(force: float) -> float:
	return clampf(force, 0.0, mass_over_wheel * 45.0)


func process_tires(braking: bool, delta: float) -> void:
	# Narrow tires use a bounded contact patch to prevent a light bike from rebounding
	# off the car tire model's much stiffer slip curve.
	var forward_slip := spin * tire_radius + local_velocity.z
	slip_vector = Vector2(-local_velocity.x, forward_slip) / maxf(absf(local_velocity.z), 2.0)
	spin_velocity_diff = forward_slip
	var grip := minf(spring_force, mass_over_wheel * 22.0) * (1.38 if surface_type == "Road" else 1.12)
	var side_force := -local_velocity.x * mass_over_wheel * 20.0
	var longitudinal_limit := grip * 0.72
	force_vector = Vector2(
		clampf(side_force, -grip, grip),
		clampf(-forward_slip * mass_over_wheel * 8.0, -longitudinal_limit, longitudinal_limit)
	)
	if braking:
		# A rear tire can still be spun up from a rev just before the rider brakes.
		# Use the brake demand to settle that slip instead of delivering another push.
		force_vector.y = -local_velocity.z * mass_over_wheel * vehicle.brake_amount * 8.0
		spin = lerpf(spin, -local_velocity.z / tire_radius, minf(delta * 18.0, 1.0))
	elif is_zero_approx(vehicle.throttle_input):
		# Match wheel spin to the road while coasting. Residual spin must not
		# turn into another burst of acceleration when the brake is released.
		spin = -local_velocity.z / tire_radius
		force_vector.y = -local_velocity.z * mass_over_wheel * 0.22
	force_vector.y += process_rolling_resistance() * -signf(local_velocity.z)
	force_vector = force_vector.limit_length(grip)
	limit_spin = absf(forward_slip) > 2.0
