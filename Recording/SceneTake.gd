extends RefCounted
## Visual recording, not simulation rollback. No scripts, bodies, AI or audio
## players are copied. Stable tracks remain valid when a source disappears.
const MAX_SECONDS := 120.0
const MAX_TRACKS := 768
const MAX_SUBJECTS := 6
const SUBJECT_GROUPS := ["carrier", "aircraft", "ai_aircraft", "ground_vehicles"]
const MAX_ESTIMATED_BYTES := 128 * 1024 * 1024
var world: Node3D
var subjects: Array[Node3D] = []
var sources: Array[WeakRef] = []
var copies: Array[Node3D] = []
var frames: Array = []
var times := PackedFloat64Array()
var shots: Array = [[], []]
var origin_offset := Vector3.ZERO
var estimated_bytes := 0
var warning := ""
var _roots: Array[WeakRef] = []
var _skeletons: Dictionary = {}
var _source_ids: Dictionary = {}
var _actor_ids: Dictionary = {}
var _materials: Dictionary = {}
var _textures: Dictionary = {}
var _meshes: Dictionary = {}
var _presentation_released := false
var combat := preload("res://Recording/TransientTake.gd").new()

func build(scene: Node3D, actors: Array[Node3D], center: Vector3, radius: float = 1800.0) -> bool:
	world = Node3D.new()
	world.name = "RecordedWorld"
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for actor in actors:
		if not add_actor(actor): return false
	_copy_set(scene, actors, center, radius)
	return not subjects.is_empty()

func has_actor(actor: Node3D) -> bool:
	return is_instance_valid(actor) and _actor_ids.has(actor.get_instance_id())

func focuses(node: Node3D) -> bool:
	var current: Node = node
	while is_instance_valid(current):
		if _actor_ids.has(current.get_instance_id()): return true
		current = current.get_parent()
	return false

func add_actor(actor: Node3D) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return false
	if has_actor(actor): return true
	if subjects.size() >= MAX_SUBJECTS:
		warning = "Subject limit reached; additional vehicles are not recorded."
		return false
	var nodes: Array[Node3D] = []
	_find_new_visuals(actor, nodes)
	if copies.size() + nodes.size() + 1 > MAX_TRACKS:
		warning = "Visual track limit reached; additional subjects/parts are not recorded."
		return false
	var copy := Node3D.new()
	copy.name = "Subject%d" % subjects.size()
	copy.set_meta("display_name", str(actor.name))
	world.add_child(copy)
	copy.owner = world
	subjects.append(copy)
	_roots.append(weakref(actor))
	_actor_ids[actor.get_instance_id()] = true
	_track(actor, copy)
	_add_visuals(nodes, copy)
	return true

func discover_parts() -> void:
	# Run at capture cadence; no global scene traversal or old-frame padding.
	for index in range(_roots.size()):
		var actor: Variant = _roots[index].get_ref()
		if not is_instance_valid(actor) or not actor.is_inside_tree(): continue
		if not _presentation_released and is_aircraft_subject(actor):
			var budget: Node = actor.get_node_or_null("/root/EnemyVisualBudget")
			if budget != null: budget.set_recording_occupants_active(actor, true)
		var nodes: Array[Node3D] = []
		_find_new_visuals(actor, nodes)
		if copies.size() + nodes.size() > MAX_TRACKS:
			warning = "Visual track limit reached; additional subjects/parts are not recorded."
			continue
		if not nodes.is_empty(): _add_visuals(nodes, subjects[index])

func release_presentation() -> void:
	if _presentation_released: return
	_presentation_released = true
	for ref in sources:
		var source: Variant = ref.get_ref()
		if is_instance_valid(source) and source.has_meta("recording_instance_poses"):
			source.remove_meta("recording_instance_poses")
	for ref in _roots:
		var actor: Variant = ref.get_ref()
		if not is_instance_valid(actor) or not actor.is_inside_tree(): continue
		if is_aircraft_subject(actor):
			var budget: Node = actor.get_node_or_null("/root/EnemyVisualBudget")
			if budget != null: budget.set_recording_occupants_active(actor, false)

func _find_new_visuals(node: Node, result: Array[Node3D]) -> void:
	if node is SubViewport: return
	if node.is_in_group("recording_transient"): return
	if node.has_method("prepare_recording_instances"): node.prepare_recording_instances()
	if (node is MeshInstance3D or node is MultiMeshInstance3D or node is Skeleton3D) and not _source_ids.has(node.get_instance_id()):
		result.append(node)
	for child in node.get_children():
		# A vehicle temporarily parented to the carrier is an independent subject,
		# not part of the carrier's mesh track set.
		if is_vehicle_subject(child): continue
		_find_new_visuals(child, result)

static func is_aircraft_subject(node: Node) -> bool:
	return node.is_in_group("aircraft") or node.is_in_group("ai_aircraft")

static func is_vehicle_subject(node: Node) -> bool:
	for group in SUBJECT_GROUPS:
		if node.is_in_group(group): return true
	return false

func _add_visuals(nodes: Array[Node3D], actor_copy: Node3D) -> void:
	for node in nodes:
		var copy := _visual(node)
		copy.name = "Track%d" % copies.size()
		actor_copy.add_child(copy)
		copy.owner = world
		_track(node, copy)
	# Meshes use their original skin resources but point to script-free skeletons.
	for index in range(copies.size()):
		var original: Variant = sources[index].get_ref()
		if is_instance_valid(original) and original is MeshInstance3D and copies[index] is MeshInstance3D:
			var skeleton: Node = original.get_node_or_null(original.skeleton)
			if _skeletons.has(skeleton): copies[index].skeleton = copies[index].get_path_to(_skeletons[skeleton])

func _track(source: Node3D, copy: Node3D) -> void:
	_source_ids[source.get_instance_id()] = true
	sources.append(weakref(source))
	copies.append(copy)

func _material_has_viewport(material: Material, visited: Dictionary = {}) -> bool:
	if material == null or visited.has(material.get_instance_id()): return false
	visited[material.get_instance_id()] = true
	for property in material.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE): continue
		var value: Variant = material.get(property.name)
		if value is ViewportTexture: return true
		if value is Material and _material_has_viewport(value, visited): return true
	return false

func _snapshot_material(material: Material) -> Material:
	if material == null: return null
	var id := material.get_instance_id()
	if _materials.has(id): return _materials[id]
	var snapshot: Material = material.duplicate(false)
	_materials[id] = snapshot
	for property in material.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE): continue
		var value: Variant = material.get(property.name)
		if value is ViewportTexture:
			var texture_id: int = value.get_instance_id()
			if not _textures.has(texture_id):
				var pixels: Image = value.get_image() if DisplayServer.get_name() != "headless" else null
				if pixels == null or pixels.is_empty():
					pixels = Image.create(1, 1, false, Image.FORMAT_RGBA8)
					pixels.fill(Color.BLACK)
				_textures[texture_id] = ImageTexture.create_from_image(pixels)
			snapshot.set(property.name, _textures[texture_id])
		elif value is Material:
			snapshot.set(property.name, _snapshot_material(value))
	return snapshot

func _snapshot_mesh(mesh: Mesh) -> Mesh:
	if mesh == null: return null
	var id := mesh.get_instance_id()
	if _meshes.has(id): return _meshes[id]
	var snapshot := mesh
	# Overrides alone are insufficient: PackedScene also serializes materials
	# embedded in the mesh. Only duplicate geometry if that embedded graph has
	# a live viewport; ordinary terrain/vehicle mesh data stays shared.
	for surface in range(mesh.get_surface_count()):
		if _material_has_viewport(mesh.surface_get_material(surface)):
			snapshot = mesh.duplicate(false)
			if snapshot is ArrayMesh:
				for index in range(snapshot.get_surface_count()):
					snapshot.surface_set_material(index, _snapshot_material(mesh.surface_get_material(index)))
			elif snapshot is PrimitiveMesh:
				snapshot.material = _snapshot_material(mesh.material)
			break
	_meshes[id] = snapshot
	return snapshot

func _visual(source: Node3D) -> Node3D:
	if source is MeshInstance3D:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _snapshot_mesh(source.mesh)
		mesh.skin = source.skin
		mesh.material_override = _snapshot_material(source.material_override)
		mesh.material_overlay = _snapshot_material(source.material_overlay)
		mesh.cast_shadow = source.cast_shadow
		mesh.layers = source.layers
		for surface in range(source.get_surface_override_material_count()):
			mesh.set_surface_override_material(surface, _snapshot_material(source.get_active_material(surface)))
		return mesh
	if source is MultiMeshInstance3D:
		var multi := MultiMeshInstance3D.new()
		if source.multimesh != null:
			# Explicit allocation order avoids Resource.duplicate setting the GPU
			# buffer before instance layout/count. Headless has no readable buffer.
			var original: MultiMesh = source.multimesh
			var snapshot := MultiMesh.new()
			snapshot.transform_format = original.transform_format
			snapshot.use_colors = original.use_colors
			snapshot.use_custom_data = original.use_custom_data
			snapshot.mesh = _snapshot_mesh(original.mesh)
			snapshot.instance_count = original.instance_count
			var buffer := original.buffer
			if not buffer.is_empty(): snapshot.buffer = buffer
			snapshot.visible_instance_count = original.visible_instance_count
			snapshot.custom_aabb = original.custom_aabb
			multi.multimesh = snapshot
		multi.material_override = _snapshot_material(source.material_override)
		multi.cast_shadow = source.cast_shadow
		return multi
	if source is Skeleton3D:
		var skeleton := Skeleton3D.new()
		for bone in range(source.get_bone_count()):
			skeleton.add_bone(source.get_bone_name(bone))
			skeleton.set_bone_parent(bone, source.get_bone_parent(bone))
			skeleton.set_bone_rest(bone, source.get_bone_rest(bone))
			skeleton.set_bone_pose(bone, source.get_bone_pose(bone))
		_skeletons[source] = skeleton
		return skeleton
	return null

func _copy_set(node: Node, actors: Array[Node3D], center: Vector3, radius: float) -> void:
	if node.is_in_group("recording_transient"): return
	if (node is Node3D and actors.has(node)) or node is SubViewport or node is Camera3D: return
	# Other vehicles are NOT frozen extras pretending to be part of the take.
	if is_vehicle_subject(node): return
	if node is WorldEnvironment:
		var environment := WorldEnvironment.new()
		environment.environment = node.environment.duplicate(true) if node.environment != null else null
		world.add_child(environment)
		environment.owner = world
	elif node is DirectionalLight3D:
		var light := DirectionalLight3D.new()
		light.transform = node.global_transform
		light.light_color = node.light_color
		light.light_energy = node.light_energy
		light.shadow_enabled = node.shadow_enabled
		world.add_child(light)
		light.owner = world
	elif node is MeshInstance3D or node is MultiMeshInstance3D:
		# Streamed terrain vertices need not be centered on their node origin.
		# Test transformed geometry bounds, not the chunk's transform origin.
		var bounds: AABB = node.global_transform * node.get_aabb()
		if node.is_visible_in_tree() and bounds.get_center().distance_to(center) <= radius + bounds.size.length() * 0.5:
			var visual := _visual(node)
			world.add_child(visual)
			visual.owner = world
			visual.transform = node.global_transform
	for child in node.get_children(): _copy_set(child, actors, center, radius)

func sample(time: float) -> bool:
	if time > MAX_SECONDS or estimated_bytes >= MAX_ESTIMATED_BYTES:
		warning = "Take stopped at the 120 s / 128 MiB recording limit."
		return false
	if not times.is_empty() and time < times[-1]:
		warning = "Capture timestamps must move forward."
		return false
	# STOP can arrive between physics callbacks at the current sample time.
	# Refresh that endpoint rather than leaving the take one live step behind.
	var replace_last := not times.is_empty() and is_equal_approx(time, times[-1])
	discover_parts()
	combat.sample(self, time)
	var poses: Array[Transform3D] = []
	var visible := PackedByteArray()
	var bones: Dictionary = {}
	var blends: Dictionary = {}
	var instances: Dictionary = {}
	for index in range(sources.size()):
		var source: Variant = sources[index].get_ref()
		var pose := Transform3D.IDENTITY
		if not frames.is_empty() and index < frames.back().poses.size():
			pose = frames.back().poses[index] # Despawn must not fly back to the origin.
		var shown := false
		if is_instance_valid(source) and source.is_inside_tree():
			pose = source.global_transform
			pose.origin += origin_offset
			shown = _recorded_visibility(source)
			if source is MultiMeshInstance3D and source.has_meta("recording_instance_poses"):
				var values: Array = source.get_meta("recording_instance_poses")
				if values.size() <= 4096:
					instances[index] = values.duplicate()
					estimated_bytes += values.size() * 64
				else:
					warning = "Instance capture omitted: more than 4096 instances in a visual track."
			if source is Skeleton3D:
				var bone_poses: Array[Transform3D] = []
				for bone in range(source.get_bone_count()): bone_poses.append(source.get_bone_pose(bone))
				bones[index] = bone_poses
				estimated_bytes += bone_poses.size() * 64
			if source is MeshInstance3D and source.mesh != null:
				var values := PackedFloat32Array()
				for blend in range(source.get_blend_shape_count()): values.append(source.get_blend_shape_value(blend))
				if not values.is_empty(): blends[index] = values
		poses.append(pose)
		visible.append(1 if shown else 0)
	var frame := {"poses": poses, "visible": visible, "bones": bones, "blends": blends, "instances": instances}
	if replace_last:
		frames[-1] = frame
	else:
		frames.append(frame)
		times.append(time)
	estimated_bytes += sources.size() * 80
	return true

func duration() -> float:
	return times[-1] if not times.is_empty() else 0.0

func _recorded_visibility(source: Node3D) -> bool:
	# First-person masking must not leak into the replay, nor may recording
	# reveal the pilot's head in the live cockpit. Respect every other hide.
	if source.is_visible_in_tree(): return true
	var node: Node = source
	while node != null:
		if node is Node3D and not node.visible and not bool(node.get_meta("recording_cockpit_hidden", false)): return false
		node = node.get_parent()
	return true

func seek(time: float) -> void:
	combat.seek(time)
	if frames.is_empty(): return
	var right := clampi(times.bsearch(time), 0, times.size() - 1)
	var left := maxi(0, right - 1)
	var weight := clampf((time - times[left]) / maxf(times[right] - times[left], 0.00001), 0.0, 1.0)
	var a: Dictionary = frames[left]
	var b: Dictionary = frames[right]
	for index in range(copies.size()):
		var copy := copies[index]
		if copy is MultiMeshInstance3D:
			_seek_instances(copy, index, a, b, weight)
		# Frames keep their original length. A later-born track is absent, not
		# a transform at the origin to interpolate toward before its birth.
		if index >= b.poses.size():
			copy.hide()
			continue
		if index >= a.poses.size():
			copy.global_transform = b.poses[index]
			copy.visible = weight >= 1.0 and bool(b.visible[index])
			if copy is Skeleton3D and b.bones.has(index):
				for bone in range(copy.get_bone_count()): copy.set_bone_pose(bone, b.bones[index][bone])
			if copy is MeshInstance3D and b.blends.has(index):
				for blend in range(b.blends[index].size()): copy.set_blend_shape_value(blend, b.blends[index][blend])
			continue
		copy.global_transform = (a.poses[index] as Transform3D).interpolate_with(b.poses[index], weight)
		copy.visible = bool(b.visible[index] if weight >= 1.0 else a.visible[index])
		if copy is Skeleton3D and a.bones.has(index) and b.bones.has(index):
			for bone in range(copy.get_bone_count()):
				copy.set_bone_pose(bone, (a.bones[index][bone] as Transform3D).interpolate_with(b.bones[index][bone], weight))
		if copy is MeshInstance3D and a.blends.has(index) and b.blends.has(index):
			for blend in range(a.blends[index].size()):
				copy.set_blend_shape_value(blend, lerpf(a.blends[index][blend], b.blends[index][blend], weight))

func _seek_instances(copy: MultiMeshInstance3D, index: int, a: Dictionary, b: Dictionary, weight: float) -> void:
	var before: Array = a.get("instances", {}).get(index, [])
	var after: Array = b.get("instances", {}).get(index, [])
	var selected: Array = after if weight >= 1.0 else before
	if selected.is_empty() or copy.multimesh == null: return
	if copy.multimesh.instance_count != selected.size(): copy.multimesh.instance_count = selected.size()
	var interpolate := before.size() == after.size()
	for instance in range(selected.size()):
		var pose: Transform3D = selected[instance]
		if interpolate and absf(before[instance].basis.determinant()) > 0.000001 and absf(after[instance].basis.determinant()) > 0.000001:
			pose = (before[instance] as Transform3D).interpolate_with(after[instance], weight)
		copy.multimesh.set_instance_transform(instance, pose)

func save_to(directory: String) -> Error:
	DirAccess.make_dir_recursive_absolute(directory)
	var packed := PackedScene.new()
	var result := packed.pack(world)
	if result != OK: return result
	result = ResourceSaver.save(packed, directory.path_join("world.scn"))
	if result != OK: return result
	var file := FileAccess.open(directory.path_join("take.bin"), FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	var paths: Array[String] = []
	var actor_paths: Array[String] = []
	for copy in copies: paths.append(str(world.get_path_to(copy)))
	for subject in subjects: actor_paths.append(str(world.get_path_to(subject)))
	file.store_var({"version": 4, "frames": frames, "times": times, "paths": paths, "subjects": actor_paths, "shots": shots, "warning": warning, "combat": combat.save_data(world)})
	return file.get_error()

func load_from(directory: String) -> bool:
	var file := FileAccess.open(directory.path_join("take.bin"), FileAccess.READ)
	if file == null: return false
	var data: Variant = file.get_var(false)
	if not data is Dictionary or int(data.get("version", 0)) not in [1, 2, 3, 4]: return false
	for key in ["frames", "times", "paths", "subjects", "shots"]:
		if not data.has(key): return false
	if not data.frames is Array or not data.times is PackedFloat64Array \
			or not data.paths is Array or not data.subjects is Array or not data.shots is Array: return false
	if data.frames.is_empty() or data.frames.size() != data.times.size() \
			or data.paths.size() > MAX_TRACKS or data.shots.size() != 2: return false
	var packed: PackedScene = load(directory.path_join("world.scn"))
	if packed == null: return false
	world = packed.instantiate()
	if not data.get("combat", []) is Array or not combat.load_data(world, data.get("combat", [])): return false
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	frames = data.frames
	times = data.times
	shots = data.shots
	warning = str(data.get("warning", ""))
	for path in data.paths:
		var copy := world.get_node_or_null(NodePath(path))
		if not copy is Node3D: return false
		copies.append(copy)
	for path in data.subjects:
		var subject := world.get_node_or_null(NodePath(path))
		if not subject is Node3D: return false
		subjects.append(subject)
	return not frames.is_empty()

func dispose() -> void:
	release_presentation()
	if is_instance_valid(world): world.free()
	combat.clear()
	world = null
	# Drop resources before renderer teardown even if a diagnostic/UI retains
	# the now-disposed take object for its counters.
	_materials.clear()
	_textures.clear()
	_meshes.clear()
	_skeletons.clear()
	sources.clear()
	copies.clear()
	subjects.clear()
	_roots.clear()
	_source_ids.clear()
	_actor_ids.clear()
	frames.clear()
	times.clear()
