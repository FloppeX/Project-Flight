extends SceneTree

const SOURCES := {
	1: "res://Models/Aircraft_1/aircraft 1.glb",
	2: "res://Models/Aircraft_2/aircraft 2 body.glb",
	5: "res://Models/Aircraft_5/aircraft_5.glb",
}
const MODEL_NAMES := {1: "aircraft_1", 2: "Aircraft 2 body", 5: "aircraft_5"}
const WINGS := {1: ["wing outer left", "wing outer right"], 2: ["left outer wing", "right outer wing"], 5: ["outer wing left", "outer wing right"]}
const ZONES := [&"left_wing", &"right_wing", &"horizontal_stabilizer", &"vertical_stabilizer"]
const COLLIDERS := ["LeftWingDamageCollider", "RightWingDamageCollider", "HorizontalStabilizerDamageCollider", "VerticalStabilizerDamageCollider"]
var failures: PackedStringArray = []
var context := ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for number: int in SOURCES:
		await check_fold_compatibility(number)
		for zone: StringName in ZONES:
			var poses := [0.0, 0.5, 1.0] if zone in [&"left_wing", &"right_wing"] else [0.0]
			for pose: float in poses:
				await check_damage(number, zone, pose)
	if failures.is_empty():
		print("FOLDING_AIRCRAFT_BREAKAWAY_SMOKETEST_OK aircraft=1,2,5 damage_cases=24 fold_comparisons=9")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func spawn_aircraft(host: Node3D, number: int) -> RigidBody3D:
	var aircraft := (load("res://Aircraft/Aircraft_%d.tscn" % number) as PackedScene).instantiate() as RigidBody3D
	aircraft.freeze = true
	aircraft.position.y = 100
	host.add_child(aircraft)
	return aircraft


func check_fold_compatibility(number: int) -> void:
	context = "aircraft %d fold" % number
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	var aircraft := spawn_aircraft(host, number)
	await process_frame
	await process_frame
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	var fold := aircraft.get_node("WingFold5" if number == 5 else "WingFold")
	var reference := Node3D.new()
	host.add_child(reference)
	reference.global_transform = aircraft.global_transform
	reference.process_mode = Node.PROCESS_MODE_DISABLED
	var original := (load(SOURCES[number]) as PackedScene).instantiate() as Node3D
	original.name = MODEL_NAMES[number]
	original.transform = aircraft.get_node(MODEL_NAMES[number]).transform
	reference.add_child(original)
	var original_fold := fold.duplicate()
	reference.add_child(original_fold)
	var decal_offsets: Dictionary = {}
	for decal in aircraft.find_children("*", "Decal", true, false):
		if decal.has_method("get_follow_target"):
			var target: Node3D = decal.call("get_follow_target")
			if target != null:
				decal_offsets[decal] = target.global_transform.affine_inverse() * decal.global_transform
	for fraction: float in [0.0, 0.5, 1.0]:
		fold.call("set_technical_index_preview_fraction", fraction)
		original_fold.call("set_technical_index_preview_fraction", fraction)
		aircraft.get_node("WingDamageColliderFollower").call("_update_collider_poses")
		for decal: Decal in decal_offsets:
			decal.call("update_follow_transform")
			var target: Node3D = decal.call("get_follow_target")
			expect(decal.global_transform.is_equal_approx(target.global_transform * decal_offsets[decal]), "insignia did not follow its part through folding")
		for side in range(2):
			var wing := aircraft.get_node(String(MODEL_NAMES[number]) + "/" + WINGS[number][side]) as MeshInstance3D
			var old_wing := original.get_node(WINGS[number][side]) as MeshInstance3D
			var tip := wing.get_node("OuterWingLeft" if side == 0 else "OuterWingRight") as MeshInstance3D
			expect(wing.global_position.distance_to(old_wing.global_position) < 0.01, "fold hinge moved: fraction=%s error=%s" % [fraction, wing.global_position.distance_to(old_wing.global_position)])
			expect(wing.global_basis.is_equal_approx(old_wing.global_basis), "fold rotation changed")
			expect(tip.global_transform.is_equal_approx(wing.global_transform), "tip does not follow its folding parent")
			if number == 1:
				var collider := aircraft.get_node(COLLIDERS[side]) as CollisionShape3D
				var box := collider.shape as BoxShape3D
				var relative := collider.global_transform.affine_inverse() * tip.global_transform
				for corner in range(8):
					var point := tip.get_aabb().get_endpoint(corner)
					var local := (relative * point).abs()
					expect(local.x <= box.size.x * 0.5 + 0.01 and local.y <= box.size.y * 0.5 + 0.01 and local.z <= box.size.z * 0.5 + 0.01, "folded tip escaped its damage collider")
	print("FOLD_COMPATIBILITY_CHECKED ", number)
	host.free()
	await process_frame


func check_damage(number: int, zone: StringName, fraction: float) -> void:
	context = "aircraft %d %s fold=%s" % [number, zone, fraction]
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	var aircraft := spawn_aircraft(host, number)
	await process_frame
	await process_frame
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	var fold := aircraft.get_node("WingFold5" if number == 5 else "WingFold")
	fold.call("set_technical_index_preview_fraction", fraction)
	aircraft.get_node("WingDamageColliderFollower").call("_update_collider_poses")
	var damage := aircraft.get_node("PartDamageModel")
	var visuals: Dictionary = {}
	var attached_visuals: Dictionary = {}
	for candidate_zone: StringName in ZONES:
		visuals[candidate_zone] = []
		attached_visuals[candidate_zone] = []
		var paths: Array = damage.get(String(candidate_zone) + "_visual_paths")
		expect(not paths.is_empty(), "missing " + String(candidate_zone) + " visuals")
		for path: NodePath in paths:
			var mesh := damage.get_node_or_null(path) as MeshInstance3D
			expect(mesh != null and has_cap(mesh) and mesh.is_visible_in_tree(), "missing visible capped part: " + String(path))
			if mesh != null:
				visuals[candidate_zone].append(mesh)
		var attached_paths: Array = damage.get(String(candidate_zone) + "_attached_visual_paths")
		for path: NodePath in attached_paths:
			var attached := damage.get_node_or_null(path) as MeshInstance3D
			expect(attached != null and attached.is_visible_in_tree(), "missing visible attached part: " + String(path))
			if attached != null:
				attached_visuals[candidate_zone].append(attached)
	var coll := aircraft.get_node(COLLIDERS[ZONES.find(zone)]) as CollisionShape3D
	var index := -1
	for owner_id in aircraft.get_shape_owners():
		if aircraft.shape_owner_get_owner(owner_id) == coll:
			index = aircraft.shape_owner_get_shape_index(owner_id, 0)
	var hp: float = damage.call("get_zone_max_health", zone)
	damage.call("damage_zone", zone, hp * 0.25)
	for mesh: MeshInstance3D in visuals[zone]:
		expect(mesh.is_visible_in_tree(), "sublethal damage detached a part")
	var expected_transforms: Dictionary = {}
	var attached_tail_transforms: Dictionary = {}
	var affected := [zone]
	if zone == &"vertical_stabilizer":
		affected.append(&"horizontal_stabilizer")
	for affected_zone: StringName in affected:
		for mesh: MeshInstance3D in visuals[affected_zone]:
			expected_transforms[String(mesh.name).to_pascal_case() + "Mesh"] = mesh.global_transform
	# Losing both supported stabilizers also releases the newly separable rear
	# fuselage. Its cap, pose, lifetime and idempotence use the same assertions.
	if affected.size() == 2:
		for path: NodePath in damage.tail_section_visual_paths:
			var tail := damage.get_node(path) as MeshInstance3D
			if tail != null:
				expected_transforms[String(tail.name).to_pascal_case() + "Mesh"] = tail.global_transform
		for path: NodePath in damage.tail_section_attached_visual_paths:
			var attached := damage.get_node(path) as Node3D
			var meshes: Array[Node] = [attached]
			meshes.append_array(attached.find_children("*", "MeshInstance3D", true, false))
			for mesh in meshes:
				if mesh is MeshInstance3D and mesh.is_visible_in_tree():
					attached_tail_transforms[String(mesh.name).to_pascal_case() + "Mesh"] = mesh.global_transform
	var affected_decals: Array[Decal] = []
	for decal in aircraft.find_children("*", "Decal", true, false):
		if decal.has_method("get_follow_target"):
			decal.call("update_follow_transform")
			for affected_zone: StringName in affected:
				if decal.call("get_follow_target") in visuals[affected_zone] and decal.visible:
					affected_decals.append(decal)
	# Surface geometry remains independently testable for old saved damage.
	# Combat hits on either stabilizer now route to the shared full-tail region;
	# RegionalAircraftDamageSmoketest covers that route and complete detachment.
	var hit_zone: StringName
	if zone in [&"horizontal_stabilizer", &"vertical_stabilizer"]:
		hit_zone = damage.call("resolve_zone_from_hit", coll.global_position, index)
		damage.call("damage_zone", zone, hp)
	else:
		hit_zone = aircraft.call("take_damage_at", hp, coll.global_position, index)
	expect(hit_zone == zone, "shape-index routing failed")
	var bodies: Array[RigidBody3D] = []
	for child in host.get_children():
		if child is RigidBody3D and child != aircraft:
			bodies.append(child)
	var expected_count := expected_transforms.size()
	expect(bodies.size() == expected_count, "incorrect debris count: got %d expected %d" % [bodies.size(), expected_count])
	for body in bodies:
		expect(aircraft in body.get_collision_exceptions(), "debris can collide with its owner immediately")
		var count := 0
		for mesh in body.get_children():
			if mesh is MeshInstance3D:
				count += 1
				if attached_tail_transforms.has(String(mesh.name)):
					expect(mesh.global_transform.is_equal_approx(attached_tail_transforms[String(mesh.name)]), "attached tail part jumped")
					continue
				expect(expected_transforms.has(String(mesh.name)), "unexpected debris mesh")
				if expected_transforms.has(String(mesh.name)):
					expect(mesh.global_transform.is_equal_approx(expected_transforms[String(mesh.name)]), "debris jumped when detached from folded panel")
				expect(has_cap(mesh), "debris cap missing")
		expect(count == 1 + (attached_tail_transforms.size() if body.name == "DetachedTailSection" else 0), "independent parts are rigidly joined: %s meshes=%d attached=%d" % [body.name, count, attached_tail_transforms.size()])
	var copied_decals := 0
	for body in bodies:
		copied_decals += body.find_children("*", "Decal", true, false).size()
	expect(copied_decals == affected_decals.size(), "debris lost an insignia")
	for decal in affected_decals:
		expect(not decal.visible, "detached insignia remained on aircraft")
	await process_frame
	expect(coll.disabled, "destroyed collider remained enabled")
	for candidate_zone: StringName in ZONES:
		for mesh: MeshInstance3D in visuals[candidate_zone]:
			expect(mesh.is_visible_in_tree() == (candidate_zone not in affected), "incorrect visibility after damage")
		for attached: MeshInstance3D in attached_visuals[candidate_zone]:
			expect(attached.is_visible_in_tree() == (candidate_zone not in affected), "incorrect attached-part visibility after damage")
		if candidate_zone in affected:
			expect(damage.call("is_zone_destroyed", candidate_zone), "supported tail surface did not fail")
	for wing_name: String in WINGS[number]:
		expect(aircraft.get_node(String(MODEL_NAMES[number]) + "/" + wing_name).is_visible_in_tree(), "retained wing root disappeared")
	if number == 1:
		expect(aircraft.get_node("aircraft_1/wing middle left").visible and aircraft.get_node("aircraft_1/wing middle right").visible, "middle folding panels disappeared")
	# apply_central_impulse is consumed by the physics step. Capture the baseline
	# after that step, otherwise an upward separation impulse looks like no gravity.
	await physics_frame
	await physics_frame
	var velocities: Array[Vector3] = []
	for body in bodies:
		velocities.append(body.linear_velocity)
	for tick in range(30):
		await physics_frame
	for i in bodies.size():
		expect(bodies[i].linear_velocity.y < velocities[i].y - 2.0, "debris did not fall under gravity: %s -> %s" % [velocities[i], bodies[i].linear_velocity])
	damage.call("damage_zone", zone, hp)
	expect(host.get_child_count() == 1 + expected_count, "repeated damage duplicated parts")
	print("BREAKAWAY_CASE_CHECKED ", context, " debris=", bodies.size())
	host.free()
	await process_frame


func has_cap(mesh: MeshInstance3D) -> bool:
	if mesh == null or mesh.mesh == null:
		return false
	for index in mesh.mesh.get_surface_count():
		var material := mesh.mesh.surface_get_material(index)
		if material != null and material.resource_name == "FractureInterior":
			return true
	return false


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(context + ": " + message)
