extends Node
class_name HelicopterPilot

enum State {
	IDLE,
	TAKEOFF,
	LOW_LEVEL_TRANSIT,
	HOVER,
	LANDING,
}

enum MissionPhase {
	OUTBOUND,    # heading to random LZ
	AT_LZ,       # on ground at LZ, dwell timer running
	INBOUND,     # returning to carrier
	AT_CARRIER,  # on carrier, dwell timer running
}

@export_group("References")
@export var helicopter_flight_path: NodePath
@export var control_engine_path: NodePath
@export var target_node_path: NodePath

@export_group("Mission")
@export var lz_distance_min_m: float = 4000.0
@export var lz_distance_max_m: float = 7000.0
@export var lz_candidate_attempts: int = 80
@export var lz_route_candidate_limit: int = 4
@export var lz_flat_radius_m: float = 18.0
@export var lz_max_center_drop_m: float = 1.5
@export var lz_max_height_variation_m: float = 2.5
@export var lz_obstacle_clear_radius_m: float = 22.0
@export var lz_obstacle_probe_height_m: float = 18.0
@export var lz_dwell_time_s: float = 12.0
@export var carrier_dwell_time_s: float = 20.0
@export var carrier_approach_radius_m: float = 80.0
@export var carrier_approach_point_name: String = "Helicopter Approach Point"
@export var carrier_landing_point_name: String = "Helicopter Landing Point"
@export var carrier_approach_gate_radius_m: float = 120.0
@export var carrier_final_speed_offset_mps: float = 5.0
@export var carrier_clear_distance_m: float = 120.0
@export var carrier_velocity_match_half_width_m: float = 90.0
@export var carrier_velocity_match_half_length_m: float = 170.0
@export var carrier_velocity_match_height_margin_m: float = 160.0
@export var carrier_velocity_match_landing_radius_m: float = 120.0
@export var carrier_landing_wire_number: int = 2
@export var carrier_landing_touchdown_radius_m: float = 3.0
@export var carrier_landing_hover_height_m: float = 10.0
@export var carrier_landing_final_leg_radius_m: float = 650.0
@export var carrier_landing_descent_start_radius_m: float = 3.0
@export var carrier_landing_position_speed_gain: float = 0.35
@export var carrier_landing_touchdown_relative_speed_mps: float = 1.0
@export var carrier_landing_touchdown_min_deck_agl_m: float = -0.25
@export var carrier_goal_repath_threshold_m: float = 150.0
@export var terrain_landing_approach_radius_m: float = 120.0
@export var terrain_landing_descent_radius_m: float = 35.0
@export var terrain_landing_touchdown_radius_m: float = 20.0
@export var landed_ground_planar_brake_mps2: float = 18.0
@export var landed_ground_angular_brake_radps2: float = 4.0
@export var landed_ground_snap_speed_mps: float = 0.12
@export var landed_ground_freeze_agl_m: float = 2.5
@export var landed_ground_freeze_speed_mps: float = 0.5
@export var terrain_landing_ground_contact_agl_m: float = 1.2
@export var terrain_landing_ground_contact_speed_mps: float = 2.0
@export var terrain_landing_ground_contact_compression_m: float = 0.025
@export var terrain_landing_ground_contact_min_wheels: int = 2

@export_group("Low-Level Navigation")
@export var cruise_agl_m: float = 55.0
@export var takeoff_agl_m: float = 35.0
@export var min_terrain_clearance_m: float = 24.0
@export var terrain_escape_margin_m: float = 12.0
@export var transit_speed_clearance_gain: float = 0.0
@export var transit_speed_clearance_max_agl_m: float = 140.0
@export var terrain_hazard_lookahead_time_s: float = 5.0
@export var terrain_hazard_min_lookahead_m: float = 220.0
@export var terrain_hazard_max_lookahead_m: float = 650.0
@export var terrain_hazard_vertical_margin_m: float = 45.0
@export var terrain_recovery_agl_m: float = 55.0
@export var terrain_recovery_full_agl_m: float = 25.0
@export var terrain_recovery_sink_mps: float = 8.0
@export var use_heightmap_pathfinding: bool = true
@export var heightmap_path_recompute_s: float = 60.0
@export var heightmap_path_advance_radius_m: float = 120.0
@export var heightmap_path_carrot_distance_m: float = 520.0
@export var heightmap_path_corner_blend_radius_m: float = 340.0
@export var heightmap_path_corner_blend_strength: float = 0.65
@export var heightmap_path_goal_move_recompute_m: float = 900.0
@export var destination_path_reset_threshold_m: float = 120.0
@export var heightmap_path_search_padding_m: float = 1600.0
@export var heightmap_path_max_terrain_above_reference_m: float = 270.0
@export var heightmap_path_max_flight_above_reference_m: float = 400.0
@export var heightmap_path_ground_level_band_m: float = 80.0
@export var heightmap_path_first_plateau_min_m: float = 85.0
@export var heightmap_path_first_plateau_max_m: float = 210.0
@export var heightmap_path_low_route_penalty: float = 0.22
@export var heightmap_path_top_level_penalty: float = 2.4
@export var heightmap_path_upper_level_penalty: float = 0.08
@export var heightmap_path_level_change_penalty: float = 35.0
@export var heightmap_path_mountain_avoidance_m: float = 270.0
@export var heightmap_path_max_step_climb_m: float = 0.0
@export var heightmap_path_mountain_buffer_cells: int = 2
@export var heightmap_path_max_edge_risk_m: float = 5.0
@export var heightmap_path_edge_risk_penalty: float = 900.0
@export var heightmap_path_altitude_penalty: float = 0.0
@export var heightmap_path_climb_penalty: float = 0.0
@export var heightmap_path_high_terrain_penalty: float = 0.0
@export var terrain_navgrid_path_slope_m: float = 12.0
@export var terrain_lookahead_m: float = 260.0
@export var terrain_sample_spacing_m: float = 45.0
@export var corridor_angle_deg: float = 35.0
@export var waypoint_accept_radius_m: float = 35.0
@export var replan_interval_s: float = 0.35

@export_group("Flight")
@export var cruise_speed_mps: float = 150.0
@export var max_speed_mps: float = 150.0
@export var hover_speed_mps: float = 4.0
@export var max_climb_mps: float = 7.0
@export var max_descent_mps: float = 4.0
@export var collective_trim: float = 0.58
@export var altitude_to_climb_gain: float = 0.22
@export var collective_climb_gain: float = 0.045
@export var collective_speed_lift_bias: float = 0.08
@export var collective_rate_up: float = 0.85
@export var collective_rate_down: float = 0.25
@export var collective_full_climb_alt_error_m: float = 35.0
@export var transit_collective_min: float = 1.0
@export var energy_management_min_collective: float = 0.35
@export var energy_management_speed_band_mps: float = 18.0
@export var energy_management_altitude_band_m: float = 35.0
@export var landing_flare_agl_m: float = 8.0
@export var landing_final_slowdown_agl_m: float = 5.0
@export var landing_final_descent_mps: float = 0.65
@export var landing_touchdown_descent_mps: float = 0.25
@export var landing_flare_collective_floor_margin: float = 0.02
@export var landing_descent_overspeed_collective_gain: float = 0.08
@export var landing_settle_collective_gain: float = 0.35
@export var landing_ground_effect_collective_bias: float = 0.22
@export var landing_final_horizontal_hold_radius_m: float = 14.0
@export var landing_final_horizontal_hold_agl_m: float = 18.0
@export var landing_final_position_gain: float = 0.006
@export var landing_final_velocity_gain: float = 0.22
@export var landing_final_accel_damping_gain: float = 0.012
@export var takeoff_collective_min: float = 0.82
@export var takeoff_deck_release_margin: float = 0.06
@export var deck_takeoff_climb_m: float = 85.0
@export var takeoff_vertical_hold_m: float = 8.0
@export var takeoff_transition_speed_mps: float = 24.0
@export var takeoff_clear_max_climb_mps: float = 3.5

@export_group("Controls")
@export var max_cyclic_input: float = 1.0
@export var max_yaw_input: float = 0.55
@export var cyclic_rate: float = 0.65
@export var transit_max_nose_up: float = 0.05
@export var transit_forward_lean_drop_rate: float = 0.08
@export var cyclic_speed_gain: float = 0.026
@export var cyclic_speed_d_gain: float = 0.010
@export var cyclic_lat_pos_gain: float = 0.0018
@export var cyclic_lat_vel_gain: float = 0.035
@export var cyclic_lat_d_gain: float = 0.008
@export var cyclic_altitude_trade_gain: float = 0.0035
@export var cyclic_sink_trade_gain: float = 0.035
@export var cyclic_altitude_rate_lookahead_s: float = 2.2
@export var cyclic_altitude_rate_gain: float = 0.12
@export var cyclic_vertical_accel_damping: float = 0.018
@export var cyclic_target_climb_from_alt_error_mps: float = 0.18
@export var cyclic_target_climb_mps: float = 5.0
@export var cyclic_target_sink_mps: float = 2.0
@export var cyclic_vertical_priority_rate_mps: float = 6.0
@export var takeoff_min_climb_until_clear_mps: float = 3.0
@export var cyclic_altitude_trade_min_speed_mps: float = 12.0
@export var cyclic_altitude_trade_full_speed_mps: float = 35.0
@export var altitude_guard_m: float = 5.0
@export var sink_guard_mps: float = 1.5
@export var coordinated_turn_gain: float = 0.08
@export var horizontal_guidance_deadzone_m: float = 12.0
@export var decel_distance_m: float = 600.0
@export var transit_speed_target_accel_mps2: float = 18.0
@export var transit_speed_target_decel_mps2: float = 18.0
@export var yaw_gain: float = 0.08
@export var yaw_rate_damping: float = 0.65
@export var yaw_command_rate: float = 0.30
@export var transit_coordinated_yaw_gain: float = 0.40
@export var transit_turn_roll_gain: float = 0.85
@export var transit_lateral_position_gain: float = 0.0012
@export var transit_lateral_velocity_gain: float = 0.020
@export var transit_lateral_max_demand_mps: float = 12.0
@export var transit_turn_yaw_gain: float = 0.05
@export var transit_low_speed_bank_start_mps: float = 10.0
@export var transit_low_speed_bank_full_mps: float = 42.0
@export var transit_low_speed_roll_scale: float = 0.08
@export var transit_low_speed_yaw_gain: float = 0.45
@export var transit_low_speed_yaw_input: float = 1.0
@export var transit_backward_roll_cut_start_mps: float = 0.5
@export var transit_backward_roll_cut_full_mps: float = 6.0
@export var transit_min_forward_lean: float = 0.16
@export var transit_reverse_recovery_start_mps: float = 0.2
@export var transit_reverse_recovery_full_mps: float = 5.0
@export var transit_reverse_recovery_lean: float = 0.70
@export var transit_reverse_altitude_pitch_blend: float = 0.35
@export var transit_sharp_turn_angle_deg: float = 35.0
@export var transit_sharp_turn_full_angle_deg: float = 105.0
@export var transit_sharp_turn_yaw_gain: float = 0.35
@export var transit_sharp_turn_yaw_input: float = 0.65
@export var transit_sharp_turn_roll_scale: float = 0.55
@export var transit_pedal_turn_speed_mps: float = 35.0
@export var transit_pedal_turn_angle_deg: float = 70.0
@export var transit_pedal_turn_yaw_gain: float = 0.70
@export var transit_pedal_turn_yaw_input: float = 0.85
@export var transit_pedal_turn_roll_scale: float = 0.12
@export var transit_high_speed_turn_start_mps: float = 55.0
@export var transit_high_speed_turn_full_mps: float = 95.0
@export var transit_high_speed_roll_scale: float = 0.42
@export var transit_high_speed_lateral_roll_scale: float = 0.25
@export var transit_high_speed_yaw_gain: float = 0.34
@export var transit_high_speed_yaw_input: float = 0.36
@export var transit_bank_pullback_gain: float = 0.26
@export var transit_bank_pullback_start_mps: float = 35.0
@export var transit_bank_pullback_full_mps: float = 90.0
@export var terrain_recovery_max_bank_scale: float = 0.30
@export var transit_cruise_forward_lean: float = 0.50
@export var transit_sharp_turn_lean_scale: float = 0.20
@export var lateral_obstacle_probe_dist_m: float = 120.0
@export var lateral_obstacle_probe_angle_deg: float = 30.0
@export var lateral_obstacle_margin_m: float = 30.0
@export var lateral_obstacle_roll_gain: float = 0.12
@export var lateral_obstacle_yaw_gain: float = 0.20

@export_group("Debug")
@export var debug_enabled: bool = true
@export var debug_interval_s: float = 1.0
@export var debug_log_as_error: bool = false
@export var debug_log_as_warning: bool = false
@export var debug_lifecycle_events: bool = true
@export var debug_overlay_enabled: bool = false
@export var debug_overlay_only_when_viewed: bool = false
@export var crash_log_enabled: bool = true
@export var crash_log_history_s: float = 15.0

var aircraft: RigidBody3D = null
var helicopter_flight: Node = null
var control_engine: Node = null
var control_gear: Node = null
var engine: Node = null
var target_node: Node3D = null
var state: State = State.IDLE
var mission_phase: MissionPhase = MissionPhase.AT_CARRIER

enum CarrierApproachPhase {
	NONE,
	TO_APPROACH_POINT,   # flying to the carrier-relative approach gate
	FINAL,               # flying forward at carrier speed + offset, holding altitude
	DESCEND,             # over landing point, matching speed, descending
}

var destination: Vector3 = Vector3.ZERO
var _has_destination: bool = false
var _nav_waypoint: Vector3 = Vector3.ZERO
var _desired_altitude_m: float = 0.0
var _carrier_approach_phase: CarrierApproachPhase = CarrierApproachPhase.NONE
var _pitch_cmd: float = 0.0
var _roll_cmd: float = 0.0
var _yaw_cmd: float = 0.0
var _replan_timer_s: float = 0.0
var _debug_timer_s: float = 0.0
var _idle_dwell_timer_s: float = 0.0
var _landing_on_carrier: bool = false
var _takeoff_start_altitude_m: float = NAN
var _takeoff_started_from_deck: bool = false
var _prev_fwd_speed: float = 0.0
var _prev_lat_speed: float = 0.0
var _prev_vertical_speed: float = 0.0
var _prev_forward_lean: float = 0.0
var _collective_cmd: float = 0.0
var _physics_delta: float = 0.016
var _speed_target_mps: float = 0.0
var _debug_target_vertical_rate_mps: float = 0.0
var _debug_vertical_rate_error_mps: float = 0.0
var _debug_forward_error_mps: float = 0.0
var _debug_lateral_error_mps: float = 0.0
var _debug_speed_pitch: float = 0.0
var _debug_altitude_pitch: float = 0.0
var _debug_turn_roll: float = 0.0
var _debug_sharp_turn: float = 0.0
var _debug_pedal_turn: float = 0.0
var _debug_low_speed_turn: float = 0.0
var _debug_high_speed_turn: float = 0.0
var _debug_backward_turn: float = 0.0
var _debug_bank_pullback: float = 0.0
var _debug_target_yaw: float = 0.0
var _debug_terrain_recovery: float = 0.0
var _debug_vertical_priority: float = 0.0
var _debug_collective_target: float = 0.0
var _heightmap_path: Array[Vector3] = []
var _heightmap_path_index: int = 0
var _heightmap_path_goal: Vector3 = Vector3(INF, INF, INF)
var _heightmap_path_timer_s: float = 0.0
var _transit_cruise_altitude_m: float = NAN
var _last_path_source: String = "none"
var _debug_canvas: CanvasLayer = null
var _debug_label: Label = null
var _last_debug_line: String = ""

# Flight recorder: ring buffer of (timestamp_s, line) pairs + milestone log
var _flight_log: Array = []       # [[time_s, line], ...]
var _milestone_log: Array = []    # ["2.3s  Landed at LZ", ...]
var _flight_start_time_s: float = 0.0


func _ready() -> void:
	add_to_group("origin_shifter")
	set_physics_process(false)
	_debug_event("loaded", "parent=%s" % [get_parent().name if get_parent() else "?"])
	if debug_enabled:
		print("[HelicopterPilot] %s loaded on %s — waiting for initialize(). If you never see a second line, AI was never enabled." \
			% [name, get_parent().name if get_parent() else "?"])


func apply_origin_shift(offset: Vector3) -> void:
	destination -= offset
	_nav_waypoint -= offset
	for i in range(_heightmap_path.size()):
		_heightmap_path[i] -= offset
	_heightmap_path_goal -= offset
	if not is_nan(_transit_cruise_altitude_m):
		_transit_cruise_altitude_m -= offset.y
	if not is_nan(_takeoff_start_altitude_m):
		_takeoff_start_altitude_m -= offset.y


func initialize(aircraft_node: RigidBody3D) -> void:
	aircraft = aircraft_node
	if not is_instance_valid(aircraft):
		push_error("[HelicopterPilot] Parent aircraft is not valid.")
		return

	_find_modules()
	if helicopter_flight == null or control_engine == null:
		push_error("[HelicopterPilot] Missing HelicopterFlight or ControlEngine module.")
		set_physics_process(false)
		return

	if debug_enabled:
		print("[HelicopterPilot] %s initialized — flight=%s engine=%s" \
			% [aircraft.name, str(helicopter_flight != null), str(control_engine != null)])

	_apply_ai_groups()
	_replan_timer_s = 0.0
	_debug_timer_s = 0.0
	_idle_dwell_timer_s = 0.0
	_flight_log.clear()
	_milestone_log.clear()
	_flight_start_time_s = Time.get_ticks_msec() / 1000.0
	if crash_log_enabled and aircraft.has_signal("destroyed") \
			and not aircraft.is_connected("destroyed", _on_aircraft_destroyed_flight_recorder):
		aircraft.connect("destroyed", _on_aircraft_destroyed_flight_recorder)

	_pick_random_lz()
	mission_phase = MissionPhase.OUTBOUND

	var ground_height: float = _get_ground_height_at_position(aircraft.global_position)
	var agl: float = aircraft.global_position.y - ground_height if not is_nan(ground_height) else aircraft.global_position.y
	if bool(aircraft.get_meta("parking_brake", false)) or agl < takeoff_agl_m:
		change_state(State.TAKEOFF)
	else:
		change_state(State.LOW_LEVEL_TRANSIT)
	_debug_event("init", "flight=%s engine=%s agl=%.1f ground=%.1f" % [
		str(helicopter_flight != null),
		str(control_engine != null),
		agl,
		ground_height,
	])
	set_physics_process(true)


func deinitialize() -> void:
	_set_helicopter_input(0.0, 0.0, 0.0)
	_apply_collective(0.0)
	_pitch_cmd = 0.0
	_roll_cmd = 0.0
	_yaw_cmd = 0.0
	_landing_on_carrier = false
	_takeoff_start_altitude_m = NAN
	_takeoff_started_from_deck = false
	_prev_fwd_speed = 0.0
	_prev_lat_speed = 0.0
	_prev_vertical_speed = 0.0
	_collective_cmd = 0.0
	set_physics_process(false)


func change_state(new_state: State) -> void:
	if state == new_state:
		return
	if new_state == State.TAKEOFF:
		_prime_takeoff_reference()
		if not _is_deck_takeoff_context() and is_instance_valid(aircraft):
			if aircraft.has_meta("parking_brake"):
				aircraft.remove_meta("parking_brake")
			aircraft.freeze = false
			aircraft.sleeping = false
	# As soon as we leave the deck and enter normal flight, drop the carrier velocity reference.
	# HelicopterFlight clears helicopter_deck_takeoff_ready on brake release but never calls
	# VelocityFrame.clear_reference, so the motion_reference_node persists and causes sliding.
	if state == State.TAKEOFF and new_state == State.LOW_LEVEL_TRANSIT:
		if is_instance_valid(aircraft):
			var control_vel: Vector3 = _get_control_velocity()
			_speed_target_mps = Vector2(control_vel.x, control_vel.z).length()
			VelocityFrame.clear_reference(aircraft)
			if aircraft.has_meta("helicopter_deck_reference_node"):
				aircraft.remove_meta("helicopter_deck_reference_node")
		_set_landing_gear_deployed(false)
		_transit_cruise_altitude_m = NAN
	elif new_state == State.LANDING:
		_set_landing_gear_deployed(true)
	var previous_state := state
	state = new_state
	_debug_event("state", "from=%s to=%s" % [_state_name_for(previous_state), _state_name()])


func set_destination(world_position: Vector3) -> void:
	var previous_destination := destination
	var had_destination := _has_destination
	destination = world_position
	_has_destination = true
	if not had_destination or _flat_distance(previous_destination, world_position) > maxf(destination_path_reset_threshold_m, 0.0):
		_clear_heightmap_path("set_destination")
	if state == State.IDLE or state == State.HOVER:
		change_state(State.LOW_LEVEL_TRANSIT)


func command_hover(world_position: Variant = null) -> void:
	if world_position is Vector3:
		destination = world_position as Vector3
		_has_destination = true
	elif is_instance_valid(aircraft):
		destination = aircraft.global_position
		_has_destination = true
	change_state(State.HOVER)


func command_land(world_position: Variant = null) -> void:
	if world_position is Vector3:
		destination = world_position as Vector3
		_has_destination = true
	elif is_instance_valid(aircraft):
		destination = aircraft.global_position
		_has_destination = true
	_landing_on_carrier = false
	change_state(State.LANDING)


func launch() -> void:
	change_state(State.TAKEOFF)


func command_return_to_carrier_and_land() -> bool:
	if not is_instance_valid(aircraft):
		return false
	var carrier: Node = get_tree().get_first_node_in_group("carrier")
	if not (carrier is Node3D):
		_debug_event("manual_return_failed", "reason=no_carrier")
		return false
	if bool(aircraft.get_meta("carrier_transport_mode", false)):
		_debug_event("manual_return_ignored", "reason=already_on_carrier")
		return true

	_clear_heightmap_path("manual_return")
	mission_phase = MissionPhase.INBOUND
	_landing_on_carrier = false
	_carrier_approach_phase = CarrierApproachPhase.NONE
	_transit_cruise_altitude_m = NAN
	_idle_dwell_timer_s = 0.0
	_update_carrier_destination()
	if not _has_destination:
		_debug_event("manual_return_failed", "reason=no_destination")
		return false

	if state == State.IDLE:
		_clear_ground_landing_hold()
		change_state(State.TAKEOFF)
	elif state == State.TAKEOFF:
		pass
	else:
		change_state(State.LOW_LEVEL_TRANSIT)
	set_physics_process(true)
	_debug_event("manual_return", "dest=%s" % [str(destination.snapped(Vector3.ONE * 0.1))])
	return true


func get_active_waypoints() -> Array[Vector3]:
	var route: Array[Vector3] = []
	if not _heightmap_path.is_empty():
		var start_index: int = clampi(_heightmap_path_index, 0, _heightmap_path.size() - 1)
		for i in range(start_index, _heightmap_path.size()):
			var point := _heightmap_path[i]
			if route.is_empty() or _flat_distance(route[route.size() - 1], point) > 1.0:
				route.append(point)
	elif is_instance_valid(aircraft) and _nav_waypoint != Vector3.ZERO:
		if _flat_distance(aircraft.global_position, _nav_waypoint) > maxf(horizontal_guidance_deadzone_m, 1.0):
			route.append(_nav_waypoint)
	if _has_destination:
		if route.is_empty() or _flat_distance(route[route.size() - 1], destination) > 1.0:
			route.append(destination)
	return route


func _physics_process(delta: float) -> void:
	if not is_instance_valid(aircraft):
		set_physics_process(false)
		return
	if aircraft.get_meta("controls_disabled", false):
		return
	_physics_delta = delta

	if _is_deck_takeoff_context() and state != State.TAKEOFF:
		change_state(State.TAKEOFF)
	elif state == State.TAKEOFF:
		_refresh_takeoff_deck_context()

	# Hard altitude floor near the carrier. If within 400 m and not actively
	# landing or taking off, force desired altitude to at least carrier + 70 m.
	if state == State.LOW_LEVEL_TRANSIT or state == State.HOVER:
		var _carrier_floor := get_tree().get_first_node_in_group("carrier") as Node3D
		if _carrier_floor != null and _flat_distance(aircraft.global_position, _carrier_floor.global_position) < 400.0:
			var _floor_y := _get_carrier_deck_y(_carrier_floor) + 70.0
			if aircraft.global_position.y < _floor_y:
				_desired_altitude_m = maxf(_desired_altitude_m, _floor_y)
				_transit_cruise_altitude_m = maxf(_transit_cruise_altitude_m if not is_nan(_transit_cruise_altitude_m) else 0.0, _floor_y)

	_replan_timer_s -= delta
	if _replan_timer_s <= 0.0:
		_replan_timer_s = maxf(replan_interval_s, 0.05)
		_update_navigation_plan()

	match state:
		State.IDLE:
			_collective_cmd = 0.0
			_apply_collective(0.0)
			_set_helicopter_input(0.0, 0.0, 0.0)
			if mission_phase == MissionPhase.AT_LZ:
				_hold_landed_on_terrain(delta)
				# Carrier is a CharacterBody3D using move_and_slide — if it drives into us it
				# physically pushes the RigidBody3D at carrier velocity. Cut dwell and take off.
				var lz_carrier := get_tree().get_first_node_in_group("carrier")
				if lz_carrier is Node3D:
					var carrier_dist := _flat_distance(aircraft.global_position, (lz_carrier as Node3D).global_position)
					if carrier_dist < carrier_clear_distance_m:
						_idle_dwell_timer_s = 0.0
			elif mission_phase == MissionPhase.AT_CARRIER:
				_hold_landed_on_carrier()
			_idle_dwell_timer_s -= delta
			if _idle_dwell_timer_s <= 0.0:
				_advance_mission()
		State.TAKEOFF:
			if _should_hold_vertical_takeoff():
				_nav_waypoint = Vector3(aircraft.global_position.x, _desired_altitude_m, aircraft.global_position.z)
			_fly_toward(_nav_waypoint, _get_takeoff_speed_limit(), delta)
			if _takeoff_is_clear():
				change_state(State.LOW_LEVEL_TRANSIT)
		State.LOW_LEVEL_TRANSIT:
			_fly_toward(_nav_waypoint, cruise_speed_mps, delta)
			if mission_phase == MissionPhase.INBOUND:
				# For carrier landing, only enter LANDING once through the approach gate.
				# The gate is the approach marker position — stay in transit until then
				# so the helicopter decelerates naturally rather than slamming the hover brake.
				var approach_world := _get_carrier_marker_world_pos(carrier_approach_point_name)
				var gate_dist := _flat_distance(aircraft.global_position, approach_world) if approach_world != Vector3.INF \
					else _flat_distance(aircraft.global_position, destination)
				if gate_dist <= maxf(carrier_approach_gate_radius_m, 5.0):
					_landing_on_carrier = true
					change_state(State.LANDING)
			else:
				var _land_r: float = maxf(terrain_landing_approach_radius_m, waypoint_accept_radius_m)
				if _has_destination and _flat_distance(aircraft.global_position, destination) <= _land_r:
					_landing_on_carrier = false
					change_state(State.LANDING)
		State.HOVER:
			_fly_toward(destination if _has_destination else aircraft.global_position, hover_speed_mps, delta)
		State.LANDING:
			if _landing_on_carrier:
				_run_scripted_carrier_approach(delta)
			else:
				_update_navigation_plan()
				var landing_fly_target := destination if _has_destination else aircraft.global_position
				landing_fly_target = Vector3(landing_fly_target.x, _desired_altitude_m, landing_fly_target.z)
				_fly_toward(landing_fly_target, hover_speed_mps, delta)
			_try_finish_landing()

	_emit_debug(delta)


func _advance_mission() -> void:
	match mission_phase:
		MissionPhase.AT_LZ:
			_record_milestone("Departed LZ — heading back to carrier")
			_clear_ground_landing_hold()
			_clear_heightmap_path("inbound_start")
			mission_phase = MissionPhase.INBOUND
			_carrier_approach_phase = CarrierApproachPhase.NONE
			_update_carrier_destination()
			change_state(State.TAKEOFF)
		MissionPhase.AT_CARRIER:
			_record_milestone("Landed back at carrier — picking new LZ")
			_clear_carrier_landing_hold()
			_pick_random_lz()
			mission_phase = MissionPhase.OUTBOUND
			change_state(State.TAKEOFF)


func _clear_ground_landing_hold() -> void:
	if not is_instance_valid(aircraft):
		return
	VelocityFrame.clear_reference(aircraft)
	for meta_name: String in ["helicopter_deck_takeoff_ready", "helicopter_deck_reference_node", "carrier_transport_mode"]:
		if aircraft.has_meta(meta_name):
			aircraft.remove_meta(meta_name)
	if aircraft.has_meta("parking_brake"):
		aircraft.remove_meta("parking_brake")
	aircraft.freeze = false
	aircraft.sleeping = false
	_pitch_cmd = 0.0
	_roll_cmd = 0.0
	_yaw_cmd = 0.0
	_prev_fwd_speed = 0.0
	_prev_lat_speed = 0.0
	_prev_vertical_speed = 0.0
	_debug_event("ground_hold_clear", "reason=lz_departure")


func _clear_carrier_landing_hold() -> void:
	if not is_instance_valid(aircraft):
		return
	if aircraft.has_meta("carrier_transport_mode"):
		aircraft.remove_meta("carrier_transport_mode")
	if aircraft.has_meta("parking_brake"):
		aircraft.remove_meta("parking_brake")
	aircraft.freeze = false
	aircraft.sleeping = false
	_zero_flight_controls_now()
	var carrier := get_tree().get_first_node_in_group("carrier")
	if carrier is Node3D:
		aircraft.set_meta("helicopter_deck_reference_node", carrier)
		aircraft.set_meta("helicopter_deck_takeoff_ready", true)
		VelocityFrame.set_reference_node(aircraft, carrier as Node3D)
	_debug_event("carrier_hold_clear", "reason=carrier_departure")


func _clear_heightmap_path(reason: String = "unspecified") -> void:
	if not _heightmap_path.is_empty():
		_debug_event("path_clear", "reason=%s points=%d index=%d goal=%s" % [
			reason,
			_heightmap_path.size(),
			_heightmap_path_index,
			str(_heightmap_path_goal.snapped(Vector3.ONE * 0.1)),
		])
	_heightmap_path.clear()
	_heightmap_path_index = 0
	_heightmap_path_goal = Vector3(INF, INF, INF)
	_heightmap_path_timer_s = 0.0
	_transit_cruise_altitude_m = NAN


func _pick_random_lz() -> void:
	var start_ms := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var current_pos := aircraft.global_position if is_instance_valid(aircraft) else Vector3.ZERO
	if use_heightmap_pathfinding and _terrain_pathfinding_ready():
		var nav_grid := get_node_or_null("/root/TerrainNavGrid")
		if nav_grid != null and nav_grid.has_method("get_random_passable_position"):
			var candidates: Array = []
			for _i in range(maxi(lz_candidate_attempts, 1)):
				var candidate_variant: Variant = nav_grid.call("get_random_passable_position", rng, 15.0)
				if not (candidate_variant is Vector3):
					continue
				var candidate := candidate_variant as Vector3
				var dist := _flat_distance(current_pos, candidate)
				if dist < lz_distance_min_m or dist > lz_distance_max_m:
					continue
				var score := _score_lz_candidate(candidate, current_pos)
				if is_inf(score):
					continue
				candidates.append([score, candidate])
			candidates.sort_custom(func(a, b): return a[0] < b[0])
			var route_checks := mini(candidates.size(), maxi(lz_route_candidate_limit, 0))
			for i in range(route_checks):
				var candidate: Vector3 = candidates[i][1]
				if not _find_aerial_heightmap_path(current_pos, candidate).is_empty():
					_set_lz_destination(candidate, "scored", float(candidates[i][0]))
					_debug_event("lz_pick_time", "ms=%d candidates=%d route_checks=%d" % [
						Time.get_ticks_msec() - start_ms,
						candidates.size(),
						i + 1,
					])
					return
			if not candidates.is_empty():
				# Prefer a verified flat/clear LZ over a blind fallback even if the
				# coarse aerial path search cannot prove the route immediately.
				_set_lz_destination(candidates[0][1], "scored_unrouted", float(candidates[0][0]))
				_debug_event("lz_pick_time", "ms=%d candidates=%d route_checks=%d" % [
					Time.get_ticks_msec() - start_ms,
					candidates.size(),
					route_checks,
				])
				return
	var angle: float = rng.randf_range(-PI, PI)
	var dist: float = rng.randf_range(lz_distance_min_m, lz_distance_max_m)
	var fallback := current_pos + Vector3(sin(angle), 0.0, cos(angle)) * dist
	var fallback_ground := _get_ground_height_at_position(fallback)
	if not is_nan(fallback_ground):
		fallback.y = fallback_ground
	destination = fallback
	_has_destination = true
	_clear_heightmap_path("fallback_lz")
	_debug_event("lz_pick_time", "ms=%d candidates=0 route_checks=0" % [Time.get_ticks_msec() - start_ms])


func _set_lz_destination(candidate: Vector3, method: String, score: float = NAN) -> void:
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")
	if nav_grid != null:
		var ground_h := _sample_lz_ground_height(candidate, nav_grid)
		if ground_h > _terrain_impassable_threshold(nav_grid):
			candidate.y = ground_h
	destination = candidate
	_has_destination = true
	_clear_heightmap_path("lz_pick")
	_debug_event("lz_pick", "method=%s score=%.2f dest=%s" % [
		method,
		score,
		str(destination.snapped(Vector3.ONE * 0.1)),
	])


func _score_lz_candidate(candidate: Vector3, current_pos: Vector3) -> float:
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")
	if nav_grid == null:
		return INF

	var ground_h := _sample_lz_ground_height(candidate, nav_grid)
	if ground_h <= _terrain_impassable_threshold(nav_grid):
		return INF
	if ground_h > _get_heightmap_reference_ground_y() + maxf(heightmap_path_max_terrain_above_reference_m, 0.0):
		return INF
	candidate.y = ground_h

	if nav_grid.has_method("is_stable_footprint"):
		var stable := bool(nav_grid.call(
			"is_stable_footprint",
			candidate.x,
			candidate.z,
			maxf(lz_flat_radius_m, 1.0),
			maxf(lz_max_center_drop_m, 0.0),
			maxf(lz_max_height_variation_m, 0.0)
		))
		if not stable:
			return INF

	var edge_risk := 0.0
	if nav_grid.has_method("sample_query_edge_risk"):
		edge_risk = float(nav_grid.call("sample_query_edge_risk", candidate.x, candidate.z))
		if edge_risk >= INF or edge_risk > maxf(lz_max_height_variation_m, 0.0):
			return INF

	if _lz_has_nearby_obstacles(candidate):
		return INF

	var dist := _flat_distance(current_pos, candidate)
	var mid_dist := (maxf(lz_distance_min_m, 0.0) + maxf(lz_distance_max_m, lz_distance_min_m)) * 0.5
	var distance_bias := absf(dist - mid_dist) * 0.01
	return edge_risk * 8.0 + distance_bias


func _sample_lz_ground_height(candidate: Vector3, nav_grid: Node) -> float:
	if nav_grid.has_method("sample_query_height"):
		var query_h := float(nav_grid.call("sample_query_height", candidate.x, candidate.z))
		if query_h > _terrain_impassable_threshold(nav_grid):
			return query_h
	if nav_grid.has_method("sample_height"):
		return float(nav_grid.call("sample_height", candidate.x, candidate.z))
	return candidate.y


func _terrain_impassable_threshold(nav_grid: Node) -> float:
	var impassable := -1000000.0
	if nav_grid != null:
		impassable = float(nav_grid.get("IMPASSABLE"))
	return impassable * 0.5


func _lz_has_nearby_obstacles(candidate: Vector3) -> bool:
	if not is_instance_valid(aircraft):
		return false
	var world := aircraft.get_world_3d()
	if world == null:
		return false
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(lz_obstacle_clear_radius_m, 1.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(
		Basis(),
		candidate + Vector3.UP * maxf(lz_obstacle_probe_height_m, 1.0) * 0.5
	)
	query.collision_mask = 0xFFFFFFFF
	query.exclude = [aircraft.get_rid()]
	var hits := world.direct_space_state.intersect_shape(query, 16)
	for hit in hits:
		var collider = hit.get("collider")
		if not (collider is Node):
			continue
		var node := collider as Node
		if _is_lz_ignored_collider(node):
			continue
		return true
	return false


func _is_lz_ignored_collider(node: Node) -> bool:
	if node.is_in_group("terrain") or node.is_in_group("ground"):
		return true
	var lower_name := node.name.to_lower()
	return lower_name.find("terrain") != -1 or lower_name.find("ground") != -1


func _update_carrier_destination() -> void:
	var carrier := get_tree().get_first_node_in_group("carrier")
	if carrier is Node3D:
		var carrier_node := carrier as Node3D
		if mission_phase == MissionPhase.INBOUND or _landing_on_carrier:
			# During scripted approach, aim transit at the approach gate so the
			# heightmap path leads to the right place. Once in LANDING the
			# scripted approach handler overrides destination each frame.
			var approach_pos := _get_carrier_marker_world_pos(carrier_approach_point_name)
			if approach_pos != Vector3.INF and not _landing_on_carrier:
				destination = approach_pos
			else:
				destination = _get_carrier_landing_point(carrier_node)
		else:
			destination = carrier_node.global_position
		_has_destination = true


func _get_carrier_landing_point(carrier: Node3D) -> Vector3:
	var fallback := carrier.global_position
	var deck_y := _get_carrier_deck_y(carrier)

	var aim_wire := _find_carrier_arresting_wire(maxi(carrier_landing_wire_number, 1))
	if is_instance_valid(aim_wire):
		var point := aim_wire.global_position
		point.y = deck_y
		return point

	var deck_start := carrier.find_child("DeckCenterStart", true, false) as Node3D
	if is_instance_valid(deck_start):
		var point := deck_start.global_position
		point.y = deck_y
		return point

	fallback.y = deck_y
	return fallback


func _find_carrier_arresting_wire(wire_number: int) -> Node3D:
	var named_fallback: Node3D = null
	for node in get_tree().get_nodes_in_group("arresting_cable"):
		if not (node is Node3D):
			continue
		var cable := node as Node3D
		if node.has_method("get_wire_number") and int(node.call("get_wire_number")) == wire_number:
			return cable
		if not is_instance_valid(named_fallback) and cable.name.to_lower().find(str(wire_number)) != -1:
			named_fallback = cable
	return named_fallback


func _find_modules() -> void:
	if helicopter_flight_path != NodePath():
		helicopter_flight = get_node_or_null(helicopter_flight_path)
	if helicopter_flight == null:
		helicopter_flight = _find_module_by_name("HelicopterFlight")
	if helicopter_flight == null:
		helicopter_flight = aircraft.find_child("HelicopterFlight", true, false)

	if control_engine_path != NodePath():
		control_engine = get_node_or_null(control_engine_path)
	if control_engine == null:
		control_engine = _find_module_by_name("ControlEngine")
	if control_engine == null:
		control_engine = aircraft.find_child("ControlEngine", true, false)

	control_gear = aircraft.get_node_or_null("ControlLandingGear")
	if control_gear == null:
		control_gear = _find_module_by_name("ControlLandingGear")
	if control_gear == null:
		control_gear = aircraft.find_child("ControlLandingGear", true, false)

	engine = _find_module_by_name("Engine")
	if engine == null:
		engine = aircraft.find_child("Engine", true, false)

	if target_node_path != NodePath():
		target_node = get_node_or_null(target_node_path) as Node3D


func _find_module_by_name(module_name: String) -> Node:
	if not is_instance_valid(aircraft):
		return null
	if aircraft.has_method("find_modules_by_type"):
		var modules_variant: Variant = aircraft.call("find_modules_by_type", module_name)
		if not (modules_variant is Array):
			modules_variant = []
		var modules: Array = modules_variant as Array
		if not modules.is_empty():
			return modules[0] as Node
	return _find_node_by_script_name(aircraft, module_name)


func _find_node_by_script_name(root: Node, script_name: String) -> Node:
	for child in root.get_children():
		var script_obj: Script = child.get_script()
		if script_obj != null and script_obj.resource_path.ends_with(script_name + ".gd"):
			return child
		var result: Node = _find_node_by_script_name(child, script_name)
		if result != null:
			return result
	return null


func _apply_ai_groups() -> void:
	if not is_instance_valid(aircraft):
		return
	if not aircraft.is_in_group("aircraft"):
		aircraft.add_to_group("aircraft")
	if not aircraft.is_in_group("ai_aircraft"):
		aircraft.add_to_group("ai_aircraft")

	var my_team: int = aircraft.get_team() if aircraft.has_method("get_team") else 1
	if my_team == 1:
		if not aircraft.is_in_group("friendlies"):
			aircraft.add_to_group("friendlies")
		if aircraft.is_in_group("enemies"):
			aircraft.remove_from_group("enemies")
	else:
		if not aircraft.is_in_group("enemies"):
			aircraft.add_to_group("enemies")
		if aircraft.is_in_group("friendlies"):
			aircraft.remove_from_group("friendlies")


func _update_navigation_plan() -> void:
	# Keep tracking the moving carrier while inbound
	if mission_phase == MissionPhase.INBOUND:
		_update_carrier_destination()

	if not _has_destination:
		_pick_random_lz()

	var current_pos: Vector3 = aircraft.global_position
	var goal: Vector3 = destination if _has_destination else current_pos
	if state == State.TAKEOFF:
		goal = current_pos

	var ground_height: float = _get_ground_height_at_position(current_pos)
	var base_ground: float = ground_height if not is_nan(ground_height) else current_pos.y - cruise_agl_m
	var requested_agl: float = cruise_agl_m
	if state == State.TAKEOFF:
		requested_agl = takeoff_agl_m
	elif state == State.LANDING:
		requested_agl = -1.5
	elif state == State.LOW_LEVEL_TRANSIT:
		if is_nan(_transit_cruise_altitude_m):
			_transit_cruise_altitude_m = maxf(current_pos.y, base_ground + _get_transit_clearance_agl())
		requested_agl = maxf(_transit_cruise_altitude_m - base_ground, min_terrain_clearance_m)
	_desired_altitude_m = base_ground + requested_agl
	if state == State.LOW_LEVEL_TRANSIT and not is_nan(_transit_cruise_altitude_m):
		_desired_altitude_m = _clamp_heightmap_flight_altitude(_transit_cruise_altitude_m)
		_transit_cruise_altitude_m = _desired_altitude_m
		# Bleed cruise altitude back down toward local terrain + cruise_agl over time.
		# This prevents a high ridge early in the route from keeping the helicopter
		# permanently elevated over flat ground for the rest of the flight.
		# The terrain hazard system will immediately raise it again if needed.
		var local_target_altitude := base_ground + _get_transit_clearance_agl()
		if _transit_cruise_altitude_m > local_target_altitude:
			var bleed := minf(
				(_transit_cruise_altitude_m - local_target_altitude) * 0.15,
				12.0
			) * _physics_delta
			_transit_cruise_altitude_m = maxf(_transit_cruise_altitude_m - bleed, local_target_altitude)
			_desired_altitude_m = _transit_cruise_altitude_m

	if state == State.TAKEOFF and _takeoff_started_from_deck and not is_nan(_takeoff_start_altitude_m):
		_desired_altitude_m = maxf(_desired_altitude_m, _takeoff_start_altitude_m + maxf(takeoff_agl_m, deck_takeoff_climb_m))

	if state == State.LOW_LEVEL_TRANSIT and mission_phase == MissionPhase.INBOUND:
		var carrier_final_altitude: float = _get_carrier_landing_approach_altitude()
		if not is_nan(carrier_final_altitude):
			# Enforce deck hover altitude across the entire inbound leg so the helicopter
			# arrives at LANDING altitude already at the right height, not 40 m below it.
			var prev := _desired_altitude_m
			_desired_altitude_m = maxf(carrier_final_altitude, _desired_altitude_m)
			_transit_cruise_altitude_m = _desired_altitude_m
			if absf(_desired_altitude_m - prev) > 2.0:
				_debug_event("carrier_approach_alt", "deck_hover=%.1f prev=%.1f corrected=%.1f" % [
					carrier_final_altitude, prev, _desired_altitude_m])
			if _flat_distance(current_pos, goal) <= maxf(carrier_landing_final_leg_radius_m, carrier_approach_radius_m):
				_nav_waypoint = Vector3(goal.x, _desired_altitude_m, goal.z)
				return

	if state == State.LANDING:
		# Carrier landing: hold above the moving deck point until XZ is precise,
		# then descend. Terrain landing stays at transit clearance until it is
		# actually over the LZ, then descends.
		if _landing_on_carrier:
			var landing_surface_y: float = _get_landing_surface_y()
			if not is_nan(landing_surface_y):
				var landing_dist: float = _flat_distance(current_pos, goal)
				var descent_radius: float = maxf(carrier_landing_descent_start_radius_m, 0.5)
				var hover_altitude: float = landing_surface_y + maxf(carrier_landing_hover_height_m, 0.0)
				_desired_altitude_m = hover_altitude
				if landing_dist <= descent_radius and current_pos.y >= hover_altitude - 1.0:
					_desired_altitude_m = landing_surface_y
		else:
			var landing_dist := _flat_distance(current_pos, goal)
			if landing_dist > maxf(terrain_landing_descent_radius_m, 1.0):
				var corridor_height := _sample_max_terrain_height_along_path(current_pos, goal)
				if not is_nan(corridor_height):
					_desired_altitude_m = maxf(_desired_altitude_m, corridor_height + min_terrain_clearance_m)
			else:
				var landing_surface_y := _get_landing_surface_y()
				if not is_nan(landing_surface_y):
					_desired_altitude_m = landing_surface_y
		_nav_waypoint = Vector3(goal.x, _desired_altitude_m, goal.z)
		return
	if state == State.TAKEOFF and _should_hold_vertical_takeoff():
		_nav_waypoint = Vector3(current_pos.x, _desired_altitude_m, current_pos.z)
		return
	if state == State.TAKEOFF:
		var takeoff_dir := destination - current_pos if _has_destination else aircraft.global_transform.basis.z
		takeoff_dir.y = 0.0
		if takeoff_dir.length_squared() < 1.0:
			takeoff_dir = aircraft.global_transform.basis.z
			takeoff_dir.y = 0.0
		takeoff_dir = takeoff_dir.normalized() if takeoff_dir.length_squared() > 0.001 else Vector3.FORWARD
		var takeoff_lookahead := maxf(terrain_lookahead_m * 0.5, 80.0)
		var takeoff_target := current_pos + takeoff_dir * takeoff_lookahead
		_nav_waypoint = Vector3(takeoff_target.x, _desired_altitude_m, takeoff_target.z)
		return

	# If terrain clearance has already collapsed, stop asking for a forward leg.
	# The normal speed controller will bleed horizontal speed while collective climbs.
	if state != State.LANDING and not is_nan(ground_height):
		var agl := current_pos.y - ground_height
		var clearance_floor := min_terrain_clearance_m + terrain_escape_margin_m if state == State.LOW_LEVEL_TRANSIT else min_terrain_clearance_m
		if agl < clearance_floor:
			_desired_altitude_m = maxf(
				_desired_altitude_m,
				ground_height + clearance_floor + terrain_escape_margin_m
			)
			if state == State.LOW_LEVEL_TRANSIT:
				_desired_altitude_m = _clamp_heightmap_flight_altitude(_desired_altitude_m)
			_nav_waypoint = Vector3(current_pos.x, _desired_altitude_m, current_pos.z)
			return

	var path_point := _get_heightmap_route_point(current_pos, goal)
	if path_point != Vector3.INF:
		var carrot_alt := _clamp_heightmap_flight_altitude(path_point.y)
		# Only raise cruise altitude, never lower it. The path initialises
		# _transit_cruise_altitude_m to the highest node; let it stay there
		# so the helicopter flies at a consistent altitude rather than
		# descending into every valley as the carrot advances.
		if is_nan(_transit_cruise_altitude_m) or carrot_alt > _transit_cruise_altitude_m:
			_transit_cruise_altitude_m = carrot_alt
		_desired_altitude_m = _transit_cruise_altitude_m
		var path_corridor_height: float = _sample_max_terrain_height_along_path(current_pos, path_point)
		if not is_nan(path_corridor_height):
			var path_required_altitude: float = path_corridor_height + _get_transit_clearance_agl() + terrain_escape_margin_m
			if path_required_altitude > _desired_altitude_m:
				_desired_altitude_m = _clamp_heightmap_flight_altitude(path_required_altitude)
				_transit_cruise_altitude_m = maxf(_transit_cruise_altitude_m, _desired_altitude_m)
				_debug_event("path_hazard", "mode=raise_alt hazard=%.1f target_alt=%.1f point=%s" % [
					path_corridor_height,
					_desired_altitude_m,
					str(path_point.snapped(Vector3.ONE * 0.1)),
				])
		_apply_forward_terrain_hazard(current_pos, path_point)
		_nav_waypoint = Vector3(path_point.x, _desired_altitude_m, path_point.z)
		return

	var selected_dir: Vector3 = _choose_low_level_corridor(current_pos, goal)
	var lookahead_distance: float = minf(terrain_lookahead_m, maxf(_flat_distance(current_pos, goal), 80.0))
	var candidate: Vector3 = current_pos + selected_dir * lookahead_distance
	if _flat_distance(current_pos, goal) <= lookahead_distance:
		candidate = goal

	var corridor_height: float = _sample_max_terrain_height_along_path(current_pos, candidate)
	if not is_nan(corridor_height):
		var fallback_required_altitude := corridor_height + min_terrain_clearance_m + terrain_escape_margin_m
		if state == State.LOW_LEVEL_TRANSIT and fallback_required_altitude > _transit_cruise_altitude_m:
			_transit_cruise_altitude_m = _clamp_heightmap_flight_altitude(fallback_required_altitude)
			_desired_altitude_m = _transit_cruise_altitude_m
		else:
			_desired_altitude_m = maxf(_desired_altitude_m, fallback_required_altitude)
			if state == State.LOW_LEVEL_TRANSIT:
				_desired_altitude_m = _clamp_heightmap_flight_altitude(_desired_altitude_m)
		if _apply_corridor_terrain_hazard(current_pos, corridor_height):
			return
	if _apply_forward_terrain_hazard(current_pos, candidate):
		return
	_nav_waypoint = Vector3(candidate.x, _desired_altitude_m, candidate.z)


func _choose_low_level_corridor(current_pos: Vector3, goal: Vector3) -> Vector3:
	var direct: Vector3 = goal - current_pos
	direct.y = 0.0
	if direct.length_squared() < 1.0:
		direct = aircraft.linear_velocity
		direct.y = 0.0
	if direct.length_squared() < 1.0:
		direct = aircraft.global_transform.basis.z
		direct.y = 0.0
	if direct.length_squared() < 0.001:
		return Vector3.FORWARD
	direct = direct.normalized()

	var angles: PackedFloat32Array = PackedFloat32Array([
		0.0,
		deg_to_rad(corridor_angle_deg),
		-deg_to_rad(corridor_angle_deg),
		deg_to_rad(corridor_angle_deg * 2.0),
		-deg_to_rad(corridor_angle_deg * 2.0),
	])
	var best_dir: Vector3 = direct
	var best_score: float = INF
	for angle in angles:
		var dir: Vector3 = direct.rotated(Vector3.UP, angle).normalized()
		var sample_end: Vector3 = current_pos + dir * terrain_lookahead_m
		var terrain_h: float = _sample_max_terrain_height_along_path(current_pos, sample_end)
		var destination_bias: float = _flat_distance(sample_end, goal) * 0.035
		var turn_bias: float = absf(angle) * 12.0
		var height_score: float = terrain_h if not is_nan(terrain_h) else current_pos.y
		var score: float = height_score + destination_bias + turn_bias
		if score < best_score:
			best_score = score
			best_dir = dir
	return best_dir


func _get_transit_clearance_agl() -> float:
	var speed_clearance := cruise_agl_m
	if is_instance_valid(aircraft):
		var control_vel := _get_control_velocity()
		var horizontal_speed := Vector2(control_vel.x, control_vel.z).length()
		speed_clearance += horizontal_speed * maxf(transit_speed_clearance_gain, 0.0)
	var floor_clearance := maxf(cruise_agl_m, min_terrain_clearance_m + terrain_escape_margin_m)
	return clampf(
		maxf(speed_clearance, floor_clearance),
		floor_clearance,
		maxf(transit_speed_clearance_max_agl_m, floor_clearance)
	)


func _apply_forward_terrain_hazard(current_pos: Vector3, route_target: Vector3) -> bool:
	if state != State.LOW_LEVEL_TRANSIT or not is_instance_valid(aircraft):
		return false
	var hazard_height := _sample_forward_terrain_hazard_height(current_pos, route_target)
	if is_nan(hazard_height):
		return false
	return _apply_terrain_hazard_height(current_pos, hazard_height, "forward")


func _apply_corridor_terrain_hazard(current_pos: Vector3, corridor_height: float) -> bool:
	if state != State.LOW_LEVEL_TRANSIT or is_nan(corridor_height):
		return false
	return _apply_terrain_hazard_height(current_pos, corridor_height, "corridor")


func _apply_terrain_hazard_height(current_pos: Vector3, hazard_height: float, source: String) -> bool:
	if state != State.LOW_LEVEL_TRANSIT:
		return false

	var clearance_agl := _get_transit_clearance_agl()
	_desired_altitude_m = maxf(_desired_altitude_m, hazard_height + clearance_agl)
	_desired_altitude_m = _clamp_heightmap_flight_altitude(_desired_altitude_m)
	if is_nan(_transit_cruise_altitude_m) or _desired_altitude_m > _transit_cruise_altitude_m:
		_transit_cruise_altitude_m = _desired_altitude_m

	var hazard_ceiling := hazard_height + maxf(terrain_hazard_vertical_margin_m, 0.0)
	if current_pos.y >= hazard_ceiling:
		return false

	_desired_altitude_m = maxf(_desired_altitude_m, hazard_height + clearance_agl + terrain_escape_margin_m)
	_desired_altitude_m = _clamp_heightmap_flight_altitude(_desired_altitude_m)
	if is_nan(_transit_cruise_altitude_m):
		_transit_cruise_altitude_m = _desired_altitude_m
	else:
		_transit_cruise_altitude_m = maxf(_transit_cruise_altitude_m, _desired_altitude_m)
	_debug_event("terrain_hazard", "source=%s mode=raise_alt hazard=%.1f hazard_ceiling=%.1f alt=%.1f target_alt=%.1f clearance_agl=%.1f" % [
		source,
		hazard_height,
		hazard_ceiling,
		current_pos.y,
		_desired_altitude_m,
		clearance_agl,
	])
	return false


func _sample_forward_terrain_hazard_height(current_pos: Vector3, route_target: Vector3) -> float:
	var control_vel := _get_control_velocity()
	var horizontal_vel := Vector3(control_vel.x, 0.0, control_vel.z)
	var route_dir := route_target - current_pos
	route_dir.y = 0.0

	var probe_dir := Vector3.ZERO
	if horizontal_vel.length_squared() > 1.0:
		probe_dir = horizontal_vel.normalized()
	elif route_dir.length_squared() > 1.0:
		probe_dir = route_dir.normalized()
	else:
		return NAN

	var horizontal_speed := horizontal_vel.length()
	var lookahead := horizontal_speed * maxf(terrain_hazard_lookahead_time_s, 0.0)
	lookahead = clampf(
		lookahead,
		maxf(terrain_hazard_min_lookahead_m, 1.0),
		maxf(terrain_hazard_max_lookahead_m, terrain_hazard_min_lookahead_m)
	)
	var sample_end := current_pos + probe_dir * lookahead
	return _sample_max_terrain_height_along_path(current_pos, sample_end)


func _get_heightmap_route_point(current_pos: Vector3, goal: Vector3) -> Vector3:
	if not use_heightmap_pathfinding or state == State.LANDING:
		return Vector3.INF
	if not _terrain_pathfinding_ready():
		return Vector3.INF

	_heightmap_path_timer_s -= _physics_delta
	var goal_repath_threshold: float = maxf(heightmap_path_goal_move_recompute_m, 1.0)
	if mission_phase == MissionPhase.INBOUND:
		goal_repath_threshold = maxf(carrier_goal_repath_threshold_m, 1.0)
	if not _heightmap_path.is_empty() and _flat_distance(_heightmap_path_goal, goal) > goal_repath_threshold:
		_clear_heightmap_path("goal_moved")
	if _heightmap_path.is_empty() and _heightmap_path_timer_s <= 0.0:
		_rebuild_heightmap_path(current_pos, goal)

	if _heightmap_path.is_empty():
		return Vector3.INF

	# Radius advance: step past waypoints the helicopter is close to.
	while _heightmap_path_index < _heightmap_path.size() - 1 \
			and _flat_distance(current_pos, _heightmap_path[_heightmap_path_index]) <= maxf(heightmap_path_advance_radius_m, 1.0):
		_heightmap_path_index += 1
	# Overshoot advance: if the helicopter has passed the current waypoint along the
	# path direction, step past it. Without this, the carrot points backward and the
	# helicopter makes wide circling orbits trying to revisit the waypoint it overshot.
	while _heightmap_path_index < _heightmap_path.size() - 1:
		var cur_pt := _heightmap_path[_heightmap_path_index]
		var nxt_pt := _heightmap_path[_heightmap_path_index + 1]
		var to_next := Vector3(nxt_pt.x - cur_pt.x, 0.0, nxt_pt.z - cur_pt.z)
		var to_here := Vector3(current_pos.x - cur_pt.x, 0.0, current_pos.z - cur_pt.z)
		if to_next.length_squared() > 1.0 and to_here.dot(to_next.normalized()) > 0.0:
			_heightmap_path_index += 1
		else:
			break
	if _heightmap_path_index >= _heightmap_path.size():
		return goal
	# Clear-segment skip: jump to the furthest waypoint reachable without terrain
	# obstruction. Discards intermediate waypoints the helicopter can fly past directly.
	_advance_heightmap_path_to_clear_point(current_pos)
	if _heightmap_path_index >= _heightmap_path.size():
		return goal
	return _get_heightmap_path_carrot_point(current_pos)


func _advance_heightmap_path_to_clear_point(current_pos: Vector3) -> void:
	if _heightmap_path.is_empty() or _heightmap_path_index >= _heightmap_path.size() - 1:
		return
	var original_index := _heightmap_path_index
	for i in range(_heightmap_path.size() - 1, _heightmap_path_index, -1):
		if _has_clear_transit_segment(current_pos, _heightmap_path[i]):
			_heightmap_path_index = i
			break
	if _heightmap_path_index != original_index:
		_debug_event("path_advance", "from=%d to=%d clear_to=%s" % [
			original_index,
			_heightmap_path_index,
			str(_heightmap_path[_heightmap_path_index].snapped(Vector3.ONE * 0.1)),
		])


func _get_heightmap_path_carrot_point(current_pos: Vector3) -> Vector3:
	if _heightmap_path.is_empty() or _heightmap_path_index >= _heightmap_path.size():
		return Vector3.INF
	var carrot_distance := maxf(heightmap_path_carrot_distance_m, heightmap_path_advance_radius_m)
	var previous := current_pos
	var best := _heightmap_path[_heightmap_path_index]
	var traveled := 0.0
	for i in range(_heightmap_path_index, _heightmap_path.size()):
		var point := _heightmap_path[i]
		var segment_len := _flat_distance(previous, point)
		if traveled + segment_len >= carrot_distance:
			var t := 1.0
			if segment_len > 0.001:
				t = (carrot_distance - traveled) / segment_len
			var carrot := previous.lerp(point, clampf(t, 0.0, 1.0))
			return _smooth_heightmap_corner_carrot(carrot, i)
		traveled += segment_len
		best = point
		previous = point
	return best


func _smooth_heightmap_corner_carrot(carrot: Vector3, path_index: int) -> Vector3:
	if path_index <= 0 or path_index >= _heightmap_path.size() - 1:
		return carrot
	var corner := _heightmap_path[path_index]
	var next_point := _heightmap_path[path_index + 1]
	var corner_dist := _flat_distance(carrot, corner)
	var blend_radius := maxf(heightmap_path_corner_blend_radius_m, 0.0)
	if blend_radius <= 0.0 or corner_dist >= blend_radius:
		return carrot
	var next_leg := next_point - corner
	next_leg.y = 0.0
	if next_leg.length_squared() < 1.0:
		return carrot
	next_leg = next_leg.normalized()
	var blend_t := (1.0 - corner_dist / blend_radius) * clampf(heightmap_path_corner_blend_strength, 0.0, 1.0)
	var corner_cut := corner + next_leg * minf(blend_radius, _flat_distance(corner, next_point) * 0.5)
	corner_cut.y = maxf(corner.y, next_point.y)
	var smoothed := carrot.lerp(corner_cut, blend_t)
	if not _aerial_segment_reasonable(carrot, smoothed):
		return carrot
	if not _aerial_segment_reasonable(smoothed, next_point):
		return carrot
	return smoothed


func _terrain_pathfinding_ready() -> bool:
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")
	if nav_grid == null:
		return false
	if nav_grid.has_method("is_ready") and not bool(nav_grid.call("is_ready")):
		return false
	return true


func _get_heightmap_reference_ground_y() -> float:
	var carrier := get_tree().get_first_node_in_group("carrier")
	if carrier is Node3D:
		var carrier_pos := (carrier as Node3D).global_position
		var carrier_ground := _get_ground_height_at_position(carrier_pos)
		if not is_nan(carrier_ground):
			return carrier_ground
	var current_ground := _get_ground_height_at_position(aircraft.global_position) if is_instance_valid(aircraft) else NAN
	if not is_nan(current_ground):
		return current_ground
	return aircraft.global_position.y - cruise_agl_m if is_instance_valid(aircraft) else 0.0


func _clamp_heightmap_flight_altitude(altitude_m: float) -> float:
	var max_altitude := _get_heightmap_reference_ground_y() + maxf(heightmap_path_max_flight_above_reference_m, 0.0)
	return minf(altitude_m, max_altitude)


func _rebuild_heightmap_path(current_pos: Vector3, goal: Vector3) -> void:
	var start_ms := Time.get_ticks_msec()
	_heightmap_path_timer_s = maxf(heightmap_path_recompute_s, 0.2)
	_last_path_source = "none"
	var new_path: Array[Vector3] = []
	var path_array: Array[Vector3] = _find_aerial_heightmap_path(current_pos, goal)
	var elevated_path := _elevate_aerial_path_points(current_pos, path_array)
	for point_variant in elevated_path:
		if point_variant is Vector3:
			var point := point_variant as Vector3
			if _flat_distance(current_pos, point) > maxf(heightmap_path_advance_radius_m * 0.5, 1.0):
				new_path.append(point)
	if new_path.is_empty():
		_debug_event("path_failed", "source=%s keeping_old=%s goal=%s old_points=%d old_index=%d" % [
			_last_path_source,
			str(not _heightmap_path.is_empty()),
			str(goal.snapped(Vector3.ONE * 0.1)),
			_heightmap_path.size(),
			_heightmap_path_index,
		])
		return

	_heightmap_path_goal = goal
	_heightmap_path = new_path
	_heightmap_path_index = 0
	var route_altitude := _clamp_heightmap_flight_altitude(current_pos.y)
	for path_point in _heightmap_path:
		route_altitude = maxf(route_altitude, _clamp_heightmap_flight_altitude(path_point.y))
	_transit_cruise_altitude_m = route_altitude
	var reference_ground := _get_heightmap_reference_ground_y()
	_debug_event("path", "source=%s ms=%d points=%d ref=%.1f terrain_ceiling=%.1f flight_ceiling=%.1f goal=%s first=%s" % [
		_last_path_source,
		Time.get_ticks_msec() - start_ms,
		_heightmap_path.size(),
		reference_ground,
		reference_ground + maxf(heightmap_path_max_terrain_above_reference_m, 0.0),
		reference_ground + maxf(heightmap_path_max_flight_above_reference_m, 0.0),
		str(goal.snapped(Vector3.ONE * 0.1)),
		str(_heightmap_path[0].snapped(Vector3.ONE * 0.1)),
	])


func _elevate_aerial_path_points(current_pos: Vector3, path: Array[Vector3]) -> Array[Vector3]:
	var elevated: Array[Vector3] = []
	var segment_start := current_pos
	var clearance_agl := _get_transit_clearance_agl()
	for point in path:
		var segment_end := Vector3(point.x, segment_start.y, point.z)
		var corridor_height := _sample_max_terrain_height_along_path(segment_start, segment_end)
		var terrain_height := point.y
		if not is_nan(corridor_height):
			terrain_height = maxf(terrain_height, corridor_height)
		elevated.append(Vector3(point.x, _clamp_heightmap_flight_altitude(terrain_height + clearance_agl), point.z))
		segment_start = point
	return elevated


func _find_low_terrain_navgrid_path(nav_grid: Node, current_pos: Vector3, goal: Vector3) -> Array[Vector3]:
	if nav_grid == null or not nav_grid.has_method("_astar"):
		return []
	var path_variant: Variant = nav_grid.call(
		"_astar",
		current_pos,
		goal,
		maxf(terrain_navgrid_path_slope_m, 1.0),
		INF
	)
	if not (path_variant is Array):
		return []
	var raw_path: Array = path_variant as Array
	var route: Array[Vector3] = []
	for point_variant in raw_path:
		if point_variant is Vector3:
			var point := point_variant as Vector3
			var ground_h := _get_ground_height_at_position(point)
			if not is_nan(ground_h):
				point.y = ground_h
			route.append(point)
	if route.is_empty():
		return []
	if _flat_distance(route[route.size() - 1], goal) > maxf(heightmap_path_advance_radius_m, 1.0):
		route.append(goal)
	return route


func _find_aerial_heightmap_path(current_pos: Vector3, goal: Vector3) -> Array[Vector3]:
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")
	if nav_grid == null:
		return []

	var cols: int = int(nav_grid.get("_cols"))
	var rows: int = int(nav_grid.get("_rows"))
	var heights: PackedFloat32Array = nav_grid.get("_heights") as PackedFloat32Array
	var origin_x: float = float(nav_grid.get("_origin_x"))
	var origin_z: float = float(nav_grid.get("_origin_z"))
	var cell_size: float = maxf(float(nav_grid.get("cell_size_m")), 1.0)
	var impassable: float = float(nav_grid.get("IMPASSABLE"))
	if cols <= 0 or rows <= 0 or heights.is_empty():
		return []
	_last_path_source = "aerial"

	var pad := maxf(heightmap_path_search_padding_m, cell_size * 4.0)
	var gx_min: int = clampi(int(floor((minf(current_pos.x, goal.x) - pad - origin_x) / cell_size)), 0, cols - 1)
	var gz_min: int = clampi(int(floor((minf(current_pos.z, goal.z) - pad - origin_z) / cell_size)), 0, rows - 1)
	var gx_max: int = clampi(int(ceil((maxf(current_pos.x, goal.x) + pad - origin_x) / cell_size)), 0, cols - 1)
	var gz_max: int = clampi(int(ceil((maxf(current_pos.z, goal.z) + pad - origin_z) / cell_size)), 0, rows - 1)

	var start := Vector2i(
		clampi(int((current_pos.x - origin_x) / cell_size), gx_min, gx_max),
		clampi(int((current_pos.z - origin_z) / cell_size), gz_min, gz_max)
	)
	var end := Vector2i(
		clampi(int((goal.x - origin_x) / cell_size), gx_min, gx_max),
		clampi(int((goal.z - origin_z) / cell_size), gz_min, gz_max)
	)
	if start == end:
		return [goal]

	var reference_ground := _get_heightmap_reference_ground_y()
	var max_route_terrain_y := reference_ground + maxf(heightmap_path_max_terrain_above_reference_m, 0.0)
	var route_floor := reference_ground
	var max_step_climb := maxf(heightmap_path_max_step_climb_m, 0.0)
	var ground_band_ceiling := reference_ground + maxf(heightmap_path_ground_level_band_m, 0.0)
	var first_plateau_min_y := reference_ground + maxf(heightmap_path_first_plateau_min_m, 0.0)
	var first_plateau_max_y := reference_ground + maxf(heightmap_path_first_plateau_max_m, heightmap_path_first_plateau_min_m)

	var open: Array = []
	_heap_push_path_node(open, [_aerial_h(start, end, cell_size), start.x, start.y])
	var g_score: Dictionary = { start: 0.0 }
	var came_from: Dictionary = {}
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var iterations := 0
	var max_iterations := maxi((gx_max - gx_min + 1) * (gz_max - gz_min + 1), 1)
	while not open.is_empty() and iterations < max_iterations:
		iterations += 1
		var entry: Array = _heap_pop_path_node(open)
		var cur := Vector2i(int(entry[1]), int(entry[2]))
		if cur == end:
			return _rebuild_aerial_heightmap_path(came_from, cur, heights, cols, origin_x, origin_z, cell_size)

		var cur_h := _heightmap_cell_height(heights, cols, cur.x, cur.y, impassable)
		if cur_h <= impassable * 0.5:
			continue
		for dir in dirs:
			var nb := cur + dir
			if nb.x < gx_min or nb.x > gx_max or nb.y < gz_min or nb.y > gz_max:
				continue
			var nb_h := _heightmap_cell_height(heights, cols, nb.x, nb.y, impassable)
			if nb_h <= impassable * 0.5:
				continue
			var nb_world := Vector3(origin_x + float(nb.x) * cell_size, nb_h, origin_z + float(nb.y) * cell_size)
			var nb_edge_risk := _sample_terrain_edge_risk_at(nb_world)
			if nb_edge_risk >= INF or nb_edge_risk > maxf(heightmap_path_max_edge_risk_m, 0.0):
				continue
			var buf := maxi(heightmap_path_mountain_buffer_cells, 0)
			if buf > 0:
				var mountain_ceiling := reference_ground + maxf(heightmap_path_mountain_avoidance_m, 0.0)
				if _heightmap_has_nearby_high_terrain(heights, cols, rows, nb.x, nb.y, mountain_ceiling, impassable, buf):
					continue
			if nb_h > max_route_terrain_y:
				continue
			if max_step_climb > 0.0 and nb != end and maxf(nb_h - cur_h, 0.0) > max_step_climb:
				continue
			var diagonal := dir.x != 0 and dir.y != 0
			if diagonal:
				var side_a := Vector2i(cur.x + dir.x, cur.y)
				var side_b := Vector2i(cur.x, cur.y + dir.y)
				if _heightmap_cell_blocked_for_aerial_path(
						heights,
						cols,
						side_a,
						impassable,
						max_route_terrain_y,
						origin_x,
						origin_z,
						cell_size
				) or _heightmap_cell_blocked_for_aerial_path(
						heights,
						cols,
						side_b,
						impassable,
						max_route_terrain_y,
						origin_x,
						origin_z,
						cell_size
				):
					continue
			var step_dist := cell_size * (1.4142135 if diagonal else 1.0)
			var altitude_cost := maxf(nb_h - reference_ground, 0.0) * heightmap_path_altitude_penalty
			var climb_cost := maxf(nb_h - cur_h, 0.0) * heightmap_path_climb_penalty
			var high_terrain_cost := maxf(nb_h - route_floor, 0.0) * heightmap_path_high_terrain_penalty
			var edge_cost := nb_edge_risk * maxf(heightmap_path_edge_risk_penalty, 0.0)
			var low_route_cost := 0.0
			if nb_h < first_plateau_min_y:
				low_route_cost = (first_plateau_min_y - nb_h) * maxf(heightmap_path_low_route_penalty, 0.0)
			var top_level_cost := 0.0
			if nb_h > first_plateau_max_y:
				top_level_cost = (nb_h - first_plateau_max_y) * maxf(heightmap_path_top_level_penalty, 0.0)
			var level_cost := 0.0
			if nb_h > ground_band_ceiling:
				level_cost += maxf(heightmap_path_upper_level_penalty, 0.0)
			var cur_ground_level := cur_h <= ground_band_ceiling
			var nb_ground_level := nb_h <= ground_band_ceiling
			if cur_ground_level != nb_ground_level:
				level_cost += maxf(heightmap_path_level_change_penalty, 0.0)
			var tg: float = g_score.get(cur, INF) + step_dist + altitude_cost + climb_cost + high_terrain_cost + edge_cost + low_route_cost + top_level_cost + level_cost
			if tg < g_score.get(nb, INF):
				came_from[nb] = cur
				g_score[nb] = tg
				_heap_push_path_node(open, [tg + _aerial_h(nb, end, cell_size), nb.x, nb.y])
	var navgrid_path := _find_low_terrain_navgrid_path(nav_grid, current_pos, goal)
	if not navgrid_path.is_empty():
		_last_path_source = "navgrid_fallback"
		return navgrid_path
	return []


func _heap_push_path_node(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var i := heap.size() - 1
	while i > 0:
		var parent := int((i - 1) / 2)
		if float(heap[parent][0]) <= float(heap[i][0]):
			break
		var temp: Variant = heap[parent]
		heap[parent] = heap[i]
		heap[i] = temp
		i = parent


func _heap_pop_path_node(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Variant = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = last
	var i := 0
	while true:
		var left := i * 2 + 1
		var right := left + 1
		var smallest := i
		if left < heap.size() and float(heap[left][0]) < float(heap[smallest][0]):
			smallest = left
		if right < heap.size() and float(heap[right][0]) < float(heap[smallest][0]):
			smallest = right
		if smallest == i:
			break
		var temp: Variant = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = temp
		i = smallest
	return result


func _heightmap_has_nearby_high_terrain(
		heights: PackedFloat32Array,
		cols: int,
		rows: int,
		gx: int,
		gz: int,
		mountain_ceiling: float,
		impassable: float,
		radius_cells: int
) -> bool:
	var r := maxi(radius_cells, 0)
	for oz in range(-r, r + 1):
		var sample_z := gz + oz
		if sample_z < 0 or sample_z >= rows:
			continue
		for ox in range(-r, r + 1):
			var sample_x := gx + ox
			if sample_x < 0 or sample_x >= cols:
				continue
			var h := _heightmap_cell_height(heights, cols, sample_x, sample_z, impassable)
			if h > mountain_ceiling:
				return true
	return false


func _heightmap_cell_height(heights: PackedFloat32Array, cols: int, gx: int, gz: int, impassable: float) -> float:
	var idx := gz * cols + gx
	if idx < 0 or idx >= heights.size():
		return impassable
	return heights[idx]


func _heightmap_cell_blocked_for_aerial_path(
		heights: PackedFloat32Array,
		cols: int,
		cell: Vector2i,
		impassable: float,
		max_route_terrain_y: float,
		origin_x: float,
		origin_z: float,
		cell_size: float
) -> bool:
	var h := _heightmap_cell_height(heights, cols, cell.x, cell.y, impassable)
	if h <= impassable * 0.5 or h > max_route_terrain_y:
		return true
	var world := Vector3(origin_x + float(cell.x) * cell_size, h, origin_z + float(cell.y) * cell_size)
	var edge_risk := _sample_terrain_edge_risk_at(world)
	return edge_risk >= INF or edge_risk > maxf(heightmap_path_max_edge_risk_m, 0.0)


func _aerial_h(a: Vector2i, b: Vector2i, cell_size: float) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length() * cell_size


func _rebuild_aerial_heightmap_path(
		came_from: Dictionary,
		end: Vector2i,
		heights: PackedFloat32Array,
		cols: int,
		origin_x: float,
		origin_z: float,
		cell_size: float
) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var cur := end
	while came_from.has(cur):
		var wx := origin_x + float(cur.x) * cell_size
		var wz := origin_z + float(cur.y) * cell_size
		path.append(Vector3(wx, heights[cur.y * cols + cur.x], wz))
		cur = came_from[cur]
	path.reverse()
	return _smooth_aerial_heightmap_path(path)


func _smooth_aerial_heightmap_path(path: Array[Vector3]) -> Array[Vector3]:
	if path.size() <= 2:
		return path
	var result: Array[Vector3] = [path[0]]
	var i := 0
	while i < path.size() - 1:
		var furthest := i + 1
		for j in range(path.size() - 1, i + 1, -1):
			if _aerial_segment_reasonable(path[i], path[j]):
				furthest = j
				break
		result.append(path[furthest])
		i = furthest
	return result


func _aerial_segment_reasonable(a: Vector3, b: Vector3) -> bool:
	var max_h := _sample_max_terrain_height_along_path(a, b)
	if is_nan(max_h):
		return false
	if max_h > _get_heightmap_reference_ground_y() + maxf(heightmap_path_max_terrain_above_reference_m, 0.0):
		return false
	var max_edge_risk := _sample_max_terrain_edge_risk_along_path(a, b)
	var max_allowed_risk := maxf(heightmap_path_max_edge_risk_m, 0.0)
	if max_edge_risk > max_allowed_risk:
		return false
	var endpoint_h := maxf(a.y, b.y)
	return max_h <= endpoint_h + min_terrain_clearance_m + terrain_escape_margin_m


func _has_clear_transit_segment(a: Vector3, b: Vector3) -> bool:
	var max_h := _sample_max_terrain_height_along_path(a, b)
	if is_nan(max_h):
		return false
	if max_h > _get_heightmap_reference_ground_y() + maxf(heightmap_path_max_terrain_above_reference_m, 0.0):
		return false
	var max_edge_risk := _sample_max_terrain_edge_risk_along_path(a, b)
	var max_allowed_risk := maxf(heightmap_path_max_edge_risk_m, 0.0)
	if max_edge_risk > max_allowed_risk:
		return false
	var segment_altitude := maxf(a.y, b.y)
	return max_h + _get_path_segment_clearance_m() <= segment_altitude


func _get_path_segment_clearance_m() -> float:
	return maxf(
		_get_transit_clearance_agl(),
		maxf(min_terrain_clearance_m, 0.0) + maxf(terrain_escape_margin_m, 0.0)
	)


func _fly_transit_vector(target: Vector3, desired_speed: float, delta: float) -> void:
	var current_pos := aircraft.global_position
	var to_target := target - current_pos
	var horizontal_to_target := Vector3(to_target.x, 0.0, to_target.z)
	var has_horizontal_target := horizontal_to_target.length_squared() > 1.0
	var path_dir := horizontal_to_target.normalized() if has_horizontal_target else aircraft.global_transform.basis.z
	path_dir.y = 0.0
	path_dir = path_dir.normalized() if path_dir.length_squared() > 0.001 else Vector3.FORWARD

	var forward := aircraft.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var right := aircraft.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT

	var control_vel := _get_control_velocity()
	var fwd_speed := control_vel.dot(forward)
	var lat_speed := control_vel.dot(right)
	var vertical_speed := control_vel.y
	var fwd_accel := (fwd_speed - _prev_fwd_speed) / maxf(delta, 0.001)
	var lat_accel := (lat_speed - _prev_lat_speed) / maxf(delta, 0.001)
	var vertical_accel: float = (vertical_speed - _prev_vertical_speed) / maxf(delta, 0.001)
	_prev_fwd_speed = fwd_speed
	_prev_lat_speed = lat_speed
	_prev_vertical_speed = vertical_speed

	# Constant forward lean: the helicopter pitches forward by this bias and flies at
	# whatever speed drag allows. No speed target involved — collective owns altitude.
	# The lean scales to zero on approach so the helicopter arrives slow.
	# Approach decel is suppressed during a sharp turn — you can't brake and spin at the
	# same time without going nose-up and backwards. Turn first, then brake once aligned.
	var forward_lean := maxf(transit_cruise_forward_lean, 0.0)
	var approach_lean_scale := 1.0
	if _has_destination:
		var dest_dist := _flat_distance(current_pos, destination)
		var turn_error_early := forward.signed_angle_to(
			(Vector3(destination.x - current_pos.x, 0.0, destination.z - current_pos.z).normalized()
			if Vector3(destination.x - current_pos.x, 0.0, destination.z - current_pos.z).length_squared() > 1.0
			else forward),
			Vector3.UP)
		var turn_suppression := clampf(
			(absf(turn_error_early) - deg_to_rad(maxf(transit_sharp_turn_angle_deg, 0.0)))
			/ deg_to_rad(maxf(transit_sharp_turn_full_angle_deg - transit_sharp_turn_angle_deg, 1.0)),
			0.0, 1.0)
		var base_decel := decel_distance_m if mission_phase != MissionPhase.INBOUND else decel_distance_m * 2.0
		var effective_decel_dist := maxf(base_decel, 1.0) * (1.0 - turn_suppression)
		if dest_dist < effective_decel_dist:
			var approach_t := 1.0 - clampf(dest_dist / maxf(effective_decel_dist, 1.0), 0.0, 1.0)
			# Squared: gentle at first, firms up only close in. Avoids hard yank-back at speed.
			approach_lean_scale = 1.0 - approach_t * approach_t
	forward_lean *= approach_lean_scale
	# Rate-limit how fast forward lean can drop — prevents sudden pitch-up from
	# approach decel or speed target changes causing panic braking.
	# Inbound: allow faster lean drop so approach decel actually works.
	var lean_drop_rate := transit_forward_lean_drop_rate if mission_phase != MissionPhase.INBOUND \
		else transit_forward_lean_drop_rate * 4.0
	forward_lean = maxf(forward_lean, _prev_forward_lean - maxf(lean_drop_rate, 0.001) * _physics_delta)
	_prev_forward_lean = forward_lean
	# max_speed_mps drives collective energy management (not pitch).
	_speed_target_mps = maxf(max_speed_mps, 0.0)
	var horizontal_speed := Vector2(control_vel.x, control_vel.z).length()
	var forward_error := forward_lean
	var lateral_error := path_dir.dot(right) * minf(horizontal_speed, maxf(transit_lateral_max_demand_mps, 0.0)) - lat_speed
	var turn_error := forward.signed_angle_to(path_dir, Vector3.UP)
	var absolute_turn_error := absf(turn_error)
	var terrain_recovery_t: float = 0.0
	var ground_h := _get_ground_height_at_position(current_pos)
	# Skip terrain recovery during carrier approach — the helicopter is near the
	# carrier deck at low AGL intentionally. Terrain recovery kills speed and
	# collective at exactly the wrong moment.
	var skip_terrain_recovery := state == State.LANDING and _landing_on_carrier
	if not skip_terrain_recovery and not is_nan(ground_h):
		var agl := current_pos.y - ground_h
		var recovery_start := maxf(terrain_recovery_agl_m, terrain_recovery_full_agl_m + 0.1)
		var recovery_full := maxf(terrain_recovery_full_agl_m, 0.1)
		var low_agl_t := clampf(
			(recovery_start - agl) / maxf(recovery_start - recovery_full, 0.001),
			0.0,
			1.0
		)
		terrain_recovery_t = low_agl_t
	# Lateral wall probes: sample terrain 55 m to each side and compute repulsion.
	# risk = 0 when terrain is more than wall_margin below helicopter; 1.0 when at or above.
	var lateral_wall_roll := 0.0
	var lateral_wall_yaw := 0.0
	var _probe_dist := maxf(lateral_obstacle_probe_dist_m, 1.0)
	var _wall_margin := maxf(lateral_obstacle_margin_m, 1.0)
	var _probe_fwd := cos(deg_to_rad(clampf(lateral_obstacle_probe_angle_deg, 0.0, 89.9)))
	var _probe_side := sin(deg_to_rad(clampf(lateral_obstacle_probe_angle_deg, 0.0, 89.9)))
	var _left_dir := (forward * _probe_fwd - right * _probe_side).normalized()
	var _right_dir := (forward * _probe_fwd + right * _probe_side).normalized()
	var _left_h := _get_ground_height_at_position(current_pos + _left_dir * _probe_dist)
	var _right_h := _get_ground_height_at_position(current_pos + _right_dir * _probe_dist)
	var _left_risk := 0.0 if is_nan(_left_h) else clampf(1.0 + (_left_h - current_pos.y) / _wall_margin, 0.0, 1.0)
	var _right_risk := 0.0 if is_nan(_right_h) else clampf(1.0 + (_right_h - current_pos.y) / _wall_margin, 0.0, 1.0)
	if _left_risk > 0.0 or _right_risk > 0.0:
		lateral_wall_roll = (_left_risk - _right_risk) * maxf(lateral_obstacle_roll_gain, 0.0)
		lateral_wall_yaw = (_left_risk - _right_risk) * maxf(lateral_obstacle_yaw_gain, 0.0)
	var bank_speed_start: float = maxf(transit_low_speed_bank_start_mps, 0.0)
	var bank_speed_full: float = maxf(transit_low_speed_bank_full_mps, bank_speed_start + 1.0)
	var bank_speed_t: float = clampf(
		(horizontal_speed - bank_speed_start) / maxf(bank_speed_full - bank_speed_start, 0.001),
		0.0,
		1.0
	)
	var low_speed_turn: float = 1.0 - bank_speed_t
	var backward_speed: float = maxf(-fwd_speed, 0.0)
	var backward_roll_start: float = maxf(transit_backward_roll_cut_start_mps, 0.0)
	var backward_roll_full: float = maxf(transit_backward_roll_cut_full_mps, backward_roll_start + 0.1)
	var backward_turn: float = clampf(
		(backward_speed - backward_roll_start) / maxf(backward_roll_full - backward_roll_start, 0.001),
		0.0,
		1.0
	)
	var reverse_recovery_start: float = maxf(transit_reverse_recovery_start_mps, 0.0)
	var reverse_recovery_full: float = maxf(transit_reverse_recovery_full_mps, reverse_recovery_start + 0.1)
	var reverse_recovery: float = clampf(
		(backward_speed - reverse_recovery_start) / maxf(reverse_recovery_full - reverse_recovery_start, 0.001),
		0.0,
		1.0
	)
	var high_speed_start: float = maxf(transit_high_speed_turn_start_mps, 0.0)
	var high_speed_full: float = maxf(transit_high_speed_turn_full_mps, high_speed_start + 1.0)
	var high_speed_turn: float = clampf(
		(horizontal_speed - high_speed_start) / maxf(high_speed_full - high_speed_start, 0.001),
		0.0,
		1.0
	)
	var sharp_angle_start := deg_to_rad(maxf(transit_sharp_turn_angle_deg, 0.0))
	var sharp_angle_full := deg_to_rad(maxf(transit_sharp_turn_full_angle_deg, transit_sharp_turn_angle_deg + 1.0))
	var sharp_turn := clampf(
		(absolute_turn_error - sharp_angle_start) / maxf(sharp_angle_full - sharp_angle_start, 0.001),
		0.0,
		1.0
	)
	var pedal_angle_start := deg_to_rad(maxf(transit_pedal_turn_angle_deg, 0.0))
	var pedal_angle_range := maxf(PI - pedal_angle_start, 0.001)
	var pedal_angle_t := clampf((absolute_turn_error - pedal_angle_start) / pedal_angle_range, 0.0, 1.0)
	var pedal_speed_t := clampf(horizontal_speed / maxf(transit_pedal_turn_speed_mps, 0.1), 0.0, 1.0)
	var pedal_turn := pedal_angle_t * (1.0 - pedal_speed_t)
	pedal_turn = maxf(pedal_turn, backward_turn)
	var min_forward_lean: float = minf(
		maxf(transit_min_forward_lean, 0.0),
		maxf(transit_cruise_forward_lean, 0.0)
	)
	if pedal_turn > 0.0:
		forward_lean = lerpf(forward_lean, min_forward_lean, pedal_turn)
		lateral_error *= 1.0 - pedal_turn
	if backward_turn > 0.0:
		lateral_error = lerpf(lateral_error, -lat_speed, backward_turn)
		forward_lean = maxf(forward_lean, min_forward_lean)
	if sharp_turn > 0.0:
		var turn_scale := lerpf(1.0, maxf(transit_sharp_turn_lean_scale, 0.0), sharp_turn)
		# Use min so approach decel and sharp-turn decel don't compound multiplicatively.
		# The helicopter decelerates to whichever constraint is tighter, not both at once.
		var combined := maxf(transit_cruise_forward_lean, 0.0) * minf(approach_lean_scale, turn_scale)
		forward_lean = maxf(minf(forward_lean, combined), min_forward_lean)
	if reverse_recovery > 0.0:
		forward_lean = maxf(
			forward_lean,
			lerpf(min_forward_lean, maxf(transit_reverse_recovery_lean, min_forward_lean), reverse_recovery)
		)

	# Terrain climb speed limit: if the required climb to clear terrain ahead exceeds
	# what the helicopter can achieve at current speed, back off the forward lean so it
	# slows down enough to make the climb. At 70 m/s into a 200m cliff it simply can't
	# climb fast enough — it must slow down first.
	if horizontal_speed > 5.0:
		var altitude_deficit := target.y - current_pos.y
		if altitude_deficit > 0.0:
			# Time available to make the climb at current speed before hitting the hazard.
			# Use a conservative lookahead based on speed and terrain hazard distance.
			var time_available := maxf(terrain_hazard_min_lookahead_m, 1.0) / maxf(horizontal_speed, 1.0)
			var required_climb_rate := altitude_deficit / maxf(time_available, 0.5)
			var climb_capacity := maxf(max_climb_mps, 1.0)
			if required_climb_rate > climb_capacity:
				# Scale forward lean down so the helicopter bleeds speed.
				# At 2× required climb rate, forward lean halves. At 4×, nearly zero.
				var overload := clampf(required_climb_rate / climb_capacity, 1.0, 4.0)
				var terrain_speed_scale := 1.0 / overload
				forward_lean = minf(forward_lean, maxf(transit_cruise_forward_lean, 0.0) * terrain_speed_scale)
				forward_lean = maxf(forward_lean, min_forward_lean)

	var lookahead_s := maxf(cyclic_altitude_rate_lookahead_s, 0.0)
	var predicted_alt_error := target.y - (current_pos.y + vertical_speed * lookahead_s)
	var target_vertical_rate := predicted_alt_error * cyclic_target_climb_from_alt_error_mps
	if target_vertical_rate >= 0.0:
		target_vertical_rate = minf(target_vertical_rate, maxf(cyclic_target_climb_mps, 0.0))
	else:
		target_vertical_rate = maxf(target_vertical_rate, -maxf(cyclic_target_sink_mps, 0.0))

	if not is_nan(ground_h):
		var agl := current_pos.y - ground_h
		var desired_clearance := maxf(min_terrain_clearance_m + terrain_escape_margin_m, 1.0)
		var predicted_agl := agl + vertical_speed * lookahead_s
		var clearance_vertical_rate := (desired_clearance - predicted_agl) * cyclic_target_climb_from_alt_error_mps
		target_vertical_rate = maxf(
			target_vertical_rate,
			minf(clearance_vertical_rate, maxf(cyclic_target_climb_mps, 0.0))
		)

	var vertical_rate_error := target_vertical_rate - vertical_speed
	var cyclic_limit := clampf(max_cyclic_input, 0.0, 1.0)
	var speed_pitch := -forward_lean
	var altitude_pitch := (
		vertical_rate_error * cyclic_altitude_rate_gain
		- vertical_accel * maxf(cyclic_vertical_accel_damping, 0.0)
	)
	if reverse_recovery > 0.0:
		altitude_pitch *= lerpf(1.0, clampf(transit_reverse_altitude_pitch_blend, 0.0, 1.0), reverse_recovery)
	var vertical_priority := 0.0
	var target_pitch := clampf(speed_pitch + altitude_pitch, -cyclic_limit, cyclic_limit)
	# Never let a climb demand or braking pitch push the nose above the minimum forward lean.
	# Without this, a tight turn + climb = full nose-up, the helicopter bleeds speed,
	# slides sideways in the air, and then struggles to recover heading.
	# The floor fades out below a minimum speed so a stationary hover can still pitch up freely.
	# At speed: never pitch more nose-up than transit_max_nose_up.
	# This is the primary anti-panic-braking rule — steer or add power instead.
	# Fades out below low-speed threshold so hover/landing can still pitch up freely.
	var pitch_floor_speed_t := clampf(
		(horizontal_speed - transit_low_speed_bank_start_mps) / maxf(transit_low_speed_bank_full_mps - transit_low_speed_bank_start_mps, 1.0),
		0.0, 1.0
	)
	var min_pitch_floor := -maxf(transit_min_forward_lean, 0.0)
	var effective_pitch_floor := lerpf(0.0, min_pitch_floor, pitch_floor_speed_t)
	var effective_nose_up_cap := lerpf(1.0, maxf(transit_max_nose_up, 0.0), pitch_floor_speed_t)
	target_pitch = clampf(target_pitch, -1.0, effective_nose_up_cap)
	target_pitch = minf(target_pitch, effective_pitch_floor)

	var turn_roll := turn_error * transit_turn_roll_gain
	var path_lateral_error := horizontal_to_target.dot(right)
	var lateral_roll_scale: float = lerpf(
		1.0,
		clampf(transit_high_speed_lateral_roll_scale, 0.0, 1.0),
		high_speed_turn
	)
	var roll_command := (
		turn_roll
		+ (path_lateral_error * transit_lateral_position_gain
			+ lateral_error * transit_lateral_velocity_gain
			- lat_accel * cyclic_lat_d_gain) * lateral_roll_scale
	)
	var sharp_roll_scale := lerpf(1.0, clampf(transit_sharp_turn_roll_scale, 0.0, 1.0), sharp_turn)
	var pedal_roll_scale := lerpf(1.0, clampf(transit_pedal_turn_roll_scale, 0.0, 1.0), pedal_turn)
	var high_speed_roll_scale := lerpf(
		1.0,
		clampf(transit_high_speed_roll_scale, 0.0, 1.0),
		high_speed_turn
	)
	var low_speed_roll_scale: float = lerpf(
		clampf(transit_low_speed_roll_scale, 0.0, 1.0),
		1.0,
		bank_speed_t * bank_speed_t
	)
	var target_roll := clampf(
		roll_command * minf(minf(sharp_roll_scale, pedal_roll_scale), high_speed_roll_scale) * low_speed_roll_scale,
		-cyclic_limit,
		cyclic_limit
	)
	if backward_turn > 0.0:
		target_roll = lerpf(target_roll, 0.0, backward_turn)
	var pullback_speed_start: float = maxf(transit_bank_pullback_start_mps, 0.0)
	var pullback_speed_full: float = maxf(transit_bank_pullback_full_mps, pullback_speed_start + 1.0)
	var pullback_speed_t: float = clampf(
		(horizontal_speed - pullback_speed_start) / maxf(pullback_speed_full - pullback_speed_start, 0.001),
		0.0,
		1.0
	)
	var bank_pullback: float = absf(target_roll) * pullback_speed_t * maxf(transit_bank_pullback_gain, 0.0)
	target_pitch = clampf(target_pitch + bank_pullback, -cyclic_limit, cyclic_limit)

	# Reduce bank when close to terrain so the lift vector stays mostly vertical
	# and collective can actually arrest descent. terrain_recovery_t goes to 1.0 at
	# terrain_recovery_full_agl_m; terrain_recovery_max_bank_scale caps the roll there.
	var terrain_bank_scale := lerpf(1.0, maxf(terrain_recovery_max_bank_scale, 0.0), terrain_recovery_t)
	target_roll = clampf(target_roll, -cyclic_limit * terrain_bank_scale, cyclic_limit * terrain_bank_scale)
	# Lateral wall avoidance stays within the terrain bank limit.
	target_roll = clampf(target_roll + lateral_wall_roll, -cyclic_limit * terrain_bank_scale, cyclic_limit * terrain_bank_scale)

	var base_yaw_limit := clampf(max_yaw_input, 0.0, 1.0)
	var low_speed_yaw_limit := lerpf(
		base_yaw_limit,
		clampf(transit_low_speed_yaw_input, 0.0, 1.0),
		low_speed_turn
	)
	var sharp_yaw_limit := lerpf(low_speed_yaw_limit, clampf(transit_sharp_turn_yaw_input, 0.0, 1.0), sharp_turn)
	var high_speed_yaw_limit := lerpf(
		sharp_yaw_limit,
		clampf(transit_high_speed_yaw_input, 0.0, 1.0),
		high_speed_turn
	)
	var yaw_limit := lerpf(
		high_speed_yaw_limit,
		clampf(transit_pedal_turn_yaw_input, 0.0, 1.0),
		pedal_turn
	)
	var low_speed_yaw_gain := lerpf(
		maxf(transit_turn_yaw_gain, 0.0),
		maxf(transit_low_speed_yaw_gain, 0.0),
		low_speed_turn
	)
	var sharp_yaw_gain := lerpf(
		low_speed_yaw_gain,
		maxf(transit_sharp_turn_yaw_gain, 0.0),
		sharp_turn
	)
	sharp_yaw_gain = lerpf(
		sharp_yaw_gain,
		maxf(transit_high_speed_yaw_gain, 0.0),
		high_speed_turn
	)
	var transit_yaw_gain := lerpf(
		sharp_yaw_gain,
		maxf(transit_pedal_turn_yaw_gain, 0.0),
		pedal_turn
	)
	var heading_yaw := turn_error * transit_yaw_gain
	# Coordinated turn: measure the sideslip angle between the nose and the velocity
	# vector and yaw to null it, keeping the flight path vector pointing forward.
	var coordinated_yaw := 0.0
	if horizontal_speed > 5.0:
		var vel_horiz := Vector3(control_vel.x, 0.0, control_vel.z)
		if vel_horiz.length_squared() > 1.0:
			var sideslip := forward.signed_angle_to(vel_horiz.normalized(), Vector3.UP)
			coordinated_yaw = sideslip * maxf(transit_coordinated_yaw_gain, 0.0)
	var target_yaw := clampf(heading_yaw - aircraft.angular_velocity.y * yaw_rate_damping + lateral_wall_yaw + coordinated_yaw, -yaw_limit, yaw_limit)

	# Emergency sink recovery: if descending fast at low AGL, override everything —
	# level the nose, flatten roll, and go to full collective immediately.
	# This is a last-resort guard, not a flight mode: it only fires when already in danger.
	var emergency_t := 0.0
	if not is_nan(ground_h):
		var agl := aircraft.global_position.y - ground_h
		var sink_rate := maxf(-vertical_speed, 0.0)
		var sink_danger := clampf(
			(sink_rate - maxf(sink_guard_mps, 1.0)) / maxf(sink_guard_mps, 1.0),
			0.0, 1.0
		)
		var agl_danger := clampf(
			1.0 - (agl - maxf(altitude_guard_m, 1.0)) / maxf(altitude_guard_m * 3.0, 1.0),
			0.0, 1.0
		)
		emergency_t = sink_danger * agl_danger
		if emergency_t > 0.0:
			target_pitch = lerpf(target_pitch, 0.0, emergency_t)
			target_roll = lerpf(target_roll, 0.0, emergency_t)
			_debug_event("sink_recovery", "t=%.2f agl=%.1f sink=%.1f" % [emergency_t, agl, sink_rate]) if emergency_t > 0.5 else null

	_pitch_cmd = move_toward(_pitch_cmd, target_pitch, maxf(cyclic_rate, 0.01) * delta)
	_roll_cmd = move_toward(_roll_cmd, target_roll, maxf(cyclic_rate, 0.01) * delta)
	_yaw_cmd = move_toward(_yaw_cmd, target_yaw, maxf(yaw_command_rate, 0.01) * delta)

	_debug_target_vertical_rate_mps = target_vertical_rate
	_debug_vertical_rate_error_mps = vertical_rate_error
	_debug_forward_error_mps = forward_error
	_debug_lateral_error_mps = lateral_error
	_debug_speed_pitch = speed_pitch
	_debug_altitude_pitch = altitude_pitch
	_debug_turn_roll = target_roll
	_debug_sharp_turn = sharp_turn
	_debug_pedal_turn = pedal_turn
	_debug_low_speed_turn = low_speed_turn
	_debug_high_speed_turn = high_speed_turn
	_debug_backward_turn = maxf(backward_turn, reverse_recovery)
	_debug_bank_pullback = bank_pullback
	_debug_target_yaw = target_yaw
	_debug_terrain_recovery = terrain_recovery_t
	_debug_vertical_priority = vertical_priority

	_set_helicopter_input(_pitch_cmd, _roll_cmd, _yaw_cmd)
	var collective_target := _calculate_collective(target.y)
	if emergency_t > 0.0:
		collective_target = lerpf(collective_target, 1.0, emergency_t)
	_debug_collective_target = collective_target
	_apply_collective(collective_target)


func _fly_toward(target: Vector3, desired_speed: float, delta: float) -> void:
	if state == State.LOW_LEVEL_TRANSIT:
		_fly_transit_vector(target, desired_speed, delta)
		return

	var current_pos: Vector3 = aircraft.global_position
	var horiz: Vector3 = Vector3(target.x - current_pos.x, 0.0, target.z - current_pos.z)
	var dist: float = horiz.length()
	var final_terrain_landing_t: float = 0.0
	var final_carrier_landing_t: float = 0.0
	if state == State.LANDING and not _landing_on_carrier:
		var landing_surface_y := _get_landing_surface_y()
		if not is_nan(landing_surface_y):
			var landing_agl := current_pos.y - landing_surface_y
			# AGL-only: stop horizontal movement and raise roll authority whenever
			# the helicopter is close to the ground, regardless of LZ centerline distance.
			final_terrain_landing_t = clampf(
				1.0 - landing_agl / maxf(landing_final_horizontal_hold_agl_m, 0.1),
				0.0,
				1.0
			)
	elif state == State.LANDING and _landing_on_carrier:
		final_carrier_landing_t = 1.0
	var final_landing_t: float = maxf(final_terrain_landing_t, final_carrier_landing_t)
	var guidance_deadzone := 1.0
	if state == State.TAKEOFF or state == State.LOW_LEVEL_TRANSIT:
		guidance_deadzone = maxf(horizontal_guidance_deadzone_m, 1.0)
	elif final_landing_t > 0.0:
		guidance_deadzone = 0.05
	var horizontal_guidance_active := dist > guidance_deadzone
	var target_dir := horiz.normalized() if horizontal_guidance_active else Vector3.ZERO
	var position_error := horiz if horizontal_guidance_active else Vector3.ZERO
	if final_landing_t > 0.0:
		position_error = horiz

	var forward := aircraft.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var right := aircraft.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT

	var control_vel := _get_control_velocity()

	# Speed profile. Transit waypoints steer the route; they are not brake points.
	var spd: float
	if state == State.LANDING and _landing_on_carrier:
		# Deck-relative creeping speed: stay matched to the carrier while trimming
		# the last few meters instead of accepting a loose hover radius.
		spd = clampf(dist * maxf(carrier_landing_position_speed_gain, 0.0), 0.0, hover_speed_mps)
	elif state == State.HOVER or state == State.LANDING:
		var dist_t := clampf(dist / maxf(waypoint_accept_radius_m * 2.0, 1.0), 0.0, 1.0)
		spd = lerpf(1.0, hover_speed_mps, dist_t)
		if final_terrain_landing_t > 0.0:
			spd = lerpf(spd, 0.0, final_terrain_landing_t)
	elif state == State.LOW_LEVEL_TRANSIT:
		spd = desired_speed
	else:
		spd = clampf(dist * desired_speed / maxf(decel_distance_m, 1.0), 0.0, desired_speed)
	# Rate-limit the speed target so state transitions (e.g. TRANSIT → LANDING) don't
	# instantly demand a stop and cause a hard pitch-up brake.
	var speed_decel_step := maxf(transit_speed_target_decel_mps2, 0.0) * delta
	var speed_accel_step := maxf(transit_speed_target_accel_mps2, 0.0) * delta
	_speed_target_mps = move_toward(_speed_target_mps, spd,
			speed_decel_step if spd < _speed_target_mps else speed_accel_step)

	# Measured speeds in aircraft axes — used for both P error and D derivative
	var fwd_speed := control_vel.dot(forward)
	var lat_speed := control_vel.dot(right)
	var vertical_speed: float = control_vel.y

	# D term: derivative of measured speed ("D on measurement" — no spike when setpoint changes)
	var fwd_accel := (fwd_speed - _prev_fwd_speed) / maxf(delta, 0.001)
	var lat_accel := (lat_speed - _prev_lat_speed) / maxf(delta, 0.001)
	var vertical_accel: float = (vertical_speed - _prev_vertical_speed) / maxf(delta, 0.001)
	_prev_fwd_speed = fwd_speed
	_prev_lat_speed = lat_speed
	_prev_vertical_speed = vertical_speed

	# P term: velocity error in aircraft axes. In transit, keep forward energy
	# through turns and let roll steer toward the path; do not brake just because
	# the next carrot point is off the nose.
	var desired_vel := target_dir * spd
	var vel_err_fwd := desired_vel.dot(forward) - fwd_speed
	var vel_err_lat := desired_vel.dot(right) - lat_speed
	if state == State.LOW_LEVEL_TRANSIT:
		vel_err_fwd = spd - fwd_speed
		vel_err_lat = target_dir.dot(right) * spd - lat_speed

	# Yaw is trim, not primary steering. In transit the helicopter turns with cyclic roll;
	# pedal yaw only damps spin so it does not kick back and forth between headings.
	var desired_heading := target_dir if target_dir.length_squared() > 0.001 else forward
	var yaw_error := forward.signed_angle_to(desired_heading, Vector3.UP)
	var yaw_rate := aircraft.angular_velocity.y
	var yaw_limit := clampf(max_yaw_input, 0.0, 1.0)
	var yaw_heading_gain := 0.0 if state == State.LOW_LEVEL_TRANSIT else yaw_gain
	var target_yaw := clampf(yaw_error * yaw_heading_gain - yaw_rate * yaw_rate_damping, -yaw_limit, yaw_limit)
	_yaw_cmd = move_toward(_yaw_cmd, target_yaw, maxf(yaw_command_rate, 0.01) * delta)

	# Pitch trades speed and altitude using predicted vertical motion. This keeps
	# the cyclic ahead of the helicopter's delayed response instead of reacting
	# only after altitude has already drifted badly.
	var horizontal_speed := Vector2(control_vel.x, control_vel.z).length()
	var cyclic_limit := clampf(max_cyclic_input, 0.0, 1.0)
	var vertical_rate_error := 0.0
	var target_vertical_rate := 0.0
	var altitude_trade_pitch := 0.0
	if state != State.LANDING:
		var lookahead_s := maxf(cyclic_altitude_rate_lookahead_s, 0.0)
		var predicted_alt_error := target.y - (current_pos.y + vertical_speed * lookahead_s)
		target_vertical_rate = predicted_alt_error * cyclic_target_climb_from_alt_error_mps
		if target_vertical_rate >= 0.0:
			target_vertical_rate = minf(target_vertical_rate, maxf(cyclic_target_climb_mps, 0.0))
		else:
			target_vertical_rate = maxf(target_vertical_rate, -maxf(cyclic_target_sink_mps, 0.0))
		if state == State.TAKEOFF and current_pos.y < target.y:
			target_vertical_rate = maxf(
				target_vertical_rate,
				minf(maxf(takeoff_min_climb_until_clear_mps, 0.0), maxf(cyclic_target_climb_mps, 0.0))
			)

		var ground_h := _get_ground_height_at_position(current_pos)
		if not is_nan(ground_h):
			var agl := current_pos.y - ground_h
			var desired_clearance := maxf(min_terrain_clearance_m + terrain_escape_margin_m, 1.0)
			var predicted_agl := agl + vertical_speed * lookahead_s
			var clearance_vertical_rate := (desired_clearance - predicted_agl) * cyclic_target_climb_from_alt_error_mps
			target_vertical_rate = maxf(
				target_vertical_rate,
				minf(clearance_vertical_rate, maxf(cyclic_target_climb_mps, 0.0))
			)

		vertical_rate_error = target_vertical_rate - vertical_speed
		altitude_trade_pitch = clampf(
			vertical_rate_error * cyclic_altitude_rate_gain
			- vertical_accel * maxf(cyclic_vertical_accel_damping, 0.0),
			-cyclic_limit,
			cyclic_limit
		)
		if state == State.TAKEOFF and current_pos.y < target.y:
			if horizontal_speed < maxf(cyclic_altitude_trade_min_speed_mps, 0.0):
				altitude_trade_pitch = 0.0
			else:
				altitude_trade_pitch = maxf(altitude_trade_pitch, 0.0)
	_debug_target_vertical_rate_mps = target_vertical_rate
	_debug_vertical_rate_error_mps = vertical_rate_error

	var pitch_velocity_gain := lerpf(
		cyclic_speed_gain,
		maxf(landing_final_velocity_gain, cyclic_speed_gain),
		final_landing_t
	)
	var pitch_accel_damping := lerpf(
		cyclic_speed_d_gain,
		maxf(landing_final_accel_damping_gain, cyclic_speed_d_gain),
		final_landing_t
	)
	var final_position_pitch := -position_error.dot(forward) * maxf(landing_final_position_gain, 0.0) * final_landing_t
	var speed_pitch := -vel_err_fwd * pitch_velocity_gain + fwd_accel * pitch_accel_damping + final_position_pitch
	_debug_forward_error_mps = vel_err_fwd
	_debug_lateral_error_mps = vel_err_lat
	_debug_speed_pitch = speed_pitch
	_debug_altitude_pitch = altitude_trade_pitch
	_debug_turn_roll = -yaw_error * coordinated_turn_gain
	_debug_sharp_turn = 0.0
	_debug_pedal_turn = 0.0
	_debug_low_speed_turn = 0.0
	_debug_high_speed_turn = 0.0
	_debug_backward_turn = 0.0
	_debug_bank_pullback = 0.0
	_debug_target_yaw = 0.0
	_debug_terrain_recovery = 0.0
	var vertical_priority := 0.0
	_debug_vertical_priority = vertical_priority
	var target_pitch := clampf(speed_pitch + altitude_trade_pitch, -cyclic_limit, cyclic_limit)

	# Roll PD: path correction + lateral speed damping + coordinated bank into turns
	var roll_position_gain := lerpf(
		cyclic_lat_pos_gain,
		maxf(landing_final_position_gain, cyclic_lat_pos_gain),
		final_landing_t
	)
	var roll_velocity_gain := lerpf(
		cyclic_lat_vel_gain,
		maxf(landing_final_velocity_gain, cyclic_lat_vel_gain),
		final_landing_t
	)
	var roll_accel_damping := lerpf(
		cyclic_lat_d_gain,
		maxf(landing_final_accel_damping_gain, cyclic_lat_d_gain),
		final_landing_t
	)
	var target_roll := clampf(
		position_error.dot(right) * roll_position_gain
		+ vel_err_lat * roll_velocity_gain
		- lat_accel * roll_accel_damping
		- yaw_error * coordinated_turn_gain,
		-cyclic_limit, cyclic_limit
	)

	# Rate-limit both axes so commands build gradually, not instantly
	_pitch_cmd = move_toward(_pitch_cmd, target_pitch, maxf(cyclic_rate, 0.01) * delta)
	_roll_cmd = move_toward(_roll_cmd, target_roll, maxf(cyclic_rate, 0.01) * delta)

	_set_helicopter_input(_pitch_cmd, _roll_cmd, _yaw_cmd)
	var collective_target := _calculate_collective(target.y)
	_debug_collective_target = collective_target
	_apply_collective(collective_target)


func _calculate_collective(target_altitude_m: float) -> float:
	# Two-loop altitude PD:
	#   Outer loop (P): altitude error → desired climb rate
	#   Inner loop (P): climb rate error → collective
	# Together these act as PD on altitude without the D-overwhelms-P scaling problem.
	var alt_error := target_altitude_m - aircraft.global_position.y
	var descent_limit := max_descent_mps
	if state == State.LANDING:
		descent_limit = _get_landing_descent_limit_mps()
	var desired_climb := clampf(alt_error * altitude_to_climb_gain, -descent_limit, max_climb_mps)
	var climb_error := desired_climb - aircraft.linear_velocity.y
	var collective := _get_collective_trim()
	collective += climb_error * collective_climb_gain
	# Roll-turn lift compensation is handled with cyclic pullback, not extra thrust.
	# Speed-induced extra lift demand in forward flight
	var control_vel := _get_control_velocity()
	var horizontal_speed := Vector2(control_vel.x, control_vel.z).length()
	collective += clampf(horizontal_speed / maxf(max_speed_mps, 1.0), 0.0, 1.0) * collective_speed_lift_bias
	if state == State.TAKEOFF or state == State.LOW_LEVEL_TRANSIT:
		return _calculate_transit_collective(collective, alt_error, horizontal_speed)
	if alt_error > altitude_guard_m:
		var climb_power_t := clampf(
			alt_error / maxf(collective_full_climb_alt_error_m, 1.0),
			0.0,
			1.0
		)
		collective = maxf(collective, lerpf(_get_collective_trim(), 1.0, climb_power_t))
	if state == State.TAKEOFF:
		collective = maxf(collective, _get_takeoff_collective_floor())
	if state == State.LANDING and (_carrier_approach_phase == CarrierApproachPhase.DESCEND or not _landing_on_carrier):
		# Flare only during actual descent (carrier) or terrain landing.
		# Skip during TO_APPROACH_POINT / FINAL — the helicopter may be below deck
		# height and the flare code would incorrectly suppress collective.
		var surface_y := _get_landing_surface_y()
		var agl := aircraft.global_position.y - surface_y if not is_nan(surface_y) else landing_flare_agl_m
		var trim := _get_collective_trim()
		if agl <= maxf(landing_flare_agl_m, 0.5):
			var descent_rate := maxf(-aircraft.linear_velocity.y, 0.0)
			var descent_limit_now := _get_landing_descent_limit_mps()
			var descent_overspeed := maxf(descent_rate - descent_limit_now, 0.0)
			var descent_shortfall := maxf(descent_limit_now - descent_rate, 0.0)
			var ground_effect_t := clampf(1.0 - agl / maxf(landing_flare_agl_m, 0.5), 0.0, 1.0)
			collective -= descent_shortfall * maxf(landing_settle_collective_gain, 0.0)
			collective -= ground_effect_t * maxf(landing_ground_effect_collective_bias, 0.0)
			if descent_overspeed > 0.0:
				collective = maxf(
					collective,
					trim - maxf(landing_flare_collective_floor_margin, 0.0)
							+ descent_overspeed * maxf(landing_descent_overspeed_collective_gain, 0.0)
				)
	return clampf(collective, 0.0, 1.0)


func _calculate_transit_collective(base_collective: float, alt_error: float, horizontal_speed: float) -> float:
	var feedback_collective := clampf(base_collective, 0.0, 1.0)

	# Bank compensation: a banked rotor produces less vertical lift. Add collective to
	# compensate — without this a low-speed banked turn loses altitude and crashes.
	# cos(roll) of the aircraft's up vector vs world up gives the vertical thrust fraction.
	if is_instance_valid(aircraft):
		var up_dot := aircraft.global_transform.basis.y.dot(Vector3.UP)
		var vert_fraction := maxf(up_dot, 0.15)
		var bank_boost := _get_collective_trim() * (1.0 / vert_fraction - 1.0)
		feedback_collective = clampf(feedback_collective + bank_boost, 0.0, 1.0)

	# Altitude boost: smoothly blend toward 1.0 as altitude error grows.
	# No hard thresholds — the gain curve determines how aggressively altitude error increases collective.
	var alt_boost_t := clampf(alt_error / maxf(collective_full_climb_alt_error_m, 1.0), 0.0, 1.0)
	var alt_boosted := lerpf(feedback_collective, 1.0, alt_boost_t)

	# Speed management: if already at or above speed target, allow collective to settle back.
	var speed_target := maxf(_speed_target_mps, 0.0)
	var speed_excess := horizontal_speed - speed_target
	var speed_t := 0.0
	if speed_target > 0.0:
		speed_t = clampf(speed_excess / maxf(energy_management_speed_band_mps, 1.0), 0.0, 1.0)

	var minimum_collective := clampf(energy_management_min_collective, 0.0, 1.0)
	var speed_managed_collective := lerpf(alt_boosted, minimum_collective, speed_t)
	return clampf(maxf(speed_managed_collective, feedback_collective), minimum_collective, 1.0)


func _get_collective_trim() -> float:
	if helicopter_flight != null:
		var hover_variant: Variant = helicopter_flight.get("hover_collective")
		if hover_variant != null:
			return clampf(float(hover_variant), 0.0, 1.0)
	return clampf(collective_trim, 0.0, 1.0)


func _get_takeoff_collective_floor() -> float:
	var floor_value: float = maxf(clampf(takeoff_collective_min, 0.0, 1.0), _get_collective_trim())
	if aircraft == null or not bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false)):
		return floor_value
	if helicopter_flight != null:
		var release_variant: Variant = helicopter_flight.get("deck_takeoff_brake_release_collective")
		if release_variant != null:
			floor_value = maxf(floor_value, float(release_variant) + maxf(takeoff_deck_release_margin, 0.0))
	return clampf(floor_value, 0.0, 1.0)


func _get_landing_descent_limit_mps() -> float:
	if not is_instance_valid(aircraft):
		return max_descent_mps
	var surface_y := _get_landing_surface_y()
	if is_nan(surface_y):
		return max_descent_mps
	var height_above_surface: float = maxf(aircraft.global_position.y - surface_y, 0.0)
	var slow_height := maxf(landing_final_slowdown_agl_m, 0.1)
	var t := clampf(height_above_surface / slow_height, 0.0, 1.0)
	var near_ground_limit := maxf(landing_touchdown_descent_mps, 0.05)
	var upper_limit := maxf(landing_final_descent_mps, near_ground_limit)
	var limit := lerpf(near_ground_limit, upper_limit, t)
	if height_above_surface > slow_height:
		var blend_out := clampf((height_above_surface - slow_height) / maxf(landing_flare_agl_m, 0.1), 0.0, 1.0)
		limit = lerpf(limit, max_descent_mps, blend_out)
	return clampf(limit, near_ground_limit, max_descent_mps)


func _get_landing_surface_y() -> float:
	if not is_instance_valid(aircraft):
		return NAN
	if _landing_on_carrier:
		var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
		if carrier == null:
			return destination.y if _has_destination else NAN
		return _get_carrier_deck_y(carrier)
	return _get_ground_height_at_position(aircraft.global_position)


func _get_carrier_marker_world_pos(marker_name: String) -> Vector3:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return Vector3.INF
	var marker := carrier.find_child(marker_name, true, false) as Node3D
	if marker == null:
		if debug_enabled:
			print("HELI_AI marker_not_found name='%s' carrier=%s" % [marker_name, carrier.name])
		return Vector3.INF
	return marker.global_position


func _get_carrier_velocity_world() -> Vector3:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return Vector3.ZERO
	if carrier.has_method("get_deck_reference_velocity_vector"):
		return carrier.call("get_deck_reference_velocity_vector") as Vector3
	return _get_deck_reference_velocity()


# Returns true while it is handling the approach and has set _pitch_cmd/_roll_cmd/_yaw_cmd
# and called _apply_collective. Returns false if markers are missing and caller should fall back.
func _run_scripted_carrier_approach(delta: float) -> bool:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return false
	var approach_world := _get_carrier_marker_world_pos(carrier_approach_point_name)
	var landing_world := _get_carrier_marker_world_pos(carrier_landing_point_name)
	if approach_world == Vector3.INF or landing_world == Vector3.INF:
		return false

	var pos := aircraft.global_position
	var carrier_vel := _get_carrier_velocity_world()
	var carrier_speed := carrier_vel.length()
	var carrier_fwd := carrier_vel.normalized() if carrier_speed > 0.5 else -carrier.global_transform.basis.z

	# Phase transitions
	match _carrier_approach_phase:
		CarrierApproachPhase.NONE, CarrierApproachPhase.TO_APPROACH_POINT:
			_carrier_approach_phase = CarrierApproachPhase.TO_APPROACH_POINT
			var dist_to_gate := _flat_distance(pos, approach_world)
			var height_ok := absf(pos.y - approach_world.y) < 8.0
			if dist_to_gate < maxf(carrier_approach_gate_radius_m, 5.0) and height_ok:
				_carrier_approach_phase = CarrierApproachPhase.FINAL
				_debug_event("carrier_approach", "phase=FINAL gate_dist=%.1f" % dist_to_gate)
		CarrierApproachPhase.FINAL:
			# Transition to DESCEND once we are above or past the landing point
			var to_landing := landing_world - pos
			to_landing.y = 0.0
			var ahead_of_landing := to_landing.dot(carrier_fwd) < 15.0
			if ahead_of_landing and _flat_distance(pos, landing_world) < 30.0:
				_carrier_approach_phase = CarrierApproachPhase.DESCEND
				_debug_event("carrier_approach", "phase=DESCEND")
		CarrierApproachPhase.DESCEND:
			pass  # stays in DESCEND until _try_finish_landing fires

	# Per-phase flight control
	var target_altitude := approach_world.y  # approach point height = correct deck hover height
	var target_speed := carrier_speed
	var target_pos := approach_world

	match _carrier_approach_phase:
		CarrierApproachPhase.TO_APPROACH_POINT:
			target_pos = approach_world
			target_speed = cruise_speed_mps
			target_altitude = approach_world.y

		CarrierApproachPhase.FINAL:
			# Fly forward along carrier heading at carrier speed + offset, hold approach altitude
			target_pos = landing_world
			target_speed = carrier_speed + maxf(carrier_final_speed_offset_mps, 0.0)
			target_altitude = approach_world.y  # same height as approach gate throughout final

		CarrierApproachPhase.DESCEND:
			target_pos = landing_world
			target_speed = carrier_speed
			target_altitude = landing_world.y  # descend to landing point

	# Update destination so _try_finish_landing and other systems see the right point
	destination = landing_world
	_has_destination = true
	_desired_altitude_m = target_altitude

	var fly_target := Vector3(target_pos.x, target_altitude, target_pos.z)
	if _carrier_approach_phase == CarrierApproachPhase.TO_APPROACH_POINT:
		# Use transit flight path so the helicopter flies at full speed with proper
		# altitude control to reach the gate. The LANDING state hover path is too
		# slow and collective-weak to climb 30+ m to reach the approach point.
		_fly_transit_vector(fly_target, target_speed, delta)
	else:
		_fly_toward(fly_target, target_speed, delta)
	return true


func _get_carrier_landing_approach_altitude() -> float:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return NAN
	return _get_carrier_deck_y(carrier) + maxf(carrier_landing_hover_height_m, 0.0)


func _get_carrier_deck_y(carrier: Node3D = null) -> float:
	var carrier_node := carrier
	if carrier_node == null:
		carrier_node = get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier_node == null:
		return destination.y if _has_destination else NAN
	var fdm := get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm == null:
		fdm = carrier_node.find_child("FlightDeckManager", true, false)
	if fdm != null and fdm.has_method("get_deck_height"):
		return float(fdm.call("get_deck_height"))
	return carrier_node.global_position.y


func _apply_collective(value: float) -> void:
	var target := clampf(value, 0.0, 1.0)
	var rate := collective_rate_up if target >= _collective_cmd else collective_rate_down
	_collective_cmd = move_toward(_collective_cmd, target, rate * _physics_delta)
	if control_engine != null and control_engine.has_method("set_target_power"):
		control_engine.call("set_target_power", _collective_cmd)
		return
	if engine != null and engine.has_method("engine_set_power"):
		engine.call("engine_set_power", _collective_cmd)


func _set_landing_gear_deployed(deployed: bool) -> void:
	if not is_instance_valid(control_gear):
		return
	if "gear_down_state" in control_gear and bool(control_gear.get("gear_down_state")) == deployed:
		return
	var gear_method := "deploy" if deployed else "stow"
	if control_gear.has_method("send_to_landing_gears"):
		control_gear.call("send_to_landing_gears", gear_method)
	if control_gear.has_method("send_to_tailhooks"):
		control_gear.call("send_to_tailhooks", "stow")
	if control_gear.has_method("send_to_tailhook_simple"):
		control_gear.call("send_to_tailhook_simple", false)
	if control_gear.has_method("_set_collider_disabled"):
		control_gear.call("_set_collider_disabled", not deployed)
	if "gear_down_state" in control_gear:
		control_gear.set("gear_down_state", deployed)
	if "tailhook_down_state" in control_gear:
		control_gear.set("tailhook_down_state", false)


func _stop_rotors_after_landing() -> void:
	_collective_cmd = 0.0
	_set_helicopter_input(0.0, 0.0, 0.0)
	if is_instance_valid(control_engine) and control_engine.has_method("set_target_power"):
		control_engine.call("set_target_power", 0.0)
	if is_instance_valid(engine):
		if engine.has_method("engine_set_power"):
			engine.call("engine_set_power", 0.0)
		elif engine.has_method("engine_stop"):
			engine.call("engine_stop")


func _get_control_velocity() -> Vector3:
	if not is_instance_valid(aircraft):
		return Vector3.ZERO
	if _should_use_reference_velocity():
		return aircraft.linear_velocity - _get_deck_reference_velocity()
	return aircraft.linear_velocity


func _should_use_reference_velocity() -> bool:
	if not is_instance_valid(aircraft):
		return false
	if state == State.TAKEOFF and _takeoff_started_from_deck:
		return true
	if state == State.TAKEOFF and _is_deck_takeoff_context():
		return true
	if state == State.LANDING and _landing_on_carrier:
		return true
	if state == State.LANDING and _should_match_landing_carrier_velocity():
		return true
	if bool(aircraft.get_meta("carrier_transport_mode", false)):
		return true
	return false


func _should_match_landing_carrier_velocity() -> bool:
	if not _landing_on_carrier or not _is_aircraft_in_carrier_velocity_match_zone():
		return false
	if not _has_destination:
		return false
	return _flat_distance(aircraft.global_position, destination) <= maxf(carrier_velocity_match_landing_radius_m, 0.0)


func _is_aircraft_in_carrier_velocity_match_zone() -> bool:
	if not is_instance_valid(aircraft):
		return false
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return false
	var local_pos: Vector3 = carrier.to_local(aircraft.global_position)
	if absf(local_pos.x) > maxf(carrier_velocity_match_half_width_m, 0.0):
		return false
	if absf(local_pos.z) > maxf(carrier_velocity_match_half_length_m, 0.0):
		return false
	var deck_y := _get_carrier_deck_y(carrier)
	return absf(aircraft.global_position.y - deck_y) <= maxf(carrier_velocity_match_height_margin_m, 0.0)


func _get_deck_reference_velocity() -> Vector3:
	if not is_instance_valid(aircraft):
		return Vector3.ZERO
	if aircraft.has_meta("helicopter_deck_reference_node"):
		var reference_node = aircraft.get_meta("helicopter_deck_reference_node")
		if reference_node is Node and is_instance_valid(reference_node):
			return VelocityFrame.get_node_velocity(reference_node)
	var deck_velocity := VelocityFrame.get_reference_velocity(aircraft)
	if deck_velocity.length_squared() > 0.0001:
		return deck_velocity
	var carrier := get_tree().get_first_node_in_group("carrier")
	if carrier is Node:
		return VelocityFrame.get_node_velocity(carrier as Node)
	return Vector3.ZERO


func _set_helicopter_input(pitch: float, roll: float, yaw: float) -> void:
	if helicopter_flight == null:
		return
	helicopter_flight.set("pitch_input", clampf(pitch, -1.0, 1.0))
	helicopter_flight.set("roll_input", clampf(roll, -1.0, 1.0))
	helicopter_flight.set("yaw_input", clampf(yaw, -1.0, 1.0))


func _zero_flight_controls_now() -> void:
	_pitch_cmd = 0.0
	_roll_cmd = 0.0
	_yaw_cmd = 0.0
	_collective_cmd = 0.0
	_prev_fwd_speed = 0.0
	_prev_lat_speed = 0.0
	_prev_vertical_speed = 0.0
	_set_helicopter_input(0.0, 0.0, 0.0)
	if helicopter_flight == null:
		return
	helicopter_flight.set("current_disc_tilt", Vector2.ZERO)
	helicopter_flight.set("target_disc_tilt", Vector2.ZERO)
	helicopter_flight.set("current_yaw_input", 0.0)


func _prime_takeoff_reference() -> void:
	if not is_instance_valid(aircraft):
		return
	_takeoff_start_altitude_m = aircraft.global_position.y
	_takeoff_started_from_deck = _is_deck_takeoff_context()


func _is_deck_takeoff_context() -> bool:
	if not is_instance_valid(aircraft):
		return false
	if bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false)):
		return true
	return aircraft.has_meta("helicopter_deck_reference_node") and bool(aircraft.get_meta("parking_brake", false))


func _refresh_takeoff_deck_context() -> void:
	if _takeoff_started_from_deck or not _is_deck_takeoff_context():
		return
	_takeoff_start_altitude_m = aircraft.global_position.y
	_takeoff_started_from_deck = true


func _should_hold_vertical_takeoff() -> bool:
	if not _takeoff_started_from_deck or not is_instance_valid(aircraft):
		return false
	if bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false)):
		return true
	if is_nan(_takeoff_start_altitude_m):
		return false
	return aircraft.global_position.y < _takeoff_start_altitude_m + maxf(takeoff_vertical_hold_m, 0.0)


func _takeoff_is_clear() -> bool:
	if not is_instance_valid(aircraft):
		return false
	if bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false)):
		return false
	var altitude_target: float = _desired_altitude_m - 4.0
	if _takeoff_started_from_deck and not is_nan(_takeoff_start_altitude_m):
		var deck_clear_m: float = maxf(maxf(takeoff_agl_m, deck_takeoff_climb_m) - 4.0, 4.0)
		altitude_target = maxf(altitude_target, _takeoff_start_altitude_m + deck_clear_m)
	return aircraft.global_position.y >= altitude_target \
			and aircraft.linear_velocity.y <= maxf(takeoff_clear_max_climb_mps, 0.0)


func _get_takeoff_speed_limit() -> float:
	if not _takeoff_started_from_deck or is_nan(_takeoff_start_altitude_m):
		return cruise_speed_mps * 0.35
	if _should_hold_vertical_takeoff():
		return 0.0
	var climb_m: float = maxf(aircraft.global_position.y - _takeoff_start_altitude_m, 0.0)
	var hold_m: float = maxf(takeoff_vertical_hold_m, 0.0)
	var transition_band_m: float = maxf(deck_takeoff_climb_m - hold_m, 1.0)
	var transition_t: float = clampf((climb_m - hold_m) / transition_band_m, 0.0, 1.0)
	return lerpf(hover_speed_mps, takeoff_transition_speed_mps, transition_t)


func _try_finish_landing() -> void:
	var is_landed: bool = false

	if _landing_on_carrier:
		var carrier := get_tree().get_first_node_in_group("carrier")
		if not (carrier is Node3D):
			return
		var flat_dist: float = _flat_distance(aircraft.global_position, destination) if _has_destination else INF
		var carrier_rel_speed: float = (aircraft.linear_velocity - _get_deck_reference_velocity()).length()
		var deck_y := _get_landing_surface_y()
		var deck_agl := aircraft.global_position.y - deck_y if not is_nan(deck_y) else INF
		var touchdown_radius: float = minf(
			maxf(carrier_landing_touchdown_radius_m, 0.5),
			maxf(carrier_landing_descent_start_radius_m, 0.5)
		)
		is_landed = flat_dist <= touchdown_radius \
				and carrier_rel_speed < maxf(carrier_landing_touchdown_relative_speed_mps, 0.1) \
				and deck_agl >= carrier_landing_touchdown_min_deck_agl_m \
				and deck_agl <= 2.0
	else:
		var ground_height: float = _get_ground_height_at_position(aircraft.global_position)
		if is_nan(ground_height):
			return
		var flat_dist: float = _flat_distance(aircraft.global_position, destination) if _has_destination else INF
		var agl: float = aircraft.global_position.y - ground_height
		var close_to_lz: bool = flat_dist <= maxf(terrain_landing_touchdown_radius_m, 0.5)
		var soft_touchdown: bool = close_to_lz and agl <= 2.0 and aircraft.linear_velocity.length() < 3.0
		# grounded_touchdown does not require close_to_lz: LANDING starts at 120 m so the
		# helicopter may touch down anywhere in a wide area. Gear compression + low speed
		# is sufficient evidence of a real landing regardless of exact LZ offset.
		var grounded_touchdown: bool = \
				agl <= maxf(terrain_landing_ground_contact_agl_m, 0.1) \
				and aircraft.linear_velocity.length() <= maxf(terrain_landing_ground_contact_speed_mps, 0.1) \
				and _get_grounded_gear_count() >= maxi(terrain_landing_ground_contact_min_wheels, 1)
		is_landed = soft_touchdown or grounded_touchdown

	if not is_landed:
		return

	if not _landing_on_carrier:
		# Clear all carrier velocity state so HelicopterFlight doesn't snap us to deck velocity.
		# VelocityFrame leaves motion_reference_node/velocity on the aircraft after carrier takeoff
		# and never clears them — anything reading those would match carrier speed on terrain.
		VelocityFrame.clear_reference(aircraft)
		for meta_name: String in ["helicopter_deck_takeoff_ready", "helicopter_deck_reference_node",
				"carrier_transport_mode"]:
			if aircraft.has_meta(meta_name):
				aircraft.remove_meta(meta_name)
		_hold_landed_on_terrain(0.0, true)

	_landing_on_carrier = false
	_carrier_approach_phase = CarrierApproachPhase.NONE
	_stop_rotors_after_landing()
	match mission_phase:
		MissionPhase.OUTBOUND:
			mission_phase = MissionPhase.AT_LZ
			_idle_dwell_timer_s = lz_dwell_time_s
			_record_milestone("Landed at LZ — pos=%s" % [str(aircraft.global_position.snapped(Vector3.ONE)) if is_instance_valid(aircraft) else "?"])
		MissionPhase.INBOUND:
			mission_phase = MissionPhase.AT_CARRIER
			_idle_dwell_timer_s = carrier_dwell_time_s
			_record_milestone("Landed back at carrier")
			_hold_landed_on_carrier()
	change_state(State.IDLE)


func _hold_landed_on_carrier() -> void:
	if not is_instance_valid(aircraft):
		return
	_zero_flight_controls_now()
	var deck_velocity: Vector3 = _get_deck_reference_velocity()
	aircraft.linear_velocity = deck_velocity
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.set_meta("parking_brake", true)
	aircraft.set_meta("carrier_transport_mode", true)
	# Clear takeoff_ready so _is_helicopter_ready_for_deck_recovery passes.
	if aircraft.has_meta("helicopter_deck_takeoff_ready"):
		aircraft.remove_meta("helicopter_deck_takeoff_ready")
	aircraft.freeze = true
	aircraft.sleeping = false


func _hold_landed_on_terrain(delta: float, force_freeze: bool = false) -> void:
	if not is_instance_valid(aircraft):
		return
	VelocityFrame.clear_reference(aircraft)
	for meta_name: String in ["helicopter_deck_takeoff_ready", "helicopter_deck_reference_node", "carrier_transport_mode"]:
		if aircraft.has_meta(meta_name):
			aircraft.remove_meta(meta_name)
	aircraft.set_meta("parking_brake", true)
	_zero_flight_controls_now()

	var ground_height: float = _get_ground_height_at_position(aircraft.global_position)
	if is_nan(ground_height):
		return
	var agl: float = aircraft.global_position.y - ground_height
	if agl > 4.0:
		return

	if aircraft.freeze:
		_zero_flight_controls_now()
		aircraft.linear_velocity = Vector3.ZERO
		aircraft.angular_velocity = Vector3.ZERO
		aircraft.sleeping = false
		return

	var vel := aircraft.linear_velocity
	var planar := Vector3(vel.x, 0.0, vel.z)
	planar = planar.move_toward(Vector3.ZERO, maxf(landed_ground_planar_brake_mps2, 0.0) * delta)
	if planar.length() <= maxf(landed_ground_snap_speed_mps, 0.0):
		planar = Vector3.ZERO
	vel.x = planar.x
	vel.z = planar.z
	aircraft.linear_velocity = vel
	aircraft.angular_velocity = aircraft.angular_velocity.move_toward(
		Vector3.ZERO,
		maxf(landed_ground_angular_brake_radps2, 0.0) * delta
	)
	var freeze_speed: float = maxf(landed_ground_freeze_speed_mps, landed_ground_snap_speed_mps)
	if force_freeze or (agl <= maxf(landed_ground_freeze_agl_m, 0.1) and aircraft.linear_velocity.length() <= freeze_speed):
		_zero_flight_controls_now()
		aircraft.linear_velocity = Vector3.ZERO
		aircraft.angular_velocity = Vector3.ZERO
		aircraft.freeze = true
		aircraft.sleeping = false


func _get_grounded_gear_count() -> int:
	if control_gear == null:
		return 0
	var compressions_variant: Variant = control_gear.get("gear_compressions")
	if not (compressions_variant is Array):
		return 0
	var compressions: Array = compressions_variant as Array
	var grounded_count: int = 0
	var threshold: float = maxf(terrain_landing_ground_contact_compression_m, 0.0)
	for value: Variant in compressions:
		if float(value) >= threshold:
			grounded_count += 1
	return grounded_count


func _get_ground_height_at_position(world_pos: Vector3) -> float:
	var nav_grid: Node = get_node_or_null("/root/TerrainNavGrid")
	if nav_grid != null and nav_grid.has_method("sample_query_height"):
		var query_h_variant: Variant = nav_grid.call("sample_query_height", world_pos.x, world_pos.z)
		var query_h: float = float(query_h_variant)
		if query_h > -500000.0:
			return query_h
	if nav_grid != null and nav_grid.has_method("sample_height"):
		var grid_h_variant: Variant = nav_grid.call("sample_height", world_pos.x, world_pos.z)
		var grid_h: float = float(grid_h_variant)
		if grid_h > -500000.0:
			return grid_h

	var terrain: Node = TerrainReference.get_terrain_node()
	if terrain != null and is_instance_valid(terrain):
		if terrain.has_method("get_height"):
			var h_variant: Variant = terrain.call("get_height", world_pos)
			return float(h_variant)
		if "data" in terrain:
			var data_variant: Variant = terrain.get("data")
			if data_variant is Object:
				var data_object: Object = data_variant as Object
				if data_object.has_method("get_height"):
					var data_h_variant: Variant = data_object.call("get_height", world_pos)
					return float(data_h_variant)

	var space_state: PhysicsDirectSpaceState3D = aircraft.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		world_pos + Vector3.UP * 2000.0,
		world_pos + Vector3.DOWN * 6000.0
	)
	query.exclude = [aircraft.get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.has("position"):
		return result["position"].y
	return NAN


func _sample_max_terrain_height_along_path(from_pos: Vector3, to_pos: Vector3) -> float:
	var distance: float = _flat_distance(from_pos, to_pos)
	var sample_count: int = maxi(int(ceil(distance / maxf(terrain_sample_spacing_m, 1.0))), 1)
	var max_height: float = -INF
	var found_height: bool = false
	for i in range(sample_count + 1):
		var t: float = float(i) / float(sample_count)
		var sample_pos: Vector3 = from_pos.lerp(to_pos, t)
		var h: float = _get_ground_height_at_position(sample_pos)
		if is_nan(h):
			continue
		max_height = maxf(max_height, h)
		found_height = true
	return max_height if found_height else NAN


func _sample_max_terrain_edge_risk_along_path(from_pos: Vector3, to_pos: Vector3) -> float:
	var nav_grid: Node = get_node_or_null("/root/TerrainNavGrid")
	if nav_grid == null or not nav_grid.has_method("sample_query_edge_risk"):
		return 0.0
	var distance: float = _flat_distance(from_pos, to_pos)
	var sample_count: int = maxi(int(ceil(distance / maxf(terrain_sample_spacing_m, 1.0))), 1)
	var max_risk: float = 0.0
	for i in range(sample_count + 1):
		var t: float = float(i) / float(sample_count)
		var sample_pos: Vector3 = from_pos.lerp(to_pos, t)
		var risk := float(nav_grid.call("sample_query_edge_risk", sample_pos.x, sample_pos.z))
		if risk >= INF:
			return INF
		max_risk = maxf(max_risk, risk)
	return max_risk


func _sample_terrain_edge_risk_at(world_pos: Vector3) -> float:
	var nav_grid: Node = get_node_or_null("/root/TerrainNavGrid")
	if nav_grid == null or not nav_grid.has_method("sample_query_edge_risk"):
		return 0.0
	var risk := float(nav_grid.call("sample_query_edge_risk", world_pos.x, world_pos.z))
	return risk if risk < INF else INF


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _debug_event(event_name: String, details: String = "") -> void:
	if not debug_enabled or not debug_lifecycle_events:
		return
	var craft_name: String = aircraft.name if is_instance_valid(aircraft) else "?"
	var line: String = "HELI_AI event=%s craft=%s state=%s phase=%s" % [
		event_name,
		craft_name,
		_state_name(),
		_mission_name(),
	]
	if not details.is_empty():
		line += " " + details
	_debug_output(line)


func _debug_output(line: String) -> void:
	_last_debug_line = line
	if debug_log_as_error:
		push_error(line)
	elif debug_log_as_warning:
		push_warning(line)
	else:
		print(line)
	if crash_log_enabled:
		var now := Time.get_ticks_msec() / 1000.0
		_flight_log.append([now, line])
		# Trim entries older than the history window
		var cutoff := now - maxf(crash_log_history_s, 1.0)
		while not _flight_log.is_empty() and _flight_log[0][0] < cutoff:
			_flight_log.pop_front()


func _setup_debug_overlay() -> void:
	if not debug_overlay_enabled or _debug_canvas != null:
		return
	_debug_canvas = CanvasLayer.new()
	_debug_canvas.name = "HelicopterAIDebugOverlay"
	_debug_canvas.layer = 128
	add_child(_debug_canvas)

	_debug_label = Label.new()
	_debug_label.name = "Readout"
	_debug_label.position = Vector2(18.0, 410.0)
	_debug_label.size = Vector2(760.0, 260.0)
	_debug_label.add_theme_font_size_override("font_size", 15)
	_debug_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45, 0.96))
	_debug_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_debug_label.add_theme_constant_override("outline_size", 2)
	_debug_label.text = "HELI_AI DEBUG\nloaded, waiting for AI initialize"
	_debug_canvas.add_child(_debug_label)


func _should_show_debug_overlay() -> bool:
	if not debug_overlay_enabled:
		return false
	if not debug_overlay_only_when_viewed:
		return true
	if not is_instance_valid(aircraft):
		return true
	if typeof(FlightDirector) == TYPE_NIL:
		return true
	if FlightDirector.current_viewed_aircraft == aircraft:
		return true
	if FlightDirector.player_controlled_plane == aircraft:
		return true
	return false


func _update_debug_overlay(
		agl: float,
		ground_height: float,
		abs_speed: float,
		rel_speed: float,
		deck_ref_speed: float,
		dist_to_dest: float,
		carrier_dist: float,
		landing_surface_y: float,
		ref_match: bool,
		match_zone: bool,
		landing_match: bool
) -> void:
	if not debug_overlay_enabled:
		return
	if _debug_canvas == null or _debug_label == null:
		_setup_debug_overlay()
		if _debug_canvas == null or _debug_label == null:
			return
	_debug_canvas.visible = _should_show_debug_overlay()
	if not _debug_canvas.visible:
		return
	_debug_label.text = "\n".join([
		"HELI_AI DEBUG",
		"%s  %s / %s" % [aircraft.name if is_instance_valid(aircraft) else "?", _state_name(), _mission_name()],
		"pos       %s" % [str(aircraft.global_position.snapped(Vector3.ONE * 0.1)) if is_instance_valid(aircraft) else "?"],
		"dest      %s" % [str(destination.snapped(Vector3.ONE * 0.1))],
		"wp        %s" % [str(_nav_waypoint.snapped(Vector3.ONE * 0.1))],
		"agl       %6.1f   ground %6.1f   landing_y %6.1f" % [agl, ground_height, landing_surface_y],
		"speed     %6.1f   rel %6.1f   deck_ref %6.1f" % [abs_speed, rel_speed, deck_ref_speed],
		"dist      %6.1f   carrier %6.1f" % [dist_to_dest, carrier_dist],
		"match     ref=%s zone=%s landing=%s" % [str(ref_match), str(match_zone), str(landing_match)],
		"controls  coll %.2f  pitch %.2f  roll %.2f  yaw %.2f" % [_collective_cmd, _pitch_cmd, _roll_cmd, _yaw_cmd],
		"flags     brake=%s frozen=%s" % [
			str(bool(aircraft.get_meta("parking_brake", false))) if is_instance_valid(aircraft) else "?",
			str(aircraft.freeze) if is_instance_valid(aircraft) else "?",
		],
	])


func _emit_debug(delta: float) -> void:
	if not debug_enabled:
		return
	_debug_timer_s -= delta
	if _debug_timer_s > 0.0:
		return
	_debug_timer_s = maxf(debug_interval_s, 0.1)

	var ground_height: float = _get_ground_height_at_position(aircraft.global_position)
	var agl: float = aircraft.global_position.y - ground_height if not is_nan(ground_height) else NAN
	var abs_speed: float = aircraft.linear_velocity.length()
	var dist_to_dest: float = _flat_distance(aircraft.global_position, destination) if _has_destination else NAN

	var debug_line := "HELI_AI craft=%s %s/%s pos=%s agl=%.1f tgt=%.1f onc=%s spd=%.1f vs=%.1f/%+.1f col=%.2f/%.2f lean=%.2f pa=%.2f st=%.2f tr=%.2f ctl=(%.2f,%.2f,%.2f) dist=%.0f" % [
			aircraft.name,
			_state_name(),
			_mission_name(),
			str(aircraft.global_position.snapped(Vector3.ONE)),
			agl,
			_desired_altitude_m,
			str(_landing_on_carrier),
			abs_speed,
			aircraft.linear_velocity.y,
			_debug_vertical_rate_error_mps,
			_collective_cmd,
			_debug_collective_target,
			_debug_forward_error_mps,
			_debug_altitude_pitch,
			_debug_sharp_turn,
			_debug_terrain_recovery,
			_pitch_cmd,
			_roll_cmd,
			_yaw_cmd,
			dist_to_dest,
		]
	_debug_output(debug_line)

	if debug_overlay_enabled:
		var control_vel := _get_control_velocity()
		var carrier_dist: float = NAN
		var carrier := get_tree().get_first_node_in_group("carrier")
		if carrier is Node3D:
			carrier_dist = _flat_distance(aircraft.global_position, (carrier as Node3D).global_position)
		var deck_ref_vel := _get_deck_reference_velocity()
		var ref_match := _should_use_reference_velocity()
		var match_zone := _is_aircraft_in_carrier_velocity_match_zone()
		var landing_match := _should_match_landing_carrier_velocity()
		_update_debug_overlay(
			agl, ground_height, abs_speed, control_vel.length(),
			deck_ref_vel.length(), dist_to_dest, carrier_dist,
			_get_landing_surface_y(), ref_match, match_zone, landing_match
		)

func _state_name() -> String:
	return _state_name_for(state)


func _state_name_for(value: State) -> String:
	match value:
		State.IDLE: return "IDLE"
		State.TAKEOFF: return "TAKEOFF"
		State.LOW_LEVEL_TRANSIT: return "LOW_LEVEL_TRANSIT"
		State.HOVER: return "HOVER"
		State.LANDING: return "LANDING"
	return "UNKNOWN"


func _mission_name() -> String:
	match mission_phase:
		MissionPhase.OUTBOUND: return "OUTBOUND"
		MissionPhase.AT_LZ: return "AT_LZ"
		MissionPhase.INBOUND: return "INBOUND"
		MissionPhase.AT_CARRIER: return "AT_CARRIER"
	return "UNKNOWN"


func _elapsed_s() -> float:
	return Time.get_ticks_msec() / 1000.0 - _flight_start_time_s


func _record_milestone(text: String) -> void:
	if not crash_log_enabled:
		return
	_milestone_log.append("  [+%.1fs]  %s" % [_elapsed_s(), text])


func _on_aircraft_destroyed_flight_recorder() -> void:
	if not crash_log_enabled:
		return
	var craft_name: String = aircraft.name if is_instance_valid(aircraft) else "unknown"
	var pos_str: String = str(aircraft.global_position.snapped(Vector3.ONE)) if is_instance_valid(aircraft) else "?"
	var ground_h: float = _get_ground_height_at_position(aircraft.global_position) if is_instance_valid(aircraft) else NAN
	var agl_str: String = "%.1fm" % [aircraft.global_position.y - ground_h] if is_instance_valid(aircraft) and not is_nan(ground_h) else "?"

	var lines: PackedStringArray = PackedStringArray()
	lines.append("=" .repeat(72))
	lines.append("CRASH REPORT — %s" % craft_name)
	lines.append("Time since AI start: +%.1fs" % [_elapsed_s()])
	lines.append("Last known position: %s  AGL: %s" % [pos_str, agl_str])
	lines.append("State: %s / %s" % [_state_name(), _mission_name()])
	lines.append("")
	lines.append("--- Flight milestones ---")
	if _milestone_log.is_empty():
		lines.append("  (none)")
	else:
		for m in _milestone_log:
			lines.append(m)
	lines.append("")
	lines.append("--- Last %.0f s of debug output ---" % [maxf(crash_log_history_s, 1.0)])
	if _flight_log.is_empty():
		lines.append("  (no debug lines captured)")
	else:
		var t0: float = _flight_log[0][0]
		for entry in _flight_log:
			lines.append("  [+%.2fs]  %s" % [entry[0] - t0, entry[1]])
	lines.append("")
	lines.append("*** CRASH ***")
	lines.append("=" .repeat(72))
	lines.append("")

	var path: String = "user://heli_crash_report_%s.log" % craft_name.replace(" ", "_")
	var file := FileAccess.open(path, FileAccess.WRITE_READ if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		push_warning("[HelicopterPilot] Could not open crash log: %s" % path)
		return
	file.seek_end()
	for line in lines:
		file.store_line(line)
	file.close()
	print("[HelicopterPilot] Crash log written to: %s" % path)
