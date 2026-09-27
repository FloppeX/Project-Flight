extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var failures: Array[String] = []
	for model in [1, 2, 3, 4, 5, 6, 7, 8, 14]:
		var craft: RigidBody3D = load("res://Aircraft/Aircraft_%d.tscn" % model).instantiate()
		craft.freeze = true
		scene.add_child(craft)
		var pilot: Node = craft.get_node("AIPilot")
		pilot.set_physics_process(false)
		pilot.aircraft = craft
		var aero: Node = craft.get_node("SimpleAero")
		aero.set_flight_model_override_for_testing(1)
		pilot.simple_aero = aero
		var original_mass := craft.mass
		var original_scale: float = aero.get_lift_load_scale()
		craft.set_payload_mass(pilot, original_mass)
		if not is_equal_approx(aero.get_lift_load_scale(), original_scale * 0.5):
			failures.append("Loaded lift scale did not follow actual mass")
		craft.set_payload_mass(pilot, 0.0)
		pilot.current_state = pilot.State.RECOVERY_APPROACH
		craft.linear_velocity = Vector3(0, 0, 90)
		pilot._compute_coordinated_turn_controls(1.0 / 60.0, 0.0, 0.0, 4.5, true, true)
		var available_before: float = pilot._coordinated_turn_available_g
		craft.set_payload_mass(pilot, original_mass)
		pilot._compute_coordinated_turn_controls(1.0 / 60.0, 0.0, 0.0, 4.5, true, true)
		if not is_equal_approx(pilot._coordinated_turn_available_g, available_before * 0.5):
			failures.append("AI recovery capacity did not follow loaded wing capacity")
		craft.set_payload_mass(pilot, 0.0)
		print("RECOVERY_AIRFRAME ", model, " mass=", craft.mass,
			" lift_scale=", aero.get_lift_load_scale(), " stall=", aero.get_effective_stall_speed_mps())
		if pilot.landing_bolter_retry_cooldown_s <= 0.0:
			failures.append("Aircraft %d cannot retry automatically" % model)
		var markers: Array[Node3D] = []
		for i in 5:
			var marker := Marker3D.new()
			craft.add_child(marker)
			markers.append(marker)
		pilot._approach_wp.assign(markers)
		pilot._recovery_retry_limit_reached = true
		pilot._recovery_go_around_attempt_count = 3
		pilot._recovery_clearance_granted = false
		if pilot._update_recovery_retry_cooldown(19.0):
			failures.append("Retry cooldown was skipped")
		if not pilot._update_recovery_retry_cooldown(1.0) or pilot._recovery_retry_limit_reached:
			failures.append("Retry did not release the attempt limit")
		if pilot._recovery_clearance_granted:
			failures.append("Retry bypassed the deck queue")
		pilot.landing_bolter_retry_cooldown_s = 0.0
		pilot._recovery_retry_limit_reached = true
		if pilot._update_recovery_retry_cooldown(100.0):
			failures.append("Explicit supervised hold was overridden")
		pilot.current_state = pilot.State.PRE_LANDING
		pilot._landing_sight_solution = {}
		craft.global_position = Vector3(200.0, 200.0, 2400.0)
		craft.linear_velocity = Vector3(0, 0, -60)
		var line := {"valid": true, "axis": Vector3.FORWARD, "touchdown": Vector3.ZERO}
		if not pilot._update_pre_landing_line_capture(1.0 / 60.0, line):
			failures.append("Line capture still requires a wire forecast")
		var acceleration: float = pilot._landing_sight_solution.lateral_plan.accel_mps2
		if acceleration <= 0.0:
			failures.append("Line capture steers away from the centreline")
		pilot.current_state = pilot.State.LANDING
		if pilot._update_pre_landing_line_capture(1.0 / 60.0, line):
			failures.append("Line capture replaced final wire guidance")
		craft.free()
	for failure in failures: push_error(failure)
	print("RECOVERY_LINE_CAPTURE ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
