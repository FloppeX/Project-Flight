extends Node
class_name FlightDeckManager

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")

signal deck_state_changed(new_state)

@export var catapult: Node
@export var tractor_bot: Node
@export var elevator_pickup_marker: Node3D
@export var elevator: Node
@export var deck_marker: Node3D  # Marker on deck to derive deck world height
@export var tractor_bots: Array[Node] = []  # Array of SimpleTractorBot nodes
@export var hangar_spawn_points: Array[Vector3] = [
	Vector3(-8, 0, 0),
	Vector3(-4, 0, 0), 
	Vector3(0, 0, 0),
	Vector3(4, 0, 0),
	Vector3(8, 0, 0),
	Vector3(12, 0, 0)
]
@export var max_hangar_capacity: int = 12
@export var aircraft_template_scene: PackedScene  # Default aircraft template (Aircraft 5)
@export var aircraft_1_scene: PackedScene         # Aircraft 1 template
@export var aircraft_2_scene: PackedScene         # Aircraft 2 template
@export var aircraft_7_scene: PackedScene         # Aircraft 7 template
@export var aircraft_8_scene: PackedScene         # Aircraft 8 template
@export var aircraft_9_scene: PackedScene         # Rescue helicopter placeholder template
@export var aircraft_10_scene: PackedScene        # Scout helicopter template
@export var aircraft_11_scene: PackedScene        # Utility helicopter template
@export_range(0, 6, 1) var initial_utility_helicopter_count: int = 3
@export var carrier_manager_path: NodePath = NodePath("../CarrierManager")
@export var auto_recovery_enabled: bool = true
@export var auto_recovery_speed_threshold_mps: float = 1.5
@export var auto_recovery_zone_half_width_m: float = 22.0
@export var auto_recovery_zone_min_local_z: float = -90.0
@export var auto_recovery_zone_max_local_z: float = -15.0
@export var auto_recovery_zone_height_margin_m: float = 6.0
@export var launch_deck_pitch_contact_max_deg: float = 4.0
@export var desired_deck_tractor_count: int = 4
@export var landing_deck_block_half_width_m: float = 24.0
@export var landing_deck_block_min_local_z: float = -95.0
@export var landing_deck_block_max_local_z: float = 95.0
@export var landing_deck_block_height_margin_m: float = 8.0
@export var landing_blocker_cleanup_enabled: bool = true
@export var landing_blocker_cleanup_timeout_s: float = 35.0
@export var landing_blocker_cleanup_speed_threshold_mps: float = 2.5
@export var landing_blocker_cleanup_deck_contact_margin_m: float = 1.0
@export var settled_touchdown_vertical_speed_threshold_mps: float = 1.0
@export var settled_touchdown_min_upright_dot: float = 0.75
@export var landing_clearance_abandon_radius_m: float = 8000.0
@export var landing_clearance_timeout_s: float = 30.0
@export var landing_clearance_retry_cooldown_s: float = 12.0
@export var helicopter_recent_landing_clearance_hold_s: float = 15.0
@export var carrier_recovery_speed_limit_mps: float = 0.0
@export var carrier_recovery_constraint_requires_active_clearance: bool = true
@export var launch_carrier_turn_yaw_rate_limit_deg_s: float = 0.6
@export var launch_carrier_turn_steer_limit: float = 0.06
# When a launch is pending and the carrier is turning, make the carrier STOP TURNING (and slow via the
# recovery constraint) to create a launch window, rather than deferring the launch until it happens to
# be flying straight. This gets aircraft off the deck promptly instead of trickling out.
@export var launch_stop_carrier_to_launch: bool = true
# Don't launch into a cliff: sample terrain ahead along the launch heading and refuse if it rises above
# a shallow climb profile within the check distance.
@export var launch_terrain_check_enabled: bool = true
@export var launch_terrain_check_distance_m: float = 800.0    # how far ahead to reserve before reactive pilot avoidance takes over
@export var launch_terrain_check_step_m: float = 80.0         # sampling step along the departure path
@export var launch_terrain_climb_grade: float = 0.10          # assumed climb-out gradient (rise/run) after launch
@export var launch_terrain_clearance_m: float = 60.0          # required clearance above terrain along the path
var _launch_terrain_block_log_s: float = 0.0
# Don't clear a fixed-wing recovery into terrain that protrudes through the
# carrier's glideslope. The carrier keeps moving while clearance is withheld,
# so queued aircraft can hold until a usable approach corridor opens.
@export var landing_terrain_check_enabled: bool = true
@export var landing_terrain_check_distance_m: float = 2000.0  # Fallback only; authored approach_0 -> approach_4 distance is preferred
@export var landing_terrain_check_step_m: float = 100.0
@export var landing_terrain_glideslope_deg: float = 5.9
@export var landing_terrain_clearance_m: float = 25.0
@export var landing_terrain_corridor_half_width_m: float = 180.0
@export var landing_terrain_corridor_near_half_width_m: float = 35.0
@export var landing_terrain_corridor_full_width_distance_m: float = 1500.0
@export var landing_terrain_cache_interval_s: float = 0.35
@export var landing_carrier_turn_yaw_rate_limit_deg_s: float = 0.35
@export var landing_carrier_turn_steer_limit: float = 0.04
@export var tractor_recovery_debug: bool = true
@export var tractor_recovery_debug_interval_s: float = 1.0
@export var tractor_position_timeout_s: float = 16.0
@export var tractor_elevator_floor_offset_m: float = 0.0
@export var tractor_elevator_align_duration_s: float = 1.2

const AIRCRAFT_1_SCENE_PATH := "res://Aircraft/Aircraft_1.tscn"
const DEFAULT_AIRCRAFT_SCENE_PATH := "res://Aircraft/Aircraft_5.tscn"
const LOADOUT_CAP := "cap"
const LOADOUT_INTERCEPT := "intercept"
const LOADOUT_STRIKE := "strike"
const LOADOUT_COMBAT_TEST := "combat_test"
const LOADOUT_ROCKET_STRIKE := "rocket_strike"
const LOADOUT_BOMB_STRIKE := "bomb_strike"
const LOADOUT_RANDOM_GROUND_STRIKE := "random_ground_strike"
const LOADOUT_GUN_ONLY := "gun_only"
const WEAPON_SCENE_20MM := "res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn"
const WEAPON_SCENE_ROCKET_POD := "res://Weapons/RocketPod/rocket_pod.tscn"
const WEAPON_SCENE_BOMB_RACK := "res://Weapons/Bomb/bomb_rack.tscn"
const PRIMARY_TRACTOR_COUNT := 4
const MOTION_REFERENCE_NODE_META := "motion_reference_node"
const MOTION_REFERENCE_VELOCITY_META := "motion_reference_velocity"
const LEGACY_CARRIER_VELOCITY_META := "carrier_deck_velocity"
const MANUAL_TRANSPORT_META := "carrier_manual_transport"
const HELI_TEST_TYPE_META := "heli_test_aircraft_type"
const HELI_TEST_STAT_META_PREFIX := "heli_test_stat_recorded_"
const HELI_TEST_UNLIMITED_AMMO_META := "heli_test_unlimited_ammo"
const HELI_TEST_COMBAT_MODE_META := "heli_test_combat_mode"
const HELI_NAVIGATION_TEST_META := "heli_navigation_test_mode"
const HELI_NAVIGATION_ROUTE_SLOT_META := "heli_navigation_route_slot"
const HELI_NAVIGATION_FIXED_LZ_META := "heli_navigation_fixed_lz"
const HELI_NAVIGATION_TUNING_ASSIGNMENT_META := "heli_navigation_tuning_assignment"
const HELI_NAVIGATION_HOME_META := "heli_navigation_home_point"
const HELI_TEST_FLAT_GROUND_Y_META := "heli_test_flat_ground_y"
const HELI_TEST_ARENA_CENTER_META := "heli_test_arena_center"
const HELI_TEST_ARENA_RADIUS_META := "heli_test_arena_radius"

enum DeckState {
	IDLE,
	AIRCRAFT_ON_DECK,
	LAUNCH_IN_PROGRESS,
	RECOVERY_IN_PROGRESS,
	STORING_IN_HANGAR,
	RETRIEVING_FROM_HANGAR,
	TRACTOR_CLEANUP
}

var current_state: DeckState = DeckState.IDLE:
	set(value):
		if current_state != value:
			current_state = value
			emit_signal("deck_state_changed", current_state)

var deck_aircraft: RigidBody3D = null
var _recovery_powerdown_in_progress: bool = false
var _recovery_release_done: bool = false
var stored_aircraft: Array[Dictionary] = []  # Store aircraft data instead of references
var _pending_store_aircraft: RigidBody3D = null
var _aircraft_lift_height: float = 0.2  # Height to lift aircraft when moving
var _aircraft_move_speed: float = 5.5  # Speed to move aircraft around deck
var _tractor_staging_speed: float = 12.0  # Bot retreat speed to staging (m/s)
var _retrieval_spawn_settle_s: float = 0.15
var _flight_deck_local_offset_y: float = 0.5  # Fallback local offset if no marker
var _aircraft_original_collision_layer: int = 0
var _aircraft_original_collision_mask: int = 0
var _retrieval_top_handled: bool = false
var _recovery_job_dispatched: bool = false
var _tractor_cleanup_in_progress: bool = false
var _tractor_cleanup_batch: Array[Node3D] = []
var _tractor_cleanup_move_speed: float = 3.75
var _tractor_elevator_transfer_in_progress: bool = false
var _tractorbots_in_hangar: bool = false
var landing_deck_active: bool = false
var _landing_clearance_aircraft: RigidBody3D = null
var _landing_clearance_queue: Array[RigidBody3D] = []
var _landing_clearance_elapsed_s: float = 0.0
var _landing_clearance_retry_after_s: Dictionary = {}
var _recent_helicopter_landing_aircraft: RigidBody3D = null
var _recent_helicopter_landing_hold_until_s: float = 0.0
var _landing_blocker_aircraft: RigidBody3D = null
var _landing_blocker_elapsed_s: float = 0.0
var _landing_blocker_cleanup_dispatched: bool = false
var _landing_path_cache_clear: bool = true
var _landing_path_cache_until_s: float = 0.0
var _launch_turn_block_log_s: float = 0.0
var carrier_manager: CarrierManager = null

# --- Landing test mode ---
var _landing_test_active: bool = false
var _landing_test_timer: float = 0.0
var _landing_test_aircraft: Array[RigidBody3D] = []
var _landing_test_spawn_index: int = 0
var _recovery_debug_spawn_index: int = 0
var _retrieval_sequence: int = 0
const LANDING_TEST_INTERVAL_S: float = 20.0
const LANDING_TEST_SPAWN_DIST_M: float = 2000.0
const LANDING_TEST_ALTITUDE_M: float = 140.0  # above carrier deck
const LANDING_TEST_SPEED_MPS: float = 70.0
const RECOVERY_DEBUG_SPAWN_DIST_M: float = 1000.0
const RECOVERY_DEBUG_ALTITUDE_M: float = 100.0
const LANDING_WIRE_HALF_WIDTH_M: float = 24.8  # ±24.8 m = full wire width

# --- Saved physical test scenarios (F11 / Shift+F11) ---
enum TestScenario { NORMAL_GAME, HELI_NAVIGATION, HELI_AIMING, AIRPLANE_TEST, DOGFIGHT_TEST, LANDING_TEST, CARRIER_COMBAT_TEST }
const TEST_SCENARIO_SETTINGS_PATH := "user://physical_test_scenario.json"
const TEST_SCENARIO_LABELS := {
	TestScenario.NORMAL_GAME: "Normal Game",
	TestScenario.HELI_NAVIGATION: "Helicopter Navigation Loop",
	TestScenario.HELI_AIMING: "Helicopter Aiming Range",
	TestScenario.AIRPLANE_TEST: "Airplane Test Circuit",
	TestScenario.DOGFIGHT_TEST: "Dogfight Test",
	TestScenario.LANDING_TEST: "Landing Test",
	TestScenario.CARRIER_COMBAT_TEST: "Carrier Combat Test",
}
@export_enum("Normal Game", "Helicopter Navigation Loop", "Helicopter Aiming Range", "Airplane Test Circuit", "Dogfight Test", "Landing Test", "Carrier Combat Test") \
		var startup_test_scenario: int = TestScenario.NORMAL_GAME
@export var remember_test_scenario: bool = true
var _active_test_scenario: int = TestScenario.NORMAL_GAME

# --- Helicopter aiming range ---
var _heli_test_active: bool = false
var _heli_test_timer: float = 0.0
var _heli_test_spawn_index: int = 0
var _heli_test_dummy_retry_s: float = 0.0
var _heli_test_arena: Node3D = null
var _heli_test_arena_center: Vector3 = Vector3.ZERO
var _heli_test_carrier_original_transform: Transform3D = Transform3D.IDENTITY
var _heli_test_has_carrier_original_transform: bool = false
var _heli_test_suspended_manager_modes: Dictionary = {}
const HELI_TEST_INTERVAL_S: float = 5.0
const HELI_TEST_MAX_COUNT: int = 8
const HELI_TEST_DUMMY_COUNT: int = 8
const HELI_TEST_DUMMY_RETRY_S: float = 5.0
const HELI_TEST_ARENA_SIZE_M: float = 10000.0
const HELI_TEST_ARENA_SURFACE_Y: float = 1600.0
const HELI_TEST_TARGET_RING_RADIUS_M: float = 2700.0
const HELI_TEST_HELICOPTER_RING_RADIUS_M: float = 350.0
const HELI_TEST_HELICOPTER_AGL_M: float = 100.0
const HELI_TEST_DUMMY_HEALTH: float = 1000000000.0
const HELI_TEST_UI_LAYER: int = 1000

# --- Helicopter navigation loop ---
var _heli_navigation_test_active: bool = false
var _heli_navigation_test_timer_s: float = 0.0
var _heli_navigation_lzs: Array[Vector3] = []
var _heli_navigation_center: Vector3 = Vector3.ZERO
var _heli_navigation_spawn_serial: int = 0
# Per-aircraft navigation-loop tracking, keyed by aircraft instance id. Each entry
# records the current leg, leg start time, and per-route aggregate metrics so we can
# write lap times / success / crash stats to the navigation report.
var _navigation_tracked: Dictionary = {}
var _navigation_route_stats: Array[Dictionary] = []
var _navigation_report_started: bool = false
var _navigation_report_summary_timer_s: float = 0.0
var _navigation_launch_watchdog_log_s: float = 0.0
var _navigation_no_active_since_s: float = -1.0
var _navigation_orphan_cleanup_log_s: float = 0.0
var _navigation_idle_refill_log_s: float = 0.0
const HELI_NAVIGATION_REPORT_PATH := "res://heli_navigation_report.log"
const HELI_NAVIGATION_REPORT_SUMMARY_S: float = 30.0
const HELI_NAVIGATION_RETRY_S: float = 5.0
const HELI_NAVIGATION_ROUTE_COUNT: int = 8
const HELI_NAVIGATION_LAUNCH_WATCHDOG_GRACE_S: float = 12.0
const HELI_NAVIGATION_LAUNCH_WATCHDOG_LOG_S: float = 15.0
const HELI_NAVIGATION_ORPHAN_CLEANUP_LOG_S: float = 10.0
const HELI_NAVIGATION_IDLE_REFILL_LOG_S: float = 15.0
# Test-harness safety valve. A candidate that cannot reduce its distance to the
# active endpoint should fail promptly instead of consuming a route for 15 minutes.
const HELI_NAVIGATION_NO_PROGRESS_TIMEOUT_S: float = 120.0
const HELI_NAVIGATION_PROGRESS_EPSILON_M: float = 60.0
const HELI_NAVIGATION_PROGRESS_GOAL_RADIUS_M: float = 300.0
# This test is about navigation/path following, not carrier landing clearance.
# Once an inbound heli has returned close to the stationary carrier, count the
# return as a lap and despawn/requeue it instead of entering the landing pattern.
const HELI_NAVIGATION_RETURN_CAPTURE_RADIUS_M: float = 200.0
# Navigation test geometry. The carrier is placed on a broad, nearly level patch
# near map centre; eight fixed LZs fan out from that actual carrier position.
const HELI_NAVIGATION_MIN_LEG_M: float = 4000.0
const HELI_NAVIGATION_MAX_LEG_M: float = 7000.0
const HELI_NAVIGATION_LZ_BASE_RADIUS_M: float = 4300.0
const HELI_NAVIGATION_LZ_RADIUS_STEP_M: float = 300.0
const HELI_NAVIGATION_LZ_FLAT_RADIUS_M: float = 24.0
const HELI_NAVIGATION_LZ_MAX_VARIATION_M: float = 1.5
# A tiny flat pad can still sit beside a cliff, which turns the LZ into a trap
# rather than a navigation test. Require a broad low-relief approach/departure
# area too, but keep it looser than the actual touchdown footprint so normal
# rolling terrain can still be used.
const HELI_NAVIGATION_LZ_SURROUNDING_RADIUS_M: float = 260.0
const HELI_NAVIGATION_LZ_SURROUNDING_MAX_RELIEF_M: float = 45.0
# Diagnostic route policy: keep LZs near the carrier's terrain level so the
# navigation tuner can learn basic path following, turning, landing and recovery
# before we reintroduce large plateau/cliff altitude transitions.
const HELI_NAVIGATION_LZ_SAME_LEVEL_BAND_M: float = 70.0
const HELI_NAVIGATION_LZ_FALLBACK_LEVEL_BAND_M: float = 140.0
# Full A* route previews are useful diagnostics, but too expensive to run across
# the whole LZ search loop during startup. Keep the helper available, but do not
# gate scenario setup on it until it is cached or moved off-thread.
const HELI_NAVIGATION_LZ_PATH_QUALITY_PROBE_ENABLED: bool = false
const HELI_NAVIGATION_LZ_MAX_PATH_RATIO: float = 1.85
const HELI_NAVIGATION_LZ_PATH_REJECT_LOG_LIMIT: int = 3
# Routes 7/8 repeatedly selected technically flat south/southeast LZs whose actual
# routes were crash-heavy detours. Bias those two test-only slots away from the
# observed choke, then require a path-quality preview for them before accepting.
const HELI_NAVIGATION_ROUTE_7_LZ_ANGLE_BIAS_DEG: float = -25.0
const HELI_NAVIGATION_ROUTE_7_LZ_RADIUS_BIAS_M: float = -1000.0
const HELI_NAVIGATION_ROUTE_8_LZ_ANGLE_BIAS_DEG: float = 35.0
const HELI_NAVIGATION_ROUTE_8_LZ_RADIUS_BIAS_M: float = -1200.0
const HELI_NAVIGATION_CARRIER_FLAT_RADIUS_M: float = 130.0
const HELI_NAVIGATION_CARRIER_MAX_VARIATION_M: float = 2.5
# The deck footprint alone can sit on a perfectly flat mesa. Require a broad,
# low-relief departure area as well so every route does not begin at a cliff wall.
const HELI_NAVIGATION_CARRIER_SURROUNDING_RADIUS_M: float = 600.0
const HELI_NAVIGATION_CARRIER_SURROUNDING_MAX_RELIEF_M: float = 115.0
const HELI_NAVIGATION_CARRIER_GROUND_BAND_M: float = 35.0
const HELI_NAVIGATION_CARRIER_SEARCH_STEP_M: float = 200.0
const HELI_NAVIGATION_CARRIER_SEARCH_RADIUS_M: float = 4000.0

var _landing_score_total: float = 0.0
var _landing_attempt_count: int = 0

# --- HELI TEST UI STATS ---
var _heli_test_stats: Dictionary = {
	"Aircraft_9": {"spawned": 0, "lz": 0, "carrier": 0, "crash": 0},
	"Aircraft_10": {"spawned": 0, "lz": 0, "carrier": 0, "crash": 0},
	"Aircraft_11": {"spawned": 0, "lz": 0, "carrier": 0, "crash": 0},
}
var _heli_test_start_time_msec: int = 0
var _heli_ui_update_accum_s: float = 0.0
var _heli_ui_canvas: CanvasLayer = null
var _heli_ui_bg: ColorRect = null
var _heli_ui_label: Label = null

func _landing_test_outcome_type(outcome: String) -> String:
	match outcome:
		"CAUGHT":
			return "CATCH"
		"BOLTER", "WAVE-OFF":
			return "GO-AROUND"
		"CRASH", "DESTROYED":
			return "CRASH"
		"STRAY":
			return "STRAY"
		_:
			return "OTHER"

func record_landing_test_outcome(aircraft_variant: Variant, outcome: String, points: float = 0.0) -> bool:
	if not is_instance_valid(aircraft_variant):
		return false
	var aircraft := aircraft_variant as RigidBody3D
	if not is_instance_valid(aircraft):
		return false
	var terminal_outcome: bool = outcome in ["CAUGHT", "BOLTER", "WAVE-OFF", "CRASH", "DESTROYED", "STRAY"]
	if terminal_outcome:
		release_landing_clearance(aircraft)
	if not _landing_test_aircraft.has(aircraft):
		return false
	if aircraft.has_meta("landing_test_score_recorded") and bool(aircraft.get_meta("landing_test_score_recorded")):
		if terminal_outcome:
			_release_landing_test_aircraft(aircraft, 0.2)
		return false
	aircraft.set_meta("landing_test_score_recorded", true)
	_landing_score_total += points
	_landing_attempt_count += 1
	var avg: float = _landing_score_total / maxf(float(_landing_attempt_count), 1.0)
	var outcome_type: String = _landing_test_outcome_type(outcome)
	print("[LAND] AVG  %.2f pts  n=%d  last=%s %.1f pts  type=%s" % [
		avg,
		_landing_attempt_count,
		outcome,
		points,
		outcome_type
	])
	if terminal_outcome:
		var release_delay: float = 1.5 if outcome == "CAUGHT" else 0.2
		_release_landing_test_aircraft(aircraft, release_delay)
	return true

func _release_landing_test_aircraft(aircraft: RigidBody3D, delay_s: float = 0.2) -> void:
	_landing_test_aircraft.erase(aircraft)
	if not is_instance_valid(aircraft):
		return
	if delay_s <= 0.0:
		aircraft.queue_free()
		return
	get_tree().create_timer(delay_s).timeout.connect(func():
		if is_instance_valid(aircraft):
			aircraft.queue_free()
	)

# FlightOps AI-launch queue
var _ai_launch_queue: int = 0          # Aircraft still to retrieve+launch for FlightOps
var _pending_flight_ops: Node = null   # Node waiting for notify_aircraft_launched() callbacks (FlightDirector)
var _retrieval_ai_land_after_launch: bool = true
var _pending_ai_loadout_profile: String = ""
var _pending_ai_aircraft_kind: String = "fixed_wing"
var _pending_ai_aircraft_model: String = ""
var _pending_launch_hangar_index: int = 0   # hangar slot chosen for the current launch (skips utility helis for AI scrambles)

func _deck_state_name(state: int = -1) -> String:
	var resolved_state := current_state if state == -1 else state
	match resolved_state:
		DeckState.IDLE:
			return "IDLE"
		DeckState.AIRCRAFT_ON_DECK:
			return "AIRCRAFT_ON_DECK"
		DeckState.LAUNCH_IN_PROGRESS:
			return "LAUNCH_IN_PROGRESS"
		DeckState.RECOVERY_IN_PROGRESS:
			return "RECOVERY_IN_PROGRESS"
		DeckState.STORING_IN_HANGAR:
			return "STORING_IN_HANGAR"
		DeckState.RETRIEVING_FROM_HANGAR:
			return "RETRIEVING_FROM_HANGAR"
		DeckState.TRACTOR_CLEANUP:
			return "TRACTOR_CLEANUP"
		_:
			return "UNKNOWN"

func _aircraft_debug_name(aircraft: Variant) -> String:
	if not is_instance_valid(aircraft):
		return "none"
	var node := aircraft as Node
	return node.name if is_instance_valid(node) else "none"

func _fmt_vec3(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]

func _recovery_debug(message: String) -> void:
	if not tractor_recovery_debug:
		return
	print("[FlightDeck RECOVERY] state=%s aircraft=%s pending=%s dispatched=%s bots_hangar=%s %s" % [
		_deck_state_name(),
		_aircraft_debug_name(deck_aircraft),
		_aircraft_debug_name(_pending_store_aircraft),
		str(_recovery_job_dispatched),
		str(_tractorbots_in_hangar),
		message
	])

func _launch_path_clear_of_terrain() -> bool:
	## Sample terrain ahead along the launch (deck-forward) direction. Aircraft launch low and climb out
	## shallowly, so if terrain rises above a climb profile within the check distance, it's a cliff ahead
	## -- refuse the launch. Returns true (clear) if no terrain provider is available (can't check).
	if not launch_terrain_check_enabled:
		return true
	var carrier := get_parent()
	var origin: Node3D = null
	if catapult and is_instance_valid(catapult) and catapult is Node3D:
		origin = catapult as Node3D
	elif carrier is Node3D:
		origin = carrier as Node3D
	if origin == null:
		return true
	var terrain: Node = get_tree().get_first_node_in_group("terrain_provider")
	if terrain == null or not terrain.has_method("get_height"):
		return true  # can't check -> don't block
	var start_pos: Vector3 = origin.global_position
	var fwd: Vector3
	if catapult and catapult.has_method("_get_deck_forward_vector"):
		fwd = catapult.call("_get_deck_forward_vector")
	elif carrier is Node3D:
		fwd = (carrier as Node3D).global_transform.basis.z
	else:
		return true
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return true
	fwd = fwd.normalized()
	# Climb profile: aircraft is ~deck height at launch and climbs at ~climb_grade. Terrain above
	# (launch_y + distance*grade + clearance) within the check distance is a wall we'd hit.
	# Sample a small fan around deck-forward, not just the single centerline ray -- the aircraft's
	# actual post-launch heading (captured from its own attitude once clear of the deck, see
	# AIPilot._state_launching) can drift a few degrees off deck-forward, and a single ray missed a
	# cliff that two aircraft in a row flew straight into on an otherwise nominal climb-out.
	var launch_y: float = start_pos.y
	var step_m: float = maxf(launch_terrain_check_step_m, 20.0)
	for fan_deg in [0.0, -10.0, 10.0]:
		var fan_dir: Vector3 = fwd.rotated(Vector3.UP, deg_to_rad(fan_deg))
		var dist: float = step_m
		while dist <= launch_terrain_check_distance_m:
			var sample: Vector3 = start_pos + fan_dir * dist
			var terrain_y: float = float(terrain.call("get_height", sample))
			var safe_y: float = launch_y + dist * launch_terrain_climb_grade + launch_terrain_clearance_m
			if terrain_y > safe_y:
				return false
			dist += step_m
	return true


func _landing_path_clear_of_terrain(force_refresh: bool = false) -> bool:
	## Sample behind the deck along the fixed-wing approach axis. Clearance is
	## withheld when terrain intersects the nominal glideslope plus a small
	## airframe margin. Helicopters do not use this corridor.
	if not landing_terrain_check_enabled:
		return true
	var now_s := Time.get_ticks_msec() / 1000.0
	if not force_refresh and now_s < _landing_path_cache_until_s:
		return _landing_path_cache_clear
	var carrier := get_parent() as Node3D
	if not is_instance_valid(carrier):
		return true
	var terrain: Node = get_tree().get_first_node_in_group("terrain_provider")
	if terrain == null or not terrain.has_method("get_height"):
		return true
	var deck_y: float = carrier.global_position.y
	var check_distance_m: float = maxf(landing_terrain_check_distance_m, landing_terrain_check_step_m)
	var root := get_tree().current_scene
	if root != null:
		var approach_4 := root.find_child("approach_4", true, false) as Node3D
		if is_instance_valid(approach_4):
			deck_y = approach_4.global_position.y
			var approach_0 := root.find_child("approach_0", true, false) as Node3D
			if is_instance_valid(approach_0):
				var authored_final_span: Vector3 = approach_4.global_position - approach_0.global_position
				authored_final_span.y = 0.0
				if authored_final_span.length_squared() > 1.0:
					# Only the authored straight-in segment must be terrain-clear. Recovery
					# before approach_0 is a terrain-aware 3D route, not an extension of the
					# fixed glideslope across several kilometres of arbitrary terrain.
					check_distance_m = authored_final_span.length()
	var forward: Vector3 = carrier.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return true
	forward = forward.normalized()
	var right: Vector3 = carrier.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() >= 0.001 else forward.cross(Vector3.UP).normalized()
	var glide_tan: float = tan(deg_to_rad(clampf(landing_terrain_glideslope_deg, 1.0, 20.0)))
	# A sampling interval wider than the clearance buffer can step cleanly over a
	# narrow ridge that still intersects the glideslope between samples. Respect the
	# configured interval, but never let it be coarser than the safety margin itself.
	var step_m: float = minf(
		maxf(landing_terrain_check_step_m, 20.0),
		maxf(landing_terrain_clearance_m, 20.0)
	)
	var distance_m: float = step_m
	var corridor_clear := true
	while distance_m <= maxf(check_distance_m, step_m):
		# Check a tapered three-lane corridor rather than only its centerline. Near the deck the
		# footprint is narrow; farther out it widens enough to cover a normal lineup correction.
		var width_t := clampf(
			distance_m / maxf(landing_terrain_corridor_full_width_distance_m, step_m),
			0.0,
			1.0
		)
		var half_width := lerpf(
			maxf(landing_terrain_corridor_near_half_width_m, 0.0),
			maxf(landing_terrain_corridor_half_width_m, 0.0),
			width_t
		)
		var path_y: float = deck_y + distance_m * glide_tan
		for lateral_m in [-half_width, 0.0, half_width]:
			var sample: Vector3 = carrier.global_position - forward * distance_m + right * lateral_m
			var terrain_y: float = float(terrain.call("get_height", sample))
			if is_finite(terrain_y) \
			and terrain_y + maxf(landing_terrain_clearance_m, 0.0) > path_y:
				corridor_clear = false
				break
		if not corridor_clear:
			break
		distance_m += step_m
	_landing_path_cache_clear = corridor_clear
	_landing_path_cache_until_s = now_s + maxf(landing_terrain_cache_interval_s, 0.05)
	return corridor_clear


func _is_carrier_settled_for_recovery() -> bool:
	var carrier := get_parent()
	if carrier == null:
		return true
	var yaw_limit := deg_to_rad(maxf(landing_carrier_turn_yaw_rate_limit_deg_s, 0.0))
	var steer_limit := maxf(landing_carrier_turn_steer_limit, 0.0)
	if carrier.has_method("is_turning_for_launch"):
		return not bool(carrier.call("is_turning_for_launch", yaw_limit, steer_limit))
	if carrier.has_method("get_yaw_rate_rad_s"):
		return absf(float(carrier.call("get_yaw_rate_rad_s"))) <= yaw_limit
	return true


func _queued_fixed_wing_recovery_has_clear_corridor() -> bool:
	for requester in _landing_clearance_queue:
		if _is_landing_clearance_aircraft_stale(requester):
			continue
		if not _is_helicopter_aircraft(requester):
			return _landing_path_clear_of_terrain()
	return false

func _is_carrier_turning_for_launch(log_block: bool = false) -> bool:
	var carrier := get_parent()
	if carrier == null:
		return false
	var yaw_limit := deg_to_rad(maxf(launch_carrier_turn_yaw_rate_limit_deg_s, 0.0))
	var steer_limit := maxf(launch_carrier_turn_steer_limit, 0.0)
	var turning := false
	if carrier.has_method("is_turning_for_launch"):
		turning = bool(carrier.call("is_turning_for_launch", yaw_limit, steer_limit))
	elif carrier.has_method("get_yaw_rate_rad_s"):
		turning = absf(float(carrier.call("get_yaw_rate_rad_s"))) > yaw_limit
	if turning and log_block:
		var now_s := Time.get_ticks_msec() / 1000.0
		if now_s >= _launch_turn_block_log_s:
			_launch_turn_block_log_s = now_s + 2.0
			_recovery_debug("launch held: carrier is turning")
	return turning

func _ready():
	if not aircraft_template_scene:
		aircraft_template_scene = load(DEFAULT_AIRCRAFT_SCENE_PATH) as PackedScene
	_normalize_primary_tractorbots()
	_place_primary_tractorbots_at_staging_start()
	_resolve_carrier_manager()
	add_to_group("flight_deck_manager")
	add_to_group("origin_shifter")
	if catapult:
		if catapult.has_signal("launch_sequence_complete"):
			catapult.launch_sequence_complete.connect(_on_catapult_sequence_complete)
		if catapult.has_signal("launch_sequence_aborted"):
			catapult.launch_sequence_aborted.connect(_on_catapult_sequence_aborted)
	var cables = get_tree().get_nodes_in_group("arresting_cable")
	for c in cables:
		_connect_cable_signals(c)
	get_tree().node_added.connect(_on_node_added)
	_ensure_elevator_signal_connections()
	set_physics_process(true)

	# Pre-populate hangar with aircraft
	_initialize_hangar_with_aircraft()

	_active_test_scenario = _load_saved_test_scenario() if remember_test_scenario \
			else clampi(startup_test_scenario, TestScenario.NORMAL_GAME, TestScenario.size() - 1)
	# Let the main scene and autoload managers finish their own _ready methods.
	call_deferred("_activate_selected_test_scenario")


func apply_origin_shift(offset: Vector3) -> void:
	_heli_test_arena_center -= offset
	_heli_navigation_center -= offset
	for i in range(_heli_navigation_lzs.size()):
		_heli_navigation_lzs[i] -= offset
	# Hangar entries are dictionaries rather than Node3Ds, so FloatingOrigin cannot
	# move their cached route coordinates automatically.
	for i in range(stored_aircraft.size()):
		var stored_data: Dictionary = stored_aircraft[i]
		var metadata_variant: Variant = stored_data.get("metadata", {})
		if not (metadata_variant is Dictionary):
			continue
		var metadata := metadata_variant as Dictionary
		if metadata.get(HELI_NAVIGATION_FIXED_LZ_META) is Vector3:
			metadata[HELI_NAVIGATION_FIXED_LZ_META] = \
				(metadata[HELI_NAVIGATION_FIXED_LZ_META] as Vector3) - offset
		if metadata.get(HELI_NAVIGATION_HOME_META) is Vector3:
			metadata[HELI_NAVIGATION_HOME_META] = \
				(metadata[HELI_NAVIGATION_HOME_META] as Vector3) - offset
		stored_data["metadata"] = metadata
		stored_aircraft[i] = stored_data
	if _heli_test_has_carrier_original_transform:
		_heli_test_carrier_original_transform.origin -= offset


func _activate_selected_test_scenario() -> void:
	match _active_test_scenario:
		TestScenario.HELI_NAVIGATION:
			_enable_heli_navigation_test_mode()
		TestScenario.HELI_AIMING:
			if not _heli_test_active:
				_toggle_heli_test_mode()
		TestScenario.AIRPLANE_TEST:
			print("[TestScenario] Airplane Test Circuit (handled by ScenarioManager)")
		TestScenario.DOGFIGHT_TEST:
			print("[TestScenario] Dogfight Test (handled by ScenarioManager)")
		TestScenario.LANDING_TEST:
			print("[TestScenario] Landing Test (handled by ScenarioManager)")
		TestScenario.CARRIER_COMBAT_TEST:
			print("[TestScenario] Carrier Combat Test (handled by ScenarioManager)")
		_:
			print("[TestScenario] Normal Game (F11: next, Shift+F11: previous)")


func _load_saved_test_scenario() -> int:
	if not FileAccess.file_exists(TEST_SCENARIO_SETTINGS_PATH):
		return clampi(startup_test_scenario, TestScenario.NORMAL_GAME, TestScenario.size() - 1)
	var file := FileAccess.open(TEST_SCENARIO_SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return clampi(startup_test_scenario, TestScenario.NORMAL_GAME, TestScenario.size() - 1)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return clampi(startup_test_scenario, TestScenario.NORMAL_GAME, TestScenario.size() - 1)
	var requested_scenario: int = int((parsed as Dictionary).get("scenario", startup_test_scenario))
	if requested_scenario < TestScenario.NORMAL_GAME or requested_scenario >= TestScenario.size():
		return TestScenario.NORMAL_GAME
	return requested_scenario


func _save_test_scenario(scenario: int) -> void:
	var file := FileAccess.open(TEST_SCENARIO_SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[TestScenario] Could not save %s" % TEST_SCENARIO_SETTINGS_PATH)
		return
	file.store_string(JSON.stringify({"scenario": scenario}, "  "))


func _cycle_test_scenario(direction: int) -> void:
	var scenario_count := TestScenario.size()
	var next_scenario := posmod(_active_test_scenario + direction, scenario_count)
	_save_test_scenario(next_scenario)
	print("[TestScenario] Switching to %s..." % _test_scenario_label(next_scenario))
	# Reloading is intentional: it restores enemies, managers, carrier state, and
	# terrain cleanly instead of allowing one scenario's isolation to leak into the next.
	get_tree().call_deferred("reload_current_scene")


func _test_scenario_label(scenario: int = _active_test_scenario) -> String:
	return String(TEST_SCENARIO_LABELS.get(scenario, "Unknown"))


func _on_node_added(node: Node) -> void:
	if node.is_in_group("arresting_cable"):
		_connect_cable_signals(node)

func _connect_cable_signals(cable: Node) -> void:
	if cable.has_signal("cable_engaged") and not cable.cable_engaged.is_connected(_on_cable_engaged):
		cable.cable_engaged.connect(_on_cable_engaged)
	if cable.has_signal("cable_released") and not cable.cable_released.is_connected(_on_cable_released):
		cable.cable_released.connect(_on_cable_released)

func _ensure_elevator_signal_connections() -> void:
	if not elevator:
		return
	if elevator.has_signal("elevator_at_bottom") and not elevator.elevator_at_bottom.is_connected(_on_elevator_at_bottom):
		elevator.elevator_at_bottom.connect(_on_elevator_at_bottom)
	if elevator.has_signal("elevator_at_top") and not elevator.elevator_at_top.is_connected(_on_elevator_at_top):
		elevator.elevator_at_top.connect(_on_elevator_at_top)
	# CarrierElevator currently emits covers_opened when returning to deck top.
	# Treat it as a top-reached fallback so state transitions complete reliably.
	if elevator.has_signal("covers_opened") and not elevator.covers_opened.is_connected(_on_elevator_covers_opened):
		elevator.covers_opened.connect(_on_elevator_covers_opened)

func _resolve_carrier_manager() -> void:
	if is_instance_valid(carrier_manager):
		return
	if carrier_manager_path != NodePath():
		var configured_node := get_node_or_null(carrier_manager_path)
		if configured_node is CarrierManager:
			carrier_manager = configured_node as CarrierManager
	if not is_instance_valid(carrier_manager):
		var parent := get_parent()
		if parent:
			var sibling := parent.get_node_or_null("CarrierManager")
			if sibling is CarrierManager:
				carrier_manager = sibling as CarrierManager
	if is_instance_valid(carrier_manager):
		carrier_manager.ensure_initialized()
	else:
		push_warning("[FlightDeckManager] CarrierManager not found. Aircraft pilot assignment is unavailable.")

func _get_primary_tractor_bots() -> Array[Node3D]:
	var primary: Array[Node3D] = []
	var seen: Dictionary = {}
	for bot_variant in tractor_bots:
		if not is_instance_valid(bot_variant) or not (bot_variant is Node3D):
			continue
		var bot := bot_variant as Node3D
		var id := bot.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		primary.append(bot)
		if primary.size() >= PRIMARY_TRACTOR_COUNT:
			break
	return primary

func _normalize_primary_tractorbots() -> void:
	var primary := _get_primary_tractor_bots()
	tractor_bots.clear()
	for bot in primary:
		tractor_bots.append(bot)
	desired_deck_tractor_count = PRIMARY_TRACTOR_COUNT
	var primary_lookup: Dictionary = {}
	for bot in primary:
		primary_lookup[bot.get_instance_id()] = true
	for node in _get_all_tractor_nodes():
		if primary_lookup.has(node.get_instance_id()):
			continue
		node.queue_free()
	if primary.size() < PRIMARY_TRACTOR_COUNT:
		push_warning("[FlightDeckManager] Expected %d tractorbots, found %d." % [PRIMARY_TRACTOR_COUNT, primary.size()])

func _get_primary_staging_slots_local(count: int) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var deck_local_y: float = _get_deck_local_y()
	var slot_offsets: Array[Vector3] = [
		Vector3(10.0, 0.0, -6.0),
		Vector3(14.0, 0.0, -6.0),
		Vector3(18.0, 0.0, -6.0),
		Vector3(22.0, 0.0, -6.0)
	]
	var base_local: Vector3 = elevator_pickup_marker.position if is_instance_valid(elevator_pickup_marker) else Vector3.ZERO
	for i in range(min(count, slot_offsets.size())):
		var slot_local: Vector3 = base_local + slot_offsets[i]
		slot_local.y = deck_local_y
		slots.append(slot_local)
	return slots

func _place_primary_tractorbots_at_staging_start() -> void:
	var primary := _get_primary_tractor_bots()
	if primary.is_empty():
		return

	var starts_on_bottom_elevator := _is_elevator_physically_at_bottom()
	var slots := _get_primary_staging_slots_local(primary.size())
	if starts_on_bottom_elevator:
		var bottom_slot_y := _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
		slots = _get_primary_elevator_slots_local(primary.size(), bottom_slot_y)

	for i in range(min(primary.size(), slots.size())):
		var bot := primary[i]
		_set_cleanup_idle_for_tractor_bot(bot)
		bot.position = slots[i]

	_tractorbots_in_hangar = starts_on_bottom_elevator
	_tractor_elevator_transfer_in_progress = false

func _ensure_pilot_assigned_for_data(aircraft_data: Dictionary) -> bool:
	_resolve_carrier_manager()
	if not is_instance_valid(carrier_manager):
		return false
	return carrier_manager.ensure_aircraft_data_has_pilot(aircraft_data)

func _make_stored_aircraft_entry_unassigned(aircraft_name: String, scene: PackedScene, scene_file: String = "") -> Dictionary:
	var resolved_scene_file := scene_file
	if resolved_scene_file == "" and scene != null:
		resolved_scene_file = scene.resource_path
	return {
		"name": aircraft_name,
		"scene_file": resolved_scene_file,
		"scene": scene,
		"position": Vector3.ZERO,
		"rotation": Vector3.ZERO,
		"scale": Vector3.ONE,
		"metadata": {}
	}

func _make_stored_aircraft_entry(aircraft_name: String, scene: PackedScene, scene_file: String = "") -> Dictionary:
	var entry := _make_stored_aircraft_entry_unassigned(aircraft_name, scene, scene_file)
	if not _ensure_pilot_assigned_for_data(entry):
		return {}
	return entry

func _queue_aircraft_scene_for_retrieval(aircraft_name: String, scene: PackedScene, scene_file: String = "") -> void:
	if _landing_test_active:
		return
	var entry := _make_stored_aircraft_entry(aircraft_name, scene, scene_file)
	if entry.is_empty():
		return
	if _heli_test_active:
		entry.metadata[HELI_TEST_TYPE_META] = aircraft_name
		entry.metadata[HELI_TEST_UNLIMITED_AMMO_META] = true
		entry.metadata[HELI_TEST_COMBAT_MODE_META] = true
		entry.metadata[HELI_TEST_FLAT_GROUND_Y_META] = HELI_TEST_ARENA_SURFACE_Y
		entry.metadata[HELI_TEST_ARENA_CENTER_META] = _heli_test_arena_center
		entry.metadata[HELI_TEST_ARENA_RADIUS_META] = HELI_TEST_ARENA_SIZE_M * 0.5
	stored_aircraft.push_front(entry)
	if _heli_test_active:
		_log_heli_test("retrieval queued state=%s stored=%d elevator_top=%s bottom=%s" % [
			_deck_state_name(),
			stored_aircraft.size(),
			str(_is_elevator_physically_at_top()),
			str(elevator != null and "current_state" in elevator and elevator.current_state == elevator.ElevatorState.AT_BOTTOM),
		])
	start_hangar_retrieval()

func _queue_aircraft_1_hotkey_launch() -> void:
	if current_state != DeckState.IDLE or _landing_test_active:
		return
	var scene := aircraft_1_scene
	if scene == null:
		scene = load(AIRCRAFT_1_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("[FlightDeckManager] Aircraft 1 hotkey could not load %s" % AIRCRAFT_1_SCENE_PATH)
		return
	_queue_aircraft_scene_for_retrieval("Aircraft_1", scene, AIRCRAFT_1_SCENE_PATH)

func _is_elevator_physically_at_top() -> bool:
	if not elevator:
		return false
	if not ("platform_size" in elevator):
		return false
	var platform_local_y := _get_elevator_platform_local_y(INF)
	if platform_local_y == INF:
		return false
	var top_y = -float(elevator.platform_size.y) * 0.5
	return abs(platform_local_y - top_y) <= 0.15

func _is_elevator_physically_at_bottom() -> bool:
	if not elevator:
		return false
	if not ("shaft_depth" in elevator):
		return false
	var platform_local_y := _get_elevator_platform_local_y(INF)
	if platform_local_y == INF:
		return false
	return abs(platform_local_y + float(elevator.shaft_depth)) <= 0.15

func _get_elevator_platform_local_y(fallback_y: float = -10.0) -> float:
	if not elevator or not ("platform" in elevator):
		return fallback_y
	var platform_node: Variant = elevator.platform
	if not is_instance_valid(platform_node) or not (platform_node is Node3D):
		return fallback_y
	return float((platform_node as Node3D).position.y)

func _get_elevator_platform_top_offset_y() -> float:
	if elevator and "platform_size" in elevator:
		return float(elevator.platform_size.y) * 0.5
	return 0.5

func _get_elevator_platform_top_global_y(fallback_platform_local_y: float = -10.0) -> float:
	return _get_deck_height_y() + _get_elevator_platform_local_y(fallback_platform_local_y) + _get_elevator_platform_top_offset_y()

func _get_elevator_platform_top_local_y(fallback_platform_local_y: float = -10.0) -> float:
	return _get_deck_local_y() + _get_elevator_platform_local_y(fallback_platform_local_y) + _get_elevator_platform_top_offset_y()

func _get_carrier_forward_yaw() -> float:
	var carrier := get_parent() as Node3D
	var forward := Vector3.FORWARD
	if is_instance_valid(carrier):
		forward = carrier.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	return atan2(forward.x, forward.z)

func _on_elevator_covers_opened() -> void:
	# Some states can open covers before the platform is fully at deck height.
	# Only treat covers_opened as "top reached" when position is physically at top.
	if (current_state == DeckState.STORING_IN_HANGAR or current_state == DeckState.RETRIEVING_FROM_HANGAR) and _is_elevator_physically_at_top():
		_on_elevator_at_top()

func _input(event):
	if Input.is_action_just_pressed("request_launch"):
		var player_aircraft = get_tree().get_first_node_in_group("aircraft")
		if player_aircraft and player_aircraft is RigidBody3D:
			if current_state == DeckState.IDLE:
				request_launch_sequence(player_aircraft)
			else:
				pass
		else:
			pass

	# Store last landed aircraft in hangar
	if Input.is_action_just_pressed("store_aircraft"):
		if _pending_store_aircraft and current_state == DeckState.IDLE:
			start_hangar_storage(_pending_store_aircraft)
		else:
			pass

	# Retrieve the next existing aircraft through the generic Input Map action.
	if Input.is_action_just_pressed("retrieve_aircraft"):
		if current_state == DeckState.IDLE and not stored_aircraft.is_empty():
			start_hangar_retrieval()
		else:
			if current_state != DeckState.IDLE:
				pass
			if stored_aircraft.is_empty():
				pass

	# Summon Aircraft 1 from the hangar and run the normal automatic launch flow.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_1:
		_queue_aircraft_1_hotkey_launch()
		return

	# Direct keyboard shortcuts below this point were development/test controls.
	# Keep action-based controls above so newly assigned Input Map keys still work.
	if event is InputEventKey:
		return

	# Spawn Aircraft 2 from hangar (key "2")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_2:
		if current_state == DeckState.IDLE:
			var scene := aircraft_2_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_2.tscn")
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_2", scene)
			else:
				pass
		else:
			pass

	# Spawn Aircraft 5 from hangar (key "5")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_5:
		if current_state == DeckState.IDLE:
			var scene: PackedScene = load(DEFAULT_AIRCRAFT_SCENE_PATH)
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_5", scene, DEFAULT_AIRCRAFT_SCENE_PATH)

	# Spawn Aircraft 7 from hangar (key "7")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_7:
		if current_state == DeckState.IDLE:
			var scene := aircraft_7_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_7.tscn")
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_7", scene)

	# Spawn Aircraft 8 from hangar (key "8")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_8:
		if current_state == DeckState.IDLE:
			var scene := aircraft_8_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_8.tscn")
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_8", scene)

	# Spawn Aircraft 9 rescue helicopter from hangar (key "9")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_9:
		if current_state == DeckState.IDLE:
			var scene := aircraft_9_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_9.tscn")
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_9", scene)

	# Spawn Aircraft 10 scout helicopter from hangar (key "0")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_0:
		if current_state == DeckState.IDLE:
			var scene := aircraft_10_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_10.tscn")
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_10", scene)

	# Spawn Aircraft 11 utility helicopter from hangar (key "-")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_MINUS:
		if current_state == DeckState.IDLE:
			var scene := aircraft_11_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_11.tscn")
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_11", scene)

	# Debug key to force reset state (F9)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		current_state = DeckState.IDLE
		_pending_store_aircraft = null
		_landing_clearance_aircraft = null
		_landing_clearance_queue.clear()

	# F1 — toggle landing test mode
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_landing_test_active = not _landing_test_active
		_landing_test_timer = 0.0  # Spawn first aircraft immediately
		print("[LandingTest] mode %s" % ("ON" if _landing_test_active else "OFF"))
		if _landing_test_active:
			_enter_landing_test_isolation()
		else:
			for ac in _landing_test_aircraft:
				if is_instance_valid(ac):
					ac.queue_free()
			_landing_test_aircraft.clear()
			_landing_clearance_aircraft = null
			_landing_clearance_queue.clear()
			_landing_test_spawn_index = 0
			_landing_score_total = 0.0
			_landing_attempt_count = 0

	# F2 - spawn one normal recovery-test aircraft on straight-in landing.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		_spawn_recovery_debug_aircraft()

	# F3 - command closest eligible airborne AI aircraft to return via recovery framework.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_command_closest_aircraft_to_return_to_base()

	# F11 cycles saved physical scenarios; Shift+F11 cycles backwards. The scene
	# reload gives every scenario a pristine world and makes Normal Game truly normal.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_cycle_test_scenario(-1 if event.shift_pressed else 1)
		get_viewport().set_input_as_handled()

func request_launch_sequence(aircraft: RigidBody3D):
	if not is_instance_valid(aircraft):
		_recovery_debug("launch request ignored: invalid aircraft")
		return
	if _is_non_aircraft_body(aircraft):
		_recovery_debug("launch request ignored for non-aircraft body %s" % _aircraft_debug_name(aircraft))
		return
	if _landing_test_active and not _landing_test_aircraft.has(aircraft):
		return
	if not catapult:
		return
	if _is_carrier_turning_for_launch(true):
		return
	# Don't launch straight into rising terrain / a cliff ahead (this has flung aircraft into walls).
	# Hold the launch until the departure path is clear -- the carrier will keep moving/turning and the
	# heading will change, opening a safe launch corridor.
	if not _launch_path_clear_of_terrain():
		var now_cliff_s := Time.get_ticks_msec() / 1000.0
		if now_cliff_s >= _launch_terrain_block_log_s:
			_launch_terrain_block_log_s = now_cliff_s + 2.0
			_recovery_debug("launch held: terrain/cliff ahead on departure path")
		return

	# Clear parking brake but keep controls_disabled set until catapult latch/release.
	# This prevents AIPilot/ControlEngine from spooling before shuttle connection.
	if aircraft.has_meta("parking_brake"):
		aircraft.remove_meta("parking_brake")

	aircraft.set_meta("controls_disabled", true)
	

	var physics_ready_handoff := false
	# Retrieval launch handoff:
	# If retrieval already restored physics at the catapult marker, skip a second
	# restore here and tell Catapult to skip its teleport/freeze path once.
	# This avoids double handoff artifacts and keeps launch flow deterministic.
	if aircraft.has_meta("physics_ready_for_launch") and bool(aircraft.get_meta("physics_ready_for_launch")):
		aircraft.remove_meta("physics_ready_for_launch")
		physics_ready_handoff = true
		
	else:
		await _restore_aircraft_physics(aircraft)
		if not is_instance_valid(aircraft):
			_recovery_debug("launch request aborted after restore: aircraft invalid")
			return
		if _is_non_aircraft_body(aircraft):
			_recovery_debug("launch request aborted after restore for non-aircraft body %s" % _aircraft_debug_name(aircraft))
			return

	current_state = DeckState.LAUNCH_IN_PROGRESS
	deck_aircraft = aircraft
	if catapult.has_method("align_aircraft"):
		if physics_ready_handoff:
			# One-shot catapult bypass for retrieval launches.
			aircraft.set_meta("catapult_skip_teleport_once", true)
		catapult.align_aircraft(aircraft)
		# If this aircraft is AI-controlled, start AI launch state.
		# Player-retrieved aircraft should not auto-enable AI here.
		var ai_toggle = aircraft.find_child("AIToggle", true, false)
		var ai_is_active: bool = false
		if ai_toggle and "ai_active" in ai_toggle:
			ai_is_active = bool(ai_toggle.ai_active)
		if ai_is_active:
			var ai_pilot = aircraft.get_node_or_null("AIPilot")
			if ai_pilot and ai_pilot.has_method("launch"):
				ai_pilot.launch()
	else:
		pass

func _is_non_aircraft_body(node: Node) -> bool:
	if not is_instance_valid(node):
		return true
	return bool(node.get_meta("non_aircraft_body", false)) \
			or bool(node.get_meta("ejected_pilot_camera_target", false)) \
			or node.is_in_group("ejected_pilots")

func queue_ai_flight(
	count: int,
	ops: Node,
	loadout_profile: String = "",
	aircraft_model: String = ""
) -> int:
	"""Request FlightOps to launch `count` AI aircraft one after another.
	Each successful launch calls ops.notify_aircraft_launched(pilot)."""
	if _landing_test_active:
		_ai_launch_queue = 0
		_pending_flight_ops = null
		_retrieval_ai_land_after_launch = true
		_pending_ai_loadout_profile = ""
		_pending_ai_aircraft_kind = "fixed_wing"
		_pending_ai_aircraft_model = ""
		return 0
	if not _can_accept_ai_ops_launch_request():
		return 0
	var available := mini(count, _count_stored_aircraft_for_kind("fixed_wing", aircraft_model))
	if available <= 0:
		push_warning("[FlightDeckManager] queue_ai_flight: hangar empty")
		return 0
	_ai_launch_queue = available
	_pending_flight_ops = ops
	_retrieval_ai_land_after_launch = false
	_pending_ai_loadout_profile = loadout_profile
	_pending_ai_aircraft_kind = "fixed_wing"
	_pending_ai_aircraft_model = aircraft_model
	if current_state == DeckState.IDLE:
		_launch_next_queued_ai()
	return available


func queue_ai_helicopters(count: int, ops: Node, aircraft_model: String = "") -> int:
	## Launch utility helicopters through the real elevator/deck flow.  Unlike a
	## fighter scramble, these aircraft bypass the catapult and lift vertically.
	if _landing_test_active:
		return 0
	if not _can_accept_ai_ops_launch_request():
		return 0
	var available := mini(count, _count_stored_aircraft_for_kind("helicopter", aircraft_model))
	if available <= 0:
		push_warning("[FlightDeckManager] queue_ai_helicopters: no helicopters in hangar")
		return 0
	_ai_launch_queue = available
	_pending_flight_ops = ops
	_retrieval_ai_land_after_launch = false
	_pending_ai_loadout_profile = ""
	_pending_ai_aircraft_kind = "helicopter"
	_pending_ai_aircraft_model = aircraft_model
	if current_state == DeckState.IDLE:
		_launch_next_queued_ai()
	return available


func can_queue_ai_helicopters(aircraft_model: String = "") -> bool:
	## Rescue tasking polls this rather than overwriting another deck operation.
	return _can_accept_ai_ops_launch_request() \
			and _count_stored_aircraft_for_kind("helicopter", aircraft_model) > 0


func _can_accept_ai_ops_launch_request() -> bool:
	return not _landing_test_active \
			and current_state == DeckState.IDLE \
			and _ai_launch_queue <= 0 \
			and _pending_flight_ops == null

func _launch_next_queued_ai() -> void:
	if _landing_test_active:
		_ai_launch_queue = 0
		_pending_flight_ops = null
		_retrieval_ai_land_after_launch = true
		_pending_ai_loadout_profile = ""
		_pending_ai_aircraft_kind = "fixed_wing"
		_pending_ai_aircraft_model = ""
		return
	if _ai_launch_queue <= 0 or stored_aircraft.is_empty():
		_ai_launch_queue = 0
		_pending_flight_ops = null
		_retrieval_ai_land_after_launch = true
		_pending_ai_loadout_profile = ""
		_pending_ai_aircraft_kind = "fixed_wing"
		_pending_ai_aircraft_model = ""
		return
	# Recovery traffic owns the deck once an aircraft has requested clearance.
	# Keep the launch queued instead of retrieving it ahead of an active holder,
	# a waiting recovery, or an arrested aircraft still being stored.
	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	if is_instance_valid(_pending_store_aircraft) \
			or is_instance_valid(_landing_clearance_aircraft) \
			or not _landing_clearance_queue.is_empty():
		return
	_ai_launch_queue -= 1
	start_hangar_retrieval()

func _on_catapult_sequence_complete():
	# Notify FlightOps about the aircraft that just launched
	if _pending_flight_ops and is_instance_valid(deck_aircraft):
		var pilot = deck_aircraft.get_node_or_null("AIPilot")
		_notify_pending_ops_launched(pilot)

	current_state = DeckState.IDLE
	deck_aircraft = null

	# Continue queued AI launches if more are pending
	if _ai_launch_queue > 0:
		_launch_next_queued_ai()
	elif _pending_flight_ops != null:
		_pending_flight_ops = null
		_retrieval_ai_land_after_launch = true
		_pending_ai_loadout_profile = ""
		_pending_ai_aircraft_kind = "fixed_wing"
		_pending_ai_aircraft_model = ""

func _on_catapult_sequence_aborted():
	if is_instance_valid(deck_aircraft):
		if deck_aircraft.has_meta("controls_disabled"):
			deck_aircraft.remove_meta("controls_disabled")
	_return_tractors_to_staging()
	_ai_launch_queue = 0
	_pending_flight_ops = null
	_retrieval_ai_land_after_launch = true
	_pending_ai_loadout_profile = ""
	_pending_ai_aircraft_kind = "fixed_wing"
	_pending_ai_aircraft_model = ""
	current_state = DeckState.IDLE
	deck_aircraft = null


func _notify_pending_ops_launched(pilot: Node) -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	if _pending_flight_ops != null \
			and is_instance_valid(_pending_flight_ops) \
			and _pending_flight_ops.has_method("notify_aircraft_launched"):
		_pending_flight_ops.call("notify_aircraft_launched", pilot)

# --- Arresting cable integration ---
func _on_cable_engaged(aircraft_variant: Variant) -> void:
	if not is_instance_valid(aircraft_variant):
		_recovery_debug("cable engaged ignored: invalid aircraft")
		return
	var aircraft := aircraft_variant as RigidBody3D
	if not is_instance_valid(aircraft):
		_recovery_debug("cable engaged ignored: non-aircraft node")
		return
	release_landing_clearance(aircraft)
	# Landing test mode: cable catch despawns the test aircraft after a short pause.
	if _landing_test_aircraft.has(aircraft):
		# Score tracking — per-aircraft detail is printed by AIPilot's CAUGHT snap
		var cable: Node = null
		if aircraft.has_meta("arresting_cable"):
			cable = aircraft.get_meta("arresting_cable")
		var wire_num: int = 2
		var lateral_m: float = 0.0
		if cable and cable.has_method("get_wire_number"):
			wire_num = cable.get_wire_number()
		if cable and cable.has_method("get_engage_lateral_m"):
			lateral_m = cable.get_engage_lateral_m()
		var base_pts: float = 10.0 if wire_num == 2 else 5.0
		var lat_factor: float = clamp(1.0 - abs(lateral_m) / LANDING_WIRE_HALF_WIDTH_M, 0.0, 1.0)
		record_landing_test_outcome(aircraft, "CAUGHT", base_pts * lat_factor)
		print("[LandingTest] cable caught — despawning %s" % _aircraft_debug_name(aircraft))
		return

	deck_aircraft = aircraft
	current_state = DeckState.RECOVERY_IN_PROGRESS
	_recovery_powerdown_in_progress = true
	_recovery_release_done = false
	_recovery_job_dispatched = false
	_recovery_debug("cable engaged by %s" % _aircraft_debug_name(aircraft))
	if is_instance_valid(aircraft):
		aircraft.set_meta("controls_disabled", true)
		aircraft.set_meta("arresting_hold_until_manual_release", true)
		_call_power_down_sequence(aircraft)

func _deferred_release_cable(_cable: Node) -> void:
	# no-op now; timing handled by _call_power_down_sequence
	pass

func _on_cable_released(aircraft_variant: Variant) -> void:
	if not is_instance_valid(aircraft_variant):
		_recovery_debug("cable released ignored: invalid aircraft")
		return
	var aircraft := aircraft_variant as RigidBody3D
	if not is_instance_valid(aircraft):
		_recovery_debug("cable released ignored: non-aircraft node")
		return
	_recovery_debug("cable released signal for %s" % _aircraft_debug_name(aircraft))
	var tailhook = _find_tailhook(aircraft)
	if is_instance_valid(tailhook) and tailhook.has_method("stow"):
		tailhook.stow()
	if current_state == DeckState.RECOVERY_IN_PROGRESS and deck_aircraft == aircraft and not _recovery_job_dispatched:
		start_post_arrest_recovery(aircraft)

func _dispatch_recovery_job() -> void:
	"""Move aircraft to elevator using simple movement and visual tractorbots"""
	if not is_instance_valid(deck_aircraft) or not is_instance_valid(elevator_pickup_marker):
		_recovery_debug("cannot dispatch recovery: aircraft_valid=%s pickup_marker_valid=%s" % [
			str(is_instance_valid(deck_aircraft)),
			str(is_instance_valid(elevator_pickup_marker))
		])
		return
	if _recovery_job_dispatched:
		_recovery_debug("recovery dispatch ignored: job already dispatched")
		return
	
	_recovery_job_dispatched = true
	_recovery_debug("dispatch recovery job")
	await _prepare_tractorbots_for_recovery_job()
	if not is_instance_valid(deck_aircraft):
		_recovery_debug("recovery dispatch aborted after tractor prep: aircraft no longer valid")
		return
	_recovery_debug("tractor prep complete; moving aircraft to elevator")
	_move_aircraft_to_elevator(deck_aircraft)

# Timed power-down and release sequence
func _call_power_down_sequence(ac: RigidBody3D) -> void:
	var engine = _find_engine(ac)
	var steps := 6
	for i in steps:
		if not is_instance_valid(ac):
			break
		var t := 1.0 - float(i + 1) / float(steps)
		if is_instance_valid(engine) and engine.has_method("set_throttle_input"):
			engine.set_throttle_input(max(0.0, t))
		await get_tree().create_timer(0.5).timeout
	# Ensure full stop
	if is_instance_valid(engine):
		if engine.has_method("engine_stop"):
			engine.engine_stop()
		elif engine.has_method("set_throttle_input"):
			engine.set_throttle_input(0.0)
	# Wait additional 3s before releasing cable
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(ac):
		_recovery_powerdown_in_progress = false
		_recovery_release_done = true
		return
	_perform_cable_release(ac)
	_recovery_powerdown_in_progress = false
	_recovery_release_done = true

func _perform_cable_release(ac_variant: Variant) -> void:
	if not is_instance_valid(ac_variant):
		return
	var ac_obj: Object = ac_variant as Object
	if ac_obj == null:
		return
	var ac_node: Node = ac_obj as Node
	if ac_node == null:
		return
	if not (ac_node is RigidBody3D):
		return
	var ac: RigidBody3D = ac_node as RigidBody3D
	if not is_instance_valid(ac):
		return
	ac.set_meta("parking_brake", true)
	var cable = ac.get_meta("arresting_cable") if ac.has_meta("arresting_cable") else null
	if cable and cable.has_method("manual_release"):
		cable.manual_release()
	# Ensure tailhook is stowed even if the signal is missed
	var th = _find_tailhook(ac)
	if is_instance_valid(th) and th.has_method("stow"):
		th.stow()
	_stabilize_aircraft_for_recovery_pickup(ac)
	_recovery_debug("manual cable release complete; dispatching tractor recovery")
	_dispatch_recovery_job()
	
	# Set aircraft as pending for storage
	_pending_store_aircraft = ac
	_recovery_debug("pending store aircraft set after cable release")

# --- Fallback polling and safety checks ---
func _physics_process(_delta: float) -> void:
	var _profiler_start: int = FrameProfiler.begin("FlightDeckManager.physics")
	# Pump a pending AI launch queue if it was requested while the deck was busy. queue_ai_flight() only
	# kicks off the launch if the deck was IDLE at request time; without this, a scramble that arrives
	# during vehicle deploy / another op sits queued forever (AirOps flights never launch).
	if _ai_launch_queue > 0 and current_state == DeckState.IDLE and not _landing_test_active and not stored_aircraft.is_empty():
		_launch_next_queued_ai()
	# 1. Safety Check: If an operation is active, verify the aircraft still exists and is on the deck
	if current_state == DeckState.LAUNCH_IN_PROGRESS or current_state == DeckState.RECOVERY_IN_PROGRESS:
		if not is_instance_valid(deck_aircraft):
			_abort_current_sequence()
		else:
			var deck_y = _get_deck_height_y()
			# If aircraft falls 10m below the deck, it fell off
			if deck_aircraft.global_position.y < deck_y - 10.0:
				# Allow the player/AI to fly away if they fell off, but free up the deck state
				if deck_aircraft.has_meta("controls_disabled"):
					deck_aircraft.remove_meta("controls_disabled")
				_abort_current_sequence()

	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	_prune_recent_helicopter_landing_hold()
	_update_landing_clearance_timeout(_delta)
	var landing_blocker := _find_landing_deck_blocker()
	var deck_blocked_by_aircraft: bool = is_instance_valid(landing_blocker)
	var recent_helicopter_landing_active := _is_recent_helicopter_landing_hold_active()
	if current_state in [DeckState.IDLE, DeckState.AIRCRAFT_ON_DECK]:
		landing_deck_active = deck_blocked_by_aircraft \
				or recent_helicopter_landing_active \
				or is_instance_valid(_landing_clearance_aircraft) \
				or not _landing_clearance_queue.is_empty()
		if deck_blocked_by_aircraft and current_state == DeckState.IDLE:
			current_state = DeckState.AIRCRAFT_ON_DECK
		elif not deck_blocked_by_aircraft and current_state == DeckState.AIRCRAFT_ON_DECK:
			current_state = DeckState.IDLE
	else:
		landing_deck_active = true
	_update_landing_blocker_cleanup(_delta, landing_blocker)
	_grant_next_landing_clearance_if_possible()

	# 2. Polling for unmanaged arrests
	if current_state != DeckState.RECOVERY_IN_PROGRESS and not _recovery_powerdown_in_progress:
		var ac = _find_arrested_aircraft()
		if ac:
			_recovery_debug("polling found arrested aircraft %s" % _aircraft_debug_name(ac))
			_on_cable_engaged(ac)
			FrameProfiler.end("FlightDeckManager.physics", _profiler_start)
			return

	# 3. Fallback for manual player landings that stop in the aft recovery zone
	if auto_recovery_enabled and current_state in [DeckState.IDLE, DeckState.AIRCRAFT_ON_DECK]:
		var recovery_candidate := _find_stopped_aircraft_in_recovery_zone()
		if recovery_candidate and recovery_candidate != _pending_store_aircraft:
			_recovery_debug("auto recovery selected stopped aircraft %s" % _aircraft_debug_name(recovery_candidate))
			start_post_arrest_recovery(recovery_candidate)
			FrameProfiler.end("FlightDeckManager.physics", _profiler_start)
			return

	if current_state == DeckState.IDLE and not _tractor_cleanup_in_progress:
		_maybe_dispatch_extra_tractor_cleanup()

	if current_state == DeckState.IDLE and _ai_launch_queue > 0 and not _tractor_cleanup_in_progress \
			and not _tractor_elevator_transfer_in_progress:
		_launch_next_queued_ai()

	# Landing test mode: spawn on a fixed cadence; older attempts may still be airborne.
	if _landing_test_active:
		# Despawn test aircraft that have left the landing state and drifted far from the carrier
		var carrier_node_t := get_tree().get_first_node_in_group("carrier") as Node3D
		if is_instance_valid(carrier_node_t):
			var to_despawn: Array[RigidBody3D] = []
			for ac in _landing_test_aircraft:
				if not is_instance_valid(ac):
					to_despawn.append(ac)
					continue
				var pilot = ac.find_child("AIPilot", true, false)
				var in_landing: bool = is_instance_valid(pilot) and \
						pilot.get("current_state") == AIPilot.State.LANDING
				if not in_landing and ac.global_position.distance_to(carrier_node_t.global_position) > 250.0:
					to_despawn.append(ac)
			for ac in to_despawn:
				if is_instance_valid(ac):
					# 0 pts for bolter/wave-off/crash — per-aircraft detail already printed by AIPilot
					record_landing_test_outcome(ac, "STRAY", 0.0)
					print("[LandingTest] despawning stray %s" % ac.name)
				else:
					_landing_test_aircraft.erase(ac)
		_landing_test_timer -= _delta
		if _landing_test_timer <= 0.0:
			_landing_test_timer = LANDING_TEST_INTERVAL_S
			_spawn_landing_test_aircraft()

	if _heli_test_active:
		_heli_test_dummy_retry_s -= _delta
		if _heli_test_dummy_retry_s <= 0.0:
			_heli_test_dummy_retry_s = HELI_TEST_DUMMY_RETRY_S
			_ensure_dummy_turrets_for_test()
		_heli_test_timer -= _delta
		if _heli_test_timer <= 0.0:
			_heli_test_timer = HELI_TEST_INTERVAL_S
			_fill_heli_test_population()
	if _heli_navigation_test_active:
		_heli_navigation_test_timer_s -= _delta
		if _heli_navigation_test_timer_s <= 0.0:
			_heli_navigation_test_timer_s = HELI_NAVIGATION_RETRY_S
			_ensure_heli_navigation_test_aircraft()
		_update_navigation_report(_delta)
	if _heli_test_active or _heli_navigation_test_active:
		_heli_ui_update_accum_s -= _delta
		if _heli_ui_update_accum_s <= 0.0:
			_heli_ui_update_accum_s = 0.25
			_update_physical_test_ui()
	FrameProfiler.end("FlightDeckManager.physics", _profiler_start)


func _get_heli_test_aircraft_key(craft_ref: Variant) -> String:
	var search_text := ""
	if craft_ref is RigidBody3D:
		var aircraft := craft_ref as RigidBody3D
		if aircraft.has_meta(HELI_TEST_TYPE_META):
			var meta_key := str(aircraft.get_meta(HELI_TEST_TYPE_META))
			if _heli_test_stats.has(meta_key):
				return meta_key
		search_text = "%s %s" % [aircraft.name, aircraft.scene_file_path]
	elif craft_ref is Dictionary:
		var dict_ref: Dictionary = craft_ref
		search_text = "%s %s" % [str(dict_ref.get("name", "")), str(dict_ref.get("scene_file", ""))]
	else:
		search_text = str(craft_ref)
	var lower_text := search_text.to_lower()
	for key in ["Aircraft_9", "Aircraft_10", "Aircraft_11"]:
		if lower_text.find(key.to_lower()) != -1:
			return key
	return ""


func record_heli_stat(craft_ref: Variant, stat: String) -> void:
	if not (_heli_test_active or _heli_navigation_test_active):
		return
	var base_name := _get_heli_test_aircraft_key(craft_ref)
	if base_name == "":
		return
	if not _heli_test_stats[base_name].has(stat):
		return
	if craft_ref is RigidBody3D:
		var aircraft := craft_ref as RigidBody3D
		var stat_meta := "%s%s" % [HELI_TEST_STAT_META_PREFIX, stat]
		if bool(aircraft.get_meta(stat_meta, false)):
			return
		aircraft.set_meta(stat_meta, true)
		aircraft.set_meta(HELI_TEST_TYPE_META, base_name)
		aircraft.set_meta(HELI_TEST_UNLIMITED_AMMO_META, true)
	_heli_test_stats[base_name][stat] += 1

func _abort_current_sequence() -> void:
	# Called when a safety check fails (plane destroyed or fell off)
	_return_tractors_to_staging()
	_recovery_powerdown_in_progress = false
	_recovery_release_done = false
	_recovery_job_dispatched = false
	deck_aircraft = null
	_pending_store_aircraft = null
	_landing_clearance_aircraft = null
	_landing_clearance_queue.clear()
	_reset_landing_blocker_cleanup()
	if catapult and catapult.has_method("_reset_state"):
		catapult._reset_state()
	current_state = DeckState.IDLE

func _find_arrested_aircraft() -> RigidBody3D:
	for group in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in get_tree().get_nodes_in_group(group):
			if not (node is RigidBody3D):
				continue
			var aircraft := node as RigidBody3D
			if not is_instance_valid(aircraft):
				continue
			if aircraft.has_meta("arresting_engaged") and bool(aircraft.get_meta("arresting_engaged")):
				return aircraft
	return null

func _find_stopped_aircraft_in_recovery_zone() -> RigidBody3D:
	for group in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in get_tree().get_nodes_in_group(group):
			if not (node is RigidBody3D):
				continue
			var aircraft := node as RigidBody3D
			if not is_instance_valid(aircraft):
				continue
			var in_transport := aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode"))
			if _is_helicopter_aircraft(aircraft):
				# Helicopters set carrier_transport_mode when parked — don't skip them.
				if _is_helicopter_ready_for_deck_recovery(aircraft):
					return aircraft
				continue
			if in_transport:
				continue
			var controls_disabled := aircraft.has_meta("controls_disabled") and bool(aircraft.get_meta("controls_disabled"))
			var arresting_engaged := aircraft.has_meta("arresting_engaged") and bool(aircraft.get_meta("arresting_engaged"))
			var parking_brake := aircraft.has_meta("parking_brake") and bool(aircraft.get_meta("parking_brake"))
			if controls_disabled and not arresting_engaged and not parking_brake:
				continue
			if aircraft.linear_velocity.length() > auto_recovery_speed_threshold_mps:
				continue
			if _is_aircraft_in_auto_recovery_zone(aircraft):
				var carrier := get_parent() as Node3D
				var local_pos := carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
				_recovery_debug("candidate in recovery zone %s speed=%.2f local=%s" % [
					_aircraft_debug_name(aircraft),
					aircraft.linear_velocity.length(),
					_fmt_vec3(local_pos)
				])
				return aircraft
	return null

func _is_helicopter_ready_for_deck_recovery(aircraft: RigidBody3D) -> bool:
	if not is_instance_valid(aircraft):
		return false
	if aircraft.has_meta("helicopter_deck_takeoff_ready") and bool(aircraft.get_meta("helicopter_deck_takeoff_ready")):
		return false
	if aircraft.has_meta("controls_disabled") and bool(aircraft.get_meta("controls_disabled")):
		return false
	if not _is_helicopter_on_carrier_deck_for_recovery(aircraft):
		return false
	# Accept a parked helicopter (parking_brake set, near-zero relative speed) even
	# if the engine is still spinning down — the pilot already zeroed collective/power.
	# A braked helicopter can be anywhere on deck (not just the fixed-wing recovery zone).
	var has_brake := aircraft.has_meta("parking_brake") and bool(aircraft.get_meta("parking_brake"))
	var relative_speed := _get_aircraft_carrier_relative_speed(aircraft)
	if not has_brake:
		if not _is_helicopter_engine_stopped(aircraft):
			return false
		if not _is_aircraft_blocking_landing_deck(aircraft):
			return false
	if relative_speed > auto_recovery_speed_threshold_mps:
		return false
	var carrier := get_parent() as Node3D
	var local_pos := carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
	_recovery_debug("helicopter ready for deck recovery %s rel_speed=%.2f local=%s" % [
		_aircraft_debug_name(aircraft),
		relative_speed,
		_fmt_vec3(local_pos)
	])
	return true

func _is_helicopter_on_carrier_deck_for_recovery(aircraft: RigidBody3D) -> bool:
	if not is_instance_valid(aircraft):
		return false
	if aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode")):
		return true
	if _is_aircraft_blocking_landing_deck(aircraft):
		return true
	if _is_aircraft_in_auto_recovery_zone(aircraft):
		return true
	return false

func _is_helicopter_engine_stopped(aircraft: RigidBody3D) -> bool:
	var engine := aircraft.find_child("Engine", true, false)
	if engine == null:
		return aircraft.has_meta("parking_brake") and bool(aircraft.get_meta("parking_brake"))
	var working = engine.get("is_engine_working")
	if working != null and bool(working):
		return false
	var target_power = engine.get("target_power")
	if target_power != null and float(target_power) > 0.01:
		return false
	return true

func _get_aircraft_carrier_relative_speed(aircraft: RigidBody3D) -> float:
	var reference_velocity := _get_aircraft_reference_velocity(aircraft)
	if reference_velocity.length_squared() <= 0.0001:
		var carrier := get_parent()
		if carrier is Node:
			reference_velocity = _get_node_velocity(carrier as Node)
	var relative_velocity := aircraft.linear_velocity - reference_velocity
	return Vector2(relative_velocity.x, relative_velocity.z).length()

func _get_aircraft_reference_velocity(aircraft: RigidBody3D) -> Vector3:
	if aircraft.has_meta(MOTION_REFERENCE_NODE_META):
		var reference = aircraft.get_meta(MOTION_REFERENCE_NODE_META)
		if reference is Node and is_instance_valid(reference):
			return _get_node_velocity(reference as Node)
	if aircraft.has_meta(MOTION_REFERENCE_VELOCITY_META):
		var velocity = aircraft.get_meta(MOTION_REFERENCE_VELOCITY_META)
		if typeof(velocity) == TYPE_VECTOR3:
			return velocity as Vector3
	if aircraft.has_meta(LEGACY_CARRIER_VELOCITY_META):
		var legacy_velocity = aircraft.get_meta(LEGACY_CARRIER_VELOCITY_META)
		if typeof(legacy_velocity) == TYPE_VECTOR3:
			return legacy_velocity as Vector3
	return Vector3.ZERO

func _set_aircraft_reference_node(aircraft: RigidBody3D, reference_node: Node) -> void:
	if not is_instance_valid(aircraft) or not is_instance_valid(reference_node):
		return
	var reference_velocity := _get_node_velocity(reference_node)
	aircraft.set_meta(MOTION_REFERENCE_NODE_META, reference_node)
	aircraft.set_meta(MOTION_REFERENCE_VELOCITY_META, reference_velocity)
	aircraft.set_meta(LEGACY_CARRIER_VELOCITY_META, reference_velocity)

func _set_manual_transport(node: Node, enabled: bool) -> void:
	if not is_instance_valid(node):
		return
	if enabled:
		node.set_meta(MANUAL_TRANSPORT_META, true)
	elif node.has_meta(MANUAL_TRANSPORT_META):
		node.remove_meta(MANUAL_TRANSPORT_META)

func _sync_rigidbody_transform_state(body: RigidBody3D) -> void:
	if not is_instance_valid(body):
		return
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)

func _get_node_velocity(node: Node) -> Vector3:
	if node is RigidBody3D:
		return (node as RigidBody3D).linear_velocity
	if node.has_method("get_deck_reference_velocity_vector"):
		var deck_velocity = node.call("get_deck_reference_velocity_vector")
		if typeof(deck_velocity) == TYPE_VECTOR3:
			return deck_velocity as Vector3
	if node is CharacterBody3D:
		return (node as CharacterBody3D).velocity
	if node.has_method("get_velocity_vector"):
		var velocity = node.call("get_velocity_vector")
		if typeof(velocity) == TYPE_VECTOR3:
			return velocity as Vector3
	var property_velocity = node.get("velocity")
	if typeof(property_velocity) == TYPE_VECTOR3:
		return property_velocity as Vector3
	return Vector3.ZERO

func _is_aircraft_in_auto_recovery_zone(aircraft: RigidBody3D) -> bool:
	var carrier := get_parent() as Node3D
	if carrier == null:
		return false
	var local_pos := carrier.to_local(aircraft.global_position)
	var deck_y := _get_deck_height_y()
	if absf(aircraft.global_position.y - deck_y) > auto_recovery_zone_height_margin_m:
		return false
	if absf(local_pos.x) > auto_recovery_zone_half_width_m:
		return false
	return local_pos.z >= auto_recovery_zone_min_local_z and local_pos.z <= auto_recovery_zone_max_local_z

func _get_all_aircraft_nodes() -> Array[RigidBody3D]:
	var all_aircraft: Array[RigidBody3D] = []
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is RigidBody3D):
				continue
			var aircraft := node as RigidBody3D
			if not is_instance_valid(aircraft):
				continue
			if _is_non_aircraft_body(aircraft):
				continue
			var id := aircraft.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			all_aircraft.append(aircraft)
	return all_aircraft

func _is_helicopter_currently_landing_on_carrier(aircraft: RigidBody3D) -> bool:
	if not is_instance_valid(aircraft):
		return false
	if _is_landing_clearance_aircraft_stale(aircraft):
		return false
	if aircraft.has_meta("carrier_landing_final_active") and bool(aircraft.get_meta("carrier_landing_final_active")):
		return true
	var pilot := aircraft.find_child("HelicopterPilot", true, false)
	if not is_instance_valid(pilot):
		return false
	var landing_on_carrier_variant: Variant = pilot.get("_landing_on_carrier")
	if landing_on_carrier_variant is bool and bool(landing_on_carrier_variant):
		return true
	var carrier_approach_phase_variant: Variant = pilot.get("_carrier_approach_phase")
	return carrier_approach_phase_variant is int and int(carrier_approach_phase_variant) != 0

func _is_aircraft_blocking_landing_deck(aircraft: RigidBody3D, requester: RigidBody3D = null) -> bool:
	if not is_instance_valid(aircraft) or aircraft == requester:
		return false
	if _is_landing_clearance_aircraft_stale(aircraft):
		return false
	if aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode")):
		return false
	var carrier := get_parent() as Node3D
	if carrier == null:
		return false
	var local_pos := carrier.to_local(aircraft.global_position)
	var deck_y := _get_deck_height_y()
	if absf(aircraft.global_position.y - deck_y) > landing_deck_block_height_margin_m:
		return false
	if absf(local_pos.x) > landing_deck_block_half_width_m:
		return false
	return local_pos.z >= landing_deck_block_min_local_z and local_pos.z <= landing_deck_block_max_local_z

func _is_aircraft_physically_in_landing_deck_rectangle(aircraft: RigidBody3D, requester: RigidBody3D = null) -> bool:
	if not is_instance_valid(aircraft) or aircraft == requester:
		return false
	if _is_landing_clearance_aircraft_stale(aircraft):
		return false
	if aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode")):
		return false
	var carrier := get_parent() as Node3D
	if carrier == null:
		return false
	var local_pos := carrier.to_local(aircraft.global_position)
	var deck_y := _get_deck_height_y()
	if absf(aircraft.global_position.y - deck_y) > landing_deck_block_height_margin_m:
		return false
	if absf(local_pos.x) > landing_deck_block_half_width_m:
		return false
	return local_pos.z >= landing_deck_block_min_local_z and local_pos.z <= landing_deck_block_max_local_z

func _find_landing_deck_blocker(requester: RigidBody3D = null) -> RigidBody3D:
	for aircraft in _get_all_aircraft_nodes():
		if _is_aircraft_blocking_landing_deck(aircraft, requester) \
				or _is_aircraft_physically_in_landing_deck_rectangle(aircraft, requester):
			return aircraft
	return null


func is_aircraft_physically_settled_on_landing_deck(aircraft: RigidBody3D) -> bool:
	## Authoritative physical touchdown check shared with helicopter landing logic.
	## This deliberately does not depend on LandingGear's carrier-surface probe:
	## the skid collision can be resting on the deck even if a short centre ray
	## momentarily misses while the helicopter rocks after touchdown.
	if not is_instance_valid(aircraft):
		return false
	if not _is_aircraft_physically_in_landing_deck_rectangle(aircraft):
		return false
	if not _landing_blocker_has_deck_contact(aircraft):
		return false
	if _get_aircraft_carrier_relative_speed(aircraft) \
			> maxf(landing_blocker_cleanup_speed_threshold_mps, 0.0):
		return false

	var reference_velocity := _get_aircraft_reference_velocity(aircraft)
	if reference_velocity.length_squared() <= 0.0001:
		var carrier := get_parent()
		if carrier is Node:
			reference_velocity = _get_node_velocity(carrier as Node)
	var relative_vertical_speed := aircraft.linear_velocity.y - reference_velocity.y
	if absf(relative_vertical_speed) > maxf(settled_touchdown_vertical_speed_threshold_mps, 0.0):
		return false

	var up_axis := aircraft.global_transform.basis.y
	if up_axis.length_squared() <= 0.0001:
		return false
	return up_axis.normalized().dot(Vector3.UP) >= clampf(settled_touchdown_min_upright_dot, -1.0, 1.0)

func _reset_landing_blocker_cleanup() -> void:
	_landing_blocker_aircraft = null
	_landing_blocker_elapsed_s = 0.0
	_landing_blocker_cleanup_dispatched = false

func _landing_blocker_cleanup_has_landing_pressure(blocker: RigidBody3D) -> bool:
	if is_instance_valid(_landing_clearance_aircraft):
		return true
	if not _landing_clearance_queue.is_empty():
		return true
	# If the blocker itself has already landed and is waiting on the deck, clearing it is
	# useful even before the next aircraft asks for clearance.
	return is_instance_valid(blocker) and _is_helicopter_ready_for_deck_recovery(blocker)

func _landing_blocker_has_deck_contact(blocker: RigidBody3D) -> bool:
	if not is_instance_valid(blocker):
		return false
	if blocker.has_meta("carrier_transport_mode") and bool(blocker.get_meta("carrier_transport_mode")):
		return true
	if blocker.has_meta("parking_brake") and bool(blocker.get_meta("parking_brake")):
		return true
	var deck_y := _get_deck_height_y()
	var contact_margin := maxf(landing_blocker_cleanup_deck_contact_margin_m, 0.0)
	var gear_nodes := _find_gear_colliders(blocker)
	if gear_nodes.is_empty():
		gear_nodes = _get_launch_wheel_nodes(blocker)
	if gear_nodes.is_empty():
		return absf(blocker.global_position.y - deck_y) <= contact_margin
	for gear in gear_nodes:
		if is_instance_valid(gear) and absf((gear as Node3D).global_position.y - deck_y) <= contact_margin:
			return true
	return false

func _update_landing_blocker_cleanup(delta: float, blocker: RigidBody3D) -> void:
	if not landing_blocker_cleanup_enabled:
		_reset_landing_blocker_cleanup()
		return
	if current_state not in [DeckState.IDLE, DeckState.AIRCRAFT_ON_DECK]:
		_reset_landing_blocker_cleanup()
		return
	if not is_instance_valid(blocker):
		_reset_landing_blocker_cleanup()
		return
	if blocker == deck_aircraft or blocker == _pending_store_aircraft:
		_reset_landing_blocker_cleanup()
		return
	if _landing_blocker_cleanup_dispatched:
		return
	if not _landing_blocker_cleanup_has_landing_pressure(blocker):
		_reset_landing_blocker_cleanup()
		return
	var relative_speed := _get_aircraft_carrier_relative_speed(blocker)
	if relative_speed > maxf(landing_blocker_cleanup_speed_threshold_mps, 0.0):
		_reset_landing_blocker_cleanup()
		return
	if not _landing_blocker_has_deck_contact(blocker):
		_reset_landing_blocker_cleanup()
		return
	if _landing_blocker_aircraft != blocker:
		_landing_blocker_aircraft = blocker
		_landing_blocker_elapsed_s = 0.0
		_recovery_debug("landing blocker cleanup armed for %s" % _aircraft_debug_name(blocker))
	_landing_blocker_elapsed_s += maxf(delta, 0.0)
	if _landing_blocker_elapsed_s < maxf(landing_blocker_cleanup_timeout_s, 0.0):
		return
	_landing_blocker_cleanup_dispatched = true
	_recovery_debug("landing blocker cleanup dispatching tractor recovery for %s after %.1fs" % [
		_aircraft_debug_name(blocker),
		_landing_blocker_elapsed_s,
	])
	start_post_arrest_recovery(blocker)

func _landing_deck_state_busy_for_clearance() -> bool:
	return current_state in [
		DeckState.LAUNCH_IN_PROGRESS,
		DeckState.RECOVERY_IN_PROGRESS,
		DeckState.STORING_IN_HANGAR,
		DeckState.RETRIEVING_FROM_HANGAR,
		DeckState.TRACTOR_CLEANUP
	]

func _can_grant_landing_clearance_to(requester: RigidBody3D = null) -> bool:
	# Clearance is deliberately generous: only an ACTUALLY BUSY deck (another launch/recovery/hangar
	# op in progress) or actual physical traffic should hold a pilot off. Terrain-corridor and
	# carrier-settled were previously hard gates here, but the carrier patrols autonomously and can
	# spend long stretches never satisfying either (a smoothly curving route rarely drops yaw rate to
	# near-zero; a corridor sampled from whatever heading the carrier currently happens to be on is
	# essentially arbitrary relative to the aircraft's actual approach) -- that stranded pilots who had
	# survived their mission in an indefinite holding pattern with nothing else going on. AIPilot's own
	# recovery-approach logic already re-samples terrain along its real flight path via
	# _terrain_safe_altitude_for_segment once it starts the approach, so this deck-level pre-check was
	# redundant as a blocker, not the only safety net. _landing_path_clear_of_terrain() is kept for its
	# other caller (_queued_fixed_wing_recovery_has_clear_corridor / carrier motion constraint) -- only
	# its use as a clearance gate here is removed.
	if _landing_deck_state_busy_for_clearance():
		return false
	if _is_recent_helicopter_landing_hold_active(requester):
		return false
	for aircraft in _get_all_aircraft_nodes():
		if _is_aircraft_blocking_landing_deck(aircraft, requester) \
				or _is_aircraft_physically_in_landing_deck_rectangle(aircraft, requester):
			return false
	return true

func _is_landing_deck_busy(requester: RigidBody3D = null) -> bool:
	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	if is_instance_valid(_landing_clearance_aircraft):
		if requester == null or _landing_clearance_aircraft != requester:
			return true
	else:
		_landing_clearance_aircraft = null
		if not _landing_clearance_queue.is_empty() \
				and (requester == null or _landing_clearance_queue[0] != requester):
			return true
	return not _can_grant_landing_clearance_to(requester)

func can_accept_landing(requester: RigidBody3D = null) -> bool:
	var busy := _is_landing_deck_busy(requester)
	landing_deck_active = busy \
			or is_instance_valid(_landing_clearance_aircraft) \
			or not _landing_clearance_queue.is_empty()
	return not busy

func is_carrier_recovery_constraint_active() -> bool:
	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	return current_state == DeckState.RECOVERY_IN_PROGRESS \
			or (carrier_recovery_constraint_requires_active_clearance and _landing_clearance_aircraft_needs_carrier_constraint()) \
			or _queued_fixed_wing_recovery_has_clear_corridor() \
			or _launch_needs_carrier_constraint()

func is_launch_constraint_active() -> bool:
	## True when the carrier motion constraint is being driven by a pending LAUNCH (vs a landing recovery).
	## Lets the carrier keep moving straight for a launch instead of dead-stopping.
	return _launch_needs_carrier_constraint() \
			and current_state != DeckState.RECOVERY_IN_PROGRESS \
			and not _landing_clearance_aircraft_needs_carrier_constraint()

func _launch_needs_carrier_constraint() -> bool:
	## True when a launch is pending/underway and the carrier is still turning. This makes the carrier
	## STOP TURNING (and slow) to create a launch window, instead of deferring the launch indefinitely
	## while it patrols/turns. Straight deck = safe launch.
	if not launch_stop_carrier_to_launch:
		return false
	if not _has_pending_launch():
		return false
	# Hold the deck straight for the WHOLE pending launch (don't gate on currently-turning, or it would
	# oscillate: settle -> resume turn to waypoint -> turn again). Suppressed if there's a cliff ahead --
	# then let the carrier keep moving/turning to swing onto a clear heading before it commits to straight.
	if not _launch_path_clear_of_terrain():
		return false
	return true

func _has_pending_launch() -> bool:
	if _ai_launch_queue > 0:
		return true
	if current_state == DeckState.LAUNCH_IN_PROGRESS or current_state == DeckState.AIRCRAFT_ON_DECK:
		return true
	return false

func _landing_clearance_aircraft_needs_carrier_constraint() -> bool:
	if not is_instance_valid(_landing_clearance_aircraft):
		return false
	if _landing_clearance_aircraft.has_meta("carrier_fixed_wing_recovery_active") \
			and bool(_landing_clearance_aircraft.get_meta("carrier_fixed_wing_recovery_active")):
		return true
	if _is_helicopter_aircraft(_landing_clearance_aircraft):
		return false
	return _landing_clearance_aircraft.has_meta("carrier_landing_final_active") \
			and bool(_landing_clearance_aircraft.get_meta("carrier_landing_final_active"))

func get_carrier_recovery_speed_limit_mps() -> float:
	if not is_carrier_recovery_constraint_active():
		return INF
	return maxf(carrier_recovery_speed_limit_mps, 0.0)

func has_landing_clearance(requester: RigidBody3D) -> bool:
	_prune_landing_clearance_aircraft()
	return is_instance_valid(requester) \
			and is_instance_valid(_landing_clearance_aircraft) \
			and _landing_clearance_aircraft == requester

func _queue_landing_clearance_request(requester: RigidBody3D) -> void:
	if _is_landing_clearance_aircraft_stale(requester):
		return
	if _landing_clearance_queue.has(requester):
		return
	_landing_clearance_queue.append(requester)
	_recovery_debug("landing clearance queued for %s" % _aircraft_debug_name(requester))

func _remove_landing_clearance_request(requester: RigidBody3D) -> void:
	if requester == null:
		return
	for i in range(_landing_clearance_queue.size() - 1, -1, -1):
		if _landing_clearance_queue[i] == requester:
			_landing_clearance_queue.remove_at(i)

func _prune_landing_clearance_queue() -> void:
	_prune_landing_clearance_retry_cooldowns()
	for i in range(_landing_clearance_queue.size() - 1, -1, -1):
		if _is_landing_clearance_aircraft_stale(_landing_clearance_queue[i]):
			_recovery_debug("landing clearance removed stale queued aircraft %s" % _aircraft_debug_name(_landing_clearance_queue[i]))
			_landing_clearance_queue.remove_at(i)

func _prune_landing_clearance_retry_cooldowns() -> void:
	if _landing_clearance_retry_after_s.is_empty():
		return
	var now_s := Time.get_ticks_msec() / 1000.0
	for key in _landing_clearance_retry_after_s.keys():
		if float(_landing_clearance_retry_after_s[key]) <= now_s:
			_landing_clearance_retry_after_s.erase(key)

func _is_landing_clearance_request_on_cooldown(requester: RigidBody3D) -> bool:
	if not is_instance_valid(requester):
		return false
	var key := requester.get_instance_id()
	if not _landing_clearance_retry_after_s.has(key):
		return false
	return float(_landing_clearance_retry_after_s[key]) > Time.get_ticks_msec() / 1000.0

func _set_landing_clearance_retry_cooldown(requester: RigidBody3D) -> void:
	if not is_instance_valid(requester):
		return
	var cooldown_s := maxf(landing_clearance_retry_cooldown_s, 0.0)
	if cooldown_s <= 0.0:
		return
	_landing_clearance_retry_after_s[requester.get_instance_id()] = Time.get_ticks_msec() / 1000.0 + cooldown_s

func _prune_recent_helicopter_landing_hold() -> void:
	if _recent_helicopter_landing_hold_until_s <= 0.0:
		_recent_helicopter_landing_aircraft = null
		return
	var now_s := Time.get_ticks_msec() / 1000.0
	if now_s < _recent_helicopter_landing_hold_until_s:
		if is_instance_valid(_recent_helicopter_landing_aircraft) \
				and _recent_helicopter_landing_aircraft.is_queued_for_deletion():
			_recent_helicopter_landing_aircraft = null
		return
	_recent_helicopter_landing_aircraft = null
	_recent_helicopter_landing_hold_until_s = 0.0

func _is_recent_helicopter_landing_hold_active(requester: RigidBody3D = null) -> bool:
	_prune_recent_helicopter_landing_hold()
	if _recent_helicopter_landing_hold_until_s <= 0.0:
		return false
	if is_instance_valid(requester) \
			and is_instance_valid(_recent_helicopter_landing_aircraft) \
			and _recent_helicopter_landing_aircraft == requester:
		return false
	return true

func notify_helicopter_landed_on_carrier(aircraft: RigidBody3D) -> void:
	if not is_instance_valid(aircraft):
		return
	if not _is_helicopter_aircraft(aircraft):
		return
	var hold_s := maxf(helicopter_recent_landing_clearance_hold_s, 0.0)
	if hold_s <= 0.0:
		return
	_recent_helicopter_landing_aircraft = aircraft
	_recent_helicopter_landing_hold_until_s = Time.get_ticks_msec() / 1000.0 + hold_s
	landing_deck_active = true
	_recovery_debug("helicopter landing hold active for %.1fs after %s touchdown" % [
		hold_s,
		_aircraft_debug_name(aircraft),
	])

func _prune_landing_clearance_aircraft() -> void:
	if _landing_clearance_aircraft == null:
		_landing_clearance_elapsed_s = 0.0
		return
	if not _is_landing_clearance_aircraft_stale(_landing_clearance_aircraft):
		return
	_recovery_debug("landing clearance released stale holder %s" % _aircraft_debug_name(_landing_clearance_aircraft))
	_landing_clearance_aircraft = null
	_landing_clearance_elapsed_s = 0.0

func _update_landing_clearance_timeout(delta: float) -> void:
	if not is_instance_valid(_landing_clearance_aircraft):
		_landing_clearance_aircraft = null
		_landing_clearance_elapsed_s = 0.0
		return
	# Fixed-wing recovery includes a long outbound extension and intercept. Its pilot explicitly
	# releases clearance on bolter, abort, or destruction, so the generic queue timeout must not
	# rotate a second aircraft into the same approach while the first is still active.
	if _landing_clearance_aircraft.has_meta("carrier_fixed_wing_recovery_active") \
			and bool(_landing_clearance_aircraft.get_meta("carrier_fixed_wing_recovery_active")):
		_landing_clearance_elapsed_s = 0.0
		return
	var timeout_s := maxf(landing_clearance_timeout_s, 0.0)
	if timeout_s <= 0.0:
		return
	_landing_clearance_elapsed_s += maxf(delta, 0.0)
	if _landing_clearance_elapsed_s < timeout_s:
		return
	if _is_helicopter_currently_landing_on_carrier(_landing_clearance_aircraft):
		_landing_clearance_elapsed_s = 0.0
		return
	if _is_aircraft_blocking_landing_deck(_landing_clearance_aircraft):
		_landing_clearance_elapsed_s = timeout_s
		return
	var bumped := _landing_clearance_aircraft
	_landing_clearance_aircraft = null
	_landing_clearance_elapsed_s = 0.0
	if _landing_clearance_queue.is_empty():
		_set_landing_clearance_retry_cooldown(bumped)
		_recovery_debug("landing clearance timed out for %s; released (no queue waiting)" % _aircraft_debug_name(bumped))
	elif not _is_landing_clearance_aircraft_stale(bumped) and not _landing_clearance_queue.has(bumped):
		_landing_clearance_queue.append(bumped)
		_recovery_debug("landing clearance timed out for %s; moved to back of queue (%d waiting)" % [
			_aircraft_debug_name(bumped),
			_landing_clearance_queue.size(),
		])
	landing_deck_active = _is_landing_deck_busy()
	_grant_next_landing_clearance_if_possible()

func _is_landing_clearance_aircraft_stale(aircraft: RigidBody3D) -> bool:
	if not is_instance_valid(aircraft):
		return true
	if aircraft.is_queued_for_deletion():
		return true
	if _is_non_aircraft_body(aircraft):
		return true
	if not aircraft.is_inside_tree():
		return true
	if aircraft.has_meta("non_aircraft_body") and bool(aircraft.get_meta("non_aircraft_body")):
		return true
	if "current_health" in aircraft and float(aircraft.get("current_health")) <= 0.0:
		return true
	if "_has_exploded" in aircraft and bool(aircraft.get("_has_exploded")):
		return true
	var active_fixed_wing_recovery: bool = aircraft.has_meta(
		"carrier_fixed_wing_recovery_active"
	) and bool(aircraft.get_meta("carrier_fixed_wing_recovery_active"))
	var carrier := get_parent() as Node3D
	if not active_fixed_wing_recovery \
			and is_instance_valid(carrier) \
			and maxf(landing_clearance_abandon_radius_m, 0.0) > 0.0:
		# Fixed-wing recovery deliberately includes an outbound reversal that can
		# exceed the generic request radius. Its pilot owns explicit release on
		# wave-off, abort, destruction, and arrest; pruning that live clearance here
		# lets the carrier resume moving underneath a world-space arrival route.
		var carrier_to_aircraft := aircraft.global_position - carrier.global_position
		carrier_to_aircraft.y = 0.0
		if carrier_to_aircraft.length() > landing_clearance_abandon_radius_m:
			return true
	return false

func _grant_landing_clearance(requester: RigidBody3D) -> void:
	if _is_landing_clearance_aircraft_stale(requester):
		return
	_landing_clearance_aircraft = requester
	_landing_clearance_elapsed_s = 0.0
	_remove_landing_clearance_request(requester)
	landing_deck_active = true
	_recovery_debug("landing clearance granted to %s" % _aircraft_debug_name(requester))

func _grant_next_landing_clearance_if_possible() -> void:
	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	if is_instance_valid(_landing_clearance_aircraft):
		return
	if _landing_clearance_queue.is_empty():
		return
	var requester := _landing_clearance_queue[0]
	if not is_instance_valid(requester):
		_landing_clearance_queue.remove_at(0)
		return
	if _can_grant_landing_clearance_to(requester):
		_grant_landing_clearance(requester)

func request_landing_clearance(requester: RigidBody3D) -> bool:
	if not is_instance_valid(requester):
		return false
	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	if _is_landing_clearance_request_on_cooldown(requester):
		landing_deck_active = _is_landing_deck_busy()
		return false
	if has_landing_clearance(requester):
		return true
	if is_instance_valid(_landing_clearance_aircraft):
		_queue_landing_clearance_request(requester)
		landing_deck_active = true
		return false
	if not _landing_clearance_queue.is_empty():
		if not _landing_clearance_queue.has(requester):
			_queue_landing_clearance_request(requester)
		if _landing_clearance_queue[0] != requester:
			landing_deck_active = true
			return false
	if not _can_grant_landing_clearance_to(requester):
		_queue_landing_clearance_request(requester)
		landing_deck_active = true
		return false
	_grant_landing_clearance(requester)
	# _grant_landing_clearance() can still reject a requester that became stale between the
	# earlier checks and assignment. Never report clearance unless this manager owns it.
	return has_landing_clearance(requester)

func get_landing_queue_position(requester: RigidBody3D) -> int:
	if not is_instance_valid(requester):
		return -1
	if is_instance_valid(_landing_clearance_aircraft) and _landing_clearance_aircraft == requester:
		return 0  # cleared, actively landing
	for i in range(_landing_clearance_queue.size()):
		if is_instance_valid(_landing_clearance_queue[i]) and _landing_clearance_queue[i] == requester:
			# Position 1 = next in queue (at approach point), 2 = behind, etc.
			return i + 1
	return -1  # not in queue


func release_landing_clearance(requester: RigidBody3D) -> void:
	if requester != null:
		_remove_landing_clearance_request(requester)
	if not is_instance_valid(_landing_clearance_aircraft):
		_landing_clearance_aircraft = null
		_landing_clearance_elapsed_s = 0.0
		landing_deck_active = _is_landing_deck_busy()
		_grant_next_landing_clearance_if_possible()
		return
	if requester == null or _landing_clearance_aircraft == requester:
		_recovery_debug("landing clearance released for %s" % _aircraft_debug_name(_landing_clearance_aircraft))
		_landing_clearance_aircraft = null
		_landing_clearance_elapsed_s = 0.0
		landing_deck_active = _is_landing_deck_busy()
		_grant_next_landing_clearance_if_possible()

func start_post_arrest_recovery(aircraft_variant: Variant) -> void:
	"""Called by AIPilot when the arresting cable has already auto-released.
	Skips the power-down timer and goes straight to hangar storage."""
	if not is_instance_valid(aircraft_variant):
		_recovery_debug("start_post_arrest_recovery ignored: invalid aircraft")
		return
	var aircraft := aircraft_variant as RigidBody3D
	if not is_instance_valid(aircraft):
		_recovery_debug("start_post_arrest_recovery ignored: invalid aircraft")
		return
	if _is_helicopter_aircraft(aircraft) and not _is_helicopter_on_carrier_deck_for_recovery(aircraft):
		var carrier := get_parent() as Node3D
		var local_pos := carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
		_recovery_debug("start_post_arrest_recovery ignored: helicopter not on deck aircraft=%s local=%s pos=%s" % [
			_aircraft_debug_name(aircraft),
			_fmt_vec3(local_pos),
			_fmt_vec3(aircraft.global_position),
		])
		return
	release_landing_clearance(aircraft)
	var arresting_engaged := aircraft.has_meta("arresting_engaged") and bool(aircraft.get_meta("arresting_engaged"))
	var cable = aircraft.get_meta("arresting_cable") if aircraft.has_meta("arresting_cable") else null
	# If FlightDeckManager already started a managed recovery via signal, let it finish.
	if current_state == DeckState.RECOVERY_IN_PROGRESS:
		if deck_aircraft == aircraft and _recovery_job_dispatched:
			_recovery_debug("start_post_arrest_recovery ignored: same aircraft already dispatched")
			return
		if deck_aircraft != aircraft and _recovery_job_dispatched:
			_recovery_debug("start_post_arrest_recovery ignored: another aircraft already dispatched")
			return
	if current_state == DeckState.RECOVERY_IN_PROGRESS and deck_aircraft != aircraft and _recovery_job_dispatched and false:
		return
	deck_aircraft = aircraft
	_pending_store_aircraft = aircraft
	current_state = DeckState.RECOVERY_IN_PROGRESS
	_recovery_debug("start post-arrest recovery arresting=%s cable=%s" % [
		str(arresting_engaged),
		str(cable != null)
	])
	aircraft.set_meta("parking_brake", true)
	aircraft.set_meta("controls_disabled", true)
	_stabilize_aircraft_for_recovery_pickup(aircraft)
	var th = _find_tailhook(aircraft)
	if is_instance_valid(th) and th.has_method("stow"):
		th.stow()
	if arresting_engaged and cable and cable.has_method("manual_release"):
		_recovery_powerdown_in_progress = false
		_recovery_release_done = false
		_recovery_job_dispatched = false
		cable.manual_release()
		var still_engaged: bool = aircraft.has_meta("arresting_engaged") and bool(aircraft.get_meta("arresting_engaged"))
		if still_engaged:
			_recovery_debug("manual release requested but aircraft still reports arresting_engaged")
		elif not _recovery_job_dispatched:
			_recovery_release_done = true
			_recovery_debug("cable released synchronously; dispatching recovery")
			_dispatch_recovery_job()
		return
	_recovery_powerdown_in_progress = false
	_recovery_release_done = true
	_recovery_job_dispatched = false
	_recovery_debug("dispatching direct recovery with no engaged cable")
	_dispatch_recovery_job()

func _stabilize_aircraft_for_recovery_pickup(aircraft: RigidBody3D) -> void:
	if not is_instance_valid(aircraft):
		return
	aircraft.set_meta("parking_brake", true)
	aircraft.set_meta("controls_disabled", true)
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.freeze = true

func _configure_retrieved_aircraft_as_ai(aircraft: RigidBody3D, land_after_launch: bool = true) -> void:
	"""Set up a hangar-retrieved aircraft for AI control."""
	aircraft.add_to_group("friendlies")
	aircraft.add_to_group("ai_aircraft")
	aircraft.remove_from_group("aircraft")  # Ensure not treated as player plane

	# Disable player-only nodes
	for node_name in ["CameraController", "HeadsUpDisplay", "InstrumentPanel", "ControlTargeting"]:
		var node = aircraft.find_child(node_name, true, false)
		if node:
			node.set_process(false)
			node.set_physics_process(false)
			node.set_process_input(false)
			if node is CanvasItem:
				node.visible = false
			elif node is Node3D:
				node.visible = false

	# Keep camera tripods so the player can watch this plane
	for cam_name in ["CameraCockpit", "CameraChase", "CameraCinematic"]:
		var tripod = aircraft.get_node_or_null(cam_name)
		if tripod:
			tripod.set_process(true)
			tripod.set_physics_process(true)

	# Enable AI but keep it muted until the catapult shuttle connects.
	# controls_disabled is cleared by request_launch_sequence() just before launch().
	aircraft.set_meta("controls_disabled", true)

	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()

	# Manual retrieval can still use a launch-then-recover flow, but scramble
	# launches should immediately proceed to their assigned mission.
	var ai_pilot = aircraft.find_child("AIPilot", true, false)
	if ai_pilot and "land_after_launch" in ai_pilot:
		ai_pilot.land_after_launch = land_after_launch

func _configure_retrieved_aircraft_as_player(aircraft: RigidBody3D) -> void:
	"""Set up a hangar-retrieved aircraft for player control."""
	# Ensure this craft is treated as a player aircraft, not AI-only.
	if not aircraft.is_in_group("aircraft"):
		aircraft.add_to_group("aircraft")
	if aircraft.is_in_group("ai_aircraft"):
		aircraft.remove_from_group("ai_aircraft")

	# Ensure player-facing nodes are enabled.
	for node_name in ["CameraController", "HeadsUpDisplay", "InstrumentPanel", "ControlTargeting"]:
		var node = aircraft.find_child(node_name, true, false)
		if not node:
			continue
		node.set_process(true)
		node.set_physics_process(true)
		node.set_process_input(true)
		if node is CanvasItem:
			node.visible = true
		elif node is Node3D:
			node.visible = true

	# Explicitly disable AI pilot for this retrieved aircraft.
	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("disable_ai"):
		ai_toggle.disable_ai()
	var ai_pilot = aircraft.find_child("AIPilot", true, false)
	if ai_pilot and "land_after_launch" in ai_pilot:
		ai_pilot.land_after_launch = false

	# Keep controls muted until catapult handoff/release.
	aircraft.set_meta("controls_disabled", true)
	

# --- Helpers ---
func _find_nodes_by_script(root: Node, script_name: String) -> Array[Node]:
	var found_nodes: Array[Node] = []
	for child in root.get_children():
		if child.get_script() and child.get_script().resource_path.ends_with(script_name):
			found_nodes.append(child)
		found_nodes.append_array(_find_nodes_by_script(child, script_name))
	return found_nodes

func _find_tailhook(root: Node) -> Node:
	# First pass: by script file name
	var nodes = _find_nodes_by_script(root, "Tailhook.gd")
	if not nodes.is_empty():
		return nodes[0]
	var nodes2 = _find_nodes_by_script(root, "TailhookSimple.gd")
	if not nodes2.is_empty():
		return nodes2[0]
	# Second pass: by ModuleType property
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n and n.has_method("get"):
			var mt = null
			# Protect against modules without get
			if n.has_method("get"):
				mt = n.get("ModuleType")
			if mt != null and str(mt).to_lower() == "tailhook":
				return n
		for child in n.get_children():
			stack.push_back(child)
	# Third pass: any node with stow() and class/script hint containing Tailhook
	stack = [root]
	while not stack.is_empty():
		var n2 = stack.pop_back()
		if n2 and n2.has_method("stow"):
			var hint = ""
			if n2.get_script():
				hint = str(n2.get_script().resource_path)
			if hint.to_lower().find("tailhook") != -1 or n2.get_class().to_lower().find("tailhook") != -1:
				return n2
		for ch in n2.get_children():
			stack.push_back(ch)
	return null

func _find_engine(root: Node) -> Node:
	var engine_nodes = _find_nodes_by_script(root, "Engine.gd")
	if not engine_nodes.is_empty():
		return engine_nodes[0]
	return null

# --- Hangar Storage and Retrieval ---
func start_hangar_storage(aircraft: RigidBody3D):
	"""Start storing aircraft in hangar"""
	if _landing_test_active:
		return
	if stored_aircraft.size() >= max_hangar_capacity:
		return
	
	current_state = DeckState.STORING_IN_HANGAR
	_retrieval_top_handled = false
	
	# Move elevator down to hangar level
	if elevator and elevator.has_method("move_platform_down"):
		_ensure_elevator_signal_connections()
		elevator.move_platform_down()

func start_hangar_retrieval():
	"""Start retrieving aircraft from hangar"""
	if _landing_test_active:
		return
	if stored_aircraft.is_empty():
		return
	while _tractor_elevator_transfer_in_progress:
		await get_tree().physics_frame

	current_state = DeckState.RETRIEVING_FROM_HANGAR
	_retrieval_top_handled = false

	# Move elevator down to hangar level (empty)
	if elevator and elevator.has_method("move_platform_down"):
		_ensure_elevator_signal_connections()
		if "current_state" in elevator and elevator.current_state == elevator.ElevatorState.AT_BOTTOM:
			_spawn_aircraft_at_hangar_level.call_deferred()
		else:
			elevator.move_platform_down()

func _on_elevator_at_bottom():
	"""Handle elevator reaching bottom"""
	if _landing_test_active and current_state in [DeckState.STORING_IN_HANGAR, DeckState.RETRIEVING_FROM_HANGAR]:
		current_state = DeckState.IDLE
		deck_aircraft = null
		_pending_store_aircraft = null
		_landing_clearance_aircraft = null
		_landing_clearance_queue.clear()
		return
	match current_state:
		DeckState.STORING_IN_HANGAR:
			_store_aircraft_in_hangar()
		DeckState.RETRIEVING_FROM_HANGAR:
			_spawn_aircraft_at_hangar_level()
		DeckState.TRACTOR_CLEANUP:
			pass
		_:
			# State was clobbered mid-descent (e.g. second helicopter landed during storage).
			# If we still have a pending store aircraft, complete it now.
			if is_instance_valid(_pending_store_aircraft):
				_recovery_debug("elevator_at_bottom: state=%s but pending_store valid; completing storage for %s" % [
					_deck_state_name(), _aircraft_debug_name(_pending_store_aircraft)
				])
				current_state = DeckState.STORING_IN_HANGAR
				_store_aircraft_in_hangar()

func _store_aircraft_in_hangar():
	"""Store the aircraft in hangar"""
	if not is_instance_valid(_pending_store_aircraft):
		_pending_store_aircraft = null
		_recovery_debug("store aircraft skipped: no pending store aircraft")
		current_state = DeckState.IDLE
		_prune_landing_clearance_queue()
		_prune_landing_clearance_aircraft()
		_grant_next_landing_clearance_if_possible()
		return


	# Store aircraft data for later spawning
	_recovery_debug("storing aircraft in hangar")
	var aircraft_data = _extract_aircraft_data(_pending_store_aircraft)
	_resolve_carrier_manager()
	if is_instance_valid(carrier_manager):
		carrier_manager.mark_aircraft_stored(_pending_store_aircraft, aircraft_data)
	elif not _ensure_pilot_assigned_for_data(aircraft_data):
		push_warning("[FlightDeckManager] Stored aircraft is missing pilot data and CarrierManager is unavailable.")
	stored_aircraft.append(aircraft_data)
	_recovery_debug("aircraft stored; hangar count=%d" % stored_aircraft.size())

	# Remove aircraft from the scene
	_pending_store_aircraft.queue_free()
	_pending_store_aircraft = null

	deck_aircraft = null
	_recovery_powerdown_in_progress = false
	_recovery_release_done = false
	_recovery_job_dispatched = false
	_reset_landing_blocker_cleanup()
	current_state = DeckState.IDLE
	# The arrested aircraft released its own clearance before storage. Preserve
	# every other recovery request and promote the next waiter now that the deck
	# has physically cleared.
	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	_grant_next_landing_clearance_if_possible()

func _spawn_aircraft_at_hangar_level():
	"""Spawn aircraft at hangar level when elevator reaches bottom during retrieval"""
	if _landing_test_active:
		current_state = DeckState.IDLE
		deck_aircraft = null
		return
	if stored_aircraft.is_empty():
		current_state = DeckState.IDLE
		return


	# Create aircraft at hangar level
	_pending_launch_hangar_index = 0
	var aircraft = _create_aircraft_at_hangar_level()

	if not aircraft:
		current_state = DeckState.IDLE
		# If an AI scramble couldn't find a suitable aircraft, drop the queue so we do not retry forever.
		if _pending_flight_ops != null and _select_hangar_launch_index() < 0:
			_ai_launch_queue = 0
			_pending_flight_ops = null
			_pending_ai_loadout_profile = ""
			_pending_ai_aircraft_kind = "fixed_wing"
			_pending_ai_aircraft_model = ""
		return

	# Remove the aircraft we actually launched (may not be index 0 if we skipped utility helicopters).
	var remove_idx: int = clampi(_pending_launch_hangar_index, 0, stored_aircraft.size() - 1)
	stored_aircraft.remove_at(remove_idx)
	_pending_launch_hangar_index = 0

	# Store reference for the retrieval sequence
	deck_aircraft = aircraft

	# Short settle so the fresh spawn is stable before the elevator starts up.
	await get_tree().create_timer(_retrieval_spawn_settle_s).timeout
	# Re-validate after await: local references can become stale if the node was freed.
	var retrieval_aircraft := deck_aircraft
	if not is_instance_valid(retrieval_aircraft):
		deck_aircraft = null
		current_state = DeckState.IDLE
		return
	_start_retrieval_ascent_sequence(retrieval_aircraft)

func _on_elevator_at_top():
	"""Handle elevator reaching top"""
	if _heli_test_active:
		_log_heli_test("elevator top callback state=%s handled=%s physical_top=%s aircraft=%s" % [
			_deck_state_name(),
			str(_retrieval_top_handled),
			str(_is_elevator_physically_at_top()),
			_aircraft_debug_name(deck_aircraft),
		])
	if _landing_test_active and current_state in [DeckState.STORING_IN_HANGAR, DeckState.RETRIEVING_FROM_HANGAR]:
		current_state = DeckState.IDLE
		deck_aircraft = null
		_pending_store_aircraft = null
		return
	match current_state:
		DeckState.STORING_IN_HANGAR:
			deck_aircraft = null
			_pending_store_aircraft = null
			_recovery_powerdown_in_progress = false
			_recovery_release_done = false
			_recovery_job_dispatched = false
			current_state = DeckState.IDLE
		DeckState.RETRIEVING_FROM_HANGAR:
			if not _is_elevator_physically_at_top():
				return
			if _retrieval_top_handled:
				return
			_retrieval_top_handled = true
			_complete_retrieval_sequence()
		DeckState.TRACTOR_CLEANUP:
			pass
		_:
			pass

func get_hangar_status() -> Dictionary:
	"""Get hangar status"""
	return {
		"stored_count": stored_aircraft.size(),
		"max_capacity": max_hangar_capacity,
		"available_space": max_hangar_capacity - stored_aircraft.size(),
		"pending_store": _pending_store_aircraft != null
	}

func _initialize_hangar_with_aircraft():
	"""Pre-populate hangar with aircraft at startup"""

	# Prepend a few Aircraft_11 utility helicopters so rescue dispatches work immediately.
	var a11_scene: PackedScene = aircraft_11_scene
	if a11_scene == null:
		a11_scene = load("res://Aircraft/Aircraft_11.tscn") as PackedScene
	if a11_scene != null:
		var utility_count := mini(maxi(initial_utility_helicopter_count, 0), max_hangar_capacity)
		for _j in range(utility_count):
			var heli_data := _make_stored_aircraft_entry("Aircraft_11", a11_scene)
			if not heli_data.is_empty():
				stored_aircraft.append(heli_data)

	# Fill remaining hangar capacity with default jets
	var remaining := max_hangar_capacity - stored_aircraft.size()
	for i in range(remaining):
		var aircraft_data := _make_stored_aircraft_entry(
			"Aircraft_" + str(i + 1),
			null,
			DEFAULT_AIRCRAFT_SCENE_PATH
		)
		if aircraft_data.is_empty():
			push_warning("[FlightDeckManager] Stopping hangar prefill: unable to assign pilot to stored aircraft.")
			break
		stored_aircraft.append(aircraft_data)


# --- Aircraft Movement System ---
func _move_aircraft_to_elevator(aircraft: RigidBody3D):
	"""Move aircraft to elevator position using gentle forces"""
	var active_bots: Array[Node] = _activate_tractor_bots(aircraft)
	_recovery_debug("move aircraft to elevator; active_bots=%d target=%s" % [
		active_bots.size(),
		_fmt_vec3(elevator_pickup_marker.global_position)
	])
	# Wait for tractorbots to position themselves, then start gentle movement
	if not active_bots.is_empty():
		await _wait_for_tractor_bots_positioned(active_bots)
	else:
		_recovery_debug("no active tractorbots; moving aircraft without visual tractor pickup")
		
	if not is_instance_valid(aircraft):
		current_state = DeckState.IDLE
		return

	_start_aircraft_movement(aircraft, elevator_pickup_marker.global_position)

func _activate_tractor_bots(aircraft: RigidBody3D) -> Array[Node]:
	"""Activate tractorbots to position at aircraft wheels"""
	var active_bots: Array[Node] = []
	var gear_colliders: Array[Node3D] = _get_launch_wheel_nodes(aircraft)
	if gear_colliders.is_empty():
		_recovery_debug("tractor activation found no gear/wheel nodes on %s" % _aircraft_debug_name(aircraft))
		return active_bots
	_recovery_debug("tractor activation found %d gear nodes and %d configured bots" % [gear_colliders.size(), tractor_bots.size()])

	for i in range(min(tractor_bots.size(), gear_colliders.size())):
		var bot = tractor_bots[i]
		var gear_collider = gear_colliders[i]
		if bot and gear_collider and bot.has_method("activate"):
			# Calculate offset from aircraft center to gear collider
			var wheel_offset = gear_collider.global_position - aircraft.global_position
			bot.activate(aircraft, wheel_offset, gear_collider)
			active_bots.append(bot)
			_recovery_debug("activated %s for gear %s offset=%s" % [
				bot.name,
				gear_collider.name,
				_fmt_vec3(wheel_offset)
			])
	return active_bots

func _get_tractor_wait_status(active_bots: Array[Node]) -> String:
	var parts := PackedStringArray()
	for bot in active_bots:
		if not is_instance_valid(bot):
			parts.append("invalid")
			continue
		if bot.has_method("get_recovery_debug_status"):
			var status: Dictionary = bot.get_recovery_debug_status()
			parts.append("%s phase=%s role=%s pos=%s wheel=%s src=%s dist=%.2f live=%.2f fixed_delta=%.2f replans=%d last_replan=%.2f ac_spd=%.1f bot=%s goal=%s wheel_pos=%s blocked=%s disabled=%s" % [
				str(status.get("name", bot.name)),
				str(status.get("phase", "?")),
				str(status.get("role", "?")),
				str(status.get("positioned", false)),
				str(status.get("target_wheel", "none")),
				str(status.get("wheel_source", "?")),
				float(status.get("distance", -1.0)),
				float(status.get("live_distance", -1.0)),
				float(status.get("fixed_live_delta", -1.0)),
				int(status.get("replans", 0)),
				float(status.get("last_replan_delta", 0.0)),
				float(status.get("aircraft_speed", 0.0)),
				_fmt_vec3(status.get("bot_position", Vector3.ZERO)),
				_fmt_vec3(status.get("goal_position", Vector3.ZERO)),
				_fmt_vec3(status.get("live_wheel_position", Vector3.ZERO)),
				str(status.get("blocked", false)),
				str(status.get("movement_disabled", false))
			])
		else:
			var positioned := false
			if bot.has_method("is_positioned_at_gear"):
				positioned = bool(bot.is_positioned_at_gear())
			parts.append("%s pos=%s" % [bot.name, str(positioned)])
	return "; ".join(parts)

func _wait_for_tractor_bots_positioned(active_bots: Array[Node]):
	"""Wait for all tractorbots to be positioned at their gear locations"""
	var wait_time := 0.0
	var next_debug_time := 0.0
	_recovery_debug("waiting for tractorbots to reach gear")
	while true:
		var all_positioned = true
		for bot in active_bots:
			if bot and bot.has_method("is_positioned_at_gear") and not bot.is_positioned_at_gear():
				all_positioned = false
				break
		
		if all_positioned:
			_recovery_debug("tractorbots positioned after %.2fs" % wait_time)
			break
		if wait_time >= maxf(tractor_position_timeout_s, 0.5):
			_recovery_debug("tractorbot positioning timed out after %.2fs; snapping visual bots to gear" % wait_time)
			_snap_active_tractor_bots_to_targets(active_bots)
			break
		
		var delta := get_physics_process_delta_time()
		wait_time += delta
		if wait_time >= next_debug_time:
			_recovery_debug("waiting for tractorbots %.1fs: %s" % [
				wait_time,
				_get_tractor_wait_status(active_bots)
			])
			next_debug_time += maxf(tractor_recovery_debug_interval_s, 0.1)
		await get_tree().physics_frame

func _snap_active_tractor_bots_to_targets(active_bots: Array[Node]) -> void:
	var deck_y := _get_deck_height_y()
	for bot in active_bots:
		if not is_instance_valid(bot) or not (bot is Node3D):
			continue
		var bot_node := bot as Node3D
		var status_target: Vector3 = bot_node.global_position
		var wheel_node := bot.get("target_wheel_node") as Node3D
		var target_aircraft_node := bot.get("target_aircraft") as RigidBody3D
		if is_instance_valid(wheel_node):
			status_target = wheel_node.global_position
		elif is_instance_valid(target_aircraft_node):
			var wheel_offset_variant: Variant = bot.get("wheel_position_offset")
			var wheel_offset: Vector3 = wheel_offset_variant if wheel_offset_variant is Vector3 else Vector3.ZERO
			status_target = target_aircraft_node.global_position + wheel_offset
		status_target.y = deck_y
		_recovery_debug("snap tractorbot %s to wheel target=%s wheel=%s aircraft=%s" % [
			bot_node.name,
			_fmt_vec3(status_target),
			wheel_node.name if is_instance_valid(wheel_node) else "offset",
			_aircraft_debug_name(target_aircraft_node)
		])
		bot_node.global_position = status_target
		bot.set("is_positioned", true)
		if bot.has_method("enable_movement"):
			bot.enable_movement()

func _deactivate_tractor_bots():
	"""Deactivate all tractorbots"""
	for bot in tractor_bots:
		if bot and bot.has_method("enable_movement"):
			bot.enable_movement()
		if bot and bot.has_method("deactivate"):
			bot.deactivate()

func _return_tractors_to_staging():
	"""Force tractorbots to drop what they are doing and return to staging"""
	var primary_bots := _get_primary_tractor_bots()
	var staging_slots := _get_primary_staging_slots_local(primary_bots.size())
	for i in range(min(primary_bots.size(), staging_slots.size())):
		var bot := primary_bots[i]
		if not is_instance_valid(bot):
			continue
		_set_cleanup_idle_for_tractor_bot(bot)
		bot.position = staging_slots[i]
	_tractorbots_in_hangar = false
	for bot in tractor_bots:
		if is_instance_valid(bot):
			# Drop any active connections
			if bot.has_method("_tick_uncoupling"):
				bot._tick_uncoupling(0.0)
			# Legacy TractorBot retreat path (SimpleTractorBot does not expose these members).
			if bot is TractorBot:
				bot.set("_state", TractorBot.BotState.RETURNING_TO_STAGING)
				if bot.has_method("_plan_move_to") and is_instance_valid(bot.staging_marker):
					bot._plan_move_to(bot.staging_marker.global_position)

func _disable_tractor_bot_movement():
	"""Disable tractorbot movement logic during elevator sequence"""
	for bot in tractor_bots:
		if bot and bot.has_method("disable_movement"):
			bot.disable_movement()

func _start_aircraft_movement(aircraft: RigidBody3D, target_position: Vector3):
	"""Start moving aircraft to target position with physics disabled"""
	_recovery_debug("starting aircraft movement to %s" % _fmt_vec3(target_position))
	_prepare_aircraft_for_movement(aircraft)
	# Use the same tractor-coupled horizontal move used during retrieval so
	# storage/retrieval have consistent bot motion and pacing.
	var deck_height = _get_deck_height_y()
	var gear_colliders = _find_gear_colliders(aircraft)
	if not _is_helicopter_aircraft(aircraft) and not gear_colliders.is_empty():
		var stance_target_position := Vector3(target_position.x, aircraft.global_position.y, target_position.z)
		await _move_aircraft_horizontally(aircraft, stance_target_position)
	elif not gear_colliders.is_empty():
		var lowest_gear_global_y := INF
		for gear in gear_colliders:
			if (gear as Node3D).global_position.y < lowest_gear_global_y:
				lowest_gear_global_y = (gear as Node3D).global_position.y
		var gear_to_body_offset: float = aircraft.global_position.y - lowest_gear_global_y
		var lift_aircraft_y: float = float(deck_height) + _aircraft_lift_height + gear_to_body_offset
		var lift_target_position = Vector3(target_position.x, lift_aircraft_y, target_position.z)
		await _move_aircraft_horizontally(aircraft, lift_target_position)
	else:
		await _move_aircraft_smoothly(aircraft, target_position)
	
	if not is_instance_valid(aircraft):
		current_state = DeckState.IDLE
		return
	await _align_aircraft_forward_on_elevator(aircraft)

	if not is_instance_valid(aircraft):
		current_state = DeckState.IDLE
		return
	_place_fixed_wing_in_static_suspension_pose(aircraft, _get_deck_height_y())
	# Wait 1 second after aircraft is in position before starting elevator
	await get_tree().create_timer(1.0).timeout

	# After aircraft reaches elevator, start elevator sequence
	if not is_instance_valid(aircraft):
		_recovery_debug("aircraft movement completed but aircraft became invalid")
		current_state = DeckState.IDLE
		return
	_recovery_debug("aircraft reached elevator; starting elevator sequence")
	_start_elevator_sequence(aircraft)

func _prepare_aircraft_for_movement(aircraft: RigidBody3D):
	"""Disable physics and place aircraft in its supported deck stance."""

	# Save original collision settings (only if not already saved)
	if _aircraft_original_collision_layer == 0:
		_aircraft_original_collision_layer = aircraft.collision_layer
		_aircraft_original_collision_mask = aircraft.collision_mask
		# Disable physics
	aircraft.set_meta("carrier_transport_mode", true)
	aircraft.freeze = true
	aircraft.gravity_scale = 0.0
	aircraft.collision_layer = 0  # Disable collision with ship
	aircraft.collision_mask = 0
	
	# Preserve the same spring-loaded stance used when physics becomes active.
	_position_aircraft_above_deck(aircraft)

func _position_aircraft_above_deck(aircraft: RigidBody3D):
	"""Position aircraft in its supported deck stance."""
	var gear_colliders = _find_gear_colliders(aircraft)
	var deck_height = _get_deck_height_y()
	if _place_fixed_wing_in_static_suspension_pose(aircraft, deck_height):
		return
	var target_gear_height = deck_height + _aircraft_lift_height
	
	if gear_colliders.is_empty():
		# No gear colliders found — use the LandingGear module's wheel nodes instead
		var wheel_nodes := _get_launch_wheel_nodes(aircraft)
		if not wheel_nodes.is_empty():
			var lowest_world_y := INF
			for w in wheel_nodes:
				if (w as Node3D).global_position.y < lowest_world_y:
					lowest_world_y = (w as Node3D).global_position.y
			aircraft.global_position.y += target_gear_height - lowest_world_y
		else:
			aircraft.global_position.y = target_gear_height
		return

	# Find the lowest gear collider
	var lowest_gear_y = INF
	for gear in gear_colliders:
		if gear.global_position.y < lowest_gear_y:
			lowest_gear_y = gear.global_position.y

	# Calculate offset to position lowest gear 20cm above deck
	var y_offset = target_gear_height - lowest_gear_y
	
	# Apply offset to aircraft position
	aircraft.global_position.y += y_offset

func _move_aircraft_smoothly(aircraft: RigidBody3D, target_position: Vector3):
	"""Move aircraft smoothly to target position with rotation"""
	# Work in carrier-local space so movement tracks with the moving carrier.
	var carrier := get_parent() as Node3D
	if carrier:
		carrier.force_update_transform()
	# Calculate target position. Fixed-wing aircraft retain their spring-loaded
	# body height; legacy/helicopter paths retain the configured transport lift.
	var deck_height = _get_deck_height_y()
	var target_gear_height = deck_height + _aircraft_lift_height

	# Find the lowest gear collider to calculate the aircraft's target Y position
	var gear_colliders = _find_gear_colliders(aircraft)
	var lowest_gear_local_y = INF
	for gear in gear_colliders:
		var local_y = aircraft.to_local(gear.global_position).y
		if local_y < lowest_gear_local_y:
			lowest_gear_local_y = local_y

	var aircraft_target_y := aircraft.global_position.y
	if _is_helicopter_aircraft(aircraft) or gear_colliders.is_empty():
		# Calculate aircraft's target Y position so its lowest gear is at target_gear_height
		aircraft_target_y = target_gear_height - lowest_gear_local_y
	var final_position = Vector3(target_position.x, aircraft_target_y, target_position.z)

	# Convert to carrier-local space
	var start_local: Vector3 = carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
	var target_local: Vector3 = carrier.to_local(final_position) if carrier else final_position
	var aircraft_carrier_local_basis: Basis = carrier.global_transform.basis.inverse() * aircraft.global_transform.basis if carrier else aircraft.global_transform.basis

	var distance = start_local.distance_to(target_local)
	var duration = distance / _aircraft_move_speed


	var elapsed_time = 0.0

	while elapsed_time < duration and is_instance_valid(aircraft):
		elapsed_time += get_physics_process_delta_time()
		var t = ease_in_out_cubic(clamp(elapsed_time / duration, 0.0, 1.0))

		# Lerp in carrier-local space, convert back to world — tracks carrier movement
		var current_local = start_local.lerp(target_local, t)
		if carrier:
			var aircraft_transform := aircraft.global_transform
			aircraft_transform.origin = carrier.to_global(current_local)
			aircraft_transform.basis = (carrier.global_transform.basis * aircraft_carrier_local_basis).orthonormalized()
			aircraft.global_transform = aircraft_transform
			_sync_rigidbody_transform_state(aircraft)
		else:
			aircraft.global_position = current_local
			_sync_rigidbody_transform_state(aircraft)
		aircraft.angular_velocity = Vector3.ZERO

		await get_tree().physics_frame

	# Final position — snap to carrier-relative target
	aircraft.global_position = carrier.to_global(target_local) if carrier else final_position
	if carrier:
		var final_transform := aircraft.global_transform
		final_transform.basis = (carrier.global_transform.basis * aircraft_carrier_local_basis).orthonormalized()
		aircraft.global_transform = final_transform
	_sync_rigidbody_transform_state(aircraft)
	aircraft.angular_velocity = Vector3.ZERO

	# Don't deactivate tractorbots yet - they need to follow the elevator

func _align_aircraft_forward_on_elevator(aircraft: RigidBody3D) -> void:
	if not is_instance_valid(aircraft):
		return

	var active_bots: Array[Node3D] = []
	var fallback_offsets: Array[Vector3] = []
	for bot in tractor_bots:
		if bot and bot is Node3D and bool(bot.get("is_active")):
			var bot_node := bot as Node3D
			if bot.has_method("disable_movement"):
				bot.disable_movement()
			active_bots.append(bot_node)
			fallback_offsets.append(bot_node.global_position - aircraft.global_position)

	var start_rotation := aircraft.global_rotation
	var target_yaw := _get_carrier_forward_yaw()
	var duration := maxf(tractor_elevator_align_duration_s, 0.01)
	var elapsed := 0.0
	_recovery_debug("aligning aircraft forward on elevator")

	while elapsed < duration and is_instance_valid(aircraft):
		elapsed += get_physics_process_delta_time()
		var t := ease_in_out_cubic(clampf(elapsed / duration, 0.0, 1.0))
		aircraft.global_rotation = Vector3(
			lerp_angle(start_rotation.x, 0.0, t),
			lerp_angle(start_rotation.y, target_yaw, t),
			lerp_angle(start_rotation.z, 0.0, t)
		)
		_sync_rigidbody_transform_state(aircraft)
		_snap_active_bots_to_aircraft_wheels(active_bots, fallback_offsets, aircraft)
		await get_tree().physics_frame

	if not is_instance_valid(aircraft):
		return
	aircraft.global_rotation = Vector3(0.0, target_yaw, 0.0)
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	_sync_rigidbody_transform_state(aircraft)
	_snap_active_bots_to_aircraft_wheels(active_bots, fallback_offsets, aircraft)

func _snap_active_bots_to_aircraft_wheels(active_bots: Array[Node3D], fallback_offsets: Array[Vector3], aircraft: RigidBody3D) -> void:
	if not is_instance_valid(aircraft):
		return
	var bot_floor_y := _get_deck_height_y() + tractor_elevator_floor_offset_m
	for i in range(min(active_bots.size(), fallback_offsets.size())):
		var bot := active_bots[i]
		if not is_instance_valid(bot):
			continue
		var bot_position := aircraft.global_position + fallback_offsets[i]
		var wheel_node := bot.get("target_wheel_node") as Node3D
		if is_instance_valid(wheel_node):
			bot_position = wheel_node.global_position
		bot_position.y = bot_floor_y
		bot.global_position = bot_position

func _find_gear_colliders(aircraft: RigidBody3D) -> Array[Node3D]:
	"""Find gear colliders on the aircraft"""
	var gear_colliders: Array[Node3D] = []
	
	# Look for common gear collider names
	var gear_names = [
		"CenterGearCollider",
		"LeftGearCollider",
		"RightGearCollider",
		"LeftMainGearCollider",
		"RightMainGearCollider",
		"NoseGearCollider",
		"FrontGearCollider",
		"RearLeftGearCollider",
		"RearRightGearCollider",
		"RearGearCollider",
	]
	
	for gear_name in gear_names:
		var gear_node = aircraft.find_child(gear_name, true, false)
		if gear_node and gear_node is Node3D:
			gear_colliders.append(gear_node)
	
	# If we didn't find specific gear colliders, look for any colliders with "gear" in the name
	if gear_colliders.is_empty():
		var all_children = _get_all_children(aircraft)
		for child in all_children:
			if child is Node3D and "gear" in child.name.to_lower():
				gear_colliders.append(child)
	
	pass
	return gear_colliders

func _find_landing_gear_module(aircraft: RigidBody3D) -> Node:
	for child in _get_all_children(aircraft):
		if "gear_collision_shapes" in child and "nose_gear_index" in child:
			return child
	return null

func _get_launch_wheel_nodes(aircraft: RigidBody3D) -> Array[Node3D]:
	var wheel_nodes: Array[Node3D] = []
	var landing_gear_module := _find_landing_gear_module(aircraft)
	if landing_gear_module:
		var shapes_variant: Variant = landing_gear_module.get("gear_collision_shapes")
		if typeof(shapes_variant) == TYPE_ARRAY:
			for entry in shapes_variant:
				if entry is Node3D and is_instance_valid(entry) and not wheel_nodes.has(entry):
					wheel_nodes.append(entry)
	if wheel_nodes.is_empty():
		wheel_nodes = _find_gear_colliders(aircraft)
	return wheel_nodes

func _get_launch_nose_and_main_nodes(aircraft: RigidBody3D, wheel_nodes: Array[Node3D]) -> Dictionary:
	var nose_node: Node3D = null
	var main_nodes: Array[Node3D] = []
	var landing_gear_module := _find_landing_gear_module(aircraft)
	if landing_gear_module:
		var nose_index: int = int(landing_gear_module.get("nose_gear_index"))
		if nose_index >= 0 and nose_index < wheel_nodes.size():
			nose_node = wheel_nodes[nose_index]

	if nose_node == null:
		for wheel in wheel_nodes:
			var name_l: String = wheel.name.to_lower()
			if "nose" in name_l or "center" in name_l:
				nose_node = wheel
				break

	for wheel in wheel_nodes:
		if wheel != nose_node:
			main_nodes.append(wheel)

	return {
		"nose": nose_node,
		"mains": main_nodes,
	}


func _place_fixed_wing_in_static_suspension_pose(aircraft: RigidBody3D, surface_y: float) -> bool:
	if not is_instance_valid(aircraft) or _is_helicopter_aircraft(aircraft):
		return false
	var landing_gear_module := _find_landing_gear_module(aircraft)
	if landing_gear_module == null \
			or not landing_gear_module.has_method("get_static_load_compressions") \
			or not landing_gear_module.has_method("get_gear_base_global_position") \
			or not landing_gear_module.has_method("get_wheel_rest_height"):
		return false
	var gear_count := int(landing_gear_module.call("get_gear_count"))
	if gear_count <= 0:
		return false
	var compression_variant: Variant = landing_gear_module.call("get_static_load_compressions")
	if typeof(compression_variant) != TYPE_ARRAY or compression_variant.size() < gear_count:
		return false
	var target_base_heights: Array[float] = []
	target_base_heights.resize(gear_count)
	for i in range(gear_count):
		target_base_heights[i] = surface_y \
				+ float(landing_gear_module.call("get_wheel_rest_height", i)) \
				- float(compression_variant[i])

	var nose_index := int(landing_gear_module.get("nose_gear_index"))
	var main_indices: Array[int] = []
	var rear_variant: Variant = landing_gear_module.get("rear_gear_indices")
	if typeof(rear_variant) == TYPE_ARRAY:
		for rear_index_variant in rear_variant:
			var rear_index := int(rear_index_variant)
			if rear_index >= 0 and rear_index < gear_count and rear_index != nose_index:
				main_indices.append(rear_index)

	# Solve pitch and height against the unshifted suspension bases. Collider and
	# visual travel are applied afterward, so the same load/compression exists
	# while frozen and on the first active physics frame.
	for _iteration in range(4):
		if nose_index >= 0 and nose_index < gear_count and not main_indices.is_empty():
			var nose_base: Vector3 = landing_gear_module.call("get_gear_base_global_position", nose_index)
			var main_base := Vector3.ZERO
			var main_target_y := 0.0
			for main_index in main_indices:
				main_base += landing_gear_module.call("get_gear_base_global_position", main_index) as Vector3
				main_target_y += target_base_heights[main_index]
			main_base /= float(main_indices.size())
			main_target_y /= float(main_indices.size())
			var nose_error := nose_base.y - target_base_heights[nose_index]
			var main_error := main_base.y - main_target_y
			var longitudinal_span := absf(
				aircraft.to_local(nose_base).z - aircraft.to_local(main_base).z
			)
			if longitudinal_span > 0.001:
				var pitch_step := clampf(
					atan2(nose_error - main_error, longitudinal_span),
					-deg_to_rad(launch_deck_pitch_contact_max_deg),
					deg_to_rad(launch_deck_pitch_contact_max_deg)
				)
				if absf(pitch_step) >= deg_to_rad(0.01):
					var x_axis := aircraft.global_transform.basis.x.normalized()
					var adjusted_transform := aircraft.global_transform
					adjusted_transform.basis = adjusted_transform.basis.rotated(x_axis, pitch_step).orthonormalized()
					aircraft.global_transform = adjusted_transform

		var average_height_error := 0.0
		for i in range(gear_count):
			var base_position: Vector3 = landing_gear_module.call("get_gear_base_global_position", i)
			average_height_error += base_position.y - target_base_heights[i]
		average_height_error /= float(gear_count)
		aircraft.global_position.y -= average_height_error

	if landing_gear_module.has_method("snap_suspension_to_static_load"):
		landing_gear_module.call("snap_suspension_to_static_load")
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	_sync_rigidbody_transform_state(aircraft)
	return true

func _lower_launch_wheels_to_deck(aircraft: RigidBody3D, wheel_nodes: Array[Node3D], deck_y: float) -> void:
	if wheel_nodes.is_empty():
		aircraft.global_position.y = deck_y
		return

	var contact_offset: float = _get_deck_contact_visual_offset(aircraft)
	var lowest_world_y: float = INF
	for gear in wheel_nodes:
		var gear_world_y: float = gear.global_position.y - contact_offset
		if gear_world_y < lowest_world_y:
			lowest_world_y = gear_world_y
	aircraft.global_position.y += deck_y - lowest_world_y

func _get_deck_contact_visual_offset(aircraft: RigidBody3D) -> float:
	var landing_gear_module := _find_landing_gear_module(aircraft)
	if landing_gear_module == null:
		return 0.0
	var offset = landing_gear_module.get("deck_contact_visual_offset_m")
	if offset == null:
		return 0.0
	return maxf(float(offset), 0.0)

func _settle_launch_aircraft_on_wheels(aircraft: RigidBody3D, wheel_nodes: Array[Node3D], deck_y: float) -> void:
	if _place_fixed_wing_in_static_suspension_pose(aircraft, deck_y):
		return
	if wheel_nodes.is_empty():
		aircraft.global_position.y = deck_y
		return

	var wheel_split: Dictionary = _get_launch_nose_and_main_nodes(aircraft, wheel_nodes)
	var nose_node: Node3D = wheel_split.get("nose") as Node3D
	var main_nodes: Array[Node3D] = wheel_split.get("mains", []) as Array[Node3D]
	var max_pitch: float = deg_to_rad(launch_deck_pitch_contact_max_deg)

	for _i in range(4):
		if is_instance_valid(nose_node) and main_nodes.size() >= 2 and max_pitch > 0.0:
			var nose_local: Vector3 = aircraft.to_local(nose_node.global_position)
			var main_avg_local: Vector3 = Vector3.ZERO
			var main_avg_world_y: float = 0.0
			for wheel in main_nodes:
				main_avg_local += aircraft.to_local(wheel.global_position)
				main_avg_world_y += wheel.global_position.y
			main_avg_local /= float(main_nodes.size())
			main_avg_world_y /= float(main_nodes.size())

			var longitudinal_span: float = absf(nose_local.z - main_avg_local.z)
			var height_error: float = nose_node.global_position.y - main_avg_world_y
			if longitudinal_span > 0.001 and absf(height_error) > 0.002:
				var pitch_step: float = clampf(atan2(height_error, longitudinal_span), -max_pitch, max_pitch)
				if absf(pitch_step) >= deg_to_rad(0.02):
					var x_axis: Vector3 = aircraft.global_transform.basis.x.normalized()
					var adjusted_basis: Basis = aircraft.global_transform.basis.rotated(x_axis, pitch_step).orthonormalized()
					var adjusted_transform: Transform3D = aircraft.global_transform
					adjusted_transform.basis = adjusted_basis
					aircraft.global_transform = adjusted_transform

		_lower_launch_wheels_to_deck(aircraft, wheel_nodes, deck_y)

	var final_heights: Array[String] = []
	for wheel in wheel_nodes:
		final_heights.append(str(snappedf(wheel.global_position.y - deck_y, 0.001)))

func _apply_launch_three_wheel_pitch_correction(aircraft: RigidBody3D, wheel_nodes: Array[Node3D]) -> void:
	if wheel_nodes.size() < 3 or launch_deck_pitch_contact_max_deg <= 0.0:
		return

	var nose_node: Node3D = null
	var main_nodes: Array[Node3D] = []
	var landing_gear_module := _find_landing_gear_module(aircraft)
	if landing_gear_module:
		var nose_index := int(landing_gear_module.get("nose_gear_index"))
		if nose_index >= 0 and nose_index < wheel_nodes.size():
			nose_node = wheel_nodes[nose_index]

	if nose_node == null:
		for wheel in wheel_nodes:
			var name_l := wheel.name.to_lower()
			if "nose" in name_l or "center" in name_l:
				nose_node = wheel
				break
	if nose_node == null:
		return

	for wheel in wheel_nodes:
		if wheel == nose_node:
			continue
		main_nodes.append(wheel)
	if main_nodes.size() < 2:
		return

	var nose_local := aircraft.to_local(nose_node.global_position)
	var main_avg := Vector3.ZERO
	for wheel in main_nodes:
		main_avg += aircraft.to_local(wheel.global_position)
	main_avg /= float(main_nodes.size())

	var dz := nose_local.z - main_avg.z
	var dy := nose_local.y - main_avg.y
	if absf(dz) < 0.001 or absf(dy) < 0.0005:
		return

	var max_pitch := deg_to_rad(launch_deck_pitch_contact_max_deg)
	var pitch_correction := clampf(atan2(dy, dz), -max_pitch, max_pitch)
	if absf(pitch_correction) < deg_to_rad(0.05):
		return

	var x_axis := aircraft.global_transform.basis.x.normalized()
	var adjusted_basis := aircraft.global_transform.basis.rotated(x_axis, pitch_correction).orthonormalized()
	var adjusted_transform := aircraft.global_transform
	adjusted_transform.basis = adjusted_basis
	aircraft.global_transform = adjusted_transform

func _get_all_children(node: Node) -> Array[Node]:
	"""Get all children recursively"""
	var children: Array[Node] = []
	for child in node.get_children():
		children.append(child)
		children.append_array(_get_all_children(child))
	return children

func _get_deck_height_y() -> float:
	var carrier = get_parent()
	if carrier and carrier is Node3D:
		(carrier as Node3D).force_update_transform()
	# Prefer explicit deck marker global height if present
	if deck_marker and deck_marker is Node3D:
		(deck_marker as Node3D).force_update_transform()
		return (deck_marker as Node3D).global_position.y
	# Fallback: parent carrier global Y plus known local offset
	if carrier and carrier is Node3D:
		return (carrier as Node3D).global_position.y + _flight_deck_local_offset_y
	return _flight_deck_local_offset_y

func _get_deck_local_y() -> float:
	if deck_marker and deck_marker is Node3D:
		return (deck_marker as Node3D).position.y
	return _flight_deck_local_offset_y

func _get_all_tractor_nodes() -> Array[Node3D]:
	var tractor_nodes: Array[Node3D] = []
	var carrier := get_parent()
	if carrier == null:
		return tractor_nodes
	for node in carrier.find_children("*", "", true, false):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if node.get_parent() != carrier:
			continue
		if node is SimpleTractorBot or node is TractorBot:
			tractor_nodes.append(node as Node3D)
	return tractor_nodes

func _get_extra_deck_tractor_bots() -> Array[Node3D]:
	var extras: Array[Node3D] = []
	var deck_y := _get_deck_height_y()
	var carrier := get_parent() as Node3D
	for node in _get_all_tractor_nodes():
		if tractor_bots.has(node):
			continue
		if absf(node.global_position.y - deck_y) > 2.5:
			continue
		if carrier != null:
			var local_pos := carrier.to_local(node.global_position)
			if absf(local_pos.x) > 25.0 or absf(local_pos.z) > 90.0:
				continue
		extras.append(node)
	return extras

func _get_tractor_cleanup_elevator_slots_local(count: int) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var deck_local_y: float = _get_deck_local_y()
	var slot_offsets: Array[Vector3] = [
		Vector3(-6.0, 0.0, -3.0),
		Vector3(-2.0, 0.0, -3.0),
		Vector3(2.0, 0.0, -3.0),
		Vector3(6.0, 0.0, -3.0)
	]
	var base_local: Vector3 = elevator_pickup_marker.position if is_instance_valid(elevator_pickup_marker) else Vector3.ZERO
	for i in range(min(count, slot_offsets.size())):
		var slot_local: Vector3 = base_local + slot_offsets[i]
		slot_local.y = deck_local_y
		slots.append(slot_local)
	return slots

func _get_tractor_cleanup_hangar_slots_local(count: int) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var hangar_local_y: float = _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
	var slot_offsets: Array[Vector3] = [
		Vector3(-9.0, 0.0, -8.0),
		Vector3(-3.0, 0.0, -8.0),
		Vector3(3.0, 0.0, -8.0),
		Vector3(9.0, 0.0, -8.0)
	]
	var base_local: Vector3 = elevator_pickup_marker.position if is_instance_valid(elevator_pickup_marker) else Vector3.ZERO
	for i in range(min(count, slot_offsets.size())):
		var slot_local: Vector3 = base_local + slot_offsets[i]
		slot_local.y = hangar_local_y
		slots.append(slot_local)
	return slots

func get_deck_height() -> float:
	"""Public method to get deck height for other components"""
	return _get_deck_height_y()

func _capture_aircraft_energy_state(aircraft: RigidBody3D) -> Array[Dictionary]:
	var containers: Array[Dictionary] = []
	for node in _get_all_children(aircraft):
		if "current_level" in node and "EnergyType" in node and "MaxCapacity" in node:
			containers.append({
				"path": str(aircraft.get_path_to(node)),
				"energy_type": str(node.get("EnergyType")),
				"current_level": float(node.get("current_level")),
				"active": bool(node.get("ContainerActive")),
			})
	return containers

func _restore_aircraft_energy_state(aircraft: RigidBody3D, energy_state: Array) -> void:
	for entry_variant in energy_state:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var node_path := NodePath(str(entry.get("path", "")))
		if node_path == NodePath():
			continue
		var container := aircraft.get_node_or_null(node_path)
		if container == null:
			continue
		if "ContainerActive" in container:
			container.set("ContainerActive", bool(entry.get("active", true)))
		if "current_level" in container:
			container.set("current_level", float(entry.get("current_level", container.get("current_level"))))
		if container.has_method("request_update_interface"):
			container.request_update_interface()
	if aircraft.has_method("prepare_energy_system"):
		aircraft.prepare_energy_system()

func _capture_aircraft_loadout_state(aircraft: RigidBody3D) -> Dictionary:
	var loadout: Array[Dictionary] = []
	for node in _get_all_children(aircraft):
		if node is Hardpoint:
			var hardpoint := node as Hardpoint
			var weapon_scene_path := ""
			var ammo_count := -1
			if is_instance_valid(hardpoint.weapon_instance):
				weapon_scene_path = hardpoint.weapon_instance.scene_file_path
				if weapon_scene_path == "" and hardpoint.mounted_weapon:
					weapon_scene_path = hardpoint.mounted_weapon.resource_path
				if "ammo_count" in hardpoint.weapon_instance:
					ammo_count = int(hardpoint.weapon_instance.get("ammo_count"))
			elif hardpoint.mounted_weapon:
				weapon_scene_path = hardpoint.mounted_weapon.resource_path
			loadout.append({
				"path": str(aircraft.get_path_to(hardpoint)),
				"weapon_scene": weapon_scene_path,
				"ammo_count": ammo_count,
			})
	var selected_weapon_type := ""
	var control_weapons := aircraft.find_child("ControlWeapons", true, false)
	if control_weapons and "selected_weapon_type" in control_weapons:
		selected_weapon_type = str(control_weapons.selected_weapon_type)
	return {
		"hardpoints": loadout,
		"selected_weapon_type": selected_weapon_type,
	}

func _restore_aircraft_loadout_state(aircraft: RigidBody3D, loadout_state: Dictionary) -> void:
	var hardpoints: Array = loadout_state.get("hardpoints", [])
	for entry_variant in hardpoints:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var hardpoint := aircraft.get_node_or_null(NodePath(str(entry.get("path", "")))) as Hardpoint
		if hardpoint == null:
			continue
		if is_instance_valid(hardpoint.weapon_instance):
			hardpoint.weapon_instance.queue_free()
			hardpoint.weapon_instance = null
		var weapon_scene_path := str(entry.get("weapon_scene", ""))
		if weapon_scene_path == "":
			hardpoint.mounted_weapon = null
			continue
		var weapon_scene := load(weapon_scene_path) as PackedScene
		hardpoint.mounted_weapon = weapon_scene
		if weapon_scene:
			hardpoint.mount_weapon_from_scene(weapon_scene)
			if is_instance_valid(hardpoint.weapon_instance) and "ammo_count" in hardpoint.weapon_instance:
				hardpoint.weapon_instance.set("ammo_count", int(entry.get("ammo_count", hardpoint.weapon_instance.get("ammo_count"))))
	var control_weapons := aircraft.find_child("ControlWeapons", true, false)
	if control_weapons:
		if "aircraft" in control_weapons and control_weapons.aircraft == null:
			control_weapons.aircraft = aircraft
		if control_weapons.has_method("find_hardpoints"):
			control_weapons.find_hardpoints()
		if control_weapons.has_method("categorize_weapons"):
			control_weapons.categorize_weapons()
		var selected_weapon_type := str(loadout_state.get("selected_weapon_type", ""))
		if selected_weapon_type != "" and "weapon_types" in control_weapons and selected_weapon_type in control_weapons.weapon_types:
			control_weapons.selected_weapon_type = selected_weapon_type
			control_weapons.selected_weapon_type_index = control_weapons.weapon_types.find(selected_weapon_type)

func _apply_ai_loadout_profile(aircraft: RigidBody3D, profile: String) -> void:
	var normalized_profile := profile.strip_edges().to_lower()
	if normalized_profile == "":
		return
	# Resolve this once per materialized aircraft, not once per hardpoint, so a
	# random strike loadout is always a coherent pair of stores plus the gun.
	if normalized_profile == LOADOUT_RANDOM_GROUND_STRIKE:
		normalized_profile = LOADOUT_ROCKET_STRIKE if randi() % 2 == 0 else LOADOUT_BOMB_STRIKE
	aircraft.set_meta("resolved_ai_loadout_profile", normalized_profile)
	var hardpoints: Array[Hardpoint] = []
	for node in _get_all_children(aircraft):
		if node is Hardpoint:
			hardpoints.append(node as Hardpoint)
	if hardpoints.is_empty():
		return
	for i in range(hardpoints.size()):
		var hardpoint := hardpoints[i]
		if normalized_profile == LOADOUT_GUN_ONLY or normalized_profile == LOADOUT_INTERCEPT:
			if i == 0:
				_mount_weapon_scene_on_hardpoint(hardpoint, WEAPON_SCENE_20MM)
			else:
				_clear_hardpoint_weapon(hardpoint)
			continue
		var weapon_scene_path := _choose_ai_loadout_weapon_scene(hardpoint, i, normalized_profile)
		_mount_weapon_scene_on_hardpoint(hardpoint, weapon_scene_path)
	_refresh_weapon_controller_after_loadout(aircraft, normalized_profile)

func _choose_ai_loadout_weapon_scene(hardpoint: Hardpoint, hardpoint_index: int, profile: String) -> String:
	if profile == LOADOUT_CAP:
		var current_weapon_name := _get_hardpoint_weapon_name(hardpoint)
		if _is_gun_weapon_name(current_weapon_name):
			return ""
		if hardpoint_index == 0:
			return WEAPON_SCENE_ROCKET_POD
		return WEAPON_SCENE_20MM
	if profile == LOADOUT_STRIKE or profile == "cas":
		return WEAPON_SCENE_BOMB_RACK if hardpoint_index == 0 else WEAPON_SCENE_ROCKET_POD
	if profile == LOADOUT_COMBAT_TEST:
		if hardpoint_index == 0:
			return WEAPON_SCENE_BOMB_RACK
		if hardpoint_index == 1:
			return WEAPON_SCENE_ROCKET_POD
		return WEAPON_SCENE_20MM
	if profile == LOADOUT_ROCKET_STRIKE:
		# Aircraft_5 has three hardpoints. The full-cycle combat test needs two
		# finite 24-round rocket canisters and its normal gun, in that order.
		return WEAPON_SCENE_ROCKET_POD if hardpoint_index < 2 else WEAPON_SCENE_20MM
	if profile == LOADOUT_BOMB_STRIKE:
		return WEAPON_SCENE_BOMB_RACK if hardpoint_index < 2 else WEAPON_SCENE_20MM
	return ""

func _mount_weapon_scene_on_hardpoint(hardpoint: Hardpoint, weapon_scene_path: String) -> void:
	if hardpoint == null or weapon_scene_path == "":
		return
	var weapon_scene := load(weapon_scene_path) as PackedScene
	if weapon_scene == null:
		push_warning("[FlightDeckManager] Unable to load AI loadout weapon: %s" % weapon_scene_path)
		return
	if is_instance_valid(hardpoint.weapon_instance):
		hardpoint.weapon_instance.queue_free()
		hardpoint.weapon_instance = null
	hardpoint.mounted_weapon = weapon_scene
	hardpoint.mount_weapon_from_scene(weapon_scene)


func _clear_hardpoint_weapon(hardpoint: Hardpoint) -> void:
	if hardpoint == null:
		return
	if is_instance_valid(hardpoint.weapon_instance):
		hardpoint.weapon_instance.queue_free()
	hardpoint.weapon_instance = null
	hardpoint.mounted_weapon = null

func _get_hardpoint_weapon_name(hardpoint: Hardpoint) -> String:
	if hardpoint == null or not is_instance_valid(hardpoint.weapon_instance):
		return ""
	if "weapon_name" in hardpoint.weapon_instance:
		return str(hardpoint.weapon_instance.weapon_name)
	return ""

func _is_gun_weapon_name(weapon_name: String) -> bool:
	var lower_name := weapon_name.to_lower()
	return lower_name.find("autocannon") != -1 or lower_name.find("machine gun") != -1

func _refresh_weapon_controller_after_loadout(aircraft: RigidBody3D, profile: String) -> void:
	var control_weapons := aircraft.find_child("ControlWeapons", true, false)
	if not control_weapons:
		return
	if "aircraft" in control_weapons:
		control_weapons.aircraft = aircraft
	if control_weapons.has_method("find_hardpoints"):
		control_weapons.find_hardpoints()
	if control_weapons.has_method("categorize_weapons"):
		control_weapons.categorize_weapons()
	if not ("weapon_types" in control_weapons):
		return
	var preferred_type := "Autocannon"
	if profile == LOADOUT_STRIKE or profile == "cas" or profile == LOADOUT_COMBAT_TEST or profile == LOADOUT_BOMB_STRIKE:
		preferred_type = "Bomb"
	elif profile == LOADOUT_ROCKET_STRIKE:
		preferred_type = "Rocket Pod"
	var selected_idx := -1
	for i in range(control_weapons.weapon_types.size()):
		var weapon_type := str(control_weapons.weapon_types[i])
		if weapon_type == preferred_type or (preferred_type == "Autocannon" and _is_gun_weapon_name(weapon_type)):
			selected_idx = i
			break
	if selected_idx == -1 and control_weapons.weapon_types.size() > 0:
		selected_idx = 0
	if selected_idx != -1:
		control_weapons.selected_weapon_type_index = selected_idx
		control_weapons.selected_weapon_type = control_weapons.weapon_types[selected_idx]

func _restore_aircraft_runtime_state_deferred(aircraft: RigidBody3D, aircraft_data: Dictionary) -> void:
	if not is_instance_valid(aircraft):
		return
	await get_tree().process_frame
	if not is_instance_valid(aircraft):
		return
	if aircraft_data.has("current_health") and "current_health" in aircraft:
		aircraft.set("current_health", float(aircraft_data.get("current_health", aircraft.get("current_health"))))
	_restore_aircraft_energy_state(aircraft, aircraft_data.get("energy_state", []))
	_restore_aircraft_loadout_state(aircraft, aircraft_data.get("loadout_state", {}))
	_apply_ai_loadout_profile(aircraft, str(aircraft_data.get("requested_ai_loadout_profile", "")))

func _extract_aircraft_data(aircraft: RigidBody3D) -> Dictionary:
	"""Extract aircraft data for storage"""
	var scene_file := aircraft.scene_file_path if aircraft.scene_file_path else ""
	var data = {
		"name": aircraft.name,
		"scene_file": scene_file,
		"scene": load(scene_file) as PackedScene if scene_file != "" else null,
		"position": aircraft.global_position,
		"rotation": aircraft.global_rotation,
		"scale": aircraft.scale,
		"current_health": aircraft.get("current_health"),
		"energy_state": _capture_aircraft_energy_state(aircraft),
		"loadout_state": _capture_aircraft_loadout_state(aircraft),
		# Store any custom properties you want to preserve
		"metadata": {}
	}

	# Copy any metadata
	for key in aircraft.get_meta_list():
		if str(key).begins_with(HELI_TEST_STAT_META_PREFIX):
			continue
		data.metadata[key] = aircraft.get_meta(key)

	return data

func _select_hangar_launch_index() -> int:
	## Which stored aircraft to launch next. For an AI COMBAT flight launch (a flight-ops scramble), skip
	## utility helicopters (Aircraft_11) -- they're prepended in the hangar for rescue readiness and must
	## NOT be scrambled as fighters. Explicit retrievals (debug key / rescue) push_front their chosen
	## aircraft, so index 0 is correct for them.
	if stored_aircraft.is_empty():
		return -1
	# An AI operations launch is in progress when there's a pending callback target.
	# Select by capability so utility helicopters cannot be scrambled as fighters,
	# while helicopter missions can explicitly retrieve one from the same hangar.
	var ai_ops_launch: bool = _pending_flight_ops != null and not _retrieval_ai_land_after_launch
	if ai_ops_launch:
		for i in range(stored_aircraft.size()):
			var stored_data := stored_aircraft[i] as Dictionary
			var is_helicopter := _stored_aircraft_is_helicopter(stored_data)
			if (_pending_ai_aircraft_kind == "helicopter" and is_helicopter) \
					or (_pending_ai_aircraft_kind != "helicopter" and not is_helicopter):
				if not _pending_ai_aircraft_model.is_empty() \
						and not _stored_aircraft_matches_model(stored_data, _pending_ai_aircraft_model):
					continue
				return i
		# No aircraft of the requested capability is available.
		return -1
	return 0


func _count_stored_aircraft_for_kind(kind: String, aircraft_model: String = "") -> int:
	var count := 0
	for stored_variant in stored_aircraft:
		if not (stored_variant is Dictionary):
			continue
		var is_helicopter := _stored_aircraft_is_helicopter(stored_variant as Dictionary)
		if not aircraft_model.is_empty() \
				and not _stored_aircraft_matches_model(stored_variant as Dictionary, aircraft_model):
			continue
		if (kind == "helicopter" and is_helicopter) \
				or (kind != "helicopter" and not is_helicopter):
			count += 1
	return count


func _stored_aircraft_matches_model(stored_data: Dictionary, aircraft_model: String) -> bool:
	var needle := aircraft_model.strip_edges().to_lower()
	if needle.is_empty():
		return true
	var stored_name := str(stored_data.get("name", "")).to_lower()
	var scene_file := str(stored_data.get("scene_file", "")).to_lower()
	return stored_name.contains(needle) or scene_file.contains(needle)


func _stored_aircraft_is_helicopter(stored_data: Dictionary) -> bool:
	var stored_name := str(stored_data.get("name", "")).to_lower()
	var scene_file := str(stored_data.get("scene_file", "")).to_lower()
	var metadata_variant: Variant = stored_data.get("metadata", {})
	var role := ""
	if metadata_variant is Dictionary:
		role = str((metadata_variant as Dictionary).get("aircraft_role", "")).to_lower()
	return stored_name.begins_with("aircraft_9") \
			or stored_name.begins_with("aircraft_10") \
			or stored_name.begins_with("aircraft_11") \
			or scene_file.contains("aircraft_9.tscn") \
			or scene_file.contains("aircraft_10.tscn") \
			or scene_file.contains("aircraft_11.tscn") \
			or role.contains("helicopter")

func _create_aircraft_at_hangar_level() -> RigidBody3D:
	"""Create aircraft at hangar level from stored data and template"""
	if stored_aircraft.is_empty():
		return null

	var idx := _select_hangar_launch_index()
	if idx < 0:
		# No suitable aircraft (e.g. an AI scramble but only utility helicopters remain).
		return null
	var aircraft_data = stored_aircraft[idx]
	if not _ensure_pilot_assigned_for_data(aircraft_data):
		push_warning("[FlightDeckManager] Retrieval blocked: no available pilot for aircraft.")
		return null
	if not _pending_ai_loadout_profile.is_empty():
		aircraft_data["requested_ai_loadout_profile"] = _pending_ai_loadout_profile
	stored_aircraft[idx] = aircraft_data
	_pending_launch_hangar_index = idx

	# Use scene embedded in data dict (e.g. Aircraft 2), otherwise fall back to template
	var scene_to_use: PackedScene = aircraft_data.get("scene", null)
	if not scene_to_use:
		var scene_file := str(aircraft_data.get("scene_file", ""))
		if scene_file != "":
			scene_to_use = load(scene_file) as PackedScene
	if not scene_to_use:
		scene_to_use = aircraft_template_scene
	if not scene_to_use:
		scene_to_use = load(DEFAULT_AIRCRAFT_SCENE_PATH)
		if not scene_to_use:
			return null


	# Instantiate new aircraft from template
	var aircraft = scene_to_use.instantiate() as RigidBody3D
	if not aircraft:
		return null

	# Mute all controls immediately — before add_child so _physics_process never sees an open throttle.
	aircraft.set_meta("controls_disabled", true)
	aircraft.set_meta("carrier_transport_mode", true)
	_aircraft_original_collision_layer = aircraft.collision_layer
	_aircraft_original_collision_mask = aircraft.collision_mask
	aircraft.freeze = true
	aircraft.gravity_scale = 0.0
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.collision_layer = 0
	aircraft.collision_mask = 0

	# Add to scene
	var main_scene = get_tree().current_scene
	main_scene.add_child(aircraft)

	# Restore aircraft properties from stored data
	_retrieval_sequence += 1
	aircraft.name = "%s_%d" % [aircraft_data.name, _retrieval_sequence]

	# Position aircraft on elevator platform at hangar level (where elevator currently is)
	if elevator_pickup_marker and elevator_pickup_marker is Node3D:
		(elevator_pickup_marker as Node3D).force_update_transform()
	var elevator_hangar_pos = elevator_pickup_marker.global_position
	elevator_hangar_pos.y = _get_elevator_platform_top_global_y(-10.0) + _get_gear_ground_offset(aircraft)
	aircraft.global_position = elevator_hangar_pos

	# Face aircraft toward deck forward (carrier's +Z) during retrieval
	var carrier_fwd := (get_parent() as Node3D).global_transform.basis.z
	aircraft.global_rotation = Vector3(0, atan2(carrier_fwd.x, carrier_fwd.z), 0)
	aircraft.scale = aircraft_data.scale
	if _is_helicopter_aircraft(aircraft):
		_straighten_retrieved_helicopter_on_deck(aircraft)
	else:
		_place_fixed_wing_in_static_suspension_pose(
			aircraft,
			_get_elevator_platform_top_global_y(-10.0)
		)

	# Restore metadata
	for key in aircraft_data.metadata:
		aircraft.set_meta(key, aircraft_data.metadata[key])
	if _is_helicopter_aircraft(aircraft):
		_straighten_retrieved_helicopter_on_deck(aircraft)
	_restore_aircraft_runtime_state_deferred.call_deferred(aircraft, aircraft_data)
	_resolve_carrier_manager()
	if not is_instance_valid(carrier_manager) or not carrier_manager.bind_pilot_to_live_aircraft(aircraft, aircraft_data):
		aircraft.queue_free()
		return null

	# Keep aircraft fully still during elevator movement.
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	return aircraft

func _spawn_tractorbots_at_aircraft(aircraft: RigidBody3D):
	"""Spawn tractorbots directly at aircraft wheel positions at hangar level"""

	var gear_colliders: Array[Node3D] = _get_launch_wheel_nodes(aircraft)
	if gear_colliders.is_empty():
		return

	# Position tractorbots directly at aircraft wheels
	for i in range(min(tractor_bots.size(), gear_colliders.size())):
		var bot = tractor_bots[i]
		var gear_collider = gear_colliders[i]
		if bot and gear_collider:
			# Position bot directly at the gear collider location
			bot.global_position = gear_collider.global_position
			bot.global_position.y = _get_elevator_platform_top_global_y(-10.0) + tractor_elevator_floor_offset_m

			# Activate bot for the aircraft
			if bot.has_method("activate"):
				var wheel_offset = gear_collider.global_position - aircraft.global_position
				bot.activate(aircraft, wheel_offset, gear_collider)
				bot.set("is_positioned", true)
			if bot.has_method("disable_movement"):
				bot.disable_movement()
	_tractorbots_in_hangar = false

func _start_elevator_sequence(aircraft: RigidBody3D):
	"""Start the elevator sequence - aircraft and tractorbots follow elevator down"""

	# Set state to STORING_IN_HANGAR so elevator signals work properly
	current_state = DeckState.STORING_IN_HANGAR
	_recovery_debug("elevator sequence started")
	_retrieval_top_handled = false

	# Ensure elevator signals are connected
	_ensure_elevator_signal_connections()

	# Keep active recovery tractorbots coupled to the aircraft during descent.
	_disable_tractor_bot_movement()

	# Start elevator moving down
	elevator.move_platform_down()

	# Start following the elevator with aircraft and tractorbots
	_follow_elevator_down(aircraft)


func _follow_elevator_down(aircraft: RigidBody3D):
	"""Make aircraft and tractorbots follow the elevator down"""
	if not is_instance_valid(aircraft):
		_recovery_debug("follow elevator down skipped: invalid aircraft")
		return
	
	# Store reference to aircraft for elevator following
	_pending_store_aircraft = aircraft
	var aircraft_name := _aircraft_debug_name(aircraft)
	var last_aircraft_position := aircraft.global_position
	
	# Get initial positions relative to deck level (not elevator platform)
	var deck_height = _get_deck_height_y()
	var initial_aircraft_position = aircraft.global_position
	var fixed_wing_surface_offset: float = aircraft.global_position.y - deck_height
	var active_bots: Array[Node3D] = []
	var active_bot_offsets: Array[Vector3] = []
	for bot in tractor_bots:
		if bot and bot is Node3D and bool(bot.get("is_active")):
			active_bots.append(bot as Node3D)
			active_bot_offsets.append((bot as Node3D).global_position - aircraft.global_position)
	_set_manual_transport(aircraft, true)
	for bot in active_bots:
		_set_manual_transport(bot, true)
	var carrier := get_parent() as Node3D
	var aircraft_carrier_local: Vector3 = carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
	var aircraft_carrier_local_basis: Basis = carrier.global_transform.basis.inverse() * aircraft.global_transform.basis if carrier else aircraft.global_transform.basis
	
	# Calculate the aircraft's gear offset from its center
	var gear_colliders = _find_gear_colliders(aircraft)
	var lowest_gear_local_y = INF
	for gear in gear_colliders:
		var local_y = aircraft.to_local(gear.global_position).y
		if local_y < lowest_gear_local_y:
			lowest_gear_local_y = local_y
	
	# Calculate how much the aircraft center needs to be offset to position gear 0.2m above elevator
	var gear_offset_from_aircraft_center = lowest_gear_local_y
	var target_gear_height_above_elevator = 0.2  # 20cm above elevator platform
	
	# Start following the elevator platform
	while is_instance_valid(aircraft) and is_instance_valid(elevator) and not _is_elevator_physically_at_bottom():
		var elevator_top_y = _get_elevator_platform_top_global_y(-10.0)

		var target_aircraft_y: float
		if _is_helicopter_aircraft(aircraft):
			# Legacy helicopter transport clearance.
			var target_gear_height = elevator_top_y + target_gear_height_above_elevator
			target_aircraft_y = target_gear_height - gear_offset_from_aircraft_center
		else:
			target_aircraft_y = elevator_top_y + fixed_wing_surface_offset

		# Only update Y — carrier delta (LandCarrier._carry_deck_passengers) handles XZ
		if carrier:
			var aircraft_transform := aircraft.global_transform
			aircraft_transform.origin = carrier.to_global(aircraft_carrier_local)
			aircraft_transform.origin.y = target_aircraft_y
			aircraft_transform.basis = (carrier.global_transform.basis * aircraft_carrier_local_basis).orthonormalized()
			aircraft.global_transform = aircraft_transform
			_sync_rigidbody_transform_state(aircraft)
		else:
			aircraft.global_position.y = target_aircraft_y
			_sync_rigidbody_transform_state(aircraft)
		aircraft.angular_velocity = Vector3.ZERO
		last_aircraft_position = aircraft.global_position
		for i in range(min(active_bots.size(), active_bot_offsets.size())):
			if is_instance_valid(active_bots[i]):
				var bot_position: Vector3 = aircraft.global_position + active_bot_offsets[i]
				bot_position.y = elevator_top_y + tractor_elevator_floor_offset_m
				active_bots[i].global_position = bot_position
		await get_tree().physics_frame

	if not is_instance_valid(aircraft):
		_recovery_debug("aircraft became invalid while following elevator down name=%s last_pos=%s elevator_state=%s elevator_y=%.1f active_bots=%d" % [
			aircraft_name,
			_fmt_vec3(last_aircraft_position),
			str(elevator.current_state) if is_instance_valid(elevator) else "invalid",
			_get_elevator_platform_top_global_y(-10.0) if is_instance_valid(elevator) else NAN,
			active_bots.size(),
		])
		for bot in active_bots:
			_set_manual_transport(bot, false)
		return

	for i in range(min(active_bots.size(), active_bot_offsets.size())):
		if is_instance_valid(active_bots[i]):
			var bot_position: Vector3 = aircraft.global_position + active_bot_offsets[i]
			bot_position.y = _get_elevator_platform_top_global_y(-10.0) + tractor_elevator_floor_offset_m
			active_bots[i].global_position = bot_position
			_set_cleanup_idle_for_tractor_bot(active_bots[i])
			_set_manual_transport(active_bots[i], false)
	_set_manual_transport(aircraft, false)
	_tractorbots_in_hangar = not active_bots.is_empty()

	_recovery_debug("elevator reached bottom")

func _restore_aircraft_physics(aircraft_ref: Variant, keep_frozen: bool = false):
	"""Restore aircraft physics for launch.
	keep_frozen=true restores collisions/gravity but skips the unfreeze,
	used by the retrieval path where the aircraft is already correctly positioned."""
	if not is_instance_valid(aircraft_ref) or not (aircraft_ref is RigidBody3D):
		_recovery_debug("restore aircraft physics skipped: invalid aircraft")
		return
	var aircraft := aircraft_ref as RigidBody3D

	# Force aircraft to be completely still first
	aircraft.freeze = true
	aircraft.set_gravity_scale(0.0)
	aircraft.collision_layer = 0
	aircraft.collision_mask = 0

	# Clear ALL forces and momentum aggressively
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.constant_force = Vector3.ZERO
	aircraft.constant_torque = Vector3.ZERO

	# Short frame-based settle to avoid long pauses during retrieval->launch handoff
	await get_tree().physics_frame
	if not is_instance_valid(aircraft):
		_recovery_debug("restore aircraft physics aborted after first frame: invalid aircraft")
		return

	# Clear again after waiting
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	# Enable physics but keep aircraft frozen initially
	aircraft.set_gravity_scale(1.0)

	# Let gravity/physics state apply for a frame
	await get_tree().physics_frame
	if not is_instance_valid(aircraft):
		_recovery_debug("restore aircraft physics aborted after gravity frame: invalid aircraft")
		return

	# Clear velocities one more time before unfreezing
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	var default_layer = 513  # Layers 0 and 9 (binary 1000000001)
	var default_mask = 513

	if keep_frozen:
		# Retrieval path: aircraft is already correctly positioned on the deck.
		# Restore collisions and gravity without unfreezing — avoids the moving
		# deck surface pushing the aircraft before begin_sequence freezes it.
		aircraft.set_gravity_scale(1.0)
		aircraft.collision_layer = _aircraft_original_collision_layer if _aircraft_original_collision_layer != 0 else default_layer
		aircraft.collision_mask  = _aircraft_original_collision_mask  if _aircraft_original_collision_mask  != 0 else default_mask
		if aircraft.has_meta("carrier_transport_mode") and not _is_helicopter_aircraft(aircraft):
			aircraft.remove_meta("carrier_transport_mode")
		return

	# Normal path: aircraft was teleported to catapult, needs a brief unfreeze
	# so it can settle onto the deck under gravity before the catapult latches.
	aircraft.freeze = false
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	await get_tree().physics_frame
	if not is_instance_valid(aircraft):
		_recovery_debug("restore aircraft physics aborted after unfreeze frame: invalid aircraft")
		return

	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	aircraft.collision_layer = _aircraft_original_collision_layer if _aircraft_original_collision_layer != 0 else default_layer
	aircraft.collision_mask  = _aircraft_original_collision_mask  if _aircraft_original_collision_mask  != 0 else default_mask

	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	if aircraft.has_meta("carrier_transport_mode"):
		aircraft.remove_meta("carrier_transport_mode")


func _start_retrieval_ascent_sequence(aircraft: RigidBody3D):
	"""Start the elevator ascent with aircraft and tractorbots"""
	if _is_helicopter_aircraft(aircraft):
		_straighten_retrieved_helicopter_on_deck(aircraft)

	# Tractorbots are already spawned at aircraft wheels, so just start elevator
	_spawn_tractorbots_at_aircraft(aircraft)
	_disable_tractor_bot_movement()

	# Start elevator moving up
	_retrieval_top_handled = false
	_ensure_elevator_signal_connections()
	elevator.move_platform_up()

	# Follow elevator up with aircraft and tractorbots
	_follow_elevator_up_for_retrieval(aircraft)

func _follow_elevator_up_for_retrieval(aircraft: RigidBody3D):
	"""Make aircraft and tractorbots follow the elevator up during retrieval"""
	if not is_instance_valid(aircraft):
		return

	# Disable collisions for the entire elevator ride — the aircraft passes through
	# the carrier structure and must not take damage from it.
	aircraft.collision_layer = 0
	aircraft.collision_mask = 0
	aircraft.freeze = true

	# Get initial positions relative to deck level
	var deck_height = _get_deck_height_y()
	var active_bots: Array[Node3D] = []
	var active_bot_offsets: Array[Vector3] = []
	for bot in tractor_bots:
		if bot and bot is Node3D and bool(bot.get("is_active")):
			active_bots.append(bot as Node3D)
			active_bot_offsets.append((bot as Node3D).global_position - aircraft.global_position)
	_set_manual_transport(aircraft, true)
	for bot in active_bots:
		_set_manual_transport(bot, true)
	var carrier := get_parent() as Node3D
	var aircraft_carrier_local: Vector3 = carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
	var aircraft_carrier_local_basis: Basis = carrier.global_transform.basis.inverse() * aircraft.global_transform.basis if carrier else aircraft.global_transform.basis
	var initial_elevator_top_y: float = _get_elevator_platform_top_global_y(-10.0)
	var fixed_wing_surface_offset: float = aircraft.global_position.y - initial_elevator_top_y

	# Calculate gear offset from aircraft center using global Y (tilt-safe).
	# gear_to_body_offset = how far the aircraft body is above its lowest gear.
	var gear_colliders = _find_gear_colliders(aircraft)
	var lowest_gear_global_y := INF
	for gear in gear_colliders:
		if (gear as Node3D).global_position.y < lowest_gear_global_y:
			lowest_gear_global_y = (gear as Node3D).global_position.y
	var gear_to_body_offset := aircraft.global_position.y - lowest_gear_global_y
	var target_gear_height_above_elevator = 0.2  # 20cm above elevator platform

	# Follow until the platform is physically at top, not just state transitions.
	while is_instance_valid(aircraft) and is_instance_valid(elevator) and not _is_elevator_physically_at_top():
		var elevator_top_y = _get_elevator_platform_top_global_y(-10.0)

		var target_aircraft_y: float
		if _is_helicopter_aircraft(aircraft):
			# Aircraft body sits gear_to_body_offset above where the gear needs to be.
			var target_gear_height = elevator_top_y + target_gear_height_above_elevator
			target_aircraft_y = target_gear_height + gear_to_body_offset
		else:
			target_aircraft_y = elevator_top_y + fixed_wing_surface_offset

		# Only update Y — carrier delta (LandCarrier._carry_deck_passengers) handles XZ
		if carrier:
			var aircraft_transform := aircraft.global_transform
			aircraft_transform.origin = carrier.to_global(aircraft_carrier_local)
			aircraft_transform.origin.y = target_aircraft_y
			aircraft_transform.basis = (carrier.global_transform.basis * aircraft_carrier_local_basis).orthonormalized()
			aircraft.global_transform = aircraft_transform
			_sync_rigidbody_transform_state(aircraft)
		else:
			aircraft.global_position.y = target_aircraft_y
			_sync_rigidbody_transform_state(aircraft)
		aircraft.angular_velocity = Vector3.ZERO
		for i in range(min(active_bots.size(), active_bot_offsets.size())):
			if is_instance_valid(active_bots[i]):
				var bot_position: Vector3 = aircraft.global_position + active_bot_offsets[i]
				bot_position.y = elevator_top_y + tractor_elevator_floor_offset_m
				active_bots[i].global_position = bot_position

		await get_tree().physics_frame

	if not is_instance_valid(aircraft):
		for bot in active_bots:
			_set_manual_transport(bot, false)
		return

	for i in range(min(active_bots.size(), active_bot_offsets.size())):
		if is_instance_valid(active_bots[i]):
			var bot_position: Vector3 = aircraft.global_position + active_bot_offsets[i]
			bot_position.y = _get_elevator_platform_top_global_y(-0.5) + tractor_elevator_floor_offset_m
			active_bots[i].global_position = bot_position
			_set_manual_transport(active_bots[i], false)
	_set_manual_transport(aircraft, false)

	# Signal timing can vary (elevator_at_top/covers_opened may have fired early).
	# Force the handoff once we have physically reached top.
	if current_state == DeckState.RETRIEVING_FROM_HANGAR and not _retrieval_top_handled:
		_on_elevator_at_top()

func _complete_retrieval_sequence():
	"""Complete the retrieval by moving aircraft to launch position and restoring physics"""
	if _landing_test_active:
		if is_instance_valid(deck_aircraft):
			deck_aircraft.queue_free()
		deck_aircraft = null
		current_state = DeckState.IDLE
		return

	var aircraft = deck_aircraft
	if not is_instance_valid(aircraft):
		deck_aircraft = null
		current_state = DeckState.IDLE
		return
	if _is_helicopter_aircraft(aircraft):
		await _complete_helicopter_retrieval_sequence(aircraft)
		return

	var active_bots: Array[Node] = []
	for bot in tractor_bots:
		if bot and bool(bot.get("is_active")):
			active_bots.append(bot)
	if active_bots.is_empty():
		await _prepare_tractorbots_for_recovery_job()
		active_bots = _activate_tractor_bots(aircraft)
		if not active_bots.is_empty():
			await _wait_for_tractor_bots_positioned(active_bots)
	if not is_instance_valid(aircraft):
		return

	# Resolve the catapult position only after the tractor waits. FloatingOrigin
	# may shift the whole world during those awaits; retaining the earlier global
	# coordinate would turn that shift into a multi-kilometre aircraft teleport.
	var target_position := Vector3.ZERO
	var launch_marker: Node = get_tree().current_scene.find_child("catapult_latch_marker", true, false)
	if launch_marker is Node3D:
		var launch_marker_3d := launch_marker as Node3D
		var carrier := get_parent() as Node3D
		if carrier != null:
			carrier.force_update_transform()
		launch_marker_3d.force_update_transform()
		target_position = launch_marker_3d.global_position
	else:
		# Fallback - position forward of elevator
		if elevator_pickup_marker is Node3D:
			(elevator_pickup_marker as Node3D).force_update_transform()
			target_position = elevator_pickup_marker.global_position + Vector3(0, 0, 20)

	var deck_height = _get_deck_height_y()
	var gear_colliders = _find_gear_colliders(aircraft)
	var target_gear_height = deck_height + _aircraft_lift_height  # deck + 0.2m

	if not _is_helicopter_aircraft(aircraft) and not gear_colliders.is_empty():
		# Elevator travel already preserved the static suspension surface offset.
		# Keep that exact body height during the horizontal catapult transfer.
		await _move_aircraft_horizontally(
			aircraft,
			Vector3(target_position.x, aircraft.global_position.y, target_position.z)
		)
	elif not gear_colliders.is_empty():
		# Find lowest gear collider offset
		var lowest_gear_local_y = INF
		for gear in gear_colliders:
			var local_y = aircraft.to_local(gear.global_position).y
			if local_y < lowest_gear_local_y:
				lowest_gear_local_y = local_y

		# Calculate aircraft Y position to maintain gear at deck + 0.2m
		var lift_aircraft_y = target_gear_height - lowest_gear_local_y
		var lift_target_position = Vector3(target_position.x, lift_aircraft_y, target_position.z)

		# Move to launch position while maintaining lift
		await _move_aircraft_horizontally(aircraft, lift_target_position)
	else:
		# Fallback if no gear colliders found
		await _move_aircraft_smoothly(aircraft, target_position)

	# Re-enable physics at launch position. Keep the body frozen so the moving
	# deck doesn't push it before the catapult takes over.
	await _restore_aircraft_physics(aircraft, true)
	if not is_instance_valid(aircraft):
		_recovery_debug("retrieval completion aborted after restore: aircraft invalid")
		return

	# Lower the frozen aircraft so its wheels sit on the flight deck.
	# Must happen before tractor bots leave so they can support the aircraft.
	var deck_y := _get_deck_height_y()
	var landing_gear_nodes := _get_launch_wheel_nodes(aircraft)
	_settle_launch_aircraft_on_wheels(aircraft, landing_gear_nodes, deck_y)

	aircraft.set_meta("physics_ready_for_launch", true)

	# Retrieved aircraft stay AI-controlled until the player explicitly takes over.
	_configure_retrieved_aircraft_as_ai(aircraft, _retrieval_ai_land_after_launch)

	# Keep this retrieval operation and its aircraft reserved at the catapult until
	# every launch interlock is clear. request_launch_sequence() rejects a blocked
	# request rather than queuing it; returning from this function after such a
	# rejection lets later hangar work overwrite deck_aircraft and stack another
	# plane on the same latch marker.
	while is_instance_valid(aircraft):
		if _is_carrier_turning_for_launch(true):
			await get_tree().physics_frame
			continue
		if not _launch_path_clear_of_terrain():
			var now_cliff_s := Time.get_ticks_msec() / 1000.0
			if now_cliff_s >= _launch_terrain_block_log_s:
				_launch_terrain_block_log_s = now_cliff_s + 2.0
				_recovery_debug("launch held: terrain/cliff ahead on departure path")
			await get_tree().physics_frame
			continue
		break
	if not is_instance_valid(aircraft):
		return

	# Automatically start launch sequence
	request_launch_sequence(aircraft)
	_send_primary_tractorbots_to_hangar.call_deferred()


func _complete_helicopter_retrieval_sequence(aircraft: RigidBody3D) -> void:
	"""Move helicopters to a deck takeoff spot and skip the catapult launch."""
	var target_position := _get_helicopter_takeoff_position()
	if _heli_test_active:
		_log_heli_test("helicopter retrieval begin aircraft=%s pos=%s target=%s active_bots=%d" % [
			_aircraft_debug_name(aircraft),
			_fmt_vec3(aircraft.global_position) if is_instance_valid(aircraft) else "?",
			_fmt_vec3(target_position),
			tractor_bots.filter(func(bot): return bot and bool(bot.get("is_active"))).size(),
		])

	var active_bots: Array[Node] = []
	for bot in tractor_bots:
		if bot and bool(bot.get("is_active")):
			active_bots.append(bot)
	if active_bots.is_empty():
		await _prepare_tractorbots_for_recovery_job()
		if not is_instance_valid(aircraft):
			return
		active_bots = _activate_tractor_bots(aircraft)
		if not active_bots.is_empty():
			await _wait_for_tractor_bots_positioned(active_bots)

	if not is_instance_valid(aircraft):
		return
	# As with the fixed-wing catapult target, refresh this world coordinate after
	# tractor waits so an origin shift cannot leave the helicopter at the old origin.
	target_position = _get_helicopter_takeoff_position()
	var deck_height := _get_deck_height_y()
	var gear_colliders := _find_gear_colliders(aircraft)
	var target_gear_height := deck_height + _aircraft_lift_height
	if not gear_colliders.is_empty():
		# Use global Y so tilt doesn't corrupt the offset calculation.
		var lowest_gear_global_y := INF
		for gear in gear_colliders:
			if (gear as Node3D).global_position.y < lowest_gear_global_y:
				lowest_gear_global_y = (gear as Node3D).global_position.y
		var gear_to_body_offset := aircraft.global_position.y - lowest_gear_global_y
		var lift_aircraft_y := target_gear_height + gear_to_body_offset
		await _move_aircraft_horizontally(aircraft, Vector3(target_position.x, lift_aircraft_y, target_position.z))
	else:
		await _move_aircraft_smoothly(aircraft, target_position)

	if not is_instance_valid(aircraft):
		return
	if _heli_test_active:
		_log_heli_test("helicopter retrieval moved to deck spot aircraft=%s pos=%s" % [
			_aircraft_debug_name(aircraft),
			_fmt_vec3(aircraft.global_position),
		])
	await _restore_aircraft_physics(aircraft, true)
	if not is_instance_valid(aircraft):
		return
	var _settle_profiler_start: int = FrameProfiler.begin("FlightDeckManager.heli_retrieval_settle")
	var landing_gear_nodes := _get_launch_wheel_nodes(aircraft)
	_settle_launch_aircraft_on_wheels(aircraft, landing_gear_nodes, deck_height)
	_straighten_retrieved_helicopter_on_deck(aircraft)
	# Final safety pass: ensure no gear collider is below the deck surface.
	var heli_gear_colliders := _find_gear_colliders(aircraft)
	if not heli_gear_colliders.is_empty():
		var lowest_y := INF
		for g in heli_gear_colliders:
			var gy: float = (g as Node3D).global_position.y
			if gy < lowest_y:
				lowest_y = gy
		if lowest_y < deck_height:
			aircraft.global_position.y += deck_height - lowest_y
	FrameProfiler.end("FlightDeckManager.heli_retrieval_settle", _settle_profiler_start)

	var _ai_profiler_start: int = FrameProfiler.begin("FlightDeckManager.heli_retrieval_ai_enable")
	var heli_pilot := aircraft.find_child("HelicopterPilot", true, false)
	if heli_pilot != null and bool(aircraft.get_meta(HELI_NAVIGATION_TEST_META, false)):
		# This scenario measures the real LZ/path/recovery loop. Combat would turn an
		# outbound navigation trial into a different test entirely.
		heli_pilot.set("combat_enabled", false)
		heli_pilot.set("atk_enabled", false)
		heli_pilot.set("combat_tuning_enabled", false)
		if not aircraft.has_meta(HELI_NAVIGATION_TUNING_ASSIGNMENT_META):
			var nav_slot := int(aircraft.get_meta(HELI_NAVIGATION_ROUTE_SLOT_META, -1))
			var tuning_assignment := _navigation_begin_tuning_trial(aircraft, heli_pilot, nav_slot)
			if not tuning_assignment.is_empty():
				aircraft.set_meta(HELI_NAVIGATION_TUNING_ASSIGNMENT_META, tuning_assignment)
	var ai_heli_landed := heli_pilot != null and heli_pilot.is_physics_processing()
	if not ai_heli_landed:
		_configure_retrieved_aircraft_as_player(aircraft)
	if not aircraft.is_in_group("friendlies"):
		aircraft.add_to_group("friendlies")
	if not ai_heli_landed and aircraft.is_in_group("ai_aircraft"):
		aircraft.remove_from_group("ai_aircraft")
	if aircraft.has_meta("controls_disabled"):
		aircraft.remove_meta("controls_disabled")
	if aircraft.has_meta("physics_ready_for_launch"):
		aircraft.remove_meta("physics_ready_for_launch")
	aircraft.set_meta("parking_brake", true)
	aircraft.set_meta("helicopter_deck_takeoff_ready", true)
	record_heli_stat(aircraft, "spawned")
	if aircraft.has_meta("carrier_transport_mode"):
		aircraft.remove_meta("carrier_transport_mode")
	var carrier_node := get_parent() as Node
	if carrier_node == null or not carrier_node.has_method("get_deck_reference_velocity_vector"):
		carrier_node = get_tree().get_first_node_in_group("carrier")
	var deck_velocity := Vector3.ZERO
	if carrier_node != null:
		deck_velocity = _get_node_velocity(carrier_node)
		aircraft.set_meta("helicopter_deck_reference_node", carrier_node)
		_set_aircraft_reference_node(aircraft, carrier_node)
	aircraft.freeze = true
	aircraft.linear_velocity = deck_velocity
	aircraft.angular_velocity = Vector3.ZERO
	if not ai_heli_landed:
		var ai_toggle = aircraft.find_child("AIToggle", true, false)
		if ai_toggle and ai_toggle.has_method("enable_ai"):
			ai_toggle.enable_ai()
	FrameProfiler.end("FlightDeckManager.heli_retrieval_ai_enable", _ai_profiler_start)

	current_state = DeckState.AIRCRAFT_ON_DECK
	deck_aircraft = aircraft
	if _pending_ai_aircraft_kind == "helicopter":
		_notify_pending_ops_launched(heli_pilot)
		if _ai_launch_queue <= 0:
			_pending_flight_ops = null
			_retrieval_ai_land_after_launch = true
			_pending_ai_loadout_profile = ""
			_pending_ai_aircraft_kind = "fixed_wing"
			_pending_ai_aircraft_model = ""
	if _heli_test_active:
		_log_heli_test("helicopter retrieval complete aircraft=%s freeze=%s brake=%s ready=%s transport=%s pos=%s" % [
			_aircraft_debug_name(aircraft),
			str(aircraft.freeze),
			str(bool(aircraft.get_meta("parking_brake", false))),
			str(bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false))),
			str(bool(aircraft.get_meta("carrier_transport_mode", false))),
			_fmt_vec3(aircraft.global_position),
		])
	_send_primary_tractorbots_to_hangar.call_deferred()


func _straighten_retrieved_helicopter_on_deck(aircraft: RigidBody3D) -> void:
	if not is_instance_valid(aircraft):
		return
	aircraft.global_rotation = Vector3(0.0, _get_carrier_forward_yaw(), 0.0)
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO


func _get_helicopter_takeoff_position() -> Vector3:
	var carrier := get_parent() as Node3D
	if carrier == null:
		if elevator_pickup_marker and elevator_pickup_marker is Node3D:
			(elevator_pickup_marker as Node3D).force_update_transform()
			return elevator_pickup_marker.global_position + Vector3(0, 0, 36.0)
		return Vector3.ZERO

	carrier.force_update_transform()
	if elevator_pickup_marker and elevator_pickup_marker is Node3D:
		(elevator_pickup_marker as Node3D).force_update_transform()

	var elevator_local := Vector3.ZERO
	if elevator_pickup_marker and elevator_pickup_marker is Node3D:
		elevator_local = carrier.to_local((elevator_pickup_marker as Node3D).global_position)

	var front_local_z := 72.0
	var deck_end := carrier.get_node_or_null("DeckCenterEnd") as Node3D
	if deck_end != null:
		deck_end.force_update_transform()
		front_local_z = carrier.to_local(deck_end.global_position).z

	var target_local := elevator_local
	target_local.x = 0.0
	target_local.y = _get_deck_local_y()
	target_local.z = lerpf(elevator_local.z, front_local_z, 0.5)
	
	var final_pos = carrier.to_global(target_local)
	if _heli_test_active:
		print("[HeliTest] _get_helicopter_takeoff_position: carrier_pos=%s elevator_marker_global=%s elevator_local=%s front_local_z=%.1f target_local=%s final_pos_global=%s" % [
			str(carrier.global_position),
			str((elevator_pickup_marker as Node3D).global_position) if elevator_pickup_marker else "none",
			str(elevator_local),
			front_local_z,
			str(target_local),
			str(final_pos)
		])
	return final_pos


func _is_helicopter_aircraft(aircraft: RigidBody3D) -> bool:
	if not is_instance_valid(aircraft):
		return false
	if aircraft.get_meta("is_helicopter", false):
		return true
	if str(aircraft.get_meta("aircraft_role", "")).to_lower().find("helicopter") != -1:
		return true
	if aircraft.scene_file_path.to_lower().find("aircraft_9") != -1:
		return true
	return aircraft.name.to_lower().find("aircraft_9") != -1

func _move_aircraft_horizontally(aircraft: RigidBody3D, target_position: Vector3):
	"""Move aircraft horizontally to target position with tractorbots following"""
	# Work in carrier-local space so movement tracks with the moving carrier.
	# Lerping world-space snapshots causes the aircraft to lag behind as the
	# carrier moves forward during the tween.
	var carrier := get_parent() as Node3D
	if carrier:
		carrier.force_update_transform()
	var start_local: Vector3 = carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
	var target_local: Vector3 = carrier.to_local(target_position) if carrier else target_position
	var aircraft_carrier_local_basis: Basis = carrier.global_transform.basis.inverse() * aircraft.global_transform.basis if carrier else aircraft.global_transform.basis

	# Get initial tractorbot offsets from aircraft
	var bot_offsets: Array[Vector3] = []
	for bot in tractor_bots:
		if bot and bot.is_active:
			bot_offsets.append(bot.global_position - aircraft.global_position)
		else:
			bot_offsets.append(Vector3.ZERO)
	_set_manual_transport(aircraft, true)
	for bot in tractor_bots:
		if bot and bot.is_active:
			_set_manual_transport(bot, true)

	var distance = start_local.distance_to(target_local)
	var duration = distance / _aircraft_move_speed
	if _heli_test_active:
		_log_heli_test("move horizontal begin aircraft=%s dist=%.1f duration=%.1f start=%s target=%s active_bots=%d" % [
			_aircraft_debug_name(aircraft),
			distance,
			duration,
			_fmt_vec3(aircraft.global_position),
			_fmt_vec3(target_position),
			tractor_bots.filter(func(bot): return bot and bool(bot.get("is_active"))).size(),
		])


	var elapsed_time = 0.0

	while elapsed_time < duration and is_instance_valid(aircraft):
		elapsed_time += get_physics_process_delta_time()
		var t = ease_in_out_cubic(clamp(elapsed_time / duration, 0.0, 1.0))

		# Lerp in carrier-local space, convert back to world — tracks carrier movement
		var current_local = start_local.lerp(target_local, t)
		if carrier:
			var aircraft_transform := aircraft.global_transform
			aircraft_transform.origin = carrier.to_global(current_local)
			aircraft_transform.basis = (carrier.global_transform.basis * aircraft_carrier_local_basis).orthonormalized()
			aircraft.global_transform = aircraft_transform
			_sync_rigidbody_transform_state(aircraft)
		else:
			aircraft.global_position = current_local
			_sync_rigidbody_transform_state(aircraft)
		aircraft.angular_velocity = Vector3.ZERO

		# Move tractorbots to maintain relative positions
		for i in range(min(tractor_bots.size(), bot_offsets.size())):
			var bot = tractor_bots[i]
			if bot and bot.is_active:
				bot.global_position = aircraft.global_position + bot_offsets[i]

		await get_tree().physics_frame

	# Final position — snap to carrier-relative target
	if not is_instance_valid(aircraft):
		for bot in tractor_bots:
			if bot:
				_set_manual_transport(bot, false)
		return

	aircraft.global_position = carrier.to_global(target_local) if carrier else target_position
	if carrier:
		var final_transform := aircraft.global_transform
		final_transform.basis = (carrier.global_transform.basis * aircraft_carrier_local_basis).orthonormalized()
		aircraft.global_transform = final_transform
	_sync_rigidbody_transform_state(aircraft)
	aircraft.angular_velocity = Vector3.ZERO
	if _heli_test_active:
		_log_heli_test("move horizontal complete aircraft=%s pos=%s" % [
			_aircraft_debug_name(aircraft),
			_fmt_vec3(aircraft.global_position),
		])

	# Final tractorbot positions
	for i in range(min(tractor_bots.size(), bot_offsets.size())):
		var bot = tractor_bots[i]
		if bot and bot.is_active:
			bot.global_position = aircraft.global_position + bot_offsets[i]
	for bot in tractor_bots:
		if bot:
			_set_manual_transport(bot, false)
	_set_manual_transport(aircraft, false)


func _move_tractorbots_to_staging():
	"""Move tractorbots to staging at a consistent speed, then deactivate them"""
	var primary_bots := _get_primary_tractor_bots()
	if primary_bots.is_empty():
		return
	for bot in primary_bots:
		_set_cleanup_idle_for_tractor_bot(bot)
	var staging_slots := _get_primary_staging_slots_local(primary_bots.size())
	await _move_nodes_to_local_targets(primary_bots, staging_slots, _tractor_staging_speed)
	for bot in primary_bots:
		_set_cleanup_idle_for_tractor_bot(bot)
	_tractorbots_in_hangar = false

func _get_primary_elevator_slots_local(count: int, platform_local_y: float) -> Array[Vector3]:
	var slots := _get_tractor_cleanup_elevator_slots_local(count)
	for i in range(slots.size()):
		var slot_local: Vector3 = slots[i]
		slot_local.y = platform_local_y
		slots[i] = slot_local
	return slots

func _wait_for_tractor_elevator_transfer() -> void:
	while _tractor_elevator_transfer_in_progress:
		await get_tree().physics_frame

func _wait_for_elevator_bottom() -> void:
	while is_instance_valid(elevator) and elevator.current_state != elevator.ElevatorState.AT_BOTTOM:
		await get_tree().physics_frame

func _follow_cleanup_tractors_with_elevator_up(nodes: Array[Node3D], local_slots: Array[Vector3]) -> void:
	if nodes.is_empty() or not elevator or not ("platform" in elevator):
		return
	while is_instance_valid(elevator) and not _is_elevator_physically_at_top():
		var bot_local_y := _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
		for i in range(min(nodes.size(), local_slots.size())):
			if not is_instance_valid(nodes[i]):
				continue
			var target_local := local_slots[i]
			target_local.y = bot_local_y
			nodes[i].position = target_local
		await get_tree().physics_frame
	var final_local_y := _get_elevator_platform_top_local_y(-0.5) + tractor_elevator_floor_offset_m
	for i in range(min(nodes.size(), local_slots.size())):
		if not is_instance_valid(nodes[i]):
			continue
		var final_local := local_slots[i]
		final_local.y = final_local_y
		nodes[i].position = final_local

func _prepare_tractorbots_for_recovery_job() -> void:
	_recovery_debug("preparing tractorbots for recovery job")
	await _wait_for_tractor_elevator_transfer()
	var primary_bots := _get_primary_tractor_bots()
	if primary_bots.is_empty() or not is_instance_valid(elevator_pickup_marker):
		_recovery_debug("tractor prep skipped: primary_bots=%d pickup_marker_valid=%s elevator_valid=%s" % [
			primary_bots.size(),
			str(is_instance_valid(elevator_pickup_marker)),
			str(elevator != null)
		])
		return

	for bot in primary_bots:
		_set_cleanup_idle_for_tractor_bot(bot)

	var bots_need_elevator_fetch := false
	if elevator:
		var elevator_at_bottom: bool = "current_state" in elevator and elevator.current_state == elevator.ElevatorState.AT_BOTTOM
		bots_need_elevator_fetch = _tractorbots_in_hangar or (elevator_at_bottom and not _is_elevator_physically_at_top())

	var fetched_bots_from_hangar := false
	if bots_need_elevator_fetch:
		_tractor_elevator_transfer_in_progress = true
		_recovery_debug("fetching tractorbots from hangar elevator")
		if not ("current_state" in elevator and elevator.current_state == elevator.ElevatorState.AT_BOTTOM):
			if elevator.has_method("move_platform_down"):
				elevator.move_platform_down()
			await _wait_for_elevator_bottom()
		if not is_instance_valid(elevator):
			_tractor_elevator_transfer_in_progress = false
			return

		var bottom_slot_y := _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
		var elevator_slots := _get_primary_elevator_slots_local(primary_bots.size(), bottom_slot_y)
		await _move_nodes_to_local_targets(primary_bots, elevator_slots, _tractor_staging_speed)
		if not is_instance_valid(elevator):
			_tractor_elevator_transfer_in_progress = false
			return

		if elevator.has_method("move_platform_up"):
			elevator.move_platform_up()
		await _follow_cleanup_tractors_with_elevator_up(primary_bots, elevator_slots)
		await _wait_for_elevator_top()
		_tractor_elevator_transfer_in_progress = false
		_tractorbots_in_hangar = false
		fetched_bots_from_hangar = true

	if not fetched_bots_from_hangar:
		var staging_slots := _get_primary_staging_slots_local(primary_bots.size())
		_recovery_debug("moving tractorbots to deck staging")
		await _move_nodes_to_local_targets(primary_bots, staging_slots, _tractor_staging_speed)
	else:
		_recovery_debug("tractorbots delivered by elevator; starting recovery from elevator slots")

	for bot in primary_bots:
		if bot.has_method("enable_movement"):
			bot.enable_movement()

	_tractorbots_in_hangar = false
	_recovery_debug("tractorbots ready on deck")

func _send_primary_tractorbots_to_hangar() -> void:
	if _tractor_elevator_transfer_in_progress:
		return
	if not is_instance_valid(elevator_pickup_marker) or not elevator:
		return

	var primary_bots := _get_primary_tractor_bots()
	if primary_bots.size() < PRIMARY_TRACTOR_COUNT:
		return

	_tractor_elevator_transfer_in_progress = true
	for bot in primary_bots:
		_set_cleanup_idle_for_tractor_bot(bot)

	if not _is_elevator_physically_at_top():
		if elevator.has_method("move_platform_up"):
			elevator.move_platform_up()
		await _wait_for_elevator_top()
	if not is_instance_valid(elevator):
		_tractor_elevator_transfer_in_progress = false
		return

	var top_slot_y := _get_elevator_platform_top_local_y(-0.5) + tractor_elevator_floor_offset_m
	var elevator_slots := _get_primary_elevator_slots_local(primary_bots.size(), top_slot_y)
	await _move_nodes_to_local_targets(primary_bots, elevator_slots, _tractor_staging_speed)
	if not is_instance_valid(elevator):
		_tractor_elevator_transfer_in_progress = false
		return

	if elevator.has_method("move_platform_down"):
		elevator.move_platform_down()
	await _follow_cleanup_tractors_with_elevator_down(primary_bots, elevator_slots)
	await _wait_for_elevator_bottom()

	for bot in primary_bots:
		_set_cleanup_idle_for_tractor_bot(bot)

	_tractorbots_in_hangar = true
	_tractor_elevator_transfer_in_progress = false

func _set_cleanup_idle_for_tractor_bot(bot: Node3D) -> void:
	if not is_instance_valid(bot):
		return
	if bot.has_method("deactivate"):
		bot.deactivate()
	if bot.has_method("enable_movement"):
		bot.enable_movement()
	if bot.has_method("disable_movement"):
		bot.disable_movement()

func _move_nodes_to_local_targets(nodes: Array[Node3D], local_targets: Array[Vector3], speed: float) -> void:
	if nodes.is_empty() or local_targets.is_empty():
		return
	var max_distance: float = 0.0
	var start_positions: Array[Vector3] = []
	for i in range(nodes.size()):
		var node := nodes[i]
		if not is_instance_valid(node):
			start_positions.append(Vector3.ZERO)
			continue
		start_positions.append(node.position)
		if i < local_targets.size():
			max_distance = maxf(max_distance, node.position.distance_to(local_targets[i]))
	var duration: float = maxf(max_distance / maxf(speed, 0.1), 0.01)
	var elapsed: float = 0.0
	while elapsed < duration:
		elapsed += get_physics_process_delta_time()
		var t := ease_in_out_cubic(clampf(elapsed / duration, 0.0, 1.0))
		for i in range(min(nodes.size(), local_targets.size())):
			if not is_instance_valid(nodes[i]):
				continue
			nodes[i].position = start_positions[i].lerp(local_targets[i], t)
		await get_tree().physics_frame
	for i in range(min(nodes.size(), local_targets.size())):
		if not is_instance_valid(nodes[i]):
			continue
		nodes[i].position = local_targets[i]

func _follow_cleanup_tractors_with_elevator_down(nodes: Array[Node3D], local_slots: Array[Vector3]) -> void:
	if nodes.is_empty() or not elevator or not ("platform" in elevator):
		return
	while is_instance_valid(elevator) and elevator.current_state != elevator.ElevatorState.AT_BOTTOM:
		var bot_local_y := _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
		for i in range(min(nodes.size(), local_slots.size())):
			if not is_instance_valid(nodes[i]):
				continue
			var target_local := local_slots[i]
			target_local.y = bot_local_y
			nodes[i].position = target_local
		await get_tree().physics_frame
	var final_local_y := _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
	for i in range(min(nodes.size(), local_slots.size())):
		if not is_instance_valid(nodes[i]):
			continue
		var final_local := local_slots[i]
		final_local.y = final_local_y
		nodes[i].position = final_local

func _wait_for_elevator_top() -> void:
	while is_instance_valid(elevator) and not _is_elevator_physically_at_top():
		await get_tree().physics_frame

func _run_extra_tractor_cleanup() -> void:
	if _tractor_cleanup_batch.is_empty():
		_tractor_cleanup_batch.clear()
		_tractor_cleanup_in_progress = false
		if current_state == DeckState.TRACTOR_CLEANUP:
			current_state = DeckState.IDLE
		return

	var cleanup_batch: Array[Node3D] = _tractor_cleanup_batch.duplicate()
	for bot in cleanup_batch:
		if is_instance_valid(bot):
			bot.queue_free()

	_tractor_cleanup_batch.clear()
	_tractor_cleanup_in_progress = false
	current_state = DeckState.IDLE

func _maybe_dispatch_extra_tractor_cleanup() -> void:
	if _tractor_cleanup_in_progress or current_state != DeckState.IDLE:
		return
	var extras := _get_extra_deck_tractor_bots()
	if extras.is_empty():
		return
	var batch_size := mini(extras.size(), max(desired_deck_tractor_count, 1))
	_tractor_cleanup_batch.clear()
	for i in range(batch_size):
		_tractor_cleanup_batch.append(extras[i])
	_tractor_cleanup_in_progress = true
	current_state = DeckState.TRACTOR_CLEANUP
	_run_extra_tractor_cleanup.call_deferred()

func ease_in_out_cubic(t: float) -> float:
	"""Smooth easing function"""
	return 3.0 * t * t - 2.0 * t * t * t

# ============================================================================
# LANDING TEST MODE
# ============================================================================

func _get_all_landing_test_cleanup_aircraft() -> Array[RigidBody3D]:
	var all_aircraft: Array[RigidBody3D] = []
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is RigidBody3D):
				continue
			var aircraft := node as RigidBody3D
			if not is_instance_valid(aircraft):
				continue
			var id := aircraft.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			all_aircraft.append(aircraft)
	return all_aircraft

func _enter_landing_test_isolation() -> void:
	_ai_launch_queue = 0
	_pending_flight_ops = null
	_pending_ai_loadout_profile = ""
	_retrieval_ai_land_after_launch = true
	_landing_test_timer = 0.0
	_landing_test_spawn_index = 0
	for aircraft in _get_all_landing_test_cleanup_aircraft():
		if _landing_test_aircraft.has(aircraft):
			continue
		print("[LandingTest] despawning non-test aircraft %s" % _aircraft_debug_name(aircraft))
		aircraft.queue_free()
	if is_instance_valid(deck_aircraft) and not _landing_test_aircraft.has(deck_aircraft):
		deck_aircraft = null
	if is_instance_valid(_pending_store_aircraft) and not _landing_test_aircraft.has(_pending_store_aircraft):
		_pending_store_aircraft = null
	_recovery_powerdown_in_progress = false
	_recovery_release_done = false
	_recovery_job_dispatched = false
	_pending_store_aircraft = null
	deck_aircraft = null
	_landing_clearance_aircraft = null
	_landing_clearance_queue.clear()
	current_state = DeckState.IDLE
	if catapult and catapult.has_method("_reset_state"):
		catapult._reset_state()

func _strip_test_aircraft_weapons(node: Node) -> void:
	if "mounted_weapon" in node:
		node.set("mounted_weapon", null)
	for child in node.get_children():
		_strip_test_aircraft_weapons(child)

func _spawn_recovery_debug_aircraft() -> void:
	if _landing_test_active:
		_landing_test_active = false
		for ac in _landing_test_aircraft:
			if is_instance_valid(ac):
				ac.queue_free()
		_landing_test_aircraft.clear()
		print("[RecoveryDebug] landing test mode OFF for single recovery spawn")

	var scene: PackedScene = aircraft_template_scene
	if not scene:
		scene = load(DEFAULT_AIRCRAFT_SCENE_PATH)
	if not scene:
		push_warning("[RecoveryDebug] Aircraft_5 scene not found")
		return

	var root: Node = get_tree().current_scene
	var carrier_node := get_tree().get_first_node_in_group("carrier") as Node3D
	if not is_instance_valid(root) or not is_instance_valid(carrier_node):
		push_warning("[RecoveryDebug] Missing scene root or carrier")
		return

	var carrier_forward := carrier_node.global_transform.basis.z
	carrier_forward.y = 0.0
	if carrier_forward.length_squared() <= 0.001:
		carrier_forward = Vector3.FORWARD
	carrier_forward = carrier_forward.normalized()

	var spawn_pos: Vector3 = carrier_node.global_position - carrier_forward * RECOVERY_DEBUG_SPAWN_DIST_M
	spawn_pos.y = carrier_node.global_position.y + RECOVERY_DEBUG_ALTITUDE_M

	var aircraft := scene.instantiate() as RigidBody3D
	if not is_instance_valid(aircraft):
		push_warning("[RecoveryDebug] Scene instantiate failed")
		return

	_recovery_debug_spawn_index += 1
	aircraft.name = "RecoveryDebug_%03d" % _recovery_debug_spawn_index
	_strip_test_aircraft_weapons(aircraft)
	root.add_child(aircraft)

	aircraft.global_position = spawn_pos
	var look_target := carrier_node.global_position
	look_target.y = spawn_pos.y
	aircraft.look_at(look_target, Vector3.UP)
	aircraft.rotate_y(PI)
	aircraft.linear_velocity = carrier_forward * LANDING_TEST_SPEED_MPS
	aircraft.angular_velocity = Vector3.ZERO

	var pilot := aircraft.find_child("AIPilot", true, false)
	if is_instance_valid(pilot) and pilot.has_method("start_straight_in_landing"):
		pilot.start_straight_in_landing()
	else:
		push_warning("[RecoveryDebug] AIPilot not found on spawned aircraft")

	var cg := aircraft.find_child("ControlLandingGear", true, false)
	if is_instance_valid(cg):
		get_tree().create_timer(0.1).timeout.connect(func():
			if not is_instance_valid(cg): return
			cg.send_to_landing_gears("stow")
			cg.send_to_tailhooks("stow")
			cg.send_to_tailhook_simple(false)
			cg.gear_down_state = false
			cg.tailhook_down_state = false
		)
		get_tree().create_timer(0.4).timeout.connect(func():
			if not is_instance_valid(cg): return
			cg.send_to_landing_gears("deploy")
			cg.send_to_tailhooks("deploy")
			cg.send_to_tailhook_simple(true)
			cg.gear_down_state = true
			cg.tailhook_down_state = true
		)
	print("[RecoveryDebug] spawned %s 1000m behind carrier at +100m, landing mode" % aircraft.name)

func _is_aircraft_eligible_for_return_command(aircraft: RigidBody3D) -> bool:
	if not is_instance_valid(aircraft):
		return false
	if aircraft == deck_aircraft or aircraft == _pending_store_aircraft:
		return false
	if aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode")):
		return false
	if aircraft.has_meta("parking_brake") and bool(aircraft.get_meta("parking_brake")):
		return false
	if aircraft.has_meta("controls_disabled") and bool(aircraft.get_meta("controls_disabled")):
		return false
	if aircraft.has_meta("arresting_engaged") and bool(aircraft.get_meta("arresting_engaged")):
		return false
	if _is_aircraft_blocking_landing_deck(aircraft):
		return false
	var pilot := aircraft.find_child("AIPilot", true, false)
	return is_instance_valid(pilot) and pilot.has_method("return_to_base")

func _command_closest_aircraft_to_return_to_base() -> void:
	var carrier := get_parent() as Node3D
	var origin: Vector3 = carrier.global_position if is_instance_valid(carrier) else Vector3.ZERO
	var best_aircraft: RigidBody3D = null
	var best_dist_sq: float = INF
	for aircraft in _get_all_aircraft_nodes():
		if not _is_aircraft_eligible_for_return_command(aircraft):
			continue
		var dist_sq: float = aircraft.global_position.distance_squared_to(origin)
		if dist_sq < best_dist_sq:
			best_aircraft = aircraft
			best_dist_sq = dist_sq
	if not is_instance_valid(best_aircraft):
		print("[FlightDeck] F3 return-to-base: no eligible AI aircraft found")
		return
	var pilot := best_aircraft.find_child("AIPilot", true, false)
	print("[FlightDeck] F3 return-to-base: commanding %s via recovery framework" % _aircraft_debug_name(best_aircraft))
	pilot.return_to_base()

func _spawn_landing_test_aircraft() -> void:
	var scene: PackedScene = aircraft_template_scene
	if not scene:
		scene = load(DEFAULT_AIRCRAFT_SCENE_PATH)
	if not scene:
		push_warning("[LandingTest] Aircraft_5 scene not found")
		return

	# Compute approach axis from waypoints; fall back to carrier orientation.
	var root: Node = get_tree().current_scene
	var carrier_node := get_tree().get_first_node_in_group("carrier") as Node3D
	if not is_instance_valid(carrier_node):
		push_warning("[LandingTest] No node in group 'carrier'")
		return

	var approach_dir := Vector3.ZERO
	var wp0 := root.find_child("approach_0", true, false) as Node3D
	var wp4 := root.find_child("approach_4", true, false) as Node3D
	if is_instance_valid(wp0) and is_instance_valid(wp4):
		var flat := wp4.global_position - wp0.global_position
		flat.y = 0.0
		if flat.length_squared() > 1.0:
			approach_dir = flat.normalized()
	if approach_dir == Vector3.ZERO:
		# Carrier's local -Z is its forward; approach comes from behind (+Z).
		approach_dir = carrier_node.global_transform.basis.z.normalized()
		approach_dir.y = 0.0
		approach_dir = approach_dir.normalized()

	# Randomise spawn: distance 1700-2300 m, lateral offset ±150 m, altitude ±60 m, speed ±15 m/s.
	var rand_dist: float  = LANDING_TEST_SPAWN_DIST_M + randf_range(-300.0, 300.0)
	var rand_alt: float   = LANDING_TEST_ALTITUDE_M   + randf_range(-60.0,  60.0)
	var rand_speed: float = LANDING_TEST_SPEED_MPS    + randf_range(-15.0,  15.0)
	var lateral_dir := approach_dir.rotated(Vector3.UP, PI * 0.5)
	var rand_lateral: float = randf_range(-150.0, 150.0)
	# Randomise heading ±20° off the approach axis
	var rand_yaw: float = randf_range(-20.0, 20.0)
	var rand_heading_dir := approach_dir.rotated(Vector3.UP, deg_to_rad(rand_yaw))

	var spawn_pos: Vector3 = carrier_node.global_position \
		- approach_dir * rand_dist \
		+ lateral_dir  * rand_lateral
	spawn_pos.y = carrier_node.global_position.y + rand_alt

	# Instantiate and place.
	var aircraft := scene.instantiate() as RigidBody3D
	if not is_instance_valid(aircraft):
		push_warning("[LandingTest] Scene instantiate failed")
		return
	_landing_test_spawn_index += 1
	var aircraft_name := "LandingTest_%03d" % _landing_test_spawn_index
	aircraft.name = aircraft_name
	aircraft.set_meta("landing_test_aircraft", true)
	# Clear weapons before entering the tree so Hardpoint._ready() skips mounting.
	_strip_test_aircraft_weapons(aircraft)
	root.add_child(aircraft)

	aircraft.global_position = spawn_pos
	# Face roughly toward the carrier (heading may be offset by rand_yaw).
	var look_target := carrier_node.global_position
	look_target.y = spawn_pos.y
	aircraft.look_at(look_target, Vector3.UP)
	aircraft.rotate_y(PI)  # Aircraft_5's nose is +Z; look_at aims -Z, so flip 180°.
	aircraft.rotate_y(deg_to_rad(rand_yaw))
	aircraft.linear_velocity = rand_heading_dir * rand_speed
	aircraft.angular_velocity = Vector3.ZERO

	# Start straight-in final approach (skips the downwind/base circuit).
	var pilot := aircraft.find_child("AIPilot", true, false)
	if is_instance_valid(pilot) and pilot.has_method("start_straight_in_landing"):
		pilot.start_straight_in_landing()
	else:
		push_warning("[LandingTest] AIPilot not found on spawned aircraft")

	# Cycle gear stow→deploy so the tailhook ends up deployed regardless of setup() order.
	var cg := aircraft.find_child("ControlLandingGear", true, false)
	if is_instance_valid(cg):
		get_tree().create_timer(0.1).timeout.connect(func():
			if not is_instance_valid(cg): return
			cg.send_to_landing_gears("stow")
			cg.send_to_tailhooks("stow")
			cg.send_to_tailhook_simple(false)
			cg.gear_down_state = false
			cg.tailhook_down_state = false
		)
		get_tree().create_timer(0.4).timeout.connect(func():
			if not is_instance_valid(cg): return
			cg.send_to_landing_gears("deploy")
			cg.send_to_tailhooks("deploy")
			cg.send_to_tailhook_simple(true)
			cg.gear_down_state = true
			cg.tailhook_down_state = true
		)

	_landing_test_aircraft.append(aircraft)
	print("[LandingTest] spawned %s at pos=(%.0f, %.0f, %.0f) approach_dir=(%.2f,%.0f,%.2f)" % [
		aircraft.name,
		spawn_pos.x, spawn_pos.y, spawn_pos.z,
		approach_dir.x, approach_dir.y, approach_dir.z])


func _enable_heli_navigation_test_mode() -> void:
	if _heli_navigation_test_active:
		return
	_heli_navigation_test_active = true
	_active_test_scenario = TestScenario.HELI_NAVIGATION
	if _landing_test_active:
		_landing_test_active = false
		for ac in _landing_test_aircraft:
			if is_instance_valid(ac):
				ac.queue_free()
		_landing_test_aircraft.clear()
	FrameProfiler.set_enabled(true, "helicopter navigation scenario")
	_set_heli_test_friendly_ops_suspended(true)
	_disable_enemies_for_heli_test()
	var scene_root := get_tree().current_scene
	if scene_root != null and scene_root.has_method("disable_structures_for_navigation_test"):
		scene_root.call("disable_structures_for_navigation_test")
	var poi_mgr := get_node_or_null("/root/POIManager")
	if poi_mgr and "reveals_disabled" in poi_mgr:
		poi_mgr.set("reveals_disabled", true)
	var dnc := scene_root.find_child("DayNightCycle", true, false) if scene_root != null else null
	if dnc and "freeze_daytime" in dnc:
		dnc.set("freeze_daytime", true)
	auto_recovery_enabled = true

	# A clean scene is normally supplied by the selector reload. Keep this cleanup
	# defensive so direct/editor activation still produces an isolated test.
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "friendlies", "enemies"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is RigidBody3D) or seen.has(node.get_instance_id()):
				continue
			seen[node.get_instance_id()] = true
			if node == deck_aircraft:
				deck_aircraft = null
			(node as RigidBody3D).queue_free()
	stored_aircraft.clear()
	_pending_store_aircraft = null
	_landing_clearance_aircraft = null
	_landing_clearance_queue.clear()
	current_state = DeckState.IDLE
	_clear_navigation_test_world_clutter()

	_reset_heli_test_stats()
	_ensure_physical_test_ui()
	_heli_navigation_lzs.clear()
	_heli_navigation_spawn_serial = 0
	_heli_navigation_test_timer_s = 0.0
	# Fresh navigation report for this run.
	_navigation_report_started = false
	_navigation_tracked.clear()
	_navigation_route_stats.clear()
	_navigation_report_summary_timer_s = HELI_NAVIGATION_REPORT_SUMMARY_S
	_navigation_launch_watchdog_log_s = 0.0
	_navigation_no_active_since_s = -1.0
	_navigation_orphan_cleanup_log_s = 0.0
	_navigation_idle_refill_log_s = 0.0
	_log_heli_test("scenario ON: stationary center carrier, 8 fixed terrain routes")
	call_deferred("_ensure_heli_navigation_test_aircraft")


func _ensure_heli_navigation_test_aircraft() -> void:
	if not _heli_navigation_test_active:
		return
	# Defensive cleanup for any structure proxy that finished spawning after the
	# scenario was activated.
	_clear_navigation_test_world_clutter()
	if _heli_navigation_lzs.size() != HELI_NAVIGATION_ROUTE_COUNT:
		var _nav_range_profiler_start: int = FrameProfiler.begin("FlightDeckManager.nav_setup_range")
		var nav_range_ready := _setup_heli_navigation_test_range()
		FrameProfiler.end("FlightDeckManager.nav_setup_range", _nav_range_profiler_start)
		if not nav_range_ready:
			return
	if not _navigation_report_started:
		_start_navigation_report()
	var _nav_refill_profiler_start: int = FrameProfiler.begin("FlightDeckManager.nav_force_refill")
	_navigation_force_refill_if_tuner_idle()
	FrameProfiler.end("FlightDeckManager.nav_force_refill", _nav_refill_profiler_start)

	var occupied_slots: Dictionary = {}
	var active_nav_count := 0
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is RigidBody3D) or seen.has(node.get_instance_id()):
				continue
			seen[node.get_instance_id()] = true
			if not bool(node.get_meta(HELI_NAVIGATION_TEST_META, false)) \
					or node.is_queued_for_deletion():
				continue
			if _navigation_cleanup_orphaned_test_aircraft(node as RigidBody3D):
				continue
			active_nav_count += 1
			var slot := int(node.get_meta(HELI_NAVIGATION_ROUTE_SLOT_META, -1))
			if slot >= 0 and slot < HELI_NAVIGATION_ROUTE_COUNT:
				occupied_slots[slot] = true
	var launch_refs: Array[RigidBody3D] = [deck_aircraft, _pending_store_aircraft, _landing_clearance_aircraft]
	for ref: RigidBody3D in launch_refs:
		if not is_instance_valid(ref) or seen.has(ref.get_instance_id()):
			continue
		seen[ref.get_instance_id()] = true
		if not bool(ref.get_meta(HELI_NAVIGATION_TEST_META, false)) \
				or ref.is_queued_for_deletion():
			continue
		active_nav_count += 1
		var ref_slot := int(ref.get_meta(HELI_NAVIGATION_ROUTE_SLOT_META, -1))
		if ref_slot >= 0 and ref_slot < HELI_NAVIGATION_ROUTE_COUNT:
			occupied_slots[ref_slot] = true
	var stored_nav_count := 0
	for stored_data_variant in stored_aircraft:
		if not (stored_data_variant is Dictionary):
			continue
		var stored_data := stored_data_variant as Dictionary
		var metadata_variant: Variant = stored_data.get("metadata", {})
		if not (metadata_variant is Dictionary):
			continue
		var metadata := metadata_variant as Dictionary
		if not bool(metadata.get(HELI_NAVIGATION_TEST_META, false)):
			continue
		stored_nav_count += 1
		var stored_slot := int(metadata.get(HELI_NAVIGATION_ROUTE_SLOT_META, -1))
		if stored_slot >= 0 and stored_slot < HELI_NAVIGATION_ROUTE_COUNT:
			occupied_slots[stored_slot] = true

	var tuner_status: Dictionary = _navigation_tuner_call("get_status", [], {}) as Dictionary
	var tuner_required := int(tuner_status.get("required_results", 0))
	var tuner_scored := int(tuner_status.get("scored_results", 0))
	var tuner_pending := int(tuner_status.get("pending_scored_trials", 0))
	var tuner_active := int(tuner_status.get("active_trials", 0))
	var tuner_population := int(tuner_status.get("population", HELI_NAVIGATION_ROUTE_COUNT))
	var tuner_route_count := int(tuner_status.get("route_count", HELI_NAVIGATION_ROUTE_COUNT))
	var tuner_max_concurrent := mini(
		maxi(tuner_population, 1),
		maxi(tuner_route_count, 1)
	)
	var tuner_inflight := maxi(tuner_pending, tuner_active)
	var tuner_unstarted_required := maxi(tuner_required - tuner_scored - tuner_pending, 0) \
			if tuner_required > 0 else HELI_NAVIGATION_ROUTE_COUNT
	var queue_capacity := maxi(
		mini(tuner_unstarted_required, tuner_max_concurrent - tuner_inflight - stored_nav_count),
		0
	)
	var queued := 0
	for slot in range(HELI_NAVIGATION_ROUTE_COUNT):
		if queued >= queue_capacity:
			break
		if occupied_slots.has(slot):
			continue
		if _queue_heli_navigation_test_aircraft(slot):
			occupied_slots[slot] = true
			queued += 1
	_log_heli_test("navigation routes accounted=%d/%d newly_queued=%d" % [
		occupied_slots.size(),
		HELI_NAVIGATION_ROUTE_COUNT,
		queued,
	])
	var now_s := Time.get_ticks_msec() / 1000.0
	if active_nav_count > 0 or stored_nav_count <= 0:
		_navigation_no_active_since_s = -1.0
	elif _navigation_no_active_since_s < 0.0:
		_navigation_no_active_since_s = now_s
	_navigation_test_clear_stale_launch_blockers(active_nav_count, stored_nav_count)

	if not tuner_status.is_empty() \
			and (tuner_unstarted_required <= 0 or tuner_inflight >= tuner_max_concurrent):
		_navigation_test_log_launch_blocked(
			"tuner_capacity_full",
			active_nav_count,
			stored_nav_count
		)
		return

	# Normal helicopter retrieval is intentionally serial. Wait until the prior
	# launch has physically cleared the deck, and let recovery traffic go first.
	if current_state != DeckState.IDLE or _tractor_cleanup_in_progress \
			or _tractor_elevator_transfer_in_progress:
		_navigation_test_log_launch_blocked(
			"deck_busy",
			active_nav_count,
			stored_nav_count
		)
		return
	if is_instance_valid(_pending_store_aircraft) or is_instance_valid(_landing_clearance_aircraft) \
			or not _landing_clearance_queue.is_empty():
		_navigation_test_log_launch_blocked(
			"landing_or_storage_busy",
			active_nav_count,
			stored_nav_count
		)
		return
	if is_instance_valid(deck_aircraft):
		if bool(deck_aircraft.get_meta(HELI_NAVIGATION_TEST_META, false)) \
				and not bool(deck_aircraft.get_meta("helicopter_deck_takeoff_ready", false)):
			_navigation_test_log_launch_blocked(
				"cleared_unready_nav_deck_aircraft",
				active_nav_count,
				stored_nav_count
			)
			deck_aircraft = null
		else:
			_navigation_test_log_launch_blocked(
				"deck_aircraft_present",
				active_nav_count,
				stored_nav_count
			)
			return

	var next_nav_index := -1
	for i in range(stored_aircraft.size()):
		var stored_data: Dictionary = stored_aircraft[i]
		var metadata_variant: Variant = stored_data.get("metadata", {})
		if metadata_variant is Dictionary \
				and bool((metadata_variant as Dictionary).get(HELI_NAVIGATION_TEST_META, false)):
			next_nav_index = i
			break
	if next_nav_index < 0:
		_navigation_test_log_launch_blocked(
			"no_stored_nav_aircraft",
			active_nav_count,
			stored_nav_count
		)
		return
	if next_nav_index > 0:
		var next_nav_data: Dictionary = stored_aircraft[next_nav_index]
		stored_aircraft.remove_at(next_nav_index)
		stored_aircraft.push_front(next_nav_data)
	var next_metadata: Dictionary = stored_aircraft[0].get("metadata", {})
	_log_heli_test("carrier launch queued route=%d stored=%d" % [
		int(next_metadata.get(HELI_NAVIGATION_ROUTE_SLOT_META, -1)) + 1,
		stored_aircraft.size(),
	])
	start_hangar_retrieval()


func _navigation_cleanup_orphaned_test_aircraft(ac: RigidBody3D) -> bool:
	if not is_instance_valid(ac) or ac.is_queued_for_deletion():
		return false
	if _navigation_tracked.has(ac.get_instance_id()):
		return false
	if ac == deck_aircraft or ac == _pending_store_aircraft or ac == _landing_clearance_aircraft:
		return false
	var carrier_owned := bool(ac.get_meta("controls_disabled", false)) \
			or bool(ac.get_meta("carrier_transport_mode", false)) \
			or bool(ac.get_meta("helicopter_deck_takeoff_ready", false))
	var phase := -1
	var pilot := ac.find_child("HelicopterPilot", true, false)
	if pilot != null:
		phase = int(pilot.get("mission_phase"))
	if not carrier_owned and phase < 3:
		return false
	var now_s := Time.get_ticks_msec() / 1000.0
	if now_s >= _navigation_orphan_cleanup_log_s:
		_navigation_orphan_cleanup_log_s = now_s + HELI_NAVIGATION_ORPHAN_CLEANUP_LOG_S
		var detail := "ORPHAN_NAV_CLEANUP craft=%s phase=%d carrier_owned=%s slot=%d" % [
			ac.name,
			phase,
			str(carrier_owned),
			int(ac.get_meta(HELI_NAVIGATION_ROUTE_SLOT_META, -1)) + 1,
		]
		_log_heli_test(detail)
		if _navigation_report_started:
			_write_navigation_line(detail)
	ac.queue_free()
	return true


func _navigation_force_refill_if_tuner_idle() -> void:
	if not _heli_navigation_test_active:
		return
	if _heli_navigation_lzs.size() != HELI_NAVIGATION_ROUTE_COUNT:
		return
	var status_variant: Variant = _navigation_tuner_call("get_status", [], {})
	if not (status_variant is Dictionary):
		return
	var status := status_variant as Dictionary
	if int(status.get("remaining_results", 0)) <= 0:
		return
	if int(status.get("active_trials", 0)) > 0 or int(status.get("pending_scored_trials", 0)) > 0:
		return
	var active_nav_count := 0
	var stored_nav_count := 0
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is RigidBody3D) or seen.has(node.get_instance_id()):
				continue
			seen[node.get_instance_id()] = true
			var ac := node as RigidBody3D
			if not bool(ac.get_meta(HELI_NAVIGATION_TEST_META, false)) or ac.is_queued_for_deletion():
				continue
			active_nav_count += 1
	for stored_data_variant in stored_aircraft:
		if not (stored_data_variant is Dictionary):
			continue
		var metadata_variant: Variant = (stored_data_variant as Dictionary).get("metadata", {})
		if metadata_variant is Dictionary \
				and bool((metadata_variant as Dictionary).get(HELI_NAVIGATION_TEST_META, false)):
			stored_nav_count += 1
	var now_s := Time.get_ticks_msec() / 1000.0
	var launch_in_progress := stored_nav_count > 0 \
			or active_nav_count > 0 \
			or is_instance_valid(deck_aircraft) \
			or is_instance_valid(_pending_store_aircraft) \
			or is_instance_valid(_landing_clearance_aircraft) \
			or current_state != DeckState.IDLE \
			or _tractor_cleanup_in_progress \
			or _tractor_elevator_transfer_in_progress
	if launch_in_progress:
		if now_s >= _navigation_idle_refill_log_s:
			_navigation_idle_refill_log_s = now_s + HELI_NAVIGATION_IDLE_REFILL_LOG_S
			var wait_detail := "IDLE_TUNER_WAIT gen=%d results=%d/%d remaining=%d active_nav=%d stored=%d state=%s next_trial=%d" % [
				int(status.get("generation", 0)),
				int(status.get("scored_results", 0)),
				int(status.get("required_results", 0)),
				int(status.get("remaining_results", 0)),
				active_nav_count,
				stored_nav_count,
				_deck_state_name(),
				int(status.get("next_trial_id", 0)),
			]
			_log_heli_test(wait_detail)
			if _navigation_report_started:
				_write_navigation_line(wait_detail)
		return
	_navigation_tracked.clear()
	var queued := 0
	var _queue_profiler_start: int = FrameProfiler.begin("FlightDeckManager.nav_refill_queue")
	for slot in range(HELI_NAVIGATION_ROUTE_COUNT):
		if _queue_heli_navigation_test_aircraft(slot):
			queued += 1
	FrameProfiler.end("FlightDeckManager.nav_refill_queue", _queue_profiler_start)
	var stored_after := stored_aircraft.size()
	var retrieval_started := false
	if queued > 0 and current_state == DeckState.IDLE \
			and not _tractor_cleanup_in_progress \
			and not _tractor_elevator_transfer_in_progress \
			and not is_instance_valid(deck_aircraft) \
			and not is_instance_valid(_pending_store_aircraft) \
			and not is_instance_valid(_landing_clearance_aircraft):
		var _retrieval_profiler_start: int = FrameProfiler.begin("FlightDeckManager.nav_refill_start_retrieval")
		start_hangar_retrieval()
		FrameProfiler.end("FlightDeckManager.nav_refill_start_retrieval", _retrieval_profiler_start)
		retrieval_started = true
	if now_s >= _navigation_idle_refill_log_s:
		_navigation_idle_refill_log_s = now_s + HELI_NAVIGATION_IDLE_REFILL_LOG_S
		var detail := "IDLE_TUNER_REFILL gen=%d results=%d/%d remaining=%d active_nav=%d stored_before=%d queued=%d stored_after=%d retrieval_started=%s state=%s next_trial=%d" % [
			int(status.get("generation", 0)),
			int(status.get("scored_results", 0)),
			int(status.get("required_results", 0)),
			int(status.get("remaining_results", 0)),
			active_nav_count,
			stored_nav_count,
			queued,
			stored_after,
			str(retrieval_started),
			_deck_state_name(),
			int(status.get("next_trial_id", 0)),
		]
		_log_heli_test(detail)
		if _navigation_report_started:
			_write_navigation_line(detail)


func _navigation_test_no_active_grace_elapsed() -> bool:
	if _navigation_no_active_since_s < 0.0:
		return false
	var now_s := Time.get_ticks_msec() / 1000.0
	return now_s - _navigation_no_active_since_s >= HELI_NAVIGATION_LAUNCH_WATCHDOG_GRACE_S


func _navigation_test_clear_stale_launch_blockers(active_nav_count: int, stored_nav_count: int) -> void:
	if not _heli_navigation_test_active:
		return
	if active_nav_count > 0 or stored_nav_count <= 0:
		return
	if not _navigation_test_no_active_grace_elapsed():
		_navigation_test_log_launch_blocked("waiting_no_active_grace", active_nav_count, stored_nav_count)
		return
	var cleared: PackedStringArray = PackedStringArray()
	if is_instance_valid(_landing_clearance_aircraft) or not _landing_clearance_queue.is_empty():
		cleared.append("landing_clearance")
		_landing_clearance_aircraft = null
		_landing_clearance_elapsed_s = 0.0
		_landing_clearance_queue.clear()
		_landing_clearance_retry_after_s.clear()
	if not is_instance_valid(deck_aircraft):
		deck_aircraft = null
	if not is_instance_valid(_pending_store_aircraft):
		_pending_store_aircraft = null
	if _tractor_cleanup_in_progress and not is_instance_valid(deck_aircraft) \
			and not is_instance_valid(_pending_store_aircraft):
		cleared.append("tractor_cleanup")
		_tractor_cleanup_in_progress = false
		_tractor_cleanup_batch.clear()
	if _tractor_elevator_transfer_in_progress and not is_instance_valid(deck_aircraft) \
			and not is_instance_valid(_pending_store_aircraft):
		cleared.append("tractor_elevator_transfer")
		_tractor_elevator_transfer_in_progress = false
	if current_state != DeckState.IDLE and not is_instance_valid(deck_aircraft) \
			and not is_instance_valid(_pending_store_aircraft):
		cleared.append("deck_state=%s" % _deck_state_name())
		current_state = DeckState.IDLE
		_retrieval_top_handled = false
		_recovery_powerdown_in_progress = false
		_recovery_release_done = false
		_recovery_job_dispatched = false
	if not cleared.is_empty():
		var detail := "LAUNCH_WATCHDOG cleared=%s active=%d stored=%d state=%s deck=%s pending=%s clearance=%s queue=%d" % [
			",".join(cleared),
			active_nav_count,
			stored_nav_count,
			_deck_state_name(),
			_aircraft_debug_name(deck_aircraft),
			_aircraft_debug_name(_pending_store_aircraft),
			_aircraft_debug_name(_landing_clearance_aircraft),
			_landing_clearance_queue.size(),
		]
		_log_heli_test(detail)
		if _navigation_report_started:
			_write_navigation_line(detail)


func _navigation_test_log_launch_blocked(reason: String, active_nav_count: int, stored_nav_count: int) -> void:
	if not _heli_navigation_test_active:
		return
	if stored_nav_count <= 0:
		return
	var now_s := Time.get_ticks_msec() / 1000.0
	if now_s < _navigation_launch_watchdog_log_s:
		return
	_navigation_launch_watchdog_log_s = now_s + HELI_NAVIGATION_LAUNCH_WATCHDOG_LOG_S
	var no_active_s := 0.0
	if _navigation_no_active_since_s >= 0.0:
		no_active_s = now_s - _navigation_no_active_since_s
	var detail := "LAUNCH_BLOCKED reason=%s active=%d stored=%d no_active_s=%.1f state=%s tractor_cleanup=%s elevator_transfer=%s deck=%s pending=%s clearance=%s queue=%d" % [
		reason,
		active_nav_count,
		stored_nav_count,
		no_active_s,
		_deck_state_name(),
		str(_tractor_cleanup_in_progress),
		str(_tractor_elevator_transfer_in_progress),
		_aircraft_debug_name(deck_aircraft),
		_aircraft_debug_name(_pending_store_aircraft),
		_aircraft_debug_name(_landing_clearance_aircraft),
		_landing_clearance_queue.size(),
	]
	_log_heli_test(detail)
	if _navigation_report_started:
		_write_navigation_line(detail)


func _setup_heli_navigation_test_range() -> bool:
	var nav_grid := get_node_or_null("/root/TerrainNavGrid")
	if nav_grid == null or not nav_grid.has_method("is_ready") \
			or not bool(nav_grid.call("is_ready")):
		return false
	var carrier_node := get_parent() as Node3D
	if not is_instance_valid(carrier_node):
		return false

	var center_variant: Variant = nav_grid.call("get_bake_center")
	if not (center_variant is Vector3):
		return false
	var requested_center := center_variant as Vector3
	var _carrier_site_profiler_start: int = FrameProfiler.begin("FlightDeckManager.nav_find_carrier_site")
	var carrier_site := _find_flat_navigation_carrier_site(nav_grid, requested_center)
	FrameProfiler.end("FlightDeckManager.nav_find_carrier_site", _carrier_site_profiler_start)
	if is_inf(carrier_site.x):
		push_warning("[TestScenario] Could not find a carrier-sized flat site near map centre")
		return false
	_heli_navigation_center = carrier_site

	# Park the carrier on terrain at its normal body ride height. The carrier remains
	# visible and uses the ordinary elevator/deck launch and recovery machinery.
	if carrier_node.has_method("set_heli_test_stationary"):
		carrier_node.call("set_heli_test_stationary", true)
	if not _heli_test_has_carrier_original_transform:
		_heli_test_carrier_original_transform = carrier_node.global_transform
		_heli_test_has_carrier_original_transform = true
	carrier_node.global_position = _heli_navigation_center + Vector3.UP * 40.0
	carrier_node.rotation = Vector3(0.0, carrier_node.rotation.y, 0.0)
	carrier_node.visible = true

	_heli_navigation_lzs.clear()
	var _lz_profiler_start: int = FrameProfiler.begin("FlightDeckManager.nav_find_lzs")
	for slot in range(HELI_NAVIGATION_ROUTE_COUNT):
		var lz := _find_flat_navigation_test_lz(slot, nav_grid)
		if is_inf(lz.x):
			FrameProfiler.end("FlightDeckManager.nav_find_lzs", _lz_profiler_start)
			_heli_navigation_lzs.clear()
			push_warning("[TestScenario] Could not find flat fixed LZ for route %d" % slot)
			return false
		_heli_navigation_lzs.append(lz)
		_log_heli_test("route %d carrier=%s LZ=%s distance=%.0fm terrain_delta_y=%.0fm" % [
			slot + 1,
			str(_heli_navigation_center.snapped(Vector3.ONE)),
			str(lz.snapped(Vector3.ONE)),
			Vector2(lz.x - _heli_navigation_center.x, lz.z - _heli_navigation_center.z).length(),
			lz.y - _heli_navigation_center.y,
		])
	FrameProfiler.end("FlightDeckManager.nav_find_lzs", _lz_profiler_start)
	_log_heli_test("navigation carrier site=%s flat_radius=%.0fm routes=%d" % [
		str(_heli_navigation_center.snapped(Vector3.ONE)),
		HELI_NAVIGATION_CARRIER_FLAT_RADIUS_M,
		_heli_navigation_lzs.size(),
	])
	return true


func _find_flat_navigation_carrier_site(nav_grid: Node, requested_center: Vector3) -> Vector3:
	if nav_grid == null or not nav_grid.has_method("is_stable_footprint"):
		return Vector3.INF
	var ring_count := maxi(int(ceil(
		HELI_NAVIGATION_CARRIER_SEARCH_RADIUS_M / HELI_NAVIGATION_CARRIER_SEARCH_STEP_M
	)), 0)
	var candidates: Array[Vector3] = []
	var lowest_sample_y := INF
	for ring in range(ring_count + 1):
		var sample_count := 1 if ring == 0 else maxi(ring * 8, 8)
		var radius := float(ring) * HELI_NAVIGATION_CARRIER_SEARCH_STEP_M
		for sample_index in range(sample_count):
			var angle := TAU * float(sample_index) / float(sample_count)
			var candidate := requested_center + Vector3(cos(angle), 0.0, sin(angle)) * radius
			var ground_h := _navigation_test_sample_height(nav_grid, candidate)
			if is_nan(ground_h):
				continue
			candidate.y = ground_h
			candidates.append(candidate)
			lowest_sample_y = minf(lowest_sample_y, ground_h)
	if candidates.is_empty():
		return Vector3.INF

	# Prefer terrain close to the lowest sampled level (the practical meaning of
	# "ground level" on this stepped terrain). Fall back to any broad flat area only
	# if the low band contains none.
	for altitude_band in [HELI_NAVIGATION_CARRIER_GROUND_BAND_M, INF]:
		for candidate in candidates:
			if candidate.y > lowest_sample_y + altitude_band:
				continue
			if not bool(nav_grid.call(
				"is_stable_footprint", candidate.x, candidate.z,
				HELI_NAVIGATION_CARRIER_FLAT_RADIUS_M, 1.5,
				HELI_NAVIGATION_CARRIER_MAX_VARIATION_M
			)):
				continue
			if not bool(nav_grid.call(
				"is_stable_footprint", candidate.x, candidate.z,
				HELI_NAVIGATION_CARRIER_SURROUNDING_RADIUS_M,
				HELI_NAVIGATION_CARRIER_SURROUNDING_MAX_RELIEF_M,
				HELI_NAVIGATION_CARRIER_SURROUNDING_MAX_RELIEF_M
			)):
				continue
			_log_heli_test("navigation carrier broad-site accepted ground=%.1f lowest_sample=%.1f surrounding_radius=%.0fm max_relief=%.0fm" % [
				candidate.y, lowest_sample_y,
				HELI_NAVIGATION_CARRIER_SURROUNDING_RADIUS_M,
				HELI_NAVIGATION_CARRIER_SURROUNDING_MAX_RELIEF_M,
			])
			return candidate
	return Vector3.INF


func _find_flat_navigation_test_lz(slot: int, nav_grid: Node) -> Vector3:
	if nav_grid == null or not nav_grid.has_method("is_stable_footprint"):
		return Vector3.INF
	var base_angle := TAU * float(slot) / float(HELI_NAVIGATION_ROUTE_COUNT)
	if slot == 6:
		base_angle += deg_to_rad(HELI_NAVIGATION_ROUTE_7_LZ_ANGLE_BIAS_DEG)
	elif slot == 7:
		base_angle += deg_to_rad(HELI_NAVIGATION_ROUTE_8_LZ_ANGLE_BIAS_DEG)
	var ideal_radius := clampf(
		HELI_NAVIGATION_LZ_BASE_RADIUS_M
				+ HELI_NAVIGATION_LZ_RADIUS_STEP_M * float(slot)
				+ _navigation_lz_radius_bias_m(slot),
		HELI_NAVIGATION_MIN_LEG_M,
		HELI_NAVIGATION_MAX_LEG_M
	)
	var path_reject_logs := 0
	for level_band in [HELI_NAVIGATION_LZ_SAME_LEVEL_BAND_M, HELI_NAVIGATION_LZ_FALLBACK_LEVEL_BAND_M]:
		for angular_step in range(33):
			var signed_step := 0
			if angular_step > 0:
				signed_step = int((angular_step + 1) / 2)
				if angular_step % 2 == 0:
					signed_step = -signed_step
			var angle := base_angle + deg_to_rad(float(signed_step) * 2.5)
			var radial := Vector3(cos(angle), 0.0, sin(angle))
			for radius_step in range(15):
				var radius_offset := 0.0
				if radius_step > 0:
					var magnitude := float(int((radius_step + 1) / 2)) * 200.0
					radius_offset = magnitude if radius_step % 2 == 1 else -magnitude
				var radius := clampf(
					ideal_radius + radius_offset,
					HELI_NAVIGATION_MIN_LEG_M,
					HELI_NAVIGATION_MAX_LEG_M
				)
				var candidate := _heli_navigation_center + radial * radius
				var ground_h := _navigation_test_sample_height(nav_grid, candidate)
				if is_nan(ground_h):
					continue
				if absf(ground_h - _heli_navigation_center.y) > level_band:
					continue
				candidate.y = ground_h
				if _navigation_rejects_lz_candidate(slot, candidate):
					continue
				if not bool(nav_grid.call(
					"is_stable_footprint", candidate.x, candidate.z,
					HELI_NAVIGATION_LZ_FLAT_RADIUS_M, 1.5,
					HELI_NAVIGATION_LZ_MAX_VARIATION_M
				)):
					continue
				if not bool(nav_grid.call(
					"is_stable_footprint", candidate.x, candidate.z,
					HELI_NAVIGATION_LZ_SURROUNDING_RADIUS_M,
					HELI_NAVIGATION_LZ_SURROUNDING_MAX_RELIEF_M,
					HELI_NAVIGATION_LZ_SURROUNDING_MAX_RELIEF_M
				)):
					continue
				var route_quality: Dictionary = {}
				if HELI_NAVIGATION_LZ_PATH_QUALITY_PROBE_ENABLED \
						or _navigation_lz_path_quality_required(slot):
					var _path_quality_profiler_start: int = FrameProfiler.begin("FlightDeckManager.nav_lz_path_quality")
					route_quality = _navigation_get_lz_route_quality(nav_grid, _heli_navigation_center, candidate)
					FrameProfiler.end("FlightDeckManager.nav_lz_path_quality", _path_quality_profiler_start)
					if route_quality.is_empty():
						if path_reject_logs < HELI_NAVIGATION_LZ_PATH_REJECT_LOG_LIMIT:
							path_reject_logs += 1
							_log_heli_test("route %d rejected LZ path_probe_failed candidate=%s" % [
								slot + 1,
								str(candidate.snapped(Vector3.ONE)),
							])
						continue
					var path_ratio := float(route_quality.get("ratio", INF))
					if path_ratio > HELI_NAVIGATION_LZ_MAX_PATH_RATIO:
						if path_reject_logs < HELI_NAVIGATION_LZ_PATH_REJECT_LOG_LIMIT:
							path_reject_logs += 1
							_log_heli_test("route %d rejected LZ path_ratio=%.2f max=%.2f direct=%.0fm length=%.0fm points=%d candidate=%s" % [
								slot + 1,
								path_ratio,
								HELI_NAVIGATION_LZ_MAX_PATH_RATIO,
								float(route_quality.get("direct", 0.0)),
								float(route_quality.get("length", 0.0)),
								int(route_quality.get("points", 0)),
								str(candidate.snapped(Vector3.ONE)),
							])
						continue
				if level_band > HELI_NAVIGATION_LZ_SAME_LEVEL_BAND_M:
					_log_heli_test("route %d using fallback same-level band %.0fm terrain_delta_y=%.0fm" % [
						slot + 1,
						level_band,
						candidate.y - _heli_navigation_center.y,
					])
				if not route_quality.is_empty():
					_log_heli_test("route %d accepted LZ path_ratio=%.2f direct=%.0fm length=%.0fm points=%d" % [
						slot + 1,
						float(route_quality.get("ratio", 0.0)),
						float(route_quality.get("direct", 0.0)),
						float(route_quality.get("length", 0.0)),
						int(route_quality.get("points", 0)),
					])
				return candidate
	return Vector3.INF


func _navigation_lz_radius_bias_m(slot: int) -> float:
	if slot == 6:
		return HELI_NAVIGATION_ROUTE_7_LZ_RADIUS_BIAS_M
	if slot == 7:
		return HELI_NAVIGATION_ROUTE_8_LZ_RADIUS_BIAS_M
	return 0.0


func _navigation_lz_path_quality_required(slot: int) -> bool:
	return slot == 6 or slot == 7


func _navigation_rejects_lz_candidate(slot: int, candidate: Vector3) -> bool:
	var rel := candidate - _heli_navigation_center
	# Observed bad pocket: routes 7/8 repeatedly selected south/southeast LZs that are
	# flat enough to pass footprint tests but produce 1.9x-2.1x A* detours through
	# the same plateau choke. Keep searching for a neighboring flat site instead.
	if slot == 6:
		return rel.z < -5000.0 and rel.x > 2500.0
	if slot == 7:
		return rel.z < -4300.0 and rel.x > 2500.0
	return false


func _navigation_get_lz_route_quality(nav_grid: Node, start: Vector3, goal: Vector3) -> Dictionary:
	var grid := _navigation_build_path_preview_grid(nav_grid)
	if grid.is_empty():
		return {}
	var reference_ground := _heli_navigation_center.y
	var flight_ceiling := reference_ground + 2100.0
	var max_route_terrain_y := minf(reference_ground + 2000.0, flight_ceiling - 50.0)
	var params := _navigation_get_path_preview_params(max_route_terrain_y, flight_ceiling)
	var job_data := _navigation_make_path_preview_job_data(
		start,
		goal,
		grid,
		params,
		reference_ground,
		max_route_terrain_y
	)
	if job_data.is_empty():
		return {}
	HelicopterPilot._run_threaded_pathfinding_job(job_data)
	var result_variant: Variant = job_data.get("result", {})
	if not (result_variant is Dictionary):
		return {}
	var result := result_variant as Dictionary
	if not bool(result.get("success", false)):
		return {}
	var path_variant: Variant = result.get("final_path", [])
	if not (path_variant is Array):
		return {}
	var path := path_variant as Array
	if path.is_empty():
		return {}
	var direct := Vector2(start.x - goal.x, start.z - goal.z).length()
	if direct <= 1.0:
		return {}
	var path_length := _navigation_measure_horizontal_path_length(start, path)
	return {
		"ratio": path_length / direct,
		"length": path_length,
		"direct": direct,
		"points": path.size(),
		"elapsed_ms": int(result.get("elapsed_ms", 0)),
		"reason": String(result.get("reason", "")),
	}


func _navigation_build_path_preview_grid(nav_grid: Node) -> Dictionary:
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


func _navigation_get_path_preview_params(max_route_terrain_y: float, flight_ceiling: float) -> Dictionary:
	return {
		"heightmap_path_max_edge_risk_m": 5.0,
		"heightmap_path_edge_risk_penalty": 85.0,
		"heightmap_path_mountain_buffer_cells": 0,
		"heightmap_path_mountain_avoidance_m": 185.0,
		"heightmap_path_max_step_climb_m": 0.0,
		"heightmap_path_altitude_penalty": 0.035,
		"heightmap_path_climb_penalty": 1.0,
		"heightmap_path_high_terrain_penalty": 0.0,
		"heightmap_path_same_level_wall_risk_start_m": 8.0,
		"heightmap_path_same_level_wall_penalty": 50.0,
		"heightmap_path_ground_level_band_m": 35.0,
		"heightmap_path_first_plateau_min_m": 40.0,
		"heightmap_path_first_plateau_max_m": 180.0,
		"heightmap_path_ground_route_penalty": 0.0,
		"heightmap_path_low_route_penalty": 0.0,
		"heightmap_path_top_level_penalty": 0.08,
		"heightmap_path_upper_level_penalty": 10.0,
		"heightmap_path_level_change_penalty": 2.0,
		"heightmap_path_same_level_preferred_band_m": 80.0,
		"heightmap_path_same_level_soft_band_m": 220.0,
		"heightmap_path_same_level_penalty": 0.8,
		"heightmap_path_same_level_max_penalty": 180.0,
		"heightmap_path_same_level_departure_penalty": 75.0,
		"heightmap_path_target_agl_m": 50.0,
		"min_terrain_clearance_m": 24.0,
		"heightmap_path_carrot_distance_m": 520.0,
		"heightmap_path_insert_spacing_m": 100.0,
		"heightmap_path_simplify_altitude_error_m": 8.0,
		"heightmap_path_simplify_max_deviation_m": 900.0,
		"heightmap_path_pilot_min_segment_m": 170.0,
		"heightmap_path_pilot_max_turn_angle_deg": 95.0,
		"heightmap_path_direct_corridor_enabled": false,
		"heightmap_path_direct_corridor_max_climb_m": 420.0,
		"terrain_climb_lookahead_m": 900.0,
		"terrain_climb_capacity_scale": 0.5,
		"heightmap_path_climb_lead_speed_mps": 30.0,
		"max_climb_mps": 7.0,
		"terrain_sample_spacing_m": 120.0,
		"heightmap_path_simplify_enabled": true,
		"heightmap_path_heuristic_weight": 1.15,
		"heightmap_path_turn_soft_angle_deg": 18.0,
		"heightmap_path_turn_penalty": 420.0,
		"min_altitude": -1000.0,
		"max_altitude": 10000.0,
		"route_terrain_ceiling": max_route_terrain_y,
		"flight_ceiling": flight_ceiling,
	}


func _navigation_make_path_preview_job_data(
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
	var pad := maxf(600.0, dist_max * 0.5)
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


func _navigation_measure_horizontal_path_length(start: Vector3, path: Array) -> float:
	var total := 0.0
	var previous := start
	for point_variant in path:
		if not (point_variant is Vector3):
			continue
		var point := point_variant as Vector3
		total += Vector2(point.x - previous.x, point.z - previous.z).length()
		previous = point
	return total




func _navigation_test_sample_height(nav_grid: Node, world_pos: Vector3) -> float:
	if nav_grid == null or not nav_grid.has_method("sample_height"):
		return NAN
	var height := float(nav_grid.call("sample_height", world_pos.x, world_pos.z))
	return height if height > -500000.0 and not is_nan(height) else NAN


# --- Navigation report -----------------------------------------------------------
# Polls each navigation-test helicopter's mission_phase to time legs and laps, and
# writes per-event + periodic-summary metrics to res://heli_navigation_report.log.
# A "lap" = OUTBOUND -> reach/land at LZ -> INBOUND -> reach/land at carrier.

func _navigation_report_now_s() -> float:
	return float(Time.get_ticks_msec() - _heli_test_start_time_msec) / 1000.0


func _ensure_navigation_route_stats() -> void:
	if _navigation_route_stats.size() == HELI_NAVIGATION_ROUTE_COUNT:
		return
	_navigation_route_stats.clear()
	for _i in range(HELI_NAVIGATION_ROUTE_COUNT):
		_navigation_route_stats.append({
			"laps": 0, "crashes": 0,
			"lz_reached": 0, "close_calls": 0,
			"last_fitness": 0.0, "best_fitness": -INF,
			"outbound_sum_s": 0.0, "outbound_n": 0,
			"return_sum_s": 0.0, "return_n": 0,
			"lap_sum_s": 0.0, "lap_n": 0,
			"best_lap_s": INF,
		})


func _update_navigation_report(_delta: float) -> void:
	# Route geometry is not available until the terrain grid has baked and the
	# carrier-sized flat site has been selected.
	if _heli_navigation_lzs.size() != HELI_NAVIGATION_ROUTE_COUNT:
		return
	if not _navigation_report_started:
		_start_navigation_report()
	var _nav_refill_profiler_start: int = FrameProfiler.begin("FlightDeckManager.nav_force_refill")
	_navigation_force_refill_if_tuner_idle()
	FrameProfiler.end("FlightDeckManager.nav_force_refill", _nav_refill_profiler_start)
	_ensure_navigation_route_stats()
	var now := _navigation_report_now_s()

	# Build the set of currently-alive tracked nav helicopters and detect transitions.
	var alive: Dictionary = {}
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is RigidBody3D) or seen.has(node.get_instance_id()):
				continue
			seen[node.get_instance_id()] = true
			var ac := node as RigidBody3D
			if not bool(ac.get_meta(HELI_NAVIGATION_TEST_META, false)) or ac.is_queued_for_deletion():
				continue
			var id := ac.get_instance_id()
			# Retrieval time is carrier logistics, not navigation-leg time. Begin
			# tracking only after the helicopter has actually released from deck. Once
			# a nav-test helicopter is already tracked, keep watching it through carrier
			# recovery so the AT_CARRIER transition can be counted as a lap.
			var carrier_owned := bool(ac.get_meta("controls_disabled", false)) \
					or bool(ac.get_meta("carrier_transport_mode", false)) \
					or bool(ac.get_meta("helicopter_deck_takeoff_ready", false))
			if carrier_owned and not _navigation_tracked.has(id):
				continue
			var pilot := ac.find_child("HelicopterPilot", true, false)
			if pilot == null:
				continue
			alive[id] = true
			var slot := int(ac.get_meta(HELI_NAVIGATION_ROUTE_SLOT_META, -1))
			var phase := int(pilot.get("mission_phase"))
			if _navigation_complete_return_near_carrier(id, ac, now):
				continue
			_navigation_track_phase(id, ac, pilot, slot, phase, now)
			if not _navigation_tracked.has(id):
				continue
			if _navigation_update_progress_watchdog(id, ac, pilot, now):
				continue
			_navigation_record_tuning_sample(id, ac, pilot, _delta)

	# Any tracked heli no longer alive (and not cleanly recovered) counts as a crash.
	for id in _navigation_tracked.keys():
		if not alive.has(id):
			_navigation_on_lost(id, now)

	_navigation_report_summary_timer_s -= _delta
	if _navigation_report_summary_timer_s <= 0.0:
		_navigation_report_summary_timer_s = HELI_NAVIGATION_REPORT_SUMMARY_S
		_write_navigation_summary(now)


func _navigation_track_phase(id: int, ac: RigidBody3D, pilot: Node, slot: int, phase: int, now: float) -> void:
	# MissionPhase: 0=OUTBOUND 1=AT_LZ 2=INBOUND 3=AT_CARRIER 4=RESCUE.
	if not _navigation_tracked.has(id):
		var tuning_assignment: Dictionary = {}
		var cached_assignment_variant: Variant = ac.get_meta(HELI_NAVIGATION_TUNING_ASSIGNMENT_META, {})
		if cached_assignment_variant is Dictionary:
			tuning_assignment = cached_assignment_variant as Dictionary
		if ac.has_meta(HELI_NAVIGATION_TUNING_ASSIGNMENT_META):
			ac.remove_meta(HELI_NAVIGATION_TUNING_ASSIGNMENT_META)
		if tuning_assignment.is_empty():
			tuning_assignment = _navigation_begin_tuning_trial(ac, pilot, slot)
		slot = int(tuning_assignment.get("route_slot", slot))
		if slot >= 0 and slot < _heli_navigation_lzs.size():
			ac.set_meta(HELI_NAVIGATION_ROUTE_SLOT_META, slot)
			ac.set_meta(HELI_NAVIGATION_FIXED_LZ_META, _heli_navigation_lzs[slot])
		_navigation_tracked[id] = {
			"name": ac.name, "slot": slot, "phase": phase,
			"leg_start_s": now, "outbound_start_s": now,
			"progress_best_distance_m": INF, "progress_last_s": now,
			"tuning_trial_id": int(tuning_assignment.get("trial_id", 0)),
			"tuning_candidate": int(tuning_assignment.get("candidate", -1)),
			"tuning_sample_accum_s": 0.0,
		}
		_write_navigation_line("SPAWN craft=%s route=%d candidate=%d trial=%d t=%.1f" % [
			ac.name, slot + 1, int(tuning_assignment.get("candidate", -1)) + 1,
			int(tuning_assignment.get("trial_id", 0)), now])
		return
	var t: Dictionary = _navigation_tracked[id]
	var prev := int(t["phase"])
	if phase == prev:
		return
	var craft_name := ac.name
	# Transitions we care about.
	if prev == 0 and phase == 1:
		# Reached / landed at the LZ — end of outbound leg.
		var outbound_s := now - float(t["outbound_start_s"])
		t["outbound_s"] = outbound_s
		_record_navigation_leg(slot, "outbound", outbound_s)
		if slot >= 0 and slot < _navigation_route_stats.size():
			_navigation_route_stats[slot]["lz_reached"] = int(_navigation_route_stats[slot].get("lz_reached", 0)) + 1
		_navigation_tuner_call("mark_lz_reached", [int(t.get("tuning_trial_id", 0)), outbound_s])
		_write_navigation_line("LZ_REACHED craft=%s route=%d outbound=%.1fs t=%.1f" % [craft_name, slot + 1, outbound_s, now])
	elif phase == 2:
		# Departed LZ, heading home — start of return leg.
		t["return_start_s"] = now
	elif phase == 3:
		# Back at the carrier — lap complete.
		var return_s := now - float(t.get("return_start_s", now))
		var lap_s := now - float(t["outbound_start_s"])
		_record_navigation_leg(slot, "return", return_s)
		_record_navigation_lap(slot, lap_s)
		var lap_result: Variant = _navigation_tuner_call("end_trial", [int(t.get("tuning_trial_id", 0)), "lap"], {})
		if lap_result is Dictionary:
			_navigation_capture_tuning_result(slot, lap_result as Dictionary)
		t["tuning_trial_id"] = 0
		_write_navigation_line("LAP craft=%s route=%d return=%.1fs lap=%.1fs t=%.1f" % [craft_name, slot + 1, return_s, lap_s, now])
		# Navigation tuning is not testing deck recovery. If a heli slips past the
		# near-carrier capture gate and reaches AT_CARRIER, count the lap and remove
		# it before landing/recovery machinery can block the next launch.
		t["terminal_reason"] = "lap"
		_navigation_tracked.erase(id)
		ac.queue_free()
		return
	elif prev == 3 and phase == 0:
		# Some recovered aircraft remain instantiated and launch again. Give the new
		# lap a fresh candidate only when it actually departs.
		var assignment := _navigation_begin_tuning_trial(ac, pilot, slot)
		t["tuning_trial_id"] = int(assignment.get("trial_id", 0))
		t["tuning_candidate"] = int(assignment.get("candidate", -1))
		t["tuning_sample_accum_s"] = 0.0
		t["outbound_start_s"] = now
	t["phase"] = phase
	t["leg_start_s"] = now
	t["progress_best_distance_m"] = INF
	t["progress_last_s"] = now


func _navigation_update_progress_watchdog(
		id: int,
		ac: RigidBody3D,
		pilot: Node,
		now: float
) -> bool:
	if not _navigation_tracked.has(id):
		return false
	var tracked: Dictionary = _navigation_tracked[id]
	var phase := int(tracked.get("phase", -1))
	if phase != 0 and phase != 2:
		tracked["progress_best_distance_m"] = INF
		tracked["progress_last_s"] = now
		return false
	var destination_variant: Variant = pilot.get("destination")
	if not (destination_variant is Vector3):
		return false
	var destination := destination_variant as Vector3
	var distance_m := Vector2(
		ac.global_position.x - destination.x,
		ac.global_position.z - destination.z
	).length()
	if distance_m <= HELI_NAVIGATION_PROGRESS_GOAL_RADIUS_M:
		tracked["progress_best_distance_m"] = distance_m
		tracked["progress_last_s"] = now
		return false
	var best_distance := float(tracked.get("progress_best_distance_m", INF))
	if not is_finite(best_distance) \
			or distance_m <= best_distance - HELI_NAVIGATION_PROGRESS_EPSILON_M:
		tracked["progress_best_distance_m"] = distance_m
		tracked["progress_last_s"] = now
		return false
	if now - float(tracked.get("progress_last_s", now)) < HELI_NAVIGATION_NO_PROGRESS_TIMEOUT_S:
		return false

	var trial_id := int(tracked.get("tuning_trial_id", 0))
	if trial_id > 0:
		var result: Variant = _navigation_tuner_call("end_trial", [trial_id, "stuck"], {})
		if result is Dictionary:
			_navigation_capture_tuning_result(int(tracked.get("slot", -1)), result as Dictionary)
	tracked["tuning_trial_id"] = 0
	tracked["terminal_reason"] = "stuck"
	_write_navigation_line("STUCK craft=%s route=%d phase=%d dist=%.0fm best=%.0fm idle=%.0fs t=%.1f" % [
		ac.name,
		int(tracked.get("slot", -1)) + 1,
		phase,
		distance_m,
		best_distance,
		now - float(tracked.get("progress_last_s", now)),
		now,
	])
	_navigation_tracked.erase(id)
	ac.queue_free()
	return true


func _navigation_complete_return_near_carrier(id: int, ac: RigidBody3D, now: float) -> bool:
	if not _navigation_tracked.has(id):
		return false
	var tracked: Dictionary = _navigation_tracked[id]
	if int(tracked.get("phase", -1)) != 2:
		return false
	var carrier_node := get_parent() as Node3D
	var carrier_pos := _heli_navigation_center
	if is_instance_valid(carrier_node):
		carrier_pos = carrier_node.global_position
	var carrier_dist := Vector2(
		ac.global_position.x - carrier_pos.x,
		ac.global_position.z - carrier_pos.z
	).length()
	if carrier_dist > maxf(HELI_NAVIGATION_RETURN_CAPTURE_RADIUS_M, 1.0):
		return false

	var slot := int(tracked.get("slot", -1))
	var return_s := now - float(tracked.get("return_start_s", tracked.get("leg_start_s", now)))
	var lap_s := now - float(tracked.get("outbound_start_s", now))
	_record_navigation_leg(slot, "return", return_s)
	_record_navigation_lap(slot, lap_s)
	var trial_id := int(tracked.get("tuning_trial_id", 0))
	if trial_id > 0:
		var lap_result: Variant = _navigation_tuner_call("end_trial", [trial_id, "lap"], {})
		if lap_result is Dictionary:
			_navigation_capture_tuning_result(slot, lap_result as Dictionary)
	tracked["tuning_trial_id"] = 0
	tracked["terminal_reason"] = "lap_capture"
	_write_navigation_line("LAP_CAPTURE craft=%s route=%d return=%.1fs lap=%.1fs carrier_dist=%.0fm t=%.1f" % [
		ac.name,
		slot + 1,
		return_s,
		lap_s,
		carrier_dist,
		now,
	])
	_navigation_tracked.erase(id)
	ac.queue_free()
	return true


func _navigation_on_lost(id: int, now: float) -> void:
	var t: Dictionary = _navigation_tracked.get(id, {})
	_navigation_tracked.erase(id)
	if t.is_empty():
		return
	var slot := int(t.get("slot", -1))
	if String(t.get("terminal_reason", "")) == "stuck":
		return
	# Lost while AT_CARRIER (phase 3) is a clean recovery/replacement, not a crash.
	if int(t.get("phase", 0)) == 3:
		return
	if slot >= 0 and slot < _navigation_route_stats.size():
		_navigation_route_stats[slot]["crashes"] = int(_navigation_route_stats[slot]["crashes"]) + 1
	var tuning_trial_id := int(t.get("tuning_trial_id", 0))
	if tuning_trial_id > 0:
		var crash_result: Variant = _navigation_tuner_call("end_trial", [tuning_trial_id, "crash"], {})
		if crash_result is Dictionary:
			_navigation_capture_tuning_result(slot, crash_result as Dictionary)
	_write_navigation_line("CRASH craft=%s route=%d phase=%d t=%.1f" % [str(t.get("name", "?")), slot + 1, int(t.get("phase", 0)), now])


func _navigation_begin_tuning_trial(ac: RigidBody3D, pilot: Node, slot: int) -> Dictionary:
	var result: Variant = _navigation_tuner_call("begin_trial", [pilot.get_instance_id(), ac.name, slot])
	if not (result is Dictionary):
		return {}
	var assignment := result as Dictionary
	var assigned_slot := int(assignment.get("route_slot", slot))
	if assigned_slot >= 0 and assigned_slot < _heli_navigation_lzs.size():
		ac.set_meta(HELI_NAVIGATION_ROUTE_SLOT_META, assigned_slot)
		ac.set_meta(HELI_NAVIGATION_FIXED_LZ_META, _heli_navigation_lzs[assigned_slot])
		if assigned_slot != slot:
			_write_navigation_line("TUNING_REASSIGN craft=%s requested_route=%d assigned_route=%d" % [
				ac.name, slot + 1, assigned_slot + 1
			])
	var genome_variant: Variant = assignment.get("genome", {})
	if genome_variant is Dictionary and pilot.has_method("apply_navigation_tuning_genome"):
		pilot.call("apply_navigation_tuning_genome", genome_variant as Dictionary)
	return assignment


func _navigation_record_tuning_sample(
		id: int,
		ac: RigidBody3D,
		pilot: Node,
		delta: float
) -> void:
	if not _navigation_tracked.has(id):
		return
	var tracked: Dictionary = _navigation_tracked[id]
	var trial_id := int(tracked.get("tuning_trial_id", 0))
	if trial_id <= 0:
		return
	var accumulator := float(tracked.get("tuning_sample_accum_s", 0.0)) + delta
	if accumulator < 0.25:
		tracked["tuning_sample_accum_s"] = accumulator
		return
	tracked["tuning_sample_accum_s"] = 0.0
	if pilot.has_method("get_navigation_tuning_sample"):
		var sample_variant: Variant = pilot.call("get_navigation_tuning_sample")
		if sample_variant is Dictionary:
			_navigation_tuner_call("record_sample", [trial_id, sample_variant as Dictionary, accumulator])
	var timed_out := bool(_navigation_tuner_call("is_trial_timed_out", [trial_id], false))
	if timed_out:
		var timeout_result: Variant = _navigation_tuner_call("end_trial", [trial_id, "timeout"], {})
		if timeout_result is Dictionary:
			_navigation_capture_tuning_result(int(tracked.get("slot", -1)), timeout_result as Dictionary)
		tracked["tuning_trial_id"] = 0
		_write_navigation_line("TUNING_TIMEOUT craft=%s route=%d trial=%d" % [ac.name, int(tracked.get("slot", -1)) + 1, trial_id])
		ac.queue_free()


func _navigation_tuner_call(method: StringName, args: Array = [], fallback: Variant = null) -> Variant:
	var tuner := get_node_or_null("/root/HelicopterNavigationTuner")
	if tuner == null or not tuner.has_method(method):
		return fallback
	return tuner.callv(method, args)


func _navigation_capture_tuning_result(slot: int, result: Dictionary) -> void:
	if slot < 0 or slot >= _navigation_route_stats.size() or result.is_empty():
		return
	var stats: Dictionary = _navigation_route_stats[slot]
	stats["close_calls"] = int(stats.get("close_calls", 0)) + int(result.get("close_calls", 0))
	var fitness := float(result.get("fitness", 0.0))
	stats["last_fitness"] = fitness
	stats["best_fitness"] = maxf(float(stats.get("best_fitness", -INF)), fitness)


func _record_navigation_leg(slot: int, leg: String, seconds: float) -> void:
	if slot < 0 or slot >= _navigation_route_stats.size():
		return
	var s: Dictionary = _navigation_route_stats[slot]
	s["%s_sum_s" % leg] = float(s["%s_sum_s" % leg]) + seconds
	s["%s_n" % leg] = int(s["%s_n" % leg]) + 1


func _record_navigation_lap(slot: int, lap_s: float) -> void:
	if slot < 0 or slot >= _navigation_route_stats.size():
		return
	var s: Dictionary = _navigation_route_stats[slot]
	s["laps"] = int(s["laps"]) + 1
	s["lap_sum_s"] = float(s["lap_sum_s"]) + lap_s
	s["lap_n"] = int(s["lap_n"]) + 1
	s["best_lap_s"] = minf(float(s["best_lap_s"]), lap_s)


func _start_navigation_report() -> void:
	_navigation_report_started = true
	_navigation_tracked.clear()
	_ensure_navigation_route_stats()
	var header := "HELI NAVIGATION REPORT START t=%.1f routes=%d center=%s\n" % [
		_navigation_report_now_s(), HELI_NAVIGATION_ROUTE_COUNT, str(_heli_navigation_center.snapped(Vector3.ONE))]
	for slot in range(_heli_navigation_lzs.size()):
		var lz: Vector3 = _heli_navigation_lzs[slot]
		header += "SETUP route=%d carrier=%s LZ=%s distance=%.0fm terrain_delta_y=%.0fm\n" % [
			slot + 1,
			str(_heli_navigation_center.snapped(Vector3.ONE)),
			str(lz.snapped(Vector3.ONE)),
			Vector2(lz.x - _heli_navigation_center.x, lz.z - _heli_navigation_center.z).length(),
			lz.y - _heli_navigation_center.y,
		]
	var f := FileAccess.open(HELI_NAVIGATION_REPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(header)
		f.close()


func _write_navigation_line(line: String) -> void:
	var f := FileAccess.open(HELI_NAVIGATION_REPORT_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(HELI_NAVIGATION_REPORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_string("t=%.1f %s\n" % [_navigation_report_now_s(), line])
	f.close()


func _write_navigation_summary(now: float) -> void:
	var total_laps := 0
	var total_crashes := 0
	var lines: PackedStringArray = PackedStringArray()
	lines.append("==== SUMMARY t=%.1f ====" % now)
	for slot in range(_navigation_route_stats.size()):
		var s: Dictionary = _navigation_route_stats[slot]
		var laps := int(s["laps"])
		var crashes := int(s["crashes"])
		total_laps += laps
		total_crashes += crashes
		var avg_out := (float(s["outbound_sum_s"]) / float(s["outbound_n"])) if int(s["outbound_n"]) > 0 else 0.0
		var avg_ret := (float(s["return_sum_s"]) / float(s["return_n"])) if int(s["return_n"]) > 0 else 0.0
		var avg_lap := (float(s["lap_sum_s"]) / float(s["lap_n"])) if int(s["lap_n"]) > 0 else 0.0
		var best := float(s["best_lap_s"])
		var best_text := "%.1f" % best if is_finite(best) else "-"
		lines.append("route=%d laps=%d crashes=%d avg_out=%.1fs avg_ret=%.1fs avg_lap=%.1fs best_lap=%s" % [
			slot + 1, laps, crashes, avg_out, avg_ret, avg_lap, best_text])
	lines.append("TOTAL laps=%d crashes=%d" % [total_laps, total_crashes])
	var tuner_status_variant: Variant = _navigation_tuner_call("get_status", [], {})
	if tuner_status_variant is Dictionary:
		var tuner_status := tuner_status_variant as Dictionary
		var route_rounds_parts := PackedStringArray()
		var route_rounds_variant: Variant = tuner_status.get("route_rounds", [])
		if route_rounds_variant is Array:
			for round_variant in route_rounds_variant:
				route_rounds_parts.append(str(int(round_variant)))
		var route_rounds_text := ",".join(route_rounds_parts)
		lines.append("TUNER gen=%d results=%d/%d pending=%d active=%d remaining=%d next_trial=%d rounds=[%s]" % [
			int(tuner_status.get("generation", 0)),
			int(tuner_status.get("scored_results", 0)),
			int(tuner_status.get("required_results", 0)),
			int(tuner_status.get("pending_scored_trials", 0)),
			int(tuner_status.get("active_trials", 0)),
			int(tuner_status.get("remaining_results", 0)),
			int(tuner_status.get("next_trial_id", 0)),
			route_rounds_text,
		])
	for line in lines:
		_write_navigation_line(line)


func _queue_heli_navigation_test_aircraft(slot: int) -> bool:
	if slot < 0 or slot >= _heli_navigation_lzs.size():
		return false
	var scene: PackedScene = aircraft_11_scene
	if scene == null:
		scene = load("res://Aircraft/Aircraft_11.tscn") as PackedScene
	if scene == null:
		push_warning("[TestScenario] Aircraft_11.tscn not found for navigation range")
		return false
	var entry := _make_stored_aircraft_entry_unassigned("Aircraft_11_nav_r%d" % (slot + 1), scene)
	var metadata: Dictionary = entry.get("metadata", {})
	metadata[HELI_TEST_TYPE_META] = "Aircraft_11"
	metadata[HELI_NAVIGATION_TEST_META] = true
	metadata[HELI_NAVIGATION_ROUTE_SLOT_META] = slot
	metadata[HELI_NAVIGATION_FIXED_LZ_META] = _heli_navigation_lzs[slot]
	metadata["pilot_livery_colors"] = {
		"main_color": Color.from_hsv(float(slot) / float(HELI_NAVIGATION_ROUTE_COUNT), 0.55, 0.65),
		"main_color_dark": Color(0.06, 0.08, 0.11),
		"helmet_color_1": Color(0.80, 0.80, 0.72),
		"helmet_color_2": Color(0.18, 0.23, 0.28),
	}
	entry["metadata"] = metadata
	if not _ensure_pilot_assigned_for_data(entry):
		push_warning("[TestScenario] Could not allocate reusable test pilot for route %d" % (slot + 1))
		return false
	stored_aircraft.append(entry)
	_log_heli_test("hangar queued Aircraft_11 route=%d LZ=%s" % [
		slot + 1,
		str(_heli_navigation_lzs[slot].snapped(Vector3.ONE)),
	])
	return true


func _clear_navigation_test_world_clutter() -> void:
	var cleaned := 0
	var seen: Dictionary = {}
	for group_name in ["buildings", "enemy_bases", "gun_emplacements", "ground_vehicles"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node) or node == get_parent():
				continue
			var instance_id := node.get_instance_id()
			if seen.has(instance_id):
				continue
			seen[instance_id] = true
			node.queue_free()
			cleaned += 1
	if cleaned > 0:
		_log_heli_test("navigation clutter removed=%d" % cleaned)


func _reset_heli_test_stats() -> void:
	_heli_test_start_time_msec = Time.get_ticks_msec()
	_heli_ui_update_accum_s = 0.0
	for key in _heli_test_stats.keys():
		_heli_test_stats[key] = {"spawned": 0, "lz": 0, "carrier": 0, "crash": 0}


func _ensure_physical_test_ui() -> void:
	if is_instance_valid(_heli_ui_canvas):
		_heli_ui_canvas.layer = HELI_TEST_UI_LAYER
		if is_instance_valid(_heli_ui_bg):
			_heli_ui_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_instance_valid(_heli_ui_label):
			_heli_ui_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	_heli_ui_canvas = CanvasLayer.new()
	_heli_ui_canvas.layer = HELI_TEST_UI_LAYER
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bg.offset_left = -1460.0
	bg.offset_top = 20.0
	bg.offset_right = -20.0
	bg.offset_bottom = 740.0
	_heli_ui_canvas.add_child(bg)
	_heli_ui_bg = bg
	_heli_ui_label = Label.new()
	_heli_ui_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heli_ui_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_heli_ui_label.offset_left = 18.0
	_heli_ui_label.offset_top = 18.0
	_heli_ui_label.offset_right = -18.0
	_heli_ui_label.offset_bottom = -18.0
	var ui_font := SystemFont.new()
	ui_font.font_names = PackedStringArray(["Consolas", "Courier New"])
	_heli_ui_label.add_theme_font_override("font", ui_font)
	_heli_ui_label.add_theme_font_size_override("font_size", 20)
	bg.add_child(_heli_ui_label)
	add_child(_heli_ui_canvas)


func _update_physical_test_ui() -> void:
	if not is_instance_valid(_heli_ui_label):
		return
	var elapsed_s := maxi((Time.get_ticks_msec() - _heli_test_start_time_msec) / 1000, 0)
	var title := "HELICOPTER AIMING RANGE" if _heli_test_active else "HELICOPTER NAVIGATION LOOP"
	var subtitle := "8 aircraft / 8 unlimited-health targets" if _heli_test_active \
			else "%d fixed terrain routes / crash replacement enabled" % HELI_NAVIGATION_ROUTE_COUNT
	var text := "%s\n%s\nRuntime: %02d:%02d:%02d  |  F11 next / Shift+F11 previous\n\n" % [
		title, subtitle, elapsed_s / 3600, (elapsed_s / 60) % 60, elapsed_s % 60,
	]
	if _heli_navigation_test_active:
		text += _get_navigation_scoreboard_text()
		_heli_ui_label.text = text
		return
	text += "%-12s | %-7s | %-2s | %-7s | %-5s\n" % ["AIRCRAFT", "SPAWNED", "LZ", "CARRIER", "CRASH"]
	text += "------------------------------------------------\n"
	for key in ["Aircraft_9", "Aircraft_10", "Aircraft_11"]:
		var st: Dictionary = _heli_test_stats[key]
		text += "%-12s | %7d | %2d | %7d | %5d\n" % [key, st["spawned"], st["lz"], st["carrier"], st["crash"]]
	_heli_ui_label.text = text


func _get_navigation_tuner_ui_text() -> String:
	var tuner_status_variant: Variant = _navigation_tuner_call("get_status", [], {})
	if not (tuner_status_variant is Dictionary):
		return "TUNER unavailable\n\n"
	var tuner_status := tuner_status_variant as Dictionary
	var route_rounds_parts := PackedStringArray()
	var route_rounds_variant: Variant = tuner_status.get("route_rounds", [])
	if route_rounds_variant is Array:
		for round_variant in route_rounds_variant:
			route_rounds_parts.append(str(int(round_variant)))
	var route_rounds_text := ",".join(route_rounds_parts)
	var best_trial_text := _format_navigation_best_trial_text(tuner_status.get("generation_best_trial", {}))
	var champion_text := _format_navigation_champion_text(tuner_status.get("all_time_best", {}))
	var required := int(tuner_status.get("required_results", 0))
	var scored := int(tuner_status.get("scored_results", 0))
	var percent := 0.0
	if required > 0:
		percent = float(scored) * 100.0 / float(required)
	return "TUNER gen=%d  trials=%d/%d (%3.0f%%)  pending=%d  active=%d  remaining=%d  next=T%d\nrounds=[%s]\nBEST TRIAL %s\nCHAMPION   %s\n\n" % [
		int(tuner_status.get("generation", 0)),
		scored,
		required,
		percent,
		int(tuner_status.get("pending_scored_trials", 0)),
		int(tuner_status.get("active_trials", 0)),
		int(tuner_status.get("remaining_results", 0)),
		int(tuner_status.get("next_trial_id", 0)),
		route_rounds_text,
		best_trial_text,
		champion_text,
	]


func _format_navigation_best_trial_text(summary_variant: Variant) -> String:
	if not (summary_variant is Dictionary):
		return "-"
	var summary := summary_variant as Dictionary
	if summary.is_empty():
		return "-"
	var candidate := int(summary.get("candidate", -1))
	var candidate_text := "C%d" % (candidate + 1) if candidate >= 0 else "C?"
	var route := int(summary.get("route", 0))
	var route_text := "R%d" % route if route > 0 else "R?"
	var exit_text := "lap" if bool(summary.get("lap_completed", false)) else String(summary.get("exit_reason", "?"))
	return "%s %s T%d fit=%+.0f xtrk=%.0fm fpv=%.1f/%.1fdeg slalom=%d close=%d nopth=%.0fs %s" % [
		candidate_text,
		route_text,
		int(summary.get("trial_id", 0)),
		float(summary.get("fitness", 0.0)),
		float(summary.get("mean_path_cross_track_m", 0.0)),
		float(summary.get("mean_path_fpv_error_deg", 0.0)),
		float(summary.get("mean_path_fpv_vertical_error_deg", 0.0)),
		int(summary.get("path_slalom_crossings", 0)),
		int(summary.get("close_calls", 0)),
		float(summary.get("no_path_time_s", 0.0)),
		exit_text,
	]


func _format_navigation_champion_text(summary_variant: Variant) -> String:
	if not (summary_variant is Dictionary):
		return "-"
	var summary := summary_variant as Dictionary
	if summary.is_empty():
		return "-"
	var candidate := int(summary.get("candidate", -1))
	var candidate_text := "C%d" % (candidate + 1) if candidate >= 0 else "C?"
	return "%s fit=%+.0f trials=%d laps=%d lz=%d crash=%d xtrk=%.0fm hdg=%.1fdeg slalom=%.1f" % [
		candidate_text,
		float(summary.get("fitness", 0.0)),
		int(summary.get("trials", 0)),
		int(summary.get("laps", 0)),
		int(summary.get("lz_reached", 0)),
		int(summary.get("crashes", 0)),
		float(summary.get("mean_path_cross_track_m", 0.0)),
		float(summary.get("mean_path_heading_error_deg", 0.0)),
		float(summary.get("mean_path_slalom_crossings", 0.0)),
	]


func _get_navigation_scoreboard_text() -> String:
	_ensure_navigation_route_stats()
	var tracked_by_slot: Dictionary = {}
	for tracked_variant in _navigation_tracked.values():
		if not (tracked_variant is Dictionary):
			continue
		var tracked := tracked_variant as Dictionary
		var slot := int(tracked.get("slot", -1))
		if slot >= 0 and slot < HELI_NAVIGATION_ROUTE_COUNT:
			tracked_by_slot[slot] = tracked
	var text := _get_navigation_tuner_ui_text()
	text += "%-4s %-5s %-7s %6s %4s %5s %9s %9s %6s %5s %7s\n" % [
		"HELI", "CAND", "PHASE", "CLOSE", "LZ", "CRASH", "FIT NOW", "BEST", "XTRK", "NOPTH", "MINCLR"]
	text += "--------------------------------------------------------------------------------------\n"
	for slot in range(HELI_NAVIGATION_ROUTE_COUNT):
		var stats: Dictionary = _navigation_route_stats[slot]
		var tracked: Dictionary = tracked_by_slot.get(slot, {})
		var trial_id := int(tracked.get("tuning_trial_id", 0))
		var snapshot: Dictionary = {}
		if trial_id > 0:
			var snapshot_variant: Variant = _navigation_tuner_call("get_trial_snapshot", [trial_id], {})
			if snapshot_variant is Dictionary:
				snapshot = snapshot_variant as Dictionary
		var candidate := int(snapshot.get("candidate", tracked.get("tuning_candidate", -1)))
		var candidate_text := "C%d" % (candidate + 1) if candidate >= 0 else "-"
		var phase := int(tracked.get("phase", -1))
		var phase_text := "WAIT"
		match phase:
			0: phase_text = "OUT"
			1: phase_text = "AT LZ"
			2: phase_text = "IN"
			3: phase_text = "HOME"
			4: phase_text = "RESCUE"
		var close_calls := int(stats.get("close_calls", 0)) + int(snapshot.get("close_calls", 0))
		var fitness := float(snapshot.get("fitness", stats.get("last_fitness", 0.0)))
		var best_fitness := float(stats.get("best_fitness", -INF))
		var best_text := "%+.0f" % best_fitness if is_finite(best_fitness) else "-"
		var mean_cross_track := float(snapshot.get("mean_path_cross_track_m", 0.0))
		var no_path_time := float(snapshot.get("no_path_time_s", 0.0))
		var min_clearance := float(snapshot.get("min_clearance_m", -1.0))
		var min_clearance_text := "%.0fm" % min_clearance if min_clearance >= 0.0 else "-"
		text += "H%-3d %-5s %-7s %6d %4d %5d %+9.0f %9s %5.0fm %5.0fs %7s\n" % [
			slot + 1, candidate_text, phase_text, close_calls,
			int(stats.get("lz_reached", 0)), int(stats.get("crashes", 0)),
			fitness, best_text, mean_cross_track, no_path_time, min_clearance_text]
	text += "\nFIT NOW = live trial score; XTRK = mean route error; NOPTH = unscored no-path time"
	return text


func _toggle_heli_test_mode() -> void:
	_heli_test_active = not _heli_test_active

	if not _heli_test_active:
		_log_heli_test("mode OFF")
		_heli_test_dummy_retry_s = 0.0
		_set_heli_test_friendly_ops_suspended(false)
		FrameProfiler.set_enabled(false, "heli test off")
		for i in range(stored_aircraft.size()):
			var stored_data: Dictionary = stored_aircraft[i]
			var metadata_variant: Variant = stored_data.get("metadata", {})
			if metadata_variant is Dictionary:
				var metadata: Dictionary = metadata_variant
				metadata.erase(HELI_TEST_TYPE_META)
				metadata.erase(HELI_TEST_UNLIMITED_AMMO_META)
				metadata.erase(HELI_TEST_COMBAT_MODE_META)
				metadata.erase(HELI_TEST_FLAT_GROUND_Y_META)
				metadata.erase(HELI_TEST_ARENA_CENTER_META)
				metadata.erase(HELI_TEST_ARENA_RADIUS_META)
				stored_data["metadata"] = metadata
			stored_aircraft[i] = stored_data
		# Despawn all live helicopters
		for node in get_tree().get_nodes_in_group("aircraft"):
			if node is RigidBody3D and _is_helicopter_aircraft(node as RigidBody3D):
				(node as RigidBody3D).queue_free()
		var poi_mgr_off := get_node_or_null("/root/POIManager")
		if poi_mgr_off and "reveals_disabled" in poi_mgr_off:
			poi_mgr_off.set("reveals_disabled", false)
		var dnc_off := get_tree().current_scene.find_child("DayNightCycle", true, false) if get_tree().current_scene else null
		if dnc_off and "freeze_daytime" in dnc_off:
			dnc_off.set("freeze_daytime", false)
			
		if is_instance_valid(_heli_ui_canvas):
			_heli_ui_canvas.queue_free()
			_heli_ui_canvas = null
			_heli_ui_bg = null
			_heli_ui_label = null
			
		# Despawn all dummy turrets
		for node in get_tree().get_nodes_in_group("dummy_turrets"):
			if is_instance_valid(node):
				node.queue_free()
		if is_instance_valid(_heli_test_arena):
			_heli_test_arena.queue_free()
		_heli_test_arena = null
		var carrier_off := get_parent() as Node3D
		if is_instance_valid(carrier_off):
			if _heli_test_has_carrier_original_transform:
				carrier_off.global_transform = _heli_test_carrier_original_transform
			if carrier_off.has_method("set_heli_test_stationary"):
				carrier_off.call("set_heli_test_stationary", false)
		_heli_test_has_carrier_original_transform = false
				
		return

	_active_test_scenario = TestScenario.HELI_AIMING
	# Disable other test modes
	if _landing_test_active:
		_landing_test_active = false
		for ac in _landing_test_aircraft:
			if is_instance_valid(ac):
				ac.queue_free()
		_landing_test_aircraft.clear()
	FrameProfiler.set_enabled(true, "heli test")
	_set_heli_test_friendly_ops_suspended(true)
	_disable_enemies_for_heli_test()

	# Start from a clean population. The range spawns eight standardized test helicopters
	# directly into the air after the flat arena and target ring are ready.
	var seen: Array[RigidBody3D] = []
	for group in ["aircraft", "ai_aircraft", "friendlies", "enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			if not (node is RigidBody3D):
				continue
			var ac := node as RigidBody3D
			if seen.has(ac):
				continue
			seen.append(ac)
			if ac == deck_aircraft:
				deck_aircraft = null
			ac.queue_free()

	# Clear any queued/stored fixed-wing aircraft so they don't pop out of the hangar
	stored_aircraft.clear()
	_pending_store_aircraft = null
	_landing_clearance_aircraft = null
	_landing_clearance_queue.clear()
	current_state = DeckState.IDLE

	# Wipe helicopter logs so this test session starts clean, including retrieved-name variants.
	var user_dir := DirAccess.open("user://")
	if user_dir:
		user_dir.list_dir_begin()
		var filename := user_dir.get_next()
		while not filename.is_empty():
			if not user_dir.current_is_dir() and filename.begins_with("heli_crash_report") and filename.ends_with(".log"):
				user_dir.remove(filename)
			filename = user_dir.get_next()
		user_dir.list_dir_end()
	var aggregate_log := FileAccess.open("user://heli_crash_report.log", FileAccess.WRITE)
	if aggregate_log:
		aggregate_log.store_line("=" .repeat(72))
		aggregate_log.store_line("HELICOPTER TEST LOG")
		aggregate_log.store_line("Started: %s" % Time.get_datetime_string_from_system())
		aggregate_log.store_line("Includes compact flight summaries from Aircraft_9/Aircraft_10/Aircraft_11 helicopter pilots.")
		aggregate_log.store_line("Crash/fault reports include the last few seconds of HELI_AI output.")
		aggregate_log.store_line("=" .repeat(72))
		aggregate_log.store_line("")
		aggregate_log.close()
	_log_heli_test("mode ON")
	_log_heli_test("crash logs cleared: user://heli_crash_report.log")

	var poi_mgr := get_node_or_null("/root/POIManager")
	if poi_mgr and "reveals_disabled" in poi_mgr:
		poi_mgr.set("reveals_disabled", true)
	var dnc := get_tree().current_scene.find_child("DayNightCycle", true, false) if get_tree().current_scene else null
	if dnc and "freeze_daytime" in dnc:
		dnc.set("freeze_daytime", true)

	_heli_test_timer = HELI_TEST_INTERVAL_S
	_heli_test_spawn_index = 0
	_heli_test_dummy_retry_s = 0.0

	_reset_heli_test_stats()
	_ensure_physical_test_ui()
	_setup_heli_test_range()
	_ensure_dummy_turrets_for_test()
	call_deferred("_fill_heli_test_population")


func _setup_heli_test_range() -> void:
	if not _heli_test_active or is_instance_valid(_heli_test_arena):
		return
	var scene_root := get_tree().current_scene
	var carrier_node := get_parent() as Node3D
	if scene_root == null or carrier_node == null:
		push_warning("[HeliTest] Cannot create flat range without scene root and carrier")
		return

	_heli_test_carrier_original_transform = carrier_node.global_transform
	_heli_test_has_carrier_original_transform = true
	if carrier_node.has_method("set_heli_test_stationary"):
		carrier_node.call("set_heli_test_stationary", true)
	_heli_test_arena_center = Vector3(
		carrier_node.global_position.x,
		HELI_TEST_ARENA_SURFACE_Y,
		carrier_node.global_position.z
	)
	carrier_node.global_position = Vector3(
		_heli_test_arena_center.x,
		HELI_TEST_ARENA_SURFACE_Y + 40.0,
		_heli_test_arena_center.z
	)
	carrier_node.rotation = Vector3(0.0, carrier_node.rotation.y, 0.0)

	var arena_body := StaticBody3D.new()
	arena_body.name = "HeliTestFlatArena"
	arena_body.collision_layer = 1
	arena_body.collision_mask = 1
	scene_root.add_child(arena_body)
	arena_body.global_position = _heli_test_arena_center - Vector3.UP

	var box := BoxShape3D.new()
	box.size = Vector3(HELI_TEST_ARENA_SIZE_M, 2.0, HELI_TEST_ARENA_SIZE_M)
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = box
	arena_body.add_child(collider)

	var mesh_box := BoxMesh.new()
	mesh_box.size = box.size
	var material := ShaderMaterial.new()
	var range_shader := Shader.new()
	range_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(world_position.xz / 100.0);
	float checker = mod(cell.x + cell.y, 2.0);
	vec3 dark_green = vec3(0.055, 0.12, 0.075);
	vec3 light_green = vec3(0.20, 0.34, 0.20);
	vec3 base = mix(dark_green, light_green, checker);

	vec2 edge = abs(fract(world_position.xz / 100.0) - vec2(0.5));
	float minor_line = smoothstep(0.46, 0.495, max(edge.x, edge.y));
	vec2 major_edge = abs(fract(world_position.xz / 500.0) - vec2(0.5));
	float major_line = smoothstep(0.485, 0.499, max(major_edge.x, major_edge.y));
	ALBEDO = mix(base, vec3(0.65, 0.82, 0.42), minor_line * 0.55);
	ALBEDO = mix(ALBEDO, vec3(0.95, 0.80, 0.20), major_line);
	ROUGHNESS = 1.0;
}
"""
	material.shader = range_shader
	mesh_box.material = material
	var mesh := MeshInstance3D.new()
	mesh.name = "RangeSurface"
	mesh.mesh = mesh_box
	arena_body.add_child(mesh)

	_heli_test_arena = arena_body
	_log_heli_test("flat range ready center=%s surface_y=%.0f size=%.0fm" % [
		str(_heli_test_arena_center.snapped(Vector3.ONE)),
		HELI_TEST_ARENA_SURFACE_Y,
		HELI_TEST_ARENA_SIZE_M,
	])


func _get_heli_test_dummy_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("dummy_turrets"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1
	return count


func _ensure_dummy_turrets_for_test() -> void:
	if not _heli_test_active:
		return
	if not is_instance_valid(_heli_test_arena):
		_setup_heli_test_range()
	if not is_instance_valid(_heli_test_arena):
		return
	if _get_heli_test_dummy_count() >= HELI_TEST_DUMMY_COUNT:
		return
	_spawn_dummy_turrets_for_test()


func _spawn_dummy_turrets_for_test() -> void:
	var dummy_scene := load("res://Buildings/dummy_gun_emplacement.tscn") as PackedScene
	if not dummy_scene:
		push_error("[HeliTest] Failed to load dummy gun emplacement scene.")
		return

	var scene_root := get_tree().current_scene
	if not scene_root:
		return

	var existing_count := _get_heli_test_dummy_count()
	var target_count := HELI_TEST_DUMMY_COUNT
	var spawned := 0

	while existing_count + spawned < target_count:
		var ring_index := existing_count + spawned
		var angle := TAU * float(ring_index) / float(maxi(target_count, 1))
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var pos := _heli_test_arena_center + radial * HELI_TEST_TARGET_RING_RADIUS_M
		pos.y = HELI_TEST_ARENA_SURFACE_Y

		var dummy := dummy_scene.instantiate() as Node3D
		if not dummy:
			continue

		var name_index := existing_count + spawned
		var dummy_name := "DummyTurret_HeliTest_%d" % name_index
		while scene_root.get_node_or_null(NodePath(dummy_name)) != null:
			name_index += 1
			dummy_name = "DummyTurret_HeliTest_%d" % name_index
		dummy.name = dummy_name
		dummy.add_to_group("dummy_turrets")
		dummy.set_meta("heli_test_range_target", true)
		if "max_health" in dummy:
			dummy.set("max_health", HELI_TEST_DUMMY_HEALTH)

		scene_root.add_child(dummy)
		dummy.global_position = pos
		dummy.global_basis = Basis(Vector3.UP, angle + PI)

		spawned += 1

	_log_heli_test("spawned %d unlimited-health ring targets; total=%d/%d radius=%.0fm" % [
		spawned, existing_count + spawned, target_count, HELI_TEST_TARGET_RING_RADIUS_M,
	])



func _disable_enemies_for_heli_test() -> void:
	var enemy_ops := get_node_or_null("/root/EnemyOpsManager")
	if enemy_ops and enemy_ops.has_method("disable_for_heli_test"):
		enemy_ops.disable_for_heli_test()

	var base_manager := get_node_or_null("/root/EnemyBaseManager")
	if base_manager and base_manager.has_method("disable_for_heli_test"):
		base_manager.disable_for_heli_test()

	for spawner in get_tree().get_nodes_in_group("enemy_aircraft_spawner"):
		if spawner and spawner.has_method("disable_for_heli_test"):
			spawner.disable_for_heli_test()
	var scene_root := get_tree().current_scene
	if scene_root:
		var named_spawner := scene_root.find_child("EnemyAircraftSpawner", true, false)
		if named_spawner and named_spawner.has_method("disable_for_heli_test"):
			named_spawner.disable_for_heli_test()

	var cleaned := 0
	var seen: Dictionary = {}
	for group_name in ["enemies", "enemy_bases", "gun_emplacements", "ground_vehicles", "ai_aircraft"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node) or not is_instance_valid(node):
				continue
			var id := (node as Node).get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			if not _is_enemy_cleanup_node(node as Node):
				continue
			(node as Node).queue_free()
			cleaned += 1
	_log_heli_test("enemies disabled; cleaned %d live enemy nodes" % cleaned)


func _set_heli_test_friendly_ops_suspended(suspended: bool) -> void:
	for manager_path in ["/root/AirOpsManager", "/root/GroundOpsManager"]:
		var manager := get_node_or_null(manager_path)
		if manager == null:
			continue
		if suspended:
			if not _heli_test_suspended_manager_modes.has(manager_path):
				_heli_test_suspended_manager_modes[manager_path] = manager.process_mode
			manager.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			var previous_mode := int(_heli_test_suspended_manager_modes.get(
				manager_path, Node.PROCESS_MODE_INHERIT
			))
			manager.process_mode = previous_mode as Node.ProcessMode
	if not suspended:
		_heli_test_suspended_manager_modes.clear()
	_log_heli_test("friendly air/ground operations %s" % ("suspended" if suspended else "restored"))


func _is_enemy_cleanup_node(node: Node) -> bool:
	return node.is_in_group("enemies") \
			or node.is_in_group("enemy_bases") \
			or node.is_in_group("team_2")


func _get_live_heli_test_aircraft_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("aircraft"):
		if node is RigidBody3D and is_instance_valid(node) and not node.is_queued_for_deletion() \
				and bool(node.get_meta(HELI_TEST_COMBAT_MODE_META, false)):
			count += 1
	return count


func _fill_heli_test_population() -> void:
	if not _heli_test_active or not is_instance_valid(_heli_test_arena):
		return
	var live_count := _get_live_heli_test_aircraft_count()
	while live_count < HELI_TEST_MAX_COUNT:
		if not _spawn_heli_test_aircraft():
			break
		live_count += 1
	_log_heli_test("combat population=%d/%d" % [live_count, HELI_TEST_MAX_COUNT])


func _spawn_heli_test_aircraft() -> bool:
	var scene: PackedScene = aircraft_10_scene
	if not scene:
		scene = load("res://Aircraft/Aircraft_10.tscn")
	if not scene:
		push_warning("[HeliTest] Aircraft_10.tscn not found")
		return false
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return false

	var slot := _heli_test_spawn_index % HELI_TEST_MAX_COUNT
	var angle := TAU * float(slot) / float(HELI_TEST_MAX_COUNT)
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	var spawn_pos := _heli_test_arena_center + radial * HELI_TEST_HELICOPTER_RING_RADIUS_M
	spawn_pos.y = HELI_TEST_ARENA_SURFACE_Y + HELI_TEST_HELICOPTER_AGL_M

	var aircraft := scene.instantiate() as RigidBody3D
	if not is_instance_valid(aircraft):
		return false
	_heli_test_spawn_index += 1
	aircraft.name = "Aircraft_10_%d" % _heli_test_spawn_index
	aircraft.set_meta(HELI_TEST_TYPE_META, "Aircraft_10")
	aircraft.set_meta(HELI_TEST_UNLIMITED_AMMO_META, true)
	aircraft.set_meta(HELI_TEST_COMBAT_MODE_META, true)
	aircraft.set_meta(HELI_TEST_FLAT_GROUND_Y_META, HELI_TEST_ARENA_SURFACE_Y)
	aircraft.set_meta(HELI_TEST_ARENA_CENTER_META, _heli_test_arena_center)
	aircraft.set_meta(HELI_TEST_ARENA_RADIUS_META, HELI_TEST_ARENA_SIZE_M * 0.5)
	# Livery normally receives this metadata from the carrier retrieval path. Direct
	# test spawning bypasses that path, so provide a complete deterministic palette.
	aircraft.set_meta("pilot_livery_colors", {
		"main_color": Color(0.18, 0.24, 0.30),
		"main_color_dark": Color(0.06, 0.08, 0.11),
		"helmet_color_1": Color(0.80, 0.80, 0.72),
		"helmet_color_2": Color(0.18, 0.23, 0.28),
	})
	aircraft.transform = Transform3D(Basis.looking_at(-radial, Vector3.UP), spawn_pos)
	aircraft.linear_velocity = radial * 8.0
	aircraft.angular_velocity = Vector3.ZERO
	scene_root.add_child(aircraft)
	aircraft.global_transform = Transform3D(Basis.looking_at(-radial, Vector3.UP), spawn_pos)
	aircraft.freeze = false
	aircraft.sleeping = false

	var ai_toggle := aircraft.find_child("AIToggle", true, false)
	if ai_toggle != null and ai_toggle.has_method("enable_ai"):
		ai_toggle.call("enable_ai")
	var pilot := aircraft.find_child("HelicopterPilot", true, false)
	if pilot != null:
		pilot.set("combat_tuning_enabled", true)
	if pilot != null and pilot.has_method("set_combat_hunt_mode"):
		pilot.call("set_combat_hunt_mode", true)
	record_heli_stat(aircraft, "spawned")
	_log_heli_test("spawned %s slot=%d pos=%s" % [
		aircraft.name,
		slot,
		str(spawn_pos.snapped(Vector3.ONE)),
	])
	return true


func _log_heli_test(message: String) -> void:
	var line := "[HeliTest] %s" % message
	print(line)


# Returns how far the aircraft origin sits above its lowest gear contact point.
# Add this to any Y placement so gear rests on the surface rather than clipping through it.
# Falls back to 0.2 if no "gear_ground_point" group nodes are found on the aircraft.
func _get_gear_ground_offset(aircraft: RigidBody3D) -> float:
	var lowest_y: float = INF
	for child in aircraft.find_children("*", "Node3D", true, false):
		var n := child as Node3D
		if n.is_in_group("gear_ground_point"):
			# Convert to aircraft-local space to get the Y offset from the body origin
			var local_y: float = aircraft.to_local(n.global_position).y
			lowest_y = minf(lowest_y, local_y)
	if lowest_y == INF or lowest_y >= 0.0:
		return 0.2
	return -lowest_y
