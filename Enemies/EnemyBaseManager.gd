extends Node
## Autoload - spawns and manages one enemy base.
## Base 0 (Crimson Pact) in the upper-left quadrant.
## "Upper" means lower Z values on the map.

const QUADRANT_MIN_REACH := 0.35 # min fraction of bake_half_extent for random target pick
const QUADRANT_MAX_REACH := 0.78 # max fraction of bake_half_extent for random target pick
const SEARCH_RADIUS_M := 2500.0  # how far to search around the random target
const SEARCH_STEP_M := 220.0     # grid step for flatness candidates
const PROBE_RADIUS_M := 180.0    # flatness probe spread
const MAX_SPAN_M := 28.0         # max height span to accept as "flat enough"
const MAX_HEIGHT_DELTA_FROM_CARRIER_M := 110.0
const HEIGHT_MATCH_WEIGHT := 0.22
const BASE_GROUND_CLEARANCE_M := 1.0
const EMPLACEMENT_SEARCH_ATTEMPTS := 32

var bases: Array[EnemyBase] = []
var emplacements: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _disabled_for_test: bool = false

@export_group("Enemy Emplacements")
@export var emplacement_scene: PackedScene = preload("res://Buildings/gun_emplacement.tscn")
@export var emplacement_clumps_per_team_min: int = 4
@export var emplacement_clumps_per_team_max: int = 5
@export var emplacements_per_clump_min: int = 1
@export var emplacements_per_clump_max: int = 3
@export var emplacement_cluster_spread_min_m: float = 18.0
@export var emplacement_cluster_spread_max_m: float = 75.0
@export var emplacement_map_margin_m: float = 500.0
@export var emplacement_activation_distance_m: float = 1700.0
@export var emplacement_spawn_debug: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	if TerrainNavGrid.is_ready():
		call_deferred("_spawn_bases")
	else:
		TerrainNavGrid.bake_complete.connect(_spawn_bases, CONNECT_ONE_SHOT)


func _spawn_bases() -> void:
	if _disabled_for_test:
		return
	bases.clear()
	_clear_managed_emplacements()

	var center: Vector3 = TerrainNavGrid.get_bake_center()
	var half_ext: float = TerrainNavGrid.bake_half_extent_m
	var carrier_ground_y: float = _get_carrier_ground_level(center)

	# Base 0 upper-left only.
	for i in range(1):
		var x_sign := -1.0 if i == 0 else 1.0
		var target: Vector2 = _pick_random_upper_quadrant_target(center, half_ext, x_sign)

		var pos := _find_flat_ground(target.x, target.y, carrier_ground_y, MAX_HEIGHT_DELTA_FROM_CARRIER_M)
		if pos == Vector3.INF:
			# Relax once if this quadrant has sparse matching terrain.
			pos = _find_flat_ground(target.x, target.y, carrier_ground_y, MAX_HEIGHT_DELTA_FROM_CARRIER_M * 1.8)
		if pos == Vector3.INF:
			# Final fallback: prioritize flatness only.
			pos = _find_flat_ground(target.x, target.y, carrier_ground_y, INF)

		if pos == Vector3.INF:
			push_warning("[EnemyBaseManager] No flat ground found for base %d - using target" % i)
			var h := TerrainNavGrid.sample_height(target.x, target.y)
			if h <= TerrainNavGrid.IMPASSABLE * 0.5:
				h = carrier_ground_y
			pos = Vector3(target.x, h, target.y)

		var base := EnemyBase.new()
		base.faction_id = i
		get_tree().current_scene.add_child(base)
		base.global_position = pos
		bases.append(base)
		print("[EnemyBaseManager] Base %d (%s) -> %.0f, %.0f (ground d=%.1fm)" % [
			i, EnemyBase.FACTION_NAMES[i], pos.x, pos.z, absf(pos.y - carrier_ground_y)
		])

	_spawn_enemy_emplacement_clumps(center, half_ext, carrier_ground_y)


func _find_flat_ground(cx: float, cz: float, reference_ground_y: float, max_height_delta_m: float) -> Vector3:
	var best_score := INF
	var best_pos := Vector3.INF

	var half := SEARCH_RADIUS_M
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			if x * x + z * z <= half * half:
				var wx := cx + x
				var wz := cz + z
				var result := _evaluate_flatness(wx, wz, reference_ground_y, max_height_delta_m)
				if result.valid and result.score < best_score:
					best_score = result.score
					best_pos = Vector3(wx, result.height + BASE_GROUND_CLEARANCE_M, wz)
			z += SEARCH_STEP_M
		x += SEARCH_STEP_M

	return best_pos


func _evaluate_flatness(cx: float, cz: float, reference_ground_y: float, max_height_delta_m: float) -> Dictionary:
	var r := PROBE_RADIUS_M
	var d := r * 0.707
	var sample_offsets := [
		Vector2(0.0, 0.0), Vector2(r, 0.0), Vector2(-r, 0.0),
		Vector2(0.0, r), Vector2(0.0, -r),
		Vector2(d, d), Vector2(-d, d), Vector2(d, -d), Vector2(-d, -d),
	]

	var heights: Array[float] = []
	for off in sample_offsets:
		var h := TerrainNavGrid.sample_height(cx + off.x, cz + off.y)
		if h <= TerrainNavGrid.IMPASSABLE * 0.5:
			return {"valid": false}
		heights.append(h)

	var min_h: float = heights[0]
	var max_h: float = heights[0]
	for h in heights:
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)

	var span := max_h - min_h
	var center_h: float = heights[0]
	var height_delta: float = absf(center_h - reference_ground_y)
	return {
		"valid": span < MAX_SPAN_M and (max_height_delta_m == INF or height_delta <= max_height_delta_m),
		"score": span + height_delta * HEIGHT_MATCH_WEIGHT,
		"height": center_h,
	}


func _pick_random_upper_quadrant_target(center: Vector3, half_ext: float, x_sign: float) -> Vector2:
	var reach_min := half_ext * QUADRANT_MIN_REACH
	var reach_max := half_ext * QUADRANT_MAX_REACH
	var x_off := _rng.randf_range(reach_min, reach_max) * x_sign
	var z_off := -_rng.randf_range(reach_min, reach_max)
	return Vector2(center.x + x_off, center.z + z_off)


func _get_carrier_ground_level(center: Vector3) -> float:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		var carrier_h := TerrainNavGrid.sample_height(carrier.global_position.x, carrier.global_position.z)
		if carrier_h > TerrainNavGrid.IMPASSABLE * 0.5:
			return carrier_h
	var center_h := TerrainNavGrid.sample_height(center.x, center.z)
	if center_h > TerrainNavGrid.IMPASSABLE * 0.5:
		return center_h
	return center.y


func _clear_managed_emplacements() -> void:
	var still_valid: Array[Node3D] = []
	for emplacement in emplacements:
		if not is_instance_valid(emplacement):
			continue
		if emplacement.has_meta("managed_enemy_emplacement") and bool(emplacement.get_meta("managed_enemy_emplacement")):
			emplacement.queue_free()
		else:
			still_valid.append(emplacement)
	emplacements = still_valid

	for node in get_tree().get_nodes_in_group("gun_emplacements"):
		if not (node is Node3D):
			continue
		var emplacement := node as Node3D
		if not is_instance_valid(emplacement):
			continue
		if emplacement.has_meta("managed_enemy_emplacement") and bool(emplacement.get_meta("managed_enemy_emplacement")):
			emplacement.queue_free()


func disable_for_heli_test() -> void:
	_disabled_for_test = true
	if TerrainNavGrid.bake_complete.is_connected(_spawn_bases):
		TerrainNavGrid.bake_complete.disconnect(_spawn_bases)
	for base in bases:
		if is_instance_valid(base):
			base.queue_free()
	bases.clear()
	_clear_managed_emplacements()
	emplacements.clear()
	print("[EnemyBaseManager] disabled for helicopter test")


func _spawn_enemy_emplacement_clumps(center: Vector3, half_ext: float, carrier_ground_y: float) -> void:
	if emplacement_scene == null:
		return

	var clumps_min: int = maxi(0, emplacement_clumps_per_team_min)
	var clumps_max: int = maxi(clumps_min, emplacement_clumps_per_team_max)
	var units_min: int = maxi(1, emplacements_per_clump_min)
	var units_max: int = maxi(units_min, emplacements_per_clump_max)
	var spread_min: float = maxf(emplacement_cluster_spread_min_m, 0.0)
	var spread_max: float = maxf(spread_min, emplacement_cluster_spread_max_m)

	for enemy_faction_id in range(1):
		var clump_count: int = _rng.randi_range(clumps_min, clumps_max)
		for clump_idx in range(clump_count):
			var clump_center: Vector3 = _find_random_emplacement_center(center, half_ext, carrier_ground_y)
			if clump_center == Vector3.INF:
				continue
			var units: int = _rng.randi_range(units_min, units_max)
			for unit_idx in range(units):
				var unit_position: Vector3 = clump_center
				if unit_idx > 0:
					var angle: float = _rng.randf_range(0.0, TAU)
					var dist: float = _rng.randf_range(spread_min, spread_max)
					var candidate_x: float = clump_center.x + cos(angle) * dist
					var candidate_z: float = clump_center.z + sin(angle) * dist
					var candidate_position: Vector3 = _find_flat_ground(candidate_x, candidate_z, carrier_ground_y, MAX_HEIGHT_DELTA_FROM_CARRIER_M * 1.8)
					if candidate_position != Vector3.INF:
						unit_position = candidate_position
				_spawn_single_emplacement(unit_position, enemy_faction_id)
				if emplacement_spawn_debug:
					print("[EnemyBaseManager] Emplacement faction=%d clump=%d unit=%d pos=(%.0f, %.0f)" % [
						enemy_faction_id, clump_idx, unit_idx, unit_position.x, unit_position.z
					])


func _find_random_emplacement_center(center: Vector3, half_ext: float, carrier_ground_y: float) -> Vector3:
	var margin: float = clampf(emplacement_map_margin_m, 0.0, maxf(half_ext - SEARCH_STEP_M, 0.0))
	var range_extent: float = maxf(half_ext - margin, SEARCH_STEP_M)
	for _attempt in range(EMPLACEMENT_SEARCH_ATTEMPTS):
		var tx: float = center.x + _rng.randf_range(-range_extent, range_extent)
		var tz: float = center.z + _rng.randf_range(-range_extent, range_extent)
		var result: Vector3 = _find_flat_ground(tx, tz, carrier_ground_y, MAX_HEIGHT_DELTA_FROM_CARRIER_M * 1.8)
		if result != Vector3.INF:
			return result
	return Vector3.INF


func _spawn_single_emplacement(world_position: Vector3, enemy_faction_id: int) -> void:
	var instance: Node = emplacement_scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		push_warning("[EnemyBaseManager] emplacement_scene must instantiate Node3D.")
		return

	var emplacement := instance as Node3D
	if "team" in emplacement:
		emplacement.set("team", 2)
	if "activation_distance_m" in emplacement:
		emplacement.set("activation_distance_m", maxf(emplacement_activation_distance_m, 50.0))
	get_tree().current_scene.add_child(emplacement)
	emplacement.global_position = world_position
	emplacement.rotation.y = _rng.randf_range(0.0, TAU)
	if emplacement.has_method("snap_collider_to_ground"):
		emplacement.call("snap_collider_to_ground")
	emplacement.set_meta("managed_enemy_emplacement", true)
	emplacement.set_meta("enemy_faction_id", enemy_faction_id)
	emplacements.append(emplacement)


func get_all_bases() -> Array[EnemyBase]:
	var valid: Array[EnemyBase] = []
	for base in bases:
		if is_instance_valid(base):
			valid.append(base)

	# Include runtime-spawned EnemyBase nodes (for example debug key spawns).
	for node in get_tree().get_nodes_in_group("enemy_bases"):
		if node is EnemyBase and is_instance_valid(node as EnemyBase):
			var enemy_base := node as EnemyBase
			if not valid.has(enemy_base):
				valid.append(enemy_base)

	bases = valid
	return valid
