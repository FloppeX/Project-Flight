extends CharacterBody3D
class_name VehicleFriendlyLight

signal destroyed(vehicle)

# --- Movement ---
@export var max_speed: float = 15.0
@export var acceleration: float = 12.0
@export var turn_speed: float = 1.8
@export var max_steering_angle: float = 0.5
@export var chassis_height_smoothing: float = 30.0
@export var chassis_rotation_smoothing: float = 20.0
@export var chassis_ride_height_m: float = 1.72
@export var wheel_suspension_smoothing: float = 12.0
@export var wheel_visual_travel_m: float = 0.55
@export var wheel_probe_up_m: float = 2.0
@export var wheel_probe_down_m: float = 8.0
@export var wheel_support_smoothing: float = 10.0

# --- Waypoints ---
@export var waypoints: Array[NodePath] = []
@export var loop_waypoints: bool = true
@export var waypoint_reach_distance: float = 8.0
@export var use_waypoint_pathfinding: bool = true
@export var path_waypoint_reach_distance: float = 18.0
@export var path_replan_interval_s: float = 1.0
@export var path_goal_repath_distance_m: float = 80.0
@export var path_stuck_timeout_s: float = 4.0
@export var path_max_segment_m: float = 600.0
@export var path_min_clearance_m: float = 0.0
@export var path_retry_cooldown_s: float = 3.0
@export var path_no_anchor_retry_cooldown_s: float = 6.0

# --- Combat ---
@export var max_health: float = 50.0
@export var team: int = 1
@export var turret_range: float = 750.0
@export var burst_length: float = 1.5
@export var delay_length: float = 3.0
@export var turret_weapon: PackedScene
@export var aim_skill: float = 0.75
@export var platoon_min_neighbor_distance_m: float = 30.0
@export var platoon_rejoin_distance_m: float = 80.0
@export var preferred_vehicle_spacing_min_m: float = 30.0
@export var preferred_vehicle_spacing_max_m: float = 80.0
@export var shoot_and_scoot_enabled: bool = false
@export var fire_position_hold_s: float = 2.0
@export var scoot_move_s: float = 3.0
@export var scoot_distance_m: float = 35.0
@export var combat_hold_distance_m: float = 320.0
@export var combat_stop_distance_m: float = 220.0
@export var combat_creep_speed_mps: float = 4.0
@export var combat_track_angle_deg: float = 18.0

# State
var current_health: float
var is_dying: bool = false
var turret_controller: TurretController
var current_target: Node3D
var platoon: GroundVehiclePlatoon = null
var _combat_hold_timer_s: float = 0.0
var _combat_is_scooting: bool = false
var _combat_scoot_destination: Vector3 = Vector3.ZERO
var _had_combat_target_last_frame: bool = false

var _waypoint_positions: Array[Vector3] = []
var _waypoint_index: int = 0
var _nav_path_positions: Array[Vector3] = []
var _nav_path_index: int = 0
var _nav_path_goal: Vector3 = Vector3.ZERO
var _nav_repath_timer_s: float = 0.0
var _nav_stuck_timer_s: float = 0.0
var _nav_prev_wp_distance: float = INF
var _nav_retry_cooldown_s: float = 0.0

var _front_wheels: Array[Node3D] = []
var _body_node: Node3D
var _all_wheel_nodes: Array[Node3D] = []
var _wheel_contact_nodes: Array[Node3D] = []
var _wheel_nominal_positions: Array[Vector3] = []
var _wheel_contact_local_positions: Array[Vector3] = []
var _wheel_support_points_world: Array[Vector3] = []
var _wheel_support_normals: Array[Vector3] = []
var _wheel_support_initialized: Array[bool] = []
var _body_rest_position: Vector3 = Vector3.ZERO
var _body_rest_rotation: Vector3 = Vector3.ZERO

const GRAVITY: float = 25.0
const WHEEL_RADIUS: float = 0.4
func _ready() -> void:
	current_health = max_health
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)
	add_to_group("friendlies")
	add_to_group("ground_vehicles")
	add_to_group("team_" + str(team))
	_resolve_waypoints()
	_collect_wheel_nodes()

	turret_controller = _find_turret_controller()

	if not turret_controller:
		push_warning("VehicleFriendlyLight: No TurretController found as child!")
	else:
		turret_controller.team = team
		turret_controller.max_range = turret_range
		turret_controller.burst_length = burst_length
		turret_controller.delay_length = minf(delay_length, 0.35)
		turret_controller.aim_skill = aim_skill
		turret_controller.fire_angle_tolerance_deg = maxf(turret_controller.fire_angle_tolerance_deg, 24.0)
		turret_controller.target_aim_height_bias_m = 1.2
		if turret_weapon and turret_controller.weapon_instance == null:
			turret_controller.mount_weapon(turret_weapon)

func _find_turret_controller() -> TurretController:
	var direct: Node = find_child("TurretController", true, false)
	if direct is TurretController:
		return direct as TurretController
	for child in get_children():
		if child is TurretController:
			return child as TurretController
	return null

func _collect_wheel_nodes() -> void:
	_body_node = get_node_or_null("Body")
	if _body_node:
		_body_rest_position = _body_node.position
		_body_rest_rotation = _body_node.rotation
	for wname in ["wheel_right_1", "wheel_right_2", "wheel_right_3", "wheel_left_1", "wheel_left_2", "wheel_left_3"]:
		var w := get_node_or_null(wname) as Node3D
		if w:
			_all_wheel_nodes.append(w)
			var contact_node: Node3D = _find_wheel_contact_node(w)
			_wheel_contact_nodes.append(contact_node)
			_wheel_nominal_positions.append(w.position)
			if contact_node and is_instance_valid(contact_node):
				_wheel_contact_local_positions.append(w.position + contact_node.position)
			else:
				_wheel_contact_local_positions.append(w.position + Vector3(0.0, -WHEEL_RADIUS, 0.0))
			_wheel_support_points_world.append(Vector3.ZERO)
			_wheel_support_normals.append(Vector3.UP)
			_wheel_support_initialized.append(false)
			if wname.ends_with("_1"):
				_front_wheels.append(w)

func _find_wheel_contact_node(wheel_node: Node3D) -> Node3D:
	if not wheel_node:
		return null
	for child in wheel_node.get_children():
		if child is Node3D and child.name.to_lower().contains("contact"):
			return child as Node3D
	return null

func _resolve_waypoints() -> void:
	_waypoint_positions.clear()
	for path in waypoints:
		var node = get_node_or_null(path)
		if node is Node3D:
			_waypoint_positions.append((node as Node3D).global_position)

func set_patrol_waypoints(positions: Array[Vector3]) -> void:
	_waypoint_positions = positions.duplicate()
	_waypoint_index = 0
	_clear_navigation_path()

func assign_platoon(new_platoon: GroundVehiclePlatoon) -> void:
	platoon = new_platoon
	if platoon and is_instance_valid(platoon):
		platoon.register_vehicle(self)
	_clear_navigation_path()

func _physics_process(delta: float) -> void:
	if is_dying:
		return

	if turret_controller:
		current_target = turret_controller.current_target
	else:
		current_target = null
	_update_shoot_and_scoot(delta)
	_update_navigation_path(delta)

	_drive_to_waypoint(delta)
	_update_wheel_visuals()

# --- Wheel Visuals / Chassis Support ---

func _update_wheel_visuals() -> void:
	if _all_wheel_nodes.is_empty():
		return

	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.exclude = [get_rid()]

	var contact_points: Array[Vector3] = []
	var ground_normals: Array[Vector3] = []

	for i in range(_all_wheel_nodes.size()):
		var nominal: Vector3 = _wheel_nominal_positions[i]
		var contact_node: Node3D = _wheel_contact_nodes[i] if i < _wheel_contact_nodes.size() else null
		var contact_local: Vector3 = _wheel_contact_local_positions[i] if i < _wheel_contact_local_positions.size() else nominal + Vector3(0.0, -WHEEL_RADIUS, 0.0)
		var contact_world: Vector3 = to_global(contact_local)
		if contact_node and is_instance_valid(contact_node):
			params.from = contact_world + Vector3.UP * wheel_probe_up_m
			params.to = contact_world - Vector3.UP * wheel_probe_down_m
		else:
			params.from = contact_world + Vector3.UP * wheel_probe_up_m
			params.to = contact_world - Vector3.UP * wheel_probe_down_m
		var hit := space_state.intersect_ray(params)
		if hit:
			var wheel_y: float = nominal.y
			var hit_local_y: float = to_local(hit.position).y
			wheel_y = nominal.y + (hit_local_y - contact_local.y)
			var clamped_wheel_y: float = clampf(
				wheel_y,
				nominal.y - wheel_visual_travel_m,
				nominal.y + wheel_visual_travel_m
			)
			var suspension_blend: float = clampf(wheel_suspension_smoothing * get_physics_process_delta_time(), 0.0, 1.0)
			_all_wheel_nodes[i].position.y = lerpf(_all_wheel_nodes[i].position.y, clamped_wheel_y, suspension_blend)
			if not _wheel_support_initialized[i]:
				_wheel_support_points_world[i] = hit.position
				_wheel_support_normals[i] = hit.normal.normalized()
				_wheel_support_initialized[i] = true
			else:
				var support_blend: float = clampf(wheel_support_smoothing * get_physics_process_delta_time(), 0.0, 1.0)
				_wheel_support_points_world[i] = _wheel_support_points_world[i].lerp(hit.position, support_blend)
				_wheel_support_normals[i] = _wheel_support_normals[i].lerp(hit.normal.normalized(), support_blend).normalized()
			contact_points.append(_wheel_support_points_world[i])
			ground_normals.append(_wheel_support_normals[i])
		else:
			if not _wheel_support_initialized[i]:
				_wheel_support_points_world[i] = contact_world
				_wheel_support_normals[i] = Vector3.UP
				_wheel_support_initialized[i] = true
			else:
				_wheel_support_points_world[i] = _wheel_support_points_world[i].lerp(contact_world, clampf(wheel_support_smoothing * get_physics_process_delta_time() * 0.35, 0.0, 1.0))
				_wheel_support_normals[i] = _wheel_support_normals[i].lerp(Vector3.UP, clampf(wheel_support_smoothing * get_physics_process_delta_time() * 0.2, 0.0, 1.0)).normalized()
			contact_points.append(_wheel_support_points_world[i])
			ground_normals.append(_wheel_support_normals[i])

	if contact_points.is_empty():
		return

	var support_center := Vector3.ZERO
	for point in contact_points:
		support_center += point
	support_center /= float(contact_points.size())

	var avg_normal := Vector3.ZERO
	for normal in ground_normals:
		avg_normal += normal
	var support_up: Vector3 = avg_normal.normalized() if avg_normal.length_squared() > 0.0001 else Vector3.UP

	if _body_node:
		var plane_forward: Vector3 = global_basis.z.slide(support_up)
		if plane_forward.length_squared() <= 0.0001:
			plane_forward = Vector3.FORWARD.slide(support_up)
		plane_forward = plane_forward.normalized()
		var plane_right: Vector3 = support_up.cross(plane_forward).normalized()
		if plane_right.length_squared() <= 0.0001:
			plane_right = Vector3.RIGHT
		var target_basis: Basis = Basis(plane_right, support_up, plane_forward).orthonormalized()
		var target_y: float = global_position.y
		var solved_count: int = 0
		for i in range(contact_points.size()):
			if i >= _wheel_contact_local_positions.size():
				continue
			var solved_origin: Vector3 = contact_points[i] - (target_basis * _wheel_contact_local_positions[i])
			target_y += solved_origin.y
			solved_count += 1
		if solved_count > 0:
			target_y /= float(solved_count + 1)
		var height_blend: float = clampf(chassis_height_smoothing * get_physics_process_delta_time(), 0.0, 1.0)
		global_position.y = lerpf(global_position.y, target_y, height_blend)
		var rotation_blend: float = clampf(chassis_rotation_smoothing * get_physics_process_delta_time(), 0.0, 1.0)
		var current_quat: Quaternion = Quaternion(global_basis.orthonormalized())
		var target_quat: Quaternion = Quaternion(target_basis)
		global_basis = Basis(current_quat.slerp(target_quat, rotation_blend)).orthonormalized()
		_body_node.position = _body_rest_position
		_body_node.rotation = _body_rest_rotation

# --- Driving AI ---

func _update_navigation_path(delta: float) -> void:
	_advance_patrol_waypoint_if_reached()
	if _nav_retry_cooldown_s > 0.0:
		_nav_retry_cooldown_s = maxf(_nav_retry_cooldown_s - delta, 0.0)
	if not use_waypoint_pathfinding:
		_clear_navigation_path()
		return
	if _has_combat_target():
		_nav_repath_timer_s = 0.0
		_nav_stuck_timer_s = 0.0
		_nav_prev_wp_distance = INF
		return
	if not _has_navigation_destination():
		_clear_navigation_path()
		return
	if not NavGraph.is_ready():
		return
	var raw_target: Vector3 = _get_raw_navigation_destination()
	_consume_reached_nav_waypoints(raw_target)
	var dynamic_goal: bool = platoon != null and is_instance_valid(platoon) and platoon.has_active_objective()
	var goal_shifted: bool = _flat_distance(raw_target, _nav_path_goal) > path_goal_repath_distance_m
	_nav_repath_timer_s += delta
	var needs_repath: bool = _nav_path_positions.is_empty() or _nav_path_index >= _nav_path_positions.size()
	if _nav_retry_cooldown_s > 0.0:
		return
	if goal_shifted:
		_recompute_navigation_path(raw_target)
	elif needs_repath and _nav_repath_timer_s >= path_replan_interval_s:
		_recompute_navigation_path(raw_target)
	elif dynamic_goal and _nav_repath_timer_s >= path_replan_interval_s:
		_recompute_navigation_path(raw_target)

func _advance_patrol_waypoint_if_reached() -> void:
	if platoon and is_instance_valid(platoon) and platoon.has_active_objective():
		return
	if _waypoint_positions.is_empty():
		return
	var current_target: Vector3 = _waypoint_positions[_waypoint_index]
	if _flat_distance(global_position, current_target) > waypoint_reach_distance:
		return
	if loop_waypoints:
		_waypoint_index = (_waypoint_index + 1) % _waypoint_positions.size()
	else:
		_waypoint_index = min(_waypoint_index + 1, _waypoint_positions.size() - 1)
	_clear_navigation_path()

func _recompute_navigation_path(raw_target: Vector3) -> void:
	if not NavGraph.is_ready():
		return
	if not NavGraph.has_nearby_node(global_position, path_min_clearance_m):
		_nav_path_goal = raw_target
		_nav_repath_timer_s = 0.0
		_nav_stuck_timer_s = 0.0
		_nav_prev_wp_distance = INF
		_nav_retry_cooldown_s = maxf(_nav_retry_cooldown_s, path_no_anchor_retry_cooldown_s)
		if _nav_path_index >= _nav_path_positions.size():
			_nav_path_positions.clear()
			_nav_path_index = 0
		return
	var flat := Vector2(raw_target.x - global_position.x, raw_target.z - global_position.z)
	if flat.length() <= maxf(path_waypoint_reach_distance, waypoint_reach_distance):
		_clear_navigation_path()
		_nav_path_goal = raw_target
		return

	var base_dir := flat.normalized() if flat.length() > 1.0 else Vector2(1.0, 0.0)
	var seg_len := minf(flat.length(), path_max_segment_m)
	var best_path: Array[Vector3] = []
	const ROTATIONS: Array[float] = [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]

	for deg in ROTATIONS:
		var rad := deg_to_rad(deg)
		var c := cos(rad)
		var s := sin(rad)
		var dir := Vector2(base_dir.x * c - base_dir.y * s, base_dir.x * s + base_dir.y * c)
		var segment_goal := global_position + Vector3(dir.x, 0.0, dir.y) * seg_len
		var terrain_y := TerrainNavGrid.sample_height(segment_goal.x, segment_goal.z)
		if terrain_y > TerrainNavGrid.IMPASSABLE * 0.5:
			segment_goal.y = terrain_y
		else:
			segment_goal.y = global_position.y
		var candidate := NavGraph.find_path(global_position, segment_goal, path_min_clearance_m)
		if candidate.is_empty():
			continue
		var candidate_len := _path_length(candidate)
		if candidate_len > seg_len * 3.0:
			continue
		best_path = candidate
		break

	_nav_repath_timer_s = 0.0
	_nav_stuck_timer_s = 0.0
	_nav_prev_wp_distance = INF
	_nav_retry_cooldown_s = 0.0
	_nav_path_goal = raw_target
	if best_path.is_empty():
		_nav_retry_cooldown_s = maxf(_nav_retry_cooldown_s, path_retry_cooldown_s)
		if _nav_path_index >= _nav_path_positions.size():
			_clear_navigation_path()
		return

	_nav_path_positions = best_path
	_nav_path_index = 0
	_consume_reached_nav_waypoints(raw_target)

func _consume_reached_nav_waypoints(raw_target: Vector3) -> void:
	var reach_dist := maxf(path_waypoint_reach_distance, waypoint_reach_distance)
	while _nav_path_index < _nav_path_positions.size():
		if _flat_distance(global_position, _nav_path_positions[_nav_path_index]) > reach_dist:
			break
		_nav_path_index += 1
		_nav_stuck_timer_s = 0.0
		_nav_prev_wp_distance = INF
	if _nav_path_index >= _nav_path_positions.size() and _flat_distance(global_position, raw_target) > reach_dist:
		_recompute_navigation_path(raw_target)

func _clear_navigation_path() -> void:
	_nav_path_positions.clear()
	_nav_path_index = 0
	_nav_repath_timer_s = path_replan_interval_s
	_nav_stuck_timer_s = 0.0
	_nav_prev_wp_distance = INF
	_nav_retry_cooldown_s = 0.0

func _get_raw_navigation_destination() -> Vector3:
	if platoon and is_instance_valid(platoon) and platoon.has_active_objective():
		return platoon.get_destination_for(self)
	if not _waypoint_positions.is_empty():
		return _waypoint_positions[_waypoint_index]
	return global_position

func _get_follow_navigation_destination() -> Vector3:
	var raw_target := _get_raw_navigation_destination()
	if not use_waypoint_pathfinding or not NavGraph.is_ready():
		return raw_target
	if _nav_path_index < _nav_path_positions.size():
		return _nav_path_positions[_nav_path_index]
	return raw_target

func _update_path_stuck_state(delta: float, follow_destination: Vector3) -> void:
	if not use_waypoint_pathfinding or _nav_path_index >= _nav_path_positions.size():
		_nav_stuck_timer_s = 0.0
		_nav_prev_wp_distance = INF
		return
	var wp_dist := _flat_distance(global_position, follow_destination)
	if wp_dist > _nav_prev_wp_distance + 0.5:
		_nav_stuck_timer_s += delta
		if _nav_stuck_timer_s >= path_stuck_timeout_s and _nav_retry_cooldown_s <= 0.0:
			_recompute_navigation_path(_get_raw_navigation_destination())
			_nav_stuck_timer_s = 0.0
			_nav_prev_wp_distance = INF
			return
	else:
		_nav_stuck_timer_s = 0.0
	_nav_prev_wp_distance = wp_dist

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _path_length(path: Array[Vector3]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += _flat_distance(path[i], path[i - 1])
	return total

func _drive_to_waypoint(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -2.0

	var hold_in_combat: bool = _has_combat_target()

	if not _has_navigation_destination():
		var stop_accel: float = acceleration * delta * 2.5
		velocity.x = move_toward(velocity.x, 0.0, stop_accel)
		velocity.z = move_toward(velocity.z, 0.0, stop_accel)
		move_and_slide()
		return

	var nav_dest: Vector3 = _get_follow_navigation_destination()
	var dest: Vector3 = _apply_combat_mobility(nav_dest)
	dest = _apply_platoon_cohesion(dest)
	_update_path_stuck_state(delta, nav_dest)

	var current_forward: Vector3 = global_basis.z
	current_forward.y = 0.0
	current_forward = current_forward.normalized() if current_forward.length_squared() > 0.0001 else Vector3.FORWARD
	var desired_dir: Vector3 = current_forward
	if hold_in_combat and current_target and is_instance_valid(current_target):
		desired_dir = current_target.global_position - global_position
		desired_dir.y = 0.0
	else:
		var to_dest: Vector3 = dest - global_position
		to_dest.y = 0.0
		if to_dest.length_squared() <= 0.01:
			var stop_accel_idle: float = acceleration * delta * 2.5
			velocity.x = move_toward(velocity.x, 0.0, stop_accel_idle)
			velocity.z = move_toward(velocity.z, 0.0, stop_accel_idle)
			move_and_slide()
			return
		desired_dir = to_dest
	if desired_dir.length_squared() <= 0.0001:
		desired_dir = current_forward
	else:
		desired_dir = desired_dir.normalized()

	var cross_y: float = current_forward.cross(desired_dir).y
	var dot: float = clampf(current_forward.dot(desired_dir), -1.0, 1.0)
	var turn_angle_deg: float = rad_to_deg(acos(dot))
	var planar_speed: float = Vector2(velocity.x, velocity.z).length()

	var steer_target: float = clamp(cross_y * 2.0, -1.0, 1.0)
	if hold_in_combat:
		steer_target = clamp(cross_y * 1.1, -0.65, 0.65)
	var turn_rate_scale: float = lerpf(0.35, 1.0, clampf(planar_speed / maxf(max_speed, 0.1), 0.0, 1.0))
	if hold_in_combat:
		turn_rate_scale = maxf(turn_rate_scale, 0.45)
	rotate_y(steer_target * turn_speed * delta * turn_rate_scale)

	var throttle: float = clamp((dot + 1.0) * 0.5, 0.0, 1.0) * (1.0 - abs(steer_target) * 0.3)
	if hold_in_combat and current_target and is_instance_valid(current_target):
		var target_distance: float = global_position.distance_to(current_target.global_position)
		if target_distance <= combat_stop_distance_m and turn_angle_deg <= combat_track_angle_deg:
			throttle = 0.0
		elif target_distance <= combat_stop_distance_m:
			throttle = combat_creep_speed_mps / maxf(max_speed, 0.1)
		else:
			var closing_speed: float = clampf((target_distance - combat_stop_distance_m) / maxf(combat_hold_distance_m - combat_stop_distance_m, 1.0), 0.25, 0.7)
			throttle = maxf(closing_speed, combat_creep_speed_mps / maxf(max_speed, 0.1))
	var forward: Vector3 = global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD

	var sep := Vector3.ZERO
	if not hold_in_combat:
		for other in get_tree().get_nodes_in_group("ground_vehicles"):
			if other == self or not is_instance_valid(other) or not other is Node3D:
				continue
			var away: Vector3 = global_position - (other as Node3D).global_position
			away.y = 0.0
			var dist: float = away.length()
			var min_spacing: float = maxf(preferred_vehicle_spacing_min_m, 5.0)
			if dist < min_spacing and dist > 0.01:
				sep += away.normalized() * (min_spacing - dist) / min_spacing * max_speed

	var accel_scale: float = 1.8 if hold_in_combat else 1.0
	velocity.x = move_toward(velocity.x, forward.x * throttle * max_speed + sep.x, acceleration * delta * accel_scale)
	velocity.z = move_toward(velocity.z, forward.z * throttle * max_speed + sep.z, acceleration * delta * accel_scale)

	move_and_slide()

	for w in _front_wheels:
		w.rotation.y = steer_target * max_steering_angle

func _get_navigation_destination() -> Vector3:
	return _get_follow_navigation_destination()

func _has_navigation_destination() -> bool:
	return (platoon and is_instance_valid(platoon) and platoon.has_active_objective()) or not _waypoint_positions.is_empty()

func _apply_platoon_cohesion(base_destination: Vector3) -> Vector3:
	if _has_combat_target():
		return global_position
	if not platoon or not is_instance_valid(platoon):
		return base_destination
	var members: Array[Node3D] = platoon.get_members()
	var nearest_member: Node3D = null
	var nearest_distance: float = INF
	for member in members:
		if member == self or not is_instance_valid(member):
			continue
		var dist: float = global_position.distance_to(member.global_position)
		if dist < nearest_distance:
			nearest_distance = dist
			nearest_member = member
	if nearest_member == null:
		return base_destination
	var desired_spacing: float = clampf(platoon_min_neighbor_distance_m, 5.0, maxf(preferred_vehicle_spacing_max_m, 5.0))
	if nearest_distance >= desired_spacing and nearest_distance <= maxf(preferred_vehicle_spacing_max_m, desired_spacing):
		return base_destination
	if nearest_distance < desired_spacing:
		var push_dir: Vector3 = global_position - nearest_member.global_position
		push_dir.y = 0.0
		if push_dir.length_squared() > 0.01:
			return global_position + push_dir.normalized() * (desired_spacing - nearest_distance)
		return base_destination
	var rejoin_distance: float = maxf(platoon_rejoin_distance_m, maxf(preferred_vehicle_spacing_max_m, desired_spacing + 5.0))
	var pull_t: float = clampf(
		(nearest_distance - preferred_vehicle_spacing_max_m) / maxf(rejoin_distance - preferred_vehicle_spacing_max_m, 1.0),
		0.0,
		1.0
	)
	return base_destination.lerp(nearest_member.global_position, pull_t)

func _update_shoot_and_scoot(delta: float) -> void:
	if not shoot_and_scoot_enabled or not current_target or not is_instance_valid(current_target):
		_combat_hold_timer_s = 0.0
		_combat_is_scooting = false
		_combat_scoot_destination = Vector3.ZERO
		_had_combat_target_last_frame = false
		return
	var engage_distance: float = maxf(combat_hold_distance_m, 25.0)
	if global_position.distance_to(current_target.global_position) > engage_distance:
		_combat_hold_timer_s = 0.0
		_combat_is_scooting = false
		_combat_scoot_destination = Vector3.ZERO
		_had_combat_target_last_frame = false
		return
	if not _had_combat_target_last_frame:
		_combat_is_scooting = false
		_combat_hold_timer_s = maxf(fire_position_hold_s, 0.2)
		_combat_scoot_destination = Vector3.ZERO
		_had_combat_target_last_frame = true
		return
	if _combat_hold_timer_s > 0.0:
		_combat_hold_timer_s -= delta
		return
	if _combat_is_scooting:
		_combat_is_scooting = false
		_combat_hold_timer_s = maxf(fire_position_hold_s, 0.2)
		_combat_scoot_destination = Vector3.ZERO
		return
	_combat_is_scooting = true
	_combat_hold_timer_s = maxf(scoot_move_s, 0.2)
	_combat_scoot_destination = _choose_scoot_destination()

func _apply_combat_mobility(base_destination: Vector3) -> Vector3:
	if not _has_combat_target():
		return base_destination
	return global_position

func _has_combat_target() -> bool:
	return current_target != null and is_instance_valid(current_target)

func _should_hold_combat_position() -> bool:
	return _has_combat_target()

func _choose_scoot_destination() -> Vector3:
	if not current_target or not is_instance_valid(current_target):
		return global_position
	var to_target: Vector3 = current_target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return global_position
	var forward_from_target: Vector3 = to_target.normalized()
	var lateral: Vector3 = Vector3(-forward_from_target.z, 0.0, forward_from_target.x)
	if randf() < 0.5:
		lateral = -lateral
	var scoot_offset: Vector3 = lateral * scoot_distance_m + forward_from_target * randf_range(-0.4, 0.3) * scoot_distance_m
	var candidate: Vector3 = global_position + scoot_offset
	return _project_destination_to_ground(candidate)

func _project_destination_to_ground(candidate: Vector3) -> Vector3:
	var space_state := get_world_3d().direct_space_state
	var hit := space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 2000.0, candidate - Vector3.UP * 200.0)
	)
	if hit:
		candidate.y = hit.position.y + 2.0
	return candidate

# --- Combat ---

func get_team() -> int:
	return team

func take_damage(damage_amount: float) -> void:
	if is_dying or current_health <= 0:
		return
	current_health -= damage_amount
	current_health = max(current_health, 0.0)
	if current_health <= 0:
		is_dying = true
		var death_timer = Timer.new()
		death_timer.wait_time = randf_range(0.0, 0.6)
		death_timer.one_shot = true
		death_timer.timeout.connect(explode)
		death_timer.timeout.connect(death_timer.queue_free)
		add_child(death_timer)
		death_timer.start()

func explode() -> void:
	emit_signal("destroyed", self)
	if platoon and is_instance_valid(platoon):
		platoon.unregister_vehicle(self)
	var explosion_res = load("res://Projectiles/Explosion/explosion.tscn")
	if explosion_res:
		var exp = explosion_res.instantiate()
		get_parent().add_child(exp)
		exp.global_position = global_position
	VehicleWreck.spawn(get_parent(), global_transform)
	queue_free()
