extends SceneTree
func _init():
	var scene = load("res://Models/LandCarrier/Land carrier body.glb")
	if scene:
		var inst = scene.instantiate()
		_print_tree(inst, 0)
		inst.queue_free()
	quit()
func _print_tree(node: Node, depth: int):
	print("  ".repeat(depth) + node.name + " (" + node.get_class() + ")")
	for child in node.get_children():
		_print_tree(child, depth + 1)
