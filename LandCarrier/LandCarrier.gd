extends CharacterBody3D
class_name LandCarrier

# --- Waypoints ---
@export var waypoints: Array[NodePath] = []
@export var loop_waypoints: bool = false
@export var waypoint_reach_distance: float = 120.0

# --- Movement ---
@export var max_speed: float = 8.0
@export var acceleration: float = 1.5
@export var turn_speed: float = 0.25

# --- Height ---
@export var height_smoothing: float = 15.0 # height tracking speed (higher = snappier)

# --- Obstacle avoidance (short-range reactive) ---
@export var obstacle_lookahead_m: float = 300.0
@export var obstacle_width_m: float = 120.0
@export var obstacle_height_threshold_m: float = 20.0

# --- Wall avoidance (periodic side raycasts) ---
@export var wall_check_dist_m: float = 100.0  # how far to cast sideways from carrier edge
@export var wall_check_interval: int = 12     # frames between checks (~5/s at 60fps)

# --- Pathfinding ---
@export var path_max_slope_m: float = 12.0    # max height variation within clearance radius (carrier-specific)
@export var use_waypoint_pathfinding: bool = true
@export var path_max_segment_m: float = 1600.0 # replan distance; long routes are split into segments
@export var turn_in_place_angle_deg: float = 100.0

const BODY_RIDE_HEIGHT: float = 40.0
const TREAD_GROUND_OFFSET: float = 8.0
const MAX_TREAD_STEER: float = 0.4

# --- State ---
var _raw_waypoints: Array[Vector3] = []
var _raw_waypoint_index: int = 0
var _waypoint_positions: Array[Vector3] = []
var _waypoint_index: int = 0
var _tread_nodes: Array[Node3D] = []
var _tread_local_xz: Array[Vector2] = []
var _tread_initial_rot_y: Array[float] = []
var _current_steer: float = 0.0
var _tread_steer: float = 0.0
var _wall_steer: float = 0.0
var _wall_check_frame: int = 0
var _stuck_timer: float = 0.0
var _prev_wp_dist: float = INF
var _no_path_timer: float = 0.0
var _debug_timer: float = 0.0
var _last_planar_speed_mps: float = 0.0
var treads: Array[CarrierTread] = []
var elevator: Node3D
const TEAM_ID: int = 1

func _ready():
	add_to_group("carrier")
	visible = false
	_resolve_waypoints()
	_collect_tread_nodes()
	find_treads()
	elevator = find_child("Elevator")
	if elevator and elevator.has_method("setup"):
		elevator.setup(self)
	if not use_waypoint_pathfinding:
		_apply_direct_waypoints()
		visible = true
	elif _raw_waypoints.is_empty():
		call_deferred("_set_north_heading")
	else:
		call_deferred("_compute_next_path_segment")

func _resolve_waypoints() -> void:
	_raw_waypoints.clear()
	for path in waypoints:
		var node = get_node_or_null(path)
		if node is Node3D:
			_raw_waypoints.append((node as Node3D).global_position)

func set_patrol_waypoints(positions: Array[Vector3]) -> void:
	_raw_waypoints = positions.duplicate()
	_raw_waypoint_index = 0
	_waypoint_positions.clear()
	_waypoint_index = 0
	if not use_waypoint_pathfinding:
		_apply_direct_waypoints()
		return
	_compute_next_path_segment()

func _apply_direct_waypoints() -> void:
	_waypoint_positions = _raw_waypoints.duplicate()
	_waypoint_index = 0
	_stuck_timer = 0.0
	_prev_wp_dist = INF
	_align_to_active_waypoint()

func _set_north_heading() -> void:
	if not use_waypoint_pathfinding:
		visible = true
		return
	if NavGraph.is_ready():
		_start_random_patrol()
	else:
		NavGraph.graph_ready.connect(_start_random_patrol, CONNECT_ONE_SHOT)

func _start_random_patrol() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var start: Vector3 = TerrainNavGrid.get_random_passable_position(rng, path_max_slope_m)
	if start != Vector3.ZERO:
		global_position = Vector3(start.x, start.y + BODY_RIDE_HEIGHT, start.z)

	visible = true

	var destination: Vector3 = TerrainNavGrid.get_furthest_edge_position(global_position, 3, path_max_slope_m)
	_raw_waypoints = [destination]
	_raw_waypoint_index = 0
	_compute_next_path_segment()
	print("[LandCarrier] Random patrol: start=", global_position, " dest=", destination)

func _compute_next_path_segment() -> void:
	visible = true
	if _raw_waypoints.is_empty():
		return
	if _raw_waypoint_index >= _raw_waypoints.size():
		if loop_waypoints:
			_raw_waypoint_index = 0
		else:
			_pick_new_patrol_destination()
			return
	if not use_waypoint_pathfinding:
		_apply_direct_waypoints()
		return
	var target := _raw_waypoints[_raw_waypoint_index]

	var flat := Vector2(target.x - global_position.x, target.z - global_position.z)
	var base_dir := flat.normalized() if flat.length() > 1.0 else Vector2(1.0, 0.0)

	var path: Array[Vector3] = []
	const ROTATIONS: Array[float] = [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]
	for deg in ROTATIONS:
		var rad := deg_to_rad(deg)
		var c := cos(rad)
		var s := sin(rad)
		var dir := Vector2(base_dir.x * c - base_dir.y * s, base_dir.x * s + base_dir.y * c)
		var seg_len := minf(flat.length(), path_max_segment_m)
		var sg := global_position + Vector3(dir.x, 0.0, dir.y) * seg_len
		var h := TerrainNavGrid.sample_height(sg.x, sg.z)
		sg.y = h if h > TerrainNavGrid.IMPASSABLE * 0.5 else global_position.y
		path = NavGraph.find_path(global_position, sg, 40.0)
		if path.is_empty():
			path = NavGraph.find_path(global_position, sg, 0.0)
		if not path.is_empty():
			var path_xz_len := 0.0
			for k in range(1, path.size()):
				path_xz_len += Vector2(path[k].x - path[k - 1].x, path[k].z - path[k - 1].z).length()
			if path_xz_len > seg_len * 2.5:
				print("[Carrier] Rejected %.0fm path at %.0fdeg (%.1fx target) - U-turn route" % [
					path_xz_len, deg, path_xz_len / seg_len
				])
				path = []
				continue
			if deg != 0.0:
				print("[Carrier] Path found at %.0fdeg rotation from destination bearing" % deg)
			break

	if path.is_empty():
		if not _raw_waypoints.is_empty() and _raw_waypoint_index < _raw_waypoints.size():
			var raw_target := _raw_waypoints[_raw_waypoint_index]
			var dist := Vector2(global_position.x - raw_target.x, global_position.z - raw_target.z).length()
			if dist < path_max_segment_m:
				print("[Carrier] No path found but within %.0fm of destination - skipping" % dist)
				_raw_waypoint_index += 1
				_compute_next_path_segment()
				return

	_on_path_ready(path)

func _pick_new_patrol_destination() -> void:
	var destination: Vector3 = TerrainNavGrid.get_furthest_edge_position(global_position, 3, path_max_slope_m)
	_raw_waypoints = [destination]
	_raw_waypoint_index = 0
	print("[LandCarrier] New patrol destination: (%d,%d,%d)" % [int(destination.x), int(destination.y), int(destination.z)])
	_compute_next_path_segment()

func _on_path_ready(path: Array) -> void:
	_waypoint_positions.clear()
	for p in path:
		_waypoint_positions.append(p as Vector3)
	_waypoint_index = 0
	_stuck_timer = 0.0
	_prev_wp_dist = INF
	_align_to_active_waypoint()
	var total_dist := 0.0
	for i in range(1, _waypoint_positions.size()):
		total_dist += Vector2(
			_waypoint_positions[i].x - _waypoint_positions[i - 1].x,
			_waypoint_positions[i].z - _waypoint_positions[i - 1].z
		).length()
	print("[Carrier] Path: %d waypoints, %.0fm total" % [_waypoint_positions.size(), total_dist])
	var dest := _raw_waypoints[_raw_waypoint_index] if not _raw_waypoints.is_empty() and _raw_waypoint_index < _raw_waypoints.size() else Vector3.ZERO
	# TerrainNavGrid.save_debug_image(_waypoint_positions, global_position, dest, path_max_slope_m)

func _align_to_active_waypoint() -> void:
	if _waypoint_positions.is_empty() or _waypoint_index >= _waypoint_positions.size():
		return
	var target: Vector3 = _waypoint_positions[_waypoint_index]
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return
	to_target = to_target.normalized()
	rotation.y = atan2(to_target.x, to_target.z)

func _advance_waypoint_or_replan() -> void:
	if _raw_waypoints.is_empty():
		return
	var raw_target := _raw_waypoints[_raw_waypoint_index]
	var flat_dist := Vector2(global_position.x - raw_target.x, global_position.z - raw_target.z).length()
	if flat_dist < waypoint_reach_distance:
		_raw_waypoint_index += 1
		if _raw_waypoint_index >= _raw_waypoints.size():
			if loop_waypoints:
				_raw_waypoint_index = 0
			else:
				_pick_new_patrol_destination()
				return
	if not use_waypoint_pathfinding:
		_apply_direct_waypoints()
		return
	_compute_next_path_segment()

func _collect_tread_nodes() -> void:
	_tread_nodes.clear()
	_tread_local_xz.clear()
	_tread_initial_rot_y.clear()
	for child in get_children():
		if child is CarrierTread:
			_tread_nodes.append(child)
			_tread_local_xz.append(Vector2(child.position.x, child.position.z))
			_tread_initial_rot_y.append(child.rotation.y)

func find_treads() -> void:
	treads.clear()
	for child in get_children():
		if child is CarrierTread:
			treads.append(child)

func _physics_process(delta: float) -> void:
	var transform_before := global_transform
	_drive_to_waypoint(delta)
	_update_tread_visuals(delta)
	_debug_timer += delta
	if _debug_timer >= 3.0:
		_debug_timer = 0.0
		_print_debug_status()
	if elevator and elevator.has_method("update"):
		elevator.update(delta)
	_carry_deck_passengers(global_transform, transform_before)

func _carry_deck_passengers(current_transform: Transform3D, old_transform: Transform3D) -> void:
	if current_transform.is_equal_approx(old_transform):
		return
	var transform_delta: Transform3D = current_transform * old_transform.affine_inverse()
	for group in ["aircraft", "ai_aircraft", "tractor_bot"]:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or not node is Node3D:
				continue
			var n := node as Node
			var has_brake := n.has_meta("parking_brake") and bool(n.get_meta("parking_brake"))
			var has_transport := n.has_meta("carrier_transport_mode") and bool(n.get_meta("carrier_transport_mode"))
			var on_carrier := has_brake or has_transport
			var on_catapult := n.has_meta("controls_disabled") and bool(n.get_meta("controls_disabled")) and not has_brake and not has_transport
			if on_carrier or on_catapult:
				(node as Node3D).global_transform = transform_delta * (node as Node3D).global_transform
			if (on_carrier or on_catapult) and Engine.get_process_frames() % 120 == 0:
				var plane_z = snappedf((node as Node3D).global_position.z, 0.1)
				var carrier_z = snappedf(global_position.z, 0.1)
				print("[Deck] ", node.name, " z=", plane_z, "  carrier z=", carrier_z, "  gap=", snappedf(plane_z - carrier_z, 0.1))
	for joint in get_tree().get_nodes_in_group("carrier_pin_joint"):
		if is_instance_valid(joint) and joint is Node3D:
			(joint as Node3D).global_transform = transform_delta * (joint as Node3D).global_transform

func _update_tread_visuals(delta: float) -> void:
	_tread_steer = lerp(_tread_steer, _current_steer, delta * 1.5)

	if not TerrainNavGrid.is_ready():
		return

	var world_heights: Array[float] = []

	for i in _tread_nodes.size():
		var xz: Vector2 = _tread_local_xz[i]
		var world_xz := to_global(Vector3(xz.x, 0.0, xz.y))

		var terrain_y: float = TerrainNavGrid.sample_height(world_xz.x, world_xz.z)
		if terrain_y <= TerrainNavGrid.IMPASSABLE * 0.5:
			terrain_y = global_position.y - BODY_RIDE_HEIGHT

		world_heights.append(terrain_y)

		var tread := _tread_nodes[i] as Node3D
		tread.global_position = Vector3(world_xz.x, terrain_y + TREAD_GROUND_OFFSET, world_xz.z)
		var steer_offset: float = 0.0
		if xz.y > 20.0:
			steer_offset = _tread_steer * MAX_TREAD_STEER
		elif xz.y < -20.0:
			steer_offset = -_tread_steer * MAX_TREAD_STEER
		tread.rotation.y = _tread_initial_rot_y[i] + steer_offset

	if not world_heights.is_empty():
		var avg_y: float = 0.0
		for h in world_heights:
			avg_y += h
		avg_y /= world_heights.size()
		var desired_y: float = avg_y + BODY_RIDE_HEIGHT
		global_position.y = lerp(global_position.y, desired_y, height_smoothing * delta)

func _sample_terrain_y(wx: float, wz: float) -> float:
	var h: float = TerrainNavGrid.sample_height(wx, wz)
	if h <= TerrainNavGrid.IMPASSABLE * 0.5:
		return global_position.y - BODY_RIDE_HEIGHT
	return h

func _get_avoidance_steer() -> float:
	var fwd := global_transform.basis.z
	var right := fwd.cross(global_transform.basis.y)
	var ahead := global_position + fwd * obstacle_lookahead_m

	var port_pos := ahead - right * obstacle_width_m
	var center_pos := ahead
	var starboard_pos := ahead + right * obstacle_width_m
	var port_h := _sample_terrain_y(port_pos.x, port_pos.z)
	var center_h := _sample_terrain_y(center_pos.x, center_pos.z)
	var starboard_h := _sample_terrain_y(starboard_pos.x, starboard_pos.z)

	var base_y := global_position.y - BODY_RIDE_HEIGHT
	var thresh := obstacle_height_threshold_m

	var left_excess := maxf(port_h - base_y - thresh, 0.0)
	var center_excess := maxf(center_h - base_y - thresh, 0.0)
	var right_excess := maxf(starboard_h - base_y - thresh, 0.0)

	if left_excess == 0.0 and center_excess == 0.0 and right_excess == 0.0:
		return 0.0

	var side_diff := right_excess - left_excess
	var urgency := 1.0 + center_excess * 0.05
	return clamp(side_diff * urgency, -1.0, 1.0)

func _update_wall_steer() -> void:
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	var exclude: Array[RID] = [get_rid()]
	for t in _tread_nodes:
		exclude.append((t as CollisionObject3D).get_rid())
	params.exclude = exclude

	var right := global_transform.basis.x
	var cast_y := global_position.y - BODY_RIDE_HEIGHT + 10.0
	var carrier_half_width := 40.0

	var origin_r := Vector3(global_position.x, cast_y, global_position.z) + right * carrier_half_width
	var origin_l := Vector3(global_position.x, cast_y, global_position.z) - right * carrier_half_width

	params.from = origin_r
	params.to = origin_r + right * wall_check_dist_m
	var hit_r := space.intersect_ray(params)

	params.from = origin_l
	params.to = origin_l - right * wall_check_dist_m
	var hit_l := space.intersect_ray(params)

	var steer := 0.0
	if hit_r:
		var d := ((hit_r.position as Vector3) - origin_r).length()
		steer -= (1.0 - d / wall_check_dist_m)
	if hit_l:
		var d := ((hit_l.position as Vector3) - origin_l).length()
		steer += (1.0 - d / wall_check_dist_m)
	_wall_steer = clamp(steer, -1.0, 1.0)

func _drive_to_waypoint(delta: float) -> void:
	_wall_check_frame = (_wall_check_frame + 1) % wall_check_interval
	if _wall_check_frame == 0:
		_update_wall_steer()

	if _waypoint_positions.is_empty() or _waypoint_index >= _waypoint_positions.size():
		_no_path_timer += delta
		var avoidance: float = _get_avoidance_steer()
		var combined: float = clamp(avoidance + _wall_steer, -1.0, 1.0)
		_current_steer = combined if abs(combined) > 0.1 else move_toward(_current_steer, 0.0, delta * 2.0)
		_last_planar_speed_mps = 0.0
		if use_waypoint_pathfinding and _no_path_timer > 6.0:
			print("[Carrier] No path for %.0fs - retrying" % _no_path_timer)
			_no_path_timer = 0.0
			_compute_next_path_segment()
		return
	_no_path_timer = 0.0

	var wp: Vector3 = _waypoint_positions[_waypoint_index]
	var to_wp: Vector3 = wp - global_position
	to_wp.y = 0.0
	var wp_dist: float = to_wp.length()

	if wp_dist < waypoint_reach_distance:
		_stuck_timer = 0.0
		_prev_wp_dist = INF
		_waypoint_index += 1
		var next_dist := 0.0
		if _waypoint_index < _waypoint_positions.size():
			var next_wp := _waypoint_positions[_waypoint_index]
			next_dist = Vector2(global_position.x - next_wp.x, global_position.z - next_wp.z).length()
		print("[Carrier] WP reached -> [%d/%d]  next dist=%.0fm" % [
			_waypoint_index, _waypoint_positions.size(), next_dist
		])
		if _waypoint_index >= _waypoint_positions.size():
			_advance_waypoint_or_replan()
		_current_steer = move_toward(_current_steer, 0.0, delta * 2.0)
		_last_planar_speed_mps = 0.0
		return

	if wp_dist > _prev_wp_dist:
		_stuck_timer += delta
		if use_waypoint_pathfinding and _stuck_timer > 20.0:
			print("[Carrier] Stuck (dist growing for 20s) - replanning from current position")
			_stuck_timer = 0.0
			_prev_wp_dist = INF
			_wall_steer = 0.0
			_compute_next_path_segment()
			return
	else:
		_stuck_timer = 0.0
	_prev_wp_dist = wp_dist

	var desired_dir: Vector3 = to_wp.normalized()
	var current_forward: Vector3 = global_transform.basis.z
	current_forward.y = 0.0
	current_forward = current_forward.normalized() if current_forward.length_squared() > 0.0001 else Vector3.FORWARD

	var turn_angle: float = current_forward.signed_angle_to(desired_dir, Vector3.UP)
	var turn_angle_deg: float = abs(rad_to_deg(turn_angle))
	var dot: float = clampf(current_forward.dot(desired_dir), -1.0, 1.0)

	# Signed-angle steering stays decisive even when the waypoint is almost directly behind.
	var wp_steer: float = clampf(turn_angle / deg_to_rad(75.0), -1.0, 1.0)
	var avoidance: float = _get_avoidance_steer()
	var wall_weight: float = 0.4
	if turn_angle_deg > 70.0:
		avoidance *= 0.35
		wall_weight = 0.15
	_current_steer = clamp(wp_steer + avoidance + _wall_steer * wall_weight, -1.0, 1.0)
	rotate_y(_current_steer * turn_speed * delta)

	var throttle: float = clamp((dot + 1.0) * 0.5, 0.0, 1.0) * (1.0 - abs(_current_steer) * 0.3)
	if turn_angle_deg > turn_in_place_angle_deg:
		throttle = 0.0
	var forward: Vector3 = global_transform.basis.z
	global_position.x += forward.x * throttle * max_speed * delta
	global_position.z += forward.z * throttle * max_speed * delta
	_last_planar_speed_mps = throttle * max_speed

func _print_debug_status() -> void:
	var pos := global_position
	var fwd := global_transform.basis.z
	var heading_deg := rad_to_deg(atan2(-fwd.x, -fwd.z))
	var terrain_y := TerrainNavGrid.sample_height(pos.x, pos.z)
	var agl := pos.y - BODY_RIDE_HEIGHT - terrain_y if terrain_y > TerrainNavGrid.IMPASSABLE * 0.5 else NAN

	var wp_str := "none"
	var turn_err_deg := 0.0
	if not _waypoint_positions.is_empty() and _waypoint_index < _waypoint_positions.size():
		var wp := _waypoint_positions[_waypoint_index]
		var to_wp := wp - pos
		to_wp.y = 0.0
		var dist := Vector2(to_wp.x, to_wp.z).length()
		wp_str = "(%d,%d) dist=%.0fm [%d/%d]" % [int(wp.x), int(wp.z), dist, _waypoint_index + 1, _waypoint_positions.size()]
		if to_wp.length_squared() > 0.0001:
			var flat_fwd := fwd
			flat_fwd.y = 0.0
			flat_fwd = flat_fwd.normalized() if flat_fwd.length_squared() > 0.0001 else Vector3.FORWARD
			turn_err_deg = rad_to_deg(flat_fwd.signed_angle_to(to_wp.normalized(), Vector3.UP))

	var raw_dest := "none"
	if not _raw_waypoints.is_empty() and _raw_waypoint_index < _raw_waypoints.size():
		var rd := _raw_waypoints[_raw_waypoint_index]
		var raw_dist := Vector2(rd.x - pos.x, rd.z - pos.z).length()
		raw_dest = "(%d,%d) dist=%.0fm" % [int(rd.x), int(rd.z), raw_dist]

	var avoid := _get_avoidance_steer()
	print("[Carrier] pos=(%d,%d,%d)  hdg=%.0fdeg  AGL=%.1f  spd=%.1fm/s" % [
		int(pos.x), int(pos.y), int(pos.z), heading_deg, agl, _last_planar_speed_mps
	])
	print("[Carrier] steer=%.2f  avoid=%.2f  wall=%.2f  turn=%.0fdeg  stuck=%.0fs  wp=%s  -> %s" % [
		_current_steer, avoid, _wall_steer, turn_err_deg, _stuck_timer, wp_str, raw_dest
	])

# --- Speed / direction API (kept for LandCarrierInput compatibility) ---

func set_speed(_speed: float) -> void:
	pass

func set_direction(_direction: float) -> void:
	pass

func increase_speed(_amount: float = 5.0) -> void:
	pass

func decrease_speed(_amount: float = 5.0) -> void:
	pass

func turn_left(_amount: float = 30.0) -> void:
	pass

func turn_right(_amount: float = 30.0) -> void:
	pass

func get_speed() -> float:
	return max_speed

func get_direction() -> float:
	return rad_to_deg(atan2(-global_transform.basis.z.x, -global_transform.basis.z.z))

func get_elevator() -> Node3D:
	if not elevator:
		elevator = find_child("Elevator")
	return elevator

func get_team() -> int:
	return TEAM_ID
