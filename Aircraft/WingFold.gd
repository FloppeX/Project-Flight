extends Node
class_name WingFold

## Animates outer wing fold/unfold on Aircraft_2.
## Wings fold when the parking brake is set, unfold when it is released.
##
## Uses the authored node origins unless model-space hinge overrides are enabled.

## Degrees the wing tip rotates upward when fully folded.
@export var fold_angle_deg: float = 120.0
## Time in seconds to complete a full fold or unfold.
@export var fold_duration:  float = 2.0
## Hinge axis for the LEFT wing, mirrored on the right. Local by default;
## expressed in the wing parent's space when model-space hinges are enabled.
## Default is tilted 15 degrees upward from the fore-aft axis so folded wings
## point slightly up and back.
@export var fold_axis: Vector3 = Vector3(0.0, 0.258819, 0.965926)
@export var stable_poll_interval_s: float = 0.2
@export var broad_wing_collider_path: NodePath = NodePath("../WingCollider")
## Optional hinge lines in the wing parent's model space. These let a revised
## mesh retain its authored origin and non-uniform scale.
@export var use_model_space_hinges: bool = false
@export var left_hinge_origin: Vector3 = Vector3.ZERO
@export var right_hinge_origin: Vector3 = Vector3.ZERO

var _left_wing:  Node3D
var _right_wing: Node3D
var _broad_wing_collider: CollisionShape3D
var _fold_t: float = 0.0   # 0.0 = unfolded, 1.0 = fully folded
var _snapped: bool = false  # true after first-frame snap
var _left_rest_quat: Quaternion
var _right_rest_quat: Quaternion
var _left_rest_pos: Vector3
var _right_rest_pos: Vector3
var _stable_poll_timer_s: float = 0.0
var _left_authored_transform: Transform3D
var _right_authored_transform: Transform3D

func _ready() -> void:
	_broad_wing_collider = get_node_or_null(broad_wing_collider_path) as CollisionShape3D
	_cache_wing_nodes(true)


func _cache_wing_nodes(warn_when_missing: bool) -> bool:
	_left_wing = null
	_right_wing = null
	var body := get_parent().get_node_or_null("Aircraft 2 body") as Node3D
	if body:
		_left_wing  = body.get_node_or_null("left outer wing")  as Node3D
		_right_wing = body.get_node_or_null("right outer wing") as Node3D
	if not _left_wing or not _right_wing:
		if warn_when_missing:
			push_warning("[WingFold] Wing nodes not found — check GLB node names")
		return false
	_left_authored_transform = _left_wing.get_meta("livery_rest_transform_local", _left_wing.transform)
	_right_authored_transform = _right_wing.get_meta("livery_rest_transform_local", _right_wing.transform)
	_left_rest_pos = _left_authored_transform.origin
	_right_rest_pos = _right_authored_transform.origin
	_left_rest_quat = _left_authored_transform.basis.get_rotation_quaternion()
	_right_rest_quat = _right_authored_transform.basis.get_rotation_quaternion()
	# Store the exact authored rest local transforms for livery anchoring.
	_left_wing.set_meta("livery_rest_transform_local", _left_authored_transform)
	_right_wing.set_meta("livery_rest_transform_local", _right_authored_transform)
	return true

func _process(delta: float) -> void:
	if not _left_wing or not _right_wing:
		return
	var stable: bool = _snapped and (_fold_t <= 0.0 or _fold_t >= 1.0)
	if stable:
		_stable_poll_timer_s -= delta
		if _stable_poll_timer_s > 0.0:
			return
		_stable_poll_timer_s = maxf(stable_poll_interval_s, 0.02)

	var parent    := get_parent()
	var braked    := parent.has_meta("parking_brake") and bool(parent.get_meta("parking_brake"))
	var transport := parent.has_meta("carrier_transport_mode") and bool(parent.get_meta("carrier_transport_mode"))
	var should_fold := braked or transport
	var target := 1.0 if should_fold else 0.0

	# Snap to folded instantly on first frame if spawned in transport/hangar mode
	if not _snapped:
		_snapped = true
		if should_fold:
			_fold_t = 1.0

	var speed := delta / maxf(fold_duration, 0.01)
	var previous_fold_t: float = _fold_t
	_fold_t = move_toward(_fold_t, target, speed)

	if not is_equal_approx(previous_fold_t, _fold_t) or not stable:
		var angle := deg_to_rad(fold_angle_deg) * _fold_t
		_apply_fold_pose(angle)


func prepare_technical_index_preview() -> bool:
	if not _cache_wing_nodes(false):
		return false
	set_technical_index_preview_fraction(0.0)
	return true


func set_technical_index_preview_fraction(fold_fraction: float) -> void:
	_fold_t = clampf(fold_fraction, 0.0, 1.0)
	_snapped = true
	_apply_fold_pose(deg_to_rad(fold_angle_deg) * _fold_t)


func get_technical_index_preview_fraction() -> float:
	return _fold_t


func get_technical_index_preview_duration() -> float:
	return maxf(fold_duration, 0.01)


func get_technical_index_preview_kind() -> StringName:
	return &"wings"

func _apply_fold_pose(angle: float) -> void:
	var left_axis := fold_axis.normalized()
	if left_axis.length_squared() <= 0.0001:
		left_axis = Vector3.FORWARD

	if use_model_space_hinges:
		var left_rotation := Basis(left_axis, angle)
		# Mirroring an axial rotation across X reverses its Y/Z components.
		var right_axis := Vector3(left_axis.x, -left_axis.y, -left_axis.z)
		var right_rotation := Basis(right_axis, angle)
		_left_wing.transform = Transform3D(left_rotation,
			left_hinge_origin - left_rotation * left_hinge_origin) * _left_authored_transform
		_right_wing.transform = Transform3D(right_rotation,
			right_hinge_origin - right_rotation * right_hinge_origin) * _right_authored_transform
	else:
		_left_wing.quaternion = _left_rest_quat * Quaternion(left_axis, angle)
		_right_wing.quaternion = _right_rest_quat * Quaternion(left_axis, -angle)
	_set_broad_wing_collision_folded(_fold_t > 0.0)


func _set_broad_wing_collision_folded(is_folded_or_moving: bool) -> void:
	# The full-span box only matches the authored unfolded pose. Disabling it
	# during the fold prevents the invisible span hitting elevator geometry.
	# Localized wing colliders supersede it in every pose when installed.
	if is_instance_valid(_broad_wing_collider):
		_broad_wing_collider.disabled = _has_localized_wing_colliders() or is_folded_or_moving


func _has_localized_wing_colliders() -> bool:
	var aircraft := get_parent()
	return (
		aircraft.get_node_or_null("LeftWingDamageCollider") is CollisionShape3D
		and aircraft.get_node_or_null("RightWingDamageCollider") is CollisionShape3D
	)
