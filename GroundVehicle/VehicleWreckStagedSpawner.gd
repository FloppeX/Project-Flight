extends Node

## Small, temporary coordinator that spreads one vehicle's expensive procedural
## wreck construction over a short presentation window. Gameplay destruction has
## already happened before this node is created; this owns visuals only.

const STEP_COUNT: int = 7

var _wreck_parent_ref: WeakRef = null
var _wreck_transform: Transform3D = Transform3D.IDENTITY
var _inherited_velocity: Vector3 = Vector3.ZERO
var _spread_duration_s: float = 0.28
var _elapsed_s: float = 0.0
var _next_step: int = 0


func configure(
	wreck_parent: Node3D,
	wreck_transform: Transform3D,
	inherited_velocity: Vector3,
	spread_duration_s: float
) -> void:
	_wreck_parent_ref = weakref(wreck_parent)
	_wreck_transform = wreck_transform
	_inherited_velocity = inherited_velocity
	_spread_duration_s = maxf(spread_duration_s, 0.01)


func _process(delta: float) -> void:
	var parent_object: Object = _wreck_parent_ref.get_ref() if _wreck_parent_ref != null else null
	if not parent_object is Node3D or not is_instance_valid(parent_object):
		queue_free()
		return
	var wreck_parent := parent_object as Node3D
	_elapsed_s += maxf(delta, 0.0)
	var final_step_index := maxi(STEP_COUNT - 1, 1)
	var due_time_s := _spread_duration_s * float(_next_step) / float(final_step_index)
	if _elapsed_s < due_time_s:
		return
	# Never catch up multiple construction steps in one rendered frame. A slow
	# frame extends the visual breakup rather than compounding the hitch.
	VehicleWreck.spawn_staged_step(wreck_parent, _wreck_transform, _inherited_velocity, _next_step)
	_next_step += 1
	if _next_step >= STEP_COUNT:
		queue_free()
