extends Node3D

var failures := 0
var checks := 0

class Target:
	extends Node3D
	var current_health := 100.0
	var team := 2
	var is_dummy := false
	func get_team() -> int:
		return team

class FlightFixture:
	extends Flight
	var contacts: Array[Node3D] = []
	func _get_cas_target_nodes() -> Array[Node3D]:
		return contacts

class BombPilotFixture:
	extends AIPilot
	var drops := 0
	func _drop_one_bomb(_target_pos: Vector3 = Vector3.ZERO, _predicted: Vector3 = Vector3.ZERO) -> bool:
		drops += 1
		return true

class AxisPilotFixture:
	extends AIPilot
	func _navigate_to_waypoint(_delta: float) -> void:
		pass # Exercise real state transitions, without moving the frozen fixture.

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _flat_ground(_pos: Vector3) -> float:
	return 0.0

func _ridge_ground(pos: Vector3) -> float:
	return 260.0 if absf(pos.x) < 1500.0 and pos.z > 600.0 and pos.z < 1000.0 else 0.0

func _blocked_ground(_pos: Vector3) -> float:
	return 5000.0

func _unknown_ground(_pos: Vector3) -> float:
	return NAN

func _run() -> void:
	var craft := RigidBody3D.new()
	craft.freeze = true
	add_child(craft)
	craft.position = Vector3(0, 500, -2500)
	craft.linear_velocity = Vector3(0, 0, 100)
	var pilot := AIPilot.new()
	pilot.name = "AIPilot"
	craft.add_child(pilot)
	pilot.set_physics_process(false)
	pilot.aircraft = craft
	pilot._terrain_height_callable = _flat_ground
	pilot.current_state = AIPilot.State.ATTACK_POSITIONING
	# Isolate the handoff, not the expensive pose-curve generator.
	pilot.ground_attack_compact_ingress_enabled = true
	_check(pilot._get_aircraft_heightmap_grid_snapshot().is_empty(), "Fixture must have no terrain navigation grid")
	for weapon in ["Guns", "Rocket Pod", "Bomb"]:
		pilot._run_weapon_type = weapon
		pilot._set_ground_attack_flight_plan(Vector3(0, 400, -1400), Vector3.ZERO,
			Vector3(0, 500, 1700), Vector3(0, 400, -1900))
		var roles: Array = pilot._flight_plan_legs.map(func(leg): return leg.role)
		_check(not pilot._aircraft_heightmap_route_job_active, "Unavailable grid must not pretend a job was queued")
		_check(roles.has("attack_setup") and roles.has("attack_target") and roles.has("attack_egress"),
			"No-grid fallback must retain setup, target and egress for " + weapon)
		_check(pilot._flight_plan_legs.back().position == Vector3(0, 500, 1700), "Fallback retains its real egress")
	var depot := Target.new()
	add_child(depot)
	depot.add_to_group("buildings")
	depot.position = Vector3(0, 0, -1800)
	var threat := Target.new()
	add_child(threat)
	threat.add_to_group("gun_emplacements")
	threat.position = Vector3(0, 0, 1000)
	pilot.known_enemies.assign([depot, threat])
	_check(pilot._find_ground_attack_target() == threat, "Known threat outranks a much closer depot")
	threat.current_health = 0
	_check(pilot._find_ground_attack_target() == depot, "Destroyed threat cannot pin selection")
	threat.current_health = 100
	threat.team = 1
	_check(pilot._find_ground_attack_target() == depot, "Friendly emplacement must never be selected")
	threat.team = 2
	threat.is_dummy = true
	_check(pilot._get_ground_target_threat_tier(threat) == 1, "Explicit unarmed dummy is not an active threat")
	pilot.known_enemies.assign([depot])
	threat.is_dummy = false
	_check(pilot._find_ground_attack_target() == depot, "Unknown threat is not acquired through omniscient global search")
	pilot.known_enemies.clear()
	_check(pilot._find_ground_attack_target() == null, "Empty target list remains empty")
	# Recovery prediction is not weakened by direct interception or threat priority.
	pilot.altitude_agl = 70.0
	craft.position = Vector3(0, 70, -700)
	craft.linear_velocity = Vector3(0, -65, 100)
	_check(not pilot._evaluate_attack_recovery_clearance().safe, "A steep low attack still fails the physical pull-out gate")
	var flight := FlightFixture.new()
	add_child(flight)
	flight.set_process(false)
	flight._cas_area_center = Vector3.ZERO
	flight._cas_area_radius = 5000
	flight.contacts.assign([depot, threat])
	_check(flight._pick_unclaimed_target(craft.position) == threat, "CAS assignment shares pilot threat priority")
	flight._claimed_targets[threat] = craft
	_check(flight._pick_unclaimed_target(craft.position) == depot, "CAS preserves separate friendly claims")
	threat.current_health = 0
	flight._prune_stale_claims(false)
	_check(flight._claimed_targets.is_empty(), "Destroyed but retained target releases its claim")
	_check(flight._pick_unclaimed_target(craft.position) == depot, "CAS excludes destroyed targets")
	threat.current_health = 100
	flight._members.append(craft)
	pilot.current_state = AIPilot.State.ATTACK_BREAK_OFF
	pilot.combat_target = depot
	flight._update_cas_assignments()
	_check(pilot.current_state == AIPilot.State.ATTACK_BREAK_OFF and pilot.combat_target == depot,
		"Automatic CAS assignment cannot cancel a physical pull-out")
	var rate := pilot._direct_intercept_track_rate_command(Vector3(100, 0, 100), Vector3(0, 0, 100), 2.0)
	_check(is_equal_approx(rate, PI / 8.0 + 0.5), "Offset intercept includes target-bearing motion")
	_check(is_equal_approx(pilot._direct_intercept_track_rate_command(Vector3(-100, 0, 100), Vector3(0, 0, 100), 2.0), -rate),
		"Intercept steering mirrors left and right")
	_check(is_zero_approx(pilot._direct_intercept_track_rate_command(Vector3(0, 0, 100), Vector3(0, 0, 100), 2.0)),
		"Aligned flight path requests no turn")
	_check(is_zero_approx(pilot._direct_intercept_track_rate_command(Vector3.ZERO, Vector3.ZERO, 0.0)),
		"Degenerate intercept stays finite")
	var axis := Vector3(0, 0, 1)
	var guidance := pilot._ground_attack_axis_guidance(Vector3(0, 400, -2200), Vector3(0, 0, -100), Vector3.ZERO, axis, 400)
	_check(not guidance.captured and is_equal_approx(guidance.heading_deg, 180.0),
		"Reaching the staging point outbound does not capture the attack axis")
	_check(absf(guidance.rate) > 0.5, "Tail-first arrival requests a real reversal")
	guidance = pilot._ground_attack_axis_guidance(Vector3(200, 400, -2200), Vector3(0, 0, 100), Vector3.ZERO, axis, 400)
	_check(guidance.rate < 0.0 and not guidance.captured, "Parallel offset flight closes toward the axis without early capture")
	var mirrored := pilot._ground_attack_axis_guidance(Vector3(-200, 400, -2200), Vector3(0, 0, 100), Vector3.ZERO, axis, 400)
	_check(is_equal_approx(guidance.rate, -mirrored.rate), "Line capture mirrors correctly")
	guidance = pilot._ground_attack_axis_guidance(Vector3(0, 400, -1600), Vector3(0, 0, 100), Vector3.ZERO, axis, 400)
	_check(guidance.captured and is_zero_approx(guidance.rate), "Settled inbound aircraft captures with no spurious turn")
	guidance = pilot._ground_attack_axis_guidance(Vector3(0, 400, 100), Vector3(0, 0, 100), Vector3.ZERO, axis, 400)
	_check(not guidance.captured, "The far side of the target is not a captured approach")
	guidance = pilot._ground_attack_axis_guidance(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 0)
	_check(not guidance.valid and not guidance.captured and is_finite(guidance.rate), "Degenerate line guidance fails closed")
	pilot._cached_bomb_blast_radius_m = 30.0
	_check(pilot._bomb_solution_can_damage_target(12.0), "Useful bomb solution remains releasable")
	_check(not pilot._bomb_solution_can_damage_target(100.0), "Proximity cannot make a known wide bomb miss useful")
	_check(not pilot._bomb_solution_can_damage_target(INF), "Missing bomb prediction is not an accurate solution")
	var bomber := BombPilotFixture.new()
	craft.add_child(bomber)
	bomber.set_physics_process(false)
	bomber.aircraft = craft
	bomber.debug_enabled = false
	bomber._bombs_to_drop_this_run = 2
	bomber.bomb_gameplay_release_enabled = true
	bomber.bomb_gameplay_force_release_range_m = 500.0
	craft.position = Vector3(0, 300, -400)
	craft.linear_velocity = Vector3(0, -40, 100)
	bomber._handle_bomb_release_run(Vector3.ZERO, Vector3.ZERO, Vector3(100, 0, 0))
	_check(bomber.drops == 0 and bomber.get_last_bomb_release_block_reason() == "ccip_miss",
		"Real proximity-fallback handler withholds a known 100 m miss")
	bomber._handle_bomb_release_run(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	_check(bomber.drops == 0, "Real release handler does not drop without a prediction")
	bomber._handle_bomb_release_run(Vector3.ZERO, Vector3.ZERO, Vector3(12, 0, 0))
	_check(bomber.drops == 1, "Real release handler still acts on a useful close solution")
	pilot._terrain_height_callable = _ridge_ground
	craft.position = Vector3(0, 400, 1800)
	craft.linear_velocity = Vector3(0, 0, -100)
	for weapon in ["Guns", "Bomb", "Rocket Pod"]:
		pilot._run_weapon_type = weapon
		var staging := pilot._find_clear_ground_attack_staging_point(Vector3.ZERO, 400.0)
		_check(staging != Vector3.INF, "A ridge must leave a discoverable side approach for " + weapon)
		if staging != Vector3.INF:
			var direction := Vector3(staging.x, 0, staging.z).normalized()
			var entry := direction * pilot.ground_attack_direct_intercept_commit_range_m
			entry.y = staging.y
			var egress := pilot._pick_attack_egress_waypoint(Vector3.ZERO, entry, staging.y)
			var obstruction: float = pilot._score_rocket_attack_corridor_obstruction(entry, Vector3.ZERO) \
				if weapon == "Rocket Pod" else pilot._score_attack_run_corridor_obstruction(entry, Vector3.ZERO, egress)
			_check(is_zero_approx(obstruction), "Selected side approach passes real weapon corridor validation")
	pilot._terrain_height_callable = _blocked_ground
	_check(pilot._find_clear_ground_attack_staging_point(Vector3.ZERO, 400.0) == Vector3.INF,
		"No clear attack axis must not fabricate a safe corridor")
	var aligner := AxisPilotFixture.new()
	craft.add_child(aligner)
	aligner.set_physics_process(false)
	aligner.aircraft = craft
	aligner.debug_enabled = false
	aligner._terrain_height_callable = _flat_ground
	aligner._bomb_run_altitude_m = 400
	aligner._run_weapon_type = "Bomb"
	aligner.current_state = AIPilot.State.ATTACK_POSITIONING
	aligner._direct_intercept_axis_direction = Vector3(0, 0, 1)
	aligner._direct_intercept_staging_waypoint = Vector3(0, 400, -2400)
	craft.position = aligner._direct_intercept_staging_waypoint
	craft.linear_velocity = Vector3(0, 0, -100)
	aligner._state_direct_ground_attack_intercept(0.016, depot, Vector3.ZERO)
	_check(aligner._direct_intercept_axis_joining and aligner._direct_intercept_staging_waypoint != Vector3.INF,
		"Actual state enters alignment, not capture, on an outbound staging arrival")
	craft.position = Vector3(30, 400, -1300)
	craft.linear_velocity = Vector3(0, 0, 100)
	aligner._state_direct_ground_attack_intercept(0.016, depot, Vector3.ZERO)
	_check(aligner._direct_intercept_staging_waypoint == Vector3.INF and aligner.get_attack_last_commit_reason() == "clear_axis_captured",
		"Actual state accepts alignment inside the outer 1400 m window with a useful lane remaining")
	_check(aligner._direct_intercept_axis_joining, "Capturing does not throw away the chosen line guidance")
	_check(is_equal_approx(aligner._ground_attack_axis_min_lane_m(), 900.0), "Bomb alignment deadline uses its existing minimum useful lane")
	_check(aligner._ground_attack_axis_reached_join_plane(Vector3(500, 400, -2400), Vector3(0, 400, -2400), Vector3(0, 0, 1), 260),
		"Passing 500 m abeam of staging starts alignment rather than orbiting back to a point")
	_check(not aligner._ground_attack_axis_reached_join_plane(Vector3(0, 400, -1900), Vector3(0, 400, -2400), Vector3(0, 0, 1), 260),
		"An outbound aircraft still inside the staging plane continues to gain space")
	_check(not aligner._ground_attack_axis_reached_join_plane(Vector3.ZERO, Vector3.INF, Vector3.ZERO, 260),
		"Missing staging geometry does not start line capture")
	_check(aligner._direct_intercept_axis_guidance_active, "The alignment navigation call owns line guidance")
	aligner._direct_intercept_extension_waypoint = Vector3(0, 400, -4000)
	aligner._state_direct_ground_attack_intercept(0.016, depot, Vector3.ZERO)
	_check(not aligner._direct_intercept_axis_guidance_active, "An extension leg is not overridden by a retained attack axis")
	aligner._setup_direct_ground_attack_intercept(Vector3.ZERO)
	_check(aligner._direct_intercept_axis_direction == Vector3.ZERO and not aligner._direct_intercept_axis_joining,
		"A fresh direct approach clears stale alternate alignment state")
	_check(aligner._direct_intercept_entry_waypoint == Vector3.INF and is_zero_approx(aligner._direct_intercept_entry_range_m),
		"A fresh direct approach clears the old entry pose")
	aligner._run_weapon_type = "Guns"
	var low_entry := aligner._ground_attack_entry_range_for_height(300, 100)
	var high_entry := aligner._ground_attack_entry_range_for_height(550, 100)
	_check(high_entry > low_entry and high_entry > 1900, "A high gun entry reserves descent distance before aiming")
	_check(aligner._ground_attack_entry_range_for_height(300, 200) > low_entry, "A faster entry reserves aiming time")
	_check(aligner._ground_attack_axis_settling_distance(600, 100) > aligner._ground_attack_axis_settling_distance(300, 100),
		"Larger airframe turns retain more line-settling distance")
	aligner._terrain_height_callable = _ridge_ground
	var short_entry := Vector3(0, 300, -1400)
	var short_join := aligner._ground_attack_short_join_prediction(Vector3(0, 300, -2400),
		Vector3(0, 0, 110), Vector3.ZERO, Vector3(0, 0, 1), short_entry, 450)
	_check(not short_join.is_empty(), "Already aligned aircraft can skip distant staging with entry reserve")
	_check(aligner._ground_attack_short_join_prediction(Vector3(0, 300, -1500),
		Vector3(0, 0, 110), Vector3.ZERO, Vector3(0, 0, 1), short_entry, 450).is_empty(),
		"A short join cannot spend the entry settling reserve")
	_check(aligner._ground_attack_short_join_prediction(Vector3(0, 1000, -2400),
		Vector3(0, 0, 110), Vector3.ZERO, Vector3(0, 0, 1), short_entry, 450).is_empty(),
		"Aligned but much too high does not qualify as a reachable entry pose")
	_check(aligner._ground_attack_short_join_prediction(Vector3.ZERO, Vector3.ZERO,
		Vector3.ZERO, Vector3.ZERO, Vector3.INF, 0).is_empty(), "Invalid short-join geometry fails closed")
	_check(aligner._ground_attack_short_join_prediction(Vector3(0, 300, -2400), Vector3(0, 50, 0),
		Vector3.ZERO, Vector3(0, 0, 1), short_entry, 450).is_empty(), "Vertical-only motion has no usable ground track")
	var left_join := aligner._ground_attack_short_join_prediction(Vector3(500, 300, -4000),
		Vector3(110, 0, 0), Vector3.ZERO, Vector3(0, 0, 1), short_entry, 450)
	var right_join := aligner._ground_attack_short_join_prediction(Vector3(-500, 300, -4000),
		Vector3(-110, 0, 0), Vector3.ZERO, Vector3(0, 0, 1), short_entry, 450)
	_check(not left_join.is_empty() and left_join == right_join, "Short-join prediction mirrors left and right turns")
	aligner._terrain_height_callable = _flat_ground
	aligner._run_weapon_type = "Guns"
	aligner._direct_intercept_staging_waypoint = Vector3(0, 300, -4000)
	aligner._direct_intercept_entry_waypoint = short_entry
	aligner._direct_intercept_axis_direction = Vector3(0, 0, 1)
	aligner._attack_setup_target_pos = Vector3.ZERO
	aligner._ground_attack_short_join_check_s = 0.0
	craft.position = Vector3(0, 300, -2400)
	craft.linear_velocity = Vector3(0, 0, 110)
	aligner._state_direct_ground_attack_intercept(0.016, depot, Vector3.ZERO)
	_check(aligner._direct_intercept_axis_joining and aligner._ground_attack_short_join_count == 1,
		"Actual navigation skips outbound staging when the entry pose is already reachable")
	_check(aligner._direct_intercept_axis_guidance_active and aligner.nav_waypoint == short_entry,
		"Short join still steers through the planned entry altitude and attack line")
	aligner._setup_direct_ground_attack_intercept(Vector3.ZERO)
	_check(is_zero_approx(aligner._ground_attack_short_join_check_s), "Fresh approach resets short-join check cadence")
	aligner._run_weapon_type = "Rocket Pod"
	aligner._direct_intercept_staging_waypoint = Vector3(0, 300, -4000)
	aligner._direct_intercept_entry_waypoint = short_entry
	aligner._direct_intercept_axis_direction = Vector3(0, 0, 1)
	aligner._state_direct_ground_attack_intercept(0.016, depot, Vector3.ZERO)
	_check(not aligner._direct_intercept_axis_joining and not aligner._direct_intercept_axis_guidance_active,
		"Rocket navigation retains its validated staging while shorter-join salvo accuracy is unresolved")
	_check(aligner.nav_waypoint == aligner._direct_intercept_staging_waypoint,
		"Rocket fallback flies to its real staging waypoint rather than bypassing entry geometry")
	aligner._terrain_height_callable = _ridge_ground
	craft.position = Vector3(0, 500, 1800)
	craft.linear_velocity = Vector3(0, 0, -100)
	for weapon in ["Guns", "Bomb", "Rocket Pod"]:
		aligner._run_weapon_type = weapon
		var pose := aligner._find_ground_attack_entry_pose(Vector3.ZERO, 400)
		_check(not pose.is_empty(), "Entry pose search retains a feasible ridge corridor for " + weapon)
		if not pose.is_empty():
			var obstruction: float = aligner._score_rocket_attack_corridor_obstruction(pose.entry, Vector3.ZERO) \
				if weapon == "Rocket Pod" else aligner._score_attack_run_corridor_obstruction(pose.entry, Vector3.ZERO, pose.egress)
			_check(is_zero_approx(obstruction), "The actual planned entry, not a nominal point, clears the weapon corridor")
			_check(pose.staging.distance_to(pose.entry) > pose.settling_m, "Entry has a separate turn and settling leg")
	# A target-level rejection cannot permanently block a now-clear approach.
	craft.position = Vector3(0, 500, -3000)
	craft.linear_velocity = Vector3(0, 0, 110)
	aligner._terrain_height_callable = _flat_ground
	aligner.combat_target = depot
	aligner.ground_attack_alternate_axis_enabled = true
	for weapon in ["Guns", "Bomb", "Rocket Pod"]:
		aligner._run_weapon_type = weapon
		_check(not aligner._find_ground_attack_direct_reentry_pose(Vector3.ZERO, 400).is_empty(),
			"Flat direct entry is revalidated for " + weapon)
		aligner._direct_intercept_blocked_target_id = depot.get_instance_id()
		var prior_revalidations: int = aligner._ground_attack_direct_revalidation_count
		var prior_commits: int = aligner._attack_commit_count
		aligner._setup_direct_ground_attack_intercept(Vector3.ZERO)
		_check(aligner._ground_attack_direct_revalidation_count == prior_revalidations + 1 \
			and aligner._direct_intercept_staging_waypoint == Vector3.INF,
			"Clear re-entry avoids alternate staging for " + weapon)
		_check(aligner._attack_commit_count == prior_commits and aligner._direct_intercept_blocked_target_id == 0,
			"Revalidation consumes old rejection without authorizing attack commitment")
		_check(is_equal_approx(aligner.nav_waypoint.y, aligner._direct_intercept_entry_waypoint.y) \
			and is_equal_approx(aligner._direct_intercept_entry_range_m,
				aligner._ground_attack_entry_range_for_height(aligner.nav_waypoint.y, 110.0)),
			"Revalidation retains both the accepted height and its required acquisition range")
	aligner._terrain_height_callable = _ridge_ground
	craft.position = Vector3(0, 500, 1800)
	for weapon in ["Guns", "Bomb", "Rocket Pod"]:
		aligner._run_weapon_type = weapon
		var reentry := aligner._find_ground_attack_direct_reentry_pose(Vector3.ZERO, 400)
		if weapon == "Rocket Pod" and not reentry.is_empty():
			_check(reentry.entry.y > 400 and is_zero_approx(aligner._score_rocket_attack_corridor_obstruction(reentry.entry, Vector3.ZERO)),
				"Rocket revalidation over the ridge retains its actually clear higher entry")
		else:
			_check(reentry.is_empty(), "A still-blocked ridge approach is not revalidated for " + weapon)
	aligner._terrain_height_callable = _blocked_ground
	for weapon in ["Guns", "Bomb", "Rocket Pod"]:
		aligner._run_weapon_type = weapon
		_check(aligner._find_ground_attack_direct_reentry_pose(Vector3.ZERO, 400).is_empty(),
			"An obstructed entry for every candidate height remains blocked for " + weapon)
	aligner._terrain_height_callable = _unknown_ground
	_check(aligner._find_ground_attack_direct_reentry_pose(Vector3.ZERO, 400).is_empty(),
		"Unknown entry terrain cannot erase the old rejection")
	aligner._terrain_height_callable = _flat_ground
	_check(aligner._find_ground_attack_direct_reentry_pose(craft.global_position, 400).is_empty(),
		"Degenerate direct bearing cannot be revalidated")
	craft.position = Vector3(0, 500, -600)
	craft.rotation.y = PI
	craft.linear_velocity = Vector3(0, 0, -110)
	aligner._run_weapon_type = "Guns"
	aligner._direct_intercept_blocked_target_id = depot.get_instance_id()
	aligner._setup_direct_ground_attack_intercept(Vector3.ZERO)
	aligner._state_direct_ground_attack_intercept(0.016, depot, Vector3.ZERO)
	_check(aligner._direct_intercept_extension_waypoint != Vector3.INF,
		"Revalidated corridor still uses the normal extension when a reversal lacks turn space")
	craft.rotation = Vector3.ZERO
	craft.position = Vector3(0, 500, -3000)
	craft.linear_velocity = Vector3(0, 0, 110)
	aligner.ground_attack_direct_revalidation_enabled = false
	aligner._direct_intercept_blocked_target_id = depot.get_instance_id()
	aligner._setup_direct_ground_attack_intercept(Vector3.ZERO)
	_check(aligner._direct_intercept_staging_waypoint != Vector3.INF,
		"Comparison switch retains the prior alternate-entry search")
	aligner._attack_setup_target_pos = Vector3(10, 0, 20)
	aligner._direct_intercept_entry_waypoint = Vector3(10, 300, -1380)
	_check(aligner._ground_attack_entry_nav_point(Vector3(110, 0, 20), 500) == Vector3(110, 300, -1380),
		"Entry guidance and live target share one translated line origin")
	aligner.apply_origin_shift(Vector3(1000, 0, -500))
	_check(aligner._direct_intercept_entry_waypoint == Vector3(-990, 300, -880), "Floating-origin shift rebases the entry pose")
	aligner.ground_attack_alternate_axis_enabled = false
	aligner._terrain_height_callable = _flat_ground
	aligner._run_weapon_type = "Guns"
	craft.position = Vector3(0, 300, -2600)
	craft.rotation = Vector3.ZERO
	craft.linear_velocity = Vector3(0, 0, 110)
	aligner._setup_direct_ground_attack_intercept(Vector3.ZERO)
	var entry := Vector3(0, aligner._bomb_run_altitude_m, -1400)
	_check(is_zero_approx(aligner._score_attack_run_corridor_obstruction(entry, Vector3.ZERO, aligner._attack_egress_waypoint)),
		"Direct gun setup clears its own commit corridor even from a low initial altitude")
	craft.position = Vector3(0, 1400, -2600)
	aligner.current_state = AIPilot.State.ATTACK_POSITIONING
	aligner._setup_direct_ground_attack_intercept(Vector3.ZERO)
	var commits_before_descent := aligner._attack_commit_count
	aligner._state_direct_ground_attack_intercept(0.016, depot, Vector3.ZERO)
	_check(aligner._direct_intercept_extension_waypoint != Vector3.INF \
		and aligner._attack_commit_count == commits_before_descent,
		"A high close approach establishes descent room instead of committing a no-shot dive")
	craft.position = Vector3(0, 600, -1400)
	aligner._run_weapon_type = "Bomb"
	aligner.current_state = AIPilot.State.ATTACK_POSITIONING
	aligner._setup_direct_ground_attack_intercept(Vector3.ZERO)
	aligner._state_direct_ground_attack_intercept(0.016, depot, Vector3.ZERO)
	_check(aligner._direct_intercept_extension_waypoint == Vector3.INF \
		and aligner._attack_commit_count > commits_before_descent,
		"A viable bomb entry does not inherit the shallow direct-fire descent restriction")
	aligner._gun_ccip_yaw_integral = 0.2
	aligner._clear_gun_ccip_aim_error()
	_check(is_zero_approx(aligner._gun_ccip_yaw_integral), "Losing the gun impact solution clears accumulated aim correction")
	print("GROUND_ATTACK_PLAN_SMOKETEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
