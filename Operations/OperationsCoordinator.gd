extends Node

## Shared command/status boundary above AirOps and GroundOps.  It supervises
## semantic progress only; vehicle controllers remain solely responsible for
## control surfaces, cyclic/collective, steering, pathfinding, and formations.

signal order_accepted(unit: Node, order: OpsOrder)
signal order_rejected(unit: Node, order: OpsOrder, reason: String)
signal order_completed(unit: Node, order: OpsOrder)
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
	if not adapter.accept_order(order):
		order_rejected.emit(unit, order, "controller rejected order")
		return false
	var now_s := _simulation_elapsed_s
	var status := adapter.get_status()
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
		"ground_retrieval_started": false,
		"patrol_leg_index": patrol_leg_index,
		"patrol_corrections": 0,
		"patrol_last_command_s": now_s,
	}
	order_accepted.emit(unit, order)
	return true


func get_unit_status(unit: Node) -> Dictionary:
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
	return statuses


func clear_order(unit: Node) -> void:
	if unit != null and is_instance_valid(unit):
		_assignments.erase(unit.get_instance_id())


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
		if bool(status.get("recovered", false)) and order.kind in [OpsOrder.Kind.RETURN_TO_BASE, OpsOrder.Kind.RECOVER]:
			order_completed.emit(unit, order)
			completed_ids.append(id)
			continue
		var carrier := _get_carrier()
		var patrol_leg_index := int(assignment.get("patrol_leg_index", 0))
		var goal := _get_patrol_leg_position(order, patrol_leg_index) \
				if order.kind == OpsOrder.Kind.PATROL_POSITION \
				else order.get_goal_position(carrier)
		var position: Vector3 = status.get("position", Vector3.ZERO)
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
				ground_retrieval_started.emit(unit)
		var stalled_s := now_s - float(assignment.get("last_progress_s", now_s))
		if not bool(status.get("waiting_for_clearance", false)) \
				and stalled_s >= maxf(stalled_report_after_s, 5.0) \
				and not bool(assignment.get("stall_reported", false)):
			assignment["stall_reported"] = true
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
