extends Node3D
class_name GroundVehiclePlatoon

enum ObjectiveType {
	NONE,
	MOVE_TO_POSITION,
	PURSUE_ENEMIES,
	PROTECT_NODE,
	ATTACK_NODE,
}

@export var platoon_id: String = ""
@export var team: int = 1
@export var objective_type: ObjectiveType = ObjectiveType.NONE
@export var objective_position: Vector3 = Vector3.ZERO
@export var pursue_range_m: float = 1200.0
@export var protect_radius_m: float = 250.0
@export var protect_slot_radius_m: float = 140.0
@export var attack_radius_m: float = 300.0
@export var attack_slot_radius_m: float = 180.0

var protected_node: Node3D = null
var attack_node: Node3D = null
var _members: Array[Node3D] = []

func _ready() -> void:
	add_to_group("ground_vehicle_platoons")

func register_vehicle(vehicle: Node3D) -> void:
	if not vehicle or not is_instance_valid(vehicle):
		return
	if not _members.has(vehicle):
		_members.append(vehicle)

func unregister_vehicle(vehicle: Node3D) -> void:
	_members.erase(vehicle)

func get_members() -> Array[Node3D]:
	var valid_members: Array[Node3D] = []
	for member in _members:
		if member and is_instance_valid(member):
			valid_members.append(member)
	_members = valid_members
	return valid_members

func get_center_position() -> Vector3:
	var members: Array[Node3D] = get_members()
	if members.is_empty():
		return global_position
	var sum := Vector3.ZERO
	for member in members:
		sum += member.global_position
	return sum / float(members.size())

func set_move_objective(position: Vector3) -> void:
	objective_type = ObjectiveType.MOVE_TO_POSITION
	objective_position = position

func set_pursue_enemies(range_m: float = 1200.0) -> void:
	objective_type = ObjectiveType.PURSUE_ENEMIES
	pursue_range_m = maxf(range_m, 50.0)

func set_protect_node(node: Node3D, radius_m: float = 250.0) -> void:
	objective_type = ObjectiveType.PROTECT_NODE
	protected_node = node
	protect_radius_m = maxf(radius_m, 25.0)

func set_attack_node(node: Node3D, radius_m: float = 300.0) -> void:
	objective_type = ObjectiveType.ATTACK_NODE
	attack_node = node
	attack_radius_m = maxf(radius_m, 50.0)

func get_destination_for(vehicle: Node3D) -> Vector3:
	match objective_type:
		ObjectiveType.MOVE_TO_POSITION:
			return objective_position
		ObjectiveType.PURSUE_ENEMIES:
			var pursuit_target: Node3D = _find_nearest_hostile(vehicle.global_position, pursue_range_m)
			if pursuit_target:
				return pursuit_target.global_position
			return get_center_position()
		ObjectiveType.PROTECT_NODE:
			if protected_node and is_instance_valid(protected_node):
				var threat: Node3D = _find_nearest_hostile(protected_node.global_position, protect_radius_m, protected_node)
				var protect_slot: Vector3 = _get_slot_position_around(protected_node.global_position, vehicle, protect_slot_radius_m)
				if threat:
					return protect_slot.lerp(threat.global_position, 0.35)
				return protect_slot
			return get_center_position()
		ObjectiveType.ATTACK_NODE:
			if attack_node and is_instance_valid(attack_node):
				var attack_slot: Vector3 = _get_slot_position_around(attack_node.global_position, vehicle, attack_slot_radius_m)
				var defender: Node3D = _find_nearest_hostile(attack_node.global_position, attack_radius_m)
				if defender:
					return attack_slot.lerp(defender.global_position, 0.45)
				return attack_slot
			return get_center_position()
		_:
			return get_center_position()

func has_active_objective() -> bool:
	return objective_type != ObjectiveType.NONE

func _find_nearest_hostile(origin: Vector3, range_limit: float, excluded_node: Node3D = null) -> Node3D:
	var best_target: Node3D = null
	var best_distance: float = maxf(range_limit, 1.0)
	for group_name in ["ground_vehicles", "aircraft", "ai_aircraft", "friendlies", "enemies", "carrier"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node3D) or not is_instance_valid(node):
				continue
			if excluded_node and node == excluded_node:
				continue
			if node.has_method("get_team") and int(node.get_team()) == team:
				continue
			var node3d := node as Node3D
			var dist: float = origin.distance_to(node3d.global_position)
			if dist < best_distance:
				best_distance = dist
				best_target = node3d
	return best_target

func _get_slot_position_around(anchor: Vector3, vehicle: Node3D, radius_m: float) -> Vector3:
	var members: Array[Node3D] = get_members()
	var slot_index: int = members.find(vehicle)
	if slot_index < 0:
		slot_index = 0
	var slot_count: int = max(members.size(), 1)
	var angle: float = TAU * float(slot_index) / float(slot_count)
	return anchor + Vector3(cos(angle) * radius_m, 0.0, sin(angle) * radius_m)
