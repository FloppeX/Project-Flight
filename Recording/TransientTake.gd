extends RefCounted
## Sparse visual lifetimes: pooled reuse gets a NEW track, never rewrites an
## earlier shot. Replay contains meshes only and never runs an effect script.
const MAX_TRACKS := 4096
const MAX_ACTIVE_MESHES := 256
var tracks: Array = []
var copies: Array[MeshInstance3D] = []
var sources: Array[WeakRef] = []
var active: Dictionary = {}
var _owned_materials: Array[Material] = []

func begin(take: RefCounted, source: Node3D, time: float, kind: String) -> void:
	var id := source.get_instance_id()
	if active.has(id): return
	var meshes: Array[MeshInstance3D] = []
	_collect(source, meshes)
	var active_count := 0
	for entry in active.values(): active_count += entry.indices.size()
	if meshes.is_empty(): return
	if tracks.size() + meshes.size() > MAX_TRACKS or active_count + meshes.size() > MAX_ACTIVE_MESHES:
		take.warning = "Combat visual limit reached; additional effects omitted (4096 lifetime / 256 active meshes)."
		return
	if take.estimated_bytes + meshes.size() * 1024 >= take.MAX_ESTIMATED_BYTES:
		take.warning = "Combat effects reached the shared recording memory limit."
		return
	var indices: Array[int] = []
	for mesh in meshes:
		var copy := MeshInstance3D.new()
		copy.mesh = take._snapshot_mesh(mesh.mesh)
		copy.cast_shadow = mesh.cast_shadow
		copy.layers = mesh.layers
		# Pool-owned materials change on the next activation. Give every effect
		# its own snapshot, including embedded/surface materials.
		copy.material_override = _effect_material(take, mesh.material_override)
		copy.material_overlay = _effect_material(take, mesh.material_overlay)
		if mesh.mesh != null:
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface)
				if material != null: copy.set_surface_override_material(surface, _effect_material(take, material))
		copy.name = "Combat%d" % tracks.size()
		_hold_materials(copy)
		take.world.add_child(copy)
		copy.owner = take.world
		indices.append(tracks.size())
		copies.append(copy)
		sources.append(weakref(mesh))
		tracks.append({"kind": kind, "birth": time, "death": INF, "times": PackedFloat64Array(),
			"poses": [], "visible": PackedByteArray(), "colors": PackedColorArray(), "energy": PackedFloat32Array()})
		take.estimated_bytes += 1024
	active[id] = {"root": weakref(source), "indices": indices}
	_sample_entry(take, active[id], time)

func _effect_material(take: RefCounted, material: Material) -> Material:
	if material == null: return null
	if material is BaseMaterial3D and material.next_pass == null:
		var has_viewport := false
		for slot in BaseMaterial3D.TEXTURE_MAX:
			if material.get_texture(slot) is ViewportTexture:
				has_viewport = true
				break
		if not has_viewport:
			# Managed effects use ordinary materials and static textures. Snapshot
			# the current activation directly, without reflection or cloning textures.
			return material.duplicate(false)
	# Uncommon shader/display materials still use the safe viewport snapshot path.
	take._materials.erase(material.get_instance_id())
	return take._snapshot_material(material)

func _collect(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is SubViewport: return
	if node is MeshInstance3D: meshes.append(node)
	for child in node.get_children(): _collect(child, meshes)

func sample(take: RefCounted, time: float) -> void:
	for id in active.keys():
		var entry: Dictionary = active[id]
		var root: Variant = entry.root.get_ref()
		if not is_instance_valid(root) or not root.is_inside_tree():
			end(take, id, time)
		else:
			_sample_entry(take, entry, time)

func end(take: RefCounted, id: int, time: float) -> void:
	if not active.has(id): return
	var entry: Dictionary = active[id]
	_sample_entry(take, entry, time)
	for index in entry.indices: tracks[index].death = time
	active.erase(id)

func _sample_entry(take: RefCounted, entry: Dictionary, time: float) -> void:
	for index in entry.indices:
		var source: Variant = sources[index].get_ref()
		if not is_instance_valid(source) or not source.is_inside_tree(): continue
		var track: Dictionary = tracks[index]
		if not track.times.is_empty() and time < track.times[-1]: continue
		var replace: bool = not track.times.is_empty() and is_equal_approx(time, track.times[-1])
		if not replace and take.estimated_bytes + 128 >= take.MAX_ESTIMATED_BYTES:
			take.warning = "Combat effects reached the shared recording memory limit."
			continue
		var pose: Transform3D = source.global_transform
		pose.origin += take.origin_offset
		var color := Color.WHITE
		var energy := 0.0
		if source.material_override is BaseMaterial3D:
			color = source.material_override.albedo_color
			energy = source.material_override.emission_energy_multiplier
		if replace:
			track.poses[-1] = pose
			track.visible[-1] = int(source.is_visible_in_tree())
			track.colors[-1] = color
			track.energy[-1] = energy
		else:
			track.times.append(time)
			track.poses.append(pose)
			track.visible.append(int(source.is_visible_in_tree()))
			track.colors.append(color)
			track.energy.append(energy)
			take.estimated_bytes += 128

func seek(time: float) -> void:
	for index in tracks.size():
		var track: Dictionary = tracks[index]
		var copy := copies[index]
		copy.visible = time >= track.birth and time < track.death and not track.times.is_empty()
		if not copy.visible: continue
		var right: int = clampi(track.times.bsearch(time), 0, track.times.size() - 1)
		var left := maxi(0, right - 1)
		var weight := clampf((time - track.times[left]) / maxf(track.times[right] - track.times[left], 0.000001), 0.0, 1.0)
		var selected := right if weight >= 1.0 else left
		var before: Transform3D = track.poses[left]
		var after: Transform3D = track.poses[right]
		copy.transform = before.interpolate_with(after, weight) if absf(before.basis.determinant()) > 0.000001 and absf(after.basis.determinant()) > 0.000001 else track.poses[selected]
		copy.visible = bool(track.visible[selected])
		if copy.material_override is BaseMaterial3D:
			copy.material_override.albedo_color = track.colors[left].lerp(track.colors[right], weight)
			copy.material_override.emission_energy_multiplier = lerpf(track.energy[left], track.energy[right], weight)

func save_data(world: Node3D) -> Array:
	var result: Array = []
	for index in tracks.size():
		var entry: Dictionary = tracks[index].duplicate(false)
		entry.path = str(world.get_path_to(copies[index]))
		result.append(entry)
	return result

func load_data(world: Node3D, data: Array) -> bool:
	if data.size() > MAX_TRACKS: return false
	for entry in data:
		if not entry is Dictionary: return false
		for key in ["path", "kind", "birth", "death", "times", "poses", "visible", "colors", "energy"]:
			if not entry.has(key): return false
		if not entry.times is PackedFloat64Array or not entry.poses is Array or not entry.visible is PackedByteArray or not entry.colors is PackedColorArray or not entry.energy is PackedFloat32Array: return false
		var count: int = entry.times.size()
		if count != entry.poses.size() or count != entry.visible.size() or count != entry.colors.size() or count != entry.energy.size(): return false
		var copy := world.get_node_or_null(NodePath(entry.path)) as MeshInstance3D
		if copy == null: return false
		tracks.append(entry)
		copies.append(copy)
		_hold_materials(copy)
	return true

func _hold_materials(copy: MeshInstance3D) -> void:
	# Keep resources alive until all renderer instances have been destroyed.
	if copy.material_override != null: _owned_materials.append(copy.material_override)
	if copy.material_overlay != null: _owned_materials.append(copy.material_overlay)
	for surface in copy.get_surface_override_material_count():
		var material := copy.get_surface_override_material(surface)
		if material != null: _owned_materials.append(material)

func clear() -> void:
	active.clear()
	tracks.clear()
	sources.clear()
	copies.clear()
	_owned_materials.clear()
