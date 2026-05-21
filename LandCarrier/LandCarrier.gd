extends CharacterBody3D
class_name LandCarrier

const CARRIER_TREAD_SCRIPT := preload("res://LandCarrier/CarrierTread.gd")
const VEHICLE_RAMP_SCRIPT := preload("res://LandCarrier/VehicleRamp.gd")
const VEHICLE_BAY_SCRIPT := preload("res://LandCarrier/VehicleBayManager.gd")

# --- Waypoints ---
@export var waypoints: Array[NodePath] = []
@export var loop_waypoints: bool = false
@export var waypoint_reach_distance: float = 120.0

# --- Movement ---
@export var max_speed: float = 10.0
@export var acceleration: float = 1.5
@export var turn_speed: float = 0.25
@export var steer_response: float = 2.5
@export var steer_deadzone: float = 0.03
@export var settle_turn_angle_deg: float = 1.5
@export var settle_steer_deadzone: float = 0.08

# --- Height ---
@export var height_smoothing: float = 2.5  # height tracking speed (higher = snappier)
@export var height_deadband_m: float = 0.35
@export var height_target_response: float = 2.0

# --- Terrain feeler avoidance ---
@export var feeler_height_threshold_m: float = 15.0  # terrain rise above carrier base that counts as obstacle

# --- Pathfinding ---
@export var path_max_slope_m: float = 12.0    # max height variation within clearance radius (carrier-specific)
@export var use_waypoint_pathfinding: bool = true
@export var turn_in_place_angle_deg: float = 100.0
@export var default_cross_map_route: bool = true
@export var route_start_edge_margin_m: float = 1800.0
@export var route_goal_edge_margin_m: float = 0.0
@export var route_center_search_width_m: float = 4200.0
@export var route_edge_search_depth_m: float = 3200.0
@export var route_goal_candidate_spacing_m: float = 1200.0
@export var route_setup_debug: bool = false

const BODY_RIDE_HEIGHT: float = 40.0
const TREAD_GROUND_OFFSET: float = 8.0
const MAX_TREAD_STEER: float = 0.4

@export var deck_sound: AudioStream = preload("res://Audio/Carrier/carrier_deck_sound_mono.wav")
@export var deck_sound_bus: String = "Master"
@export var deck_sound_idle_volume_db: float = -16.0
@export var deck_sound_max_volume_db: float = -8.0
@export var deck_sound_pitch_min: float = 0.92
@export var deck_sound_pitch_max: float = 1.05
@export var deck_sound_idle_factor: float = 0.35
@export var deck_sound_full_speed_mps: float = 10.0
@export var deck_sound_unit_size_m: float = 55.0
@export var deck_sound_max_distance_m: float = 420.0

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
var _replan_attempts: int = 0
var _last_planar_speed_mps: float = 0.0
var _smoothed_desired_y: float = NAN
var _using_default_cross_map_route: bool = false
var _default_cross_map_route_completed: bool = false
var treads: Array[Node3D] = []
var elevator: Node3D
var vehicle_ramp: Node3D
var vehicle_bay: Node3D
var _deck_audio_player: AudioStreamPlayer3D
const TEAM_ID: int = 1

func _ready():
	add_to_group("carrier")
	add_to_group("origin_shifter")
	visible = false
	_resolve_waypoints()
	_collect_tread_nodes()
	find_treads()
	elevator = find_child("Elevator")
	if elevator and elevator.has_method("setup"):
		elevator.setup(self)
	_setup_deck_audio()
	_setup_vehicle_ramp()
	if Livery:
		Livery.apply(self)
	if not use_waypoint_pathfinding:
		_apply_direct_waypoints()
		visible = true
	elif _raw_waypoints.is_empty():
		call_deferred("_set_north_heading")
	else:
		call_deferred("_compute_path_to_destination")

func apply_origin_shift(offset: Vector3) -> void:
	for i in range(_raw_waypoints.size()):
		_raw_waypoints[i] -= offset
	for i in range(_waypoint_positions.size()):
		_waypoint_positions[i] -= offset

func _setup_vehicle_ramp() -> void:
	var ramp_node := Node3D.new()
	ramp_node.name = "VehicleRamp"
	ramp_node.set_script(VEHICLE_RAMP_SCRIPT)
	add_child(ramp_node)
	vehicle_ramp = ramp_node
	_setup_vehicle_bay()

func _setup_vehicle_bay() -> void:
	var bay_node := Node3D.new()
	bay_node.name = "VehicleBayManager"
	bay_node.set_script(VEHICLE_BAY_SCRIPT)
	add_child(bay_node)
	vehicle_bay = bay_node

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
	_using_default_cross_map_route = false
	_default_cross_map_route_completed = false
	if not use_waypoint_pathfinding:
		_apply_direct_waypoints()
		return
	_compute_path_to_destination()

func get_active_waypoints() -> Array[Vector3]:
	var active_waypoints: Array[Vector3] = []
	for i in range(_waypoint_index, _waypoint_positions.size()):
		active_waypoints.append(_waypoint_positions[i])
	if active_waypoints.is_empty() and _raw_waypoint_index < _raw_waypoints.size():
		active_waypoints.append(_raw_waypoints[_raw_waypoint_index])
	return active_waypoints

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
	_using_default_cross_map_route = false
	_default_cross_map_route_completed = false

	if default_cross_map_route:
		var routed_start := TerrainNavGrid.get_centered_edge_position(
			"bottom",
			route_start_edge_margin_m,
			route_center_search_width_m,
			route_edge_search_depth_m,
			path_max_slope_m
		)
		if routed_start != Vector3.ZERO:
			global_position = Vector3(routed_start.x, routed_start.y + BODY_RIDE_HEIGHT, routed_start.z)
			visible = true
			var route_plan := _find_shortest_top_edge_route(global_position)
			if bool(route_plan.get("valid", false)):
				var routed_destination: Vector3 = route_plan.get("destination", Vector3.ZERO)
				var routed_path: Array = route_plan.get("path", [])
				var to_dest := routed_destination - global_position
				to_dest.y = 0.0
				if to_dest.length_squared() > 1.0:
					var dir := to_dest.normalized()
					rotation.y = atan2(dir.x, dir.z)
				_raw_waypoints = [routed_destination]
				_raw_waypoint_index = 0
				_using_default_cross_map_route = true
				if route_setup_debug:
					print(
						"[LandCarrier] Using shortest top-edge route start=",
						global_position,
						" goal=",
						routed_destination,
						" edge_depth=",
						snapped(float(route_plan.get("edge_depth_m", 0.0)), 0.1),
						" path_length=",
						snapped(float(route_plan.get("path_length_m", 0.0)), 0.1)
					)
				_on_path_ready(routed_path)
				return
			if route_setup_debug:
				print("[LandCarrier] Could not find a reachable shortest route to the top edge; falling back to patrol start.")
		elif route_setup_debug:
			print("[LandCarrier] Could not find a suitable bottom-edge start anchor; falling back to patrol start.")

	var start: Vector3 = TerrainNavGrid.get_random_passable_position(rng, path_max_slope_m)
	if start != Vector3.ZERO:
		global_position = Vector3(start.x, start.y + BODY_RIDE_HEIGHT, start.z)

	visible = true

	var destination: Vector3 = TerrainNavGrid.get_furthest_edge_position(global_position, 3, path_max_slope_m)
	var to_dest := destination - global_position
	to_dest.y = 0.0
	if to_dest.length_squared() > 1.0:
		var dir := to_dest.normalized()
		rotation.y = atan2(dir.x, dir.z)
	_raw_waypoints = [destination]
	_raw_waypoint_index = 0
	_compute_path_to_destination()

const CARRIER_CLEARANCE_M: float = 120.0

func _find_shortest_top_edge_route(start_world: Vector3) -> Dictionary:
	var candidates := TerrainNavGrid.get_edge_position_candidates(
		"top",
		route_goal_edge_margin_m,
		route_goal_candidate_spacing_m,
		route_edge_search_depth_m,
		path_max_slope_m
	)
	if candidates.is_empty():
		return {"valid": false}

	var best_destination := Vector3.ZERO
	var best_path: Array = []
	var best_path_length_m := INF
	var best_edge_depth_m := INF
	var top_edge_z: float = TerrainNavGrid._origin_z
	for candidate in candidates:
		var path := NavGraph.find_path(start_world, candidate, CARRIER_CLEARANCE_M)
		if path.is_empty():
			continue
		var path_length_m := _measure_path_length(path)
		var edge_depth_m := maxf(candidate.z - top_edge_z, 0.0)
		var is_better_edge := edge_depth_m < best_edge_depth_m - 0.5
		var same_edge_band := absf(edge_depth_m - best_edge_depth_m) <= 0.5
		if is_better_edge or (same_edge_band and path_length_m < best_path_length_m):
			best_edge_depth_m = edge_depth_m
			best_path_length_m = path_length_m
			best_destination = candidate
			best_path = path

	if best_path.is_empty():
		return {"valid": false}

	return {
		"valid": true,
		"destination": best_destination,
		"path": best_path,
		"edge_depth_m": best_edge_depth_m,
		"path_length_m": best_path_length_m
	}

func _measure_path_length(path: Array) -> float:
	if path.size() < 2:
		return 0.0
	var total_length_m := 0.0
	for i in range(1, path.size()):
		var prev_point := path[i - 1] as Vector3
		var next_point := path[i] as Vector3
		total_length_m += prev_point.distance_to(next_point)
	return total_length_m

func _compute_path_to_destination() -> void:
	visible = true
	if _raw_waypoints.is_empty():
		return
	if _raw_waypoint_index >= _raw_waypoints.size():
		if loop_waypoints:
			_raw_waypoint_index = 0
		elif _using_default_cross_map_route:
			_waypoint_positions.clear()
			_waypoint_index = 0
			_default_cross_map_route_completed = true
			_last_planar_speed_mps = 0.0
			return
		else:
			_pick_new_patrol_destination()
			return
	if not use_waypoint_pathfinding:
		_apply_direct_waypoints()
		return

	var target := _raw_waypoints[_raw_waypoint_index]
	var path := NavGraph.find_path(global_position, target, CARRIER_CLEARANCE_M)

	if path.is_empty():
		# Destination unreachable — skip it
		_raw_waypoint_index += 1
		if _raw_waypoint_index >= _raw_waypoints.size():
			_pick_new_patrol_destination()
		else:
			_compute_path_to_destination()
		return

	_on_path_ready(path)

func _pick_new_patrol_destination() -> void:
	_using_default_cross_map_route = false
	_default_cross_map_route_completed = false
	# Try several candidate destinations, pick the furthest one that
	# A* can actually reach with full carrier clearance.
	var best_dest := Vector3.ZERO
	var best_dist_sq := -1.0
	for inset in [3, 5, 8]:
		var dest: Vector3 = TerrainNavGrid.get_furthest_edge_position(global_position, inset, path_max_slope_m)
		if dest == global_position:
			continue
		if not NavGraph.has_nearby_node(dest, CARRIER_CLEARANCE_M):
			continue
		# Verify full path exists before committing
		var test_path := NavGraph.find_path(global_position, dest, CARRIER_CLEARANCE_M)
		if test_path.is_empty():
			continue
		var dsq := Vector2(dest.x - global_position.x, dest.z - global_position.z).length_squared()
		if dsq > best_dist_sq:
			best_dist_sq = dsq
			best_dest = dest
	if best_dist_sq < 0.0:
		# Nothing reachable at edges — try a random passable position
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		best_dest = TerrainNavGrid.get_random_passable_position(rng, path_max_slope_m)
		if best_dest == Vector3.ZERO:
			best_dest = global_position + global_transform.basis.z * 500.0
	_raw_waypoints = [best_dest]
	_raw_waypoint_index = 0
	_compute_path_to_destination()

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
	_compute_path_to_destination()

func _collect_tread_nodes() -> void:
	_tread_nodes.clear()
	_tread_local_xz.clear()
	_tread_initial_rot_y.clear()
	for child in get_children():
		if _is_tread_node(child):
			_tread_nodes.append(child)
			_tread_local_xz.append(Vector2(child.position.x, child.position.z))
			_tread_initial_rot_y.append(child.rotation.y)
			# Attach dust effect to each tread
			if not child.has_node("DustEffect"):
				var dust := DustEffect.new()
				dust.name = "DustEffect"
				dust.spawn_interval_s = 0.5
				dust.puff_scale_min = 2.0
				dust.puff_scale_max = 5.0
				dust.puff_lifetime_s = 5.0
				dust.puff_rise_speed = 8.0
				dust.full_speed_mps = 12.0
				dust.min_speed_mps = 1.0
				child.add_child(dust)

func find_treads() -> void:
	treads.clear()
	for child in get_children():
		if _is_tread_node(child):
			treads.append(child)

func _is_tread_node(node: Node) -> bool:
	return node is Node3D and node.get_script() == CARRIER_TREAD_SCRIPT

func _physics_process(delta: float) -> void:
	var transform_before := global_transform
	_drive_to_waypoint(delta)
	_update_tread_visuals(delta)
	if elevator and elevator.has_method("update"):
		elevator.update(delta)
	_carry_deck_passengers(global_transform, transform_before)
	_update_deck_audio(delta)

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
			var has_deck_follow := n.has_meta("carrier_deck_follow") and bool(n.get_meta("carrier_deck_follow"))
			var helicopter_deck_ready := n.has_meta("helicopter_deck_takeoff_ready") and bool(n.get_meta("helicopter_deck_takeoff_ready"))
			var on_carrier := has_transport or helicopter_deck_ready or has_deck_follow
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
			var target_delta: float = raw_desired_y - _smoothed_desired_y
			if absf(target_delta) > height_deadband_m:
				var filtered_target: float = raw_desired_y - signf(target_delta) * height_deadband_m
				_smoothed_desired_y = lerp(
					_smoothed_desired_y,
					filtered_target,
					clampf(height_target_response * delta, 0.0, 1.0)
				)
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
	var right := global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3(fwd.z, 0.0, -fwd.x)
	right = right.normalized()
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
		if _default_cross_map_route_completed:
			_no_path_timer = 0.0
			_replan_attempts = 0
			_current_steer = move_toward(_current_steer, 0.0, steer_response * delta)
			_last_planar_speed_mps = 0.0
			return
		_no_path_timer += delta
		_last_planar_speed_mps = 0.0
		if use_waypoint_pathfinding and _no_path_timer > 4.0:
			_no_path_timer = 0.0
			_replan_attempts += 1
			if _replan_attempts >= 2:
				_replan_attempts = 0
				_pick_new_patrol_destination()
			else:
				_compute_path_to_destination()
		return
	_no_path_timer = 0.0

	var wp: Vector3 = _waypoint_positions[_waypoint_index]
	var to_wp: Vector3 = wp - global_position
	to_wp.y = 0.0
	var wp_dist: float = to_wp.length()

	if wp_dist < waypoint_reach_distance:
		_stuck_timer = 0.0
		_prev_wp_dist = INF
		_replan_attempts = 0
		_waypoint_index += 1
		if _waypoint_index >= _waypoint_positions.size():
			_advance_waypoint_or_replan()
		_current_steer = move_toward(_current_steer, 0.0, steer_response * delta)
		_last_planar_speed_mps = 0.0
		return

	if wp_dist > _prev_wp_dist:
		_stuck_timer += delta
		if _stuck_timer > 10.0:
			_stuck_timer = 0.0
			_prev_wp_dist = INF
			_replan_attempts += 1
			if _replan_attempts >= 3:
				_replan_attempts = 0
				_pick_new_patrol_destination()
			else:
				# Replan full path from current position
				_compute_path_to_destination()
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
	# Avoidance blends with waypoint steering but cannot fully oppose it.
	# If avoidance and waypoint steer are in opposite directions, cap avoidance
	# so the carrier always retains some forward waypoint progress.
	var avoid_strength := absf(avoidance)
	var opposing := signf(avoidance) != signf(wp_steer) and absf(wp_steer) > 0.1
	var effective_avoidance := avoidance
	if opposing:
		# Cap opposing avoidance so waypoint direction is never fully overridden
		effective_avoidance = clampf(avoidance, -absf(wp_steer) * 0.8, absf(wp_steer) * 0.8)
	var avoid_blend := clampf(avoid_strength * 2.0, 0.0, 1.0)
	var target_steer := clampf(lerpf(wp_steer, wp_steer + effective_avoidance * 2.0, avoid_blend), -1.0, 1.0)
	if absf(target_steer) < steer_deadzone:
		target_steer = 0.0
	_current_steer = move_toward(_current_steer, target_steer, steer_response * delta)
	if turn_angle_deg < settle_turn_angle_deg and absf(avoidance) < steer_deadzone and absf(_current_steer) < settle_steer_deadzone:
		_current_steer = 0.0
	# When turning in place (large angle to waypoint), turn faster to recover sooner
	var effective_turn_speed := turn_speed
	if turn_angle_deg > turn_in_place_angle_deg:
		effective_turn_speed = turn_speed * 2.0
	rotate_y(_current_steer * effective_turn_speed * delta)

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

func get_velocity_vector() -> Vector3:
	var forward: Vector3 = global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	return forward * _last_planar_speed_mps

func get_deck_reference_velocity_vector() -> Vector3:
	var actual_velocity := get_velocity_vector()
	if actual_velocity.length_squared() > 0.0001:
		return actual_velocity
	var forward: Vector3 = global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	return forward * max_speed

func _setup_deck_audio() -> void:
	if deck_sound == null:
		return

	if deck_sound is AudioStreamWAV:
		deck_sound.loop_mode = AudioStreamWAV.LOOP_FORWARD

	_deck_audio_player = AudioStreamPlayer3D.new()
	_deck_audio_player.name = "DeckAudio"
	_deck_audio_player.stream = deck_sound
	_deck_audio_player.bus = deck_sound_bus
	_deck_audio_player.max_distance = deck_sound_max_distance_m
	_deck_audio_player.unit_size = deck_sound_unit_size_m
	_deck_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	_deck_audio_player.volume_db = deck_sound_idle_volume_db
	_deck_audio_player.pitch_scale = deck_sound_pitch_min
	_deck_audio_player.position = _get_deck_audio_anchor_local_position()
	_deck_audio_player.add_to_group("3d_audio")
	add_child(_deck_audio_player)
	_deck_audio_player.call_deferred("play")

func _get_deck_audio_anchor_local_position() -> Vector3:
	var start_marker := get_node_or_null("DeckCenterStart") as Node3D
	var end_marker := get_node_or_null("DeckCenterEnd") as Node3D
	if start_marker and end_marker:
		return (start_marker.position + end_marker.position) * 0.5 + Vector3(0.0, 1.5, 0.0)
	if start_marker:
		return start_marker.position + Vector3(0.0, 1.5, 0.0)
	if end_marker:
		return end_marker.position + Vector3(0.0, 1.5, 0.0)
	return Vector3(0.0, 0.0, 0.0)

func _update_deck_audio(delta: float) -> void:
	if _deck_audio_player == null:
		return

	var speed_factor := clampf(_last_planar_speed_mps / maxf(deck_sound_full_speed_mps, 0.01), 0.0, 1.0)
	speed_factor = speed_factor * speed_factor * (3.0 - 2.0 * speed_factor)
	speed_factor = maxf(deck_sound_idle_factor, speed_factor)
	var target_volume := lerpf(deck_sound_idle_volume_db, deck_sound_max_volume_db, speed_factor)
	var target_pitch := lerpf(deck_sound_pitch_min, deck_sound_pitch_max, speed_factor)
	var blend := clampf(delta * 2.5, 0.0, 1.0)
	_deck_audio_player.volume_db = lerpf(_deck_audio_player.volume_db, target_volume, blend)
	_deck_audio_player.pitch_scale = lerpf(_deck_audio_player.pitch_scale, target_pitch, blend)
	if not _deck_audio_player.playing:
		_deck_audio_player.call_deferred("play")

func get_direction() -> float:
	return rad_to_deg(atan2(-global_transform.basis.z.x, -global_transform.basis.z.z))

func get_elevator() -> Node3D:
	if not elevator:
		elevator = find_child("Elevator")
	return elevator

func get_team() -> int:
	return TEAM_ID
