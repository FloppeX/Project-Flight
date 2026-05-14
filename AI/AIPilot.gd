class_name AIPilot
extends Node

const PROJECTILE_SPEED_CAP_SETTING_KEYS: Array = [
	"physics/jolt_3d/simulation/limits/max_linear_velocity",
	"physics/jolt_physics_3d/simulation/limits/max_linear_velocity",
	"physics/jolt_3d/limits/max_linear_velocity",
	"physics/jolt_physics_3d/limits/max_linear_velocity",
	"physics/3d/max_linear_velocity",
]

## AI Pilot - Controls aircraft like a human using same input system
## Uses PID controllers for smooth, human-like control

# ============================================================================
# STATE MACHINE
# ============================================================================
enum State {
	IDLE,           # Waiting on deck
	LAUNCHING,      # In catapult sequence
	CLIMBING,       # Climbing after launch
	TRANSIT,        # Flying to waypoint
	SEARCH,         # Patrol - looking for ground targets
	ATTACK_POSITIONING,  # Flying to attack run start waypoint (800m in front, 300m above target)
	ATTACK_INBOUND, # Bombing only: fly level toward target before dive
	ATTACK_DIVE,    # Diving at target, firing guns, pull up at 100m
	ATTACK_BREAK_OFF,   # Too close - fly away from target, then line up new run
	DOGFIGHT,       # Air-to-air gun combat with lead pursuit + burst fire
	ENGAGE,         # Attacking target (legacy/air combat)
	RTB,            # Returning to base
	RECOVERY_MARSHAL,  # Fly to a high carrier-relative recovery gate and request clearance
	RECOVERY_HOLD,     # Hold behind the carrier until the deck is clear
	RECOVERY_APPROACH, # Step down through carrier-relative gates before final landing
	APPROACH,       # Carrier approach pattern
	LANDING,        # Final approach and landing
	MISSED_APPROACH # Bolter/go-around back to takeoff_0
}

enum DogfightLostSightBehavior {
	EFFICIENT,
	WRONG_TURN,
	CLIMB,
	EXTEND,
	OFFSET
}

enum ApproachGuidanceMode {
	WAYPOINT_CHAIN,
	PATH_FOLLOWER
}

enum AIPilotSkill {
	ROOKIE,
	EXPERIENCED,
	VETERAN,
	ACE
}

var current_state: State = State.IDLE

# ============================================================================
# REFERENCES
# ============================================================================
var aircraft: RigidBody3D
var control_engine: Node  # ControlEngine module
var simple_aero: Node     # SimpleAero module
var engine: Node          # Engine module
var control_gear: Node    # ControlLandingGear module
var control_weapons: Node # ControlWeapons module (for ground attack)
var control_targeting_aam: Node # Cached AAM targeting module for dogfight missile support
var cached_hardpoints: Array = []  # Cached hardpoints list

# Saved SimpleAero values for restoration when AI is disabled
var _saved_stability_strength: float = -1.0
var _saved_auto_rudder_strength: float = -1.0
var _ai_control_overrides_applied: bool = false

# ============================================================================
# SENSORS - AI's limited view of the world
# ============================================================================
var altitude_agl: float = 0.0  # Altitude above ground level
var terrain_ahead_distance: float = INF  # Distance to terrain in flight path
var known_enemies: Array[Node3D] = []  # Enemies in sensor range
var known_friendlies: Array[Node3D] = []  # Friendly aircraft in sensor range
var cached_hostile_nodes: Array[Node3D] = []  # Cached raw hostile group nodes
var cached_friendly_nodes: Array[Node3D] = []  # Cached raw friendly group nodes
var sensor_update_counter: int = 0
@export var sensor_update_interval: int = 10  # Update cached groups every N frames
@export var contact_scan_interval_s: float = 0.18  # Filter cached contacts at low frequency; group lookup is still frame-staggered.
@export var contact_report_interval_s: float = 1.5
var _terrain_check_counter: int = 0
@export var terrain_check_interval: int = 3  # Update terrain fan/ahead every N physics frames (~20 Hz at 60 Hz physics)
@export var collision_avoidance_interval_s: float = 0.10
@export var rtb_check_interval_s: float = 1.0
var _contact_scan_timer_s: float = 0.0
var _contact_report_timer_s: float = 0.0
var _collision_avoidance_timer_s: float = 0.0
var _rtb_check_timer_s: float = 0.0
var _smoothed_ground_height: float = NAN  # Smoothed ground height for stable low-level flight
var _cached_day_night_cycle: Node = null
var _cached_ai_darkness_factor: float = 0.0
var _ai_darkness_cache_at_ms: int = -100000
# Terrain fan avoidance â€” directional escape sampling
var _terrain_fan_clearances: PackedFloat32Array = PackedFloat32Array([INF, INF, INF, INF, INF])
var _terrain_fan_best_idx: int = 2  # Index into fan angles; 2 = forward
var _terrain_height_callable: Callable  # Cached get_height callable â€” resolved once on first use
var _safety_override_active: bool = false  # True when terrain/collision override is controlling

@export var sensor_range: float = 5000.0  # How far AI can "see"
@export_group("Night Combat Penalties")
@export_range(0.1, 1.0, 0.05) var night_sensor_range_multiplier: float = 0.58
@export_range(1.0, 4.0, 0.05) var night_contact_scan_interval_multiplier: float = 1.65
@export_range(0.1, 1.0, 0.05) var night_dogfight_max_range_multiplier: float = 0.72
@export_range(0.0, 0.5, 0.01) var night_fire_hit_chance_bonus: float = 0.16
@export_range(0.1, 1.0, 0.05) var night_fire_max_tof_multiplier: float = 0.72
@export_range(1.0, 12.0, 0.25) var night_ground_gun_alignment_deg: float = 3.75
@export_range(0.1, 1.0, 0.05) var night_rocket_release_tolerance_multiplier: float = 0.70
@export_group("")
@export var ground_check_distance: float = 10000.0  # Max distance for AGL raycast
@export var terrain_ahead_check_distance: float = 2000.0  # How far ahead to check for terrain
@export var terrain_warning_distance: float = 500.0  # Pull up if terrain closer than this
@export var emergency_min_agl_m: float = 180.0  # Emergency override if below this AGL
@export var emergency_tti_s: float = 3.0  # Emergency override if terrain time-to-impact is below this
@export var terrain_escape_low_speed_pitch_input: float = 0.18  # Pull-up authority near stall speed
@export var terrain_escape_max_pitch_input: float = 0.68  # Pull-up authority with healthy energy
@export var terrain_escape_full_pull_speed_margin_mps: float = 45.0
@export var terrain_escape_min_target_pitch_deg: float = 6.0
@export var terrain_escape_max_target_pitch_deg: float = 18.0
@export var terrain_escape_critical_pitch_bonus_deg: float = 7.0
@export var terrain_escape_lateral_roll_input: float = 0.65
@export var rocket_attack_commit_extra_range_m: float = 140.0
@export var rocket_attack_commit_min_agl_m: float = 55.0
@export var rocket_attack_commit_critical_tti_s: float = 1.15
@export var gun_attack_commit_extra_range_m: float = 120.0
@export var gun_attack_commit_min_agl_m: float = 45.0
@export var gun_attack_commit_critical_tti_s: float = 1.0

# ============================================================================
# PID CONTROLLERS - Smooth human-like control
# ============================================================================
var altitude_controller: PIDController
var heading_controller: PIDController
var speed_controller: PIDController
var pitch_controller: PIDController  # For precise pitch control

# ============================================================================
# TARGETS - What the AI wants to achieve
# ============================================================================
var target_altitude: float = 300.0
var target_heading: float = 0.0  # Radians
var target_speed: float = 80.0   # m/s
var target_waypoint: Vector3 = Vector3.ZERO
var combat_target: Node3D = null
var formation_anchor_active: bool = false
var formation_anchor: Vector3 = Vector3.ZERO
var formation_speed_cap_mps: float = -1.0
var formation_speed_bias_mps: float = 0.0
var formation_slot_quality: float = 0.0
var formation_ahead_hold_t: float = 0.0

# Two-layer waypoint system
var nav_waypoint: Vector3 = Vector3.ZERO  # High-level navigation goal
var maneuver_waypoint: Vector3 = Vector3.ZERO  # Short-term maneuvering target
@export var maneuver_lookahead_distance: float = 800.0  # How far ahead to place maneuver waypoint
@export var formation_close_bank_limit_deg: float = 30.0
@export var formation_close_pitch_limit_deg: float = 12.0
@export var formation_close_vs_limit_mps: float = 4.0
@export var formation_close_pitch_gain_scale: float = 0.65
@export var formation_close_bank_gain_scale: float = 0.45
@export var formation_turnaround_bank_scale: float = 0.28
@export var formation_turnaround_bearing_soften_deg: float = 35.0

# Ground attack parameters
@export var attack_run_distance_m: float = 800.0   # Waypoint ~800m in front of target
@export var attack_run_altitude_offset_m: float = 300.0  # Waypoint 300m above target
@export var bomb_run_setup_distance_m: float = 1350.0  # Bomb run setup distance from target
@export var bomb_run_setup_altitude_offset_m: float = 360.0  # Bomb run setup altitude above target
@export var bomb_run_setup_max_altitude_offset_m: float = 480.0
@export var rocket_run_setup_distance_m: float = 900.0
@export var rocket_run_altitude_offset_m: float = 180.0
@export var bomb_dive_start_distance_m: float = 1150.0  # Start bomb dive at this HORIZONTAL range
@export var bomb_dive_start_altitude_factor: float = 3.2
@export var bomb_dive_start_min_target_dot: float = 0.82
@export var bomb_dive_start_max_bank_deg: float = 25.0
@export var attack_pull_up_distance_m: float = 150.0  # Break off when this close to target (gun runs)
@export var bomb_pull_up_distance_m: float = 250.0   # Break off distance for bomb runs
@export var rocket_pull_up_distance_m: float = 120.0
@export var bomb_dive_aim_height_m: float = 90.0     # Aim this many metres above the target during bomb dive
@export var bomb_dive_close_aim_height_m: float = 75.0
@export var rocket_dive_aim_height_m: float = 3.0
@export var bomb_release_altitude_window_m: float = 650.0  # Max altitude above target at which bomb can be released
@export var bomb_ccip_release_tolerance_m: float = 140.0  # Fallback release tolerance if skill-specific bombing is disabled
@export var bomb_rookie_release_tolerance_m: float = 120.0
@export var bomb_experienced_release_tolerance_m: float = 70.0
@export var bomb_veteran_release_tolerance_m: float = 40.0
@export var bomb_ace_release_tolerance_m: float = 20.0
@export var bomb_release_best_miss_slack_m: float = 6.0
@export var bomb_release_after_best_worsen_m: float = 3.0
@export var bomb_release_after_best_grace_m: float = 20.0
@export var bomb_release_best_solution_tolerance_multiplier: float = 6.0
@export var bomb_ccip_fallback_alt_m: float = 320.0       # Legacy tuning value; bomb release now requires a valid CCIP solution
@export var bomb_release_min_range_m: float = 180.0       # Do not salvage bad bomb runs with very close drops
@export var bomb_ccip_aim_correction_max_m: float = 260.0
@export var bomb_ccip_aim_correction_close_range_m: float = 450.0
@export var bomb_ccip_aim_correction_close_scale: float = 0.55
@export var bomb_ccip_use_moving_target_plane: bool = true
@export var bomb_dive_pitch_los_gain: float = 3.2
@export var bomb_min_dive_angle_deg: float = 3.0          # Minimum flight path angle (degrees nose-down) to release bombs
@export var bomb_preferred_dive_angle_deg: float = 16.0
@export var bomb_dive_pullback_gain: float = 0.035
@export var bomb_ccip_recompute_interval_s: float = 0.08
@export var bomb_ccip_time_step_s: float = 0.04
@export var bomb_ccip_max_time_s: float = 10.0
@export var bomb_salvo_per_run: int = 2
@export var carrier_bomb_salvo_per_run: int = 3
@export var rocket_release_min_range_m: float = 120.0
@export var rocket_release_max_range_m: float = 520.0
@export var rocket_ccip_release_tolerance_m: float = 45.0
@export var rocket_min_dive_angle_deg: float = 8.0
@export var rocket_fire_alignment_deg: float = 22.0
@export var rocket_release_spacing_s: float = 0.35
@export var rocket_ccip_recompute_interval_s: float = 0.15
@export var rocket_shots_per_run: int = 6
@export var attack_break_off_distance_m: float = 500.0  # Must fly this far from target before lining up new run
@export var attack_aim_lead_time_s: float = 0.25  # Small lead for moving targets during dive
@export var bomb_target_lead_max_s: float = 8.0
@export var bomb_target_lead_scale: float = 1.0
@export var carrier_bomb_setup_along_motion: bool = false
@export var carrier_bomb_setup_min_speed_mps: float = 2.0
@export var carrier_bomb_target_lead_scale: float = 1.0
@export var carrier_bomb_target_lead_max_s: float = 7.0
@export var carrier_bomb_forward_bias_m: float = 35.0
@export var rocket_target_lead_max_s: float = 4.0
@export var rocket_target_lead_scale: float = 1.0
@export var bomb_release_spacing_s: float = 0.35   # Time spacing between bombs
@export var weapon_release_stability_hold_s: float = 0.18
@export var bomb_rookie_release_hold_s: float = 0.18
@export var bomb_experienced_release_hold_s: float = 0.12
@export var bomb_veteran_release_hold_s: float = 0.08
@export var bomb_ace_release_hold_s: float = 0.04
@export var bomb_release_max_bank_deg: float = 45.0
@export var rocket_release_max_bank_deg: float = 14.0
@export var attack_terrain_sample_refresh_s: float = 0.25
@export var attack_terrain_sample_reuse_distance_m: float = 60.0
@export var attack_positioning_direct_entry_after_s: float = 4.0
@export var attack_positioning_direct_entry_range_buffer_m: float = 250.0
@export var attack_positioning_direct_entry_min_dot: float = 0.55
@export var bomb_direct_entry_max_cross_track_m: float = 90.0
@export var bomb_direct_entry_max_altitude_overshoot_m: float = 120.0
@export var ground_attack_enabled: bool = true  # True = autonomous ground attack when valid targets appear
@export var dogfight_enabled: bool = true
@export var dogfight_proximity_override_m: float = 500.0  # Break off ground attack if enemy aircraft within this range
@export var engagement_radius_from_carrier_m: float = 4500.0
@export var disengage_radius_from_carrier_m: float = 6000.0
@export var dogfight_max_range_m: float = 1800.0
@export var dogfight_target_radius_m: float = 4.0
@export var dogfight_min_hit_chance: float = 0.72
@export var dogfight_fire_burst_s: float = 0.55
@export var dogfight_burst_cooldown_s: float = 0.22
@export var dogfight_min_aim_dot: float = 0.9982  # ~3.4 deg
@export var dogfight_fire_max_tof_s: float = 0.85
@export var dogfight_fire_precise_min_blend: float = 0.90
@export var dogfight_fire_precise_close_range_m: float = 300.0
@export var dogfight_fire_fallback_range_m: float = 220.0
@export var dogfight_fire_fallback_min_dot: float = 0.9986  # ~3.0 deg
@export var dogfight_fire_fallback_lateral: float = 0.025
@export var dogfight_fire_fallback_vertical: float = 0.02
@export var dogfight_fire_close_relax_range_m: float = 250.0
@export var dogfight_fire_close_relax_min_dot: float = 0.997  # ~4.4 deg
@export var dogfight_fire_close_relax_min_hit_chance: float = 0.55
@export var dogfight_gun_preferred_range_m: float = 450.0
@export var dogfight_missile_min_range_m: float = 650.0
@export var dogfight_missile_max_range_m: float = 2200.0
@export var dogfight_missile_max_off_boresight_deg: float = 18.0
@export var dogfight_missile_use_chance: float = 0.55
@export var dogfight_missile_commit_s: float = 1.2
@export var dogfight_missile_required_lock_s: float = 1.0
@export var dogfight_default_muzzle_velocity_mps: float = 500.0
@export var dogfight_retarget_interval_s: float = 0.5
@export var dogfight_retarget_advantage_m: float = 150.0
@export var dogfight_bank_cmd_limit_deg: float = 90.0
@export var dogfight_min_speed_mps: float = 60.0
@export var dogfight_max_speed_mps: float = 130.0
@export var dogfight_closure_speed_boost_mps: float = 15.0
@export var dogfight_corner_speed_mps: float = 85.0
@export var dogfight_turn_pitch_bias: float = 7.5
@export var dogfight_turn_vs_limit_mps: float = 42.0
@export var dogfight_turn_pull_vs_per_extra_g: float = 10.0
@export var dogfight_ground_protect_agl_m: float = 260.0
@export var dogfight_ground_protect_min_bank_deg: float = 30.0
@export var dogfight_ground_protect_min_climb_vs_mps: float = 8.0
@export var dogfight_collision_check_horizon_s: float = 3.0
@export var dogfight_collision_min_sep_m: float = 130.0
@export var dogfight_collision_escape_distance_m: float = 700.0
@export var dogfight_collision_escape_vertical_m: float = 260.0
@export var dogfight_stalemate_trigger_s: float = 6.0
@export var dogfight_variation_duration_s: float = 2.2
@export var dogfight_variation_cooldown_s: float = 4.0
@export var dogfight_variation_lateral_m: float = 650.0
@export var dogfight_variation_vertical_m: float = 220.0
@export var dogfight_max_rudder_input: float = 1.0
@export var dogfight_sideslip_damping_gain: float = 0.45
@export var dogfight_aim_rudder_gain: float = 0.12
@export var dogfight_coord_rudder_gain: float = 0.15
@export var dogfight_spiral_recovery_bank_deg: float = 40.0
@export var dogfight_spiral_recovery_sink_mps: float = 10.0
@export var dogfight_spiral_recovery_min_speed_mps: float = 75.0
@export var dogfight_spiral_recovery_duration_s: float = 1.8
@export var dogfight_spiral_recovery_climb_m: float = 320.0
@export var dogfight_spiral_recovery_forward_m: float = 900.0
@export var dogfight_vs_limit_mps: float = 16.0
@export var dogfight_vs_gain: float = 0.10
@export var dogfight_unload_speed_margin_mps: float = 8.0
@export var dogfight_unload_descent_gain: float = 0.18
@export var dogfight_low_speed_pitch_cap: float = 0.45
@export var dogfight_lead_pursuit_blend: float = 1.0
@export var dogfight_ballistic_aim_blend: float = 0.95
@export var dogfight_precise_ballistic_aim_blend: float = 1.0
@export var dogfight_rejoin_range_m: float = 2200.0
@export var dogfight_rejoin_speed_mps: float = 110.0
@export var dogfight_rejoin_bank_limit_deg: float = 45.0
@export var dogfight_lost_sight_cone_deg: float = 120.0
@export var dogfight_lost_sight_pursue_chance: float = 0.5
@export var dogfight_lost_sight_behavior_min_s: float = 0.9
@export var dogfight_lost_sight_behavior_max_s: float = 1.8
@export var dogfight_lost_sight_extend_forward_m: float = 900.0
@export var dogfight_lost_sight_extend_vertical_m: float = 120.0

var cached_ballistic_solution: Dictionary = {}
var ballistic_cache_time: float = 0.0
@export var ballistic_cache_duration: float = 0.1
@export var dogfight_straight_level_yaw_deg: float = 5.0
@export var dogfight_straight_level_bank_blend: float = 0.25
@export var dogfight_straight_level_pitch_blend: float = 0.15
@export var dogfight_simple_yaw_aim_gain: float = 1.8
@export var dogfight_simple_yaw_coord_gain: float = 0.55
@export var dogfight_simple_yaw_high_bank_scale: float = 1.0
@export var dogfight_simple_yaw_rejoin_scale: float = 0.9
@export var dogfight_simple_yaw_smoothing: float = 0.80
@export var dogfight_precise_aim_entry_deg: float = 35.0
@export var dogfight_precise_aim_full_deg: float = 1.5
@export var dogfight_precise_aim_max_range_m: float = 1800.0
@export var dogfight_precise_pid_blend: float = 1.0
@export var dogfight_precise_roll_response: float = 1.0
@export var dogfight_precise_pitch_response: float = 1.0
@export var dogfight_precise_yaw_response: float = 1.0
var _run_weapon_type: String = "Autocannon"
var _bombs_to_drop_this_run: int = 0
var _bombs_dropped_this_run: int = 0
var _last_bomb_drop_time_s: float = -INF
var _rockets_to_fire_this_run: int = 0
var _rockets_fired_this_run: int = 0
var _last_rocket_fire_time_s: float = -INF
var _prev_run_was_failed_bomb: bool = false  # True if last bomb run dropped nothing
var _bomb_run_altitude_m: float = 0.0
var _attack_setup_wp_xz: Vector2 = Vector2.ZERO   # Fixed setup-point XZ (set once per run)
var _attack_setup_target_pos: Vector3 = Vector3.ZERO  # Carrier pos when setup was planned
var _overshoot_recompute_cooldown_s: float = 0.0     # Prevents recomputing every frame after overshoot
var _positioning_time_s: float = 0.0                  # Time spent in ATTACK_POSITIONING; recompute if too long
var _prev_ccip_miss: float = INF  # Tracks CCIP miss from last frame to detect improving accuracy
var _ccip_cache_timer: float = 0.0  # Throttle CCIP to avoid per-frame ballistic sim
var _ccip_cached_result: Vector3 = Vector3.ZERO
var _ccip_cached_tof_s: float = -1.0
var _cached_bomb_linear_damp: float = -1.0  # -1 = not yet cached
var _cached_bomb_gravity_scale: float = 1.0
var _best_bomb_ccip_miss_this_run: float = INF
var _attack_terrain_sample_cache_until_s: float = -INF
var _attack_terrain_sample_cache_from: Vector3 = Vector3.ZERO
var _attack_terrain_sample_cache_to: Vector3 = Vector3.ZERO
var _attack_terrain_sample_cache_samples: int = -1
var _attack_terrain_sample_cache_value: float = NAN
var _release_solution_stable_time_s: float = 0.0
var _release_solution_last_update_s: float = -INF
var _attack_recovery_until_s: float = 0.0  # After emergency, hold egress before next run
var _dive_precise_aim: bool = false  # When true, use tighter bank for steadier final approach
var _dive_entry_time_s: float = -INF  # When we entered ATTACK_DIVE (for soft dive entry)
@export var attack_debug_summary_interval_s: float = 1.0
@export var general_debug_summary_interval_s: float = 10.0
var _periodic_debug_timer_s: float = 0.0
var _player_periodic_debug_timer_s: float = 0.0
var _landing_debug_timer_s: float = 0.0
var _dogfight_burst_timer_s: float = 0.0
var _dogfight_burst_cooldown_timer_s: float = 0.0
var _dogfight_burst_active: bool = false
var _dogfight_retarget_timer_s: float = 0.0
var _dogfight_weapon_commit_timer_s: float = 0.0
var _dogfight_active_missile: Node3D = null
var _dogfight_variation_timer_s: float = 0.0
var _dogfight_variation_cooldown_timer_s: float = 0.0
var _dogfight_stalemate_timer_s: float = 0.0
var _dogfight_variation_waypoint: Vector3 = Vector3.ZERO
var _dogfight_prev_target_distance_m: float = INF
var _dogfight_recovery_timer_s: float = 0.0
var _dogfight_recovery_waypoint: Vector3 = Vector3.ZERO
var _dogfight_precise_yaw_controller: PIDController
var _dogfight_precise_pitch_controller: PIDController
var _dogfight_lost_sight_behavior: DogfightLostSightBehavior = DogfightLostSightBehavior.EFFICIENT
var _dogfight_lost_sight_timer_s: float = 0.0
var _dogfight_lost_sight_turn_sign: float = 0.0
var _projectile_speed_cap_cached: bool = false
var _projectile_speed_cap_mps: float = INF

# Landing approach
var _landing_phase: int = 0  # 0=to approach_1, 1=to approach_2, thenÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢LANDING state
var _approach_wp: Array = []  # [Node3D approach_1, Node3D approach_2, Node3D approach_3]
var _takeoff_wp: Node3D = null
var _approach_path_along_m: float = 0.0
var _carrot_along_m: float = 0.0  # Rolling carrot progress along approach polyline
var _recovery_phase: int = 0
var _recovery_hold_side: float = 1.0
var _recovery_clearance_granted: bool = false
@export var approach_phase0_alt_above_deck_m: float = 450.0
@export var approach_phase1_alt_above_deck_m: float = 350.0
@export var approach_phase2_alt_above_deck_m: float = 200.0
@export var approach_phase3_alt_above_deck_m: float = 130.0
@export var approach_deck_height_fallback_m: float = 60.0  # Used if approach_4 cannot be read
@export var approach_entry_altitude_m: float = 600.0
@export var approach_post_gate_speed_mps: float = 54.0
@export var approach_post_gate_throttle_cut: float = 0.2
@export var approach_post_gate_min_throttle: float = 0.1
@export var approach_post_gate_slowdown_margin_mps: float = 6.0
@export var approach_phase0_capture_m: float = 100.0
@export var approach_phase1_capture_m: float = 80.0
@export var approach_phase2_capture_m: float = 60.0
@export var approach_phase3_capture_m: float = 40.0
@export var approach_guidance_mode: ApproachGuidanceMode = ApproachGuidanceMode.PATH_FOLLOWER
@export var approach_precision_bank_limit_deg: float = 25.0
@export var approach_precision_bank_gain: float = 1.5
@export var approach_precision_min_bank_deg: float = 2.0
@export var approach_path_far_speed_mps: float = 68.0
@export var approach_path_near_speed_mps: float = 54.0
@export var approach_path_lookahead_time_s: float = 3.0
@export var approach_path_min_lookahead_m: float = 140.0
@export var approach_path_max_lookahead_m: float = 260.0
@export var approach_path_final_switch_buffer_m: float = 0.0
@export var approach_path_entry_vertical_capture_m: float = 180.0
@export var approach_carrot_lookahead_m: float = 200.0
@export var approach_carrot_final_lookahead_m: float = 60.0
@export var approach_carrot_terrain_clearance_m: float = 60.0
@export var approach_carrot_funnel_half_angle_deg: float = 60.0
@export var approach_carrot_funnel_max_dist_m: float = 2200.0
@export var recovery_marshal_behind_m: float = 2000.0
@export var recovery_marshal_alt_above_deck_m: float = 600.0
@export var recovery_hold_lateral_m: float = 450.0
@export var recovery_clearance_request_distance_m: float = 180.0
@export var recovery_gate_capture_m: float = 130.0
@export var recovery_final_gate_capture_m: float = 120.0
@export var recovery_gate_speed_mps: float = 68.0
@export var recovery_final_gate_speed_mps: float = 58.0
@export var recovery_gate_min_terrain_clearance_m: float = 80.0
@export var recovery_mid_gate_behind_m: float = 1600.0
@export var recovery_mid_gate_alt_above_deck_m: float = 300.0
@export var recovery_low_gate_behind_m: float = 1300.0
@export var recovery_low_gate_alt_above_deck_m: float = 160.0
@export var recovery_final_gate_behind_m: float = 1000.0
@export var recovery_final_gate_alt_above_deck_m: float = 120.0
@export var landing_path_lookahead_time_s: float = 2.0
@export var landing_path_min_lookahead_m: float = 35.0
@export var landing_path_max_lookahead_m: float = 120.0
@export var landing_glideslope_deg: float = 5.9  # ideal approach glideslope; carrot tracks this path
@export var landing_moving_carrot_enabled: bool = true
@export var landing_carrot_speed_mps: float = 48.0
@export var landing_carrot_initial_gap_m: float = 300.0
@export var landing_carrot_min_gap_m: float = 45.0
@export var landing_carrot_final_max_gap_m: float = 120.0
@export var landing_carrot_touchdown_gap_m: float = 8.0
@export var landing_carrot_final_max_gap_start_m: float = 650.0
@export var landing_carrot_gap_taper_distance_m: float = 180.0
@export var landing_carrot_min_start_remaining_m: float = 280.0
@export var landing_carrot_vertical_bias_m: float = 1.0
@export var landing_carrot_rollout_m: float = 120.0
@export var landing_use_deck_start_catch_zone: bool = true
@export var landing_deck_start_node_name: String = "deck_start"
@export var landing_aim_wire_number: int = 2
@export var landing_aim_forward_offset_m: float = 4.0
@export_range(0.0, 1.0, 0.05) var landing_catch_zone_target_t: float = 0.5
@export var landing_short_final_bank_distance_m: float = 200.0
@export var landing_short_final_bank_limit_deg: float = 12.0
@export var landing_short_final_min_bank_deg: float = 4.0
@export var landing_touchdown_level_distance_m: float = 110.0
@export var landing_touchdown_bank_limit_deg: float = 8.0
@export var landing_short_final_yaw_gain: float = 2.5
@export var landing_carrier_motion_compensation_enabled: bool = true
@export var landing_carrier_motion_min_speed_mps: float = 1.0
@export var landing_carrier_motion_velocity_smoothing: float = 0.18
@export var landing_carrier_motion_max_speed_mps: float = 20.0
@export var landing_carrier_speed_compensation_scale: float = 1.0
@export var landing_waveoff_check_distance_m: float = 220.0
@export var landing_bolter_past_target_m: float = 25.0
@export var landing_bolter_rejoin_distance_m: float = 180.0
@export var landing_bolter_rejoin_altitude_margin_m: float = 80.0
@export var landing_bolter_target_speed_mps: float = 68.0
@export var landing_bolter_gear_retract_height_m: float = 35.0
@export var landing_bolter_speed_recovery_mps: float = 72.0
@export var landing_bolter_initial_climb_margin_m: float = 80.0
@export var landing_bolter_climb_step_m: float = 35.0
@export var landing_approach_vs_limit_mps: float = 14.0
@export var landing_approach_vs_gain: float = 0.07
@export var landing_approach_pitch_gain: float = 0.07
@export var landing_approach_pitch_rate_damping: float = 0.95
@export var landing_approach_pitch_input_limit: float = 0.42
@export var landing_approach_max_descent_fpa_deg: float = 25.0
@export var landing_approach_max_climb_fpa_deg: float = 15.0
@export var landing_approach_fpa_pitch_gain: float = 2.8
@export var landing_approach_fpa_pitch_rate_damping: float = 1.4
@export var landing_approach_fpa_pitch_input_limit: float = 0.65
@export var landing_approach_fpa_pitch_smoothing: float = 0.6
@export var landing_final_gate_max_high_m: float = 45.0
@export var landing_final_high_waveoff_remaining_m: float = 260.0
@export var landing_final_max_descent_fpa_deg: float = 25.0
@export var landing_final_max_climb_fpa_deg: float = 8.0
@export var landing_final_glide_error_fpa_gain: float = 0.01
@export var landing_final_glide_error_limit_deg: float = 11.0
@export var landing_final_glide_vs_damping_gain: float = 0.024
@export var landing_final_glide_vs_damping_limit_deg: float = 7.0
@export var landing_final_path_waveoff_error_m: float = 25.0
@export var landing_final_path_waveoff_remaining_m: float = 330.0
@export var landing_final_far_damping_start_m: float = 260.0
@export var landing_final_far_damping_end_m: float = 90.0
@export var landing_final_far_correction_scale: float = 0.45
@export var landing_final_low_path_far_correction_scale: float = 1.0
@export var landing_final_fpa_smoothing_far: float = 0.18
@export var landing_final_fpa_smoothing_near: float = 0.55
@export var landing_final_fpa_slew_deg_per_s: float = 8.0
@export var landing_final_lateral_damping_start_m: float = 260.0
@export var landing_final_lateral_damping_end_m: float = 80.0
@export var landing_final_lateral_gain_scale_far: float = 0.55
@export var landing_final_lateral_smoothing_far: float = 0.16
@export var landing_final_lateral_smoothing_near: float = 0.42
@export var landing_final_lateral_slew_deg_per_s: float = 18.0
@export var landing_final_runway_yaw_gain: float = 2.4
@export var landing_final_rudder_lateral_gain: float = 1.12
@export var landing_final_lateral_pd_lookahead_m: float = 130.0
@export var landing_final_lateral_velocity_damping_s: float = 2.0
@export var landing_final_lateral_pd_limit_deg: float = 10.0
@export var landing_final_lateral_bank_gain: float = 0.22
@export var landing_final_lateral_bank_limit_deg: float = 3.0
@export var landing_final_rudder_rate_damping: float = 0.7
@export var landing_final_bank_yaw_mix: float = 0.18
@export var landing_final_rudder_primary_bank_scale: float = 0.35
@export var landing_final_low_path_waveoff_m: float = 6.0
@export var landing_final_low_path_waveoff_remaining_m: float = 125.0
@export var landing_final_low_path_throttle_floor: float = 0.76
@export var landing_final_sink_throttle_floor: float = 0.84
@export var landing_final_pitch_gain: float = 1.65
@export var landing_final_pitch_rate_damping: float = 1.35
@export var landing_final_pitch_input_limit: float = 0.55
@export var landing_final_pitch_smoothing: float = 0.34

# ============================================================================
# CONTROL OUTPUTS - Fed to aircraft control system
# ============================================================================
var pitch_input: float = 0.0    # -1 to 1
var roll_input: float = 0.0     # -1 to 1
var yaw_input: float = 0.0      # -1 to 1
var throttle_input: float = 0.5 # 0 to 1

# ============================================================================
# AI PARAMETERS
# ============================================================================
@export var skill: AIPilotSkill = AIPilotSkill.EXPERIENCED
@export var rtb_health_threshold: float = 0.3  # Return to base below this health %
@export var rtb_fuel_threshold: float = 0.2    # Return to base below this fuel %
@export var debug_enabled: bool = true
@export var show_waypoint_markers: bool = false  # Show green pillar markers at nav waypoints
@export var verbose_debug_enabled: bool = false  # Extra non-attack telemetry spam
@export var bomb_debug_markers_enabled: bool = true
@export var bomb_debug_print_enabled: bool = true
@export var bomb_debug_print_interval_s: float = 0.5
@export var bomb_debug_marker_height_m: float = 350.0
@export var bomb_debug_line_thickness_m: float = 3.0
@export var landing_debug_print_enabled: bool = true
@export var landing_debug_print_interval_s: float = 0.5
@export var ai_checkin_enabled: bool = false     # Periodic combat status checkin
@export var ai_checkin_interval_s: float = 4.0  # Seconds between checkins
@export var cap_route_debug_enabled: bool = true
@export var cap_route_debug_interval_s: float = 1.0
@export var cap_route_debug_progress_epsilon_m: float = 8.0
@export var cap_route_debug_stuck_time_s: float = 4.0
@export var flight_path_alignment_debug_enabled: bool = true
@export var flight_path_alignment_debug_interval_s: float = 2.5
@export var flight_path_alignment_debug_min_speed_mps: float = 25.0
@export var player_control_debug_passthrough_enabled: bool = true

# Flight limits
@export var max_pitch_angle: float = deg_to_rad(30.0)  # Maximum pitch up/down
@export var max_roll_angle: float = deg_to_rad(30.0)   # Maximum roll left/right

# Navigation
var waypoint_threshold: float = 50.0  # Distance to consider waypoint reached
@export var on_station_radius_m: float = 400.0  # Arrival radius for TRANSIT rally point
var _committed_turn_sign: float = 0.0  # Locks turn direction when target is behind
var waypoints: Array[Vector3] = []
var current_waypoint_index: int = 0
var waypoints_follow_carrier: bool = false
var carrier_position: Vector3 = Vector3.ZERO  # Home carrier position

# Launch safety
var launch_position: Vector3 = Vector3.ZERO
var deck_clearance_distance: float = 300.0  # Distance from launch point to start climbing
var land_after_launch: bool = false         # If true, start landing approach once climb completes
var _land_after_climb: bool = false         # Set internally when land_after_launch triggers climb
@export var launch_pullup_pitch_input: float = 0.45   # Pull-up authority after catapult launch
@export var launch_min_climb_rate_mps: float = 8.0   # Keep pulling until this vertical speed
@export var launch_target_pitch_deg: float = 20.0
@export var launch_soft_pitch_limit_deg: float = 28.0
@export var launch_hard_pitch_limit_deg: float = 35.0
@export var climb_aggressive_pitch_input: float = 0.75  # Strong climb command after deck clear
@export var climb_aggressive_alt_margin_m: float = 120.0  # Stay aggressive until near climb target
@export var climb_max_pitch_deg: float = 30.0
@export var climb_vs_limit_mps: float = 14.0

# Waypoint marker (visual)
var _waypoint_marker: MeshInstance3D = null
var _cap_route_debug_last_index: int = -1
var _cap_route_debug_last_waypoint_count: int = 0
var _flight_path_alignment_debug_timer_s: float = 0.0
var _cap_route_debug_last_distance_m: float = INF
var _cap_route_debug_timer_s: float = 0.0
var _cap_route_debug_no_progress_s: float = 0.0
var _passive_debug_only: bool = false
var _ai_checkin_timer: float = 0.0
var _bomb_debug_nodes: Dictionary = {}
var _bomb_debug_print_timer_s: float = 0.0

# Health monitoring
var max_health: float = 100.0
var current_health: float = 100.0

# =========================================================================
# TUNING PARAMS (AI-side, independent of aircraft modules)
# =========================================================================
@export var patrol_altitude_m: float = 300.0
@export var figure_eight_radius_m: float = 600.0
@export var bank_cmd_limit_deg: float = 60.0
@export var attack_bank_cmd_limit_deg: float = 75.0  # Extra bank authority while attacking
@export var bank_limit_when_low_deg: float = 25.0
@export var climb_rate_limit_mps: float = 12.0
@export var descend_rate_limit_mps: float = 10.0
@export var stall_speed_mps: float = 40.0
@export var stall_margin_mps: float = 8.0
@export var throttle_bank_gain: float = 0.35
@export var flight_path_angle_limit_deg: float = 45.0

# Dynamic navigation target (updates several times per second)
@export var nav_update_hz: float = 6.0
var _nav_update_accum: float = 0.0
var nav_target: Node3D = null

# Control sign mapping (to match aircraft module expectations)
# Player ControlSteering negates roll before SimpleAero; AI must match.
@export var invert_pitch_sign: bool = false
@export var invert_roll_sign: bool = true
@export var invert_yaw_sign: bool = false
## If plane turns wrong way toward waypoints, enable to flip roll direction
@export var flip_roll_direction: bool = true
## Smooth control inputs (0=no smoothing, 1=instant). Higher = more decisive response
@export var input_smoothing: float = 0.75
@export var pitch_input_smoothing: float = 0.5
@export var pitch_deadband_m: float = 20.0  # Ignore tiny altitude errors to avoid constant porpoising
@export var normal_flight_vs_limit_mps: float = 8.0
@export var normal_flight_vs_gain: float = 0.055
@export var normal_flight_pitch_gain: float = 0.065
@export var normal_flight_pitch_rate_damping: float = 0.95
@export var normal_flight_pitch_input_limit: float = 0.35
@export var normal_flight_pitch_smoothing: float = 0.32
@export var high_bank_start_ratio: float = 0.75  # Start extra damping above this % of bank limit
@export var high_bank_roll_damping_gain: float = 0.45  # Extra roll-rate damping near max bank
@export var high_bank_yaw_scale: float = 0.7  # Reduce rudder at high bank to avoid waggle
@export var precision_point_pitch_gain: float = 5.0
@export var precision_point_yaw_gain: float = 2.8
@export var precision_point_roll_response: float = 0.38
@export var precision_point_pitch_response: float = 0.22
@export var precision_point_yaw_response: float = 0.32
@export var dogfight_precision_bank_gain: float = 7.0
@export var dogfight_precision_min_bank_deg: float = 8.0
@export var dogfight_precision_direct_pitch_gain: float = 26.0
@export var dogfight_precision_direct_yaw_gain: float = 14.0
@export var dogfight_precision_pid_scale: float = 0.55

var _smoothed_roll_input: float = 0.0
var _smoothed_pitch_input: float = 0.0
var _smoothed_yaw_input: float = 0.0
var _smoothed_fpa_pitch: float = 0.0  # FPA controller's own smoother state; kept separate from VS controller to prevent cross-contamination oscillation
var _landing_smoothed_desired_fpa: float = NAN
var _landing_smoothed_bearing_error: float = NAN
var _landing_smoothed_runway_heading_error: float = NAN
var _ma_escape_complete: bool = false  # True once wings-level escape climb finishes; gates Phase 2 navigation
var _bolter_go_around: bool = false   # True while carrot is guiding the climb-out after a bolter
var _bolter_dir: Vector3 = Vector3.ZERO  # Flat forward direction at the moment of bolter detection
var _landing_carrot_active: bool = false
var _landing_carrot_remaining_m: float = INF
var _landing_measured_carrier_velocity: Vector3 = Vector3.ZERO
var _landing_carrier_motion_last_ref: Vector3 = Vector3.ZERO
var _landing_carrier_motion_has_ref: bool = false
var _land_snap_400_done: bool = false
var _land_snap_200_done: bool = false
var _land_snap_100_done: bool = false
var _land_snap_touch_done: bool = false

# Arrest debug
var _arrest_engaged_prev: bool = false  # Detect wire-catch transition
var _arrest_debug_timer: float = 0.0    # Accumulates time since last print
var _arrest_debug_interval: float = 0.1 # Print 10ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â/s
var _arrest_prev_vel: Vector3 = Vector3.ZERO
var _arrest_start_pos: Vector3 = Vector3.ZERO
var _arrest_stopped_reported: bool = false

func apply_origin_shift(offset: Vector3) -> void:
	target_waypoint -= offset
	formation_anchor -= offset
	nav_waypoint -= offset
	maneuver_waypoint -= offset
	launch_position -= offset
	carrier_position -= offset
	_dogfight_variation_waypoint -= offset
	_dogfight_recovery_waypoint -= offset
	if _landing_carrier_motion_has_ref:
		_landing_carrier_motion_last_ref -= offset
	for i in range(waypoints.size()):
		waypoints[i] -= offset

func _ready():
	add_to_group("origin_shifter")
	# Initialize PID controllers with tuned values
	# These values will need adjustment based on aircraft flight characteristics

	# Altitude: gentle with a touch of integral to remove steady-state bias
	altitude_controller = PIDController.new(0.008, 0.002, 0.01)

	# Heading: Gentle response
	heading_controller = PIDController.new(0.3, 0.0, 0.1)

	# Speed: Slow response
	speed_controller = PIDController.new(0.05, 0.001, 0.01)

	# Pitch: Very gentle control to prevent loops and oscillation
	pitch_controller = PIDController.new(0.5, 0.0, 0.3)
	_dogfight_precise_yaw_controller = PIDController.new(8.0, 2.5, 0.10)
	_dogfight_precise_yaw_controller.integral_limit = 1.5
	_dogfight_precise_pitch_controller = PIDController.new(7.5, 2.2, 0.08)
	_dogfight_precise_pitch_controller.integral_limit = 1.5

	set_physics_process(false)  # Don't start until initialized
	apply_skill_preset()

func apply_skill_preset() -> void:
	match skill:
		AIPilotSkill.ROOKIE:
			dogfight_precision_direct_pitch_gain = 10.0
			dogfight_precision_direct_yaw_gain   = 6.0
			dogfight_precision_pid_scale         = 0.15
			dogfight_min_hit_chance              = 0.50
			dogfight_fire_precise_min_blend      = 0.65
			dogfight_fire_burst_s                = 0.35
			dogfight_burst_cooldown_s            = 0.40
			dogfight_missile_use_chance          = 0.25
			dogfight_corner_speed_mps            = 78.0
			dogfight_retarget_interval_s         = 1.2
		AIPilotSkill.EXPERIENCED:
			dogfight_precision_direct_pitch_gain = 26.0
			dogfight_precision_direct_yaw_gain   = 14.0
			dogfight_precision_pid_scale         = 0.55
			dogfight_min_hit_chance              = 0.72
			dogfight_fire_precise_min_blend      = 0.90
			dogfight_fire_burst_s                = 0.55
			dogfight_burst_cooldown_s            = 0.22
			dogfight_missile_use_chance          = 0.55
			dogfight_corner_speed_mps            = 85.0
			dogfight_retarget_interval_s         = 0.5
		AIPilotSkill.VETERAN:
			dogfight_precision_direct_pitch_gain = 32.0
			dogfight_precision_direct_yaw_gain   = 18.0
			dogfight_precision_pid_scale         = 0.70
			dogfight_min_hit_chance              = 0.85
			dogfight_fire_precise_min_blend      = 0.95
			dogfight_fire_burst_s                = 0.70
			dogfight_burst_cooldown_s            = 0.14
			dogfight_missile_use_chance          = 0.75
			dogfight_corner_speed_mps            = 92.0
			dogfight_retarget_interval_s         = 0.25
		AIPilotSkill.ACE:
			dogfight_precision_direct_pitch_gain = 36.0
			dogfight_precision_direct_yaw_gain   = 22.0
			dogfight_precision_pid_scale         = 0.80
			dogfight_min_hit_chance              = 0.90
			dogfight_fire_precise_min_blend      = 0.98
			dogfight_fire_burst_s                = 0.75
			dogfight_burst_cooldown_s            = 0.10
			dogfight_missile_use_chance          = 0.80
			dogfight_corner_speed_mps            = 95.0
			dogfight_retarget_interval_s         = 0.20


func _get_dogfight_max_upward_aim_deg() -> float:
	match skill:
		AIPilotSkill.ROOKIE:
			return 25.0
		AIPilotSkill.EXPERIENCED, AIPilotSkill.VETERAN:
			return 35.0
		AIPilotSkill.ACE:
			return 45.0
	return 35.0


func _dogfight_should_bypass_upward_aim_clamp() -> bool:
	# Terrain/collision safety always has authority over dogfight style limits.
	if _safety_override_active:
		return true
	if not aircraft or not is_instance_valid(aircraft):
		return false
	if terrain_ahead_distance >= INF:
		return false
	var speed_mps: float = maxf(aircraft.linear_velocity.length(), 10.0)
	var tti_s: float = terrain_ahead_distance / speed_mps
	return tti_s <= maxf(emergency_tti_s, 2.5)


func _clamp_dogfight_upward_aim_point(origin: Vector3, target_point: Vector3) -> Vector3:
	# Clamp only upward aim angle relative to world horizon (global horizontal plane).
	# This is not relative to aircraft attitude; downward aim (dives) remains unrestricted.
	if _dogfight_should_bypass_upward_aim_clamp():
		return target_point
	var max_up_deg: float = _get_dogfight_max_upward_aim_deg()
	if max_up_deg == INF:
		return target_point

	var to_target: Vector3 = target_point - origin
	if to_target.y <= 0.0:
		return target_point

	var horiz_len: float = Vector2(to_target.x, to_target.z).length()
	var reference_horiz_len: float = maxf(horiz_len, 1.0)
	var max_up_y: float = tan(deg_to_rad(max_up_deg)) * reference_horiz_len
	if to_target.y <= max_up_y:
		return target_point

	to_target.y = max_up_y
	return origin + to_target


func initialize(aircraft_node: RigidBody3D):
	"""Setup AI pilot with aircraft reference"""
	aircraft = aircraft_node
	_passive_debug_only = false
	_flight_path_alignment_debug_timer_s = 0.0

	# Team-driven contact groups used by sensor scans.
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

	# Find control modules
	control_engine = _find_module(aircraft, "ControlEngine")
	simple_aero = _find_module(aircraft, "SimpleAero")
	engine = _find_module(aircraft, "Engine")
	control_gear = _find_module(aircraft, "ControlLandingGear")
	control_weapons = _find_module(aircraft, "ControlWeapons")
	if not control_weapons:
		control_weapons = _find_module(aircraft, "control_weapons")
	if not control_weapons:
		control_weapons = aircraft.find_child("ControlWeapons", true, false)
	control_targeting_aam = aircraft.find_child("ControlTargeting_AAM", true, false)

	if not control_engine or not simple_aero:
		push_error("[AIPilot] Failed to find required control modules!")
		return

	if aircraft.has_signal("destroyed") and not aircraft.is_connected("destroyed", _on_aircraft_destroyed):
		aircraft.connect("destroyed", _on_aircraft_destroyed)

	# Disable stability (auto-levels aircraft, fights AI's intentional banking)
	# and auto_rudder (AI manages yaw explicitly based on desired bank angle).
	if simple_aero:
		if not _ai_control_overrides_applied and "stability_strength" in simple_aero:
			_saved_stability_strength = simple_aero.stability_strength
		if not _ai_control_overrides_applied and "auto_rudder_strength" in simple_aero:
			_saved_auto_rudder_strength = simple_aero.auto_rudder_strength
		if "stability_strength" in simple_aero:
			simple_aero.stability_strength = 0.0
		if "auto_rudder_strength" in simple_aero:
			simple_aero.auto_rudder_strength = 0.0
		_ai_control_overrides_applied = true
		if debug_enabled and verbose_debug_enabled:
			print("[AIPilot] Disabled stability and auto_rudder for AI control")

	# Get initial health if aircraft has it
	if aircraft.has_meta("max_health"):
		max_health = aircraft.get_meta("max_health")
		current_health = max_health

	if debug_enabled and verbose_debug_enabled:
		print("[AIPilot] Initialized for aircraft: ", aircraft.name)

	# Ensure a dynamic navigation target exists
	nav_target = get_node_or_null("NavTarget") as Node3D
	if not nav_target:
		nav_target = Node3D.new()
		nav_target.name = "NavTarget"
		add_child(nav_target)
		nav_target.global_position = aircraft.global_position
		if debug_enabled and verbose_debug_enabled:
			print("[AIPilot] Created NavTarget node")

	# Create waypoint marker: lime green box 1x1m footprint, 1000m tall
	if show_waypoint_markers:
		_create_waypoint_marker()

	set_physics_process(true)

func deinitialize():
	"""Restore SimpleAero settings when AI is disabled"""
	if simple_aero:
		if _saved_stability_strength >= 0.0 and "stability_strength" in simple_aero:
			simple_aero.stability_strength = _saved_stability_strength
		if _saved_auto_rudder_strength >= 0.0 and "auto_rudder_strength" in simple_aero:
			simple_aero.auto_rudder_strength = _saved_auto_rudder_strength
		_ai_control_overrides_applied = false
		if "roll_input" in simple_aero:
			simple_aero.roll_input = 0.0
		if "pitch_input" in simple_aero:
			simple_aero.pitch_input = 0.0
		if "yaw_input" in simple_aero:
			simple_aero.yaw_input = 0.0
		_saved_stability_strength = -1.0
		_saved_auto_rudder_strength = -1.0
		if debug_enabled and verbose_debug_enabled:
			print("[AIPilot] Restored stability and auto_rudder for player control")
	if _waypoint_marker and is_instance_valid(_waypoint_marker):
		_waypoint_marker.queue_free()
		_waypoint_marker = null
	_clear_bomb_debug_visuals()
	_flight_path_alignment_debug_timer_s = 0.0
	_passive_debug_only = player_control_debug_passthrough_enabled and debug_enabled
	set_physics_process(_passive_debug_only)

func _physics_process(delta: float):
	if not aircraft or not is_instance_valid(aircraft):
		if _waypoint_marker and is_instance_valid(_waypoint_marker):
			_waypoint_marker.queue_free()
			_waypoint_marker = null
		return

	# Yield control to FlightDeckManager / catapult during deck sequences.
	# Do NOT call _apply_controls() here ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â the catapult owns the engine and
	# set_target_power(0) would trigger engine_stop(), killing the spool-up.
	if aircraft.get_meta("controls_disabled", false):
		return

	_update_landing_carrier_motion_estimate(delta)

	# Update sensors - AI's view of the world
	_update_sensors(delta)

	if _passive_debug_only:
		_emit_player_debug_telemetry(delta)
		return

	# Update health and fuel monitoring for RTB. This walks aircraft resource state,
	# so keep it low-frequency and skip it entirely for pilots with RTB disabled.
	if _should_run_rtb_check(delta):
		_check_rtb_triggers()

	# === HIERARCHY OF NEEDS ===
	# 1. Don't fly into terrain (highest priority)
	# 2. Don't fly into other aircraft
	# 3. Do whatever the state machine says
	_safety_override_active = false
	if _check_terrain_avoidance(delta):
		_safety_override_active = true
	elif _should_run_collision_avoidance(delta) and _check_collision_avoidance(delta):
		_safety_override_active = true

	if not _safety_override_active:
		# State machine â€” only runs when safety is not overriding
		match current_state:
			State.IDLE:
				_state_idle(delta)
			State.LAUNCHING:
				_state_launching(delta)
			State.CLIMBING:
				_state_climbing(delta)
			State.TRANSIT:
				_state_transit(delta)
			State.SEARCH:
				_state_search(delta)
			State.ATTACK_POSITIONING:
				_state_attack_positioning(delta)
			State.ATTACK_INBOUND:
				_state_attack_inbound(delta)
			State.ATTACK_DIVE:
				_state_attack_dive(delta)
			State.ATTACK_BREAK_OFF:
				_state_attack_break_off(delta)
			State.DOGFIGHT:
				_state_dogfight(delta)
			State.ENGAGE:
				_state_engage(delta)
			State.RTB:
				_state_rtb(delta)
			State.RECOVERY_MARSHAL:
				_state_recovery_marshal(delta)
			State.RECOVERY_HOLD:
				_state_recovery_hold(delta)
			State.RECOVERY_APPROACH:
				_state_recovery_approach(delta)
			State.APPROACH:
				_state_approach(delta)
			State.LANDING:
				_state_landing(delta)
			State.MISSED_APPROACH:
				_state_missed_approach(delta)

	_emit_periodic_ai_debug(delta)

	_debug_flight_path_alignment(delta)
	_update_ai_checkin(delta)

	# Update waypoint marker position
	_update_waypoint_marker()

	# Apply computed control inputs to aircraft
	_apply_controls()

# ============================================================================
# DEBUG HELPERS
# ============================================================================

func _is_attack_debug_state(state_value: int = -1) -> bool:
	var effective_state: int = current_state if state_value < 0 else state_value
	return effective_state in [
		State.ATTACK_POSITIONING,
		State.ATTACK_INBOUND,
		State.ATTACK_DIVE,
		State.ATTACK_BREAK_OFF
	]

func _get_debug_summary_interval_s(state_value: int = -1) -> float:
	return attack_debug_summary_interval_s if _is_attack_debug_state(state_value) else general_debug_summary_interval_s

func _emit_periodic_ai_debug(delta: float) -> void:
	if not debug_enabled or aircraft == null:
		return
	_periodic_debug_timer_s -= delta
	if _periodic_debug_timer_s > 0.0:
		return
	_periodic_debug_timer_s = maxf(_get_debug_summary_interval_s(), 0.25)

	var spd: float = aircraft.linear_velocity.length()
	var pos: Vector3 = aircraft.global_position
	var vs: float = aircraft.linear_velocity.y
	var pitch_deg: float = rad_to_deg(_get_forward_pitch_rad())
	var h_spd: float = Vector2(aircraft.linear_velocity.x, aircraft.linear_velocity.z).length()
	var fpa_deg: float = rad_to_deg(atan2(-aircraft.linear_velocity.y, max(h_spd, 1.0)))
	var state_name: String = State.keys()[current_state]
	var target_name: String = combat_target.name if combat_target and is_instance_valid(combat_target) else "-"
	var target_range: float = aircraft.global_position.distance_to(combat_target.global_position) if combat_target and is_instance_valid(combat_target) else -1.0
	var safety_str: String = " safety=ON" if _safety_override_active else ""
	var weapon_str: String = ""
	if _is_attack_debug_state():
		weapon_str = " weapon=%s" % _run_weapon_type
		if _run_weapon_type == "Bomb":
			weapon_str += " bombs=%d/%d" % [_bombs_dropped_this_run, _bombs_to_drop_this_run]
		elif _run_weapon_type == "Rocket Pod":
			weapon_str += " rockets=%d/%d" % [_rockets_fired_this_run, _rockets_to_fire_this_run]
		if _prev_ccip_miss < INF:
			weapon_str += " ccip_miss=%.0fm" % _prev_ccip_miss

	print("[AIPilot STATUS] %s state=%s%s%s pos=(%.0f,%.0f,%.0f) AGL=%.0f spd=%.1f VS=%.1f pitch=%.1fdeg fpa=%.1fdeg target=%s range=%.0f" % [
		aircraft.name,
		state_name,
		safety_str,
		weapon_str,
		pos.x,
		pos.y,
		pos.z,
		altitude_agl,
		spd,
		vs,
		pitch_deg,
		fpa_deg,
		target_name,
		target_range
	])

func _landing_debug_enabled() -> bool:
	return debug_enabled and landing_debug_print_enabled

func _landing_phase_name(phase: int) -> String:
	match phase:
		0:
			return "entry"
		1:
			return "gate0"
		2:
			return "approach1"
		3:
			return "approach2"
		4:
			return "approach3"
		_:
			return "phase%d" % phase

func _landing_debug_event(message: String) -> void:
	if not _landing_debug_enabled():
		return
	var aircraft_name: String = aircraft.name if aircraft and is_instance_valid(aircraft) else "AI"
	print("[LAND] %s %s" % [aircraft_name, message])

func _on_aircraft_destroyed() -> void:
	if current_state in [State.RECOVERY_MARSHAL, State.RECOVERY_HOLD, State.RECOVERY_APPROACH, State.LANDING, State.MISSED_APPROACH]:
		_release_landing_clearance_from_deck()
	if current_state == State.LANDING:
		_landing_snap("CRASH", "destroyed=true  pts=0.0")

func _record_landing_test_failure(label: String) -> void:
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm and fdm.has_method("record_landing_test_outcome"):
		fdm.record_landing_test_outcome(aircraft, label, 0.0)

func _landing_snap(label: String, extra: String = "") -> void:
	if label in ["BOLTER", "WAVE-OFF", "CRASH", "DESTROYED"] and is_instance_valid(aircraft):
		_record_landing_test_failure(label)
	if not _landing_debug_enabled() or not is_instance_valid(aircraft):
		return
	var pos: Vector3 = aircraft.global_position
	var vel: Vector3 = aircraft.linear_velocity
	var spd: float = vel.length()
	var hspd: float = Vector2(vel.x, vel.z).length()
	var deck_y: float = _get_approach_deck_y()
	var alt_m: float = pos.y - deck_y
	var fpa_deg: float = rad_to_deg(atan2(-vel.y, maxf(hspd, 1.0)))
	var basis: Basis = aircraft.global_transform.basis
	var pitch_deg: float = rad_to_deg(asin(clamp(basis.z.y, -1.0, 1.0)))
	var hdg_deg: float = fmod(rad_to_deg(atan2(basis.z.x, basis.z.z)) + 360.0, 360.0)
	var bank_deg: float = rad_to_deg(atan2(basis.x.y, basis.y.y))
	var gear_str: String = "?" if not is_instance_valid(control_gear) \
							else ("D" if bool(control_gear.get("gear_down_state")) else "U")
	var line: String = "[LAND] %-24s  %-10s  spd=%3.0f  alt=%4.0fm  vs=%+5.1f  fpa=%+5.1f°  hdg=%3.0f°  pitch=%+5.1f°  bank=%+5.1f°  gear=%s" % [
		aircraft.name, label, spd, alt_m, vel.y, fpa_deg, hdg_deg, pitch_deg, bank_deg, gear_str
	]
	var track: Dictionary = _landing_track_error(pos)
	if bool(track.get("valid", false)):
		line += "  rem=%4.0fm  trk_lat=%+5.1fm  trk_v=%+5.1fm  trk_err=%4.1fm" % [
			float(track.get("remaining_m", 0.0)),
			float(track.get("lateral_m", 0.0)),
			float(track.get("vertical_m", 0.0)),
			float(track.get("track_error_m", 0.0))
		]
	if extra != "":
		line += "  " + extra
	print(line)

func _landing_debug_tick(delta: float, label: String, target_pos: Vector3, extra: String = "") -> void:
	if not _landing_debug_enabled() or aircraft == null:
		return
	_landing_debug_timer_s -= delta
	if _landing_debug_timer_s > 0.0:
		return
	_landing_debug_timer_s = maxf(landing_debug_print_interval_s, 0.1)

	var pos: Vector3 = aircraft.global_position
	var vel: Vector3 = aircraft.linear_velocity
	var to_target: Vector3 = target_pos - pos
	var hdist: float = Vector2(to_target.x, to_target.z).length()
	var speed: float = vel.length()
	var hspeed: float = Vector2(vel.x, vel.z).length()
	var fpa_deg: float = rad_to_deg(atan2(-vel.y, maxf(hspeed, 1.0)))
	var target_fpa_deg: float = rad_to_deg(atan2(-to_target.y, maxf(hdist, 1.0)))
	var basis: Basis = aircraft.global_transform.basis
	var pitch_deg: float = rad_to_deg(_get_forward_pitch_rad())
	var bank_deg: float = rad_to_deg(atan2(basis.x.y, basis.y.y))
	var deck_y: float = _get_approach_deck_y()
	var own_deck_alt_m: float = pos.y - deck_y
	var target_deck_alt_m: float = target_pos.y - deck_y
	var gear_str: String = "?"
	if is_instance_valid(control_gear):
		gear_str = "down" if bool(control_gear.get("gear_down_state")) else "up"
	var arrest_str: String = "true" if aircraft.get_meta("arresting_engaged", false) else "false"
	var extra_str: String = ""
	if extra != "":
		extra_str = " " + extra

	print("[AIPilot LANDDBG] %s %s state=%s phase=%s hdist=%.0fm alt_err=%.1fm own_deck_alt=%.0fm target_deck_alt=%.0fm spd=%.1f target_spd=%.1f vs=%.1f fpa=%.1fdeg cmd_fpa=%.1fdeg pitch=%.1fdeg bank=%.1fdeg pitch_in=%.2f thr=%.2f gear=%s arrest=%s target=(%.0f,%.0f,%.0f)%s" % [
		aircraft.name,
		label,
		State.keys()[current_state],
		_landing_phase_name(_landing_phase),
		hdist,
		to_target.y,
		own_deck_alt_m,
		target_deck_alt_m,
		speed,
		_get_effective_target_speed(),
		vel.y,
		fpa_deg,
		target_fpa_deg,
		pitch_deg,
		bank_deg,
		pitch_input,
		throttle_input,
		gear_str,
		arrest_str,
		target_pos.x,
		target_pos.y,
		target_pos.z,
		extra_str
	])

# ============================================================================
# STATE HANDLERS
# ============================================================================

func _state_idle(delta: float):
	"""Waiting on deck"""
	# Do nothing, waiting for launch
	pass

func _state_launching(delta: float):
	"""In catapult sequence"""
	# Maintain near-level flight ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â gentle pitch-up keeps us from descending into the water
	# while we clear the deck, but avoid aggressive pull-up at catapult speed.
	# Pull hard until we have a healthy climb rate; taper slightly once climbing
	# but never drop below a minimum to prevent terrain impact after catapult.
	var current_pitch_deg := rad_to_deg(_get_forward_pitch_rad())
	var base_pitch_input: float = launch_pullup_pitch_input if aircraft.linear_velocity.y < launch_min_climb_rate_mps else maxf(launch_pullup_pitch_input * 0.65, 0.16)
	var pitch_soft_t := clampf(
		(launch_soft_pitch_limit_deg - current_pitch_deg) / maxf(launch_soft_pitch_limit_deg - launch_target_pitch_deg, 1.0),
		0.0,
		1.0
	)
	pitch_input = lerpf(-0.16, base_pitch_input, pitch_soft_t)
	if current_pitch_deg >= launch_hard_pitch_limit_deg:
		pitch_input = minf(pitch_input, -0.18)
	_smoothed_pitch_input = pitch_input
	roll_input = 0.0
	yaw_input = 0.0
	throttle_input = 1.0  # Full throttle

	# Don't climb-state until distance AND AGL are both safe â€” low-AGL turns kill.
	if _is_airborne():
		var distance_from_launch = aircraft.global_position.distance_to(launch_position)
		if distance_from_launch > deck_clearance_distance and altitude_agl > 60.0:
			var current_heading = atan2(aircraft.global_transform.basis.z.x, aircraft.global_transform.basis.z.z)
			target_heading = current_heading
			if land_after_launch:
				land_after_launch = false
				_land_after_climb = true
				print("[AIPilot] Clear of deck ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â climbing to pattern altitude before approach")
			else:
				if debug_enabled and verbose_debug_enabled:
					print("[AIPilot] Clear of deck (", distance_from_launch, "m), starting climb")
			change_state(State.CLIMBING)
		elif debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 60 == 0:
			print("[AIPilot LAUNCH] Airborne but maintaining level flight. Distance from launch: ", distance_from_launch, "m")

func _state_climbing(delta: float):
	"""Climb to pattern altitude after launch"""
	target_speed = 85.0
	var current_pitch_deg := rad_to_deg(_get_forward_pitch_rad())

	# Retract gear and flaps once airborne
	if _is_airborne() and is_instance_valid(control_gear):
		_stow_landing_config()

	# Fixed climb waypoint: 600 m ahead of the carrier along the launch heading, 200 m above it.
	# Computed from fixed inputs (carrier_position, target_heading) so it is the same 3D
	# point every frame ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â the aircraft can actually reach and clear it.
	# Waypoint anchored to aircraft's OWN position, not the carrier's â€” the carrier
	# turns and its position drifts sideways relative to the launch track, which
	# causes navigation to command a bank to chase it. Pointing 2000 m straight
	# ahead in the fixed launch heading keeps the heading error near zero.
	# Y: 600 m above carrier deck so the aircraft climbs well clear before patrolling.
	_refresh_carrier_position(false)
	_ensure_carrier_position()
	var launch_fwd := Vector3(sin(target_heading), 0.0, cos(target_heading))
	nav_waypoint = aircraft.global_position + launch_fwd * 2000.0
	nav_waypoint.y = carrier_position.y + 600.0

	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)

	# Speed-aware pitch limit: scale climb aggression down when slow to avoid stalls.
	# Below stall+margin we suppress pitch entirely and let speed build.
	var cur_speed := aircraft.linear_velocity.length()
	var safe_speed := stall_speed_mps + stall_margin_mps  # ~48 m/s default
	if aircraft.global_position.y < nav_waypoint.y - climb_aggressive_alt_margin_m:
		var speed_factor := clampf((cur_speed - safe_speed) / 30.0, 0.0, 1.0)
		var max_pitch := lerpf(0.1, climb_aggressive_pitch_input * 0.5, speed_factor)
		pitch_input = minf(pitch_input, max_pitch)
		throttle_input = 1.0
	var climb_pitch_soft_t := clampf((climb_max_pitch_deg - current_pitch_deg) / 8.0, 0.0, 1.0)
	var climb_pitch_cap := lerpf(-0.12, climb_aggressive_pitch_input * 0.35, climb_pitch_soft_t)
	pitch_input = minf(pitch_input, climb_pitch_cap)
	if current_pitch_deg >= climb_max_pitch_deg + 4.0:
		pitch_input = minf(pitch_input, -0.16)
	_smoothed_pitch_input = pitch_input

	# No banking below 150m AGL â€” turns at low altitude after launch are fatal.
	# Taper bank in gradually between 150 m and 300 m AGL.
	var bank_agl_limit := clampf((altitude_agl - 150.0) / 150.0, 0.0, 1.0) * 0.3
	roll_input = clamp(roll_input, -bank_agl_limit, bank_agl_limit)

	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 60 == 0:
		print("[AIPilot CLIMB] Alt: ", snapped(aircraft.global_position.y, 1.0),
			  " Target: ", snapped(nav_waypoint.y, 1.0), " Dist: ",
			  snapped(aircraft.global_position.distance_to(nav_waypoint), 1.0))

	# Transition once we reach the target altitude
	if aircraft.global_position.y >= nav_waypoint.y - 20.0:
		if _land_after_climb:
			_land_after_climb = false
			print("[AIPilot] Climb waypoint cleared ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â starting landing approach")
			start_landing()
		elif waypoints.size() > 0:
			change_state(State.TRANSIT)
		else:
			set_patrol_altitude(nav_waypoint.y)
			print("[AIPilot] Climb altitude reached â€” entering patrol")
			change_state(State.SEARCH)

func _state_transit(delta: float):
	"""Flying to a specific nav_waypoint (e.g. FlightOps rally point).
	Notifies flight_ops_ref when on station, then enters patrol."""
	target_speed = 80.0

	if formation_anchor_active:
		nav_waypoint = formation_anchor
		target_altitude = nav_waypoint.y
		_update_maneuver_waypoint()
		_navigate_to_waypoint(delta)
		return

	# Maintain altitude and navigate toward nav_waypoint
	target_altitude = nav_waypoint.y
	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)

	var dist := aircraft.global_position.distance_to(nav_waypoint)
	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 60 == 0:
		print("[AIPilot TRANSIT] dist_to_rally=", snappedf(dist, 1.0), "m")

	if dist < on_station_radius_m:
		change_state(State.SEARCH)

func _state_search(delta: float):
	"""Looking for targets - fly rectangular patrol pattern around carrier"""
	# Carrier-centered patrols should stay synced to patrol altitude, but
	# externally authored routes may carry their own per-waypoint altitudes.
	var should_sync_patrol_altitude := waypoints_follow_carrier or waypoints.is_empty()
	if should_sync_patrol_altitude and target_altitude != patrol_altitude_m:
		set_patrol_altitude(patrol_altitude_m)
	# Speed policy for patrol
	target_speed = 80.0

	if formation_anchor_active:
		_reset_cap_route_debug()
		nav_waypoint = formation_anchor
		_update_maneuver_waypoint()
		_navigate_to_waypoint(delta)
		if _evaluate_combat_objective():
			return
		return

	# Ensure we have a valid patrol center
	_refresh_carrier_position(waypoints_follow_carrier)
	_ensure_carrier_position()

	# Set up patrol waypoints if not already done
	if waypoints.is_empty():
		_setup_patrol_waypoints()

	# Set navigation waypoint to current patrol waypoint
	if waypoints.size() > 0:
		nav_waypoint = waypoints[current_waypoint_index]
		
		# Update maneuvering waypoint to lead toward navigation waypoint
		_update_maneuver_waypoint()
		
		# Navigate using maneuvering waypoint
		_navigate_to_waypoint(delta)

		# Check if reached waypoint (within 100m)
		var distance_to_waypoint = aircraft.global_position.distance_to(nav_waypoint)
		_debug_cap_route_following(delta, distance_to_waypoint)
		if distance_to_waypoint < 100.0:
			var reached_index: int = current_waypoint_index
			# Move to next waypoint
			current_waypoint_index += 1
			if current_waypoint_index >= waypoints.size():
				current_waypoint_index = 0

			if debug_enabled and verbose_debug_enabled:
				print("[AIPilot SEARCH] Reached waypoint ", current_waypoint_index, "/", waypoints.size())
			if _is_debugging_custom_cap_route():
				print("[AIPilot CAPDBG %s] reached wp %d/%d (dist=%.0fm) -> next %d/%d" % [
					aircraft.name,
					reached_index + 1,
					waypoints.size(),
					distance_to_waypoint,
					current_waypoint_index + 1,
					waypoints.size()
				])
				_cap_route_debug_last_index = current_waypoint_index
				_cap_route_debug_last_distance_m = INF
				_cap_route_debug_no_progress_s = 0.0
				_cap_route_debug_timer_s = cap_route_debug_interval_s
	else:
		_reset_cap_route_debug()

	if _evaluate_combat_objective():
		return

	# Debug
	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 60 == 0:
		var dist_to_wp = aircraft.global_position.distance_to(nav_waypoint) if waypoints.size() > 0 else 0
		print("[AIPilot SEARCH] WP %d/%d  dist=%.0fm  nav=(%.0f,%.0f,%.0f)" % [current_waypoint_index, waypoints.size(), dist_to_wp, nav_waypoint.x, nav_waypoint.y, nav_waypoint.z])

func _find_ground_attack_target() -> Node3D:
	"""Find nearest hostile ground or surface target within sensor range. Excludes same-team."""
	var my_team: int = aircraft.get_team() if aircraft.has_method("get_team") else 1
	var nearest: Node3D = null
	var best_score: float = INF
	for enemy in known_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("get_team") and enemy.get_team() == my_team:
			continue
		if _is_enemy_aircraft_target(enemy):
			continue
		var normalized_enemy: Node3D = _normalize_ground_attack_target(enemy)
		if not _is_valid_ground_attack_target(normalized_enemy):
			continue
		var d: float = aircraft.global_position.distance_to(normalized_enemy.global_position)
		var score: float = d + _get_ground_target_priority_penalty(normalized_enemy)
		if score < best_score:
			best_score = score
			nearest = normalized_enemy
	return nearest

func _normalize_ground_attack_target(node: Variant) -> Node3D:
	if node == null or not is_instance_valid(node):
		return null
	if not (node is Node3D):
		return null
	var current: Node = node as Node
	var best_match: Node3D = node as Node3D
	while current != null:
		if not is_instance_valid(current):
			break
		if not (current is Node3D):
			break
		var current_3d: Node3D = current as Node3D
		if current_3d.is_in_group("carrier") \
				or current_3d.is_in_group("ground_vehicles") \
				or current_3d.is_in_group("gun_emplacements") \
				or current_3d.is_in_group("buildings") \
				or current_3d.is_in_group("enemy_bases"):
			best_match = current_3d
		current = current.get_parent()
	return best_match if best_match and is_instance_valid(best_match) else null

func _sanitize_ground_attack_target(node: Variant) -> Node3D:
	if node == null or not is_instance_valid(node):
		return null
	if not (node is Node3D):
		return null
	var normalized: Node3D = _normalize_ground_attack_target(node)
	if not normalized or not is_instance_valid(normalized):
		return null
	return normalized

func _resolve_current_ground_attack_target() -> Node3D:
	var resolved_target: Node3D = _sanitize_ground_attack_target(combat_target)
	if resolved_target == null:
		combat_target = null
		return null
	if combat_target != resolved_target:
		combat_target = resolved_target
	return resolved_target

func _get_target_linear_velocity(target: Variant) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	if not (target is Node3D):
		return Vector3.ZERO
	if "linear_velocity" in target:
		return target.linear_velocity
	if target.has_method("get_velocity_vector"):
		var velocity_variant: Variant = target.call("get_velocity_vector")
		if velocity_variant is Vector3:
			return velocity_variant
	if "velocity" in target:
		var velocity_value: Variant = target.velocity
		if velocity_value is Vector3:
			return velocity_value
	return Vector3.ZERO

func _sample_attack_path_terrain_max_cached(from_pos: Vector3, to_pos: Vector3, num_samples: int) -> float:
	if num_samples <= 0:
		return NAN
	var now_s: float = Time.get_ticks_msec() / 1000.0
	var reuse_distance_sq: float = attack_terrain_sample_reuse_distance_m * attack_terrain_sample_reuse_distance_m
	var cache_valid: bool = now_s < _attack_terrain_sample_cache_until_s
	cache_valid = cache_valid and _attack_terrain_sample_cache_samples == num_samples
	cache_valid = cache_valid and from_pos.distance_squared_to(_attack_terrain_sample_cache_from) <= reuse_distance_sq
	cache_valid = cache_valid and to_pos.distance_squared_to(_attack_terrain_sample_cache_to) <= reuse_distance_sq
	if cache_valid:
		return _attack_terrain_sample_cache_value
	var sampled_height: float = _sample_max_terrain_height_along_path(from_pos, to_pos, num_samples)
	_attack_terrain_sample_cache_until_s = now_s + maxf(attack_terrain_sample_refresh_s, 0.0)
	_attack_terrain_sample_cache_from = from_pos
	_attack_terrain_sample_cache_to = to_pos
	_attack_terrain_sample_cache_samples = num_samples
	_attack_terrain_sample_cache_value = sampled_height
	return sampled_height

func _get_current_bank_angle_deg() -> float:
	if aircraft == null or not is_instance_valid(aircraft):
		return 0.0
	var basis: Basis = aircraft.global_transform.basis
	var current_roll_rad: float = atan2(basis.x.y, basis.y.y)
	return absf(rad_to_deg(current_roll_rad))

func _reset_release_solution_stability() -> void:
	_release_solution_stable_time_s = 0.0
	_release_solution_last_update_s = -INF

func _is_release_solution_stable_enough(now_s: float, is_stable_now: bool, hold_s: float = -1.0) -> bool:
	var dt_s: float = 0.0
	if is_finite(_release_solution_last_update_s):
		dt_s = clampf(now_s - _release_solution_last_update_s, 0.0, 0.25)
	_release_solution_last_update_s = now_s
	if is_stable_now:
		_release_solution_stable_time_s += dt_s
	else:
		_release_solution_stable_time_s = 0.0
	var required_hold_s: float = weapon_release_stability_hold_s if hold_s < 0.0 else maxf(hold_s, 0.0)
	return _release_solution_stable_time_s >= required_hold_s

func _get_effective_bomb_release_tolerance_m() -> float:
	match skill:
		AIPilotSkill.ROOKIE:
			return bomb_rookie_release_tolerance_m
		AIPilotSkill.EXPERIENCED:
			return bomb_experienced_release_tolerance_m
		AIPilotSkill.VETERAN:
			return bomb_veteran_release_tolerance_m
		AIPilotSkill.ACE:
			return bomb_ace_release_tolerance_m
	return bomb_ccip_release_tolerance_m

func _get_effective_bomb_release_hold_s() -> float:
	match skill:
		AIPilotSkill.ROOKIE:
			return bomb_rookie_release_hold_s
		AIPilotSkill.EXPERIENCED:
			return bomb_experienced_release_hold_s
		AIPilotSkill.VETERAN:
			return bomb_veteran_release_hold_s
		AIPilotSkill.ACE:
			return bomb_ace_release_hold_s
	return weapon_release_stability_hold_s

func _is_bomb_best_solution_release_moment(current_miss_m: float, previous_miss_m: float, best_miss_m: float, release_tolerance_m: float) -> bool:
	if current_miss_m < 0.0 or not is_finite(previous_miss_m) or not is_finite(best_miss_m):
		return false
	var grace_m: float = maxf(bomb_release_after_best_grace_m, 0.0)
	var worsen_m: float = maxf(bomb_release_after_best_worsen_m, 0.0)
	var max_best_solution_m: float = release_tolerance_m * maxf(bomb_release_best_solution_tolerance_multiplier, 1.0)
	var best_was_good_enough: bool = best_miss_m <= max_best_solution_m
	var previous_was_near_best: bool = previous_miss_m <= best_miss_m + grace_m
	var current_is_still_near_best: bool = current_miss_m <= best_miss_m + grace_m
	var solution_is_worsening: bool = current_miss_m > previous_miss_m + worsen_m
	var solution_has_left_best: bool = current_miss_m >= best_miss_m + worsen_m
	return best_was_good_enough and previous_was_near_best and current_is_still_near_best and (solution_is_worsening or solution_has_left_best)

func _is_carrier_attack_target(node: Variant) -> bool:
	var normalized: Node3D = _sanitize_ground_attack_target(node)
	return normalized != null and is_instance_valid(normalized) and normalized.is_in_group("carrier")

func _is_valid_ground_attack_target(node: Variant) -> bool:
	node = _sanitize_ground_attack_target(node)
	if not node or not is_instance_valid(node):
		return false
	if node == aircraft:
		return false
	if node.has_method("get_team") and aircraft and aircraft.has_method("get_team"):
		if int(node.get_team()) == int(aircraft.get_team()):
			return false
	if node.is_in_group("carrier"):
		return true
	if node.is_in_group("ground_vehicles"):
		return true
	if node.is_in_group("gun_emplacements") or node.is_in_group("buildings") or node.is_in_group("enemy_bases"):
		return true
	return false

func _get_ground_target_priority_penalty(node: Variant) -> float:
	node = _sanitize_ground_attack_target(node)
	if not node or not is_instance_valid(node):
		return 100000.0
	if node.is_in_group("ground_vehicles"):
		return 0.0
	if node.is_in_group("gun_emplacements"):
		return 80.0
	if node.is_in_group("buildings") or node.is_in_group("enemy_bases"):
		return 180.0
	if node.is_in_group("carrier"):
		return 450.0
	return 300.0

func _is_enemy_aircraft_target(node: Variant) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not (node is Node3D):
		return false
	if node == aircraft:
		return false
	# Require a physics-body-like target so velocity lead is meaningful.
	if not (node is RigidBody3D):
		return false
	# Exclude same-team contacts.
	var my_team: int = aircraft.get_team() if aircraft.has_method("get_team") else 1
	if node.has_method("get_team"):
		var node_team: int = int(node.get_team())
		if node_team == my_team:
			return false
	return true

func _find_nearest_enemy_aircraft_target() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = INF
	for enemy in known_enemies:
		if not is_instance_valid(enemy) or not (enemy is Node3D):
			continue
		var enemy_node: Node3D = enemy as Node3D
		if not _is_enemy_aircraft_target(enemy_node):
			continue
		if not _is_within_engagement_radius(enemy_node):
			continue
		var d: float = aircraft.global_position.distance_to(enemy_node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = enemy_node
	return nearest

func _check_air_threat_proximity() -> bool:
	"""During ground attack, check if an enemy aircraft is dangerously close.
	If so, break off and engage it in a dogfight."""
	if not dogfight_enabled or dogfight_proximity_override_m <= 0.0:
		return false
	for enemy in known_enemies:
		if not is_instance_valid(enemy) or not (enemy is Node3D):
			continue
		if not _is_enemy_aircraft_target(enemy as Node3D):
			continue
		var d: float = aircraft.global_position.distance_to((enemy as Node3D).global_position)
		if d <= dogfight_proximity_override_m:
			combat_target = enemy as Node3D
			change_state(State.DOGFIGHT)
			if debug_enabled:
				print("[AIPilot] Air threat at %.0fm â€” breaking off ground attack to dogfight %s" % [d, combat_target.name])
			return true
	return false

func _evaluate_combat_objective() -> bool:
	# Air defense has priority over ground attack.
	if dogfight_enabled:
		var air_target: Node3D = _find_nearest_enemy_aircraft_target()
		if air_target and is_instance_valid(air_target):
			combat_target = air_target
			change_state(State.DOGFIGHT)
			if debug_enabled:
				var da: float = aircraft.global_position.distance_to(combat_target.global_position)
				print("[AIPilot DOGFIGHT] Air target acquired: ", combat_target.name, "  dist=", snapped(da, 1.0), "m")
			return true

	if ground_attack_enabled:
		var ground_target: Node3D = _find_ground_attack_target()
		if ground_target and is_instance_valid(ground_target):
			combat_target = ground_target
			_setup_attack_run_waypoint()
			change_state(State.ATTACK_POSITIONING)
			if debug_enabled:
				var d: float = aircraft.global_position.distance_to(combat_target.global_position)
				print("[AIPilot ATTACK] Target acquired: ", combat_target.name, "  dist=", snapped(d, 1.0), "m  pos=", combat_target.global_position)
				print("[AIPilot ATTACK] Starting attack run -> ATTACK_POSITIONING")
			return true

	return false

func _is_within_engagement_radius(target: Variant, radius_m: float = -1.0) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not (target is Node3D):
		return false
	var radius: float = radius_m if radius_m > 0.0 else engagement_radius_from_carrier_m
	if radius <= 0.0:
		return true
	_refresh_carrier_position(false)
	if carrier_position == Vector3.ZERO:
		return aircraft.global_position.distance_to(target.global_position) <= radius
	return carrier_position.distance_to(target.global_position) <= radius

func _setup_attack_run_waypoint():
	"""Set nav_waypoint to the weapon setup point, honoring the mission altitude floor."""
	var active_target: Node3D = _resolve_current_ground_attack_target()
	if active_target == null:
		return
	_plan_attack_run_weapon()
	var target_pos: Vector3 = _get_surface_target_position(active_target)
	var to_target: Vector3 = target_pos - aircraft.global_position
	to_target.y = 0.0
	var horiz_dir: Vector3 = to_target.normalized() if to_target.length() > 1.0 else aircraft.global_transform.basis.z
	if _run_weapon_type == "Bomb" and _is_carrier_attack_target(active_target) and carrier_bomb_setup_along_motion:
		var target_velocity: Vector3 = _get_target_linear_velocity(active_target)
		var target_motion: Vector3 = Vector3(target_velocity.x, 0.0, target_velocity.z)
		if target_motion.length() >= maxf(carrier_bomb_setup_min_speed_mps, 0.0):
			horiz_dir = target_motion.normalized()
	var setup_dist: float = _get_attack_setup_distance_m()
	nav_waypoint = target_pos - horiz_dir * setup_dist
	# Lock XZ now â€” _state_attack_positioning must NOT recompute from aircraft position.
	_attack_setup_wp_xz = Vector2(nav_waypoint.x, nav_waypoint.z)
	_attack_setup_target_pos = target_pos
	# Survey the highest terrain between setup point and target to guarantee adequate clearance.
	var terrain_max: float = _sample_attack_path_terrain_max_cached(nav_waypoint, target_pos, 8)
	var setup_altitude_m: float = _get_attack_setup_altitude_m(target_pos, terrain_max)
	if _run_weapon_type == "Bomb":
		_bomb_run_altitude_m = setup_altitude_m
		_best_bomb_ccip_miss_this_run = INF
	nav_waypoint.y = setup_altitude_m
	maneuver_waypoint = nav_waypoint
	_overshoot_recompute_cooldown_s = 0.0  # fresh setup â€” allow overshoot check immediately next frame
	_positioning_time_s = 0.0
	_committed_turn_sign = 0.0
	if debug_enabled:
		print("[AIPilot ATTACK] Run setup waypoint: ", nav_waypoint, "  target=", target_pos, "  weapon=", _run_weapon_type, "  bombs=", _bombs_to_drop_this_run)

func _state_attack_positioning(delta: float):
	"""Fly to attack run setup waypoint (800m offset; altitude depends on weapon plan)."""
	if _check_air_threat_proximity():
		return
	if not ground_attack_enabled:
		change_state(State.SEARCH)
		return
	var active_target: Node3D = _resolve_current_ground_attack_target()
	if active_target == null:
		change_state(State.SEARCH)
		return

	# Don't attempt attack maneuvers at dangerously low speed ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â build energy first
	var cur_speed: float = aircraft.linear_velocity.length()
	if cur_speed < stall_speed_mps + stall_margin_mps:
		# Too slow: fly straight, nose slightly down, build speed
		nav_waypoint = aircraft.global_position + aircraft.global_transform.basis.z * 500.0
		nav_waypoint.y = aircraft.global_position.y - 20.0
		_update_maneuver_waypoint()
		_navigate_to_waypoint(delta)
		target_speed = 120.0
		return

	target_speed = 100.0
	_positioning_time_s += delta

	var target_pos: Vector3 = _get_surface_target_position(active_target)

	# Hard timeout: if we've been positioning for too long, recompute the approach
	# from the current position. This unsticks aircraft that got a bad setup_wp.
	if _positioning_time_s > 30.0:
		if debug_enabled:
			print("[AIPilot ATTACK] Positioning timeout (%.0fs), recomputing setup waypoint" % _positioning_time_s)
		_setup_attack_run_waypoint()
		# _setup_attack_run_waypoint resets _positioning_time_s to 0

	# Use the approach direction computed at setup time (stored in _attack_setup_wp_xz).
	# Only drift XZ for carrier movement â€” never recompute from current aircraft position,
	# which would cause the waypoint to spiral away as the aircraft moves.
	var carrier_drift := target_pos - _attack_setup_target_pos
	nav_waypoint.x = _attack_setup_wp_xz.x + carrier_drift.x
	nav_waypoint.z = _attack_setup_wp_xz.y + carrier_drift.z

	var terrain_max: float = _sample_attack_path_terrain_max_cached(nav_waypoint, target_pos, 8)
	var setup_altitude_m: float = _get_attack_setup_altitude_m(target_pos, terrain_max)
	if _run_weapon_type == "Bomb":
		_bomb_run_altitude_m = setup_altitude_m
	nav_waypoint.y = setup_altitude_m

	# Never let the positioning waypoint sit lower than our current altitude minus a gentle
	# descent allowance. This prevents the plane from descending steeply through hilly terrain
	# just to reach the ideal setup altitude. It will level off and approach the altitude
	# gradually rather than punching into the terrain beneath it.
	var ground_h: float = _smoothed_ground_height if not is_nan(_smoothed_ground_height) else _get_ground_height_at_position(aircraft.global_position)
	var terrain_floor: float = (ground_h + 220.0) if not is_nan(ground_h) else nav_waypoint.y
	nav_waypoint.y = max(nav_waypoint.y, terrain_floor, aircraft.global_position.y - 60.0)

	# Overshoot detection: if the setup waypoint is more than 120 deg behind our velocity
	# vector, we've clearly flown past it. Recompute from current position so we don't
	# spend 30+ seconds completing a wide arc back to a stale approach direction.
	# Cooldown prevents re-triggering every frame while the aircraft turns.
	_overshoot_recompute_cooldown_s = maxf(0.0, _overshoot_recompute_cooldown_s - delta)
	if _overshoot_recompute_cooldown_s <= 0.0:
		var vel_xz := Vector2(aircraft.linear_velocity.x, aircraft.linear_velocity.z)
		if vel_xz.length_squared() > 100.0:  # need meaningful airspeed to test direction
			var to_wp_xz := Vector2(nav_waypoint.x - aircraft.global_position.x,
									nav_waypoint.z - aircraft.global_position.z)
			if to_wp_xz.length_squared() > 400.0:  # don't trigger when almost there
				var dot := vel_xz.normalized().dot(to_wp_xz.normalized())
				if dot < -0.5:  # > 120 deg off â€” clear overshoot
					if debug_enabled:
						print("[AIPilot ATTACK] Overshoot detected (dot=%.2f), recomputing setup waypoint" % dot)
					_setup_attack_run_waypoint()
					_overshoot_recompute_cooldown_s = 10.0  # wait 10s before checking again

	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)

	var dist_to_wp: float = aircraft.global_position.distance_to(nav_waypoint)
	var reached_setup_point: bool = dist_to_wp < 150.0
	if reached_setup_point and _run_weapon_type == "Bomb":
		var planned_bomb_altitude: float = _bomb_run_altitude_m if _bomb_run_altitude_m > 0.0 else nav_waypoint.y
		var altitude_overshoot: float = aircraft.global_position.y - planned_bomb_altitude
		reached_setup_point = altitude_overshoot <= maxf(bomb_direct_entry_max_altitude_overshoot_m, 0.0)
	if reached_setup_point or _can_enter_attack_run_from_current_geometry(target_pos):
		# Reached setup point: bombs go level-inbound first, guns can start dive immediately
		if _run_weapon_type == "Bomb":
			change_state(State.ATTACK_INBOUND)
		else:
			change_state(State.ATTACK_DIVE)
		_committed_turn_sign = 0.0
		if debug_enabled:
			print("[AIPilot ATTACK] Reached setup point, next phase: ", State.keys()[current_state])

func _can_enter_attack_run_from_current_geometry(target_pos: Vector3) -> bool:
	if _positioning_time_s < maxf(attack_positioning_direct_entry_after_s, 0.0):
		return false

	var to_target: Vector3 = target_pos - aircraft.global_position
	var to_target_flat := Vector3(to_target.x, 0.0, to_target.z)
	var horiz_dist: float = to_target_flat.length()
	if horiz_dist < 1.0:
		return false

	var setup_dist: float = _get_attack_setup_distance_m()
	var range_buffer: float = maxf(attack_positioning_direct_entry_range_buffer_m, 0.0)
	if horiz_dist > setup_dist + range_buffer:
		return false
	if _run_weapon_type == "Bomb":
		var min_bomb_entry_range: float = maxf(bomb_dive_start_distance_m + 150.0, setup_dist - 150.0)
		if horiz_dist < min_bomb_entry_range:
			return false
		var planned_altitude: float = _bomb_run_altitude_m if _bomb_run_altitude_m > 0.0 else target_pos.y + bomb_run_setup_altitude_offset_m
		var altitude_overshoot: float = aircraft.global_position.y - planned_altitude
		if altitude_overshoot > maxf(bomb_direct_entry_max_altitude_overshoot_m, 0.0):
			return false
		var setup_wp_flat := Vector3(_attack_setup_wp_xz.x, 0.0, _attack_setup_wp_xz.y)
		var target_flat := Vector3(target_pos.x, 0.0, target_pos.z)
		var attack_line: Vector3 = target_flat - setup_wp_flat
		if attack_line.length_squared() > 1.0:
			var attack_dir: Vector3 = attack_line.normalized()
			var aircraft_flat := Vector3(aircraft.global_position.x, 0.0, aircraft.global_position.z)
			var from_setup: Vector3 = aircraft_flat - setup_wp_flat
			var along_track: float = from_setup.dot(attack_dir)
			var closest_on_line: Vector3 = setup_wp_flat + attack_dir * along_track
			var cross_track_m: float = aircraft_flat.distance_to(closest_on_line)
			if cross_track_m > maxf(bomb_direct_entry_max_cross_track_m, 0.0):
				return false

	var forward_flat := Vector3(aircraft.global_transform.basis.z.x, 0.0, aircraft.global_transform.basis.z.z)
	if forward_flat.length_squared() <= 0.0001:
		return false

	var target_dot: float = forward_flat.normalized().dot(to_target_flat.normalized())
	if target_dot < clampf(attack_positioning_direct_entry_min_dot, -1.0, 1.0):
		return false
	if _run_weapon_type == "Bomb":
		var planned_setup_flat := Vector3(_attack_setup_wp_xz.x, 0.0, _attack_setup_wp_xz.y)
		var planned_target_flat := Vector3(target_pos.x, 0.0, target_pos.z)
		var planned_attack_line: Vector3 = planned_target_flat - planned_setup_flat
		if planned_attack_line.length_squared() > 1.0:
			var attack_dot: float = forward_flat.normalized().dot(planned_attack_line.normalized())
			if attack_dot < 0.75:
				return false

	if debug_enabled:
		print("[AIPilot ATTACK] Entering run from geometry: range=%.0fm dot=%.2f weapon=%s" % [
			horiz_dist,
			target_dot,
			_run_weapon_type
		])
	return true

func _state_attack_inbound(delta: float):
	"""Bomb run inbound leg: fly level toward target at setup altitude, then dive at bomb_dive_start_distance_m."""
	if _check_air_threat_proximity():
		return
	if not ground_attack_enabled:
		change_state(State.SEARCH)
		return
	var active_target: Node3D = _resolve_current_ground_attack_target()
	if active_target == null:
		change_state(State.SEARCH)
		return
	var target_pos: Vector3 = _get_surface_target_position(active_target)
	var to_target: Vector3 = target_pos - aircraft.global_position
	var horiz_dist_to_target: float = Vector2(to_target.x, to_target.z).length()
	target_speed = 105.0

	# Fly straight at the target, clamped above the highest terrain between us and
	# the target so we don't fly into hills during the approach.
	var inbound_alt: float = _bomb_run_altitude_m
	var ground_h: float = _smoothed_ground_height if not is_nan(_smoothed_ground_height) else _get_ground_height_at_position(aircraft.global_position)
	if not is_nan(ground_h):
		inbound_alt = max(inbound_alt, ground_h + 220.0)
	var ahead_h: float = _sample_attack_path_terrain_max_cached(aircraft.global_position, target_pos, 4)
	if not is_nan(ahead_h):
		inbound_alt = max(inbound_alt, ahead_h + 180.0)
	nav_waypoint = target_pos
	nav_waypoint.y = inbound_alt

	# Skip the generic lookahead on the final inbound leg: steer directly at the aim
	# point so the plane cannot overshoot the dive-start threshold.
	maneuver_waypoint = nav_waypoint
	if nav_target:
		nav_target.global_position = maneuver_waypoint
	_navigate_to_waypoint(delta)

	# Only start the dive if we're at or above the planned inbound altitude (within tolerance).
	# If we're still climbing over high terrain, hold the inbound leg until we have altitude.
	var alt_above: float = aircraft.global_position.y - target_pos.y
	var effective_dive_start_dist: float = bomb_dive_start_distance_m
	if _run_weapon_type == "Bomb":
		effective_dive_start_dist = clampf(
			maxf(bomb_dive_start_distance_m, alt_above * maxf(bomb_dive_start_altitude_factor, 0.1)),
			bomb_dive_start_distance_m,
			bomb_run_setup_distance_m + 200.0
		)
	var alt_ready: bool = aircraft.global_position.y >= (_bomb_run_altitude_m - 50.0)
	var forward_flat := Vector3(aircraft.global_transform.basis.z.x, 0.0, aircraft.global_transform.basis.z.z)
	var target_flat := Vector3(to_target.x, 0.0, to_target.z)
	var target_aligned: bool = false
	if forward_flat.length_squared() > 0.0001 and target_flat.length_squared() > 1.0:
		target_aligned = forward_flat.normalized().dot(target_flat.normalized()) >= clampf(bomb_dive_start_min_target_dot, -1.0, 1.0)
	var bank_ready: bool = _get_current_bank_angle_deg() <= maxf(bomb_dive_start_max_bank_deg, 1.0)
	if horiz_dist_to_target <= effective_dive_start_dist and alt_ready and target_aligned and bank_ready:
		change_state(State.ATTACK_DIVE)
		_committed_turn_sign = 0.0
		if debug_enabled:
			print("[AIPilot ATTACK] Dive start: target=", active_target.name, "  horiz_range=", snapped(horiz_dist_to_target, 1.0), "m  alt_above=", snapped(alt_above, 1.0), "m  aim_height=", bomb_dive_aim_height_m, "m")
	elif horiz_dist_to_target <= bomb_dive_start_distance_m * 0.4:
		# Abort: we're way too close and still too low ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â can't set up a proper dive
		change_state(State.ATTACK_BREAK_OFF)
		_committed_turn_sign = 0.0
		if debug_enabled:
			print("[AIPilot ATTACK] Inbound abort: too close (", snapped(horiz_dist_to_target, 1.0), "m) and too low for dive, breaking off")

func _state_attack_dive(delta: float):
	"""Dive at target, fire guns, break off at 100m to line up new run."""
	if _check_air_threat_proximity():
		return
	if not ground_attack_enabled:
		change_state(State.SEARCH)
		return
	var active_target: Node3D = _resolve_current_ground_attack_target()
	if active_target == null:
		change_state(State.SEARCH)
		return

	var target_pos: Vector3 = _get_surface_target_position(active_target)
	var dist_to_target: float = aircraft.global_position.distance_to(target_pos)

	# Bomb runs need a much larger break-off margin ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â they dive from high altitude and need room to recover.
	var pull_up_dist: float = _get_attack_pull_up_distance_m()

	# Break off when we've dropped all planned bombs (3 for bomb runs)
	if _run_weapon_type == "Bomb" and _bombs_dropped_this_run >= _bombs_to_drop_this_run:
		change_state(State.ATTACK_BREAK_OFF)
		_committed_turn_sign = 0.0
		if debug_enabled:
			print("[AIPilot ATTACK] Break-off: dropped ", _bombs_dropped_this_run, " bombs, pulling up")
		return
	if _run_weapon_type == "Rocket Pod" and _rockets_to_fire_this_run > 0 and _rockets_fired_this_run >= _rockets_to_fire_this_run:
		change_state(State.ATTACK_BREAK_OFF)
		_committed_turn_sign = 0.0
		if debug_enabled:
			print("[AIPilot ATTACK] Break-off: fired ", _rockets_fired_this_run, " rockets, pulling up")
		return
	# Break off when too close. Bomb runs should not be salvaged with last-second drops;
	# if CCIP was not good by the pull-up range, keep the bombs and try another pass.
	var min_safe_dist: float = pull_up_dist
	if dist_to_target < min_safe_dist:
		change_state(State.ATTACK_BREAK_OFF)
		_committed_turn_sign = 0.0
		if debug_enabled:
			print("[AIPilot ATTACK] Break-off: too close to target (", snapped(dist_to_target, 1.0), "m)")
		return

	# For gun runs aim just above the ground target for accuracy.
	# For bomb runs aim at target altitude so the dive trajectory sweeps through the
	# optimal CCIP release geometry, allowing CCIP to cross zero during the approach.
	# Raise the aim point only if terrain on the approach path requires it.
	var aim_height: float = 1.5
	var target_velocity: Vector3 = _get_target_linear_velocity(active_target)
	var is_carrier_bomb_target: bool = _run_weapon_type == "Bomb" and _is_carrier_attack_target(active_target)
	var release_target_pos: Vector3 = target_pos
	if _run_weapon_type == "Bomb":
		aim_height = bomb_dive_aim_height_m
		var highest_terrain: float = _sample_attack_path_terrain_max_cached(aircraft.global_position, target_pos, 6)
		if not is_nan(highest_terrain):
			var min_aim_y: float = highest_terrain + 25.0
			aim_height = max(aim_height, min_aim_y - target_pos.y)
	elif _run_weapon_type == "Rocket Pod":
		aim_height = rocket_dive_aim_height_m
	var aim_pos: Vector3 = target_pos + Vector3(0.0, aim_height, 0.0)
	if target_velocity != Vector3.ZERO and not is_carrier_bomb_target:
		aim_pos += target_velocity * attack_aim_lead_time_s

	# Bomb runs: refine aim using predicted impact ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â steer to put the bullseye on target
	var horiz_dist: float = Vector2(aircraft.global_position.x - target_pos.x, aircraft.global_position.z - target_pos.z).length()
	var alt_above: float = aircraft.global_position.y - target_pos.y
	if _run_weapon_type == "Bomb" and _bombs_dropped_this_run == 0:
		var target_flat_dir := Vector3(target_pos.x - aircraft.global_position.x, 0.0, target_pos.z - aircraft.global_position.z)
		var forward_flat_dir := Vector3(aircraft.global_transform.basis.z.x, 0.0, aircraft.global_transform.basis.z.z)
		if target_flat_dir.length_squared() > 1.0 and forward_flat_dir.length_squared() > 0.0001:
			var nose_to_target_dot: float = forward_flat_dir.normalized().dot(target_flat_dir.normalized())
			if nose_to_target_dot < -0.15 and horiz_dist > maxf(bomb_pull_up_distance_m, 1.0):
				if debug_enabled:
					print("[AIPilot ATTACK] Bomb dive invalid: target behind nose (dot=%.2f), resetting run" % nose_to_target_dot)
				_setup_attack_run_waypoint()
				change_state(State.ATTACK_POSITIONING)
				return
	var ccip_impact: Vector3 = Vector3.ZERO  # Shared between aim correction and release check
	if _run_weapon_type == "Bomb":
		# Throttle CCIP calculation â€” ballistic sim is expensive (~500 iterations + raycasts)
		_ccip_cache_timer -= delta
		if _ccip_cache_timer <= 0.0:
			_ccip_cache_timer = maxf(bomb_ccip_recompute_interval_s, 0.05)
			var use_moving_target_ccip: bool = bomb_ccip_use_moving_target_plane \
				and target_velocity.length_squared() > 1.0 \
				and not is_carrier_bomb_target
			var bomb_ccip_solution: Dictionary = _predict_bomb_impact_solution(false, target_pos, target_velocity, use_moving_target_ccip)
			var impact_variant: Variant = bomb_ccip_solution.get("impact_position", Vector3.ZERO)
			_ccip_cached_result = impact_variant if impact_variant is Vector3 else Vector3.ZERO
			_ccip_cached_tof_s = float(bomb_ccip_solution.get("time_of_flight", -1.0))
		ccip_impact = _ccip_cached_result
		if target_velocity != Vector3.ZERO:
			var lead_time_s: float = attack_aim_lead_time_s
			if ccip_impact != Vector3.ZERO and _ccip_cached_tof_s > 0.0:
				if is_carrier_bomb_target:
					lead_time_s = clampf(
						_ccip_cached_tof_s * carrier_bomb_target_lead_scale,
						0.0,
						carrier_bomb_target_lead_max_s
					)
				else:
					lead_time_s = clampf(_ccip_cached_tof_s * bomb_target_lead_scale, attack_aim_lead_time_s, bomb_target_lead_max_s)
			if not is_carrier_bomb_target or lead_time_s > 0.0:
				release_target_pos += target_velocity * lead_time_s
			if is_carrier_bomb_target:
				var carrier_forward: Vector3 = Vector3(target_velocity.x, 0.0, target_velocity.z)
				if carrier_forward.length_squared() > 0.01:
					release_target_pos += carrier_forward.normalized() * maxf(carrier_bomb_forward_bias_m, 0.0)
		if ccip_impact != Vector3.ZERO:
			var err_h: Vector3 = Vector3(release_target_pos.x - ccip_impact.x, 0.0, release_target_pos.z - ccip_impact.z)
			var max_correction_m: float = maxf(bomb_ccip_aim_correction_max_m, 0.0)
			if err_h.length() > max_correction_m and max_correction_m > 0.0:
				err_h = err_h.normalized() * max_correction_m
			var correction_strength: float = 0.8
			if horiz_dist < bomb_ccip_aim_correction_close_range_m:
				var close_t: float = 1.0 - clampf(horiz_dist / maxf(bomb_ccip_aim_correction_close_range_m, 1.0), 0.0, 1.0)
				correction_strength = lerpf(correction_strength, bomb_ccip_aim_correction_close_scale, close_t)
			aim_pos += err_h * correction_strength
		# In release window: aim closer to target and use precise steering
		# Smooth transition 600ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢400m to avoid abrupt aim-height jump that causes pitch oscillation
		var release_t: float = clamp(1.0 - (horiz_dist - 650.0) / 350.0, 0.0, 1.0) if alt_above < 450.0 else 0.0
		var aim_height_close: float = lerp(aim_height, bomb_dive_close_aim_height_m, release_t)
		aim_pos.y = release_target_pos.y + aim_height_close
		_dive_precise_aim = horiz_dist < 750.0 and alt_above < 450.0
	elif _run_weapon_type == "Rocket Pod":
		_ccip_cache_timer -= delta
		if _ccip_cache_timer <= 0.0:
			_ccip_cache_timer = maxf(rocket_ccip_recompute_interval_s, 0.05)
			var rocket_ccip_solution: Dictionary = _predict_rocket_impact_solution()
			var rocket_impact_variant: Variant = rocket_ccip_solution.get("impact_position", Vector3.ZERO)
			_ccip_cached_result = rocket_impact_variant if rocket_impact_variant is Vector3 else Vector3.ZERO
			_ccip_cached_tof_s = float(rocket_ccip_solution.get("time_to_impact", -1.0))
		ccip_impact = _ccip_cached_result
		if target_velocity != Vector3.ZERO:
			var rocket_lead_time_s: float = attack_aim_lead_time_s
			if ccip_impact != Vector3.ZERO and _ccip_cached_tof_s > 0.0:
				rocket_lead_time_s = clampf(_ccip_cached_tof_s * rocket_target_lead_scale, attack_aim_lead_time_s, rocket_target_lead_max_s)
			release_target_pos += target_velocity * rocket_lead_time_s
		if ccip_impact != Vector3.ZERO:
			var rocket_err_h: Vector3 = Vector3(release_target_pos.x - ccip_impact.x, 0.0, release_target_pos.z - ccip_impact.z)
			var rocket_correction_strength: float = clampf(0.35 + 0.45 * (1.0 - horiz_dist / maxf(rocket_release_max_range_m, 1.0)), 0.35, 0.8)
			aim_pos += rocket_err_h * rocket_correction_strength
		_dive_precise_aim = horiz_dist < rocket_release_max_range_m and alt_above < 320.0
	else:
		_dive_precise_aim = false
		_hide_bomb_debug_visuals()

	if _run_weapon_type == "Bomb":
		_update_bomb_debug_visuals(aim_pos, release_target_pos, ccip_impact, target_velocity, horiz_dist, alt_above, delta, target_pos)

	nav_waypoint = aim_pos
	maneuver_waypoint = aim_pos
	if nav_target:
		nav_target.global_position = maneuver_waypoint
	_navigate_to_waypoint(delta)

	if _run_weapon_type == "Bomb":
		_handle_bomb_release_run(aim_pos, release_target_pos, ccip_impact, target_pos)
	elif _run_weapon_type == "Rocket Pod":
		_handle_rocket_release_run(aim_pos, release_target_pos, ccip_impact)
	else:
		# Fire guns only when precisely aimed (within ~5ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â° cone)
		var fwd: Vector3 = aircraft.global_transform.basis.z
		var to_tgt: Vector3 = (aim_pos - aircraft.global_position).normalized()
		var dot: float = fwd.dot(to_tgt)
		var gun_max_range_m: float = _get_selected_gun_max_range_m()
		var in_gun_range: bool = (not is_finite(gun_max_range_m)) or dist_to_target <= gun_max_range_m
		var ground_gun_alignment_deg: float = lerpf(6.0, night_ground_gun_alignment_deg, _get_ai_darkness_factor())
		if dot > cos(deg_to_rad(ground_gun_alignment_deg)) and in_gun_range:
			_fire_guns()
		else:
			_stop_firing()

	target_speed = 110.0 if _run_weapon_type == "Rocket Pod" else 120.0  # Faster during attack run

func _state_attack_break_off(delta: float):
	"""Fly away from target until far enough, then return to SEARCH to set up new run."""
	if _check_air_threat_proximity():
		return
	if not ground_attack_enabled:
		change_state(State.SEARCH)
		return
	var active_target: Node3D = _resolve_current_ground_attack_target()
	if active_target == null:
		change_state(State.SEARCH)
		return

	var target_pos: Vector3 = _get_surface_target_position(active_target)
	var dist_to_target: float = aircraft.global_position.distance_to(target_pos)
	var now_s: float = Time.get_ticks_msec() / 1000.0
	var recovery_ready: bool = now_s >= _attack_recovery_until_s and altitude_agl > (emergency_min_agl_m + 80.0)

	# Far enough - acquire a (potentially new) target and line up the next run
	if dist_to_target >= attack_break_off_distance_m and recovery_ready:
		var next_target: Node3D = _find_ground_attack_target()
		if next_target and is_instance_valid(next_target):
			combat_target = next_target
			_setup_attack_run_waypoint()
			change_state(State.ATTACK_POSITIONING)
			if debug_enabled:
				print("[AIPilot ATTACK] Break-off complete, new target acquired, setting up next run")
		else:
			combat_target = null
			change_state(State.SEARCH)
			if debug_enabled:
				print("[AIPilot ATTACK] Break-off complete, no target in range, returning to search")
		return

	# Fly away from target (direction from target to us, extended)
	var away: Vector3 = (aircraft.global_position - target_pos)
	away.y = 0.0
	var away_dir: Vector3 = away.normalized() if away.length() > 1.0 else aircraft.global_transform.basis.z
	nav_waypoint = aircraft.global_position + away_dir * 1000.0
	# Egress at current altitude or patrol altitude â€” don't force a steep climb that bleeds airspeed.
	nav_waypoint.y = maxf(aircraft.global_position.y + 30.0, patrol_altitude_m)
	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)

	target_speed = 100.0

func _state_dogfight(delta: float):
	"""Simple dogfight law: roll into target bearing, pull to bring target near nose, full throttle."""
	if not dogfight_enabled:
		_stop_firing()
		change_state(State.SEARCH)
		return

	_dogfight_retarget_timer_s -= delta
	_dogfight_weapon_commit_timer_s = maxf(0.0, _dogfight_weapon_commit_timer_s - delta)
	_dogfight_lost_sight_timer_s = maxf(0.0, _dogfight_lost_sight_timer_s - delta)
	var target_invalid: bool = not (combat_target and is_instance_valid(combat_target) and _is_enemy_aircraft_target(combat_target))
	if target_invalid or _dogfight_retarget_timer_s <= 0.0:
		_dogfight_retarget_timer_s = maxf(dogfight_retarget_interval_s, 0.1)
		var candidate: Node3D = _find_nearest_enemy_aircraft_target()
		if candidate and is_instance_valid(candidate):
			if target_invalid or _should_switch_dogfight_target(combat_target, candidate):
				combat_target = candidate

	if not (combat_target and is_instance_valid(combat_target) and _is_enemy_aircraft_target(combat_target)):
		_stop_firing()
		change_state(State.SEARCH)
		return
	if not _is_within_engagement_radius(combat_target, disengage_radius_from_carrier_m):
		_stop_firing()
		combat_target = null
		change_state(State.SEARCH)
		return
	var own_pos: Vector3 = aircraft.global_position
	var own_vel: Vector3 = aircraft.linear_velocity
	var speed_mps: float = own_vel.length()
	var b: Basis = aircraft.global_transform.basis

	var target_pos: Vector3 = combat_target.global_position
	var target_vel: Vector3 = Vector3.ZERO
	if "linear_velocity" in combat_target:
		target_vel = combat_target.linear_velocity
	var dist_to_target: float = own_pos.distance_to(target_pos)
	_dogfight_prev_target_distance_m = dist_to_target
	var collision_avoid_wp: Vector3 = _compute_dogfight_collision_avoidance(target_pos, target_vel, own_pos, own_vel)
	var collision_avoiding: bool = collision_avoid_wp != Vector3.ZERO
	var in_rejoin: bool = dist_to_target > dogfight_rejoin_range_m or collision_avoiding
	var to_target_dir: Vector3 = (target_pos - own_pos).normalized() if dist_to_target > 1.0 else b.z
	var sight_cos: float = cos(deg_to_rad(clampf(dogfight_lost_sight_cone_deg, 10.0, 179.0) * 0.5))
	var target_in_sight: bool = to_target_dir.dot(b.z) >= sight_cos
	if target_in_sight:
		_clear_dogfight_lost_sight_behavior()
	elif _dogfight_lost_sight_timer_s <= 0.0:
		_choose_dogfight_lost_sight_behavior(target_pos, target_vel, own_pos, b)
		if not (combat_target and is_instance_valid(combat_target) and _is_enemy_aircraft_target(combat_target)):
			_stop_firing()
			change_state(State.SEARCH)
			return
		target_pos = combat_target.global_position
		target_vel = combat_target.linear_velocity if "linear_velocity" in combat_target else Vector3.ZERO
		dist_to_target = own_pos.distance_to(target_pos)
		to_target_dir = (target_pos - own_pos).normalized() if dist_to_target > 1.0 else b.z
		target_in_sight = to_target_dir.dot(b.z) >= sight_cos

	_sync_dogfight_missile_target(combat_target)
	_select_dogfight_weapon(dist_to_target, target_in_sight, to_target_dir)

	var muzzle_velocity: float = _get_selected_gun_muzzle_velocity()
	var weapon_mount: Dictionary = _get_selected_weapon_mount_info()
	var muzzle_origin: Vector3 = weapon_mount.get("origin", own_pos)
	var muzzle_forward: Vector3 = weapon_mount.get("forward", b.z)
	var weapon_spread_deg: float = float(weapon_mount.get("spread_deg", 1.0))
	var using_guns: bool = not _is_selected_dogfight_missile()
	var aim_reference_pos: Vector3 = muzzle_origin if using_guns else own_pos
	var aim_reference_vel: Vector3 = _get_point_velocity_at_world_position(muzzle_origin) if using_guns else own_vel
	var aim_solution: Dictionary = _get_dogfight_aim_solution(muzzle_origin, aim_reference_vel, target_pos, target_vel, muzzle_velocity)
	var lead_point: Vector3 = aim_solution.get("intercept_point", target_pos)
	var compensated_aim_point: Vector3 = aim_solution.get("aim_point", lead_point)
	lead_point = _clamp_dogfight_upward_aim_point(own_pos, lead_point)
	compensated_aim_point = _clamp_dogfight_upward_aim_point(aim_reference_pos, compensated_aim_point)
	var aim_tof: float = float(aim_solution.get("tof", maxf(muzzle_origin.distance_to(lead_point) / maxf(muzzle_velocity, 50.0), 0.05)))
	var aim_blend: float = clampf(dogfight_lead_pursuit_blend, 0.0, 1.0)
	var pursuit_point: Vector3 = target_pos.lerp(lead_point, aim_blend)
	pursuit_point = _clamp_dogfight_upward_aim_point(own_pos, pursuit_point)
	var ballistic_aim_base_blend: float = clampf(dogfight_ballistic_aim_blend, 0.0, 1.0)
	var aim_point: Vector3 = pursuit_point.lerp(compensated_aim_point, ballistic_aim_base_blend)
	aim_point = _clamp_dogfight_upward_aim_point(own_pos, aim_point)
	if not target_in_sight and _dogfight_lost_sight_behavior in [
		DogfightLostSightBehavior.CLIMB,
		DogfightLostSightBehavior.EXTEND,
		DogfightLostSightBehavior.OFFSET
	] and _dogfight_variation_waypoint != Vector3.ZERO:
		aim_point = _clamp_dogfight_upward_aim_point(own_pos, _dogfight_variation_waypoint)

	var to_aim: Vector3 = aim_point - aim_reference_pos
	if to_aim.length_squared() < 1.0:
		to_aim = b.z
	var aim_dir: Vector3 = to_aim.normalized()
	var local_x: float = aim_dir.dot(b.x)
	var local_y: float = aim_dir.dot(b.y)
	var local_z: float = aim_dir.dot(b.z)

	# Outer loop: choose desired bank from aim azimuth error.
	var max_bank_deg: float = dogfight_bank_cmd_limit_deg
	if in_rejoin:
		max_bank_deg = minf(max_bank_deg, dogfight_rejoin_bank_limit_deg)
	var speed_t: float = clampf(
		(speed_mps - dogfight_min_speed_mps) / maxf(dogfight_corner_speed_mps - dogfight_min_speed_mps, 1.0),
		0.0,
		1.0
	)
	var low_speed_bank_deg: float = 30.0 if in_rejoin else 40.0
	max_bank_deg = lerpf(low_speed_bank_deg, max_bank_deg, speed_t)
	if altitude_agl < dogfight_ground_protect_agl_m:
		max_bank_deg = minf(max_bank_deg, dogfight_ground_protect_min_bank_deg + 15.0)

	var yaw_err_rad: float
	if local_z < -0.15:
		# Target behind: commit hard turn toward the side of the target.
		yaw_err_rad = signf(local_x) * PI * 0.5
	else:
		yaw_err_rad = atan2(local_x, maxf(local_z, 0.05))
	var pitch_err_rad: float = atan2(local_y, maxf(absf(local_z), 0.05))
	var aim_err_rad: float = sqrt(yaw_err_rad * yaw_err_rad + pitch_err_rad * pitch_err_rad)

	var precise_entry_deg: float = maxf(dogfight_precise_aim_entry_deg, 0.5)
	var precise_full_deg: float = clampf(dogfight_precise_aim_full_deg, 0.1, precise_entry_deg - 0.1)
	var precise_entry_rad: float = deg_to_rad(precise_entry_deg)
	var precise_full_rad: float = deg_to_rad(precise_full_deg)
	var precise_aim_t: float = 0.0
	if not in_rejoin and local_z > 0.15 and dist_to_target < maxf(dogfight_precise_aim_max_range_m, 50.0):
		var denom: float = maxf(precise_entry_rad - precise_full_rad, deg_to_rad(0.1))
		precise_aim_t = clampf((precise_entry_rad - aim_err_rad) / denom, 0.0, 1.0)
	if not target_in_sight:
		precise_aim_t = 0.0
	else:
		# Bias the blend so precise tracking takes over sooner once we are broadly on the gun line.
		precise_aim_t = clampf(sqrt(precise_aim_t), 0.0, 1.0)

	# As the nose comes on target, transition from pursuit steering onto the real ballistic solution.
	if target_in_sight:
		var precise_ballistic_blend: float = lerpf(
			ballistic_aim_base_blend,
			clampf(dogfight_precise_ballistic_aim_blend, ballistic_aim_base_blend, 1.0),
			precise_aim_t
		)
		var refined_aim_point: Vector3 = pursuit_point.lerp(compensated_aim_point, precise_ballistic_blend)
		refined_aim_point = _clamp_dogfight_upward_aim_point(own_pos, refined_aim_point)
		if refined_aim_point.distance_squared_to(aim_point) > 0.01:
			aim_point = refined_aim_point
			to_aim = aim_point - aim_reference_pos
			if to_aim.length_squared() < 1.0:
				to_aim = b.z
			aim_dir = to_aim.normalized()
			local_x = aim_dir.dot(b.x)
			local_y = aim_dir.dot(b.y)
			local_z = aim_dir.dot(b.z)
			if local_z < -0.15:
				yaw_err_rad = signf(local_x) * PI * 0.5
			else:
				yaw_err_rad = atan2(local_x, maxf(local_z, 0.05))
			pitch_err_rad = atan2(local_y, maxf(absf(local_z), 0.05))
			aim_err_rad = sqrt(yaw_err_rad * yaw_err_rad + pitch_err_rad * pitch_err_rad)
			# Don't recompute precise_aim_t here â€” that creates a feedback loop where
			# the aim point shifting to ballistic undermines control authority just when
			# it's needed most. Keep the value computed from the initial aim error.

	if collision_avoiding:
		aim_point = collision_avoid_wp
		precise_aim_t = 0.0
		_reset_dogfight_precise_controllers()

	# Keep debug marker aligned with dogfight aim point.
	nav_waypoint = aim_point
	maneuver_waypoint = aim_point
	if nav_target:
		nav_target.global_position = maneuver_waypoint

	var desired_bank: float = clampf(yaw_err_rad * 4.5, -deg_to_rad(max_bank_deg), deg_to_rad(max_bank_deg))
	var straight_t: float = 0.0
	var straight_t_effective: float = 0.0
	if local_z > 0.2:
		var straight_yaw_rad: float = deg_to_rad(maxf(dogfight_straight_level_yaw_deg, 1.0))
		straight_t = 1.0 - clampf(absf(yaw_err_rad) / straight_yaw_rad, 0.0, 1.0)
		# In precise-aim phase, aggressively kill straight-flight bias so aiming errors are driven to zero.
		var straight_precision_scale: float = (1.0 - precise_aim_t) * 0.2
		straight_t_effective = straight_t * straight_precision_scale * straight_precision_scale
		var bank_blend: float = clampf(dogfight_straight_level_bank_blend, 0.0, 1.0)
		desired_bank = lerpf(desired_bank, 0.0, straight_t_effective * bank_blend)
	if not target_in_sight and _dogfight_lost_sight_behavior == DogfightLostSightBehavior.WRONG_TURN:
		var wrong_turn_sign: float = _dogfight_lost_sight_turn_sign
		if absf(wrong_turn_sign) < 0.01:
			wrong_turn_sign = -signf(local_x)
		if absf(wrong_turn_sign) < 0.01:
			wrong_turn_sign = -1.0 if randf() < 0.5 else 1.0
		desired_bank = wrong_turn_sign * deg_to_rad(max_bank_deg)
	# Keep dogfight roll sign aligned with the aircraft's configured control mapping.
	if flip_roll_direction:
		desired_bank = -desired_bank

	# Inner loop: roll to desired bank.
	var current_roll: float = atan2(b.x.y, b.y.y)
	var inverted_recover: bool = b.y.y < -0.05
	if inverted_recover:
		# Never level inverted: force wings back to upright first.
		desired_bank = 0.0
	var bank_error: float = _normalize_angle(desired_bank - current_roll)
	var roll_rate: float = aircraft.angular_velocity.dot(b.z)
	var roll_p_gain: float = 7.0 if inverted_recover else 7.5
	var roll_d_gain: float = 0.35 if inverted_recover else 0.18
	var raw_roll: float = clampf(bank_error * roll_p_gain - roll_rate * roll_d_gain, -1.0, 1.0)

	# Inner loop: pitch toward aim elevation with turn-load bias.
	var pitch_rate_up: float = -aircraft.angular_velocity.dot(b.x)
	var turn_pull_bias: float = clampf(absf(desired_bank) / deg_to_rad(maxf(max_bank_deg, 1.0)), 0.0, 1.0) * 0.22
	if local_z < -0.15:
		turn_pull_bias += 0.15
	var pitch_level_blend: float = clampf(dogfight_straight_level_pitch_blend, 0.0, 1.0)
	turn_pull_bias *= 1.0 - straight_t_effective * pitch_level_blend
	var raw_pitch: float
	if inverted_recover:
		raw_pitch = clampf(-pitch_rate_up * 0.30 - own_vel.y * 0.012, -0.25, 0.35)
	else:
		raw_pitch = pitch_err_rad * 5.0 + turn_pull_bias - pitch_rate_up * 0.12
	var level_vs_correction: float = clampf(-own_vel.y * 0.020, -0.45, 0.45)
	if not inverted_recover:
		raw_pitch += level_vs_correction * straight_t_effective
	if in_rejoin:
		raw_pitch = clampf(raw_pitch, -0.55, 0.65)
	else:
		raw_pitch = clampf(raw_pitch, -0.75, 1.0)
	var low_speed_t: float = clampf((dogfight_corner_speed_mps - speed_mps) / maxf(dogfight_corner_speed_mps, 1.0), 0.0, 1.0)
	var low_speed_pitch_cap: float = lerpf(0.85, dogfight_low_speed_pitch_cap, low_speed_t)
	raw_pitch = clampf(raw_pitch, -0.6, low_speed_pitch_cap)
	if altitude_agl < 80.0 and own_vel.y < 0.0:
		raw_pitch = maxf(raw_pitch, 0.6)
		raw_roll = clampf(raw_roll, -0.6, 0.6)

	# Inner loop: yaw toward azimuth error + coordinated-turn + yaw-rate damping.
	var yaw_rate: float = aircraft.angular_velocity.dot(b.y)
	var sideslip: float = clampf(own_vel.dot(b.x) / maxf(speed_mps, 1.0), -1.0, 1.0)
	var yaw_p_gain: float = dogfight_simple_yaw_aim_gain
	if local_z < -0.15:
		yaw_p_gain *= 1.25
	var yaw_coord: float = -sin(current_roll) * dogfight_simple_yaw_coord_gain
	var raw_yaw: float
	if inverted_recover:
		raw_yaw = 0.0
	else:
		raw_yaw = yaw_err_rad * yaw_p_gain + yaw_coord - yaw_rate * 0.10 - sideslip * 0.15
	raw_yaw = clampf(raw_yaw, -dogfight_max_rudder_input, dogfight_max_rudder_input)
	if in_rejoin:
		raw_yaw *= dogfight_simple_yaw_rejoin_scale

	# --- Single-path precision aiming: when precise_aim_t is significant, skip the
	#     layered blend chain and compute one authoritative command directly. ---
	if precise_aim_t > 0.2 and not inverted_recover:
		# Direct high-authority aiming: error Ã— gain, minimal damping.
		var direct_roll: float = clampf(bank_error * 14.0 - roll_rate * 0.08, -1.0, 1.0)
		var direct_pitch: float = clampf(pitch_err_rad * dogfight_precision_direct_pitch_gain - pitch_rate_up * 0.05, -0.90, low_speed_pitch_cap)
		var direct_yaw: float = clampf(
			yaw_err_rad * dogfight_precision_direct_yaw_gain - yaw_rate * 0.03 - sideslip * 0.04,
			-dogfight_max_rudder_input,
			dogfight_max_rudder_input
		)
		# PID integral adds steady-state correction on top.
		if _dogfight_precise_pitch_controller:
			var pid_pitch: float = clampf(_dogfight_precise_pitch_controller.update(pitch_err_rad, delta), -1.0, 1.0)
			direct_pitch = clampf(direct_pitch + pid_pitch * dogfight_precision_pid_scale, -0.90, low_speed_pitch_cap)
		if _dogfight_precise_yaw_controller:
			var pid_yaw: float = clampf(_dogfight_precise_yaw_controller.update(yaw_err_rad, delta), -dogfight_max_rudder_input, dogfight_max_rudder_input)
			direct_yaw = clampf(direct_yaw + pid_yaw * dogfight_precision_pid_scale, -dogfight_max_rudder_input, dogfight_max_rudder_input)
		# Anti-deadzone: prevent stalling on sub-threshold residuals without over-commanding.
		var min_cmd: float = 0.15
		if absf(direct_pitch) < min_cmd and absf(pitch_err_rad) > deg_to_rad(0.15):
			direct_pitch = signf(pitch_err_rad) * min_cmd
		if absf(direct_yaw) < min_cmd and absf(yaw_err_rad) > deg_to_rad(0.15):
			direct_yaw = signf(yaw_err_rad) * min_cmd
		# Blend from base steering into direct control. Ramps from 0 at precise_aim_t=0.2 to 1 at 1.0.
		var direct_t: float = clampf((precise_aim_t - 0.2) / 0.8, 0.0, 1.0)
		raw_roll = lerpf(raw_roll, direct_roll, direct_t)
		raw_pitch = lerpf(raw_pitch, direct_pitch, direct_t)
		raw_yaw = lerpf(raw_yaw, direct_yaw, direct_t)
	elif precise_aim_t > 0.0 and not inverted_recover:
		# Low precision phase: use the old layered approach for the transition region.
		var precision_mix_t: float = clampf(precise_aim_t * 2.0, 0.0, 1.0)
		var precision_control: Dictionary = _compute_precision_point_control(
			compensated_aim_point,
			max_bank_deg,
			dogfight_precision_bank_gain,
			1.9,
			maxf(dogfight_simple_yaw_aim_gain, precision_point_yaw_gain),
			dogfight_precision_min_bank_deg,
			low_speed_pitch_cap,
			dogfight_max_rudder_input,
			aim_reference_pos
		)
		if bool(precision_control.get("valid", false)):
			raw_roll = lerpf(raw_roll, float(precision_control.get("raw_roll", raw_roll)), precision_mix_t)
			raw_pitch = lerpf(raw_pitch, float(precision_control.get("raw_pitch", raw_pitch)), precision_mix_t)
			raw_yaw = lerpf(raw_yaw, float(precision_control.get("raw_yaw", raw_yaw)), precision_mix_t)
	else:
		_reset_dogfight_precise_controllers()

	# Output with minimal smoothing. In the direct-control path, apply commands near-instantly.
	var response_t: float = clampf(lerpf(0.93, 1.0, precise_aim_t), 0.0, 1.0)
	roll_input = lerpf(_smoothed_roll_input, raw_roll, response_t)
	pitch_input = lerpf(_smoothed_pitch_input, raw_pitch, response_t)
	yaw_input = lerpf(_smoothed_yaw_input, raw_yaw, response_t)
	_smoothed_roll_input = roll_input
	_smoothed_pitch_input = pitch_input
	_smoothed_yaw_input = yaw_input

	# Keep energy high in dogfight.
	throttle_input = 1.0
	if in_rejoin:
		target_speed = clampf(dogfight_rejoin_speed_mps, dogfight_min_speed_mps, dogfight_max_speed_mps)
	else:
		target_speed = clampf(dogfight_corner_speed_mps, dogfight_min_speed_mps, dogfight_max_speed_mps)
	if not target_in_sight and _dogfight_lost_sight_behavior in [
		DogfightLostSightBehavior.CLIMB,
		DogfightLostSightBehavior.EXTEND,
		DogfightLostSightBehavior.OFFSET
	]:
		target_speed = maxf(target_speed, dogfight_rejoin_speed_mps)

	var fire_ok: bool = _dogfight_has_good_fire_solution(
		compensated_aim_point,
		lead_point,
		muzzle_origin,
		aim_reference_vel,
		muzzle_forward,
		muzzle_velocity,
		weapon_spread_deg,
		aim_tof,
		dist_to_target
	)
	# Don't shoot at medium/long range unless we're in precise-aim phase.
	var min_precise_fire_blend: float = clampf(dogfight_fire_precise_min_blend, 0.0, 1.0)
	var precise_close_range_m: float = maxf(dogfight_fire_precise_close_range_m, 50.0)
	if precise_aim_t < min_precise_fire_blend and dist_to_target > precise_close_range_m:
		fire_ok = false

	# Geometric fallback only for very close, centerline shots.
	var fallback_range_m: float = maxf(dogfight_fire_fallback_range_m, 50.0)
	var fallback_min_dot: float = clampf(dogfight_fire_fallback_min_dot, 0.0, 0.9999)
	var fire_geom_ok: bool = false
	if dist_to_target < fallback_range_m and precise_aim_t > 0.94:
		fire_geom_ok = (
			local_z > fallback_min_dot
			and absf(local_x) < maxf(dogfight_fire_fallback_lateral, 0.01)
			and absf(local_y) < maxf(dogfight_fire_fallback_vertical, 0.01)
		)
	fire_ok = fire_ok or fire_geom_ok
	if in_rejoin or inverted_recover:
		fire_ok = false
	_update_dogfight_burst_timers(delta, fire_ok)
	if _dogfight_burst_active:
		_fire_guns()
	else:
		_stop_firing()

	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 30 == 0 and is_instance_valid(combat_target):
		var mode_str: String = "REJOIN" if in_rejoin else "FIGHT"
		var bank_deg_signed: float = rad_to_deg(current_roll)
		var pitch_deg: float = rad_to_deg(asin(clamp(-b.y.z, -1.0, 1.0)))
		var hdg_deg: float = rad_to_deg(atan2(b.z.x, b.z.z))
		var to_tgt: Vector3 = target_pos - own_pos
		var tgt_bearing_deg: float = rad_to_deg(atan2(to_tgt.x, to_tgt.z))
		var bearing_err_deg: float = rad_to_deg(_normalize_angle(deg_to_rad(tgt_bearing_deg) - deg_to_rad(hdg_deg)))
		print("[DOGFIGHT] mode=%s tgt=%-10s  dist=%4.0fm  bear=%+5.0fdeg  hdg=%4.0fdeg" % [
			mode_str, combat_target.name, dist_to_target, bearing_err_deg, hdg_deg])
		print("  attitude: bank=%+5.0fdeg  pitch=%+4.0fdeg  spd=%4.0fm/s  VS=%+5.1fm/s  AGL=%4.0fm" % [
			bank_deg_signed, pitch_deg, speed_mps, own_vel.y, altitude_agl])
		print("  local:    x=%+6.0f  y=%+6.0f  z=%+6.0f  bank_cmd=%+5.0fdeg" % [
			local_x, local_y, local_z, rad_to_deg(desired_bank)])
		print("  aim_err:  yaw=%+5.1fdeg  pitch=%+5.1fdeg" % [
			rad_to_deg(yaw_err_rad), rad_to_deg(pitch_err_rad)])
		print("  precise:  aim=%4.2fdeg  blend=%.2f" % [
			rad_to_deg(aim_err_rad), precise_aim_t])
		print("  recovery: inverted=%s" % [str(inverted_recover)])
		print("  inputs:   roll=%+5.2f  pitch=%+5.2f  yaw=%+5.2f  thr=%.2f  firing=%s" % [
			roll_input, pitch_input, yaw_input, throttle_input, str(_dogfight_burst_active)])

func _reset_dogfight_precise_controllers() -> void:
	if _dogfight_precise_yaw_controller:
		_dogfight_precise_yaw_controller.reset()
	if _dogfight_precise_pitch_controller:
		_dogfight_precise_pitch_controller.reset()

func _clear_dogfight_lost_sight_behavior() -> void:
	_dogfight_lost_sight_behavior = DogfightLostSightBehavior.EFFICIENT
	_dogfight_lost_sight_timer_s = 0.0
	_dogfight_lost_sight_turn_sign = 0.0
	_dogfight_variation_waypoint = Vector3.ZERO

func _choose_dogfight_lost_sight_behavior(target_pos: Vector3, target_vel: Vector3, own_pos: Vector3, own_basis: Basis) -> void:
	_clear_dogfight_lost_sight_behavior()
	_dogfight_lost_sight_timer_s = randf_range(
		maxf(dogfight_lost_sight_behavior_min_s, 0.2),
		maxf(dogfight_lost_sight_behavior_max_s, maxf(dogfight_lost_sight_behavior_min_s, 0.2))
	)

	if randf() < clampf(dogfight_lost_sight_pursue_chance, 0.0, 1.0):
		return

	var alternate_target: Node3D = _find_alternate_dogfight_target()
	var branch_roll: float = randf()
	if alternate_target and branch_roll < 0.25:
		combat_target = alternate_target
		return

	if branch_roll < 0.50:
		_dogfight_lost_sight_behavior = DogfightLostSightBehavior.WRONG_TURN
		var to_target_flat: Vector3 = Vector3(target_pos.x - own_pos.x, 0.0, target_pos.z - own_pos.z).normalized()
		var toward_sign: float = signf(to_target_flat.dot(own_basis.x))
		if absf(toward_sign) < 0.01:
			toward_sign = -1.0 if randf() < 0.5 else 1.0
		_dogfight_lost_sight_turn_sign = -toward_sign
		return

	var forward: Vector3 = Vector3(own_basis.z.x, 0.0, own_basis.z.z)
	if forward.length_squared() < 0.0001:
		forward = Vector3(target_pos.x - own_pos.x, 0.0, target_pos.z - own_pos.z)
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, 1.0)
	forward = forward.normalized()
	var right: Vector3 = Vector3.UP.cross(forward).normalized()
	if right.length_squared() < 0.0001:
		right = Vector3(1.0, 0.0, 0.0)
	var side_sign: float = -1.0 if randf() < 0.5 else 1.0
	_dogfight_variation_waypoint = own_pos

	if branch_roll < 0.75:
		_dogfight_lost_sight_behavior = DogfightLostSightBehavior.CLIMB
		_dogfight_variation_waypoint += forward * randf_range(450.0, 850.0)
		_dogfight_variation_waypoint += right * side_sign * randf_range(180.0, 420.0)
		_dogfight_variation_waypoint.y = own_pos.y + randf_range(
			dogfight_variation_vertical_m * 0.8,
			dogfight_variation_vertical_m * 1.5
		)
	elif branch_roll < 0.90:
		_dogfight_lost_sight_behavior = DogfightLostSightBehavior.EXTEND
		_dogfight_variation_waypoint += forward * maxf(dogfight_lost_sight_extend_forward_m, 200.0)
		_dogfight_variation_waypoint += right * side_sign * randf_range(60.0, 180.0)
		_dogfight_variation_waypoint.y = own_pos.y + randf_range(40.0, maxf(dogfight_lost_sight_extend_vertical_m, 40.0))
	else:
		_dogfight_lost_sight_behavior = DogfightLostSightBehavior.OFFSET
		_dogfight_variation_waypoint += forward * randf_range(350.0, 650.0)
		_dogfight_variation_waypoint += right * side_sign * randf_range(
			dogfight_variation_lateral_m * 0.9,
			dogfight_variation_lateral_m * 1.4
		)
		_dogfight_variation_waypoint.y = own_pos.y + randf_range(
			-dogfight_variation_vertical_m * 0.35,
			dogfight_variation_vertical_m * 0.9
		)

	if altitude_agl < dogfight_ground_protect_agl_m:
		_dogfight_variation_waypoint.y = maxf(_dogfight_variation_waypoint.y, own_pos.y + dogfight_variation_vertical_m * 0.8)
	_dogfight_variation_waypoint += target_vel * 0.2
	_dogfight_variation_waypoint = _clamp_dogfight_upward_aim_point(own_pos, _dogfight_variation_waypoint)

func _find_alternate_dogfight_target() -> Node3D:
	var best_target: Node3D = null
	var best_distance: float = INF
	for enemy in known_enemies:
		if not is_instance_valid(enemy) or not (enemy is Node3D):
			continue
		var enemy_node: Node3D = enemy as Node3D
		if enemy_node == combat_target:
			continue
		if not _is_enemy_aircraft_target(enemy_node):
			continue
		if not _is_within_engagement_radius(enemy_node):
			continue
		var distance: float = aircraft.global_position.distance_to(enemy_node.global_position)
		if distance < best_distance:
			best_distance = distance
			best_target = enemy_node
	return best_target

func _should_switch_dogfight_target(current_target: Variant, candidate: Variant) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not (candidate is Node3D):
		return false
	if current_target == null or not is_instance_valid(current_target) or not (current_target is Node3D):
		return true
	if candidate == current_target:
		return false
	var current_node := current_target as Node3D
	var candidate_node := candidate as Node3D
	var current_dist: float = aircraft.global_position.distance_to(current_node.global_position)
	var candidate_dist: float = aircraft.global_position.distance_to(candidate_node.global_position)
	return candidate_dist + maxf(dogfight_retarget_advantage_m, 0.0) < current_dist

func _compute_dogfight_collision_avoidance(target_pos: Vector3, target_vel: Vector3, own_pos: Vector3, own_vel: Vector3) -> Vector3:
	"""Predict close pass and return an avoidance waypoint when needed."""
	var rel_pos: Vector3 = target_pos - own_pos
	var rel_vel: Vector3 = target_vel - own_vel
	var rel_speed_sq: float = rel_vel.length_squared()
	if rel_speed_sq < 1.0:
		return Vector3.ZERO

	var horizon: float = maxf(dogfight_collision_check_horizon_s, 0.1)
	var t_cpa: float = clampf(-rel_pos.dot(rel_vel) / rel_speed_sq, 0.0, horizon)
	var sep_vec: Vector3 = rel_pos + rel_vel * t_cpa
	var sep_dist: float = sep_vec.length()
	if sep_dist > dogfight_collision_min_sep_m:
		return Vector3.ZERO

	# Build an orthogonal break direction away from closure line.
	var closure_dir: Vector3 = rel_vel.normalized()
	var lateral: Vector3 = closure_dir.cross(Vector3.UP).normalized()
	if lateral.length() < 0.1:
		lateral = aircraft.global_transform.basis.x.normalized()
	var side_sign: float = 1.0 if lateral.dot(aircraft.global_transform.basis.x) >= 0.0 else -1.0
	if randf() < 0.5:
		side_sign *= -1.0

	var climb_sign: float = 1.0
	if altitude_agl > dogfight_ground_protect_agl_m * 1.5 and randf() < 0.35:
		climb_sign = -1.0

	var avoid_wp: Vector3 = own_pos + lateral * side_sign * dogfight_collision_escape_distance_m
	avoid_wp += aircraft.global_transform.basis.z.normalized() * 250.0
	avoid_wp.y = own_pos.y + dogfight_collision_escape_vertical_m * climb_sign
	if altitude_agl < dogfight_ground_protect_agl_m:
		avoid_wp.y = maxf(avoid_wp.y, own_pos.y + dogfight_collision_escape_vertical_m)
	return avoid_wp

func _start_dogfight_variation_maneuver(target_pos: Vector3, target_vel: Vector3, own_pos: Vector3, _now_s: float) -> void:
	"""Inject a short random maneuver to break endless turn loops."""
	var to_target: Vector3 = target_pos - own_pos
	var to_target_flat: Vector3 = Vector3(to_target.x, 0.0, to_target.z).normalized()
	if to_target_flat.length() < 0.01:
		to_target_flat = aircraft.global_transform.basis.z.normalized()
	var right: Vector3 = to_target_flat.cross(Vector3.UP).normalized()
	if right.length() < 0.01:
		right = aircraft.global_transform.basis.x.normalized()
	var side_sign: float = -1.0 if randf() < 0.5 else 1.0
	var vertical_sign: float = 1.0
	if altitude_agl > dogfight_ground_protect_agl_m * 1.8 and randf() < 0.4:
		vertical_sign = -1.0
	if altitude_agl < dogfight_ground_protect_agl_m:
		vertical_sign = 1.0

	var lateral_mag: float = dogfight_variation_lateral_m * randf_range(0.75, 1.2)
	var vertical_mag: float = dogfight_variation_vertical_m * randf_range(0.7, 1.25)
	var forward_mag: float = 300.0 + randf_range(0.0, 250.0)

	var wp: Vector3 = own_pos
	wp += to_target_flat * forward_mag
	wp += right * side_sign * lateral_mag
	wp.y += vertical_sign * vertical_mag
	if altitude_agl < dogfight_ground_protect_agl_m:
		wp.y = maxf(wp.y, own_pos.y + dogfight_variation_vertical_m * 0.8)

	# Mild target-motion bias keeps the maneuver relevant.
	wp += target_vel * 0.25
	wp = _clamp_dogfight_upward_aim_point(own_pos, wp)
	_dogfight_variation_waypoint = wp
	_dogfight_variation_timer_s = maxf(dogfight_variation_duration_s, 0.5)
	_dogfight_variation_cooldown_timer_s = maxf(dogfight_variation_cooldown_s, 0.5)
	_dogfight_stalemate_timer_s = 0.0

func _get_control_weapon_hardpoints() -> Array:
	if cached_hardpoints.is_empty() and control_weapons:
		var hardpoints_value = control_weapons.get("hardpoints")
		cached_hardpoints = hardpoints_value if hardpoints_value is Array else []
	return cached_hardpoints

func _get_control_weapon_types() -> Array:
	if not control_weapons:
		return []
	var weapon_types_value = control_weapons.get("weapon_types")
	return weapon_types_value if weapon_types_value is Array else []

func _get_selected_control_weapon_type() -> String:
	if not control_weapons:
		return ""
	var selected = control_weapons.get("selected_weapon_type")
	return "" if selected == null else String(selected)

func _set_selected_control_weapon_type(weapon_type: String) -> void:
	if control_weapons:
		control_weapons.set("selected_weapon_type", weapon_type)

func _select_dogfight_weapon(dist_to_target: float, target_in_sight: bool, to_target_dir: Vector3) -> void:
	"""Choose weapon for dogfight. Use missiles opportunistically, otherwise stay on guns."""
	if not control_weapons:
		return

	var gun_choice: String = _choose_non_bomb_weapon_type()
	if gun_choice == "AAMissile":
		gun_choice = ""
		for t in _get_control_weapon_types():
			var ts: String = String(t)
			if ts != "Bomb" and ts != "AAMissile":
				gun_choice = ts
				break
	if gun_choice.is_empty():
		gun_choice = _get_selected_control_weapon_type()

	var current_selection: String = _get_selected_control_weapon_type()

	if _dogfight_weapon_commit_timer_s > 0.0:
		if current_selection == "AAMissile" and _has_ready_dogfight_missile():
			_run_weapon_type = current_selection
			return
		if current_selection == gun_choice:
			_run_weapon_type = current_selection
			return

	var selected: String = gun_choice
	if _should_use_dogfight_missile(dist_to_target, target_in_sight, to_target_dir):
		selected = "AAMissile"
		_dogfight_weapon_commit_timer_s = maxf(dogfight_missile_commit_s, 0.2)
	else:
		_dogfight_weapon_commit_timer_s = 0.35

	_set_selected_control_weapon_type(selected)
	_run_weapon_type = selected

func _has_ready_dogfight_missile() -> bool:
	if _dogfight_has_active_missile():
		return false
	for hp in _get_control_weapon_hardpoints():
		if not hp or not hp.weapon_instance:
			continue
		if hp.weapon_instance.weapon_name != "AAMissile":
			continue
		if hp.weapon_instance.can_fire():
			return true
	return false

func _dogfight_has_active_missile() -> bool:
	return _dogfight_active_missile != null and is_instance_valid(_dogfight_active_missile)

func _sync_dogfight_missile_target(target_node) -> void:
	if not aircraft or not is_instance_valid(aircraft):
		return
	if not target_node or not is_instance_valid(target_node):
		return
	var aam_targeting: Node = control_targeting_aam
	if not aam_targeting or not is_instance_valid(aam_targeting):
		aam_targeting = aircraft.find_child("ControlTargeting_AAM", true, false)
		control_targeting_aam = aam_targeting
	if not aam_targeting or not is_instance_valid(aam_targeting):
		return
	aam_targeting.set("auto_replace_target", false)
	aam_targeting.set("required_lock_time", maxf(dogfight_missile_required_lock_s, 0.0))
	var current_max_range = aam_targeting.get("max_range_m")
	if current_max_range != null:
		aam_targeting.set("max_range_m", maxf(float(current_max_range), dogfight_missile_max_range_m))
	var current_target = aam_targeting.get("current_target")
	if current_target != null and not is_instance_valid(current_target):
		aam_targeting.set("current_target", null)
		current_target = null
	if current_target != target_node and aam_targeting.has_method("set_target"):
		aam_targeting.set_target(target_node)

func _should_use_dogfight_missile(dist_to_target: float, target_in_sight: bool, to_target_dir: Vector3) -> bool:
	if not _has_ready_dogfight_missile():
		return false
	if not target_in_sight:
		return false
	if dist_to_target < maxf(dogfight_missile_min_range_m, dogfight_gun_preferred_range_m):
		return false
	if dist_to_target > maxf(dogfight_missile_max_range_m, dogfight_missile_min_range_m):
		return false

	var forward: Vector3 = aircraft.global_transform.basis.z.normalized()
	var off_boresight_cos: float = cos(deg_to_rad(clampf(dogfight_missile_max_off_boresight_deg, 1.0, 89.0)))
	if forward.dot(to_target_dir) < off_boresight_cos:
		return false

	var range_t: float = clampf(
		(dist_to_target - dogfight_missile_min_range_m) / maxf(dogfight_missile_max_range_m - dogfight_missile_min_range_m, 1.0),
		0.0,
		1.0
	)
	var chance: float = clampf(dogfight_missile_use_chance, 0.0, 1.0)
	chance = lerpf(chance * 0.55, maxf(chance, 0.8), range_t)
	return randf() < chance

func _get_selected_gun_muzzle_velocity() -> float:
	var selected_muzzle_velocity_mps: float = dogfight_default_muzzle_velocity_mps
	if not control_weapons:
		return _get_effective_projectile_speed_mps(selected_muzzle_velocity_mps)
	var selected: String = _get_selected_control_weapon_type()
	if selected.is_empty():
		selected = "Autocannon"
	for hp in _get_control_weapon_hardpoints():
		if not hp or not hp.weapon_instance:
			continue
		var wname: String = String(hp.weapon_instance.weapon_name)
		if wname != selected:
			continue
		if "muzzle_velocity" in hp.weapon_instance:
			selected_muzzle_velocity_mps = maxf(float(hp.weapon_instance.muzzle_velocity), 50.0)
			break
	return _get_effective_projectile_speed_mps(selected_muzzle_velocity_mps)

func _get_selected_gun_max_range_m() -> float:
	if not control_weapons:
		return INF
	var selected: String = _get_selected_control_weapon_type()
	if selected.is_empty():
		selected = "Autocannon"
	var best_range_m: float = -1.0
	for hp in _get_control_weapon_hardpoints():
		if not hp or not hp.weapon_instance:
			continue
		var wname: String = String(hp.weapon_instance.weapon_name)
		if wname != selected:
			continue
		var range_variant: Variant = hp.weapon_instance.get("max_range_m")
		if typeof(range_variant) in [TYPE_FLOAT, TYPE_INT]:
			best_range_m = maxf(best_range_m, maxf(float(range_variant), 1.0))
	if best_range_m > 0.0:
		return best_range_m
	return INF

func _get_effective_projectile_speed_mps(nominal_speed_mps: float) -> float:
	var speed_cap_mps: float = _get_projectile_linear_speed_cap_mps()
	if is_finite(speed_cap_mps):
		return maxf(minf(nominal_speed_mps, speed_cap_mps), 50.0)
	return maxf(nominal_speed_mps, 50.0)

func _get_projectile_linear_speed_cap_mps() -> float:
	if _projectile_speed_cap_cached:
		return _projectile_speed_cap_mps
	_projectile_speed_cap_cached = true
	_projectile_speed_cap_mps = INF
	for key_variant in PROJECTILE_SPEED_CAP_SETTING_KEYS:
		var key: String = str(key_variant)
		if not ProjectSettings.has_setting(key):
			continue
		var cap_variant: Variant = ProjectSettings.get_setting(key)
		if typeof(cap_variant) in [TYPE_FLOAT, TYPE_INT]:
			var cap_mps: float = float(cap_variant)
			if cap_mps > 0.0:
				_projectile_speed_cap_mps = cap_mps
				break
	return _projectile_speed_cap_mps

func _get_selected_weapon_mount_info() -> Dictionary:
	var default_forward: Vector3 = aircraft.global_transform.basis.z.normalized()
	var mount_info := {
		"origin": aircraft.global_position,
		"forward": default_forward,
		"spread_deg": 1.0,
	}
	if not control_weapons:
		return mount_info

	var selected: String = _get_selected_control_weapon_type()
	if selected.is_empty():
		selected = "Autocannon"

	var count: int = 0
	var avg_origin: Vector3 = Vector3.ZERO
	var avg_forward: Vector3 = Vector3.ZERO
	for hp in _get_control_weapon_hardpoints():
		if not hp or not hp.weapon_instance:
			continue
		if String(hp.weapon_instance.weapon_name) != selected:
			continue
		avg_origin += hp.global_position
		avg_forward += hp.get_hardpoint_forward_direction().normalized()
		count += 1
		if "spread_angle" in hp.weapon_instance:
			mount_info["spread_deg"] = float(hp.weapon_instance.spread_angle)

	if count <= 0:
		return mount_info

	mount_info["origin"] = avg_origin / float(count)
	if avg_forward.length_squared() > 0.001:
		mount_info["forward"] = avg_forward.normalized()
	return mount_info

func _get_point_velocity_at_world_position(world_pos: Vector3) -> Vector3:
	if not aircraft:
		return Vector3.ZERO
	var point_velocity: Vector3 = aircraft.linear_velocity
	var r_offset: Vector3 = world_pos - aircraft.global_position
	point_velocity += aircraft.angular_velocity.cross(r_offset)
	return point_velocity

func _get_dogfight_aim_solution(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3, target_vel: Vector3, projectile_speed: float) -> Dictionary:
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - ballistic_cache_time < ballistic_cache_duration and not cached_ballistic_solution.is_empty():
		var cached_solution: Dictionary = cached_ballistic_solution.duplicate()
		var cached_intercept: Vector3 = cached_solution.get("intercept_point", target_pos)
		cached_intercept = _clamp_dogfight_upward_aim_point(shooter_pos, cached_intercept)
		var cached_aim_point: Vector3 = cached_solution.get("aim_point", cached_intercept)
		cached_aim_point = _clamp_dogfight_upward_aim_point(shooter_pos, cached_aim_point)
		cached_solution["intercept_point"] = cached_intercept
		cached_solution["aim_point"] = cached_aim_point
		return cached_solution

	var intercept_point: Vector3 = _predict_lead_point(shooter_pos, shooter_vel, target_pos, target_vel, projectile_speed)
	var tof_guess: float = maxf(shooter_pos.distance_to(intercept_point) / maxf(projectile_speed, 50.0), 0.05)
	var solution := {
		"aim_point": intercept_point,
		"intercept_point": intercept_point,
		"tof": tof_guess,
	}

	if _is_selected_dogfight_missile():
		var missile_intercept: Vector3 = _clamp_dogfight_upward_aim_point(shooter_pos, intercept_point)
		var missile_aim_point: Vector3 = _clamp_dogfight_upward_aim_point(shooter_pos, solution.get("aim_point", missile_intercept))
		solution["intercept_point"] = missile_intercept
		solution["aim_point"] = missile_aim_point
		return solution

	solution = _predict_ballistic_aim_solution(shooter_pos, shooter_vel, target_pos, target_vel, projectile_speed)
	var clamped_intercept: Vector3 = _clamp_dogfight_upward_aim_point(shooter_pos, solution.get("intercept_point", intercept_point))
	var clamped_aim_point: Vector3 = _clamp_dogfight_upward_aim_point(shooter_pos, solution.get("aim_point", clamped_intercept))
	solution["intercept_point"] = clamped_intercept
	solution["aim_point"] = clamped_aim_point
	cached_ballistic_solution = solution.duplicate()
	ballistic_cache_time = current_time
	return solution

func _is_selected_dogfight_missile() -> bool:
	return _get_selected_control_weapon_type() == "AAMissile"

func _get_world_gravity_vector() -> Vector3:
	var gravity_dir: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3(0, -1, 0))
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	return gravity_dir * gravity_mag

func _solve_intercept_time_no_gravity(relative_pos: Vector3, relative_vel: Vector3, projectile_speed: float) -> float:
	var speed_sq: float = projectile_speed * projectile_speed
	var a: float = relative_vel.length_squared() - speed_sq
	var b: float = 2.0 * relative_pos.dot(relative_vel)
	var c: float = relative_pos.length_squared()

	if absf(a) <= 0.0001:
		if absf(b) <= 0.0001:
			return -1.0
		var linear_t: float = -c / b
		return linear_t if linear_t > 0.0 else -1.0

	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0

	var sqrt_discriminant: float = sqrt(discriminant)
	var inv_2a: float = 0.5 / a
	var t0: float = (-b - sqrt_discriminant) * inv_2a
	var t1: float = (-b + sqrt_discriminant) * inv_2a

	var best_t: float = INF
	if t0 > 0.0 and t0 < best_t:
		best_t = t0
	if t1 > 0.0 and t1 < best_t:
		best_t = t1

	return -1.0 if best_t == INF else best_t

func _predict_ballistic_aim_solution(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3, target_vel: Vector3, projectile_speed: float) -> Dictionary:
	var muzzle_speed: float = maxf(projectile_speed, 50.0)
	var gravity_vec: Vector3 = _get_world_gravity_vector()
	var relative_pos: Vector3 = target_pos - shooter_pos
	var relative_vel: Vector3 = target_vel - shooter_vel
	var min_tof: float = 0.05
	var distance_estimate: float = relative_pos.length()
	var solver_max_tof: float = clampf(distance_estimate / muzzle_speed * 2.0, 0.35, 6.0)
	var best_t: float = _solve_intercept_time_no_gravity(relative_pos, relative_vel, muzzle_speed)
	if best_t <= 0.0:
		best_t = distance_estimate / muzzle_speed
	best_t = clampf(best_t, min_tof, solver_max_tof)
	var best_intercept: Vector3 = target_pos + target_vel * best_t
	var best_muzzle_vec: Vector3 = Vector3.ZERO

	# Refine time-of-flight with gravity by matching required muzzle speed.
	for _i in range(5):
		var future_target: Vector3 = target_pos + target_vel * best_t
		var required_muzzle_vec: Vector3 = (future_target - shooter_pos - shooter_vel * best_t - 0.5 * gravity_vec * best_t * best_t) / best_t
		var required_speed: float = required_muzzle_vec.length()
		if required_speed <= 0.0001:
			break

		best_intercept = future_target
		best_muzzle_vec = required_muzzle_vec

		var speed_error: float = required_speed - muzzle_speed
		if absf(speed_error) <= 0.5:
			break

		best_t = clampf(best_t * (required_speed / muzzle_speed), min_tof, solver_max_tof)

	if best_muzzle_vec.length_squared() < 1.0:
		var fallback_intercept: Vector3 = _predict_lead_point(shooter_pos, shooter_vel, target_pos, target_vel, projectile_speed)
		var fallback_t: float = maxf(shooter_pos.distance_to(fallback_intercept) / muzzle_speed, min_tof)
		return {
			"aim_point": fallback_intercept,
			"intercept_point": fallback_intercept,
			"tof": fallback_t,
		}

	var launch_dir: Vector3 = best_muzzle_vec.normalized()
	var aim_dist: float = maxf((best_intercept - shooter_pos).length(), 100.0)
	var aim_point: Vector3 = shooter_pos + launch_dir * aim_dist
	return {
		"aim_point": aim_point,
		"intercept_point": best_intercept,
		"tof": best_t,
	}

func _predict_lead_point(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3, target_vel: Vector3, projectile_speed: float) -> Vector3:
	"""First-order interception point for constant-velocity target."""
	var rel_pos: Vector3 = target_pos - shooter_pos
	var effective_projectile_speed: float = maxf(projectile_speed, 50.0)
	var rel_vel: Vector3 = target_vel - shooter_vel
	var a: float = rel_vel.dot(rel_vel) - effective_projectile_speed * effective_projectile_speed
	var b: float = 2.0 * rel_pos.dot(rel_vel)
	var c: float = rel_pos.dot(rel_pos)
	var t: float = 0.0

	if absf(a) < 0.001:
		if absf(b) > 0.001:
			t = maxf(-c / b, 0.0)
	else:
		var disc: float = b * b - 4.0 * a * c
		if disc >= 0.0:
			var sqrt_disc: float = sqrt(disc)
			var t1: float = (-b - sqrt_disc) / (2.0 * a)
			var t2: float = (-b + sqrt_disc) / (2.0 * a)
			var t_min: float = INF
			if t1 > 0.0:
				t_min = min(t_min, t1)
			if t2 > 0.0:
				t_min = min(t_min, t2)
			if t_min < INF:
				t = t_min

	if t <= 0.0:
		t = rel_pos.length() / effective_projectile_speed
	return target_pos + target_vel * t

func _predict_dogfight_projectile_position(shooter_pos: Vector3, shooter_vel: Vector3, aim_dir: Vector3, muzzle_velocity: float, tof: float) -> Vector3:
	return shooter_pos \
		+ shooter_vel * tof \
		+ aim_dir * maxf(muzzle_velocity, 50.0) * tof \
		+ 0.5 * _get_world_gravity_vector() * tof * tof

func _dogfight_has_good_fire_solution(
	aim_point: Vector3,
	intercept_point: Vector3,
	shooter_pos: Vector3,
	shooter_vel: Vector3,
	muzzle_forward: Vector3,
	muzzle_velocity: float,
	spread_deg: float,
	tof: float,
	dist_to_target: float
) -> bool:
	if _get_selected_control_weapon_type() == "AAMissile":
		for hp in _get_control_weapon_hardpoints():
			if hp and hp.weapon_instance and hp.weapon_instance.weapon_name == "AAMissile":
				return hp.weapon_instance.can_fire()
		return false
	
	var gun_max_range_m: float = _get_selected_gun_max_range_m()
	if is_finite(gun_max_range_m) and dist_to_target > gun_max_range_m:
		return false
	var darkness: float = _get_ai_darkness_factor()
	var effective_dogfight_max_range_m: float = dogfight_max_range_m * lerpf(1.0, night_dogfight_max_range_multiplier, darkness)
	if dist_to_target > effective_dogfight_max_range_m:
		return false
	var to_aim: Vector3 = aim_point - shooter_pos
	var aim_dist: float = to_aim.length()
	if aim_dist < 1.0:
		return false
	var aim_dir: Vector3 = to_aim / aim_dist
	var fwd: Vector3 = muzzle_forward.normalized()
	if fwd.length_squared() < 0.001:
		fwd = aircraft.global_transform.basis.z.normalized()
	var close_relax_range: float = maxf(dogfight_fire_close_relax_range_m, 50.0)
	var close_t: float = 1.0 - clampf(dist_to_target / close_relax_range, 0.0, 1.0)
	var required_dot: float = lerpf(
		clampf(dogfight_min_aim_dot, -1.0, 1.0),
		clampf(dogfight_fire_close_relax_min_dot, -1.0, 1.0),
		close_t
	)
	var required_hit_chance: float = lerpf(
		clampf(dogfight_min_hit_chance, 0.0, 1.0),
		clampf(dogfight_fire_close_relax_min_hit_chance, 0.0, 1.0),
		close_t
	)
	required_hit_chance = clampf(required_hit_chance + night_fire_hit_chance_bonus * darkness, 0.0, 0.98)
	var dot: float = clampf(fwd.dot(aim_dir), -1.0, 1.0)
	if dot < required_dot:
		return false

	var predicted_impact: Vector3 = _predict_dogfight_projectile_position(
		shooter_pos,
		shooter_vel,
		aim_dir,
		muzzle_velocity,
		maxf(tof, 0.05)
	)
	var miss_radius: float = predicted_impact.distance_to(intercept_point)
	var spread_radius: float = tan(deg_to_rad(maxf(spread_deg, 0.1))) * shooter_pos.distance_to(predicted_impact)
	var hit_envelope: float = dogfight_target_radius_m + spread_radius
	var hit_chance: float = clampf(1.0 - (miss_radius / maxf(hit_envelope, 0.1)), 0.0, 1.0)

	# Also require finite bullet time-of-flight to avoid very stale lead.
	var max_tof: float = maxf(dogfight_fire_max_tof_s * lerpf(1.0, night_fire_max_tof_multiplier, darkness), 0.1)
	return hit_chance >= required_hit_chance and tof <= max_tof

func _update_dogfight_burst_timers(delta: float, fire_solution_good: bool) -> void:
	_dogfight_burst_timer_s = maxf(0.0, _dogfight_burst_timer_s - delta)
	_dogfight_burst_cooldown_timer_s = maxf(0.0, _dogfight_burst_cooldown_timer_s - delta)

	if _dogfight_burst_active:
		if not fire_solution_good:
			_dogfight_burst_active = false
			_dogfight_burst_timer_s = 0.0
			_dogfight_burst_cooldown_timer_s = maxf(_dogfight_burst_cooldown_timer_s, dogfight_burst_cooldown_s)
			return
		if _dogfight_burst_timer_s <= 0.0:
			_dogfight_burst_active = false
			_dogfight_burst_cooldown_timer_s = dogfight_burst_cooldown_s
		return

	if fire_solution_good and _dogfight_burst_cooldown_timer_s <= 0.0:
		_dogfight_burst_active = true
		_dogfight_burst_timer_s = dogfight_fire_burst_s

func _fire_guns():
	"""Trigger weapon fire via ControlWeapons."""
	if not control_weapons:
		return
	var weapon_type: String = _get_selected_control_weapon_type()
	if weapon_type == "AAMissile":
		_fire_one_weapon_of_type(weapon_type)
		return
	if control_weapons.has_method("fire_automatic_weapons_of_type"):
		if weapon_type.is_empty():
			var weapon_types: Array = _get_control_weapon_types()
			if weapon_types.size() > 0:
				weapon_type = String(weapon_types[0])
		if not weapon_type.is_empty():
			control_weapons.fire_automatic_weapons_of_type(weapon_type)
	elif control_weapons.has_method("fire_selected_weapon_type"):
		control_weapons.fire_selected_weapon_type()

func _fire_one_weapon_of_type(weapon_type: String) -> void:
	_fire_one_weapon_of_type_with_result(weapon_type)

func _fire_one_weapon_of_type_with_result(weapon_type: String) -> bool:
	for hp in _get_control_weapon_hardpoints():
		if not hp or not hp.weapon_instance:
			continue
		if hp.weapon_instance.weapon_name != weapon_type:
			continue
		if hp.weapon_instance.can_fire() and hp.fire():
			if weapon_type == "AAMissile":
				var launched_missile = hp.weapon_instance.get("last_fired_missile")
				if launched_missile != null and is_instance_valid(launched_missile):
					_dogfight_active_missile = launched_missile as Node3D
			return true
	return false

func _plan_attack_run_weapon() -> void:
	"""Choose one weapon profile for this run. Prefer bombs when available."""
	# Capture outcome of the previous run before resetting
	var just_failed_bomb_run: bool = (_run_weapon_type == "Bomb" and _bombs_dropped_this_run == 0 and _bombs_to_drop_this_run > 0)
	# One-run skip after a failed bomb run; reset after a non-bomb run so bombs get another chance
	if _run_weapon_type != "Bomb":
		_prev_run_was_failed_bomb = false
	elif just_failed_bomb_run:
		_prev_run_was_failed_bomb = true
	else:
		_prev_run_was_failed_bomb = false

	_run_weapon_type = "Autocannon"
	_bombs_to_drop_this_run = 0
	_bombs_dropped_this_run = 0
	_last_bomb_drop_time_s = -INF
	_rockets_to_fire_this_run = 0
	_rockets_fired_this_run = 0
	_last_rocket_fire_time_s = -INF
	_prev_ccip_miss = INF
	_ccip_cache_timer = 0.0
	_ccip_cached_result = Vector3.ZERO
	_ccip_cached_tof_s = -1.0
	_best_bomb_ccip_miss_this_run = INF
	_reset_release_solution_stability()
	if not control_weapons:
		return

	var bomb_ready: int = _count_ready_bombs()
	var rockets_ready: int = _count_ready_rockets()

	if debug_enabled:
		var hps: Array = _get_control_weapon_hardpoints()
		print("[WEAPON SELECT] %s  hardpoints=%d  bomb_ready=%d  rockets_ready=%d  prev_failed_bomb=%s" % [
			aircraft.name, hps.size(), bomb_ready, rockets_ready, str(_prev_run_was_failed_bomb)])
		for hp in hps:
			if hp and hp.weapon_instance:
				print("  hp: %s  weapon=%s  ammo=%s  can_fire=%s" % [
					hp.name, hp.weapon_instance.weapon_name,
					str(hp.weapon_instance.get("ammo_count")),
					str(hp.weapon_instance.can_fire())])

	# Keep preferring bombs against the carrier so strike aircraft actually shed their heavy payloads.
	# For non-carrier targets, still allow a one-run fallback to rockets after a failed bomb pass.
	var force_bombs_for_target: bool = _is_carrier_attack_target(combat_target)
	var allow_bomb_run: bool = bomb_ready > 0 and (force_bombs_for_target or not _prev_run_was_failed_bomb)
	if allow_bomb_run:
		_run_weapon_type = "Bomb"
		var total_ammo: int = _get_total_bomb_ammo()
		var planned_bomb_count: int = maxi(bomb_salvo_per_run, 1)
		if force_bombs_for_target:
			planned_bomb_count = maxi(carrier_bomb_salvo_per_run, planned_bomb_count)
		_bombs_to_drop_this_run = min(planned_bomb_count, total_ammo)
	else:
		if rockets_ready > 0:
			_run_weapon_type = "Rocket Pod"
			var total_rocket_ammo: int = _get_total_rocket_ammo()
			_rockets_to_fire_this_run = min(maxi(rocket_shots_per_run, 1), total_rocket_ammo)
		else:
			_run_weapon_type = _choose_non_bomb_weapon_type()

	if debug_enabled:
		print("[WEAPON SELECT] -> %s  bombs_planned=%d  rockets_planned=%d  force_bombs=%s" % [
			_run_weapon_type, _bombs_to_drop_this_run, _rockets_to_fire_this_run, str(force_bombs_for_target)])
	_set_selected_control_weapon_type(_run_weapon_type)

func _choose_non_bomb_weapon_type() -> String:
	if not control_weapons:
		return ""
	var types: Array = _get_control_weapon_types()
	if types.is_empty():
		return ""
	var fallback_gun: String = ""
	for t in types:
		var weapon_type: String = String(t)
		if weapon_type == "Bomb":
			continue
		if weapon_type == "AAMissile":
			continue
		if weapon_type == "Rocket Pod":
			continue
		if weapon_type.to_lower().find("autocannon") != -1:
			return weapon_type
		if fallback_gun.is_empty():
			fallback_gun = weapon_type
	if not fallback_gun.is_empty():
		return fallback_gun
	if types.has("AAMissile"):
		return "AAMissile"
	for t in types:
		var any_non_bomb: String = String(t)
		if any_non_bomb != "Bomb":
			return any_non_bomb
	return ""

func _count_ready_bombs() -> int:
	"""Number of hardpoints with a Bomb weapon that can fire (for quick availability check)."""
	var count: int = 0
	for hp in _get_control_weapon_hardpoints():
		if not hp or not hp.weapon_instance:
			continue
		if hp.weapon_instance.weapon_name != "Bomb":
			continue
		if hp.weapon_instance.can_fire():
			count += 1
	return count

func _get_total_bomb_ammo() -> int:
	"""Total ammo across all bomb dispensers (bombs can have 50+ shots each)."""
	var total: int = 0
	for hp in _get_control_weapon_hardpoints():
		if not hp or not hp.weapon_instance:
			continue
		if hp.weapon_instance.weapon_name != "Bomb":
			continue
		if "ammo_count" in hp.weapon_instance:
			total += int(hp.weapon_instance.ammo_count)
	return total

func _count_ready_rockets() -> int:
	var count: int = 0
	for hp in _get_control_weapon_hardpoints():
		if not hp or not hp.weapon_instance:
			continue
		if hp.weapon_instance.weapon_name != "Rocket Pod":
			continue
		if hp.weapon_instance.can_fire():
			count += 1
	return count

func _get_total_rocket_ammo() -> int:
	var total: int = 0
	for hp in _get_control_weapon_hardpoints():
		if not hp or not hp.weapon_instance:
			continue
		if hp.weapon_instance.weapon_name != "Rocket Pod":
			continue
		if "ammo_count" in hp.weapon_instance:
			total += int(hp.weapon_instance.ammo_count)
	return total

func _handle_bomb_release_run(aim_pos: Vector3, target_pos: Vector3, ccip_predicted: Vector3 = Vector3.ZERO, current_target_pos: Vector3 = Vector3.ZERO) -> void:
	if _bombs_to_drop_this_run <= 0:
		return
	if _bombs_dropped_this_run >= _bombs_to_drop_this_run:
		return
	var now_s: float = Time.get_ticks_msec() / 1000.0
	var drop_spacing_ready: bool = now_s - _last_bomb_drop_time_s >= bomb_release_spacing_s

	var alt_above_target: float = aircraft.global_position.y - target_pos.y
	var horiz_dist_to_target: float = Vector2(aircraft.global_position.x - target_pos.x, aircraft.global_position.z - target_pos.z).length()
	# Safety window: never release outside 5ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ600m above target
	if alt_above_target > bomb_release_altitude_window_m or alt_above_target < 5.0 or horiz_dist_to_target < bomb_release_min_range_m:
		_is_release_solution_stable_enough(now_s, false)
		return
	# Must be descending
	var horiz_speed: float = Vector2(aircraft.linear_velocity.x, aircraft.linear_velocity.z).length()
	var fpa_deg: float = rad_to_deg(atan2(-aircraft.linear_velocity.y, max(horiz_speed, 1.0)))
	if fpa_deg < bomb_min_dive_angle_deg:
		_is_release_solution_stable_enough(now_s, false)
		return  # Not in a real dive yet ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â CCIP is unreliable at shallow angles

	# CCIP release: hold until predicted impact is close enough to target.
	# If CCIP failed (Vector3.ZERO ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â no terrain found), release immediately.
	var pred_err_h: float = -1.0
	var led_pred_err_h: float = -1.0
	var current_pred_err_h: float = -1.0
	var ccip_good: bool = false
	var release_at_best_solution: bool = false
	if ccip_predicted != Vector3.ZERO:
		led_pred_err_h = Vector2(target_pos.x - ccip_predicted.x, target_pos.z - ccip_predicted.z).length()
		if current_target_pos == Vector3.ZERO:
			current_target_pos = target_pos
		current_pred_err_h = Vector2(current_target_pos.x - ccip_predicted.x, current_target_pos.z - ccip_predicted.z).length()
		pred_err_h = led_pred_err_h
		if _is_carrier_attack_target(combat_target):
			pred_err_h = minf(led_pred_err_h, current_pred_err_h)
		var release_tolerance_m: float = _get_effective_bomb_release_tolerance_m()
		var previous_miss_m: float = _prev_ccip_miss
		var previous_best_miss_m: float = _best_bomb_ccip_miss_this_run
		release_at_best_solution = _is_bomb_best_solution_release_moment(pred_err_h, previous_miss_m, previous_best_miss_m, release_tolerance_m)
		var best_with_current_m: float = minf(previous_best_miss_m, pred_err_h)
		var near_best_solution: bool = pred_err_h <= best_with_current_m + maxf(bomb_release_best_miss_slack_m, 0.0)
		ccip_good = (pred_err_h <= release_tolerance_m and near_best_solution) or release_at_best_solution
		_prev_ccip_miss = pred_err_h
		_best_bomb_ccip_miss_this_run = best_with_current_m
	var bank_ok: bool = _get_current_bank_angle_deg() <= bomb_release_max_bank_deg
	if not drop_spacing_ready:
		return
	var release_hold_s: float = 0.0 if release_at_best_solution else _get_effective_bomb_release_hold_s()
	if not _is_release_solution_stable_enough(now_s, ccip_good and bank_ok, release_hold_s):
		return

	var bomb_released: bool = _drop_one_bomb(target_pos, ccip_predicted)
	if bomb_released:
		_bombs_dropped_this_run += 1
		_last_bomb_drop_time_s = now_s

		if debug_enabled:
			var hdist: float = Vector2(aircraft.global_position.x - target_pos.x, aircraft.global_position.z - target_pos.z).length()
			var spd: float = aircraft.linear_velocity.length()
			var fpa_at_drop: float = rad_to_deg(atan2(-aircraft.linear_velocity.y, max(horiz_speed, 1.0)))
			var miss_str: String = " miss=%.1fm led=%.1fm cur=%.1fm" % [pred_err_h, led_pred_err_h, current_pred_err_h] if ccip_predicted != Vector3.ZERO else " miss=no-ccip"
			var target_range_now: float = aircraft.global_position.distance_to(_get_surface_target_position(combat_target)) if combat_target and is_instance_valid(combat_target) else hdist
			print("[AIPilot RELEASE] %s type=Bomb count=%d/%d alt_above=%.1fm hdist=%.1fm current_range=%.1fm spd=%.1fm/s fpa=%.1fdeg%s" % [
				aircraft.name,
				_bombs_dropped_this_run,
				_bombs_to_drop_this_run,
				alt_above_target,
				hdist,
				target_range_now,
				spd,
				fpa_at_drop,
				miss_str
			])
	elif debug_enabled:
		print("[AIPilot RELEASE_FAIL] %s type=Bomb reason=no_ready_bomb miss=%.1fm desired=%d dropped=%d" % [
			aircraft.name,
			pred_err_h,
			_bombs_to_drop_this_run,
			_bombs_dropped_this_run
		])

func _drop_one_bomb(target_pos: Vector3 = Vector3.ZERO, ccip_predicted: Vector3 = Vector3.ZERO) -> bool:
	for hp in _get_control_weapon_hardpoints():
		if not hp or not hp.weapon_instance:
			continue
		if hp.weapon_instance.weapon_name != "Bomb":
			continue
		if not hp.weapon_instance.can_fire():
			continue
		var attach_bomb_debug_metadata: bool = debug_enabled and verbose_debug_enabled
		if attach_bomb_debug_metadata and hp.weapon_instance.has_method("set_next_bomb_debug_metadata"):
			hp.weapon_instance.set_next_bomb_debug_metadata(target_pos, ccip_predicted)
		if hp.fire():
			var dropped_bomb_variant: Variant = hp.weapon_instance.get("last_bomb_dropped")
			if attach_bomb_debug_metadata and dropped_bomb_variant != null and dropped_bomb_variant is Object and is_instance_valid(dropped_bomb_variant) and dropped_bomb_variant is BombProjectile:
				var dropped_bomb: BombProjectile = dropped_bomb_variant
				dropped_bomb.set_meta("debug_aim_target", target_pos)
				dropped_bomb.set_meta("debug_predicted_impact", ccip_predicted)
			return true
	return false

func _handle_rocket_release_run(aim_pos: Vector3, target_pos: Vector3, ccip_predicted: Vector3 = Vector3.ZERO) -> void:
	if _rockets_to_fire_this_run <= 0:
		return
	if _rockets_fired_this_run >= _rockets_to_fire_this_run:
		return

	var now_s: float = Time.get_ticks_msec() / 1000.0
	if now_s - _last_rocket_fire_time_s < rocket_release_spacing_s:
		return

	var horiz_dist: float = Vector2(aircraft.global_position.x - target_pos.x, aircraft.global_position.z - target_pos.z).length()
	if horiz_dist > rocket_release_max_range_m or horiz_dist < rocket_release_min_range_m:
		_is_release_solution_stable_enough(now_s, false)
		return

	var fwd: Vector3 = aircraft.global_transform.basis.z.normalized()
	# Use raw target direction for alignment â€” CCIP correction on aim_pos can be large for
	# a moving target, which would falsely fail alignment even when pointing at the carrier.
	var to_target_dir: Vector3 = (target_pos - aircraft.global_position).normalized()
	var required_dot: float = cos(deg_to_rad(maxf(rocket_fire_alignment_deg, 1.0)))
	var alignment_ok: bool = fwd.dot(to_target_dir) >= required_dot
	if ccip_predicted == Vector3.ZERO:
		_is_release_solution_stable_enough(now_s, false)
		return
	var pred_err_h: float = Vector2(target_pos.x - ccip_predicted.x, target_pos.z - ccip_predicted.z).length()
	_prev_ccip_miss = pred_err_h
	var effective_rocket_tolerance_m: float = rocket_ccip_release_tolerance_m \
		* lerpf(1.0, night_rocket_release_tolerance_multiplier, _get_ai_darkness_factor())
	var ccip_ok: bool = pred_err_h <= effective_rocket_tolerance_m
	var bank_ok: bool = _get_current_bank_angle_deg() <= rocket_release_max_bank_deg
	if not _is_release_solution_stable_enough(now_s, alignment_ok and ccip_ok and bank_ok):
		return

	if _fire_one_weapon_of_type_with_result("Rocket Pod"):
		_rockets_fired_this_run += 1
		_last_rocket_fire_time_s = now_s
		if debug_enabled:
			var pred_err_h_debug: float = Vector2(target_pos.x - ccip_predicted.x, target_pos.z - ccip_predicted.z).length() if ccip_predicted != Vector3.ZERO else -1.0
			var miss_str: String = " miss=%.1fm" % pred_err_h_debug if ccip_predicted != Vector3.ZERO else " miss=n/a"
			print("[AIPilot RELEASE] %s type=Rocket count=%d/%d range=%.0fm%s" % [
				aircraft.name,
				_rockets_fired_this_run,
				_rockets_to_fire_this_run,
				horiz_dist,
				miss_str
			])

func _predict_rocket_impact_solution() -> Dictionary:
	if aircraft == null or not is_instance_valid(aircraft):
		return {}
	if not aircraft.has_method("calculate_rocket_ccip_impact_point"):
		return {}
	var result: Variant = aircraft.calculate_rocket_ccip_impact_point()
	if result is Dictionary:
		return result
	return {}

func _predict_rocket_impact_point() -> Vector3:
	var result: Dictionary = _predict_rocket_impact_solution()
	if bool(result.get("has_impact", false)):
		var impact_variant: Variant = result.get("impact_position", Vector3.ZERO)
		if impact_variant is Vector3:
			return impact_variant
	return Vector3.ZERO

func _predict_bomb_impact_solution(
	log_debug: bool = false,
	moving_target_pos: Vector3 = Vector3.ZERO,
	moving_target_velocity: Vector3 = Vector3.ZERO,
	use_moving_target_plane: bool = false
) -> Dictionary:
	"""Estimate bomb impact point and time of flight using ballistic simulation.
	The Terrain3D plugin doesn't register physics collision for raycasts,
	so we use Terrain3D.get_height() as the primary detection method ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â
	the same fallback used by projectile_new.gd."""
	var start_pos: Vector3 = aircraft.global_position
	var drop_force: float = 0.0
	var bomb_projectile_scene: PackedScene = null

	for hp in _get_control_weapon_hardpoints():
		if hp and hp.weapon_instance and hp.weapon_instance.weapon_name == "Bomb":
			if "drop_force" in hp.weapon_instance:
				drop_force = float(hp.weapon_instance.drop_force)
			if "bomb_projectile_scene" in hp.weapon_instance and hp.weapon_instance.bomb_projectile_scene:
				bomb_projectile_scene = hp.weapon_instance.bomb_projectile_scene
				if hp.weapon_instance.has_method("get_predicted_release_transform"):
					start_pos = hp.weapon_instance.get_predicted_release_transform().origin
				else:
					start_pos = hp.global_position
			break

	var current_vel: Vector3 = Vector3.DOWN * drop_force + aircraft.linear_velocity
	for hp in _get_control_weapon_hardpoints():
		if hp and hp.weapon_instance and hp.weapon_instance.weapon_name == "Bomb":
			if hp.weapon_instance.has_method("get_predicted_initial_velocity"):
				current_vel = hp.weapon_instance.get_predicted_initial_velocity(aircraft)
			break

	var linear_damp: float = 0.0
	var gravity_scale: float = 1.0
	if _cached_bomb_linear_damp >= 0.0:
		# Use cached values from previous instantiation
		linear_damp = _cached_bomb_linear_damp
		gravity_scale = _cached_bomb_gravity_scale
	elif bomb_projectile_scene:
		var bomb_instance = bomb_projectile_scene.instantiate()
		if "linear_damp" in bomb_instance:
			linear_damp = float(bomb_instance.linear_damp)
			if linear_damp < 0.0:
				linear_damp = float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.0))
		if "gravity_scale" in bomb_instance:
			gravity_scale = float(bomb_instance.gravity_scale)
		bomb_instance.queue_free()
		_cached_bomb_linear_damp = linear_damp
		_cached_bomb_gravity_scale = gravity_scale

	var gravity_dir: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3(0, -1, 0))
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gravity_vec: Vector3 = gravity_dir * gravity_mag

	var time_step: float = maxf(bomb_ccip_time_step_s, 0.02)
	var max_time: float = maxf(bomb_ccip_max_time_s, time_step)
	var current_pos: Vector3 = start_pos
	var space_state: PhysicsDirectSpaceState3D = aircraft.get_world_3d().direct_space_state
	var terrain: Node = _get_cached_terrain_node()

	if log_debug:
		print("[CCIP] start=", snapped(start_pos, Vector3.ONE * 0.1),
			"  vel=", snapped(current_vel, Vector3.ONE * 0.1),
			"  grav_scale=", gravity_scale, "  damp=", linear_damp,
			"  terrain3d=", terrain != null)

	for step in int(max_time / time_step):
		current_vel += gravity_vec * gravity_scale * time_step
		if linear_damp > 0.0:
			current_vel /= (1.0 + linear_damp * time_step)
		var next_pos: Vector3 = current_pos + current_vel * time_step
		var segment_start_t: float = float(step) * time_step

		if use_moving_target_plane:
			var target_y: float = moving_target_pos.y
			var crosses_target_plane: bool = current_pos.y >= target_y and next_pos.y <= target_y
			if crosses_target_plane:
				var y_span: float = current_pos.y - next_pos.y
				var t: float = (current_pos.y - target_y) / maxf(y_span, 0.001)
				t = clampf(t, 0.0, 1.0)
				var hit_time_s: float = segment_start_t + time_step * t
				var bomb_at_target_y: Vector3 = current_pos.lerp(next_pos, t)
				var future_target_pos: Vector3 = moving_target_pos + moving_target_velocity * hit_time_s
				var moving_miss_m: float = Vector2(future_target_pos.x - bomb_at_target_y.x, future_target_pos.z - bomb_at_target_y.z).length()
				if log_debug:
					print("[CCIP] moving target plane t=", snapped(hit_time_s, 0.01), "s bomb=", snapped(bomb_at_target_y, Vector3.ONE * 0.1), " target=", snapped(future_target_pos, Vector3.ONE * 0.1), " miss=", snapped(moving_miss_m, 0.1))
				return {
					"impact_position": bomb_at_target_y,
					"time_of_flight": hit_time_s,
					"moving_target_position": future_target_pos,
					"moving_target_miss_m": moving_miss_m
				}

		# Primary: physics raycast (works for standard StaticBody3D terrain)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
		query.exclude = [aircraft.get_rid()] if aircraft is CollisionObject3D else []
		query.collision_mask = 0xFFFFFFFF
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit and hit.has("position"):
			var hit_pos: Vector3 = hit.position
			var segment_len: float = current_pos.distance_to(next_pos)
			var segment_fraction: float = current_pos.distance_to(hit_pos) / maxf(segment_len, 0.001)
			var hit_time_s: float = segment_start_t + time_step * clampf(segment_fraction, 0.0, 1.0)
			if log_debug:
				print("[CCIP] raycast HIT at t=", snapped(hit_time_s, 0.01), "s  pos=", snapped(hit_pos, Vector3.ONE * 0.1))
			return {
				"impact_position": hit_pos,
				"time_of_flight": hit_time_s
			}

		# Fallback: Terrain3D height API ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â mirrors projectile_new.gd tunneling detection
		if terrain:
			var h_prev: float = _get_ground_height_at_position(current_pos)
			var h_next: float = _get_ground_height_at_position(next_pos)
			if not is_nan(h_prev) and not is_nan(h_next):
				if current_pos.y >= h_prev and next_pos.y < h_next:
					# Interpolate the crossing fraction
					var alpha_prev: float = current_pos.y - h_prev
					var alpha_next: float = next_pos.y - h_next
					var t: float = alpha_prev / max(alpha_prev - alpha_next, 0.001)
					var impact: Vector3 = current_pos.lerp(next_pos, t)
					var h_impact: float = _get_ground_height_at_position(impact)
					impact.y = h_impact if not is_nan(h_impact) else lerp(h_prev, h_next, t)
					var hit_time_s: float = segment_start_t + time_step * clampf(t, 0.0, 1.0)
					if log_debug:
						print("[CCIP] Terrain3D HIT at t=", snapped(hit_time_s, 0.01), "s  pos=", snapped(impact, Vector3.ONE * 0.1))
					return {
						"impact_position": impact,
						"time_of_flight": hit_time_s
					}

		if next_pos.y < -1000.0:
			if log_debug:
				print("[CCIP] fell off world at t=", snapped(step * time_step, 0.01), "s")
			return {
				"impact_position": Vector3.ZERO,
				"time_of_flight": -1.0
			}
		current_pos = next_pos

	if log_debug:
		print("[CCIP] ran out of steps, final_pos=", snapped(current_pos, Vector3.ONE * 0.1))
	return {
		"impact_position": Vector3.ZERO,
		"time_of_flight": -1.0
	}

func _predict_bomb_impact_point(log_debug: bool = false) -> Vector3:
	var solution: Dictionary = _predict_bomb_impact_solution(log_debug)
	var impact_variant: Variant = solution.get("impact_position", Vector3.ZERO)
	return impact_variant if impact_variant is Vector3 else Vector3.ZERO

func _stop_firing():
	"""Stop weapon fire - ControlWeapons uses is_trigger_held which we don't set."""
	# ControlWeapons fires when is_trigger_held; we call fire_automatic each frame when we want to fire
	# So we simply don't call it when we don't want to fire - no explicit stop needed
	pass

func _state_engage(delta: float):
	"""Attacking target"""
	if _evaluate_combat_objective():
		return
	combat_target = null
	change_state(State.SEARCH)

func _state_rtb(delta: float):
	"""Returning to base"""
	# Priority 1: Stop combat
	_stop_firing()
	
	_refresh_carrier_position(false)
	_ensure_carrier_position()
	
	# Set target speed and navigation towards carrier
	target_speed = 100.0
	if formation_anchor_active:
		nav_waypoint = formation_anchor
	else:
		nav_waypoint = carrier_position
		nav_waypoint.y = _resolve_effective_altitude_world_y(nav_waypoint, patrol_altitude_m)
	
	# Climb/descend to patrol altitude while navigating
	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)
	
	# Check horizontal distance to carrier
	var h_dist: float = Vector2(aircraft.global_position.x - carrier_position.x, aircraft.global_position.z - carrier_position.z).length()
	
	# Start landing approach when within 4000m
	if h_dist < 4000.0:
		if debug_enabled:
			print("[AIPilot RTB] Reached carrier vicinity (", h_dist, "m), starting recovery sequence.")
		if not start_recovery():
			start_landing()

func _get_carrier_node() -> Node3D:
	var carriers = get_tree().get_nodes_in_group("carrier")
	if not carriers.is_empty() and carriers[0] is Node3D:
		return carriers[0] as Node3D
	return null

func _get_recovery_carrier_frame() -> Dictionary:
	_refresh_carrier_position(false)
	_ensure_carrier_position()
	var carrier := _get_carrier_node()
	var origin: Vector3 = carrier.global_position if is_instance_valid(carrier) else carrier_position
	var forward: Vector3 = Vector3.FORWARD
	var right: Vector3 = Vector3.RIGHT
	if is_instance_valid(carrier):
		forward = carrier.global_transform.basis.z
		right = carrier.global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	if right.length_squared() <= 0.001:
		right = forward.cross(Vector3.UP).normalized()
	else:
		right = right.normalized()
	return {
		"valid": true,
		"origin": origin,
		"forward": forward,
		"right": right,
		"deck_y": _get_approach_deck_y()
	}

func _get_recovery_point(behind_m: float, right_m: float, alt_above_deck_m: float) -> Vector3:
	var frame: Dictionary = _get_recovery_carrier_frame()
	var origin: Vector3 = frame.get("origin", carrier_position)
	var forward: Vector3 = frame.get("forward", Vector3.FORWARD)
	var right: Vector3 = frame.get("right", Vector3.RIGHT)
	var deck_y: float = float(frame.get("deck_y", carrier_position.y + approach_deck_height_fallback_m))
	var point: Vector3 = origin - forward * behind_m + right * right_m
	point.y = deck_y + alt_above_deck_m
	if is_instance_valid(aircraft):
		point.y = _terrain_safe_altitude_for_segment(
			aircraft.global_position,
			point,
			point.y,
			recovery_gate_min_terrain_clearance_m
		)
	return point

func _get_recovery_approach_gate(phase: int) -> Dictionary:
	match phase:
		0:
			return {
				"behind_m": recovery_mid_gate_behind_m,
				"alt_above_deck_m": recovery_mid_gate_alt_above_deck_m,
				"label": "mid"
			}
		1:
			return {
				"behind_m": recovery_low_gate_behind_m,
				"alt_above_deck_m": recovery_low_gate_alt_above_deck_m,
				"label": "low"
			}
		_:
			return {
				"behind_m": recovery_final_gate_behind_m,
				"alt_above_deck_m": recovery_final_gate_alt_above_deck_m,
				"label": "final"
			}

func _request_landing_clearance_from_deck() -> bool:
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm and fdm.has_method("request_landing_clearance"):
		return bool(fdm.request_landing_clearance(aircraft))
	if fdm and fdm.has_method("can_accept_landing"):
		return bool(fdm.can_accept_landing(aircraft))
	return true

func _release_landing_clearance_from_deck() -> void:
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm and fdm.has_method("release_landing_clearance"):
		fdm.release_landing_clearance(aircraft)

func _state_recovery_marshal(delta: float) -> void:
	"""Fly to the high recovery gate and ask the deck for landing clearance."""
	_stop_firing()
	target_speed = recovery_gate_speed_mps
	nav_waypoint = _get_recovery_point(recovery_marshal_behind_m, 0.0, recovery_marshal_alt_above_deck_m)
	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)
	_landing_debug_tick(delta, "RECOVERY_MARSHAL", nav_waypoint)

	var dist_to_gate: float = aircraft.global_position.distance_to(nav_waypoint)
	if dist_to_gate <= recovery_clearance_request_distance_m:
		if _request_landing_clearance_from_deck():
			_recovery_clearance_granted = true
			_recovery_phase = 0
			_landing_debug_event("recovery clearance granted; stepping down to approach gates")
			change_state(State.RECOVERY_APPROACH)
		else:
			_recovery_clearance_granted = false
			_landing_debug_event("recovery clearance denied; entering hold")
			change_state(State.RECOVERY_HOLD)

func _state_recovery_hold(delta: float) -> void:
	"""Simple carrier-relative hold behind the ship until clearance opens."""
	_stop_firing()
	target_speed = recovery_gate_speed_mps
	nav_waypoint = _get_recovery_point(
		recovery_marshal_behind_m,
		_recovery_hold_side * recovery_hold_lateral_m,
		recovery_marshal_alt_above_deck_m
	)
	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)
	_landing_debug_tick(delta, "RECOVERY_HOLD", nav_waypoint)

	if aircraft.global_position.distance_to(nav_waypoint) <= recovery_gate_capture_m:
		_recovery_hold_side *= -1.0

	if _request_landing_clearance_from_deck():
		_recovery_clearance_granted = true
		_recovery_phase = 0
		_landing_debug_event("recovery clearance granted from hold; stepping down to approach gates")
		change_state(State.RECOVERY_APPROACH)

func _state_recovery_approach(delta: float) -> void:
	"""Fly the clearance-owned carrier-relative descent gates, then hand off to final landing."""
	target_speed = recovery_final_gate_speed_mps if _recovery_phase >= 2 else recovery_gate_speed_mps
	_deploy_landing_gear()
	var gate: Dictionary = _get_recovery_approach_gate(_recovery_phase)
	nav_waypoint = _get_recovery_point(
		float(gate.get("behind_m", recovery_final_gate_behind_m)),
		0.0,
		float(gate.get("alt_above_deck_m", recovery_final_gate_alt_above_deck_m))
	)
	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)
	_landing_debug_tick(delta, "RECOVERY_APPROACH", nav_waypoint, "gate=%s" % str(gate.get("label", "final")))

	var capture_m: float = recovery_final_gate_capture_m if _recovery_phase >= 2 else recovery_gate_capture_m
	if aircraft.global_position.distance_to(nav_waypoint) > capture_m:
		return
	if _recovery_phase < 2:
		_recovery_phase += 1
		_landing_debug_event("recovery gate reached; next gate phase=%d" % _recovery_phase)
		return
	_landing_debug_event("recovery final gate reached; starting straight-in landing")
	if not start_landing():
		_release_landing_clearance_from_deck()
		change_state(State.RTB)

func _get_approach_deck_y() -> float:
	"""Deck reference for approach phase altitudes."""
	if _approach_wp.size() >= 5:
		var wp4: Node3D = _approach_wp[4] as Node3D
		if is_instance_valid(wp4):
			return wp4.global_position.y
	# Fallback: carrier center + configured deck offset
	return carrier_position.y + approach_deck_height_fallback_m

func _get_approach_entry_altitude() -> float:
	if _approach_wp.size() >= 1:
		var wp0: Node3D = _approach_wp[0] as Node3D
		if is_instance_valid(wp0):
			return wp0.global_position.y
	return _get_approach_deck_y() + approach_entry_altitude_m

func _get_approach_phase_capture_radius(phase: int) -> float:
	match phase:
		1:
			return approach_phase0_capture_m
		2:
			return approach_phase1_capture_m
		3:
			return approach_phase2_capture_m
		4:
			return approach_phase3_capture_m
		_:
			return approach_phase0_capture_m

func _compute_precision_point_control(
	target_point: Vector3,
	bank_limit_deg: float,
	bank_gain: float,
	pitch_gain: float = -1.0,
	yaw_gain: float = -1.0,
	min_bank_deg: float = 0.0,
	pitch_limit: float = 0.8,
	yaw_limit: float = 1.0,
	reference_origin: Vector3 = Vector3.INF
) -> Dictionary:
	if not aircraft:
		return {"valid": false}
	var aim_origin: Vector3 = aircraft.global_position
	if reference_origin != Vector3.INF:
		aim_origin = reference_origin
	var to_target: Vector3 = target_point - aim_origin
	if to_target.length_squared() < 1.0:
		return {"valid": false}

	var vel: Vector3 = aircraft.linear_velocity
	var speed_mps: float = maxf(vel.length(), 1.0)
	var b: Basis = aircraft.global_transform.basis
	var ang_vel: Vector3 = aircraft.angular_velocity
	var aim_dir: Vector3 = to_target.normalized()
	var local_x: float = aim_dir.dot(b.x)
	var local_y: float = aim_dir.dot(b.y)
	var local_z: float = aim_dir.dot(b.z)

	var yaw_err_rad: float
	if local_z < -0.15:
		yaw_err_rad = signf(local_x)
		if absf(yaw_err_rad) < 0.01:
			yaw_err_rad = 1.0
		yaw_err_rad *= PI * 0.5
	else:
		yaw_err_rad = atan2(local_x, maxf(local_z, 0.05))
	var pitch_err_rad: float = atan2(local_y, maxf(absf(local_z), 0.05))

	var bank_limit_rad: float = deg_to_rad(maxf(bank_limit_deg, 1.0))
	var desired_bank: float = clampf(yaw_err_rad * bank_gain, -bank_limit_rad, bank_limit_rad)
	var min_bank_rad: float = deg_to_rad(maxf(min_bank_deg, 0.0))
	if min_bank_rad > 0.0 and absf(yaw_err_rad) > deg_to_rad(1.0) and absf(desired_bank) < min_bank_rad:
		desired_bank = signf(yaw_err_rad)
		if absf(desired_bank) < 0.01:
			desired_bank = 1.0
		desired_bank *= minf(min_bank_rad, bank_limit_rad)
	if flip_roll_direction:
		desired_bank = -desired_bank

	var current_roll: float = atan2(b.x.y, b.y.y)
	var roll_rate: float = ang_vel.dot(b.z)
	var bank_error: float = _normalize_angle(desired_bank - current_roll)
	var raw_roll: float = clampf(bank_error * 8.0 - roll_rate * 0.25, -1.0, 1.0)
	if absf(bank_error) > deg_to_rad(2.0):
		var min_roll: float = 0.10 * signf(bank_error)
		if absf(raw_roll) < absf(min_roll):
			raw_roll = min_roll

	var pitch_rate_up: float = -ang_vel.dot(b.x)
	var effective_pitch_gain: float = precision_point_pitch_gain if pitch_gain < 0.0 else pitch_gain
	var raw_pitch: float = clampf(
		pitch_err_rad * effective_pitch_gain - pitch_rate_up * 0.18,
		-pitch_limit,
		pitch_limit
	)

	var yaw_rate: float = ang_vel.dot(b.y)
	var sideslip: float = clampf(vel.dot(b.x) / speed_mps, -1.0, 1.0)
	var effective_yaw_gain: float = precision_point_yaw_gain if yaw_gain < 0.0 else yaw_gain
	var raw_yaw: float = clampf(
		yaw_err_rad * effective_yaw_gain - yaw_rate * 0.30 - sideslip * 0.15 - sin(current_roll) * 0.08,
		-yaw_limit,
		yaw_limit
	)

	return {
		"valid": true,
		"raw_roll": raw_roll,
		"raw_pitch": raw_pitch,
		"raw_yaw": raw_yaw,
		"desired_bank": desired_bank,
		"yaw_err_rad": yaw_err_rad,
		"pitch_err_rad": pitch_err_rad
	}

func _apply_precision_point_guidance(
	target_point: Vector3,
	bank_limit_deg: float,
	bank_gain: float,
	min_bank_deg: float = 0.0,
	pitch_gain: float = -1.0,
	yaw_gain: float = -1.0,
	roll_response: float = -1.0,
	pitch_response: float = -1.0,
	yaw_response: float = -1.0,
	pitch_limit: float = 0.8,
	yaw_limit: float = 1.0
) -> Dictionary:
	var control: Dictionary = _compute_precision_point_control(
		target_point,
		bank_limit_deg,
		bank_gain,
		pitch_gain,
		yaw_gain,
		min_bank_deg,
		pitch_limit,
		yaw_limit
	)
	if not bool(control.get("valid", false)):
		return control

	var effective_roll_response: float = precision_point_roll_response if roll_response < 0.0 else roll_response
	var effective_pitch_response: float = precision_point_pitch_response if pitch_response < 0.0 else pitch_response
	var effective_yaw_response: float = precision_point_yaw_response if yaw_response < 0.0 else yaw_response
	roll_input = lerpf(_smoothed_roll_input, float(control.get("raw_roll", 0.0)), clampf(effective_roll_response, 0.0, 1.0))
	pitch_input = lerpf(_smoothed_pitch_input, float(control.get("raw_pitch", 0.0)), clampf(effective_pitch_response, 0.0, 1.0))
	yaw_input = lerpf(_smoothed_yaw_input, float(control.get("raw_yaw", 0.0)), clampf(effective_yaw_response, 0.0, 1.0))
	_smoothed_roll_input = roll_input
	_smoothed_pitch_input = pitch_input
	_smoothed_yaw_input = yaw_input
	return control

func _apply_precision_horizontal_guidance(
	target_point: Vector3,
	bank_limit_deg: float,
	bank_gain: float,
	min_bank_deg: float = 0.0,
	yaw_gain: float = -1.0,
	roll_response: float = -1.0,
	yaw_response: float = -1.0,
	yaw_limit: float = 1.0
) -> Dictionary:
	var flat_target: Vector3 = target_point
	flat_target.y = aircraft.global_position.y
	var control: Dictionary = _compute_precision_point_control(
		flat_target,
		bank_limit_deg,
		bank_gain,
		0.0,
		yaw_gain,
		min_bank_deg,
		0.0,
		yaw_limit
	)
	if not bool(control.get("valid", false)):
		return control

	var effective_roll_response: float = precision_point_roll_response if roll_response < 0.0 else roll_response
	var effective_yaw_response: float = precision_point_yaw_response if yaw_response < 0.0 else yaw_response
	roll_input = lerpf(_smoothed_roll_input, float(control.get("raw_roll", 0.0)), clampf(effective_roll_response, 0.0, 1.0))
	yaw_input = lerpf(_smoothed_yaw_input, float(control.get("raw_yaw", 0.0)), clampf(effective_yaw_response, 0.0, 1.0))
	_smoothed_roll_input = roll_input
	_smoothed_yaw_input = yaw_input
	return control

func _horizontal_distance_vec3(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _get_approach_path_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if _approach_wp.size() < 5:
		return points
	for i in range(5):
		var wp: Node3D = _approach_wp[i] as Node3D
		if not is_instance_valid(wp):
			return []
		points.append(wp.global_position)
	return points

func _get_polyline_total_horizontal_length(points: Array[Vector3]) -> float:
	if points.size() < 2:
		return 0.0
	var total: float = 0.0
	for i in range(points.size() - 1):
		total += _horizontal_distance_vec3(points[i], points[i + 1])
	return total

func _sample_polyline_xz(points: Array[Vector3], distance_along: float) -> Dictionary:
	if points.size() < 2:
		return {"valid": false}
	var remaining: float = maxf(distance_along, 0.0)
	var total: float = _get_polyline_total_horizontal_length(points)
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var seg_len: float = _horizontal_distance_vec3(a, b)
		if seg_len <= 0.001:
			continue
		if remaining <= seg_len or i == points.size() - 2:
			var t: float = clampf(remaining / seg_len, 0.0, 1.0)
			var pos: Vector3 = a.lerp(b, t)
			var tangent: Vector3 = (b - a).normalized()
			return {
				"valid": true,
				"position": pos,
				"tangent": tangent,
				"segment_index": i,
				"t": t,
				"total_length": total
			}
		remaining -= seg_len
	var last_idx: int = points.size() - 1
	var fallback_tangent: Vector3 = (points[last_idx] - points[last_idx - 1]).normalized()
	return {
		"valid": true,
		"position": points[last_idx],
		"tangent": fallback_tangent,
		"segment_index": last_idx - 1,
		"t": 1.0,
		"total_length": total
	}

func _find_closest_polyline_point_xz(points: Array[Vector3], pos: Vector3) -> Dictionary:
	if points.size() < 2:
		return {"valid": false}
	var total_length: float = _get_polyline_total_horizontal_length(points)
	var best_dist: float = INF
	var best: Dictionary = {"valid": false}
	var traveled: float = 0.0
	var pos2: Vector2 = Vector2(pos.x, pos.z)
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var a2: Vector2 = Vector2(a.x, a.z)
		var b2: Vector2 = Vector2(b.x, b.z)
		var ab2: Vector2 = b2 - a2
		var seg_len_sq: float = ab2.length_squared()
		if seg_len_sq <= 0.001:
			continue
		var t: float = clampf((pos2 - a2).dot(ab2) / seg_len_sq, 0.0, 1.0)
		var sample: Vector3 = a.lerp(b, t)
		var dist: float = Vector2(sample.x - pos.x, sample.z - pos.z).length()
		var seg_len: float = sqrt(seg_len_sq)
		if dist < best_dist:
			best_dist = dist
			best = {
				"valid": true,
				"position": sample,
				"segment_index": i,
				"t": t,
				"along_distance": traveled + seg_len * t,
				"horizontal_error": dist,
				"total_length": total_length
		}
		traveled += seg_len
	return best

func _state_approach_path_follower(delta: float) -> void:
	if _approach_wp.size() < 5:
		_landing_debug_event("approach aborted: missing approach waypoints")
		change_state(State.SEARCH)
		return

	var points: Array[Vector3] = _get_approach_path_points()
	if points.size() < 5:
		_landing_debug_event("approach aborted: invalid approach path")
		change_state(State.SEARCH)
		return

	if _landing_phase <= 0:
		# Pre-funnel: navigate toward approach_0 at entry altitude until in funnel.
		target_speed = 80.0
		nav_waypoint = Vector3(points[0].x, _get_approach_entry_altitude(), points[0].z)
		_update_maneuver_waypoint()
		_navigate_to_waypoint(delta)
		var entry_hdist: float = _horizontal_distance_vec3(aircraft.global_position, points[0])
		_landing_debug_tick(delta, "APPROACH_PATH_ENTRY", nav_waypoint, "dist_ap0=%.0fm funnel_max=%.0fm" % [entry_hdist, approach_carrot_funnel_max_dist_m])
		if _is_in_approach_funnel(points):
			var init_c: Dictionary = _find_closest_polyline_point_xz(points, aircraft.global_position)
			var init_along: float = float(init_c.get("along_distance", 0.0))
			var init_total: float = float(init_c.get("total_length", 1.0))
			# Only activate if aircraft projects to the FIRST approach segment (before approach_1).
			# A large projection means the aircraft came from the side and isn't set up for approach.
			var first_seg_end: float = Vector2(points[1].x - points[0].x, points[1].z - points[0].z).length()
			if init_along <= first_seg_end:
				_deploy_landing_gear()
				target_speed = approach_post_gate_speed_mps
				throttle_input = approach_post_gate_throttle_cut
				if control_engine and control_engine.has_method("set_target_power"):
					control_engine.set_target_power(throttle_input)
				if engine and engine.has_method("set_throttle_input"):
					engine.set_throttle_input(throttle_input)
				_carrot_along_m = clampf(init_along + approach_carrot_lookahead_m, 0.0, init_total)
				_approach_path_along_m = 0.0
				_landing_phase = 1
				_smoothed_fpa_pitch = _smoothed_pitch_input  # seed FPA smoother from current pitch state
				if debug_enabled:
					print("[AIPilot] Approach(path): funnel captured, carrot at %.0fm" % _carrot_along_m)
				_landing_debug_event("funnel captured; gear down, carrot activated at along=%.0fm init_along=%.0fm first_seg=%.0fm" % [_carrot_along_m, init_along, first_seg_end])
		return

	# --- Rolling carrot phase ---
	var closest: Dictionary = _find_closest_polyline_point_xz(points, aircraft.global_position)
	if not bool(closest.get("valid", false)):
		_landing_debug_event("approach aborted: no closest path point")
		change_state(State.SEARCH)
		return
	var total_length: float = float(closest.get("total_length", 0.0))
	var aircraft_along: float = float(closest.get("along_distance", 0.0))

	# Carrot advances monotonically; lookahead tapers from far (200 m) to close (60 m) on final.
	var approach_progress_t: float = clampf(aircraft_along / maxf(total_length, 1.0), 0.0, 1.0)
	var carrot_lookahead: float = lerpf(approach_carrot_lookahead_m, approach_carrot_final_lookahead_m, approach_progress_t)
	_carrot_along_m = clampf(maxf(_carrot_along_m, aircraft_along + carrot_lookahead), 0.0, total_length)

	var sample: Dictionary = _sample_polyline_xz(points, _carrot_along_m)
	if not bool(sample.get("valid", false)):
		_landing_debug_event("approach aborted: could not sample carrot position")
		change_state(State.SEARCH)
		return

	# Terrain safety: lift the carrot if it would be below terrain + clearance.
	var carrot_pos: Vector3 = sample.get("position", points[1])
	var terrain_h: float = _get_ground_height_at_position(carrot_pos)
	if not is_nan(terrain_h):
		carrot_pos.y = maxf(carrot_pos.y, terrain_h + approach_carrot_terrain_clearance_m)

	nav_waypoint = carrot_pos
	maneuver_waypoint = nav_waypoint
	if nav_target:
		nav_target.global_position = maneuver_waypoint

	# Speed: lerp from far speed (carrot near approach_0) to near speed (carrot near approach_4).
	var progress_t: float = clampf(_carrot_along_m / maxf(total_length, 1.0), 0.0, 1.0)
	var far_speed: float = maxf(approach_path_far_speed_mps, approach_post_gate_speed_mps)
	var near_speed: float = maxf(approach_path_near_speed_mps, approach_post_gate_speed_mps)
	target_speed = lerpf(far_speed, near_speed, progress_t)

	var remaining_distance: float = maxf(total_length - aircraft_along, 0.0)
	_navigate_to_waypoint(delta)
	_apply_precision_horizontal_guidance(
		nav_waypoint,
		approach_precision_bank_limit_deg,
		approach_precision_bank_gain,
		approach_precision_min_bank_deg,
		precision_point_yaw_gain,
		0.42,
		0.32,
		1.0
	)
	_apply_approach_path_vertical_guidance(nav_waypoint)
	_landing_debug_tick(delta, "APPROACH_CARROT", nav_waypoint, "carrot=%.0fm aircraft=%.0fm remain=%.0fm" % [_carrot_along_m, aircraft_along, remaining_distance])

	# Transition to LANDING when aircraft reaches the final segment AND is aligned with approach_4.
	var final_segment_length: float = _horizontal_distance_vec3(points[3], points[4])
	var final_segment_start: float = maxf(total_length - final_segment_length, 0.0)
	if aircraft_along >= maxf(final_segment_start - approach_path_final_switch_buffer_m, 0.0):
		# Require bearing alignment before switching to LANDING state.
		var _b_align: Basis = aircraft.global_transform.basis
		var _hdg_align: float = atan2(_b_align.z.x, _b_align.z.z)
		var _to_ap4: Vector3 = points[4] - aircraft.global_position
		var _to_ap4_flat: Vector2 = Vector2(_to_ap4.x, _to_ap4.z)
		if _to_ap4_flat.length() > 10.0:
			var _bear_ap4: float = atan2(_to_ap4_flat.x, _to_ap4_flat.y)
			var _bear_err: float = absf(_normalize_angle(_bear_ap4 - _hdg_align))
			if _bear_err > deg_to_rad(25.0):
				_landing_debug_tick(delta, "APPROACH_CARROT_ALIGN", nav_waypoint, "bear_err=%.0fdeg — holding carrot" % rad_to_deg(_bear_err))
				return
		var final_gate_high_m: float = aircraft.global_position.y - nav_waypoint.y
		if final_gate_high_m > landing_final_gate_max_high_m:
			if remaining_distance > landing_final_high_waveoff_remaining_m:
				_landing_debug_tick(delta, "APPROACH_CARROT_HIGH", nav_waypoint, "high=%.0fm catchup_remain=%.0fm" % [
					final_gate_high_m,
					remaining_distance
				])
				return
			_landing_debug_event("missed approach trigger: too high at final gate high=%.0fm limit=%.0fm" % [
				final_gate_high_m,
				landing_final_gate_max_high_m
			])
			_begin_missed_approach()
			return
		if debug_enabled:
			print("[AIPilot] Approach(path): established on final segment, switching to LANDING")
		_landing_debug_event("established on final segment; switching to LANDING")
		change_state(State.LANDING)

func _is_in_approach_funnel(points: Array[Vector3]) -> bool:
	if points.size() < 2:
		return false
	# Outbound axis: direction from approach_1 toward approach_0, then beyond.
	var ap0_xz: Vector2 = Vector2(points[0].x, points[0].z)
	var ap1_xz: Vector2 = Vector2(points[1].x, points[1].z)
	var axis_dir: Vector2 = (ap0_xz - ap1_xz).normalized()
	var aircraft_xz: Vector2 = Vector2(aircraft.global_position.x, aircraft.global_position.z)
	var to_aircraft: Vector2 = aircraft_xz - ap0_xz
	var dist: float = to_aircraft.length()
	if dist > approach_carrot_funnel_max_dist_m:
		return false
	# Within 100 m of approach_0 any direction qualifies; beyond that enforce cone.
	if dist >= 100.0:
		var cos_threshold: float = cos(deg_to_rad(approach_carrot_funnel_half_angle_deg))
		if to_aircraft.normalized().dot(axis_dir) < cos_threshold:
			return false
	return true

func _apply_approach_path_vertical_guidance(target_pos: Vector3) -> void:
	var vel: Vector3 = aircraft.linear_velocity
	var to_target: Vector3 = target_pos - aircraft.global_position
	var horiz_dist: float = Vector2(to_target.x, to_target.z).length()
	var raw_desired_fpa: float = atan2(to_target.y, maxf(horiz_dist, 35.0))
	var desired_fpa: float = clampf(
		raw_desired_fpa,
		-deg_to_rad(maxf(landing_approach_max_descent_fpa_deg, 1.0)),
		deg_to_rad(maxf(landing_approach_max_climb_fpa_deg, 1.0))
	)
	# Use carrier-relative velocity so the glideslope is measured in the carrier's frame.
	var carrier_vel: Vector3 = _get_carrier_velocity()
	var rel_vel: Vector3 = vel - carrier_vel
	var rel_horiz_speed: float = Vector2(rel_vel.x, rel_vel.z).length()
	var current_fpa: float = atan2(rel_vel.y, maxf(rel_horiz_speed, 1.0))
	var pitch_rate_up: float = -aircraft.angular_velocity.dot(aircraft.global_transform.basis.x)
	var raw_pitch: float = clampf(
		(desired_fpa - current_fpa) * landing_approach_fpa_pitch_gain - pitch_rate_up * landing_approach_fpa_pitch_rate_damping,
		-maxf(landing_approach_fpa_pitch_input_limit, 0.05),
		maxf(landing_approach_fpa_pitch_input_limit, 0.05)
	)
	pitch_input = lerpf(_smoothed_fpa_pitch, raw_pitch, clampf(landing_approach_fpa_pitch_smoothing, 0.02, 1.0))
	_smoothed_fpa_pitch = pitch_input
	_smoothed_pitch_input = pitch_input  # keep in sync so LANDING state inherits correct value at transition
	if _landing_debug_enabled() and Engine.get_process_frames() % 30 == 0:
		print("[AIPilot FPACTL] %s des_fpa=%.1fdeg cur_fpa=%.1fdeg err=%.1fdeg p_rate=%.3f raw_p=%.3f pitch_in=%.3f" % [
			aircraft.name,
			rad_to_deg(desired_fpa), rad_to_deg(current_fpa), rad_to_deg(desired_fpa - current_fpa),
			-aircraft.angular_velocity.dot(aircraft.global_transform.basis.x),
			raw_pitch, pitch_input
		])

func _get_landing_path_target() -> Dictionary:
	var points: Array[Vector3] = _get_approach_path_points()
	if points.size() < 5:
		return {"valid": false}

	var final_points: Array[Vector3] = [points[3], points[4]]
	var closest: Dictionary = _find_closest_polyline_point_xz(final_points, aircraft.global_position)
	if not bool(closest.get("valid", false)):
		return {"valid": false}

	var speed_mps: float = aircraft.linear_velocity.length()
	var final_length: float = float(closest.get("total_length", 0.0))
	var along_distance: float = float(closest.get("along_distance", 0.0))
	var remaining_distance: float = maxf(final_length - along_distance, 0.0)
	var lookahead_m: float = clampf(
		speed_mps * landing_path_lookahead_time_s,
		landing_path_min_lookahead_m,
		landing_path_max_lookahead_m
	)
	var target_distance: float = minf(along_distance + lookahead_m, final_length)
	if remaining_distance <= lookahead_m * 0.45:
		target_distance = final_length
	var sample: Dictionary = _sample_polyline_xz(final_points, target_distance)
	var target_pos: Vector3 = sample.get("position", points[4])
	return {
		"valid": true,
		"target_pos": target_pos
	}

func _find_landing_marker(marker_names: Array[String]) -> Node3D:
	var root: Node = get_tree().current_scene
	if not is_instance_valid(root):
		return null
	for marker_name in marker_names:
		if marker_name.is_empty():
			continue
		var marker: Node3D = root.find_child(marker_name, true, false) as Node3D
		if is_instance_valid(marker):
			return marker
	return null

func _find_arresting_wire(wire_number: int) -> Node3D:
	var named_fallback: Node3D = null
	for node in get_tree().get_nodes_in_group("arresting_cable"):
		if not (node is Node3D):
			continue
		var cable: Node3D = node as Node3D
		if node.has_method("get_wire_number") and int(node.call("get_wire_number")) == wire_number:
			return cable
		if not is_instance_valid(named_fallback) and cable.name.to_lower().find(str(wire_number)) != -1:
			named_fallback = cable
	return named_fallback

func _get_landing_touchdown_reference() -> Dictionary:
	if _approach_wp.size() < 5 or not is_instance_valid(_approach_wp[4]):
		return {"valid": false}
	var approach_4_pos: Vector3 = (_approach_wp[4] as Node3D).global_position
	var result: Dictionary = {
		"valid": true,
		"position": approach_4_pos,
		"source": "approach_4"
	}
	if not landing_use_deck_start_catch_zone:
		return result
	var deck_start: Node3D = _find_landing_marker([
		landing_deck_start_node_name,
		"deck_start",
		"DeckCenterStart"
	])
	var aim_wire: Node3D = _find_arresting_wire(maxi(landing_aim_wire_number, 1))
	if is_instance_valid(aim_wire):
		var wire_target: Vector3 = aim_wire.global_position
		var forward_offset_m: float = maxf(landing_aim_forward_offset_m, 0.0)
		if forward_offset_m > 0.0:
			var deck_forward: Vector3 = Vector3.ZERO
			if is_instance_valid(deck_start):
				deck_forward = aim_wire.global_position - deck_start.global_position
			elif _approach_wp.size() > 0 and is_instance_valid(_approach_wp[0]):
				deck_forward = aim_wire.global_position - (_approach_wp[0] as Node3D).global_position
			deck_forward.y = 0.0
			if deck_forward.length_squared() > 0.001:
				wire_target += deck_forward.normalized() * forward_offset_m
		wire_target.y = approach_4_pos.y
		result["position"] = wire_target
		result["source"] = "wire_%d+%.0fm" % [maxi(landing_aim_wire_number, 1), forward_offset_m]
		if is_instance_valid(deck_start):
			result["deck_start"] = deck_start.global_position
		result["aim_wire"] = aim_wire.global_position
		return result
	var wire_3: Node3D = _find_arresting_wire(3)
	if not (is_instance_valid(deck_start) and is_instance_valid(wire_3)):
		return result
	var target_t: float = clampf(landing_catch_zone_target_t, 0.0, 1.0)
	var catch_zone_target: Vector3 = deck_start.global_position.lerp(wire_3.global_position, target_t)
	catch_zone_target.y = approach_4_pos.y
	result["position"] = catch_zone_target
	result["source"] = "deck_start_to_wire_3"
	result["deck_start"] = deck_start.global_position
	result["wire_3"] = wire_3.global_position
	result["catch_zone_t"] = target_t
	return result

func _get_landing_line_geometry() -> Dictionary:
	if _approach_wp.size() < 5 or not is_instance_valid(_approach_wp[4]):
		return {"valid": false}
	var touchdown_ref: Dictionary = _get_landing_touchdown_reference()
	var touchdown: Vector3 = touchdown_ref.get("position", (_approach_wp[4] as Node3D).global_position)
	var axis: Vector3 = Vector3.ZERO
	if is_instance_valid(_approach_wp[0]):
		axis = touchdown - (_approach_wp[0] as Node3D).global_position
	elif is_instance_valid(_approach_wp[3]):
		axis = touchdown - (_approach_wp[3] as Node3D).global_position
	else:
		var carrier: Node3D = (_approach_wp[4] as Node3D).get_parent() as Node3D
		if is_instance_valid(carrier):
			axis = carrier.global_transform.basis.z
	axis.y = 0.0
	if axis.length_squared() < 0.001:
		axis = aircraft.global_transform.basis.z
		axis.y = 0.0
	if axis.length_squared() < 0.001:
		return {"valid": false}
	axis = axis.normalized()
	return {
		"valid": true,
		"touchdown": touchdown,
		"axis": axis,
		"touchdown_source": touchdown_ref.get("source", "approach_4")
	}

func _landing_remaining_to_touchdown(pos: Vector3, landing_geom: Dictionary) -> float:
	var touchdown: Vector3 = landing_geom.get("touchdown", Vector3.ZERO)
	var axis: Vector3 = landing_geom.get("axis", Vector3.FORWARD)
	return (touchdown - pos).dot(axis)

func _landing_path_point(landing_geom: Dictionary, remaining_m: float) -> Vector3:
	var touchdown: Vector3 = landing_geom.get("touchdown", Vector3.ZERO)
	var axis: Vector3 = landing_geom.get("axis", Vector3.FORWARD)
	var remaining: float = remaining_m
	var point: Vector3 = touchdown - axis * remaining
	var approach_remaining: float = maxf(remaining, 0.0)
	var bias_t: float = clampf(approach_remaining / maxf(landing_carrot_gap_taper_distance_m, 1.0), 0.0, 1.0)
	point.y = touchdown.y + approach_remaining * tan(deg_to_rad(maxf(landing_glideslope_deg, 0.1))) + landing_carrot_vertical_bias_m * bias_t
	return point

func _landing_track_error(pos: Vector3) -> Dictionary:
	var landing_geom: Dictionary = _get_landing_line_geometry()
	if not bool(landing_geom.get("valid", false)):
		return {"valid": false}
	var touchdown: Vector3 = landing_geom.get("touchdown", Vector3.ZERO)
	var axis: Vector3 = landing_geom.get("axis", Vector3.FORWARD)
	var remaining: float = maxf(_landing_remaining_to_touchdown(pos, landing_geom), 0.0)
	var ideal: Vector3 = _landing_path_point(landing_geom, remaining)
	var right: Vector3 = Vector3.UP.cross(axis).normalized()
	var lateral_m: float = (pos - ideal).dot(right) if right.length_squared() > 0.001 else 0.0
	var vertical_m: float = pos.y - ideal.y
	return {
		"valid": true,
		"remaining_m": remaining,
		"lateral_m": lateral_m,
		"vertical_m": vertical_m,
		"track_error_m": sqrt(lateral_m * lateral_m + vertical_m * vertical_m)
	}

func _get_moving_landing_carrot(delta: float) -> Dictionary:
	var landing_geom: Dictionary = _get_landing_line_geometry()
	if not bool(landing_geom.get("valid", false)):
		return {"valid": false}
	var aircraft_remaining: float = maxf(_landing_remaining_to_touchdown(aircraft.global_position, landing_geom), 0.0)
	var carrot_floor_remaining: float = -maxf(landing_carrot_rollout_m, 0.0)
	if not _landing_carrot_active and aircraft_remaining < maxf(landing_carrot_min_start_remaining_m, 0.0):
		return {"valid": false}

	if not _landing_carrot_active or is_inf(_landing_carrot_remaining_m):
		_landing_carrot_active = true
		_landing_carrot_remaining_m = maxf(aircraft_remaining - maxf(landing_carrot_initial_gap_m, 0.0), carrot_floor_remaining)
	else:
		_landing_carrot_remaining_m = maxf(
			_landing_carrot_remaining_m - maxf(landing_carrot_speed_mps, 1.0) * delta,
			carrot_floor_remaining
		)

	var taper_t: float = clampf(aircraft_remaining / maxf(landing_carrot_gap_taper_distance_m, 1.0), 0.0, 1.0)
	var min_gap: float = maxf(landing_carrot_min_gap_m, 0.0) * taper_t
	_landing_carrot_remaining_m = minf(_landing_carrot_remaining_m, maxf(aircraft_remaining - min_gap, carrot_floor_remaining))
	if aircraft_remaining <= maxf(landing_carrot_final_max_gap_start_m, 1.0):
		var final_t: float = clampf(aircraft_remaining / maxf(landing_carrot_final_max_gap_start_m, 1.0), 0.0, 1.0)
		var max_gap: float = lerpf(
			maxf(landing_carrot_touchdown_gap_m, 0.0),
			maxf(landing_carrot_final_max_gap_m, 0.0),
			final_t
		)
		max_gap = maxf(max_gap, min_gap)
		_landing_carrot_remaining_m = maxf(_landing_carrot_remaining_m, aircraft_remaining - max_gap)
	var gap_m: float = aircraft_remaining - _landing_carrot_remaining_m
	return {
		"valid": true,
		"target_pos": _landing_path_point(landing_geom, _landing_carrot_remaining_m),
		"aircraft_remaining_m": aircraft_remaining,
		"carrot_remaining_m": _landing_carrot_remaining_m,
		"gap_m": gap_m
	}

func _state_approach(delta: float):
	"""Carrier approach: phase 0ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢3 (approach_0ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢3) then LANDING toward approach_4."""
	if approach_guidance_mode == ApproachGuidanceMode.PATH_FOLLOWER:
		_state_approach_path_follower(delta)
		return
	if _approach_wp.size() < 5:
		_landing_debug_event("approach aborted: missing approach waypoints")
		change_state(State.SEARCH)
		return
	if _landing_phase >= _approach_wp.size():
		_landing_debug_event("approach aborted: phase index outside waypoint list")
		change_state(State.SEARCH)
		return

	match _landing_phase:
		0:  # Fly to the horizontal position of approach_0 at entry altitude.
			target_speed = 80.0
			var wp0: Node3D = _approach_wp[0] as Node3D
			if not is_instance_valid(wp0):
				change_state(State.SEARCH)
				return
			nav_waypoint = Vector3(
				wp0.global_position.x,
				_get_approach_entry_altitude(),
				wp0.global_position.z
			)
			_update_maneuver_waypoint()
			_navigate_to_waypoint(delta)
			_landing_debug_tick(delta, "APPROACH", nav_waypoint, "gate=approach_0")
			var horiz_to_wp0: float = Vector2(
				aircraft.global_position.x - wp0.global_position.x,
				aircraft.global_position.z - wp0.global_position.z
			).length()
			if horiz_to_wp0 <= approach_phase0_capture_m:
				_deploy_landing_gear()
				target_speed = approach_post_gate_speed_mps
				throttle_input = approach_post_gate_throttle_cut
				if control_engine and control_engine.has_method("set_target_power"):
					control_engine.set_target_power(throttle_input)
				if engine and engine.has_method("set_throttle_input"):
					engine.set_throttle_input(throttle_input)
				_landing_phase = 1
				if debug_enabled:
					print("[AIPilot] Approach: reached approach_0 horizontal gate, gear down, slowing for descent")
				_landing_debug_event("reached approach_0 horizontal gate; gear down, slowing for descent")

		1:  # Fly to the actual approach_0 marker.
			target_speed = approach_post_gate_speed_mps
			var wp1: Node3D = _approach_wp[0] as Node3D
			if not is_instance_valid(wp1):
				change_state(State.SEARCH)
				return
			nav_waypoint = wp1.global_position
			_update_maneuver_waypoint()
			_navigate_to_waypoint(delta)
			_apply_precision_horizontal_guidance(
				nav_waypoint,
				approach_precision_bank_limit_deg,
				approach_precision_bank_gain,
				approach_precision_min_bank_deg,
				precision_point_yaw_gain,
				0.42,
				0.32,
				1.0
			)
			var h1: float = aircraft.global_position.distance_to(wp1.global_position)
			_landing_debug_tick(delta, "APPROACH", nav_waypoint, "gate=approach_0 dist=%.0fm" % h1)
			if h1 <= approach_phase0_capture_m:
				_landing_phase = 2
				if debug_enabled:
					print("[AIPilot] Approach: reached approach_0, turning to approach_1")
				_landing_debug_event("reached approach_0; turning to approach_1")

		2:  # Fly to approach_1.
			target_speed = approach_post_gate_speed_mps
			var wp2: Node3D = _approach_wp[1] as Node3D
			if not is_instance_valid(wp2):
				change_state(State.SEARCH)
				return
			nav_waypoint = wp2.global_position
			_update_maneuver_waypoint()
			_navigate_to_waypoint(delta)
			_apply_precision_horizontal_guidance(
				nav_waypoint,
				approach_precision_bank_limit_deg,
				approach_precision_bank_gain,
				approach_precision_min_bank_deg,
				precision_point_yaw_gain,
				0.42,
				0.32,
				1.0
			)
			var h2: float = aircraft.global_position.distance_to(wp2.global_position)
			_landing_debug_tick(delta, "APPROACH", nav_waypoint, "gate=approach_1 dist=%.0fm" % h2)
			if h2 <= approach_phase1_capture_m:
				_landing_phase = 3
				if debug_enabled:
					print("[AIPilot] Approach: reached approach_1, turning to approach_2")
				_landing_debug_event("reached approach_1; turning to approach_2")

		3:  # Fly to approach_2.
			target_speed = approach_post_gate_speed_mps
			var wp3: Node3D = _approach_wp[2] as Node3D
			if not is_instance_valid(wp3):
				change_state(State.SEARCH)
				return
			nav_waypoint = wp3.global_position
			_update_maneuver_waypoint()
			_navigate_to_waypoint(delta)
			_apply_precision_horizontal_guidance(
				nav_waypoint,
				approach_precision_bank_limit_deg,
				approach_precision_bank_gain,
				approach_precision_min_bank_deg,
				precision_point_yaw_gain,
				0.42,
				0.32,
				1.0
			)
			var h3: float = aircraft.global_position.distance_to(wp3.global_position)
			_landing_debug_tick(delta, "APPROACH", nav_waypoint, "gate=approach_2 dist=%.0fm" % h3)
			if h3 <= approach_phase2_capture_m:
				_landing_phase = 4
				if debug_enabled:
					print("[AIPilot] Approach: reached approach_2, turning to approach_3")
				_landing_debug_event("reached approach_2; turning to approach_3")

		4:  # Fly to approach_3.
			target_speed = 54.0
			var wp4: Node3D = _approach_wp[3] as Node3D
			if not is_instance_valid(wp4):
				change_state(State.SEARCH)
				return
			nav_waypoint = wp4.global_position
			_update_maneuver_waypoint()
			_navigate_to_waypoint(delta)
			_apply_precision_horizontal_guidance(
				nav_waypoint,
				approach_precision_bank_limit_deg,
				approach_precision_bank_gain,
				approach_precision_min_bank_deg,
				precision_point_yaw_gain,
				0.45,
				0.34,
				1.0
			)
			var h4: float = aircraft.global_position.distance_to(wp4.global_position)
			_landing_debug_tick(delta, "APPROACH", nav_waypoint, "gate=approach_3 dist=%.0fm" % h4)
			if h4 <= approach_phase3_capture_m:
				if debug_enabled:
					print("[AIPilot] Approach: reached approach_3, starting final approach")
				_landing_debug_event("reached approach_3; starting final approach")
				change_state(State.LANDING)

func _state_landing(delta: float):
	"""Final approach: rolling carrot on the straight line to the touchdown reference.
	FPA steering aims the velocity vector at the carrot. No intermediate waypoints."""
	if _approach_wp.size() < 5 or not is_instance_valid(_approach_wp[4]):
		_landing_debug_event("final aborted: missing approach_4")
		change_state(State.SEARCH)
		return
	var wp4: Node3D = _approach_wp[4] as Node3D
	var touchdown_ref: Dictionary = _get_landing_touchdown_reference()
	var touchdown: Vector3 = touchdown_ref.get("position", wp4.global_position)

	var vel: Vector3 = aircraft.linear_velocity
	var speed: float = vel.length()
	var b: Basis = aircraft.global_transform.basis
	var ang_vel: Vector3 = aircraft.angular_velocity
	var to_touch: Vector3 = touchdown - aircraft.global_position
	var dist_to_touch: float = to_touch.length()
	var horiz_dist_to_touch: float = Vector2(to_touch.x, to_touch.z).length()
	var landing_geom: Dictionary = _get_landing_line_geometry()
	var landing_line_valid: bool = bool(landing_geom.get("valid", false))
	var remaining_to_touchdown_m: float = horiz_dist_to_touch
	var glide_reference_pos: Vector3 = touchdown
	var glide_vertical_error_m: float = 0.0
	if landing_line_valid:
		remaining_to_touchdown_m = maxf(_landing_remaining_to_touchdown(aircraft.global_position, landing_geom), 0.0)
		glide_reference_pos = _landing_path_point(landing_geom, remaining_to_touchdown_m)
		glide_vertical_error_m = aircraft.global_position.y - glide_reference_pos.y

	var lookahead_m: float = clampf(speed * landing_path_lookahead_time_s,
									landing_path_min_lookahead_m,
									landing_path_max_lookahead_m)

	if not _land_snap_400_done and dist_to_touch < 400.0:
		_land_snap_400_done = true
		_landing_snap("400m")
	elif not _land_snap_200_done and dist_to_touch < 200.0:
		_land_snap_200_done = true
		_landing_snap("200m")
	elif not _land_snap_100_done and dist_to_touch < 100.0:
		_land_snap_100_done = true
		_landing_snap("100m")

	# Detect bolter / wave-off before committing the carrot so we can override it.
	if not _bolter_go_around:
		if landing_line_valid \
		and remaining_to_touchdown_m <= maxf(landing_final_path_waveoff_remaining_m, 1.0) \
		and absf(glide_vertical_error_m) > maxf(landing_final_path_waveoff_error_m, 0.0):
			_bolter_go_around = true
			var vf := Vector3(vel.x, 0.0, vel.z)
			_bolter_dir = vf.normalized() if vf.length_squared() > 0.5 else b.z
			if not _land_snap_touch_done:
				_land_snap_touch_done = true
				_landing_snap("WAVE-OFF", "path_err=%+.1fm  pts=0.0" % glide_vertical_error_m)
		elif landing_line_valid \
		and remaining_to_touchdown_m <= maxf(landing_final_low_path_waveoff_remaining_m, 1.0) \
		and glide_vertical_error_m < -maxf(landing_final_low_path_waveoff_m, 0.0) \
		and vel.y < -1.0:
			_bolter_go_around = true
			var vf := Vector3(vel.x, 0.0, vel.z)
			_bolter_dir = vf.normalized() if vf.length_squared() > 0.5 else b.z
			if not _land_snap_touch_done:
				_land_snap_touch_done = true
				var own_deck_alt_waveoff: float = aircraft.global_position.y - _get_approach_deck_y()
				if own_deck_alt_waveoff < 0.0:
					_landing_snap("CRASH", "low_path=%+.1fm  below_deck=%+.1fm  pts=0.0" % [
						glide_vertical_error_m,
						own_deck_alt_waveoff
					])
				else:
					_landing_snap("WAVE-OFF", "low_path=%+.1fm  pts=0.0" % glide_vertical_error_m)
		elif _should_wave_off_for_busy_deck(horiz_dist_to_touch):
			_bolter_go_around = true
			var vf := Vector3(vel.x, 0.0, vel.z)
			_bolter_dir = vf.normalized() if vf.length_squared() > 0.5 else b.z
			if not _land_snap_touch_done:
				_land_snap_touch_done = true
				_landing_snap("WAVE-OFF", "pts=0.0")
		elif _should_start_missed_approach():
			var vf := Vector3(vel.x, 0.0, vel.z)
			_bolter_dir = vf.normalized() if vf.length_squared() > 0.5 else b.z
			if not _land_snap_touch_done:
				_land_snap_touch_done = true
				_landing_snap("BOLTER", "pts=0.0")
			_begin_missed_approach()
			return

	var target_pos: Vector3
	if _bolter_go_around:
		_landing_carrot_active = false
		_landing_carrot_remaining_m = INF
		throttle_input = 1.0
		target_speed = maxf(target_speed, 80.0)
		if aircraft.global_position.y >= touchdown.y + landing_bolter_gear_retract_height_m:
			_stow_landing_config()
		if aircraft.global_position.y < touchdown.y + 80.0:
			# Phase 1: climb away from deck at ~8°
			target_pos = aircraft.global_position \
							+ _bolter_dir * lookahead_m \
							+ Vector3.UP * (lookahead_m * 0.14)
		else:
			# Phase 2: steer back to re-entry point 800 m behind approach_4
			var reentry := touchdown - _bolter_dir * 800.0
			reentry.y = touchdown.y + 150.0
			target_pos = reentry
			# Restart once behind approach_4 and at approach altitude
			var behind_m := (touchdown - aircraft.global_position).dot(_bolter_dir)
			if behind_m >= 500.0:
				start_landing()
				return
	else:
		var moving_carrot: Dictionary = {}
		if landing_moving_carrot_enabled:
			moving_carrot = _get_moving_landing_carrot(delta)
		if bool(moving_carrot.get("valid", false)):
			target_pos = moving_carrot.get("target_pos", touchdown)
		else:
			_landing_carrot_active = false
			_landing_carrot_remaining_m = INF
			# Direct-to-touchdown fallback: stable regardless of starting altitude.
			target_pos = aircraft.global_position + to_touch.normalized() * lookahead_m

	nav_waypoint = target_pos
	_update_maneuver_waypoint()

	var to_target: Vector3 = target_pos - aircraft.global_position
	var horiz_dist: float = Vector2(to_target.x, to_target.z).length()
	var horiz_speed: float = Vector2(vel.x, vel.z).length()

	if _landing_carrot_active:
		var aircraft_remaining_dbg: float = 0.0
		var gap_dbg: float = 0.0
		var deck_axis_speed_dbg: float = 0.0
		var rel_axis_speed_dbg: float = speed
		var landing_geom_dbg: Dictionary = _get_landing_line_geometry()
		if bool(landing_geom_dbg.get("valid", false)):
			aircraft_remaining_dbg = maxf(_landing_remaining_to_touchdown(aircraft.global_position, landing_geom_dbg), 0.0)
			gap_dbg = aircraft_remaining_dbg - _landing_carrot_remaining_m
			var dbg_axis: Vector3 = landing_geom_dbg.get("axis", Vector3.ZERO)
			dbg_axis.y = 0.0
			if dbg_axis.length_squared() > 0.001:
				dbg_axis = dbg_axis.normalized()
				var deck_vel_dbg: Vector3 = _get_carrier_velocity()
				deck_axis_speed_dbg = deck_vel_dbg.dot(dbg_axis)
				rel_axis_speed_dbg = (vel - deck_vel_dbg).dot(dbg_axis)
		_landing_debug_tick(delta, "LANDING_CARROT", target_pos,
			"air=%.0fm carrot=%.0fm gap=%.0fm line_v=%+.1fm deck_v=%+.1f rel_v=%.1f" % [
				aircraft_remaining_dbg,
				_landing_carrot_remaining_m,
				gap_dbg,
				glide_vertical_error_m,
				deck_axis_speed_dbg,
				rel_axis_speed_dbg
			])

	# Wire caught: kill engine, release pitch/yaw, but keep wings-level roll command
	# (mirrors real pilot behaviour ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â hold aileron to stay upright through the arrest)
	var arrest_engaged: bool = aircraft.get_meta("arresting_engaged", false)
	if arrest_engaged:
		throttle_input = 0.0
		pitch_input = lerp(_smoothed_pitch_input, 0.0, 0.3)
		yaw_input = lerp(_smoothed_yaw_input, 0.0, 0.3)
		_smoothed_pitch_input = pitch_input
		_smoothed_yaw_input = yaw_input
		# Actively level wings: proportional + roll-rate damping, same gains as final approach
		var current_roll: float = atan2(b.x.y, b.y.y)
		var roll_rate: float = ang_vel.dot(b.z)
		var raw_roll: float = clamp(-current_roll * 11.0 - roll_rate * 0.3, -1.0, 1.0)
		roll_input = lerp(_smoothed_roll_input, raw_roll, 0.25)
		_smoothed_roll_input = roll_input

		if not _arrest_engaged_prev:
			_arrest_engaged_prev = true
			if not _land_snap_touch_done:
				_land_snap_touch_done = true
				var _snap_cable = aircraft.get_meta("arresting_cable", null) as Node
				var _snap_wire: int = 0
				var _snap_lat: float = 0.0
				var _snap_pts: float = 0.0
				if is_instance_valid(_snap_cable) and _snap_cable.has_method("get_wire_number"):
					_snap_wire = _snap_cable.get_wire_number()
					_snap_lat = _snap_cable.get_engage_lateral_m()
					var _snap_base: float = 10.0 if _snap_wire == 2 else 5.0
					_snap_pts = _snap_base * clamp(1.0 - abs(_snap_lat) / 24.8, 0.0, 1.0)
				_landing_snap("CAUGHT", "wire=%d  lat=%+.1fm  pts=%.1f" % [_snap_wire, _snap_lat, _snap_pts])
		return
	# Cable just released ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â go idle and hand aircraft to FlightDeckManager
	if _arrest_engaged_prev:
		_arrest_engaged_prev = false
		_arrest_stopped_reported = false
		_landing_debug_event("arrest ended; transitioning to IDLE and requesting recovery")
		print("[AIPilot] Arrest ended ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â transitioning to IDLE and requesting recovery")
		change_state(State.IDLE)
		_request_carrier_recovery()
		return

	# Speed target: bleed off as we close in (gear+flap drag assists; skip during go-around)
	if not _bolter_go_around:
		var base_landing_speed: float = 62.0
		if horiz_dist < 80.0:
			base_landing_speed = 50.0
		elif horiz_dist < 150.0:
			base_landing_speed = 53.0
		elif horiz_dist < 250.0:
			base_landing_speed = 57.0
		else:
			base_landing_speed = 62.0
		target_speed = base_landing_speed + _get_landing_carrier_speed_compensation(landing_geom)

	# === ROLL: wings level on short final (< 200 m), bearing-based further out ===
	var current_roll: float = atan2(b.x.y, b.y.y)
	var roll_rate: float = ang_vel.dot(b.z)
	# Bearing error computed always ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â needed for rudder correction throughout final approach
	var bearing_err_final: float = 0.0
	var runway_heading_err_final: float = 0.0
	var heading_rad_f: float = atan2(b.z.x, b.z.z)
	var horiz_to_target_flat: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	if horiz_to_target_flat.length() > 1.0:
		var bearing_rad_f: float = atan2(horiz_to_target_flat.x, horiz_to_target_flat.z)
		bearing_err_final = _normalize_angle(bearing_rad_f - heading_rad_f)
	var runway_axis_flat: Vector3 = Vector3.ZERO
	if landing_line_valid:
		runway_axis_flat = landing_geom.get("axis", Vector3.ZERO)
	runway_axis_flat.y = 0.0
	if runway_axis_flat.length() <= 0.01 and horiz_to_target_flat.length() > 1.0:
		runway_axis_flat = horiz_to_target_flat.normalized()
	if runway_axis_flat.length() > 0.01:
		runway_axis_flat = runway_axis_flat.normalized()
		var runway_heading_rad_f: float = atan2(runway_axis_flat.x, runway_axis_flat.z)
		runway_heading_err_final = _normalize_angle(runway_heading_rad_f - heading_rad_f)
	var lateral_damping_start_m: float = maxf(landing_final_lateral_damping_start_m, 1.0)
	var lateral_damping_end_m: float = clampf(landing_final_lateral_damping_end_m, 0.0, lateral_damping_start_m - 1.0)
	var lateral_far_t: float = clampf(
		(horiz_dist - lateral_damping_end_m) / maxf(lateral_damping_start_m - lateral_damping_end_m, 1.0),
		0.0,
		1.0
	)
	var lateral_smoothing: float = lerpf(
		clampf(landing_final_lateral_smoothing_near, 0.02, 1.0),
		clampf(landing_final_lateral_smoothing_far, 0.02, 1.0),
		lateral_far_t
	)
	if is_nan(_landing_smoothed_bearing_error):
		_landing_smoothed_bearing_error = bearing_err_final
	else:
		var max_bearing_step: float = deg_to_rad(maxf(landing_final_lateral_slew_deg_per_s, 1.0)) * maxf(delta, 0.001)
		var bearing_delta: float = clampf(
			_normalize_angle(bearing_err_final - _landing_smoothed_bearing_error),
			-max_bearing_step,
			max_bearing_step
		)
		_landing_smoothed_bearing_error = _normalize_angle(
			_landing_smoothed_bearing_error + bearing_delta * lateral_smoothing
		)
	if is_nan(_landing_smoothed_runway_heading_error):
		_landing_smoothed_runway_heading_error = runway_heading_err_final
	else:
		var max_heading_step: float = deg_to_rad(maxf(landing_final_lateral_slew_deg_per_s, 1.0)) * maxf(delta, 0.001)
		var heading_delta: float = clampf(
			_normalize_angle(runway_heading_err_final - _landing_smoothed_runway_heading_error),
			-max_heading_step,
			max_heading_step
		)
		_landing_smoothed_runway_heading_error = _normalize_angle(
			_landing_smoothed_runway_heading_error + heading_delta * lateral_smoothing
		)
	var lateral_gain_scale: float = lerpf(
		1.0,
		clampf(landing_final_lateral_gain_scale_far, 0.0, 1.0),
		lateral_far_t
	)
	var damped_bearing_err_final: float = _landing_smoothed_bearing_error * lateral_gain_scale
	var damped_runway_heading_err_final: float = _landing_smoothed_runway_heading_error
	var lateral_pd_err_final: float = damped_bearing_err_final
	if landing_line_valid and runway_axis_flat.length() > 0.01:
		var line_point_xz: Vector3 = _landing_path_point(landing_geom, remaining_to_touchdown_m)
		line_point_xz.y = aircraft.global_position.y
		var runway_right_flat: Vector3 = Vector3(runway_axis_flat.z, 0.0, -runway_axis_flat.x).normalized()
		var signed_lateral_m: float = (aircraft.global_position - line_point_xz).dot(runway_right_flat)
		var signed_lateral_vel_mps: float = (vel - _get_carrier_velocity()).dot(runway_right_flat)
		var lateral_pd_lookahead_m: float = maxf(landing_final_lateral_pd_lookahead_m, 10.0)
		var lateral_closure_m: float = signed_lateral_m + signed_lateral_vel_mps * maxf(
			landing_final_lateral_velocity_damping_s,
			0.0
		)
		var lateral_pd_limit_rad: float = deg_to_rad(maxf(landing_final_lateral_pd_limit_deg, 1.0))
		var lateral_offset_ratio: float = clampf(
			lateral_closure_m / lateral_pd_lookahead_m,
			-tan(lateral_pd_limit_rad),
			tan(lateral_pd_limit_rad)
		)
		var lateral_aim_dir: Vector3 = runway_axis_flat - runway_right_flat * lateral_offset_ratio
		if lateral_aim_dir.length() > 0.01:
			lateral_aim_dir = lateral_aim_dir.normalized()
			var lateral_aim_heading_rad: float = atan2(lateral_aim_dir.x, lateral_aim_dir.z)
			var runway_heading_rad_pd: float = atan2(runway_axis_flat.x, runway_axis_flat.z)
			lateral_pd_err_final = _normalize_angle(lateral_aim_heading_rad - runway_heading_rad_pd) * lateral_gain_scale
	var desired_bank: float = 0.0
	var lateral_bank_gain: float = maxf(landing_final_lateral_bank_gain, 0.0)
	var lateral_bank_limit_rad: float = deg_to_rad(maxf(landing_final_lateral_bank_limit_deg, 0.0))
	if horiz_dist > 200.0:
		desired_bank = clampf(
			lateral_pd_err_final * lateral_bank_gain,
			-lateral_bank_limit_rad,
			lateral_bank_limit_rad
		)
		if flip_roll_direction:
			desired_bank = -desired_bank
	# desired_bank stays 0.0 inside 200 m ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â command wings level
	var bank_error: float = desired_bank - current_roll
	var raw_roll: float = clamp(bank_error * 11.0 - roll_rate * 0.3, -1.0, 1.0)
	roll_input = lerp(_smoothed_roll_input, raw_roll, 0.25)
	_smoothed_roll_input = roll_input
	var short_final_dist_m: float = maxf(landing_short_final_bank_distance_m, 1.0)
	var close_alignment_t: float = 1.0 - clampf(horiz_dist / short_final_dist_m, 0.0, 1.0)
	var touchdown_level_dist_m: float = maxf(landing_touchdown_level_distance_m, 1.0)
	var touchdown_level_t: float = 1.0 - clampf(horiz_dist / touchdown_level_dist_m, 0.0, 1.0)
	var landing_bank_limit_deg: float = lerpf(
		20.0,
		clampf(landing_short_final_bank_limit_deg, 4.0, 20.0),
		close_alignment_t
	)
	landing_bank_limit_deg = lerpf(
		landing_bank_limit_deg,
		clampf(landing_touchdown_bank_limit_deg, 2.0, landing_bank_limit_deg),
		touchdown_level_t
	)
	var rudder_primary_bank_scale: float = lerpf(
		1.0,
		clampf(landing_final_rudder_primary_bank_scale, 0.0, 1.0),
		close_alignment_t
	)
	var aligned_bank: float = clampf(
		lateral_pd_err_final * lateral_bank_gain * rudder_primary_bank_scale,
		-minf(deg_to_rad(landing_bank_limit_deg), lateral_bank_limit_rad),
		minf(deg_to_rad(landing_bank_limit_deg), lateral_bank_limit_rad)
	)
	var short_final_min_bank_deg: float = 0.0
	if lateral_bank_gain >= 1.0:
		short_final_min_bank_deg = lerpf(
			clampf(landing_short_final_min_bank_deg, 0.0, landing_bank_limit_deg),
			0.0,
			touchdown_level_t
		)
		short_final_min_bank_deg *= rudder_primary_bank_scale
	var short_final_min_bank_rad: float = deg_to_rad(short_final_min_bank_deg)
	if close_alignment_t > 0.0 and absf(lateral_pd_err_final) > deg_to_rad(1.0) and absf(aligned_bank) < short_final_min_bank_rad:
		aligned_bank = signf(lateral_pd_err_final)
		if absf(aligned_bank) < 0.01:
			aligned_bank = 1.0
		aligned_bank *= short_final_min_bank_rad
	if flip_roll_direction:
		aligned_bank = -aligned_bank
	var aligned_bank_error: float = _normalize_angle(aligned_bank - current_roll)
	var touchdown_roll_damping: float = lerpf(0.3, 0.45, touchdown_level_t)
	var aligned_raw_roll: float = clampf(aligned_bank_error * 11.0 - roll_rate * touchdown_roll_damping, -1.0, 1.0)
	roll_input = lerpf(_smoothed_roll_input, aligned_raw_roll, lerpf(0.25, 0.4, maxf(close_alignment_t, touchdown_level_t)))
	_smoothed_roll_input = roll_input

	# === PITCH: follow the ideal touchdown line, not the carrot's instantaneous height ===
	# At slow speed with gear/flaps the nose is above the actual flight path, so
	# pitch tracks carrier-relative FPA. The carrot still guides lateral/forward
	# navigation; vertical correction comes from the fixed glideslope line.
	var carrier_vel_fpa: Vector3 = _get_carrier_velocity()
	var rel_vel_fpa: Vector3 = vel - carrier_vel_fpa
	var rel_horiz_speed_fpa: float = Vector2(rel_vel_fpa.x, rel_vel_fpa.z).length()
	var current_fpa: float = atan2(rel_vel_fpa.y, maxf(rel_horiz_speed_fpa, 1.0))
	var far_damping_start_m: float = maxf(landing_final_far_damping_start_m, 1.0)
	var far_damping_end_m: float = clampf(landing_final_far_damping_end_m, 0.0, far_damping_start_m - 1.0)
	var far_damping_t: float = clampf(
		(remaining_to_touchdown_m - far_damping_end_m) / maxf(far_damping_start_m - far_damping_end_m, 1.0),
		0.0,
		1.0
	)
	var far_correction_scale: float = clampf(landing_final_far_correction_scale, 0.0, 1.0)
	var correction_scale: float = lerpf(1.0, far_correction_scale, far_damping_t)
	var desired_fpa: float
	if landing_line_valid:
		var glideslope_rad: float = deg_to_rad(maxf(landing_glideslope_deg, 0.1))
		var base_fpa: float = -glideslope_rad
		var height_correction: float = clampf(
			-glide_vertical_error_m * maxf(landing_final_glide_error_fpa_gain, 0.0),
			-deg_to_rad(maxf(landing_final_glide_error_limit_deg, 0.0)),
			deg_to_rad(maxf(landing_final_glide_error_limit_deg, 0.0))
		)
		var ideal_vs: float = -rel_horiz_speed_fpa * tan(glideslope_rad)
		var vs_error: float = rel_vel_fpa.y - ideal_vs
		var vs_correction: float = clampf(
			-vs_error * maxf(landing_final_glide_vs_damping_gain, 0.0),
			-deg_to_rad(maxf(landing_final_glide_vs_damping_limit_deg, 0.0)),
			deg_to_rad(maxf(landing_final_glide_vs_damping_limit_deg, 0.0))
		)
		var vertical_correction_scale: float = correction_scale
		if glide_vertical_error_m < 0.0:
			var low_path_far_scale: float = clampf(
				landing_final_low_path_far_correction_scale,
				far_correction_scale,
				1.0
			)
			vertical_correction_scale = lerpf(1.0, low_path_far_scale, far_damping_t)
		height_correction *= vertical_correction_scale
		vs_correction *= vertical_correction_scale
		desired_fpa = base_fpa + height_correction + vs_correction
	else:
		desired_fpa = atan2(to_target.y, maxf(horiz_dist, 25.0))
	desired_fpa = clampf(
		desired_fpa,
		-deg_to_rad(maxf(landing_final_max_descent_fpa_deg, 1.0)),
		deg_to_rad(maxf(landing_final_max_climb_fpa_deg, 1.0))
	)
	# Flare: prevent nose-down dive in the last few metres above the deck.
	if is_instance_valid(_approach_wp[4]):
		var own_deck_alt_f: float = aircraft.global_position.y - (_approach_wp[4] as Node3D).global_position.y
		if own_deck_alt_f < 8.0 and horiz_dist_to_touch < 45.0:
			desired_fpa = maxf(desired_fpa, -deg_to_rad(5.0))
	var fpa_smoothing: float = lerpf(
		clampf(landing_final_fpa_smoothing_near, 0.02, 1.0),
		clampf(landing_final_fpa_smoothing_far, 0.02, 1.0),
		far_damping_t
	)
	if is_nan(_landing_smoothed_desired_fpa):
		_landing_smoothed_desired_fpa = desired_fpa
	else:
		var max_fpa_step: float = deg_to_rad(maxf(landing_final_fpa_slew_deg_per_s, 1.0)) * maxf(delta, 0.001)
		var slewed_fpa: float = clampf(
			desired_fpa,
			_landing_smoothed_desired_fpa - max_fpa_step,
			_landing_smoothed_desired_fpa + max_fpa_step
		)
		desired_fpa = lerpf(_landing_smoothed_desired_fpa, slewed_fpa, fpa_smoothing)
		_landing_smoothed_desired_fpa = desired_fpa
	var fpa_err: float = desired_fpa - current_fpa
	var pitch_rate_up: float = -ang_vel.dot(b.x)
	var final_pitch_limit: float = maxf(landing_final_pitch_input_limit, 0.05)
	var raw_pitch: float = clampf(
		fpa_err * landing_final_pitch_gain - pitch_rate_up * landing_final_pitch_rate_damping,
		-final_pitch_limit,
		final_pitch_limit
	)
	pitch_input = lerpf(_smoothed_pitch_input, raw_pitch, clampf(landing_final_pitch_smoothing, 0.02, 1.0))
	_smoothed_pitch_input = pitch_input
	# Stall protection: don't push nose down aggressively when near stall.
	var _stall_floor_final: float = stall_speed_mps + stall_margin_mps
	var _final_speed_margin: float = speed - _stall_floor_final
	if _final_speed_margin < 12.0:
		var _max_nd: float = lerpf(-0.05, -final_pitch_limit, clampf(_final_speed_margin / 12.0, 0.0, 1.0))
		# If significantly above glidepath, allow more nose-down to descend back through it.
		if fpa_err < -deg_to_rad(8.0):
			_max_nd = minf(_max_nd, -0.25)
		if pitch_input < _max_nd:
			pitch_input = _max_nd
			_smoothed_pitch_input = pitch_input

	# === THROTTLE: maintain approach speed (min 0.1 ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â lower than normal nav's 0.4) ===
	var commanded_target_speed: float = _get_effective_target_speed()
	var speed_err: float = commanded_target_speed - speed
	throttle_input = clamp(throttle_input + clamp(speed_err * 0.01, -0.05, 0.05), 0.1, 1.0)
	if landing_line_valid and not _bolter_go_around:
		var throttle_glideslope_rad: float = deg_to_rad(maxf(landing_glideslope_deg, 0.1))
		var throttle_ideal_vs: float = -rel_horiz_speed_fpa * tan(throttle_glideslope_rad)
		var low_path_t: float = clampf((-glide_vertical_error_m - 1.0) / 8.0, 0.0, 1.0)
		var excess_sink_t: float = clampf((throttle_ideal_vs - rel_vel_fpa.y) / 4.0, 0.0, 1.0)
		var low_path_floor: float = lerpf(0.1, clampf(landing_final_low_path_throttle_floor, 0.1, 1.0), low_path_t)
		var sink_floor: float = lerpf(0.1, clampf(landing_final_sink_throttle_floor, 0.1, 1.0), excess_sink_t)
		throttle_input = maxf(throttle_input, maxf(low_path_floor, sink_floor))
	if speed < stall_speed_mps + stall_margin_mps:
		throttle_input = 1.0

	# === YAW: coordinate the bank + rudder correction for heading fine-tuning ===
	var yaw_rate: float = ang_vel.dot(b.y)
	var rudder_target_heading_err: float = _normalize_angle(
		damped_runway_heading_err_final + lateral_pd_err_final * maxf(landing_final_rudder_lateral_gain, 0.0)
	)
	var yaw_correction_final: float = clampf(
		rudder_target_heading_err * maxf(landing_final_runway_yaw_gain, 0.0),
		-0.85,
		0.85
	)
	var raw_yaw: float = clampf(
		-sin(desired_bank) * landing_final_bank_yaw_mix + yaw_correction_final - yaw_rate * landing_final_rudder_rate_damping,
		-1.0,
		1.0
	)
	yaw_input = lerp(_smoothed_yaw_input, raw_yaw, input_smoothing)
	_smoothed_yaw_input = yaw_input
	# Rudder authority scales up as bank is restricted — rudder becomes the primary alignment tool.
	var aligned_yaw_correction_limit: float = lerpf(0.4, 0.85, close_alignment_t)
	var aligned_yaw_correction: float = clampf(
		rudder_target_heading_err * maxf(landing_final_runway_yaw_gain, 0.0),
		-aligned_yaw_correction_limit,
		aligned_yaw_correction_limit
	)
	var aligned_raw_yaw: float = clampf(
		-sin(aligned_bank) * landing_final_bank_yaw_mix + aligned_yaw_correction - yaw_rate * landing_final_rudder_rate_damping,
		-1.0,
		1.0
	)
	yaw_input = lerpf(_smoothed_yaw_input, aligned_raw_yaw, lerpf(input_smoothing, 0.4, close_alignment_t))
	_smoothed_yaw_input = yaw_input

	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 30 == 0:
		print("[AIPilot FINAL] dist=%.0fm  ÃƒÆ’Ã…Â½ÃƒÂ¢Ã¢â€šÂ¬Ã‚Âalt=%.1fm  fpa: want=%.1fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  act=%.1fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  err=%.1fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  pitch=%.2f  thr=%.2f  spd=%.0f" % [
			horiz_dist, to_target.y,
			rad_to_deg(desired_fpa), rad_to_deg(current_fpa), rad_to_deg(fpa_err),
			pitch_input, throttle_input, speed])

func _state_missed_approach(delta: float):
	"""Bolter/go-around: wings-level escape climb, then restart straight-in approach."""
	var deck_height: float = 0.0
	if _approach_wp.size() >= 5 and is_instance_valid(_approach_wp[4]):
		deck_height = (_approach_wp[4] as Node3D).global_position.y
	elif is_instance_valid(_takeoff_wp):
		deck_height = _takeoff_wp.global_position.y

	var vel: Vector3 = aircraft.linear_velocity
	var speed: float = vel.length()
	var stall_floor_speed: float = maxf(stall_speed_mps + stall_margin_mps, 1.0)
	target_speed = maxf(landing_bolter_target_speed_mps, approach_path_far_speed_mps)
	throttle_input = 1.0

	var speed_margin: float = speed - stall_floor_speed
	var b: Basis = aircraft.global_transform.basis
	var ang_vel: Vector3 = aircraft.angular_velocity
	var current_roll: float = atan2(b.x.y, b.y.y)
	var roll_rate: float = ang_vel.dot(b.z)
	var pitch_rate_up: float = -ang_vel.dot(b.x)

	# === PHASE 1: Escape climb — wings level + gentle nose up ===
	# approach_0 is BEHIND the aircraft. Navigating toward it immediately commands
	# full bank to turn around, which rolls the aircraft inverted at low speed.
	# Instead: level wings, pitch up gently, let the engine accelerate.
	if not _ma_escape_complete:
		# Retract gear/flaps only once safely clear of the deck.
		if aircraft.global_position.y >= deck_height + landing_bolter_gear_retract_height_m:
			_stow_landing_config()
		var wings_ok: bool = absf(current_roll) < deg_to_rad(15.0)
		var speed_ok: bool = speed_margin >= 15.0
		var climbing: bool = vel.y >= 0.0
		if wings_ok and speed_ok and climbing:
			_ma_escape_complete = true
			# Fall through to Phase 2 immediately this frame.
		else:
			var bank_error: float = _normalize_angle(0.0 - current_roll)
			roll_input = clampf(bank_error * 6.0 - roll_rate * 0.4, -1.0, 1.0)
			_smoothed_roll_input = roll_input
			yaw_input = 0.0
			_smoothed_yaw_input = 0.0
			# Keep meaningful nose-up authority even at near-stall: hold landing attitude, let thrust work.
			var nose_limit: float = lerpf(0.18, 0.35, clampf(speed_margin / 20.0, 0.0, 1.0))
			var target_pitch_rad: float = deg_to_rad(lerpf(5.0, 12.0, clampf(speed_margin / 20.0, 0.0, 1.0)))
			var current_pitch: float = asin(clampf(-b.z.y, -1.0, 1.0))
			pitch_input = clampf((target_pitch_rad - current_pitch) * 3.0 - pitch_rate_up * 0.4, -0.10, nose_limit)
			_smoothed_pitch_input = pitch_input
			_landing_debug_tick(delta, "MISSED_APPROACH", Vector3.ZERO,
				"ESCAPE bank=%.1fdeg margin=%.1f limit=%.2f pitch=%.2f vs=%.1f" % [
				rad_to_deg(current_roll), speed_margin, nose_limit, pitch_input, vel.y])
			return

	# === PHASE 2: Turn back toward touchdown point, then restart straight-in approach ===
	var wp4_ma: Node3D = _approach_wp[4] as Node3D if _approach_wp.size() >= 5 else null
	if is_instance_valid(wp4_ma):
		nav_waypoint = Vector3(wp4_ma.global_position.x, aircraft.global_position.y, wp4_ma.global_position.z)
	elif is_instance_valid(_takeoff_wp):
		nav_waypoint = Vector3(_takeoff_wp.global_position.x, aircraft.global_position.y, _takeoff_wp.global_position.z)
	else:
		_landing_debug_event("missed approach aborted: no approach_4 or takeoff_0")
		change_state(State.RTB)
		return

	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)

	# Stall guard: cap nose-up when near stall so the engine can accelerate first.
	if speed_margin < 15.0:
		var nose_up_limit: float = lerpf(0.08, 0.30, clampf(speed_margin / 15.0, 0.0, 1.0))
		pitch_input = clampf(pitch_input, -0.40, nose_up_limit)
		_smoothed_pitch_input = pitch_input

	var recover_pct: float = clampf(speed_margin / maxf(landing_bolter_speed_recovery_mps - stall_floor_speed, 1.0), 0.0, 1.0) * 100.0
	_landing_debug_tick(delta, "MISSED_APPROACH", nav_waypoint,
		"NAV spd_recover=%.0f%% stall_margin=%.1f pitch_in=%.2f vs=%.1f" % [
		recover_pct, speed_margin, pitch_input, vel.y])

	var high_enough: bool = aircraft.global_position.y >= deck_height + 80.0
	var speed_safe: bool = speed_margin >= 10.0
	if speed_safe and high_enough:
		_landing_debug_event("missed approach re-entry: starting straight-in landing")
		if not start_landing():
			change_state(State.RTB)

# ============================================================================
# NAVIGATION FUNCTIONS
# ============================================================================

func _navigate_to_waypoint(delta: float):
	"""Hybrid approach: local-space horizontal steering (roll) + world-space altitude hold (pitch)."""
	
	var vel: Vector3 = aircraft.linear_velocity
	var speed: float = max(vel.length(), 0.1)
	# Heading-independent bank angle: basis.x is the aircraft's right-wing vector.
	# Its Y component directly tells us the bank: negative = right wing down = right bank.
	var current_roll: float = atan2(aircraft.global_transform.basis.x.y, aircraft.global_transform.basis.y.y)
	var bank_rad: float = abs(current_roll)
	var aircraft_up_y: float = aircraft.global_transform.basis.y.y
	# In dogfight, the aircraft intentionally banks up to dogfight_bank_cmd_limit_deg (e.g. 85ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°).
	# cos(85ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°) = 0.087 ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â below the normal 0.3 threshold ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â so we raise the limit only in states
	# that deliberately command steep banks, to avoid fighting the roll controller.
	var is_upright: bool = current_state == State.DOGFIGHT or aircraft_up_y > 0.3

	# === INVERTED RECOVERY ===
	if not is_upright:
		var roll_to_level: float = _normalize_angle(0.0 - current_roll)
		roll_input = clamp(roll_to_level * 2.0, -1.0, 1.0)
		pitch_input = 0.0
		yaw_input = 0.0
		throttle_input = 0.8
		_smoothed_roll_input = roll_input
		_smoothed_pitch_input = pitch_input
		_smoothed_yaw_input = yaw_input
		return

	# === DESCENDING SPIRAL RECOVERY ===
	# If we're banked significantly and descending fast, the turn is bleeding altitude.
	# Pulling back in a steep bank just tightens the spiral. Level wings first, then climb.
	# Approach/Landing are also intentional descents ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â don't interfere with spiral recovery
	var in_dive_or_attack: bool = current_state in [State.DOGFIGHT, State.ATTACK_DIVE, State.RECOVERY_APPROACH, State.APPROACH, State.LANDING]
	if not in_dive_or_attack and bank_rad > deg_to_rad(25.0) and vel.y < -15.0:
		var roll_to_level: float = _normalize_angle(0.0 - current_roll)
		roll_input = clamp(roll_to_level * 3.0, -1.0, 1.0)
		pitch_input = clamp(-vel.y * 0.02, 0.0, 0.6)
		yaw_input = 0.0
		throttle_input = 1.0
		_smoothed_roll_input = roll_input
		_smoothed_pitch_input = pitch_input
		_smoothed_yaw_input = yaw_input
		return
	
	var to_target: Vector3 = maneuver_waypoint - aircraft.global_position
	var b: Basis = aircraft.global_transform.basis
	var in_dogfight_rejoin: bool = false
	if current_state == State.DOGFIGHT and combat_target and is_instance_valid(combat_target):
		in_dogfight_rejoin = aircraft.global_position.distance_to(combat_target.global_position) > dogfight_rejoin_range_m
	var formation_soft_t: float = 0.0
	if formation_anchor_active and current_state in [State.SEARCH, State.TRANSIT, State.RTB]:
		formation_soft_t = clampf(maxf(formation_slot_quality, formation_ahead_hold_t), 0.0, 1.0)
	var horiz_to_target_for_limit: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	var local_z_for_limit: float = horiz_to_target_for_limit.dot(b.z)
	var bank_limit_deg: float
	if current_state not in [State.ATTACK_DIVE, State.LANDING]:
		_dive_precise_aim = false
	if _dive_precise_aim:
		bank_limit_deg = 35.0  # Tighter bank for steadier final approach
	elif current_state == State.DOGFIGHT:
		bank_limit_deg = dogfight_bank_cmd_limit_deg
	elif current_state in [State.ATTACK_POSITIONING, State.ATTACK_DIVE, State.ATTACK_BREAK_OFF]:
		bank_limit_deg = attack_bank_cmd_limit_deg
	elif current_state == State.APPROACH:
		# Limit approach bank so bank_compensation (capped 1.2×) can hold altitude.
		# cos⁻¹(1/1.2) ≈ 34° — keep well under that to maintain altitude in entry turns.
		bank_limit_deg = minf(bank_cmd_limit_deg, maxf(approach_precision_bank_limit_deg, 5.0))
	elif current_state == State.MISSED_APPROACH:
		# At approach speeds (~50 m/s), 60° bank requires 2g to maintain altitude → stall.
		# Ramp from 15° at stall speed up to 35° once 20 m/s above stall.
		var ma_spd_margin: float = aircraft.linear_velocity.length() - (stall_speed_mps + stall_margin_mps)
		bank_limit_deg = lerpf(15.0, minf(bank_cmd_limit_deg, 35.0), clampf(ma_spd_margin / 20.0, 0.0, 1.0))
	else:
		bank_limit_deg = bank_cmd_limit_deg
	if current_state in [State.SEARCH, State.TRANSIT]:
		var nav_bank_t: float = clampf((altitude_agl - emergency_min_agl_m) / 220.0, 0.0, 1.0)
		var low_nav_bank_limit: float = lerpf(bank_limit_when_low_deg, bank_limit_deg, nav_bank_t)
		bank_limit_deg = minf(bank_limit_deg, low_nav_bank_limit)
	if formation_soft_t > 0.0:
		bank_limit_deg = lerpf(bank_limit_deg, minf(bank_limit_deg, formation_close_bank_limit_deg), formation_soft_t)
	if current_state == State.DOGFIGHT and _dogfight_recovery_timer_s > 0.0:
		bank_limit_deg = minf(bank_limit_deg, 25.0)
	if current_state == State.DOGFIGHT and in_dogfight_rejoin:
		bank_limit_deg = minf(bank_limit_deg, dogfight_rejoin_bank_limit_deg)
	# Ground protection in dogfight: taper max bank as AGL gets low.
	if current_state == State.DOGFIGHT:
		var agl_t: float = clampf((dogfight_ground_protect_agl_m - altitude_agl) / maxf(dogfight_ground_protect_agl_m, 1.0), 0.0, 1.0)
		var protected_bank_limit: float = lerpf(dogfight_bank_cmd_limit_deg, dogfight_ground_protect_min_bank_deg, agl_t)
		bank_limit_deg = minf(bank_limit_deg, protected_bank_limit)
		# Energy-aware bank limit: at low speed, avoid knife-edge banks that produce no useful turn.
		var speed_t: float = clampf(
			(speed - dogfight_min_speed_mps) / maxf(dogfight_corner_speed_mps - dogfight_min_speed_mps, 1.0),
			0.0,
			1.0
		)
		var speed_bank_floor: float = 45.0 if local_z_for_limit < -0.2 else 35.0
		if in_dogfight_rejoin:
			speed_bank_floor = 30.0
		var speed_bank_limit: float = lerpf(speed_bank_floor, dogfight_bank_cmd_limit_deg, speed_t)
		bank_limit_deg = minf(bank_limit_deg, speed_bank_limit)
	# Proactive terrain protection outside final approach/landing:
	# taper allowed bank as AGL drops so lift stays available for pull-up.
	if current_state not in [State.APPROACH, State.LANDING, State.IDLE]:
		var low_agl_soft_band_m: float = emergency_min_agl_m + 140.0
		if altitude_agl < low_agl_soft_band_m:
			var low_agl_t: float = clampf((low_agl_soft_band_m - altitude_agl) / maxf(low_agl_soft_band_m, 1.0), 0.0, 1.0)
			var low_agl_bank_limit: float = lerpf(bank_limit_deg, bank_limit_when_low_deg, low_agl_t)
			bank_limit_deg = minf(bank_limit_deg, low_agl_bank_limit)
	
	# === ROLL: project HORIZONTAL direction to target into local frame ===
	# By zeroing Y we prevent altitude differences from affecting the bank command.
	var horiz_to_target: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	var local_horiz_x: float = horiz_to_target.dot(b.x)
	var local_horiz_z: float = horiz_to_target.dot(b.z)
	var horiz_len: float = sqrt(local_horiz_x * local_horiz_x + local_horiz_z * local_horiz_z)
	
	var desired_bank: float = 0.0
	var bearing_err_rad: float = 0.0  # Heading error in radians; used for bank and rudder correction
	if horiz_len > 1.0:
		var lateral_ratio: float = local_horiz_x / horiz_len
		var horiz_dir_z: float = local_horiz_z / horiz_len

		# Bearing error: used for rudder and non-dogfight states
		var heading_rad: float = atan2(aircraft.global_transform.basis.z.x, aircraft.global_transform.basis.z.z)
		var bearing_to_wp_rad: float = atan2(horiz_to_target.x, horiz_to_target.z)
		bearing_err_rad = _normalize_angle(bearing_to_wp_rad - heading_rad)

		if current_state == State.DOGFIGHT:
			# Pure horizontal LOS turn law: bank toward target bearing.
			# Vertical pursuit is handled by pitch/energy logic below.
			var dogfight_bearing_err_rad: float = atan2(local_horiz_x, local_horiz_z)
			if local_horiz_z < -0.2:
				var behind_sign: float = signf(local_horiz_x)
				if absf(behind_sign) < 0.01:
					behind_sign = signf(bearing_err_rad)
				if absf(behind_sign) < 0.01:
					behind_sign = 1.0
				desired_bank = behind_sign * deg_to_rad(bank_limit_deg)
			else:
				desired_bank = clampf(
					dogfight_bearing_err_rad * 1.9,
					-deg_to_rad(bank_limit_deg),
					deg_to_rad(bank_limit_deg)
				)
			# Dogfight uses direct LOS sign; do not apply generic waypoint sign flip here.
			_committed_turn_sign = 0.0
		elif horiz_dir_z < -0.5:
			if formation_soft_t > 0.0:
				var turnaround_soft_t := clampf(
					absf(bearing_err_rad) / maxf(deg_to_rad(formation_turnaround_bearing_soften_deg), 0.01),
					0.0,
					1.0
				)
				var formation_turn_gain := lerpf(
					formation_turnaround_bank_scale,
					formation_close_bank_gain_scale,
					turnaround_soft_t
				)
				desired_bank = clampf(
					bearing_err_rad * formation_turn_gain,
					-deg_to_rad(bank_limit_deg),
					deg_to_rad(bank_limit_deg)
				)
				_committed_turn_sign = 0.0
				if flip_roll_direction:
					desired_bank = -desired_bank
			else:
				# Target behind: commit to a turn direction.
				var turn_toward: float
				if abs(lateral_ratio) > 0.05:
					turn_toward = signf(lateral_ratio)
				else:
					if _committed_turn_sign == 0.0:
						var cross: float = aircraft.global_transform.basis.z.x * horiz_to_target.z - aircraft.global_transform.basis.z.z * horiz_to_target.x
						_committed_turn_sign = -1.0 if cross > 0 else 1.0
					turn_toward = _committed_turn_sign
				if _committed_turn_sign == 0.0:
					_committed_turn_sign = turn_toward
				elif abs(lateral_ratio) > 0.05 and signf(_committed_turn_sign) != signf(lateral_ratio):
					_committed_turn_sign = turn_toward
				desired_bank = _committed_turn_sign * deg_to_rad(bank_limit_deg)
				if flip_roll_direction:
					desired_bank = -desired_bank
		else:
			if horiz_dir_z > 0.0:
				_committed_turn_sign = 0.0
			var bank_gain: float = 2.2 if _dive_precise_aim else 1.5
			if formation_soft_t > 0.0:
				bank_gain = lerpf(bank_gain, formation_close_bank_gain_scale, formation_soft_t)
			desired_bank = clamp(bearing_err_rad * bank_gain, -deg_to_rad(bank_limit_deg), deg_to_rad(bank_limit_deg))
			if flip_roll_direction:
				desired_bank = -desired_bank
	
	# Read angular rates for derivative damping (PD control instead of just P)
	var ang_vel: Vector3 = aircraft.angular_velocity
	var roll_rate: float = ang_vel.dot(b.z)
	var pitch_rate_up: float = -ang_vel.dot(b.x)
	var bank_limit_rad: float = deg_to_rad(max(bank_limit_deg, 1.0))
	var bank_util: float = clamp(abs(current_roll) / bank_limit_rad, 0.0, 1.0)
	var high_bank_t: float = clamp((bank_util - high_bank_start_ratio) / max(1.0 - high_bank_start_ratio, 0.01), 0.0, 1.0)
	
	# === ROLL: PD controller - decisive gain + minimum input when off target ===
	var bank_error: float = desired_bank - current_roll
	var roll_rate_damping: float = 0.30 + high_bank_roll_damping_gain * high_bank_t
	# Taper P-gain as bank approaches the limit: reduces vibration at max bank by making
	# the controller damping-dominated near the ceiling rather than twitchy-proportional.
	var roll_p_gain: float = lerp(11.0, 4.5, high_bank_t)
	var raw_roll: float = clamp(bank_error * roll_p_gain - roll_rate * roll_rate_damping, -1.0, 1.0)
	if abs(bank_error) > deg_to_rad(2.0):
		var min_roll: float = 0.45 * (1.0 - 0.55 * high_bank_t) * sign(bank_error)
		if abs(raw_roll) < abs(min_roll):
			raw_roll = min_roll
	var roll_smoothing: float = lerp(input_smoothing, 0.45, high_bank_t)
	if _dive_precise_aim:
		roll_smoothing = lerp(roll_smoothing, 0.25, 0.8)  # Faster response when aiming precisely
	roll_input = lerp(_smoothed_roll_input, raw_roll, roll_smoothing)
	_smoothed_roll_input = roll_input
	
	# === PITCH: world-space altitude hold via desired vertical speed, with stronger damping ===
	var alt_err: float = nav_waypoint.y - aircraft.global_position.y
	var in_dive_state: bool = current_state == State.ATTACK_DIVE
	var in_break_off: bool = current_state == State.ATTACK_BREAK_OFF
	var in_attack_approach: bool = current_state in [State.ATTACK_POSITIONING, State.ATTACK_INBOUND]
	var in_dogfight: bool = current_state == State.DOGFIGHT
	var in_carrier_approach: bool = current_state == State.APPROACH
	var in_landing: bool = current_state == State.LANDING
	var in_normal_altitude_hold: bool = not (
		in_dive_state
		or in_break_off
		or in_attack_approach
		or in_dogfight
		or in_carrier_approach
		or in_landing
		or current_state == State.CLIMBING
	)
	# Continuous ramp 0ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢1 as alt deficit grows 0ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢80m. Replaces the old binary in_attack_climb
	# switch at 30m which caused an abrupt gain step and drove oscillation.
	var attack_climb_t: float = clamp(alt_err / 80.0, 0.0, 1.0) if in_attack_approach else 0.0
	var needs_high_authority: bool = in_dive_state or in_break_off or in_landing or in_carrier_approach
	var vs_limit: float
	var vs_gain: float
	if in_landing:
		# Carrier final: need enough descent (150m over ~540m) ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â default 10 m/s cap is too low
		vs_limit = 18.0
		vs_gain = 0.18
	elif in_carrier_approach:
		vs_limit = maxf(landing_approach_vs_limit_mps, 2.0)
		vs_gain = maxf(landing_approach_vs_gain, 0.01)
	elif needs_high_authority:
		# Soft dive entry: ramp up over 1.2s to avoid initial pull-too-hard oscillation
		var now_s: float = Time.get_ticks_msec() / 1000.0
		var dive_age_s: float = now_s - _dive_entry_time_s if _dive_entry_time_s > -INF else 999.0
		var entry_t: float = clamp(dive_age_s / 1.2, 0.0, 1.0)
		vs_limit = lerp(18.0, 55.0, entry_t)
		vs_gain = lerp(0.12, 0.25, entry_t)
	elif in_attack_approach:
		# Smoothly blend authority as altitude deficit grows ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â no abrupt step at any threshold
		vs_limit = lerp(10.0, 18.0, attack_climb_t)
		vs_gain  = lerp(0.08, 0.12, attack_climb_t)
	elif in_dogfight:
		# Dogfight: bounded vertical command; calmer rejoin profile at long range.
		if in_dogfight_rejoin:
			vs_limit = 10.0
			vs_gain = 0.06
		else:
			vs_limit = maxf(dogfight_vs_limit_mps, 2.0)
			vs_gain = maxf(dogfight_vs_gain, 0.01)
	elif current_state == State.CLIMBING:
		# Post-launch climb: climb positively without over-rotating into a loop.
		vs_limit = maxf(climb_vs_limit_mps, 6.0)
		vs_gain = 0.09
	else:
		vs_limit = maxf(normal_flight_vs_limit_mps, 2.0)
		vs_gain = maxf(normal_flight_vs_gain, 0.01)
	var desired_vs: float = clamp(alt_err * vs_gain, -vs_limit, vs_limit)
	# Deadband: settle when close to target altitude ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â applies in all non-dive/break-off states
	if not needs_high_authority and abs(alt_err) < pitch_deadband_m and abs(vel.y) < 2.0:
		desired_vs = 0.0
	# During dive: deadband near aim altitude to prevent pitch hunting/oscillation
	elif in_dive_state and abs(alt_err) < 35.0:
		desired_vs = clamp(alt_err * 0.15, -8.0, 8.0)  # Gentle correction when close
	if formation_soft_t > 0.0 and not needs_high_authority and not in_dogfight:
		var formation_vs := clampf(alt_err * 0.045, -formation_close_vs_limit_mps, formation_close_vs_limit_mps)
		desired_vs = lerpf(desired_vs, formation_vs, formation_soft_t)
	var dogfight_speed_deficit: float = 0.0
	# Dogfight turn-pull assist: compensate lift loss in steep bank.
	if in_dogfight:
		if not in_dogfight_rejoin:
			# Unload/push over when below corner-speed envelope to avoid endless climb + stall.
			dogfight_speed_deficit = maxf((dogfight_corner_speed_mps + dogfight_unload_speed_margin_mps) - speed, 0.0)
			var allow_energy_unload: bool = local_horiz_z > -0.2
			dogfight_speed_deficit = minf(dogfight_speed_deficit, 35.0)
			if dogfight_speed_deficit > 0.0 and allow_energy_unload:
				var unload_descent: float = -minf(dogfight_speed_deficit * dogfight_unload_descent_gain, vs_limit * 0.75)
				desired_vs = minf(desired_vs, unload_descent)
		# Near ground, enforce a minimum climb demand during significant bank.
		var protect_agl: float = dogfight_ground_protect_agl_m
		if in_dogfight_rejoin:
			protect_agl = minf(protect_agl, 120.0)
		if altitude_agl < protect_agl and bank_rad > deg_to_rad(35.0):
			desired_vs = maxf(desired_vs, dogfight_ground_protect_min_climb_vs_mps)
		if _dogfight_recovery_timer_s > 0.0:
			desired_vs = maxf(desired_vs, dogfight_ground_protect_min_climb_vs_mps + 4.0)
	# General low-altitude guardrail: bias toward a climb before we hit hard safety override.
	# ATTACK_DIVE excluded: the dive has its own break-off logic; guardrail was canceling dive command.
	if current_state not in [State.APPROACH, State.LANDING, State.IDLE, State.ATTACK_DIVE]:
		var low_agl_guard_band_m: float = emergency_min_agl_m + 120.0
		if altitude_agl < low_agl_guard_band_m:
			var low_guard_t: float = clampf((low_agl_guard_band_m - altitude_agl) / maxf(low_agl_guard_band_m, 1.0), 0.0, 1.0)
			var min_climb_vs: float = lerpf(2.0, maxf(dogfight_ground_protect_min_climb_vs_mps, 10.0), low_guard_t)
			desired_vs = maxf(desired_vs, min_climb_vs)
	var vs_err: float = desired_vs - vel.y
	var bank_compensation: float = clamp(1.0 / max(cos(bank_rad), 0.7), 1.0, 1.2)
	var pitch_limit: float = 0.75 if in_dogfight else max_pitch_angle / deg_to_rad(60.0)
	if in_carrier_approach:
		pitch_limit = minf(maxf(pitch_limit, 0.25), maxf(landing_approach_pitch_input_limit, 0.05))
	elif in_normal_altitude_hold:
		pitch_limit = minf(pitch_limit, maxf(normal_flight_pitch_input_limit, 0.05))
	if formation_soft_t > 0.0 and not in_dogfight:
		var formation_pitch_limit: float = deg_to_rad(formation_close_pitch_limit_deg) / deg_to_rad(60.0)
		pitch_limit = minf(pitch_limit, lerpf(pitch_limit, formation_pitch_limit, formation_soft_t))
	var pitch_gain: float
	if in_carrier_approach:
		pitch_gain = maxf(landing_approach_pitch_gain, 0.01)
	elif needs_high_authority:
		pitch_gain = 0.10
	elif in_attack_approach:
		pitch_gain = lerp(0.06, 0.08, attack_climb_t)  # Gentler ceiling reduces overshoot
	elif in_dogfight:
		pitch_gain = 0.14
	elif in_normal_altitude_hold:
		pitch_gain = maxf(normal_flight_pitch_gain, 0.01)
	else:
		pitch_gain = 0.06
	if formation_soft_t > 0.0 and not in_dogfight:
		pitch_gain = lerpf(pitch_gain, pitch_gain * formation_close_pitch_gain_scale, formation_soft_t)
	var pitch_rate_damping: float = 0.45 if in_dive_state or in_dogfight else 0.5  # Stronger damping in combat
	if in_carrier_approach:
		pitch_rate_damping = maxf(landing_approach_pitch_rate_damping, 0.1)
	elif in_normal_altitude_hold:
		pitch_rate_damping = maxf(normal_flight_pitch_rate_damping, 0.1)
	var raw_pitch: float = clamp(vs_err * pitch_gain * bank_compensation - pitch_rate_up * pitch_rate_damping, -pitch_limit, pitch_limit)
	if in_dive_state:
		var aim_vector: Vector3 = maneuver_waypoint - aircraft.global_position
		if aim_vector.length_squared() > 1.0:
			var aim_dir: Vector3 = aim_vector.normalized()
			var local_y_to_aim: float = aim_dir.dot(b.y)
			var local_z_to_aim: float = aim_dir.dot(b.z)
			var pitch_los_err_rad: float = atan2(local_y_to_aim, maxf(absf(local_z_to_aim), 0.05))
			raw_pitch = clampf(
				pitch_los_err_rad * maxf(bomb_dive_pitch_los_gain, 0.1) - pitch_rate_up * 0.22,
				-pitch_limit,
				pitch_limit
			)
		if _run_weapon_type == "Bomb":
			var horiz_speed_for_fpa: float = Vector2(vel.x, vel.z).length()
			var fpa_deg: float = rad_to_deg(atan2(-vel.y, maxf(horiz_speed_for_fpa, 1.0)))
			if fpa_deg > bomb_preferred_dive_angle_deg:
				var pullback_pitch: float = (fpa_deg - bomb_preferred_dive_angle_deg) * maxf(bomb_dive_pullback_gain, 0.0)
				raw_pitch = maxf(raw_pitch, clampf(pullback_pitch, 0.0, pitch_limit))
	# Min pitch prevents dead-zone but must not fight the controller when it is already correcting
	# correctly. Only enforce the floor when vs_err agrees with the altitude error direction.
	var min_pitch_threshold: float = 60.0 if in_dive_state else 40.0
	if not in_dogfight and not in_dive_state and abs(alt_err) > min_pitch_threshold:
		var min_pitch: float = (0.10 if needs_high_authority else 0.04) * sign(alt_err)
		if sign(vs_err) == sign(alt_err) and abs(raw_pitch) < abs(min_pitch):
			raw_pitch = min_pitch
	var effective_pitch_smoothing: float
	if in_dive_state:
		effective_pitch_smoothing = 0.4
	elif in_carrier_approach:
		effective_pitch_smoothing = 0.5
	elif in_attack_approach:
		effective_pitch_smoothing = 0.4
	elif in_normal_altitude_hold:
		effective_pitch_smoothing = clampf(normal_flight_pitch_smoothing, 0.02, 1.0)
	else:
		effective_pitch_smoothing = pitch_input_smoothing
	pitch_input = lerp(_smoothed_pitch_input, raw_pitch, effective_pitch_smoothing)
	_smoothed_pitch_input = pitch_input
	
	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 30 == 0:
		var gh: float = _smoothed_ground_height if not is_nan(_smoothed_ground_height) else _get_ground_height_at_position(aircraft.global_position)
		print("[AIPilot PITCH] Alt: %.1f (Tgt: %.1f, Err: %.1f) | VS: %.1f (Des: %.1f, Err: %.1f) | Pitch: %.3f (Raw: %.3f) | Gnd: %.1f" % [aircraft.global_position.y, nav_waypoint.y, alt_err, vel.y, desired_vs, vs_err, pitch_input, raw_pitch, gh])
	if _landing_debug_enabled() and current_state in [State.APPROACH, State.LANDING, State.MISSED_APPROACH] and Engine.get_process_frames() % 30 == 0:
		print("[AIPilot PITCHCTL] %s state=%s alt_err=%.1f des_vs=%.1f vs_err=%.1f raw_p=%.3f smooth_p=%.3f pitch_in=%.3f p_rate=%.3f p_gain=%.3f p_damp=%.2f smth=%.2f" % [
			aircraft.name, State.keys()[current_state],
			alt_err, desired_vs, vs_err, raw_pitch, _smoothed_pitch_input, pitch_input,
			pitch_rate_up, pitch_gain, pitch_rate_damping, effective_pitch_smoothing
		])

	# Dogfight controller internals ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â shows bank/roll PD details every 30 frames
	if debug_enabled and verbose_debug_enabled and current_state == State.DOGFIGHT and Engine.get_process_frames() % 30 == 0:
		print("  [ROLL_CTL] desired=%+5.0fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  cur=%+5.0fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  err=%+5.1fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  p_gain=%.1f  d=%.2f  raw=%+5.2f  out=%+5.2f  rate=%.2f" % [
			rad_to_deg(desired_bank), rad_to_deg(current_roll), rad_to_deg(bank_error),
			roll_p_gain, roll_rate_damping, raw_roll, roll_input, roll_rate])
		print("  [PITCH_CTL] vs_des=%+5.1f  vs_err=%+5.1f  gain=%.2f  bank_comp=%.2f  dV=%.1f  raw=%+5.2f  out=%+5.2f" % [
			desired_vs, vs_err, pitch_gain, bank_compensation, dogfight_speed_deficit, raw_pitch, pitch_input])
	
	# === YAW: coordinate the bank + rudder fine-tuning for small heading errors ===
	# Rudder correction fades at high bank angles (not effective for heading in steep turns)
	var raw_yaw: float
	var yaw_smoothing: float
	if in_dogfight:
		# Dogfight yaw: do NOT use rudder as primary turn control.
		# Use mostly slip damping + small aiming trim, and fade with high bank.
		var sideslip_ratio: float = clampf(vel.dot(b.x) / maxf(speed, 1.0), -1.0, 1.0)
		var yaw_slip_damp: float = -sideslip_ratio * dogfight_sideslip_damping_gain
		var yaw_aim: float = bearing_err_rad * dogfight_aim_rudder_gain * (1.0 - high_bank_t)
		var yaw_coord: float = -sin(desired_bank) * dogfight_coord_rudder_gain * (1.0 - high_bank_t)
		raw_yaw = clampf(yaw_slip_damp + yaw_aim + yaw_coord, -dogfight_max_rudder_input, dogfight_max_rudder_input)
		yaw_smoothing = 0.25
	else:
		var yaw_turn: float = -sin(desired_bank) * lerp(1.0, high_bank_yaw_scale, high_bank_t)
		var yaw_correction: float
		if current_state in [State.APPROACH, State.LANDING]:
			# PD controller: proportional to bearing error, derivative damps yaw rate to prevent overshoot.
			var yaw_rate: float = ang_vel.dot(b.y)
			yaw_correction = clampf(bearing_err_rad * 1.5 - yaw_rate * 0.5, -0.7, 0.7)
		else:
			yaw_correction = clampf(bearing_err_rad * 0.25, -0.3, 0.3) * (1.0 - high_bank_t)
		raw_yaw = clampf(yaw_turn + yaw_correction, -1.0, 1.0)
		yaw_smoothing = lerp(input_smoothing, 0.5, high_bank_t)
	yaw_input = lerp(_smoothed_yaw_input, raw_yaw, yaw_smoothing)
	_smoothed_yaw_input = yaw_input
	
	# === THROTTLE ===
	var commanded_target_speed: float = _get_effective_target_speed()
	var speed_error: float = commanded_target_speed - speed
	throttle_input += clamp(speed_error * 0.01, -0.05, 0.05)
	var thr_min: float = 0.4
	if current_state == State.APPROACH and _landing_phase >= 1:
		thr_min = approach_post_gate_min_throttle
	elif current_state == State.LANDING:
		var dist_to_touchdown: float = Vector2(aircraft.global_position.x - nav_waypoint.x, aircraft.global_position.z - nav_waypoint.z).length()
		if dist_to_touchdown < 150.0:
			thr_min = 0.25  # Allow lower throttle on short final to avoid overflying
	throttle_input = clamp(throttle_input, thr_min, 1.0)
	throttle_input += clamp(bank_rad / deg_to_rad(30.0), 0.0, 1.0) * 0.15
	if current_state == State.APPROACH and _landing_phase >= 1 and speed > target_speed + approach_post_gate_slowdown_margin_mps:
		throttle_input = minf(throttle_input, approach_post_gate_throttle_cut)
	throttle_input = clamp(throttle_input, 0.0, 1.0)
	
	# Low speed protection ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â full throttle, limit pitch-up to avoid bleeding more energy
	if speed < stall_speed_mps + stall_margin_mps:
		if current_state == State.DOGFIGHT:
			var speed_shortfall: float = maxf((stall_speed_mps + stall_margin_mps) - speed, 0.0)
			var extra_unload_t: float = clampf(speed_shortfall / 20.0, 0.0, 1.0)
			var dogfight_pitch_cap: float = lerpf(dogfight_low_speed_pitch_cap, 0.0, extra_unload_t)
			pitch_input = clamp(pitch_input, -0.6, dogfight_pitch_cap)
		else:
			pitch_input = clamp(pitch_input, -0.5, 0.3)
		throttle_input = 1.0
	
	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 30 == 0:
		var alt: float = aircraft.global_position.y
		var horiz_len_safe: float = max(horiz_len, 0.01)
		var lateral_norm: float = local_horiz_x / horiz_len_safe
		var ahead_norm: float = local_horiz_z / horiz_len_safe
		if horiz_len <= 1.0:
			print("[AIPilot %s] WARNING: horiz_len=%.1f <= 1.0 - NOT computing bank! Target too close or behind?" % [aircraft.name, horiz_len])
		# Target position: AHEAD/BEHIND + LEFT/RIGHT
		var target_pos := "AHEAD" if ahead_norm > 0.3 else ("BEHIND" if ahead_norm < -0.3 else "ABEAM")
		if abs(lateral_norm) > 0.3:
			target_pos += "-" + ("RIGHT" if lateral_norm > 0 else "LEFT")
		# Turn direction: banking which way to intercept
		var turn_dir := "STRAIGHT"
		if abs(rad_to_deg(desired_bank)) > 2.0:
			turn_dir = "BANK-RIGHT" if desired_bank > 0 else "BANK-LEFT"
		# Aircraft heading (degrees, 0=+Z)
		var heading_deg := rad_to_deg(atan2(aircraft.global_transform.basis.z.x, aircraft.global_transform.basis.z.z))
		# Bearing to waypoint (degrees)
		var bearing_to_wp := rad_to_deg(atan2(horiz_to_target.x, horiz_to_target.z)) if horiz_len > 0.1 else heading_deg
		var bearing_err := _normalize_angle(deg_to_rad(bearing_to_wp - heading_deg)) if horiz_len > 0.1 else 0.0
		print("=== [AIPilot %s] STEERING ===" % aircraft.name)
		print("  WAYPOINT: nav=(%.0f,%.0f,%.0f)  maneuver=(%.0f,%.0f,%.0f)" % [nav_waypoint.x, nav_waypoint.y, nav_waypoint.z, maneuver_waypoint.x, maneuver_waypoint.y, maneuver_waypoint.z])
		print("  TARGET: %s  dist=%.0fm  bearing=%.0fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  heading=%.0fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  err=%.0fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â° (pos=turn R)" % [target_pos, to_target.length(), bearing_to_wp, heading_deg, rad_to_deg(bearing_err)])
		var vel_fwd: float = vel.dot(aircraft.global_transform.basis.z)
		var vel_right: float = vel.dot(aircraft.global_transform.basis.x)
		var turning: String = "RIGHT" if vel_right > 5 else ("LEFT" if vel_right < -5 else "STRAIGHT")
		print("  TURN: %s  desired_bank=%.1fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  current_roll=%.1fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  bank_err=%.1fÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  commit=%.0f  flip=%s" % [turn_dir, rad_to_deg(desired_bank), rad_to_deg(current_roll), rad_to_deg(bank_error), _committed_turn_sign, flip_roll_direction])
		print("  ACTUAL: turning=%s (vel_right=%.1f)  vel_fwd=%.1f" % [turning, vel_right, vel_fwd])
		print("  LOCAL: lx=%.2f (right+)  lz=%.2f (ahead+)  lateral_ratio=%.2f" % [lateral_norm, ahead_norm, lateral_norm])
		print("  CMD: roll=%.2f  pitch=%.2f  yaw=%.2f  thr=%.2f" % [roll_input, pitch_input, yaw_input, throttle_input])
		print("  ALT: %.0fm (tgt %.0f)  spd=%.0f  vs=%.1f" % [alt, nav_waypoint.y, speed, vel.y])

func _update_maneuver_waypoint():
	"""Place maneuver waypoint along the direction TO the navigation waypoint"""
	if nav_waypoint == Vector3.ZERO:
		return
	
	# LANDING: always steer directly at approach_4 (touchdown point). No lookahead ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â we must
	# fly to the deck, not past it. The general lookahead helps turning but causes overfly on final.
	if current_state == State.LANDING:
		maneuver_waypoint = nav_waypoint
		if nav_target:
			nav_target.global_position = maneuver_waypoint
		return
		
	var to_nav: Vector3 = nav_waypoint - aircraft.global_position
	var horizontal_distance: float = Vector2(to_nav.x, to_nav.z).length()
	
	if horizontal_distance < 100.0:
		maneuver_waypoint = nav_waypoint
	else:
		var dir_to_nav: Vector3 = to_nav.normalized()
		var lookahead: float = min(maneuver_lookahead_distance, horizontal_distance)
		maneuver_waypoint = aircraft.global_position + dir_to_nav * lookahead
		maneuver_waypoint.y = nav_waypoint.y
	
	if nav_target:
		nav_target.global_position = maneuver_waypoint

func _create_waypoint_marker():
	"""Create lime green box marker: 1x1m footprint, 1000m tall, extending up from ground."""
	if _waypoint_marker:
		return
	var box := BoxMesh.new()
	box.size = Vector3(10.0, 1000.0, 10.0)  # 10m footprint (visible from distance), 1000m tall
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.5, 1.0, 0.0, 0.2)  # Lime green at 20% opacity
	mat.emission_enabled = true
	mat.emission = Color(0.5, 1.0, 0.0, 0.2)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Always visible
	_waypoint_marker = MeshInstance3D.new()
	_waypoint_marker.name = "WaypointMarker_" + aircraft.name
	_waypoint_marker.mesh = box
	_waypoint_marker.material_override = mat
	# BoxMesh is centered; offset so base is at y=0 (box goes from -500 to +500 in Y)
	_waypoint_marker.position = Vector3(0, 500, 0)  # Center at y=500 for 1000m height
	# Add to scene root so it's in world space (avoids aircraft transform/culling issues)
	get_tree().current_scene.add_child(_waypoint_marker)

func _update_waypoint_marker():
	"""Position marker at nav waypoint, or target during attack phases."""
	if not _waypoint_marker:
		return
	# Only show when actively navigating/attacking
	if current_state not in [State.TRANSIT, State.SEARCH, State.ATTACK_POSITIONING, State.ATTACK_INBOUND, State.ATTACK_DIVE, State.ATTACK_BREAK_OFF, State.ENGAGE, State.RECOVERY_MARSHAL, State.RECOVERY_HOLD, State.RECOVERY_APPROACH, State.APPROACH, State.LANDING, State.MISSED_APPROACH]:
		_waypoint_marker.visible = false
		return
	var marker_world: Vector3 = nav_waypoint
	var attack_states := [State.ATTACK_POSITIONING, State.ATTACK_INBOUND, State.ATTACK_DIVE, State.ATTACK_BREAK_OFF, State.ENGAGE]
	if current_state in attack_states and combat_target and is_instance_valid(combat_target):
		marker_world = combat_target.global_position
	elif marker_world == Vector3.ZERO:
		marker_world = maneuver_waypoint
	if marker_world == Vector3.ZERO:
		_waypoint_marker.visible = false
		return
	_waypoint_marker.visible = true
	# Box extends from y=0 to y=1000 (center at y=500)
	_waypoint_marker.global_position = Vector3(marker_world.x, 500, marker_world.z)

func _get_bomb_debug_node(key: String, color: Color) -> MeshInstance3D:
	if _bomb_debug_nodes.has(key):
		var existing: Variant = _bomb_debug_nodes[key]
		if existing is MeshInstance3D and is_instance_valid(existing):
			return existing
	var scene_root: Node = get_tree().current_scene if get_tree() else null
	if scene_root == null:
		return null
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b, color.a)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var node := MeshInstance3D.new()
	node.name = "BombDebug_%s_%s" % [key, aircraft.name if aircraft else "AI"]
	node.mesh = box
	node.material_override = mat
	scene_root.add_child(node)
	_bomb_debug_nodes[key] = node
	return node

func _set_bomb_debug_column(key: String, pos: Vector3, color: Color, footprint_m: float, height_m: float) -> void:
	var node := _get_bomb_debug_node(key, color)
	if node == null:
		return
	var box := node.mesh as BoxMesh
	if box:
		box.size = Vector3(footprint_m, height_m, footprint_m)
	node.visible = true
	node.global_transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * height_m * 0.5)

func _set_bomb_debug_line(key: String, start_pos: Vector3, end_pos: Vector3, color: Color, thickness_m: float) -> void:
	var node := _get_bomb_debug_node(key, color)
	if node == null:
		return
	var length: float = start_pos.distance_to(end_pos)
	if length < 1.0:
		node.visible = false
		return
	var box := node.mesh as BoxMesh
	if box:
		box.size = Vector3(thickness_m, thickness_m, length)
	var z_axis: Vector3 = (end_pos - start_pos) / length
	var x_axis: Vector3 = Vector3.UP.cross(z_axis)
	if x_axis.length_squared() <= 0.0001:
		x_axis = Vector3.RIGHT.cross(z_axis)
	x_axis = x_axis.normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	node.visible = true
	node.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis).orthonormalized(), start_pos.lerp(end_pos, 0.5))

func _hide_bomb_debug_visuals() -> void:
	for node_variant in _bomb_debug_nodes.values():
		if node_variant is Node3D and is_instance_valid(node_variant):
			(node_variant as Node3D).visible = false

func _clear_bomb_debug_visuals() -> void:
	for node_variant in _bomb_debug_nodes.values():
		if node_variant is Node and is_instance_valid(node_variant):
			(node_variant as Node).queue_free()
	_bomb_debug_nodes.clear()

func _update_bomb_debug_visuals(
	aim_pos: Vector3,
	release_target_pos: Vector3,
	ccip_impact: Vector3,
	target_velocity: Vector3,
	horiz_dist: float,
	alt_above: float,
	delta: float,
	current_target_pos: Vector3 = Vector3.ZERO
) -> void:
	if not debug_enabled:
		_hide_bomb_debug_visuals()
		return
	if bomb_debug_markers_enabled:
		var marker_height: float = maxf(bomb_debug_marker_height_m, 20.0)
		var line_thickness: float = maxf(bomb_debug_line_thickness_m, 0.5)
		_set_bomb_debug_column("Target", release_target_pos, Color(1.0, 0.1, 0.1, 0.35), 12.0, marker_height)
		_set_bomb_debug_column("Aim", aim_pos, Color(1.0, 0.9, 0.1, 0.32), 8.0, marker_height * 0.55)
		_set_bomb_debug_line("AircraftToAim", aircraft.global_position, aim_pos, Color(1.0, 0.9, 0.1, 0.45), line_thickness)
		if ccip_impact != Vector3.ZERO:
			_set_bomb_debug_column("CCIP", ccip_impact, Color(0.1, 0.7, 1.0, 0.35), 10.0, marker_height)
			_set_bomb_debug_line("CCIPMiss", ccip_impact + Vector3.UP * 8.0, release_target_pos + Vector3.UP * 8.0, Color(1.0, 0.0, 1.0, 0.55), line_thickness)
		else:
			for key in ["CCIP", "CCIPMiss"]:
				if _bomb_debug_nodes.has(key):
					var node_variant: Variant = _bomb_debug_nodes[key]
					if node_variant is Node3D and is_instance_valid(node_variant):
						(node_variant as Node3D).visible = false
	else:
		_hide_bomb_debug_visuals()

	if not bomb_debug_print_enabled:
		return
	_bomb_debug_print_timer_s -= delta
	if _bomb_debug_print_timer_s > 0.0:
		return
	_bomb_debug_print_timer_s = maxf(bomb_debug_print_interval_s, 0.1)
	var ccip_miss: float = Vector2(release_target_pos.x - ccip_impact.x, release_target_pos.z - ccip_impact.z).length() if ccip_impact != Vector3.ZERO else -1.0
	var current_ccip_miss: float = Vector2(current_target_pos.x - ccip_impact.x, current_target_pos.z - ccip_impact.z).length() if ccip_impact != Vector3.ZERO else -1.0
	var target_lead_m: float = Vector2(release_target_pos.x - current_target_pos.x, release_target_pos.z - current_target_pos.z).length()
	var release_ccip_miss: float = ccip_miss
	if current_ccip_miss >= 0.0 and target_lead_m > 1.0:
		release_ccip_miss = minf(ccip_miss, current_ccip_miss)
	var release_tolerance_m: float = _get_effective_bomb_release_tolerance_m()
	var displayed_best_miss: float = _best_bomb_ccip_miss_this_run
	if ccip_impact != Vector3.ZERO:
		displayed_best_miss = minf(displayed_best_miss, release_ccip_miss)
	var near_best_solution: bool = ccip_impact != Vector3.ZERO and release_ccip_miss <= displayed_best_miss + maxf(bomb_release_best_miss_slack_m, 0.0)
	var release_at_best_solution: bool = ccip_impact != Vector3.ZERO and _is_bomb_best_solution_release_moment(release_ccip_miss, _prev_ccip_miss, _best_bomb_ccip_miss_this_run, release_tolerance_m)
	var horiz_speed: float = Vector2(aircraft.linear_velocity.x, aircraft.linear_velocity.z).length()
	var fpa_deg: float = rad_to_deg(atan2(-aircraft.linear_velocity.y, max(horiz_speed, 1.0)))
	var bank_deg: float = _get_current_bank_angle_deg()
	var release_hold_s: float = 0.0 if release_at_best_solution else _get_effective_bomb_release_hold_s()
	var stable_ready: bool = release_at_best_solution or _release_solution_stable_time_s >= release_hold_s
	var miss_gate_ok: bool = (release_ccip_miss <= release_tolerance_m and near_best_solution) or release_at_best_solution
	var release_geometry_ok: bool = ccip_impact != Vector3.ZERO \
		and miss_gate_ok \
		and bank_deg <= bomb_release_max_bank_deg \
		and alt_above <= bomb_release_altitude_window_m \
		and alt_above >= 5.0 \
		and horiz_dist >= bomb_release_min_range_m \
		and fpa_deg >= bomb_min_dive_angle_deg
	var release_now: bool = release_geometry_ok and stable_ready
	var release_block: String = "ok"
	if ccip_impact == Vector3.ZERO:
		release_block = "no_ccip"
	elif bank_deg > bomb_release_max_bank_deg:
		release_block = "bank"
	elif alt_above > bomb_release_altitude_window_m:
		release_block = "high"
	elif alt_above < 5.0:
		release_block = "low"
	elif horiz_dist < bomb_release_min_range_m:
		release_block = "close"
	elif fpa_deg < bomb_min_dive_angle_deg:
		release_block = "shallow"
	elif release_at_best_solution:
		release_block = "best"
	elif release_ccip_miss > release_tolerance_m:
		release_block = "ccip_miss"
	elif not near_best_solution:
		release_block = "past_best"
	elif not stable_ready:
		release_block = "hold"
	var aim_err_deg: float = 0.0
	var to_aim: Vector3 = aim_pos - aircraft.global_position
	if to_aim.length_squared() > 1.0:
		aim_err_deg = rad_to_deg(acos(clampf(aircraft.global_transform.basis.z.normalized().dot(to_aim.normalized()), -1.0, 1.0)))
	var miss_forward_m: float = 0.0
	var miss_side_m: float = 0.0
	var current_miss_m: float = -1.0
	var current_forward_m: float = 0.0
	var current_side_m: float = 0.0
	if ccip_impact != Vector3.ZERO:
		var forward_ref: Vector3 = Vector3(target_velocity.x, 0.0, target_velocity.z)
		if forward_ref.length_squared() <= 0.01:
			forward_ref = Vector3(aircraft.global_transform.basis.z.x, 0.0, aircraft.global_transform.basis.z.z)
		forward_ref = forward_ref.normalized() if forward_ref.length_squared() > 0.01 else Vector3.FORWARD
		var right_ref: Vector3 = Vector3.UP.cross(forward_ref).normalized()
		var miss_vec: Vector3 = Vector3(release_target_pos.x - ccip_impact.x, 0.0, release_target_pos.z - ccip_impact.z)
		miss_forward_m = miss_vec.dot(forward_ref)
		miss_side_m = miss_vec.dot(right_ref)
		var current_vec: Vector3 = Vector3(current_target_pos.x - ccip_impact.x, 0.0, current_target_pos.z - ccip_impact.z)
		current_miss_m = Vector2(current_vec.x, current_vec.z).length()
		current_forward_m = current_vec.dot(forward_ref)
		current_side_m = current_vec.dot(right_ref)
	print("[AIPilot BOMBDBG] %s hdist=%.0fm alt=%.0fm fpa=%.1fdeg bank=%.1fdeg aim_err=%.1fdeg ccip=%s miss=%.0fm best=%.0fm tol=%.0fm fwd=%.0fm side=%.0fm cur_miss=%.0fm cur_fwd=%.0fm cur_side=%.0fm lead=%.0fm release=%s block=%s stable=%.2fs hold=%.2fs tof=%.2fs target_vel=%.1f" % [
		aircraft.name if aircraft else "AI",
		horiz_dist,
		alt_above,
		fpa_deg,
		bank_deg,
		aim_err_deg,
		str(ccip_impact != Vector3.ZERO),
		ccip_miss,
		displayed_best_miss,
		release_tolerance_m,
		miss_forward_m,
		miss_side_m,
		current_miss_m,
		current_forward_m,
		current_side_m,
		target_lead_m,
		str(release_now),
		release_block,
		_release_solution_stable_time_s,
		release_hold_s,
		_ccip_cached_tof_s,
		target_velocity.length()
	])

func _apply_turn_controls(desired_pitch: float, desired_roll: float, delta: float):
	"""Apply control inputs to execute a coordinated turn"""

	# Get current aircraft attitude
	var current_pitch = _get_forward_pitch_rad()
	var current_roll = atan2(aircraft.global_transform.basis.y.x, aircraft.global_transform.basis.y.y)

	# ROLL CONTROL - Establish bank angle
	var roll_error = _normalize_angle(desired_roll - current_roll)
	roll_input = roll_error * 3.0  # Direct proportional control
	roll_input = clamp(roll_input, -1.0, 1.0)

	# PITCH CONTROL - Pull back to turn
	var pitch_error = desired_pitch - current_pitch
	pitch_input = pitch_controller.update(pitch_error, delta)
	pitch_input = clamp(pitch_input, -1.0, 1.0)

	# RUDDER - Coordinate turn based on bank angle
	# More bank = more rudder in direction of turn
	var bank_amount = abs(current_roll) / max_roll_angle  # 0 to 1
	yaw_input = sign(current_roll) * bank_amount * 0.5  # Rudder proportional to bank
	yaw_input = clamp(yaw_input, -1.0, 1.0)

	# Debug
	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 60 == 0:
		var current_alt = aircraft.global_position.y
		var vertical_speed = aircraft.linear_velocity.y
		print("[AIPilot TURN] Bank: ", snapped(rad_to_deg(current_roll), 0.1), "ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â° Pitch: ", snapped(rad_to_deg(current_pitch), 0.1),
			  "ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â° Alt: ", snapped(current_alt, 0.1), " VS: ", snapped(vertical_speed, 0.1))

func _navigate_to_altitude_and_speed(delta: float):
	"""Navigate to target altitude and speed (waypoint-based)"""

	# Set navigation waypoint: straight ahead at target altitude
	var forward = aircraft.global_transform.basis.z
	nav_waypoint = aircraft.global_position + forward * 1000.0
	nav_waypoint.y = target_altitude
	
	# Update maneuvering waypoint to lead toward navigation waypoint
	_update_maneuver_waypoint()
	
	_navigate_to_waypoint(delta)

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

func _evaluate_terrain_fan() -> void:
	"""Sample terrain clearance in a fan of directions ahead of the aircraft.
	Fills _terrain_fan_clearances with the minimum clearance along each direction,
	and sets _terrain_fan_best_idx to the direction with the most clearance."""
	var vel := aircraft.linear_velocity
	var horiz_speed := Vector2(vel.x, vel.z).length()
	var vert_speed := vel.y

	var heading_dir: Vector3
	if horiz_speed > 10.0:
		heading_dir = Vector3(vel.x, 0.0, vel.z).normalized()
	else:
		var fwd := aircraft.global_transform.basis.z
		heading_dir = Vector3(fwd.x, 0.0, fwd.z).normalized()
		horiz_speed = maxf(horiz_speed, 30.0)

	var fan_angles := [-60.0, -30.0, 0.0, 30.0, 60.0]
	var max_lookahead_s: float = clampf(1.8 + horiz_speed / 120.0, 1.8, 4.0)
	var lookahead_times := [0.5, 1.0, minf(1.7, max_lookahead_s), max_lookahead_s]
	var pos := aircraft.global_position

	var best_clearance := -INF
	_terrain_fan_best_idx = 2

	for i in range(fan_angles.size()):
		var angle_rad := deg_to_rad(fan_angles[i])
		var ca := cos(angle_rad)
		var sa := sin(angle_rad)
		# Rotate heading direction horizontally
		var dir := Vector3(
			heading_dir.x * ca - heading_dir.z * sa,
			0.0,
			heading_dir.x * sa + heading_dir.z * ca
		)

		var min_clearance := INF
		for t in lookahead_times:
			var projected_pos: Vector3 = pos + dir * horiz_speed * t + Vector3.UP * vert_speed * t
			var terrain_h: float = _get_ground_height_at_position(projected_pos)
			if is_nan(terrain_h):
				continue
			var clearance: float = projected_pos.y - terrain_h
			min_clearance = minf(min_clearance, clearance)

		_terrain_fan_clearances[i] = min_clearance
		if min_clearance > best_clearance:
			best_clearance = min_clearance
			_terrain_fan_best_idx = i

func _check_terrain_avoidance(_delta: float) -> bool:
	"""Directional terrain avoidance using fan-sampled clearance data.
	Steers toward the safest direction when terrain is threatening ahead.
	Returns true if controls were overridden."""
	if current_state in [State.LAUNCHING, State.LANDING, State.IDLE, State.MISSED_APPROACH]:
		return false
	if current_state == State.CLIMBING and aircraft.linear_velocity.y > 2.0:
		return false

	# State-specific safety margins (how much clearance we need to feel safe)
	var safety_margin: float
	if current_state == State.APPROACH:
		safety_margin = 45.0
	elif current_state == State.ATTACK_DIVE:
		safety_margin = 60.0
	elif current_state in [State.DOGFIGHT, State.ATTACK_POSITIONING, State.ATTACK_INBOUND, State.ATTACK_BREAK_OFF]:
		safety_margin = 80.0
	else:
		safety_margin = emergency_min_agl_m  # 180.0

	var fan_angles := [-60.0, -30.0, 0.0, 30.0, 60.0]
	var forward_clearance: float = _terrain_fan_clearances[2]  # 0 degrees = forward
	var best_idx := _terrain_fan_best_idx
	var best_clearance: float = _terrain_fan_clearances[best_idx]

	# Also incorporate the raycast-based terrain_ahead_distance as a forward threat signal.
	# The raycast catches geometry that terrain height API may miss (overhangs, non-terrain).
	var vel := aircraft.linear_velocity
	var forward_speed: float = maxf(vel.length(), 10.0)
	var tti: float = terrain_ahead_distance / forward_speed
	var sink_mps: float = maxf(-vel.y, 0.0)
	var dynamic_margin: float = safety_margin
	dynamic_margin += clampf((forward_speed - 90.0) * 0.8, 0.0, 120.0)
	dynamic_margin += clampf(sink_mps * 5.0, 0.0, 80.0)
	var imminent_terrain: bool = terrain_ahead_distance < INF and tti <= (emergency_tti_s + 0.8)
	var critical_terrain: bool = terrain_ahead_distance < INF and tti <= emergency_tti_s
	if _is_committed_direct_fire_attack_run(tti):
		imminent_terrain = false
		critical_terrain = false
		var commit_min_agl: float = rocket_attack_commit_min_agl_m if _run_weapon_type == "Rocket Pod" else gun_attack_commit_min_agl_m
		dynamic_margin = minf(dynamic_margin, maxf(commit_min_agl, 20.0))
	if terrain_ahead_distance < INF and tti < 2.8:
		forward_clearance = minf(forward_clearance, terrain_ahead_distance * 0.5)

	# If forward is fine AND we're not dangerously low, no override needed.
	var is_climbing: bool = current_state in [State.DOGFIGHT, State.ATTACK_POSITIONING, State.ATTACK_INBOUND] and vel.y > 0.0
	var agl_ok: bool
	if current_state == State.APPROACH:
		agl_ok = altitude_agl > 20.0 or vel.y > -6.0
	elif is_climbing:
		agl_ok = altitude_agl > 30.0
	else:
		agl_ok = altitude_agl > dynamic_margin

	if forward_clearance > dynamic_margin and agl_ok and not imminent_terrain:
		return false

	# We're in danger. Decide: turn or climb?
	var escape_angle_deg: float = fan_angles[best_idx]
	var emergency_escape: bool = altitude_agl < emergency_min_agl_m or critical_terrain or forward_clearance < dynamic_margin * 0.6
	var lateral_advantage_margin: float = 20.0 if emergency_escape else 30.0
	var lateral_is_better: bool = best_clearance > forward_clearance + lateral_advantage_margin and best_idx != 2
	var stall_floor_speed: float = maxf(stall_speed_mps + stall_margin_mps, 1.0)
	var speed_margin: float = forward_speed - stall_floor_speed
	var energy_t: float = clampf(speed_margin / maxf(terrain_escape_full_pull_speed_margin_mps, 1.0), 0.0, 1.0)
	var pitch_cap: float = lerpf(
		maxf(terrain_escape_low_speed_pitch_input, 0.0),
		maxf(terrain_escape_max_pitch_input, terrain_escape_low_speed_pitch_input),
		energy_t
	)
	if critical_terrain:
		pitch_cap = minf(pitch_cap + 0.12 * energy_t, 0.78)
	var target_pitch_deg: float = lerpf(
		terrain_escape_min_target_pitch_deg,
		terrain_escape_max_target_pitch_deg,
		energy_t
	)
	if critical_terrain:
		target_pitch_deg += terrain_escape_critical_pitch_bonus_deg * energy_t
	var current_pitch_rad: float = _get_forward_pitch_rad()
	var pitch_rate_up: float = -aircraft.angular_velocity.dot(aircraft.global_transform.basis.x)
	var escape_pitch_input: float = clampf(
		(deg_to_rad(target_pitch_deg) - current_pitch_rad) * 2.8 - pitch_rate_up * 0.35,
		-0.12,
		pitch_cap
	)
	var sink_pull_floor: float = lerpf(0.0, minf(pitch_cap, 0.45), clampf(sink_mps / 18.0, 0.0, 1.0) * energy_t)
	escape_pitch_input = maxf(escape_pitch_input, sink_pull_floor)

	if lateral_is_better and not emergency_escape and altitude_agl > emergency_min_agl_m + 40.0:
		# A lateral direction has more clearance; turn toward it without bleeding all energy.
		var bank_sign: float = signf(escape_angle_deg)
		var lateral_roll_t: float = clampf(energy_t, 0.25, 1.0)
		roll_input = bank_sign * terrain_escape_lateral_roll_input * lateral_roll_t
		pitch_input = escape_pitch_input
	else:
		# No good lateral escape; level the wings and climb without over-rotating.
		roll_input = 0.0
		pitch_input = escape_pitch_input

	yaw_input = 0.0
	throttle_input = 1.0
	target_speed = maxf(target_speed, stall_floor_speed + 35.0)
	# Slam smoothed values so the state machine doesn't fight the override next frame.
	_smoothed_roll_input = roll_input
	_smoothed_pitch_input = pitch_input
	_smoothed_yaw_input = 0.0

	# Force state transition out of attack if needed.
	if current_state in [State.ATTACK_DIVE, State.ATTACK_POSITIONING, State.ATTACK_INBOUND]:
		_attack_recovery_until_s = maxf(_attack_recovery_until_s, Time.get_ticks_msec() / 1000.0 + 4.0)
		change_state(State.ATTACK_BREAK_OFF)

	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 30 == 0:
		var action: String = ("TURN %.0f deg" % escape_angle_deg) if lateral_is_better else "CLIMB"
		print("[AIPilot TERRAIN] AGL=%.0fm fwd_clr=%.0fm need=%.0fm tti=%.1fs spd=%.0fmps margin=%.0fmps pitch=%.2f cap=%.2f best_dir=%.0fdeg best_clr=%.0fm -- %s" % [
			altitude_agl, forward_clearance, dynamic_margin, tti, forward_speed, speed_margin, pitch_input, pitch_cap, escape_angle_deg, best_clearance, action])
	return true

func _is_committed_rocket_attack_run(terrain_tti_s: float) -> bool:
	if current_state != State.ATTACK_DIVE:
		return false
	if _run_weapon_type != "Rocket Pod":
		return false
	if _rockets_to_fire_this_run <= 0 or _rockets_fired_this_run >= _rockets_to_fire_this_run:
		return false
	if combat_target == null or not is_instance_valid(combat_target):
		return false
	if altitude_agl < maxf(rocket_attack_commit_min_agl_m, 1.0):
		return false
	if terrain_tti_s < maxf(rocket_attack_commit_critical_tti_s, 0.2):
		return false
	var target_pos: Vector3 = _get_surface_target_position(combat_target)
	var horiz_dist: float = Vector2(
		aircraft.global_position.x - target_pos.x,
		aircraft.global_position.z - target_pos.z
	).length()
	if horiz_dist < maxf(rocket_pull_up_distance_m, rocket_release_min_range_m * 0.75):
		return false
	return horiz_dist <= rocket_release_max_range_m + maxf(rocket_attack_commit_extra_range_m, 0.0)

func _is_committed_direct_fire_attack_run(terrain_tti_s: float) -> bool:
	if _is_committed_rocket_attack_run(terrain_tti_s):
		return true
	if current_state != State.ATTACK_DIVE:
		return false
	if _run_weapon_type == "Bomb" or _run_weapon_type == "Rocket Pod" or _run_weapon_type == "AAMissile":
		return false
	if combat_target == null or not is_instance_valid(combat_target):
		return false
	if altitude_agl < maxf(gun_attack_commit_min_agl_m, 1.0):
		return false
	if terrain_tti_s < maxf(gun_attack_commit_critical_tti_s, 0.2):
		return false
	var target_pos: Vector3 = _get_surface_target_position(combat_target)
	var horiz_dist: float = Vector2(
		aircraft.global_position.x - target_pos.x,
		aircraft.global_position.z - target_pos.z
	).length()
	if horiz_dist < maxf(attack_pull_up_distance_m, 1.0):
		return false
	var gun_range_m: float = _get_selected_gun_max_range_m()
	if not is_finite(gun_range_m):
		gun_range_m = 700.0
	return horiz_dist <= gun_range_m + maxf(gun_attack_commit_extra_range_m, 0.0)

func _should_run_collision_avoidance(delta: float) -> bool:
	if current_state in [State.LAUNCHING, State.LANDING, State.IDLE]:
		_collision_avoidance_timer_s = 0.0
		return false
	_collision_avoidance_timer_s -= delta
	if _collision_avoidance_timer_s > 0.0:
		return false
	var interval_s: float = maxf(collision_avoidance_interval_s, 0.02)
	if current_state in [State.ATTACK_DIVE, State.DOGFIGHT]:
		interval_s *= 0.5
	_collision_avoidance_timer_s = interval_s
	return true

func _check_collision_avoidance(_delta: float) -> bool:
	"""Avoid mid-air collisions with other aircraft.
	Uses time-to-closest-approach (TCA) to detect imminent collisions and steer away.
	Returns true if controls were overridden."""
	if current_state in [State.LAUNCHING, State.LANDING, State.IDLE]:
		return false

	var my_pos := aircraft.global_position
	var my_vel := aircraft.linear_velocity

	var closest_tca := INF
	var closest_miss := INF
	var closest_threat: Node3D = null
	var closest_rel_pos := Vector3.ZERO

	# Check all known contacts (enemies + friendlies)
	var all_contacts: Array = []
	all_contacts.append_array(known_enemies)
	all_contacts.append_array(known_friendlies)

	for contact in all_contacts:
		if not is_instance_valid(contact) or not (contact is Node3D):
			continue
		var cnode := contact as Node3D
		# Only worry about things near our altitude (skip ground vehicles etc)
		if absf(cnode.global_position.y - my_pos.y) > 200.0:
			continue
		var rel_pos: Vector3 = cnode.global_position - my_pos
		if rel_pos.length_squared() > 160000.0:
			continue
		# Get contact velocity
		var contact_vel := Vector3.ZERO
		var lv = cnode.get("linear_velocity")
		if lv is Vector3:
			contact_vel = lv
		else:
			var v = cnode.get("velocity")
			if v is Vector3:
				contact_vel = v
		var rel_vel: Vector3 = contact_vel - my_vel
		var rel_speed_sq: float = rel_vel.length_squared()
		if rel_speed_sq < 1.0:
			continue
		# Time to closest approach
		var tca: float = -rel_pos.dot(rel_vel) / rel_speed_sq
		if tca < 0.0 or tca > 3.0:
			continue
		# Miss distance at closest approach
		var miss_vec: Vector3 = rel_pos + rel_vel * tca
		var miss_dist: float = miss_vec.length()
		var coll_miss_threshold: float = 25.0 if current_state == State.ATTACK_DIVE else 80.0
		if miss_dist < coll_miss_threshold and tca < closest_tca:
			closest_tca = tca
			closest_miss = miss_dist
			closest_threat = cnode
			closest_rel_pos = rel_pos

	if closest_threat == null:
		return false

	# Evade: turn away from the threat aircraft
	var away_horiz := Vector3(-closest_rel_pos.x, 0.0, -closest_rel_pos.z)
	if away_horiz.length_squared() < 0.01:
		away_horiz = aircraft.global_transform.basis.x  # Default: dodge right
	away_horiz = away_horiz.normalized()

	# Which way to bank? Use dot with aircraft's right vector.
	var right: Vector3 = aircraft.global_transform.basis.x
	var bank_sign: float = signf(away_horiz.dot(right))

	# Proportional evasion â€” firm but not violent, so formation flight is possible
	var urgency: float = clampf(1.0 - closest_tca / 3.0, 0.3, 0.7)
	roll_input = bank_sign * urgency
	pitch_input = 0.3 * urgency
	yaw_input = 0.0
	throttle_input = 1.0
	_smoothed_roll_input = roll_input
	_smoothed_pitch_input = pitch_input
	_smoothed_yaw_input = 0.0

	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 30 == 0:
		print("[AIPilot COLLISION] threat=%s tca=%.1fs miss=%.0fm â€” EVADING" % [
			closest_threat.name, closest_tca, closest_miss])
	return true

func _apply_controls():
	"""Apply control inputs to aircraft modules"""
	if simple_aero:
		var out_roll := -roll_input if invert_roll_sign else roll_input
		var out_pitch := -pitch_input if invert_pitch_sign else pitch_input
		var out_yaw := -yaw_input if invert_yaw_sign else yaw_input
		simple_aero.roll_input = out_roll
		simple_aero.pitch_input = out_pitch
		simple_aero.yaw_input = out_yaw

	if control_engine and control_engine.has_method("set_target_power"):
		control_engine.set_target_power(throttle_input)

func _update_ai_checkin(delta: float) -> void:
	if not ai_checkin_enabled or not aircraft:
		return
	_ai_checkin_timer -= delta
	if _ai_checkin_timer > 0.0:
		return
	_ai_checkin_timer = ai_checkin_interval_s

	var state_name: String = State.keys()[current_state]
	var pos: Vector3 = snapped(aircraft.global_position, Vector3.ONE)
	var spd: float = snapped(aircraft.linear_velocity.length(), 1.0)

	# Enemies in sensor range â€” list names, cap at 4
	var enemy_names: Array[String] = []
	for e in known_enemies:
		if is_instance_valid(e):
			enemy_names.append(e.name)
		if enemy_names.size() >= 4:
			break
	var enemy_str: String = "%d [%s]" % [known_enemies.size(), ", ".join(enemy_names)] if not enemy_names.is_empty() else "0"

	# Current target
	var target_str: String = combat_target.name if combat_target and is_instance_valid(combat_target) else "none"

	# Weapon readiness
	var bombs: int = _count_ready_bombs()
	var rockets: int = _count_ready_rockets()
	var bomb_ammo: int = _get_total_bomb_ammo()
	var rocket_ammo: int = _get_total_rocket_ammo()
	var weapon_str: String = _run_weapon_type if not _run_weapon_type.is_empty() else "none"

	# Health
	var hp_str: String = "%.0f%%" % (_get_health_fraction() * 100.0) if _get_health_fraction() >= 0.0 else "?"

	print("[CHECKIN] %s  state=%-22s pos=(%d,%d,%d)  spd=%.0fm/s  AGL=%.0f" % [
		aircraft.name, state_name, pos.x, pos.y, pos.z, spd, altitude_agl])
	print("          target=%-20s enemies=%s" % [target_str, enemy_str])
	print("          weapon=%-12s bombs=%d(x%d)  rockets=%d(x%d)  health=%s  prev_failed_bomb=%s" % [
		weapon_str, bombs, bomb_ammo, rockets, rocket_ammo, hp_str, str(_prev_run_was_failed_bomb)])


func _emit_player_debug_telemetry(delta: float) -> void:
	if not debug_enabled or aircraft == null:
		return
	_player_periodic_debug_timer_s -= delta
	if _player_periodic_debug_timer_s > 0.0:
		if verbose_debug_enabled:
			_debug_flight_path_alignment(delta, "PLAYER")
		return
	_player_periodic_debug_timer_s = maxf(general_debug_summary_interval_s, 0.25)
	var spd: float = aircraft.linear_velocity.length()
	var pos: Vector3 = aircraft.global_position
	var vs: float = aircraft.linear_velocity.y
	var pitch_deg: float = rad_to_deg(_get_forward_pitch_rad())
	var h_spd: float = Vector2(aircraft.linear_velocity.x, aircraft.linear_velocity.z).length()
	var fpa_deg: float = rad_to_deg(atan2(-aircraft.linear_velocity.y, max(h_spd, 1.0)))
	var player_pitch_cmd: float = 0.0
	var est_lift_ratio: float = 0.0
	var est_aoa_deg: float = 0.0
	if simple_aero:
		if "pitch_input" in simple_aero:
			player_pitch_cmd = float(simple_aero.pitch_input)
		if simple_aero.has_method("get_estimated_lift_ratio"):
			est_lift_ratio = float(simple_aero.call("get_estimated_lift_ratio"))
		if simple_aero.has_method("get_estimated_angle_of_attack_deg"):
			est_aoa_deg = float(simple_aero.call("get_estimated_angle_of_attack_deg"))
	print("[AIPilot STATUS] PLAYER pos=(%.0f,%.0f,%.0f) AGL=%.0f spd=%.1f VS=%.1f pitch=%.1fdeg fpa=%.1fdeg cmdP=%.2f aoa=%.1fdeg lift=%.2f" % [
		pos.x,
		pos.y,
		pos.z,
		altitude_agl,
		spd,
		vs,
		pitch_deg,
		fpa_deg,
		player_pitch_cmd,
		est_aoa_deg,
		est_lift_ratio
	])
	if verbose_debug_enabled:
		_debug_flight_path_alignment(delta, "PLAYER")

func _debug_flight_path_alignment(delta: float, state_override: String = "") -> void:
	if not debug_enabled or not verbose_debug_enabled or not flight_path_alignment_debug_enabled or aircraft == null:
		return
	if not _is_airborne():
		_flight_path_alignment_debug_timer_s = 0.0
		return
	var velocity: Vector3 = aircraft.linear_velocity
	var speed: float = velocity.length()
	if speed < maxf(flight_path_alignment_debug_min_speed_mps, 1.0):
		return
	_flight_path_alignment_debug_timer_s += delta
	var debug_interval_s: float = maxf(flight_path_alignment_debug_interval_s, _get_debug_summary_interval_s())
	if _flight_path_alignment_debug_timer_s < maxf(debug_interval_s, 0.25):
		return
	_flight_path_alignment_debug_timer_s = 0.0

	var nose_dir: Vector3 = aircraft.global_transform.basis.z.normalized()
	var vel_dir: Vector3 = velocity.normalized()
	var alignment_dot: float = clampf(nose_dir.dot(vel_dir), -1.0, 1.0)
	var alignment_angle_deg: float = rad_to_deg(acos(alignment_dot))
	var nose_flat: Vector2 = Vector2(nose_dir.x, nose_dir.z)
	var vel_flat: Vector2 = Vector2(vel_dir.x, vel_dir.z)
	var flat_alignment_angle_deg: float = 0.0
	if nose_flat.length_squared() > 0.0001 and vel_flat.length_squared() > 0.0001:
		flat_alignment_angle_deg = rad_to_deg(acos(clampf(nose_flat.normalized().dot(vel_flat.normalized()), -1.0, 1.0)))
	var state_name: String = state_override if not state_override.is_empty() else State.keys()[current_state]
	print("[AIPilot ALIGN] ", aircraft.name,
		" state=", state_name,
		" spd=", snapped(speed, 0.1),
		" angle3d=", snapped(alignment_angle_deg, 0.1),
		" angle2d=", snapped(flat_alignment_angle_deg, 0.1),
		" nose=", snapped(nose_dir, Vector3.ONE * 0.01),
		" vel=", snapped(vel_dir, Vector3.ONE * 0.01))

func _get_forward_pitch_rad() -> float:
	var forward: Vector3 = aircraft.global_transform.basis.z.normalized()
	var horiz_len: float = maxf(Vector2(forward.x, forward.z).length(), 0.0001)
	return atan2(forward.y, horiz_len)

func _is_airborne() -> bool:
	"""Check if aircraft is airborne"""
	# Simple check: altitude > 5m and speed > 30 m/s
	return aircraft.global_position.y > 5.0 and aircraft.linear_velocity.length() > 30.0

func _update_sensors(delta: float):
	"""Update AI's limited view of the world"""
	_terrain_check_counter += 1
	var dynamic_terrain_interval: int = max(terrain_check_interval, 1)
	var speed_mps: float = aircraft.linear_velocity.length() if aircraft else 0.0
	if altitude_agl < emergency_min_agl_m + 140.0 or speed_mps > 140.0:
		dynamic_terrain_interval = 1
	elif altitude_agl < emergency_min_agl_m + 260.0 or speed_mps > 110.0:
		dynamic_terrain_interval = min(dynamic_terrain_interval, 2)
	var run_terrain_checks: bool = (_terrain_check_counter % dynamic_terrain_interval) == 0

	# Update smoothed ground height and AGL every frame (cheap â€” uses cached terrain node)
	var gh: float = _get_ground_height_at_position(aircraft.global_position)
	if not is_nan(gh):
		if is_nan(_smoothed_ground_height):
			_smoothed_ground_height = gh
		else:
			_smoothed_ground_height = lerp(_smoothed_ground_height, gh, 0.05)

	# Update altitude above ground
	_update_agl()

	# Terrain-ahead and fan checks are expensive (many noise evals) â€” throttle to ~20 Hz
	if run_terrain_checks:
		_check_terrain_ahead()
		_evaluate_terrain_fan()

	# Contact filtering walks every cached sensor contact, so run it on a short timer
	# instead of every physics frame. Dogfights and attack runs keep a snappier cadence.
	_contact_scan_timer_s -= delta
	if _contact_scan_timer_s <= 0.0:
		var scan_interval_s: float = maxf(contact_scan_interval_s, 0.03)
		if current_state in [State.DOGFIGHT, State.ATTACK_POSITIONING, State.ATTACK_INBOUND, State.ATTACK_DIVE, State.ATTACK_BREAK_OFF]:
			scan_interval_s *= 0.5
		scan_interval_s *= lerpf(1.0, night_contact_scan_interval_multiplier, _get_ai_darkness_factor())
		_contact_scan_timer_s = scan_interval_s
		_scan_contacts()
	_report_contacts_to_air_ops(delta)

func _update_agl():
	"""Raycast down to find altitude above ground"""
	if aircraft and aircraft.has_method("get_effective_altitude_agl_m"):
		altitude_agl = float(aircraft.get_effective_altitude_agl_m())
		return
	var terrain_h: float = _get_ground_height_at_position(aircraft.global_position)
	if not is_nan(terrain_h):
		altitude_agl = aircraft.global_position.y - terrain_h
		return

	var space_state = aircraft.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		aircraft.global_position,
		aircraft.global_position + Vector3.DOWN * ground_check_distance
	)
	query.exclude = [aircraft]
	# Use all layers so this works with project-specific Terrain3D collision settings.
	query.collision_mask = 0xFFFFFFFF

	var result = space_state.intersect_ray(query)
	if result:
		altitude_agl = aircraft.global_position.distance_to(result.position)
	else:
		altitude_agl = aircraft.global_position.y  # Fallback to absolute altitude

func _check_terrain_ahead():
	"""Check for terrain ahead in flight path"""
	var space_state = aircraft.get_world_3d().direct_space_state

	# Cast forward along velocity vector (or +Z forward if stationary)
	var forward_dir: Vector3 = aircraft.linear_velocity.normalized() if aircraft.linear_velocity.length() > 10.0 else aircraft.global_transform.basis.z
	forward_dir = forward_dir.normalized()
	var ray_start: Vector3 = aircraft.global_position + Vector3.UP * 2.0
	var probe_dirs: Array[Vector3] = [
		forward_dir,
		(forward_dir + Vector3.DOWN * 0.22).normalized(),
		(forward_dir + Vector3.DOWN * 0.42).normalized(),
	]

	terrain_ahead_distance = INF
	for probe_dir in probe_dirs:
		var query = PhysicsRayQueryParameters3D.create(
			ray_start,
			ray_start + probe_dir * terrain_ahead_check_distance
		)
		query.exclude = [aircraft]
		# Use all layers so this works with project-specific Terrain3D collision settings.
		query.collision_mask = 0xFFFFFFFF
		var result = space_state.intersect_ray(query)
		if result:
			terrain_ahead_distance = minf(terrain_ahead_distance, ray_start.distance_to(result.position))

	if terrain_ahead_distance == INF:
		terrain_ahead_distance = INF
		# Fallback for Terrain3D setups where physics raycasts may miss:
		# sample terrain height ahead at a few distances and infer collision risk.
		var speed_mps: float = maxf(aircraft.linear_velocity.length(), 30.0)
		var dynamic_probe_distance: float = minf(
			terrain_ahead_check_distance,
			maxf(terrain_warning_distance * 2.0, speed_mps * (emergency_tti_s + 1.5))
		)
		var probe_distances := [
			terrain_warning_distance * 0.5,
			terrain_warning_distance,
			minf(terrain_ahead_check_distance, terrain_warning_distance * 2.0),
			dynamic_probe_distance,
		]
		var min_clearance_needed: float = maxf(30.0, emergency_min_agl_m * 0.55)
		for d in probe_distances:
			var probe_pos: Vector3 = aircraft.global_position + forward_dir * d
			var h: float = _get_ground_height_at_position(probe_pos)
			if is_nan(h):
				continue
			var clearance: float = probe_pos.y - h
			if clearance < min_clearance_needed:
				terrain_ahead_distance = min(terrain_ahead_distance, d)
				break

func _get_cached_terrain_node() -> Node:
	return TerrainReference.get_terrain_node()

func _get_ground_height_at_position(world_pos: Vector3) -> float:
	if not _terrain_height_callable.is_valid():
		var terrain: Node = _get_cached_terrain_node()
		if not terrain:
			return NAN
		if terrain.has_method("get_height"):
			_terrain_height_callable = Callable(terrain, "get_height")
		elif "data" in terrain and terrain.data and terrain.data.has_method("get_height"):
			_terrain_height_callable = Callable(terrain.data, "get_height")
		else:
			return NAN
	var h = _terrain_height_callable.call(world_pos)
	if typeof(h) == TYPE_FLOAT and not is_nan(float(h)):
		return float(h)
	return NAN

func _sample_max_terrain_height_along_path(from_pos: Vector3, to_pos: Vector3, num_samples: int) -> float:
	"""Sample terrain height at evenly-spaced points between two positions and return the maximum."""
	var max_h: float = NAN
	for i in range(num_samples):
		var t: float = float(i + 1) / float(num_samples + 1)
		var sample_pos: Vector3 = from_pos.lerp(to_pos, t)
		var h: float = _get_ground_height_at_position(sample_pos)
		if is_nan(h):
			continue
		if is_nan(max_h) or h > max_h:
			max_h = h
	return max_h

func _get_attack_setup_altitude_m(target_pos: Vector3, terrain_max: float = NAN) -> float:
	var setup_altitude_m: float = patrol_altitude_m
	if _run_weapon_type == "Bomb":
		setup_altitude_m = target_pos.y + bomb_run_setup_altitude_offset_m
		if not is_nan(terrain_max):
			setup_altitude_m = maxf(setup_altitude_m, terrain_max + bomb_run_setup_altitude_offset_m)
		var max_bomb_setup_altitude: float = target_pos.y + maxf(bomb_run_setup_max_altitude_offset_m, bomb_run_setup_altitude_offset_m)
		if not is_nan(terrain_max):
			max_bomb_setup_altitude = maxf(max_bomb_setup_altitude, terrain_max + 220.0)
		setup_altitude_m = minf(setup_altitude_m, max_bomb_setup_altitude)
	elif _run_weapon_type == "Rocket Pod":
		setup_altitude_m = maxf(setup_altitude_m, target_pos.y + rocket_run_altitude_offset_m)
		if not is_nan(terrain_max):
			setup_altitude_m = maxf(setup_altitude_m, terrain_max + rocket_run_altitude_offset_m)
	else:
		setup_altitude_m = maxf(setup_altitude_m, target_pos.y + attack_run_altitude_offset_m)
		if not is_nan(terrain_max):
			setup_altitude_m = maxf(setup_altitude_m, terrain_max + attack_run_altitude_offset_m)
	return setup_altitude_m

func _get_attack_setup_distance_m() -> float:
	if _run_weapon_type == "Bomb":
		return bomb_run_setup_distance_m
	if _run_weapon_type == "Rocket Pod":
		return rocket_run_setup_distance_m
	return attack_run_distance_m

func _get_attack_pull_up_distance_m() -> float:
	if _run_weapon_type == "Bomb":
		return bomb_pull_up_distance_m
	if _run_weapon_type == "Rocket Pod":
		return rocket_pull_up_distance_m
	return attack_pull_up_distance_m

func _terrain_safe_altitude_for_segment(from_pos: Vector3, to_pos: Vector3, requested_altitude_m: float, minimum_agl_m: float) -> float:
	var safe_altitude_m: float = requested_altitude_m
	var point_terrain_h: float = _get_ground_height_at_position(to_pos)
	if not is_nan(point_terrain_h):
		safe_altitude_m = maxf(safe_altitude_m, point_terrain_h + minimum_agl_m)
	var segment_samples: int = clampi(int(ceil(from_pos.distance_to(to_pos) / 600.0)), 6, 18)
	var segment_terrain_h: float = _sample_max_terrain_height_along_path(from_pos, to_pos, segment_samples)
	if not is_nan(segment_terrain_h):
		safe_altitude_m = maxf(safe_altitude_m, segment_terrain_h + minimum_agl_m)
	return safe_altitude_m

func _resolve_effective_altitude_world_y(world_pos: Vector3, desired_agl_m: float) -> float:
	var reference_y: float = _get_ground_height_at_position(world_pos)
	if is_nan(reference_y) and aircraft and aircraft.has_method("get_effective_altitude_reference_y"):
		reference_y = float(aircraft.get_effective_altitude_reference_y())
	if is_nan(reference_y):
		reference_y = 0.0
	return reference_y + maxf(desired_agl_m, 0.0)

func _scan_contacts():
	"""Scan for enemies and friendlies within sensor range"""
	sensor_update_counter += 1
	known_enemies.clear()
	known_friendlies.clear()
	var my_team: int = aircraft.get_team() if aircraft.has_method("get_team") else 1
	var hostile_groups: Array[String] = ["enemies", "ai_aircraft", "ground_vehicles", "gun_emplacements", "buildings", "enemy_bases"]
	var friendly_groups: Array[String] = ["friendlies", "aircraft", "ai_aircraft", "carrier", "ground_vehicles", "gun_emplacements", "buildings"]
	if my_team != 1:
		hostile_groups = ["friendlies", "aircraft", "ai_aircraft", "carrier", "ground_vehicles", "gun_emplacements", "buildings"]
		friendly_groups = ["enemies", "ai_aircraft", "ground_vehicles", "gun_emplacements", "buildings", "enemy_bases"]
	var effective_sensor_range: float = sensor_range * _get_night_sensor_range_multiplier()
	var sensor_range_sq: float = effective_sensor_range * effective_sensor_range

	# Update cached group nodes periodically
	if sensor_update_counter % sensor_update_interval == 0:
		cached_hostile_nodes.clear()
		for group_name in hostile_groups:
			cached_hostile_nodes.append_array(get_tree().get_nodes_in_group(group_name))
		cached_friendly_nodes.clear()
		for group_name in friendly_groups:
			cached_friendly_nodes.append_array(get_tree().get_nodes_in_group(group_name))

	# Scan cached hostile nodes
	for node in cached_hostile_nodes:
		if not is_instance_valid(node) or not (node is Node3D) or node == aircraft:
			continue
		if node.has_method("get_team") and int(node.get_team()) == my_team:
			continue
		var enemy_node := node as Node3D
		var distance_sq: float = aircraft.global_position.distance_squared_to(enemy_node.global_position)
		if distance_sq <= sensor_range_sq and not known_enemies.has(enemy_node):
			known_enemies.append(enemy_node)

	# Scan cached friendly nodes
	for node in cached_friendly_nodes:
		if not is_instance_valid(node) or not (node is Node3D) or node == aircraft:
			continue
		if node.has_method("get_team") and int(node.get_team()) != my_team:
			continue
		var friendly_node := node as Node3D
		var distance_sq: float = aircraft.global_position.distance_squared_to(friendly_node.global_position)
		if distance_sq <= sensor_range_sq and not known_friendlies.has(friendly_node):
			known_friendlies.append(friendly_node)

func _report_contacts_to_air_ops(delta: float) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	if aircraft.has_method("get_team") and int(aircraft.get_team()) != 1:
		return
	if known_enemies.is_empty():
		return
	_contact_report_timer_s -= delta
	if _contact_report_timer_s > 0.0:
		return
	_contact_report_timer_s = maxf(contact_report_interval_s, 0.2)
	if AirOpsManager == null or not is_instance_valid(AirOpsManager):
		return
	if not AirOpsManager.has_method("report_contact"):
		return
	for enemy in known_enemies:
		if enemy and is_instance_valid(enemy):
			AirOpsManager.report_contact(aircraft, enemy)

func _get_ai_darkness_factor() -> float:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _ai_darkness_cache_at_ms <= 500:
		return _cached_ai_darkness_factor
	_ai_darkness_cache_at_ms = now_ms
	if not is_instance_valid(_cached_day_night_cycle):
		_cached_day_night_cycle = get_tree().get_first_node_in_group("day_night_cycle")
	var cycle := _cached_day_night_cycle
	if cycle != null and cycle.has_method("get_ai_darkness_factor"):
		_cached_ai_darkness_factor = clampf(float(cycle.call("get_ai_darkness_factor")), 0.0, 1.0)
	else:
		_cached_ai_darkness_factor = 0.0
	return _cached_ai_darkness_factor

func _get_night_sensor_range_multiplier() -> float:
	return lerpf(1.0, night_sensor_range_multiplier, _get_ai_darkness_factor())

func _should_run_rtb_check(delta: float) -> bool:
	if rtb_health_threshold <= 0.0 and rtb_fuel_threshold <= 0.0:
		return false
	if current_state in [State.RTB, State.RECOVERY_MARSHAL, State.RECOVERY_HOLD, State.RECOVERY_APPROACH, State.APPROACH, State.LANDING, State.MISSED_APPROACH]:
		_rtb_check_timer_s = maxf(_rtb_check_timer_s, rtb_check_interval_s)
		return false
	_rtb_check_timer_s -= delta
	if _rtb_check_timer_s > 0.0:
		return false
	_rtb_check_timer_s = maxf(rtb_check_interval_s, 0.1)
	return true

func _check_rtb_triggers():
	"""Monitor health and fuel, trigger RTB if critical"""
	if current_state in [State.RTB, State.RECOVERY_MARSHAL, State.RECOVERY_HOLD, State.RECOVERY_APPROACH, State.APPROACH, State.LANDING, State.MISSED_APPROACH]:
		return
		
	var needs_rtb: bool = false
	var rtb_reason: String = ""

	# Check Health
	var health_percent: float = _get_health_fraction()
	if health_percent >= 0.0:
		if health_percent < rtb_health_threshold:
			needs_rtb = true
			rtb_reason = "Health low (%.1f%%)" % (health_percent * 100.0)

	# Check Fuel
	if not needs_rtb:
		var fuel_percent: float = _get_energy_fraction("fuel")
		if fuel_percent >= 0.0 and fuel_percent < rtb_fuel_threshold:
			needs_rtb = true
			rtb_reason = "Fuel low (%.1f%%)" % (fuel_percent * 100.0)

	if needs_rtb:
		if debug_enabled:
			print("[AIPilot] Triggering RTB: ", rtb_reason)
		if not start_recovery():
			change_state(State.RTB)

func _get_health_fraction() -> float:
	if not aircraft:
		return -1.0
	var current_value = aircraft.get("current_health")
	var max_value = aircraft.get("max_health")
	if current_value == null or max_value == null:
		return -1.0
	var current_num: float = float(current_value)
	var max_num: float = float(max_value)
	if max_num <= 0.0:
		return -1.0
	current_health = current_num
	max_health = max_num
	return clampf(current_num / max_num, 0.0, 1.0)

func _get_energy_fraction(energy_type: String) -> float:
	if not aircraft or not ("available_energy" in aircraft):
		return -1.0
	var current_energy = aircraft.available_energy.get(energy_type, -1.0)
	if typeof(current_energy) not in [TYPE_FLOAT, TYPE_INT]:
		return -1.0
	var max_energy_total: float = 0.0
	if "energy_containers_by_type" in aircraft:
		var containers = aircraft.energy_containers_by_type.get(energy_type, [])
		for container in containers:
			if not is_instance_valid(container):
				continue
			var is_active = container.get("ContainerActive")
			if is_active != null and not bool(is_active):
				continue
			var capacity = container.get("MaxCapacity")
			if capacity != null:
				max_energy_total += float(capacity)
	if max_energy_total <= 0.0:
		return -1.0
	return clampf(float(current_energy) / max_energy_total, 0.0, 1.0)

func _find_nearest_enemy() -> Node3D:
	"""Find nearest enemy target from known contacts"""
	if known_enemies.is_empty():
		return null

	var nearest_enemy: Node3D = null
	var nearest_distance: float = INF

	for enemy in known_enemies:
		if is_instance_valid(enemy):
			var distance = aircraft.global_position.distance_to(enemy.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_enemy = enemy

	return nearest_enemy

func _find_module(root: Node, script_name: String) -> Node:
	"""Find module by script name"""
	for child in root.get_children():
		if child.get_script() and child.get_script().resource_path.ends_with(script_name + ".gd"):
			return child
		var result = _find_module(child, script_name)
		if result:
			return result
	return null

func _normalize_angle(angle: float) -> float:
	"""Normalize angle to -PI to PI"""
	while angle > PI:
		angle -= TAU
	while angle < -PI:
		angle += TAU
	return angle

func _setup_patrol_waypoints():
	"""Create 2 km square patrol around carrier"""
	waypoints.clear()
	current_waypoint_index = 0
	waypoints_follow_carrier = true

	var half: float = 1000.0  # half-side â†’ 2 km sides
	var patrol_points: Array[Vector3] = [
		carrier_position + Vector3( half, 0.0,  half),
		carrier_position + Vector3(-half, 0.0,  half),
		carrier_position + Vector3(-half, 0.0, -half),
		carrier_position + Vector3( half, 0.0, -half),
	]
	for point in patrol_points:
		var waypoint := point
		waypoint.y = _resolve_effective_altitude_world_y(waypoint, patrol_altitude_m)
		waypoints.append(waypoint)

	if debug_enabled and verbose_debug_enabled:
		print("[AIPilot] Figure-eight patrol with ", waypoints.size(), " waypoints around carrier at: ", carrier_position)
		for i in range(waypoints.size()):
			print("  WP", i, ": ", waypoints[i])

func _ensure_carrier_position():
	"""Find and set carrier_position if not initialized."""
	var need_seed := carrier_position == Vector3.ZERO
	if not need_seed and aircraft.global_position.distance_to(carrier_position) > 50000.0:
		need_seed = true
	if not need_seed:
		return
	_refresh_carrier_position(false)
	if carrier_position != Vector3.ZERO:
		return
	var carriers = get_tree().get_nodes_in_group("carrier")
	if carriers.size() > 0:
		var c = carriers[0]
		if c is Node3D:
			carrier_position = (c as Node3D).global_position
			if debug_enabled and verbose_debug_enabled:
				print("[AIPilot] Seeded carrier_position from group 'carrier': ", carrier_position)
	else:
		# Fallback: use current position as temporary center to prevent runaway
		carrier_position = aircraft.global_position
		if debug_enabled and verbose_debug_enabled:
			print("[AIPilot] No carrier found; seeding patrol center at aircraft position: ", carrier_position)

func _refresh_carrier_position(shift_patrol_waypoints: bool) -> void:
	var carriers = get_tree().get_nodes_in_group("carrier")
	if carriers.is_empty() or not (carriers[0] is Node3D):
		if carrier_position == Vector3.ZERO:
			carrier_position = aircraft.global_position
		return

	var new_center: Vector3 = (carriers[0] as Node3D).global_position
	if carrier_position == Vector3.ZERO:
		carrier_position = new_center
		return

	var center_delta: Vector3 = new_center - carrier_position
	carrier_position = new_center
	if shift_patrol_waypoints and center_delta.length_squared() > 0.01 and not waypoints.is_empty():
		for i in range(waypoints.size()):
			waypoints[i] += center_delta

func change_state(new_state: State):
	"""Change AI state with logging"""
	if debug_enabled and current_state != new_state:
		var target_name: String = combat_target.name if combat_target and is_instance_valid(combat_target) else "-"
		print("[AIPilot STATE] %s %s -> %s target=%s weapon=%s" % [
			aircraft.name if aircraft else "AI",
			State.keys()[current_state],
			State.keys()[new_state],
			target_name,
			_run_weapon_type
		])
		_periodic_debug_timer_s = 0.0
		if new_state in [State.RECOVERY_MARSHAL, State.RECOVERY_HOLD, State.RECOVERY_APPROACH, State.APPROACH, State.LANDING, State.MISSED_APPROACH]:
			_landing_debug_timer_s = 0.0
	if current_state != new_state:
		_reset_release_solution_stability()
	if current_state == State.DOGFIGHT and new_state != State.DOGFIGHT:
		_dogfight_burst_active = false
		_dogfight_burst_timer_s = 0.0
		_dogfight_burst_cooldown_timer_s = 0.0
		_dogfight_retarget_timer_s = 0.0
		_dogfight_weapon_commit_timer_s = 0.0
		_dogfight_active_missile = null
		_dogfight_variation_timer_s = 0.0
		_dogfight_variation_cooldown_timer_s = 0.0
		_dogfight_stalemate_timer_s = 0.0
		_dogfight_variation_waypoint = Vector3.ZERO
		_dogfight_prev_target_distance_m = INF
		_dogfight_recovery_timer_s = 0.0
		_dogfight_recovery_waypoint = Vector3.ZERO
		_clear_dogfight_lost_sight_behavior()
		_reset_dogfight_precise_controllers()
		_stop_firing()
	if new_state == State.ATTACK_DIVE:
		_dive_entry_time_s = Time.get_ticks_msec() / 1000.0
		_best_bomb_ccip_miss_this_run = INF
	if current_state == State.ATTACK_DIVE and new_state != State.ATTACK_DIVE:
		_hide_bomb_debug_visuals()
	if new_state == State.DOGFIGHT:
		_dogfight_retarget_timer_s = 0.0
		_dogfight_weapon_commit_timer_s = 0.0
		_dogfight_active_missile = null
		_dogfight_stalemate_timer_s = 0.0
		_dogfight_prev_target_distance_m = INF
		_dogfight_recovery_timer_s = 0.0
		_dogfight_recovery_waypoint = Vector3.ZERO
		_clear_dogfight_lost_sight_behavior()
		_reset_dogfight_precise_controllers()
	current_state = new_state

# ============================================================================
# PUBLIC API - For external control
# ============================================================================

func set_waypoints(new_waypoints: Array[Vector3], follow_carrier: bool = false):
	"""Set waypoint list for navigation"""
	waypoints = new_waypoints
	current_waypoint_index = 0
	waypoints_follow_carrier = follow_carrier
	_reset_cap_route_debug()
	if cap_route_debug_enabled and not follow_carrier and new_waypoints.size() > 1:
		var first := new_waypoints[0]
		var second := new_waypoints[1]
		print("[AIPilot CAPDBG %s] route assigned points=%d first=(%.0f,%.0f,%.0f) second=(%.0f,%.0f,%.0f)" % [
			aircraft.name,
			new_waypoints.size(),
			first.x, first.y, first.z,
			second.x, second.y, second.z
		])

func set_formation_anchor(anchor_world: Vector3) -> void:
	formation_anchor = anchor_world
	formation_anchor_active = true

func set_formation_speed_guidance(speed_cap_mps: float = -1.0, speed_bias_mps: float = 0.0) -> void:
	formation_speed_cap_mps = speed_cap_mps
	formation_speed_bias_mps = speed_bias_mps

func set_formation_handling(slot_quality: float = 0.0, ahead_hold_t: float = 0.0) -> void:
	formation_slot_quality = clampf(slot_quality, 0.0, 1.0)
	formation_ahead_hold_t = clampf(ahead_hold_t, 0.0, 1.0)

func clear_formation_guidance() -> void:
	formation_anchor_active = false
	formation_anchor = Vector3.ZERO
	formation_speed_cap_mps = -1.0
	formation_speed_bias_mps = 0.0
	formation_slot_quality = 0.0
	formation_ahead_hold_t = 0.0

func _is_debugging_custom_cap_route() -> bool:
	return cap_route_debug_enabled \
		and aircraft != null \
		and is_instance_valid(aircraft) \
		and current_state == State.SEARCH \
		and not waypoints_follow_carrier \
		and not formation_anchor_active \
		and waypoints.size() > 1

func _reset_cap_route_debug() -> void:
	_cap_route_debug_last_index = -1
	_cap_route_debug_last_waypoint_count = 0
	_cap_route_debug_last_distance_m = INF
	_cap_route_debug_timer_s = 0.0
	_cap_route_debug_no_progress_s = 0.0

func _debug_cap_route_following(delta: float, distance_to_waypoint: float) -> void:
	if not _is_debugging_custom_cap_route():
		_reset_cap_route_debug()
		return
	var waypoint_count: int = waypoints.size()
	var waypoint_index: int = clampi(current_waypoint_index, 0, waypoint_count - 1)
	if waypoint_index != _cap_route_debug_last_index or waypoint_count != _cap_route_debug_last_waypoint_count:
		var nav_local := aircraft.to_local(nav_waypoint)
		print("[AIPilot CAPDBG %s] tracking wp %d/%d dist=%.0fm local=(%.0f,%.0f,%.0f)" % [
			aircraft.name,
			waypoint_index + 1,
			waypoint_count,
			distance_to_waypoint,
			nav_local.x, nav_local.y, nav_local.z
		])
		_cap_route_debug_last_index = waypoint_index
		_cap_route_debug_last_waypoint_count = waypoint_count
		_cap_route_debug_last_distance_m = distance_to_waypoint
		_cap_route_debug_no_progress_s = 0.0
		_cap_route_debug_timer_s = cap_route_debug_interval_s
		return
	var progress_m: float = _cap_route_debug_last_distance_m - distance_to_waypoint
	if distance_to_waypoint > waypoint_threshold * 1.5 and progress_m < cap_route_debug_progress_epsilon_m:
		_cap_route_debug_no_progress_s += delta
	else:
		_cap_route_debug_no_progress_s = maxf(_cap_route_debug_no_progress_s - delta * 0.5, 0.0)
	_cap_route_debug_timer_s -= delta
	if _cap_route_debug_timer_s <= 0.0:
		var nav_local := aircraft.to_local(nav_waypoint)
		print("[AIPilot CAPDBG %s] wp %d/%d dist=%.0fm progress=%.1fm/s stall=%.1fs local=(%.0f,%.0f,%.0f)" % [
			aircraft.name,
			waypoint_index + 1,
			waypoint_count,
			distance_to_waypoint,
			progress_m / maxf(delta, 0.001),
			_cap_route_debug_no_progress_s,
			nav_local.x, nav_local.y, nav_local.z
		])
		_cap_route_debug_timer_s = cap_route_debug_interval_s
	if _cap_route_debug_no_progress_s >= cap_route_debug_stuck_time_s:
		var nav_local := aircraft.to_local(nav_waypoint)
		print("[AIPilot CAPDBG %s] suspect stuck on wp %d/%d dist=%.0fm stall=%.1fs pos=(%.0f,%.0f,%.0f) nav=(%.0f,%.0f,%.0f) local=(%.0f,%.0f,%.0f)" % [
			aircraft.name,
			waypoint_index + 1,
			waypoint_count,
			distance_to_waypoint,
			_cap_route_debug_no_progress_s,
			aircraft.global_position.x, aircraft.global_position.y, aircraft.global_position.z,
			nav_waypoint.x, nav_waypoint.y, nav_waypoint.z,
			nav_local.x, nav_local.y, nav_local.z
		])
		_cap_route_debug_no_progress_s = cap_route_debug_stuck_time_s * 0.5
	_cap_route_debug_last_distance_m = distance_to_waypoint

func _get_effective_target_speed() -> float:
	var effective_target_speed: float = target_speed + formation_speed_bias_mps
	if formation_speed_cap_mps > 0.0:
		effective_target_speed = minf(effective_target_speed, formation_speed_cap_mps)
	return maxf(effective_target_speed, stall_speed_mps + stall_margin_mps + 2.0)

func build_terrain_safe_waypoints(new_waypoints: Array[Vector3], minimum_agl_m: float = 260.0, include_return_leg: bool = false, keep_uniform_altitude: bool = false) -> Array[Vector3]:
	"""Raise waypoint altitudes to maintain terrain clearance along each segment."""
	var safe_waypoints: Array[Vector3] = []
	for point in new_waypoints:
		safe_waypoints.append(point)
	if safe_waypoints.is_empty():
		return safe_waypoints

	if keep_uniform_altitude:
		var safe_altitude_m: float = safe_waypoints[0].y
		var prev_uniform_point := aircraft.global_position if aircraft and is_instance_valid(aircraft) else safe_waypoints[0]
		for waypoint in safe_waypoints:
			safe_altitude_m = maxf(
				safe_altitude_m,
				_terrain_safe_altitude_for_segment(prev_uniform_point, waypoint, waypoint.y, minimum_agl_m)
			)
			prev_uniform_point = waypoint
		if include_return_leg and safe_waypoints.size() > 1:
			safe_altitude_m = maxf(
				safe_altitude_m,
				_terrain_safe_altitude_for_segment(
					safe_waypoints[safe_waypoints.size() - 1],
					safe_waypoints[0],
					safe_waypoints[0].y,
					minimum_agl_m
				)
			)
		for i in range(safe_waypoints.size()):
			var uniform_waypoint := safe_waypoints[i]
			uniform_waypoint.y = safe_altitude_m
			safe_waypoints[i] = uniform_waypoint
		return safe_waypoints

	var prev_point := aircraft.global_position if aircraft and is_instance_valid(aircraft) else safe_waypoints[0]
	for i in range(safe_waypoints.size()):
		var waypoint := safe_waypoints[i]
		waypoint.y = _terrain_safe_altitude_for_segment(prev_point, waypoint, waypoint.y, minimum_agl_m)
		safe_waypoints[i] = waypoint
		prev_point = waypoint

	if include_return_leg and safe_waypoints.size() > 1:
		var first_waypoint := safe_waypoints[0]
		first_waypoint.y = _terrain_safe_altitude_for_segment(
			safe_waypoints[safe_waypoints.size() - 1],
			first_waypoint,
			first_waypoint.y,
			minimum_agl_m
		)
		safe_waypoints[0] = first_waypoint

	return safe_waypoints

func build_effective_altitude_waypoints(new_waypoints: Array[Vector3], minimum_agl_m: float = 260.0, include_return_leg: bool = false) -> Array[Vector3]:
	"""Interpret waypoint.y as desired altitude AGL and convert to terrain-relative world coordinates."""
	var world_waypoints: Array[Vector3] = []
	for point in new_waypoints:
		var world_point := point
		world_point.y = _resolve_effective_altitude_world_y(world_point, point.y)
		world_waypoints.append(world_point)
	return build_terrain_safe_waypoints(world_waypoints, minimum_agl_m, include_return_leg, false)

func add_waypoint(waypoint: Vector3):
	"""Add waypoint to list"""
	waypoints.append(waypoint)

func set_target(target: Variant):
	"""Set combat target and engage"""
	if target == null or not is_instance_valid(target):
		combat_target = null
		change_state(State.SEARCH)
		return
	var ground_target: Node3D = _sanitize_ground_attack_target(target)
	if _is_enemy_aircraft_target(target):
		combat_target = target as Node3D
		change_state(State.DOGFIGHT)
	elif ground_target and _is_valid_ground_attack_target(ground_target) and ground_attack_enabled:
		combat_target = ground_target
		_setup_attack_run_waypoint()
		change_state(State.ATTACK_POSITIONING)
	else:
		combat_target = target as Node3D if target is Node3D else null
		change_state(State.ENGAGE)

func _get_surface_target_position(target: Variant) -> Vector3:
	target = _sanitize_ground_attack_target(target)
	if not target or not is_instance_valid(target):
		return aircraft.global_position
	var collision_shape: CollisionShape3D = _find_target_collision_shape(target)
	if collision_shape and is_instance_valid(collision_shape):
		# Keep vertical bias in world-up space. Some colliders are rotated so their
		# local Y axis points along the fuselage, which biases aim behind/ahead.
		return collision_shape.global_position + Vector3.UP * _get_shape_vertical_half_extent(collision_shape) * 0.35
	var body_node: Node3D = target.get_node_or_null("Body") as Node3D
	if body_node and is_instance_valid(body_node):
		return body_node.global_position + Vector3.UP * 1.2
	return target.global_position + Vector3.UP * 1.2

func _find_target_collision_shape(node: Node) -> CollisionShape3D:
	if not node or not is_instance_valid(node):
		return null
	for child in node.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null

func _get_shape_vertical_half_extent(collision_shape: CollisionShape3D) -> float:
	if not collision_shape or not is_instance_valid(collision_shape) or collision_shape.shape == null:
		return 1.2
	var shape: Shape3D = collision_shape.shape
	if shape is BoxShape3D:
		var box: BoxShape3D = shape as BoxShape3D
		var half_size: Vector3 = box.size * 0.5
		var basis: Basis = collision_shape.global_transform.basis
		var max_y: float = 0.0
		for x_sign in [-1.0, 1.0]:
			for y_sign in [-1.0, 1.0]:
				for z_sign in [-1.0, 1.0]:
					var local_corner := Vector3(half_size.x * x_sign, half_size.y * y_sign, half_size.z * z_sign)
					max_y = maxf(max_y, absf((basis * local_corner).y))
		return max_y
	if shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape as CapsuleShape3D
		var capsule_scale_vec: Vector3 = collision_shape.global_transform.basis.get_scale().abs()
		var capsule_scale: float = maxf(capsule_scale_vec.x, maxf(capsule_scale_vec.y, capsule_scale_vec.z))
		return (capsule.height * 0.5 + capsule.radius) * maxf(capsule_scale, 0.001)
	if shape is SphereShape3D:
		var sphere_scale_vec: Vector3 = collision_shape.global_transform.basis.get_scale().abs()
		var sphere_scale: float = maxf(sphere_scale_vec.x, maxf(sphere_scale_vec.y, sphere_scale_vec.z))
		return (shape as SphereShape3D).radius * maxf(sphere_scale, 0.001)
	if shape is CylinderShape3D:
		var cylinder_scale_vec: Vector3 = collision_shape.global_transform.basis.get_scale().abs()
		var cylinder_scale: float = maxf(cylinder_scale_vec.x, maxf(cylinder_scale_vec.y, cylinder_scale_vec.z))
		return (shape as CylinderShape3D).height * 0.5 * maxf(cylinder_scale, 0.001)
	return 1.2

func set_target_altitude(meters: float) -> void:
	"""Set the AI's immediate altitude target. If patrolling, also update patrol altitude."""
	target_altitude = meters
	patrol_altitude_m = meters
	# Update existing patrol waypoints to the new altitude
	for i in range(waypoints.size()):
		var wp: Vector3 = waypoints[i]
		wp.y = _resolve_effective_altitude_world_y(wp, patrol_altitude_m) if waypoints_follow_carrier else patrol_altitude_m
		waypoints[i] = wp
	if debug_enabled and verbose_debug_enabled:
		print("[AIPilot] Target altitude set to ", meters, "m (patrol altitude updated)")

func set_patrol_altitude(meters: float) -> void:
	"""Set patrol altitude and refresh patrol waypoints' altitude."""
	patrol_altitude_m = meters
	target_altitude = meters
	for i in range(waypoints.size()):
		var wp2: Vector3 = waypoints[i]
		wp2.y = _resolve_effective_altitude_world_y(wp2, patrol_altitude_m) if waypoints_follow_carrier else patrol_altitude_m
		waypoints[i] = wp2
	if debug_enabled and verbose_debug_enabled:
		print("[AIPilot] Patrol altitude set to ", meters, "m")

func launch():
	"""Begin launch sequence"""
	# Save launch position for deck clearance check
	launch_position = aircraft.global_position
	# Save current carrier center for patrol / RTB logic.
	carrier_position = Vector3.ZERO
	_refresh_carrier_position(false)
	if carrier_position == Vector3.ZERO:
		carrier_position = launch_position
	if debug_enabled and verbose_debug_enabled:
		print("[AIPilot] Launch initiated from position: ", launch_position)
		print("[AIPilot] Carrier position saved: ", carrier_position)
	change_state(State.LAUNCHING)

func return_to_base():
	"""Command to return to carrier"""
	if not start_recovery():
		change_state(State.RTB)

func start_recovery() -> bool:
	"""Enter the mission-return recovery framework before final landing."""
	if not _find_approach_waypoints():
		_landing_debug_event("recovery start failed: missing approach_4")
		return false
	_find_takeoff_waypoint()
	_stop_firing()
	_recovery_phase = 0
	_recovery_hold_side = 1.0
	_recovery_clearance_granted = false
	_landing_debug_timer_s = 0.0
	_reset_landing_carrier_motion_estimate()
	_stow_landing_config()
	change_state(State.RECOVERY_MARSHAL)
	return true

func _request_carrier_recovery() -> void:
	"""After arrest, ask FlightDeckManager to move aircraft to hangar."""
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm and fdm.has_method("start_post_arrest_recovery"):
		_landing_debug_event("requesting post-arrest recovery from FlightDeckManager")
		fdm.start_post_arrest_recovery(aircraft)
	else:
		# Fallback: just keep parking brake so it sits still
		_landing_debug_event("recovery fallback: FlightDeckManager unavailable, parking brake set")
		if is_instance_valid(aircraft):
			aircraft.set_meta("parking_brake", true)

func _should_wave_off_for_busy_deck(horiz_dist: float) -> bool:
	if horiz_dist > landing_waveoff_check_distance_m:
		return false
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if not fdm or not fdm.has_method("can_accept_landing"):
		return false
	return not bool(fdm.can_accept_landing(aircraft))

func start_straight_in_landing() -> bool:
	"""Alias for start_landing() — both go directly to LANDING state now."""
	return start_landing()

func start_landing() -> bool:
	"""Command the AI to begin the carrier landing. Goes directly to LANDING state
	using a rolling carrot toward approach_4 — no approach circuit."""
	if not _find_approach_waypoints():
		_landing_debug_event("landing start failed: missing approach_4")
		return false
	_find_takeoff_waypoint()
	_landing_phase = 0
	_approach_path_along_m = 0.0
	_carrot_along_m = 0.0
	_committed_turn_sign = 0.0
	_bolter_go_around = false
	_bolter_dir = Vector3.ZERO
	_landing_carrot_active = false
	_landing_carrot_remaining_m = INF
	_landing_smoothed_desired_fpa = NAN
	_landing_smoothed_bearing_error = NAN
	_landing_smoothed_runway_heading_error = NAN
	_reset_landing_carrier_motion_estimate()
	_land_snap_400_done = false
	_land_snap_200_done = false
	_land_snap_100_done = false
	_land_snap_touch_done = false
	target_speed = 80.0
	_landing_debug_timer_s = 0.0
	_deploy_landing_gear()
	if is_instance_valid(control_gear) and control_gear.has_method("send_to_tailhook_simple"):
		control_gear.send_to_tailhook_simple(true)
		if "tailhook_down_state" in control_gear:
			control_gear.tailhook_down_state = true
	change_state(State.LANDING)
	return true

func _find_approach_waypoints() -> bool:
	"""Find approach waypoints. Only approach_4 (touchdown) is required."""
	var root: Node = get_tree().current_scene
	if not root:
		return false
	var wp4: Node3D = root.find_child("approach_4", true, false) as Node3D
	if not is_instance_valid(wp4):
		push_warning("[AIPilot] start_landing: could not find approach_4 node in scene")
		return false
	var wp0: Node3D = root.find_child("approach_0", true, false) as Node3D
	var wp1: Node3D = root.find_child("approach_1", true, false) as Node3D
	var wp2: Node3D = root.find_child("approach_2", true, false) as Node3D
	var wp3: Node3D = root.find_child("approach_3", true, false) as Node3D
	_approach_wp = [wp0, wp1, wp2, wp3, wp4]
	return true

func _reset_landing_carrier_motion_estimate() -> void:
	_landing_measured_carrier_velocity = Vector3.ZERO
	_landing_carrier_motion_last_ref = Vector3.ZERO
	_landing_carrier_motion_has_ref = false

func _get_landing_carrier_motion_reference() -> Dictionary:
	if _approach_wp.size() >= 5 and is_instance_valid(_approach_wp[4]):
		var touchdown_ref: Dictionary = _get_landing_touchdown_reference()
		if bool(touchdown_ref.get("valid", false)):
			return {
				"valid": true,
				"position": touchdown_ref.get("position", (_approach_wp[4] as Node3D).global_position)
			}
		return {
			"valid": true,
			"position": (_approach_wp[4] as Node3D).global_position
		}
	return {"valid": false}

func _update_landing_carrier_motion_estimate(delta: float) -> void:
	if not landing_carrier_motion_compensation_enabled:
		_reset_landing_carrier_motion_estimate()
		return
	if not (current_state in [State.RECOVERY_MARSHAL, State.RECOVERY_HOLD, State.RECOVERY_APPROACH, State.APPROACH, State.LANDING, State.MISSED_APPROACH]):
		_reset_landing_carrier_motion_estimate()
		return
	if delta <= 0.0:
		return
	var ref: Dictionary = _get_landing_carrier_motion_reference()
	if not bool(ref.get("valid", false)):
		_reset_landing_carrier_motion_estimate()
		return
	var ref_pos: Vector3 = ref.get("position", Vector3.ZERO)
	if not _landing_carrier_motion_has_ref:
		_landing_carrier_motion_last_ref = ref_pos
		_landing_carrier_motion_has_ref = true
		_landing_measured_carrier_velocity = Vector3.ZERO
		return
	var raw_velocity: Vector3 = (ref_pos - _landing_carrier_motion_last_ref) / maxf(delta, 0.001)
	raw_velocity.y = 0.0
	var max_speed: float = maxf(landing_carrier_motion_max_speed_mps, 1.0)
	if raw_velocity.length() > max_speed:
		raw_velocity = raw_velocity.normalized() * max_speed
	var smoothing: float = clampf(landing_carrier_motion_velocity_smoothing, 0.01, 1.0)
	_landing_measured_carrier_velocity = _landing_measured_carrier_velocity.lerp(raw_velocity, smoothing)
	_landing_carrier_motion_last_ref = ref_pos

func _get_carrier_velocity() -> Vector3:
	if landing_carrier_motion_compensation_enabled \
	and _landing_carrier_motion_has_ref \
	and _landing_measured_carrier_velocity.length() >= maxf(landing_carrier_motion_min_speed_mps, 0.0):
		return _landing_measured_carrier_velocity
	if _approach_wp.is_empty() or not is_instance_valid(_approach_wp[0]):
		return Vector3.ZERO
	var carrier: Node = (_approach_wp[0] as Node3D).get_parent()
	if not is_instance_valid(carrier):
		return Vector3.ZERO
	if carrier is CharacterBody3D:
		return (carrier as CharacterBody3D).velocity
	if "linear_velocity" in carrier:
		return carrier.get("linear_velocity")
	return Vector3.ZERO

func _get_landing_carrier_speed_compensation(landing_geom: Dictionary) -> float:
	if not landing_carrier_motion_compensation_enabled or not bool(landing_geom.get("valid", false)):
		return 0.0
	var carrier_vel: Vector3 = _get_carrier_velocity()
	if carrier_vel.length() < maxf(landing_carrier_motion_min_speed_mps, 0.0):
		return 0.0
	var axis: Vector3 = landing_geom.get("axis", Vector3.ZERO)
	axis.y = 0.0
	if axis.length_squared() < 0.001:
		return 0.0
	axis = axis.normalized()
	var compensation: float = carrier_vel.dot(axis) * landing_carrier_speed_compensation_scale
	var max_compensation: float = maxf(landing_carrier_motion_max_speed_mps, 0.0)
	return clampf(compensation, -max_compensation, max_compensation)

func _find_takeoff_waypoint() -> bool:
	var root: Node = get_tree().current_scene
	if not root:
		_takeoff_wp = null
		return false
	_takeoff_wp = root.find_child("takeoff_0", true, false) as Node3D
	return is_instance_valid(_takeoff_wp)

func _should_start_missed_approach() -> bool:
	if _approach_wp.size() < 5 or not is_instance_valid(_approach_wp[4]):
		return false
	var wp4: Node3D = _approach_wp[4] as Node3D
	var touchdown_ref: Dictionary = _get_landing_touchdown_reference()
	var touchdown: Vector3 = touchdown_ref.get("position", wp4.global_position)
	# Only detect a bolter when the aircraft is near deck level — not while it is still
	# descending from a high entry. Planes that started high pass approach_4 horizontally
	# but are still 30+ m up and very much on approach.
	if aircraft.global_position.y > touchdown.y + 15.0:
		return false
	# Use velocity direction as the approach axis (no approach_3 required).
	var vel_flat := Vector3(aircraft.linear_velocity.x, 0.0, aircraft.linear_velocity.z)
	if vel_flat.length_squared() < 1.0:
		return false
	vel_flat = vel_flat.normalized()
	# Positive = aircraft is that many metres past the touchdown reference along its travel direction.
	var past_target_m: float = Vector3(
		aircraft.global_position.x - touchdown.x,
		0.0,
		aircraft.global_position.z - touchdown.z
	).dot(vel_flat)
	return past_target_m >= landing_bolter_past_target_m

func _begin_missed_approach() -> void:
	_release_landing_clearance_from_deck()
	if not is_instance_valid(_takeoff_wp) and not _find_takeoff_waypoint():
		_landing_debug_event("missed approach failed: could not find takeoff_0")
		push_warning("[AIPilot] Missed approach: could not find takeoff_0")
		change_state(State.RTB)
		return
	if debug_enabled:
		print("[AIPilot] Missed approach: bolter detected, climbing to takeoff_0")
	if is_instance_valid(_takeoff_wp):
		_landing_debug_event("missed approach begin takeoff_0=(%.0f,%.0f,%.0f)" % [
			_takeoff_wp.global_position.x,
			_takeoff_wp.global_position.y,
			_takeoff_wp.global_position.z
		])
	_ma_escape_complete = false
	# Do NOT stow landing config here — flaps provide critical lift at near-stall speed.
	# Gear/flap retraction happens in _state_missed_approach once safe altitude is reached.
	change_state(State.MISSED_APPROACH)

func _deploy_landing_gear():
	"""Deploy landing gear, tailhook, and flaps for the carrier approach (gear+flaps together)."""
	if not is_instance_valid(control_gear):
		return
	if control_gear.get("gear_down_state") == true:
		return  # Already down
	if control_gear.has_method("send_to_landing_gears"):
		control_gear.send_to_landing_gears("deploy")
	if control_gear.has_method("send_to_tailhooks"):
		control_gear.send_to_tailhooks("deploy")
	if control_gear.has_method("send_to_tailhook_simple"):
		control_gear.send_to_tailhook_simple(true)
	if control_gear.has_method("_set_collider_disabled"):
		control_gear._set_collider_disabled(false)
	if "gear_down_state" in control_gear:
		control_gear.gear_down_state = true
	# Deploy flaps with gear (approach config: both increase drag)
	var flaps = aircraft.find_modules_by_type("flaps") if aircraft.has_method("find_modules_by_type") else []
	if not flaps.is_empty() and flaps[0].has_method("flap_set_position"):
		flaps[0].flap_set_position(1.0)

func _stow_landing_config() -> void:
	"""Retract landing gear, tailhook, and flaps after launch or a go-around."""
	if not is_instance_valid(control_gear):
		return
	if control_gear.get("gear_down_state") != true:
		return
	control_gear.send_to_landing_gears("stow")
	control_gear.send_to_tailhooks("stow")
	control_gear.send_to_tailhook_simple(false)
	control_gear._set_collider_disabled(true)
	control_gear.gear_down_state = false
	var flaps = aircraft.find_modules_by_type("flaps") if aircraft.has_method("find_modules_by_type") else []
	if not flaps.is_empty() and flaps[0].has_method("flap_set_position"):
		flaps[0].flap_set_position(0.0)
