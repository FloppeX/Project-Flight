class_name AirTask
extends RefCounted

## High-level intent issued by AirOps or a scenario to a pilot.
##
## An AirTask deliberately does not contain waypoints or control inputs. The pilot's
## tactical planner turns this intent into one or more FlightPlans, while the shared
## path follower remains agnostic about why those paths were requested.

enum Kind {
	NONE,
	PATROL,
	ATTACK_TARGET,
	INTERCEPT_TARGET,
	RETURN_TO_BASE,
	RECOVER,
}

var kind: Kind = Kind.NONE
var requested_speed_mps: float = NAN
var requested_altitude_m: float = NAN
var area_center: Vector3 = Vector3.INF
var area_radius_m: float = NAN
var return_point: Vector3 = Vector3.INF
var return_speed_mps: float = NAN
var return_capture_radius_m: float = 300.0
var metadata: Dictionary = {}

var _target_ref: WeakRef = null
var _target_instance_id: int = 0
var _target_name: String = ""


static func patrol(
	center: Vector3 = Vector3.INF,
	radius_m: float = NAN,
	altitude_m: float = NAN
) -> AirTask:
	var task := AirTask.new()
	task.kind = Kind.PATROL
	task.area_center = center
	task.area_radius_m = radius_m
	task.requested_altitude_m = altitude_m
	return task


static func attack_target(target: Node3D) -> AirTask:
	return _target_task(Kind.ATTACK_TARGET, target)


static func attack_target_and_return(
	target: Node3D,
	recovery_point: Vector3,
	recovery_speed_mps: float = NAN,
	recovery_capture_radius_m: float = 300.0
) -> AirTask:
	## Composite mission intent: the tactical planner owns the attack corridor, then
	## produces a separate terrain-aware FlightPlan back to the recovery point once
	## a weapon has actually been released and the attack egress is complete.
	var task := _target_task(Kind.ATTACK_TARGET, target)
	task.return_point = recovery_point
	task.return_speed_mps = recovery_speed_mps
	task.return_capture_radius_m = maxf(recovery_capture_radius_m, 1.0)
	task.metadata = {"return_after_attack": true, "phase": "attack"}
	return task


static func intercept_target(target: Node3D) -> AirTask:
	return _target_task(Kind.INTERCEPT_TARGET, target)


static func return_to_base() -> AirTask:
	var task := AirTask.new()
	task.kind = Kind.RETURN_TO_BASE
	return task


static func recover() -> AirTask:
	var task := AirTask.new()
	task.kind = Kind.RECOVER
	return task


static func _target_task(task_kind: Kind, target: Node3D) -> AirTask:
	var task := AirTask.new()
	task.kind = task_kind
	task.set_target(target)
	return task


func set_target(target: Node3D) -> void:
	_target_ref = weakref(target) if target != null and is_instance_valid(target) else null
	_target_instance_id = target.get_instance_id() \
		if target != null and is_instance_valid(target) else 0
	_target_name = String(target.name) \
		if target != null and is_instance_valid(target) else ""


func get_target() -> Node3D:
	if _target_ref == null:
		return null
	var target: Variant = _target_ref.get_ref()
	return target as Node3D if target is Node3D and is_instance_valid(target) else null


func get_target_instance_id() -> int:
	return _target_instance_id


func get_target_name() -> String:
	return _target_name


func requires_live_target() -> bool:
	return kind in [Kind.ATTACK_TARGET, Kind.INTERCEPT_TARGET]


func is_actionable() -> bool:
	return kind != Kind.NONE and (not requires_live_target() or get_target() != null)


func has_return_point() -> bool:
	return return_point != Vector3.INF \
		and is_finite(return_point.x) \
		and is_finite(return_point.y) \
		and is_finite(return_point.z)


func describe() -> String:
	var kind_name: String = Kind.keys()[kind] if kind >= 0 and kind < Kind.size() else "UNKNOWN"
	if requires_live_target():
		return "%s target=%s" % [kind_name, _target_name if not _target_name.is_empty() else "invalid"]
	return kind_name
