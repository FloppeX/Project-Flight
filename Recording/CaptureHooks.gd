extends RefCounted
## Presentation-only lifecycle hooks. Groups also find effects already alive
## when Record is pressed. No gameplay timers, RNG, damage or pooling changes.
static func begin(node: Node3D, kind: String) -> void:
	if not node.is_in_group("recording_transient"):
		# Rockets/bombs and detached parts can queue_free directly. Observe their
		# final pose before deletion; pooled reparenting also consumes this hook.
		node.tree_exiting.connect(_exiting.bind(weakref(node)), CONNECT_ONE_SHOT)
	node.add_to_group("recording_transient")
	node.set_meta("recording_kind", kind)
	var mode := node.get_node_or_null("/root/RecordingMode")
	if mode != null and mode.recording: mode.capture_transient(node, kind)

static func end(node: Node3D) -> void:
	var mode := node.get_node_or_null("/root/RecordingMode")
	if mode != null and mode.recording: mode.end_transient(node.get_instance_id())
	node.remove_from_group("recording_transient")

static func _exiting(node_ref: WeakRef) -> void:
	var node: Variant = node_ref.get_ref()
	if is_instance_valid(node): end(node)
