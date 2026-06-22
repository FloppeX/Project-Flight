extends Node

## Online evolutionary tuner for the clean helicopter attack state machine.
## Each attack receives one bounded parameter genome. Completed attacks are scored,
## logged, and used to breed the next population without restarting the game.

@export var enabled: bool = true
@export_range(4, 64, 1) var population_size: int = 8
@export_range(1, 8, 1) var elite_count: int = 2
@export_range(2, 8, 1) var trials_per_candidate: int = 5
@export_range(0.0, 1.0, 0.01) var mutation_probability: float = 0.65
@export_range(0.1, 4.0, 0.1) var mutation_scale: float = 1.0
@export var focus_aim_controller_only: bool = false
@export var focus_ballistic_correction_only: bool = false
@export var focus_attack_efficiency_only: bool = true
@export_range(1, 3, 1) var focused_mutations_per_child: int = 1
@export var use_targeted_aim_grid: bool = true
@export var use_targeted_ballistic_grid: bool = true
@export_range(0.0, 10.0, 0.1) var result_grace_s: float = 5.0
# Safety valves for trials whose pilot disappears without calling end_trial(), or
# whose attack state gets stuck. Normal runs in the current test data begin within
# ~140 s and finish within ~55 s of RUN, so these retain generous headroom.
@export var active_trial_pre_run_timeout_s: float = 240.0
@export var active_trial_post_run_timeout_s: float = 90.0
@export var unobserved_rocket_miss_m: float = 1000.0
@export var grouping_bonus_reference_m: float = 100.0
@export var grouping_bonus_max: float = 10.0
# Sustained-tracking reward: rewards genomes that HOLD the nose on the target through
# the run (vs. briefly grazing it then flying past). A sample counts as "in range"
# below aim_track_range_m and "aligned" at/above aim_track_dot; the reward scales
# with the aligned fraction.
@export var aim_track_range_m: float = 700.0
@export var aim_track_dot: float = 0.98
@export var aim_track_bonus_max: float = 8.0
@export var log_path: String = "user://heli_combat_tuning.log"
@export var project_mirror_enabled: bool = true
@export var project_mirror_path: String = "res://heli_combat_tuning.log"
@export var state_path: String = "user://heli_combat_tuning_state.json"
@export var champion_project_mirror_path: String = "res://heli_combat_champion.json"

const PARAM_SPECS := [
	{"name": "atk_ingress_distance_m", "base": 1300.0, "min": 800.0, "max": 1500.0, "sigma": 100.0},
	{"name": "atk_breakoff_distance_m", "base": 379.038306593895, "min": 220.0, "max": 450.0, "sigma": 30.0},
	{"name": "atk_run_timeout_s", "base": 20.0, "min": 15.0, "max": 40.0, "sigma": 3.0},
	{"name": "atk_fire_cone_deg", "base": 3.5, "min": 2.5, "max": 7.0, "sigma": 0.5},
	{"name": "atk_fire_range_m", "base": 807.382278442383, "min": 550.0, "max": 1000.0, "sigma": 60.0},
	{"name": "atk_speed_mps", "base": 28.0, "min": 28.0, "max": 48.0, "sigma": 3.0},
	{"name": "atk_egress_distance_m", "base": 701.068078041077, "min": 450.0, "max": 1100.0, "sigma": 100.0},
	{"name": "atk_aim_yaw_gain", "base": 2.2, "min": 0.6, "max": 4.0, "sigma": 0.35},
	{"name": "atk_aim_yaw_damping", "base": 0.9, "min": 0.1, "max": 2.0, "sigma": 0.18},
	{"name": "atk_aim_yaw_max", "base": 0.647095043957233, "min": 0.25, "max": 1.0, "sigma": 0.08},
	{"name": "atk_pitch_aim_gain", "base": 2.05854495167732, "min": 0.8, "max": 5.0, "sigma": 0.4},
	{"name": "atk_pitch_aim_damping", "base": 0.6, "min": 0.1, "max": 1.5, "sigma": 0.15},
	{"name": "atk_pitch_aim_max_input", "base": 0.689764803647995, "min": 0.25, "max": 0.9, "sigma": 0.08},
	{"name": "combat_rocket_ccip_aim_correction_strength", "base": 0.932934373617172, "min": 0.35, "max": 2.0, "sigma": 0.20},
	{"name": "combat_rocket_aim_lower_bias_m", "base": 1.53823965787888, "min": 0.0, "max": 8.0, "sigma": 1.25},
]
const FITNESS_VERSION: int = 6
const EVALUATION_VERSION: int = 9
const AIM_FOCUS_PARAMS := {
	"atk_aim_yaw_gain": true,
	"atk_aim_yaw_damping": true,
	"atk_aim_yaw_max": true,
	"atk_pitch_aim_gain": true,
	"atk_pitch_aim_damping": true,
	"atk_pitch_aim_max_input": true,
}
const BALLISTIC_FOCUS_PARAMS := {
	"combat_rocket_ccip_aim_correction_strength": true,
	"combat_rocket_aim_lower_bias_m": true,
}
const EFFICIENCY_FOCUS_PARAMS := {
	"atk_ingress_distance_m": true,
	"atk_breakoff_distance_m": true,
	"atk_fire_range_m": true,
	"atk_speed_mps": true,
	"atk_egress_distance_m": true,
}
const TARGETED_AIM_GRID := [
	{},
	{"atk_aim_yaw_gain": 1.5},
	{"atk_aim_yaw_gain": 1.7},
	{"atk_aim_yaw_gain": 1.9},
	{"atk_pitch_aim_gain": 1.8},
	{"atk_pitch_aim_gain": 2.05},
	{"atk_pitch_aim_gain": 2.25},
	{"atk_aim_yaw_gain": 1.7, "atk_pitch_aim_gain": 2.15},
]
const TARGETED_BALLISTIC_GRID := [
	{},
	{"combat_rocket_ccip_aim_correction_strength": 0.50},
	{"combat_rocket_ccip_aim_correction_strength": 0.75},
	{"combat_rocket_ccip_aim_correction_strength": 1.25},
	{"combat_rocket_ccip_aim_correction_strength": 1.50},
	{"combat_rocket_ccip_aim_correction_strength": 2.00},
	{"combat_rocket_aim_lower_bias_m": 0.0},
	{"combat_rocket_aim_lower_bias_m": 4.0},
]
const TARGETED_EFFICIENCY_GRID := [
	{},
	{"atk_speed_mps": 28.0},
	{"atk_speed_mps": 32.0},
	{"atk_breakoff_distance_m": 250.0},
	{"atk_speed_mps": 28.0, "atk_breakoff_distance_m": 250.0},
	{"atk_ingress_distance_m": 1300.0},
	{"atk_speed_mps": 28.0, "atk_ingress_distance_m": 1300.0},
	{"atk_fire_range_m": 900.0},
]

var _rng := RandomNumberGenerator.new()
var _generation: int = 0
var _population: Array[Dictionary] = []
var _assignment_index: int = 0
var _generation_results: Array[Dictionary] = []
var _generation_pending_trial_ids: Dictionary = {}
var _trials: Dictionary = {}
var _active_by_pilot: Dictionary = {}
var _next_trial_id: int = 1
var _best_fitness: float = -INF
var _best_genome: Dictionary = {}
var _best_result: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_load_state()
	_build_initial_population()
	_start_log()
	set_process(enabled)


func begin_trial(pilot_id: int, craft_name: String, craft_type: String, target_name: String, weapon_kind: String) -> Dictionary:
	if not enabled or _population.is_empty():
		return {}
	if _active_by_pilot.has(pilot_id):
		end_trial(int(_active_by_pilot[pilot_id]), "replaced")
	# Each candidate is tested repeatedly. Round-robin assignment spreads map/time
	# conditions across genomes instead of giving one candidate a consecutive block.
	var required_trials := _required_scored_trial_count()
	var scored := _assignment_index < required_trials
	var candidate_index := _assignment_index % _population.size() if scored else 0
	var repeat_index := floori(float(_assignment_index) / float(_population.size())) if scored else -1
	if scored:
		_assignment_index += 1
	var trial_id := _next_trial_id
	_next_trial_id += 1
	var genome: Dictionary = _population[candidate_index].duplicate(true)
	var trial := {
		"id": trial_id,
		"pilot_id": pilot_id,
		"generation": _generation,
		"candidate": candidate_index,
		"repeat": repeat_index,
		"scored": scored,
		"craft": craft_name,
		"craft_type": craft_type,
		"target": target_name,
		"weapon": weapon_kind,
		"genome": genome,
		"started_s": _now_s(),
		"run_started_s": -1.0,
		"ended_s": -1.0,
		"finalize_at_s": INF,
		"exit_reason": "active",
		"shots": 0,
		"first_shot_s": -1.0,
		"first_damage_s": -1.0,
		"first_damage_amount": 0.0,
		"shots_at_first_damage": 0,
		"rocket_impacts": 0,
		"rocket_miss_sum_m": 0.0,
		"rocket_impact_offsets": [],
		"rocket_along_track_sum_m": 0.0,
		"rocket_cross_track_sum_m": 0.0,
		"rocket_directional_impacts": 0,
		"hits": 0,
		"damage": 0.0,
		"damage_targets": {},
		"destroyed": false,
		"min_dist": INF,
		"best_aim_dot": -1.0,
		# Sustained-tracking signal: how many samples were taken in firing range, and
		# how many of those were well aligned. Rewards genomes that HOLD the target on
		# the nose through the run, not ones that briefly graze it then diverge.
		"aim_samples_in_range": 0,
		"aim_samples_aligned": 0,
	}
	_trials[trial_id] = trial
	_active_by_pilot[pilot_id] = trial_id
	if scored:
		_generation_pending_trial_ids[trial_id] = true
	_log_event("TRIAL_START", {
		"trial": trial_id,
		"generation": _generation,
		"candidate": candidate_index,
		"repeat": repeat_index,
		"scored": scored,
		"craft": craft_name,
		"type": craft_type,
		"target": target_name,
		"weapon": weapon_kind,
		"genome": genome,
	})
	return {"trial_id": trial_id, "genome": genome.duplicate(true)}


func mark_run_started(trial_id: int) -> void:
	var trial := _get_trial(trial_id)
	if trial.is_empty():
		return
	trial["run_started_s"] = _now_s()


func record_sample(trial_id: int, dist_m: float, aim_dot: float) -> void:
	var trial := _get_trial(trial_id)
	if trial.is_empty():
		return
	if is_finite(dist_m):
		trial["min_dist"] = minf(float(trial["min_dist"]), dist_m)
	if is_finite(aim_dot):
		trial["best_aim_dot"] = maxf(float(trial["best_aim_dot"]), aim_dot)
	# Sustained-tracking: of the frames spent in firing range, what fraction held the
	# nose on the target. A genome that flies past (bearing diverging) racks up many
	# in-range frames but few aligned ones -> low fraction -> selected against.
	if is_finite(dist_m) and is_finite(aim_dot) and dist_m <= aim_track_range_m:
		trial["aim_samples_in_range"] = int(trial.get("aim_samples_in_range", 0)) + 1
		if aim_dot >= aim_track_dot:
			trial["aim_samples_aligned"] = int(trial.get("aim_samples_aligned", 0)) + 1


func record_shot(trial_id: int) -> void:
	var trial := _get_trial(trial_id)
	if not trial.is_empty():
		trial["shots"] = int(trial["shots"]) + 1
		if float(trial.get("first_shot_s", -1.0)) < 0.0:
			trial["first_shot_s"] = _now_s()


func record_rocket_impact(
		trial_id: int,
		miss_distance_m: float,
		offset_x_m: float = NAN,
		offset_z_m: float = NAN,
		along_track_m: float = NAN,
		cross_track_m: float = NAN
) -> void:
	var trial := _get_trial(trial_id)
	if trial.is_empty():
		return
	trial["rocket_impacts"] = int(trial["rocket_impacts"]) + 1
	trial["rocket_miss_sum_m"] = float(trial["rocket_miss_sum_m"]) \
			+ clampf(miss_distance_m, 0.0, maxf(unobserved_rocket_miss_m, 1.0))
	if is_finite(offset_x_m) and is_finite(offset_z_m):
		var offsets: Array = trial["rocket_impact_offsets"]
		offsets.append([offset_x_m, offset_z_m])
	if is_finite(along_track_m) and is_finite(cross_track_m):
		trial["rocket_along_track_sum_m"] = float(trial["rocket_along_track_sum_m"]) + along_track_m
		trial["rocket_cross_track_sum_m"] = float(trial["rocket_cross_track_sum_m"]) + cross_track_m
		trial["rocket_directional_impacts"] = int(trial["rocket_directional_impacts"]) + 1


func record_result(
		trial_id: int,
		target_id: int,
		before_health: float,
		after_health: float,
		fallback_damage: float,
		damaged: bool,
		destroyed: bool
) -> void:
	var trial := _get_trial(trial_id)
	if trial.is_empty():
		return
	if is_finite(before_health) and is_finite(after_health) and target_id != 0:
		var damage_targets: Dictionary = trial["damage_targets"]
		var window: Dictionary = damage_targets.get(target_id, {
			"max_before": before_health,
			"min_after": after_health,
		})
		window["max_before"] = maxf(float(window["max_before"]), before_health)
		window["min_after"] = minf(float(window["min_after"]), after_health)
		damage_targets[target_id] = window
		var measured_damage := 0.0
		for target_window_variant in damage_targets.values():
			var target_window := target_window_variant as Dictionary
			measured_damage += maxf(float(target_window["max_before"]) - float(target_window["min_after"]), 0.0)
		trial["damage"] = measured_damage
	else:
		trial["damage"] = float(trial["damage"]) + maxf(fallback_damage, 0.0)
	if damaged:
		trial["hits"] = int(trial["hits"]) + 1
		if float(trial.get("first_damage_s", -1.0)) < 0.0:
			trial["first_damage_s"] = _now_s()
			trial["first_damage_amount"] = float(trial.get("damage", 0.0))
			trial["shots_at_first_damage"] = int(trial.get("shots", 0))
	if destroyed:
		trial["destroyed"] = true


func end_trial(trial_id: int, reason: String) -> void:
	var trial := _get_trial(trial_id)
	if trial.is_empty() or float(trial["ended_s"]) >= 0.0:
		return
	var now := _now_s()
	trial["ended_s"] = now
	trial["finalize_at_s"] = now + maxf(result_grace_s, 0.0)
	trial["exit_reason"] = reason
	var pilot_id := int(trial["pilot_id"])
	if int(_active_by_pilot.get(pilot_id, 0)) == trial_id:
		_active_by_pilot.erase(pilot_id)


func _process(_delta: float) -> void:
	if not enabled:
		return
	var now := _now_s()
	var ready: Array[int] = []
	for trial_id_variant in _trials.keys():
		var trial_id := int(trial_id_variant)
		var trial: Dictionary = _trials[trial_id]
		if float(trial["ended_s"]) < 0.0:
			var pilot_id := int(trial.get("pilot_id", 0))
			var run_started_s := float(trial.get("run_started_s", -1.0))
			if pilot_id == 0 or not is_instance_id_valid(pilot_id):
				end_trial(trial_id, "orphaned_pilot")
			elif run_started_s < 0.0 \
					and now - float(trial.get("started_s", now)) \
							>= maxf(active_trial_pre_run_timeout_s, 1.0):
				end_trial(trial_id, "pre_run_timeout")
			elif run_started_s >= 0.0 \
					and now - run_started_s >= maxf(active_trial_post_run_timeout_s, 1.0):
				end_trial(trial_id, "post_run_timeout")
		if float(trial["ended_s"]) >= 0.0 and now >= float(trial["finalize_at_s"]):
			ready.append(trial_id)
	for trial_id in ready:
		_finalize_trial(trial_id)


func _finalize_trial(trial_id: int) -> void:
	var trial := _get_trial(trial_id)
	if trial.is_empty():
		return
	var shots := int(trial["shots"])
	trial["damage_per_rocket"] = float(trial["damage"]) / float(shots) if shots > 0 else 0.0
	trial["time_to_first_shot_s"] = float(trial.get("first_shot_s", -1.0)) \
			- float(trial["started_s"]) if float(trial.get("first_shot_s", -1.0)) >= 0.0 else INF
	trial["time_to_first_damage_s"] = float(trial.get("first_damage_s", -1.0)) \
			- float(trial["started_s"]) if float(trial.get("first_damage_s", -1.0)) >= 0.0 else INF
	trial["total_cycle_time_s"] = float(trial.get("ended_s", _now_s())) - float(trial["started_s"])
	var shots_at_first_damage := int(trial.get("shots_at_first_damage", 0))
	trial["first_damage_per_rocket"] = float(trial.get("first_damage_amount", 0.0)) \
			/ float(shots_at_first_damage) if shots_at_first_damage > 0 else 0.0
	trial["mean_rocket_miss_m"] = _get_mean_rocket_miss_m(trial)
	trial["rocket_group_radius_m"] = _get_rocket_group_radius_m(trial)
	var directional_impacts := int(trial.get("rocket_directional_impacts", 0))
	trial["mean_rocket_along_track_m"] = float(trial.get("rocket_along_track_sum_m", 0.0)) \
			/ float(directional_impacts) if directional_impacts > 0 else NAN
	trial["mean_rocket_cross_track_m"] = float(trial.get("rocket_cross_track_sum_m", 0.0)) \
			/ float(directional_impacts) if directional_impacts > 0 else NAN
	# Sustained-tracking fraction: of the frames in firing range, how many held the
	# nose on target. High = clean run-in that tracks; low = grazed then flew past.
	var in_range := int(trial.get("aim_samples_in_range", 0))
	trial["aim_aligned_fraction"] = float(trial.get("aim_samples_aligned", 0)) / float(in_range) if in_range > 0 else 0.0
	trial["fitness"] = _score_trial(trial)
	var result := trial.duplicate(true)
	result.erase("pilot_id")
	result.erase("finalize_at_s")
	result.erase("damage_targets")
	result.erase("rocket_impact_offsets")
	result.erase("rocket_along_track_sum_m")
	result.erase("rocket_cross_track_sum_m")
	_log_event("TRIAL_RESULT", result)
	_trials.erase(trial_id)
	if not bool(trial.get("scored", false)) or int(trial["generation"]) != _generation:
		return
	_generation_pending_trial_ids.erase(trial_id)
	_generation_results.append(result)
	var required_trials := _required_scored_trial_count()
	if _assignment_index >= required_trials \
			and _generation_pending_trial_ids.is_empty() \
			and _generation_results.size() >= required_trials:
		_evolve_generation()


func _score_trial(trial: Dictionary) -> float:
	if focus_attack_efficiency_only:
		return _score_efficiency_trial(trial)
	var shots := int(trial["shots"])
	var damage := float(trial["damage"])
	var min_dist := float(trial["min_dist"])
	var best_aim := float(trial["best_aim_dot"])
	var damage_per_rocket := damage / float(shots) if shots > 0 else 0.0
	# Primary outcome: minimize the mean actual impact distance of every rocket.
	# Missing impact reports receive the full miss penalty; not firing at all is worse.
	var mean_miss := _get_mean_rocket_miss_m(trial)
	var score := -mean_miss if shots > 0 else -maxf(unobserved_rocket_miss_m, 1.0) * 2.0
	# Damage efficiency is retained only as a small tie-breaker between similarly close impacts.
	score += damage_per_rocket * 0.1
	# Reward repeatability without allowing a tight cluster far from the target to
	# overpower actual miss distance. At most ten points are available here.
	var group_radius := _get_rocket_group_radius_m(trial)
	if is_finite(group_radius):
		score += clampf(
			(maxf(grouping_bonus_reference_m, 1.0) - group_radius) \
					/ maxf(grouping_bonus_reference_m, 1.0),
			0.0,
			1.0
		) * maxf(grouping_bonus_max, 0.0)
	# Dense shaping keeps zero-shot generations learnable: get close and point well.
	if is_finite(min_dist):
		score += clampf((2000.0 - min_dist) / 400.0, 0.0, 5.0)
	if is_finite(best_aim):
		score += clampf((best_aim - 0.90) * 50.0, 0.0, 5.0)
	# Sustained-tracking reward: fraction of in-range frames that held the target on
	# the nose. This is the signal that separates a clean run-in (holds alignment,
	# bearing converges) from a fly-past (briefly grazes dot=1.0 then diverges) — the
	# latter racks up in-range frames with few aligned, so it scores low here even
	# though its best_aim_dot peak is identical.
	var in_range := int(trial.get("aim_samples_in_range", 0))
	if in_range > 0:
		var aligned_fraction := float(trial.get("aim_samples_aligned", 0)) / float(in_range)
		score += clampf(aligned_fraction, 0.0, 1.0) * maxf(aim_track_bonus_max, 0.0)
	return score


func _score_efficiency_trial(trial: Dictionary) -> float:
	var shots := int(trial.get("shots", 0))
	if shots <= 0:
		return -2000.0
	var damage := float(trial.get("damage", 0.0))
	var damage_per_rocket := damage / float(shots)
	var first_damage := float(trial.get("first_damage_amount", 0.0))
	var first_damage_per_rocket := float(trial.get("first_damage_per_rocket", 0.0))
	var time_to_damage := float(trial.get("time_to_first_damage_s", INF))
	var cycle_time := float(trial.get("total_cycle_time_s", INF))
	var mean_miss := float(trial.get("mean_rocket_miss_m", unobserved_rocket_miss_m))
	var score := 0.0
	if first_damage > 0.0 and is_finite(time_to_damage):
		# A damaging first volley is the primary outcome. Efficiency and promptness
		# separate equally successful attacks without rewarding target-dousing.
		score += 250.0
		score += clampf(first_damage_per_rocket, 0.0, 150.0) * 2.0
		score += clampf(first_damage, 0.0, 500.0) * 0.10
		score -= time_to_damage
	else:
		score -= 500.0
		score -= minf(mean_miss, maxf(unobserved_rocket_miss_m, 1.0))
	# Retain total damage efficiency as a tie-breaker, but every extra rocket and
	# second of exposure has a cost.
	score += clampf(damage_per_rocket, 0.0, 150.0) * 0.5
	score -= float(shots)
	if is_finite(cycle_time):
		score -= maxf(cycle_time - 45.0, 0.0) * 0.35
	var reason := String(trial.get("exit_reason", "unknown"))
	if reason in ["node_exit", "orphaned_pilot", "pre_run_timeout", "post_run_timeout", "target_lost"]:
		score -= 500.0
	return score


func _get_mean_rocket_miss_m(trial: Dictionary) -> float:
	var shots := int(trial.get("shots", 0))
	if shots <= 0:
		return maxf(unobserved_rocket_miss_m, 1.0) * 2.0
	var impacts := mini(int(trial.get("rocket_impacts", 0)), shots)
	var missing := shots - impacts
	var total_miss := float(trial.get("rocket_miss_sum_m", 0.0)) \
			+ float(missing) * maxf(unobserved_rocket_miss_m, 1.0)
	return total_miss / float(shots)


func _get_rocket_group_radius_m(trial: Dictionary) -> float:
	var offsets_variant: Variant = trial.get("rocket_impact_offsets", [])
	if not (offsets_variant is Array):
		return INF
	var offsets := offsets_variant as Array
	if offsets.size() < 2:
		return INF
	var centroid := Vector2.ZERO
	var valid_offsets: Array[Vector2] = []
	for offset_variant in offsets:
		if not (offset_variant is Array) or (offset_variant as Array).size() < 2:
			continue
		var values := offset_variant as Array
		var offset := Vector2(float(values[0]), float(values[1]))
		if not is_finite(offset.x) or not is_finite(offset.y):
			continue
		valid_offsets.append(offset)
		centroid += offset
	if valid_offsets.size() < 2:
		return INF
	centroid /= float(valid_offsets.size())
	var squared_sum := 0.0
	for offset in valid_offsets:
		squared_sum += offset.distance_squared_to(centroid)
	return sqrt(squared_sum / float(valid_offsets.size()))


func _required_scored_trial_count() -> int:
	return _population.size() * maxi(trials_per_candidate, 1)


func _aggregate_generation_results() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for candidate_index in range(_population.size()):
		var candidate_trials: Array[Dictionary] = []
		for result in _generation_results:
			if int(result.get("candidate", -1)) == candidate_index:
				candidate_trials.append(result)
		if candidate_trials.is_empty():
			continue

		var fitness_sum := 0.0
		var total_shots := 0
		var total_hits := 0
		var total_damage := 0.0
		var total_miss_sum := 0.0
		var total_along_track_sum := 0.0
		var total_cross_track_sum := 0.0
		var total_directional_impacts := 0
		var first_damage_sum := 0.0
		var first_damage_per_rocket_sum := 0.0
		var time_to_first_damage_sum := 0.0
		var damaging_trials := 0
		var cycle_time_sum := 0.0
		var group_radius_sum := 0.0
		var grouped_trials := 0
		var fired_trials := 0
		var exit_reasons := {}
		var trial_ids: Array[int] = []
		var trial_fitnesses: Array[float] = []
		var representative := candidate_trials[0]
		for trial in candidate_trials:
			var fitness := float(trial.get("fitness", -INF))
			fitness_sum += fitness
			trial_fitnesses.append(fitness)
			trial_ids.append(int(trial.get("id", 0)))
			if fitness > float(representative.get("fitness", -INF)):
				representative = trial
			var shots := int(trial.get("shots", 0))
			var impacts := mini(int(trial.get("rocket_impacts", 0)), shots)
			total_shots += shots
			total_hits += int(trial.get("hits", 0))
			total_damage += float(trial.get("damage", 0.0))
			total_miss_sum += float(trial.get("rocket_miss_sum_m", 0.0)) \
					+ float(shots - impacts) * maxf(unobserved_rocket_miss_m, 1.0)
			var directional_impacts := int(trial.get("rocket_directional_impacts", 0))
			total_along_track_sum += float(trial.get("mean_rocket_along_track_m", 0.0)) \
					* float(directional_impacts)
			total_cross_track_sum += float(trial.get("mean_rocket_cross_track_m", 0.0)) \
					* float(directional_impacts)
			total_directional_impacts += directional_impacts
			var first_damage := float(trial.get("first_damage_amount", 0.0))
			var time_to_damage := float(trial.get("time_to_first_damage_s", INF))
			if first_damage > 0.0 and is_finite(time_to_damage):
				first_damage_sum += first_damage
				first_damage_per_rocket_sum += float(trial.get("first_damage_per_rocket", 0.0))
				time_to_first_damage_sum += time_to_damage
				damaging_trials += 1
			var cycle_time := float(trial.get("total_cycle_time_s", INF))
			if is_finite(cycle_time):
				cycle_time_sum += cycle_time
			var group_radius := float(trial.get("rocket_group_radius_m", INF))
			if is_finite(group_radius):
				group_radius_sum += group_radius
				grouped_trials += 1
			if shots > 0:
				fired_trials += 1
			var reason := String(trial.get("exit_reason", "unknown"))
			exit_reasons[reason] = int(exit_reasons.get(reason, 0)) + 1

		var trial_count := candidate_trials.size()
		var mean_trial_fitness := fitness_sum / float(trial_count)
		var fire_rate := float(fired_trials) / float(trial_count)
		var damaging_rate := float(damaging_trials) / float(trial_count)
		var aggregate_fitness := mean_trial_fitness
		if focus_attack_efficiency_only:
			# Reliability is deliberately lexicographic here: even the best possible
			# quality tie-breaker cannot let a 4/5 damaging candidate outrank 5/5.
			# Firing without damage still ranks above never firing, while damage per
			# rocket and cycle time separate candidates with equal consistency.
			aggregate_fitness = damaging_rate * 10000.0 \
					+ fire_rate * 1000.0 \
					+ clampf(mean_trial_fitness, -500.0, 500.0)
		var mean_miss := total_miss_sum / float(total_shots) \
				if total_shots > 0 else maxf(unobserved_rocket_miss_m, 1.0) * 2.0
		var damage_per_rocket := total_damage / float(total_shots) if total_shots > 0 else 0.0
		var mean_group_radius := group_radius_sum / float(grouped_trials) if grouped_trials > 0 else INF
		var mean_along_track := total_along_track_sum / float(total_directional_impacts) \
				if total_directional_impacts > 0 else NAN
		var mean_cross_track := total_cross_track_sum / float(total_directional_impacts) \
				if total_directional_impacts > 0 else NAN
		var mean_first_damage := first_damage_sum / float(damaging_trials) if damaging_trials > 0 else 0.0
		var mean_first_damage_per_rocket := first_damage_per_rocket_sum / float(damaging_trials) \
				if damaging_trials > 0 else 0.0
		var mean_time_to_first_damage := time_to_first_damage_sum / float(damaging_trials) \
				if damaging_trials > 0 else INF
		var mean_cycle_time := cycle_time_sum / float(trial_count) if trial_count > 0 else INF
		var genome := (_population[candidate_index] as Dictionary).duplicate(true)
		summaries.append({
			"candidate": candidate_index,
			"fitness": aggregate_fitness,
			"trial_count": trial_count,
			"fired_trials": fired_trials,
			"fire_rate": fire_rate,
			"shots": total_shots,
			"hits": total_hits,
			"damage": total_damage,
			"damage_per_rocket": damage_per_rocket,
			"mean_rocket_miss_m": mean_miss,
			"mean_rocket_group_radius_m": mean_group_radius,
			"mean_rocket_along_track_m": mean_along_track,
			"mean_rocket_cross_track_m": mean_cross_track,
			"damaging_trials": damaging_trials,
			"mean_first_damage": mean_first_damage,
			"mean_first_damage_per_rocket": mean_first_damage_per_rocket,
			"mean_time_to_first_damage_s": mean_time_to_first_damage,
			"mean_cycle_time_s": mean_cycle_time,
			"best_trial": int(representative.get("id", 0)),
			"trial_ids": trial_ids,
			"trial_fitnesses": trial_fitnesses,
			"exit_reasons": exit_reasons,
			"focus_changes": _get_focus_changes(genome, _population[0]),
			"genome": genome,
		})
	return summaries


func _evolve_generation() -> void:
	var ranked := _aggregate_generation_results()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["fitness"]) > float(b["fitness"])
	)
	if ranked.is_empty():
		return
	for summary in ranked:
		_log_event("CANDIDATE_SUMMARY", {
			"generation": _generation,
			"candidate": summary["candidate"],
			"fitness": summary["fitness"],
			"trial_count": summary["trial_count"],
			"fired_trials": summary["fired_trials"],
			"fire_rate": summary["fire_rate"],
			"shots": summary["shots"],
			"damage": summary["damage"],
			"damage_per_rocket": summary["damage_per_rocket"],
			"mean_rocket_miss_m": summary["mean_rocket_miss_m"],
			"mean_rocket_group_radius_m": summary["mean_rocket_group_radius_m"],
			"mean_rocket_along_track_m": summary["mean_rocket_along_track_m"],
			"mean_rocket_cross_track_m": summary["mean_rocket_cross_track_m"],
			"damaging_trials": summary["damaging_trials"],
			"mean_first_damage": summary["mean_first_damage"],
			"mean_first_damage_per_rocket": summary["mean_first_damage_per_rocket"],
			"mean_time_to_first_damage_s": summary["mean_time_to_first_damage_s"],
			"mean_cycle_time_s": summary["mean_cycle_time_s"],
			"trial_ids": summary["trial_ids"],
			"trial_fitnesses": summary["trial_fitnesses"],
			"exit_reasons": summary["exit_reasons"],
			"focus_changes": summary["focus_changes"],
			"genome": summary["genome"],
		})
	var champion: Dictionary = ranked[0]
	var champion_fitness := float(champion["fitness"])
	var new_all_time_best := champion_fitness > _best_fitness
	if new_all_time_best:
		_best_fitness = champion_fitness
		_best_genome = (champion["genome"] as Dictionary).duplicate(true)
		_best_result = champion.duplicate(true)
	_log_event("GENERATION", {
		"generation": _generation,
		"evaluated": _generation_results.size(),
		"evaluated_candidates": ranked.size(),
		"trials_per_candidate": maxi(trials_per_candidate, 1),
		"best_fitness": champion_fitness,
		"best_trial": int(champion["best_trial"]),
		"best_fire_rate": float(champion["fire_rate"]),
		"best_fired_trials": int(champion["fired_trials"]),
		"best_shots": int(champion["shots"]),
		"best_hits": int(champion["hits"]),
		"best_damage": float(champion["damage"]),
		"best_damage_per_rocket": float(champion.get("damage_per_rocket", 0.0)),
		"best_mean_rocket_miss_m": float(champion.get("mean_rocket_miss_m", unobserved_rocket_miss_m)),
		"best_mean_rocket_group_radius_m": float(champion.get("mean_rocket_group_radius_m", INF)),
		"best_mean_rocket_along_track_m": float(champion.get("mean_rocket_along_track_m", NAN)),
		"best_mean_rocket_cross_track_m": float(champion.get("mean_rocket_cross_track_m", NAN)),
		"best_damaging_trials": int(champion.get("damaging_trials", 0)),
		"best_mean_first_damage": float(champion.get("mean_first_damage", 0.0)),
		"best_mean_first_damage_per_rocket": float(champion.get("mean_first_damage_per_rocket", 0.0)),
		"best_mean_time_to_first_damage_s": float(champion.get("mean_time_to_first_damage_s", INF)),
		"best_mean_cycle_time_s": float(champion.get("mean_cycle_time_s", INF)),
		"new_all_time_best": new_all_time_best,
		"all_time_best_fitness": _best_fitness,
		"genome": champion["genome"],
	})
	_save_state()

	var next_population: Array[Dictionary] = []
	# Candidate zero is a permanent hall-of-fame slot. Generation elites can come
	# and go, but the strongest result ever observed is never mutated or displaced.
	if not _best_genome.is_empty():
		next_population.append(_best_genome.duplicate(true))
	var elites := mini(maxi(elite_count, 1), mini(ranked.size(), maxi(population_size, 4)))
	for i in range(elites):
		var elite_genome := (ranked[i]["genome"] as Dictionary).duplicate(true)
		if elite_genome != _best_genome and next_population.size() < maxi(population_size, 4):
			next_population.append(elite_genome)
	var parent_pool_size := maxi(elites, int(ceil(float(ranked.size()) * 0.5)))
	while next_population.size() < maxi(population_size, 4):
		var parent_a: Dictionary = ranked[_rng.randi_range(0, parent_pool_size - 1)]["genome"]
		var parent_b: Dictionary = ranked[_rng.randi_range(0, parent_pool_size - 1)]["genome"]
		var child := _crossover(parent_a, parent_b)
		next_population.append(_mutate(child, mutation_scale))
	_population = next_population
	_generation += 1
	_assignment_index = 0
	_generation_results.clear()
	_generation_pending_trial_ids.clear()


func _build_initial_population() -> void:
	_population.clear()
	var seed := _best_genome.duplicate(true) if not _best_genome.is_empty() else _base_genome()
	seed = _clamp_genome(seed)
	if focus_attack_efficiency_only:
		for overrides_variant in TARGETED_EFFICIENCY_GRID:
			if _population.size() >= maxi(population_size, 4):
				break
			var candidate := seed.duplicate(true)
			var overrides := overrides_variant as Dictionary
			for key_variant in overrides.keys():
				candidate[String(key_variant)] = float(overrides[key_variant])
			_population.append(_clamp_genome(candidate))
		while _population.size() < maxi(population_size, 4):
			_population.append(_mutate(seed, mutation_scale))
		return
	if focus_ballistic_correction_only and use_targeted_ballistic_grid:
		# First establish which side of the current correction is useful. Candidate
		# zero preserves the stabilized champion; the others vary only CCIP feedback
		# strength or vertical aim bias.
		for overrides_variant in TARGETED_BALLISTIC_GRID:
			if _population.size() >= maxi(population_size, 4):
				break
			var candidate := seed.duplicate(true)
			var overrides := overrides_variant as Dictionary
			for key_variant in overrides.keys():
				candidate[String(key_variant)] = float(overrides[key_variant])
			_population.append(_clamp_genome(candidate))
		while _population.size() < maxi(population_size, 4):
			_population.append(_mutate(seed, mutation_scale))
		return
	if focus_aim_controller_only and use_targeted_aim_grid:
		# Controlled grid requested from the latest repeated-trial evidence. Candidate
		# zero remains the persisted champion; every other candidate changes only the
		# named yaw/pitch gains, keeping damping and all flight geometry identical.
		for overrides_variant in TARGETED_AIM_GRID:
			if _population.size() >= maxi(population_size, 4):
				break
			var candidate := seed.duplicate(true)
			var overrides := overrides_variant as Dictionary
			for key_variant in overrides.keys():
				candidate[String(key_variant)] = float(overrides[key_variant])
			_population.append(_clamp_genome(candidate))
		while _population.size() < maxi(population_size, 4):
			_population.append(_mutate(seed, mutation_scale))
		return
	_population.append(seed)
	if focus_aim_controller_only or focus_ballistic_correction_only or focus_attack_efficiency_only:
		# The first focused generation is a coordinate experiment: one child for each
		# yaw/pitch dimension, all sharing the exact same non-aim baseline.
		var focus_specs := _get_focus_specs()
		while _population.size() < maxi(population_size, 4):
			var spec_index := (_population.size() - 1) % focus_specs.size()
			_population.append(_mutate_one_spec(seed, focus_specs[spec_index], mutation_scale * 1.5))
		return
	while _population.size() < maxi(population_size, 4):
		_population.append(_mutate(seed, mutation_scale * 1.5))


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
	return child


func _mutate(source: Dictionary, scale: float) -> Dictionary:
	var genome := source.duplicate(true)
	if focus_aim_controller_only or focus_ballistic_correction_only or focus_attack_efficiency_only:
		var focus_specs := _get_focus_specs()
		var mutation_count := mini(maxi(focused_mutations_per_child, 1), focus_specs.size())
		for _i in range(mutation_count):
			var spec_index := _rng.randi_range(0, focus_specs.size() - 1)
			var spec := focus_specs[spec_index]
			focus_specs.remove_at(spec_index)
			genome = _mutate_one_spec(genome, spec, scale)
		return genome
	for spec in PARAM_SPECS:
		var key := String(spec["name"])
		var value := float(genome.get(key, spec["base"]))
		if _rng.randf() < mutation_probability:
			value += _rng.randfn(0.0, float(spec["sigma"]) * maxf(scale, 0.01))
		genome[key] = clampf(value, float(spec["min"]), float(spec["max"]))
	return genome


func _get_focus_specs() -> Array[Dictionary]:
	var focus_specs: Array[Dictionary] = []
	var focus_params: Dictionary = EFFICIENCY_FOCUS_PARAMS if focus_attack_efficiency_only \
			else (BALLISTIC_FOCUS_PARAMS if focus_ballistic_correction_only else AIM_FOCUS_PARAMS)
	for spec in PARAM_SPECS:
		if focus_params.has(String(spec["name"])):
			focus_specs.append(spec)
	return focus_specs


func _get_focus_changes(genome: Dictionary, baseline: Dictionary) -> Dictionary:
	var changes := {}
	var focus_params: Dictionary = EFFICIENCY_FOCUS_PARAMS if focus_attack_efficiency_only \
			else (BALLISTIC_FOCUS_PARAMS if focus_ballistic_correction_only else AIM_FOCUS_PARAMS)
	for key_variant in focus_params.keys():
		var key := String(key_variant)
		var delta := float(genome.get(key, 0.0)) - float(baseline.get(key, 0.0))
		if absf(delta) > 0.000001:
			changes[key] = delta
	return changes


func _mutate_one_spec(source: Dictionary, spec: Dictionary, scale: float) -> Dictionary:
	var genome := source.duplicate(true)
	var key := String(spec["name"])
	var value := float(genome.get(key, spec["base"]))
	value += _rng.randfn(0.0, float(spec["sigma"]) * maxf(scale, 0.01))
	genome[key] = clampf(value, float(spec["min"]), float(spec["max"]))
	return genome


func _clamp_genome(source: Dictionary) -> Dictionary:
	var genome := {}
	for spec in PARAM_SPECS:
		var key := String(spec["name"])
		genome[key] = clampf(float(source.get(key, spec["base"])), float(spec["min"]), float(spec["max"]))
	return genome


func _get_trial(trial_id: int) -> Dictionary:
	var value: Variant = _trials.get(trial_id, {})
	return value as Dictionary if value is Dictionary else {}


func _now_s() -> float:
	return Time.get_ticks_msec() / 1000.0


func _start_log() -> void:
	var header := "HELI COMBAT TUNING START time=%s generation=%d population=%d trials_per_candidate=%d focus_aim=%s focus_ballistic=%s focus_efficiency=%s targeted_grid=%s" % [
		Time.get_datetime_string_from_system(), _generation, maxi(population_size, 4),
		maxi(trials_per_candidate, 1), str(focus_aim_controller_only),
		str(focus_ballistic_correction_only),
		str(focus_attack_efficiency_only),
		str(true if focus_attack_efficiency_only else (use_targeted_ballistic_grid if focus_ballistic_correction_only else use_targeted_aim_grid)),
	]
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
		push_warning("HelicopterCombatTuner could not open %s" % path)
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
		return
	_generation = maxi(int(state.get("generation", 0)), 0)
	var genome_variant: Variant = state.get("best_genome", {})
	if genome_variant is Dictionary:
		_best_genome = _clamp_genome(genome_variant as Dictionary)
	var evaluation_compatible := int(state.get("fitness_version", 0)) == FITNESS_VERSION \
			and int(state.get("evaluation_version", 1)) == EVALUATION_VERSION \
			and int(state.get("trials_per_candidate", 1)) == maxi(trials_per_candidate, 1) \
			and bool(state.get("focus_aim_controller_only", false)) == focus_aim_controller_only \
			and bool(state.get("focus_ballistic_correction_only", false)) == focus_ballistic_correction_only \
			and bool(state.get("focus_attack_efficiency_only", false)) == focus_attack_efficiency_only
	if evaluation_compatible:
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
		"fitness_version": FITNESS_VERSION,
		"evaluation_version": EVALUATION_VERSION,
		"trials_per_candidate": maxi(trials_per_candidate, 1),
		"focus_aim_controller_only": focus_aim_controller_only,
		"focus_ballistic_correction_only": focus_ballistic_correction_only,
		"focus_attack_efficiency_only": focus_attack_efficiency_only,
		"generation": _generation + 1,
		"best_fitness": _best_fitness,
		"best_genome": _best_genome,
		"best_result": _best_result,
	}
	_write_json_file(state_path, state)
	if project_mirror_enabled and not champion_project_mirror_path.is_empty():
		_write_json_file(champion_project_mirror_path, state)


func _write_json_file(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("HelicopterCombatTuner could not save %s" % path)
		return
	file.store_string(JSON.stringify(data, "  "))
