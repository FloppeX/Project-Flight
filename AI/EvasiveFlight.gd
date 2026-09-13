extends RefCounted

## Bounded defensive intent. No scene nodes, target truth, or force/attitude writes.
var phase := "idle"
var remaining_s := 0.0
var cooldown_s := 0.0
var evidence_s := 0.0
var damage_age_s := INF
var direction := Vector3.ZERO
var reason := ""
var episodes := 0
var active_time_s := 0.0

func report_damage(amount: float, source: StringName) -> void:
	if amount > 0.0 and source == &"projectile":
		damage_age_s = 0.0

func reset() -> void:
	phase = "idle"
	remaining_s = 0.0
	evidence_s = 0.0
	damage_age_s = INF
	direction = Vector3.ZERO

func update(delta: float, own: Dictionary, observation: Dictionary, allowed: bool) -> Vector3:
	cooldown_s = maxf(0.0, cooldown_s - delta)
	damage_age_s += delta
	if not allowed:
		reset()
		return Vector3.ZERO
	var velocity: Vector3 = own.velocity
	var forward: Vector3 = own.forward
	var position: Vector3 = own.position
	var safe_descent: bool = own.agl > own.floor_agl + 200.0
	var low_energy: bool = velocity.length() < maxf(own.stall_speed * 1.5, float(own.get("corner_speed", 85.0)) * 0.9)
	if phase != "idle":
		remaining_s -= delta
		active_time_s += delta
		if remaining_s <= 0.0 or (phase == "break" and low_energy):
			if phase == "break":
				phase = "extend"
				remaining_s = 4.0
				direction = Vector3(velocity.x, 0, velocity.z).normalized()
				if direction.length_squared() < 0.1:
					direction = Vector3(forward.x, 0, forward.z).normalized()
			else:
				reset()
				cooldown_s = 8.0
				return Vector3.ZERO
		var request := direction * 700.0
		request.y = -70.0 if safe_descent else 0.0
		return position + request
	if cooldown_s > 0.0:
		evidence_s = 0.0
		return Vector3.ZERO
	var credible := false
	var relative := Vector3.ZERO
	if not observation.is_empty() and bool(observation.get("visible", false)) \
			and not bool(observation.get("expired", true)) and float(observation.get("age_s", INF)) <= 0.25:
		relative = Vector3(observation.position) - position
		var range_m := relative.length()
		var threat_velocity: Vector3 = observation.velocity
		# Approximate gun geometry from observed motion; not proof that guns are firing.
		credible = range_m > 80.0 and range_m < 750.0 and threat_velocity.length() > 25.0 \
			and relative.normalized().dot(forward) < 0.25 \
			and threat_velocity.normalized().dot(-relative.normalized()) > 0.97 \
			and relative.normalized().dot(threat_velocity - velocity) < -3.0
	var damaged := damage_age_s < 1.5
	evidence_s = evidence_s + delta if credible or damaged else maxf(0.0, evidence_s - delta * 3.0)
	var reaction_s := lerpf(0.8, 0.3, clampf(own.skill, 0.0, 1.0))
	if evidence_s < reaction_s:
		return Vector3.ZERO
	var flat := Vector3(velocity.x, 0, velocity.z).normalized()
	if flat.length_squared() < 0.1:
		flat = Vector3(forward.x, 0, forward.z).normalized()
	var right := Vector3(flat.z, 0, -flat.x)
	# Unknown-source damage uses own bank, never nearest-enemy truth.
	var side := -signf(float(own.bank)) if absf(float(own.bank)) > 0.1 else 1.0
	if credible and absf(relative.dot(right)) > 10.0:
		side = -signf(relative.dot(right))
	direction = (flat * 0.35 + right * side).normalized() if not low_energy else flat
	phase = "extend" if low_energy else "break"
	remaining_s = 4.0
	reason = "projectile_damage" if damaged else "observed_threat"
	damage_age_s = INF
	evidence_s = 0.0
	episodes += 1
	var request := direction * 700.0
	request.y = -70.0 if safe_descent else 0.0
	return position + request
