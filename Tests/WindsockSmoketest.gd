extends SceneTree

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var field := load("res://Weather/WindField.gd").new() as Node3D
	scene.add_child(field)
	field.set_physics_process(false)
	field.set("gust_amplitude_mps", Vector3.ZERO)
	field.set("turbulence_amplitude_mps", Vector3.ZERO)
	var socks: Array[Node3D] = []
	for i in 3:
		field.set("prevailing_velocity_mps", Vector3([0.0, 3.0, 10.0][i], 0, 0))
		var sock := load("res://LandCarrier/Windsock.tscn").instantiate() as Node3D
		scene.add_child(sock)
		sock.position.x = (i - 1) * 6.0
		sock.set_process(false)
		sock.set("flutter_enabled", false)
		sock.call("update_wind", 0.0, true)
		assert(sock.get("_materials").size() == 4)
		socks.append(sock)
		var label := Label3D.new()
		label.text = ["Calm", "3 m/s", "10 m/s"][i]
		label.position = Vector3(sock.position.x, 0.3, 1.0)
		label.font_size = 80
		label.pixel_size = 0.012
		scene.add_child(label)
	assert(socks[0].get("_materials")[0].get_shader_parameter("droop") == 1.0)
	assert(socks[2].get("_materials")[0].get_shader_parameter("droop") == 0.0)
	assert(is_equal_approx(socks[0].get("_materials")[0].get_shader_parameter("fixed_cuff_fraction"), 0.12))
	# World wind remains world-aligned even under a rotated mount.
	var probe := load("res://LandCarrier/Windsock.tscn").instantiate() as Node3D
	var body := CharacterBody3D.new()
	body.rotation.y = 1.2
	scene.add_child(body)
	body.add_child(probe)
	probe.set_process(false)
	field.set("prevailing_velocity_mps", Vector3(0, 0, 6))
	probe.call("update_wind", 0.0, true)
	assert(probe.get("_swivel").global_basis.x.normalized().dot(Vector3.BACK) > 0.999)
	field.set("enabled", false)
	body.velocity = Vector3(5, 0, 0)
	probe.call("update_wind", 0.0, true)
	assert(probe.call("get_relative_wind").is_equal_approx(Vector3(-5, 0, 0)))
	assert(probe.get("_swivel").global_basis.x.normalized().dot(Vector3.LEFT) > 0.999)
	body.queue_free()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1600, 900))
		var camera := Camera3D.new()
		scene.add_child(camera)
		camera.position = Vector3(5, 6, 20)
		camera.look_at(Vector3(1.5, 3, 0))
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 21
		camera.current = true
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35, -30, 0)
		scene.add_child(light)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.16, 0.21, 0.28)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.6
		scene.add_child(environment)
		if "--carrier-preview" in OS.get_cmdline_user_args():
			for sock in socks: sock.hide()
			for child in scene.get_children():
				if child is Label3D: child.hide()
			var carrier_visual := load("res://Models/LandCarrier/CarrierWithInterior.tscn").instantiate() as Node3D
			carrier_visual.rotation.y = PI
			scene.add_child(carrier_visual)
			# Read the actual mounted scene position, rather than a separate mock position.
			var carrier_state: SceneState = load("res://LandCarrier/LandCarrier2.tscn").get_state()
			var mounted := load("res://LandCarrier/Windsock.tscn").instantiate() as Node3D
			for node in carrier_state.get_node_count():
				if carrier_state.get_node_name(node) == &"Windsock":
					for property in carrier_state.get_node_property_count(node):
						if carrier_state.get_node_property_name(node, property) == &"position":
							mounted.position = carrier_state.get_node_property_value(node, property)
			field.set("enabled", true)
			field.set("prevailing_velocity_mps", Vector3(-5, 0, 0))
			scene.add_child(mounted)
			camera.position = Vector3(-45, 20, -52)
			camera.look_at(Vector3(-15, 3, -19))
			camera.size = 38
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		var filename := "windsock_carrier_preview.png" if "--carrier-preview" in OS.get_cmdline_user_args() else "windsock_preview.png"
		root.get_texture().get_image().save_png("user://" + filename)
	print("WINDSOCK_PASS sections=4 fixed_cuff=true calm_droop=true strong_extension=true rotated_mount=true carrier_airflow=true")
	quit()
