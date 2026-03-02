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
	ENGAGE,         # Attacking target (legacy/air combat)
	RTB,            # Returning to base
	APPROACH,       # Carrier approach pattern
	LANDING         # Final approach and landing
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

# Saved SimpleAero values for restoration when AI is disabled
var _saved_stability_strength: float = -1.0
var _saved_auto_rudder_strength: float = -1.0

# ============================================================================
# SENSORS - AI's limited view of the world
# ============================================================================
var altitude_agl: float = 0.0  # Altitude above ground level
var terrain_ahead_distance: float = INF  # Distance to terrain in flight path
var known_enemies: Array[Node3D] = []  # Enemies in sensor range
var known_friendlies: Array[Node3D] = []  # Friendly aircraft in sensor range
var _terrain_node: Node = null

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

# Two-layer waypoint system
var nav_waypoint: Vector3 = Vector3.ZERO  # High-level navigation goal
var maneuver_waypoint: Vector3 = Vector3.ZERO  # Short-term maneuvering target
@export var maneuver_lookahead_distance: float = 800.0  # How far ahead to place maneuver waypoint

# Ground attack parameters
@export var attack_run_distance_m: float = 800.0   # Waypoint ~800m in front of target
@export var attack_run_altitude_offset_m: float = 300.0  # Waypoint 300m above target
@export var bomb_run_setup_distance_m: float = 1400.0  # Bomb run setup distance from target
@export var bomb_run_setup_altitude_offset_m: float = 500.0  # Bomb run setup altitude above target
@export var bomb_dive_start_distance_m: float = 800.0  # Start bomb dive at this HORIZONTAL range
@export var attack_pull_up_distance_m: float = 150.0  # Break off when this close to target (gun runs)
@export var bomb_pull_up_distance_m: float = 250.0   # Break off distance for bomb runs
@export var bomb_dive_aim_height_m: float = 80.0     # Aim this many metres above the target during bomb dive
@export var bomb_release_altitude_window_m: float = 300.0  # Start dropping when within this altitude above target (5–300m); drop until 3, then pull up
@export var attack_break_off_distance_m: float = 700.0  # Must fly this far from target before lining up new run
@export var attack_aim_lead_time_s: float = 0.25  # Small lead for moving targets during dive
@export var bomb_release_spacing_s: float = 0.11  # Time spacing between bombs (slightly above bomb fire_cooldown)
var ground_attack_enabled: bool = false  # Toggle with O key: true=attack mode, false=patrol only
var _run_weapon_type: String = "Autocannon"
var _bombs_to_drop_this_run: int = 0
var _bombs_dropped_this_run: int = 0
var _last_bomb_drop_time_s: float = -INF
var _bomb_run_altitude_m: float = 0.0
var _attack_recovery_until_s: float = 0.0  # After emergency, hold egress before next run
var _dive_precise_aim: bool = false  # When true, use tighter bank for steadier final approach
var _dive_entry_time_s: float = -INF  # When we entered ATTACK_DIVE (for soft dive entry)

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
@export var skill_level: float = 1.0  # 0-1, affects reaction time and precision
@export var aggressiveness: float = 0.7  # 0-1, affects combat decisions
@export var rtb_health_threshold: float = 0.5  # Return to base below this health %
@export var debug_enabled: bool = true
@export var verbose_debug_enabled: bool = false  # Extra non-attack telemetry spam

# Flight limits
@export var max_pitch_angle: float = deg_to_rad(30.0)  # Maximum pitch up/down
@export var max_roll_angle: float = deg_to_rad(30.0)   # Maximum roll left/right

# Navigation
var waypoint_threshold: float = 50.0  # Distance to consider waypoint reached
var _committed_turn_sign: float = 0.0  # Locks turn direction when target is behind
var waypoints: Array[Vector3] = []
var current_waypoint_index: int = 0
var carrier_position: Vector3 = Vector3.ZERO  # Home carrier position

# Launch safety
var launch_position: Vector3 = Vector3.ZERO
var deck_clearance_distance: float = 300.0  # Distance from launch point to start climbing

# Waypoint marker (visual)
var _waypoint_marker: MeshInstance3D = null

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

var _smoothed_roll_input: float = 0.0
var _smoothed_pitch_input: float = 0.0
var _smoothed_yaw_input: float = 0.0

func _ready():
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

	set_physics_process(false)  # Don't start until initialized

func initialize(aircraft_node: RigidBody3D):
	"""Setup AI pilot with aircraft reference"""
	aircraft = aircraft_node

	# Add to friendlies group so other AI can detect us
	if not aircraft.is_in_group("friendlies"):
		aircraft.add_to_group("friendlies")

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
		if "stability_strength" in simple_aero:
			_saved_stability_strength = simple_aero.stability_strength
			simple_aero.stability_strength = 0.0
		if "auto_rudder_strength" in simple_aero:
			_saved_auto_rudder_strength = simple_aero.auto_rudder_strength
			simple_aero.auto_rudder_strength = 0.0
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
		if debug_enabled and verbose_debug_enabled:
			print("[AIPilot] Restored stability and auto_rudder for player control")
	if _waypoint_marker and is_instance_valid(_waypoint_marker):
		_waypoint_marker.queue_free()
		_waypoint_marker = null
	set_physics_process(false)

func _physics_process(delta: float):
	if not aircraft or not is_instance_valid(aircraft):
		if _waypoint_marker and is_instance_valid(_waypoint_marker):
			_waypoint_marker.queue_free()
			_waypoint_marker = null
		return

	# Update sensors - AI's view of the world
	_update_sensors()

	# Update health monitoring
	_check_health()

	# State machine
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
		State.ENGAGE:
			_state_engage(delta)
		State.RTB:
			_state_rtb(delta)
		State.APPROACH:
			_state_approach(delta)
		State.LANDING:
			_state_landing(delta)

	# Periodic telemetry (~2 per second at 60fps)
	if debug_enabled and Engine.get_process_frames() % 30 == 0:
		var spd: float = aircraft.linear_velocity.length()
		var alt: float = aircraft.global_position.y
		var vs: float = aircraft.linear_velocity.y
		var pitch_deg: float = rad_to_deg(asin(clamp(-aircraft.global_transform.basis.y.z, -1.0, 1.0)))
		var h_spd: float = Vector2(aircraft.linear_velocity.x, aircraft.linear_velocity.z).length()
		var fpa_deg: float = rad_to_deg(atan2(-aircraft.linear_velocity.y, max(h_spd, 1.0)))
		var state_name: String = State.keys()[current_state]
		var pos: Vector3 = aircraft.global_position
		print("[AIPilot TEL] state=", state_name, "  pos=(", snapped(pos.x, 1), ",", snapped(pos.y, 1), ",", snapped(pos.z, 1), ")  alt=", snapped(alt, 1), "  AGL=", snapped(altitude_agl, 1), "  spd=", snapped(spd, 1), "m/s  VS=", snapped(vs, 1), "  pitch=", snapped(pitch_deg, 0.1), "°  fpa=", snapped(fpa_deg, 0.1), "°")

	# Emergency terrain avoidance - overrides normal behavior
	_check_emergency_terrain_avoidance()

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
	# Maintain level flight during launch - don't pull up yet!
	pitch_input = 0.0
	roll_input = 0.0
	yaw_input = 0.0
	throttle_input = 1.0  # Full throttle

	# Check if airborne AND clear of deck
	if _is_airborne():
		var distance_from_launch = aircraft.global_position.distance_to(launch_position)
		if distance_from_launch > deck_clearance_distance:
			if debug_enabled and verbose_debug_enabled:
				print("[AIPilot] Clear of deck (", distance_from_launch, "m), starting climb")
			# Set target heading to current heading - climb straight!
			var current_heading = atan2(aircraft.global_transform.basis.z.x, aircraft.global_transform.basis.z.z)
			target_heading = current_heading
			change_state(State.CLIMBING)
		elif debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 60 == 0:
			print("[AIPilot LAUNCH] Airborne but maintaining level flight. Distance from launch: ", distance_from_launch, "m")

func _state_climbing(delta: float):
	"""Climb to cruise altitude after launch"""
	target_speed = 85.0  # Climb speed
	target_altitude = patrol_altitude_m  # Initial patrol altitude

	# Maintain runway heading initially
	# target_heading set before state change

	# Retract gear once airborne
	if _is_airborne() and control_gear:
		if control_gear.get("gear_down_state") == true:
			control_gear.send_to_landing_gears("stow")
			control_gear.send_to_tailhooks("stow")
			control_gear.send_to_tailhook_simple(false)
			control_gear._set_collider_disabled(true)
			control_gear.gear_down_state = false
			if debug_enabled and verbose_debug_enabled:
				print("[AIPilot] Retracting landing gear and tailhook")

	# Set navigation waypoint: straight ahead at target altitude
	var forward = aircraft.global_transform.basis.z
	nav_waypoint = aircraft.global_position + forward * 1000.0
	nav_waypoint.y = target_altitude
	
	# Update maneuvering waypoint to lead toward navigation waypoint
	_update_maneuver_waypoint()
	
	# Navigate using maneuvering waypoint
	_navigate_to_waypoint(delta)

	# Ensure maximum power during climb until near target altitude
	if aircraft.global_position.y < target_altitude - 50.0:
		throttle_input = 1.0

	# Extra roll limit during climb to prevent rolling over
	roll_input = clamp(roll_input, -0.3, 0.3)

	# Debug output
	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 60 == 0:
		print("[AIPilot CLIMB] Alt: ", aircraft.global_position.y, " AGL: ", altitude_agl,
			  " Terrain ahead: ", terrain_ahead_distance,
			  " Speed: ", aircraft.linear_velocity.length())

	# Check if reached cruise altitude (close to navigation waypoint)
	if aircraft.global_position.distance_to(nav_waypoint) < 200.0:
		if waypoints.size() > 0:
			change_state(State.TRANSIT)
		else:
			change_state(State.SEARCH)

func _state_transit(delta: float):
	"""Flying to specific waypoints (mission waypoints, not patrol)"""
	# This state is for flying to specific mission waypoints
	# Once all mission waypoints are complete, switch to patrol
	change_state(State.SEARCH)

func _state_search(delta: float):
	"""Looking for targets - fly rectangular patrol pattern around carrier"""
	# Keep patrol altitude via public API to ensure waypoint Y syncs
	if target_altitude != patrol_altitude_m:
		set_patrol_altitude(patrol_altitude_m)
	# Speed policy for patrol
	target_speed = 80.0

	# Ensure we have a valid patrol center
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
		if distance_to_waypoint < 100.0:
			# Move to next waypoint
			current_waypoint_index += 1
			if current_waypoint_index >= waypoints.size():
				current_waypoint_index = 0

			if debug_enabled and verbose_debug_enabled:
				print("[AIPilot SEARCH] Reached waypoint ", current_waypoint_index, "/", waypoints.size())

	# Look for ground attack target (EnemyBox) only when in attack mode
	if ground_attack_enabled:
		var ground_target = _find_ground_attack_target()
		if ground_target:
			combat_target = ground_target
			_setup_attack_run_waypoint()
			change_state(State.ATTACK_POSITIONING)
			if debug_enabled:
				var d := aircraft.global_position.distance_to(combat_target.global_position)
				print("[AIPilot ATTACK] Target acquired: ", combat_target.name, "  dist=", snapped(d, 1.0), "m  pos=", combat_target.global_position)
				print("[AIPilot ATTACK] Starting attack run -> ATTACK_POSITIONING")

	# Debug
	if debug_enabled and verbose_debug_enabled and Engine.get_process_frames() % 60 == 0:
		var dist_to_wp = aircraft.global_position.distance_to(nav_waypoint) if waypoints.size() > 0 else 0
		print("[AIPilot SEARCH] WP %d/%d  dist=%.0fm  nav=(%.0f,%.0f,%.0f)" % [current_waypoint_index, waypoints.size(), dist_to_wp, nav_waypoint.x, nav_waypoint.y, nav_waypoint.z])

func _find_ground_attack_target() -> Node3D:
	"""Find nearest EnemyBox (ground target) within sensor range. Excludes same-team."""
	var my_team: int = aircraft.get_team() if aircraft.has_method("get_team") else 1
	var nearest: Node3D = null
	var nearest_dist: float = INF
	for enemy in known_enemies:
		if not is_instance_valid(enemy):
			continue
		if not (enemy is EnemyBox):
			continue
		if enemy.has_method("get_team") and enemy.get_team() == my_team:
			continue
		var d: float = aircraft.global_position.distance_to(enemy.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = enemy
	return nearest

func _setup_attack_run_waypoint():
	"""Set nav_waypoint to attack run start: ~800m in front of target, 300m above it."""
	if not combat_target or not is_instance_valid(combat_target):
		return
	_plan_attack_run_weapon()
	var target_pos: Vector3 = combat_target.global_position
	var to_target: Vector3 = target_pos - aircraft.global_position
	to_target.y = 0.0
	var horiz_dir: Vector3 = to_target.normalized() if to_target.length() > 1.0 else aircraft.global_transform.basis.z
	var setup_dist: float = bomb_run_setup_distance_m if _run_weapon_type == "Bomb" else attack_run_distance_m
	nav_waypoint = target_pos - horiz_dir * setup_dist
	if _run_weapon_type == "Bomb":
		# Survey the highest terrain between setup point and target to guarantee adequate clearance.
		var terrain_max: float = _sample_max_terrain_height_along_path(nav_waypoint, target_pos, 8)
		var base_alt: float = target_pos.y + bomb_run_setup_altitude_offset_m
		if not is_nan(terrain_max):
			base_alt = max(base_alt, terrain_max + bomb_run_setup_altitude_offset_m)
		_bomb_run_altitude_m = base_alt
		nav_waypoint.y = _bomb_run_altitude_m
	else:
		nav_waypoint.y = target_pos.y + attack_run_altitude_offset_m
	maneuver_waypoint = nav_waypoint
	if debug_enabled:
		print("[AIPilot ATTACK] Run setup waypoint: ", nav_waypoint, "  target=", target_pos, "  weapon=", _run_weapon_type, "  bombs=", _bombs_to_drop_this_run)

func _state_attack_positioning(delta: float):
	"""Fly to attack run setup waypoint (800m offset; altitude depends on weapon plan)."""
	if not ground_attack_enabled:
		change_state(State.SEARCH)
		return
	if not combat_target or not is_instance_valid(combat_target):
		change_state(State.SEARCH)
		return

	# Don't attempt attack maneuvers at dangerously low speed — build energy first
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
	var to_tgt: Vector3 = combat_target.global_position - aircraft.global_position
	to_tgt.y = 0.0
	var dir: Vector3 = to_tgt.normalized() if to_tgt.length() > 1.0 else aircraft.global_transform.basis.z
	var setup_dist: float = bomb_run_setup_distance_m if _run_weapon_type == "Bomb" else attack_run_distance_m
	nav_waypoint = combat_target.global_position - dir * setup_dist
	if _run_weapon_type == "Bomb":
		_bomb_run_altitude_m = combat_target.global_position.y + bomb_run_setup_altitude_offset_m
		nav_waypoint.y = _bomb_run_altitude_m
	else:
		nav_waypoint.y = combat_target.global_position.y + attack_run_altitude_offset_m

	# Never let the positioning waypoint sit lower than our current altitude minus a gentle
	# descent allowance. This prevents the plane from descending steeply through hilly terrain
	# just to reach the ideal setup altitude. It will level off and approach the altitude
	# gradually rather than punching into the terrain beneath it.
	var ground_h: float = _get_ground_height_at_position(aircraft.global_position)
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
	if not ground_attack_enabled:
		change_state(State.SEARCH)
		return
	if not combat_target or not is_instance_valid(combat_target):
		change_state(State.SEARCH)
		return
	var target_pos: Vector3 = combat_target.global_position
	var to_target: Vector3 = target_pos - aircraft.global_position
	var horiz_dist_to_target: float = Vector2(to_target.x, to_target.z).length()
	target_speed = 105.0

	# Fly straight at the target, clamped above the highest terrain between us and
	# the target so we don't fly into hills during the approach.
	var inbound_alt: float = _bomb_run_altitude_m
	var ground_h: float = _get_ground_height_at_position(aircraft.global_position)
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
		# Abort: we're way too close and still too low — can't set up a proper dive
		change_state(State.ATTACK_BREAK_OFF)
		_committed_turn_sign = 0.0
		if debug_enabled:
			print("[AIPilot ATTACK] Inbound abort: too close (", snapped(horiz_dist_to_target, 1.0), "m) and too low for dive, breaking off")

func _state_attack_dive(delta: float):
	"""Dive at target, fire guns, break off at 100m to line up new run."""
	if not ground_attack_enabled:
		change_state(State.SEARCH)
		return
	if not combat_target or not is_instance_valid(combat_target):
		change_state(State.SEARCH)
		return

	var target_pos: Vector3 = combat_target.global_position
	var dist_to_target: float = aircraft.global_position.distance_to(target_pos)

	# Bomb runs need a much larger break-off margin — they dive from high altitude and need room to recover.
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
	# For bomb runs aim above the target, but raise the aim point dynamically if there
	# is high terrain between us and the target so we don't dive into a hillside.
	var aim_height: float = 1.5
	if _run_weapon_type == "Bomb":
		aim_height = bomb_dive_aim_height_m
		var highest_terrain: float = _sample_max_terrain_height_along_path(aircraft.global_position, target_pos, 6)
		if not is_nan(highest_terrain):
			var min_aim_y: float = highest_terrain + 80.0
			aim_height = max(aim_height, min_aim_y - target_pos.y)
	var aim_pos: Vector3 = target_pos + Vector3(0.0, aim_height, 0.0)
	if "linear_velocity" in combat_target:
		aim_pos += combat_target.linear_velocity * attack_aim_lead_time_s

	# Bomb runs: refine aim using predicted impact — steer to put the bullseye on target
	var horiz_dist: float = Vector2(aircraft.global_position.x - target_pos.x, aircraft.global_position.z - target_pos.z).length()
	var alt_above: float = aircraft.global_position.y - target_pos.y
	if _run_weapon_type == "Bomb":
		var impact: Vector3 = _predict_bomb_impact_point()
		if impact != Vector3.ZERO:
			var err_h: Vector3 = Vector3(target_pos.x - impact.x, 0.0, target_pos.z - impact.z)
			var correction_strength: float = clamp(0.6 + 0.6 * (1.0 - horiz_dist / 500.0), 0.6, 1.2)
			aim_pos += err_h * correction_strength
		# In release window: aim closer to target and use precise steering
		# Smooth transition 600→400m to avoid abrupt aim-height jump that causes pitch oscillation
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
		_handle_bomb_release_run(aim_pos, target_pos)
	else:
		# Fire guns only when precisely aimed (within ~5° cone)
		var fwd: Vector3 = aircraft.global_transform.basis.z
		var to_tgt: Vector3 = (aim_pos - aircraft.global_position).normalized()
		var dot: float = fwd.dot(to_tgt)
		if dot > cos(deg_to_rad(5.0)):  # ~5° cone - fire only when precisely aimed
			_fire_guns()
		else:
			_stop_firing()

	target_speed = 120.0  # Faster during attack run

func _state_attack_break_off(delta: float):
	"""Fly away from target until far enough, then return to SEARCH to set up new run."""
	if not ground_attack_enabled:
		change_state(State.SEARCH)
		return
	if not combat_target or not is_instance_valid(combat_target):
		change_state(State.SEARCH)
		return

	var target_pos: Vector3 = combat_target.global_position
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
	nav_waypoint.y = aircraft.global_position.y + 150.0  # Climb while egressing
	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)

	target_speed = 100.0

func _fire_guns():
	"""Trigger weapon fire via ControlWeapons."""
	if not control_weapons:
		return
	if control_weapons.has_method("fire_automatic_weapons_of_type"):
		var weapon_type: String = control_weapons.selected_weapon_type if "selected_weapon_type" in control_weapons else ""
		if weapon_type.is_empty() and "weapon_types" in control_weapons and control_weapons.weapon_types.size() > 0:
			weapon_type = control_weapons.weapon_types[0]
		if not weapon_type.is_empty():
			control_weapons.fire_automatic_weapons_of_type(weapon_type)
	elif control_weapons.has_method("fire_selected_weapon_type"):
		control_weapons.fire_selected_weapon_type()

func _plan_attack_run_weapon() -> void:
	"""Choose one weapon profile for this run. Prefer bombs when available."""
	_run_weapon_type = "Autocannon"
	_bombs_to_drop_this_run = 0
	_bombs_dropped_this_run = 0
	_last_bomb_drop_time_s = -INF
	if not control_weapons:
		return

	var bomb_ready: int = _count_ready_bombs()
	if bomb_ready > 0:
		_run_weapon_type = "Bomb"
		var total_ammo: int = _get_total_bomb_ammo()
		_bombs_to_drop_this_run = min(3, total_ammo)  # Drop 3 per run, then pull up
	else:
		_run_weapon_type = _choose_non_bomb_weapon_type()

	if "selected_weapon_type" in control_weapons:
		control_weapons.selected_weapon_type = _run_weapon_type

func _choose_non_bomb_weapon_type() -> String:
	if not control_weapons or not ("weapon_types" in control_weapons):
		return "Autocannon"
	var types: Array = control_weapons.weapon_types
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
	if not control_weapons or not ("hardpoints" in control_weapons):
		return 0
	for hp in control_weapons.hardpoints:
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
	if not control_weapons or not ("hardpoints" in control_weapons):
		return 0
	for hp in control_weapons.hardpoints:
		if not hp or not hp.weapon_instance:
			continue
		if hp.weapon_instance.weapon_name != "Bomb":
			continue
		if "ammo_count" in hp.weapon_instance:
			total += int(hp.weapon_instance.ammo_count)
	return total

func _handle_bomb_release_run(aim_pos: Vector3, target_pos: Vector3) -> void:
	if _bombs_to_drop_this_run <= 0:
		return
	if _bombs_dropped_this_run >= _bombs_to_drop_this_run:
		return
	var now_s: float = Time.get_ticks_msec() / 1000.0
	if now_s - _last_bomb_drop_time_s < bomb_release_spacing_s:
		return

	var alt_above_target: float = aircraft.global_position.y - target_pos.y
	# Start dropping when within altitude window (5–300m above target); keep dropping until 3
	if alt_above_target > bomb_release_altitude_window_m or alt_above_target < 5.0:
		return
	# Must be descending (not level or climbing)
	var horiz_speed: float = Vector2(aircraft.linear_velocity.x, aircraft.linear_velocity.z).length()
	var fpa_deg: float = rad_to_deg(atan2(-aircraft.linear_velocity.y, max(horiz_speed, 1.0)))
	if fpa_deg < 1.0:
		return

	if _drop_one_bomb():
		_bombs_dropped_this_run += 1
		_last_bomb_drop_time_s = now_s
		if debug_enabled:
			var hdist: float = Vector2(aircraft.global_position.x - target_pos.x, aircraft.global_position.z - target_pos.z).length()
			print("[AIPilot ATTACK] Bomb release ", _bombs_dropped_this_run, "/", _bombs_to_drop_this_run, " alt_above=", snapped(alt_above_target, 1.0), "m hdist=", snapped(hdist, 1.0), "m")

func _drop_one_bomb() -> bool:
	if not control_weapons or not ("hardpoints" in control_weapons):
		return false
	for hp in control_weapons.hardpoints:
		if not hp or not hp.weapon_instance:
			continue
		if hp.weapon_instance.weapon_name != "Bomb":
			continue
		if hp.weapon_instance.can_fire() and hp.fire():
			return true
	return false

func _predict_bomb_impact_point() -> Vector3:
	"""Estimate bomb impact by stepping ballistic trajectory matching CCIP physics."""
	var start_pos: Vector3 = aircraft.global_position
	var drop_force: float = 0.0
	var bomb_projectile_scene: PackedScene = null

	if control_weapons and ("hardpoints" in control_weapons):
		for hp in control_weapons.hardpoints:
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
	if bomb_projectile_scene:
		var bomb_instance = bomb_projectile_scene.instantiate()
		if "linear_damp" in bomb_instance:
			linear_damp = float(bomb_instance.linear_damp)
			if linear_damp < 0.0:
				linear_damp = float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.0))
		if "gravity_scale" in bomb_instance:
			gravity_scale = float(bomb_instance.gravity_scale)
		bomb_instance.queue_free()

	var gravity_dir: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3(0, -1, 0))
	var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gravity_vec: Vector3 = gravity_dir * gravity_mag

	var time_step: float = 0.02
	var max_time: float = 25.0
	var current_pos: Vector3 = start_pos
	var space_state: PhysicsDirectSpaceState3D = aircraft.get_world_3d().direct_space_state

	for step in int(max_time / time_step):
		current_vel += gravity_vec * gravity_scale * time_step
		if linear_damp > 0.0:
			current_vel /= (1.0 + linear_damp * time_step)
		var next_pos: Vector3 = current_pos + current_vel * time_step

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
		query.exclude = [aircraft]
		query.collision_mask = 0xFFFFFFFF
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit and hit.has("position"):
			return hit.position

		if next_pos.y < -1000.0:
			return Vector3.ZERO
		current_pos = next_pos
	return Vector3.ZERO

func _stop_firing():
	"""Stop weapon fire - ControlWeapons uses is_trigger_held which we don't set."""
	# ControlWeapons fires when is_trigger_held; we call fire_automatic each frame when we want to fire
	# So we simply don't call it when we don't want to fire - no explicit stop needed
	pass

func _state_engage(delta: float):
	"""Attacking target"""
	if not combat_target or not is_instance_valid(combat_target):
		combat_target = null
		change_state(State.SEARCH)
		return

	# Simple attack: fly toward target
	nav_waypoint = combat_target.global_position
	_update_maneuver_waypoint()
	_navigate_to_waypoint(delta)

	# TODO: Implement proper attack patterns, weapon firing, etc.

func _state_rtb(delta: float):
	"""Returning to base"""
	# TODO: Fly to carrier
	# For now, just maintain altitude and heading
	_navigate_to_altitude_and_speed(delta)

func _state_approach(delta: float):
	"""Carrier approach pattern"""
	# TODO: Implement carrier landing pattern
	pass

func _state_landing(delta: float):
	"""Final approach and landing"""
	# TODO: Implement precise landing control
	pass

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
	var is_upright: bool = aircraft_up_y > 0.3
	
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
	var in_dive_or_attack: bool = current_state in [State.ATTACK_DIVE]
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
	var bank_limit_deg: float
	if current_state != State.ATTACK_DIVE:
		_dive_precise_aim = false
	if _dive_precise_aim:
		bank_limit_deg = 35.0  # Tighter bank for steadier final approach
	elif current_state in [State.ATTACK_POSITIONING, State.ATTACK_DIVE, State.ATTACK_BREAK_OFF]:
		bank_limit_deg = attack_bank_cmd_limit_deg
	else:
		bank_limit_deg = bank_cmd_limit_deg
	
	# === ROLL: project HORIZONTAL direction to target into local frame ===
	# By zeroing Y we prevent altitude differences from affecting the bank command.
	var horiz_to_target: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	var local_horiz_x: float = horiz_to_target.dot(b.x)
	var local_horiz_z: float = horiz_to_target.dot(b.z)
	var horiz_len: float = sqrt(local_horiz_x * local_horiz_x + local_horiz_z * local_horiz_z)
	
	var desired_bank: float = 0.0
	if horiz_len > 1.0:
		var lateral_ratio: float = local_horiz_x / horiz_len
		var horiz_dir_z: float = local_horiz_z / horiz_len
		
		# Bearing error: positive = turn right, negative = turn left (for when target is directly behind)
		var heading_rad: float = atan2(aircraft.global_transform.basis.z.x, aircraft.global_transform.basis.z.z)
		var bearing_to_wp_rad: float = atan2(horiz_to_target.x, horiz_to_target.z)
		var bearing_err_rad: float = _normalize_angle(bearing_to_wp_rad - heading_rad)
		
		# Positive current_roll = right bank (empirically verified).
		# Target right (positive lateral_ratio) → right bank (positive desired_bank).
		if horiz_dir_z < -0.5:
			# Target behind: commit to a turn direction.
			# When target is directly behind (lateral_ratio ~0), bearing_err flips +180/-180 - LOCK direction.
			# When lateral is clear, use it; overshoot check switches when target crosses.
			var turn_toward: float
			if abs(lateral_ratio) > 0.05:
				turn_toward = signf(lateral_ratio)
			else:
				# Directly behind: set once and LOCK - bearing_err wraps at ±180° causing flip
				if _committed_turn_sign == 0.0:
					# First time: use cross product (avoids ±180° wrap). cross>0 = target left = turn left
					var cross: float = aircraft.global_transform.basis.z.x * horiz_to_target.z - aircraft.global_transform.basis.z.z * horiz_to_target.x
					_committed_turn_sign = -1.0 if cross > 0 else 1.0
				turn_toward = _committed_turn_sign
			if _committed_turn_sign == 0.0:
				_committed_turn_sign = turn_toward
			elif abs(lateral_ratio) > 0.05 and signf(_committed_turn_sign) != signf(lateral_ratio):
				# Overshot: target crossed to other side, switch turn direction
				_committed_turn_sign = turn_toward
			desired_bank = _committed_turn_sign * deg_to_rad(bank_limit_deg)
		else:
			if horiz_dir_z > 0.0:
				_committed_turn_sign = 0.0
			if _dive_precise_aim:
				# Use bearing error directly — proportional correction so we steer toward target, not overshoot
				# Gain ~2.2: 5° error → ~12° bank; 15° error → ~35° bank
				desired_bank = clamp(bearing_err_rad * 2.2, -deg_to_rad(bank_limit_deg), deg_to_rad(bank_limit_deg))
			else:
				desired_bank = lateral_ratio * deg_to_rad(bank_limit_deg)
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
	var raw_roll: float = clamp(bank_error * 11.0 - roll_rate * roll_rate_damping, -1.0, 1.0)
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
	var in_attack_climb: bool = current_state in [State.ATTACK_POSITIONING, State.ATTACK_INBOUND] and alt_err > 30.0
	var needs_high_authority: bool = in_dive_state or in_break_off
	var vs_limit: float
	var vs_gain: float
	if needs_high_authority:
		# Soft dive entry: ramp up over 1.2s to avoid initial pull-too-hard oscillation
		var now_s: float = Time.get_ticks_msec() / 1000.0
		var dive_age_s: float = now_s - _dive_entry_time_s if _dive_entry_time_s > -INF else 999.0
		var entry_t: float = clamp(dive_age_s / 1.2, 0.0, 1.0)
		vs_limit = lerp(18.0, 40.0, entry_t)
		vs_gain = lerp(0.12, 0.25, entry_t)
	elif in_attack_climb:
		vs_limit = 25.0
		vs_gain = 0.18
	else:
		vs_limit = 10.0
		vs_gain = 0.12
	var desired_vs: float = clamp(alt_err * vs_gain, -vs_limit, vs_limit)
	if not needs_high_authority and not in_attack_climb and abs(alt_err) < pitch_deadband_m and abs(vel.y) < 2.0:
		desired_vs = 0.0
	# During dive: deadband near aim altitude to prevent pitch hunting/oscillation
	elif in_dive_state and abs(alt_err) < 35.0:
		desired_vs = clamp(alt_err * 0.15, -8.0, 8.0)  # Gentle correction when close
	var vs_err: float = desired_vs - vel.y
	var bank_compensation: float = clamp(1.0 / max(cos(bank_rad), 0.7), 1.0, 1.2)
	var pitch_limit: float = max_pitch_angle / deg_to_rad(60.0)
	var pitch_gain: float = 0.10 if (needs_high_authority or in_attack_climb) else 0.06
	var pitch_rate_damping: float = 0.45 if in_dive_state else 0.28  # Stronger derivative damping in dive to reduce oscillation
	var raw_pitch: float = clamp(vs_err * pitch_gain * bank_compensation - pitch_rate_up * pitch_rate_damping, -pitch_limit, pitch_limit)
	# Min pitch prevents dead zone but can cause overshoot when close — use larger threshold in dive
	var min_pitch_threshold: float = 60.0 if in_dive_state else 40.0
	if abs(alt_err) > min_pitch_threshold:
		var min_pitch: float = (0.10 if (needs_high_authority or in_attack_climb) else 0.04) * sign(alt_err)
		if abs(raw_pitch) < abs(min_pitch):
			raw_pitch = min_pitch
	var effective_pitch_smoothing: float = 0.12 if in_dive_state else pitch_input_smoothing  # Heavier smoothing in dive for steadier aim
	pitch_input = lerp(_smoothed_pitch_input, raw_pitch, effective_pitch_smoothing)
	_smoothed_pitch_input = pitch_input
	
	# === YAW: apply rudder proportional to DESIRED bank to sweep the nose into the turn ===
	var raw_yaw: float = -sin(desired_bank) * lerp(1.0, high_bank_yaw_scale, high_bank_t)
	var yaw_smoothing: float = lerp(input_smoothing, 0.5, high_bank_t)
	yaw_input = lerp(_smoothed_yaw_input, raw_yaw, yaw_smoothing)
	_smoothed_yaw_input = yaw_input
	
	# === THROTTLE ===
	var speed_error: float = target_speed - speed
	throttle_input += clamp(speed_error * 0.01, -0.05, 0.05)
	throttle_input = clamp(throttle_input, 0.4, 1.0)
	throttle_input += clamp(bank_rad / deg_to_rad(30.0), 0.0, 1.0) * 0.15
	throttle_input = clamp(throttle_input, 0.0, 1.0)
	
	# Low speed protection — full throttle, limit pitch-up to avoid bleeding more energy
	if speed < stall_speed_mps + stall_margin_mps:
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
		print("  TARGET: %s  dist=%.0fm  bearing=%.0f°  heading=%.0f°  err=%.0f° (pos=turn R)" % [target_pos, to_target.length(), bearing_to_wp, heading_deg, rad_to_deg(bearing_err)])
		var vel_fwd: float = vel.dot(aircraft.global_transform.basis.z)
		var vel_right: float = vel.dot(aircraft.global_transform.basis.x)
		var turning: String = "RIGHT" if vel_right > 5 else ("LEFT" if vel_right < -5 else "STRAIGHT")
		print("  TURN: %s  desired_bank=%.1f°  current_roll=%.1f°  bank_err=%.1f°  commit=%.0f  flip=%s" % [turn_dir, rad_to_deg(desired_bank), rad_to_deg(current_roll), rad_to_deg(bank_error), _committed_turn_sign, flip_roll_direction])
		print("  ACTUAL: turning=%s (vel_right=%.1f)  vel_fwd=%.1f" % [turning, vel_right, vel_fwd])
		print("  LOCAL: lx=%.2f (right+)  lz=%.2f (ahead+)  lateral_ratio=%.2f" % [lateral_norm, ahead_norm, lateral_norm])
		print("  CMD: roll=%.2f  pitch=%.2f  yaw=%.2f  thr=%.2f" % [roll_input, pitch_input, yaw_input, throttle_input])
		print("  ALT: %.0fm (tgt %.0f)  spd=%.0f  vs=%.1f" % [alt, nav_waypoint.y, speed, vel.y])

func _update_maneuver_waypoint():
	"""Place maneuver waypoint along the direction TO the navigation waypoint"""
	if nav_waypoint == Vector3.ZERO:
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
	mat.albedo_color = Color(0.5, 1.0, 0.0)  # Lime green
	mat.emission_enabled = true
	mat.emission = Color(0.5, 1.0, 0.0)
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
	if current_state not in [State.TRANSIT, State.SEARCH, State.ATTACK_POSITIONING, State.ATTACK_INBOUND, State.ATTACK_DIVE, State.ATTACK_BREAK_OFF, State.ENGAGE]:
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
	var current_pitch = asin(clamp(-aircraft.global_transform.basis.y.z, -1.0, 1.0))
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
		print("[AIPilot TURN] Bank: ", snapped(rad_to_deg(current_roll), 0.1), "° Pitch: ", snapped(rad_to_deg(current_pitch), 0.1),
			  "° Alt: ", snapped(current_alt, 0.1), " VS: ", snapped(vertical_speed, 0.1))

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

func _check_emergency_terrain_avoidance():
	"""Override controls if terrain is dangerously close"""
	var in_attack_phase: bool = current_state in [State.ATTACK_POSITIONING, State.ATTACK_INBOUND, State.ATTACK_DIVE, State.ATTACK_BREAK_OFF]
	# During an actual dive the plane intentionally descends; use less conservative thresholds.
	# During positioning/inbound the plane is just navigating, use slightly relaxed but still safe values.
	var in_dive: bool = current_state == State.ATTACK_DIVE
	var agl_floor: float
	var tti_limit: float
	var terrain_warn: float
	if in_dive:
		agl_floor  = 60.0
		tti_limit  = 1.2
		terrain_warn = 160.0
	elif in_attack_phase:
		agl_floor  = 80.0
		tti_limit  = 1.5
		terrain_warn = 200.0
	else:
		agl_floor  = emergency_min_agl_m
		tti_limit  = emergency_tti_s
		terrain_warn = terrain_warning_distance

	var forward_dir: Vector3 = aircraft.linear_velocity.normalized() if aircraft.linear_velocity.length() > 10.0 else aircraft.global_transform.basis.z
	var forward_speed: float = max(aircraft.linear_velocity.dot(forward_dir), 0.0)
	var tti: float = terrain_ahead_distance / max(forward_speed, 0.1)
	var imminent_impact: bool = terrain_ahead_distance < terrain_warn or (terrain_ahead_distance < INF and tti < tti_limit)
	var descending_low: bool = in_dive and aircraft.linear_velocity.y < -8.0 and altitude_agl < agl_floor + 20.0 and terrain_ahead_distance < terrain_warn * 1.5

	# During positioning/inbound the plane may be at low AGL while climbing to the setup
	# altitude. Don't abort the attack based on AGL alone when the plane is climbing and
	# there's no terrain directly ahead. Only trigger on truly dangerous AGL (<30m) or
	# if terrain ahead is actually a threat.
	var is_climbing_to_altitude: bool = current_state in [State.ATTACK_POSITIONING, State.ATTACK_INBOUND] and aircraft.linear_velocity.y > 0.0
	var low_agl: bool
	if is_climbing_to_altitude:
		low_agl = altitude_agl < 30.0
	else:
		low_agl = altitude_agl < agl_floor

	# Check AGL and predicted collision
	if low_agl or imminent_impact or descending_low:
		pitch_input = 1.0  # Full pull up
		roll_input = 0.0  # Wings level
		yaw_input = 0.0
		throttle_input = 1.0  # Full throttle
		# Slam the smoothed values so navigation doesn't fight the emergency on the next frame
		_smoothed_roll_input = 0.0
		_smoothed_pitch_input = 1.0
		_smoothed_yaw_input = 0.0
		# Force an egress profile out of attack dive if needed
		if current_state in [State.ATTACK_DIVE, State.ATTACK_POSITIONING, State.ATTACK_INBOUND]:
			# Hold off re-attacks briefly so we do not thrash between setup and break-off near terrain.
			_attack_recovery_until_s = max(_attack_recovery_until_s, Time.get_ticks_msec() / 1000.0 + 4.0)
			change_state(State.ATTACK_BREAK_OFF)
		if debug_enabled and Engine.get_process_frames() % 30 == 0:
			print("[AIPilot EMERGENCY] AGL=", snapped(altitude_agl, 0.1), "m  terrain_ahead=", snapped(terrain_ahead_distance, 0.1), "m  tti=", snapped(tti, 0.1), "s  (attack=", in_attack_phase, ") - PULLING UP!")

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

func _is_airborne() -> bool:
	"""Check if aircraft is airborne"""
	# Simple check: altitude > 5m and speed > 30 m/s
	return aircraft.global_position.y > 5.0 and aircraft.linear_velocity.length() > 30.0

func _update_sensors():
	"""Update AI's limited view of the world"""
	# Update altitude above ground
	_update_agl()

	# Check terrain ahead in flight path
	_check_terrain_ahead()

	# Scan for enemies and friendlies within sensor range
	_scan_contacts()

func _update_agl():
	"""Raycast down to find altitude above ground"""
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

	var query = PhysicsRayQueryParameters3D.create(
		aircraft.global_position,
		aircraft.global_position + forward_dir * terrain_ahead_check_distance
	)
	query.exclude = [aircraft]
	# Use all layers so this works with project-specific Terrain3D collision settings.
	query.collision_mask = 0xFFFFFFFF

	var result = space_state.intersect_ray(query)
	if result:
		terrain_ahead_distance = aircraft.global_position.distance_to(result.position)
	else:
		terrain_ahead_distance = INF
		# Fallback for Terrain3D setups where physics raycasts may miss:
		# sample terrain height ahead at a few distances and infer collision risk.
		var probe_distances := [terrain_warning_distance * 0.5, terrain_warning_distance, min(terrain_ahead_check_distance, terrain_warning_distance * 2.0)]
		for d in probe_distances:
			var probe_pos: Vector3 = aircraft.global_position + forward_dir * d
			var h: float = _get_ground_height_at_position(probe_pos)
			if is_nan(h):
				continue
			var clearance: float = probe_pos.y - h
			if clearance < 30.0:
				terrain_ahead_distance = min(terrain_ahead_distance, d)
				break

func _get_cached_terrain_node() -> Node:
	if _terrain_node and is_instance_valid(_terrain_node):
		return _terrain_node
	var root: Node = get_tree().current_scene
	if not root:
		return null
	var queue: Array = [root]
	while queue.size() > 0:
		var cur: Node = queue.pop_front()
		if cur.get_class() == "Terrain3D":
			_terrain_node = cur
			return _terrain_node
		for child in cur.get_children():
			queue.append(child)
	return null

func _get_ground_height_at_position(world_pos: Vector3) -> float:
	var terrain: Node = _get_cached_terrain_node()
	if not terrain:
		return NAN
	if terrain.has_method("get_height"):
		var h = terrain.get_height(world_pos)
		if typeof(h) == TYPE_FLOAT and not is_nan(float(h)):
			return float(h)
	if "data" in terrain and terrain.data and terrain.data.has_method("get_height"):
		var h2 = terrain.data.get_height(world_pos)
		if typeof(h2) == TYPE_FLOAT and not is_nan(float(h2)):
			return float(h2)
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

func _scan_contacts():
	"""Scan for enemies and friendlies within sensor range"""
	known_enemies.clear()
	known_friendlies.clear()

	# Scan for enemies
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy is Node3D and is_instance_valid(enemy):
			var distance = aircraft.global_position.distance_to(enemy.global_position)
			if distance <= sensor_range:
				known_enemies.append(enemy)

	# Scan for friendlies
	var friendlies = get_tree().get_nodes_in_group("friendlies")
	for friendly in friendlies:
		if friendly is Node3D and is_instance_valid(friendly) and friendly != aircraft:
			var distance = aircraft.global_position.distance_to(friendly.global_position)
			if distance <= sensor_range:
				known_friendlies.append(friendly)

func _check_health():
	"""Monitor health and RTB if damaged"""
	if aircraft.has_meta("current_health"):
		current_health = aircraft.get_meta("current_health")
		var health_percent = current_health / max_health

		if health_percent < rtb_health_threshold and current_state not in [State.RTB, State.APPROACH, State.LANDING]:
			if debug_enabled:
				print("[AIPilot] Health low (", health_percent * 100, "%), returning to base")
			change_state(State.RTB)

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
	"""Create figure-eight pattern around carrier"""
	waypoints.clear()
	current_waypoint_index = 0

	var radius: float = figure_eight_radius_m
	var num_points_per_loop: int = 8

	# Left loop: circle centered at (-radius, 0, 0) from carrier
	for i in range(num_points_per_loop):
		var angle: float = (float(i) / float(num_points_per_loop)) * TAU
		var x: float = -radius + cos(angle) * radius
		var z: float = sin(angle) * radius
		waypoints.append(carrier_position + Vector3(x, patrol_altitude_m, z))

	# Right loop: circle centered at (+radius, 0, 0) from carrier
	for i in range(num_points_per_loop):
		var angle: float = (float(i) / float(num_points_per_loop)) * TAU
		var x: float = radius + cos(angle) * radius
		var z: float = -sin(angle) * radius
		waypoints.append(carrier_position + Vector3(x, patrol_altitude_m, z))

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

func change_state(new_state: State):
	"""Change AI state with logging"""
	if debug_enabled and verbose_debug_enabled:
		print("[AIPilot] State change: ", State.keys()[current_state], " -> ", State.keys()[new_state])
	if new_state == State.ATTACK_DIVE:
		_dive_entry_time_s = Time.get_ticks_msec() / 1000.0
	current_state = new_state

# ============================================================================
# PUBLIC API - For external control
# ============================================================================

func set_waypoints(new_waypoints: Array[Vector3]):
	"""Set waypoint list for navigation"""
	waypoints = new_waypoints
	current_waypoint_index = 0

func add_waypoint(waypoint: Vector3):
	"""Add waypoint to list"""
	waypoints.append(waypoint)

func set_target(target: Node3D):
	"""Set combat target and engage"""
	combat_target = target
	change_state(State.ENGAGE)

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
	# Save carrier position for circling
	carrier_position = launch_position
	if debug_enabled and verbose_debug_enabled:
		print("[AIPilot] Launch initiated from position: ", launch_position)
		print("[AIPilot] Carrier position saved: ", carrier_position)
	change_state(State.LAUNCHING)

func return_to_base():
	"""Command to return to carrier"""
	change_state(State.RTB)
