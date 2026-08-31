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
	# Scene removal can leave valid Node3D references alive until queue_free is
	# committed. Global transforms and frustum queries are invalid during that
	# interval, so treat the node as irrelevant until both ends share a world.
	if not context.is_inside_tree() or not node.is_inside_tree():
		return false
	if VISUAL_FOCUS_HELPER.is_node_in_target_camera_focus(context, node):
		return true
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return false
	var node_world: World3D = node.get_world_3d()
	var camera_world: World3D = camera.get_world_3d()
	if node_world == null or camera_world == null or node_world != camera_world:
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
