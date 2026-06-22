extends Node

## Online evolutionary tuner for the helicopter navigation test scenario.
## Each candidate is evaluated once on every fixed route. A Latin-square assignment
## keeps all eight candidates flying concurrently while rotating them across routes.

@export var enabled: bool = true
@export_range(4, 32, 1) var population_size: int = 8
@export_range(1, 8, 1) var elite_count: int = 2
@export_range(1, 6, 1) var focused_mutations_per_child: int = 3
@export_range(0.1, 4.0, 0.1) var mutation_scale: float = 1.0
@export var focus_turn_controller: bool = true
@export var route_count: int = 8
@export var trial_timeout_s: float = 900.0

# Continuous safety scoring. These are evaluation constants, not pilot genes.
# Match HelicopterPilot._has_clear_transit_segment(), which validates planner
# shortcuts against same-altitude terrain within a 50 m horizontal radius.
@export var horizontal_soft_clearance_m: float = 50.0
@export var vertical_soft_clearance_m: float = 50.0
@export var low_down_clearance_m: float = 25.0
@export var low_down_clearance_sinking_mps: float = 1.0
@export var low_down_clearance_climbing_mps: float = 0.75
@export var approach_scoring_exclusion_m: float = 300.0
@export var excess_agl_start_m: float = 150.0
@export var path_cross_track_soft_m: float = 120.0
@export var path_cross_track_good_m: float = 45.0
@export var path_cross_track_penalty: float = 150.0
@export var path_cross_track_mean_penalty: float = 4.0
@export var path_slalom_penalty: float = 85.0
@export var path_heading_error_penalty: float = 0.45
@export var path_fpv_error_penalty: float = 0.55
@export var path_fpv_vertical_error_penalty: float = 0.35
@export var feeler_strength_penalty: float = 220.0
@export var feeler_active_penalty: float = 140.0
@export var feeler_budget_penalty: float = 0.0
@export var clean_lap_time_reward: float = 6.0
@export var slow_lap_time_penalty: float = 4.0
@export var clean_lap_time_cap: float = 900.0
@export var turn_sample_threshold_deg: float = 15.0
@export var coordination_penalty_start_speed_mps: float = 25.0
@export var coordination_penalty_full_speed_mps: float = 40.0
@export var ball_center_good_g: float = 0.08
@export var ball_center_soft_g: float = 0.18
@export var sideslip_good_deg: float = 5.0
@export var sideslip_soft_deg: float = 12.0
@export var close_call_clearance_m: float = 50.0
@export var close_call_reset_m: float = 65.0
@export var progress_log_interval_s: float = 30.0
@export var no_path_unscored_grace_s: float = 5.0

@export var log_path: String = "user://heli_navigation_aircraft_11_tuning.log"
@export var project_mirror_enabled: bool = true
@export var project_mirror_path: String = "res://heli_navigation_aircraft_11_tuning.log"
@export var state_path: String = "user://heli_navigation_aircraft_11_tuning_state.json"
@export var champion_project_mirror_path: String = "res://heli_navigation_aircraft_11_champion.json"
@export var seed_genome_path: String = "res://heli_navigation_aircraft_9_champion.json"

# The genome contains terrain sensing plus a focused guidance/control group. With
# focus_turn_controller enabled, mutations touch only the latter while the terrain
# sensors remain a common baseline across candidates.
const PARAM_SPECS := [
	{"name": "terrain_hazard_lookahead_time_s", "base": 5.0, "min": 3.0, "max": 9.0, "sigma": 0.8},
	{"name": "terrain_hazard_min_lookahead_m", "base": 220.0, "min": 140.0, "max": 420.0, "sigma": 35.0},
	{"name": "terrain_hazard_max_lookahead_m", "base": 650.0, "min": 450.0, "max": 1050.0, "sigma": 75.0},
	{"name": "terrain_hazard_vertical_margin_m", "base": 45.0, "min": 28.0, "max": 100.0, "sigma": 9.0},
	{"name": "terrain_recovery_agl_m", "base": 75.0, "min": 55.0, "max": 135.0, "sigma": 10.0},
	{"name": "terrain_recovery_full_agl_m", "base": 35.0, "min": 22.0, "max": 65.0, "sigma": 7.0},
	{"name": "terrain_down_feeler_radius_m", "base": 18.0, "min": 8.0, "max": 55.0, "sigma": 7.0},
	{"name": "terrain_down_feeler_extra_clearance_m", "base": 16.0, "min": 6.0, "max": 45.0, "sigma": 6.0},
	{"name": "lateral_obstacle_probe_dist_m", "base": 85.0, "min": 45.0, "max": 130.0, "sigma": 15.0},
	{"name": "lateral_obstacle_probe_speed_scale", "base": 1.7, "min": 0.4, "max": 3.0, "sigma": 0.35},
	{"name": "lateral_obstacle_probe_max_dist_m", "base": 315.434814453125, "min": 130.0, "max": 380.0, "sigma": 40.0},
	{"name": "lateral_obstacle_margin_m", "base": 45.0, "min": 28.0, "max": 105.0, "sigma": 9.0},
	{"name": "lateral_obstacle_roll_gain", "base": 0.25, "min": 0.05, "max": 0.50, "sigma": 0.07},
	{"name": "lateral_obstacle_yaw_gain", "base": 0.12, "min": 0.0, "max": 0.30, "sigma": 0.04},
	{"name": "lateral_obstacle_side_push_mps", "base": 7.0, "min": 0.0, "max": 18.0, "sigma": 3.0},
	{"name": "lateral_obstacle_forward_speed_scale", "base": 0.12, "min": 0.02, "max": 0.40, "sigma": 0.06},
	{"name": "heightmap_safe_direction_probe_dist_m", "base": 145.0, "min": 80.0, "max": 230.0, "sigma": 25.0},
	{"name": "heightmap_safe_direction_probe_speed_scale", "base": 1.5, "min": 0.4, "max": 3.0, "sigma": 0.35},
	{"name": "heightmap_safe_direction_probe_max_dist_m", "base": 380.0, "min": 200.0, "max": 520.0, "sigma": 55.0},
	{"name": "heightmap_safe_direction_margin_m", "base": 88.0, "min": 45.0, "max": 165.0, "sigma": 14.0},
	{"name": "heightmap_safe_direction_roll_gain", "base": 0.28, "min": 0.05, "max": 0.55, "sigma": 0.07},
	{"name": "heightmap_safe_direction_yaw_gain", "base": 0.16, "min": 0.0, "max": 0.35, "sigma": 0.05},
	{"name": "heightmap_safe_direction_side_push_mps", "base": 10.0, "min": 0.0, "max": 24.0, "sigma": 4.0},
	{"name": "heightmap_safe_direction_forward_speed_scale", "base": 0.35, "min": 0.05, "max": 0.80, "sigma": 0.10},
	{"name": "terrain_climb_capacity_scale", "base": 0.5, "min": 0.25, "max": 1.0, "sigma": 0.10},
	{"name": "terrain_climb_speed_floor_mps", "base": 18.0, "min": 8.0, "max": 30.0, "sigma": 3.0},
	{"name": "cyclic_target_climb_from_alt_error_mps", "base": 0.18, "min": 0.08, "max": 0.40, "sigma": 0.04},
	{"name": "cyclic_target_climb_mps", "base": 5.0, "min": 3.5, "max": 8.5, "sigma": 0.6},
	{"name": "heightmap_path_insert_spacing_m", "base": 650.0, "min": 420.0, "max": 950.0, "sigma": 90.0},
	{"name": "heightmap_path_carrot_distance_m", "base": 520.0, "min": 220.0, "max": 680.0, "sigma": 65.0},
	{"name": "heightmap_path_corner_blend_radius_m", "base": 340.0, "min": 100.0, "max": 500.0, "sigma": 55.0},
	{"name": "heightmap_path_corner_blend_strength", "base": 0.65, "min": 0.20, "max": 0.95, "sigma": 0.10},
	{"name": "heightmap_path_pilot_min_segment_m", "base": 138.757526397705, "min": 100.0, "max": 260.0, "sigma": 35.0},
	{"name": "path_follow_line_blend", "base": 0.82, "min": 0.35, "max": 1.0, "sigma": 0.12},
	{"name": "path_follow_cross_track_full_m", "base": 260.0, "min": 90.0, "max": 520.0, "sigma": 55.0},
	{"name": "path_follow_cross_track_steer_strength", "base": 0.95, "min": 0.25, "max": 1.80, "sigma": 0.20},
	{"name": "path_follow_large_error_slowdown_m", "base": 360.0, "min": 150.0, "max": 750.0, "sigma": 75.0},
	{"name": "path_follow_min_speed_scale", "base": 0.55, "min": 0.25, "max": 0.90, "sigma": 0.08},
	{"name": "path_follow_aim_yaw_p", "base": 0.518674057722092, "min": 0.35, "max": 1.80, "sigma": 0.18},
	{"name": "path_follow_aim_yaw_d", "base": 0.18, "min": 0.0, "max": 0.55, "sigma": 0.07},
	{"name": "path_follow_aim_roll_rate_damping", "base": 0.45, "min": 0.0, "max": 1.10, "sigma": 0.14},
	{"name": "path_follow_aim_max_roll_input", "base": 0.971472656726837, "min": 0.35, "max": 1.0, "sigma": 0.10},
	{"name": "path_follow_aim_correction_rate", "base": 2.1301099896431, "min": 0.60, "max": 5.0, "sigma": 0.55},
	{"name": "path_follow_aim_roll_blend", "base": 0.55, "min": 0.0, "max": 0.90, "sigma": 0.15},
	{"name": "path_follow_fpv_roll_gain", "base": 1.10, "min": 0.25, "max": 2.40, "sigma": 0.22},
	{"name": "path_follow_fpv_roll_damping", "base": 0.30, "min": 0.0, "max": 0.90, "sigma": 0.10},
	{"name": "path_follow_fpv_pitch_gain", "base": 0.85, "min": 0.20, "max": 2.00, "sigma": 0.20},
	{"name": "path_follow_fpv_pitch_damping", "base": 0.12, "min": 0.0, "max": 0.55, "sigma": 0.07},
	{"name": "path_follow_fpv_max_roll_input", "base": 0.55, "min": 0.20, "max": 1.0, "sigma": 0.10},
	{"name": "path_follow_fpv_max_pitch_input", "base": 0.28, "min": 0.08, "max": 0.65, "sigma": 0.07},
	{"name": "path_follow_fpv_blend", "base": 0.65, "min": 0.15, "max": 1.0, "sigma": 0.12},
	{"name": "path_follow_fpv_correction_rate", "base": 2.2, "min": 0.60, "max": 5.0, "sigma": 0.45},
	{"name": "heightmap_path_overshoot_advance_max_m", "base": 360.0, "min": 140.0, "max": 360.0, "sigma": 60.0},
	{"name": "heightmap_path_segment_progress_cross_track_m", "base": 320.0, "min": 120.0, "max": 320.0, "sigma": 45.0},
	{"name": "heightmap_path_segment_progress_extra_m", "base": 0.0, "min": -80.0, "max": 120.0, "sigma": 35.0},
	{"name": "path_turn_speed_lookahead_m", "base": 900.0, "min": 550.0, "max": 1500.0, "sigma": 120.0},
	{"name": "path_turn_speed_floor_mps", "base": 20.0, "min": 8.0, "max": 30.0, "sigma": 3.0},
	{"name": "transit_turn_roll_gain", "base": 1.10, "min": 0.65, "max": 1.65, "sigma": 0.14},
	{"name": "transit_lateral_position_gain", "base": 0.00099129414714407, "min": 0.0002, "max": 0.0040, "sigma": 0.00055},
	{"name": "transit_lateral_velocity_gain", "base": 0.0269994907826185, "min": 0.005, "max": 0.065, "sigma": 0.007},
	{"name": "transit_lateral_max_demand_mps", "base": 12.0, "min": 4.0, "max": 28.0, "sigma": 3.0},
	{"name": "cyclic_rate", "base": 0.5, "min": 0.50, "max": 1.30, "sigma": 0.12},
	{"name": "control_input_expo", "base": 0.50, "min": 0.15, "max": 0.80, "sigma": 0.09},
	{"name": "transit_sharp_turn_roll_scale", "base": 0.75, "min": 0.45, "max": 1.0, "sigma": 0.10},
	{"name": "terrain_recovery_max_bank_scale", "base": 0.30, "min": 0.15, "max": 0.65, "sigma": 0.07},
	{"name": "transit_cruise_forward_lean", "base": 0.50, "min": 0.30, "max": 0.58, "sigma": 0.04},
	{"name": "collective_rate_up", "base": 0.85, "min": 0.55, "max": 1.50, "sigma": 0.12},
	{"name": "collective_speed_lift_bias", "base": 0.08, "min": 0.03, "max": 0.18, "sigma": 0.02},
]

const TURN_CONTROL_PARAMS := {
	"heightmap_path_insert_spacing_m": true,
	"heightmap_path_carrot_distance_m": true,
	"heightmap_path_corner_blend_radius_m": true,
	"heightmap_path_corner_blend_strength": true,
	"heightmap_path_pilot_min_segment_m": true,
	"path_follow_line_blend": true,
	"path_follow_cross_track_full_m": true,
	"path_follow_cross_track_steer_strength": true,
	"path_follow_large_error_slowdown_m": true,
	"path_follow_min_speed_scale": true,
	"path_follow_aim_yaw_p": true,
	"path_follow_aim_yaw_d": true,
	"path_follow_aim_roll_rate_damping": true,
	"path_follow_aim_max_roll_input": true,
	"path_follow_aim_correction_rate": true,
	"path_follow_aim_roll_blend": true,
	"path_follow_fpv_roll_gain": true,
	"path_follow_fpv_roll_damping": true,
	"path_follow_fpv_pitch_gain": true,
	"path_follow_fpv_pitch_damping": true,
	"path_follow_fpv_max_roll_input": true,
	"path_follow_fpv_max_pitch_input": true,
	"path_follow_fpv_blend": true,
	"path_follow_fpv_correction_rate": true,
	"heightmap_path_overshoot_advance_max_m": true,
	"heightmap_path_segment_progress_cross_track_m": true,
	"heightmap_path_segment_progress_extra_m": true,
	"path_turn_speed_lookahead_m": true,
	"path_turn_speed_floor_mps": true,
	"transit_turn_roll_gain": true,
	"transit_lateral_position_gain": true,
	"transit_lateral_velocity_gain": true,
	"transit_lateral_max_demand_mps": true,
	"cyclic_rate": true,
	"control_input_expo": true,
	"transit_sharp_turn_roll_scale": true,
	"terrain_recovery_max_bank_scale": true,
	"transit_cruise_forward_lean": true,
	"collective_rate_up": true,
	"collective_speed_lift_bias": true,
}
const FITNESS_VERSION: int = 24
const EVALUATION_VERSION: int = 20

# Per-route clean-lap targets from the observed Aircraft_11 path-following run.
# The score should say "fly the planned route cleanly, then prefer doing it
# briskly"; these are deliberately near the old averages, not aspirational max
# speeds, so the GA does not learn to dive through corners.
const ROUTE_CLEAN_LAP_TARGET_S := [
	295.0, 395.0, 465.0, 325.0,
	475.0, 280.0, 300.0, 320.0,
]

var _rng := RandomNumberGenerator.new()
var _generation: int = 0
var _population: Array[Dictionary] = []
var _route_rounds: Array[int] = []
var _trials: Dictionary = {}
var _active_by_pilot: Dictionary = {}
var _generation_results: Array[Dictionary] = []
var _pending_scored_trials: Dictionary = {}
var _next_trial_id: int = 1
var _best_fitness: float = -INF
var _best_genome: Dictionary = {}
var _best_result: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_load_state()
	_build_initial_population()
	_reset_route_rounds()
	_start_log()


func begin_trial(pilot_id: int, craft_name: String, route_slot: int) -> Dictionary:
	if not enabled or _population.is_empty():
		return {}
	if _active_by_pilot.has(pilot_id):
		end_trial(int(_active_by_pilot[pilot_id]), "replaced")
	var requested_route_slot := route_slot
	route_slot = _pick_route_slot_for_trial(requested_route_slot)
	var valid_route := route_slot >= 0 and route_slot < maxi(route_count, 1)
	var route_round := _route_rounds[route_slot] if valid_route else maxi(population_size, 4)
	var scored := valid_route and route_round < _population.size()
	var candidate := (route_slot + route_round) % _population.size() if scored else 0
	if scored:
		_route_rounds[route_slot] = route_round + 1
	var trial_id := _next_trial_id
	_next_trial_id += 1
	var genome: Dictionary = _population[candidate].duplicate(true)
	var trial := {
		"id": trial_id, "pilot_id": pilot_id, "craft": craft_name,
		"generation": _generation, "candidate": candidate, "route": route_slot,
		"route_round": route_round, "scored": scored, "genome": genome,
		"started_s": _now_s(), "lz_reached": false, "lap_completed": false,
		"next_progress_log_s": _now_s() + maxf(progress_log_interval_s, 5.0),
		"outbound_s": -1.0, "samples": 0, "scored_time_s": 0.0,
		"path_required_time_s": 0.0, "no_path_time_s": 0.0,
		"no_path_events": 0, "no_path_active": false,
		"min_local_agl_m": INF, "min_feeler_clearance_m": INF,
		"min_horizontal_clearance_m": INF, "max_sink_mps": 0.0,
		"vertical_risk_s": 0.0, "horizontal_risk_s": 0.0,
		"low_down_clearance_s": 0.0, "sinking_low_down_clearance_s": 0.0,
		"climbing_low_down_clearance_s": 0.0,
		"feeler_active_s": 0.0, "feeler_strength_integral": 0.0,
		"excess_agl_integral": 0.0, "speed_integral": 0.0,
		"max_path_cross_track_m": 0.0, "cross_track_risk_s": 0.0,
		"path_cross_track_integral": 0.0, "path_heading_error_integral": 0.0,
		"path_fpv_error_integral": 0.0, "path_fpv_vertical_error_integral": 0.0,
		"path_slalom_crossings": 0, "path_prev_signed_cross_track_m": INF,
		"path_prev_cross_track_sample_valid": false,
		"turn_time_s": 0.0, "turn_speed_integral": 0.0,
		"turn_bank_integral": 0.0, "turn_rate_integral": 0.0,
		"turn_heading_error_integral": 0.0, "turn_target_roll_integral": 0.0,
		"turn_signed_error_integral": 0.0, "turn_signed_bank_integral": 0.0,
		"turn_signed_target_roll_integral": 0.0,
		"turn_correct_bank_s": 0.0, "turn_opposing_bank_s": 0.0, "turn_weak_bank_s": 0.0,
		"turn_correct_roll_cmd_s": 0.0, "turn_opposing_roll_cmd_s": 0.0, "turn_weak_roll_cmd_s": 0.0,
		"turn_altitude_loss_m": 0.0,
		"coordination_time_s": 0.0, "coordinated_time_s": 0.0,
		"ball_abs_g_integral": 0.0, "ball_risk_s": 0.0,
		"sideslip_abs_integral": 0.0, "sideslip_risk_s": 0.0,
		"yaw_track_mismatch_integral": 0.0, "yaw_without_track_s": 0.0,
		"wrong_way_bank_s": 0.0,
		"close_calls": 0, "close_call_active": false,
	}
	_trials[trial_id] = trial
	_active_by_pilot[pilot_id] = trial_id
	if scored:
		_pending_scored_trials[trial_id] = true
	_log_event("TRIAL_START", {
		"trial": trial_id, "generation": _generation, "candidate": candidate,
		"route": route_slot + 1, "route_round": route_round,
		"requested_route": requested_route_slot + 1, "reassigned": route_slot != requested_route_slot,
		"scored": scored, "craft": craft_name, "genome": genome,
	})
	return {
		"trial_id": trial_id, "candidate": candidate, "route_round": route_round,
		"route_slot": route_slot, "requested_route_slot": requested_route_slot,
		"genome": genome.duplicate(true), "scored": scored,
	}


func _pick_route_slot_for_trial(requested_route_slot: int) -> int:
	var route_total := maxi(route_count, 1)
	while _route_rounds.size() < route_total:
		_route_rounds.append(0)
	var requested_valid := requested_route_slot >= 0 and requested_route_slot < route_total
	if requested_valid and _route_rounds[requested_route_slot] < _population.size():
		return requested_route_slot
	var best_slot := -1
	var best_round := INF
	for slot in range(route_total):
		var slot_round := float(_route_rounds[slot])
		if slot_round < float(_population.size()) and slot_round < best_round:
			best_round = slot_round
			best_slot = slot
	if best_slot >= 0:
		return best_slot
	return requested_route_slot


func record_sample(trial_id: int, sample: Dictionary, delta_s: float) -> void:
	var trial := _get_trial(trial_id)
	if trial.is_empty():
		return
	var dt := clampf(delta_s, 0.0, 2.0)
	if dt <= 0.0:
		return
	var navigation_transit_active := bool(sample.get("navigation_transit_active", sample.get("score_active", false)))
	var path_active := bool(sample.get("path_active", false))
	if navigation_transit_active:
		trial["path_required_time_s"] = float(trial.get("path_required_time_s", 0.0)) + dt
		if not path_active:
			trial["no_path_time_s"] = float(trial.get("no_path_time_s", 0.0)) + dt
			if not bool(trial.get("no_path_active", false)):
				trial["no_path_events"] = int(trial.get("no_path_events", 0)) + 1
			trial["no_path_active"] = true
		else:
			trial["no_path_active"] = false
	if not bool(sample.get("score_active", false)):
		return
	trial["samples"] = int(trial["samples"]) + 1
	trial["scored_time_s"] = float(trial["scored_time_s"]) + dt
	var local_agl := float(sample.get("local_agl_m", INF))
	var feeler_clearance := float(sample.get("feeler_clearance_m", INF))
	var horizontal_clearance := float(sample.get("horizontal_clearance_m", INF))
	var sink := maxf(float(sample.get("sink_mps", 0.0)), 0.0)
	var climb := maxf(float(sample.get("climb_mps", 0.0)), 0.0)
	var speed := maxf(float(sample.get("horizontal_speed_mps", 0.0)), 0.0)
	var feeler_strength := clampf(float(sample.get("feeler_strength", 0.0)), 0.0, 2.0)
	var path_cross_track := float(sample.get("path_cross_track_m", INF))
	var signed_path_cross_track := float(sample.get("signed_path_cross_track_m", path_cross_track))
	var turn_error_deg := maxf(float(sample.get("turn_error_deg", 0.0)), 0.0)
	var fpv_error_deg := maxf(float(sample.get("fpv_error_deg", turn_error_deg)), 0.0)
	var fpv_vertical_error_deg := maxf(float(sample.get("fpv_vertical_error_deg", 0.0)), 0.0)
	var bank_angle_deg := maxf(float(sample.get("bank_angle_deg", 0.0)), 0.0)
	var turn_rate_deg_s := maxf(float(sample.get("turn_rate_deg_s", 0.0)), 0.0)
	var target_roll_input := maxf(float(sample.get("target_roll_input", 0.0)), 0.0)
	var signed_target_roll := float(sample.get("signed_target_roll_input", 0.0))
	var signed_turn_error := float(sample.get("signed_turn_error_deg", 0.0))
	var signed_bank_angle := float(sample.get("signed_bank_angle_deg", 0.0))
	var yaw_rate := absf(float(sample.get("signed_yaw_rate_deg_s", 0.0)))
	var track_turn_rate := absf(float(sample.get("track_turn_rate_deg_s", 0.0)))
	var ball_abs_g := absf(float(sample.get("ball_lateral_g", 0.0)))
	var sideslip_abs_deg := absf(float(sample.get("sideslip_deg", 0.0)))
	# The final carrier/LZ approach deliberately leaves transit clearance. Keep it
	# outside both proximity objectives so the route planner and fitness agree.
	var goal_distance := float(sample.get("goal_distance_m", INF))
	if goal_distance > approach_scoring_exclusion_m:
		var nearest_terrain_clearance := INF
		if is_finite(feeler_clearance):
			nearest_terrain_clearance = minf(nearest_terrain_clearance, feeler_clearance)
		if is_finite(horizontal_clearance):
			nearest_terrain_clearance = minf(nearest_terrain_clearance, horizontal_clearance)
		if nearest_terrain_clearance <= close_call_clearance_m:
			if not bool(trial.get("close_call_active", false)):
				trial["close_calls"] = int(trial.get("close_calls", 0)) + 1
			trial["close_call_active"] = true
		elif nearest_terrain_clearance >= maxf(close_call_reset_m, close_call_clearance_m):
			trial["close_call_active"] = false
	else:
		trial["close_call_active"] = false
	if is_finite(local_agl):
		trial["min_local_agl_m"] = minf(float(trial["min_local_agl_m"]), local_agl)
		trial["excess_agl_integral"] = float(trial["excess_agl_integral"]) \
				+ maxf(local_agl - excess_agl_start_m, 0.0) / maxf(excess_agl_start_m, 1.0) * dt
	if goal_distance > approach_scoring_exclusion_m and is_finite(feeler_clearance):
		trial["min_feeler_clearance_m"] = minf(float(trial["min_feeler_clearance_m"]), feeler_clearance)
		var vertical_risk := clampf((vertical_soft_clearance_m - feeler_clearance) / maxf(vertical_soft_clearance_m, 1.0), 0.0, 2.0)
		var vertical_context_scale := 1.0
		if climb >= low_down_clearance_climbing_mps and sink < low_down_clearance_sinking_mps:
			vertical_context_scale = 0.25
		elif sink >= low_down_clearance_sinking_mps:
			vertical_context_scale = 1.0 + clampf(sink / 6.0, 0.0, 1.5)
		trial["vertical_risk_s"] = float(trial["vertical_risk_s"]) + vertical_risk * vertical_risk * vertical_context_scale * dt
		if feeler_clearance < low_down_clearance_m:
			trial["low_down_clearance_s"] = float(trial["low_down_clearance_s"]) + dt
			if sink >= low_down_clearance_sinking_mps:
				trial["sinking_low_down_clearance_s"] = float(trial["sinking_low_down_clearance_s"]) + dt
			elif climb >= low_down_clearance_climbing_mps:
				trial["climbing_low_down_clearance_s"] = float(trial["climbing_low_down_clearance_s"]) + dt
	# Do not teach the tuner that approaching a carrier or LZ is itself dangerous.
	if goal_distance > approach_scoring_exclusion_m and is_finite(horizontal_clearance):
		trial["min_horizontal_clearance_m"] = minf(float(trial["min_horizontal_clearance_m"]), horizontal_clearance)
		var horizontal_risk := clampf((horizontal_soft_clearance_m - horizontal_clearance) / maxf(horizontal_soft_clearance_m, 1.0), 0.0, 1.0)
		trial["horizontal_risk_s"] = float(trial["horizontal_risk_s"]) + horizontal_risk * horizontal_risk * dt
	if goal_distance > approach_scoring_exclusion_m and is_finite(path_cross_track):
		trial["max_path_cross_track_m"] = maxf(float(trial["max_path_cross_track_m"]), path_cross_track)
		trial["path_cross_track_integral"] = float(trial["path_cross_track_integral"]) + path_cross_track * dt
		trial["path_heading_error_integral"] = float(trial["path_heading_error_integral"]) + turn_error_deg * dt
		trial["path_fpv_error_integral"] = float(trial["path_fpv_error_integral"]) + fpv_error_deg * dt
		trial["path_fpv_vertical_error_integral"] = float(trial["path_fpv_vertical_error_integral"]) + fpv_vertical_error_deg * dt
		var cross_track_risk := clampf((path_cross_track - path_cross_track_soft_m) / maxf(path_cross_track_soft_m, 1.0), 0.0, 3.0)
		trial["cross_track_risk_s"] = float(trial["cross_track_risk_s"]) + cross_track_risk * cross_track_risk * dt
		if is_finite(signed_path_cross_track):
			var previous_signed := float(trial.get("path_prev_signed_cross_track_m", INF))
			if bool(trial.get("path_prev_cross_track_sample_valid", false)) \
					and absf(previous_signed) > path_cross_track_good_m \
					and absf(signed_path_cross_track) > path_cross_track_good_m \
					and previous_signed * signed_path_cross_track < 0.0:
				trial["path_slalom_crossings"] = int(trial.get("path_slalom_crossings", 0)) + 1
			trial["path_prev_signed_cross_track_m"] = signed_path_cross_track
			trial["path_prev_cross_track_sample_valid"] = true
	if turn_error_deg >= turn_sample_threshold_deg:
		trial["turn_time_s"] = float(trial["turn_time_s"]) + dt
		trial["turn_speed_integral"] = float(trial["turn_speed_integral"]) + speed * dt
		trial["turn_bank_integral"] = float(trial["turn_bank_integral"]) + bank_angle_deg * dt
		trial["turn_rate_integral"] = float(trial["turn_rate_integral"]) + turn_rate_deg_s * dt
		trial["turn_heading_error_integral"] = float(trial["turn_heading_error_integral"]) + turn_error_deg * dt
		trial["turn_target_roll_integral"] = float(trial["turn_target_roll_integral"]) + target_roll_input * dt
		trial["turn_signed_error_integral"] = float(trial["turn_signed_error_integral"]) + signed_turn_error * dt
		trial["turn_signed_bank_integral"] = float(trial["turn_signed_bank_integral"]) + signed_bank_angle * dt
		trial["turn_signed_target_roll_integral"] = float(trial["turn_signed_target_roll_integral"]) + signed_target_roll * dt
		var significant_turn := absf(signed_turn_error) >= 25.0
		if significant_turn:
			if bank_angle_deg < 2.0:
				trial["turn_weak_bank_s"] = float(trial["turn_weak_bank_s"]) + dt
			elif signed_bank_angle * signed_turn_error < 0.0:
				trial["turn_correct_bank_s"] = float(trial["turn_correct_bank_s"]) + dt
			elif signed_bank_angle * signed_turn_error > 0.0:
				trial["turn_opposing_bank_s"] = float(trial["turn_opposing_bank_s"]) + dt
			if target_roll_input < 0.12:
				trial["turn_weak_roll_cmd_s"] = float(trial["turn_weak_roll_cmd_s"]) + dt
			elif signed_target_roll * signed_turn_error > 0.0:
				trial["turn_correct_roll_cmd_s"] = float(trial["turn_correct_roll_cmd_s"]) + dt
			elif signed_target_roll * signed_turn_error < 0.0:
				trial["turn_opposing_roll_cmd_s"] = float(trial["turn_opposing_roll_cmd_s"]) + dt
		trial["turn_altitude_loss_m"] = float(trial["turn_altitude_loss_m"]) + sink * dt
		var coordination_speed_t := clampf(
			(speed - coordination_penalty_start_speed_mps) \
					/ maxf(coordination_penalty_full_speed_mps - coordination_penalty_start_speed_mps, 0.1),
			0.0, 1.0
		)
		if coordination_speed_t > 0.0:
			var coordination_dt := dt * coordination_speed_t
			trial["coordination_time_s"] = float(trial["coordination_time_s"]) + coordination_dt
			trial["ball_abs_g_integral"] = float(trial["ball_abs_g_integral"]) + ball_abs_g * coordination_dt
			trial["sideslip_abs_integral"] = float(trial["sideslip_abs_integral"]) + sideslip_abs_deg * coordination_dt
			var ball_risk := clampf(
				(ball_abs_g - ball_center_good_g) / maxf(ball_center_soft_g - ball_center_good_g, 0.01),
				0.0, 3.0
			)
			var sideslip_risk := clampf(
				(sideslip_abs_deg - sideslip_good_deg) / maxf(sideslip_soft_deg - sideslip_good_deg, 0.1),
				0.0, 3.0
			)
			trial["ball_risk_s"] = float(trial["ball_risk_s"]) + ball_risk * ball_risk * coordination_dt
			trial["sideslip_risk_s"] = float(trial["sideslip_risk_s"]) + sideslip_risk * sideslip_risk * coordination_dt
			var yaw_track_mismatch := absf(yaw_rate - track_turn_rate)
			trial["yaw_track_mismatch_integral"] = float(trial["yaw_track_mismatch_integral"]) + yaw_track_mismatch * coordination_dt
			if absf(yaw_rate) > 3.0 and absf(track_turn_rate) < 0.75:
				trial["yaw_without_track_s"] = float(trial["yaw_without_track_s"]) + coordination_dt
			# After the path-follow cyclic polarity fix, the turns that actually
			# reduced cross-track error logged bank angle with the opposite sign
			# from signed_turn_error. Keep the score aligned with observed path
			# following, not the earlier stale convention.
			if absf(signed_bank_angle) > 3.0 and signed_bank_angle * signed_turn_error > 0.0:
				trial["wrong_way_bank_s"] = float(trial["wrong_way_bank_s"]) + coordination_dt
			var coordinated := ball_abs_g <= ball_center_good_g \
					and sideslip_abs_deg <= sideslip_good_deg \
					and absf(track_turn_rate) >= 0.75 \
					and absf(signed_bank_angle) >= 3.0 \
					and yaw_track_mismatch <= 3.0
			if coordinated:
				trial["coordinated_time_s"] = float(trial["coordinated_time_s"]) + coordination_dt
	trial["max_sink_mps"] = maxf(float(trial["max_sink_mps"]), sink)
	trial["speed_integral"] = float(trial["speed_integral"]) + speed * dt
	trial["feeler_strength_integral"] = float(trial["feeler_strength_integral"]) + feeler_strength * dt
	if feeler_strength > 0.01:
		trial["feeler_active_s"] = float(trial["feeler_active_s"]) + dt
	if _now_s() >= float(trial.get("next_progress_log_s", INF)):
		trial["next_progress_log_s"] = _now_s() + maxf(progress_log_interval_s, 5.0)
		_log_event("TRIAL_PROGRESS", _trial_progress_log_data(trial))


func mark_lz_reached(trial_id: int, outbound_s: float) -> void:
	var trial := _get_trial(trial_id)
	if trial.is_empty():
		return
	trial["lz_reached"] = true
	trial["outbound_s"] = outbound_s


func is_trial_timed_out(trial_id: int) -> bool:
	var trial := _get_trial(trial_id)
	return not trial.is_empty() and _now_s() - float(trial["started_s"]) >= maxf(trial_timeout_s, 60.0)


func get_status() -> Dictionary:
	var required := _population.size() * maxi(route_count, 1)
	return {
		"enabled": enabled,
		"generation": _generation,
		"population": _population.size(),
		"route_count": maxi(route_count, 1),
		"required_results": required,
		"scored_results": _generation_results.size(),
		"pending_scored_trials": _pending_scored_trials.size(),
		"active_trials": _trials.size(),
		"remaining_results": maxi(required - _generation_results.size(), 0),
		"route_rounds": _route_rounds.duplicate(),
		"next_trial_id": _next_trial_id,
		"best_fitness": _best_fitness,
		"generation_best_trial": _get_generation_best_trial_summary(),
		"all_time_best": _get_all_time_best_summary(),
	}


func _get_generation_best_trial_summary() -> Dictionary:
	var best_trial: Dictionary = {}
	var best_score := -INF
	for trial_variant in _generation_results:
		if not (trial_variant is Dictionary):
			continue
		var trial := trial_variant as Dictionary
		var fitness := float(trial.get("fitness", -INF))
		if fitness > best_score:
			best_score = fitness
			best_trial = trial
	if best_trial.is_empty():
		return {}
	return {
		"trial_id": int(best_trial.get("id", 0)),
		"candidate": int(best_trial.get("candidate", -1)),
		"route": int(best_trial.get("route", -1)) + 1,
		"fitness": best_score,
		"lap_completed": bool(best_trial.get("lap_completed", false)),
		"lz_reached": bool(best_trial.get("lz_reached", false)),
		"exit_reason": String(best_trial.get("exit_reason", "")),
		"mean_path_cross_track_m": float(best_trial.get("mean_path_cross_track_m", 0.0)),
		"mean_path_fpv_error_deg": float(best_trial.get("mean_path_fpv_error_deg", 0.0)),
		"mean_path_fpv_vertical_error_deg": float(best_trial.get("mean_path_fpv_vertical_error_deg", 0.0)),
		"path_slalom_crossings": int(best_trial.get("path_slalom_crossings", 0)),
		"close_calls": int(best_trial.get("close_calls", 0)),
		"no_path_time_s": float(best_trial.get("no_path_time_s", 0.0)),
	}


func _get_all_time_best_summary() -> Dictionary:
	if _best_result.is_empty():
		return {}
	return {
		"candidate": int(_best_result.get("candidate", -1)),
		"fitness": float(_best_result.get("fitness", _best_fitness)),
		"trials": int(_best_result.get("trials", 0)),
		"laps": int(_best_result.get("laps", 0)),
		"lz_reached": int(_best_result.get("lz_reached", 0)),
		"crashes": int(_best_result.get("crashes", 0)),
		"mean_path_cross_track_m": float(_best_result.get("mean_path_cross_track_m", 0.0)),
		"mean_path_heading_error_deg": float(_best_result.get("mean_path_heading_error_deg", 0.0)),
		"mean_path_fpv_error_deg": float(_best_result.get("mean_path_fpv_error_deg", 0.0)),
		"mean_path_fpv_vertical_error_deg": float(_best_result.get("mean_path_fpv_vertical_error_deg", 0.0)),
		"mean_path_slalom_crossings": float(_best_result.get("mean_path_slalom_crossings", 0.0)),
	}


func end_trial(trial_id: int, reason: String) -> Dictionary:
	var trial := _get_trial(trial_id)
	if trial.is_empty():
		return {}
	_trials.erase(trial_id)
	var pilot_id := int(trial["pilot_id"])
	if int(_active_by_pilot.get(pilot_id, -1)) == trial_id:
		_active_by_pilot.erase(pilot_id)
	trial["ended_s"] = _now_s()
	trial["duration_s"] = float(trial["ended_s"]) - float(trial["started_s"])
	trial["exit_reason"] = reason
	trial["lap_completed"] = reason == "lap"
	_finalize_trial_metrics(trial)
	if bool(trial.get("scored", false)) \
			and float(trial.get("no_path_time_s", 0.0)) >= maxf(no_path_unscored_grace_s, 0.0):
		trial["scored"] = false
		trial["unscored_reason"] = "no_path"
	trial["fitness"] = _score_trial(trial)
	_log_event("TRIAL_END", _trial_log_data(trial))
	_pending_scored_trials.erase(trial_id)
	if bool(trial.get("scored", false)):
		_generation_results.append(trial.duplicate(true))
	elif String(trial.get("unscored_reason", "")) == "no_path":
		var route := int(trial.get("route", -1))
		var route_round := int(trial.get("route_round", -1))
		if route >= 0 and route < _route_rounds.size() and route_round >= 0:
			_route_rounds[route] = mini(int(_route_rounds[route]), route_round)
	_try_evolve_generation()
	return _trial_ui_snapshot(trial)


func get_trial_snapshot(trial_id: int) -> Dictionary:
	var trial := _get_trial(trial_id)
	if trial.is_empty():
		return {}
	var snapshot_trial := trial.duplicate(true)
	snapshot_trial["duration_s"] = _now_s() - float(snapshot_trial["started_s"])
	snapshot_trial["exit_reason"] = "active"
	_finalize_trial_metrics(snapshot_trial)
	snapshot_trial["fitness"] = _score_trial(snapshot_trial)
	return _trial_ui_snapshot(snapshot_trial)


func _trial_ui_snapshot(trial: Dictionary) -> Dictionary:
	var min_feeler := float(trial.get("min_feeler_clearance_m", -1.0))
	var min_horizontal := float(trial.get("min_horizontal_clearance_m", -1.0))
	var min_clearance := -1.0
	if min_feeler >= 0.0:
		min_clearance = min_feeler
	if min_horizontal >= 0.0:
		min_clearance = min_horizontal if min_clearance < 0.0 else minf(min_clearance, min_horizontal)
	return {
		"trial_id": int(trial.get("id", 0)),
		"candidate": int(trial.get("candidate", -1)),
		"fitness": float(trial.get("fitness", 0.0)),
		"close_calls": int(trial.get("close_calls", 0)),
		"lz_reached": bool(trial.get("lz_reached", false)),
		"coordinated_turn_fraction": float(trial.get("coordinated_turn_fraction", 0.0)),
		"min_clearance_m": min_clearance,
		"mean_path_cross_track_m": float(trial.get("mean_path_cross_track_m", 0.0)),
		"path_slalom_crossings": int(trial.get("path_slalom_crossings", 0)),
		"no_path_time_s": float(trial.get("no_path_time_s", 0.0)),
		"scored": bool(trial.get("scored", false)),
	}


func _finalize_trial_metrics(trial: Dictionary) -> void:
	var scored_time := maxf(float(trial.get("scored_time_s", 0.0)), 0.001)
	var path_required_time := maxf(float(trial.get("path_required_time_s", 0.0)), 0.001)
	trial["no_path_fraction"] = float(trial.get("no_path_time_s", 0.0)) / path_required_time
	trial["mean_speed_mps"] = float(trial.get("speed_integral", 0.0)) / scored_time
	trial["mean_feeler_strength"] = float(trial.get("feeler_strength_integral", 0.0)) / scored_time
	trial["feeler_active_fraction"] = float(trial.get("feeler_active_s", 0.0)) / scored_time
	trial["mean_path_cross_track_m"] = float(trial.get("path_cross_track_integral", 0.0)) / scored_time
	trial["mean_path_heading_error_deg"] = float(trial.get("path_heading_error_integral", 0.0)) / scored_time
	trial["mean_path_fpv_error_deg"] = float(trial.get("path_fpv_error_integral", 0.0)) / scored_time
	trial["mean_path_fpv_vertical_error_deg"] = float(trial.get("path_fpv_vertical_error_integral", 0.0)) / scored_time
	var turn_time := maxf(float(trial.get("turn_time_s", 0.0)), 0.001)
	trial["mean_turn_speed_mps"] = float(trial.get("turn_speed_integral", 0.0)) / turn_time
	trial["mean_turn_bank_deg"] = float(trial.get("turn_bank_integral", 0.0)) / turn_time
	trial["mean_turn_rate_deg_s"] = float(trial.get("turn_rate_integral", 0.0)) / turn_time
	trial["mean_turn_heading_error_deg"] = float(trial.get("turn_heading_error_integral", 0.0)) / turn_time
	trial["mean_turn_target_roll"] = float(trial.get("turn_target_roll_integral", 0.0)) / turn_time
	trial["mean_signed_turn_error_deg"] = float(trial.get("turn_signed_error_integral", 0.0)) / turn_time
	trial["mean_signed_bank_deg"] = float(trial.get("turn_signed_bank_integral", 0.0)) / turn_time
	trial["mean_signed_target_roll"] = float(trial.get("turn_signed_target_roll_integral", 0.0)) / turn_time
	trial["turn_correct_bank_fraction"] = float(trial.get("turn_correct_bank_s", 0.0)) / turn_time
	trial["turn_opposing_bank_fraction"] = float(trial.get("turn_opposing_bank_s", 0.0)) / turn_time
	trial["turn_weak_bank_fraction"] = float(trial.get("turn_weak_bank_s", 0.0)) / turn_time
	trial["turn_correct_roll_cmd_fraction"] = float(trial.get("turn_correct_roll_cmd_s", 0.0)) / turn_time
	trial["turn_opposing_roll_cmd_fraction"] = float(trial.get("turn_opposing_roll_cmd_s", 0.0)) / turn_time
	trial["turn_weak_roll_cmd_fraction"] = float(trial.get("turn_weak_roll_cmd_s", 0.0)) / turn_time
	var coordination_time := maxf(float(trial.get("coordination_time_s", 0.0)), 0.001)
	trial["mean_ball_abs_g"] = float(trial.get("ball_abs_g_integral", 0.0)) / coordination_time
	trial["mean_sideslip_abs_deg"] = float(trial.get("sideslip_abs_integral", 0.0)) / coordination_time
	trial["mean_yaw_track_mismatch_deg_s"] = float(trial.get("yaw_track_mismatch_integral", 0.0)) / coordination_time
	trial["coordinated_turn_fraction"] = float(trial.get("coordinated_time_s", 0.0)) / coordination_time
	for key in ["min_local_agl_m", "min_feeler_clearance_m", "min_horizontal_clearance_m"]:
		if not is_finite(float(trial.get(key, INF))):
			trial[key] = -1.0


func _score_trial(trial: Dictionary) -> float:
	var score := 0.0
	if bool(trial.get("lz_reached", false)):
		score += 700.0
	if bool(trial.get("lap_completed", false)):
		score += 2000.0
	var reason := String(trial.get("exit_reason", "unknown"))
	if reason == "crash":
		# A crash often means the route/LZ/terrain setup handed the aircraft a bad
		# problem, not that the controller was bad. Let the sampled path-following,
		# clearance, and feeler metrics carry the blame instead of adding a large
		# terminal penalty.
		score -= 0.0
	elif reason == "timeout" or reason == "stuck":
		score -= 500.0
	var lap_time_score := _get_clean_lap_time_score(trial)
	trial["lap_time_score"] = lap_time_score
	score += lap_time_score
	# Survival used to get a positive scored-time bonus here. That was helpful when
	# most candidates failed early, but it fights the new "clean but brisk" goal
	# now that full laps are common.
	score -= float(trial.get("vertical_risk_s", 0.0)) * 110.0
	score -= float(trial.get("horizontal_risk_s", 0.0)) * 85.0
	score -= float(trial.get("cross_track_risk_s", 0.0)) * maxf(path_cross_track_penalty, 0.0)
	score -= maxf(float(trial.get("mean_path_cross_track_m", 0.0)) - path_cross_track_good_m, 0.0) \
			* maxf(path_cross_track_mean_penalty, 0.0)
	score -= float(trial.get("path_slalom_crossings", 0)) * maxf(path_slalom_penalty, 0.0)
	score -= float(trial.get("path_heading_error_integral", 0.0)) * maxf(path_heading_error_penalty, 0.0)
	score -= float(trial.get("path_fpv_error_integral", 0.0)) * maxf(path_fpv_error_penalty, 0.0)
	score -= float(trial.get("path_fpv_vertical_error_integral", 0.0)) * maxf(path_fpv_vertical_error_penalty, 0.0)
	score -= float(trial.get("mean_feeler_strength", 0.0)) * maxf(feeler_strength_penalty, 0.0)
	score -= float(trial.get("feeler_active_fraction", 0.0)) * maxf(feeler_active_penalty, 0.0)
	var genome_variant: Variant = trial.get("genome", {})
	if genome_variant is Dictionary:
		score -= _get_feeler_budget_score(genome_variant as Dictionary) * maxf(feeler_budget_penalty, 0.0)
	score -= float(trial.get("ball_risk_s", 0.0)) * 35.0
	score -= float(trial.get("sideslip_risk_s", 0.0)) * 20.0
	score -= float(trial.get("yaw_without_track_s", 0.0)) * 20.0
	score -= float(trial.get("excess_agl_integral", 0.0)) * 8.0
	score -= minf(float(trial.get("duration_s", 0.0)) * 0.05, 250.0)
	score -= float(trial.get("low_down_clearance_s", 0.0)) * 35.0
	score -= float(trial.get("sinking_low_down_clearance_s", 0.0)) * 120.0
	score += minf(float(trial.get("climbing_low_down_clearance_s", 0.0)) * 10.0, 80.0)
	var min_horizontal := float(trial.get("min_horizontal_clearance_m", -1.0))
	if min_horizontal >= 0.0:
		score -= clampf((horizontal_soft_clearance_m - min_horizontal) / maxf(horizontal_soft_clearance_m, 1.0), 0.0, 1.0) * 500.0
	if float(trial.get("coordination_time_s", 0.0)) >= 5.0:
		# Bounded fraction reward: good coordination helps, but there is no incentive
		# to prolong a turn merely to accumulate more reward.
		score += clampf(float(trial.get("coordinated_turn_fraction", 0.0)), 0.0, 1.0) * 300.0
	return score


func _get_clean_lap_time_score(trial: Dictionary) -> float:
	if not bool(trial.get("lap_completed", false)):
		return 0.0
	var route_index := clampi(int(trial.get("route", 0)), 0, ROUTE_CLEAN_LAP_TARGET_S.size() - 1)
	var target_s := float(ROUTE_CLEAN_LAP_TARGET_S[route_index])
	var duration_s := maxf(float(trial.get("duration_s", 0.0)), 1.0)
	var delta_s := target_s - duration_s
	if delta_s >= 0.0:
		return minf(delta_s * maxf(clean_lap_time_reward, 0.0), maxf(clean_lap_time_cap, 0.0))
	return -minf(-delta_s * maxf(slow_lap_time_penalty, 0.0), maxf(clean_lap_time_cap, 0.0))


func _get_feeler_budget_score(genome: Dictionary) -> float:
	var budget := 0.0
	budget += clampf(float(genome.get("lateral_obstacle_probe_dist_m", 85.0)) / 130.0, 0.0, 1.5)
	budget += clampf(float(genome.get("lateral_obstacle_probe_speed_scale", 1.7)) / 3.0, 0.0, 1.5)
	budget += clampf(float(genome.get("lateral_obstacle_probe_max_dist_m", 260.0)) / 380.0, 0.0, 1.5)
	budget += clampf(float(genome.get("lateral_obstacle_roll_gain", 0.25)) / 0.50, 0.0, 1.5)
	budget += clampf(float(genome.get("lateral_obstacle_yaw_gain", 0.12)) / 0.30, 0.0, 1.5)
	budget += clampf(float(genome.get("lateral_obstacle_side_push_mps", 7.0)) / 18.0, 0.0, 1.5)
	budget += clampf(float(genome.get("heightmap_safe_direction_probe_dist_m", 145.0)) / 230.0, 0.0, 1.5)
	budget += clampf(float(genome.get("heightmap_safe_direction_probe_speed_scale", 1.5)) / 3.0, 0.0, 1.5)
	budget += clampf(float(genome.get("heightmap_safe_direction_probe_max_dist_m", 380.0)) / 520.0, 0.0, 1.5)
	budget += clampf(float(genome.get("heightmap_safe_direction_roll_gain", 0.28)) / 0.55, 0.0, 1.5)
	budget += clampf(float(genome.get("heightmap_safe_direction_yaw_gain", 0.16)) / 0.35, 0.0, 1.5)
	budget += clampf(float(genome.get("heightmap_safe_direction_side_push_mps", 10.0)) / 24.0, 0.0, 1.5)
	return budget / 12.0


func _try_evolve_generation() -> void:
	var required := _population.size() * maxi(route_count, 1)
	if _generation_results.size() < required or not _pending_scored_trials.is_empty():
		return
	var summaries: Array[Dictionary] = []
	for candidate in range(_population.size()):
		var candidate_trials: Array[Dictionary] = []
		for trial_variant in _generation_results:
			var trial := trial_variant as Dictionary
			if int(trial.get("candidate", -1)) == candidate:
				candidate_trials.append(trial)
		if candidate_trials.is_empty():
			continue
		var laps := 0
		var lz_reached := 0
		var crashes := 0
		var fitness_sum := 0.0
		var worst_fitness := INF
		var horizontal_risk_sum := 0.0
		var vertical_risk_sum := 0.0
		var cross_track_risk_sum := 0.0
		var mean_cross_track_sum := 0.0
		var mean_heading_error_sum := 0.0
		var slalom_sum := 0
		var mean_feeler_strength_sum := 0.0
		var feeler_active_fraction_sum := 0.0
		var scored_time_sum := 0.0
		var duration_sum := 0.0
		var lap_time_score_sum := 0.0
		for trial in candidate_trials:
			laps += 1 if bool(trial.get("lap_completed", false)) else 0
			lz_reached += 1 if bool(trial.get("lz_reached", false)) else 0
			crashes += 1 if String(trial.get("exit_reason", "")) == "crash" else 0
			var trial_fitness := float(trial.get("fitness", -10000.0))
			fitness_sum += trial_fitness
			worst_fitness = minf(worst_fitness, trial_fitness)
			horizontal_risk_sum += float(trial.get("horizontal_risk_s", 0.0))
			vertical_risk_sum += float(trial.get("vertical_risk_s", 0.0))
			cross_track_risk_sum += float(trial.get("cross_track_risk_s", 0.0))
			mean_cross_track_sum += float(trial.get("mean_path_cross_track_m", 0.0))
			mean_heading_error_sum += float(trial.get("mean_path_heading_error_deg", 0.0))
			slalom_sum += int(trial.get("path_slalom_crossings", 0))
			mean_feeler_strength_sum += float(trial.get("mean_feeler_strength", 0.0))
			feeler_active_fraction_sum += float(trial.get("feeler_active_fraction", 0.0))
			scored_time_sum += float(trial.get("scored_time_s", 0.0))
			duration_sum += float(trial.get("duration_s", 0.0))
			lap_time_score_sum += float(trial.get("lap_time_score", _get_clean_lap_time_score(trial)))
		var count := candidate_trials.size()
		var mean_fitness := fitness_sum / float(count)
		var mean_cross_track := mean_cross_track_sum / float(count)
		var mean_heading_error := mean_heading_error_sum / float(count)
		var mean_slalom := float(slalom_sum) / float(count)
		var mean_cross_track_risk := cross_track_risk_sum / float(count)
		var mean_scored_time := scored_time_sum / float(count)
		var mean_duration := duration_sum / float(count)
		var mean_lap_time_score := lap_time_score_sum / float(count)
		# Controller-tuning phase: rank primarily by path following. Crashes still
		# matter, but they should not swamp the useful gradient from cross-track,
		# heading error, and slalom while most candidates are still fragile. Clean
		# lap-time is now a secondary tie-breaker; raw time aloft is not rewarded.
		var aggregate := clampf(mean_fitness, -40000.0, 12000.0) \
				- mean_cross_track * 18.0 \
				- mean_cross_track_risk * 160.0 \
				- mean_heading_error * 45.0 \
				- mean_slalom * 450.0 \
				+ mean_lap_time_score \
				+ float(lz_reached) * 600.0 \
				+ float(laps) * 1800.0 \
				- float(crashes) * 0.0 \
				+ clampf(worst_fitness, -20000.0, 6000.0) * 0.10
		summaries.append({
			"candidate": candidate, "fitness": aggregate, "trials": count,
			"laps": laps, "lz_reached": lz_reached, "crashes": crashes,
			"mean_trial_fitness": mean_fitness, "worst_trial_fitness": worst_fitness,
			"mean_horizontal_risk_s": horizontal_risk_sum / float(count),
			"mean_vertical_risk_s": vertical_risk_sum / float(count),
			"mean_cross_track_risk_s": mean_cross_track_risk,
			"mean_path_cross_track_m": mean_cross_track,
			"mean_path_heading_error_deg": mean_heading_error,
			"mean_path_slalom_crossings": mean_slalom,
			"mean_scored_time_s": mean_scored_time,
			"mean_duration_s": mean_duration,
			"mean_lap_time_score": mean_lap_time_score,
			"mean_feeler_strength": mean_feeler_strength_sum / float(count),
			"mean_feeler_active_fraction": feeler_active_fraction_sum / float(count),
			"genome": _population[candidate].duplicate(true),
		})
	summaries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["fitness"]) > float(b["fitness"])
	)
	if summaries.is_empty():
		return
	for summary in summaries:
		_log_event("CANDIDATE_SUMMARY", summary)
	var champion: Dictionary = summaries[0]
	var new_best := float(champion["fitness"]) > _best_fitness
	if new_best:
		_best_fitness = float(champion["fitness"])
		_best_genome = (champion["genome"] as Dictionary).duplicate(true)
		_best_result = champion.duplicate(true)
	_log_event("GENERATION", {
		"generation": _generation, "new_all_time_best": new_best,
		"generation_best_fitness": champion["fitness"],
		"all_time_best_fitness": _best_fitness,
		"laps": champion["laps"], "lz_reached": champion["lz_reached"],
		"crashes": champion["crashes"], "genome": champion["genome"],
	})
	_breed_next_population(summaries)
	_generation += 1
	_generation_results.clear()
	_pending_scored_trials.clear()
	_reset_route_rounds()
	_save_state()


func _breed_next_population(ranked: Array[Dictionary]) -> void:
	var next_population: Array[Dictionary] = []
	if not _best_genome.is_empty():
		next_population.append(_best_genome.duplicate(true))
	var elites := mini(maxi(elite_count, 1), ranked.size())
	for i in range(elites):
		var elite: Dictionary = (ranked[i]["genome"] as Dictionary).duplicate(true)
		if elite != _best_genome and next_population.size() < maxi(population_size, 4):
			next_population.append(elite)
	var parent_pool := maxi(elites, int(ceil(float(ranked.size()) * 0.5)))
	while next_population.size() < maxi(population_size, 4):
		var a: Dictionary = ranked[_rng.randi_range(0, parent_pool - 1)]["genome"]
		var b: Dictionary = ranked[_rng.randi_range(0, parent_pool - 1)]["genome"]
		next_population.append(_mutate(_crossover(a, b), mutation_scale))
	_population = next_population


func _build_initial_population() -> void:
	_population.clear()
	var seed := _clamp_genome(_best_genome if not _best_genome.is_empty() else _base_genome())
	_population.append(seed)
	while _population.size() < maxi(population_size, 4):
		_population.append(_mutate(seed, mutation_scale * 1.35))


func _base_genome() -> Dictionary:
	var genome := {}
	for spec in PARAM_SPECS:
		genome[String(spec["name"])] = float(spec["base"])
	return genome


func _crossover(a: Dictionary, b: Dictionary) -> Dictionary:
	var child := {}
	for spec in PARAM_SPECS:
		var key := String(spec["name"])
		child[key] = float(a.get(key, spec["base"])) if _rng.randf() < 0.5 else float(b.get(key, spec["base"]))
	return _clamp_genome(child)


func _mutate(source: Dictionary, scale: float) -> Dictionary:
	var genome := source.duplicate(true)
	var specs: Array = []
	for spec in PARAM_SPECS:
		if not focus_turn_controller or TURN_CONTROL_PARAMS.has(String(spec["name"])):
			specs.append(spec)
	specs.shuffle()
	var count := mini(maxi(focused_mutations_per_child, 1), specs.size())
	for i in range(count):
		var spec: Dictionary = specs[i]
		var key := String(spec["name"])
		genome[key] = float(genome.get(key, spec["base"])) \
				+ _rng.randfn(0.0, float(spec["sigma"]) * maxf(scale, 0.01))
	return _clamp_genome(genome)


func _clamp_genome(source: Dictionary) -> Dictionary:
	var genome := {}
	for spec in PARAM_SPECS:
		var key := String(spec["name"])
		genome[key] = clampf(float(source.get(key, spec["base"])), float(spec["min"]), float(spec["max"]))
	genome["terrain_hazard_max_lookahead_m"] = maxf(float(genome["terrain_hazard_max_lookahead_m"]), float(genome["terrain_hazard_min_lookahead_m"]))
	genome["lateral_obstacle_probe_max_dist_m"] = maxf(float(genome["lateral_obstacle_probe_max_dist_m"]), float(genome["lateral_obstacle_probe_dist_m"]))
	genome["heightmap_safe_direction_probe_max_dist_m"] = maxf(float(genome["heightmap_safe_direction_probe_max_dist_m"]), float(genome["heightmap_safe_direction_probe_dist_m"]))
	genome["terrain_recovery_full_agl_m"] = minf(float(genome["terrain_recovery_full_agl_m"]), float(genome["terrain_recovery_agl_m"]) - 5.0)
	return genome


func _reset_route_rounds() -> void:
	_route_rounds.clear()
	for _i in range(maxi(route_count, 1)):
		_route_rounds.append(0)


func _get_trial(trial_id: int) -> Dictionary:
	var value: Variant = _trials.get(trial_id, {})
	return value as Dictionary if value is Dictionary else {}


func _trial_log_data(trial: Dictionary) -> Dictionary:
	return {
		"trial": trial["id"], "generation": trial["generation"],
		"candidate": trial["candidate"], "route": int(trial["route"]) + 1,
		"scored": trial["scored"], "unscored_reason": String(trial.get("unscored_reason", "")),
		"reason": trial["exit_reason"],
		"fitness": trial["fitness"], "duration_s": trial["duration_s"],
		"lap_time_score": trial.get("lap_time_score", 0.0),
		"lz_reached": trial["lz_reached"], "lap_completed": trial["lap_completed"],
		"min_local_agl_m": trial["min_local_agl_m"],
		"min_feeler_clearance_m": trial["min_feeler_clearance_m"],
		"min_horizontal_clearance_m": trial["min_horizontal_clearance_m"],
		"vertical_risk_s": trial["vertical_risk_s"],
		"low_down_clearance_s": trial["low_down_clearance_s"],
		"sinking_low_down_clearance_s": trial["sinking_low_down_clearance_s"],
		"climbing_low_down_clearance_s": trial["climbing_low_down_clearance_s"],
		"horizontal_risk_s": trial["horizontal_risk_s"],
		"cross_track_risk_s": trial["cross_track_risk_s"],
		"max_path_cross_track_m": trial["max_path_cross_track_m"],
		"mean_path_cross_track_m": trial["mean_path_cross_track_m"],
		"mean_path_heading_error_deg": trial["mean_path_heading_error_deg"],
		"mean_path_fpv_error_deg": trial.get("mean_path_fpv_error_deg", 0.0),
		"mean_path_fpv_vertical_error_deg": trial.get("mean_path_fpv_vertical_error_deg", 0.0),
		"path_slalom_crossings": trial["path_slalom_crossings"],
		"max_sink_mps": trial["max_sink_mps"],
		"mean_speed_mps": trial["mean_speed_mps"],
		"mean_feeler_strength": trial["mean_feeler_strength"],
		"feeler_active_fraction": trial["feeler_active_fraction"],
		"mean_turn_speed_mps": trial["mean_turn_speed_mps"],
		"mean_turn_bank_deg": trial["mean_turn_bank_deg"],
		"mean_turn_rate_deg_s": trial["mean_turn_rate_deg_s"],
		"mean_turn_heading_error_deg": trial["mean_turn_heading_error_deg"],
		"mean_turn_target_roll": trial["mean_turn_target_roll"],
		"mean_signed_turn_error_deg": trial["mean_signed_turn_error_deg"],
		"mean_signed_bank_deg": trial["mean_signed_bank_deg"],
		"mean_signed_target_roll": trial["mean_signed_target_roll"],
		"turn_correct_bank_fraction": trial["turn_correct_bank_fraction"],
		"turn_opposing_bank_fraction": trial["turn_opposing_bank_fraction"],
		"turn_weak_bank_fraction": trial["turn_weak_bank_fraction"],
		"turn_correct_roll_cmd_fraction": trial["turn_correct_roll_cmd_fraction"],
		"turn_opposing_roll_cmd_fraction": trial["turn_opposing_roll_cmd_fraction"],
		"turn_weak_roll_cmd_fraction": trial["turn_weak_roll_cmd_fraction"],
		"turn_altitude_loss_m": trial["turn_altitude_loss_m"],
		"mean_ball_abs_g": trial["mean_ball_abs_g"],
		"mean_sideslip_abs_deg": trial["mean_sideslip_abs_deg"],
		"mean_yaw_track_mismatch_deg_s": trial["mean_yaw_track_mismatch_deg_s"],
		"coordinated_turn_fraction": trial["coordinated_turn_fraction"],
		"ball_risk_s": trial["ball_risk_s"],
		"sideslip_risk_s": trial["sideslip_risk_s"],
		"yaw_without_track_s": trial["yaw_without_track_s"],
		"wrong_way_bank_s": trial["wrong_way_bank_s"],
		"close_calls": trial["close_calls"],
		"path_required_time_s": trial.get("path_required_time_s", 0.0),
		"no_path_time_s": trial.get("no_path_time_s", 0.0),
		"no_path_fraction": trial.get("no_path_fraction", 0.0),
		"no_path_events": trial.get("no_path_events", 0),
		"genome": trial["genome"],
	}


func _trial_progress_log_data(trial: Dictionary) -> Dictionary:
	var scored_time := maxf(float(trial.get("scored_time_s", 0.0)), 0.001)
	return {
		"trial": trial["id"], "generation": trial["generation"],
		"candidate": trial["candidate"], "route": int(trial["route"]) + 1,
		"elapsed_s": _now_s() - float(trial["started_s"]),
		"scored_time_s": trial["scored_time_s"],
		"no_path_time_s": trial.get("no_path_time_s", 0.0),
		"no_path_events": trial.get("no_path_events", 0),
		"min_local_agl_m": _finite_or_negative_one(float(trial["min_local_agl_m"])),
		"min_feeler_clearance_m": _finite_or_negative_one(float(trial["min_feeler_clearance_m"])),
		"min_horizontal_clearance_m": _finite_or_negative_one(float(trial["min_horizontal_clearance_m"])),
		"vertical_risk_s": trial["vertical_risk_s"],
		"low_down_clearance_s": trial["low_down_clearance_s"],
		"sinking_low_down_clearance_s": trial["sinking_low_down_clearance_s"],
		"climbing_low_down_clearance_s": trial["climbing_low_down_clearance_s"],
		"horizontal_risk_s": trial["horizontal_risk_s"],
		"cross_track_risk_s": trial["cross_track_risk_s"],
		"max_path_cross_track_m": trial["max_path_cross_track_m"],
		"mean_path_cross_track_m": float(trial["path_cross_track_integral"]) / scored_time,
		"mean_path_heading_error_deg": float(trial["path_heading_error_integral"]) / scored_time,
		"mean_path_fpv_error_deg": float(trial.get("path_fpv_error_integral", 0.0)) / scored_time,
		"mean_path_fpv_vertical_error_deg": float(trial.get("path_fpv_vertical_error_integral", 0.0)) / scored_time,
		"path_slalom_crossings": trial["path_slalom_crossings"],
		"max_sink_mps": trial["max_sink_mps"],
		"mean_speed_mps": float(trial["speed_integral"]) / scored_time,
		"mean_feeler_strength": float(trial["feeler_strength_integral"]) / scored_time,
		"feeler_active_fraction": float(trial["feeler_active_s"]) / scored_time,
		"turn_time_s": trial["turn_time_s"],
		"mean_turn_speed_mps": float(trial["turn_speed_integral"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"mean_turn_bank_deg": float(trial["turn_bank_integral"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"mean_turn_rate_deg_s": float(trial["turn_rate_integral"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"mean_signed_turn_error_deg": float(trial["turn_signed_error_integral"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"mean_signed_bank_deg": float(trial["turn_signed_bank_integral"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"mean_signed_target_roll": float(trial["turn_signed_target_roll_integral"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"turn_correct_bank_fraction": float(trial["turn_correct_bank_s"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"turn_opposing_bank_fraction": float(trial["turn_opposing_bank_s"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"turn_weak_bank_fraction": float(trial["turn_weak_bank_s"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"turn_correct_roll_cmd_fraction": float(trial["turn_correct_roll_cmd_s"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"turn_opposing_roll_cmd_fraction": float(trial["turn_opposing_roll_cmd_s"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"turn_weak_roll_cmd_fraction": float(trial["turn_weak_roll_cmd_s"]) / maxf(float(trial["turn_time_s"]), 0.001),
		"turn_altitude_loss_m": trial["turn_altitude_loss_m"],
		"mean_ball_abs_g": float(trial["ball_abs_g_integral"]) / maxf(float(trial["coordination_time_s"]), 0.001),
		"mean_sideslip_abs_deg": float(trial["sideslip_abs_integral"]) / maxf(float(trial["coordination_time_s"]), 0.001),
		"mean_yaw_track_mismatch_deg_s": float(trial["yaw_track_mismatch_integral"]) / maxf(float(trial["coordination_time_s"]), 0.001),
		"coordinated_turn_fraction": float(trial["coordinated_time_s"]) / maxf(float(trial["coordination_time_s"]), 0.001),
		"ball_risk_s": trial["ball_risk_s"],
		"sideslip_risk_s": trial["sideslip_risk_s"],
		"yaw_without_track_s": trial["yaw_without_track_s"],
		"close_calls": trial["close_calls"],
	}


func _finite_or_negative_one(value: float) -> float:
	return value if is_finite(value) else -1.0


func _now_s() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _start_log() -> void:
	var header := "HELI NAVIGATION TUNING START time=%s generation=%d population=%d routes=%d fitness_version=%d" % [
		Time.get_datetime_string_from_system(), _generation, _population.size(), maxi(route_count, 1), FITNESS_VERSION]
	_write_line(log_path, header, false)
	if project_mirror_enabled:
		_write_line(project_mirror_path, header, false)


func _log_event(event_name: String, data: Dictionary) -> void:
	var line := "t=%.2f event=%s %s" % [_now_s(), event_name, JSON.stringify(data)]
	_write_line(log_path, line, true)
	if project_mirror_enabled:
		_write_line(project_mirror_path, line, true)


func _write_line(path: String, line: String, append: bool) -> void:
	var mode := FileAccess.READ_WRITE if append and FileAccess.file_exists(path) else FileAccess.WRITE
	var file := FileAccess.open(path, mode)
	if file == null:
		push_warning("HelicopterNavigationTuner could not open %s" % path)
		return
	if append:
		file.seek_end()
	file.store_line(line)


func _load_state() -> void:
	var state: Dictionary = {}
	for candidate_path in [state_path, champion_project_mirror_path]:
		var candidate := _read_json_file(String(candidate_path))
		if not candidate.is_empty():
			state = candidate
			break
	if state.is_empty():
		var seed_state := _read_json_file(seed_genome_path)
		var seed_genome_variant: Variant = seed_state.get("best_genome", {})
		if seed_genome_variant is Dictionary:
			_best_genome = _clamp_genome(seed_genome_variant as Dictionary)
			_best_fitness = -INF
			_best_result = {}
		return
	var compatible := int(state.get("fitness_version", 0)) == FITNESS_VERSION \
			and int(state.get("evaluation_version", 0)) == EVALUATION_VERSION \
			and int(state.get("route_count", 0)) == maxi(route_count, 1)
	if not compatible:
		_generation = 0
		var incompatible_genome_variant: Variant = state.get("best_genome", {})
		if incompatible_genome_variant is Dictionary:
			# Seed the next run from the previous champion's control values, but do
			# not compare old fitness numbers after a scoring-policy change.
			_best_genome = _clamp_genome(incompatible_genome_variant as Dictionary)
		_best_fitness = -INF
		_best_result = {}
		return
	_generation = maxi(int(state.get("generation", 0)), 0)
	var genome_variant: Variant = state.get("best_genome", {})
	if genome_variant is Dictionary:
		_best_genome = _clamp_genome(genome_variant as Dictionary)
	_best_fitness = float(state.get("best_fitness", -INF))
	var result_variant: Variant = state.get("best_result", {})
	if result_variant is Dictionary:
		_best_result = (result_variant as Dictionary).duplicate(true)


func _read_json_file(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _save_state() -> void:
	var state := {
		"fitness_version": FITNESS_VERSION, "evaluation_version": EVALUATION_VERSION,
		"route_count": maxi(route_count, 1), "generation": _generation,
		"best_fitness": _best_fitness, "best_genome": _best_genome,
		"best_result": _best_result,
	}
	_write_json_file(state_path, state)
	if project_mirror_enabled and not champion_project_mirror_path.is_empty():
		_write_json_file(champion_project_mirror_path, state)


func _write_json_file(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("HelicopterNavigationTuner could not save %s" % path)
		return
	file.store_string(JSON.stringify(data, "  "))
