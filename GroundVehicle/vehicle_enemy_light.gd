extends CharacterBody3D
class_name VehicleEnemyLight

signal destroyed(vehicle)

# --- Movement ---
@export var max_speed: float = 15.0
@export var acceleration: float = 4.0
@export var turn_speed: float = 0.6
@export var max_steering_angle: float = 0.5
@export var chassis_ride_height_m: float = 1.0
@export var wheel_suspension_smoothing: float = 12.0
@export var wheel_probe_down_m: float = 12.0
@export var spring_stiffness: float = 120.0
@export var spring_damping: float = 18.0
@export var spring_tilt_stiffness: float = 80.0
@export var spring_tilt_damping: float = 18.0

# --- Waypoints ---
@export var waypoints: Array[NodePath] = []
@export var loop_waypoints: bool = true
@export var waypoint_reach_distance: float = 25.0
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
@export var team: int = 2
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
var _body_rest_position: Vector3 = Vector3.ZERO
var _body_rest_rotation: Vector3 = Vector3.ZERO

# Corner probe positions (local space) — front-left, front-right, rear-left, rear-right
var _corner_probes: Array[Vector3] = []
var _corner_half_x: float = 1.66
var _corner_half_z: float = 4.68

const GRAVITY: float = 25.0
const WHEEL_RADIUS: float = 0.4
var _spring_velocity_y: float = 0.0
var _spring_pitch_velocity: float = 0.0
var _spring_roll_velocity: float = 0.0
var _spring_initialized: bool = false
func _ready() -> void:
	current_health = max_health
	floor_snap_length = 0.0
	floor_max_angle = deg_to_rad(50.0)
	add_to_group("enemies")
	add_to_group("ground_vehicles")
	add_to_group("team_" + str(team))
	_resolve_waypoints()
	_collect_wheel_nodes()
	_compute_corner_probes()

	# Dust from wheels
	if not has_node("DustEffect"):
		var dust := DustEffect.new()
		dust.name = "DustEffect"
		dust.min_speed_mps = 3.0
		dust.spawn_interval_s = 0.4
		dust.puff_scale_min = 1.0
		dust.puff_scale_max = 2.5
		dust.puff_lifetime_s = 4.0
		dust.puff_rise_speed = 5.0
		dust.full_speed_mps = max_speed
		add_child(dust)

	turret_controller = _find_turret_controller()

	if not turret_controller:
		push_warning("VehicleEnemyLight: No TurretController found as child!")
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
			if wname.ends_with("_1"):
				_front_wheels.append(w)

func _compute_corner_probes() -> void:
	## Build 4 corner probe positions from the CollisionShape3D box.
	var col_shape: CollisionShape3D = null
	for child in get_children():
		if child is CollisionShape3D:
			col_shape = child as CollisionShape3D
			break
	if col_shape and col_shape.shape is BoxShape3D:
		var box: BoxShape3D = col_shape.shape as BoxShape3D
		_corner_half_x = box.size.x * 0.5
		_corner_half_z = box.size.z * 0.5
	# Probe at y=0 (vehicle root level) at the 4 XZ corners
	_corner_probes = [
		Vector3(-_corner_half_x, 0.0,  _corner_half_z),  # front-left
		Vector3( _corner_half_x, 0.0,  _corner_half_z),  # front-right
		Vector3(-_corner_half_x, 0.0, -_corner_half_z),  # rear-left
		Vector3( _corner_half_x, 0.0, -_corner_half_z),  # rear-right
	]

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
	var delta := get_physics_process_delta_time()
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.exclude = [get_rid()]

	# --- 1. Corner probes: determine target height & tilt ---
	var corner_target_ys: Array[float] = []
	var hit_count: int = 0
	for corner_local in _corner_probes:
		# Use only XZ from corner, probe straight down in world Y
		var corner_world: Vector3 = to_global(corner_local)
		params.from = corner_world + Vector3.UP * 5.0
		params.to = corner_world - Vector3.UP * wheel_probe_down_m
		var hit := space_state.intersect_ray(params)
		if hit:
			corner_target_ys.append(hit.position.y + chassis_ride_height_m)
			hit_count += 1
		else:
			corner_target_ys.append(-99999.0)

	if hit_count == 0:
		# No ground — free-fall
		_spring_velocity_y -= GRAVITY * delta
		# Settle wheels to nominal
		for i in range(_all_wheel_nodes.size()):
			_all_wheel_nodes[i].position.y = lerpf(_all_wheel_nodes[i].position.y, _wheel_nominal_positions[i].y, 0.1)
		return

	# Fill missing corners with average of valid ones
	var valid_sum: float = 0.0
	for y in corner_target_ys:
		if y > -90000.0:
			valid_sum += y
	var valid_avg: float = valid_sum / float(hit_count)
	for i in range(corner_target_ys.size()):
		if corner_target_ys[i] < -90000.0:
			corner_target_ys[i] = valid_avg

	# Target height = average of 4 corners
	var target_y: float = (corner_target_ys[0] + corner_target_ys[1] + corner_target_ys[2] + corner_target_ys[3]) / 4.0

	# Target pitch from front vs rear (positive pitch = nose up)
	var front_avg_y: float = (corner_target_ys[0] + corner_target_ys[1]) / 2.0
	var rear_avg_y: float = (corner_target_ys[2] + corner_target_ys[3]) / 2.0
	var target_pitch: float = atan2(rear_avg_y - front_avg_y, _corner_half_z * 2.0)

	# Target roll from right vs left (positive roll = right side up)
	var left_avg_y: float = (corner_target_ys[0] + corner_target_ys[2]) / 2.0
	var right_avg_y: float = (corner_target_ys[1] + corner_target_ys[3]) / 2.0
	var target_roll: float = atan2(right_avg_y - left_avg_y, _corner_half_x * 2.0)

	# --- 2. Height spring ---
	if not _spring_initialized:
		global_position.y = target_y
		_spring_velocity_y = 0.0
		_spring_pitch_velocity = 0.0
		_spring_roll_velocity = 0.0
		_spring_initialized = true
	else:
		var displacement: float = global_position.y - target_y
		var spring_force: float = -spring_stiffness * displacement - spring_damping * _spring_velocity_y
		_spring_velocity_y += spring_force * delta
		_spring_velocity_y = clampf(_spring_velocity_y, -50.0, 50.0)

	# --- 3. Tilt spring (pitch & roll only, never yaw) ---
	# Extract current yaw from basis
	var current_yaw: float = atan2(global_basis.z.x, global_basis.z.z)
	# Extract current pitch and roll
	var current_pitch: float = asin(clampf(-global_basis.z.y, -1.0, 1.0))
	var current_roll: float = atan2(global_basis.x.y, global_basis.y.y)

	var pitch_torque: float = -spring_tilt_stiffness * (current_pitch - target_pitch) - spring_tilt_damping * _spring_pitch_velocity
	_spring_pitch_velocity += pitch_torque * delta
	_spring_pitch_velocity = clampf(_spring_pitch_velocity, -5.0, 5.0)

	var roll_torque: float = -spring_tilt_stiffness * (current_roll - target_roll) - spring_tilt_damping * _spring_roll_velocity
	_spring_roll_velocity += roll_torque * delta
	_spring_roll_velocity = clampf(_spring_roll_velocity, -5.0, 5.0)

	var new_pitch: float = current_pitch + _spring_pitch_velocity * delta
	var new_roll: float = current_roll + _spring_roll_velocity * delta

	# Rebuild basis from yaw (preserved), new pitch, new roll
	global_basis = Basis.from_euler(Vector3(new_pitch, current_yaw, new_roll), EULER_ORDER_YXZ).orthonormalized()

	# --- 4. Position wheels visually on the ground ---
	for i in range(_all_wheel_nodes.size()):
		if i >= _wheel_contact_local_positions.size():
			continue
		var nominal: Vector3 = _wheel_nominal_positions[i]
		var contact_local: Vector3 = _wheel_contact_local_positions[i]
		var contact_world: Vector3 = to_global(contact_local)
		params.from = contact_world + Vector3.UP * 3.0
		params.to = contact_world - Vector3.UP * wheel_probe_down_m
		var hit := space_state.intersect_ray(params)
		if hit:
			var hit_local_y: float = to_local(hit.position).y
			var target_wheel_y: float = nominal.y + (hit_local_y - contact_local.y)
			var blend: float = clampf(wheel_suspension_smoothing * delta, 0.0, 1.0)
			_all_wheel_nodes[i].position.y = lerpf(_all_wheel_nodes[i].position.y, target_wheel_y, blend)
		else:
			_all_wheel_nodes[i].position.y = lerpf(_all_wheel_nodes[i].position.y, nominal.y, 0.1)

	if _body_node:
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
	velocity.y = _spring_velocity_y

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

	# Compute avoidance nudge BEFORE steering so it influences direction, not just velocity
	var nudge := Vector3.ZERO
	if not hold_in_combat:
		for other in get_tree().get_nodes_in_group("ground_vehicles"):
			if other == self or not is_instance_valid(other) or not other is Node3D:
				continue
			var away: Vector3 = global_position - (other as Node3D).global_position
			away.y = 0.0
			var dist: float = away.length()
			var min_spacing: float = maxf(preferred_vehicle_spacing_min_m, 5.0)
			if dist < min_spacing and dist > 0.01:
				var strength: float = (min_spacing - dist) / min_spacing
				nudge += away.normalized() * strength

	# Elliptical carrier avoidance — gentle flow around
	for carrier in get_tree().get_nodes_in_group("carrier"):
		if not carrier is Node3D or not is_instance_valid(carrier):
			continue
		var local_pos: Vector3 = (carrier as Node3D).to_local(global_position)
		var rx: float = 70.0
		var rz: float = 90.0
		var nx: float = local_pos.x / rx
		var nz: float = local_pos.z / rz
		var ellipse_dist: float = sqrt(nx * nx + nz * nz)
		if ellipse_dist < 1.4 and ellipse_dist > 0.01:
			var radial_local := Vector3(local_pos.x / (rx * rx), 0.0, local_pos.z / (rz * rz))
			if radial_local.length_squared() > 0.0001:
				radial_local = radial_local.normalized()
			var tangent_local := Vector3(-radial_local.z, 0.0, radial_local.x)
			var desired_local: Vector3 = (carrier as Node3D).global_basis.inverse() * desired_dir
			if tangent_local.dot(Vector3(desired_local.x, 0.0, desired_local.z)) < 0.0:
				tangent_local = -tangent_local
			var strength: float = clampf((1.4 - ellipse_dist) / 0.4, 0.0, 1.0)
			if ellipse_dist < 1.0:
				strength = 1.0
			var push_local := (radial_local * 0.4 + tangent_local * 0.6).normalized()
			var push_world: Vector3 = (carrier as Node3D).global_basis * push_local
			push_world.y = 0.0
			nudge += push_world * strength * 3.0

	# Track whether avoidance is active
	var nudge_active: bool = nudge.length_squared() > 0.001

	# Blend avoidance into desired direction so vehicles steer around obstacles
	if nudge_active:
		var nudge_weight: float = clampf(nudge.length(), 1.0, 6.0)
		desired_dir = (desired_dir + nudge.normalized() * nudge_weight).normalized()

	var cross_y: float = current_forward.cross(desired_dir).y
	var dot: float = clampf(current_forward.dot(desired_dir), -1.0, 1.0)
	var turn_angle_deg: float = rad_to_deg(acos(dot))
	var planar_speed: float = Vector2(velocity.x, velocity.z).length()

	var steer_target: float = clamp(cross_y, -1.0, 1.0)
	if hold_in_combat:
		steer_target = clamp(cross_y * 0.7, -0.65, 0.65)
	var turn_rate_scale: float = lerpf(0.2, 1.0, clampf(planar_speed / maxf(max_speed, 0.1), 0.0, 1.0))
	if nudge_active:
		turn_rate_scale = maxf(turn_rate_scale, 0.5)  # Don't let avoidance kill turn rate
	if hold_in_combat:
		turn_rate_scale = maxf(turn_rate_scale, 0.35)
	global_rotate(Vector3.UP, steer_target * turn_speed * delta * turn_rate_scale)

	var throttle: float = 1.0
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

	# Kill lateral velocity — vehicles only move along their forward axis
	var current_planar := Vector3(velocity.x, 0.0, velocity.z)
	var forward_speed: float = current_planar.dot(forward)
	var target_speed: float = throttle * max_speed
	if hold_in_combat:
		forward_speed = move_toward(forward_speed, target_speed, acceleration * delta * (4.0 if forward_speed > target_speed else 1.8))
	else:
		forward_speed = move_toward(forward_speed, target_speed, acceleration * delta * (4.0 if forward_speed > target_speed else 1.0))
	velocity.x = forward.x * forward_speed
	velocity.z = forward.z * forward_speed

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
