extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var ground := StaticBody3D.new()
	ground.name = "TestTerrain"
	ground.add_to_group("terrain")
	scene.add_child(ground)
	var ground_shape := CollisionShape3D.new()
	var slope := 0.08 if "--slope" in OS.get_cmdline_user_args() else 0.0
	if "--terrain-mesh" in OS.get_cmdline_user_args():
		var terrain := ConcavePolygonShape3D.new()
		terrain.set_faces(PackedVector3Array([
			Vector3(-100, -100 * slope, -100), Vector3(100, 100 * slope, -100), Vector3(100, 100 * slope, 100),
			Vector3(-100, -100 * slope, -100), Vector3(100, 100 * slope, 100), Vector3(-100, -100 * slope, 100),
		]))
		ground_shape.shape = terrain
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(200, 1, 200)
		ground_shape.shape = box
		ground_shape.position.y = -0.5
	ground.add_child(ground_shape)
	var aircraft_id := 10 if "--aircraft10" in OS.get_cmdline_user_args() else (11 if "--aircraft11" in OS.get_cmdline_user_args() else 13)
	var craft := load("res://Aircraft/Aircraft_%d.tscn" % aircraft_id).instantiate() as RigidBody3D
	craft.position = Vector3(0, 3, 0)
	scene.add_child(craft)
	var pilot := craft.get_node("HelicopterPilot")
	pilot.set_physics_process(false)
	await process_frame
	var gear := craft.get_node("LandingGear")
	for frame in 180:
		await physics_frame
		if frame in [0, 30, 60, 120, 179]:
			var colliders := [craft.get_node("LeftGearCollider"), craft.get_node("RightGearCollider")]
			print("A13_LANDING frame=%d root_y=%.3f vel_y=%.3f colliders_y=%s contact=%s compression=%s frozen=%s power=%s exploded=%s" % [frame, craft.global_position.y, craft.linear_velocity.y, colliders.map(func(c): return c.global_position.y), gear.gear_has_contact, gear.gear_compressions, craft.freeze, craft.get_node("Engine").get("current_power"), craft.get("_has_exploded")])
	var model := craft.get_node("aircraft_%d" % aircraft_id)
	var skid_min_y := INF
	var skid_min_clearance := INF
	for mesh in model.get_children():
		if mesh is MeshInstance3D and ("strut" in mesh.name.to_lower() or "fuselage" in mesh.name.to_lower()):
			var aabb: AABB = mesh.get_aabb()
			var min_y := INF
			var lowest_local := Vector3.ZERO
			for x in [aabb.position.x, aabb.end.x]:
				for y in [aabb.position.y, aabb.end.y]:
					for z in [aabb.position.z, aabb.end.z]:
						var point: Vector3 = mesh.to_global(Vector3(x, y, z))
						if point.y < min_y:
							min_y = point.y
							lowest_local = craft.to_local(point)
			print("A13_VISUAL %s min_y=%.3f lowest_local=%s local_aabb=%s mesh_position=%s" % [mesh.name, min_y, lowest_local, aabb, mesh.position])
			var vertex_min_y := INF
			var vertex_min_clearance := INF
			var vertex_min_local := Vector3.ZERO
			for surface in mesh.mesh.get_surface_count():
				var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					var world_vertex: Vector3 = mesh.to_global(vertex)
					if world_vertex.y < vertex_min_y:
						vertex_min_y = world_vertex.y
						vertex_min_local = craft.to_local(world_vertex)
					vertex_min_clearance = minf(vertex_min_clearance, world_vertex.y - slope * world_vertex.x)
			print("A13_VERTICES %s min_y=%.3f clearance=%.3f lowest_local=%s" % [mesh.name, vertex_min_y, vertex_min_clearance, vertex_min_local])
			if mesh.name == "landing struts":
				skid_min_y = vertex_min_y
				skid_min_clearance = vertex_min_clearance
	print("A13_REST rotation=%s" % craft.rotation_degrees)
	for name in ["LeftGearCollider", "RightGearCollider"]:
		var collider := craft.get_node(name) as CollisionShape3D
		var half_size: Vector3 = (collider.shape as BoxShape3D).size * 0.5
		var min_y := INF
		for x in [-half_size.x, half_size.x]:
			for y in [-half_size.y, half_size.y]:
				for z in [-half_size.z, half_size.z]:
					min_y = minf(min_y, collider.to_global(Vector3(x, y, z)).y)
		print("A13_COLLIDER %s min_y=%.3f" % [name, min_y])
	var contacts := 0
	for contact in gear.gear_has_contact:
		if contact:
			contacts += 1
	var safe_colliders: Array = craft.get("safe_colliders")
	var rigid_skids_safe := safe_colliders.has(craft.get_node("LeftGearCollider")) and safe_colliders.has(craft.get_node("RightGearCollider"))
	var passed := absf(craft.rotation_degrees.x) < 8.0 and (aircraft_id != 13 or skid_min_clearance >= -0.02) and contacts >= 3 and rigid_skids_safe
	print("SKID_TERRAIN_LANDING_%s aircraft=%d pitch=%.2f skid_min_y=%.3f skid_clearance=%.3f contacts=%d rigid_skids_safe=%s" % ["PASS" if passed else "FAIL", aircraft_id, craft.rotation_degrees.x, skid_min_y, skid_min_clearance, contacts, rigid_skids_safe])
	quit(0 if passed else 1)
