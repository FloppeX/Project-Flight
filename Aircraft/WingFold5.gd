extends Node
class_name WingFold5

## Multi-phase wing fold for Aircraft_5.
## Phase 1: Slide outer wing 10 cm laterally outward.
## Phase 2: Rotate 90° on X axis (rear edge tips upward).
## Phase 3 (starts 1s after phase 2 begins): Rotate 90° on Y axis
##          (left wing counter-clockwise, right wing clockwise from above).
## Unfold reverses the sequence.

@export var slide_distance: float = 0.1  ## Lateral slide in meters
@export var phase1_duration: float = 0.5  ## Slide duration
@export var phase2_duration: float = 1.5  ## X-axis rotation duration
@export var phase3_delay: float = 1.0     ## Delay after phase 2 starts before phase 3 begins
@export var phase3_duration: float = 2.5  ## Y-axis rotation duration
@export var x_fold_deg: float = 90.0      ## X-axis fold angle
@export var y_fold_deg: float = 90.0      ## Y-axis fold angle

var _left_wing: Node3D
var _right_wing: Node3D
var _left_rest_pos: Vector3
var _right_rest_pos: Vector3
var _left_rest_quat: Quaternion
var _right_rest_quat: Quaternion

# Animation progress: 0 = unfolded, runs up to total duration when folding
var _anim_time: float = 0.0
var _folding: bool = false
var _snapped: bool = false

# Total animation length
var _total_duration: float

func _ready() -> void:
	_total_duration = phase1_duration + phase3_delay + phase3_duration
	# phase2 runs from phase1_duration to phase1_duration + phase2_duration
	# phase3 runs from phase1_duration + phase3_delay to phase1_duration + phase3_delay + phase3_duration
	# total is the max end time of all phases

	var body := get_parent().get_node_or_null("aircraft_5") as Node3D
	if body:
		_left_wing = body.get_node_or_null("outer wing left") as Node3D
		_right_wing = body.get_node_or_null("outer wing right") as Node3D
	if not _left_wing or not _right_wing:
		push_warning("[WingFold5] Wing nodes not found — need 'outer wing left' / 'outer wing right' under 'aircraft_5'")
		return
	_left_rest_pos = _left_wing.position
	_right_rest_pos = _right_wing.position
	_left_rest_quat = _left_wing.quaternion
	_right_rest_quat = _right_wing.quaternion

func _process(delta: float) -> void:
	if not _left_wing or not _right_wing:
		return

	var parent := get_parent()
	var braked: bool = parent.has_meta("parking_brake") and bool(parent.get_meta("parking_brake"))
	var transport: bool = parent.has_meta("carrier_transport_mode") and bool(parent.get_meta("carrier_transport_mode"))
	var should_fold := braked or transport

	# Snap on first frame if spawned folded
	if not _snapped:
		_snapped = true
		if should_fold:
			_anim_time = _total_duration
			_folding = true

	# Advance or rewind animation time
	if should_fold:
		_anim_time = minf(_anim_time + delta, _total_duration)
		_folding = true
	else:
		_anim_time = maxf(_anim_time - delta, 0.0)
		_folding = false

	_apply_pose()

func _apply_pose() -> void:
	# Phase 1: lateral slide (0 → phase1_duration)
	var slide_t: float = clampf(_anim_time / phase1_duration, 0.0, 1.0)

	# Phase 2: Y rotation starts first (phase1_duration → phase1_duration + phase3_duration)
	var phase2_start := phase1_duration
	var rot_y_t: float = clampf((_anim_time - phase2_start) / phase3_duration, 0.0, 1.0)

	# Phase 3: X rotation starts after delay, overlaps with Y (phase1_duration + phase3_delay → ...)
	var phase3_start := phase1_duration + phase3_delay
	var rot_x_t: float = clampf((_anim_time - phase3_start) / phase2_duration, 0.0, 1.0)

	# Smooth the transitions
	slide_t = _smooth(slide_t)
	rot_x_t = _smooth(rot_x_t)
	rot_y_t = _smooth(rot_y_t)

	var x_angle := deg_to_rad(x_fold_deg) * rot_x_t
	var y_angle := deg_to_rad(y_fold_deg) * rot_y_t

	# Left wing: +X, +Y (mesh is mirrored)
	_left_wing.position = _left_rest_pos + Vector3(slide_distance * slide_t, 0.0, 0.0)
	_left_wing.quaternion = _left_rest_quat * Quaternion(Vector3.RIGHT, x_angle) * Quaternion(Vector3.UP, -y_angle)

	# Right wing: -X, -Y
	_right_wing.position = _right_rest_pos + Vector3(-slide_distance * slide_t, 0.0, 0.0)
	_right_wing.quaternion = _right_rest_quat * Quaternion(Vector3.RIGHT, -x_angle) * Quaternion(Vector3.UP, -y_angle)

func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
