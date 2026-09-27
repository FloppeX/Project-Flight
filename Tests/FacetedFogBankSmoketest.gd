extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	await process_frame
	root.get_node("FloatingOrigin").enabled = false
	for manager_name in ["AirOpsManager", "EnemyOpsManager", "EnemyBaseManager", "GroundOpsManager"]:
		var manager := root.get_node_or_null(manager_name)
		if manager != null: manager.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	var menu := load("res://UI/VehicleSpawnMenu.gd").new() as CanvasLayer
	scene.add_child(menu)
	var entry: Dictionary = {}
	for candidate in menu.get_spawn_entries():
		if candidate.get("spawn_kind") == "fog_bank":
			entry = candidate
	check(not entry.is_empty(), "Environment catalog exposes fog bank")
	var bank := menu.spawn_environment_entry(entry) as Node3D
	check(bank != null and bank.initialized, "Menu initializes fog bank")
	bank.set_physics_process(false)
	bank.start_at(Vector3(2300, 200, -1700), Vector3(1, 0, 1))
	check(bank.get_intensity_at(bank.global_position) > 0.99, "Rotated bank has dense core")
	check(bank.get_intensity_at(bank.to_global(Vector3(2000, 0, 0))) == 0.0, "Outside remains clear")
	var edge := bank.to_global(Vector3(350, 0, 0))
	var intensity: float = bank.get_intensity_at(edge)
	check(intensity > 0.0 and intensity < 1.0, "Bank edge fades progressively")
	check(absf(bank.get_intensity_at(edge + Vector3.ONE) - intensity) < 0.03, "Edge has no abrupt density boundary")
	var shift := Vector3(12000, 0, -9000)
	root.get_node("FloatingOrigin").shift_origin(shift)
	check(absf(bank.get_intensity_at(edge - shift) - intensity) < 0.001, "Floating origin preserves density")
	bank.enabled = false
	bank._process(0.0)
	check(not bank.visible and bank.get_intensity_at(bank.global_position) == 0.0, "Disabled bank clears")
	check(menu.spawn_environment_entry(entry) == bank and get_nodes_in_group("faceted_fog_bank").size() == 1, "Respawn repositions and re-enables one bank")
	bank.set_physics_process(true)
	paused = true
	var old_time: float = bank.elapsed_s
	for i in 5: await process_frame
	check(is_equal_approx(bank.elapsed_s, old_time), "Pause freezes billows")
	paused = false
	bank.set_physics_process(false)
	root.get_node("FloatingOrigin").shift_origin(-shift)
	menu.queue_free()
	if "--render" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _render(scene, bank, camera)
	print("FACETED_FOG_BANK_SMOKETEST_", "OK" if failures.is_empty() else "FAILED", " failures=", failures)
	scene.queue_free()
	for i in 3: await process_frame
	quit(0 if failures.is_empty() else 1)

func _render(scene: Node3D, bank: Node3D, camera: Camera3D) -> void:
	var terrain := load("res://Environment/LowPolyTerrainPrototype.tscn").instantiate() as Node3D
	terrain.use_streaming = false
	terrain.generate_collision = false
	terrain.quads_x = 384
	terrain.quads_z = 384
	terrain.cell_size_m = 40.0
	scene.add_child(terrain)
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	we.environment.sky = Sky.new()
	we.environment.sky.sky_material = ProceduralSkyMaterial.new()
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	scene.add_child(sun)
	var cycle := load("res://Environment/DayNightCycle.gd").new() as Node
	cycle.freeze_daytime = true
	cycle.background_haze_density_scale = 1.0
	scene.add_child(cycle)
	cycle.apply_fixed_time_setting(true, 720)
	# Choose an actual low canyon floor for this art comparison.
	var ground := Vector3.ZERO
	ground.y = INF
	for x in range(-600, 601, 100):
		for z in range(-600, 601, 100):
			var p := Vector3(x, 0, z)
			p.y = terrain.get_height(p)
			if p.y < ground.y: ground = p
	bank.start_at(ground, Vector3.BACK)
	bank.elapsed_s = 10.0
	var base: Vector3 = bank.global_position
	camera.far = 6500.0
	var output := "res://captures/fog_bank"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for pose in [
		["outside", Vector3(650, 260, 750), Vector3.ZERO],
		["above", Vector3(400, 700, 450), Vector3.ZERO],
		["edge", Vector3(0, 20, 270), Vector3(0, 20, -400)],
		["inside", Vector3(0, 20, 0), Vector3(0, 20, -400)],
		["exit", Vector3(0, 20, -350), Vector3(0, 20, -800)]
	]:
		camera.position = base + pose[1]
		camera.position.y = maxf(camera.position.y, terrain.get_height(camera.position) + 25.0)
		camera.look_at(base + pose[2])
		await create_timer(0.5).timeout
		for i in 25: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/" + pose[0] + ".png")
		if pose[0] == "inside":
			check(we.environment.volumetric_fog_length < 600.0, "Interior fog concentrates samples near camera")
		if pose[0] == "exit":
			check(we.environment.volumetric_fog_length > 2000.0, "Leaving bank restores background fog range")
		if pose[0] == "outside":
			bank.enabled = false
			await create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output + "/comparison_without.png")
			bank.enabled = true
		if pose[0] in ["outside", "inside"] and "--profile" in OS.get_cmdline_user_args():
			await _profile_bank(bank, pose[0])
	var aircraft := load("res://Aircraft/Aircraft_1.tscn").instantiate() as RigidBody3D
	aircraft.freeze = true
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	aircraft.position = base + Vector3.UP * 20.0
	scene.add_child(aircraft)
	await process_frame
	await process_frame
	var cockpit := aircraft.get_node("CameraCockpit/Camera3D") as Camera3D
	cockpit.current = true
	aircraft.get_node("CockpitCanopyVisibility")._update_canopy_visibility()
	await create_timer(0.5).timeout
	for i in 25: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/cockpit.png")

func _profile_bank(bank: Node3D, pose: String) -> void:
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for active in [false, true, false, true]:
		bank.enabled = active
		await create_timer(0.5).timeout
		for i in 30: await process_frame
		var timings: Array[float] = []
		for i in 90:
			await process_frame
			timings.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		timings.sort()
		print("FOG_BANK_GPU pose=", pose, " enabled=", active, " median_ms=", timings[45])
	bank.enabled = true
