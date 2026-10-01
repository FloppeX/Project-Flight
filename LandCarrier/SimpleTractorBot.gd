class_name SimpleTractorBot
extends Node3D

const DeckRoute = preload("res://LandCarrier/TractorDeckRoute.gd")
# Bounds of the authored GLB (including its nested scales), plus wheel clearance.
const CHASSIS_HALF_WIDTH := 1.02
const CHASSIS_HALF_LENGTH := 1.1
const CLOSE_GEAR_CHASSIS_SPACING := 2.3

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")

# Simple tractorbot that follows aircraft movement for visual effect
# The actual aircraft movement is handled by FlightDeckManager

@export var target_aircraft: RigidBody3D
@export var target_wheel_node: Node3D
@export var wheel_position_offset: Vector3 = Vector3.ZERO  # Offset from aircraft center to wheel
@export var follow_height: float = 0.0  # Keep tractorbot centered on deck height (Y offset from deck)
@export var move_speed: float = 11.0  # Speed to follow aircraft
@export var positioning_speed: float = 4.5  # Speed when initially positioning at gear
@export var rotation_speed: float = 360.0  # Degrees per second to rotate
@export var separation_radius: float = 3.1  # Keep this much space from sibling tractor bots
@export var gear_clearance_m: float = 1.75
@export var turn_move_min_factor: float = 0.35
@export var center_lane_half_width_m: float = 0.45
@export var side_approach_offset_m: float = 2.0
@export var center_approach_offset_m: float = 2.2
@export var wheel_arrive_tolerance_m: float = 0.18
@export var live_wheel_replan_distance_m: float = 0.75
@export var rotation_align_tolerance_deg: float = 3.0

var _wheel_cache: Dictionary = {}
var _approach_points: Array[Vector3] = []
var _route: Array[Vector3] = []
var _route_goal := Vector3.INF
var _retry_s := 0.0
var _withdrawal := Vector3.INF
var _withdraw_wheel: WeakRef
var _docking_offset_local := Vector3.ZERO
var _dock_outward := Vector3.ZERO
var _exit_offsets: Array[Vector3] = []
var _exit_choices: Array[Vector3] = []
var _exit_target := Vector3.INF

var is_active: bool = false
var is_positioned: bool = false  # Whether we've reached the gear position
var fixed_target_position: Vector3 = Vector3.ZERO  # Fixed position to move to, not following aircraft
var _fixed_target_local_position: Vector3 = Vector3.ZERO
var target_position: Vector3
var external_target_set: bool = false  # Whether target was set externally (e.g., by elevator)
var movement_disabled: bool = false  # Whether movement logic is disabled (e.g., during elevator)

enum ApproachRole {
	CENTER,
	LEFT,
	RIGHT
}

enum ApproachPhase {
	ROUTE_TO_STAGE,
	ROTATE_TO_GEAR,
	DRIVE_TO_GEAR,
	FOLLOW
}

var _approach_role: ApproachRole = ApproachRole.CENTER
var _approach_phase: ApproachPhase = ApproachPhase.ROUTE_TO_STAGE
var _last_blocked_by_peer: bool = false
var _blocked_time_s: float = 0.0
var _debug_replan_count: int = 0
var _debug_last_live_replan_delta_m: float = 0.0

func _ready():
	add_to_group("tractor_bot")
	add_to_group("simple_tractor_bot")
	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_ON

func activate(aircraft: RigidBody3D, wheel_offset: Vector3, wheel_node: Node3D = null):
	"""Activate this tractorbot to position at a specific aircraft wheel"""
	target_aircraft = aircraft
	target_wheel_node = wheel_node
	wheel_position_offset = wheel_offset
	_withdrawal = Vector3.INF
	_exit_choices.clear()
	_exit_target = Vector3.INF
	_route.clear()
	is_active = true
	is_positioned = false
	movement_disabled = false
	external_target_set = false
	
	_approach_role = _classify_approach_role()
	_docking_offset_local = Vector3.ZERO
	if is_instance_valid(target_wheel_node) and _approach_role != ApproachRole.CENTER:
		var assigned := aircraft.to_local(target_wheel_node.global_position)
		var skid_contact := "skid" in target_wheel_node.name.to_lower()
		for wheel in _aircraft_wheels(aircraft):
			if wheel == target_wheel_node: continue
			var other := aircraft.to_local(wheel.global_position)
			if assigned.x * other.x < 0.0 and absf(assigned.z - other.z) < 2.2:
				# A close pair seats toward the inner end of each fork. Keep
				# the chassis outside the wheels rather than overlapping bodies.
				var clearance := maxf(0.0, (CLOSE_GEAR_CHASSIS_SPACING - absf(assigned.x - other.x)) * 0.5)
				_docking_offset_local.x = signf(assigned.x) * maxf(absf(_docking_offset_local.x), clearance)
			if skid_contact and assigned.x * other.x > 0.0 and absf(assigned.x - other.x) < 0.5:
				var longitudinal_clearance := maxf(0.0, (CLOSE_GEAR_CHASSIS_SPACING - absf(assigned.z - other.z)) * 0.5)
				_docking_offset_local.z = signf(assigned.z - other.z) * maxf(absf(_docking_offset_local.z), longitudinal_clearance)
	# Keep the approach target fixed for this docking pass.
	var deck_height: float = _get_deck_height()
	fixed_target_position = _resolve_wheel_target_position()
	fixed_target_position.y = deck_height
	_fixed_target_local_position = _to_carrier_local(fixed_target_position)
	_approach_role = _classify_approach_role()
	_build_approach_plan()
	_last_blocked_by_peer = false
	_blocked_time_s = 0.0
	_debug_replan_count = 0
	_debug_last_live_replan_delta_m = 0.0
	
	pass  # activated

func deactivate():
	"""Deactivate this tractorbot"""
	# Retain the reverse docking leg when the manager releases us for transit.
	if is_active and is_positioned and is_instance_valid(target_aircraft):
		_fixed_target_local_position = _to_carrier_local(_resolve_wheel_target_position())
		_build_approach_plan()
	if is_active and is_positioned and _dock_outward.length_squared() > 0.01:
		_withdrawal = _to_carrier_local(global_position) + _dock_outward
		_withdraw_wheel = weakref(target_wheel_node) if is_instance_valid(target_wheel_node) else null
		_exit_choices.clear()
		for offset in _exit_offsets:
			_exit_choices.append(_to_carrier_local(global_position) + offset)
	_route.clear()
	is_active = false
	is_positioned = false
	target_aircraft = null
	target_wheel_node = null
	movement_disabled = false
	external_target_set = false
	_approach_phase = ApproachPhase.ROUTE_TO_STAGE
	_debug_replan_count = 0
	_debug_last_live_replan_delta_m = 0.0
	pass  # deactivated

func is_positioned_at_gear() -> bool:
	"""Check if this tractorbot is positioned at its target gear"""
	return is_positioned

func get_recovery_debug_status() -> Dictionary:
	var live_wheel := _resolve_wheel_target_position()
	var fixed_target := fixed_target_position
	var goal := live_wheel
	if external_target_set:
		goal = target_position
	elif not is_positioned:
		match _approach_phase:
			ApproachPhase.ROUTE_TO_STAGE:
				goal = _from_carrier_local(_approach_points[0]) if not _approach_points.is_empty() else live_wheel
			ApproachPhase.ROTATE_TO_GEAR, ApproachPhase.DRIVE_TO_GEAR:
				goal = live_wheel
	goal.y = global_position.y
	live_wheel.y = global_position.y
	fixed_target.y = global_position.y
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var to_live := live_wheel - global_position
	to_live.y = 0.0
	var fixed_to_live := live_wheel - fixed_target
	fixed_to_live.y = 0.0
	var aircraft_speed := 0.0
	if is_instance_valid(target_aircraft):
		aircraft_speed = target_aircraft.linear_velocity.length()
	return {
		"name": name,
		"active": is_active,
		"positioned": is_positioned,
		"phase": _approach_phase_name(),
		"role": _approach_role_name(),
		"distance": to_goal.length(),
		"blocked": _last_blocked_by_peer,
		"blocked_seconds": _blocked_time_s,
		"movement_disabled": movement_disabled,
		"external_target": external_target_set,
		"target_aircraft": target_aircraft.name if is_instance_valid(target_aircraft) else "none",
		"target_wheel": target_wheel_node.name if is_instance_valid(target_wheel_node) else "none",
		"wheel_source": "live" if is_instance_valid(target_wheel_node) else "offset",
		"goal_position": goal,
		"bot_position": global_position,
		"live_wheel_position": live_wheel,
		"fixed_target_position": fixed_target,
		"live_distance": to_live.length(),
		"fixed_live_delta": fixed_to_live.length(),
		"replans": _debug_replan_count,
		"last_replan_delta": _debug_last_live_replan_delta_m,
		"aircraft_speed": aircraft_speed,
	}

func set_external_target(new_target: Vector3):
	"""Set target position externally (e.g., by elevator)"""
	target_position = new_target
	external_target_set = true
	pass  # external target set

func clear_external_target():
	"""Clear external target and return to following aircraft"""
	external_target_set = false
	if is_active and not is_positioned:
		_build_approach_plan()

func disable_movement():
	"""Disable movement logic (e.g., during elevator sequence)"""
	movement_disabled = true

func enable_movement():
	"""Re-enable movement logic"""
	movement_disabled = false

func _get_deck_height() -> float:
	"""Get the flight deck height from the carrier"""
	var carrier = get_parent()
	if carrier and carrier.has_method("get_deck_height"):
		return carrier.get_deck_height()
	if carrier:
		var fdm: Node = carrier.find_child("FlightDeckManager", true, false)
		if fdm and fdm.has_method("get_deck_height"):
			return float(fdm.call("get_deck_height"))
	# Fallback to carrier's global Y + 0.5
	if carrier and carrier is Node3D:
		return (carrier as Node3D).global_position.y + 0.5
	return 0.5

func _physics_process(delta: float):
	if not is_active or movement_disabled:
		return
	var _profiler_start: int = FrameProfiler.begin("SimpleTractorBot.physics")

	var deck_height: float = _get_deck_height()
	if external_target_set:
		target_position.y = deck_height
		_navigate_to(target_position, move_speed, delta)
		FrameProfiler.end("SimpleTractorBot.physics", _profiler_start)
		return

	if not is_instance_valid(target_aircraft):
		FrameProfiler.end("SimpleTractorBot.physics", _profiler_start)
		return

	if not is_positioned:
		_tick_approach(deck_height, delta)
	else:
		var live_target: Vector3 = _resolve_wheel_target_position()
		live_target.y = deck_height
		target_position = live_target
		_approach_phase = ApproachPhase.FOLLOW
		_drive_toward_point(target_position, move_speed, delta, wheel_arrive_tolerance_m)
	FrameProfiler.end("SimpleTractorBot.physics", _profiler_start)

func _tick_approach(deck_height: float, delta: float) -> void:
	if _approach_phase == ApproachPhase.ROUTE_TO_STAGE:
		fixed_target_position = _from_carrier_local(_fixed_target_local_position)
		fixed_target_position.y = deck_height
		var live_wheel_target := _resolve_wheel_target_position()
		live_wheel_target.y = deck_height
		var live_delta := live_wheel_target.distance_to(fixed_target_position)
		if live_delta > live_wheel_replan_distance_m:
			fixed_target_position = live_wheel_target
			_fixed_target_local_position = _to_carrier_local(fixed_target_position)
			_debug_replan_count += 1
			_debug_last_live_replan_delta_m = live_delta
			_build_approach_plan()
	if not _approach_points.is_empty():
		var waypoint := _from_carrier_local(_approach_points[0])
		waypoint.y = deck_height
		# A transit corner is optional if another robot is occupying it: route
		# to the next corner instead of mutually reserving occupied waypoints.
		if _approach_points.size() > 1 and not DeckRoute.segment_clear(waypoint, waypoint, _obstacles()):
			_approach_points.pop_front()
			_route.clear()
			return
		if _navigate_to(waypoint, positioning_speed, delta):
			_approach_points.pop_front()
		return
	var wheel_target := _resolve_wheel_target_position()
	wheel_target.y = deck_height
	if _approach_phase != ApproachPhase.DRIVE_TO_GEAR:
		_approach_phase = ApproachPhase.ROTATE_TO_GEAR
		if _rotate_toward_point_yaw(wheel_target, delta):
			_approach_phase = ApproachPhase.DRIVE_TO_GEAR
		return
	if _drive_toward_point(wheel_target, positioning_speed, delta, wheel_arrive_tolerance_m):
		is_positioned = true
		_approach_phase = ApproachPhase.FOLLOW

func _build_approach_plan() -> void:
	fixed_target_position = _from_carrier_local(_fixed_target_local_position)
	var stage := _compute_staging_target(fixed_target_position)
	var side_clearance := maxf(side_approach_offset_m, 2.5) if is_instance_valid(target_wheel_node) and "skid" in target_wheel_node.name.to_lower() else side_approach_offset_m
	_dock_outward = _to_carrier_local(stage) - _to_carrier_local(fixed_target_position)
	_dock_outward.y = 0.0
	_route.clear()
	_approach_points.clear()
	# Travel along the outside of the gear footprint, then turn inward at the wheel.
	# Crossing to the opposite side happens beyond the fore/aft gear extent.
	var start := target_aircraft.to_local(global_position)
	var end := target_aircraft.to_local(stage)
	var min_z := end.z
	var max_z := end.z
	var min_x := -side_clearance
	var max_x := side_clearance
	for wheel in _aircraft_wheels(target_aircraft):
		var point := target_aircraft.to_local(wheel.global_position)
		min_z = minf(min_z, point.z - center_approach_offset_m)
		max_z = maxf(max_z, point.z + center_approach_offset_m)
		min_x = minf(min_x, point.x - side_clearance)
		max_x = maxf(max_x, point.x + side_clearance)
	var corridor_x := min_x if (start.x if _approach_role == ApproachRole.CENTER else end.x) < 0.0 else max_x
	if start.x * corridor_x < 0.0 and start.z > min_z and start.z < max_z:
		var crossing_z := min_z if absf(start.z - min_z) < absf(start.z - max_z) else max_z
		_add_approach_point(target_aircraft.to_global(Vector3(start.x, end.y, crossing_z)))
		_add_approach_point(target_aircraft.to_global(Vector3(corridor_x, end.y, crossing_z)))
	else:
		_add_approach_point(target_aircraft.to_global(Vector3(corridor_x, end.y, start.z)))
	_add_approach_point(target_aircraft.to_global(Vector3(corridor_x, end.y, end.z)))
	_exit_offsets.clear()
	if _approach_role != ApproachRole.CENTER:
		# Once uncoupled, continue alongside the aircraft to either end before
		# crossing back toward home. Offsets travel with the coupled aircraft.
		for z in [min_z, max_z]:
			_exit_offsets.append(_to_carrier_local(target_aircraft.to_global(Vector3(corridor_x, end.y, z))) - _fixed_target_local_position)

	_add_approach_point(stage)
	_approach_phase = ApproachPhase.ROUTE_TO_STAGE

func _add_approach_point(point: Vector3) -> void:
	_approach_points.append(_to_carrier_local(point))

func _compute_staging_target(wheel_target: Vector3) -> Vector3:
	if not is_instance_valid(target_aircraft):
		return wheel_target
	var fwd: Vector3 = _project_planar(target_aircraft.global_transform.basis.z, Vector3.FORWARD)
	var right: Vector3 = _project_planar(target_aircraft.global_transform.basis.x, Vector3.RIGHT)
	var aircraft_center: Vector3 = target_aircraft.global_position
	aircraft_center.y = wheel_target.y
	match _approach_role:
		ApproachRole.LEFT, ApproachRole.RIGHT:
			var side_clearance := maxf(side_approach_offset_m, 2.5) if is_instance_valid(target_wheel_node) and "skid" in target_wheel_node.name.to_lower() else side_approach_offset_m
			var side_a: Vector3 = wheel_target + right * side_clearance
			var side_b: Vector3 = wheel_target - right * side_clearance
			side_a.y = wheel_target.y
			side_b.y = wheel_target.y
			return side_a if side_a.distance_squared_to(aircraft_center) >= side_b.distance_squared_to(aircraft_center) else side_b
		_:
			var front: Vector3 = wheel_target + fwd * center_approach_offset_m
			var back: Vector3 = wheel_target - fwd * center_approach_offset_m
			front.y = wheel_target.y
			back.y = wheel_target.y
			return front if front.distance_squared_to(aircraft_center) >= back.distance_squared_to(aircraft_center) else back

func _classify_approach_role() -> ApproachRole:
	if not is_instance_valid(target_aircraft):
		return ApproachRole.CENTER
	var local_offset: Vector3
	if is_instance_valid(target_wheel_node):
		local_offset = target_aircraft.to_local(target_wheel_node.global_position)
	else:
		local_offset = target_aircraft.global_transform.basis.inverse() * wheel_position_offset
	if absf(local_offset.x) <= center_lane_half_width_m:
		return ApproachRole.CENTER
	return ApproachRole.RIGHT if local_offset.x > 0.0 else ApproachRole.LEFT

func _drive_toward_point(goal: Vector3, speed: float, delta: float, arrive_tolerance: float) -> bool:
	var to_goal: Vector3 = goal - global_position
	to_goal.y = 0.0
	var dist: float = to_goal.length()
	if dist <= maxf(arrive_tolerance, 0.01):
		var snap_pos: Vector3 = goal
		if _would_overlap_peer(snap_pos, delta):
			return false
		global_position = snap_pos
		return true
	var alignment: float = _rotate_toward_point_yaw_factor(goal, delta)
	var move_factor: float = maxf(turn_move_min_factor, alignment)
	var move_dist: float = minf(speed * move_factor * delta, dist)
	var move_dir: Vector3 = to_goal / maxf(dist, 0.001)
	var next_pos: Vector3 = global_position + move_dir * move_dist
	next_pos.y = goal.y
	var arrived_this_step := dist - move_dist <= maxf(arrive_tolerance, 0.01)
	if arrived_this_step:
		next_pos = goal
	if _would_overlap_peer(next_pos, delta):
		return false
	global_position = next_pos
	return arrived_this_step

func _rotate_toward_point_yaw(goal: Vector3, delta: float) -> bool:
	return _rotate_toward_point_yaw_factor(goal, delta) >= 0.99

func _rotate_toward_point_yaw_factor(goal: Vector3, delta: float) -> float:
	var to_goal: Vector3 = goal - global_position
	to_goal.y = 0.0
	if to_goal.length_squared() <= 0.00001:
		return 1.0
	var desired_yaw: float = atan2(to_goal.x, to_goal.z)
	var current_yaw: float = global_rotation.y
	var diff: float = wrapf(desired_yaw - current_yaw, -PI, PI)
	var max_step: float = deg_to_rad(maxf(rotation_speed, 0.0)) * delta
	global_rotation.y += clampf(diff, -max_step, max_step)
	for peer in get_tree().get_nodes_in_group("tractor_bot"):
		if peer != self and peer is SimpleTractorBot and _peer_sweep_blocked(peer, global_position):
			global_rotation.y = current_yaw
			return 0.0
	var remaining: float = absf(wrapf(desired_yaw - global_rotation.y, -PI, PI))
	var tolerance: float = deg_to_rad(maxf(rotation_align_tolerance_deg, 0.1))
	if remaining <= tolerance:
		return 1.0
	return clampf(1.0 - (remaining / PI), 0.0, 1.0)

func _would_overlap_peer(candidate_position: Vector3, delta: float = 0.0, allow_separation: bool = false) -> bool:
	var ignore_wheel: Node3D = null
	if _withdrawal != Vector3.INF and _withdraw_wheel != null:
		ignore_wheel = _withdraw_wheel.get_ref() as Node3D
	elif _approach_phase == ApproachPhase.DRIVE_TO_GEAR or is_positioned:
		ignore_wheel = target_wheel_node
	var docking_to_skid := is_instance_valid(target_wheel_node) and "skid" in target_wheel_node.name.to_lower() \
			and (_approach_phase == ApproachPhase.DRIVE_TO_GEAR or is_positioned)
	_last_blocked_by_peer = not DeckRoute.segment_clear(
		global_position, candidate_position, _obstacles(ignore_wheel,
			not (is_positioned or _approach_phase == ApproachPhase.DRIVE_TO_GEAR or _withdrawal != Vector3.INF),
			target_aircraft if docking_to_skid else null))
	if not _last_blocked_by_peer:
		for peer in get_tree().get_nodes_in_group("tractor_bot"):
			if peer != self and peer is SimpleTractorBot and _peer_sweep_blocked(peer, candidate_position):
				if allow_separation and _peer_separation_is_outward(peer, candidate_position):
					continue
				_last_blocked_by_peer = true
				break
	_blocked_time_s = _blocked_time_s + delta if _last_blocked_by_peer else 0.0
	return _last_blocked_by_peer

func _aircraft_wheels(aircraft: Node3D) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var key := aircraft.get_instance_id()
	if _wheel_cache.has(key):
		for reference in _wheel_cache[key]:
			var wheel = reference.get_ref()
			if is_instance_valid(wheel): result.append(wheel)
		return result
	for module in aircraft.find_children("*", "Node", true, false):
		if "gear_collision_shapes" in module:
			for wheel in module.get("gear_collision_shapes"):
				if is_instance_valid(wheel) and wheel is Node3D and not result.has(wheel):
					result.append(wheel)
	if result.is_empty():
		for wheel in aircraft.find_children("*Gear*Collider*", "CollisionShape3D", true, false):
			result.append(wheel)
	if _wheel_cache.size() > 64: _wheel_cache.clear()
	_wheel_cache[key] = result.map(func(wheel): return weakref(wheel))
	return result

func _obstacles(ignore_wheel: Node3D = null, include_peers: bool = true, ignore_aircraft: Node3D = null) -> Array[Vector3]:
	# X/Z are the planar center; Y stores the clearance radius.
	var result: Array[Vector3] = []
	for peer in (get_tree().get_nodes_in_group("tractor_bot") if include_peers else []):
		if peer == self or not is_instance_valid(peer) or not peer is Node3D:
			continue
		if absf(peer.global_position.y - global_position.y) < 1.0:
			var clearance := separation_radius
			if peer is SimpleTractorBot: clearance = maxf(clearance, peer.separation_radius)
			result.append(Vector3(peer.global_position.x, clearance, peer.global_position.z))
	var aircraft_list := get_tree().get_nodes_in_group("aircraft")
	if is_instance_valid(target_aircraft) and not aircraft_list.has(target_aircraft):
		aircraft_list.append(target_aircraft)
	for aircraft in aircraft_list:
		if aircraft == ignore_aircraft or aircraft.global_position.distance_to(global_position) > 80.0: continue
		for wheel in _aircraft_wheels(aircraft):
			if wheel == ignore_wheel or (wheel is CollisionShape3D and wheel.disabled): continue
			if absf(wheel.global_position.y - global_position.y) > 2.0: continue
			result.append(Vector3(wheel.global_position.x, gear_clearance_m, wheel.global_position.z))
	return result

func _navigate_to(goal: Vector3, speed: float, delta: float) -> bool:
	_retry_s -= delta
	var obstacles := _obstacles()
	var local_goal := _to_carrier_local(goal)
	var blocked := not _route.is_empty() and not DeckRoute.segment_clear(global_position, _from_carrier_local(_route[0]), obstacles)
	if local_goal.distance_to(_route_goal) > 0.1 or ((_route.is_empty() or blocked) and _retry_s <= 0.0):
		_route.clear()
		var routing_goal := goal
		if not DeckRoute.segment_clear(goal, goal, obstacles):
			# Keep right while waiting for an occupied destination. This frees
			# our own starting space, including when two robots exchange slots.
			var forward := (goal - global_position).normalized()
			var right := Vector3(forward.z, 0.0, -forward.x)
			routing_goal = goal - forward * separation_radius * 1.5 + right * separation_radius * 1.5
			routing_goal.y = goal.y
		for point in DeckRoute.plan(global_position, routing_goal, obstacles):
			_route.append(_to_carrier_local(point))
		_route_goal = local_goal
		_retry_s = 0.3 + float(get_instance_id() % 7) * 0.04
	if _route.is_empty(): return global_position.distance_to(goal) < 0.01
	var next := _from_carrier_local(_route[0])
	next.y = goal.y
	if _drive_toward_point(next, speed, delta, 0.02):
		_route.pop_front()
	return _route.is_empty() and global_position.distance_to(goal) < 0.01

func move_deck_transit(local_goal: Vector3, speed: float, delta: float) -> bool:
	# Called by the deck manager while autonomous following is disabled.
	if get_tree().paused: return false
	if _withdrawal != Vector3.INF and _withdraw_wheel != null and not is_instance_valid(_withdraw_wheel.get_ref()):
		# Storage removes the aircraft and its gear. The old straight reverse
		# leg can now lead into an idle elevator bot, so route freely to staging.
		_withdrawal = Vector3.INF
		_withdraw_wheel = null
		_exit_choices.clear()
		_exit_target = Vector3.INF
		_route.clear()
	if _withdrawal != Vector3.INF:
		var retreat := _from_carrier_local(_withdrawal)
		retreat.y = global_position.y
		# Back out without turning across the wheel or nearby robots.
		var next := global_position.move_toward(retreat, speed * delta)
		if _would_overlap_peer(next, delta): return false
		global_position = next
		if global_position.distance_to(retreat) < 0.01:
			_withdrawal = Vector3.INF
			_withdraw_wheel = null
			_route.clear()
		return false
	if _separate_transit_peers(speed, delta):
		return false
	if not _exit_choices.is_empty():
		_exit_target = _exit_choices[0]
		for choice in _exit_choices:
			if choice.distance_squared_to(local_goal) < _exit_target.distance_squared_to(local_goal): _exit_target = choice
		_exit_choices.clear()
	if _exit_target != Vector3.INF:
		var exit_world := _from_carrier_local(_exit_target)
		exit_world.y = global_position.y
		if _navigate_to(exit_world, speed, delta):
			_exit_target = Vector3.INF
			_route.clear()
		return false
	return _navigate_to(_from_carrier_local(local_goal), speed, delta)

func _separate_transit_peers(speed: float, delta: float) -> bool:
	# Stored aircraft can leave idle robots inside one another's turning space.
	# Translate outward before turning; ordinary swept collision checks cannot
	# resolve an overlap that already exists at the start of a movement.
	var outward := Vector3.ZERO
	var crowded := false
	var clearance := 2.0 * Vector2(CHASSIS_HALF_WIDTH, CHASSIS_HALF_LENGTH).length() + 0.1
	for peer in get_tree().get_nodes_in_group("tractor_bot"):
		if peer == self or not peer is SimpleTractorBot: continue
		if absf(peer.global_position.y - global_position.y) > 1.0: continue
		var offset: Vector3 = global_position - peer.global_position
		offset.y = 0.0
		if offset.length() >= clearance: continue
		crowded = true
		outward += offset.normalized()
	if not crowded: return false
	if outward.length_squared() < 0.0001: return true
	var candidate := global_position + outward.normalized() * minf(speed, 4.5) * delta
	if not _would_overlap_peer(candidate, delta, true):
		global_position = candidate
		_route.clear()
	return true

func _peer_separation_is_outward(peer: SimpleTractorBot, candidate: Vector3) -> bool:
	if not _peer_sweep_blocked(peer, global_position): return false
	var offset := global_position - peer.global_position
	var motion := candidate - global_position
	if motion.length_squared() < 0.00000001: return false
	# Every separating-axis distance must stay the same or grow. This permits
	# backing out of an existing overlap, never crossing through a neighbour.
	for axis in [global_basis.x, global_basis.z, peer.global_basis.x, peer.global_basis.z]:
		var planar := _project_planar(axis, Vector3.RIGHT)
		if offset.dot(planar) * motion.dot(planar) < -0.000001: return false
	return offset.dot(motion) > 0.000001

func _approach_phase_name() -> String:
	match _approach_phase:
		ApproachPhase.ROUTE_TO_STAGE:
			return "ROUTE_TO_STAGE"
		ApproachPhase.ROTATE_TO_GEAR:
			return "ROTATE_TO_GEAR"
		ApproachPhase.DRIVE_TO_GEAR:
			return "DRIVE_TO_GEAR"
		ApproachPhase.FOLLOW:
			return "FOLLOW"
		_:
			return "UNKNOWN"

func _approach_role_name() -> String:
	match _approach_role:
		ApproachRole.CENTER:
			return "CENTER"
		ApproachRole.LEFT:
			return "LEFT"
		ApproachRole.RIGHT:
			return "RIGHT"
		_:
			return "UNKNOWN"

func _resolve_wheel_target_position() -> Vector3:
	if is_instance_valid(target_wheel_node):
		return target_wheel_node.global_position + target_aircraft.global_basis * _docking_offset_local if is_instance_valid(target_aircraft) else target_wheel_node.global_position
	if is_instance_valid(target_aircraft):
		return target_aircraft.global_position + wheel_position_offset
	return global_position

func _to_carrier_local(world_pos: Vector3) -> Vector3:
	var carrier := get_parent() as Node3D
	if is_instance_valid(carrier):
		return carrier.to_local(world_pos)
	return world_pos

func _from_carrier_local(local_pos: Vector3) -> Vector3:
	var carrier := get_parent() as Node3D
	if is_instance_valid(carrier):
		return carrier.to_global(local_pos)
	return local_pos

func _project_planar(dir: Vector3, fallback: Vector3) -> Vector3:
	var planar := Vector3(dir.x, 0.0, dir.z)
	if planar.length_squared() <= 0.0001:
		planar = Vector3(fallback.x, 0.0, fallback.z)
	if planar.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return planar.normalized()

func _peer_sweep_blocked(peer: SimpleTractorBot, candidate: Vector3) -> bool:
	if absf(peer.global_position.y - global_position.y) > 1.0: return false
	# Swept oriented rectangles: the wide wheeled chassis can fit beside a
	# closely spaced gear pair when both robots face inward, without overlap.
	var axes: Array[Vector3] = [global_basis.x, global_basis.z, peer.global_basis.x, peer.global_basis.z]
	var offset := global_position - peer.global_position
	var motion := candidate - global_position
	var enter := 0.0
	var leave := 1.0
	for axis in axes:
		axis = _project_planar(axis, Vector3.RIGHT)
		var radius := _footprint_support(axis) + peer._footprint_support(axis) + 0.05
		var distance := offset.dot(axis)
		var velocity := motion.dot(axis)
		if absf(velocity) < 0.00001:
			if absf(distance) >= radius: return false
		else:
			var first := (-radius - distance) / velocity
			var last := (radius - distance) / velocity
			enter = maxf(enter, minf(first, last))
			leave = minf(leave, maxf(first, last))
			if enter >= leave: return false
	return enter < leave

func _footprint_support(axis: Vector3) -> float:
	return absf(axis.dot(global_basis.x.normalized())) * CHASSIS_HALF_WIDTH + absf(axis.dot(global_basis.z.normalized())) * CHASSIS_HALF_LENGTH

func finish_hangar_docking() -> void:
	# The hidden hangar spawn starts coupled; use the same inward-facing pose.
	var deck_y := global_position.y
	global_position = _resolve_wheel_target_position()
	global_position.y = deck_y
	var inward: Vector3 = -(get_parent().global_basis * _dock_outward)
	global_rotation.y = atan2(inward.x, inward.z)
	is_positioned = true
	_approach_phase = ApproachPhase.FOLLOW

func can_tow_step(displacement: Vector3, convoy: Array) -> bool:
	var candidate := global_position + displacement
	for peer in get_tree().get_nodes_in_group("tractor_bot"):
		if not convoy.has(peer) and peer is SimpleTractorBot and _peer_sweep_blocked(peer, candidate): return false
	return DeckRoute.segment_clear(global_position, candidate, _obstacles(null, false, target_aircraft))
