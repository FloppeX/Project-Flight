extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene

	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.38, 0.55, 0.72)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	environment.environment.ambient_light_energy = 1.0
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	scene.add_child(sun)

	var bird_scene := load("res://Wildlife/CanyonVulture.tscn") as PackedScene
	var glide := bird_scene.instantiate() as Node3D
	scene.add_child(glide)
	glide.set_physics_process(false)
	glide.position = Vector3(-2.2, 1.8, 0.0)
	var flap := bird_scene.instantiate() as Node3D
	scene.add_child(flap)
	flap.set_physics_process(false)
	flap.position = Vector3(2.2, 1.8, 0.0)
	flap.call("_start_flap_burst", 2)
	flap.call("_update_wings", 0.18)

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(18.0, 12.0)
	var ground := MeshInstance3D.new()
	ground.mesh = ground_mesh
	ground.position.y = -0.1
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.42, 0.23, 0.11)
	ground.material_override = ground_material
	scene.add_child(ground)

	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0.0, 4.2, 10.5)
	camera.look_at(Vector3(0.0, 1.5, 0.0))
	camera.fov = 42.0
	camera.current = true
	for _frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var output := "user://canyon_vulture_preview.png"
	var error := root.get_texture().get_image().save_png(output)
	if error != OK:
		push_error("CANYON_VULTURE_RENDER_FAIL save=%s" % error_string(error))
		quit(1)
		return
	print("CANYON_VULTURE_RENDER_PASS path=%s" % ProjectSettings.globalize_path(output))
	quit(0)
