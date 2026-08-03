class_name OpsUnitAdapter
extends RefCounted

const AirTaskModel: Script = preload("res://AI/AirTask.gd")

enum Domain { UNKNOWN, FIXED_WING, HELICOPTER, GROUND_PLATOON }

var unit: Node = null
var controller: Node = null
var domain: Domain = Domain.UNKNOWN


static func create(subject: Node) -> OpsUnitAdapter:
	var adapter := OpsUnitAdapter.new()
	if subject == null or not is_instance_valid(subject):
		return adapter
	if subject is GroundVehiclePlatoon:
		adapter.unit = subject
		adapter.controller = subject
		adapter.domain = Domain.GROUND_PLATOON
		return adapter
	if subject is AIPilot:
		adapter.controller = subject
		adapter.unit = subject.get("aircraft") as Node
		adapter.domain = Domain.FIXED_WING
		return adapter
	if subject is HelicopterPilot:
		adapter.controller = subject
		adapter.unit = subject.get("aircraft") as Node
		adapter.domain = Domain.HELICOPTER
		return adapter
	var heli_pilot := subject.find_child("HelicopterPilot", true, false)
	if heli_pilot != null:
		adapter.unit = subject
		adapter.controller = heli_pilot
		adapter.domain = Domain.HELICOPTER
		return adapter
	var fixed_wing_pilot := subject.find_child("AIPilot", true, false)
	if fixed_wing_pilot != null:
		adapter.unit = subject
		adapter.controller = fixed_wing_pilot
		adapter.domain = Domain.FIXED_WING
	return adapter


func is_valid() -> bool:
	return domain != Domain.UNKNOWN \
			and unit != null and is_instance_valid(unit) \
			and controller != null and is_instance_valid(controller)


func get_capabilities() -> PackedStringArray:
	match domain:
		Domain.FIXED_WING:
			return PackedStringArray(["transit", "patrol", "attack", "intercept", "recover"])
		Domain.HELICOPTER:
			return PackedStringArray(["transit", "ground_attack", "hover", "terrain_land", "rescue", "recover"])
		Domain.GROUND_PLATOON:
			return PackedStringArray(["transit", "attack", "protect", "escort", "recover"])
	return PackedStringArray()


func accepts(order: OpsOrder) -> bool:
	if not is_valid() or order == null or not order.is_actionable():
		return false
	match domain:
		Domain.FIXED_WING:
			return order.kind in [
				OpsOrder.Kind.TRANSIT_TO_POSITION,
				OpsOrder.Kind.PATROL_POSITION,
				OpsOrder.Kind.INTERCEPT_TARGET,
				OpsOrder.Kind.ATTACK_TARGET,
				OpsOrder.Kind.RETURN_TO_BASE,
				OpsOrder.Kind.RECOVER,
			]
		Domain.HELICOPTER:
			return order.kind in [
				OpsOrder.Kind.TRANSIT_TO_POSITION,
				OpsOrder.Kind.ATTACK_TARGET,
				OpsOrder.Kind.RESCUE_TARGET,
				OpsOrder.Kind.HOLD_POSITION,
				OpsOrder.Kind.RETURN_TO_BASE,
				OpsOrder.Kind.RECOVER,
			]
		Domain.GROUND_PLATOON:
			return order.kind in [
				OpsOrder.Kind.TRANSIT_TO_POSITION,
				OpsOrder.Kind.ATTACK_TARGET,
				OpsOrder.Kind.ATTACK_POSITION,
				OpsOrder.Kind.PROTECT_TARGET,
				OpsOrder.Kind.ESCORT_CARRIER,
				OpsOrder.Kind.HOLD_POSITION,
				OpsOrder.Kind.RETURN_TO_BASE,
				OpsOrder.Kind.RECOVER,
			]
	return false


func accept_order(order: OpsOrder) -> bool:
	if not accepts(order):
		return false
	match domain:
		Domain.FIXED_WING:
			return _accept_fixed_wing_order(order)
		Domain.HELICOPTER:
			return _accept_helicopter_order(order)
		Domain.GROUND_PLATOON:
			return _accept_ground_order(order)
	return false


func set_supervised_patrol_leg(order: OpsOrder, leg_index: int) -> bool:
	## AirOps owns patrol containment and advances these semantic legs. The pilot
	## still owns all flight-path and control-surface behavior for each leg.
	if domain != Domain.FIXED_WING or not is_valid() \
			or order == null or order.kind != OpsOrder.Kind.PATROL_POSITION:
		return false
	var patrol_task: Variant = AirTaskModel.patrol(order.position, order.radius_m, order.altitude_m)
	patrol_task.requested_speed_mps = order.speed_mps
	patrol_task.metadata = order.metadata.duplicate(true)
	if not bool(controller.call("assign_air_task", patrol_task)):
		return false
	var patrol_radius := maxf(order.radius_m if is_finite(order.radius_m) else 1200.0, 400.0)
	var offsets: Array[Vector3] = [
		Vector3.FORWARD,
		Vector3.RIGHT,
		Vector3.BACK,
		Vector3.LEFT,
	]
	var destination: Vector3 = order.position + offsets[posmod(leg_index, offsets.size())] * patrol_radius
	if controller.has_method("build_terrain_safe_waypoints"):
		var requested_points: Array[Vector3] = [destination]
		var safe_points: Variant = controller.call(
			"build_terrain_safe_waypoints",
			requested_points,
			maxf(float(order.metadata.get("minimum_agl_m", 260.0)), 50.0),
			false,
			false
		)
		if safe_points is Array and not safe_points.is_empty() and safe_points[0] is Vector3:
			destination = safe_points[0]
	var patrol_speed := order.speed_mps if is_finite(order.speed_mps) else -1.0
	controller.call("set_flight_plan_legs", "ops_patrol_leg", [{
		"position": destination,
		"role": "ops_patrol",
		"speed_mps": patrol_speed,
		"capture_radius_m": 400.0,
	}], false, false)
	controller.set("nav_waypoint", destination)
	controller.call("change_state", AIPilot.State.TRANSIT)
	return true


func get_status() -> Dictionary:
	if not is_valid():
		return {"valid": false, "domain": Domain.UNKNOWN}
	var status := {
		"valid": true,
		"unit": unit,
		"unit_id": unit.get_instance_id(),
		"name": unit.name,
		"domain": domain,
		"domain_name": Domain.keys()[domain],
		"position": _get_unit_position(),
		"waiting_for_clearance": false,
		"recovered": false,
	}
	match domain:
		Domain.FIXED_WING:
			var fixed_state := int(controller.get("current_state"))
			status["state"] = fixed_state
			status["state_name"] = AIPilot.State.keys()[fixed_state] \
					if fixed_state >= 0 and fixed_state < AIPilot.State.size() else "UNKNOWN"
			status["waiting_for_clearance"] = fixed_state == AIPilot.State.RECOVERY_HOLD
			status["recovered"] = bool(unit.get_meta("carrier_transport_mode", false))
		Domain.HELICOPTER:
			var heli_state := int(controller.get("state"))
			var mission_phase := int(controller.get("mission_phase"))
			status["state"] = heli_state
			status["state_name"] = HelicopterPilot.State.keys()[heli_state] \
					if heli_state >= 0 and heli_state < HelicopterPilot.State.size() else "UNKNOWN"
			status["mission_phase"] = mission_phase
			status["mission_name"] = HelicopterPilot.MissionPhase.keys()[mission_phase] \
					if mission_phase >= 0 and mission_phase < HelicopterPilot.MissionPhase.size() else "UNKNOWN"
			status["recovered"] = bool(unit.get_meta("carrier_transport_mode", false)) \
					or mission_phase == HelicopterPilot.MissionPhase.AT_CARRIER
		Domain.GROUND_PLATOON:
			var platoon := controller as GroundVehiclePlatoon
			status["state_name"] = platoon.get_objective_name()
			status["member_count"] = platoon.get_members().size()
			status["recovered"] = platoon.get_members().is_empty()
	var queue_position := _get_landing_queue_position()
	status["landing_queue_position"] = queue_position
	if queue_position > 0:
		status["waiting_for_clearance"] = true
	return status


func try_begin_ground_retrieval() -> bool:
	if domain != Domain.GROUND_PLATOON or not is_valid():
		return false
	var platoon := controller as GroundVehiclePlatoon
	if platoon.get_members().is_empty():
		return true
	var ground_ops := unit.get_node_or_null("/root/GroundOpsManager")
	var platoon_id := str(platoon.get("platoon_id"))
	if ground_ops != null and not platoon_id.is_empty() and ground_ops.has_method("retrieve"):
		ground_ops.call("retrieve", platoon_id)
		return true
	var carrier := _get_carrier()
	if carrier != null and "vehicle_bay" in carrier:
		var bay: Variant = carrier.get("vehicle_bay")
		if is_instance_valid(bay) and bay.has_method("retrieve_vehicles"):
			bay.call("retrieve_vehicles", platoon.get_members())
			return true
	return false


func _accept_fixed_wing_order(order: OpsOrder) -> bool:
	match order.kind:
		OpsOrder.Kind.TRANSIT_TO_POSITION:
			var destination := order.position
			if controller.has_method("build_terrain_safe_waypoints"):
				var requested_points: Array[Vector3] = [order.position]
				var safe_points: Variant = controller.call(
					"build_terrain_safe_waypoints",
					requested_points,
					maxf(float(order.metadata.get("minimum_agl_m", 260.0)), 50.0),
					false,
					false
				)
				if safe_points is Array and not safe_points.is_empty() and safe_points[0] is Vector3:
					destination = safe_points[0]
			var task: Variant = AirTaskModel.patrol(
				destination,
				order.radius_m if is_finite(order.radius_m) else 250.0,
				order.altitude_m
			)
			task.requested_speed_mps = order.speed_mps
			task.metadata = order.metadata.duplicate(true)
			if not bool(controller.call("assign_air_task", task)):
				return false
			var leg_speed := order.speed_mps if is_finite(order.speed_mps) else -1.0
			controller.call("set_flight_plan_legs", "ops_transit", [{
				"position": destination,
				"role": "ops_transit",
				"speed_mps": leg_speed,
				"capture_radius_m": order.radius_m if is_finite(order.radius_m) else 250.0,
			}], false, false)
			controller.set("nav_waypoint", destination)
			controller.call("change_state", AIPilot.State.TRANSIT)
			return true
		OpsOrder.Kind.PATROL_POSITION:
			return set_supervised_patrol_leg(order, 0)
		OpsOrder.Kind.INTERCEPT_TARGET:
			return bool(controller.call("assign_air_task", AirTaskModel.intercept_target(order.target)))
		OpsOrder.Kind.ATTACK_TARGET:
			return bool(controller.call("assign_air_task", AirTaskModel.attack_target(order.target)))
		OpsOrder.Kind.RETURN_TO_BASE:
			return bool(controller.call("assign_air_task", AirTaskModel.return_to_base()))
		OpsOrder.Kind.RECOVER:
			return bool(controller.call("assign_air_task", AirTaskModel.recover()))
	return false


func _accept_helicopter_order(order: OpsOrder) -> bool:
	match order.kind:
		OpsOrder.Kind.TRANSIT_TO_POSITION:
			controller.call(
				"set_flight_leg",
				order.position,
				order.speed_mps if is_finite(order.speed_mps) else -1.0
			)
			return true
		OpsOrder.Kind.ATTACK_TARGET:
			return bool(controller.call("command_attack_target", order.target)) \
					if controller.has_method("command_attack_target") else false
		OpsOrder.Kind.RESCUE_TARGET:
			controller.call("command_rescue", order.target)
			return true
		OpsOrder.Kind.HOLD_POSITION:
			controller.call(
				"command_hover",
				order.position if OpsOrder._is_finite_position(order.position) else null
			)
			return true
		OpsOrder.Kind.RETURN_TO_BASE, OpsOrder.Kind.RECOVER:
			return bool(controller.call("command_return_to_carrier_and_land"))
	return false


func _accept_ground_order(order: OpsOrder) -> bool:
	var platoon := controller as GroundVehiclePlatoon
	match order.kind:
		OpsOrder.Kind.TRANSIT_TO_POSITION:
			platoon.set_move_objective(order.position)
		OpsOrder.Kind.ATTACK_TARGET:
			platoon.set_attack_node(order.target, order.radius_m if is_finite(order.radius_m) else 300.0)
		OpsOrder.Kind.ATTACK_POSITION:
			platoon.set_attack_position(order.position, order.radius_m if is_finite(order.radius_m) else 300.0)
		OpsOrder.Kind.PROTECT_TARGET:
			platoon.set_protect_node(order.target, order.radius_m if is_finite(order.radius_m) else 250.0)
		OpsOrder.Kind.ESCORT_CARRIER:
			var escort_carrier := _get_carrier()
			if escort_carrier == null:
				return false
			platoon.set_escort_carrier(escort_carrier, order.radius_m if is_finite(order.radius_m) else 100.0)
		OpsOrder.Kind.HOLD_POSITION:
			platoon.set("objective_type", GroundVehiclePlatoon.ObjectiveType.NONE)
		OpsOrder.Kind.RETURN_TO_BASE, OpsOrder.Kind.RECOVER:
			var return_carrier := _get_carrier()
			if return_carrier == null:
				return false
			platoon.set_return_to_base(return_carrier, order.radius_m if is_finite(order.radius_m) else 90.0)
		_:
			return false
	return true


func _get_unit_position() -> Vector3:
	if domain == Domain.GROUND_PLATOON:
		return (controller as GroundVehiclePlatoon).get_center_position()
	return (unit as Node3D).global_position if unit is Node3D else Vector3.ZERO


func _get_carrier() -> Node3D:
	if unit == null or not is_instance_valid(unit):
		return null
	return unit.get_tree().get_first_node_in_group("carrier") as Node3D


func _get_landing_queue_position() -> int:
	if domain not in [Domain.FIXED_WING, Domain.HELICOPTER] or not (unit is RigidBody3D):
		return -1
	var fdm := unit.get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm != null and fdm.has_method("get_landing_queue_position"):
		return int(fdm.call("get_landing_queue_position", unit))
	return -1
