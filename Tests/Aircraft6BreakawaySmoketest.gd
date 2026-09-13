extends SceneTree

const SCENE := "res://Aircraft/Aircraft_6.tscn"
const PIECES := {
	&"left_wing": ["OuterWingLeft"],
	&"right_wing": ["OuterWingRight"],
	&"horizontal_stabilizer": ["HorizontalTipLeft", "HorizontalTipRight"],
	&"vertical_stabilizer": ["VerticalTip"],
}
const COLLIDERS := {
	&"left_wing": "LeftWingDamageCollider",
	&"right_wing": "RightWingDamageCollider",
	&"horizontal_stabilizer": "HorizontalStabilizerDamageCollider",
	&"vertical_stabilizer": "VerticalStabilizerDamageCollider",
}
var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for zone: StringName in PIECES:
		await check_zone(zone)
	if failures.is_empty():
		print("AIRCRAFT6_BREAKAWAY_SMOKETEST_OK four_zones five_independent_debris roots_retained gravity_verified")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func check_zone(zone: StringName) -> void:
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	var aircraft := (load(SCENE) as PackedScene).instantiate() as RigidBody3D
	aircraft.freeze = true
	aircraft.position.y = 100.0
	host.add_child(aircraft)
	await process_frame
	await process_frame
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	var damage := aircraft.get_node("PartDamageModel")
	var airframe := aircraft.get_node("aircraft_6/Airframe") as MeshInstance3D
	expect(airframe != null and has_cap(airframe), "retained airframe lacks capped fractures")
	for names: Array in PIECES.values():
		for piece_name: String in names:
			var mesh := aircraft.get_node("aircraft_6/" + piece_name) as MeshInstance3D
			expect(mesh != null and mesh.visible and has_cap(mesh), piece_name + " missing, hidden or uncapped")
	var maximum: float = damage.call("get_zone_max_health", zone)
	var fin_decal: Decal
	if zone == &"vertical_stabilizer":
		for candidate in aircraft.find_children("*", "Decal", true, false):
			if candidate.has_method("get_follow_target") and candidate.call("get_follow_target") == aircraft.get_node("aircraft_6/VerticalTip"):
				fin_decal = candidate
		expect(fin_decal != null, "tail decal does not follow detachable fin")
	damage.call("damage_zone", zone, maximum * 0.25)
	for piece_name: String in PIECES[zone]:
		expect(aircraft.get_node("aircraft_6/" + piece_name).visible, "sublethal damage detached " + piece_name)
	# Exercise real shape-index hit routing, not just the internal detach helper.
	var collider := aircraft.get_node(COLLIDERS[zone]) as CollisionShape3D
	var shape_index := -1
	for owner_id in aircraft.get_shape_owners():
		if aircraft.shape_owner_get_owner(owner_id) == collider:
			shape_index = aircraft.shape_owner_get_shape_index(owner_id, 0)
	expect(shape_index >= 0, "missing damage shape index")
	var hit_zone: StringName = aircraft.call("take_damage_at", maximum, collider.global_position, shape_index)
	expect(hit_zone == zone, "wrong hit zone: " + String(hit_zone))
	await process_frame
	expect(collider.disabled, "destroyed part collider stayed active")
	expect(airframe.visible, "wing roots or tail bases disappeared")
	for other_zone: StringName in PIECES:
		for piece_name: String in PIECES[other_zone]:
			var mesh := aircraft.get_node("aircraft_6/" + piece_name) as MeshInstance3D
			expect(mesh.visible == (other_zone != zone), "incorrect detach state: " + piece_name)
	var debris: Array[RigidBody3D] = []
	for child in host.get_children():
		if child is RigidBody3D and child != aircraft:
			debris.append(child)
	expect(debris.size() == PIECES[zone].size(), "incorrect independent debris count for " + String(zone))
	var starts: Array[Vector3] = []
	var velocities: Array[Vector3] = []
	for body in debris:
		expect(not body.freeze and body.mass > 0, "debris is not physical")
		expect(aircraft in body.get_collision_exceptions(), "debris can immediately collide with owner")
		starts.append(body.global_position)
		velocities.append(body.linear_velocity)
		var mesh_count := 0
		for child in body.get_children():
			if child is MeshInstance3D:
				mesh_count += 1
				expect(child.visible and has_cap(child), "debris lacks its visible capped mesh")
		expect(mesh_count == 1, "separate tips remain rigidly joined")
	if zone == &"vertical_stabilizer":
		expect(fin_decal != null and not fin_decal.visible, "tail insignia floated after fin loss")
		expect(not debris.is_empty() and not debris[0].find_children("*", "Decal", true, false).is_empty(), "fin debris lost its insignia")
	for tick in range(45):
		await physics_frame
	for i in debris.size():
		expect(debris[i].global_position.distance_to(starts[i]) > 0.2, "debris did not move")
		expect(debris[i].linear_velocity.y < velocities[i].y - 3.0, "debris did not fall under gravity")
	# Repeated damage must not create duplicate debris.
	damage.call("damage_zone", zone, maximum)
	expect(host.get_child_count() == 1 + debris.size(), "repeated damage duplicated debris")
	print("AIRCRAFT6_ZONE_OK ", zone, " debris=", debris.size())
	host.free()
	await process_frame


func has_cap(mesh: MeshInstance3D) -> bool:
	if mesh == null or mesh.mesh == null:
		return false
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.mesh.surface_get_material(surface)
		if material != null and material.resource_name == "FractureInterior":
			return true
	return false


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
