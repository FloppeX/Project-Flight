extends RefCounted
class_name AttackPlanner

const WEAPON_ROCKET := "rocket"
const WEAPON_GUN := "gun"
const WEAPON_BOMB := "bomb"

static func build_air_attack_plan(
		attacker: Node3D,
		targets: Array,
		weapon_options: Array,
		height_sampler: Callable,
		params: Dictionary = {}
) -> Dictionary:
	if attacker == null or not is_instance_valid(attacker):
		return {}
	if targets.is_empty() or weapon_options.is_empty():
		return {}

	var best_plan: Dictionary = {}
	var best_score := -INF
	for target_variant in targets:
		var target := _node3d_from_variant(target_variant)
		if target == null or not is_instance_valid(target):
			continue
		if _variant_truthy(target.get("is_destroyed")):
			continue
		for weapon_variant in weapon_options:
			if not (weapon_variant is Dictionary):
				continue
			var weapon: Dictionary = weapon_variant as Dictionary
			if weapon.is_empty():
				continue
			var plan := _build_best_lane_for_weapon(attacker, target, weapon, height_sampler, params)
			if plan.is_empty():
				continue
			var score := float(plan.get("score", -INF))
			if score > best_score:
				best_score = score
				best_plan = plan
	return best_plan


static func build_air_attack_plan_snapshot(
		attacker_pos: Vector3,
		targets: Array,
		weapon_options: Array,
		grid: Dictionary,
		params: Dictionary = {}
) -> Dictionary:
	if targets.is_empty() or weapon_options.is_empty():
		return {}

	var best_plan: Dictionary = {}
	var best_score := -INF
	for target_variant in targets:
		if not (target_variant is Dictionary):
			continue
		var target: Dictionary = target_variant as Dictionary
		var target_pos_variant: Variant = target.get("aim_position", target.get("position", Vector3.INF))
		if not (target_pos_variant is Vector3):
			continue
		var target_pos: Vector3 = target_pos_variant
		for weapon_variant in weapon_options:
			if not (weapon_variant is Dictionary):
				continue
			var weapon: Dictionary = weapon_variant as Dictionary
			if weapon.is_empty():
				continue
			var plan := _build_best_lane_for_weapon_snapshot(attacker_pos, target_pos, weapon, grid, params)
			if plan.is_empty():
				continue
			var score := float(plan.get("score", -INF))
			if score > best_score:
				best_score = score
				best_plan = plan
				best_plan["target_instance_id"] = int(target.get("instance_id", 0))
				best_plan["target_name"] = String(target.get("name", "target"))
				best_plan["target_position"] = target_pos
	return best_plan


static func _build_best_lane_for_weapon(
		attacker: Node3D,
		target: Node3D,
		weapon: Dictionary,
		height_sampler: Callable,
		params: Dictionary
) -> Dictionary:
	var weapon_kind := String(weapon.get("kind", ""))
	var profile: Dictionary = _weapon_profile(weapon_kind, params)
	profile = _apply_weapon_profile_overrides(profile, weapon)
	if profile.is_empty():
		return {}

	var current_pos: Vector3 = attacker.global_position
	var target_pos := _target_aim_position(target, float(params.get("target_aim_height_m", 1.2)))
	var min_plan_distance := float(profile.get("min_plan_distance_m", 350.0))
	var max_plan_distance := float(profile.get("max_plan_distance_m", 4500.0))
	var current_dist := _flat_distance(current_pos, target_pos)
	if current_dist < min_plan_distance or current_dist > max_plan_distance:
		return {}

	var attack_agl := float(profile.get("attack_agl_m", 85.0))
	var egress_agl := float(profile.get("egress_agl_m", attack_agl + 20.0))
	var ingress_dist := float(profile.get("ingress_distance_m", 950.0))
	var fire_start_dist := float(profile.get("fire_start_distance_m", 650.0))
	var fire_end_dist := float(profile.get("fire_end_distance_m", 250.0))
	var egress_dist := float(profile.get("egress_distance_m", 950.0))
	var egress_side := float(profile.get("egress_side_offset_m", 260.0))

	var lanes: Array[Vector3] = _candidate_attack_directions(current_pos, target_pos)
	var best_lane: Dictionary = {}
	var best_score := -INF
	for dir in lanes:
		var right := Vector3.UP.cross(dir).normalized()
		var ingress := target_pos - dir * ingress_dist
		var fire_start := target_pos - dir * fire_start_dist
		var fire_end := target_pos - dir * fire_end_dist

		ingress = _with_safe_altitude(ingress, attack_agl, height_sampler)
		fire_start = _with_safe_altitude(fire_start, attack_agl, height_sampler)
		fire_end = _with_safe_altitude(fire_end, attack_agl, height_sampler)
		if ingress == Vector3.INF or fire_start == Vector3.INF or fire_end == Vector3.INF:
			continue

		var clearance := float(profile.get("terrain_clearance_m", 45.0))
		var start_clearance := maxf(clearance - float(params.get("start_clearance_grace_m", 0.0)), 1.0)
		if not _segment_is_clear(current_pos, ingress, start_clearance, height_sampler):
			continue
		if not _segment_is_clear(ingress, fire_start, clearance, height_sampler):
			continue
		var corridor_clearance := clearance + float(params.get("fire_corridor_extra_clearance_m", 25.0))
		if not _corridor_is_clear(fire_start, fire_end, corridor_clearance, height_sampler):
			continue
		# Turning break-off egress (see snapshot path). Reject lane if no clear break.
		var egress := _find_clear_break_egress_sampler(fire_end, dir, right, egress_dist, egress_side, egress_agl, clearance, height_sampler)
		if egress == Vector3.INF:
			continue

		var alignment := 0.0
		var current_to_target := Vector3(target_pos.x - current_pos.x, 0.0, target_pos.z - current_pos.z)
		if current_to_target.length_squared() > 0.001:
			alignment = dir.dot(current_to_target.normalized())
		var distance_score := -current_dist * 0.001
		var weapon_score := float(profile.get("score_bias", 0.0))
		var lane_score := alignment * 2.0 + distance_score + weapon_score
		if lane_score > best_score:
			best_score = lane_score
			best_lane = {
				"target": target,
				"target_position": target_pos,
				"weapon": weapon,
				"weapon_kind": weapon_kind,
				"ingress": ingress,
				"fire_start": fire_start,
				"fire_end": fire_end,
				"egress": egress,
				"attack_direction": dir,
				"fire_range_m": float(profile.get("fire_range_m", 750.0)),
				"fire_cone_cos": cos(deg_to_rad(float(profile.get("fire_cone_deg", 10.0)))),
				"attack_speed_mps": float(profile.get("attack_speed_mps", 34.0)),
				"egress_speed_mps": float(profile.get("egress_speed_mps", 45.0)),
				"score": lane_score,
			}
	return best_lane


static func _build_best_lane_for_weapon_snapshot(
		current_pos: Vector3,
		target_pos: Vector3,
		weapon: Dictionary,
		grid: Dictionary,
		params: Dictionary
) -> Dictionary:
	var weapon_kind := String(weapon.get("kind", ""))
	var profile: Dictionary = _weapon_profile(weapon_kind, params)
	profile = _apply_weapon_profile_overrides(profile, weapon)
	if profile.is_empty():
		return {}

	var min_plan_distance := float(profile.get("min_plan_distance_m", 350.0))
	var max_plan_distance := float(profile.get("max_plan_distance_m", 4500.0))
	var current_dist := _flat_distance(current_pos, target_pos)
	if current_dist < min_plan_distance or current_dist > max_plan_distance:
		return {}

	var attack_agl := float(profile.get("attack_agl_m", 85.0))
	var egress_agl := float(profile.get("egress_agl_m", attack_agl + 20.0))
	var ingress_dist := float(profile.get("ingress_distance_m", 950.0))
	var fire_start_dist := float(profile.get("fire_start_distance_m", 650.0))
	var fire_end_dist := float(profile.get("fire_end_distance_m", 250.0))
	var egress_dist := float(profile.get("egress_distance_m", 950.0))
	var egress_side := float(profile.get("egress_side_offset_m", 260.0))

	var lanes: Array[Vector3] = _candidate_attack_directions(current_pos, target_pos)
	var best_lane: Dictionary = {}
	var best_score := -INF
	for dir in lanes:
		var right := Vector3.UP.cross(dir).normalized()
		var ingress := target_pos - dir * ingress_dist
		var fire_start := target_pos - dir * fire_start_dist
		var fire_end := target_pos - dir * fire_end_dist

		ingress = _with_safe_altitude_from_grid(ingress, attack_agl, grid)
		fire_start = _with_safe_altitude_from_grid(fire_start, attack_agl, grid)
		fire_end = _with_safe_altitude_from_grid(fire_end, attack_agl, grid)
		if ingress == Vector3.INF or fire_start == Vector3.INF or fire_end == Vector3.INF:
			continue

		var clearance := float(profile.get("terrain_clearance_m", 45.0))
		var start_clearance := maxf(clearance - float(params.get("start_clearance_grace_m", 0.0)), 1.0)
		if not _segment_is_clear_from_grid(current_pos, ingress, start_clearance, grid):
			continue
		if not _segment_is_clear_from_grid(ingress, fire_start, clearance, grid):
			continue
		# The firing corridor is flown as a committed straight line while the heli
		# pitches down to aim (it can't dodge here). Validate it with finer sampling
		# and extra clearance so a cliff rising into the run can't be missed between
		# coarse samples — this is the leg that produces head-first cliff crashes.
		var corridor_clearance := clearance + float(params.get("fire_corridor_extra_clearance_m", 25.0))
		if not _corridor_is_clear_from_grid(fire_start, fire_end, corridor_clearance, grid):
			continue

		# Egress is a TURNING break-off, not a straight overrun past the target (which
		# flew the heli into terrain behind defended positions). From fire_end, break
		# to whichever side is terrain-clear, angled back the way we came. Try both
		# sides and require the break leg to be clear; reject the lane if neither is.
		var egress := _find_clear_break_egress(fire_end, dir, right, egress_dist, egress_side, egress_agl, clearance, grid)
		if egress == Vector3.INF:
			continue

		var alignment := 0.0
		var current_to_target := Vector3(target_pos.x - current_pos.x, 0.0, target_pos.z - current_pos.z)
		if current_to_target.length_squared() > 0.001:
			alignment = dir.dot(current_to_target.normalized())
		var distance_score := -current_dist * 0.001
		var weapon_score := float(profile.get("score_bias", 0.0))
		var lane_score := alignment * 2.0 + distance_score + weapon_score
		if lane_score > best_score:
			best_score = lane_score
			best_lane = {
				"weapon_kind": weapon_kind,
				"ingress": ingress,
				"fire_start": fire_start,
				"fire_end": fire_end,
				"egress": egress,
				"attack_direction": dir,
				"fire_range_m": float(profile.get("fire_range_m", 750.0)),
				"fire_cone_cos": cos(deg_to_rad(float(profile.get("fire_cone_deg", 10.0)))),
				"attack_speed_mps": float(profile.get("attack_speed_mps", 34.0)),
				"egress_speed_mps": float(profile.get("egress_speed_mps", 45.0)),
				"score": lane_score,
			}
	return best_lane


static func _weapon_profile(weapon_kind: String, params: Dictionary) -> Dictionary:
	match weapon_kind:
		WEAPON_ROCKET:
			return {
				"score_bias": 3.0,
				"min_plan_distance_m": 450.0,
				"max_plan_distance_m": float(params.get("rocket_max_plan_distance_m", 5200.0)),
				"ingress_distance_m": 700.0,
				"fire_start_distance_m": 480.0,
				"fire_end_distance_m": 320.0,
				"egress_distance_m": 700.0,
				"egress_side_offset_m": 500.0,
				"attack_agl_m": float(params.get("rocket_attack_agl_m", 90.0)),
				"egress_agl_m": float(params.get("rocket_egress_agl_m", 125.0)),
				"terrain_clearance_m": float(params.get("rocket_terrain_clearance_m", 55.0)),
				"fire_range_m": 780.0,
				"fire_cone_deg": 9.0,
				"attack_speed_mps": 36.0,
				"egress_speed_mps": 48.0,
			}
		WEAPON_GUN:
			return {
				"score_bias": 1.0,
				"min_plan_distance_m": 250.0,
				"max_plan_distance_m": float(params.get("gun_max_plan_distance_m", 3200.0)),
				"ingress_distance_m": 560.0,
				"fire_start_distance_m": 400.0,
				"fire_end_distance_m": 240.0,
				"egress_distance_m": 600.0,
				"egress_side_offset_m": 420.0,
				"attack_agl_m": float(params.get("gun_attack_agl_m", 75.0)),
				"egress_agl_m": float(params.get("gun_egress_agl_m", 105.0)),
				"terrain_clearance_m": float(params.get("gun_terrain_clearance_m", 45.0)),
				"fire_range_m": 520.0,
				"fire_cone_deg": 14.0,
				"attack_speed_mps": 30.0,
				"egress_speed_mps": 42.0,
			}
		WEAPON_BOMB:
			if not _variant_truthy(params.get("allow_bombs", false)):
				return {}
			return {
				"score_bias": -1.0,
				"min_plan_distance_m": 650.0,
				"max_plan_distance_m": float(params.get("bomb_max_plan_distance_m", 5000.0)),
				"ingress_distance_m": 1200.0,
				"fire_start_distance_m": 180.0,
				"fire_end_distance_m": -80.0,
				"egress_distance_m": 1300.0,
				"egress_side_offset_m": 420.0,
				"attack_agl_m": float(params.get("bomb_attack_agl_m", 150.0)),
				"egress_agl_m": float(params.get("bomb_egress_agl_m", 190.0)),
				"terrain_clearance_m": float(params.get("bomb_terrain_clearance_m", 95.0)),
				"fire_range_m": 220.0,
				"fire_cone_deg": 18.0,
				"attack_speed_mps": 42.0,
				"egress_speed_mps": 55.0,
			}
	return {}


static func _apply_weapon_profile_overrides(profile: Dictionary, weapon: Dictionary) -> Dictionary:
	if profile.is_empty():
		return profile
	var out: Dictionary = profile.duplicate()
	if weapon.has("score_bias"):
		out["score_bias"] = float(weapon.get("score_bias", out.get("score_bias", 0.0)))
	return out


static func _candidate_attack_directions(current_pos: Vector3, target_pos: Vector3) -> Array[Vector3]:
	var dirs: Array[Vector3] = []
	var direct := Vector3(target_pos.x - current_pos.x, 0.0, target_pos.z - current_pos.z)
	if direct.length_squared() > 0.001:
		dirs.append(direct.normalized())
	for angle_deg in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		var r := deg_to_rad(angle_deg)
		dirs.append(Vector3(cos(r), 0.0, sin(r)).normalized())
	return dirs


static func _with_safe_altitude(point: Vector3, agl_m: float, height_sampler: Callable) -> Vector3:
	if not height_sampler.is_valid():
		return point
	var height_variant: Variant = height_sampler.call(point)
	if not (typeof(height_variant) in [TYPE_FLOAT, TYPE_INT]):
		return Vector3.INF
	var ground_h := float(height_variant)
	if is_nan(ground_h):
		return Vector3.INF
	return Vector3(point.x, ground_h + maxf(agl_m, 1.0), point.z)


static func _segment_is_clear(a: Vector3, b: Vector3, clearance_m: float, height_sampler: Callable) -> bool:
	if not height_sampler.is_valid():
		return true
	var distance := _flat_distance(a, b)
	var steps := maxi(ceili(distance / 120.0), 2)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var height_variant: Variant = height_sampler.call(p)
		if not (typeof(height_variant) in [TYPE_FLOAT, TYPE_INT]):
			return false
		var ground_h := float(height_variant)
		if is_nan(ground_h):
			return false
		if p.y < ground_h + clearance_m:
			return false
	return true


static func _find_clear_break_egress_sampler(
		fire_end: Vector3,
		dir: Vector3,
		right: Vector3,
		egress_dist: float,
		egress_side: float,
		egress_agl: float,
		clearance_m: float,
		height_sampler: Callable
) -> Vector3:
	var back := -dir
	var lateral := maxf(egress_side, 1.0)
	var behind := maxf(egress_dist * 0.5, 1.0)
	for side_sign in [1.0, -1.0]:
		var candidate: Vector3 = fire_end + right * lateral * side_sign + back * behind
		candidate = _with_safe_altitude(candidate, egress_agl, height_sampler)
		if candidate == Vector3.INF:
			continue
		if _segment_is_clear(fire_end, candidate, clearance_m, height_sampler):
			return candidate
	return Vector3.INF


static func _corridor_is_clear(a: Vector3, b: Vector3, clearance_m: float, height_sampler: Callable) -> bool:
	# Finer-sampled (30 m) corridor check for the committed firing run.
	if not height_sampler.is_valid():
		return true
	var distance := _flat_distance(a, b)
	var steps := maxi(ceili(distance / 30.0), 2)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var height_variant: Variant = height_sampler.call(p)
		if not (typeof(height_variant) in [TYPE_FLOAT, TYPE_INT]):
			return false
		var ground_h := float(height_variant)
		if is_nan(ground_h):
			return false
		if p.y < ground_h + clearance_m:
			return false
	return true


static func _with_safe_altitude_from_grid(point: Vector3, agl_m: float, grid: Dictionary) -> Vector3:
	var ground_h := _sample_grid_height(grid, point.x, point.z)
	if is_nan(ground_h):
		return Vector3.INF
	return Vector3(point.x, ground_h + maxf(agl_m, 1.0), point.z)


static func _segment_is_clear_from_grid(a: Vector3, b: Vector3, clearance_m: float, grid: Dictionary) -> bool:
	var distance := _flat_distance(a, b)
	var steps := maxi(ceili(distance / 120.0), 2)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var ground_h := _sample_grid_height(grid, p.x, p.z)
		if is_nan(ground_h):
			return false
		if p.y < ground_h + clearance_m:
			return false
	return true


static func _find_clear_break_egress(
		fire_end: Vector3,
		dir: Vector3,
		right: Vector3,
		egress_dist: float,
		egress_side: float,
		egress_agl: float,
		clearance_m: float,
		grid: Dictionary
) -> Vector3:
	# A break-off turn away from the firing direction: mostly lateral, partly back
	# toward where we came from (negative `dir`), never continuing forward past the
	# target. Try both sides and pick the first whose break leg is terrain-clear.
	var back := -dir
	var lateral := maxf(egress_side, 1.0)
	var behind := maxf(egress_dist * 0.5, 1.0)
	for side_sign in [1.0, -1.0]:
		var candidate: Vector3 = fire_end + right * lateral * side_sign + back * behind
		candidate = _with_safe_altitude_from_grid(candidate, egress_agl, grid)
		if candidate == Vector3.INF:
			continue
		if _segment_is_clear_from_grid(fire_end, candidate, clearance_m, grid):
			return candidate
	return Vector3.INF


static func _corridor_is_clear_from_grid(a: Vector3, b: Vector3, clearance_m: float, grid: Dictionary) -> bool:
	# Like _segment_is_clear_from_grid but with much finer sampling (30 m vs 120 m)
	# so a thin cliff or sharp rise inside the committed firing run can't slip
	# between samples. The corridor altitude interpolates a/b, matching the line
	# the heli actually flies.
	var distance := _flat_distance(a, b)
	var steps := maxi(ceili(distance / 30.0), 2)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var ground_h := _sample_grid_height(grid, p.x, p.z)
		if is_nan(ground_h):
			return false
		if p.y < ground_h + clearance_m:
			return false
	return true


static func _sample_grid_height(grid: Dictionary, wx: float, wz: float) -> float:
	var query_heights: PackedFloat32Array = grid.get("query_heights", PackedFloat32Array()) as PackedFloat32Array
	var query_cols := int(grid.get("query_cols", 0))
	var query_rows := int(grid.get("query_rows", 0))
	var query_cell_size := maxf(float(grid.get("query_cell_size", 1.0)), 1.0)
	var query_origin_x := float(grid.get("query_origin_x", 0.0))
	var query_origin_z := float(grid.get("query_origin_z", 0.0))
	var impassable := float(grid.get("impassable", -1000000.0))
	if query_cols > 0 and query_rows > 0 and not query_heights.is_empty():
		var qx := int(round((wx - query_origin_x) / query_cell_size))
		var qz := int(round((wz - query_origin_z) / query_cell_size))
		if qx >= 0 and qx < query_cols and qz >= 0 and qz < query_rows:
			var qh := query_heights[qz * query_cols + qx]
			if qh > impassable * 0.5:
				return qh

	var heights: PackedFloat32Array = grid.get("heights", PackedFloat32Array()) as PackedFloat32Array
	var cols := int(grid.get("cols", 0))
	var rows := int(grid.get("rows", 0))
	var cell_size := maxf(float(grid.get("cell_size", 1.0)), 1.0)
	var origin_x := float(grid.get("origin_x", 0.0))
	var origin_z := float(grid.get("origin_z", 0.0))
	if cols <= 0 or rows <= 0 or heights.is_empty():
		return NAN
	var gx := int(round((wx - origin_x) / cell_size))
	var gz := int(round((wz - origin_z) / cell_size))
	if gx < 0 or gx >= cols or gz < 0 or gz >= rows:
		return NAN
	var h := heights[gz * cols + gx]
	if h <= impassable * 0.5:
		return NAN
	return h


static func _target_aim_position(target: Node3D, aim_height_m: float) -> Vector3:
	var pos := target.global_position
	var body := target.get_node_or_null("Body") as Node3D
	if body != null:
		pos = body.global_position
	return pos + Vector3.UP * maxf(aim_height_m, 0.0)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _node3d_from_variant(value: Variant) -> Node3D:
	if value == null or typeof(value) != TYPE_OBJECT:
		return null
	if not is_instance_valid(value):
		return null
	if not (value is Node3D):
		return null
	return value as Node3D


static func _variant_truthy(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return float(value) != 0.0
	if value is String:
		var text := String(value).strip_edges().to_lower()
		return text == "true" or text == "1" or text == "yes" or text == "on"
	return value != null
