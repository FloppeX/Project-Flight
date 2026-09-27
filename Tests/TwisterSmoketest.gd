extends SceneTree

class DamageBody extends RigidBody3D:
	var max_health := 100.0
	var health := 100.0
	func take_damage(amount: float) -> void:
		health -= amount

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	await process_frame
	root.get_node("FloatingOrigin").enabled = false
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var twister := load("res://Weather/Twister.gd").new() as Node3D
	scene.add_child(twister)
	twister.set_physics_process(false)
	twister.start_at(Vector3.ZERO, Vector3.RIGHT)
	twister.elapsed_s = 20.0
	twister.strength = 1.0
	var axis: Vector3 = twister.get_axis_offset(100.0 / twister.height_m) + Vector3.UP * 100.0
	var wind: Vector3 = twister.get_wind_at(axis)
	check(wind.is_finite() and wind.y > 20.0, "Axis has finite updraft")
	var east: Vector3 = twister.get_wind_at(axis + Vector3.RIGHT * 60.0)
	var west: Vector3 = twister.get_wind_at(axis + Vector3.LEFT * 60.0)
	check(east.z > 40.0 and west.z < -40.0, "Opposite sides have opposite strong rotating wind")
	check(east.x < 0.0 and west.x > 0.0, "Inflow pulls toward the column")
	check(twister.get_wind_at(Vector3(800, 100, 0)) == Vector3.ZERO, "Outside radius is calm")
	check(twister.get_wind_at(Vector3(0, 1200, 0)) == Vector3.ZERO, "Above funnel is calm")
	check(twister.get_wind_at(Vector3(0, -40, 0)) == Vector3.ZERO, "Below terrain frame is calm")
	var max_speed := 0.0
	for y in range(0, 1201, 50):
		for x in range(-800, 801, 10):
			var sample: Vector3 = twister.get_wind_at(Vector3(x, y, 0))
			check(sample.is_finite(), "Wind grid stays finite")
			max_speed = maxf(max_speed, sample.length())
	check(max_speed < 85.0, "Default twister wind remains bounded")
	var boundary: Vector3 = axis + Vector3.RIGHT * 549.0
	check(twister.get_wind_at(boundary).length() < 0.01, "Outer boundary fades smoothly")
	var field := load("res://Weather/WindField.gd").new() as Node3D
	scene.add_child(field)
	field.set_physics_process(false)
	field.gust_amplitude_mps = Vector3.ZERO
	field.turbulence_amplitude_mps = Vector3.ZERO
	field._physics_process(0.0)
	check(field.get_velocity_at(axis).is_equal_approx(field.prevailing_velocity_mps + wind), "Shared aircraft field includes twister")
	var front := load("res://Weather/DustFront.gd").new() as Node3D
	front.automatic_start = false
	scene.add_child(front)
	front.set_physics_process(false)
	front.start_at(Vector3(0, -500, 0), Vector3.BACK)
	front.strength = 1.0
	field._physics_process(0.0)
	check(field.get_velocity_at(axis).is_equal_approx(field.prevailing_velocity_mps + wind + front.get_wind_at(axis)), "Dust and twister winds coexist")
	var body := DamageBody.new()
	body.freeze = true
	scene.add_child(body)
	body.add_to_group("ai_aircraft")
	body.position = axis
	twister._apply_debris_damage(1.0)
	check(body.health < 95.0, "AI aircraft suffers core debris damage")
	body.add_to_group("aircraft")
	var old_health := body.health
	twister._apply_debris_damage(1.0)
	check(is_equal_approx(old_health - body.health, 6.0), "Overlapping aircraft groups do not double damage")
	body.position = axis + Vector3.RIGHT * 350.0
	old_health = body.health
	twister._apply_debris_damage(1.0)
	check(body.health == old_health, "Outer wind band causes no debris damage")
	body.position = axis
	var roof := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 2, 40)
	shape.shape = box
	roof.add_child(shape)
	scene.add_child(roof)
	roof.position = axis + Vector3.UP * 15.0
	await physics_frame
	await physics_frame
	twister._apply_debris_damage(1.0)
	check(body.health == old_health, "Overhead shelter prevents debris damage")
	roof.queue_free()
	body.queue_free()
	await process_frame
	await physics_frame
	for path in ["res://Aircraft/Aircraft_1.tscn", "res://Aircraft/Aircraft_11.tscn"]:
		var aircraft := load(path).instantiate() as RigidBody3D
		aircraft.freeze = true
		aircraft.process_mode = Node.PROCESS_MODE_DISABLED
		aircraft.position = axis
		scene.add_child(aircraft)
		await process_frame
		await process_frame
		await physics_frame
		var parts := aircraft.get_node_or_null("PartDamageModel")
		var initial: float = parts.get_zone_health(&"fuselage") if parts != null else aircraft.current_health
		aircraft.hide()
		aircraft.process_mode = Node.PROCESS_MODE_INHERIT
		aircraft.set("_last_damage_ms", 0)
		twister._apply_debris_damage(1.0)
		aircraft.process_mode = Node.PROCESS_MODE_DISABLED
		var after: float = parts.get_zone_health(&"fuselage") if parts != null else aircraft.current_health
		check(is_equal_approx(after, initial * 0.94), "Real aircraft takes core damage despite visual hiding: " + path)
		aircraft.queue_free()
		await process_frame
	var shift := Vector3(10000, 0, -8000)
	root.get_node("FloatingOrigin").shift_origin(shift)
	var shifted_wind: Vector3 = twister.get_wind_at(axis - shift)
	print("Twister origin delta: ", shifted_wind.distance_to(wind), " position=", twister.global_position)
	check(shifted_wind.distance_to(wind) < 0.002, "Origin shift preserves vortex within float precision")
	twister.set_physics_process(true)
	paused = true
	var old_position := twister.global_position
	var old_time: float = twister.elapsed_s
	for i in 4: await process_frame
	check(old_position == twister.global_position and old_time == twister.elapsed_s, "Pause freezes twister")
	paused = false
	twister.set_physics_process(false)
	twister.enabled = false
	check(twister.get_wind_at(axis - shift) == Vector3.ZERO, "Disabled twister contributes no forces")
	var menu := load("res://UI/VehicleSpawnMenu.gd").new() as CanvasLayer
	scene.add_child(menu)
	var entry: Dictionary = {}
	for candidate in menu.get_spawn_entries():
		if candidate.get("spawn_kind", "") == "twister":
			entry = candidate
	check(not entry.is_empty(), "Spawn menu exposes twister in Environment")
	check(menu.spawn_environment_entry(entry) == twister, "Menu reuses existing twister")
	check(twister.enabled and twister.strength == 1.0, "Menu restarts disabled twister immediately")
	check(menu.spawn_environment_entry(entry) == twister and get_nodes_in_group("twister").size() == 1, "Repeated spawn stays bounded")
	check(is_instance_valid(front) and front.enabled, "Twister spawning preserves dust storm")
	front.enabled = false
	var overlay := root.get_node("WorldMapOverlay")
	overlay._refresh_weather()
	check("TWISTER" in overlay.get("_weather_info").text, "Map reports twister without a dust front")
	front.enabled = true
	overlay._refresh_weather()
	check("DUST" in overlay.get("_weather_info").text and "TWISTER" in overlay.get("_weather_info").text, "Map reports both weather types")
	front.enabled = false
	twister.elapsed_s = twister.lifetime_s - 1.0
	twister._physics_process(2.0)
	check(not twister.enabled and twister.strength == 0.0, "Twister expires cleanly")
	menu.queue_free()
	if "--render" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _render(scene, twister)
	print("TWISTER_SMOKETEST_", "OK" if failures.is_empty() else "FAILED", " peak_sampled_wind=", max_speed, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _render(scene: Node3D, twister: Node3D) -> void:
	var terrain := load("res://Environment/LowPolyTerrainPrototype.tscn").instantiate() as Node3D
	terrain.use_streaming = false
	terrain.generate_collision = false
	terrain.quads_x = 256
	terrain.quads_z = 256
	terrain.cell_size_m = 32.0
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
	var camera := Camera3D.new()
	camera.far = 20000.0
	scene.add_child(camera)
	camera.current = true
	twister.enabled = true
	twister.start_at(Vector3.ZERO, Vector3.RIGHT)
	twister.elapsed_s = 20.0
	twister.strength = 1.0
	var base: Vector3 = twister.global_position
	var output := "res://captures/twister"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for pose in [
		["outside", Vector3(1800, 600, 1600), Vector3(0, 450, 0)],
		["approach", Vector3(500, 260, 550), Vector3(0, 340, 0)],
		["inside", Vector3(25, 160, 15), Vector3(250, 160, 0)],
		["above", Vector3(1000, 1500, 1100), Vector3(0, 400, 0)]
	]:
		camera.position = base + pose[1]
		camera.position.y = maxf(camera.position.y, terrain.get_height(camera.position) + 35.0)
		camera.look_at(base + pose[2])
		# Fog updates on a timer; a fixed frame count can finish before it at high FPS.
		await create_timer(cycle.update_interval_s + 0.1).timeout
		for i in 35:
			twister.elapsed_s += 1.0 / 60.0
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/" + pose[0] + ".png")
	var aircraft := load("res://Aircraft/Aircraft_1.tscn").instantiate() as RigidBody3D
	aircraft.freeze = true
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	aircraft.position = base + Vector3.UP * 160.0 + twister.get_axis_offset(160.0 / twister.height_m)
	scene.add_child(aircraft)
	await process_frame
	await process_frame
	var cockpit := aircraft.get_node("CameraCockpit/Camera3D") as Camera3D
	cockpit.current = true
	aircraft.get_node("CockpitCanopyVisibility")._update_canopy_visibility()
	await create_timer(cycle.update_interval_s + 0.1).timeout
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/cockpit.png")
	check(we.environment.volumetric_fog_length < 400.0, "Twister fog concentrates samples near cockpit")
	camera.current = true
	aircraft.queue_free()
	# The actual command overlay, without a dust front present.
	var grid := root.get_node("TerrainNavGrid")
	grid.set_process(false)
	grid._cols = 81
	grid._rows = 81
	grid.cell_size_m = 100.0
	grid._origin_x = -4000.0
	grid._origin_z = -4000.0
	var heights := PackedFloat32Array()
	heights.resize(81 * 81)
	for z in 81:
		for x in 81:
			heights[z * 81 + x] = terrain.get_height(Vector3(-4000 + x * 100, 0, -4000 + z * 100))
	grid._heights = heights
	grid._is_baked = true
	grid.bake_complete.emit()
	var overlay := root.get_node("WorldMapOverlay")
	overlay.set("_fog_mask_suppressed", true)
	overlay.set_console_visible(true)
	var deadline := Time.get_ticks_msec() + 45000
	while root.get_node("TerrainMapCache").get_textures().is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/map.png")
	overlay.set_console_visible(false)
