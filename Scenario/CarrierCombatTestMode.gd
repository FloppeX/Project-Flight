extends Node3D

## Carrier combat observation with named reusable profiles. The default continuous
## intercept range uses real hangar launches, bounded rail targets, and automatic
## replacement. Isolated ground attack and the older integrated sequence share the
## same deterministic carrier/terrain setup.

const FRIENDLY_SCENE_PATH := "res://Aircraft/Aircraft_5.tscn"
const FRIENDLY_ATTACK_HELICOPTER_PATH := "res://Aircraft/Aircraft_10.tscn"
const ENEMY_SCENE: PackedScene = preload("res://Aircraft/Aircraft_4.tscn")
const ENEMY_FIGHTER_SCENE: PackedScene = preload("res://Aircraft/Aircraft_3.tscn")
const AirTaskModel: Script = preload("res://AI/AirTask.gd")
const OpsOrderModel: Script = preload("res://Operations/OpsOrder.gd")
const DUMMY_TURRET_SCENE: PackedScene = preload("res://Buildings/dummy_gun_emplacement.tscn")
const ACTIVE_TURRET_SCENE: PackedScene = preload("res://Buildings/gun_emplacement.tscn")
const ACTIVE_TURRET_10MM_WEAPON_SCENE: PackedScene = preload("res://Weapons/Turrets/bullet_weapon.tscn")
const ENEMY_TRUCK_SCENE: PackedScene = preload("res://GroundVehicle/GroundVehicle.tscn")
const ENEMY_BUGGY_SCENE: PackedScene = preload("res://GroundVehicle/vehicle_enemy_buggy.tscn")
const ENEMY_PICKUP_SCENE: PackedScene = preload("res://GroundVehicle/vehicle_enemy_pickup.tscn")
const REPORT_PATH := "user://carrier_combat_test_report.log"
const BATCH_REPORT_PREFIX := "user://carrier_combat_test_"
const MIXED_LOADOUT_PROFILE := "combat_test"
const INTERCEPT_LOADOUT_PROFILE := "cap"
const GUN_ONLY_LOADOUT_PROFILE := "gun_only"
const FULL_CYCLE_LOADOUT_PROFILE := "random_ground_strike"
const FULL_CYCLE_ROCKET_LOADOUT_PROFILE := "rocket_strike"
const FULL_CYCLE_BOMB_LOADOUT_PROFILE := "bomb_strike"
const SUMMARY_INTERVAL_S := 2.0
const ROLLING_SUMMARY_INTERVAL_S := 10.0
const PROFILE_CONTINUOUS_INTERCEPT := "continuous_intercept"
const PROFILE_ISOLATED_GROUND_ATTACK := "isolated_ground_attack"
const PROFILE_INTEGRATED := "integrated"
const PROFILE_FULL_CYCLE := "full_cycle"
const PROFILE_ROLLING_RECOVERY := "rolling_recovery"
const PROFILE_MIXED_RECOVERY := "mixed_recovery"
const PROFILE_DESERT_RECOVERY := "desert_recovery"
const PROFILE_ROLE_STRESS := "role_stress"
const PROJECT_ROCKET_SPECIALIST_PATH := "res://Scenario/airplane_test_best_rocket_genome.json"
const DESERT_RECOVERY_MODEL_ROSTER: PackedStringArray = [
	"Aircraft_1", "Aircraft_2", "Aircraft_5", "Aircraft_7",
	"Aircraft_8", "Aircraft_5", "Aircraft_1", "Aircraft_7",
]
const DESERT_RECOVERY_STAGE_KEYS: PackedStringArray = [
	"launch_complete",
	"outbound_complete",
	"rtb_started",
	"recovery_route",
	"pre_landing",
	"final_handoff",
	"confirmed_landing",
]

enum Stage { SETUP, GROUND_STRIKE, AIR_COMBAT, RECOVERY, ROLLING, COMPLETE }

# Launch/climb consumes roughly the first 1.7 km from the carrier in this test.
# Keep the target far enough beyond that point for the turn-radius-derived setup
# and aiming lane to exist before the aircraft reaches the target area.
@export var ground_target_range_from_carrier_m: float = 3200.0
@export var ground_target_spacing_m: float = 75.0
@export var ground_target_site_max_rise_from_carrier_m: float = 30.0
@export var ground_target_site_max_height_span_m: float = 35.0
@export var ground_target_attack_corridor_forward_m: float = 1700.0
@export var ground_target_attack_corridor_half_width_m: float = 180.0
@export var ground_target_attack_corridor_max_rise_m: float = 40.0
@export var ground_target_attack_corridor_samples: int = 22
@export var ground_target_wave_min_relocation_m: float = 600.0
@export var full_cycle_ground_vehicle_range_m: float = 5000.0
@export var full_cycle_ground_vehicle_spacing_m: float = 38.0
@export var full_cycle_ground_vehicle_attack_radius_m: float = 500.0
@export_range(0.0, 1.0, 0.05) var full_cycle_ground_vehicle_air_aim_multiplier: float = 0.55
@export var full_cycle_ground_vehicle_air_extra_spread_m: float = 12.0
@export var full_cycle_skip_enemy_air: bool = true
@export_enum("Bomb", "Rocket Pod", "Guns", "Rotate") var isolated_ground_weapon_focus: String = "Rocket Pod"
@export var enemy_range_from_carrier_m: float = 4000.0
@export var full_cycle_enemy_range_from_carrier_m: float = 6000.0
@export var full_cycle_carrier_initial_patrol_leg_m: float = 5000.0
@export_range(500.0, 600.0, 5.0) var enemy_altitude_agl_m: float = 550.0
@export var enemy_initial_speed_mps: float = 80.0
@export var enemy_pair_spacing_m: float = 300.0
@export var enemy_path_past_carrier_m: float = 2000.0
@export var enemy_return_turn_radius_m: float = 900.0
@export var enemy_rail_vertical_speed_limit_mps: float = 20.0
@export var enemy_hold_spawn_world_altitude: bool = true
@export var enemy_path_sample_spacing_m: float = 750.0
@export var ground_strike_observation_timeout_s: float = 300.0
@export var air_combat_timeout_s: float = 300.0
# Recovery orders can be issued while a survivor is still 4-6 km away on the
# terrain route.  Allow that transit plus multiple safe go-arounds/replans before
# the per-aircraft test budget expires; this is an observation limit, not pilot
# guidance or a gameplay shortcut.  The outer process watchdog still catches a
# genuinely non-terminating run.
@export var recovery_timeout_s: float = 900.0
@export var initial_launch_watchdog_s: float = 90.0
@export var ground_assignment_min_agl_m: float = 300.0
@export var keep_carrier_at_verified_pose: bool = true
@export_enum("continuous_intercept", "isolated_ground_attack", "integrated", "full_cycle", "rolling_recovery", "mixed_recovery", "desert_recovery", "role_stress") var test_profile: String = PROFILE_CONTINUOUS_INTERCEPT
@export var continuous_intercept_mode: bool = true
@export_range(1, 8, 1) var continuous_friendly_count: int = 2
@export_range(1, 8, 1) var continuous_enemy_count: int = 2
@export_group("Rolling Recovery")
@export_range(1, 8, 1) var rolling_active_aircraft_max: int = 5
@export var rolling_outbound_min_m: float = 4000.0
@export var rolling_outbound_max_m: float = 6000.0
@export var rolling_outbound_altitude_agl_m: float = 520.0
@export var rolling_outbound_min_route_agl_m: float = 350.0
@export var rolling_outbound_capture_radius_m: float = 300.0
@export var rolling_outbound_speed_mps: float = 100.0
@export_range(0, 1000, 1) var rolling_target_traps: int = 10
@export var rolling_random_seed: int = 20260801
@export var rolling_finite_cohort: bool = false
@export_group("Desert Recovery")
@export_range(1, 8, 1) var desert_recovery_active_cap: int = 6
## Keep refilling the active pool until several complete rotations have been
## observed. Set to 0 from the command line for an intentionally unlimited run.
@export_range(0, 1000, 1) var desert_recovery_target_traps: int = 24
@export var desert_recovery_open_radius_m: float = 900.0
@export var desert_recovery_max_relief_m: float = 30.0
## PRE_LANDING starts about 2.8 km behind touchdown. Keep the carrier bubble
## modest, then validate this longer strip along each candidate landing heading.
@export var desert_recovery_final_corridor_length_m: float = 3200.0
@export var desert_recovery_final_corridor_half_width_m: float = 350.0
@export var desert_recovery_final_corridor_max_relief_m: float = 80.0
@export var desert_recovery_initial_launch_timeout_s: float = 240.0
@export var desert_recovery_outbound_distance_m: float = 10000.0
@export_range(0.1, 0.9, 0.05) var desert_recovery_recall_arm_fraction: float = 0.5
@export var desert_recovery_recall_delay_min_s: float = 5.0
@export var desert_recovery_recall_delay_max_s: float = 35.0
## Test-only diagnosis: let the final controller receive a dirty approach after
## logging the normal handoff-gate failures. Final capture, wire and confirmed-
## landing gates remain unchanged, so a bad attempt still fails noisily.
@export var desert_recovery_diagnostic_final_attempt: bool = true
@export_group("Mixed Recovery")
@export_range(1, 3, 1) var mixed_helicopter_count: int = 2
@export_range(1, 3, 1) var mixed_fixed_wing_count: int = 2
@export_group("Role Stress")
@export var role_stress_patrol_radius_m: float = 1800.0
@export var role_stress_patrol_altitude_agl_m: float = 650.0
@export var role_stress_enemy_fighter_range_m: float = 4500.0
@export var role_stress_timeout_s: float = 1500.0
@export_range(0.0, 1.0, 0.05) var role_stress_ground_vehicle_air_aim_multiplier: float = 0.25
@export var role_stress_ground_vehicle_air_extra_spread_m: float = 24.0

var _play_area_center := Vector3.ZERO
var _carrier: Node3D = null
var _terrain: Node = null
var _fdm: Node = null
var _stage: Stage = Stage.SETUP
var _stage_started_s: float = 0.0
var _elapsed_s: float = 0.0
var _summary_s: float = 0.0
var _poll_s: float = 0.0
var _friendly_launches: int = 0
var _friendly_launch_requests_outstanding: int = 0
var _enemy_spawn_serial: int = 0
var _friendly_losses: int = 0
var _enemy_kills: int = 0
var _continuous_force_check_s: float = 0.0
var _reserve_aircraft_serial: int = 0
var _ground_targets: Array[Node3D] = []
var _ground_target_platoon: GroundVehiclePlatoon = null
var _ground_targets_destroyed: int = 0
var _ground_wave_index: int = 0
var _ground_wave_destroyed: int = 0
var _last_ground_target_center: Vector3 = Vector3.INF
var _aircraft_records: Dictionary = {} # id -> runtime state dictionary
var _enemy_rail_tracks: Dictionary = {} # aircraft id -> kinematic gunnery-target track
var _weapon_ammo: Dictionary = {}      # weapon instance id -> last ammo
var _gun_misses_since_log: Dictionary = {}
var _recovery_requested: Dictionary = {}
var _caught_aircraft: Dictionary = {}
var _rocket_specialist_genome: Dictionary = {}
var _rocket_specialist_loaded: bool = false
var _started: bool = false
var _initial_launch_watchdog_fired: bool = false
var _carrier_resume_route_offset := Vector3.ZERO
var _carrier_held_for_launches: bool = false
var _carrier_resume_pending: bool = false
var _carrier_held_for_recovery: bool = false
var _carrier_recovery_hold_wait_logged: bool = false
var _recovery_orders_dispatched: bool = false
var _isolated_ground_attack_mode: bool = false
var _full_cycle_mode: bool = false
var _rolling_recovery_mode: bool = false
var _mixed_recovery_mode: bool = false
var _desert_recovery_mode: bool = false
var _role_stress_mode: bool = false
var _weapon_focus_override_requested: bool = false
var _rolling_rng := RandomNumberGenerator.new()
var _rolling_traps: int = 0
var _rolling_losses: int = 0
var _rolling_last_queue_signature: String = ""
var _rolling_last_refill_log_s: float = -100.0
var _rolling_max_queue_depth: int = 0
var _rolling_max_holding_aircraft: int = 0
var _report_path: String = REPORT_PATH
var _test_seed: int = -1
var _test_run_id: String = ""
var _quit_on_test_complete: bool = false
var _completion_handled: bool = false
var _friendly_destroyed_count: int = 0
var _friendly_crash_count: int = 0
var _mixed_helicopter_launches: int = 0
var _mixed_fixed_wing_launches: int = 0
var _mixed_helicopters_requested: bool = false
var _mixed_fixed_wings_requested: bool = false
var _role_stress_helicopter_launches: int = 0
var _role_stress_patrol_launches: int = 0
var _role_stress_helicopters_requested: bool = false
var _role_stress_patrol_requested: bool = false
var _role_stress_enemy_fighters_spawned: bool = false
var _role_stress_recovery_started: bool = false
var _role_stress_role_violations: int = 0
var _desert_recovery_stage_counts: Dictionary = {}
var _completion_reason: String = ""


func configure(play_area_center: Vector3) -> void:
	_play_area_center = play_area_center


func set_test_profile(profile: String) -> void:
	if profile not in [
		PROFILE_CONTINUOUS_INTERCEPT,
		PROFILE_ISOLATED_GROUND_ATTACK,
		PROFILE_INTEGRATED,
		PROFILE_FULL_CYCLE,
		PROFILE_ROLLING_RECOVERY,
		PROFILE_MIXED_RECOVERY,
		PROFILE_DESERT_RECOVERY,
		PROFILE_ROLE_STRESS,
	]:
		push_warning("[CarrierCombatTest] Unknown profile '%s'; using %s" % [profile, PROFILE_CONTINUOUS_INTERCEPT])
		test_profile = PROFILE_CONTINUOUS_INTERCEPT
	else:
		test_profile = profile
	_sync_test_profile_flags()


func set_isolated_ground_weapon_focus(weapon_focus: String) -> void:
	if weapon_focus.is_empty():
		return
	if weapon_focus not in ["Bomb", "Rocket Pod", "Guns", "Rotate"]:
		push_warning("[CarrierCombatTest] Unknown isolated ground weapon focus '%s'; keeping %s" % [
			weapon_focus,
			isolated_ground_weapon_focus,
		])
		return
	isolated_ground_weapon_focus = weapon_focus
	_weapon_focus_override_requested = true


func _sync_test_profile_flags() -> void:
	continuous_intercept_mode = test_profile == PROFILE_CONTINUOUS_INTERCEPT
	_isolated_ground_attack_mode = test_profile == PROFILE_ISOLATED_GROUND_ATTACK
	_role_stress_mode = test_profile == PROFILE_ROLE_STRESS
	_full_cycle_mode = test_profile in [PROFILE_FULL_CYCLE, PROFILE_ROLE_STRESS]
	_mixed_recovery_mode = test_profile == PROFILE_MIXED_RECOVERY
	_desert_recovery_mode = test_profile == PROFILE_DESERT_RECOVERY
	_rolling_recovery_mode = test_profile in [
		PROFILE_ROLLING_RECOVERY,
		PROFILE_MIXED_RECOVERY,
		PROFILE_DESERT_RECOVERY,
	]
	if _mixed_recovery_mode:
		rolling_finite_cohort = true
		rolling_active_aircraft_max = mixed_helicopter_count + mixed_fixed_wing_count
		rolling_target_traps = rolling_active_aircraft_max
	elif _desert_recovery_mode:
		desert_recovery_active_cap = clampi(desert_recovery_active_cap, 1, 8)
		rolling_active_aircraft_max = desert_recovery_active_cap
		rolling_target_traps = maxi(desert_recovery_target_traps, 0)
		rolling_finite_cohort = false
		rolling_outbound_min_m = maxf(desert_recovery_outbound_distance_m, 1000.0)
		rolling_outbound_max_m = rolling_outbound_min_m
		rolling_outbound_altitude_agl_m = 500.0
	# Existing observation profiles deliberately keep their verified static pose.
	# The end-to-end mission explicitly tests launch, combat and recovery from a
	# carrier that resumes its patrol after the second catapult shot.
	if _full_cycle_mode:
		keep_carrier_at_verified_pose = false


func _ready() -> void:
	_sync_test_profile_flags()
	_configure_batch_run_from_cli()
	# Every profile below replaces the ordinary random carrier start with a
	# deterministic, terrain-validated test pose. Freeze that random patrol before
	# NavGraph becomes ready so its expensive route search cannot delay the harness.
	# LandCarrier will still signal initial placement once the grid is ready, after
	# which _setup_scenario() installs the validated pose and later resumes movement.
	var startup_carrier := get_tree().get_first_node_in_group("carrier")
	if is_instance_valid(startup_carrier) and startup_carrier.has_method("set_heli_test_stationary"):
		startup_carrier.call("set_heli_test_stationary", true)
	if _rolling_recovery_mode and OS.get_cmdline_user_args().has("--rolling-finite-cohort"):
		rolling_finite_cohort = true
		rolling_target_traps = rolling_active_aircraft_max
	var report := FileAccess.open(_report_path, FileAccess.WRITE)
	if report != null:
		report.store_line("Carrier combat test report")
		if not _test_run_id.is_empty():
			report.store_line("run_id=%s seed=%d" % [_test_run_id, _test_seed])
		report.close()
	if _role_stress_mode:
		_log("START requested: role stress; AirOps launches 2x Aircraft_10 for ground attack and 2x gun-only Aircraft_5 for CAP; first vehicle kill triggers 2x gun-only Aircraft_3; all friendlies recover after both threats are eliminated")
	elif continuous_intercept_mode:
		_log("START requested: continuous carrier intercept; %dx Aircraft_5 gun fighters; %dx replaceable kinematic-rail Aircraft_4 targets at %.0fm AGL" % [
			continuous_friendly_count, continuous_enemy_count, enemy_altitude_agl_m,
		])
	elif _isolated_ground_attack_mode:
		_log("START requested: isolated ground attack; repeating %s against waves of 4 non-firing ground targets; 2x Aircraft_5 strike; unlimited ammunition; no phase timeout, enemy aircraft, or recovery phase" % _isolated_ground_weapon_profile_label())
	elif _full_cycle_mode:
		if full_cycle_skip_enemy_air:
			_log("START requested: strike-to-recovery cycle; moving carrier; 4-vehicle enemy platoon (truck/buggy/pickup) advancing from 5000m; 2x Aircraft_5 independently randomized to 2x finite rocket canisters + gun or 2x finite bomb racks + gun; survivors recover immediately after the vehicles are destroyed; enemy air skipped")
		else:
			_log("START requested: full cycle; moving carrier; 4-vehicle enemy platoon (truck/buggy/pickup) advancing from 5000m; 2x Aircraft_5 independently randomized to 2x finite rocket canisters + gun or 2x finite bomb racks + gun; then 2x live Aircraft_4 bombers at 6000m; survivors recover")
	elif _desert_recovery_mode:
		_log("START requested: dedicated desert land-carrier recovery; models=%s active_cap=%d (expandable_to=8) outbound=%.0f-%.0fm; autonomous catapult launch, controlled transit, recall, RTB route, strict final handoff, wire catch, and hangar recovery" % [
			", ".join(_desert_recovery_models_for_cap()),
			rolling_active_aircraft_max,
			rolling_outbound_min_m,
			rolling_outbound_max_m,
		])
	elif _rolling_recovery_mode:
		var recovery_test_name := "mixed helicopter/fixed-wing recovery" if _mixed_recovery_mode else "rolling recovery"
		_log("START requested: %s; max_active=%d outbound=%.0f-%.0fm target_traps=%s seed=%d mode=%s; real hangar launch, shared FIFO landing clearance, recovery hold, touchdown/arrest, tractor, hangar%s" % [
			recovery_test_name,
			rolling_active_aircraft_max,
			rolling_outbound_min_m,
			rolling_outbound_max_m,
			str(rolling_target_traps) if rolling_target_traps > 0 else "unlimited",
			rolling_random_seed,
			"finite_cohort" if rolling_finite_cohort else "rolling_refill",
			"" if rolling_finite_cohort else ", and relaunch",
		])
	else:
		_log("START requested: carrier + 4 non-firing enemy turrets; 2x Aircraft_5 strike; 2x kinematic-rail Aircraft_4 gunnery targets inbound at 550m AGL; survivors recover")
	_suppress_normal_ops()
	_clear_unrelated_units()
	call_deferred("_setup_scenario")


func _configure_batch_run_from_cli() -> void:
	var seed_text := _get_cmdline_option("--test-seed=")
	if seed_text.is_valid_int():
		_test_seed = int(seed_text)
		seed(_test_seed)
	var rolling_active_text := _get_cmdline_option("--rolling-active=")
	if rolling_active_text.is_valid_int():
		rolling_active_aircraft_max = clampi(
			int(rolling_active_text),
			1,
			8
		)
		if _desert_recovery_mode:
			desert_recovery_active_cap = rolling_active_aircraft_max
	var rolling_target_text := _get_cmdline_option("--rolling-target-traps=")
	if rolling_target_text.is_valid_int():
		rolling_target_traps = clampi(int(rolling_target_text), 0, 1000)
		if _desert_recovery_mode:
			desert_recovery_target_traps = rolling_target_traps
	_test_run_id = _sanitize_run_id(_get_cmdline_option("--test-run-id="))
	_quit_on_test_complete = OS.get_cmdline_user_args().has("--quit-on-test-complete")
	if OS.get_cmdline_user_args().has("--include-enemy-air"):
		full_cycle_skip_enemy_air = false
	elif OS.get_cmdline_user_args().has("--skip-enemy-air"):
		full_cycle_skip_enemy_air = true
	if not _test_run_id.is_empty():
		_report_path = BATCH_REPORT_PREFIX + _test_run_id + ".log"


func _get_cmdline_option(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


func _sanitize_run_id(value: String) -> String:
	var safe := ""
	for character in value:
		if character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			safe += character
	return safe.left(80)


func _setup_scenario() -> void:
	# Let queued deletions finish and allow the carrier/deck manager to complete _ready().
	await get_tree().process_frame
	await get_tree().process_frame
	_carrier = get_tree().get_first_node_in_group("carrier") as Node3D
	_terrain = get_tree().get_first_node_in_group("terrain_provider")
	_fdm = get_tree().get_first_node_in_group("flight_deck_manager")
	if not is_instance_valid(_carrier) or not is_instance_valid(_fdm):
		_log("ERROR setup failed: carrier=%s flight_deck_manager=%s" % [str(is_instance_valid(_carrier)), str(is_instance_valid(_fdm))])
		return
	# Ordinary scenarios now require player-issued carrier routes. The full-cycle
	# harness deliberately keeps the legacy continuation after its contained test leg.
	if "automatic_patrol_enabled" in _carrier:
		_carrier.set("automatic_patrol_enabled", _full_cycle_mode)
	# The carrier resolves its safe terrain start asynchronously and then relocates from
	# its authored origin. Launching before this signal leaves root-level aircraft/targets
	# behind when the carrier makes that initial move.
	if _carrier.has_method("is_initial_placement_complete") \
			and not bool(_carrier.call("is_initial_placement_complete")):
		_log("WAIT carrier initial route placement")
		await _carrier.initial_placement_completed
		_log("READY carrier initial placement pos=%s" % _fmt(_carrier.global_position))
	await get_tree().process_frame
	_clear_unrelated_units()
	await get_tree().process_frame
	_suppress_carrier_defenses()
	if not _hold_carrier_for_launches():
		_log("ERROR setup failed: no terrain-safe carrier launch/recovery pose found")
		return
	# The contained profiles can move the already-instantiated carrier many
	# kilometres in one assignment. Give top-level elevator physics bodies and
	# cached catapult transforms two physics ticks to adopt the new carrier pose
	# before any aircraft is spawned for retrieval.
	for _settle_frame in range(2):
		await get_tree().physics_frame
		await get_tree().process_frame
	_connect_arresting_cables()
	if _role_stress_mode:
		# Keep the platoon live and dangerous, but make this role/recovery stress test
		# resistant to a lucky long-range gunner hit ending a helicopter on ingress.
		# The ordinary full-cycle profile retains its normal anti-air settings.
		full_cycle_ground_vehicle_air_aim_multiplier = role_stress_ground_vehicle_air_aim_multiplier
		full_cycle_ground_vehicle_air_extra_spread_m = role_stress_ground_vehicle_air_extra_spread_m
		_spawn_ground_targets()
		if _ground_targets.size() != 4:
			_log("ERROR role stress setup failed: spawned %d/4 ground vehicles" % _ground_targets.size())
			return
		_ensure_role_stress_hangar_stock()
		_stage = Stage.GROUND_STRIKE
		_stage_started_s = _elapsed_s
		_started = true
		_request_role_stress_launches()
		_log("PHASE role stress active; helicopters=ground_attack fixed_wing=CAP enemy_air_trigger=first_ground_kill")
		return
	if _rolling_recovery_mode:
		_rolling_rng.seed = rolling_random_seed
		_stage = Stage.ROLLING
		_stage_started_s = _elapsed_s
		_started = true
		if _desert_recovery_mode:
			_initialize_desert_recovery_stage_counts()
			if not _ensure_desert_recovery_hangar_stock():
				_stage = Stage.COMPLETE
				_completion_reason = "desert_hangar_preparation_failed"
				_log("FAILED desert recovery: compatible hangar stock could not be prepared")
				return
			_fdm.set("prioritize_ai_launch_refill_over_waiting_recovery", true)
			_request_desert_recovery_launches()
			_log("PHASE desert recovery active; fixed-wing=%d models=%s combat=disabled carrier=held site=open_level_desert" % [
				rolling_active_aircraft_max,
				", ".join(_desert_recovery_models_for_cap()),
			])
		elif _mixed_recovery_mode:
			_request_mixed_launches()
			_log("PHASE mixed recovery active; %d helicopters + %d fixed-wing aircraft; combat disabled, carrier held at verified launch/recovery pose" % [
				mixed_helicopter_count,
				mixed_fixed_wing_count,
			])
		else:
			_request_recovery_test_launches()
			_log("PHASE rolling recovery active; combat disabled, carrier held at verified launch/recovery pose")
		return
	if continuous_intercept_mode:
		_stage = Stage.AIR_COMBAT
		_stage_started_s = _elapsed_s
		_started = true
		_ensure_enemy_target_count()
		_ensure_friendly_force()
		_log("PHASE continuous intercept active; ground strike, recovery, and phase timeout disabled")
		return
	_spawn_ground_targets()
	if _ground_targets.size() != 4:
		_log("ERROR setup failed: spawned %d/4 ground targets" % _ground_targets.size())
		return
	var launch_loadout := FULL_CYCLE_LOADOUT_PROFILE if _full_cycle_mode else MIXED_LOADOUT_PROFILE
	if _full_cycle_mode and _weapon_focus_override_requested:
		if isolated_ground_weapon_focus == "Rocket Pod":
			launch_loadout = FULL_CYCLE_ROCKET_LOADOUT_PROFILE
		elif isolated_ground_weapon_focus == "Bomb":
			launch_loadout = FULL_CYCLE_BOMB_LOADOUT_PROFILE
	var queued: int = int(_fdm.call("queue_ai_flight", 2, self, launch_loadout))
	_log("LAUNCH_ORDER queued=%d aircraft_scene=%s loadout=%s" % [
		queued,
		FRIENDLY_SCENE_PATH,
		launch_loadout if _full_cycle_mode else "Bomb+Rocket+Gun",
	])
	if queued != 2:
		_log("ERROR expected two available Aircraft_5 hangar launches, got %d" % queued)
	_stage = Stage.GROUND_STRIKE
	_stage_started_s = _elapsed_s
	_started = true


func _suppress_normal_ops() -> void:
	for autoload_name in ["AirOpsManager", "EnemyOpsManager", "GroundOpsManager", "EnemyBaseManager", "POIManager"]:
		var manager: Node = get_node_or_null("/root/" + autoload_name)
		if manager != null:
			# This harness owns mission/combat tasking in every profile, but recovery
			# supervision is orthogonal and should remain active during the real combat
			# cycle as well as the isolated rolling test.
			if autoload_name == "AirOpsManager":
				manager.set("mission_tasking_enabled", false)
				manager.set_process(true)
				manager.set_physics_process(false)
				_log("SUPPRESSED AirOpsManager tasking; recovery supervision active")
				continue
			manager.set_process(false)
			manager.set_physics_process(false)
			_log("SUPPRESSED %s" % autoload_name)


func _suppress_carrier_defenses() -> void:
	# This scenario measures the strike aircraft. The carrier's autonomous 10 mm
	# turrets otherwise engage the nearby enemy ground targets and erase them before the
	# aircraft can finish a second pass.
	var pending: Array[Node] = [_carrier]
	var suppressed: int = 0
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if not (node is TurretController):
			continue
		var controller := node as TurretController
		controller.set_process(false)
		controller.set_physics_process(false)
		controller.current_target = null
		if controller.turret != null and is_instance_valid(controller.turret):
			controller.turret.set_target(null)
		if controller.weapon_instance != null and is_instance_valid(controller.weapon_instance) \
				and controller.weapon_instance.has_method("stop_firing"):
			controller.weapon_instance.stop_firing()
		suppressed += 1
	_log("SUPPRESSED carrier defense turrets=%d" % suppressed)


func _clear_unrelated_units() -> void:
	var groups: Array[String] = [
		"aircraft", "ai_aircraft", "buildings", "enemy_bases", "ground_vehicles",
		"ground_vehicle_platoons", "gun_emplacements", "wind_turbines",
		"wind_turbine_proxies", "enemy_aircraft_spawner",
	]
	var seen: Dictionary = {}
	var removed: int = 0
	for group_name in groups:
		for node_variant in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node_variant):
				continue
			var node := node_variant as Node
			var id := node.get_instance_id()
			if seen.has(id) or node == _carrier:
				continue
			seen[id] = true
			node.queue_free()
			removed += 1
	_log("SCENE_CLEARED removed=%d unrelated unit/building nodes" % removed)


func _spawn_ground_targets() -> void:
	_ground_wave_index += 1
	_ground_wave_destroyed = 0
	_ground_targets.clear()
	_ground_target_platoon = null
	var carrier_right := _carrier.global_transform.basis.x
	carrier_right.y = 0.0
	if carrier_right.length_squared() < 0.001:
		carrier_right = Vector3.RIGHT
	carrier_right = carrier_right.normalized()
	var carrier_forward := _carrier.global_transform.basis.z
	carrier_forward.y = 0.0
	if carrier_forward.length_squared() < 0.001:
		carrier_forward = Vector3.FORWARD
	carrier_forward = carrier_forward.normalized()
	var offsets: Array[Vector2] = [
		Vector2(-0.5, -0.5), Vector2(0.5, -0.5),
		Vector2(-0.5, 0.5), Vector2(0.5, 0.5),
	]
	var preferred_bearing_deg: float = _ground_wave_preferred_bearing_deg(_ground_wave_index)
	var cluster_spacing_m: float = full_cycle_ground_vehicle_spacing_m if _full_cycle_mode else ground_target_spacing_m
	var cluster_range_m: float = full_cycle_ground_vehicle_range_m if _full_cycle_mode else ground_target_range_from_carrier_m
	var site: Dictionary = _find_moving_ground_platoon_site(
		carrier_forward,
		carrier_right,
		offsets,
		preferred_bearing_deg,
		cluster_spacing_m,
		cluster_range_m
	) if _full_cycle_mode else _find_ground_target_cluster_site(
		carrier_forward,
		carrier_right,
		offsets,
		preferred_bearing_deg,
		_last_ground_target_center,
		cluster_spacing_m,
		cluster_range_m,
		false
	)
	if site.is_empty() and is_finite(_last_ground_target_center.x):
		# Terrain legality wins if the fixed map happens not to offer a second clear
		# corridor at the requested separation, but make that fallback explicit.
		_log("GROUND_WAVE relocation fallback: no alternate legal site at least %.0fm from prior wave" % ground_target_wave_min_relocation_m)
		site = _find_moving_ground_platoon_site(
			carrier_forward,
			carrier_right,
			offsets,
			preferred_bearing_deg,
			cluster_spacing_m,
			cluster_range_m
		) if _full_cycle_mode else _find_ground_target_cluster_site(
			carrier_forward,
			carrier_right,
			offsets,
			preferred_bearing_deg,
			Vector3.INF,
			cluster_spacing_m,
			cluster_range_m,
			false
		)
	if site.is_empty():
		_log("ERROR no terrain-safe ground-target attack corridor found")
		return
	var cluster_center: Vector3 = site.get(
		"center",
		_carrier.global_position + (carrier_forward + carrier_right * 0.35).normalized() * cluster_range_m
	)
	_last_ground_target_center = cluster_center
	_log("GROUND_TARGET_SITE wave=%d preferred=%.0fdeg bearing=%.0fdeg range=%.0fm rise=%.0fm span=%.0fm corridor_rise=%.0fm" % [
		_ground_wave_index,
		preferred_bearing_deg,
		float(site.get("bearing_deg", 19.0)),
		_flat_distance(cluster_center, _carrier.global_position),
		float(site.get("rise_m", NAN)),
		float(site.get("span_m", NAN)),
		float(site.get("corridor_rise_m", NAN)),
	])
	if _full_cycle_mode:
		_spawn_full_cycle_ground_vehicle_platoon(cluster_center, carrier_forward, carrier_right, offsets)
		return
	for i in range(4):
		var target_scene := DUMMY_TURRET_SCENE
		var target := target_scene.instantiate() as Node3D
		if target == null:
			continue
		target.name = "CombatTest_Wave_%02d_DummyTurret_%d" % [
			_ground_wave_index,
			i + 1,
		]
		# One solid near-hit should remove a test target. These dummies exist to advance
		# the integrated strike -> dogfight -> recovery sequence, not to soak repeated
		# bombing passes while maneuvering changes are under observation.
		target.set("max_health", 100.0)
		target.set("team", 2)
		target.set("is_dummy", true)
		# The normal relevance optimization can hide and disable a distant emplacement.
		# Test targets must remain visible and collidable throughout the strike.
		target.set("inactive_when_no_targets", false)
		target.set("full_deactivation_when_no_targets", false)
		target.set_meta("suppress_enemy_ops_on_destroy", true)
		get_tree().current_scene.add_child(target)
		for turret_controller in target.find_children("*", "TurretController", true, false):
			if "air_target_aim_skill_multiplier" in turret_controller:
				turret_controller.set(
					"air_target_aim_skill_multiplier",
					full_cycle_ground_vehicle_air_aim_multiplier
				)
			if "air_target_extra_spread_m" in turret_controller:
				turret_controller.set(
					"air_target_extra_spread_m",
					maxf(full_cycle_ground_vehicle_air_extra_spread_m, 0.0)
				)
		var p := cluster_center \
				+ carrier_right * offsets[i].x * cluster_spacing_m \
				+ carrier_forward * offsets[i].y * cluster_spacing_m
		# _ground_height() reads the terrain node's exact analytical height. Do NOT follow this with
		# snap_collider_to_ground() -- that re-derives Y from TerrainNavGrid's baked, coarser grid
		# (40m/cell resolution per its own docs), which can disagree by a meter or more on sloped
		# ground and buried these turrets up to their tops. The height computed here is already the
		# accurate one.
		p.y = _ground_height(p)
		target.global_position = p
		if target.has_signal("damaged"):
			target.connect("damaged", Callable(self, "_on_ground_target_damaged").bind(target))
		if target.has_signal("destroyed"):
			target.connect("destroyed", Callable(self, "_on_ground_target_destroyed"), CONNECT_ONE_SHOT)
		_ground_targets.append(target)
		_log("SPAWN ground_target=%s type=%s pos=%s range_from_carrier=%.0fm hp=%.0f armed=%s weapon=%s" % [
			target.name,
			"dummy_turret",
			_fmt(p),
			_flat_distance(p, _carrier.global_position),
			float(target.get("max_health")) if "max_health" in target else -1.0,
			"false",
			"none",
		])


func _spawn_full_cycle_ground_vehicle_platoon(
	cluster_center: Vector3,
	carrier_forward: Vector3,
	carrier_right: Vector3,
	offsets: Array[Vector2]
) -> void:
	var platoon := GroundVehiclePlatoon.new()
	platoon.name = "CombatTest_EnemyVehiclePlatoon_%02d" % _ground_wave_index
	platoon.platoon_id = platoon.name
	platoon.team = 2
	platoon.global_position = cluster_center
	get_tree().current_scene.add_child(platoon)
	platoon.set_attack_node(_carrier, full_cycle_ground_vehicle_attack_radius_m)
	_ground_target_platoon = platoon

	var scenes: Array[PackedScene] = [
		ENEMY_TRUCK_SCENE,
		ENEMY_BUGGY_SCENE,
		ENEMY_PICKUP_SCENE,
	]
	var toward_carrier: Vector3 = _carrier.global_position - cluster_center
	toward_carrier.y = 0.0
	if toward_carrier.length_squared() <= 0.001:
		toward_carrier = -carrier_forward
	toward_carrier = toward_carrier.normalized()
	for i in range(4):
		var scene: PackedScene = scenes[randi() % scenes.size()]
		var target := scene.instantiate() as Node3D
		if target == null:
			continue
		var vehicle_type := "truck"
		if scene == ENEMY_BUGGY_SCENE:
			vehicle_type = "buggy"
		elif scene == ENEMY_PICKUP_SCENE:
			vehicle_type = "pickup"
		target.name = "CombatTest_Wave_%02d_%s_%d" % [
			_ground_wave_index,
			vehicle_type.capitalize(),
			i + 1,
		]
		target.set("team", 2)
		target.set_meta("suppress_enemy_ops_on_destroy", true)
		get_tree().current_scene.add_child(target)
		var configured_gunners: int = _configure_full_cycle_ground_vehicle_gunners(target)
		var p := cluster_center \
				+ carrier_right * offsets[i].x * full_cycle_ground_vehicle_spacing_m \
				+ carrier_forward * offsets[i].y * full_cycle_ground_vehicle_spacing_m
		p.y = _ground_height(p) + 2.0
		target.global_transform = Transform3D(_basis_from_forward(toward_carrier), p)
		if target.has_method("assign_platoon"):
			target.call("assign_platoon", platoon)
		if target.has_signal("damaged"):
			target.connect("damaged", Callable(self, "_on_ground_target_damaged").bind(target))
		if target.has_signal("destroyed"):
			target.connect("destroyed", Callable(self, "_on_ground_target_destroyed"), CONNECT_ONE_SHOT)
		_ground_targets.append(target)
		_log("SPAWN ground_target=%s type=%s pos=%s range_from_carrier=%.0fm hp=%.0f armed=true objective=attack_carrier platoon=%s gunners=%d air_aim_mult=%.2f air_spread=%.1fm" % [
			target.name,
			vehicle_type,
			_fmt(p),
			_flat_distance(p, _carrier.global_position),
			float(target.get("max_health")) if "max_health" in target else -1.0,
			platoon.name,
			configured_gunners,
			full_cycle_ground_vehicle_air_aim_multiplier,
			maxf(full_cycle_ground_vehicle_air_extra_spread_m, 0.0),
		])


func _configure_full_cycle_ground_vehicle_gunners(target: Node3D) -> int:
	# These penalties belong to this deliberately small, exposed test platoon.  The
	# spawn log previously advertised them without applying them: only the retired
	# static-turret branch configured its TurretControllers.  Keep the vehicle's
	# ordinary ground-target accuracy intact and weaken only its air solution.
	var configured_count: int = 0
	for turret_controller in target.find_children("*", "TurretController", true, false):
		if "air_target_aim_skill_multiplier" in turret_controller:
			turret_controller.set(
				"air_target_aim_skill_multiplier",
				clampf(full_cycle_ground_vehicle_air_aim_multiplier, 0.0, 1.0)
			)
		if "air_target_extra_spread_m" in turret_controller:
			turret_controller.set(
				"air_target_extra_spread_m",
				maxf(full_cycle_ground_vehicle_air_extra_spread_m, 0.0)
			)
		configured_count += 1
	return configured_count


func _find_moving_ground_platoon_site(
	carrier_forward: Vector3,
	carrier_right: Vector3,
	offsets: Array[Vector2],
	preferred_bearing_deg: float,
	cluster_spacing_m: float,
	cluster_range_m: float
) -> Dictionary:
	var bearings_deg: Array[float] = [
		preferred_bearing_deg,
		preferred_bearing_deg + 20.0,
		preferred_bearing_deg - 20.0,
		preferred_bearing_deg + 45.0,
		preferred_bearing_deg - 45.0,
		preferred_bearing_deg + 90.0,
		preferred_bearing_deg - 90.0,
		preferred_bearing_deg + 135.0,
		preferred_bearing_deg - 135.0,
		preferred_bearing_deg + 180.0,
	]
	var ranges_m: Array[float] = [
		cluster_range_m,
		cluster_range_m - 200.0,
		cluster_range_m + 200.0,
		cluster_range_m - 400.0,
		cluster_range_m + 400.0,
	]
	var best: Dictionary = {}
	var best_score: float = INF
	for bearing_deg in bearings_deg:
		var bearing_rad := deg_to_rad(bearing_deg)
		var direction := (carrier_forward * cos(bearing_rad) + carrier_right * sin(bearing_rad)).normalized()
		for candidate_range_m in ranges_m:
			var center := _carrier.global_position + direction * maxf(candidate_range_m, 500.0)
			if not _is_inside_tactical_map(center, 300.0):
				continue
			var min_h: float = INF
			var max_h: float = -INF
			var valid: bool = true
			for offset in offsets:
				var probe := center \
						+ carrier_right * offset.x * cluster_spacing_m \
						+ carrier_forward * offset.y * cluster_spacing_m
				var height_m: float = _ground_height(probe)
				if not is_finite(height_m):
					valid = false
					break
				min_h = minf(min_h, height_m)
				max_h = maxf(max_h, height_m)
			if not valid:
				continue
			var local_height_span_m: float = max_h - min_h
			if local_height_span_m > maxf(ground_target_site_max_height_span_m, 1.0):
				continue
			var ground_center := Vector3(center.x, (min_h + max_h) * 0.5, center.z)
			if NavGraph.is_ready() and not NavGraph.can_anchor(ground_center, 60.0, 220.0):
				continue
			var bearing_error_deg: float = absf(wrapf(bearing_deg - preferred_bearing_deg, -180.0, 180.0))
			var score: float = bearing_error_deg * 2.0 \
					+ absf(candidate_range_m - cluster_range_m) * 0.05 \
					+ local_height_span_m * 10.0
			if score < best_score:
				best_score = score
				best = {
					"center": ground_center,
					"bearing_deg": wrapf(bearing_deg, -180.0, 180.0),
					"rise_m": max_h - _ground_height(_carrier.global_position),
					"span_m": local_height_span_m,
					"corridor_rise_m": NAN,
				}
	return best


func _is_inside_tactical_map(world_pos: Vector3, margin_m: float = 0.0) -> bool:
	if not TerrainNavGrid.is_ready() or TerrainNavGrid._cols <= 1 or TerrainNavGrid._rows <= 1:
		return false
	var max_x: float = TerrainNavGrid._origin_x \
			+ float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var max_z: float = TerrainNavGrid._origin_z \
			+ float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	return world_pos.x >= TerrainNavGrid._origin_x + margin_m \
			and world_pos.x <= max_x - margin_m \
			and world_pos.z >= TerrainNavGrid._origin_z + margin_m \
			and world_pos.z <= max_z - margin_m


func _find_ground_target_cluster_site(
	carrier_forward: Vector3,
	carrier_right: Vector3,
	offsets: Array[Vector2],
	preferred_bearing_deg: float = NAN,
	avoid_center: Vector3 = Vector3.INF,
	cluster_spacing_m: float = -1.0,
	cluster_range_m: float = -1.0,
	require_ground_navigation: bool = false
) -> Dictionary:
	if cluster_spacing_m <= 0.0:
		cluster_spacing_m = ground_target_spacing_m
	if cluster_range_m <= 0.0:
		cluster_range_m = ground_target_range_from_carrier_m
	var carrier_ground: float = _ground_height(_carrier.global_position)
	var best: Dictionary = {}
	var best_score: float = INF
	var bearings_deg: Array[float] = [
		0.0, 5.0, -5.0, 10.0, -10.0, 15.0, -15.0, 20.0, -20.0,
		30.0, -30.0, 40.0, -40.0, 60.0, -60.0, 80.0, -80.0,
		100.0, -100.0, 120.0, -120.0, 140.0, -140.0, 160.0, -160.0, 180.0,
	]
	var ranges_m: Array[float] = [
		cluster_range_m,
		cluster_range_m + 200.0,
		cluster_range_m - 200.0,
		cluster_range_m + 400.0,
	]
	for bearing_deg in bearings_deg:
		var bearing_rad := deg_to_rad(bearing_deg)
		var direction := (carrier_forward * cos(bearing_rad) + carrier_right * sin(bearing_rad)).normalized()
		for candidate_range in ranges_m:
			var center := _carrier.global_position + direction * maxf(candidate_range, 500.0)
			if is_finite(avoid_center.x) \
					and _flat_distance(center, avoid_center) < maxf(ground_target_wave_min_relocation_m, 0.0):
				continue
			var min_h: float = INF
			var max_h: float = -INF
			var valid: bool = true
			for offset in offsets:
				var probe := center \
						+ carrier_right * offset.x * cluster_spacing_m \
						+ carrier_forward * offset.y * cluster_spacing_m
				var h: float = _ground_height(probe)
				if not is_finite(h):
					valid = false
					break
				min_h = minf(min_h, h)
				max_h = maxf(max_h, h)
			if not valid:
				continue
			var rise_m: float = max_h - carrier_ground
			var span_m: float = max_h - min_h
			if require_ground_navigation and NavGraph.is_ready():
				var ground_center := Vector3(center.x, (min_h + max_h) * 0.5, center.z)
				if not NavGraph.can_anchor(ground_center, 60.0, 220.0):
					continue
			if rise_m > maxf(ground_target_site_max_rise_from_carrier_m, 0.0) \
					or span_m > maxf(ground_target_site_max_height_span_m, 0.0):
				continue
			var corridor: Dictionary = _evaluate_ground_target_attack_corridor(center, direction)
			if not bool(corridor.get("clear", false)):
				continue
			var corridor_rise_m: float = float(corridor.get("max_rise_m", INF))
			var bearing_error_deg: float = absf(bearing_deg)
			if is_finite(preferred_bearing_deg):
				bearing_error_deg = absf(wrapf(bearing_deg - preferred_bearing_deg, -180.0, 180.0))
			var score: float = bearing_error_deg * 2.0 \
					+ absf(candidate_range - cluster_range_m) * 0.05 \
					+ maxf(rise_m, 0.0) * 4.0 \
					+ span_m * 10.0 \
					+ maxf(corridor_rise_m, 0.0) * 2.0
			if score < best_score:
				best_score = score
				center.y = (min_h + max_h) * 0.5
				best = {
					"center": center,
					"bearing_deg": bearing_deg,
					"rise_m": rise_m,
					"span_m": span_m,
					"corridor_rise_m": corridor_rise_m,
				}
	return best


func _ground_wave_preferred_bearing_deg(wave_index: int) -> float:
	# Deterministic variety keeps comparisons reproducible while forcing the pilots
	# to rebuild their attack geometry instead of orbiting one permanent site.
	var bearings: Array[float] = [0.0, 90.0, -90.0, 180.0, 45.0, -45.0, 135.0, -135.0]
	return bearings[posmod(maxi(wave_index, 1) - 1, bearings.size())]


func _ground_wave_weapon_type(_wave_index: int) -> String:
	return isolated_ground_weapon_focus


func _isolated_ground_weapon_rotation() -> PackedStringArray:
	return PackedStringArray(["Bomb", "Rocket Pod", "Guns"])


func _isolated_ground_weapon_profile_label() -> String:
	if isolated_ground_weapon_focus == "Rotate":
		return "per-pass Bomb -> Rocket Pod -> Guns rotation"
	return "%s-only passes" % isolated_ground_weapon_focus


func _evaluate_ground_target_attack_corridor(center: Vector3, direction: Vector3) -> Dictionary:
	var target_ground_m: float = _ground_height(center)
	if not is_finite(target_ground_m):
		return {"clear": false, "max_rise_m": INF}
	var flat_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	if flat_direction.length_squared() < 0.5:
		return {"clear": false, "max_rise_m": INF}
	var lateral_direction := Vector3(-flat_direction.z, 0.0, flat_direction.x)
	var target_distance_m: float = _flat_distance(_carrier.global_position, center)
	var corridor_length_m: float = target_distance_m + maxf(ground_target_attack_corridor_forward_m, 0.0)
	var half_width_m: float = maxf(ground_target_attack_corridor_half_width_m, 0.0)
	var max_rise_m: float = -INF
	var sample_count: int = maxi(ground_target_attack_corridor_samples, 4)
	for sample_index in range(1, sample_count + 1):
		var distance_m: float = lerpf(250.0, corridor_length_m, float(sample_index) / float(sample_count))
		for lateral_m in [-half_width_m, 0.0, half_width_m]:
			var probe: Vector3 = _carrier.global_position \
					+ flat_direction * distance_m \
					+ lateral_direction * lateral_m
			var height_m: float = _ground_height(probe)
			if not is_finite(height_m):
				return {"clear": false, "max_rise_m": INF}
			max_rise_m = maxf(max_rise_m, height_m - target_ground_m)
			if max_rise_m > maxf(ground_target_attack_corridor_max_rise_m, 0.0):
				return {"clear": false, "max_rise_m": max_rise_m}
	return {"clear": true, "max_rise_m": max_rise_m}


## Called by FlightDeckManager after each real catapult sequence completes.
func notify_aircraft_launched(pilot: Node) -> void:
	if pilot == null or not is_instance_valid(pilot):
		_log("ERROR deck launch callback had no valid pilot")
		return
	var craft_variant: Variant = pilot.get("aircraft")
	if not is_instance_valid(craft_variant) or not (craft_variant is RigidBody3D):
		_log("ERROR deck launch callback pilot had no valid aircraft")
		return
	var craft := craft_variant as RigidBody3D
	var is_helicopter := pilot is HelicopterPilot \
			or pilot.name == "HelicopterPilot" \
			or bool(craft.get_meta("is_helicopter", false))
	if _role_stress_mode and is_helicopter:
		_notify_role_stress_helicopter_launched(craft, pilot)
		return
	if _mixed_recovery_mode and is_helicopter:
		_notify_mixed_helicopter_launched(craft, pilot)
		return
	if continuous_intercept_mode or _rolling_recovery_mode or _role_stress_mode:
		_friendly_launch_requests_outstanding = maxi(_friendly_launch_requests_outstanding - 1, 0)
	_friendly_launches += 1
	if _role_stress_mode:
		_role_stress_patrol_launches += 1
	if _mixed_recovery_mode:
		_mixed_fixed_wing_launches += 1
	var desert_model := _desert_recovery_model_for_craft(craft) if _desert_recovery_mode else ""
	craft.name = ("RoleStress_CAP_%02d" % _role_stress_patrol_launches) if _role_stress_mode else (
		("DesertRecovery_%02d_%s" % [_friendly_launches, desert_model]) if _desert_recovery_mode else (
			("RecoveryCycle_%03d" if _rolling_recovery_mode else "Combat_Friendly_%d") % _friendly_launches
		)
	)
	craft.set_meta("carrier_combat_test", true)
	if _desert_recovery_mode:
		craft.set_meta(
			"recovery_diagnostic_force_final_handoff",
			desert_recovery_diagnostic_final_attempt
		)
		craft.set_meta("recovery_diagnostic_handoff", false)
	_configure_pilot(pilot, true)
	if _role_stress_mode:
		pilot.set("ground_attack_enabled", false)
		pilot.set("dogfight_enabled", true)
	_register_aircraft(craft, pilot, 1)
	_configure_weapon_logging(craft)
	_log("LAUNCHED %s via catapult pos=%s speed=%.1fm/s loadout=%s" % [
		craft.name, _fmt(craft.global_position), craft.linear_velocity.length(), _describe_loadout(craft),
	])
	# Do not replace LAUNCHING/CLIMBING with an attack state. The assignment is issued
	# from _poll_aircraft_events only after the normal climb reaches SEARCH.
	var id := craft.get_instance_id()
	var record: Dictionary = _aircraft_records[id]
	record["ground_assignment_index"] = _friendly_launches - 1
	record["ground_mission_assigned"] = false
	if _role_stress_mode:
		record["ops_domain"] = "fixed_wing"
		record["role"] = "CAP"
		record["role_ordered"] = false
	if _rolling_recovery_mode:
		record["ops_domain"] = "fixed_wing"
		record["rolling_status"] = "departing"
		record["rolling_outbound_point"] = Vector3.INF
		record["rolling_recovery_started_s"] = -1.0
		record["rolling_hold_started_s"] = -1.0
		record["rolling_clearance_s"] = -1.0
		record["rolling_queue_position"] = -2
		_aircraft_records[id] = record
		if _desert_recovery_mode:
			_record_desert_recovery_stage(id, "launch_complete", "model=%s" % desert_model)
	if _rolling_recovery_mode:
		_log("ROLLING_SLOT launched aircraft=%s active=%d pending=%d traps=%d/%s" % [
			craft.name,
			_rolling_active_aircraft_count(),
			_friendly_launch_requests_outstanding,
			_rolling_traps,
			str(rolling_target_traps) if rolling_target_traps > 0 else "unlimited",
		])
		call_deferred("_request_recovery_test_launches")
		return
	if continuous_intercept_mode:
		_log("INTERCEPT_REPLACEMENT ready aircraft=%s live=%d requested=%d" % [
			craft.name,
			_live_aircraft_for_team(1).size(),
			_friendly_launch_requests_outstanding,
		])
		# Preserve LAUNCHING/CLIMBING. _poll_aircraft_events assigns a rail target
		# after the aircraft is in a state that can safely become DOGFIGHT.
		call_deferred("_ensure_friendly_force")
	if _role_stress_mode:
		_log("ROLE_LAUNCHED aircraft=%s model=Aircraft_5 role=CAP loadout=%s" % [
			craft.name,
			_describe_loadout(craft),
		])
		call_deferred("_request_role_stress_launches")
		return
	if _friendly_launches >= 2:
		if keep_carrier_at_verified_pose:
			_log("CARRIER_HOLD retained verified launch/recovery pose")
		else:
			_carrier_resume_pending = true


func _notify_mixed_helicopter_launched(craft: RigidBody3D, pilot: Node) -> void:
	_friendly_launch_requests_outstanding = maxi(_friendly_launch_requests_outstanding - 1, 0)
	_friendly_launches += 1
	_mixed_helicopter_launches += 1
	craft.name = "MixedRecovery_Heli_%02d" % _mixed_helicopter_launches
	craft.set_meta("carrier_combat_test", true)
	craft.set_meta("mixed_recovery_test", true)
	if "combat_enabled" in pilot:
		pilot.set("combat_enabled", false)
	if "atk_enabled" in pilot:
		pilot.set("atk_enabled", false)
	if "combat_tuning_enabled" in pilot:
		pilot.set("combat_tuning_enabled", false)
	_register_aircraft(craft, pilot, 1)
	var id := craft.get_instance_id()
	var record: Dictionary = _aircraft_records[id]
	record["ops_domain"] = "helicopter"
	record["rolling_status"] = "departing"
	record["rolling_outbound_point"] = Vector3.INF
	record["rolling_recovery_started_s"] = -1.0
	record["rolling_hold_started_s"] = -1.0
	record["rolling_clearance_s"] = -1.0
	record["rolling_queue_position"] = -2
	_aircraft_records[id] = record
	_log("MIXED_LAUNCHED aircraft=%s type=helicopter deck_vertical_departure=true active=%d pending=%d" % [
		craft.name,
		_rolling_active_aircraft_count(),
		_friendly_launch_requests_outstanding,
	])
	_assign_mixed_helicopter_outbound(id, record)
	call_deferred("_request_mixed_launches")


func _notify_role_stress_helicopter_launched(craft: RigidBody3D, pilot: Node) -> void:
	_friendly_launch_requests_outstanding = maxi(_friendly_launch_requests_outstanding - 1, 0)
	_friendly_launches += 1
	_role_stress_helicopter_launches += 1
	craft.name = "RoleStress_AttackHeli_%02d" % _role_stress_helicopter_launches
	craft.set_meta("carrier_combat_test", true)
	craft.set_meta("role_stress_test", true)
	pilot.set("combat_enabled", true)
	pilot.set("atk_enabled", true)
	pilot.set("combat_tuning_enabled", false)
	pilot.set("combat_report_gun_projectiles_enabled", true)
	pilot.set("combat_report_feeler_events_enabled", true)
	_register_aircraft(craft, pilot, 1)
	_configure_weapon_logging(craft)
	var id := craft.get_instance_id()
	var record: Dictionary = _aircraft_records[id]
	record["ops_domain"] = "helicopter"
	record["role"] = "GROUND_ATTACK"
	record["role_ordered"] = false
	record["moving_target_shots"] = 0
	_aircraft_records[id] = record
	_assign_role_stress_helicopter_target(id)
	_log("ROLE_LAUNCHED aircraft=%s model=Aircraft_10 role=GROUND_ATTACK loadout=%s" % [
		craft.name,
		_describe_loadout(craft),
	])
	call_deferred("_request_role_stress_launches")


func _request_rolling_launches() -> void:
	if not _rolling_recovery_mode or _stage != Stage.ROLLING or not is_instance_valid(_fdm):
		return
	# queue_ai_flight replaces, rather than extends, an existing deck launch queue.
	# Wait for its callback count to drain before asking for another refill batch.
	if _friendly_launch_requests_outstanding > 0:
		return
	var active_count := _rolling_active_aircraft_count()
	var request_count := maxi(rolling_active_aircraft_max - active_count, 0)
	if rolling_finite_cohort:
		# Launch exactly one cohort. An abandoned deck callback may be retried, but a
		# trapped or lost member is never replaced, making N/N traps a real assertion.
		var cohort_slots_remaining := maxi(
			rolling_active_aircraft_max
				- _friendly_launches
				- _friendly_launch_requests_outstanding,
			0
		)
		request_count = mini(request_count, cohort_slots_remaining)
	if request_count <= 0:
		return
	var stored_variant: Variant = _fdm.get("stored_aircraft")
	var stored_count: int = stored_variant.size() if stored_variant is Array else 0
	if stored_count <= 0:
		if _elapsed_s - _rolling_last_refill_log_s >= 10.0:
			_rolling_last_refill_log_s = _elapsed_s
			_log("ROLLING_REFILL waiting active=%d needed=%d hangar=0 deck_state=%d" % [
				active_count, request_count, int(_fdm.get("current_state")),
			])
		return
	var queued := int(_fdm.call("queue_ai_flight", request_count, self, INTERCEPT_LOADOUT_PROFILE))
	_friendly_launch_requests_outstanding += queued
	_rolling_last_refill_log_s = _elapsed_s
	_log("ROLLING_REFILL requested=%d queued=%d active=%d committed=%d hangar=%d deck_state=%d" % [
		request_count,
		queued,
		active_count,
		active_count + _friendly_launch_requests_outstanding,
		stored_count,
		int(_fdm.get("current_state")),
	])


func _request_recovery_test_launches() -> void:
	if _desert_recovery_mode:
		_request_desert_recovery_launches()
	elif _mixed_recovery_mode:
		_request_mixed_launches()
	else:
		_request_rolling_launches()


func _request_desert_recovery_launches() -> void:
	if not _desert_recovery_mode or _stage != Stage.ROLLING or not is_instance_valid(_fdm):
		return
	if _friendly_launch_requests_outstanding > 0:
		return
	var active_count := _rolling_active_aircraft_count()
	var committed_active := active_count + _friendly_launch_requests_outstanding
	if committed_active >= rolling_active_aircraft_max:
		return
	if rolling_target_traps > 0 and _rolling_traps >= rolling_target_traps:
		return
	# Reserve the complete airborne deficit in one operation. The prepared hangar
	# order supplies the varied authored roster, followed by physical spares and
	# returned aircraft, without serializing the refill behind one model callback.
	var request_count := rolling_active_aircraft_max - committed_active
	var queued := int(_fdm.call(
		"queue_ai_flight",
		request_count,
		self,
		INTERCEPT_LOADOUT_PROFILE
	))
	_friendly_launch_requests_outstanding = queued
	if queued <= 0:
		if _elapsed_s - _rolling_last_refill_log_s >= 10.0:
			_rolling_last_refill_log_s = _elapsed_s
			_log("DESERT_REFILL_WAIT requested=%d active=%d/%d traps=%d/%s hangar_turnaround=true" % [
				request_count,
				active_count,
				rolling_active_aircraft_max,
				_rolling_traps,
				str(rolling_target_traps) if rolling_target_traps > 0 else "unlimited",
			])
		return
	_rolling_last_refill_log_s = _elapsed_s
	_log("DESERT_REFILL_ORDER requested=%d queued=%d active=%d committed=%d/%d traps=%d/%s priority=waiting_recovery" % [
		request_count,
		queued,
		active_count,
		active_count + queued,
		rolling_active_aircraft_max,
		_rolling_traps,
		str(rolling_target_traps) if rolling_target_traps > 0 else "unlimited",
	])


func _desert_recovery_models_for_cap() -> PackedStringArray:
	var models := PackedStringArray()
	var count := mini(clampi(rolling_active_aircraft_max, 1, 8), DESERT_RECOVERY_MODEL_ROSTER.size())
	for i in range(count):
		models.append(DESERT_RECOVERY_MODEL_ROSTER[i])
	return models


func _desert_recovery_model_for_craft(craft: Node) -> String:
	if not is_instance_valid(craft):
		return "Aircraft_unknown"
	var scene_path := craft.scene_file_path.to_lower()
	for model in DESERT_RECOVERY_MODEL_ROSTER:
		if scene_path.contains(model.to_lower() + ".tscn"):
			return model
	return "Aircraft_unknown"


func _ensure_desert_recovery_hangar_stock() -> bool:
	if not is_instance_valid(_fdm):
		return false
	var stored_variant: Variant = _fdm.get("stored_aircraft")
	if not (stored_variant is Array):
		return false
	var stored: Array = stored_variant
	var fixed_wing_indices: Array[int] = []
	for i in range(stored.size()):
		if not (stored[i] is Dictionary):
			continue
		var entry := stored[i] as Dictionary
		var scene_file := str(entry.get("scene_file", "")).to_lower()
		var entry_name := str(entry.get("name", "")).to_lower()
		var helicopter := scene_file.contains("aircraft_9.tscn") \
				or scene_file.contains("aircraft_10.tscn") \
				or scene_file.contains("aircraft_11.tscn") \
				or entry_name.begins_with("aircraft_9") \
				or entry_name.begins_with("aircraft_10") \
				or entry_name.begins_with("aircraft_11")
		if not helicopter:
			fixed_wing_indices.append(i)
	# Provision all eight authored roster entries. With the default six-aircraft
	# active cap this leaves two physical spares ready while a caught aircraft is
	# still being tractored to the hangar.
	var models := PackedStringArray()
	var stock_count := mini(fixed_wing_indices.size(), DESERT_RECOVERY_MODEL_ROSTER.size())
	for i in range(stock_count):
		models.append(DESERT_RECOVERY_MODEL_ROSTER[i])
	if fixed_wing_indices.size() < models.size():
		_log("DESERT_HANGAR insufficient fixed_wing_slots=%d required=%d" % [
			fixed_wing_indices.size(),
			models.size(),
		])
		return false
	for slot in range(models.size()):
		var model := models[slot]
		var path := "res://Aircraft/%s.tscn" % model
		var scene := load(path) as PackedScene
		if scene == null:
			_log("DESERT_HANGAR missing model=%s path=%s" % [model, path])
			return false
		var index := fixed_wing_indices[slot]
		var entry := stored[index] as Dictionary
		entry["name"] = "DesertRecoveryStored_%02d_%s" % [slot + 1, model]
		entry["scene_file"] = path
		entry["scene"] = scene
		var metadata: Dictionary = entry.get("metadata", {})
		metadata["desert_recovery_model"] = model
		entry["metadata"] = metadata
		stored[index] = entry
	_fdm.set("stored_aircraft", stored)
	_log("DESERT_HANGAR prepared=%d models=%s fixed_wing_slots=%d active_cap=%d spares=%d" % [
		models.size(),
		", ".join(models),
		fixed_wing_indices.size(),
		rolling_active_aircraft_max,
		maxi(models.size() - rolling_active_aircraft_max, 0),
	])
	return true


func _request_mixed_launches() -> void:
	if not _mixed_recovery_mode or _stage != Stage.ROLLING or not is_instance_valid(_fdm):
		return
	if _friendly_launch_requests_outstanding > 0:
		return
	# Helicopters depart first. Their slower 4-6 km transit keeps them airborne
	# while the fixed-wing pair completes elevator/catapult launch, producing a
	# genuinely mixed return queue rather than two isolated recovery batches.
	if not _mixed_helicopters_requested:
		var queued_helis := int(_fdm.call("queue_ai_helicopters", mixed_helicopter_count, self)) \
				if _fdm.has_method("queue_ai_helicopters") else 0
		_mixed_helicopters_requested = queued_helis > 0
		_friendly_launch_requests_outstanding = queued_helis
		_log("MIXED_LAUNCH_ORDER type=helicopter requested=%d queued=%d" % [
			mixed_helicopter_count,
			queued_helis,
		])
		if queued_helis != mixed_helicopter_count:
			_stage = Stage.COMPLETE
			_log("FAILED mixed recovery: expected %d helicopters in hangar, queued=%d" % [
				mixed_helicopter_count,
				queued_helis,
			])
		return
	if _mixed_helicopter_launches < mixed_helicopter_count:
		return
	if not _mixed_fixed_wings_requested:
		var queued_fixed := int(_fdm.call("queue_ai_flight", mixed_fixed_wing_count, self, INTERCEPT_LOADOUT_PROFILE))
		_mixed_fixed_wings_requested = queued_fixed > 0
		_friendly_launch_requests_outstanding = queued_fixed
		_log("MIXED_LAUNCH_ORDER type=fixed_wing requested=%d queued=%d" % [
			mixed_fixed_wing_count,
			queued_fixed,
		])
		if queued_fixed != mixed_fixed_wing_count:
			_stage = Stage.COMPLETE
			_log("FAILED mixed recovery: expected %d fixed-wing aircraft in hangar, queued=%d" % [
				mixed_fixed_wing_count,
				queued_fixed,
			])


func _ensure_role_stress_hangar_stock() -> void:
	if not is_instance_valid(_fdm):
		return
	var stored_variant: Variant = _fdm.get("stored_aircraft")
	if not (stored_variant is Array):
		return
	var stored: Array = stored_variant
	var existing_aircraft_10 := 0
	for entry_variant in stored:
		if entry_variant is Dictionary \
				and str((entry_variant as Dictionary).get("scene_file", "")).to_lower().contains("aircraft_10"):
			existing_aircraft_10 += 1
	var converted := 0
	for i in range(stored.size()):
		if existing_aircraft_10 + converted >= 2:
			break
		if not (stored[i] is Dictionary):
			continue
		var entry := stored[i] as Dictionary
		var scene_file := str(entry.get("scene_file", "")).to_lower()
		var entry_name := str(entry.get("name", "")).to_lower()
		if scene_file.contains("aircraft_9") or scene_file.contains("aircraft_10") \
				or scene_file.contains("aircraft_11") or entry_name.contains("aircraft_11"):
			continue
		entry["name"] = "RoleStress_Aircraft_10_%02d" % (existing_aircraft_10 + converted + 1)
		entry["scene_file"] = FRIENDLY_ATTACK_HELICOPTER_PATH
		entry["scene"] = load(FRIENDLY_ATTACK_HELICOPTER_PATH) as PackedScene
		var metadata: Dictionary = entry.get("metadata", {})
		metadata["aircraft_role"] = "attack_helicopter"
		entry["metadata"] = metadata
		stored[i] = entry
		converted += 1
	_fdm.set("stored_aircraft", stored)
	_log("ROLE_STRESS_HANGAR Aircraft_10=%d converted=%d Aircraft_5=%d" % [
		existing_aircraft_10 + converted,
		converted,
		_count_stored_model("aircraft_5"),
	])


func _count_stored_model(model_name: String) -> int:
	if not is_instance_valid(_fdm):
		return 0
	var stored_variant: Variant = _fdm.get("stored_aircraft")
	if not (stored_variant is Array):
		return 0
	var count := 0
	for entry_variant in stored_variant:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		if str(entry.get("scene_file", "")).to_lower().contains(model_name.to_lower()) \
				or str(entry.get("name", "")).to_lower().contains(model_name.to_lower()):
			count += 1
	return count


func _request_role_stress_launches() -> void:
	if not _role_stress_mode or _stage != Stage.GROUND_STRIKE or not is_instance_valid(_fdm):
		return
	if _friendly_launch_requests_outstanding > 0:
		return
	if not _role_stress_helicopters_requested:
		var queued_helis := int(_fdm.call("queue_ai_helicopters", 2, self, "Aircraft_10"))
		_role_stress_helicopters_requested = queued_helis > 0
		_friendly_launch_requests_outstanding = queued_helis
		_log("AIROPS_LAUNCH role=ground_attack model=Aircraft_10 requested=2 queued=%d" % queued_helis)
		if queued_helis != 2:
			_stage = Stage.COMPLETE
			_log("FAILED role stress: expected two Aircraft_10 helicopters, queued=%d" % queued_helis)
		return
	if _role_stress_helicopter_launches < 2:
		return
	if not _role_stress_patrol_requested:
		var queued_patrol := int(_fdm.call("queue_ai_flight", 2, self, GUN_ONLY_LOADOUT_PROFILE, "Aircraft_5"))
		_role_stress_patrol_requested = queued_patrol > 0
		_friendly_launch_requests_outstanding = queued_patrol
		_log("AIROPS_LAUNCH role=CAP model=Aircraft_5 requested=2 queued=%d loadout=single_gun")
		if queued_patrol != 2:
			_stage = Stage.COMPLETE
			_log("FAILED role stress: expected two gun-only Aircraft_5, queued=%d" % queued_patrol)


func _air_ops_issue(unit: Node, order: OpsOrder) -> bool:
	if AirOpsManager != null and AirOpsManager.has_method("issue_ops_order"):
		return bool(AirOpsManager.call("issue_ops_order", unit, order))
	return OperationsCoordinator.issue_order(unit, order)


func _rolling_active_aircraft_count() -> int:
	var count := 0
	for record_variant in _aircraft_records.values():
		var record: Dictionary = record_variant
		if int(record.get("team", 0)) != 1 or not bool(record.get("alive", false)):
			continue
		var craft_variant: Variant = record.get("craft", null)
		if not is_instance_valid(craft_variant):
			continue
		if str(record.get("rolling_status", "")) in ["departing", "outbound", "recovery"]:
			count += 1
	return count


func _assign_rolling_outbound(id: int, record: Dictionary) -> bool:
	var craft_variant: Variant = record.get("craft", null)
	var pilot_variant: Variant = record.get("pilot", null)
	if not is_instance_valid(craft_variant) or not (craft_variant is RigidBody3D) \
			or not is_instance_valid(pilot_variant) or not (pilot_variant is Node) \
			or not is_instance_valid(_carrier):
		return false
	var craft := craft_variant as RigidBody3D
	var pilot := pilot_variant as Node
	var min_range_m := maxf(rolling_outbound_min_m, 1000.0)
	var max_range_m := maxf(rolling_outbound_max_m, min_range_m)
	var range_m := _rolling_rng.randf_range(min_range_m, max_range_m)
	var bearing_rad := _rolling_rng.randf_range(-PI, PI)
	var outbound_direction := Vector3(sin(bearing_rad), 0.0, cos(bearing_rad)).normalized()
	var outbound_point := _carrier.global_position + outbound_direction * range_m
	var endpoint_ground_m := _ground_height(outbound_point)
	if not is_finite(endpoint_ground_m):
		return false
	outbound_point.y = maxf(
		endpoint_ground_m + maxf(rolling_outbound_altitude_agl_m, 100.0),
		_carrier.global_position.y + 350.0
	)
	if pilot.has_method("build_terrain_safe_waypoints"):
		var desired_points: Array[Vector3] = [outbound_point]
		var safe_variant: Variant = pilot.call(
			"build_terrain_safe_waypoints",
			desired_points,
			maxf(rolling_outbound_min_route_agl_m, 100.0),
			false,
			false
		)
		if safe_variant is Array and not safe_variant.is_empty() and safe_variant[0] is Vector3:
			outbound_point = safe_variant[0]
	var outbound_order: OpsOrder = OpsOrderModel.transit_to_position(
		outbound_point,
		maxf(rolling_outbound_speed_mps, 60.0),
		outbound_point.y,
		maxf(rolling_outbound_capture_radius_m, 50.0)
	)
	outbound_order.metadata = {
		"mission": "rolling_recovery_outbound",
		"launch_serial": _friendly_launches,
		"minimum_agl_m": maxf(rolling_outbound_min_route_agl_m, 100.0),
	}
	if not OperationsCoordinator.issue_order(craft, outbound_order):
		return false
	record["rolling_status"] = "outbound"
	record["rolling_outbound_point"] = outbound_point
	record["rolling_outbound_range_m"] = range_m
	record["rolling_outbound_origin"] = _carrier.global_position
	record["rolling_outbound_bearing_rad"] = bearing_rad
	if _desert_recovery_mode:
		record["desert_recall_due_s"] = -1.0
		record["desert_recall_delay_s"] = -1.0
	_aircraft_records[id] = record
	_log("ROLLING_OUTBOUND aircraft=%s point=%s range=%.0fm bearing=%.1fdeg altitude=%.0fm agl=%.0fm" % [
		craft.name,
		_fmt(outbound_point),
		range_m,
		rad_to_deg(bearing_rad),
		outbound_point.y,
		outbound_point.y - endpoint_ground_m,
	])
	return true


func _assign_mixed_helicopter_outbound(id: int, record: Dictionary) -> bool:
	var craft_variant: Variant = record.get("craft", null)
	if not is_instance_valid(craft_variant) or not (craft_variant is RigidBody3D) \
			or not is_instance_valid(_carrier):
		return false
	var craft := craft_variant as RigidBody3D
	var min_range_m := maxf(rolling_outbound_min_m, 1000.0)
	var max_range_m := maxf(rolling_outbound_max_m, min_range_m)
	var range_m := _rolling_rng.randf_range(min_range_m, max_range_m)
	var bearing_rad := _rolling_rng.randf_range(-PI, PI)
	var outbound_direction := Vector3(sin(bearing_rad), 0.0, cos(bearing_rad)).normalized()
	var outbound_point := _carrier.global_position + outbound_direction * range_m
	var endpoint_ground_m := _ground_height(outbound_point)
	if not is_finite(endpoint_ground_m):
		return false
	# HelicopterPilot owns terrain routing and vertical profile generation. Give it
	# a moderate terminal AGL rather than the fixed-wing cruise altitude.
	outbound_point.y = maxf(endpoint_ground_m + 120.0, _carrier.global_position.y + 90.0)
	var outbound_order: OpsOrder = OpsOrderModel.transit_to_position(
		outbound_point,
		minf(maxf(rolling_outbound_speed_mps * 0.55, 35.0), 65.0),
		outbound_point.y,
		maxf(rolling_outbound_capture_radius_m, 80.0)
	)
	outbound_order.metadata = {
		"mission": "mixed_recovery_outbound",
		"vehicle_type": "helicopter",
		"launch_serial": _friendly_launches,
	}
	if not OperationsCoordinator.issue_order(craft, outbound_order):
		return false
	record["rolling_status"] = "outbound"
	record["rolling_outbound_point"] = outbound_point
	record["rolling_outbound_range_m"] = range_m
	_aircraft_records[id] = record
	_log("MIXED_OUTBOUND aircraft=%s type=helicopter point=%s range=%.0fm bearing=%.1fdeg altitude=%.0fm agl=%.0fm" % [
		craft.name,
		_fmt(outbound_point),
		range_m,
		rad_to_deg(bearing_rad),
		outbound_point.y,
		outbound_point.y - endpoint_ground_m,
	])
	return true


func _poll_rolling_aircraft() -> void:
	if not _rolling_recovery_mode or _stage != Stage.ROLLING:
		return
	var holding_count := 0
	for id_variant in _aircraft_records.keys():
		var id := int(id_variant)
		var record: Dictionary = _aircraft_records[id]
		if int(record.get("team", 0)) != 1 or not bool(record.get("alive", false)):
			continue
		var craft_variant: Variant = record.get("craft", null)
		var pilot_variant: Variant = record.get("pilot", null)
		if not is_instance_valid(craft_variant) or not (craft_variant is RigidBody3D) \
				or not is_instance_valid(pilot_variant) or not (pilot_variant is Node):
			continue
		var craft := craft_variant as RigidBody3D
		var pilot := pilot_variant as Node
		var ops_domain := str(record.get("ops_domain", "fixed_wing"))
		var status := str(record.get("rolling_status", ""))
		var state := int(pilot.get("state")) if ops_domain == "helicopter" \
				else int(pilot.get("current_state"))
		if status == "departing":
			if ops_domain == "helicopter":
				_assign_mixed_helicopter_outbound(id, record)
			elif state in [AIPilot.State.SEARCH, AIPilot.State.TRANSIT]:
				_assign_rolling_outbound(id, record)
			continue
		if status == "outbound":
			var outbound_value: Variant = record.get("rolling_outbound_point", Vector3.INF)
			if outbound_value is Vector3 and outbound_value != Vector3.INF:
				var outbound_point: Vector3 = outbound_value
				var distance_to_point_m := _flat_distance(craft.global_position, outbound_point)
				var outbound_origin_value: Variant = record.get(
					"rolling_outbound_origin",
					_carrier.global_position if is_instance_valid(_carrier) else Vector3.ZERO
				)
				var outbound_origin: Vector3 = outbound_origin_value \
						if outbound_origin_value is Vector3 else Vector3.ZERO
				var outbound_distance_m := _flat_distance(craft.global_position, outbound_origin)
				# A finite one-leg plan changes to SEARCH after crossing its terminal
				# gate. Accept that contract as well as spatial capture so a high-speed
				# endpoint miss cannot wander indefinitely before returning.
				var outbound_route_complete := ops_domain == "fixed_wing" \
						and state == AIPilot.State.SEARCH
				var desert_initial_cohort_ready := not _desert_recovery_mode \
						or (
							_friendly_launches >= _desert_recovery_models_for_cap().size() \
							and _friendly_launch_requests_outstanding <= 0
						)
				var recall_trigger := "route_complete" if outbound_route_complete else "radius"
				var outbound_reached := distance_to_point_m <= maxf(rolling_outbound_capture_radius_m, 50.0) \
						or outbound_route_complete
				if _desert_recovery_mode:
					# Each aircraft owns a random 10 km bearing. Crossing the configured
					# fraction arms an independent delay; the plane keeps flying its route
					# until that timer expires, producing dispersed return geometry.
					var target_range_m := maxf(
						float(record.get("rolling_outbound_range_m", desert_recovery_outbound_distance_m)),
						1000.0
					)
					var recall_arm_distance_m := target_range_m * clampf(
						desert_recovery_recall_arm_fraction,
						0.1,
						0.9
					)
					var recall_due_s := float(record.get("desert_recall_due_s", -1.0))
					if recall_due_s < 0.0 \
							and desert_initial_cohort_ready \
							and outbound_distance_m >= recall_arm_distance_m:
						var min_delay_s := maxf(desert_recovery_recall_delay_min_s, 0.0)
						var max_delay_s := maxf(desert_recovery_recall_delay_max_s, min_delay_s)
						var recall_delay_s := _rolling_rng.randf_range(min_delay_s, max_delay_s)
						recall_due_s = _elapsed_s + recall_delay_s
						record["desert_recall_due_s"] = recall_due_s
						record["desert_recall_delay_s"] = recall_delay_s
						record["desert_recall_arm_distance_m"] = outbound_distance_m
						if not bool(record.get("rolling_outbound_complete", false)):
							record["rolling_outbound_complete"] = true
							_record_desert_recovery_stage(
								id,
								"outbound_complete",
								"trigger=halfway distance=%.0fm target=%.0fm recall_delay=%.1fs" % [
									outbound_distance_m,
									target_range_m,
									recall_delay_s,
								]
							)
						_aircraft_records[id] = record
						_log("DESERT_RECALL_ARMED aircraft=%s distance=%.0fm target=%.0fm delay=%.1fs due=%.1fs" % [
							craft.name,
							outbound_distance_m,
							target_range_m,
							recall_delay_s,
							recall_due_s,
						])
					outbound_reached = recall_due_s >= 0.0 and _elapsed_s >= recall_due_s
					recall_trigger = "random_delay_after_halfway"
				if outbound_reached:
					if not bool(record.get("rolling_outbound_complete", false)):
						record["rolling_outbound_complete"] = true
						_aircraft_records[id] = record
						if _desert_recovery_mode:
							_record_desert_recovery_stage(
								id,
								"outbound_complete",
								"trigger=%s distance=%.0fm" % [
									recall_trigger,
									outbound_distance_m,
								]
							)
					if not desert_initial_cohort_ready:
						continue
					if ops_domain == "fixed_wing":
						pilot.set("ground_attack_enabled", false)
						pilot.set("dogfight_enabled", false)
						pilot.set("aircraft_heightmap_pathfinding_enabled", true)
						pilot.set("approach_route_threaded", true)
					var accepted := OperationsCoordinator.issue_order(craft, OpsOrderModel.recover())
					if accepted:
						record["rolling_status"] = "recovery"
						record["rolling_recovery_started_s"] = _elapsed_s
						_recovery_requested[id] = true
						_aircraft_records[id] = record
						if _desert_recovery_mode:
							_record_desert_recovery_stage(
								id,
								"rtb_started",
								"recall_accepted=true trigger=%s distance=%.0fm" % [
									recall_trigger,
									outbound_distance_m,
								]
							)
						_log("ROLLING_RETURN aircraft=%s type=%s outbound_reached=%.0fm recovery_accepted=true state=%s trigger=%s" % [
							craft.name,
							ops_domain,
							outbound_distance_m,
							_ops_state_name(pilot, ops_domain),
							recall_trigger,
						])
			continue
		if status != "recovery":
			continue
		if ops_domain == "helicopter" \
				and bool(craft.get_meta("carrier_transport_mode", false)) \
				and not _caught_aircraft.has(id):
			_record_rolling_recovery(craft, -1, NAN, "helicopter")
			continue
		var queue_position := int(_fdm.call("get_landing_queue_position", craft)) \
				if is_instance_valid(_fdm) and _fdm.has_method("get_landing_queue_position") else -1
		var waiting_for_clearance := state == AIPilot.State.RECOVERY_HOLD \
				if ops_domain == "fixed_wing" else queue_position > 0
		if waiting_for_clearance:
			holding_count += 1
			if float(record.get("rolling_hold_started_s", -1.0)) < 0.0:
				record["rolling_hold_started_s"] = _elapsed_s
				_log("ROLLING_HOLD aircraft=%s type=%s entered carrier_dist=%.0fm" % [
					craft.name,
					ops_domain,
					_flat_distance(craft.global_position, _carrier.global_position),
				])
		if queue_position != int(record.get("rolling_queue_position", -2)):
			record["rolling_queue_position"] = queue_position
			if queue_position == 0 and float(record.get("rolling_clearance_s", -1.0)) < 0.0:
				record["rolling_clearance_s"] = _elapsed_s
			_log("ROLLING_QUEUE aircraft=%s type=%s position=%d state=%s recovery_elapsed=%.1fs" % [
				craft.name,
				ops_domain,
				queue_position,
				_ops_state_name(pilot, ops_domain),
				_elapsed_s - float(record.get("rolling_recovery_started_s", _elapsed_s)),
			])
		_aircraft_records[id] = record
	_rolling_max_holding_aircraft = maxi(_rolling_max_holding_aircraft, holding_count)
	_log_rolling_queue_snapshot()


func _ops_state_name(pilot: Node, ops_domain: String) -> String:
	if ops_domain == "helicopter":
		var state := int(pilot.get("state"))
		return str(HelicopterPilot.State.keys()[state]) \
				if state >= 0 and state < HelicopterPilot.State.size() else "UNKNOWN"
	return _state_name(int(pilot.get("current_state")))


func _log_rolling_queue_snapshot() -> void:
	if not is_instance_valid(_fdm):
		return
	var holder_variant: Variant = _fdm.get("_landing_clearance_aircraft")
	var holder_name := "none"
	if is_instance_valid(holder_variant) and holder_variant is Node:
		holder_name = str((holder_variant as Node).name)
	var queue_names: PackedStringArray = []
	var queue_variant: Variant = _fdm.get("_landing_clearance_queue")
	if queue_variant is Array:
		for requester_variant in queue_variant:
			if is_instance_valid(requester_variant) and requester_variant is Node:
				queue_names.append(str((requester_variant as Node).name))
	_rolling_max_queue_depth = maxi(_rolling_max_queue_depth, queue_names.size())
	var signature := "%s|%s" % [holder_name, ",".join(queue_names)]
	if signature == _rolling_last_queue_signature:
		return
	_rolling_last_queue_signature = signature
	_log("ROLLING_QUEUE_SNAPSHOT holder=%s waiting=%d [%s]" % [
		holder_name,
		queue_names.size(),
		", ".join(queue_names),
	])


func _hold_carrier_for_launches() -> bool:
	if not is_instance_valid(_carrier) or not _carrier.has_method("set_heli_test_stationary"):
		return false
	var active_route: Array[Vector3] = []
	if _carrier.has_method("get_active_waypoints"):
		active_route = _carrier.call("get_active_waypoints")
	if not active_route.is_empty():
		_carrier_resume_route_offset = active_route[-1] - _carrier.global_position
	_carrier.call("set_heli_test_stationary", true)
	if not _stage_carrier_at_safe_test_pose():
		_carrier.call("set_heli_test_stationary", false)
		return false
	_carrier_held_for_launches = true
	_log("CARRIER_HOLD deck launches stabilized heading=%.1fdeg" % rad_to_deg(_carrier.rotation.y))
	return true


func _stage_carrier_at_safe_test_pose() -> bool:
	# This is a controlled physical test, so do not inherit a random patrol pose
	# and then wait a minute for the terrain interlock to happen to clear. Search
	# nearby flat ground and evaluate the same launch and landing checks used by
	# FlightDeckManager before committing the scenario pose.
	if not is_instance_valid(_carrier) or not is_instance_valid(_fdm):
		return false
	if not _fdm.has_method("_launch_path_clear_of_terrain"):
		return false

	var original_transform: Transform3D = _carrier.global_transform
	var original_ground_m: float = _ground_height(original_transform.origin)
	var ride_height_m: float = original_transform.origin.y - original_ground_m
	if not is_finite(ride_height_m) or ride_height_m < 10.0 or ride_height_m > 100.0:
		ride_height_m = 40.0

	# The normal game deliberately starts the carrier near one edge for its
	# cross-map patrol. That is unsuitable for the full-cycle range: its strike
	# site and 6 km bomber spawn can then fall outside TerrainNavGrid, which is
	# also the exact footprint displayed by the tactical map. Anchor this profile
	# at the live grid centre and search outward from there. Other observation
	# profiles preserve their established nearest-to-normal-start behavior.
	var staging_center := original_transform.origin
	if _full_cycle_mode or _desert_recovery_mode:
		staging_center = _tactical_map_center_world()
		staging_center.y = original_transform.origin.y
	# Ordered nearest-first around the selected anchor. Rotation is cheaper than
	# relocation, so only move farther out if every heading is obstructed.
	var position_offsets: Array[Vector3] = [Vector3.ZERO]
	for radius_m in [400.0, 800.0, 1200.0, 1800.0, 2600.0, 3600.0, 4800.0]:
		for bearing_deg in range(0, 360, 45):
			position_offsets.append(
				Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(float(bearing_deg))) * radius_m
			)
	var heading_offsets_deg: Array[float] = [0.0]
	for heading_step_deg in range(15, 181, 15):
		heading_offsets_deg.append(float(heading_step_deg))
		heading_offsets_deg.append(-float(heading_step_deg))

	var target_offsets: Array[Vector2] = [
		Vector2(-0.5, -0.5), Vector2(0.5, -0.5),
		Vector2(-0.5, 0.5), Vector2(0.5, 0.5),
	]
	var original_heading_rad: float = original_transform.basis.get_euler().y
	var poses_tested: int = 0
	for position_offset in position_offsets:
		var candidate_xz: Vector3 = staging_center + position_offset
		var candidate_ground_m: float = _ground_height(candidate_xz)
		if not is_finite(candidate_ground_m):
			continue
		var candidate_position := Vector3(
			candidate_xz.x,
			candidate_ground_m + ride_height_m,
			candidate_xz.z
		)
		if _desert_recovery_mode and not _desert_recovery_site_is_open(candidate_position):
			continue
		for heading_offset_deg in heading_offsets_deg:
			var candidate_heading_rad: float = original_heading_rad + deg_to_rad(heading_offset_deg)
			var candidate_basis := Basis(Vector3.UP, candidate_heading_rad)
			if _desert_recovery_mode \
					and not _desert_recovery_final_corridor_is_open(
						candidate_position,
						candidate_basis
					):
				continue
			if not _carrier_staging_surface_is_flat(candidate_position, candidate_basis):
				continue
			_carrier.global_transform = Transform3D(candidate_basis, candidate_position)
			poses_tested += 1
			if not bool(_fdm.call("_launch_path_clear_of_terrain")):
				continue
			if not _carrier_launch_climb_corridor_is_clear(candidate_position, candidate_basis):
				continue
			if not continuous_intercept_mode \
					and _fdm.has_method("_landing_path_clear_of_terrain") \
					and not bool(_fdm.call("_landing_path_clear_of_terrain", true)):
				continue
			if not continuous_intercept_mode and not _rolling_recovery_mode:
				var carrier_forward := candidate_basis.z.normalized()
				var carrier_right := candidate_basis.x.normalized()
				if _find_ground_target_cluster_site(carrier_forward, carrier_right, target_offsets).is_empty():
					continue
			if _full_cycle_mode:
				# Replace the inherited edge-to-edge destination with a contained first
				# leg. Once reached, LandCarrier's normal patrol selector continues to
				# choose legal destinations inside the same navigation/map footprint.
				var flat_forward := Vector3(candidate_basis.z.x, 0.0, candidate_basis.z.z).normalized()
				_carrier_resume_route_offset = flat_forward * maxf(full_cycle_carrier_initial_patrol_leg_m, 500.0)
			var validated_for := "launch+climb+recovery+open_level_desert" if _desert_recovery_mode else (
				"launch+climb" if continuous_intercept_mode else "launch+climb+recovery+targets"
			)
			_log("CARRIER_STAGED pos=%s heading=%.1fdeg moved=%.0fm map_center=%s poses_tested=%d validated=%s" % [
				_fmt(candidate_position),
				rad_to_deg(candidate_heading_rad),
				_flat_distance(candidate_position, original_transform.origin),
				_fmt(_tactical_map_center_world()),
				poses_tested,
				validated_for,
			])
			return true

	_carrier.global_transform = original_transform
	_log("CARRIER_STAGING_FAILED poses_tested=%d restored=%s" % [
		poses_tested,
		_fmt(original_transform.origin),
	])
	return false


func _desert_recovery_site_is_open(position: Vector3) -> bool:
	var center_ground_m := _ground_height(position)
	if not is_finite(center_ground_m):
		return false
	var radius_m := maxf(desert_recovery_open_radius_m, 300.0)
	var max_relief_m := maxf(desert_recovery_final_corridor_max_relief_m, 5.0)
	var min_height_m := center_ground_m
	var max_height_m := center_ground_m
	# Three rings reject carrier starts beside narrow ridges or cliff shelves. The
	# longer, heading-dependent final strip is checked separately below.
	for ring_fraction in [0.33, 0.66, 1.0]:
		var ring_radius_m: float = radius_m * float(ring_fraction)
		for bearing_deg in range(0, 360, 30):
			var direction := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(float(bearing_deg)))
			var ground_m := _ground_height(position + direction * ring_radius_m)
			if not is_finite(ground_m):
				return false
			min_height_m = minf(min_height_m, ground_m)
			max_height_m = maxf(max_height_m, ground_m)
			if absf(ground_m - center_ground_m) > max_relief_m:
				return false
	return max_height_m - min_height_m <= max_relief_m


func _desert_recovery_final_corridor_is_open(
	carrier_position: Vector3,
	carrier_basis: Basis
) -> bool:
	## The generic FlightDeckManager check protects the close final. This profile
	## additionally guarantees that the entire authored PRE_LANDING straight is on
	## the same broad desert level, with enough width for normal lateral correction.
	var center_ground_m := _ground_height(carrier_position)
	if not is_finite(center_ground_m):
		return false
	var corridor_length_m := maxf(desert_recovery_final_corridor_length_m, 2800.0)
	var half_width_m := maxf(desert_recovery_final_corridor_half_width_m, 100.0)
	var max_relief_m := maxf(desert_recovery_max_relief_m, 5.0)
	var approach_axis := Vector3(
		carrier_basis.z.x,
		0.0,
		carrier_basis.z.z
	).normalized()
	var lateral_axis := Vector3(
		carrier_basis.x.x,
		0.0,
		carrier_basis.x.z
	).normalized()
	for along_fraction in [0.25, 0.5, 0.75, 1.0]:
		var along_m: float = corridor_length_m * float(along_fraction)
		for lateral_fraction in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var probe := carrier_position \
					+ approach_axis * along_m \
					+ lateral_axis * half_width_m * float(lateral_fraction)
			var ground_m := _ground_height(probe)
			if not is_finite(ground_m) \
					or absf(ground_m - center_ground_m) > max_relief_m:
				return false
	return true


func _tactical_map_center_world() -> Vector3:
	# WorldMapSymbolLayer uses these exact TerrainNavGrid extents. Deriving the
	# centre here keeps staging correct after any floating-origin shift.
	if TerrainNavGrid.is_ready() and TerrainNavGrid._cols > 1 and TerrainNavGrid._rows > 1:
		return Vector3(
			TerrainNavGrid._origin_x + float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m * 0.5,
			_carrier.global_position.y if is_instance_valid(_carrier) else _play_area_center.y,
			TerrainNavGrid._origin_z + float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m * 0.5
		)
	return _play_area_center


func _carrier_launch_climb_corridor_is_clear(position: Vector3, basis: Basis) -> bool:
	# FlightDeckManager validates the catapult itself, but the generic launch state
	# continues straight ahead while building altitude. Reject a pose that points
	# that 1.8 km climb into a ridge. This profile is deliberately below the actual
	# healthy climb, leaving a terrain margin instead of assuming perfect performance.
	var forward := Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	if forward.length_squared() < 0.001:
		return false
	var starting_ground_m: float = _ground_height(position)
	if not is_finite(starting_ground_m):
		return false
	var deck_height_m: float = position.y - starting_ground_m
	var capture_height_m: float = 350.0
	# Terrain chunks can contain narrow ridges that a 100 m probe interval steps
	# over completely. The failed visible run launched both aircraft into the
	# same peak roughly 500 m ahead even though the 450/550 m probes passed.
	# Sample the real departure centerline densely enough to catch those peaks.
	for distance_m_value in range(50, 2001, 25):
		var distance_m: float = float(distance_m_value)
		var probe: Vector3 = position + forward * distance_m
		var terrain_m: float = _ground_height(probe)
		if not is_finite(terrain_m):
			return false
		var planned_height_above_start_m: float = minf(
			maxf((distance_m - 150.0) * 0.40, 0.0),
			capture_height_m
		)
		var conservative_flight_y_m: float = starting_ground_m + deck_height_m \
				+ planned_height_above_start_m
		var margin_m: float = lerpf(
			10.0,
			70.0,
			clampf((distance_m - 150.0) / 700.0, 0.0, 1.0)
		)
		if terrain_m + margin_m > conservative_flight_y_m:
			return false
	return true


func _carrier_staging_surface_is_flat(position: Vector3, basis: Basis) -> bool:
	# Approximate the tread footprint. The carrier's own suspension will handle
	# small variation, but staging it across a ridge can move the catapult after
	# the corridor check and invalidate an otherwise clear pose.
	var forward := Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	var min_height_m: float = INF
	var max_height_m: float = -INF
	for longitudinal_value in [-150.0, 0.0, 150.0]:
		var longitudinal_m: float = float(longitudinal_value)
		for lateral_value in [-55.0, 0.0, 55.0]:
			var lateral_m: float = float(lateral_value)
			var probe: Vector3 = position + forward * longitudinal_m + right * lateral_m
			var height_m: float = _ground_height(probe)
			if not is_finite(height_m):
				return false
			min_height_m = minf(min_height_m, height_m)
			max_height_m = maxf(max_height_m, height_m)
	return max_height_m - min_height_m <= 8.0


func _resume_carrier_after_launches() -> void:
	_release_carrier_hold("after second launch")


func _release_carrier_hold(reason: String) -> bool:
	if not _carrier_held_for_launches or not is_instance_valid(_carrier):
		return false
	_carrier_resume_pending = false
	_carrier_held_for_launches = false
	if _carrier.has_method("set_heli_test_stationary"):
		_carrier.call("set_heli_test_stationary", false)
	if _carrier_resume_route_offset.length_squared() > 1.0 and _carrier.has_method("set_patrol_waypoints"):
		var destination := _carrier.global_position + _carrier_resume_route_offset
		var resume_waypoints: Array[Vector3] = [destination]
		_carrier.call("set_patrol_waypoints", resume_waypoints)
	_log("CARRIER_RESUME %s" % reason)
	return true


func _try_resume_carrier_after_launches() -> void:
	if not _carrier_resume_pending or _friendly_launches < 2:
		return
	for record_variant in _aircraft_records.values():
		var record: Dictionary = record_variant
		if int(record.get("team", 0)) != 1 or not bool(record.get("alive", false)):
			continue
		var pilot: Node = record.get("pilot", null)
		if is_instance_valid(pilot) and int(pilot.get("current_state")) in [AIPilot.State.IDLE, AIPilot.State.LAUNCHING]:
			return
	_resume_carrier_after_launches()


func _assign_ground_target(pilot: Node, launch_index: int) -> void:
	if not is_instance_valid(pilot) or _stage != Stage.GROUND_STRIKE:
		return
	var live := _live_ground_targets()
	if live.is_empty():
		return
	var target := live[launch_index % live.size()]
	pilot.call("set_target", target)
	_log("ORDER %s attack %s" % [_pilot_aircraft_name(pilot), target.name])


func _assign_role_stress_helicopter_target(id: int) -> bool:
	var record: Dictionary = _aircraft_records.get(id, {})
	if not bool(record.get("alive", false)) or str(record.get("role", "")) != "GROUND_ATTACK":
		return false
	var craft: Node = record.get("craft", null)
	if not is_instance_valid(craft):
		return false
	var live_targets := _live_ground_targets()
	if live_targets.is_empty():
		return false
	var assignment_index := int(record.get("ground_assignment_index", _role_stress_helicopter_launches - 1))
	var target := live_targets[posmod(assignment_index, live_targets.size())]
	var accepted := _air_ops_issue(craft, OpsOrderModel.attack_target(target))
	record["ground_assignment_index"] = assignment_index
	record["role_ordered"] = accepted
	record["assigned_ground_target_id"] = target.get_instance_id() if accepted else 0
	_aircraft_records[id] = record
	_log("AIROPS_ORDER aircraft=%s role=GROUND_ATTACK target=%s moving=true accepted=%s" % [
		record.get("name", craft.name),
		target.name,
		str(accepted),
	])
	return accepted


func _assign_role_stress_patrol(record_id: int) -> bool:
	var record: Dictionary = _aircraft_records.get(record_id, {})
	var craft: Node = record.get("craft", null)
	if not is_instance_valid(craft) or not is_instance_valid(_carrier):
		return false
	var forward := _carrier.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var patrol_center := _carrier.global_position + forward * 1400.0
	patrol_center.y = _ground_height(patrol_center) + role_stress_patrol_altitude_agl_m
	var accepted := _air_ops_issue(craft, OpsOrderModel.patrol_position(
		patrol_center,
		role_stress_patrol_radius_m,
		patrol_center.y
	))
	record["role_ordered"] = accepted
	record["role_order_name"] = "PATROL"
	_aircraft_records[record_id] = record
	_log("AIROPS_ORDER aircraft=%s role=CAP task=PATROL center=%s radius=%.0fm accepted=%s" % [
		record.get("name", craft.name),
		_fmt(patrol_center),
		role_stress_patrol_radius_m,
		str(accepted),
	])
	return accepted


func _assign_role_stress_intercepts() -> void:
	var enemies := _live_aircraft_for_team(2)
	if enemies.is_empty():
		return
	var next_enemy := 0
	for id_variant in _aircraft_records.keys():
		var id := int(id_variant)
		var record: Dictionary = _aircraft_records[id]
		if not bool(record.get("alive", false)) or str(record.get("role", "")) != "CAP":
			continue
		var pilot: Node = record.get("pilot", null)
		var craft: Node = record.get("craft", null)
		if not is_instance_valid(pilot) or not is_instance_valid(craft):
			continue
		var state := int(pilot.get("current_state"))
		if state in [AIPilot.State.IDLE, AIPilot.State.LAUNCHING]:
			continue
		var enemy_record: Dictionary = enemies[next_enemy % enemies.size()]
		next_enemy += 1
		var target: Node3D = enemy_record.get("craft", null) as Node3D
		if not is_instance_valid(target):
			continue
		var current_target: Variant = pilot.get("combat_target")
		if current_target == target and str(record.get("role_order_name", "")) == "INTERCEPT":
			continue
		var accepted := _air_ops_issue(craft, OpsOrderModel.intercept_target(target))
		if accepted:
			pilot.set("ground_attack_enabled", false)
			pilot.set("dogfight_enabled", true)
			record["role_ordered"] = true
			record["role_order_name"] = "INTERCEPT"
			_aircraft_records[id] = record
		_log("AIROPS_ORDER aircraft=%s role=CAP task=INTERCEPT target=%s accepted=%s" % [
			record.get("name", craft.name),
			target.name,
			str(accepted),
		])
	_refresh_all_gun_targets()


func _spawn_role_stress_enemy_fighters() -> void:
	if _role_stress_enemy_fighters_spawned or not is_instance_valid(_carrier):
		return
	_role_stress_enemy_fighters_spawned = true
	var caps: Array[Dictionary] = []
	for record_variant in _live_aircraft_for_team(1):
		var friendly_record: Dictionary = record_variant
		if str(friendly_record.get("role", "")) == "CAP":
			caps.append(friendly_record)
	var outward := _carrier.global_transform.basis.x
	outward.y = 0.0
	outward = outward.normalized() if outward.length_squared() > 0.001 else Vector3.RIGHT
	var lateral := _carrier.global_transform.basis.z
	lateral.y = 0.0
	lateral = lateral.normalized() if lateral.length_squared() > 0.001 else Vector3.FORWARD
	var spawned := 0
	for i in range(2):
		_enemy_spawn_serial += 1
		var craft := ENEMY_FIGHTER_SCENE.instantiate() as RigidBody3D
		if craft == null:
			continue
		craft.name = "RoleStress_Enemy_Aircraft_3_%02d" % (i + 1)
		craft.set("team", 2)
		craft.set_meta("carrier_combat_test", true)
		craft.set_meta("carrier_transport_mode", false)
		get_tree().current_scene.add_child(craft)
		var lane := (float(i) - 0.5) * enemy_pair_spacing_m
		var pos := _carrier.global_position + outward * role_stress_enemy_fighter_range_m + lateral * lane
		pos.y = _ground_height(pos) + role_stress_patrol_altitude_agl_m
		craft.global_transform = Transform3D(_basis_from_forward(-outward), pos)
		craft.linear_velocity = -outward * enemy_initial_speed_mps
		craft.angular_velocity = Vector3.ZERO
		_configure_existing_guns_only(craft)
		var toggle := craft.find_child("AIToggle", true, false)
		if toggle != null and toggle.has_method("enable_ai"):
			toggle.call("enable_ai")
		var pilot := craft.find_child("AIPilot", true, false)
		_configure_pilot(pilot, false)
		if is_instance_valid(pilot):
			pilot.set("dogfight_enabled", true)
			pilot.set("ground_attack_enabled", false)
		_register_aircraft(craft, pilot, 2)
		var enemy_id := craft.get_instance_id()
		var enemy_record: Dictionary = _aircraft_records[enemy_id]
		enemy_record["role"] = "INTERCEPTOR"
		_aircraft_records[enemy_id] = enemy_record
		_configure_weapon_logging(craft)
		if not caps.is_empty() and is_instance_valid(pilot):
			var target: Node3D = caps[i % caps.size()].get("craft", null) as Node3D
			if is_instance_valid(target):
				pilot.call("assign_air_task", AirTaskModel.intercept_target(target))
		_log("SPAWN aircraft=%s model=Aircraft_3 role=INTERCEPTOR loadout=%s pos=%s target=%s" % [
			craft.name,
			_describe_loadout(craft),
			_fmt(pos),
			str(caps[i % caps.size()].get("name", "none")) if not caps.is_empty() else "none",
		])
		_remove_player_group_deferred(craft)
		spawned += 1
	_log("ROLE_TRIGGER first_ground_vehicle_destroyed enemy_air_spawned=%d model=Aircraft_3 loadout=guns_only" % spawned)
	_assign_role_stress_intercepts()


func _configure_existing_guns_only(craft: RigidBody3D) -> void:
	for node in craft.find_children("*", "Hardpoint", true, false):
		var hardpoint := node as Hardpoint
		if hardpoint == null:
			continue
		var weapon_name := ""
		if is_instance_valid(hardpoint.weapon_instance):
			weapon_name = str(hardpoint.weapon_instance.get("weapon_name")).to_lower()
		var is_gun := weapon_name.contains("gun") or weapon_name.contains("cannon") \
				or hardpoint.weapon_instance is Autocannon
		if is_gun:
			continue
		if is_instance_valid(hardpoint.weapon_instance):
			hardpoint.weapon_instance.queue_free()
		hardpoint.weapon_instance = null
		hardpoint.mounted_weapon = null
	var control_weapons := craft.find_child("ControlWeapons", true, false)
	if control_weapons != null:
		if control_weapons.has_method("find_hardpoints"):
			control_weapons.call("find_hardpoints")
		if control_weapons.has_method("categorize_weapons"):
			control_weapons.call("categorize_weapons")


func _poll_role_stress() -> void:
	if not _role_stress_mode:
		return
	if _stage == Stage.RECOVERY:
		for id_variant in _recovery_requested.keys():
			var id := int(id_variant)
			if _caught_aircraft.has(id):
				continue
			var record: Dictionary = _aircraft_records.get(id, {})
			if str(record.get("ops_domain", "")) != "helicopter":
				continue
			var craft: RigidBody3D = record.get("craft", null) as RigidBody3D
			if is_instance_valid(craft) and bool(craft.get_meta("carrier_transport_mode", false)):
				_caught_aircraft[id] = true
				OperationsCoordinator.clear_order(craft)
				_log("LANDING helicopter_recovered aircraft=%s caught=%d/%d" % [
					record.get("name", craft.name),
					_caught_aircraft.size(),
					_recovery_requested.size(),
				])
		_check_recovery_end()
		return
	if _stage != Stage.GROUND_STRIKE:
		return
	for id_variant in _aircraft_records.keys():
		var id := int(id_variant)
		var record: Dictionary = _aircraft_records[id]
		if not bool(record.get("alive", false)) or int(record.get("team", 0)) != 1:
			continue
		var role := str(record.get("role", ""))
		var pilot: Node = record.get("pilot", null)
		if not is_instance_valid(pilot):
			continue
		if role == "GROUND_ATTACK":
			var commanded_target: Variant = pilot.get("_commanded_attack_target")
			if is_instance_valid(commanded_target) and commanded_target is Node3D \
					and ((commanded_target as Node3D).is_in_group("aircraft") \
					or (commanded_target as Node3D).is_in_group("ai_aircraft")):
				_record_role_violation(id, "ground-attack helicopter targeted aircraft %s" % (commanded_target as Node).name)
			var assigned_id := int(record.get("assigned_ground_target_id", 0))
			if assigned_id == 0 or not is_instance_id_valid(assigned_id):
				# The pilot may tactically continue an established firing corridor onto a
				# second ground target. Recognize that continuation instead of immediately
				# overwriting it with a fresh AirOps order and rebuilding the whole ingress.
				if is_instance_valid(commanded_target) and commanded_target is Node3D \
						and not bool((commanded_target as Node3D).get("is_destroyed")) \
						and not (commanded_target as Node3D).is_in_group("aircraft") \
						and not (commanded_target as Node3D).is_in_group("ai_aircraft"):
					record["assigned_ground_target_id"] = (commanded_target as Node3D).get_instance_id()
					_aircraft_records[id] = record
					_log("AIROPS_ACK aircraft=%s role=GROUND_ATTACK tactical_retarget=%s" % [
						record.get("name", "unknown"),
						(commanded_target as Node3D).name,
					])
				else:
					record["ground_assignment_index"] = int(record.get("ground_assignment_index", 0)) + 1
					_aircraft_records[id] = record
					_assign_role_stress_helicopter_target(id)
		elif role == "CAP":
			var cap_target: Variant = pilot.get("combat_target")
			if is_instance_valid(cap_target) and cap_target is Node3D \
					and not ((cap_target as Node3D).is_in_group("aircraft") \
					or (cap_target as Node3D).is_in_group("ai_aircraft")):
				_record_role_violation(id, "CAP aircraft targeted non-aircraft %s" % (cap_target as Node).name)
			var state := int(pilot.get("current_state"))
			if state in [AIPilot.State.SEARCH, AIPilot.State.TRANSIT, AIPilot.State.CLIMBING]:
				if _role_stress_enemy_fighters_spawned:
					_assign_role_stress_intercepts()
				elif not bool(record.get("role_ordered", false)):
					_assign_role_stress_patrol(id)


func _record_role_violation(id: int, reason: String) -> void:
	var record: Dictionary = _aircraft_records.get(id, {})
	if bool(record.get("role_violation_reported", false)):
		return
	record["role_violation_reported"] = true
	_aircraft_records[id] = record
	_role_stress_role_violations += 1
	_log("ROLE_VIOLATION aircraft=%s reason=%s total=%d" % [
		record.get("name", "unknown"),
		reason,
		_role_stress_role_violations,
	])


func _try_finish_role_stress_combat() -> void:
	if not _role_stress_mode or _stage != Stage.GROUND_STRIKE:
		return
	if _ground_targets_destroyed < 4 or not _role_stress_enemy_fighters_spawned:
		return
	if not _live_aircraft_for_team(2).is_empty():
		return
	_begin_role_stress_recovery()


func _begin_role_stress_recovery() -> void:
	if _role_stress_recovery_started:
		return
	_role_stress_recovery_started = true
	_stage = Stage.RECOVERY
	_stage_started_s = _elapsed_s
	_log("PHASE role stress recovery; ground vehicles eliminated and enemy Aircraft_3 eliminated")
	for record_variant in _live_aircraft_for_team(1):
		var record: Dictionary = record_variant
		var craft: Node = record.get("craft", null)
		var pilot: Node = record.get("pilot", null)
		if not is_instance_valid(craft) or not is_instance_valid(pilot):
			continue
		if str(record.get("ops_domain", "")) == "fixed_wing":
			pilot.set("ground_attack_enabled", false)
			pilot.set("dogfight_enabled", false)
			pilot.set("aircraft_heightmap_pathfinding_enabled", true)
			pilot.set("approach_route_threaded", true)
		var id := craft.get_instance_id()
		_recovery_requested[id] = true
		var accepted := _air_ops_issue(craft, OpsOrderModel.recover())
		_log("AIROPS_ORDER aircraft=%s role=%s task=RECOVER accepted=%s" % [
			record.get("name", craft.name),
			record.get("role", "unknown"),
			str(accepted),
		])


func _on_ground_target_damaged(amount: float, health: float, target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	_log("HIT ground_target=%s damage=%.1f hp=%.1f" % [target.name, amount, health])


func _on_ground_target_destroyed(target: Node) -> void:
	_ground_targets_destroyed += 1
	_ground_wave_destroyed += 1
	_log("DESTROYED ground_target=%s wave=%d count=%d/4 total=%d" % [
		target.name if is_instance_valid(target) else "unknown",
		_ground_wave_index,
		_ground_wave_destroyed,
		_ground_targets_destroyed,
	])
	if _role_stress_mode:
		if _ground_targets_destroyed == 1:
			call_deferred("_spawn_role_stress_enemy_fighters")
		var destroyed_id := target.get_instance_id() if is_instance_valid(target) else 0
		for id_variant in _aircraft_records.keys():
			var id := int(id_variant)
			var record: Dictionary = _aircraft_records[id]
			if str(record.get("role", "")) != "GROUND_ATTACK" \
					or int(record.get("assigned_ground_target_id", 0)) != destroyed_id:
				continue
			record["assigned_ground_target_id"] = 0
			record["ground_assignment_index"] = int(record.get("ground_assignment_index", 0)) + 1
			_aircraft_records[id] = record
			call_deferred("_assign_role_stress_helicopter_target", id)
		_try_finish_role_stress_combat()
		return
	# A target may be destroyed by the other aircraft while this pilot still owns
	# it. Re-open only those stale mission slots so the remaining emplacements are
	# assigned without disturbing a valid attack already in progress.
	for id_variant in _aircraft_records.keys():
		var id := int(id_variant)
		var record: Dictionary = _aircraft_records[id]
		if int(record.get("team", 0)) != 1 or not bool(record.get("alive", false)):
			continue
		var pilot: Node = record.get("pilot", null)
		if not is_instance_valid(pilot):
			continue
		var assigned_target: Variant = pilot.get("combat_target")
		if assigned_target != target:
			continue
		record["ground_assignment_index"] = int(record.get("ground_assignment_index", 0)) + 1
		record["ground_mission_assigned"] = false
		_aircraft_records[id] = record
		if pilot.has_method("set_target"):
			pilot.call("set_target", null)
	if _ground_wave_destroyed >= 4 and _stage == Stage.GROUND_STRIKE:
		if _isolated_ground_attack_mode:
			_log("GROUND_WAVE_COMPLETE wave=%d total_destroyed=%d; spawning a relocated wave" % [
				_ground_wave_index,
				_ground_targets_destroyed,
			])
			call_deferred("_spawn_next_ground_wave")
		elif _full_cycle_mode and full_cycle_skip_enemy_air:
			_begin_recovery("ground targets eliminated; enemy air phase skipped")
		else:
			_begin_air_combat("ground targets eliminated")


func _spawn_next_ground_wave() -> void:
	if not _isolated_ground_attack_mode or _stage != Stage.GROUND_STRIKE:
		return
	await get_tree().process_frame
	if _stage != Stage.GROUND_STRIKE:
		return
	_spawn_ground_targets()
	if _ground_targets.size() != 4:
		_log("ERROR ground wave %d spawned %d/4 targets" % [_ground_wave_index, _ground_targets.size()])
		return
	for id_variant in _aircraft_records.keys():
		var id := int(id_variant)
		var record: Dictionary = _aircraft_records[id]
		if int(record.get("team", 0)) != 1 or not bool(record.get("alive", false)):
			continue
		record["ground_mission_assigned"] = false
		_aircraft_records[id] = record
		var pilot: Node = record.get("pilot", null)
		if is_instance_valid(pilot):
			var wave_weapon := "" if isolated_ground_weapon_focus == "Rotate" \
				else _ground_wave_weapon_type(_ground_wave_index)
			if pilot.has_method("set_ground_attack_forced_weapon_type"):
				pilot.call("set_ground_attack_forced_weapon_type", wave_weapon)
			else:
				pilot.set("ground_attack_forced_weapon_type", wave_weapon)
			pilot.set(
				"ground_attack_weapon_rotation",
				_isolated_ground_weapon_rotation() if isolated_ground_weapon_focus == "Rotate" \
					else PackedStringArray()
			)
			if pilot.has_method("set_target"):
				pilot.call("set_target", null)
	_log("GROUND_WAVE_READY wave=%d targets=4 weapons=%s unlimited_ammunition=true" % [
		_ground_wave_index,
		_isolated_ground_weapon_profile_label(),
	])


func _complete_isolated_ground_attack(reason: String) -> void:
	if _stage != Stage.GROUND_STRIKE:
		return
	for record_variant in _live_aircraft_for_team(1):
		var record: Dictionary = record_variant
		var pilot: Node = record.get("pilot", null)
		if is_instance_valid(pilot) and pilot.has_method("set_target"):
			pilot.call("set_target", null)
		if is_instance_valid(pilot):
			pilot.set_process(false)
			pilot.set_physics_process(false)
		var craft: RigidBody3D = record.get("craft", null) as RigidBody3D
		if is_instance_valid(craft):
			craft.linear_velocity = Vector3.ZERO
			craft.angular_velocity = Vector3.ZERO
			craft.freeze = true
	_stage = Stage.COMPLETE
	_log("COMPLETE isolated ground attack: %s; waves=%d total_targets=%d current_wave=%d/4 friendly_alive=%d" % [
		reason,
		_ground_wave_index,
		_ground_targets_destroyed,
		_ground_wave_destroyed,
		_live_aircraft_for_team(1).size(),
	])


func _begin_air_combat(reason: String) -> void:
	if _stage != Stage.GROUND_STRIKE:
		return
	_stage = Stage.AIR_COMBAT
	_stage_started_s = _elapsed_s
	_log("PHASE %s; spawning enemy flight" % reason)
	call_deferred("_spawn_enemy_flight")


func _ensure_friendly_force() -> void:
	if not continuous_intercept_mode or _stage != Stage.AIR_COMBAT or not is_instance_valid(_fdm):
		return
	var live_count := _live_aircraft_for_team(1).size()
	var missing := maxi(
		continuous_friendly_count - live_count - _friendly_launch_requests_outstanding,
		0
	)
	if missing <= 0:
		return
	_ensure_fighter_hangar_stock(missing)
	var fighter_stock := _fighter_hangar_stock()
	var request_count := mini(missing, fighter_stock)
	if request_count <= 0:
		_log("INTERCEPT_REPLACEMENT_BLOCKED no fighter/pilot available live=%d requested=%d" % [
			live_count, _friendly_launch_requests_outstanding,
		])
		return
	var queued := int(_fdm.call("queue_ai_flight", request_count, self, INTERCEPT_LOADOUT_PROFILE))
	_friendly_launch_requests_outstanding += queued
	_log("INTERCEPT_LAUNCH_ORDER queued=%d live=%d outstanding=%d fighter_stock=%d loadout=Guns" % [
		queued, live_count, _friendly_launch_requests_outstanding, fighter_stock,
	])


func _ensure_fighter_hangar_stock(required: int) -> void:
	if not is_instance_valid(_fdm) or not _fdm.has_method("_make_stored_aircraft_entry"):
		return
	var stored_variant: Variant = _fdm.get("stored_aircraft")
	if not (stored_variant is Array):
		return
	var stored: Array = stored_variant
	var needed := maxi(required - _fighter_hangar_stock(), 0)
	var added := 0
	for _i in range(needed):
		_reserve_aircraft_serial += 1
		var entry_variant: Variant = _fdm.call(
			"_make_stored_aircraft_entry",
			"CombatReserve_Aircraft_5_%d" % _reserve_aircraft_serial,
			null,
			FRIENDLY_SCENE_PATH
		)
		if not (entry_variant is Dictionary) or (entry_variant as Dictionary).is_empty():
			break
		stored.append(entry_variant)
		added += 1
	if added > 0:
		_fdm.set("stored_aircraft", stored)
		_log("INTERCEPT_HANGAR_REPLENISHED fighters=%d added=%d" % [
			_fighter_hangar_stock(), added,
		])


func _fighter_hangar_stock() -> int:
	if not is_instance_valid(_fdm):
		return 0
	var stored_variant: Variant = _fdm.get("stored_aircraft")
	if not (stored_variant is Array):
		return 0
	var count := 0
	for entry_variant in stored_variant:
		if not (entry_variant is Dictionary):
			continue
		var aircraft_name := str((entry_variant as Dictionary).get("name", ""))
		if not aircraft_name.begins_with("Aircraft_11"):
			count += 1
	return count


func _spawn_enemy_flight() -> void:
	if continuous_intercept_mode:
		_ensure_enemy_target_count()
		return
	if _full_cycle_mode:
		_spawn_live_bomber_targets(2)
		return
	_spawn_enemy_targets(2)


func _spawn_live_bomber_targets(count: int) -> int:
	if not is_instance_valid(_carrier):
		return 0
	var outward := _carrier.global_transform.basis.x
	outward.y = 0.0
	outward = outward.normalized() if outward.length_squared() > 0.001 else Vector3.RIGHT
	var lateral := _carrier.global_transform.basis.z
	lateral.y = 0.0
	lateral = lateral.normalized() if lateral.length_squared() > 0.001 else Vector3.FORWARD
	var base := _carrier.global_position + outward * full_cycle_enemy_range_from_carrier_m
	var enemies: Array[RigidBody3D] = []
	for i in range(maxi(count, 0)):
		_enemy_spawn_serial += 1
		var lane_fraction := float(i) - float(maxi(count, 1) - 1) * 0.5
		var pos := base + lateral * lane_fraction * enemy_pair_spacing_m
		pos.y = _ground_height(pos) + enemy_altitude_agl_m
		var enemy := _spawn_live_bomber(_enemy_spawn_serial, pos, -outward)
		if enemy != null:
			enemies.append(enemy)
	_log("ENEMY_FLIGHT spawned=%d type=Aircraft_4 mode=planned_bomb_strike target=carrier return=spawn spawn_agl=%.0fm range=%.0fm" % [
		enemies.size(),
		enemy_altitude_agl_m,
		full_cycle_enemy_range_from_carrier_m,
	])
	var friendlies := _live_aircraft_for_team(1)
	for i in range(friendlies.size()):
		if enemies.is_empty():
			break
		var record: Dictionary = friendlies[i]
		var pilot: Node = record.get("pilot", null)
		if is_instance_valid(pilot):
			pilot.set("ground_attack_enabled", false)
			var assigned_enemy: RigidBody3D = enemies[i % enemies.size()]
			var intercept_task: Variant = AirTaskModel.intercept_target(assigned_enemy)
			var assigned: bool = pilot.has_method("assign_air_task") \
				and bool(pilot.call("assign_air_task", intercept_task))
			if not assigned:
				pilot.call("set_target", assigned_enemy)
			_log("ORDER %s intercept %s track=%s" % [
				_pilot_aircraft_name(pilot),
				assigned_enemy.name,
				"controller" if assigned else "visual_fallback",
			])
	_refresh_all_gun_targets()
	return enemies.size()


func _spawn_live_bomber(index: int, pos: Vector3, inbound_direction: Vector3) -> RigidBody3D:
	var craft := ENEMY_SCENE.instantiate() as RigidBody3D
	if craft == null:
		_log("ERROR unable to instantiate live bomber %d" % index)
		return null
	craft.name = "Combat_Enemy_Bomber_%d" % index
	get_tree().current_scene.add_child(craft)
	craft.set("team", 2)
	craft.add_to_group("ai_aircraft")
	craft.add_to_group("enemies")
	craft.set_meta("carrier_combat_test", true)
	craft.set_meta("carrier_combat_spawn_point", pos)
	craft.set_meta("carrier_transport_mode", false)
	craft.remove_meta("controls_disabled")
	var toward_carrier := inbound_direction
	toward_carrier.y = 0.0
	toward_carrier = toward_carrier.normalized() if toward_carrier.length_squared() > 0.001 else Vector3.LEFT
	craft.global_transform = Transform3D(_basis_from_forward(toward_carrier), pos)
	craft.linear_velocity = toward_carrier * enemy_initial_speed_mps
	craft.angular_velocity = Vector3.ZERO
	craft.freeze = false
	craft.sleeping = false
	var toggle: Node = craft.find_child("AIToggle", true, false)
	if toggle != null and toggle.has_method("enable_ai"):
		toggle.call("enable_ai")
	var pilot: Node = craft.find_child("AIPilot", true, false)
	_configure_pilot(pilot, false)
	if is_instance_valid(pilot):
		pilot.set("carrier_position", _carrier.global_position)
		pilot.set("target_altitude", pos.y)
		pilot.set("patrol_altitude_m", pos.y)
		pilot.set("target_speed", maxf(enemy_initial_speed_mps, 90.0))
		pilot.set("dogfight_enabled", false)
		pilot.set("dogfight_proximity_override_m", 0.0)
		pilot.set("ground_attack_enabled", true)
		pilot.set("ground_attack_forced_weapon_type", "Bomb")
		pilot.set("ground_attack_weapon_rotation", PackedStringArray())
		# The 6 km bomber mission benefits from the same terrain-aware 3D planner used
		# by recovery and long routes. The short friendly strike disables this only to
		# avoid replacing its already-compact ingress while an async job completes.
		pilot.set("aircraft_heightmap_pathfinding_enabled", true)
	_register_aircraft(craft, pilot, 2)
	_configure_weapon_logging(craft)
	_select_aircraft_weapon(craft, "Bomb")
	_stow_gear_retry(craft, 0)
	_remove_player_group_deferred(craft)
	if is_instance_valid(pilot):
		var strike_task: Variant = AirTaskModel.attack_target_and_return(
			_carrier,
			pos,
			maxf(enemy_initial_speed_mps, 90.0),
			350.0
		)
		strike_task.requested_altitude_m = pos.y
		strike_task.metadata["mission"] = "carrier_bomb_strike"
		strike_task.metadata["spawn_point"] = pos
		if not pilot.has_method("assign_air_task") \
				or not bool(pilot.call("assign_air_task", strike_task)):
			pilot.call("set_target", _carrier)
	_log("SPAWN %s pos=%s speed=%.1fm/s loadout=%s target=%s defensive_turret=active" % [
		craft.name,
		_fmt(pos),
		enemy_initial_speed_mps,
		_describe_loadout(craft),
		_carrier.name,
	])
	return craft


func _select_aircraft_weapon(craft: RigidBody3D, requested_type: String) -> void:
	var control_weapons: Node = craft.find_child("ControlWeapons", true, false)
	if not is_instance_valid(control_weapons):
		return
	if control_weapons.has_method("find_hardpoints"):
		control_weapons.call("find_hardpoints")
	if control_weapons.has_method("categorize_weapons"):
		control_weapons.call("categorize_weapons")
	var weapon_types_variant: Variant = control_weapons.get("weapon_types")
	if typeof(weapon_types_variant) not in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		return
	var index: int = int(weapon_types_variant.find(requested_type))
	if index < 0:
		return
	control_weapons.set("selected_weapon_type_index", index)
	control_weapons.set("selected_weapon_type", weapon_types_variant[index])


func _ensure_enemy_target_count() -> void:
	if not continuous_intercept_mode or _stage != Stage.AIR_COMBAT:
		return
	var missing := maxi(continuous_enemy_count - _live_aircraft_for_team(2).size(), 0)
	if missing <= 0:
		_assign_missing_intercept_targets()
		return
	var spawned := _spawn_enemy_targets(missing)
	_log("INTERCEPT_TARGET_REPLACEMENT requested=%d spawned=%d live=%d" % [
		missing, spawned, _live_aircraft_for_team(2).size(),
	])
	_assign_missing_intercept_targets()


func _spawn_enemy_targets(count: int) -> int:
	if not is_instance_valid(_carrier):
		return 0
	var outward := _carrier.global_transform.basis.x
	outward.y = 0.0
	if outward.length_squared() < 0.001:
		outward = Vector3.RIGHT
	outward = outward.normalized()
	var lateral := _carrier.global_transform.basis.z
	lateral.y = 0.0
	lateral = lateral.normalized() if lateral.length_squared() > 0.001 else Vector3.FORWARD
	var base := _carrier.global_position + outward * enemy_range_from_carrier_m
	base.y = _ground_height(base) + enemy_altitude_agl_m
	var enemies: Array[RigidBody3D] = []
	for _i in range(maxi(count, 0)):
		_enemy_spawn_serial += 1
		var lane_index := (_enemy_spawn_serial - 1) % maxi(continuous_enemy_count if continuous_intercept_mode else 2, 1)
		var lane_fraction := float(lane_index) - float(maxi(continuous_enemy_count if continuous_intercept_mode else 2, 1) - 1) * 0.5
		var lane_offset := lateral * lane_fraction * enemy_pair_spacing_m
		var pos := base + lane_offset
		pos.y = _ground_height(pos) + enemy_altitude_agl_m
		var enemy := _spawn_enemy(_enemy_spawn_serial, pos, -outward, lane_offset)
		if enemy != null:
			enemies.append(enemy)
	_log("ENEMY_FLIGHT spawned=%d type=Aircraft_4 mode=kinematic_constant_altitude_return spawn_agl=%.0fm range=%.0fm" % [
		enemies.size(), enemy_altitude_agl_m, enemy_range_from_carrier_m,
	])
	if not continuous_intercept_mode:
		var friendlies := _live_aircraft_for_team(1)
		for i in range(friendlies.size()):
			if enemies.is_empty():
				break
			var record: Dictionary = friendlies[i]
			var pilot: Node = record.get("pilot", null)
			if is_instance_valid(pilot):
				pilot.set("ground_attack_enabled", false)
				pilot.call("set_target", enemies[i % enemies.size()])
	_refresh_all_gun_targets()
	return enemies.size()


func _assign_missing_intercept_targets() -> void:
	# This applies to both the endless intercept gym and the full-cycle scenario.
	# Air targets are deliberately non-exclusive: when only one bomber remains,
	# every fighter whose previous target died should join the attack on it.
	if _stage != Stage.AIR_COMBAT:
		return
	var enemies := _live_aircraft_for_team(2)
	if enemies.is_empty():
		return
	var next_enemy := 0
	for record_variant in _live_aircraft_for_team(1):
		var record: Dictionary = record_variant
		var pilot: Node = record.get("pilot", null)
		if not is_instance_valid(pilot):
			continue
		var state := int(pilot.get("current_state"))
		if state in [AIPilot.State.IDLE, AIPilot.State.LAUNCHING]:
			continue
		var craft_variant: Variant = record.get("craft", null)
		var climb_rate_settled := is_instance_valid(craft_variant) \
				and craft_variant is RigidBody3D \
				and absf((craft_variant as RigidBody3D).linear_velocity.y) <= 4.0
		if state == AIPilot.State.CLIMBING and not climb_rate_settled:
			continue
		var current_target: Variant = pilot.get("combat_target")
		if _is_live_enemy_target(current_target):
			continue
		var enemy_record: Dictionary = enemies[next_enemy % enemies.size()]
		next_enemy += 1
		var target: Variant = enemy_record.get("craft", null)
		if not is_instance_valid(target):
			continue
		pilot.set("ground_attack_enabled", false)
		pilot.call("set_target", target)
		_log("ORDER %s intercept %s" % [_pilot_aircraft_name(pilot), (target as Node).name])
	_refresh_all_gun_targets()


func _is_live_enemy_target(target: Variant) -> bool:
	if not is_instance_valid(target) or not (target is Node):
		return false
	var record: Dictionary = _aircraft_records.get((target as Node).get_instance_id(), {})
	return int(record.get("team", 0)) == 2 and bool(record.get("alive", false))


func _spawn_enemy(index: int, pos: Vector3, inbound_direction: Vector3, lane_offset: Vector3) -> RigidBody3D:
	var craft := ENEMY_SCENE.instantiate() as RigidBody3D
	if craft == null:
		_log("ERROR unable to instantiate Enemy_%d" % index)
		return null
	craft.name = "Combat_Enemy_%d" % index
	get_tree().current_scene.add_child(craft)
	craft.set("team", 2)
	craft.add_to_group("ai_aircraft")
	craft.add_to_group("enemies")
	craft.set_meta("carrier_combat_test", true)
	craft.set_meta("carrier_transport_mode", false)
	craft.set_meta("controls_disabled", true)
	craft.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	craft.freeze = true
	var toward_carrier := inbound_direction
	toward_carrier.y = 0.0
	toward_carrier = toward_carrier.normalized() if toward_carrier.length_squared() > 0.001 else Vector3.LEFT
	craft.global_transform = Transform3D(_basis_from_forward(toward_carrier), pos)
	craft.linear_velocity = toward_carrier * enemy_initial_speed_mps
	craft.angular_velocity = Vector3.ZERO
	var toggle: Node = craft.find_child("AIToggle", true, false)
	if toggle != null and toggle.has_method("enable_ai"):
		toggle.call("enable_ai")
	var pilot: Node = craft.find_child("AIPilot", true, false)
	_configure_pilot(pilot, false)
	_register_aircraft(craft, pilot, 2)
	_configure_enemy_gunnery_rail(craft, pilot, pos, toward_carrier, lane_offset)
	_configure_weapon_logging(craft)
	var turret_disabled := _disable_defensive_turret(craft)
	_stow_gear_retry(craft, 0)
	_remove_player_group_deferred(craft)
	_log("SPAWN %s pos=%s speed=%.1fm/s loadout=%s defensive_turret_disabled=%s" % [craft.name, _fmt(pos), enemy_initial_speed_mps, _describe_loadout(craft), turret_disabled])
	return craft


func _configure_enemy_gunnery_rail(
	craft: RigidBody3D,
	pilot: Node,
	spawn_position: Vector3,
	inbound_direction: Vector3,
	lane_offset: Vector3
) -> void:
	if not is_instance_valid(craft) or not is_instance_valid(_carrier):
		return
	# This test needs a repeatable airborne gunnery target, not a second flight-control
	# problem. Freeze the rigid body and advance it explicitly along a carrier-relative,
	# terrain-following rail. The aircraft remains a collision/damage target.
	if is_instance_valid(pilot):
		pilot.set("dogfight_enabled", false)
		pilot.set("ground_attack_enabled", false)
		pilot.call("set_target", null)
		pilot.set_process(false)
		pilot.set_physics_process(false)
	var flat_inbound := inbound_direction
	flat_inbound.y = 0.0
	flat_inbound = flat_inbound.normalized() if flat_inbound.length_squared() > 0.001 else Vector3.LEFT
	var turn_right := Vector3.UP.cross(flat_inbound).normalized()
	var turn_sign := signf(lane_offset.dot(turn_right))
	if absf(turn_sign) < 0.5:
		turn_sign = 1.0 if craft.get_instance_id() % 2 == 0 else -1.0
	_enemy_rail_tracks[craft.get_instance_id()] = {
		"craft": craft,
		"inbound_direction": flat_inbound,
		"lane_offset": lane_offset,
		"turn_sign": turn_sign,
		"phase": "INBOUND",
		"cruise_altitude_world_y": spawn_position.y,
		"progress_m": 0.0,
		"previous_position": spawn_position,
	}
	_log("ORDER %s kinematic rail spawn_agl=%.0fm altitude_mode=%s speed=%.0fm/s collision_and_damage=enabled" % [
		craft.name,
		enemy_altitude_agl_m,
		"hold_world" if enemy_hold_spawn_world_altitude else "terrain_relative",
		enemy_initial_speed_mps,
	])


func _update_enemy_gunnery_rails(delta: float) -> void:
	if delta <= 0.0 or not is_instance_valid(_carrier):
		return
	for id_variant in _enemy_rail_tracks.keys():
		var id := int(id_variant)
		var track: Dictionary = _enemy_rail_tracks.get(id, {})
		# A destroyed aircraft can remain in this dictionary for one frame as a freed
		# object reference. Validate the Variant before casting it; casting a freed
		# object raises and would otherwise prevent the surviving rails from updating.
		var craft_variant: Variant = track.get("craft", null)
		var record: Dictionary = _aircraft_records.get(id, {})
		if not is_instance_valid(craft_variant) or not (craft_variant is RigidBody3D) \
				or not bool(record.get("alive", false)):
			_enemy_rail_tracks.erase(id)
			continue
		var craft := craft_variant as RigidBody3D
		var inbound: Vector3 = track.get("inbound_direction", Vector3.LEFT)
		var lane_offset: Vector3 = track.get("lane_offset", Vector3.ZERO)
		var progress_m := float(track.get("progress_m", 0.0)) + enemy_initial_speed_mps * delta
		# Fly a complete intercept pattern instead of teleporting back to the inbound
		# spawn point: straight through the carrier area, a broad 180-degree turn,
		# then an outbound leg back to the side of the map it arrived from. The long
		# outbound leg gives a pursuing fighter time to establish a tail shot.
		var past_carrier_m := maxf(enemy_path_past_carrier_m, 500.0)
		var straight_leg_m := enemy_range_from_carrier_m + past_carrier_m
		var turn_radius_m := maxf(enemy_return_turn_radius_m, 250.0)
		var turn_arc_m := PI * turn_radius_m
		var total_path_m := straight_leg_m * 2.0 + turn_arc_m
		if progress_m >= total_path_m:
			record["alive"] = false
			_aircraft_records[id] = record
			_enemy_rail_tracks.erase(id)
			_log("RAIL_COMPLETE aircraft=%s returned_to_arrival_side path=%.0fm despawning" % [
				craft.name, total_path_m,
			])
			craft.queue_free()
			call_deferred("_ensure_enemy_target_count")
			continue

		var turn_right := Vector3.UP.cross(inbound).normalized()
		var turn_sign := signf(float(track.get("turn_sign", 1.0)))
		if absf(turn_sign) < 0.5:
			turn_sign = 1.0
		var turn_start := _carrier.global_position + lane_offset + inbound * past_carrier_m
		var turn_center := turn_start + turn_right * turn_radius_m * turn_sign
		var desired_position: Vector3
		var heading := inbound
		var bank_rad := 0.0
		var phase := "INBOUND"
		if progress_m < straight_leg_m:
			desired_position = _carrier.global_position + lane_offset \
					- inbound * enemy_range_from_carrier_m + inbound * progress_m
		elif progress_m < straight_leg_m + turn_arc_m:
			phase = "TURN"
			var arc_progress_m := progress_m - straight_leg_m
			var arc_fraction := clampf(arc_progress_m / turn_arc_m, 0.0, 1.0)
			var arc_angle := PI * turn_sign * arc_fraction
			var radial_start := -turn_right * turn_radius_m * turn_sign
			desired_position = turn_center + radial_start.rotated(Vector3.UP, arc_angle)
			heading = inbound.rotated(Vector3.UP, arc_angle).normalized()
			bank_rad = -turn_sign * atan2(
				enemy_initial_speed_mps * enemy_initial_speed_mps,
				turn_radius_m * 9.80665
			)
		else:
			phase = "OUTBOUND"
			var outbound_progress_m := progress_m - straight_leg_m - turn_arc_m
			var turn_end := turn_start + turn_right * turn_radius_m * 2.0 * turn_sign
			desired_position = turn_end - inbound * outbound_progress_m
			heading = -inbound
		var previous_phase := str(track.get("phase", "INBOUND"))
		if phase != previous_phase:
			_log("RAIL_PHASE aircraft=%s %s->%s carrier_dist=%.0fm" % [
				craft.name, previous_phase, phase,
				Vector2(desired_position.x - _carrier.global_position.x, desired_position.z - _carrier.global_position.z).length(),
			])
		var previous_position: Vector3 = track.get("previous_position", desired_position)
		if enemy_hold_spawn_world_altitude:
			# Aircraft hold an actual world altitude. Following terrain height exactly
			# made them visibly slide up and down over every ridge and valley.
			desired_position.y = float(track.get("cruise_altitude_world_y", previous_position.y))
		else:
			desired_position.y = _ground_height(desired_position) + enemy_altitude_agl_m
		var observed_delta := desired_position - previous_position
		var horizontal_motion := Vector2(observed_delta.x, observed_delta.z).length()
		var terrain_vertical_speed := 0.0
		# A floating-origin recenter can move every world object by kilometres in one
		# tick. Do not expose that discontinuity as target velocity to gun-lead logic.
		if not enemy_hold_spawn_world_altitude \
				and horizontal_motion <= enemy_initial_speed_mps * delta + 50.0:
			terrain_vertical_speed = clampf(
				observed_delta.y / delta,
				-maxf(enemy_rail_vertical_speed_limit_mps, 1.0),
				maxf(enemy_rail_vertical_speed_limit_mps, 1.0)
			)
		var rail_basis := _basis_from_forward(heading)
		if absf(bank_rad) > 0.001:
			rail_basis = rail_basis.rotated(heading, bank_rad)
		craft.global_transform = Transform3D(rail_basis, desired_position)
		craft.linear_velocity = heading * enemy_initial_speed_mps + Vector3.UP * terrain_vertical_speed
		craft.angular_velocity = Vector3.ZERO
		track["progress_m"] = progress_m
		track["previous_position"] = desired_position
		track["phase"] = phase
		_enemy_rail_tracks[id] = track


func _disable_defensive_turret(craft: RigidBody3D) -> bool:
	var turret_controller: Node = craft.find_child("TurretController", true, false)
	if turret_controller == null:
		return false
	turret_controller.set_physics_process(false)
	turret_controller.set_process(false)
	if turret_controller.has_method("stop_firing"):
		turret_controller.call("stop_firing")
	return true


func _remove_player_group_deferred(craft: RigidBody3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(craft) and craft.is_in_group("aircraft"):
		craft.remove_from_group("aircraft")


func _configure_pilot(pilot: Node, friendly: bool) -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	pilot.set("ground_attack_enabled", friendly and not continuous_intercept_mode and not _rolling_recovery_mode)
	pilot.set("dogfight_enabled", friendly and not _rolling_recovery_mode)
	pilot.set("land_after_launch", false)
	pilot.set("_land_after_climb", false)
	# Friendly damage withdrawals are part of the end-to-end combat/recovery
	# observation now. Enemy test aircraft still remain committed to the fight.
	pilot.set("rtb_health_threshold", 0.5 if friendly else 0.0)
	pilot.set("rtb_fuel_threshold", 0.0)
	pilot.set("sensor_range", 12000.0)
	pilot.set("engagement_radius_from_carrier_m", 0.0)
	pilot.set("disengage_radius_from_carrier_m", 0.0)
	pilot.set("dogfight_max_range_m", 10000.0)
	pilot.set("dogfight_rejoin_range_m", 4500.0)
	pilot.set("skill", 3 if friendly else 2)
	if pilot.has_method("apply_skill_preset"):
		pilot.call("apply_skill_preset")
	# Structure clearance has its own predictive guard. Do not turn the requested
	# 350 m launch height into a 350 m positioning hard floor as well: that made
	# the attack abort the instant a hard bank crossed terrain only a few metres
	# higher than the carrier. The normal terrain lookahead and 220 m emergency
	# floor still retain recovery authority.
	pilot.set("attack_positioning_hard_floor_agl_m", 120.0)
	pilot.set("emergency_min_agl_m", 220.0)
	# Level near the strike altitude before assignment. The generic 600 m carrier
	# climb and the old immediate 300 m-AGL assignment both carried a large positive
	# vertical speed directly into the first attack turn.
	pilot.set("launch_climb_height_above_carrier_m", 350.0)
	pilot.set("launch_climb_capture_vertical_speed_mps", 4.0)
	# Let the assertive turn layer use a genuinely combat-like bank.
	pilot.set("attack_route_bank_limit_deg", 82.0)
	pilot.set("attack_inbound_bank_limit_deg", 35.0)
	pilot.set("attack_ingress_turn_altitude_reserve_m", 220.0)
	# A fixed focus dedicates every pass to one weapon. Rotate exercises the pilot's
	# actual per-pass planner so each aircraft flies Bomb -> Rocket Pod -> Guns and
	# repeats; geometry-only retries do not consume another rotation entry.
	var forced_ground_weapon := ""
	var ground_weapon_rotation := PackedStringArray()
	if friendly and _isolated_ground_attack_mode:
		if isolated_ground_weapon_focus == "Rotate":
			ground_weapon_rotation = _isolated_ground_weapon_rotation()
		else:
			forced_ground_weapon = _ground_wave_weapon_type(_ground_wave_index)
	elif friendly and _full_cycle_mode:
		if _weapon_focus_override_requested and isolated_ground_weapon_focus != "Rotate":
			# A diagnostic full-cycle config can isolate one available weapon while
			# retaining the moving platoon. Normal full-cycle configs omit weapon_focus
			# and continue to exercise their random primary weapon followed by guns.
			forced_ground_weapon = isolated_ground_weapon_focus
		else:
			# Each full-cycle aircraft may carry rockets or bombs, but always has its gun.
			# The rotation planner skips unavailable types, so this becomes Rocket -> Guns
			# or Bomb -> Guns without adding loadout-specific attack-state branches.
			ground_weapon_rotation = _isolated_ground_weapon_rotation()
	pilot.set("ground_attack_forced_weapon_type", forced_ground_weapon)
	pilot.set("ground_attack_weapon_rotation", ground_weapon_rotation)
	if forced_ground_weapon == "Rocket Pod" or ground_weapon_rotation.has("Rocket Pod"):
		_apply_rocket_specialist_aim_genes(pilot)
	# Bombs need a setup -> target -> egress line. Pointing directly at the target
	# from the post-launch climb forced a close-in maximum-bank intercept and made
	# the apparent attack path orbit around the target. The compact ingress below
	# already gives this short scenario a direct, flyable three-leg attack run.
	pilot.set("ground_attack_direct_intercept_enabled", false)
	pilot.set("ground_attack_direct_fire_intercept_enabled", false)
	pilot.set("attack_direct_fire_energy_recovery_start_margin_mps", 20.0)
	pilot.set("attack_direct_fire_energy_recovery_roll_scale", 0.55)
	pilot.set("attack_direct_fire_energy_recovery_yaw_scale", 0.45)
	pilot.set("ground_gun_fire_alignment_deg", 14.0)
	# Fly the complete corridor selected by the geometry planner. Compact ingress
	# discarded the evaluated join leg, so aircraft reached setup from the side and
	# then spent repeated retries failing target-heading and attack-line gates.
	pilot.set("ground_attack_compact_ingress_enabled", false)
	pilot.set("attack_run_distance_m", 1400.0)
	pilot.set("rocket_run_setup_distance_m", 1400.0)
	# Scale the setup and the preceding roll-out leg from the aircraft's actual turn
	# radius. The fixed distances remain floors, not the whole guidance solution.
	pilot.set("attack_setup_distance_turn_radius_scale", 3.25)
	pilot.set("attack_ingress_lineup_turn_radii", 1.75)
	pilot.set("attack_route_flyby_enabled", true)
	pilot.set("attack_run_altitude_offset_m", 300.0)
	pilot.set("attack_pull_up_distance_m", 250.0)
	pilot.set("rocket_pull_up_distance_m", 350.0)
	pilot.set("rocket_attack_commit_min_agl_m", 150.0)
	pilot.set("bomb_run_setup_distance_m", 1400.0)
	pilot.set("bomb_run_setup_altitude_offset_m", 320.0)
	pilot.set("bomb_run_setup_max_altitude_offset_m", 420.0)
	pilot.set("bomb_dive_start_distance_m", 1150.0)
	pilot.set("bomb_pull_up_distance_m", 200.0)
	pilot.set("bomb_release_altitude_window_m", 900.0)
	pilot.set("bomb_release_min_range_m", 220.0)
	pilot.set("bomb_min_dive_angle_deg", 1.0)
	pilot.set("bomb_release_max_bank_deg", 58.0)
	for tolerance_property in [
		"bomb_ccip_release_tolerance_m",
		"bomb_rookie_release_tolerance_m",
		"bomb_experienced_release_tolerance_m",
		"bomb_veteran_release_tolerance_m",
		"bomb_ace_release_tolerance_m",
	]:
		# The repeating range is an accuracy test: wait for the CCIP pipper to cross
		# close to the target instead of releasing the first bomb while it is still
		# 80-90 m short. Integrated sequencing remains finite through its phase timeout.
		pilot.set(tolerance_property, 18.0 if _isolated_ground_attack_mode else 90.0)
	pilot.set("bomb_release_best_miss_slack_m", 6.4)
	pilot.set("bomb_release_after_best_worsen_m", 5.8)
	pilot.set("bomb_release_after_best_grace_m", 14.4)
	pilot.set("bomb_release_best_solution_tolerance_multiplier", 1.15)
	pilot.set("bomb_rookie_release_hold_s", 0.08)
	pilot.set("bomb_experienced_release_hold_s", 0.08)
	pilot.set("bomb_veteran_release_hold_s", 0.08)
	pilot.set("bomb_ace_release_hold_s", 0.08)
	# Clustered ground targets support a two-target pass: after one release the
	# pilot's existing in-pass retargeting can drop on a neighbour without flying
	# another complete setup circuit. Carrier strikes remain one bomb per pass.
	var test_bombs_per_run: int = 2 if (
		_full_cycle_mode
		or (_isolated_ground_attack_mode and isolated_ground_weapon_focus == "Bomb")
	) else 1
	pilot.set("bomb_salvo_per_run", test_bombs_per_run)
	pilot.set("carrier_bomb_salvo_per_run", 1)
	pilot.set("bomb_release_spacing_s", 0.45)
	# A run is only "inbound" once the aircraft has joined the planned attack
	# line. The old 2.2 km cross-track and 0.20 dot gates admitted approaches
	# nearly perpendicular to it, bypassing the compact setup -> target route.
	pilot.set("bomb_direct_entry_max_cross_track_m", 450.0)
	pilot.set("bomb_direct_entry_max_altitude_overshoot_m", 420.0)
	pilot.set("bomb_positioning_commit_min_lane_m", 800.0)
	pilot.set("attack_positioning_direct_entry_after_s", 2.0)
	pilot.set("attack_positioning_direct_entry_range_buffer_m", 450.0)
	pilot.set("attack_positioning_direct_entry_min_dot", 0.70)
	pilot.set("attack_positioning_direct_entry_min_planned_dot", 0.78)
	# The targets are clustered, so a full bomber-sized egress turns every follow-up
	# into a several-kilometre racetrack. Keep roughly one Aircraft_5 turn radius
	# plus recovery margin, then let it establish the next inbound leg.
	pilot.set("attack_egress_distance_m", 1350.0)
	pilot.set("attack_break_off_distance_m", 500.0)
	pilot.set("attack_breakoff_completion_radius_m", 500.0)
	pilot.set("attack_breakoff_max_time_s", 13.0)
	# Preserve the proven 32 m release standard while the solution is improving.
	# If it never arrives, force a drop at 425 m so a viable quick pass still
	# produces action before the terrain-recovery gate begins its pull-up.
	# Combat validation showed the solution improving from 93.5 m at 500 m range
	# to 53.6 m at 457 m, so 500 m was pre-empting the accurate release window.
	pilot.set("bomb_gameplay_release_range_m", 650.0)
	pilot.set("bomb_gameplay_release_tolerance_m", 18.0 if _isolated_ground_attack_mode else 32.0)
	pilot.set("bomb_gameplay_force_release_range_m", 0.0 if _isolated_ground_attack_mode else 425.0)
	# At two kilometres the asynchronous heightmap departure route is counterproductive:
	# it can send the aircraft several kilometres straight away while the route job runs.
	# Use the pilot's direct attack legs, which still retain terrain sampling and avoidance.
	pilot.set("aircraft_heightmap_pathfinding_enabled", false)
	pilot.set("attack_route_direct_waypoint_steering", false)


func _apply_rocket_specialist_aim_genes(pilot: Node) -> void:
	if not _rocket_specialist_loaded:
		_rocket_specialist_loaded = true
		var file := FileAccess.open(PROJECT_ROCKET_SPECIALIST_PATH, FileAccess.READ)
		if file == null:
			_log("WARNING rocket specialist seed could not be opened: %s" % PROJECT_ROCKET_SPECIALIST_PATH)
			return
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			var genome_variant: Variant = (parsed as Dictionary).get("genome", {})
			if genome_variant is Dictionary:
				_rocket_specialist_genome = (genome_variant as Dictionary).duplicate(true)
	if _rocket_specialist_genome.is_empty():
		_log("WARNING rocket specialist seed has no genome: %s" % PROJECT_ROCKET_SPECIALIST_PATH)
		return
	# The recovered champion also contains navigation genes from its old test course.
	# Those are intentionally excluded: only reconnect the seven genes that tune the
	# rocket CCIP overlay used by the current aircraft controller.
	var gene_to_property := {
		"rocket_ccip_pitch_gain": "rocket_ccip_pitch_gain",
		"rocket_ccip_yaw_gain": "rocket_ccip_yaw_gain",
		"rocket_ccip_pitch_damp": "rocket_ccip_pitch_rate_damping",
		"rocket_ccip_yaw_damp": "rocket_ccip_yaw_rate_damping",
		"rocket_ccip_max_pitch": "rocket_ccip_max_pitch_input",
		"rocket_ccip_max_yaw": "rocket_ccip_max_yaw_input",
		"rocket_ccip_smooth": "rocket_ccip_aim_smoothing",
	}
	for gene: String in gene_to_property:
		if not _rocket_specialist_genome.has(gene):
			continue
		var property_name: String = str(gene_to_property[gene])
		var gene_value: float = float(_rocket_specialist_genome[gene])
		# Legacy rocket specialists evolved against the old signed pitch-gain
		# convention. The controller now defines this property as an unsigned
		# response magnitude, so retain the evolved strength without restoring
		# the feedback inversion.
		if gene == "rocket_ccip_pitch_gain":
			gene_value = absf(gene_value)
		pilot.set(property_name, gene_value)
	_log("ROCKET_SPECIALIST applied source=%s genes=%d" % [
		PROJECT_ROCKET_SPECIALIST_PATH,
		gene_to_property.size(),
	])


func _register_aircraft(craft: RigidBody3D, pilot: Node, team: int) -> void:
	var id := craft.get_instance_id()
	_aircraft_records[id] = {
		"craft": craft,
		"pilot": pilot,
		"name": craft.name,
		"team": team,
		"alive": true,
		"last_state": -1,
		"last_target_id": 0,
		"last_commit_reason": "",
		"gun_hits": 0,
		"gun_misses": 0,
		"last_gun_shot_s": -100.0,
	}
	if craft.has_signal("damaged"):
		craft.connect("damaged", Callable(self, "_on_aircraft_damaged").bind(id))
	if craft.has_signal("destroyed"):
		craft.connect("destroyed", Callable(self, "_on_aircraft_destroyed").bind(id), CONNECT_ONE_SHOT)
	if craft.has_signal("crashed"):
		craft.connect("crashed", Callable(self, "_on_aircraft_crashed").bind(id))


func _on_aircraft_damaged(amount: float, health: float, id: int) -> void:
	var record: Dictionary = _aircraft_records.get(id, {})
	_log("HIT aircraft=%s team=%d damage=%.1f hp=%.1f" % [record.get("name", "unknown"), int(record.get("team", 0)), amount, health])
	if int(record.get("team", 0)) != 1 or bool(record.get("health_rtb_threshold_logged", false)):
		return
	var craft_variant: Variant = record.get("craft", null)
	var pilot_variant: Variant = record.get("pilot", null)
	if not is_instance_valid(craft_variant) or not (craft_variant is RigidBody3D) \
			or not is_instance_valid(pilot_variant):
		return
	var maximum_variant: Variant = (craft_variant as RigidBody3D).get("max_health")
	var threshold_variant: Variant = pilot_variant.get("rtb_health_threshold")
	if typeof(maximum_variant) not in [TYPE_FLOAT, TYPE_INT] \
			or typeof(threshold_variant) not in [TYPE_FLOAT, TYPE_INT]:
		return
	var maximum_health := float(maximum_variant)
	var threshold := float(threshold_variant)
	if maximum_health <= 0.0 or threshold <= 0.0 or health / maximum_health >= threshold:
		return
	record["health_rtb_threshold_logged"] = true
	_aircraft_records[id] = record
	_log("HEALTH_RTB aircraft=%s hp=%.1f/%.1f threshold=%.0f%% pilot_state=%s" % [
		record.get("name", "unknown"),
		health,
		maximum_health,
		threshold * 100.0,
		_ops_state_name(pilot_variant as Node, str(record.get("ops_domain", "fixed_wing"))),
	])


func _on_aircraft_destroyed(id: int) -> void:
	var record: Dictionary = _aircraft_records.get(id, {})
	if not bool(record.get("alive", false)):
		return
	var diagnostics := _aircraft_diagnostics(record)
	record["alive"] = false
	_aircraft_records[id] = record
	var team := int(record.get("team", 0))
	if team == 1:
		_friendly_destroyed_count += 1
	_log("DESTROYED aircraft=%s team=%d %s" % [record.get("name", "unknown"), team, diagnostics])
	if _role_stress_mode:
		if team == 2:
			_enemy_kills += 1
			_log("ROLE_SCORE enemy_air_kills=%d/2 ground_vehicle_kills=%d/4" % [
				_enemy_kills,
				_ground_targets_destroyed,
			])
			call_deferred("_assign_role_stress_intercepts")
			call_deferred("_try_finish_role_stress_combat")
		elif team == 1 and _live_aircraft_for_team(1).is_empty():
			_stage = Stage.COMPLETE
			_log("FAILED role stress: all friendly aircraft lost")
		return
	if _rolling_recovery_mode and _stage == Stage.ROLLING and team == 1:
		record["rolling_status"] = "lost"
		_aircraft_records[id] = record
		_rolling_losses += 1
		_log("ROLLING_LOSS aircraft=%s reason=destroyed losses=%d active=%d" % [
			record.get("name", "unknown"), _rolling_losses, _rolling_active_aircraft_count(),
		])
		if rolling_finite_cohort:
			_stage = Stage.COMPLETE
			_log("FAILED rolling finite cohort; traps=%d/%d losses=%d launches=%d reason=destroyed" % [
				_rolling_traps, rolling_target_traps, _rolling_losses, _friendly_launches,
			])
			return
		call_deferred("_request_recovery_test_launches")
		return
	if continuous_intercept_mode and _stage == Stage.AIR_COMBAT:
		if team == 2:
			_enemy_kills += 1
			_enemy_rail_tracks.erase(id)
			call_deferred("_ensure_enemy_target_count")
		elif team == 1:
			_friendly_losses += 1
			call_deferred("_ensure_friendly_force")
		_log("INTERCEPT_SCORE kills=%d friendly_losses=%d" % [_enemy_kills, _friendly_losses])
		return
	if _stage == Stage.GROUND_STRIKE and _friendly_launches >= 2 and _live_aircraft_for_team(1).is_empty():
		_stage = Stage.COMPLETE
		_log("COMPLETE friendly strike flight eliminated before ground targets were destroyed")
	_check_air_combat_end()
	_check_recovery_end()


func _on_aircraft_crashed(impact_velocity: float, id: int) -> void:
	var record: Dictionary = _aircraft_records.get(id, {})
	if int(record.get("team", 0)) == 1 and not bool(record.get("crash_recorded", false)):
		record["crash_recorded"] = true
		_aircraft_records[id] = record
		_friendly_crash_count += 1
	_log("CRASH aircraft=%s team=%d impact_speed=%.1fm/s %s" % [record.get("name", "unknown"), int(record.get("team", 0)), impact_velocity, _aircraft_diagnostics(record)])
	if _rolling_recovery_mode and _stage == Stage.ROLLING \
			and int(record.get("team", 0)) == 1 and bool(record.get("alive", false)):
		record["alive"] = false
		record["rolling_status"] = "lost"
		_aircraft_records[id] = record
		_rolling_losses += 1
		_log("ROLLING_LOSS aircraft=%s reason=crash losses=%d active=%d" % [
			record.get("name", "unknown"), _rolling_losses, _rolling_active_aircraft_count(),
		])
		if rolling_finite_cohort:
			_stage = Stage.COMPLETE
			_log("FAILED rolling finite cohort; traps=%d/%d losses=%d launches=%d reason=crash" % [
				_rolling_traps, rolling_target_traps, _rolling_losses, _friendly_launches,
			])
			return
		call_deferred("_request_recovery_test_launches")


func _check_air_combat_end() -> void:
	if _stage != Stage.AIR_COMBAT:
		return
	if continuous_intercept_mode:
		return
	var friendlies_alive := _live_aircraft_for_team(1).size()
	var enemies_alive := _live_aircraft_for_team(2).size()
	if enemies_alive == 0:
		_begin_recovery("enemy flight eliminated")
	elif friendlies_alive == 0:
		_stage = Stage.COMPLETE
		_log("COMPLETE friendly flight eliminated; no aircraft available to recover")
	else:
		# A destroyed bandit invalidates only the pilots assigned to that bandit.
		# Immediately retask those free fighters onto the survivors; do not reserve
		# an air target for a single attacker.
		call_deferred("_assign_missing_intercept_targets")


func _begin_recovery(reason: String) -> void:
	if _stage == Stage.RECOVERY or _stage == Stage.COMPLETE:
		return
	_stage = Stage.RECOVERY
	_stage_started_s = _elapsed_s
	_retire_remaining_gunnery_targets()
	_log("PHASE recovery reason=%s" % reason)
	for record_variant in _live_aircraft_for_team(1):
		var record: Dictionary = record_variant
		var pilot: Node = record.get("pilot", null)
		var craft: Variant = record.get("craft", null)
		if not is_instance_valid(pilot) or not is_instance_valid(craft):
			continue
		var id: int = (craft as Node).get_instance_id()
		_recovery_requested[id] = true
		pilot.set("ground_attack_enabled", false)
		# Ground-attack configuration deliberately disables asynchronous heightmap
		# routing so a short ingress is not replaced by a several-kilometre detour.
		# Recovery is the opposite problem: it needs the terrain-aware 3D arrival
		# route into the carrier's authored final corridor. Restore that controller
		# before start_recovery() atomically clears the target, combat task, and old
		# planner ownership. Calling set_target(null) here used to insert a transient
		# SEARCH state while those stale owners were still live.
		pilot.set("aircraft_heightmap_pathfinding_enabled", true)
		pilot.set("approach_route_threaded", true)
	if _try_hold_carrier_for_recovery():
		_dispatch_recovery_orders()
	else:
		_log("RECOVERY_ORDER pending until carrier locks a terrain-clear pose")


func _dispatch_recovery_orders() -> void:
	if _recovery_orders_dispatched:
		return
	_recovery_orders_dispatched = true
	for id_variant in _recovery_requested.keys():
		var record: Dictionary = _aircraft_records.get(int(id_variant), {})
		if not bool(record.get("alive", false)):
			continue
		var pilot: Node = record.get("pilot", null)
		if not is_instance_valid(pilot):
			continue
		var accepted: bool = bool(pilot.call("start_recovery")) \
			if pilot.has_method("start_recovery") else false
		_log("RECOVERY_ORDER aircraft=%s accepted=%s pathfinding=3D_threaded condition={%s}" % [
			record.get("name", "unknown"),
			str(accepted),
			_recovery_condition_diagnostics(record),
		])


func _try_hold_carrier_for_recovery() -> bool:
	# The full-cycle carrier should move throughout launch and combat, but a landing
	# corridor verified at recovery start is not guaranteed to remain clear if the
	# carrier drives on for the several minutes needed to recover a queued pair.
	# Freeze only after the live FlightDeckManager terrain check says the current
	# authored final is clear; until then the aircraft can safely remain in recovery hold.
	if not _full_cycle_mode or _carrier_held_for_recovery:
		return _carrier_held_for_recovery
	if not is_instance_valid(_carrier) \
			or not _carrier.has_method("set_heli_test_stationary") \
			or not is_instance_valid(_fdm) \
			or not _fdm.has_method("_landing_path_clear_of_terrain"):
		return false
	if not bool(_fdm.call("_landing_path_clear_of_terrain", true)):
		if not _carrier_recovery_hold_wait_logged:
			_carrier_recovery_hold_wait_logged = true
			_log("CARRIER_RECOVERY_HOLD waiting for terrain-clear final corridor")
		return false
	_carrier.call("set_heli_test_stationary", true)
	_carrier_held_for_recovery = true
	_log("CARRIER_RECOVERY_HOLD engaged at terrain-clear pose")
	return true


func _retire_remaining_gunnery_targets() -> void:
	# Once recovery starts, surviving test targets have no mission role. Remove them
	# before clearing the friendly pilots' targets so the landing phase contains only
	# the carrier and recovering aircraft.
	var retired := 0
	for id_variant in _enemy_rail_tracks.keys():
		var id := int(id_variant)
		var track: Dictionary = _enemy_rail_tracks.get(id, {})
		var craft_variant: Variant = track.get("craft", null)
		var record: Dictionary = _aircraft_records.get(id, {})
		if bool(record.get("alive", false)):
			record["alive"] = false
			_aircraft_records[id] = record
			retired += 1
		if is_instance_valid(craft_variant):
			(craft_variant as Node).queue_free()
	_enemy_rail_tracks.clear()
	if retired > 0:
		_log("ENEMY_FLIGHT retired=%d for carrier recovery" % retired)


func _connect_arresting_cables() -> void:
	for cable in get_tree().get_nodes_in_group("arresting_cable"):
		if is_instance_valid(cable) and cable.has_signal("cable_engaged"):
			var callback := Callable(self, "_on_cable_engaged").bind(cable)
			if not cable.is_connected("cable_engaged", callback):
				cable.connect("cable_engaged", callback)


func _on_cable_engaged(aircraft_variant: Variant, cable: Node) -> void:
	if not is_instance_valid(aircraft_variant) or not (aircraft_variant is RigidBody3D):
		return
	var craft := aircraft_variant as RigidBody3D
	var id := craft.get_instance_id()
	if not _aircraft_records.has(id):
		return
	if _stage == Stage.COMPLETE:
		_log("LANDING_LATE ignored aircraft=%s reason=test_already_complete" % craft.name)
		return
	var wire: int = int(cable.call("get_wire_number")) if is_instance_valid(cable) and cable.has_method("get_wire_number") else -1
	var lateral: float = float(cable.call("get_engage_lateral_m")) if is_instance_valid(cable) and cable.has_method("get_engage_lateral_m") else NAN
	_log("LANDING caught aircraft=%s wire=%d lateral=%.2fm speed=%.1fm/s" % [craft.name, wire, lateral, craft.linear_velocity.length()])
	if _rolling_recovery_mode and _stage == Stage.ROLLING:
		if _desert_recovery_mode:
			_record_desert_recovery_stage(id, "confirmed_landing", "wire=%d lateral=%.2fm" % [wire, lateral])
		_record_rolling_recovery(craft, wire, lateral, "fixed_wing")
		return
	_caught_aircraft[id] = true
	_check_recovery_end()


func _record_rolling_recovery(
	craft: RigidBody3D,
	wire: int,
	lateral: float,
	recovery_type: String
) -> void:
	if not is_instance_valid(craft):
		return
	var id := craft.get_instance_id()
	if _caught_aircraft.has(id):
		return
	_caught_aircraft[id] = true
	var record: Dictionary = _aircraft_records.get(id, {})
	# A safely landed aircraft no longer occupies an active airborne slot. The deck
	# manager may subsequently store and free it, so stop harness polling now.
	record["alive"] = false
	record["rolling_status"] = "caught"
	_aircraft_records[id] = record
	OperationsCoordinator.clear_order(craft)
	_rolling_traps += 1
	var recovery_started_s := float(record.get("rolling_recovery_started_s", _elapsed_s))
	var hold_started_s := float(record.get("rolling_hold_started_s", -1.0))
	var clearance_s := float(record.get("rolling_clearance_s", -1.0))
	var hold_wait_s := maxf((clearance_s if clearance_s >= 0.0 else _elapsed_s) - hold_started_s, 0.0) \
			if hold_started_s >= 0.0 else 0.0
	_log("ROLLING_TRAP count=%d/%s aircraft=%s type=%s wire=%d lateral=%s recovery=%.1fs hold_wait=%.1fs active_after=%d max_queue=%d max_holding=%d" % [
		_rolling_traps,
		str(rolling_target_traps) if rolling_target_traps > 0 else "unlimited",
		craft.name,
		recovery_type,
		wire,
		("%.2fm" % lateral) if is_finite(lateral) else "n/a",
		_elapsed_s - recovery_started_s,
		hold_wait_s,
		_rolling_active_aircraft_count(),
		_rolling_max_queue_depth,
		_rolling_max_holding_aircraft,
	])
	if rolling_target_traps > 0 and _rolling_traps >= rolling_target_traps:
		_stage = Stage.COMPLETE
		_log("COMPLETE recovery target reached; traps=%d losses=%d launches=%d max_active=%d max_queue=%d max_holding=%d mode=%s" % [
			_rolling_traps,
			_rolling_losses,
			_friendly_launches,
			rolling_active_aircraft_max,
			_rolling_max_queue_depth,
			_rolling_max_holding_aircraft,
			"mixed_finite_cohort" if _mixed_recovery_mode else (
				"finite_cohort" if rolling_finite_cohort else "rolling_refill"
			),
		])
	else:
		call_deferred("_request_recovery_test_launches")


func _check_recovery_end() -> void:
	if _stage != Stage.RECOVERY or _recovery_requested.is_empty():
		return
	for id_variant in _recovery_requested.keys():
		var id := int(id_variant)
		if _caught_aircraft.has(id):
			continue
		var record: Dictionary = _aircraft_records.get(id, {})
		if bool(record.get("alive", false)):
			return
	_stage = Stage.COMPLETE
	_log("COMPLETE all surviving friendly aircraft trapped or were lost; caught=%d requested=%d" % [_caught_aircraft.size(), _recovery_requested.size()])


func _configure_weapon_logging(craft: RigidBody3D) -> void:
	# Test-only, non-consuming ammunition is already implemented by bomb racks and
	# rocket pods; autocannons honor the same aircraft metadata as well.
	if _full_cycle_mode:
		# This mission is also a loadout/endurance test: two 24-round canisters are
		# all each friendly receives, and the attacking bombers keep finite stores.
		# Persistent tuning metadata keeps the telemetry callbacks attached after the
		# first release; it does not replenish ammunition.
		craft.remove_meta("heli_test_unlimited_ammo")
		craft.set_meta("airplane_test_persistent_bomb_tuning", true)
		craft.set_meta("airplane_test_persistent_rocket_tuning", true)
	else:
		craft.set_meta("heli_test_unlimited_ammo", true)
		craft.set_meta("airplane_test_persistent_bomb_tuning", true)
		craft.set_meta("airplane_test_persistent_rocket_tuning", true)
	var id := craft.get_instance_id()
	for weapon in _weapon_nodes(craft):
		if weapon is BombRack:
			(weapon as BombRack).set_tuning_context(
				Callable(self, "_on_bomb_dropped"), Callable(), id, null,
				Callable(self, "_on_bomb_impact_detail"))
		elif weapon is RocketPod:
			(weapon as RocketPod).set_tuning_context(
				Callable(self, "_on_rocket_launched"), Callable(), id, null,
				Callable(self, "_on_rocket_impact_detail"))
		elif weapon is Autocannon:
			_set_gun_context(weapon as Autocannon, craft)
		if "ammo_count" in weapon:
			_weapon_ammo[weapon.get_instance_id()] = int(weapon.get("ammo_count"))


func _set_gun_context(gun: Autocannon, craft: RigidBody3D) -> void:
	var record: Dictionary = _aircraft_records.get(craft.get_instance_id(), {})
	var pilot: Node = record.get("pilot", null)
	var target: Node3D = null
	if is_instance_valid(pilot):
		var candidate: Variant = pilot.get("combat_target")
		if is_instance_valid(candidate) and candidate is Node3D:
			target = candidate as Node3D
	gun.set_tuning_context(
		Callable(self, "_on_gun_shot"),
		Callable(self, "_on_gun_report").bind(craft.get_instance_id()),
		craft.get_instance_id(), target)


func _refresh_all_gun_targets() -> void:
	for record_variant in _aircraft_records.values():
		var record: Dictionary = record_variant
		var craft_variant: Variant = record.get("craft", null)
		if not is_instance_valid(craft_variant) or not (craft_variant is RigidBody3D):
			continue
		var craft := craft_variant as RigidBody3D
		for weapon in _weapon_nodes(craft):
			if weapon is Autocannon:
				_set_gun_context(weapon as Autocannon, craft)


func _on_bomb_dropped(id: int, projectile: Node) -> void:
	var record: Dictionary = _aircraft_records.get(id, {})
	_log("FIRE aircraft=%s weapon=Bomb target=%s projectile=%s %s" % [
		_name_for_id(id), _target_name_for_id(id), projectile.name,
		_aircraft_diagnostics(record),
	])


func _on_rocket_launched(id: int, projectile: Node, _target: Node3D) -> void:
	var record: Dictionary = _aircraft_records.get(id, {})
	var craft: RigidBody3D = record.get("craft", null) as RigidBody3D
	var target: Node3D = _target_for_id(id)
	var launch_pos: Vector3 = projectile.global_position if projectile is Node3D else Vector3.ZERO
	var initial_velocity: Vector3 = Vector3.ZERO
	var projectile_velocity: Variant = projectile.get("linear_velocity") if is_instance_valid(projectile) else null
	if projectile_velocity is Vector3:
		initial_velocity = projectile_velocity
	var target_pos: Vector3 = target.global_position if is_instance_valid(target) else Vector3.INF
	var to_target_flat := Vector3(target_pos.x - launch_pos.x, 0.0, target_pos.z - launch_pos.z) \
		if is_instance_valid(target) else Vector3.ZERO
	var along_axis: Vector3 = to_target_flat.normalized() if to_target_flat.length_squared() > 0.001 else Vector3.FORWARD
	var lateral_axis: Vector3 = Vector3.UP.cross(along_axis).normalized()
	var prediction: Dictionary = {}
	if is_instance_valid(craft) and craft.has_method("calculate_rocket_ccip_impact_point") and is_instance_valid(target):
		var prediction_variant: Variant = craft.call("calculate_rocket_ccip_impact_point", target_pos, target)
		if prediction_variant is Dictionary:
			prediction = prediction_variant
	var predicted_variant: Variant = prediction.get("impact_position", Vector3.ZERO)
	var predicted_pos: Vector3 = predicted_variant if predicted_variant is Vector3 else Vector3.ZERO
	var predicted_has_impact: bool = bool(prediction.get("has_impact", false)) and predicted_pos != Vector3.ZERO
	var predicted_along_m: float = (predicted_pos - target_pos).dot(along_axis) if predicted_has_impact else NAN
	var predicted_lateral_m: float = (predicted_pos - target_pos).dot(lateral_axis) if predicted_has_impact else NAN
	var snapshot := {
		"launch_time_s": _elapsed_s,
		"launch_position": launch_pos,
		"initial_velocity": initial_velocity,
		"target_position": target_pos,
		"target_name": target.name if is_instance_valid(target) else "none",
		"along_axis": along_axis,
		"lateral_axis": lateral_axis,
		"predicted_has_impact": predicted_has_impact,
		"predicted_position": predicted_pos,
		"predicted_time_s": float(prediction.get("time_to_impact", -1.0)),
		"predicted_blocked": bool(prediction.get("blocked", false)),
		"predicted_block_reason": str(prediction.get("blocked_reason", "")),
		"predicted_along_m": predicted_along_m,
		"predicted_lateral_m": predicted_lateral_m,
	}
	if is_instance_valid(projectile):
		projectile.set_meta("carrier_test_rocket_prediction", snapshot)
	_log("FIRE aircraft=%s weapon=Rocket target=%s projectile=%s launch=%s v0=%s speed=%.1f" % [
		_name_for_id(id), _target_name_for_id(id), projectile.name, _fmt(launch_pos),
		_fmt(initial_velocity), initial_velocity.length(),
	])
	_log("ROCKET_PREDICT aircraft=%s projectile=%s target=%s predicted=%s along=%+.1fm lateral=%+.1fm tof=%.2fs blocked=%s reason=%s" % [
		_name_for_id(id), projectile.name, snapshot.target_name,
		_fmt(predicted_pos) if predicted_has_impact else "none",
		predicted_along_m, predicted_lateral_m, float(snapshot.predicted_time_s),
		str(snapshot.predicted_blocked), str(snapshot.predicted_block_reason),
	])


func _on_bomb_impact_detail(position: Vector3, body: Node, id: int, _target: Node3D) -> void:
	_log_projectile_impact("Bomb", position, body, id, 30.0)


func _on_rocket_impact_detail(position: Vector3, body: Node, id: int, _target: Node3D, projectile: Node) -> void:
	_log_rocket_prediction_residual(position, id, projectile)
	_log_projectile_impact("Rocket", position, body, id, 8.0)


func _log_rocket_prediction_residual(actual_position: Vector3, id: int, projectile: Node) -> void:
	if not is_instance_valid(projectile) or not projectile.has_meta("carrier_test_rocket_prediction"):
		_log("ROCKET_MODEL aircraft=%s projectile=unknown prediction=missing actual=%s" % [
			_name_for_id(id), _fmt(actual_position),
		])
		return
	var snapshot_variant: Variant = projectile.get_meta("carrier_test_rocket_prediction")
	if not (snapshot_variant is Dictionary):
		return
	var snapshot: Dictionary = snapshot_variant
	var target_variant: Variant = snapshot.get("target_position", Vector3.INF)
	var along_variant: Variant = snapshot.get("along_axis", Vector3.FORWARD)
	var lateral_variant: Variant = snapshot.get("lateral_axis", Vector3.RIGHT)
	var target_pos: Vector3 = target_variant if target_variant is Vector3 else Vector3.INF
	var along_axis: Vector3 = along_variant if along_variant is Vector3 else Vector3.FORWARD
	var lateral_axis: Vector3 = lateral_variant if lateral_variant is Vector3 else Vector3.RIGHT
	var actual_along_m: float = (actual_position - target_pos).dot(along_axis)
	var actual_lateral_m: float = (actual_position - target_pos).dot(lateral_axis)
	var predicted_has_impact: bool = bool(snapshot.get("predicted_has_impact", false))
	var predicted_along_m: float = float(snapshot.get("predicted_along_m", NAN))
	var predicted_lateral_m: float = float(snapshot.get("predicted_lateral_m", NAN))
	var along_residual_m: float = actual_along_m - predicted_along_m if predicted_has_impact else NAN
	var lateral_residual_m: float = actual_lateral_m - predicted_lateral_m if predicted_has_impact else NAN
	var actual_tof_s: float = _elapsed_s - float(snapshot.get("launch_time_s", _elapsed_s))
	var initial_velocity_variant: Variant = snapshot.get("initial_velocity", Vector3.ZERO)
	var initial_velocity: Vector3 = initial_velocity_variant if initial_velocity_variant is Vector3 else Vector3.ZERO
	_log("ROCKET_MODEL aircraft=%s projectile=%s target=%s actual=%s actual_along=%+.1fm actual_lateral=%+.1fm predicted_along=%+.1fm predicted_lateral=%+.1fm residual_along=%+.1fm residual_lateral=%+.1fm tof_actual=%.2fs tof_predicted=%.2fs v0=%.1f" % [
		_name_for_id(id), projectile.name, str(snapshot.get("target_name", "none")), _fmt(actual_position),
		actual_along_m, actual_lateral_m, predicted_along_m, predicted_lateral_m,
		along_residual_m, lateral_residual_m, actual_tof_s,
		float(snapshot.get("predicted_time_s", -1.0)), initial_velocity.length(),
	])


func _log_projectile_impact(weapon_name: String, position: Vector3, body: Node, id: int, effective_radius: float) -> void:
	var target := _target_for_id(id)
	var miss: float = _flat_distance(position, target.global_position) if is_instance_valid(target) else INF
	var hit_name := _damage_target_name(body)
	var result := "HIT_DIRECT" if is_instance_valid(target) and _node_is_or_descends_from(body, target) else ("IMPACT_NEAR" if miss <= effective_radius else "MISS")
	_log("%s aircraft=%s weapon=%s target=%s impact=%s miss=%.1fm body=%s" % [
		result, _name_for_id(id), weapon_name, _target_name_for_id(id), _fmt(position), miss, hit_name,
	])


func _on_gun_shot(id: int, _bullet: Node) -> void:
	var record: Dictionary = _aircraft_records.get(id, {})
	if _elapsed_s - float(record.get("last_gun_shot_s", -100.0)) > 0.8:
		_log("FIRE aircraft=%s weapon=Gun burst target=%s" % [_name_for_id(id), _target_name_for_id(id)])
	record["last_gun_shot_s"] = _elapsed_s
	_aircraft_records[id] = record


func _on_gun_report(report: Dictionary, id: int) -> void:
	var record: Dictionary = _aircraft_records.get(id, {})
	if bool(report.get("hit_target", false)):
		record["gun_hits"] = int(record.get("gun_hits", 0)) + 1
		_log("HIT aircraft=%s weapon=Gun target=%s closest_edge=%.2fm" % [
			_name_for_id(id), report.get("target_name", "unknown"), float(report.get("closest_edge_m", -1.0)),
		])
	else:
		record["gun_misses"] = int(record.get("gun_misses", 0)) + 1
		var pending := int(_gun_misses_since_log.get(id, 0)) + 1
		_gun_misses_since_log[id] = pending
		if pending >= 25:
			_log("MISS aircraft=%s weapon=Gun rounds=25 target=%s" % [_name_for_id(id), report.get("target_name", "unknown")])
			_gun_misses_since_log[id] = 0
	_aircraft_records[id] = record


func _physics_process(delta: float) -> void:
	_elapsed_s += delta
	if not _started:
		return
	_update_enemy_gunnery_rails(delta)
	if _stage == Stage.COMPLETE:
		_finalize_completed_run()
		return
	if continuous_intercept_mode and _stage == Stage.AIR_COMBAT:
		_continuous_force_check_s += delta
		if _continuous_force_check_s >= 2.0:
			_continuous_force_check_s = 0.0
			# If FlightDeckManager abandoned a retrieval without issuing its callback,
			# release our bookkeeping so the next periodic force check can retry.
			if _friendly_launch_requests_outstanding > 0 and is_instance_valid(_fdm):
				var pending_ops: Variant = _fdm.get("_pending_flight_ops")
				var deck_state := int(_fdm.get("current_state"))
				var deck_queue := int(_fdm.get("_ai_launch_queue"))
				if not is_instance_valid(pending_ops) and deck_state == 0 and deck_queue <= 0:
					_log("INTERCEPT_LAUNCH_RETRY abandoned_callbacks=%d" % _friendly_launch_requests_outstanding)
					_friendly_launch_requests_outstanding = 0
			_ensure_enemy_target_count()
			_ensure_friendly_force()
	if _role_stress_mode and _stage == Stage.GROUND_STRIKE:
		_continuous_force_check_s += delta
		if _continuous_force_check_s >= 2.0:
			_continuous_force_check_s = 0.0
			if _friendly_launch_requests_outstanding > 0 and is_instance_valid(_fdm):
				var role_pending_ops: Variant = _fdm.get("_pending_flight_ops")
				var role_deck_state := int(_fdm.get("current_state"))
				var role_deck_queue := int(_fdm.get("_ai_launch_queue"))
				if not is_instance_valid(role_pending_ops) and role_deck_state == 0 and role_deck_queue <= 0:
					_log("ROLE_LAUNCH_RETRY abandoned_callbacks=%d" % _friendly_launch_requests_outstanding)
					_friendly_launch_requests_outstanding = 0
			_request_role_stress_launches()
	if _rolling_recovery_mode and _stage == Stage.ROLLING:
		_continuous_force_check_s += delta
		if _continuous_force_check_s >= 2.0:
			_continuous_force_check_s = 0.0
			if _friendly_launch_requests_outstanding > 0 and is_instance_valid(_fdm):
				var rolling_pending_ops: Variant = _fdm.get("_pending_flight_ops")
				var rolling_deck_state := int(_fdm.get("current_state"))
				var rolling_deck_queue := int(_fdm.get("_ai_launch_queue"))
				if not is_instance_valid(rolling_pending_ops) and rolling_deck_state == 0 and rolling_deck_queue <= 0:
					_log("ROLLING_LAUNCH_RETRY abandoned_callbacks=%d" % _friendly_launch_requests_outstanding)
					_friendly_launch_requests_outstanding = 0
			_request_recovery_test_launches()
	if _stage in [Stage.GROUND_STRIKE, Stage.ROLLING] \
			and _friendly_launches == 0 \
			and not _initial_launch_watchdog_fired \
			and _elapsed_s - _stage_started_s >= maxf(initial_launch_watchdog_s, 5.0):
		_initial_launch_watchdog_fired = true
		var queued_launches: int = int(_fdm.get("_ai_launch_queue")) if is_instance_valid(_fdm) else 0
		var deck_state: int = int(_fdm.get("current_state")) if is_instance_valid(_fdm) else -1
		var expected_initial_queue := (
			mixed_helicopter_count if _mixed_recovery_mode else rolling_active_aircraft_max
		) if _rolling_recovery_mode else 2
		var untouched_queue: bool = queued_launches >= expected_initial_queue
		var released_for_departure: bool = false
		if not keep_carrier_at_verified_pose:
			released_for_departure = _release_carrier_hold("launch watchdog: departure corridor did not clear")
		var watchdog_action := "release_carrier_for_departure" if released_for_departure else (
				"force_untouched_queue" if untouched_queue else "retrieval_already_in_progress"
		)
		_log("LAUNCH_WATCHDOG no aircraft launched state=%d queued=%d action=%s" % [
			deck_state,
			queued_launches,
			watchdog_action,
		])
		if not released_for_departure \
				and is_instance_valid(_fdm) \
				and untouched_queue \
				and _fdm.has_method("_launch_next_queued_ai"):
			# The test clears unrelated deck units after carrier relocation. If the deck
			# manager retained a stale non-idle state from one of those units, its queue
			# otherwise waits forever even though the deck is physically empty.
			_fdm.set("current_state", 0) # FlightDeckManager.DeckState.IDLE
			_fdm.call("_launch_next_queued_ai")
	if _desert_recovery_mode \
			and _stage == Stage.ROLLING \
			and _friendly_launches == 0 \
			and _elapsed_s - _stage_started_s >= maxf(desert_recovery_initial_launch_timeout_s, 30.0):
		var launch_snapshot := _desert_deck_launch_snapshot()
		_completion_reason = "initial_launch_timeout"
		_stage = Stage.COMPLETE
		_log("FAILED desert recovery: initial launch timeout after %.0fs snapshot=%s" % [
			_elapsed_s - _stage_started_s,
			JSON.stringify(launch_snapshot),
		])
		return
	_update_g_force_tracking(delta)
	_summary_s += delta
	_poll_s += delta
	if _poll_s >= 0.5:
		_poll_s = 0.0
		if _stage == Stage.RECOVERY and not _carrier_held_for_recovery:
			if _try_hold_carrier_for_recovery():
				_dispatch_recovery_orders()
		elif _stage == Stage.RECOVERY and not _recovery_orders_dispatched:
			_dispatch_recovery_orders()
		_poll_aircraft_events()
		_poll_rolling_aircraft()
		_poll_role_stress()
		_poll_missile_launches()
	var summary_interval_s := ROLLING_SUMMARY_INTERVAL_S \
			if _rolling_recovery_mode else SUMMARY_INTERVAL_S
	if _summary_s >= summary_interval_s:
		_summary_s = 0.0
		_log_summary()
	if _stage == Stage.GROUND_STRIKE \
			and not _isolated_ground_attack_mode \
			and not _full_cycle_mode \
			and _elapsed_s - _stage_started_s >= maxf(ground_strike_observation_timeout_s, 30.0):
		var live_targets := _live_ground_targets()
		for target in live_targets:
			if is_instance_valid(target):
				target.queue_free()
		_begin_air_combat("ground strike observation timeout (%d/4 targets destroyed)" % _ground_targets_destroyed)
	if not continuous_intercept_mode \
			and not _full_cycle_mode \
			and _stage == Stage.AIR_COMBAT \
			and _elapsed_s - _stage_started_s >= air_combat_timeout_s:
		_begin_recovery("air combat timeout with %d enemies still airborne" % _live_aircraft_for_team(2).size())
	if _role_stress_mode and _stage == Stage.GROUND_STRIKE \
			and _elapsed_s - _stage_started_s >= maxf(role_stress_timeout_s, 60.0):
		_stage = Stage.COMPLETE
		_log("FAILED role stress combat timeout; ground=%d/4 enemy_air_kills=%d/2 friendly_alive=%d" % [
			_ground_targets_destroyed,
			_enemy_kills,
			_live_aircraft_for_team(1).size(),
		])
	var recovery_time_budget_s: float = maxf(recovery_timeout_s, 30.0) \
		* float(maxi(_recovery_requested.size(), 1))
	if _stage == Stage.RECOVERY \
			and _elapsed_s - _stage_started_s >= recovery_time_budget_s:
		var surviving_recovery_aircraft: int = 0
		for id_variant in _recovery_requested.keys():
			var record: Dictionary = _aircraft_records.get(int(id_variant), {})
			if bool(record.get("alive", false)) and not _caught_aircraft.has(int(id_variant)):
				surviving_recovery_aircraft += 1
		_stage = Stage.COMPLETE
		_log("COMPLETE recovery timeout after %.0fs (%.0fs per requested aircraft); caught=%d requested=%d still_airborne=%d" % [
			recovery_time_budget_s,
			maxf(recovery_timeout_s, 30.0),
			_caught_aircraft.size(),
			_recovery_requested.size(),
			surviving_recovery_aircraft,
		])


func _finalize_completed_run() -> void:
	if _completion_handled:
		return
	_completion_handled = true
	var friendly_alive := 0
	var enemy_spawned := 0
	var enemy_alive := 0
	var loadouts: Array[String] = []
	for record_variant in _aircraft_records.values():
		var record: Dictionary = record_variant
		var team := int(record.get("team", 0))
		if team == 1:
			if bool(record.get("alive", false)):
				friendly_alive += 1
			var craft_variant: Variant = record.get("craft", null)
			if is_instance_valid(craft_variant):
				loadouts.append(_describe_loadout(craft_variant as Node))
		elif team == 2:
			enemy_spawned += 1
			if bool(record.get("alive", false)):
				enemy_alive += 1
	var enemy_phase_success := (
		full_cycle_skip_enemy_air and enemy_spawned == 0
	) or (
		not full_cycle_skip_enemy_air and enemy_spawned >= 2 and enemy_alive == 0
	)
	var full_cycle_success := _full_cycle_mode \
			and _ground_targets_destroyed >= 4 \
			and enemy_phase_success \
			and _friendly_launches == 2 \
			and _caught_aircraft.size() == _friendly_launches \
			and _friendly_destroyed_count == 0 \
			and _friendly_crash_count == 0
	var rolling_success := _rolling_recovery_mode \
			and rolling_target_traps > 0 \
			and _rolling_traps >= rolling_target_traps \
			and _rolling_losses == 0 \
			and (
				_friendly_launches == rolling_target_traps if rolling_finite_cohort \
				else _friendly_launches >= _rolling_traps
			)
	var role_stress_success := _role_stress_mode \
			and _ground_targets_destroyed >= 4 \
			and enemy_spawned == 2 \
			and enemy_alive == 0 \
			and _enemy_kills >= 2 \
			and _friendly_launches == 4 \
			and _role_stress_helicopter_launches == 2 \
			and _role_stress_patrol_launches == 2 \
			and _recovery_requested.size() == 4 \
			and _caught_aircraft.size() == 4 \
			and _friendly_destroyed_count == 0 \
			and _friendly_crash_count == 0 \
			and _role_stress_role_violations == 0
	var strict_success := full_cycle_success or rolling_success or role_stress_success
	var result := {
		"run_id": _test_run_id,
		"seed": _test_seed,
		"profile": test_profile,
		"status": "PASS" if strict_success else "FAIL",
		"failure_reason": "" if strict_success else _completion_reason,
		"sim_time_s": snappedf(_elapsed_s, 0.1),
		"ground_destroyed": _ground_targets_destroyed,
		"enemy_air_skipped": full_cycle_skip_enemy_air,
		"enemy_spawned": enemy_spawned,
		"enemy_alive": enemy_alive,
		"friendly_launched": _friendly_launches,
		"friendly_alive": friendly_alive,
		"friendly_destroyed": _friendly_destroyed_count,
		"friendly_crashes": _friendly_crash_count,
		"recovery_requested": _recovery_requested.size(),
		"caught": _caught_aircraft.size(),
		"recovery_stages": _desert_recovery_stage_counts.duplicate(true) if _desert_recovery_mode else {},
		"role_attack_helicopters": _role_stress_helicopter_launches,
		"role_cap_aircraft": _role_stress_patrol_launches,
		"role_violations": _role_stress_role_violations,
		"loadouts": loadouts,
	}
	_log("RUN_RESULT json=%s" % JSON.stringify(result))
	if _quit_on_test_complete:
		call_deferred("_quit_completed_run")


func _quit_completed_run() -> void:
	# Give stdout and the report file one idle frame to flush before the batch
	# process exits and its launcher starts a completely fresh game instance.
	await get_tree().process_frame
	get_tree().quit(0)


func _poll_aircraft_events() -> void:
	for id_variant in _aircraft_records.keys():
		var id := int(id_variant)
		var record: Dictionary = _aircraft_records[id]
		if not bool(record.get("alive", false)):
			continue
		var pilot_variant: Variant = record.get("pilot", null)
		if not is_instance_valid(pilot_variant) or not (pilot_variant is Node):
			continue
		var pilot := pilot_variant as Node
		# Fixed-wing combat telemetry below intentionally knows AIPilot's detailed
		# states. Helicopters are supervised through the domain-neutral rolling poll.
		if str(record.get("ops_domain", "fixed_wing")) == "helicopter":
			continue
		var state := int(pilot.get("current_state"))
		if state != int(record.get("last_state", -1)):
			_log("STATE aircraft=%s %s->%s target=%s %s" % [
				record.get("name", "unknown"), _state_name(int(record.get("last_state", -1))),
				_state_name(state), _target_name_for_id(id), _aircraft_diagnostics(record),
			])
			record["last_state"] = state
			if _desert_recovery_mode:
				if state == AIPilot.State.RTB:
					_record_desert_recovery_stage(id, "rtb_started", "state=RTB")
				elif state == AIPilot.State.RECOVERY_APPROACH:
					_record_desert_recovery_stage(id, "recovery_route", "state=RECOVERY_APPROACH")
				elif state == AIPilot.State.PRE_LANDING:
					_record_desert_recovery_stage(id, "pre_landing", "state=PRE_LANDING")
				elif state == AIPilot.State.LANDING:
					var craft_variant: Variant = record.get("craft", null)
					var diagnostic_handoff := is_instance_valid(craft_variant) \
							and bool((craft_variant as Node).get_meta(
								"recovery_diagnostic_handoff",
								false
							))
					_record_desert_recovery_stage(
						id,
						"final_handoff",
						"state=LANDING strict_gate_passed=%s diagnostic_override=%s" % [
							str(not diagnostic_handoff),
							str(diagnostic_handoff),
						]
					)
		if state in [AIPilot.State.ATTACK_POSITIONING, AIPilot.State.ATTACK_INBOUND] \
				and pilot.has_method("get_attack_last_commit_reason"):
			var commit_reason := str(pilot.call("get_attack_last_commit_reason"))
			if commit_reason != str(record.get("last_commit_reason", "")):
				record["last_commit_reason"] = commit_reason
				if commit_reason not in ["", "not_evaluated", "positioning_time"]:
					_log("GATE aircraft=%s reason=%s target=%s %s" % [
						record.get("name", "unknown"), commit_reason,
						_target_name_for_id(id), _aircraft_diagnostics(record),
					])
		# Do not throw a still-climbing aircraft directly into the first attack turn.
		# The scenario configures a lower launch capture altitude; wait until its
		# vertical speed has settled before assigning the nearby target.
		var assignment_craft: Variant = record.get("craft", null)
		var climb_rate_settled: bool = is_instance_valid(assignment_craft) \
				and assignment_craft is RigidBody3D \
				and absf((assignment_craft as RigidBody3D).linear_velocity.y) <= 4.0
		var safe_climb_assignment: bool = state == AIPilot.State.CLIMBING \
				and float(pilot.get("altitude_agl")) >= maxf(ground_assignment_min_agl_m, 0.0) \
				and climb_rate_settled
		var ready_for_ground_assignment: bool = state in [AIPilot.State.SEARCH, AIPilot.State.TRANSIT] \
				or safe_climb_assignment
		if _stage == Stage.GROUND_STRIKE \
				and not _role_stress_mode \
				and int(record.get("team", 0)) == 1 \
				and not bool(record.get("ground_mission_assigned", false)) \
				and ready_for_ground_assignment:
			record["ground_mission_assigned"] = true
			_aircraft_records[id] = record
			_assign_ground_target(pilot, int(record.get("ground_assignment_index", 0)))
		var target: Variant = pilot.get("combat_target")
		var target_id := (target as Node).get_instance_id() if is_instance_valid(target) and target is Node else 0
		if target_id != int(record.get("last_target_id", 0)):
			record["last_target_id"] = target_id
			_log("TARGET aircraft=%s acquired=%s" % [record.get("name", "unknown"), _target_name_for_id(id)])
			var craft_variant: Variant = record.get("craft", null)
			if is_instance_valid(craft_variant) and craft_variant is RigidBody3D:
				for weapon in _weapon_nodes(craft_variant as RigidBody3D):
					if weapon is Autocannon:
						_set_gun_context(weapon as Autocannon, craft_variant as RigidBody3D)
		_aircraft_records[id] = record
	if continuous_intercept_mode:
		_assign_missing_intercept_targets()
	_try_resume_carrier_after_launches()


func _initialize_desert_recovery_stage_counts() -> void:
	_desert_recovery_stage_counts.clear()
	for stage_key in DESERT_RECOVERY_STAGE_KEYS:
		_desert_recovery_stage_counts[stage_key] = 0


func _desert_deck_launch_snapshot() -> Dictionary:
	if not is_instance_valid(_fdm):
		return {"flight_deck_valid": false}
	var elevator_variant: Variant = _fdm.get("elevator")
	var elevator_state := -1
	var elevator_platform_y := NAN
	if is_instance_valid(elevator_variant) and elevator_variant is Node:
		var elevator_node := elevator_variant as Node
		if "current_state" in elevator_node:
			elevator_state = int(elevator_node.get("current_state"))
		if elevator_node.has_method("get_platform_local_y"):
			elevator_platform_y = float(elevator_node.call("get_platform_local_y"))
	var deck_aircraft_variant: Variant = _fdm.get("deck_aircraft")
	var deck_aircraft_position := Vector3.INF
	var distance_to_catapult_m := NAN
	var carrier_transport_mode := false
	if is_instance_valid(deck_aircraft_variant) and deck_aircraft_variant is Node3D:
		var deck_aircraft_node := deck_aircraft_variant as Node3D
		deck_aircraft_position = deck_aircraft_node.global_position
		carrier_transport_mode = bool(deck_aircraft_node.get_meta("carrier_transport_mode", false))
		if _fdm.has_method("_get_active_catapult_latch_marker"):
			var latch_variant: Variant = _fdm.call("_get_active_catapult_latch_marker")
			if is_instance_valid(latch_variant) and latch_variant is Node3D:
				distance_to_catapult_m = deck_aircraft_node.global_position.distance_to(
					(latch_variant as Node3D).global_position
				)
	var job_bots_variant: Variant = _fdm.get("_current_job_tractor_bots")
	return {
		"flight_deck_valid": true,
		"deck_state": int(_fdm.get("current_state")),
		"queued_launches": int(_fdm.get("_ai_launch_queue")),
		"pending_callback": is_instance_valid(_fdm.get("_pending_flight_ops")),
		"deck_aircraft": str((deck_aircraft_variant as Node).name) \
				if is_instance_valid(deck_aircraft_variant) and deck_aircraft_variant is Node else "none",
		"deck_aircraft_position": deck_aircraft_position,
		"distance_to_catapult_m": distance_to_catapult_m,
		"carrier_transport_mode": carrier_transport_mode,
		"retrieval_top_handled": bool(_fdm.get("_retrieval_top_handled")),
		"elevator_ride_in_progress": bool(_fdm.get("_aircraft_elevator_ride_in_progress")),
		"tractor_transfer_in_progress": bool(_fdm.get("_tractor_elevator_transfer_in_progress")),
		"tractorbots_in_hangar": bool(_fdm.get("_tractorbots_in_hangar")),
		"job_tractor_count": job_bots_variant.size() if job_bots_variant is Array else -1,
		"elevator_state": elevator_state,
		"elevator_platform_local_y": elevator_platform_y,
	}


func _record_desert_recovery_stage(id: int, stage_key: String, detail: String = "") -> void:
	if not _desert_recovery_mode or stage_key not in DESERT_RECOVERY_STAGE_KEYS:
		return
	var record: Dictionary = _aircraft_records.get(id, {})
	if record.is_empty():
		return
	var marker_key := "desert_stage_%s" % stage_key
	if bool(record.get(marker_key, false)):
		return
	record[marker_key] = true
	_aircraft_records[id] = record
	_desert_recovery_stage_counts[stage_key] = int(_desert_recovery_stage_counts.get(stage_key, 0)) + 1
	_log("RECOVERY_STAGE aircraft=%s stage=%s count=%d active_cap=%d target_traps=%s%s" % [
		record.get("name", "unknown"),
		stage_key.to_upper(),
		int(_desert_recovery_stage_counts[stage_key]),
		rolling_active_aircraft_max,
		str(rolling_target_traps) if rolling_target_traps > 0 else "unlimited",
		(" " + detail) if not detail.is_empty() else "",
	])


## Real load factor (g), computed the same way the in-cockpit slip ball reads it: specific force
## (acceleration minus gravity) projected onto the aircraft's own local up axis, filtered to settle
## on the sustained turn value rather than frame noise. This is ground truth for "how hard are they
## actually pulling" -- pitch_input alone doesn't reveal it, since it's several steps removed from
## the airframe's actual lift response (AoA, aoa_lift_bonus_factor, max_lift_ratio all sit between
## the two).
func _update_g_force_tracking(delta: float) -> void:
	if delta <= 0.0001:
		return
	for id_variant in _aircraft_records.keys():
		var id := int(id_variant)
		var record: Dictionary = _aircraft_records[id]
		if not bool(record.get("alive", false)):
			continue
		var craft_variant: Variant = record.get("craft", null)
		if not is_instance_valid(craft_variant) or not (craft_variant is RigidBody3D):
			continue
		var craft := craft_variant as RigidBody3D
		var velocity: Vector3 = craft.linear_velocity
		var has_previous: bool = bool(record.get("g_has_previous_velocity", false))
		var previous_velocity: Vector3 = record.get("g_previous_velocity", Vector3.ZERO)
		if has_previous:
			var acceleration: Vector3 = (velocity - previous_velocity) / delta
			var gravity := Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665))
			var specific_force: Vector3 = acceleration - gravity
			var local_up: Vector3 = craft.global_transform.basis.y
			var instant_g: float = specific_force.dot(local_up) / 9.80665
			var filtered_g: float = float(record.get("g_filtered", 1.0))
			filtered_g = lerpf(filtered_g, instant_g, clampf(delta * 4.0, 0.0, 1.0))
			record["g_filtered"] = filtered_g
			record["g_peak_recent"] = maxf(float(record.get("g_peak_recent", 1.0)) * 0.98, filtered_g)
		record["g_previous_velocity"] = velocity
		record["g_has_previous_velocity"] = true
		_aircraft_records[id] = record


func _aircraft_diagnostics(record: Dictionary) -> String:
	var pieces: Array[String] = []
	var craft_variant: Variant = record.get("craft", null)
	var pilot: Node = record.get("pilot", null)
	if str(record.get("ops_domain", "fixed_wing")) == "helicopter":
		if is_instance_valid(craft_variant) and craft_variant is RigidBody3D:
			var heli_craft := craft_variant as RigidBody3D
			pieces.append("pos=%s" % _fmt(heli_craft.global_position))
			pieces.append("speed=%.1f" % heli_craft.linear_velocity.length())
			var collision_name := str(heli_craft.get_meta("last_collision_body_name", "none"))
			if collision_name != "none":
				pieces.append("collision=%s" % collision_name)
				pieces.append("collision_path=%s" % str(heli_craft.get_meta("last_collision_ancestry", "")))
				pieces.append("collision_speed=%.1f" % float(heli_craft.get_meta("last_collision_impact_speed_mps", 0.0)))
		if is_instance_valid(pilot):
			pieces.append("state=%s" % _ops_state_name(pilot, "helicopter"))
		return " ".join(pieces)
	if is_instance_valid(craft_variant) and craft_variant is RigidBody3D:
		var craft := craft_variant as RigidBody3D
		pieces.append("pos=%s" % _fmt(craft.global_position))
		pieces.append("speed=%.1f" % craft.linear_velocity.length())
		var bank_deg: float = absf(rad_to_deg(atan2(
			craft.global_transform.basis.x.y,
			craft.global_transform.basis.y.y
		)))
		pieces.append("bank=%.1fdeg" % bank_deg)
		if is_instance_valid(pilot) and "yaw_input" in pilot:
			pieces.append("yaw=%.2f" % float(pilot.get("yaw_input")))
		if is_instance_valid(pilot) and "pitch_input" in pilot:
			pieces.append("pitch=%.2f" % float(pilot.get("pitch_input")))
		if record.has("g_filtered"):
			pieces.append("g=%.2f" % float(record.get("g_filtered")))
		var target_variant: Variant = pilot.get("combat_target") if is_instance_valid(pilot) else null
		if is_instance_valid(target_variant) and target_variant is Node3D:
			var target := target_variant as Node3D
			var target_range := Vector2(craft.global_position.x - target.global_position.x, craft.global_position.z - target.global_position.z).length()
			pieces.append("target_range=%.1f" % target_range)
		var collision_name := str(craft.get_meta("last_collision_body_name", "none"))
		if collision_name != "none":
			pieces.append("collision=%s" % collision_name)
			pieces.append("collision_path=%s" % str(craft.get_meta("last_collision_ancestry", "")))
	if is_instance_valid(pilot):
		var simple_aero_variant: Variant = pilot.get("simple_aero")
		if is_instance_valid(simple_aero_variant):
			if simple_aero_variant.has_method("get_estimated_angle_of_attack_deg"):
				pieces.append("alpha=%.1fdeg" % float(simple_aero_variant.call("get_estimated_angle_of_attack_deg")))
			if simple_aero_variant.has_method("get_estimated_lift_ratio"):
				pieces.append("lift_ratio=%.2f" % float(simple_aero_variant.call("get_estimated_lift_ratio")))
		else:
			pieces.append("aero=INVALID")
		pieces.append("agl=%.1f" % float(pilot.get("altitude_agl")))
		pieces.append("weapon=%s" % str(pilot.get("_run_weapon_type")))
		if pilot.has_method("get_attack_last_commit_reason"):
			pieces.append("commit=%s" % str(pilot.call("get_attack_last_commit_reason")))
		if pilot.has_method("get_attack_last_end_reason"):
			pieces.append("end=%s" % str(pilot.call("get_attack_last_end_reason")))
		var run_weapon := str(pilot.get("_run_weapon_type"))
		if run_weapon == "Bomb" and pilot.has_method("get_last_bomb_release_block_reason"):
			pieces.append("release=%s" % str(pilot.call("get_last_bomb_release_block_reason")))
			var release_miss := float(pilot.call("get_last_bomb_release_miss_m"))
			var release_best := float(pilot.call("get_last_bomb_release_best_miss_m"))
			if is_finite(release_miss):
				pieces.append("ccip=%.1fm" % release_miss)
			if is_finite(release_best):
				pieces.append("best=%.1fm" % release_best)
			pieces.append("drop_range=%.1fm" % float(pilot.call("get_last_bomb_release_range_m")))
			pieces.append("fpa=%.1fdeg" % float(pilot.call("get_last_bomb_release_fpa_deg")))
			pieces.append("bank=%.1fdeg" % float(pilot.call("get_last_bomb_release_bank_deg")))
		elif run_weapon == "Rocket Pod" and pilot.has_method("get_last_rocket_release_reason"):
			var rocket_release_reason := str(pilot.call("get_last_rocket_release_reason"))
			if rocket_release_reason.is_empty() and pilot.has_method("get_last_rocket_release_block_reason"):
				rocket_release_reason = str(pilot.call("get_last_rocket_release_block_reason"))
			pieces.append("release=%s" % rocket_release_reason)
			if pilot.has_method("get_last_rocket_release_miss_m"):
				var rocket_release_miss := float(pilot.call("get_last_rocket_release_miss_m"))
				if is_finite(rocket_release_miss):
					pieces.append("ccip=%.1fm" % rocket_release_miss)
	return " ".join(pieces)


func _recovery_condition_diagnostics(record: Dictionary) -> String:
	var pieces: Array[String] = []
	var craft_value: Variant = record.get("craft", null)
	var pilot: Node = record.get("pilot", null)
	if is_instance_valid(craft_value) and craft_value is RigidBody3D:
		var craft := craft_value as RigidBody3D
		pieces.append("mass=%.1f" % craft.mass)
		pieces.append("speed=%.1f" % craft.linear_velocity.length())
		pieces.append("vs=%+.1f" % craft.linear_velocity.y)
		var bank_deg: float = absf(rad_to_deg(atan2(
			craft.global_transform.basis.x.y,
			craft.global_transform.basis.y.y
		)))
		pieces.append("bank=%.1fdeg" % bank_deg)
		for property_name in ["health", "current_health", "fuel", "fuel_amount"]:
			if property_name in craft:
				var property_value: Variant = craft.get(property_name)
				if property_value is float or property_value is int:
					pieces.append("%s=%.1f" % [property_name, float(property_value)])
		var stores: int = 0
		for weapon in _weapon_nodes(craft):
			for ammo_property in ["ammo_count", "rounds_remaining", "bomb_count"]:
				if ammo_property in weapon:
					var ammo_value: Variant = weapon.get(ammo_property)
					if ammo_value is int or ammo_value is float:
						stores += maxi(int(ammo_value), 0)
						break
		pieces.append("stores=%d" % stores)
	if is_instance_valid(pilot):
		if "altitude_agl" in pilot:
			pieces.append("agl=%.1f" % float(pilot.get("altitude_agl")))
		if "stall_speed_mps" in pilot:
			pieces.append("stall=%.1f" % float(pilot.get("stall_speed_mps")))
		if "_aircraft_heightmap_route_serial" in pilot:
			pieces.append("route_serial=%d" % int(pilot.get("_aircraft_heightmap_route_serial")))
		if "current_air_task" in pilot:
			var task_value: Variant = pilot.get("current_air_task")
			pieces.append("task=%s" % (str(task_value.kind) if task_value != null else "none"))
	return " ".join(pieces)


func _poll_missile_launches() -> void:
	for record_variant in _aircraft_records.values():
		var record: Dictionary = record_variant
		var craft_variant: Variant = record.get("craft", null)
		if not is_instance_valid(craft_variant) or not (craft_variant is RigidBody3D):
			continue
		for weapon in _weapon_nodes(craft_variant as RigidBody3D):
			if not (weapon is AAMissileLauncher):
				continue
			var key := weapon.get_instance_id()
			var ammo := int(weapon.get("ammo_count"))
			var previous := int(_weapon_ammo.get(key, ammo))
			if ammo < previous:
				_log("FIRE aircraft=%s weapon=AAMissile count=%d target=%s" % [
					record.get("name", "unknown"), previous - ammo,
					_target_name_for_id((craft_variant as Node).get_instance_id()),
				])
			_weapon_ammo[key] = ammo


func _log_summary() -> void:
	var stage_name: String = str(Stage.keys()[int(_stage)])
	var measured_fps: int = Engine.get_frames_per_second()
	var pieces: Array[String] = []
	for record_variant in _aircraft_records.values():
		var record: Dictionary = record_variant
		var craft_variant: Variant = record.get("craft", null)
		var status := "dead"
		if bool(record.get("alive", false)) and is_instance_valid(craft_variant) and craft_variant is RigidBody3D:
			var craft := craft_variant as RigidBody3D
			var carrier_range := craft.global_position.distance_to(_carrier.global_position) if is_instance_valid(_carrier) else -1.0
			status = "pos=%s spd=%.0f carrier_dist=%.0f" % [_fmt(craft.global_position), craft.linear_velocity.length(), carrier_range]
			var pilot_variant: Variant = record.get("pilot", null)
			if str(record.get("ops_domain", "fixed_wing")) == "helicopter":
				if is_instance_valid(pilot_variant):
					status += " type=helicopter state=%s mission=%s" % [
						_ops_state_name(pilot_variant as Node, "helicopter"),
						str(HelicopterPilot.MissionPhase.keys()[int(pilot_variant.get("mission_phase"))]),
					]
					if _role_stress_mode:
						var commanded: Variant = pilot_variant.get("_commanded_attack_target")
						var commanded_dist := craft.global_position.distance_to((commanded as Node3D).global_position) \
								if is_instance_valid(commanded) and commanded is Node3D else -1.0
						status += " atk=%s cmd_dist=%.0f dest=%s" % [
							str(HelicopterPilot.AtkState.keys()[int(pilot_variant.get("_atk_state"))]),
							commanded_dist,
							_fmt(pilot_variant.get("destination")),
						]
				var heli_rolling_label := " cycle=%s q=%d" % [
					str(record.get("rolling_status", "")),
					int(record.get("rolling_queue_position", -1)),
				]
				pieces.append("%s[%s%s]" % [record.get("name", "?"), status, heli_rolling_label])
				continue
			if is_instance_valid(pilot_variant):
				var bank_deg: float = absf(rad_to_deg(atan2(
					craft.global_transform.basis.x.y,
					craft.global_transform.basis.y.y
				)))
				var pitch_val: float = float(pilot_variant.get("pitch_input")) if "pitch_input" in pilot_variant else 0.0
				var yaw_val: float = float(pilot_variant.get("yaw_input")) if "yaw_input" in pilot_variant else 0.0
				var g_val: float = float(record.get("g_filtered", 1.0))
				var agl_m: float = float(pilot_variant.get("altitude_agl")) if "altitude_agl" in pilot_variant else -1.0
				if _enemy_rail_tracks.has(craft.get_instance_id()):
					agl_m = craft.global_position.y - _ground_height(craft.global_position)
				var pilot_state: int = int(pilot_variant.get("current_state"))
				status += " state=%s agl=%.0f bank=%.0f pitch=%.2f yaw=%.2f g=%.2f" % [
					_state_name(pilot_state),
					agl_m,
					bank_deg,
					pitch_val,
					yaw_val,
					g_val,
				]
				if _role_stress_mode:
					var nav: Vector3 = pilot_variant.get("nav_waypoint")
					var nav_dist := Vector2(nav.x - craft.global_position.x, nav.z - craft.global_position.z).length()
					status += " nav=%s nav_dist=%.0f fp=%s/%d" % [
						_fmt(nav),
						nav_dist,
						str(pilot_variant.get("_flight_plan_name")),
						int(pilot_variant.get("current_waypoint_index")),
					]
				if pilot_state in [
					AIPilot.State.RTB,
					AIPilot.State.RECOVERY_HOLD,
					AIPilot.State.RECOVERY_APPROACH,
					AIPilot.State.PRE_LANDING,
				] and pilot_variant.has_method("get_recovery_navigation_snapshot"):
					var nav_snapshot: Dictionary = pilot_variant.call(
						"get_recovery_navigation_snapshot"
					)
					var progress_value: Variant = nav_snapshot.get("progress", {})
					var progress: Dictionary = progress_value \
						if progress_value is Dictionary else {}
					status += " rc=%d re=%d fp=%d/%d/%s rem=%.0f plan=%.0f homev=%+.1f homec=%+.2f reacq=%s" % [
						int(nav_snapshot.get("route_serial", -1)),
						int(nav_snapshot.get("origin_shift_epoch", -1)),
						int(progress.get("index", -1)) + 1,
						int(pilot_variant.get("waypoints").size()) \
							if pilot_variant.get("waypoints") is Array else 0,
						str(progress.get("role", "none")),
						float(progress.get("remaining_m", INF)),
						float(progress.get("plan_remaining_m", INF)),
						float(nav_snapshot.get("velocity_toward_carrier_mps", NAN)),
						float(nav_snapshot.get("guidance_toward_carrier_dot", NAN)),
						str(bool(nav_snapshot.get("reacquire_active", false))),
					]
				if pilot_state in [AIPilot.State.RECOVERY_APPROACH, AIPilot.State.PRE_LANDING]:
					if "_recovery_phase" in pilot_variant:
						status += " rp=%d" % int(pilot_variant.get("_recovery_phase"))
					if pilot_variant.has_method("get_route_follow_debug_snapshot"):
						var recovery_route_debug: Dictionary = pilot_variant.call("get_route_follow_debug_snapshot")
						status += " rn=%s ri=%d rr=%s rx=%.0f" % [
							str(pilot_variant.get("_flight_plan_name")),
							int(recovery_route_debug.get("index", -1)),
							str(recovery_route_debug.get("role", "none")),
							float(recovery_route_debug.get("projection_cross_track_m", INF)),
						]
					if pilot_state == AIPilot.State.PRE_LANDING:
						status += " hs=%.2f" % float(
							pilot_variant.get("_recovery_final_handoff_stable_s")
						)
				if pilot_state == AIPilot.State.LANDING:
					status += " bolter=%s" % str(bool(pilot_variant.get("_bolter_go_around")))
					if pilot_variant.has_method("_landing_behind_carrier_m"):
						status += " behind=%.0f" % float(pilot_variant.call("_landing_behind_carrier_m"))
				if pilot_state == AIPilot.State.ATTACK_POSITIONING \
						and pilot_variant.has_method("get_route_follow_debug_snapshot"):
					var route_debug: Dictionary = pilot_variant.call("get_route_follow_debug_snapshot")
					var route_projection_active: bool = bool(pilot_variant.call("is_route_forward_projection_active")) \
						if pilot_variant.has_method("is_route_forward_projection_active") else false
					var route_projection_usable: bool = bool(pilot_variant.call("is_route_forward_projection_usable")) \
						if pilot_variant.has_method("is_route_forward_projection_usable") else false
					var route_guidance_error_deg: float = rad_to_deg(float(
						pilot_variant.call("get_route_guidance_yaw_error_rad")
					)) if pilot_variant.has_method("get_route_guidance_yaw_error_rad") else 0.0
					status += " ri=%d rr=%s proj=%s/%s rye=%+.0f rx=%.0f" % [
						int(route_debug.get("index", -1)),
						str(route_debug.get("role", "none")),
						str(route_projection_active),
						str(route_projection_usable),
						route_guidance_error_deg,
						float(route_debug.get("projection_cross_track_m", INF)),
					]
					if "_attack_setup_requires_target_crossing" in pilot_variant:
						status += " cross=%s" % str(bool(pilot_variant.get(
							"_attack_setup_requires_target_crossing"
						)))
					var route_tag: String = str(route_debug.get("debug_tag", ""))
					if not route_tag.is_empty():
						status += " rt=%s" % route_tag
					if route_debug.has("arc_remaining_m"):
						status += " arm=%.0f" % float(route_debug.get("arc_remaining_m", INF))
					if pilot_variant.has_method("get_flight_plan_debug_snapshot"):
						var plan_debug: Dictionary = pilot_variant.call("get_flight_plan_debug_snapshot")
						var plan_legs_value: Variant = plan_debug.get("legs", [])
						var active_index: int = int(plan_debug.get("current_index", -1))
						var plan_leg_count: int = plan_legs_value.size() if plan_legs_value is Array else 0
						status += " rv=%d/%d pt=%.0f/%.0f lc=%s" % [
							int(plan_debug.get("revision", -1)),
							plan_leg_count,
							float(pilot_variant.get("_positioning_time_s")),
							float(pilot_variant.call("get_attack_positioning_route_timeout_s")) \
								if pilot_variant.has_method("get_attack_positioning_route_timeout_s") else -1.0,
							str(pilot_variant.get("_attack_last_commit_reason")),
						]
						if plan_legs_value is Array and active_index >= 0 and active_index < plan_legs_value.size():
							var active_leg_value: Variant = plan_legs_value[active_index]
							if active_leg_value is Dictionary:
								status += " rad=%.0f" % float((active_leg_value as Dictionary).get("turn_radius_m", NAN))
								var active_position_value: Variant = (active_leg_value as Dictionary).get("position", Vector3.INF)
								if active_position_value is Vector3 and active_position_value != Vector3.INF:
									var active_position: Vector3 = active_position_value
									status += " wp=(%.0f,%.0f)" % [active_position.x, active_position.z]
							if active_index + 1 < plan_legs_value.size():
								var next_leg_value: Variant = plan_legs_value[active_index + 1]
								if next_leg_value is Dictionary:
									var next_position_value: Variant = (next_leg_value as Dictionary).get("position", Vector3.INF)
									if next_position_value is Vector3 and next_position_value != Vector3.INF:
										var next_position: Vector3 = next_position_value
										status += " nx=(%.0f,%.0f)" % [next_position.x, next_position.z]
				if "_positive_turn_load_guard_active" in pilot_variant \
						and bool(pilot_variant.get("_positive_turn_load_guard_active")):
					status += " posload=guard"
				if "_coordinated_turn_last_frame" in pilot_variant \
						and Engine.get_physics_frames() - int(pilot_variant.get("_coordinated_turn_last_frame")) <= 2:
					status += " tb=%+.0f tg=%.2f ag=%.2f ta=%.1f ar=%+.1f vlf=%+.2f nwa=%+.1f slip=%+.3f vyr=%+.2f dvs=%+.1f vs=%+.1f tr=%.1f" % [
						float(pilot_variant.get("_coordinated_turn_target_bank_deg")),
						float(pilot_variant.get("_coordinated_turn_target_g")),
						float(pilot_variant.get("_coordinated_turn_available_g")),
						float(pilot_variant.get("_coordinated_turn_target_aoa_deg")),
						float(pilot_variant.get("_coordinated_turn_filtered_aoa_rate_deg_s")),
						float(pilot_variant.get("_coordinated_turn_vertical_lift_fraction")),
						float(pilot_variant.get("_coordinated_turn_nonwing_vertical_accel_mps2")),
						float(pilot_variant.get("_coordinated_turn_sideslip")),
						float(pilot_variant.get("_coordinated_turn_vertical_rudder")),
						float(pilot_variant.get("_coordinated_turn_desired_vertical_speed_mps")),
						craft.linear_velocity.y,
						float(pilot_variant.get("_coordinated_turn_rate_deg_s")),
					]
				if "_dogfight_commanded_turn_rate_deg_s" in pilot_variant \
						and pilot_state == AIPilot.State.DOGFIGHT:
					status += " ye=%+.1f los=%+.1f ctr=%+.1f atr=%+.1f btr=%+.1f pa=%.2f" % [
						float(pilot_variant.get("_dogfight_assertive_turn_yaw_error_deg")),
						float(pilot_variant.get("_dogfight_los_rate_deg_s")),
						float(pilot_variant.get("_dogfight_commanded_turn_rate_deg_s")),
						float(pilot_variant.get("_dogfight_actual_track_rate_deg_s")),
						float(pilot_variant.get("_dogfight_bank_command_rate_deg_s")),
						float(pilot_variant.get("_dogfight_precise_aim_blend")),
					]
				if pilot_state == AIPilot.State.ATTACK_DIVE \
						and str(pilot_variant.get("_run_weapon_type")) == "Rocket Pod" \
						and pilot_variant.has_method("is_rocket_ccip_aim_active"):
					var rocket_ccip_active: bool = bool(pilot_variant.call("is_rocket_ccip_aim_active"))
					status += " rca=%s" % str(rocket_ccip_active)
					if rocket_ccip_active:
						var rocket_ccip_miss_m: float = float(pilot_variant.call("get_rocket_ccip_aim_miss_m"))
						var rocket_ccip_right_m: float = float(pilot_variant.call("get_rocket_ccip_aim_local_right_m"))
						var rocket_ccip_forward_m: float = float(pilot_variant.call("get_rocket_ccip_aim_local_forward_m"))
						var rocket_ccip_pitch_cmd: float = float(pilot_variant.call("get_rocket_ccip_aim_pitch_cmd"))
						var rocket_ccip_yaw_cmd: float = float(pilot_variant.call("get_rocket_ccip_aim_yaw_cmd"))
						status += " rcm=%.0f rcf=%+.0f rcr=%+.0f rcp=%+.2f rcy=%+.2f" % [
							rocket_ccip_miss_m,
							rocket_ccip_forward_m,
							rocket_ccip_right_m,
							rocket_ccip_pitch_cmd,
							rocket_ccip_yaw_cmd,
						]
						if pilot_variant.has_method("is_rocket_ccip_blocked") \
								and bool(pilot_variant.call("is_rocket_ccip_blocked")):
							status += " rcb=%s" % str(pilot_variant.call("get_rocket_ccip_block_reason"))
				if pilot_state == AIPilot.State.ATTACK_DIVE \
						and str(pilot_variant.get("_run_weapon_type")) == "Guns" \
						and pilot_variant.has_method("is_gun_ccip_aim_active"):
					var gun_ccip_active: bool = bool(pilot_variant.call("is_gun_ccip_aim_active"))
					status += " gca=%s" % str(gun_ccip_active)
					if gun_ccip_active:
						status += " gcm=%.0f gcf=%+.0f gcr=%+.0f gcp=%+.2f gcy=%+.2f" % [
							float(pilot_variant.call("get_gun_ccip_aim_miss_m")),
							float(pilot_variant.call("get_gun_ccip_aim_local_forward_m")),
							float(pilot_variant.call("get_gun_ccip_aim_local_right_m")),
							float(pilot_variant.call("get_gun_ccip_aim_pitch_cmd")),
							float(pilot_variant.call("get_gun_ccip_aim_yaw_cmd")),
						]
						if pilot_variant.has_method("is_gun_ccip_blocked") \
								and bool(pilot_variant.call("is_gun_ccip_blocked")):
							status += " gcb=%s" % str(pilot_variant.call("get_gun_ccip_block_reason"))
				var simple_aero_variant: Variant = pilot_variant.get("simple_aero")
				if is_instance_valid(simple_aero_variant):
					if simple_aero_variant.has_method("get_estimated_angle_of_attack_deg"):
						status += " alpha=%.1f" % float(simple_aero_variant.call("get_estimated_angle_of_attack_deg"))
					if simple_aero_variant.has_method("get_estimated_lift_ratio"):
						status += " lift=%.2f" % float(simple_aero_variant.call("get_estimated_lift_ratio"))
		var rolling_label := ""
		if _rolling_recovery_mode and not str(record.get("rolling_status", "")).is_empty():
			rolling_label = " cycle=%s q=%d" % [
				str(record.get("rolling_status", "")),
				int(record.get("rolling_queue_position", -1)),
			]
		pieces.append("%s[%s%s h=%d m=%d]" % [record.get("name", "?"), status, rolling_label, int(record.get("gun_hits", 0)), int(record.get("gun_misses", 0))])
	if _rolling_recovery_mode:
		var waiting_count := 0
		if is_instance_valid(_fdm):
			var waiting_variant: Variant = _fdm.get("_landing_clearance_queue")
			waiting_count = waiting_variant.size() if waiting_variant is Array else 0
		_log("SUMMARY stage=ROLLING_RECOVERY fps=%d traps=%d/%s losses=%d launches=%d active=%d pending_launches=%d waiting=%d max_queue=%d max_holding=%d :: %s" % [
			measured_fps,
			_rolling_traps,
			str(rolling_target_traps) if rolling_target_traps > 0 else "unlimited",
			_rolling_losses,
			_friendly_launches,
			_rolling_active_aircraft_count(),
			_friendly_launch_requests_outstanding,
			waiting_count,
			_rolling_max_queue_depth,
			_rolling_max_holding_aircraft,
			" | ".join(pieces),
		])
	elif continuous_intercept_mode:
		_log("SUMMARY stage=CONTINUOUS_INTERCEPT fps=%d kills=%d friendly_losses=%d friendly_alive=%d launches_pending=%d enemy_alive=%d :: %s" % [
			measured_fps,
			_enemy_kills,
			_friendly_losses,
			_live_aircraft_for_team(1).size(),
			_friendly_launch_requests_outstanding,
			_live_aircraft_for_team(2).size(),
			" | ".join(pieces),
		])
	else:
		var ground_status := "%d/4" % _ground_wave_destroyed
		if _isolated_ground_attack_mode:
			ground_status = "wave=%d weapons=%s %d/4 total=%d" % [
				_ground_wave_index,
				_isolated_ground_weapon_profile_label(),
				_ground_wave_destroyed,
				_ground_targets_destroyed,
			]
		_log("SUMMARY stage=%s fps=%d ground_targets=%s friendly_alive=%d enemy_alive=%d :: %s" % [
			stage_name, measured_fps, ground_status, _live_aircraft_for_team(1).size(),
			_live_aircraft_for_team(2).size(), " | ".join(pieces),
		])


func _live_aircraft_for_team(team: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record_variant in _aircraft_records.values():
		var record: Dictionary = record_variant
		if int(record.get("team", 0)) != team or not bool(record.get("alive", false)):
			continue
		var craft: Variant = record.get("craft", null)
		if is_instance_valid(craft):
			out.append(record)
	return out


func _live_ground_targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for target in _ground_targets:
		if not is_instance_valid(target):
			continue
		if "is_destroyed" in target and bool(target.get("is_destroyed")):
			continue
		if "is_dying" in target and bool(target.get("is_dying")):
			continue
		if "current_health" in target and float(target.get("current_health")) <= 0.0:
			continue
		out.append(target)
	return out


func _weapon_nodes(craft: Node) -> Array[Node]:
	var out: Array[Node] = []
	_collect_weapon_nodes(craft, out)
	return out


func _collect_weapon_nodes(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child is Weapon:
			out.append(child)
		_collect_weapon_nodes(child, out)


func _describe_loadout(craft: Node) -> String:
	var names: Array[String] = []
	for weapon in _weapon_nodes(craft):
		var weapon_name: String = str(weapon.get("weapon_name")) if "weapon_name" in weapon else str(weapon.name)
		if weapon_name not in names:
			names.append(weapon_name)
	return "+".join(names)


func _target_for_id(id: int) -> Node3D:
	var record: Dictionary = _aircraft_records.get(id, {})
	var pilot: Node = record.get("pilot", null)
	if not is_instance_valid(pilot):
		return null
	var target: Variant = pilot.get("combat_target")
	return target as Node3D if is_instance_valid(target) and target is Node3D else null


func _target_name_for_id(id: int) -> String:
	var target := _target_for_id(id)
	return target.name if is_instance_valid(target) else "none"


func _name_for_id(id: int) -> String:
	return str((_aircraft_records.get(id, {}) as Dictionary).get("name", "unknown"))


func _pilot_aircraft_name(pilot: Node) -> String:
	var craft: Variant = pilot.get("aircraft") if is_instance_valid(pilot) else null
	return craft.name if is_instance_valid(craft) else "unknown"


func _state_name(state: int) -> String:
	if state < 0 or state >= AIPilot.State.size():
		return "NONE"
	return str(AIPilot.State.keys()[state])


func _damage_target_name(body: Node) -> String:
	var node := body
	while is_instance_valid(node):
		if node.has_method("take_damage"):
			return node.name
		node = node.get_parent()
	return body.name if is_instance_valid(body) else "none"


func _node_is_or_descends_from(node: Node, ancestor: Node) -> bool:
	while is_instance_valid(node):
		if node == ancestor:
			return true
		node = node.get_parent()
	return false


func _ground_height(position: Vector3) -> float:
	if is_instance_valid(_terrain) and _terrain.has_method("get_height"):
		var height := float(_terrain.call("get_height", position))
		if is_finite(height):
			return height
	return _carrier.global_position.y - 40.0 if is_instance_valid(_carrier) else _play_area_center.y


func _basis_from_forward(forward: Vector3) -> Basis:
	var f := forward.normalized()
	var right := Vector3.UP.cross(f).normalized()
	var up := f.cross(right).normalized()
	return Basis(right, up, f)


func _stow_gear_retry(craft: RigidBody3D, attempt: int) -> void:
	if not is_instance_valid(craft):
		return
	var gear: Node = craft.find_child("ControlLandingGear", true, false)
	if gear != null:
		if "LockGearDeployed" in gear:
			gear.set("LockGearDeployed", false)
		if gear.has_method("stow_gear"):
			gear.call("stow_gear")
		elif gear.has_method("send_to_landing_gears"):
			gear.call("send_to_landing_gears", "stow")
	if attempt < 15:
		get_tree().create_timer(0.12).timeout.connect(_stow_gear_retry.bind(craft, attempt + 1))


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _fmt(v: Vector3) -> String:
	return "(%.0f,%.0f,%.0f)" % [v.x, v.y, v.z]


func _log(message: String) -> void:
	var line := "t=%07.1f %s" % [_elapsed_s, message]
	print("[CarrierCombatTest] ", line)
	var file := FileAccess.open(_report_path, FileAccess.READ_WRITE) if FileAccess.file_exists(_report_path) else FileAccess.open(_report_path, FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(line)
		file.close()
	var combat_log := get_node_or_null("/root/CombatLog")
	if combat_log != null and combat_log.has_method("event"):
		combat_log.call("event", "TEST", message)
