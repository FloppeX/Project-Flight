extends RefCounted
class_name TracerVisualFactory

## A round tapered solid avoids the direction-dependent flat "blade" silhouette
## produced by the old four-sided pyramid while retaining a broad bullet-end base.
const RADIAL_SEGMENTS: int = 12


static func create_unit_tracer_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	for segment in RADIAL_SEGMENTS:
		var angle := TAU * float(segment) / float(RADIAL_SEGMENTS)
		vertices.append(Vector3(cos(angle) * 0.5, sin(angle) * 0.5, 0.0))
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
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func create_glow_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.flags_unshaded = true
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = maxf(emission_energy, 0.0)
	# Transparent additive faces stack on top of one another inside a closed cone.
	# From the side that turns the tracer into an over-bright flat strip. An opaque
	# emissive core lets depth/culling preserve the intended volumetric silhouette;
	# the WorldEnvironment glow still supplies the soft halo.
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.albedo_color = Color(color.r, color.g, color.b, 1.0)
	return material
