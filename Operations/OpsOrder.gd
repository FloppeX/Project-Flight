class_name OpsOrder
extends RefCounted

## Domain-neutral mission intent.  Operations managers issue these orders; the
## receiving adapter translates them into fixed-wing, helicopter, or platoon APIs.
## Orders deliberately contain no control inputs or vehicle-specific state names.

enum Kind {
	NONE,
	TRANSIT_TO_POSITION,
	PATROL_POSITION,
	INTERCEPT_TARGET,
	ATTACK_TARGET,
	ATTACK_POSITION,
	PROTECT_TARGET,
	ESCORT_CARRIER,
	RESCUE_TARGET,
	HOLD_POSITION,
	RETURN_TO_BASE,
	RECOVER,
}

var kind: Kind = Kind.NONE
var position: Vector3 = Vector3.INF
var target: Node3D = null
var radius_m: float = NAN
var altitude_m: float = NAN
var speed_mps: float = NAN
var priority: int = 0
var metadata: Dictionary = {}


static func transit_to_position(
	destination: Vector3,
	requested_speed_mps: float = NAN,
	requested_altitude_m: float = NAN,
	capture_radius_m: float = 250.0
) -> OpsOrder:
	var order := OpsOrder.new()
	order.kind = Kind.TRANSIT_TO_POSITION
	order.position = destination
	order.speed_mps = requested_speed_mps
	order.altitude_m = requested_altitude_m
	order.radius_m = maxf(capture_radius_m, 1.0)
	return order


static func patrol_position(
	center: Vector3,
	radius_m: float = 1000.0,
	requested_altitude_m: float = NAN
) -> OpsOrder:
	var order := OpsOrder.new()
	order.kind = Kind.PATROL_POSITION
	order.position = center
	order.radius_m = maxf(radius_m, 1.0)
	order.altitude_m = requested_altitude_m
	return order


static func attack_target(target_node: Node3D, radius_m: float = 300.0) -> OpsOrder:
	var order := OpsOrder.new()
	order.kind = Kind.ATTACK_TARGET
	order.target = target_node
	order.radius_m = maxf(radius_m, 1.0)
	return order


static func intercept_target(target_node: Node3D) -> OpsOrder:
	var order := OpsOrder.new()
	order.kind = Kind.INTERCEPT_TARGET
	order.target = target_node
	return order


static func attack_position(target_position: Vector3, radius_m: float = 300.0) -> OpsOrder:
	var order := OpsOrder.new()
	order.kind = Kind.ATTACK_POSITION
	order.position = target_position
	order.radius_m = maxf(radius_m, 1.0)
	return order


static func protect_target(target_node: Node3D, radius_m: float = 250.0) -> OpsOrder:
	var order := OpsOrder.new()
	order.kind = Kind.PROTECT_TARGET
	order.target = target_node
	order.radius_m = maxf(radius_m, 1.0)
	return order


static func escort_carrier(distance_m: float = 100.0) -> OpsOrder:
	var order := OpsOrder.new()
	order.kind = Kind.ESCORT_CARRIER
	order.radius_m = maxf(distance_m, 1.0)
	return order


static func rescue_target(target_node: Node3D) -> OpsOrder:
	var order := OpsOrder.new()
	order.kind = Kind.RESCUE_TARGET
	order.target = target_node
	return order


static func hold_position(hold_at: Vector3 = Vector3.INF) -> OpsOrder:
	var order := OpsOrder.new()
	order.kind = Kind.HOLD_POSITION
	order.position = hold_at
	return order


static func return_to_base() -> OpsOrder:
	var order := OpsOrder.new()
	order.kind = Kind.RETURN_TO_BASE
	return order


static func recover() -> OpsOrder:
	var order := OpsOrder.new()
	order.kind = Kind.RECOVER
	return order


func is_actionable() -> bool:
	if kind == Kind.NONE:
		return false
	if kind in [Kind.INTERCEPT_TARGET, Kind.ATTACK_TARGET, Kind.PROTECT_TARGET, Kind.RESCUE_TARGET]:
		return target != null and is_instance_valid(target)
	if kind in [Kind.TRANSIT_TO_POSITION, Kind.PATROL_POSITION, Kind.ATTACK_POSITION]:
		return _is_finite_position(position)
	return true


func get_goal_position(carrier: Node3D = null) -> Vector3:
	if target != null and is_instance_valid(target):
		return target.global_position
	if _is_finite_position(position):
		return position
	if kind in [Kind.ESCORT_CARRIER, Kind.RETURN_TO_BASE, Kind.RECOVER] \
			and carrier != null and is_instance_valid(carrier):
		return carrier.global_position
	return Vector3.INF


func describe() -> String:
	var kind_name: String = str(Kind.keys()[kind]) \
			if kind >= 0 and kind < Kind.size() else "UNKNOWN"
	if target != null and is_instance_valid(target):
		return "%s target=%s" % [kind_name, target.name]
	if _is_finite_position(position):
		return "%s position=%s" % [kind_name, str(position.snapped(Vector3.ONE))]
	return kind_name


static func _is_finite_position(value: Vector3) -> bool:
	return value != Vector3.INF \
			and is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
