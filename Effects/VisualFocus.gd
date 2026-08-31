extends RefCounted
class_name VisualFocus

## Shared helper for "treat this thing as near-detail because the player is
## actively watching it through a secondary feed such as the target camera."

static func is_node_in_target_camera_focus(context: Node, node: Node3D) -> bool:
	if context == null or node == null or not is_instance_valid(node):
		return false
	if not context.is_inside_tree() or not node.is_inside_tree():
		return false
	var tree: SceneTree = context.get_tree()
	if tree == null:
		return false

	for panel in tree.get_nodes_in_group("instrument_panel"):
		if panel == null or not is_instance_valid(panel):
			continue
		if not panel.has_method("is_target_camera_focusing_node"):
			continue
		var result = panel.call("is_target_camera_focusing_node", node)
		if result is bool and result:
			return true
	return false
