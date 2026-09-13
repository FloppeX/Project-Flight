extends Node
## Carrier-local rescue coordinator. Uses the same navigation graph as platoons;
## route requests are asynchronous and cached, never repeated every physics tick.

const PICKUP_RANGE_M := 40.0
const STALL_TIMEOUT_S := 120.0
var jobs: Dictionary = {} # pilot -> route planning / assigned platoon
var retry_after: Dictionary = {}
var returning: Dictionary = {} # platoon name -> platoon waiting for a free bay
var ops: Node
var _tick_s := 0.0
var _serial := 0

func _ready() -> void:
	ops = get_parent()
	add_to_group("origin_shifter")

func apply_origin_shift(offset: Vector3) -> void:
	for job: Dictionary in jobs.values():
		job.start -= offset
		job.goal -= offset

func consider(pilot: Node3D, helicopter: Node3D) -> bool:
	if jobs.has(pilot):
		return true
	if not NavGraph.is_ready():
		return false
	var best: GroundVehiclePlatoon = null
	var best_cost := INF
	for pname in ops.get_platoon_names():
		var p: GroundVehiclePlatoon = ops.get_platoon(pname)
		if not is_instance_valid(p) or p.objective_type != GroundVehiclePlatoon.ObjectiveType.NONE:
			continue # Never steal explicit movement, escort, or combat orders.
		if not _eligible(p):
			continue
		var retry_key := "%d:%s" % [pilot.get_instance_id(), p.platoon_id]
		if float(retry_after.get(retry_key, 0.0)) > Time.get_ticks_msec() / 1000.0:
			continue # A failed route for one platoon must not exclude every other one.
		var cost := _origin(p).distance_to(pilot.global_position) / 15.0
		if not p.has_members(): cost += 90.0
		if cost < best_cost:
			best = p
			best_cost = cost
	if best == null:
		return false
	var air_eta := 180.0
	ops._refresh_carrier()
	if is_instance_valid(helicopter):
		air_eta = helicopter.global_position.distance_to(pilot.global_position) / 50.0 + 60.0
	elif is_instance_valid(ops._carrier):
		air_eta += ops._carrier.global_position.distance_to(pilot.global_position) / 50.0
	if not is_instance_valid(helicopter):
		var deck := get_tree().get_first_node_in_group("flight_deck_manager")
		if deck == null or not deck.has_method("can_queue_ai_helicopters") \
				or not deck.can_queue_ai_helicopters(AirOpsManager.rescue_helicopter_model):
			air_eta = INF # Do not prefer a hypothetical helicopter that cannot launch.
	if best_cost > air_eta * 1.25:
		return false
	return assign(best, pilot, false, air_eta)

func _eligible(p: GroundVehiclePlatoon) -> bool:
	if p.has_any_member_in_combat(): return false
	for member in p.get_members():
		if member.has_method("can_accept_passenger") and member.can_accept_passenger(): return true
	if p.has_members(): return false
	ops._refresh_vehicle_bay()
	return is_instance_valid(ops._vehicle_bay) and ops._vehicle_bay.stored_vehicles > 0 \
		and not ops._deploy_queue.has(p.platoon_id) and ops._deploying_platoon_name != p.platoon_id

func _origin(p: GroundVehiclePlatoon) -> Vector3:
	if p.has_members(): return p.get_center_position()
	ops._refresh_carrier()
	return ops._carrier.global_position if is_instance_valid(ops._carrier) else Vector3.INF

func assign(p: GroundVehiclePlatoon, pilot: Node3D, manual: bool = true, air_eta: float = INF) -> bool:
	if not is_instance_valid(pilot) or pilot.is_queued_for_deletion() or not pilot.has_method("approach_ground_transport"):
		return false
	if jobs.has(pilot): return jobs[pilot].platoon == p
	if not _eligible(p) or not NavGraph.is_ready(): return false
	# One pickup objective per platoon: do not overwrite another survivor's route.
	for existing: Dictionary in jobs.values():
		if existing.platoon == p: return false
	# An explicit rescue order may replace this platoon's old order, but do not
	# silently interrupt an already committed helicopter rescue.
	if is_instance_valid(AirOpsManager._get_valid_rescue_helicopter(pilot)) \
		or AirOpsManager._pending_rescue_launch_pilot == pilot:
		return false
	var start := _origin(p)
	var goal := pilot.global_position
	if not NavGraph.can_anchor(start, p.contact_path_clearance_m, p.contact_anchor_distance_m) \
		or not NavGraph.can_anchor(goal, p.contact_path_clearance_m, p.contact_anchor_distance_m):
		return false
	p.set_rescue_objective(start) # Hold while the route is checked.
	_serial += 1
	var serial := _serial
	jobs[pilot] = {"platoon": p, "planning": true, "age": 0.0, "stalled": 0.0,
		"best_distance": INF, "goal": goal, "start": start, "manual": manual, "air_eta": air_eta, "serial": serial}
	pilot.set_meta("air_ops_rescue_status", "ground_route_check")
	NavGraph.find_path_async(start, goal, p.contact_path_clearance_m,
		_on_route_received.bind(weakref(pilot), serial))
	return true

func _on_route_received(path: Array, pilot_ref: WeakRef, serial: int) -> void:
	_route_ready(pilot_ref.get_ref(), path, serial)

func _route_ready(pilot: Variant, path: Array, serial: int) -> void:
	if not is_instance_valid(pilot) or not jobs.has(pilot): return
	var job: Dictionary = jobs[pilot]
	if job.serial != serial: return
	var p: Variant = job.platoon
	if not is_instance_valid(p) or p.objective_type != GroundVehiclePlatoon.ObjectiveType.RESCUE:
		_cancel(pilot, "order changed")
		return
	if path.is_empty() or pilot.global_position.distance_to(job.goal) > 30.0:
		_cancel(pilot, "route unavailable or survivor moved")
		return
	var endpoint: Vector3 = path.back()
	# Graph paths end at a snapped node, NOT necessarily at the requested pilot.
	# Reject distant/wrong-level endpoints and verify the final walk to boarding.
	if endpoint.distance_to(pilot.global_position) > p.contact_anchor_distance_m \
		or not walk_is_clear(endpoint, pilot.global_position):
		_cancel(pilot, "route does not reach survivor")
		return
	path.append(pilot.global_position)
	endpoint = pilot.global_position
	var length_m := 0.0
	var cursor: Vector3 = job.start
	for point: Vector3 in path:
		length_m += cursor.distance_to(point)
		cursor = point
	var eta := length_m / 15.0 + 25.0 + (0.0 if p.has_members() else 90.0)
	var threat_penalty := _known_route_risk(path)
	if not job.manual and (threat_penalty >= 300.0 or eta + threat_penalty > float(job.air_eta) * 1.25):
		_cancel(pilot, "helicopter preferred on time/threat cost")
		return
	job.planning = false
	job.goal = endpoint
	jobs[pilot] = job
	p.set_rescue_objective(endpoint)
	pilot.set_meta("air_ops_rescue_status", "ground_assigned")
	pilot.set_meta("ground_rescue_platoon", p.platoon_id)
	pilot.prepare_for_ground_rescue()
	ops._ensure_platoon_deployed(p.platoon_id, p)
	print("[GroundRescue] assigned platoon=%s eta_s=%.0f route_m=%.0f risk=%.0f" % [p.platoon_id, eta, length_m, threat_penalty])

func _known_route_risk(path: Array) -> float:
	var penalty := 0.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node3D or not AirOpsManager.is_contact_detected(enemy): continue
		for index in range(1, path.size()):
			var nearest := Geometry3D.get_closest_point_to_segment(enemy.global_position, path[index - 1], path[index])
			if nearest.distance_to(enemy.global_position) < 500.0:
				penalty += 180.0
				break
	return penalty

static func walk_is_clear(from: Vector3, to: Vector3) -> bool:
	if not TerrainNavGrid.is_ready(): return false
	if absf(from.y - to.y) > 8.0: return false
	var steps := maxi(1, ceili(from.distance_to(to) / 2.0))
	var previous_y := TerrainNavGrid.sample_height(from.x, from.z)
	if previous_y <= -9000.0: return false
	for index in range(1, steps + 1):
		var point := from.lerp(to, float(index) / steps)
		var height := TerrainNavGrid.sample_height(point.x, point.z)
		if height <= -9000.0 or absf(height - previous_y) > 1.5: return false
		previous_y = height
	return true

func _process(delta: float) -> void:
	if jobs.is_empty() and returning.is_empty(): return
	_tick_s += delta
	if _tick_s < 0.5: return
	delta = _tick_s
	_tick_s = 0.0
	_update_returns()
	for pilot: Variant in jobs.keys():
		if not is_instance_valid(pilot) or pilot.is_queued_for_deletion():
			_cancel(pilot, "survivor removed")
			continue
		var job: Dictionary = jobs[pilot]
		var p: Variant = job.platoon
		if not is_instance_valid(p) or p.objective_type != GroundVehiclePlatoon.ObjectiveType.RESCUE:
			_cancel(pilot, "order changed")
			continue
		job.age += delta
		if job.planning:
			if job.age > 10.0: _cancel(pilot, "route check timeout")
			continue
		var best_vehicle: Node3D = null
		var distance := INF
		for member in p.get_members():
			if member.has_method("set_rescue_driving"): member.set_rescue_driving(true)
			if not member.has_method("can_accept_passenger") or not member.can_accept_passenger(): continue
			var d: float = member.global_position.distance_to(pilot.global_position)
			if d < distance:
				distance = d
				best_vehicle = member
		if distance < float(job.best_distance) - 3.0:
			job.best_distance = distance
			job.stalled = 0.0
		else: job.stalled += delta
		if job.stalled > STALL_TIMEOUT_S or job.age > 600.0:
			_cancel(pilot, "no pickup progress")
			continue
		if best_vehicle != null and distance <= PICKUP_RANGE_M:
			pilot.approach_ground_transport(best_vehicle)

func complete(pilot: Node3D) -> void:
	if not jobs.has(pilot): return
	var p: Variant = jobs[pilot].platoon
	jobs.erase(pilot)
	if is_instance_valid(p):
		_restore_driving(p)
		returning[p.platoon_id] = p
		ops.order_rtb(p.platoon_id)
		_update_returns()

func _update_returns() -> void:
	if returning.is_empty(): return
	ops._refresh_vehicle_bay()
	for pname: String in returning.keys():
		var p: Variant = returning[pname]
		if not is_instance_valid(p) or not p.has_members() or p.get_passenger_count() == 0:
			returning.erase(pname)
			continue
		if p.objective_type != GroundVehiclePlatoon.ObjectiveType.RETURN_TO_BASE:
			returning.erase(pname) # Explicit replacement order takes priority.
			continue
		if not is_instance_valid(ops._vehicle_bay) or not ops._vehicle_bay.can_retrieve_vehicles(): continue
		var ready := true
		for member in p.get_members():
			if bool(member.get("deploy_mode")) or bool(member.get("retrieve_mode")): ready = false
		if not ready: continue
		ops.retrieve(pname)
		returning.erase(pname)

func _cancel(pilot: Variant, reason: String) -> void:
	if not jobs.has(pilot): return
	var p: Variant = jobs[pilot].platoon
	jobs.erase(pilot)
	if is_instance_valid(pilot):
		if is_instance_valid(p):
			var retry_key := "%d:%s" % [pilot.get_instance_id(), p.platoon_id]
			retry_after[retry_key] = Time.get_ticks_msec() / 1000.0 + 60.0
		pilot.set_meta("air_ops_rescue_status", "waiting")
		pilot.remove_meta("ground_rescue_platoon")
		pilot.cancel_ground_transport()
	if is_instance_valid(p) and p.objective_type == GroundVehiclePlatoon.ObjectiveType.RESCUE:
		_restore_driving(p)
		ops.order_hold(p.platoon_id)
	elif is_instance_valid(p):
		_restore_driving(p)
	print("[GroundRescue] released: %s" % reason)

func _restore_driving(p: GroundVehiclePlatoon) -> void:
	for member in p.get_members():
		if member.has_method("set_rescue_driving"): member.set_rescue_driving(false)
