extends Node
class_name WingFold

## Animates outer wing fold/unfold on Aircraft_2.
## Wings fold when the parking brake is set, unfold when it is released.
##
## The fold pivot is the wing node's local origin — make sure the origin
## is at the fold hinge in Blender, not the mesh centre.

## Degrees the wing tip rotates upward when fully folded.
@export var fold_angle_deg: float = 120.0
## Time in seconds to complete a full fold or unfold.
@export var fold_duration:  float = 2.0
## Local hinge axis for the LEFT wing. Right wing mirrors the Z component.
## Default is tilted 15 degrees upward from the fore-aft axis so folded wings
## point slightly up and back.
@export var fold_axis: Vector3 = Vector3(0.0, 0.258819, 0.965926)

var _left_wing:  Node3D
var _right_wing: Node3D
var _fold_t: float = 0.0   # 0.0 = unfolded, 1.0 = fully folded
var _snapped: bool = false  # true after first-frame snap
var _left_rest_quat: Quaternion
var _right_rest_quat: Quaternion
var _left_rest_pos: Vector3
var _right_rest_pos: Vector3

func _ready() -> void:
	var body := get_parent().get_node_or_null("Aircraft 2 body") as Node3D
	if body:
		_left_wing  = body.get_node_or_null("left outer wing")  as Node3D
		_right_wing = body.get_node_or_null("right outer wing") as Node3D
	if not _left_wing or not _right_wing:
		push_warning("[WingFold] Wing nodes not found — check GLB node names")
		return
	_left_rest_pos = _left_wing.position
	_right_rest_pos = _right_wing.position
	_left_rest_quat = _left_wing.quaternion
	_right_rest_quat = _right_wing.quaternion
	# Store the exact authored rest local transforms for livery anchoring.
	_left_wing.set_meta("livery_rest_transform_local", _left_wing.transform)
	_right_wing.set_meta("livery_rest_transform_local", _right_wing.transform)

func _process(delta: float) -> void:
	if not _left_wing or not _right_wing:
		return

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
	_fold_t = move_toward(_fold_t, target, speed)

	var angle := deg_to_rad(fold_angle_deg) * _fold_t
	_apply_fold_pose(angle)

func _apply_fold_pose(angle: float) -> void:
	var left_axis := fold_axis.normalized()
	if left_axis.length_squared() <= 0.0001:
		left_axis = Vector3.FORWARD

	_left_wing.quaternion = _left_rest_quat * Quaternion(left_axis, angle)
	# Mirror the full hinge rotation on the opposite wing so the aft/up tilt
	# stays symmetrical when the fold axis itself is canted.
	_right_wing.quaternion = _right_rest_quat * Quaternion(left_axis, -angle)
