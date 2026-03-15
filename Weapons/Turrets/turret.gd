extends Node3D
class_name Turret

# --- Output Signals ---
signal target_acquired(target: Node3D)
signal target_lost()
signal fired()

# --- Configuration ---
@export_group("Aiming Restrictions")
@export var turn_speed: float = 60.0  # degrees per second
@export var pitch_speed: float = 60.0 # degrees per second
@export var max_pitch_up: float = 85.0 # degrees
@export var max_pitch_down: float = -15.0 # degrees

@export_group("References")
@export var base_mesh: Node3D # The Y-axis rotation part (visual only)
@export var barrel_mount: Node3D # The X-axis pitch part (child of base)
@export var firing_points: Array[Node3D] = [] # Where projectiles spawn
@export var enable_barrel_recoil: bool = false
@export_group("Rig Axes")
@export var auto_detect_barrel_axes: bool = false
@export var barrel_forward_axis_local: Vector3 = Vector3.UP
@export var barrel_pitch_axis_local: Vector3 = Vector3.RIGHT

# --- State ---
var current_target: Node3D = null
var current_target_position: Vector3 = Vector3.ZERO
var is_aiming_at_point: bool = false

var _current_fire_point_idx: int = 0
var _turret_rest_rotation: Vector3 = Vector3.ZERO
var _barrel_rest_rotation: Vector3 = Vector3.ZERO
var _barrel_rest_basis: Basis = Basis.IDENTITY
var _barrel_rest_scale: Vector3 = Vector3.ONE
var _barrel_rest_rotation_basis: Basis = Basis.IDENTITY
var _barrel_rest_quaternion: Quaternion = Quaternion.IDENTITY
var _barrel_forward_axis_local: Vector3 = Vector3.FORWARD
var _barrel_pitch_axis_local: Vector3 = Vector3.RIGHT
var _barrel_current_pitch: float = 0.0

func _ready() -> void:
	_turret_rest_rotation = rotation
	if not barrel_mount:
		push_warning("Turret %s: barrel_mount not assigned!" % name)
	else:
		_barrel_rest_rotation = barrel_mount.rotation
		_barrel_rest_basis = barrel_mount.transform.basis
		_barrel_rest_scale = barrel_mount.scale
		_barrel_rest_rotation_basis = _barrel_rest_basis.orthonormalized()
		_barrel_rest_quaternion = Quaternion(_barrel_rest_rotation_basis)
		if auto_detect_barrel_axes:
			_barrel_forward_axis_local = _determine_barrel_forward_axis_local()
			_barrel_pitch_axis_local = _determine_barrel_pitch_axis_local()
		else:
			_barrel_forward_axis_local = barrel_forward_axis_local.normalized()
			_barrel_pitch_axis_local = barrel_pitch_axis_local.normalized()
		_barrel_current_pitch = 0.0

func set_target(target: Node3D) -> void:
	if current_target != target:
		current_target = target
		if target:
			emit_signal("target_acquired", target)
		else:
			emit_signal("target_lost")
			is_aiming_at_point = false

func aim_at_point(point: Vector3) -> void:
	current_target_position = point
	is_aiming_at_point = true

# Called by TurretController every physics frame — no _process needed.
func tick(delta: float, target_pos: Vector3) -> void:
	if not barrel_mount:
		return
	var desired_target: Vector3 = current_target_position if is_aiming_at_point else target_pos
	_rotate_towards(desired_target, delta)

func _rotate_towards(target_pos: Vector3, delta: float) -> void:
	# 1. Yaw: rotate self around world Y so barrel faces target horizontally.
	# The turret base only yaws in its own local space. No local pitch/roll.
	var turret_parent := get_parent_node_3d()
	if turret_parent == null:
		return
	var local_target: Vector3 = turret_parent.to_local(target_pos) - position
	local_target.y = 0.0
	if local_target.length() > 0.1:
		var desired_yaw: float = _turret_rest_rotation.y + atan2(local_target.x, local_target.z)
		var max_turn: float = deg_to_rad(turn_speed) * delta
		var new_yaw: float = rotate_toward(rotation.y, desired_yaw, max_turn)
		rotation = Vector3(_turret_rest_rotation.x, new_yaw, _turret_rest_rotation.z)

	# 2. Pitch: the barrel only elevates around its hinge axis from the rest pose.
	var barrel_parent := barrel_mount.get_parent_node_3d()
	if barrel_parent == null:
		return
	var target_dir_parent: Vector3 = (barrel_parent.to_local(target_pos) - barrel_mount.position).normalized()
	if target_dir_parent.length_squared() <= 0.0001:
		return
	var target_dir_rest_local: Vector3 = (_barrel_rest_basis.inverse() * target_dir_parent).normalized()
	var pitch_plane_dir: Vector3 = target_dir_rest_local.slide(_barrel_pitch_axis_local).normalized()
	if pitch_plane_dir.length_squared() <= 0.0001:
		return
	var target_pitch: float = _signed_angle_around_axis(_barrel_forward_axis_local, pitch_plane_dir, _barrel_pitch_axis_local)
	target_pitch = clamp(
		target_pitch,
		deg_to_rad(max_pitch_down),
		deg_to_rad(max_pitch_up)
	)
	var max_p: float = deg_to_rad(pitch_speed) * delta
	_barrel_current_pitch = move_toward(_barrel_current_pitch, target_pitch, max_p)
	barrel_mount.quaternion = _barrel_rest_quaternion * Quaternion(_barrel_pitch_axis_local.normalized(), _barrel_current_pitch)
	barrel_mount.scale = _barrel_rest_scale

func get_aim_angle_to_target() -> float:
	if not _has_target_position():
		return -1.0
	var target_pos: Vector3 = _get_target_position()
	var muzzle_transform: Transform3D = _get_current_muzzle_transform()
	var to_target: Vector3 = target_pos - muzzle_transform.origin
	if to_target.length_squared() <= 0.01:
		return 0.0
	var forward: Vector3 = muzzle_transform.basis.z
	if forward.length_squared() <= 0.01:
		return -1.0
	return rad_to_deg(acos(clamp(forward.normalized().dot(to_target.normalized()), -1.0, 1.0)))

func is_aimed_at_target(tolerance_degrees: float = 5.0) -> bool:
	var angle := get_aim_angle_to_target()
	return angle >= 0.0 and angle <= tolerance_degrees

func get_fallback_firing_origin() -> Vector3:
	if not barrel_mount or not is_instance_valid(barrel_mount):
		return global_position
	if barrel_mount is MeshInstance3D:
		var mesh_instance := barrel_mount as MeshInstance3D
		var aabb: AABB = mesh_instance.get_aabb()
		var local_muzzle: Vector3 = aabb.position + aabb.size * 0.5 + (_barrel_forward_axis_local * _get_barrel_forward_half_extent(aabb))
		return mesh_instance.to_global(local_muzzle)
	return barrel_mount.global_position

func get_next_firing_transform() -> Transform3D:
	var valid_points: Array[Node3D] = []
	for point in firing_points:
		if point and is_instance_valid(point):
			valid_points.append(point)

	var origin_transform: Transform3D
	if valid_points.is_empty() and barrel_mount:
		origin_transform = Transform3D(barrel_mount.global_transform.basis, get_fallback_firing_origin())
	elif valid_points.is_empty():
		origin_transform = global_transform
	else:
		var point := valid_points[_current_fire_point_idx % valid_points.size()]
		_current_fire_point_idx = (_current_fire_point_idx + 1) % valid_points.size()
		origin_transform = point.global_transform

	if not _has_target_position():
		return origin_transform
	var target_pos: Vector3 = _get_target_position()

	var fire_dir: Vector3 = (target_pos - origin_transform.origin).normalized()
	if fire_dir.length_squared() <= 0.0001:
		return origin_transform
	var up := Vector3.UP
	var right := up.cross(fire_dir).normalized()
	if right.length_squared() <= 0.0001:
		right = Vector3.RIGHT
	var corrected_up: Vector3 = fire_dir.cross(right).normalized()
	return Transform3D(Basis(right, corrected_up, fire_dir), origin_transform.origin)

func _get_current_muzzle_transform() -> Transform3D:
	var valid_points: Array[Node3D] = []
	for point in firing_points:
		if point and is_instance_valid(point):
			valid_points.append(point)

	if not valid_points.is_empty():
		return valid_points[_current_fire_point_idx % valid_points.size()].global_transform

	if barrel_mount and is_instance_valid(barrel_mount):
		var barrel_forward: Vector3 = (barrel_mount.global_transform.basis * _barrel_forward_axis_local).normalized()
		if barrel_forward.length_squared() <= 0.0001:
			barrel_forward = barrel_mount.global_transform.basis.z.normalized()
		var up: Vector3 = barrel_mount.global_transform.basis.y.normalized()
		if up.length_squared() <= 0.0001:
			up = Vector3.UP
		var right: Vector3 = up.cross(barrel_forward).normalized()
		if right.length_squared() <= 0.0001:
			right = Vector3.RIGHT
		var corrected_up: Vector3 = barrel_forward.cross(right).normalized()
		return Transform3D(Basis(right, corrected_up, barrel_forward), get_fallback_firing_origin())

	return global_transform

func fire() -> void:
	emit_signal("fired")
	if enable_barrel_recoil and barrel_mount:
		var tween := create_tween()
		var original_z := barrel_mount.position.z
		tween.tween_property(barrel_mount, "position:z", original_z + 0.1, 0.05)
		tween.tween_property(barrel_mount, "position:z", original_z, 0.1)

func _has_target_position() -> bool:
	return is_aiming_at_point or (current_target and is_instance_valid(current_target))

func _get_target_position() -> Vector3:
	if is_aiming_at_point:
		return current_target_position
	if current_target and is_instance_valid(current_target):
		return current_target.global_position
	return Vector3.ZERO

func _determine_barrel_forward_axis_local() -> Vector3:
	if not (barrel_mount is MeshInstance3D):
		return Vector3.FORWARD
	var mesh_instance := barrel_mount as MeshInstance3D
	var aabb: AABB = mesh_instance.get_aabb()
	var extents := [aabb.size.x, aabb.size.y, aabb.size.z]
	var dominant_idx: int = 0
	var dominant_size: float = extents[0]
	for i in range(1, extents.size()):
		if extents[i] > dominant_size:
			dominant_idx = i
			dominant_size = extents[i]

	var axis := Vector3.FORWARD
	match dominant_idx:
		0:
			axis = Vector3.RIGHT
		1:
			axis = Vector3.UP
		2:
			axis = Vector3.FORWARD

	var barrel_parent := barrel_mount.get_parent_node_3d()
	if barrel_parent == null:
		return axis
	var turret_forward_parent: Vector3 = (barrel_parent.global_basis.inverse() * global_basis.z).normalized()
	if turret_forward_parent.length_squared() <= 0.0001:
		return axis
	var positive_dir: Vector3 = (_barrel_rest_basis * axis).normalized()
	var negative_dir: Vector3 = (_barrel_rest_basis * -axis).normalized()
	return axis if positive_dir.dot(turret_forward_parent) >= negative_dir.dot(turret_forward_parent) else -axis

func _determine_barrel_pitch_axis_local() -> Vector3:
	var barrel_parent := barrel_mount.get_parent_node_3d()
	if barrel_parent == null:
		return Vector3.RIGHT
	if absf(_barrel_forward_axis_local.dot(Vector3.UP)) > 0.9:
		return Vector3.RIGHT
	if absf(_barrel_forward_axis_local.dot(Vector3.RIGHT)) > 0.9:
		return Vector3.UP
	if absf(_barrel_forward_axis_local.dot(Vector3.FORWARD)) > 0.9:
		return Vector3.RIGHT
	var parent_up_parent: Vector3 = (barrel_parent.global_basis.inverse() * Vector3.UP).normalized()
	if parent_up_parent.length_squared() <= 0.0001:
		parent_up_parent = Vector3.UP
	var rest_forward_parent: Vector3 = (_barrel_rest_basis * _barrel_forward_axis_local).normalized()
	var best_axis: Vector3 = Vector3.RIGHT
	var best_score: float = -INF
	var test_angle: float = deg_to_rad(5.0)

	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		if absf(axis.dot(_barrel_forward_axis_local)) > 0.9:
			continue
		var rotated_positive_parent: Vector3 = (_barrel_rest_basis * (Basis(axis, test_angle) * _barrel_forward_axis_local)).normalized()
		var rotated_negative_parent: Vector3 = (_barrel_rest_basis * (Basis(axis, -test_angle) * _barrel_forward_axis_local)).normalized()
		var positive_score: float = _score_pitch_axis_candidate(rest_forward_parent, rotated_positive_parent, parent_up_parent)
		var negative_score: float = _score_pitch_axis_candidate(rest_forward_parent, rotated_negative_parent, parent_up_parent)
		if positive_score > best_score:
			best_score = positive_score
			best_axis = axis
		if negative_score > best_score:
			best_score = negative_score
			best_axis = -axis

	return best_axis.normalized()

func _score_pitch_axis_candidate(rest_forward_parent: Vector3, rotated_forward_parent: Vector3, parent_up_parent: Vector3) -> float:
	var pitch_gain: float = rotated_forward_parent.dot(parent_up_parent) - rest_forward_parent.dot(parent_up_parent)
	var rest_flat: Vector3 = (rest_forward_parent - parent_up_parent * rest_forward_parent.dot(parent_up_parent)).normalized()
	var rotated_flat: Vector3 = (rotated_forward_parent - parent_up_parent * rotated_forward_parent.dot(parent_up_parent)).normalized()
	var yaw_penalty: float = 0.0
	if rest_flat.length_squared() > 0.0001 and rotated_flat.length_squared() > 0.0001:
		yaw_penalty = absf(rest_flat.signed_angle_to(rotated_flat, parent_up_parent))
	return pitch_gain - yaw_penalty * 0.35

func _get_barrel_forward_half_extent(aabb: AABB) -> float:
	var axis := _barrel_forward_axis_local.abs()
	if axis.x > 0.5:
		return aabb.size.x * 0.5
	if axis.y > 0.5:
		return aabb.size.y * 0.5
	return aabb.size.z * 0.5

func _signed_angle_around_axis(from_dir: Vector3, to_dir: Vector3, axis: Vector3) -> float:
	var from_n: Vector3 = from_dir.normalized()
	var to_n: Vector3 = to_dir.normalized()
	var axis_n: Vector3 = axis.normalized()
	var cross_term: float = axis_n.dot(from_n.cross(to_n))
	var dot_term: float = clamp(from_n.dot(to_n), -1.0, 1.0)
	return atan2(cross_term, dot_term)
