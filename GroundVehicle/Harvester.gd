extends VehicleFriendlyLight
## Unarmed utility vehicle. Resource ownership stays in its cargo until unloading.
const CAPACITY := 160.0
const EXTRACTION_RATE := 12.0
const PARKING_TOLERANCE := 0.75
var cargo := {"corium": 0.0, "plasteel": 0.0}
var collection_target := Vector3.ZERO
var collecting := false
var _intake_time := 0.0
var collection_parking_position := Vector3.ZERO
var collection_parking_forward := Vector3.ZERO
var navigation_status := "idle"

func _ready() -> void:
	turret_range = 0.0
	passenger_capacity = 0
	max_speed = 14.0
	allow_reverse_navigation = false
	waypoint_reach_distance = 0.5
	path_waypoint_reach_distance = 3.0
	path_min_clearance_m = 6.0
	path_max_segment_m = 300.0
	loop_waypoints = false
	super._ready()
	add_to_group("harvesters")
	destroyed.connect(_on_harvester_destroyed)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var visual: Node3D = get_node("Body")
	visual.set("cargo_fraction", cargo_total() / CAPACITY)
	max_speed = lerpf(14.0, 10.0, cargo_total() / CAPACITY)
	var stopped := Vector2(velocity.x, velocity.z).length() < 0.5
	visual.set("arm_extended", collecting and stopped and not is_dying)
	visual.set("suction", collecting and stopped and not is_dying)
	if collecting:
		_intake_time += delta
		# Scan a small patch, with the tool held close to the actual material.
		var scan := Vector3(sin(_intake_time * 0.8) * 0.35, 0.0, sin(_intake_time * 0.53) * 0.3)
		visual.set("arm_target", visual.to_local(collection_target + scan + Vector3.UP * 0.8))

func cargo_total() -> float:
	return float(cargo.corium) + float(cargo.plasteel)

func get_active_waypoints() -> Array[Vector3]:
	if _nav_path_index < _nav_path_positions.size():
		var result: Array[Vector3] = _nav_path_positions.slice(_nav_path_index)
		result.append_array(_waypoint_positions.slice(_waypoint_index + 1))
		return result
	return _waypoint_positions.slice(_waypoint_index)

func corium_exposure_resistance() -> float:
	# The shielded intake and sealed cargo tank contain active corium safely.
	return 1.0

func set_collection_approach(target: Vector3, parking: Vector3, forward: Vector3) -> void:
	collection_target = target
	collection_parking_position = parking
	collection_parking_forward = forward.normalized()

func at_collection_stop() -> bool:
	return _flat_distance(global_position, collection_parking_position) <= PARKING_TOLERANCE \
		and Vector2(velocity.x, velocity.z).length() < 0.5

func align_for_collection(delta: float) -> bool:
	if not at_collection_stop():
		return false
	var target_yaw := atan2(collection_parking_forward.x, collection_parking_forward.z)
	var current_yaw := atan2(global_basis.z.x, global_basis.z.z)
	var yaw_error := wrapf(target_yaw - current_yaw, -PI, PI)
	global_rotate(Vector3.UP, clampf(yaw_error, -turn_speed * delta, turn_speed * delta))
	return absf(yaw_error) < 0.04

func _refresh_drive_command(delta: float) -> void:
	super._refresh_drive_command(delta)
	if not _drive_command_has_destination or _drive_command_formation_hold:
		return
	# Brake for each approach waypoint, especially the precise side-on stop.
	var distance := _flat_distance(global_position, _get_raw_navigation_destination())
	if distance < 12.0:
		var approach_speed := clampf(distance * 0.55, 0.65, max_speed)
		_drive_command_throttle = minf(_drive_command_throttle, approach_speed / max_speed)

func _get_follow_navigation_destination() -> Vector3:
	var exact := _get_raw_navigation_destination()
	if NavGraph.is_ready() and TerrainNavGrid.is_ready() and _flat_distance(global_position, exact) < 80.0 and NavGraph.can_traverse_segment(global_position, exact, path_min_clearance_m) and TerrainNavGrid.is_stable_footprint(exact.x, exact.z, 3.0, 2.0, 2.5):
		return exact
	return super._get_follow_navigation_destination()

func _recompute_navigation_path(raw_target: Vector3) -> void:
	if not NavGraph.is_ready() or _is_pathfinding or _nav_retry_cooldown_s > 0.0:
		return
	_is_pathfinding = true
	navigation_status = "planning"
	var start := global_position
	var clearance := path_min_clearance_m
	var work: Callable = func() -> Dictionary:
		# The destination may be beyond a long canyon wall. Rotating a short
		# 300 m goal cannot tell which detour actually reaches the assigned site.
		var route := NavGraph.find_ground_path(start, raw_target, clearance)
		return {"best_path": route, "target": raw_target, "status_code": 2 if route.is_empty() else 0}
	if NavPathScheduler.request_work(work, _on_navigation_path_job_result, 0, "Harvester.navigation") < 0:
		_is_pathfinding = false
		_nav_retry_cooldown_s = path_retry_cooldown_s

func _on_navigation_path_computed(best_path: Array[Vector3], target_at_request_time: Vector3,
		status_code: int, no_anchor_cooldown: float, path_cooldown: float) -> void:
	var current_order := _flat_distance(target_at_request_time, _get_raw_navigation_destination()) <= 1.0
	super._on_navigation_path_computed(best_path, target_at_request_time, status_code, no_anchor_cooldown, path_cooldown)
	if current_order:
		navigation_status = "travelling" if status_code == 0 and not best_path.is_empty() else "blocked"
		# _clear_navigation_path resets this in the shared failure handler. Keep
		# failed orders on a bounded retry cadence instead of submitting every tick.
		if navigation_status == "blocked":
			_nav_retry_cooldown_s = maxf(_nav_retry_cooldown_s, path_cooldown)

func _update_path_stuck_state(delta: float, follow_destination: Vector3) -> void:
	if not use_waypoint_pathfinding or _nav_path_index >= _nav_path_positions.size():
		_nav_stuck_timer_s = 0.0
		_nav_prev_wp_distance = INF
		return
	var distance := _flat_distance(global_position, follow_destination)
	# Measure progress over time. The shared test only noticed a vehicle getting
	# farther away on every tick, so one sitting still never requested a new path.
	if distance < _nav_prev_wp_distance - 0.5:
		_nav_prev_wp_distance = distance
		_nav_stuck_timer_s = 0.0
	else:
		_nav_stuck_timer_s += delta
	if _nav_stuck_timer_s >= path_stuck_timeout_s and not _is_pathfinding and _nav_retry_cooldown_s <= 0.0:
		_recompute_navigation_path(_get_raw_navigation_destination())
		_nav_stuck_timer_s = 0.0
		_nav_prev_wp_distance = INF

func _retrieve_drive_to_rally(delta: float) -> void:
	var rally := _get_rally_world_pos()
	if _flat_distance(global_position, rally) < 12.0:
		super._retrieve_drive_to_rally(delta)
		return
	# Far from the carrier, use the terrain route in both directions. The normal
	# bay controller takes over alignment and the physical ramp at the rally point.
	use_waypoint_pathfinding = true
	if _waypoint_positions.is_empty() or _flat_distance(_waypoint_positions[0], rally) > 8.0:
		var points: Array[Vector3] = [rally]
		set_patrol_waypoints(points)
	_update_navigation_path(delta)
	_refresh_drive_command(delta)
	_apply_cached_drive_motion(delta, false)
	_update_wheel_visuals(delta, true)

func can_extract() -> bool:
	return collecting and not is_dying and not deploy_mode and not retrieve_mode and Vector2(velocity.x, velocity.z).length() < 0.5 and get_node("Body").call("arm_ready") and global_position.distance_to(collection_target) < 10.0

func arm_folded() -> bool:
	return get_node("Body").call("is_folded")

func load_cargo(material: String, amount: float) -> float:
	if not cargo.has(material) or is_dying:
		return 0.0
	var accepted := clampf(amount, 0.0, CAPACITY - cargo_total())
	cargo[material] += accepted
	return accepted

func unload_cargo(manager: Node) -> Dictionary:
	var delivered := cargo.duplicate()
	manager.set("corium_units", float(manager.get("corium_units")) + float(cargo.corium))
	manager.set("plasteel_units", float(manager.get("plasteel_units")) + float(cargo.plasteel))
	cargo = {"corium": 0.0, "plasteel": 0.0}
	return delivered

func apply_origin_shift(offset: Vector3) -> void:
	super.apply_origin_shift(offset)
	collection_target -= offset
	collection_parking_position -= offset

func _on_harvester_destroyed(_vehicle: Node3D) -> void:
	collecting = false
	var poi := get_tree().root.get_node_or_null("POIManager")
	if poi != null and cargo_total() > 0.0:
		poi.get_resource_field().add_source("Lost harvester cargo", global_position, "cargo", cargo.duplicate(), true)
	cargo = {"corium": 0.0, "plasteel": 0.0}
