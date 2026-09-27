extends SceneTree

class FakeFlightDeckManager:
	extends Node3D
	var deck_y := 0.0
	func get_deck_height() -> float:
		return deck_y

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	root.get_node("FloatingOrigin").enabled = false
	for name in ["AirOpsManager", "EnemyOpsManager", "EnemyBaseManager", "GroundOpsManager"]:
		var manager := root.get_node_or_null(name)
		if manager != null: manager.process_mode = Node.PROCESS_MODE_DISABLED
	if "--main" in OS.get_cmdline_user_args():
		await _check_main_scene()
		return
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
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
	var ground: float = terrain.get_height(Vector3.ZERO)
	var deck := FakeFlightDeckManager.new()
	deck.deck_y = ground + 40.0
	scene.add_child(deck)
	deck.add_to_group("flight_deck_manager")
	var actual_height := "--actual" in OS.get_cmdline_user_args()
	var cycle := load("res://Environment/DayNightCycle.gd").new() as Node
	cycle.freeze_daytime = true
	cycle.background_haze_density_scale = 1.0
	if not actual_height:
		cycle.dust_layer_top_m = 1100.0
	cycle.dust_layer_top_variation_m = 0.0
	cycle.dust_layer_bottom_m = -500.0
	scene.add_child(cycle)
	cycle.apply_fixed_time_setting(true, 720)
	var camera := Camera3D.new()
	camera.far = 6500.0
	scene.add_child(camera)
	camera.current = true
	var electrical: Node3D = null
	if "--electrical" in OS.get_cmdline_user_args():
		electrical = load("res://Weather/ElectricalStorm.gd").new() as Node3D
		scene.add_child(electrical)
		electrical.set_physics_process(false)
		electrical.start_at(Vector3(0.0, ground, -800.0), Vector3.RIGHT)
		cycle._update_electrical_storm_uniforms()
		check(is_equal_approx(float(cycle._dust_deck_material.get_shader_parameter("storm_radius_m")),
			electrical.cloud_radius_m), "Electrical area darkens the authored dust deck")
		check(is_equal_approx(electrical._get_dust_layer_heights().x - deck.deck_y, 1200.0) if "--actual" in OS.get_cmdline_user_args() else true,
			"Electrical strike origin follows the carrier-relative layer height")
	var output := "res://captures/dust_layer"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var lower: float = deck.deck_y + cycle.dust_layer_top_m + cycle.dust_deck_vertical_offset_m
	if actual_height:
		check(is_equal_approx(lower - deck.deck_y, 1200.0), "Authored dust layer starts 1200 m above the carrier deck")
		check(is_equal_approx(cycle._get_dust_layer_top_for_position(Vector3.ZERO) + cycle.dust_deck_upper_vertical_offset_m - deck.deck_y, 2000.0), "Authored dust layer ends 2000 m above the carrier deck")
	var poses := [
		["below", Vector3(0, lower - 180, 0), Vector3(0, lower + 200, -1200)],
		["edge", Vector3(0, lower - 30, 0), Vector3(0, lower + 200, -1200)],
		["inside", Vector3(0, lower + 300, 0), Vector3(0, lower + 300, -1200)],
		["above", Vector3(0, deck.deck_y + cycle.dust_layer_top_m + 200, 0), Vector3(0, lower + 150, -1200)]
	]
	if actual_height:
		poses.push_front(["ground", Vector3(0, ground + 70, 0), Vector3(0, ground + 450, -1200)])
	if electrical != null:
		# Observe the charged region from beyond both actual deck surfaces.
		poses[poses.size() - 1] = ["above", Vector3(0, deck.deck_y + cycle.dust_layer_top_m + 1000, 1400),
			Vector3(0, deck.deck_y + cycle.dust_layer_top_m, -800)]
	for pose in poses:
		camera.position = pose[1]
		var target: Vector3 = pose[2]
		if electrical != null and pose[0] != "above":
			target.z = -800.0
			if pose[0] == "ground":
				target.y = lower + 100.0
		camera.look_at(target)
		if electrical != null:
			electrical._update_cloud(0.16)
			electrical._strike()
		await create_timer(0.5).timeout
		for i in 25: await process_frame
		await RenderingServer.frame_post_draw
		var prefix := ("electrical_" if electrical != null else "") + ("actual_" if actual_height else "")
		root.get_texture().get_image().save_png(output + "/" + prefix + pose[0] + ".png")
		print("DUST_LAYER_VIEW ", pose[0], " density=", we.environment.volumetric_fog_density, " range=", we.environment.volumetric_fog_length)
		if pose[0] == "below":
			check(we.environment.volumetric_fog_length > 2500.0, "Below the deck retains distant atmosphere")
		if pose[0] == "inside":
			check(we.environment.volumetric_fog_length <= 1600.0, "Inside the deck concentrates fog detail")
		if pose[0] == "above":
			check(we.environment.volumetric_fog_length > 2500.0, "Climbing above the deck restores the normal fog range")
		if pose[0] in ["below", "inside"] and "--profile" in OS.get_cmdline_user_args():
			await _profile_layer(cycle, pose[0])
	if electrical != null and "--electrical-timing" in OS.get_cmdline_user_args():
		electrical._strike()
		var impact: Vector3 = electrical._last_strike_impact
		var origin: Vector3 = electrical._last_strike_origin
		var timing_camera_pos := impact + Vector3(0.0, 550.0, 950.0)
		var camera_ground: float = terrain.get_height(timing_camera_pos)
		timing_camera_pos.y = maxf(timing_camera_pos.y, camera_ground + 450.0)
		camera.global_position = timing_camera_pos
		camera.look_at(origin.lerp(impact, 0.47))
		for timing in [["hit", 0.0], ["hold", 0.5], ["fade", 0.5], ["clear", 0.5]]:
			if timing[1] > 0.0:
				electrical._physics_process(timing[1])
			for i in 5: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output + "/electrical_strike_" + timing[0] + ".png")
	var lower_deck: MeshInstance3D = cycle._dust_deck
	var upper_deck: MeshInstance3D = cycle._dust_deck_upper
	var volume: FogVolume = cycle._dust_volume
	var lower_y := lower_deck.global_position.y
	var upper_y := upper_deck.global_position.y
	var volume_y := volume.global_position.y
	deck.deck_y += 75.0
	cycle._update(cycle._t)
	check(absf(lower_deck.global_position.y - lower_y - 75.0) < 0.01, "Lower deck follows the carrier deck height")
	check(absf(upper_deck.global_position.y - upper_y - 75.0) < 0.01, "Upper deck follows the carrier deck height")
	check(absf(volume.global_position.y - volume_y - 75.0) < 0.01, "Dust fog follows the carrier deck height")
	var original_xz := Vector2(lower_deck.global_position.x, lower_deck.global_position.z)
	camera.global_position += Vector3(400.0, 0.0, -300.0)
	cycle._update(cycle._t)
	check(Vector2(lower_deck.global_position.x, lower_deck.global_position.z).distance_to(original_xz) < 0.01, "Lower deck stays fixed as camera moves")
	check(Vector2(upper_deck.global_position.x, upper_deck.global_position.z).distance_to(original_xz) < 0.01, "Upper deck stays fixed as camera moves")
	check(Vector2(volume.global_position.x, volume.global_position.z).distance_to(original_xz) < 0.01, "Dust volume stays fixed as camera moves")
	var shift := Vector3(5000.0, 0.0, -4000.0)
	root.get_node("FloatingOrigin").shift_origin(shift)
	cycle._update(cycle._t)
	var shifted_xz := original_xz - Vector2(shift.x, shift.z)
	check(Vector2(lower_deck.global_position.x, lower_deck.global_position.z).distance_to(shifted_xz) < 0.01, "Lower deck retains floating-origin shift")
	check(Vector2(upper_deck.global_position.x, upper_deck.global_position.z).distance_to(shifted_xz) < 0.01, "Upper deck retains floating-origin shift")
	check(Vector2(volume.global_position.x, volume.global_position.z).distance_to(shifted_xz) < 0.01, "Dust volume retains floating-origin shift")
	print("DUST_LAYER_RENDER_", "OK" if failures.is_empty() else "FAILED", " failures=", failures)
	scene.queue_free()
	for i in 3: await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_main_scene() -> void:
	var scene := load("res://Main_Scene.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 3: await process_frame
	var cycle := scene.get_node("DayNightCycle")
	var manager := scene.get_node("LandCarrier/FlightDeckManager")
	cycle._update(cycle._t)
	var deck_y: float = manager.get_deck_height()
	check(absf(cycle._get_dust_layer_top_for_position(Vector3.ZERO) - deck_y - 2000.0) < 0.01, "Main scene dust top is 2000 m above its real flight deck")
	check(absf(cycle._dust_deck.global_position.y - deck_y - 1200.0) < 0.01, "Main scene dust floor is 1200 m above its real flight deck")
	print("DUST_LAYER_MAIN_", "OK" if failures.is_empty() else "FAILED", " deck_y=", deck_y, " failures=", failures)
	scene.queue_free()
	for i in 3: await process_frame
	quit(0 if failures.is_empty() else 1)

func _profile_layer(cycle: Node, pose: String) -> void:
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for active in [false, true, false, true]:
		cycle.dust_deck_enabled = active
		cycle._update(cycle._t)
		await create_timer(0.5).timeout
		var timings: Array[float] = []
		for i in 90:
			await process_frame
			timings.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		timings.sort()
		print("DUST_LAYER_GPU pose=", pose, " enabled=", active, " median_ms=", timings[45])
	cycle.dust_deck_enabled = true
	cycle._update(cycle._t)
