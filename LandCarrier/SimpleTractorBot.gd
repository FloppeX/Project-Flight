class_name SimpleTractorBot
extends Node3D

# Simple tractorbot that follows aircraft movement for visual effect
# The actual aircraft movement is handled by FlightDeckManager

@export var target_aircraft: RigidBody3D
@export var target_wheel_node: Node3D
@export var wheel_position_offset: Vector3 = Vector3.ZERO  # Offset from aircraft center to wheel
@export var follow_height: float = 0.0  # Keep tractorbot centered on deck height (Y offset from deck)
@export var move_speed: float = 15.0  # Speed to follow aircraft
@export var positioning_speed: float = 3.0  # Speed when initially positioning at gear
@export var rotation_speed: float = 180.0  # Degrees per second to rotate
@export var separation_radius: float = 1.2  # Keep this much space from sibling tractor bots
@export var center_lane_half_width_m: float = 0.45
@export var side_approach_offset_m: float = 1.5
@export var center_approach_offset_m: float = 2.2
@export var axis_arrive_tolerance_m: float = 0.08
@export var wheel_arrive_tolerance_m: float = 0.06
@export var rotation_align_tolerance_deg: float = 3.0

var is_active: bool = false
var is_positioned: bool = false  # Whether we've reached the gear position
var fixed_target_position: Vector3 = Vector3.ZERO  # Fixed position to move to, not following aircraft
var target_position: Vector3
var external_target_set: bool = false  # Whether target was set externally (e.g., by elevator)
var movement_disabled: bool = false  # Whether movement logic is disabled (e.g., during elevator)

enum ApproachRole {
	CENTER,
	LEFT,
	RIGHT
}

enum ApproachPhase {
	AXIS_MOVE_1,
	AXIS_MOVE_2,
	ROTATE_TO_GEAR,
	DRIVE_TO_GEAR,
	FOLLOW
}

var _approach_role: ApproachRole = ApproachRole.CENTER
var _approach_phase: ApproachPhase = ApproachPhase.AXIS_MOVE_1
var _axis1_dir: Vector3 = Vector3.ZERO
var _axis1_target: Vector3 = Vector3.ZERO
var _axis2_dir: Vector3 = Vector3.ZERO
var _axis2_target: Vector3 = Vector3.ZERO
var _has_axis1: bool = false
var _has_axis2: bool = false

func _ready():
	add_to_group("tractor_bot")
	add_to_group("simple_tractor_bot")

func activate(aircraft: RigidBody3D, wheel_offset: Vector3, wheel_node: Node3D = null):
	"""Activate this tractorbot to position at a specific aircraft wheel"""
	target_aircraft = aircraft
	target_wheel_node = wheel_node
	wheel_position_offset = wheel_offset
	is_active = true
	is_positioned = false
	movement_disabled = false
	external_target_set = false
	
	# Keep the approach target fixed for this docking pass.
	var deck_height: float = _get_deck_height()
	fixed_target_position = _resolve_wheel_target_position()
	fixed_target_position.y = deck_height
	_approach_role = _classify_approach_role()
	_build_axis_approach_plan()
	
	pass  # activated

func deactivate():
	"""Deactivate this tractorbot"""
	is_active = false
	target_aircraft = null
	target_wheel_node = null
	movement_disabled = false
	external_target_set = false
	_has_axis1 = false
	_has_axis2 = false
	_approach_phase = ApproachPhase.AXIS_MOVE_1
	pass  # deactivated

func is_positioned_at_gear() -> bool:
	"""Check if this tractorbot is positioned at its target gear"""
	return is_positioned

func set_external_target(new_target: Vector3):
	"""Set target position externally (e.g., by elevator)"""
	target_position = new_target
	external_target_set = true
	pass  # external target set

func clear_external_target():
	"""Clear external target and return to following aircraft"""
	external_target_set = false
	if is_active and not is_positioned:
		_build_axis_approach_plan()

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

	var deck_height: float = _get_deck_height()
	if external_target_set:
		target_position.y = deck_height
		_drive_toward_point(target_position, move_speed, delta, wheel_arrive_tolerance_m)
		return

	if not is_instance_valid(target_aircraft):
		return

	if not is_positioned:
		_tick_axis_approach(deck_height, delta)
	else:
		var live_target: Vector3 = _resolve_wheel_target_position()
		live_target.y = deck_height
		target_position = live_target
		_approach_phase = ApproachPhase.FOLLOW
		_drive_toward_point(target_position, move_speed, delta, wheel_arrive_tolerance_m)

func _tick_axis_approach(deck_height: float, delta: float) -> void:
	match _approach_phase:
		ApproachPhase.AXIS_MOVE_1:
			if not _has_axis1 or _move_along_axis_to_target(_axis1_dir, _axis1_target, positioning_speed, delta):
				_approach_phase = ApproachPhase.AXIS_MOVE_2 if _has_axis2 else ApproachPhase.ROTATE_TO_GEAR
		ApproachPhase.AXIS_MOVE_2:
			if not _has_axis2 or _move_along_axis_to_target(_axis2_dir, _axis2_target, positioning_speed, delta):
				_approach_phase = ApproachPhase.ROTATE_TO_GEAR
		ApproachPhase.ROTATE_TO_GEAR:
			var wheel_target := _resolve_wheel_target_position()
			wheel_target.y = deck_height
			if _rotate_toward_point_yaw(wheel_target, delta):
				_approach_phase = ApproachPhase.DRIVE_TO_GEAR
		ApproachPhase.DRIVE_TO_GEAR:
			var wheel_target := _resolve_wheel_target_position()
			wheel_target.y = deck_height
			if _drive_toward_point(wheel_target, positioning_speed, delta, wheel_arrive_tolerance_m):
				is_positioned = true
				_approach_phase = ApproachPhase.FOLLOW
		ApproachPhase.FOLLOW:
			is_positioned = true

func _build_axis_approach_plan() -> void:
	var deck_height: float = _get_deck_height()
	var wheel_target: Vector3 = fixed_target_position
	wheel_target.y = deck_height
	var staging_target: Vector3 = _compute_staging_target(wheel_target)
	staging_target.y = wheel_target.y
	var axes: Dictionary = _get_deck_planar_axes()
	var deck_x: Vector3 = axes.get("x", Vector3.RIGHT)
	var deck_z: Vector3 = axes.get("z", Vector3.FORWARD)
	var start_pos: Vector3 = global_position
	start_pos.y = wheel_target.y
	var delta_to_stage: Vector3 = staging_target - start_pos
	delta_to_stage.y = 0.0
	var delta_x: float = delta_to_stage.dot(deck_x)
	var delta_z: float = delta_to_stage.dot(deck_z)
	var use_x_first: bool = absf(delta_x) >= absf(delta_z)

	_has_axis1 = false
	_has_axis2 = false
	_axis1_dir = Vector3.ZERO
	_axis2_dir = Vector3.ZERO
	_axis1_target = start_pos
	_axis2_target = staging_target

	var mid_pos: Vector3 = start_pos
	if use_x_first:
		if absf(delta_x) > axis_arrive_tolerance_m:
			_has_axis1 = true
			_axis1_dir = deck_x * signf(delta_x)
			_axis1_target = start_pos + deck_x * delta_x
			_axis1_target.y = wheel_target.y
			mid_pos = _axis1_target
		if absf(delta_z) > axis_arrive_tolerance_m:
			_has_axis2 = true
			_axis2_dir = deck_z * signf(delta_z)
			_axis2_target = mid_pos + deck_z * delta_z
			_axis2_target.y = wheel_target.y
	else:
		if absf(delta_z) > axis_arrive_tolerance_m:
			_has_axis1 = true
			_axis1_dir = deck_z * signf(delta_z)
			_axis1_target = start_pos + deck_z * delta_z
			_axis1_target.y = wheel_target.y
			mid_pos = _axis1_target
		if absf(delta_x) > axis_arrive_tolerance_m:
			_has_axis2 = true
			_axis2_dir = deck_x * signf(delta_x)
			_axis2_target = mid_pos + deck_x * delta_x
			_axis2_target.y = wheel_target.y

	if _has_axis1:
		_approach_phase = ApproachPhase.AXIS_MOVE_1
	elif _has_axis2:
		_approach_phase = ApproachPhase.AXIS_MOVE_2
	else:
		_approach_phase = ApproachPhase.ROTATE_TO_GEAR

func _compute_staging_target(wheel_target: Vector3) -> Vector3:
	if not is_instance_valid(target_aircraft):
		return wheel_target
	var fwd: Vector3 = _project_planar(target_aircraft.global_transform.basis.z, Vector3.FORWARD)
	var right: Vector3 = _project_planar(target_aircraft.global_transform.basis.x, Vector3.RIGHT)
	match _approach_role:
		ApproachRole.LEFT:
			return wheel_target - right * side_approach_offset_m
		ApproachRole.RIGHT:
			return wheel_target + right * side_approach_offset_m
		_:
			var front: Vector3 = wheel_target + fwd * center_approach_offset_m
			var back: Vector3 = wheel_target - fwd * center_approach_offset_m
			front.y = wheel_target.y
			back.y = wheel_target.y
			return front if global_position.distance_squared_to(front) <= global_position.distance_squared_to(back) else back

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

func _move_along_axis_to_target(axis: Vector3, axis_target: Vector3, speed: float, delta: float) -> bool:
	if axis.length_squared() <= 0.000001:
		return true
	var axis_dir: Vector3 = axis.normalized()
	var planar_to_target: Vector3 = axis_target - global_position
	planar_to_target.y = 0.0
	var along: float = planar_to_target.dot(axis_dir)
	if absf(along) <= axis_arrive_tolerance_m:
		var snapped: Vector3 = global_position + axis_dir * along
		snapped.y = axis_target.y
		if not _would_overlap_peer(snapped):
			global_position = snapped
		return true
	var step: float = clampf(along, -speed * delta, speed * delta)
	var next_pos: Vector3 = global_position + axis_dir * step
	next_pos.y = axis_target.y
	if _would_overlap_peer(next_pos):
		return false
	global_position = next_pos
	return false

func _drive_toward_point(goal: Vector3, speed: float, delta: float, arrive_tolerance: float) -> bool:
	var to_goal: Vector3 = goal - global_position
	to_goal.y = 0.0
	var dist: float = to_goal.length()
	if dist <= maxf(arrive_tolerance, 0.01):
		var snap_pos: Vector3 = goal
		if not _would_overlap_peer(snap_pos):
			global_position = snap_pos
		return true
	var aligned: bool = _rotate_toward_point_yaw(goal, delta)
	if not aligned:
		return false
	var move_dist: float = minf(speed * delta, dist)
	var move_dir: Vector3 = to_goal / maxf(dist, 0.001)
	var next_pos: Vector3 = global_position + move_dir * move_dist
	next_pos.y = goal.y
	if _would_overlap_peer(next_pos):
		return false
	global_position = next_pos
	return false

func _rotate_toward_point_yaw(goal: Vector3, delta: float) -> bool:
	var to_goal: Vector3 = goal - global_position
	to_goal.y = 0.0
	if to_goal.length_squared() <= 0.00001:
		return true
	var desired_yaw: float = atan2(to_goal.x, to_goal.z)
	var current_yaw: float = global_rotation.y
	var diff: float = wrapf(desired_yaw - current_yaw, -PI, PI)
	var max_step: float = deg_to_rad(maxf(rotation_speed, 0.0)) * delta
	global_rotation.y += clampf(diff, -max_step, max_step)
	return absf(diff) <= deg_to_rad(maxf(rotation_align_tolerance_deg, 0.1))

func _would_overlap_peer(candidate_position: Vector3) -> bool:
	if separation_radius <= 0.0 or not is_inside_tree():
		return false
	for node in get_tree().get_nodes_in_group("tractor_bot"):
		if node == self or not is_instance_valid(node) or not (node is Node3D):
			continue
		var other := node as Node3D
		if absf(other.global_position.y - global_position.y) > 1.0:
			continue
		var away: Vector3 = candidate_position - other.global_position
		away.y = 0.0
		if away.length() < separation_radius:
			return true
	return false

func _resolve_wheel_target_position() -> Vector3:
	if is_instance_valid(target_wheel_node):
		return target_wheel_node.global_position
	if is_instance_valid(target_aircraft):
		return target_aircraft.global_position + wheel_position_offset
	return global_position

func _get_deck_planar_axes() -> Dictionary:
	var carrier: Node3D = get_parent() as Node3D
	var deck_x: Vector3 = Vector3.RIGHT
	var deck_z: Vector3 = Vector3.FORWARD
	if is_instance_valid(carrier):
		deck_x = _project_planar(carrier.global_transform.basis.x, Vector3.RIGHT)
		deck_z = _project_planar(carrier.global_transform.basis.z, Vector3.FORWARD)
	# Keep an orthonormal planar pair.
	deck_z = _project_planar(deck_z, Vector3.FORWARD)
	if absf(deck_x.dot(deck_z)) > 0.01:
		deck_z = _project_planar(Vector3.UP.cross(deck_x), Vector3.FORWARD)
	return {"x": deck_x, "z": deck_z}

func _project_planar(dir: Vector3, fallback: Vector3) -> Vector3:
	var planar := Vector3(dir.x, 0.0, dir.z)
	if planar.length_squared() <= 0.0001:
		planar = Vector3(fallback.x, 0.0, fallback.z)
	if planar.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return planar.normalized()
