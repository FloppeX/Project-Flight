extends SceneTree

class TerrainFixture:
	extends Node
	var ridge := false
	var samples := 0
	func get_height(position: Vector3) -> float:
		samples += 1
		return 1000.0 if ridge and position.z > 400.0 else 0.0

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var script: Variant = load("res://AI/AIPilot.gd")
	for direction in [-1.0, 1.0]:
		_check(script._recovery_arc_rollout_ready(20.0, 500.0, 3.0, 60.0, 60.0),
			"established tangent must retain ordinary rollout")
		_check(script._recovery_arc_rollout_ready(200.0, 500.0, 3.0, 60.0, 60.0),
			"moderate parallel offset must not force an extra orbit instead of normal rollout")
		_check(not script._recovery_arc_rollout_ready(3487.0, 500.0, 59.8, -2.4, 60.0),
			"recorded seed 20260908 case 6 must retain capture authority")
		_check(not script._recovery_arc_rollout_ready(3363.0, 500.0, 60.0, 0.0, 60.0),
			"recorded seed 20260909 case 3 must retain capture authority")
		_check(not script._recovery_arc_rollout_ready(0.0, 500.0, 0.0, -60.0, 60.0),
			"being on the circle backwards must not allow rollout")
		_check(not script._recovery_arc_rollout_ready(0.0, 500.0, 59.0, 2.0, 60.0),
			"radial travel must not allow rollout")
		var steady: float = script._recovery_arc_capture_acceleration(0.0, direction,
			60.0, 200.0, 7.2, 7.2, 60.0)
		_check(absf(steady - direction * 7.2) < 0.001, "steady circle preserves feedforward")
		var reciprocal: float = script._recovery_arc_capture_acceleration(PI, direction,
			60.0, 200.0, 7.2, 50.0, -60.0)
		_check(reciprocal * direction > 10.0, "reciprocal capture cannot produce zero steering")
		var opposite: float = script._recovery_arc_capture_acceleration(-direction * PI * 0.5,
			direction, 60.0, 200.0, 7.2, 50.0, -20.0)
		_check(opposite * direction < -10.0, "off-axis capture may steer opposite eventual circle direction")
	var short_horizon: float = script._recovery_terrain_lookahead_s(60.0, 0.0, 0.0, 0.8, 14.0, 80.0)
	var heavy_horizon: float = script._recovery_terrain_lookahead_s(60.0, 5.0, 0.8, 0.3, 6.0, 80.0)
	_check(heavy_horizon > short_horizon and heavy_horizon <= 18.0,
		"slower climb/roll and sink must lengthen the bounded terrain horizon")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var craft := RigidBody3D.new()
	craft.freeze = true
	scene.add_child(craft)
	var pilot := Node.new()
	pilot.set_script(script)
	craft.add_child(pilot)
	pilot.set_physics_process(false)
	pilot.set("aircraft", craft)
	_check(not bool(pilot.get("recovery_route_capture_experimental")) \
		and not bool(pilot.get("recovery_recapture_steering_experimental")) \
		and not bool(pilot.get("recovery_capture_terrain_experimental")),
		"unproven fleet-wide retunes must remain opt-in")
	pilot.set("recovery_capture_terrain_experimental", true)
	pilot.set("current_state", 14) # RECOVERY_APPROACH
	pilot.set("_flight_plan_name", "recovery_approach")
	var points: Array[Vector3] = [Vector3(500, 700, 0), Vector3(-500, 700, 0)]
	pilot.set("waypoints", points)
	pilot.set("current_waypoint_index", 1)
	var legs: Array[Dictionary] = [{}, {"route_primitive": "arc", "role": "recovery_arrival",
		"turn_radius_m": 500.0, "arc_center_xz": Vector2.ZERO, "arc_start_angle_rad": 0.0,
		"arc_sweep_rad": PI, "arc_turn_sign": 1.0}]
	pilot.set("_flight_plan_legs", legs)
	craft.position = Vector3(0, 700, 500)
	craft.linear_velocity = Vector3(-60, 0, 0)
	_check(pilot.call("_is_tracking_checked_recovery_corridor"), "on-circle forward travel keeps checked margin")
	craft.linear_velocity = Vector3(60, 0, 0)
	_check(not pilot.call("_is_tracking_checked_recovery_corridor"), "backwards flight loses checked margin")
	craft.position = Vector3(0, 700, 1200)
	craft.linear_velocity = Vector3(0, 0, 60)
	_check(not pilot.call("_is_tracking_checked_recovery_corridor"), "off-circle flight loses checked margin")
	pilot.set("_route_arc_progress_index", 1)
	pilot.set("_route_arc_remaining_m", 4.0)
	pilot.set("_route_arc_radial_error_m", 700.0)
	pilot.call("_update_recovery_route_progress_watchdog", 0.1)
	_check(not pilot.call("_update_recovery_route_progress_watchdog", 7.0),
		"default behavior must not activate the experimental six-second watchdog")
	_check(is_zero_approx(float(pilot.get("_recovery_route_diverging_s"))),
		"default behavior must not accumulate experimental divergence time")
	craft.position = Vector3(0, 700, 2500)
	_check(pilot.call("_update_recovery_route_progress_watchdog", 6.1),
		"gross outward departure must replan even with experimental capture disabled")
	craft.position = Vector3(0, 700, 1200)
	pilot.call("_reset_recovery_route_progress_watchdog")
	pilot.set("recovery_route_capture_experimental", true)
	pilot.call("_update_recovery_route_progress_watchdog", 0.1)
	_check(not pilot.call("_update_recovery_route_progress_watchdog", 5.0), "divergence needs persistence")
	_check(pilot.call("_update_recovery_route_progress_watchdog", 1.1), "outward departure must replan within six seconds")
	pilot.call("_reset_recovery_route_progress_watchdog")
	pilot.call("_update_recovery_route_progress_watchdog", 0.1)
	pilot.call("_update_recovery_route_progress_watchdog", 5.0)
	craft.linear_velocity = Vector3(0, 0, -60)
	_check(not pilot.call("_update_recovery_route_progress_watchdog", 2.0), "successful recapture resets divergence")
	_check(is_zero_approx(float(pilot.get("_recovery_route_diverging_s"))), "divergence timer clears during improvement")
	pilot.call("_reset_recovery_route_progress_watchdog")
	pilot.set("_route_arc_remaining_m", 1500.0)
	craft.linear_velocity = Vector3(0, 0, 60)
	pilot.call("_update_recovery_route_progress_watchdog", 0.1)
	_check(not pilot.call("_update_recovery_route_progress_watchdog", 7.0),
		"ordinary initial radial capture keeps the full-turn allowance, not the six-second exit timeout")
	_check(is_zero_approx(float(pilot.get("_recovery_route_diverging_s"))),
		"fast divergence timer must not accumulate during ordinary initial capture")
	craft.position = Vector3(0, 700, 2500)
	_check(pilot.call("_update_recovery_route_progress_watchdog", 6.1),
		"gross departure must still get the fast watchdog during the body of a turn")
	points.append(Vector3(-500, 700, -1000))
	legs.append({"role": "recovery_lineup", "route_primitive": "straight"})
	pilot.set("waypoints", points)
	pilot.set("_flight_plan_legs", legs)
	pilot.set("_route_arc_progress_rad", PI)
	craft.position = Vector3(-3500, 700, 0)
	craft.linear_velocity = Vector3(0, 0, -60)
	pilot.call("_update_route_arc_primitive_guidance", 1, false)
	_check(int(pilot.get("_route_suggested_advance_index")) == -1,
		"angular completion kilometres from exit must not advance into final")
	pilot.set("recovery_route_capture_experimental", false)
	pilot.call("_update_route_arc_primitive_guidance", 1, false)
	_check(int(pilot.get("_route_suggested_advance_index")) == 2,
		"default behavior preserves the original arc-progress handoff")
	pilot.set("recovery_route_capture_experimental", true)
	craft.position = Vector3(-500, 700, 5)
	craft.linear_velocity = Vector3(0, 0, 60)
	pilot.call("_clear_route_advance_hint")
	pilot.call("_update_route_arc_primitive_guidance", 1, false)
	_check(int(pilot.get("_route_suggested_advance_index")) == -1,
		"wrong-way endpoint travel cannot advance")
	craft.linear_velocity = Vector3(0, 0, -60)
	pilot.call("_update_route_arc_primitive_guidance", 1, false)
	_check(int(pilot.get("_route_suggested_advance_index")) == 2,
		"near-endpoint tangent travel must hand off without another orbit")
	var terrain := TerrainFixture.new()
	scene.add_child(terrain)
	pilot.set("_terrain_height_callable", Callable(terrain, "get_height"))
	craft.position = Vector3(2000, 700, 0)
	craft.linear_velocity = Vector3(0, -30, 60)
	pilot.call("_evaluate_terrain_fan")
	var clearances: PackedFloat32Array = pilot.get("_terrain_fan_clearances")
	_check(clearances[2] > 500.0, "long forecast must allow achievable recovery from a planned descent")
	_check(terrain.samples == 28, "off-corridor response profile adds eight terrain samples")
	terrain.ridge = true
	pilot.call("_evaluate_terrain_fan")
	clearances = pilot.get("_terrain_fan_clearances")
	_check(clearances[2] < 0.0, "ridge beyond the short fan must be detected against the escape envelope")
	craft.position = Vector3(0, 700, 500)
	craft.linear_velocity = Vector3(-60, 0, 0)
	terrain.samples = 0
	pilot.call("_evaluate_terrain_fan")
	_check(terrain.samples == 20, "checked corridor keeps original fan cost and approach behavior")
	craft.position = Vector3(0, 700, 650)
	_check(pilot.call("_needs_recovery_capture_terrain_help"),
		"150m arc offset must not inherit reduced clearance from a sampled centerline")
	craft.position = Vector3(0, 700, 500)
	pilot.set("altitude_agl", 300.0)
	pilot.set("terrain_ahead_distance", INF)
	pilot.set("terrain_flight_path_distance", INF)
	pilot.set("_terrain_fan_clearances", PackedFloat32Array([100, 100, 100, 100, 100]))
	_check(not pilot.call("_check_terrain_avoidance", 0.016),
		"checked corridor keeps ordinary terrain behavior")
	_check(float(pilot.get("_recovery_terrain_vs_floor_mps")) == -INF,
		"checked arrival retains its smaller clearance without a false climb cue")
	craft.position = Vector3(2000, 700, 0)
	pilot.set("terrain_ahead_distance", 1.0) # Downward-only false positive off corridor.
	_check(not pilot.call("_check_terrain_avoidance", 0.016),
		"off-corridor margin warning must preserve turn authority")
	_check(float(pilot.get("_recovery_terrain_vs_floor_mps")) > 0.0,
		"off-corridor warning must request a shared-vector climb")
	craft.linear_velocity = Vector3(0, -16, 60)
	pilot.call("_check_terrain_avoidance", 0.016)
	_check(float(pilot.get("_recovery_terrain_vs_floor_mps")) < 14.0,
		"clearance correction must include current sink rather than demand a full climb step")
	pilot.set("terrain_flight_path_distance", 30.0)
	_check(pilot.call("_check_terrain_avoidance", 0.016),
		"real imminent terrain intersection retains hard override authority")
	_check(float(pilot.get("_recovery_terrain_vs_floor_mps")) == -INF,
		"soft climb floor resets when emergency override takes control")
	legs[1]["role"] = "recovery_transit"
	pilot.set("_flight_plan_legs", legs)
	_check(pilot.call("_needs_recovery_capture_terrain_help"),
		"off-corridor recovery transit needs the same response-aware terrain check")
	craft.position = Vector3(0, 700, 500)
	craft.linear_velocity = Vector3(-60, 0, 0)
	_check(not pilot.call("_needs_recovery_capture_terrain_help"),
		"on-corridor transit retains ordinary terrain sampling")
	legs[1]["role"] = "recovery_arrival"
	pilot.set("_flight_plan_legs", legs)
	pilot.set("current_state", 17) # MISSED_APPROACH
	_check(not pilot.call("_needs_recovery_capture_terrain_help"),
		"bolter behavior must remain outside the capture terrain extension")
	pilot.set("current_state", script.State.PRE_LANDING)
	craft.basis = Basis.IDENTITY
	craft.linear_velocity = Vector3(0, -5, 60)
	pilot.set("_smoothed_fpa_pitch", 0.0)
	pilot.set("_recovery_terrain_vs_floor_mps", -INF)
	pilot.call("_apply_approach_path_vertical_guidance", craft.position + Vector3(0, -300, 500))
	var descent_input: float = pilot.get("pitch_input")
	pilot.set("_smoothed_fpa_pitch", 0.0)
	pilot.set("_recovery_terrain_vs_floor_mps", 15.0)
	pilot.call("_apply_approach_path_vertical_guidance", craft.position + Vector3(0, -300, 500))
	_check(float(pilot.get("pitch_input")) > maxf(descent_input, 0.0),
		"pre-landing FPA controller must preserve the terrain climb floor")
	pilot.set("_smoothed_fpa_pitch", 0.0)
	pilot.set("_recovery_terrain_vs_floor_mps", -INF)
	pilot.call("_apply_approach_path_vertical_guidance", craft.position + Vector3(0, -300, 500))
	_check(is_equal_approx(float(pilot.get("pitch_input")), descent_input),
		"ordinary glideslope command resumes when the terrain constraint clears")
	scene.free()
	print("RECOVERY_ROUTE_CAPTURE_SMOKETEST %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
