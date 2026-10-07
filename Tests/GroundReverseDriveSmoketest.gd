extends Node

const ReverseDrive = preload("res://GroundVehicle/ReverseDrive.gd")
var failures: Array[String] = []

class Friendly:
	extends "res://GroundVehicle/vehicle_friendly_light.gd"
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)
	func _move_vehicle_body(delta: float, _coarse: bool) -> void:
		position += velocity * delta

class Enemy:
	extends "res://GroundVehicle/vehicle_enemy_light.gd"
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)
	func _move_vehicle_body(delta: float, _coarse: bool) -> void:
		position += velocity * delta

class Carrier:
	extends "res://LandCarrier/LandCarrier.gd"
	var rear_cliff := false
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)
	func _sample_precise_terrain_y(_x: float, z: float) -> float:
		return maxf(-z - 20.0, 0.0) * 2.0 if rear_cliff else 0.0
	func _get_avoidance_steer(_direction: float = 1.0) -> float:
		return 0.0

class EscortReference extends Node3D:
	func get_velocity_vector() -> Vector3:
		return Vector3(0, 0, -4)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _ready() -> void:
	check(ReverseDrive.choose_reverse(-1.0, false), "rear destination selects reverse")
	check(ReverseDrive.choose_reverse(0.0, true), "sideways retains reverse")
	check(not ReverseDrive.choose_reverse(1.0, true), "front destination releases reverse")
	check(is_zero_approx(ReverseDrive.approach_speed(2.0, -3.0, 2.0, 4.0, 1.0)), "gear change crosses zero in one tick")
	var selector := ReverseDrive.new()
	check(not selector.choose_navigation_reverse(-1.0, 400.0, 0.1), "long journey must turn forward")
	check(selector.choose_navigation_reverse(-1.0, 10.0, 0.1), "nearby rear adjustment may reverse")
	for tick in 80:
		selector.choose_navigation_reverse(-1.0, 10.0, 0.05)
	check(not selector.choose_navigation_reverse(-1.0, 10.0, 0.1), "moving nearby goal must not allow endless reverse")
	selector.choose_navigation_reverse(1.0, 10.0, 0.1)
	check(selector.choose_navigation_reverse(-1.0, 10.0, 0.1), "forward alignment rearms short reverse")
	check(not selector.choose_navigation_reverse(-1.0, 10.0, 0.1, false), "forward-only harvester ignores short reverse")
	for v in [Friendly.new(), Enemy.new()]:
		add_child(v)
		v.use_waypoint_pathfinding = false
		var points: Array[Vector3] = [Vector3(0, 0, -400)]
		v._waypoint_positions = points
		v._refresh_drive_command(0.1)
		check(v._drive_command_throttle >= 0.0 and absf(v._drive_command_steer) > 0.9, "rear command needs decisive forward U-turn")
		for tick in 600:
			v._refresh_drive_command(0.05)
			v._apply_cached_drive_motion(0.05, true)
			check(not v._reverse_driving, "long route entered reverse")
		check(v.position.z < -250.0, "vehicle did not progress to rearward destination")
		check(v.global_basis.z.dot(Vector3.FORWARD) > 0.9, "vehicle did not turn nose-first toward rearward destination")
		# A precision parking/rescue adjustment behind the vehicle is still legal.
		v.position = Vector3.ZERO
		v.rotation = Vector3.ZERO
		v.velocity = Vector3.ZERO
		v.waypoint_reach_distance = 1.0
		if v is Friendly:
			v._arrived_at_destination = false
		v._navigation_drive.reset_navigation()
		points.assign([Vector3(0, 0, -10)])
		v._waypoint_positions = points
		v._refresh_drive_command(0.1)
		check(v._reverse_driving and v._drive_command_throttle < 0.0, "short rear command")
		for tick in 20:
			v._refresh_drive_command(0.05)
			v._apply_cached_drive_motion(0.05, true)
		check(v.position.z < -0.1, "short adjustment did not back up")
		check(absf(v.velocity.z) <= v.max_speed * v.reverse_speed_ratio + 0.01, "reverse speed exceeded cap")
		check(v.global_basis.z.dot(Vector3.BACK) > 0.99, "short straight reverse turned vehicle around")
		points.assign([v.position + v.global_basis.z * 400.0])
		v._waypoint_positions = points
		for tick in 120:
			v._refresh_drive_command(0.05)
			v._apply_cached_drive_motion(0.05, true)
		check(v.velocity.dot(v.global_basis.z) > 0.0, "vehicle did not resume forward travel")
		v._waypoint_positions.clear()
		for tick in 60:
			v._refresh_drive_command(0.05)
			v._apply_cached_drive_motion(0.05, true)
		check(v.velocity.length() < 0.01, "vehicle HOLD did not brake")
		var enemy_target := Node3D.new()
		add_child(enemy_target)
		enemy_target.position = v.position - v.global_basis.z * 400.0
		v.current_target = enemy_target
		points.assign([enemy_target.position])
		v._waypoint_positions = points
		v._refresh_drive_command(0.1)
		check(not v._reverse_driving and absf(v._drive_command_steer) > 0.5, "rearward combat route must turn forward too")
		enemy_target.free()
		v.free()
	var escort := EscortReference.new()
	add_child(escort)
	var formation := GroundVehiclePlatoon.new()
	add_child(formation)
	formation.objective_type = GroundVehiclePlatoon.ObjectiveType.ESCORT_CARRIER
	formation.escort_node = escort
	var follower := Friendly.new()
	add_child(follower)
	follower.platoon = formation
	for tick in 200:
		follower._match_formation_velocity(follower.position, 0.05, true)
	check(follower.global_basis.z.dot(Vector3.FORWARD) > 0.95, "moving escort slot must turn a backwards-facing follower")
	follower.free()
	formation.free()
	escort.free()
	var c := Carrier.new()
	add_child(c)
	c._waypoint_positions.assign([Vector3(0, 0, -400)])
	c._raw_waypoints.assign([Vector3(0, 0, -400)])
	for tick in 120:
		c._refresh_drive_command(0.05)
		c._apply_drive_motion(0.05, c._drive_target_speed_mps, c._drive_target_yaw_rate_rad_s)
	check(c.position.z < -1.0, "carrier did not reverse")
	check(absf(c._current_planar_speed_mps) <= c.max_speed * c.reverse_speed_ratio + 0.01, "carrier reverse cap")
	c._waypoint_positions.assign([c.position + Vector3(100, 0, -400)])
	var carrier_before := c.position
	for tick in 120:
		c._refresh_drive_command(0.05)
		c._apply_drive_motion(0.05, c._drive_target_speed_mps, c._drive_target_yaw_rate_rad_s)
	check(c.position.x > carrier_before.x, "carrier reverse steering sign")
	c.hold_position()
	for tick in 60:
		c._refresh_drive_command(0.05)
		c._apply_drive_motion(0.05, c._drive_target_speed_mps, c._drive_target_yaw_rate_rad_s)
	check(is_zero_approx(c._current_planar_speed_mps), "carrier HOLD while reversing")
	c.position = Vector3.ZERO
	c.rotation = Vector3.ZERO
	c._current_yaw_rate_rad_s = 0.0
	c.rear_cliff = true
	for tick in 300:
		c._apply_drive_motion(0.05, -3.0, 0.0)
	check(c.position.z > -20.0 and is_zero_approx(c._current_planar_speed_mps), "carrier backed through steep terrain")
	c.free()
	for message in failures: push_error(message)
	print("GROUND_REVERSE_DRIVE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
