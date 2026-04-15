extends SceneTree

func _init() -> void:
	var packed := load("res://Models/Aircraft_5/aircraft_5.glb") as PackedScene
	if packed == null:
		print("FAILED load model")
		quit(1)
		return
	var inst := packed.instantiate()
	if inst == null:
		print("FAILED instantiate")
		quit(2)
		return
	print("MODEL ROOT:", inst.name, " class=", inst.get_class())
	_recurse(inst, inst.name)
	quit(0)

func _recurse(n: Node, path: String) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var surfaces := mi.mesh.get_surface_count() if mi.mesh else 0
		var mat0 := "<none>"
		if surfaces > 0:
			var m := mi.get_active_material(0)
			if m != null:
				mat0 = m.resource_path
		print("MESH", path, "surfaces=", surfaces, "mat0=", mat0)
	for c in n.get_children():
		_recurse(c, path + "/" + c.name)
