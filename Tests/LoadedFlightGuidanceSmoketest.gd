extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	for model in [1, 2, 3, 4, 5, 6, 7, 8, 14]:
		var craft = load("res://Aircraft/Aircraft_%d.tscn" % model).instantiate()
		craft.freeze = true
		craft.position.y = 1200
		world.add_child(craft)
		var pilot = craft.get_node("AIPilot")
		pilot.set_physics_process(false)
		pilot.aircraft = craft
		var aero = craft.get_node("SimpleAero")
		pilot.simple_aero = aero
		var initial_mass: float = craft.mass
		for mode in [0, 1]:
			aero.set_flight_model_override_for_testing(mode)
			for state in [pilot.State.SEARCH, pilot.State.TRANSIT, pilot.State.ATTACK_POSITIONING, pilot.State.DOGFIGHT, pilot.State.RECOVERY_APPROACH]:
				pilot.current_state = state
				var capacities: Array[float] = []
				var angles: Array[float] = []
				for extra_mass in [0.0, initial_mass]:
					craft.set_payload_mass(pilot, extra_mass)
					craft.rotation = Vector3(0, 0, deg_to_rad(-30))
					craft.linear_velocity = craft.global_basis * Vector3(0, 0, 94)
					craft.angular_velocity = Vector3.ZERO
					pilot.reset_coordinated_turn_test_state()
					pilot._compute_coordinated_turn_controls(1.0 / 60.0, deg_to_rad(-30), craft.linear_velocity.y, 1.07, true, true)
					capacities.append(pilot._coordinated_turn_available_g)
					var aoa: float = pilot._coordinated_turn_target_aoa_deg
					angles.append(aoa)
					# Put the actual wing at the requested AoA and ask the physics for its load.
					craft.linear_velocity = craft.global_basis * Vector3(0, -sin(deg_to_rad(aoa)), cos(deg_to_rad(aoa))) * 94.0
					var actual_g: float = aero.get_estimated_lift_ratio()
					var requested_g: float = pilot._coordinated_turn_target_g
					check(absf(actual_g - requested_g) < 0.03, "model=%d mode=%d state=%d load=%.1f: wing %.3fg differs from command %.3fg" % [model, mode, state, extra_mass, actual_g, requested_g])
				check(is_equal_approx(capacities[1], capacities[0] * 0.5), "loaded capacity did not halve for model %d state %d" % [model, state])
				check(angles[1] > angles[0], "loaded aircraft did not request more AoA for model %d state %d" % [model, state])
				craft.set_payload_mass(pilot, 0.0)
		craft.free()
	print("LOADED_FLIGHT_GUIDANCE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
