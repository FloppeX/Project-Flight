extends RefCounted

## Shared camera relevance test for simulation-detail throttling.
## Callers own the cache interval so the check itself stays stateless and easy to disable.

const VISUAL_FOCUS_HELPER = preload("res://Effects/VisualFocus.gd")

static func is_node_camera_relevant(
	context: Node,
	node: Node3D,
	camera: Camera3D,
	padding_m: float = 0.0
) -> bool:
	if context == null or node == null or not is_instance_valid(node):
		return false
	if VISUAL_FOCUS_HELPER.is_node_in_target_camera_focus(context, node):
		return true
	if camera == null or not is_instance_valid(camera):
		return false

	var center := node.global_position
	if camera.is_position_in_frustum(center):
		return true
	var padding := maxf(padding_m, 0.0)
	if padding <= 0.0:
		return false
	for offset in [
		Vector3.UP * padding,
		Vector3.DOWN * padding,
		Vector3.RIGHT * padding,
		Vector3.LEFT * padding,
		Vector3.FORWARD * padding,
		Vector3.BACK * padding,
	]:
		if camera.is_position_in_frustum(center + offset):
			return true
	return false
