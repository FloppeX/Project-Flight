extends SceneTree
## Headless CPU benchmark; does not measure rendered FPS or alter scenario settings.
## --script res://Tests/TerrainPerformanceBench.gd -- --bench-mode=nav --bench-label=before

const TerrainScript = preload("res://Environment/LowPolyTerrain.gd")
const GridScript = preload("res://Environment/TerrainNavGrid.gd")
var _options: Dictionary = {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			var parts := argument.trim_prefix("--").split("=", true, 1)
			_options[parts[0]] = parts[1]
	call_deferred("_run")

func _run() -> void:
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(18880.0, 1400.0, -3720.0)
	camera.current = true
	var terrain := TerrainScript.new()
	terrain.generate_on_ready = false
	terrain.cell_size_m = 36.0
	terrain.seed = 22551
	terrain.position.y = 62.0
	terrain.plateau_height_m = 500.0
	terrain.base_height_offset_m = 220.0
	terrain.load_radius_chunks = 4
	terrain.unload_margin_chunks = 2
	terrain.stream_preload_ahead_m = 0.0
	terrain.map_profile_id = _options.get("map-profile", "open_canyons")
	scene.add_child(terrain)
	terrain.set_process(false)
	terrain._refresh_layout()
	terrain._noises = terrain._build_noises()
	var result: Dictionary
	if _options.get("bench-mode", "nav") == "stream":
		result = await _stream_bench(terrain, camera)
	else:
		result = await _nav_bench(terrain, scene)
	result["label"] = _options.get("bench-label", "candidate")
	result["profile"] = terrain.map_profile_id
	var path := "user://terrain_bench_%s_%s.json" % [str(result["label"]).validate_filename(), str(_options.get("bench-mode", "nav")).validate_filename()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("TERRAIN_PERFORMANCE_BENCH ", JSON.stringify(result))
	quit(0 if bool(result.get("complete", false)) else 1)

func _nav_bench(terrain: Node3D, scene: Node3D) -> Dictionary:
	var grid := GridScript.new()
	# This benchmark measures generation, not repeat-load cache hits.
	grid.disk_cache_enabled = false
	grid.prefer_batch_height_sampling = _options.get("scalar", "false") != "true"
	grid.bake_half_extent_m = float(_options.get("extent", "25000"))
	scene.add_child(grid)
	grid.set_process(false)
	grid.set_bake_center_override(Vector3.ZERO)
	grid._try_start_bake()
	var start := Time.get_ticks_usec()
	var stages: Dictionary = {}
	while not grid.is_ready() and Time.get_ticks_usec() - start < 240000000:
		var stage: String = grid.get_bake_stage_label()
		var tick := Time.get_ticks_usec()
		grid._bake_rows()
		var elapsed := Time.get_ticks_usec() - tick
		var row: Dictionary = stages.get(stage, {"cpu_ms": 0.0, "max_slice_ms": 0.0, "slices": 0})
		row["cpu_ms"] += elapsed / 1000.0
		row["max_slice_ms"] = maxf(row["max_slice_ms"], elapsed / 1000.0)
		row["slices"] += 1
		stages[stage] = row
		if stage != grid.get_bake_stage_label():
			print("TERRAIN_BENCH_STAGE ", stage, " ", JSON.stringify(row))
		await process_frame
	return {"complete": grid.is_ready(), "wall_ms": (Time.get_ticks_usec() - start) / 1000.0, "stages": stages, "coarse_cells": grid._heights.size(), "query_cells": grid._query_heights.size()}

func _stream_bench(terrain: Node3D, camera: Camera3D) -> Dictionary:
	terrain.rebuild()
	terrain.set_process(false)
	var result := {"complete": true, "legs": []}
	for offset in [Vector3.ZERO, Vector3(1008, 0, 0), Vector3(10080, 0, 0), Vector3(-10080, 0, 0)]:
		camera.position += offset
		terrain._update_streaming(true)
		var start := Time.get_ticks_usec()
		var slices: Array[float] = []
		var max_jobs := 0
		while not terrain.is_initial_load_complete() and Time.get_ticks_usec() - start < 60000000:
			var tick := Time.get_ticks_usec()
			terrain._process(1.0 / 60.0)
			slices.append((Time.get_ticks_usec() - tick) / 1000.0)
			max_jobs = maxi(max_jobs, terrain._async_tasks.size())
			await process_frame
		slices.sort()
		var row := {"wall_ms": (Time.get_ticks_usec() - start) / 1000.0, "max_slice_ms": slices.back() if not slices.is_empty() else 0.0, "p95_slice_ms": slices[int(slices.size() * 0.95)] if not slices.is_empty() else 0.0, "max_jobs": max_jobs, "stats": terrain.get_streaming_stats()}
		result["legs"].append(row)
		result["complete"] = result["complete"] and terrain.is_initial_load_complete()
		print("TERRAIN_BENCH_STREAM ", JSON.stringify(row))
	return result
