extends RefCounted

static var _flat_mesh_cache: Dictionary = {}


static func apply_flat_shading(root: Node) -> void:
	if root == null:
		return
	_apply_flat_shading_recursive(root)


static func _apply_flat_shading_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		_flat_shade_mesh_instance(node as MeshInstance3D)
	for child in node.get_children():
		_apply_flat_shading_recursive(child)


static func _flat_shade_mesh_instance(mesh_instance: MeshInstance3D) -> Mesh:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return null
	var flat_mesh := _get_flat_shaded_mesh(mesh)
	if flat_mesh != null and flat_mesh != mesh:
		mesh_instance.mesh = flat_mesh
		return flat_mesh
	return mesh


static func _get_flat_shaded_mesh(source: Mesh) -> Mesh:
	if source == null:
		return null
	if source.has_meta("flat_shaded_visual_mesh"):
		return source
	var cache_key := "%s:%s:%d" % [source.resource_path, source.resource_name, source.get_instance_id()]
	if _flat_mesh_cache.has(cache_key):
		return _flat_mesh_cache[cache_key] as Mesh
	var flat := _make_flat_shaded_mesh(source)
	if flat != null:
		_flat_mesh_cache[cache_key] = flat
	return flat


static func _make_flat_shaded_mesh(source: Mesh) -> ArrayMesh:
	var flat := ArrayMesh.new()
	flat.resource_name = "%s_flat" % source.resource_name
	for surface_index in range(source.get_surface_count()):
		if source.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			return null
		var arrays := source.surface_get_arrays(surface_index)
		var vertices := _get_vector3_array(arrays, Mesh.ARRAY_VERTEX)
		if vertices.is_empty():
			continue
		var triangle_indices := _get_triangle_indices(arrays, vertices.size())
		if triangle_indices.size() < 3:
			continue
		var uvs := _get_vector2_array(arrays, Mesh.ARRAY_TEX_UV)
		var uv2s := _get_vector2_array(arrays, Mesh.ARRAY_TEX_UV2)
		var colors := _get_color_array(arrays, Mesh.ARRAY_COLOR)
		var bones := _get_int_array(arrays, Mesh.ARRAY_BONES)
		var weights := _get_float_array(arrays, Mesh.ARRAY_WEIGHTS)
		var bone_components := _components_per_vertex(bones.size(), vertices.size())
		var weight_components := _components_per_vertex(weights.size(), vertices.size())
		var out_arrays: Array = []
		out_arrays.resize(Mesh.ARRAY_MAX)
		var out_vertices := PackedVector3Array()
		var out_normals := PackedVector3Array()
		var out_uvs := PackedVector2Array()
		var out_uv2s := PackedVector2Array()
		var out_colors := PackedColorArray()
		var out_bones := PackedInt32Array()
		var out_weights := PackedFloat32Array()
		for tri in range(0, triangle_indices.size() - 2, 3):
			var i0 := int(triangle_indices[tri])
			var i1 := int(triangle_indices[tri + 1])
			var i2 := int(triangle_indices[tri + 2])
			if not _valid_triangle_indices(i0, i1, i2, vertices.size()):
				continue
			var v0 := vertices[i0]
			var v1 := vertices[i1]
			var v2 := vertices[i2]
			var normal := (v1 - v0).cross(v2 - v0)
			if normal.length_squared() <= 0.0000001:
				normal = Vector3.UP
			else:
				normal = normal.normalized()
			_append_flat_vertex(i0, vertices, normal, uvs, uv2s, colors, bones, weights, bone_components, weight_components, out_vertices, out_normals, out_uvs, out_uv2s, out_colors, out_bones, out_weights)
			_append_flat_vertex(i1, vertices, normal, uvs, uv2s, colors, bones, weights, bone_components, weight_components, out_vertices, out_normals, out_uvs, out_uv2s, out_colors, out_bones, out_weights)
			_append_flat_vertex(i2, vertices, normal, uvs, uv2s, colors, bones, weights, bone_components, weight_components, out_vertices, out_normals, out_uvs, out_uv2s, out_colors, out_bones, out_weights)
		if out_vertices.is_empty():
			continue
		out_arrays[Mesh.ARRAY_VERTEX] = out_vertices
		out_arrays[Mesh.ARRAY_NORMAL] = out_normals
		if not out_uvs.is_empty():
			out_arrays[Mesh.ARRAY_TEX_UV] = out_uvs
		if not out_uv2s.is_empty():
			out_arrays[Mesh.ARRAY_TEX_UV2] = out_uv2s
		if not out_colors.is_empty():
			out_arrays[Mesh.ARRAY_COLOR] = out_colors
		if not out_bones.is_empty():
			out_arrays[Mesh.ARRAY_BONES] = out_bones
		if not out_weights.is_empty():
			out_arrays[Mesh.ARRAY_WEIGHTS] = out_weights
		flat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
		var material := source.surface_get_material(surface_index)
		if material != null:
			flat.surface_set_material(flat.get_surface_count() - 1, material)
	if flat.get_surface_count() == 0:
		return null
	flat.set_meta("flat_shaded_visual_mesh", true)
	return flat


static func _append_flat_vertex(
	source_index: int,
	vertices: PackedVector3Array,
	normal: Vector3,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	colors: PackedColorArray,
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	bone_components: int,
	weight_components: int,
	out_vertices: PackedVector3Array,
	out_normals: PackedVector3Array,
	out_uvs: PackedVector2Array,
	out_uv2s: PackedVector2Array,
	out_colors: PackedColorArray,
	out_bones: PackedInt32Array,
	out_weights: PackedFloat32Array
) -> void:
	out_vertices.append(vertices[source_index])
	out_normals.append(normal)
	if source_index < uvs.size():
		out_uvs.append(uvs[source_index])
	if source_index < uv2s.size():
		out_uv2s.append(uv2s[source_index])
	if source_index < colors.size():
		out_colors.append(colors[source_index])
	_append_components_int(bones, source_index, bone_components, out_bones)
	_append_components_float(weights, source_index, weight_components, out_weights)


static func _append_components_int(source: PackedInt32Array, vertex_index: int, components: int, target: PackedInt32Array) -> void:
	if components <= 0:
		return
	var start := vertex_index * components
	if start + components > source.size():
		return
	for offset in range(components):
		target.append(source[start + offset])


static func _append_components_float(source: PackedFloat32Array, vertex_index: int, components: int, target: PackedFloat32Array) -> void:
	if components <= 0:
		return
	var start := vertex_index * components
	if start + components > source.size():
		return
	for offset in range(components):
		target.append(source[start + offset])


static func _get_triangle_indices(arrays: Array, vertex_count: int) -> PackedInt32Array:
	var indices := _get_int_array(arrays, Mesh.ARRAY_INDEX)
	if not indices.is_empty():
		return indices
	var generated := PackedInt32Array()
	generated.resize(vertex_count)
	for index in range(vertex_count):
		generated[index] = index
	return generated


static func _valid_triangle_indices(i0: int, i1: int, i2: int, vertex_count: int) -> bool:
	return i0 >= 0 and i1 >= 0 and i2 >= 0 and i0 < vertex_count and i1 < vertex_count and i2 < vertex_count


static func _components_per_vertex(value_count: int, vertex_count: int) -> int:
	if value_count <= 0 or vertex_count <= 0 or value_count % vertex_count != 0:
		return 0
	return value_count / vertex_count


static func _get_vector3_array(arrays: Array, index: int) -> PackedVector3Array:
	if arrays.size() > index and arrays[index] is PackedVector3Array:
		return arrays[index] as PackedVector3Array
	return PackedVector3Array()


static func _get_vector2_array(arrays: Array, index: int) -> PackedVector2Array:
	if arrays.size() > index and arrays[index] is PackedVector2Array:
		return arrays[index] as PackedVector2Array
	return PackedVector2Array()


static func _get_color_array(arrays: Array, index: int) -> PackedColorArray:
	if arrays.size() > index and arrays[index] is PackedColorArray:
		return arrays[index] as PackedColorArray
	return PackedColorArray()


static func _get_int_array(arrays: Array, index: int) -> PackedInt32Array:
	if arrays.size() > index and arrays[index] is PackedInt32Array:
		return arrays[index] as PackedInt32Array
	return PackedInt32Array()


static func _get_float_array(arrays: Array, index: int) -> PackedFloat32Array:
	if arrays.size() > index and arrays[index] is PackedFloat32Array:
		return arrays[index] as PackedFloat32Array
	return PackedFloat32Array()
