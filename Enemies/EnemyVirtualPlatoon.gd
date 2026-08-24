class_name EnemyVirtualPlatoon
extends Node

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")
## Abstract representation of an enemy ground platoon.
## Moves as data until a friendly asset comes within ACTIVATE_RANGE_M,
## then spawns real VehicleEnemyLight instances inside a GroundVehiclePlatoon.
## When all friendlies leave DEACTIVATE_RANGE_M the real vehicles are freed
## and the platoon resumes as a map marker.
##
## Detection: ground units scan every DETECTION_SCAN_INTERVAL_S with a shorter
## range than air. Reports are delayed 40–90 s before reaching EnemyOpsManager.

enum Mission { PATROL, ATTACK_CARRIER, ATTACK_POSITION, RTB, HOLD }
enum VState  { VIRTUAL, ACTIVE }

const ACTIVATE_RANGE_M          := 3000.0
const DEACTIVATE_RANGE_M        := 4400.0
const PATROL_SPEED_MPS          := 8.0
const ATTACK_SPEED_MPS          := 10.0
const RTB_SPEED_MPS             := 9.0
const PATROL_WP_COUNT           := 6
const PATROL_WP_REACH_M         := 80.0
const DRIVE_NAV_CLEARANCE_M     := 60.0
const DRIVE_NAV_ANCHOR_M        := 220.0
const DRIVE_POSITION_SEARCH_M   := 1800.0
const DRIVE_POSITION_SAMPLES    := 16
const DRIVE_POSITION_RINGS      := 6
const DRIVE_NAV_CANDIDATES_TO_CHECK := 8
const DRIVE_FOOTPRINT_RADIUS_M  := 55.0
const DRIVE_MAX_CENTER_DROP_M   := 4.0
const DRIVE_PATH_REACH_M        := 65.0
const DRIVE_PATH_REPATH_M       := 140.0
const DRIVE_PATH_RETRY_S        := 10.0
const DRIVE_PATH_RETRY_JITTER_S := 6.0
const VIRTUAL_PATH_MAX_CONCURRENT_JOBS := 2
const DETECTION_RANGE_M         := 2500.0  # ground units see less than air
const DETECTION_SCAN_INTERVAL_S := 6.0
const REPORT_DELAY_MIN_S        := 40.0    # slower comms for ground
const REPORT_DELAY_MAX_S        := 90.0

# Configuration (set before adding to tree)
@export var platoon_name:  String = "EP-01"
@export var vehicle_count: int    = 5
@export var patrol_radius: float  = 2000.0
@export var faction_color: Color  = Color.RED

# Runtime state
var position:        Vector3 = Vector3.ZERO
var heading:         Vector3 = Vector3(1, 0, 0)
var home_position:   Vector3 = Vector3.ZERO
var mission:         Mission = Mission.PATROL
var vstate:          VState  = VState.VIRTUAL
var attack_position: Vector3 = Vector3.ZERO

var _vehicle_scenes:   Array[PackedScene] = []
var _patrol_waypoints: Array[Vector3] = []
var _patrol_wp_idx:    int = 0
var _platoon_node:     GroundVehiclePlatoon = null
var _active_vehicles:  Array[Node3D] = []
var _last_live_count:  int = 0
var _detection_timer:  float = 0.0
var _pending_reports:  Array[Dictionary] = []
var _rng:              RandomNumberGenerator = RandomNumberGenerator.new()
var _virtual_path:     Array[Vector3] = []
var _virtual_path_idx: int = 0
var _virtual_path_goal: Vector3 = Vector3.INF
var _virtual_path_retry_s: float = 0.0
var _is_virtual_pathfinding: bool = false

static var _global_virtual_path_jobs: int = 0

signal unit_destroyed(platoon: EnemyVirtualPlatoon)


func _ready() -> void:
	if WorldUnitIndex != null:
		WorldUnitIndex.register_formation(self, "platoon", platoon_name)


func _exit_tree() -> void:
	if WorldUnitIndex != null:
		WorldUnitIndex.unregister_formation(self)


func setup(home_pos: Vector3, scenes: Array[PackedScene], start_angle: float = 0.0) -> void:
	home_position   = home_pos
	_vehicle_scenes = scenes
	_rng.randomize()
	_generate_patrol_waypoints(start_angle)
	_randomize_initial_patrol_waypoint()
	if not _patrol_waypoints.is_empty():
		position = _patrol_waypoints[_patrol_wp_idx]
	else:
		var ix := home_pos.x + cos(start_angle) * patrol_radius
		var iz := home_pos.z + sin(start_angle) * patrol_radius
		position = _find_driveable_position_near(Vector3(ix, home_pos.y, iz), home_pos, false)
	_update_heading_toward_next_patrol_waypoint(start_angle)
	_detection_timer = _rng.randf_range(0.0, DETECTION_SCAN_INTERVAL_S)


func capture_save_state() -> Dictionary:
	var scene_paths: Array[String] = []
	for scene in _vehicle_scenes:
		scene_paths.append(scene.resource_path if scene != null else "")
	return {
		"platoon_name": platoon_name,
		"vehicle_count": vehicle_count,
		"patrol_radius": patrol_radius,
		"faction_color": faction_color,
		"position": position,
		"heading": heading,
		"home_position": home_position,
		"mission": mission,
		"attack_position": attack_position,
		"vehicle_scene_paths": scene_paths,
		"patrol_waypoints": _patrol_waypoints.duplicate(),
		"patrol_wp_idx": _patrol_wp_idx,
		"pending_reports": _pending_reports.duplicate(true),
		"virtual_path": _virtual_path.duplicate(),
		"virtual_path_idx": _virtual_path_idx,
		"virtual_path_goal": _virtual_path_goal,
	}


func restore_save_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	platoon_name = str(state.get("platoon_name", platoon_name))
	vehicle_count = maxi(int(state.get("vehicle_count", vehicle_count)), 0)
	patrol_radius = float(state.get("patrol_radius", patrol_radius))
	faction_color = state.get("faction_color", faction_color) as Color
	position = state.get("position", position) as Vector3
	heading = state.get("heading", heading) as Vector3
	home_position = state.get("home_position", home_position) as Vector3
	mission = int(state.get("mission", Mission.PATROL))
	attack_position = state.get("attack_position", attack_position) as Vector3
	vstate = VState.VIRTUAL
	_platoon_node = null
	_active_vehicles.clear()
	_vehicle_scenes.clear()
	var paths_variant: Variant = state.get("vehicle_scene_paths", [])
	if paths_variant is Array:
		for path_variant in paths_variant:
			_vehicle_scenes.append(load(str(path_variant)) as PackedScene)
	_patrol_waypoints.clear()
	var waypoints_variant: Variant = state.get("patrol_waypoints", [])
	if waypoints_variant is Array:
		for waypoint_variant in waypoints_variant:
			if waypoint_variant is Vector3:
				_patrol_waypoints.append(waypoint_variant as Vector3)
	_patrol_wp_idx = clampi(int(state.get("patrol_wp_idx", 0)), 0, maxi(_patrol_waypoints.size() - 1, 0))
	_pending_reports.clear()
	var reports_variant: Variant = state.get("pending_reports", [])
	if reports_variant is Array:
		for report_variant in reports_variant:
			if report_variant is Dictionary:
				_pending_reports.append((report_variant as Dictionary).duplicate(true))
	_virtual_path.clear()
	var path_variant: Variant = state.get("virtual_path", [])
	if path_variant is Array:
		for waypoint_variant in path_variant:
			if waypoint_variant is Vector3:
				_virtual_path.append(waypoint_variant as Vector3)
	_virtual_path_idx = clampi(int(state.get("virtual_path_idx", 0)), 0, _virtual_path.size())
	_virtual_path_goal = state.get("virtual_path_goal", Vector3.INF) as Vector3
	_is_virtual_pathfinding = false
	_rng.randomize()
	return true


func _generate_patrol_waypoints(start_angle: float) -> void:
	_patrol_waypoints.clear()
	for i in range(PATROL_WP_COUNT):
		var angle := start_angle + float(i) * TAU / float(PATROL_WP_COUNT) + _rng.randf_range(-0.38, 0.38)
		var r     := patrol_radius * _rng.randf_range(0.65, 1.15)
		var wx    := home_position.x + cos(angle) * r
		var wz    := home_position.z + sin(angle) * r
		_patrol_waypoints.append(_find_driveable_position_near(Vector3(wx, home_position.y, wz), home_position, false))
	_patrol_wp_idx = 0


func _randomize_initial_patrol_waypoint() -> void:
	if _patrol_waypoints.is_empty():
		_patrol_wp_idx = 0
		return
	_patrol_wp_idx = _rng.randi() % _patrol_waypoints.size()


func _update_heading_toward_next_patrol_waypoint(fallback_angle: float) -> void:
	if _patrol_waypoints.size() <= 1:
		heading = Vector3(-sin(fallback_angle), 0.0, cos(fallback_angle)).normalized()
		return
	var next_idx: int = (_patrol_wp_idx + 1) % _patrol_waypoints.size()
	var to_next: Vector3 = _patrol_waypoints[next_idx] - position
	to_next.y = 0.0
	if to_next.length_squared() <= 1.0:
		heading = Vector3(-sin(fallback_angle), 0.0, cos(fallback_angle)).normalized()
		return
	heading = to_next.normalized()


func tick(delta: float) -> void:
	var _profiler_start: int = FrameProfiler.begin("EnemyVirtualPlatoon.tick")
	_active_vehicles = _active_vehicles.filter(func(v): return is_instance_valid(v))

	if vstate == VState.ACTIVE:
		if _platoon_node == null or not is_instance_valid(_platoon_node):
			_on_platoon_gone()
			FrameProfiler.end("EnemyVirtualPlatoon.tick", _profiler_start)
			return
		var live := _platoon_node.get_members().size()
		if live != _last_live_count:
			_last_live_count = live
			vehicle_count = live
			if live == 0:
				_on_platoon_gone()
				FrameProfiler.end("EnemyVirtualPlatoon.tick", _profiler_start)
				return
		var centroid := _platoon_node.get_contact_position()
		if centroid != Vector3.INF:
			position = centroid
		var active_check_start: int = FrameProfiler.begin("EnemyVirtualPlatoon.active_checks")
		_check_dematerialize()
		if vstate != VState.ACTIVE:
			FrameProfiler.end("EnemyVirtualPlatoon.active_checks", active_check_start)
			FrameProfiler.end("EnemyVirtualPlatoon.tick", _profiler_start)
			return
		# Materialized units report immediately
		_scan_for_contacts(true)
		FrameProfiler.end("EnemyVirtualPlatoon.active_checks", active_check_start)
		FrameProfiler.end("EnemyVirtualPlatoon.tick", _profiler_start)
		return

	if vehicle_count <= 0:
		FrameProfiler.end("EnemyVirtualPlatoon.tick", _profiler_start)
		return

	var move_start: int = FrameProfiler.begin("EnemyVirtualPlatoon.move")
	match mission:
		Mission.PATROL:
			_tick_patrol(delta)
		Mission.ATTACK_CARRIER, Mission.ATTACK_POSITION:
			_tick_move_to(attack_position, ATTACK_SPEED_MPS, delta)
		Mission.RTB:
			_tick_rtb(delta)
		Mission.HOLD:
			pass
	FrameProfiler.end("EnemyVirtualPlatoon.move", move_start)

	var materialize_start: int = FrameProfiler.begin("EnemyVirtualPlatoon.materialize_check")
	_check_materialize()
	FrameProfiler.end("EnemyVirtualPlatoon.materialize_check", materialize_start)
	var detection_start: int = FrameProfiler.begin("EnemyVirtualPlatoon.detection")
	_tick_detection(delta)
	FrameProfiler.end("EnemyVirtualPlatoon.detection", detection_start)
	FrameProfiler.end("EnemyVirtualPlatoon.tick", _profiler_start)


# ── Movement ──────────────────────────────────────────────────────────────────

func _tick_patrol(delta: float) -> void:
	if _patrol_waypoints.is_empty():
		_generate_patrol_waypoints(0.0)
		return
	var target    := _patrol_waypoints[_patrol_wp_idx]
	var to_target := Vector3(target.x - position.x, 0.0, target.z - position.z)
	if to_target.length() < PATROL_WP_REACH_M:
		_patrol_wp_idx = (_patrol_wp_idx + 1) % _patrol_waypoints.size()
		_clear_virtual_path()
		return
	_move_virtual_toward(target, PATROL_SPEED_MPS, delta, PATROL_WP_REACH_M)


func _tick_move_to(target: Vector3, speed: float, delta: float) -> void:
	var to_target := Vector3(target.x - position.x, 0.0, target.z - position.z)
	if to_target.length() < 80.0:
		return
	_move_virtual_toward(target, speed, delta, 80.0)


func _tick_rtb(delta: float) -> void:
	var to_base := Vector3(home_position.x - position.x, 0.0, home_position.z - position.z)
	if to_base.length() < 150.0:
		mission  = Mission.HOLD
		position = home_position
		_clear_virtual_path()
		return
	_move_virtual_toward(home_position, RTB_SPEED_MPS, delta, 150.0)


func _move_virtual_toward(raw_target: Vector3, speed: float, delta: float, stop_distance: float) -> void:
	_virtual_path_retry_s = maxf(_virtual_path_retry_s - delta, 0.0)
	var target := _project_to_ground(raw_target)
	var follow_start: int = FrameProfiler.begin("EnemyVirtualPlatoon.follow_point")
	var follow := _get_virtual_follow_point(target)
	FrameProfiler.end("EnemyVirtualPlatoon.follow_point", follow_start)
	if not _is_valid_world_position(follow):
		return
	var to_follow := Vector3(follow.x - position.x, 0.0, follow.z - position.z)
	var follow_dist := to_follow.length()
	if follow_dist <= DRIVE_PATH_REACH_M:
		if _virtual_path_idx < _virtual_path.size():
			_virtual_path_idx += 1
			if _virtual_path_idx >= _virtual_path.size():
				if Vector3(target.x - position.x, 0.0, target.z - position.z).length() <= stop_distance:
					return
				follow = target
			else:
				follow = _virtual_path[_virtual_path_idx]
				if not _is_valid_world_position(follow):
					return
			to_follow = Vector3(follow.x - position.x, 0.0, follow.z - position.z)
			follow_dist = to_follow.length()
		elif Vector3(target.x - position.x, 0.0, target.z - position.z).length() <= stop_distance:
			return
	if follow_dist <= 0.001:
		return
	var dir := to_follow / follow_dist
	var step := minf(speed * delta, follow_dist)
	position += dir * step
	position = _project_to_ground(position)
	heading = dir


func _get_virtual_follow_point(target: Vector3) -> Vector3:
	if not NavGraph.is_ready():
		return target if _is_driveable_terrain_position(target) else _find_driveable_position_near(target, position, false)
	var goal_shifted := not _is_valid_world_position(_virtual_path_goal) \
		or _flat_distance(_virtual_path_goal, target) > DRIVE_PATH_REPATH_M
	var needs_path := _virtual_path.is_empty()
	if goal_shifted or needs_path:
		if _is_virtual_pathfinding or _virtual_path_retry_s > 0.0:
			return position
		_recompute_virtual_path(target)
	if _virtual_path_idx < _virtual_path.size():
		return _virtual_path[_virtual_path_idx]
	if _is_driveable_terrain_position(target):
		return target
	return Vector3.INF


func _recompute_virtual_path(target: Vector3) -> void:
	if _is_virtual_pathfinding:
		return
	_clear_virtual_path()
	if not NavGraph.is_ready():
		return
	if _global_virtual_path_jobs >= VIRTUAL_PATH_MAX_CONCURRENT_JOBS:
		_virtual_path_retry_s = _rng.randf_range(0.5, 1.5)
		return
	var start_pos := position
	var goal_pos := target
	if not _is_driveable_terrain_position(start_pos) or not _is_driveable_terrain_position(goal_pos):
		_virtual_path_retry_s = _next_path_retry_s()
		return
	if not _is_valid_world_position(start_pos) or not _is_valid_world_position(goal_pos):
		_virtual_path_retry_s = _next_path_retry_s()
		return
	_virtual_path_goal = goal_pos
	_is_virtual_pathfinding = true
	_global_virtual_path_jobs += 1
	var callback: Callable = func(path: Array[Vector3]) -> void:
		_on_virtual_path_computed(path, goal_pos)
	var job_id: int = NavPathScheduler.request_find_path(start_pos, goal_pos, DRIVE_NAV_CLEARANCE_M, callback, 0, "EnemyVirtualPlatoon")
	if job_id < 0:
		_global_virtual_path_jobs = maxi(_global_virtual_path_jobs - 1, 0)
		_is_virtual_pathfinding = false
		_virtual_path_retry_s = _next_path_retry_s()
		return


func _on_virtual_path_computed(path: Array[Vector3], goal_at_request: Vector3) -> void:
	_global_virtual_path_jobs = maxi(_global_virtual_path_jobs - 1, 0)
	_is_virtual_pathfinding = false
	if not is_instance_valid(self):
		return
	if not _is_valid_world_position(_virtual_path_goal) or _flat_distance(goal_at_request, _virtual_path_goal) > DRIVE_PATH_REPATH_M:
		return
	if path.is_empty():
		_virtual_path_retry_s = _next_path_retry_s()
		return
	_virtual_path_goal = goal_at_request
	_virtual_path.clear()
	for point in path:
		if point is Vector3:
			_virtual_path.append(_project_to_ground(point as Vector3))
	var projected_goal := _project_to_ground(goal_at_request)
	if _virtual_path.is_empty() or _flat_distance(_virtual_path[_virtual_path.size() - 1], projected_goal) > DRIVE_PATH_REACH_M:
		_virtual_path.append(projected_goal)
	_virtual_path_idx = 0
	while _virtual_path_idx < _virtual_path.size() and _flat_distance(position, _virtual_path[_virtual_path_idx]) <= DRIVE_PATH_REACH_M:
		_virtual_path_idx += 1


func _clear_virtual_path() -> void:
	_virtual_path.clear()
	_virtual_path_idx = 0
	_virtual_path_goal = Vector3.INF
	_virtual_path_retry_s = 0.0


func _next_path_retry_s() -> float:
	return DRIVE_PATH_RETRY_S + _rng.randf_range(0.0, DRIVE_PATH_RETRY_JITTER_S)


# ── Detection & reporting ─────────────────────────────────────────────────────

func _tick_detection(delta: float) -> void:
	_detection_timer -= delta
	if _detection_timer <= 0.0:
		_detection_timer = DETECTION_SCAN_INTERVAL_S
		_scan_for_contacts(false)
	_process_pending_reports(delta)


func _scan_for_contacts(immediate: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var delay_s := 0.0 if immediate else _rng.randf_range(REPORT_DELAY_MIN_S, REPORT_DELAY_MAX_S)

	var carrier := tree.get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		if position.distance_to(carrier.global_position) <= DETECTION_RANGE_M:
			_queue_report("carrier", carrier.global_position, 1, delay_s)

	var friendly_air_pos   := Vector3.ZERO
	var friendly_air_count := 0
	for aircraft in _get_friendly_air_nodes():
		if position.distance_to(aircraft.global_position) <= DETECTION_RANGE_M:
			friendly_air_pos += aircraft.global_position
			friendly_air_count += 1
	if friendly_air_count > 0:
		_queue_report("air", friendly_air_pos / float(friendly_air_count), friendly_air_count, delay_s)

	var friendly_gnd_pos   := Vector3.ZERO
	var friendly_gnd_count := 0
	for node in tree.get_nodes_in_group("ground_vehicles"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if (node as Node3D).is_in_group("enemies"):
			continue
		if position.distance_to((node as Node3D).global_position) <= DETECTION_RANGE_M:
			friendly_gnd_pos   += (node as Node3D).global_position
			friendly_gnd_count += 1
	if friendly_gnd_count > 0:
		_queue_report("ground", friendly_gnd_pos / float(friendly_gnd_count), friendly_gnd_count, delay_s)


func _queue_report(contact_type: String, contact_pos: Vector3, strength: int, delay_s: float) -> void:
	for r in _pending_reports:
		if r["type"] == contact_type:
			r["position"] = contact_pos
			r["strength"] = strength
			return
	_pending_reports.append({
		"type":      contact_type,
		"position":  contact_pos,
		"strength":  strength,
		"countdown": delay_s,
	})


func _process_pending_reports(delta: float) -> void:
	var sent: Array[int] = []
	for i in range(_pending_reports.size()):
		_pending_reports[i]["countdown"] -= delta
		if _pending_reports[i]["countdown"] <= 0.0:
			var r: Dictionary = _pending_reports[i]
			EnemyOpsManager.receive_intel(platoon_name, r["type"], r["position"], r["strength"])
			sent.append(i)
	for i in range(sent.size() - 1, -1, -1):
		_pending_reports.remove_at(sent[i])


# ── Materialize / dematerialize ───────────────────────────────────────────────

func _check_materialize() -> void:
	if _vehicle_scenes.is_empty() or vstate == VState.ACTIVE:
		return
	if _should_materialize():
		_materialize()


func _check_dematerialize() -> void:
	if WorldUnitIndex != null and WorldUnitIndex.enabled and WorldUnitIndex.formation_relevance_enabled:
		if WorldUnitIndex.should_dematerialize_formation(position, DEACTIVATE_RANGE_M):
			dematerialize()
		return
	if _nearest_player_relevance_distance() > DEACTIVATE_RANGE_M:
		dematerialize()


func _should_materialize() -> bool:
	if WorldUnitIndex != null and WorldUnitIndex.enabled and WorldUnitIndex.formation_relevance_enabled:
		return WorldUnitIndex.should_materialize_formation(position, ACTIVATE_RANGE_M, DEACTIVATE_RANGE_M)
	var player_dist: float = _nearest_player_relevance_distance()
	if player_dist <= ACTIVATE_RANGE_M:
		return true
	if player_dist <= DEACTIVATE_RANGE_M and _nearest_friendly_distance() <= ACTIVATE_RANGE_M:
		return true
	return false


func _materialize() -> void:
	if _vehicle_scenes.is_empty() or vstate == VState.ACTIVE or vehicle_count <= 0:
		return
	vstate = VState.ACTIVE
	var scene_root := get_tree().current_scene

	_platoon_node = GroundVehiclePlatoon.new()
	_platoon_node.name      = "EnemyPlatoon_" + platoon_name
	_platoon_node.platoon_id = platoon_name
	_platoon_node.team      = 2
	scene_root.add_child(_platoon_node)
	_platoon_node.global_position = position

	for i in range(vehicle_count):
		var scene := _vehicle_scenes[_rng.randi() % _vehicle_scenes.size()]
		var veh   := scene.instantiate() as Node3D
		if veh == null:
			continue
		scene_root.add_child(veh)
		var angle  := float(i) * TAU / float(maxi(vehicle_count, 1))
		var spread := Vector3(cos(angle) * 28.0, 0.0, sin(angle) * 28.0)
		var spawn_pos := _find_driveable_position_near(position + spread, position, false)
		if not _is_valid_world_position(spawn_pos):
			spawn_pos = _project_to_ground(position + spread)
		veh.global_position = spawn_pos
		veh.set_meta("faction_color", faction_color)
		if "team" in veh:
			veh.set("team", 2)
		if veh.has_method("assign_platoon"):
			veh.call("assign_platoon", _platoon_node)
		_active_vehicles.append(veh)

	_last_live_count = vehicle_count
	_apply_mission_to_platoon()
	# Immediate intel — we can see the player
	_scan_for_contacts(true)
	print("[EnemyVirtualPlatoon] %s materialized (%d vehicles) at (%.0f, %.0f)" % [
		platoon_name, vehicle_count, position.x, position.z])


func _apply_mission_to_platoon() -> void:
	if _platoon_node == null or not is_instance_valid(_platoon_node):
		return
	match mission:
		Mission.ATTACK_CARRIER:
			var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
			if carrier and is_instance_valid(carrier):
				_platoon_node.set_attack_node(carrier)
				return
			_platoon_node.set_attack_position(attack_position)
		Mission.ATTACK_POSITION:
			_platoon_node.set_attack_position(attack_position)
		_:
			# PATROL / RTB / HOLD — move to next patrol waypoint
			var dest := _current_patrol_waypoint()
			_platoon_node.set_move_objective(dest)


func _current_patrol_waypoint() -> Vector3:
	if _patrol_waypoints.is_empty():
		return home_position
	return _patrol_waypoints[_patrol_wp_idx % _patrol_waypoints.size()]


func _on_platoon_gone() -> void:
	vehicle_count    = 0
	vstate           = VState.VIRTUAL
	_platoon_node    = null
	_active_vehicles.clear()
	unit_destroyed.emit(self)


func dematerialize() -> void:
	for veh in _active_vehicles:
		if is_instance_valid(veh):
			veh.queue_free()
	_active_vehicles.clear()
	if _platoon_node != null and is_instance_valid(_platoon_node):
		_platoon_node.queue_free()
	_platoon_node = null
	vstate  = VState.VIRTUAL
	mission = Mission.RTB
	print("[EnemyVirtualPlatoon] %s dematerialized → RTB" % platoon_name)


# ── Mission orders ────────────────────────────────────────────────────────────

func set_mission_patrol() -> void:
	mission = Mission.PATROL
	_clear_virtual_path()
	if vstate == VState.ACTIVE:
		_apply_mission_to_platoon()


func set_mission_attack_carrier() -> void:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		attack_position = carrier.global_position
	mission = Mission.ATTACK_CARRIER
	_clear_virtual_path()
	if vstate == VState.ACTIVE:
		_apply_mission_to_platoon()


func set_mission_attack_position(target: Vector3) -> void:
	attack_position = _find_driveable_position_near(target, position, false)
	mission         = Mission.ATTACK_POSITION
	_clear_virtual_path()
	if vstate == VState.ACTIVE:
		_apply_mission_to_platoon()


func set_mission_rtb() -> void:
	mission = Mission.RTB
	_clear_virtual_path()
	if vstate == VState.ACTIVE:
		_apply_mission_to_platoon()


# Terrain and navigation helpers

func _find_driveable_position_near(desired: Vector3, reference: Vector3, require_nav_anchor: bool = true) -> Vector3:
	var projected := _project_to_ground(desired)
	if require_nav_anchor:
		if _is_driveable_position(projected):
			return projected
	elif _is_driveable_terrain_position(projected):
		return projected

	var candidates: Array[Dictionary] = []
	var rings := maxi(DRIVE_POSITION_RINGS, 1)
	var samples := maxi(DRIVE_POSITION_SAMPLES, 4)
	for ring in range(1, rings + 1):
		var radius := DRIVE_POSITION_SEARCH_M * float(ring) / float(rings)
		var angle_offset := _rng.randf_range(0.0, TAU)
		for sample_idx in range(samples):
			var angle := angle_offset + TAU * float(sample_idx) / float(samples)
			var candidate := Vector3(
				desired.x + cos(angle) * radius,
				desired.y,
				desired.z + sin(angle) * radius
			)
			candidate = _project_to_ground(candidate)
			if not _is_driveable_terrain_position(candidate):
				continue
			var score := _flat_distance(candidate, desired) + _flat_distance(candidate, reference) * 0.12
			candidates.append({"position": candidate, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) < float(b["score"])
	)
	if not candidates.is_empty():
		if require_nav_anchor:
			var nav_checks: int = mini(candidates.size(), DRIVE_NAV_CANDIDATES_TO_CHECK)
			for i in range(nav_checks):
				var entry: Dictionary = candidates[i]
				var candidate_pos: Vector3 = entry["position"] as Vector3
				if _has_drive_nav_anchor(candidate_pos):
					return candidate_pos
		var fallback_entry: Dictionary = candidates[0]
		return fallback_entry["position"] as Vector3
	var projected_reference := _project_to_ground(reference)
	if require_nav_anchor:
		if _is_driveable_position(projected_reference):
			return projected_reference
	elif _is_driveable_terrain_position(projected_reference):
		return projected_reference
	return projected if _is_valid_world_position(projected) else Vector3.INF


func _is_driveable_position(world_pos: Vector3) -> bool:
	if not _is_driveable_terrain_position(world_pos):
		return false
	return _has_drive_nav_anchor(world_pos)


func _is_driveable_terrain_position(world_pos: Vector3) -> bool:
	if not _is_valid_world_position(world_pos) or not TerrainNavGrid.is_ready():
		return false
	if not TerrainNavGrid.is_low_clear_position(world_pos.x, world_pos.z, _max_drive_slope_m()):
		return false
	if TerrainNavGrid.has_query_grid():
		if not TerrainNavGrid.is_stable_footprint(
				world_pos.x,
				world_pos.z,
				DRIVE_FOOTPRINT_RADIUS_M,
				DRIVE_MAX_CENTER_DROP_M,
				_max_drive_slope_m()):
			return false
	return true


func _has_drive_nav_anchor(world_pos: Vector3) -> bool:
	if NavGraph.is_ready():
		return NavGraph.can_anchor(world_pos, DRIVE_NAV_CLEARANCE_M, DRIVE_NAV_ANCHOR_M)
	return true


func _project_to_ground(world_pos: Vector3) -> Vector3:
	var projected := world_pos
	var h := TerrainNavGrid.sample_height(world_pos.x, world_pos.z)
	if h > TerrainNavGrid.IMPASSABLE * 0.5:
		projected.y = h
	return projected


func _max_drive_slope_m() -> float:
	return NavGraph.max_slope_m if NavGraph != null else 18.0


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _is_valid_world_position(world_pos: Vector3) -> bool:
	return is_finite(world_pos.x) and is_finite(world_pos.y) and is_finite(world_pos.z)


# ── Proximity helpers ─────────────────────────────────────────────────────────

func _nearest_friendly_distance() -> float:
	var tree := get_tree()
	if tree == null:
		return INF
	var best_sq := INF
	var carrier := tree.get_first_node_in_group("carrier") as Node3D
	if carrier and is_instance_valid(carrier):
		best_sq = minf(best_sq, position.distance_squared_to(carrier.global_position))
	for aircraft in _get_friendly_air_nodes():
		best_sq = minf(best_sq, position.distance_squared_to(aircraft.global_position))
	for node in tree.get_nodes_in_group("ground_vehicles"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if (node as Node3D).is_in_group("enemies"):
			continue
		best_sq = minf(best_sq, position.distance_squared_to((node as Node3D).global_position))
	return sqrt(best_sq)


func _nearest_player_relevance_distance() -> float:
	var player_node: Node3D = _get_player_relevance_node()
	if player_node != null and is_instance_valid(player_node):
		return position.distance_to(player_node.global_position)
	return _nearest_friendly_distance()


func _get_player_relevance_node() -> Node3D:
	var camera_node: Node3D = _get_active_camera_relevance_node()
	if camera_node != null and is_instance_valid(camera_node):
		return camera_node
	var flight_director: Node = get_node_or_null("/root/FlightDirector")
	if flight_director != null:
		var controlled_value: Variant = flight_director.get("player_controlled_plane")
		if controlled_value is Node3D and is_instance_valid(controlled_value):
			return controlled_value as Node3D
		var viewed_value: Variant = flight_director.get("current_viewed_aircraft")
		if viewed_value is Node3D and is_instance_valid(viewed_value):
			return viewed_value as Node3D
	return null


func _get_active_camera_relevance_node() -> Node3D:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var camera: Camera3D = viewport.get_camera_3d()
		if camera != null and is_instance_valid(camera):
			var node: Node = camera
			while node != null:
				if node is Node3D and _is_player_relevance_root(node):
					return node as Node3D
				node = node.get_parent()
			return camera
	return null


func _is_player_relevance_root(node: Node) -> bool:
	return node.is_in_group("aircraft") \
		or node.is_in_group("ai_aircraft") \
		or node.is_in_group("ground_vehicles") \
		or node.is_in_group("carrier") \
		or node.is_in_group("friendlies")


func _get_friendly_air_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var tree := get_tree()
	if tree == null:
		return result
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in tree.get_nodes_in_group(group_name):
			if not is_instance_valid(node) or not (node is Node3D):
				continue
			var aircraft := node as Node3D
			if aircraft.is_in_group("enemies"):
				continue
			var id := aircraft.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			result.append(aircraft)
	return result


# ── Origin shift ──────────────────────────────────────────────────────────────

func apply_origin_shift(offset: Vector3) -> void:
	position        -= offset
	home_position   -= offset
	attack_position -= offset
	for i in range(_patrol_waypoints.size()):
		_patrol_waypoints[i] -= offset
	for r in _pending_reports:
		r["position"] = (r["position"] as Vector3) - offset
