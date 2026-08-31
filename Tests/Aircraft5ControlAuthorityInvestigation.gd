extends Node3D

## Diagnostic only: measures the production Aircraft_5 under direct full pitch,
## roll, and yaw commands without changing authored flight-model values.

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")
const GRAVITY_MPS2 := 9.80665
const PULL_DURATION_S := 2.5
const ROLL_DURATION_S := 2.0
const YAW_DURATION_S := 2.0
const WARMUP_S := 0.35
const REPORT_PATH := "user://aircraft5_control_authority_report.json"

const BASELINE_SPEEDS: Array[float] = [55.0, 65.0, 82.0, 105.0, 127.0, 160.0, 180.0]
const PITCH_POWER_SWEEP: Array[float] = [3.75, 5.0, 6.0, 6.25, 6.5, 7.5, 10.0, 15.0]
const ROLL_POWER_SWEEP: Array[float] = [6.5, 9.0, 13.0, 18.0, 26.0]
const YAW_POWER_SWEEP: Array[float] = [1.0, 1.5, 2.0, 3.0, 4.0]

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var pull_configs: Array[Dictionary] = []
	for speed_mps in BASELINE_SPEEDS:
		pull_configs.append({
			"name": "baseline_%03d" % roundi(speed_mps),
			"speed_mps": speed_mps,
			"kind": "speed_sweep",
		})
	for pitch_power in PITCH_POWER_SWEEP:
		pull_configs.append({
			"name": "pitch_%0.2f" % pitch_power,
			"speed_mps": 82.0,
			"pitch_power": pitch_power,
			"kind": "pitch_power_sweep",
		})

	var pull_trials := await _spawn_trials(pull_configs)
	await _warm_up(pull_trials)
	var pull_results := await _run_pull_trials(pull_trials)
	await _free_trials(pull_trials)
	if pull_results.size() != pull_configs.size():
		_failures.append("Expected %d pull results, got %d" % [pull_configs.size(), pull_results.size()])

	var roll_configs: Array[Dictionary] = []
	for roll_power in ROLL_POWER_SWEEP:
		roll_configs.append({
			"name": "roll_%0.2f" % roll_power,
			"speed_mps": 82.0,
			"roll_power": roll_power,
			"kind": "roll_power_sweep",
		})
	var roll_trials := await _spawn_trials(roll_configs)
	await _warm_up(roll_trials)
	var roll_results := await _run_roll_trials(roll_trials)
	await _free_trials(roll_trials)
	if roll_results.size() != roll_configs.size():
		_failures.append("Expected %d roll results, got %d" % [roll_configs.size(), roll_results.size()])

	var yaw_configs: Array[Dictionary] = []
	for yaw_power in YAW_POWER_SWEEP:
		yaw_configs.append({
			"name": "yaw_%0.2f" % yaw_power,
			"speed_mps": 82.0,
			"yaw_power": yaw_power,
			"kind": "yaw_power_sweep",
		})
	var yaw_trials := await _spawn_trials(yaw_configs)
	await _warm_up(yaw_trials)
	var yaw_results := await _run_yaw_trials(yaw_trials)
	await _free_trials(yaw_trials)
	if yaw_results.size() != yaw_configs.size():
		_failures.append("Expected %d yaw results, got %d" % [yaw_configs.size(), yaw_results.size()])

	var report := {
		"aircraft_scene": "res://Aircraft/Aircraft_5.tscn",
		"flight_model": "advanced",
		"pull_duration_s": PULL_DURATION_S,
		"roll_duration_s": ROLL_DURATION_S,
		"yaw_duration_s": YAW_DURATION_S,
		"pull_results": pull_results,
		"roll_results": roll_results,
		"yaw_results": yaw_results,
	}
	_write_report(report)
	_print_report(pull_results, roll_results, yaw_results)

	if _failures.is_empty():
		print("[Aircraft5ControlAuthorityInvestigation] PASS pull=%d roll=%d yaw=%d output=%s" % [
			pull_results.size(),
			roll_results.size(),
			yaw_results.size(),
			REPORT_PATH,
		])
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[Aircraft5ControlAuthorityInvestigation] %s" % failure)
	get_tree().quit(1)


func _spawn_trials(configs: Array[Dictionary]) -> Array[Dictionary]:
	var trials: Array[Dictionary] = []
	for index in range(configs.size()):
		var config := configs[index]
		var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
		if aircraft == null:
			_failures.append("Aircraft_5 failed to instantiate for %s" % str(config.get("name", index)))
			continue
		aircraft.name = "ControlAuthority_%s" % str(config.get("name", index))
		# Configure the body before it enters the tree. Aircraft._ready() yields for
		# one process frame; placing it only after that yield leaves it at the origin
		# for a physics tick, where ordinary crash/ownership systems can retire it.
		aircraft.transform = Transform3D(
			Basis.IDENTITY,
			Vector3(float(index) * 4500.0, 6000.0, 0.0)
		)
		aircraft.linear_velocity = Vector3.BACK * float(config.get("speed_mps", 82.0))
		aircraft.angular_velocity = Vector3.ZERO
		aircraft.set_meta("landing_test_aircraft", true)
		aircraft.set_meta("control_authority_investigation", true)
		var ai_toggle_before_ready := aircraft.get_node_or_null("AIToggle")
		if ai_toggle_before_ready != null:
			ai_toggle_before_ready.set("ai_enabled_at_start", false)
		add_child(aircraft)
		trials.append({
			"config": config,
			"aircraft": aircraft,
			"aero": aircraft.get_node_or_null("SimpleAero") as SimpleAero,
		})

	# Aircraft and AIToggle both add player-facing groups during startup. Remove
	# those groups before allowing the first physics frame so this diagnostic
	# remains isolated from global player-aircraft consumers.
	for _startup_frame in range(2):
		await get_tree().process_frame
		for trial in trials:
			var aircraft_value: Variant = trial.get("aircraft")
			if not is_instance_valid(aircraft_value):
				continue
			var startup_aircraft := aircraft_value as RigidBody3D
			startup_aircraft.remove_from_group("aircraft")
			startup_aircraft.remove_from_group("friendlies")
			startup_aircraft.remove_from_group("ai_aircraft")
	for index in range(trials.size()):
		var trial := trials[index]
		var aircraft_value: Variant = trial.get("aircraft")
		var aero_value: Variant = trial.get("aero")
		if not is_instance_valid(aircraft_value) or not is_instance_valid(aero_value):
			_failures.append("Aircraft_5 trial lost physics nodes")
			continue
		var aircraft := aircraft_value as RigidBody3D
		var aero := aero_value as SimpleAero
		var pilot := aircraft.find_child("AIPilot", true, false)
		if pilot != null:
			pilot.set_process(false)
			pilot.set_physics_process(false)
		var controls := aircraft.find_child("ControlSteering", true, false)
		if controls != null:
			controls.set("ControlActive", false)
			controls.set_physics_process(false)
		var ai_toggle := aircraft.get_node_or_null("AIToggle")
		if ai_toggle != null and "ai_active" in ai_toggle:
			ai_toggle.set("ai_active", false)
		var engine := aircraft.get_node_or_null("Engine")
		if engine != null:
			engine.set("is_engine_working", false)
			engine.set("current_power", 0.0)
			engine.set("target_power", 0.0)
		var gear := aircraft.find_child("ControlLandingGear", true, false)
		if gear != null and gear.has_method("stow_gear"):
			gear.call("stow_gear")
		aero.airflow_feedback_enabled = false
		aero.aero_report_enabled = false
		aero.set_flight_model_override_for_testing(1)
		var config: Dictionary = trial.get("config", {})
		if config.has("pitch_power"):
			aero.pitch_power = float(config.pitch_power)
		if config.has("roll_power"):
			aero.roll_power = float(config.roll_power)
		if config.has("yaw_power"):
			aero.yaw_power = float(config.yaw_power)
		aircraft.global_transform = Transform3D(
			Basis.IDENTITY,
			Vector3(float(index) * 4500.0, 6000.0, 0.0)
		)
		PhysicsServer3D.body_set_state(
			aircraft.get_rid(),
			PhysicsServer3D.BODY_STATE_TRANSFORM,
			aircraft.global_transform
		)
		aircraft.linear_velocity = Vector3.BACK * float(config.get("speed_mps", 82.0))
		aircraft.angular_velocity = Vector3.ZERO
		aircraft.freeze = false
		aircraft.sleeping = false
		aero.pitch_input = 0.0
		aero.roll_input = 0.0
		aero.yaw_input = 0.0
	await get_tree().physics_frame
	return trials


func _warm_up(trials: Array[Dictionary]) -> void:
	var elapsed := 0.0
	while elapsed < WARMUP_S:
		for trial in trials:
			var aero := trial.get("aero") as SimpleAero
			if aero != null:
				aero.pitch_input = 0.0
				aero.roll_input = 0.0
				aero.yaw_input = 0.0
		await get_tree().physics_frame
		elapsed += _physics_delta()


func _run_pull_trials(trials: Array[Dictionary]) -> Array[Dictionary]:
	for trial in trials:
		var aircraft := trial.get("aircraft") as RigidBody3D
		var aero := trial.get("aero") as SimpleAero
		if aircraft == null or aero == null:
			continue
		trial["previous_velocity"] = aircraft.linear_velocity
		trial["peak_normal_g"] = -INF
		trial["peak_lift_ratio"] = 0.0
		trial["peak_aoa_deg"] = 0.0
		trial["peak_stall_severity"] = 0.0
		trial["peak_departure_severity"] = 0.0
		trial["peak_path_turn_rate_deg_s"] = 0.0
		trial["minimum_radius_m"] = INF
		trial["peak_pitch_rate_deg_s"] = 0.0
		trial["time_to_2g_s"] = -1.0
		trial["time_to_3g_s"] = -1.0
		trial["late_g_sum"] = 0.0
		trial["late_g_samples"] = 0
		trial["initial_pitch_authority"] = aero.get_axis_control_authority_at_speed(
			aircraft.linear_velocity.length(),
			&"pitch",
			aero.get_effective_stall_speed_mps(),
			0.0
		)
		trial["initial_pitch_limit"] = aero.get_high_speed_control_limit(
			aircraft.linear_velocity.length(),
			&"pitch"
		)
		trial["runtime_mass_kg"] = aircraft.mass
		trial["runtime_inertia"] = aircraft.inertia

	var elapsed := 0.0
	while elapsed < PULL_DURATION_S:
		for trial in trials:
			var aero := trial.get("aero") as SimpleAero
			if aero != null:
				aero.pitch_input = 1.0
				aero.roll_input = 0.0
				aero.yaw_input = 0.0
		await get_tree().physics_frame
		var delta := _physics_delta()
		elapsed += delta
		for trial in trials:
			_sample_pull_trial(trial, delta, elapsed)

	var results: Array[Dictionary] = []
	for trial in trials:
		var aircraft := trial.get("aircraft") as RigidBody3D
		var aero := trial.get("aero") as SimpleAero
		var config: Dictionary = trial.get("config", {})
		if aircraft == null or aero == null:
			continue
		var late_samples := maxi(int(trial.get("late_g_samples", 0)), 1)
		results.append({
			"name": str(config.get("name", "unknown")),
			"kind": str(config.get("kind", "unknown")),
			"initial_speed_mps": float(config.get("speed_mps", 0.0)),
			"pitch_power": aero.get_effective_pitch_power(),
			"runtime_mass_kg": float(trial.get("runtime_mass_kg", 0.0)),
			"runtime_inertia": _vector_to_array(trial.get("runtime_inertia", Vector3.ZERO)),
			"initial_pitch_authority": float(trial.get("initial_pitch_authority", 0.0)),
			"initial_pitch_limit": float(trial.get("initial_pitch_limit", 0.0)),
			"peak_normal_g": float(trial.get("peak_normal_g", 0.0)),
			"late_mean_normal_g": float(trial.get("late_g_sum", 0.0)) / float(late_samples),
			"peak_lift_ratio": float(trial.get("peak_lift_ratio", 0.0)),
			"peak_aoa_deg": float(trial.get("peak_aoa_deg", 0.0)),
			"peak_stall_severity": float(trial.get("peak_stall_severity", 0.0)),
			"peak_departure_severity": float(trial.get("peak_departure_severity", 0.0)),
			"peak_path_turn_rate_deg_s": float(trial.get("peak_path_turn_rate_deg_s", 0.0)),
			"minimum_radius_m": float(trial.get("minimum_radius_m", 0.0)),
			"peak_pitch_rate_deg_s": float(trial.get("peak_pitch_rate_deg_s", 0.0)),
			"time_to_2g_s": float(trial.get("time_to_2g_s", -1.0)),
			"time_to_3g_s": float(trial.get("time_to_3g_s", -1.0)),
			"final_speed_mps": aircraft.linear_velocity.length(),
			"final_actual_pitch_control": aero.actual_pitch_control,
		})
	return results


func _sample_pull_trial(trial: Dictionary, delta: float, elapsed: float) -> void:
	var aircraft := trial.get("aircraft") as RigidBody3D
	var aero := trial.get("aero") as SimpleAero
	if aircraft == null or aero == null:
		return
	var previous_velocity: Vector3 = trial.get("previous_velocity", aircraft.linear_velocity)
	var velocity := aircraft.linear_velocity
	var acceleration := (velocity - previous_velocity) / maxf(delta, 0.0001)
	var gravity := Vector3.DOWN * GRAVITY_MPS2 * aircraft.gravity_scale
	var local_specific_g := aircraft.global_transform.basis.orthonormalized().inverse() \
		* (acceleration - gravity) / GRAVITY_MPS2
	var normal_g := local_specific_g.y
	var path_turn_rate := 0.0
	if previous_velocity.length() > 0.1 and velocity.length() > 0.1:
		var direction_dot := clampf(previous_velocity.normalized().dot(velocity.normalized()), -1.0, 1.0)
		path_turn_rate = acos(direction_dot) / maxf(delta, 0.0001)
	var radius := velocity.length() / path_turn_rate if path_turn_rate > 0.001 else INF
	var local_pitch_rate := absf(aircraft.angular_velocity.dot(aircraft.global_transform.basis.x))
	var aoa := absf(aero.get_estimated_angle_of_attack_deg())
	var lift_ratio := aero.get_estimated_lift_ratio()

	trial["peak_normal_g"] = maxf(float(trial.get("peak_normal_g", -INF)), normal_g)
	trial["peak_lift_ratio"] = maxf(float(trial.get("peak_lift_ratio", 0.0)), lift_ratio)
	trial["peak_aoa_deg"] = maxf(float(trial.get("peak_aoa_deg", 0.0)), aoa)
	trial["peak_stall_severity"] = maxf(float(trial.get("peak_stall_severity", 0.0)), aero.get_stall_severity())
	trial["peak_departure_severity"] = maxf(float(trial.get("peak_departure_severity", 0.0)), aero.current_departure_severity)
	trial["peak_path_turn_rate_deg_s"] = maxf(
		float(trial.get("peak_path_turn_rate_deg_s", 0.0)),
		rad_to_deg(path_turn_rate)
	)
	trial["minimum_radius_m"] = minf(float(trial.get("minimum_radius_m", INF)), radius)
	trial["peak_pitch_rate_deg_s"] = maxf(
		float(trial.get("peak_pitch_rate_deg_s", 0.0)),
		rad_to_deg(local_pitch_rate)
	)
	if float(trial.get("time_to_2g_s", -1.0)) < 0.0 and normal_g >= 2.0:
		trial["time_to_2g_s"] = elapsed
	if float(trial.get("time_to_3g_s", -1.0)) < 0.0 and normal_g >= 3.0:
		trial["time_to_3g_s"] = elapsed
	if elapsed >= PULL_DURATION_S - 0.5:
		trial["late_g_sum"] = float(trial.get("late_g_sum", 0.0)) + normal_g
		trial["late_g_samples"] = int(trial.get("late_g_samples", 0)) + 1
	trial["previous_velocity"] = velocity


func _run_roll_trials(trials: Array[Dictionary]) -> Array[Dictionary]:
	for trial in trials:
		trial["peak_roll_rate_deg_s"] = 0.0
		trial["time_to_45_deg_s"] = -1.0
		trial["time_to_90_deg_s"] = -1.0
		trial["peak_actual_roll_control"] = 0.0
		var aircraft := trial.get("aircraft") as RigidBody3D
		trial["runtime_mass_kg"] = aircraft.mass if aircraft != null else 0.0

	var elapsed := 0.0
	while elapsed < ROLL_DURATION_S:
		for trial in trials:
			var aero := trial.get("aero") as SimpleAero
			if aero != null:
				aero.pitch_input = 0.0
				aero.roll_input = 1.0
				aero.yaw_input = 0.0
		await get_tree().physics_frame
		elapsed += _physics_delta()
		for trial in trials:
			_sample_roll_trial(trial, elapsed)

	var results: Array[Dictionary] = []
	for trial in trials:
		var aircraft := trial.get("aircraft") as RigidBody3D
		var aero := trial.get("aero") as SimpleAero
		var config: Dictionary = trial.get("config", {})
		if aircraft == null or aero == null:
			continue
		results.append({
			"name": str(config.get("name", "unknown")),
			"initial_speed_mps": float(config.get("speed_mps", 0.0)),
			"roll_power": aero.roll_power,
			"runtime_mass_kg": float(trial.get("runtime_mass_kg", 0.0)),
			"peak_roll_rate_deg_s": float(trial.get("peak_roll_rate_deg_s", 0.0)),
			"time_to_45_deg_s": float(trial.get("time_to_45_deg_s", -1.0)),
			"time_to_90_deg_s": float(trial.get("time_to_90_deg_s", -1.0)),
			"peak_actual_roll_control": float(trial.get("peak_actual_roll_control", 0.0)),
			"final_speed_mps": aircraft.linear_velocity.length(),
		})
	return results


func _sample_roll_trial(trial: Dictionary, elapsed: float) -> void:
	var aircraft := trial.get("aircraft") as RigidBody3D
	var aero := trial.get("aero") as SimpleAero
	if aircraft == null or aero == null:
		return
	var basis := aircraft.global_transform.basis.orthonormalized()
	var bank_deg := absf(rad_to_deg(atan2(basis.x.y, basis.y.y)))
	var roll_rate_deg_s := absf(rad_to_deg(aircraft.angular_velocity.dot(basis.z)))
	trial["peak_roll_rate_deg_s"] = maxf(float(trial.get("peak_roll_rate_deg_s", 0.0)), roll_rate_deg_s)
	trial["peak_actual_roll_control"] = maxf(
		float(trial.get("peak_actual_roll_control", 0.0)),
		absf(aero.actual_roll_control)
	)
	if float(trial.get("time_to_45_deg_s", -1.0)) < 0.0 and bank_deg >= 45.0:
		trial["time_to_45_deg_s"] = elapsed
	if float(trial.get("time_to_90_deg_s", -1.0)) < 0.0 and bank_deg >= 90.0:
		trial["time_to_90_deg_s"] = elapsed


func _run_yaw_trials(trials: Array[Dictionary]) -> Array[Dictionary]:
	for trial in trials:
		var aircraft := trial.get("aircraft") as RigidBody3D
		trial["previous_velocity"] = aircraft.linear_velocity if aircraft != null else Vector3.ZERO
		trial["peak_yaw_rate_deg_s"] = 0.0
		trial["peak_sideslip_ratio"] = 0.0
		trial["peak_lateral_g"] = 0.0
		trial["peak_bank_deg"] = 0.0
		trial["peak_actual_yaw_control"] = 0.0
		trial["initial_yaw_authority"] = 0.0
		trial["initial_yaw_limit"] = 0.0
		var aero := trial.get("aero") as SimpleAero
		if aircraft != null and aero != null:
			trial["initial_yaw_authority"] = aero.get_axis_control_authority_at_speed(
				aircraft.linear_velocity.length(),
				&"yaw",
				aero.get_effective_stall_speed_mps(),
				0.0
			)
			trial["initial_yaw_limit"] = aero.get_high_speed_control_limit(
				aircraft.linear_velocity.length(),
				&"yaw"
			)

	var elapsed := 0.0
	while elapsed < YAW_DURATION_S:
		for trial in trials:
			var aero := trial.get("aero") as SimpleAero
			if aero != null:
				aero.pitch_input = 0.0
				aero.roll_input = 0.0
				aero.yaw_input = 1.0
		await get_tree().physics_frame
		var delta := _physics_delta()
		elapsed += delta
		for trial in trials:
			_sample_yaw_trial(trial, delta)

	var results: Array[Dictionary] = []
	for trial in trials:
		var aircraft := trial.get("aircraft") as RigidBody3D
		var aero := trial.get("aero") as SimpleAero
		var config: Dictionary = trial.get("config", {})
		if aircraft == null or aero == null:
			continue
		results.append({
			"name": str(config.get("name", "unknown")),
			"initial_speed_mps": float(config.get("speed_mps", 0.0)),
			"yaw_power": aero.yaw_power,
			"initial_yaw_authority": float(trial.get("initial_yaw_authority", 0.0)),
			"initial_yaw_limit": float(trial.get("initial_yaw_limit", 0.0)),
			"peak_yaw_rate_deg_s": float(trial.get("peak_yaw_rate_deg_s", 0.0)),
			"peak_sideslip_ratio": float(trial.get("peak_sideslip_ratio", 0.0)),
			"peak_lateral_g": float(trial.get("peak_lateral_g", 0.0)),
			"peak_bank_deg": float(trial.get("peak_bank_deg", 0.0)),
			"peak_actual_yaw_control": float(trial.get("peak_actual_yaw_control", 0.0)),
			"final_speed_mps": aircraft.linear_velocity.length(),
		})
	return results


func _sample_yaw_trial(trial: Dictionary, delta: float) -> void:
	var aircraft := trial.get("aircraft") as RigidBody3D
	var aero := trial.get("aero") as SimpleAero
	if aircraft == null or aero == null:
		return
	var basis := aircraft.global_transform.basis.orthonormalized()
	var previous_velocity: Vector3 = trial.get("previous_velocity", aircraft.linear_velocity)
	var acceleration := (aircraft.linear_velocity - previous_velocity) / maxf(delta, 0.0001)
	var gravity := Vector3.DOWN * GRAVITY_MPS2 * aircraft.gravity_scale
	var local_specific_g := basis.inverse() * (acceleration - gravity) / GRAVITY_MPS2
	var yaw_rate_deg_s := absf(rad_to_deg(aircraft.angular_velocity.dot(basis.y)))
	var bank_deg := absf(rad_to_deg(atan2(basis.x.y, basis.y.y)))
	trial["peak_yaw_rate_deg_s"] = maxf(float(trial.get("peak_yaw_rate_deg_s", 0.0)), yaw_rate_deg_s)
	trial["peak_sideslip_ratio"] = maxf(
		float(trial.get("peak_sideslip_ratio", 0.0)),
		aero.current_sideslip_ratio
	)
	trial["peak_lateral_g"] = maxf(float(trial.get("peak_lateral_g", 0.0)), absf(local_specific_g.x))
	trial["peak_bank_deg"] = maxf(float(trial.get("peak_bank_deg", 0.0)), bank_deg)
	trial["peak_actual_yaw_control"] = maxf(
		float(trial.get("peak_actual_yaw_control", 0.0)),
		absf(aero.actual_yaw_control)
	)
	trial["previous_velocity"] = aircraft.linear_velocity


func _free_trials(trials: Array[Dictionary]) -> void:
	for trial in trials:
		var aircraft := trial.get("aircraft") as RigidBody3D
		if aircraft != null:
			aircraft.queue_free()
	await get_tree().process_frame


func _physics_delta() -> float:
	return 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)


func _vector_to_array(value: Variant) -> Array[float]:
	var vector := value as Vector3 if value is Vector3 else Vector3.ZERO
	return [vector.x, vector.y, vector.z]


func _write_report(report: Dictionary) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write %s" % REPORT_PATH)
		return
	file.store_string(JSON.stringify(report, "\t"))


func _print_report(
	pull_results: Array[Dictionary],
	roll_results: Array[Dictionary],
	yaw_results: Array[Dictionary]
) -> void:
	for result in pull_results:
		print("A5_PULL kind=%s speed=%.0f pitch_power=%.2f authority=%.3f limit=%.3f peak_g=%.2f late_g=%.2f peak_lift=%.2f aoa=%.1f stall=%.2f departure=%.2f path_rate=%.1f radius=%.0f pitch_rate=%.1f t2g=%.2f t3g=%.2f final_speed=%.1f mass=%.0f" % [
			str(result.kind),
			float(result.initial_speed_mps),
			float(result.pitch_power),
			float(result.initial_pitch_authority),
			float(result.initial_pitch_limit),
			float(result.peak_normal_g),
			float(result.late_mean_normal_g),
			float(result.peak_lift_ratio),
			float(result.peak_aoa_deg),
			float(result.peak_stall_severity),
			float(result.peak_departure_severity),
			float(result.peak_path_turn_rate_deg_s),
			float(result.minimum_radius_m),
			float(result.peak_pitch_rate_deg_s),
			float(result.time_to_2g_s),
			float(result.time_to_3g_s),
			float(result.final_speed_mps),
			float(result.runtime_mass_kg),
		])
	for result in roll_results:
		print("A5_ROLL speed=%.0f roll_power=%.2f peak_rate=%.1f t45=%.2f t90=%.2f actual=%.2f final_speed=%.1f mass=%.0f" % [
			float(result.initial_speed_mps),
			float(result.roll_power),
			float(result.peak_roll_rate_deg_s),
			float(result.time_to_45_deg_s),
			float(result.time_to_90_deg_s),
			float(result.peak_actual_roll_control),
			float(result.final_speed_mps),
			float(result.runtime_mass_kg),
		])
	for result in yaw_results:
		print("A5_YAW speed=%.0f yaw_power=%.2f authority=%.3f limit=%.3f peak_rate=%.1f slip=%.3f lateral_g=%.2f bank=%.1f actual=%.2f final_speed=%.1f" % [
			float(result.initial_speed_mps),
			float(result.yaw_power),
			float(result.initial_yaw_authority),
			float(result.initial_yaw_limit),
			float(result.peak_yaw_rate_deg_s),
			float(result.peak_sideslip_ratio),
			float(result.peak_lateral_g),
			float(result.peak_bank_deg),
			float(result.peak_actual_yaw_control),
			float(result.final_speed_mps),
		])
