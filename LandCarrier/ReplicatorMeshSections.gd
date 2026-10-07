extends RefCounted
## Camera-only mesh derivatives. Slice triangles on a chamber-space grid;
## interpolate their attributes so the assembled result keeps the source surface.
const CELL_SIZE := 0.8
static var _cache: Dictionary = {}

static func split(mesh: Mesh, to_chamber: Transform3D) -> Array[Dictionary]:
	var key := str(mesh.get_instance_id()) + str(to_chamber)
	# Imported/shared resources have stable identities. Procedural meshes belong
	# to a chamber and should be released with it rather than held globally.
	var cacheable := not mesh.resource_path.is_empty()
	if cacheable and _cache.has(key):
		return _cache[key]
	var cells: Dictionary = {}
	for surface in range(mesh.get_surface_count()):
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0, count - 2, 3):
			var triangle: Array[Dictionary] = []
			var low := Vector3(INF, INF, INF)
			var high := Vector3(-INF, -INF, -INF)
			for corner in range(3):
				var index := indices[offset + corner] if not indices.is_empty() else offset + corner
				var vertex := _vertex(arrays, index, to_chamber)
				triangle.append(vertex)
				low = low.min(vertex.world)
				high = high.max(vertex.world)
			var first := Vector3i((low / CELL_SIZE).floor())
			var last := Vector3i(((high - Vector3.ONE * 0.00001).max(low) / CELL_SIZE).floor())
			for x in range(first.x, last.x + 1):
				for y in range(first.y, last.y + 1):
					for z in range(first.z, last.z + 1):
						var cell := Vector3i(x, y, z)
						var minimum := Vector3(cell) * CELL_SIZE
						var polygon: Array[Dictionary] = triangle
						for axis in range(3):
							polygon = _clip(polygon, axis, minimum[axis], true)
							polygon = _clip(polygon, axis, minimum[axis] + CELL_SIZE, false)
						if polygon.size() < 3:
							continue
						if not cells.has(cell):
							cells[cell] = {"surfaces": {}, "seams": [], "points": []}
						var bucket: Dictionary = cells[cell]
						if not bucket.surfaces.has(surface):
							bucket.surfaces[surface] = []
						for corner in range(1, polygon.size() - 1):
							if (polygon[corner].position - polygon[0].position).cross(polygon[corner + 1].position - polygon[0].position).length_squared() > 0.0000000001:
								bucket.surfaces[surface].append_array([polygon[0], polygon[corner], polygon[corner + 1]])
						for corner in range(polygon.size()):
							var a: Vector3 = polygon[corner].world
							var b: Vector3 = polygon[(corner + 1) % polygon.size()].world
							bucket.points.append(a)
							# These are real edges on the triangle surface, including
							# seams introduced by cutting it into adjacent sections.
							if a.distance_squared_to(b) > 0.0025 and bucket.seams.size() < 48:
								bucket.seams.append([a, b])
	var result: Array[Dictionary] = []
	for cell in cells:
		var bucket: Dictionary = cells[cell]
		var section := ArrayMesh.new()
		var source_surfaces: Array[int] = []
		for surface in bucket.surfaces:
			var samples: Array = bucket.surfaces[surface]
			if samples.is_empty():
				continue
			var arrays := _arrays(samples, mesh.surface_get_arrays(surface))
			var flags: int = (mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) if mesh is ArrayMesh else 0
			section.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
			section.surface_set_material(section.get_surface_count() - 1, mesh.surface_get_material(surface))
			source_surfaces.append(surface)
		if section.get_surface_count() > 0:
			result.append({"mesh": section, "surfaces": source_surfaces, "seams": bucket.seams, "points": bucket.points, "cell": cell})
	if cacheable:
		_cache[key] = result
	return result

static func _vertex(arrays: Array, index: int, transform: Transform3D) -> Dictionary:
	var vertex := {"position": arrays[Mesh.ARRAY_VERTEX][index]}
	vertex.world = transform * vertex.position
	for attribute in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[attribute] != null and arrays[attribute].size() > index:
			vertex[attribute] = arrays[attribute][index]
	for attribute in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if arrays[attribute] != null and not arrays[attribute].is_empty():
			var width: int = arrays[attribute].size() / arrays[Mesh.ARRAY_VERTEX].size()
			vertex[attribute] = Array(arrays[attribute].slice(index * width, (index + 1) * width))
	return vertex

static func _mix(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var vertex := {"position": a.position.lerp(b.position, weight), "world": a.world.lerp(b.world, weight)}
	for attribute in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if a.has(attribute):
			vertex[attribute] = a[attribute].lerp(b[attribute], weight)
	if a.has(Mesh.ARRAY_TANGENT):
		var tangent: Array = []
		for index in range(4):
			tangent.append(lerpf(a[Mesh.ARRAY_TANGENT][index], b[Mesh.ARRAY_TANGENT][index], weight) if index < 3 else a[Mesh.ARRAY_TANGENT][index])
		vertex[Mesh.ARRAY_TANGENT] = tangent
	if a.has(Mesh.ARRAY_BONES):
		var influences: Dictionary = {}
		for endpoint in range(2):
			var original: Dictionary = a if endpoint == 0 else b
			var fraction := 1.0 - weight if endpoint == 0 else weight
			for index in range(original[Mesh.ARRAY_BONES].size()):
				var bone: int = original[Mesh.ARRAY_BONES][index]
				influences[bone] = float(influences.get(bone, 0.0)) + original[Mesh.ARRAY_WEIGHTS][index] * fraction
		var bones: Array = influences.keys()
		bones.sort_custom(func(left, right): return influences[left] > influences[right])
		bones.resize(a[Mesh.ARRAY_BONES].size())
		var weights: Array = []
		var total := 0.0
		for index in range(bones.size()):
			if bones[index] == null:
				bones[index] = 0
				weights.append(0.0)
			else:
				weights.append(float(influences[bones[index]]))
			total += weights[index]
		for index in range(weights.size()):
			weights[index] /= maxf(total, 0.00001)
		vertex[Mesh.ARRAY_BONES] = bones
		vertex[Mesh.ARRAY_WEIGHTS] = weights
	return vertex

static func _clip(polygon: Array[Dictionary], axis: int, distance: float, keep_above: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if polygon.is_empty():
		return result
	var previous: Dictionary = polygon.back()
	var previous_inside: bool = previous.world[axis] >= distance if keep_above else previous.world[axis] <= distance
	for current in polygon:
		var inside: bool = current.world[axis] >= distance if keep_above else current.world[axis] <= distance
		if inside != previous_inside:
			var weight: float = (distance - previous.world[axis]) / (current.world[axis] - previous.world[axis])
			result.append(_mix(previous, current, weight))
		if inside:
			result.append(current)
		previous = current
		previous_inside = inside
	return result

static func _arrays(samples: Array, original: Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	for attribute in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if original[attribute] != null:
			arrays[attribute] = original[attribute].slice(0, 0)
	for sample in samples:
		arrays[Mesh.ARRAY_VERTEX].append(sample.position)
		for attribute in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			if sample.has(attribute):
				arrays[attribute].append(sample[attribute].normalized() if attribute == Mesh.ARRAY_NORMAL else sample[attribute])
		for attribute in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			if sample.has(attribute):
				arrays[attribute].append_array(sample[attribute])
	return arrays
