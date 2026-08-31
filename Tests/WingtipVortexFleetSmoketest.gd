extends Node3D

const FIXED_WING_SCENES := [
	"res://Aircraft/Aircraft_1.tscn",
	"res://Aircraft/Aircraft_2.tscn",
	"res://Aircraft/Aircraft_3.tscn",
	"res://Aircraft/Aircraft_4.tscn",
	"res://Aircraft/Aircraft_5.tscn",
	"res://Aircraft/Aircraft_6.tscn",
	"res://Aircraft/Aircraft_7.tscn",
	"res://Aircraft/Aircraft_8.tscn",
	"res://Aircraft/Aircraft_14.tscn",
]

const ROTORCRAFT_SCENES := [
	"res://Aircraft/Aircraft_9.tscn",
	"res://Aircraft/Aircraft_10.tscn",
	"res://Aircraft/Aircraft_11.tscn",
	"res://Aircraft/Aircraft_12.tscn",
]

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for scene_path in FIXED_WING_SCENES:
		await _verify_fixed_wing(scene_path)
	for scene_path in ROTORCRAFT_SCENES:
		_verify_rotorcraft_untouched(scene_path)
	_finish()


func _verify_fixed_wing(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	_expect(packed != null, "%s did not load" % scene_path)
	if packed == null:
		return
	var aircraft := packed.instantiate() as RigidBody3D
	_expect(aircraft != null, "%s did not instantiate as a rigid body" % scene_path)
	if aircraft == null:
		return
	aircraft.freeze = true
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(aircraft)
	await get_tree().process_frame

	var label := aircraft.name
	var left_tip := aircraft.get_node_or_null("WingtipLeft") as Node3D
	var right_tip := aircraft.get_node_or_null("WingtipRight") as Node3D
	var effect := aircraft.get_node_or_null("WingtipVortexEffect") as WingtipVortexEffect
	_expect(left_tip != null, "%s is missing WingtipLeft" % label)
	_expect(right_tip != null, "%s is missing WingtipRight" % label)
	_expect(effect != null, "%s is missing WingtipVortexEffect" % label)
	if left_tip != null and right_tip != null:
		_expect(left_tip.position.x > 3.0, "%s left marker is not outboard" % label)
		_expect(right_tip.position.x < -3.0, "%s right marker is not outboard" % label)
		_expect(absf(left_tip.position.x + right_tip.position.x) < 0.08, "%s markers are not laterally mirrored" % label)
		_expect(absf(left_tip.position.y - right_tip.position.y) < 0.06, "%s marker heights do not match" % label)
		_expect(absf(left_tip.position.z - right_tip.position.z) < 0.06, "%s marker fore-aft positions do not match" % label)
		var mesh_tips := _derive_mesh_tip_positions(aircraft)
		_expect(mesh_tips.size() == 2, "%s mesh tip positions could not be derived" % label)
		if mesh_tips.size() == 2:
			_expect(left_tip.position.distance_to(mesh_tips[0]) < 0.13, "%s left marker misses the imported wingtip" % label)
			_expect(right_tip.position.distance_to(mesh_tips[1]) < 0.13, "%s right marker misses the imported wingtip" % label)
	if effect != null:
		_expect(effect.get_node_or_null("LeftVortexRibbon") is MeshInstance3D, "%s did not create its left ribbon" % label)
		_expect(effect.get_node_or_null("RightVortexRibbon") is MeshInstance3D, "%s did not create its right ribbon" % label)
		_expect(not _contains_particle_emitter(effect), "%s vortex effect contains a particle emitter" % label)
		var fold_controller := _find_fold_controller(aircraft)
		if fold_controller != null:
			_expect(effect.get("_wing_fold") == fold_controller, "%s vortex effect did not bind its fold controller" % label)

	aircraft.queue_free()
	await get_tree().process_frame


func _verify_rotorcraft_untouched(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	_expect(packed != null, "%s did not load" % scene_path)
	if packed == null:
		return
	var aircraft := packed.instantiate()
	var label := aircraft.name
	_expect(aircraft.get_node_or_null("WingtipLeft") == null, "%s rotorcraft unexpectedly has a wingtip marker" % label)
	_expect(aircraft.get_node_or_null("WingtipRight") == null, "%s rotorcraft unexpectedly has a wingtip marker" % label)
	_expect(aircraft.get_node_or_null("WingtipVortexEffect") == null, "%s rotorcraft unexpectedly has a fixed-wing vortex effect" % label)
	aircraft.free()


func _derive_mesh_tip_positions(aircraft: Node3D) -> Array[Vector3]:
	if aircraft.get_child_count() == 0:
		return []
	var model_root := aircraft.get_child(0) as Node3D
	if model_root == null:
		return []
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model_root, meshes)
	var vertices := PackedVector3Array()
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		var relative_path := String(model_root.get_path_to(mesh_instance)).to_lower()
		if "propeller" in relative_path or "propellor" in relative_path:
			continue
		var root_to_mesh := _transform_relative_to_root(mesh_instance, aircraft)
		for surface_index in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in surface_vertices:
				vertices.append(root_to_mesh * vertex)
	if vertices.is_empty():
		return []

	var min_x := INF
	var max_x := -INF
	for vertex in vertices:
		min_x = minf(min_x, vertex.x)
		max_x = maxf(max_x, vertex.x)
	var edge_band := maxf(0.025, (max_x - min_x) * 0.005)
	var left_front_z := INF
	var right_front_z := INF
	for vertex in vertices:
		if vertex.x >= max_x - edge_band:
			left_front_z = minf(left_front_z, vertex.z)
		if vertex.x <= min_x + edge_band:
			right_front_z = minf(right_front_z, vertex.z)
	var left_sum := Vector3.ZERO
	var right_sum := Vector3.ZERO
	var left_count := 0
	var right_count := 0
	for vertex in vertices:
		if vertex.x >= max_x - edge_band and vertex.z <= left_front_z + 0.05:
			left_sum += vertex
			left_count += 1
		if vertex.x <= min_x + edge_band and vertex.z <= right_front_z + 0.05:
			right_sum += vertex
			right_count += 1
	if left_count == 0 or right_count == 0:
		return []
	return [left_sum / float(left_count), right_sum / float(right_count)]


func _transform_relative_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var transforms: Array[Transform3D] = []
	var cursor := node
	while cursor != null and cursor != root:
		transforms.push_front(cursor.transform)
		cursor = cursor.get_parent() as Node3D
	var result := Transform3D.IDENTITY
	for local_transform in transforms:
		result = result * local_transform
	return result


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node)
	for child in node.get_children():
		_collect_meshes(child, output)


func _contains_particle_emitter(node: Node) -> bool:
	if node is GPUParticles3D or node is CPUParticles3D:
		return true
	for child in node.get_children():
		if _contains_particle_emitter(child):
			return true
	return false


func _find_fold_controller(aircraft: Node) -> Node:
	for child in aircraft.get_children():
		if "wingfold" in String(child.name).to_lower() \
				and child.has_method("get_technical_index_preview_fraction"):
			return child
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("WINGTIP_VORTEX_FLEET_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[WingtipVortexFleetSmoketest] %s" % failure)
	get_tree().quit(1)
