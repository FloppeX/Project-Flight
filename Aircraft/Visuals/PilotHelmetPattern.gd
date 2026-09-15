extends RefCounted
## Helmet-only paint overlay in bind-pose space. CUSTOM0 travels with skinning,
## unlike world/local VERTEX projection, so markings do not slide during poses.
## Imported meshes/materials/UVs are never edited. One derived mesh is shared
## between pooled bodies; individual paint remains a surface override.

const Appearance := preload("res://Aircraft/PilotAppearance.gd")
const PAINT_SHADER := preload("res://Shaders/pilot_helmet_pattern.gdshader")
const PREPARED_META := &"pilot_helmet_pattern_mesh"
static var _mesh_cache: Dictionary = {}


static func is_helmet_material(material: Material) -> bool:
	if material == null:
		return false
	var label := material.resource_name.to_lower().replace("_", " ")
	return label.begins_with("helmet color")


static func prepare_mesh(instance: MeshInstance3D) -> bool:
	var source := instance.mesh as ArrayMesh
	if source == null:
		return false
	if source.has_meta(PREPARED_META):
		return true
	if _mesh_cache.has(source):
		instance.mesh = _mesh_cache[source]
		return true
	var bounds := AABB()
	var found := false
	for surface in range(source.get_surface_count()):
		if not is_helmet_material(source.surface_get_material(surface)):
			continue
		var arrays := source.surface_get_arrays(surface)
		# Do not silently replace an authored custom channel on future models.
		if arrays[Mesh.ARRAY_CUSTOM0] != null:
			return false
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			if not found:
				bounds = AABB(vertex, Vector3.ZERO)
				found = true
			bounds = bounds.expand(vertex)
	if not found or bounds.size.x < 0.001 or bounds.size.y < 0.001 or bounds.size.z < 0.001:
		return false
	var derived := ArrayMesh.new()
	derived.resource_name = source.resource_name + " Helmet Paint Space"
	derived.blend_shape_mode = source.blend_shape_mode
	derived.custom_aabb = source.custom_aabb
	derived.shadow_mesh = source.shadow_mesh
	for blend in range(source.get_blend_shape_count()):
		derived.add_blend_shape(source.get_blend_shape_name(blend))
	# Preserve serialized surfaces (including skin data, LODs, materials and
	# bounds) verbatim except the helmet's added attribute. ArrayMesh has no
	# public surface_get_lods(), and rebuilding unrelated body surfaces is wasteful.
	var stored_surfaces: Array = source.get("_surfaces").duplicate()
	for surface in range(source.get_surface_count()):
		if not is_helmet_material(source.surface_get_material(surface)):
			continue
		var arrays := source.surface_get_arrays(surface)
		var flags := source.surface_get_format(surface)
		var coordinates := PackedFloat32Array()
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var p := (vertex - bounds.get_center()) / (bounds.size * 0.5)
			coordinates.append_array(PackedFloat32Array([p.x, p.y, p.z]))
		arrays[Mesh.ARRAY_CUSTOM0] = coordinates
		flags &= ~(Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		flags |= Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		var prepared_surface := ArrayMesh.new()
		prepared_surface.blend_shape_mode = source.blend_shape_mode
		for blend in range(source.get_blend_shape_count()):
			prepared_surface.add_blend_shape(source.get_blend_shape_name(blend))
		prepared_surface.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays,
				source.surface_get_blend_shape_arrays(surface), {}, flags)
		prepared_surface.surface_set_material(0, source.surface_get_material(surface))
		prepared_surface.surface_set_name(0, source.surface_get_name(surface))
		var updated: Dictionary = prepared_surface.get("_surfaces")[0]
		if stored_surfaces[surface].has("lods"):
			updated["lods"] = stored_surfaces[surface]["lods"]
		stored_surfaces[surface] = updated
	derived.set("_surfaces", stored_surfaces)
	for key in source.get_meta_list():
		derived.set_meta(key, source.get_meta(key))
	derived.set_meta(PREPARED_META, true)
	_mesh_cache[source] = derived
	instance.mesh = derived
	return true


static func make_material(source: Material, base_color: Color, palette: Dictionary) -> ShaderMaterial:
	var paint := ShaderMaterial.new()
	paint.resource_name = "Pilot Helmet " + Appearance.helmet_pattern(palette)
	paint.shader = PAINT_SHADER
	paint.set_shader_parameter("base_color", base_color)
	paint.set_shader_parameter("marking_color", Appearance.helmet_marking_color(palette))
	paint.set_shader_parameter("pattern_mode", Appearance.HELMET_PATTERNS.find(Appearance.helmet_pattern(palette)))
	if source is StandardMaterial3D:
		paint.set_shader_parameter("roughness", (source as StandardMaterial3D).roughness)
		paint.set_shader_parameter("metallic", (source as StandardMaterial3D).metallic)
	return paint
