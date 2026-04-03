extends SceneTree


func _init() -> void:
	var tread_scene := load("res://LandCarrier/CarrierTread.tscn") as PackedScene
	var path_scene := load("res://Models/LandCarrier/track_path_export.glb") as PackedScene
	if tread_scene == null or path_scene == null:
		push_error("Failed to load tread or path scene.")
		quit(1)
		return

	var tread_root := tread_scene.instantiate()
	var belt_root := tread_root.get_node_or_null("carrier track tread")
	var belt_mesh := _find_mesh_recursive(belt_root)
	var path_root := path_scene.instantiate()
	var path_mesh := _find_mesh_recursive(path_root)

	if belt_mesh == null or belt_mesh.mesh == null:
		push_error("Failed to find belt mesh.")
		quit(1)
		return
	if path_mesh == null or path_mesh.mesh == null:
		push_error("Failed to find path mesh.")
		quit(1)
		return

	var belt_axis: int = int(tread_root.get("belt_axis"))
	var belt_cross_axis: int = int(tread_root.get("belt_cross_axis"))
	var run_axis := _get_run_axis(belt_axis, belt_cross_axis)

	var belt_aabb := belt_mesh.get_aabb()
	var path_aabb := path_mesh.get_aabb()

	var path_points := _extract_projected_points(path_mesh)
	var path_extents := _compute_extents(path_points)

	print("[TREAD INSPECT] belt_aabb pos=%s size=%s" % [belt_aabb.position, belt_aabb.size])
	print("[TREAD INSPECT] path_aabb pos=%s size=%s" % [path_aabb.position, path_aabb.size])
	print("[TREAD INSPECT] axes run=%d scroll=%d cross=%d" % [run_axis, belt_axis, belt_cross_axis])
	print("[TREAD INSPECT] belt spans run=%.3f scroll=%.3f cross=%.3f" % [
		_axis_from_vec3(belt_aabb.size, run_axis),
		_axis_from_vec3(belt_aabb.size, belt_axis),
		_axis_from_vec3(belt_aabb.size, belt_cross_axis),
	])
	print("[TREAD INSPECT] path projected min=%s max=%s spans=(%.3f, %.3f)" % [
		path_extents["min"],
		path_extents["max"],
		path_extents["max"].x - path_extents["min"].x,
		path_extents["max"].y - path_extents["min"].y,
	])

	path_root.queue_free()
	tread_root.queue_free()
	quit()


func _find_mesh_recursive(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_recursive(child)
		if found:
			return found
	return null


func _get_run_axis(belt_axis: int, belt_cross_axis: int) -> int:
	for axis in range(3):
		if axis != belt_axis and axis != belt_cross_axis:
			return axis
	return 1


func _axis_from_vec3(value: Vector3, axis: int) -> float:
	match axis:
		0:
			return value.x
		1:
			return value.y
		_:
			return value.z


func _extract_projected_points(path_mesh: MeshInstance3D) -> PackedVector2Array:
	var mesh := path_mesh.mesh
	var aabb := path_mesh.get_aabb()
	var extents := aabb.size
	var thin_axis := 0
	for axis in range(1, 3):
		if _axis_from_vec3(extents, axis) < _axis_from_vec3(extents, thin_axis):
			thin_axis = axis

	var plane_axes: Array[int] = []
	for axis in range(3):
		if axis != thin_axis:
			plane_axes.append(axis)

	var run_axis := plane_axes[0]
	var scroll_axis := plane_axes[1]
	if _axis_from_vec3(extents, scroll_axis) < _axis_from_vec3(extents, run_axis):
		run_axis = plane_axes[1]
		scroll_axis = plane_axes[0]

	var points := PackedVector2Array()
	for surface_idx in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_idx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vert in verts:
			var local_vert := path_mesh.transform * vert
			points.append(Vector2(
				_axis_from_vec3(local_vert, run_axis),
				_axis_from_vec3(local_vert, scroll_axis)
			))
	return points


func _compute_extents(points: PackedVector2Array) -> Dictionary:
	if points.is_empty():
		return {"min": Vector2.ZERO, "max": Vector2.ZERO}

	var min_point := points[0]
	var max_point := points[0]
	for point in points:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	return {"min": min_point, "max": max_point}
