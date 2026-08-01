class_name FlightPathFollower
extends RefCounted

## Shared 3D path-execution guidance.
##
## This layer knows nothing about targets, weapons, recovery clearance or pilot
## states. It receives the aircraft's current motion and a desired 3D velocity,
## then returns a compatible bank, positive wing-load target and vertical-speed
## demand. AIPilot's aerodynamic inner loop converts that demand into controls.


static func solve_acceleration_guidance(
	actual_velocity_world: Vector3,
	body_forward_world: Vector3,
	requested_accel_world: Vector3,
	desired_vs_mps: float,
	fallback_horizontal_bank_rad: float,
	bank_limit_deg: float,
	maximum_load_g: float,
	nonwing_vertical_accel_mps2: float
) -> Dictionary:
	## Resolve one requested world-space acceleration into the orientation and
	## magnitude of the wing lift vector.  This is the authority boundary between
	## path guidance and aircraft control: callers may shape the requested 3D
	## acceleration, but they must not independently choose bank and elevator.
	var actual_track_flat := Vector3(
		actual_velocity_world.x,
		0.0,
		actual_velocity_world.z
	)
	if actual_track_flat.length_squared() <= 1.0:
		actual_track_flat = -body_forward_world
		actual_track_flat.y = 0.0
	if actual_track_flat.length_squared() <= 0.0001:
		return {"active": false}
	actual_track_flat = actual_track_flat.normalized()
	var track_right := Vector3(actual_track_flat.z, 0.0, -actual_track_flat.x)
	var signed_right_accel_mps2: float = requested_accel_world.dot(track_right)

	# Near an exact reciprocal target there may be no lateral component in the
	# velocity error. Preserve the caller's chosen turn side without inventing a
	# fixed bank magnitude.
	if absf(signed_right_accel_mps2) <= 0.0001 \
			and absf(fallback_horizontal_bank_rad) > 0.0001:
		signed_right_accel_mps2 = -signf(fallback_horizontal_bank_rad) * 0.0001

	var gravity_mps2: float = float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
	var required_vertical_lift_accel_mps2: float = gravity_mps2 \
		+ requested_accel_world.y - nonwing_vertical_accel_mps2
	var bank_limit_rad: float = deg_to_rad(clampf(bank_limit_deg, 1.0, 179.0))
	var bank_rad: float = clampf(
		-atan2(signed_right_accel_mps2, required_vertical_lift_accel_mps2),
		-bank_limit_rad,
		bank_limit_rad
	)

	# If the requested lift vector lies outside the permitted bank envelope,
	# project it onto the attainable direction.  The previous implementation then
	# raised the projected magnitude until the lateral component was satisfied in
	# full.  That silently discarded the vertical part of the same 3D request: a
	# holding aircraft could ask to descend, but the lateral floor restored exactly
	# enough load to maintain altitude and it spiralled upward indefinitely.
	#
	# Orthogonal projection is the physically coherent compromise.  It minimizes
	# the error of the complete requested acceleration vector, so neither the
	# horizontal nor vertical axis becomes a hidden second controller.
	var bank_abs_rad: float = absf(bank_rad)
	var lateral_accel_mps2: float = absf(signed_right_accel_mps2)
	var projected_load_g: float = (
		lateral_accel_mps2 * sin(bank_abs_rad)
		+ required_vertical_lift_accel_mps2 * cos(bank_abs_rad)
	) / maxf(gravity_mps2, 0.1)
	if projected_load_g <= 0.0:
		# No positive wing load can move the aircraft toward the requested vector
		# at the constrained bank.  Unload with wings level instead of displaying a
		# bank that cannot produce the requested turn.
		bank_rad = 0.0
	var target_load_g: float = clampf(
		maxf(projected_load_g, 0.1),
		0.1,
		maxf(maximum_load_g, 0.1)
	)
	return {
		"active": true,
		"bank_rad": bank_rad,
		"target_load_g": target_load_g,
		"desired_vs_mps": desired_vs_mps,
		"requested_accel_world": requested_accel_world,
		"required_vertical_lift_accel_mps2": required_vertical_lift_accel_mps2,
		"signed_right_accel_mps2": signed_right_accel_mps2,
	}


static func solve_velocity_guidance(
	actual_velocity_world: Vector3,
	body_forward_world: Vector3,
	desired_velocity_world: Vector3,
	velocity_response_time_s: float,
	feedforward_accel_world: Vector3,
	fallback_horizontal_bank_rad: float,
	bank_limit_deg: float,
	maximum_load_g: float,
	minimum_response_time_s: float,
	vertical_path_response: float,
	nonwing_vertical_accel_mps2: float
) -> Dictionary:
	if desired_velocity_world.length_squared() <= 0.0001:
		return {"active": false}

	var response_time_s: float = maxf(velocity_response_time_s, minimum_response_time_s)
	var requested_accel_world: Vector3 = (
		desired_velocity_world - actual_velocity_world
	) / maxf(response_time_s, 0.001) + feedforward_accel_world

	# Only acceleration perpendicular to the ground track turns the aircraft.
	# Longitudinal acceleration remains a throttle/speed-control concern.
	var actual_track_flat := Vector3(
		actual_velocity_world.x,
		0.0,
		actual_velocity_world.z
	)
	if actual_track_flat.length_squared() <= 1.0:
		actual_track_flat = -body_forward_world
		actual_track_flat.y = 0.0
	if actual_track_flat.length_squared() <= 0.0001:
		return {"active": false}
	actual_track_flat = actual_track_flat.normalized()
	var track_right := Vector3(actual_track_flat.z, 0.0, -actual_track_flat.x)
	var signed_right_accel_mps2: float = requested_accel_world.dot(track_right)

	# At an exact reciprocal, velocity subtraction has no lateral component. The
	# fallback bank selects a deterministic turn side while the angular error sets
	# the acceleration magnitude over the same response interval.
	var desired_track_flat := Vector3(
		desired_velocity_world.x,
		0.0,
		desired_velocity_world.z
	)
	if desired_track_flat.length_squared() > 0.0001:
		desired_track_flat = desired_track_flat.normalized()
		var desired_track_right_component: float = desired_track_flat.dot(track_right)
		var desired_track_forward_component: float = desired_track_flat.dot(actual_track_flat)
		var track_error_rad: float = atan2(
			desired_track_right_component,
			desired_track_forward_component
		)
		if desired_track_forward_component < 0.0 \
				and absf(signed_right_accel_mps2) \
					< actual_velocity_world.length() * absf(track_error_rad) / response_time_s:
			var turn_side: float = signf(track_error_rad)
			if absf(turn_side) < 0.5:
				# Positive controller bank corresponds to acceleration toward track-left.
				turn_side = -signf(fallback_horizontal_bank_rad)
			if absf(turn_side) < 0.5:
				turn_side = 1.0
			signed_right_accel_mps2 = turn_side \
				* actual_velocity_world.length() * absf(track_error_rad) / response_time_s

	var desired_vs_mps: float = desired_velocity_world.y
	var vertical_accel_mps2: float = (
		desired_vs_mps - actual_velocity_world.y
	) * maxf(vertical_path_response, 0.0) + feedforward_accel_world.y
	requested_accel_world.y = vertical_accel_mps2
	var resolved: Dictionary = solve_acceleration_guidance(
		actual_velocity_world,
		body_forward_world,
		requested_accel_world,
		desired_vs_mps,
		fallback_horizontal_bank_rad,
		bank_limit_deg,
		maximum_load_g,
		nonwing_vertical_accel_mps2
	)
	if bool(resolved.get("active", false)):
		resolved["desired_velocity_world"] = desired_velocity_world
	return resolved


static func solve_point_guidance(
	actual_position_world: Vector3,
	actual_velocity_world: Vector3,
	body_forward_world: Vector3,
	target_point_world: Vector3,
	desired_speed_mps: float,
	fallback_horizontal_bank_rad: float,
	bank_limit_deg: float,
	maximum_load_g: float,
	flight_path_angle_limit_deg: float,
	minimum_response_time_s: float,
	vertical_path_response: float,
	nonwing_vertical_accel_mps2: float
) -> Dictionary:
	var to_target: Vector3 = target_point_world - actual_position_world
	var horizontal_distance_m: float = Vector2(to_target.x, to_target.z).length()
	if horizontal_distance_m <= 0.01 and absf(to_target.y) <= 0.01:
		return {"active": false}

	var horizontal_direction := Vector3(to_target.x, 0.0, to_target.z)
	if horizontal_direction.length_squared() <= 0.0001:
		horizontal_direction = Vector3(
			actual_velocity_world.x,
			0.0,
			actual_velocity_world.z
		)
	if horizontal_direction.length_squared() <= 0.0001:
		horizontal_direction = -body_forward_world
		horizontal_direction.y = 0.0
	if horizontal_direction.length_squared() <= 0.0001:
		return {"active": false}
	horizontal_direction = horizontal_direction.normalized()

	var desired_fpa_rad: float = atan2(to_target.y, maxf(horizontal_distance_m, 0.001))
	desired_fpa_rad = clampf(
		desired_fpa_rad,
		-deg_to_rad(maxf(flight_path_angle_limit_deg, 0.0)),
		deg_to_rad(maxf(flight_path_angle_limit_deg, 0.0))
	)
	var speed_mps: float = maxf(desired_speed_mps, 1.0)
	var desired_velocity_world: Vector3 = horizontal_direction \
		* (speed_mps * cos(desired_fpa_rad))
	desired_velocity_world.y = speed_mps * sin(desired_fpa_rad)
	var desired_horizontal_speed_mps: float = maxf(
		Vector2(desired_velocity_world.x, desired_velocity_world.z).length(),
		1.0
	)
	var response_time_s: float = maxf(horizontal_distance_m, 1.0) \
		/ desired_horizontal_speed_mps
	return solve_velocity_guidance(
		actual_velocity_world,
		body_forward_world,
		desired_velocity_world,
		response_time_s,
		Vector3.ZERO,
		fallback_horizontal_bank_rad,
		bank_limit_deg,
		maximum_load_g,
		minimum_response_time_s,
		vertical_path_response,
		nonwing_vertical_accel_mps2
	)
