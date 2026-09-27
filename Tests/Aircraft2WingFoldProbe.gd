extends "res://Tests/Aircraft1MainGearStanceSmoketest.gd"

func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	var craft = load("res://Aircraft/Aircraft_2.tscn").instantiate()
	craft.freeze = true
	craft.position.y = 1000.0
	host.add_child(craft)
	await process_frame
	await physics_frame
	disable_updates(craft)
	craft.position = Vector3.ZERO
	var fold = craft.get_node("WingFold")
	fold.set_technical_index_preview_fraction(0.0)
	var wings: Array[Node3D] = [fold._left_wing, fold._right_wing]
	var rest: Array[Transform3D] = [wings[0].transform, wings[1].transform]
	var hinges: Array[Vector3] = [fold.left_hinge_origin, fold.right_hinge_origin]
	var collider_nodes: Array[CollisionShape3D] = [craft.get_node("LeftWingDamageCollider"), craft.get_node("RightWingDamageCollider")]
	var collider_rest: Array[Transform3D] = [collider_nodes[0].transform, collider_nodes[1].transform]
	var follower = craft.get_node("WingDamageColliderFollower")
	var gear_rest: Transform3D = craft.get_node("LeftGearRig").transform
	for side in 2:
		var mesh: Mesh = (wings[side] as MeshInstance3D).mesh
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var seam_x := INF if side == 0 else -INF
		for vertex in vertices:
			var point := rest[side] * vertex
			seam_x = minf(seam_x, point.x) if side == 0 else maxf(seam_x, point.x)
		check(absf(seam_x - hinges[side].x) < 0.002, "hinge must lie on the revised wing-root seam")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("293644")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.8
	host.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	host.add_child(light)
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.0
	camera.position = Vector3(12, 9, 18)
	camera.look_at(Vector3(0, 1, 0))
	camera.make_current()
	var label := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.get_slice("=", 1)
	for fraction in [0.0, 0.5, 1.0]:
		fold.set_technical_index_preview_fraction(fraction)
		follower._update_collider_poses()
		for side in 2:
			var local_hinge := rest[side].affine_inverse() * hinges[side]
			check((wings[side].transform * local_hinge).distance_to(hinges[side]) < 0.0001, "hinge must remain fixed during folding")
			check(wings[side].basis.get_scale().distance_to(rest[side].basis.get_scale()) < 0.0001, "fold must preserve authored non-uniform scale")
			var expected := wings[side].transform * rest[side].affine_inverse() * collider_rest[side]
			check(collider_nodes[side].transform.is_equal_approx(expected), "damage collider must follow its folding panel")
		check(bool(craft.get_node("WingCollider").disabled), "obsolete full-span collider must stay disabled")
		check(craft.get_node("LeftGearRig").transform.is_equal_approx(gear_rest), "wing folding must not move the main gear")
		if "--render" in OS.get_cmdline_user_args():
			for frame in 4: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/aircraft2_wing_%s_%03d.png" % [label, roundi(fraction * 100)])
		print("WING_POSE ", fraction, " ", fold._left_wing.transform, " ", fold._right_wing.transform)
	check(fold.prepare_technical_index_preview(), "preview must be reusable from a folded pose")
	for side in 2:
		check(wings[side].transform.is_equal_approx(rest[side]), "unfold must restore the exact authored pose without drift")
	for failure in failures: push_error(failure)
	print("AIRCRAFT_2_WING_FOLD_" + ("PASS" if failures.is_empty() else "FAIL"))
	host.free()
	quit(0 if failures.is_empty() else 1)
