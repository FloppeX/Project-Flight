extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func run() -> void:
	var carrier := CharacterBody3D.new()
	carrier.name = "CarrierCollisionFixture"
	carrier.position = Vector3(120, 60, -90)
	carrier.rotation.y = 0.47
	var commander := CharacterBody3D.new()
	commander.name = "Commander"
	carrier.add_child(commander)
	var model := (load("res://Models/LandCarrier/CarrierWithInterior.tscn") as PackedScene).instantiate() as Node3D
	model.rotation.y = PI
	carrier.add_child(model)
	root.add_child(carrier)
	current_scene = carrier
	await physics_frame
	await physics_frame
	var exterior := model.get_node("IslandExteriorCollision") as AnimatableBody3D
	check(exterior.collision_layer == 1, "exterior must use the aircraft's world collision layer only")
	check(exterior.collision_mask == 0, "exterior mask must not push crew")
	check(exterior.get_collision_exceptions().has(carrier), "island can collide with its moving carrier")
	check(exterior.get_collision_exceptions().has(commander), "commander physics exception missing")
	check(exterior.get_child_count() == 10, "expected complete island coverage through the mast")
	var probe := CharacterBody3D.new()
	probe.collision_layer = 0
	probe.collision_mask = 513 # Same world/terrain mask used by the aircraft.
	var sphere := CollisionShape3D.new()
	sphere.shape = SphereShape3D.new()
	(sphere.shape as SphereShape3D).radius = 0.2
	probe.add_child(sphere)
	root.add_child(probe)
	await physics_frame
	var excludes: Array[RID] = [carrier.get_rid(), commander.get_rid()]
	for node in model.find_children("*", "PhysicsBody3D", true, false):
		if node != exterior:
			excludes.append((node as PhysicsBody3D).get_rid())
	# Verify both the authored pose and the same island after carrier movement.
	for moved in [false, true]:
		if moved:
			carrier.position += Vector3(70, 5, -40)
			carrier.rotation.y += 0.6
			await physics_frame
			await physics_frame
		for collision: CollisionShape3D in exterior.get_children():
			var hull := collision.shape as ConvexPolygonShape3D
			check(hull != null and hull.points.size() >= 4, "%s invalid solid hull" % collision.name)
			if hull == null:
				continue
			var center := Vector3.ZERO
			for point in hull.points:
				center += point
			center /= float(hull.points.size())
			var start := collision.to_global(center + Vector3(30, 0, 0))
			var end := collision.to_global(center)
			var ray := PhysicsRayQueryParameters3D.create(start, end, 1)
			ray.exclude = excludes
			var hit := carrier.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not hit.is_empty() and hit.collider == exterior, "%s did not stop exterior ray moved=%s" % [collision.name, moved])
			ray.collision_mask = 1 << 20
			check(carrier.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "%s leaked into commander walking queries" % collision.name)
			var motion := PhysicsTestMotionParameters3D.new()
			motion.from = Transform3D(Basis.IDENTITY, start)
			motion.motion = end - start
			motion.exclude_bodies = excludes
			var result := PhysicsTestMotionResult3D.new()
			var blocked := PhysicsServer3D.body_test_motion(probe.get_rid(), motion, result)
			check(blocked and result.get_collider() == exterior, "%s did not stop a physical contact probe" % collision.name)
	if "--render" in OS.get_cmdline_user_args():
		await render_overlay(carrier, model, exterior)
	probe.free()
	carrier.free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("CARRIER_ISLAND_COLLISION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("CARRIER_ISLAND_COLLISION_PASS")
	quit(0 if failures.is_empty() else 1)

func render_overlay(carrier: Node3D, model: Node3D, exterior: Node3D) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 1.0, 0.35)
	material.no_depth_test = true
	for collision: CollisionShape3D in exterior.get_children():
		var visual := MeshInstance3D.new()
		var lines := ImmediateMesh.new()
		lines.surface_begin(Mesh.PRIMITIVE_LINES)
		var faces := collision.shape.get_debug_mesh().get_faces()
		for i in range(0, faces.size(), 3):
			for edge in 3:
				lines.surface_add_vertex(faces[i + edge])
				lines.surface_add_vertex(faces[i + (edge + 1) % 3])
		lines.surface_end()
		visual.mesh = lines
		visual.material_override = material
		collision.add_child(visual)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	light.light_energy = 1.2
	carrier.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("26323d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	carrier.add_child(environment)
	var camera := Camera3D.new()
	model.add_child(camera)
	camera.current = true
	camera.fov = 55
	var target := model.to_global(Vector3(21.5, 10, 1))
	for side in [-1, 1]:
		camera.position = Vector3(21.5 + side * 32, 28, 36)
		camera.look_at(target)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/island_collision_%d.png" % side)
