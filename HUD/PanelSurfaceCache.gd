extends RefCounted

## Mesh-owned CPU geometry: shared by pooled displays and discarded with the
## mesh. Never mutate the returned arrays. Resource edits invalidate the cache.
const KEY: StringName = &"instrument_panel_surface_cache_v1"

static func arrays(mesh: Mesh, surface: int) -> Array:
	var cached: Dictionary = mesh.get_meta(KEY, {})
	# Resource duplication also copies metadata. A clone owns a fresh cache and
	# its own invalidation signal, even when its initial geometry is identical.
	if int(cached.get("mesh_id", 0)) != mesh.get_instance_id():
		cached = {"mesh_id": mesh.get_instance_id(), "surfaces": {}}
		mesh.set_meta(KEY, cached)
		var invalidate := _invalidate.bind(weakref(mesh))
		if not mesh.changed.is_connected(invalidate): mesh.changed.connect(invalidate)
	var surfaces: Dictionary = cached.surfaces
	if not surfaces.has(surface): surfaces[surface] = mesh.surface_get_arrays(surface)
	return surfaces[surface]

static func _invalidate(mesh_ref: WeakRef) -> void:
	var mesh := mesh_ref.get_ref() as Mesh
	if mesh != null and mesh.has_meta(KEY):
		((mesh.get_meta(KEY) as Dictionary).surfaces as Dictionary).clear()
