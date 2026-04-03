extends RefCounted
class_name FactionPaint

const _AIRCRAFT_INSIGNIA_GROUP := "faction_aircraft_insignia"
const _SURFACE_INSIGNIA_GROUP := "faction_surface_insignia"
const _INVALID_COLOR := Color(-1.0, -1.0, -1.0, -1.0)
const _BASE_PALETTE: Array[Color] = [
	Color(0.70, 0.18, 0.16),
	Color(0.74, 0.32, 0.10),
	Color(0.62, 0.46, 0.12),
	Color(0.46, 0.52, 0.14),
	Color(0.22, 0.52, 0.24),
	Color(0.16, 0.52, 0.42),
	Color(0.18, 0.44, 0.62),
	Color(0.30, 0.34, 0.68),
	Color(0.46, 0.22, 0.62),
	Color(0.62, 0.22, 0.46),
]

static var _insignia_textures: Array[Texture2D] = []
static var _insignia_loaded: bool = false

static func build_random_scheme(rng: RandomNumberGenerator = null) -> Dictionary:
	var local_rng := rng
	if local_rng == null:
		local_rng = RandomNumberGenerator.new()
		local_rng.randomize()

	var base_color := _BASE_PALETTE[int(local_rng.randi() % _BASE_PALETTE.size())]
	var primary_color := Color.from_hsv(
		wrapf(base_color.h + local_rng.randf_range(-0.035, 0.035), 0.0, 1.0),
		clampf(base_color.s + local_rng.randf_range(-0.05, 0.06), 0.35, 0.88),
		clampf(base_color.v + local_rng.randf_range(-0.05, 0.06), 0.34, 0.86)
	)
	var secondary_color := primary_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.24)

	_ensure_insignia_loaded()
	var insignia_texture: Texture2D = null
	var insignia_index: int = -1
	if not _insignia_textures.is_empty():
		insignia_index = int(local_rng.randi() % _insignia_textures.size())
		insignia_texture = _insignia_textures[insignia_index]

	return {
		"primary_color": primary_color,
		"secondary_color": secondary_color,
		"insignia_index": insignia_index,
		"insignia_texture": insignia_texture,
	}

static func get_insignia_count() -> int:
	_ensure_insignia_loaded()
	return _insignia_textures.size()

static func apply_aircraft(root: Node, scheme: Dictionary) -> void:
	if root == null:
		return
	_apply_recursive_standard_materials(root, scheme, "aircraft")
	var insignia_texture := _get_scheme_insignia_texture(scheme)
	if insignia_texture != null:
		_apply_aircraft_insignia(root, insignia_texture)

static func apply_vehicle(root: Node, scheme: Dictionary) -> void:
	if root == null:
		return
	_apply_recursive_standard_materials(root, scheme, "vehicle")
	var insignia_texture := _get_scheme_insignia_texture(scheme)
	var body_mesh := _find_mesh_under_named_child(root, "Body")
	if insignia_texture != null and body_mesh != null:
		_apply_side_insignia(root, body_mesh, insignia_texture, 0.9, 0.42, 0.52)

static func apply_building(root: Node, scheme: Dictionary) -> void:
	if root == null:
		return
	_apply_recursive_standard_materials(root, scheme, "building")
	var insignia_texture := _get_scheme_insignia_texture(scheme)
	var mesh_node := _find_mesh_under_named_child(root, "Mesh")
	if insignia_texture != null and mesh_node != null:
		var mesh_aabb := mesh_node.get_aabb()
		var width := clampf(minf(mesh_aabb.size.x, mesh_aabb.size.y) * 0.55, 1.4, 3.6)
		_apply_side_insignia(root, mesh_node, insignia_texture, width, 0.65, 0.62)

static func apply_base_ground(root: Node, scheme: Dictionary) -> void:
	if root == null:
		return
	var mesh_node := root.get_node_or_null("Mesh") as MeshInstance3D
	if mesh_node == null:
		return
	var primary_color: Color = scheme.get("primary_color", Color(0.32, 0.18, 0.12, 1.0))
	_tint_all_standard_surfaces(mesh_node, primary_color.darkened(0.48))

static func apply_runway(root: Node, scheme: Dictionary) -> void:
	if root == null:
		return
	var primary_color: Color = scheme.get("primary_color", Color(0.32, 0.18, 0.12, 1.0))
	var secondary_color: Color = scheme.get("secondary_color", Color(0.56, 0.56, 0.58, 1.0))

	var runway_mesh := root.get_node_or_null("Mesh") as MeshInstance3D
	if runway_mesh != null and runway_mesh.material_override is ShaderMaterial:
		var runway_override := (runway_mesh.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		runway_override.set_shader_parameter("base_color", primary_color.darkened(0.36))
		runway_override.set_shader_parameter("stripe_color", secondary_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.45))
		runway_mesh.material_override = runway_override

	var taxiway_mesh := root.get_node_or_null("TaxiwayMesh") as MeshInstance3D
	if taxiway_mesh != null:
		_tint_all_standard_surfaces(taxiway_mesh, secondary_color.darkened(0.16))

static func _ensure_insignia_loaded() -> void:
	if _insignia_loaded:
		return
	_insignia_loaded = true
	_insignia_textures.clear()
	var dir := DirAccess.open("res://")
	if dir == null:
		return
	var paths: Array[String] = []
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		var lower_name := file_name.to_lower()
		if not lower_name.begins_with("insignia_"):
			continue
		if not (lower_name.ends_with(".png") or lower_name.ends_with(".jpg") or lower_name.ends_with(".jpeg") or lower_name.ends_with(".webp")):
			continue
		paths.append("res://" + file_name)
	dir.list_dir_end()
	paths.sort()
	for path in paths:
		var texture := load(path) as Texture2D
		if texture != null:
			_insignia_textures.append(texture)

static func _get_scheme_insignia_texture(scheme: Dictionary) -> Texture2D:
	var insignia_variant = scheme.get("insignia_texture", null)
	return insignia_variant as Texture2D

static func _apply_recursive_standard_materials(node: Node, scheme: Dictionary, context: String) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var source_material := mesh_instance.get_surface_override_material(surface_index)
				if source_material == null:
					source_material = mesh.surface_get_material(surface_index)
				if not (source_material is StandardMaterial3D):
					continue
				var standard_material := source_material as StandardMaterial3D
				var target_color := _pick_standard_material_color(node, standard_material, scheme, context)
				if target_color.r < 0.0:
					continue
				var override_material := standard_material.duplicate() as StandardMaterial3D
				override_material.albedo_color = target_color
				mesh_instance.set_surface_override_material(surface_index, override_material)
	for child in node.get_children():
		_apply_recursive_standard_materials(child, scheme, context)

static func _pick_standard_material_color(node: Node, material: StandardMaterial3D, scheme: Dictionary, context: String) -> Color:
	var primary_color: Color = scheme.get("primary_color", Color(0.5, 0.5, 0.5, 1.0))
	var secondary_color: Color = scheme.get("secondary_color", primary_color.lerp(Color.WHITE, 0.24))
	var material_name := material.resource_name.to_lower()

	if "upper fuselage" in material_name or "upper_fuselage" in material_name:
		return primary_color
	if "lower fuselage" in material_name or "lower_fuselage" in material_name:
		return secondary_color
	if "body main color" in material_name:
		return primary_color
	if "body secondary color" in material_name:
		return secondary_color
	if "detail color 1" in material_name:
		return secondary_color
	if "detail color 2" in material_name:
		return secondary_color.darkened(0.15)
	if "detail color 3" in material_name:
		return primary_color.darkened(0.10)

	if context == "building":
		var original_luma := _luminance(material.albedo_color)
		if original_luma <= 0.08:
			return _INVALID_COLOR
		if original_luma <= 0.18:
			return primary_color.darkened(0.48)
		if original_luma <= 0.35:
			return primary_color.darkened(0.20)
		if original_luma <= 0.62:
			return primary_color
		return secondary_color

	if context == "vehicle":
		return _INVALID_COLOR

	return _INVALID_COLOR

static func _tint_all_standard_surfaces(mesh_instance: MeshInstance3D, tint_color: Color) -> void:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		var source_material := mesh_instance.get_surface_override_material(surface_index)
		if source_material == null:
			source_material = mesh.surface_get_material(surface_index)
		if not (source_material is StandardMaterial3D):
			continue
		var override_material := (source_material as StandardMaterial3D).duplicate() as StandardMaterial3D
		override_material.albedo_color = tint_color
		mesh_instance.set_surface_override_material(surface_index, override_material)

static func _apply_aircraft_insignia(root: Node, texture: Texture2D) -> void:
	_clear_group_recursive(root, _AIRCRAFT_INSIGNIA_GROUP)
	var marker := root.get_node_or_null("InsigniaWing") as Marker3D
	if marker == null:
		return
	var tex_w := float(texture.get_width())
	var tex_h := float(texture.get_height())
	var aspect := tex_h / maxf(tex_w, 1.0)
	var decal_size := Vector3(1.0, 0.6, 1.0 * aspect)
	for side in [1.0, -1.0]:
		var decal := Decal.new()
		decal.name = "FactionAircraftInsignia_R" if side > 0.0 else "FactionAircraftInsignia_L"
		decal.add_to_group(_AIRCRAFT_INSIGNIA_GROUP)
		decal.texture_albedo = texture
		decal.size = decal_size
		var decal_transform := marker.transform
		decal_transform.origin.x *= side
		decal_transform.basis = decal_transform.basis * Basis(Vector3.UP, PI)
		decal.transform = decal_transform
		root.add_child(decal)

static func _apply_side_insignia(root: Node, mesh_instance: MeshInstance3D, texture: Texture2D, width: float, depth: float, height_ratio: float) -> void:
	_clear_group_recursive(root, _SURFACE_INSIGNIA_GROUP)
	var aabb := mesh_instance.get_aabb()
	if aabb.size.length_squared() <= 0.001:
		return
	var tex_w := float(texture.get_width())
	var tex_h := float(texture.get_height())
	var aspect := tex_h / maxf(tex_w, 1.0)
	var decal_size := Vector3(width, depth, width * aspect)
	var center_y := aabb.position.y + aabb.size.y * clampf(height_ratio, 0.2, 0.85)
	var center_z := aabb.position.z + aabb.size.z * 0.12
	for side in [1.0, -1.0]:
		var decal := Decal.new()
		decal.name = "FactionSurfaceInsignia_R" if side > 0.0 else "FactionSurfaceInsignia_L"
		decal.add_to_group(_SURFACE_INSIGNIA_GROUP)
		decal.texture_albedo = texture
		decal.size = decal_size
		var x_offset := aabb.position.x + (aabb.size.x - 0.04 if side > 0.0 else 0.04)
		decal.transform.origin = Vector3(x_offset, center_y, center_z)
		var inward := -1.0 if side > 0.0 else 1.0
		decal.transform.basis = Basis(
			Vector3(0.0, 0.0, -1.0),
			Vector3(inward, 0.0, 0.0),
			Vector3(0.0, -1.0, 0.0)
		)
		mesh_instance.add_child(decal)

static func _find_mesh_under_named_child(root: Node, child_name: String) -> MeshInstance3D:
	var direct_child := root.get_node_or_null(child_name)
	if direct_child != null:
		var preferred_mesh := _find_first_mesh_recursive(direct_child)
		if preferred_mesh != null:
			return preferred_mesh
	return _find_first_mesh_recursive(root)

static func _find_first_mesh_recursive(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var mesh := _find_first_mesh_recursive(child)
		if mesh != null:
			return mesh
	return null

static func _clear_group_recursive(node: Node, group_name: String) -> void:
	for child in node.get_children():
		_clear_group_recursive(child, group_name)
		if child.is_in_group(group_name):
			child.queue_free()

static func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
