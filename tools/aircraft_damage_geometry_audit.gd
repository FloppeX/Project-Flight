extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	var report: Dictionary = {}
	for number in [1, 2, 3, 4, 5, 6, 7, 8, 14, 16]:
		var craft := load("res://Aircraft/Aircraft_%d.tscn" % number).instantiate() as RigidBody3D
		craft.freeze = true
		host.add_child(craft)
		craft.process_mode = Node.PROCESS_MODE_DISABLED
		var entries: Array = []
		for mesh: MeshInstance3D in craft.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null:
				continue
			var box: AABB = craft.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
			entries.append({"path": str(craft.get_path_to(mesh)), "min": [box.position.x,box.position.y,box.position.z], "max": [box.end.x,box.end.y,box.end.z]})
		report[str(number)] = entries
		craft.free()
	var file := FileAccess.open("res://logs/aircraft_damage_geometry.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("AIRCRAFT_DAMAGE_GEOMETRY_AUDIT_OK")
	quit()
