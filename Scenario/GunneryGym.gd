extends Node3D

## Deterministic, headless batch evaluator for air-to-air tracking and gunnery.
## Input:  user://gunnery_gym_batch.json
## Output: user://gunnery_gym_result.json

const SHOOTER_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")
const INPUT_PATH := "user://gunnery_gym_batch.json"
const OUTPUT_PATH := "user://gunnery_gym_result.json"

const DEFAULT_GAINS := {
	"turn_rate_heading_gain": 0.8,
	"turn_rate_los_feedforward": 1.0,
	"turn_rate_limit_deg_s": 40.0,
	"los_rate_filter_hz": 4.0,
	"bank_response_hz": 0.0,
	"precision_direct_pitch_gain": 26.0,
	"precision_direct_yaw_gain": 14.0,
	"precision_pid_scale": 1.0,
	"precision_entry_deg": 35.0,
	"precision_full_deg": 1.5,
	"precision_axis_authority_power": 1.0,
}

const DEFAULT_CASES := [
	{"name": "tail_chase", "path": "straight", "target_offset": [0.0, 0.0, 520.0], "target_velocity": [0.0, 0.0, 78.0], "duration_s": 16.0},
	{"name": "crossing_left", "path": "straight", "target_offset": [360.0, 25.0, 560.0], "target_velocity": [-62.0, 0.0, 48.0], "duration_s": 18.0},
	{"name": "gentle_left", "path": "circle", "target_offset": [0.0, 0.0, 580.0], "target_speed_mps": 84.0, "turn_radius_m": 480.0, "turn_sign": 1.0, "duration_s": 18.0},
	{"name": "hard_left", "path": "circle", "target_offset": [0.0, 0.0, 560.0], "target_speed_mps": 80.0, "turn_radius_m": 220.0, "turn_sign": 1.0, "duration_s": 20.0},
	{"name": "hard_right", "path": "circle", "target_offset": [0.0, -20.0, 560.0], "target_speed_mps": 80.0, "turn_radius_m": 220.0, "turn_sign": -1.0, "duration_s": 20.0},
]

var _trials: Array[Dictionary] = []
var _case_results_by_candidate: Array[Array] = []


func _ready() -> void:
	seed(20260726)
	call_deferred("_run")


func _run() -> void:
	var batch := _read_batch()
	var candidates_value: Variant = batch.get("candidates", [])
	var candidates: Array = candidates_value as Array if candidates_value is Array else []
	if candidates.is_empty():
		candidates = [{"id": "baseline", "gains": DEFAULT_GAINS.duplicate(true)}]
	var cases_value: Variant = batch.get("cases", DEFAULT_CASES)
	var cases: Array = cases_value as Array if cases_value is Array else DEFAULT_CASES.duplicate(true)
	var warmup_s := clampf(float(batch.get("warmup_s", 1.0)), 0.25, 4.0)
	var drain_s := clampf(float(batch.get("drain_s", 3.0)), 0.5, 8.0)

	# Keep one real shooter per candidate and reuse it across cases. Aircraft_5 is a
	# large production scene; multiplying it by candidates * cases made a generation
	# needlessly expensive and did not improve isolation because arenas are separated.
	for candidate_index in range(candidates.size()):
		var candidate_value: Variant = candidates[candidate_index]
		var candidate: Dictionary = candidate_value as Dictionary if candidate_value is Dictionary else {}
		var first_case_value: Variant = cases[0] if not cases.is_empty() else {}
		var first_case: Dictionary = first_case_value as Dictionary if first_case_value is Dictionary else {}
		_spawn_trial(candidate, candidate_index, first_case, 0, warmup_s)
		_case_results_by_candidate.append([])

	await get_tree().physics_frame
	await get_tree().physics_frame
	for trial in _trials:
		_finalize_trial_setup(trial)

	var delta_s := 1.0 / float(Engine.physics_ticks_per_second)
	for case_index in range(cases.size()):
		var case_value: Variant = cases[case_index]
		var gun_case: Dictionary = case_value as Dictionary if case_value is Dictionary else {}
		for trial in _trials:
			_reset_trial_for_case(trial, gun_case, case_index, warmup_s)
		await get_tree().physics_frame
		var case_duration_s := clampf(float(gun_case.get("duration_s", 18.0)), warmup_s + 2.0, 35.0)
		var elapsed_s := 0.0
		while elapsed_s < case_duration_s + drain_s:
			for trial in _trials:
				_update_target(trial, elapsed_s)
				if elapsed_s >= case_duration_s:
					_stop_trial_fire(trial)
			await get_tree().physics_frame
			elapsed_s += delta_s
			if elapsed_s <= case_duration_s:
				for trial in _trials:
					_sample_trial(trial, delta_s, elapsed_s)
		for trial in _trials:
			var candidate_index := int(trial.get("candidate_index", -1))
			if candidate_index >= 0 and candidate_index < _case_results_by_candidate.size():
				_case_results_by_candidate[candidate_index].append(_score_trial(trial))

	var output := {
		"schema_version": 1,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"candidate_results": _build_candidate_results(candidates),
	}
	_write_json(OUTPUT_PATH, output)
	print("GUNNERY_GYM_COMPLETE candidates=%d trials=%d output=%s" % [
		candidates.size(), _trials.size(), OUTPUT_PATH,
	])
	get_tree().quit(0)


func _spawn_trial(candidate: Dictionary, candidate_index: int, gun_case: Dictionary, case_index: int, warmup_s: float) -> void:
	var shooter := SHOOTER_SCENE.instantiate() as RigidBody3D
	var target := _create_lightweight_target()
	if shooter == null or target == null:
		push_error("[GunneryGym] Aircraft scene did not instantiate as RigidBody3D")
		return
	var origin := Vector3(float(candidate_index) * 14000.0, 2600.0, float(case_index) * 14000.0)
	shooter.name = "GunneryShooter_C%d_K%d" % [candidate_index, case_index]
	target.name = "GunneryTarget_C%d_K%d" % [candidate_index, case_index]
	add_child(target)
	add_child(shooter)
	_configure_target(target)
	_configure_shooter(shooter)

	var shooter_speed := clampf(float(gun_case.get("shooter_speed_mps", 102.0)), 55.0, 150.0)
	shooter.global_transform = Transform3D(_basis_from_forward(Vector3.BACK), origin)
	shooter.linear_velocity = Vector3.BACK * shooter_speed
	shooter.angular_velocity = Vector3.ZERO
	shooter.freeze = false
	shooter.sleeping = false

	var offset := _array_to_vector3(gun_case.get("target_offset", [0.0, 0.0, 550.0]))
	var initial_target_pos := origin + offset
	var path := str(gun_case.get("path", "straight"))
	var target_velocity := _array_to_vector3(gun_case.get("target_velocity", [0.0, 0.0, 80.0]))
	var circle_center := initial_target_pos
	var circle_phase := 0.0
	var circle_rate := 0.0
	if path == "circle":
		var radius := maxf(float(gun_case.get("turn_radius_m", 300.0)), 80.0)
		var turn_sign := signf(float(gun_case.get("turn_sign", 1.0)))
		if turn_sign == 0.0:
			turn_sign = 1.0
		var target_speed := maxf(float(gun_case.get("target_speed_mps", 80.0)), 20.0)
		circle_rate = turn_sign * target_speed / radius
		circle_phase = 0.0 if turn_sign > 0.0 else PI
		circle_center = initial_target_pos + Vector3(-turn_sign * radius, 0.0, 0.0)
		target_velocity = Vector3.BACK * target_speed
	target.global_transform = Transform3D(_basis_from_forward(target_velocity), initial_target_pos)
	target.linear_velocity = target_velocity

	var gains := DEFAULT_GAINS.duplicate(true)
	var gains_value: Variant = candidate.get("gains", {})
	if gains_value is Dictionary:
		gains.merge(gains_value as Dictionary, true)
	var trial_id := _trials.size()
	var duration_s := clampf(float(gun_case.get("duration_s", 18.0)), warmup_s + 2.0, 35.0)
	var trial := {
		"trial_id": trial_id,
		"candidate_id": str(candidate.get("id", candidate_index)),
		"candidate_index": candidate_index,
		"case_name": str(gun_case.get("name", case_index)),
		"case_index": case_index,
		"shooter": shooter,
		"target": target,
		"pilot": shooter.find_child("AIPilot", true, false),
		"gains": gains,
		"path": path,
		"target_initial_pos": initial_target_pos,
		"target_velocity": target_velocity,
		"circle_center": circle_center,
		"circle_phase": circle_phase,
		"circle_rate": circle_rate,
		"circle_radius": maxf(float(gun_case.get("turn_radius_m", 300.0)), 80.0),
		"duration_s": duration_s,
		"warmup_s": warmup_s,
		"start_altitude_m": origin.y,
		"initial_speed_mps": shooter_speed,
		"samples": 0,
		"shots": 0,
		"reports": 0,
		"hits": 0,
		"sum_report_miss_m": 0.0,
		"best_report_miss_m": INF,
		"sum_alignment_quality": 0.0,
		"sum_ballistic_quality": 0.0,
		"valid_solution_samples": 0,
		"in_range_samples": 0,
		"sum_bank_abs_deg": 0.0,
		"sum_unnecessary_bank_deg": 0.0,
		"sum_altitude_error_abs_m": 0.0,
		"sum_control_delta": 0.0,
		"roll_reversals": 0,
		"previous_roll_input": 0.0,
		"previous_inputs": Vector3.ZERO,
		"min_speed_mps": shooter_speed,
		"max_abs_altitude_error_m": 0.0,
		"collision": false,
		"invalid": false,
		"block_reasons": {},
		"trace": [],
		"last_trace_second": -1,
	}
	_trials.append(trial)
	_apply_candidate(trial)


func _configure_target(target: RigidBody3D) -> void:
	target.add_to_group("enemies")
	target.add_to_group("ai_aircraft")
	target.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	target.freeze = true


func _reset_trial_for_case(trial: Dictionary, gun_case: Dictionary, case_index: int, warmup_s: float) -> void:
	var shooter: RigidBody3D = trial.get("shooter") as RigidBody3D
	var target: RigidBody3D = trial.get("target") as RigidBody3D
	var pilot: AIPilot = trial.get("pilot") as AIPilot
	if shooter == null or target == null or pilot == null:
		trial["invalid"] = true
		return
	var candidate_index := int(trial.get("candidate_index", 0))
	var origin := Vector3(float(candidate_index) * 14000.0, 2600.0, 0.0)
	var shooter_speed := clampf(float(gun_case.get("shooter_speed_mps", 102.0)), 55.0, 150.0)
	shooter.global_transform = Transform3D(_basis_from_forward(Vector3.BACK), origin)
	shooter.linear_velocity = Vector3.BACK * shooter_speed
	shooter.angular_velocity = Vector3.ZERO
	shooter.sleeping = false
	if "max_health" in shooter and "current_health" in shooter:
		shooter.set("current_health", shooter.get("max_health"))

	var initial_target_pos := origin + _array_to_vector3(gun_case.get("target_offset", [0.0, 0.0, 550.0]))
	var path := str(gun_case.get("path", "straight"))
	var target_velocity := _array_to_vector3(gun_case.get("target_velocity", [0.0, 0.0, 80.0]))
	var circle_center := initial_target_pos
	var circle_phase := 0.0
	var circle_rate := 0.0
	var circle_radius := maxf(float(gun_case.get("turn_radius_m", 300.0)), 80.0)
	if path == "circle":
		var turn_sign := signf(float(gun_case.get("turn_sign", 1.0)))
		if turn_sign == 0.0:
			turn_sign = 1.0
		var target_speed := maxf(float(gun_case.get("target_speed_mps", 80.0)), 20.0)
		circle_rate = turn_sign * target_speed / circle_radius
		circle_phase = 0.0 if turn_sign > 0.0 else PI
		circle_center = initial_target_pos + Vector3(-turn_sign * circle_radius, 0.0, 0.0)
		target_velocity = Vector3.BACK * target_speed
	target.global_transform = Transform3D(_basis_from_forward(target_velocity), initial_target_pos)
	target.linear_velocity = target_velocity
	target.angular_velocity = Vector3.ZERO

	trial["case_name"] = str(gun_case.get("name", case_index))
	trial["case_index"] = case_index
	trial["case_serial"] = case_index
	trial["path"] = path
	trial["target_initial_pos"] = initial_target_pos
	trial["target_velocity"] = target_velocity
	trial["circle_center"] = circle_center
	trial["circle_phase"] = circle_phase
	trial["circle_rate"] = circle_rate
	trial["circle_radius"] = circle_radius
	trial["duration_s"] = clampf(float(gun_case.get("duration_s", 18.0)), warmup_s + 2.0, 35.0)
	trial["warmup_s"] = warmup_s
	trial["start_altitude_m"] = origin.y
	trial["initial_speed_mps"] = shooter_speed
	trial["samples"] = 0
	trial["shots"] = 0
	trial["reports"] = 0
	trial["hits"] = 0
	trial["sum_report_miss_m"] = 0.0
	trial["best_report_miss_m"] = INF
	trial["sum_alignment_quality"] = 0.0
	trial["sum_ballistic_quality"] = 0.0
	trial["valid_solution_samples"] = 0
	trial["in_range_samples"] = 0
	trial["sum_bank_abs_deg"] = 0.0
	trial["sum_unnecessary_bank_deg"] = 0.0
	trial["sum_altitude_error_abs_m"] = 0.0
	trial["sum_control_delta"] = 0.0
	trial["roll_reversals"] = 0
	trial["previous_roll_input"] = 0.0
	trial["previous_inputs"] = Vector3.ZERO
	trial["min_speed_mps"] = shooter_speed
	trial["max_abs_altitude_error_m"] = 0.0
	trial["collision"] = false
	trial["invalid"] = false
	trial["block_reasons"] = {}
	trial["trace"] = []
	trial["last_trace_second"] = -1
	pilot.roll_input = 0.0
	pilot.pitch_input = 0.0
	pilot.yaw_input = 0.0
	pilot.change_state(AIPilot.State.SEARCH)
	pilot.set_target(target)
	_refresh_gun_tuning_context(trial)


func _create_lightweight_target() -> RigidBody3D:
	# AIPilot only requires an enemy RigidBody3D with a velocity. A sphere collider is
	# sufficient for real projectile ray hits and avoids loading another complete aircraft.
	var target := RigidBody3D.new()
	target.collision_layer = 513
	target.collision_mask = 513
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 4.0
	collision.shape = shape
	target.add_child(collision)
	return target


func _configure_shooter(shooter: RigidBody3D) -> void:
	shooter.set("team", 1)
	if shooter.is_in_group("aircraft"):
		shooter.remove_from_group("aircraft")
	shooter.add_to_group("friendlies")
	shooter.set_meta("carrier_transport_mode", false)
	shooter.set_meta("controls_disabled", false)
	var toggle := shooter.get_node_or_null("AIToggle")
	if toggle != null and toggle.has_method("enable_ai"):
		toggle.call("enable_ai")


func _apply_candidate(trial: Dictionary) -> void:
	var pilot: AIPilot = trial.get("pilot") as AIPilot
	var target: RigidBody3D = trial.get("target") as RigidBody3D
	if pilot == null or target == null:
		trial["invalid"] = true
		return
	var gains: Dictionary = trial.get("gains", {})
	pilot.debug_enabled = false
	pilot.verbose_debug_enabled = false
	pilot.ground_attack_enabled = false
	pilot.dogfight_enabled = true
	pilot.dogfight_smart_retarget_enabled = false
	pilot.dogfight_situational_awareness_enabled = false
	pilot.dogfight_energy_tactics_enabled = false
	pilot.dogfight_bugout_enabled = false
	pilot.dogfight_finish_kill_enabled = false
	pilot.dogfight_unrestricted_maneuvering = false
	pilot.dogfight_collision_min_sep_m = 25.0
	pilot.rtb_health_threshold = 0.0
	pilot.rtb_fuel_threshold = 0.0
	pilot.engagement_radius_from_carrier_m = 0.0
	pilot.disengage_radius_from_carrier_m = 0.0
	pilot.dogfight_max_range_m = 1800.0
	pilot.dogfight_rejoin_range_m = 1800.0
	pilot.sensor_range = 3000.0
	pilot.dogfight_turn_rate_heading_gain = float(gains.get("turn_rate_heading_gain", DEFAULT_GAINS.turn_rate_heading_gain))
	pilot.dogfight_turn_rate_los_feedforward = float(gains.get("turn_rate_los_feedforward", DEFAULT_GAINS.turn_rate_los_feedforward))
	pilot.dogfight_turn_rate_limit_deg_s = float(gains.get("turn_rate_limit_deg_s", DEFAULT_GAINS.turn_rate_limit_deg_s))
	pilot.dogfight_los_rate_filter_hz = float(gains.get("los_rate_filter_hz", DEFAULT_GAINS.los_rate_filter_hz))
	pilot.dogfight_turn_rate_bank_response_hz = float(gains.get("bank_response_hz", DEFAULT_GAINS.bank_response_hz))
	pilot.dogfight_precision_direct_pitch_gain = float(gains.get("precision_direct_pitch_gain", DEFAULT_GAINS.precision_direct_pitch_gain))
	pilot.dogfight_precision_direct_yaw_gain = float(gains.get("precision_direct_yaw_gain", DEFAULT_GAINS.precision_direct_yaw_gain))
	pilot.dogfight_precision_pid_scale = float(gains.get("precision_pid_scale", DEFAULT_GAINS.precision_pid_scale))
	pilot.dogfight_precise_aim_entry_deg = float(gains.get("precision_entry_deg", DEFAULT_GAINS.precision_entry_deg))
	pilot.dogfight_precise_aim_full_deg = minf(
		float(gains.get("precision_full_deg", DEFAULT_GAINS.precision_full_deg)),
		pilot.dogfight_precise_aim_entry_deg - 0.1
	)
	pilot.dogfight_precision_axis_authority_power = float(gains.get("precision_axis_authority_power", DEFAULT_GAINS.precision_axis_authority_power))
	pilot.change_state(AIPilot.State.SEARCH)
	pilot.set_target(target)
	var shooter: RigidBody3D = trial.get("shooter") as RigidBody3D
	var gear := shooter.find_child("ControlLandingGear", true, false) if shooter != null else null
	if gear != null and gear.has_method("stow_gear"):
		gear.call("stow_gear")


func _finalize_trial_setup(trial: Dictionary) -> void:
	if bool(trial.get("invalid", false)):
		return
	var shooter: RigidBody3D = trial.get("shooter") as RigidBody3D
	var target: RigidBody3D = trial.get("target") as RigidBody3D
	if shooter == null or target == null:
		trial["invalid"] = true
		return
	var weapons := shooter.find_child("ControlWeapons", true, false)
	if weapons != null:
		weapons.call("find_hardpoints")
		weapons.call("categorize_weapons")
		weapons.set("selected_weapon_type", "Guns")
	var guns: Array[Node] = []
	_collect_guns(shooter, guns)
	if guns.is_empty():
		trial["invalid"] = true
		return
	trial["guns"] = guns
	for gun in guns:
		gun.set("spread_angle", 0.0)
		gun.set("ammo_count", 10000)
	_refresh_gun_tuning_context(trial)


func _refresh_gun_tuning_context(trial: Dictionary) -> void:
	var target: RigidBody3D = trial.get("target") as RigidBody3D
	var guns_value: Variant = trial.get("guns", [])
	if not (guns_value is Array):
		return
	for gun_value in guns_value:
		if is_instance_valid(gun_value) and gun_value.has_method("set_tuning_context"):
			gun_value.call(
				"set_tuning_context",
				Callable(self, "_on_gun_shot"),
				Callable(self, "_on_bullet_report").bind(
					int(trial.get("trial_id", -1)),
					int(trial.get("case_serial", -1))
				),
				int(trial.get("trial_id", -1)),
				target
			)


func _update_target(trial: Dictionary, elapsed_s: float) -> void:
	var target: RigidBody3D = trial.get("target") as RigidBody3D
	if target == null or not is_instance_valid(target):
		trial["invalid"] = true
		return
	var position: Vector3
	var velocity: Vector3
	if str(trial.get("path", "straight")) == "circle":
		var phase := float(trial.get("circle_phase", 0.0)) + float(trial.get("circle_rate", 0.0)) * elapsed_s
		var radius := float(trial.get("circle_radius", 300.0))
		var center: Vector3 = trial.get("circle_center", Vector3.ZERO)
		var rate := float(trial.get("circle_rate", 0.0))
		position = center + Vector3(cos(phase) * radius, 0.0, sin(phase) * radius)
		velocity = Vector3(-sin(phase) * radius * rate, 0.0, cos(phase) * radius * rate)
	else:
		velocity = trial.get("target_velocity", Vector3.ZERO)
		position = trial.get("target_initial_pos", Vector3.ZERO) + velocity * elapsed_s
	target.global_transform = Transform3D(_basis_from_forward(velocity), position)
	target.linear_velocity = velocity
	target.angular_velocity = Vector3.ZERO


func _sample_trial(trial: Dictionary, _delta_s: float, elapsed_s: float) -> void:
	if bool(trial.get("invalid", false)) or elapsed_s < float(trial.get("warmup_s", 0.0)):
		return
	var shooter: RigidBody3D = trial.get("shooter") as RigidBody3D
	var target: RigidBody3D = trial.get("target") as RigidBody3D
	var pilot: AIPilot = trial.get("pilot") as AIPilot
	if shooter == null or target == null or pilot == null or not shooter.global_position.is_finite():
		trial["invalid"] = true
		return
	var metrics: Dictionary = pilot.get_dogfight_gunnery_metrics()
	var aim_dot := clampf(float(metrics.get("aim_dot", -1.0)), -1.0, 1.0)
	var aim_error_deg := rad_to_deg(acos(aim_dot)) if aim_dot > -0.999 else 180.0
	var alignment_quality := exp(-aim_error_deg / 4.0)
	var envelope := maxf(float(metrics.get("hit_envelope_m", 0.0)), 0.1)
	var miss_m := float(metrics.get("miss_radius_m", INF))
	var ballistic_quality := 0.0
	if is_finite(miss_m):
		ballistic_quality = 1.0 / (1.0 + pow(miss_m / envelope, 2.0))
	var reason := str(metrics.get("block_reason", "unknown"))
	var reasons: Dictionary = trial.get("block_reasons", {})
	reasons[reason] = int(reasons.get(reason, 0)) + 1
	trial["block_reasons"] = reasons
	trial["samples"] = int(trial.get("samples", 0)) + 1
	trial["sum_alignment_quality"] = float(trial.get("sum_alignment_quality", 0.0)) + alignment_quality
	trial["sum_ballistic_quality"] = float(trial.get("sum_ballistic_quality", 0.0)) + ballistic_quality
	if bool(metrics.get("fire_solution_good", false)):
		trial["valid_solution_samples"] = int(trial.get("valid_solution_samples", 0)) + 1
	if float(metrics.get("range_m", INF)) <= 900.0:
		trial["in_range_samples"] = int(trial.get("in_range_samples", 0)) + 1
	var bank_deg := rad_to_deg(atan2(shooter.global_transform.basis.x.y, shooter.global_transform.basis.y.y))
	var los_rate := absf(float(metrics.get("los_rate_deg_s", 0.0)))
	trial["sum_bank_abs_deg"] = float(trial.get("sum_bank_abs_deg", 0.0)) + absf(bank_deg)
	if aim_error_deg < 6.0 and los_rate < 5.0:
		trial["sum_unnecessary_bank_deg"] = float(trial.get("sum_unnecessary_bank_deg", 0.0)) + maxf(absf(bank_deg) - 35.0, 0.0)
	var altitude_error := shooter.global_position.y - float(trial.get("start_altitude_m", shooter.global_position.y))
	trial["sum_altitude_error_abs_m"] = float(trial.get("sum_altitude_error_abs_m", 0.0)) + absf(altitude_error)
	trial["max_abs_altitude_error_m"] = maxf(float(trial.get("max_abs_altitude_error_m", 0.0)), absf(altitude_error))
	trial["min_speed_mps"] = minf(float(trial.get("min_speed_mps", shooter.linear_velocity.length())), shooter.linear_velocity.length())
	var inputs := Vector3(pilot.roll_input, pilot.pitch_input, pilot.yaw_input)
	var previous_inputs: Vector3 = trial.get("previous_inputs", Vector3.ZERO)
	trial["sum_control_delta"] = float(trial.get("sum_control_delta", 0.0)) + inputs.distance_to(previous_inputs)
	var previous_roll := float(trial.get("previous_roll_input", 0.0))
	if absf(inputs.x) > 0.25 and absf(previous_roll) > 0.25 and signf(inputs.x) != signf(previous_roll):
		trial["roll_reversals"] = int(trial.get("roll_reversals", 0)) + 1
	trial["previous_roll_input"] = inputs.x
	trial["previous_inputs"] = inputs
	if shooter.global_position.distance_to(target.global_position) < 12.0:
		trial["collision"] = true
	var trace_second := floori(elapsed_s)
	if trace_second > int(trial.get("last_trace_second", -1)):
		trial["last_trace_second"] = trace_second
		var trace: Array = trial.get("trace", [])
		trace.append({
			"time_s": snappedf(elapsed_s, 0.01),
			"range_m": snappedf(float(metrics.get("range_m", INF)), 0.1),
			"aim_error_deg": snappedf(aim_error_deg, 0.01),
			"miss_radius_m": snappedf(miss_m, 0.01) if is_finite(miss_m) else -1.0,
			"bank_deg": snappedf(bank_deg, 0.1),
			"scheduled_bank_deg": snappedf(float(metrics.get("scheduled_bank_deg", 0.0)), 0.1),
			"target_load_g": snappedf(float(metrics.get("target_load_g", 1.0)), 0.01),
			"available_load_g": snappedf(float(metrics.get("available_load_g", 1.0)), 0.01),
			"target_aoa_deg": snappedf(float(metrics.get("target_aoa_deg", 0.0)), 0.1),
			"los_rate_deg_s": snappedf(float(metrics.get("los_rate_deg_s", 0.0)), 0.1),
			"precise_blend": snappedf(float(metrics.get("precise_aim_blend", 0.0)), 0.01),
			"block_reason": reason,
			"shots": int(trial.get("shots", 0)),
			"hits": int(trial.get("hits", 0)),
		})
		trial["trace"] = trace


func _on_gun_shot(trial_id: int, _bullet: Node) -> void:
	if trial_id >= 0 and trial_id < _trials.size():
		_trials[trial_id]["shots"] = int(_trials[trial_id].get("shots", 0)) + 1


func _on_bullet_report(report: Dictionary, trial_id: int, case_serial: int) -> void:
	if trial_id < 0 or trial_id >= _trials.size():
		return
	var trial := _trials[trial_id]
	# Late reports from the previous case are deliberately ignored after a reset.
	if int(trial.get("case_serial", -1)) != case_serial:
		return
	trial["reports"] = int(trial.get("reports", 0)) + 1
	if bool(report.get("hit_target", false)):
		trial["hits"] = int(trial.get("hits", 0)) + 1
	var miss_m := float(report.get("closest_edge_m", INF))
	if is_finite(miss_m):
		trial["sum_report_miss_m"] = float(trial.get("sum_report_miss_m", 0.0)) + miss_m
		trial["best_report_miss_m"] = minf(float(trial.get("best_report_miss_m", INF)), miss_m)


func _stop_trial_fire(trial: Dictionary) -> void:
	var guns_value: Variant = trial.get("guns", [])
	if guns_value is Array:
		for gun_value in guns_value:
			if is_instance_valid(gun_value) and gun_value.has_method("stop_firing"):
				gun_value.call("stop_firing")


func _build_candidate_results(candidates: Array) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for candidate_index in range(candidates.size()):
		var case_results: Array = _case_results_by_candidate[candidate_index] \
			if candidate_index < _case_results_by_candidate.size() else []
		var fitness_sum := 0.0
		var worst_fitness := INF
		var valid_cases := 0
		for case_value in case_results:
			var case_result: Dictionary = case_value as Dictionary if case_value is Dictionary else {}
			if not bool(case_result.get("invalid", true)):
				var case_fitness := float(case_result.get("fitness", -1000.0))
				fitness_sum += case_fitness
				worst_fitness = minf(worst_fitness, case_fitness)
				valid_cases += 1
		var candidate_value: Variant = candidates[candidate_index]
		var candidate: Dictionary = candidate_value as Dictionary if candidate_value is Dictionary else {}
		var mean_fitness := fitness_sum / float(valid_cases) if valid_cases > 0 else -1000.0
		# A small worst-case term discourages a specialist that only solves tail chases.
		var robust_fitness := mean_fitness * 0.8 + worst_fitness * 0.2 if valid_cases > 0 else -1000.0
		results.append({
			"id": str(candidate.get("id", candidate_index)),
			"gains": candidate.get("gains", {}),
			"fitness": robust_fitness,
			"mean_fitness": mean_fitness,
			"worst_fitness": worst_fitness if valid_cases > 0 else -1000.0,
			"valid_cases": valid_cases,
			"case_results": case_results,
		})
	return results


func _score_trial(trial: Dictionary) -> Dictionary:
	var samples := int(trial.get("samples", 0))
	if bool(trial.get("invalid", false)) or samples <= 0:
		return {"name": str(trial.get("case_name", "unknown")), "fitness": -1000.0, "invalid": true}
	var inv_n := 1.0 / float(samples)
	var shots := int(trial.get("shots", 0))
	var reports := int(trial.get("reports", 0))
	var hits := int(trial.get("hits", 0))
	var hit_ratio := float(hits) / float(maxi(shots, 1))
	var solution_fraction := float(trial.get("valid_solution_samples", 0)) * inv_n
	var in_range_fraction := float(trial.get("in_range_samples", 0)) * inv_n
	var alignment_quality := float(trial.get("sum_alignment_quality", 0.0)) * inv_n
	var ballistic_quality := float(trial.get("sum_ballistic_quality", 0.0)) * inv_n
	var mean_bank_deg := float(trial.get("sum_bank_abs_deg", 0.0)) * inv_n
	var unnecessary_bank_deg := float(trial.get("sum_unnecessary_bank_deg", 0.0)) * inv_n
	var mean_altitude_error_m := float(trial.get("sum_altitude_error_abs_m", 0.0)) * inv_n
	var control_delta_mean := float(trial.get("sum_control_delta", 0.0)) * inv_n
	var report_miss_mean := float(trial.get("sum_report_miss_m", 0.0)) / float(maxi(reports, 1))
	var shot_excess := maxf(float(shots - 140), 0.0)
	var speed_loss := maxf(float(trial.get("initial_speed_mps", 100.0)) - float(trial.get("min_speed_mps", 100.0)), 0.0)
	var fitness := 520.0 * minf(float(hits), 6.0) \
		+ 280.0 * hit_ratio \
		+ 170.0 * solution_fraction \
		+ 95.0 * ballistic_quality \
		+ 70.0 * alignment_quality \
		+ 20.0 * in_range_fraction \
		- 0.35 * minf(report_miss_mean, 300.0) \
		- 6.0 * unnecessary_bank_deg \
		- 0.012 * mean_altitude_error_m \
		- 1.8 * float(trial.get("roll_reversals", 0)) \
		- 9.0 * control_delta_mean \
		- 0.12 * speed_loss \
		- 0.8 * shot_excess
	if bool(trial.get("collision", false)):
		fitness -= 350.0
	return {
		"name": str(trial.get("case_name", "unknown")),
		"fitness": fitness,
		"invalid": false,
		"shots": shots,
		"reports": reports,
		"hits": hits,
		"hit_ratio": hit_ratio,
		"solution_fraction": solution_fraction,
		"in_range_fraction": in_range_fraction,
		"alignment_quality": alignment_quality,
		"ballistic_quality": ballistic_quality,
		"report_miss_mean_m": report_miss_mean,
		"best_report_miss_m": float(trial.get("best_report_miss_m", INF)),
		"mean_bank_deg": mean_bank_deg,
		"unnecessary_bank_deg": unnecessary_bank_deg,
		"mean_altitude_error_m": mean_altitude_error_m,
		"max_abs_altitude_error_m": float(trial.get("max_abs_altitude_error_m", 0.0)),
		"min_speed_mps": float(trial.get("min_speed_mps", 0.0)),
		"roll_reversals": int(trial.get("roll_reversals", 0)),
		"collision": bool(trial.get("collision", false)),
		"block_reasons": trial.get("block_reasons", {}),
		"trace": trial.get("trace", []),
	}


func _collect_guns(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child.has_method("set_tuning_context") and child.has_method("fire"):
			out.append(child)
		_collect_guns(child, out)


func _basis_from_forward(direction: Vector3) -> Basis:
	var forward := direction.normalized()
	if forward.length_squared() < 0.001:
		forward = Vector3.BACK
	var right := Vector3.UP.cross(forward).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	var up := forward.cross(right).normalized()
	return Basis(right, up, forward)


func _array_to_vector3(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _read_batch() -> Dictionary:
	if not FileAccess.file_exists(INPUT_PATH):
		return {}
	var file := FileAccess.open(INPUT_PATH, FileAccess.READ)
	if file == null:
		push_error("[GunneryGym] Cannot open %s" % INPUT_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[GunneryGym] Cannot write %s" % path)
		return
	file.store_string(JSON.stringify(value, "\t"))
