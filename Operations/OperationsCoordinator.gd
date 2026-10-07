extends Node

## Shared command/status boundary above AirOps and GroundOps.  It supervises
## semantic progress only; vehicle controllers remain solely responsible for
## control surfaces, cyclic/collective, steering, pathfinding, and formations.

signal order_accepted(unit: Node, order: OpsOrder)
signal order_rejected(unit: Node, order: OpsOrder, reason: String)
signal order_completed(unit: Node, order: OpsOrder)
signal order_ended(unit: Node, order: OpsOrder, reason: String)
signal unit_stalled(unit: Node, order: OpsOrder, stalled_for_s: float)
signal ground_retrieval_started(unit: Node)

@export var supervision_interval_s: float = 1.0
@export var stalled_report_after_s: float = 90.0
@export var meaningful_progress_m: float = 25.0
@export var ground_retrieval_radius_m: float = 130.0
@export var patrol_capture_radius_m: float = 650.0
@export var patrol_reissue_after_s: float = 75.0
@export var patrol_leash_multiplier: float = 2.2

var _assignments: Dictionary = {}
var _supervision_elapsed_s: float = 0.0
var _simulation_elapsed_s: float = 0.0


func _ready() -> void:
	add_to_group("origin_shifter")


func reset_runtime_state() -> void:
	_assignments.clear()
	_supervision_elapsed_s = 0.0
	_simulation_elapsed_s = 0.0


func apply_origin_shift(offset: Vector3) -> void:
	## OpsOrders are RefCounted intent objects, not Node3Ds, so FloatingOrigin
	## cannot move their stored world positions automatically.
	for id_variant in _assignments.keys():
		var assignment: Dictionary = _assignments[id_variant]
		var order: OpsOrder = assignment.get("order", null)
		if order != null and OpsOrder._is_finite_position(order.position):
			order.position -= offset
		_assignments[id_variant] = assignment


func issue_order(unit: Node, order: OpsOrder) -> bool:
	if unit == null or not is_instance_valid(unit) or order == null:
		order_rejected.emit(unit, order, "invalid unit or order")
		return false
	var adapter := OpsUnitAdapter.create(unit)
	if not adapter.is_valid():
		order_rejected.emit(unit, order, "unsupported unit")
		return false
	if not adapter.accepts(order):
		order_rejected.emit(unit, order, "capability mismatch")
		return false
	if adapter.domain == OpsUnitAdapter.Domain.FIXED_WING and order.kind not in [OpsOrder.Kind.RETURN_TO_BASE, OpsOrder.Kind.RECOVER]:
		var readiness: Dictionary = preload("res://Operations/OperationalReadiness.gd").aircraft_status(adapter.unit)
		if readiness.recovering or readiness.departing or readiness.player_controlled:
			order_rejected.emit(unit, order, "protected flight phase")
			return false
	if not adapter.accept_order(order):
		order_rejected.emit(unit, order, "controller rejected order")
		return false
	track_accepted_order(adapter.unit, order)
	return true


func track_accepted_order(unit: Node, order: OpsOrder) -> void:
	## Domain managers call this after accepting an order through their own APIs.
	## It records intent without dispatching a second command to the vehicle.
	if not is_instance_valid(unit) or order == null:
		return
	var adapter := OpsUnitAdapter.create(unit)
	if not adapter.is_valid():
		return
	if _assignments.has(unit.get_instance_id()):
		var previous: Dictionary = _assignments[unit.get_instance_id()]
		order_ended.emit(unit, previous.order, "superseded")
	var now_s := _simulation_elapsed_s
	var status := adapter.get_status()
	if unit is GroundVehiclePlatoon:
		unit.set_meta("ops_order_source", str(order.metadata.get("source", "external")))
		unit.set_meta("ops_order_phase", "ACTIVE" if unit.has_members() else "PENDING DEPLOYMENT")
	var patrol_leg_index := 0
	var goal := _get_patrol_leg_position(order, patrol_leg_index) \
			if order.kind == OpsOrder.Kind.PATROL_POSITION \
			else order.get_goal_position(_get_carrier())
	_assignments[unit.get_instance_id()] = {
		"unit_ref": weakref(unit),
		"adapter": adapter,
		"order": order,
		"accepted_s": now_s,
		"last_progress_s": now_s,
		"last_distance_m": _distance_to_goal(status.get("position", Vector3.ZERO), goal),
		"stall_reported": false,
		"ground_retrieval_started": bool(order.metadata.get("retrieval_started", false)),
		"patrol_leg_index": patrol_leg_index,
		"patrol_corrections": 0,
		"patrol_last_command_s": now_s,
		"objective_type": int(unit.get("objective_type")) if unit is GroundVehiclePlatoon else -1,
		"had_members": unit.has_members() if unit is GroundVehiclePlatoon else true,
	}
	order_accepted.emit(unit, order)


func get_unit_status(unit: Node) -> Dictionary:
	if is_instance_valid(unit) and (unit is AIPilot or unit is HelicopterPilot):
		unit = OpsUnitAdapter.create(unit).unit
	if unit == null or not is_instance_valid(unit):
		return {"valid": false}
	var assignment: Dictionary = _assignments.get(unit.get_instance_id(), {})
	if not assignment.is_empty():
		var assigned_adapter: Variant = assignment.get("adapter", null)
		if assigned_adapter is OpsUnitAdapter:
			var status := (assigned_adapter as OpsUnitAdapter).get_status()
			var order: OpsOrder = assignment.get("order", null)
			status["order"] = order
			status["order_name"] = order.describe() if order != null else "NONE"
			status["order_source"] = str(order.metadata.get("source", "external")) if order != null else "automatic"
			status["order_stalled"] = bool(assignment.get("stall_reported", false))
			return status
	return OpsUnitAdapter.create(unit).get_status()


func get_all_statuses() -> Array[Dictionary]:
	var statuses: Array[Dictionary] = []
	for id_variant in _assignments.keys():
		var assignment: Dictionary = _assignments[id_variant]
		var unit_ref: WeakRef = assignment.get("unit_ref", null)
		var unit: Variant = unit_ref.get_ref() if unit_ref != null else null
		if unit is Node and is_instance_valid(unit):
			statuses.append(get_unit_status(unit))
	var air_ops := get_node_or_null("/root/AirOpsManager")
	if air_ops != null:
		for fname in air_ops.get_flight_names():
			statuses.append(air_ops.get_flight_status(fname))
	var ground_ops := get_node_or_null("/root/GroundOpsManager")
	if ground_ops != null:
		for pname in ground_ops.get_platoon_names():
			var platoon: Variant = ground_ops.get_platoon(pname)
			if is_instance_valid(platoon) and not _assignments.has(platoon.get_instance_id()):
				statuses.append(ground_ops.get_platoon_status(pname))
	return statuses


func has_individual_order(aircraft: Node) -> bool:
	return is_instance_valid(aircraft) and _assignments.has(aircraft.get_instance_id())


func clear_order(unit: Node, reason: String = "cancelled") -> void:
	if is_instance_valid(unit) and (unit is AIPilot or unit is HelicopterPilot):
		unit = OpsUnitAdapter.create(unit).unit
	if unit != null and is_instance_valid(unit):
		var previous: Dictionary = _assignments.get(unit.get_instance_id(), {})
		_assignments.erase(unit.get_instance_id())
		if not previous.is_empty():
			order_ended.emit(unit, previous.order, reason)


func _process(delta: float) -> void:
	_simulation_elapsed_s += delta
	_supervision_elapsed_s += delta
	if _supervision_elapsed_s < maxf(supervision_interval_s, 0.1):
		return
	_supervision_elapsed_s = 0.0
	_supervise_assignments()


func _supervise_assignments() -> void:
	var now_s := _simulation_elapsed_s
	var completed_ids: Array[int] = []
	for id_variant in _assignments.keys():
		var id := int(id_variant)
		var assignment: Dictionary = _assignments[id]
		var unit_ref: WeakRef = assignment.get("unit_ref", null)
		var unit_variant: Variant = unit_ref.get_ref() if unit_ref != null else null
		if not (unit_variant is Node) or not is_instance_valid(unit_variant):
			completed_ids.append(id)
			continue
		var unit := unit_variant as Node
		var adapter: OpsUnitAdapter = assignment.get("adapter", null)
		var order: OpsOrder = assignment.get("order", null)
		if adapter == null or order == null or not adapter.is_valid():
			completed_ids.append(id)
			continue
		var status := adapter.get_status()
		if unit is GroundVehiclePlatoon:
			if int(unit.objective_type) != int(assignment.get("objective_type", -1)):
				order_ended.emit(unit, order, "objective changed")
				completed_ids.append(id)
				continue
			if unit.has_members():
				assignment["had_members"] = true
				unit.set_meta("ops_order_phase", "ACTIVE")
			elif not bool(assignment.get("had_members", false)):
				# Deployment is queued or waiting for a vehicle bay; no progress yet.
				assignment["last_progress_s"] = now_s
				_assignments[id] = assignment
				continue
		if order.kind in [OpsOrder.Kind.ATTACK_TARGET, OpsOrder.Kind.INTERCEPT_TARGET]:
			var target: Variant = order.target
			if not is_instance_valid(target) or target.is_queued_for_deletion() or bool(target.get_meta("destroyed", false)) \
					or ("current_health" in target and float(target.current_health) <= 0.0):
				if unit is GroundVehiclePlatoon: unit.set_meta("ops_order_phase", "COMPLETED")
				order_completed.emit(unit, order)
				completed_ids.append(id)
				continue
		if adapter.domain == OpsUnitAdapter.Domain.FIXED_WING \
				and int(status.get("state", -1)) in preload("res://Operations/OperationalReadiness.gd").RECOVERY_STATES \
				and order.kind not in [OpsOrder.Kind.RETURN_TO_BASE, OpsOrder.Kind.RECOVER]:
			order_ended.emit(unit, order, "returning for recovery")
			completed_ids.append(id)
			continue
		if bool(status.get("recovered", false)) and order.kind in [OpsOrder.Kind.RETURN_TO_BASE, OpsOrder.Kind.RECOVER]:
			if unit is GroundVehiclePlatoon: unit.set_meta("ops_order_phase", "COMPLETED")
			order_completed.emit(unit, order)
			completed_ids.append(id)
			continue
		var carrier := _get_carrier()
		var patrol_leg_index := int(assignment.get("patrol_leg_index", 0))
		var goal := _get_patrol_leg_position(order, patrol_leg_index) \
				if order.kind == OpsOrder.Kind.PATROL_POSITION \
				else order.get_goal_position(carrier)
		var position: Vector3 = status.get("position", Vector3.ZERO)
		if unit is GroundVehiclePlatoon and (order.kind == OpsOrder.Kind.ESCORT_HARVESTER \
				or (order.kind == OpsOrder.Kind.RECOVER and unit.objective_type == GroundVehiclePlatoon.ObjectiveType.RETURN_TO_BASE)):
			goal = unit._get_route_preview_goal()
		var distance_m := _distance_to_goal(position, goal)
		var previous_distance_m := float(assignment.get("last_distance_m", INF))
		if is_finite(distance_m) and (
				not is_finite(previous_distance_m)
				or distance_m <= previous_distance_m - maxf(meaningful_progress_m, 1.0)
		):
			assignment["last_progress_s"] = now_s
			assignment["last_distance_m"] = distance_m
			assignment["stall_reported"] = false
		if order.kind == OpsOrder.Kind.TRANSIT_TO_POSITION \
				and is_finite(distance_m) \
				and distance_m <= (order.radius_m if is_finite(order.radius_m) else 100.0):
			if unit is GroundVehiclePlatoon: unit.set_meta("ops_order_phase", "COMPLETED")
			order_completed.emit(unit, order)
			completed_ids.append(id)
			continue
		if order.kind == OpsOrder.Kind.PATROL_POSITION:
			var center_distance_m := _distance_to_goal(position, order.position)
			var capture_m := maxf(
				patrol_capture_radius_m,
				minf(maxf(order.radius_m, 1.0) * 0.4, 900.0)
			)
			var stalled_s := now_s - float(assignment.get("last_progress_s", now_s))
			var outside_leash := is_finite(center_distance_m) \
					and center_distance_m > maxf(order.radius_m, 1.0) * maxf(patrol_leash_multiplier, 1.1)
			if is_finite(distance_m) and distance_m <= capture_m:
				patrol_leg_index = posmod(patrol_leg_index + 1, 4)
				_reissue_patrol_leg(adapter, order, assignment, patrol_leg_index, now_s, position)
			var since_last_command_s := now_s - float(assignment.get("patrol_last_command_s", now_s))
			var correction_due := since_last_command_s >= maxf(patrol_reissue_after_s, 5.0)
			if correction_due and (outside_leash or stalled_s >= maxf(patrol_reissue_after_s, 5.0)):
				assignment["patrol_corrections"] = int(assignment.get("patrol_corrections", 0)) + 1
				_reissue_patrol_leg(adapter, order, assignment, patrol_leg_index, now_s, position)
			_assignments[id] = assignment
			continue
		if adapter.domain == OpsUnitAdapter.Domain.GROUND_PLATOON \
				and order.kind == OpsOrder.Kind.RECOVER \
				and is_finite(distance_m) \
				and distance_m <= maxf(ground_retrieval_radius_m, 20.0) \
				and not bool(assignment.get("ground_retrieval_started", false)):
			if adapter.try_begin_ground_retrieval():
				assignment["ground_retrieval_started"] = true
				assignment["objective_type"] = int(unit.objective_type)
				ground_retrieval_started.emit(unit)
		var standing := order.kind in [OpsOrder.Kind.HOLD_POSITION, OpsOrder.Kind.PROTECT_POSITION,
			OpsOrder.Kind.PROTECT_TARGET, OpsOrder.Kind.ESCORT_CARRIER, OpsOrder.Kind.ESCORT_HARVESTER, OpsOrder.Kind.PURSUE_ENEMIES]
		if standing and (not is_finite(distance_m) or distance_m <= maxf(order.radius_m if is_finite(order.radius_m) else 100.0, 150.0)):
			assignment["last_progress_s"] = now_s
			assignment["stall_reported"] = false
		var stalled_s := now_s - float(assignment.get("last_progress_s", now_s))
		if not bool(status.get("waiting_for_clearance", false)) \
				and stalled_s >= maxf(stalled_report_after_s, 5.0) \
				and not bool(assignment.get("stall_reported", false)):
			assignment["stall_reported"] = true
			if unit is GroundVehiclePlatoon: unit.set_meta("ops_order_phase", "STALLED")
			unit_stalled.emit(unit, order, stalled_s)
		_assignments[id] = assignment
	for id in completed_ids:
		_assignments.erase(id)


func _get_carrier() -> Node3D:
	return get_tree().get_first_node_in_group("carrier") as Node3D


func _distance_to_goal(position: Vector3, goal: Vector3) -> float:
	if not OpsOrder._is_finite_position(goal):
		return INF
	return Vector2(position.x - goal.x, position.z - goal.z).length()


func _get_patrol_leg_position(order: OpsOrder, leg_index: int) -> Vector3:
	if order == null or order.kind != OpsOrder.Kind.PATROL_POSITION:
		return Vector3.INF
	var offsets: Array[Vector3] = [
		Vector3.FORWARD,
		Vector3.RIGHT,
		Vector3.BACK,
		Vector3.LEFT,
	]
	return order.position + offsets[posmod(leg_index, offsets.size())] * maxf(order.radius_m, 1.0)


func _reissue_patrol_leg(
	adapter: OpsUnitAdapter,
	order: OpsOrder,
	assignment: Dictionary,
	leg_index: int,
	now_s: float,
	position: Vector3
) -> void:
	if not adapter.set_supervised_patrol_leg(order, leg_index):
		return
	var goal := _get_patrol_leg_position(order, leg_index)
	assignment["patrol_leg_index"] = leg_index
	assignment["last_progress_s"] = now_s
	assignment["last_distance_m"] = _distance_to_goal(position, goal)
	assignment["stall_reported"] = false
	assignment["patrol_last_command_s"] = now_s
