extends SceneTree

const Follower = preload("res://AI/FlightPathFollower.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func solve(point: Vector3, horizon: float = 6.0) -> Dictionary:
	return Follower.solve_point_guidance(Vector3.ZERO, Vector3(0, 0, 100),
		Vector3.BACK, point, 100, 0, 65, 4.5, 45, 0.14, 1, 0, horizon)

func _run() -> void:
	for bearing in [-179.0, -90.0, -30.0, 30.0, 90.0, 179.0]:
		var direction := Vector3(sin(deg_to_rad(bearing)), 0, cos(deg_to_rad(bearing)))
		var near := solve(direction * 3000)
		var far := solve(direction * 20000)
		check(signf(far.bank_rad) == -signf(bearing), "Waypoint turn must face target")
		check(absf(near.bank_rad - far.bank_rad) < 0.001, "Distant waypoint must not weaken heading capture")
		check(absf(rad_to_deg(far.bank_rad)) >= 35.0, "Large bearing error requires a useful turn")
	var aligned := solve(Vector3(0, 0, 20000))
	check(absf(aligned.bank_rad) < 0.001, "Aligned waypoint must roll out")
	check(absf(aligned.target_load_g - 1.0) < 0.001, "Aligned level flight requires one G")
	var close := solve(Vector3(100, 0, 100))
	var legacy_close := solve(Vector3(100, 0, 100), INF)
	check(close.requested_accel_world.is_equal_approx(legacy_close.requested_accel_world),
		"Close waypoint interception retains its geometric response")
	var slope := solve(Vector3(3000, -400, 4000))
	var legacy_slope := solve(Vector3(3000, -400, 4000), INF)
	check(is_equal_approx(slope.desired_vs_mps, legacy_slope.desired_vs_mps),
		"Heading response must preserve the waypoint's vertical slope")
	var craft = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	craft.freeze = true
	root.add_child(craft)
	var pilot = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	craft.linear_velocity = Vector3(0, 0, 100)
	check(pilot._get_aircraft_route_planning_bank_limit_deg("waypoint") <= 65.0,
		"Ordinary route planning must fit the upright bank envelope")
	var planned_radius: float = pilot._estimate_aircraft_turn_radius_m(100.0)
	check(atan(10000.0 / (9.80665 * planned_radius)) < deg_to_rad(65.0),
		"Planned navigation curvature must leave bank margin")
	for state in [pilot.State.SEARCH, pilot.State.TRANSIT, pilot.State.RTB]:
		pilot.current_state = state
		pilot.formation_anchor_active = false
		var capture: Dictionary = pilot._get_3d_point_flight_path_guidance(Vector3(10000, 0, 0), 100, -1, 65)
		check(absf(rad_to_deg(capture.bank_rad)) > 55, "Ordinary waypoint modes must use bounded capture")
		pilot.formation_anchor_active = true
		var slot: Dictionary = pilot._get_3d_point_flight_path_guidance(Vector3(10000, 0, 0), 100, -1, 65)
		check(absf(slot.bank_rad) < absf(capture.bank_rad), "Formation retains its slot response")
	pilot.formation_anchor_active = false
	pilot.current_state = pilot.State.ATTACK_POSITIONING
	var attack: Dictionary = pilot._get_3d_point_flight_path_guidance(Vector3(10000, 0, 0), 100, -1, 65)
	check(absf(rad_to_deg(attack.bank_rad)) > 55, "Direct attack positioning must capture a distant bearing decisively")
	pilot.ground_attack_direct_intercept_enabled = false
	pilot.ground_attack_direct_fire_intercept_enabled = false
	for state in [pilot.State.ATTACK_POSITIONING, pilot.State.RECOVERY_APPROACH, pilot.State.RECOVERY_HOLD]:
		pilot.current_state = state
		var approach: Dictionary = pilot._get_3d_point_flight_path_guidance(Vector3(10000, 0, 0), 100, -1, 65)
		check(absf(rad_to_deg(approach.bank_rad)) < 10, "Special route guidance retains its response")
	craft.free()
	print("WAYPOINT_GUIDANCE_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
