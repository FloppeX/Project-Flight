extends SceneTree

func _initialize():
	for name in ["Aircraft_9", "Aircraft_10", "Aircraft_11"]:
		var path = "res://Aircraft/" + name + ".tscn"
		var scene = load(path)
		if scene:
			var inst = scene.instantiate()
			print("====================================")
			print("NODE TREE FOR: ", name)
			print("====================================")
			_print_tree(inst, "")
			inst.queue_free()
		else:
			print("Failed to load: ", path)
	quit()

func _print_tree(node: Node, indent: String):
	var line = indent + node.name + " (" + node.get_class() + ")"
	if node is MeshInstance3D:
		line += " [mesh: " + str(node.mesh) + "]"
	print(line)
	for child in node.get_children():
		_print_tree(child, indent + "  ")
