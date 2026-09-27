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
	await process_frame
	disable_updates(craft)
	var gear = craft.get_node("LandingGear")
	var control = craft.get_node("ControlLandingGear")
	var rigs := [craft.get_node("NoseGearRig"), craft.get_node("RightGearRig"), craft.get_node("LeftGearRig")]
	var names := ["CenterGearCollider", "RightGearCollider", "LeftGearCollider"]
	for i in 3:
		var collider = craft.get_node(names[i])
		check(gear.gear_collision_shapes[i] == collider, "suspension must use the new collider")
		check(craft.safe_colliders.has(collider), "new wheels must be registered as safe gear")
		check(rigs[i].gear_index == i, "rig must follow its own suspension")
	check(control._nose_cs == craft.get_node(names[0]), "nose gear must be discoverable")
	check(control._right_cs == craft.get_node(names[1]) and control._left_cs == craft.get_node(names[2]), "main gear control must resolve")
	var camera: Camera3D
	if "--render" in OS.get_cmdline_user_args():
		craft.position.y = 0.0
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("263340")
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_energy = 0.8
		host.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-40, -25, 0)
		host.add_child(light)
		camera = Camera3D.new()
		host.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 9.0
		camera.position = Vector3(0, -3.0, 14)
		camera.look_at(Vector3(0, -0.8, 0))
		camera.make_current()
	var rest: Array[Vector3] = []
	var previous_x := [INF, INF, INF]
	for fraction in [1.0, 0.55, 0.275, 0.001, 0.0]:
		for i in 3:
			var rig = rigs[i]
			rig.set_technical_index_preview_fraction(fraction)
			var wheel: Vector3 = craft.to_local(rig._wheel_pivot.global_position)
			if fraction == 1.0: rest.append(wheel)
			if i > 0:
				check(absf(wheel.x) <= previous_x[i] + 0.001, "both main wheels must travel medially")
				previous_x[i] = absf(wheel.x)
				if fraction == 0.55:
					check(wheel.y > rest[i].y + 0.35, "lower leg must shorten before folding")
					check(absf(wheel.x - rest[i].x) < 0.01, "shortening phase must retain lateral position")
				if fraction == 0.0:
					check(absf(wheel.x) < absf(rest[i].x) - 0.8, "main wheels must finish closer to the fuselage")
					check(absf(wheel.z - rest[i].z) < 0.01, "main legs must not swing fore or aft")
			check(rig.visible == (fraction > 0.0), "gear must remain visible until fully stowed")
		if camera != null:
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/aircraft2_medial_gear_%03d.png" % roundi(fraction * 1000))
	control.stow_gear()
	await physics_frame
	for name in names: check(craft.get_node(name).disabled, "stow must disable wheel colliders")
	control.deploy_gear()
	await physics_frame
	for i in 3:
		rigs[i].set_technical_index_preview_fraction(1.0)
		check(not craft.get_node(names[i]).disabled, "deploy must restore wheel colliders")
		check(craft.to_local(rigs[i]._wheel_pivot.global_position).distance_to(rest[i]) < 0.001, "deployment must restore authored wheel placement")
	for failure in failures: push_error(failure)
	print("AIRCRAFT_2_MEDIAL_GEAR_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	host.free()
	quit(0 if failures.is_empty() else 1)
