class_name AIPilot
extends Node

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
var _terrain_check_counter: int = 0
@export var terrain_check_interval: int = 3  # Update terrain fan/ahead every N physics frames (~20 Hz at 60 Hz physics)
var _smoothed_ground_height: float = NAN  # Smoothed ground height for stable low-level flight
# Terrain fan avoidance — directional escape sampling
var _terrain_fan_clearances: PackedFloat32Array = PackedFloat32Array([INF, INF, INF, INF, INF])
var _terrain_fan_best_idx: int = 2  # Index into fan angles; 2 = forward
var _terrain_height_callable: Callable  # Cached get_height callable — resolved once on first use
var _safety_override_active: bool = false  # True when terrain/collision override is controlling

@export var sensor_range: float = 5000.0  # How far AI can "see"
@export var ground_check_distance: float = 10000.0  # Max distance for AGL raycast
@export var terrain_ahead_check_distance: float = 2000.0  # How far ahead to check for terrain
@export var terrain_warning_distance: float = 500.0  # Pull up if terrain closer than this
@export var emergency_min_agl_m: float = 180.0  # Emergency override if below this AGL
@export var emergency_tti_s: float = 3.0  # Emergency override if terrain time-to-impact is below this

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
@export var bomb_run_setup_distance_m: float = 1400.0  # Bomb run setup distance from target
@export var bomb_run_setup_altitude_offset_m: float = 650.0  # Bomb run setup altitude above target
@export var bomb_dive_start_distance_m: float = 800.0  # Start bomb dive at this HORIZONTAL range
@export var attack_pull_up_distance_m: float = 150.0  # Break off when this close to target (gun runs)
@export var bomb_pull_up_distance_m: float = 250.0   # Break off distance for bomb runs
@export var bomb_dive_aim_height_m: float = 0.0      # Aim this many metres above the target during bomb dive
@export var bomb_release_altitude_window_m: float = 600.0  # Max altitude above target at which bomb can be released
@export var bomb_ccip_release_tolerance_m: float = 30.0   # Release when predicted impact is within this distance of target
@export var bomb_ccip_fallback_alt_m: float = 80.0        # Release regardless of CCIP if below this altitude above target
@export var attack_break_off_distance_m: float = 700.0  # Must fly this far from target before lining up new run
@export var attack_aim_lead_time_s: float = 0.25  # Small lead for moving targets during dive
@export var bomb_release_spacing_s: float = 0.2   # Time spacing between bombs
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
@export var dogfight_default_muzzle_velocity_mps: float = 800.0
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
var _bomb_run_altitude_m: float = 0.0
var _prev_ccip_miss: float = INF  # Tracks CCIP miss from last frame to detect improving accuracy
var _ccip_cache_timer: float = 0.0  # Throttle CCIP to avoid per-frame ballistic sim
var _ccip_cached_result: Vector3 = Vector3.ZERO
var _cached_bomb_linear_damp: float = -1.0  # -1 = not yet cached
var _cached_bomb_gravity_scale: float = 1.0
var _attack_recovery_until_s: float = 0.0  # After emergency, hold egress before next run
var _dive_precise_aim: bool = false  # When true, use tighter bank for steadier final approach
var _dive_entry_time_s: float = -INF  # When we entered ATTACK_DIVE (for soft dive entry)
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

# Landing approach
var _landing_phase: int = 0  # 0=to approach_1, 1=to approach_2, thenÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢LANDING state
var _approach_wp: Array = []  # [Node3D approach_1, Node3D approach_2, Node3D approach_3]
var _takeoff_wp: Node3D = null
@export var approach_phase0_alt_above_deck_m: float = 450.0
@export var approach_phase1_alt_above_deck_m: float = 350.0
@export var approach_phase2_alt_above_deck_m: float = 200.0
@export var approach_phase3_alt_above_deck_m: float = 130.0
@export var approach_deck_height_fallback_m: float = 60.0  # Used if approach_4 cannot be read
@export var approach_entry_altitude_m: float = 600.0
@export var approach_post_gate_speed_mps: float = 56.0
@export var approach_post_gate_throttle_cut: float = 0.2
@export var approach_post_gate_min_throttle: float = 0.1
@export var approach_post_gate_slowdown_margin_mps: float = 6.0
@export var approach_phase0_capture_m: float = 100.0
@export var approach_phase1_capture_m: float = 80.0
@export var approach_phase2_capture_m: float = 60.0
@export var approach_phase3_capture_m: float = 40.0
@export var approach_guidance_mode: ApproachGuidanceMode = ApproachGuidanceMode.PATH_FOLLOWER
@export var approach_precision_bank_limit_deg: float = 55.0
@export var approach_precision_bank_gain: float = 2.5
@export var approach_precision_min_bank_deg: float = 8.0
@export var approach_path_far_speed_mps: float = 78.0
@export var approach_path_near_speed_mps: float = 60.0
@export var approach_path_lookahead_time_s: float = 3.0
@export var approach_path_min_lookahead_m: float = 140.0
@export var approach_path_max_lookahead_m: float = 260.0
@export var approach_path_final_switch_buffer_m: float = 120.0
@export var landing_path_lookahead_time_s: float = 2.0
@export var landing_path_min_lookahead_m: float = 35.0
@export var landing_path_max_lookahead_m: float = 120.0
@export var landing_short_final_bank_distance_m: float = 200.0
@export var landing_short_final_bank_limit_deg: float = 18.0
@export var landing_short_final_min_bank_deg: float = 4.0
@export var landing_touchdown_level_distance_m: float = 90.0
@export var landing_touchdown_bank_limit_deg: float = 6.0
@export var landing_short_final_yaw_gain: float = 0.65
@export var landing_waveoff_check_distance_m: float = 220.0
@export var landing_bolter_past_target_m: float = 25.0
@export var landing_bolter_rejoin_distance_m: float = 180.0
@export var landing_bolter_rejoin_altitude_margin_m: float = 80.0
@export var landing_bolter_target_speed_mps: float = 92.0
@export var landing_bolter_gear_retract_height_m: float = 35.0

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
@export var verbose_debug_enabled: bool = false  # Extra non-attack telemetry spam
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
@export var pitch_input_smoothing: float = 0.2  # Heavier pitch smoothing to reduce oscillation
@export var pitch_deadband_m: float = 20.0  # Ignore tiny altitude errors to avoid constant porpoising
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

# Arrest debug
var _arrest_engaged_prev: bool = false  # Detect wire-catch transition
var _arrest_debug_timer: float = 0.0    # Accumulates time since last print
var _arrest_debug_interval: float = 0.1 # Print 10ÃƒÆ’Ã¢â‚¬â€/s
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

	if not control_engine or not simple_aero:
		push_error("[AIPilot] Failed to find required control modules!")
		return

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
	# Do NOT call _apply_controls() here ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â the catapult owns the engine and
	# set_target_power(0) would trigger engine_stop(), killing the spool-up.
	if aircraft.get_meta("controls_disabled", false):
		return

	# Update sensors - AI's view of the world
	_update_sensors()

	if _passive_debug_only:
		_emit_player_debug_telemetry(delta)
		return

	# Update health and fuel monitoring for RTB
	_check_rtb_triggers()

	# === HIERARCHY OF NEEDS ===
	# 1. Don't fly into terrain (highest priority)
	# 2. Don't fly into other aircraft
	# 3. Do whatever the state machine says
	_safety_override_active = false
	if _check_terrain_avoidance(delta):
		_safety_override_active = true
	elif _check_collision_avoidance(delta):
		_safety_override_active = true

	if not _safety_override_active:
		# State machine — only runs when safety is not overriding
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
			State.APPROACH:
				_state_approach(delta)
			State.LANDING:
				_state_landing(delta)
			State.MISSED_APPROACH:
				_state_missed_approach(delta)

	# Periodic telemetry (~2 per second at 60fps)
	if debug_enabled and Engine.get_process_frames() % 30 == 0:
		var spd: float = aircraft.linear_velocity.length()
		var alt: float = aircraft.global_position.y
		var vs: float = aircraft.linear_velocity.y
		var pitch_deg: float = rad_to_deg(_get_forward_pitch_rad())
		var h_spd: float = Vector2(aircraft.linear_velocity.x, aircraft.linear_velocity.z).length()
		var fpa_deg: float = rad_to_deg(atan2(-aircraft.linear_velocity.y, max(h_spd, 1.0)))
		var state_name: String = State.keys()[current_state]
		var pos: Vector3 = aircraft.global_position
		var override_str: String = "  [SAFETY]" if _safety_override_active else ""
		print("[AIPilot TEL] state=", state_name, override_str, "  pos=(", snapped(pos.x, 1), ",", snapped(pos.y, 1), ",", snapped(pos.z, 1), ")  alt=", snapped(alt, 1), "  AGL=", snapped(altitude_agl, 1), "  spd=", snapped(spd, 1), "m/s  VS=", snapped(vs, 1), "  pitch=", snapped(pitch_deg, 0.1), "Ãƒâ€šÃ‚Â°  fpa=", snapped(fpa_deg, 0.1), "Ãƒâ€šÃ‚Â°")

	_debug_flight_path_alignment(delta)

	# Update waypoint marker position
	_update_waypoint_marker()

	# Apply computed control inputs to aircraft
	_apply_controls()

# ============================================================================
# STATE HANDLERS
# ============================================================================

func _state_idle(delta: float):
	"""Waiting on deck"""
	# Do nothing, waiting for launch
	pass

func _state_launching(delta: float):
	"""In catapult sequence"""
	# Maintain near-level flight ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â gentle pitch-up keeps us from descending into the water
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

	# Don't climb-state until distance AND AGL are both safe — low-AGL turns kill.
	if _is_airborne():
		var distance_from_launch = aircraft.global_position.distance_to(launch_position)
		if distance_from_launch > deck_clearance_distance and altitude_agl > 60.0:
			var current_heading = atan2(aircraft.global_transform.basis.z.x, aircraft.global_transform.basis.z.z)
			target_heading = current_heading
			if land_after_launch:
				land_after_launch = false
				_land_after_climb = true
				print("[AIPilot] Clear of deck ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â climbing to pattern altitude before approach")
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
	# point every frame ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â the aircraft can actually reach and clear it.
	# Waypoint anchored to aircraft's OWN position, not the carrier's — the carrier
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

	# No banking below 150m AGL — turns at low altitude after launch are fatal.
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
			print("[AIPilot] Climb waypoint cleared ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â starting landing approach")
			start_landing()
		elif waypoints.size() > 0:
			change_state(State.TRANSIT)
		else:
			set_patrol_altitude(nav_waypoint.y)
			print("[AIPilot] Climb altitude reached — entering patrol")
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
		if not _is_valid_ground_attack_target(enemy):
			continue
		var d: float = aircraft.global_position.distance_to(enemy.global_position)
		var score: float = d + _get_ground_target_priority_penalty(enemy)
		if score < best_score:
			best_score = score
			nearest = enemy
	return nearest

func _is_valid_ground_attack_target(node: Node3D) -> bool:
	if not node or not is_instance_valid(node):
		return false
	if node == aircraft:
		return false
	if node.is_in_group("carrier"):
		return true
	if node.is_in_group("ground_vehicles"):
		return true
	return false

func _get_ground_target_priority_penalty(node: Node3D) -> float:
	if not node or not is_instance_valid(node):
		return 100000.0
	if node.is_in_group("ground_vehicles"):
		return 0.0
	if node.is_in_group("carrier"):
		return 450.0
	return 300.0

func _is_enemy_aircraft_target(node: Node3D) -> bool:
	if not node or not is_instance_valid(node):
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
		if not (enemy is Node3D):
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
		if not (enemy is Node3D) or not is_instance_valid(enemy):
			continue
		if not _is_enemy_aircraft_target(enemy as Node3D):
			continue
		var d: float = aircraft.global_position.distance_to((enemy as Node3D).global_position)
		if d <= dogfight_proximity_override_m:
			combat_target = enemy as Node3D
			change_state(State.DOGFIGHT)
			if debug_enabled:
				print("[AIPilot] Air threat at %.0fm — breaking off ground attack to dogfight %s" % [d, combat_target.name])
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

func _is_within_engagement_radius(target: Node3D, radius_m: float = -1.0) -> bool:
	if not target or not is_instance_valid(target):
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
	if not combat_target or not is_instance_valid(combat_target):
		return
	_plan_attack_run_weapon()
	var target_pos: Vector3 = _get_surface_target_position(combat_target)
	var to_target: Vector3 = target_pos - aircraft.global_position
	to_target.y = 0.0
	var horiz_dir: Vector3 = to_target.normalized() if to_target.length() > 1.0 else aircraft.global_transform.basis.z
	var setup_dist: float = bomb_run_setup_distance_m if _run_weapon_type == "Bomb" else attack_run_distance_m
	nav_waypoint = target_pos - horiz_dir * setup_dist
	# Survey the highest terrain between setup point and target to guarantee adequate clearance.
	var terrain_max: float = _sample_max_terrain_height_along_path(nav_waypoint, target_pos, 8)
	var setup_altitude_m: float = _get_attack_setup_altitude_m(target_pos, terrain_max)
	if _run_weapon_type == "Bomb":
		_bomb_run_altitude_m = setup_altitude_m
	nav_waypoint.y = setup_altitude_m
	maneuver_waypoint = nav_waypoint
	if debug_enabled:
		print("[AIPilot ATTACK] Run setup waypoint: ", nav_waypoint, "  target=", target_pos, "  weapon=", _run_weapon_type, "  bombs=", _bombs_to_drop_this_run)

func _state_attack_positioning(delta: float):
	"""Fly to attack run setup waypoint (800m offset; altitude depends on weapon plan)."""
	if _check_air_threat_proximity():
		return
	if not ground_attack_enabled:
		change_state(State.SEARCH)
		return
	if not combat_target or not is_instance_valid(combat_target):
		change_state(State.SEARCH)
		return

	# Don't attempt attack maneuvers at dangerously low speed ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â build energy first
	var cur_speed: float = aircraft.linear_velocity.length()
	if cur_speed < stall_speed_mps + stall_margin_mps + 10.0:
		# Too slow: fly straight, nose slightly down, build speed
		nav_waypoint = aircraft.global_position + aircraft.global_transform.basis.z * 500.0
		nav_waypoint.y = aircraft.global_position.y - 20.0
		_update_maneuver_waypoint()
		_navigate_to_waypoint(delta)
		target_speed = 120.0
		return

	target_speed = 100.0
	var target_pos: Vector3 = _get_surface_target_position(combat_target)
	var to_tgt: Vector3 = target_pos - aircraft.global_position
	to_tgt.y = 0.0
	var dir: Vector3 = to_tgt.normalized() if to_tgt.length() > 1.0 else aircraft.global_transform.basis.z
	var setup_dist: float = bomb_run_setup_distance_m if _run_weapon_type == "Bomb" else attack_run_distance_m
	nav_waypoint = target_pos - dir * setup_dist
	var terrain_max: float = _sample_max_terrain_height_along_path(nav_waypoint, target_pos, 8)
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

	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)

	var dist_to_wp: float = aircraft.global_position.distance_to(nav_waypoint)
	if dist_to_wp < 150.0:
		# Reached setup point: bombs go level-inbound first, guns can start dive immediately
		if _run_weapon_type == "Bomb":
			change_state(State.ATTACK_INBOUND)
		else:
			change_state(State.ATTACK_DIVE)
		_committed_turn_sign = 0.0
		if debug_enabled:
			print("[AIPilot ATTACK] Reached setup point, next phase: ", State.keys()[current_state])

func _state_attack_inbound(delta: float):
	"""Bomb run inbound leg: fly level toward target at setup altitude, then dive at bomb_dive_start_distance_m."""
	if _check_air_threat_proximity():
		return
	if not ground_attack_enabled:
		change_state(State.SEARCH)
		return
	if not combat_target or not is_instance_valid(combat_target):
		change_state(State.SEARCH)
		return
	var target_pos: Vector3 = _get_surface_target_position(combat_target)
	var to_target: Vector3 = target_pos - aircraft.global_position
	var horiz_dist_to_target: float = Vector2(to_target.x, to_target.z).length()
	target_speed = 105.0

	# Fly straight at the target, clamped above the highest terrain between us and
	# the target so we don't fly into hills during the approach.
	var inbound_alt: float = _bomb_run_altitude_m
	var ground_h: float = _smoothed_ground_height if not is_nan(_smoothed_ground_height) else _get_ground_height_at_position(aircraft.global_position)
	if not is_nan(ground_h):
		inbound_alt = max(inbound_alt, ground_h + 220.0)
	var ahead_h: float = _sample_max_terrain_height_along_path(aircraft.global_position, target_pos, 4)
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
	var alt_ready: bool = aircraft.global_position.y >= (_bomb_run_altitude_m - 50.0)
	if horiz_dist_to_target <= bomb_dive_start_distance_m and alt_ready:
		change_state(State.ATTACK_DIVE)
		_committed_turn_sign = 0.0
		if debug_enabled:
			var alt_above: float = aircraft.global_position.y - target_pos.y
			print("[AIPilot ATTACK] Dive start: target=", combat_target.name, "  horiz_range=", snapped(horiz_dist_to_target, 1.0), "m  alt_above=", snapped(alt_above, 1.0), "m  aim_height=", bomb_dive_aim_height_m, "m")
	elif horiz_dist_to_target <= bomb_dive_start_distance_m * 0.4:
		# Abort: we're way too close and still too low ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â can't set up a proper dive
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
	if not combat_target or not is_instance_valid(combat_target):
		change_state(State.SEARCH)
		return

	var target_pos: Vector3 = _get_surface_target_position(combat_target)
	var dist_to_target: float = aircraft.global_position.distance_to(target_pos)

	# Bomb runs need a much larger break-off margin ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â they dive from high altitude and need room to recover.
	var pull_up_dist: float = bomb_pull_up_distance_m if _run_weapon_type == "Bomb" else attack_pull_up_distance_m

	# Break off when we've dropped all planned bombs (3 for bomb runs)
	if _run_weapon_type == "Bomb" and _bombs_dropped_this_run >= _bombs_to_drop_this_run:
		change_state(State.ATTACK_BREAK_OFF)
		_committed_turn_sign = 0.0
		if debug_enabled:
			print("[AIPilot ATTACK] Break-off: dropped ", _bombs_dropped_this_run, " bombs, pulling up")
		return
	# Break off when too close (for bomb runs, only after dropping or when critically close for safety)
	var min_safe_dist: float = 120.0 if _run_weapon_type == "Bomb" else pull_up_dist
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
	if _run_weapon_type == "Bomb":
		aim_height = bomb_dive_aim_height_m
		var highest_terrain: float = _sample_max_terrain_height_along_path(aircraft.global_position, target_pos, 6)
		if not is_nan(highest_terrain):
			var min_aim_y: float = highest_terrain + 25.0
			aim_height = max(aim_height, min_aim_y - target_pos.y)
	var aim_pos: Vector3 = target_pos + Vector3(0.0, aim_height, 0.0)
	if "linear_velocity" in combat_target:
		aim_pos += combat_target.linear_velocity * attack_aim_lead_time_s

	# Bomb runs: refine aim using predicted impact ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â steer to put the bullseye on target
	var horiz_dist: float = Vector2(aircraft.global_position.x - target_pos.x, aircraft.global_position.z - target_pos.z).length()
	var alt_above: float = aircraft.global_position.y - target_pos.y
	var ccip_impact: Vector3 = Vector3.ZERO  # Shared between aim correction and release check
	if _run_weapon_type == "Bomb":
		# Throttle CCIP calculation — ballistic sim is expensive (~500 iterations + raycasts)
		_ccip_cache_timer -= delta
		if _ccip_cache_timer <= 0.0:
			_ccip_cache_timer = 0.1  # Recalculate every ~6 physics frames
			_ccip_cached_result = _predict_bomb_impact_point()
		ccip_impact = _ccip_cached_result
		if ccip_impact != Vector3.ZERO:
			var err_h: Vector3 = Vector3(target_pos.x - ccip_impact.x, 0.0, target_pos.z - ccip_impact.z)
			var correction_strength: float = clamp(0.6 + 0.6 * (1.0 - horiz_dist / 500.0), 0.6, 1.2)
			aim_pos += err_h * correction_strength
		# In release window: aim closer to target and use precise steering
		# Smooth transition 600ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢400m to avoid abrupt aim-height jump that causes pitch oscillation
		var release_t: float = clamp(1.0 - (horiz_dist - 400.0) / 200.0, 0.0, 1.0) if alt_above < 400.0 else 0.0
		var aim_height_close: float = lerp(aim_height, 15.0, release_t)
		aim_pos.y = target_pos.y + aim_height_close
		_dive_precise_aim = horiz_dist < 500.0 and alt_above < 400.0
	else:
		_dive_precise_aim = false

	nav_waypoint = aim_pos
	maneuver_waypoint = aim_pos
	if nav_target:
		nav_target.global_position = maneuver_waypoint
	_navigate_to_waypoint(delta)

	if _run_weapon_type == "Bomb":
		_handle_bomb_release_run(aim_pos, target_pos, ccip_impact)
	else:
		# Fire guns only when precisely aimed (within ~5Ãƒâ€šÃ‚Â° cone)
		var fwd: Vector3 = aircraft.global_transform.basis.z
		var to_tgt: Vector3 = (aim_pos - aircraft.global_position).normalized()
		var dot: float = fwd.dot(to_tgt)
		if dot > cos(deg_to_rad(6.0)):  # ~6 deg cone - fire a touch earlier on valid runs
			_fire_guns()
		else:
			_stop_firing()

	target_speed = 120.0  # Faster during attack run

func _state_attack_break_off(delta: float):
	"""Fly away from target until far enough, then return to SEARCH to set up new run."""
	if _check_air_threat_proximity():
		return
	if not ground_attack_enabled:
		change_state(State.SEARCH)
		return
	if not combat_target or not is_instance_valid(combat_target):
		change_state(State.SEARCH)
		return

	var target_pos: Vector3 = _get_surface_target_position(combat_target)
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
	nav_waypoint.y = maxf(aircraft.global_position.y + 150.0, patrol_altitude_m)  # Climb back toward mission altitude while egressing
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
			# Don't recompute precise_aim_t here — that creates a feedback loop where
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
		# Direct high-authority aiming: error × gain, minimal damping.
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

	if debug_enabled and Engine.get_process_frames() % 30 == 0 and is_instance_valid(combat_target):
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
		if not (enemy is Node3D):
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

func _should_switch_dogfight_target(current_target: Node3D, candidate: Node3D) -> bool:
	if not candidate or not is_instance_valid(candidate):
		return false
	if not current_target or not is_instance_valid(current_target):
		return true
	if candidate == current_target:
		return false
	var current_dist: float = aircraft.global_position.distance_to(current_target.global_position)
	var candidate_dist: float = aircraft.global_position.distance_to(candidate.global_position)
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
		gun_choice = "Autocannon"
	if gun_choice.is_empty():
		gun_choice = "Autocannon"

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
	var aam_targeting: Node = aircraft.find_child("ControlTargeting_AAM", true, false)
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
	if not control_weapons:
		return dogfight_default_muzzle_velocity_mps
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
			return maxf(float(hp.weapon_instance.muzzle_velocity), 50.0)
	return dogfight_default_muzzle_velocity_mps

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
	
	if dist_to_target > dogfight_max_range_m:
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
	var max_tof: float = maxf(dogfight_fire_max_tof_s, 0.1)
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
			return

func _plan_attack_run_weapon() -> void:
	"""Choose one weapon profile for this run. Prefer bombs when available."""
	_run_weapon_type = "Autocannon"
	_bombs_to_drop_this_run = 0
	_bombs_dropped_this_run = 0
	_last_bomb_drop_time_s = -INF
	_prev_ccip_miss = INF
	_ccip_cache_timer = 0.0
	_ccip_cached_result = Vector3.ZERO
	if not control_weapons:
		return

	var bomb_ready: int = _count_ready_bombs()
	if bomb_ready > 0:
		_run_weapon_type = "Bomb"
		var total_ammo: int = _get_total_bomb_ammo()
		_bombs_to_drop_this_run = min(3, total_ammo)
	else:
		_run_weapon_type = _choose_non_bomb_weapon_type()

	_set_selected_control_weapon_type(_run_weapon_type)

func _choose_non_bomb_weapon_type() -> String:
	if not control_weapons:
		return "Autocannon"
	var types: Array = _get_control_weapon_types()
	if types.is_empty():
		return "Autocannon"
	if types.has("Autocannon"):
		return "Autocannon"
	for t in types:
		if t != "Bomb":
			return String(t)
	return String(types[0])

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

func _handle_bomb_release_run(aim_pos: Vector3, target_pos: Vector3, ccip_predicted: Vector3 = Vector3.ZERO) -> void:
	if _bombs_to_drop_this_run <= 0:
		return
	if _bombs_dropped_this_run >= _bombs_to_drop_this_run:
		return
	var now_s: float = Time.get_ticks_msec() / 1000.0
	if now_s - _last_bomb_drop_time_s < bomb_release_spacing_s:
		return

	var alt_above_target: float = aircraft.global_position.y - target_pos.y
	# Safety window: never release outside 5ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“600m above target
	if alt_above_target > bomb_release_altitude_window_m or alt_above_target < 5.0:
		return
	# Must be descending
	var horiz_speed: float = Vector2(aircraft.linear_velocity.x, aircraft.linear_velocity.z).length()
	var fpa_deg: float = rad_to_deg(atan2(-aircraft.linear_velocity.y, max(horiz_speed, 1.0)))
	if fpa_deg < 30.0:
		return  # Not in a real dive yet ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â CCIP is unreliable at shallow angles

	# CCIP release: hold until predicted impact is close enough to target,
	# unless we're very low (fallback ensures we always release before breaking off).
	# If CCIP failed (Vector3.ZERO ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â no terrain found), release immediately.
	if ccip_predicted != Vector3.ZERO and alt_above_target > bomb_ccip_fallback_alt_m:
		var pred_err_h: float = Vector2(target_pos.x - ccip_predicted.x, target_pos.z - ccip_predicted.z).length()
		var improving: bool = pred_err_h < _prev_ccip_miss - 0.5  # Still getting noticeably better
		_prev_ccip_miss = pred_err_h
		if pred_err_h > bomb_ccip_release_tolerance_m:
			return  # Not accurate enough yet
		if improving and pred_err_h > 8.0:
			return  # Accuracy still improving ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â wait for the peak

	var dropped_bomb: BombProjectile = _drop_one_bomb()
	if dropped_bomb:
		_bombs_dropped_this_run += 1
		_last_bomb_drop_time_s = now_s

		var hdist: float = Vector2(aircraft.global_position.x - target_pos.x, aircraft.global_position.z - target_pos.z).length()
		var pred_err_h: float = Vector2(target_pos.x - ccip_predicted.x, target_pos.z - ccip_predicted.z).length() if ccip_predicted != Vector3.ZERO else -1.0
		var spd: float = aircraft.linear_velocity.length()
		var fpa_at_drop: float = rad_to_deg(atan2(-aircraft.linear_velocity.y, max(horiz_speed, 1.0)))
		print("ÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚Â BOMB RELEASE ÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚Â")
		print("  aircraft  pos=", snapped(aircraft.global_position, Vector3.ONE * 0.1), "  spd=", snapped(spd, 0.1), " m/s  fpa=", snapped(fpa_at_drop, 0.1), "Ãƒâ€šÃ‚Â°")
		print("  target    pos=", snapped(target_pos, Vector3.ONE * 0.1), "  alt_above=", snapped(alt_above_target, 0.1), "m  hdist=", snapped(hdist, 0.1), "m")
		if ccip_predicted != Vector3.ZERO:
			print("  predicted pos=", snapped(ccip_predicted, Vector3.ONE * 0.1), "  miss_from_target=", snapped(pred_err_h, 0.1), "m")
		else:
			print("  predicted pos=N/A (fallback release ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â no terrain in CCIP)")

		# Tag the bomb with the intended target so it can report miss at impact
		dropped_bomb.set_meta("debug_aim_target", target_pos)
		dropped_bomb.set_meta("debug_predicted_impact", ccip_predicted)

func _drop_one_bomb() -> BombProjectile:
	for hp in _get_control_weapon_hardpoints():
		if not hp or not hp.weapon_instance:
			continue
		if hp.weapon_instance.weapon_name != "Bomb":
			continue
		if hp.weapon_instance.can_fire() and hp.fire():
			return hp.weapon_instance.get("last_bomb_dropped") as BombProjectile
	return null

func _predict_bomb_impact_point(log_debug: bool = false) -> Vector3:
	"""Estimate bomb impact point using ballistic simulation.
	The Terrain3D plugin doesn't register physics collision for raycasts,
	so we use Terrain3D.get_height() as the primary detection method ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â
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
				start_pos = hp.global_position
			break

	var r_offset: Vector3 = start_pos - aircraft.global_position
	var angular_vel_component: Vector3 = aircraft.angular_velocity.cross(r_offset)
	var current_vel: Vector3 = Vector3.DOWN * drop_force + aircraft.linear_velocity + angular_vel_component

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

	var time_step: float = 0.05
	var max_time: float = 15.0
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

		# Primary: physics raycast (works for standard StaticBody3D terrain)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
		query.exclude = [aircraft]
		query.collision_mask = 0xFFFFFFFF
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit and hit.has("position"):
			if log_debug:
				print("[CCIP] raycast HIT at t=", snapped(step * time_step, 0.01), "s  pos=", snapped(hit["position"], Vector3.ONE * 0.1))
			return hit.position

		# Fallback: Terrain3D height API ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â mirrors projectile_new.gd tunneling detection
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
					if log_debug:
						print("[CCIP] Terrain3D HIT at t=", snapped(step * time_step, 0.01), "s  pos=", snapped(impact, Vector3.ONE * 0.1))
					return impact

		if next_pos.y < -1000.0:
			if log_debug:
				print("[CCIP] fell off world at t=", snapped(step * time_step, 0.01), "s")
			return Vector3.ZERO
		current_pos = next_pos

	if log_debug:
		print("[CCIP] ran out of steps, final_pos=", snapped(current_pos, Vector3.ONE * 0.1))
	return Vector3.ZERO

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
		nav_waypoint.y = patrol_altitude_m
	
	# Climb/descend to patrol altitude while navigating
	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)
	
	# Check horizontal distance to carrier
	var h_dist: float = Vector2(aircraft.global_position.x - carrier_position.x, aircraft.global_position.z - carrier_position.z).length()
	
	# Start landing approach when within 4000m
	if h_dist < 4000.0:
		if debug_enabled:
			print("[AIPilot RTB] Reached carrier vicinity (", h_dist, "m), starting approach sequence.")
		start_landing()

func _get_approach_deck_y() -> float:
	"""Deck reference for approach phase altitudes."""
	if _approach_wp.size() >= 5:
		var wp4: Node3D = _approach_wp[4] as Node3D
		if is_instance_valid(wp4):
			return wp4.global_position.y
	# Fallback: carrier center + configured deck offset
	return carrier_position.y + approach_deck_height_fallback_m

func _get_approach_entry_altitude() -> float:
	if not is_instance_valid(aircraft):
		return approach_entry_altitude_m

	var reference_y: float = aircraft.global_position.y - altitude_agl
	if aircraft.has_method("get_effective_altitude_reference_y"):
		reference_y = float(aircraft.get_effective_altitude_reference_y())

	var current_effective_altitude_m: float = altitude_agl
	if aircraft.has_method("get_effective_altitude_agl_m"):
		current_effective_altitude_m = float(aircraft.get_effective_altitude_agl_m())

	var target_effective_altitude_m: float = maxf(approach_entry_altitude_m, current_effective_altitude_m)
	return reference_y + target_effective_altitude_m

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
	if absf(bank_error) > deg_to_rad(1.0):
		var min_roll: float = 0.40 * signf(bank_error)
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
		yaw_err_rad * effective_yaw_gain - yaw_rate * 0.10 - sideslip * 0.15 - sin(current_roll) * 0.08,
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
		change_state(State.SEARCH)
		return

	var points: Array[Vector3] = _get_approach_path_points()
	if points.size() < 5:
		change_state(State.SEARCH)
		return

	if _landing_phase <= 0:
		target_speed = 80.0
		nav_waypoint = Vector3(points[0].x, _get_approach_entry_altitude(), points[0].z)
		_update_maneuver_waypoint()
		_navigate_to_waypoint(delta)
		if _horizontal_distance_vec3(aircraft.global_position, points[0]) <= approach_phase0_capture_m:
			_deploy_landing_gear()
			target_speed = approach_post_gate_speed_mps
			throttle_input = approach_post_gate_throttle_cut
			if control_engine and control_engine.has_method("set_target_power"):
				control_engine.set_target_power(throttle_input)
			if engine and engine.has_method("set_throttle_input"):
				engine.set_throttle_input(throttle_input)
			_landing_phase = 1
			if debug_enabled:
				print("[AIPilot] Approach(path): captured approach entry, switching to path follower")
		return

	var closest: Dictionary = _find_closest_polyline_point_xz(points, aircraft.global_position)
	if not bool(closest.get("valid", false)):
		change_state(State.SEARCH)
		return
	var speed_mps: float = aircraft.linear_velocity.length()
	var total_length: float = float(closest.get("total_length", 0.0))
	var along_distance: float = float(closest.get("along_distance", 0.0))
	var remaining_distance: float = maxf(total_length - along_distance, 0.0)
	var lookahead_m: float = clampf(
		speed_mps * approach_path_lookahead_time_s,
		approach_path_min_lookahead_m,
		approach_path_max_lookahead_m
	)
	var sample: Dictionary = _sample_polyline_xz(points, minf(along_distance + lookahead_m, total_length))
	if not bool(sample.get("valid", false)):
		change_state(State.SEARCH)
		return

	nav_waypoint = sample.get("position", points[1])
	maneuver_waypoint = nav_waypoint
	if nav_target:
		nav_target.global_position = maneuver_waypoint
	var remaining_t: float = clampf(remaining_distance / maxf(total_length, 1.0), 0.0, 1.0)
	var far_speed: float = maxf(approach_path_far_speed_mps, approach_post_gate_speed_mps)
	var near_speed: float = maxf(approach_path_near_speed_mps, approach_post_gate_speed_mps)
	target_speed = lerpf(near_speed, far_speed, remaining_t)
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

	var final_segment_length: float = _horizontal_distance_vec3(points[3], points[4])
	var final_segment_start: float = maxf(total_length - final_segment_length, 0.0)
	if along_distance >= maxf(final_segment_start - approach_path_final_switch_buffer_m, 0.0):
		if debug_enabled:
			print("[AIPilot] Approach(path): established on final segment, switching to LANDING")
		change_state(State.LANDING)

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

func _state_approach(delta: float):
	"""Carrier approach: phase 0ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢3 (approach_0ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢3) then LANDING toward approach_4."""
	if approach_guidance_mode == ApproachGuidanceMode.PATH_FOLLOWER:
		_state_approach_path_follower(delta)
		return
	if _approach_wp.size() < 5:
		change_state(State.SEARCH)
		return
	if _landing_phase >= _approach_wp.size():
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
			if h1 <= approach_phase0_capture_m:
				_landing_phase = 2
				if debug_enabled:
					print("[AIPilot] Approach: reached approach_0, turning to approach_1")

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
			if h2 <= approach_phase1_capture_m:
				_landing_phase = 3
				if debug_enabled:
					print("[AIPilot] Approach: reached approach_1, turning to approach_2")

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
			if h3 <= approach_phase2_capture_m:
				_landing_phase = 4
				if debug_enabled:
					print("[AIPilot] Approach: reached approach_2, turning to approach_3")

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
			if h4 <= approach_phase3_capture_m:
				if debug_enabled:
					print("[AIPilot] Approach: reached approach_3, starting final approach")
				change_state(State.LANDING)

func _state_landing(delta: float):
	"""Final approach: aim the velocity vector at approach_4 (FPA steering).
	Throttle holds approach speed. This correctly accounts for the nose being
	above the actual flight path at low speed with gear/flaps extended."""
	var target_pos: Vector3
	if approach_guidance_mode == ApproachGuidanceMode.PATH_FOLLOWER:
		var path_target: Dictionary = _get_landing_path_target()
		if not bool(path_target.get("valid", false)):
			change_state(State.SEARCH)
			return
		target_pos = path_target.get("target_pos", Vector3.ZERO)
	else:
		if _approach_wp.size() < 5 or not is_instance_valid(_approach_wp[4]):
			change_state(State.SEARCH)
			return
		var wp4: Node3D = _approach_wp[4] as Node3D
		target_pos = wp4.global_position
	nav_waypoint = target_pos
	_update_maneuver_waypoint()  # keeps waypoint marker visible

	var to_target: Vector3 = target_pos - aircraft.global_position
	var vel: Vector3 = aircraft.linear_velocity
	var horiz_dist: float = Vector2(to_target.x, to_target.z).length()
	var horiz_speed: float = Vector2(vel.x, vel.z).length()
	var speed: float = vel.length()
	var b: Basis = aircraft.global_transform.basis
	var ang_vel: Vector3 = aircraft.angular_velocity

	# Wire caught: kill engine, release pitch/yaw, but keep wings-level roll command
	# (mirrors real pilot behaviour ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â hold aileron to stay upright through the arrest)
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

		# ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Arrest debug ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
		var delta_time: float = get_physics_process_delta_time()
		if not _arrest_engaged_prev:
			# First frame of engagement
			_arrest_start_pos = aircraft.global_position
			_arrest_prev_vel = vel
			_arrest_debug_timer = 0.0
			_arrest_stopped_reported = false
			print("ÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚Â WIRE CAUGHT ÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚Â  pos=", snapped(aircraft.global_position, Vector3.ONE * 0.1),
				"  speed=", snapped(speed, 0.1), " m/s")
		_arrest_engaged_prev = true

		_arrest_debug_timer += delta_time
		if _arrest_debug_timer >= _arrest_debug_interval:
			_arrest_debug_timer = 0.0
			var run: float = aircraft.global_position.distance_to(_arrest_start_pos)
			var decel_ms2: float = (_arrest_prev_vel - vel).length() / _arrest_debug_interval
			var decel_g: float = decel_ms2 / 9.8
			var rot_deg: Vector3 = Vector3(
				rad_to_deg(asin(clamp(b.z.y, -1.0, 1.0))),   # pitch: +ve = nose down (b.z.y>0 = fwd axis tilts down)
				rad_to_deg(atan2(b.x.y, b.y.y)),              # roll: bank angle
				rad_to_deg(atan2(b.z.x, b.z.z))               # yaw: heading in world XZ
			)
			# Collect gear compressions
			var gear_node = aircraft.find_child("LandingGear", true, false)
			var comp_str: String = "n/a"
			if gear_node and "gear_compressions" in gear_node and gear_node.gear_compressions.size() > 0:
				var parts: Array[String] = []
				for c in gear_node.gear_compressions:
					parts.append(str(snapped(c, 0.001)))
				comp_str = "[" + ", ".join(parts) + "] m"
			print("  run=", snapped(run, 0.1), "m  spd=", snapped(speed, 0.1),
				" m/s  decel=", snapped(decel_g, 0.01), "g",
				"  rot(P/R/Y)=", snapped(rot_deg, Vector3.ONE * 0.1),
				"  gear=", comp_str)
			_arrest_prev_vel = vel

		if speed < 2.0 and not _arrest_stopped_reported:
			var run: float = aircraft.global_position.distance_to(_arrest_start_pos)
			print("ÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚Â STOPPED  run=", snapped(run, 0.1), " m ÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚ÂÃƒÂ¢Ã¢â‚¬ÂÃ‚Â")
			_arrest_stopped_reported = true
		# ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
		return
	# Cable just released ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â go idle and hand aircraft to FlightDeckManager
	if _arrest_engaged_prev:
		_arrest_engaged_prev = false
		_arrest_stopped_reported = false
		print("[AIPilot] Arrest ended ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â transitioning to IDLE and requesting recovery")
		change_state(State.IDLE)
		_request_carrier_recovery()
		return

	if _should_wave_off_for_busy_deck(horiz_dist):
		if debug_enabled:
			print("[AIPilot] Wave-off: landing deck is active, going around")
		_begin_missed_approach()
		return

	if _should_start_missed_approach():
		_begin_missed_approach()
		return

	# Speed target: bleed off as we close in (gear+flap drag assists)
	if horiz_dist < 80.0:
		target_speed = 40.0
	elif horiz_dist < 150.0:
		target_speed = 44.0
	elif horiz_dist < 250.0:
		target_speed = 48.0
	else:
		target_speed = 54.0

	# === ROLL: wings level on short final (< 200 m), bearing-based further out ===
	var current_roll: float = atan2(b.x.y, b.y.y)
	var roll_rate: float = ang_vel.dot(b.z)
	# Bearing error computed always ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â needed for rudder correction throughout final approach
	var bearing_err_final: float = 0.0
	var horiz_to_target_flat: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	if horiz_to_target_flat.length() > 1.0:
		var heading_rad_f: float = atan2(b.z.x, b.z.z)
		var bearing_rad_f: float = atan2(horiz_to_target_flat.x, horiz_to_target_flat.z)
		bearing_err_final = _normalize_angle(bearing_rad_f - heading_rad_f)
	var desired_bank: float = 0.0
	if horiz_dist > 200.0:
		desired_bank = clamp(bearing_err_final * 2.5, -deg_to_rad(30.0), deg_to_rad(30.0))
		if flip_roll_direction:
			desired_bank = -desired_bank
	# desired_bank stays 0.0 inside 200 m ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â command wings level
	var bank_error: float = desired_bank - current_roll
	var raw_roll: float = clamp(bank_error * 11.0 - roll_rate * 0.3, -1.0, 1.0)
	roll_input = lerp(_smoothed_roll_input, raw_roll, 0.25)
	_smoothed_roll_input = roll_input
	var short_final_dist_m: float = maxf(landing_short_final_bank_distance_m, 1.0)
	var close_alignment_t: float = 1.0 - clampf(horiz_dist / short_final_dist_m, 0.0, 1.0)
	var touchdown_level_dist_m: float = maxf(landing_touchdown_level_distance_m, 1.0)
	var touchdown_level_t: float = 1.0 - clampf(horiz_dist / touchdown_level_dist_m, 0.0, 1.0)
	var landing_bank_limit_deg: float = lerpf(
		30.0,
		clampf(landing_short_final_bank_limit_deg, 4.0, 30.0),
		close_alignment_t
	)
	landing_bank_limit_deg = lerpf(
		landing_bank_limit_deg,
		clampf(landing_touchdown_bank_limit_deg, 2.0, landing_bank_limit_deg),
		touchdown_level_t
	)
	var aligned_bank: float = clampf(
		bearing_err_final * lerpf(2.5, 3.0, close_alignment_t),
		-deg_to_rad(landing_bank_limit_deg),
		deg_to_rad(landing_bank_limit_deg)
	)
	var short_final_min_bank_deg: float = lerpf(
		clampf(landing_short_final_min_bank_deg, 0.0, landing_bank_limit_deg),
		0.0,
		touchdown_level_t
	)
	var short_final_min_bank_rad: float = deg_to_rad(short_final_min_bank_deg)
	if close_alignment_t > 0.0 and absf(bearing_err_final) > deg_to_rad(1.0) and absf(aligned_bank) < short_final_min_bank_rad:
		aligned_bank = signf(bearing_err_final)
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

	# === PITCH: aim the velocity vector at approach_4 (not the nose) ===
	# At slow speed with gear/flaps the nose is above the actual flight path.
	# By matching the velocity vector angle to the required FPA we fly where
	# we are actually going, not where the nose is pointing.
	var desired_fpa: float = atan2(to_target.y, max(horiz_dist, 10.0))
	var current_fpa: float = atan2(vel.y, max(horiz_speed, 1.0))
	var fpa_err: float = desired_fpa - current_fpa
	var pitch_rate_up: float = -ang_vel.dot(b.x)
	var raw_pitch: float = clamp(fpa_err * 2.5 - pitch_rate_up * 0.4, -0.5, 0.5)
	pitch_input = lerp(_smoothed_pitch_input, raw_pitch, 0.15)
	_smoothed_pitch_input = pitch_input

	# === THROTTLE: maintain approach speed (min 0.1 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â lower than normal nav's 0.4) ===
	var commanded_target_speed: float = _get_effective_target_speed()
	var speed_err: float = commanded_target_speed - speed
	throttle_input = clamp(throttle_input + clamp(speed_err * 0.01, -0.05, 0.05), 0.1, 1.0)
	if speed < stall_speed_mps + stall_margin_mps:
		throttle_input = 1.0

	# === YAW: coordinate the bank + rudder correction for heading fine-tuning ===
	var yaw_correction_final: float = clamp(bearing_err_final * 0.4, -0.3, 0.3)
	var raw_yaw: float = -sin(desired_bank) * 0.5 + yaw_correction_final
	yaw_input = lerp(_smoothed_yaw_input, raw_yaw, input_smoothing)
	_smoothed_yaw_input = yaw_input
	var aligned_yaw_correction_limit: float = lerpf(0.3, 0.45, close_alignment_t)
	var aligned_yaw_correction: float = clampf(
		bearing_err_final * landing_short_final_yaw_gain,
		-aligned_yaw_correction_limit,
		aligned_yaw_correction_limit
	)
	var yaw_rate: float = ang_vel.dot(b.y)
	var aligned_raw_yaw: float = clampf(
		-sin(aligned_bank) * 0.5 + aligned_yaw_correction - yaw_rate * 0.12,
		-1.0,
		1.0
	)
	yaw_input = lerpf(_smoothed_yaw_input, aligned_raw_yaw, lerpf(input_smoothing, 0.4, close_alignment_t))
	_smoothed_yaw_input = yaw_input

	if debug_enabled and Engine.get_process_frames() % 30 == 0:
		print("[AIPilot FINAL] dist=%.0fm  ÃƒÅ½Ã¢â‚¬Âalt=%.1fm  fpa: want=%.1fÃƒâ€šÃ‚Â°  act=%.1fÃƒâ€šÃ‚Â°  err=%.1fÃƒâ€šÃ‚Â°  pitch=%.2f  thr=%.2f  spd=%.0f" % [
			horiz_dist, to_target.y,
			rad_to_deg(desired_fpa), rad_to_deg(current_fpa), rad_to_deg(fpa_err),
			pitch_input, throttle_input, speed])

func _state_missed_approach(delta: float):
	"""Bolter/go-around: climb to takeoff_0, then restart the landing pattern."""
	if not is_instance_valid(_takeoff_wp):
		if not _find_takeoff_waypoint():
			push_warning("[AIPilot] Missed approach: could not find takeoff_0")
			change_state(State.RTB)
			return

	target_speed = maxf(landing_bolter_target_speed_mps, approach_path_far_speed_mps)
	nav_waypoint = _takeoff_wp.global_position
	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)
	throttle_input = 1.0

	var deck_height: float = nav_waypoint.y
	if _approach_wp.size() >= 5 and is_instance_valid(_approach_wp[4]):
		deck_height = (_approach_wp[4] as Node3D).global_position.y
	if aircraft.global_position.y >= deck_height + landing_bolter_gear_retract_height_m:
		_stow_landing_config()

	var horiz_to_takeoff: float = Vector2(
		aircraft.global_position.x - nav_waypoint.x,
		aircraft.global_position.z - nav_waypoint.z
	).length()
	var close_to_rejoin_altitude: bool = aircraft.global_position.y >= nav_waypoint.y - landing_bolter_rejoin_altitude_margin_m
	if horiz_to_takeoff <= landing_bolter_rejoin_distance_m and close_to_rejoin_altitude:
		if debug_enabled:
			print("[AIPilot] Missed approach: reached takeoff_0, restarting landing pattern")
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
	# In dogfight, the aircraft intentionally banks up to dogfight_bank_cmd_limit_deg (e.g. 85Ãƒâ€šÃ‚Â°).
	# cos(85Ãƒâ€šÃ‚Â°) = 0.087 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â below the normal 0.3 threshold ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â so we raise the limit only in states
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
	# Approach/Landing are also intentional descents ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â don't interfere with spiral recovery
	var in_dive_or_attack: bool = current_state in [State.DOGFIGHT, State.ATTACK_DIVE, State.APPROACH, State.LANDING]
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
	# Continuous ramp 0ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢1 as alt deficit grows 0ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢80m. Replaces the old binary in_attack_climb
	# switch at 30m which caused an abrupt gain step and drove oscillation.
	var attack_climb_t: float = clamp(alt_err / 80.0, 0.0, 1.0) if in_attack_approach else 0.0
	var needs_high_authority: bool = in_dive_state or in_break_off or in_landing or in_carrier_approach
	var vs_limit: float
	var vs_gain: float
	if in_landing:
		# Carrier final: need enough descent (150m over ~540m) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â default 10 m/s cap is too low
		vs_limit = 18.0
		vs_gain = 0.18
	elif in_carrier_approach:
		vs_limit = 20.0
		vs_gain = 0.16
	elif needs_high_authority:
		# Soft dive entry: ramp up over 1.2s to avoid initial pull-too-hard oscillation
		var now_s: float = Time.get_ticks_msec() / 1000.0
		var dive_age_s: float = now_s - _dive_entry_time_s if _dive_entry_time_s > -INF else 999.0
		var entry_t: float = clamp(dive_age_s / 1.2, 0.0, 1.0)
		vs_limit = lerp(18.0, 55.0, entry_t)
		vs_gain = lerp(0.12, 0.25, entry_t)
	elif in_attack_approach:
		# Smoothly blend authority as altitude deficit grows ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â no abrupt step at any threshold
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
		vs_limit = 10.0
		vs_gain = 0.08
	var desired_vs: float = clamp(alt_err * vs_gain, -vs_limit, vs_limit)
	# Deadband: settle when close to target altitude ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â applies in all non-dive/break-off states
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
	if current_state not in [State.APPROACH, State.LANDING, State.IDLE]:
		var low_agl_guard_band_m: float = emergency_min_agl_m + 120.0
		if altitude_agl < low_agl_guard_band_m:
			var low_guard_t: float = clampf((low_agl_guard_band_m - altitude_agl) / maxf(low_agl_guard_band_m, 1.0), 0.0, 1.0)
			var min_climb_vs: float = lerpf(2.0, maxf(dogfight_ground_protect_min_climb_vs_mps, 10.0), low_guard_t)
			desired_vs = maxf(desired_vs, min_climb_vs)
	var vs_err: float = desired_vs - vel.y
	var bank_compensation: float = clamp(1.0 / max(cos(bank_rad), 0.7), 1.0, 1.2)
	var pitch_limit: float = 0.75 if in_dogfight else max_pitch_angle / deg_to_rad(60.0)
	if in_carrier_approach:
		pitch_limit = maxf(pitch_limit, 0.85)
	if formation_soft_t > 0.0 and not in_dogfight:
		var formation_pitch_limit: float = deg_to_rad(formation_close_pitch_limit_deg) / deg_to_rad(60.0)
		pitch_limit = minf(pitch_limit, lerpf(pitch_limit, formation_pitch_limit, formation_soft_t))
	var pitch_gain: float
	if in_carrier_approach:
		pitch_gain = 0.11
	elif needs_high_authority:
		pitch_gain = 0.10
	elif in_attack_approach:
		pitch_gain = lerp(0.06, 0.08, attack_climb_t)  # Gentler ceiling reduces overshoot
	elif in_dogfight:
		pitch_gain = 0.14
	else:
		pitch_gain = 0.06
	if formation_soft_t > 0.0 and not in_dogfight:
		pitch_gain = lerpf(pitch_gain, pitch_gain * formation_close_pitch_gain_scale, formation_soft_t)
	var pitch_rate_damping: float = 0.45 if in_dive_state or in_dogfight else 0.5  # Stronger damping in combat
	var raw_pitch: float = clamp(vs_err * pitch_gain * bank_compensation - pitch_rate_up * pitch_rate_damping, -pitch_limit, pitch_limit)
	# Min pitch prevents dead-zone but must not fight the controller when it is already correcting
	# correctly. Only enforce the floor when vs_err agrees with the altitude error direction.
	var min_pitch_threshold: float = 60.0 if in_dive_state else 40.0
	if not in_dogfight and abs(alt_err) > min_pitch_threshold:
		var min_pitch: float = (0.10 if needs_high_authority else 0.04) * sign(alt_err)
		if sign(vs_err) == sign(alt_err) and abs(raw_pitch) < abs(min_pitch):
			raw_pitch = min_pitch
	# Slightly heavier smoothing during attack approach to dampen bobbing
	var effective_pitch_smoothing: float
	if in_dive_state:
		effective_pitch_smoothing = 0.12
	elif in_carrier_approach:
		effective_pitch_smoothing = 0.14
	elif in_attack_approach:
		effective_pitch_smoothing = 0.15
	else:
		effective_pitch_smoothing = pitch_input_smoothing
	pitch_input = lerp(_smoothed_pitch_input, raw_pitch, effective_pitch_smoothing)
	_smoothed_pitch_input = pitch_input
	
	if debug_enabled and Engine.get_process_frames() % 30 == 0:
		var gh: float = _smoothed_ground_height if not is_nan(_smoothed_ground_height) else _get_ground_height_at_position(aircraft.global_position)
		print("[AIPilot PITCH] Alt: %.1f (Tgt: %.1f, Err: %.1f) | VS: %.1f (Des: %.1f, Err: %.1f) | Pitch: %.3f (Raw: %.3f) | Gnd: %.1f" % [aircraft.global_position.y, nav_waypoint.y, alt_err, vel.y, desired_vs, vs_err, pitch_input, raw_pitch, gh])

	# Dogfight controller internals ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â shows bank/roll PD details every 30 frames
	if debug_enabled and current_state == State.DOGFIGHT and Engine.get_process_frames() % 30 == 0:
		print("  [ROLL_CTL] desired=%+5.0fÃƒâ€šÃ‚Â°  cur=%+5.0fÃƒâ€šÃ‚Â°  err=%+5.1fÃƒâ€šÃ‚Â°  p_gain=%.1f  d=%.2f  raw=%+5.2f  out=%+5.2f  rate=%.2f" % [
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
		var yaw_correction: float = clampf(bearing_err_rad * 0.25, -0.3, 0.3) * (1.0 - high_bank_t)
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
	
	# Low speed protection ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â full throttle, limit pitch-up to avoid bleeding more energy
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
		print("  TARGET: %s  dist=%.0fm  bearing=%.0fÃƒâ€šÃ‚Â°  heading=%.0fÃƒâ€šÃ‚Â°  err=%.0fÃƒâ€šÃ‚Â° (pos=turn R)" % [target_pos, to_target.length(), bearing_to_wp, heading_deg, rad_to_deg(bearing_err)])
		var vel_fwd: float = vel.dot(aircraft.global_transform.basis.z)
		var vel_right: float = vel.dot(aircraft.global_transform.basis.x)
		var turning: String = "RIGHT" if vel_right > 5 else ("LEFT" if vel_right < -5 else "STRAIGHT")
		print("  TURN: %s  desired_bank=%.1fÃƒâ€šÃ‚Â°  current_roll=%.1fÃƒâ€šÃ‚Â°  bank_err=%.1fÃƒâ€šÃ‚Â°  commit=%.0f  flip=%s" % [turn_dir, rad_to_deg(desired_bank), rad_to_deg(current_roll), rad_to_deg(bank_error), _committed_turn_sign, flip_roll_direction])
		print("  ACTUAL: turning=%s (vel_right=%.1f)  vel_fwd=%.1f" % [turning, vel_right, vel_fwd])
		print("  LOCAL: lx=%.2f (right+)  lz=%.2f (ahead+)  lateral_ratio=%.2f" % [lateral_norm, ahead_norm, lateral_norm])
		print("  CMD: roll=%.2f  pitch=%.2f  yaw=%.2f  thr=%.2f" % [roll_input, pitch_input, yaw_input, throttle_input])
		print("  ALT: %.0fm (tgt %.0f)  spd=%.0f  vs=%.1f" % [alt, nav_waypoint.y, speed, vel.y])

func _update_maneuver_waypoint():
	"""Place maneuver waypoint along the direction TO the navigation waypoint"""
	if nav_waypoint == Vector3.ZERO:
		return
	
	# LANDING: always steer directly at approach_4 (touchdown point). No lookahead ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â we must
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
	if current_state not in [State.TRANSIT, State.SEARCH, State.ATTACK_POSITIONING, State.ATTACK_INBOUND, State.ATTACK_DIVE, State.ATTACK_BREAK_OFF, State.ENGAGE, State.APPROACH, State.LANDING, State.MISSED_APPROACH]:
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
		print("[AIPilot TURN] Bank: ", snapped(rad_to_deg(current_roll), 0.1), "Ãƒâ€šÃ‚Â° Pitch: ", snapped(rad_to_deg(current_pitch), 0.1),
			  "Ãƒâ€šÃ‚Â° Alt: ", snapped(current_alt, 0.1), " VS: ", snapped(vertical_speed, 0.1))

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
	if current_state in [State.LAUNCHING, State.LANDING, State.IDLE]:
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

	if lateral_is_better and not emergency_escape and altitude_agl > emergency_min_agl_m + 40.0:
		# A lateral direction has more clearance — full bank toward it.
		var bank_sign: float = signf(escape_angle_deg)
		roll_input = bank_sign * 0.9
		pitch_input = 0.95
	else:
		# No good lateral escape — wings level, full pull up.
		roll_input = 0.0
		pitch_input = 1.0

	yaw_input = 0.0
	throttle_input = 1.0
	# Slam smoothed values so the state machine doesn't fight the override next frame.
	_smoothed_roll_input = roll_input
	_smoothed_pitch_input = pitch_input
	_smoothed_yaw_input = 0.0

	# Force state transition out of attack if needed.
	if current_state in [State.ATTACK_DIVE, State.ATTACK_POSITIONING, State.ATTACK_INBOUND]:
		_attack_recovery_until_s = maxf(_attack_recovery_until_s, Time.get_ticks_msec() / 1000.0 + 4.0)
		change_state(State.ATTACK_BREAK_OFF)

	if debug_enabled and Engine.get_process_frames() % 30 == 0:
		var action: String = ("TURN %.0f deg" % escape_angle_deg) if lateral_is_better else "CLIMB"
		print("[AIPilot TERRAIN] AGL=%.0fm fwd_clr=%.0fm need=%.0fm tti=%.1fs best_dir=%.0f° best_clr=%.0fm — %s" % [
			altitude_agl, forward_clearance, dynamic_margin, tti, escape_angle_deg, best_clearance, action])
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
		if not (contact is Node3D) or not is_instance_valid(contact):
			continue
		var cnode := contact as Node3D
		# Only worry about things near our altitude (skip ground vehicles etc)
		if absf(cnode.global_position.y - my_pos.y) > 200.0:
			continue
		var rel_pos: Vector3 = cnode.global_position - my_pos
		var dist: float = rel_pos.length()
		if dist > 400.0:
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
		if miss_dist < 80.0 and tca < closest_tca:
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

	# Proportional evasion — firm but not violent, so formation flight is possible
	var urgency: float = clampf(1.0 - closest_tca / 3.0, 0.3, 0.7)
	roll_input = bank_sign * urgency
	pitch_input = 0.3 * urgency
	yaw_input = 0.0
	throttle_input = 1.0
	_smoothed_roll_input = roll_input
	_smoothed_pitch_input = pitch_input
	_smoothed_yaw_input = 0.0

	if debug_enabled and Engine.get_process_frames() % 30 == 0:
		print("[AIPilot COLLISION] threat=%s tca=%.1fs miss=%.0fm — EVADING" % [
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

func _emit_player_debug_telemetry(delta: float) -> void:
	if not debug_enabled or aircraft == null:
		return
	if Engine.get_process_frames() % 30 == 0:
		var spd: float = aircraft.linear_velocity.length()
		var alt: float = aircraft.global_position.y
		var vs: float = aircraft.linear_velocity.y
		var pitch_deg: float = rad_to_deg(_get_forward_pitch_rad())
		var h_spd: float = Vector2(aircraft.linear_velocity.x, aircraft.linear_velocity.z).length()
		var fpa_deg: float = rad_to_deg(atan2(-aircraft.linear_velocity.y, max(h_spd, 1.0)))
		var pos: Vector3 = aircraft.global_position
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
		print("[AIPilot TEL] state=PLAYER  [PLAYER]  pos=(", snapped(pos.x, 1), ",", snapped(pos.y, 1), ",", snapped(pos.z, 1), ")  alt=", snapped(alt, 1), "  AGL=", snapped(altitude_agl, 1), "  spd=", snapped(spd, 1), "m/s  VS=", snapped(vs, 1), "  pitch=", snapped(pitch_deg, 0.1), "ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  fpa=", snapped(fpa_deg, 0.1), "ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  cmdP=", snapped(player_pitch_cmd, 0.01), "  aoa=", snapped(est_aoa_deg, 0.1), "ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°  liftRatio=", snapped(est_lift_ratio, 0.01))
	_debug_flight_path_alignment(delta, "PLAYER")

func _debug_flight_path_alignment(delta: float, state_override: String = "") -> void:
	if not debug_enabled or not flight_path_alignment_debug_enabled or aircraft == null:
		return
	if not _is_airborne():
		_flight_path_alignment_debug_timer_s = 0.0
		return
	var velocity: Vector3 = aircraft.linear_velocity
	var speed: float = velocity.length()
	if speed < maxf(flight_path_alignment_debug_min_speed_mps, 1.0):
		return
	_flight_path_alignment_debug_timer_s += delta
	if _flight_path_alignment_debug_timer_s < maxf(flight_path_alignment_debug_interval_s, 0.25):
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

func _update_sensors():
	"""Update AI's limited view of the world"""
	_terrain_check_counter += 1
	var dynamic_terrain_interval: int = max(terrain_check_interval, 1)
	var speed_mps: float = aircraft.linear_velocity.length() if aircraft else 0.0
	if altitude_agl < emergency_min_agl_m + 140.0 or speed_mps > 140.0:
		dynamic_terrain_interval = 1
	elif altitude_agl < emergency_min_agl_m + 260.0 or speed_mps > 110.0:
		dynamic_terrain_interval = min(dynamic_terrain_interval, 2)
	var run_terrain_checks: bool = (_terrain_check_counter % dynamic_terrain_interval) == 0

	# Update smoothed ground height and AGL every frame (cheap — uses cached terrain node)
	var gh: float = _get_ground_height_at_position(aircraft.global_position)
	if not is_nan(gh):
		if is_nan(_smoothed_ground_height):
			_smoothed_ground_height = gh
		else:
			_smoothed_ground_height = lerp(_smoothed_ground_height, gh, 0.05)

	# Update altitude above ground
	_update_agl()

	# Terrain-ahead and fan checks are expensive (many noise evals) — throttle to ~20 Hz
	if run_terrain_checks:
		_check_terrain_ahead()
		_evaluate_terrain_fan()

	# Scan for enemies and friendlies within sensor range
	_scan_contacts()

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
		setup_altitude_m = maxf(setup_altitude_m, target_pos.y + bomb_run_setup_altitude_offset_m)
		if not is_nan(terrain_max):
			setup_altitude_m = maxf(setup_altitude_m, terrain_max + bomb_run_setup_altitude_offset_m)
	else:
		setup_altitude_m = maxf(setup_altitude_m, target_pos.y + attack_run_altitude_offset_m)
		if not is_nan(terrain_max):
			setup_altitude_m = maxf(setup_altitude_m, terrain_max + attack_run_altitude_offset_m)
	return setup_altitude_m

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
	var hostile_groups: Array[String] = ["enemies", "ai_aircraft", "ground_vehicles"]
	var friendly_groups: Array[String] = ["friendlies", "aircraft", "ai_aircraft", "carrier", "ground_vehicles"]
	if my_team != 1:
		hostile_groups = ["friendlies", "aircraft", "ai_aircraft", "carrier", "ground_vehicles"]
		friendly_groups = ["enemies", "ai_aircraft", "ground_vehicles"]

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
		var distance: float = aircraft.global_position.distance_to(enemy_node.global_position)
		if distance <= sensor_range and not known_enemies.has(enemy_node):
			known_enemies.append(enemy_node)

	# Scan cached friendly nodes
	for node in cached_friendly_nodes:
		if not is_instance_valid(node) or not (node is Node3D) or node == aircraft:
			continue
		if node.has_method("get_team") and int(node.get_team()) != my_team:
			continue
		var friendly_node := node as Node3D
		var distance: float = aircraft.global_position.distance_to(friendly_node.global_position)
		if distance <= sensor_range and not known_friendlies.has(friendly_node):
			known_friendlies.append(friendly_node)

func _check_rtb_triggers():
	"""Monitor health and fuel, trigger RTB if critical"""
	if current_state in [State.RTB, State.APPROACH, State.LANDING, State.MISSED_APPROACH]:
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

	var half: float = 1000.0  # half-side → 2 km sides
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
	if debug_enabled and verbose_debug_enabled:
		print("[AIPilot] State change: ", State.keys()[current_state], " -> ", State.keys()[new_state])
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
	elif new_state == State.DOGFIGHT:
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

func set_target(target: Node3D):
	"""Set combat target and engage"""
	combat_target = target
	if target and _is_enemy_aircraft_target(target):
		change_state(State.DOGFIGHT)
	elif target and _is_valid_ground_attack_target(target) and ground_attack_enabled:
		_setup_attack_run_waypoint()
		change_state(State.ATTACK_POSITIONING)
	else:
		change_state(State.ENGAGE)

func _get_surface_target_position(target: Node3D) -> Vector3:
	if not target or not is_instance_valid(target):
		return aircraft.global_position
	var collision_shape: CollisionShape3D = _find_target_collision_shape(target)
	if collision_shape and is_instance_valid(collision_shape):
		return collision_shape.global_position + collision_shape.global_basis.y.normalized() * _get_shape_vertical_half_extent(collision_shape) * 0.35
	var body_node: Node3D = target.get_node_or_null("Body") as Node3D
	if body_node and is_instance_valid(body_node):
		return body_node.global_position + body_node.global_basis.y.normalized() * 1.2
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
		return (shape as BoxShape3D).size.y * 0.5
	if shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape as CapsuleShape3D
		return capsule.height * 0.5 + capsule.radius
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).height * 0.5
	return 1.2

func set_target_altitude(meters: float) -> void:
	"""Set the AI's immediate altitude target. If patrolling, also update patrol altitude."""
	target_altitude = meters
	patrol_altitude_m = meters
	# Update existing patrol waypoints to the new altitude
	for i in range(waypoints.size()):
		var wp: Vector3 = waypoints[i]
		wp.y = patrol_altitude_m
		waypoints[i] = wp
	if debug_enabled and verbose_debug_enabled:
		print("[AIPilot] Target altitude set to ", meters, "m (patrol altitude updated)")

func set_patrol_altitude(meters: float) -> void:
	"""Set patrol altitude and refresh patrol waypoints' altitude."""
	patrol_altitude_m = meters
	target_altitude = meters
	for i in range(waypoints.size()):
		var wp2: Vector3 = waypoints[i]
		wp2.y = patrol_altitude_m
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
	change_state(State.RTB)

func _request_carrier_recovery() -> void:
	"""After arrest, ask FlightDeckManager to move aircraft to hangar."""
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm and fdm.has_method("start_post_arrest_recovery"):
		fdm.start_post_arrest_recovery(aircraft)
	else:
		# Fallback: just keep parking brake so it sits still
		if is_instance_valid(aircraft):
			aircraft.set_meta("parking_brake", true)

func _should_wave_off_for_busy_deck(horiz_dist: float) -> bool:
	if horiz_dist > landing_waveoff_check_distance_m:
		return false
	var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if not fdm or not fdm.has_method("can_accept_landing"):
		return false
	return not bool(fdm.can_accept_landing(aircraft))

func start_landing() -> bool:
	"""Command the AI to begin the carrier landing approach sequence.
	Returns false if approach_1/2/3 waypoint nodes cannot be found in the scene."""
	if not _find_approach_waypoints():
		return false
	_find_takeoff_waypoint()
	_landing_phase = 0
	_committed_turn_sign = 0.0
	target_speed = 80.0
	if debug_enabled:
		print("[AIPilot] Landing approach initiated -> approach_0=", _approach_wp[0].global_position)
	change_state(State.APPROACH)
	return true

func _find_approach_waypoints() -> bool:
	"""Search the current scene for nodes named approach_0 through approach_4."""
	var root: Node = get_tree().current_scene
	if not root:
		return false
	var wp0: Node3D = root.find_child("approach_0", true, false) as Node3D
	var wp1: Node3D = root.find_child("approach_1", true, false) as Node3D
	var wp2: Node3D = root.find_child("approach_2", true, false) as Node3D
	var wp3: Node3D = root.find_child("approach_3", true, false) as Node3D
	var wp4: Node3D = root.find_child("approach_4", true, false) as Node3D
	if wp0 and wp1 and wp2 and wp3 and wp4:
		_approach_wp = [wp0, wp1, wp2, wp3, wp4]
		return true
	push_warning("[AIPilot] start_landing: could not find approach_0/1/2/3/4 nodes in scene")
	return false

func _find_takeoff_waypoint() -> bool:
	var root: Node = get_tree().current_scene
	if not root:
		_takeoff_wp = null
		return false
	_takeoff_wp = root.find_child("takeoff_0", true, false) as Node3D
	return is_instance_valid(_takeoff_wp)

func _should_start_missed_approach() -> bool:
	if _approach_wp.size() < 5 or not is_instance_valid(_approach_wp[3]) or not is_instance_valid(_approach_wp[4]):
		return false
	var wp3: Node3D = _approach_wp[3] as Node3D
	var wp4: Node3D = _approach_wp[4] as Node3D
	var final_dir_flat := Vector3(
		wp4.global_position.x - wp3.global_position.x,
		0.0,
		wp4.global_position.z - wp3.global_position.z
	)
	if final_dir_flat.length_squared() < 1.0:
		return false
	final_dir_flat = final_dir_flat.normalized()
	var past_target_m: float = Vector3(
		aircraft.global_position.x - wp4.global_position.x,
		0.0,
		aircraft.global_position.z - wp4.global_position.z
	).dot(final_dir_flat)
	return past_target_m >= landing_bolter_past_target_m

func _begin_missed_approach() -> void:
	if not is_instance_valid(_takeoff_wp) and not _find_takeoff_waypoint():
		push_warning("[AIPilot] Missed approach: could not find takeoff_0")
		change_state(State.RTB)
		return
	if debug_enabled:
		print("[AIPilot] Missed approach: bolter detected, climbing to takeoff_0")
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
	if debug_enabled:
		print("[AIPilot] Landing gear, tailhook, and flaps deployed")

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
	if debug_enabled and verbose_debug_enabled:
		print("[AIPilot] Retracting landing gear, tailhook, and flaps")
