extends RefCounted

## Pilot knowledge only. This object never holds or reads a target Node.
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var turn_axis := Vector3.ZERO
var turn_rate := 0.0
var observed_at := -INF
var visible := false
var _last_glimpse_at := -INF
var _recognition_evidence_s := 0.0
var _estimate_uncertainty_m := 2.0
var _recognition_required_s := 0.0

func observe(new_position: Vector3, new_velocity: Vector3, now: float, profile: Dictionary = {}) -> void:
	# A clear ray is a glimpse, not immediate recognition. Repeated glimpses
	# accumulate evidence; a long interruption discards it. Until recognition,
	# preserve the last accepted observation rather than leaking a fresh pose.
	var glimpse_dt := now - _last_glimpse_at
	if not is_finite(glimpse_dt) or glimpse_dt > 1.0:
		_recognition_evidence_s = 0.0
	elif glimpse_dt > 0.0:
		_recognition_evidence_s += minf(glimpse_dt, 0.25)
	_last_glimpse_at = now
	_recognition_required_s = float(profile.get("recognition_s", 0.0))
	if _recognition_evidence_s + 0.0001 < _recognition_required_s:
		visible = false
		return
	var dt := now - observed_at
	var estimated_velocity := new_velocity
	if is_finite(dt) and dt > 0.001 and dt < 1.0 and not profile.is_empty():
		# No per-frame random aim jitter: errors come from lagging recognition of
		# actual changes in observed motion, and settle on a steady target.
		estimated_velocity = velocity.lerp(new_velocity,
			1.0 - exp(-dt * float(profile.motion_response_hz)))
	if is_finite(dt) and dt > 0.001 and dt < 0.5 and velocity.length() > 5.0 and new_velocity.length() > 5.0:
		var cross := velocity.normalized().cross(estimated_velocity.normalized())
		var angle := atan2(cross.length(), velocity.normalized().dot(estimated_velocity.normalized()))
		var response := 1.0 - exp(-dt * float(profile.get("turn_response_hz", 12.0)))
		turn_rate = lerpf(turn_rate, minf(angle / dt, 1.5), response)
		if cross.length_squared() > 0.00000001:
			turn_axis = cross.normalized()
	else:
		turn_axis = Vector3.ZERO
		turn_rate = 0.0
	position = new_position
	velocity = estimated_velocity
	_estimate_uncertainty_m = float(profile.get("estimate_uncertainty_m", 2.0))
	observed_at = now
	visible = true

func is_recognizing(now: float) -> bool:
	# No position/velocity is exposed by this status. A missed scan cancels the
	# grace promptly, so an unobserved assigned Node cannot sustain course hold.
	return now - _last_glimpse_at <= 0.25 \
		and _recognition_evidence_s + 0.0001 < _recognition_required_s

func sample(now: float, memory_s: float) -> Dictionary:
	if not is_finite(observed_at):
		return {}
	var age := maxf(now - observed_at, 0.0)
	# A remembered maneuver is only extrapolated briefly; uncertainty then grows
	# rather than secretly observing every subsequent reversal.
	var predict_s := minf(age, 2.0)
	var predicted_position := position + velocity * predict_s
	var predicted_velocity := velocity
	if turn_rate > 0.001 and turn_axis.length_squared() > 0.5:
		var parallel := turn_axis * velocity.dot(turn_axis)
		var perpendicular := velocity - parallel
		var angle := turn_rate * predict_s
		predicted_position = position + parallel * predict_s + perpendicular * sin(angle) / turn_rate \
			+ turn_axis.cross(perpendicular) * (1.0 - cos(angle)) / turn_rate
		predicted_velocity = velocity.rotated(turn_axis, angle)
	return {"position": predicted_position, "velocity": predicted_velocity,
		"age_s": age, "visible": visible and age <= 0.25,
		"uncertainty_m": _estimate_uncertainty_m + age * 12.0 + age * age * 5.0,
		"expired": age > memory_s, "turn_axis": turn_axis, "turn_rate": turn_rate}

func shift_origin(offset: Vector3) -> void:
	position -= offset

static func in_visual_sector(local_direction: Vector3) -> bool:
	# Broad canopy view, with blind rear and belly sectors. No proximity immunity.
	return local_direction.z > -0.65 and local_direction.y > -0.35

static func in_search_sector(local_direction: Vector3, remembered_direction: Vector3) -> bool:
	if local_direction.y <= -0.35 or remembered_direction.length_squared() < 0.5:
		return false
	var bearing := clampf(atan2(remembered_direction.x, remembered_direction.z), -deg_to_rad(150), deg_to_rad(150))
	var gaze := Vector3(sin(bearing), 0, cos(bearing))
	return local_direction.dot(gaze) > cos(deg_to_rad(35))
