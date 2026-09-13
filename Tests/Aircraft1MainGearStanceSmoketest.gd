extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func disable_updates(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		disable_updates(child)

func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	var craft = load("res://Aircraft/Aircraft_1.tscn").instantiate()
	craft.freeze = true
	craft.position.y = 1000.0
	host.add_child(craft)
	await process_frame
	await physics_frame
	await process_frame
	disable_updates(craft)
	var gear = craft.get_node("LandingGear")
	var left = craft.get_node("LeftGearCollider")
	var right = craft.get_node("RightGearCollider")
	check(is_equal_approx(left.position.x - right.position.x, 3.6), "main gear track must be 3.6 m")
	check(is_equal_approx(left.position.y, -1.9637557) and is_equal_approx(right.position.y, -1.964),
		"gear height must stay unchanged")
	check(is_equal_approx(left.position.z, -0.12683374) and is_equal_approx(right.position.z, -0.12683374),
		"gear fore-aft position must stay unchanged")
	check(is_equal_approx(craft.get_node("CenterGearCollider").position.x, 0.0), "nose gear must stay centered")
	check(is_zero_approx(gear.deck_hold_force), "wider stance must not add downforce")
	for side in ["Left", "Right"]:
		var rig = craft.get_node(side + "GearRig")
		var collider = craft.get_node(side + "GearCollider")
		check(is_equal_approx(rig.position.x, collider.position.x), "rig and collider lateral anchors must match")
		check(gear.gear_collision_shapes[rig.gear_index] == collider, "visual rig must still follow its actual wheel")
		for fraction in [0.0, 0.5, 1.0]:
			rig.set_technical_index_preview_fraction(fraction)
			check(rig.visible == (fraction > 0.0), "rig deployment visibility must remain correct")
			check(is_equal_approx(rig.position.x, collider.position.x), "deployment must not shift main gear anchors")
	gear.use_accel_lean = false
	var initial_left_y: float = left.position.y
	gear.gear_compressions.assign([0.1, 0.1, 0.1])
	gear._update_suspension_collider_geometry(1.0)
	gear._update_lean_geometry()
	await physics_frame
	check(left.position.y > initial_left_y + 0.09, "main wheel collider must still compress")
	check(is_equal_approx(left.position.x - right.position.x, 3.6), "compression must retain wider track")
	for wheel in [left, right]:
		check(craft.safe_colliders.has(wheel), "widened wheel must retain safe-gear collision classification")
		for owner_id in craft.get_shape_owners():
			if craft.shape_owner_get_owner(owner_id) == wheel:
				var index: int = craft.shape_owner_get_shape_index(owner_id, 0)
				var physics_transform := PhysicsServer3D.body_get_shape_transform(craft.get_rid(), index)
				check(physics_transform.origin.distance_to(wheel.position) < 0.001, "physics and scene wheel positions must match")
	if OS.get_cmdline_user_args().has("--render"):
		craft.position.y = 0.0
		gear.gear_compressions.assign([0.0, 0.0, 0.0])
		gear._update_suspension_collider_geometry(1.0)
		gear._update_lean_geometry()
		for name in ["NoseGearRig", "LeftGearRig", "RightGearRig"]:
			craft.get_node(name).set_technical_index_preview_fraction(1.0)
		var world := WorldEnvironment.new()
		world.environment = Environment.new()
		world.environment.background_mode = Environment.BG_COLOR
		world.environment.background_color = Color("263340")
		world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world.environment.ambient_light_color = Color.WHITE
		world.environment.ambient_light_energy = 0.65
		host.add_child(world)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -35, 0)
		light.light_energy = 1.8
		host.add_child(light)
		var camera := Camera3D.new()
		host.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 12.0
		camera.position = Vector3(7, 0.2, 14)
		camera.look_at(Vector3(0, -0.8, 0))
		camera.make_current()
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var output := "user://aircraft_1_wider_main_gear.png"
		check(root.get_texture().get_image().save_png(output) == OK, "rendered preview must save")
		print("GEAR_STANCE_PREVIEW %s" % ProjectSettings.globalize_path(output))
	for failure in failures:
		push_error(failure)
	print("AIRCRAFT_1_MAIN_GEAR_STANCE_SMOKETEST %s" % ("PASS" if failures.is_empty() else "FAIL"))
	host.free()
	quit(0 if failures.is_empty() else 1)
