extends Node3D

@export var aircraft_scene: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")
@export var aircraft_label := "Aircraft_5"
@export var expect_passive_directional_stability := false
@export var isolate_rudder_loop := true

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var pause_menu := get_node_or_null("/root/PauseMenu")
	_expect(pause_menu != null, "PauseMenu autoload was not available")
	var previous_assist_level := 0
	if pause_menu != null:
		previous_assist_level = int(pause_menu.get("_rudder_assist_level"))
		# Exercise the strongest user-facing setting without writing settings.cfg.
		pause_menu.set("_rudder_assist_level", 2)

	var aircraft := aircraft_scene.instantiate() as RigidBody3D if aircraft_scene != null else null
	_expect(aircraft != null, "%s did not instantiate" % aircraft_label)
	if aircraft == null:
		_restore_assist_level(pause_menu, previous_assist_level)
		_finish()
		return
	aircraft.name = "YawAssistRuntimeAircraft"
	var aero := aircraft.get_node_or_null("SimpleAero") as SimpleAero
	_expect(aero != null, "SimpleAero was not found")
	if aero == null:
		aircraft.free()
		_restore_assist_level(pause_menu, previous_assist_level)
		_finish()
		return
	aero.airflow_feedback_enabled = false
	aero.aero_report_enabled = false
	aero.set_flight_model_override_for_testing(1)
	# The baseline isolates the advanced rudder loop so a reduction in sideslip
	# must come from commanded rudder. The Aircraft_14 wrapper keeps both central
	# alignment and passive weathervaning active to catch integrated limit cycles.
	if isolate_rudder_loop:
		aero.alignment_strength = 0.0
		aero.alignment_low_speed_strength = 0.0
		aero.directional_stability_strength = 0.0
	var controls := aircraft.get_node_or_null("ControlSteering") as AircraftModule_ControlSteering
	_expect(controls != null, "ControlSteering was not found")
	var pilot := aircraft.find_child("AIPilot", true, false)
	if pilot != null:
		pilot.set_process(false)
		pilot.set_physics_process(false)
	var engine := aircraft.get_node_or_null("Engine")
	if engine != null and "PowerFactor" in engine:
		engine.set("PowerFactor", 0.0)
	add_child(aircraft)
	# Aircraft setup awaits a process frame before it wires its modules. Explicitly
	# re-run this one setup afterward so the harness cannot silently test passive
	# SimpleAero alignment with an inactive control module.
	await get_tree().process_frame
	var ai_toggle := aircraft.get_node_or_null("AIToggle")
	if ai_toggle != null and ai_toggle.has_method("disable_ai"):
		ai_toggle.call("disable_ai")
	if pilot != null:
		pilot.set_process(false)
		pilot.set_physics_process(false)
	if controls != null:
		controls.setup(aircraft)
		controls.ControlActive = true
		controls.set_physics_process(true)
		controls._reset_rudder_assist_state()
		_expect(controls.steering_module != null, "ControlSteering did not acquire the steering module")
		_expect(controls._get_rudder_assist_strength(false) > 0.99, "full rudder assist was not active")
		_expect(controls.is_physics_processing(), "ControlSteering physics processing remained disabled")
	aircraft.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2500.0, 0.0))
	aircraft.linear_velocity = Vector3(12.0, 0.0, 170.0)
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.freeze = false
	aircraft.sleeping = false

	await get_tree().physics_frame
	await get_tree().physics_frame
	var initial_sideslip := absf(aircraft.linear_velocity.x) / maxf(aircraft.linear_velocity.length(), 1.0)
	var maximum_command := 0.0
	var maximum_stiffened_command := 0.0
	var maximum_command_limit_excess := 0.0
	var maximum_actual_surface_limit_excess := 0.0
	var maximum_actual_rudder := 0.0
	var maximum_logged_assist_component := 0.0
	var maximum_logged_raw_yaw := 0.0
	var maximum_stiffening := 0.0
	var minimum_slip_ball_scale := 1.0
	var maximum_slip_ball_scale := 0.0
	var maximum_directional_torque_nm := 0.0
	var command_reversals := 0
	var actual_reversals := 0
	var previous_command_sign := 0.0
	var previous_actual_sign := 0.0
	var elapsed := 0.0
	while elapsed < 4.0:
		await get_tree().physics_frame
		var delta := 1.0 / float(Engine.physics_ticks_per_second)
		elapsed += delta
		var command := aero.yaw_input
		var actual := aero.actual_yaw_control
		maximum_command = maxf(maximum_command, absf(command))
		maximum_actual_rudder = maxf(maximum_actual_rudder, absf(actual))
		maximum_directional_torque_nm = maxf(
			maximum_directional_torque_nm,
			absf(aero.current_directional_stability_torque_nm)
		)
		if controls != null:
			maximum_logged_assist_component = maxf(
				maximum_logged_assist_component,
				absf(controls.telemetry_rudder_assist_component)
			)
			maximum_logged_raw_yaw = maxf(maximum_logged_raw_yaw, absf(controls.telemetry_raw_yaw))
			maximum_stiffening = maxf(maximum_stiffening, aero.current_high_speed_stiffening)
			maximum_command_limit_excess = maxf(
				maximum_command_limit_excess,
				absf(command) - controls.telemetry_rudder_assist_limit
			)
			maximum_actual_surface_limit_excess = maxf(
				maximum_actual_surface_limit_excess,
				absf(actual) - aero.get_high_speed_control_limit(
					aircraft.linear_velocity.length(),
					&"yaw"
				)
			)
			if controls.telemetry_rudder_assist_stiffening >= 0.5:
				maximum_stiffened_command = maxf(maximum_stiffened_command, absf(command))
			var slip_ball_scale := controls._get_fixed_wing_slip_ball_scale()
			minimum_slip_ball_scale = minf(minimum_slip_ball_scale, slip_ball_scale)
			maximum_slip_ball_scale = maxf(maximum_slip_ball_scale, slip_ball_scale)
		var command_sign := signf(command) if absf(command) >= 0.03 else 0.0
		if command_sign != 0.0:
			if previous_command_sign != 0.0 and command_sign != previous_command_sign:
				command_reversals += 1
			previous_command_sign = command_sign
		var actual_sign := signf(actual) if absf(actual) >= 0.02 else 0.0
		if actual_sign != 0.0:
			if previous_actual_sign != 0.0 and actual_sign != previous_actual_sign:
				actual_reversals += 1
			previous_actual_sign = actual_sign

	var local_velocity := aircraft.global_transform.basis.inverse() * aircraft.linear_velocity
	var final_sideslip := absf(local_velocity.x) / maxf(aircraft.linear_velocity.length(), 1.0)
	print("[FixedWingYawAssistRuntimeSmoketest] %s measured stiffening=%.2f ball_scale=%.2f..%.2f command=%.3f stiffened=%.3f actual=%.3f passive=%.1fNm reversals=%d/%d sideslip=%.3f->%.3f" % [
		aircraft_label,
		maximum_stiffening,
		minimum_slip_ball_scale,
		maximum_slip_ball_scale,
		maximum_command,
		maximum_stiffened_command,
		maximum_actual_rudder,
		maximum_directional_torque_nm,
		command_reversals,
		actual_reversals,
		initial_sideslip,
		final_sideslip,
	])
	_expect(maximum_stiffening > 0.5, "run never exercised the high-speed stiffening range")
	var minimum_correction := 0.03 if isolate_rudder_loop else 0.01
	_expect(maximum_command >= minimum_correction, "rudder assist never issued a corrective command")
	_expect(maximum_logged_assist_component >= minimum_correction, "rudder correction was not exposed to player telemetry")
	_expect(maximum_logged_raw_yaw < 0.001, "headless test unexpectedly logged manual yaw input")
	_expect(maximum_command <= 1.01, "FULL rudder assist exceeded normalized input range")
	_expect(maximum_command_limit_excess <= 0.02, "filtered rudder assist materially exceeded its scheduled travel")
	_expect(maximum_actual_surface_limit_excess <= 0.03, "physical rudder exceeded SimpleAero's high-speed surface limit")
	_expect(command_reversals <= 2, "rudder-assist command developed a high-speed limit cycle")
	_expect(actual_reversals <= 2, "physical rudder developed a high-speed limit cycle")
	_expect(final_sideslip < initial_sideslip, "rudder assist did not reduce the initial sideslip")
	if expect_passive_directional_stability:
		_expect(maximum_directional_torque_nm > 100.0, "configured passive directional stability never produced a useful moment")
	else:
		_expect(maximum_directional_torque_nm < 0.1, "baseline unexpectedly used passive directional stability")

	# Exercise the real Advanced trigger-input path after the hands-off wobble run.
	# Half manual rudder should reserve its proportional share of authority, while
	# full opposing rudder must take complete control immediately.
	Input.action_press("yaw_left", 0.50)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var manual_raw_yaw := controls.telemetry_raw_yaw if controls != null else 0.0
	var manual_shaped_yaw := controls.telemetry_shaped_yaw if controls != null else 0.0
	var manual_assist_component := controls.telemetry_rudder_assist_component if controls != null else 1.0
	var automatic_during_manual := controls._filtered_assist_yaw if controls != null else 0.0
	var expected_manual_assist_component := automatic_during_manual * (1.0 - absf(manual_shaped_yaw))
	Input.action_release("yaw_left")
	Input.action_press("yaw_right", 1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var full_override_output := controls.telemetry_assisted_yaw if controls != null else 0.0
	var full_override_assist_component := controls.telemetry_rudder_assist_component if controls != null else 1.0
	Input.action_release("yaw_right")
	_expect(absf(manual_raw_yaw - 0.50) < 0.01, "Advanced did not read half-trigger raw rudder input")
	_expect(absf(manual_shaped_yaw - 0.4186) < 0.01, "Advanced half-trigger rudder did not use the 5 percent/15 percent curve")
	_expect(
		absf(manual_assist_component - expected_manual_assist_component) < 0.01,
		"half-trigger manual rudder did not reserve proportional authority from the autorudder"
	)
	_expect(absf(full_override_output + 1.0) < 0.01, "full opposing manual rudder did not take complete control")
	_expect(absf(full_override_assist_component) < 0.01, "autorudder remained mixed into full manual rudder")

	_restore_assist_level(pause_menu, previous_assist_level)
	aircraft.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("[FixedWingYawAssistRuntimeSmoketest] PASS %s high_speed_reversals=%d/%d sideslip=%.3f->%.3f manual_half=%.3f assist=%.3f full_override=%.1f" % [
			aircraft_label,
			command_reversals,
			actual_reversals,
			initial_sideslip,
			final_sideslip,
			manual_shaped_yaw,
			manual_assist_component,
			full_override_output,
		])
		get_tree().quit(0)
		return
	_finish()


func _restore_assist_level(pause_menu: Node, previous_level: int) -> void:
	if pause_menu != null:
		pause_menu.set("_rudder_assist_level", previous_level)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error("[FixedWingYawAssistRuntimeSmoketest] %s" % failure)
	get_tree().quit(1)
