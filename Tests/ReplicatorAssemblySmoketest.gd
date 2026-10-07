extends SceneTree
const SECTIONS := preload("res://LandCarrier/ReplicatorMeshSections.gd")
const CATALOG := preload("res://LandCarrier/ReplicatorCatalog.gd")
const MOTION := preload("res://LandCarrier/ReplicatorArmMotion.gd")
var failures: Array[String] = []
var _previous_wrists: Array[Vector3] = []
var _previous_passes: Array[Dictionary] = [{}, {}, {}, {}]

class RaisedTrayChamber:
	extends "res://LandCarrier/ReplicatorChamber.gd"
	func _build_chamber() -> void:
		super._build_chamber()
		_platform.position.y += 0.35

func _initialize() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("REPLICATOR_ASSEMBLY_FAIL: " + message)

func _area(mesh: Mesh) -> float:
	var area := 0.0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for index in range(0, count, 3):
			var a: Vector3 = vertices[indices[index] if not indices.is_empty() else index]
			var b: Vector3 = vertices[indices[index + 1] if not indices.is_empty() else index + 1]
			var c: Vector3 = vertices[indices[index + 2] if not indices.is_empty() else index + 2]
			area += (b - a).cross(c - a).length() * 0.5
	return area

func _check_octagonal_joints(chamber: Node3D) -> void:
	# Inspect the exported vertices, including both inner and outer corners.
	# A wider rectangular box would overlap at one edge and still fail this.
	var rings := [
		"FabricationFrame/UpperOctagon_", "FabricationFrame/LowerOctagonRail_",
		"DescendingShield/ShieldPanel_", "DescendingShield/ShieldSeal_",
		"TransferPlatform/TrayBorder_"]
	for ring in rings:
		for index in range(8):
			var part := chamber.get_node("ReplicatorModel/Replicator/" + ring + "%02d" % index) as MeshInstance3D
			var next := chamber.get_node("ReplicatorModel/Replicator/" + ring + "%02d" % ((index + 1) % 8)) as MeshInstance3D
			var vertices: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var neighbours: PackedVector3Array = next.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var corners: Array[Vector3] = []
			for vertex in vertices:
				if vertex.x <= 0.0: continue
				var at := part.to_global(vertex)
				var closest := INF
				for neighbour in neighbours:
					closest = minf(closest, at.distance_to(next.to_global(neighbour)))
				_expect(closest < 0.0001, "octagonal joint has no gap or overlap: %s%d" % [ring, index])
				var unique := true
				for corner in corners:
					if corner.distance_to(at) < 0.0001: unique = false
				if unique: corners.append(at)
			_expect(corners.size() == 4, "all four corners of each mitred joint are present: " + ring)

func _run() -> void:
	await process_frame
	# Large flat faces must really be cut; centroid grouping would leave these
	# twelve box triangles intact and fail to produce many small sections.
	var box := BoxMesh.new()
	box.size = Vector3(3.4, 1.6, 2.4)
	box.material = StandardMaterial3D.new()
	var transform := Transform3D(Basis.from_euler(Vector3(0.15, 0.4, 0.1)), Vector3(0.11, 0.3, -0.12))
	var sections := SECTIONS.split(box, transform)
	var area := 0.0
	for section in sections:
		area += _area(section.mesh)
		for surface in range(section.mesh.get_surface_count()):
			var arrays: Array = section.mesh.surface_get_arrays(surface)
			_expect(arrays[Mesh.ARRAY_NORMAL].size() == arrays[Mesh.ARRAY_VERTEX].size() and arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size(), "cut surfaces retain normals and UVs")
			_expect(section.mesh.surface_get_material(surface) == box.material, "cut surfaces retain materials")
	_expect(sections.size() > 30 and absf(area - _area(box)) < 0.001, "fragments reconstruct complete source surface without holes/duplicates")
	# Aircraft sections retain interpolated skin weights too, including meshes
	# using eight influences per vertex.
	var skin_arrays: Array = []
	skin_arrays.resize(Mesh.ARRAY_MAX)
	skin_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 2, 0)])
	skin_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	skin_arrays[Mesh.ARRAY_BONES] = PackedInt32Array()
	skin_arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array()
	for vertex in range(3):
		for influence in range(8):
			skin_arrays[Mesh.ARRAY_BONES].append(influence)
			skin_arrays[Mesh.ARRAY_WEIGHTS].append(1.0 if influence == vertex else 0.0)
	var skin_mesh := ArrayMesh.new()
	skin_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, skin_arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	for section in SECTIONS.split(skin_mesh, Transform3D.IDENTITY):
		var arrays: Array = section.mesh.surface_get_arrays(0)
		_expect(arrays[Mesh.ARRAY_WEIGHTS].size() == arrays[Mesh.ARRAY_VERTEX].size() * 8, "skin influence layout retained")
		for vertex in range(arrays[Mesh.ARRAY_VERTEX].size()):
			var sum := 0.0
			for influence in range(8):
				sum += arrays[Mesh.ARRAY_WEIGHTS][vertex * 8 + influence]
			_expect(absf(sum - 1.0) < 0.0001, "interpolated skin weights stay normalized")
	var chamber: Node3D = load("res://LandCarrier/ReplicatorChamber.tscn").instantiate()
	root.add_child(chamber)
	chamber.set_process(false)
	# Inspect real pad vertices against each shield plane rather than trusting
	# a debug constant to prove that the octagons line up.
	var model := chamber.get_node_or_null("ReplicatorModel")
	_expect(model != null and model.scene_file_path == "res://Models/Replicator/replicator.blend", "chamber uses the authored Blender scene")
	_check_octagonal_joints(chamber)
	var pad: MeshInstance3D = chamber.get_node("ReplicatorModel/Replicator/FabricationFrame/BuildPadSeal")
	var pad_vertices: PackedVector3Array = pad.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for index in range(8):
		var angle := index * TAU / 8.0
		var outward := Vector3(sin(angle), 0, cos(angle))
		var projection := -INF
		for vertex in pad_vertices:
			projection = maxf(projection, outward.dot(pad.transform * vertex))
		_expect(absf(projection - 5.65) < 0.001, "pad face matches shield plane %d" % index)
	var ground_product_id := 0
	for id in CATALOG.STARTER_IDS:
		var state := {"phase": "fabricating", "recipe": id, "progress": 0.41, "stage": 2, "shield": 1.0, "rollout": 0.0, "powered": true}
		chamber.set_feed_state(state)
		chamber._process(0.016)
		_check_product_on_tray(chamber, id)
		var before: Dictionary = chamber.get_debug_snapshot()
		state.progress = 0.49
		chamber.set_feed_state(state)
		var contact_frames := 0
		var arm_welding_frames := [0, 0, 0, 0]
		var peak_contacts := 0
		var first_weld_frames := [-1, -1, -1, -1]
		var peak_reposition_speed := 0.0
		for frame in range(720):
			chamber._process(1.0 / 60.0)
			contact_frames += 1 if int(chamber.get_debug_snapshot().welding_contacts) > 0 else 0
			peak_contacts = maxi(peak_contacts, int(chamber.get_debug_snapshot().welding_contacts))
			for index in range(4):
				arm_welding_frames[index] += 1 if bool(chamber.get("_arms")[index].contact) else 0
				if bool(chamber.get("_arms")[index].contact) and first_weld_frames[index] < 0:
					first_weld_frames[index] = frame
				peak_reposition_speed = maxf(peak_reposition_speed, float(chamber.get("_motion").jobs[index].speed))
			_check_motion(chamber)
		var after: Dictionary = chamber.get_debug_snapshot()
		_expect(after.piece_count > after.source_piece_count * 2, "authored objects divided into smaller sections: " + id)
		_expect(after.visible_pieces > before.visible_pieces, "new parts appear within the same stage: " + id)
		_expect(contact_frames > 0, "deliberate welding pass reaches surface: " + id)
		for index in range(4):
			_expect(arm_welding_frames[index] > 0, "every arm performs its own welding passes: %s arm %d" % [id, index])
		_expect(peak_contacts == 4, "all four arms can weld simultaneously on different sections: " + id)
		_expect(peak_reposition_speed > 2.8, "arm repositioning is faster with controlled starts and stops: " + id)
		var distinct_starts: Dictionary = {}
		for frame in first_weld_frames:
			distinct_starts[frame] = true
		_expect(distinct_starts.size() >= 3, "arms begin their work on independent timings: " + id)
		var pieces: Array = chamber.get("_pieces")
		var product: Node3D = chamber.get("_product")
		if id == "light_combat_vehicle":
			ground_product_id = product.get_instance_id()
		var source_area := 0.0
		var fragment_area := 0.0
		for visual: MeshInstance3D in product.find_children("*", "MeshInstance3D", true, false):
			if visual.layers == 0:
				source_area += _area(visual.mesh)
			else:
				fragment_area += _area(visual.mesh)
		_expect(absf(source_area - fragment_area) < maxf(0.001, source_area * 0.0001), "complete authored geometry retained: " + id)
		var connected := 0
		for index in range(pieces.size()):
			connected += 1 if pieces[index].connected_seam else 0
			if index > 0:
				_expect(pieces[index].center.y >= pieces[index - 1].center.y - 0.0001, "assembly progresses upward: " + id)
		_expect(connected > 0, "joining seams found between sections: " + id)
		for arm in chamber.get("_arms"):
			if int(arm.piece_index) < 0:
				continue
			var piece: Dictionary = pieces[arm.piece_index]
			_expect(int(arm.piece_index) <= mini(pieces.size() - 1, int(state.progress * pieces.size()) + maxi(4, int(pieces.size() * 4.0 / float(CATALOG.recipe(id).duration_s)))), "arm works at the current build frontier: " + id)
			var distance := INF
			for seam in piece.weld_seams:
				var closest := Geometry3D.get_closest_point_to_segment(arm.weld_target, seam[0], seam[1])
				distance = minf(distance, closest.distance_to(arm.weld_target))
			_expect(distance < 0.0001, "welding target lies on a real section edge: " + id)
			var tool: Node3D = arm.tool
			_expect((-tool.basis.y).dot((arm.weld_target - tool.position).normalized()) > 0.999, "tool rotates toward seam: " + id)
		print("REPLICATOR_ASSEMBLY %s fragments=%d connected=%d welding_frames=%s peak=%d" % [id, after.piece_count, connected, str(arm_welding_frames), peak_contacts])
		state.powered = false
		chamber.set_feed_state(state)
		chamber._process(0.016)
		for arm in chamber.get("_arms"):
			_expect(not arm.sparks.emitting and not arm.laser.visible and arm.light.light_energy == 0.0, "power loss stops fabrication effects: " + id)
		for frame in range(300):
			chamber._process(1.0 / 60.0)
			_check_motion(chamber)
		_expect((chamber.get("_motion") as RefCounted).all_stowed(), "all arms stow before automatic transfer: " + id)
	chamber.set_feed_state({"phase": "fabricating", "recipe": "light_combat_vehicle", "progress": 0.15, "stage": 0, "shield": 1.0, "rollout": 0.0})
	chamber._process(0.016)
	_expect((chamber.get("_product") as Node3D).get_instance_id() == ground_product_id, "repeat jobs reuse generated model")
	var visible_models := 0
	for product in (chamber.get("_products") as Dictionary).values():
		visible_models += 1 if (product.node as Node3D).visible else 0
	_expect(visible_models == 1, "cached recipes cannot overlap active product")
	# Run every recipe at its actual speed, including the 20-second ammunition
	# job. Every newly appearing fragment must have prior local beam contact.
	for id in CATALOG.STARTER_IDS:
		var duration := float(CATALOG.recipe(id).duration_s)
		chamber.set_feed_state({"phase": "closing", "recipe": id, "job_id": 200, "progress": 0.0, "stage": -1, "shield": 1.0, "rollout": 0.0})
		chamber._process(2.0)
		var revealed: Dictionary = {}
		var contact_frames := 0
		var initial_wait := 0
		for frame in range(int(duration / 0.05) + 1):
			var progress := minf(1.0, frame * 0.05 / duration)
			chamber.set_feed_state({"phase": "fabricating", "recipe": id, "job_id": 200, "progress": progress, "stage": int(progress * 5.0), "shield": 1.0, "rollout": 0.0})
			chamber._process(0.05)
			_check_motion(chamber, 0.05)
			contact_frames += 1 if int(chamber.get_debug_snapshot().welding_contacts) > 0 else 0
			initial_wait += 1 if revealed.is_empty() else 0
			var pieces: Array = chamber.get("_pieces")
			for index in range(pieces.size()):
				var piece: Dictionary = pieces[index]
				if not (piece.node as Node3D).visible or revealed.has(index):
					continue
				revealed[index] = true
				_expect(int(piece.preweld_arm) >= 0 and float(piece.preweld_seconds) >= MOTION.PREWELD_SECONDS, "section waits for welding before appearing: %s / %d" % [id, index])
				var cell_bounds := AABB(Vector3(piece.cell) * SECTIONS.CELL_SIZE, Vector3.ONE * SECTIONS.CELL_SIZE).grow(0.001)
				_expect(cell_bounds.has_point(piece.preweld_target), "prior welding is in the new section's location: %s / %d" % [id, index])
		_expect(initial_wait > 5, "empty build area waits for arms to arrive: " + id)
		_expect(revealed.size() == (chamber.get("_pieces") as Array).size(), "all sections welded before fabrication ends: " + id)
		if revealed.size() != (chamber.get("_pieces") as Array).size():
			var missing: Array = []
			for index in range((chamber.get("_pieces") as Array).size()):
				if not revealed.has(index):
					missing.append([index, chamber.get("_pieces")[index].cell])
			print("REPLICATOR_PREWELD_MISSING %s %s" % [id, str(missing)])
			print("REPLICATOR_PREWELD_JOBS %s %s" % [id, str(chamber.get("_motion").jobs)])
		_expect(contact_frames > 20, "welding continues while fabrication progresses: " + id)
		print("REPLICATOR_PREWELD %s revealed=%d/%d contact_frames=%d" % [id, revealed.size(), (chamber.get("_pieces") as Array).size(), contact_frames])
		chamber.set_feed_state({"phase": "stowing", "recipe": id, "job_id": 200, "progress": 1.0, "stage": 4, "shield": 1.0, "rollout": 0.0})
		chamber._process(5.0)
		_expect(chamber.get("_motion").all_stowed(), "welded product clears all arms before transfer: " + id)
	# Closing the console does not rewind fabrication or require past sections
	# to be welded again when the camera returns to an existing job.
	chamber.set_feed_state({"phase": "idle", "progress": 0.0, "stage": -1, "shield": 0.0, "rollout": 0.0})
	chamber.resume_feed()
	chamber.set_feed_state({"phase": "fabricating", "recipe": "bullets", "job_id": 201, "progress": 0.5, "stage": 2, "shield": 1.0, "rollout": 0.0})
	chamber._process(0.016)
	_expect(int(chamber.get_debug_snapshot().visible_pieces) == int((chamber.get("_pieces") as Array).size() * 0.5) + 1, "resumed feed restores sections completed off camera")
	chamber.set_feed_state({"phase": "rollout", "recipe": "bullets", "progress": 1.0, "stage": 4, "shield": 0.0, "rollout": 0.5})
	chamber._process(0.016)
	var platform: Node3D = chamber.get("_platform")
	var product: Node3D = chamber.get("_product")
	_expect(product.get_parent() == platform and is_equal_approx(platform.position.z, 8.5), "platform carries completed item into transfer room")
	chamber.set_feed_state({"phase": "returning", "progress": 0.0, "stage": -1, "shield": 0.0, "rollout": 0.5})
	chamber._process(0.016)
	_expect(not product.visible and is_equal_approx(platform.position.z, 8.5), "empty platform returns without a duplicate product")
	chamber.free()
	# Moving the tray's parent empty must also move the assembly's weld targets.
	var raised := RaisedTrayChamber.new()
	root.add_child(raised)
	raised.set_process(false)
	for id in CATALOG.STARTER_IDS:
		raised.set_feed_state({"phase": "fabricating", "recipe": id, "progress": 0.4, "stage": 2, "shield": 1.0, "rollout": 0.0})
		_check_product_on_tray(raised, id + " / raised tray parent")
	raised.free()
	if failures.is_empty():
		print("REPLICATOR_ASSEMBLY_PASS geometry+preweld_reveal+eight_timed_builds+resume+surface_targets+tool_rotation+power+octagon_alignment+authored_tray_height")
	quit(0 if failures.is_empty() else 1)

func _check_product_on_tray(chamber: Node3D, label: String) -> void:
	var platform: Node3D = chamber.get("_platform")
	var floor_mesh := platform.get_node("BuildPadFloor") as MeshInstance3D
	var surface_y := -INF
	for vertex: Vector3 in floor_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		surface_y = maxf(surface_y, chamber.to_local(floor_mesh.to_global(vertex)).y)
	var bottom_y := INF
	for piece: Dictionary in chamber.get("_pieces"):
		var visual: MeshInstance3D = piece.node
		var matches := true
		for surface in range(visual.mesh.get_surface_count()):
			for vertex: Vector3 in visual.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var at := chamber.to_local(visual.to_global(vertex))
				bottom_y = minf(bottom_y, at.y)
				matches = matches and (piece.bounds as AABB).grow(0.001).has_point(at)
		_expect(matches, "weld section bounds track actual raised geometry: " + label)
	_expect(absf(bottom_y - surface_y) < 0.001, "product rests on authored tray surface: " + label)

func _check_motion(chamber: Node3D, delta: float = 1.0 / 60.0) -> void:
	var motion: RefCounted = chamber.get("_motion")
	var claimed: Dictionary = {}
	for index in range(4):
		var job: Dictionary = motion.jobs[index]
		if int(job.piece_index) >= 0:
			_expect(not claimed.has(job.piece_index), "each arm owns a different part")
			claimed[job.piece_index] = true
		if job.mode == "weld":
			var closest := Geometry3D.get_closest_point_to_segment(job.target, job.edge[0], job.edge[1])
			_expect(closest.distance_to(job.target) < 0.0001, "each welding pass traces its selected edge")
			var previous := _previous_passes[index]
			if previous.get("mode", "") == "weld":
				_expect(job.key == previous.key and job.piece_index == previous.piece, "newly added sections do not interrupt an arm's edge pass")
				_expect((job.target as Vector3).distance_to(previous.target) < 1.5 * delta + 0.001, "welding advances along the edge without jumps")
		_previous_passes[index] = {"mode": job.mode, "piece": job.piece_index, "key": job.key, "target": job.target}
	for index in range(4):
		for other in range(index + 1, 4):
			_expect(MOTION.clearance_between(motion.poses[index], motion.poses[other]) >= MOTION.CLEARANCE - 0.0001, "arm bodies retain clearance throughout motion")
