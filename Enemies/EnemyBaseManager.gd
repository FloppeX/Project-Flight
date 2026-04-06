extends Node
## Autoload - spawns and manages the two enemy bases.
## Base 0 (Crimson Pact) in the upper-left quadrant.
## Base 1 (Iron Veil) in the upper-right quadrant.
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

var bases: Array[EnemyBase] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	if TerrainNavGrid.is_ready():
		call_deferred("_spawn_bases")
	else:
		TerrainNavGrid.bake_complete.connect(_spawn_bases, CONNECT_ONE_SHOT)


func _spawn_bases() -> void:
	bases.clear()

	var center: Vector3 = TerrainNavGrid.get_bake_center()
	var half_ext: float = TerrainNavGrid.bake_half_extent_m
	var carrier_ground_y: float = _get_carrier_ground_level(center)

	# Base 0 upper-left, base 1 upper-right.
	for i in range(2):
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
