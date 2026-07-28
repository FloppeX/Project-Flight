extends "res://Scenario/AirplaneTestMode.gd"

const ROUTE_SCORE_SCHEMA_VERSION := 2
const ROUTE_SAVE_PATH := "user://airplane_test_best_route_genome.json"
const ROUTE_GEOMETRY_MARGIN := 0.527

const ROUTE_POINTS := [
	Vector3(1.35, 0.00, -0.60),
	Vector3(1.25, 0.20, 0.05),
	Vector3(1.55, 0.80, 0.70),
	Vector3(1.15, 1.20, 1.20),
	Vector3(0.45, 1.20, 1.45),
	Vector3(-0.30, 0.75, 1.38),
	Vector3(-0.83, 0.20, 1.68),
	Vector3(-1.35, -0.10, 1.25),
	Vector3(-1.55, 0.10, 0.65),
	Vector3(-1.35, 0.70, 0.05),
	Vector3(-1.60, 1.25, -0.55),
	Vector3(-1.25, 0.75, -1.05),
	Vector3(-0.65, 0.15, -1.35),
	Vector3(-0.10, -0.20, -1.18),
	Vector3(0.35, 0.35, -1.45),
	Vector3(0.90, 0.90, -1.35),
	Vector3(1.35, 0.40, -1.05),
]
const ROUTE_ROLES := [
	"east_gate", "east_climb_entry", "east_s_bend", "northeast_sweep",
	"north_straight", "northwest_descent", "northwest_reversal", "west_sweep",
	"west_straight", "west_climb_entry", "west_reversal_high", "southwest_descent",
	"south_straight", "south_reversal_low", "southeast_climb", "southeast_sweep",
	"east_egress",
]
const ROUTE_SPEED_SCALES := [
	1.00, 1.00, 0.96, 0.96, 1.02, 1.00, 0.94, 0.96, 1.00,
	0.98, 0.94, 0.96, 1.02, 0.96, 0.96, 0.98, 1.00,
]
const REVERSAL_POINT_INDICES := [2, 6, 9, 13]

@export var route_mutation_sigma: float = 0.055
@export var route_horizontal_scale_min: float = 0.68
@export var route_horizontal_scale_max: float = 1.08
@export var route_reversal_intensity_min: float = 0.72
@export var route_reversal_intensity_max: float = 1.45
@export var route_vertical_scale_min: float = 0.60
@export var route_vertical_scale_max: float = 1.65
@export var route_geometry_min_segment_m: float = 520.0
@export var route_geometry_min_radius_m: float = 360.0
@export var route_geometry_max_turn_deg: float = 100.0
@export var route_geometry_max_gradient: float = 0.35
@export var route_qualification_mean_xtrack_m: float = 190.0
@export var route_qualification_max_xtrack_m: float = 520.0
@export var route_qualification_mean_alt_error_m: float = 100.0
@export var route_qualification_min_agl_m: float = 420.0
@export var route_qualification_max_adjacent_forward_resyncs: int = 1

var _fixed_pilot_genome: Dictionary = {}
var _baseline_route_geometry: Dictionary = {}
var _best_route_genome: Dictionary = {}
var _best_route_record: Dictionary = {}
var _next_route_genome_id: int = 0

func _start_test() -> void:
	_setup_flat_arena()
	_fixed_pilot_genome = _load_saved_default_pilot()
	if _fixed_pilot_genome.is_empty():
		_fixed_pilot_genome = _load_genome_seed_file(PROJECT_NAVIGATION_SEED_PATH)
	if _fixed_pilot_genome.is_empty():
		_fixed_pilot_genome = super._make_default_genome()
	_ensure_route_guidance_genes(_fixed_pilot_genome)

	_base_route = super._build_base_circuit_route()
	_create_waypoint_markers()
	var baseline_genome: Dictionary = _make_default_route_genome()
	_baseline_route_geometry = _analyze_route_geometry(_build_trial_route(baseline_genome))
	var seed_routes: Array[Dictionary] = []
	var saved_route: Dictionary = _load_saved_route_genome()
	if not saved_route.is_empty():
		seed_routes.append(saved_route)
	else:
		seed_routes.append(baseline_genome)
	_start_generation(seed_routes)
	_log_event("ROUTE_EVOLUTION_START pilot=%s population=%d baseline=%s constraints=mean_x<=%.0f max_x<=%.0f min_agl>=%.0f adjacent_resyncs<=%d severe_resyncs=0" % [
		super._format_genome(_fixed_pilot_genome),
		_get_population_size(),
		_format_route_geometry(_baseline_route_geometry),
		route_qualification_mean_xtrack_m,
		route_qualification_max_xtrack_m,
		route_qualification_min_agl_m,
		route_qualification_max_adjacent_forward_resyncs,
	])

func _prepare_population(seed_genomes: Array[Dictionary]) -> Array[Dictionary]:
	var population: Array[Dictionary] = []
	var desired_count: int = _get_population_size()
	for seed: Dictionary in seed_genomes:
		_append_unique_route_genome(population, seed)
		if population.size() >= desired_count:
			return population
	if population.is_empty():
		population.append(_make_default_route_genome())
	while population.size() < desired_count:
		var parent: Dictionary = population[_rng.randi_range(0, population.size() - 1)]
		population.append(_mutate_route_genome(parent))
	return population

func _make_default_route_genome() -> Dictionary:
	var genome: Dictionary = {
		"id": _next_route_genome_id,
		"horizontal_scale": 1.0,
		"reversal_intensity": 1.0,
		"vertical_scale": 1.0,
	}
	_next_route_genome_id += 1
	return genome

func _mutate_route_genome(parent: Dictionary) -> Dictionary:
	for _attempt in range(20):
		var genome: Dictionary = parent.duplicate(true)
		genome["id"] = _next_route_genome_id
		_next_route_genome_id += 1
		genome["horizontal_scale"] = clampf(
			float(parent.get("horizontal_scale", 1.0)) + _rng.randfn(0.0, route_mutation_sigma),
			route_horizontal_scale_min,
			route_horizontal_scale_max
		)
		genome["reversal_intensity"] = clampf(
			float(parent.get("reversal_intensity", 1.0)) + _rng.randfn(0.0, route_mutation_sigma * 1.35),
			route_reversal_intensity_min,
			route_reversal_intensity_max
		)
		genome["vertical_scale"] = clampf(
			float(parent.get("vertical_scale", 1.0)) + _rng.randfn(0.0, route_mutation_sigma * 1.6),
			route_vertical_scale_min,
			route_vertical_scale_max
		)
		var geometry: Dictionary = _analyze_route_geometry(_build_trial_route(genome))
		if _route_geometry_is_valid(geometry):
			return genome
	return parent.duplicate(true)

func _build_trial_route(route_genome: Dictionary) -> Array[Dictionary]:
	var horizontal_scale: float = float(route_genome.get("horizontal_scale", 1.0))
	var reversal_intensity: float = float(route_genome.get("reversal_intensity", 1.0))
	var vertical_scale: float = float(route_genome.get("vertical_scale", 1.0))
	var adjusted_points: Array[Vector3] = []
	for point_value: Variant in ROUTE_POINTS:
		adjusted_points.append(point_value as Vector3)
	for reversal_value: Variant in REVERSAL_POINT_INDICES:
		var index: int = int(reversal_value)
		var previous: Vector3 = ROUTE_POINTS[posmod(index - 1, ROUTE_POINTS.size())]
		var current: Vector3 = ROUTE_POINTS[index]
		var next: Vector3 = ROUTE_POINTS[(index + 1) % ROUTE_POINTS.size()]
		var midpoint: Vector3 = (previous + next) * 0.5
		var deviation: Vector3 = current - midpoint
		adjusted_points[index] = midpoint + deviation * reversal_intensity

	var pilot_speed_mps: float = float(_fixed_pilot_genome.get("speed_mps", circuit_speed_mps))
	var capture_radius_m: float = float(_fixed_pilot_genome.get("capture_radius_m", 260.0))
	var route: Array[Dictionary] = []
	for index in range(adjusted_points.size()):
		var point: Vector3 = adjusted_points[index]
		var agl_m: float = circuit_altitude_agl_m + circuit_altitude_step_m * point.y * vertical_scale
		route.append({
			"position": _get_route_point(
				circuit_radius_m * point.x * horizontal_scale,
				circuit_radius_m * point.z * horizontal_scale,
				agl_m
			),
			"role": str(ROUTE_ROLES[index]),
			"speed_mps": pilot_speed_mps * float(ROUTE_SPEED_SCALES[index]),
			"capture_radius_m": capture_radius_m,
		})
	return route

func _configure_test_aircraft(aircraft: RigidBody3D, _route_genome: Dictionary) -> AIPilot:
	return super._configure_test_aircraft(aircraft, _fixed_pilot_genome)

func _place_trial_aircraft(aircraft: RigidBody3D, route: Array[Dictionary], slot_index: int, _route_genome: Dictionary) -> void:
	super._place_trial_aircraft(aircraft, route, slot_index, _fixed_pilot_genome)

func _score_trial(trial: Dictionary) -> Dictionary:
	var record: Dictionary = super._score_trial(trial)
	var route: Array[Dictionary] = _get_trial_route(trial)
	var geometry: Dictionary = _analyze_route_geometry(route)
	var difficulty: float = _calculate_route_difficulty(geometry)
	var qualified: bool = _route_record_is_qualified(record, geometry)
	var pilot_score: float = float(record.get("score", INF))
	var qualification_penalty: float = 0.0
	if not qualified:
		qualification_penalty = 100000.0
		qualification_penalty += maxf(float(record.get("mean_xtrack_m", INF)) - route_qualification_mean_xtrack_m, 0.0) * 120.0
		qualification_penalty += maxf(float(record.get("max_xtrack_m", INF)) - route_qualification_max_xtrack_m, 0.0) * 45.0
		qualification_penalty += float(int(record.get("route_resync_disqualifying_count", 0))) * 12000.0
		qualification_penalty += maxf(
			float(int(record.get("route_resync_adjacent_forward_count", 0)) - route_qualification_max_adjacent_forward_resyncs),
			0.0
		) * 6000.0
	record["pilot_score"] = pilot_score
	record["score"] = -difficulty + pilot_score * 0.01 + qualification_penalty
	record["route_qualified"] = qualified
	record["route_difficulty"] = difficulty
	record["route_geometry"] = geometry
	return record

func _route_record_is_qualified(record: Dictionary, geometry: Dictionary) -> bool:
	return (
		bool(record.get("lap_completed", false))
		and not bool(record.get("crashed", false))
		and _route_geometry_is_valid(geometry)
		and int(record.get("route_resync_disqualifying_count", 0)) == 0
		and int(record.get("route_resync_adjacent_forward_count", 0)) <= route_qualification_max_adjacent_forward_resyncs
		and float(record.get("mean_xtrack_m", INF)) <= route_qualification_mean_xtrack_m
		and float(record.get("max_xtrack_m", INF)) <= route_qualification_max_xtrack_m
		and float(record.get("mean_alt_error_m", INF)) <= route_qualification_mean_alt_error_m
		and float(record.get("min_agl_m", -INF)) >= route_qualification_min_agl_m
	)

func _score_record_less(a: Dictionary, b: Dictionary) -> bool:
	var a_qualified: bool = bool(a.get("route_qualified", false))
	var b_qualified: bool = bool(b.get("route_qualified", false))
	if a_qualified != b_qualified:
		return a_qualified
	if a_qualified:
		var a_difficulty: float = float(a.get("route_difficulty", -INF))
		var b_difficulty: float = float(b.get("route_difficulty", -INF))
		if not is_equal_approx(a_difficulty, b_difficulty):
			return a_difficulty > b_difficulty
	return float(a.get("score", INF)) < float(b.get("score", INF))

func _make_next_generation(records: Array[Dictionary]) -> Array[Dictionary]:
	var population: Array[Dictionary] = []
	var parents: Array[Dictionary] = []
	if not _best_route_genome.is_empty():
		_append_unique_route_genome(population, _best_route_genome)
		parents.append(_best_route_genome.duplicate(true))
	var parent_count: int = clampi(maxi(genetic_parent_pool_count, genetic_elite_count), 1, records.size())
	for index in range(parent_count):
		var genome_value: Variant = records[index].get("genome", {})
		if not (genome_value is Dictionary):
			continue
		var genome: Dictionary = (genome_value as Dictionary).duplicate(true)
		if index < genetic_elite_count:
			_append_unique_route_genome(population, genome)
		parents.append(genome)
	if parents.is_empty():
		parents.append(_make_default_route_genome())
	while population.size() < _get_population_size():
		var parent: Dictionary = parents[_rng.randi_range(0, parents.size() - 1)]
		population.append(_mutate_route_genome(parent))
	return population

func _append_unique_route_genome(population: Array[Dictionary], genome: Dictionary) -> void:
	for existing: Dictionary in population:
		if (
			is_equal_approx(float(existing.get("horizontal_scale", 1.0)), float(genome.get("horizontal_scale", 1.0)))
			and is_equal_approx(float(existing.get("reversal_intensity", 1.0)), float(genome.get("reversal_intensity", 1.0)))
			and is_equal_approx(float(existing.get("vertical_scale", 1.0)), float(genome.get("vertical_scale", 1.0)))
		):
			return
	population.append(genome.duplicate(true))

func _save_best_pilot_if_improved(record: Dictionary) -> void:
	if not bool(record.get("route_qualified", false)):
		return
	if not _best_route_record.is_empty() and not _score_record_less(record, _best_route_record):
		return
	var genome_value: Variant = record.get("genome", {})
	if not (genome_value is Dictionary):
		return
	var state: Dictionary = {
		"saved_unix_time": Time.get_unix_time_from_system(),
		"score_schema_version": ROUTE_SCORE_SCHEMA_VERSION,
		"generation": _generation_index,
		"trial_id": int(record.get("trial_id", -1)),
		"route_qualified": true,
		"route_difficulty": float(record.get("route_difficulty", 0.0)),
		"pilot_score": float(record.get("pilot_score", INF)),
		"mean_xtrack_m": float(record.get("mean_xtrack_m", INF)),
		"max_xtrack_m": float(record.get("max_xtrack_m", INF)),
		"mean_alt_error_m": float(record.get("mean_alt_error_m", INF)),
		"min_agl_m": float(record.get("min_agl_m", INF)),
		"evaluation_duration_s": float(record.get("evaluation_duration_s", 0.0)),
		"adjacent_forward_resyncs": int(record.get("route_resync_adjacent_forward_count", 0)),
		"disqualifying_resyncs": int(record.get("route_resync_disqualifying_count", 0)),
		"route_geometry": record.get("route_geometry", {}),
		"route_genome": (genome_value as Dictionary).duplicate(true),
		"fixed_pilot_id": int(_fixed_pilot_genome.get("id", -1)),
	}
	if _write_json_file(ROUTE_SAVE_PATH, state):
		_best_route_genome = (genome_value as Dictionary).duplicate(true)
		_best_route_record = record.duplicate(true)
		_log_event("SAVED_ROUTE_CHAMPION generation=%d id=%d difficulty=%.1f pilot_score=%.1f path=%s route=%s geometry=%s" % [
			_generation_index,
			int(record.get("trial_id", -1)),
			float(record.get("route_difficulty", 0.0)),
			float(record.get("pilot_score", INF)),
			ProjectSettings.globalize_path(ROUTE_SAVE_PATH),
			_format_genome(genome_value as Dictionary),
			_format_route_geometry(record.get("route_geometry", {}) as Dictionary),
		])

func _load_saved_route_genome() -> Dictionary:
	if not FileAccess.file_exists(ROUTE_SAVE_PATH):
		return {}
	var file: FileAccess = FileAccess.open(ROUTE_SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	var state: Dictionary = parsed as Dictionary
	var genome_value: Variant = state.get("route_genome", {})
	if not (genome_value is Dictionary):
		return {}
	var genome: Dictionary = (genome_value as Dictionary).duplicate(true)
	_next_route_genome_id = maxi(_next_route_genome_id, int(genome.get("id", -1)) + 1)
	if int(state.get("score_schema_version", 0)) == ROUTE_SCORE_SCHEMA_VERSION and bool(state.get("route_qualified", false)):
		_best_route_genome = genome.duplicate(true)
		_best_route_record = {
			"route_qualified": true,
			"route_difficulty": float(state.get("route_difficulty", -INF)),
			"score": -float(state.get("route_difficulty", -INF)),
		}
	_log_event("LOADED_ROUTE_CHAMPION generation=%d difficulty=%.1f route=%s" % [
		int(state.get("generation", -1)),
		float(state.get("route_difficulty", 0.0)),
		_format_genome(genome),
	])
	return genome

func _log_generation_ranking(records: Array[Dictionary]) -> void:
	for rank in range(records.size()):
		var record: Dictionary = records[rank]
		_log_event("ROUTE_GENERATION_RANK generation=%d rank=%d id=%d qualified=%s difficulty=%.1f fitness=%.1f pilot_score=%.1f duration=%.1f mean_x=%.1f max_x=%.1f mean_alt=%.1f min_agl=%.1f resyncs=%d adjacent=%d severe=%d route=%s geometry=%s" % [
			_generation_index,
			rank + 1,
			int(record.get("trial_id", -1)),
			str(record.get("route_qualified", false)),
			float(record.get("route_difficulty", -INF)),
			float(record.get("score", INF)),
			float(record.get("pilot_score", INF)),
			float(record.get("evaluation_duration_s", 0.0)),
			float(record.get("mean_xtrack_m", INF)),
			float(record.get("max_xtrack_m", INF)),
			float(record.get("mean_alt_error_m", INF)),
			float(record.get("min_agl_m", -INF)),
			int(record.get("route_resync_count", 0)),
			int(record.get("route_resync_adjacent_forward_count", 0)),
			int(record.get("route_resync_disqualifying_count", 0)),
			_format_genome(record.get("genome", {}) as Dictionary),
			_format_route_geometry(record.get("route_geometry", {}) as Dictionary),
		])

func _analyze_route_geometry(route: Array[Dictionary]) -> Dictionary:
	var points: Array[Vector3] = []
	for leg: Dictionary in route:
		var position_value: Variant = leg.get("position", Vector3.INF)
		if position_value is Vector3:
			points.append(position_value as Vector3)
	if points.size() < 3:
		return {"valid": false}
	var total_length_m: float = 0.0
	var min_segment_m: float = INF
	var min_radius_m: float = INF
	var max_turn_deg: float = 0.0
	var max_gradient: float = 0.0
	for index in range(points.size()):
		var previous: Vector3 = points[posmod(index - 1, points.size())]
		var current: Vector3 = points[index]
		var next: Vector3 = points[(index + 1) % points.size()]
		var incoming: Vector2 = Vector2(current.x - previous.x, current.z - previous.z)
		var outgoing: Vector2 = Vector2(next.x - current.x, next.z - current.z)
		var incoming_length_m: float = incoming.length()
		var outgoing_length_m: float = outgoing.length()
		total_length_m += outgoing_length_m
		min_segment_m = minf(min_segment_m, outgoing_length_m)
		if outgoing_length_m > 1.0:
			max_gradient = maxf(max_gradient, absf(next.y - current.y) / outgoing_length_m)
		if incoming_length_m <= 1.0 or outgoing_length_m <= 1.0:
			min_radius_m = 0.0
			continue
		var turn_rad: float = acos(clampf(incoming.normalized().dot(outgoing.normalized()), -1.0, 1.0))
		max_turn_deg = maxf(max_turn_deg, rad_to_deg(turn_rad))
		var half_turn_tan: float = tan(turn_rad * 0.5)
		if half_turn_tan > 0.001:
			var available_radius_m: float = minf(incoming_length_m, outgoing_length_m) * ROUTE_GEOMETRY_MARGIN / half_turn_tan
			min_radius_m = minf(min_radius_m, available_radius_m)
	var intersections: int = _count_route_intersections(points)
	return {
		"valid": intersections == 0,
		"total_length_m": total_length_m,
		"min_segment_m": min_segment_m,
		"min_radius_m": min_radius_m,
		"max_turn_deg": max_turn_deg,
		"max_gradient": max_gradient,
		"intersections": intersections,
	}

func _route_geometry_is_valid(geometry: Dictionary) -> bool:
	return (
		bool(geometry.get("valid", false))
		and int(geometry.get("intersections", 1)) == 0
		and float(geometry.get("min_segment_m", 0.0)) >= route_geometry_min_segment_m
		and float(geometry.get("min_radius_m", 0.0)) >= route_geometry_min_radius_m
		and float(geometry.get("max_turn_deg", INF)) <= route_geometry_max_turn_deg
		and float(geometry.get("max_gradient", INF)) <= route_geometry_max_gradient
	)

func _calculate_route_difficulty(geometry: Dictionary) -> float:
	if _baseline_route_geometry.is_empty():
		return 0.0
	var baseline_radius_m: float = maxf(float(_baseline_route_geometry.get("min_radius_m", 1.0)), 1.0)
	var candidate_radius_m: float = maxf(float(geometry.get("min_radius_m", baseline_radius_m)), 1.0)
	var baseline_turn_deg: float = float(_baseline_route_geometry.get("max_turn_deg", 0.0))
	var candidate_turn_deg: float = float(geometry.get("max_turn_deg", baseline_turn_deg))
	var baseline_gradient: float = float(_baseline_route_geometry.get("max_gradient", 0.0))
	var candidate_gradient: float = float(geometry.get("max_gradient", baseline_gradient))
	var baseline_length_m: float = maxf(float(_baseline_route_geometry.get("total_length_m", 1.0)), 1.0)
	var candidate_length_m: float = maxf(float(geometry.get("total_length_m", baseline_length_m)), 1.0)
	return (
		(baseline_radius_m / candidate_radius_m - 1.0) * 900.0
		+ (candidate_turn_deg - baseline_turn_deg) * 10.0
		+ (candidate_gradient - baseline_gradient) * 1800.0
		+ (baseline_length_m / candidate_length_m - 1.0) * 350.0
	)

func _count_route_intersections(points: Array[Vector3]) -> int:
	var intersections: int = 0
	for first_index in range(points.size()):
		var first_next: int = (first_index + 1) % points.size()
		var a: Vector2 = Vector2(points[first_index].x, points[first_index].z)
		var b: Vector2 = Vector2(points[first_next].x, points[first_next].z)
		for second_index in range(first_index + 1, points.size()):
			var second_next: int = (second_index + 1) % points.size()
			if second_index == first_index or second_index == first_next or second_next == first_index:
				continue
			var c: Vector2 = Vector2(points[second_index].x, points[second_index].z)
			var d: Vector2 = Vector2(points[second_next].x, points[second_next].z)
			if _segments_intersect_2d(a, b, c, d):
				intersections += 1
	return intersections

func _segments_intersect_2d(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c: float = (b - a).cross(c - a)
	var ab_d: float = (b - a).cross(d - a)
	var cd_a: float = (d - c).cross(a - c)
	var cd_b: float = (d - c).cross(b - c)
	return ab_c * ab_d < 0.0 and cd_a * cd_b < 0.0

func _get_score_schema_version() -> int:
	return ROUTE_SCORE_SCHEMA_VERSION

func _format_genome(genome: Dictionary) -> String:
	if genome.has("horizontal_scale"):
		return "rid=%d scale=%.3f reversal=%.3f vertical=%.3f" % [
			int(genome.get("id", -1)),
			float(genome.get("horizontal_scale", 1.0)),
			float(genome.get("reversal_intensity", 1.0)),
			float(genome.get("vertical_scale", 1.0)),
		]
	return super._format_genome(genome)

func _format_route_geometry(geometry: Dictionary) -> String:
	return "len=%.0f min_seg=%.0f min_radius=%.0f max_turn=%.1f max_grade=%.3f intersections=%d" % [
		float(geometry.get("total_length_m", 0.0)),
		float(geometry.get("min_segment_m", 0.0)),
		float(geometry.get("min_radius_m", 0.0)),
		float(geometry.get("max_turn_deg", 0.0)),
		float(geometry.get("max_gradient", 0.0)),
		int(geometry.get("intersections", 0)),
	]
