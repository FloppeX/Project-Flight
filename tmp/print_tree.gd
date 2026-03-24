extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://Models/LandCarrier/Land carrier static.glb")
	if not scene:
		print("Failed to load scene")
		quit()
		return
	var inst := scene.instantiate()
	_print_node(inst, 0)
	inst.queue_free()
	quit()

func _print_node(node: Node, depth: int) -> void:
	var indent := ""
	for i in range(depth):
		indent += "  "
	var info := "%s%s [%s]" % [indent, node.name, node.get_class()]
	if node is Node3D:
		var n3d := node as Node3D
		info += " pos=%s rot_deg=%s" % [str(n3d.position), str(n3d.rotation_degrees)]
	print(info)
	for child in node.get_children():
		_print_node(child, depth + 1)
