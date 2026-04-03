extends Node3D

const FactionPaint = preload("res://FactionPaint.gd")

var restart_timer: Timer

@export var auto_place_carrier_on_flat_ground: bool = false
@export var carrier_node_path: NodePath = NodePath("LandCarrier")
@export var terrain_node_path: NodePath = NodePath("LowPolyTerrainPrototype")
@export var randomize_play_area_each_run: bool = true
@export var play_area_center_edge_margin_m: float = 2000.0
@export var play_area_randomization_debug: bool = false
@export var carrier_center_search_radius_m: float = 1400.0
@export var carrier_search_step_m: float = 120.0
@export var carrier_flat_probe_radius_m: float = 140.0
@export var carrier_ground_clearance_m: float = 40.0  # Carrier root floats 40m above terrain (tread ride height)
@export var carrier_placement_debug: bool = false

@export var spawn_enemy_base_at_start: bool = true
@export var enemy_base_scene: PackedScene = preload("res://Enemies/EnemyBase.tscn")
@export var enemy_base_min_distance_m: float = 4000.0
@export var enemy_base_max_distance_m: float = 9000.0
@export var enemy_base_preferred_distance_m: float = 6500.0
@export var enemy_base_search_attempts: int = 220
@export var enemy_base_search_step_m: float = 120.0
@export var enemy_base_height_bias_weight: float = 0.3
@export var enemy_base_ground_level_tolerance_m: float = 24.0
@export var enemy_base_quadrant_divider_margin_m: float = 800.0
@export var enemy_runway_max_ground_span_m: float = 4.0
@export var enemy_runway_top_clearance_m: float = 1.0
@export var enemy_runway_body_height_m: float = 2.0
@export var enemy_base_debug: bool = false

const BASE_YAW_CANDIDATES_DEG: Array[float] = [0.0, 45.0, 90.0, 135.0]
const RUNWAY_SAMPLE_X: Array[float] = [-180.0, -120.0, -60.0, 0.0, 60.0, 120.0, 180.0]
const RUNWAY_SAMPLE_Z: Array[float] = [-320.0, -240.0, -160.0, -80.0, 0.0, 80.0, 160.0, 240.0, 320.0]
const ENEMY_BASE_WAIT_FRAMES: int = 600
const ENEMY_BASE_BUILDING_COUNT_MIN: int = 5
const ENEMY_BASE_BUILDING_COUNT_MAX: int = 6
const MAP_PLACEMENT_MARGIN_M: float = 1200.0

var _scenario_play_area_center: Vector3 = Vector3.ZERO
var _scenario_play_area_center_valid: bool = false

func _enter_tree() -> void:
	_configure_play_area_for_run()

func _ready():
	if not _scenario_play_area_center_valid:
		_configure_play_area_for_run()
	var aircraft = find_child("Aircraft_1")
	if aircraft:
		aircraft.destroyed.connect(_on_aircraft_destroyed)
		aircraft.crashed.connect(_on_aircraft_crashed)
	if auto_place_carrier_on_flat_ground:
		call_deferred("_place_carrier_on_flat_ground")
	if spawn_enemy_base_at_start:
		call_deferred("_spawn_enemy_base_on_map")


func _input(_event):
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()


func _on_aircraft_destroyed():
	print("Aircraft destroyed! Restarting scene in 3 seconds...")
	restart_scene_after_delay(10.0)


func _on_aircraft_crashed(impact_velocity: float):
	if impact_velocity > 15.0:
		print("Aircraft crashed hard! Restarting scene in 3 seconds...")
		restart_scene_after_delay(3.0)


func restart_scene_after_delay(delay_seconds: float):
	if restart_timer:
		restart_timer.queue_free()

	restart_timer = Timer.new()
	add_child(restart_timer)
	restart_timer.one_shot = true
	restart_timer.timeout.connect(restart_scene)
	restart_timer.start(delay_seconds)


func restart_scene():
	get_tree().reload_current_scene()


func _place_carrier_on_flat_ground() -> void:
	var carrier := get_node_or_null(carrier_node_path) as Node3D
	var terrain := get_node_or_null(terrain_node_path) as Node3D
	if not carrier or not terrain or not terrain.has_method("get_height"):
		return

	var center: Vector3 = _scenario_play_area_center if _scenario_play_area_center_valid else terrain.global_position
	var radius: float = maxf(carrier_center_search_radius_m, 0.0)
	var step: float = maxf(carrier_search_step_m, 20.0)
	var probe: float = maxf(carrier_flat_probe_radius_m, step * 0.5)
	var radius_sq: float = radius * radius

	var best_score: float = INF
	var best_ground_y: float = NAN
	var best_xz: Vector2 = Vector2(center.x, center.z)
	var x: float = -radius
	while x <= radius + 0.001:
		var z: float = -radius
		while z <= radius + 0.001:
			if (x * x + z * z) <= radius_sq:
				var sample_x: float = center.x + x
				var sample_z: float = center.z + z
				var eval: Dictionary = _evaluate_terrain_flatness(terrain, sample_x, sample_z, probe)
				if eval.get("valid", false):
					var score: float = float(eval.get("score", INF))
					if score < best_score:
						best_score = score
						best_ground_y = float(eval.get("ground_y", NAN))
						best_xz = Vector2(sample_x, sample_z)
			z += step
		x += step

	if is_nan(best_ground_y):
		var fallback_ground: float = _sample_terrain_world_height(terrain, center.x, center.z)
		if is_nan(fallback_ground):
			return
		best_ground_y = fallback_ground
		best_xz = Vector2(center.x, center.z)

	carrier.global_position = Vector3(best_xz.x, best_ground_y + carrier_ground_clearance_m, best_xz.y)
	if carrier_placement_debug:
		print("[Main_Scene] Carrier placed on flat ground at ", carrier.global_position, " (score=", snapped(best_score, 0.01), ")")

func _configure_play_area_for_run() -> void:
	var terrain := get_node_or_null(terrain_node_path) as Node3D
	if terrain == null:
		return

	var center: Vector3 = terrain.global_position
	if randomize_play_area_each_run:
		center = _pick_random_play_area_center(terrain)
	center = _snap_play_area_center_to_nav_grid(center)

	_scenario_play_area_center = center
	_scenario_play_area_center_valid = true
	var current_bake_center: Vector3 = TerrainNavGrid.get_bake_center()
	var needs_rebake: bool = TerrainNavGrid.is_ready() and current_bake_center.distance_to(center) > 0.1
	if needs_rebake:
		TerrainNavGrid.rebake_at_center(center)
		NavGraph.rebuild_from_current_navgrid()
	else:
		TerrainNavGrid.set_bake_center_override(center)

	if play_area_randomization_debug:
		print("[ScenarioManager] Play area center set to ", center)

func _pick_random_play_area_center(terrain: Node3D) -> Vector3:
	var quads_x_variant = terrain.get("quads_x")
	var quads_z_variant = terrain.get("quads_z")
	var cell_size_variant = terrain.get("cell_size_m")
	var terrain_quads_x: int = int(quads_x_variant) if quads_x_variant != null else 0
	var terrain_quads_z: int = int(quads_z_variant) if quads_z_variant != null else 0
	var terrain_cell_size_m: float = float(cell_size_variant) if cell_size_variant != null else 0.0
	if terrain_quads_x <= 0 or terrain_quads_z <= 0 or terrain_cell_size_m <= 0.0:
		return terrain.global_position

	var terrain_half_span_x: float = float(terrain_quads_x) * terrain_cell_size_m * 0.5
	var terrain_half_span_z: float = float(terrain_quads_z) * terrain_cell_size_m * 0.5
	var required_margin_x: float = TerrainNavGrid.bake_half_extent_m + maxf(play_area_center_edge_margin_m, 0.0)
	var required_margin_z: float = TerrainNavGrid.bake_half_extent_m + maxf(play_area_center_edge_margin_m, 0.0)
	var max_offset_x: float = terrain_half_span_x - required_margin_x
	var max_offset_z: float = terrain_half_span_z - required_margin_z
	if max_offset_x <= 0.0 or max_offset_z <= 0.0:
		return terrain.global_position

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return Vector3(
		terrain.global_position.x + rng.randf_range(-max_offset_x, max_offset_x),
		terrain.global_position.y,
		terrain.global_position.z + rng.randf_range(-max_offset_z, max_offset_z)
	)

func _snap_play_area_center_to_nav_grid(center: Vector3) -> Vector3:
	var step_m: float = maxf(TerrainNavGrid.cell_size_m, 1.0)
	return Vector3(
		round(center.x / step_m) * step_m,
		center.y,
		round(center.z / step_m) * step_m
	)


func _spawn_enemy_base_on_map() -> void:
	if enemy_base_scene == null:
		return
	if get_node_or_null("EnemyBaseTopLeft") or get_node_or_null("EnemyBaseTopRight"):
		return

	var carrier := get_node_or_null(carrier_node_path) as Node3D
	var terrain := get_node_or_null(terrain_node_path) as Node3D
	if not carrier or not terrain or not terrain.has_method("get_height"):
		return

	var wait_frames: int = 0
	while wait_frames < ENEMY_BASE_WAIT_FRAMES and is_instance_valid(carrier) and not carrier.visible:
		wait_frames += 1
		await get_tree().process_frame
	if not is_instance_valid(carrier) or not is_instance_valid(terrain):
		return
	if not TerrainNavGrid.is_ready():
		return

	var map_bounds := _get_play_area_bounds()
	if map_bounds.is_empty():
		return

	var carrier_ground_y: float = _sample_terrain_world_height(terrain, carrier.global_position.x, carrier.global_position.z)
	var min_x: float = float(map_bounds.get("min_x", 0.0))
	var max_x: float = float(map_bounds.get("max_x", 0.0))
	var min_z: float = float(map_bounds.get("min_z", 0.0))
	var max_z: float = float(map_bounds.get("max_z", 0.0))
	var mid_x: float = (min_x + max_x) * 0.5
	var mid_z: float = (min_z + max_z) * 0.5
	var divider_margin_m: float = maxf(enemy_base_quadrant_divider_margin_m, 0.0)
	var top_z_max: float = mid_z - divider_margin_m
	var left_x_max: float = mid_x - divider_margin_m
	var right_x_min: float = mid_x + divider_margin_m
	if top_z_max <= min_z:
		top_z_max = mid_z
	if left_x_max <= min_x:
		left_x_max = mid_x
	if right_x_min >= max_x:
		right_x_min = mid_x

	var region_requests: Array[Dictionary] = [
		{
			"name": "EnemyBaseTopLeft",
			"region_name": "top-left",
			"min_x": min_x,
			"max_x": left_x_max,
			"min_z": min_z,
			"max_z": top_z_max
		},
		{
			"name": "EnemyBaseTopRight",
			"region_name": "top-right",
			"min_x": right_x_min,
			"max_x": max_x,
			"min_z": min_z,
			"max_z": top_z_max
		}
	]
	var base_identities := _build_enemy_base_visual_identities(region_requests.size())
	var placed_positions: Array[Vector3] = []
	for idx in range(region_requests.size()):
		var request: Dictionary = region_requests[idx]
		var placement := _find_enemy_base_placement_in_region(terrain, request, carrier_ground_y, placed_positions)
		if not bool(placement.get("valid", false)):
			if enemy_base_debug:
				push_warning("[Main_Scene] Could not find a valid %s enemy base placement" % str(request.get("region_name", "quadrant")))
			continue
		var identity: Dictionary = base_identities[idx] if idx < base_identities.size() else {}
		var enemy_base := _spawn_enemy_base_instance(str(request.get("name", "EnemyBase")), terrain, placement, identity)
		if enemy_base == null:
			continue
		placed_positions.append(placement.get("position", Vector3.ZERO))
		if enemy_base_debug:
			print(
				"[Main_Scene] Enemy base placed in ",
				request.get("region_name", "quadrant"),
				" at ",
				placement.get("position", Vector3.ZERO),
				" yaw=",
				float(placement.get("yaw_deg", 0.0)),
				" score=",
				snapped(float(placement.get("score", INF)), 0.01)
			)

func _spawn_enemy_base_instance(base_name: String, terrain: Node3D, placement: Dictionary, identity: Dictionary = {}) -> Node3D:
	var enemy_base := enemy_base_scene.instantiate() as Node3D
	if enemy_base == null:
		return null

	enemy_base.name = base_name
	add_child(enemy_base)

	var yaw_deg: float = float(placement.get("yaw_deg", 0.0))
	var position: Vector3 = placement.get("position", Vector3.ZERO)
	enemy_base.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), position)
	if not identity.is_empty() and enemy_base.has_method("configure_visual_identity"):
		enemy_base.call("configure_visual_identity", identity)
	if enemy_base.has_method("configure_layout"):
		enemy_base.call(
			"configure_layout",
			terrain,
			randi_range(ENEMY_BASE_BUILDING_COUNT_MIN, ENEMY_BASE_BUILDING_COUNT_MAX)
		)
	return enemy_base

func _get_play_area_bounds() -> Dictionary:
	if not TerrainNavGrid.is_ready():
		return {}
	var span_x: float = float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var span_z: float = float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	var min_x: float = TerrainNavGrid._origin_x + MAP_PLACEMENT_MARGIN_M
	var max_x: float = TerrainNavGrid._origin_x + span_x - MAP_PLACEMENT_MARGIN_M
	var min_z: float = TerrainNavGrid._origin_z + MAP_PLACEMENT_MARGIN_M
	var max_z: float = TerrainNavGrid._origin_z + span_z - MAP_PLACEMENT_MARGIN_M
	if min_x >= max_x or min_z >= max_z:
		return {}
	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
	}

func _build_enemy_base_visual_identities(count: int) -> Array[Dictionary]:
	var identities: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var attempts: int = 0
	var max_attempts: int = maxi(count * 16, 16)
	while identities.size() < count and attempts < max_attempts:
		attempts += 1
		var candidate: Dictionary = FactionPaint.build_random_scheme(rng)
		var is_unique := true
		for existing_identity in identities:
			if not _enemy_base_identities_are_distinct(existing_identity, candidate):
				is_unique = false
				break
		if is_unique:
			identities.append(candidate)
	while identities.size() < count:
		var fallback_identity: Dictionary = FactionPaint.build_random_scheme(rng)
		if not identities.is_empty():
			var primary_color: Color = fallback_identity.get("primary_color", Color(0.5, 0.5, 0.5, 1.0))
			primary_color = Color.from_hsv(wrapf(primary_color.h + 0.18 * float(identities.size()), 0.0, 1.0), primary_color.s, primary_color.v)
			fallback_identity["primary_color"] = primary_color
			fallback_identity["secondary_color"] = primary_color.lerp(Color.WHITE, 0.24)
		identities.append(fallback_identity)
	return identities

func _enemy_base_identities_are_distinct(a: Dictionary, b: Dictionary) -> bool:
	var a_primary: Color = a.get("primary_color", Color.BLACK)
	var b_primary: Color = b.get("primary_color", Color.BLACK)
	var color_distance: float = absf(a_primary.r - b_primary.r) + absf(a_primary.g - b_primary.g) + absf(a_primary.b - b_primary.b)
	if color_distance < 0.45:
		return false
	var insignia_count: int = FactionPaint.get_insignia_count()
	if insignia_count > 1 and a.get("insignia_texture", null) == b.get("insignia_texture", null):
		return false
	return true

func _find_enemy_base_placement_in_region(
	terrain: Node3D,
	region: Dictionary,
	carrier_ground_y: float,
	existing_positions: Array[Vector3]
) -> Dictionary:
	_enemy_base_search_state.score = INF
	_enemy_base_search_state.position = Vector3.ZERO
	_enemy_base_search_state.yaw_deg = 0.0

	var min_x: float = float(region.get("min_x", 0.0))
	var max_x: float = float(region.get("max_x", 0.0))
	var min_z: float = float(region.get("min_z", 0.0))
	var max_z: float = float(region.get("max_z", 0.0))
	if min_x >= max_x or min_z >= max_z:
		return {"valid": false}

	var region_center := Vector2((min_x + max_x) * 0.5, (min_z + max_z) * 0.5)
	var attempts: int = maxi(enemy_base_search_attempts, 1)
	for _attempt in range(attempts):
		var candidate_x: float = randf_range(min_x, max_x)
		var candidate_z: float = randf_range(min_z, max_z)
		_score_enemy_base_candidate_in_region(
			terrain,
			candidate_x,
			candidate_z,
			region_center,
			carrier_ground_y,
			existing_positions
		)

	if is_inf(_enemy_base_search_state.score):
		var step: float = maxf(enemy_base_search_step_m, 50.0)
		var x: float = min_x
		while x <= max_x + 0.001:
			var z: float = min_z
			while z <= max_z + 0.001:
				_score_enemy_base_candidate_in_region(
					terrain,
					x,
					z,
					region_center,
					carrier_ground_y,
					existing_positions
				)
				z += step
			x += step

	if is_inf(_enemy_base_search_state.score):
		return {"valid": false}

	return {
		"valid": true,
		"position": _enemy_base_search_state.position,
		"yaw_deg": _enemy_base_search_state.yaw_deg,
		"score": _enemy_base_search_state.score
	}

func _score_enemy_base_candidate_in_region(
	terrain: Node3D,
	candidate_x: float,
	candidate_z: float,
	region_center: Vector2,
	carrier_ground_y: float,
	existing_positions: Array[Vector3]
) -> void:
	var min_separation_m: float = maxf(MAP_PLACEMENT_MARGIN_M * 1.5, 1500.0)
	for existing_position in existing_positions:
		if Vector2(candidate_x - existing_position.x, candidate_z - existing_position.z).length() < min_separation_m:
			return

	for yaw_deg in BASE_YAW_CANDIDATES_DEG:
		var eval: Dictionary = _evaluate_runway_placement(terrain, candidate_x, candidate_z, yaw_deg)
		if not bool(eval.get("valid", false)):
			continue
		var ground_y: float = float(eval.get("ground_y", NAN))
		if not is_nan(carrier_ground_y):
			var level_delta_m: float = absf(ground_y - carrier_ground_y)
			if level_delta_m > maxf(enemy_base_ground_level_tolerance_m, 0.0):
				continue
		var placement_y: float = float(eval.get("placement_y", ground_y))
		var flat_score: float = float(eval.get("score", INF))
		var height_bias: float = 0.0 if is_nan(carrier_ground_y) else absf(ground_y - carrier_ground_y)
		var region_bias: float = Vector2(candidate_x - region_center.x, candidate_z - region_center.y).length()
		var total_score: float = flat_score * 220.0 + height_bias * 6.0 + region_bias * 0.01
		if total_score < _enemy_base_search_state.score:
			_enemy_base_search_state.score = total_score
			_enemy_base_search_state.position = Vector3(candidate_x, placement_y, candidate_z)
			_enemy_base_search_state.yaw_deg = yaw_deg


func _find_enemy_base_placement(carrier: Node3D, terrain: Node3D) -> Dictionary:
	_enemy_base_search_state.score = INF
	_enemy_base_search_state.position = Vector3.ZERO
	_enemy_base_search_state.yaw_deg = 0.0

	var best_score: float = INF
	var best_position: Vector3 = Vector3.ZERO
	var best_yaw_deg: float = 0.0

	var carrier_ground_y: float = _sample_terrain_world_height(terrain, carrier.global_position.x, carrier.global_position.z)
	var min_distance: float = maxf(enemy_base_min_distance_m, 0.0)
	var max_distance: float = maxf(enemy_base_max_distance_m, min_distance + 100.0)
	var preferred_distance: float = clampf(enemy_base_preferred_distance_m, min_distance, max_distance)

	var used_map_bounds: bool = false
	if TerrainNavGrid.is_ready():
		used_map_bounds = _score_enemy_base_candidates_in_map_bounds(
			carrier,
			terrain,
			min_distance,
			max_distance,
			preferred_distance,
			carrier_ground_y,
			best_score,
			best_position,
			best_yaw_deg
		)
		best_score = _enemy_base_search_state.score
		best_position = _enemy_base_search_state.position
		best_yaw_deg = _enemy_base_search_state.yaw_deg

	if is_inf(best_score):
		_score_enemy_base_candidates_in_distance_ring(
			carrier,
			terrain,
			min_distance,
			max_distance,
			preferred_distance,
			carrier_ground_y,
			best_score,
			best_position,
			best_yaw_deg
		)
		best_score = _enemy_base_search_state.score
		best_position = _enemy_base_search_state.position
		best_yaw_deg = _enemy_base_search_state.yaw_deg

	if is_inf(best_score):
		return {"valid": false}

	if enemy_base_debug and used_map_bounds:
		print("[Main_Scene] Enemy base search used tactical map bounds")

	return {
		"valid": true,
		"position": best_position,
		"yaw_deg": best_yaw_deg,
		"score": best_score
	}


var _enemy_base_search_state := {
	"score": INF,
	"position": Vector3.ZERO,
	"yaw_deg": 0.0,
}


func _score_enemy_base_candidates_in_map_bounds(
	carrier: Node3D,
	terrain: Node3D,
	min_distance: float,
	max_distance: float,
	preferred_distance: float,
	carrier_ground_y: float,
	_best_score: float,
	_best_position: Vector3,
	_best_yaw_deg: float
) -> bool:
	var span_x: float = float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var span_z: float = float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	var min_x: float = TerrainNavGrid._origin_x + MAP_PLACEMENT_MARGIN_M
	var max_x: float = TerrainNavGrid._origin_x + span_x - MAP_PLACEMENT_MARGIN_M
	var min_z: float = TerrainNavGrid._origin_z + MAP_PLACEMENT_MARGIN_M
	var max_z: float = TerrainNavGrid._origin_z + span_z - MAP_PLACEMENT_MARGIN_M
	if min_x >= max_x or min_z >= max_z:
		return false

	var attempts: int = maxi(enemy_base_search_attempts, 1)
	for _attempt in range(attempts):
		var candidate_x: float = randf_range(min_x, max_x)
		var candidate_z: float = randf_range(min_z, max_z)
		var distance_m: float = Vector2(candidate_x - carrier.global_position.x, candidate_z - carrier.global_position.z).length()
		if distance_m < min_distance or distance_m > max_distance:
			continue
		for yaw_deg in BASE_YAW_CANDIDATES_DEG:
			_score_enemy_base_candidate(terrain, candidate_x, candidate_z, yaw_deg, distance_m, preferred_distance, carrier_ground_y)
	return not is_inf(_enemy_base_search_state.score)


func _score_enemy_base_candidates_in_distance_ring(
	carrier: Node3D,
	terrain: Node3D,
	min_distance: float,
	max_distance: float,
	preferred_distance: float,
	carrier_ground_y: float,
	_best_score: float,
	_best_position: Vector3,
	_best_yaw_deg: float
) -> void:
	var step: float = maxf(enemy_base_search_step_m, 50.0)
	var max_distance_sq: float = max_distance * max_distance
	var min_distance_sq: float = min_distance * min_distance
	var x: float = -max_distance
	while x <= max_distance + 0.001:
		var z: float = -max_distance
		while z <= max_distance + 0.001:
			var dist_sq: float = x * x + z * z
			if dist_sq >= min_distance_sq and dist_sq <= max_distance_sq:
				var candidate_x: float = carrier.global_position.x + x
				var candidate_z: float = carrier.global_position.z + z
				var distance_m: float = sqrt(dist_sq)
				for yaw_deg in BASE_YAW_CANDIDATES_DEG:
					_score_enemy_base_candidate(terrain, candidate_x, candidate_z, yaw_deg, distance_m, preferred_distance, carrier_ground_y)
			z += step
		x += step


func _score_enemy_base_candidate(
	terrain: Node3D,
	candidate_x: float,
	candidate_z: float,
	yaw_deg: float,
	distance_m: float,
	preferred_distance: float,
	carrier_ground_y: float
) -> void:
	var eval: Dictionary = _evaluate_runway_placement(terrain, candidate_x, candidate_z, yaw_deg)
	if not bool(eval.get("valid", false)):
		return
	var ground_y: float = float(eval.get("ground_y", NAN))
	var placement_y: float = float(eval.get("placement_y", ground_y))
	var flat_score: float = float(eval.get("score", INF))
	var distance_bias: float = absf(distance_m - preferred_distance)
	var height_bias: float = 0.0 if is_nan(carrier_ground_y) else absf(ground_y - carrier_ground_y)
	var total_score: float = flat_score * 220.0 + distance_bias * 0.06 + height_bias * enemy_base_height_bias_weight
	if total_score < _enemy_base_search_state.score:
		_enemy_base_search_state.score = total_score
		_enemy_base_search_state.position = Vector3(candidate_x, placement_y, candidate_z)
		_enemy_base_search_state.yaw_deg = yaw_deg


func _evaluate_runway_placement(terrain: Node3D, x: float, z: float, yaw_deg: float) -> Dictionary:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var heights: Array[float] = []
	for sample_x in RUNWAY_SAMPLE_X:
		for sample_z in RUNWAY_SAMPLE_Z:
			var sample_offset := basis * Vector3(sample_x, 0.0, sample_z)
			var h: float = _sample_terrain_world_height(terrain, x + sample_offset.x, z + sample_offset.z)
			if is_nan(h):
				return {"valid": false}
			heights.append(h)

	if heights.is_empty():
		return {"valid": false}

	var center_h: float = _sample_terrain_world_height(terrain, x, z)
	if is_nan(center_h):
		return {"valid": false}

	var min_h: float = heights[0]
	var max_h: float = heights[0]
	var sum_h: float = 0.0
	for h in heights:
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
		sum_h += h

	var avg_h: float = sum_h / float(heights.size())
	var span: float = max_h - min_h
	if span > maxf(enemy_runway_max_ground_span_m, 0.1):
		return {"valid": false}

	var center_bias: float = absf(avg_h - center_h)
	var placement_y: float = max_h - maxf(enemy_runway_body_height_m, 0.1) + enemy_runway_top_clearance_m
	return {
		"valid": true,
		"score": span + center_bias * 0.5,
		"ground_y": center_h,
		"placement_y": placement_y
	}


func _evaluate_terrain_flatness(terrain: Node3D, x: float, z: float, probe_radius: float) -> Dictionary:
	var diag: float = probe_radius * 0.70710678
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(probe_radius, 0.0),
		Vector2(-probe_radius, 0.0),
		Vector2(0.0, probe_radius),
		Vector2(0.0, -probe_radius),
		Vector2(diag, diag),
		Vector2(-diag, diag),
		Vector2(diag, -diag),
		Vector2(-diag, -diag)
	]

	var heights: Array[float] = []
	for offset in offsets:
		var h: float = _sample_terrain_world_height(terrain, x + offset.x, z + offset.y)
		if is_nan(h):
			return {"valid": false}
		heights.append(h)

	var center_h: float = heights[0]
	var min_h: float = center_h
	var max_h: float = center_h
	var sum_h: float = 0.0
	for h in heights:
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
		sum_h += h

	var avg_h: float = sum_h / float(heights.size())
	var span: float = max_h - min_h
	var center_bias: float = absf(avg_h - center_h)
	var score: float = span + center_bias * 0.5
	return {
		"valid": true,
		"score": score,
		"ground_y": center_h
	}


func _sample_terrain_world_height(terrain: Node3D, world_x: float, world_z: float) -> float:
	var world_query := Vector3(world_x, terrain.global_position.y, world_z)
	var sampled_height: Variant = terrain.call("get_height", world_query)
	if typeof(sampled_height) != TYPE_FLOAT:
		return NAN
	var world_height: float = float(sampled_height)
	if is_nan(world_height):
		return NAN
	return world_height
