extends SceneTree
## Roll-in must preserve the intended vertical lift instead of turning lateral
## load into a climb. Production and diagnostic arcs must use the same law.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var results := {}
	var failures: Array[String] = []
	for side in [-1.0, 1.0]:
		for tag in ["compact_recovery_break", "quick_recovery_turn_in", "unlabelled_arc"]:
			var craft: RigidBody3D = load("res://Aircraft/Aircraft_5.tscn").instantiate()
			craft.freeze = true
			craft.position.y = 1000.0
			craft.rotation.z = deg_to_rad(45.0) * side
			scene.add_child(craft)
			var pilot: Node = craft.get_node("AIPilot")
			pilot.set_physics_process(false)
			var aero: Node = craft.get_node("SimpleAero")
			aero.set_flight_model_override_for_testing(1)
			craft.linear_velocity = Vector3(0, 0, 70)
			pilot.aircraft = craft
			pilot.simple_aero = aero
			pilot.current_state = pilot.State.RECOVERY_APPROACH
			pilot._flight_plan_name = "recovery_approach"
			pilot._active_flight_plan = {"metadata": {"planner": "compact_pattern"}}
			pilot._flight_plan_legs.assign([{"route_primitive": "arc", "debug_tag": tag}])
			pilot.current_waypoint_index = 0
			var controls: Dictionary = pilot._compute_coordinated_turn_controls(1.0 / 60.0, deg_to_rad(60.0) * side, 0.0, 2.0, true, true)
			var vertical_g: float = controls.target_g * controls.vertical_lift_fraction
			if vertical_g > 1.01:
				failures.append("Roll-in adds unrequested vertical lift: %s %s %s" % [side, tag, vertical_g])
			var key := str(side)
			if results.has(key) and not is_equal_approx(float(results[key]), float(controls.target_g)):
				failures.append("Debug tag changes production load")
			results[key] = controls.target_g
			print("COMPACT_VECTOR_CASE ", {"side": side, "tag": tag, "target_g": controls.target_g, "vertical_g": vertical_g})
			pilot._flight_plan_legs.assign([{"route_primitive": "straight"}])
			if pilot._uses_compact_recovery_vector_control(): failures.append("Straight leg selected arc controller")
			pilot._flight_plan_legs.assign([{"route_primitive": "arc"}])
			pilot._flight_plan_name = "ground_attack"
			if pilot._uses_compact_recovery_vector_control(): failures.append("Combat selected recovery controller")
			craft.free()
	for failure in failures: push_error(failure)
	print("COMPACT_RECOVERY_VECTOR ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
