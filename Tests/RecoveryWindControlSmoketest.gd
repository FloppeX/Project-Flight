extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var craft := RigidBody3D.new()
	root.add_child(craft)
	var aero = load("res://Tests/Fixtures/RecoveryAirflowProbe.gd").new()
	aero.set_flight_model_override_for_testing(1)
	aero.progressive_control_authority_enabled = true
	var pilot = load("res://AI/AIPilot.gd").new()
	pilot.aircraft = craft
	pilot.simple_aero = aero
	pilot.invert_yaw_sign = false
	craft.linear_velocity = Vector3(5.0, 0.0, 60.0)
	pilot._landing_sight_solution = {"deck_normal": Vector3.UP,
		"deck_axis": Vector3.FORWARD * -1.0, "lateral_plan": {"accel_mps2": 0.0}}
	pilot._apply_landing_terminal_rudder(1.0, 0.0)
	var failures: Array[String] = []
	if absf(pilot.yaw_input) > 0.001:
		failures.append("crosswind ground drift was mistaken for aerodynamic sideslip")
	craft.linear_velocity = Vector3(0.0, 0.0, 60.0)
	pilot._landing_sight_solution.lateral_plan.accel_mps2 = 1.0
	pilot._apply_landing_terminal_rudder(1.0, 0.0)
	var weak_rudder: float = pilot.yaw_input
	aero.progressive_control_authority_enabled = false
	pilot._apply_landing_terminal_rudder(1.0, 0.0)
	if weak_rudder <= pilot.yaw_input * 1.3 or weak_rudder <= 0.0:
		failures.append("weaker rudder did not receive more travel for the same turn request")
	aero.progressive_control_authority_enabled = true
	for direction in [-1.0, 1.0]:
		pilot._landing_sight_solution.lateral_plan.accel_mps2 = direction * 20.0
		pilot._apply_landing_terminal_rudder(1.0, 0.0)
		if not is_finite(pilot.yaw_input) or absf(pilot.yaw_input) > 1.0 \
				or signf(pilot.yaw_input) != direction:
			failures.append("unreachable turn request produced an invalid rudder command")
	pilot.free()
	aero.free()
	craft.free()
	for failure in failures:
		push_error(failure)
	print("[RecoveryWindControlSmoketest] " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
