extends SceneTree
func _init() -> void:
	var packed := load("res://Models/Aircraft_5/aircraft_5.glb") as PackedScene
	var inst := packed.instantiate() as Node3D
	var body := inst.get_node_or_null("world_001/body") as MeshInstance3D
	if body == null or body.mesh == null:
		print("no body")
		quit(1)
		return
	print("surface_count:", body.mesh.get_surface_count())
	for i in range(body.mesh.get_surface_count()):
		var m := body.mesh.surface_get_material(i)
		if m == null:
			print(i, "<null>")
			continue
		var line := str(i, " name=", m.resource_name, " class=", m.get_class(), " path=", m.resource_path)
		if m is StandardMaterial3D:
			var sm := m as StandardMaterial3D
			line += str(" albedo=", sm.albedo_color, " transparency=", sm.transparency, " depth_mode=", sm.depth_draw_mode)
		print(line)
	quit(0)
