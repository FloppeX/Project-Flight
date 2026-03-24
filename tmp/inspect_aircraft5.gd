extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://Models/Aircraft_5/aircraft_5.glb")
	if scene == null:
		print("ERROR: Could not load aircraft_5.glb")
		quit()
		return
	var root := scene.instantiate()
	_print_tree(root, "")
	root.queue_free()
	quit()

func _print_tree(node: Node, indent: String) -> void:
	var info := "%s%s [%s]" % [indent, node.name, node.get_class()]
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			info += " surfaces=%d" % mi.mesh.get_surface_count()
			for i in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(i)
				var mat_name := ""
				if mat:
					mat_name = mat.resource_name if mat.resource_name != "" else str(mat)
				print("%s  surface[%d]: %s" % [indent, i, mat_name])
	print(info)
	for child in node.get_children():
		_print_tree(child, indent + "  ")
