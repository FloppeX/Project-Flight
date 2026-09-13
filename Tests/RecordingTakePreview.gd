extends SceneTree
## Script-free production aircraft/carrier visuals, staged as a short fly-by.
## Produces a reusable take with two angles; no live scenario is modified.
var mode: Node

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	mode = root.get_node("RecordingMode")
	mode.process_mode = Node.PROCESS_MODE_ALWAYS
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.36, 0.24, 0.15)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.85, 0.77, 0.61)
	environment.environment.ambient_light_energy = 0.7
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -30, 0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	scene.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2500, 2500)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.56, 0.37, 0.21)
	floor_mesh.material_override = material
	scene.add_child(floor_mesh)
	var aircraft: Node3D = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	var carrier: Node3D = load("res://LandCarrier/LandCarrier.tscn").instantiate()
	_strip(aircraft)
	_strip(carrier)
	scene.add_child(aircraft)
	scene.add_child(carrier)
	aircraft.name = "Aircraft_5_Flyby"
	carrier.name = "Carrier_Flyby"
	aircraft.position = Vector3(28, 70, -65)
	carrier.position.y = 40
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = aircraft.position + Vector3(35, 15, 50)
	camera.look_at(aircraft.position)
	camera.make_current()
	mode.enter()
	var actors: Array[Node3D] = [aircraft, carrier]
	if not mode.start_recording(actors):
		push_error("Preview failed to record: %s" % mode._message)
		quit(1)
		return
	mode.recording = false
	paused = true
	for frame in range(1, 91):
		var t := frame / 30.0
		aircraft.position = Vector3(28, 70 + sin(t) * 2.0, -65 + t * 45)
		aircraft.rotation.z = sin(t) * 0.12
		carrier.position.z = t * 8.0
		var propeller: Node3D = aircraft.get_node_or_null("aircraft_5/Aircraft 2 propeller")
		if propeller != null: propeller.rotation.z = t * 12.0
		for gear_name in ["NoseGearRig", "LeftGearRig", "RightGearRig"]:
			var gear: Node3D = aircraft.get_node_or_null(NodePath(gear_name))
			if gear != null: gear.rotation.x = -clampf(t / 3.0, 0.0, 1.0) * PI / 2.0
		mode.take.sample(t)
	mode.elapsed = 3.0
	mode.enter_replay()
	mode._panel.show()
	for frame in range(3): await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures/recording")
		root.get_texture().get_image().save_png("res://captures/recording/controls.png")
	mode.seek(0.0)
	mode._selected_subject = 0
	mode.camera.global_position = mode.take.subjects[0].global_position + Vector3(22, 8, 33)
	mode.camera.look_at(mode.take.subjects[0].global_position)
	mode.camera.attach(mode.take.subjects[0], 1)
	mode.camera.aim_target = mode.take.subjects[0]
	mode.add_key()
	mode.seek(3.0)
	mode.camera.move_camera(Vector3.ZERO, Vector2.ZERO, 0.0, 0.0)
	mode.add_key()
	mode.selected_shot = 1
	mode._selected_subject = 1
	mode.seek(0.0)
	mode.camera.global_position = Vector3(150, 130, 170)
	mode.camera.look_at(Vector3(0, 40, 0))
	mode.camera.aim_target = null
	mode.camera.attach(mode.take.subjects[1], 2)
	mode.add_key()
	mode.seek(3.0)
	mode.camera.move_camera(Vector3.ZERO, Vector2.ZERO, 0.0, 0.0)
	mode.add_key()
	var directory: String = mode.save_take()
	DirAccess.make_dir_recursive_absolute("res://captures/recording")
	var pointer := FileAccess.open("res://captures/recording/preview_take_path.txt", FileAccess.WRITE)
	pointer.store_string(directory)
	pointer.close()
	mode._panel.hide()
	for shot in range(2):
		mode.selected_shot = shot
		mode.play_shot = true
		mode.seek(1.5)
		for frame in range(8): await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/recording/shot_%s.png" % ("A" if shot == 0 else "B"))
	print("[RecordingTakePreview] PASS tracks=%d frames=%d estimate_mib=%.2f path=%s" % [mode.take.copies.size(), mode.take.frames.size(), mode.take.estimated_bytes / 1048576.0, directory])
	mode.exit()
	mode.clear_take()
	quit(0)

func _strip(node: Node) -> void:
	node.set_script(null)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is RigidBody3D: node.freeze = true
	if node is Camera3D: node.current = false
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.autoplay = false
	for child in node.get_children(): _strip(child)
