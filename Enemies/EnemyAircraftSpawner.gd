extends Node3D

@export var spawn_altitude: float = 600.0
@export var spawn_speed: float = 60.0
@export var respawn_delay: float = 3.0
@export var patrol_side_length: float = 2000.0
@export var max_ai_planes: int = 10
@export var duel_range_from_carrier_m: float = 1000.0
@export var duel_altitude_m: float = 600.0
@export var strike_flight_range_from_carrier_m: float = 5000.0
@export var strike_flight_altitude_m: float = 600.0
@export var cap_flight_altitude_m: float = 600.0
@export var cap_orbit_radius_m: float = 1200.0
@export var friendly_debug_flight_altitude_m: float = 500.0
@export var enemy_debug_flight_range_from_carrier_m: float = 4000.0
@export var debug_air_spawn_spacing_m: float = 180.0
@export var debug_air_spawn_map_margin_m: float = 500.0
@export var debug_air_spawn_direction_attempts: int = 24
@export var debug_ground_vehicle_spawns: bool = true
@export var ground_vehicle_spawn_probe_radius_m: float = 12.0
@export var ground_vehicle_spawn_max_height_delta_m: float = 4.0
@export var ground_vehicle_spawn_search_radius_m: float = 36.0
@export var ground_vehicle_spawn_search_attempts: int = 14
@export var ground_vehicle_spawn_path_clearance_m: float = 60.0
@export var ground_vehicle_spawn_anchor_distance_m: float = 180.0
@export var enemy_platoon_spawn_min_range_m: float = 7000.0
@export var enemy_platoon_spawn_max_range_m: float = 12000.0
@export var enemy_platoon_spawn_attempts: int = 72
@export var enemy_platoon_spawn_map_margin_m: float = 360.0
@export var enemy_base_max_height_delta_from_carrier_m: float = 120.0
@export var enemy_base_height_match_weight: float = 0.25
@export var enemy_base_flatness_goal_m: float = 5.0

var _aircraft_scene: PackedScene
var _aircraft_3_scene: PackedScene
var _aircraft_4_scene: PackedScene
var _aircraft_5_scene: PackedScene
var _aircraft_6_scene: PackedScene
var _enemy_aircraft_scene: PackedScene
var _active_ai_planes: Array[RigidBody3D] = []
var _enemy_vehicle_scenes: Array[PackedScene] = []
var _friendly_vehicle_scene: PackedScene
var _ground_platoon_counter: int = 0
var _disabled_for_heli_test: bool = false

func _ready():
	add_to_group("enemy_aircraft_spawner")
	_aircraft_scene = load("res://Aircraft/Aircraft_1.tscn")
	if not _aircraft_scene:
		push_error("[EnemyAircraftSpawner] Failed to load Aircraft_1.tscn")
	_aircraft_3_scene = load("res://Aircraft/Aircraft_3.tscn")
	if not _aircraft_3_scene:
		push_error("[EnemyAircraftSpawner] Failed to load Aircraft/Aircraft_3.tscn")
	_aircraft_4_scene = load("res://Aircraft/Aircraft_4.tscn")
	if not _aircraft_4_scene:
		push_error("[EnemyAircraftSpawner] Failed to load Aircraft/Aircraft_4.tscn")
	_aircraft_5_scene = load("res://Aircraft/Aircraft_5.tscn")
	if not _aircraft_5_scene:
		push_error("[EnemyAircraftSpawner] Failed to load Aircraft/Aircraft_5.tscn")
	_aircraft_6_scene = load("res://Aircraft/Aircraft_6.tscn")
	if not _aircraft_6_scene:
		push_error("[EnemyAircraftSpawner] Failed to load Aircraft/Aircraft_6.tscn")
	_enemy_aircraft_scene = _aircraft_3_scene
	_enemy_vehicle_scenes.clear()
	for vehicle_path in [
		"res://GroundVehicle/vehicle_enemy_buggy.tscn",
		"res://GroundVehicle/vehicle_enemy_pickup.tscn",
		"res://GroundVehicle/vehicle_enemy_battle_bus.tscn",
	]:
		var vehicle_scene := load(vehicle_path) as PackedScene
		if vehicle_scene:
			_enemy_vehicle_scenes.append(vehicle_scene)
		else:
			push_error("[EnemyAircraftSpawner] Failed to load %s" % vehicle_path)
	_friendly_vehicle_scene = load("res://GroundVehicle/vehicle_friendly_light.tscn")

func _input(event):
	pass

func _spawn_ground_vehicles(scene: PackedScene, count: int) -> void:
	if _disabled_for_heli_test:
		return
	if not scene:
		return
	var carrier_pos: Vector3 = _get_carrier_position()
	var carrier_node := get_tree().get_first_node_in_group("carrier") as CollisionObject3D
	var base_pos: Vector3 = carrier_pos
	var team_id := 1 if scene == _friendly_vehicle_scene else 2
	if team_id == 1:
		base_pos = _find_friendly_vehicle_staging_position(carrier_pos, carrier_node)
	else:
		base_pos = _find_enemy_vehicle_staging_position(carrier_pos, carrier_node)
	base_pos = _find_nearby_valid_ground_spawn(base_pos, carrier_node, carrier_pos, true)
	var scenes: Array[PackedScene] = [scene]
	_spawn_ground_vehicle_wave(scenes, count, team_id, carrier_pos, base_pos, carrier_node)

func _spawn_enemy_vehicle_mix(count: int) -> void:
	if _disabled_for_heli_test:
		return
	if _enemy_vehicle_scenes.is_empty():
		print("[EnemyAircraftSpawner] E: no enemy vehicle scenes loaded")
		return
	var carrier_pos: Vector3 = _get_carrier_position()
	var carrier_node := get_tree().get_first_node_in_group("carrier") as CollisionObject3D
	var base_pos := _find_enemy_platoon_staging_position(carrier_pos, carrier_node)
	base_pos = _find_nearby_valid_ground_spawn(base_pos, carrier_node, carrier_pos, true, true, enemy_platoon_spawn_map_margin_m)
	var compact_offsets: Array[Vector3] = [
		Vector3(-12, 0, -8),
		Vector3(10, 0, -6),
		Vector3(-6, 0, 12),
		Vector3(14, 0, 10),
	]
	_spawn_ground_vehicle_wave(_enemy_vehicle_scenes, count, 2, carrier_pos, base_pos, carrier_node, compact_offsets, true, enemy_platoon_spawn_map_margin_m)

func _spawn_ground_vehicle_wave(scenes: Array[PackedScene], count: int, team_id: int, carrier_pos: Vector3, base_pos: Vector3, carrier_node: CollisionObject3D = null, offsets_override: Array[Vector3] = [], require_map_bounds: bool = false, map_margin_m: float = 0.0) -> void:
	if scenes.is_empty():
		return
	if debug_ground_vehicle_spawns:
		print("[GroundSpawn] team=%d carrier=%s base=%s" % [
			team_id,
			str(carrier_pos),
			str(base_pos)
		])
	# Generate shared patrol waypoints around the spawn cluster (4 points, 150-300m out)
	var patrol_positions: Array[Vector3] = []
	for w in range(4):
		var angle := w * TAU / 4.0 + randf_range(-0.3, 0.3)
		var dist := randf_range(150.0, 300.0)
		var wp := Vector3(base_pos.x + cos(angle) * dist, 0.0, base_pos.z + sin(angle) * dist)
		wp = _find_nearby_valid_ground_spawn(wp, carrier_node, carrier_pos, false, require_map_bounds, map_margin_m)
		patrol_positions.append(wp)

	var platoon := GroundVehiclePlatoon.new()
	_ground_platoon_counter += 1
	platoon.name = "GroundPlatoon_%d" % _ground_platoon_counter
	platoon.platoon_id = platoon.name
	platoon.team = team_id
	platoon.global_position = base_pos
	get_tree().current_scene.add_child(platoon)
	if platoon.team == 1:
		var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
		if carrier:
			platoon.set_protect_node(carrier, 450.0)
		elif not patrol_positions.is_empty():
			platoon.set_move_objective(patrol_positions[0])
	else:
		var attack_carrier := get_tree().get_first_node_in_group("carrier") as Node3D
		if attack_carrier:
			platoon.set_attack_node(attack_carrier, 500.0)
		else:
			platoon.set_pursue_enemies(1800.0)

	var offsets: Array[Vector3] = offsets_override if not offsets_override.is_empty() else [
		Vector3(-35, 0, 0),
		Vector3(0, 0, 35),
		Vector3(35, 0, -15),
		Vector3(-15, 0, -35),
		Vector3(20, 0, 18),
	]
	for i in range(count):
		var off: Vector3 = offsets[i] if i < offsets.size() else Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
		var desired_spawn := Vector3(base_pos.x + off.x, base_pos.y, base_pos.z + off.z)
		var spawn_pos := _find_nearby_valid_ground_spawn(desired_spawn, carrier_node, carrier_pos, false, require_map_bounds, map_margin_m)

		var vehicle_scene := scenes[randi() % scenes.size()]
		var vehicle := vehicle_scene.instantiate() as Node3D
		get_tree().current_scene.add_child(vehicle)
		vehicle.global_position = spawn_pos
		if debug_ground_vehicle_spawns:
			_log_ground_vehicle_spawn(team_id, vehicle_scene, i, base_pos, spawn_pos, vehicle, carrier_node)

		# Stagger starting waypoint so vehicles don't all drive to the same point at once
		if vehicle.has_method("set_patrol_waypoints"):
			var staggered := patrol_positions.duplicate()
			staggered = staggered.slice(i % staggered.size()) + staggered.slice(0, i % staggered.size())
			vehicle.set_patrol_waypoints(staggered)
		if vehicle.has_method("assign_platoon"):
			vehicle.assign_platoon(platoon)

func _find_enemy_vehicle_staging_position(carrier_pos: Vector3, carrier_node: CollisionObject3D = null) -> Vector3:
	var carrier_ground_y: float = _sample_ground_height(carrier_pos)
	var best_pos: Vector3 = Vector3(carrier_pos.x + 5000.0, carrier_ground_y + 2.0, carrier_pos.z)
	var best_score: float = INF
	for _attempt in range(32):
		var angle: float = randf() * TAU
		var dist: float = randf_range(4500.0, 5500.0)
		var candidate := Vector3(
			carrier_pos.x + cos(angle) * dist,
			0.0,
			carrier_pos.z + sin(angle) * dist
		)
		var candidate_eval := _evaluate_ground_spawn_candidate(candidate, carrier_node, carrier_pos, true)
		if not candidate_eval["valid"]:
			continue
		var candidate_pos: Vector3 = candidate_eval["position"]
		var height_delta: float = absf(candidate_pos.y - (carrier_ground_y + 2.0))
		var flatness: float = float(candidate_eval["height_delta"])
		var route_length: float = float(candidate_eval.get("route_length", 0.0))
		var score: float = height_delta + flatness * 10.0 + route_length * 0.002
		if score < best_score:
			best_score = score
			best_pos = candidate_pos
		if height_delta <= 35.0 and flatness <= ground_vehicle_spawn_max_height_delta_m:
			break
	return best_pos

func _find_enemy_platoon_staging_position(carrier_pos: Vector3, carrier_node: CollisionObject3D = null) -> Vector3:
	var min_range_m: float = minf(enemy_platoon_spawn_min_range_m, enemy_platoon_spawn_max_range_m)
	var max_range_m: float = maxf(enemy_platoon_spawn_min_range_m, enemy_platoon_spawn_max_range_m)
	var valid_positions: Array[Vector3] = []
	var attempts: int = maxi(enemy_platoon_spawn_attempts, 1)
	for _attempt in range(attempts):
		var angle: float = randf() * TAU
		var dist: float = randf_range(min_range_m, max_range_m)
		var candidate := carrier_pos + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var candidate_eval := _evaluate_ground_spawn_candidate(candidate, carrier_node, carrier_pos, true, true, enemy_platoon_spawn_map_margin_m)
		if not bool(candidate_eval["valid"]):
			continue
		valid_positions.append(candidate_eval["position"])
		if valid_positions.size() >= 8:
			break
	if not valid_positions.is_empty():
		return valid_positions[randi() % valid_positions.size()]

	var sweep_angle_offset: float = randf() * TAU
	var sweep_distances: Array[float] = [max_range_m, lerpf(min_range_m, max_range_m, 0.5), min_range_m]
	for dir_idx in range(24):
		var angle: float = sweep_angle_offset + TAU * float(dir_idx) / 24.0
		for dist in sweep_distances:
			var candidate := carrier_pos + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			var candidate_eval := _evaluate_ground_spawn_candidate(candidate, carrier_node, carrier_pos, true, true, enemy_platoon_spawn_map_margin_m)
			if bool(candidate_eval["valid"]):
				return candidate_eval["position"]

	return _find_enemy_vehicle_staging_position(carrier_pos, carrier_node)

func _find_friendly_vehicle_staging_position(carrier_pos: Vector3, carrier_node: CollisionObject3D = null) -> Vector3:
	var carrier_ground_y: float = _sample_ground_height(carrier_pos, carrier_node)
	var best_pos: Vector3 = Vector3(carrier_pos.x + 220.0, carrier_ground_y + 2.0, carrier_pos.z)
	var best_score: float = INF
	for _attempt in range(28):
		var angle: float = randf() * TAU
		var dist: float = randf_range(150.0, 300.0)
		var candidate := Vector3(
			carrier_pos.x + cos(angle) * dist,
			0.0,
			carrier_pos.z + sin(angle) * dist
		)
		var candidate_eval := _evaluate_ground_spawn_candidate(candidate, carrier_node, carrier_pos, true)
		if not candidate_eval["valid"]:
			continue
		var candidate_pos: Vector3 = candidate_eval["position"]
		var height_delta: float = absf(candidate_pos.y - (carrier_ground_y + 2.0))
		var flatness: float = float(candidate_eval["height_delta"])
		var route_length: float = float(candidate_eval.get("route_length", 0.0))
		var score: float = height_delta + flatness * 10.0 + route_length * 0.002
		if score < best_score:
			best_score = score
			best_pos = candidate_pos
		if height_delta <= 12.0 and flatness <= ground_vehicle_spawn_max_height_delta_m:
			break
	return best_pos

func _find_nearby_valid_ground_spawn(desired_pos: Vector3, exclude_body: CollisionObject3D = null, carrier_pos: Vector3 = Vector3.ZERO, require_path_to_carrier: bool = false, require_map_bounds: bool = false, map_margin_m: float = 0.0) -> Vector3:
	var best_eval := _evaluate_ground_spawn_candidate(desired_pos, exclude_body, carrier_pos, require_path_to_carrier, require_map_bounds, map_margin_m)
	if bool(best_eval["valid"]):
		return best_eval["position"]
	var best_pos: Vector3 = Vector3(desired_pos.x, _sample_ground_height(desired_pos, exclude_body) + 2.0, desired_pos.z)
	var best_score: float = INF
	for attempt in range(maxi(ground_vehicle_spawn_search_attempts, 1)):
		var angle: float = randf() * TAU
		var dist_t: float = 1.0 if ground_vehicle_spawn_search_attempts <= 1 else float(attempt + 1) / float(ground_vehicle_spawn_search_attempts)
		var dist: float = dist_t * ground_vehicle_spawn_search_radius_m
		var candidate := Vector3(
			desired_pos.x + cos(angle) * dist,
			desired_pos.y,
			desired_pos.z + sin(angle) * dist
		)
		var eval := _evaluate_ground_spawn_candidate(candidate, exclude_body, carrier_pos, require_path_to_carrier, require_map_bounds, map_margin_m)
		if not bool(eval["valid"]):
			continue
		var candidate_pos: Vector3 = eval["position"]
		var route_length: float = float(eval.get("route_length", 0.0))
		var score: float = candidate_pos.distance_to(desired_pos) + float(eval["height_delta"]) * 12.0 + route_length * 0.001
		if score < best_score:
			best_score = score
			best_pos = candidate_pos
	return best_pos

func _evaluate_ground_spawn_candidate(world_pos: Vector3, exclude_body: CollisionObject3D = null, carrier_pos: Vector3 = Vector3.ZERO, require_path_to_carrier: bool = false, require_map_bounds: bool = false, map_margin_m: float = 0.0) -> Dictionary:
	if require_map_bounds and not _is_world_in_tactical_map_bounds(world_pos, map_margin_m):
		return {"valid": false, "position": world_pos, "height_delta": INF, "route_length": INF}
	var center_y: float = _sample_ground_height(world_pos, exclude_body)
	if not is_finite(center_y):
		return {"valid": false, "position": world_pos, "height_delta": INF, "route_length": INF}
	var center_pos := Vector3(world_pos.x, center_y + 2.0, world_pos.z)
	var max_delta: float = 0.0
	var sample_radius: float = maxf(ground_vehicle_spawn_probe_radius_m, 2.0)
	for sample_idx in range(8):
		var angle: float = TAU * float(sample_idx) / 8.0
		var sample_pos := Vector3(
			world_pos.x + cos(angle) * sample_radius,
			world_pos.y,
			world_pos.z + sin(angle) * sample_radius
		)
		if require_map_bounds and not _is_world_in_tactical_map_bounds(sample_pos, map_margin_m):
			return {"valid": false, "position": center_pos, "height_delta": INF, "route_length": INF}
		var sample_y: float = _sample_ground_height(sample_pos, exclude_body)
		if not is_finite(sample_y):
			return {"valid": false, "position": center_pos, "height_delta": INF, "route_length": INF}
		max_delta = maxf(max_delta, absf(sample_y - center_y))
		if max_delta > ground_vehicle_spawn_max_height_delta_m:
			return {"valid": false, "position": center_pos, "height_delta": max_delta, "route_length": INF}
	if NavGraph.is_ready():
		if not NavGraph.can_anchor(center_pos, ground_vehicle_spawn_path_clearance_m, ground_vehicle_spawn_anchor_distance_m):
			return {"valid": false, "position": center_pos, "height_delta": max_delta, "route_length": INF}
		if require_path_to_carrier:
			var carrier_ground_y: float = _sample_ground_height(carrier_pos, exclude_body)
			if not is_finite(carrier_ground_y):
				return {"valid": false, "position": center_pos, "height_delta": max_delta, "route_length": INF}
			var carrier_ground_pos := Vector3(carrier_pos.x, carrier_ground_y + 2.0, carrier_pos.z)
			if not NavGraph.can_anchor(carrier_ground_pos, ground_vehicle_spawn_path_clearance_m, ground_vehicle_spawn_anchor_distance_m):
				return {"valid": false, "position": center_pos, "height_delta": max_delta, "route_length": INF}
			return {"valid": true, "position": center_pos, "height_delta": max_delta, "route_length": Vector2(center_pos.x - carrier_ground_pos.x, center_pos.z - carrier_ground_pos.z).length()}
	return {"valid": true, "position": center_pos, "height_delta": max_delta, "route_length": 0.0}

func _is_world_in_tactical_map_bounds(world_pos: Vector3, margin_m: float = 0.0) -> bool:
	if not TerrainNavGrid.is_ready():
		return false
	var span_x: float = float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var span_z: float = float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	if span_x <= 1.0 or span_z <= 1.0:
		return false
	var min_x: float = TerrainNavGrid._origin_x + margin_m
	var max_x: float = TerrainNavGrid._origin_x + span_x - margin_m
	var min_z: float = TerrainNavGrid._origin_z + margin_m
	var max_z: float = TerrainNavGrid._origin_z + span_z - margin_m
	return world_pos.x >= min_x and world_pos.x <= max_x and world_pos.z >= min_z and world_pos.z <= max_z

func _sample_ground_height(world_pos: Vector3, exclude_body: CollisionObject3D = null) -> float:
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(world_pos + Vector3.UP * 2000.0, world_pos - Vector3.UP * 300.0)
	if exclude_body and is_instance_valid(exclude_body):
		params.exclude = [exclude_body.get_rid()]
	var hit := space_state.intersect_ray(params)
	if hit:
		return hit.position.y
	return world_pos.y

func _path_length(path: Array[Vector3]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += Vector2(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z).length()
	return total

func _log_ground_vehicle_spawn(team_id: int, scene: PackedScene, index: int, base_pos: Vector3, spawn_pos: Vector3, vehicle: Node3D, carrier_node: CollisionObject3D = null) -> void:
	var terrain_y: float = _sample_ground_height(spawn_pos, carrier_node)
	print("[GroundSpawn] team=%d idx=%d scene=%s base=%s spawn=%s terrain_y=%.2f vehicle=%s" % [
		team_id,
		index,
		scene.resource_path,
		str(base_pos),
		str(spawn_pos),
		terrain_y,
		str(vehicle.global_position)
	])
	await get_tree().process_frame
	if is_instance_valid(vehicle):
		var settled_terrain_y: float = _sample_ground_height(vehicle.global_position, carrier_node)
		print("[GroundSpawn] team=%d idx=%d after_frame vehicle=%s terrain_y=%.2f delta_y=%.2f" % [
			team_id,
			index,
			str(vehicle.global_position),
			settled_terrain_y,
			vehicle.global_position.y - settled_terrain_y
		])

func _spawn_enemy_strike_flight() -> void:
	if not _enemy_aircraft_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() + 4 > max_ai_planes:
		print("[EnemyAircraftSpawner] R: max AI planes would be exceeded")
		return

	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	var carrier_pos: Vector3 = _get_carrier_position()
	var spawn_angle: float = randf() * TAU
	var spawn_dir := Vector3(cos(spawn_angle), 0.0, sin(spawn_angle)).normalized()
	if spawn_dir.length() < 0.01:
		spawn_dir = Vector3.FORWARD
	var spawn_center := carrier_pos + spawn_dir * strike_flight_range_from_carrier_m
	spawn_center.y = carrier_pos.y + strike_flight_altitude_m
	var formation_right := Vector3(-spawn_dir.z, 0.0, spawn_dir.x)
	var offsets := [-180.0, -60.0, 60.0, 180.0]
	var spawned: Array[RigidBody3D] = []

	for i in range(offsets.size()):
		var spawn_pos: Vector3 = spawn_center + formation_right * float(offsets[i])
		spawn_pos.y = spawn_center.y
		var aircraft := await _spawn_ai_fighter(
			_enemy_aircraft_scene,
			"EnemyStrike_%d" % (i + 1),
			2,
			"enemies",
			spawn_pos,
			-spawn_dir,
			maxf(spawn_speed, 85.0)
		)
		if is_instance_valid(aircraft):
			spawned.append(aircraft)

	await get_tree().create_timer(0.5).timeout
	for aircraft in spawned:
		_configure_enemy_strike_pilot(aircraft, carrier)

func _spawn_friendly_debug_flight() -> void:
	if not _aircraft_5_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() + 3 > max_ai_planes:
		print("[EnemyAircraftSpawner] F: max AI planes would be exceeded")
		return

	var carrier_pos: Vector3 = _get_carrier_position()
	var forward_flat: Vector3 = _get_carrier_forward()
	forward_flat.y = 0.0
	forward_flat = forward_flat.normalized()
	if forward_flat.length() < 0.01:
		forward_flat = Vector3.FORWARD
	var formation_right := Vector3(-forward_flat.z, 0.0, forward_flat.x).normalized()
	if formation_right.length() < 0.01:
		formation_right = Vector3.RIGHT
	var spawn_center := carrier_pos + Vector3(0.0, friendly_debug_flight_altitude_m, 0.0)
	var orbit_waypoints: Array[Vector3] = _build_carrier_orbit_waypoints(carrier_pos, cap_orbit_radius_m, friendly_debug_flight_altitude_m, 9)
	var spawned: Array[RigidBody3D] = []

	for i in range(3):
		var slot_offset: float = (float(i) - 1.0) * debug_air_spawn_spacing_m
		var spawn_pos := spawn_center + formation_right * slot_offset
		spawn_pos.y = spawn_center.y
		var aircraft := await _spawn_ai_fighter(
			_aircraft_5_scene,
			"FriendlySpawn_%d" % (i + 1),
			1,
			"friendlies",
			spawn_pos,
			forward_flat,
			maxf(spawn_speed, 80.0)
		)
		if is_instance_valid(aircraft):
			spawned.append(aircraft)

	_assign_friendly_aircraft_to_shared_flight(spawned)

	await get_tree().create_timer(0.5).timeout
	for i in range(spawned.size()):
		_configure_friendly_cap_pilot(spawned[i], orbit_waypoints, i, friendly_debug_flight_altitude_m)

func _spawn_enemy_debug_flight() -> void:
	if not _aircraft_3_scene:
		return
	var aircraft_4_scene: PackedScene = _aircraft_4_scene if _aircraft_4_scene else _aircraft_3_scene
	_prune_active_ai_planes()
	if _active_ai_planes.size() + 4 > max_ai_planes:
		print("[EnemyAircraftSpawner] R: max AI planes would be exceeded")
		return

	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	var carrier_pos: Vector3 = _get_carrier_position()
	var spawn_dir := _get_random_valid_air_spawn_direction(carrier_pos, enemy_debug_flight_range_from_carrier_m, debug_air_spawn_map_margin_m)
	var spawn_center := carrier_pos + spawn_dir * enemy_debug_flight_range_from_carrier_m
	spawn_center.y = carrier_pos.y + strike_flight_altitude_m
	var formation_right := Vector3(-spawn_dir.z, 0.0, spawn_dir.x).normalized()
	if formation_right.length() < 0.01:
		formation_right = Vector3.RIGHT
	var spawned: Array[RigidBody3D] = []
	var scenes: Array[PackedScene] = [_aircraft_3_scene, _aircraft_3_scene, aircraft_4_scene, aircraft_4_scene]

	for i in range(scenes.size()):
		var slot_offset: float = (float(i) - 1.5) * debug_air_spawn_spacing_m
		var spawn_pos := spawn_center + formation_right * slot_offset
		spawn_pos.y = spawn_center.y
		var aircraft := await _spawn_ai_fighter(
			scenes[i],
			"EnemyStrike_%d" % (i + 1),
			2,
			"enemies",
			spawn_pos,
			-spawn_dir,
			maxf(spawn_speed, 85.0)
		)
		if is_instance_valid(aircraft):
			spawned.append(aircraft)

	await get_tree().create_timer(0.5).timeout
	for aircraft in spawned:
		_configure_enemy_strike_pilot(aircraft, carrier, false)

func _assign_friendly_aircraft_to_shared_flight(aircraft_list: Array[RigidBody3D]) -> void:
	if aircraft_list.is_empty():
		return
	if AirOpsManager == null or not is_instance_valid(AirOpsManager):
		return

	var flight := _pick_shared_friendly_flight()
	if flight == null or not is_instance_valid(flight):
		return

	for aircraft in aircraft_list:
		if not is_instance_valid(aircraft):
			continue
		AirOpsManager.reassign(aircraft, flight.flight_name)

	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	flight.set_cap(carrier, friendly_debug_flight_altitude_m)
	print("[EnemyAircraftSpawner] F: assigned %d aircraft to %s flight" % [aircraft_list.size(), flight.flight_name])

func _pick_shared_friendly_flight() -> Flight:
	if AirOpsManager == null or not is_instance_valid(AirOpsManager):
		return null

	var best_cap_flight: Flight = null
	var best_cap_strength: int = 1 << 30
	var best_any_flight: Flight = null
	var best_any_strength: int = 1 << 30

	for flight in AirOpsManager.flights:
		if flight == null or not is_instance_valid(flight):
			continue
		var member_count: int = flight.strength()
		if member_count == 0:
			return flight
		if flight.mission == Flight.Mission.CAP and not flight.is_engaged() and member_count < best_cap_strength:
			best_cap_flight = flight
			best_cap_strength = member_count
		if flight.mission != Flight.Mission.RTB and member_count < best_any_strength:
			best_any_flight = flight
			best_any_strength = member_count

	if best_cap_flight != null:
		return best_cap_flight
	return best_any_flight

func _spawn_friendly_aircraft_3() -> void:
	if not _aircraft_3_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() >= max_ai_planes:
		print("[EnemyAircraftSpawner] 3: max AI planes reached")
		return

	var carrier_pos: Vector3 = _get_carrier_position()
	var orbit_waypoints: Array[Vector3] = _build_carrier_orbit_waypoints(carrier_pos, cap_orbit_radius_m, cap_flight_altitude_m, 9)

	var angle: float = randf() * TAU
	var radial: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
	var spawn_pos: Vector3 = carrier_pos + radial * cap_orbit_radius_m
	spawn_pos.y = carrier_pos.y + cap_flight_altitude_m
	var tangent: Vector3 = Vector3(-radial.z, 0.0, radial.x).normalized()

	var aircraft := await _spawn_ai_fighter(
		_aircraft_3_scene,
		"FriendlyAC3_%d" % (_active_ai_planes.size() + 1),
		1,
		"friendlies",
		spawn_pos,
		tangent,
		maxf(spawn_speed, 80.0)
	)
	if is_instance_valid(aircraft):
		await get_tree().create_timer(0.5).timeout
		_configure_friendly_cap_pilot(aircraft, orbit_waypoints, 0)

func _spawn_friendly_cap_flight() -> void:
	if not _aircraft_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() + 3 > max_ai_planes:
		print("[EnemyAircraftSpawner] G: max AI planes would be exceeded")
		return

	var carrier_pos: Vector3 = _get_carrier_position()
	var orbit_waypoints: Array[Vector3] = _build_carrier_orbit_waypoints(carrier_pos, cap_orbit_radius_m, cap_flight_altitude_m, 9)
	var spawned: Array[RigidBody3D] = []

	for i in range(3):
		var angle: float = TAU * float(i) / 3.0
		var radial: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var spawn_pos: Vector3 = carrier_pos + radial * cap_orbit_radius_m
		spawn_pos.y = carrier_pos.y + cap_flight_altitude_m
		var tangent: Vector3 = Vector3(-radial.z, 0.0, radial.x).normalized()
		var aircraft := await _spawn_ai_fighter(
			_aircraft_scene,
			"FriendlyCAP_%d" % (i + 1),
			1,
			"friendlies",
			spawn_pos,
			tangent,
			maxf(spawn_speed, 80.0)
		)
		if is_instance_valid(aircraft):
			spawned.append(aircraft)

	await get_tree().create_timer(0.5).timeout
	for i in range(spawned.size()):
		_configure_friendly_cap_pilot(spawned[i], orbit_waypoints, i)

func _spawn_friendly_aircraft_4() -> void:
	if not _aircraft_4_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() >= max_ai_planes:
		print("[EnemyAircraftSpawner] 4: max AI planes reached")
		return

	var carrier_pos: Vector3 = _get_carrier_position()
	var orbit_waypoints: Array[Vector3] = _build_carrier_orbit_waypoints(carrier_pos, cap_orbit_radius_m, cap_flight_altitude_m, 9)
	var forward_flat: Vector3 = _get_carrier_forward()
	forward_flat.y = 0.0
	forward_flat = forward_flat.normalized()
	if forward_flat.length() < 0.01:
		forward_flat = Vector3.FORWARD

	var spawn_pos: Vector3 = carrier_pos + Vector3(0.0, friendly_debug_flight_altitude_m, 0.0)
	var aircraft := await _spawn_ai_fighter(
		_aircraft_4_scene,
		"FriendlyAC4_%d" % (_active_ai_planes.size() + 1),
		1,
		"friendlies",
		spawn_pos,
		forward_flat,
		maxf(spawn_speed, 80.0)
	)
	if is_instance_valid(aircraft):
		await get_tree().create_timer(0.5).timeout
		_configure_friendly_cap_pilot(aircraft, orbit_waypoints, 0)

func _spawn_friendly_aircraft_6() -> void:
	if not _aircraft_6_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() >= max_ai_planes:
		print("[EnemyAircraftSpawner] 6: max AI planes reached")
		return

	var carrier_pos: Vector3 = _get_carrier_position()
	var orbit_waypoints: Array[Vector3] = _build_carrier_orbit_waypoints(carrier_pos, cap_orbit_radius_m, cap_flight_altitude_m, 9)
	var forward_flat: Vector3 = _get_carrier_forward()
	forward_flat.y = 0.0
	forward_flat = forward_flat.normalized()
	if forward_flat.length() < 0.01:
		forward_flat = Vector3.FORWARD

	var spawn_pos: Vector3 = carrier_pos + Vector3(0.0, 200.0, 0.0)
	var aircraft := await _spawn_ai_fighter(
		_aircraft_6_scene,
		"FriendlyAC6_%d" % (_active_ai_planes.size() + 1),
		1,
		"friendlies",
		spawn_pos,
		forward_flat,
		60.0
	)
	if is_instance_valid(aircraft):
		await get_tree().create_timer(0.5).timeout
		_configure_friendly_cap_pilot(aircraft, orbit_waypoints, 0)

func _is_aircraft_3(aircraft: Node) -> bool:
	if aircraft == null:
		return false
	if aircraft.has_meta("source_scene_path") and String(aircraft.get_meta("source_scene_path")) == "res://Aircraft/Aircraft_3.tscn":
		return true
	return String(aircraft.scene_file_path) == "res://Aircraft/Aircraft_3.tscn"

func _is_strike_or_missile_weapon(weapon_name: String) -> bool:
	return weapon_name == "Bomb" or weapon_name == "Rocket Pod" or "Missile" in weapon_name

func _strip_enemy_aircraft_3_stores(aircraft: Node3D) -> void:
	if not _is_aircraft_3(aircraft):
		return
	for hp in aircraft.find_children("*", "Hardpoint", true, false):
		var hardpoint := hp as Hardpoint
		if hardpoint == null or hardpoint.weapon_instance == null:
			continue
		var weapon_name := String(hardpoint.weapon_instance.weapon_name)
		if not _is_strike_or_missile_weapon(weapon_name):
			continue
		hardpoint.weapon_instance.queue_free()
		hardpoint.weapon_instance = null
		hardpoint.mounted_weapon = null

	var cw := aircraft.find_child("ControlWeapons", true, false) as ControlWeapons
	if cw:
		cw.find_hardpoints()
		cw.categorize_weapons()
		var gun_idx := cw.weapon_types.find("Autocannon")
		if gun_idx == -1:
			gun_idx = 0
		if cw.weapon_types.size() > 0:
			cw.selected_weapon_type_index = gun_idx
			cw.selected_weapon_type = cw.weapon_types[gun_idx]

func _configure_enemy_strike_pilot(aircraft: RigidBody3D, carrier: Node3D, prefer_air_combat: bool = false) -> void:
	if not is_instance_valid(aircraft):
		return
	_strip_enemy_aircraft_3_stores(aircraft)
	var is_clean_aircraft_3 := _is_aircraft_3(aircraft)
	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()
	var ai_pilot = aircraft.find_child("AIPilot", true, false) as AIPilot
	if not ai_pilot:
		print("[EnemyAircraftSpawner] R: missing AIPilot on strike aircraft")
		return
	# Temporary high-skill baseline while tuning bomb accuracy. Once the ceiling feels
	# right, enemy strike skill can be lowered without weakening friendly pilots.
	ai_pilot.skill = AIPilot.AIPilotSkill.ELITE
	ai_pilot.apply_skill_preset()
	ai_pilot.carrier_position = _get_carrier_position()
	ai_pilot.target_altitude = strike_flight_altitude_m
	ai_pilot.patrol_altitude_m = strike_flight_altitude_m
	ai_pilot.target_speed = maxf(spawn_speed, 90.0)
	ai_pilot.dogfight_enabled = prefer_air_combat or is_clean_aircraft_3
	ai_pilot.dogfight_proximity_override_m = 0.0  # never break off a carrier attack run
	ai_pilot.ground_attack_enabled = not prefer_air_combat and not is_clean_aircraft_3
	# Strike aircraft press the attack until destroyed — no RTB for damage or fuel
	ai_pilot.rtb_health_threshold = 0.0
	ai_pilot.rtb_fuel_threshold = 0.0
	ai_pilot.waypoints.clear()
	if prefer_air_combat or is_clean_aircraft_3:
		ai_pilot.change_state(AIPilot.State.SEARCH)
	elif carrier and is_instance_valid(carrier):
		ai_pilot.set_target(carrier)
	else:
		ai_pilot.change_state(AIPilot.State.SEARCH)

func _configure_friendly_cap_pilot(aircraft: RigidBody3D, orbit_waypoints: Array[Vector3], orbit_offset: int, altitude_override_m: float = -1.0) -> void:
	if not is_instance_valid(aircraft):
		return
	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()
	var ai_pilot = aircraft.find_child("AIPilot", true, false) as AIPilot
	if not ai_pilot:
		print("[EnemyAircraftSpawner] G: missing AIPilot on CAP aircraft")
		return
	var patrol_altitude_m: float = altitude_override_m if altitude_override_m > 0.0 else cap_flight_altitude_m
	ai_pilot.carrier_position = _get_carrier_position()
	ai_pilot.target_altitude = patrol_altitude_m
	ai_pilot.patrol_altitude_m = patrol_altitude_m
	ai_pilot.target_speed = maxf(spawn_speed, 80.0)
	ai_pilot.ground_attack_enabled = false
	ai_pilot.dogfight_enabled = true
	ai_pilot.set_waypoints(orbit_waypoints.duplicate())
	if not orbit_waypoints.is_empty():
		ai_pilot.current_waypoint_index = int((orbit_offset * orbit_waypoints.size()) / 3)
	ai_pilot.change_state(AIPilot.State.SEARCH)

func _build_carrier_orbit_waypoints(center: Vector3, radius_m: float, altitude_m: float, point_count: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var clamped_count: int = max(point_count, 3)
	for i in range(clamped_count):
		var angle: float = TAU * float(i) / float(clamped_count)
		points.append(center + Vector3(cos(angle) * radius_m, altitude_m, sin(angle) * radius_m))
	return points

func _get_random_valid_air_spawn_direction(origin: Vector3, range_m: float, map_margin_m: float = 0.0) -> Vector3:
	for _attempt in range(maxi(debug_air_spawn_direction_attempts, 1)):
		var spawn_angle: float = randf() * TAU
		var spawn_dir := Vector3(cos(spawn_angle), 0.0, sin(spawn_angle)).normalized()
		if spawn_dir.length() < 0.01:
			continue
		if not TerrainNavGrid.is_ready():
			return spawn_dir
		var spawn_world := origin + spawn_dir * range_m
		if _is_world_in_tactical_map_bounds(spawn_world, map_margin_m):
			return spawn_dir

	if TerrainNavGrid.is_ready():
		var span_x: float = float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
		var span_z: float = float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
		var map_center := Vector3(
			TerrainNavGrid._origin_x + span_x * 0.5,
			origin.y,
			TerrainNavGrid._origin_z + span_z * 0.5
		)
		var center_dir := map_center - origin
		center_dir.y = 0.0
		center_dir = center_dir.normalized()
		if center_dir.length() >= 0.01:
			return center_dir

	var fallback_dir: Vector3 = _get_carrier_forward()
	fallback_dir.y = 0.0
	fallback_dir = fallback_dir.normalized()
	if fallback_dir.length() < 0.01:
		fallback_dir = Vector3.FORWARD
	return fallback_dir

func _spawn_enemy():
	if not _aircraft_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() >= max_ai_planes:
		print("[EnemyAircraftSpawner] Max AI planes reached: ", max_ai_planes)
		return

	var aircraft = _aircraft_scene.instantiate() as RigidBody3D
	if not aircraft:
		push_error("[EnemyAircraftSpawner] Failed to instantiate enemy aircraft")
		return

	aircraft.name = "FriendlyAI"
	get_tree().current_scene.add_child(aircraft)

	var spawn_pos = _get_carrier_position()
	spawn_pos.y += spawn_altitude
	aircraft.global_position = spawn_pos

	var forward_dir = _get_carrier_forward()
	var yaw = atan2(forward_dir.x, forward_dir.z)
	aircraft.global_rotation = Vector3(0, yaw, 0)
	aircraft.linear_velocity = forward_dir * spawn_speed

	# aircraft._ready() awaits process_frame before add_to_group("aircraft"), so we must
	# remove after it completes (next frame)
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frame to ensure aircraft._ready() has finished
	aircraft.remove_from_group("aircraft")
	aircraft.add_to_group("friendlies")
	aircraft.add_to_group("ai_aircraft")

	_apply_ai_aircraft_spawn_budget(aircraft)

	# AI planes spawn airborne - stow gear immediately
	var control_gear = aircraft.find_child("ControlLandingGear", true, false)
	if control_gear and control_gear.has_method("send_to_landing_gears"):
		control_gear.send_to_landing_gears("stow")
		control_gear.send_to_tailhooks("stow")
		if control_gear.has_method("send_to_tailhook_simple"):
			control_gear.send_to_tailhook_simple(false)
		if "gear_down_state" in control_gear:
			control_gear.gear_down_state = false
		if control_gear.has_method("_set_collider_disabled"):
			control_gear._set_collider_disabled(true)

	if aircraft.has_signal("crashed"):
		aircraft.crashed.connect(_on_enemy_crashed.bind(aircraft), CONNECT_ONE_SHOT)
	if aircraft.has_signal("destroyed"):
		aircraft.destroyed.connect(_on_enemy_destroyed.bind(aircraft), CONNECT_ONE_SHOT)

	_active_ai_planes.append(aircraft)

	await get_tree().create_timer(0.5).timeout
	_configure_ai_patrol(aircraft)

func _spawn_ai_fighter(scene: PackedScene, display_name: String, team_id: int, extra_group: String, spawn_pos: Vector3, forward_dir: Vector3, initial_speed: float) -> RigidBody3D:
	if not scene:
		return null
	var aircraft := scene.instantiate() as RigidBody3D
	if not aircraft:
		return null
	aircraft.set_meta("source_scene_path", scene.resource_path)
	aircraft.name = display_name
	if "team" in aircraft:
		aircraft.team = team_id
	get_tree().current_scene.add_child(aircraft)

	aircraft.global_position = spawn_pos
	var flat_fwd := Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
	if flat_fwd.length() < 0.01:
		flat_fwd = Vector3.FORWARD
	var yaw := atan2(flat_fwd.x, flat_fwd.z)
	aircraft.global_rotation = Vector3(0.0, yaw, 0.0)
	aircraft.linear_velocity = flat_fwd * initial_speed

	# Wait for aircraft._ready() to finish adding default groups.
	await get_tree().process_frame
	await get_tree().process_frame
	aircraft.remove_from_group("aircraft")
	aircraft.add_to_group("ai_aircraft")
	if not extra_group.is_empty():
		aircraft.add_to_group(extra_group)
	if team_id == 2:
		_strip_enemy_aircraft_3_stores(aircraft)

	_apply_ai_aircraft_spawn_budget(aircraft)

	# Spawn airborne with gear up.
	var control_gear = aircraft.find_child("ControlLandingGear", true, false)
	if control_gear and control_gear.has_method("send_to_landing_gears"):
		control_gear.send_to_landing_gears("stow")
		control_gear.send_to_tailhooks("stow")
		if control_gear.has_method("send_to_tailhook_simple"):
			control_gear.send_to_tailhook_simple(false)
		if "gear_down_state" in control_gear:
			control_gear.gear_down_state = false
		if control_gear.has_method("_set_collider_disabled"):
			control_gear._set_collider_disabled(true)

	if aircraft.has_signal("crashed"):
		aircraft.crashed.connect(_on_enemy_crashed.bind(aircraft), CONNECT_ONE_SHOT)
	if aircraft.has_signal("destroyed"):
		aircraft.destroyed.connect(_on_enemy_destroyed.bind(aircraft), CONNECT_ONE_SHOT)
	_active_ai_planes.append(aircraft)
	return aircraft

func _apply_ai_aircraft_spawn_budget(aircraft: Node) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	aircraft.set_meta("ai_spawn_budget_applied", true)

	for node_name_variant in [
		"CameraController",
		"HeadsUpDisplay",
		"InstrumentPanel",
		"ControlTargeting",
		"AudioManager3D",
		"CockpitCanopyVisibility",
		"CockpitPilot",
		"CameraCockpit",
		"CameraChase",
		"CameraCinematic",
		"CameraTarget",
	]:
		var node_name: String = str(node_name_variant)
		var node: Node = aircraft.find_child(node_name, true, false)
		if node == null or not is_instance_valid(node):
			continue
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_input(false)
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		elif node is Node3D:
			(node as Node3D).visible = false
		_stop_audio_players_recursive(node)

	for child_variant in aircraft.find_children("*", "AudioStreamPlayer", true, false):
		var audio_node_2d: Node = child_variant as Node
		_stop_audio_player(audio_node_2d)
	for child_variant in aircraft.find_children("*", "AudioStreamPlayer3D", true, false):
		var audio_node_3d: Node = child_variant as Node
		_stop_audio_player(audio_node_3d)

	for child_variant in aircraft.find_children("*", "", true, false):
		var node: Node = child_variant as Node
		if node == null:
			continue
		if node.has_method("set_aircraft_visual_budget_enabled"):
			node.call("set_aircraft_visual_budget_enabled", false)
		if node.has_method("set_aircraft_audio_budget_enabled"):
			node.call("set_aircraft_audio_budget_enabled", false)

func _stop_audio_players_recursive(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_stop_audio_player(node)
	for child: Node in node.get_children():
		_stop_audio_players_recursive(child)

func _stop_audio_player(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is AudioStreamPlayer:
		var audio_2d: AudioStreamPlayer = node as AudioStreamPlayer
		if audio_2d.playing:
			audio_2d.stop()
	elif node is AudioStreamPlayer3D:
		var audio_3d: AudioStreamPlayer3D = node as AudioStreamPlayer3D
		if audio_3d.playing:
			audio_3d.stop()

func _spawn_dogfight_duel() -> void:
	"""D key: spawn one friendly + one enemy in a head-on dogfight setup."""
	if not _aircraft_scene or not _enemy_aircraft_scene:
		print("[EnemyAircraftSpawner] D: missing aircraft scenes")
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() + 2 > max_ai_planes:
		print("[EnemyAircraftSpawner] D: max AI planes would be exceeded")
		return

	var carrier_pos: Vector3 = _get_carrier_position()
	var carrier_fwd: Vector3 = _get_carrier_forward()
	var forward_flat: Vector3 = Vector3(carrier_fwd.x, 0.0, carrier_fwd.z).normalized()
	if forward_flat.length() < 0.01:
		forward_flat = Vector3.FORWARD
	var altitude_y: float = carrier_pos.y + duel_altitude_m

	var friendly_pos: Vector3 = carrier_pos + forward_flat * duel_range_from_carrier_m
	friendly_pos.y = altitude_y
	var enemy_pos: Vector3 = carrier_pos - forward_flat * duel_range_from_carrier_m
	enemy_pos.y = altitude_y

	var friendly: RigidBody3D = await _spawn_ai_fighter(_aircraft_scene, "FriendlyDuelAI", 1, "friendlies", friendly_pos, -forward_flat, spawn_speed)
	var enemy: RigidBody3D = await _spawn_ai_fighter(_enemy_aircraft_scene, "EnemyDuelAI", 2, "enemies", enemy_pos, forward_flat, spawn_speed)
	if not is_instance_valid(friendly) or not is_instance_valid(enemy):
		print("[EnemyAircraftSpawner] D: failed to spawn duel aircraft")
		return

	await get_tree().create_timer(0.5).timeout
	var friendly_toggle = friendly.find_child("AIToggle", true, false)
	if friendly_toggle and friendly_toggle.has_method("enable_ai"):
		friendly_toggle.enable_ai()
	var enemy_toggle = enemy.find_child("AIToggle", true, false)
	if enemy_toggle and enemy_toggle.has_method("enable_ai"):
		enemy_toggle.enable_ai()

	var friendly_pilot = friendly.find_child("AIPilot", true, false)
	var enemy_pilot = enemy.find_child("AIPilot", true, false)
	if friendly_pilot and enemy_pilot and friendly_pilot is AIPilot and enemy_pilot is AIPilot:
		enemy_pilot.skill = AIPilot.AIPilotSkill.ROOKIE
		enemy_pilot.apply_skill_preset()
		friendly_pilot.dogfight_enabled = true
		enemy_pilot.dogfight_enabled = true
		friendly_pilot.ground_attack_enabled = false
		enemy_pilot.ground_attack_enabled = false
		friendly_pilot.set_target(enemy)
		enemy_pilot.set_target(friendly)
		print("[EnemyAircraftSpawner] D: spawned dogfight duel. Separation=", snapped(friendly.global_position.distance_to(enemy.global_position), 1.0), "m Alt=", snapped(duel_altitude_m, 1.0), "m")
	else:
		print("[EnemyAircraftSpawner] D: missing AIPilot on one or both duel aircraft")

func _configure_ai_patrol(aircraft: RigidBody3D):
	if not is_instance_valid(aircraft):
		return

	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()

	var ai_pilot = aircraft.find_child("AIPilot", true, false) as AIPilot
	if not ai_pilot:
		push_error("[EnemyAircraftSpawner] No AIPilot found on enemy aircraft")
		return
	ai_pilot.skill = AIPilot.AIPilotSkill.ROOKIE
	ai_pilot.apply_skill_preset()

	var center = _get_carrier_position()
	ai_pilot.carrier_position = center
	ai_pilot.target_altitude = 600.0
	ai_pilot.patrol_altitude_m = 600.0
	ai_pilot.target_speed = spawn_speed

	# Build a square patrol: 4 corners, each side = patrol_side_length, centered on carrier
	var half = patrol_side_length / 2.0
	var alt: float = 600.0
	ai_pilot.waypoints.clear()
	ai_pilot.waypoints.append(center + Vector3( half, alt,  half))
	ai_pilot.waypoints.append(center + Vector3(-half, alt,  half))
	ai_pilot.waypoints.append(center + Vector3(-half, alt, -half))
	ai_pilot.waypoints.append(center + Vector3( half, alt, -half))
	# Start at the waypoint most ahead of the aircraft (avoids flying away from first target)
	ai_pilot.current_waypoint_index = _waypoint_most_ahead(aircraft, ai_pilot.waypoints)

	ai_pilot.change_state(AIPilot.State.SEARCH)

func _on_enemy_crashed(_impact_velocity: float, aircraft: RigidBody3D):
	_schedule_respawn(aircraft)

func _on_enemy_destroyed(aircraft: RigidBody3D):
	_schedule_respawn(aircraft)

func _schedule_respawn(aircraft: RigidBody3D):
	if is_instance_valid(aircraft):
		if aircraft.crashed.is_connected(_on_enemy_crashed):
			aircraft.crashed.disconnect(_on_enemy_crashed)
		if aircraft.destroyed.is_connected(_on_enemy_destroyed):
			aircraft.destroyed.disconnect(_on_enemy_destroyed)

	await get_tree().create_timer(respawn_delay).timeout

	if is_instance_valid(aircraft):
		aircraft.queue_free()
	_active_ai_planes.erase(aircraft)
	_prune_active_ai_planes()

	# No automatic respawn — planes are only spawned manually via key press.

func _prune_active_ai_planes():
	_active_ai_planes = _active_ai_planes.filter(func(p): return is_instance_valid(p))


func disable_for_heli_test() -> void:
	_disabled_for_heli_test = true
	for aircraft in _active_ai_planes:
		if is_instance_valid(aircraft):
			aircraft.queue_free()
	_active_ai_planes.clear()
	for group_name in ["enemies", "enemy_bases", "ground_vehicles", "gun_emplacements"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node and is_instance_valid(node) and _is_enemy_test_cleanup_node(node as Node):
				(node as Node).queue_free()
	print("[EnemyAircraftSpawner] disabled for helicopter test")


func _is_enemy_test_cleanup_node(node: Node) -> bool:
	return node.is_in_group("enemies") \
			or node.is_in_group("enemy_bases") \
			or node.is_in_group("team_2")


func _spawn_on_approach():
	"""U key: spawn an AI plane at approach_0 (alt 450 m), pointed at approach_1, already in landing mode."""
	var root := get_tree().current_scene
	var wp0 := root.find_child("approach_0", true, false) as Node3D
	var wp1 := root.find_child("approach_1", true, false) as Node3D
	if not wp0 or not wp1:
		print("[EnemyAircraftSpawner] U: approach_0/1 nodes not found in scene")
		return

	if not _aircraft_scene:
		return
	_prune_active_ai_planes()
	if _active_ai_planes.size() >= max_ai_planes:
		print("[EnemyAircraftSpawner] U: max AI planes reached")
		return

	var aircraft = _aircraft_scene.instantiate() as RigidBody3D
	if not aircraft:
		return

	aircraft.name = "FriendlyAI"
	get_tree().current_scene.add_child(aircraft)

	# Place at approach_0 XZ, altitude 450 m, pointed toward approach_1
	var spawn_pos := Vector3(wp0.global_position.x, 450.0, wp0.global_position.z)
	aircraft.global_position = spawn_pos
	var to_wp1 := Vector3(wp1.global_position.x - spawn_pos.x, 0.0, wp1.global_position.z - spawn_pos.z).normalized()
	var yaw := atan2(to_wp1.x, to_wp1.z)
	aircraft.global_rotation = Vector3(0.0, yaw, 0.0)
	aircraft.linear_velocity = to_wp1 * 80.0

	await get_tree().process_frame
	await get_tree().process_frame
	aircraft.remove_from_group("aircraft")
	aircraft.add_to_group("friendlies")
	aircraft.add_to_group("ai_aircraft")

	_apply_ai_aircraft_spawn_budget(aircraft)

	# Gear stowed — will be deployed by AIPilot at approach_2
	var control_gear = aircraft.find_child("ControlLandingGear", true, false)
	if control_gear and control_gear.has_method("send_to_landing_gears"):
		control_gear.send_to_landing_gears("stow")
		control_gear.send_to_tailhooks("stow")
		if control_gear.has_method("send_to_tailhook_simple"):
			control_gear.send_to_tailhook_simple(false)
		if "gear_down_state" in control_gear:
			control_gear.gear_down_state = false
		if control_gear.has_method("_set_collider_disabled"):
			control_gear._set_collider_disabled(true)

	if aircraft.has_signal("crashed"):
		aircraft.crashed.connect(_on_enemy_crashed.bind(aircraft), CONNECT_ONE_SHOT)
	if aircraft.has_signal("destroyed"):
		aircraft.destroyed.connect(_on_enemy_destroyed.bind(aircraft), CONNECT_ONE_SHOT)

	_active_ai_planes.append(aircraft)

	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(aircraft):
		return

	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()

	var ai_pilot = aircraft.find_child("AIPilot", true, false)
	if not ai_pilot or not ai_pilot.has_method("start_landing"):
		push_error("[EnemyAircraftSpawner] U: no AIPilot on spawned aircraft")
		return

	# start_landing() finds all waypoints, sets phase 0, enters APPROACH state.
	# Override phase to 1 so it heads straight to approach_1 (we spawned at approach_0).
	var ok: bool = ai_pilot.start_landing()
	if ok:
		ai_pilot._landing_phase = 1
		print("[EnemyAircraftSpawner] U: spawned on approach at approach_0, heading to approach_1")
	else:
		print("[EnemyAircraftSpawner] U: approach waypoints not found — place approach_0..4 in scene")

func _command_land():
	"""Shift+L: tell the currently watched AI plane to begin its carrier landing approach."""
	var switcher = get_tree().get_first_node_in_group("standalone_camera_switcher")
	if not switcher or not switcher.has_method("get_watched_aircraft"):
		print("[EnemyAircraftSpawner] Shift+L: camera switcher not found")
		return
	var aircraft: RigidBody3D = switcher.get_watched_aircraft()
	if not aircraft or not is_instance_valid(aircraft):
		print("[EnemyAircraftSpawner] Shift+L: no aircraft currently being watched")
		return
	var ai_pilot = aircraft.find_child("AIPilot", true, false)
	if not ai_pilot or not ai_pilot.has_method("start_landing"):
		print("[EnemyAircraftSpawner] Shift+L: no AIPilot on watched aircraft")
		return
	var ok: bool = ai_pilot.start_landing()
	if ok:
		print("[EnemyAircraftSpawner] Shift+L: landing commanded for ", aircraft.name)
	else:
		print("[EnemyAircraftSpawner] L: approach_0/1/2/3/4 waypoints not found in scene — place them first")

func _toggle_ai_attack_mode():
	"""Toggle all AI planes between patrol mode and attack mode (O key)."""
	var ai_planes = get_tree().get_nodes_in_group("ai_aircraft")
	var pilots: Array[AIPilot] = []
	for node in ai_planes:
		if not is_instance_valid(node):
			continue
		var pilot = node.find_child("AIPilot", true, false)
		if pilot and pilot is AIPilot:
			pilots.append(pilot)
	if pilots.is_empty():
		return
	var new_mode: bool = not pilots[0].ground_attack_enabled
	for pilot in pilots:
		pilot.ground_attack_enabled = new_mode
	var mode_str: String = "ATTACK" if new_mode else "PATROL"
	print("[EnemyAircraftSpawner] AI mode: ", mode_str, " (", pilots.size(), " plane(s))")

func _waypoint_most_ahead(aircraft: Node3D, waypoints: Array) -> int:
	"""Return index of waypoint that is most ahead of aircraft (largest forward dot product)."""
	if waypoints.is_empty():
		return 0
	var fwd := aircraft.global_transform.basis.z
	var best_idx := 0
	var best_dot := -INF
	for i in range(waypoints.size()):
		var wp: Vector3 = waypoints[i]
		var to_wp := (wp - aircraft.global_position).normalized()
		var dot_val := to_wp.dot(fwd)
		if dot_val > best_dot:
			best_dot = dot_val
			best_idx = i
	return best_idx

func _spawn_enemy_base() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		print("[EnemyAircraftSpawner] X: current scene not ready")
		return

	var carrier_pos: Vector3 = _get_carrier_position()
	var base_center: Vector3 = _find_flat_base_position(carrier_pos)
	var base := EnemyBase.new()
	base.faction_id = randi() % maxi(EnemyBase.FACTION_NAMES.size(), 1)
	scene_root.add_child(base)
	base.global_position = base_center
	print("[EnemyAircraftSpawner] X: spawned enemy base %s at %s" % [
		EnemyBase.FACTION_NAMES[base.faction_id % EnemyBase.FACTION_NAMES.size()],
		str(base_center)
	])

func _find_flat_base_position(carrier_pos: Vector3) -> Vector3:
	var carrier_ground_y: float = _sample_ground_height(carrier_pos)
	var best_pos := Vector3(carrier_pos.x + 2500.0, carrier_ground_y, carrier_pos.z)
	var best_score: float = INF

	var allowed_height_deltas: Array[float] = [
		enemy_base_max_height_delta_from_carrier_m,
		enemy_base_max_height_delta_from_carrier_m * 1.8,
		INF
	]

	for allowed_height_delta in allowed_height_deltas:
		var pass_found: bool = false
		for _attempt in range(40):
			var angle: float = randf() * TAU
			var dist: float = randf_range(2000.0, 3500.0)
			var center := Vector3(
				carrier_pos.x + cos(angle) * dist,
				0.0,
				carrier_pos.z + sin(angle) * dist
			)
			center.y = _sample_ground_height(center)

			# Check flatness: sample 4 corners ~60m out, measure max height difference.
			var max_delta: float = 0.0
			for corner in range(4):
				var ca: float = corner * TAU / 4.0
				var sample_pos := Vector3(
					center.x + cos(ca) * 60.0,
					0.0,
					center.z + sin(ca) * 60.0
				)
				var sample_y: float = _sample_ground_height(sample_pos)
				max_delta = maxf(max_delta, absf(sample_y - center.y))

			var height_delta: float = absf(center.y - carrier_ground_y)
			if allowed_height_delta != INF and height_delta > allowed_height_delta:
				continue

			var score: float = max_delta + height_delta * enemy_base_height_match_weight
			if score < best_score:
				best_score = score
				best_pos = center
				pass_found = true

			if max_delta <= enemy_base_flatness_goal_m and height_delta <= enemy_base_max_height_delta_from_carrier_m * 0.4:
				return best_pos

		if pass_found:
			break

	return best_pos

func _get_carrier_position() -> Vector3:
	var carriers = get_tree().get_nodes_in_group("carrier")
	if carriers.size() > 0 and carriers[0] is Node3D:
		return (carriers[0] as Node3D).global_position
	return Vector3.ZERO

func _get_carrier_forward() -> Vector3:
	var carriers = get_tree().get_nodes_in_group("carrier")
	if carriers.size() > 0 and carriers[0] is Node3D:
		return (carriers[0] as Node3D).global_transform.basis.z.normalized()
	return Vector3(0, 0, 1)
