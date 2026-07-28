extends Node3D

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")
const TEST_GUN_SCENE: PackedScene = preload("res://Weapons/Guns/Hardpoint/15mm_machine_gun_hardpoint.tscn")
const TEST_TARGET_SCRIPT: Script = preload("res://Scenario/AirplaneTestTarget.gd")
const REPORT_PATH := "user://airplane_test_report.log"
const LEGACY_BEST_PILOT_PATH := "user://airplane_test_best_pilot.json"
const LEGACY_DEFAULT_PILOT_PATH := "user://airplane_test_default_pilot.json"
const PROJECT_ROCKET_SPECIALIST_PATH := "res://Scenario/airplane_test_best_rocket_genome.json"
const PROJECT_NAVIGATION_SEED_PATH := "res://Scenario/airplane_test_best_navigation_genome.json"
const MIXED_ATTACK_SCORE_SCHEMA_VERSION := 4  # bumped: added margin/crash incentives (low-alt penalty, crash 8000->45000)
const NAVIGATION_SCORE_SCHEMA_VERSION := 7
const NAVIGATION_TURN_PULL_BOOTSTRAP_VALUES: Array[float] = [0.0, 0.04, 0.08, 0.12]
const NAVIGATION_GENE_KEYS: PackedStringArray = [
	"speed_mps", "capture_radius_m", "lookahead_m", "lookahead_radius_fraction",
	"bank_limit_deg", "pitch_smoothing", "pitch_input_smoothing", "input_smoothing",
	"high_bank_roll_damping", "high_bank_yaw_scale", "vs_gain", "auto_rudder_strength",
	"sideslip_gain", "route_recovery_start_m", "route_recovery_full_m",
	"route_recovery_lookahead_scale", "route_recovery_speed_cut_mps",
	"route_projection_advance_max_xtrack_m", "route_projection_blend",
	"route_projection_gain", "route_capture_radius_scale", "route_capture_max_angle_deg",
	"route_capture_max_blend", "route_fpv_yaw_blend", "pitch_altitude_trim",
	"above_path_unload_start_m", "above_path_unload_full_m", "above_path_unload_pitch",
	"turn_pull_pitch_input", "fpv_pitch_gain", "fpv_pitch_damping", "fpv_pitch_limit",
	"route_flyby_start_fraction", "route_flyby_lookahead_fraction", "route_turn_tangent_fraction",
	"route_curvature_feedforward_gain", "navigation_bank_gain", "navigation_roll_p_gain",
	"navigation_roll_high_bank_p_gain", "navigation_roll_rate_damping", "navigation_roll_min_input",
]
const PILOT_DRESSING_DOWN: String = "Returning safely is the minimum requirement, not the entire mission. Flying an immaculate circuit, pointing vaguely toward the enemy, and bringing every rocket home is not combat effectiveness. Line up properly, commit to the attack, achieve a usable firing solution, release your weapons, and execute a controlled egress. Do not dive at targets behind you. Do not shut down your engines. Do not mistake indecision for caution. Get your act together."

@export var circuit_radius_m: float = 2200.0
@export var circuit_altitude_agl_m: float = 720.0
@export var circuit_altitude_step_m: float = 140.0
@export var circuit_speed_mps: float = 105.0
@export var sample_interval_s: float = 1.0
@export var test_aircraft_count: int = 4
@export var spawn_interval_s: float = 8.0
@export var navigation_turn_pull_bootstrap_sweep_enabled: bool = false
@export var generation_duration_s: float = 420.0
@export var mixed_generation_hard_timeout_s: float = 720.0
@export var full_lap_evaluation_enabled: bool = true
@export var full_lap_required_laps: int = 1
@export var full_lap_timeout_s: float = 420.0
@export var genetic_tuning_enabled: bool = true
@export var genetic_population_size: int = 4
@export var genetic_elite_count: int = 1
@export var genetic_parent_pool_count: int = 2
@export var genetic_mutation_sigma: float = 0.12
@export var seed_from_saved_default_pilot: bool = true
@export var save_best_pilot_as_default: bool = true
@export var genetic_preserve_saved_best: bool = true
@export var deterministic_validation_enabled: bool = false
@export var deterministic_validation_seed: int = 21021
@export var deterministic_validation_aircraft_count: int = 1
@export var mixed_seed_weapon_specialists: bool = true
@export var mixed_preserve_weapon_specialists: bool = true
@export var mixed_min_population_size: int = 6
@export var mixed_lock_navigation_genes: bool = true
@export var aggressive_maneuvering_enabled: bool = true  # Boost turn-hardness genes over the locked nav baseline; accept occasional crashes for now
@export var attack_phase_enabled: bool = true
@export var attack_phase_start_s: float = 45.0
@export var terminal_attack_regression_enabled: bool = false
@export var terminal_attack_regression_start_s: float = 3.0
@export var terminal_attack_corridor_directions: int = 16
@export var terminal_attack_corridor_samples: int = 24
@export var terminal_attack_corridor_clearance_m: float = 260.0
@export var attack_circuit_waypoint_index: int = 4
@export var attack_mixed_cycle_waypoint_indices: Array[int] = [4, 9, 14]
@export var attack_cycles_per_trial: int = 3
@export var attack_positioning_supervisor_grace_s: float = 25.0
@export var attack_positioning_retry_immediately: bool = true
@export var mixed_attack_run_budget_s: float = 150.0
@export var mixed_attack_interphase_delay_s: float = 12.0
@export var attack_mind_sample_ages_s: Array[float] = [4.0, 12.0, 25.0, 45.0]
@export var attack_target_offset_m: Vector3 = Vector3(900.0, 0.0, 350.0)
@export var attack_target_offsets_m: Array[Vector3] = [
	Vector3(900.0, 0.0, 350.0),
	Vector3(-650.0, 0.0, 920.0),
	Vector3(1250.0, 0.0, -850.0),
	Vector3(-1100.0, 0.0, -520.0),
]
@export var attack_target_footprint_m: Vector2 = Vector2(20.0, 20.0)
# Moving targets: when enabled, each target patrols a loop around its spawn point like an enemy
# ground vehicle, so pilots must lead a moving aim point. 0 speed / disabled = the old static test.
@export var attack_targets_move: bool = true
@export var attack_target_move_speed_mps: float = 14.0   # ~50 km/h, a plausible ground-vehicle pace
@export var attack_target_patrol_radius_m: float = 220.0  # size of the patrol loop around the spawn point
@export var attack_target_patrol_waypoints: int = 4       # corners of the patrol loop
@export var attack_target_flat_search_radius_m: float = 3000.0
@export var attack_target_flat_search_step_m: float = 120.0
@export var attack_target_max_footprint_height_span_m: float = 3.0
@export var attack_target_open_radius_m: float = 700.0
@export var attack_target_open_sample_step_m: float = 100.0
@export var attack_target_max_open_height_span_m: float = 14.0
@export var flat_arena_enabled: bool = false
@export var flat_arena_ground_y: float = 0.0
@export var flat_arena_center: Vector3 = Vector3.ZERO
@export var flat_arena_size_m: float = 14000.0
@export var flat_arena_disable_real_terrain: bool = true
@export var flat_arena_visual_enabled: bool = true
@export var strip_external_ordnance: bool = true
@export_enum("Rockets", "Bombs", "Guns", "Mixed") var attack_test_weapon_mode: String = "Mixed"
@export var attack_test_mixed_sequence: Array[String] = ["Bombs", "Rockets", "Guns"]
@export var attack_test_keep_rocket_pods: bool = true
@export var attack_test_unlimited_rockets: bool = true
@export var attack_test_unlimited_bombs: bool = true
@export var rocket_hit_radius_m: float = 18.0
@export var bomb_hit_radius_m: float = 32.0
@export var gun_hit_radius_m: float = 10.0
@export var gun_test_max_range_m: float = 1300.0
@export var mixed_score_missing_weapon_phase_penalty: float = 35000.0
@export var mixed_score_min_rocket_launches: int = 4
@export var mixed_score_min_gun_shots: int = 24
@export var mixed_score_per_weapon_hit_bonus: float = 750.0
@export var mixed_score_complete_all_weapons_bonus: float = 1800.0
@export var mixed_save_requires_all_weapon_phases: bool = true
@export var stow_landing_gear_on_start: bool = true
@export var navigation_auto_rudder_strength: float = 0.32
@export var navigation_spawn_cross_track_offset_m: float = 900.0
@export var navigation_spawn_altitude_offset_m: float = 180.0
@export var navigation_capture_cross_track_m: float = 120.0
@export var navigation_capture_altitude_error_m: float = 70.0
@export var navigation_capture_settle_samples: int = 5

var play_area_center: Vector3 = Vector3.ZERO
var _target: Node3D = null
var _targets: Array[Node3D] = []
var _base_route: Array[Dictionary] = []
var _trials: Array[Dictionary] = []
var _population_genomes: Array[Dictionary] = []
var _elapsed_s: float = 0.0
var _sample_timer_s: float = 0.0
var _attack_phase_started: bool = false
var _report_file: FileAccess = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _generation_index: int = 0
var _generation_start_s: float = 0.0
var _pending_spawn_index: int = 0
var _next_spawn_time_s: float = 0.0
var _next_trial_id: int = 0
var _next_genome_id: int = 0
var _view_assigned: bool = false
var _physics_tick_logged: bool = false
var _best_saved_score: float = INF
var _best_saved_generation: int = -1
var _best_saved_genome: Dictionary = {}
var _best_saved_record: Dictionary = {}
var _validation_genome: Dictionary = {}
var _mixed_navigation_baseline_genome: Dictionary = {}
var _flat_arena_root: Node3D = null
var _flat_arena_disabled_nodes: Array[Dictionary] = []

func configure(center: Vector3) -> void:
	play_area_center = center

func _ready() -> void:
	name = "AirplaneTestMode"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(true)
	add_to_group("origin_shifter")
	if deterministic_validation_enabled:
		_rng.seed = deterministic_validation_seed
	else:
		_rng.randomize()
	_open_report()
	_configure_autoloads_for_test()
	call_deferred("_start_test")

func _exit_tree() -> void:
	_log_all_summaries("exit")
	_restore_flat_arena_scene_nodes()
	if _report_file != null:
		_report_file.close()
		_report_file = null

func apply_origin_shift(offset: Vector3) -> void:
	play_area_center -= offset
	if flat_arena_enabled:
		flat_arena_center -= offset
	# Test targets are root Node3D children, so FloatingOrigin shifts their transforms
	# before notifying this cached-coordinate hook.
	_shift_route(_base_route, offset)
	for i in range(_trials.size()):
		var trial: Dictionary = _trials[i]
		var route_value: Variant = trial.get("route", [])
		if route_value is Array:
			var route: Array = route_value as Array
			_shift_route(route, offset)
			trial["route"] = route
		trial["previous_cross_track_m"] = NAN
		trial["previous_sample_time_s"] = NAN
		trial["previous_velocity"] = Vector3.INF
		var pilot: AIPilot = _get_trial_pilot(trial)
		if pilot != null and pilot.current_state == AIPilot.State.SEARCH and not _attack_phase_started:
			trial["route_sync_pending"] = true
			var waypoint_index: int = pilot.current_waypoint_index
			var trial_id: int = int(trial.get("id", -1))
			call_deferred("_sync_circuit_route_after_origin_shift", trial_id, waypoint_index)
		_trials[i] = trial

func get_height(_world_pos: Vector3) -> float:
	if flat_arena_enabled:
		return flat_arena_ground_y
	return NAN

func _sync_circuit_route_after_origin_shift(trial_id: int, waypoint_index: int) -> void:
	var trial_index: int = _find_trial_index(trial_id)
	if trial_index < 0:
		return
	var trial: Dictionary = _trials[trial_index]
	var pilot: AIPilot = _get_trial_pilot(trial)
	if pilot == null or _attack_phase_started:
		trial["route_sync_pending"] = false
		_trials[trial_index] = trial
		return
	var route: Array[Dictionary] = _get_trial_route(trial)
	pilot.set_flight_plan_legs("airplane_test_circuit", route, false, true)
	pilot.current_waypoint_index = clampi(waypoint_index, 0, maxi(pilot.waypoints.size() - 1, 0))
	if not pilot.waypoints.is_empty():
		pilot.nav_waypoint = pilot.waypoints[pilot.current_waypoint_index]
	trial["route_sync_pending"] = false
	_trials[trial_index] = trial

func _physics_process(delta: float) -> void:
	if not _physics_tick_logged:
		_physics_tick_logged = true
		_log_event("PHYSICS_START paused=%s process_mode=%d pending=%d population=%d" % [
			str(get_tree().paused),
			process_mode,
			_pending_spawn_index,
			_population_genomes.size(),
		])
	_elapsed_s += delta
	_spawn_due_trials()
	_maybe_start_attack_phase()
	_update_attack_cycle_supervisor()
	_sample_timer_s -= delta
	if _sample_timer_s <= 0.0:
		_sample_timer_s = maxf(sample_interval_s, 0.1)
		_sample_route_following()
	_update_generation_completion()

func _start_test() -> void:
	_setup_flat_arena()
	_base_route = _build_base_circuit_route()
	_create_waypoint_markers()
	var seed_genomes: Array[Dictionary] = []
	if _attack_is_mixed_mode():
		var navigation_genome: Dictionary = _load_genome_seed_file("user://airplane_test_default_pilot_navigation.json")
		if navigation_genome.is_empty():
			navigation_genome = _load_genome_seed_file(PROJECT_NAVIGATION_SEED_PATH)
		if not navigation_genome.is_empty():
			_mixed_navigation_baseline_genome = navigation_genome.duplicate(true)
			_append_seed_genome(seed_genomes, navigation_genome)
			_log_event("MIXED_NAVIGATION_SEED genome=%s" % _format_genome(navigation_genome))
	if seed_from_saved_default_pilot:
		var saved_genome: Dictionary = _load_saved_default_pilot()
		if not saved_genome.is_empty():
			_append_seed_genome(seed_genomes, saved_genome)
	if mixed_seed_weapon_specialists:
		for specialist_genome: Dictionary in _load_mixed_specialist_seed_genomes():
			_append_seed_genome(seed_genomes, specialist_genome)
	_start_generation(seed_genomes)
	_log_event("START center=%s route_points=%d aircraft_per_generation=%d genetic=%s validation=%s validation_seed=%d generation_duration=%.1f full_lap=%s required_laps=%d full_lap_timeout=%.1f attack_phase=%s weapon=%s mixed_nav_locked=%s" % [
		_fmt_v3(play_area_center),
		_base_route.size(),
		_get_population_size(),
		str(genetic_tuning_enabled),
		str(deterministic_validation_enabled),
		deterministic_validation_seed,
		generation_duration_s,
		str(_uses_full_lap_evaluation()),
		maxi(full_lap_required_laps, 1),
		full_lap_timeout_s,
		str(attack_phase_enabled),
		attack_test_weapon_mode,
		str(_attack_is_mixed_mode() and mixed_lock_navigation_genes and not _mixed_navigation_baseline_genome.is_empty()),
	])

func _configure_autoloads_for_test() -> void:
	if AirOpsManager != null:
		AirOpsManager.maintain_carrier_cap = false
		AirOpsManager.debug_print = false
		AirOpsManager.set_process(false)
	if GroundOpsManager != null:
		GroundOpsManager.debug_print = false
		GroundOpsManager.set_process(false)
	if EnemyBaseManager != null:
		EnemyBaseManager.set("_disabled_for_test", true)
		EnemyBaseManager.set_process(false)
	if EnemyOpsManager != null:
		EnemyOpsManager.set("_disabled_for_test", true)
		EnemyOpsManager.debug_print = false
		EnemyOpsManager.set_process(false)

func _setup_flat_arena() -> void:
	if not flat_arena_enabled:
		return
	play_area_center = Vector3(flat_arena_center.x, flat_arena_ground_y, flat_arena_center.z)
	if flat_arena_disable_real_terrain:
		_disable_real_terrain_for_flat_arena()
	add_to_group("terrain_provider")
	if TerrainReference != null:
		TerrainReference.terrain_node = self
	_create_flat_arena_plane()
	_log_event("FLAT_ARENA_ENABLED center=%s ground_y=%.1f size=%.0f disabled_nodes=%d visual=%s" % [
		_fmt_v3(play_area_center),
		flat_arena_ground_y,
		flat_arena_size_m,
		_flat_arena_disabled_nodes.size(),
		str(flat_arena_visual_enabled),
	])

func _disable_real_terrain_for_flat_arena() -> void:
	var candidates: Array[Node] = []
	var root: Node = get_tree().current_scene
	if root != null:
		for node_path_value in [
			"LowPolyTerrainPrototype",
			"RockStream",
			"PlantPatchStreamer",
			"RockFeatureSpawner",
			"RockScatter",
		]:
			var node_path: String = str(node_path_value)
			var named_node: Node = root.get_node_or_null(node_path)
			if named_node != null:
				candidates.append(named_node)
	for group_name_value in ["terrain", "terrain_provider"]:
		var group_name: String = str(group_name_value)
		for group_node: Node in get_tree().get_nodes_in_group(group_name):
			if group_node != null:
				candidates.append(group_node)
	for candidate: Node in candidates:
		_disable_scene_node_for_flat_arena(candidate)

func _disable_scene_node_for_flat_arena(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node == _flat_arena_root:
		return
	for entry: Dictionary in _flat_arena_disabled_nodes:
		var existing: Variant = entry.get("node", null)
		if existing == node:
			return
	var entry: Dictionary = {
		"node": node,
		"processing": node.is_processing(),
		"physics_processing": node.is_physics_processing(),
	}
	if node is CollisionObject3D:
		var collision_object: CollisionObject3D = node as CollisionObject3D
		entry["collision_layer"] = collision_object.collision_layer
		entry["collision_mask"] = collision_object.collision_mask
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if node is CollisionShape3D:
		var collision_shape: CollisionShape3D = node as CollisionShape3D
		entry["disabled"] = collision_shape.disabled
		collision_shape.disabled = true
	if node is Node3D:
		var node_3d: Node3D = node as Node3D
		entry["visible"] = node_3d.visible
		node_3d.visible = false
	node.set_process(false)
	node.set_physics_process(false)
	_flat_arena_disabled_nodes.append(entry)

func _create_flat_arena_plane() -> void:
	if _flat_arena_root != null and is_instance_valid(_flat_arena_root):
		return
	var root: Node = get_tree().current_scene
	if root == null:
		root = self
	var arena_root: Node3D = Node3D.new()
	arena_root.name = "AirplaneTestFlatArena"
	arena_root.global_position = Vector3(play_area_center.x, flat_arena_ground_y, play_area_center.z)
	root.add_child(arena_root)
	_flat_arena_root = arena_root

	var body: StaticBody3D = StaticBody3D.new()
	body.name = "FlatArenaBody"
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("terrain")
	body.add_to_group("ground")
	arena_root.add_child(body)

	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	var size_m: float = maxf(flat_arena_size_m, circuit_radius_m * 4.0)
	box_shape.size = Vector3(size_m, 12.0, size_m)
	shape.shape = box_shape
	shape.position = Vector3(0.0, -6.0, 0.0)
	body.add_child(shape)

	if flat_arena_visual_enabled:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.name = "FlatArenaVisual"
		var mesh: PlaneMesh = PlaneMesh.new()
		mesh.size = Vector2(size_m, size_m)
		mesh_instance.mesh = mesh
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.56, 0.50, 0.38, 1.0)
		material.roughness = 0.92
		mesh_instance.material_override = material
		arena_root.add_child(mesh_instance)

func _restore_flat_arena_scene_nodes() -> void:
	if _flat_arena_root != null and is_instance_valid(_flat_arena_root):
		_flat_arena_root.queue_free()
	_flat_arena_root = null
	remove_from_group("terrain_provider")
	if TerrainReference != null and TerrainReference.terrain_node == self:
		TerrainReference.terrain_node = null
	for entry: Dictionary in _flat_arena_disabled_nodes:
		var node_value: Variant = entry.get("node", null)
		if not is_instance_valid(node_value):
			continue
		var node: Node = node_value as Node
		if node == null:
			continue
		node.set_process(bool(entry.get("processing", false)))
		node.set_physics_process(bool(entry.get("physics_processing", false)))
		if node is CollisionObject3D:
			var collision_object: CollisionObject3D = node as CollisionObject3D
			collision_object.collision_layer = int(entry.get("collision_layer", collision_object.collision_layer))
			collision_object.collision_mask = int(entry.get("collision_mask", collision_object.collision_mask))
		if node is CollisionShape3D:
			var collision_shape: CollisionShape3D = node as CollisionShape3D
			collision_shape.disabled = bool(entry.get("disabled", collision_shape.disabled))
		if node is Node3D:
			var node_3d: Node3D = node as Node3D
			node_3d.visible = bool(entry.get("visible", node_3d.visible))
	_flat_arena_disabled_nodes.clear()

func _start_generation(genomes: Array[Dictionary]) -> void:
	_clear_trials()
	_clear_attack_target()
	_attack_phase_started = false
	if attack_phase_enabled:
		_spawn_attack_targets()
	_population_genomes = _prepare_population(genomes)
	_pending_spawn_index = 0
	_next_spawn_time_s = _elapsed_s
	_generation_start_s = _elapsed_s
	_view_assigned = false
	_log_event("GENERATION_START generation=%d population=%d stagger_s=%.1f" % [
		_generation_index,
		_population_genomes.size(),
		spawn_interval_s,
	])
	_log_event("PILOT_BRIEFING generation=%d text=\"%s\"" % [_generation_index, PILOT_DRESSING_DOWN])

func _prepare_population(seed_genomes: Array[Dictionary]) -> Array[Dictionary]:
	var population: Array[Dictionary] = []
	var desired_count: int = _get_population_size()
	if deterministic_validation_enabled:
		if _validation_genome.is_empty():
			_validation_genome = seed_genomes[0].duplicate(true) if not seed_genomes.is_empty() else _make_default_genome()
		while population.size() < desired_count:
			population.append(_validation_genome.duplicate(true))
		return population
	if (
		_generation_index == 0
		and not attack_phase_enabled
		and navigation_turn_pull_bootstrap_sweep_enabled
		and not seed_genomes.is_empty()
	):
		var base_genome: Dictionary = seed_genomes[0].duplicate(true)
		for index: int in range(mini(desired_count, NAVIGATION_TURN_PULL_BOOTSTRAP_VALUES.size())):
			var sweep_genome: Dictionary = base_genome.duplicate(true)
			if index > 0:
				sweep_genome["id"] = _next_genome_id
				_next_genome_id += 1
			sweep_genome["turn_pull_pitch_input"] = NAVIGATION_TURN_PULL_BOOTSTRAP_VALUES[index]
			population.append(sweep_genome)
		_log_event("TURN_PULL_SWEEP generation=0 values=%s" % str(NAVIGATION_TURN_PULL_BOOTSTRAP_VALUES))
	if not seed_genomes.is_empty():
		for seed: Dictionary in seed_genomes:
			if population.size() >= desired_count:
				break
			var normalized_seed: Dictionary = seed.duplicate(true)
			_apply_mixed_navigation_baseline(normalized_seed)
			population.append(normalized_seed)
	while population.size() < desired_count:
		if _generation_index == 0 and population.is_empty():
			population.append(_make_default_genome())
		else:
			var parent: Dictionary = _make_default_genome()
			if not seed_genomes.is_empty():
				parent = seed_genomes[_rng.randi_range(0, seed_genomes.size() - 1)]
			population.append(_mutate_genome(parent))
	return population

func _apply_mixed_navigation_baseline(genome: Dictionary) -> void:
	if not mixed_lock_navigation_genes or not _attack_is_mixed_mode() or _mixed_navigation_baseline_genome.is_empty():
		return
	for key: String in NAVIGATION_GENE_KEYS:
		if _mixed_navigation_baseline_genome.has(key):
			genome[key] = _mixed_navigation_baseline_genome[key]
	_apply_aggressive_maneuvering_overrides(genome)

# The locked navigation baseline (gid=542) flies a clean but timid circuit -- shallow banks,
# late corner cuts, no turn back-pressure. Push the turn-hardness genes toward the aggressive
# end of their evolved ranges so pilots crank harder toward waypoints and dive straight into
# attacks. Occasional crashes are acceptable for now; safety can be tuned back later.
# Set aggressive_maneuvering_enabled = false to restore the plain locked baseline.
func _apply_aggressive_maneuvering_overrides(genome: Dictionary) -> void:
	if not aggressive_maneuvering_enabled:
		return
	genome["navigation_bank_gain"] = 2.2                # was ~1.56 (range 0.90-2.40): bank harder toward lateral error
	genome["navigation_roll_p_gain"] = 14.0             # was ~10.1 (range 6-16): snappier roll onto commanded bank
	genome["route_capture_max_angle_deg"] = 60.0        # was ~49.7 (range 25-60): cut toward the waypoint at steeper angles
	genome["route_turn_tangent_fraction"] = 0.80        # was ~0.51 (range 0.35-0.85): anticipate/cut corners much more
	genome["route_curvature_feedforward_gain"] = 1.5    # was ~0.90 (range 0.0-1.60): feed turn rate forward aggressively
	genome["turn_pull_pitch_input"] = 0.06              # was 0.0; 0.15 pulled the nose earthward in steep banks and dragged pilots into terrain -- keep a light tightening pull only
	genome["attack_route_bank_limit_deg"] = 85.0        # was ~79: allow steeper bank while lining up attacks

func _make_default_genome() -> Dictionary:
	var genome: Dictionary = {
		"id": _next_genome_id,
		"speed_mps": 99.6,
		"capture_radius_m": 266.0,
		"lookahead_m": 760.0,
		"lookahead_radius_fraction": 0.50,
		"bank_limit_deg": 68.1,
		"pitch_smoothing": 0.22,
		"pitch_input_smoothing": 0.56,
		"input_smoothing": 0.86,
		"high_bank_roll_damping": 0.54,
		"high_bank_yaw_scale": 0.49,
		"vs_gain": 0.052,
		"auto_rudder_strength": 0.68,
		"sideslip_gain": 1.44,
		"route_recovery_start_m": 140.0,
		"route_recovery_full_m": 462.0,
		"route_recovery_lookahead_scale": 0.14,
		"route_recovery_speed_cut_mps": 13.0,
		"route_projection_advance_max_xtrack_m": 617.0,
		"route_projection_blend": 0.72,
		"route_projection_gain": 1.55,
		"route_capture_radius_scale": 1.0,
		"route_capture_max_angle_deg": 45.0,
		"route_capture_max_blend": 0.90,
		"route_fpv_yaw_blend": 0.55,
		"route_flyby_start_fraction": 1.0,
		"route_flyby_lookahead_fraction": 0.55,
		"route_turn_tangent_fraction": 0.62,
		"route_curvature_feedforward_gain": 1.0,
		"navigation_bank_gain": 1.5,
		"navigation_roll_p_gain": 11.0,
		"navigation_roll_high_bank_p_gain": 4.5,
		"navigation_roll_rate_damping": 0.30,
		"navigation_roll_min_input": 0.45,
		"pitch_altitude_trim": 0.02,
		"above_path_unload_start_m": 30.0,
		"above_path_unload_full_m": 396.0,
		"above_path_unload_pitch": 0.68,
		"turn_pull_pitch_input": 0.08,
		"fpv_pitch_gain": 1.35,
		"fpv_pitch_damping": 0.20,
		"fpv_pitch_limit": 0.46,
		"attack_route_lookahead_fraction": 0.35,
		"attack_route_capture_scale": 1.0,
		"attack_route_projection_blend": 0.72,
		"attack_route_projection_gain": 1.55,
		"attack_route_bank_limit_deg": 75.0,
		"rocket_ccip_pitch_gain": -0.55,
		"rocket_ccip_yaw_gain": 0.55,
		"rocket_ccip_pitch_damp": 0.14,
		"rocket_ccip_yaw_damp": 0.12,
		"rocket_ccip_max_pitch": 0.22,
		"rocket_ccip_max_yaw": 0.18,
		"rocket_ccip_smooth": 0.35,
	}
	_next_genome_id += 1
	return genome

func _ensure_route_guidance_genes(genome: Dictionary) -> bool:
	var changed: bool = false
	if not genome.has("route_projection_blend"):
		genome["route_projection_blend"] = 0.72
		changed = true
	if not genome.has("route_projection_gain"):
		genome["route_projection_gain"] = 1.55
		changed = true
	if not genome.has("route_capture_radius_scale"):
		genome["route_capture_radius_scale"] = 1.0
		changed = true
	if not genome.has("route_capture_max_angle_deg"):
		genome["route_capture_max_angle_deg"] = 45.0
		changed = true
	if not genome.has("route_capture_max_blend"):
		genome["route_capture_max_blend"] = 0.90
		changed = true
	if not genome.has("route_fpv_yaw_blend"):
		genome["route_fpv_yaw_blend"] = 0.55
		changed = true
	if not genome.has("route_flyby_start_fraction"):
		genome["route_flyby_start_fraction"] = 1.0
		changed = true
	if not genome.has("route_flyby_lookahead_fraction"):
		genome["route_flyby_lookahead_fraction"] = 0.55
		changed = true
	if not genome.has("route_turn_tangent_fraction"):
		genome["route_turn_tangent_fraction"] = 0.62
		changed = true
	if not genome.has("route_curvature_feedforward_gain"):
		genome["route_curvature_feedforward_gain"] = 1.0
		changed = true
	if not genome.has("navigation_bank_gain"):
		genome["navigation_bank_gain"] = 1.5
		changed = true
	if not genome.has("navigation_roll_p_gain"):
		genome["navigation_roll_p_gain"] = 11.0
		changed = true
	if not genome.has("navigation_roll_high_bank_p_gain"):
		genome["navigation_roll_high_bank_p_gain"] = 4.5
		changed = true
	if not genome.has("navigation_roll_rate_damping"):
		genome["navigation_roll_rate_damping"] = 0.30
		changed = true
	if not genome.has("navigation_roll_min_input"):
		genome["navigation_roll_min_input"] = 0.45
		changed = true
	if not genome.has("turn_pull_pitch_input"):
		genome["turn_pull_pitch_input"] = 0.0
		changed = true
	if not genome.has("fpv_pitch_gain"):
		genome["fpv_pitch_gain"] = 1.35
		changed = true
	if not genome.has("fpv_pitch_damping"):
		genome["fpv_pitch_damping"] = 0.20
		changed = true
	if not genome.has("fpv_pitch_limit"):
		genome["fpv_pitch_limit"] = 0.46
		changed = true
	if not genome.has("attack_route_lookahead_fraction"):
		genome["attack_route_lookahead_fraction"] = 0.35
		changed = true
	if not genome.has("attack_route_capture_scale"):
		genome["attack_route_capture_scale"] = 1.0
		changed = true
	if not genome.has("attack_route_projection_blend"):
		genome["attack_route_projection_blend"] = 0.72
		changed = true
	if not genome.has("attack_route_projection_gain"):
		genome["attack_route_projection_gain"] = 1.55
		changed = true
	if not genome.has("attack_route_bank_limit_deg"):
		genome["attack_route_bank_limit_deg"] = 75.0
		changed = true
	return changed

func _mutate_genome(parent: Dictionary) -> Dictionary:
	var genome: Dictionary = parent.duplicate(true)
	genome["id"] = _next_genome_id
	_next_genome_id += 1
	genome["speed_mps"] = _mutate_float(float(parent.get("speed_mps", circuit_speed_mps)), 92.0, 122.0, 9.0)
	genome["capture_radius_m"] = _mutate_float(float(parent.get("capture_radius_m", 300.0)), 220.0, 520.0, 85.0)
	genome["lookahead_m"] = _mutate_float(float(parent.get("lookahead_m", 1100.0)), 700.0, 1900.0, 280.0)
	genome["lookahead_radius_fraction"] = _mutate_float(float(parent.get("lookahead_radius_fraction", 0.82)), 0.45, 1.30, 0.20)
	genome["bank_limit_deg"] = _mutate_float(float(parent.get("bank_limit_deg", 72.0)), 52.0, 82.0, 8.0)
	genome["pitch_smoothing"] = _mutate_float(float(parent.get("pitch_smoothing", 0.34)), 0.18, 0.62, 0.10)
	genome["pitch_input_smoothing"] = _mutate_float(float(parent.get("pitch_input_smoothing", 0.50)), 0.30, 0.82, 0.10)
	genome["input_smoothing"] = _mutate_float(float(parent.get("input_smoothing", 0.72)), 0.45, 0.90, 0.09)
	genome["high_bank_roll_damping"] = _mutate_float(float(parent.get("high_bank_roll_damping", 0.55)), 0.30, 0.95, 0.13)
	genome["high_bank_yaw_scale"] = _mutate_float(float(parent.get("high_bank_yaw_scale", 0.55)), 0.15, 0.95, 0.16)
	genome["vs_gain"] = _mutate_float(float(parent.get("vs_gain", 0.058)), 0.035, 0.095, 0.014)
	genome["auto_rudder_strength"] = _mutate_float(float(parent.get("auto_rudder_strength", 0.28)), 0.0, 0.75, 0.16)
	genome["sideslip_gain"] = _mutate_float(float(parent.get("sideslip_gain", 0.80)), 0.20, 1.60, 0.28)
	genome["route_recovery_start_m"] = _mutate_float(float(parent.get("route_recovery_start_m", 180.0)), 80.0, 420.0, 70.0)
	genome["route_recovery_full_m"] = _mutate_float(float(parent.get("route_recovery_full_m", 720.0)), 420.0, 1200.0, 150.0)
	if float(genome["route_recovery_full_m"]) < float(genome["route_recovery_start_m"]) + 120.0:
		genome["route_recovery_full_m"] = float(genome["route_recovery_start_m"]) + 120.0
	genome["route_recovery_lookahead_scale"] = _mutate_float(float(parent.get("route_recovery_lookahead_scale", 0.24)), 0.12, 0.65, 0.10)
	genome["route_recovery_speed_cut_mps"] = _mutate_float(float(parent.get("route_recovery_speed_cut_mps", 18.0)), 4.0, 32.0, 6.0)
	genome["route_projection_advance_max_xtrack_m"] = _mutate_float(float(parent.get("route_projection_advance_max_xtrack_m", 460.0)), 220.0, 820.0, 120.0)
	genome["route_projection_blend"] = _mutate_float(float(parent.get("route_projection_blend", 0.72)), 0.45, 0.95, 0.12)
	genome["route_projection_gain"] = _mutate_float(float(parent.get("route_projection_gain", 1.55)), 0.80, 2.60, 0.35)
	genome["route_capture_radius_scale"] = _mutate_float(float(parent.get("route_capture_radius_scale", 1.0)), 0.55, 1.80, 0.25)
	genome["route_capture_max_angle_deg"] = _mutate_float(float(parent.get("route_capture_max_angle_deg", 45.0)), 25.0, 60.0, 8.0)
	genome["route_capture_max_blend"] = _mutate_float(float(parent.get("route_capture_max_blend", 0.90)), 0.65, 1.0, 0.08)
	genome["route_capture_max_blend"] = maxf(float(genome["route_capture_max_blend"]), float(genome["route_projection_blend"]))
	genome["route_fpv_yaw_blend"] = _mutate_float(float(parent.get("route_fpv_yaw_blend", 0.55)), 0.0, 1.0, 0.20)
	genome["route_flyby_start_fraction"] = _mutate_float(float(parent.get("route_flyby_start_fraction", 1.0)), 0.55, 1.50, 0.25)
	genome["route_flyby_lookahead_fraction"] = _mutate_float(float(parent.get("route_flyby_lookahead_fraction", 0.55)), 0.25, 0.90, 0.15)
	genome["route_turn_tangent_fraction"] = _mutate_float(float(parent.get("route_turn_tangent_fraction", 0.62)), 0.35, 0.85, 0.12)
	genome["route_curvature_feedforward_gain"] = _mutate_float(float(parent.get("route_curvature_feedforward_gain", 1.0)), 0.0, 1.60, 0.35)
	genome["navigation_bank_gain"] = _mutate_float(float(parent.get("navigation_bank_gain", 1.5)), 0.90, 2.40, 0.30)
	genome["navigation_roll_p_gain"] = _mutate_float(float(parent.get("navigation_roll_p_gain", 11.0)), 6.0, 16.0, 2.0)
	genome["navigation_roll_high_bank_p_gain"] = _mutate_float(float(parent.get("navigation_roll_high_bank_p_gain", 4.5)), 2.5, 8.0, 1.2)
	genome["navigation_roll_high_bank_p_gain"] = minf(float(genome["navigation_roll_high_bank_p_gain"]), float(genome["navigation_roll_p_gain"]))
	genome["navigation_roll_rate_damping"] = _mutate_float(float(parent.get("navigation_roll_rate_damping", 0.30)), 0.12, 0.65, 0.12)
	genome["navigation_roll_min_input"] = _mutate_float(float(parent.get("navigation_roll_min_input", 0.45)), 0.15, 0.65, 0.12)
	genome["pitch_altitude_trim"] = _mutate_float(float(parent.get("pitch_altitude_trim", 0.08)), 0.02, 0.18, 0.035)
	genome["above_path_unload_start_m"] = _mutate_float(float(parent.get("above_path_unload_start_m", 80.0)), 30.0, 220.0, 40.0)
	genome["above_path_unload_full_m"] = _mutate_float(float(parent.get("above_path_unload_full_m", 360.0)), 180.0, 720.0, 110.0)
	if float(genome["above_path_unload_full_m"]) < float(genome["above_path_unload_start_m"]) + 80.0:
		genome["above_path_unload_full_m"] = float(genome["above_path_unload_start_m"]) + 80.0
	genome["above_path_unload_pitch"] = _mutate_float(float(parent.get("above_path_unload_pitch", 0.42)), 0.10, 0.72, 0.12)
	genome["turn_pull_pitch_input"] = _mutate_float(float(parent.get("turn_pull_pitch_input", 0.08)), 0.0, 0.20, 0.09)
	genome["fpv_pitch_gain"] = _mutate_float(float(parent.get("fpv_pitch_gain", 1.35)), 0.70, 3.20, 1.0)
	genome["fpv_pitch_damping"] = _mutate_float(float(parent.get("fpv_pitch_damping", 0.20)), 0.04, 0.55, 0.20)
	genome["fpv_pitch_limit"] = _mutate_float(float(parent.get("fpv_pitch_limit", 0.46)), 0.24, 0.72, 0.20)
	genome["attack_route_lookahead_fraction"] = _mutate_float(float(parent.get("attack_route_lookahead_fraction", 0.35)), 0.18, 0.65, 0.10)
	genome["attack_route_capture_scale"] = _mutate_float(float(parent.get("attack_route_capture_scale", 1.0)), 0.65, 1.60, 0.20)
	genome["attack_route_projection_blend"] = _mutate_float(float(parent.get("attack_route_projection_blend", 0.72)), 0.35, 0.90, 0.12)
	genome["attack_route_projection_gain"] = _mutate_float(float(parent.get("attack_route_projection_gain", 1.55)), 0.90, 2.80, 0.35)
	genome["attack_route_bank_limit_deg"] = _mutate_float(float(parent.get("attack_route_bank_limit_deg", 75.0)), 55.0, 80.0, 6.0)
	genome["rocket_ccip_pitch_gain"] = _mutate_float(float(parent.get("rocket_ccip_pitch_gain", -0.55)), -1.40, 1.40, 0.28)
	genome["rocket_ccip_yaw_gain"] = _mutate_float(float(parent.get("rocket_ccip_yaw_gain", 0.55)), -1.40, 1.40, 0.28)
	genome["rocket_ccip_pitch_damp"] = _mutate_float(float(parent.get("rocket_ccip_pitch_damp", 0.14)), 0.0, 0.42, 0.08)
	genome["rocket_ccip_yaw_damp"] = _mutate_float(float(parent.get("rocket_ccip_yaw_damp", 0.12)), 0.0, 0.42, 0.08)
	genome["rocket_ccip_max_pitch"] = _mutate_float(float(parent.get("rocket_ccip_max_pitch", 0.22)), 0.04, 0.42, 0.07)
	genome["rocket_ccip_max_yaw"] = _mutate_float(float(parent.get("rocket_ccip_max_yaw", 0.18)), 0.02, 0.36, 0.06)
	genome["rocket_ccip_smooth"] = _mutate_float(float(parent.get("rocket_ccip_smooth", 0.35)), 0.08, 0.80, 0.12)
	_apply_mixed_navigation_baseline(genome)
	return genome

func _mutate_float(value: float, min_value: float, max_value: float, sigma: float) -> float:
	var mutation_scale: float = maxf(genetic_mutation_sigma, 0.0)
	var mutated: float = value + _rng.randfn(0.0, sigma * mutation_scale)
	return clampf(mutated, min_value, max_value)

func _get_population_size() -> int:
	if deterministic_validation_enabled:
		return maxi(deterministic_validation_aircraft_count, 1)
	if genetic_tuning_enabled:
		if _attack_is_mixed_mode():
			return maxi(genetic_population_size, mixed_min_population_size)
		return maxi(genetic_population_size, 1)
	return maxi(test_aircraft_count, 1)

func _append_seed_genome(seeds: Array[Dictionary], genome: Dictionary) -> void:
	if genome.is_empty():
		return
	var genome_id: int = int(genome.get("id", -1))
	for existing: Dictionary in seeds:
		if genome_id >= 0 and int(existing.get("id", -2)) == genome_id:
			return
	seeds.append(genome.duplicate(true))

func _spawn_due_trials() -> void:
	if _pending_spawn_index >= _population_genomes.size():
		return
	if _elapsed_s + 0.001 < _next_spawn_time_s:
		return
	var genome: Dictionary = _population_genomes[_pending_spawn_index]
	_spawn_trial(_pending_spawn_index, genome)
	_pending_spawn_index += 1
	_next_spawn_time_s = _elapsed_s + maxf(spawn_interval_s, 0.0)

func _maybe_start_attack_phase() -> void:
	if not attack_phase_enabled or _attack_phase_started:
		return
	var start_delay_s: float = terminal_attack_regression_start_s if terminal_attack_regression_enabled else attack_phase_start_s
	if _elapsed_s - _generation_start_s < maxf(start_delay_s, 0.0):
		return
	if _trials.is_empty():
		return
	if _targets.is_empty():
		_spawn_attack_targets()
	_attack_phase_started = true
	if terminal_attack_regression_enabled:
		for trial_index in range(_trials.size()):
			var terminal_trial: Dictionary = _trials[trial_index]
			if bool(terminal_trial.get("crashed", false)) or bool(terminal_trial.get("destroyed", false)):
				continue
			var terminal_aircraft: RigidBody3D = _get_trial_aircraft(terminal_trial)
			var terminal_pilot: AIPilot = _get_trial_pilot(terminal_trial)
			if terminal_aircraft == null or terminal_pilot == null:
				continue
			_start_trial_attack(trial_index, terminal_trial, terminal_aircraft, terminal_pilot)
		_log_event("ATTACK_PHASE_ARMED generation=%d t=%.1f targets=%d primary=%s mode=terminal_regression" % [
			_generation_index,
			_elapsed_s,
			_targets.size(),
			_fmt_v3(_target.global_position) if _target != null and is_instance_valid(_target) else "(none)",
		])
		return
	for i in range(_trials.size()):
		var trial: Dictionary = _trials[i]
		var progress_units: float = float(trial.get("route_progress_units", 0.0))
		_schedule_next_attack_from_progress(trial, progress_units, false)
		_trials[i] = trial
	_log_event("ATTACK_PHASE_ARMED generation=%d t=%.1f targets=%d primary=%s attack_wp=%d" % [
		_generation_index,
		_elapsed_s,
		_targets.size(),
		_fmt_v3(_target.global_position) if _target != null and is_instance_valid(_target) else "(none)",
		_get_attack_waypoint_index(),
	])

func _start_attack_phase() -> void:
	_spawn_attack_targets()
	if _targets.is_empty():
		_log_event("ATTACK_PHASE_FAILED generation=%d t=%.1f reason=no_target" % [
			_generation_index,
			_elapsed_s,
		])
		return
	_attack_phase_started = true
	var activated: int = 0
	for i in range(_trials.size()):
		var trial: Dictionary = _trials[i]
		if bool(trial.get("crashed", false)) or bool(trial.get("destroyed", false)):
			continue
		var aircraft: RigidBody3D = _get_trial_aircraft(trial)
		var pilot: AIPilot = _get_trial_pilot(trial)
		if aircraft == null or pilot == null:
			continue
		var weapon_mode: String = _get_weapon_mode_for_cycle(int(trial.get("attack_cycle_count", 0)))
		_configure_aircraft_for_attack_weapon(aircraft, weapon_mode)
		_configure_pilot_for_attack_weapon(pilot, weapon_mode)
		var attack_target: Node3D = _choose_attack_target_for_trial(trial)
		trial["current_attack_target"] = attack_target
		trial["current_weapon_mode"] = weapon_mode
		_configure_attack_tuning_context(aircraft, int(trial.get("id", -1)), attack_target, weapon_mode)
		pilot.ground_attack_enabled = true
		pilot.dogfight_enabled = false
		pilot.set_target(attack_target)
		trial["attack_started"] = true
		trial["attack_start_time_s"] = _elapsed_s
		_trials[i] = trial
		activated += 1
	_log_event("ATTACK_PHASE_START generation=%d t=%.1f activated=%d targets=%d primary=%s" % [
		_generation_index,
		_elapsed_s,
		activated,
		_targets.size(),
		_fmt_v3(_target.global_position),
	])

func _update_attack_cycle_supervisor() -> void:
	if not attack_phase_enabled or not _attack_phase_started:
		return
	for i in range(_trials.size()):
		var trial: Dictionary = _trials[i]
		if bool(trial.get("crashed", false)) or bool(trial.get("destroyed", false)):
			continue
		var aircraft: RigidBody3D = _get_trial_aircraft(trial)
		var pilot: AIPilot = _get_trial_pilot(trial)
		if aircraft == null or pilot == null:
			continue
		if bool(trial.get("attack_active", false)):
			var attack_age_s: float = _elapsed_s - float(trial.get("attack_start_time_s", _elapsed_s))
			_sample_attack_mind_if_due(i, trial, aircraft, pilot, attack_age_s)
			trial = _trials[i]
			var run_budget_s: float = maxf(mixed_attack_run_budget_s, 30.0)
			if _attack_is_mixed_mode() and attack_age_s >= run_budget_s:
				_expire_mixed_attack_run(i, trial, aircraft, pilot, attack_age_s, run_budget_s)
				continue
			if pilot.current_state == AIPilot.State.ATTACK_POSITIONING:
				var route_snapshot: Dictionary = pilot.get_flight_plan_debug_snapshot()
				var route_revision: int = int(route_snapshot.get("revision", -1))
				var watched_revision: int = int(trial.get("attack_positioning_watch_revision", -1))
				if route_revision != watched_revision:
					trial["attack_positioning_watch_revision"] = route_revision
					trial["attack_positioning_watch_start_time_s"] = _elapsed_s
					_trials[i] = trial
					_log_event("ATTACK_ROUTE_WATCH_RESET generation=%d id=%d cycle=%d t=%.1f old_rev=%d new_rev=%d run_age=%.1f" % [
						int(trial.get("generation", _generation_index)),
						int(trial.get("id", -1)),
						int(trial.get("attack_cycle_count", 0)),
						_elapsed_s,
						watched_revision,
						route_revision,
						attack_age_s,
					])
				var positioning_watch_start_s: float = float(
					trial.get("attack_positioning_watch_start_time_s", trial.get("attack_start_time_s", _elapsed_s))
				)
				var positioning_age_s: float = maxf(_elapsed_s - positioning_watch_start_s, 0.0)
				var positioning_timeout_s: float = maxf(
					pilot.get_attack_positioning_route_timeout_s() + maxf(attack_positioning_supervisor_grace_s, 0.0),
					60.0
				)
				if positioning_age_s >= positioning_timeout_s:
					_retry_stalled_attack(
						i, trial, aircraft, pilot, attack_age_s, positioning_age_s, positioning_timeout_s
					)
					continue
			if pilot.current_state == AIPilot.State.SEARCH:
				_restore_trial_to_circuit(i, trial, aircraft, pilot, "egress_complete")
			continue
		var max_cycles: int = maxi(attack_cycles_per_trial, 0)
		if max_cycles > 0 and int(trial.get("attack_cycle_count", 0)) >= max_cycles:
			continue
		if pilot.current_state != AIPilot.State.SEARCH:
			continue
		var force_time_s: float = float(trial.get("next_attack_force_time_s", INF))
		if _attack_is_mixed_mode() and is_finite(force_time_s) and _elapsed_s >= force_time_s:
			_log_event("ATTACK_PHASE_ADVANCE generation=%d id=%d next_cycle=%d t=%.1f waited=%.1f" % [
				int(trial.get("generation", _generation_index)),
				int(trial.get("id", -1)),
				int(trial.get("attack_cycle_count", 0)) + 1,
				_elapsed_s,
				maxf(_elapsed_s - force_time_s + maxf(mixed_attack_interphase_delay_s, 0.0), 0.0),
			])
			_start_trial_attack(i, trial, aircraft, pilot)
			continue
		var route_progress_units: float = float(trial.get("route_progress_units", 0.0))
		var next_attack_progress_units: float = float(trial.get("next_attack_progress_units", _get_attack_waypoint_index()))
		if route_progress_units + 0.001 >= next_attack_progress_units:
			_start_trial_attack(i, trial, aircraft, pilot)

func _sample_attack_mind_if_due(
		trial_index: int,
		trial: Dictionary,
		aircraft: RigidBody3D,
		pilot: AIPilot,
		attack_age_s: float
) -> void:
	var sample_index: int = int(trial.get("attack_mind_sample_index", 0))
	while sample_index < attack_mind_sample_ages_s.size() \
			and attack_age_s >= maxf(attack_mind_sample_ages_s[sample_index], 0.0):
		_log_attack_mind(trial, aircraft, pilot, "age_%.0f" % attack_mind_sample_ages_s[sample_index])
		sample_index += 1
	trial["attack_mind_sample_index"] = sample_index
	_trials[trial_index] = trial

func _log_attack_mind(
		trial: Dictionary,
		aircraft: RigidBody3D,
		pilot: AIPilot,
		checkpoint: String
) -> void:
	if aircraft == null or pilot == null or not is_instance_valid(aircraft) or not is_instance_valid(pilot):
		return
	var state_index: int = pilot.current_state
	var state_name: String = str(AIPilot.State.keys()[state_index]) if state_index >= 0 and state_index < AIPilot.State.size() else str(state_index)
	var goal: String = "hold"
	match pilot.current_state:
		AIPilot.State.ATTACK_POSITIONING:
			goal = "reach_setup_and_align"
		AIPilot.State.ATTACK_INBOUND:
			goal = "stabilize_inbound"
		AIPilot.State.ATTACK_DIVE:
			goal = "place_ccip_and_fire"
		AIPilot.State.ATTACK_BREAK_OFF:
			goal = "terrain_safe_egress"
		AIPilot.State.SEARCH:
			goal = "rejoin_circuit"
	var target: Node3D = trial.get("current_attack_target", null) as Node3D
	var target_distance_m: float = aircraft.global_position.distance_to(target.global_position) if target != null and is_instance_valid(target) else INF
	var target_bearing_deg: float = INF
	if target != null and is_instance_valid(target):
		var to_target: Vector3 = target.global_position - aircraft.global_position
		var forward: Vector3 = aircraft.global_transform.basis.z
		var flat_forward: Vector2 = Vector2(forward.x, forward.z).normalized()
		var flat_target: Vector2 = Vector2(to_target.x, to_target.z).normalized()
		if flat_forward.length_squared() > 0.0 and flat_target.length_squared() > 0.0:
			target_bearing_deg = rad_to_deg(flat_forward.angle_to(flat_target))
	var route_debug: Dictionary = pilot.get_route_follow_debug_snapshot()
	var ccip_miss_m: float = INF
	var ccip_right_m: float = INF
	var ccip_forward_m: float = INF
	var ccip_blocked: bool = false
	var ccip_block_reason: String = ""
	var weapon_mode: String = _get_trial_weapon_mode(trial)
	if weapon_mode == "Rockets":
		ccip_miss_m = pilot.get_rocket_ccip_aim_miss_m()
		ccip_right_m = pilot.get_rocket_ccip_aim_local_right_m()
		ccip_forward_m = pilot.get_rocket_ccip_aim_local_forward_m()
		ccip_blocked = pilot.is_rocket_ccip_blocked()
		ccip_block_reason = pilot.get_rocket_ccip_block_reason()
	elif weapon_mode == "Guns":
		ccip_miss_m = pilot.get_gun_ccip_aim_miss_m()
		ccip_right_m = pilot.get_gun_ccip_aim_local_right_m()
		ccip_forward_m = pilot.get_gun_ccip_aim_local_forward_m()
		ccip_block_reason = pilot.get_gun_ccip_block_reason()
		ccip_blocked = not ccip_block_reason.is_empty()
	else:
		var cached_impact: Variant = pilot.get("_ccip_cached_result")
		if cached_impact is Vector3 and target != null and is_instance_valid(target) and cached_impact != Vector3.ZERO:
			ccip_miss_m = (cached_impact as Vector3).distance_to(target.global_position)
		ccip_blocked = bool(pilot.get("_ccip_cached_blocked"))
		ccip_block_reason = str(pilot.get("_ccip_cached_block_reason"))
	_log_event("ATTACK_MIND generation=%d id=%d cycle=%d checkpoint=%s age=%.1f weapon=%s state=%s goal=%s commit=%s end=%s route=%s:%d/%d retry=%d route_decision=%s dist_wp=%.0f target_dist=%.0f target_bearing=%.1f speed=%.1f vspd=%.1f agl=%.1f bank=%.1f pitch=%.1f throttle=%.2f controls=(%.2f,%.2f,%.2f) ccip_miss=%.1f ccip_right=%.1f ccip_forward=%.1f ccip_blocked=%s ccip_reason=%s" % [
		int(trial.get("generation", _generation_index)), int(trial.get("id", -1)), int(trial.get("attack_cycle_count", 0)),
		checkpoint, _elapsed_s - float(trial.get("attack_start_time_s", _elapsed_s)), weapon_mode, state_name, goal,
		pilot.get_attack_last_commit_reason(), pilot.get_attack_last_end_reason(), str(route_debug.get("role", "")),
		int(route_debug.get("index", -1)) + 1, int(route_debug.get("count", pilot.waypoints.size())), int(pilot.get("_attack_lineup_retry_count")), str(route_debug.get("decision", "")),
		float(route_debug.get("distance_m", aircraft.global_position.distance_to(pilot.nav_waypoint))), target_distance_m, target_bearing_deg,
		aircraft.linear_velocity.length(), aircraft.linear_velocity.y, pilot.altitude_agl,
		rad_to_deg(aircraft.global_transform.basis.get_euler().z), rad_to_deg(aircraft.global_transform.basis.get_euler().x),
		float(pilot.get("throttle_input")), float(pilot.get("roll_input")), float(pilot.get("pitch_input")), float(pilot.get("yaw_input")),
		ccip_miss_m, ccip_right_m, ccip_forward_m, str(ccip_blocked), ccip_block_reason,
	])

func _retry_stalled_attack(
		trial_index: int,
		trial: Dictionary,
		aircraft: RigidBody3D,
		pilot: AIPilot,
		attack_age_s: float,
		positioning_age_s: float,
		positioning_timeout_s: float
) -> void:
	trial["attack_stalled_runs"] = int(trial.get("attack_stalled_runs", 0)) + 1
	_log_event("ATTACK_RUN_STALLED generation=%d id=%d cycle=%d t=%.1f run_age=%.1f route_age=%.1f timeout=%.1f commit_reason=%s" % [
		int(trial.get("generation", _generation_index)),
		int(trial.get("id", -1)),
		int(trial.get("attack_cycle_count", 0)),
		_elapsed_s,
		attack_age_s,
		positioning_age_s,
		positioning_timeout_s,
		pilot.get_attack_last_commit_reason(),
	])
	_restore_trial_to_circuit(trial_index, trial, aircraft, pilot, "positioning_timeout")
	if not attack_positioning_retry_immediately or _attack_is_mixed_mode():
		return
	var refreshed_trial: Dictionary = _trials[trial_index]
	var max_cycles: int = maxi(attack_cycles_per_trial, 0)
	if max_cycles > 0 and int(refreshed_trial.get("attack_cycle_count", 0)) >= max_cycles:
		return
	_start_trial_attack(trial_index, refreshed_trial, aircraft, pilot)

func _expire_mixed_attack_run(
		trial_index: int,
		trial: Dictionary,
		aircraft: RigidBody3D,
		pilot: AIPilot,
		attack_age_s: float,
		run_budget_s: float
) -> void:
	trial["attack_stalled_runs"] = int(trial.get("attack_stalled_runs", 0)) + 1
	_log_event("ATTACK_RUN_BUDGET_EXPIRED generation=%d id=%d cycle=%d weapon=%s t=%.1f age=%.1f budget=%.1f state=%s commit_reason=%s end_reason=%s" % [
		int(trial.get("generation", _generation_index)),
		int(trial.get("id", -1)),
		int(trial.get("attack_cycle_count", 0)),
		_get_trial_weapon_mode(trial),
		_elapsed_s,
		attack_age_s,
		run_budget_s,
		str(AIPilot.State.keys()[pilot.current_state]),
		pilot.get_attack_last_commit_reason(),
		pilot.get_attack_last_end_reason(),
	])
	_restore_trial_to_circuit(trial_index, trial, aircraft, pilot, "run_budget_expired")

func _start_trial_attack(trial_index: int, trial: Dictionary, aircraft: RigidBody3D, pilot: AIPilot) -> void:
	if _targets.is_empty():
		_spawn_attack_targets()
	if _targets.is_empty():
		return
	var attack_target: Node3D = _choose_attack_target_for_trial(trial)
	var weapon_mode: String = _get_weapon_mode_for_cycle(int(trial.get("attack_cycle_count", 0)))
	_configure_aircraft_for_attack_weapon(aircraft, weapon_mode)
	_configure_pilot_for_attack_weapon(pilot, weapon_mode)
	trial["current_attack_target"] = attack_target
	trial["current_weapon_mode"] = weapon_mode
	_configure_attack_tuning_context(aircraft, int(trial.get("id", -1)), attack_target, weapon_mode)
	pilot.ground_attack_enabled = true
	pilot.dogfight_enabled = false
	if terminal_attack_regression_enabled:
		_position_terminal_attack_trial(aircraft, pilot, attack_target, weapon_mode)
	pilot.set_target(attack_target)
	trial["attack_active"] = true
	trial["attack_started"] = true
	trial["attack_start_time_s"] = _elapsed_s
	var attack_route_snapshot: Dictionary = pilot.get_flight_plan_debug_snapshot()
	trial["attack_positioning_watch_revision"] = int(attack_route_snapshot.get("revision", -1))
	trial["attack_positioning_watch_start_time_s"] = _elapsed_s
	trial["attack_start_rocket_launches"] = int(trial.get("rocket_launches", 0))
	trial["attack_start_bomb_drops"] = int(trial.get("bomb_drops", 0))
	trial["attack_start_gun_shots"] = int(trial.get("gun_shots", 0))
	trial["attack_start_commit_count"] = pilot.get_attack_commit_count()
	trial["attack_mind_sample_index"] = 0
	trial["next_attack_force_time_s"] = INF
	trial["attack_cycle_count"] = int(trial.get("attack_cycle_count", 0)) + 1
	_trials[trial_index] = trial
	_log_event("ATTACK_RUN_START generation=%d id=%d cycle=%d weapon=%s t=%.1f target=%s" % [
		int(trial.get("generation", _generation_index)),
		int(trial.get("id", -1)),
		int(trial.get("attack_cycle_count", 0)),
		weapon_mode,
		_elapsed_s,
		_fmt_v3(attack_target.global_position),
	])

func _position_terminal_attack_trial(aircraft: RigidBody3D, pilot: AIPilot, target: Node3D, weapon_mode: String) -> void:
	if aircraft == null or pilot == null or target == null:
		return
	var ingress_range_m: float = pilot.attack_run_distance_m
	var altitude_offset_m: float = pilot.attack_run_altitude_offset_m
	if weapon_mode == "Bombs":
		ingress_range_m = pilot.bomb_run_setup_distance_m
		altitude_offset_m = pilot.bomb_run_setup_altitude_offset_m
	elif weapon_mode == "Rockets":
		ingress_range_m = pilot.rocket_run_setup_distance_m
		altitude_offset_m = pilot.rocket_run_altitude_offset_m
	ingress_range_m = maxf(ingress_range_m, 600.0)

	var target_pos: Vector3 = target.global_position
	var best_forward: Vector3 = Vector3.FORWARD
	var best_ingress: Vector3 = target_pos - best_forward * ingress_range_m
	var best_altitude_m: float = target_pos.y + maxf(altitude_offset_m, 120.0)
	var best_score: float = INF
	var direction_count: int = maxi(terminal_attack_corridor_directions, 4)
	for direction_index in range(direction_count):
		var angle_rad: float = TAU * float(direction_index) / float(direction_count)
		var forward: Vector3 = Vector3(cos(angle_rad), 0.0, sin(angle_rad)).normalized()
		var ingress_pos: Vector3 = target_pos - forward * ingress_range_m
		var egress_pos: Vector3 = target_pos + forward * maxf(pilot.attack_egress_distance_m, 1000.0)
		var terrain_max_m: float = maxf(
			_sample_terminal_corridor_max_height(ingress_pos, target_pos),
			_sample_terminal_corridor_max_height(target_pos, egress_pos)
		)
		var required_altitude_m: float = target_pos.y + maxf(altitude_offset_m, 120.0)
		if is_finite(terrain_max_m):
			required_altitude_m = maxf(required_altitude_m, terrain_max_m + maxf(terminal_attack_corridor_clearance_m, 80.0))
		var score: float = required_altitude_m - target_pos.y
		if score < best_score:
			best_score = score
			best_forward = forward
			best_ingress = ingress_pos
			best_altitude_m = required_altitude_m

	best_ingress.y = best_altitude_m
	aircraft.global_transform = Transform3D(_basis_with_project_forward(best_forward), best_ingress)
	aircraft.linear_velocity = best_forward * 115.0
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.freeze = false
	aircraft.sleeping = false
	# Aggressive commit gates: wider entry range, a broader heading cone, and no settle wait so
	# pilots attack from the approach instead of circling to line up a picture-perfect run.
	pilot.attack_positioning_direct_entry_after_s = 0.0
	pilot.attack_positioning_direct_entry_range_buffer_m = 500.0
	pilot.attack_positioning_direct_entry_min_dot = 0.7
	pilot.attack_positioning_direct_entry_min_planned_dot = 0.75
	pilot.attack_positioning_direct_entry_max_cross_track_m = 550.0
	_log_event("TERMINAL_ATTACK_SETUP weapon=%s ingress=%s target=%s forward=%s range=%.1f altitude_offset=%.1f" % [
		weapon_mode,
		_fmt_v3(best_ingress),
		_fmt_v3(target_pos),
		_fmt_v3(best_forward),
		ingress_range_m,
		best_altitude_m - target_pos.y,
	])

func _sample_terminal_corridor_max_height(from_pos: Vector3, to_pos: Vector3) -> float:
	var max_height_m: float = -INF
	var sample_count: int = maxi(terminal_attack_corridor_samples, 2)
	for sample_index in range(sample_count + 1):
		var t: float = float(sample_index) / float(sample_count)
		var ground_height_m: float = _sample_ground_height(from_pos.lerp(to_pos, t))
		if not is_nan(ground_height_m):
			max_height_m = maxf(max_height_m, ground_height_m)
	return max_height_m

func _restore_trial_to_circuit(
		trial_index: int,
		trial: Dictionary,
		aircraft: RigidBody3D,
		pilot: AIPilot,
		reason: String
) -> void:
	_log_attack_mind(trial, aircraft, pilot, "exit")
	var route: Array[Dictionary] = _get_trial_route(trial)
	if route.is_empty():
		return
	var weapon_mode: String = _get_trial_weapon_mode(trial)
	var ordnance_used: int = 0
	if weapon_mode == "Bombs":
		ordnance_used = int(trial.get("bomb_drops", 0)) - int(trial.get("attack_start_bomb_drops", 0))
	elif weapon_mode == "Rockets":
		ordnance_used = int(trial.get("rocket_launches", 0)) - int(trial.get("attack_start_rocket_launches", 0))
	else:
		ordnance_used = int(trial.get("gun_shots", 0)) - int(trial.get("attack_start_gun_shots", 0))
	ordnance_used = maxi(ordnance_used, 0)
	var commit_delta: int = maxi(
		pilot.get_attack_commit_count() - int(trial.get("attack_start_commit_count", 0)),
		0
	)
	var committed: bool = commit_delta > 0
	if committed:
		trial["committed_attack_runs"] = int(trial.get("committed_attack_runs", 0)) + 1
	if ordnance_used <= 0:
		trial["dry_attack_runs"] = int(trial.get("dry_attack_runs", 0)) + 1
	var commit_reason: String = pilot.get_attack_last_commit_reason()
	var end_reason: String = pilot.get_attack_last_end_reason()
	trial["attack_lineup_retries"] = int(trial.get("attack_lineup_retries", 0)) \
		+ int(pilot.get("_attack_lineup_retry_count"))
	if end_reason.contains("terrain") or reason.contains("terrain"):
		trial["attack_terrain_emergency_runs"] = int(trial.get("attack_terrain_emergency_runs", 0)) + 1
	_log_event("ATTACK_RUN_OUTCOME generation=%d id=%d cycle=%d weapon=%s committed=%s ordnance=%d fired=%s commit_reason=%s end_reason=%s harness_reason=%s" % [
		int(trial.get("generation", _generation_index)),
		int(trial.get("id", -1)),
		int(trial.get("attack_cycle_count", 0)),
		weapon_mode,
		str(committed),
		ordnance_used,
		str(ordnance_used > 0),
		commit_reason,
		end_reason,
		reason,
	])
	pilot.ground_attack_enabled = false
	_configure_pilot_for_attack_weapon(pilot, "")
	pilot.set("combat_target", null)
	pilot.set_flight_plan_legs("airplane_test_circuit", route, false, true)
	var local_circuit_progress: float = _measure_route_progress_units_for_position(route, aircraft.global_position)
	var route_size: int = route.size()
	var previous_lap: int = int(trial.get("completed_laps", 0))
	var previous_progress: float = float(trial.get("route_progress_units", 0.0))
	var progress_lap: int = int(floor(previous_progress / float(route_size))) if route_size > 0 else previous_lap
	var current_lap: int = maxi(previous_lap, progress_lap)
	var circuit_progress: float = float(current_lap * route_size) + fposmod(local_circuit_progress, float(route_size))
	var waypoint_index: int = clampi(int(floor(local_circuit_progress)) + 1, 0, maxi(pilot.waypoints.size() - 1, 0))
	pilot.current_waypoint_index = waypoint_index
	if not pilot.waypoints.is_empty():
		pilot.nav_waypoint = pilot.waypoints[pilot.current_waypoint_index]
	pilot.change_state(AIPilot.State.SEARCH)
	trial["attack_active"] = false
	trial["route_sync_pending"] = false
	trial["completed_laps"] = current_lap
	trial["last_waypoint_index"] = waypoint_index
	trial["route_progress_units"] = circuit_progress
	_schedule_next_attack_from_progress(trial, circuit_progress, true)
	trial["next_attack_force_time_s"] = INF
	var max_cycles: int = maxi(attack_cycles_per_trial, 0)
	if _attack_is_mixed_mode() and int(trial.get("attack_cycle_count", 0)) < max_cycles:
		trial["next_attack_force_time_s"] = _elapsed_s + maxf(mixed_attack_interphase_delay_s, 0.0)
	_trials[trial_index] = trial
	_log_event("ATTACK_RUN_END generation=%d id=%d cycle=%d weapon=%s t=%.1f reason=%s next_attack_progress=%.2f" % [
		int(trial.get("generation", _generation_index)),
		int(trial.get("id", -1)),
		int(trial.get("attack_cycle_count", 0)),
		weapon_mode,
		_elapsed_s,
		reason,
		float(trial.get("next_attack_progress_units", 0.0)),
	])

func _spawn_trial(slot_index: int, genome: Dictionary) -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = self
	var instance: Node = AIRCRAFT_SCENE.instantiate()
	var aircraft: RigidBody3D = instance as RigidBody3D
	if aircraft == null:
		push_error("[AirplaneTest] Aircraft_5 scene did not instantiate as RigidBody3D")
		return
	var trial_id: int = _next_trial_id
	_next_trial_id += 1
	aircraft.name = "Aircraft_5_G%d_T%d" % [_generation_index, trial_id]
	if "team" in aircraft:
		aircraft.set("team", 1)
	aircraft.add_to_group("friendlies")
	aircraft.add_to_group("aircraft")
	aircraft.remove_from_group("enemies")
	root.add_child(aircraft)

	var route: Array[Dictionary] = _build_trial_route(genome)
	_place_trial_aircraft(aircraft, route, slot_index, genome)
	if aircraft.has_signal("crashed"):
		aircraft.crashed.connect(_on_trial_aircraft_crashed.bind(trial_id))
	if aircraft.has_signal("destroyed"):
		aircraft.destroyed.connect(_on_trial_aircraft_destroyed.bind(trial_id))

	var pilot: AIPilot = _configure_test_aircraft(aircraft, genome)
	if pilot != null:
		pilot.set_meta("commanding_officer_briefing", PILOT_DRESSING_DOWN)
		pilot.set_flight_plan_legs("airplane_test_circuit", route, false, true)
		pilot.current_waypoint_index = 0
		pilot.change_state(AIPilot.State.SEARCH)
	if stow_landing_gear_on_start:
		_stow_test_landing_gear(aircraft)
		_stow_test_landing_gear_after_ready(aircraft)

	var trial: Dictionary = {
		"id": trial_id,
		"slot": slot_index,
		"generation": _generation_index,
		"aircraft": aircraft,
		"pilot": pilot,
		"route": route,
		"genome": genome.duplicate(true),
		"spawn_time_s": _elapsed_s,
		"route_sync_pending": false,
		"last_waypoint_index": -1,
		"completed_laps": 0,
		"lap_completed": false,
		"evaluation_complete": false,
		"evaluation_reason": "running",
		"evaluation_end_time_s": -1.0,
		"evaluation_duration_s": 0.0,
		"samples": 0,
		"sum_cross_track_m": 0.0,
		"max_cross_track_m": 0.0,
		"sum_abs_alt_error_m": 0.0,
		"sum_high_alt_error_m": 0.0,
		"max_high_alt_error_m": 0.0,
		"sum_low_alt_error_m": 0.0,
		"max_low_alt_error_m": 0.0,
		"high_alt_samples": 0,
		"low_alt_samples": 0,
		"min_agl_m": INF,
		"sum_speed_error_mps": 0.0,
		"sum_overspeed_mps": 0.0,
		"max_overspeed_mps": 0.0,
		"overspeed_samples": 0,
		"turn_limited_samples": 0,
		"sum_route_turn_brake": 0.0,
		"max_route_turn_brake": 0.0,
		"sum_abs_sideslip": 0.0,
		"max_abs_sideslip": 0.0,
		"sum_abs_yaw_input": 0.0,
		"yaw_saturated_samples": 0,
		"sum_abs_lateral_accel_g": 0.0,
		"max_abs_lateral_accel_g": 0.0,
		"previous_velocity": Vector3.INF,
		"previous_sample_time_s": NAN,
		"previous_cross_track_m": NAN,
		"sum_cross_track_delta_m": 0.0,
		"max_cross_track_delta_m": 0.0,
		"sum_path_error_m": 0.0,
		"navigation_capture_first_time_s": INF,
		"navigation_capture_settled_time_s": INF,
		"navigation_capture_consecutive_samples": 0,
		"navigation_capture_corridor_samples": 0,
		"navigation_pre_capture_error_area": 0.0,
		"navigation_settled_samples": 0,
		"navigation_settled_sum_path_error_m": 0.0,
		"navigation_settled_max_path_error_m": 0.0,
		"previous_control_inputs": Vector3.INF,
		"sum_control_input_delta": 0.0,
		"max_control_input_delta": 0.0,
		"navigation_settled_sum_control_delta": 0.0,
		"navigation_settled_max_control_delta": 0.0,
		"route_projection_bad_samples": 0,
		"route_projection_advance_count": 0,
		"route_resync_count": 0,
		"route_resync_adjacent_forward_count": 0,
		"route_resync_disqualifying_count": 0,
		"last_debug_route_revision": -1,
		"last_debug_route_index": -1,
		"route_progress_units": 0.0,
		"attack_started": false,
		"attack_active": false,
		"attack_cycle_count": 0,
		"attack_start_time_s": -1.0,
		"attack_positioning_watch_revision": -1,
		"attack_positioning_watch_start_time_s": -1.0,
		"attack_start_rocket_launches": 0,
		"attack_start_bomb_drops": 0,
		"attack_start_gun_shots": 0,
		"attack_start_commit_count": 0,
		"attack_mind_sample_index": 0,
		"committed_attack_runs": 0,
		"dry_attack_runs": 0,
		"attack_stalled_runs": 0,
		"attack_lineup_retries": 0,
		"attack_terrain_emergency_runs": 0,
		"current_weapon_mode": attack_test_weapon_mode,
		"next_attack_progress_units": float(_get_attack_waypoint_index()),
		"next_attack_force_time_s": INF,
		"rocket_launches": 0,
		"rocket_tight_launches": 0,
		"rocket_after_best_launches": 0,
		"rocket_last_chance_launches": 0,
		"rocket_other_launches": 0,
		"rocket_impacts": 0,
		"rocket_hits": 0,
		"rocket_direct_hits": 0,
		"rocket_sum_miss_m": 0.0,
		"rocket_min_miss_m": INF,
		"rocket_last_miss_m": INF,
		"rocket_launch_contexts": [],
		"rocket_launch_context_by_id": {},
		"bomb_drops": 0,
		"bomb_impacts": 0,
		"bomb_hits": 0,
		"bomb_direct_hits": 0,
		"bomb_sum_miss_m": 0.0,
		"bomb_min_miss_m": INF,
		"bomb_last_miss_m": INF,
		"bomb_drop_contexts": [],
		"gun_shots": 0,
		"gun_reports": 0,
		"gun_hits": 0,
		"gun_sum_edge_miss_m": 0.0,
		"gun_min_edge_miss_m": INF,
		"gun_last_edge_miss_m": INF,
		"gun_min_center_miss_m": INF,
		"gun_aim_samples": 0,
		"gun_aim_sum_angle_deg": 0.0,
		"gun_aim_min_angle_deg": INF,
		"gun_aim_good_samples": 0,
		"gun_aim_first_good_time_s": INF,
		"gun_aim_dive_start_time_s": INF,
		"gun_aim_first_good_dive_time_s": INF,
		"rocket_ccip_samples": 0,
		"rocket_ccip_sum_miss_m": 0.0,
		"rocket_ccip_min_miss_m": INF,
		"rocket_ccip_sum_abs_right_m": 0.0,
		"rocket_ccip_sum_abs_forward_m": 0.0,
		"rocket_ccip_sum_abs_pitch_cmd": 0.0,
		"rocket_ccip_sum_abs_yaw_cmd": 0.0,
		"crashed": false,
		"destroyed": false,
	}
	_trials.append(trial)
	_log_event("TRIAL_START generation=%d id=%d slot=%d genome=%s route_points=%d spawn_t=%.1f" % [
		_generation_index,
		trial_id,
		slot_index,
		_format_genome(genome),
		route.size(),
		_elapsed_s,
	])

func _place_trial_aircraft(aircraft: RigidBody3D, route: Array[Dictionary], _slot_index: int, genome: Dictionary) -> void:
	if route.is_empty():
		return
	var start_value: Variant = route[route.size() - 1].get("position", play_area_center)
	var first_value: Variant = route[0].get("position", play_area_center + Vector3.FORWARD)
	var route_start: Vector3 = start_value as Vector3 if start_value is Vector3 else play_area_center
	var first_waypoint: Vector3 = first_value as Vector3 if first_value is Vector3 else play_area_center + Vector3.FORWARD
	var initial_forward: Vector3 = first_waypoint - route_start
	if initial_forward.length_squared() <= 0.001:
		initial_forward = Vector3(1.0, 0.0, 0.15)
	initial_forward = initial_forward.normalized()
	var speed_mps: float = float(genome.get("speed_mps", circuit_speed_mps))
	var spawn_position: Vector3 = route_start
	if not attack_phase_enabled:
		var initial_right: Vector3 = Vector3(initial_forward.z, 0.0, -initial_forward.x).normalized()
		spawn_position += initial_right * navigation_spawn_cross_track_offset_m
		spawn_position.y += navigation_spawn_altitude_offset_m
	aircraft.global_transform = Transform3D(_basis_with_project_forward(initial_forward), spawn_position)
	aircraft.linear_velocity = initial_forward * speed_mps
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.freeze = false
	aircraft.sleeping = false

func _configure_test_aircraft(aircraft: RigidBody3D, genome: Dictionary) -> AIPilot:
	if aircraft == null or not is_instance_valid(aircraft):
		return null
	var ai_toggle: Node = aircraft.get_node_or_null("AIToggle")
	if ai_toggle != null and ai_toggle.has_method("enable_ai"):
		ai_toggle.call("enable_ai")
	var removed_weapons: int = _prepare_test_aircraft_systems(aircraft)
	var pilot: AIPilot = aircraft.find_child("AIPilot", true, false) as AIPilot
	if pilot == null:
		push_error("[AirplaneTest] Aircraft_5 has no AIPilot")
		return null
	pilot.debug_enabled = false
	pilot.verbose_debug_enabled = false
	pilot.ground_attack_enabled = false
	pilot.ground_attack_reacquire_after_breakoff = false
	pilot.dogfight_enabled = false
	pilot.rtb_health_threshold = 0.0
	pilot.rtb_fuel_threshold = 0.0
	pilot.land_after_launch = false
	pilot.set("_land_after_climb", false)
	pilot.default_waypoint_speed_mps = float(genome.get("speed_mps", circuit_speed_mps))
	pilot.patrol_altitude_m = circuit_altitude_agl_m
	pilot.carrier_position = play_area_center
	pilot.sensor_range = 7000.0
	pilot.aircraft_flight_plan_capture_radius_m = float(genome.get("capture_radius_m", 260.0))
	pilot.maneuver_lookahead_distance = float(genome.get("lookahead_m", 1000.0))
	pilot.aircraft_route_lookahead_radius_fraction = float(genome.get("lookahead_radius_fraction", 0.75))
	pilot.bank_cmd_limit_deg = float(genome.get("bank_limit_deg", 72.0))
	pilot.normal_flight_pitch_smoothing = float(genome.get("pitch_smoothing", 0.32))
	pilot.pitch_input_smoothing = float(genome.get("pitch_input_smoothing", 0.42))
	pilot.input_smoothing = float(genome.get("input_smoothing", 0.62))
	pilot.high_bank_roll_damping_gain = float(genome.get("high_bank_roll_damping", 0.72))
	pilot.high_bank_yaw_scale = float(genome.get("high_bank_yaw_scale", 0.55))
	pilot.normal_flight_vs_gain = float(genome.get("vs_gain", 0.055))
	pilot.navigation_auto_rudder_strength = float(genome.get("auto_rudder_strength", navigation_auto_rudder_strength))
	pilot.navigation_auto_rudder_sideslip_gain = float(genome.get("sideslip_gain", 0.35))
	pilot.navigation_auto_rudder_enabled = pilot.navigation_auto_rudder_strength > 0.001 or pilot.navigation_auto_rudder_sideslip_gain > 0.001
	pilot.navigation_auto_rudder_zero_manual_yaw = false
	pilot.aircraft_route_cross_track_recovery_start_m = float(genome.get("route_recovery_start_m", pilot.aircraft_route_cross_track_recovery_start_m))
	pilot.aircraft_route_cross_track_recovery_full_m = float(genome.get("route_recovery_full_m", pilot.aircraft_route_cross_track_recovery_full_m))
	pilot.aircraft_route_cross_track_recovery_lookahead_scale = float(genome.get("route_recovery_lookahead_scale", pilot.aircraft_route_cross_track_recovery_lookahead_scale))
	pilot.aircraft_route_cross_track_recovery_speed_cut_mps = float(genome.get("route_recovery_speed_cut_mps", pilot.aircraft_route_cross_track_recovery_speed_cut_mps))
	pilot.aircraft_route_projection_advance_max_cross_track_m = float(genome.get("route_projection_advance_max_xtrack_m", pilot.aircraft_route_projection_advance_max_cross_track_m))
	pilot.aircraft_route_forward_projection_blend = float(genome.get("route_projection_blend", pilot.aircraft_route_forward_projection_blend))
	pilot.aircraft_route_forward_projection_gain = float(genome.get("route_projection_gain", pilot.aircraft_route_forward_projection_gain))
	pilot.aircraft_route_cross_track_capture_radius_scale = float(genome.get("route_capture_radius_scale", pilot.aircraft_route_cross_track_capture_radius_scale))
	pilot.aircraft_route_cross_track_capture_max_angle_deg = float(genome.get("route_capture_max_angle_deg", pilot.aircraft_route_cross_track_capture_max_angle_deg))
	pilot.aircraft_route_cross_track_capture_max_projection_blend = float(genome.get("route_capture_max_blend", pilot.aircraft_route_cross_track_capture_max_projection_blend))
	pilot.aircraft_route_fpv_yaw_blend = float(genome.get("route_fpv_yaw_blend", pilot.aircraft_route_fpv_yaw_blend))
	pilot.aircraft_route_flyby_start_radius_fraction = float(genome.get("route_flyby_start_fraction", pilot.aircraft_route_flyby_start_radius_fraction))
	pilot.aircraft_route_flyby_lookahead_fraction = float(genome.get("route_flyby_lookahead_fraction", pilot.aircraft_route_flyby_lookahead_fraction))
	pilot.aircraft_route_turn_tangent_fraction = float(genome.get("route_turn_tangent_fraction", pilot.aircraft_route_turn_tangent_fraction))
	pilot.aircraft_route_curvature_feedforward_gain = float(genome.get("route_curvature_feedforward_gain", pilot.aircraft_route_curvature_feedforward_gain))
	pilot.navigation_point_tracking_bank_gain = float(genome.get("navigation_bank_gain", pilot.navigation_point_tracking_bank_gain))
	pilot.navigation_roll_p_gain = float(genome.get("navigation_roll_p_gain", pilot.navigation_roll_p_gain))
	pilot.navigation_roll_high_bank_p_gain = float(genome.get("navigation_roll_high_bank_p_gain", pilot.navigation_roll_high_bank_p_gain))
	pilot.navigation_roll_rate_damping = float(genome.get("navigation_roll_rate_damping", pilot.navigation_roll_rate_damping))
	pilot.navigation_roll_min_input = float(genome.get("navigation_roll_min_input", pilot.navigation_roll_min_input))
	pilot.navigation_forward_frame_altitude_trim_limit = float(genome.get("pitch_altitude_trim", pilot.navigation_forward_frame_altitude_trim_limit))
	pilot.navigation_forward_frame_above_path_unload_start_m = float(genome.get("above_path_unload_start_m", pilot.navigation_forward_frame_above_path_unload_start_m))
	pilot.navigation_forward_frame_above_path_unload_full_m = float(genome.get("above_path_unload_full_m", pilot.navigation_forward_frame_above_path_unload_full_m))
	pilot.navigation_forward_frame_above_path_unload_pitch = float(genome.get("above_path_unload_pitch", pilot.navigation_forward_frame_above_path_unload_pitch))
	pilot.navigation_turn_backpressure_pitch_input = float(genome.get("turn_pull_pitch_input", 0.0))
	pilot.navigation_forward_frame_pitch_gain = float(genome.get("fpv_pitch_gain", pilot.navigation_forward_frame_pitch_gain))
	pilot.navigation_forward_frame_pitch_rate_damping = float(genome.get("fpv_pitch_damping", pilot.navigation_forward_frame_pitch_rate_damping))
	pilot.navigation_forward_frame_pitch_limit = float(genome.get("fpv_pitch_limit", pilot.navigation_forward_frame_pitch_limit))
	pilot.attack_route_lookahead_radius_fraction = float(genome.get("attack_route_lookahead_fraction", pilot.attack_route_lookahead_radius_fraction))
	pilot.attack_route_capture_radius_scale = float(genome.get("attack_route_capture_scale", pilot.attack_route_capture_radius_scale))
	pilot.attack_route_projection_blend = float(genome.get("attack_route_projection_blend", pilot.attack_route_projection_blend))
	pilot.attack_route_projection_gain = float(genome.get("attack_route_projection_gain", pilot.attack_route_projection_gain))
	pilot.attack_route_bank_limit_deg = float(genome.get("attack_route_bank_limit_deg", pilot.attack_route_bank_limit_deg))
	if attack_phase_enabled:
		# Circuit legs carry their own altitudes. This lower patrol floor lets attack
		# route planning honor the weapon-specific setup altitude instead of being
		# pinned to the 720 m circuit altitude.
		pilot.patrol_altitude_m = 300.0
		# Match the gun run geometry: rockets are a strafing pass, same setup distance/altitude.
		pilot.rocket_run_setup_distance_m = 1700.0
		pilot.rocket_run_altitude_offset_m = 260.0
		pilot.rocket_release_min_range_m = 200.0
		# Moderate window (was 1550m, then over-corrected to 650m). 1550m gave a rocket ~4.5s time-of-
		# flight -- a 14 m/s mover ran ~65m out of the 18m hit radius, and even static shots scattered
		# from wobble over that long flight. 800m keeps ToF ~2.3s (mover ~32m -- leadable) while
		# leaving a real firing window (200-800m) instead of the too-narrow 150-650m that starved shots.
		pilot.rocket_release_max_range_m = 800.0
		pilot.rocket_pull_up_distance_m = 180.0  # Just below the 200m min release range so the pilot fires down to 200m then pulls up. 130m let pilots press too low and crash in break-off (agl 18-25m).
		pilot.rocket_dive_aim_height_m = 0.0
		pilot.rocket_ccip_release_tolerance_m = 120.0  # Strafing-style: fire when roughly on target, not a 45m precision-bomb solution
		pilot.rocket_ccip_best_solution_max_m = 140.0
		pilot.rocket_ccip_best_miss_slack_m = 30.0
		pilot.rocket_ccip_release_after_best_worsen_m = 4.0
		pilot.rocket_ccip_release_after_best_grace_m = 18.0
		pilot.rocket_ccip_last_chance_tolerance_m = 110.0
		pilot.rocket_ccip_last_chance_range_margin_m = 180.0
		pilot.rocket_release_hold_s = 0.06
		pilot.rocket_fire_alignment_deg = 22.0
		pilot.rocket_release_max_bank_deg = 36.0
		# One trigger pull tells RocketPod to emit its six-rocket volley. The old value
		# of six requested six separate bursts and would consume all 24 rounds in one pass.
		pilot.rocket_shots_per_run = 1
		pilot.rocket_ccip_aim_overlay_enabled = true
		pilot.rocket_ccip_pitch_gain = float(genome.get("rocket_ccip_pitch_gain", pilot.rocket_ccip_pitch_gain))
		pilot.rocket_ccip_yaw_gain = float(genome.get("rocket_ccip_yaw_gain", pilot.rocket_ccip_yaw_gain))
		pilot.rocket_ccip_pitch_rate_damping = float(genome.get("rocket_ccip_pitch_damp", pilot.rocket_ccip_pitch_rate_damping))
		pilot.rocket_ccip_yaw_rate_damping = float(genome.get("rocket_ccip_yaw_damp", pilot.rocket_ccip_yaw_rate_damping))
		pilot.rocket_ccip_max_pitch_input = float(genome.get("rocket_ccip_max_pitch", pilot.rocket_ccip_max_pitch_input))
		pilot.rocket_ccip_max_yaw_input = float(genome.get("rocket_ccip_max_yaw", pilot.rocket_ccip_max_yaw_input))
		pilot.rocket_ccip_aim_smoothing = float(genome.get("rocket_ccip_smooth", pilot.rocket_ccip_aim_smoothing))
		if _attack_uses_rockets():
			# Rockets are a long-range strafing weapon (release out to ~1550m), yet the old gates
			# let them commit only inside 1420m with a tight 35deg cone and a 6s wait -- so pilots
			# burned ~100s circling on 'outside_setup_range' before committing. Open the commit
			# window wider than guns and drop the extra wait so they attack aggressively.
			pilot.attack_positioning_direct_entry_after_s = 0.0
			pilot.attack_positioning_direct_entry_range_buffer_m = 700.0
			pilot.attack_positioning_direct_entry_min_dot = 0.6
			pilot.attack_positioning_direct_entry_min_planned_dot = 0.7
			pilot.attack_positioning_direct_entry_max_cross_track_m = 400.0
		pilot.attack_egress_distance_m = 1700.0
		pilot.attack_break_off_distance_m = 700.0
		if _attack_uses_bombs():
			pilot.bomb_run_setup_distance_m = 1400.0
			pilot.bomb_run_setup_altitude_offset_m = 380.0
			pilot.bomb_run_setup_max_altitude_offset_m = 620.0
			pilot.bomb_dive_start_distance_m = 1150.0
			pilot.bomb_pull_up_distance_m = 200.0
			pilot.bomb_release_altitude_window_m = 900.0
			pilot.bomb_release_min_range_m = 220.0
			pilot.bomb_min_dive_angle_deg = 1.0
			pilot.bomb_release_max_bank_deg = 58.0
			var bomb_test_release_tolerance_m: float = maxf(bomb_hit_radius_m, attack_target_footprint_m.length() * 0.5)
			pilot.bomb_ccip_release_tolerance_m = bomb_test_release_tolerance_m
			pilot.bomb_rookie_release_tolerance_m = bomb_test_release_tolerance_m
			pilot.bomb_experienced_release_tolerance_m = bomb_test_release_tolerance_m
			pilot.bomb_veteran_release_tolerance_m = bomb_test_release_tolerance_m
			pilot.bomb_ace_release_tolerance_m = bomb_test_release_tolerance_m
			pilot.bomb_release_best_miss_slack_m = maxf(bomb_test_release_tolerance_m * 0.20, 4.0)
			pilot.bomb_release_after_best_worsen_m = maxf(bomb_test_release_tolerance_m * 0.18, 4.0)
			pilot.bomb_release_after_best_grace_m = maxf(bomb_test_release_tolerance_m * 0.45, 10.0)
			pilot.bomb_release_best_solution_tolerance_multiplier = 1.15
			pilot.bomb_rookie_release_hold_s = 0.08
			pilot.bomb_experienced_release_hold_s = 0.08
			pilot.bomb_veteran_release_hold_s = 0.08
			pilot.bomb_ace_release_hold_s = 0.08
			pilot.bomb_salvo_per_run = 2
			pilot.bomb_release_spacing_s = 0.45
			pilot.bomb_direct_entry_max_cross_track_m = 2200.0
			pilot.bomb_direct_entry_max_altitude_overshoot_m = 420.0
			pilot.attack_positioning_direct_entry_after_s = 1.0
			pilot.attack_positioning_direct_entry_range_buffer_m = 1100.0
			pilot.attack_positioning_direct_entry_min_dot = 0.20
			pilot.attack_positioning_direct_entry_min_planned_dot = 0.20
			pilot.attack_egress_distance_m = 1900.0
			pilot.attack_break_off_distance_m = 650.0
		if _attack_uses_guns():
			pilot.attack_run_distance_m = 1700.0
			pilot.attack_run_altitude_offset_m = 260.0
			pilot.attack_pull_up_distance_m = 250.0
			pilot.gun_ccip_fire_tolerance_m = 180.0
			pilot.gun_ccip_blocked_fire_tolerance_m = 22.0
			pilot.gun_attack_commit_extra_range_m = 360.0
			pilot.gun_attack_commit_min_agl_m = 90.0
			pilot.gun_attack_commit_critical_tti_s = 1.8
			pilot.attack_positioning_direct_entry_after_s = 1.0
			pilot.attack_egress_distance_m = 1700.0
			pilot.attack_break_off_distance_m = 650.0
	_apply_test_auto_rudder_to_simple_aero(pilot)
	if FlightDirector != null and FlightDirector.has_method("register_aircraft"):
		FlightDirector.register_aircraft(aircraft)
	if not _view_assigned and FlightDirector != null and FlightDirector.has_method("_view_aircraft"):
		_view_assigned = true
		FlightDirector.call_deferred("_view_aircraft", aircraft)
	_log_event("SYSTEMS aircraft=%s gear_stowed=%s stripped_weapons=%d genome=%s" % [
		aircraft.name,
		str(stow_landing_gear_on_start),
		removed_weapons,
		_format_genome(genome),
	])
	return pilot

func _prepare_test_aircraft_systems(aircraft: RigidBody3D) -> int:
	var removed_weapons: int = 0
	if strip_external_ordnance:
		removed_weapons = _strip_non_gun_weapons(aircraft)
	if attack_phase_enabled and _attack_uses_guns():
		_install_test_gun(aircraft)
	if attack_phase_enabled and _attack_uses_unlimited_ordnance():
		aircraft.set_meta("heli_test_unlimited_ammo", true)
		aircraft.set_meta("airplane_test_persistent_rocket_tuning", _attack_uses_rockets())
		aircraft.set_meta("airplane_test_persistent_bomb_tuning", _attack_uses_bombs())
	if stow_landing_gear_on_start:
		_stow_test_landing_gear(aircraft)
	if attack_phase_enabled and _attack_uses_bombs():
		_select_bomb_weapon(aircraft)
	elif attack_phase_enabled and _attack_uses_rockets() and attack_test_keep_rocket_pods:
		_select_rocket_weapon(aircraft)
	else:
		_select_gun_weapon(aircraft)
	return removed_weapons

func _attack_is_mixed_mode() -> bool:
	return attack_phase_enabled and attack_test_weapon_mode == "Mixed"

func _attack_uses_bombs(weapon_mode: String = "") -> bool:
	var mode: String = attack_test_weapon_mode if weapon_mode.is_empty() else weapon_mode
	return mode == "Bombs" or mode == "Mixed"

func _attack_uses_rockets(weapon_mode: String = "") -> bool:
	var mode: String = attack_test_weapon_mode if weapon_mode.is_empty() else weapon_mode
	return mode == "Rockets" or mode == "Mixed"

func _attack_uses_guns(weapon_mode: String = "") -> bool:
	var mode: String = attack_test_weapon_mode if weapon_mode.is_empty() else weapon_mode
	return mode == "Guns" or mode == "Mixed"

func _attack_uses_unlimited_ordnance() -> bool:
	return (_attack_uses_rockets() and attack_test_unlimited_rockets) or (_attack_uses_bombs() and attack_test_unlimited_bombs)

func _weapon_mode_uses_unlimited_ordnance(weapon_mode: String) -> bool:
	return (_attack_uses_rockets(weapon_mode) and attack_test_unlimited_rockets) or (_attack_uses_bombs(weapon_mode) and attack_test_unlimited_bombs)

func _get_weapon_mode_for_cycle(cycle_index: int) -> String:
	if not _attack_is_mixed_mode():
		return attack_test_weapon_mode
	if attack_test_mixed_sequence.is_empty():
		return "Guns"
	var sequence_size: int = attack_test_mixed_sequence.size()
	var safe_index: int = ((cycle_index % sequence_size) + sequence_size) % sequence_size
	var mode: String = attack_test_mixed_sequence[safe_index]
	if mode in ["Bombs", "Rockets", "Guns"]:
		return mode
	return "Guns"

func _get_trial_weapon_mode(trial: Dictionary) -> String:
	return str(trial.get("current_weapon_mode", attack_test_weapon_mode))

func _configure_aircraft_for_attack_weapon(aircraft: RigidBody3D, weapon_mode: String) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	if _weapon_mode_uses_unlimited_ordnance(weapon_mode):
		aircraft.set_meta("heli_test_unlimited_ammo", true)
		aircraft.set_meta("airplane_test_persistent_rocket_tuning", _attack_uses_rockets(weapon_mode))
		aircraft.set_meta("airplane_test_persistent_bomb_tuning", _attack_uses_bombs(weapon_mode))
	if _attack_uses_bombs(weapon_mode):
		_select_bomb_weapon(aircraft)
	elif _attack_uses_rockets(weapon_mode):
		_select_rocket_weapon(aircraft)
	else:
		_select_gun_weapon(aircraft)

func _configure_pilot_for_attack_weapon(pilot: AIPilot, weapon_mode: String) -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	var forced_weapon_type: String = ""
	if _attack_uses_bombs(weapon_mode):
		forced_weapon_type = "Bomb"
	elif _attack_uses_rockets(weapon_mode):
		forced_weapon_type = "Rocket Pod"
	elif _attack_uses_guns(weapon_mode):
		forced_weapon_type = "Guns"
	if pilot.has_method("set_ground_attack_forced_weapon_type"):
		pilot.set_ground_attack_forced_weapon_type(forced_weapon_type)
	else:
		pilot.set("ground_attack_forced_weapon_type", forced_weapon_type)

func _strip_non_gun_weapons(aircraft: RigidBody3D) -> int:
	var removed: int = 0
	var keep_rockets: bool = attack_phase_enabled and _attack_uses_rockets() and attack_test_keep_rocket_pods
	var keep_bombs: bool = attack_phase_enabled and _attack_uses_bombs()
	var hardpoints: Array[Node] = []
	_collect_hardpoints(aircraft, hardpoints)
	for hardpoint: Node in hardpoints:
		var weapon_value: Variant = hardpoint.get("weapon_instance")
		if not is_instance_valid(weapon_value):
			continue
		var weapon: Node = weapon_value as Node
		if weapon == null:
			continue
		if _is_gun_weapon(weapon):
			continue
		if keep_rockets and _is_rocket_weapon(weapon):
			continue
		if keep_bombs and _is_bomb_weapon(weapon):
			continue
		hardpoint.set("weapon_instance", null)
		weapon.queue_free()
		removed += 1
	return removed

func _collect_hardpoints(node: Node, out: Array[Node]) -> void:
	if node == null:
		return
	if node is Hardpoint:
		out.append(node)
	for child: Node in node.get_children():
		_collect_hardpoints(child, out)

func _install_test_gun(aircraft: RigidBody3D) -> bool:
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	var hardpoints: Array[Node] = []
	_collect_hardpoints(aircraft, hardpoints)
	var preferred_hardpoint: Hardpoint = null
	for hardpoint_node: Node in hardpoints:
		var hardpoint: Hardpoint = hardpoint_node as Hardpoint
		if hardpoint == null:
			continue
		if hardpoint.name == "Hardpoint3":
			preferred_hardpoint = hardpoint
			break
		var weapon_value: Variant = hardpoint.get("weapon_instance")
		if is_instance_valid(weapon_value) and weapon_value is Node and _is_gun_weapon(weapon_value as Node):
			preferred_hardpoint = hardpoint
	if preferred_hardpoint == null and not hardpoints.is_empty():
		preferred_hardpoint = hardpoints[0] as Hardpoint
	if preferred_hardpoint == null:
		return false
	var mounted: bool = preferred_hardpoint.mount_weapon_from_scene(TEST_GUN_SCENE)
	if mounted:
		var weapon_value: Variant = preferred_hardpoint.get("weapon_instance")
		if is_instance_valid(weapon_value) and weapon_value is Node:
			var weapon: Node = weapon_value as Node
			if "max_range_m" in weapon:
				weapon.set("max_range_m", maxf(gun_test_max_range_m, 50.0))
		_refresh_weapon_controller(aircraft)
	_log_event("TEST_GUN_INSTALL aircraft=%s hardpoint=%s mounted=%s max_range=%.1f scene=%s" % [
		aircraft.name,
		preferred_hardpoint.name,
		str(mounted),
		gun_test_max_range_m,
		TEST_GUN_SCENE.resource_path,
	])
	return mounted

func _configure_rocket_tuning_context(aircraft: RigidBody3D, trial_id: int, target: Node3D = null) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	var tuning_target: Node3D = target
	if tuning_target == null or not is_instance_valid(tuning_target):
		tuning_target = _target
	var hardpoints: Array[Node] = []
	_collect_hardpoints(aircraft, hardpoints)
	for hardpoint: Node in hardpoints:
		var weapon_value: Variant = hardpoint.get("weapon_instance")
		if not is_instance_valid(weapon_value):
			continue
		var weapon: Node = weapon_value as Node
		if weapon == null or not _is_rocket_weapon(weapon):
			continue
		if weapon.has_method("set_tuning_context"):
			weapon.call(
				"set_tuning_context",
				Callable(self, "_on_test_rocket_launched"),
				Callable(),
				trial_id,
				tuning_target,
				Callable(self, "_on_test_rocket_impact_detail")
			)

func _configure_bomb_tuning_context(aircraft: RigidBody3D, trial_id: int, target: Node3D = null) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	var tuning_target: Node3D = target
	if tuning_target == null or not is_instance_valid(tuning_target):
		tuning_target = _target
	var hardpoints: Array[Node] = []
	_collect_hardpoints(aircraft, hardpoints)
	for hardpoint: Node in hardpoints:
		var weapon_value: Variant = hardpoint.get("weapon_instance")
		if not is_instance_valid(weapon_value):
			continue
		var weapon: Node = weapon_value as Node
		if weapon == null or not _is_bomb_weapon(weapon):
			continue
		if weapon.has_method("set_tuning_context"):
			weapon.call(
				"set_tuning_context",
				Callable(self, "_on_test_bomb_dropped"),
				Callable(),
				trial_id,
				tuning_target,
				Callable(self, "_on_test_bomb_impact_detail")
			)

func _configure_gun_tuning_context(aircraft: RigidBody3D, trial_id: int, target: Node3D = null) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	var tuning_target: Node3D = target
	if tuning_target == null or not is_instance_valid(tuning_target):
		tuning_target = _target
	var hardpoints: Array[Node] = []
	_collect_hardpoints(aircraft, hardpoints)
	for hardpoint: Node in hardpoints:
		var weapon_value: Variant = hardpoint.get("weapon_instance")
		if not is_instance_valid(weapon_value):
			continue
		var weapon: Node = weapon_value as Node
		if weapon == null or not _is_gun_weapon(weapon):
			continue
		if weapon.has_method("set_tuning_context"):
			weapon.call(
				"set_tuning_context",
				Callable(self, "_on_test_gun_shot"),
				Callable(self, "_on_test_gun_report").bind(trial_id),
				trial_id,
				tuning_target
			)

func _configure_attack_tuning_context(aircraft: RigidBody3D, trial_id: int, target: Node3D = null, weapon_mode: String = "") -> void:
	if weapon_mode.is_empty() and _attack_is_mixed_mode():
		_configure_bomb_tuning_context(aircraft, trial_id, target)
		_configure_rocket_tuning_context(aircraft, trial_id, target)
		_configure_gun_tuning_context(aircraft, trial_id, target)
	elif _attack_uses_bombs(weapon_mode):
		_configure_bomb_tuning_context(aircraft, trial_id, target)
	elif _attack_uses_rockets(weapon_mode):
		_configure_rocket_tuning_context(aircraft, trial_id, target)
	elif _attack_uses_guns(weapon_mode):
		_configure_gun_tuning_context(aircraft, trial_id, target)

func _is_gun_weapon(weapon: Node) -> bool:
	var weapon_name: String = str(weapon.get("weapon_name"))
	var weapon_category: String = str(weapon.get("weapon_category"))
	return weapon_name == "Autocannon" or weapon_category == "Guns" or weapon_category == "Autocannon"

func _is_rocket_weapon(weapon: Node) -> bool:
	var weapon_name: String = str(weapon.get("weapon_name"))
	var weapon_category: String = str(weapon.get("weapon_category"))
	return weapon_name == "Rocket Pod" or weapon_category == "Rocket Pod" or weapon_category == "Rockets"

func _is_bomb_weapon(weapon: Node) -> bool:
	var weapon_name: String = str(weapon.get("weapon_name"))
	var weapon_category: String = str(weapon.get("weapon_category"))
	return weapon_name == "Bomb" or weapon_category == "Bomb" or weapon_category == "Bombs"

func _refresh_weapon_controller(aircraft: RigidBody3D) -> Node:
	var control_weapons: Node = aircraft.find_child("ControlWeapons", true, false)
	if control_weapons == null:
		return null
	if control_weapons.has_method("find_hardpoints"):
		control_weapons.call("find_hardpoints")
	if control_weapons.has_method("categorize_weapons"):
		control_weapons.call("categorize_weapons")
	return control_weapons

func _select_bomb_weapon(aircraft: RigidBody3D) -> void:
	var control_weapons: Node = _refresh_weapon_controller(aircraft)
	if control_weapons == null:
		return
	var weapon_types_value: Variant = control_weapons.get("weapon_types")
	if not (weapon_types_value is Array):
		return
	var weapon_types: Array = weapon_types_value as Array
	var bomb_index: int = weapon_types.find("Bomb")
	if bomb_index == -1:
		return
	control_weapons.set("selected_weapon_type_index", bomb_index)
	control_weapons.set("selected_weapon_type", str(weapon_types[bomb_index]))

func _select_rocket_weapon(aircraft: RigidBody3D) -> void:
	var control_weapons: Node = _refresh_weapon_controller(aircraft)
	if control_weapons == null:
		return
	var weapon_types_value: Variant = control_weapons.get("weapon_types")
	if not (weapon_types_value is Array):
		return
	var weapon_types: Array = weapon_types_value as Array
	var rocket_index: int = weapon_types.find("Rocket Pod")
	if rocket_index == -1:
		return
	control_weapons.set("selected_weapon_type_index", rocket_index)
	control_weapons.set("selected_weapon_type", str(weapon_types[rocket_index]))

func _select_gun_weapon(aircraft: RigidBody3D) -> void:
	var control_weapons: Node = _refresh_weapon_controller(aircraft)
	if control_weapons == null:
		return
	var weapon_types_value: Variant = control_weapons.get("weapon_types")
	if not (weapon_types_value is Array):
		return
	var weapon_types: Array = weapon_types_value as Array
	var gun_index: int = weapon_types.find("Guns")
	if gun_index == -1:
		gun_index = weapon_types.find("Autocannon")
	if gun_index == -1:
		return
	control_weapons.set("selected_weapon_type_index", gun_index)
	control_weapons.set("selected_weapon_type", str(weapon_types[gun_index]))

func _stow_test_landing_gear(aircraft: RigidBody3D) -> void:
	var control_gear: Node = aircraft.find_child("ControlLandingGear", true, false)
	if control_gear != null:
		if "LockGearDeployed" in control_gear:
			control_gear.set("LockGearDeployed", false)
		if control_gear.has_method("send_to_landing_gears"):
			control_gear.call("send_to_landing_gears", "stow")
		if control_gear.has_method("send_to_tailhooks"):
			control_gear.call("send_to_tailhooks", "stow")
		if control_gear.has_method("send_to_tailhook_simple"):
			control_gear.call("send_to_tailhook_simple", false)
		if control_gear.has_method("_set_collider_disabled"):
			control_gear.call("_set_collider_disabled", true)
		if "gear_down_state" in control_gear:
			control_gear.set("gear_down_state", false)
		if "tailhook_down_state" in control_gear:
			control_gear.set("tailhook_down_state", false)
	var landing_gear: Node = aircraft.find_child("LandingGear", true, false)
	if landing_gear != null:
		if "lock_deployed" in landing_gear:
			landing_gear.set("lock_deployed", false)
		if landing_gear.has_method("stow"):
			landing_gear.call("stow")
		if "current_state" in landing_gear:
			landing_gear.set("current_state", 0)
		if "is_deployed" in landing_gear:
			landing_gear.set("is_deployed", false)
		if "is_stowed" in landing_gear:
			landing_gear.set("is_stowed", true)
		if "_gear_animation_target" in landing_gear:
			landing_gear.set("_gear_animation_target", 0.0)
		if "_gear_animation_progress" in landing_gear:
			landing_gear.set("_gear_animation_progress", 0.0)
		if "_gear_animation_active" in landing_gear:
			landing_gear.set("_gear_animation_active", false)
		if landing_gear.has_method("_apply_visual_gear_pose"):
			landing_gear.call("_apply_visual_gear_pose")
	for collider_name: String in ["CenterGearCollider", "RightGearCollider", "LeftGearCollider"]:
		var collider: CollisionShape3D = aircraft.find_child(collider_name, true, false) as CollisionShape3D
		if collider != null:
			collider.disabled = true

func _stow_test_landing_gear_after_ready(aircraft: RigidBody3D) -> void:
	await get_tree().process_frame
	if aircraft == null or not is_instance_valid(aircraft):
		return
	_stow_test_landing_gear(aircraft)
	await get_tree().create_timer(0.25).timeout
	if aircraft == null or not is_instance_valid(aircraft):
		return
	_stow_test_landing_gear(aircraft)

func _apply_test_auto_rudder_to_simple_aero(pilot: AIPilot) -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	var simple_aero: Node = pilot.simple_aero
	if simple_aero != null and is_instance_valid(simple_aero) and "auto_rudder_strength" in simple_aero:
		simple_aero.auto_rudder_strength = 0.0

func _build_base_circuit_route() -> Array[Dictionary]:
	var r: float = circuit_radius_m
	var h: float = circuit_altitude_agl_m
	var step: float = circuit_altitude_step_m
	var route: Array[Dictionary] = [
		_make_base_leg(_get_route_point(r * 1.35, -r * 0.60, h), "east_gate", 1.00),
		_make_base_leg(_get_route_point(r * 1.25, r * 0.05, h + step * 0.20), "east_climb_entry", 1.00),
		_make_base_leg(_get_route_point(r * 1.55, r * 0.70, h + step * 0.80), "east_s_bend", 0.96),
		_make_base_leg(_get_route_point(r * 1.15, r * 1.20, h + step * 1.20), "northeast_sweep", 0.96),
		_make_base_leg(_get_route_point(r * 0.45, r * 1.45, h + step * 1.20), "north_straight", 1.02),
		_make_base_leg(_get_route_point(-r * 0.30, r * 1.38, h + step * 0.75), "northwest_descent", 1.00),
		_make_base_leg(_get_route_point(-r * 0.83, r * 1.68, h + step * 0.20), "northwest_reversal", 0.94),
		_make_base_leg(_get_route_point(-r * 1.35, r * 1.25, h - step * 0.10), "west_sweep", 0.96),
		_make_base_leg(_get_route_point(-r * 1.55, r * 0.65, h + step * 0.10), "west_straight", 1.00),
		_make_base_leg(_get_route_point(-r * 1.35, r * 0.05, h + step * 0.70), "west_climb_entry", 0.98),
		_make_base_leg(_get_route_point(-r * 1.60, -r * 0.55, h + step * 1.25), "west_reversal_high", 0.94),
		_make_base_leg(_get_route_point(-r * 1.25, -r * 1.05, h + step * 0.75), "southwest_descent", 0.96),
		_make_base_leg(_get_route_point(-r * 0.65, -r * 1.35, h + step * 0.15), "south_straight", 1.02),
		_make_base_leg(_get_route_point(-r * 0.10, -r * 1.18, h - step * 0.20), "south_reversal_low", 0.96),
		_make_base_leg(_get_route_point(r * 0.35, -r * 1.45, h + step * 0.35), "southeast_climb", 0.96),
		_make_base_leg(_get_route_point(r * 0.90, -r * 1.35, h + step * 0.90), "southeast_sweep", 0.98),
		_make_base_leg(_get_route_point(r * 1.35, -r * 1.05, h + step * 0.40), "east_egress", 1.00),
	]
	return route

func _make_base_leg(position: Vector3, role: String, speed_scale: float) -> Dictionary:
	return {
		"position": position,
		"role": role,
		"speed_scale": speed_scale,
	}

func _build_trial_route(genome: Dictionary) -> Array[Dictionary]:
	var route: Array[Dictionary] = []
	var speed_mps: float = float(genome.get("speed_mps", circuit_speed_mps))
	var capture_radius_m: float = float(genome.get("capture_radius_m", 260.0))
	for base_leg: Dictionary in _base_route:
		var position_value: Variant = base_leg.get("position", Vector3.ZERO)
		if not (position_value is Vector3):
			continue
		var speed_scale: float = float(base_leg.get("speed_scale", 1.0))
		route.append({
			"position": position_value as Vector3,
			"role": str(base_leg.get("role", "circuit")),
			"speed_mps": speed_mps * speed_scale,
			"capture_radius_m": capture_radius_m,
		})
	return route

func _uses_full_lap_evaluation() -> bool:
	return full_lap_evaluation_enabled and not attack_phase_enabled

func _update_generation_completion() -> void:
	if not genetic_tuning_enabled:
		return
	var generation_age_s: float = _elapsed_s - _generation_start_s
	if not _uses_full_lap_evaluation():
		var nominal_duration_s: float = maxf(generation_duration_s, 30.0)
		if _attack_is_mixed_mode() and generation_age_s >= nominal_duration_s:
			var hard_timeout_s: float = maxf(mixed_generation_hard_timeout_s, nominal_duration_s)
			if _all_mixed_attack_cycles_complete() or generation_age_s >= hard_timeout_s:
				_complete_generation_and_start_next()
			return
		if generation_age_s >= nominal_duration_s:
			_complete_generation_and_start_next()
		return
	if _all_generation_trials_terminal():
		_log_event("GENERATION_TERMINAL generation=%d age=%.1f reason=all_trials_complete" % [
			_generation_index,
			generation_age_s,
		])
		_complete_generation_and_start_next()
		return
	if generation_age_s >= maxf(full_lap_timeout_s, 30.0):
		_mark_unfinished_trials_timed_out()
		_log_event("GENERATION_TERMINAL generation=%d age=%.1f reason=timeout" % [
			_generation_index,
			generation_age_s,
		])
		_complete_generation_and_start_next()

func _all_mixed_attack_cycles_complete() -> bool:
	if _pending_spawn_index < _population_genomes.size() or _trials.size() < _population_genomes.size():
		return false
	var required_cycles: int = maxi(attack_cycles_per_trial, 0)
	for trial: Dictionary in _trials:
		if bool(trial.get("crashed", false)) or bool(trial.get("destroyed", false)):
			continue
		if bool(trial.get("attack_active", false)):
			return false
		if int(trial.get("attack_cycle_count", 0)) < required_cycles:
			return false
	return true

func _all_generation_trials_terminal() -> bool:
	if _population_genomes.is_empty():
		return false
	if _pending_spawn_index < _population_genomes.size():
		return false
	if _trials.size() < _population_genomes.size():
		return false
	for trial: Dictionary in _trials:
		if not bool(trial.get("evaluation_complete", false)):
			return false
	return true

func _mark_unfinished_trials_timed_out() -> void:
	for trial_index in range(_trials.size()):
		var trial: Dictionary = _trials[trial_index]
		if bool(trial.get("evaluation_complete", false)):
			continue
		_finish_trial_evaluation(trial_index, "timeout", true)

func _finish_trial_evaluation(trial_index: int, reason: String, remove_aircraft: bool) -> void:
	if trial_index < 0 or trial_index >= _trials.size():
		return
	var trial: Dictionary = _trials[trial_index]
	if bool(trial.get("evaluation_complete", false)):
		return
	var spawn_time_s: float = float(trial.get("spawn_time_s", _elapsed_s))
	trial["evaluation_complete"] = true
	trial["evaluation_reason"] = reason
	trial["evaluation_end_time_s"] = _elapsed_s
	trial["evaluation_duration_s"] = maxf(_elapsed_s - spawn_time_s, 0.0)
	if reason == "lap_complete":
		trial["lap_completed"] = true
	_trials[trial_index] = trial
	var record: Dictionary = _score_trial(trial)
	_log_event("TRIAL_EVALUATION_COMPLETE generation=%d id=%d reason=%s duration=%.1f samples=%d laps=%d progress=%.2f score=%.1f mean_x=%.1f max_x=%.1f" % [
		int(trial.get("generation", _generation_index)),
		int(trial.get("id", -1)),
		reason,
		float(trial.get("evaluation_duration_s", 0.0)),
		int(trial.get("samples", 0)),
		int(trial.get("completed_laps", 0)),
		float(trial.get("route_progress_units", 0.0)),
		float(record.get("score", INF)),
		float(record.get("mean_xtrack_m", INF)),
		float(record.get("max_xtrack_m", INF)),
	])
	if not remove_aircraft:
		return
	var aircraft: RigidBody3D = _get_trial_aircraft(trial)
	trial["aircraft"] = null
	trial["pilot"] = null
	_trials[trial_index] = trial
	if aircraft != null:
		aircraft.queue_free()

func _complete_generation_and_start_next() -> void:
	var records: Array[Dictionary] = []
	for i in range(_trials.size()):
		var trial: Dictionary = _trials[i]
		var record: Dictionary = _score_trial(trial)
		records.append(record)
		_log_trial_summary(trial, "generation_end")
	if records.is_empty():
		_generation_index += 1
		_start_generation([])
		return
	records.sort_custom(_score_record_less)
	var best: Dictionary = records[0]
	var worst: Dictionary = records[records.size() - 1]
	_save_best_pilot_if_improved(best)
	_log_event("GENERATION_SUMMARY generation=%d best_id=%d best_score=%.1f worst_score=%.1f best_genome=%s" % [
		_generation_index,
		int(best.get("trial_id", -1)),
		float(best.get("score", INF)),
		float(worst.get("score", INF)),
		_format_genome(best.get("genome", {}) as Dictionary),
	])
	_log_generation_ranking(records)
	if deterministic_validation_enabled:
		_log_validation_summary(records)
	var next_population: Array[Dictionary] = _make_next_generation(records)
	_generation_index += 1
	_start_generation(next_population)

func _score_record_less(a: Dictionary, b: Dictionary) -> bool:
	var a_survived: bool = not bool(a.get("crashed", false))
	var b_survived: bool = not bool(b.get("crashed", false))
	if a_survived != b_survived:
		return a_survived
	if _uses_full_lap_evaluation():
		var a_lap_completed: bool = bool(a.get("lap_completed", false))
		var b_lap_completed: bool = bool(b.get("lap_completed", false))
		if a_lap_completed != b_lap_completed:
			return a_lap_completed
	if attack_phase_enabled:
		var a_completed: bool = int(a.get("committed_attack_runs", 0)) > 0
		var b_completed: bool = int(b.get("committed_attack_runs", 0)) > 0
		if a_completed != b_completed:
			return a_completed
		var a_fired: bool = int(a.get("attack_launches", 0)) > 0
		var b_fired: bool = int(b.get("attack_launches", 0)) > 0
		if a_fired != b_fired:
			return a_fired
		var a_hit: bool = int(a.get("attack_hits", 0)) > 0
		var b_hit: bool = int(b.get("attack_hits", 0)) > 0
		if a_hit != b_hit:
			return a_hit
	if _attack_is_mixed_mode():
		var a_complete: bool = _mixed_record_has_all_weapon_phases(a)
		var b_complete: bool = _mixed_record_has_all_weapon_phases(b)
		if a_complete != b_complete:
			return a_complete
	return float(a.get("score", INF)) < float(b.get("score", INF))

func _mixed_record_has_all_weapon_phases(record: Dictionary) -> bool:
	return (
		int(record.get("bomb_drops", 0)) > 0
		and int(record.get("rocket_launches", 0)) > 0
		and int(record.get("gun_shots", 0)) > 0
	)

func _log_validation_summary(records: Array[Dictionary]) -> void:
	var survived: int = 0
	var completed: int = 0
	var fired: int = 0
	var launches: int = 0
	var impacts: int = 0
	var hits: int = 0
	var direct_hits: int = 0
	var dry_runs: int = 0
	for record: Dictionary in records:
		if not bool(record.get("crashed", false)):
			survived += 1
		if int(record.get("committed_attack_runs", 0)) > 0:
			completed += 1
		if int(record.get("attack_launches", 0)) > 0:
			fired += 1
		launches += int(record.get("attack_launches", 0))
		impacts += int(record.get("attack_impacts", 0))
		hits += int(record.get("attack_hits", 0))
		direct_hits += int(record.get("attack_direct_hits", 0))
		dry_runs += int(record.get("dry_attack_runs", 0))
	_log_event("VALIDATION_SUMMARY generation=%d aircraft=%d survived=%d completed=%d fired=%d launches=%d impacts=%d hits=%d direct=%d dry_runs=%d genome=%s" % [
		_generation_index,
		records.size(),
		survived,
		completed,
		fired,
		launches,
		impacts,
		hits,
		direct_hits,
		dry_runs,
		_format_genome(_validation_genome),
	])

func _make_next_generation(records: Array[Dictionary]) -> Array[Dictionary]:
	if deterministic_validation_enabled and not _validation_genome.is_empty():
		var validation_population: Array[Dictionary] = []
		while validation_population.size() < _get_population_size():
			validation_population.append(_validation_genome.duplicate(true))
		return validation_population
	var next_population: Array[Dictionary] = []
	var parent_pool: Array[Dictionary] = []
	if _attack_is_mixed_mode() and not _mixed_navigation_baseline_genome.is_empty():
		_append_population_genome(next_population, _mixed_navigation_baseline_genome)
		parent_pool.append(_mixed_navigation_baseline_genome.duplicate(true))
	if genetic_preserve_saved_best and not _best_saved_genome.is_empty():
		_append_population_genome(next_population, _best_saved_genome)
		parent_pool.append(_best_saved_genome.duplicate(true))
	var elite_count: int = clampi(genetic_elite_count, 1, records.size())
	for i in range(elite_count):
		var genome_value: Variant = records[i].get("genome", {})
		if genome_value is Dictionary:
			_append_population_genome(next_population, genome_value as Dictionary)
	if _attack_is_mixed_mode() and mixed_preserve_weapon_specialists:
		_append_mixed_weapon_specialists(next_population, parent_pool, records)
	var parent_record_count: int = clampi(maxi(genetic_parent_pool_count, elite_count), 1, records.size())
	for i in range(parent_record_count):
		var parent_value: Variant = records[i].get("genome", {})
		if parent_value is Dictionary:
			parent_pool.append((parent_value as Dictionary).duplicate(true))
	if parent_pool.is_empty():
		parent_pool.append(_make_default_genome())
	while next_population.size() < _get_population_size():
		var parent_index: int = _rng.randi_range(0, parent_pool.size() - 1)
		var parent: Dictionary = parent_pool[parent_index]
		next_population.append(_mutate_genome(parent))
	return next_population

func _append_mixed_weapon_specialists(
	population: Array[Dictionary],
	parent_pool: Array[Dictionary],
	records: Array[Dictionary]
) -> void:
	for weapon_value in ["Rockets", "Bombs", "Guns"]:
		var weapon_mode: String = str(weapon_value)
		var record: Dictionary = _find_mixed_weapon_specialist(records, weapon_mode)
		if record.is_empty():
			continue
		var genome_value: Variant = record.get("genome", {})
		if not (genome_value is Dictionary):
			continue
		var genome: Dictionary = (genome_value as Dictionary).duplicate(true)
		_append_population_genome(population, genome)
		parent_pool.append(genome)
		_log_event("MIXED_SPECIALIST_PRESERVED generation=%d weapon=%s id=%d score=%.1f rockets=%d rocket_hits=%d bombs=%d bomb_hits=%d guns=%d gun_hits=%d crashed=%s genome=%s" % [
			_generation_index,
			weapon_mode,
			int(record.get("trial_id", -1)),
			float(record.get("score", INF)),
			int(record.get("rocket_launches", 0)),
			int(record.get("rocket_hits", 0)),
			int(record.get("bomb_drops", 0)),
			int(record.get("bomb_hits", 0)),
			int(record.get("gun_shots", 0)),
			int(record.get("gun_hits", 0)),
			str(record.get("crashed", false)),
			_format_genome(genome),
		])

func _find_mixed_weapon_specialist(records: Array[Dictionary], weapon_mode: String) -> Dictionary:
	var best: Dictionary = {}
	for record: Dictionary in records:
		if not _record_has_weapon_phase(record, weapon_mode):
			continue
		if best.is_empty() or _mixed_weapon_record_better(record, best, weapon_mode):
			best = record
	return best

func _record_has_weapon_phase(record: Dictionary, weapon_mode: String) -> bool:
	match weapon_mode:
		"Rockets":
			return int(record.get("rocket_launches", 0)) > 0
		"Bombs":
			return int(record.get("bomb_drops", 0)) > 0
		"Guns":
			return int(record.get("gun_shots", 0)) > 0
	return false

func _mixed_weapon_record_better(candidate: Dictionary, current: Dictionary, weapon_mode: String) -> bool:
	var candidate_crashed: bool = bool(candidate.get("crashed", false))
	var current_crashed: bool = bool(current.get("crashed", false))
	if candidate_crashed != current_crashed:
		return not candidate_crashed
	var candidate_hits: int = _weapon_record_hits(candidate, weapon_mode)
	var current_hits: int = _weapon_record_hits(current, weapon_mode)
	if candidate_hits != current_hits:
		return candidate_hits > current_hits
	var candidate_direct_hits: int = _weapon_record_direct_hits(candidate, weapon_mode)
	var current_direct_hits: int = _weapon_record_direct_hits(current, weapon_mode)
	if candidate_direct_hits != current_direct_hits:
		return candidate_direct_hits > current_direct_hits
	var candidate_min_miss: float = _weapon_record_min_miss(candidate, weapon_mode)
	var current_min_miss: float = _weapon_record_min_miss(current, weapon_mode)
	if not is_equal_approx(candidate_min_miss, current_min_miss):
		return candidate_min_miss < current_min_miss
	var candidate_actions: int = _weapon_record_actions(candidate, weapon_mode)
	var current_actions: int = _weapon_record_actions(current, weapon_mode)
	if candidate_actions != current_actions:
		return candidate_actions > current_actions
	return float(candidate.get("score", INF)) < float(current.get("score", INF))

func _weapon_record_hits(record: Dictionary, weapon_mode: String) -> int:
	match weapon_mode:
		"Rockets":
			return int(record.get("rocket_hits", 0))
		"Bombs":
			return int(record.get("bomb_hits", 0))
		"Guns":
			return int(record.get("gun_hits", 0))
	return 0

func _weapon_record_direct_hits(record: Dictionary, weapon_mode: String) -> int:
	match weapon_mode:
		"Rockets":
			return int(record.get("rocket_direct_hits", 0))
		"Bombs":
			return int(record.get("bomb_direct_hits", 0))
		"Guns":
			return int(record.get("gun_hits", 0))
	return 0

func _weapon_record_actions(record: Dictionary, weapon_mode: String) -> int:
	match weapon_mode:
		"Rockets":
			return int(record.get("rocket_launches", 0))
		"Bombs":
			return int(record.get("bomb_drops", 0))
		"Guns":
			return int(record.get("gun_shots", 0))
	return 0

func _weapon_record_min_miss(record: Dictionary, weapon_mode: String) -> float:
	match weapon_mode:
		"Rockets":
			return float(record.get("rocket_min_miss_m", INF))
		"Bombs":
			return float(record.get("bomb_min_miss_m", INF))
		"Guns":
			return float(record.get("gun_min_edge_miss_m", INF))
	return INF

func _append_population_genome(population: Array[Dictionary], genome: Dictionary) -> void:
	if population.size() >= _get_population_size() or genome.is_empty():
		return
	var genome_id: int = int(genome.get("id", -1))
	if genome_id >= 0:
		for existing: Dictionary in population:
			if int(existing.get("id", -2)) == genome_id:
				return
	var normalized_genome: Dictionary = genome.duplicate(true)
	_apply_mixed_navigation_baseline(normalized_genome)
	population.append(normalized_genome)

func _load_saved_default_pilot() -> Dictionary:
	var primary_default_path: String = _get_default_pilot_path()
	var primary_best_path: String = _get_best_pilot_path()
	var paths: Array[String] = [primary_default_path, primary_best_path]
	if not attack_phase_enabled:
		paths.append("user://airplane_test_default_pilot_rockets.json")
		paths.append("user://airplane_test_best_pilot_rockets.json")
		paths.append(PROJECT_NAVIGATION_SEED_PATH)
	elif _attack_is_mixed_mode():
		paths.append("user://airplane_test_default_pilot_guns.json")
		paths.append("user://airplane_test_best_pilot_guns.json")
		paths.append("user://airplane_test_default_pilot_rockets.json")
		paths.append("user://airplane_test_best_pilot_rockets.json")
		paths.append("user://airplane_test_default_pilot_bombs.json")
		paths.append("user://airplane_test_best_pilot_bombs.json")
	elif _attack_uses_rockets():
		paths.append(PROJECT_ROCKET_SPECIALIST_PATH)
		paths.append(PROJECT_NAVIGATION_SEED_PATH)
	elif _attack_uses_bombs():
		paths.append(LEGACY_DEFAULT_PILOT_PATH)
		paths.append(LEGACY_BEST_PILOT_PATH)
	for path: String in paths:
		if not FileAccess.file_exists(path):
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_warning("[AirplaneTest] Could not read %s" % path)
			continue
		var text: String = file.get_as_text()
		file.close()
		var parsed: Variant = JSON.parse_string(text)
		if not (parsed is Dictionary):
			push_warning("[AirplaneTest] Ignoring invalid saved pilot JSON at %s" % path)
			continue
		var state: Dictionary = parsed as Dictionary
		var genome_value: Variant = state.get("genome", {})
		if not (genome_value is Dictionary):
			push_warning("[AirplaneTest] Saved pilot at %s has no genome" % path)
			continue
		var genome: Dictionary = (genome_value as Dictionary).duplicate(true)
		var genome_normalized: bool = _ensure_route_guidance_genes(genome)
		_next_genome_id = maxi(_next_genome_id, int(genome.get("id", -1)) + 1)
		var is_mode_specific_save: bool = path == primary_default_path or path == primary_best_path
		if genome_normalized and is_mode_specific_save:
			state["genome"] = genome
			_write_json_file(path, state)
		var is_project_weapon_specialist: bool = path == PROJECT_ROCKET_SPECIALIST_PATH
		var score_schema_matches: bool = int(state.get("score_schema_version", 0)) == _get_score_schema_version()
		var weapon_mode_matches: bool = str(state.get("weapon_mode", "")) == _get_pilot_mode_name()
		var saved_score_eligible: bool = (is_mode_specific_save or is_project_weapon_specialist) \
				and score_schema_matches and weapon_mode_matches
		if saved_score_eligible and _attack_is_mixed_mode() and mixed_save_requires_all_weapon_phases:
			saved_score_eligible = _mixed_saved_state_has_all_weapon_phases(state)
		if saved_score_eligible:
			_best_saved_score = float(state.get("score", _best_saved_score))
			_best_saved_generation = int(state.get("generation", -1))
			_best_saved_genome = genome.duplicate(true)
			_best_saved_record = _make_score_record_from_saved_state(state)
			if is_project_weapon_specialist:
				_materialize_project_specialist_save(state, primary_default_path, primary_best_path)
		_log_event("LOADED_DEFAULT_PILOT path=%s generation=%d score=%.1f score_schema=%d score_active=%s genome=%s" % [
			ProjectSettings.globalize_path(path),
			int(state.get("generation", -1)),
			float(state.get("score", INF)),
			int(state.get("score_schema_version", 0)),
			str(saved_score_eligible),
			_format_genome(genome),
		])
		return genome
	return {}

func _materialize_project_specialist_save(state: Dictionary, default_path: String, best_path: String) -> void:
	var wrote_default: bool = false
	var wrote_best: bool = false
	if not FileAccess.file_exists(default_path):
		wrote_default = _write_json_file(default_path, state)
	if not FileAccess.file_exists(best_path):
		wrote_best = _write_json_file(best_path, state)
	if wrote_default or wrote_best:
		_log_event("MATERIALIZED_PROJECT_SPECIALIST weapon=%s default=%s best=%s" % [
			attack_test_weapon_mode,
			ProjectSettings.globalize_path(default_path),
			ProjectSettings.globalize_path(best_path),
		])

func _make_score_record_from_saved_state(state: Dictionary) -> Dictionary:
	return {
		"score": float(state.get("score", INF)),
		"lap_completed": bool(state.get("lap_completed", false)),
		"evaluation_reason": str(state.get("evaluation_reason", "saved")),
		"evaluation_duration_s": float(state.get("evaluation_duration_s", 0.0)),
		"attack_started": bool(state.get("attack_started", int(state.get("attack_launches", 0)) > 0)),
		"committed_attack_runs": int(state.get("committed_attack_runs", 0)),
		"dry_attack_runs": int(state.get("dry_attack_runs", 0)),
		"attack_stalled_runs": int(state.get("attack_stalled_runs", 0)),
		"attack_lineup_retries": int(state.get("attack_lineup_retries", 0)),
		"attack_terrain_emergency_runs": int(state.get("attack_terrain_emergency_runs", 0)),
		"attack_launches": int(state.get("attack_launches", state.get("rocket_launches", 0))),
		"attack_impacts": int(state.get("attack_impacts", state.get("rocket_impacts", 0))),
		"attack_hits": int(state.get("attack_hits", state.get("rocket_hits", 0))),
		"attack_direct_hits": int(state.get("attack_direct_hits", state.get("rocket_direct_hits", 0))),
		"rocket_launches": int(state.get("rocket_launches", 0)),
		"bomb_drops": int(state.get("bomb_drops", state.get("bombs", 0))),
		"gun_shots": int(state.get("gun_shots", 0)),
		"crashed": bool(state.get("crashed", false)),
	}

func _load_mixed_specialist_seed_genomes() -> Array[Dictionary]:
	var seeds: Array[Dictionary] = []
	if not _attack_is_mixed_mode():
		return seeds
	var paths: Array[String] = [
		PROJECT_ROCKET_SPECIALIST_PATH,
		"user://airplane_test_default_pilot_rockets.json",
		"user://airplane_test_best_pilot_rockets.json",
		"user://airplane_test_default_pilot_bombs.json",
		"user://airplane_test_best_pilot_bombs.json",
		"user://airplane_test_default_pilot_guns.json",
		"user://airplane_test_best_pilot_guns.json",
	]
	for path: String in paths:
		var genome: Dictionary = _load_genome_seed_file(path)
		if genome.is_empty():
			continue
		var previous_size: int = seeds.size()
		_append_seed_genome(seeds, genome)
		if seeds.size() > previous_size:
			_log_event("MIXED_SPECIALIST_SEED path=%s genome=%s" % [
				ProjectSettings.globalize_path(path),
				_format_genome(genome),
			])
	return seeds

func _load_genome_seed_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[AirplaneTest] Could not read specialist seed %s" % path)
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[AirplaneTest] Ignoring invalid specialist seed JSON at %s" % path)
		return {}
	var state: Dictionary = parsed as Dictionary
	var genome_value: Variant = state.get("genome", {})
	if not (genome_value is Dictionary) and state.has("speed_mps"):
		genome_value = state
	if not (genome_value is Dictionary):
		push_warning("[AirplaneTest] Specialist seed at %s has no genome" % path)
		return {}
	var genome: Dictionary = (genome_value as Dictionary).duplicate(true)
	_next_genome_id = maxi(_next_genome_id, int(genome.get("id", -1)) + 1)
	return genome

func _mixed_saved_state_has_all_weapon_phases(state: Dictionary) -> bool:
	var bomb_count: int = int(state.get("bombs", state.get("bomb_drops", 0)))
	var rocket_count: int = int(state.get("rocket_launches", state.get("rockets", 0)))
	var gun_count: int = int(state.get("gun_shots", 0))
	return bomb_count > 0 and rocket_count > 0 and gun_count > 0

func _save_best_pilot_if_improved(record: Dictionary) -> void:
	if not save_best_pilot_as_default:
		return
	if _uses_full_lap_evaluation() and not bool(record.get("lap_completed", false)):
		_log_event("SKIPPED_DEFAULT_PILOT_SAVE generation=%d id=%d score=%.1f reason=incomplete_lap" % [
			_generation_index,
			int(record.get("trial_id", -1)),
			float(record.get("score", INF)),
		])
		return
	if _attack_is_mixed_mode() and mixed_save_requires_all_weapon_phases and not _mixed_record_has_all_weapon_phases(record):
		_log_event("SKIPPED_DEFAULT_PILOT_SAVE generation=%d id=%d score=%.1f reason=missing_mixed_weapon_phase bombs=%d rockets=%d guns=%d" % [
			_generation_index,
			int(record.get("trial_id", -1)),
			float(record.get("score", INF)),
			int(record.get("bomb_drops", 0)),
			int(record.get("rocket_launches", 0)),
			int(record.get("gun_shots", 0)),
		])
		return
	var score: float = float(record.get("score", INF))
	if not _best_saved_record.is_empty() and not _score_record_less(record, _best_saved_record):
		return
	var genome_value: Variant = record.get("genome", {})
	if not (genome_value is Dictionary):
		return
	var genome: Dictionary = (genome_value as Dictionary).duplicate(true)
	_ensure_route_guidance_genes(genome)
	var bomb_min_miss_m: float = float(record.get("bomb_min_miss_m", INF))
	var saved_bomb_min_miss: Variant = null if is_inf(bomb_min_miss_m) or is_nan(bomb_min_miss_m) else bomb_min_miss_m
	var gun_min_edge_miss_m: float = float(record.get("gun_min_edge_miss_m", INF))
	var saved_gun_min_edge_miss: Variant = null if is_inf(gun_min_edge_miss_m) or is_nan(gun_min_edge_miss_m) else gun_min_edge_miss_m
	var state: Dictionary = {
		"saved_unix_time": Time.get_unix_time_from_system(),
		"kind": "airplane_test_best_rank1_by_score",
		"weapon_mode": _get_pilot_mode_name(),
		"score_schema_version": _get_score_schema_version(),
		"source_report": ProjectSettings.globalize_path(REPORT_PATH),
		"generation": _generation_index,
		"trial_id": int(record.get("trial_id", -1)),
		"score": score,
		"lap_completed": bool(record.get("lap_completed", false)),
		"evaluation_reason": str(record.get("evaluation_reason", "unknown")),
		"evaluation_duration_s": float(record.get("evaluation_duration_s", 0.0)),
		"attack_started": bool(record.get("attack_started", false)),
		"committed_attack_runs": int(record.get("committed_attack_runs", 0)),
		"dry_attack_runs": int(record.get("dry_attack_runs", 0)),
		"attack_stalled_runs": int(record.get("attack_stalled_runs", 0)),
		"attack_lineup_retries": int(record.get("attack_lineup_retries", 0)),
		"attack_terrain_emergency_runs": int(record.get("attack_terrain_emergency_runs", 0)),
		"attack_launches": int(record.get("attack_launches", 0)),
		"attack_impacts": int(record.get("attack_impacts", 0)),
		"attack_hits": int(record.get("attack_hits", 0)),
		"attack_direct_hits": int(record.get("attack_direct_hits", 0)),
		"rocket_launches": int(record.get("rocket_launches", 0)),
		"rocket_impacts": int(record.get("rocket_impacts", 0)),
		"rocket_hits": int(record.get("rocket_hits", 0)),
		"rocket_direct_hits": int(record.get("rocket_direct_hits", 0)),
		"bombs": int(record.get("bomb_drops", 0)),
		"bomb_impacts": int(record.get("bomb_impacts", 0)),
		"bomb_hits": int(record.get("bomb_hits", 0)),
		"bomb_direct_hits": int(record.get("bomb_direct_hits", 0)),
		"bomb_min_miss_m": saved_bomb_min_miss,
		"gun_shots": int(record.get("gun_shots", 0)),
		"gun_reports": int(record.get("gun_reports", 0)),
		"gun_hits": int(record.get("gun_hits", 0)),
		"gun_min_edge_miss_m": saved_gun_min_edge_miss,
		"mean_xtrack_m": float(record.get("mean_xtrack_m", INF)),
		"max_xtrack_m": float(record.get("max_xtrack_m", INF)),
		"mean_xtrack_delta_m": float(record.get("mean_xtrack_delta_m", INF)),
		"mean_path_error_m": float(record.get("mean_path_error_m", INF)),
		"navigation_capture_first_time_s": record.get("navigation_capture_first_time_s", null),
		"navigation_capture_settled_time_s": record.get("navigation_capture_settled_time_s", null),
		"navigation_capture_corridor_fraction": float(record.get("navigation_capture_corridor_fraction", 0.0)),
		"navigation_pre_capture_error_area": float(record.get("navigation_pre_capture_error_area", 0.0)),
		"navigation_settled_mean_path_error_m": float(record.get("navigation_settled_mean_path_error_m", INF)),
		"navigation_settled_max_path_error_m": float(record.get("navigation_settled_max_path_error_m", 0.0)),
		"mean_control_input_delta": float(record.get("mean_control_input_delta", 0.0)),
		"navigation_settled_mean_control_delta": float(record.get("navigation_settled_mean_control_delta", 0.0)),
		"route_progress_units": float(record.get("route_progress_units", 0.0)),
		"progress_rate_units_per_min": float(record.get("progress_rate_units_per_min", 0.0)),
		"mean_alt_error_m": float(record.get("mean_alt_error_m", INF)),
		"min_agl_m": float(record.get("min_agl_m", INF)),
		"crashed": bool(record.get("crashed", false)),
		"genome": genome,
	}
	var default_path: String = _get_default_pilot_path()
	var wrote_best: bool = _write_json_file(_get_best_pilot_path(), state)
	var wrote_default: bool = _write_json_file(default_path, state)
	if wrote_best or wrote_default:
		_best_saved_score = score
		_best_saved_generation = _generation_index
		_best_saved_genome = genome.duplicate(true)
		_best_saved_record = record.duplicate(true)
		_log_event("SAVED_DEFAULT_PILOT generation=%d id=%d score=%.1f weapon=%s bomb_min_miss=%.1f gun_min=%.1f path=%s genome=%s" % [
			_generation_index,
			int(record.get("trial_id", -1)),
			score,
			_get_pilot_mode_name(),
			bomb_min_miss_m,
			gun_min_edge_miss_m,
			ProjectSettings.globalize_path(default_path),
			_format_genome(genome),
		])

func _get_score_schema_version() -> int:
	if not attack_phase_enabled:
		return NAVIGATION_SCORE_SCHEMA_VERSION
	if _attack_is_mixed_mode():
		return MIXED_ATTACK_SCORE_SCHEMA_VERSION
	return 1

func _get_pilot_mode_name() -> String:
	return "Navigation" if not attack_phase_enabled else attack_test_weapon_mode

func _get_pilot_save_suffix() -> String:
	return _get_pilot_mode_name().to_lower()

func _get_best_pilot_path() -> String:
	return "user://airplane_test_best_pilot_%s.json" % _get_pilot_save_suffix()

func _get_default_pilot_path() -> String:
	return "user://airplane_test_default_pilot_%s.json" % _get_pilot_save_suffix()

func _write_json_file(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[AirplaneTest] Could not save %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

func _log_generation_ranking(records: Array[Dictionary]) -> void:
	if records.is_empty():
		return
	var top_count: int = mini(3, records.size())
	for rank in range(top_count):
		_log_rank_record("GENERATION_RANK", rank + 1, records[rank])
	if records.size() > top_count:
		_log_rank_record("GENERATION_WORST", records.size(), records[records.size() - 1])

func _log_rank_record(prefix: String, rank: int, record: Dictionary) -> void:
	_log_event("%s generation=%d rank=%d id=%d score=%.1f lap_complete=%s eval=%s duration=%.1f progress=%.2f rate=%.2f mean_x=%.1f max_x=%.1f mean_alt=%.1f high=%.1f low=%.1f high_frac=%.2f low_frac=%.2f speed_err=%.1f overspeed=%.1f max_over=%.1f over_frac=%.2f brake=%.2f limited=%.2f weapon=%s attack_launches=%d attack_impacts=%d attack_hits=%d attack_direct=%d attack_min_miss=%.1f stalls=%d lineup_retries=%d terrain_aborts=%d rockets=%d tight=%d after_best=%d last=%d rocket_impacts=%d rocket_hits=%d rocket_direct=%d rocket_min_miss=%.1f bombs=%d bomb_impacts=%d bomb_hits=%d bomb_direct=%d bomb_min_miss=%.1f gun_shots=%d gun_reports=%d gun_hits=%d gun_min=%.1f gun_mean=%.1f gun_aim_n=%d gun_aim_mean=%.1f gun_aim_min=%.1f gun_aim_good=%.2f gun_aim_first=%.1f gun_aim_dive_first=%.1f ccip_samples=%d ccip_mean=%.1f ccip_min=%.1f ccip_right=%.1f ccip_fwd=%.1f ccip_pitch=%.3f ccip_yaw=%.3f resyncs=%d crashed=%s genome=%s" % [
		prefix,
		_generation_index,
		rank,
		int(record.get("trial_id", -1)),
		float(record.get("score", INF)),
		str(record.get("lap_completed", false)),
		str(record.get("evaluation_reason", "unknown")),
		float(record.get("evaluation_duration_s", 0.0)),
		float(record.get("route_progress_units", 0.0)),
		float(record.get("progress_rate_units_per_min", 0.0)),
		float(record.get("mean_xtrack_m", INF)),
		float(record.get("max_xtrack_m", 0.0)),
		float(record.get("mean_alt_error_m", INF)),
		float(record.get("mean_high_alt_error_m", 0.0)),
		float(record.get("mean_low_alt_error_m", 0.0)),
		float(record.get("high_alt_fraction", 0.0)),
		float(record.get("low_alt_fraction", 0.0)),
		float(record.get("mean_speed_error_mps", INF)),
		float(record.get("mean_overspeed_mps", 0.0)),
		float(record.get("max_overspeed_mps", 0.0)),
		float(record.get("overspeed_fraction", 0.0)),
		float(record.get("mean_route_turn_brake", 0.0)),
		float(record.get("turn_limited_fraction", 0.0)),
		attack_test_weapon_mode,
		int(record.get("attack_launches", 0)),
		int(record.get("attack_impacts", 0)),
		int(record.get("attack_hits", 0)),
		int(record.get("attack_direct_hits", 0)),
		float(record.get("attack_min_miss_m", INF)),
		int(record.get("attack_stalled_runs", 0)),
		int(record.get("attack_lineup_retries", 0)),
		int(record.get("attack_terrain_emergency_runs", 0)),
		int(record.get("rocket_launches", 0)),
		int(record.get("rocket_tight_launches", 0)),
		int(record.get("rocket_after_best_launches", 0)),
		int(record.get("rocket_last_chance_launches", 0)),
		int(record.get("rocket_impacts", 0)),
		int(record.get("rocket_hits", 0)),
		int(record.get("rocket_direct_hits", 0)),
		float(record.get("rocket_min_miss_m", INF)),
		int(record.get("bomb_drops", 0)),
		int(record.get("bomb_impacts", 0)),
		int(record.get("bomb_hits", 0)),
		int(record.get("bomb_direct_hits", 0)),
		float(record.get("bomb_min_miss_m", INF)),
		int(record.get("gun_shots", 0)),
		int(record.get("gun_reports", 0)),
		int(record.get("gun_hits", 0)),
		float(record.get("gun_min_edge_miss_m", INF)),
		float(record.get("gun_mean_edge_miss_m", INF)),
		int(record.get("gun_aim_samples", 0)),
		float(record.get("gun_aim_mean_angle_deg", INF)),
		float(record.get("gun_aim_min_angle_deg", INF)),
		float(record.get("gun_aim_good_fraction", 0.0)),
		float(record.get("gun_aim_first_good_time_s", INF)),
		float(record.get("gun_aim_first_good_dive_time_s", INF)),
		int(record.get("rocket_ccip_samples", 0)),
		float(record.get("rocket_ccip_mean_miss_m", INF)),
		float(record.get("rocket_ccip_min_miss_m", INF)),
		float(record.get("rocket_ccip_mean_abs_right_m", INF)),
		float(record.get("rocket_ccip_mean_abs_forward_m", INF)),
		float(record.get("rocket_ccip_mean_abs_pitch_cmd", 0.0)),
		float(record.get("rocket_ccip_mean_abs_yaw_cmd", 0.0)),
		int(record.get("route_resync_count", 0)),
		str(record.get("crashed", false)),
		_format_genome(record.get("genome", {}) as Dictionary),
	])
	if not attack_phase_enabled:
		_log_event("NAVIGATION_RANK_DETAIL generation=%d rank=%d id=%d capture=%.1f settle=%.1f corridor=%.3f mean_path=%.1f settled_path=%.1f settled_max=%.1f pre_area=%.1f control_delta=%.3f settled_control=%.3f" % [
			_generation_index,
			rank,
			int(record.get("trial_id", -1)),
			float(record.get("navigation_capture_first_time_s", INF)),
			float(record.get("navigation_capture_settled_time_s", INF)),
			float(record.get("navigation_capture_corridor_fraction", 0.0)),
			float(record.get("mean_path_error_m", INF)),
			float(record.get("navigation_settled_mean_path_error_m", INF)),
			float(record.get("navigation_settled_max_path_error_m", 0.0)),
			float(record.get("navigation_pre_capture_error_area", 0.0)),
			float(record.get("mean_control_input_delta", 0.0)),
			float(record.get("navigation_settled_mean_control_delta", 0.0)),
		])

func _score_trial(trial: Dictionary) -> Dictionary:
	var samples: int = int(trial.get("samples", 0))
	var mean_xtrack_m: float = INF
	var mean_alt_error_m: float = INF
	var mean_high_alt_error_m: float = 0.0
	var mean_low_alt_error_m: float = 0.0
	var mean_speed_error_mps: float = INF
	var mean_overspeed_mps: float = 0.0
	var overspeed_fraction: float = 0.0
	var turn_limited_fraction: float = 0.0
	var mean_route_turn_brake: float = 0.0
	if samples > 0:
		mean_xtrack_m = float(trial.get("sum_cross_track_m", 0.0)) / float(samples)
		mean_alt_error_m = float(trial.get("sum_abs_alt_error_m", 0.0)) / float(samples)
		mean_high_alt_error_m = float(trial.get("sum_high_alt_error_m", 0.0)) / float(samples)
		mean_low_alt_error_m = float(trial.get("sum_low_alt_error_m", 0.0)) / float(samples)
		mean_speed_error_mps = float(trial.get("sum_speed_error_mps", 0.0)) / float(samples)
		mean_overspeed_mps = float(trial.get("sum_overspeed_mps", 0.0)) / float(samples)
		overspeed_fraction = float(trial.get("overspeed_samples", 0)) / float(samples)
		turn_limited_fraction = float(trial.get("turn_limited_samples", 0)) / float(samples)
		mean_route_turn_brake = float(trial.get("sum_route_turn_brake", 0.0)) / float(samples)
	var mean_abs_sideslip: float = 0.0
	var mean_abs_lateral_accel_g: float = 0.0
	var mean_abs_yaw_input: float = 0.0
	var yaw_saturation_fraction: float = 0.0
	if samples > 0:
		mean_abs_sideslip = float(trial.get("sum_abs_sideslip", 0.0)) / float(samples)
		mean_abs_lateral_accel_g = float(trial.get("sum_abs_lateral_accel_g", 0.0)) / float(samples)
		mean_abs_yaw_input = float(trial.get("sum_abs_yaw_input", 0.0)) / float(samples)
		yaw_saturation_fraction = float(trial.get("yaw_saturated_samples", 0)) / float(samples)
	var max_abs_sideslip: float = float(trial.get("max_abs_sideslip", 0.0))
	var max_abs_lateral_accel_g: float = float(trial.get("max_abs_lateral_accel_g", 0.0))
	var max_xtrack_m: float = float(trial.get("max_cross_track_m", 0.0))
	var max_high_alt_error_m: float = float(trial.get("max_high_alt_error_m", 0.0))
	var max_low_alt_error_m: float = float(trial.get("max_low_alt_error_m", 0.0))
	var high_alt_fraction: float = 0.0
	var low_alt_fraction: float = 0.0
	var max_overspeed_mps: float = float(trial.get("max_overspeed_mps", 0.0))
	var max_route_turn_brake: float = float(trial.get("max_route_turn_brake", 0.0))
	if samples > 0:
		high_alt_fraction = float(trial.get("high_alt_samples", 0)) / float(samples)
		low_alt_fraction = float(trial.get("low_alt_samples", 0)) / float(samples)
	var min_agl_m: float = float(trial.get("min_agl_m", INF))
	var laps: int = int(trial.get("completed_laps", 0))
	var lap_completed: bool = bool(trial.get("lap_completed", false))
	var evaluation_reason: String = str(trial.get("evaluation_reason", "running"))
	var route_progress_units: float = float(trial.get("route_progress_units", 0.0))
	var spawn_time_s: float = float(trial.get("spawn_time_s", _elapsed_s))
	var evaluation_end_s: float = float(trial.get("evaluation_end_time_s", -1.0))
	if evaluation_end_s < spawn_time_s:
		evaluation_end_s = _elapsed_s
	var evaluation_duration_s: float = maxf(evaluation_end_s - spawn_time_s, 0.0)
	var age_s: float = maxf(evaluation_duration_s, 1.0)
	var progress_rate_units_per_min: float = route_progress_units / age_s * 60.0
	var mean_cross_track_delta_m: float = 0.0
	if samples > 1:
		mean_cross_track_delta_m = float(trial.get("sum_cross_track_delta_m", 0.0)) / float(samples - 1)
	var max_cross_track_delta_m: float = float(trial.get("max_cross_track_delta_m", 0.0))
	var route_projection_bad_fraction: float = 0.0
	var route_projection_advance_fraction: float = 0.0
	if samples > 0:
		route_projection_bad_fraction = float(trial.get("route_projection_bad_samples", 0)) / float(samples)
		route_projection_advance_fraction = float(trial.get("route_projection_advance_count", 0)) / float(samples)
	var route_resync_count: int = int(trial.get("route_resync_count", 0))
	var route_resync_adjacent_forward_count: int = int(trial.get("route_resync_adjacent_forward_count", 0))
	var route_resync_disqualifying_count: int = int(trial.get("route_resync_disqualifying_count", 0))
	var mean_path_error_m: float = INF
	var navigation_capture_corridor_fraction: float = 0.0
	var mean_control_input_delta: float = 0.0
	if samples > 0:
		mean_path_error_m = float(trial.get("sum_path_error_m", 0.0)) / float(samples)
		navigation_capture_corridor_fraction = float(trial.get("navigation_capture_corridor_samples", 0)) / float(samples)
	if samples > 1:
		mean_control_input_delta = float(trial.get("sum_control_input_delta", 0.0)) / float(samples - 1)
	var navigation_capture_first_time_s: float = float(trial.get("navigation_capture_first_time_s", INF))
	var navigation_capture_settled_time_s: float = float(trial.get("navigation_capture_settled_time_s", INF))
	var navigation_pre_capture_error_area: float = float(trial.get("navigation_pre_capture_error_area", 0.0))
	var navigation_settled_samples: int = int(trial.get("navigation_settled_samples", 0))
	var navigation_settled_mean_path_error_m: float = INF
	var navigation_settled_mean_control_delta: float = 0.0
	if navigation_settled_samples > 0:
		navigation_settled_mean_path_error_m = float(trial.get("navigation_settled_sum_path_error_m", 0.0)) / float(navigation_settled_samples)
		navigation_settled_mean_control_delta = float(trial.get("navigation_settled_sum_control_delta", 0.0)) / float(navigation_settled_samples)
	var navigation_settled_max_path_error_m: float = float(trial.get("navigation_settled_max_path_error_m", 0.0))
	var navigation_settled_max_control_delta: float = float(trial.get("navigation_settled_max_control_delta", 0.0))
	var max_control_input_delta: float = float(trial.get("max_control_input_delta", 0.0))
	var attack_started: bool = bool(trial.get("attack_started", false))
	var committed_attack_runs: int = int(trial.get("committed_attack_runs", 0))
	var dry_attack_runs: int = int(trial.get("dry_attack_runs", 0))
	var attack_stalled_runs: int = int(trial.get("attack_stalled_runs", 0))
	var attack_lineup_retries: int = int(trial.get("attack_lineup_retries", 0))
	var attack_terrain_emergency_runs: int = int(trial.get("attack_terrain_emergency_runs", 0))
	var rocket_launches: int = int(trial.get("rocket_launches", 0))
	var rocket_tight_launches: int = int(trial.get("rocket_tight_launches", 0))
	var rocket_after_best_launches: int = int(trial.get("rocket_after_best_launches", 0))
	var rocket_last_chance_launches: int = int(trial.get("rocket_last_chance_launches", 0))
	var rocket_impacts: int = int(trial.get("rocket_impacts", 0))
	var rocket_hits: int = int(trial.get("rocket_hits", 0))
	var rocket_direct_hits: int = int(trial.get("rocket_direct_hits", 0))
	var rocket_min_miss_m: float = float(trial.get("rocket_min_miss_m", INF))
	var rocket_mean_miss_m: float = INF
	if rocket_impacts > 0:
		rocket_mean_miss_m = float(trial.get("rocket_sum_miss_m", 0.0)) / float(rocket_impacts)
	var bomb_drops: int = int(trial.get("bomb_drops", 0))
	var bomb_impacts: int = int(trial.get("bomb_impacts", 0))
	var bomb_hits: int = int(trial.get("bomb_hits", 0))
	var bomb_direct_hits: int = int(trial.get("bomb_direct_hits", 0))
	var bomb_min_miss_m: float = float(trial.get("bomb_min_miss_m", INF))
	var bomb_mean_miss_m: float = INF
	if bomb_impacts > 0:
		bomb_mean_miss_m = float(trial.get("bomb_sum_miss_m", 0.0)) / float(bomb_impacts)
	var gun_shots: int = int(trial.get("gun_shots", 0))
	var gun_reports: int = int(trial.get("gun_reports", 0))
	var gun_hits: int = int(trial.get("gun_hits", 0))
	var gun_min_edge_miss_m: float = float(trial.get("gun_min_edge_miss_m", INF))
	var gun_mean_edge_miss_m: float = INF
	if gun_reports > 0:
		gun_mean_edge_miss_m = float(trial.get("gun_sum_edge_miss_m", 0.0)) / float(gun_reports)
	var gun_aim_samples: int = int(trial.get("gun_aim_samples", 0))
	var gun_aim_mean_angle_deg: float = INF
	var gun_aim_min_angle_deg: float = float(trial.get("gun_aim_min_angle_deg", INF))
	var gun_aim_good_samples: int = int(trial.get("gun_aim_good_samples", 0))
	var gun_aim_good_fraction: float = 0.0
	var gun_aim_first_good_time_s: float = float(trial.get("gun_aim_first_good_time_s", INF))
	var gun_aim_first_good_dive_time_s: float = float(trial.get("gun_aim_first_good_dive_time_s", INF))
	if gun_aim_samples > 0:
		gun_aim_mean_angle_deg = float(trial.get("gun_aim_sum_angle_deg", 0.0)) / float(gun_aim_samples)
		gun_aim_good_fraction = float(gun_aim_good_samples) / float(gun_aim_samples)
	var attack_launches: int = rocket_launches + bomb_drops
	var attack_impacts: int = rocket_impacts + bomb_impacts
	var attack_hits: int = rocket_hits + bomb_hits
	var attack_direct_hits: int = rocket_direct_hits + bomb_direct_hits
	var attack_min_miss_m: float = minf(rocket_min_miss_m, bomb_min_miss_m)
	var attack_sum_miss_m: float = float(trial.get("rocket_sum_miss_m", 0.0)) + float(trial.get("bomb_sum_miss_m", 0.0))
	if _attack_uses_guns():
		if _attack_is_mixed_mode():
			attack_launches += gun_shots
			attack_impacts += gun_reports
			attack_hits += gun_hits
			attack_direct_hits += gun_hits
			attack_min_miss_m = minf(attack_min_miss_m, gun_min_edge_miss_m)
			attack_sum_miss_m += float(trial.get("gun_sum_edge_miss_m", 0.0))
		else:
			attack_launches = gun_shots
			attack_impacts = gun_reports
			attack_hits = gun_hits
			attack_direct_hits = gun_hits
			attack_min_miss_m = gun_min_edge_miss_m
			attack_sum_miss_m = float(trial.get("gun_sum_edge_miss_m", 0.0))
	var attack_mean_miss_m: float = INF
	if attack_impacts > 0:
		attack_mean_miss_m = attack_sum_miss_m / float(attack_impacts)
	var rocket_ccip_samples: int = int(trial.get("rocket_ccip_samples", 0))
	var rocket_ccip_mean_miss_m: float = INF
	var rocket_ccip_min_miss_m: float = float(trial.get("rocket_ccip_min_miss_m", INF))
	var rocket_ccip_mean_abs_right_m: float = INF
	var rocket_ccip_mean_abs_forward_m: float = INF
	var rocket_ccip_mean_abs_pitch_cmd: float = 0.0
	var rocket_ccip_mean_abs_yaw_cmd: float = 0.0
	if rocket_ccip_samples > 0:
		var ccip_sample_count: float = float(rocket_ccip_samples)
		rocket_ccip_mean_miss_m = float(trial.get("rocket_ccip_sum_miss_m", 0.0)) / ccip_sample_count
		rocket_ccip_mean_abs_right_m = float(trial.get("rocket_ccip_sum_abs_right_m", 0.0)) / ccip_sample_count
		rocket_ccip_mean_abs_forward_m = float(trial.get("rocket_ccip_sum_abs_forward_m", 0.0)) / ccip_sample_count
		rocket_ccip_mean_abs_pitch_cmd = float(trial.get("rocket_ccip_sum_abs_pitch_cmd", 0.0)) / ccip_sample_count
		rocket_ccip_mean_abs_yaw_cmd = float(trial.get("rocket_ccip_sum_abs_yaw_cmd", 0.0)) / ccip_sample_count
	var crashed: bool = bool(trial.get("crashed", false)) or bool(trial.get("destroyed", false))
	var score: float = (
		mean_xtrack_m
		+ mean_alt_error_m * 1.1
		+ mean_high_alt_error_m * 0.8
		+ mean_low_alt_error_m * 1.5
		+ max_high_alt_error_m * 0.16
		+ max_low_alt_error_m * 0.55
		+ high_alt_fraction * 260.0
		+ low_alt_fraction * 650.0
		+ mean_speed_error_mps * 3.0
		+ mean_overspeed_mps * 8.0
		+ max_overspeed_mps * 2.0
		+ overspeed_fraction * 320.0
		+ max_xtrack_m * 0.34
		+ maxf(mean_xtrack_m - 120.0, 0.0) * 1.15
		+ maxf(max_xtrack_m - 420.0, 0.0) * 0.85
		+ mean_cross_track_delta_m * 3.2
		+ max_cross_track_delta_m * 0.48
		+ maxf(max_cross_track_delta_m - 180.0, 0.0) * 1.1
		+ mean_abs_sideslip * 900.0
		+ max_abs_sideslip * 280.0
		+ mean_abs_yaw_input * 70.0
		+ yaw_saturation_fraction * 260.0
		+ mean_abs_lateral_accel_g * 140.0
		+ max_abs_lateral_accel_g * 35.0
		+ mean_route_turn_brake * 70.0
		+ max_route_turn_brake * 45.0
		+ turn_limited_fraction * 28.0
		+ route_projection_bad_fraction * 520.0
		+ route_projection_advance_fraction * 760.0
		+ float(route_resync_count) * 160.0
	)
	score -= route_progress_units * 22.0
	score -= progress_rate_units_per_min * 15.0
	if route_progress_units < 12.0:
		score += (12.0 - route_progress_units) * 520.0
	if progress_rate_units_per_min < 3.5:
		score += (3.5 - progress_rate_units_per_min) * 900.0
	# Margin incentive: reward flying with altitude to spare, not just surviving. As the GA breeds
	# toward aggression, later generations creep the crash rate up by skating the ground. Penalize
	# low-margin flight among survivors so the GA prefers pilots that are aggressive AND leave
	# themselves room, pulling the crash rate down without hard limits or timidity.
	if min_agl_m < 500.0:
		score += (500.0 - min_agl_m) * 3.5   # was 2.2 -- steeper cost for close terrain passes
	if min_agl_m < 180.0:
		score += (180.0 - min_agl_m) * 16.0  # was 8.0 -- hard cost for genuinely scary min AGL
	# Sustained time flown well below the target route altitude (>120m low) is the strongest
	# "skating the edge" signal a survivor shows. Penalize the fraction of the run spent there.
	score += low_alt_fraction * 9000.0
	score += float(trial.get("low_alt_samples", 0)) * 15.0
	if _uses_full_lap_evaluation() and not lap_completed:
		var required_progress_units: float = float(_base_route.size() * maxi(full_lap_required_laps, 1))
		var missing_progress_units: float = maxf(required_progress_units - route_progress_units, 0.0)
		score += 6000.0 + missing_progress_units * 420.0
	if crashed:
		# Was 8000 -- too cheap next to a good attacker's ~-49000, so the GA happily bred pilots
		# that crash sometimes. Make a crash genuinely costly so surviving beats a dead high-scorer,
		# reversing the crash-rate creep over a long run. Ranking still hard-prefers survivors; this
		# shapes which SURVIVORS' close relatives (crashers) look bad enough to stop breeding.
		score += 45000.0
	if samples < 20:
		score += 2500.0
	if not attack_phase_enabled:
		# Reward decisive convergence separately from steady-state line holding.
		# The shared score above still rejects unsafe or energy-wasting shortcuts.
		score += mean_xtrack_m * 1.4
		score += max_xtrack_m * 0.20
		score += mean_cross_track_delta_m * 1.5
		score += mean_path_error_m * 2.5
		score += navigation_pre_capture_error_area * 0.08
		score += (1.0 - navigation_capture_corridor_fraction) * 900.0
		score += mean_control_input_delta * 450.0
		score += max_control_input_delta * 35.0
		if is_finite(navigation_capture_first_time_s):
			score += navigation_capture_first_time_s * 20.0
		else:
			score += 20000.0
		if is_finite(navigation_capture_settled_time_s):
			score += navigation_capture_settled_time_s * 30.0
			score += navigation_settled_mean_path_error_m * 5.0
			score += navigation_settled_max_path_error_m * 0.25
			score += navigation_settled_mean_control_delta * 800.0
			score += navigation_settled_max_control_delta * 120.0
		else:
			score += 16000.0
	if attack_phase_enabled and attack_started:
		score += float(dry_attack_runs) * 2200.0
		score += float(attack_stalled_runs) * 3200.0
		score += float(attack_lineup_retries) * 650.0
		score += float(attack_terrain_emergency_runs) * 2400.0
		if attack_launches <= 0:
			score += 3200.0
		else:
			var launch_hit_fraction: float = float(attack_hits) / float(maxi(attack_launches, 1))
			var direct_hit_fraction: float = float(attack_direct_hits) / float(maxi(attack_launches, 1))
			var last_chance_fraction: float = float(rocket_last_chance_launches) / float(maxi(rocket_launches, 1)) if rocket_launches > 0 else 0.0
			var confident_launch_fraction: float = float(rocket_tight_launches + rocket_after_best_launches) / float(maxi(rocket_launches, 1)) if rocket_launches > 0 else 1.0
			score += last_chance_fraction * 1800.0
			score -= confident_launch_fraction * 260.0
			if attack_hits <= 0:
				score += 2800.0
			elif launch_hit_fraction < 0.25:
				score += (0.25 - launch_hit_fraction) * 3400.0
			score -= launch_hit_fraction * 900.0
			score -= direct_hit_fraction * 1100.0
		if _attack_is_mixed_mode():
			var missing_weapon_phases: int = 0
			if bomb_drops <= 0:
				missing_weapon_phases += 1
			if rocket_launches <= 0:
				missing_weapon_phases += 1
			if gun_shots <= 0:
				missing_weapon_phases += 1
			score += float(missing_weapon_phases) * mixed_score_missing_weapon_phase_penalty
			if rocket_launches > 0 and rocket_launches < mixed_score_min_rocket_launches:
				score += float(mixed_score_min_rocket_launches - rocket_launches) * 320.0
			if gun_shots > 0 and gun_shots < mixed_score_min_gun_shots:
				score += float(mixed_score_min_gun_shots - gun_shots) * 95.0
			score -= float(mini(bomb_hits, 2)) * mixed_score_per_weapon_hit_bonus
			score -= float(mini(rocket_hits, 2)) * mixed_score_per_weapon_hit_bonus
			score -= float(mini(gun_hits, 8)) * mixed_score_per_weapon_hit_bonus
			if bomb_hits > 0 and rocket_hits > 0 and gun_hits > 0:
				score -= mixed_score_complete_all_weapons_bonus
		if _attack_uses_rockets() and rocket_ccip_samples <= 0:
			score += 900.0
		elif rocket_ccip_samples > 0:
			score += minf(rocket_ccip_mean_miss_m, 1200.0) * 0.70
			score += minf(rocket_ccip_min_miss_m, 1200.0) * 0.30
			score += minf(rocket_ccip_mean_abs_right_m, 600.0) * 0.18
			score += minf(rocket_ccip_mean_abs_forward_m, 600.0) * 0.18
			score += rocket_ccip_mean_abs_pitch_cmd * 110.0
			score += rocket_ccip_mean_abs_yaw_cmd * 130.0
		if attack_impacts <= 0:
			score += 1100.0
		else:
			score += minf(attack_mean_miss_m, 1200.0) * 0.55
			score += minf(attack_min_miss_m, 1200.0) * 0.35
			score -= float(attack_hits) * 260.0
			score -= float(attack_direct_hits) * 460.0
		if _attack_uses_bombs():
			if bomb_drops <= 0:
				score += 6500.0
			else:
				var expected_bomb_drops: int = 2
				if bomb_drops < expected_bomb_drops:
					score += float(expected_bomb_drops - bomb_drops) * 1400.0
				if bomb_impacts <= 0:
					score += 2500.0
				else:
					score += minf(bomb_mean_miss_m, 900.0) * 1.25
					score += minf(bomb_min_miss_m, 900.0) * 1.05
					score += maxf(bomb_min_miss_m - 80.0, 0.0) * 4.0
					score += maxf(bomb_mean_miss_m - 120.0, 0.0) * 2.0
					if bomb_min_miss_m <= 80.0:
						score -= 650.0
					if bomb_min_miss_m <= maxf(bomb_hit_radius_m, 0.0):
						score -= 1200.0
					score -= float(bomb_hits) * 900.0
					score -= float(bomb_direct_hits) * 1400.0
		if _attack_uses_guns():
			if gun_shots <= 0:
				score += 4200.0
			elif gun_shots < 35:
				score += float(35 - gun_shots) * 70.0
			if rocket_ccip_samples <= 0:
				score += 1600.0
			else:
				score += minf(rocket_ccip_mean_miss_m, 900.0) * 0.95
				score += minf(rocket_ccip_min_miss_m, 900.0) * 0.65
				score += minf(rocket_ccip_mean_abs_right_m, 450.0) * 0.22
				score += minf(rocket_ccip_mean_abs_forward_m, 450.0) * 0.22
			if gun_aim_samples <= 0:
				score += 1100.0
			else:
				score += minf(gun_aim_mean_angle_deg, 60.0) * 18.0
				score += minf(gun_aim_min_angle_deg, 60.0) * 22.0
				score -= gun_aim_good_fraction * 520.0
				if is_finite(gun_aim_first_good_dive_time_s):
					score += minf(gun_aim_first_good_dive_time_s, 12.0) * 70.0
				elif is_finite(gun_aim_first_good_time_s):
					score += minf(gun_aim_first_good_time_s, 18.0) * 45.0
				else:
					score += 900.0
			if gun_reports <= 0:
				score += 1500.0
			else:
				score += minf(gun_mean_edge_miss_m, 650.0) * 0.45
				score += minf(gun_min_edge_miss_m, 650.0) * 0.95
				if gun_min_edge_miss_m <= maxf(gun_hit_radius_m, 0.0):
					score -= 1100.0
				score -= float(mini(gun_hits, 24)) * 120.0
	return {
		"trial_id": int(trial.get("id", -1)),
		"score": score,
		"mean_xtrack_m": mean_xtrack_m,
		"mean_alt_error_m": mean_alt_error_m,
		"mean_high_alt_error_m": mean_high_alt_error_m,
		"mean_low_alt_error_m": mean_low_alt_error_m,
		"max_high_alt_error_m": max_high_alt_error_m,
		"max_low_alt_error_m": max_low_alt_error_m,
		"high_alt_fraction": high_alt_fraction,
		"low_alt_fraction": low_alt_fraction,
		"mean_speed_error_mps": mean_speed_error_mps,
		"mean_overspeed_mps": mean_overspeed_mps,
		"max_overspeed_mps": max_overspeed_mps,
		"overspeed_fraction": overspeed_fraction,
		"turn_limited_fraction": turn_limited_fraction,
		"mean_route_turn_brake": mean_route_turn_brake,
		"max_route_turn_brake": max_route_turn_brake,
		"mean_abs_sideslip": mean_abs_sideslip,
		"max_abs_sideslip": max_abs_sideslip,
		"mean_abs_yaw_input": mean_abs_yaw_input,
		"yaw_saturation_fraction": yaw_saturation_fraction,
		"mean_abs_lateral_accel_g": mean_abs_lateral_accel_g,
		"max_abs_lateral_accel_g": max_abs_lateral_accel_g,
		"max_xtrack_m": max_xtrack_m,
		"mean_xtrack_delta_m": mean_cross_track_delta_m,
		"max_xtrack_delta_m": max_cross_track_delta_m,
		"route_projection_bad_fraction": route_projection_bad_fraction,
		"route_projection_advance_fraction": route_projection_advance_fraction,
		"route_resync_count": route_resync_count,
		"route_resync_adjacent_forward_count": route_resync_adjacent_forward_count,
		"route_resync_disqualifying_count": route_resync_disqualifying_count,
		"mean_path_error_m": mean_path_error_m,
		"navigation_capture_first_time_s": navigation_capture_first_time_s,
		"navigation_capture_settled_time_s": navigation_capture_settled_time_s,
		"navigation_capture_corridor_fraction": navigation_capture_corridor_fraction,
		"navigation_pre_capture_error_area": navigation_pre_capture_error_area,
		"navigation_settled_samples": navigation_settled_samples,
		"navigation_settled_mean_path_error_m": navigation_settled_mean_path_error_m,
		"navigation_settled_max_path_error_m": navigation_settled_max_path_error_m,
		"mean_control_input_delta": mean_control_input_delta,
		"max_control_input_delta": max_control_input_delta,
		"navigation_settled_mean_control_delta": navigation_settled_mean_control_delta,
		"navigation_settled_max_control_delta": navigation_settled_max_control_delta,
		"min_agl_m": min_agl_m,
		"laps": laps,
		"lap_completed": lap_completed,
		"evaluation_reason": evaluation_reason,
		"evaluation_duration_s": evaluation_duration_s,
		"route_progress_units": route_progress_units,
		"progress_rate_units_per_min": progress_rate_units_per_min,
		"attack_started": attack_started,
		"committed_attack_runs": committed_attack_runs,
		"dry_attack_runs": dry_attack_runs,
		"attack_stalled_runs": attack_stalled_runs,
		"attack_lineup_retries": attack_lineup_retries,
		"attack_terrain_emergency_runs": attack_terrain_emergency_runs,
		"rocket_launches": rocket_launches,
		"rocket_tight_launches": rocket_tight_launches,
		"rocket_after_best_launches": rocket_after_best_launches,
		"rocket_last_chance_launches": rocket_last_chance_launches,
		"rocket_impacts": rocket_impacts,
		"rocket_hits": rocket_hits,
		"rocket_direct_hits": rocket_direct_hits,
		"rocket_min_miss_m": rocket_min_miss_m,
		"rocket_mean_miss_m": rocket_mean_miss_m,
		"bomb_drops": bomb_drops,
		"bomb_impacts": bomb_impacts,
		"bomb_hits": bomb_hits,
		"bomb_direct_hits": bomb_direct_hits,
		"bomb_min_miss_m": bomb_min_miss_m,
		"bomb_mean_miss_m": bomb_mean_miss_m,
		"gun_shots": gun_shots,
		"gun_reports": gun_reports,
		"gun_hits": gun_hits,
		"gun_min_edge_miss_m": gun_min_edge_miss_m,
		"gun_mean_edge_miss_m": gun_mean_edge_miss_m,
		"gun_aim_samples": gun_aim_samples,
		"gun_aim_mean_angle_deg": gun_aim_mean_angle_deg,
		"gun_aim_min_angle_deg": gun_aim_min_angle_deg,
		"gun_aim_good_fraction": gun_aim_good_fraction,
		"gun_aim_first_good_time_s": gun_aim_first_good_time_s,
		"gun_aim_first_good_dive_time_s": gun_aim_first_good_dive_time_s,
		"attack_launches": attack_launches,
		"attack_impacts": attack_impacts,
		"attack_hits": attack_hits,
		"attack_direct_hits": attack_direct_hits,
		"attack_min_miss_m": attack_min_miss_m,
		"attack_mean_miss_m": attack_mean_miss_m,
		"rocket_ccip_samples": rocket_ccip_samples,
		"rocket_ccip_mean_miss_m": rocket_ccip_mean_miss_m,
		"rocket_ccip_min_miss_m": rocket_ccip_min_miss_m,
		"rocket_ccip_mean_abs_right_m": rocket_ccip_mean_abs_right_m,
		"rocket_ccip_mean_abs_forward_m": rocket_ccip_mean_abs_forward_m,
		"rocket_ccip_mean_abs_pitch_cmd": rocket_ccip_mean_abs_pitch_cmd,
		"rocket_ccip_mean_abs_yaw_cmd": rocket_ccip_mean_abs_yaw_cmd,
		"crashed": crashed,
		"genome": trial.get("genome", {}),
	}

func _sample_route_following() -> void:
	for i in range(_trials.size()):
		var trial: Dictionary = _trials[i]
		if bool(trial.get("evaluation_complete", false)):
			continue
		if bool(trial.get("route_sync_pending", false)):
			continue
		if bool(trial.get("crashed", false)) or bool(trial.get("destroyed", false)):
			continue
		var aircraft: RigidBody3D = _get_trial_aircraft(trial)
		var pilot: AIPilot = _get_trial_pilot(trial)
		if aircraft == null or pilot == null or pilot.waypoints.is_empty():
			continue
		_sample_trial(i, trial, aircraft, pilot)

func _sample_trial(trial_index: int, trial: Dictionary, aircraft: RigidBody3D, pilot: AIPilot) -> void:
	_log_route_debug_if_changed(trial, aircraft, pilot)
	if _attack_phase_started:
		_configure_attack_tuning_context(aircraft, int(trial.get("id", -1)), _get_trial_attack_target(trial))
	var index: int = clampi(pilot.current_waypoint_index, 0, pilot.waypoints.size() - 1)
	var last_index: int = int(trial.get("last_waypoint_index", -1))
	var completed_laps: int = int(trial.get("completed_laps", 0))
	var lap_completed_this_sample: bool = false
	var final_waypoint_index: int = pilot.waypoints.size() - 1
	if last_index >= maxi(final_waypoint_index - 1, 0) and index <= 1:
		completed_laps += 1
		lap_completed_this_sample = completed_laps >= maxi(full_lap_required_laps, 1)
	trial["last_waypoint_index"] = index
	trial["completed_laps"] = completed_laps

	var current_pos: Vector3 = aircraft.global_position
	var prev_index: int = index - 1
	if prev_index < 0:
		prev_index = pilot.waypoints.size() - 1
	var seg_start: Vector3 = pilot.waypoints[prev_index]
	var seg_end: Vector3 = pilot.waypoints[index]
	var segment_error: Dictionary = _measure_segment_error(current_pos, seg_start, seg_end)
	var cross_track_m: float = float(segment_error.get("cross_track_m", 0.0))
	var alt_error_m: float = float(segment_error.get("alt_error_m", 0.0))
	var segment_t: float = float(segment_error.get("segment_t", 0.0))
	var ground_y: float = _sample_ground_height(current_pos)
	var agl_m: float = current_pos.y - ground_y if not is_nan(ground_y) else INF
	var speed_mps: float = aircraft.linear_velocity.length()
	var target_speed_mps: float = pilot.default_waypoint_speed_mps
	var commanded_speed_mps: float = pilot.target_speed
	var route_turn_limited: bool = pilot.is_route_turn_speed_limited()
	var route_turn_cap_mps: float = pilot.get_route_turn_speed_cap_mps()
	var route_turn_brake_t: float = pilot.get_route_turn_speed_brake_t()
	var speed_error_mps: float = absf(speed_mps - target_speed_mps)
	var overspeed_mps: float = maxf(speed_mps - target_speed_mps, 0.0)
	var high_alt_error_m: float = maxf(alt_error_m, 0.0)
	var low_alt_error_m: float = maxf(-alt_error_m, 0.0)
	var basis: Basis = aircraft.global_transform.basis
	var sideslip_ratio: float = 0.0
	if speed_mps > 1.0:
		sideslip_ratio = clampf(aircraft.linear_velocity.dot(basis.x) / speed_mps, -1.0, 1.0)
	var previous_velocity_value: Variant = trial.get("previous_velocity", Vector3.INF)
	var previous_time_s: float = float(trial.get("previous_sample_time_s", NAN))
	var lateral_accel_g: float = 0.0
	if previous_velocity_value is Vector3 and not is_nan(previous_time_s):
		var sample_dt_s: float = maxf(_elapsed_s - previous_time_s, 0.001)
		var acceleration: Vector3 = (aircraft.linear_velocity - (previous_velocity_value as Vector3)) / sample_dt_s
		lateral_accel_g = acceleration.dot(basis.x) / 9.80665

	var samples: int = int(trial.get("samples", 0)) + 1
	var sum_cross_track_m: float = float(trial.get("sum_cross_track_m", 0.0)) + cross_track_m
	var max_cross_track_m: float = maxf(float(trial.get("max_cross_track_m", 0.0)), cross_track_m)
	var sum_abs_alt_error_m: float = float(trial.get("sum_abs_alt_error_m", 0.0)) + absf(alt_error_m)
	var sum_high_alt_error_m: float = float(trial.get("sum_high_alt_error_m", 0.0)) + high_alt_error_m
	var max_high_alt_error_m: float = maxf(float(trial.get("max_high_alt_error_m", 0.0)), high_alt_error_m)
	var sum_low_alt_error_m: float = float(trial.get("sum_low_alt_error_m", 0.0)) + low_alt_error_m
	var max_low_alt_error_m: float = maxf(float(trial.get("max_low_alt_error_m", 0.0)), low_alt_error_m)
	var high_alt_samples: int = int(trial.get("high_alt_samples", 0)) + (1 if high_alt_error_m > 150.0 else 0)
	var low_alt_samples: int = int(trial.get("low_alt_samples", 0)) + (1 if low_alt_error_m > 120.0 else 0)
	var min_agl_m: float = minf(float(trial.get("min_agl_m", INF)), agl_m)
	var sum_speed_error_mps: float = float(trial.get("sum_speed_error_mps", 0.0)) + speed_error_mps
	var sum_overspeed_mps: float = float(trial.get("sum_overspeed_mps", 0.0)) + overspeed_mps
	var max_overspeed_mps: float = maxf(float(trial.get("max_overspeed_mps", 0.0)), overspeed_mps)
	var overspeed_samples: int = int(trial.get("overspeed_samples", 0)) + (1 if overspeed_mps > 8.0 else 0)
	var turn_limited_samples: int = int(trial.get("turn_limited_samples", 0)) + (1 if route_turn_limited else 0)
	var sum_route_turn_brake: float = float(trial.get("sum_route_turn_brake", 0.0)) + route_turn_brake_t
	var max_route_turn_brake: float = maxf(float(trial.get("max_route_turn_brake", 0.0)), route_turn_brake_t)
	var abs_sideslip: float = absf(sideslip_ratio)
	var abs_lateral_accel_g: float = absf(lateral_accel_g)
	var yaw_input_value: float = pilot.yaw_input
	var abs_yaw_input: float = absf(yaw_input_value)
	var sum_abs_sideslip: float = float(trial.get("sum_abs_sideslip", 0.0)) + abs_sideslip
	var max_abs_sideslip: float = maxf(float(trial.get("max_abs_sideslip", 0.0)), abs_sideslip)
	var sum_abs_yaw_input: float = float(trial.get("sum_abs_yaw_input", 0.0)) + abs_yaw_input
	var yaw_saturated_samples: int = int(trial.get("yaw_saturated_samples", 0))
	if abs_yaw_input >= 0.98:
		yaw_saturated_samples += 1
	var sum_abs_lateral_accel_g: float = float(trial.get("sum_abs_lateral_accel_g", 0.0)) + abs_lateral_accel_g
	var max_abs_lateral_accel_g: float = maxf(float(trial.get("max_abs_lateral_accel_g", 0.0)), abs_lateral_accel_g)
	var rocket_ccip_samples: int = int(trial.get("rocket_ccip_samples", 0))
	var rocket_ccip_sum_miss_m: float = float(trial.get("rocket_ccip_sum_miss_m", 0.0))
	var rocket_ccip_min_miss_m: float = float(trial.get("rocket_ccip_min_miss_m", INF))
	var rocket_ccip_sum_abs_right_m: float = float(trial.get("rocket_ccip_sum_abs_right_m", 0.0))
	var rocket_ccip_sum_abs_forward_m: float = float(trial.get("rocket_ccip_sum_abs_forward_m", 0.0))
	var rocket_ccip_sum_abs_pitch_cmd: float = float(trial.get("rocket_ccip_sum_abs_pitch_cmd", 0.0))
	var rocket_ccip_sum_abs_yaw_cmd: float = float(trial.get("rocket_ccip_sum_abs_yaw_cmd", 0.0))
	var ccip_active: bool = pilot.is_rocket_ccip_aim_active()
	var ccip_miss_m: float = pilot.get_rocket_ccip_aim_miss_m()
	var ccip_right_m: float = pilot.get_rocket_ccip_aim_local_right_m()
	var ccip_forward_m: float = pilot.get_rocket_ccip_aim_local_forward_m()
	var ccip_pitch_cmd: float = pilot.get_rocket_ccip_aim_pitch_cmd()
	var ccip_yaw_cmd: float = pilot.get_rocket_ccip_aim_yaw_cmd()
	if _attack_uses_guns() and pilot.current_state == AIPilot.State.ATTACK_DIVE and pilot.is_gun_ccip_aim_active():
		ccip_active = true
		ccip_miss_m = pilot.get_gun_ccip_aim_miss_m()
		ccip_right_m = pilot.get_gun_ccip_aim_local_right_m()
		ccip_forward_m = pilot.get_gun_ccip_aim_local_forward_m()
		ccip_pitch_cmd = pilot.get_gun_ccip_aim_pitch_cmd()
		ccip_yaw_cmd = pilot.get_gun_ccip_aim_yaw_cmd()
	if ccip_active:
		rocket_ccip_samples += 1
		rocket_ccip_sum_miss_m += ccip_miss_m
		rocket_ccip_min_miss_m = minf(rocket_ccip_min_miss_m, ccip_miss_m)
		rocket_ccip_sum_abs_right_m += absf(ccip_right_m)
		rocket_ccip_sum_abs_forward_m += absf(ccip_forward_m)
		rocket_ccip_sum_abs_pitch_cmd += absf(ccip_pitch_cmd)
		rocket_ccip_sum_abs_yaw_cmd += absf(ccip_yaw_cmd)
	if _attack_uses_guns() and pilot.current_state == AIPilot.State.ATTACK_DIVE:
		var dive_start_s: float = float(trial.get("gun_aim_dive_start_time_s", INF))
		if not is_finite(dive_start_s):
			dive_start_s = _elapsed_s
			trial["gun_aim_dive_start_time_s"] = dive_start_s
		var aim_target: Node3D = _get_trial_attack_target(trial)
		if aim_target != null and is_instance_valid(aim_target):
			var aim_pos: Vector3 = aim_target.global_position + Vector3(0.0, 3.0, 0.0)
			var to_aim: Vector3 = aim_pos - aircraft.global_position
			if to_aim.length_squared() > 1.0:
				var aim_range_m: float = to_aim.length()
				var aim_dot: float = clampf(aircraft.global_transform.basis.z.normalized().dot(to_aim / aim_range_m), -1.0, 1.0)
				var aim_angle_deg: float = rad_to_deg(acos(aim_dot))
				if aim_range_m <= maxf(gun_test_max_range_m + 450.0, 50.0):
					var gun_aim_samples: int = int(trial.get("gun_aim_samples", 0)) + 1
					var gun_aim_sum_angle_deg: float = float(trial.get("gun_aim_sum_angle_deg", 0.0)) + aim_angle_deg
					var gun_aim_min_angle_deg: float = minf(float(trial.get("gun_aim_min_angle_deg", INF)), aim_angle_deg)
					var gun_aim_good_samples: int = int(trial.get("gun_aim_good_samples", 0))
					var first_good_s: float = float(trial.get("gun_aim_first_good_time_s", INF))
					var first_good_dive_s: float = float(trial.get("gun_aim_first_good_dive_time_s", INF))
					if aim_angle_deg <= 6.0:
						gun_aim_good_samples += 1
						if not is_finite(first_good_s):
							first_good_s = maxf(_elapsed_s - float(trial.get("attack_start_time_s", _elapsed_s)), 0.0)
						if not is_finite(first_good_dive_s):
							first_good_dive_s = maxf(_elapsed_s - dive_start_s, 0.0)
					trial["gun_aim_samples"] = gun_aim_samples
					trial["gun_aim_sum_angle_deg"] = gun_aim_sum_angle_deg
					trial["gun_aim_min_angle_deg"] = gun_aim_min_angle_deg
					trial["gun_aim_good_samples"] = gun_aim_good_samples
					trial["gun_aim_first_good_time_s"] = first_good_s
					trial["gun_aim_first_good_dive_time_s"] = first_good_dive_s
	var previous_cross_track_m: float = float(trial.get("previous_cross_track_m", NAN))
	var cross_track_delta_m: float = 0.0
	if not is_nan(previous_cross_track_m):
		cross_track_delta_m = absf(cross_track_m - previous_cross_track_m)
	var sum_cross_track_delta_m: float = float(trial.get("sum_cross_track_delta_m", 0.0)) + cross_track_delta_m
	var max_cross_track_delta_m: float = maxf(float(trial.get("max_cross_track_delta_m", 0.0)), cross_track_delta_m)
	var path_error_m: float = Vector2(cross_track_m, alt_error_m).length()
	var sum_path_error_m: float = float(trial.get("sum_path_error_m", 0.0)) + path_error_m
	var navigation_capture_first_time_s: float = float(trial.get("navigation_capture_first_time_s", INF))
	var navigation_capture_settled_time_s: float = float(trial.get("navigation_capture_settled_time_s", INF))
	var navigation_capture_consecutive_samples: int = int(trial.get("navigation_capture_consecutive_samples", 0))
	var navigation_capture_corridor_samples: int = int(trial.get("navigation_capture_corridor_samples", 0))
	var navigation_pre_capture_error_area: float = float(trial.get("navigation_pre_capture_error_area", 0.0))
	var navigation_settled_samples: int = int(trial.get("navigation_settled_samples", 0))
	var navigation_settled_sum_path_error_m: float = float(trial.get("navigation_settled_sum_path_error_m", 0.0))
	var navigation_settled_max_path_error_m: float = float(trial.get("navigation_settled_max_path_error_m", 0.0))
	var current_control_inputs: Vector3 = Vector3(pilot.roll_input, pilot.pitch_input, pilot.yaw_input)
	var previous_control_inputs: Vector3 = trial.get("previous_control_inputs", Vector3.INF) as Vector3
	var control_input_delta: float = 0.0
	if previous_control_inputs.is_finite():
		var control_delta_vector: Vector3 = (current_control_inputs - previous_control_inputs).abs()
		control_input_delta = control_delta_vector.x + control_delta_vector.y + control_delta_vector.z
	var sum_control_input_delta: float = float(trial.get("sum_control_input_delta", 0.0)) + control_input_delta
	var max_control_input_delta: float = maxf(float(trial.get("max_control_input_delta", 0.0)), control_input_delta)
	var navigation_settled_sum_control_delta: float = float(trial.get("navigation_settled_sum_control_delta", 0.0))
	var navigation_settled_max_control_delta: float = float(trial.get("navigation_settled_max_control_delta", 0.0))
	if not attack_phase_enabled:
		var navigation_age_s: float = maxf(_elapsed_s - float(trial.get("spawn_time_s", _elapsed_s)), 0.0)
		var navigation_sample_dt_s: float = maxf(_elapsed_s - previous_time_s, 0.001) if not is_nan(previous_time_s) else maxf(sample_interval_s, 0.1)
		var in_capture_corridor: bool = (
			cross_track_m <= navigation_capture_cross_track_m
			and absf(alt_error_m) <= navigation_capture_altitude_error_m
		)
		if in_capture_corridor:
			navigation_capture_corridor_samples += 1
			navigation_capture_consecutive_samples += 1
			if not is_finite(navigation_capture_first_time_s):
				navigation_capture_first_time_s = navigation_age_s
		else:
			navigation_capture_consecutive_samples = 0
		if (
			not is_finite(navigation_capture_settled_time_s)
			and navigation_capture_consecutive_samples >= maxi(navigation_capture_settle_samples, 1)
		):
			navigation_capture_settled_time_s = navigation_age_s
		if is_finite(navigation_capture_settled_time_s):
			navigation_settled_samples += 1
			navigation_settled_sum_path_error_m += path_error_m
			navigation_settled_max_path_error_m = maxf(navigation_settled_max_path_error_m, path_error_m)
			navigation_settled_sum_control_delta += control_input_delta
			navigation_settled_max_control_delta = maxf(navigation_settled_max_control_delta, control_input_delta)
		else:
			navigation_pre_capture_error_area += path_error_m * navigation_sample_dt_s
	var route_progress_units: float = float(completed_laps * pilot.waypoints.size()) + float(index) + segment_t
	trial["samples"] = samples
	trial["sum_cross_track_m"] = sum_cross_track_m
	trial["max_cross_track_m"] = max_cross_track_m
	trial["sum_abs_alt_error_m"] = sum_abs_alt_error_m
	trial["sum_high_alt_error_m"] = sum_high_alt_error_m
	trial["max_high_alt_error_m"] = max_high_alt_error_m
	trial["sum_low_alt_error_m"] = sum_low_alt_error_m
	trial["max_low_alt_error_m"] = max_low_alt_error_m
	trial["high_alt_samples"] = high_alt_samples
	trial["low_alt_samples"] = low_alt_samples
	trial["min_agl_m"] = min_agl_m
	trial["sum_speed_error_mps"] = sum_speed_error_mps
	trial["sum_overspeed_mps"] = sum_overspeed_mps
	trial["max_overspeed_mps"] = max_overspeed_mps
	trial["overspeed_samples"] = overspeed_samples
	trial["turn_limited_samples"] = turn_limited_samples
	trial["sum_route_turn_brake"] = sum_route_turn_brake
	trial["max_route_turn_brake"] = max_route_turn_brake
	trial["sum_abs_sideslip"] = sum_abs_sideslip
	trial["max_abs_sideslip"] = max_abs_sideslip
	trial["sum_abs_yaw_input"] = sum_abs_yaw_input
	trial["yaw_saturated_samples"] = yaw_saturated_samples
	trial["sum_abs_lateral_accel_g"] = sum_abs_lateral_accel_g
	trial["max_abs_lateral_accel_g"] = max_abs_lateral_accel_g
	trial["rocket_ccip_samples"] = rocket_ccip_samples
	trial["rocket_ccip_sum_miss_m"] = rocket_ccip_sum_miss_m
	trial["rocket_ccip_min_miss_m"] = rocket_ccip_min_miss_m
	trial["rocket_ccip_sum_abs_right_m"] = rocket_ccip_sum_abs_right_m
	trial["rocket_ccip_sum_abs_forward_m"] = rocket_ccip_sum_abs_forward_m
	trial["rocket_ccip_sum_abs_pitch_cmd"] = rocket_ccip_sum_abs_pitch_cmd
	trial["rocket_ccip_sum_abs_yaw_cmd"] = rocket_ccip_sum_abs_yaw_cmd
	trial["previous_velocity"] = aircraft.linear_velocity
	trial["previous_sample_time_s"] = _elapsed_s
	trial["previous_cross_track_m"] = cross_track_m
	trial["sum_cross_track_delta_m"] = sum_cross_track_delta_m
	trial["max_cross_track_delta_m"] = max_cross_track_delta_m
	trial["sum_path_error_m"] = sum_path_error_m
	trial["navigation_capture_first_time_s"] = navigation_capture_first_time_s
	trial["navigation_capture_settled_time_s"] = navigation_capture_settled_time_s
	trial["navigation_capture_consecutive_samples"] = navigation_capture_consecutive_samples
	trial["navigation_capture_corridor_samples"] = navigation_capture_corridor_samples
	trial["navigation_pre_capture_error_area"] = navigation_pre_capture_error_area
	trial["navigation_settled_samples"] = navigation_settled_samples
	trial["navigation_settled_sum_path_error_m"] = navigation_settled_sum_path_error_m
	trial["navigation_settled_max_path_error_m"] = navigation_settled_max_path_error_m
	trial["previous_control_inputs"] = current_control_inputs
	trial["sum_control_input_delta"] = sum_control_input_delta
	trial["max_control_input_delta"] = max_control_input_delta
	trial["navigation_settled_sum_control_delta"] = navigation_settled_sum_control_delta
	trial["navigation_settled_max_control_delta"] = navigation_settled_max_control_delta
	trial["route_progress_units"] = route_progress_units
	_trials[trial_index] = trial

	var state_name: String = AIPilot.State.keys()[pilot.current_state]
	var run_weapon_name: String = str(pilot.get("_run_weapon_type"))
	var dist_wp_m: float = current_pos.distance_to(pilot.nav_waypoint)
	var bank_deg: float = rad_to_deg(atan2(basis.x.y, basis.y.y))
	var route_projection_yaw_deg: float = rad_to_deg(pilot.get_route_forward_projection_yaw_error_rad())
	var route_fpv_yaw_deg: float = rad_to_deg(pilot.get_route_fpv_yaw_error_rad())
	var route_guidance_yaw_deg: float = rad_to_deg(pilot.get_route_guidance_yaw_error_rad())
	var route_capture_angle_deg: float = rad_to_deg(pilot.get_route_capture_angle_rad())
	var route_signed_cross_track_m: float = pilot.get_route_signed_cross_track_m()
	var route_projection_usable: bool = pilot.is_route_forward_projection_usable()
	var route_advance_reason: String = pilot.consume_route_advance_reason()
	var route_resync_reason: String = pilot.consume_route_resync_reason()
	var route_projection_bad_samples: int = int(trial.get("route_projection_bad_samples", 0))
	if not route_projection_usable:
		route_projection_bad_samples += 1
	var route_projection_advance_count: int = int(trial.get("route_projection_advance_count", 0))
	if route_advance_reason == "projection":
		route_projection_advance_count += 1
	var route_resync_count: int = int(trial.get("route_resync_count", 0))
	var route_resync_adjacent_forward_count: int = int(trial.get("route_resync_adjacent_forward_count", 0))
	var route_resync_disqualifying_count: int = int(trial.get("route_resync_disqualifying_count", 0))
	if route_resync_reason != "" and route_resync_reason != "none":
		route_resync_count += 1
		if _route_resync_is_adjacent_forward(route_resync_reason, pilot.waypoints.size()):
			route_resync_adjacent_forward_count += 1
		else:
			route_resync_disqualifying_count += 1
	trial["route_projection_bad_samples"] = route_projection_bad_samples
	trial["route_projection_advance_count"] = route_projection_advance_count
	trial["route_resync_count"] = route_resync_count
	trial["route_resync_adjacent_forward_count"] = route_resync_adjacent_forward_count
	trial["route_resync_disqualifying_count"] = route_resync_disqualifying_count
	_trials[trial_index] = trial
	var sample_ccip_active: bool = pilot.is_rocket_ccip_aim_active()
	var sample_ccip_blocked: bool = pilot.is_rocket_ccip_blocked()
	var sample_ccip_block_reason: String = pilot.get_rocket_ccip_block_reason()
	var sample_ccip_miss_m: float = pilot.get_rocket_ccip_aim_miss_m()
	var sample_ccip_right_m: float = pilot.get_rocket_ccip_aim_local_right_m()
	var sample_ccip_forward_m: float = pilot.get_rocket_ccip_aim_local_forward_m()
	var sample_ccip_pitch_cmd: float = pilot.get_rocket_ccip_aim_pitch_cmd()
	var sample_ccip_yaw_cmd: float = pilot.get_rocket_ccip_aim_yaw_cmd()
	if _attack_uses_guns() and pilot.current_state == AIPilot.State.ATTACK_DIVE and pilot.is_gun_ccip_aim_active():
		sample_ccip_active = true
		sample_ccip_blocked = pilot.is_gun_ccip_blocked()
		sample_ccip_block_reason = pilot.get_gun_ccip_block_reason()
		sample_ccip_miss_m = pilot.get_gun_ccip_aim_miss_m()
		sample_ccip_right_m = pilot.get_gun_ccip_aim_local_right_m()
		sample_ccip_forward_m = pilot.get_gun_ccip_aim_local_forward_m()
		sample_ccip_pitch_cmd = pilot.get_gun_ccip_aim_pitch_cmd()
		sample_ccip_yaw_cmd = pilot.get_gun_ccip_aim_yaw_cmd()
	_log_event("SAMPLE generation=%d id=%d t=%.1f age=%.1f state=%s run_weapon=%s attack_commit=%s attack_end=%s energy_recovery=%s lap=%d wp=%d/%d progress=%.2f speed=%.1f target_speed=%.1f cmd_speed=%.1f turn_cap=%.1f turn_brake=%.2f turn_limited=%s thr=%.2f pitch=%.2f fpv_pitch=%.1f turn_pull=%.3f agl=%.1f dist_wp=%.1f xtrack=%.1f sxtrack=%.1f dxtrack=%.1f slip=%.3f lat_g=%.2f yaw=%.2f route_yaw=%.1f route_fpv_yaw=%.1f route_guidance_yaw=%.1f route_capture=%.1f route_proj=%s bank=%.1f alt_err=%.1f adv=%s resync=%s ccip=%s ccip_blocked=%s ccip_block=%s ccip_miss=%.1f ccip_r=%.1f ccip_f=%.1f ccip_p=%.3f ccip_y=%.3f bomb_block=%s bomb_miss=%.1f bomb_best=%.1f bomb_alt=%.1f bomb_range=%.1f bomb_bank=%.1f bomb_fpa=%.1f bomb_ccip=%s bomb_stable=%.2f pos=%s nav=%s maneuver=%s" % [
		int(trial.get("generation", _generation_index)),
		int(trial.get("id", -1)),
		_elapsed_s,
		_elapsed_s - float(trial.get("spawn_time_s", _elapsed_s)),
		state_name,
		run_weapon_name,
		pilot.get_attack_last_commit_reason(),
		pilot.get_attack_last_end_reason(),
		str(pilot.is_attack_energy_recovery_active()),
		completed_laps,
		index + 1,
		pilot.waypoints.size(),
		route_progress_units,
		speed_mps,
		target_speed_mps,
		commanded_speed_mps,
		route_turn_cap_mps,
		route_turn_brake_t,
		str(route_turn_limited),
		pilot.throttle_input,
		pilot.pitch_input,
		rad_to_deg(pilot.get_route_fpv_pitch_error_rad()),
		pilot.get_navigation_turn_pull_command(),
		agl_m,
		dist_wp_m,
		cross_track_m,
		route_signed_cross_track_m,
		cross_track_delta_m,
		sideslip_ratio,
		lateral_accel_g,
		yaw_input_value,
		route_projection_yaw_deg,
		route_fpv_yaw_deg,
		route_guidance_yaw_deg,
		route_capture_angle_deg,
		str(route_projection_usable),
		bank_deg,
		alt_error_m,
		route_advance_reason,
		route_resync_reason,
		str(sample_ccip_active),
		str(sample_ccip_blocked),
		sample_ccip_block_reason,
		sample_ccip_miss_m,
		sample_ccip_right_m,
		sample_ccip_forward_m,
		sample_ccip_pitch_cmd,
		sample_ccip_yaw_cmd,
		pilot.get_last_bomb_release_block_reason(),
		pilot.get_last_bomb_release_miss_m(),
		pilot.get_last_bomb_release_best_miss_m(),
		pilot.get_last_bomb_release_alt_above_m(),
		pilot.get_last_bomb_release_range_m(),
		pilot.get_last_bomb_release_bank_deg(),
		pilot.get_last_bomb_release_fpa_deg(),
		str(pilot.last_bomb_release_has_ccip()),
		pilot.get_last_bomb_release_stable_s(),
		_fmt_v3(current_pos),
		_fmt_v3(pilot.nav_waypoint),
		_fmt_v3(pilot.maneuver_waypoint),
	])
	if _uses_full_lap_evaluation() and lap_completed_this_sample:
		_finish_trial_evaluation(trial_index, "lap_complete", true)

func _route_resync_is_adjacent_forward(reason: String, waypoint_count: int) -> bool:
	if waypoint_count <= 1:
		return false
	var parts: PackedStringArray = reason.split("_")
	if parts.size() < 4 or parts[0] != "resync" or parts[2] != "to":
		return false
	if not parts[1].is_valid_int() or not parts[3].is_valid_int():
		return false
	var from_index: int = int(parts[1])
	var to_index: int = int(parts[3])
	var expected_next: int = from_index + 1
	if expected_next > waypoint_count:
		expected_next = 1
	return to_index == expected_next

func _log_route_debug_if_changed(trial: Dictionary, aircraft: RigidBody3D, pilot: AIPilot) -> void:
	var snapshot: Dictionary = pilot.get_flight_plan_debug_snapshot()
	var revision: int = int(snapshot.get("revision", -1))
	var current_index: int = int(snapshot.get("current_index", -1))
	var previous_revision: int = int(trial.get("last_debug_route_revision", -1))
	var previous_index: int = int(trial.get("last_debug_route_index", -1))
	var plan_name: String = str(snapshot.get("plan_name", ""))
	var legs_value: Variant = snapshot.get("legs", [])
	var legs: Array = legs_value as Array if legs_value is Array else []
	if revision != previous_revision:
		var leg_descriptions: Array[String] = []
		for leg_index in range(legs.size()):
			var leg_value: Variant = legs[leg_index]
			if not (leg_value is Dictionary):
				continue
			var leg: Dictionary = leg_value as Dictionary
			var position_value: Variant = leg.get("position", Vector3.INF)
			var position: Vector3 = position_value as Vector3 if position_value is Vector3 else Vector3.INF
			var distance_m: float = Vector2(position.x - aircraft.global_position.x, position.z - aircraft.global_position.z).length() if position != Vector3.INF else INF
			var debug_tag: String = str(leg.get("debug_tag", ""))
			var role_label: String = str(leg.get("role", "waypoint"))
			if not debug_tag.is_empty():
				role_label += ":" + debug_tag
			leg_descriptions.append("%d:%s pos=%s dist=%.0f cap=%.0f turn=%.0f feasible=%s" % [
				leg_index + 1,
				role_label,
				_fmt_v3(position),
				distance_m,
				float(leg.get("capture_radius_m", NAN)),
				float(leg.get("turn_radius_m", NAN)),
				str(leg.get("turn_feasible", true)),
			])
		var thread_stats_value: Variant = snapshot.get("thread_stats", {})
		var thread_stats: Dictionary = thread_stats_value as Dictionary if thread_stats_value is Dictionary else {}
		_log_event("ROUTE_APPLIED generation=%d id=%d t=%.1f rev=%d plan=%s current=%d/%d pos=%s vel=%s raw=%d smooth=%d join_skip=%d departure_delta=%d legs=[%s]" % [
			int(trial.get("generation", _generation_index)),
			int(trial.get("id", -1)),
			_elapsed_s,
			revision,
			plan_name,
			current_index + 1,
			legs.size(),
			_fmt_v3(aircraft.global_position),
			_fmt_v3(aircraft.linear_velocity),
			int(thread_stats.get("input_points", 0)),
			int(thread_stats.get("output_points", 0)),
			int(thread_stats.get("async_join_skipped_legs", 0)),
			int(thread_stats.get("departure_leg_delta", 0)),
			"; ".join(leg_descriptions),
		])
		trial["last_debug_route_revision"] = revision
		previous_revision = revision
	if revision == previous_revision and current_index != previous_index and plan_name == "ground_attack":
		var active_role: String = "none"
		var active_position: Vector3 = Vector3.INF
		if current_index >= 0 and current_index < legs.size() and legs[current_index] is Dictionary:
			var active_leg: Dictionary = legs[current_index] as Dictionary
			active_role = str(active_leg.get("role", "waypoint"))
			var active_position_value: Variant = active_leg.get("position", Vector3.INF)
			if active_position_value is Vector3:
				active_position = active_position_value as Vector3
		var active_distance_m: float = Vector2(active_position.x - aircraft.global_position.x, active_position.z - aircraft.global_position.z).length() if active_position != Vector3.INF else INF
		_log_event("ROUTE_ADVANCE generation=%d id=%d t=%.1f rev=%d index=%d/%d role=%s pos=%s dist=%.0f reason=%s" % [
			int(trial.get("generation", _generation_index)),
			int(trial.get("id", -1)),
			_elapsed_s,
			revision,
			current_index + 1,
			legs.size(),
			active_role,
			_fmt_v3(active_position),
			active_distance_m,
			pilot.get_route_last_advance_reason(),
		])
	if plan_name == "ground_attack":
		var follow_debug: Dictionary = pilot.get_route_follow_debug_snapshot()
		_log_event("ROUTE_FOLLOW generation=%d id=%d t=%.1f rev=%d index=%d/%d role=%s carrot=%s dist=%.0f capture=%.0f proj_t=%.2f proj_x=%.0f proj_limit=%.0f hint=%d:%s decision=%s" % [
			int(trial.get("generation", _generation_index)),
			int(trial.get("id", -1)),
			_elapsed_s,
			revision,
			int(follow_debug.get("index", current_index)) + 1,
			legs.size(),
			str(follow_debug.get("role", "")),
			str(follow_debug.get("using_carrot", false)),
			float(follow_debug.get("distance_m", INF)),
			float(follow_debug.get("capture_m", 0.0)),
			float(follow_debug.get("projection_t", NAN)),
			float(follow_debug.get("projection_cross_track_m", INF)),
			float(follow_debug.get("projection_limit_m", 0.0)),
			int(follow_debug.get("suggested_index", -1)) + 1,
			str(follow_debug.get("suggested_reason", "")),
			str(follow_debug.get("decision", "hold")),
		])
	trial["last_debug_route_index"] = current_index

func _measure_segment_error(point: Vector3, start: Vector3, end: Vector3) -> Dictionary:
	var p: Vector2 = Vector2(point.x, point.z)
	var a: Vector2 = Vector2(start.x, start.z)
	var b: Vector2 = Vector2(end.x, end.z)
	var ab: Vector2 = b - a
	var ab_len_sq: float = ab.length_squared()
	var t: float = 0.0
	if ab_len_sq > 0.001:
		t = clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest: Vector2 = a + ab * t
	var target_y: float = lerpf(start.y, end.y, t)
	return {
		"cross_track_m": p.distance_to(closest),
		"alt_error_m": point.y - target_y,
		"segment_t": t,
	}

func _get_attack_waypoint_index() -> int:
	return _get_attack_waypoint_index_for_cycle(0)

func _get_attack_waypoint_index_for_cycle(cycle_index: int, route_size_override: int = -1) -> int:
	var route_size: int = route_size_override if route_size_override > 0 else _base_route.size()
	if route_size <= 0:
		return 0
	if _attack_is_mixed_mode() and not attack_mixed_cycle_waypoint_indices.is_empty():
		var sequence_index: int = posmod(cycle_index, attack_mixed_cycle_waypoint_indices.size())
		return clampi(int(attack_mixed_cycle_waypoint_indices[sequence_index]), 0, route_size - 1)
	return clampi(attack_circuit_waypoint_index, 0, route_size - 1)

func _schedule_next_attack_from_progress(trial: Dictionary, progress_units: float, force_next_lap: bool) -> void:
	var route_size: int = maxi(_get_trial_route(trial).size(), _base_route.size())
	if route_size <= 0:
		trial["next_attack_progress_units"] = INF
		return
	var attack_cycle_index: int = int(trial.get("attack_cycle_count", 0))
	var attack_index: int = _get_attack_waypoint_index_for_cycle(attack_cycle_index, route_size)
	var progress_lap: int = int(floor(progress_units / float(route_size)))
	var lap: int = maxi(progress_lap, int(trial.get("completed_laps", 0)))
	var next_progress: float = float(lap * route_size + attack_index)
	var force_later_lap: bool = force_next_lap
	if _attack_is_mixed_mode() and attack_cycle_index > 0:
		force_later_lap = false
	if force_later_lap or next_progress <= progress_units + 0.25:
		next_progress += float(route_size)
	trial["next_attack_progress_units"] = next_progress

func _measure_route_progress_units_for_position(route: Array[Dictionary], point: Vector3) -> float:
	if route.is_empty():
		return 0.0
	var best_score: float = INF
	var best_progress: float = 0.0
	for i in range(route.size()):
		var start_index: int = i - 1
		if start_index < 0:
			start_index = route.size() - 1
		var start_value: Variant = route[start_index].get("position", point)
		var end_value: Variant = route[i].get("position", point)
		if not (start_value is Vector3) or not (end_value is Vector3):
			continue
		var segment_error: Dictionary = _measure_segment_error(point, start_value as Vector3, end_value as Vector3)
		var cross_track_m: float = float(segment_error.get("cross_track_m", INF))
		var alt_error_m: float = absf(float(segment_error.get("alt_error_m", 0.0)))
		var score: float = cross_track_m + alt_error_m * 0.15
		if score < best_score:
			var segment_t: float = float(segment_error.get("segment_t", 0.0))
			best_score = score
			best_progress = float(start_index) + segment_t
			if start_index > i:
				best_progress = segment_t
	return best_progress

func _get_route_point(offset_x: float, offset_z: float, agl_m: float) -> Vector3:
	var base: Vector3 = Vector3(play_area_center.x + offset_x, play_area_center.y, play_area_center.z + offset_z)
	var ground_y: float = _sample_ground_height(base)
	if is_nan(ground_y):
		ground_y = play_area_center.y
	return Vector3(base.x, ground_y + agl_m, base.z)

func _sample_ground_height(world_pos: Vector3) -> float:
	if flat_arena_enabled:
		return flat_arena_ground_y
	if TerrainNavGrid != null and TerrainNavGrid.has_method("sample_height") and TerrainNavGrid.is_ready():
		var h: float = TerrainNavGrid.sample_height(world_pos.x, world_pos.z)
		if h > TerrainNavGrid.IMPASSABLE * 0.5:
			return h
	var terrain: Node = get_node_or_null("../LowPolyTerrainPrototype")
	if terrain == null:
		terrain = get_tree().current_scene.get_node_or_null("LowPolyTerrainPrototype") if get_tree().current_scene != null else null
	if terrain != null and terrain.has_method("get_height"):
		var value: Variant = terrain.call("get_height", world_pos)
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			return float(value)
	return NAN

func _find_grounded_attack_target_placement(desired_pos: Vector3) -> Dictionary:
	var best_eval: Dictionary = _evaluate_attack_target_footprint(desired_pos)
	var best_score: float = _score_attack_target_placement(desired_pos, best_eval)

	var radius: float = maxf(attack_target_flat_search_radius_m, 0.0)
	var step: float = maxf(attack_target_flat_search_step_m, 1.0)
	var rings: int = int(ceil(radius / step))
	for ring in range(1, rings + 1):
		var ring_radius: float = minf(float(ring) * step, radius)
		var sample_count: int = maxi(8, int(ceil(TAU * ring_radius / step)))
		for sample_idx in range(sample_count):
			var angle: float = TAU * float(sample_idx) / float(sample_count)
			var candidate: Vector3 = Vector3(
				desired_pos.x + cos(angle) * ring_radius,
				desired_pos.y,
				desired_pos.z + sin(angle) * ring_radius
			)
			var candidate_eval: Dictionary = _evaluate_attack_target_footprint(candidate)
			var candidate_score: float = _score_attack_target_placement(desired_pos, candidate_eval)
			if candidate_score < best_score:
				best_score = candidate_score
				best_eval = candidate_eval
	return best_eval

func _score_attack_target_placement(desired_pos: Vector3, eval: Dictionary) -> float:
	var position_value: Variant = eval.get("position", desired_pos)
	var position: Vector3 = position_value as Vector3 if position_value is Vector3 else desired_pos
	var dist_m: float = Vector2(position.x - desired_pos.x, position.z - desired_pos.z).length()
	var span_m: float = float(eval.get("height_span_m", INF))
	var open_span_m: float = float(eval.get("open_height_span_m", INF))
	var invalid_penalty: float = 0.0 if bool(eval.get("valid", false)) else 10000.0
	return invalid_penalty + dist_m + span_m * 140.0 + open_span_m * 80.0

func _evaluate_attack_target_footprint(center_pos: Vector3) -> Dictionary:
	var half_x: float = maxf(attack_target_footprint_m.x * 0.5, 1.0)
	var half_z: float = maxf(attack_target_footprint_m.y * 0.5, 1.0)
	var sample_offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(-half_x, -half_z),
		Vector2(half_x, -half_z),
		Vector2(half_x, half_z),
		Vector2(-half_x, half_z),
		Vector2(-half_x, 0.0),
		Vector2(half_x, 0.0),
		Vector2(0.0, -half_z),
		Vector2(0.0, half_z),
	]
	var min_ground_y: float = INF
	var max_ground_y: float = -INF
	for sample_offset: Vector2 in sample_offsets:
		var sample_pos: Vector3 = Vector3(center_pos.x + sample_offset.x, center_pos.y, center_pos.z + sample_offset.y)
		var ground_y: float = _sample_ground_height(sample_pos)
		if is_nan(ground_y) or not is_finite(ground_y):
			return {
				"valid": false,
				"position": center_pos,
				"height_span_m": INF,
				"min_ground_y": NAN,
				"max_ground_y": NAN,
			}
		min_ground_y = minf(min_ground_y, ground_y)
		max_ground_y = maxf(max_ground_y, ground_y)
	var height_span_m: float = max_ground_y - min_ground_y
	var open_eval: Dictionary = _evaluate_attack_target_open_area(center_pos, max_ground_y)
	var open_span_m: float = float(open_eval.get("height_span_m", INF))
	return {
		"valid": height_span_m <= maxf(attack_target_max_footprint_height_span_m, 0.0)
				and bool(open_eval.get("valid", false)),
		"position": Vector3(center_pos.x, max_ground_y, center_pos.z),
		"height_span_m": height_span_m,
		"open_height_span_m": open_span_m,
		"min_ground_y": min_ground_y,
		"max_ground_y": max_ground_y,
		"open_min_ground_y": float(open_eval.get("min_ground_y", NAN)),
		"open_max_ground_y": float(open_eval.get("max_ground_y", NAN)),
	}

func _evaluate_attack_target_open_area(center_pos: Vector3, center_ground_y: float) -> Dictionary:
	var radius: float = maxf(attack_target_open_radius_m, 0.0)
	if radius <= 0.0:
		return {
			"valid": true,
			"height_span_m": 0.0,
			"min_ground_y": center_ground_y,
			"max_ground_y": center_ground_y,
		}
	var step: float = maxf(attack_target_open_sample_step_m, 1.0)
	var rings: int = int(ceil(radius / step))
	var min_ground_y: float = center_ground_y
	var max_ground_y: float = center_ground_y
	for ring in range(1, rings + 1):
		var ring_radius: float = minf(float(ring) * step, radius)
		var sample_count: int = maxi(8, int(ceil(TAU * ring_radius / step)))
		for sample_idx in range(sample_count):
			var angle: float = TAU * float(sample_idx) / float(sample_count)
			var sample_pos: Vector3 = Vector3(
				center_pos.x + cos(angle) * ring_radius,
				center_pos.y,
				center_pos.z + sin(angle) * ring_radius
			)
			var ground_y: float = _sample_ground_height(sample_pos)
			if is_nan(ground_y) or not is_finite(ground_y):
				return {
					"valid": false,
					"height_span_m": INF,
					"min_ground_y": NAN,
					"max_ground_y": NAN,
				}
			min_ground_y = minf(min_ground_y, ground_y)
			max_ground_y = maxf(max_ground_y, ground_y)
			if max_ground_y - min_ground_y > maxf(attack_target_max_open_height_span_m, 0.0):
				return {
					"valid": false,
					"height_span_m": max_ground_y - min_ground_y,
					"min_ground_y": min_ground_y,
					"max_ground_y": max_ground_y,
				}
	return {
		"valid": true,
		"height_span_m": max_ground_y - min_ground_y,
		"min_ground_y": min_ground_y,
		"max_ground_y": max_ground_y,
	}

func _basis_with_project_forward(forward: Vector3) -> Basis:
	var flat_forward: Vector3 = Vector3(forward.x, 0.0, forward.z)
	if flat_forward.length_squared() <= 0.001:
		flat_forward = Vector3.FORWARD
	flat_forward = flat_forward.normalized()
	var yaw: float = atan2(flat_forward.x, flat_forward.z)
	return Basis(Vector3.UP, yaw)

func _create_waypoint_markers() -> void:
	var container: Node3D = Node3D.new()
	container.name = "AirplaneTestWaypointMarkers"
	add_child(container)
	for i in range(_base_route.size()):
		var leg: Dictionary = _base_route[i]
		var pos_value: Variant = leg.get("position", Vector3.ZERO)
		if not (pos_value is Vector3):
			continue
		var marker: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(35.0, 220.0, 35.0)
		marker.mesh = mesh
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.1, 0.7, 1.0, 0.55)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		marker.material_override = material
		container.add_child(marker)
		marker.global_position = (pos_value as Vector3) + Vector3(0.0, -110.0, 0.0)

func _open_report() -> void:
	var dir: String = "user://perf_logs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_report_file = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if _report_file == null:
		push_warning("[AirplaneTest] Could not open %s" % REPORT_PATH)
		return
	_report_file.store_line("Airplane test report")
	_report_file.store_line("path=%s" % ProjectSettings.globalize_path(REPORT_PATH))

func _log_event(line: String) -> void:
	print("[AirplaneTest] ", line)
	if _report_file != null:
		_report_file.store_line(line)
		_report_file.flush()

func _log_all_summaries(reason: String) -> void:
	for trial: Dictionary in _trials:
		_log_trial_summary(trial, reason)

func _log_trial_summary(trial: Dictionary, reason: String) -> void:
	var score_record: Dictionary = _score_trial(trial)
	var samples: int = int(trial.get("samples", 0))
	if samples <= 0:
		return
	_log_event("SUMMARY reason=%s generation=%d id=%d samples=%d laps=%d progress=%.2f progress_rate=%.2f score=%.1f mean_xtrack=%.1f max_xtrack=%.1f mean_dxtrack=%.1f max_dxtrack=%.1f proj_bad=%.3f proj_adv=%.3f resyncs=%d mean_slip=%.3f max_slip=%.3f mean_yaw=%.2f yaw_sat=%.2f mean_lat_g=%.2f max_lat_g=%.2f mean_abs_alt_err=%.1f high_alt=%.1f low_alt=%.1f high_frac=%.2f low_frac=%.2f mean_speed_err=%.1f overspeed=%.1f max_over=%.1f over_frac=%.2f brake=%.2f max_brake=%.2f limited=%.2f weapon=%s attack_launches=%d attack_impacts=%d attack_hits=%d attack_direct=%d attack_min_miss=%.1f attack_mean_miss=%.1f rockets=%d tight=%d after_best=%d last=%d rocket_impacts=%d rocket_hits=%d rocket_direct=%d rocket_min_miss=%.1f rocket_mean_miss=%.1f bombs=%d bomb_impacts=%d bomb_hits=%d bomb_direct=%d bomb_min_miss=%.1f bomb_mean_miss=%.1f gun_shots=%d gun_reports=%d gun_hits=%d gun_min=%.1f gun_mean=%.1f gun_aim_n=%d gun_aim_mean=%.1f gun_aim_min=%.1f gun_aim_good=%.2f gun_aim_first=%.1f gun_aim_dive_first=%.1f ccip_samples=%d ccip_mean=%.1f ccip_min=%.1f ccip_right=%.1f ccip_fwd=%.1f ccip_pitch=%.3f ccip_yaw=%.3f min_agl=%.1f crashed=%s genome=%s" % [
		reason,
		int(trial.get("generation", _generation_index)),
		int(trial.get("id", -1)),
		samples,
		int(score_record.get("laps", 0)),
		float(score_record.get("route_progress_units", 0.0)),
		float(score_record.get("progress_rate_units_per_min", 0.0)),
		float(score_record.get("score", INF)),
		float(score_record.get("mean_xtrack_m", INF)),
		float(score_record.get("max_xtrack_m", 0.0)),
		float(score_record.get("mean_xtrack_delta_m", 0.0)),
		float(score_record.get("max_xtrack_delta_m", 0.0)),
		float(score_record.get("route_projection_bad_fraction", 0.0)),
		float(score_record.get("route_projection_advance_fraction", 0.0)),
		int(score_record.get("route_resync_count", 0)),
		float(score_record.get("mean_abs_sideslip", 0.0)),
		float(score_record.get("max_abs_sideslip", 0.0)),
		float(score_record.get("mean_abs_yaw_input", 0.0)),
		float(score_record.get("yaw_saturation_fraction", 0.0)),
		float(score_record.get("mean_abs_lateral_accel_g", 0.0)),
		float(score_record.get("max_abs_lateral_accel_g", 0.0)),
		float(score_record.get("mean_alt_error_m", INF)),
		float(score_record.get("mean_high_alt_error_m", 0.0)),
		float(score_record.get("mean_low_alt_error_m", 0.0)),
		float(score_record.get("high_alt_fraction", 0.0)),
		float(score_record.get("low_alt_fraction", 0.0)),
		float(score_record.get("mean_speed_error_mps", INF)),
		float(score_record.get("mean_overspeed_mps", 0.0)),
		float(score_record.get("max_overspeed_mps", 0.0)),
		float(score_record.get("overspeed_fraction", 0.0)),
		float(score_record.get("mean_route_turn_brake", 0.0)),
		float(score_record.get("max_route_turn_brake", 0.0)),
		float(score_record.get("turn_limited_fraction", 0.0)),
		attack_test_weapon_mode,
		int(score_record.get("attack_launches", 0)),
		int(score_record.get("attack_impacts", 0)),
		int(score_record.get("attack_hits", 0)),
		int(score_record.get("attack_direct_hits", 0)),
		float(score_record.get("attack_min_miss_m", INF)),
		float(score_record.get("attack_mean_miss_m", INF)),
		int(score_record.get("rocket_launches", 0)),
		int(score_record.get("rocket_tight_launches", 0)),
		int(score_record.get("rocket_after_best_launches", 0)),
		int(score_record.get("rocket_last_chance_launches", 0)),
		int(score_record.get("rocket_impacts", 0)),
		int(score_record.get("rocket_hits", 0)),
		int(score_record.get("rocket_direct_hits", 0)),
		float(score_record.get("rocket_min_miss_m", INF)),
		float(score_record.get("rocket_mean_miss_m", INF)),
		int(score_record.get("bomb_drops", 0)),
		int(score_record.get("bomb_impacts", 0)),
		int(score_record.get("bomb_hits", 0)),
		int(score_record.get("bomb_direct_hits", 0)),
		float(score_record.get("bomb_min_miss_m", INF)),
		float(score_record.get("bomb_mean_miss_m", INF)),
		int(score_record.get("gun_shots", 0)),
		int(score_record.get("gun_reports", 0)),
		int(score_record.get("gun_hits", 0)),
		float(score_record.get("gun_min_edge_miss_m", INF)),
		float(score_record.get("gun_mean_edge_miss_m", INF)),
		int(score_record.get("gun_aim_samples", 0)),
		float(score_record.get("gun_aim_mean_angle_deg", INF)),
		float(score_record.get("gun_aim_min_angle_deg", INF)),
		float(score_record.get("gun_aim_good_fraction", 0.0)),
		float(score_record.get("gun_aim_first_good_time_s", INF)),
		float(score_record.get("gun_aim_first_good_dive_time_s", INF)),
		int(score_record.get("rocket_ccip_samples", 0)),
		float(score_record.get("rocket_ccip_mean_miss_m", INF)),
		float(score_record.get("rocket_ccip_min_miss_m", INF)),
		float(score_record.get("rocket_ccip_mean_abs_right_m", INF)),
		float(score_record.get("rocket_ccip_mean_abs_forward_m", INF)),
		float(score_record.get("rocket_ccip_mean_abs_pitch_cmd", 0.0)),
		float(score_record.get("rocket_ccip_mean_abs_yaw_cmd", 0.0)),
		float(score_record.get("min_agl_m", INF)),
		str(score_record.get("crashed", false)),
		_format_genome(score_record.get("genome", {}) as Dictionary),
	])

func _format_genome(genome: Dictionary) -> String:
	return "gid=%d speed=%.1f cap=%.0f look=%.0f look_frac=%.2f bank=%.1f pitch_smooth=%.2f pitch_in=%.2f input=%.2f roll_damp=%.2f yaw_scale=%.2f vs_gain=%.3f rudder=%.2f slip=%.2f rec_start=%.0f rec_full=%.0f rec_look=%.2f rec_speed=%.1f adv_x=%.0f proj_blend=%.2f proj_gain=%.2f cap_scale=%.2f cap_angle=%.1f cap_blend=%.2f fpv_blend=%.2f fly_start=%.2f fly_look=%.2f turn_tan=%.2f curve_ff=%.2f nav_bank=%.2f roll_p=%.2f roll_hp=%.2f roll_d=%.2f roll_min=%.2f alt_trim=%.2f unload_start=%.0f unload_full=%.0f unload_pitch=%.2f turn_pull=%.3f fpv_pg=%.2f fpv_pd=%.2f fpv_plim=%.2f atk_look=%.2f atk_cap=%.2f atk_blend=%.2f atk_gain=%.2f atk_bank=%.1f r_pitch=%.2f r_yaw=%.2f r_pdamp=%.2f r_ydamp=%.2f r_pmax=%.2f r_ymax=%.2f r_smooth=%.2f" % [
		int(genome.get("id", -1)),
		float(genome.get("speed_mps", 0.0)),
		float(genome.get("capture_radius_m", 0.0)),
		float(genome.get("lookahead_m", 0.0)),
		float(genome.get("lookahead_radius_fraction", 0.0)),
		float(genome.get("bank_limit_deg", 0.0)),
		float(genome.get("pitch_smoothing", 0.0)),
		float(genome.get("pitch_input_smoothing", 0.0)),
		float(genome.get("input_smoothing", 0.0)),
		float(genome.get("high_bank_roll_damping", 0.0)),
		float(genome.get("high_bank_yaw_scale", 0.0)),
		float(genome.get("vs_gain", 0.0)),
		float(genome.get("auto_rudder_strength", 0.0)),
		float(genome.get("sideslip_gain", 0.0)),
		float(genome.get("route_recovery_start_m", 0.0)),
		float(genome.get("route_recovery_full_m", 0.0)),
		float(genome.get("route_recovery_lookahead_scale", 0.0)),
		float(genome.get("route_recovery_speed_cut_mps", 0.0)),
		float(genome.get("route_projection_advance_max_xtrack_m", 0.0)),
		float(genome.get("route_projection_blend", 0.72)),
		float(genome.get("route_projection_gain", 1.55)),
		float(genome.get("route_capture_radius_scale", 1.0)),
		float(genome.get("route_capture_max_angle_deg", 45.0)),
		float(genome.get("route_capture_max_blend", 0.90)),
		float(genome.get("route_fpv_yaw_blend", 0.55)),
		float(genome.get("route_flyby_start_fraction", 1.0)),
		float(genome.get("route_flyby_lookahead_fraction", 0.55)),
		float(genome.get("route_turn_tangent_fraction", 0.62)),
		float(genome.get("route_curvature_feedforward_gain", 1.0)),
		float(genome.get("navigation_bank_gain", 1.5)),
		float(genome.get("navigation_roll_p_gain", 11.0)),
		float(genome.get("navigation_roll_high_bank_p_gain", 4.5)),
		float(genome.get("navigation_roll_rate_damping", 0.30)),
		float(genome.get("navigation_roll_min_input", 0.45)),
		float(genome.get("pitch_altitude_trim", 0.0)),
		float(genome.get("above_path_unload_start_m", 0.0)),
		float(genome.get("above_path_unload_full_m", 0.0)),
		float(genome.get("above_path_unload_pitch", 0.0)),
		float(genome.get("turn_pull_pitch_input", 0.0)),
		float(genome.get("fpv_pitch_gain", 1.35)),
		float(genome.get("fpv_pitch_damping", 0.20)),
		float(genome.get("fpv_pitch_limit", 0.46)),
		float(genome.get("attack_route_lookahead_fraction", 0.35)),
		float(genome.get("attack_route_capture_scale", 1.0)),
		float(genome.get("attack_route_projection_blend", 0.72)),
		float(genome.get("attack_route_projection_gain", 1.55)),
		float(genome.get("attack_route_bank_limit_deg", 75.0)),
		float(genome.get("rocket_ccip_pitch_gain", 0.0)),
		float(genome.get("rocket_ccip_yaw_gain", 0.0)),
		float(genome.get("rocket_ccip_pitch_damp", 0.0)),
		float(genome.get("rocket_ccip_yaw_damp", 0.0)),
		float(genome.get("rocket_ccip_max_pitch", 0.0)),
		float(genome.get("rocket_ccip_max_yaw", 0.0)),
		float(genome.get("rocket_ccip_smooth", 0.0)),
	]

func _fmt_v3(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]

func _fmt_v2(v: Vector2) -> String:
	return "(%.2f,%.2f)" % [v.x, v.y]

func _shift_route(route: Array, offset: Vector3) -> void:
	for i in range(route.size()):
		var leg_value: Variant = route[i]
		if not (leg_value is Dictionary):
			continue
		var leg: Dictionary = leg_value as Dictionary
		var position_value: Variant = leg.get("position", Vector3.INF)
		if position_value is Vector3:
			leg["position"] = (position_value as Vector3) - offset
			route[i] = leg

func _clear_trials() -> void:
	for trial: Dictionary in _trials:
		var aircraft: RigidBody3D = _get_trial_aircraft(trial)
		if aircraft != null:
			aircraft.queue_free()
	_trials.clear()

func _clear_attack_target() -> void:
	for target: Node3D in _targets:
		if target != null and is_instance_valid(target):
			target.queue_free()
	_targets.clear()
	_target = null

func _find_trial_index(trial_id: int) -> int:
	for i in range(_trials.size()):
		var trial: Dictionary = _trials[i]
		if int(trial.get("id", -1)) == trial_id:
			return i
	return -1

func _get_trial_aircraft(trial: Dictionary) -> RigidBody3D:
	var aircraft_value: Variant = trial.get("aircraft", null)
	if not is_instance_valid(aircraft_value):
		return null
	return aircraft_value as RigidBody3D

func _get_trial_pilot(trial: Dictionary) -> AIPilot:
	var pilot_value: Variant = trial.get("pilot", null)
	if not is_instance_valid(pilot_value):
		return null
	return pilot_value as AIPilot

func _get_trial_attack_target(trial: Dictionary) -> Node3D:
	var target_value: Variant = trial.get("current_attack_target", null)
	if is_instance_valid(target_value) and target_value is Node3D:
		return target_value as Node3D
	if _target != null and is_instance_valid(_target):
		return _target
	return null

func _get_trial_route(trial: Dictionary) -> Array[Dictionary]:
	var route: Array[Dictionary] = []
	var route_value: Variant = trial.get("route", [])
	if not (route_value is Array):
		return route
	for leg_value: Variant in route_value as Array:
		if leg_value is Dictionary:
			route.append(leg_value as Dictionary)
	return route

func _on_trial_aircraft_crashed(impact_velocity: float, trial_id: int) -> void:
	var trial_index: int = _find_trial_index(trial_id)
	if trial_index < 0:
		return
	var trial: Dictionary = _trials[trial_index]
	trial["crashed"] = true
	_trials[trial_index] = trial
	_finish_trial_evaluation(trial_index, "crashed", false)
	trial = _trials[trial_index]
	var aircraft: RigidBody3D = _get_trial_aircraft(trial)
	var position: Vector3 = aircraft.global_position if aircraft != null else Vector3.ZERO
	_log_event("AIRCRAFT_CRASH generation=%d id=%d impact=%.1f t=%.1f pos=%s" % [
		int(trial.get("generation", _generation_index)),
		trial_id,
		impact_velocity,
		_elapsed_s,
		_fmt_v3(position),
	])
	_log_trial_summary(trial, "crash")

func _on_trial_aircraft_destroyed(trial_id: int) -> void:
	var trial_index: int = _find_trial_index(trial_id)
	if trial_index < 0:
		return
	var trial: Dictionary = _trials[trial_index]
	trial["destroyed"] = true
	trial["crashed"] = true
	_trials[trial_index] = trial
	_finish_trial_evaluation(trial_index, "destroyed", false)
	trial = _trials[trial_index]
	_log_event("AIRCRAFT_DESTROYED generation=%d id=%d t=%.1f" % [
		int(trial.get("generation", _generation_index)),
		trial_id,
		_elapsed_s,
	])
	_log_trial_summary(trial, "destroyed")

func _spawn_attack_targets() -> void:
	if not _targets.is_empty():
		return
	var offsets: Array[Vector3] = attack_target_offsets_m
	if offsets.is_empty():
		offsets = [attack_target_offset_m]
	for i in range(offsets.size()):
		var offset: Vector3 = offsets[i]
		var spawned_target: Node3D = _spawn_attack_target(offset, i)
		if spawned_target != null:
			_targets.append(spawned_target)
	if not _targets.is_empty():
		_target = _targets[0]

func _spawn_attack_target(offset: Vector3, target_index: int) -> Node3D:
	var root: Node = get_tree().current_scene
	if root == null:
		root = self
	var target: StaticBody3D = StaticBody3D.new()
	target.name = "AirplaneTestTarget_%d" % target_index
	target.set_script(TEST_TARGET_SCRIPT)
	target.set("infinite_health", true)
	target.set("max_health", 1000000000.0)
	target.set("health", 1000000000.0)
	target.collision_layer = 1
	target.collision_mask = 1
	target.add_to_group("enemies")
	target.add_to_group("buildings")
	target.add_to_group("enemy_bases")

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(attack_target_footprint_m.x, 12.0, attack_target_footprint_m.y)
	shape.shape = box
	shape.position = Vector3(0.0, 6.0, 0.0)
	target.add_child(shape)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(attack_target_footprint_m.x, 12.0, attack_target_footprint_m.y)
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, 6.0, 0.0)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.16, 0.08, 1.0)
	mesh_instance.material_override = material
	target.add_child(mesh_instance)

	root.add_child(target)
	var desired_pos: Vector3 = Vector3(play_area_center.x + offset.x, play_area_center.y, play_area_center.z + offset.z)
	var placement: Dictionary = _find_grounded_attack_target_placement(desired_pos)
	var placement_pos_value: Variant = placement.get("position", desired_pos)
	var placement_pos: Vector3 = placement_pos_value as Vector3 if placement_pos_value is Vector3 else desired_pos
	target.global_position = placement_pos
	if attack_targets_move and attack_target_move_speed_mps > 0.0:
		var patrol: PackedVector3Array = _build_target_patrol_path(placement_pos)
		if patrol.size() >= 2:
			target.set("path_points", patrol)
			target.set("move_speed_mps", attack_target_move_speed_mps)
			target.set("path_loops", true)
			target.set("stick_to_ground", true)
			_log_event("TARGET_PATROL generation=%d index=%d speed=%.1f radius=%.0f waypoints=%d" % [
				_generation_index, target_index, attack_target_move_speed_mps,
				attack_target_patrol_radius_m, patrol.size()])
	if target.has_signal("damaged"):
		target.damaged.connect(_on_target_damaged)
	if target.has_signal("destroyed"):
		target.destroyed.connect(_on_target_destroyed)
	_log_event("TARGET_SPAWNED generation=%d index=%d t=%.1f pos=%s offset=%s span=%.2f open_span=%.2f min_ground=%.1f max_ground=%.1f open_min=%.1f open_max=%.1f shifted=%.1f valid=%s" % [
		_generation_index,
		target_index,
		_elapsed_s,
		_fmt_v3(target.global_position),
		_fmt_v3(offset),
		float(placement.get("height_span_m", INF)),
		float(placement.get("open_height_span_m", INF)),
		float(placement.get("min_ground_y", NAN)),
		float(placement.get("max_ground_y", NAN)),
		float(placement.get("open_min_ground_y", NAN)),
		float(placement.get("open_max_ground_y", NAN)),
		Vector2(placement_pos.x - desired_pos.x, placement_pos.z - desired_pos.z).length(),
		str(placement.get("valid", false)),
	])
	return target

# Build a closed patrol loop of waypoints around a center point (the target's spawn position),
# so the target circles like a vehicle on patrol. Waypoints are placed on a ring and grounded to
# terrain so the target follows the surface.
func _build_target_patrol_path(center: Vector3) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	var n: int = maxi(attack_target_patrol_waypoints, 2)
	var radius: float = maxf(attack_target_patrol_radius_m, 20.0)
	var start_angle: float = randf() * TAU
	for i in range(n):
		var a: float = start_angle + TAU * float(i) / float(n)
		var wp: Vector3 = Vector3(center.x + cos(a) * radius, center.y, center.z + sin(a) * radius)
		points.append(wp)
	return points

func _choose_attack_target_for_trial(trial: Dictionary) -> Node3D:
	if _targets.is_empty():
		_spawn_attack_targets()
	if _targets.is_empty():
		return null
	var trial_id: int = int(trial.get("slot", 0)) if deterministic_validation_enabled else int(trial.get("id", 0))
	var cycle_count: int = int(trial.get("attack_cycle_count", 0))
	var index: int = posmod(trial_id + cycle_count, _targets.size())
	var target: Node3D = _targets[index]
	if target == null or not is_instance_valid(target):
		return _target
	return target

func _on_test_gun_shot(trial_id: int, bullet_variant: Variant = null) -> void:
	var trial_index: int = _find_trial_index(trial_id)
	if trial_index < 0:
		return
	var trial: Dictionary = _trials[trial_index]
	trial["gun_shots"] = int(trial.get("gun_shots", 0)) + 1
	_trials[trial_index] = trial
	var shot_count: int = int(trial.get("gun_shots", 0))
	if shot_count <= 5 or shot_count % 25 == 0:
		var bullet_pos: Vector3 = Vector3.ZERO
		if bullet_variant is Node3D and is_instance_valid(bullet_variant):
			bullet_pos = (bullet_variant as Node3D).global_position
		_log_event("GUN_SHOT generation=%d id=%d t=%.1f shots=%d pos=%s" % [
			int(trial.get("generation", _generation_index)),
			trial_id,
			_elapsed_s,
			shot_count,
			_fmt_v3(bullet_pos),
		])

func _on_test_gun_report(report: Dictionary, trial_id: int) -> void:
	var trial_index: int = _find_trial_index(trial_id)
	if trial_index < 0:
		return
	var trial: Dictionary = _trials[trial_index]
	var closest_edge_m: float = float(report.get("closest_edge_m", INF))
	var closest_center_m: float = float(report.get("closest_center_m", INF))
	var direct_hit: bool = bool(report.get("hit_target", false))
	var hit: bool = direct_hit or closest_edge_m <= maxf(gun_hit_radius_m, 0.0)
	trial["gun_reports"] = int(trial.get("gun_reports", 0)) + 1
	trial["gun_sum_edge_miss_m"] = float(trial.get("gun_sum_edge_miss_m", 0.0)) + closest_edge_m
	trial["gun_min_edge_miss_m"] = minf(float(trial.get("gun_min_edge_miss_m", INF)), closest_edge_m)
	trial["gun_last_edge_miss_m"] = closest_edge_m
	trial["gun_min_center_miss_m"] = minf(float(trial.get("gun_min_center_miss_m", INF)), closest_center_m)
	if hit:
		trial["gun_hits"] = int(trial.get("gun_hits", 0)) + 1
	_trials[trial_index] = trial
	var report_count: int = int(trial.get("gun_reports", 0))
	if hit or report_count <= 5 or report_count % 25 == 0:
		_log_event("GUN_REPORT generation=%d id=%d t=%.1f reports=%d shots=%d edge=%.1f center=%.1f hit=%s direct_hit=%s reason=%s age=%.2f speed=%.1f target=%s" % [
			int(trial.get("generation", _generation_index)),
			trial_id,
			_elapsed_s,
			report_count,
			int(trial.get("gun_shots", 0)),
			closest_edge_m,
			closest_center_m,
			str(hit),
			str(direct_hit),
			str(report.get("reason", "")),
			float(report.get("bullet_age_s", 0.0)),
			float(report.get("bullet_avg_speed_integrated_mps", 0.0)),
			str(report.get("target_name", "")),
		])

func _on_test_rocket_launched(trial_id: int, rocket_variant: Variant = null, target_variant: Variant = null) -> void:
	var trial_index: int = _find_trial_index(trial_id)
	if trial_index < 0:
		return
	var trial: Dictionary = _trials[trial_index]
	trial["rocket_launches"] = int(trial.get("rocket_launches", 0)) + 1
	var pilot: AIPilot = _get_trial_pilot(trial)
	var release_reason: String = pilot.get_last_rocket_release_reason() if pilot != null else ""
	var release_miss_m: float = pilot.get_last_rocket_release_miss_m() if pilot != null else INF
	var release_best_miss_m: float = pilot.get_last_rocket_release_best_miss_m() if pilot != null else INF
	match release_reason:
		"tight":
			trial["rocket_tight_launches"] = int(trial.get("rocket_tight_launches", 0)) + 1
		"after_best":
			trial["rocket_after_best_launches"] = int(trial.get("rocket_after_best_launches", 0)) + 1
		"last_chance":
			trial["rocket_last_chance_launches"] = int(trial.get("rocket_last_chance_launches", 0)) + 1
		_:
			trial["rocket_other_launches"] = int(trial.get("rocket_other_launches", 0)) + 1
	var aircraft: RigidBody3D = _get_trial_aircraft(trial)
	var launch_pos: Vector3 = Vector3.ZERO
	var forward_xz: Vector2 = Vector2.ZERO
	var right_xz: Vector2 = Vector2.ZERO
	var launch_speed_mps: float = 0.0
	var rocket_id: int = 0
	var rocket: Node3D = _variant_to_node3d(rocket_variant)
	if rocket != null:
		rocket_id = int(rocket.get_instance_id())
	var target: Node3D = _variant_to_node3d(target_variant)
	if target == null:
		target = _target
	var target_pos: Vector3 = target.global_position if target != null and is_instance_valid(target) else Vector3.ZERO
	if aircraft != null:
		launch_pos = aircraft.global_position
		launch_speed_mps = aircraft.linear_velocity.length()
		var forward_3d: Vector3 = aircraft.linear_velocity
		forward_3d.y = 0.0
		if forward_3d.length_squared() < 1.0:
			forward_3d = aircraft.global_transform.basis.z
			forward_3d.y = 0.0
		if forward_3d.length_squared() > 0.001:
			forward_3d = forward_3d.normalized()
			forward_xz = Vector2(forward_3d.x, forward_3d.z)
			right_xz = Vector2(forward_3d.z, -forward_3d.x)
	var contexts_value: Variant = trial.get("rocket_launch_contexts", [])
	var launch_contexts: Array = []
	if contexts_value is Array:
		launch_contexts = contexts_value as Array
	var launch_context: Dictionary = {
		"rocket_id": rocket_id,
		"launch_pos": launch_pos,
		"forward_xz": forward_xz,
		"right_xz": right_xz,
		"speed_mps": launch_speed_mps,
		"target_pos": target_pos,
		"release_reason": release_reason,
		"release_miss_m": release_miss_m,
		"release_best_miss_m": release_best_miss_m,
	}
	launch_contexts.append(launch_context)
	trial["rocket_launch_contexts"] = launch_contexts
	if rocket_id != 0:
		var context_by_id_value: Variant = trial.get("rocket_launch_context_by_id", {})
		var context_by_id: Dictionary = {}
		if context_by_id_value is Dictionary:
			context_by_id = context_by_id_value as Dictionary
		context_by_id[str(rocket_id)] = launch_context
		trial["rocket_launch_context_by_id"] = context_by_id
	_trials[trial_index] = trial
	_log_event("ROCKET_LAUNCH generation=%d id=%d rocket=%d t=%.1f launches=%d reason=%s release_miss=%.1f best_miss=%.1f launch_pos=%s launch_fwd=%s speed=%.1f target=%s" % [
		int(trial.get("generation", _generation_index)),
		trial_id,
		rocket_id,
		_elapsed_s,
		int(trial.get("rocket_launches", 0)),
		release_reason,
		release_miss_m,
		release_best_miss_m,
		_fmt_v3(launch_pos),
		_fmt_v2(forward_xz),
		launch_speed_mps,
		_fmt_v3(target_pos),
	])

func _on_test_rocket_impact(impact_position: Vector3, trial_id: int, target_variant: Variant, rocket_variant: Variant = null) -> void:
	_record_test_rocket_impact(impact_position, null, trial_id, target_variant, rocket_variant)

func _on_test_rocket_impact_detail(impact_position: Vector3, body: Node, trial_id: int, target_variant: Variant, rocket_variant: Variant = null) -> void:
	_record_test_rocket_impact(impact_position, body, trial_id, target_variant, rocket_variant)

func _record_test_rocket_impact(impact_position: Vector3, body: Node, trial_id: int, target_variant: Variant, rocket_variant: Variant = null) -> void:
	var trial_index: int = _find_trial_index(trial_id)
	if trial_index < 0:
		return
	var trial: Dictionary = _trials[trial_index]
	var rocket: Node3D = _variant_to_node3d(rocket_variant)
	var rocket_id: int = int(rocket.get_instance_id()) if rocket != null else 0
	var launch_context: Dictionary = {}
	var matched_by_id: bool = false
	if rocket_id != 0:
		var context_by_id_value: Variant = trial.get("rocket_launch_context_by_id", {})
		var context_by_id: Dictionary = {}
		if context_by_id_value is Dictionary:
			context_by_id = context_by_id_value as Dictionary
		var context_key: String = str(rocket_id)
		var context_value: Variant = context_by_id.get(context_key, {})
		if context_value is Dictionary:
			launch_context = context_value as Dictionary
			matched_by_id = true
			context_by_id.erase(context_key)
			trial["rocket_launch_context_by_id"] = context_by_id
	var contexts_value: Variant = trial.get("rocket_launch_contexts", [])
	var launch_contexts: Array = []
	if contexts_value is Array:
		launch_contexts = contexts_value as Array
	if matched_by_id:
		for context_index: int in range(launch_contexts.size() - 1, -1, -1):
			var queued_context_value: Variant = launch_contexts[context_index]
			if queued_context_value is Dictionary:
				var queued_context: Dictionary = queued_context_value as Dictionary
				if int(queued_context.get("rocket_id", 0)) == rocket_id:
					launch_contexts.remove_at(context_index)
					break
	elif not launch_contexts.is_empty():
		var launch_context_value: Variant = launch_contexts.pop_front()
		if launch_context_value is Dictionary:
			launch_context = launch_context_value as Dictionary
	trial["rocket_launch_contexts"] = launch_contexts
	var target: Node3D = _variant_to_node3d(target_variant)
	if target == null:
		target = _target
	var target_pos: Vector3 = target.global_position if target != null and is_instance_valid(target) else Vector3.ZERO
	var context_target_pos_value: Variant = launch_context.get("target_pos", Vector3.ZERO)
	if context_target_pos_value is Vector3:
		target_pos = context_target_pos_value as Vector3
	var impact_offset_xz: Vector2 = Vector2(impact_position.x - target_pos.x, impact_position.z - target_pos.z)
	var ground_miss_m: float = impact_offset_xz.length()
	var direct_hit: bool = _rocket_impact_body_matches_target(body, target)
	var score_miss_m: float = 0.0 if direct_hit else ground_miss_m
	var hit: bool = direct_hit or ground_miss_m <= maxf(rocket_hit_radius_m, 0.0)
	trial["rocket_impacts"] = int(trial.get("rocket_impacts", 0)) + 1
	trial["rocket_sum_miss_m"] = float(trial.get("rocket_sum_miss_m", 0.0)) + score_miss_m
	trial["rocket_min_miss_m"] = minf(float(trial.get("rocket_min_miss_m", INF)), score_miss_m)
	trial["rocket_last_miss_m"] = score_miss_m
	if hit:
		trial["rocket_hits"] = int(trial.get("rocket_hits", 0)) + 1
	if direct_hit:
		trial["rocket_direct_hits"] = int(trial.get("rocket_direct_hits", 0)) + 1
	_trials[trial_index] = trial
	var along_track_m: float = NAN
	var cross_track_m: float = NAN
	var launch_range_m: float = NAN
	var release_reason: String = ""
	var release_miss_m: float = INF
	var release_best_miss_m: float = INF
	var launch_pos: Vector3 = Vector3.ZERO
	var forward_xz: Vector2 = Vector2.ZERO
	var forward_value: Variant = launch_context.get("forward_xz", Vector2.ZERO)
	var right_value: Variant = launch_context.get("right_xz", Vector2.ZERO)
	if forward_value is Vector2 and right_value is Vector2:
		forward_xz = forward_value as Vector2
		var right_xz: Vector2 = right_value as Vector2
		if forward_xz.length_squared() > 0.001 and right_xz.length_squared() > 0.001:
			along_track_m = impact_offset_xz.dot(forward_xz)
			cross_track_m = impact_offset_xz.dot(right_xz)
	var launch_pos_value: Variant = launch_context.get("launch_pos", Vector3.ZERO)
	if launch_pos_value is Vector3:
		launch_pos = launch_pos_value as Vector3
		launch_range_m = Vector2(target_pos.x - launch_pos.x, target_pos.z - launch_pos.z).length()
	var reason_value: Variant = launch_context.get("release_reason", "")
	if reason_value is String:
		release_reason = reason_value
	release_miss_m = float(launch_context.get("release_miss_m", INF))
	release_best_miss_m = float(launch_context.get("release_best_miss_m", INF))
	_log_event("ROCKET_IMPACT generation=%d id=%d rocket=%d ctx=%s t=%.1f miss=%.1f ground_miss=%.1f hit=%s direct_hit=%s impacts=%d dx=%.1f dz=%.1f along=%.1f cross=%.1f release_reason=%s release_miss=%.1f best_miss=%.1f launch_range=%.1f launch_pos=%s launch_fwd=%s body=%s pos=%s target=%s" % [
		int(trial.get("generation", _generation_index)),
		trial_id,
		rocket_id,
		"id" if matched_by_id else "fifo",
		_elapsed_s,
		score_miss_m,
		ground_miss_m,
		str(hit),
		str(direct_hit),
		int(trial.get("rocket_impacts", 0)),
		impact_offset_xz.x,
		impact_offset_xz.y,
		along_track_m,
		cross_track_m,
		release_reason,
		release_miss_m,
		release_best_miss_m,
		launch_range_m,
		_fmt_v3(launch_pos),
		_fmt_v2(forward_xz),
		_get_node_label(body),
		_fmt_v3(impact_position),
		_fmt_v3(target_pos),
	])

func _on_test_bomb_dropped(trial_id: int, bomb_variant: Variant = null) -> void:
	var trial_index: int = _find_trial_index(trial_id)
	if trial_index < 0:
		return
	var trial: Dictionary = _trials[trial_index]
	trial["bomb_drops"] = int(trial.get("bomb_drops", 0)) + 1
	var aircraft: RigidBody3D = _get_trial_aircraft(trial)
	var bomb: RigidBody3D = null
	if bomb_variant is RigidBody3D and is_instance_valid(bomb_variant):
		bomb = bomb_variant as RigidBody3D
	var drop_pos: Vector3 = Vector3.ZERO
	var forward_xz: Vector2 = Vector2.ZERO
	var right_xz: Vector2 = Vector2.ZERO
	var drop_speed_mps: float = 0.0
	var drop_forward_speed_mps: float = 0.0
	var predicted_impact: Vector3 = Vector3.ZERO
	var aim_target: Vector3 = Vector3.ZERO
	var has_predicted_impact: bool = false
	var has_aim_target: bool = false
	if bomb != null:
		drop_pos = bomb.global_position
		drop_speed_mps = bomb.linear_velocity.length()
		var predicted_value: Variant = bomb.get_meta("debug_predicted_impact", Vector3.ZERO)
		if predicted_value is Vector3:
			predicted_impact = predicted_value as Vector3
			has_predicted_impact = predicted_impact != Vector3.ZERO
		var aim_value: Variant = bomb.get_meta("debug_aim_target", Vector3.ZERO)
		if aim_value is Vector3:
			aim_target = aim_value as Vector3
			has_aim_target = aim_target != Vector3.ZERO
	if drop_pos == Vector3.ZERO and aircraft != null:
		drop_pos = aircraft.global_position
	var velocity_source: RigidBody3D = bomb if bomb != null else aircraft
	if velocity_source != null:
		drop_speed_mps = velocity_source.linear_velocity.length()
		var forward_3d: Vector3 = velocity_source.linear_velocity
		forward_3d.y = 0.0
		if forward_3d.length_squared() < 1.0:
			forward_3d = velocity_source.global_transform.basis.z
			forward_3d.y = 0.0
		if forward_3d.length_squared() > 0.001:
			forward_3d = forward_3d.normalized()
			forward_xz = Vector2(forward_3d.x, forward_3d.z)
			right_xz = Vector2(forward_3d.z, -forward_3d.x)
			var horizontal_velocity: Vector2 = Vector2(velocity_source.linear_velocity.x, velocity_source.linear_velocity.z)
			drop_forward_speed_mps = horizontal_velocity.dot(forward_xz)
	var release_miss_m: float = INF
	var release_best_miss_m: float = INF
	var release_alt_above_m: float = INF
	var release_range_m: float = INF
	var release_bank_deg: float = 0.0
	var release_fpa_deg: float = 0.0
	var release_stable_s: float = 0.0
	var pilot_value: Variant = trial.get("pilot", null)
	if pilot_value is AIPilot and is_instance_valid(pilot_value):
		var pilot: AIPilot = pilot_value as AIPilot
		release_miss_m = pilot.get_last_bomb_release_miss_m()
		release_best_miss_m = pilot.get_last_bomb_release_best_miss_m()
		release_alt_above_m = pilot.get_last_bomb_release_alt_above_m()
		release_range_m = pilot.get_last_bomb_release_range_m()
		release_bank_deg = pilot.get_last_bomb_release_bank_deg()
		release_fpa_deg = pilot.get_last_bomb_release_fpa_deg()
		release_stable_s = pilot.get_last_bomb_release_stable_s()
	var contexts_value: Variant = trial.get("bomb_drop_contexts", [])
	var drop_contexts: Array = []
	if contexts_value is Array:
		drop_contexts = contexts_value as Array
	drop_contexts.append({
		"drop_pos": drop_pos,
		"forward_xz": forward_xz,
		"right_xz": right_xz,
		"speed_mps": drop_speed_mps,
		"forward_speed_mps": drop_forward_speed_mps,
		"predicted_impact": predicted_impact,
		"has_predicted_impact": has_predicted_impact,
		"aim_target": aim_target,
		"has_aim_target": has_aim_target,
		"release_miss_m": release_miss_m,
		"release_best_miss_m": release_best_miss_m,
		"release_alt_above_m": release_alt_above_m,
		"release_range_m": release_range_m,
		"release_bank_deg": release_bank_deg,
		"release_fpa_deg": release_fpa_deg,
		"release_stable_s": release_stable_s,
	})
	trial["bomb_drop_contexts"] = drop_contexts
	_trials[trial_index] = trial
	_log_event("BOMB_DROP generation=%d id=%d t=%.1f drops=%d drop_pos=%s drop_fwd=%s speed=%.1f pred=%s aim=%s release_miss=%.1f best=%.1f alt=%.1f range=%.1f bank=%.1f fpa=%.1f stable=%.2f" % [
		int(trial.get("generation", _generation_index)),
		trial_id,
		_elapsed_s,
		int(trial.get("bomb_drops", 0)),
		_fmt_v3(drop_pos),
		_fmt_v2(forward_xz),
		drop_speed_mps,
		_fmt_v3(predicted_impact) if has_predicted_impact else "none",
		_fmt_v3(aim_target) if has_aim_target else "none",
		release_miss_m,
		release_best_miss_m,
		release_alt_above_m,
		release_range_m,
		release_bank_deg,
		release_fpa_deg,
		release_stable_s,
	])

func _on_test_bomb_impact(impact_position: Vector3, trial_id: int, target_variant: Variant) -> void:
	_record_test_bomb_impact(impact_position, null, trial_id, target_variant)

func _on_test_bomb_impact_detail(impact_position: Vector3, body: Node, trial_id: int, target_variant: Variant) -> void:
	_record_test_bomb_impact(impact_position, body, trial_id, target_variant)

func _record_test_bomb_impact(impact_position: Vector3, body: Node, trial_id: int, target_variant: Variant) -> void:
	var trial_index: int = _find_trial_index(trial_id)
	if trial_index < 0:
		return
	var trial: Dictionary = _trials[trial_index]
	var drop_context: Dictionary = {}
	var contexts_value: Variant = trial.get("bomb_drop_contexts", [])
	var drop_contexts: Array = []
	if contexts_value is Array:
		drop_contexts = contexts_value as Array
	if not drop_contexts.is_empty():
		var drop_context_value: Variant = drop_contexts.pop_front()
		if drop_context_value is Dictionary:
			drop_context = drop_context_value as Dictionary
	trial["bomb_drop_contexts"] = drop_contexts

	var target: Node3D = null
	if target_variant is Node3D and is_instance_valid(target_variant):
		target = target_variant as Node3D
	else:
		target = _target
	var target_pos: Vector3 = target.global_position if target != null and is_instance_valid(target) else Vector3.ZERO
	var aim_target: Vector3 = Vector3.ZERO
	var has_aim_target: bool = bool(drop_context.get("has_aim_target", false))
	var aim_value: Variant = drop_context.get("aim_target", Vector3.ZERO)
	if has_aim_target and aim_value is Vector3:
		aim_target = aim_value as Vector3
		target_pos = aim_target
	var impact_offset_xz: Vector2 = Vector2(impact_position.x - target_pos.x, impact_position.z - target_pos.z)
	var ground_miss_m: float = impact_offset_xz.length()
	var direct_hit: bool = _rocket_impact_body_matches_target(body, target)
	var score_miss_m: float = 0.0 if direct_hit else ground_miss_m
	var hit: bool = direct_hit or ground_miss_m <= maxf(bomb_hit_radius_m, 0.0)
	trial["bomb_impacts"] = int(trial.get("bomb_impacts", 0)) + 1
	trial["bomb_sum_miss_m"] = float(trial.get("bomb_sum_miss_m", 0.0)) + score_miss_m
	trial["bomb_min_miss_m"] = minf(float(trial.get("bomb_min_miss_m", INF)), score_miss_m)
	trial["bomb_last_miss_m"] = score_miss_m
	if hit:
		trial["bomb_hits"] = int(trial.get("bomb_hits", 0)) + 1
	if direct_hit:
		trial["bomb_direct_hits"] = int(trial.get("bomb_direct_hits", 0)) + 1
	_trials[trial_index] = trial

	var along_track_m: float = NAN
	var cross_track_m: float = NAN
	var drop_range_m: float = NAN
	var needed_release_bias_s: float = NAN
	var predicted_needed_release_bias_s: float = NAN
	var drop_pos: Vector3 = Vector3.ZERO
	var forward_xz: Vector2 = Vector2.ZERO
	var forward_value: Variant = drop_context.get("forward_xz", Vector2.ZERO)
	var right_value: Variant = drop_context.get("right_xz", Vector2.ZERO)
	if forward_value is Vector2 and right_value is Vector2:
		forward_xz = forward_value as Vector2
		var right_xz: Vector2 = right_value as Vector2
		if forward_xz.length_squared() > 0.001 and right_xz.length_squared() > 0.001:
			along_track_m = impact_offset_xz.dot(forward_xz)
			cross_track_m = impact_offset_xz.dot(right_xz)
	var drop_pos_value: Variant = drop_context.get("drop_pos", Vector3.ZERO)
	if drop_pos_value is Vector3:
		drop_pos = drop_pos_value as Vector3
		drop_range_m = Vector2(target_pos.x - drop_pos.x, target_pos.z - drop_pos.z).length()
	var drop_forward_speed_mps: float = float(drop_context.get("forward_speed_mps", 0.0))
	if absf(drop_forward_speed_mps) > 0.001 and not is_nan(along_track_m):
		needed_release_bias_s = -along_track_m / drop_forward_speed_mps
	var predict_err_m: float = INF
	var predicted_target_miss_m: float = INF
	var predicted_along_track_m: float = NAN
	var predicted_cross_track_m: float = NAN
	var predicted_impact: Vector3 = Vector3.ZERO
	var has_predicted_impact: bool = bool(drop_context.get("has_predicted_impact", false))
	var predicted_value: Variant = drop_context.get("predicted_impact", Vector3.ZERO)
	if has_predicted_impact and predicted_value is Vector3:
		predicted_impact = predicted_value as Vector3
		predict_err_m = Vector2(impact_position.x - predicted_impact.x, impact_position.z - predicted_impact.z).length()
		var predicted_offset_xz: Vector2 = Vector2(predicted_impact.x - target_pos.x, predicted_impact.z - target_pos.z)
		predicted_target_miss_m = predicted_offset_xz.length()
		if forward_xz.length_squared() > 0.001:
			var right_for_pred: Vector2 = Vector2(forward_xz.y, -forward_xz.x)
			predicted_along_track_m = predicted_offset_xz.dot(forward_xz)
			predicted_cross_track_m = predicted_offset_xz.dot(right_for_pred)
			if absf(drop_forward_speed_mps) > 0.001:
				predicted_needed_release_bias_s = -predicted_along_track_m / drop_forward_speed_mps
	var aim_miss_m: float = INF
	if has_aim_target:
		aim_miss_m = Vector2(impact_position.x - aim_target.x, impact_position.z - aim_target.z).length()
	_log_event("BOMB_IMPACT generation=%d id=%d t=%.1f miss=%.1f ground_miss=%.1f hit=%s direct_hit=%s impacts=%d dx=%.1f dz=%.1f along=%.1f cross=%.1f bias_needed=%.3f pred_bias_needed=%.3f drop_fwd_speed=%.1f pred_err=%.1f pred_target_miss=%.1f pred_along=%.1f pred_cross=%.1f aim_miss=%.1f release_miss=%.1f best=%.1f drop_range=%.1f drop_pos=%s drop_fwd=%s pred=%s aim=%s body=%s pos=%s target=%s" % [
		int(trial.get("generation", _generation_index)),
		trial_id,
		_elapsed_s,
		score_miss_m,
		ground_miss_m,
		str(hit),
		str(direct_hit),
		int(trial.get("bomb_impacts", 0)),
		impact_offset_xz.x,
		impact_offset_xz.y,
		along_track_m,
		cross_track_m,
		needed_release_bias_s,
		predicted_needed_release_bias_s,
		drop_forward_speed_mps,
		predict_err_m,
		predicted_target_miss_m,
		predicted_along_track_m,
		predicted_cross_track_m,
		aim_miss_m,
		float(drop_context.get("release_miss_m", INF)),
		float(drop_context.get("release_best_miss_m", INF)),
		drop_range_m,
		_fmt_v3(drop_pos),
		_fmt_v2(forward_xz),
		_fmt_v3(predicted_impact) if has_predicted_impact else "none",
		_fmt_v3(aim_target) if has_aim_target else "none",
		_get_node_label(body),
		_fmt_v3(impact_position),
		_fmt_v3(target_pos),
	])

func _rocket_impact_body_matches_target(body: Node, target: Node3D) -> bool:
	if body == null or target == null or not is_instance_valid(body) or not is_instance_valid(target):
		return false
	var node: Node = body
	while node != null:
		if node == target:
			return true
		node = node.get_parent()
	return false

func _variant_to_node3d(value: Variant) -> Node3D:
	if value == null or typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null
	if not value is Node3D:
		return null
	return value as Node3D

func _get_node_label(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return "none"
	return "%s:%s" % [node.get_class(), node.name]

func _on_target_damaged(amount: float, health: float) -> void:
	_log_event("TARGET_DAMAGED t=%.1f amount=%.1f health=%.1f" % [_elapsed_s, amount, health])

func _on_target_destroyed() -> void:
	_log_event("TARGET_DESTROYED t=%.1f" % _elapsed_s)
