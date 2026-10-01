extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var model = load("res://Models/LandCarrier/Land carrier 4.glb").instantiate()
	model.rotation.y = PI
	scene.add_child(model)
	scene.add_child(load("res://LandCarrier/CarrierInteriorLighting.tscn").instantiate())
	var signs = load("res://LandCarrier/DeckStatusSigns.tscn").instantiate()
	scene.add_child(signs)
	signs.set_process(false)
	signs.apply_status({"land_available": true, "land_reason": "APPROACH CLEAR", "launch_available": false, "launch_reason": "TERRAIN AHEAD"})
	for pose in [Vector4(-22.357641, 8.863214, 3.0476203, PI), Vector4(-19.861603, 8.863214, 3.0476203, PI), Vector4(-18.63801, 13.318354, -7.422716, -PI / 2), Vector4(-18.63801, 13.318354, -5.030582, -PI / 2)]:
		var station = load("res://Models/computer station.glb").instantiate()
		station.position = Vector3(pose.x, pose.y, pose.z)
		station.rotation.y = pose.w
		scene.add_child(station)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.15, 0.22, 0.28)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.6
	scene.add_child(world)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.fov = 75.0
	var output := "res://captures/deck_status_signs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for room in ["CommandRoom", "AirOps"]:
		var panel: Node3D = signs.get_node(room)
		camera.global_position = Vector3(-21.05, 10.35, 0.3) if room == "CommandRoom" else Vector3(-22.4, 14.85, -6.22)
		camera.look_at(panel.global_position - Vector3(0, 0.3, 0))
		for frame in 24: await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(output + "/" + room + ".png")
		assert(result == OK)
	print("DECK_STATUS_SIGNS_RENDERED_PASS")
	quit()
