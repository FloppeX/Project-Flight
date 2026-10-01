extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var aircraft = load("res://Aircraft/Aircraft_15.tscn").instantiate()
	aircraft.freeze = true
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	aircraft.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	scene.add_child(aircraft)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.19, 0.24)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	scene.add_child(sun)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.fov = 65
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/aircraft15_blend"))
	for view in ["exterior", "cockpit"]:
		if view == "exterior":
			camera.position = Vector3(10, 5, 12)
			camera.look_at(Vector3(0, 0, 0))
		else:
			camera.global_transform = aircraft.get_node("CameraCockpit/Camera3D").global_transform
			camera.look_at(aircraft.to_global(Vector3(-0.32, -0.05, 3.2)))
		for frame in 24: await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png("res://captures/aircraft15_blend/" + view + ".png") == OK)
	print("AIRCRAFT15_BLEND_RENDERED_PASS")
	quit()
