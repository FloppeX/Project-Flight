extends Node3D

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_expect(aircraft != null, "Aircraft_5 did not instantiate")
	if aircraft == null:
		_finish()
		return
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
	var controls := aircraft.find_child("ControlSteering", true, false)
	if controls != null and "ControlActive" in controls:
		controls.set("ControlActive", false)
	var engine := aircraft.get_node_or_null("Engine")
	if engine != null and "PowerFactor" in engine:
		engine.set("PowerFactor", 0.0)
	add_child(aircraft)

	# Recreate the essential L3_003 state: inverted, nearly vertical 10.9 m/s
	# descent, high sideslip, and rapid rotation around all three body axes.
	var marked_basis := Basis.from_euler(Vector3(
		deg_to_rad(-35.35),
		deg_to_rad(-11.66),
		deg_to_rad(149.22)
	))
	aircraft.global_transform = Transform3D(marked_basis, Vector3(0.0, 5000.0, 0.0))
	aircraft.linear_velocity = Vector3(1.61, -10.74, 0.0)
	aircraft.angular_velocity = marked_basis * Vector3(-1.64, 0.847, 1.06)
	aircraft.freeze = false
	aircraft.sleeping = false
	aero.pitch_input = 0.0
	aero.roll_input = 0.0
	aero.yaw_input = 0.0

	var initial_sink := aircraft.linear_velocity.y
	await get_tree().physics_frame
	await get_tree().physics_frame
	var fastest_sink := initial_sink
	var peak_departure := 0.0
	var peak_body_drag_n := 0.0
	var last_two_second_sink_sum := 0.0
	var last_two_second_samples := 0
	var elapsed := 0.0
	while elapsed < 7.0:
		await get_tree().physics_frame
		var delta := 1.0 / float(Engine.physics_ticks_per_second)
		elapsed += delta
		fastest_sink = minf(fastest_sink, aircraft.linear_velocity.y)
		peak_departure = maxf(peak_departure, aero.current_departure_severity)
		peak_body_drag_n = maxf(peak_body_drag_n, aero.current_departure_drag_n)
		if elapsed >= 5.0:
			last_two_second_sink_sum += aircraft.linear_velocity.y
			last_two_second_samples += 1

	var mean_late_sink := last_two_second_sink_sum / float(maxi(last_two_second_samples, 1))
	print("[FixedWingFlatSpinRegressionSmoketest] measured initial_sink=%.2f fastest_sink=%.2f late_sink=%.2f departure=%.2f body_drag=%.1fN speed=%.2f" % [
		initial_sink,
		fastest_sink,
		mean_late_sink,
		peak_departure,
		peak_body_drag_n,
		aircraft.linear_velocity.length(),
	])
	_expect(peak_departure > 0.90, "marked state did not enter a deep departure")
	_expect(peak_body_drag_n > 500.0, "deep departure did not replace rotation-derived drag")
	_expect(fastest_sink < -20.0, "marked state remained trapped near its artificial 10-11 m/s sink rate")
	_expect(mean_late_sink < -18.0, "marked state returned to a parachute-like slow descent")

	aircraft.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("[FixedWingFlatSpinRegressionSmoketest] PASS no_slow_parachute_equilibrium=true")
		get_tree().quit(0)
		return
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error("[FixedWingFlatSpinRegressionSmoketest] %s" % failure)
	get_tree().quit(1)
