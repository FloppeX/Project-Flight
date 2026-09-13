extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var sight: Script = load("res://AI/LandingSight.gd")
	var mild: Dictionary = sight.escape_response_budget(4.0, 0.0, 1.0, 2.0)
	var severe: Dictionary = sight.escape_response_budget(12.0, 0.8, 0.5, 1.5)
	check(float(severe.height_m) > float(mild.height_m), "sink/roll/low lift must increase escape height budget")
	check(float(severe.time_s) > float(mild.time_s), "heavy-aircraft response needs earlier decision")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var packed: PackedScene = load("res://Aircraft/Aircraft_2.tscn")
	var craft := packed.instantiate() as RigidBody3D
	craft.freeze = true
	scene.add_child(craft)
	await process_frame
	await process_frame
	var pilot := craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	craft.global_position = Vector3(0, 10, 0)
	craft.global_basis = Basis.IDENTITY
	craft.linear_velocity = Vector3(0, -8, 60)
	craft.angular_velocity = Vector3.ZERO
	var departure := Node3D.new()
	scene.add_child(departure)
	pilot.set("_takeoff_wp", departure)
	pilot.set("current_state", 16)
	pilot.set("throttle_input", 0.03)
	pilot.set("pitch_input", -0.4)
	check(pilot.call("request_landing_wave_off", "smoke"), "established final accepts a waveoff")
	check(int(pilot.get("current_state")) == 17, "waveoff enters canonical escape")
	check(is_equal_approx(float(pilot.get("throttle_input")), 1.0), "power must change in same call")
	check(float(pilot.get("pitch_input")) > 0.0, "escape replaces stale nose-down input immediately")
	check(float(pilot.get("_coordinated_turn_target_g")) > 1.0, "wings-level escape must request descent-arrest load above 1G")
	check(float(pilot.get("_coordinated_turn_target_g")) <= float(pilot.get("_coordinated_turn_available_g")) + 0.001,
		"escape cannot demand more than available useful lift")
	check(absf(float(pilot.get("roll_input"))) < 0.01, "level aircraft must not begin its return turn")
	pilot.set("current_state", 16)
	var deck_y := float(pilot.call("_get_approach_deck_y"))
	var solution := {"valid": true, "main_gear_sensor": {"valid": true,
		"lowest_position": Vector3(0, deck_y + 8.0, 0)}, "predicted_viable_wire_number": 0,
		"sink_rate_at_contact_mps": -8.0,
		"wire_solutions": [{"valid": true, "time_s": 1.0, "vertical_m": -8.0,
			"lateral_m": 0.0, "half_span_m": 10.0, "vertical_tolerance_m": 0.8, "wire_number": 1}]}
	pilot.set("_landing_sight_solution", solution)
	check(pilot.call("_update_landing_high_miss_waveoff", 0.016),
		"nonviable close crossing must consider time to escape before the old miss gate")
	# The same deadline must not reject a small correctable linear miss.
	solution["sink_rate_at_contact_mps"] = -3.3
	solution["wire_solutions"][0]["time_s"] = 1.2
	solution["wire_solutions"][0]["vertical_m"] = -0.9
	pilot.set("_landing_sight_solution", solution)
	check(not pilot.call("_update_landing_high_miss_waveoff", 0.016),
		"absence of a constant-velocity catch does not prove a correction is impossible")
	solution["sink_rate_at_contact_mps"] = -8.0
	solution["wire_solutions"][0]["time_s"] = 1.0
	solution["wire_solutions"][0]["vertical_m"] = -8.0
	solution["predicted_viable_wire_number"] = 1
	pilot.set("_landing_sight_solution", solution)
	check(not pilot.call("_update_landing_high_miss_waveoff", 0.016),
		"viable catch must not be abandoned by the escape deadline")
	craft.set_meta("arresting_engaged", true)
	solution["predicted_viable_wire_number"] = 0
	pilot.set("_landing_sight_solution", solution)
	check(not pilot.call("_update_landing_high_miss_waveoff", 0.016),
		"real wire catch always suppresses waveoff")
	craft.set_meta("arresting_engaged", false)
	pilot.set("current_state", 17)
	pilot.set("altitude_agl", 50.0)
	pilot.set("terrain_ahead_distance", 10.0) # Downward awareness ray, not flight path.
	pilot.set("terrain_flight_path_distance", INF)
	pilot.set("_terrain_fan_clearances", PackedFloat32Array([50, 50, 50, 50, 50]))
	check(not pilot.call("_check_terrain_avoidance", 0.016),
		"terrain margin warning must not replace the active lift-based escape controller")
	pilot.set("terrain_flight_path_distance", 10.0)
	check(pilot.call("_check_terrain_avoidance", 0.016),
		"real imminent flight-path terrain collision keeps emergency priority")
	check(float(pilot.get("_coordinated_turn_target_g")) > 1.0,
		"imminent-terrain escape must keep updating the lift controller, not restore the weak pitch servo")
	var carrier := Node3D.new()
	carrier.add_to_group("carrier")
	scene.add_child(carrier)
	craft.global_position = Vector3(-500, 600, -500)
	craft.global_basis = Basis.IDENTITY
	craft.linear_velocity = Vector3(-100, 0, 0)
	craft.angular_velocity = Vector3.ZERO
	pilot.set("current_state", 17)
	pilot.set("_ma_escape_complete", false)
	pilot.set("_ma_escape_start_altitude_m", 400.0)
	pilot.set("_recovery_escape_terrain_solution", {})
	pilot.call("_state_missed_approach", 0.016)
	check(int(pilot.get("current_state")) != 17,
		"clear sideways flight exits wings-level escape even without crossing bow; missing references may enter hold")
	scene.free()
	print("GO_AROUND_RESPONSE_SMOKETEST %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
