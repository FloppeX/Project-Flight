extends SceneTree

const TerrainScript = preload("res://Environment/LowPolyTerrain.gd")
const GridScript = preload("res://Environment/TerrainNavGrid.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	_test_query_analysis()
	await _test_streaming()
	print("TERRAIN_STREAMING_BUDGET_SMOKETEST ", JSON.stringify({"status": "PASS" if _failures.is_empty() else "FAIL", "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)

func _test_query_analysis() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99117
	var grid := GridScript.new()
	for dimensions in [Vector2i(31, 27), Vector2i(3, 4), Vector2i(1, 1)]:
		for radius in range(1, 5):
			for mode in range(3):
				grid._query_cols = dimensions.x
				grid._query_rows = dimensions.y
				grid.query_edge_radius_cells = radius
				grid.rows_per_frame = 3
				grid._query_heights.resize(dimensions.x * dimensions.y)
				for i in grid._query_heights.size():
					grid._query_heights[i] = rng.randf_range(-200.0, 900.0) if mode != 0 else 50.0
					if mode == 2 and rng.randf() < 0.08:
						grid._query_heights[i] = grid.IMPASSABLE
				grid._begin_query_analysis()
				while grid._query_analysis_gz < grid._query_rows:
					grid._analyze_query_rows()
				for z in dimensions.y:
					for x in dimensions.x:
						var lo := INF
						var hi := -INF
						var valid := true
						for dz in range(-radius, radius + 1):
							for dx in range(-radius, radius + 1):
								var nx: int = x + dx
								var nz: int = z + dz
								if nx < 0 or nx >= dimensions.x or nz < 0 or nz >= dimensions.y:
									valid = false
									continue
								var h: float = grid._query_heights[nz * dimensions.x + nx]
								if h <= grid.IMPASSABLE * 0.5:
									valid = false
								lo = minf(lo, h)
								hi = maxf(hi, h)
						var i: int = z * dimensions.x + x
						# Expected output is also float32, as in the original packed arrays.
						var expected := PackedFloat32Array([hi - lo if valid else INF, hi if valid else -INF])
						_expect(grid._query_height_variation[i] == expected[0] and grid._query_max_heights[i] == expected[1], "query window mismatch: %s r=%d mode=%d cell=%d" % [dimensions, radius, mode, i])
				_expect(grid._query_window_min.is_empty(), "analysis scratch rows retained after completion")
	grid.free()

func _test_streaming() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 1000, 0)
	camera.current = true
	var terrain := TerrainScript.new()
	terrain.generate_on_ready = false
	terrain.quads_x = 112
	terrain.quads_z = 112
	terrain.cell_size_m = 36.0
	terrain.chunk_quads_x = 8
	terrain.chunk_quads_z = 8
	terrain.load_radius_chunks = 2
	terrain.stream_preload_ahead_m = 0.0
	terrain.max_in_flight_chunk_tasks = 3
	scene.add_child(terrain)
	terrain.rebuild()
	terrain.set_process(false)
	_expect(terrain._async_tasks.size() <= 3, "initial build exceeded job limit")
	# Finish all queued workers first: make the main-thread budget test deterministic.
	for task in terrain._async_tasks:
		while not WorkerThreadPool.is_task_completed(task.task_id):
			await process_frame
	var center := terrain._get_active_camera_chunk()
	var expected_key := terrain._chunk_key(center.x, center.y)
	terrain._finalize_ready_tasks(16, Time.get_ticks_usec() - 1)
	_expect(terrain._stream_last_finalized == 1, "expired soft budget installed more than one ready chunk")
	_expect(terrain._chunks.has(expected_key), "nearest ready chunk did not finalize first")
	var chunk: Node = terrain._chunks.get(expected_key)
	if chunk != null:
		var mesh := (chunk.get_node("Mesh") as MeshInstance3D).mesh
		var shape := (chunk.get_node("Body/CollisionShape3D") as CollisionShape3D).shape as ConcavePolygonShape3D
		_expect(mesh.get_faces() == shape.get_faces(), "render/collision triangles differ")
	var start := Time.get_ticks_msec()
	while not terrain.is_initial_load_complete() and Time.get_ticks_msec() - start < 5000:
		terrain._process(1.0 / 60.0)
		_expect(terrain._async_tasks.size() <= 3, "in-flight queue exceeded configured cap")
		await process_frame
	_expect(terrain.is_initial_load_complete(), "bounded streaming stalled before completion")
	_expect(terrain.is_current_view_load_complete(), "settled view not reported ready")
	camera.position.x += 1000
	_expect(not terrain.is_current_view_load_complete(), "camera relocation reused previous view's completed queue")
	camera.position.x -= 1000
	var loading: Node = root.get_node("LoadingScreen")
	loading.set("_terrain_node", terrain)
	loading.call("_set_terrain_loading_budget", true)
	_expect(terrain._scenario_loading_active, "loading budget not enabled")
	loading.call("_hide_immediately")
	_expect(not terrain._scenario_loading_active, "loading budget leaked into gameplay")
	# Rebuild with jobs outstanding must join safely and reset initial progress.
	camera.position.x += 1000
	terrain._update_streaming(true)
	terrain.rebuild()
	_expect(terrain._async_tasks.size() <= 3, "rebuild exceeded job limit")
	terrain._clear_chunks()
	loading.set("_terrain_node", null)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
