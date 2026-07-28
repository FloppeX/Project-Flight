extends Node3D

## Headless, deterministic batch evaluator for AIPilot's coordinated-turn controller.
## Input:  user://turn_gym_batch.json
## Output: user://turn_gym_result.json

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")
const INPUT_PATH := "user://turn_gym_batch.json"
const OUTPUT_PATH := "user://turn_gym_result.json"
const GRAVITY_MPS2 := 9.80665

const DEFAULT_GAINS := {
	"load_kp": 0.74211577,
	"load_ki": 0.32882861,
	"vertical_accel_gain": 5.0,
	"vertical_accel_damping": 5.0,
	"pitch_rate_damping": 0.105681,
	"aoa_soft_deg": 18.16582181,
	"aoa_hard_deg": 21.42927714,
	"aoa_relief_gain": 0.0609993,
	"sideslip_kp": 4.0,
	"sideslip_kd": 0.25,
	"max_load_g": 4.5,
}

const DEFAULT_CASES := [
	{"name": "left_corner", "bank_deg": -72.0, "speed_mps": 82.0, "duration_s": 8.0},
	{"name": "right_corner", "bank_deg": 72.0, "speed_mps": 82.0, "duration_s": 8.0},
	{"name": "left_fast", "bank_deg": -72.0, "speed_mps": 105.0, "duration_s": 8.0},
	{"name": "right_slow", "bank_deg": 72.0, "speed_mps": 65.0, "duration_s": 8.0},
]

var _trials: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var batch: Dictionary = _read_batch()
	var candidates_value: Variant = batch.get("candidates", [])
	var candidates: Array = candidates_value as Array if candidates_value is Array else []
	if candidates.is_empty():
		candidates = [{"id": "baseline", "gains": DEFAULT_GAINS.duplicate(true)}]
	var cases_value: Variant = batch.get("cases", DEFAULT_CASES)
	var cases: Array = cases_value as Array if cases_value is Array else DEFAULT_CASES.duplicate(true)
	var warmup_s: float = clampf(float(batch.get("warmup_s", 1.5)), 0.25, 5.0)

	for candidate_index in range(candidates.size()):
		var candidate_value: Variant = candidates[candidate_index]
		var candidate: Dictionary = candidate_value as Dictionary if candidate_value is Dictionary else {}
		for case_index in range(cases.size()):
			var case_value: Variant = cases[case_index]
			var turn_case: Dictionary = case_value as Dictionary if case_value is Dictionary else {}
			_spawn_trial(candidate, candidate_index, turn_case, case_index, warmup_s)

	# Modules are ready synchronously when each aircraft is added. The pilots have already been
	# put under exclusive gym control; these frames only let engines and retracting gear settle.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var max_duration_s: float = 0.0
	for trial in _trials:
		max_duration_s = maxf(max_duration_s, float(trial.get("duration_s", 0.0)))
	var elapsed_s := 0.0
	while elapsed_s < max_duration_s:
		var delta_s: float = 1.0 / float(Engine.physics_ticks_per_second)
		for trial in _trials:
			if elapsed_s <= float(trial.get("duration_s", 0.0)):
				_command_trial(trial, delta_s, elapsed_s)
		await get_tree().physics_frame
		elapsed_s += delta_s
		for trial in _trials:
			if elapsed_s <= float(trial.get("duration_s", 0.0)) + delta_s:
				_sample_trial(trial, delta_s, elapsed_s)

	var output := {
		"schema_version": 1,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"candidate_results": _build_candidate_results(candidates),
	}
	_write_json(OUTPUT_PATH, output)
	print("TURN_GYM_COMPLETE candidates=%d trials=%d output=%s" % [
		candidates.size(), _trials.size(), OUTPUT_PATH,
	])
	get_tree().quit(0)


func _spawn_trial(
	candidate: Dictionary,
	candidate_index: int,
	turn_case: Dictionary,
	case_index: int,
	warmup_s: float
) -> void:
	var instance: Node = AIRCRAFT_SCENE.instantiate()
	var aircraft := instance as RigidBody3D
	if aircraft == null:
		push_error("[TurnGym] Aircraft_5 did not instantiate as RigidBody3D")
		return
	aircraft.name = "TurnGym_C%d_K%d" % [candidate_index, case_index]
	add_child(aircraft)

	var speed_mps: float = clampf(float(turn_case.get("speed_mps", 82.0)), 45.0, 180.0)
	var spawn := Vector3(float(candidate_index) * 6000.0, 2400.0, float(case_index) * 6000.0)
	aircraft.global_transform = Transform3D(Basis.IDENTITY, spawn)
	# This project's aircraft scenes use Basis.z as the nose/forward axis.
	aircraft.linear_velocity = Vector3.BACK * speed_mps \
		+ Vector3.UP * float(turn_case.get("initial_vertical_speed_mps", 0.0))
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.freeze = false
	aircraft.sleeping = false

	var candidate_gains_value: Variant = candidate.get("gains", {})
	var gains: Dictionary = DEFAULT_GAINS.duplicate(true)
	if candidate_gains_value is Dictionary:
		gains.merge(candidate_gains_value as Dictionary, true)
	var duration_s: float = clampf(float(turn_case.get("duration_s", 8.0)), warmup_s + 1.0, 30.0)
	var trial := {
		"candidate_id": str(candidate.get("id", candidate_index)),
		"candidate_index": candidate_index,
		"case_name": str(turn_case.get("name", case_index)),
		"case_index": case_index,
		"aircraft": aircraft,
		"pilot": aircraft.find_child("AIPilot", true, false),
		"gains": gains,
		# The production pilot can use transient overbanked roll-onto maneuvers.
		# Keep the gym capable of exercising the same signed lift geometry.
		"target_bank_rad": deg_to_rad(clampf(float(turn_case.get("bank_deg", 72.0)), -179.0, 179.0)),
		"climb_coupled_overbank": bool(turn_case.get("climb_coupled_overbank", false)),
		"overbank_max_rad": deg_to_rad(clampf(float(turn_case.get("overbank_max_deg", 120.0)), 1.0, 179.0)),
		"overbank_start_mps": maxf(float(turn_case.get("overbank_start_mps", 2.0)), 0.0),
		"overbank_full_mps": maxf(float(turn_case.get("overbank_full_mps", 20.0)), 1.0),
		"altitude_coupled_overbank": bool(turn_case.get("altitude_coupled_overbank", false)),
		"overbank_altitude_start_m": maxf(float(turn_case.get("overbank_altitude_start_m", 30.0)), 0.0),
		"overbank_altitude_full_m": maxf(float(turn_case.get("overbank_altitude_full_m", 180.0)), 1.0),
		"overbank_descent_release_mps": maxf(float(turn_case.get("overbank_descent_release_mps", 4.0)), 0.5),
		"desired_vertical_speed_mps": float(turn_case.get("vertical_speed_mps", 0.0)),
		"initial_speed_mps": speed_mps,
		"duration_s": duration_s,
		"warmup_s": warmup_s,
		"start_altitude_m": spawn.y,
		"previous_heading_rad": 0.0,
		"unwrapped_heading_rad": 0.0,
		"previous_velocity": aircraft.linear_velocity,
		"previous_inputs": Vector3.ZERO,
		"samples": 0,
		"sum_bank_error_sq": 0.0,
		"sum_vertical_speed_sq": 0.0,
		"sum_sideslip_sq": 0.0,
		"max_abs_sideslip": 0.0,
		"sum_load_error_sq": 0.0,
		"sum_aoa_excess_sq": 0.0,
		"max_abs_aoa_deg": 0.0,
		"sum_stall_severity": 0.0,
		"max_stall_severity": 0.0,
		"sum_control_delta": 0.0,
		"control_saturation_samples": 0,
		"min_speed_mps": speed_mps,
		"max_abs_altitude_error_m": 0.0,
		"invalid": false,
		"last_controls": {},
	}
	_trials.append(trial)
	_prepare_trial(trial)


func _prepare_trial(trial: Dictionary) -> void:
	var aircraft: RigidBody3D = trial.get("aircraft") as RigidBody3D
	var pilot: AIPilot = trial.get("pilot") as AIPilot
	if aircraft == null or pilot == null:
		trial["invalid"] = true
		return
	pilot.set_process(false)
	pilot.set_physics_process(false)
	pilot.debug_enabled = false
	pilot.verbose_debug_enabled = false
	pilot.navigation_auto_rudder_enabled = false
	var gains: Dictionary = trial.get("gains", {})
	pilot.coordinated_turn_load_kp = float(gains.get("load_kp", DEFAULT_GAINS.load_kp))
	pilot.coordinated_turn_load_ki = float(gains.get("load_ki", DEFAULT_GAINS.load_ki))
	pilot.coordinated_turn_vertical_accel_gain = float(gains.get("vertical_accel_gain", DEFAULT_GAINS.vertical_accel_gain))
	pilot.coordinated_turn_vertical_accel_damping = float(
		gains.get("vertical_accel_damping", DEFAULT_GAINS.vertical_accel_damping)
	)
	pilot.coordinated_turn_pitch_rate_damping = float(gains.get("pitch_rate_damping", DEFAULT_GAINS.pitch_rate_damping))
	pilot.coordinated_turn_aoa_soft_deg = float(gains.get("aoa_soft_deg", DEFAULT_GAINS.aoa_soft_deg))
	pilot.coordinated_turn_aoa_hard_deg = maxf(
		float(gains.get("aoa_hard_deg", DEFAULT_GAINS.aoa_hard_deg)),
		pilot.coordinated_turn_aoa_soft_deg + 1.0
	)
	pilot.coordinated_turn_aoa_relief_gain = float(gains.get("aoa_relief_gain", DEFAULT_GAINS.aoa_relief_gain))
	pilot.coordinated_turn_sideslip_kp = float(gains.get("sideslip_kp", DEFAULT_GAINS.sideslip_kp))
	pilot.coordinated_turn_sideslip_kd = float(gains.get("sideslip_kd", DEFAULT_GAINS.sideslip_kd))
	pilot.reset_coordinated_turn_test_state()
	var gear: Node = aircraft.find_child("ControlLandingGear", true, false)
	if gear != null and gear.has_method("stow_gear"):
		gear.call("stow_gear")
	trial["previous_heading_rad"] = _velocity_heading(aircraft.linear_velocity)
	trial["previous_velocity"] = aircraft.linear_velocity


func _command_trial(trial: Dictionary, delta_s: float, elapsed_s: float) -> void:
	if bool(trial.get("invalid", false)):
		return
	var pilot: AIPilot = trial.get("pilot") as AIPilot
	var aircraft: RigidBody3D = trial.get("aircraft") as RigidBody3D
	if pilot == null or aircraft == null:
		trial["invalid"] = true
		return
	var target_bank_rad: float = float(trial.get("target_bank_rad", 0.0))
	if bool(trial.get("climb_coupled_overbank", false)):
		var bank_sign: float = signf(target_bank_rad)
		if absf(bank_sign) < 0.01:
			bank_sign = 1.0
		var overbank_start_mps: float = float(trial.get("overbank_start_mps", 2.0))
		var overbank_full_mps: float = maxf(
			float(trial.get("overbank_full_mps", 20.0)),
			overbank_start_mps + 1.0
		)
		var overbank_t: float = clampf(
			(maxf(aircraft.linear_velocity.y, 0.0) - overbank_start_mps)
				/ (overbank_full_mps - overbank_start_mps),
			0.0,
			1.0
		)
		if bool(trial.get("altitude_coupled_overbank", false)):
			var altitude_start_m: float = float(trial.get("overbank_altitude_start_m", 30.0))
			var altitude_full_m: float = maxf(
				float(trial.get("overbank_altitude_full_m", 180.0)),
				altitude_start_m + 1.0
			)
			var excess_altitude_m: float = maxf(
				aircraft.global_position.y - float(trial.get("start_altitude_m", aircraft.global_position.y)),
				0.0
			)
			var altitude_t: float = clampf(
				(excess_altitude_m - altitude_start_m) / (altitude_full_m - altitude_start_m),
				0.0,
				1.0
			)
			var descent_release_mps: float = float(trial.get("overbank_descent_release_mps", 4.0))
			var descent_release_t: float = clampf(
				(aircraft.linear_velocity.y + descent_release_mps) / descent_release_mps,
				0.0,
				1.0
			)
			overbank_t = maxf(overbank_t, altitude_t * descent_release_t)
		target_bank_rad = bank_sign * lerpf(
			absf(target_bank_rad),
			absf(float(trial.get("overbank_max_rad", deg_to_rad(120.0)))),
			overbank_t
		)
	# Ease the first half-second into the bank. It removes spawn transients without hiding
	# controller settling behavior, which is still scored after the warm-up window.
	var entry_t: float = clampf(elapsed_s / 0.5, 0.0, 1.0)
	var controls: Dictionary = pilot.run_coordinated_turn_test_step(
		delta_s,
		target_bank_rad * entry_t,
		float(trial.get("desired_vertical_speed_mps", 0.0)),
		float((trial.get("gains", {}) as Dictionary).get("max_load_g", DEFAULT_GAINS.max_load_g))
	)
	trial["last_controls"] = controls


func _sample_trial(trial: Dictionary, _delta_s: float, elapsed_s: float) -> void:
	if bool(trial.get("invalid", false)) or elapsed_s < float(trial.get("warmup_s", 0.0)):
		return
	var aircraft: RigidBody3D = trial.get("aircraft") as RigidBody3D
	var pilot: AIPilot = trial.get("pilot") as AIPilot
	if aircraft == null or pilot == null:
		trial["invalid"] = true
		return
	var velocity: Vector3 = aircraft.linear_velocity
	if not velocity.is_finite() or not aircraft.global_position.is_finite():
		trial["invalid"] = true
		return
	var speed_mps: float = velocity.length()
	var heading_rad: float = _velocity_heading(velocity)
	var previous_heading_rad: float = float(trial.get("previous_heading_rad", heading_rad))
	trial["unwrapped_heading_rad"] = float(trial.get("unwrapped_heading_rad", 0.0)) \
		+ _normalize_angle(heading_rad - previous_heading_rad)
	trial["previous_heading_rad"] = heading_rad

	var controls: Dictionary = trial.get("last_controls", {})
	var bank_error_deg: float = float(controls.get("bank_error_deg", 0.0))
	var sideslip: float = float(controls.get("sideslip", 0.0))
	var load_error_g: float = float(controls.get("target_g", 1.0)) \
		- float(controls.get("effective_measured_g", controls.get("measured_g", 1.0)))
	var aoa_deg: float = float(controls.get("aoa_deg", 0.0))
	var soft_aoa_deg: float = float((trial.get("gains", {}) as Dictionary).get("aoa_soft_deg", DEFAULT_GAINS.aoa_soft_deg))
	var aoa_excess_deg: float = maxf(absf(aoa_deg) - soft_aoa_deg, 0.0)
	var input_vector := Vector3(
		float(controls.get("roll", 0.0)),
		float(controls.get("pitch", 0.0)),
		float(controls.get("yaw", 0.0))
	)
	var previous_inputs: Vector3 = trial.get("previous_inputs", Vector3.ZERO)
	var simple_aero: Node = aircraft.find_child("SimpleAero", true, false)
	var stall_severity: float = 0.0
	if simple_aero != null and simple_aero.has_method("get_stall_severity"):
		stall_severity = float(simple_aero.call("get_stall_severity"))

	trial["samples"] = int(trial.get("samples", 0)) + 1
	trial["sum_bank_error_sq"] = float(trial.get("sum_bank_error_sq", 0.0)) + bank_error_deg * bank_error_deg
	trial["sum_vertical_speed_sq"] = float(trial.get("sum_vertical_speed_sq", 0.0)) + velocity.y * velocity.y
	trial["sum_sideslip_sq"] = float(trial.get("sum_sideslip_sq", 0.0)) + sideslip * sideslip
	trial["max_abs_sideslip"] = maxf(float(trial.get("max_abs_sideslip", 0.0)), absf(sideslip))
	trial["sum_load_error_sq"] = float(trial.get("sum_load_error_sq", 0.0)) + load_error_g * load_error_g
	trial["sum_aoa_excess_sq"] = float(trial.get("sum_aoa_excess_sq", 0.0)) + aoa_excess_deg * aoa_excess_deg
	trial["max_abs_aoa_deg"] = maxf(float(trial.get("max_abs_aoa_deg", 0.0)), absf(aoa_deg))
	trial["sum_stall_severity"] = float(trial.get("sum_stall_severity", 0.0)) + stall_severity
	trial["max_stall_severity"] = maxf(float(trial.get("max_stall_severity", 0.0)), stall_severity)
	trial["sum_control_delta"] = float(trial.get("sum_control_delta", 0.0)) + input_vector.distance_to(previous_inputs)
	trial["previous_inputs"] = input_vector
	if absf(input_vector.y) >= 0.98 or absf(input_vector.z) >= 0.98:
		trial["control_saturation_samples"] = int(trial.get("control_saturation_samples", 0)) + 1
	trial["min_speed_mps"] = minf(float(trial.get("min_speed_mps", speed_mps)), speed_mps)
	var altitude_error_m: float = aircraft.global_position.y - float(trial.get("start_altitude_m", aircraft.global_position.y))
	trial["max_abs_altitude_error_m"] = maxf(float(trial.get("max_abs_altitude_error_m", 0.0)), absf(altitude_error_m))
	trial["final_altitude_error_m"] = altitude_error_m
	trial["final_speed_mps"] = speed_mps
	# Keep a sparse diagnostic trace alongside the aggregate fitness. This makes failures such
	# as trading all airspeed for altitude diagnosable without changing the production pilot or
	# flooding the Godot log with per-frame telemetry.
	var trace_second: int = floori(elapsed_s)
	if trace_second > int(trial.get("last_trace_second", -1)):
		trial["last_trace_second"] = trace_second
		var trace: Array = trial.get("trace", [])
		trace.append({
			"time_s": snappedf(elapsed_s, 0.01),
			"bank_deg": snappedf(float(controls.get("bank_deg", 0.0)), 0.01),
			"target_bank_deg": snappedf(float(controls.get("target_bank_deg", 0.0)), 0.01),
			"pitch": snappedf(float(controls.get("pitch", 0.0)), 0.001),
			"yaw": snappedf(float(controls.get("yaw", 0.0)), 0.001),
			"target_g": snappedf(float(controls.get("target_g", 1.0)), 0.01),
			"measured_g": snappedf(float(controls.get("measured_g", 1.0)), 0.01),
			"effective_measured_g": snappedf(float(controls.get("effective_measured_g", 1.0)), 0.01),
			"vertical_accel_mps2": snappedf(float(controls.get("vertical_accel_mps2", 0.0)), 0.01),
			"vertical_lift_fraction": snappedf(float(controls.get("vertical_lift_fraction", 0.0)), 0.001),
			"aoa_deg": snappedf(aoa_deg, 0.01),
			"sideslip": snappedf(sideslip, 0.001),
			"vertical_speed_mps": snappedf(velocity.y, 0.01),
			"altitude_error_m": snappedf(altitude_error_m, 0.01),
			"speed_mps": snappedf(speed_mps, 0.01),
		})
		trial["trace"] = trace


func _build_candidate_results(candidates: Array) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for candidate_index in range(candidates.size()):
		var case_results: Array[Dictionary] = []
		var fitness_sum := 0.0
		var valid_cases := 0
		for trial in _trials:
			if int(trial.get("candidate_index", -1)) != candidate_index:
				continue
			var case_result: Dictionary = _score_trial(trial)
			case_results.append(case_result)
			if not bool(case_result.get("invalid", true)):
				fitness_sum += float(case_result.get("fitness", -1000.0))
				valid_cases += 1
		var candidate_value: Variant = candidates[candidate_index]
		var candidate: Dictionary = candidate_value as Dictionary if candidate_value is Dictionary else {}
		results.append({
			"id": str(candidate.get("id", candidate_index)),
			"gains": candidate.get("gains", {}),
			"fitness": fitness_sum / float(valid_cases) if valid_cases > 0 else -1000.0,
			"valid_cases": valid_cases,
			"case_results": case_results,
		})
	return results


func _score_trial(trial: Dictionary) -> Dictionary:
	var samples: int = int(trial.get("samples", 0))
	if bool(trial.get("invalid", false)) or samples <= 0:
		return {
			"name": str(trial.get("case_name", "unknown")),
			"fitness": -1000.0,
			"invalid": true,
		}
	var inv_n := 1.0 / float(samples)
	var scored_duration_s: float = maxf(
		float(trial.get("duration_s", 0.0)) - float(trial.get("warmup_s", 0.0)),
		0.1
	)
	var heading_change_deg: float = absf(rad_to_deg(float(trial.get("unwrapped_heading_rad", 0.0))))
	var actual_turn_rate_deg_s: float = heading_change_deg / scored_duration_s
	var target_bank_rad: float = absf(float(trial.get("target_bank_rad", 0.0)))
	var initial_speed_mps: float = float(trial.get("initial_speed_mps", 82.0))
	var ideal_turn_rate_deg_s: float = rad_to_deg(GRAVITY_MPS2 * tan(target_bank_rad) / maxf(initial_speed_mps, 1.0))
	var turn_effectiveness: float = clampf(actual_turn_rate_deg_s / maxf(ideal_turn_rate_deg_s, 1.0), 0.0, 1.35)
	var bank_error_rms_deg: float = sqrt(float(trial.get("sum_bank_error_sq", 0.0)) * inv_n)
	var vertical_speed_rms_mps: float = sqrt(float(trial.get("sum_vertical_speed_sq", 0.0)) * inv_n)
	var sideslip_rms: float = sqrt(float(trial.get("sum_sideslip_sq", 0.0)) * inv_n)
	var load_error_rms_g: float = sqrt(float(trial.get("sum_load_error_sq", 0.0)) * inv_n)
	var aoa_excess_rms_deg: float = sqrt(float(trial.get("sum_aoa_excess_sq", 0.0)) * inv_n)
	var stall_mean: float = float(trial.get("sum_stall_severity", 0.0)) * inv_n
	var saturation_fraction: float = float(trial.get("control_saturation_samples", 0)) * inv_n
	var control_delta_mean: float = float(trial.get("sum_control_delta", 0.0)) * inv_n
	var final_altitude_error_m: float = absf(float(trial.get("final_altitude_error_m", 0.0)))
	var speed_retained: float = float(trial.get("final_speed_mps", initial_speed_mps)) / maxf(initial_speed_mps, 1.0)

	# Turn rate is the dominant reward. Coordination, altitude, stall, and energy losses only
	# distinguish controllers that actually turn; they cannot make wings-level flight look good.
	var fitness: float = 140.0 * turn_effectiveness \
		- 0.75 * bank_error_rms_deg \
		- 1.4 * vertical_speed_rms_mps \
		- 0.025 * final_altitude_error_m \
		- 95.0 * sideslip_rms \
		- 22.0 * load_error_rms_g \
		- 3.5 * aoa_excess_rms_deg \
		- 120.0 * stall_mean \
		- 18.0 * saturation_fraction \
		- 7.0 * control_delta_mean \
		- 90.0 * maxf(0.72 - speed_retained, 0.0)
	return {
		"name": str(trial.get("case_name", "unknown")),
		"fitness": fitness,
		"invalid": false,
		"turn_rate_deg_s": actual_turn_rate_deg_s,
		"ideal_turn_rate_deg_s": ideal_turn_rate_deg_s,
		"turn_effectiveness": turn_effectiveness,
		"bank_error_rms_deg": bank_error_rms_deg,
		"vertical_speed_rms_mps": vertical_speed_rms_mps,
		"final_altitude_error_m": float(trial.get("final_altitude_error_m", 0.0)),
		"max_abs_altitude_error_m": float(trial.get("max_abs_altitude_error_m", 0.0)),
		"sideslip_rms": sideslip_rms,
		"max_abs_sideslip": float(trial.get("max_abs_sideslip", 0.0)),
		"load_error_rms_g": load_error_rms_g,
		"max_abs_aoa_deg": float(trial.get("max_abs_aoa_deg", 0.0)),
		"stall_mean": stall_mean,
		"max_stall_severity": float(trial.get("max_stall_severity", 0.0)),
		"final_speed_mps": float(trial.get("final_speed_mps", initial_speed_mps)),
		"min_speed_mps": float(trial.get("min_speed_mps", initial_speed_mps)),
		"saturation_fraction": saturation_fraction,
		"trace": trial.get("trace", []),
	}


func _read_batch() -> Dictionary:
	if not FileAccess.file_exists(INPUT_PATH):
		return {}
	var file := FileAccess.open(INPUT_PATH, FileAccess.READ)
	if file == null:
		push_error("[TurnGym] Cannot open %s" % INPUT_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[TurnGym] Cannot write %s" % path)
		return
	file.store_string(JSON.stringify(value, "\t"))


func _velocity_heading(velocity: Vector3) -> float:
	if Vector2(velocity.x, velocity.z).length_squared() < 0.01:
		return 0.0
	return atan2(velocity.x, velocity.z)


func _normalize_angle(angle: float) -> float:
	return wrapf(angle + PI, 0.0, TAU) - PI
