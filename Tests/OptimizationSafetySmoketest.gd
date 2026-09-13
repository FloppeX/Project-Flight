extends SceneTree
const Cache = preload("res://Environment/NavigationGridCache.gd")
class Contact extends Node3D:
	var team := 2
	func get_team() -> int: return team
var failures: Array[String] = []
var metrics := {}

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var terrain = load("res://Environment/LowPolyTerrain.gd").new()
	terrain.generate_on_ready = false
	terrain.quads_x = 112
	terrain.quads_z = 112
	root.add_child(terrain)
	terrain.set_process(false)
	terrain._refresh_layout()
	terrain._noises = terrain._build_noises()
	await process_frame
	var grid = load("res://Environment/TerrainNavGrid.gd").new()
	root.add_child(grid)
	grid.set_process(false)
	grid.bake_half_extent_m = 500.0
	grid._reset_bake_state()
	grid._try_start_bake()
	var key: String = grid._grid_cache_key
	_expect(not key.is_empty(), "production provider has cache key")
	while not grid._is_baked: grid._bake_rows()
	var expected := [grid._heights.to_byte_array(), grid._query_heights.to_byte_array(), grid._query_height_variation.to_byte_array(), grid._query_max_heights.to_byte_array(), grid._h_min_passable]
	grid._reset_bake_state()
	grid._try_start_bake()
	_expect(grid._grid_cache_hit and grid._is_baked and grid._query_is_baked, "cache publishes complete grids")
	_expect(expected == [grid._heights.to_byte_array(), grid._query_heights.to_byte_array(), grid._query_height_variation.to_byte_array(), grid._query_max_heights.to_byte_array(), grid._h_min_passable], "bit-exact grid round trip")
	metrics.cache = grid.get_bake_timing_stats()
	for property in ["seed", "quant_step_m", "plateau_height_m"]:
		var previous: Variant = terrain.get(property)
		terrain.set(property, previous + 1)
		_expect(Cache.fingerprint(grid, terrain) != key, property + " invalidates cache")
		terrain.set(property, previous)
	terrain.position.x += 1
	_expect(Cache.fingerprint(grid, terrain) != key, "transform invalidates cache")
	terrain.position.x -= 1
	grid.query_edge_radius_cells += 1
	_expect(Cache.fingerprint(grid, terrain) != key, "safety radius invalidates cache")
	grid.query_edge_radius_cells -= 1
	_expect(Cache.read(key, 1, 1).is_empty(), "reject dimension mismatch")
	# Corrupt only this test-generated small cache, never a campaign save.
	var file := FileAccess.open(Cache.cache_path(key), FileAccess.WRITE)
	file.store_string("truncated test cache")
	file.close()
	grid._reset_bake_state()
	grid._try_start_bake()
	_expect(not grid._grid_cache_hit and not grid._is_baked, "corrupt cache falls back to bake")
	while not grid._is_baked: grid._bake_rows()
	_expect(not Cache.read(key, grid._cols * grid._rows, grid._query_cols * grid._query_rows).is_empty(), "corrupt cache replaced")
	# The alternate profile, transformed terrain, and coarse-only mode must also
	# round-trip rather than incorrectly accepting the previous region's cache.
	for query_enabled in [true, false]:
		terrain.map_profile_id = "layered_badlands"
		terrain.position = Vector3(31.125, 47.75, -28.25)
		terrain.rotation.y = 0.13
		terrain._refresh_layout()
		terrain._noises = terrain._build_noises()
		grid.query_grid_enabled = query_enabled
		grid._reset_bake_state()
		grid._try_start_bake()
		_expect(grid._grid_cache_key != key, "profile/region cannot reuse old cache")
		while not grid._is_baked: grid._bake_rows()
		var exact := [grid._heights.to_byte_array(), grid._query_heights.to_byte_array(), grid._query_height_variation.to_byte_array(), grid._query_max_heights.to_byte_array(), grid._h_min_passable]
		grid._reset_bake_state()
		grid._try_start_bake()
		_expect(grid._grid_cache_hit and grid._query_is_baked == query_enabled, "alternate profile cache readiness")
		_expect(exact == [grid._heights.to_byte_array(), grid._query_heights.to_byte_array(), grid._query_height_variation.to_byte_array(), grid._query_max_heights.to_byte_array(), grid._h_min_passable], "alternate profile exact round trip")
		var before: PackedByteArray = grid._heights.to_byte_array()
		grid.apply_origin_shift(Vector3(10000, 0, -10000))
		_expect(grid._heights.to_byte_array() == before, "cached grids survive origin rebasing")
	grid.free()
	terrain.queue_free()
	await process_frame
	await _sensors()
	await _sensor_pipeline()
	await _spawning()
	_expect(metrics.has("spawn_complete"), "spawn test reached completion")
	print("OPTIMIZATION_SAFETY_SMOKETEST ", JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures, "metrics": metrics}))
	quit(0 if failures.is_empty() else 1)

func _sensors() -> void:
	var index = root.get_node("WorldUnitIndex")
	var nodes: Array[Node3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 9183
	for i in 1000:
		var target := Node3D.new()
		root.add_child(target)
		target.position = Vector3(rng.randf_range(-20000, 20000), rng.randf_range(0, 800), rng.randf_range(-20000, 20000))
		nodes.append(target)
	var started := Time.get_ticks_usec()
	var snapshot: Dictionary = index.build_spatial_snapshot(nodes)
	var returned := 0
	for i in 100:
		var center := Vector3(float(i - 50) * 310, 0, float(i % 17) * 850 - 7000)
		var actual: Array[Node3D] = index.query_spatial_snapshot(snapshot, center, 2500.0)
		var expected: Array[Node3D] = []
		for node in nodes:
			if node.global_position.distance_squared_to(center) <= 2500.0 * 2500.0: expected.append(node)
		_expect(actual.size() == expected.size(), "spatial count matches exhaustive")
		for node in expected: _expect(node in actual, "spatial includes every in-range target")
		returned += actual.size()
	metrics.sensor_exact_comparison_ms = (Time.get_ticks_usec() - started) / 1000.0
	metrics.sensor_candidates = returned
	metrics.sensor_exhaustive_candidates = 100000
	# Include exact cell/range boundaries, vertical distance and origin movement.
	nodes[0].position = Vector3(2000, 0, 0)
	nodes[1].position = Vector3(0, 2501, 0)
	snapshot = index.build_spatial_snapshot(nodes)
	var boundary: Array = index.query_spatial_snapshot(snapshot, Vector3.ZERO, 2000)
	_expect(nodes[0] in boundary and not nodes[1] in boundary, "exact spherical boundary")
	nodes[0].free()
	index.query_spatial_snapshot(snapshot, Vector3.ZERO, 2000)
	for node: Variant in nodes:
		if is_instance_valid(node): node.free()
	await process_frame

func _spawning() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var platoons: Array = []
	for n in 2:
		var platoon = load("res://Enemies/EnemyVirtualPlatoon.gd").new()
		platoon.vehicle_count = 4
		platoon.position = Vector3(200 * n, 100, 0)
		platoon._vehicle_scenes.append(load("res://GroundVehicle/vehicle_enemy_buggy.tscn") as PackedScene)
		world.add_child(platoon)
		platoon._materialize()
		platoons.append(platoon)
	var previous := 0
	for frame in 30:
		await process_frame
		var count := 0
		for platoon in platoons:
			count += platoon._active_vehicles.size()
			for vehicle in platoon._active_vehicles: vehicle.process_mode = Node.PROCESS_MODE_DISABLED
		_expect(count - previous <= 1, "global single-vehicle spawn slice")
		previous = count
		if count == 8: break
	_expect(previous == 8, "all requested vehicles materialize")
	for platoon in platoons:
		_expect(platoon.vstate == 1 and platoon.vehicle_count == 4, "complete platoon state")
		platoon.dematerialize()
		platoon.vehicle_count = 4
		platoon._materialize()
		platoon.dematerialize()
	await process_frame
	for platoon in platoons: _expect(platoon._active_vehicles.is_empty() and not platoon.is_processing(), "cancel cannot resurrect spawn")
	current_scene = null
	world.queue_free()
	await process_frame
	metrics.spawn_complete = true

func _sensor_pipeline() -> void:
	var manager = root.get_node("AirOpsManager")
	manager.carrier_radar_enabled = false
	manager.ground_vehicle_radar_enabled = true
	manager.ground_vehicle_radar_range_m = 2500.0
	var nodes: Array[Node3D] = []
	for i in 320:
		var node := Contact.new()
		node.team = 1 if i < 20 else 2
		node.add_to_group("ground_vehicles" if i < 20 else "buildings")
		if i >= 20: node.add_to_group("enemies") # duplicate membership
		node.position = Vector3((i % 20) * 2000, 0, (i / 20) * 1500)
		root.add_child(node)
		nodes.append(node)
	var expected: Array = []
	for optimized in [false, true]:
		manager.spatial_sensor_queries_enabled = optimized
		manager._reported_contacts.clear()
		var started := Time.get_ticks_usec()
		for repeat in 10: manager._update_friendly_sensor_picture()
		metrics["sensor_indexed_ms" if optimized else "sensor_exhaustive_ms"] = (Time.get_ticks_usec() - started) / 10000.0
		var actual: Array = manager._reported_contacts.keys()
		if not optimized: expected = actual
		else:
			_expect(actual.size() == expected.size(), "sensor pipeline contact count unchanged")
			for node in expected: _expect(node in actual, "sensor pipeline contacts unchanged")
	manager.sensor_batch_budget_ms = 0.1
	manager._update_friendly_sensor_picture(true)
	nodes[0].free()
	nodes[20].free()
	# A moved target must be read from its current position on the next slice.
	nodes[21].position += Vector3(100000, 0, 0)
	var steps := 0
	while not manager._pending_sensor_observers.is_empty() and steps < 100:
		manager._service_sensor_batch()
		steps += 1
	_expect(manager._pending_sensor_observers.is_empty(), "budgeted sensors drain after freed observer/target")
	manager._reported_contacts.clear()
	for node: Variant in nodes:
		if is_instance_valid(node): node.queue_free()
	await process_frame
	metrics.sensor_pipeline_complete = true

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
