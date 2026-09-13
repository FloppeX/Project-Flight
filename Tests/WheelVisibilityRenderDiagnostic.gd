extends "res://tools/vehicle_lod_ab_benchmark.gd"
## Isolates wheel range only. All simulation is stopped; mesh/shadow LOD stays enabled.

func _run() -> void:
	create_timer(90.0).timeout.connect(func():
		push_error("Wheel visibility diagnostic timed out")
		quit(1))
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("SaveGameManager").set("autosave_enabled", false)
	Engine.max_fps = 0
	_build_world()
	await _spawn_vehicles()
	for vehicle in _vehicles: _stop_processing(vehicle)
	for _i in range(3): await process_frame
	for vehicle in _vehicles: _stop_processing(vehicle)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_camera.look_at(Vector3(0, 2, -700), Vector3.UP)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var phases: Array = []
	for distance_limit in [450.0, 0.0, 0.0, 450.0]:
		for vehicle in _vehicles:
			vehicle.set("wheel_mesh_visibility_distance_m", distance_limit)
			vehicle.get("_mesh_lod_controller").call("force_refresh")
			vehicle.call("_update_mesh_lod", 1.0)
		var warm_until := Time.get_ticks_msec() + 1500
		while Time.get_ticks_msec() < warm_until: await process_frame
		var frame_ms: Array[float] = []
		var gpu_ms: Array[float] = []
		var cpu_ms: Array[float] = []
		var draws: Array[float] = []
		var last := Time.get_ticks_usec()
		var sample_until := Time.get_ticks_msec() + 3000
		while Time.get_ticks_msec() < sample_until:
			await process_frame
			var now := Time.get_ticks_usec()
			frame_ms.append((now - last) / 1000.0)
			last = now
			gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		phases.append({"wheel_range_m": distance_limit, "frame_mean_ms": _mean(frame_ms),
			"frame_p95_ms": _percentile(frame_ms, 0.95), "gpu_mean_ms": _mean(gpu_ms),
			"cpu_render_mean_ms": _mean(cpu_ms), "draws_mean": _mean(draws), "samples": frame_ms.size()})
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://wheel_visibility_%d.png" % int(distance_limit))
	var result := {"phases": phases, "vehicles": _vehicles.size(), "viewport": str(root.size),
		"renderer": RenderingServer.get_current_rendering_method(),
		"limits": "Static 30-vehicle fixture; no terrain streaming or suspension simulation; wheel range is the only A/B change."}
	var output := FileAccess.open("user://wheel_visibility_render_diagnostic.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	print("WHEEL_VISIBILITY_RENDER_DIAGNOSTIC ", JSON.stringify(result))
	_world.free()
	quit()

func _stop_processing(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _stop_processing(child)
