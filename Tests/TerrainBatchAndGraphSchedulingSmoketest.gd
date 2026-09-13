extends SceneTree

var _failures: Array[String] = []
var _ready_signals := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var terrain := load("res://Environment/LowPolyTerrain.gd").new() as Node3D
	terrain.set("generate_on_ready", false)
	terrain.set("quads_x", 112)
	terrain.set("quads_z", 112)
	root.add_child(terrain)
	terrain.set_process(false)
	for profile in ["open_canyons", "layered_badlands"]:
		for quantization in [0.0, 3.0]:
			for transformed in [false, true]:
				terrain.set("map_profile_id", profile)
				terrain.set("quant_step_m", quantization)
				terrain.position = Vector3(35.125, 62.13, -102.75) if transformed else Vector3.ZERO
				terrain.rotation = Vector3(0.05, 0.21, 0.0) if transformed else Vector3.ZERO
				terrain.scale = Vector3(1.3, 0.8, 0.9) if transformed else Vector3.ONE
				terrain.call("_refresh_layout")
				terrain.set("_noises", terrain.call("_build_noises"))
				var batch: Dictionary = terrain.call("sample_height_grid_rows", -850.35, -752.125, 41.3, 2, 29, 43)
				var actual: PackedFloat32Array = batch["heights"]
				var minimum := INF
				for row in 29:
					for column in 43:
						var position := Vector3(-850.35 + column * 41.3, terrain.global_position.y, -752.125 + (row + 2) * 41.3)
						var h: float = terrain.call("get_height", position)
						var expected := PackedFloat32Array([h])[0]
						var found := actual[row * 43 + column]
						_expect((is_nan(expected) and is_nan(found)) or expected == found, "batch height changed")
						if not is_nan(h):
							minimum = minf(minimum, h)
				_expect(minimum == float(batch["minimum"]), "batch minimum lost precision")
	var grid := root.get_node("TerrainNavGrid")
	grid.call("_reset_bake_state")
	grid.set("_cols", 121)
	grid.set("_rows", 121)
	grid.set("cell_size_m", 40.0)
	var heights := PackedFloat32Array()
	heights.resize(121 * 121)
	heights.fill(100.0)
	grid.set("_heights", heights)
	grid.set("_h_min_passable", 100.0)
	grid.set("_is_baked", true)
	var graph := root.get_node("NavGraph")
	graph.set("build_frame_budget_ms", 0.5)
	graph.call("_reset_graph")
	graph.call("_build")
	var expected_arrays: Dictionary = {}
	for field in ["_nodes", "_node_cl", "_cl_map", "_edge_starts", "_edge_nb", "_edge_cl"]:
		expected_arrays[field] = graph.get(field)
	graph.call("_reset_graph")
	var frame_start := Engine.get_process_frames()
	await graph.call("_build", true)
	_expect(Engine.get_process_frames() > frame_start + 2, "cooperative build did not yield")
	for field in expected_arrays:
		_expect(expected_arrays[field] == graph.get(field), "cooperative graph differs: " + field)
	# Real publication/caching path, using a unique cache namespace via node spacing.
	graph.set("node_spacing_m", 83.125)
	graph.set("layered_node_spacing_m", 163.125)
	graph.graph_ready.connect(func(): _ready_signals += 1)
	graph.call("_init_graph")
	_expect(not graph.is_ready(), "partly built graph published")
	graph.call("_reset_graph") # cancel while suspended
	await process_frame
	_expect(_ready_signals == 0 and not graph.is_ready(), "cancelled build published")
	graph.call("_init_graph")
	var start := Time.get_ticks_msec()
	while not graph.is_ready() and Time.get_ticks_msec() - start < 10000:
		await process_frame
	_expect(graph.is_ready() and _ready_signals == 1, "replacement graph did not publish exactly once")
	var loading := root.get_node("LoadingScreen")
	_expect(bool(loading.call("_navigation_is_ready")), "loading did not observe completed graph")
	grid.call("_reset_bake_state")
	_expect(not graph.is_ready(), "rebake left stale graph available")
	_expect(not bool(loading.call("_navigation_is_ready")), "loading accepted invalidated graph")
	print("TERRAIN_BATCH_GRAPH_SCHEDULING ", JSON.stringify({"status": "PASS" if _failures.is_empty() else "FAIL", "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
