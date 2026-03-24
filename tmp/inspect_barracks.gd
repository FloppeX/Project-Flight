extends SceneTree

func _init() -> void:
	for path in ["res://building barracks.glb", "res://building barracks destroyed.glb"]:
		var scene: PackedScene = load(path)
		if scene == null:
			print("ERROR: Could not load ", path)
			continue
		var root := scene.instantiate()
		print("=== ", path, " ===")
		_print_tree(root, "")
		root.queue_free()
	quit()

func _print_tree(node: Node, indent: String) -> void:
	var info := "%s%s [%s]" % [indent, node.name, node.get_class()]
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var aabb := mi.mesh.get_aabb()
			info += " size=%s" % str(aabb.size)
	print(info)
	for child in node.get_children():
		_print_tree(child, indent + "  ")
