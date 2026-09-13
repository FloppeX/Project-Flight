extends SceneTree
## Full-sized graph CPU benchmark. No scene load, query grid, or cache hit shortcuts.
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
	var terrain := load("res://Environment/LowPolyTerrain.gd").new() as Node3D
	terrain.set("generate_on_ready", false)
	terrain.set("cell_size_m", 36.0)
	terrain.set("seed", 22551)
	terrain.position.y = 62.0
	terrain.set("plateau_height_m", 500.0)
	terrain.set("base_height_offset_m", 220.0)
	terrain.set("map_profile_id", _options.get("profile", "open_canyons"))
	scene.add_child(terrain)
	terrain.set_process(false)
	var grid := root.get_node("TerrainNavGrid")
	grid.set("bake_half_extent_m", float(_options.get("extent", "25000")))
	grid.set("query_grid_enabled", false)
	grid.call("rebake_at_center", Vector3.ZERO)
	grid.call("_try_start_bake")
	while int(grid.get("_bake_gz")) < int(grid.get("_rows")):
		grid.call("_bake_height_rows")
		await process_frame
	grid.set("_is_baked", true) # Do not emit the gameplay population callbacks.
	var graph := root.get_node("NavGraph")
	graph.call("_reset_graph")
	var started := Time.get_ticks_usec()
	if _options.get("cooperative", "false") == "true":
		await graph.call("_build", true)
	else:
		graph.call("_build")
	var build_ms := (Time.get_ticks_usec() - started) / 1000.0
	var hashes: Dictionary = {}
	for key in ["_nodes", "_node_cl", "_cl_map", "_edge_starts", "_edge_nb", "_edge_cl"]:
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(var_to_bytes(graph.get(key)))
		hashes[key] = hash.finish().hex_encode()
	var result := {"build_ms": build_ms, "stages_ms": graph.get("_build_stage_ms"), "hashes": hashes,
		"yields": graph.get("_build_yields"), "max_slice_ms": graph.get("_build_max_slice_ms"),
		"nodes": (graph.get("_nodes") as PackedVector3Array).size(), "edges": (graph.get("_edge_nb") as PackedInt32Array).size(),
		"profile": terrain.get("map_profile_id"), "extent": grid.get("bake_half_extent_m")}
	var label: String = _options.get("label", "candidate")
	var file := FileAccess.open("user://navgraph_bench_%s.json" % label.validate_filename(), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("NAVGRAPH_PERFORMANCE_BENCH ", JSON.stringify(result))
	quit(0)
