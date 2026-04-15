extends SceneTree
func _init() -> void:
	var packed := load("res://Models/Aircraft_5/aircraft_5.glb") as PackedScene
	var inst := packed.instantiate() as Node3D
	var body := inst.get_node_or_null("world_001/body") as MeshInstance3D
	var mesh := body.mesh as ArrayMesh
	for i in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var tri_count := 0
		var area := 0.0
		var aabb := AABB()
		var has := false
		if indices.size() >= 3:
			for t in range(0, indices.size(), 3):
				if t+2 >= indices.size():
					break
				var a := verts[indices[t]]
				var b := verts[indices[t+1]]
				var c := verts[indices[t+2]]
				area += ((b-a).cross(c-a)).length() * 0.5
				tri_count += 1
				if not has:
					aabb = AABB(a, Vector3.ZERO)
					has = true
					aabb = aabb.expand(b)
					aabb = aabb.expand(c)
		else:
			for t in range(0, verts.size(), 3):
				if t+2 >= verts.size():
					break
				var a := verts[t]
				var b := verts[t+1]
				var c := verts[t+2]
				area += ((b-a).cross(c-a)).length() * 0.5
				tri_count += 1
				if not has:
					aabb = AABB(a, Vector3.ZERO)
					has = true
					aabb = aabb.expand(b)
					aabb = aabb.expand(c)
		var m := mesh.surface_get_material(i)
		var n := m.resource_name if m != null else "<null>"
		print(i, " ", n, " tris=", tri_count, " area=", snappedf(area, 0.01), " aabb=", aabb)
	quit()
