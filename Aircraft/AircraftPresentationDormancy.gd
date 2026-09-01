extends RefCounted
class_name AircraftPresentationDormancy

## Temporarily removes player-facing aircraft branches while retaining the exact
## node instances for later restoration. This also works before the aircraft is
## added to the SceneTree, allowing virtual flights to avoid running _ready() on
## dormant cameras, cockpit UI, audio, and occupants. Flight, weapons, targeting,
## damage, and aircraft visuals are deliberately left attached.

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
## Restore dependencies before the controller that discovers and coordinates
## them. Each entry is still returned to its authored sibling index.
const STAGED_RESTORE_ORDER: Array[StringName] = [
	&"CameraCockpit",
	&"CameraTarget",
	&"CameraChase",
	&"CameraCinematic",
	&"CockpitPilot",
	&"HeadsUpDisplay",
	&"InstrumentPanel",
	&"CockpitCanopyVisibility",
	&"CameraController",
	&"AudioManager3D",
]
const CAMERA_CAPABILITY_META: StringName = &"presentation_dormant_camera_capable"
const COCKPIT_PILOT_DETACHED_META: StringName = &"presentation_dormant_cockpit_pilot_detached"

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
	_set_cockpit_pilot_presentation_active(aircraft, false)
	var has_camera_capability := bool(aircraft.get_meta(CAMERA_CAPABILITY_META, false))
	var entries_to_detach: Array[Dictionary] = []
	for root_name in PRESENTATION_ROOT_NAMES:
		var node := aircraft.get_node_or_null(NodePath(String(root_name)))
		if node == null:
			continue
		if root_name in [&"CameraController", &"CameraCockpit", &"CameraChase", &"CameraCinematic"]:
			has_camera_capability = true
		var parent := node.get_parent()
		if parent == null:
			continue
		entries_to_detach.append({
			"node": node,
			"parent": parent,
			"index": node.get_index(),
			"owner": node.owner,
			"root_name": root_name,
			"node_count": _count_subtree_nodes(node),
		})
		_detached_node_count += int(entries_to_detach[-1].get("node_count", 0))
	# Removing in reverse preserves every node's authored sibling index. The
	# restoration order therefore remains deterministic even when several direct
	# children occupied consecutive slots in the aircraft scene.
	for entry_index in range(entries_to_detach.size() - 1, -1, -1):
		var entry: Dictionary = entries_to_detach[entry_index]
		var node: Node = entry.get("node") as Node
		var parent: Node = entry.get("parent") as Node
		if node != null and parent != null and node.get_parent() == parent:
			# Scene-instantiated children normally name the aircraft as owner. Clear
			# that relationship while the owner is no longer their ancestor; restore()
			# reinstates it after the child is attached again.
			node.owner = null
			parent.remove_child(node)
			if StringName(str(entry.get("root_name", ""))) == &"CockpitPilot":
				# aircraft._ready() has a compatibility fallback that creates a
				# missing pilot mount. Tell it this authored mount still exists but
				# is temporarily owned by the dormancy session.
				aircraft.set_meta(COCKPIT_PILOT_DETACHED_META, true)
	_detached_entries = entries_to_detach
	aircraft.set_meta(CAMERA_CAPABILITY_META, has_camera_capability)
	return _detached_node_count


func restore(activate_presentation: bool = true) -> void:
	var aircraft := _get_aircraft()
	if aircraft == null:
		return
	if _detached_entries.is_empty():
		if activate_presentation:
			_set_cockpit_pilot_presentation_active(aircraft, true)
		return
	_detached_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("index", 0)) < int(b.get("index", 0))
	)
	for entry in _detached_entries:
		_restore_entry(entry)
	_detached_entries.clear()
	_detached_node_count = 0
	_set_cockpit_pilot_presentation_active(aircraft, activate_presentation)


## Restores exactly one authored presentation root. Large roots remain atomic so
## their own _ready() dependency assumptions are preserved, while the caller can
## distribute the independent roots across separate frames.
func restore_next_root(activate_when_complete: bool = false) -> Dictionary:
	var result: Dictionary = {
		"restored": false,
		"root_name": "",
		"node_count": 0,
		"remaining_roots": _detached_entries.size(),
		"remaining_nodes": _detached_node_count,
		"complete": _detached_entries.is_empty(),
	}
	var aircraft := _get_aircraft()
	if aircraft == null:
		return result
	if _detached_entries.is_empty():
		if activate_when_complete:
			_set_cockpit_pilot_presentation_active(aircraft, true)
		return result

	var entry_index := _find_next_staged_entry_index()
	var entry: Dictionary = _detached_entries[entry_index]
	_detached_entries.remove_at(entry_index)
	var node_count := maxi(int(entry.get("node_count", 0)), 0)
	var restored := _restore_entry(entry)
	_detached_node_count = maxi(_detached_node_count - node_count, 0)
	var complete := _detached_entries.is_empty()
	if complete:
		_detached_node_count = 0
		_set_cockpit_pilot_presentation_active(aircraft, activate_when_complete)
	result["restored"] = restored
	result["root_name"] = str(entry.get("root_name", ""))
	result["node_count"] = node_count
	result["remaining_roots"] = _detached_entries.size()
	result["remaining_nodes"] = _detached_node_count
	result["complete"] = complete
	return result


func get_detached_root_count() -> int:
	return _detached_entries.size()


func get_detached_root_names() -> Array[String]:
	var names: Array[String] = []
	for entry in _detached_entries:
		names.append(str(entry.get("root_name", "")))
	return names


func is_detached() -> bool:
	return not _detached_entries.is_empty()


func get_detached_node_count() -> int:
	return _detached_node_count


func dispose() -> void:
	# Cache disposal restores ownership but must not wake a cockpit that is not
	# being viewed.
	restore(false)
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


func _find_next_staged_entry_index() -> int:
	for desired_name in STAGED_RESTORE_ORDER:
		for entry_index in range(_detached_entries.size()):
			if StringName(str(_detached_entries[entry_index].get("root_name", ""))) == desired_name:
				return entry_index
	return 0


func _restore_entry(entry: Dictionary) -> bool:
	var node: Node = entry.get("node") as Node
	var parent: Node = entry.get("parent") as Node
	if node == null or parent == null or not is_instance_valid(node) or not is_instance_valid(parent):
		return false
	if node.get_parent() != null:
		var already_restored := node.get_parent() == parent
		if already_restored:
			_clear_root_detached_meta(StringName(str(entry.get("root_name", ""))))
		return already_restored
	parent.add_child(node)
	parent.move_child(
		node,
		clampi(int(entry.get("index", parent.get_child_count() - 1)), 0, parent.get_child_count() - 1)
	)
	var original_owner: Node = entry.get("owner") as Node
	if original_owner != null and is_instance_valid(original_owner) \
			and original_owner.is_ancestor_of(node):
		node.owner = original_owner
	_clear_root_detached_meta(StringName(str(entry.get("root_name", ""))))
	return true


func _clear_root_detached_meta(root_name: StringName) -> void:
	if root_name != &"CockpitPilot":
		return
	var aircraft := _get_aircraft()
	if aircraft != null:
		aircraft.remove_meta(COCKPIT_PILOT_DETACHED_META)


func _set_cockpit_pilot_presentation_active(aircraft: Node, active: bool) -> void:
	_set_occupant_presentation_recursive(aircraft, active)


func _set_occupant_presentation_recursive(node: Node, active: bool) -> void:
	for child_variant in node.get_children():
		var child := child_variant as Node
		if child == null:
			continue
		if child.has_method("is_pooled_aircraft_occupant_mount") \
				and bool(child.call("is_pooled_aircraft_occupant_mount")) \
				and child.has_method("set_presentation_active"):
			child.call("set_presentation_active", active)
		_set_occupant_presentation_recursive(child, active)


func _count_subtree_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_subtree_nodes(child)
	return total
