extends Node
## Autoload singleton for terrain node reference.
## Caches the terrain node to avoid repeated tree traversals.

var terrain_node: Node = null
var _search_dirty := true

func _ready():
	get_tree().tree_changed.connect(_on_tree_changed)
	# Find terrain node on startup
	_find_terrain_node()

func _on_tree_changed() -> void:
	# Also cache an unsuccessful search. Aircraft can ask several times per tick;
	# an unchanged terrain-free scene should not be traversed for every query.
	_search_dirty = true

func _find_terrain_node():
	terrain_node = null
	_search_dirty = false
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
	var index := 0
	while index < queue.size():
		var cur: Node = queue[index]
		index += 1
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
	if is_instance_valid(terrain_node) and terrain_node.is_inside_tree():
		return terrain_node
	terrain_node = null
	# Groups may be assigned after node insertion without changing tree structure.
	var tagged := get_tree().get_first_node_in_group("terrain_provider")
	if is_instance_valid(tagged):
		terrain_node = tagged
	elif _search_dirty:
		_find_terrain_node()
	return terrain_node
