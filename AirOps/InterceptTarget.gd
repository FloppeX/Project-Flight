extends RefCounted

## A tactical intercept keeps a formation identity across materialization and losses.
## Standalone aircraft are treated as a flight of one.
static func is_aircraft_valid(target: Variant) -> bool:
	if not is_instance_valid(target) or not target is RigidBody3D or target.is_queued_for_deletion():
		return false
	if target.is_in_group("ground_vehicles") or not target.has_method("get_team") or target.get_team() != 2:
		return false
	if not (target.is_in_group("aircraft") or target.is_in_group("ai_aircraft") or target.has_node("AIPilot")):
		return false
	for property in ["current_health", "health"]:
		if property in target and typeof(target.get(property)) in [TYPE_INT, TYPE_FLOAT]:
			return float(target.get(property)) > 0.0
	return true


static func members(target: Variant) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not is_instance_valid(target):
		return result
	if target is EnemyVirtualFlight:
		for member in target.active_aircraft:
			if is_aircraft_valid(member):
				result.append(member)
	elif is_aircraft_valid(target):
		result.append(target)
	return result


static func is_valid(target: Variant) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	if target is EnemyVirtualFlight:
		if target.aircraft_count <= 0 or target.mission == EnemyVirtualFlight.Mission.LANDED:
			return false
		return target.vstate != EnemyVirtualFlight.VState.ACTIVE or not members(target).is_empty()
	return is_aircraft_valid(target)


static func position(target: Variant) -> Vector3:
	if not is_valid(target):
		return Vector3.INF
	var aircraft := members(target)
	if aircraft.is_empty():
		return target.position
	var center := Vector3.ZERO
	for member in aircraft:
		center += member.global_position
	return center / aircraft.size()


static func label(target: Variant) -> String:
	if not is_valid(target):
		return "NO TARGET"
	return target.flight_name if target is EnemyVirtualFlight else str(target.name)
