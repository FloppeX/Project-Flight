extends RefCounted
class_name AircraftPresentationDormancy

## Temporarily removes player-facing aircraft branches from the SceneTree while
## retaining the exact node instances for later restoration. Flight, weapons,
## targeting, damage, and aircraft visuals are deliberately left attached.

const PRESENTATION_ROOT_NAMES: Array[StringName] = [
	&"CameraController",
	&"AudioManager3D",
	&"CameraCockpit",
	&"CockpitPilot",
	&"CameraTarget",
	&"CameraChase",
	&"CameraCinematic",
	&"HeadsUpDisplay",
	&"InstrumentPanel",
	&"CockpitCanopyVisibility",
]
const CAMERA_CAPABILITY_META: StringName = &"presentation_dormant_camera_capable"

var _aircraft_ref: WeakRef
var _detached_entries: Array[Dictionary] = []
var _detached_node_count: int = 0


func _init(aircraft: Node = null) -> void:
	_aircraft_ref = weakref(aircraft) if aircraft != null else null


func detach() -> int:
	if not _detached_entries.is_empty():
		return _detached_node_count
	var aircraft := _get_aircraft()
	if aircraft == null:
		return 0
	var has_camera_capability := bool(aircraft.get_meta(CAMERA_CAPABILITY_META, false))
	for root_name in PRESENTATION_ROOT_NAMES:
		var node := aircraft.get_node_or_null(NodePath(String(root_name)))
		if node == null:
			continue
		if root_name in [&"CameraController", &"CameraCockpit", &"CameraChase", &"CameraCinematic"]:
			has_camera_capability = true
		var parent := node.get_parent()
		if parent == null:
			continue
		_detached_entries.append({
			"node": node,
			"parent": parent,
			"index": node.get_index(),
		})
		_detached_node_count += _count_subtree_nodes(node)
		parent.remove_child(node)
	aircraft.set_meta(CAMERA_CAPABILITY_META, has_camera_capability)
	return _detached_node_count


func restore() -> void:
	if _detached_entries.is_empty():
		return
	_detached_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("index", 0)) < int(b.get("index", 0))
	)
	for entry in _detached_entries:
		var node: Node = entry.get("node") as Node
		var parent: Node = entry.get("parent") as Node
		if node == null or parent == null or not is_instance_valid(node) or not is_instance_valid(parent):
			continue
		if node.get_parent() != null:
			continue
		parent.add_child(node)
		parent.move_child(node, clampi(int(entry.get("index", parent.get_child_count() - 1)), 0, parent.get_child_count() - 1))
	_detached_entries.clear()
	_detached_node_count = 0


func is_detached() -> bool:
	return not _detached_entries.is_empty()


func get_detached_node_count() -> int:
	return _detached_node_count


func dispose() -> void:
	restore()
	_aircraft_ref = null


func discard_detached() -> void:
	for entry in _detached_entries:
		var node: Node = entry.get("node") as Node
		if node == null or not is_instance_valid(node):
			continue
		if node.get_parent() == null:
			node.free()
	_detached_entries.clear()
	_detached_node_count = 0
	_aircraft_ref = null


func _get_aircraft() -> Node:
	if _aircraft_ref == null:
		return null
	var aircraft := _aircraft_ref.get_ref() as Node
	if aircraft == null or not is_instance_valid(aircraft):
		return null
	return aircraft


func _count_subtree_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_subtree_nodes(child)
	return total
