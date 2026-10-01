extends Node

const Follower = preload("res://AI/FlightPathFollower.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for bearing in [-179.9, -150.0, 150.0, 179.9]:
		var angle := deg_to_rad(bearing)
		var result: Dictionary = Follower.solve_velocity_guidance(Vector3(0, 0, 100), Vector3.BACK,
			Vector3(sin(angle), 0, cos(angle)) * 100, 2.0, Vector3.ZERO, 0.5, 80, 4.5, 0.1, 1, 0)
		check(absf(rad_to_deg(result.bank_rad)) > 70, "Rear target must demand decisive bank")
		check(signf(result.bank_rad) == -signf(bearing), "Near-rear turn must face target")
	for side in [-1.0, 1.0]:
		var rear: Dictionary = Follower.solve_velocity_guidance(Vector3(0, 0, 100), Vector3.BACK,
			Vector3(0, 0, -100), 2.0, Vector3.ZERO, side, 80, 4.5, 0.1, 1, 0)
		check(signf(rear.bank_rad) == side and absf(rear.bank_rad) > 1.0, "Exact rear respects latched side")
	var ahead: Dictionary = Follower.solve_velocity_guidance(Vector3(0, 0, 100), Vector3.BACK,
		Vector3(0, 0, 100), 2.0, Vector3.ZERO, 0, 80, 4.5, 0.1, 1, 0)
	check(absf(ahead.bank_rad) < 0.001 and absf(ahead.target_load_g - 1) < 0.001, "Forward guidance unchanged")
	var craft := (load("res://Aircraft/Aircraft_5.tscn") as PackedScene).instantiate() as RigidBody3D
	craft.position = Vector3(0, 1000, 0)
	craft.freeze = true
	add_child(craft)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pilot: AIPilot = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	pilot.altitude_agl = 1000
	craft.linear_velocity = Vector3(0, 0, 100)
	pilot.throttle_input = 1.0
	pilot._update_dogfight_closure_throttle(1.0, craft.position + Vector3(0, 0, 250), Vector3(0, 0, 78), false)
	check(pilot.throttle_input < 0.5 and pilot.target_speed >= pilot.simple_aero.get_effective_stall_speed_mps() * 1.5, "Close chase must reduce power without demanding stall")
	pilot._update_dogfight_closure_throttle(1.0, craft.position + Vector3(0, 0, 3000), Vector3(0, 0, 110), false)
	check(pilot.throttle_input > 0.5, "Distant receding target must increase power")
	pilot._lead_track_valid = true
	pilot._lead_track_turn_rate = 0.15
	pilot._dogfight_precise_aim_blend = 1.0
	pilot._update_dogfight_closure_throttle(0.1, craft.position + Vector3(300, 0, 500), Vector3(-62, 0, 48), false)
	check(pilot.target_speed >= Vector3(-62, 0, 48).length() + 4.9, "Turning pursuit preserves capture speed instead of braking to radial speed")
	pilot._lead_track_turn_rate = 0.0
	pilot._update_dogfight_closure_throttle(0.1, craft.position + Vector3(300, 0, 500), Vector3(-62, 0, 48), false)
	check(pilot.target_speed < Vector3(-62, 0, 48).length(), "Straight crossing retains tested braking schedule")
	pilot._dogfight_precise_aim_blend = 0.0
	var first := pilot._compute_dogfight_collision_avoidance(craft.position + Vector3(0, 0, 50), Vector3(0, 0, 78), craft.position, craft.linear_velocity)
	check(first != Vector3.ZERO, "Escape fixture must actually enter hard-proximity avoidance")
	for i in 30:
		var again := pilot._compute_dogfight_collision_avoidance(craft.position + Vector3(0, 0, 100), Vector3(0, 0, 78), craft.position, craft.linear_velocity)
		check(first.distance_to(again) < 0.001, "Escape cannot reroll its side")
	pilot._dogfight_escape_remaining_s = 0.0
	check(pilot._compute_dogfight_collision_avoidance(craft.position + Vector3(0, 0, 700), Vector3(0, 0, 78), craft.position, craft.linear_velocity) != Vector3.ZERO, "Closing pass cannot release a committed escape solely by distance")
	var established_velocity := pilot._dogfight_escape_direction.normalized() * 100.0
	check(pilot._compute_dogfight_collision_avoidance(craft.position + Vector3(0, 0, 700), established_velocity + Vector3(0, 0, 30), craft.position, established_velocity) == Vector3.ZERO, "Established opening escape must release")
	pilot._update_dogfight_pursuit_energy(0.1, 50)
	check(pilot._dogfight_energy_recovering and pilot._dogfight_energy_load_limit_g <= 1.3, "Low energy must unload")
	pilot._update_dogfight_closure_throttle(0.1, craft.position + Vector3(0, 0, 100), Vector3(0, 0, 60), false)
	check(pilot.throttle_input == 1.0, "Energy recovery takes priority over range braking")
	pilot._update_dogfight_pursuit_energy(1.0, 100)
	check(not pilot._dogfight_energy_recovering, "Energy recovery exits after speed returns")
	pilot._lead_track_valid = false
	pilot.control_weapons.set("selected_weapon_type", "Guns")
	var mount := pilot._get_selected_weapon_mount_info()
	check(absf(float(mount.spread_deg) - 0.35) < 0.001, "Gun category must resolve authored spread")
	check(Vector3(mount.origin).distance_to(craft.position) > 2.0, "Gun category must use actual muzzle rather than aircraft origin")
	var origin := craft.position
	var target_pos := origin + Vector3(0, 0, 400)
	var solution := pilot._get_dogfight_aim_solution(origin, craft.linear_velocity, target_pos, Vector3(0, 0, 78), 600)
	var ideal: Vector3 = (Vector3(solution.aim_point) - origin).normalized()
	check(pilot._dogfight_has_good_fire_solution(solution.aim_point, solution.intercept_point, origin,
		craft.linear_velocity, ideal, 600, 0.35, solution.tof, 400), "Actual aligned gun may fire")
	check(not pilot._dogfight_has_good_fire_solution(solution.aim_point, solution.intercept_point, origin,
		craft.linear_velocity, ideal.rotated(Vector3.UP, deg_to_rad(2)), 600, 0.35, solution.tof, 400), "Loose angular gate cannot authorize a wide current-bore miss")
	# Accept useful partial spread overlap, while retaining the ballistic miss gate.
	var partial_bore := ideal.rotated(Vector3.UP, deg_to_rad(0.55))
	check(pilot._dogfight_has_good_fire_solution(solution.aim_point, solution.intercept_point, origin,
		craft.linear_velocity, partial_bore, 600, 0.35, solution.tof, 400), "Partial-overlap shot is worth taking")
	check(pilot._dogfight_last_hit_chance < 0.72, "Partial-overlap fixture exercises the former rejection threshold")
	for frame in 180:
		pilot._update_dogfight_burst_timers(1.0 / 60.0, true)
		check(pilot._dogfight_burst_active, "Useful solution holds trigger through former burst boundaries")
	pilot._update_dogfight_burst_timers(1.0 / 60.0, false)
	check(not pilot._dogfight_burst_active, "Lost solution releases trigger immediately")
	pilot._update_dogfight_burst_timers(1.0 / 60.0, true)
	check(pilot._dogfight_burst_active, "Reacquired solution resumes without stale cooldown")
	var moved := pilot._get_dogfight_aim_solution(origin, craft.linear_velocity, target_pos + Vector3(100, 0, 0), Vector3(0, 0, 78), 600)
	check(Vector3(moved.aim_point).distance_to(solution.aim_point) > 80, "Aim responds to new physics state without waiting for wall clock")
	pilot._lead_track_valid = true
	pilot._lead_track_turn_axis = Vector3.UP
	pilot._lead_track_turn_rate = 1.0
	check(pilot._predict_target_future_pos(Vector3.ZERO, Vector3.BACK, PI / 2).distance_to(Vector3(1, 0, 1)) < 0.001, "Curved lead integrates exact arc")
	for side in [-1.0, 1.0]:
		pilot._reset_dogfight_pursuit()
		for frame in 61:
			pilot._update_dogfight_ballistic_rate(Vector3.BACK.rotated(Vector3.UP, side * float(frame) / 600.0), 1.0 / 60.0)
		check(absf(pilot._dogfight_ballistic_rate_world.y - side * 0.1) < 0.002, "Sightline rate is measured in simulation time")
		pilot.simple_aero.current_yaw_authority = 1.0
		pilot.simple_aero.current_directional_stability_torque_nm = 0.0
		check(pilot._dogfight_precision_yaw_feedforward(Basis.IDENTITY) * side > 0.5, "Turning sight receives damping trim in correct direction")
	pilot._reset_dogfight_pursuit()
	check(pilot._dogfight_ballistic_rate_world == Vector3.ZERO, "Target/state reset clears sightline motion")
	check(AIPilot.dogfight_spread_hit_fraction(2, 0, 4, 0.5) > 0.999, "Fully contained spread is a good shot despite offset")
	check(AIPilot.dogfight_spread_hit_fraction(10, 0, 4, 1) == 0.0, "Disjoint spread cannot hit")
	check(AIPilot.dogfight_spread_hit_fraction(0, 0, 4, 12) < 0.12, "Large spread lowers confidence even with perfect aim")
	check(AIPilot.dogfight_spread_hit_fraction(3, 0, 4, 2) > 0.65, "Partial overlap is not linearly penalized center error")
	for bank in [-60.0, 60.0]:
		craft.global_basis = Basis(Vector3.BACK, deg_to_rad(bank))
		pilot._reset_dogfight_pursuit()
		var left_break := pilot._build_dogfight_collision_avoid_waypoint(Vector3(30, 0, 0), craft.position, Vector3(0, 0, 70))
		check(left_break.x < craft.position.x, "Right-side threat demands left separation regardless of current bank")
		check(left_break.y > craft.position.y, "Right-side co-altitude threat receives upward separation")
		pilot._reset_dogfight_pursuit()
		var right_break := pilot._build_dogfight_collision_avoid_waypoint(Vector3(-30, 0, 0), craft.position, Vector3(0, 0, 70))
		check(right_break.x > craft.position.x, "Left-side threat demands right separation regardless of current bank")
		check(right_break.y < craft.position.y, "Opposite-side aircraft receives opposite vertical separation")
	craft.global_basis = Basis(Vector3.BACK, deg_to_rad(-60.0))
	check(pilot._dogfight_separation_horizon(Vector3(100, 0, 500), Vector3(0, 0, 80)) > 4.5, "Bank reversal gets physical roll-in lead time")
	check(pilot._dogfight_separation_horizon(Vector3(-100, 0, 500), Vector3(0, 0, 80)) == pilot.dogfight_collision_check_horizon_s, "Existing away bank retains normal prediction horizon")
	craft.global_basis = Basis.IDENTITY
	check(pilot._dogfight_separation_horizon(Vector3(100, 0, 500), Vector3(0, 0, 80)) == pilot.dogfight_collision_check_horizon_s, "Level opening pass retains normal horizon")
	pilot._reset_dogfight_pursuit()
	check(pilot._compute_dogfight_collision_avoidance(craft.position + Vector3(0, 0, 100), Vector3(0, 0, 120), craft.position, Vector3(0, 0, 70)) == Vector3.ZERO, "Receding pass outside hard floor does not restart avoidance")
	craft.global_basis = Basis.IDENTITY
	pilot._dogfight_contact_visible = true
	pilot._dogfight_contact_age_s = 0.0
	pilot._dogfight_reset_timer_s = 0.0
	pilot._dogfight_reset_cooldown_s = 0.0
	pilot._dogfight_burst_active = false
	var stalled_point := craft.position + Vector3(200, 0, 500)
	for step in 280:
		pilot._update_dogfight_tactical_reset(0.1, stalled_point)
	check(pilot._dogfight_reset_timer_s > 0.0, "Unchanging twenty-degree error eventually requests a reset")
	pilot._reset_dogfight_pursuit()
	pilot._dogfight_reset_timer_s = 0.0
	pilot._dogfight_reset_cooldown_s = 0.0
	for step in 300:
		pilot._update_dogfight_tactical_reset(0.1, craft.position + Vector3(0, 0, 450))
	check(pilot._dogfight_reset_timer_s == 0.0, "Stable useful firing position must not trigger a reset")
	craft.free()
	print("DOGFIGHT_PURSUIT_SMOKETEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
