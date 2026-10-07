extends Node3D

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	for service in get_tree().root.get_children():
		if service != self: service.process_mode = Node.PROCESS_MODE_DISABLED
	FloatingOrigin.enabled = false
	Engine.time_scale = 6.0
	get_tree().create_timer(600.0).timeout.connect(func():
		push_error("HARVESTER_NAVIGATION timeout")
		get_tree().quit(1))
	if "--campaign-snapshot" in OS.get_cmdline_user_args():
		_test_campaign_snapshot()
		return
	_setup_grid()
	var start := Vector3(-500, 1, 0)
	var goal := Vector3(500, 0, 0)
	var route := NavGraph.find_ground_path(start, goal, 6.0)
	_check(route.size() > 2, "long wall requires a complete detour")
	_check(not route.is_empty() and route[-1].distance_to(goal) < 0.01, "route reaches actual order beyond the old 300 m horizon")
	var crossed_end := false
	for i in range(1, route.size()):
		_check(NavGraph.can_traverse_segment(route[i - 1], route[i], 6.0), "route contains an unsafe terrain shortcut")
		crossed_end = crossed_end or absf(route[i].z) > 640.0
	_check(crossed_end, "detour goes around the end of the wall")
	_check(NavGraph.find_ground_path(start, Vector3(0, 160, 0), 6.0).is_empty(), "unreachable cliff destination must fail safely")
	# The closest geometric anchor can be on the wrong side of an obstacle.
	var edge_start := Vector3(-90, 0, 600)
	var anchor := NavGraph._nearest_reachable_ground_node(edge_start, 6.0)
	_check(anchor >= 0, "safe endpoint can join the graph near a cliff corner")
	if anchor >= 0:
		_check(NavGraph.can_traverse_segment(edge_start, NavGraph._nodes[anchor], 6.0), "endpoint connector respects terrain")
	var shift := Vector3(8123.5, 0, -5678.25)
	TerrainNavGrid.apply_origin_shift(shift)
	NavGraph.apply_origin_shift(shift)
	var shifted := NavGraph.find_ground_path(start - shift, goal - shift, 6.0)
	_check(shifted.size() == route.size(), "origin shift preserves full route")
	for i in mini(route.size(), shifted.size()):
		_check(shifted[i].distance_to(route[i] - shift) < 0.03, "route coordinates survive origin shift")
	TerrainNavGrid.apply_origin_shift(-shift)
	NavGraph.apply_origin_shift(-shift)
	_add_box(Vector3(0, -1, 0), Vector3(2600, 2, 2600))
	_add_box(Vector3(0, 80, 0), Vector3(80, 160, 1280))
	var h := preload("res://GroundVehicle/Harvester.tscn").instantiate()
	add_child(h)
	h.global_position = start
	h.rotation.y = PI * 0.5
	var points: Array[Vector3] = [goal]
	h.set_patrol_waypoints(points)
	NavPathScheduler.process_mode = Node.PROCESS_MODE_ALWAYS
	NavPathScheduler.min_job_start_interval_s = 0.0
	NavPathScheduler.start_jitter_s = 0.0
	var travelled := 0.0
	var last: Vector3 = h.global_position
	var deadline := Time.get_ticks_msec() + 50000
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		travelled += h._flat_distance(h.global_position, last)
		last = h.global_position
		if h._flat_distance(h.global_position, goal) < 0.75 and Vector2(h.velocity.x, h.velocity.z).length() < 0.5:
			break
	_check(h._flat_distance(h.global_position, goal) < 0.75, "physical harvester reaches the distant exact stop around a wall")
	_check(travelled < 2600.0, "physical driver makes steady progress without circling")
	print("HARVESTER_NAV_TRAVEL at=%s distance=%.1f target=%s state=%s" % [h.global_position, travelled, goal, h.navigation_status])
	h.set_physics_process(false)
	# A parked vehicle with a remaining path must trigger recovery; decreasing
	# distance by less than 0.5 m per tick still counts as progress over time.
	points.assign([Vector3(-500, 0, 0)])
	h.set_patrol_waypoints(points)
	h._nav_path_positions.assign([Vector3(300, 0, 0)])
	h._nav_path_index = 0
	for step in 45: h._update_path_stuck_state(0.1, Vector3(300, 0, 0))
	_check(h._is_pathfinding, "stationary harvester requests a new route")
	while h._is_pathfinding: await get_tree().process_frame
	var empty: Array[Vector3] = []
	h._clear_navigation_path()
	h._on_navigation_path_computed(empty, h._get_raw_navigation_destination(), 2, 6.0, 3.0)
	_check(h.navigation_status == "blocked" and h._nav_retry_cooldown_s >= 3.0, "failed routes retain a bounded retry cooldown")
	var jobs := NavPathScheduler.get_pending_count()
	for step in 20: h._recompute_navigation_path(h._get_raw_navigation_destination())
	_check(NavPathScheduler.get_pending_count() == jobs, "blocked vehicle does not flood the path scheduler")
	h.queue_free()
	await get_tree().process_frame
	print("HARVESTER_NAVIGATION_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _setup_grid() -> void:
	var heights := PackedFloat32Array()
	for z in 61:
		for x in 61:
			var wx := -1200 + x * 40
			var wz := -1200 + z * 40
			heights.append(160.0 if abs(wx) <= 40 and abs(wz) <= 640 else 0.0)
	TerrainNavGrid._cols = 61
	TerrainNavGrid._rows = 61
	TerrainNavGrid.cell_size_m = 40.0
	TerrainNavGrid._origin_x = -1200.0
	TerrainNavGrid._origin_z = -1200.0
	TerrainNavGrid._heights = heights
	TerrainNavGrid._h_min_passable = 0.0
	TerrainNavGrid._is_baked = true
	TerrainNavGrid.query_cell_size_m = 40.0
	TerrainNavGrid._query_cols = 61
	TerrainNavGrid._query_rows = 61
	TerrainNavGrid._query_origin_x = -1200.0
	TerrainNavGrid._query_origin_z = -1200.0
	TerrainNavGrid._query_heights = heights.duplicate()
	TerrainNavGrid._query_max_heights = heights.duplicate()
	TerrainNavGrid._query_height_variation.resize(61 * 61)
	TerrainNavGrid._query_height_variation.fill(0.0)
	TerrainNavGrid._query_is_baked = true
	NavGraph._reset_graph()
	NavGraph._build()
	NavGraph._build_spatial_index()
	NavGraph._is_ready = true

func _test_campaign_snapshot() -> void:
	var file := FileAccess.open("res://captures/harvester_navigation_snapshot.bin", FileAccess.READ)
	_check(file != null, "campaign navigation snapshot exists")
	if file == null:
		get_tree().quit(1)
		return
	var data: Dictionary = file.get_var()
	NavGraph._reset_graph()
	for key in ["nodes", "node_cl", "edge_starts", "edge_nb", "edge_cl", "cl_map"]:
		NavGraph.set("_" + key, data[key])
	NavGraph._query_grid = data.grid
	NavGraph._build_spatial_index()
	NavGraph._is_ready = true
	var began := Time.get_ticks_usec()
	var route := NavGraph.find_ground_path(data.start, data.goal, 6.0)
	var elapsed_ms := (Time.get_ticks_usec() - began) / 1000.0
	_check(not route.is_empty(), "stopped campaign harvester has a complete safe route")
	var length := 0.0
	for i in range(1, route.size()):
		length += route[i - 1].distance_to(route[i])
		_check(NavGraph.can_traverse_segment(route[i - 1], route[i], 6.0), "campaign route segment is unsafe")
	if not route.is_empty():
		_check(Vector2(route[-1].x, route[-1].z).distance_to(Vector2(data.goal.x, data.goal.z)) < 0.1, "campaign route reaches the actual salvage site")
	print("HARVESTER_CAMPAIGN_ROUTE_%s points=%d length=%.1f solve_ms=%.1f start=%s goal=%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", route.size(), length, elapsed_ms, data.start, data.goal, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _add_box(at: Vector3, dimensions: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = dimensions
	body.add_child(shape)
	add_child(body)
	body.position = at
