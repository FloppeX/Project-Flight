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
## Local rotation axis for the LEFT wing.  Right wing mirrors the Z component.
## Default (0,0,1) = rotate around the fore-aft axis → tip goes up.
@export var fold_axis: Vector3 = Vector3(0.0, 0.0, 1.0)

var _left_wing:  Node3D
var _right_wing: Node3D
var _fold_t: float = 0.0   # 0.0 = unfolded, 1.0 = fully folded
var _snapped: bool = false  # true after first-frame snap

func _ready() -> void:
	var body := get_parent().get_node_or_null("Aircraft 2 body") as Node3D
	if body:
		_left_wing  = body.get_node_or_null("left outer wing")  as Node3D
		_right_wing = body.get_node_or_null("right outer wing") as Node3D
	if not _left_wing or not _right_wing:
		push_warning("[WingFold] Wing nodes not found — check GLB node names")

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

	# Left wing rotates around fold_axis; right wing mirrors the Z component
	# so both tips fold upward symmetrically.
	_left_wing.rotation  = fold_axis * angle
	_right_wing.rotation = Vector3(fold_axis.x, fold_axis.y, -fold_axis.z) * angle
