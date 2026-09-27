extends SceneTree
## Isolates the inner-loop response to a wings-level terrain climb request.
## This is a controller probe, not an exact replay of saved simulation state.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures: Array[String] = []
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	for scenario in ["terrain_climb", "ordinary_level", "bank_not_established", "emergency"]:
		var craft: RigidBody3D = load("res://Aircraft/Aircraft_5.tscn").instantiate()
		craft.freeze = true
		craft.position = Vector3(0, 1000, 0)
		craft.rotation.x = atan2(23.0, 70.0)
		scene.add_child(craft)
		var pilot: Node = craft.get_node("AIPilot")
		pilot.set_physics_process(false)
		var aero: Node = craft.get_node("SimpleAero")
		aero.set_flight_model_override_for_testing(1)
		craft.linear_velocity = Vector3(0, -23, 70)
		pilot.aircraft = craft
		pilot.simple_aero = aero
		pilot.current_state = pilot.State.RECOVERY_APPROACH
		pilot._recovery_terrain_vs_floor_mps = -INF if scenario == "ordinary_level" else 16.0
		pilot._recovery_lift_escape_active = scenario == "emergency"
		var requested_bank := deg_to_rad(40.0) if scenario == "bank_not_established" else 0.0
		var controls: Dictionary = pilot._compute_coordinated_turn_controls(1.0 / 60.0, requested_bank, 16.0, 2.5, true, true)
		var expected_load := 2.5 if scenario in ["terrain_climb", "emergency"] else 1.0
		if not is_equal_approx(float(controls.target_g), expected_load):
			failures.append("Unexpected load in " + scenario)
		if scenario == "terrain_climb" and float(controls.pitch) <= 0.08:
			failures.append("Early terrain climb is still limited by the roll-in elevator cap")
		print("RECOVERY_CLIMB_PROBE ", JSON.stringify({"scenario": scenario,
			"desired_vs": 16.0, "actual_vs": -23.0, "supplied_load_g": 2.5,
			"target_load_g": pilot._coordinated_turn_target_g, "controls": controls}))
		craft.free()
	for failure in failures: push_error(failure)
	print("RECOVERY_CLIMB_AUTHORITY ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
