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
@export var project_log_path: String = "res://logs/landing_ga_tuning.log"

const FITNESS_VERSION: int = 41 # Success requires sustained arrest; retain damage and terminal drift costs.
const CURRICULUM_VERSION: int = 2
const PARAM_SPECS := [
	# Optimize the new physical hook/deck prediction and the vertical controller that executes its cue.
	# Horizontal tracking is intentionally fixed for this first run: the baseline matrix already showed
	# sub-metre centerline errors, while most misses crossed above a wire.
	{"name":"landing_sight_guidance_start_remaining_m", "base":700.0, "min":500.0, "max":1200.0, "sigma":90.0},
	{"name":"landing_sight_guidance_full_remaining_m", "base":350.0, "min":180.0, "max":600.0, "sigma":55.0},
	{"name":"landing_sight_guidance_time_floor_s", "base":1.0, "min":0.3, "max":2.2, "sigma":0.25},
	{"name":"landing_sight_guidance_max_sink_mps", "base":12.0, "min":8.0, "max":14.0, "sigma":0.8},
	{"name":"landing_sight_guidance_max_climb_mps", "base":2.0, "min":0.0, "max":4.0, "sigma":0.5},
	{"name":"landing_sight_guidance_target_hook_vertical_m", "base":0.0, "min":-5.0, "max":1.0, "sigma":0.6},
	{"name":"landing_sight_guidance_pitch_gain", "base":4.0, "min":1.0, "max":10.0, "sigma":0.9},
	{"name":"landing_sight_guidance_max_lateral_intercept_deg", "base":16.0, "min":12.0, "max":28.0, "sigma":2.0},
	{"name":"landing_sight_guidance_terminal_lateral_power", "base":2.0, "min":1.1, "max":2.8, "sigma":0.2},
	{"name":"landing_sight_guidance_terminal_lateral_accel_mps2", "base":4.0, "min":2.0, "max":7.0, "sigma":0.5},
	{"name":"landing_final_pitch_gain", "base":2.4, "min":0.8, "max":4.0, "sigma":0.30},
	{"name":"landing_final_pitch_rate_damping", "base":1.35, "min":0.55, "max":2.4, "sigma":0.20},
	{"name":"landing_final_pitch_smoothing", "base":0.34, "min":0.15, "max":0.75, "sigma":0.07},
	{"name":"landing_final_glide_error_fpa_gain", "base":0.018, "min":0.005, "max":0.035, "sigma":0.003},
	{"name":"landing_final_target_aoa_deg", "base":8.0, "min":6.0, "max":10.0, "sigma":0.45},
	{"name":"landing_final_aoa_gain", "base":4.0, "min":2.0, "max":7.0, "sigma":0.55},
	{"name":"landing_final_aoa_pitch_input_limit", "base":0.16, "min":0.05, "max":0.35, "sigma":0.04},
	{"name":"landing_final_speed_far_mps", "base":52.0, "min":46.0, "max":60.0, "sigma":1.8},
	{"name":"landing_final_speed_touchdown_mps", "base":42.0, "min":38.0, "max":50.0, "sigma":1.5},
]

var _rng := RandomNumberGenerator.new()
## Populated by the landing harness from the selected aircraft scene before this node enters the
## tree. This keeps candidate zero tied to that airframe's real scene overrides instead of a stale
## set of shared defaults. PARAM_SPECS.base remains a safe fallback for direct tuner smoke tests.
var baseline_genome: Dictionary = {}
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
		"baseline_genome": _base_genome(),
	}


func parameter_names() -> Array[String]:
	var names: Array[String] = []
	for spec in PARAM_SPECS:
		names.append(String(spec["name"]))
	return names


func _score_trial(result: Dictionary) -> float:
	var outcome := String(result.get("outcome", "GONE"))
	if outcome == "CAUGHT" and not bool(result.get("stopped", false)):
		outcome = "BOLTER" # Old engagement-only results cannot win under the new contract.
	var score := {
		"CAUGHT": 12000.0,
		"BOLTER": 1500.0,
		"WAVE-OFF": -500.0,
		"CRASH": -800.0,
		"TIMEOUT": -8000.0,
		"TELEPORT": -8500.0,
		"GONE": -8500.0,
	}.get(outcome, -8000.0) as float
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
		score += clampf(7.0 - min_wire_hook_vertical, 0.0, 7.0) * 300.0
	# The sight should create and hold a physical capture solution, not merely cross it for one frame.
	score += clampf(float(result.get("sight_viable_fraction", 0.0)), 0.0, 1.0) * 1600.0
	score += clampf(float(result.get("sight_capture_fraction", 0.0)), 0.0, 1.0) * 2200.0
	var final_samples := int(result.get("final_samples", 0))
	if final_samples > 0:
		# Integrated mean errors reward actually keeping the FPV centered, not crossing it once.
		score -= float(result.get("mean_fpv_yaw_error_deg", 0.0)) * 85.0
		score -= float(result.get("mean_fpv_pitch_error_deg", 0.0)) * 65.0
		# A valid carrier attitude is part of the solution: keep the nose separated from the
		# descending flight path instead of winning solely by pointing the fuselage at the deck.
		score -= float(result.get("mean_aoa_error_deg", 0.0)) * 35.0
	var duration_s := float(result.get("duration_s", 0.0))
	score -= clampf(float(result.get("damage_taken", 0.0)), 0.0, 100.0) * 40.0
	score -= absf(float(result.get("catch_lateral_speed_mps", 0.0))) * 60.0
	if outcome == "CAUGHT":
		score += clampf(240.0 - duration_s, 0.0, 240.0) * 2.0
	elif outcome not in ["TIMEOUT", "TELEPORT", "GONE"]:
		score -= minf(duration_s, 360.0) * 0.35
	return score


func _finish_generation() -> void:
	var ranked: Array[Dictionary] = []
	for candidate in range(_population.size()):
		var scores: Array[float] = []
		var model_scores: Dictionary = {}
		var catches := 0
		for result in _results:
			if int(result.get("candidate", -1)) == candidate:
				var trial_score := float(result.get("fitness", -1.0e30))
				scores.append(trial_score)
				var model := str(result.get("aircraft_model", "unknown"))
				if not model_scores.has(model):
					model_scores[model] = []
				(model_scores[model] as Array).append(trial_score)
				if String(result.get("outcome", "")) == "CAUGHT" and bool(result.get("stopped", false)):
					catches += 1
		var mean := _mean(scores)
		var worst_model_mean := mean
		for model_values_variant in model_scores.values():
			var model_values: Array[float] = []
			var untyped_model_values := model_values_variant as Array
			for model_value in untyped_model_values:
				model_values.append(float(model_value))
			worst_model_mean = minf(worst_model_mean, _mean(model_values))
		var robust_fitness := mean * 0.7 + worst_model_mean * 0.3 \
			- _standard_deviation(scores, mean) * 0.25
		ranked.append({
			"candidate": candidate,
			"fitness": robust_fitness,
			"mean_fitness": mean,
			"worst_model_mean": worst_model_mean,
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
		var key := String(spec["name"])
		genome[key] = float(baseline_genome.get(key, spec["base"]))
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
	# Keep paired schedules ordered after independent mutation.
	genome["landing_sight_guidance_full_remaining_m"] = minf(
		float(genome["landing_sight_guidance_full_remaining_m"]),
		float(genome["landing_sight_guidance_start_remaining_m"]) - 50.0)
	genome["landing_final_speed_touchdown_mps"] = minf(
		float(genome["landing_final_speed_touchdown_mps"]),
		float(genome["landing_final_speed_far_mps"]) - 1.0)
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
	if int(state.get("fitness_version", 0)) != FITNESS_VERSION \
			or int(state.get("curriculum_version", 0)) != CURRICULUM_VERSION:
		return
	var best_variant: Variant = state.get("best_genome", {})
	if best_variant is Dictionary:
		_best_genome = _clamp_genome(best_variant as Dictionary)
	if int(state.get("case_count", 0)) != maxi(case_count, 1) \
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
