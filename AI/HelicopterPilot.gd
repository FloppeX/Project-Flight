extends Node
class_name HelicopterPilot

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")
const AttackPlannerScript = preload("res://AI/AttackPlanner.gd")
const COMBAT_WEAPON_ROCKET := "rocket"
const COMBAT_WEAPON_GUN := "gun"
const COMBAT_WEAPON_BOMB := "bomb"
const COMBAT_REPORT_RESET_META := "heli_combat_report_reset_done"

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
	RESCUE,      # flying to pick up a downed pilot
}

@export_group("References")
@export var helicopter_flight_path: NodePath
@export var control_engine_path: NodePath
@export var target_node_path: NodePath

@export_group("Mission")
@export var lz_distance_min_m: float = 4000.0
@export var lz_distance_max_m: float = 7000.0
@export var lz_candidate_attempts: int = 80
@export var lz_route_candidate_limit: int = 0
@export var lz_flat_radius_m: float = 18.0
@export var lz_max_center_drop_m: float = 1.5
@export var lz_max_height_variation_m: float = 2.5
@export var lz_obstacle_clear_radius_m: float = 22.0
@export var lz_obstacle_probe_height_m: float = 18.0
@export var lz_dwell_time_s: float = 12.0
@export var carrier_dwell_time_s: float = 20.0
@export var carrier_approach_radius_m: float = 80.0
@export var carrier_approach_point_name: String = "Helicopter Approach Point 1"
@export var carrier_approach_point_2_name: String = "Helicopter Approach Point 2"
@export var carrier_landing_point_name: String = "Helicopter Landing Point"
@export var carrier_approach_gate_radius_m: float = 120.0
@export var carrier_approach_capture_radius_m: float = 28.0
@export var carrier_approach_cleared_capture_radius_m: float = 45.0
@export var carrier_approach_capture_height_m: float = 20.0
@export var carrier_approach_capture_relative_speed_mps: float = 4.0
@export var carrier_approach_capture_heading_deg: float = 12.0
@export var carrier_approach_cleared_relative_speed_mps: float = 8.0
@export var carrier_approach_cleared_forced_final_relative_speed_mps: float = 10.0
@export var carrier_approach_cleared_heading_deg: float = 25.0
@export var carrier_approach_wait_log_interval_s: float = 2.0
@export var carrier_approach_clearance_request_radius_m: float = 140.0
@export var carrier_approach_clearance_request_interval_s: float = 1.0
@export var carrier_approach_capture_decel_mps2: float = 5.0
@export var carrier_approach_capture_min_closure_mps: float = 4.0
@export var carrier_approach_arrival_relative_speed_mps: float = 2.0
@export var carrier_approach_capture_lateral_gain: float = 0.08
@export var carrier_approach_capture_along_gain: float = 0.08
@export var carrier_approach_capture_max_lateral_mps: float = 18.0
@export var carrier_approach_heading_align_distance_m: float = 700.0
@export var carrier_approach_gate_prediction_s: float = 2.5
@export var carrier_approach_arrival_decel_mps2: float = 4.0
@export var carrier_approach_speed_match_distance_m: float = 1200.0
@export var carrier_approach_brake_distance_margin: float = 1.2
@export var carrier_approach_speed_log_interval_s: float = 2.0
@export var carrier_approach_fallback_height_m: float = 15.0
@export var carrier_approach_fallback_behind_m: float = 100.0
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
@export var carrier_landing_descent_start_radius_m: float = 70.0
@export var carrier_landing_descent_start_ahead_m: float = 95.0
@export var carrier_landing_descent_start_lateral_m: float = 24.0
@export var carrier_landing_position_speed_gain: float = 0.35
@export var carrier_landing_descent_correction_speed_mps: float = 4.0
@export var carrier_landing_touchdown_correction_speed_mps: float = 1.2
@export var carrier_landing_descend_relative_speed_mps: float = 6.0
@export var carrier_landing_min_sink_mps: float = 0.9
@export var carrier_landing_touchdown_sink_mps: float = 0.45
@export var carrier_landing_soft_touchdown_sink_mps: float = 0.18
@export var carrier_landing_touchdown_max_vertical_mps: float = 0.55
@export var carrier_landing_touchdown_settle_time_s: float = 0.35
@export var carrier_landing_ground_effect_collective_cap: float = 0.62
@export var carrier_landing_final_timeout_s: float = 30.0
@export var carrier_landing_touchdown_relative_speed_mps: float = 1.0
@export var carrier_landing_touchdown_min_deck_agl_m: float = -0.25
@export var carrier_landing_touchdown_max_deck_agl_m: float = 1.5
@export var carrier_landing_abort_below_deck_m: float = 1.0
@export var carrier_landing_abort_forward_m: float = 120.0
@export var carrier_landing_abort_lateral_m: float = 80.0
@export var carrier_landing_abort_distance_m: float = 180.0
@export var carrier_goal_repath_threshold_m: float = 500.0
@export var carrier_inbound_no_progress_timeout_s: float = 7.0
@export var carrier_inbound_progress_min_m: float = 40.0
@export var carrier_inbound_direct_recovery_s: float = 8.0
@export var terrain_landing_approach_radius_m: float = 120.0
@export var terrain_landing_descent_radius_m: float = 35.0
@export var terrain_landing_touchdown_radius_m: float = 40.0
@export var landed_ground_planar_brake_mps2: float = 18.0
@export var landed_ground_angular_brake_radps2: float = 4.0
@export var landed_ground_snap_speed_mps: float = 0.12
@export var landed_ground_freeze_agl_m: float = 2.5
@export var landed_ground_freeze_speed_mps: float = 0.5
@export var terrain_landing_ground_contact_agl_m: float = 1.2
@export var terrain_landing_ground_contact_speed_mps: float = 2.0
@export var terrain_landing_ground_contact_compression_m: float = 0.025
@export var terrain_landing_ground_contact_min_wheels: int = 2
@export var terrain_landing_settled_agl_m: float = 6.0
@export var terrain_landing_settled_speed_mps: float = 3.0
@export var terrain_landing_settled_vertical_mps: float = 1.0
@export var terrain_landing_settled_time_s: float = 1.5

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
@export var terrain_down_feeler_radius_m: float = 18.0
@export var terrain_down_feeler_extra_clearance_m: float = 8.0
@export var use_heightmap_pathfinding: bool = true
@export var heightmap_path_recompute_s: float = 60.0
@export var heightmap_path_async_enabled: bool = true
@export var heightmap_path_async_iterations_per_frame: int = 4000
@export var heightmap_path_postprocess_steps_per_frame: int = 8
@export var heightmap_path_target_agl_m: float = 50.0
@export var heightmap_path_insert_spacing_m: float = 100.0
@export var heightmap_path_simplify_enabled: bool = true
@export var heightmap_path_simplify_turn_deg: float = 10.0
@export var heightmap_path_simplify_altitude_error_m: float = 8.0
@export var heightmap_path_simplify_steps_per_frame: int = 3
@export var heightmap_path_descent_rate_mps: float = 15.0
@export var heightmap_path_descent_margin_m: float = 8.0
@export var heightmap_path_advance_radius_m: float = 60.0
@export var heightmap_path_carrot_distance_m: float = 520.0
@export var heightmap_path_corner_blend_radius_m: float = 340.0
@export var heightmap_path_corner_blend_strength: float = 0.65
@export var heightmap_path_goal_move_recompute_m: float = 900.0
@export var destination_path_reset_threshold_m: float = 120.0
@export var heightmap_path_search_padding_m: float = 600.0
@export var heightmap_path_max_terrain_above_reference_m: float = 2000.0
@export var heightmap_path_max_flight_above_reference_m: float = 2100.0
@export var heightmap_path_carrier_deck_ground_offset_m: float = 50.0
@export var heightmap_path_ground_level_band_m: float = 35.0
@export var heightmap_path_first_plateau_min_m: float = 40.0
@export var heightmap_path_first_plateau_max_m: float = 180.0
@export var heightmap_path_ground_route_penalty: float = 0.0
@export var heightmap_path_low_route_penalty: float = 0.0
@export var heightmap_path_top_level_penalty: float = 0.1
@export var heightmap_path_upper_level_penalty: float = 15.0

@export var heightmap_path_level_change_penalty: float = 2.0
@export var heightmap_path_mountain_avoidance_m: float = 185.0
@export var heightmap_path_max_step_climb_m: float = 0.0
@export var heightmap_path_mountain_buffer_cells: int = 0

@export var heightmap_path_max_edge_risk_m: float = 5.0
@export var heightmap_path_edge_risk_clearance_m: float = 45.0
@export var heightmap_path_edge_risk_penalty: float = 50.0
@export var heightmap_path_same_level_wall_risk_start_m: float = 8.0
@export var heightmap_path_same_level_wall_penalty: float = 50.0
@export var heightmap_path_altitude_penalty: float = 0.05
@export var heightmap_path_climb_penalty: float = 1.5
@export var heightmap_path_high_terrain_penalty: float = 0.0
@export var path_fail_escape_time_s: float = 10.0
@export var path_fail_escape_speed_mps: float = 22.0
@export var path_fail_escape_forward_lean: float = 0.08
@export var path_fail_escape_climb_margin_m: float = 95.0
@export var path_fail_escape_repath_s: float = 2.0
@export var terrain_climb_lookahead_m: float = 1300.0
@export var terrain_climb_arrival_margin_s: float = 5.0
@export var terrain_climb_capacity_scale: float = 0.5
@export var terrain_climb_speed_floor_mps: float = 18.0
@export var terrain_climb_speed_log_interval_s: float = 2.0
@export var path_turn_speed_enabled: bool = true
@export var path_turn_speed_lookahead_m: float = 900.0
@export var path_turn_speed_min_angle_deg: float = 25.0
@export var path_turn_speed_full_angle_deg: float = 110.0
@export var path_turn_lateral_accel_mps2: float = 3.5
@export var path_turn_radius_fraction: float = 0.65
@export var path_turn_min_radius_m: float = 90.0
@export var path_turn_speed_floor_mps: float = 20.0
@export var path_turn_speed_log_interval_s: float = 2.0
@export var terrain_navgrid_path_slope_m: float = 12.0
@export var terrain_lookahead_m: float = 260.0
@export var terrain_sample_spacing_m: float = 120.0
@export var corridor_angle_deg: float = 35.0
@export var waypoint_accept_radius_m: float = 35.0
@export var replan_interval_s: float = 0.35

@export_group("Airborne Separation")
@export var airborne_safe_distance_m: float = 40.0
@export var airborne_separation_start_m: float = 90.0
@export var airborne_separation_vertical_m: float = 35.0
@export var airborne_separation_lookahead_s: float = 3.0
@export var airborne_separation_max_speed_mps: float = 12.0
@export var airborne_separation_brake_start_m: float = 120.0
@export var airborne_separation_min_speed_mps: float = 8.0
@export var airborne_separation_push_start_m: float = 90.0
@export var airborne_separation_push_extra_mps: float = 18.0
@export var airborne_separation_push_max_speed_mps: float = 45.0
@export var airborne_separation_debug_interval_s: float = 1.5

@export_group("Flight")
@export var cruise_speed_mps: float = 150.0
@export var max_speed_mps: float = 150.0
@export var hover_speed_mps: float = 4.0
@export var max_climb_mps: float = 7.0
@export var max_descent_mps: float = 4.0
@export var collective_trim: float = 0.58
@export var altitude_to_climb_gain: float = 0.45
@export var collective_climb_gain: float = 0.08
@export var collective_speed_lift_bias: float = 0.08
@export var collective_rate_up: float = 0.85
@export var collective_rate_down: float = 0.25
@export var collective_full_climb_alt_error_m: float = 20.0
@export var collective_climb_urgency_alt_error_m: float = 18.0
@export var collective_climb_urgency_sink_mps: float = 1.0
@export var collective_climb_urgency_min: float = 0.78
@export var collective_climb_urgency_full_mps: float = 5.0
@export var transit_collective_min: float = 1.0
@export var energy_management_min_collective: float = 0.35
@export var transit_target_sink_mps: float = 5.0
@export var energy_management_speed_band_mps: float = 18.0
@export var energy_management_altitude_band_m: float = 35.0
@export var landing_flare_agl_m: float = 8.0
@export var landing_final_slowdown_agl_m: float = 5.0
@export var landing_final_descent_mps: float = 0.65
@export var landing_touchdown_descent_mps: float = 0.15
@export var landing_flare_collective_floor_margin: float = 0.02
@export var landing_descent_overspeed_collective_gain: float = 0.08
@export var landing_settle_collective_gain: float = 0.10
@export var landing_ground_effect_collective_bias: float = 0.15
@export var landing_final_horizontal_hold_radius_m: float = 14.0
@export var landing_final_horizontal_hold_agl_m: float = 18.0
@export var landing_final_position_gain: float = 0.006
@export var landing_final_velocity_gain: float = 0.22
@export var landing_final_accel_damping_gain: float = 0.012
@export var takeoff_collective_min: float = 0.82
@export var takeoff_deck_release_margin: float = 0.06
@export var deck_takeoff_climb_m: float = 30.0
@export var takeoff_vertical_hold_m: float = 8.0
@export var takeoff_transition_speed_mps: float = 24.0
@export var takeoff_clear_max_climb_mps: float = 3.5

@export_group("Controls")
@export var max_cyclic_input: float = 1.0
@export var max_yaw_input: float = 0.85
@export var cyclic_rate: float = 0.65
@export var transit_max_nose_up: float = 0.05
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
@export var cyclic_target_sink_mps: float = 4.0
@export var cyclic_vertical_priority_rate_mps: float = 6.0
@export var takeoff_min_climb_until_clear_mps: float = 3.0
@export var cyclic_altitude_trade_min_speed_mps: float = 12.0
@export var cyclic_altitude_trade_full_speed_mps: float = 35.0
@export var altitude_guard_m: float = 5.0
@export var sink_guard_mps: float = 1.5
@export var coordinated_turn_gain: float = 0.08
@export var horizontal_guidance_deadzone_m: float = 12.0
@export var decel_distance_m: float = 1000.0
@export var transit_speed_target_accel_mps2: float = 18.0
@export var transit_speed_target_decel_mps2: float = 18.0
@export var yaw_gain: float = 0.08
@export var yaw_rate_damping: float = 0.65
@export var yaw_command_rate: float = 0.30
@export var full_yaw_below_speed_mps: float = 8.0
@export var full_yaw_above_speed_mps: float = 18.0
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
@export var reverse_avoidance_start_mps: float = 0.2
@export var reverse_avoidance_full_mps: float = 5.0
@export var reverse_avoidance_brake_guard_mps: float = 4.0
@export var reverse_avoidance_forward_speed_mps: float = 8.0
@export var reverse_avoidance_forward_pitch: float = 0.35
@export var reverse_avoidance_nose_up_cap: float = 0.02
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
@export var transit_high_speed_yaw_gain: float = 0.42
@export var transit_high_speed_yaw_input: float = 0.75
@export var transit_bank_pullback_gain: float = 0.26
@export var transit_bank_pullback_start_mps: float = 35.0
@export var transit_bank_pullback_full_mps: float = 90.0
@export var terrain_recovery_max_bank_scale: float = 0.30
@export var transit_cruise_forward_lean: float = 0.50
@export var transit_descent_lean_bonus: float = 0.30
@export var transit_descent_lean_alt_full_m: float = 80.0
@export var transit_sharp_turn_lean_scale: float = 0.20
@export var lateral_obstacle_probe_dist_m: float = 120.0
@export var lateral_obstacle_probe_speed_scale: float = 3.0
@export var lateral_obstacle_probe_max_dist_m: float = 400.0
@export var lateral_obstacle_probe_angle_deg: float = 30.0
@export var lateral_obstacle_margin_m: float = 45.0
@export var lateral_obstacle_roll_gain: float = 0.25
@export var lateral_obstacle_yaw_gain: float = 1.10
@export var lateral_obstacle_side_push_mps: float = 10.0
@export var lateral_obstacle_rear_forward_lean: float = 0.18
@export var lateral_obstacle_forward_speed_scale: float = 0.18
@export var lateral_obstacle_forward_speed_max_penalty: float = 1.0

@export_group("Debug")
@export var debug_enabled: bool = true
@export var debug_interval_s: float = 1.0
@export var debug_log_as_error: bool = false
@export var debug_log_as_warning: bool = false
@export var debug_lifecycle_events: bool = true
@export var debug_overlay_enabled: bool = false
@export var debug_overlay_only_when_viewed: bool = false
@export var crash_log_enabled: bool = true
@export var crash_log_history_s: float = 8.0
@export var crash_log_aggregate_path: String = "user://heli_crash_report.log"
@export var lz_departure_debug_enabled: bool = true
@export var lz_departure_debug_duration_s: float = 5.0
@export var lz_departure_debug_interval_s: float = 0.25
@export var lz_landing_debug_enabled: bool = true
@export var lz_landing_debug_interval_s: float = 0.5
@export var recorder_velocity_spike_mps: float = 180.0
@export var recorder_position_jump_mps: float = 180.0
@export var recorder_fault_cooldown_s: float = 12.0
@export var recorder_inverted_dot: float = -0.25
@export var recorder_inverted_time_s: float = 2.0
@export var recorder_sink_rate_mps: float = 12.0
@export var recorder_reverse_speed_mps: float = 10.0

@export_group("Combat")
@export var combat_enabled: bool = true
@export var combat_scan_interval_s: float = 2.0
@export var combat_target_scan_range_m: float = 5500.0
@export var combat_outbound_only: bool = true
@export var combat_allow_bombs: bool = false
@export var combat_min_carrier_distance_m: float = 1800.0
@export var combat_ingress_reach_radius_m: float = 160.0
@export var combat_fire_end_radius_m: float = 160.0
@export var combat_egress_reach_radius_m: float = 220.0
@export var combat_transit_yaw_gain_scale: float = 1.0
@export var combat_plan_async_enabled: bool = true
@export var combat_target_candidate_limit: int = 14
@export var combat_debug_enabled: bool = true
@export var combat_report_enabled: bool = true
@export var combat_report_debug_events_enabled: bool = false
@export var combat_report_path: String = "user://heli_combat_report.log"
@export var combat_report_project_mirror_enabled: bool = true
@export var combat_report_project_mirror_path: String = "res://heli_combat_report.log"
@export var combat_gun_shot_assess_time_s: float = 0.35
@export var combat_alternate_hardpoint_guns_enabled: bool = true
@export var combat_preferred_gun_score_bias: float = 3.6
@export var combat_route_pathfinding_enabled: bool = true
@export var combat_route_advance_radius_m: float = 85.0
@export var combat_route_carrot_distance_m: float = 520.0
@export var combat_route_fire_corridor_spacing_m: float = 140.0
@export var combat_aim_enabled: bool = true
@export var combat_aim_yaw_p: float = 0.85
@export var combat_aim_yaw_i: float = 0.0
@export var combat_aim_yaw_d: float = 0.16
@export var combat_aim_pitch_p: float = 1.35
@export var combat_aim_pitch_i: float = 0.08
@export var combat_aim_pitch_d: float = 0.035
@export var combat_aim_integral_limit: float = 0.35
@export var combat_aim_max_yaw_input: float = 0.42
@export var combat_aim_yaw_deadband_deg: float = 0.35
@export var combat_aim_yaw_correction_rate: float = 0.85
@export var combat_aim_takeover_max_yaw_input: float = 0.78
@export var combat_aim_takeover_yaw_gain: float = 1.35
@export var combat_aim_takeover_yaw_correction_rate: float = 2.4
@export var combat_aim_max_pitch_input: float = 0.45
# Nose-down input at which cruise base pitch is fully blended out during an attack
# (so altitude-hold pitch-up stops fighting the aim controller). Lower = the base
# pitch yields sooner to a nose-down aim demand.
@export var combat_aim_attack_nose_down_full_input: float = 0.30
@export var combat_aim_takeover_max_pitch_input: float = 0.85
@export var combat_aim_takeover_pitch_control_gain: float = 1.55
@export var combat_aim_takeover_pitch_rate_scale: float = 2.4
@export var combat_aim_roll_level_blend: float = 0.35
@export var combat_gun_pitch_control_gain: float = 3.2
# Guns need the same nose-down authority rockets get, otherwise the pipper hangs
# just above the target and the firing window passes before the nose arrives.
@export var combat_gun_max_pitch_input: float = 0.85
@export var combat_gun_nose_down_rate_scale: float = 3.0
@export var combat_rocket_pitch_control_gain: float = 1.70
@export var combat_rocket_max_pitch_input: float = 1.0
@export var combat_rocket_nose_down_rate_scale: float = 3.0
@export var combat_rocket_takeover_nose_down_bias: float = 0.16
@export var combat_rocket_takeover_min_nose_down_input: float = 0.24
@export var combat_rocket_takeover_collective_floor: float = 0.64
@export var combat_rocket_fire_alignment_deg: float = 4.0
@export var combat_gun_fire_alignment_deg: float = 6.0
@export var combat_rocket_aim_settle_deg: float = 2.5
@export var combat_rocket_pitch_aim_settle_deg: float = 2.0
@export var combat_gun_aim_settle_deg: float = 3.0
@export var combat_aim_settle_time_s: float = 0.5
@export var combat_rocket_aim_settle_time_s: float = 1.05
@export var combat_gun_aim_settle_time_s: float = 0.35
@export var combat_aim_settle_max_rate_deg_s: float = 12.0
@export var combat_rocket_aim_settle_max_rate_deg_s: float = 5.0
@export var combat_rocket_pitch_aim_settle_max_rate_deg_s: float = 6.0
@export var combat_gun_aim_settle_max_rate_deg_s: float = 16.0
@export var combat_rocket_min_attack_time_before_fire_s: float = 0.65
@export var combat_rocket_fallback_fire_after_takeover_s: float = 1.2
@export var combat_rocket_fallback_fire_angle_deg: float = 3.2
@export var combat_rocket_fallback_fire_pitch_angle_deg: float = 1.0
@export var combat_rocket_first_salvo_hold_s: float = 4.0
@export var combat_aim_takeover_enabled: bool = true
@export var combat_aim_takeover_range_factor: float = 1.45
@export var combat_aim_takeover_max_time_s: float = 4.5
@export var combat_aim_takeover_cooldown_s: float = 0.15
@export var combat_aim_takeover_speed_mps: float = 22.0
@export var combat_aim_takeover_roll_level_blend: float = 0.9
@export var combat_rocket_drop_compensation: float = 0.85
@export var combat_rocket_motor_speed_bias_mps: float = 160.0
@export var combat_rocket_ccip_guidance_enabled: bool = true
@export var combat_rocket_ccip_recompute_interval_s: float = 0.08
# Proportional gain on the CCIP residual miss. ~1.0 = apply the full residual
# (drives simulated impact onto target in one step, ignoring nose lag); >1.0
# over-corrects and can oscillate, <1.0 converges slower but smoother.
@export var combat_rocket_ccip_aim_correction_strength: float = 1.0
@export var combat_rocket_ccip_aim_correction_max_m: float = 260.0
@export var combat_rocket_ccip_fire_tolerance_m: float = 18.0
@export var combat_rocket_ccip_requires_solution_to_fire: bool = true
@export var combat_rocket_aim_lower_bias_m: float = 2.0
@export var combat_rocket_assess_time_s: float = 1.2
@export var combat_rocket_max_assess_time_s: float = 4.0
@export var combat_rocket_max_salvos_per_attack: int = 8

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
var _rescue_target: Node3D = null   # downed pilot we are picking up
var _passengers: int = 0            # pilots on board
var _nav_waypoint: Vector3 = Vector3.ZERO
var _desired_altitude_m: float = 0.0
var _target_speed_mps: float = NAN
var _carrier_approach_phase: CarrierApproachPhase = CarrierApproachPhase.NONE
var _carrier_final_timer_s: float = 0.0
var _carrier_touchdown_settle_timer_s: float = 0.0
var _carrier_landing_clearance_wait_logged: bool = false
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
var _feeler_net_left_risk: float = 0.0
var _feeler_net_right_risk: float = 0.0
var _feeler_forward_penalty: float = 0.0
var _feeler_forward_obstacle_distance: float = INF
var _feeler_rear_penalty: float = 0.0
var _feeler_timer_s: float = 0.0
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
var _debug_airborne_separation_dist_m: float = INF
var _debug_airborne_separation_speed_limit_mps: float = INF
var _airborne_separation_vertical_avoidance_mps: float = 0.0
var _debug_airborne_separation_log_s: float = 0.0
var _heightmap_path: Array[Vector3] = []
var _heightmap_path_index: int = 0
var _heightmap_path_goal: Vector3 = Vector3(INF, INF, INF)
var _heightmap_path_timer_s: float = 0.0
var _heightmap_path_job: Dictionary = {}
var _path_task_id: int = -1
var _path_job_data: Dictionary = {}
var _transit_cruise_altitude_m: float = NAN
var _last_path_source: String = "none"
var _path_fail_escape_timer_s: float = 0.0
var _path_fail_escape_altitude_m: float = NAN
var _path_fail_escape_reason: String = ""
var _inbound_best_distance_m: float = INF
var _inbound_no_progress_s: float = 0.0
var _inbound_direct_recovery_s: float = 0.0
var _terrain_climb_speed_log_s: float = 0.0
var _path_turn_speed_log_s: float = 0.0
var _debug_canvas: CanvasLayer = null
var _debug_label: Label = null
var _last_debug_line: String = ""

# Flight recorder: ring buffer of (timestamp_s, line) pairs + milestone log
var _flight_log: Array = []       # [[time_s, line], ...]
var _milestone_log: Array = []    # ["2.3s  Landed at LZ", ...]

var _rotor_wash_effect: Node3D = null
var _flight_start_time_s: float = 0.0
var _last_recorder_position: Vector3 = Vector3.INF
var _last_recorder_sample_s: float = 0.0
var _last_origin_shift_s: float = -INF
var _last_origin_shift_offset: Vector3 = Vector3.ZERO
var _last_fault_report_s: float = -INF
var _inverted_timer_s: float = 0.0
var _flight_sequence: int = 0
var _active_flight_id: int = 0
var _flight_departed_carrier_s: float = NAN
var _flight_landed_lz_s: float = NAN
var _flight_departed_lz_s: float = NAN
var _flight_lz_position: Vector3 = Vector3.INF
var _flight_landed_lz: bool = false
var _flight_terminal_report_written: bool = false
var _lz_departure_debug_timer_s: float = 0.0
var _lz_departure_debug_emit_s: float = 0.0
var _lz_landing_debug_emit_s: float = 0.0
var _terrain_landing_settled_timer_s: float = 0.0
var _carrier_approach_speed_log_s: float = 0.0
var _carrier_approach_wait_log_s: float = 0.0
var _carrier_approach_clearance_request_s: float = 0.0
var _missing_carrier_marker_log_once: Dictionary = {}
var _combat_scan_timer_s: float = 0.0
var _combat_plan: Dictionary = {}
var _combat_phase: String = ""
var _combat_fire_log_s: float = 0.0
var _combat_debug_log_s: float = 0.0
var _combat_task_id: int = -1
var _combat_job_data: Dictionary = {}
var _combat_target_nodes_by_id: Dictionary = {}
var _combat_route_task_id: int = -1
var _combat_route_job_data: Dictionary = {}
var _combat_route_points: Array[Vector3] = []
var _combat_route_phases: PackedStringArray = PackedStringArray()
var _combat_route_index: int = 0
var _combat_route_ready: bool = false
var _combat_phase_started_s: float = 0.0
var _combat_aim_takeover_active: bool = false
var _combat_aim_takeover_started_s: float = 0.0
var _combat_aim_takeover_cooldown_until_s: float = 0.0
var _combat_aim_yaw_integral: float = 0.0
var _combat_aim_pitch_integral: float = 0.0
var _combat_aim_prev_yaw_error: float = NAN
var _combat_aim_prev_pitch_error: float = NAN
var _combat_aim_last_yaw_correction: float = 0.0
var _combat_aim_settle_s: float = 0.0
var _combat_rocket_assess_until_s: float = 0.0
var _combat_rocket_salvos_fired: int = 0
var _combat_rocket_next_hardpoint_index: int = 0
var _combat_rocket_ccip_cache_time_s: float = -1000000.0
var _combat_rocket_ccip_cache_target_id: int = -1
var _combat_rocket_ccip_cache: Dictionary = {}
var _combat_prefer_hardpoint_guns_next: bool = true
var _combat_pending_shot_reports: Array[Dictionary] = []
var _combat_next_shot_report_id: int = 1
var _combat_attack_run_active: bool = false
var _combat_attack_run_id: int = 0
var _combat_next_attack_run_report_id: int = 1
var _combat_attack_run_started_s: float = 0.0
var _combat_attack_run_weapon: String = ""
var _combat_attack_run_target_name: String = ""
var _combat_attack_run_target_id: int = 0
var _combat_attack_run_shots: int = 0
var _combat_attack_run_last_hold_reason: String = "none"
var _combat_attack_run_last_hold_details: String = ""
var _combat_attack_run_min_dist_m: float = INF
var _combat_attack_run_best_aim_dot: float = -1.0
var _combat_attack_run_last_aim_dot: float = NAN
var _combat_attack_run_last_yaw_deg: float = NAN
var _combat_attack_run_last_pitch_deg: float = NAN
var _combat_attack_run_best_ccip_miss_m: float = INF
var _combat_attack_run_last_ccip_miss_m: float = INF

var _phys_max_bank_deg: float = 30.0
var _phys_max_nose_up_deg: float = 15.0
var _phys_max_decel_mps2: float = 4.0
var _phys_max_climb_mps: float = 5.0

func _ready() -> void:
	add_to_group("origin_shifter")
	set_physics_process(false)
	_reset_combat_report_for_run_once()
	_debug_event("loaded", "parent=%s" % [get_parent().name if get_parent() else "?"])
	if debug_enabled:
		print("[HelicopterPilot] %s loaded on %s — waiting for initialize(). If you never see a second line, AI was never enabled." \
			% [name, get_parent().name if get_parent() else "?"])


func _exit_tree() -> void:
	if _path_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_path_task_id)
		_path_task_id = -1
	if _combat_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_combat_task_id)
		_combat_task_id = -1
	if _combat_route_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_combat_route_task_id)
		_combat_route_task_id = -1
	if crash_log_enabled and _active_flight_id > 0 and not _flight_terminal_report_written:
		_write_incomplete_flight_report("NODE EXIT")


func apply_origin_shift(offset: Vector3) -> void:
	destination -= offset
	_nav_waypoint -= offset
	for i in range(_heightmap_path.size()):
		_heightmap_path[i] -= offset
	_heightmap_path_goal -= offset
	_heightmap_path_job.clear()
	if _path_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_path_task_id)
		_path_task_id = -1
		_path_job_data.clear()
	if _combat_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_combat_task_id)
		_combat_task_id = -1
		_combat_job_data.clear()
		_combat_target_nodes_by_id.clear()
	if _combat_route_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_combat_route_task_id)
		_combat_route_task_id = -1
		_combat_route_job_data.clear()
	if not is_nan(_path_fail_escape_altitude_m):
		_path_fail_escape_altitude_m -= offset.y
	if not is_nan(_transit_cruise_altitude_m):
		_transit_cruise_altitude_m -= offset.y
	for i in range(_combat_route_points.size()):
		_combat_route_points[i] -= offset
	if not is_nan(_takeoff_start_altitude_m):
		_takeoff_start_altitude_m -= offset.y
	_last_origin_shift_s = Time.get_ticks_msec() / 1000.0
	_last_origin_shift_offset = offset
	_prev_forward_lean = 0.0
	_last_recorder_position = Vector3.INF
	_debug_event("origin_shift", "offset=%s pos=%s vel=%s" % [
		str(offset.snapped(Vector3.ONE * 0.1)),
		str(aircraft.global_position.snapped(Vector3.ONE * 0.1)) if is_instance_valid(aircraft) else "?",
		str(aircraft.linear_velocity.snapped(Vector3.ONE * 0.1)) if is_instance_valid(aircraft) else "?",
	])


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

	_update_physics_capabilities()

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

	var rotor_wash_script = load("res://Effects/RotorWashEffect.gd")
	if rotor_wash_script:
		_rotor_wash_effect = rotor_wash_script.new()
		aircraft.add_child(_rotor_wash_effect)

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
	_release_carrier_landing_clearance_from_deck()
	_set_helicopter_input(0.0, 0.0, 0.0)
	_apply_collective(0.0)
	_pitch_cmd = 0.0
	_roll_cmd = 0.0
	_yaw_cmd = 0.0
	_landing_on_carrier = false
	_carrier_landing_clearance_wait_logged = false
	_carrier_approach_clearance_request_s = 0.0
	_takeoff_start_altitude_m = NAN
	_takeoff_started_from_deck = false
	_prev_fwd_speed = 0.0
	_prev_lat_speed = 0.0
	_prev_vertical_speed = 0.0
	_prev_forward_lean = 0.0
	_collective_cmd = 0.0
	set_physics_process(false)


func change_state(new_state: State) -> void:
	if state == new_state:
		return
	_prev_forward_lean = 0.0
	if new_state != State.LANDING:
		_terrain_landing_settled_timer_s = 0.0
		_carrier_touchdown_settle_timer_s = 0.0
		if state == State.LANDING and _landing_on_carrier:
			_release_carrier_landing_clearance_from_deck()
			_carrier_landing_clearance_wait_logged = false
			_carrier_approach_clearance_request_s = 0.0
	if new_state == State.TAKEOFF:
		_prime_takeoff_reference()
		if not _is_deck_takeoff_context() and is_instance_valid(aircraft):
			var engine_working := false
			var engine_power := 0.0
			if engine != null:
				var working_val = engine.get("is_engine_working")
				if working_val != null:
					engine_working = bool(working_val)
				var power_val = engine.get("current_power")
				if power_val != null:
					engine_power = float(power_val)
			
			print("HELI_AI change_state State.TAKEOFF craft=%s engine=%s working=%s power=%.2f is_deck_takeoff=%s" % [
				aircraft.name,
				str(engine != null),
				str(engine_working),
				engine_power,
				str(_is_deck_takeoff_context())
			])
			
			if not engine_working or engine_power < 0.55:
				aircraft.set_meta("parking_brake", true)
				aircraft.freeze = true
				aircraft.sleeping = true
			else:
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
		# _transit_cruise_altitude_m is intentionally NOT set to NAN here.
		# It preserves the takeoff altitude, allowing it to smoothly bleed down
		# to the local route altitude rather than dropping out instantly.
	elif new_state == State.LANDING:
		_set_landing_gear_deployed(true)
	if new_state != State.LOW_LEVEL_TRANSIT:
		_clear_combat_attack("state_changed")
		_cancel_combat_plan_job()
		_cancel_combat_route_job()
	var previous_state := state
	state = new_state
	_debug_event("state", "from=%s to=%s" % [_state_name_for(previous_state), _state_name()])


func set_destination(world_position: Vector3, target_speed_mps: float = -1.0) -> void:
	var previous_destination := destination
	var had_destination := _has_destination
	destination = world_position
	_has_destination = true
	if target_speed_mps > 0.0:
		_target_speed_mps = target_speed_mps
	if not had_destination or _flat_distance(previous_destination, world_position) > maxf(destination_path_reset_threshold_m, 0.0):
		_clear_heightmap_path("set_destination")
	if state == State.IDLE or state == State.HOVER:
		change_state(State.LOW_LEVEL_TRANSIT)


func set_target_speed(speed_mps: float) -> void:
	if speed_mps > 0.0:
		_target_speed_mps = speed_mps


func clear_target_speed() -> void:
	_target_speed_mps = NAN


func set_flight_leg(target_position: Vector3, target_speed_mps: float = -1.0) -> void:
	set_destination(target_position, target_speed_mps)


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
	_reset_inbound_progress_watchdog()
	mission_phase = MissionPhase.INBOUND
	_landing_on_carrier = false
	_carrier_approach_phase = CarrierApproachPhase.NONE
	_carrier_final_timer_s = 0.0
	_carrier_touchdown_settle_timer_s = 0.0
	_carrier_approach_clearance_request_s = 0.0
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


func command_rescue(pilot_node: Node3D) -> void:
	if not is_instance_valid(pilot_node):
		return
	_rescue_target = pilot_node
	mission_phase = MissionPhase.RESCUE
	_clear_combat_attack("rescue_commanded")
	_cancel_combat_plan_job()
	_clear_heightmap_path("rescue_start")
	set_destination(pilot_node.global_position)
	_record_milestone("Rescue mission — heading to downed pilot at %s" % [str(pilot_node.global_position.snapped(Vector3.ONE))])
	print("[HelicopterPilot] %s dispatched for rescue of %s" % [aircraft.name if is_instance_valid(aircraft) else name, pilot_node.name])


func add_passenger(pilot_node: Node3D) -> void:
	_passengers += 1
	_rescue_target = null
	print("[HelicopterPilot] %s picked up passenger — %d on board. Returning to carrier." % [aircraft.name if is_instance_valid(aircraft) else name, _passengers])
	_clear_heightmap_path("rescue_complete")
	_reset_inbound_progress_watchdog()
	mission_phase = MissionPhase.INBOUND
	_carrier_approach_phase = CarrierApproachPhase.NONE
	_carrier_final_timer_s = 0.0
	_carrier_approach_clearance_request_s = 0.0
	_update_carrier_destination()
	_clear_ground_landing_hold()
	change_state(State.TAKEOFF)


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
	var _profiler_start: int = FrameProfiler.begin("HelicopterPilot.physics")
	_update_combat_shot_reports()
	if aircraft.get_meta("controls_disabled", false):
		FrameProfiler.end("HelicopterPilot.physics", _profiler_start)
		return
	_physics_delta = delta
	_terrain_climb_speed_log_s = maxf(_terrain_climb_speed_log_s - delta, 0.0)
	_path_turn_speed_log_s = maxf(_path_turn_speed_log_s - delta, 0.0)
	_update_path_fail_escape_timer(delta)
	if _path_task_id != -1:
		var _path_profiler_start: int = FrameProfiler.begin("HelicopterPilot.path_job")
		if WorkerThreadPool.is_task_completed(_path_task_id):
			WorkerThreadPool.wait_for_task_completion(_path_task_id)
			_path_task_id = -1
			var result: Dictionary = _path_job_data.get("result", {})
			if not result.is_empty():
				var raw_path: Array[Vector3] = []
				raw_path.assign(result.get("raw_path", []))
				var final_path: Array[Vector3] = []
				final_path.assign(result.get("final_path", []))
				_commit_heightmap_path_result(
					_path_job_data.current_pos,
					_path_job_data.goal,
					raw_path,
					final_path,
					result.elevated_count,
					result.simplified_count,
					result.start_ms,
					result.reason,
					result.get("elapsed_ms", -1)
				)
		FrameProfiler.end("HelicopterPilot.path_job", _path_profiler_start)

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

	if _rotor_wash_effect and is_instance_valid(_rotor_wash_effect):
		var ground_h := _get_ground_height_at_position(aircraft.global_position)
		_rotor_wash_effect.current_agl = aircraft.global_position.y - ground_h if not is_nan(ground_h) else INF
		_rotor_wash_effect.is_engine_on = control_engine.target_power > 0.1 if is_instance_valid(control_engine) else true
		_rotor_wash_effect.rotor_radius = helicopter_flight.rotor_radius if "rotor_radius" in helicopter_flight else 10.0

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
			elif mission_phase == MissionPhase.RESCUE:
				_hold_landed_on_terrain(delta)
				# Don't tick the timeout while the pilot is still alive and approaching.
				# Once add_passenger() is called _rescue_target is cleared and we transition
				# to INBOUND immediately — the timer only fires if no one ever boards.
				if is_instance_valid(_rescue_target):
					_idle_dwell_timer_s = 60.0
			elif mission_phase == MissionPhase.AT_CARRIER:
				_hold_landed_on_carrier()
			_idle_dwell_timer_s -= delta
			if _idle_dwell_timer_s <= 0.0:
				_advance_mission()
		State.TAKEOFF:
			var engine_working := false
			var engine_power := 0.0
			if engine != null:
				var working_val = engine.get("is_engine_working")
				if working_val != null:
					engine_working = bool(working_val)
				var power_val = engine.get("current_power")
				if power_val != null:
					engine_power = float(power_val)
			
			if not engine_working or engine_power < 0.55:
				_apply_collective(1.0)
				_set_helicopter_input(0.0, 0.0, 0.0)
				_update_lz_departure_debug(delta)
				return
			
			if not _is_deck_takeoff_context() and is_instance_valid(aircraft) and aircraft.freeze:
				if aircraft.has_meta("parking_brake"):
					aircraft.remove_meta("parking_brake")
				aircraft.freeze = false
				aircraft.sleeping = false
				_debug_event("takeoff_engine_ready", "power=%.2f" % engine_power)
				
			if _should_hold_vertical_takeoff():
				_nav_waypoint = Vector3(aircraft.global_position.x, _desired_altitude_m, aircraft.global_position.z)
			_fly_toward(_nav_waypoint, _get_takeoff_speed_limit(), delta)
			_update_lz_departure_debug(delta)
			if _takeoff_is_clear():
				change_state(State.LOW_LEVEL_TRANSIT)
		State.LOW_LEVEL_TRANSIT:
			var transit_speed := _get_path_fail_escape_speed(_get_current_leg_target_speed_mps(cruise_speed_mps))
			transit_speed = _get_terrain_climb_speed_limit(transit_speed)
			transit_speed = _get_path_turn_speed_limit(transit_speed)
			if _update_combat_attack(delta, transit_speed):
				_emit_debug(delta)
				_check_recorder_faults(delta)
				FrameProfiler.end("HelicopterPilot.physics", _profiler_start)
				return
			if mission_phase == MissionPhase.INBOUND:
				if _update_inbound_progress_watchdog(delta):
					_update_navigation_plan()
				transit_speed = minf(transit_speed, _get_carrier_approach_arrival_speed_limit(transit_speed))
			_fly_toward(_nav_waypoint, transit_speed, delta)
			if mission_phase == MissionPhase.INBOUND:
				# For carrier landing, only enter LANDING once through the approach gate.
				# The gate is the approach marker position — stay in transit until then
				# so the helicopter decelerates naturally rather than slamming the hover brake.
				var approach_world := _get_carrier_approach_point_world_pos()
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
	_check_recorder_faults(delta)
	FrameProfiler.end("HelicopterPilot.physics", _profiler_start)


func _advance_mission() -> void:
	match mission_phase:
		MissionPhase.AT_LZ:
			_record_milestone("Departed LZ — heading back to carrier")
			_flight_departed_lz_s = _elapsed_s()
			_clear_ground_landing_hold()
			_clear_heightmap_path("inbound_start")
			_reset_inbound_progress_watchdog()
			mission_phase = MissionPhase.INBOUND
			_carrier_approach_phase = CarrierApproachPhase.NONE
			_carrier_final_timer_s = 0.0
			_carrier_landing_clearance_wait_logged = false
			_carrier_approach_clearance_request_s = 0.0
			_update_carrier_destination()
			change_state(State.TAKEOFF)
		MissionPhase.RESCUE:
			# Dwell timer expired without anyone boarding — give up and return.
			_rescue_target = null
			_record_milestone("Rescue pickup timeout — returning to carrier")
			_clear_ground_landing_hold()
			_clear_heightmap_path("rescue_timeout")
			_reset_inbound_progress_watchdog()
			mission_phase = MissionPhase.INBOUND
			_carrier_approach_phase = CarrierApproachPhase.NONE
			_carrier_final_timer_s = 0.0
			_carrier_approach_clearance_request_s = 0.0
			_update_carrier_destination()
			change_state(State.TAKEOFF)
		MissionPhase.AT_CARRIER:
			var fd_mgr := get_tree().get_first_node_in_group("flight_deck_manager")
			if fd_mgr and fd_mgr.get("auto_recovery_enabled"):
				_record_milestone("Waiting on deck for tractor recovery")
				return

			_record_milestone("Landed back at carrier — picking new LZ")
			_clear_carrier_landing_hold()
			_pick_random_lz()
			_start_flight_summary()
			mission_phase = MissionPhase.OUTBOUND
			change_state(State.TAKEOFF)


func _clear_ground_landing_hold() -> void:
	if not is_instance_valid(aircraft):
		return
	_debug_lz_departure_snapshot("pre_clear")
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
	_prev_forward_lean = 0.0
	_lz_departure_debug_timer_s = maxf(lz_departure_debug_duration_s, 0.0) if lz_departure_debug_enabled else 0.0
	_lz_departure_debug_emit_s = 0.0
	_debug_lz_departure_snapshot("post_clear")
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
	_heightmap_path_job.clear()
	if _path_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_path_task_id)
		_path_task_id = -1
		_path_job_data.clear()
	_transit_cruise_altitude_m = NAN
	_path_fail_escape_timer_s = 0.0
	_path_fail_escape_altitude_m = NAN
	_path_fail_escape_reason = ""


func _pick_random_lz() -> void:
	var _profiler_start: int = FrameProfiler.begin("HelicopterPilot.lz_pick")
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
					FrameProfiler.end("HelicopterPilot.lz_pick", _profiler_start)
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
				FrameProfiler.end("HelicopterPilot.lz_pick", _profiler_start)
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
	FrameProfiler.end("HelicopterPilot.lz_pick", _profiler_start)


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
	if ground_h > _get_heightmap_max_route_terrain_y():
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
			var approach_pos := _get_carrier_approach_point_world_pos()
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


func _update_physics_capabilities() -> void:
	if not is_instance_valid(aircraft) or helicopter_flight == null:
		return
	var mass := aircraft.mass if "mass" in aircraft else 2000.0
	var gravity := 9.81
	
	var max_tilt: Variant = helicopter_flight.get("max_disc_tilt_deg")
	if max_tilt != null:
		_phys_max_bank_deg = float(max_tilt)
	
	_phys_max_nose_up_deg = minf(_phys_max_bank_deg, maxf(transit_max_nose_up * 90.0, 15.0))
	_phys_max_decel_mps2 = gravity * tan(deg_to_rad(_phys_max_nose_up_deg))
	
	var max_thrust: Variant = helicopter_flight.get("max_rotor_thrust_n")
	var thrust_val := float(max_thrust) if max_thrust != null else 0.0
	if thrust_val <= 0.0:
		var mult: Variant = helicopter_flight.get("max_lift_multiplier")
		if mult != null:
			thrust_val = mass * gravity * float(mult)
		else:
			thrust_val = mass * gravity * 1.5
	
	var climb_accel := maxf(thrust_val / mass - gravity, 0.5)
	_phys_max_climb_mps = climb_accel * 2.5 # Approximate sustainable climb speed


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

	# Keep tracking a walking downed pilot
	if mission_phase == MissionPhase.RESCUE and is_instance_valid(_rescue_target):
		var new_dest := _rescue_target.global_position
		if not _has_destination or _flat_distance(destination, new_dest) > 5.0:
			destination = new_dest
			_has_destination = true

	if not _has_destination:
		_pick_random_lz()

	var current_pos: Vector3 = aircraft.global_position
	var goal: Vector3 = destination if _has_destination else current_pos
	if use_heightmap_pathfinding and _heightmap_path.is_empty() and _has_destination:
		var _routing_pt := _get_heightmap_route_point(current_pos, destination)
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
			_transit_cruise_altitude_m = maxf(base_ground + maxf(heightmap_path_target_agl_m, min_terrain_clearance_m), current_pos.y)
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
				(_transit_cruise_altitude_m - local_target_altitude) * 0.4,
				maxf(max_descent_mps * 1.5, 4.0)
			) * _physics_delta
			_transit_cruise_altitude_m = maxf(_transit_cruise_altitude_m - bleed, local_target_altitude)
			_desired_altitude_m = _transit_cruise_altitude_m

	if state == State.LOW_LEVEL_TRANSIT and _is_path_fail_escape_active():
		var escape_altitude := _get_path_fail_escape_altitude(current_pos, goal, base_ground)
		_desired_altitude_m = maxf(_desired_altitude_m, escape_altitude)
		_transit_cruise_altitude_m = _desired_altitude_m

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
		if use_heightmap_pathfinding and _heightmap_path.is_empty() and _has_destination:
			var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
			if _takeoff_started_from_deck:
				if carrier != null and carrier.has_method("get_active_waypoints"):
					var carrier_wps: Array = carrier.call("get_active_waypoints")
					if not carrier_wps.is_empty():
						var target_wp: Vector3 = carrier_wps[0]
						_nav_waypoint = Vector3(target_wp.x, _desired_altitude_m, target_wp.z)
						return
			else:
				if carrier != null:
					var to_carrier: Vector3 = (carrier.global_position - current_pos)
					to_carrier.y = 0.0
					if to_carrier.length_squared() > 1.0:
						var backup_target := current_pos + to_carrier.normalized() * 100.0
						_nav_waypoint = Vector3(backup_target.x, _desired_altitude_m, backup_target.z)
						return
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
		var upcoming_alt := _get_heightmap_upcoming_required_altitude(current_pos, maxf(terrain_climb_lookahead_m, heightmap_path_carrot_distance_m))
		if not is_nan(upcoming_alt):
			carrot_alt = maxf(carrot_alt, upcoming_alt)
		var route_floor_altitude := base_ground + maxf(heightmap_path_target_agl_m, min_terrain_clearance_m)
		var route_target_altitude := maxf(carrot_alt, route_floor_altitude)
		if is_nan(_transit_cruise_altitude_m):
			_transit_cruise_altitude_m = route_target_altitude
		elif route_target_altitude > _transit_cruise_altitude_m:
			_transit_cruise_altitude_m = route_target_altitude
		else:
			var descent_target := route_target_altitude + maxf(heightmap_path_descent_margin_m, 0.0)
			var descent_step := maxf(heightmap_path_descent_rate_mps, 0.0) * _physics_delta
			_transit_cruise_altitude_m = move_toward(_transit_cruise_altitude_m, descent_target, descent_step)
		_desired_altitude_m = _transit_cruise_altitude_m
		var path_corridor_height: float = _sample_max_terrain_height_along_path(current_pos, path_point)
		if not is_nan(path_corridor_height):
			var path_required_altitude: float = path_corridor_height + maxf(heightmap_path_target_agl_m, min_terrain_clearance_m)
			if path_required_altitude > _desired_altitude_m:
				_desired_altitude_m = _clamp_heightmap_flight_altitude(path_required_altitude)
				_transit_cruise_altitude_m = maxf(_transit_cruise_altitude_m, _desired_altitude_m)
				_debug_event("path_hazard", "mode=raise_alt hazard=%.1f target_alt=%.1f point=%s" % [
					path_corridor_height,
					_desired_altitude_m,
					str(path_point.snapped(Vector3.ONE * 0.1)),
				])
		_apply_forward_terrain_hazard(current_pos, path_point)
		# Use carrot_alt as the waypoint Y so the heli flies a 3D path toward the
		# next point's altitude, rather than always targeting current cruise altitude.
		# _desired_altitude_m still governs terrain hazard guards above.
		_nav_waypoint = Vector3(path_point.x, carrot_alt, path_point.z)
		return

	if state == State.LOW_LEVEL_TRANSIT and _is_path_fail_escape_active():
		var hold_dir := _get_flat_direction_to_goal(current_pos, goal)
		var hold_dist := minf(terrain_lookahead_m * 0.35, maxf(_flat_distance(current_pos, goal), 0.0))
		var hold_target := current_pos + hold_dir * maxf(hold_dist, 40.0)
		_nav_waypoint = Vector3(hold_target.x, _desired_altitude_m, hold_target.z)
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


func _get_flat_direction_to_goal(current_pos: Vector3, goal: Vector3) -> Vector3:
	var direct := goal - current_pos
	direct.y = 0.0
	if direct.length_squared() > 1.0:
		return direct.normalized()
	var control_vel := _get_control_velocity()
	control_vel.y = 0.0
	if control_vel.length_squared() > 1.0:
		return control_vel.normalized()
	var forward := aircraft.global_transform.basis.z if is_instance_valid(aircraft) else Vector3.FORWARD
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD


func _reset_inbound_progress_watchdog() -> void:
	_inbound_best_distance_m = INF
	_inbound_no_progress_s = 0.0
	_inbound_direct_recovery_s = 0.0


func _update_inbound_progress_watchdog(delta: float) -> bool:
	if state != State.LOW_LEVEL_TRANSIT or mission_phase != MissionPhase.INBOUND or not _has_destination:
		_reset_inbound_progress_watchdog()
		return false
	if not is_instance_valid(aircraft):
		return false

	_inbound_direct_recovery_s = maxf(_inbound_direct_recovery_s - maxf(delta, 0.0), 0.0)
	var current_pos := aircraft.global_position
	var dist := _flat_distance(current_pos, destination)
	if dist <= maxf(carrier_approach_gate_radius_m, 5.0) * 2.0:
		_inbound_best_distance_m = dist
		_inbound_no_progress_s = 0.0
		return false

	var required_progress := maxf(carrier_inbound_progress_min_m, 1.0)
	if _inbound_best_distance_m == INF or dist < _inbound_best_distance_m - required_progress:
		_inbound_best_distance_m = dist
		_inbound_no_progress_s = 0.0
		return false

	_inbound_no_progress_s += maxf(delta, 0.0)
	if _inbound_no_progress_s < maxf(carrier_inbound_no_progress_timeout_s, 0.1):
		return false

	_debug_event("carrier_inbound_recover", "reason=no_progress dist=%.0f best=%.0f cphase=%s wp=%s path=%d/%d" % [
		dist,
		_inbound_best_distance_m,
		_carrier_approach_phase_name(),
		str(_nav_waypoint.snapped(Vector3.ONE)),
		_heightmap_path_index,
		_heightmap_path.size(),
	])
	_clear_heightmap_path("inbound_no_progress")
	_inbound_best_distance_m = dist
	_inbound_no_progress_s = 0.0
	_inbound_direct_recovery_s = maxf(carrier_inbound_direct_recovery_s, 0.0)
	_heightmap_path_timer_s = maxf(_inbound_direct_recovery_s, _heightmap_path_timer_s)
	var direct_alt := _desired_altitude_m
	if is_nan(direct_alt):
		direct_alt = current_pos.y
	_nav_waypoint = Vector3(destination.x, direct_alt, destination.z)
	return true


func _choose_low_level_corridor(current_pos: Vector3, goal: Vector3) -> Vector3:
	var direct: Vector3 = _get_flat_direction_to_goal(current_pos, goal)

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
	if _inbound_direct_recovery_s > 0.0 and mission_phase == MissionPhase.INBOUND:
		return Vector3.INF

	_heightmap_path_timer_s -= _physics_delta
	var goal_repath_threshold: float = maxf(heightmap_path_goal_move_recompute_m, 1.0)
	if mission_phase == MissionPhase.INBOUND:
		goal_repath_threshold = maxf(carrier_goal_repath_threshold_m, 1.0)
	if not _heightmap_path.is_empty() and _flat_distance(_heightmap_path_goal, goal) > goal_repath_threshold:
		if not _should_keep_inbound_heightmap_route_for_moving_goal():
			_clear_heightmap_path("goal_moved")
	if _path_task_id != -1:
		var job_goal_value: Variant = _path_job_data.get("goal", Vector3.INF)
		if job_goal_value is Vector3:
			var job_goal := Vector3.INF
			job_goal = job_goal_value
			if _flat_distance(job_goal, goal) > goal_repath_threshold:
				if not _should_keep_inbound_heightmap_route_for_moving_goal():
					WorkerThreadPool.wait_for_task_completion(_path_task_id)
					_path_task_id = -1
					_path_job_data.clear()
					_heightmap_path_timer_s = 0.0
	if _heightmap_path.is_empty() and _heightmap_path_timer_s <= 0.0:
		if heightmap_path_async_enabled:
			if _path_task_id == -1:
				_start_heightmap_path_job(current_pos, goal)
		else:
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
	# Only skip if the helicopter is reasonably close to the waypoint — don't skip
	# distant waypoints the helicopter hasn't meaningfully approached.
	while _heightmap_path_index < _heightmap_path.size() - 1:
		var cur_pt := _heightmap_path[_heightmap_path_index]
		var nxt_pt := _heightmap_path[_heightmap_path_index + 1]
		var to_next := Vector3(nxt_pt.x - cur_pt.x, 0.0, nxt_pt.z - cur_pt.z)
		var to_here := Vector3(current_pos.x - cur_pt.x, 0.0, current_pos.z - cur_pt.z)
		var dist_to_wp := to_here.length()
		if to_next.length_squared() > 1.0 and to_here.dot(to_next.normalized()) > 0.0 and dist_to_wp < maxf(heightmap_path_advance_radius_m * 3.0, 200.0):
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


func _should_keep_inbound_heightmap_route_for_moving_goal() -> bool:
	return mission_phase == MissionPhase.INBOUND \
			and (state == State.LOW_LEVEL_TRANSIT or state == State.TAKEOFF or state == State.HOVER) \
			and not _landing_on_carrier


func _advance_heightmap_path_to_clear_point(current_pos: Vector3) -> void:
	if _heightmap_path.is_empty() or _heightmap_path_index >= _heightmap_path.size() - 1:
		return
	var original_index := _heightmap_path_index
	# Don't skip past waypoints that represent significant turns — the helicopter
	# needs them to navigate safely around obstacles.
	var max_skip_turn_deg := 15.0
	for i in range(_heightmap_path.size() - 1, _heightmap_path_index, -1):
		if not _has_clear_transit_segment(current_pos, _heightmap_path[i]):
			continue
		# Check if any intermediate waypoint represents a significant turn or altitude change.
		var skip_ok := true
		var prev_dir := (_heightmap_path[_heightmap_path_index] - current_pos)
		prev_dir.y = 0.0
		var skip_start := _heightmap_path[_heightmap_path_index]
		var skip_end := _heightmap_path[i]
		var skip_span := _flat_distance(skip_start, skip_end)
		var alt_error_limit := maxf(heightmap_path_simplify_altitude_error_m, 0.0)
		for j in range(_heightmap_path_index + 1, i):
			var leg_in := (_heightmap_path[j] - _heightmap_path[j - 1])
			leg_in.y = 0.0
			var leg_out := (_heightmap_path[j + 1] - _heightmap_path[j]) if j + 1 < _heightmap_path.size() else leg_in
			leg_out.y = 0.0
			if leg_in.length_squared() < 1.0 or leg_out.length_squared() < 1.0:
				continue
			var turn_angle := rad_to_deg(leg_in.normalized().angle_to(leg_out.normalized()))
			if turn_angle > max_skip_turn_deg:
				skip_ok = false
				break
			# Don't skip past waypoints with significant altitude deviation from the
			# straight-line interpolation — the heli needs them as climb cues.
			if skip_span > 1.0:
				var mid := _heightmap_path[j]
				var t := clampf(_flat_distance(skip_start, mid) / skip_span, 0.0, 1.0)
				var expected_alt := lerpf(skip_start.y, skip_end.y, t)
				if mid.y > expected_alt + alt_error_limit:
					skip_ok = false
					break
		if skip_ok:
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


func _get_heightmap_upcoming_required_altitude(current_pos: Vector3, lookahead_m: float) -> float:
	var demand := _get_heightmap_upcoming_climb_demand(current_pos, lookahead_m)
	if demand.is_empty():
		return NAN
	return float(demand.get("altitude", NAN))


func _get_heightmap_upcoming_climb_demand(current_pos: Vector3, lookahead_m: float) -> Dictionary:
	if _heightmap_path.is_empty() or _heightmap_path_index >= _heightmap_path.size():
		return {}
	var max_lookahead := maxf(lookahead_m, 1.0)
	var previous := current_pos
	var traveled := 0.0
	var best_altitude := current_pos.y
	var best_distance := 0.0
	for i in range(_heightmap_path_index, _heightmap_path.size()):
		var point := _heightmap_path[i]
		var segment_len := _flat_distance(previous, point)
		var next_traveled := traveled + segment_len
		if next_traveled > max_lookahead:
			var t := 0.0
			if segment_len > 0.001:
				t = clampf((max_lookahead - traveled) / segment_len, 0.0, 1.0)
			var partial_altitude := lerpf(previous.y, point.y, t)
			if partial_altitude > best_altitude:
				best_altitude = partial_altitude
				best_distance = max_lookahead
			break
		if point.y > best_altitude:
			best_altitude = point.y
			best_distance = next_traveled
		traveled = next_traveled
		previous = point
	if best_altitude <= current_pos.y + 1.0:
		return {}
	return {
		"altitude": _clamp_heightmap_flight_altitude(best_altitude),
		"distance": maxf(best_distance, 1.0),
	}


func _get_terrain_climb_speed_limit(desired_speed: float) -> float:
	if state != State.LOW_LEVEL_TRANSIT or not is_instance_valid(aircraft):
		return desired_speed
	var demand := _get_heightmap_upcoming_climb_demand(
		aircraft.global_position,
		maxf(terrain_climb_lookahead_m, heightmap_path_carrot_distance_m)
	)
	if demand.is_empty():
		return desired_speed
	var target_altitude := float(demand.get("altitude", aircraft.global_position.y))
	var distance := maxf(float(demand.get("distance", 1.0)), 1.0)
	
	# Only limit speed if we are below the minimum safe clearance altitude (danger zone),
	# not just the ideal cruise altitude.
	var safety_margin := maxf(cruise_agl_m - min_terrain_clearance_m, 0.0)
	var min_safe_altitude := target_altitude - safety_margin
	var altitude_deficit := min_safe_altitude - aircraft.global_position.y
	if altitude_deficit <= 1.0:
		return desired_speed
	
	# PHYSICS RULE 3: Dynamic Climb Speed based on helicopter thrust-to-weight capability
	var climb_capacity := maxf(_phys_max_climb_mps * clampf(terrain_climb_capacity_scale, 0.1, 1.5), 1.0)
	var time_needed := altitude_deficit / climb_capacity + maxf(terrain_climb_arrival_margin_s, 0.0)
	var speed_limit := distance / maxf(time_needed, 0.1)
	
	# Removed static hard floor so big helicopters genuinely slow down if their limits demand it
	speed_limit = minf(speed_limit, desired_speed)
	if speed_limit < desired_speed - 1.0 and _terrain_climb_speed_log_s <= 0.0:
		_terrain_climb_speed_log_s = maxf(terrain_climb_speed_log_interval_s, 0.1)
		_debug_event("terrain_climb_plan", "dist=%.1f alt=%.1f deficit=%.1f limit=%.1f desired=%.1f climb_cap=%.1f" % [
			distance,
			target_altitude,
			altitude_deficit,
			speed_limit,
			desired_speed,
			climb_capacity,
		])
	return speed_limit


func _get_path_turn_speed_limit(desired_speed: float) -> float:
	if not path_turn_speed_enabled or state != State.LOW_LEVEL_TRANSIT or not is_instance_valid(aircraft):
		return desired_speed
	if _heightmap_path.is_empty() or _heightmap_path_index >= _heightmap_path.size() - 1:
		return desired_speed

	var current_pos := aircraft.global_position
	var corner := _heightmap_path[_heightmap_path_index]
	var next_point := _heightmap_path[_heightmap_path_index + 1]
	var to_corner := Vector3(corner.x - current_pos.x, 0.0, corner.z - current_pos.z)
	var out_leg := Vector3(next_point.x - corner.x, 0.0, next_point.z - corner.z)
	var corner_dist := to_corner.length()
	var out_len := out_leg.length()
	if corner_dist < 1.0 or out_len < 1.0:
		return desired_speed

	var in_dir := to_corner / corner_dist
	var out_dir := out_leg / out_len
	var turn_angle := absf(in_dir.signed_angle_to(out_dir, Vector3.UP))
	var min_angle := deg_to_rad(maxf(path_turn_speed_min_angle_deg, 0.0))
	if turn_angle <= min_angle:
		return desired_speed

	var full_angle := deg_to_rad(maxf(path_turn_speed_full_angle_deg, path_turn_speed_min_angle_deg + 1.0))
	var angle_t := clampf((turn_angle - min_angle) / maxf(full_angle - min_angle, 0.001), 0.0, 1.0)
	var lookahead := maxf(path_turn_speed_lookahead_m, heightmap_path_advance_radius_m)
	if corner_dist >= lookahead:
		return desired_speed

	var available_radius := minf(corner_dist, out_len) * clampf(path_turn_radius_fraction, 0.1, 2.0)
	var turn_radius := maxf(available_radius, maxf(path_turn_min_radius_m, 1.0))
	
	# PHYSICS RULE 1: Dynamic Turn Speed based on helicopter bank limits
	var gravity := 9.81
	var bank_margin := 0.75 # Don't ride the absolute physical bank limit during a transit turn
	var lateral_accel := gravity * tan(deg_to_rad(_phys_max_bank_deg * bank_margin))
	
	var corner_speed := sqrt(lateral_accel * turn_radius)
	# Removed static hard floor so big helicopters genuinely slow down if their limits demand it
	corner_speed = minf(corner_speed, desired_speed)

	var approach_t := 1.0 - clampf(corner_dist / lookahead, 0.0, 1.0)
	var limit_t := clampf(approach_t * angle_t, 0.0, 1.0)
	var speed_limit := lerpf(desired_speed, corner_speed, limit_t)
	speed_limit = clampf(speed_limit, maxf(path_turn_speed_floor_mps, 1.0), desired_speed)
	if speed_limit < desired_speed - 1.0 and _path_turn_speed_log_s <= 0.0:
		_path_turn_speed_log_s = maxf(path_turn_speed_log_interval_s, 0.1)
		_debug_event("path_turn_speed_plan", "dist=%.1f angle=%.1f radius=%.1f limit=%.1f corner=%.1f desired=%.1f next=%s" % [
			corner_dist,
			rad_to_deg(turn_angle),
			turn_radius,
			speed_limit,
			corner_speed,
			desired_speed,
			str(next_point.snapped(Vector3.ONE * 0.1)),
		])
	return speed_limit


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
	var carrier_deck_ground := _get_carrier_reference_ground_y()
	if not is_nan(carrier_deck_ground):
		return carrier_deck_ground
	var current_ground := _get_ground_height_at_position(aircraft.global_position) if is_instance_valid(aircraft) else NAN
	if not is_nan(current_ground):
		return current_ground
	return aircraft.global_position.y - cruise_agl_m if is_instance_valid(aircraft) else 0.0


func _get_carrier_reference_ground_y() -> float:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return NAN
	var deck_y := _get_carrier_deck_y(carrier)
	if is_nan(deck_y):
		return NAN
	return deck_y - maxf(heightmap_path_carrier_deck_ground_offset_m, 0.0)


func _get_heightmap_route_agl_m() -> float:
	return maxf(heightmap_path_target_agl_m, maxf(min_terrain_clearance_m, 0.0))


func _get_heightmap_flight_ceiling_m(reference_ground: float = NAN) -> float:
	var ref_ground := reference_ground
	if is_nan(ref_ground):
		ref_ground = _get_heightmap_reference_ground_y()
	return ref_ground + maxf(heightmap_path_max_flight_above_reference_m, 0.0)


func _get_heightmap_max_route_terrain_y(reference_ground: float = NAN) -> float:
	var ref_ground := reference_ground
	if is_nan(ref_ground):
		ref_ground = _get_heightmap_reference_ground_y()
	var configured_ceiling := ref_ground + maxf(heightmap_path_max_terrain_above_reference_m, 0.0)
	var flight_limited_ceiling := _get_heightmap_flight_ceiling_m(ref_ground) - _get_heightmap_route_agl_m()
	return minf(configured_ceiling, flight_limited_ceiling)


func _clamp_heightmap_flight_altitude(altitude_m: float) -> float:
	var max_altitude := _get_heightmap_flight_ceiling_m()
	return minf(altitude_m, max_altitude)


func _rebuild_heightmap_path(current_pos: Vector3, goal: Vector3) -> void:
	var craft_name: String = aircraft.name if is_instance_valid(aircraft) else "unknown"
	_write_to_helicopter_paths_log("[%s] START SYNC PATH BUILD: start=%s -> goal=%s" % [
		craft_name,
		str(current_pos.snapped(Vector3.ONE * 0.1)),
		str(goal.snapped(Vector3.ONE * 0.1))
	])
	var start_ms := Time.get_ticks_msec()
	_heightmap_path_timer_s = maxf(heightmap_path_recompute_s, 0.2)
	_last_path_source = "none"
	var path_array: Array[Vector3] = _find_aerial_heightmap_path(current_pos, goal)
	_apply_heightmap_path_result(current_pos, goal, path_array, start_ms)



func _apply_heightmap_path_result(current_pos: Vector3, goal: Vector3, path_array: Array[Vector3], start_ms: int) -> void:
	var elevated_path := _elevate_aerial_path_points(current_pos, path_array)
	var elevated_count := elevated_path.size()
	elevated_path = _simplify_elevated_path_points(elevated_path)
	var simplified_count := elevated_path.size()
	_commit_heightmap_path_result(current_pos, goal, path_array, elevated_path, elevated_count, simplified_count, start_ms, "Success (sync rebuild)")



func _count_heightmap_path_levels(reference_ground: float) -> Dictionary:
	var result := {
		"ground": 0,
		"first": 0,
		"upper": 0,
	}
	var ground_band_ceiling := reference_ground + maxf(heightmap_path_ground_level_band_m, 0.0)
	var first_plateau_max_y := reference_ground + maxf(heightmap_path_first_plateau_max_m, heightmap_path_first_plateau_min_m)
	for point in _heightmap_path:
		var terrain_h := _get_ground_height_at_position(point)
		if is_nan(terrain_h):
			terrain_h = point.y - maxf(heightmap_path_target_agl_m, min_terrain_clearance_m)
		if terrain_h <= ground_band_ceiling:
			result["ground"] = int(result["ground"]) + 1
		elif terrain_h <= first_plateau_max_y:
			result["first"] = int(result["first"]) + 1
		else:
			result["upper"] = int(result["upper"]) + 1
	return result


func _commit_heightmap_path_result(
		current_pos: Vector3,
		goal: Vector3,
		path_array: Array[Vector3],
		elevated_path: Array[Vector3],
		elevated_count: int,
		simplified_count: int,
		start_ms: int,
		failure_reason: String = "",
		thread_ms: int = -1
) -> void:
	_heightmap_path_job.clear()
	var craft_name: String = aircraft.name if is_instance_valid(aircraft) else "?"
	var new_path: Array[Vector3] = []
	for point_variant in elevated_path:
		if point_variant is Vector3:
			var point := point_variant as Vector3
			if _flat_distance(current_pos, point) > maxf(heightmap_path_advance_radius_m * 0.5, 1.0):
				new_path.append(point)
	if new_path.is_empty():
		var reason := failure_reason
		if reason.is_empty():
			reason = "Elevated path was empty, or all path points were too close to the current position (advance radius clearance check)."
		_write_to_helicopter_paths_log("[%s] PATH COMMIT FAILED. Goal: %s. Reason: %s" % [
			craft_name,
			str(goal.snapped(Vector3.ONE * 0.1)),
			reason
		])
		_debug_event("path_failed", "source=%s keeping_old=%s goal=%s old_points=%d old_index=%d" % [
			_last_path_source,
			str(not _heightmap_path.is_empty()),
			str(goal.snapped(Vector3.ONE * 0.1)),
			_heightmap_path.size(),
			_heightmap_path_index,
		])
		_activate_path_fail_escape(current_pos, goal, _last_path_source)
		return

	_heightmap_path_goal = goal
	_heightmap_path = new_path
	_heightmap_path_index = 0
	_path_fail_escape_timer_s = 0.0
	_path_fail_escape_altitude_m = NAN
	_path_fail_escape_reason = ""
	var route_altitude := _clamp_heightmap_flight_altitude(
		_heightmap_path[0].y if not _heightmap_path.is_empty() else current_pos.y
	)
	var route_lookahead_altitude := _get_heightmap_upcoming_required_altitude(
		current_pos,
		maxf(terrain_climb_lookahead_m, heightmap_path_carrot_distance_m)
	)
	if not is_nan(route_lookahead_altitude):
		route_altitude = maxf(route_altitude, route_lookahead_altitude)
	_transit_cruise_altitude_m = route_altitude
	var reference_ground: float = _get_heightmap_reference_ground_y()
	var level_counts: Dictionary = _count_heightmap_path_levels(reference_ground)
	
	_write_to_helicopter_paths_log("[%s] PATH COMMIT SUCCESS. Goal: %s. Points: %d. Duration: %d ms (thread: %d ms). Source: %s. Reason: %s" % [
		craft_name,
		str(goal.snapped(Vector3.ONE * 0.1)),
		new_path.size(),
		Time.get_ticks_msec() - start_ms,
		thread_ms,
		_last_path_source,
		failure_reason if not failure_reason.is_empty() else "Success"
	])
	for i in range(new_path.size()):
		_write_to_helicopter_paths_log("  Waypoint [%d]: %s" % [i, str(new_path[i].snapped(Vector3.ONE * 0.1))])

	_debug_event("path", "source=%s ms=%d raw=%d elevated=%d simplified=%d points=%d ground=%d first=%d upper=%d pref=%.0f/%.2f/%.2f wall=%.1f/%.0f ref=%.1f terrain_ceiling=%.1f flight_ceiling=%.1f goal=%s first_pt=%s" % [
		_last_path_source,
		Time.get_ticks_msec() - start_ms,
		path_array.size(),
		elevated_count,
		simplified_count,
		_heightmap_path.size(),
		int(level_counts.get("ground", 0)),
		int(level_counts.get("first", 0)),
		int(level_counts.get("upper", 0)),
		heightmap_path_ground_route_penalty,
		heightmap_path_low_route_penalty,
		heightmap_path_top_level_penalty,
		heightmap_path_same_level_wall_risk_start_m,
		heightmap_path_same_level_wall_penalty,
		reference_ground,
		_get_heightmap_max_route_terrain_y(reference_ground),
		_get_heightmap_flight_ceiling_m(reference_ground),
		str(goal.snapped(Vector3.ONE * 0.1)),
		str(_heightmap_path[0].snapped(Vector3.ONE * 0.1)),
	])
	if debug_enabled:
		var ref_g: float = _get_heightmap_reference_ground_y()
		var levels: Dictionary = _count_heightmap_path_levels(ref_g)
		print("[helipath] craft=%s pts=%d ref=%.0f gnd=%d plt1=%d plt2=%d goal=(%.0f,%.0f,%.0f)" % [
			craft_name, _heightmap_path.size(), ref_g,
			int(levels.get("ground", 0)), int(levels.get("first", 0)), int(levels.get("upper", 0)),
			goal.x, goal.y, goal.z])



func _start_heightmap_path_job(current_pos: Vector3, goal: Vector3) -> void:
	if _path_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_path_task_id)
		_path_task_id = -1
		_path_job_data.clear()

	var craft_name: String = aircraft.name if is_instance_valid(aircraft) else "unknown"
	_write_to_helicopter_paths_log("[%s] START THREADED PATH JOB: start=%s -> goal=%s" % [
		craft_name,
		str(current_pos.snapped(Vector3.ONE * 0.1)),
		str(goal.snapped(Vector3.ONE * 0.1))
	])
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")
	if nav_grid == null:
		_write_to_helicopter_paths_log("[%s] THREADED PATH JOB ABORTED: TerrainNavGrid is null" % [craft_name])
		return

	var cols: int = int(nav_grid.get("_cols"))
	var rows: int = int(nav_grid.get("_rows"))
	var heights: PackedFloat32Array = nav_grid.get("_heights") as PackedFloat32Array
	var origin_x: float = float(nav_grid.get("_origin_x"))
	var origin_z: float = float(nav_grid.get("_origin_z"))
	var cell_size: float = maxf(float(nav_grid.get("cell_size_m")), 1.0)
	var impassable: float = float(nav_grid.get("IMPASSABLE"))
	if cols <= 0 or rows <= 0 or heights.is_empty():
		return

	_heightmap_path_timer_s = maxf(heightmap_path_recompute_s, 0.2)
	_last_path_source = "aerial_async"
	var dist_max := maxf(absf(current_pos.x - goal.x), absf(current_pos.z - goal.z))
	var pad := maxf(heightmap_path_search_padding_m, dist_max * 0.5)
	var gx_min: int = clampi(int(floor((minf(current_pos.x, goal.x) - pad - origin_x) / cell_size)), 0, cols - 1)
	var gz_min: int = clampi(int(floor((minf(current_pos.z, goal.z) - pad - origin_z) / cell_size)), 0, rows - 1)
	var gx_max: int = clampi(int(ceil((maxf(current_pos.x, goal.x) + pad - origin_x) / cell_size)), 0, cols - 1)
	var gz_max: int = clampi(int(ceil((maxf(current_pos.z, goal.z) + pad - origin_z) / cell_size)), 0, rows - 1)

	var start_cell := Vector2i(
		clampi(int((current_pos.x - origin_x) / cell_size), gx_min, gx_max),
		clampi(int((current_pos.z - origin_z) / cell_size), gz_min, gz_max)
	)
	var end_cell := Vector2i(
		clampi(int((goal.x - origin_x) / cell_size), gx_min, gx_max),
		clampi(int((goal.z - origin_z) / cell_size), gz_min, gz_max)
	)
	if start_cell == end_cell:
		var direct_path: Array[Vector3] = [goal]
		_commit_heightmap_path_result(current_pos, goal, direct_path, direct_path, 1, 1, Time.get_ticks_msec(), "Success (start == end)")
		return

	var reference_ground := _get_heightmap_reference_ground_y()
	var max_route_terrain_y := _get_heightmap_max_route_terrain_y(reference_ground)
	var flight_ceiling := _get_heightmap_flight_ceiling_m()
	var max_iterations := maxi((gx_max - gx_min + 1) * (gz_max - gz_min + 1) * 3, 20000)

	var grid_snapshot := {
		"cols": cols,
		"rows": rows,
		"heights": heights,
		"origin_x": origin_x,
		"origin_z": origin_z,
		"cell_size": cell_size,
		"impassable": impassable,
		
		"query_cols": int(nav_grid.get("_query_cols")),
		"query_rows": int(nav_grid.get("_query_rows")),
		"query_heights": nav_grid.get("_query_heights") as PackedFloat32Array,
		"query_height_variation": nav_grid.get("_query_height_variation") as PackedFloat32Array,
		"query_max_heights": nav_grid.get("_query_max_heights") as PackedFloat32Array,
		"query_origin_x": float(nav_grid.get("_query_origin_x")),
		"query_origin_z": float(nav_grid.get("_query_origin_z")),
		"query_cell_size": maxf(float(nav_grid.get("query_cell_size_m")), 1.0),
	}

	var params := {
		"heightmap_path_max_edge_risk_m": heightmap_path_max_edge_risk_m,
		"heightmap_path_edge_risk_penalty": heightmap_path_edge_risk_penalty,
		"heightmap_path_mountain_buffer_cells": heightmap_path_mountain_buffer_cells,
		"heightmap_path_mountain_avoidance_m": heightmap_path_mountain_avoidance_m,
		"heightmap_path_max_step_climb_m": heightmap_path_max_step_climb_m,
		"heightmap_path_altitude_penalty": heightmap_path_altitude_penalty,
		"heightmap_path_climb_penalty": heightmap_path_climb_penalty,
		"heightmap_path_high_terrain_penalty": heightmap_path_high_terrain_penalty,
		"heightmap_path_same_level_wall_risk_start_m": heightmap_path_same_level_wall_risk_start_m,
		"heightmap_path_same_level_wall_penalty": heightmap_path_same_level_wall_penalty,
		"heightmap_path_ground_route_penalty": heightmap_path_ground_route_penalty,
		"heightmap_path_low_route_penalty": heightmap_path_low_route_penalty,
		"heightmap_path_top_level_penalty": heightmap_path_top_level_penalty,
		"heightmap_path_upper_level_penalty": heightmap_path_upper_level_penalty,
		"heightmap_path_level_change_penalty": heightmap_path_level_change_penalty,
		"heightmap_path_target_agl_m": heightmap_path_target_agl_m,
		"min_terrain_clearance_m": min_terrain_clearance_m,
		"heightmap_path_carrot_distance_m": heightmap_path_carrot_distance_m,
		"heightmap_path_insert_spacing_m": heightmap_path_insert_spacing_m,
		"heightmap_path_simplify_altitude_error_m": heightmap_path_simplify_altitude_error_m,
		"terrain_climb_lookahead_m": terrain_climb_lookahead_m,
		"terrain_sample_spacing_m": terrain_sample_spacing_m,
		"heightmap_path_simplify_enabled": heightmap_path_simplify_enabled,
		"min_altitude": -1000.0,
		"max_altitude": 10000.0,
		"route_terrain_ceiling": max_route_terrain_y,
		"flight_ceiling": flight_ceiling,
	}

	_path_job_data = {
		"start_ms": Time.get_ticks_msec(),
		"current_pos": current_pos,
		"goal": goal,
		"gx_min": gx_min,
		"gz_min": gz_min,
		"gx_max": gx_max,
		"gz_max": gz_max,
		"start_cell": start_cell,
		"end_cell": end_cell,
		"reference_ground": reference_ground,
		"max_route_terrain_y": max_route_terrain_y,
		"max_iterations": max_iterations,
		"grid": grid_snapshot,
		"params": params,
		"result": {}
	}

	_path_task_id = WorkerThreadPool.add_task(func():
		_run_threaded_pathfinding_job(_path_job_data)
	)

	_debug_event("path_job", "started_threaded goal=%s window=%dx%d" % [
		str(goal.snapped(Vector3.ONE * 0.1)),
		gx_max - gx_min + 1,
		gz_max - gz_min + 1
	])


static func _run_threaded_pathfinding_job(data: Dictionary) -> void:
	var start_time := Time.get_ticks_msec()
	var current_pos: Vector3 = data.current_pos
	var goal: Vector3 = data.goal
	var params: Dictionary = data.params
	var grid: Dictionary = data.grid
	
	var cell_size: float = grid.cell_size
	var origin_x: float = grid.origin_x
	var origin_z: float = grid.origin_z
	var heights: PackedFloat32Array = grid.heights
	var cols: int = grid.cols
	var rows: int = grid.rows
	var impassable: float = grid.impassable
	
	var gx_min: int = data.gx_min
	var gz_min: int = data.gz_min
	var gx_max: int = data.gx_max
	var gz_max: int = data.gz_max
	var start_cell: Vector2i = data.start_cell
	var end_cell: Vector2i = data.end_cell
	var reference_ground: float = data.reference_ground
	var max_route_terrain_y: float = data.max_route_terrain_y
	var route_floor: float = reference_ground
	
	var max_iterations: int = data.max_iterations
	
	var open: Array = []
	_thread_heap_push_path_node(open, [_thread_aerial_h(start_cell, end_cell, cell_size), start_cell.x, start_cell.y])
	var g_score: Dictionary = { start_cell: 0.0 }
	var came_from: Dictionary = {}
	var iterations := 0
	var found_path := false
	
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	
	while not open.is_empty() and iterations < max_iterations:
		iterations += 1
		var entry: Array = _thread_heap_pop_path_node(open)
		var cur := Vector2i(int(entry[1]), int(entry[2]))
		
		if cur == end_cell:
			found_path = true
			break
			
		var cur_h := _thread_heightmap_cell_height(heights, cols, cur.x, cur.y, impassable)
		if cur_h <= impassable * 0.5:
			continue
			
		for dir in dirs:
			var nb := cur + dir
			if nb.x < gx_min or nb.x > gx_max or nb.y < gz_min or nb.y > gz_max:
				continue
			var nb_h := _thread_heightmap_cell_height(heights, cols, nb.x, nb.y, impassable)
			if nb_h <= impassable * 0.5:
				continue
				
			var nb_world := Vector3(origin_x + float(nb.x) * cell_size, nb_h, origin_z + float(nb.y) * cell_size)
			var nb_edge_risk := _thread_sample_query_edge_risk(grid, nb_world.x, nb_world.z)
			var max_allowed_edge_risk: float = maxf(float(params.get("heightmap_path_max_edge_risk_m", 5.0)), 0.0)
			if nb_edge_risk >= INF:
				continue
				
			var buf := maxi(int(params.get("heightmap_path_mountain_buffer_cells", 0)), 0)
			if buf > 0:
				var mountain_ceiling := reference_ground + maxf(float(params.get("heightmap_path_mountain_avoidance_m", 185.0)), 0.0)
				if _thread_heightmap_has_nearby_high_terrain(heights, cols, rows, nb.x, nb.y, mountain_ceiling, impassable, buf):
					continue
					
			if nb_h > max_route_terrain_y:
				continue
				
			var max_step_climb: float = float(params.get("heightmap_path_max_step_climb_m", 0.0))
			if max_step_climb > 0.0 and nb != end_cell and maxf(nb_h - cur_h, 0.0) > max_step_climb:
				continue
				
			var diagonal := dir.x != 0 and dir.y != 0
			if diagonal:
				var side_a := Vector2i(cur.x + dir.x, cur.y)
				var side_b := Vector2i(cur.x, cur.y + dir.y)
				if _thread_heightmap_cell_blocked_for_aerial_path(heights, cols, side_a, impassable, max_route_terrain_y) \
						or _thread_heightmap_cell_blocked_for_aerial_path(heights, cols, side_b, impassable, max_route_terrain_y):
					continue
					
			var step_dist := cell_size * (1.4142135 if diagonal else 1.0)
			var altitude_cost := maxf(nb_h - reference_ground, 0.0) * float(params.get("heightmap_path_altitude_penalty", 0.05))
			var climb_cost := maxf(nb_h - cur_h, 0.0) * float(params.get("heightmap_path_climb_penalty", 1.5))
			var high_terrain_cost := maxf(nb_h - route_floor, 0.0) * float(params.get("heightmap_path_high_terrain_penalty", 0.0))
			var edge_cost := minf(nb_edge_risk, max_allowed_edge_risk) * maxf(float(params.get("heightmap_path_edge_risk_penalty", 50.0)), 0.0)
			
			var same_level_wall_cost := 0.0
			var cell_clearance: float = float(params.get("heightmap_path_target_agl_m", 50.0))
			var max_h_local := nb_h + nb_edge_risk
			
			var sample_max := _thread_sample_query_max_height(grid, nb_world.x, nb_world.z)
			if sample_max < INF and not is_nan(sample_max) and sample_max > -500000.0:
				max_h_local = sample_max
				
			if max_h_local > nb_h + cell_clearance - 5.0:
				same_level_wall_cost = _thread_get_same_level_wall_cost(params, nb_edge_risk)
				
			var low_route_cost := 0.0
			var first_plateau_min_y := reference_ground + maxf(float(params.get("heightmap_path_first_plateau_min_m", 40.0)), 0.0)
			if nb_h < first_plateau_min_y:
				low_route_cost = (
					maxf(float(params.get("heightmap_path_ground_route_penalty", 0.0)), 0.0)
					+ (first_plateau_min_y - nb_h) * maxf(float(params.get("heightmap_path_low_route_penalty", 0.0)), 0.0)
				)
				
			var top_level_cost := 0.0
			var first_plateau_max_y := reference_ground + maxf(float(params.get("heightmap_path_first_plateau_max_m", 180.0)), 0.0)
			if nb_h > first_plateau_max_y:
				top_level_cost = (nb_h - first_plateau_max_y) * maxf(float(params.get("heightmap_path_top_level_penalty", 0.1)), 0.0)
				
			var level_cost := 0.0
			if nb_h > first_plateau_max_y:
				level_cost += maxf(float(params.get("heightmap_path_upper_level_penalty", 15.0)), 0.0)
				
			var ground_band_ceiling := reference_ground + maxf(float(params.get("heightmap_path_ground_level_band_m", 35.0)), 0.0)
			var cur_ground_level := cur_h <= ground_band_ceiling
			var nb_ground_level := nb_h <= ground_band_ceiling
			if cur_ground_level != nb_ground_level and nb_ground_level:
				level_cost += maxf(float(params.get("heightmap_path_level_change_penalty", 2.0)), 0.0)
				
			var tg: float = g_score.get(cur, INF) + step_dist + altitude_cost + climb_cost + high_terrain_cost + edge_cost + same_level_wall_cost + low_route_cost + top_level_cost + level_cost
			if tg < g_score.get(nb, INF):
				came_from[nb] = cur
				g_score[nb] = tg
				_thread_heap_push_path_node(open, [tg + _thread_aerial_h(nb, end_cell, cell_size), nb.x, nb.y])

	var raw_path: Array[Vector3] = []
	if found_path:
		raw_path = _thread_rebuild_aerial_heightmap_path(came_from, end_cell, heights, cols, origin_x, origin_z, cell_size)
	else:
		var empty_vec3_array: Array[Vector3] = []
		data.result = {
			"success": false,
			"current_pos": current_pos,
			"goal": goal,
			"raw_path": empty_vec3_array,
			"elevated_path": empty_vec3_array,
			"final_path": empty_vec3_array,
			"iterations": iterations,
			"elevated_count": 0,
			"simplified_count": 0,
			"reason": "reached iterations limit" if iterations >= max_iterations else "open list empty",
			"start_ms": data.start_ms,
			"elapsed_ms": Time.get_ticks_msec() - start_time
		}
		return

	var elevated_path: Array[Vector3] = []
	var segment_start := current_pos
	var previous_sample := current_pos
	var route_agl: float = float(params.get("heightmap_path_target_agl_m", 50.0))
	var flight_ceiling: float = float(params.get("flight_ceiling", 2100.0))
	var postprocess_success := true
	var reject_reason := ""

	for point in raw_path:
		var flat_segment := Vector3(point.x - segment_start.x, 0.0, point.z - segment_start.z)
		var segment_len := flat_segment.length()
		var spacing: float = maxf(float(params.get("heightmap_path_insert_spacing_m", 100.0)), 1.0)
		var steps := maxi(int(ceil(segment_len / spacing)), 1)
		
		var inner_success := true
		for step in range(1, steps + 1):
			var t := float(step) / float(steps)
			var sample_pos := segment_start.lerp(point, t)
			var terrain_height := _thread_get_ground_height_at_position(grid, sample_pos)
			if is_nan(terrain_height):
				terrain_height = lerpf(segment_start.y, point.y, t)
			var corridor_height := _thread_sample_max_terrain_height_along_path(grid, params, previous_sample, sample_pos)
			if not is_nan(corridor_height):
				terrain_height = maxf(terrain_height, corridor_height)
			if terrain_height > max_route_terrain_y + 0.5 or terrain_height + route_agl > flight_ceiling + 0.5:
				reject_reason = "Postprocess rejected segment at %s: terrain_height=%.1f (max_route_terrain_y=%.1f), target_alt=%.1f (flight_ceiling=%.1f)" % [
					str(sample_pos.snapped(Vector3.ONE * 0.1)),
					terrain_height,
					max_route_terrain_y,
					terrain_height + route_agl,
					flight_ceiling
				]
				inner_success = false
				break
			var elevated_point := Vector3(
				sample_pos.x,
				clampf(terrain_height + route_agl, float(params.get("min_altitude", -1000.0)), float(params.get("max_altitude", 10000.0))),
				sample_pos.z
			)
			var dist_to_prev := 0.0
			if not elevated_path.is_empty():
				var prev_pt := elevated_path[elevated_path.size() - 1]
				dist_to_prev = Vector2(prev_pt.x - elevated_point.x, prev_pt.z - elevated_point.z).length()
			if elevated_path.is_empty() or dist_to_prev > 1.0:
				elevated_path.append(elevated_point)
			previous_sample = sample_pos
		if not inner_success:
			postprocess_success = false
			break
		segment_start = point

	if not postprocess_success:
		var empty_vec3_array: Array[Vector3] = []
		data.result = {
			"success": false,
			"current_pos": current_pos,
			"goal": goal,
			"raw_path": raw_path,
			"elevated_path": elevated_path,
			"final_path": empty_vec3_array,
			"iterations": iterations,
			"elevated_count": elevated_path.size(),
			"simplified_count": 0,
			"reason": reject_reason,
			"start_ms": data.start_ms,
			"elapsed_ms": Time.get_ticks_msec() - start_time
		}
		return

	var final_path: Array[Vector3] = []
	if not bool(params.get("heightmap_path_simplify_enabled", true)) or elevated_path.size() <= 2:
		final_path = elevated_path
	else:
		final_path.append(elevated_path[0])
		var anchor_index := 0
		var candidate_index := elevated_path.size() - 1
		while anchor_index < elevated_path.size() - 1:
			if candidate_index <= anchor_index:
				candidate_index = anchor_index + 1
			if candidate_index >= elevated_path.size():
				candidate_index = elevated_path.size() - 1
				
			var can_use_candidate := candidate_index == anchor_index + 1 \
					or _thread_can_skip_elevated_path_range(grid, params, elevated_path, anchor_index, candidate_index)
			if can_use_candidate:
				var candidate: Vector3 = elevated_path[candidate_index]
				var dist_to_prev := 0.0
				if not final_path.is_empty():
					var prev_pt := final_path[final_path.size() - 1]
					dist_to_prev = Vector2(prev_pt.x - candidate.x, prev_pt.z - candidate.z).length()
				if final_path.is_empty() or dist_to_prev > 1.0:
					final_path.append(candidate)
				anchor_index = candidate_index
				candidate_index = elevated_path.size() - 1
			else:
				candidate_index -= 1

	data.result = {
		"success": true,
		"current_pos": current_pos,
		"goal": goal,
		"raw_path": raw_path,
		"elevated_path": elevated_path,
		"final_path": final_path,
		"iterations": iterations,
		"elevated_count": elevated_path.size(),
		"simplified_count": final_path.size(),
		"reason": "Success (threaded)",
		"start_ms": data.start_ms,
		"elapsed_ms": Time.get_ticks_msec() - start_time
	}


static func _thread_heap_push_path_node(heap: Array, entry: Array) -> void:
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


static func _thread_heap_pop_path_node(heap: Array) -> Array:
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


static func _thread_aerial_h(a: Vector2i, b: Vector2i, cell_size: float) -> float:
	const HEURISTIC_WEIGHT := 1.5
	return Vector2(a.x - b.x, a.y - b.y).length() * cell_size * HEURISTIC_WEIGHT


static func _thread_heightmap_cell_height(heights: PackedFloat32Array, cols: int, gx: int, gz: int, impassable: float) -> float:
	var idx := gz * cols + gx
	if idx < 0 or idx >= heights.size():
		return impassable
	return heights[idx]


static func _thread_heightmap_cell_blocked_for_aerial_path(
		heights: PackedFloat32Array,
		cols: int,
		cell: Vector2i,
		impassable: float,
		max_route_terrain_y: float
) -> bool:
	var h := _thread_heightmap_cell_height(heights, cols, cell.x, cell.y, impassable)
	if h <= impassable * 0.5 or h > max_route_terrain_y:
		return true
	return false


static func _thread_heightmap_has_nearby_high_terrain(
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
			var h := _thread_heightmap_cell_height(heights, cols, sample_x, sample_z, impassable)
			if h > mountain_ceiling:
				return true
	return false


static func _thread_rebuild_aerial_heightmap_path(
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
	return path


static func _thread_get_same_level_wall_cost(params: Dictionary, edge_risk_m: float) -> float:
	if edge_risk_m >= INF:
		return INF
	var risk_start := maxf(float(params.get("heightmap_path_same_level_wall_risk_start_m", 8.0)), 0.0)
	var excess_risk := maxf(edge_risk_m - risk_start, 0.0)
	return excess_risk * excess_risk * maxf(float(params.get("heightmap_path_same_level_wall_penalty", 50.0)), 0.0)


static func _thread_sample_query_height_from_array(grid: Dictionary, values: PackedFloat32Array, wx: float, wz: float, use_max_corners: bool) -> float:
	var q_cols: int = grid.query_cols
	var q_rows: int = grid.query_rows
	var impassable: float = grid.impassable
	if values.is_empty() or q_cols <= 0 or q_rows <= 0:
		return INF if use_max_corners else impassable
	var q_cell: float = grid.query_cell_size
	var q_origin_x: float = grid.query_origin_x
	var q_origin_z: float = grid.query_origin_z
	var fx: float = (wx - q_origin_x) / q_cell
	var fz: float = (wz - q_origin_z) / q_cell
	var gx0 := int(fx)
	var gz0 := int(fz)
	if gx0 < 0 or gx0 >= q_cols - 1 or gz0 < 0 or gz0 >= q_rows - 1:
		var gx := clampi(gx0, 0, q_cols - 1)
		var gz := clampi(gz0, 0, q_rows - 1)
		return values[gz * q_cols + gx]
	var tx: float = fx - float(gx0)
	var tz: float = fz - float(gz0)
	var v00: float = values[gz0 * q_cols + gx0]
	var v10: float = values[gz0 * q_cols + (gx0 + 1)]
	var v01: float = values[(gz0 + 1) * q_cols + gx0]
	var v11: float = values[(gz0 + 1) * q_cols + (gx0 + 1)]
	if use_max_corners:
		return maxf(maxf(v00, v10), maxf(v01, v11))
	if v00 <= impassable * 0.5 or v10 <= impassable * 0.5 or v01 <= impassable * 0.5 or v11 <= impassable * 0.5:
		return v00 if v00 > impassable * 0.5 else impassable
	return lerp(lerp(v00, v10, tx), lerp(v01, v11, tx), tz)


static func _thread_sample_query_height(grid: Dictionary, wx: float, wz: float) -> float:
	return _thread_sample_query_height_from_array(grid, grid.query_heights, wx, wz, false)


static func _thread_sample_query_edge_risk(grid: Dictionary, wx: float, wz: float) -> float:
	return _thread_sample_query_height_from_array(grid, grid.query_height_variation, wx, wz, true)


static func _thread_sample_query_max_height(grid: Dictionary, wx: float, wz: float) -> float:
	return _thread_sample_query_height_from_array(grid, grid.query_max_heights, wx, wz, true)


static func _thread_sample_height(grid: Dictionary, wx: float, wz: float) -> float:
	var cols: int = grid.cols
	var rows: int = grid.rows
	var heights: PackedFloat32Array = grid.heights
	var impassable: float = grid.impassable
	var origin_x: float = grid.origin_x
	var origin_z: float = grid.origin_z
	var cell_size: float = grid.cell_size
	
	var fx: float = (wx - origin_x) / cell_size
	var fz: float = (wz - origin_z) / cell_size
	var gx0 := int(fx)
	var gz0 := int(fz)
	if gx0 < 0 or gx0 >= cols - 1 or gz0 < 0 or gz0 >= rows - 1:
		var gx := clampi(gx0, 0, cols - 1)
		var gz := clampi(gz0, 0, rows - 1)
		return heights[gz * cols + gx]
	var tx: float = fx - float(gx0)
	var tz: float = fz - float(gz0)
	var h00: float = heights[gz0 * cols + gx0]
	var h10: float = heights[gz0 * cols + (gx0 + 1)]
	var h01: float = heights[(gz0 + 1) * cols + gx0]
	var h11: float = heights[(gz0 + 1) * cols + (gx0 + 1)]
	if h00 <= impassable * 0.5 or h10 <= impassable * 0.5 or h01 <= impassable * 0.5 or h11 <= impassable * 0.5:
		return h00 if h00 > impassable * 0.5 else impassable
	return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)


static func _thread_get_max_height_in_radius(grid: Dictionary, wx: float, wz: float, radius_m: float) -> float:
	var center_x := int((wx - grid.query_origin_x) / grid.query_cell_size)
	var center_z := int((wz - grid.query_origin_z) / grid.query_cell_size)
	var radius_cells: int = maxi(int(ceil(maxf(radius_m, 0.0) / grid.query_cell_size)), 1)
	var max_h: float = -INF
	var sample_radius_sq: float = pow(radius_m + grid.query_cell_size * 0.75, 2.0)
	var found := false
	for dz in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var nx: int = center_x + dx
			var nz: int = center_z + dz
			if nx < 0 or nx >= grid.query_cols or nz < 0 or nz >= grid.query_rows:
				continue
			var sample_dx: float = float(dx) * grid.query_cell_size
			var sample_dz: float = float(dz) * grid.query_cell_size
			if sample_dx * sample_dx + sample_dz * sample_dz > sample_radius_sq:
				continue
			var idx: int = nz * grid.query_cols + nx
			var h: float = grid.query_heights[idx]
			if h > grid.impassable * 0.5:
				max_h = maxf(max_h, h)
				found = true
	return max_h if found else grid.impassable


static func _thread_get_ground_height_at_position(grid: Dictionary, world_pos: Vector3) -> float:
	var query_h := _thread_sample_query_height(grid, world_pos.x, world_pos.z)
	if query_h > -500000.0:
		return query_h
	var grid_h := _thread_sample_height(grid, world_pos.x, world_pos.z)
	if grid_h > -500000.0:
		return grid_h
	return NAN


static func _thread_sample_max_terrain_height_along_path(grid: Dictionary, params: Dictionary, from_pos: Vector3, to_pos: Vector3) -> float:
	var distance := Vector2(from_pos.x - to_pos.x, from_pos.z - to_pos.z).length()
	var spacing: float = maxf(float(params.get("terrain_sample_spacing_m", 20.0)), 1.0)
	var sample_count: int = maxi(int(ceil(distance / spacing)), 1)
	var max_height: float = -INF
	var found_height := false
	for i in range(sample_count + 1):
		var t: float = float(i) / float(sample_count)
		var sample_pos := from_pos.lerp(to_pos, t)
		var h := _thread_get_ground_height_at_position(grid, sample_pos)
		if is_nan(h):
			continue
		max_height = maxf(max_height, h)
		found_height = true
	return max_height if found_height else NAN


static func _thread_has_clear_transit_segment(grid: Dictionary, params: Dictionary, a: Vector3, b: Vector3) -> bool:
	var distance := Vector2(a.x - b.x, a.z - b.z).length()
	if distance <= 1.0:
		return true
	
	var sample_spacing := 20.0
	var sample_count: int = maxi(int(ceil(distance / sample_spacing)), 1)
	
	var path_clearance: float = float(params.get("heightmap_path_target_agl_m", 50.0))
	var route_terrain_ceiling: float = float(params.get("route_terrain_ceiling", 2000.0))

	for i in range(sample_count + 1):
		var t: float = float(i) / float(sample_count)
		var sample_pos := a.lerp(b, t)
		
		var ground_h := _thread_get_ground_height_at_position(grid, sample_pos)
		if is_nan(ground_h):
			ground_h = lerpf(a.y, b.y, t) - path_clearance
		
		if ground_h > route_terrain_ceiling:
			return false
		
		if sample_pos.y < ground_h + path_clearance:
			return false
		
		var max_h_50m := _thread_get_max_height_in_radius(grid, sample_pos.x, sample_pos.z, 50.0)
		if max_h_50m > -500000.0:
			if sample_pos.y < max_h_50m + 25.0:
				return false

	return true


static func _thread_can_skip_elevated_path_range(grid: Dictionary, params: Dictionary, path: Array, start_index: int, end_index: int) -> bool:
	if end_index <= start_index + 1:
		return true
	if start_index < 0 or end_index >= path.size():
		return false
	var start_variant: Variant = path[start_index]
	var end_variant: Variant = path[end_index]
	if not (start_variant is Vector3) or not (end_variant is Vector3):
		return false
	var start_point := start_variant as Vector3
	var end_point := end_variant as Vector3
	if not _thread_has_clear_transit_segment(grid, params, start_point, end_point):
		return false

	var span := Vector2(start_point.x - end_point.x, start_point.z - end_point.z).length()
	if span <= 1.0:
		return true

	var altitude_error_limit: float = float(params.get("heightmap_path_simplify_altitude_error_m", 8.0))
	var max_horizontal_deviation := 80.0

	for i in range(start_index + 1, end_index):
		var middle_variant: Variant = path[i]
		if not (middle_variant is Vector3):
			return false
		var middle := middle_variant as Vector3
		
		var horiz_dev := _thread_perpendicular_distance_2d(middle, start_point, end_point)
		if horiz_dev > max_horizontal_deviation:
			return false

		var t := clampf(Vector2(start_point.x - middle.x, start_point.z - middle.z).length() / span, 0.0, 1.0)
		var expected_altitude := lerpf(start_point.y, end_point.y, t)
		if middle.y > expected_altitude + altitude_error_limit:
			return false
	return true


static func _thread_perpendicular_distance_2d(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.001:
		return ap.length()
	var t := clampf(ap.dot(ab) / ab_len_sq, 0.0, 1.0)
	var projection := Vector2(a.x, a.z) + ab * t
	return Vector2(p.x - projection.x, p.z - projection.y).length()


func _activate_path_fail_escape(current_pos: Vector3, goal: Vector3, reason: String) -> void:
	if state != State.LOW_LEVEL_TRANSIT:
		return
	_path_fail_escape_timer_s = maxf(path_fail_escape_time_s, 0.0)
	_path_fail_escape_reason = reason
	_heightmap_path_timer_s = minf(_heightmap_path_timer_s, maxf(path_fail_escape_repath_s, 0.2))

	var local_ground := _get_ground_height_at_position(current_pos)
	var route_high := _sample_max_terrain_height_along_path(current_pos, goal)
	var base_altitude := current_pos.y
	if not is_nan(local_ground):
		base_altitude = maxf(base_altitude, local_ground + _get_transit_clearance_agl())
	if not is_nan(route_high):
		base_altitude = maxf(base_altitude, route_high + _get_transit_clearance_agl())
	_path_fail_escape_altitude_m = _clamp_heightmap_flight_altitude(
		base_altitude + maxf(path_fail_escape_climb_margin_m, 0.0)
	)
	_debug_event("path_fail_escape", "reason=%s time=%.1f speed=%.1f target_alt=%.1f route_high=%.1f goal=%s" % [
		reason,
		_path_fail_escape_timer_s,
		path_fail_escape_speed_mps,
		_path_fail_escape_altitude_m,
		route_high,
		str(goal.snapped(Vector3.ONE * 0.1)),
	])


func _update_path_fail_escape_timer(delta: float) -> void:
	if _path_fail_escape_timer_s <= 0.0:
		return
	_path_fail_escape_timer_s = maxf(_path_fail_escape_timer_s - delta, 0.0)
	if _path_fail_escape_timer_s <= 0.0:
		_path_fail_escape_altitude_m = NAN
		_path_fail_escape_reason = ""


func _is_path_fail_escape_active() -> bool:
	return _path_fail_escape_timer_s > 0.0 and not is_nan(_path_fail_escape_altitude_m)


func _get_path_fail_escape_speed(desired_speed: float) -> float:
	if not _is_path_fail_escape_active():
		return desired_speed
	return minf(desired_speed, maxf(path_fail_escape_speed_mps, 0.0))


func _get_current_leg_target_speed_mps(fallback_speed_mps: float) -> float:
	var speed := fallback_speed_mps
	if not is_nan(_target_speed_mps) and _target_speed_mps > 0.0:
		speed = _target_speed_mps
	speed = minf(speed, maxf(max_speed_mps, 0.0))
	return maxf(speed, 0.0)


func _get_path_fail_escape_altitude(current_pos: Vector3, goal: Vector3, fallback_ground: float) -> float:
	if not is_nan(_path_fail_escape_altitude_m):
		return _path_fail_escape_altitude_m
	var base_altitude := current_pos.y
	if not is_nan(fallback_ground):
		base_altitude = maxf(base_altitude, fallback_ground + _get_transit_clearance_agl())
	var route_high := _sample_max_terrain_height_along_path(current_pos, goal)
	if not is_nan(route_high):
		base_altitude = maxf(base_altitude, route_high + _get_transit_clearance_agl())
	_path_fail_escape_altitude_m = _clamp_heightmap_flight_altitude(
		base_altitude + maxf(path_fail_escape_climb_margin_m, 0.0)
	)
	return _path_fail_escape_altitude_m


func _elevate_aerial_path_points(current_pos: Vector3, path: Array[Vector3]) -> Array[Vector3]:
	var elevated: Array[Vector3] = []
	var segment_start := current_pos
	var route_agl := _get_heightmap_route_agl_m()
	var flight_ceiling := _get_heightmap_flight_ceiling_m()
	var route_terrain_ceiling := _get_heightmap_max_route_terrain_y()
	for point in path:
		var flat_segment := Vector3(point.x - segment_start.x, 0.0, point.z - segment_start.z)
		var segment_len := flat_segment.length()
		var steps := maxi(int(ceil(segment_len / maxf(heightmap_path_insert_spacing_m, 1.0))), 1)
		var previous_sample := segment_start
		for step in range(1, steps + 1):
			var t := float(step) / float(steps)
			var sample_pos := segment_start.lerp(point, t)
			var terrain_height := _get_ground_height_at_position(sample_pos)
			if is_nan(terrain_height):
				terrain_height = lerpf(segment_start.y, point.y, t)
			var corridor_height := _sample_max_terrain_height_along_path(previous_sample, sample_pos)
			if not is_nan(corridor_height):
				terrain_height = maxf(terrain_height, corridor_height)
			if terrain_height > route_terrain_ceiling + 0.5 or terrain_height + route_agl > flight_ceiling + 0.5:
				return []
			var elevated_point := Vector3(
				sample_pos.x,
				_clamp_heightmap_flight_altitude(terrain_height + route_agl),
				sample_pos.z
			)
			if elevated.is_empty() or _flat_distance(elevated[elevated.size() - 1], elevated_point) > 1.0:
				elevated.append(elevated_point)
			previous_sample = sample_pos
		segment_start = point
	return elevated


func _simplify_elevated_path_points(path: Array[Vector3]) -> Array[Vector3]:
	if not heightmap_path_simplify_enabled or path.size() <= 2:
		return path
	var simplified: Array[Vector3] = [path[0]]
	var anchor_index := 0
	while anchor_index < path.size() - 1:
		var selected_index := anchor_index + 1
		for candidate_index in range(path.size() - 1, anchor_index, -1):
			if candidate_index == anchor_index + 1 or _can_skip_elevated_path_range(path, anchor_index, candidate_index):
				selected_index = candidate_index
				break
		simplified.append(path[selected_index])
		anchor_index = selected_index
	return simplified


func _perpendicular_distance_2d(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.001:
		return ap.length()
	var t := clampf(ap.dot(ab) / ab_len_sq, 0.0, 1.0)
	var projection := Vector2(a.x, a.z) + ab * t
	return Vector2(p.x - projection.x, p.z - projection.y).length()


func _can_skip_elevated_path_range(path: Array, start_index: int, end_index: int) -> bool:
	if end_index <= start_index + 1:
		return true
	if start_index < 0 or end_index >= path.size():
		return false
	var start_variant: Variant = path[start_index]
	var end_variant: Variant = path[end_index]
	if not (start_variant is Vector3) or not (end_variant is Vector3):
		return false
	var start_point := start_variant as Vector3
	var end_point := end_variant as Vector3
	if not _has_clear_transit_segment(start_point, end_point):
		return false

	var span := _flat_distance(start_point, end_point)
	if span <= 1.0:
		return true

	# Keep waypoints at significant altitude changes — the helicopter needs
	# them to know it must climb before flying toward the next point.
	# Check if any intermediate waypoint is significantly higher than the
	# linear interpolation between start and end — that means there's a hill
	# that requires a dedicated climb waypoint.
	var altitude_error_limit := maxf(heightmap_path_simplify_altitude_error_m, 0.0)
	
	# Horizontal turn/deviation limit. Keep waypoints if they deviate from the straight line by more than 80 meters.
	# On flat terrain the A* grid (40m cells) creates zigzag paths that deviate ~28-56m from the straight line;
	# a limit of 80m collapses these meaningless grid artifacts while preserving real detours around obstacles.
	var max_horizontal_deviation := 80.0

	for i in range(start_index + 1, end_index):
		var middle_variant: Variant = path[i]
		if not (middle_variant is Vector3):
			return false
		var middle := middle_variant as Vector3
		
		# Check horizontal deviation from the straight segment
		var horiz_dev := _perpendicular_distance_2d(middle, start_point, end_point)
		if horiz_dev > max_horizontal_deviation:
			return false

		var t := clampf(_flat_distance(start_point, middle) / span, 0.0, 1.0)
		var expected_altitude := lerpf(start_point.y, end_point.y, t)
		if middle.y > expected_altitude + altitude_error_limit:
			return false
	return true


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
	var craft_name: String = aircraft.name if is_instance_valid(aircraft) else "unknown"
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")
	if nav_grid == null:
		_write_to_helicopter_paths_log("[%s] A* search aborted: TerrainNavGrid is null" % [craft_name])
		return []

	var cols: int = int(nav_grid.get("_cols"))
	var rows: int = int(nav_grid.get("_rows"))
	var heights: PackedFloat32Array = nav_grid.get("_heights") as PackedFloat32Array
	var origin_x: float = float(nav_grid.get("_origin_x"))
	var origin_z: float = float(nav_grid.get("_origin_z"))
	var cell_size: float = maxf(float(nav_grid.get("cell_size_m")), 1.0)
	var impassable: float = float(nav_grid.get("IMPASSABLE"))
	if cols <= 0 or rows <= 0 or heights.is_empty():
		_write_to_helicopter_paths_log("[%s] A* search aborted: grid dimensions are invalid" % [craft_name])
		return []
	_last_path_source = "aerial"

	var dist_max := maxf(absf(current_pos.x - goal.x), absf(current_pos.z - goal.z))
	var pad := maxf(heightmap_path_search_padding_m, dist_max * 0.5)
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
		_write_to_helicopter_paths_log("[%s] A* search bypassed: start == end (%s)" % [craft_name, start])
		return [goal]

	var reference_ground := _get_heightmap_reference_ground_y()
	var max_route_terrain_y := _get_heightmap_max_route_terrain_y(reference_ground)
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
	var max_iterations := maxi((gx_max - gx_min + 1) * (gz_max - gz_min + 1) * 2, 10000)
	while not open.is_empty() and iterations < max_iterations:
		iterations += 1
		var entry: Array = _heap_pop_path_node(open)
		var cur := Vector2i(int(entry[1]), int(entry[2]))
		if cur == end:
			_write_to_helicopter_paths_log("[%s] A* search success: found path to end in %d iterations (max=%d)" % [craft_name, iterations, max_iterations])
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
			var max_allowed_edge_risk := maxf(heightmap_path_max_edge_risk_m, 0.0)
			if nb_edge_risk >= INF:
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
			var edge_cost := minf(nb_edge_risk, max_allowed_edge_risk) * maxf(heightmap_path_edge_risk_penalty, 0.0)
			
			var same_level_wall_cost: float = 0.0
			var cell_clearance: float = maxf(heightmap_path_target_agl_m, min_terrain_clearance_m)
			var max_h_local: float = nb_h + nb_edge_risk
			if nav_grid.has_method("sample_query_max_height"):
				var sample_max: float = float(nav_grid.call("sample_query_max_height", nb_world.x, nb_world.z))
				if sample_max < INF and not is_nan(sample_max) and sample_max > -500000.0:
					max_h_local = sample_max
			
			# Avoid cliffs horizontally by 50m only when flying below the cliff height
			if max_h_local > nb_h + cell_clearance - 5.0:
				same_level_wall_cost = _get_same_level_wall_cost(nb_edge_risk)
			var low_route_cost := 0.0
			if nb_h < first_plateau_min_y:
				low_route_cost = (
					maxf(heightmap_path_ground_route_penalty, 0.0)
					+ (first_plateau_min_y - nb_h) * maxf(heightmap_path_low_route_penalty, 0.0)
				)
			var top_level_cost := 0.0
			if nb_h > first_plateau_max_y:
				top_level_cost = (nb_h - first_plateau_max_y) * maxf(heightmap_path_top_level_penalty, 0.0)
			var level_cost := 0.0
			if nb_h > first_plateau_max_y:
				level_cost += maxf(heightmap_path_upper_level_penalty, 0.0)
			var cur_ground_level := cur_h <= ground_band_ceiling
			var nb_ground_level := nb_h <= ground_band_ceiling
			if cur_ground_level != nb_ground_level and nb_ground_level:
				level_cost += maxf(heightmap_path_level_change_penalty, 0.0)
			var tg: float = g_score.get(cur, INF) + step_dist + altitude_cost + climb_cost + high_terrain_cost + edge_cost + same_level_wall_cost + low_route_cost + top_level_cost + level_cost
			if tg < g_score.get(nb, INF):
				came_from[nb] = cur
				g_score[nb] = tg
				_heap_push_path_node(open, [tg + _aerial_h(nb, end, cell_size), nb.x, nb.y])

	var limit_reached := iterations >= max_iterations
	_write_to_helicopter_paths_log("[%s] A* search failed: %s after %d/%d iterations." % [
		craft_name,
		"reached iterations limit" if limit_reached else "open list empty",
		iterations,
		max_iterations
	])
	var navgrid_path := _find_low_terrain_navgrid_path(nav_grid, current_pos, goal)
	if not navgrid_path.is_empty():
		_write_to_helicopter_paths_log("[%s] Fallback to low terrain navgrid success: path points=%d" % [craft_name, navgrid_path.size()])
		_last_path_source = "navgrid_fallback"
		return navgrid_path
	_write_to_helicopter_paths_log("[%s] Fallback to low terrain navgrid failed: empty path" % [craft_name])
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


func _get_same_level_wall_cost(edge_risk_m: float) -> float:
	if edge_risk_m >= INF:
		return INF
	var risk_start := maxf(heightmap_path_same_level_wall_risk_start_m, 0.0)
	var excess_risk := maxf(edge_risk_m - risk_start, 0.0)
	return excess_risk * excess_risk * maxf(heightmap_path_same_level_wall_penalty, 0.0)


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
	return false


func _aerial_h(a: Vector2i, b: Vector2i, cell_size: float) -> float:
	const HEURISTIC_WEIGHT := 1.5
	return Vector2(a.x - b.x, a.y - b.y).length() * cell_size * HEURISTIC_WEIGHT




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
	return path


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
	return _has_clear_transit_segment(a, b)


func _has_clear_transit_segment(a: Vector3, b: Vector3) -> bool:
	var distance: float = _flat_distance(a, b)
	if distance <= 1.0:
		return true
	
	var sample_spacing := 20.0
	var sample_count: int = maxi(int(ceil(distance / sample_spacing)), 1)
	
	var path_clearance := _get_path_segment_clearance_m()
	var route_terrain_ceiling := _get_heightmap_max_route_terrain_y()
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")

	for i in range(sample_count + 1):
		var t: float = float(i) / float(sample_count)
		var sample_pos: Vector3 = a.lerp(b, t)
		
		var ground_h := _get_ground_height_at_position(sample_pos)
		if is_nan(ground_h):
			ground_h = lerpf(a.y, b.y, t) - path_clearance
		
		if ground_h > route_terrain_ceiling:
			return false
		
		# Check vertical clearance at this sample point
		if sample_pos.y < ground_h + path_clearance:
			return false
		
		# Check horizontal cliff avoidance only if we are at the same altitude:
		# If the maximum terrain height within 50m of our sample position is higher
		# than our flight altitude minus 25m, then we are flying too close to a cliff wall
		# and must reject the segment shortcut.
		if nav_grid != null and nav_grid.has_method("get_max_height_in_radius"):
			var max_h_50m: float = float(nav_grid.call("get_max_height_in_radius", sample_pos.x, sample_pos.z, 50.0))
			if max_h_50m > -500000.0:
				if sample_pos.y < max_h_50m + 25.0:
					return false

	return true


func _get_path_segment_clearance_m() -> float:
	# Use the same AGL margin the path elevation step uses, not the larger
	# cruise clearance — otherwise the simplifier always fails on valid segments.
	return _get_heightmap_route_agl_m()


func _get_edge_risk_clearance_m() -> float:
	return maxf(
		maxf(heightmap_path_edge_risk_clearance_m, 0.0),
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
	var horizontal_speed := Vector2(control_vel.x, control_vel.z).length()
	desired_speed = _apply_airborne_separation_speed_limit(desired_speed, control_vel, forward, right, delta)
	
	# PHYSICS RULE 2: Dynamic Braking for Obstacles
	if _feeler_forward_obstacle_distance < 2000.0:
		var safe_stop_dist := maxf(_feeler_forward_obstacle_distance - lateral_obstacle_margin_m, 1.0)
		var max_safe_speed := sqrt(2.0 * _phys_max_decel_mps2 * safe_stop_dist)
		desired_speed = minf(desired_speed, max_safe_speed)
	
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
		# Speed-dependent braking distance: scale with actual speed so fast helis
		# start braking earlier and don't overshoot.
		var speed_ratio := horizontal_speed / maxf(cruise_speed_mps, 1.0)
		var effective_decel_dist := maxf(decel_distance_m, 1.0) * speed_ratio * (1.0 - turn_suppression)
		if dest_dist < effective_decel_dist:
			var approach_t := 1.0 - clampf(dest_dist / maxf(effective_decel_dist, 1.0), 0.0, 1.0)
			# Squared ease-in: braking builds gradually from the start of the window,
			# bleeding speed early so there's no aggressive last-second nose-up.
			approach_lean_scale = 1.0 - approach_t * approach_t
	forward_lean *= approach_lean_scale
	if desired_speed < cruise_speed_mps and horizontal_speed > desired_speed:
		var overspeed_t := clampf(
			(horizontal_speed - desired_speed) / maxf(energy_management_speed_band_mps, 1.0),
			0.0,
			1.0
		)
		forward_lean *= 1.0 - overspeed_t
	_prev_forward_lean = forward_lean
	# desired_speed drives collective energy management. In normal cruise it is the
	# usual cruise speed; path-fail escape lowers it so lift bias does not encourage
	# high-speed terrain charging.
	_speed_target_mps = maxf(desired_speed, 0.0)
	var forward_error := forward_lean
	var lateral_error := path_dir.dot(right) * minf(horizontal_speed, maxf(transit_lateral_max_demand_mps, 0.0)) - lat_speed
	var separation_vel := _get_airborne_separation_velocity(control_vel, forward, right)
	if separation_vel.length_squared() > 0.001:
		lateral_error += separation_vel.dot(right)
	var turn_error := forward.signed_angle_to(path_dir, Vector3.UP)
	var absolute_turn_error := absf(turn_error)
	var terrain_recovery_t: float = 0.0
	var ground_h := _get_down_feeler_ground_height(current_pos)
	if not is_nan(ground_h):
		var down_clearance_floor := maxf(
			min_terrain_clearance_m + terrain_escape_margin_m + terrain_down_feeler_extra_clearance_m,
			1.0
		)
		target.y = maxf(target.y, ground_h + down_clearance_floor)
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
	var _wall_margin := maxf(lateral_obstacle_margin_m, 1.0)
	# Speed-scaled probe distance: faster = longer lookahead
	var _probe_dist := clampf(
		maxf(lateral_obstacle_probe_dist_m, 1.0) + horizontal_speed * maxf(lateral_obstacle_probe_speed_scale, 0.0),
		lateral_obstacle_probe_dist_m,
		maxf(lateral_obstacle_probe_max_dist_m, lateral_obstacle_probe_dist_m)
	)
	# 5-feeler fan — recomputed every 0.1s, cached between frames.
	_feeler_timer_s -= _physics_delta
	if _feeler_timer_s <= 0.0:
		_feeler_timer_s = 0.1
		_feeler_net_left_risk = 0.0
		_feeler_net_right_risk = 0.0
		_feeler_forward_penalty = 0.0
		_feeler_forward_obstacle_distance = INF
		_feeler_rear_penalty = 0.0
	var _feeler_forward_speed_penalty := _feeler_forward_penalty
	var _min_forward_dist := _feeler_forward_obstacle_distance
	var _rear_penalty := _feeler_rear_penalty
	var _net_left_risk := _feeler_net_left_risk
	var _net_right_risk := _feeler_net_right_risk
	# Only recompute samples on the reset frame — cached otherwise.
	if _feeler_timer_s >= 0.099:
		const FEELER_ANGLES := [0.0, 20.0, -20.0, 50.0, -50.0, 90.0, -90.0, 135.0, -135.0, 180.0]
		const FEELER_BASE_WEIGHTS := [1.2, 1.0, 1.0, 0.6, 0.6, 0.9, 0.9, 0.65, 0.65, 0.55]
		const FEELER_DIST_SCALES := [1.0, 1.0, 1.0, 0.7, 0.7, 0.45, 0.45, 0.55, 0.55, 0.4]
		const FEELER_NEAR_WEIGHT := 2.5
		const FEELER_NEAR_FRAC := 0.33
		var feeler_forward := forward
		var feeler_right := right
		if horizontal_speed > 2.0:
			feeler_forward = Vector3(control_vel.x, 0.0, control_vel.z).normalized()
			feeler_right = Vector3.UP.cross(feeler_forward).normalized()
		for _fi in range(FEELER_ANGLES.size()):
			var _angle_deg: float = FEELER_ANGLES[_fi]
			var _base_weight: float = FEELER_BASE_WEIGHTS[_fi]
			var _angle_rad := deg_to_rad(_angle_deg)
			var _dir := (feeler_forward * cos(_angle_rad) + feeler_right * sin(_angle_rad)).normalized()
			var _far_dist: float = float(FEELER_DIST_SCALES[_fi]) * _probe_dist
			var _near_dist: float = _far_dist * FEELER_NEAR_FRAC
			for _sample in range(2):
				var _sdist: float = _near_dist if _sample == 0 else _far_dist
				var _dist_weight := FEELER_NEAR_WEIGHT if _sample == 0 else 1.0
				var _h := _get_ground_height_at_position(current_pos + _dir * _sdist)
				if is_nan(_h):
					continue
				var _dist_t := 1.0 - clampf(_sdist / maxf(_far_dist, 1.0), 0.0, 1.0) * 0.5
				var _risk := clampf(1.0 + (_h - current_pos.y) / _wall_margin, 0.0, 1.0) \
					* _base_weight * _dist_weight * _dist_t
				if _risk <= 0.0:
					continue
				if _angle_deg == 0.0:
					_feeler_forward_speed_penalty = maxf(_feeler_forward_speed_penalty, _risk)
					# Only trigger forward obstacle braking if the ground rises above min clearance
					if _h > current_pos.y - min_terrain_clearance_m:
						_min_forward_dist = minf(_min_forward_dist, _sdist)
				elif _angle_deg > 0.0 and _angle_deg < 179.0:
					_net_right_risk = maxf(_net_right_risk, _risk)
				elif _angle_deg < 0.0:
					_net_left_risk = maxf(_net_left_risk, _risk)
				if absf(_angle_deg) > 100.0:
					_rear_penalty = maxf(_rear_penalty, _risk)
		# Store back to cache
		_feeler_forward_penalty = _feeler_forward_speed_penalty
		_feeler_forward_obstacle_distance = _min_forward_dist
		_feeler_rear_penalty = _rear_penalty
		_feeler_net_left_risk = _net_left_risk
		_feeler_net_right_risk = _net_right_risk
	if _net_left_risk > 0.0 or _net_right_risk > 0.0:
		lateral_wall_roll = (_net_left_risk - _net_right_risk) * maxf(lateral_obstacle_roll_gain, 0.0)
		lateral_wall_yaw = (_net_left_risk - _net_right_risk) * maxf(lateral_obstacle_yaw_gain, 0.0)
		lateral_error += (_net_left_risk - _net_right_risk) * maxf(lateral_obstacle_side_push_mps, 0.0)
	# Forward obstacle: only slow down if the path is asymmetrically blocked.
	# If both sides have similar risk it's a corridor — let them fly through.
	# Slow down only when one side is significantly more blocked than the other,
	# or when the forward feeler sees something and the sides are clear.
	if _feeler_forward_speed_penalty > 0.0:
		var side_balance := absf(_net_left_risk - _net_right_risk)
		var corridor_t := 1.0 - clampf(side_balance / maxf(_feeler_forward_speed_penalty, 0.001), 0.0, 1.0)
		var effective_penalty := minf(
			_feeler_forward_speed_penalty * (1.0 - corridor_t * 0.85),
			maxf(lateral_obstacle_forward_speed_max_penalty, 0.0)
		)
		forward_lean *= 1.0 - effective_penalty * maxf(lateral_obstacle_forward_speed_scale, 0.0)
	if _rear_penalty > 0.0 and _feeler_forward_speed_penalty < 0.35:
		forward_lean = maxf(forward_lean, _rear_penalty * maxf(lateral_obstacle_rear_forward_lean, 0.0))
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
	var active_min_lean: float = min_forward_lean
	# If the speed target is reduced (braking), or if there is a significant upcoming climb required,
	# allow the helicopter to reduce forward lean to 0.0 to decelerate/brake.
	if _speed_target_mps < cruise_speed_mps or (target.y - current_pos.y) > 10.0:
		active_min_lean = 0.0

	if _is_path_fail_escape_active():
		var escape_lean := maxf(path_fail_escape_forward_lean, 0.0)
		active_min_lean = minf(active_min_lean, escape_lean)
		forward_lean = minf(forward_lean, escape_lean)
	if pedal_turn > 0.0:
		forward_lean = lerpf(forward_lean, active_min_lean, pedal_turn)
		lateral_error *= 1.0 - pedal_turn
	if backward_turn > 0.0:
		lateral_error = lerpf(lateral_error, -lat_speed, backward_turn)
		forward_lean = maxf(forward_lean, active_min_lean)
	if sharp_turn > 0.0:
		var turn_scale := lerpf(1.0, maxf(transit_sharp_turn_lean_scale, 0.0), sharp_turn)
		# Use min so approach decel and sharp-turn decel don't compound multiplicatively.
		# The helicopter decelerates to whichever constraint is tighter, not both at once.
		var combined := maxf(transit_cruise_forward_lean, 0.0) * minf(approach_lean_scale, turn_scale)
		forward_lean = maxf(minf(forward_lean, combined), active_min_lean)
	if reverse_recovery > 0.0:
		forward_lean = maxf(
			forward_lean,
			lerpf(active_min_lean, maxf(transit_reverse_recovery_lean, active_min_lean), reverse_recovery)
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
				forward_lean = maxf(forward_lean, active_min_lean)

	# Descent lean: when above the target altitude and below cruise speed, add forward
	# lean to nose over and trade altitude for speed rather than hovering down.
	# Suppressed during turns — a banked rotor needs its thrust for lift, not speed.
	var alt_surplus := current_pos.y - target.y
	if alt_surplus > 0.0 and horizontal_speed < maxf(cruise_speed_mps, 1.0) \
			and sharp_turn <= 0.0 and pedal_turn <= 0.0:
		var surplus_t := clampf(alt_surplus / maxf(transit_descent_lean_alt_full_m, 1.0), 0.0, 1.0)
		var speed_t := clampf(horizontal_speed / maxf(cruise_speed_mps, 1.0), 0.0, 1.0)
		var turn_suppress := clampf(absolute_turn_error / deg_to_rad(maxf(transit_sharp_turn_angle_deg, 10.0)), 0.0, 1.0)
		var descent_lean := maxf(transit_descent_lean_bonus, 0.0) * surplus_t * (1.0 - speed_t) * (1.0 - turn_suppress)
		forward_lean = minf(forward_lean + descent_lean, 1.0)

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

	target_vertical_rate += _airborne_separation_vertical_avoidance_mps
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
	
	var brake_pitch := 0.0
	if desired_speed < cruise_speed_mps and horizontal_speed > desired_speed:
		var overspeed := horizontal_speed - desired_speed
		brake_pitch = clampf(overspeed / 15.0, 0.0, max_cyclic_input * 0.8)
		target_pitch += brake_pitch

	var min_pitch_floor := -maxf(min_forward_lean, 0.0)
	var effective_pitch_floor := lerpf(0.0, min_pitch_floor + brake_pitch, pitch_floor_speed_t)
	var effective_nose_up_cap := lerpf(1.0, maxf(transit_max_nose_up, 0.0) + brake_pitch, pitch_floor_speed_t)
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
	target_pitch = _apply_reverse_avoidance_pitch(target_pitch, fwd_speed)
	var pitch_rate_scale: float = 1.0

	# Reduce bank when close to terrain so the lift vector stays mostly vertical
	# and collective can actually arrest descent. terrain_recovery_t goes to 1.0 at
	# terrain_recovery_full_agl_m; terrain_recovery_max_bank_scale caps the roll there.
	var terrain_bank_scale := lerpf(1.0, maxf(terrain_recovery_max_bank_scale, 0.0), terrain_recovery_t)
	target_roll = clampf(target_roll, -cyclic_limit * terrain_bank_scale, cyclic_limit * terrain_bank_scale)
	# Lateral wall avoidance stays within the terrain bank limit.
	target_roll = clampf(target_roll + lateral_wall_roll, -cyclic_limit * terrain_bank_scale, cyclic_limit * terrain_bank_scale)

	var base_yaw_limit := _get_yaw_limit_for_speed(horizontal_speed)
	var low_speed_yaw_limit := lerpf(
		base_yaw_limit,
		1.0,
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
	var combat_collective_floor: float = -1.0
	var combat_aim: Dictionary = _get_combat_aim_commands(target_pitch, target_roll, target_yaw, delta, cyclic_limit, yaw_limit)
	if not combat_aim.is_empty():
		target_pitch = float(combat_aim.get("pitch", target_pitch))
		target_roll = float(combat_aim.get("roll", target_roll))
		target_yaw = float(combat_aim.get("yaw", target_yaw))
		pitch_rate_scale = maxf(float(combat_aim.get("pitch_rate_scale", 1.0)), 0.01)
		combat_collective_floor = float(combat_aim.get("collective_floor", -1.0))

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

	_pitch_cmd = move_toward(_pitch_cmd, target_pitch, maxf(cyclic_rate, 0.01) * pitch_rate_scale * delta)
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
	if combat_collective_floor >= 0.0:
		collective_target = maxf(collective_target, clampf(combat_collective_floor, 0.0, 1.0))
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
		# Carrier landing uses deck-relative control velocity, so this is the
		# amount above carrier speed. FINAL should creep from the approach point
		# to the landing point at carrier speed + carrier_final_speed_offset_mps.
		if _carrier_approach_phase == CarrierApproachPhase.FINAL:
			spd = maxf(carrier_final_speed_offset_mps, 0.0)
		else:
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
	spd = _apply_airborne_separation_speed_limit(spd, control_vel, forward, right, delta)
	var speed_decel_step := maxf(transit_speed_target_decel_mps2, 0.0) * delta
	var speed_accel_step := maxf(transit_speed_target_accel_mps2, 0.0) * delta
	_speed_target_mps = move_toward(_speed_target_mps, spd,
			speed_decel_step if spd < _speed_target_mps else speed_accel_step)

	# Measured speeds in aircraft axes — used for both P error and D derivative
	var fwd_speed := control_vel.dot(forward)
	var lat_speed := control_vel.dot(right)
	var vertical_speed: float = control_vel.y
	var horizontal_speed := Vector2(control_vel.x, control_vel.z).length()

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
	var separation_vel := _get_airborne_separation_velocity(control_vel, forward, right)
	if separation_vel.length_squared() > 0.001:
		desired_vel += separation_vel
	var reverse_avoidance_t := _get_reverse_avoidance_t(fwd_speed)
	if reverse_avoidance_t > 0.0:
		var current_desired_forward := desired_vel.dot(forward)
		var recovery_forward := lerpf(
			current_desired_forward,
			maxf(reverse_avoidance_forward_speed_mps, 0.0),
			reverse_avoidance_t
		)
		desired_vel += forward * (recovery_forward - current_desired_forward)
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
	var yaw_limit := _get_yaw_limit_for_speed(horizontal_speed)
	var yaw_heading_gain := 0.0 if state == State.LOW_LEVEL_TRANSIT else yaw_gain
	if state == State.LOW_LEVEL_TRANSIT and not _combat_plan.is_empty():
		yaw_heading_gain = yaw_gain * maxf(combat_transit_yaw_gain_scale, 0.0)
	var target_yaw := clampf(yaw_error * yaw_heading_gain - yaw_rate * yaw_rate_damping, -yaw_limit, yaw_limit)
	_yaw_cmd = move_toward(_yaw_cmd, target_yaw, maxf(yaw_command_rate, 0.01) * delta)

	# Pitch trades speed and altitude using predicted vertical motion. This keeps
	# the cyclic ahead of the helicopter's delayed response instead of reacting
	# only after altitude has already drifted badly.
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

		target_vertical_rate += _airborne_separation_vertical_avoidance_mps
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
	_debug_backward_turn = reverse_avoidance_t
	_debug_bank_pullback = 0.0
	_debug_target_yaw = target_yaw
	_debug_terrain_recovery = 0.0
	var vertical_priority := 0.0
	_debug_vertical_priority = vertical_priority
	var target_pitch := clampf(speed_pitch + altitude_trade_pitch, -cyclic_limit, cyclic_limit)
	target_pitch = _apply_reverse_avoidance_pitch(target_pitch, fwd_speed)

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


func _apply_airborne_separation_speed_limit(requested_speed: float, control_vel: Vector3, forward: Vector3, right: Vector3, delta: float) -> float:
	_debug_airborne_separation_dist_m = INF
	_debug_airborne_separation_speed_limit_mps = INF
	_debug_airborne_separation_log_s = maxf(_debug_airborne_separation_log_s - delta, 0.0)
	if not _is_airborne_for_separation(aircraft):
		return requested_speed
	var safe_distance := maxf(airborne_safe_distance_m, 0.0)
	var brake_start := maxf(airborne_separation_brake_start_m, safe_distance + 1.0)
	var push_start := maxf(airborne_separation_push_start_m, safe_distance + 1.0)
	var separation_range := maxf(brake_start, push_start)
	var vertical_limit := maxf(airborne_separation_vertical_m, 1.0)
	var lookahead_s := maxf(airborne_separation_lookahead_s, 0.0)
	if safe_distance <= 0.0 or requested_speed <= 0.0:
		return requested_speed

	var my_pos := aircraft.global_position
	var speed_limit := INF
	var speed_boost := requested_speed
	var closest_dist := INF
	var closest_name := ""
	var closest_action := ""
	var vertical_avoidance := 0.0
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node3D) or node == aircraft:
				continue
			var other := node as Node3D
			if not is_instance_valid(other):
				continue
			var id := other.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			if not _is_airborne_for_separation(other):
				continue
			var vertical_sep := absf(other.global_position.y - my_pos.y)
			if vertical_sep > vertical_limit:
				continue
			var rel_pos := other.global_position - my_pos
			var flat_rel := Vector3(rel_pos.x, 0.0, rel_pos.z)
			var flat_dist := flat_rel.length()
			if flat_dist > separation_range:
				continue
			var other_vel := _get_node_velocity(other)
			var rel_vel := other_vel - control_vel
			var predicted_flat := flat_rel
			if lookahead_s > 0.0:
				predicted_flat += Vector3(rel_vel.x, 0.0, rel_vel.z) * lookahead_s
			var predicted_dist := predicted_flat.length()
			var min_dist := minf(flat_dist, predicted_dist)
			if min_dist > separation_range:
				continue
			var ahead := flat_rel.dot(forward)
			var lateral_abs := absf(flat_rel.dot(right))
			var closing_speed := 0.0
			if flat_dist > 0.1:
				closing_speed = (control_vel - other_vel).dot(flat_rel.normalized())
			var in_front_corridor := ahead > 0.0 and lateral_abs < safe_distance * 1.5
			var behind_corridor := ahead < 0.0 and lateral_abs < safe_distance * 1.5
			var closing_inside_margin := closing_speed > 0.0 and min_dist < safe_distance
			var action := ""
			if in_front_corridor or closing_inside_margin:
				var brake_t := 1.0 - clampf((min_dist - safe_distance) / maxf(brake_start - safe_distance, 0.001), 0.0, 1.0)
				var other_forward_speed := maxf(other_vel.dot(forward), 0.0)
				var follow_speed := maxf(airborne_separation_min_speed_mps, minf(other_forward_speed, requested_speed))
				var candidate_limit := lerpf(requested_speed, follow_speed, brake_t)
				if min_dist < safe_distance:
					var violation_t := 1.0 - clampf(min_dist / maxf(safe_distance, 0.001), 0.0, 1.0)
					candidate_limit = lerpf(candidate_limit, maxf(airborne_separation_min_speed_mps, 0.0), violation_t)
					# Vertical avoidance: if we are within safe_distance horizontally and close vertically, push vertically.
					var vert_diff := my_pos.y - other.global_position.y
					if vert_diff >= 0.0:
						vertical_avoidance = maxf(vertical_avoidance, violation_t * maxf(cyclic_target_climb_mps, 3.0))
					else:
						vertical_avoidance = minf(vertical_avoidance, -violation_t * maxf(cyclic_target_sink_mps, 3.0))
				speed_limit = minf(speed_limit, candidate_limit)
				action = "brake"
			if behind_corridor and min_dist <= push_start:
				var push_t := 1.0 - clampf((min_dist - safe_distance) / maxf(push_start - safe_distance, 0.001), 0.0, 1.0)
				if min_dist < safe_distance:
					push_t = maxf(push_t, 1.0 - clampf(min_dist / maxf(safe_distance, 0.001), 0.0, 1.0))
				var push_cap := maxf(airborne_separation_push_max_speed_mps, requested_speed)
				var push_target := minf(
					requested_speed + maxf(airborne_separation_push_extra_mps, 0.0) * push_t,
					push_cap
				)
				speed_boost = maxf(speed_boost, push_target)
				action = "push" if action.is_empty() else action + "+push"
			if action.is_empty():
				continue
			if min_dist < closest_dist:
				closest_dist = min_dist
				closest_name = str(other.name)
				closest_action = action

	if closest_dist < INF:
		_debug_airborne_separation_dist_m = closest_dist
		_airborne_separation_vertical_avoidance_mps = vertical_avoidance
		var adjusted_speed := minf(speed_boost, speed_limit)
		_debug_airborne_separation_speed_limit_mps = adjusted_speed
		if debug_enabled and _debug_airborne_separation_log_s <= 0.0:
			_debug_airborne_separation_log_s = maxf(airborne_separation_debug_interval_s, 0.25)
			_debug_event("airborne_separation", "near=%s action=%s dist=%.1f req=%.1f target=%.1f safe=%.1f" % [
				closest_name,
				closest_action,
				closest_dist,
				requested_speed,
				adjusted_speed,
				safe_distance,
			])
	return minf(speed_boost, speed_limit)


func _get_airborne_separation_velocity(control_vel: Vector3, forward: Vector3, right: Vector3) -> Vector3:
	if not _is_airborne_for_separation(aircraft):
		return Vector3.ZERO
	var safe_distance := maxf(airborne_safe_distance_m, 0.0)
	var start_distance := maxf(airborne_separation_start_m, safe_distance + 1.0)
	var vertical_limit := maxf(airborne_separation_vertical_m, 1.0)
	var lookahead_s := maxf(airborne_separation_lookahead_s, 0.0)
	var max_avoid_speed := maxf(airborne_separation_max_speed_mps, 0.0)
	if safe_distance <= 0.0 or max_avoid_speed <= 0.0:
		return Vector3.ZERO

	var my_pos := aircraft.global_position
	var steer := Vector3.ZERO
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node3D) or node == aircraft:
				continue
			var other := node as Node3D
			if not is_instance_valid(other):
				continue
			var id := other.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			if not _is_airborne_for_separation(other):
				continue
			var vertical_sep := absf(other.global_position.y - my_pos.y)
			if vertical_sep > vertical_limit:
				continue
			var rel_pos := other.global_position - my_pos
			var flat_rel := Vector3(rel_pos.x, 0.0, rel_pos.z)
			var flat_dist := flat_rel.length()
			if flat_dist > start_distance:
				continue
			var other_vel := _get_node_velocity(other)
			var rel_vel := other_vel - control_vel
			var predicted_flat := flat_rel
			if lookahead_s > 0.0:
				predicted_flat += Vector3(rel_vel.x, 0.0, rel_vel.z) * lookahead_s
			var predicted_dist := predicted_flat.length()
			if flat_dist >= safe_distance and predicted_dist >= safe_distance:
				continue
			var away := -flat_rel
			if away.length_squared() < 0.01:
				away = right if right.length_squared() > 0.001 else Vector3.RIGHT
			away = away.normalized()
			var proximity_t := 1.0 - clampf(minf(flat_dist, predicted_dist) / safe_distance, 0.0, 1.0)
			var distance_t := 1.0 - clampf(flat_dist / start_distance, 0.0, 1.0)
			steer += away * maxf(proximity_t, distance_t * 0.35)

	if steer.length_squared() < 0.001:
		return Vector3.ZERO
	steer.y = 0.0
	if steer.length_squared() < 0.001:
		return Vector3.ZERO
	var steer_strength := clampf(steer.length(), 0.0, 1.0)
	steer = steer.normalized() * steer_strength * max_avoid_speed

	var backward_component := steer.dot(forward)
	if backward_component < 0.0:
		steer -= forward * backward_component
	if steer.length_squared() < 0.001:
		steer = right * max_avoid_speed * 0.5
	return steer


func _is_airborne_for_separation(node: Node) -> bool:
	if not is_instance_valid(node) or not (node is Node3D):
		return false
	if node.has_meta("carrier_transport_mode") and bool(node.get_meta("carrier_transport_mode")):
		return false
	if node.has_meta("parking_brake") and bool(node.get_meta("parking_brake")):
		return false
	if node.has_meta("controls_disabled") and bool(node.get_meta("controls_disabled")):
		return false
	if node is RigidBody3D:
		var rb := node as RigidBody3D
		if rb.freeze:
			return false
		var ground_h := _get_ground_height_at_position(rb.global_position)
		if not is_nan(ground_h) and rb.global_position.y - ground_h < 8.0:
			return false
		return rb.linear_velocity.length() > 2.0 or rb.global_position.y > 8.0
	return true


func _get_node_velocity(node: Node) -> Vector3:
	if node is RigidBody3D:
		return (node as RigidBody3D).linear_velocity
	var lv = node.get("linear_velocity")
	if lv is Vector3:
		return lv
	var v = node.get("velocity")
	if v is Vector3:
		return v
	return Vector3.ZERO


func _get_reverse_avoidance_t(fwd_speed: float) -> float:
	var start := maxf(reverse_avoidance_start_mps, 0.0)
	var full := maxf(reverse_avoidance_full_mps, start + 0.1)
	return clampf((start - fwd_speed) / maxf(full - start, 0.001), 0.0, 1.0)


func _get_yaw_limit_for_speed(horizontal_speed: float) -> float:
	var base_limit := clampf(max_yaw_input, 0.0, 1.0)
	var full_below := maxf(full_yaw_below_speed_mps, 0.0)
	var full_above := maxf(full_yaw_above_speed_mps, full_below + 0.1)
	var full_yaw_t := 1.0 - clampf(
		(horizontal_speed - full_below) / maxf(full_above - full_below, 0.001),
		0.0,
		1.0
	)
	return lerpf(base_limit, 1.0, full_yaw_t)


func _apply_reverse_avoidance_pitch(target_pitch: float, fwd_speed: float) -> float:
	var brake_guard_speed := maxf(reverse_avoidance_brake_guard_mps, 0.1)
	var brake_guard_t := clampf((brake_guard_speed - fwd_speed) / brake_guard_speed, 0.0, 1.0)
	var guarded_nose_up_cap := lerpf(1.0, maxf(reverse_avoidance_nose_up_cap, 0.0), brake_guard_t)
	target_pitch = minf(target_pitch, guarded_nose_up_cap)

	var reverse_t := _get_reverse_avoidance_t(fwd_speed)
	if reverse_t <= 0.0:
		return target_pitch
	var nose_up_cap := maxf(reverse_avoidance_nose_up_cap, 0.0)
	var recovery_pitch := -maxf(reverse_avoidance_forward_pitch, 0.0)
	var pitch_ceiling := lerpf(nose_up_cap, recovery_pitch, reverse_t)
	return minf(target_pitch, pitch_ceiling)


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

	# Bank/Pitch compensation: a tilted rotor produces less vertical lift. Add collective to
	# compensate — without this a low-speed banked turn or deceleration flare loses altitude.
	# cos(tilt) of the aircraft's up vector vs world up gives the vertical thrust fraction.
	var tilt_boost := 0.0
	if is_instance_valid(aircraft):
		var up_dot := aircraft.global_transform.basis.y.dot(Vector3.UP)
		var vert_fraction := maxf(up_dot, 0.15)
		tilt_boost = _get_collective_trim() * (1.0 / vert_fraction - 1.0)
	
	if state == State.TAKEOFF or state == State.LOW_LEVEL_TRANSIT:
		collective = _calculate_transit_collective(collective, alt_error, horizontal_speed)
		return clampf(collective + tilt_boost, 0.4, 1.0)
		
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
		# trying to climb to approach altitude, so capping collective causes it to sink.
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
	return clampf(collective + tilt_boost, 0.4, 1.0)


func _calculate_transit_collective(base_collective: float, alt_error: float, horizontal_speed: float) -> float:
	var feedback_collective := clampf(base_collective, 0.0, 1.0)
	var vertical_speed := aircraft.linear_velocity.y if is_instance_valid(aircraft) else 0.0

	# Altitude boost: smoothly blend toward 1.0 as altitude error grows.
	# No hard thresholds — the gain curve determines how aggressively altitude error increases collective.
	var alt_boost_t := clampf(alt_error / maxf(collective_full_climb_alt_error_m, 1.0), 0.0, 1.0)
	var urgency_alt_t := clampf(alt_error / maxf(collective_climb_urgency_alt_error_m, 1.0), 0.0, 1.0)
	var climb_shortfall := maxf(minf(max_climb_mps, maxf(alt_error, 0.0)) - vertical_speed, 0.0)
	var shortfall_t := clampf(climb_shortfall / maxf(collective_climb_urgency_full_mps, 0.1), 0.0, 1.0)
	var sink_t := clampf((-vertical_speed - maxf(collective_climb_urgency_sink_mps, 0.0)) / maxf(collective_climb_urgency_full_mps, 0.1), 0.0, 1.0)
	alt_boost_t = maxf(alt_boost_t, urgency_alt_t * maxf(shortfall_t, sink_t))
	var alt_boosted := lerpf(feedback_collective, 1.0, alt_boost_t)

	# When above target altitude, nudge collective down to encourage descent.
	# "Rolling downhill" mode: if below cruise speed, don't touch collective — just
	# pitch forward and let gravity convert altitude into speed. Only reduce collective
	# when already at cruise speed and the actual sink rate is below the target.
	var trim := _get_collective_trim()
	if alt_error < 0.0:
		var speed_fraction := clampf(horizontal_speed / maxf(cruise_speed_mps, 1.0), 0.0, 1.0)
		# At full cruise speed, target sink = transit_target_sink_mps.
		# Below cruise speed, target sink scales toward zero — pitch handles it.
		# Only nudge collective down if actually descending (not still climbing through target altitude).
		if vertical_speed <= 0.5:
			var desired_sink := maxf(transit_target_sink_mps, 0.0) * speed_fraction
			var actual_sink := maxf(-vertical_speed, 0.0)  # positive = descending; clamp to 0 if levelling
			var sink_shortfall := desired_sink - actual_sink
			if sink_shortfall > 0.0:
				var reduction_t := clampf(sink_shortfall / maxf(transit_target_sink_mps, 0.1), 0.0, 1.0)
				reduction_t *= speed_fraction
				var descent_collective := lerpf(trim, maxf(energy_management_min_collective, 0.0), reduction_t)
				feedback_collective = minf(feedback_collective, descent_collective)
				alt_boosted = minf(alt_boosted, descent_collective)

	# Speed management: if already at or above speed target, allow collective to settle back.
	var speed_target := maxf(_speed_target_mps, 0.0)
	var speed_excess := horizontal_speed - speed_target
	var speed_t := 0.0
	if speed_target > 0.0:
		speed_t = clampf(speed_excess / maxf(energy_management_speed_band_mps, 1.0), 0.0, 1.0)

	var minimum_collective := clampf(energy_management_min_collective, 0.0, 1.0)
	if alt_error > 0.0:
		var urgency_floor_t := maxf(urgency_alt_t * shortfall_t, sink_t)
		minimum_collective = maxf(
			minimum_collective,
			lerpf(trim, clampf(collective_climb_urgency_min, 0.0, 1.0), urgency_floor_t)
		)
	var speed_managed_collective := lerpf(alt_boosted, minimum_collective, speed_t)
	# When descending (above target alt), don't enforce the minimum floor — doing so
	# would undo the descent nudge. Use zero as the safety floor instead.
	var return_floor := minimum_collective if alt_error >= 0.0 else 0.0
	return clampf(maxf(speed_managed_collective, feedback_collective), return_floor, 1.0)


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
		if debug_enabled and not _missing_carrier_marker_log_once.has(marker_name):
			_missing_carrier_marker_log_once[marker_name] = true
			print("HELI_AI marker_not_found name='%s' carrier=%s" % [marker_name, carrier.name])
		return Vector3.INF
	return marker.global_position


func _get_carrier_approach_point_world_pos() -> Vector3:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return Vector3.INF
	var marker_pos := _get_carrier_marker_world_pos(carrier_approach_point_name)
	if marker_pos != Vector3.INF:
		return marker_pos

	var landing_pos := _get_carrier_marker_world_pos(carrier_landing_point_name)
	if landing_pos == Vector3.INF:
		landing_pos = _get_carrier_landing_point(carrier)
	var fallback := landing_pos
	var deck_y := _get_carrier_deck_y(carrier)
	fallback.y = deck_y + maxf(carrier_approach_fallback_height_m, 0.0)
	var behind := carrier.global_transform.basis * Vector3(0.0, 0.0, -maxf(carrier_approach_fallback_behind_m, 0.0))
	behind.y = 0.0
	fallback += behind
	if debug_enabled and not _missing_carrier_marker_log_once.has(carrier_approach_point_name + "_fallback"):
		_missing_carrier_marker_log_once[carrier_approach_point_name + "_fallback"] = true
		_debug_event("carrier_approach_marker_fallback", "name='%s' pos=%s" % [
			carrier_approach_point_name,
			str(fallback.snapped(Vector3.ONE * 0.1)),
		])
	return fallback


func _get_carrier_velocity_world() -> Vector3:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return Vector3.ZERO
	if carrier.has_method("get_deck_reference_velocity_vector"):
		return carrier.call("get_deck_reference_velocity_vector") as Vector3
	return _get_deck_reference_velocity()


func _get_carrier_approach_arrival_speed_limit(desired_speed_mps: float = -1.0) -> float:
	var max_cruise := maxf(minf(cruise_speed_mps, max_speed_mps), 0.0)
	var desired_speed := max_cruise
	if desired_speed_mps > 0.0:
		desired_speed = minf(desired_speed_mps, max_cruise)
	if not is_instance_valid(aircraft):
		return desired_speed
	var approach_world := _get_carrier_approach_point_world_pos()
	if approach_world == Vector3.INF:
		return desired_speed
	var dist_to_gate := _flat_distance(aircraft.global_position, approach_world)
	var carrier_speed := _get_carrier_velocity_world().length()
	var arrival_speed := maxf(carrier_speed, 0.0) + maxf(carrier_approach_arrival_relative_speed_mps, 0.0)
	desired_speed = maxf(desired_speed, arrival_speed)
	var capture_radius := maxf(carrier_approach_capture_radius_m, 5.0)
	# Use decel_distance_m (the same knob as transit braking) as the speed match window.
	# This keeps carrier approach tuning unified with general transit decel per aircraft type.
	var match_distance := maxf(decel_distance_m, capture_radius + 300.0)
	# Implied decel rate from decel_distance_m: a = v²/2d
	var implied_decel := maxf(desired_speed * desired_speed / (2.0 * maxf(decel_distance_m, 1.0)), 0.1)
	var ramp_t := clampf((dist_to_gate - capture_radius) / maxf(match_distance - capture_radius, 1.0), 0.0, 1.0)
	var ramp_limit := lerpf(arrival_speed, desired_speed, ramp_t)
	var brake_distance := maxf(dist_to_gate - capture_radius, 0.0)
	var decel_limit := sqrt(arrival_speed * arrival_speed + 2.0 * implied_decel * brake_distance)
	var limit := minf(ramp_limit, decel_limit)
	limit = clampf(limit, arrival_speed, desired_speed)

	_carrier_approach_speed_log_s -= _physics_delta
	if debug_enabled and _carrier_approach_speed_log_s <= 0.0 and dist_to_gate < maxf(match_distance * 1.25, 1000.0):
		_carrier_approach_speed_log_s = maxf(carrier_approach_speed_log_interval_s, 0.25)
		_debug_event("carrier_approach_speed_plan", "dist=%.1f limit=%.1f desired=%.1f carrier=%.1f ramp=%.2f decel_limit=%.1f match_dist=%.1f implied_decel=%.1f" % [
			dist_to_gate,
			limit,
			desired_speed,
			carrier_speed,
			ramp_t,
			decel_limit,
			match_distance,
			implied_decel,
		])
	return limit


func _fly_carrier_approach_gate(
		approach_world: Vector3,
		carrier_fwd: Vector3,
		carrier_right: Vector3,
		carrier_vel: Vector3,
		speed_limit_mps: float,
		delta: float
) -> void:
	var current_pos := aircraft.global_position
	var control_vel := _get_control_velocity()

	var to_gate_now := approach_world - current_pos
	to_gate_now.y = 0.0
	var dist_now := to_gate_now.length()
	var max_closure := minf(maxf(minf(cruise_speed_mps, max_speed_mps), 0.0), maxf(speed_limit_mps, 0.0))
	var stop_distance := maxf(dist_now - maxf(carrier_approach_capture_radius_m, 1.0), 0.0)
	var planned_closure := sqrt(2.0 * maxf(carrier_approach_capture_decel_mps2, 0.1) * stop_distance)
	planned_closure = clampf(planned_closure, 0.0, max_closure)
	if stop_distance > 1.0:
		planned_closure = maxf(planned_closure, minf(carrier_approach_capture_min_closure_mps, max_closure))

	var eta := dist_now / maxf(planned_closure, 1.0)
	var predicted_gate := approach_world + carrier_vel * minf(eta, maxf(carrier_approach_gate_prediction_s, 0.0))
	var to_gate := predicted_gate - current_pos
	to_gate.y = 0.0
	var along_error := to_gate.dot(carrier_fwd)
	var lateral_error := to_gate.dot(carrier_right)

	var desired_forward_speed: float
	if along_error >= 0.0:
		desired_forward_speed = minf(planned_closure, along_error * maxf(carrier_approach_capture_along_gain, 0.0))
		if stop_distance > 1.0:
			desired_forward_speed = maxf(desired_forward_speed, minf(carrier_approach_capture_min_closure_mps, planned_closure))
	else:
		desired_forward_speed = clampf(
			along_error * maxf(carrier_approach_capture_along_gain, 0.0),
			-maxf(hover_speed_mps, 0.0),
			0.0
		)
	var desired_lateral_speed := clampf(
		lateral_error * maxf(carrier_approach_capture_lateral_gain, 0.0),
		-maxf(carrier_approach_capture_max_lateral_mps, 0.0),
		maxf(carrier_approach_capture_max_lateral_mps, 0.0)
	)
	var desired_vel := carrier_fwd * desired_forward_speed + carrier_right * desired_lateral_speed

	var forward := aircraft.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var right := aircraft.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT

	var fwd_speed := control_vel.dot(forward)
	var lat_speed := control_vel.dot(right)
	var vertical_speed := control_vel.y
	var horizontal_speed := Vector2(control_vel.x, control_vel.z).length()
	var fwd_accel := (fwd_speed - _prev_fwd_speed) / maxf(delta, 0.001)
	var lat_accel := (lat_speed - _prev_lat_speed) / maxf(delta, 0.001)
	var vertical_accel: float = (vertical_speed - _prev_vertical_speed) / maxf(delta, 0.001)
	_prev_fwd_speed = fwd_speed
	_prev_lat_speed = lat_speed
	_prev_vertical_speed = vertical_speed
	var reverse_avoidance_t := _get_reverse_avoidance_t(fwd_speed)
	if reverse_avoidance_t > 0.0:
		var current_desired_forward := desired_vel.dot(forward)
		var recovery_forward := lerpf(
			current_desired_forward,
			maxf(reverse_avoidance_forward_speed_mps, 0.0),
			reverse_avoidance_t
		)
		desired_vel += forward * (recovery_forward - current_desired_forward)

	var to_gate_dir := to_gate.normalized() if to_gate.length_squared() > 1.0 else carrier_fwd
	var align_t := clampf(
		1.0 - dist_now / maxf(carrier_approach_heading_align_distance_m, 1.0),
		0.0,
		1.0
	)
	var desired_heading := to_gate_dir.lerp(carrier_fwd, align_t)
	desired_heading.y = 0.0
	desired_heading = desired_heading.normalized() if desired_heading.length_squared() > 0.001 else carrier_fwd

	var yaw_error := forward.signed_angle_to(desired_heading, Vector3.UP)
	var yaw_rate := aircraft.angular_velocity.y
	var yaw_limit := _get_yaw_limit_for_speed(horizontal_speed)
	var target_yaw := clampf(yaw_error * yaw_gain - yaw_rate * yaw_rate_damping, -yaw_limit, yaw_limit)
	_yaw_cmd = move_toward(_yaw_cmd, target_yaw, maxf(yaw_command_rate, 0.01) * delta)

	var vel_err_fwd := desired_vel.dot(forward) - fwd_speed
	var vel_err_lat := desired_vel.dot(right) - lat_speed
	var cyclic_limit := clampf(max_cyclic_input, 0.0, 1.0)
	var speed_pitch := -vel_err_fwd * cyclic_speed_gain + fwd_accel * cyclic_speed_d_gain
	var target_vertical_rate := clampf(
		(approach_world.y - (current_pos.y + vertical_speed * cyclic_altitude_rate_lookahead_s))
				* cyclic_target_climb_from_alt_error_mps,
		-maxf(cyclic_target_sink_mps, 0.0),
		maxf(cyclic_target_climb_mps, 0.0)
	)
	target_vertical_rate += _airborne_separation_vertical_avoidance_mps
	var vertical_rate_error := target_vertical_rate - vertical_speed
	var altitude_pitch := clampf(
		vertical_rate_error * cyclic_altitude_rate_gain
				- vertical_accel * maxf(cyclic_vertical_accel_damping, 0.0),
		-cyclic_limit,
		cyclic_limit
	)
	var target_pitch := clampf(speed_pitch + altitude_pitch, -cyclic_limit, cyclic_limit)
	target_pitch = _apply_reverse_avoidance_pitch(target_pitch, fwd_speed)
	var target_roll := clampf(
		vel_err_lat * cyclic_lat_vel_gain
				- lat_accel * maxf(cyclic_lat_d_gain, 0.0)
				- yaw_error * coordinated_turn_gain,
		-cyclic_limit,
		cyclic_limit
	)

	_pitch_cmd = move_toward(_pitch_cmd, target_pitch, maxf(cyclic_rate, 0.01) * delta)
	_roll_cmd = move_toward(_roll_cmd, target_roll, maxf(cyclic_rate, 0.01) * delta)
	_speed_target_mps = desired_vel.length()
	_nav_waypoint = Vector3(predicted_gate.x, approach_world.y, predicted_gate.z)

	_debug_target_vertical_rate_mps = target_vertical_rate
	_debug_vertical_rate_error_mps = vertical_rate_error
	_debug_forward_error_mps = vel_err_fwd
	_debug_lateral_error_mps = vel_err_lat
	_debug_speed_pitch = speed_pitch
	_debug_altitude_pitch = altitude_pitch
	_debug_turn_roll = target_roll
	_debug_sharp_turn = 0.0
	_debug_pedal_turn = 0.0
	_debug_low_speed_turn = 0.0
	_debug_high_speed_turn = 0.0
	_debug_backward_turn = reverse_avoidance_t
	_debug_bank_pullback = 0.0
	_debug_target_yaw = target_yaw
	_debug_terrain_recovery = 0.0
	_debug_vertical_priority = 0.0

	_set_helicopter_input(_pitch_cmd, _roll_cmd, _yaw_cmd)
	# Gentle altitude hold — avoid the full LANDING boost which causes 40m oscillations.
	var gate_alt_error := approach_world.y - current_pos.y
	var gate_desired_climb := clampf(gate_alt_error * altitude_to_climb_gain * 1.5, -max_descent_mps, max_climb_mps)
	var gate_climb_error := gate_desired_climb - vertical_speed
	var collective_target := clampf(_get_collective_trim() + gate_climb_error * collective_climb_gain * 1.5, 0.4, 1.0)
	_debug_collective_target = collective_target
	_apply_collective(collective_target)


func _request_carrier_landing_clearance_from_deck() -> bool:
	if not is_instance_valid(aircraft):
		return false
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm and fdm.has_method("request_landing_clearance"):
		return bool(fdm.request_landing_clearance(aircraft))
	if fdm and fdm.has_method("can_accept_landing"):
		return bool(fdm.can_accept_landing(aircraft))
	return true


func _has_carrier_landing_clearance_from_deck() -> bool:
	if not is_instance_valid(aircraft):
		return false
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm and fdm.has_method("has_landing_clearance"):
		return bool(fdm.has_landing_clearance(aircraft))
	return false


func _get_carrier_queue_hold_position(approach_world: Vector3, _carrier_fwd: Vector3) -> Vector3:
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	# 0 = cleared (active landing slot), 1+ = queue position, -1 = not tracked.
	var queue_pos := -1
	if fdm and is_instance_valid(aircraft):
		if fdm.has_method("get_landing_queue_position"):
			queue_pos = int(fdm.call("get_landing_queue_position", aircraft))
		# If not in the queue array but already has clearance, treat as cleared (0).
		if queue_pos < 0 and fdm.has_method("has_landing_clearance") \
				and bool(fdm.call("has_landing_clearance", aircraft)):
			queue_pos = 0
	# Cleared or unknown — fly to AP1.
	if queue_pos <= 0:
		return approach_world
	# Waiting in queue — fly to Hold Point N (1-indexed, capped at 4).
	var marker_name := "Helicopter Hold Point %d" % mini(queue_pos, 4)
	var hold := _get_carrier_marker_world_pos(marker_name)
	if hold != Vector3.INF:
		return hold
	return approach_world


func _release_carrier_landing_clearance_from_deck() -> void:
	if not is_instance_valid(aircraft):
		return
	_set_carrier_landing_final_active(false)
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm and fdm.has_method("release_landing_clearance"):
		fdm.release_landing_clearance(aircraft)


func _notify_helicopter_landed_on_carrier_deck() -> void:
	if not is_instance_valid(aircraft):
		return
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm and fdm.has_method("notify_helicopter_landed_on_carrier"):
		fdm.notify_helicopter_landed_on_carrier(aircraft)


func _update_combat_attack(delta: float, fallback_speed_mps: float) -> bool:
	if not combat_enabled or not is_instance_valid(aircraft):
		_clear_combat_attack("disabled")
		_clear_combat_plan_job()
		_clear_combat_route_job()
		return false
	if not _combat_plan.is_empty():
		# Abort mid-run if the phase changed away from OUTBOUND (e.g. rescue commanded).
		if combat_outbound_only and mission_phase != MissionPhase.OUTBOUND:
			_clear_combat_attack("phase_changed")
			return false
		return _execute_combat_attack(fallback_speed_mps)
	if _combat_task_id != -1:
		var completed_plan := _finish_combat_plan_job_if_ready()
		if completed_plan:
			return _execute_combat_attack(fallback_speed_mps)
		_log_combat_debug("job", "waiting_for_async_plan")
		return false
	if not _can_start_combat_attack():
		return false

	_combat_scan_timer_s -= delta
	if _combat_scan_timer_s > 0.0:
		return false
	_combat_scan_timer_s = maxf(combat_scan_interval_s, 0.1)

	var weapon_options := _get_combat_weapon_options()
	if weapon_options.is_empty():
		_log_combat_debug("no_weapons", "")
		return false
	var targets := _get_combat_target_candidates()
	if targets.is_empty():
		_log_combat_debug("no_targets", "range=%.0f" % combat_target_scan_range_m)
		return false

	targets = _limit_combat_target_candidates(targets)
	_log_combat_debug("scan", "targets=%d weapons=%s nearest=%s async=%s" % [
		targets.size(),
		_describe_combat_weapon_options(weapon_options),
		_describe_nearest_combat_target(targets),
		str(combat_plan_async_enabled),
	])
	if combat_plan_async_enabled:
		if _start_combat_plan_job(targets, weapon_options):
			return false
		_log_combat_debug("job", "skipped_async_snapshot")
		return false

	var plan: Dictionary = AttackPlannerScript.build_air_attack_plan(
		aircraft,
		targets,
		weapon_options,
		Callable(self, "_get_ground_height_at_position"),
		_get_combat_plan_params()
	)
	if plan.is_empty():
		_log_combat_debug("no_plan", "targets=%d weapons=%d" % [targets.size(), weapon_options.size()])
		return false

	return _activate_combat_plan(plan, weapon_options)


func _can_start_combat_attack() -> bool:
	if state != State.LOW_LEVEL_TRANSIT:
		_log_combat_debug("not_ready", "reason=state current=%s" % _state_name())
		return false
	if _landing_on_carrier or _carrier_approach_phase != CarrierApproachPhase.NONE:
		_log_combat_debug("not_ready", "reason=carrier_landing cphase=%s" % _carrier_approach_phase_name())
		return false
	if combat_outbound_only and mission_phase != MissionPhase.OUTBOUND:
		_log_combat_debug("not_ready", "reason=mission phase=%s outbound_only=%s" % [_mission_name(), str(combat_outbound_only)])
		return false
	if mission_phase == MissionPhase.INBOUND:
		var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
		if carrier != null and _flat_distance(aircraft.global_position, carrier.global_position) < combat_min_carrier_distance_m:
			_log_combat_debug("not_ready", "reason=near_carrier dist=%.0f min=%.0f" % [
				_flat_distance(aircraft.global_position, carrier.global_position),
				combat_min_carrier_distance_m,
			])
			return false
	return true


func _activate_combat_plan(plan: Dictionary, weapon_options: Array) -> bool:
	if plan.is_empty():
		return false
	_combat_plan = plan
	_reset_combat_aim_controller()
	_reset_combat_rocket_salvo_state()
	_reset_combat_route_state()
	var weapon: Dictionary = {}
	if not _combat_plan.has("weapon"):
		weapon = _resolve_combat_weapon_option(String(_combat_plan.get("weapon_kind", "")), weapon_options)
	else:
		var weapon_variant: Variant = _combat_plan.get("weapon", {})
		if weapon_variant is Dictionary:
			weapon = weapon_variant as Dictionary
	if weapon.is_empty():
		_combat_plan.clear()
		return false
	_combat_plan["weapon"] = weapon
	_combat_phase = "ingress"
	_combat_phase_started_s = _elapsed_s()
	_combat_fire_log_s = 0.0
	_start_combat_route_job()
	var target := _combat_plan_target()
	var weapon_kind := String(_combat_plan.get("weapon_kind", "unknown"))
	_update_combat_hardpoint_weapon_preference_after_plan(weapon_kind, weapon)
	_sync_combat_control_weapon_selection(weapon_kind, weapon)
	_write_combat_report_plan_start(target, weapon_kind)
	if target != null:
		_log_combat_debug("plan", "target=%s weapon=%s dist=%.0f" % [
			target.name,
			weapon_kind,
			_flat_distance(aircraft.global_position, target.global_position),
		], true)
	return true


func _start_combat_plan_job(targets: Array, weapon_options: Array) -> bool:
	if _combat_task_id != -1:
		return true
	var grid := _build_combat_grid_snapshot()
	if grid.is_empty():
		return false
	var target_snapshot := _build_combat_target_snapshot(targets)
	if target_snapshot.is_empty():
		return false
	var weapon_snapshot := _build_combat_weapon_snapshot(weapon_options)
	if weapon_snapshot.is_empty():
		return false
	_combat_job_data = {
		"start_ms": Time.get_ticks_msec(),
		"attacker_pos": aircraft.global_position,
		"targets": target_snapshot,
		"weapon_options": weapon_snapshot,
		"grid": grid,
		"params": _get_combat_plan_params(),
		"cancelled": false,
		"result": {},
	}
	_combat_task_id = WorkerThreadPool.add_task(func():
		_run_threaded_combat_plan_job(_combat_job_data)
	)
	_log_combat_debug("job", "started targets=%d weapons=%d" % [target_snapshot.size(), weapon_snapshot.size()])
	return true


func _finish_combat_plan_job_if_ready() -> bool:
	if _combat_task_id == -1:
		return false
	if not WorkerThreadPool.is_task_completed(_combat_task_id):
		return false
	WorkerThreadPool.wait_for_task_completion(_combat_task_id)
	_combat_task_id = -1
	var data := _combat_job_data
	_combat_job_data = {}
	if _combat_variant_truthy(data.get("cancelled", false)):
		_combat_target_nodes_by_id.clear()
		return false
	var result_variant: Variant = data.get("result", {})
	if not (result_variant is Dictionary):
		_combat_target_nodes_by_id.clear()
		return false
	var plan: Dictionary = result_variant as Dictionary
	if plan.is_empty():
		_combat_target_nodes_by_id.clear()
		var targets_variant: Variant = data.get("targets", [])
		var target_count := 0
		if targets_variant is Array:
			target_count = (targets_variant as Array).size()
		_log_combat_debug("no_plan", "async targets=%d" % target_count)
		return false
	var target_id := int(plan.get("target_instance_id", 0))
	var target := _combat_node3d_from_variant(_combat_target_nodes_by_id.get(target_id, null))
	_combat_target_nodes_by_id.clear()
	if target == null or not _is_valid_combat_target(target):
		return false
	plan["target"] = target
	var weapon_options := _get_combat_weapon_options()
	return _activate_combat_plan(plan, weapon_options)


func _start_combat_route_job() -> bool:
	if not combat_route_pathfinding_enabled:
		return false
	if _combat_route_task_id != -1:
		return true
	var grid := _build_combat_grid_snapshot()
	if grid.is_empty():
		return false
	var route_data := _build_combat_route_job_data(grid)
	if route_data.is_empty():
		return false
	_combat_route_job_data = route_data
	_combat_route_task_id = WorkerThreadPool.add_task(func():
		_run_threaded_combat_route_job(_combat_route_job_data)
	)
	_log_combat_debug("route", "started_threaded")
	return true


func _finish_combat_route_job_if_ready() -> bool:
	if _combat_route_task_id == -1:
		return _combat_route_ready
	if not WorkerThreadPool.is_task_completed(_combat_route_task_id):
		return false
	WorkerThreadPool.wait_for_task_completion(_combat_route_task_id)
	_combat_route_task_id = -1
	var data := _combat_route_job_data
	_combat_route_job_data = {}
	if _combat_variant_truthy(data.get("cancelled", false)):
		_reset_combat_route_state()
		return false
	var result_variant: Variant = data.get("result", {})
	if not (result_variant is Dictionary):
		_reset_combat_route_state()
		return false
	var result: Dictionary = result_variant as Dictionary
	if not _combat_variant_truthy(result.get("success", false)):
		_reset_combat_route_state()
		_log_combat_debug("route", "failed reason=%s" % String(result.get("reason", "unknown")), true)
		return false
	var points_variant: Variant = result.get("points", [])
	var phases_variant: Variant = result.get("phases", PackedStringArray())
	if not (points_variant is Array):
		_reset_combat_route_state()
		return false
	var route_points: Array[Vector3] = []
	var points_array: Array = points_variant as Array
	for point_variant in points_array:
		if point_variant is Vector3:
			route_points.append(point_variant)
	if route_points.is_empty():
		_reset_combat_route_state()
		return false
	_combat_route_points = route_points
	_combat_route_phases = PackedStringArray()
	if phases_variant is PackedStringArray:
		var packed_phases: PackedStringArray = phases_variant as PackedStringArray
		_combat_route_phases = packed_phases
	elif phases_variant is Array:
		var phases_array: Array = phases_variant as Array
		for phase_variant in phases_array:
			_combat_route_phases.append(String(phase_variant))
	while _combat_route_phases.size() < _combat_route_points.size():
		_combat_route_phases.append("ingress")
	_combat_route_index = 0
	_combat_route_ready = true
	_log_combat_debug("route", "ready points=%d fallback=%s" % [
		_combat_route_points.size(),
		str(_combat_variant_truthy(result.get("used_direct_fallback", false))),
	], true)
	return true


func _cancel_combat_plan_job() -> void:
	if _combat_task_id == -1:
		return
	_combat_job_data["cancelled"] = true


func _clear_combat_plan_job() -> void:
	if _combat_task_id != -1:
		_combat_job_data["cancelled"] = true
		if WorkerThreadPool.is_task_completed(_combat_task_id):
			WorkerThreadPool.wait_for_task_completion(_combat_task_id)
			_combat_task_id = -1
			_combat_job_data.clear()
			_combat_target_nodes_by_id.clear()


func _cancel_combat_route_job() -> void:
	if _combat_route_task_id == -1:
		return
	_combat_route_job_data["cancelled"] = true


func _clear_combat_route_job() -> void:
	if _combat_route_task_id != -1:
		_combat_route_job_data["cancelled"] = true
		if WorkerThreadPool.is_task_completed(_combat_route_task_id):
			WorkerThreadPool.wait_for_task_completion(_combat_route_task_id)
			_combat_route_task_id = -1
			_combat_route_job_data.clear()
	_reset_combat_route_state()


func _get_combat_plan_params() -> Dictionary:
	return {
		"allow_bombs": combat_allow_bombs,
		"target_aim_height_m": 1.4,
		"start_clearance_grace_m": 40.0,
	}


func _build_combat_route_job_data(grid: Dictionary) -> Dictionary:
	var required_keys := ["ingress", "fire_start", "fire_end", "egress"]
	for key in required_keys:
		if _combat_plan_position(key) == Vector3.INF:
			return {}
	var reference_ground := _get_heightmap_reference_ground_y()
	var max_route_terrain_y := _get_heightmap_max_route_terrain_y(reference_ground)
	var flight_ceiling := _get_heightmap_flight_ceiling_m(reference_ground)
	var params := _get_threaded_heightmap_path_params(reference_ground, max_route_terrain_y, flight_ceiling)
	var current_pos := aircraft.global_position
	var ingress := _combat_plan_position("ingress")
	var fire_start := _combat_plan_position("fire_start")
	var fire_end := _combat_plan_position("fire_end")
	var egress := _combat_plan_position("egress")
	var legs: Array[Dictionary] = []
	_append_combat_path_leg(legs, current_pos, ingress, "ingress", grid, params, reference_ground, max_route_terrain_y)
	_append_combat_path_leg(legs, ingress, fire_start, "ingress", grid, params, reference_ground, max_route_terrain_y)
	_append_combat_fire_corridor_leg(legs, fire_start, fire_end)
	_append_combat_path_leg(legs, fire_end, egress, "egress", grid, params, reference_ground, max_route_terrain_y)
	if legs.is_empty():
		return {}
	return {
		"start_ms": Time.get_ticks_msec(),
		"legs": legs,
		"cancelled": false,
		"result": {},
	}


func _append_combat_path_leg(
		legs: Array[Dictionary],
		start: Vector3,
		goal: Vector3,
		phase: String,
		grid: Dictionary,
		params: Dictionary,
		reference_ground: float,
		max_route_terrain_y: float
) -> void:
	var leg_data := _make_threaded_path_job_data(start, goal, grid, params, reference_ground, max_route_terrain_y)
	if leg_data.is_empty():
		legs.append({"kind": "direct", "start": start, "goal": goal, "phase": phase})
		return
	legs.append({"kind": "path", "data": leg_data, "phase": phase, "goal": goal})


func _append_combat_fire_corridor_leg(legs: Array[Dictionary], start: Vector3, goal: Vector3) -> void:
	var spacing := maxf(combat_route_fire_corridor_spacing_m, 10.0)
	var distance := _flat_distance(start, goal)
	var steps := maxi(int(ceil(distance / spacing)), 1)
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		legs.append({"kind": "direct_point", "point": start.lerp(goal, t), "phase": "attack"})


func _get_threaded_heightmap_path_params(reference_ground: float, max_route_terrain_y: float, flight_ceiling: float) -> Dictionary:
	return {
		"heightmap_path_max_edge_risk_m": heightmap_path_max_edge_risk_m,
		"heightmap_path_edge_risk_penalty": heightmap_path_edge_risk_penalty,
		"heightmap_path_mountain_buffer_cells": heightmap_path_mountain_buffer_cells,
		"heightmap_path_mountain_avoidance_m": heightmap_path_mountain_avoidance_m,
		"heightmap_path_max_step_climb_m": heightmap_path_max_step_climb_m,
		"heightmap_path_altitude_penalty": heightmap_path_altitude_penalty,
		"heightmap_path_climb_penalty": heightmap_path_climb_penalty,
		"heightmap_path_high_terrain_penalty": heightmap_path_high_terrain_penalty,
		"heightmap_path_same_level_wall_risk_start_m": heightmap_path_same_level_wall_risk_start_m,
		"heightmap_path_same_level_wall_penalty": heightmap_path_same_level_wall_penalty,
		"heightmap_path_ground_route_penalty": heightmap_path_ground_route_penalty,
		"heightmap_path_low_route_penalty": heightmap_path_low_route_penalty,
		"heightmap_path_top_level_penalty": heightmap_path_top_level_penalty,
		"heightmap_path_upper_level_penalty": heightmap_path_upper_level_penalty,
		"heightmap_path_level_change_penalty": heightmap_path_level_change_penalty,
		"heightmap_path_target_agl_m": heightmap_path_target_agl_m,
		"min_terrain_clearance_m": min_terrain_clearance_m,
		"heightmap_path_carrot_distance_m": heightmap_path_carrot_distance_m,
		"heightmap_path_insert_spacing_m": heightmap_path_insert_spacing_m,
		"heightmap_path_simplify_altitude_error_m": heightmap_path_simplify_altitude_error_m,
		"terrain_climb_lookahead_m": terrain_climb_lookahead_m,
		"terrain_sample_spacing_m": terrain_sample_spacing_m,
		"heightmap_path_simplify_enabled": heightmap_path_simplify_enabled,
		"min_altitude": -1000.0,
		"max_altitude": 10000.0,
		"route_terrain_ceiling": max_route_terrain_y,
		"flight_ceiling": flight_ceiling,
	}


func _make_threaded_path_job_data(
		start: Vector3,
		goal: Vector3,
		grid: Dictionary,
		params: Dictionary,
		reference_ground: float,
		max_route_terrain_y: float
) -> Dictionary:
	var cols := int(grid.get("cols", 0))
	var rows := int(grid.get("rows", 0))
	var origin_x := float(grid.get("origin_x", 0.0))
	var origin_z := float(grid.get("origin_z", 0.0))
	var cell_size := maxf(float(grid.get("cell_size", 1.0)), 1.0)
	if cols <= 0 or rows <= 0:
		return {}
	var dist_max := maxf(absf(start.x - goal.x), absf(start.z - goal.z))
	var pad := maxf(heightmap_path_search_padding_m, dist_max * 0.5)
	var gx_min: int = clampi(int(floor((minf(start.x, goal.x) - pad - origin_x) / cell_size)), 0, cols - 1)
	var gz_min: int = clampi(int(floor((minf(start.z, goal.z) - pad - origin_z) / cell_size)), 0, rows - 1)
	var gx_max: int = clampi(int(ceil((maxf(start.x, goal.x) + pad - origin_x) / cell_size)), 0, cols - 1)
	var gz_max: int = clampi(int(ceil((maxf(start.z, goal.z) + pad - origin_z) / cell_size)), 0, rows - 1)
	var start_cell := Vector2i(
		clampi(int((start.x - origin_x) / cell_size), gx_min, gx_max),
		clampi(int((start.z - origin_z) / cell_size), gz_min, gz_max)
	)
	var end_cell := Vector2i(
		clampi(int((goal.x - origin_x) / cell_size), gx_min, gx_max),
		clampi(int((goal.z - origin_z) / cell_size), gz_min, gz_max)
	)
	var max_iterations := maxi((gx_max - gx_min + 1) * (gz_max - gz_min + 1) * 3, 20000)
	return {
		"start_ms": Time.get_ticks_msec(),
		"current_pos": start,
		"goal": goal,
		"gx_min": gx_min,
		"gz_min": gz_min,
		"gx_max": gx_max,
		"gz_max": gz_max,
		"start_cell": start_cell,
		"end_cell": end_cell,
		"reference_ground": reference_ground,
		"max_route_terrain_y": max_route_terrain_y,
		"max_iterations": max_iterations,
		"grid": grid,
		"params": params,
		"result": {},
	}


func _limit_combat_target_candidates(targets: Array) -> Array:
	var limit := maxi(combat_target_candidate_limit, 1)
	if targets.size() <= limit:
		return targets
	var scored: Array = []
	for target_variant in targets:
		var target := _combat_node3d_from_variant(target_variant)
		if target == null:
			continue
		scored.append({
			"target": target,
			"distance": _flat_distance(aircraft.global_position, target.global_position),
		})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance", INF)) < float(b.get("distance", INF))
	)
	var limited: Array = []
	for i in range(mini(scored.size(), limit)):
		limited.append(scored[i].get("target"))
	return limited


func _build_combat_target_snapshot(targets: Array) -> Array:
	_combat_target_nodes_by_id.clear()
	var out: Array = []
	for target_variant in targets:
		var target := _combat_node3d_from_variant(target_variant)
		if target == null:
			continue
		var instance_id := target.get_instance_id()
		_combat_target_nodes_by_id[instance_id] = target
		out.append({
			"instance_id": instance_id,
			"name": target.name,
			"position": target.global_position,
			"aim_position": target.global_position + Vector3.UP * 1.4,
		})
	return out


func _build_combat_weapon_snapshot(weapon_options: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for option_variant in weapon_options:
		if not (option_variant is Dictionary):
			continue
		var option: Dictionary = option_variant as Dictionary
		var kind := String(option.get("kind", ""))
		if kind.is_empty() or seen.has(kind):
			continue
		seen[kind] = true
		var snapshot: Dictionary = {"kind": kind}
		if option.has("score_bias"):
			snapshot["score_bias"] = float(option.get("score_bias", 0.0))
		out.append(snapshot)
	return out


func _resolve_combat_weapon_option(kind: String, weapon_options: Array) -> Dictionary:
	for option_variant in weapon_options:
		if not (option_variant is Dictionary):
			continue
		var option: Dictionary = option_variant as Dictionary
		if String(option.get("kind", "")) == kind:
			return option
	return {}


func _build_combat_grid_snapshot() -> Dictionary:
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")
	if nav_grid == null:
		return {}
	var cols := int(nav_grid.get("_cols"))
	var rows := int(nav_grid.get("_rows"))
	var heights := nav_grid.get("_heights") as PackedFloat32Array
	if cols <= 0 or rows <= 0 or heights.is_empty():
		return {}
	return {
		"cols": cols,
		"rows": rows,
		"heights": heights,
		"origin_x": float(nav_grid.get("_origin_x")),
		"origin_z": float(nav_grid.get("_origin_z")),
		"cell_size": maxf(float(nav_grid.get("cell_size_m")), 1.0),
		"impassable": float(nav_grid.get("IMPASSABLE")),
		"query_cols": int(nav_grid.get("_query_cols")),
		"query_rows": int(nav_grid.get("_query_rows")),
		"query_heights": nav_grid.get("_query_heights") as PackedFloat32Array,
		"query_height_variation": nav_grid.get("_query_height_variation") as PackedFloat32Array,
		"query_max_heights": nav_grid.get("_query_max_heights") as PackedFloat32Array,
		"query_origin_x": float(nav_grid.get("_query_origin_x")),
		"query_origin_z": float(nav_grid.get("_query_origin_z")),
		"query_cell_size": maxf(float(nav_grid.get("query_cell_size_m")), 1.0),
	}


static func _run_threaded_combat_plan_job(data: Dictionary) -> void:
	var attacker_variant: Variant = data.get("attacker_pos", Vector3.ZERO)
	var attacker_pos: Vector3 = Vector3.ZERO
	if attacker_variant is Vector3:
		attacker_pos = attacker_variant
	var targets_variant: Variant = data.get("targets", [])
	var targets: Array = []
	if targets_variant is Array:
		targets = targets_variant as Array
	var weapons_variant: Variant = data.get("weapon_options", [])
	var weapon_options: Array = []
	if weapons_variant is Array:
		weapon_options = weapons_variant as Array
	var grid_variant: Variant = data.get("grid", {})
	var grid: Dictionary = {}
	if grid_variant is Dictionary:
		grid = grid_variant as Dictionary
	var params_variant: Variant = data.get("params", {})
	var params: Dictionary = {}
	if params_variant is Dictionary:
		params = params_variant as Dictionary
	data["result"] = AttackPlannerScript.build_air_attack_plan_snapshot(
		attacker_pos,
		targets,
		weapon_options,
		grid,
		params
	)


static func _run_threaded_combat_route_job(data: Dictionary) -> void:
	var route_points: Array[Vector3] = []
	var route_phases := PackedStringArray()
	var used_direct_fallback := false
	var legs_variant: Variant = data.get("legs", [])
	if not (legs_variant is Array):
		data["result"] = {"success": false, "reason": "missing legs"}
		return
	var legs: Array = legs_variant as Array
	for leg_variant in legs:
		if _static_variant_truthy(data.get("cancelled", false)):
			data["result"] = {"success": false, "reason": "cancelled"}
			return
		if not (leg_variant is Dictionary):
			continue
		var leg: Dictionary = leg_variant as Dictionary
		var phase := String(leg.get("phase", "ingress"))
		var kind := String(leg.get("kind", ""))
		if kind == "direct_point":
			var point_variant: Variant = leg.get("point", Vector3.INF)
			if point_variant is Vector3:
				_thread_append_combat_route_point(route_points, route_phases, point_variant, phase)
			continue
		if kind == "direct":
			used_direct_fallback = true
			var direct_goal_variant: Variant = leg.get("goal", Vector3.INF)
			if direct_goal_variant is Vector3:
				_thread_append_combat_route_point(route_points, route_phases, direct_goal_variant, phase)
			continue
		if kind != "path":
			continue
		var leg_data_variant: Variant = leg.get("data", {})
		if not (leg_data_variant is Dictionary):
			continue
		var leg_data: Dictionary = leg_data_variant as Dictionary
		_run_threaded_pathfinding_job(leg_data)
		var result_variant: Variant = leg_data.get("result", {})
		if not (result_variant is Dictionary):
			used_direct_fallback = true
			var fallback_goal_variant: Variant = leg.get("goal", Vector3.INF)
			if fallback_goal_variant is Vector3:
				_thread_append_combat_route_point(route_points, route_phases, fallback_goal_variant, phase)
			continue
		var result: Dictionary = result_variant as Dictionary
		if not _static_variant_truthy(result.get("success", false)):
			used_direct_fallback = true
			var failed_goal_variant: Variant = leg.get("goal", Vector3.INF)
			if failed_goal_variant is Vector3:
				_thread_append_combat_route_point(route_points, route_phases, failed_goal_variant, phase)
			continue
		var path_variant: Variant = result.get("final_path", [])
		if not (path_variant is Array):
			continue
		var path_array: Array = path_variant as Array
		for point_variant in path_array:
			if point_variant is Vector3:
				_thread_append_combat_route_point(route_points, route_phases, point_variant, phase)
	if route_points.is_empty():
		data["result"] = {"success": false, "reason": "empty route"}
		return
	data["result"] = {
		"success": true,
		"points": route_points,
		"phases": route_phases,
		"used_direct_fallback": used_direct_fallback,
		"elapsed_ms": Time.get_ticks_msec() - int(data.get("start_ms", Time.get_ticks_msec())),
	}


static func _thread_append_combat_route_point(
		route_points: Array[Vector3],
		route_phases: PackedStringArray,
		point: Vector3,
		phase: String
) -> void:
	if point == Vector3.INF:
		return
	if not route_points.is_empty() and Vector2(route_points[route_points.size() - 1].x - point.x, route_points[route_points.size() - 1].z - point.z).length() < 1.0:
		route_points[route_points.size() - 1] = point
		if route_phases.size() == route_points.size():
			route_phases[route_phases.size() - 1] = phase
		return
	route_points.append(point)
	route_phases.append(phase)


static func _static_variant_truthy(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return float(value) != 0.0
	if value is String:
		var text := String(value).strip_edges().to_lower()
		return text == "true" or text == "1" or text == "yes" or text == "on"
	return value != null


func _execute_combat_attack(fallback_speed_mps: float) -> bool:
	var target := _combat_plan_target()
	if target == null or _combat_variant_truthy(target.get("is_destroyed")):
		_clear_combat_attack("target_lost")
		return false

	if _combat_route_task_id != -1 and not _finish_combat_route_job_if_ready():
		var ingress_wait := _combat_plan_position("ingress")
		if ingress_wait != Vector3.INF:
			var wait_speed := minf(fallback_speed_mps, float(_combat_plan.get("attack_speed_mps", fallback_speed_mps)))
			_log_combat_debug("route", "waiting wp_dist=%.0f" % _flat_distance(aircraft.global_position, ingress_wait))
			_nav_waypoint = ingress_wait
			_fly_toward(_nav_waypoint, wait_speed, _physics_delta)
			return true
		return false
	if combat_route_pathfinding_enabled and not _combat_route_ready:
		_start_combat_route_job()
		if _combat_route_task_id != -1:
			return true
	if _combat_route_ready:
		return _execute_combat_route_attack(target, fallback_speed_mps)

	var current_pos := aircraft.global_position
	var waypoint := Vector3.INF
	var speed := fallback_speed_mps
	match _combat_phase:
		"ingress":
			waypoint = _combat_plan_position("ingress")
			speed = minf(fallback_speed_mps, float(_combat_plan.get("attack_speed_mps", fallback_speed_mps)))
			var ingress_next := _combat_plan_position("fire_start")
			if ingress_next == Vector3.INF:
				ingress_next = _combat_plan_position("fire_end")
			if waypoint != Vector3.INF \
					and (_flat_distance(current_pos, waypoint) <= combat_ingress_reach_radius_m \
					or _has_passed_combat_waypoint(current_pos, waypoint, ingress_next, combat_ingress_reach_radius_m)):
				_combat_phase = "attack"
				_combat_phase_started_s = _elapsed_s()
				_reset_combat_aim_controller()
				_release_combat_aim_takeover("phase_attack", false)
				_reset_combat_rocket_salvo_state()
				_start_combat_attack_run_report(target)
				_log_combat_debug("phase", "attack target=%s" % target.name, true)
		"attack":
			waypoint = _combat_plan_position("fire_end")
			speed = minf(fallback_speed_mps, float(_combat_plan.get("attack_speed_mps", fallback_speed_mps)))
			_try_fire_combat_weapon(target)
			var attack_next := _combat_plan_position("egress")
			if waypoint != Vector3.INF \
					and (_flat_distance(current_pos, waypoint) <= combat_fire_end_radius_m \
					or _has_passed_combat_waypoint(current_pos, waypoint, attack_next, combat_fire_end_radius_m)):
				if _should_hold_combat_attack_for_first_rocket(target):
					_log_combat_debug("hold_attack", "first_rocket target=%s dist=%.0f" % [
						target.name,
						aircraft.global_position.distance_to(target.global_position),
					])
				else:
					_finish_combat_attack_run_report("left_fire_corridor")
					_combat_phase = "egress"
					_combat_phase_started_s = _elapsed_s()
					_release_combat_aim_takeover("phase_egress", true)
					_log_combat_debug("phase", "egress target=%s" % target.name, true)
		"egress":
			waypoint = _combat_plan_position("egress")
			speed = maxf(float(_combat_plan.get("egress_speed_mps", fallback_speed_mps)), fallback_speed_mps)
			var egress_prev := _combat_plan_position("fire_end")
			var egress_next := Vector3.INF
			if waypoint != Vector3.INF and egress_prev != Vector3.INF:
				var egress_dir := waypoint - egress_prev
				egress_dir.y = 0.0
				if egress_dir.length_squared() > 1.0:
					egress_next = waypoint + egress_dir.normalized() * maxf(combat_egress_reach_radius_m, 1.0)
			if waypoint != Vector3.INF \
					and (_flat_distance(current_pos, waypoint) <= combat_egress_reach_radius_m \
					or _has_passed_combat_waypoint(current_pos, waypoint, egress_next, combat_egress_reach_radius_m)):
				_clear_combat_attack("complete")
				_update_navigation_plan()
				return false
		_:
			_clear_combat_attack("bad_phase")
			return false

	if waypoint == Vector3.INF:
		_clear_combat_attack("bad_waypoint")
		return false
	speed = _apply_combat_aim_takeover_speed(speed)
	_log_combat_debug("run", "phase=%s target=%s wp_dist=%.0f speed=%.1f" % [
		_combat_phase,
		target.name,
		_flat_distance(current_pos, waypoint),
		speed,
	])
	_nav_waypoint = waypoint
	_fly_toward(_nav_waypoint, speed, _physics_delta)
	return true


func _execute_combat_route_attack(target: Node3D, fallback_speed_mps: float) -> bool:
	if _combat_route_points.is_empty():
		return false
	var current_pos := aircraft.global_position
	var route_index_before_advance: int = _combat_route_index
	var phase_before_advance: String = _combat_phase
	_advance_combat_route(current_pos)
	if phase_before_advance == "attack" \
			and route_index_before_advance >= 0 \
			and route_index_before_advance < _combat_route_points.size() \
			and _get_combat_route_phase(_combat_route_index) != "attack" \
			and _should_hold_combat_attack_for_first_rocket(target):
		_combat_route_index = route_index_before_advance
		_log_combat_debug("hold_attack", "route_first_rocket target=%s dist=%.0f" % [
			target.name,
			aircraft.global_position.distance_to(target.global_position),
		])
	if _combat_route_index >= _combat_route_points.size():
		_clear_combat_attack("complete")
		_update_navigation_plan()
		return false
	if _combat_route_index == _combat_route_points.size() - 1 \
			and _get_combat_route_phase(_combat_route_index) == "egress" \
			and _flat_distance(current_pos, _combat_route_points[_combat_route_index]) <= maxf(combat_egress_reach_radius_m, combat_route_advance_radius_m):
		_clear_combat_attack("complete")
		_update_navigation_plan()
		return false

	var route_phase := _get_combat_route_phase(_combat_route_index)
	if route_phase != _combat_phase:
		_combat_phase = route_phase
		_combat_phase_started_s = _elapsed_s()
		_log_combat_debug("phase", "%s target=%s route=%d/%d" % [
			_combat_phase,
			target.name,
			_combat_route_index,
			_combat_route_points.size(),
		], true)
		if _combat_phase == "attack":
			_reset_combat_aim_controller()
			_release_combat_aim_takeover("phase_attack", false)
			_reset_combat_rocket_salvo_state()
			_start_combat_attack_run_report(target)
		else:
			if phase_before_advance == "attack":
				_finish_combat_attack_run_report("left_route_attack_segment")
			_release_combat_aim_takeover("phase_%s" % _combat_phase, true)
	if _combat_phase == "attack":
		_try_fire_combat_weapon(target)

	var route_point := _combat_route_points[_combat_route_index]
	var waypoint := _get_combat_route_carrot_point(current_pos)
	if waypoint == Vector3.INF:
		waypoint = route_point
	var speed := fallback_speed_mps
	match _combat_phase:
		"ingress", "attack":
			speed = minf(fallback_speed_mps, float(_combat_plan.get("attack_speed_mps", fallback_speed_mps)))
		"egress":
			speed = maxf(float(_combat_plan.get("egress_speed_mps", fallback_speed_mps)), fallback_speed_mps)
	speed = _apply_combat_aim_takeover_speed(speed)
	_nav_waypoint = waypoint
	_log_combat_debug("run", "phase=%s target=%s route=%d/%d route_dist=%.0f carrot_dist=%.0f speed=%.1f" % [
		_combat_phase,
		target.name,
		_combat_route_index,
		_combat_route_points.size(),
		_flat_distance(current_pos, route_point),
		_flat_distance(current_pos, waypoint),
		speed,
	])
	_fly_toward(_nav_waypoint, speed, _physics_delta)
	return true


func _advance_combat_route(current_pos: Vector3) -> void:
	var original_index := _combat_route_index
	var radius := maxf(combat_route_advance_radius_m, 1.0)
	while _combat_route_index < _combat_route_points.size() - 1 \
			and _flat_distance(current_pos, _combat_route_points[_combat_route_index]) <= radius:
		_combat_route_index += 1
	while _combat_route_index < _combat_route_points.size() - 1:
		var cur_pt := _combat_route_points[_combat_route_index]
		var nxt_pt := _combat_route_points[_combat_route_index + 1]
		var to_next := Vector3(nxt_pt.x - cur_pt.x, 0.0, nxt_pt.z - cur_pt.z)
		var to_here := Vector3(current_pos.x - cur_pt.x, 0.0, current_pos.z - cur_pt.z)
		var dist_to_wp := to_here.length()
		if to_next.length_squared() > 1.0 \
				and to_here.dot(to_next.normalized()) > 0.0 \
				and dist_to_wp < maxf(radius * 3.0, 240.0):
			_combat_route_index += 1
		else:
			break
	if _combat_route_index != original_index:
		_log_combat_debug("route_advance", "from=%d to=%d/%d" % [
			original_index,
			_combat_route_index,
			_combat_route_points.size(),
		])


func _get_combat_route_carrot_point(current_pos: Vector3) -> Vector3:
	if _combat_route_points.is_empty() or _combat_route_index >= _combat_route_points.size():
		return Vector3.INF
	var carrot_distance := maxf(combat_route_carrot_distance_m, combat_route_advance_radius_m)
	var previous := current_pos
	var best := _combat_route_points[_combat_route_index]
	var traveled := 0.0
	for i in range(_combat_route_index, _combat_route_points.size()):
		var point := _combat_route_points[i]
		var segment_len := _flat_distance(previous, point)
		if traveled + segment_len >= carrot_distance:
			var t := 1.0
			if segment_len > 0.001:
				t = (carrot_distance - traveled) / segment_len
			return previous.lerp(point, clampf(t, 0.0, 1.0))
		traveled += segment_len
		best = point
		previous = point
	return best


func _has_passed_combat_waypoint(current_pos: Vector3, waypoint: Vector3, next_point: Vector3, radius: float) -> bool:
	if waypoint == Vector3.INF or next_point == Vector3.INF:
		return false
	var to_next := Vector3(next_point.x - waypoint.x, 0.0, next_point.z - waypoint.z)
	var to_here := Vector3(current_pos.x - waypoint.x, 0.0, current_pos.z - waypoint.z)
	if to_next.length_squared() <= 1.0:
		return false
	if to_here.dot(to_next.normalized()) <= 0.0:
		return false
	return to_here.length() < maxf(radius * 3.0, 240.0)


func _get_combat_route_phase(index: int) -> String:
	if index >= 0 and index < _combat_route_phases.size():
		var phase := String(_combat_route_phases[index])
		if not phase.is_empty():
			return phase
	return "ingress"


func _combat_plan_position(key: String) -> Vector3:
	var value: Variant = _combat_plan.get(key, Vector3.INF)
	return value if value is Vector3 else Vector3.INF


func _combat_plan_target() -> Node3D:
	var value: Variant = _combat_plan.get("target", null)
	return _combat_node3d_from_variant(value)


func _get_combat_aim_commands(
		base_pitch: float,
		base_roll: float,
		base_yaw: float,
		delta: float,
		cyclic_limit: float,
		yaw_limit: float
) -> Dictionary:
	if not combat_aim_enabled or _combat_phase != "attack" or _combat_plan.is_empty():
		_reset_combat_aim_controller()
		return {}
	var weapon_kind := String(_combat_plan.get("weapon_kind", ""))
	if weapon_kind != COMBAT_WEAPON_ROCKET and weapon_kind != COMBAT_WEAPON_GUN:
		_reset_combat_aim_controller()
		return {}
	var target := _combat_plan_target()
	if target == null:
		_reset_combat_aim_controller()
		return {}
	var solution := _get_combat_aim_solution(target)
	if solution.is_empty():
		_reset_combat_aim_controller()
		return {}

	var yaw_error := float(solution.get("yaw_error", 0.0))
	var pitch_error := float(solution.get("pitch_error", 0.0))
	var yaw_deadband: float = deg_to_rad(maxf(combat_aim_yaw_deadband_deg, 0.0))
	var yaw_in_deadband: bool = absf(yaw_error) <= yaw_deadband
	if yaw_in_deadband:
		yaw_error = 0.0
		_combat_aim_yaw_integral *= 0.5
	var zero_cross_epsilon: float = deg_to_rad(0.2)
	if not is_nan(_combat_aim_prev_yaw_error) \
			and absf(yaw_error) > zero_cross_epsilon \
			and absf(_combat_aim_prev_yaw_error) > zero_cross_epsilon \
			and (yaw_error > 0.0) != (_combat_aim_prev_yaw_error > 0.0):
		_combat_aim_yaw_integral *= 0.25
	if not is_nan(_combat_aim_prev_pitch_error) \
			and absf(pitch_error) > zero_cross_epsilon \
			and absf(_combat_aim_prev_pitch_error) > zero_cross_epsilon \
			and (pitch_error > 0.0) != (_combat_aim_prev_pitch_error > 0.0):
		_combat_aim_pitch_integral *= 0.5
	_combat_aim_yaw_integral = clampf(
		_combat_aim_yaw_integral + yaw_error * delta,
		-maxf(combat_aim_integral_limit, 0.0),
		maxf(combat_aim_integral_limit, 0.0)
	)
	_combat_aim_pitch_integral = clampf(
		_combat_aim_pitch_integral + pitch_error * delta,
		-maxf(combat_aim_integral_limit, 0.0),
		maxf(combat_aim_integral_limit, 0.0)
	)
	var yaw_derivative := 0.0
	if not is_nan(_combat_aim_prev_yaw_error):
		yaw_derivative = (yaw_error - _combat_aim_prev_yaw_error) / maxf(delta, 0.001)
	if yaw_in_deadband:
		yaw_derivative = 0.0
	var pitch_derivative := 0.0
	if not is_nan(_combat_aim_prev_pitch_error):
		pitch_derivative = (pitch_error - _combat_aim_prev_pitch_error) / maxf(delta, 0.001)
	_combat_aim_prev_yaw_error = yaw_error
	_combat_aim_prev_pitch_error = pitch_error
	_update_combat_aim_settle(weapon_kind, yaw_error, pitch_error, yaw_derivative, pitch_derivative, delta)

	var takeover_active: bool = _is_combat_aim_takeover_active()
	var yaw_limit_for_aim: float = maxf(combat_aim_max_yaw_input, 0.0)
	var yaw_correction_rate: float = maxf(combat_aim_yaw_correction_rate, 0.01)
	if takeover_active:
		yaw_limit_for_aim = maxf(yaw_limit_for_aim, combat_aim_takeover_max_yaw_input)
		yaw_correction_rate = maxf(yaw_correction_rate, combat_aim_takeover_yaw_correction_rate)
	var yaw_p: float = maxf(combat_aim_yaw_p, 0.0)
	if takeover_active:
		yaw_p *= maxf(combat_aim_takeover_yaw_gain, 0.0)
	var raw_yaw_correction: float = clampf(
		yaw_error * yaw_p
		+ _combat_aim_yaw_integral * maxf(combat_aim_yaw_i, 0.0)
		+ yaw_derivative * maxf(combat_aim_yaw_d, 0.0),
		-yaw_limit_for_aim,
		yaw_limit_for_aim
	)
	var yaw_correction: float = move_toward(
		_combat_aim_last_yaw_correction,
		raw_yaw_correction,
		yaw_correction_rate * delta
	)
	if raw_yaw_correction == 0.0:
		yaw_correction = move_toward(
			yaw_correction,
			0.0,
			yaw_correction_rate * delta
		)
	_combat_aim_last_yaw_correction = yaw_correction
	var pitch_gain: float = 1.0
	var pitch_limit: float = maxf(combat_aim_max_pitch_input, 0.0)
	match weapon_kind:
		COMBAT_WEAPON_ROCKET:
			pitch_gain = maxf(combat_rocket_pitch_control_gain, 0.0)
			pitch_limit = maxf(pitch_limit, combat_rocket_max_pitch_input)
		COMBAT_WEAPON_GUN:
			pitch_gain = maxf(combat_gun_pitch_control_gain, 0.0)
			pitch_limit = maxf(pitch_limit, combat_gun_max_pitch_input)
	if takeover_active:
		pitch_gain *= maxf(combat_aim_takeover_pitch_control_gain, 0.0)
		pitch_limit = maxf(pitch_limit, combat_aim_takeover_max_pitch_input)
	var pitch_correction := clampf(
		pitch_error * maxf(combat_aim_pitch_p, 0.0) * pitch_gain
		+ _combat_aim_pitch_integral * maxf(combat_aim_pitch_i, 0.0)
		+ pitch_derivative * maxf(combat_aim_pitch_d, 0.0),
		-pitch_limit,
		pitch_limit
	)
	var rocket_nose_down_t: float = 0.0
	if takeover_active and weapon_kind == COMBAT_WEAPON_ROCKET and pitch_error < -deg_to_rad(0.25):
		rocket_nose_down_t = clampf(absf(pitch_error) / deg_to_rad(6.0), 0.0, 1.0)
		pitch_correction = clampf(
			pitch_correction - maxf(combat_rocket_takeover_nose_down_bias, 0.0) * rocket_nose_down_t,
			-pitch_limit,
			pitch_limit
		)
	var roll_blend: float = clampf(combat_aim_roll_level_blend, 0.0, 1.0)
	# When the aim controller is commanding nose-down to put the weapon line on a
	# target below the flight path, blend out the cruise base pitch (which holds
	# the nose UP for altitude/forward flight). Otherwise the correction is just
	# added on top of cruise pitch-up and the nose never actually comes down — the
	# "pipper sits just above the target" symptom on rocket/gun runs that don't
	# happen to be in takeover. Blend is proportional to nose-down demand.
	var nose_down_authority_t: float = 0.0
	if pitch_correction < 0.0:
		nose_down_authority_t = clampf(absf(pitch_correction) / maxf(combat_aim_attack_nose_down_full_input, 0.01), 0.0, 1.0)
	var attack_base_pitch: float = lerpf(base_pitch, 0.0, nose_down_authority_t)
	var target_pitch: float = clampf(attack_base_pitch + pitch_correction, -cyclic_limit, cyclic_limit)
	var target_roll: float = lerpf(base_roll, 0.0, roll_blend)
	var target_yaw: float = clampf(base_yaw + yaw_correction, -yaw_limit, yaw_limit)
	if takeover_active:
		target_pitch = clampf(pitch_correction, -cyclic_limit, cyclic_limit)
		if rocket_nose_down_t > 0.0:
			target_pitch = minf(
				target_pitch,
				-maxf(combat_rocket_takeover_min_nose_down_input, 0.0) * rocket_nose_down_t
			)
		target_roll = lerpf(base_roll, 0.0, clampf(combat_aim_takeover_roll_level_blend, 0.0, 1.0))
		target_yaw = clampf(yaw_correction, -yaw_limit, yaw_limit)
	var pitch_rate_scale: float = 1.0
	if weapon_kind == COMBAT_WEAPON_ROCKET and pitch_correction < 0.0:
		pitch_rate_scale = maxf(combat_rocket_nose_down_rate_scale, 1.0)
	elif weapon_kind == COMBAT_WEAPON_GUN and pitch_correction < 0.0:
		# Same nose-down rate boost rockets get: slew the pipper down onto the
		# target fast enough to fire before the run ends.
		pitch_rate_scale = maxf(combat_gun_nose_down_rate_scale, 1.0)
	if takeover_active:
		pitch_rate_scale = maxf(pitch_rate_scale, combat_aim_takeover_pitch_rate_scale)
	var collective_floor: float = -1.0
	if takeover_active and weapon_kind == COMBAT_WEAPON_ROCKET and rocket_nose_down_t > 0.0:
		collective_floor = maxf(combat_rocket_takeover_collective_floor, _get_collective_trim())
	var corrected: Dictionary = {
		"pitch": target_pitch,
		"roll": target_roll,
		"yaw": target_yaw,
		"pitch_rate_scale": pitch_rate_scale,
		"collective_floor": collective_floor,
	}
	if combat_debug_enabled and (absf(yaw_error) > deg_to_rad(3.0) or absf(pitch_error) > deg_to_rad(3.0)):
		var aim_point: Vector3 = Vector3.ZERO
		var aim_point_variant: Variant = solution.get("aim_point", Vector3.ZERO)
		if aim_point_variant is Vector3:
			aim_point = aim_point_variant
		_log_combat_debug("aim", "yaw=%.1f pitch=%.1f yaw_cmd=%.2f pitch_cmd=%.2f target_pitch=%.2f pitch_rate=%.1f dot=%.3f takeover=%s aim=%s" % [
			rad_to_deg(yaw_error),
			rad_to_deg(pitch_error),
			yaw_correction,
			pitch_correction,
			target_pitch,
			pitch_rate_scale,
			float(solution.get("dot", 0.0)),
			str(takeover_active),
			str(aim_point.snapped(Vector3.ONE)),
		])
	return corrected


func _get_combat_aim_solution(target: Node3D) -> Dictionary:
	var weapon_variant: Variant = _combat_plan.get("weapon", {})
	if not (weapon_variant is Dictionary):
		return {}
	var weapon: Dictionary = weapon_variant as Dictionary
	var hardpoint := _get_primary_combat_hardpoint(weapon)
	if hardpoint == null:
		return {}
	var aim_point := _get_combat_predicted_aim_point(target, hardpoint)
	# Aim from the aircraft centerline, not the hardpoint. The controller can only
	# rotate the body about its center of mass, so measuring the error from an
	# off-centerline hardpoint leaves a fixed parallax angle the body can never
	# null out (the persistent yaw/pitch residual seen on every gun pass). At
	# combat range, pointing the nose correctly is good enough.
	var launch_pos := aircraft.global_position
	var to_aim := aim_point - launch_pos
	if to_aim.length_squared() < 1.0:
		return {}
	var desired_dir := to_aim.normalized()
	var weapon_forward := aircraft.global_transform.basis.z.normalized()
	if weapon_forward.length_squared() < 0.001:
		return {}
	var desired_flat := Vector3(desired_dir.x, 0.0, desired_dir.z)
	var forward_flat := Vector3(weapon_forward.x, 0.0, weapon_forward.z)
	if desired_flat.length_squared() < 0.001 or forward_flat.length_squared() < 0.001:
		return {}
	desired_flat = desired_flat.normalized()
	forward_flat = forward_flat.normalized()
	var yaw_error := forward_flat.signed_angle_to(desired_flat, Vector3.UP)
	var pitch_error := asin(clampf(desired_dir.y, -1.0, 1.0)) - asin(clampf(weapon_forward.y, -1.0, 1.0))
	return {
		"aim_point": aim_point,
		"desired_dir": desired_dir,
		"yaw_error": yaw_error,
		"pitch_error": pitch_error,
		"dot": weapon_forward.dot(desired_dir),
		"hardpoint": hardpoint,
	}


func _get_combat_predicted_aim_point(target: Node3D, hardpoint: Hardpoint) -> Vector3:
	var aim_height := float(_combat_plan.get("target_aim_height_m", 1.4))
	var target_pos := target.global_position + Vector3.UP * aim_height
	var weapon_kind := String(_combat_plan.get("weapon_kind", ""))
	var muzzle_speed := _get_combat_weapon_muzzle_speed(hardpoint)
	var target_velocity := _get_node_velocity(target)
	if weapon_kind == COMBAT_WEAPON_ROCKET:
		target_pos.y -= maxf(combat_rocket_aim_lower_bias_m, 0.0)
		# Pure CCIP feedback: the impact sim already models the full rocket arc
		# (gravity, drag, motor) from the current nose attitude, so it tells us
		# exactly where a rocket fired now would land. We drive the nose so that
		# simulated impact walks onto the target — the residual (target - impact)
		# is the only correction needed. No analytic loft is added on top, which
		# is what previously parked the pipper above the target (double drop comp).
		var ccip_aim_point: Vector3 = _get_combat_rocket_ccip_feedback_aim_point(target, target_pos, target_velocity)
		if ccip_aim_point != Vector3.INF:
			return ccip_aim_point
		# No CCIP solution yet (target not raycasting to terrain): fall back to the
		# analytic lofted-launch solver so the nose still leads toward an arc.
		var launch_velocity: Vector3 = _get_combat_launch_point_velocity(hardpoint.global_position)
		var rocket_speed: float = muzzle_speed + maxf(combat_rocket_motor_speed_bias_mps, 0.0)
		return _predict_combat_ballistic_aim_point(
			hardpoint.global_position,
			launch_velocity,
			target_pos,
			target_velocity,
			rocket_speed,
			clampf(combat_rocket_drop_compensation, 0.0, 2.0)
		)
	var distance := hardpoint.global_position.distance_to(target_pos)
	var impact_time := clampf(distance / maxf(muzzle_speed, 1.0), 0.0, 8.0)
	target_pos += target_velocity * impact_time
	return target_pos


func _get_combat_rocket_ccip_feedback_aim_point(
		target: Node3D,
		target_pos: Vector3,
		target_velocity: Vector3
) -> Vector3:
	# Returns a corrected aim point that, when the nose points at it, drives the
	# simulated rocket impact onto the target. Returns Vector3.INF if there is no
	# usable CCIP solution, so the caller can fall back to the analytic solver.
	if not combat_rocket_ccip_guidance_enabled:
		return Vector3.INF
	var ccip_solution: Dictionary = _get_combat_rocket_ccip_solution(target)
	if ccip_solution.is_empty() or not _combat_variant_truthy(ccip_solution.get("has_impact", false)):
		return Vector3.INF
	var impact_variant: Variant = ccip_solution.get("impact_position", Vector3.ZERO)
	if not (impact_variant is Vector3):
		return Vector3.INF
	var impact_pos: Vector3 = impact_variant
	var time_to_impact: float = maxf(float(ccip_solution.get("time_to_impact", 0.0)), 0.0)
	# Where the target will be when the rocket arrives (lead for a moving target).
	var target_reference: Vector3 = target_pos + target_velocity * time_to_impact
	# Residual miss of the current arc. Shifting the aim point by this amount moves
	# the nose just enough that the simulated impact lands on the target; as the arc
	# converges, the residual -> 0 and the pipper settles on the target.
	var miss_correction: Vector3 = target_reference - impact_pos
	var max_correction: float = maxf(combat_rocket_ccip_aim_correction_max_m, 0.0)
	if max_correction > 0.0 and miss_correction.length() > max_correction:
		miss_correction = miss_correction.normalized() * max_correction
	return target_reference + miss_correction * clampf(combat_rocket_ccip_aim_correction_strength, 0.0, 1.5)


func _get_combat_rocket_ccip_solution(target: Node3D, force_refresh: bool = false) -> Dictionary:
	if not combat_rocket_ccip_guidance_enabled:
		return {}
	if not is_instance_valid(aircraft) or not aircraft.has_method("calculate_rocket_ccip_impact_point"):
		return {}
	var target_id: int = target.get_instance_id() if target != null and is_instance_valid(target) else 0
	var now_s: float = _elapsed_s()
	var cache_age_s: float = now_s - _combat_rocket_ccip_cache_time_s
	if not force_refresh \
			and target_id == _combat_rocket_ccip_cache_target_id \
			and not _combat_rocket_ccip_cache.is_empty() \
			and cache_age_s < maxf(combat_rocket_ccip_recompute_interval_s, 0.02):
		return _combat_rocket_ccip_cache
	var result_variant: Variant = aircraft.call("calculate_rocket_ccip_impact_point")
	if result_variant is Dictionary:
		_combat_rocket_ccip_cache = result_variant as Dictionary
	else:
		_combat_rocket_ccip_cache = {}
	_combat_rocket_ccip_cache_time_s = now_s
	_combat_rocket_ccip_cache_target_id = target_id
	return _combat_rocket_ccip_cache


func _get_combat_rocket_ccip_miss_m(target: Node3D, ccip_solution: Dictionary) -> float:
	if target == null or not is_instance_valid(target):
		return INF
	if ccip_solution.is_empty() or not _combat_variant_truthy(ccip_solution.get("has_impact", false)):
		return INF
	var impact_variant: Variant = ccip_solution.get("impact_position", Vector3.ZERO)
	if not (impact_variant is Vector3):
		return INF
	var impact_pos: Vector3 = impact_variant
	var aim_height: float = float(_combat_plan.get("target_aim_height_m", 1.4))
	var target_pos: Vector3 = target.global_position + Vector3.UP * aim_height
	target_pos.y -= maxf(combat_rocket_aim_lower_bias_m, 0.0)
	var target_velocity: Vector3 = _get_node_velocity(target)
	var time_to_impact: float = maxf(float(ccip_solution.get("time_to_impact", 0.0)), 0.0)
	target_pos += target_velocity * time_to_impact
	return Vector2(target_pos.x - impact_pos.x, target_pos.z - impact_pos.z).length()


func _is_combat_rocket_ccip_ready_for_fire(target: Node3D) -> bool:
	if not combat_rocket_ccip_guidance_enabled:
		return true
	var ccip_solution: Dictionary = _get_combat_rocket_ccip_solution(target)
	var miss_m: float = _get_combat_rocket_ccip_miss_m(target, ccip_solution)
	var tolerance_m: float = maxf(combat_rocket_ccip_fire_tolerance_m, 0.0)
	if miss_m <= tolerance_m:
		return true
	if ccip_solution.is_empty() or not _combat_variant_truthy(ccip_solution.get("has_impact", false)):
		if combat_rocket_ccip_requires_solution_to_fire:
			_log_combat_debug("hold_fire", "rocket_ccip no_solution")
			return false
		return true
	var impact_variant: Variant = ccip_solution.get("impact_position", Vector3.ZERO)
	var impact_text: String = "?"
	if impact_variant is Vector3:
		var impact_pos: Vector3 = impact_variant
		impact_text = str(impact_pos.snapped(Vector3.ONE))
	_log_combat_debug("hold_fire", "rocket_ccip miss=%.1f tol=%.1f impact=%s" % [
		miss_m,
		tolerance_m,
		impact_text,
	])
	return false


func _get_combat_launch_point_velocity(world_pos: Vector3) -> Vector3:
	if not is_instance_valid(aircraft):
		return Vector3.ZERO
	var point_velocity: Vector3 = aircraft.linear_velocity
	var offset: Vector3 = world_pos - aircraft.global_position
	point_velocity += aircraft.angular_velocity.cross(offset)
	return point_velocity


func _predict_combat_ballistic_aim_point(
		shooter_pos: Vector3,
		shooter_vel: Vector3,
		target_pos: Vector3,
		target_vel: Vector3,
		projectile_speed: float,
		gravity_scale: float
) -> Vector3:
	var muzzle_speed: float = maxf(projectile_speed, 50.0)
	var gravity_dir_variant: Variant = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3(0, -1, 0))
	var gravity_dir: Vector3 = Vector3(0, -1, 0)
	if gravity_dir_variant is Vector3:
		gravity_dir = gravity_dir_variant.normalized()
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gravity_vec: Vector3 = gravity_dir * gravity_mag * maxf(gravity_scale, 0.0)
	var relative_pos: Vector3 = target_pos - shooter_pos
	var relative_vel: Vector3 = target_vel - shooter_vel
	var intercept_t: float = _solve_combat_intercept_time_no_gravity(relative_pos, relative_vel, muzzle_speed)
	if intercept_t <= 0.0:
		intercept_t = relative_pos.length() / muzzle_speed
	intercept_t = clampf(intercept_t, 0.05, 6.0)

	var best_intercept: Vector3 = target_pos + target_vel * intercept_t
	var best_muzzle_vec: Vector3 = Vector3.ZERO
	for _i in range(4):
		var future_target: Vector3 = target_pos + target_vel * intercept_t
		var required_muzzle_vec: Vector3 = (future_target - shooter_pos - shooter_vel * intercept_t - 0.5 * gravity_vec * intercept_t * intercept_t) / intercept_t
		var required_speed: float = required_muzzle_vec.length()
		if required_speed <= 0.0001:
			break
		best_intercept = future_target
		best_muzzle_vec = required_muzzle_vec
		var speed_error: float = required_speed - muzzle_speed
		if absf(speed_error) <= 0.5:
			break
		intercept_t = clampf(intercept_t * (required_speed / muzzle_speed), 0.05, 6.0)

	if best_muzzle_vec.length_squared() < 0.001:
		var fallback_t: float = shooter_pos.distance_to(target_pos) / muzzle_speed
		var fallback_target: Vector3 = target_pos + target_vel * fallback_t
		var fallback_dir: Vector3 = (fallback_target - shooter_pos).normalized()
		return shooter_pos + fallback_dir * maxf((fallback_target - shooter_pos).length(), 50.0)

	var launch_dir: Vector3 = best_muzzle_vec.normalized()
	var aim_dist: float = maxf((best_intercept - shooter_pos).length(), 50.0)
	return shooter_pos + launch_dir * aim_dist


func _solve_combat_intercept_time_no_gravity(relative_pos: Vector3, relative_vel: Vector3, projectile_speed: float) -> float:
	var speed_sq: float = projectile_speed * projectile_speed
	var a: float = relative_vel.dot(relative_vel) - speed_sq
	var b: float = 2.0 * relative_pos.dot(relative_vel)
	var c: float = relative_pos.dot(relative_pos)
	if absf(a) < 0.0001:
		if absf(b) < 0.0001:
			return 0.0
		var linear_t: float = -c / b
		if linear_t > 0.0:
			return linear_t
		return 0.0
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return 0.0
	var sqrt_disc: float = sqrt(discriminant)
	var t1: float = (-b - sqrt_disc) / (2.0 * a)
	var t2: float = (-b + sqrt_disc) / (2.0 * a)
	var best_t: float = INF
	if t1 > 0.0:
		best_t = minf(best_t, t1)
	if t2 > 0.0:
		best_t = minf(best_t, t2)
	if best_t < INF:
		return best_t
	return 0.0


func _get_primary_combat_hardpoint(weapon: Dictionary) -> Hardpoint:
	var hardpoints_variant: Variant = weapon.get("hardpoints", [])
	if not (hardpoints_variant is Array):
		return null
	var hardpoints: Array = hardpoints_variant as Array
	for hp_variant in hardpoints:
		var hp := _combat_hardpoint_from_variant(hp_variant)
		if hp != null and hp.weapon_instance != null:
			return hp
	return null


func _get_combat_weapon_muzzle_speed(hardpoint: Hardpoint) -> float:
	if hardpoint == null or hardpoint.weapon_instance == null:
		return 250.0
	var value: Variant = hardpoint.weapon_instance.get("muzzle_velocity")
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return maxf(float(value), 1.0)
	if hardpoint.weapon_instance.has_method("get_predicted_initial_velocity") and is_instance_valid(aircraft):
		var velocity_variant: Variant = hardpoint.weapon_instance.call("get_predicted_initial_velocity", aircraft)
		if velocity_variant is Vector3:
			var velocity: Vector3 = velocity_variant
			return maxf(velocity.length(), 1.0)
	return 250.0


func _get_combat_fire_alignment_cos(weapon_kind: String, plan_cone_cos: float) -> float:
	var cone_deg := 0.0
	match weapon_kind:
		COMBAT_WEAPON_ROCKET:
			cone_deg = maxf(combat_rocket_fire_alignment_deg, 0.1)
		COMBAT_WEAPON_GUN:
			cone_deg = maxf(combat_gun_fire_alignment_deg, 0.1)
		_:
			return plan_cone_cos
	return maxf(plan_cone_cos, cos(deg_to_rad(cone_deg)))


func _get_combat_aim_settle_angle_rad(weapon_kind: String) -> float:
	match weapon_kind:
		COMBAT_WEAPON_ROCKET:
			return deg_to_rad(maxf(combat_rocket_aim_settle_deg, 0.1))
		COMBAT_WEAPON_GUN:
			return deg_to_rad(maxf(combat_gun_aim_settle_deg, 0.1))
	return deg_to_rad(3.0)


func _get_combat_pitch_aim_settle_angle_rad(weapon_kind: String) -> float:
	match weapon_kind:
		COMBAT_WEAPON_ROCKET:
			return deg_to_rad(maxf(combat_rocket_pitch_aim_settle_deg, 0.1))
	return _get_combat_aim_settle_angle_rad(weapon_kind)


func _get_combat_aim_settle_time_s(weapon_kind: String) -> float:
	match weapon_kind:
		COMBAT_WEAPON_ROCKET:
			return maxf(combat_rocket_aim_settle_time_s, combat_aim_settle_time_s)
		COMBAT_WEAPON_GUN:
			return maxf(combat_gun_aim_settle_time_s, 0.0)
	return maxf(combat_aim_settle_time_s, 0.0)


func _get_combat_aim_settle_max_rate_rad_s(weapon_kind: String) -> float:
	var default_rate: float = maxf(combat_aim_settle_max_rate_deg_s, 0.1)
	match weapon_kind:
		COMBAT_WEAPON_ROCKET:
			return deg_to_rad(maxf(combat_rocket_aim_settle_max_rate_deg_s, 0.1))
		COMBAT_WEAPON_GUN:
			return deg_to_rad(maxf(combat_gun_aim_settle_max_rate_deg_s, 0.1))
	return deg_to_rad(default_rate)


func _get_combat_pitch_aim_settle_max_rate_rad_s(weapon_kind: String) -> float:
	match weapon_kind:
		COMBAT_WEAPON_ROCKET:
			return deg_to_rad(maxf(combat_rocket_pitch_aim_settle_max_rate_deg_s, 0.1))
	return _get_combat_aim_settle_max_rate_rad_s(weapon_kind)


func _update_combat_aim_settle(
		weapon_kind: String,
		yaw_error: float,
		pitch_error: float,
		yaw_derivative: float,
		pitch_derivative: float,
		delta: float
) -> void:
	var yaw_settle_angle: float = _get_combat_aim_settle_angle_rad(weapon_kind)
	var pitch_settle_angle: float = _get_combat_pitch_aim_settle_angle_rad(weapon_kind)
	var yaw_max_rate: float = _get_combat_aim_settle_max_rate_rad_s(weapon_kind)
	var pitch_max_rate: float = _get_combat_pitch_aim_settle_max_rate_rad_s(weapon_kind)
	var error_ok: bool = absf(yaw_error) <= yaw_settle_angle and absf(pitch_error) <= pitch_settle_angle
	var rate_ok: bool = absf(yaw_derivative) <= yaw_max_rate and absf(pitch_derivative) <= pitch_max_rate
	if error_ok and rate_ok:
		_combat_aim_settle_s += delta
	else:
		_combat_aim_settle_s = 0.0


func _is_combat_aim_settled_for_fire(weapon_kind: String, aim_solution: Dictionary, aim_dot: float, fire_cone_cos: float) -> bool:
	if aim_solution.is_empty():
		return false
	var yaw_settle_angle: float = _get_combat_aim_settle_angle_rad(weapon_kind)
	var pitch_settle_angle: float = _get_combat_pitch_aim_settle_angle_rad(weapon_kind)
	var yaw_error := absf(float(aim_solution.get("yaw_error", INF)))
	var pitch_error := absf(float(aim_solution.get("pitch_error", INF)))
	var target_settle_s: float = _get_combat_aim_settle_time_s(weapon_kind)
	var attack_time_s: float = _elapsed_s() - _combat_phase_started_s
	var min_attack_time_s: float = 0.0
	if weapon_kind == COMBAT_WEAPON_ROCKET:
		min_attack_time_s = maxf(combat_rocket_min_attack_time_before_fire_s, 0.0)
	var ready: bool = aim_dot >= fire_cone_cos \
			and yaw_error <= yaw_settle_angle \
			and pitch_error <= pitch_settle_angle \
			and _combat_aim_settle_s >= target_settle_s \
			and attack_time_s >= min_attack_time_s
	if not ready:
		_log_combat_debug("hold_fire", "settling yaw=%.1f/%.1f pitch=%.1f/%.1f settled=%.2f/%.2f attack=%.2f/%.2f dot=%.3f" % [
			rad_to_deg(yaw_error),
			rad_to_deg(yaw_settle_angle),
			rad_to_deg(pitch_error),
			rad_to_deg(pitch_settle_angle),
			_combat_aim_settle_s,
			target_settle_s,
			attack_time_s,
			min_attack_time_s,
			aim_dot,
		])
	return ready


func _get_combat_aim_takeover_elapsed_s() -> float:
	if _combat_aim_takeover_started_s <= 0.0:
		return 0.0
	return maxf(_elapsed_s() - _combat_aim_takeover_started_s, 0.0)


func _is_combat_rocket_fallback_fire_ready(aim_solution: Dictionary, aim_dot: float) -> bool:
	if aim_solution.is_empty() or not _is_combat_aim_takeover_active():
		return false
	var takeover_elapsed_s: float = _get_combat_aim_takeover_elapsed_s()
	if takeover_elapsed_s < maxf(combat_rocket_fallback_fire_after_takeover_s, 0.0):
		return false
	var fallback_yaw_angle_rad: float = deg_to_rad(maxf(combat_rocket_fallback_fire_angle_deg, 0.1))
	var fallback_pitch_angle_rad: float = deg_to_rad(maxf(combat_rocket_fallback_fire_pitch_angle_deg, 0.1))
	var yaw_error: float = absf(float(aim_solution.get("yaw_error", INF)))
	var pitch_error: float = absf(float(aim_solution.get("pitch_error", INF)))
	var fallback_cone_cos: float = cos(maxf(fallback_yaw_angle_rad, fallback_pitch_angle_rad))
	return aim_dot >= fallback_cone_cos and yaw_error <= fallback_yaw_angle_rad and pitch_error <= fallback_pitch_angle_rad


func _should_hold_combat_attack_for_first_rocket(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not is_instance_valid(aircraft):
		return false
	if String(_combat_plan.get("weapon_kind", "")) != COMBAT_WEAPON_ROCKET:
		return false
	if _combat_rocket_salvos_fired > 0:
		return false
	var attack_time_s: float = _elapsed_s() - _combat_phase_started_s
	if attack_time_s >= maxf(combat_rocket_first_salvo_hold_s, 0.0):
		return false
	var fire_range: float = float(_combat_plan.get("fire_range_m", 0.0))
	var dist: float = aircraft.global_position.distance_to(target.global_position)
	if fire_range <= 1.0 or dist > fire_range * 1.15:
		return false
	var aim_solution: Dictionary = _get_combat_aim_solution(target)
	if aim_solution.is_empty():
		return false
	var weapon_variant: Variant = _combat_plan.get("weapon", {})
	if not (weapon_variant is Dictionary):
		return false
	var weapon: Dictionary = weapon_variant as Dictionary
	var aim_dir_variant: Variant = aim_solution.get("desired_dir", Vector3.ZERO)
	if not (aim_dir_variant is Vector3):
		return false
	var aim_dir: Vector3 = aim_dir_variant
	var aim_dot: float = _get_best_combat_weapon_alignment_dot(weapon, aim_dir)
	var hold_cone_cos: float = cos(deg_to_rad(maxf(combat_rocket_fallback_fire_angle_deg + 2.0, 0.1)))
	return aim_dot >= hold_cone_cos


func _request_combat_aim_takeover(weapon_kind: String, dist: float, fire_range: float) -> void:
	if not combat_aim_takeover_enabled or _combat_phase != "attack":
		_release_combat_aim_takeover("disabled", false)
		return
	if weapon_kind != COMBAT_WEAPON_ROCKET and weapon_kind != COMBAT_WEAPON_GUN:
		_release_combat_aim_takeover("weapon", false)
		return
	var range_limit: float = maxf(fire_range * maxf(combat_aim_takeover_range_factor, 1.0), 1.0)
	if dist > range_limit:
		_release_combat_aim_takeover("range", false)
		return
	var now_s: float = _elapsed_s()
	if _combat_aim_takeover_active:
		if now_s - _combat_aim_takeover_started_s > maxf(combat_aim_takeover_max_time_s, 0.1):
			_release_combat_aim_takeover("timeout", true)
		return
	if now_s < _combat_aim_takeover_cooldown_until_s:
		return
	_combat_aim_takeover_active = true
	_combat_aim_takeover_started_s = now_s
	_log_combat_debug("aim_takeover", "start weapon=%s dist=%.0f range=%.0f" % [
		weapon_kind,
		dist,
		fire_range,
	], true)


func _release_combat_aim_takeover(reason: String, start_cooldown: bool) -> void:
	if not _combat_aim_takeover_active:
		return
	_combat_aim_takeover_active = false
	if start_cooldown:
		_combat_aim_takeover_cooldown_until_s = _elapsed_s() + maxf(combat_aim_takeover_cooldown_s, 0.0)
	_log_combat_debug("aim_takeover", "release reason=%s" % reason, true)


func _is_combat_aim_takeover_active() -> bool:
	if not _combat_aim_takeover_active:
		return false
	var now_s: float = _elapsed_s()
	if now_s - _combat_aim_takeover_started_s > maxf(combat_aim_takeover_max_time_s, 0.1):
		_release_combat_aim_takeover("timeout", true)
		return false
	return true


func _apply_combat_aim_takeover_speed(speed_mps: float) -> float:
	if not _is_combat_aim_takeover_active():
		return speed_mps
	return minf(speed_mps, maxf(combat_aim_takeover_speed_mps, 1.0))


func _get_best_combat_weapon_alignment_dot(weapon: Dictionary, aim_dir: Vector3) -> float:
	if aim_dir.length_squared() < 0.001:
		return -1.0
	var hardpoints_variant: Variant = weapon.get("hardpoints", [])
	if not (hardpoints_variant is Array):
		return aircraft.global_transform.basis.z.normalized().dot(aim_dir.normalized()) if is_instance_valid(aircraft) else -1.0
	var best_dot := -1.0
	var hardpoints: Array = hardpoints_variant as Array
	for hp_variant in hardpoints:
		var hp := _combat_hardpoint_from_variant(hp_variant)
		if hp == null:
			continue
		var forward := hp.get_hardpoint_forward_direction().normalized()
		if forward.length_squared() < 0.001:
			continue
		best_dot = maxf(best_dot, forward.dot(aim_dir.normalized()))
	return best_dot


func _try_fire_combat_rocket_salvo(weapon: Dictionary, target: Node3D, dist: float, good_enough_fire: bool, aim_solution: Dictionary, aim_dot: float) -> void:
	if _combat_variant_truthy(target.get("is_destroyed")):
		_clear_combat_attack("target_destroyed")
		return
	var now := _elapsed_s()
	if now < _combat_rocket_assess_until_s:
		_record_combat_attack_run_state("rocket_assess", "wait=%.2f salvos=%d" % [
			_combat_rocket_assess_until_s - now,
			_combat_rocket_salvos_fired,
		], dist, aim_solution, aim_dot)
		_log_combat_debug("hold_fire", "assessing rocket impact wait=%.2f salvos=%d" % [
			_combat_rocket_assess_until_s - now,
			_combat_rocket_salvos_fired,
		])
		return
	if _combat_rocket_salvos_fired >= maxi(combat_rocket_max_salvos_per_attack, 1):
		_record_combat_attack_run_state("rocket_salvo_cap", "salvos=%d" % _combat_rocket_salvos_fired, dist, aim_solution, aim_dot)
		_log_combat_debug("hold_fire", "rocket_salvo_cap salvos=%d" % _combat_rocket_salvos_fired, true)
		return

	var hardpoints := _get_combat_hardpoints_from_weapon(weapon, true)
	if hardpoints.is_empty():
		_record_combat_attack_run_state("rocket_no_ready_hardpoint", "", dist, aim_solution, aim_dot)
		_log_combat_debug("hold_fire", "rocket_no_ready_hardpoint")
		return
	var hp: Hardpoint = hardpoints[_combat_rocket_next_hardpoint_index % hardpoints.size()]
	var salvo_number: int = _combat_rocket_salvos_fired + 1
	var assess_delay_s: float = _estimate_combat_rocket_assess_time(hp, target, dist)
	var ccip_solution: Dictionary = _get_combat_rocket_ccip_solution(target)
	var ccip_miss_m: float = _get_combat_rocket_ccip_miss_m(target, ccip_solution)
	var ccip_impact_text: String = "?"
	var ccip_impact_variant: Variant = ccip_solution.get("impact_position", Vector3.ZERO)
	if ccip_impact_variant is Vector3:
		var ccip_impact_pos: Vector3 = ccip_impact_variant
		ccip_impact_text = str(ccip_impact_pos.snapped(Vector3.ONE * 0.1))
	var fired: bool = hp.fire()
	if not fired:
		_record_combat_attack_run_state("rocket_fire_rejected", "hardpoint=%s" % hp.name, dist, aim_solution, aim_dot)
		_log_combat_debug("hold_fire", "rocket_fire_rejected")
		return
	_combat_rocket_salvos_fired += 1
	_combat_rocket_next_hardpoint_index = (_combat_rocket_next_hardpoint_index + 1) % maxi(hardpoints.size(), 1)
	_combat_rocket_assess_until_s = now + assess_delay_s
	if _combat_aim_takeover_active:
		_combat_aim_takeover_started_s = now
	_queue_combat_shot_report(COMBAT_WEAPON_ROCKET, hp, target, dist, assess_delay_s, aim_solution, aim_dot, {
		"salvo": salvo_number,
		"ccip_miss_m": ccip_miss_m,
		"ccip_impact": ccip_impact_text,
		"fallback_fire": good_enough_fire,
	})
	# Keep rocket aim takeover active across the assess delay so the pipper
	# stays near the target for a possible follow-up salvo.
	if good_enough_fire:
		_log_combat_debug("fallback_fire", "rocket good_enough elapsed=%.2f dot=%.3f yaw=%.1f pitch=%.1f" % [
			_get_combat_aim_takeover_elapsed_s(),
			aim_dot,
			rad_to_deg(float(aim_solution.get("yaw_error", 0.0))),
			rad_to_deg(float(aim_solution.get("pitch_error", 0.0))),
		], true)
	_log_combat_debug("fire", "target=%s weapon=rocket salvo=%d assess=%.2f dist=%.0f hp=%s dot=%.3f yaw=%.1f pitch=%.1f" % [
		target.name,
		_combat_rocket_salvos_fired,
		_combat_rocket_assess_until_s - now,
		dist,
		hp.name,
		aim_dot,
		rad_to_deg(float(aim_solution.get("yaw_error", 0.0))),
		rad_to_deg(float(aim_solution.get("pitch_error", 0.0))),
	], true)


func _estimate_combat_rocket_assess_time(hardpoint: Hardpoint, target: Node3D, fallback_dist: float) -> float:
	var distance := fallback_dist
	if hardpoint != null and target != null and is_instance_valid(target):
		var aim_point := _get_combat_predicted_aim_point(target, hardpoint)
		distance = hardpoint.global_position.distance_to(aim_point)
	var speed := _get_combat_weapon_muzzle_speed(hardpoint) + maxf(combat_rocket_motor_speed_bias_mps, 0.0)
	var flight_time := distance / maxf(speed, 1.0)
	var base_time := maxf(combat_rocket_assess_time_s, 0.0)
	var max_time := maxf(combat_rocket_max_assess_time_s, base_time)
	return clampf(maxf(base_time, flight_time + 0.25), base_time, max_time)


func _get_combat_hardpoints_from_weapon(weapon: Dictionary, require_ready: bool) -> Array[Hardpoint]:
	var out: Array[Hardpoint] = []
	var hardpoints_variant: Variant = weapon.get("hardpoints", [])
	if not (hardpoints_variant is Array):
		return out
	var hardpoints: Array = hardpoints_variant as Array
	for hp_variant in hardpoints:
		var hp := _combat_hardpoint_from_variant(hp_variant)
		if hp == null or hp.weapon_instance == null:
			continue
		if require_ready and not hp.weapon_instance.can_fire():
			continue
		out.append(hp)
	return out


func _reset_combat_aim_controller() -> void:
	_combat_aim_yaw_integral = 0.0
	_combat_aim_pitch_integral = 0.0
	_combat_aim_prev_yaw_error = NAN
	_combat_aim_prev_pitch_error = NAN
	_combat_aim_last_yaw_correction = 0.0
	_combat_aim_settle_s = 0.0
	_combat_aim_takeover_active = false
	_combat_aim_takeover_started_s = 0.0
	_combat_aim_takeover_cooldown_until_s = 0.0


func _reset_combat_rocket_salvo_state() -> void:
	_combat_rocket_assess_until_s = 0.0
	_combat_rocket_salvos_fired = 0
	_combat_rocket_next_hardpoint_index = 0
	_combat_rocket_ccip_cache_time_s = -1000000.0
	_combat_rocket_ccip_cache_target_id = -1
	_combat_rocket_ccip_cache.clear()


func _reset_combat_route_state() -> void:
	_combat_route_points.clear()
	_combat_route_phases = PackedStringArray()
	_combat_route_index = 0
	_combat_route_ready = false


func _clear_combat_attack(reason: String) -> void:
	if _combat_plan.is_empty():
		return
	_finish_combat_attack_run_report(reason)
	_log_combat_debug("clear", "reason=%s phase=%s" % [reason, _combat_phase], true)
	_cancel_combat_route_job()
	_clear_combat_turret_targets()
	_combat_plan.clear()
	_combat_phase = ""
	_combat_phase_started_s = 0.0
	_reset_combat_aim_controller()
	_reset_combat_rocket_salvo_state()
	_reset_combat_route_state()


func _start_combat_attack_run_report(target: Node3D) -> void:
	_finish_combat_attack_run_report("replaced")
	_combat_attack_run_active = true
	_combat_attack_run_id = _combat_next_attack_run_report_id
	_combat_next_attack_run_report_id += 1
	_combat_attack_run_started_s = _elapsed_s()
	_combat_attack_run_weapon = String(_combat_plan.get("weapon_kind", "unknown"))
	_combat_attack_run_target_name = String(target.name) if target != null and is_instance_valid(target) else "unknown"
	_combat_attack_run_target_id = target.get_instance_id() if target != null and is_instance_valid(target) else 0
	_combat_attack_run_shots = 0
	_combat_attack_run_last_hold_reason = "none"
	_combat_attack_run_last_hold_details = ""
	_combat_attack_run_min_dist_m = INF
	_combat_attack_run_best_aim_dot = -1.0
	_combat_attack_run_last_aim_dot = NAN
	_combat_attack_run_last_yaw_deg = NAN
	_combat_attack_run_last_pitch_deg = NAN
	_combat_attack_run_best_ccip_miss_m = INF
	_combat_attack_run_last_ccip_miss_m = INF


func _record_combat_attack_run_state(
		reason: String,
		details: String,
		dist_m: float = NAN,
		aim_solution: Dictionary = {},
		aim_dot: float = NAN,
		ccip_miss_m: float = INF
) -> void:
	if not _combat_attack_run_active:
		return
	if not is_nan(dist_m):
		_combat_attack_run_min_dist_m = minf(_combat_attack_run_min_dist_m, dist_m)
	if not is_nan(aim_dot):
		_combat_attack_run_last_aim_dot = aim_dot
		_combat_attack_run_best_aim_dot = maxf(_combat_attack_run_best_aim_dot, aim_dot)
	if not aim_solution.is_empty():
		_combat_attack_run_last_yaw_deg = rad_to_deg(float(aim_solution.get("yaw_error", NAN)))
		_combat_attack_run_last_pitch_deg = rad_to_deg(float(aim_solution.get("pitch_error", NAN)))
	if ccip_miss_m < INF:
		_combat_attack_run_last_ccip_miss_m = ccip_miss_m
		_combat_attack_run_best_ccip_miss_m = minf(_combat_attack_run_best_ccip_miss_m, ccip_miss_m)
	_combat_attack_run_last_hold_reason = reason
	_combat_attack_run_last_hold_details = details


func _finish_combat_attack_run_report(reason: String) -> void:
	if not _combat_attack_run_active:
		return
	if _combat_attack_run_shots <= 0:
		_write_combat_attack_run_no_shot_report(reason)
	_combat_attack_run_active = false
	_combat_attack_run_id = 0
	_combat_attack_run_started_s = 0.0
	_combat_attack_run_weapon = ""
	_combat_attack_run_target_name = ""
	_combat_attack_run_target_id = 0
	_combat_attack_run_shots = 0
	_combat_attack_run_last_hold_reason = "none"
	_combat_attack_run_last_hold_details = ""
	_combat_attack_run_min_dist_m = INF
	_combat_attack_run_best_aim_dot = -1.0
	_combat_attack_run_last_aim_dot = NAN
	_combat_attack_run_last_yaw_deg = NAN
	_combat_attack_run_last_pitch_deg = NAN
	_combat_attack_run_best_ccip_miss_m = INF
	_combat_attack_run_last_ccip_miss_m = INF


func _write_combat_attack_run_no_shot_report(reason: String) -> void:
	if not combat_report_enabled:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("t=%.2f event=ATTACK_RUN_NO_SHOT run_id=%d craft=%s type=%s weapon=%s target=%s target_id=%d duration=%.2f exit_reason=%s last_hold=%s min_dist=%s best_aim_dot=%s last_aim_dot=%s last_yaw=%s last_pitch=%s best_ccip_miss=%s last_ccip_miss=%s details=\"%s\"" % [
		_elapsed_s(),
		_combat_attack_run_id,
		String(aircraft.name) if is_instance_valid(aircraft) else "unknown",
		_get_aircraft_type_label(),
		_combat_attack_run_weapon,
		_combat_attack_run_target_name,
		_combat_attack_run_target_id,
		maxf(_elapsed_s() - _combat_attack_run_started_s, 0.0),
		reason,
		_combat_attack_run_last_hold_reason,
		_format_combat_report_float(_combat_attack_run_min_dist_m),
		_format_combat_report_float(_combat_attack_run_best_aim_dot),
		_format_combat_report_float(_combat_attack_run_last_aim_dot),
		_format_combat_report_float(_combat_attack_run_last_yaw_deg),
		_format_combat_report_float(_combat_attack_run_last_pitch_deg),
		_format_combat_report_float(_combat_attack_run_best_ccip_miss_m),
		_format_combat_report_float(_combat_attack_run_last_ccip_miss_m),
		_combat_attack_run_last_hold_details.replace("\"", "'"),
	])
	_append_lines_to_log(combat_report_path, lines, "helicopter combat report")
	if combat_report_project_mirror_enabled:
		_append_lines_to_log(combat_report_project_mirror_path, lines, "project helicopter combat report")


func _get_combat_target_candidates() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for group_name in ["gun_emplacements", "ground_vehicles", "buildings", "enemies", "dummy_turrets"]:
		var nodes := get_tree().get_nodes_in_group(group_name)
		for node_variant in nodes:
			var node := _combat_node3d_from_variant(node_variant)
			if node == null:
				continue
			var instance_id := node.get_instance_id()
			if seen.has(instance_id):
				continue
			seen[instance_id] = true
			if _is_valid_combat_target(node):
				out.append(node)
	return out


func _is_valid_combat_target(target: Node3D) -> bool:
	if target == aircraft:
		return false
	if target.is_in_group("aircraft") or target.is_in_group("ai_aircraft") or target.is_in_group("carrier"):
		return false
	if _combat_variant_truthy(target.get("is_destroyed")):
		return false
	if _flat_distance(aircraft.global_position, target.global_position) > maxf(combat_target_scan_range_m, 100.0):
		return false
	var my_team := 1
	if aircraft.has_method("get_team"):
		my_team = int(aircraft.call("get_team"))
	if target.has_method("get_team"):
		var target_team: int = int(target.call("get_team"))
		if target_team == my_team:
			return false
	return true


func _get_combat_weapon_options() -> Array:
	var rockets: Array = []
	var guns: Array = []
	var bombs: Array = []
	_collect_combat_hardpoint_weapons(aircraft, rockets, guns, bombs)

	var options: Array = []
	if not rockets.is_empty():
		options.append({"kind": COMBAT_WEAPON_ROCKET, "hardpoints": rockets})
	if not guns.is_empty():
		var gun_option: Dictionary = {"kind": COMBAT_WEAPON_GUN, "hardpoints": guns}
		if combat_alternate_hardpoint_guns_enabled and not rockets.is_empty() and _combat_prefer_hardpoint_guns_next:
			gun_option["score_bias"] = maxf(combat_preferred_gun_score_bias, 0.0)
		options.append(gun_option)
	if combat_allow_bombs and not bombs.is_empty():
		options.append({"kind": COMBAT_WEAPON_BOMB, "hardpoints": bombs})
	return options


func _update_combat_hardpoint_weapon_preference_after_plan(weapon_kind: String, weapon: Dictionary) -> void:
	if not combat_alternate_hardpoint_guns_enabled:
		return
	if _get_combat_hardpoints_from_weapon(weapon, false).is_empty():
		return
	match weapon_kind:
		COMBAT_WEAPON_GUN:
			_combat_prefer_hardpoint_guns_next = false
		COMBAT_WEAPON_ROCKET:
			_combat_prefer_hardpoint_guns_next = true


func _describe_combat_weapon_options(weapon_options: Array) -> String:
	if weapon_options.is_empty():
		return "none"
	var parts := PackedStringArray()
	for option_variant in weapon_options:
		if not (option_variant is Dictionary):
			continue
		var option: Dictionary = option_variant as Dictionary
		var kind := String(option.get("kind", "unknown"))
		var hardpoints_variant: Variant = option.get("hardpoints", [])
		var hardpoint_count := 0
		if hardpoints_variant is Array:
			hardpoint_count = (hardpoints_variant as Array).size()
		var turrets_variant: Variant = option.get("turrets", [])
		var turret_count := 0
		if turrets_variant is Array:
			turret_count = (turrets_variant as Array).size()
		var score_text := ""
		if option.has("score_bias"):
			score_text = "+bias%.1f" % float(option.get("score_bias", 0.0))
		if turret_count > 0:
			parts.append("%s:%dhp/%dturret%s" % [kind, hardpoint_count, turret_count, score_text])
		else:
			parts.append("%s:%dhp%s" % [kind, hardpoint_count, score_text])
	return ",".join(parts)


func _describe_nearest_combat_target(targets: Array) -> String:
	if targets.is_empty() or not is_instance_valid(aircraft):
		return "none"
	var nearest_name := "none"
	var nearest_dist := INF
	for target_variant in targets:
		var target := _combat_node3d_from_variant(target_variant)
		if target == null:
			continue
		var dist := _flat_distance(aircraft.global_position, target.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_name = String(target.name)
	if nearest_dist >= INF:
		return "none"
	return "%s@%.0fm" % [nearest_name, nearest_dist]


func _sync_combat_control_weapon_selection(weapon_kind: String, weapon: Dictionary) -> void:
	if not is_instance_valid(aircraft):
		return
	var control_weapons: ControlWeapons = aircraft.find_child("ControlWeapons", true, false) as ControlWeapons
	if control_weapons == null:
		return
	if control_weapons.has_method("categorize_weapons"):
		control_weapons.categorize_weapons()
	var selected_type: String = _get_control_weapon_type_for_combat(weapon_kind, weapon, control_weapons)
	if selected_type.is_empty():
		return
	var selected_index: int = control_weapons.weapon_types.find(selected_type)
	if selected_index == -1:
		return
	if control_weapons.selected_weapon_type == selected_type and control_weapons.selected_weapon_type_index == selected_index:
		return
	control_weapons.selected_weapon_type_index = selected_index
	control_weapons.selected_weapon_type = selected_type
	_log_combat_debug("weapon_select", "kind=%s selected=%s" % [weapon_kind, selected_type], true)


func _get_control_weapon_type_for_combat(weapon_kind: String, weapon: Dictionary, control_weapons: ControlWeapons) -> String:
	var hardpoints_variant: Variant = weapon.get("hardpoints", [])
	if hardpoints_variant is Array:
		for hp_variant in hardpoints_variant:
			var hp: Hardpoint = _combat_hardpoint_from_variant(hp_variant)
			if hp == null or hp.weapon_instance == null or not is_instance_valid(hp.weapon_instance):
				continue
			if _classify_combat_weapon(hp.weapon_instance) == weapon_kind:
				return _get_control_weapon_effective_type(hp.weapon_instance)
	var fallback_types: PackedStringArray = _get_control_weapon_fallback_types(weapon_kind)
	for fallback_type in fallback_types:
		if control_weapons.weapon_types.has(fallback_type):
			return fallback_type
	return ""


func _get_control_weapon_effective_type(weapon: Weapon) -> String:
	if weapon == null or not is_instance_valid(weapon):
		return ""
	if not weapon.weapon_category.is_empty():
		return weapon.weapon_category
	return weapon.weapon_name


func _get_control_weapon_fallback_types(weapon_kind: String) -> PackedStringArray:
	match weapon_kind:
		COMBAT_WEAPON_ROCKET:
			return PackedStringArray(["Rocket Pod"])
		COMBAT_WEAPON_GUN:
			return PackedStringArray(["Guns", "Autocannon", "25 mm Autocannon", "30 mm Autocannon", "25 mm Cannon", "30 mm Cannon", "10 mm Machine Gun", "15 mm Machine Gun"])
		COMBAT_WEAPON_BOMB:
			return PackedStringArray(["Bomb"])
	return PackedStringArray()


func _collect_combat_hardpoint_weapons(node: Node, rockets: Array, guns: Array, bombs: Array) -> void:
	if node is Hardpoint:
		var hp := node as Hardpoint
		if hp.weapon_instance != null and is_instance_valid(hp.weapon_instance) and hp.weapon_instance.can_fire():
			match _classify_combat_weapon(hp.weapon_instance):
				COMBAT_WEAPON_ROCKET:
					rockets.append(hp)
				COMBAT_WEAPON_GUN:
					guns.append(hp)
				COMBAT_WEAPON_BOMB:
					bombs.append(hp)
	for child in node.get_children():
		_collect_combat_hardpoint_weapons(child, rockets, guns, bombs)


func _classify_combat_weapon(weapon: Weapon) -> String:
	if weapon == null:
		return ""
	var parts := PackedStringArray()
	parts.append(String(weapon.weapon_name).to_lower())
	parts.append(String(weapon.weapon_category).to_lower())
	var profile := weapon.get("gun_profile") as Object
	if profile != null and is_instance_valid(profile):
		var profile_name = profile.get("weapon_name")
		if profile_name != null:
			parts.append(str(profile_name).to_lower())
	var text := " ".join(parts)
	if "rocket" in text:
		return COMBAT_WEAPON_ROCKET
	if "bomb" in text:
		return COMBAT_WEAPON_BOMB
	if "gun" in text or "cannon" in text or "autocannon" in text or "machine" in text:
		return COMBAT_WEAPON_GUN
	return ""


func _get_combat_turret_controllers() -> Array:
	var out: Array = []
	_collect_combat_turret_controllers(aircraft, out)
	return out


func _collect_combat_turret_controllers(node: Node, out: Array) -> void:
	if node is TurretController:
		var turret_controller := node as TurretController
		if turret_controller.weapon_instance != null or turret_controller.weapon_scene != null:
			out.append(turret_controller)
	for child in node.get_children():
		_collect_combat_turret_controllers(child, out)


func _try_fire_combat_weapon(target: Node3D) -> void:
	if _combat_plan.is_empty() or target == null or not is_instance_valid(target):
		return
	var weapon_variant: Variant = _combat_plan.get("weapon", {})
	if not (weapon_variant is Dictionary):
		return
	var weapon: Dictionary = weapon_variant as Dictionary
	var weapon_kind := String(_combat_plan.get("weapon_kind", ""))
	if weapon_kind == COMBAT_WEAPON_GUN:
		_focus_combat_turrets(target)

	var aim_solution := _get_combat_aim_solution(target)
	var target_pos := target.global_position + Vector3.UP * 1.4
	var aim_dir := Vector3.ZERO
	if not aim_solution.is_empty():
		var aim_point_variant: Variant = aim_solution.get("aim_point", target_pos)
		if aim_point_variant is Vector3:
			target_pos = aim_point_variant
		var aim_dir_variant: Variant = aim_solution.get("desired_dir", Vector3.ZERO)
		if aim_dir_variant is Vector3:
			aim_dir = aim_dir_variant
	var actual_target_pos := target.global_position + Vector3.UP * 1.4
	var to_actual_target := actual_target_pos - aircraft.global_position
	var dist := to_actual_target.length()
	var fire_range := float(_combat_plan.get("fire_range_m", 0.0))
	_request_combat_aim_takeover(weapon_kind, dist, fire_range)
	if dist > fire_range or dist <= 1.0:
		_record_combat_attack_run_state("range", "dist=%.1f limit=%.1f" % [dist, fire_range], dist)
		_log_combat_debug("hold_fire", "range dist=%.0f limit=%.0f" % [dist, fire_range])
		return
	if aim_dir.length_squared() < 0.001:
		aim_dir = (target_pos - aircraft.global_position).normalized()
	var fire_cone_cos := _get_combat_fire_alignment_cos(weapon_kind, float(_combat_plan.get("fire_cone_cos", 0.98)))
	var aim_dot := _get_best_combat_weapon_alignment_dot(weapon, aim_dir)
	var rocket_fallback_ready: bool = false
	if weapon_kind == COMBAT_WEAPON_ROCKET:
		rocket_fallback_ready = _is_combat_rocket_fallback_fire_ready(aim_solution, aim_dot)
	if aim_dot < fire_cone_cos and not rocket_fallback_ready:
		_record_combat_attack_run_state("aim_alignment", "dot=%.3f need=%.3f" % [aim_dot, fire_cone_cos], dist, aim_solution, aim_dot)
		_log_combat_debug("hold_fire", "aim dot=%.3f need=%.3f yaw=%.1f pitch=%.1f" % [
			aim_dot,
			fire_cone_cos,
			rad_to_deg(float(aim_solution.get("yaw_error", 0.0))),
			rad_to_deg(float(aim_solution.get("pitch_error", 0.0))),
		])
		return
	if not rocket_fallback_ready and not _is_combat_aim_settled_for_fire(weapon_kind, aim_solution, aim_dot, fire_cone_cos):
		_record_combat_attack_run_state("aim_settle", "settled=%.2f dot=%.3f" % [_combat_aim_settle_s, aim_dot], dist, aim_solution, aim_dot)
		return
	if weapon_kind == COMBAT_WEAPON_ROCKET:
		if not _is_combat_rocket_ccip_ready_for_fire(target):
			var ccip_solution: Dictionary = _get_combat_rocket_ccip_solution(target)
			var ccip_miss_m: float = _get_combat_rocket_ccip_miss_m(target, ccip_solution)
			_record_combat_attack_run_state("ccip", "miss=%.1f tol=%.1f" % [ccip_miss_m, combat_rocket_ccip_fire_tolerance_m], dist, aim_solution, aim_dot, ccip_miss_m)
			return
		_try_fire_combat_rocket_salvo(weapon, target, dist, rocket_fallback_ready, aim_solution, aim_dot)
		return

	var fired: bool = false
	for hp_variant in weapon.get("hardpoints", []):
		var hp := _combat_hardpoint_from_variant(hp_variant)
		if hp == null or hp.weapon_instance == null:
			continue
		if hp.fire():
			fired = true
			_queue_combat_shot_report(weapon_kind, hp, target, dist, maxf(combat_gun_shot_assess_time_s, 0.05), aim_solution, aim_dot)
	if fired:
		_release_combat_aim_takeover("fired", true)
		_log_combat_debug("fire", "target=%s weapon=%s dist=%.0f" % [target.name, weapon_kind, dist], true)
	else:
		_record_combat_attack_run_state("weapon_fire_rejected", "no ready hardpoint fired", dist, aim_solution, aim_dot)


func _focus_combat_turrets(target: Node3D) -> void:
	var weapon_variant: Variant = _combat_plan.get("weapon", {})
	if not (weapon_variant is Dictionary):
		return
	var weapon: Dictionary = weapon_variant as Dictionary
	for turret_variant in weapon.get("turrets", []):
		var turret_controller := _combat_turret_controller_from_variant(turret_variant)
		if turret_controller == null:
			continue
		turret_controller.current_target = target
		var turret_node := turret_controller.get("turret") as Object
		if turret_node != null and is_instance_valid(turret_node) and turret_node.has_method("set_target"):
			turret_node.call("set_target", target)


func _clear_combat_turret_targets() -> void:
	var weapon_variant: Variant = _combat_plan.get("weapon", {})
	if not (weapon_variant is Dictionary):
		return
	var weapon: Dictionary = weapon_variant as Dictionary
	for turret_variant in weapon.get("turrets", []):
		var turret_controller := _combat_turret_controller_from_variant(turret_variant)
		if turret_controller == null:
			continue
		if turret_controller.current_target != null:
			turret_controller.current_target = null
		var turret_node := turret_controller.get("turret") as Object
		if turret_node != null and is_instance_valid(turret_node) and turret_node.has_method("set_target"):
			turret_node.call("set_target", null)


func _reset_combat_report_for_run_once() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var root: Window = tree.root
	if root == null:
		return
	if bool(root.get_meta(COMBAT_REPORT_RESET_META, false)):
		return
	root.set_meta(COMBAT_REPORT_RESET_META, true)
	if not combat_report_enabled:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("HELI COMBAT REPORT START t=%.2f ticks=%d" % [_elapsed_s(), Time.get_ticks_msec()])
	_overwrite_lines_to_log(combat_report_path, lines, "helicopter combat report")
	if combat_report_project_mirror_enabled:
		_overwrite_lines_to_log(combat_report_project_mirror_path, lines, "project helicopter combat report")


func _queue_combat_shot_report(
		weapon_kind: String,
		hardpoint: Hardpoint,
		target: Node3D,
		dist: float,
		assess_delay_s: float,
		aim_solution: Dictionary,
		aim_dot: float,
		extra: Dictionary = {}
) -> void:
	if not combat_report_enabled:
		return
	var target_state: Dictionary = _capture_combat_target_state(target)
	var shot_id: int = _combat_next_shot_report_id
	_combat_next_shot_report_id += 1
	if _combat_attack_run_active:
		_combat_attack_run_shots += 1
	var entry: Dictionary = {
		"id": shot_id,
		"weapon": weapon_kind,
		"hardpoint": String(hardpoint.name) if hardpoint != null and is_instance_valid(hardpoint) else "unknown",
		"target": target,
		"target_name": String(target.name) if target != null and is_instance_valid(target) else "unknown",
		"target_id": target.get_instance_id() if target != null and is_instance_valid(target) else 0,
		"fire_time_s": _elapsed_s(),
		"assess_at_s": _elapsed_s() + maxf(assess_delay_s, 0.0),
		"dist_m": dist,
		"aim_dot": aim_dot,
		"yaw_error_deg": rad_to_deg(float(aim_solution.get("yaw_error", NAN))),
		"pitch_error_deg": rad_to_deg(float(aim_solution.get("pitch_error", NAN))),
		"before": target_state,
		"extra": extra,
	}
	_combat_pending_shot_reports.append(entry)
	_write_combat_shot_report("SHOT", entry, {})


func _update_combat_shot_reports() -> void:
	if _combat_pending_shot_reports.is_empty():
		return
	var now_s: float = _elapsed_s()
	var remaining: Array[Dictionary] = []
	for entry in _combat_pending_shot_reports:
		if now_s >= float(entry.get("assess_at_s", 0.0)):
			_finalize_combat_shot_report(entry)
		else:
			remaining.append(entry)
	_combat_pending_shot_reports = remaining


func _finalize_combat_shot_report(entry: Dictionary) -> void:
	var target: Node3D = null
	var target_variant: Variant = entry.get("target", null)
	if target_variant != null and typeof(target_variant) == TYPE_OBJECT and is_instance_valid(target_variant) and target_variant is Node3D:
		target = target_variant as Node3D
	var before_variant: Variant = entry.get("before", {})
	var before_state: Dictionary = {}
	if before_variant is Dictionary:
		before_state = before_variant as Dictionary
	var after_state: Dictionary = _capture_combat_target_state(target)
	var before_health: float = float(before_state.get("health", NAN))
	var after_health: float = float(after_state.get("health", NAN))
	var health_delta: float = 0.0
	if not is_nan(before_health) and not is_nan(after_health):
		health_delta = maxf(before_health - after_health, 0.0)
	var before_destroyed: bool = _combat_variant_truthy(before_state.get("destroyed", false))
	var after_destroyed: bool = _combat_variant_truthy(after_state.get("destroyed", false))
	var after_valid: bool = _combat_variant_truthy(after_state.get("valid", false))
	var damaged: bool = health_delta > 0.05 or (not before_destroyed and after_destroyed)
	if not after_valid and _combat_variant_truthy(before_state.get("valid", false)):
		damaged = true
		after_destroyed = true
	var result: Dictionary = {
		"after": after_state,
		"health_delta": health_delta,
		"damaged": damaged,
		"destroyed": after_destroyed,
	}
	_write_combat_shot_report("RESULT", entry, result)


func _capture_combat_target_state(target: Node) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {
			"valid": false,
			"health": NAN,
			"max_health": NAN,
			"destroyed": false,
		}
	var health: float = _combat_float_property(target, "current_health", NAN)
	var max_health: float = _combat_float_property(target, "max_health", NAN)
	var destroyed: bool = _combat_variant_truthy(target.get("is_destroyed")) or _combat_variant_truthy(target.get("is_dying"))
	if not is_nan(health) and health <= 0.0:
		destroyed = true
	return {
		"valid": true,
		"health": health,
		"max_health": max_health,
		"destroyed": destroyed,
	}


func _combat_float_property(node: Object, property_name: String, fallback: float = NAN) -> float:
	if node == null or not is_instance_valid(node):
		return fallback
	var value: Variant = node.get(property_name)
	if value is int or value is float:
		return float(value)
	return fallback


func _write_combat_shot_report(event_name: String, entry: Dictionary, result: Dictionary) -> void:
	if not combat_report_enabled:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append(_format_combat_shot_report_line(event_name, entry, result))
	_append_lines_to_log(combat_report_path, lines, "helicopter combat report")
	if combat_report_project_mirror_enabled:
		_append_lines_to_log(combat_report_project_mirror_path, lines, "project helicopter combat report")


func _format_combat_shot_report_line(event_name: String, entry: Dictionary, result: Dictionary) -> String:
	var before_variant: Variant = entry.get("before", {})
	var before_state: Dictionary = {}
	if before_variant is Dictionary:
		before_state = before_variant as Dictionary
	var after_state: Dictionary = {}
	if result.has("after"):
		var after_variant: Variant = result.get("after", {})
		if after_variant is Dictionary:
			after_state = after_variant as Dictionary
	var extra_variant: Variant = entry.get("extra", {})
	var extra: Dictionary = {}
	if extra_variant is Dictionary:
		extra = extra_variant as Dictionary
	var before_health: float = float(before_state.get("health", NAN))
	var after_health: float = float(after_state.get("health", NAN))
	var health_delta: float = float(result.get("health_delta", 0.0))
	var craft_name: String = String(aircraft.name) if is_instance_valid(aircraft) else "unknown"
	var extra_text: String = _format_combat_report_dictionary(extra)
	return "t=%.2f event=%s shot_id=%d craft=%s type=%s weapon=%s hardpoint=%s target=%s target_id=%d dist=%.1f aim_dot=%.3f yaw=%.2f pitch=%.2f before_hp=%s after_hp=%s damage=%.1f damaged=%s destroyed=%s phase=%s extra=\"%s\"" % [
		_elapsed_s(),
		event_name,
		int(entry.get("id", 0)),
		craft_name,
		_get_aircraft_type_label(),
		str(entry.get("weapon", "unknown")),
		str(entry.get("hardpoint", "unknown")),
		str(entry.get("target_name", "unknown")),
		int(entry.get("target_id", 0)),
		float(entry.get("dist_m", NAN)),
		float(entry.get("aim_dot", NAN)),
		float(entry.get("yaw_error_deg", NAN)),
		float(entry.get("pitch_error_deg", NAN)),
		_format_combat_report_float(before_health),
		_format_combat_report_float(after_health),
		health_delta,
		str(_combat_variant_truthy(result.get("damaged", false))),
		str(_combat_variant_truthy(result.get("destroyed", false))),
		_combat_phase if not _combat_phase.is_empty() else "none",
		extra_text.replace("\"", "'"),
	]


func _format_combat_report_dictionary(data: Dictionary) -> String:
	if data.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for key in data.keys():
		var value: Variant = data[key]
		if value is float:
			parts.append("%s=%s" % [str(key), _format_combat_report_float(float(value))])
		else:
			parts.append("%s=%s" % [str(key), str(value)])
	return " ".join(parts)


func _format_combat_report_float(value: float) -> String:
	if is_nan(value):
		return "?"
	if absf(value) >= INF * 0.5:
		return "?"
	return "%.1f" % value


func _log_combat_debug(event_name: String, details: String = "", force: bool = false) -> void:
	var now: float = _elapsed_s()
	if not force and now < _combat_debug_log_s:
		return
	_combat_debug_log_s = now + 1.0
	var craft_name: String = "?"
	if is_instance_valid(aircraft):
		craft_name = String(aircraft.name)
	var line: String = "[HELI_COMBAT] event=%s craft=%s state=%s mission=%s combat_phase=%s" % [
		event_name,
		craft_name,
		_state_name(),
		_mission_name(),
		_combat_phase if not _combat_phase.is_empty() else "none",
	]
	if not details.is_empty():
		line += " " + details
	if combat_report_debug_events_enabled:
		_write_combat_report_event(event_name, details, line)
	if combat_debug_enabled:
		_debug_output(line)


func _write_combat_report_event(event_name: String, details: String, debug_line: String) -> void:
	if not combat_report_enabled:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append(_format_combat_report_event_line(event_name, details, debug_line))
	_append_lines_to_log(combat_report_path, lines, "helicopter combat report")
	if combat_report_project_mirror_enabled:
		_append_lines_to_log(combat_report_project_mirror_path, lines, "project helicopter combat report")


func _write_combat_report_plan_start(target: Node3D, weapon_kind: String) -> void:
	if not combat_report_enabled:
		return
	var craft_name: String = String(aircraft.name) if is_instance_valid(aircraft) else "unknown"
	var target_name: String = String(target.name) if target != null and is_instance_valid(target) else "none"
	var target_pos_text: String = "?"
	if target != null and is_instance_valid(target):
		target_pos_text = str(target.global_position.snapped(Vector3.ONE * 0.1))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=" .repeat(96))
	lines.append("COMBAT PLAN START t=%.2f craft=%s type=%s weapon=%s target=%s target_pos=%s state=%s mission=%s" % [
		_elapsed_s(),
		craft_name,
		_get_aircraft_type_label(),
		weapon_kind,
		target_name,
		target_pos_text,
		_state_name(),
		_mission_name(),
	])
	lines.append("  ingress=%s fire_start=%s fire_end=%s egress=%s route_ready=%s route_task=%d" % [
		_format_combat_plan_position("ingress"),
		_format_combat_plan_position("fire_start"),
		_format_combat_plan_position("fire_end"),
		_format_combat_plan_position("egress"),
		str(_combat_route_ready),
		_combat_route_task_id,
	])
	_append_lines_to_log(combat_report_path, lines, "helicopter combat report")
	if combat_report_project_mirror_enabled:
		_append_lines_to_log(combat_report_project_mirror_path, lines, "project helicopter combat report")


func _format_combat_plan_position(key: String) -> String:
	var pos: Vector3 = _combat_plan_position(key)
	if pos == Vector3.INF:
		return "?"
	return str(pos.snapped(Vector3.ONE * 0.1))


func _format_combat_report_event_line(event_name: String, details: String, debug_line: String) -> String:
	var craft_name: String = "unknown"
	var type_label: String = "unknown"
	var pos_text: String = "?"
	var vel_text: String = "?"
	var speed: float = NAN
	if is_instance_valid(aircraft):
		craft_name = String(aircraft.name)
		type_label = _get_aircraft_type_label()
		pos_text = str(aircraft.global_position.snapped(Vector3.ONE * 0.1))
		vel_text = str(aircraft.linear_velocity.snapped(Vector3.ONE * 0.1))
		speed = aircraft.linear_velocity.length()
	var target_name: String = "none"
	var target_dist: float = NAN
	var target: Node3D = _combat_plan_target()
	if target != null and is_instance_valid(target) and is_instance_valid(aircraft):
		target_name = String(target.name)
		target_dist = aircraft.global_position.distance_to(target.global_position)
	var weapon_kind: String = String(_combat_plan.get("weapon_kind", "none"))
	var route_text: String = "none"
	if _combat_route_ready:
		route_text = "%d/%d" % [_combat_route_index, _combat_route_points.size()]
	elif _combat_route_task_id != -1:
		route_text = "building"
	var takeover_text: String = "on" if _combat_aim_takeover_active else "off"
	return "t=%.2f craft=%s type=%s event=%s state=%s mission=%s phase=%s weapon=%s target=%s target_dist=%.1f route=%s takeover=%s pos=%s vel=%s speed=%.1f details=\"%s\" raw=\"%s\"" % [
		_elapsed_s(),
		craft_name,
		type_label,
		event_name,
		_state_name(),
		_mission_name(),
		_combat_phase if not _combat_phase.is_empty() else "none",
		weapon_kind,
		target_name,
		target_dist,
		route_text,
		takeover_text,
		pos_text,
		vel_text,
		speed,
		details.replace("\"", "'"),
		debug_line.replace("\"", "'"),
	]


func _combat_variant_truthy(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return float(value) != 0.0
	if value is String:
		var text := String(value).strip_edges().to_lower()
		return text == "true" or text == "1" or text == "yes" or text == "on"
	return value != null


func _combat_node3d_from_variant(value: Variant) -> Node3D:
	if value == null or typeof(value) != TYPE_OBJECT:
		return null
	if not is_instance_valid(value):
		return null
	if not (value is Node3D):
		return null
	return value as Node3D


func _combat_hardpoint_from_variant(value: Variant) -> Hardpoint:
	if value == null or typeof(value) != TYPE_OBJECT:
		return null
	if not is_instance_valid(value):
		return null
	if not (value is Hardpoint):
		return null
	return value as Hardpoint


func _combat_turret_controller_from_variant(value: Variant) -> TurretController:
	if value == null or typeof(value) != TYPE_OBJECT:
		return null
	if not is_instance_valid(value):
		return null
	if not (value is TurretController):
		return null
	return value as TurretController


func _set_carrier_landing_final_active(active: bool) -> void:
	if not is_instance_valid(aircraft):
		return
	if active:
		aircraft.set_meta("carrier_landing_final_active", true)
	elif aircraft.has_meta("carrier_landing_final_active"):
		aircraft.remove_meta("carrier_landing_final_active")


func _get_carrier_landing_abort_reason(
		pos: Vector3,
		carrier: Node3D,
		carrier_fwd: Vector3,
		carrier_right: Vector3,
		_approach_world: Vector3,
		landing_world: Vector3
) -> String:
	if _carrier_approach_phase != CarrierApproachPhase.FINAL \
			and _carrier_approach_phase != CarrierApproachPhase.DESCEND:
		return ""
	if carrier == null:
		return ""
	var deck_y := _get_carrier_deck_y(carrier)
	if pos.y < deck_y - maxf(carrier_landing_abort_below_deck_m, 0.0):
		return "below_deck"
	var to_landing := landing_world - pos
	to_landing.y = 0.0
	var flat_dist := to_landing.length()
	var past_forward := -to_landing.dot(carrier_fwd)
	var lateral_error := absf(to_landing.dot(carrier_right))
	if past_forward > maxf(carrier_landing_abort_forward_m, 0.0):
		return "too_far_forward"
	if lateral_error > maxf(carrier_landing_abort_lateral_m, 0.0):
		return "too_far_lateral"
	if flat_dist > maxf(carrier_landing_abort_distance_m, 1.0):
		return "too_far_from_landing_point"
	return ""


func _abort_carrier_landing_attempt(reason: String, approach_world: Vector3) -> void:
	_debug_event("carrier_landing_abort", "reason=%s cphase=%s pos=%s approach=%s" % [
		reason,
		_carrier_approach_phase_name(),
		str(aircraft.global_position.snapped(Vector3.ONE)) if is_instance_valid(aircraft) else "?",
		str(approach_world.snapped(Vector3.ONE)),
	])
	_release_carrier_landing_clearance_from_deck()
	_carrier_approach_phase = CarrierApproachPhase.TO_APPROACH_POINT
	_carrier_final_timer_s = 0.0
	_carrier_touchdown_settle_timer_s = 0.0
	_carrier_landing_clearance_wait_logged = false
	_carrier_approach_clearance_request_s = 0.0
	_set_carrier_landing_final_active(false)
	if is_instance_valid(aircraft):
		_desired_altitude_m = maxf(approach_world.y, aircraft.global_position.y)
		_nav_waypoint = Vector3(approach_world.x, _desired_altitude_m, approach_world.z)


# Returns true while it is handling the approach and has set _pitch_cmd/_roll_cmd/_yaw_cmd
# and called _apply_collective. Returns false if markers are missing and caller should fall back.
func _run_scripted_carrier_approach(delta: float) -> bool:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return false
	var approach_world := _get_carrier_approach_point_world_pos()
	var approach2_world := _get_carrier_marker_world_pos(carrier_approach_point_2_name)
	var landing_world := _get_carrier_marker_world_pos(carrier_landing_point_name)
	if approach_world == Vector3.INF or approach2_world == Vector3.INF or landing_world == Vector3.INF:
		return false

	var pos := aircraft.global_position
	var carrier_vel := _get_carrier_velocity_world()
	var carrier_speed := carrier_vel.length()
	var carrier_fwd := carrier_vel.normalized() if carrier_speed > 0.5 else -carrier.global_transform.basis.z
	carrier_fwd.y = 0.0
	carrier_fwd = carrier_fwd.normalized() if carrier_fwd.length_squared() > 0.001 else Vector3.FORWARD
	var carrier_right := carrier.global_transform.basis.x
	carrier_right.y = 0.0
	carrier_right = carrier_right.normalized() if carrier_right.length_squared() > 0.001 else Vector3.RIGHT

	var abort_reason := _get_carrier_landing_abort_reason(pos, carrier, carrier_fwd, carrier_right, approach_world, landing_world)
	if abort_reason != "":
		_abort_carrier_landing_attempt(abort_reason, approach_world)

	# Phase transitions
	match _carrier_approach_phase:
		CarrierApproachPhase.NONE, CarrierApproachPhase.TO_APPROACH_POINT:
			_carrier_approach_phase = CarrierApproachPhase.TO_APPROACH_POINT
			var hold_point := _get_carrier_queue_hold_position(approach_world, carrier_fwd)
			var dist_to_gate := _flat_distance(pos, hold_point)
			# If too far from the gate and receding, drop back to transit so the
			# helicopter can chase it at cruise speed instead of crawling at hover speed.
			if dist_to_gate > maxf(carrier_approach_gate_radius_m, 5.0) * 3.0:
				var to_hold := hold_point - pos
				to_hold.y = 0.0
				var closing := (aircraft.linear_velocity - carrier_vel).dot(to_hold.normalized() if to_hold.length_squared() > 0.1 else carrier_fwd)
				if closing < 2.0:
					_carrier_approach_phase = CarrierApproachPhase.NONE
					_landing_on_carrier = false
					change_state(State.LOW_LEVEL_TRANSIT)
					_debug_event("carrier_approach", "dropped back to transit: dist=%.0f closing=%.1f" % [dist_to_gate, closing])
					return true
			var has_landing_clearance := _has_carrier_landing_clearance_from_deck()
			var clearance_request_radius := maxf(
				carrier_approach_clearance_request_radius_m,
				carrier_approach_gate_radius_m
			)
			_carrier_approach_clearance_request_s = maxf(
				_carrier_approach_clearance_request_s - delta,
				0.0
			)
			if dist_to_gate > clearance_request_radius:
				_carrier_approach_clearance_request_s = 0.0
			if not has_landing_clearance \
					and dist_to_gate <= clearance_request_radius \
					and _carrier_approach_clearance_request_s <= 0.0:
				_carrier_approach_clearance_request_s = maxf(
					carrier_approach_clearance_request_interval_s,
					0.1
				)
				has_landing_clearance = _request_carrier_landing_clearance_from_deck()
				if not has_landing_clearance and not _carrier_landing_clearance_wait_logged:
					_debug_event("carrier_approach", "landing clearance queued; holding approach point")
					_carrier_landing_clearance_wait_logged = true
				elif has_landing_clearance:
					_carrier_landing_clearance_wait_logged = false
			var height_ok := absf(pos.y - hold_point.y) < maxf(carrier_approach_capture_height_m, 1.0)
			var relative_speed_limit := maxf(carrier_approach_capture_relative_speed_mps, 0.1)
			if has_landing_clearance:
				relative_speed_limit = maxf(relative_speed_limit, carrier_approach_cleared_relative_speed_mps)
			var relative_speed := (aircraft.linear_velocity - carrier_vel).length()
			var relative_speed_ok := relative_speed <= relative_speed_limit
			var forced_final_speed_limit := maxf(
				relative_speed_limit,
				carrier_approach_cleared_forced_final_relative_speed_mps
			)
			var forced_final_ok := has_landing_clearance \
					and relative_speed <= forced_final_speed_limit
			var forward := aircraft.global_transform.basis.z
			forward.y = 0.0
			forward = forward.normalized() if forward.length_squared() > 0.001 else carrier_fwd
			var heading_error_deg := rad_to_deg(absf(forward.signed_angle_to(carrier_fwd, Vector3.UP)))
			var heading_limit := maxf(carrier_approach_capture_heading_deg, 0.0)
			if has_landing_clearance:
				heading_limit = maxf(heading_limit, carrier_approach_cleared_heading_deg)
			var heading_ok := heading_error_deg <= heading_limit
			var capture_radius := maxf(carrier_approach_capture_radius_m, 5.0)
			if has_landing_clearance:
				capture_radius = maxf(capture_radius, carrier_approach_cleared_capture_radius_m)
			if dist_to_gate < capture_radius \
					and height_ok \
					and (relative_speed_ok or forced_final_ok) \
					and heading_ok:
				if has_landing_clearance:
					_carrier_landing_clearance_wait_logged = false
					# If already past the landing point, skip FINAL and go straight to DESCEND
					var to_landing_check: Vector3 = landing_world - pos
					to_landing_check.y = 0.0
					var already_past: bool = to_landing_check.dot(carrier_fwd) < 0.0 \
						and _flat_distance(pos, landing_world) < 60.0
					if already_past:
						_carrier_approach_phase = CarrierApproachPhase.DESCEND
						_debug_event("carrier_approach", "phase=DESCEND (skipped FINAL: already past landing point)")
					else:
						_carrier_approach_phase = CarrierApproachPhase.FINAL
						_carrier_final_timer_s = 0.0
					_debug_event("carrier_approach", "phase=FINAL gate_dist=%.1f rel_speed=%.1f/%.1f forced=%s heading=%.1f/%.1f clearance=%s" % [
						dist_to_gate,
						relative_speed,
						relative_speed_limit,
						str(not relative_speed_ok and forced_final_ok),
						heading_error_deg,
						heading_limit,
						str(has_landing_clearance),
					])
			else:
				_carrier_approach_wait_log_s -= delta
				if debug_enabled and _carrier_approach_wait_log_s <= 0.0 and dist_to_gate < maxf(carrier_approach_gate_radius_m, capture_radius):
					_carrier_approach_wait_log_s = maxf(carrier_approach_wait_log_interval_s, 0.25)
					_debug_event("carrier_approach_wait", "clearance=%s dist=%.1f/%.1f request_radius=%.1f height_ok=%s rel=%.1f/%.1f heading=%.1f/%.1f" % [
						str(has_landing_clearance),
						dist_to_gate,
						capture_radius,
						clearance_request_radius,
						str(height_ok),
						relative_speed,
						forced_final_speed_limit if has_landing_clearance else relative_speed_limit,
						heading_error_deg,
						heading_limit,
					])
		CarrierApproachPhase.FINAL:
			_carrier_final_timer_s += delta
			# Transition to DESCEND once hovering at AP2: close, at altitude, slow relative to carrier.
			var dist_to_ap2 := _flat_distance(pos, approach2_world)
			var relative_speed := (aircraft.linear_velocity - carrier_vel).length()
			var speed_ok := relative_speed <= maxf(carrier_landing_descend_relative_speed_mps, 0.1)
			var alt_ok := absf(pos.y - approach2_world.y) <= 8.0
			var close_enough := dist_to_ap2 <= 20.0
			if close_enough and speed_ok and alt_ok:
				_carrier_approach_phase = CarrierApproachPhase.DESCEND
				_carrier_final_timer_s = 0.0
				_debug_event("carrier_approach", "phase=DESCEND dist_ap2=%.1f rel_speed=%.1f/%.1f alt_err=%.1f" % [
					dist_to_ap2,
					relative_speed,
					carrier_landing_descend_relative_speed_mps,
					pos.y - approach2_world.y,
				])
			elif _carrier_final_timer_s > maxf(carrier_landing_final_timeout_s, 0.1):
				_abort_carrier_landing_attempt("final_timeout", approach_world)
		CarrierApproachPhase.DESCEND:
			_carrier_final_timer_s += delta
			var timed_out := _carrier_final_timer_s > maxf(carrier_landing_final_timeout_s, 0.1)
			if timed_out:
				_abort_carrier_landing_attempt("descent_timeout", approach_world)

	_set_carrier_landing_final_active(
		_carrier_approach_phase == CarrierApproachPhase.FINAL
				or _carrier_approach_phase == CarrierApproachPhase.DESCEND
	)

	# Per-phase flight control
	var target_altitude := approach_world.y  # approach point height = correct deck hover height
	var target_speed := carrier_speed
	var target_pos := approach_world

	match _carrier_approach_phase:
		CarrierApproachPhase.TO_APPROACH_POINT:
			var hold_pos := _get_carrier_queue_hold_position(approach_world, carrier_fwd)
			target_pos = hold_pos
			target_altitude = hold_pos.y
			target_speed = _get_carrier_approach_arrival_speed_limit(_get_current_leg_target_speed_mps(cruise_speed_mps))

		CarrierApproachPhase.FINAL:
			# Fly to AP2 (directly above landing point) at hover height, matching carrier speed.
			target_pos = approach2_world
			target_speed = carrier_speed
			target_altitude = approach2_world.y

		CarrierApproachPhase.DESCEND:
			# Straight down from AP2 to the deck; hold carrier speed horizontally.
			target_pos = landing_world
			target_speed = carrier_speed
			target_altitude = landing_world.y

	# Update destination so _try_finish_landing and other systems see the right point
	destination = landing_world
	_has_destination = true
	_desired_altitude_m = target_altitude

	# Per-phase landing debug: only FINAL and DESCEND, once per 3s
	if debug_enabled and _carrier_approach_phase != CarrierApproachPhase.TO_APPROACH_POINT:
		_carrier_approach_speed_log_s -= delta
		if _carrier_approach_speed_log_s <= 0.0:
			_carrier_approach_speed_log_s = maxf(carrier_approach_speed_log_interval_s * 1.5, 0.5)
			var abs_spd := aircraft.linear_velocity.length() if is_instance_valid(aircraft) else 0.0
			var rel_spd := (aircraft.linear_velocity - carrier_vel).length() if is_instance_valid(aircraft) else 0.0
			var alt_err := pos.y - target_altitude
			var dist_landing := _flat_distance(pos, landing_world)
			var dist_ap2 := _flat_distance(pos, approach2_world)
			var phase_str := ""
			match _carrier_approach_phase:
				CarrierApproachPhase.TO_APPROACH_POINT: phase_str = "GATE"
				CarrierApproachPhase.FINAL: phase_str = "FINAL"
				CarrierApproachPhase.DESCEND: phase_str = "DESCEND"
			_debug_event("land_debug", "phase=%s spd=%.1f rel=%.1f alt_err=%+.1f dist_land=%.0f dist_ap2=%.0f col=%.2f vs=%.1f" % [
				phase_str,
				abs_spd,
				rel_spd,
				alt_err,
				dist_landing,
				dist_ap2,
				_collective_cmd,
				aircraft.linear_velocity.y if is_instance_valid(aircraft) else 0.0,
			])

	var fly_target := Vector3(target_pos.x, target_altitude, target_pos.z)
	if _carrier_approach_phase == CarrierApproachPhase.TO_APPROACH_POINT:
		var hold_target := _get_carrier_queue_hold_position(approach_world, carrier_fwd)
		_fly_carrier_approach_gate(hold_target, carrier_fwd, carrier_right, carrier_vel, target_speed, delta)
	elif _carrier_approach_phase == CarrierApproachPhase.FINAL:
		_fly_carrier_final(approach2_world, approach_world, approach2_world.y, carrier_fwd, carrier_vel, delta)
	elif _carrier_approach_phase == CarrierApproachPhase.DESCEND:
		_fly_carrier_descent(landing_world, approach2_world, carrier_fwd, delta)
	else:
		_fly_toward(fly_target, target_speed, delta)
	return true


func _fly_carrier_final(
		landing_world: Vector3,
		approach_world: Vector3,
		target_altitude: float,
		carrier_fwd_fallback: Vector3,
		carrier_vel: Vector3,
		delta: float
) -> void:
	if not is_instance_valid(aircraft):
		return
	var pos := aircraft.global_position
	var world_vel := aircraft.linear_velocity

	var final_fwd := landing_world - approach_world
	final_fwd.y = 0.0
	if final_fwd.length_squared() > 0.001:
		final_fwd = final_fwd.normalized()
	else:
		final_fwd = carrier_fwd_fallback
		final_fwd.y = 0.0
		final_fwd = final_fwd.normalized() if final_fwd.length_squared() > 0.001 else Vector3.FORWARD
	var final_right := Vector3.UP.cross(final_fwd)
	final_right.y = 0.0
	final_right = final_right.normalized() if final_right.length_squared() > 0.001 else Vector3.RIGHT

	# Target world velocity = carrier velocity + small position correction toward AP2.
	var pos_err := landing_world - pos
	pos_err.y = 0.0
	var along_pos := pos_err.dot(final_fwd)
	var lat_pos := pos_err.dot(final_right)
	var speed_cap := maxf(carrier_final_speed_offset_mps, 0.0)
	var target_fwd_world := carrier_vel.dot(final_fwd) + clampf(
		along_pos * maxf(carrier_landing_position_speed_gain, 0.0), -speed_cap, speed_cap)
	var target_lat_world := carrier_vel.dot(final_right) + clampf(
		lat_pos * maxf(carrier_landing_position_speed_gain, 0.0), -speed_cap, speed_cap)

	var fwd_speed := world_vel.dot(final_fwd)
	var lat_speed := world_vel.dot(final_right)
	var vertical_speed := world_vel.y - carrier_vel.y
	var fwd_err := target_fwd_world - fwd_speed
	var lat_err := target_lat_world - lat_speed

	var pitch_cmd := clampf(-fwd_err * 0.18, -0.55, 0.55)
	var roll_cmd := clampf(lat_err * 0.18, -0.45, 0.45)

	var nose_fwd := aircraft.global_transform.basis.z
	nose_fwd.y = 0.0
	if nose_fwd.length_squared() > 0.001:
		nose_fwd = nose_fwd.normalized()
	var yaw_err := nose_fwd.signed_angle_to(final_fwd, Vector3.UP)
	var yaw_cmd := clampf(yaw_err * 0.55 - aircraft.angular_velocity.y * 0.45, -0.8, 0.8)

	_pitch_cmd = pitch_cmd
	_roll_cmd = roll_cmd
	_yaw_cmd = move_toward(_yaw_cmd, yaw_cmd, maxf(yaw_command_rate, 0.01) * delta)
	_set_helicopter_input(_pitch_cmd, _roll_cmd, _yaw_cmd)

	_speed_target_mps = carrier_vel.length()
	_debug_forward_error_mps = fwd_err
	_debug_lateral_error_mps = lat_err
	_debug_speed_pitch = pitch_cmd
	_debug_altitude_pitch = 0.0
	_debug_turn_roll = roll_cmd
	_debug_sharp_turn = 0.0
	_debug_target_yaw = yaw_cmd
	_debug_vertical_rate_error_mps = 0.0 - vertical_speed

	# Use a dedicated gentle altitude hold for the gate — avoids the big collective
	# swings from the full LANDING boost that cause 40m altitude oscillations.
	var gate_alt_error := target_altitude - aircraft.global_position.y
	var gate_desired_climb := clampf(gate_alt_error * altitude_to_climb_gain * 1.5, -max_descent_mps, max_climb_mps)
	var gate_climb_error := gate_desired_climb - vertical_speed
	var collective_target := _get_collective_trim() + gate_climb_error * collective_climb_gain * 1.5
	collective_target = clampf(collective_target, 0.4, 1.0)
	_debug_collective_target = collective_target
	_apply_collective(collective_target)


func _fly_carrier_descent(landing_world: Vector3, approach_world: Vector3, carrier_fwd_fallback: Vector3, delta: float) -> void:
	if not is_instance_valid(aircraft):
		return
	var pos := aircraft.global_position
	var control_vel := _get_control_velocity()
	var deck_y := landing_world.y
	var alt_error := deck_y - pos.y
	var height_above_deck := -alt_error

	var final_fwd := landing_world - approach_world
	final_fwd.y = 0.0
	if final_fwd.length_squared() > 0.001:
		final_fwd = final_fwd.normalized()
	else:
		final_fwd = carrier_fwd_fallback
		final_fwd.y = 0.0
		final_fwd = final_fwd.normalized() if final_fwd.length_squared() > 0.001 else Vector3.FORWARD
	var final_right := Vector3.UP.cross(final_fwd)
	final_right.y = 0.0
	final_right = final_right.normalized() if final_right.length_squared() > 0.001 else Vector3.RIGHT

	# Correct any XZ drift relative to the landing point; control_vel is carrier-relative.
	var pos_err := landing_world - pos
	pos_err.y = 0.0
	var along_pos := pos_err.dot(final_fwd)
	var lat_pos := pos_err.dot(final_right)
	var correction_cap := lerpf(
		maxf(carrier_landing_touchdown_correction_speed_mps, 0.0),
		maxf(carrier_landing_descent_correction_speed_mps, 0.0),
		clampf(height_above_deck / maxf(landing_flare_agl_m, 0.5), 0.0, 1.0)
	)
	var target_fwd_speed := clampf(along_pos * maxf(carrier_landing_position_speed_gain, 0.0), -correction_cap, correction_cap)
	var target_lat_speed := clampf(lat_pos * maxf(carrier_landing_position_speed_gain, 0.0), -correction_cap, correction_cap)

	var fwd_speed := control_vel.dot(final_fwd)
	var lat_speed := control_vel.dot(final_right)
	var fwd_err := target_fwd_speed - fwd_speed
	var lat_err := target_lat_speed - lat_speed

	# Scale down pitch authority near the deck.
	var deck_proximity_t := clampf(1.0 - height_above_deck / maxf(landing_flare_agl_m * 3.0, 1.0), 0.0, 1.0)
	var pitch_limit := lerpf(0.25, 0.08, deck_proximity_t)
	var pitch_cmd := clampf(-fwd_err * 0.06, -pitch_limit, pitch_limit)
	var roll_cmd := clampf(lat_err * 0.06 + lat_pos * 0.003, -0.3, 0.3)

	var nose_fwd := aircraft.global_transform.basis.z
	nose_fwd.y = 0.0
	if nose_fwd.length_squared() > 0.001:
		nose_fwd = nose_fwd.normalized()
	var yaw_err := nose_fwd.signed_angle_to(final_fwd, Vector3.UP)
	var yaw_cmd := clampf(yaw_err * 0.5 - aircraft.angular_velocity.y * 0.4, -0.6, 0.6)

	_pitch_cmd = move_toward(_pitch_cmd, pitch_cmd, maxf(cyclic_rate, 0.01) * delta)
	_roll_cmd = move_toward(_roll_cmd, roll_cmd, maxf(cyclic_rate, 0.01) * delta)
	_yaw_cmd = move_toward(_yaw_cmd, yaw_cmd, maxf(yaw_command_rate, 0.01) * delta)
	_set_helicopter_input(_pitch_cmd, _roll_cmd, _yaw_cmd)

	var descent_limit := _get_carrier_landing_descent_limit_mps(height_above_deck)
	var descent_gain := altitude_to_climb_gain * 2.4
	var desired_climb := clampf(alt_error * descent_gain, -descent_limit, 0.0)
	if height_above_deck > maxf(carrier_landing_touchdown_min_deck_agl_m, -0.25):
		desired_climb = minf(desired_climb, -descent_limit)
	if _get_carrier_surface_gear_count() > 0:
		desired_climb = -0.15
	var climb_error := desired_climb - control_vel.y
	var collective := _get_collective_trim() + climb_error * collective_climb_gain * 2.0
	if height_above_deck <= maxf(landing_flare_agl_m, 1.0):
		var sink_overspeed := maxf(-control_vel.y - descent_limit, 0.0)
		var soft_cap := maxf(
			carrier_landing_ground_effect_collective_cap,
			_get_collective_trim() + sink_overspeed * maxf(landing_descent_overspeed_collective_gain * 2.5, 0.0)
		)
		collective = minf(collective, soft_cap)
	collective = clampf(collective, 0.4, 1.0)
	_debug_collective_target = collective
	_apply_collective(collective)
	if debug_enabled and _debug_timer_s <= 0.0:
		_debug_event("descend", "h_above_deck=%+.1f desired_vs=%.2f limit=%.2f actual_vs=%.2f fwd_err=%.1f lat_err=%.1f lat_pos=%.1f col=%.2f->%.2f pitch=%.2f roll=%.2f" % [
			height_above_deck,
			desired_climb,
			descent_limit,
			control_vel.y,
			fwd_err,
			lat_err,
			lat_pos,
			_collective_cmd,
			collective,
			_pitch_cmd,
			_roll_cmd,
		])


func _get_carrier_landing_descent_limit_mps(height_above_deck: float) -> float:
	var upper_sink := maxf(carrier_landing_min_sink_mps, 0.05)
	var flare_sink := maxf(carrier_landing_touchdown_sink_mps, 0.05)
	var touchdown_sink := maxf(carrier_landing_soft_touchdown_sink_mps, 0.05)
	var flare_height := maxf(landing_flare_agl_m, 0.5)
	var final_slow_height := maxf(landing_final_slowdown_agl_m, 0.25)
	var h := maxf(height_above_deck, 0.0)
	if h >= flare_height:
		return upper_sink
	if h >= final_slow_height:
		var flare_t := (h - final_slow_height) / maxf(flare_height - final_slow_height, 0.1)
		return lerpf(flare_sink, upper_sink, clampf(flare_t, 0.0, 1.0))
	var touchdown_t := h / final_slow_height
	return lerpf(touchdown_sink, flare_sink, clampf(touchdown_t, 0.0, 1.0))


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
	if use_heightmap_pathfinding and _heightmap_path.is_empty() and _has_destination:
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
		if not _has_destination:
			return 0.0
		var climb_m: float = maxf(aircraft.global_position.y - _takeoff_start_altitude_m, 0.0)
		if climb_m < takeoff_vertical_hold_m:
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
		var carrier_rel_velocity: Vector3 = aircraft.linear_velocity - _get_deck_reference_velocity()
		var carrier_rel_speed: float = carrier_rel_velocity.length()
		var carrier_rel_vertical_speed: float = carrier_rel_velocity.y
		var deck_y := _get_landing_surface_y()
		var deck_agl := aircraft.global_position.y - deck_y if not is_nan(deck_y) else INF
		var touchdown_radius: float = minf(
			maxf(carrier_landing_touchdown_radius_m, 0.5),
			maxf(carrier_landing_descent_start_radius_m, 0.5)
		)
		var gear_landed := _all_landing_gear_on_carrier_deck()
		var on_deck := deck_agl >= carrier_landing_touchdown_min_deck_agl_m and deck_agl <= 6.0
		var close_to_deck := deck_agl >= carrier_landing_touchdown_min_deck_agl_m \
				and deck_agl <= maxf(carrier_landing_touchdown_max_deck_agl_m, 0.1)
		var any_gear_count := _get_carrier_surface_gear_count()
		var touchdown_contact := gear_landed \
				or (on_deck and any_gear_count >= 1) \
				or (flat_dist <= touchdown_radius \
					and carrier_rel_speed < maxf(carrier_landing_touchdown_relative_speed_mps, 0.1) \
					and close_to_deck)
		var gentle_vertical := absf(carrier_rel_vertical_speed) <= maxf(
			carrier_landing_touchdown_max_vertical_mps,
			carrier_landing_soft_touchdown_sink_mps
		)
		if touchdown_contact and gentle_vertical:
			_carrier_touchdown_settle_timer_s += _physics_delta
		else:
			_carrier_touchdown_settle_timer_s = 0.0
		is_landed = touchdown_contact \
				and gentle_vertical \
				and _carrier_touchdown_settle_timer_s >= maxf(carrier_landing_touchdown_settle_time_s, 0.0)
		if gear_landed:
			_debug_event("carrier_touchdown_gear", "gear=%d/%d flat=%.1f rel=%.2f vs=%.2f deck_agl=%.2f settled=%.2f" % [
				_get_carrier_surface_gear_count(),
				_get_landing_gear_count(),
				flat_dist,
				carrier_rel_speed,
				carrier_rel_vertical_speed,
				deck_agl,
				_carrier_touchdown_settle_timer_s,
			])
	else:
		_carrier_touchdown_settle_timer_s = 0.0
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
		var settled_hover_touchdown := _update_terrain_landing_settled_touchdown(
			close_to_lz,
			agl,
			aircraft.linear_velocity
		)
		is_landed = soft_touchdown or grounded_touchdown or settled_hover_touchdown
		if not is_landed:
			_debug_lz_landing_pending(
				flat_dist,
				agl,
				close_to_lz,
				soft_touchdown,
				grounded_touchdown
			)

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
	_carrier_final_timer_s = 0.0
	_carrier_approach_clearance_request_s = 0.0
	_stop_rotors_after_landing()
	match mission_phase:
		MissionPhase.OUTBOUND:
			mission_phase = MissionPhase.AT_LZ
			_idle_dwell_timer_s = lz_dwell_time_s
			_flight_landed_lz = true
			_record_heli_ui_stat("lz")
			_flight_landed_lz_s = _elapsed_s()
			_flight_lz_position = aircraft.global_position if is_instance_valid(aircraft) else Vector3.INF
			_record_milestone("Landed at LZ — pos=%s" % [str(aircraft.global_position.snapped(Vector3.ONE)) if is_instance_valid(aircraft) else "?"])
			_write_flight_summary_report("LZ LANDING")
		MissionPhase.RESCUE:
			# Stay in RESCUE phase so HeliSwingDoors can open; pilot's DownedPilot script
			# will call add_passenger() when it reaches us, which triggers INBOUND.
			_idle_dwell_timer_s = 60.0  # safety timeout: leave if no one boards within 60 s
			_record_milestone("Landed for rescue pickup")
		MissionPhase.INBOUND:
			mission_phase = MissionPhase.AT_CARRIER
			_idle_dwell_timer_s = carrier_dwell_time_s
			_record_heli_ui_stat("carrier")
			_record_milestone("Landed back at carrier")
			_write_flight_summary_report("CARRIER LANDING")
			_hold_landed_on_carrier()
			_notify_helicopter_landed_on_carrier_deck()
			_release_carrier_landing_clearance_from_deck()
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


func _get_landing_gear_modules() -> Array[Node]:
	var modules: Array[Node] = []
	if not is_instance_valid(aircraft):
		return modules
	if aircraft.has_method("find_modules_by_type"):
		var found_variant: Variant = aircraft.call("find_modules_by_type", "landing_gear")
		if found_variant is Array:
			for entry: Variant in found_variant:
				var module := _resolve_landing_gear_module(entry as Node)
				if is_instance_valid(module) and not modules.has(module):
					modules.append(module)
	if is_instance_valid(control_gear):
		var controlled_variant: Variant = control_gear.get("landing_gear_modules")
		if controlled_variant is Array:
			for entry: Variant in controlled_variant:
				var module := _resolve_landing_gear_module(entry as Node)
				if is_instance_valid(module) and not modules.has(module):
					modules.append(module)
	var direct := aircraft.get_node_or_null("LandingGear")
	var direct_module := _resolve_landing_gear_module(direct)
	if is_instance_valid(direct_module) and not modules.has(direct_module):
		modules.append(direct_module)
	return modules


func _resolve_landing_gear_module(node: Node) -> Node:
	if not is_instance_valid(node):
		return null
	if node.has_method("get_gear_count") or node.get("gear_compressions") is Array:
		return node
	for child in node.get_children():
		var module := _resolve_landing_gear_module(child)
		if is_instance_valid(module):
			return module
	return null


func _get_landing_gear_count() -> int:
	var count := 0
	for module: Node in _get_landing_gear_modules():
		if module.has_method("get_gear_count"):
			count += int(module.call("get_gear_count"))
			continue
		var shapes_variant: Variant = module.get("gear_collision_shapes")
		if shapes_variant is Array:
			count += (shapes_variant as Array).size()
	return count


func _get_carrier_surface_gear_count() -> int:
	var count := 0
	for module: Node in _get_landing_gear_modules():
		if module.has_method("get_carrier_surface_wheel_count"):
			count += int(module.call("get_carrier_surface_wheel_count"))
			continue
		var on_surface_variant: Variant = module.get("_wheel_on_carrier_surface")
		if on_surface_variant is Array:
			for value: Variant in on_surface_variant as Array:
				if bool(value):
					count += 1
	return count


func _all_landing_gear_on_carrier_deck() -> bool:
	var gear_count := _get_landing_gear_count()
	return gear_count > 0 and _get_carrier_surface_gear_count() >= gear_count


func _get_grounded_gear_count() -> int:
	var grounded_count: int = 0
	var threshold: float = maxf(terrain_landing_ground_contact_compression_m, 0.0)
	for module: Node in _get_landing_gear_modules():
		var compressions_variant: Variant = module.get("gear_compressions")
		if not (compressions_variant is Array):
			continue
		for value: Variant in compressions_variant as Array:
			if float(value) >= threshold:
				grounded_count += 1
	return grounded_count


func _update_terrain_landing_settled_touchdown(close_to_lz: bool, agl: float, velocity: Vector3) -> bool:
	if not close_to_lz:
		_terrain_landing_settled_timer_s = 0.0
		return false
	var speed := velocity.length()
	var settled := agl <= maxf(terrain_landing_settled_agl_m, 0.1) \
			and speed <= maxf(terrain_landing_settled_speed_mps, 0.0) \
			and absf(velocity.y) <= maxf(terrain_landing_settled_vertical_mps, 0.0)
	if not settled:
		_terrain_landing_settled_timer_s = 0.0
		return false

	_terrain_landing_settled_timer_s += _physics_delta
	if _terrain_landing_settled_timer_s < maxf(terrain_landing_settled_time_s, 0.0):
		return false

	_debug_event("lz_landing_settled", "agl=%.2f speed=%.2f vs=%.2f time=%.2f gear=%d" % [
		agl,
		speed,
		velocity.y,
		_terrain_landing_settled_timer_s,
		_get_grounded_gear_count(),
	])
	return true


func _debug_lz_landing_pending(
		flat_dist: float,
		agl: float,
		close_to_lz: bool,
		soft_touchdown: bool,
		grounded_touchdown: bool
) -> void:
	if not lz_landing_debug_enabled or not is_instance_valid(aircraft):
		return
	var near_lz := flat_dist <= maxf(terrain_landing_touchdown_radius_m * 1.75, 30.0)
	var near_ground := agl <= maxf(landing_flare_agl_m, 4.0)
	if not near_lz and not near_ground:
		return
	_lz_landing_debug_emit_s -= _physics_delta
	if _lz_landing_debug_emit_s > 0.0:
		return
	_lz_landing_debug_emit_s = maxf(lz_landing_debug_interval_s, 0.1)

	var vel := aircraft.linear_velocity
	var planar_speed := Vector2(vel.x, vel.z).length()
	var speed := vel.length()
	var gear_count := _get_grounded_gear_count()
	var brake := bool(aircraft.get_meta("parking_brake", false))
	var engine_current := _debug_float_property(engine, "current_power")
	var engine_target := _debug_float_property(engine, "target_power")
	var control_target := _debug_float_property(control_engine, "target_power")
	var hover_collective := _debug_float_property(helicopter_flight, "hover_collective")
	var engine_working := _debug_bool_property(engine, "is_engine_working")
	_debug_event("lz_landing_pending", "flat=%.1f agl=%.2f close=%s soft=%s grounded=%s gear=%d speed=%.2f planar=%.2f vs=%.2f brake=%s freeze=%s sleep=%s col_cmd=%.2f ctl_target=%.2f eng_target=%.2f eng_current=%.2f eng_working=%s hover_col=%.2f dest=%s" % [
		flat_dist,
		agl,
		str(close_to_lz),
		str(soft_touchdown),
		str(grounded_touchdown),
		gear_count,
		speed,
		planar_speed,
		vel.y,
		str(brake),
		str(aircraft.freeze),
		str(aircraft.sleeping),
		_collective_cmd,
		control_target,
		engine_target,
		engine_current,
		str(engine_working),
		hover_collective,
		str(destination.snapped(Vector3.ONE * 0.1)),
	])


func _update_lz_departure_debug(delta: float) -> void:
	if not lz_departure_debug_enabled or _lz_departure_debug_timer_s <= 0.0:
		return
	_lz_departure_debug_timer_s = maxf(_lz_departure_debug_timer_s - delta, 0.0)
	_lz_departure_debug_emit_s -= delta
	if _lz_departure_debug_emit_s > 0.0 and _lz_departure_debug_timer_s > 0.0:
		return
	_lz_departure_debug_emit_s = maxf(lz_departure_debug_interval_s, 0.05)
	_debug_lz_departure_snapshot("takeoff")


func _debug_lz_departure_snapshot(stage: String) -> void:
	if not lz_departure_debug_enabled or not is_instance_valid(aircraft):
		return
	var ground_height := _get_ground_height_at_position(aircraft.global_position)
	var agl := aircraft.global_position.y - ground_height if not is_nan(ground_height) else NAN
	var vel := aircraft.linear_velocity
	var planar_speed := Vector2(vel.x, vel.z).length()
	var gear_count := _get_grounded_gear_count()
	var brake := bool(aircraft.get_meta("parking_brake", false))
	var transport := bool(aircraft.get_meta("carrier_transport_mode", false))
	var deck_ready := bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false))
	var reference := aircraft.has_meta("helicopter_deck_reference_node")
	var gravity_scale := float(aircraft.get("gravity_scale"))
	var engine_current := _debug_float_property(engine, "current_power")
	var engine_target := _debug_float_property(engine, "target_power")
	var control_target := _debug_float_property(control_engine, "target_power")
	var hover_collective := _debug_float_property(helicopter_flight, "hover_collective")
	var engine_working := _debug_bool_property(engine, "is_engine_working")
	_debug_event("lz_departure", "stage=%s pos=%s agl=%.2f ground=%.1f freeze=%s sleeping=%s brake=%s transport=%s deck_ready=%s ref=%s gear=%d vel=%s planar=%.2f vs=%.2f gravity=%.2f col_cmd=%.2f ctl_target=%.2f eng_target=%.2f eng_current=%.2f eng_working=%s hover_col=%.2f pitch=%.2f roll=%.2f yaw=%.2f desired_alt=%.1f wp=%s dest=%s" % [
		stage,
		str(aircraft.global_position.snapped(Vector3.ONE * 0.1)),
		agl,
		ground_height,
		str(aircraft.freeze),
		str(aircraft.sleeping),
		str(brake),
		str(transport),
		str(deck_ready),
		str(reference),
		gear_count,
		str(vel.snapped(Vector3.ONE * 0.1)),
		planar_speed,
		vel.y,
		gravity_scale,
		_collective_cmd,
		control_target,
		engine_target,
		engine_current,
		str(engine_working),
		hover_collective,
		_pitch_cmd,
		_roll_cmd,
		_yaw_cmd,
		_desired_altitude_m,
		str(_nav_waypoint.snapped(Vector3.ONE * 0.1)),
		str(destination.snapped(Vector3.ONE * 0.1)),
	])


func _debug_float_property(node: Object, property_name: String) -> float:
	if not is_instance_valid(node):
		return NAN
	var value: Variant = node.get(property_name)
	if value == null:
		return NAN
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return NAN


func _debug_bool_property(node: Object, property_name: String) -> bool:
	if not is_instance_valid(node):
		return false
	var value: Variant = node.get(property_name)
	if value == null:
		return false
	return bool(value)


func _get_down_feeler_ground_height(world_pos: Vector3) -> float:
	var center_h := _get_ground_height_at_position(world_pos)
	var radius := maxf(terrain_down_feeler_radius_m, 0.0)
	if radius <= 0.0:
		return center_h
	var nav_grid: Node = get_node_or_null("/root/TerrainNavGrid")
	if nav_grid == null or not nav_grid.has_method("get_max_height_in_radius"):
		return center_h
	var radius_h := float(nav_grid.call("get_max_height_in_radius", world_pos.x, world_pos.z, radius))
	if radius_h <= -500000.0:
		return center_h
	if is_nan(center_h):
		return radius_h
	return maxf(center_h, radius_h)


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
	var excludes: Array[RID] = [aircraft.get_rid()]
	var carrier := get_tree().get_first_node_in_group("carrier")
	if carrier is CollisionObject3D:
		excludes.append(carrier.get_rid())
	query.exclude = excludes
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

	var debug_line := "HELI_AI craft=%s %s/%s cphase=%s pos=%s agl=%.1f tgt=%.1f onc=%s spd=%.1f vs=%.1f/%+.1f tvrate=%.1f col=%.2f/%.2f lean=%.2f pa=%.2f st=%.2f tr=%.2f sep=%.0f/%.1f v_avoid=%.1f ctl=(%.2f,%.2f,%.2f) dist=%.0f" % [
			aircraft.name,
			_state_name(),
			_mission_name(),
			_carrier_approach_phase_name(),
			str(aircraft.global_position.snapped(Vector3.ONE)),
			agl,
			_desired_altitude_m,
			str(_landing_on_carrier),
			abs_speed,
			aircraft.linear_velocity.y,
			_debug_vertical_rate_error_mps,
			_debug_target_vertical_rate_mps,
			_collective_cmd,
			_debug_collective_target,
			_debug_forward_error_mps,
			_debug_altitude_pitch,
			_debug_sharp_turn,
			_debug_terrain_recovery,
			_debug_airborne_separation_dist_m if _debug_airborne_separation_dist_m < INF else -1.0,
			_debug_airborne_separation_speed_limit_mps if _debug_airborne_separation_speed_limit_mps < INF else -1.0,
			_airborne_separation_vertical_avoidance_mps,
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


func _check_recorder_faults(delta: float) -> void:
	if not crash_log_enabled or not is_instance_valid(aircraft):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var pos := aircraft.global_position
	var vel := aircraft.linear_velocity
	var speed := vel.length()
	var recent_origin_shift := now - _last_origin_shift_s < maxf(debug_interval_s * 2.0, 0.5)

	if speed >= maxf(recorder_velocity_spike_mps, 1.0) and _can_write_fault_report(now):
		_debug_output("HELI_AI event=velocity_spike craft=%s speed=%.1f pos=%s last_origin_shift=%.2fs offset=%s" % [
			aircraft.name,
			speed,
			str(pos.snapped(Vector3.ONE * 0.1)),
			now - _last_origin_shift_s,
			str(_last_origin_shift_offset.snapped(Vector3.ONE * 0.1)),
		])
		_write_flight_recorder_report("VELOCITY SPIKE", "speed=%.1f m/s recent_origin_shift=%s" % [speed, str(recent_origin_shift)])

	if _last_recorder_position != Vector3.INF and _last_recorder_sample_s > 0.0:
		var sample_dt := maxf(now - _last_recorder_sample_s, 0.001)
		var moved_speed := _last_recorder_position.distance_to(pos) / sample_dt
		var expected_speed := maxf(speed, _get_control_velocity().length())
		if moved_speed >= maxf(recorder_position_jump_mps, 1.0) \
				and moved_speed > expected_speed * 1.8 \
				and _last_recorder_position.distance_to(pos) > 10.0 \
				and not recent_origin_shift \
				and _can_write_fault_report(now):
			_debug_output("HELI_AI event=position_jump craft=%s moved_speed=%.1f vel=%.1f dt=%.3f from=%s to=%s" % [
				aircraft.name,
				moved_speed,
				speed,
				sample_dt,
				str(_last_recorder_position.snapped(Vector3.ONE * 0.1)),
				str(pos.snapped(Vector3.ONE * 0.1)),
			])
			_write_flight_recorder_report("POSITION JUMP", "moved_speed=%.1f m/s velocity=%.1f m/s" % [moved_speed, speed])
	_last_recorder_position = pos
	_last_recorder_sample_s = now

	var sink_rate := -vel.y
	if sink_rate >= maxf(recorder_sink_rate_mps, 1.0) and _can_write_fault_report(now):
		_debug_output("HELI_AI event=high_sink_rate craft=%s sink=%.1f pos=%s" % [
			aircraft.name,
			sink_rate,
			str(pos.snapped(Vector3.ONE * 0.1)),
		])
		_write_flight_recorder_report("HIGH SINK RATE", "sink=%.1f m/s" % sink_rate)

	var reverse_speed := -vel.dot(aircraft.global_transform.basis.z)
	if reverse_speed >= maxf(recorder_reverse_speed_mps, 1.0) and _can_write_fault_report(now):
		_debug_output("HELI_AI event=high_reverse_speed craft=%s reverse=%.1f pos=%s" % [
			aircraft.name,
			reverse_speed,
			str(pos.snapped(Vector3.ONE * 0.1)),
		])
		_write_flight_recorder_report("HIGH REVERSE SPEED", "reverse=%.1f m/s" % reverse_speed)

	var up_dot := aircraft.global_transform.basis.y.normalized().dot(Vector3.UP)
	if up_dot <= recorder_inverted_dot and (state == State.IDLE or mission_phase == MissionPhase.AT_CARRIER):
		_inverted_timer_s += delta
	else:
		_inverted_timer_s = 0.0
	if _inverted_timer_s >= maxf(recorder_inverted_time_s, 0.1) and _can_write_fault_report(now):
		_debug_output("HELI_AI event=inverted_fault craft=%s up_dot=%.2f pos=%s state=%s/%s" % [
			aircraft.name,
			up_dot,
			str(pos.snapped(Vector3.ONE * 0.1)),
			_state_name(),
			_mission_name(),
		])
		_write_flight_recorder_report("INVERTED FAULT", "up_dot=%.2f inverted_for=%.1fs" % [up_dot, _inverted_timer_s])


func _can_write_fault_report(now: float) -> bool:
	if now - _last_fault_report_s < maxf(recorder_fault_cooldown_s, 1.0):
		return false
	_last_fault_report_s = now
	return true


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
		MissionPhase.RESCUE: return "RESCUE"
	return "UNKNOWN"


func _carrier_approach_phase_name() -> String:
	match _carrier_approach_phase:
		CarrierApproachPhase.NONE: return "NONE"
		CarrierApproachPhase.TO_APPROACH_POINT: return "TO_APPROACH_POINT"
		CarrierApproachPhase.FINAL: return "FINAL"
		CarrierApproachPhase.DESCEND: return "DESCEND"
	return "UNKNOWN"


func _elapsed_s() -> float:
	return Time.get_ticks_msec() / 1000.0 - _flight_start_time_s


func _record_milestone(text: String) -> void:
	if not crash_log_enabled:
		return
	_milestone_log.append("  [+%.1fs]  %s" % [_elapsed_s(), text])


func _start_flight_summary() -> void:
	_flight_sequence += 1
	_active_flight_id = _flight_sequence
	_milestone_log.clear()
	_flight_departed_carrier_s = _elapsed_s()
	_flight_landed_lz_s = NAN
	_flight_departed_lz_s = NAN
	_flight_lz_position = Vector3.INF
	_flight_landed_lz = false
	_flight_terminal_report_written = false
	_record_milestone("Flight %d departed carrier" % _active_flight_id)


func _write_flight_summary_report(outcome: String) -> void:
	if not crash_log_enabled or _active_flight_id <= 0:
		return
	var craft_name: String = aircraft.name if is_instance_valid(aircraft) else "unknown"
	var now_s := _elapsed_s()
	var carrier_pos := aircraft.global_position if is_instance_valid(aircraft) else Vector3.INF
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=" .repeat(72))
	lines.append("FLIGHT SUMMARY - %s flight=%d outcome=%s" % [craft_name, _active_flight_id, outcome])
	if not is_nan(_flight_departed_carrier_s):
		lines.append("Duration: %.1fs since carrier departure" % [now_s - _flight_departed_carrier_s])
	var lz_status := "NO"
	if _flight_landed_lz:
		lz_status = "YES at +%.1fs pos=%s" % [_flight_landed_lz_s, str(_flight_lz_position.snapped(Vector3.ONE))]
	lines.append("LZ landed: %s" % lz_status)
	var carrier_pos_str := "?"
	if carrier_pos != Vector3.INF:
		carrier_pos_str = str(carrier_pos.snapped(Vector3.ONE))
	lines.append("Returned to carrier: YES at +%.1fs pos=%s" % [
		now_s,
		carrier_pos_str,
	])
	if not is_nan(_flight_departed_lz_s):
		lines.append("Departed LZ: +%.1fs" % [_flight_departed_lz_s])
	lines.append("State: %s / %s" % [_state_name(), _mission_name()])
	lines.append("")
	lines.append("--- Flight milestones ---")
	if _milestone_log.is_empty():
		lines.append("  (none)")
	else:
		for m in _milestone_log:
			lines.append(m)
	lines.append("=" .repeat(72))
	lines.append("")
	var duration_note := ""
	if not is_nan(_flight_departed_carrier_s):
		duration_note = "duration=%.0fs lz=%s" % [_elapsed_s() - _flight_departed_carrier_s, "YES" if _flight_landed_lz else "NO"]
	_write_compact_log_entry(outcome, duration_note, 0)
	_flight_terminal_report_written = true


func _write_incomplete_flight_report(reason: String) -> void:
	if not crash_log_enabled or _active_flight_id <= 0:
		return
	var craft_name: String = aircraft.name if is_instance_valid(aircraft) else "unknown"
	var now_s := _elapsed_s()
	var pos := aircraft.global_position if is_instance_valid(aircraft) else Vector3.INF
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=" .repeat(72))
	lines.append("FLIGHT INCOMPLETE - %s flight=%d reason=%s" % [craft_name, _active_flight_id, reason])
	if not is_nan(_flight_departed_carrier_s):
		lines.append("Elapsed: %.1fs since carrier departure" % [now_s - _flight_departed_carrier_s])
	var lz_status := "NO"
	if _flight_landed_lz:
		lz_status = "YES at +%.1fs pos=%s" % [_flight_landed_lz_s, str(_flight_lz_position.snapped(Vector3.ONE))]
	lines.append("LZ landed: %s" % lz_status)
	lines.append("Returned to carrier: NO")
	var pos_str := "?"
	if pos != Vector3.INF:
		pos_str = str(pos.snapped(Vector3.ONE))
	lines.append("Last position: %s" % pos_str)
	lines.append("State: %s / %s" % [_state_name(), _mission_name()])
	lines.append("")
	lines.append("--- Flight milestones ---")
	if _milestone_log.is_empty():
		lines.append("  (none)")
	else:
		for m in _milestone_log:
			lines.append(m)
	lines.append("=" .repeat(72))
	lines.append("")
	var pos_note := "reason=%s pos=%s state=%s/%s" % [reason, pos_str, _state_name(), _mission_name()]
	_write_compact_log_entry("INCOMPLETE", pos_note, 0)
	_flight_terminal_report_written = true


func _append_current_flight_status(lines: PackedStringArray) -> void:
	if _active_flight_id <= 0:
		lines.append("Flight: not started")
		return
	lines.append("Flight: %d" % _active_flight_id)
	if not is_nan(_flight_departed_carrier_s):
		lines.append("Departed carrier: +%.1fs" % _flight_departed_carrier_s)
	var lz_status := "NO"
	if _flight_landed_lz:
		lz_status = "YES at +%.1fs pos=%s" % [_flight_landed_lz_s, str(_flight_lz_position.snapped(Vector3.ONE))]
	lines.append("LZ landed: %s" % lz_status)
	if not is_nan(_flight_departed_lz_s):
		lines.append("Departed LZ: +%.1fs" % _flight_departed_lz_s)


func _on_aircraft_destroyed_flight_recorder() -> void:
	_release_carrier_landing_clearance_from_deck()
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
	_append_current_flight_status(lines)
	lines.append("")
	lines.append("--- Flight milestones ---")
	if _milestone_log.is_empty():
		lines.append("  (none)")
	else:
		for m in _milestone_log:
			lines.append(m)
	lines.append("")
	lines.append("--- HELI_AI: last %.0f s ---" % [maxf(crash_log_history_s, 1.0)])
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

	_append_lines_to_log("user://heli_crash_report_%s.log" % craft_name.replace(" ", "_"), lines, "crash log")
	var pos_note := "pos=%s agl=%s state=%s/%s" % [pos_str, agl_str, _state_name(), _mission_name()]
	_record_heli_ui_stat("crash")
	_write_compact_log_entry("CRASHED", pos_note, 3)
	_flight_terminal_report_written = true
	print("[HelicopterPilot] Crash log written for: %s" % craft_name)


func save_manual_log(details: String = "") -> void:
	var craft_name: String = aircraft.name if is_instance_valid(aircraft) else "unknown"
	var pos_str: String = str(aircraft.global_position.snapped(Vector3.ONE)) if is_instance_valid(aircraft) else "?"
	var ground_h: float = _get_ground_height_at_position(aircraft.global_position) if is_instance_valid(aircraft) else NAN
	var agl_str: String = "%.1fm" % [aircraft.global_position.y - ground_h] if is_instance_valid(aircraft) and not is_nan(ground_h) else "?"
	var velocity_str: String = str(aircraft.linear_velocity.snapped(Vector3.ONE * 0.1)) if is_instance_valid(aircraft) else "?"
	var up_dot_str: String = "%.2f" % [aircraft.global_transform.basis.y.normalized().dot(Vector3.UP)] if is_instance_valid(aircraft) else "?"

	var lines: PackedStringArray = PackedStringArray()
	lines.append("=" .repeat(72))
	lines.append("MANUAL LOG REPORT - %s" % craft_name)
	lines.append("Time since AI start: +%.1fs" % [_elapsed_s()])
	lines.append("Position: %s  AGL: %s" % [pos_str, agl_str])
	lines.append("Velocity: %s  up_dot: %s" % [velocity_str, up_dot_str])
	lines.append("State: %s / %s" % [_state_name(), _mission_name()])
	_append_current_flight_status(lines)
	if not details.is_empty():
		lines.append("Details: %s" % details)
	lines.append("")
	lines.append("--- Flight milestones ---")
	if _milestone_log.is_empty():
		lines.append("  (none)")
	else:
		for m in _milestone_log:
			lines.append(m)
	lines.append("")
	lines.append("--- HELI_AI: last %.0f s ---" % [maxf(crash_log_history_s, 1.0)])
	if _flight_log.is_empty():
		if not crash_log_enabled:
			lines.append("  (no debug lines captured — crash_log_enabled is false)")
		else:
			lines.append("  (no debug lines captured)")
	else:
		var t0: float = _flight_log[0][0]
		for entry in _flight_log:
			lines.append("  [+%.2fs]  %s" % [entry[0] - t0, entry[1]])
	lines.append("")
	lines.append("*** MANUAL LOG ***")
	lines.append("=" .repeat(72))
	lines.append("")

	var filename := "user://heli_crash_report_%s.log" % craft_name.replace(" ", "_")
	_append_lines_to_log(filename, lines, "manual flight log")
	_append_lines_to_log(crash_log_aggregate_path, lines, "aggregate helicopter log")
	print("[HelicopterPilot] Manual flight log saved for %s to %s" % [craft_name, filename])


func _write_flight_recorder_report(report_type: String, details: String = "") -> void:
	if not crash_log_enabled:
		return
	var craft_name: String = aircraft.name if is_instance_valid(aircraft) else "unknown"
	var pos_str: String = str(aircraft.global_position.snapped(Vector3.ONE)) if is_instance_valid(aircraft) else "?"
	var ground_h: float = _get_ground_height_at_position(aircraft.global_position) if is_instance_valid(aircraft) else NAN
	var agl_str: String = "%.1fm" % [aircraft.global_position.y - ground_h] if is_instance_valid(aircraft) and not is_nan(ground_h) else "?"
	var velocity_str: String = str(aircraft.linear_velocity.snapped(Vector3.ONE * 0.1)) if is_instance_valid(aircraft) else "?"
	var up_dot_str: String = "%.2f" % [aircraft.global_transform.basis.y.normalized().dot(Vector3.UP)] if is_instance_valid(aircraft) else "?"

	var lines: PackedStringArray = PackedStringArray()
	lines.append("=" .repeat(72))
	lines.append("%s REPORT - %s" % [report_type, craft_name])
	lines.append("Time since AI start: +%.1fs" % [_elapsed_s()])
	lines.append("Last known position: %s  AGL: %s" % [pos_str, agl_str])
	lines.append("Velocity: %s  up_dot: %s" % [velocity_str, up_dot_str])
	lines.append("State: %s / %s" % [_state_name(), _mission_name()])
	_append_current_flight_status(lines)
	if not details.is_empty():
		lines.append("Details: %s" % details)
	lines.append("")
	lines.append("--- Flight milestones ---")
	if _milestone_log.is_empty():
		lines.append("  (none)")
	else:
		for m in _milestone_log:
			lines.append(m)
	lines.append("")
	lines.append("--- HELI_AI: last %.0f s ---" % [maxf(crash_log_history_s, 1.0)])
	if _flight_log.is_empty():
		lines.append("  (no debug lines captured)")
	else:
		var t0: float = _flight_log[0][0]
		for entry in _flight_log:
			lines.append("  [+%.2fs]  %s" % [entry[0] - t0, entry[1]])
	lines.append("")
	lines.append("*** %s ***" % report_type)
	lines.append("=" .repeat(72))
	lines.append("")

	_append_lines_to_log("user://heli_crash_report_%s.log" % craft_name.replace(" ", "_"), lines, "flight recorder log")
	if report_type != "POSITION JUMP":
		_append_lines_to_log(crash_log_aggregate_path, lines, "aggregate helicopter log")
	print("[HelicopterPilot] Flight recorder report written for: %s" % craft_name)


func _get_aircraft_type_label() -> String:
	if not is_instance_valid(aircraft):
		return "unknown"
	var scene_path: String = aircraft.scene_file_path
	if scene_path.is_empty():
		return aircraft.name
	return scene_path.get_file().get_basename()


func _record_heli_ui_stat(stat_name: String) -> void:
	if not is_instance_valid(aircraft):
		return
	var fd_mgr := get_tree().get_first_node_in_group("flight_deck_manager")
	if fd_mgr and fd_mgr.has_method("record_heli_stat"):
		fd_mgr.record_heli_stat(aircraft, stat_name)


func _write_compact_log_entry(outcome: String, notes: String, last_debug_lines: int) -> void:
	if crash_log_aggregate_path.is_empty():
		return
	var craft_name: String = aircraft.name if is_instance_valid(aircraft) else "unknown"
	var type_label := _get_aircraft_type_label()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%-20s  %-30s  %-10s  %s" % [craft_name, type_label, outcome, notes])
	if last_debug_lines > 0 and not _flight_log.is_empty():
		var start := maxi(_flight_log.size() - last_debug_lines, 0)
		var t0: float = _flight_log[start][0]
		for i in range(start, _flight_log.size()):
			lines.append("  [%+.1fs]  %s" % [_flight_log[i][0] - t0, _flight_log[i][1]])
	_append_lines_to_log(crash_log_aggregate_path, lines, "aggregate helicopter log")


func _append_lines_to_log(path: String, lines: PackedStringArray, description: String) -> void:
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		push_warning("[HelicopterPilot] Could not open %s: %s" % [description, path])
		return
	file.seek_end()
	for line in lines:
		file.store_line(line)
	file.close()


func _overwrite_lines_to_log(path: String, lines: PackedStringArray, description: String) -> void:
	if path.is_empty():
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[HelicopterPilot] Could not reset %s: %s" % [description, path])
		return
	for line in lines:
		file.store_line(line)
	file.close()


func _write_to_helicopter_paths_log(msg: String) -> void:
	var lines := PackedStringArray()
	lines.append(msg)
	_append_lines_to_log("res://helicopter_paths.log", lines, "helicopter paths log")
	_append_lines_to_log("user://helicopter_paths.log", lines, "helicopter paths log")
	print("[helicopter_paths] " + msg)
