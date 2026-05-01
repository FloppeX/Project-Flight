extends Node3D
class_name GroundVehiclePlatoon

enum ObjectiveType {
	NONE,
	MOVE_TO_POSITION,
	PURSUE_ENEMIES,
	PROTECT_NODE,
	ATTACK_NODE,
	ESCORT_CARRIER,
	PROTECT_POSITION,
	ATTACK_POSITION,
	RETURN_TO_BASE,
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
@export var contact_path_clearance_m: float = 60.0
@export var contact_repath_interval_s: float = 1.0
@export var contact_goal_repath_distance_m: float = 70.0
@export var contact_waypoint_reach_distance_m: float = 24.0
@export var contact_anchor_distance_m: float = 220.0
@export var contact_anchor_search_samples: int = 12
@export var route_preview_repath_interval_s: float = 2.5

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
var _contact_world_position: Vector3 = Vector3.INF
var _contact_path_positions: Array[Vector3] = []
var _contact_path_index: int = 0
var _contact_path_goal: Vector3 = Vector3.ZERO
var _contact_repath_timer_s: float = 0.0
var _route_preview_positions: Array[Vector3] = []
var _route_preview_goal: Vector3 = Vector3.INF
var _route_preview_origin: Vector3 = Vector3.INF
var _route_preview_repath_timer_s: float = 0.0

func _ready() -> void:
	add_to_group("origin_shifter")
	add_to_group("ground_vehicle_platoons")
	set_physics_process(true)
	_contact_repath_timer_s = randf() * maxf(contact_repath_interval_s, 0.1)
	_route_preview_repath_timer_s = randf() * maxf(route_preview_repath_interval_s, 0.1)

func apply_origin_shift(offset: Vector3) -> void:
	objective_position -= offset
	if _is_valid_contact_world_position(_contact_world_position):
		_contact_world_position -= offset
	if _is_valid_contact_world_position(_route_preview_goal):
		_route_preview_goal -= offset
	if _is_valid_contact_world_position(_route_preview_origin):
		_route_preview_origin -= offset
	for i in range(_contact_path_positions.size()):
		if _is_valid_contact_world_position(_contact_path_positions[i]):
			_contact_path_positions[i] -= offset
	for i in range(_route_preview_positions.size()):
		if _is_valid_contact_world_position(_route_preview_positions[i]):
			_route_preview_positions[i] -= offset
	if _shared_hostile_cache_origin.length_squared() < 1e10:
		_shared_hostile_cache_origin -= offset

func _physics_process(delta: float) -> void:
	_update_contact_position(delta)
	_update_route_preview(delta)

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

func has_members() -> bool:
	return not get_members().is_empty()

func get_center_position() -> Vector3:
	var members: Array[Node3D] = get_members()
	if members.is_empty():
		return global_position
	var sum := Vector3.ZERO
	for member in members:
		sum += member.global_position
	return sum / float(members.size())

func get_contact_position() -> Vector3:
	if _is_valid_contact_world_position(_contact_world_position):
		return _contact_world_position
	var fallback_contact := _get_safe_contact_nav_position(_get_contact_follow_target(), global_position)
	if _is_valid_contact_world_position(fallback_contact):
		return fallback_contact
	return _get_contact_follow_target()

func get_active_waypoints() -> Array[Vector3]:
	var active_waypoints: Array[Vector3] = []
	for point in _route_preview_positions:
		if _is_valid_contact_world_position(point):
			active_waypoints.append(_project_contact_to_ground(point))
	if active_waypoints.is_empty():
		var fallback_goal := _project_contact_to_ground(_get_route_preview_goal())
		if _is_valid_contact_world_position(fallback_goal):
			var contact_pos := get_contact_position()
			if not _is_valid_contact_world_position(contact_pos) or _flat_distance(contact_pos, fallback_goal) > maxf(contact_waypoint_reach_distance_m, 2.0):
				active_waypoints.append(fallback_goal)
	return active_waypoints

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
	protected_node = null
	attack_node = null
	escort_node = null

func set_pursue_enemies(range_m: float = 1200.0) -> void:
	objective_type = ObjectiveType.PURSUE_ENEMIES
	pursue_range_m = maxf(range_m, 50.0)
	protected_node = null
	attack_node = null
	escort_node = null

func set_protect_node(node: Node3D, radius_m: float = 250.0) -> void:
	objective_type = ObjectiveType.PROTECT_NODE
	protected_node = node
	objective_position = node.global_position if node and is_instance_valid(node) else objective_position
	protect_radius_m = maxf(radius_m, 25.0)
	attack_node = null
	escort_node = null

func set_protect_position(position: Vector3, radius_m: float = 250.0) -> void:
	objective_type = ObjectiveType.PROTECT_POSITION
	objective_position = position
	protect_radius_m = maxf(radius_m, 25.0)
	protected_node = null
	attack_node = null
	escort_node = null

func set_attack_node(node: Node3D, radius_m: float = 300.0) -> void:
	objective_type = ObjectiveType.ATTACK_NODE
	attack_node = node
	objective_position = node.global_position if node and is_instance_valid(node) else objective_position
	attack_radius_m = maxf(radius_m, 50.0)
	protected_node = null
	escort_node = null

func set_attack_position(position: Vector3, radius_m: float = 300.0) -> void:
	objective_type = ObjectiveType.ATTACK_POSITION
	objective_position = position
	attack_radius_m = maxf(radius_m, 50.0)
	protected_node = null
	attack_node = null
	escort_node = null

func set_escort_carrier(carrier: Node3D, distance_m: float = 100.0) -> void:
	objective_type = ObjectiveType.ESCORT_CARRIER
	escort_node = carrier
	escort_distance_m = maxf(distance_m, 20.0)
	protected_node = null
	attack_node = null

func set_return_to_base(carrier: Node3D, distance_m: float = 90.0) -> void:
	objective_type = ObjectiveType.RETURN_TO_BASE
	escort_node = carrier
	escort_distance_m = maxf(distance_m, 20.0)
	protected_node = null
	attack_node = null

func get_objective_name() -> String:
	match objective_type:
		ObjectiveType.NONE:
			return "HOLD"
		ObjectiveType.MOVE_TO_POSITION:
			return "MOVE"
		ObjectiveType.PURSUE_ENEMIES:
			return "PURSUE"
		ObjectiveType.PROTECT_NODE, ObjectiveType.PROTECT_POSITION:
			return "PROTECT"
		ObjectiveType.ATTACK_NODE, ObjectiveType.ATTACK_POSITION:
			return "ATTACK"
		ObjectiveType.ESCORT_CARRIER:
			return "ESCORT"
		ObjectiveType.RETURN_TO_BASE:
			return "RTB"
		_:
			return "UNKNOWN"

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
		ObjectiveType.PROTECT_POSITION:
			var protect_target := objective_position
			var protect_threat: Node3D = _find_shared_hostile("protect_position", protect_target, protect_radius_m)
			var protect_slot_pos: Vector3 = _get_slot_position_around(protect_target, vehicle, protect_slot_radius_m)
			if protect_threat:
				return protect_slot_pos.lerp(protect_threat.global_position, 0.35)
			return protect_slot_pos
		ObjectiveType.ATTACK_NODE:
			if attack_node and is_instance_valid(attack_node):
				var attack_slot: Vector3 = _get_slot_position_around(attack_node.global_position, vehicle, attack_slot_radius_m)
				var defender: Node3D = _find_shared_hostile("attack", attack_node.global_position, attack_radius_m)
				if defender:
					return attack_slot.lerp(defender.global_position, 0.45)
				return attack_slot
			return get_center_position()
		ObjectiveType.ATTACK_POSITION:
			var attack_target := objective_position
			var attack_defender: Node3D = _find_shared_hostile("attack_position", attack_target, attack_radius_m)
			var attack_slot_pos: Vector3 = _get_slot_position_around(attack_target, vehicle, attack_slot_radius_m)
			if attack_defender:
				return attack_slot_pos.lerp(attack_defender.global_position, 0.45)
			return attack_slot_pos
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
		ObjectiveType.RETURN_TO_BASE:
			if escort_node and is_instance_valid(escort_node):
				return _get_return_to_base_position(vehicle)
			return get_center_position()
		_:
			return get_center_position()

func has_active_objective() -> bool:
	return objective_type != ObjectiveType.NONE

func _get_formation_anchor(fallback_destination: Vector3) -> Vector3:
	var route_anchor := _get_route_navigation_anchor()
	if _is_valid_contact_world_position(route_anchor):
		return route_anchor
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
		ObjectiveType.PROTECT_POSITION:
			var protect_threat: Node3D = _find_shared_hostile("protect_position", objective_position, protect_radius_m)
			if protect_threat:
				return objective_position.lerp(protect_threat.global_position, 0.25)
			return objective_position
		ObjectiveType.ATTACK_NODE:
			if attack_node and is_instance_valid(attack_node):
				var defender: Node3D = _find_shared_hostile("attack", attack_node.global_position, attack_radius_m)
				if defender:
					return attack_node.global_position.lerp(defender.global_position, 0.35)
				return attack_node.global_position
		ObjectiveType.ATTACK_POSITION:
			var attack_defender: Node3D = _find_shared_hostile("attack_position", objective_position, attack_radius_m)
			if attack_defender:
				return objective_position.lerp(attack_defender.global_position, 0.35)
			return objective_position
		ObjectiveType.RETURN_TO_BASE:
			if escort_node and is_instance_valid(escort_node):
				return _get_return_to_base_position(null)
		_:
			pass
	return fallback_destination

func _get_route_navigation_anchor() -> Vector3:
	if objective_type == ObjectiveType.ESCORT_CARRIER:
		return Vector3.INF
	var contact_pos := get_contact_position()
	if not _is_valid_contact_world_position(contact_pos):
		return Vector3.INF
	var reach_distance: float = maxf(contact_waypoint_reach_distance_m, 2.0)
	for waypoint in _route_preview_positions:
		if not _is_valid_contact_world_position(waypoint):
			continue
		if _flat_distance(contact_pos, waypoint) <= reach_distance:
			continue
		return _project_contact_to_ground(waypoint)
	if _is_valid_contact_world_position(_route_preview_goal) and _flat_distance(contact_pos, _route_preview_goal) > reach_distance:
		return _project_contact_to_ground(_route_preview_goal)
	return Vector3.INF

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
			var node3d := node as Node3D
			if _is_air_movement_target(node3d):
				continue
			if node.has_method("get_team") and int(node.get_team()) == team:
				continue
			var dist: float = origin.distance_to(node3d.global_position)
			if dist < best_distance:
				best_distance = dist
				best_target = node3d
	return best_target

func _is_air_movement_target(target: Node3D) -> bool:
	return target != null and (target.is_in_group("aircraft") or target.is_in_group("ai_aircraft"))

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

func _get_return_to_base_position(vehicle: Node3D) -> Vector3:
	if escort_node == null or not is_instance_valid(escort_node):
		return get_center_position()
	var members: Array[Node3D] = get_members()
	var slot_index: int = members.find(vehicle) if vehicle != null else 0
	if slot_index < 0:
		slot_index = 0
	var lateral_slots: Array[float] = [-36.0, -12.0, 12.0, 36.0]
	var lateral: float = lateral_slots[slot_index % lateral_slots.size()]
	var rank: int = int(slot_index / lateral_slots.size())
	var rear_distance: float = 58.0 + escort_distance_m + float(rank) * formation_rank_spacing_m
	return _escort_local_to_world(Vector3(lateral, 0.0, -rear_distance))

func _get_slot_position_around(anchor: Vector3, vehicle: Node3D, radius_m: float) -> Vector3:
	var members: Array[Node3D] = get_members()
	var slot_index: int = members.find(vehicle)
	if slot_index < 0:
		slot_index = 0
	var slot_count: int = max(members.size(), 1)
	var angle: float = TAU * float(slot_index) / float(slot_count)
	return anchor + Vector3(cos(angle) * radius_m, 0.0, sin(angle) * radius_m)

func _update_contact_position(delta: float) -> void:
	var members: Array[Node3D] = get_members()
	if members.is_empty():
		_clear_contact_path()
		_contact_repath_timer_s = 0.0
		return

	var contact_target := _get_contact_follow_target_from_members(members)
	if not _is_valid_contact_world_position(contact_target):
		return

	if not _is_valid_contact_world_position(_contact_world_position):
		var initial_contact := _get_safe_contact_nav_position(contact_target, contact_target)
		_contact_world_position = initial_contact if _is_valid_contact_world_position(initial_contact) else contact_target
		_contact_path_goal = contact_target
		_clear_contact_path()
		return

	var reach_distance: float = maxf(contact_waypoint_reach_distance_m, 2.0)
	if _flat_distance(_contact_world_position, contact_target) <= reach_distance:
		_contact_world_position = contact_target
		_contact_path_goal = contact_target
		_clear_contact_path()
		return

	if not NavGraph.is_ready():
		_contact_world_position = _project_contact_to_ground(contact_target)
		return

	_contact_repath_timer_s += delta
	var repath_due: bool = _contact_repath_timer_s >= maxf(contact_repath_interval_s, 0.1)
	var goal_shifted: bool = _flat_distance(_contact_path_goal, contact_target) > contact_goal_repath_distance_m
	var needs_path: bool = _contact_path_positions.is_empty() or _contact_path_index >= _contact_path_positions.size()
	if goal_shifted or (needs_path and repath_due):
		_recompute_contact_path(contact_target)

	_advance_contact_along_path(delta, contact_target)

func _recompute_contact_path(target_world_pos: Vector3) -> void:
	_contact_repath_timer_s = 0.0
	_contact_path_goal = target_world_pos
	if not NavGraph.is_ready():
		return

	var start_world := _get_safe_contact_nav_position(_contact_world_position, target_world_pos)
	var goal_world := _get_safe_contact_nav_position(target_world_pos, _contact_world_position)
	if not _is_valid_contact_world_position(start_world) or not _is_valid_contact_world_position(goal_world):
		return
	_contact_world_position = start_world
	var reach_distance: float = maxf(contact_waypoint_reach_distance_m, 2.0)
	if _flat_distance(start_world, goal_world) <= reach_distance:
		_contact_world_position = goal_world
		_clear_contact_path()
		return

	var candidate_path := NavGraph.find_path(start_world, goal_world, contact_path_clearance_m)
	if candidate_path.is_empty():
		return
	_contact_path_positions = candidate_path
	_contact_path_index = 0
	_consume_reached_contact_waypoints()

func _advance_contact_along_path(delta: float, target_world_pos: Vector3) -> void:
	if _contact_path_index >= _contact_path_positions.size():
		if _flat_distance(_contact_world_position, target_world_pos) <= maxf(contact_waypoint_reach_distance_m, 2.0):
			_contact_world_position = _project_contact_to_ground(target_world_pos)
		return

	var remaining_step: float = maxf(_get_contact_follow_speed_mps() * maxf(delta, 0.0), 0.0)
	_consume_reached_contact_waypoints()
	while remaining_step > 0.0 and _contact_path_index < _contact_path_positions.size():
		var waypoint := _project_contact_to_ground(_contact_path_positions[_contact_path_index])
		var to_waypoint := waypoint - _contact_world_position
		to_waypoint.y = 0.0
		var distance_to_waypoint: float = to_waypoint.length()
		if distance_to_waypoint <= maxf(contact_waypoint_reach_distance_m, 2.0):
			_contact_world_position = waypoint
			_contact_path_index += 1
			continue
		var travel_step: float = minf(remaining_step, distance_to_waypoint)
		var move_dir := to_waypoint / distance_to_waypoint
		_contact_world_position += Vector3(move_dir.x, 0.0, move_dir.z) * travel_step
		_contact_world_position = _project_contact_to_ground(_contact_world_position)
		remaining_step -= travel_step
		if travel_step + 0.001 < distance_to_waypoint:
			break
		_contact_world_position = waypoint
		_contact_path_index += 1
	_consume_reached_contact_waypoints()
	if _contact_path_index >= _contact_path_positions.size() and _flat_distance(_contact_world_position, target_world_pos) <= maxf(contact_waypoint_reach_distance_m, 2.0):
		_contact_world_position = _project_contact_to_ground(target_world_pos)

func _update_route_preview(delta: float) -> void:
	if not has_active_objective() or not has_members():
		_clear_route_preview()
		return
	var route_target := _get_route_preview_goal()
	if not _is_valid_contact_world_position(route_target):
		_clear_route_preview()
		return
	if not NavGraph.is_ready():
		_route_preview_positions = [_project_contact_to_ground(route_target)]
		_route_preview_goal = route_target
		return
	var contact_pos := get_contact_position()
	if not _is_valid_contact_world_position(contact_pos):
		_clear_route_preview()
		return
	_route_preview_repath_timer_s += maxf(delta, 0.0)
	var goal_shifted: bool = not _is_valid_contact_world_position(_route_preview_goal) or _flat_distance(_route_preview_goal, route_target) > contact_goal_repath_distance_m
	var origin_shifted: bool = not _is_valid_contact_world_position(_route_preview_origin) or _flat_distance(_route_preview_origin, contact_pos) > contact_goal_repath_distance_m
	if goal_shifted or origin_shifted or _route_preview_positions.is_empty():
		_recompute_route_preview(contact_pos, route_target)

func _recompute_route_preview(start_world_pos: Vector3, target_world_pos: Vector3) -> void:
	_route_preview_repath_timer_s = 0.0
	_route_preview_goal = target_world_pos
	if not NavGraph.is_ready():
		_route_preview_positions = [_project_contact_to_ground(target_world_pos)]
		_route_preview_origin = _project_contact_to_ground(start_world_pos)
		return
	var start_world := _get_safe_contact_nav_position(start_world_pos, target_world_pos)
	var goal_world := _get_safe_contact_nav_position(target_world_pos, start_world_pos)
	if not _is_valid_contact_world_position(start_world) or not _is_valid_contact_world_position(goal_world):
		_clear_route_preview()
		return
	_route_preview_origin = start_world
	var reach_distance: float = maxf(contact_waypoint_reach_distance_m, 2.0)
	if _flat_distance(start_world, goal_world) <= reach_distance:
		_route_preview_positions = [goal_world]
		return
	var candidate_path := NavGraph.find_path(start_world, goal_world, contact_path_clearance_m)
	if candidate_path.is_empty():
		_route_preview_positions = [goal_world]
		return
	_route_preview_positions.clear()
	for i in range(candidate_path.size()):
		var waypoint := _project_contact_to_ground(candidate_path[i])
		if i == 0 and _flat_distance(waypoint, start_world) <= reach_distance:
			continue
		if not _route_preview_positions.is_empty() and _flat_distance(_route_preview_positions[_route_preview_positions.size() - 1], waypoint) <= 0.5:
			continue
		_route_preview_positions.append(waypoint)
	if _route_preview_positions.is_empty() or _flat_distance(_route_preview_positions[_route_preview_positions.size() - 1], goal_world) > reach_distance:
		_route_preview_positions.append(goal_world)

func _consume_reached_contact_waypoints() -> void:
	var reach_distance: float = maxf(contact_waypoint_reach_distance_m, 2.0)
	while _contact_path_index < _contact_path_positions.size():
		if _flat_distance(_contact_world_position, _contact_path_positions[_contact_path_index]) > reach_distance:
			break
		_contact_path_index += 1

func _clear_contact_path() -> void:
	_contact_path_positions.clear()
	_contact_path_index = 0

func _clear_route_preview() -> void:
	_route_preview_positions.clear()
	_route_preview_goal = Vector3.INF
	_route_preview_origin = Vector3.INF
	_route_preview_repath_timer_s = 0.0

func _get_contact_follow_target() -> Vector3:
	return _get_contact_follow_target_from_members(get_members())

func _get_route_preview_goal() -> Vector3:
	if not has_active_objective():
		return Vector3.INF
	var members: Array[Node3D] = get_members()
	if not members.is_empty():
		return _project_contact_to_ground(get_destination_for(members[0]))
	match objective_type:
		ObjectiveType.MOVE_TO_POSITION:
			return _project_contact_to_ground(objective_position)
		ObjectiveType.PURSUE_ENEMIES:
			var center: Vector3 = get_center_position()
			var pursuit_target: Node3D = _find_shared_hostile("pursue_preview", center, pursue_range_m)
			if pursuit_target:
				return _project_contact_to_ground(pursuit_target.global_position)
		ObjectiveType.PROTECT_NODE:
			if protected_node and is_instance_valid(protected_node):
				return _project_contact_to_ground(protected_node.global_position)
		ObjectiveType.PROTECT_POSITION:
			return _project_contact_to_ground(objective_position)
		ObjectiveType.ATTACK_NODE:
			if attack_node and is_instance_valid(attack_node):
				return _project_contact_to_ground(attack_node.global_position)
		ObjectiveType.ATTACK_POSITION:
			return _project_contact_to_ground(objective_position)
		ObjectiveType.ESCORT_CARRIER:
			if escort_node and is_instance_valid(escort_node):
				return _project_contact_to_ground(escort_node.global_position)
		ObjectiveType.RETURN_TO_BASE:
			if escort_node and is_instance_valid(escort_node):
				return _project_contact_to_ground(_get_return_to_base_position(null))
	return Vector3.INF

func _is_route_preview_goal_dynamic() -> bool:
	match objective_type:
		ObjectiveType.PURSUE_ENEMIES, ObjectiveType.PROTECT_NODE, ObjectiveType.ATTACK_NODE, ObjectiveType.PROTECT_POSITION, ObjectiveType.ATTACK_POSITION, ObjectiveType.ESCORT_CARRIER, ObjectiveType.RETURN_TO_BASE:
			return true
		_:
			return false

func _get_contact_follow_target_from_members(members: Array[Node3D]) -> Vector3:
	if members.is_empty():
		return _project_contact_to_ground(global_position)

	var center := _get_member_average_position(members)
	var representative := _get_representative_member_position(members, center)
	var safe_representative := _get_safe_contact_nav_position(representative, center)
	if _is_valid_contact_world_position(safe_representative):
		return safe_representative
	var safe_center := _get_safe_contact_nav_position(center, representative)
	if _is_valid_contact_world_position(safe_center):
		return safe_center
	return _project_contact_to_ground(representative)

func _get_member_average_position(members: Array[Node3D]) -> Vector3:
	if members.is_empty():
		return global_position
	var sum := Vector3.ZERO
	for member in members:
		sum += member.global_position
	return sum / float(members.size())

func _get_representative_member_position(members: Array[Node3D], center: Vector3) -> Vector3:
	if members.is_empty():
		return center
	var best_member_pos: Vector3 = members[0].global_position
	var best_distance_sq: float = INF
	for member in members:
		var flat_offset := Vector2(member.global_position.x - center.x, member.global_position.z - center.z)
		var distance_sq: float = flat_offset.length_squared()
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_member_pos = member.global_position
	return best_member_pos

func _project_contact_to_ground(world_pos: Vector3) -> Vector3:
	var projected := world_pos
	var terrain_y: float = TerrainNavGrid.sample_height(projected.x, projected.z)
	if terrain_y > TerrainNavGrid.IMPASSABLE * 0.5:
		projected.y = terrain_y
	return projected

func _get_safe_contact_nav_position(world_pos: Vector3, reference_world_pos: Vector3 = Vector3.INF) -> Vector3:
	var projected := _project_contact_to_ground(world_pos)
	if not _is_valid_contact_world_position(projected):
		return Vector3.INF
	if not NavGraph.is_ready():
		return projected
	if _can_anchor_contact_position(projected):
		return projected

	var reference := reference_world_pos if _is_valid_contact_world_position(reference_world_pos) else projected
	var search_radius: float = maxf(contact_anchor_distance_m, contact_waypoint_reach_distance_m * 2.0)
	var sample_count: int = maxi(contact_anchor_search_samples, 4)
	var base_vec := Vector2(projected.x - reference.x, projected.z - reference.z)
	var base_angle: float = atan2(base_vec.y, base_vec.x) if base_vec.length_squared() > 1.0 else 0.0
	var best_target: Vector3 = Vector3.INF
	var best_score: float = INF
	var ring_count: int = 3
	for ring_idx in range(1, ring_count + 1):
		var radius: float = search_radius * float(ring_idx) / float(ring_count)
		for sample_idx in range(sample_count):
			var angle: float = base_angle + TAU * float(sample_idx) / float(sample_count)
			var candidate := projected + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			candidate = _project_contact_to_ground(candidate)
			if not _can_anchor_contact_position(candidate):
				continue
			var score: float = _flat_distance(candidate, projected) + _flat_distance(candidate, reference) * 0.1
			if score < best_score:
				best_score = score
				best_target = candidate
	if _is_valid_contact_world_position(best_target):
		return best_target
	return Vector3.INF

func _can_anchor_contact_position(world_pos: Vector3) -> bool:
	if not _is_valid_contact_world_position(world_pos) or not NavGraph.is_ready():
		return false
	return NavGraph.can_anchor(world_pos, contact_path_clearance_m, contact_anchor_distance_m)

func _get_contact_follow_speed_mps() -> float:
	return maxf(get_platoon_speed_limit(15.0), 6.0)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _is_valid_contact_world_position(world_pos: Vector3) -> bool:
	return is_finite(world_pos.x) and is_finite(world_pos.y) and is_finite(world_pos.z)
