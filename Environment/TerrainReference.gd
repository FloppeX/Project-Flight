extends Node
## Autoload singleton for terrain node reference.
## Caches the terrain node to avoid repeated tree traversals.

var terrain_node: Node = null

func _ready():
	# Find terrain node on startup
	_find_terrain_node()

func _find_terrain_node():
	# First check for tagged terrain provider
	var tagged: Node = get_tree().get_first_node_in_group("terrain_provider")
	if tagged and is_instance_valid(tagged):
		terrain_node = tagged
		return
	# Then BFS for Terrain3D or node with get_height
	var root = get_tree().current_scene
	if not root:
		return
	var queue: Array = [root]
	while queue.size() > 0:
		var cur: Node = queue.pop_front()
		if cur.get_class() == "Terrain3D":
			terrain_node = cur
			break
		if cur is Node3D and cur.has_method("get_height"):
			terrain_node = cur
			break
		var children = cur.get_children()
		for child in children:
			queue.append(child)

func get_terrain_node() -> Node:
	if terrain_node and is_instance_valid(terrain_node):
		return terrain_node
	# Refind if invalid
	_find_terrain_node()
	return terrain_node