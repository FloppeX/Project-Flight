extends SceneTree

func _init() -> void:
	var packed := load("res://Aircraft/Aircraft_5.tscn") as PackedScene
	if packed == null:
		print("FAILED: load Aircraft_5")
		quit(1)
		return
	var inst := packed.instantiate()
	if inst == null:
		print("FAILED: instantiate")
		quit(1)
		return
	root.add_child(inst)
	print("ROOT:", inst.name)
	var body_root := inst.get_node_or_null("aircraft_5") as Node3D
	if body_root == null:
		print("NO body root")
		quit(2)
		return
	print("BODY ROOT CHILDREN:", body_root.get_child_count())
	for node in body_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mat0: Material = null
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat0 = mi.get_active_material(0)
		var mat_name := mat0.resource_path if mat0 != null else "<none>"
		print("MESH:", mi.get_path(), " vis=", mi.visible, " surf=", (mi.mesh.get_surface_count() if mi.mesh else 0), " mat0=", mat_name)
	quit(0)
