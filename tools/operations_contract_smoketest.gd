extends Node

const OpsOrderModel: Script = preload("res://Operations/OpsOrder.gd")
const OpsAdapterModel: Script = preload("res://Operations/OpsUnitAdapter.gd")
const PlatoonModel: Script = preload("res://GroundVehicle/ground_vehicle_platoon.gd")

var _failures: PackedStringArray = []


func _ready() -> void:
	var world := Node3D.new()
	world.name = "OperationsContractSmokeWorld"
	add_child(world)

	var carrier := Node3D.new()
	carrier.name = "ContractCarrier"
	carrier.add_to_group("carrier")
	world.add_child(carrier)

	var platoon: GroundVehiclePlatoon = PlatoonModel.new()
	platoon.name = "ContractPlatoon"
	world.add_child(platoon)

	var adapter: OpsUnitAdapter = OpsAdapterModel.create(platoon)
	_check(adapter.is_valid(), "ground platoon adapter should be valid")
	_check(adapter.domain == OpsUnitAdapter.Domain.GROUND_PLATOON, "adapter should report GROUND_PLATOON")
	_check(adapter.get_capabilities().has("recover"), "ground platoon should advertise recovery")

	var destination := Vector3(420.0, 0.0, -175.0)
	_check(adapter.accept_order(OpsOrderModel.transit_to_position(destination)), "transit order should be accepted")
	_check(platoon.objective_type == GroundVehiclePlatoon.ObjectiveType.MOVE_TO_POSITION, "transit should map to MOVE_TO_POSITION")
	_check(platoon.objective_position.is_equal_approx(destination), "transit destination should be preserved")

	var target := Node3D.new()
	target.name = "ContractTarget"
	target.position = Vector3(900.0, 0.0, 300.0)
	world.add_child(target)
	_check(adapter.accept_order(OpsOrderModel.attack_target(target)), "attack-target order should be accepted")
	_check(platoon.objective_type == GroundVehiclePlatoon.ObjectiveType.ATTACK_NODE, "attack should map to ATTACK_NODE")
	_check(platoon.attack_node == target, "attack target should be preserved")

	_check(adapter.accept_order(OpsOrderModel.escort_carrier(115.0)), "escort-carrier order should be accepted")
	_check(platoon.objective_type == GroundVehiclePlatoon.ObjectiveType.ESCORT_CARRIER, "escort should map to ESCORT_CARRIER")
	_check(platoon.escort_node == carrier, "escort should target the carrier")

	_check(adapter.accept_order(OpsOrderModel.recover()), "recover order should be accepted")
	_check(platoon.objective_type == GroundVehiclePlatoon.ObjectiveType.RETURN_TO_BASE, "recover should map to RETURN_TO_BASE")
	_check(platoon.escort_node == carrier, "recovery should target the carrier")

	var status := adapter.get_status()
	_check(bool(status.get("valid", false)), "ground status should be valid")
	_check(str(status.get("domain_name", "")) == "GROUND_PLATOON", "ground status should identify its domain")

	if _failures.is_empty():
		print("OPERATIONS_CONTRACT_SMOKE PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("OPERATIONS_CONTRACT_SMOKE: %s" % failure)
	print("OPERATIONS_CONTRACT_SMOKE FAIL count=%d" % _failures.size())
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
