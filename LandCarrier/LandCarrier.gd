extends CharacterBody3D
class_name LandCarrier

signal initial_placement_completed
signal player_route_rejected(message: String)

const CARRIER_TREAD_SCRIPT := preload("res://LandCarrier/CarrierTread.gd")
const VEHICLE_RAMP_SCRIPT := preload("res://LandCarrier/VehicleRamp.gd")
const VEHICLE_BAY_SCRIPT := preload("res://LandCarrier/VehicleBayManager.gd")
const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")
const TRACK_MARK_FADE_SHADER := preload("res://LandCarrier/track_mark_fade.gdshader")
const PERF_OVERRIDE_PATH := "user://land_carrier_perf_override.json"

# --- Waypoints ---
@export var waypoints: Array[NodePath] = []
@export var loop_waypoints: bool = false
@export var waypoint_reach_distance: float = 120.0

# --- Movement ---
@export var max_speed: float = 10.0
@export var acceleration: float = 1.5
@export var deceleration: float = 2.5
@export var turn_speed: float = 0.25
## Angular acceleration/deceleration in radians per second squared. Keeping
## these separate from turn_speed gives the carrier rotational inertia instead
## of stepping directly to the axle-limited yaw rate.
@export var turn_acceleration: float = 0.04
@export var turn_deceleration: float = 0.08
@export_range(0.0, 0.9, 0.05) var turn_speed_slowdown: float = 0.45
@export var steering_axle_half_wheelbase_m: float = 48.0
@export_range(0.0, 1.5, 0.05) var rear_axle_steer_ratio: float = 1.0
@export var hard_turn_crawl_speed_mps: float = 2.0
@export var steer_response: float = 2.5
@export var steer_deadzone: float = 0.03
@export var settle_turn_angle_deg: float = 1.5
@export var settle_steer_deadzone: float = 0.08
@export var recovery_constraint_default_speed_limit_mps: float = 0.0
@export var recovery_constraint_log_interval_s: float = 2.0
@export var debug_motion_constraints: bool = false
@export var launch_constraint_min_speed_mps: float = 8.0  # keep the deck moving straight (not dead-stopped) while launching
@export_group("Carrier Command Scheduling")
@export var multi_rate_drive_commands_enabled: bool = true
@export_range(0.02, 0.25, 0.01) var drive_command_update_interval_s: float = 0.10
@export_group("")

# --- Height ---
@export var height_smoothing: float = 2.5  # height tracking speed (higher = snappier)
@export var height_deadband_m: float = 0.35
@export var height_target_response: float = 2.0
@export var tread_ground_sample_half_length_m: float = 16.0
@export var tread_ground_follow_response: float = 5.0
@export var tread_pitch_response: float = 5.0
@export var tread_pitch_sign: float = -1.0

@export_group("Carrier Visual Budget")
@export var tread_detail_budget_enabled: bool = true
@export var tread_detail_distance_m: float = 1200.0
@export var tread_far_update_interval_s: float = 0.5

# --- Deck carry ---
@export var helicopter_deck_carry_half_width_m: float = 90.0
@export var helicopter_deck_carry_half_length_m: float = 160.0
@export var helicopter_deck_carry_height_margin_m: float = 130.0

# --- Terrain feeler avoidance ---
@export var feeler_height_threshold_m: float = 15.0  # terrain rise above carrier base that counts as obstacle

# --- Pathfinding ---
@export var path_max_slope_m: float = 12.0    # max height variation within clearance radius (carrier-specific)
@export var use_waypoint_pathfinding: bool = true
@export var turn_in_place_angle_deg: float = 100.0
## Disabled in normal play: after safe placement, the carrier waits for a player order.
@export var automatic_patrol_enabled: bool = false
@export var default_cross_map_route: bool = true
@export var route_start_edge_margin_m: float = 1800.0
@export var route_goal_edge_margin_m: float = 0.0
@export var route_center_search_width_m: float = 4200.0
@export var route_edge_search_depth_m: float = 3200.0
@export var route_goal_candidate_spacing_m: float = 1200.0
@export var spawn_clearance_radius_m: float = 320.0
@export var spawn_clearance_max_height_variation_m: float = 30.0
@export var aircraft_launch_corridor_distance_m: float = 800.0
@export var aircraft_launch_corridor_half_width_m: float = 140.0
@export var aircraft_launch_corridor_max_terrain_rise_m: float = 80.0
@export var route_setup_debug: bool = false

const BODY_RIDE_HEIGHT: float = 40.0
const TREAD_GROUND_OFFSET: float = 9.0
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

@export_group("Ground Track Marks")
@export var track_marks_enabled: bool = true
@export var track_mark_lifetime_s: float = 30.0
@export var track_mark_min_speed_mps: float = 0.1
@export var track_mark_spawn_spacing_m: float = 0.0
@export var track_mark_width_m: float = 0.0
@export var track_mark_length_m: float = 0.0
@export var track_mark_thickness_m: float = 0.035
@export var track_mark_ground_offset_m: float = 0.06
@export_range(0.0, 1.0, 0.01) var track_mark_darken_factor: float = 0.82
@export_range(0.0, 1.0, 0.01) var track_mark_max_luminance: float = 1.0
@export var track_mark_fallback_color: Color = Color(0.58, 0.39, 0.21, 1.0)
@export var track_mark_max_active: int = 240

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
var _current_planar_speed_mps: float = 0.0
var _current_yaw_rate_rad_s: float = 0.0
var _recovery_constraint_log_s: float = 0.0
var _drive_command_timer_s: float = 0.0
var _drive_command_elapsed_s: float = 0.0
var _drive_command_interval_scale: float = 1.0
var _drive_target_speed_mps: float = 0.0
var _drive_target_yaw_rate_rad_s: float = 0.0
var _smoothed_desired_y: float = NAN
var _using_default_cross_map_route: bool = false
var _default_cross_map_route_completed: bool = false
var _player_route_active: bool = false
var _last_player_route_error: String = ""
var _is_pathfinding: bool = false
var treads: Array[Node3D] = []
var elevator: Node3D
var vehicle_ramp: Node3D
var vehicle_bay: Node3D
var _deck_audio_player: AudioStreamPlayer3D
var _track_mark_root: MultiMeshInstance3D = null
var _track_mark_multimesh: MultiMesh = null
var _track_mark_mesh: BoxMesh = null
var _track_mark_material: ShaderMaterial = null
var _track_mark_entries: Array[Dictionary] = []
var _track_mark_tread_states: Dictionary = {}
var _track_mark_debug_log_interval_s: float = 0.0
var _track_mark_debug_log_timer_s: float = 0.0
var _track_mark_multimesh_dirty: bool = false
var _track_mark_clock_s: float = 0.0
var _track_mark_free_slots: Array[int] = []
var _terrain_provider: Node = null
var _heli_test_stationary: bool = false
var _tread_detail_enabled: bool = true
var _tread_far_update_timer_s: float = 0.0
var _initial_placement_completed: bool = false
const TEAM_ID: int = 1

func _ready():
	add_to_group("carrier")
	add_to_group("origin_shifter")
	var command_phase: float = float(get_instance_id() % 997) / 997.0
	_drive_command_interval_scale = lerpf(0.90, 1.10, command_phase)
	_drive_command_timer_s = maxf(drive_command_update_interval_s, 0.02) * command_phase
	visible = false
	_apply_perf_override()
	_resolve_waypoints()
	_collect_tread_nodes()
	find_treads()
	elevator = find_child("Elevator")
	if elevator and elevator.has_method("setup"):
		elevator.setup(self)
	_setup_deck_audio()
	_setup_vehicle_ramp()
	var session := get_node_or_null("/root/GameSession")
	if session != null and session.has_method("apply_to_carrier"):
		session.call("apply_to_carrier", self)
	else:
		var livery := get_node_or_null("/root/Livery")
		if livery != null and livery.has_method("apply"):
			livery.call("apply", self)
	if not use_waypoint_pathfinding:
		# Initial scene placement may choose its authored heading instantly because
		# the carrier is still hidden and has no deck passengers yet. Runtime route
		# changes must go through the tracked steering controller below.
		if not _raw_waypoints.is_empty():
			_face_route_destination(_raw_waypoints[0])
		_apply_direct_waypoints()
		visible = true
		_mark_initial_placement_completed()
	elif _raw_waypoints.is_empty():
		call_deferred("_set_north_heading")
	else:
		# Authored waypoints keep the carrier at its authored start position; only
		# the no-waypoint random-patrol branch relocates it asynchronously.
		if not _raw_waypoints.is_empty():
			_face_route_destination(_raw_waypoints[0])
		_mark_initial_placement_completed()
		call_deferred("_compute_path_to_destination")


func is_initial_placement_complete() -> bool:
	return _initial_placement_completed


func _mark_initial_placement_completed() -> void:
	if _initial_placement_completed:
		return
	_initial_placement_completed = true
	initial_placement_completed.emit()

func _apply_perf_override() -> void:
	if not FileAccess.file_exists(PERF_OVERRIDE_PATH):
		return
	var file := FileAccess.open(PERF_OVERRIDE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	if data.has("track_marks_enabled"):
		track_marks_enabled = bool(data.get("track_marks_enabled"))
	if data.has("track_mark_max_active"):
		track_mark_max_active = maxi(int(data.get("track_mark_max_active")), 0)
	if data.has("track_mark_lifetime_s"):
		track_mark_lifetime_s = maxf(float(data.get("track_mark_lifetime_s")), 0.01)
	if data.has("track_mark_spawn_spacing_m"):
		track_mark_spawn_spacing_m = maxf(float(data.get("track_mark_spawn_spacing_m")), 0.0)
	if data.has("track_mark_min_speed_mps"):
		track_mark_min_speed_mps = maxf(float(data.get("track_mark_min_speed_mps")), 0.0)
	if data.has("track_mark_debug_log_interval_s"):
		_track_mark_debug_log_interval_s = maxf(float(data.get("track_mark_debug_log_interval_s")), 0.0)
		_track_mark_debug_log_timer_s = _track_mark_debug_log_interval_s
	print("[LandCarrierPerfOverride] track_marks_enabled=%s max_active=%d lifetime=%.1f spacing=%.2f min_speed=%.2f gpu_fade=true debug_interval=%.1f" % [
		str(track_marks_enabled),
		track_mark_max_active,
		track_mark_lifetime_s,
		track_mark_spawn_spacing_m,
		track_mark_min_speed_mps,
		_track_mark_debug_log_interval_s,
	])

func apply_origin_shift(offset: Vector3) -> void:
	for i in range(_raw_waypoints.size()):
		_raw_waypoints[i] -= offset
	for i in range(_waypoint_positions.size()):
		_waypoint_positions[i] -= offset
	for tread_id_variant in _track_mark_tread_states.keys():
		var tread_state: Dictionary = _track_mark_tread_states[tread_id_variant]
		var tread_transform_variant: Variant = tread_state.get("transform", Transform3D.IDENTITY)
		if tread_transform_variant is Transform3D:
			var tread_transform: Transform3D = tread_transform_variant
			tread_transform.origin -= offset
			tread_state["transform"] = tread_transform
			_track_mark_tread_states[tread_id_variant] = tread_state
	for i in _track_mark_entries.size():
		var entry: Dictionary = _track_mark_entries[i]
		var transform_variant: Variant = entry.get("transform", Transform3D.IDENTITY)
		var mark_transform: Transform3D = transform_variant if transform_variant is Transform3D else Transform3D.IDENTITY
		mark_transform.origin -= offset
		entry["transform"] = mark_transform
		_track_mark_entries[i] = entry
	_track_mark_multimesh_dirty = true
	_sync_track_mark_multimesh(true)


func set_heli_test_stationary(active: bool) -> void:
	_heli_test_stationary = active
	_current_planar_speed_mps = 0.0
	_last_planar_speed_mps = 0.0
	_current_yaw_rate_rad_s = 0.0
	_current_steer = 0.0
	_tread_steer = 0.0
	_drive_target_speed_mps = 0.0
	_drive_target_yaw_rate_rad_s = 0.0
	velocity = Vector3.ZERO
	if active:
		visible = true
		_waypoint_positions.clear()
		_waypoint_index = 0
		_no_path_timer = 0.0
		_stuck_timer = 0.0
	else:
		call_deferred("_compute_path_to_destination")

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
	_player_route_active = false
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


func set_player_patrol_waypoints(positions: Array[Vector3]) -> bool:
	_last_player_route_error = get_player_route_error(positions)
	if not _last_player_route_error.is_empty():
		push_warning("[LandCarrier] Rejected player route: %s" % _last_player_route_error)
		return false
	set_patrol_waypoints(positions)
	_player_route_active = true
	return true


func get_player_route_error(positions: Array[Vector3]) -> String:
	if positions.is_empty():
		return "ADD AT LEAST ONE ROUTE POINT"
	for position in positions:
		var point_error := get_player_route_point_error(position)
		if not point_error.is_empty():
			return point_error
	return ""


func get_player_route_point_error(position: Vector3) -> String:
	if not MapFogOfWar.is_initialized() or not MapFogOfWar.is_world_explored(position):
		return "AREA UNKNOWN - SCOUT WITH AIRCRAFT"
	if not TerrainNavGrid.is_ready() or not NavGraph.is_ready():
		return "CARRIER NAVIGATION NOT READY"
	var terrain_y := TerrainNavGrid.sample_height(position.x, position.z)
	if terrain_y <= TerrainNavGrid.IMPASSABLE * 0.5:
		return "DESTINATION BLOCKED - PICK FLAT OPEN GROUND"
	if not TerrainNavGrid.is_clear_position(position.x, position.z, path_max_slope_m):
		return "DESTINATION BLOCKED - PICK FLAT OPEN GROUND"
	if not TerrainNavGrid.is_stable_footprint(
			position.x,
			position.z,
			CARRIER_CLEARANCE_M,
			path_max_slope_m,
			path_max_slope_m
	):
		return "DESTINATION TOO TIGHT FOR CARRIER"
	var grounded_position := Vector3(position.x, terrain_y, position.z)
	if not NavGraph.can_anchor(
			grounded_position,
			CARRIER_CLEARANCE_M,
			maxf(waypoint_reach_distance, 1.0)
	):
		return "NO CARRIER-SAFE ROUTE AT DESTINATION"
	return ""


func get_last_player_route_error() -> String:
	return _last_player_route_error


func hold_position() -> void:
	_last_player_route_error = ""
	_clear_route_and_hold()

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

func _set_north_heading() -> void:
	if not use_waypoint_pathfinding:
		visible = true
		return
	if NavGraph.is_ready():
		_start_random_patrol()
	else:
		NavGraph.graph_ready.connect(_start_random_patrol, CONNECT_ONE_SHOT)

func _start_random_patrol() -> void:
	if _heli_test_stationary:
		visible = true
		_mark_initial_placement_completed()
		return
	if _is_pathfinding:
		return
	_is_pathfinding = true

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_using_default_cross_map_route = false
	_default_cross_map_route_completed = false

	var is_default_route := default_cross_map_route
	var start_margin := route_start_edge_margin_m
	var search_width := route_center_search_width_m
	var search_depth := route_edge_search_depth_m
	var max_slope := path_max_slope_m
	var goal_margin := route_goal_edge_margin_m
	var candidate_spacing := route_goal_candidate_spacing_m
	var spawn_clear_radius := maxf(spawn_clearance_radius_m, 0.0)
	var spawn_clear_variation := maxf(spawn_clearance_max_height_variation_m, 0.1)
	var launch_corridor_distance := maxf(aircraft_launch_corridor_distance_m, 0.0)
	var launch_corridor_half_width := maxf(aircraft_launch_corridor_half_width_m, 0.0)
	var launch_corridor_max_rise := maxf(aircraft_launch_corridor_max_terrain_rise_m, 0.0)
	var setup_debug := route_setup_debug
	var body_ride_h := BODY_RIDE_HEIGHT
	var current_pos := global_position
	var build_automatic_patrol := automatic_patrol_enabled
	var initial_heading := global_transform.basis.z
	initial_heading.y = 0.0
	if initial_heading.length_squared() <= 0.001:
		initial_heading = Vector3.FORWARD
	else:
		initial_heading = initial_heading.normalized()

	var work: Callable = func() -> Dictionary:
		var routed_destination := Vector3.ZERO
		var routed_path: Array[Vector3] = []
		var final_pos := current_pos
		var using_cross_route := false
		var fallback_patrol := false
		var placement_ready := false
		var route_plan_details := {}

		if is_default_route:
			var routed_start := TerrainNavGrid.get_centered_edge_position(
				"bottom",
				start_margin,
				search_width,
				search_depth,
				max_slope,
				spawn_clear_radius,
				spawn_clear_variation
			)
			if routed_start != Vector3.ZERO:
				final_pos = Vector3(routed_start.x, routed_start.y + body_ride_h, routed_start.z)
				if not build_automatic_patrol:
					placement_ready = launch_corridor_distance <= 0.0 \
							or TerrainNavGrid.is_directional_launch_corridor_clear(
								final_pos.x,
								final_pos.z,
								initial_heading.x,
								initial_heading.z,
								launch_corridor_distance,
								launch_corridor_half_width,
								launch_corridor_max_rise
							)

				# Inline _find_shortest_top_edge_route logic. Normal gameplay only
				# needs the safe placement above; it skips this expensive route search.
				var candidates := TerrainNavGrid.get_edge_position_candidates(
					"top",
					goal_margin,
					candidate_spacing,
					search_depth,
					max_slope
				)
				if build_automatic_patrol and not candidates.is_empty():
					var best_dest := Vector3.ZERO
					var best_p: Array[Vector3] = []
					var best_p_len := INF
					var best_e_depth := INF
					var top_edge_z: float = TerrainNavGrid._origin_z
					for candidate in candidates:
						var departure_dir: Vector3 = candidate - final_pos
						departure_dir.y = 0.0
						if launch_corridor_distance > 0.0 and not TerrainNavGrid.is_directional_launch_corridor_clear(
								final_pos.x,
								final_pos.z,
								departure_dir.x,
								departure_dir.z,
								launch_corridor_distance,
								launch_corridor_half_width,
								launch_corridor_max_rise
						):
							continue
						var path := NavGraph.find_path(final_pos, candidate, CARRIER_CLEARANCE_M)
						if path.is_empty():
							continue

						# Measure path length
						var path_length_m := 0.0
						if path.size() >= 2:
							for i in range(1, path.size()):
								path_length_m += path[i - 1].distance_to(path[i])

						var edge_depth_m := maxf(candidate.z - top_edge_z, 0.0)
						var is_better_edge := edge_depth_m < best_e_depth - 0.5
						var same_edge_band := absf(edge_depth_m - best_e_depth) <= 0.5
						if is_better_edge or (same_edge_band and path_length_m < best_p_len):
							best_e_depth = edge_depth_m
							best_p_len = path_length_m
							best_dest = candidate
							best_p = path

					if not best_p.is_empty():
						routed_destination = best_dest
						routed_path = best_p
						using_cross_route = true
						route_plan_details = {
							"edge_depth_m": best_e_depth,
							"path_length_m": best_p_len
						}

		if not build_automatic_patrol:
			if not placement_ready:
				for _attempt in range(32):
					var start := TerrainNavGrid.get_random_passable_position(
						rng, max_slope, 4000, spawn_clear_radius, spawn_clear_variation)
					if start == Vector3.ZERO:
						continue
					var candidate_pos := Vector3(start.x, start.y + body_ride_h, start.z)
					if launch_corridor_distance > 0.0 and not TerrainNavGrid.is_directional_launch_corridor_clear(
							candidate_pos.x,
							candidate_pos.z,
							initial_heading.x,
							initial_heading.z,
							launch_corridor_distance,
							launch_corridor_half_width,
							launch_corridor_max_rise
					):
						continue
					final_pos = candidate_pos
					placement_ready = true
					break
			return {
				"routed_path": routed_path,
				"routed_destination": routed_destination,
				"final_pos": final_pos,
				"using_cross_route": false,
				"fallback_patrol": false,
				"route_plan_details": route_plan_details,
			}

		if routed_path.is_empty():
			# Fallback to standard random patrol, but do not discard the launch-lane
			# guarantee merely because the preferred cross-map route was unavailable.
			for _attempt in range(32):
				var start := TerrainNavGrid.get_random_passable_position(
					rng, max_slope, 4000, spawn_clear_radius, spawn_clear_variation)
				if start == Vector3.ZERO:
					continue
				var fallback_pos := Vector3(start.x, start.y + body_ride_h, start.z)
				var destination := TerrainNavGrid.get_furthest_edge_position(fallback_pos, 3, max_slope)
				var departure_dir: Vector3 = destination - fallback_pos
				departure_dir.y = 0.0
				if launch_corridor_distance > 0.0 and not TerrainNavGrid.is_directional_launch_corridor_clear(
						fallback_pos.x,
						fallback_pos.z,
						departure_dir.x,
						departure_dir.z,
						launch_corridor_distance,
						launch_corridor_half_width,
						launch_corridor_max_rise
				):
					continue
				var fallback_path: Array[Vector3] = NavGraph.find_path(fallback_pos, destination, CARRIER_CLEARANCE_M)
				if fallback_path.is_empty():
					continue
				final_pos = fallback_pos
				routed_destination = destination
				routed_path = fallback_path
				fallback_patrol = true
				break

		return {
			"routed_path": routed_path,
			"routed_destination": routed_destination,
			"final_pos": final_pos,
			"using_cross_route": using_cross_route,
			"fallback_patrol": fallback_patrol,
			"route_plan_details": route_plan_details,
		}

	var job_id: int = NavPathScheduler.request_work(work, _on_random_patrol_job_result, 1, "LandCarrier.random_patrol")
	if job_id < 0:
		_is_pathfinding = false
		visible = true
		_mark_initial_placement_completed()

func _on_random_patrol_job_result(result: Variant) -> void:
	if not result is Dictionary:
		_is_pathfinding = false
		visible = true
		_mark_initial_placement_completed()
		return
	var data: Dictionary = result as Dictionary
	_on_random_patrol_computed(
		data.get("routed_path", []),
		data.get("routed_destination", Vector3.ZERO),
		data.get("final_pos", global_position),
		bool(data.get("using_cross_route", false)),
		bool(data.get("fallback_patrol", false)),
		data.get("route_plan_details", {}))

func _on_random_patrol_computed(routed_path: Array[Vector3], routed_destination: Vector3, final_pos: Vector3, using_cross_route: bool, fallback_patrol: bool, route_plan_details: Dictionary) -> void:
	_is_pathfinding = false
	if not is_instance_valid(self):
		return
	if _heli_test_stationary:
		visible = true
		return

	global_position = final_pos
	visible = true
	_mark_initial_placement_completed()
	if not automatic_patrol_enabled:
		# The route search also gives us a launch-safe initial heading. Keep that
		# heading and placement, but do not turn the search result into an order.
		if using_cross_route or fallback_patrol:
			_face_route_destination(routed_destination)
		_clear_route_and_hold()
		return

	if using_cross_route:
		_face_route_destination(routed_destination)
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
				snapped(float(route_plan_details.get("edge_depth_m", 0.0)), 0.1),
				" path_length=",
				snapped(float(route_plan_details.get("path_length_m", 0.0)), 0.1)
			)
		_on_path_ready(routed_path)
		return

	if fallback_patrol:
		_face_route_destination(routed_destination)
		_raw_waypoints = [routed_destination]
		_raw_waypoint_index = 0

		if routed_path.is_empty():
			# Try standard replan
			_compute_path_to_destination()
		else:
			_on_path_ready(routed_path)

const CARRIER_CLEARANCE_M: float = 120.0


func _face_route_destination(destination: Vector3) -> void:
	var to_dest := destination - global_position
	to_dest.y = 0.0
	if to_dest.length_squared() <= 1.0:
		return
	var direction := to_dest.normalized()
	rotation.y = atan2(direction.x, direction.z)


func _clear_route_and_hold() -> void:
	_raw_waypoints.clear()
	_raw_waypoint_index = 0
	_waypoint_positions.clear()
	_waypoint_index = 0
	_using_default_cross_map_route = false
	_default_cross_map_route_completed = false
	_player_route_active = false
	_stuck_timer = 0.0
	_prev_wp_dist = INF
	_no_path_timer = 0.0
	_replan_attempts = 0
	_drive_target_speed_mps = 0.0
	_drive_target_yaw_rate_rad_s = 0.0
	velocity = Vector3.ZERO


func _pick_automatic_patrol_or_hold() -> void:
	if automatic_patrol_enabled:
		_pick_new_patrol_destination()
	else:
		_clear_route_and_hold()

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
			return
		else:
			_pick_automatic_patrol_or_hold()
			return
	if not use_waypoint_pathfinding:
		_apply_direct_waypoints()
		return
	if _is_pathfinding:
		return
	_is_pathfinding = true

	var target := _raw_waypoints[_raw_waypoint_index]
	var current_pos := global_position

	var callback: Callable = func(path: Array[Vector3]) -> void:
		_on_path_computed(path, target)
	var job_id: int = NavPathScheduler.request_find_path(current_pos, target, CARRIER_CLEARANCE_M, callback, 1, "LandCarrier.path")
	if job_id < 0:
		_is_pathfinding = false

func _on_path_computed(path: Array[Vector3], target_at_request: Vector3) -> void:
	_is_pathfinding = false
	if not is_instance_valid(self):
		return

	if _raw_waypoints.is_empty() or _raw_waypoint_index >= _raw_waypoints.size() or _raw_waypoints[_raw_waypoint_index] != target_at_request:
		_compute_path_to_destination()
		return

	if path.is_empty():
		if _player_route_active:
			_last_player_route_error = "NO CARRIER-SAFE PATH TO DESTINATION"
			player_route_rejected.emit(_last_player_route_error)
			_clear_route_and_hold()
			return
		_raw_waypoint_index += 1
		if _raw_waypoint_index >= _raw_waypoints.size():
			_pick_automatic_patrol_or_hold()
		else:
			_compute_path_to_destination()
		return

	_on_path_ready(path)

func _pick_new_patrol_destination() -> void:
	if _is_pathfinding:
		return
	_is_pathfinding = true

	_using_default_cross_map_route = false
	_default_cross_map_route_completed = false

	var current_pos := global_position
	var max_slope := path_max_slope_m

	var work: Callable = func() -> Dictionary:
		var best_dest := Vector3.ZERO
		var best_dist_sq := -1.0
		var best_path: Array[Vector3] = []

		for inset in [3, 5, 8]:
			var dest: Vector3 = TerrainNavGrid.get_furthest_edge_position(current_pos, inset, max_slope)
			if dest == current_pos:
				continue
			if not NavGraph.has_nearby_node(dest, CARRIER_CLEARANCE_M):
				continue
			var test_path := NavGraph.find_path(current_pos, dest, CARRIER_CLEARANCE_M)
			if test_path.is_empty():
				continue
			var dsq := Vector2(dest.x - current_pos.x, dest.z - current_pos.z).length_squared()
			if dsq > best_dist_sq:
				best_dist_sq = dsq
				best_dest = dest
				best_path = test_path

		var rng_fallback := false
		if best_dist_sq < 0.0:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			best_dest = TerrainNavGrid.get_random_passable_position(rng, max_slope)
			rng_fallback = true

		return {
			"best_path": best_path,
			"best_dest": best_dest,
			"rng_fallback": rng_fallback,
		}

	var job_id: int = NavPathScheduler.request_work(work, _on_pick_new_patrol_job_result, 1, "LandCarrier.pick_patrol")
	if job_id < 0:
		_is_pathfinding = false

func _on_pick_new_patrol_job_result(result: Variant) -> void:
	if not result is Dictionary:
		_is_pathfinding = false
		return
	var data: Dictionary = result as Dictionary
	_on_pick_new_patrol_computed(
		data.get("best_path", []),
		data.get("best_dest", Vector3.ZERO),
		bool(data.get("rng_fallback", false)))

func _on_pick_new_patrol_computed(best_path: Array[Vector3], best_dest: Vector3, rng_fallback: bool) -> void:
	_is_pathfinding = false
	if not is_instance_valid(self):
		return

	var final_dest := best_dest
	if rng_fallback and best_dest == Vector3.ZERO:
		final_dest = global_position + global_transform.basis.z * 500.0

	_raw_waypoints = [final_dest]
	_raw_waypoint_index = 0

	if best_path.is_empty():
		_compute_path_to_destination()
	else:
		_on_path_ready(best_path)

func _on_path_ready(path: Array) -> void:
	_waypoint_positions.clear()
	for p in path:
		_waypoint_positions.append(p as Vector3)
	_waypoint_index = 0
	_stuck_timer = 0.0
	_prev_wp_dist = INF
	var total_dist := 0.0
	for i in range(1, _waypoint_positions.size()):
		total_dist += Vector2(
			_waypoint_positions[i].x - _waypoint_positions[i - 1].x,
			_waypoint_positions[i].z - _waypoint_positions[i - 1].z
		).length()
	var dest := _raw_waypoints[_raw_waypoint_index] if not _raw_waypoints.is_empty() and _raw_waypoint_index < _raw_waypoints.size() else Vector3.ZERO
	# TerrainNavGrid.save_debug_image(_waypoint_positions, global_position, dest, path_max_slope_m)

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
				_pick_automatic_patrol_or_hold()
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
	var _profiler_start: int = FrameProfiler.begin("LandCarrier.physics")
	if _heli_test_stationary:
		velocity = Vector3.ZERO
		_current_planar_speed_mps = 0.0
		_last_planar_speed_mps = 0.0
		_current_yaw_rate_rad_s = 0.0
		if elevator and elevator.has_method("update"):
			var _stationary_elevator_profiler_start: int = FrameProfiler.begin("LandCarrier.elevator_update")
			elevator.update(delta)
			FrameProfiler.end("LandCarrier.elevator_update", _stationary_elevator_profiler_start)
		var _stationary_audio_profiler_start: int = FrameProfiler.begin("LandCarrier.deck_audio")
		_update_deck_audio(delta)
		FrameProfiler.end("LandCarrier.deck_audio", _stationary_audio_profiler_start)
		var _stationary_track_marks_profiler_start: int = FrameProfiler.begin("LandCarrier.track_marks")
		_update_track_marks(delta, global_transform)
		FrameProfiler.end("LandCarrier.track_marks", _stationary_track_marks_profiler_start)
		FrameProfiler.end("LandCarrier.physics", _profiler_start)
		return
	var transform_before := global_transform
	var _drive_profiler_start: int = FrameProfiler.begin("LandCarrier.drive_to_waypoint")
	_drive_to_waypoint(delta)
	FrameProfiler.end("LandCarrier.drive_to_waypoint", _drive_profiler_start)
	var _tread_visuals_profiler_start: int = FrameProfiler.begin("LandCarrier.tread_visuals")
	_update_tread_visuals(delta, transform_before)
	FrameProfiler.end("LandCarrier.tread_visuals", _tread_visuals_profiler_start)
	var _track_marks_profiler_start: int = FrameProfiler.begin("LandCarrier.track_marks")
	_update_track_marks(delta, transform_before)
	FrameProfiler.end("LandCarrier.track_marks", _track_marks_profiler_start)
	if elevator and elevator.has_method("update"):
		var _elevator_profiler_start: int = FrameProfiler.begin("LandCarrier.elevator_update")
		elevator.update(delta)
		FrameProfiler.end("LandCarrier.elevator_update", _elevator_profiler_start)
	var _carry_profiler_start: int = FrameProfiler.begin("LandCarrier.carry_deck_passengers")
	_carry_deck_passengers(global_transform, transform_before)
	FrameProfiler.end("LandCarrier.carry_deck_passengers", _carry_profiler_start)
	var _audio_profiler_start: int = FrameProfiler.begin("LandCarrier.deck_audio")
	_update_deck_audio(delta)
	FrameProfiler.end("LandCarrier.deck_audio", _audio_profiler_start)
	FrameProfiler.end("LandCarrier.physics", _profiler_start)

func _carry_deck_passengers(current_transform: Transform3D, old_transform: Transform3D) -> void:
	if current_transform.is_equal_approx(old_transform):
		return
	var transform_delta: Transform3D = current_transform * old_transform.affine_inverse()
	var carried_nodes: Dictionary = {}
	for group in ["aircraft", "ai_aircraft", "tractor_bot"]:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or not node is Node3D:
				continue
			var instance_id: int = node.get_instance_id()
			if carried_nodes.has(instance_id):
				continue
			carried_nodes[instance_id] = true
			var n: Node = node as Node
			var has_brake: bool = n.has_meta("parking_brake") and bool(n.get_meta("parking_brake"))
			var has_transport: bool = n.has_meta("carrier_transport_mode") and bool(n.get_meta("carrier_transport_mode"))
			var manual_transport: bool = n.has_meta("carrier_manual_transport") and bool(n.get_meta("carrier_manual_transport"))
			if manual_transport:
				continue
			var has_deck_follow: bool = n.has_meta("carrier_deck_follow") and bool(n.get_meta("carrier_deck_follow"))
			var helicopter_deck_ready: bool = n.has_meta("helicopter_deck_takeoff_ready") and bool(n.get_meta("helicopter_deck_takeoff_ready"))
			# A retrieved fixed-wing aircraft is frozen at the latch while terrain and
			# carrier-turn launch interlocks are checked. It still has its parking brake,
			# so the older on_catapult predicate omitted it and the carrier moved out from
			# underneath it. Keep that explicit handoff state carrier-relative too.
			var waiting_for_catapult: bool = node is RigidBody3D \
					and (node as RigidBody3D).freeze \
					and bool(n.get_meta("physics_ready_for_launch", false))
			var is_helicopter: bool = _is_helicopter_deck_passenger(n)
			var on_carrier: bool = has_transport or helicopter_deck_ready or has_deck_follow
			if is_helicopter:
				var frozen_body := node is RigidBody3D and (node as RigidBody3D).freeze
				on_carrier = frozen_body and (
					has_transport
					or helicopter_deck_ready
					or (has_brake and _is_node_in_helicopter_deck_carry_zone(node as Node3D))
				)
			var on_catapult: bool = n.has_meta("controls_disabled") and bool(n.get_meta("controls_disabled")) and not has_brake and not has_transport
			if on_carrier or on_catapult or waiting_for_catapult:
				(node as Node3D).global_transform = transform_delta * (node as Node3D).global_transform
				if waiting_for_catapult:
					var body := node as RigidBody3D
					PhysicsServer3D.body_set_state(
						body.get_rid(),
						PhysicsServer3D.BODY_STATE_TRANSFORM,
						body.global_transform
					)
					body.linear_velocity = Vector3.ZERO
					body.angular_velocity = Vector3.ZERO
	for joint in get_tree().get_nodes_in_group("carrier_pin_joint"):
		if is_instance_valid(joint) and joint is Node3D:
			(joint as Node3D).global_transform = transform_delta * (joint as Node3D).global_transform

func _is_helicopter_deck_passenger(node: Node) -> bool:
	if node == null:
		return false
	if bool(node.get_meta("is_helicopter", false)):
		return true
	var role: String = str(node.get_meta("aircraft_role", "")).to_lower()
	return role.find("helicopter") >= 0

func _is_node_in_helicopter_deck_carry_zone(node: Node3D) -> bool:
	if node == null:
		return false
	var local_pos: Vector3 = to_local(node.global_position)
	if absf(local_pos.x) > maxf(helicopter_deck_carry_half_width_m, 0.0):
		return false
	if absf(local_pos.z) > maxf(helicopter_deck_carry_half_length_m, 0.0):
		return false
	var deck_y: float = global_position.y
	var fdm := find_child("FlightDeckManager", true, false)
	if fdm != null and fdm.has_method("get_deck_height"):
		deck_y = float(fdm.call("get_deck_height"))
	return absf(node.global_position.y - deck_y) <= maxf(helicopter_deck_carry_height_margin_m, 0.0)

func _update_tread_visuals(delta: float, transform_before: Transform3D) -> void:
	_tread_steer = lerp(_tread_steer, _current_steer, delta * 1.5)
	var tread_detail_enabled := _should_enable_tread_detail_budget()
	_set_tread_detail_enabled(tread_detail_enabled)

	if not TerrainNavGrid.is_ready() and _get_precise_terrain_provider() == null:
		return

	var world_heights: Array[float] = []
	var old_forward := transform_before.basis.z
	old_forward.y = 0.0
	old_forward = old_forward.normalized() if old_forward.length_squared() > 0.0001 else Vector3.FORWARD
	var new_forward := global_transform.basis.z
	new_forward.y = 0.0
	new_forward = new_forward.normalized() if new_forward.length_squared() > 0.0001 else old_forward
	var origin_delta := global_position - transform_before.origin
	var forward_delta := origin_delta.dot(old_forward)
	var yaw_delta := old_forward.signed_angle_to(new_forward, Vector3.UP)
	var tread_world_positions: Array[Vector3] = []
	var tread_current_y: Array[float] = []
	var tread_yaws: Array[float] = []
	var tread_pitch_targets: Array[float] = []
	var tread_signed_speeds: Array[float] = []
	var tread_signed_travels: Array[float] = []

	var _tread_sample_profiler_start: int = FrameProfiler.begin("LandCarrier.tread_sample_terrain")
	for i in _tread_nodes.size():
		var xz: Vector2 = _tread_local_xz[i]
		var world_xz := to_global(Vector3(xz.x, 0.0, xz.y))

		var tread := _tread_nodes[i] as Node3D
		var steer_offset: float = 0.0
		if xz.y > 20.0:
			steer_offset = _tread_steer * MAX_TREAD_STEER
		elif xz.y < -20.0:
			steer_offset = -_tread_steer * MAX_TREAD_STEER * clampf(rear_axle_steer_ratio, 0.0, 1.5)
		var yaw_target: float = _tread_initial_rot_y[i] + steer_offset
		tread.rotation.y = yaw_target

		var tread_forward := tread.global_transform.basis.z
		tread_forward.y = 0.0
		tread_forward = tread_forward.normalized() if tread_forward.length_squared() > 0.0001 else new_forward
		var sample_half_length := maxf(tread_ground_sample_half_length_m, 0.1)
		var rear_sample := world_xz - tread_forward * sample_half_length
		var front_sample := world_xz + tread_forward * sample_half_length
		var rear_terrain_y := _sample_precise_terrain_y(rear_sample.x, rear_sample.z)
		var front_terrain_y := _sample_precise_terrain_y(front_sample.x, front_sample.z)
		var rear_target_y := rear_terrain_y + TREAD_GROUND_OFFSET
		var front_target_y := front_terrain_y + TREAD_GROUND_OFFSET
		var tread_target_y := (rear_target_y + front_target_y) * 0.5

		world_heights.append((rear_terrain_y + front_terrain_y) * 0.5)

		var pitch_target := atan2(front_target_y - rear_target_y, sample_half_length * 2.0) * tread_pitch_sign
		var signed_tread_travel := forward_delta - xz.x * yaw_delta
		var signed_tread_speed := signed_tread_travel / delta if delta > 0.0 else 0.0
		tread_world_positions.append(Vector3(world_xz.x, tread_target_y, world_xz.z))
		tread_current_y.append(tread.global_position.y)
		tread_yaws.append(yaw_target)
		tread_pitch_targets.append(pitch_target)
		tread_signed_speeds.append(signed_tread_speed)
		tread_signed_travels.append(signed_tread_travel)
	FrameProfiler.end("LandCarrier.tread_sample_terrain", _tread_sample_profiler_start)

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

	if not _should_apply_tread_node_update(tread_detail_enabled, delta):
		return

	var _tread_apply_profiler_start: int = FrameProfiler.begin("LandCarrier.tread_apply_nodes")
	for i in tread_world_positions.size():
		var tread := _tread_nodes[i] as Node3D
		var target_position := tread_world_positions[i]
		var smooth_y: float = lerp(tread_current_y[i], target_position.y, clampf(tread_ground_follow_response * delta, 0.0, 1.0))
		tread.global_position = Vector3(target_position.x, smooth_y, target_position.z)
		tread.rotation.y = tread_yaws[i]
		tread.rotation.x = lerp_angle(tread.rotation.x, tread_pitch_targets[i], clampf(tread_pitch_response * delta, 0.0, 1.0))
		if tread.has_method("update_scroll_speed"):
			tread.update_scroll_speed(delta, tread_signed_speeds[i])
		elif tread.has_method("update_from_carrier"):
			tread.update_from_carrier(delta, tread_signed_travels[i])
	FrameProfiler.end("LandCarrier.tread_apply_nodes", _tread_apply_profiler_start)


func _should_enable_tread_detail_budget() -> bool:
	if not tread_detail_budget_enabled:
		return true
	var camera := _get_active_camera()
	if camera == null or not is_instance_valid(camera):
		return true
	if _is_ancestor_of(self, camera):
		return true
	return global_position.distance_squared_to(camera.global_position) <= tread_detail_distance_m * tread_detail_distance_m


func _should_apply_tread_node_update(detail_enabled: bool, delta: float) -> bool:
	if detail_enabled:
		_tread_far_update_timer_s = 0.0
		return true
	_tread_far_update_timer_s -= maxf(delta, 0.0)
	if _tread_far_update_timer_s > 0.0:
		return false
	_tread_far_update_timer_s = maxf(tread_far_update_interval_s, 0.05)
	return true


func _set_tread_detail_enabled(enabled: bool) -> void:
	if _tread_detail_enabled == enabled:
		return
	_tread_detail_enabled = enabled
	for tread in _tread_nodes:
		if is_instance_valid(tread) and tread.has_method("set_visual_budget_enabled"):
			tread.call("set_visual_budget_enabled", enabled)


func get_visual_budget_report_stats() -> Dictionary:
	return {
		"tread_detail_budget_enabled": tread_detail_budget_enabled,
		"tread_detail_active": _tread_detail_enabled,
		"tread_detail_distance_m": tread_detail_distance_m,
		"tread_far_update_interval_s": tread_far_update_interval_s,
		"tread_count": _tread_nodes.size(),
	}


func _get_active_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_3d()


func _is_ancestor_of(root: Node, possible_child: Node) -> bool:
	var current := possible_child
	while current != null:
		if current == root:
			return true
		current = current.get_parent()
	return false


func _update_track_marks(delta: float, _transform_before: Transform3D) -> void:
	_update_track_mark_lifetimes(delta)
	_update_track_mark_debug_log(delta)
	var track_treads := _get_track_mark_treads()
	if track_treads.is_empty():
		_track_mark_tread_states.clear()
		return

	var active_tread_ids: Dictionary = {}
	for tread in track_treads:
		var tread_id := tread.get_instance_id()
		active_tread_ids[tread_id] = true
		_update_track_marks_for_tread(tread, delta, track_marks_enabled)
	for tread_id_variant in _track_mark_tread_states.keys():
		if not active_tread_ids.has(tread_id_variant):
			_track_mark_tread_states.erase(tread_id_variant)


func _update_track_marks_for_tread(tread: Node3D, delta: float, allow_spawn: bool) -> void:
	var tread_id := tread.get_instance_id()
	var current_transform := tread.global_transform
	if not _track_mark_tread_states.has(tread_id):
		_track_mark_tread_states[tread_id] = {
			"transform": current_transform,
			"distance_accum_m": 0.0,
		}
		return

	var state: Dictionary = _track_mark_tread_states[tread_id]
	var previous_transform_variant: Variant = state.get("transform", current_transform)
	var previous_transform: Transform3D = previous_transform_variant if previous_transform_variant is Transform3D else current_transform
	var distance_accum_m := maxf(float(state.get("distance_accum_m", 0.0)), 0.0)
	var travel := Vector2(
		current_transform.origin.x - previous_transform.origin.x,
		current_transform.origin.z - previous_transform.origin.z
	).length()
	var spacing := _get_track_mark_spacing_m()
	if not allow_spawn or delta <= 0.0 or travel / delta < maxf(track_mark_min_speed_mps, 0.0):
		state["transform"] = current_transform
		state["distance_accum_m"] = minf(distance_accum_m, spacing)
		_track_mark_tread_states[tread_id] = state
		return

	var distance_to_next_mark := maxf(spacing - distance_accum_m, 0.0)
	while distance_to_next_mark <= travel + 0.0001:
		var sample_fraction := clampf(distance_to_next_mark / maxf(travel, 0.0001), 0.0, 1.0)
		var sampled_tread_transform := previous_transform.interpolate_with(current_transform, sample_fraction)
		_spawn_track_mark_for_tread(sampled_tread_transform)
		distance_to_next_mark += spacing
	state["transform"] = current_transform
	state["distance_accum_m"] = fmod(distance_accum_m + travel, spacing)
	_track_mark_tread_states[tread_id] = state


func _update_track_mark_debug_log(delta: float) -> void:
	if _track_mark_debug_log_interval_s <= 0.0:
		return
	_track_mark_debug_log_timer_s -= delta
	if _track_mark_debug_log_timer_s > 0.0:
		return
	_track_mark_debug_log_timer_s = _track_mark_debug_log_interval_s
	print("[LandCarrierTrackMarks] active=%d max=%d enabled=%s" % [
		_track_mark_entries.size(),
		track_mark_max_active,
		str(track_marks_enabled),
	])


func _update_track_mark_lifetimes(delta: float) -> void:
	_track_mark_clock_s += maxf(delta, 0.0)
	if _track_mark_material != null:
		# One uniform update lets the GPU fade every instance smoothly. Rewriting
		# every MultiMesh color here would scale with the number of marks.
		_track_mark_material.set_shader_parameter(&"track_time_s", _track_mark_clock_s)
	for i in range(_track_mark_entries.size() - 1, -1, -1):
		var entry: Dictionary = _track_mark_entries[i]
		var age := float(entry.get("age", 0.0)) + delta
		entry["age"] = age
		_track_mark_entries[i] = entry

		var lifetime := maxf(float(entry.get("lifetime", track_mark_lifetime_s)), 0.01)
		if age >= lifetime:
			_release_track_mark_slot(int(entry.get("slot", -1)))
			_track_mark_entries.remove_at(i)
	if _track_mark_multimesh_dirty:
		_sync_track_mark_multimesh(true)


func _get_track_mark_treads() -> Array[Node3D]:
	var valid_treads: Array[Node3D] = []
	for tread_variant in _tread_nodes:
		var tread := tread_variant as Node3D
		if is_instance_valid(tread):
			valid_treads.append(tread)
	valid_treads.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.position.z < b.position.z
	)
	var selected: Array[Node3D] = []
	for i in mini(valid_treads.size(), 2):
		selected.append(valid_treads[i])
	return selected


func _spawn_track_mark_for_tread(tread_transform: Transform3D) -> void:
	var slot := _acquire_track_mark_slot()
	if slot < 0:
		return
	var forward := tread_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = global_transform.basis.z
		forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var right := Vector3.UP.cross(forward)
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT

	var tread_position := tread_transform.origin
	var terrain_y := _sample_precise_terrain_y(tread_position.x, tread_position.z)
	var ground_color := _get_track_mark_ground_color(Vector3(tread_position.x, terrain_y, tread_position.z))
	var mark_color := _get_track_mark_color_from_ground(ground_color)
	var basis := Basis(right, Vector3.UP, forward)
	var origin := Vector3(
		tread_position.x,
		terrain_y + maxf(track_mark_ground_offset_m, 0.0) + maxf(track_mark_thickness_m, 0.001) * 0.5,
		tread_position.z
	)
	var entry := {
		"transform": Transform3D(basis, origin),
		"age": 0.0,
		"lifetime": maxf(track_mark_lifetime_s, 0.01),
		"spawn_time": _track_mark_clock_s,
		"color": mark_color,
		"slot": slot,
	}
	_track_mark_entries.append(entry)
	_write_track_mark_slot(slot, entry)


func _acquire_track_mark_slot() -> int:
	if not _track_mark_free_slots.is_empty():
		return _track_mark_free_slots.pop_back()
	# Keep laying a continuous trail at the capacity limit by replacing the
	# oldest mark. The previous implementation stopped spawning until a timer
	# expired, leaving a visible gap behind the moving carrier.
	while not _track_mark_entries.is_empty():
		var oldest: Dictionary = _track_mark_entries.pop_front()
		var slot := int(oldest.get("slot", -1))
		if slot >= 0 and _track_mark_multimesh != null and slot < _track_mark_multimesh.instance_count:
			return slot
	return -1


func _release_track_mark_slot(slot: int) -> void:
	if _track_mark_multimesh == null or slot < 0 or slot >= _track_mark_multimesh.instance_count:
		return
	_hide_track_mark_slot(slot)
	if not _track_mark_free_slots.has(slot):
		_track_mark_free_slots.append(slot)


func _hide_track_mark_slot(slot: int) -> void:
	if _track_mark_multimesh == null or slot < 0 or slot >= _track_mark_multimesh.instance_count:
		return
	_track_mark_multimesh.set_instance_transform(slot, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	_track_mark_multimesh.set_instance_color(slot, Color(0.0, 0.0, 0.0, 0.0))
	_track_mark_multimesh.set_instance_custom_data(slot, Color(0.0, 0.01, 0.0, 0.0))


func _write_track_mark_slot(slot: int, entry: Dictionary, update_transform: bool = true, update_color: bool = true) -> void:
	if _track_mark_multimesh == null or slot < 0 or slot >= _track_mark_multimesh.instance_count:
		return
	if update_transform:
		var transform_variant: Variant = entry.get("transform", Transform3D.IDENTITY)
		var mark_transform: Transform3D = transform_variant if transform_variant is Transform3D else Transform3D.IDENTITY
		_track_mark_multimesh.set_instance_transform(slot, mark_transform)
	var spawn_time := maxf(float(entry.get("spawn_time", _track_mark_clock_s)), 0.0)
	var lifetime := maxf(float(entry.get("lifetime", track_mark_lifetime_s)), 0.01)
	_track_mark_multimesh.set_instance_custom_data(slot, Color(spawn_time, lifetime, 0.0, 0.0))
	if update_color:
		var mark_color_variant: Variant = entry.get("color", track_mark_fallback_color)
		var mark_color: Color = mark_color_variant if mark_color_variant is Color else track_mark_fallback_color
		_track_mark_multimesh.set_instance_color(slot, _limit_track_mark_luminance(mark_color))


func _ensure_track_mark_resources() -> void:
	if _track_mark_root == null or not is_instance_valid(_track_mark_root):
		var parent_node := get_parent()
		if parent_node == null:
			parent_node = get_tree().current_scene
		if parent_node == null:
			return
		_track_mark_root = MultiMeshInstance3D.new()
		_track_mark_root.name = "CarrierTrackMarks"
		_track_mark_root.top_level = true
		_track_mark_root.global_transform = Transform3D.IDENTITY
		_track_mark_root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent_node.add_child(_track_mark_root)

	var width := _get_track_mark_width_m()
	var length := _get_track_mark_length_m()
	var thickness := maxf(track_mark_thickness_m, 0.001)
	if _track_mark_mesh == null:
		_track_mark_mesh = BoxMesh.new()
	_track_mark_mesh.size = Vector3(width, thickness, length)

	if _track_mark_material == null:
		_track_mark_material = ShaderMaterial.new()
		_track_mark_material.shader = TRACK_MARK_FADE_SHADER
	_track_mark_material.set_shader_parameter(&"track_time_s", _track_mark_clock_s)
	_track_mark_root.material_override = _track_mark_material

	var capacity := maxi(track_mark_max_active, 0)
	if _track_mark_multimesh == null or _track_mark_multimesh.instance_count != capacity:
		_track_mark_multimesh = MultiMesh.new()
		_track_mark_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_track_mark_multimesh.use_colors = true
		_track_mark_multimesh.use_custom_data = true
		_track_mark_multimesh.mesh = _track_mark_mesh
		_track_mark_multimesh.instance_count = capacity
		_track_mark_multimesh.visible_instance_count = capacity
		_track_mark_free_slots.clear()
		for slot in capacity:
			_hide_track_mark_slot(slot)
			_track_mark_free_slots.append(slot)
		while _track_mark_entries.size() > capacity:
			_track_mark_entries.pop_front()
		for i in _track_mark_entries.size():
			var entry: Dictionary = _track_mark_entries[i]
			var slot: int = _track_mark_free_slots.pop_back()
			entry["slot"] = slot
			_track_mark_entries[i] = entry
			_write_track_mark_slot(slot, entry)
		_track_mark_root.multimesh = _track_mark_multimesh
		_track_mark_multimesh_dirty = false


func _sync_track_mark_multimesh(rebuild_transforms: bool = false, update_colors: bool = true) -> void:
	if not rebuild_transforms and not update_colors:
		return
	_ensure_track_mark_resources()
	if _track_mark_multimesh == null:
		return
	for i in _track_mark_entries.size():
		var entry: Dictionary = _track_mark_entries[i]
		var slot := int(entry.get("slot", -1))
		if slot < 0 or slot >= _track_mark_multimesh.instance_count:
			if _track_mark_free_slots.is_empty():
				continue
			slot = _track_mark_free_slots.pop_back()
			entry["slot"] = slot
			_track_mark_entries[i] = entry
		_write_track_mark_slot(slot, entry, rebuild_transforms, update_colors)
	_track_mark_multimesh_dirty = false


func _get_track_mark_ground_color(world_pos: Vector3) -> Color:
	var ground_color := track_mark_fallback_color
	var terrain := _get_precise_terrain_provider()
	if terrain != null and terrain.has_method("get_surface_color"):
		var color_variant: Variant = terrain.call("get_surface_color", world_pos)
		if color_variant is Color:
			ground_color = color_variant
	ground_color.a = 1.0
	return ground_color


func _get_track_mark_color_from_ground(ground_color: Color) -> Color:
	var darken := clampf(track_mark_darken_factor, 0.0, 1.0)
	return _limit_track_mark_luminance(Color(
		clampf(ground_color.r * darken, 0.0, 1.0),
		clampf(ground_color.g * darken, 0.0, 1.0),
		clampf(ground_color.b * darken, 0.0, 1.0),
		1.0
	))


func _limit_track_mark_luminance(color: Color) -> Color:
	var limited := color
	limited.a = 1.0
	var max_luma := maxf(track_mark_max_luminance, 0.0)
	if max_luma <= 0.0:
		return Color(0.0, 0.0, 0.0, 1.0)
	var luma := limited.get_luminance()
	if luma > max_luma and luma > 0.0001:
		var scale := max_luma / luma
		limited.r *= scale
		limited.g *= scale
		limited.b *= scale
	return limited


func _get_track_mark_spacing_m() -> float:
	if track_mark_spawn_spacing_m > 0.01:
		return track_mark_spawn_spacing_m
	for tread_variant in _tread_nodes:
		var tread := tread_variant as Node
		if is_instance_valid(tread) and tread.has_method("get_plate_spacing_m"):
			return maxf(float(tread.call("get_plate_spacing_m")), 0.05)
	return 3.0


func _get_track_mark_width_m() -> float:
	if track_mark_width_m > 0.01:
		return track_mark_width_m
	for tread_variant in _tread_nodes:
		var tread := tread_variant as Node
		if is_instance_valid(tread) and tread.has_method("get_plate_width_m"):
			return maxf(float(tread.call("get_plate_width_m")), 0.05)
	return 12.0


func _get_track_mark_length_m() -> float:
	if track_mark_length_m > 0.01:
		return track_mark_length_m
	for tread_variant in _tread_nodes:
		var tread := tread_variant as Node
		if is_instance_valid(tread) and tread.has_method("get_plate_length_m"):
			return maxf(float(tread.call("get_plate_length_m")), 0.05)
	return 2.8


func _sample_terrain_y(wx: float, wz: float) -> float:
	var h: float = TerrainNavGrid.sample_height(wx, wz)
	if h <= TerrainNavGrid.IMPASSABLE * 0.5:
		return global_position.y - BODY_RIDE_HEIGHT
	return h


func _sample_precise_terrain_y(wx: float, wz: float) -> float:
	_terrain_provider = _get_precise_terrain_provider()
	if _terrain_provider != null and _terrain_provider.has_method("get_height"):
		var height_variant: Variant = _terrain_provider.call("get_height", Vector3(wx, 0.0, wz))
		if height_variant is float:
			var terrain_h := float(height_variant)
			if not is_nan(terrain_h):
				return terrain_h
	return _sample_terrain_y(wx, wz)


func _get_precise_terrain_provider() -> Node:
	if _terrain_provider == null or not is_instance_valid(_terrain_provider):
		_terrain_provider = get_tree().get_first_node_in_group("terrain_provider")
	return _terrain_provider

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
	var safe_delta := maxf(delta, 0.0)
	_drive_command_elapsed_s += safe_delta
	_drive_command_timer_s -= safe_delta
	if not multi_rate_drive_commands_enabled or _drive_command_timer_s <= 0.0:
		var command_delta := _drive_command_elapsed_s
		_drive_command_elapsed_s = 0.0
		_drive_command_timer_s = maxf(drive_command_update_interval_s, 0.02) \
			* _drive_command_interval_scale
		var command_profiler_start: int = FrameProfiler.begin("LandCarrier.drive_command")
		_refresh_drive_command(maxf(command_delta, safe_delta))
		FrameProfiler.end("LandCarrier.drive_command", command_profiler_start)
	_apply_drive_motion(safe_delta, _drive_target_speed_mps, _drive_target_yaw_rate_rad_s)


func _refresh_drive_command(delta: float) -> void:
	if _waypoint_positions.is_empty() or _waypoint_index >= _waypoint_positions.size():
		if _default_cross_map_route_completed \
				or (not automatic_patrol_enabled and _raw_waypoints.is_empty()):
			_no_path_timer = 0.0
			_replan_attempts = 0
			_current_steer = move_toward(_current_steer, 0.0, steer_response * delta)
			_drive_target_speed_mps = 0.0
			_drive_target_yaw_rate_rad_s = 0.0
			return
		_no_path_timer += delta
		_drive_target_speed_mps = 0.0
		_drive_target_yaw_rate_rad_s = 0.0
		if use_waypoint_pathfinding and _no_path_timer > 4.0:
			_no_path_timer = 0.0
			_replan_attempts += 1
			if _replan_attempts >= 2:
				_replan_attempts = 0
				_pick_automatic_patrol_or_hold()
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
		_drive_target_speed_mps = 0.0
		_drive_target_yaw_rate_rad_s = 0.0
		return

	if wp_dist > _prev_wp_dist:
		_stuck_timer += delta
		if _stuck_timer > 10.0:
			_stuck_timer = 0.0
			_prev_wp_dist = INF
			_replan_attempts += 1
			if _replan_attempts >= 3:
				_replan_attempts = 0
				_pick_automatic_patrol_or_hold()
			else:
				# Replan full path from current position
				_compute_path_to_destination()
			_drive_target_speed_mps = 0.0
			_drive_target_yaw_rate_rad_s = 0.0
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
	var target_yaw_rate := _current_steer * effective_turn_speed

	var turn_speed_factor := clampf(1.0 - absf(_current_steer) * turn_speed_slowdown, 0.2, 1.0)
	var throttle: float = clamp((dot + 1.0) * 0.5, 0.0, 1.0) * turn_speed_factor
	if turn_angle_deg > turn_in_place_angle_deg:
		throttle = maxf(throttle, maxf(hard_turn_crawl_speed_mps, 0.0) / maxf(max_speed, 0.01))
	_drive_target_speed_mps = throttle * max_speed
	_drive_target_yaw_rate_rad_s = target_yaw_rate


func _apply_drive_motion(delta: float, target_speed_mps: float, target_yaw_rate_rad_s: float) -> void:
	if delta <= 0.0:
		return
	var constrained_motion := _apply_recovery_motion_constraint(target_speed_mps, target_yaw_rate_rad_s, delta)
	target_speed_mps = float(constrained_motion.get("speed", target_speed_mps))
	target_yaw_rate_rad_s = float(constrained_motion.get("yaw_rate", target_yaw_rate_rad_s))

	var speed_rate := acceleration if target_speed_mps > _current_planar_speed_mps else deceleration
	_current_planar_speed_mps = move_toward(
		_current_planar_speed_mps,
		target_speed_mps,
		maxf(speed_rate, 0.0) * delta
	)
	var target_axle_yaw_rate := _get_axle_steering_yaw_rate(_current_planar_speed_mps, target_yaw_rate_rad_s)
	var yaw_reversing: bool = _current_yaw_rate_rad_s * target_axle_yaw_rate < 0.0
	var yaw_braking: bool = yaw_reversing \
			or absf(target_axle_yaw_rate) < absf(_current_yaw_rate_rad_s)
	if yaw_reversing:
		# Shed the existing rotational momentum before accelerating the opposite
		# way; this avoids an instantaneous left-to-right yaw-rate sign change.
		_current_yaw_rate_rad_s = move_toward(
			_current_yaw_rate_rad_s,
			0.0,
			maxf(turn_deceleration, 0.0) * delta
		)
	else:
		var yaw_response: float = turn_deceleration if yaw_braking else turn_acceleration
		_current_yaw_rate_rad_s = move_toward(
			_current_yaw_rate_rad_s,
			target_axle_yaw_rate,
			maxf(yaw_response, 0.0) * delta
		)

	var yaw_delta := _current_yaw_rate_rad_s * delta
	if absf(yaw_delta) > 0.00001:
		rotate_y(yaw_delta)
	var forward: Vector3 = global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	global_position.x += forward.x * _current_planar_speed_mps * delta
	global_position.z += forward.z * _current_planar_speed_mps * delta
	_last_planar_speed_mps = _current_planar_speed_mps


func _get_axle_steering_yaw_rate(speed_mps: float, requested_yaw_rate_rad_s: float) -> float:
	var yaw_limit := absf(requested_yaw_rate_rad_s)
	if yaw_limit <= 0.00001 or absf(speed_mps) <= 0.001:
		return 0.0
	var steer_input := clampf(_current_steer, -1.0, 1.0)
	if absf(steer_input) <= steer_deadzone:
		return 0.0
	var half_wheelbase := maxf(steering_axle_half_wheelbase_m, 0.1)
	var wheelbase := half_wheelbase * 2.0
	var front_angle := steer_input * MAX_TREAD_STEER
	var rear_angle := -front_angle * clampf(rear_axle_steer_ratio, 0.0, 1.5)
	var curvature := (tan(front_angle) - tan(rear_angle)) / wheelbase
	var yaw_rate := speed_mps * curvature
	yaw_rate = clampf(yaw_rate, -yaw_limit, yaw_limit)
	if signf(yaw_rate) != 0.0 and signf(requested_yaw_rate_rad_s) != 0.0 and signf(yaw_rate) != signf(requested_yaw_rate_rad_s):
		return 0.0
	return yaw_rate


func _apply_recovery_motion_constraint(target_speed_mps: float, target_yaw_rate_rad_s: float, delta: float) -> Dictionary:
	_recovery_constraint_log_s = maxf(_recovery_constraint_log_s - delta, 0.0)
	var deck_manager := find_child("FlightDeckManager", true, false)
	if deck_manager == null or not deck_manager.has_method("is_carrier_recovery_constraint_active"):
		return {"speed": target_speed_mps, "yaw_rate": target_yaw_rate_rad_s}
	if not bool(deck_manager.call("is_carrier_recovery_constraint_active")):
		return {"speed": target_speed_mps, "yaw_rate": target_yaw_rate_rad_s}

	var speed_limit := maxf(recovery_constraint_default_speed_limit_mps, 0.0)
	if deck_manager.has_method("get_carrier_recovery_speed_limit_mps"):
		var configured_limit := float(deck_manager.call("get_carrier_recovery_speed_limit_mps"))
		if configured_limit < INF:
			speed_limit = maxf(configured_limit, 0.0)
	var constrained_speed := minf(target_speed_mps, speed_limit)
	# Zero the STEER input too, not just the yaw rate. is_turning_for_launch() checks _current_steer, so
	# leaving residual steer (still aimed at the patrol waypoint) makes the carrier read "turning" forever
	# even while stopped -> the launch never fires. Forcing steer to 0 settles it onto a straight heading.
	_current_steer = move_toward(_current_steer, 0.0, 4.0 * delta)
	# For a LAUNCH constraint, keep moving straight (a moving straight deck is a valid launch platform and
	# avoids a dead stop that can't change heading). For a recovery/landing constraint, keep the low cap.
	var launch_constraint: bool = deck_manager.has_method("is_launch_constraint_active") \
			and bool(deck_manager.call("is_launch_constraint_active"))
	if launch_constraint:
		constrained_speed = maxf(constrained_speed, maxf(launch_constraint_min_speed_mps, 0.0))
	if debug_motion_constraints and _recovery_constraint_log_s <= 0.0:
		_recovery_constraint_log_s = maxf(recovery_constraint_log_interval_s, 0.1)
		print("[LandCarrier] %s constraint: speed %.1f->%.1f steer->0 yaw->0" % [
			"launch" if launch_constraint else "recovery",
			target_speed_mps,
			constrained_speed,
		])
	return {
		"speed": constrained_speed,
		"yaw_rate": 0.0,
	}

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
	return _last_planar_speed_mps

func get_yaw_rate_rad_s() -> float:
	return _current_yaw_rate_rad_s

func is_turning_for_launch(max_yaw_rate_rad_s: float = 0.01, max_steer: float = 0.06) -> bool:
	return absf(_current_yaw_rate_rad_s) > maxf(max_yaw_rate_rad_s, 0.0) \
			or absf(_current_steer) > maxf(max_steer, 0.0)

func get_velocity_vector() -> Vector3:
	var forward: Vector3 = global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	return forward * _last_planar_speed_mps

func get_deck_reference_velocity_vector() -> Vector3:
	return get_velocity_vector()

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
