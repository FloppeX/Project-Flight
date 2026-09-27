class_name LandingSight
extends RefCounted

## Pure kinematic projections used by AIPilot's synthetic carrier-landing sight.
## The sight deliberately observes only: it does not move the aircraft or alter
## the arresting-cable capture volume.

const MIN_AXIS_SPEED_MPS: float = 0.05
const MIN_NORMAL_SPEED_MPS: float = 0.05

static func bounded_lineup_lateral_acceleration(request_mps2: float,
		vertical_lift_mps2: float, bank_limit_rad: float, gravity_mps2: float = 9.81) -> float:
	# Keep the lateral request compatible with the available bank at the desired
	# vertical support, instead of purchasing sideways authority with a steep climb.
	var support := maxf(vertical_lift_mps2, gravity_mps2 * 0.35)
	var limit := support * tan(clampf(absf(bank_limit_rad), 0.0, deg_to_rad(70.0)))
	return clampf(request_mps2, -limit, limit)

static func escape_response_budget(sink_mps: float, bank_rad: float,
		roll_rate_mps: float, available_load_g: float, response_s: float = 0.6) -> Dictionary:
	# Clearance lost before the wing can roll upright and arrest descent. This is
	# an attainable-response estimate, not instantaneous maximum-sink reachability.
	var sink := maxf(sink_mps, 0.0)
	var delay := maxf(response_s, 0.0) + absf(bank_rad) / maxf(roll_rate_mps, 0.15)
	var accel := maxf((available_load_g - 1.0) * 9.81 * 0.65, 0.5)
	return {"time_s": delay + sink / accel,
		"height_m": sink * delay + sink * sink / (2.0 * accel)}

static func bolter_clearance_fpa_floor_rad(deck_height_m: float, forward_speed_mps: float,
		speed_margin_mps: float) -> float:
	if deck_height_m >= 20.0:
		return 0.0
	var climb_mps := lerpf(2.0, 6.0, clampf(speed_margin_mps / 12.0, 0.0, 1.0))
	return atan2(climb_mps, maxf(forward_speed_mps, 1.0))

static func terrain_escape_profile(samples: Array, altitude_m: float, vertical_speed_mps: float,
		response_s: float, up_accel_mps2: float, max_climb_mps: float, clearance_m: float) -> Dictionary:
	# Sample the attainable escape, including time to roll upright and build lift.
	# Required climb is a control cue; insufficient capability remains explicit.
	var required_vs := 0.0
	var min_clearance := INF
	var valid := false
	for sample in samples:
		var t := float(sample.get("time_s", NAN))
		var ground := float(sample.get("height_m", NAN))
		if not is_finite(t) or not is_finite(ground) or t <= 0.0:
			continue
		valid = true
		var delay := minf(maxf(response_s, 0.0), t)
		var available_t := maxf(t - delay, 0.0)
		var accel := maxf(up_accel_mps2, 0.1)
		var initial_vs := minf(vertical_speed_mps, max_climb_mps)
		var accel_t := minf(available_t, maxf(max_climb_mps - initial_vs, 0.0) / accel)
		var climb := initial_vs * accel_t + 0.5 * accel * accel_t * accel_t \
			+ max_climb_mps * maxf(available_t - accel_t, 0.0)
		var delayed_height := altitude_m + vertical_speed_mps * delay
		min_clearance = minf(min_clearance, delayed_height + climb - ground)
		# Account for acceleration loss rather than pretending the requested climb
		# starts instantly when roll recovery ends.
		var acceleration_loss := maxf(max_climb_mps * accel_t \
			- initial_vs * accel_t - 0.5 * accel * accel_t * accel_t, 0.0)
		if ground + clearance_m > altitude_m + vertical_speed_mps * t:
			required_vs = maxf(required_vs,
				(ground + clearance_m - delayed_height + acceleration_loss) / maxf(available_t, 0.25))
	return {"valid": valid, "required_vs_mps": required_vs,
		"desired_vs_mps": clampf(required_vs, 0.0, maxf(max_climb_mps, 0.0)),
		"min_clearance_m": min_clearance, "unreachable": valid and min_clearance < clearance_m}

static func reachable_wire_crossing(wires: Array, vertical_speed_mps: float,
		up_accel_mps2: float, down_accel_mps2: float, lateral_accel_mps2: float,
		max_sink_mps: float, response_s: float = 0.6) -> Dictionary:
	# Test bounded correction AFTER actuator response, not just constant-velocity
	# interception. Feasibility is not a guaranteed catch or a physics override.
	var evaluated := 0
	for wire in wires:
		if not bool(wire.get("valid", false)):
			continue
		var time_s := float(wire.get("time_s", NAN))
		var vertical := float(wire.get("vertical_m", NAN))
		var lateral := float(wire.get("lateral_m", NAN))
		var span := float(wire.get("half_span_m", 0.0)) + float(wire.get("lateral_margin_m", 0.0))
		if not is_finite(time_s) or not is_finite(vertical) or not is_finite(lateral) \
				or not is_finite(vertical_speed_mps) or time_s < 0.0 or span <= 0.0:
			continue
		evaluated += 1
		var duration := maxf(time_s - maxf(response_s, 0.0), 0.0)
		var gain := 0.5 * duration * duration
		var tolerance := maxf(float(wire.get("vertical_tolerance_m", 0.8)), 0.0)
		if absf(lateral) > span + gain * maxf(lateral_accel_mps2, 0.0):
			continue
		if duration < 0.001:
			if absf(vertical) <= tolerance and vertical_speed_mps >= -max_sink_mps \
					and vertical_speed_mps <= 0.0:
				return {"valid": true, "reachable": true, "wire_number": int(wire.get("wire_number", 0)), "up_accel_mps2": 0.0}
			continue
		var low := maxf(-maxf(down_accel_mps2, 0.0), (-tolerance - vertical) / gain)
		var high := minf(maxf(up_accel_mps2, 0.0), (tolerance - vertical) / gain)
		low = maxf(low, (-maxf(max_sink_mps, 0.0) - vertical_speed_mps) / duration)
		high = minf(high, -vertical_speed_mps / duration)
		if low <= high:
			return {"valid": true, "reachable": true, "wire_number": int(wire.get("wire_number", 0)),
				"up_accel_mps2": clampf(0.0, low, high)}
	return {"valid": evaluated > 0, "reachable": false, "wire_number": 0}


static func deck_supported_wire_crossing(wires: Array, contact_s: float,
		hook_normal_speed_mps: float, support_safe: bool, sink_within_limit: bool) -> Dictionary:
	# A free-flight projection continues below the deck after wheel contact.
	# After safe support, continue horizontally at the hook's contact height.
	# This is evidence of a possible catch, never an actual/guaranteed arrest.
	if not support_safe or not sink_within_limit or not is_finite(contact_s) \
			or contact_s < 0.0 or contact_s > 4.0 \
			or not is_finite(hook_normal_speed_mps) or hook_normal_speed_mps >= 0.0:
		return {"valid": false, "reachable": false}
	var best: Dictionary = {"valid": true, "reachable": false}
	for wire in wires:
		var time_s := float(wire.get("time_s", NAN))
		var vertical := float(wire.get("vertical_m", NAN))
		var lateral := float(wire.get("lateral_m", NAN))
		var span := float(wire.get("half_span_m", 0.0)) + float(wire.get("lateral_margin_m", 0.0))
		if not bool(wire.get("valid", false)) or not is_finite(time_s) \
				or not is_finite(vertical) or not is_finite(lateral) \
				or time_s < contact_s or time_s - contact_s > 2.0 or span <= 0.0:
			continue
		var supported_height := vertical - hook_normal_speed_mps * (time_s - contact_s)
		if absf(lateral) <= span \
				and absf(supported_height) <= maxf(float(wire.get("vertical_tolerance_m", 0.8)), 0.0) \
				and time_s < float(best.get("time_s", INF)):
			best = {"valid": true, "reachable": true, "wire_number": int(wire.get("wire_number", 0)),
				"time_s": time_s, "supported_vertical_m": supported_height, "contact_s": contact_s}
	return best

static func roll_capture_input(error_rad: float, rate_rad_s: float,
		max_accel_rad_s2: float, max_rate_rad_s: float, capture_s: float = 0.6) -> float:
	var acceleration := maxf(max_accel_rad_s2, 0.1)
	var rate_limit := maxf(max_rate_rad_s, 0.1)
	var requested_rate := signf(error_rad) * minf(rate_limit,
		minf(sqrt(2.0 * acceleration * absf(error_rad)), absf(error_rad) / maxf(capture_s, 0.1)))
	return clampf((2.0 * requested_rate - rate_rad_s) / rate_limit, -1.0, 1.0)


static func deck_entry_sink_floor_mps(height_m: float, time_s: float,
		current_sink_mps: float, clearance_m: float = 1.5, response_s: float = 0.8) -> float:
	# Finite stern constraint, measured at the lowest main wheel. Allow for the
	# existing descent during pitch response; this is a control cue, not a force.
	var duration := maxf(time_s, 0.1)
	var delay := minf(maxf(response_s, 0.0), duration * 0.5)
	return (clearance_m - height_m - current_sink_mps * delay) / maxf(duration - delay, 0.1)


static func bolter_clear_of_hull(position: Vector3, velocity: Vector3, hull: AABB) -> bool:
	# Carrier-local clearance, independent of approach direction. Keep a short
	# straight-ahead response corridor clear before allowing the rejoin turn.
	if not position.is_finite() or not velocity.is_finite() or not hull.has_volume():
		return false
	var ahead := position + velocity * 2.0
	if minf(position.y, ahead.y) > hull.end.y + 50.0:
		return true
	var corridor := AABB(Vector3(hull.position.x - 30.0, -1.0, hull.position.z - 30.0),
		Vector3(hull.size.x + 60.0, 2.0, hull.size.z + 60.0))
	var flat := Vector3(position.x, 0.0, position.z)
	var flat_ahead := Vector3(ahead.x, 0.0, ahead.z)
	return not corridor.has_point(flat) and corridor.intersects_segment(flat, flat_ahead) == null


static func deck_footprint_path(bounds: Rect2, footprint: Rect2, wheels: Array,
		position: Vector2, velocity: Vector2, contact_s: float, brake_start_s: float,
		stop_distance_m: float, edge_margin_m: float) -> Dictionary:
	# Carrier-local XZ. Constant approach velocity, then finite longitudinal
	# braking; retain lateral drift instead of assuming instant cable centering.
	if not is_finite(contact_s) or contact_s < 0.0 or not is_finite(brake_start_s) \
			or not position.is_finite() or not velocity.is_finite() or wheels.size() < 2 \
			or not bounds.position.is_finite() or not bounds.size.is_finite() \
			or not footprint.position.is_finite() or not footprint.size.is_finite() \
			or not is_finite(stop_distance_m) or not is_finite(edge_margin_m) \
			or footprint.size.x <= 0.0 or footprint.size.y <= 0.0 \
			or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return {"valid": false}
	for wheel in wheels:
		if not wheel is Vector2 or not wheel.is_finite():
			return {"valid": false}
	var inner := bounds.grow(-maxf(edge_margin_m, 0.0))
	# A crossing of the infinite deck plane before the stern is NOT wheel
	# contact. Assess the support path from deck entry instead. Whether the
	# aircraft can arrest its descent to get there belongs to the independent
	# vertical stern/wire reachability checks, not this horizontal envelope.
	var support_s := contact_s
	for wheel in wheels:
		if velocity.y > 1.0:
			support_s = maxf(support_s, (inner.position.y + 0.05 - position.y - wheel.y) / velocity.y)
		elif velocity.y < -1.0:
			support_s = maxf(support_s, (inner.end.y - 0.05 - position.y - wheel.y) / velocity.y)
	var start := maxf(brake_start_s, support_s)
	var stop_s := 2.0 * maxf(stop_distance_m, 0.0) / maxf(absf(velocity.y), 1.0)
	var clearance := INF
	var wheel_clearance := INF
	var body_longitudinal_clearance := INF
	var limiting := {"kind": "none", "edge": "none", "phase": "none", "time_s": 0.0}
	var times := [support_s, start, start + stop_s * 0.5, start + stop_s]
	var phases := ["deck_entry" if support_s > contact_s else "touchdown", "brake_start", "arrest_midpoint", "stop"]
	for sample_index in times.size():
		var t: float = times[sample_index]
		var braking_s: float = maxf(t - start, 0.0)
		var travel := velocity * minf(t, start)
		travel.x += velocity.x * braking_s
		travel.y += velocity.y * braking_s * (1.0 - 0.5 * braking_s / maxf(stop_s, 0.001))
		var centre := position + travel
		var low := centre + footprint.position
		var high := centre + footprint.end
		# Wings still need side clearance, but a fuselage/tail overhanging the
		# stern is not a missing wheel support. Track fore/aft body overhang as
		# telemetry only; existing vertical stern clearance remains independent.
		body_longitudinal_clearance = minf(body_longitudinal_clearance,
			minf(low.y - inner.position.y, inner.end.y - high.y))
		var candidates := [
			{"kind": "body", "edge": "x_min", "clearance_m": low.x - inner.position.x},
			{"kind": "body", "edge": "x_max", "clearance_m": inner.end.x - high.x}]
		for wheel in wheels:
			var point: Vector2 = centre + Vector2(wheel)
			wheel_clearance = minf(wheel_clearance, minf(minf(point.x - inner.position.x, inner.end.x - point.x),
				minf(point.y - inner.position.y, inner.end.y - point.y)))
			candidates.append_array([
				{"kind": "wheel", "edge": "x_min", "clearance_m": point.x - inner.position.x},
				{"kind": "wheel", "edge": "x_max", "clearance_m": inner.end.x - point.x},
				{"kind": "wheel", "edge": "z_min", "clearance_m": point.y - inner.position.y},
				{"kind": "wheel", "edge": "z_max", "clearance_m": inner.end.y - point.y}])
		for candidate in candidates:
			if float(candidate.clearance_m) < clearance:
				clearance = float(candidate.clearance_m)
				limiting = {"kind": candidate.kind, "edge": candidate.edge,
					"phase": phases[sample_index], "time_s": t}
	return {"valid": true, "safe": clearance >= 0.0,
		"clearance_m": clearance, "wheel_clearance_m": wheel_clearance,
		"body_longitudinal_clearance_m": body_longitudinal_clearance,
		"limiting": limiting,
		"support_start_s": support_s, "entry_delay_s": support_s - contact_s,
		"contact_s": contact_s, "stop_s": stop_s, "edge_margin_m": edge_margin_m}


static func deck_entry_lateral_unreachable(position_m: float, speed_mps: float,
		time_s: float, half_width_m: float, accel_mps2: float) -> bool:
	if time_s <= 0.0 or time_s > 4.0:
		return false
	# Optimistic reach: instantaneous maximum correction after actuator delay.
	# Only abandon entries that still cannot reach the physical deck width.
	var correction := 0.5 * maxf(accel_mps2, 0.0) * pow(maxf(time_s - 0.6, 0.0), 2.0)
	return absf(position_m + speed_mps * time_s) - correction > maxf(half_width_m, 0.0)


static func pre_landing_lateral_accel(position_m: float, speed_mps: float,
		response_s: float, accel_limit_mps2: float, time_to_handoff_s: float = INF) -> float:
	# Critically damped line acquisition (natural frequency 0.3 rad/s). Unlike a
	# saturated short-horizon intercept, this brakes closing speed before crossing
	# the centreline. Predict position across actuator lag, then hold the same line.
	var frequency := 0.3
	var predicted_position := position_m + speed_mps * maxf(response_s, 0.1)
	var acceleration := -frequency * frequency * predicted_position - 2.0 * frequency * speed_mps
	var limit := maxf(accel_limit_mps2, 0.1)
	if is_finite(time_to_handoff_s):
		# Centreline pursuit must leave time to remove sideways velocity before
		# final handoff, not merely before the wire. Reserve half the remaining
		# time for braking plus actuator settling; an unreachable offset remains
		# visible to the unchanged handoff gates instead of becoming a late swerve.
		var lag := maxf(response_s, 0.1)
		var speed_limit := 0.5 * limit * maxf(time_to_handoff_s - 2.0 * lag, 0.0)
		acceleration = clampf(acceleration,
			(-speed_limit - speed_mps) / lag, (speed_limit - speed_mps) / lag)
	return clampf(acceleration, -limit, limit)


static func settled_lateral_plan(position_m: float, speed_mps: float, time_to_wire_s: float,
		accel_limit_mps2: float, response_s: float, current_accel_mps2: float) -> Dictionary:
	# Arrive settled four seconds BEFORE the wire. Blend into a damped centreline
	# hold instead of letting a shrinking time-to-go demand violent late reversals.
	# Acquire the centreline during the outer final rather than spending the
	# entire time-to-wire drifting toward it. Keep a finite correction horizon
	# even when the deck is distant, with room for slow actuator response.
	var capture_horizon_s := maxf(6.0, response_s * 4.0)
	var plan := terminal_lateral_plan(position_m, speed_mps, clampf(time_to_wire_s - 4.0, 2.0, capture_horizon_s),
		accel_limit_mps2, response_s, current_accel_mps2)
	var hold_accel := clampf(-0.16 * position_m - 0.8 * speed_mps,
		-accel_limit_mps2, accel_limit_mps2)
	var approach_weight := clampf((time_to_wire_s - 4.0) / 3.0, 0.0, 1.0)
	plan["accel_mps2"] = lerpf(hold_accel, float(plan.accel_mps2), approach_weight)
	plan["settle_before_wire_s"] = 4.0
	return plan

static func high_path_capture_sink_mps(base_sink_mps: float, height_m: float,
		distance_m: float, forward_speed_mps: float, glide_rad: float,
		target_height_m: float, terminal_limit_mps: float, outer_limit_mps: float,
		settle_distance_m: float, current_sink_mps: float = NAN,
		response_s: float = 1.5) -> float:
	# Spend excess altitude before short final. A touchdown sink limit must not
	# prevent a high aircraft from descending more steeply while it still has room.
	var settle_m := maxf(settle_distance_m, 1.0)
	if distance_m <= settle_m:
		return base_sink_mps
	var high_error_m := height_m - target_height_m - distance_m * tan(glide_rad)
	if is_finite(current_sink_mps):
		# Begin removing the extra descent before its existing momentum carries
		# the aircraft through the glideslope. This is a cue, not a physics override.
		high_error_m += (current_sink_mps + forward_speed_mps * tan(glide_rad)) * maxf(response_s, 0.0)
	var correction_weight := clampf((high_error_m - 10.0) / 30.0, 0.0, 1.0)
	var time_to_settle_s := maxf((distance_m - settle_m) / maxf(forward_speed_mps, 1.0), 2.0)
	var intercept_sink_mps := (target_height_m + settle_m * tan(glide_rad) - height_m) / time_to_settle_s
	var sink_limit_mps := lerpf(terminal_limit_mps, maxf(outer_limit_mps, terminal_limit_mps),
		clampf((distance_m - settle_m) / 550.0, 0.0, 1.0))
	var bounded_intercept_mps := maxf(minf(base_sink_mps, intercept_sink_mps), -sink_limit_mps)
	return lerpf(base_sink_mps, bounded_intercept_mps, correction_weight)


static func all_remaining_wires_too_high(wires: Array, current_sink_mps: float,
		max_sink_mps: float, response_s: float, decision_horizon_s: float,
		clearance_margin_m: float) -> bool:
	# Optimistic bound: after response delay, allow an instantaneous transition
	# to maximum descent. Wave off only if even this would pass ABOVE every wire.
	# Ignore lateral misses here: aggressive lateral corrections remain permitted.
	var future_wires := 0
	for wire in wires:
		if not bool(wire.get("valid", false)):
			continue
		var time_s := float(wire.get("time_s", INF))
		var vertical_m := float(wire.get("vertical_m", NAN))
		if not is_finite(time_s) or not is_finite(vertical_m) or not is_finite(current_sink_mps):
			return false
		if time_s < 0.0:
			continue
		future_wires += 1
		if time_s > maxf(decision_horizon_s, 0.0):
			return false
		var best_sink_mps := minf(current_sink_mps, -maxf(max_sink_mps, 0.0))
		var best_height_m := vertical_m + (best_sink_mps - current_sink_mps) \
			* maxf(time_s - maxf(response_s, 0.0), 0.0)
		if best_height_m <= maxf(clearance_margin_m, 0.0) + maxf(float(wire.get("vertical_tolerance_m", 0.8)), 0.0):
			return false
	return future_wires > 0


static func coordinated_terminal_rudder(requested_accel_mps2: float, forward_speed_mps: float,
		measured_track_rate_rad_s: float, body_heading_rate_rad_s: float, sideslip_ratio: float) -> float:
	# The arcade alignment force damps slip without turning the nose. Supply a
	# heading-rate command, then close the loop on the actual flight-path turn.
	# Positive lateral acceleration/rightward slip both require positive rudder.
	var target_rate := clampf(requested_accel_mps2 / maxf(forward_speed_mps, 25.0), -0.15, 0.15)
	return clampf(target_rate * 2.0 + (target_rate - measured_track_rate_rad_s) * 4.0
		+ sideslip_ratio * 2.0 - body_heading_rate_rad_s * 0.4, -0.7, 0.7)

static func energy_aware_rescue_weight(speed_mps: float, target_mps: float,
		stall_floor_mps: float) -> float:
	# Retain full protection near stall. An overspeed aircraft can exchange speed
	# for lift; demanding high power solely because it is low adds more excess energy.
	var reference := maxf(target_mps, stall_floor_mps + 3.0)
	return 1.0 - clampf((speed_mps - reference - 3.0) / 12.0, 0.0, 1.0)


static func terminal_lateral_speed_mps(
		current_lateral_error_m: float,
		time_to_wire_s: float,
		terminal_power: float,
		max_abs_speed_mps: float,
		max_lateral_accel_mps2: float = 0.0
	) -> float:
	## Follow x(t) proportional to time-to-go^power. Power 1 preserves the old
	## constant lateral intercept speed; any power above 1 tapers that speed to
	## zero at the wire instead of crossing the centreline sideways.
	var time_s := maxf(time_to_wire_s, 0.05)
	var power := maxf(terminal_power, 1.0)
	var requested_speed_mps := -power * current_lateral_error_m / time_s
	var speed_limit_mps := maxf(max_abs_speed_mps, 0.0)
	# A time-shaped profile can still demand maximum intercept speed after the
	# aircraft has passed the point where that speed can be removed. Bound it by
	# the elementary stopping envelope v^2 <= 2*a*distance. This intentionally
	# favors a controlled bolter over reaching the deck with unrecoverable side
	# velocity when an entry lies outside the physical capture basin.
	if max_lateral_accel_mps2 > 0.0:
		var stopping_speed_mps := sqrt(
			2.0 * max_lateral_accel_mps2 * absf(current_lateral_error_m)
		)
		speed_limit_mps = minf(speed_limit_mps, stopping_speed_mps)
	return clampf(requested_speed_mps, -speed_limit_mps, speed_limit_mps)

static func terminal_lateral_plan(position_m: float, speed_mps: float, time_s: float,
		accel_limit_mps2: float, response_s: float, current_accel_mps2: float) -> Dictionary:
	# Cubic terminal guidance: both x(T)=0 and v(T)=0, with actuator delay and
	# bounded acceleration. The forecast exposes infeasible entries instead of
	# presenting an uncorrected constant-velocity wire crossing as a landing plan.
	var duration := clampf(time_s, 0.1, 30.0)
	var delay := clampf(response_s, 0.0, duration * 0.5)
	var limit := maxf(accel_limit_mps2, 0.1)
	var initial_accel := clampf(current_accel_mps2, -limit, limit)
	var x := position_m + speed_mps * delay + 0.5 * initial_accel * delay * delay
	var v := speed_mps + initial_accel * delay
	var horizon := maxf(duration - delay, 0.1)
	var initial_request := -6.0 * x / (horizon * horizon) - 4.0 * v / horizon
	var jerk := 12.0 * x / pow(horizon, 3.0) + 6.0 * v / (horizon * horizon)
	var step := horizon / 32.0
	for index in range(32):
		var accel := clampf(initial_request + jerk * (float(index) + 0.5) * step, -limit, limit)
		x += v * step + 0.5 * accel * step * step
		v += accel * step
	return {
		"accel_mps2": clampf(initial_request, -limit, limit),
		"predicted_lateral_m": x,
		"predicted_lateral_speed_mps": v,
		"saturated": absf(initial_request) > limit or absf(initial_request + jerk * horizon) > limit,
	}


static func project_plane_crossing(
		sensor_position: Vector3,
		sensor_velocity: Vector3,
		plane_position: Vector3,
		plane_velocity: Vector3,
		plane_normal: Vector3,
		max_time_s: float
	) -> Dictionary:
	var normal := plane_normal.normalized()
	if normal.length_squared() < 0.5:
		return {"valid": false, "reason": "invalid_plane_normal"}
	var relative_position := sensor_position - plane_position
	var relative_velocity := sensor_velocity - plane_velocity
	var height_m := relative_position.dot(normal)
	var normal_speed_mps := relative_velocity.dot(normal)
	if absf(normal_speed_mps) < MIN_NORMAL_SPEED_MPS:
		return {
			"valid": false,
			"reason": "no_plane_closure",
			"height_m": height_m,
			"normal_speed_mps": normal_speed_mps,
		}
	var time_s := -height_m / normal_speed_mps
	if time_s < 0.0:
		return {
			"valid": false,
			"reason": "plane_crossing_behind",
			"time_s": time_s,
			"height_m": height_m,
			"normal_speed_mps": normal_speed_mps,
		}
	if time_s > maxf(max_time_s, 0.0):
		return {
			"valid": false,
			"reason": "plane_crossing_beyond_horizon",
			"time_s": time_s,
			"height_m": height_m,
			"normal_speed_mps": normal_speed_mps,
		}
	var sensor_at_crossing := sensor_position + sensor_velocity * time_s
	var plane_at_crossing := plane_position + plane_velocity * time_s
	# Remove tiny floating-point residue so debug markers sit exactly on the
	# predicted future deck plane.
	var residual_m := (sensor_at_crossing - plane_at_crossing).dot(normal)
	sensor_at_crossing -= normal * residual_m
	return {
		"valid": true,
		"time_s": time_s,
		"world_position": sensor_at_crossing,
		"plane_world_position": plane_at_crossing,
		"height_m": height_m,
		"normal_speed_mps": normal_speed_mps,
	}


static func project_wire_crossing(
		sensor_position: Vector3,
		sensor_velocity: Vector3,
		wire_position: Vector3,
		wire_velocity: Vector3,
		approach_axis: Vector3,
		deck_right: Vector3,
		deck_normal: Vector3,
		max_time_s: float
	) -> Dictionary:
	var axis := approach_axis.normalized()
	var right := deck_right.normalized()
	var normal := deck_normal.normalized()
	if axis.length_squared() < 0.5 or right.length_squared() < 0.5 \
			or normal.length_squared() < 0.5:
		return {"valid": false, "reason": "invalid_wire_frame"}
	var relative_position := sensor_position - wire_position
	var relative_velocity := sensor_velocity - wire_velocity
	var along_m := relative_position.dot(axis)
	var along_speed_mps := relative_velocity.dot(axis)
	if absf(along_speed_mps) < MIN_AXIS_SPEED_MPS:
		return {
			"valid": false,
			"reason": "no_wire_closure",
			"along_m": along_m,
			"along_speed_mps": along_speed_mps,
		}
	var time_s := -along_m / along_speed_mps
	if time_s < 0.0:
		return {
			"valid": false,
			"reason": "wire_crossing_behind",
			"time_s": time_s,
			"along_m": along_m,
			"along_speed_mps": along_speed_mps,
		}
	if time_s > maxf(max_time_s, 0.0):
		return {
			"valid": false,
			"reason": "wire_crossing_beyond_horizon",
			"time_s": time_s,
			"along_m": along_m,
			"along_speed_mps": along_speed_mps,
		}
	var sensor_at_crossing := sensor_position + sensor_velocity * time_s
	var wire_at_crossing := wire_position + wire_velocity * time_s
	var miss := sensor_at_crossing - wire_at_crossing
	return {
		"valid": true,
		"time_s": time_s,
		"world_position": sensor_at_crossing,
		"wire_world_position": wire_at_crossing,
		"vertical_m": miss.dot(normal),
		"lateral_m": miss.dot(right),
		"along_m": miss.dot(axis),
		"along_speed_mps": along_speed_mps,
	}
