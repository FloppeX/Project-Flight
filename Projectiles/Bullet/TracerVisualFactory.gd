extends RefCounted
class_name TracerVisualFactory

## A deliberately faceted pyramid reads as a fast streak instead of a glowing
## capsule. Rotation is handled by the projectile/virtual-tracer transform, so
## the shape remains aligned with the shot rather than with a world axis.
const RADIAL_SEGMENTS: int = 4
const BRIGHT_OUTLINE_RADIUS_SCALE: float = 1.65
const DAYLIGHT_CORE_WHITE_MIX: float = 0.35
const BRIGHT_OUTLINE_WHITE_MIX: float = 0.12
const BRIGHT_OUTLINE_EMISSION_SCALE: float = 0.9


static func create_unit_tracer_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_add_pyramid_surface(mesh, 0.5)
	_add_pyramid_surface(mesh, 0.5 * BRIGHT_OUTLINE_RADIUS_SCALE)
	return mesh


static func _add_pyramid_surface(mesh: ArrayMesh, radius: float) -> void:
	var vertices := PackedVector3Array()
	for segment in RADIAL_SEGMENTS:
		var angle := PI * 0.25 + TAU * float(segment) / float(RADIAL_SEGMENTS)
		vertices.append(Vector3(cos(angle) * radius, sin(angle) * radius, 0.0))
	var tip_index := vertices.size()
	vertices.append(Vector3(0.0, 0.0, 1.0))
	var base_center_index := vertices.size()
	vertices.append(Vector3.ZERO)

	var indices := PackedInt32Array()
	for segment in RADIAL_SEGMENTS:
		var next_segment := (segment + 1) % RADIAL_SEGMENTS
		indices.append_array(PackedInt32Array([segment, next_segment, tip_index]))
		indices.append_array(PackedInt32Array([base_center_index, next_segment, segment]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func create_glow_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var daylight_core := color.lerp(Color.WHITE, DAYLIGHT_CORE_WHITE_MIX)
	daylight_core.a = 1.0
	material.flags_unshaded = true
	material.emission_enabled = true
	material.emission = daylight_core
	material.emission_energy_multiplier = maxf(emission_energy, 0.0)
	# Transparent additive faces stack on top of one another inside a closed taper.
	# From the side that turns the tracer into an over-bright flat strip. An opaque
	# emissive core lets depth/culling preserve the intended volumetric silhouette;
	# the WorldEnvironment glow still supplies the soft halo.
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.albedo_color = daylight_core
	return material


static func create_bright_outline_material(
	color: Color,
	emission_energy: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var bright_outline := color.lerp(Color.WHITE, BRIGHT_OUTLINE_WHITE_MIX)
	bright_outline.a = 1.0
	material.flags_unshaded = true
	material.emission_enabled = true
	material.emission = bright_outline
	material.emission_energy_multiplier = maxf(
		emission_energy * BRIGHT_OUTLINE_EMISSION_SCALE,
		0.0
	)
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	# The enlarged back faces provide the readable silhouette. Keeping that
	# silhouette emissive avoids a dark shell covering the bright inner core.
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.albedo_color = bright_outline
	return material


static func configure_tracer_mesh_materials(
	mesh: ArrayMesh,
	color: Color,
	emission_energy: float
) -> void:
	if mesh == null or mesh.get_surface_count() < 2:
		return
	mesh.surface_set_material(0, create_glow_material(color, emission_energy))
	mesh.surface_set_material(1, create_bright_outline_material(color, emission_energy))
