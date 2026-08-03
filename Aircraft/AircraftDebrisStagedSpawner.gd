extends Node

var _parent_ref: WeakRef = null
var _source_transform: Transform3D = Transform3D.IDENTITY
var _inherited_velocity: Vector3 = Vector3.ZERO
var _config: Dictionary = {}
var _spread_duration_s: float = 0.28
var _elapsed_s: float = 0.0
var _next_index: int = 0


func configure(
	parent: Node,
	source_transform: Transform3D,
	inherited_velocity: Vector3,
	config: Dictionary,
	spread_duration_s: float
) -> void:
	_parent_ref = weakref(parent)
	_source_transform = source_transform
	_inherited_velocity = inherited_velocity
	_config = config.duplicate()
	_spread_duration_s = maxf(spread_duration_s, 0.01)


func _process(delta: float) -> void:
	var parent_object: Object = _parent_ref.get_ref() if _parent_ref != null else null
	if not parent_object is Node or not is_instance_valid(parent_object):
		queue_free()
		return
	var chunk_count := maxi(int(_config.get("chunk_count", 0)), 0)
	if _next_index >= chunk_count:
		queue_free()
		return
	_elapsed_s += maxf(delta, 0.0)
	var due_time_s := _spread_duration_s * float(_next_index) / float(maxi(chunk_count - 1, 1))
	if _elapsed_s < due_time_s:
		return
	# Never create more than one procedural mesh/collider per rendered frame.
	var burst_script := load("res://Aircraft/AircraftDebrisBurst.gd") as Script
	if burst_script != null:
		burst_script.call(
			"spawn_chunk",
			parent_object as Node,
			_source_transform,
			_inherited_velocity,
			_config,
			_next_index
		)
	_next_index += 1
	if _next_index >= chunk_count:
		queue_free()
