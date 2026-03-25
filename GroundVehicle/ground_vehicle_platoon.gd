extends Node3D
class_name GroundVehiclePlatoon

enum ObjectiveType {
	NONE,
	MOVE_TO_POSITION,
	PURSUE_ENEMIES,
	PROTECT_NODE,
	ATTACK_NODE,
	ESCORT_CARRIER,
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
@export var move_scatter_radius_m: float = 50.0
@export var escort_distance_m: float = 100.0
@export var escort_engage_radius_m: float = 200.0
@export var escort_lane_side_clearance_m: float = 22.0
@export var escort_lane_end_clearance_m: float = 24.0
@export var escort_lane_deadband_m: float = 10.0
@export var formation_rank_spacing_m: float = 26.0
@export var formation_file_spacing_m: float = 18.0
@export var formation_widen_per_rank_m: float = 3.0

var protected_node: Node3D = null
var attack_node: Node3D = null
var escort_node: Node3D = null
var _members: Array[Node3D] = []
var _shared_hostile_cache_key: String = ""
var _shared_hostile_cache_origin: Vector3 = Vector3.ZERO
var _shared_hostile_cache_range_m: float = 0.0
var _shared_hostile_cache_excluded: Node3D = null
var _shared_hostile_cache_target: Node3D = null
var _shared_hostile_cache_at_ms: int = 0
var _member_combat_cache: bool = false
var _member_combat_cache_at_ms: int = 0
var _member_speed_cache_mps: float = 0.0
var _member_speed_cache_at_ms: int = 0

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

func has_any_member_in_combat() -> bool:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _member_combat_cache_at_ms <= 150:
		return _member_combat_cache
	_member_combat_cache_at_ms = now_ms
	_member_combat_cache = false
	for member in get_members():
		if member and is_instance_valid(member) and member.has_method("_has_combat_target") and bool(member.call("_has_combat_target")):
			_member_combat_cache = true
			break
	return _member_combat_cache

func get_platoon_speed_limit(default_speed_mps: float) -> float:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _member_speed_cache_at_ms <= 250 and _member_speed_cache_mps > 0.0:
		return _member_speed_cache_mps
	var slowest_speed: float = maxf(default_speed_mps, 0.1)
	var found_speed: bool = false
	for member in get_members():
		if not member or not is_instance_valid(member):
			continue
		var member_speed_value = member.get("max_speed")
		if member_speed_value == null:
			continue
		var member_speed: float = float(member_speed_value)
		if member_speed <= 0.0:
			continue
		if not found_speed:
			slowest_speed = member_speed
			found_speed = true
		else:
			slowest_speed = minf(slowest_speed, member_speed)
	_member_speed_cache_mps = slowest_speed if found_speed else maxf(default_speed_mps, 0.1)
	_member_speed_cache_at_ms = now_ms
	return _member_speed_cache_mps

func get_formation_destination_for(vehicle: Node3D, fallback_destination: Vector3) -> Vector3:
	var members: Array[Node3D] = get_members()
	var slot_index: int = members.find(vehicle)
	if slot_index < 0 or members.size() <= 1:
		return fallback_destination
	if objective_type == ObjectiveType.ESCORT_CARRIER:
		return fallback_destination
	var anchor: Vector3 = _get_formation_anchor(fallback_destination)
	var center: Vector3 = get_center_position()
	var forward: Vector3 = anchor - center
	forward.y = 0.0
	if forward.length_squared() <= 1.0:
		forward = _get_average_member_forward()
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var right: Vector3 = Vector3.UP.cross(forward).normalized()
	var offset: Vector2 = _get_formation_offset(slot_index)
	var slot_world: Vector3 = anchor + right * offset.x - forward * offset.y
	var terrain_y: float = TerrainNavGrid.sample_height(slot_world.x, slot_world.z)
	if terrain_y > -9000.0:
		slot_world.y = terrain_y
	else:
		slot_world.y = fallback_destination.y
	return slot_world

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

func set_escort_carrier(carrier: Node3D, distance_m: float = 100.0) -> void:
	objective_type = ObjectiveType.ESCORT_CARRIER
	escort_node = carrier
	escort_distance_m = maxf(distance_m, 20.0)

func get_destination_for(vehicle: Node3D) -> Vector3:
	match objective_type:
		ObjectiveType.MOVE_TO_POSITION:
			return _get_slot_position_around(objective_position, vehicle, move_scatter_radius_m)
		ObjectiveType.PURSUE_ENEMIES:
			var pursuit_target: Node3D = _find_nearest_hostile(vehicle.global_position, pursue_range_m)
			if pursuit_target:
				return pursuit_target.global_position
			return get_center_position()
		ObjectiveType.PROTECT_NODE:
			if protected_node and is_instance_valid(protected_node):
				var threat: Node3D = _find_shared_hostile("protect", protected_node.global_position, protect_radius_m, protected_node)
				var protect_slot: Vector3 = _get_slot_position_around(protected_node.global_position, vehicle, protect_slot_radius_m)
				if threat:
					return protect_slot.lerp(threat.global_position, 0.35)
				return protect_slot
			return get_center_position()
		ObjectiveType.ATTACK_NODE:
			if attack_node and is_instance_valid(attack_node):
				var attack_slot: Vector3 = _get_slot_position_around(attack_node.global_position, vehicle, attack_slot_radius_m)
				var defender: Node3D = _find_shared_hostile("attack", attack_node.global_position, attack_radius_m)
				if defender:
					return attack_slot.lerp(defender.global_position, 0.45)
				return attack_slot
			return get_center_position()
		ObjectiveType.ESCORT_CARRIER:
			if escort_node and is_instance_valid(escort_node):
				var corner_pos: Vector3 = _get_escort_corner_position(vehicle)
				var nav_pos: Vector3 = _get_escort_navigation_position(vehicle, corner_pos)
				var threat: Node3D = _find_shared_hostile("escort", escort_node.global_position, escort_engage_radius_m, escort_node)
				if threat and vehicle.global_position.distance_to(corner_pos) <= 60.0:
					# Slight lean toward threat but mostly hold position
					return corner_pos.lerp(threat.global_position, 0.15)
				return nav_pos
			return get_center_position()
		_:
			return get_center_position()

func has_active_objective() -> bool:
	return objective_type != ObjectiveType.NONE

func _get_formation_anchor(fallback_destination: Vector3) -> Vector3:
	match objective_type:
		ObjectiveType.MOVE_TO_POSITION:
			return objective_position
		ObjectiveType.PURSUE_ENEMIES:
			var center: Vector3 = get_center_position()
			var pursuit_target: Node3D = _find_shared_hostile("pursue", center, pursue_range_m)
			if pursuit_target:
				return pursuit_target.global_position
			return center
		ObjectiveType.PROTECT_NODE:
			if protected_node and is_instance_valid(protected_node):
				var threat: Node3D = _find_shared_hostile("protect", protected_node.global_position, protect_radius_m, protected_node)
				if threat:
					return protected_node.global_position.lerp(threat.global_position, 0.25)
				return protected_node.global_position
		ObjectiveType.ATTACK_NODE:
			if attack_node and is_instance_valid(attack_node):
				var defender: Node3D = _find_shared_hostile("attack", attack_node.global_position, attack_radius_m)
				if defender:
					return attack_node.global_position.lerp(defender.global_position, 0.35)
				return attack_node.global_position
		_:
			pass
	return fallback_destination

func _get_average_member_forward() -> Vector3:
	var sum_forward := Vector3.ZERO
	for member in get_members():
		if not member or not is_instance_valid(member):
			continue
		var basis_forward: Vector3 = member.global_basis.z
		basis_forward.y = 0.0
		if basis_forward.length_squared() <= 0.0001:
			continue
		sum_forward += basis_forward.normalized()
	return sum_forward.normalized() if sum_forward.length_squared() > 0.0001 else Vector3.ZERO

func _get_formation_offset(slot_index: int) -> Vector2:
	if slot_index <= 0:
		return Vector2.ZERO
	var flank_index: int = slot_index - 1
	var rank: int = int(flank_index / 2) + 1
	var side: float = -1.0 if flank_index % 2 == 0 else 1.0
	var lateral: float = side * (formation_file_spacing_m + formation_widen_per_rank_m * float(rank - 1))
	var longitudinal: float = formation_rank_spacing_m * float(rank)
	return Vector2(lateral, longitudinal)

func _find_shared_hostile(cache_key: String, origin: Vector3, range_limit: float, excluded_node: Node3D = null) -> Node3D:
	var now_ms: int = Time.get_ticks_msec()
	var cache_fresh: bool = now_ms - _shared_hostile_cache_at_ms <= 250
	var cache_matches: bool = (
		_shared_hostile_cache_key == cache_key
		and absf(_shared_hostile_cache_range_m - range_limit) <= 0.01
		and _shared_hostile_cache_excluded == excluded_node
		and origin.distance_to(_shared_hostile_cache_origin) <= 25.0
	)
	var target_valid: bool = _shared_hostile_cache_target == null or is_instance_valid(_shared_hostile_cache_target)
	if cache_fresh and cache_matches and target_valid:
		return _shared_hostile_cache_target

	_shared_hostile_cache_key = cache_key
	_shared_hostile_cache_origin = origin
	_shared_hostile_cache_range_m = range_limit
	_shared_hostile_cache_excluded = excluded_node
	_shared_hostile_cache_at_ms = now_ms
	_shared_hostile_cache_target = _find_nearest_hostile(origin, range_limit, excluded_node)
	return _shared_hostile_cache_target

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

func _get_escort_corner_position(vehicle: Node3D) -> Vector3:
	var members: Array[Node3D] = get_members()
	var slot_index: int = members.find(vehicle)
	if slot_index < 0:
		slot_index = 0
	# Carrier body half-dimensions (treads at ±32 wide, ±48 long) plus buffer
	var half_length: float = 48.0 + escort_distance_m  # forward/rear from carrier center
	var half_width: float = 32.0 + escort_distance_m * 0.5  # left/right from carrier center
	# Corner offsets: front-right, front-left, rear-right, rear-left
	var corners: Array[Vector2] = [
		Vector2( half_width,  half_length),  # front-right
		Vector2(-half_width,  half_length),  # front-left
		Vector2( half_width, -half_length),  # rear-right
		Vector2(-half_width, -half_length),  # rear-left
	]
	var corner: Vector2 = corners[slot_index % corners.size()]
	var forward: Vector3 = escort_node.global_basis.z.normalized()
	var right: Vector3 = escort_node.global_basis.x.normalized()
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	var offset: Vector3 = right * corner.x + forward * corner.y
	var pos: Vector3 = escort_node.global_position + offset
	var terrain_y: float = TerrainNavGrid.sample_height(pos.x, pos.z)
	if terrain_y > -9000.0:
		pos.y = terrain_y
	return pos

func _get_escort_navigation_position(vehicle: Node3D, slot_world: Vector3) -> Vector3:
	if escort_node == null or not is_instance_valid(escort_node):
		return slot_world
	var vehicle_local: Vector3 = escort_node.to_local(vehicle.global_position)
	var slot_local: Vector3 = escort_node.to_local(slot_world)
	var side_sign: float = 1.0 if slot_local.x >= 0.0 else -1.0
	var lane_x: float = side_sign * (32.0 + escort_lane_side_clearance_m + escort_distance_m * 0.25)
	var lane_z: float = 48.0 + escort_lane_end_clearance_m + escort_distance_m * 0.15
	var side_error: float = absf(vehicle_local.x - lane_x)
	var on_correct_side: bool = side_error <= escort_lane_deadband_m
	var wants_front_slot: bool = slot_local.z >= 0.0
	var lane_entry_z: float = clampf(vehicle_local.z, -lane_z, lane_z)

	# Step 1: peel sideways out of the carrier's wake at the vehicle's current Z,
	# rather than forcing it to chase a fixed point behind the carrier.
	if not on_correct_side:
		return _escort_local_to_world(Vector3(lane_x, 0.0, lane_entry_z))

	# Step 2: once on the flank, run up or down that lane to the desired longitudinal band.
	if wants_front_slot:
		if vehicle_local.z < lane_z - escort_lane_deadband_m:
			return _escort_local_to_world(Vector3(lane_x, 0.0, lane_z))
	else:
		if vehicle_local.z > -lane_z + escort_lane_deadband_m:
			return _escort_local_to_world(Vector3(lane_x, 0.0, -lane_z))

	# Step 3: only then close in from the lane to the final slot.
	if absf(vehicle_local.x) < absf(lane_x) - escort_lane_deadband_m:
		return _escort_local_to_world(Vector3(lane_x, 0.0, slot_local.z))
	return slot_world

func _escort_local_to_world(local_pos: Vector3) -> Vector3:
	if escort_node == null or not is_instance_valid(escort_node):
		return local_pos
	var world_pos: Vector3 = escort_node.to_global(local_pos)
	var terrain_y: float = TerrainNavGrid.sample_height(world_pos.x, world_pos.z)
	if terrain_y > -9000.0:
		world_pos.y = terrain_y
	return world_pos

func _get_slot_position_around(anchor: Vector3, vehicle: Node3D, radius_m: float) -> Vector3:
	var members: Array[Node3D] = get_members()
	var slot_index: int = members.find(vehicle)
	if slot_index < 0:
		slot_index = 0
	var slot_count: int = max(members.size(), 1)
	var angle: float = TAU * float(slot_index) / float(slot_count)
	return anchor + Vector3(cos(angle) * radius_m, 0.0, sin(angle) * radius_m)
