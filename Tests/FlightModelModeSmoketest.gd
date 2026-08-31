extends Node3D

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var pause_menu := get_node_or_null("/root/PauseMenu")
	_expect(pause_menu != null, "PauseMenu autoload was unavailable")
	if pause_menu != null:
		_expect(pause_menu.has_method("is_advanced_flight_model"), "flight-model setting has no runtime getter")

	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_expect(aircraft != null, "Aircraft_5 did not instantiate")
	if aircraft == null:
		_finish()
		return
	var aero := aircraft.get_node_or_null("SimpleAero") as SimpleAero
	var engine := aircraft.get_node_or_null("Engine")
	_expect(aero != null, "SimpleAero was not found")
	_expect(engine != null and engine.has_method("get_effective_power_factor"), "engine has no flight-model thrust scaling")
	if aero == null or engine == null:
		aircraft.free()
		_finish()
		return
	aero.airflow_feedback_enabled = false
	aero.aero_report_enabled = false
	var pilot := aircraft.find_child("AIPilot", true, false)
	if pilot != null:
		pilot.set_process(false)
		pilot.set_physics_process(false)
	var controls := aircraft.find_child("ControlSteering", true, false)
	if controls != null and "ControlActive" in controls:
		controls.set("ControlActive", false)
	add_child(aircraft)
	aircraft.global_position = Vector3(0.0, 2000.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var authored_power := float(engine.get("PowerFactor"))
	aero.set_flight_model_override_for_testing(1)
	_expect(aero.is_advanced_flight_model(), "advanced override was ignored")
	_expect(
		is_equal_approx(aero.get_effective_pitch_power(), 6.25),
		"Aircraft_5 advanced pitch power is not the tuned 6.25 value"
	)
	_expect(aircraft.linear_damp_mode == RigidBody3D.DAMP_MODE_REPLACE, "advanced mode retained hidden project damping")
	_expect(is_zero_approx(aircraft.linear_damp), "advanced mode retained rigid-body linear damping")
	_expect(
		is_equal_approx(float(engine.call("get_effective_power_factor")), authored_power),
		"advanced mode did not retain the tuned half-thrust baseline"
	)

	aero.set_flight_model_override_for_testing(0)
	_expect(not aero.is_advanced_flight_model(), "simplified override was ignored")
	_expect(
		is_equal_approx(aero.get_effective_pitch_power(), 7.5),
		"Aircraft_5 simplified mode did not preserve its former 7.5 pitch power"
	)
	_expect(aircraft.linear_damp_mode == RigidBody3D.DAMP_MODE_COMBINE, "simplified mode did not restore legacy damping")
	var simplified_power := float(engine.call("get_effective_power_factor"))
	var expected_simplified_power := authored_power * float(engine.get("simplified_fixed_wing_thrust_multiplier"))
	_expect(
		is_equal_approx(simplified_power, expected_simplified_power),
		"simplified mode did not restore pre-overhaul fixed-wing thrust: got %.1f expected %.1f" % [
			simplified_power,
			expected_simplified_power,
		]
	)
	var simplified_fast_authority := aero.get_simplified_control_authority(
		aero.control_stiffening_full_speed_mps,
		aero.stall_speed,
		0.0
	)
	var advanced_fast_authority := aero.get_high_speed_control_limit(
		aero.control_stiffening_full_speed_mps,
		&"pitch"
	)
	_expect(simplified_fast_authority > 0.99, "simplified mode still applies high-speed control stiffening")
	_expect(advanced_fast_authority < 0.30, "advanced mode lost high-speed elevator stiffening")
	aircraft.linear_velocity = aircraft.global_transform.basis.z * 200.0
	aero.pitch_input = 1.0
	await get_tree().physics_frame
	_expect(aero.current_high_speed_stiffening < 0.001, "simplified runtime still reports high-speed stiffening")
	_expect(aero.actual_pitch_control > 0.99, "simplified runtime did not apply elevator input directly")
	aero.set_flight_model_override_for_testing(1)
	aero.actual_pitch_control = 0.0
	aircraft.linear_velocity = aircraft.global_transform.basis.z * 200.0
	await get_tree().physics_frame
	_expect(aero.current_high_speed_stiffening > 0.70, "advanced runtime did not enter high-speed stiffening")
	_expect(aero.actual_pitch_control < 0.10, "advanced runtime skipped rate-limited elevator motion")
	aero.set_flight_model_override_for_testing(0)
	_expect(
		aero._get_aoa_stall_severity_for_model(30.0, true) \
			> aero._get_aoa_stall_severity_for_model(30.0, false),
		"advanced stall does not break more decisively than simplified"
	)
	_expect(
		aero.get_induced_drag_rate_proxy_factor(true, 1.0) < 0.001,
		"advanced deep stall still converts tumbling into induced drag"
	)
	_expect(
		aero.get_induced_drag_rate_proxy_factor(false, 1.0) > 0.99,
		"simplified mode no longer retains its legacy induced-drag response"
	)
	_expect(
		aero.get_deep_stall_body_drag_magnitude(10.0, 1.0) >= 650.0,
		"advanced deep stall has no bounded bluff-body drag replacement"
	)
	var aero_source := FileAccess.get_file_as_string("res://Aircraft/SimpleAero.gd")
	_expect(
		not aero_source.contains("rudder_opposite_roll_coupling"),
		"rudder-to-roll coupling remains in SimpleAero"
	)

	aero.set_flight_model_override_for_testing(1)
	aircraft.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("[FlightModelModeSmoketest] PASS simplified=legacy_direct advanced=stiffened+departure thrust=2x/1x rudder_roll=off")
		get_tree().quit(0)
		return
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error("[FlightModelModeSmoketest] %s" % failure)
	get_tree().quit(1)
