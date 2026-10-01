extends "res://Tests/TailhookDeploymentSmoketest.gd"

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var deck := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	collider.shape = box
	collider.position.y = -0.5
	deck.add_child(collider)
	var surface := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	surface.mesh = mesh
	surface.position = collider.position
	deck.add_child(surface)
	scene.add_child(deck)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(7, 2.0, -7)
	camera.look_at(Vector3(0, 0.5, -1.4))
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.shadow_enabled = true
	scene.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	scene.add_child(env)
	for model in ["Aircraft_1", "Aircraft_2", "Aircraft_5", "Aircraft_7", "Aircraft_8", "Aircraft_14", "CompleteFighterJet"]:
		var aircraft := load("res://Aircraft/%s.tscn" % model).instantiate() as RigidBody3D
		strip_scripts(aircraft)
		aircraft.freeze = true
		scene.add_child(aircraft)
		var hook := aircraft.get_node("TailHook")
		hook.deploy()
		hook.set_technical_index_preview_fraction(1.0)
		for slope in [0.0, 10.0, -10.0]:
			deck.rotation.z = deg_to_rad(slope)
			aircraft.position = Vector3(0, 1.8, 0)
			aircraft.rotation.x = deg_to_rad(6.0)
			await physics_frame
			await process_frame
			hook._physics_process(1.0 / 60.0)
			var tip: Vector3 = hook.get_node("HookArea").global_position
			var normal := deck.global_basis.y
			_check(tip.dot(normal) >= hook.deck_tip_clearance_m - 0.001, model + " tip stays above deck")
			var local_tip := aircraft.to_local(tip)
			_check(absf(local_tip.distance_to(hook.stowed_mount_position) - hook.position.distance_to(hook.stowed_mount_position)) < 0.001, model + " hinge preserves shaft length")
			var visual: Transform3D = aircraft.global_transform * hook.transform * hook.get_node("Tailhook").transform
			_check(visual.origin.distance_to(tip) < 0.001, model + " mesh and wire share tip")
			_check((visual * Vector3(0, hook._shaft_length, 0)).distance_to(aircraft.to_global(hook.stowed_mount_position)) < 0.001, model + " fixed hinge mount")
			if model == "Aircraft_1" and is_zero_approx(slope):
				var cable := (load("res://LandCarrier/arresting_cable.tscn") as PackedScene).instantiate()
				scene.add_child(cable)
				cable.set_physics_process(false)
				cable.position = Vector3(0, 0.10, -4)
				cable.set("_hook_node", hook.get_node("HookArea"))
				cable.set("_engaged", true)
				_check(cable._hook_global_position().distance_to(tip) < 0.001, "cable reads hinged tip")
				cable._update_cable_visuals(tip)
				if "--rendered" in OS.get_cmdline_user_args():
					await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("res://logs/tailhook_deck_contact.png")
				cable.queue_free()
		aircraft.position.y = 10.0
		await physics_frame
		await process_frame
		hook._physics_process(1.0 / 60.0)
		_check(hook.get_node("HookArea").global_position.distance_to(hook.global_position) < 0.001, model + " free hook returns to deployed rest")
		aircraft.queue_free()
		await process_frame
	for failure in failures:
		push_error(failure)
	print("TAILHOOK_DECK_CONTACT_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
