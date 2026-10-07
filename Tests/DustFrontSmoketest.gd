extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	await process_frame
	if "--main" in OS.get_cmdline_user_args():
		await _run_main()
		return
	root.get_node("FloatingOrigin").set("enabled", false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var front := load("res://Weather/DustFront.gd").new() as Node3D
	front.automatic_start = false
	scene.add_child(front)
	_expect(front.get_child_count() == 1 and front.get_child(0).get_node_or_null("CanopySandImpacts") != null, "Storm visuals and audio initialize")
	var visuals := front.get_child(0)
	_expect(visuals.get_node_or_null("LocalStormFog") != null, "Faceted wall retains local fog")
	_expect((visuals.get_node("ApproachingWallDust") as GPUParticles3D).amount == 2200, "Faceted wall retains approaching dust puffs")
	_expect((visuals.get_node("NearbyBlowingDust") as GPUParticles3D).amount == 320, "Faceted wall retains nearby grains")
	front.set_physics_process(false)
	# Fixed geometry isolates the established boundary checks from spawn variation.
	front.start_at(Vector3(2300, -500, -1700), Vector3(1, 0, 1), front.capture_appearance())
	front.elapsed_s = 120.0
	front.strength = 1.0
	var center := front.to_global(Vector3(0, 500, 0))
	_expect(front.get_intensity_at(center) > 0.99, "Storm core contains dense dust")
	_expect(front.get_intensity_at(front.to_global(Vector3(0, 500, 4000))) == 0.0, "Outside remains clear")
	_expect(front.get_intensity_at(front.to_global(Vector3(0, 2500, 0))) == 0.0, "Climbing above the front clears dust")
	var edge := front.to_global(Vector3(0, 500, front.half_depth_m * 0.94))
	var edge_density: float = front.get_intensity_at(edge)
	_expect(edge_density > 0.05 and edge_density < 0.95, "Leading edge blends gradually")
	_expect(absf(front.get_intensity_at(edge + Vector3.ONE) - edge_density) < 0.02, "Crossing edge is continuous")
	var core_wind: Vector3 = front.get_wind_at(center)
	_expect(core_wind.dot(front.global_basis.z) > 4.0, "Storm wind blows with front travel")
	var field := load("res://Weather/WindField.gd").new() as Node3D
	scene.add_child(field)
	field.set_physics_process(false)
	field.gust_amplitude_mps = Vector3.ZERO
	field.turbulence_amplitude_mps = Vector3.ZERO
	field._physics_process(0.0)
	_expect(field.get_velocity_at(center).is_equal_approx(field.prevailing_velocity_mps + core_wind), "Atmospheric wind includes storm wind")
	field.enabled = false
	_expect(field.get_velocity_at(center) == Vector3.ZERO, "Disabling wind disables storm forces too")
	field.enabled = true
	var shift := Vector3(12000, 0, -9000)
	root.get_node("FloatingOrigin").call("shift_origin", shift)
	_expect(front.get_wind_at(center - shift).is_equal_approx(core_wind), "Floating origin preserves storm air parcel")
	var old_position := front.global_position
	front._physics_process(10.0)
	_expect(front.global_position.is_equal_approx(old_position + front.get_travel_velocity() * 10.0), "Front advects at configured speed")
	front.enabled = false
	_expect(front.get_intensity_at(front.to_global(Vector3(0, 500, 0))) == 0.0, "Disabled front has no dust")
	front.enabled = true
	front.start_at(Vector3(0, -500, 0), Vector3.BACK)
	front.elapsed_s = 120.0
	front.strength = 1.0
	front.set_physics_process(true)
	paused = true
	var paused_position := front.global_position
	for i in 4: await process_frame
	_expect(front.global_position.is_equal_approx(paused_position), "Pausing freezes the weather")
	paused = false
	front.set_physics_process(false)
	var grid := root.get_node("TerrainNavGrid")
	grid.set_process(false)
	grid.set("_cols", 201)
	grid.set("_rows", 201)
	grid.set("cell_size_m", 100.0)
	grid.set("_origin_x", -10000.0)
	grid.set("_origin_z", -10000.0)
	var overlay := root.get_node("WorldMapOverlay")
	overlay.call("set_console_visible", true)
	await process_frame
	var layer: Control = overlay.get("_weather_layer")
	_expect(layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Weather never steals map clicks")
	var mapped: Vector2 = layer.call("world_to_map", Vector3.ZERO)
	_expect(mapped.is_equal_approx(layer.size * 0.5), "World origin is correctly placed on map")
	overlay.set("_map_zoom", 2.0)
	overlay.set("_map_view_center_uv", Vector2(0.65, 0.4))
	overlay.call("_apply_map_view")
	var rect: Rect2 = overlay.call("_get_map_view_uv_rect")
	mapped = layer.call("world_to_map", Vector3.ZERO)
	_expect(mapped.is_equal_approx((Vector2(0.5, 0.5) - rect.position) / rect.size * layer.size), "Weather follows map zoom and pan")
	var button: Button = overlay.get("_weather_button")
	button.button_pressed = false
	_expect(not layer.visible and not (overlay.get("_overview_weather_layer") as Control).visible, "Toggle hides both weather overlays")
	button.button_pressed = true
	overlay.call("set_console_visible", false)
	if "--render" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _render(scene, front, overlay)
	if _failures.is_empty():
		print("DUST_FRONT_SMOKETEST_OK boundary=true wind=true origin=true pause=true map=true")
	else:
		print("DUST_FRONT_SMOKETEST_FAILED ", _failures)
	quit(0 if _failures.is_empty() else 1)

func _run_main() -> void:
	# The authored scene must leave dust to the Environment spawn menu.
	var scene := load("res://Main_Scene.tscn").instantiate() as Node3D
	var front := scene.get_node("DustFront") as Node3D
	_expect(not front.automatic_start, "Main scene must not automatically start its dust front")
	_expect(not front.initialized, "Main-scene dust front starts dormant")
	scene.free()
	if _failures.is_empty():
		print("DUST_FRONT_MAIN_SCENE_OK dormant=true")
	quit(0 if _failures.is_empty() else 1)

func _render(scene: Node3D, front: Node3D, overlay: Node) -> void:
	var camera := Camera3D.new()
	camera.far = 40000.0
	scene.add_child(camera)
	camera.current = true
	var terrain := load("res://Environment/LowPolyTerrainPrototype.tscn").instantiate() as Node3D
	terrain.set("use_streaming", false)
	terrain.set("generate_collision", false)
	terrain.set("quads_x", 384)
	terrain.set("quads_z", 384)
	terrain.set("cell_size_m", 52.0)
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
	front.start_at(Vector3(0, -250, 0), Vector3.BACK)
	front.elapsed_s = 120.0
	front.strength = 1.0
	var poses := [
		["outside", Vector3(0, 650, 4500), Vector3(0, 800, 0)],
		["approach", Vector3(0, 650, 3250), Vector3(0, 800, 0)],
		["edge", Vector3(0, 500, 2650), Vector3(0, 400, 0)],
		["inside", Vector3(0, 400, 900), Vector3(0, 250, -2500)],
		["above", Vector3(7000, 2600, 3500), Vector3(0, 500, 0)]
	]
	var output := "res://captures/dust_front"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for pose in poses:
		camera.position = pose[1]
		camera.look_at(pose[2])
		for i in 45: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/" + pose[0] + ".png")
		print("DUST_RENDER ", pose[0])
	# Real cockpit geometry must occlude the dust while grains remain visible
	# beyond the windshield. Freeze the test aircraft, but provide cruise airflow.
	var aircraft := load("res://Aircraft/Aircraft_1.tscn").instantiate() as RigidBody3D
	aircraft.freeze = true
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	aircraft.position = Vector3(0, 400, 900)
	aircraft.rotation.y = PI
	scene.add_child(aircraft)
	await process_frame
	await process_frame
	var cockpit := aircraft.get_node("CameraCockpit/Camera3D") as Camera3D
	cockpit.far = 40000.0
	cockpit.current = true
	aircraft.get_node("CockpitCanopyVisibility").call("_update_canopy_visibility")
	for level in [2, 5]:
		front.severity = level
		for i in 60:
			aircraft.linear_velocity = Vector3(0, 0, -110)
			await process_frame
		cycle._update(cycle._t)
		_expect(front.get_child(0).get("_particles").emitting, "Cockpit has exterior blowing dust")
		_expect(front.get_child(0).get_node("CanopySandImpacts")._ticks.playing, "Cockpit hears canopy grain impacts")
		_expect(front.get_child(0).get("_particle_draw_material").get_shader_parameter("cockpit_view"), "Cockpit dust has cabin clearance")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/cockpit_strength_%d.png" % level)
		print("DUST_RENDER cockpit_strength_", level)
		_expect(we.environment.volumetric_fog_length < 200.0 if level == 5 else we.environment.volumetric_fog_length < 1600.0, "Dense fog sampling stays near the camera")
	camera.current = true
	await process_frame
	await process_frame
	_expect(not front.get_child(0).get_node("CanopySandImpacts")._ticks.playing, "Exterior camera stops canopy impacts")
	aircraft.queue_free()
	front.severity = 2
	# Bake a small genuine terrain map for the actual console's layout check.
	var grid := root.get_node("TerrainNavGrid")
	var heights := PackedFloat32Array()
	heights.resize(201 * 201)
	for z in 201:
		for x in 201:
			heights[z * 201 + x] = terrain.get_height(Vector3(-10000 + x * 100, 0, -10000 + z * 100))
	grid.set("_heights", heights)
	grid.set("_is_baked", true)
	grid.emit_signal("bake_complete")
	overlay.set("_map_zoom", 1.0)
	overlay.set("_map_view_center_uv", Vector2.ONE * 0.5)
	overlay.set("_fog_mask_suppressed", true)
	overlay.call("set_console_visible", true)
	var deadline := Time.get_ticks_msec() + 45000
	while root.get_node("TerrainMapCache").call("get_textures").is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/map.png")
	print("DUST_RENDER map")
