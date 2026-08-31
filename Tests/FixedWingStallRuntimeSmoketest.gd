extends Node3D

@export var aircraft_scene: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft := aircraft_scene.instantiate() as RigidBody3D if aircraft_scene != null else null
	_expect(aircraft != null, "configured aircraft did not instantiate")
	if aircraft == null:
		_finish()
		return
	aircraft.name = "StallRuntimeAircraft"
	var aero := aircraft.get_node_or_null("SimpleAero") as SimpleAero
	_expect(aero != null, "SimpleAero was not found")
	if aero == null:
		aircraft.free()
		_finish()
		return
	aero.airflow_feedback_enabled = false
	aero.aero_report_enabled = false
	aero.set_flight_model_override_for_testing(1)
	var pilot := aircraft.find_child("AIPilot", true, false)
	if pilot != null:
		pilot.set_process(false)
		pilot.set_physics_process(false)
	var control_steering := aircraft.find_child("ControlSteering", true, false)
	if control_steering != null and "ControlActive" in control_steering:
		control_steering.set("ControlActive", false)
	var engine := aircraft.get_node_or_null("Engine")
	if engine != null and "PowerFactor" in engine:
		engine.set("PowerFactor", 0.0)
	add_child(aircraft)
	aircraft.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2500.0, 0.0))
	aircraft.linear_velocity = Vector3(4.0, -35.0, 50.0)
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.freeze = false
	aircraft.sleeping = false
	aero.pitch_input = 1.0

	await get_tree().physics_frame
	await get_tree().physics_frame
	var peak_departure := 0.0
	var peak_abs_roll_rate := 0.0
	var peak_abs_yaw_rate := 0.0
	var peak_abs_pitch_rate := 0.0
	var peak_drop_direction := 0.0
	var departure_after_peak := 0.0
	var saw_deep_control_separation := false
	var minimum_deep_pitch_authority := 1.0
	var minimum_deep_roll_authority := 1.0
	var minimum_deep_yaw_authority := 1.0
	var recovered_pitch_authority := 0.0
	var peak_departure_drag_n := 0.0
	var elapsed := 0.0
	while elapsed < 3.0:
		await get_tree().physics_frame
		var delta := 1.0 / float(Engine.physics_ticks_per_second)
		elapsed += delta
		if elapsed >= 1.2:
			aero.pitch_input = 0.0
		var local_angular := aircraft.global_transform.basis.inverse() * aircraft.angular_velocity
		peak_departure = maxf(peak_departure, aero.current_departure_severity)
		peak_abs_pitch_rate = maxf(peak_abs_pitch_rate, absf(local_angular.x))
		peak_abs_yaw_rate = maxf(peak_abs_yaw_rate, absf(local_angular.y))
		peak_abs_roll_rate = maxf(peak_abs_roll_rate, absf(local_angular.z))
		peak_drop_direction = maxf(peak_drop_direction, absf(aero.current_stall_drop_direction))
		peak_departure_drag_n = maxf(peak_departure_drag_n, aero.current_departure_drag_n)
		if aero.current_departure_severity >= 0.50:
			saw_deep_control_separation = true
			minimum_deep_pitch_authority = minf(minimum_deep_pitch_authority, aero.current_pitch_authority)
			minimum_deep_roll_authority = minf(minimum_deep_roll_authority, aero.current_roll_authority)
			minimum_deep_yaw_authority = minf(minimum_deep_yaw_authority, aero.current_yaw_authority)
		if elapsed > 2.5:
			departure_after_peak = aero.current_departure_severity
			recovered_pitch_authority = maxf(recovered_pitch_authority, aero.current_pitch_authority)

	print("[FixedWingStallRuntimeSmoketest] measured departure=%.3f drop=%.3f rates_pitch/yaw/roll=%.3f/%.3f/%.3f authority_pitch/roll/yaw=%.3f/%.3f/%.3f recovered_pitch=%.3f recovery=%.3f body_drag=%.1fN" % [
		peak_departure,
		peak_drop_direction,
		peak_abs_pitch_rate,
		peak_abs_yaw_rate,
		peak_abs_roll_rate,
		minimum_deep_pitch_authority,
		minimum_deep_roll_authority,
		minimum_deep_yaw_authority,
		recovered_pitch_authority,
		departure_after_peak,
		peak_departure_drag_n,
	])
	_expect(peak_departure > 0.35, "deep AoA did not enter the departure regime")
	_expect(peak_drop_direction > 0.25, "departure did not select a stable wing-drop direction")
	_expect(peak_abs_roll_rate > 0.08, "deep stall did not produce a measurable wing drop")
	_expect(peak_abs_yaw_rate > 0.03, "deep stall did not produce autorotation")
	_expect(peak_abs_pitch_rate > 0.08, "deep stall did not produce a nose break")
	_expect(saw_deep_control_separation, "runtime stall never exercised deep control separation")
	_expect(minimum_deep_pitch_authority <= aero.deep_stall_pitch_authority_cap + 0.01, "runtime elevator did not reach its deep-stall cap")
	_expect(minimum_deep_roll_authority <= aero.deep_stall_roll_authority_cap + 0.01, "runtime ailerons did not reach their deep-stall cap")
	_expect(minimum_deep_yaw_authority <= aero.deep_stall_yaw_authority_cap + 0.01, "runtime rudder did not reach its deep-stall cap")
	_expect(recovered_pitch_authority > minimum_deep_pitch_authority + 0.20, "control authority did not return after recovery")
	_expect(departure_after_peak < peak_departure, "departure did not begin recovering after the nose break")
	_expect(peak_departure_drag_n > 500.0, "deep departure never produced bounded bluff-body drag")

	aircraft.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("[FixedWingStallRuntimeSmoketest] PASS departure=%.2f rates_pitch/yaw/roll=%.2f/%.2f/%.2f recovery=%.2f" % [
			peak_departure,
			peak_abs_pitch_rate,
			peak_abs_yaw_rate,
			peak_abs_roll_rate,
			departure_after_peak,
		])
		get_tree().quit(0)
		return
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error("[FixedWingStallRuntimeSmoketest] %s" % failure)
	get_tree().quit(1)
