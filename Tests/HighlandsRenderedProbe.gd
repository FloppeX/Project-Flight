extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("FloatingOrigin").enabled = false
	root.get_node("TerrainNavGrid").set_process(false)
	for service in ["EnemyBaseManager", "EnemyOpsManager"]:
		root.get_node(service).set("_disabled_for_test", true)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := Node3D.new()
	scene.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.48, 0.61, 0.71)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.80, 0.86)
	environment.environment.ambient_light_energy = 0.35
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, -35.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 14000.0
	scene.add_child(sun)
	var regional := OS.get_cmdline_user_args().has("--regional")
	var terrain := preload("res://Environment/LowPolyTerrain.gd").new()
	terrain.generate_on_ready = false
	terrain.use_streaming = false
	terrain.generate_collision = true
	terrain.quads_x = 280
	terrain.quads_z = 280
	terrain.cell_size_m = 36.0
	terrain.seed = 22551
	terrain.plateau_height_m = 500.0
	terrain.base_height_offset_m = 220.0
	terrain.canyon_wall_color = Color(0.667926, 0.427286, 0.274156)
	terrain.canyon_upper_color = Color(0.744223, 0.61311, 0.439865)
	terrain.steep_slope_color = Color(0.338234, 0.326747, 0.303773)
	terrain.set_map_profile("canyon_highlands")
	scene.add_child(terrain)
	if regional:
		terrain.quads_x = 2778
		terrain.quads_z = 2778
		terrain.use_streaming = true
		terrain.set_process(false)
		terrain._refresh_layout()
		terrain._noises = terrain._build_noises()
		terrain._shared_material = terrain._build_material()
	else:
		terrain.rebuild()
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.far = 30000.0
	camera.fov = 48.0
	camera.current = true
	var views := [
		[Vector3(4200, 3400, 4800), Vector3(0, 800, 0), "highlands_overview.png"],
		[Vector3(2900, 1550, 2200), Vector3(250, 950, 0), "highlands_ascent.png"],
	]
	if regional:
		views.clear()
		for centre in [Vector3(-12500, 0, -12500), Vector3(12500, 0, -12500), Vector3(-12500, 0, 12500), Vector3(12500, 0, 12500)]:
			views.append([centre + Vector3(3500, 6500, 3500), centre + Vector3(0, 700, 0),
				"highlands_region_%d_%d.png" % [centre.x, centre.z]])
	for view in views:
		if regional:
			var centre: Vector3 = view[1]
			var gx := int(round((centre.x - terrain._x0) / terrain.cell_size_m))
			var gz := int(round((centre.z - terrain._z0) / terrain.cell_size_m))
			var arrays: Array = terrain._build_chunk_arrays(gx - 155, gx + 155, gz - 155, gz + 155)
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			terrain._mesh_node.mesh = mesh
			terrain._mesh_node.material_override = terrain._shared_material
		camera.position = view[0]
		camera.look_at(view[1])
		camera.reset_physics_interpolation()
		await physics_frame
		await physics_frame
		for frame in 30:
			await process_frame
		# Deferred view-distance settings can override a newly created camera.
		camera.far = 40000.0
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://screenshots/" + view[2]
		var error := viewport.get_texture().get_image().save_png(path)
		if error != OK:
			quit(1)
			return
		print("HIGHLANDS_RENDER path=", ProjectSettings.globalize_path(path))
	if regional:
		quit(0)
		return
	# Actual physics raycasts verify that the generated collision follows the ramp.
	await physics_frame
	var space := scene.get_world_3d().direct_space_state
	for i in range(21):
		var point := terrain.get_highlands_route_position(i / 20.0)
		point += Vector3(0.37, 0.0, 0.21)
		point.y = terrain.get_height(point)
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1500.0, point - Vector3.UP * 10.0)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or absf(hit.position.y - point.y) > 0.2:
			push_error("Highlands ramp mesh/collision mismatch at %s hit=%s" % [point, hit])
			quit(1)
			return
	print("HIGHLANDS_COLLISION_PASS samples=21")
	quit(0)
