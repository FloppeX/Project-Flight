extends Node
## Persistent, sequential genetic tuner for the carrier landing test.
## Every candidate flies the same fixed spawn cases; state is saved after every trial so an
## overnight run can resume after a crash, reboot, or deliberate restart.

@export_range(4, 24, 1) var population_size: int = 8
@export_range(1, 6, 1) var elite_count: int = 2
@export_range(1, 6, 1) var mutations_per_child: int = 4
@export_range(0.1, 3.0, 0.1) var mutation_scale: float = 1.0
@export var case_count: int = 3
@export var curriculum_level_count: int = 1
@export var curriculum_promote_catches: int = 5
@export var state_path: String = "user://landing_ga_state.json"
@export var log_path: String = "user://landing_ga_tuning.log"
@export var champion_project_path: String = "res://landing_ga_champion.json"
@export var project_log_path: String = "res://landing_ga_tuning.log"

const FITNESS_VERSION: int = 36 # Tunable pre-gate bank-settling schedule.
const CURRICULUM_VERSION: int = 1
const PARAM_SPECS := [
	# Final horizontal FPV PID and the bank/rudder authority it can use.
	{"name":"landing_final_fpv_pid_kp", "base":4.2, "min":1.8, "max":10.0, "sigma":0.70},
	{"name":"landing_final_fpv_pid_ki", "base":0.30, "min":0.0, "max":0.9, "sigma":0.10},
	{"name":"landing_final_fpv_pid_kd", "base":0.05, "min":0.0, "max":0.20, "sigma":0.025},
	{"name":"landing_final_fpv_pid_output_limit", "base":0.85, "min":0.45, "max":1.0, "sigma":0.07},
	{"name":"landing_final_lateral_bank_gain", "base":1.0, "min":0.45, "max":2.0, "sigma":0.18},
	{"name":"landing_final_lateral_bank_limit_deg", "base":8.0, "min":4.0, "max":15.0, "sigma":1.3},
	{"name":"landing_final_lateral_slew_deg_per_s", "base":18.0, "min":10.0, "max":36.0, "sigma":3.0},
	{"name":"landing_final_rudder_rate_damping", "base":0.7, "min":0.25, "max":1.4, "sigma":0.13},
	{"name":"landing_final_lateral_pd_lookahead_m", "base":130.0, "min":70.0, "max":220.0, "sigma":18.0},
	{"name":"landing_final_lateral_velocity_damping_s", "base":2.0, "min":0.5, "max":4.0, "sigma":0.35},
	{"name":"landing_final_lateral_pd_limit_deg", "base":12.0, "min":8.0, "max":18.0, "sigma":1.2},
	{"name":"landing_final_axis_track_blend_start_m", "base":800.0, "min":600.0, "max":1000.0, "sigma":55.0},
	{"name":"landing_final_axis_track_blend_full_m", "base":450.0, "min":350.0, "max":600.0, "sigma":35.0},
	{"name":"landing_final_rudder_primary_bank_scale", "base":0.60, "min":0.35, "max":0.90, "sigma":0.08},
	{"name":"landing_final_bank_settle_start_remaining_m", "base":650.0, "min":500.0, "max":850.0, "sigma":45.0},
	{"name":"landing_final_bank_scale_at_gate", "base":0.45, "min":0.20, "max":0.75, "sigma":0.07},
	# Existing vertical FPV controller. Keeping these in the genome makes the optimized error 2D.
	{"name":"landing_final_pitch_gain", "base":2.4, "min":0.8, "max":4.0, "sigma":0.30},
	{"name":"landing_final_pitch_rate_damping", "base":1.35, "min":0.55, "max":2.4, "sigma":0.20},
	{"name":"landing_final_pitch_smoothing", "base":0.34, "min":0.15, "max":0.75, "sigma":0.07},
	{"name":"landing_final_glide_error_fpa_gain", "base":0.018, "min":0.005, "max":0.035, "sigma":0.003},
	{"name":"landing_final_low_cone_intercept_max_correction_deg", "base":3.0, "min":1.0, "max":5.0, "sigma":0.45},
	{"name":"landing_final_target_aoa_deg", "base":8.0, "min":6.0, "max":10.0, "sigma":0.45},
	{"name":"landing_final_aoa_gain", "base":4.0, "min":2.0, "max":6.5, "sigma":0.45},
	# Aircraft 5's approach configuration is part of the equilibrium: enough flap lift to remain
	# controllable, with enough drag to settle near the target AoA instead of floating over the wires.
	{"name":"flaps_lift_bonus", "base":0.15, "min":0.05, "max":0.30, "sigma":0.025},
	{"name":"flaps_drag_multiplier", "base":4.0, "min":2.5, "max":5.5, "sigma":0.35},
	# Carrot geometry becomes important when there is little time to settle before the wires.
	{"name":"landing_carrot_min_gap_m", "base":45.0, "min":25.0, "max":80.0, "sigma":7.0},
	{"name":"landing_carrot_final_max_gap_m", "base":120.0, "min":70.0, "max":180.0, "sigma":15.0},
]

var _rng := RandomNumberGenerator.new()
var _generation: int = 0
var _population: Array[Dictionary] = []
var _candidate_index: int = 0
var _case_index: int = 0
var _curriculum_level: int = 0
var _results: Array[Dictionary] = []
var _best_fitness: float = -1.0e30
var _best_genome: Dictionary = {}
var _best_summary: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_load_state()
	if _population.is_empty():
		_build_initial_population()
	_save_state()
	_log_event("SESSION_START", get_status())


func next_assignment() -> Dictionary:
	if _population.is_empty():
		_build_initial_population()
	_candidate_index = clampi(_candidate_index, 0, _population.size() - 1)
	_case_index = clampi(_case_index, 0, maxi(case_count, 1) - 1)
	return {
		"generation": _generation,
		"candidate": _candidate_index,
		"case": _case_index,
		"curriculum": _curriculum_level,
		"genome": _population[_candidate_index].duplicate(true),
	}


func apply_genome(pilot: Node, genome: Dictionary) -> void:
	if pilot == null:
		return
	for spec in PARAM_SPECS:
		var key := String(spec["name"])
		if key in pilot:
			pilot.set(key, float(genome.get(key, spec["base"])))
			continue
		var aero: Node = pilot.get("simple_aero") as Node if "simple_aero" in pilot else null
		if is_instance_valid(aero) and key in aero:
			aero.set(key, float(genome.get(key, spec["base"])))


func record_result(assignment: Dictionary, metrics: Dictionary) -> float:
	if int(assignment.get("generation", -1)) != _generation \
			or int(assignment.get("candidate", -1)) != _candidate_index \
			or int(assignment.get("case", -1)) != _case_index \
			or int(assignment.get("curriculum", -1)) != _curriculum_level:
		_log_event("STALE_RESULT", {"assignment": assignment, "expected": next_assignment()})
		return -1.0e30
	var result := metrics.duplicate(true)
	result["generation"] = _generation
	result["candidate"] = _candidate_index
	result["case"] = _case_index
	result["curriculum"] = _curriculum_level
	result["fitness"] = _score_trial(result)
	result["genome"] = (_population[_candidate_index] as Dictionary).duplicate(true)
	_results.append(result)
	_log_event("TRIAL_END", result)
	_case_index += 1
	if _case_index >= maxi(case_count, 1):
		_case_index = 0
		_candidate_index += 1
	if _candidate_index >= _population.size():
		_finish_generation()
	_save_state()
	return float(result["fitness"])


func get_status() -> Dictionary:
	return {
		"generation": _generation,
		"curriculum": _curriculum_level,
		"curriculum_levels": maxi(curriculum_level_count, 1),
		"candidate": _candidate_index,
		"population": _population.size(),
		"case": _case_index,
		"cases": maxi(case_count, 1),
		"completed_trials": _results.size(),
		"generation_trials": _population.size() * maxi(case_count, 1),
		"best_fitness": _best_fitness,
		"best_genome": _best_genome.duplicate(true),
	}


func _score_trial(result: Dictionary) -> float:
	var outcome := String(result.get("outcome", "GONE"))
	var score := {
		"CAUGHT": 10000.0,
		"WAVE-OFF": 2200.0,
		"BOLTER": 2200.0,
		"TIMEOUT": -2200.0,
		"CRASH": -4000.0,
		"TELEPORT": -4000.0,
		"GONE": -3500.0,
	}.get(outcome, -3000.0) as float
	if bool(result.get("reached_glideslope", false)):
		score += 800.0
	if bool(result.get("reached_final", false)):
		score += 1400.0
	var min_remaining := float(result.get("min_remaining_m", INF))
	if is_finite(min_remaining):
		score += clampf(1800.0 - min_remaining, 0.0, 1800.0) * 0.35
	var min_lateral := float(result.get("min_lateral_m", INF))
	if is_finite(min_lateral):
		score += clampf(180.0 - min_lateral, 0.0, 180.0) * 2.5
	var min_vertical := float(result.get("min_vertical_m", INF))
	if is_finite(min_vertical):
		score += clampf(80.0 - min_vertical, 0.0, 80.0) * 3.0
	var min_wire_hook_vertical := float(result.get("min_wire_hook_vertical_m", INF))
	if is_finite(min_wire_hook_vertical):
		# A bolter that passes just above a wire is more useful genetically than one that reaches
		# deck height only after all wires. The actual CAUGHT outcome still dominates this shaping.
		score += clampf(6.0 - min_wire_hook_vertical, 0.0, 6.0) * 200.0
	var final_samples := int(result.get("final_samples", 0))
	if final_samples > 0:
		# Integrated mean errors reward actually keeping the FPV centered, not crossing it once.
		score -= float(result.get("mean_fpv_yaw_error_deg", 0.0)) * 85.0
		score -= float(result.get("mean_fpv_pitch_error_deg", 0.0)) * 65.0
		# A valid carrier attitude is part of the solution: keep the nose separated from the
		# descending flight path instead of winning solely by pointing the fuselage at the deck.
		score -= float(result.get("mean_aoa_error_deg", 0.0)) * 35.0
	var duration_s := float(result.get("duration_s", 0.0))
	if outcome == "CAUGHT":
		score += clampf(240.0 - duration_s, 0.0, 240.0) * 2.0
	else:
		score -= minf(duration_s, 360.0) * 0.35
	return score


func _finish_generation() -> void:
	var ranked: Array[Dictionary] = []
	for candidate in range(_population.size()):
		var scores: Array[float] = []
		var catches := 0
		for result in _results:
			if int(result.get("candidate", -1)) == candidate:
				scores.append(float(result.get("fitness", -1.0e30)))
				if String(result.get("outcome", "")) == "CAUGHT":
					catches += 1
		var mean := _mean(scores)
		var robust_fitness := mean - _standard_deviation(scores, mean) * 0.25
		ranked.append({
			"candidate": candidate,
			"fitness": robust_fitness,
			"mean_fitness": mean,
			"catches": catches,
			"genome": (_population[candidate] as Dictionary).duplicate(true),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["fitness"]) > float(b["fitness"]))
	var champion: Dictionary = ranked[0]
	var completed_curriculum := _curriculum_level
	var new_best := float(champion["fitness"]) > _best_fitness
	if new_best:
		_best_fitness = float(champion["fitness"])
		_best_genome = (champion["genome"] as Dictionary).duplicate(true)
		_best_summary = champion.duplicate(true)
		_write_champion()
	_log_event("GENERATION_END", {
		"generation": _generation,
		"curriculum": completed_curriculum,
		"new_best": new_best,
		"champion": champion,
		"all_time_best_fitness": _best_fitness,
		"ranking": ranked,
	})
	_breed_next_population(ranked)
	_generation += 1
	_candidate_index = 0
	_case_index = 0
	_results.clear()
	var catches_required := mini(maxi(curriculum_promote_catches, 1), maxi(case_count, 1))
	if int(champion.get("catches", 0)) >= catches_required \
			and _curriculum_level < maxi(curriculum_level_count, 1) - 1:
		_curriculum_level += 1
		# Scores from different curricula are not comparable. Retain the winning genome as the
		# population seed, but require it to establish a fresh best on the harder level.
		_best_fitness = -1.0e30
		_best_summary.clear()
		_log_event("CURRICULUM_ADVANCE", {
			"from": completed_curriculum,
			"to": _curriculum_level,
			"champion_catches": int(champion.get("catches", 0)),
			"required_catches": catches_required,
			"seed_genome": _best_genome,
		})


func _build_initial_population() -> void:
	_population.clear()
	var seed := _clamp_genome(_best_genome if not _best_genome.is_empty() else _base_genome())
	var baseline := _clamp_genome(_base_genome())
	_population.append(seed)
	if _population.size() < maxi(population_size, 4) and baseline != seed:
		_population.append(baseline)
	while _population.size() < maxi(population_size, 4):
		var mutation_parent: Dictionary = seed if _population.size() % 2 == 0 else baseline
		_population.append(_mutate(mutation_parent, mutation_scale * 1.35))


func _breed_next_population(ranked: Array[Dictionary]) -> void:
	var next_population: Array[Dictionary] = []
	if not _best_genome.is_empty():
		next_population.append(_best_genome.duplicate(true))
	var elites := mini(maxi(elite_count, 1), ranked.size())
	for i in range(elites):
		if next_population.size() >= maxi(population_size, 4):
			break
		var elite: Dictionary = (ranked[i]["genome"] as Dictionary).duplicate(true)
		if not next_population.has(elite):
			next_population.append(elite)
	var parent_pool := maxi(elites, int(ceil(float(ranked.size()) * 0.5)))
	while next_population.size() < maxi(population_size, 4):
		var a: Dictionary = ranked[_rng.randi_range(0, parent_pool - 1)]["genome"]
		var b: Dictionary = ranked[_rng.randi_range(0, parent_pool - 1)]["genome"]
		next_population.append(_mutate(_crossover(a, b), mutation_scale))
	_population = next_population


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
	var specs: Array = PARAM_SPECS.duplicate(true)
	# Fisher-Yates using this tuner's RNG keeps mutation independent of gameplay randomness.
	for i in range(specs.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = specs[i]
		specs[i] = specs[j]
		specs[j] = tmp
	for i in range(mini(maxi(mutations_per_child, 1), specs.size())):
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
	return genome


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return -1.0e30
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()


func _standard_deviation(values: Array[float], mean: float) -> float:
	if values.size() <= 1:
		return 0.0
	var sum_sq := 0.0
	for value in values:
		sum_sq += (value - mean) * (value - mean)
	return sqrt(sum_sq / values.size())


func _load_state() -> void:
	var state := _read_json(state_path)
	if state.is_empty():
		state = _read_json(champion_project_path)
	if state.is_empty():
		return
	var best_variant: Variant = state.get("best_genome", {})
	if best_variant is Dictionary:
		_best_genome = _clamp_genome(best_variant as Dictionary)
	if int(state.get("fitness_version", 0)) != FITNESS_VERSION \
			or int(state.get("curriculum_version", 0)) != CURRICULUM_VERSION \
			or int(state.get("case_count", 0)) != maxi(case_count, 1) \
			or int(state.get("curriculum_level_count", 0)) != maxi(curriculum_level_count, 1):
		return
	_generation = maxi(int(state.get("generation", 0)), 0)
	_candidate_index = maxi(int(state.get("candidate_index", 0)), 0)
	_case_index = maxi(int(state.get("case_index", 0)), 0)
	_curriculum_level = clampi(int(state.get("curriculum_level", 0)), 0, maxi(curriculum_level_count, 1) - 1)
	_best_fitness = float(state.get("best_fitness", -1.0e30))
	var summary_variant: Variant = state.get("best_summary", {})
	if summary_variant is Dictionary:
		_best_summary = (summary_variant as Dictionary).duplicate(true)
	var population_variant: Variant = state.get("population", [])
	if population_variant is Array:
		for genome_variant in population_variant:
			if genome_variant is Dictionary:
				_population.append(_clamp_genome(genome_variant as Dictionary))
	var results_variant: Variant = state.get("results", [])
	if results_variant is Array:
		for result_variant in results_variant:
			if result_variant is Dictionary:
				_results.append((result_variant as Dictionary).duplicate(true))
	if _population.size() != maxi(population_size, 4):
		_population.clear()
		_candidate_index = 0
		_case_index = 0
		_results.clear()


func _save_state() -> void:
	_write_json(state_path, {
		"fitness_version": FITNESS_VERSION,
		"curriculum_version": CURRICULUM_VERSION,
		"case_count": maxi(case_count, 1),
		"curriculum_level_count": maxi(curriculum_level_count, 1),
		"curriculum_level": _curriculum_level,
		"generation": _generation,
		"candidate_index": _candidate_index,
		"case_index": _case_index,
		"population": _population,
		"results": _results,
		"best_fitness": _best_fitness,
		"best_genome": _best_genome,
		"best_summary": _best_summary,
	})


func _write_champion() -> void:
	_write_json(champion_project_path, {
		"fitness_version": FITNESS_VERSION,
		"curriculum_version": CURRICULUM_VERSION,
		"generation": _generation,
		"curriculum_level": _curriculum_level,
		"curriculum_level_count": maxi(curriculum_level_count, 1),
		"best_fitness": _best_fitness,
		"best_genome": _best_genome,
		"best_summary": _best_summary,
		"parameter_specs": PARAM_SPECS,
	})


func _log_event(event_name: String, data: Dictionary) -> void:
	var line := "time=%s event=%s %s" % [Time.get_datetime_string_from_system(), event_name, JSON.stringify(data)]
	_write_line(log_path, line)
	_write_line(project_log_path, line)


func _write_line(path: String, line: String) -> void:
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	var file := FileAccess.open(path, mode)
	if file == null:
		push_warning("LandingGeneticTuner could not write %s" % path)
		return
	file.seek_end()
	file.store_line(line)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("LandingGeneticTuner could not save %s" % path)
		return
	file.store_string(JSON.stringify(data, "  "))
