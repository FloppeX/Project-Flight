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
@export var height_smoothing: float = 2.5  # height tracking speed (higher = snappier)

# --- Terrain feeler avoidance ---
@export var feeler_height_threshold_m: float = 15.0  # terrain rise above carrier base that counts as obstacle

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
var _stuck_timer: float = 0.0
var _prev_wp_dist: float = INF
var _no_path_timer: float = 0.0
var _last_planar_speed_mps: float = 0.0
var _smoothed_desired_y: float = NAN
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
	# Face toward the destination at spawn
	var to_dest := destination - global_position
	to_dest.y = 0.0
	if to_dest.length_squared() > 1.0:
		var dir := to_dest.normalized()
		rotation.y = atan2(dir.x, dir.z)
	_raw_waypoints = [destination]
	_raw_waypoint_index = 0
	_compute_next_path_segment()

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
				path = []
				continue
			break

	if path.is_empty():
		if not _raw_waypoints.is_empty() and _raw_waypoint_index < _raw_waypoints.size():
			var raw_target := _raw_waypoints[_raw_waypoint_index]
			var dist := Vector2(global_position.x - raw_target.x, global_position.z - raw_target.z).length()
			if dist < path_max_segment_m:
				_raw_waypoint_index += 1
				_compute_next_path_segment()
				return

	_on_path_ready(path)

func _pick_new_patrol_destination() -> void:
	var destination: Vector3 = TerrainNavGrid.get_furthest_edge_position(global_position, 3, path_max_slope_m)
	_raw_waypoints = [destination]
	_raw_waypoint_index = 0
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
	var dest := _raw_waypoints[_raw_waypoint_index] if not _raw_waypoints.is_empty() and _raw_waypoint_index < _raw_waypoints.size() else Vector3.ZERO
	# TerrainNavGrid.save_debug_image(_waypoint_positions, global_position, dest, path_max_slope_m)

func _align_to_active_waypoint() -> void:
	if _waypoint_positions.is_empty() or _waypoint_index >= _waypoint_positions.size():
		return
	# Waypoint 0 is often the carrier's own position (from NavGraph).
	# Find the first waypoint that is actually ahead of us.
	var target: Vector3
	var found := false
	for i in range(_waypoint_index, _waypoint_positions.size()):
		var candidate: Vector3 = _waypoint_positions[i]
		var to_candidate := candidate - global_position
		to_candidate.y = 0.0
		if to_candidate.length_squared() > 100.0:  # > 10m away
			target = candidate
			found = true
			break
	if not found:
		return
	var to_target := (target - global_position)
	to_target.y = 0.0
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
		var tread_target_y: float = terrain_y + TREAD_GROUND_OFFSET
		var tread_current_y: float = tread.global_position.y
		var tread_smooth_y: float = lerp(tread_current_y, tread_target_y, clampf(3.0 * delta, 0.0, 1.0))
		tread.global_position = Vector3(world_xz.x, tread_smooth_y, world_xz.z)
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
		var raw_desired_y: float = avg_y + BODY_RIDE_HEIGHT
		# Smooth the desired height target to filter terrain quantization jitter.
		if is_nan(_smoothed_desired_y):
			_smoothed_desired_y = raw_desired_y
		else:
			_smoothed_desired_y = lerp(_smoothed_desired_y, raw_desired_y, clampf(4.0 * delta, 0.0, 1.0))
		global_position.y = lerp(global_position.y, _smoothed_desired_y, clampf(height_smoothing * delta, 0.0, 1.0))


func _sample_terrain_y(wx: float, wz: float) -> float:
	var h: float = TerrainNavGrid.sample_height(wx, wz)
	if h <= TerrainNavGrid.IMPASSABLE * 0.5:
		return global_position.y - BODY_RIDE_HEIGHT
	return h

func _get_avoidance_steer() -> float:
	# Multi-range terrain feelers: sample heights at various offsets around the
	# carrier and steer away from rising terrain.  Uses the baked heightmap so
	# there is no physics cost.
	if not TerrainNavGrid.is_ready():
		return 0.0

	var fwd := global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)  # perpendicular on XZ plane
	var base_y := global_position.y - BODY_RIDE_HEIGHT
	var thresh := feeler_height_threshold_m
	var pos := global_position

	# Feeler layout: (forward_dist, lateral_offset, weight)
	# Positive lateral = starboard, negative = port
	# Close feelers respond more urgently (higher weight)
	var feelers: Array = [
		# Near sides (80m out) — strong push away from adjacent walls
		[0.0,    80.0,  1.8],
		[0.0,   -80.0,  1.8],
		[60.0,   80.0,  1.5],
		[60.0,  -80.0,  1.5],
		# Mid-range forward diagonals (150m ahead, 100m wide)
		[150.0,  100.0, 1.2],
		[150.0, -100.0, 1.2],
		[150.0,  50.0,  0.8],
		[150.0, -50.0,  0.8],
		# Far forward (300m ahead)
		[300.0,  120.0, 0.6],
		[300.0, -120.0, 0.6],
		[300.0,  0.0,   0.4],
	]

	var steer_sum := 0.0
	var weight_sum := 0.0
	for f in feelers:
		var f_fwd: float = float(f[0])
		var f_lat: float = float(f[1])
		var f_wt: float = float(f[2])
		var sample_pos: Vector3 = pos + fwd * f_fwd + right * f_lat
		var h := _sample_terrain_y(sample_pos.x, sample_pos.z)
		var excess := maxf(h - base_y - thresh, 0.0)
		if excess > 0.0:
			var strength := minf(excess / 40.0, 1.0)
			if f_lat > 0.1:
				steer_sum -= strength * f_wt
			elif f_lat < -0.1:
				steer_sum += strength * f_wt
			else:
				weight_sum += strength * f_wt * 0.5
			weight_sum += absf(strength * f_wt)

	if weight_sum < 0.001:
		return 0.0
	return clampf(steer_sum, -1.0, 1.0)

func _drive_to_waypoint(delta: float) -> void:
	if _waypoint_positions.is_empty() or _waypoint_index >= _waypoint_positions.size():
		_no_path_timer += delta
		var avoidance: float = _get_avoidance_steer()
		_current_steer = avoidance if absf(avoidance) > 0.1 else move_toward(_current_steer, 0.0, delta * 2.0)
		_last_planar_speed_mps = 0.0
		if use_waypoint_pathfinding and _no_path_timer > 6.0:
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
		if _waypoint_index >= _waypoint_positions.size():
			_advance_waypoint_or_replan()
		_current_steer = move_toward(_current_steer, 0.0, delta * 2.0)
		_last_planar_speed_mps = 0.0
		return

	if wp_dist > _prev_wp_dist:
		_stuck_timer += delta
		if use_waypoint_pathfinding and _stuck_timer > 20.0:
			_stuck_timer = 0.0
			_prev_wp_dist = INF
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

	var wp_steer: float = clampf(turn_angle / deg_to_rad(75.0), -1.0, 1.0)
	var avoidance: float = _get_avoidance_steer()
	# Avoidance overrides waypoint steering when strong — walls take priority
	var avoid_strength := absf(avoidance)
	var avoid_blend := clampf(avoid_strength * 2.0, 0.0, 1.0)  # full override at 0.5+ avoidance
	_current_steer = clamp(lerpf(wp_steer, wp_steer + avoidance * 2.0, avoid_blend), -1.0, 1.0)
	rotate_y(_current_steer * turn_speed * delta)

	var throttle: float = clamp((dot + 1.0) * 0.5, 0.0, 1.0) * (1.0 - abs(_current_steer) * 0.3)
	if turn_angle_deg > turn_in_place_angle_deg:
		throttle = 0.0
	var forward: Vector3 = global_transform.basis.z
	global_position.x += forward.x * throttle * max_speed * delta
	global_position.z += forward.z * throttle * max_speed * delta
	_last_planar_speed_mps = throttle * max_speed

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
