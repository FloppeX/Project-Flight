extends RefCounted
## Conservative vertical/deceleration screens and a time estimate for comparing
## compact arrivals. This is not a full aircraft simulation or a Dubins join.

static func assess(legs: Array, position: Vector3, velocity: Vector3,
		climb_mps: float, descent_angle_deg: float, turn_radius_m: float,
		deceleration_mps2: float) -> Dictionary:
	if legs.size() < 2:
		return {"valid": false, "reason": "missing_legs"}
	var previous := position
	var distance_m := 0.0
	var time_s := 0.0
	var distance_before_arc := 0.0
	var first_direction := Vector3.ZERO
	var first_speed := maxf(float(legs[0].get("speed_mps", 60.0)), 1.0)
	var reached_arc := false
	var live_speed := velocity.slide(Vector3.UP).length()
	var traversal_speed := live_speed
	var deceleration := maxf(deceleration_mps2, 0.1)
	for index in legs.size():
		var leg: Dictionary = legs[index]
		var target: Vector3 = leg.position
		var flat := (target - previous).slide(Vector3.UP)
		var distance := flat.length()
		if str(leg.get("route_primitive", "")) == "arc":
			distance = absf(float(leg.get("arc_sweep_rad", 0.0))) * float(leg.get("turn_radius_m", 0.0))
			reached_arc = true
		elif not reached_arc:
			distance_before_arc += distance
		if index == 0 and distance > 1.0: first_direction = flat.normalized()
		var speed := maxf(float(leg.get("speed_mps", first_speed)), 1.0)
		var duration := distance / speed
		# Fast entries cannot use target-speed travel time as available climb time.
		# Carry the braking speed across legs until the requested speed is reached.
		if traversal_speed > speed:
			var braking_leg_distance := minf(distance, (traversal_speed * traversal_speed - speed * speed) / (2.0 * deceleration))
			var exit_speed := sqrt(maxf(speed * speed, traversal_speed * traversal_speed - 2.0 * deceleration * braking_leg_distance))
			duration = (traversal_speed - exit_speed) / deceleration + (distance - braking_leg_distance) / speed
			traversal_speed = exit_speed
		else:
			traversal_speed = speed
		var rise := target.y - previous.y
		var vertical_limit := maxf(climb_mps, 0.1) if rise >= 0.0 else speed * tan(deg_to_rad(clampf(descent_angle_deg, 1.0, 45.0)))
		# A capture sphere cannot make a climb in place flyable. Allow only a small
		# numerical/height tolerance; turning time is not free climb distance.
		var allowable_height := vertical_limit * duration if rise >= 0.0 else distance * tan(deg_to_rad(clampf(descent_angle_deg, 1.0, 45.0)))
		if absf(rise) > allowable_height + 5.0:
			return {"valid": false, "reason": "climb_unreachable" if rise > 0 else "descent_unreachable",
				"leg": index, "height_change_m": rise, "distance_m": distance,
				"available_time_s": duration, "required_time_s": absf(rise) / vertical_limit}
		distance_m += distance
		time_s += duration
		previous = target
	var braking_distance := maxf(live_speed * live_speed - first_speed * first_speed, 0.0) / (2.0 * maxf(deceleration_mps2, 0.1))
	if braking_distance > distance_before_arc:
		return {"valid": false, "reason": "insufficient_deceleration_distance",
			"required_distance_m": braking_distance, "available_distance_m": distance_before_arc}
	var turn_angle := 0.0
	if live_speed > 1.0 and first_direction.length_squared() > 0.5:
		turn_angle = acos(clampf(velocity.slide(Vector3.UP).normalized().dot(first_direction), -1.0, 1.0))
	# Include the turn needed to join the outbound downwind, not just the initial
	# bearing. This prevents a short cross-deck chord from scoring as an instant turn.
	var downwind := (Vector3(legs[1].position) - Vector3(legs[0].position)).slide(Vector3.UP)
	if first_direction.length_squared() > 0.5 and downwind.length_squared() > 1.0:
		turn_angle += acos(clampf(first_direction.dot(downwind.normalized()), -1.0, 1.0))
	var turn_time := turn_angle * maxf(turn_radius_m, 1.0) / maxf(live_speed, first_speed)
	return {"valid": true, "reason": "", "estimated_time_s": time_s + turn_time,
		"route_distance_m": distance_m, "join_turn_time_s": turn_time,
		"braking_distance_m": braking_distance}
