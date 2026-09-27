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
const BASE_NAV_CLEARANCE_M := 60.0
const BASE_NAV_ANCHOR_M := 260.0
const BASE_NAV_CANDIDATES_TO_CHECK := 18
const BASE_RANDOM_FALLBACK_ATTEMPTS := 140
const EMPLACEMENT_SEARCH_ATTEMPTS := 32

var bases: Array[EnemyBase] = []
var emplacements: Array[Node3D] = []
const OUTPOST_SCENE := preload("res://Buildings/building_enemy_outpost.tscn")
var outposts: Array[EnemyOutpost] = []
var _rng := RandomNumberGenerator.new()
var _disabled_for_test: bool = false

@export_group("Enemy Emplacements")
@export var emplacement_scene: PackedScene = preload("res://Buildings/gun_emplacement.tscn")
@export var dummy_emplacement_scene: PackedScene = preload("res://Buildings/dummy_gun_emplacement.tscn")
@export var emplacement_clumps_per_team_min: int = 4
@export var emplacement_clumps_per_team_max: int = 5
@export var emplacements_per_clump_min: int = 1
@export var emplacements_per_clump_max: int = 3
@export var emplacement_cluster_spread_min_m: float = 18.0
@export var emplacement_cluster_spread_max_m: float = 75.0
@export var emplacement_map_margin_m: float = 500.0
@export var emplacement_activation_distance_m: float = 1500.0
@export var emplacement_deactivation_distance_m: float = 1800.0
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
	# Anchor validation is mandatory once the grid is ready. Graph construction
	# now yields, so grid readiness no longer implies graph readiness.
	if not NavGraph.is_ready():
		if not NavGraph.graph_ready.is_connected(_spawn_bases):
			NavGraph.graph_ready.connect(_spawn_bases, CONNECT_ONE_SHOT)
		return
	bases.clear()
	_clear_managed_outposts()
	_clear_managed_emplacements()
	var pending := _get_pending_save_state()
	if not pending.is_empty():
		_spawn_bases_from_save(pending)
		return

	var center: Vector3 = TerrainNavGrid.get_bake_center()
	var half_ext: float = TerrainNavGrid.bake_half_extent_m
	var carrier_ground_y: float = _get_carrier_ground_level(center)

	# Base 0 upper-left only.
	for i in range(1):
		var x_sign := -1.0 if i == 0 else 1.0
		var target: Vector2 = _pick_random_upper_quadrant_target(center, half_ext, x_sign)

		var pos := _find_flat_ground(target.x, target.y, carrier_ground_y, MAX_HEIGHT_DELTA_FROM_CARRIER_M, true)
		if pos == Vector3.INF:
			# Relax once if this quadrant has sparse matching terrain.
			pos = _find_flat_ground(target.x, target.y, carrier_ground_y, MAX_HEIGHT_DELTA_FROM_CARRIER_M * 1.8, true)
		if pos == Vector3.INF:
			pos = _find_random_low_ground(carrier_ground_y, MAX_HEIGHT_DELTA_FROM_CARRIER_M * 1.8)
		if pos == Vector3.INF:
			pos = _find_flat_ground(target.x, target.y, carrier_ground_y, INF, false)

		if pos == Vector3.INF:
			push_warning("[EnemyBaseManager] No low flat ground found for base %d - using emergency fallback" % i)
			var fallback_slope_m: float = maxf(NavGraph.max_slope_m if NavGraph != null else 18.0, 36.0)
			var fallback_pos := TerrainNavGrid.get_random_passable_position(_rng, fallback_slope_m, 5000)
			if fallback_pos != Vector3.ZERO:
				pos = fallback_pos + Vector3.UP * BASE_GROUND_CLEARANCE_M
			else:
				var h := TerrainNavGrid.sample_height(center.x, center.z)
				if h <= TerrainNavGrid.IMPASSABLE * 0.5:
					h = carrier_ground_y
				pos = Vector3(center.x, h + BASE_GROUND_CLEARANCE_M, center.z)

		var base := EnemyBase.new()
		base.faction_id = i
		get_tree().current_scene.add_child(base)
		base.global_position = pos
		bases.append(base)
		print("[EnemyBaseManager] Base %d (%s) -> %.0f, %.0f (ground d=%.1fm)" % [
			i, EnemyBase.FACTION_NAMES[i], pos.x, pos.z, absf(pos.y - carrier_ground_y)
		])

	_spawn_enemy_emplacement_clumps(center, half_ext, carrier_ground_y)
	_spawn_outposts(center, half_ext)


func enable_for_game() -> void:
	_disabled_for_test = false
	if TerrainNavGrid.is_ready():
		call_deferred("_spawn_bases")
		return
	if not TerrainNavGrid.bake_complete.is_connected(_spawn_bases):
		TerrainNavGrid.bake_complete.connect(_spawn_bases, CONNECT_ONE_SHOT)


func _find_flat_ground(cx: float, cz: float, reference_ground_y: float, max_height_delta_m: float, require_nav_anchor: bool = false) -> Vector3:
	var best_score := INF
	var best_pos := Vector3.INF
	var candidates: Array[Dictionary] = []

	var half := SEARCH_RADIUS_M
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			if x * x + z * z <= half * half:
				var wx := cx + x
				var wz := cz + z
				var result: Dictionary = _evaluate_flatness(wx, wz, reference_ground_y, max_height_delta_m)
				if bool(result.get("valid", false)):
					var score: float = float(result.get("score", INF))
					var candidate_pos := Vector3(wx, float(result.get("height", reference_ground_y)) + BASE_GROUND_CLEARANCE_M, wz)
					candidates.append({"position": candidate_pos, "score": score})
					if score < best_score:
						best_score = score
						best_pos = candidate_pos
			z += SEARCH_STEP_M
		x += SEARCH_STEP_M

	if not require_nav_anchor or not NavGraph.is_ready():
		return best_pos
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", INF)) < float(b.get("score", INF))
	)
	var nav_checks: int = mini(candidates.size(), BASE_NAV_CANDIDATES_TO_CHECK)
	for i in range(nav_checks):
		var entry: Dictionary = candidates[i]
		var candidate_pos: Vector3 = entry.get("position", Vector3.INF) as Vector3
		if NavGraph.can_anchor(candidate_pos, BASE_NAV_CLEARANCE_M, BASE_NAV_ANCHOR_M):
			return candidate_pos
	return Vector3.INF


func _find_random_low_ground(reference_ground_y: float, max_height_delta_m: float) -> Vector3:
	var fallback_slope_m: float = NavGraph.max_slope_m if NavGraph != null else 18.0
	for _attempt in range(BASE_RANDOM_FALLBACK_ATTEMPTS):
		var candidate: Vector3 = TerrainNavGrid.get_random_passable_position(_rng, fallback_slope_m, 120)
		if candidate == Vector3.ZERO:
			continue
		if max_height_delta_m != INF and absf(candidate.y - reference_ground_y) > max_height_delta_m:
			continue
		var base_pos := candidate + Vector3.UP * BASE_GROUND_CLEARANCE_M
		if NavGraph.is_ready() and not NavGraph.can_anchor(base_pos, BASE_NAV_CLEARANCE_M, BASE_NAV_ANCHOR_M):
			continue
		return base_pos
	return Vector3.INF


func _evaluate_flatness(cx: float, cz: float, reference_ground_y: float, max_height_delta_m: float) -> Dictionary:
	var max_slope_m: float = NavGraph.max_slope_m if NavGraph != null else 18.0
	if not TerrainNavGrid.is_low_clear_position(cx, cz, max_slope_m):
		return {"valid": false}

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
	for wreck in get_tree().get_nodes_in_group("building_wrecks"):
		if bool(wreck.get_meta("managed_enemy_emplacement_wreck", false)):
			wreck.queue_free()
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
	_clear_managed_outposts()
	if NavGraph.graph_ready.is_connected(_spawn_bases):
		NavGraph.graph_ready.disconnect(_spawn_bases)
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
					var candidate_position: Vector3 = _find_flat_ground(candidate_x, candidate_z, carrier_ground_y, MAX_HEIGHT_DELTA_FROM_CARRIER_M * 1.8, false)
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
		var result: Vector3 = _find_flat_ground(tx, tz, carrier_ground_y, MAX_HEIGHT_DELTA_FROM_CARRIER_M * 1.8, false)
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
	if "deactivation_distance_m" in emplacement:
		emplacement.set("deactivation_distance_m", maxf(emplacement_deactivation_distance_m, emplacement_activation_distance_m))
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


func capture_save_state() -> Dictionary:
	var outpost_states: Array[Dictionary] = []
	for outpost in outposts:
		if is_instance_valid(outpost):
			outpost_states.append(outpost.capture_save_state())
	var base_states: Array[Dictionary] = []
	for base in get_all_bases():
		base_states.append(base.capture_save_state())
	var emplacement_states: Array[Dictionary] = []
	for emplacement in emplacements:
		if not is_instance_valid(emplacement):
			continue
		if emplacement.is_queued_for_deletion() or bool(emplacement.get("is_destroyed")):
			continue
		emplacement_states.append({
			"position": emplacement.global_position,
			"rotation": emplacement.global_rotation,
			"team": int(emplacement.get("team")) if emplacement.get("team") != null else 2,
			"current_health": float(emplacement.get("current_health")) if emplacement.get("current_health") != null else -1.0,
			"enemy_faction_id": int(emplacement.get_meta("enemy_faction_id", 0)),
		})
	for wreck in get_tree().get_nodes_in_group("building_wrecks"):
		if not wreck is Node3D or not bool(wreck.get_meta("managed_enemy_emplacement_wreck", false)):
			continue
		emplacement_states.append({"position": wreck.global_position,
			"rotation": wreck.global_rotation, "is_destroyed": true,
			"main_color": wreck.get_meta("emplacement_main_color", Livery.get_team_upper_color(2)),
			"enemy_faction_id": int(wreck.get_meta("enemy_faction_id", 0))})
	return {"bases": base_states, "emplacements": emplacement_states, "outposts": outpost_states}


func _get_pending_save_state() -> Dictionary:
	if GameSession == null or not GameSession.has_pending_save_state():
		return {}
	var campaign := GameSession.peek_pending_campaign_state()
	var state_variant: Variant = campaign.get("enemy_bases", {})
	return state_variant as Dictionary if state_variant is Dictionary else {}


func _spawn_bases_from_save(state: Dictionary) -> void:
	var bases_variant: Variant = state.get("bases", [])
	if bases_variant is Array:
		for base_state_variant in bases_variant:
			if not (base_state_variant is Dictionary):
				continue
			var base_state := base_state_variant as Dictionary
			var base := EnemyBase.new()
			base.faction_id = int(base_state.get("faction_id", 0))
			base.position = base_state.get("position", Vector3.ZERO) as Vector3
			get_tree().current_scene.add_child(base)
			base.restore_save_state(base_state)
			bases.append(base)
	var emplacements_variant: Variant = state.get("emplacements", [])
	if emplacements_variant is Array:
		for emplacement_state_variant in emplacements_variant:
			if not (emplacement_state_variant is Dictionary):
				continue
			var emplacement_state := emplacement_state_variant as Dictionary
			if bool(emplacement_state.get("is_destroyed", false)):
				var wreck := preload("res://Buildings/gun_emplacement_destroyed.tscn").instantiate() as Node3D
				wreck.position = emplacement_state.get("position", Vector3.ZERO)
				wreck.rotation = emplacement_state.get("rotation", Vector3.ZERO)
				wreck.set_meta("managed_enemy_emplacement_wreck", true)
				wreck.set_meta("emplacement_main_color", emplacement_state.get("main_color", Livery.get_team_upper_color(2)))
				wreck.set_meta("enemy_faction_id", int(emplacement_state.get("enemy_faction_id", 0)))
				get_tree().current_scene.add_child(wreck)
				continue
			_spawn_single_emplacement(
				emplacement_state.get("position", Vector3.ZERO) as Vector3,
				int(emplacement_state.get("enemy_faction_id", 0))
			)
			if not emplacements.is_empty():
				var emplacement: Node3D = emplacements.back()
				emplacement.global_rotation = emplacement_state.get("rotation", Vector3.ZERO) as Vector3
				var saved_health := float(emplacement_state.get("current_health", -1.0))
				if saved_health >= 0.0 and "current_health" in emplacement:
					emplacement.set("current_health", saved_health)
	print("[EnemyBaseManager] Restored %d enemy base(s)" % bases.size())
	for entry: Dictionary in state.get("outposts", []):
		var outpost := _add_outpost(entry.position, str(entry.outpost_id), int(entry.get("faction_id", 0)))
		outpost.rotation = entry.get("rotation", Vector3.ZERO)
		outpost.restore_save_state(entry)
	# Older checkpoints retain their existing force structure; new regions get a network.


func get_outposts_for_base(base: EnemyBase) -> Array[EnemyOutpost]:
	var result: Array[EnemyOutpost] = []
	for outpost in outposts:
		if is_instance_valid(outpost) and outpost.faction_id == base.faction_id:
			result.append(outpost)
	return result


func _clear_managed_outposts() -> void:
	for outpost in outposts:
		if is_instance_valid(outpost):
			outpost.queue_free()
	outposts.clear()


func _add_outpost(location: Vector3, id: String, faction: int) -> EnemyOutpost:
	var outpost := OUTPOST_SCENE.instantiate() as EnemyOutpost
	outpost.outpost_id = id
	outpost.faction_id = faction
	outpost.position = location
	get_tree().current_scene.add_child(outpost)
	outposts.append(outpost)
	return outpost


func _spawn_outposts(center: Vector3, half_extent: float) -> void:
	if bases.is_empty() or GameSession.is_trailer_scenario:
		return
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	var start := carrier.global_position if carrier != null else center
	# Six separate compounds across two rows of the map, in addition to the base.
	# Bounded jitter preserves regional coverage while allowing flat-pad searches.
	var sectors: Array[Vector2] = [
		Vector2(-0.55, -0.4), Vector2(0.0, -0.4), Vector2(0.55, -0.4),
		Vector2(-0.55, 0.4), Vector2(0.0, 0.4), Vector2(0.55, 0.4),
	]
	for index in range(sectors.size()):
		var chosen := Vector3.INF
		var compound_positions: Array[Vector3] = []
		for attempt in range(180):
			var sector := sectors[index] * half_extent
			var jitter := Vector2(_rng.randf_range(-0.18, 0.18), _rng.randf_range(-0.18, 0.18)) * half_extent
			var x := center.x + sector.x + jitter.x
			var z := center.z + sector.y + jitter.y
			var h := EnemyOutpost.sample_terrain_height(x, z)
			if not is_finite(h) or h <= TerrainNavGrid.IMPASSABLE * 0.5:
				continue
			var candidate := Vector3(x, h, z)
			if candidate.distance_to(start) < 6000.0 or candidate.distance_to(bases[0].global_position) < 3000.0:
				continue
			var spaced := true
			for other in outposts:
				if candidate.distance_to(other.global_position) < 6000.0:
					spaced = false
			if not spaced:
				continue
			# The authored footprint is about 17 by 13 metres; check the whole pad.
			var low := h
			var high := h
			for dx in [-10.0, -5.0, 0.0, 5.0, 10.0]:
				for dz in [-10.0, -5.0, 0.0, 5.0, 10.0]:
					var sample := EnemyOutpost.sample_terrain_height(x + dx, z + dz)
					if not is_finite(sample):
						sample = TerrainNavGrid.IMPASSABLE
					low = minf(low, sample)
					high = maxf(high, sample)
			if high - low > 1.5 or not NavGraph.can_anchor(candidate, 20.0, 260.0):
				continue
			chosen = Vector3(x, low, z)
			compound_positions = _find_outpost_compound_pads(chosen)
			if compound_positions.is_empty():
				chosen = Vector3.INF
				continue
			break
		if chosen == Vector3.INF:
			push_warning("[EnemyBaseManager] No suitable footprint for outpost %d" % (index + 1))
			continue
		var station := _add_outpost(chosen, "OP-%02d" % (index + 1), bases[0].faction_id)
		_populate_outpost_compound(station, compound_positions)
	print("[EnemyBaseManager] Spawned %d observation outposts" % outposts.size())


func _find_outpost_compound_pads(center: Vector3) -> Array[Vector3]:
	# Keep the bay's +Z doorway clear, with guns outside both building footprints.
	var offsets: Array[Vector3] = [Vector3(32, 0, 0), Vector3(-30, 0, -30), Vector3(0, 0, 38), Vector3(40, 0, -32)]
	var pads: Array[Vector3] = []
	for i in offsets.size():
		var point := center + offsets[i]
		var radius := 14.0 if i == 0 else 6.0
		var low := INF
		var high := -INF
		for x in range(5):
			for z in range(5):
				var height := EnemyOutpost.sample_terrain_height(point.x + lerpf(-radius, radius, x / 4.0), point.z + lerpf(-radius, radius, z / 4.0))
				if not is_finite(height) or height <= TerrainNavGrid.IMPASSABLE * 0.5: return []
				low = minf(low, height)
				high = maxf(high, height)
		if high - low > 1.5: return []
		point.y = low
		pads.append(point)
	return pads


func _populate_outpost_compound(station: EnemyOutpost, pads: Array[Vector3]) -> void:
	if pads.size() != 4: return
	station.add_vehicle_bay(station.to_local(pads[0]))
	for i in range(1, pads.size()):
		_spawn_single_emplacement(pads[i], station.faction_id)
