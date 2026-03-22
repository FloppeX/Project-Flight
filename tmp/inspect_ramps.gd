extends SceneTree
func _init():
	var scene = load("res://Models/LandCarrier/Land carrier body.glb")
	if scene:
		var inst = scene.instantiate()
		for name in ["Ramp inner", "Ramp middle", "Ramp outer"]:
			var node = inst.find_child(name)
			if node and node is MeshInstance3D:
				print("=== %s ===" % name)
				print("  position: %s" % str(node.position))
				print("  rotation: %s" % str(node.rotation))
				print("  rotation_degrees: %s" % str(node.rotation_degrees))
				print("  scale: %s" % str(node.scale))
				print("  global_transform: %s" % str(node.transform))
				var mesh = node.mesh
				if mesh:
					var aabb = mesh.get_aabb()
					print("  mesh AABB pos: %s" % str(aabb.position))
					print("  mesh AABB size: %s" % str(aabb.size))
					print("  mesh AABB center: %s" % str(aabb.get_center()))
		inst.queue_free()
	quit()
