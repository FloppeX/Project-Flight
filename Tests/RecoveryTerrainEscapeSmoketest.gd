extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var craft := (load("res://Aircraft/Aircraft_5.tscn") as PackedScene).instantiate() as RigidBody3D
	craft.freeze = true
	scene.add_child(craft)
	await process_frame
	craft.get_node("AIPilot").free()
	var pilot = load("res://Tests/fixtures/WaitingRecoveryPilot.gd").new()
	pilot.name = "AIPilot"
	craft.add_child(pilot)
	pilot.set_physics_process(false)
	pilot.aircraft = craft
	pilot.simple_aero = craft.get_node("SimpleAero")
	pilot.current_state = pilot.State.RECOVERY_APPROACH
	pilot._recovery_route_request_debugged = true
	pilot._aircraft_heightmap_route_job_active = true
	pilot._flight_plan_name = ""
	pilot.waypoints.clear()
	craft.global_position = Vector3(0, 1000, 0)
	craft.global_basis = Basis(Vector3.BACK, deg_to_rad(20.0))
	craft.linear_velocity = Vector3(0, -8, 70)
	craft.angular_velocity = Vector3(0, 0, 0.5)
	pilot.altitude_agl = 1000.0
	pilot.roll_input = 0.96
	pilot.pitch_input = -0.35
	pilot._smoothed_roll_input = 0.96
	pilot._smoothed_pitch_input = -0.35
	pilot._state_recovery_approach(1.0 / 60.0)
	check(pilot.roll_input < 0.0, "pending route must replace stale positive aileron with counter-roll")
	check(pilot.pitch_input > -0.35, "pending route must replace stale nose-down command")
	check(pilot._aircraft_heightmap_route_job_active, "stabilization must not cancel the pending route")
	check(pilot._coordinated_turn_target_g > 1.0, "wings-level stabilization must arrest sink using lift feedback")
	var sight = load("res://AI/LandingSight.gd")
	var hill := [{"time_s": 6.0, "height_m": 788.0}]
	var upright: Dictionary = sight.terrain_escape_profile(hill, 732.0, -5.6, 0.6, 8.0, 30.0, 100.0)
	var inverted: Dictionary = sight.terrain_escape_profile(hill, 732.0, -5.6, 4.0, 8.0, 30.0, 100.0)
	check(float(upright.desired_vs_mps) > 12.8, "ridge must demand more than the old deck-relative climb cap")
	check(float(inverted.min_clearance_m) < float(upright.min_clearance_m), "roll-recovery delay consumes clearance")
	check(bool(inverted.unreachable), "late inverted escape must not be advertised as clear")
	var flat: Dictionary = sight.terrain_escape_profile([{"time_s": 6.0, "height_m": 0.0}], 300.0, 0.0, 0.6, 8.0, 30.0, 100.0)
	check(float(flat.desired_vs_mps) == 0.0 and not flat.unreachable, "clear flat terrain must not invent a climb demand")
	var unknown: Dictionary = sight.terrain_escape_profile([{"time_s": 6.0, "height_m": NAN}], 300.0, 0.0, 0.6, 8.0, 30.0, 100.0)
	check(not unknown.valid, "unknown terrain must stay explicitly unknown")
	# The planned line is checked; leaving it must enable protection even with
	# all previous experimental routing flags disabled.
	pilot._aircraft_heightmap_route_job_active = false
	pilot._flight_plan_name = "recovery_approach"
	pilot.waypoints.assign([Vector3(0, 1000, 1000)])
	pilot.current_waypoint_index = 0
	pilot._flight_plan_legs.assign([{"route_primitive": "arc", "role": "recovery_arrival",
		"arc_center_xz": Vector2.ZERO, "turn_radius_m": 500.0, "arc_start_angle_rad": 0.0,
		"arc_sweep_rad": PI, "arc_turn_sign": 1.0}])
	craft.global_position = Vector3(4000, 1000, 0)
	craft.linear_velocity = Vector3(70, 0, 0)
	check(pilot._needs_recovery_capture_terrain_help(), "off-corridor protection must not depend on experimental flag")
	pilot.current_state = pilot.State.MISSED_APPROACH
	pilot._ma_escape_complete = false
	pilot.terrain_flight_path_distance = INF
	pilot._terrain_fan_clearances = PackedFloat32Array([200, 200, -50, 200, 200])
	pilot._terrain_fan_best_idx = 0
	pilot._recovery_escape_terrain_solution = {"valid": true, "desired_vs_mps": 25.0, "unreachable": true}
	check(pilot._check_terrain_avoidance(1.0 / 60.0), "sampled collision must have authority before exact ray becomes imminent")
	check(pilot._coordinated_turn_target_g > 1.0, "terrain escape must use lift feedback outside final")
	pilot.terrain_test_height = 1100.0
	craft.global_position = Vector3(0, 1000, 0)
	craft.global_basis = Basis.IDENTITY
	craft.linear_velocity = Vector3(0, 0, 90)
	craft.angular_velocity = Vector3.ZERO
	pilot._ma_escape_start_altitude_m = 900.0
	pilot._ma_escape_altitude_reached = true
	pilot._state_missed_approach(1.0 / 60.0)
	check(not pilot._ma_escape_altitude_reached and not pilot._ma_escape_complete,
		"old altitude latch must not clear a new higher ridge")
	check(pilot._coordinated_turn_desired_vertical_speed_mps >= 24.9,
		"terrain climb demand must survive normal go-around FPA cap")
	pilot.current_state = pilot.State.RECOVERY_APPROACH
	pilot.terrain_test_height = 0.0
	craft.global_basis = Basis(Vector3.BACK, deg_to_rad(147.0))
	pilot.altitude_agl = 1000.0
	pilot._state_recovery_approach(1.0 / 60.0)
	check(pilot.roll_input < 0.0 and pilot._recovery_control_owner == "entry_bank_guard",
		"inverted recovery must actively roll upright even above old low-altitude guard")
	print("RECOVERY_TERRAIN_ESCAPE_SMOKETEST %s" % ("PASS" if failures == 0 else "FAIL"))
	scene.free()
	quit(0 if failures == 0 else 1)
