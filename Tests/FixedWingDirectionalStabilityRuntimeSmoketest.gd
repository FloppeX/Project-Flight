extends Node3D

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_14.tscn")
const RUN_DURATION_S := 2.5

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var passive := _spawn_trial("PassiveWeathervane", -900.0, 4.0)
	var control := _spawn_trial("NoWeathervane", 900.0, 0.0)
	if passive.is_empty() or control.is_empty():
		_finish()
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_prepare_trial(passive)
	_prepare_trial(control)
	await get_tree().physics_frame

	var initial_beta_deg := _beta_deg(passive)
	var peak_passive_torque_nm := 0.0
	var peak_passive_yaw_rate := 0.0
	var passive_yaw_reversals := 0
	var previous_yaw_sign := 0.0
	var elapsed := 0.0
	while elapsed < RUN_DURATION_S:
		await get_tree().physics_frame
		var delta := 1.0 / float(Engine.physics_ticks_per_second)
		elapsed += delta
		var passive_aero := passive.aero as SimpleAero
		peak_passive_torque_nm = maxf(
			peak_passive_torque_nm,
			absf(passive_aero.current_directional_stability_torque_nm)
		)
		var local_yaw_rate := (passive.aircraft as RigidBody3D).angular_velocity.dot(
			(passive.aircraft as RigidBody3D).global_transform.basis.y
		)
		peak_passive_yaw_rate = maxf(peak_passive_yaw_rate, absf(local_yaw_rate))
		var yaw_sign := signf(local_yaw_rate) if absf(local_yaw_rate) >= 0.02 else 0.0
		if yaw_sign != 0.0:
			if previous_yaw_sign != 0.0 and yaw_sign != previous_yaw_sign:
				passive_yaw_reversals += 1
			previous_yaw_sign = yaw_sign

	var passive_final_beta_deg := _beta_deg(passive)
	var control_final_beta_deg := _beta_deg(control)
	var passive_heading_deg := _heading_deg(passive.aircraft as RigidBody3D)
	var control_heading_deg := _heading_deg(control.aircraft as RigidBody3D)
	var passive_aero := passive.aero as SimpleAero
	var control_aero := control.aero as SimpleAero

	print("[FixedWingDirectionalStabilityRuntimeSmoketest] measured beta initial=%.2f passive=%.2f control=%.2f heading=%.2f/%.2f torque=%.1fNm yaw_rate=%.3f reversals=%d" % [
		initial_beta_deg,
		passive_final_beta_deg,
		control_final_beta_deg,
		passive_heading_deg,
		control_heading_deg,
		peak_passive_torque_nm,
		peak_passive_yaw_rate,
		passive_yaw_reversals,
	])
	_expect(initial_beta_deg > 10.0, "runtime did not begin with meaningful sideslip")
	_expect(peak_passive_torque_nm > 200.0, "passive directional stability never produced a useful moment")
	_expect(absf(passive_heading_deg) > absf(control_heading_deg) + 3.0, "weathervane moment did not turn the nose into the airflow")
	_expect(passive_final_beta_deg < control_final_beta_deg * 0.72, "passive directional stability did not materially outperform lateral drag alone")
	_expect(passive_yaw_reversals <= 1, "passive directional stability developed a yaw oscillation")
	_expect(passive_aero.current_departure_severity < 0.05, "passive trial entered a stall departure")
	_expect(control_aero.current_departure_severity < 0.05, "control trial entered a stall departure")

	(passive.aircraft as RigidBody3D).queue_free()
	(control.aircraft as RigidBody3D).queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("[FixedWingDirectionalStabilityRuntimeSmoketest] PASS passive_weathervane_without_rudder_or_alignment")
		get_tree().quit(0)
		return
	_finish()


func _spawn_trial(trial_name: String, x_position: float, strength: float) -> Dictionary:
	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	if aircraft == null:
		_failures.append("%s did not instantiate" % trial_name)
		return {}
	aircraft.name = trial_name
	aircraft.transform = Transform3D(Basis.IDENTITY, Vector3(x_position, 2500.0, 0.0))
	aircraft.linear_velocity = Vector3(20.0, 0.0, 82.0)
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.set_meta("landing_test_aircraft", true)
	var ai_toggle := aircraft.get_node_or_null("AIToggle")
	if ai_toggle != null:
		ai_toggle.set("ai_enabled_at_start", false)
	var aero := aircraft.get_node_or_null("SimpleAero") as SimpleAero
	if aero == null:
		_failures.append("%s had no SimpleAero" % trial_name)
		aircraft.free()
		return {}
	aero.directional_stability_strength = strength
	add_child(aircraft)
	return {"aircraft": aircraft, "aero": aero, "x": x_position}


func _prepare_trial(trial: Dictionary) -> void:
	var aircraft := trial.aircraft as RigidBody3D
	var aero := trial.aero as SimpleAero
	var pilot := aircraft.find_child("AIPilot", true, false)
	if pilot != null:
		pilot.set_process(false)
		pilot.set_physics_process(false)
	var controls := aircraft.get_node_or_null("ControlSteering")
	if controls != null:
		controls.set("ControlActive", false)
		controls.set_physics_process(false)
	var ai_toggle := aircraft.get_node_or_null("AIToggle")
	if ai_toggle != null and ai_toggle.has_method("disable_ai"):
		ai_toggle.call("disable_ai")
	var engine := aircraft.get_node_or_null("Engine")
	if engine != null:
		engine.set("is_engine_working", false)
		engine.set("current_power", 0.0)
		engine.set("target_power", 0.0)
		engine.set("PowerFactor", 0.0)
	var gear := aircraft.find_child("ControlLandingGear", true, false)
	if gear != null and gear.has_method("stow_gear"):
		gear.call("stow_gear")
	aero.airflow_feedback_enabled = false
	aero.aero_report_enabled = false
	aero.set_flight_model_override_for_testing(1)
	aero.alignment_strength = 0.0
	aero.alignment_low_speed_strength = 0.0
	aero.pitch_input = 0.0
	aero.roll_input = 0.0
	aero.yaw_input = 0.0
	aircraft.global_transform = Transform3D(Basis.IDENTITY, Vector3(float(trial.x), 2500.0, 0.0))
	PhysicsServer3D.body_set_state(aircraft.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, aircraft.global_transform)
	aircraft.linear_velocity = Vector3(20.0, 0.0, 82.0)
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.freeze = false
	aircraft.sleeping = false


func _beta_deg(trial: Dictionary) -> float:
	var aircraft := trial.aircraft as RigidBody3D
	var aero := trial.aero as SimpleAero
	var local_velocity := aircraft.global_transform.basis.inverse() * aircraft.linear_velocity
	return absf(rad_to_deg(aero.get_signed_sideslip_angle_rad(local_velocity)))


func _heading_deg(aircraft: RigidBody3D) -> float:
	var forward := aircraft.global_transform.basis.z.normalized()
	return rad_to_deg(atan2(forward.x, forward.z))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error("[FixedWingDirectionalStabilityRuntimeSmoketest] %s" % failure)
	get_tree().quit(1)
