extends SceneTree

const TERRAIN_SCRIPT: Script = preload("res://Environment/LowPolyTerrain.gd")
const WORLD_MAP_TEXTURE_BUILDER: Script = preload("res://UI/WorldMapTextureBuilder.gd")
var _failures: Array[String] = []
var _node_count := 0
var _map_vehicle_cells := 0
var _map_carrier_cells := 0
var _map_build_ms := 0
var _map_render_size := Vector2i.ZERO
var _main_blocked_path_points := 0
var _east_blocked_path_points := 0
var _west_blocked_path_points := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var full_map := OS.get_cmdline_user_args().has("--full-map")
	var bake_half_extent_m := 25000.0 if full_map else 5000.0
	var bake_timeout_s := 120.0 if full_map else 30.0
	var terrain_nav := root.get_node_or_null("TerrainNavGrid")
	var nav_graph := root.get_node_or_null("NavGraph")
	_expect(terrain_nav != null, "TerrainNavGrid autoload is missing")
	_expect(nav_graph != null, "NavGraph autoload is missing")
	if terrain_nav == null or nav_graph == null:
		quit(1)
		return
	var enemy_bases := root.get_node_or_null("EnemyBaseManager")
	var enemy_ops := root.get_node_or_null("EnemyOpsManager")
	if enemy_bases != null:
		enemy_bases.set("_disabled_for_test", true)
	if enemy_ops != null:
		enemy_ops.set("_disabled_for_test", true)

	terrain_nav.set("cell_size_m", 40.0)
	terrain_nav.set("bake_half_extent_m", bake_half_extent_m)
	terrain_nav.set("query_grid_enabled", false)
	terrain_nav.set("rows_per_frame", 20)
	terrain_nav.call("rebake_at_center", Vector3.ZERO)
	nav_graph.call("reset_until_navgrid_bakes")

	var terrain := TERRAIN_SCRIPT.new() as LowPolyTerrain
	terrain.generate_on_ready = false
	terrain.use_streaming = false
	terrain.cell_size_m = 36.0
	terrain.seed = 22551
	terrain.base_height_offset_m = 220.0
	terrain.quant_step_m = 3.0
	terrain.set_map_profile("layered_badlands")
	root.add_child(terrain)

	var started_ms := Time.get_ticks_msec()
	while not bool(terrain_nav.call("is_ready")) or not bool(nav_graph.call("is_ready")):
		if float(Time.get_ticks_msec() - started_ms) / 1000.0 > bake_timeout_s:
			_expect(false, "navigation bake did not finish within %.0f seconds" % bake_timeout_s)
			_finish(terrain, [], started_ms, 0.0, bake_half_extent_m)
			return
		await process_frame
	var nodes_value: Variant = nav_graph.get("_nodes")
	if nodes_value is PackedVector3Array:
		_node_count = (nodes_value as PackedVector3Array).size()

	var route_edge_m := bake_half_extent_m - 200.0
	var start_progress := (-route_edge_m + 25000.0) / 50000.0
	var goal_progress := (route_edge_m + 25000.0) / 50000.0
	var start := terrain.get_profile_route_local_position(start_progress, 0)
	var goal := terrain.get_profile_route_local_position(goal_progress, 0)
	var path: Array = nav_graph.call("find_path", start, goal, 120.0)
	_expect(path.size() >= 2, "carrier-clearance graph did not connect the layered ramp")
	if full_map:
		_validate_carrier_route_redundancy(terrain, nav_graph, start, goal)
	var map_build_started_ms := Time.get_ticks_msec()
	var map_layers: Dictionary = WORLD_MAP_TEXTURE_BUILDER.build_images()
	_map_build_ms = Time.get_ticks_msec() - map_build_started_ms
	_map_vehicle_cells = int(map_layers.get("vehicle_cells", 0))
	_map_carrier_cells = int(map_layers.get("carrier_cells", 0))
	_map_render_size = Vector2i(
		int(map_layers.get("render_cols", 0)),
		int(map_layers.get("render_rows", 0))
	)
	_expect(map_layers.get("relief") is Image, "topographic relief image was not generated from the baked map")
	_expect(map_layers.get("mobility") is Image, "mobility mask was not generated from NavGraph clearance")
	_expect(_map_vehicle_cells > 0, "actual navigation map produced no vehicle-only mobility cells")
	_expect(_map_carrier_cells > 0, "actual navigation map produced no carrier mobility cells")
	if OS.get_cmdline_user_args().has("--save-map-preview"):
		var relief := map_layers.get("relief") as Image
		var mobility := map_layers.get("mobility") as Image
		if relief != null and mobility != null:
			var preview := _compose_map_preview(relief, mobility)
			var preview_error := preview.save_png("res://screenshots/world_map_mobility_preview.png")
			_expect(preview_error == OK, "mobility preview image could not be saved")
	var height_span := 0.0
	if path.size() >= 2:
		var min_height := INF
		var max_height := -INF
		for point_variant in path:
			var point: Vector3 = point_variant
			min_height = minf(min_height, point.y)
			max_height = maxf(max_height, point.y)
		height_span = max_height - min_height
		# The cheapest of the three carrier routes is intentionally the lower
		# basin route; the profile smoke test separately checks high/low diversity.
		var expected_height_span := 250.0 if full_map else 60.0
		_expect(height_span >= expected_height_span, "lowest-cost path was effectively flat")
	_finish(terrain, path, started_ms, height_span, bake_half_extent_m)


func _finish(terrain: LowPolyTerrain, path: Array, started_ms: int, height_span: float, bake_half_extent_m: float) -> void:
	print("LAYERED_MAP_NAVIGATION_SMOKETEST ", JSON.stringify({
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"path_points": path.size(),
		"navigation_nodes": _node_count,
		"map_vehicle_cells": _map_vehicle_cells,
		"map_carrier_cells": _map_carrier_cells,
		"map_build_ms": _map_build_ms,
		"map_render_size": str(_map_render_size),
		"path_height_span_m": height_span,
		"main_blocked_path_points": _main_blocked_path_points,
		"east_blocked_path_points": _east_blocked_path_points,
		"west_blocked_path_points": _west_blocked_path_points,
		"map_size_km": bake_half_extent_m * 2.0 / 1000.0,
		"elapsed_ms": Time.get_ticks_msec() - started_ms,
		"failures": _failures,
	}))
	terrain.queue_free()
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[LayeredMapNavigationSmoketest] %s" % message)


func _validate_carrier_route_redundancy(terrain: LowPolyTerrain, nav_graph: Node, start: Vector3, goal: Vector3) -> void:
	var main_midpoint := terrain.get_profile_route_local_position(0.5, 0)
	var east_midpoint := terrain.get_profile_route_local_position(0.5, 1)
	var west_midpoint := terrain.get_profile_route_local_position(0.5, 2)
	var block_radius_m := 1800.0
	var main_blocked := _find_carrier_path_avoiding(
		nav_graph,
		start,
		goal,
		[main_midpoint],
		block_radius_m
	)
	_main_blocked_path_points = main_blocked.size()
	_expect(main_blocked.size() >= 2, "no carrier route remained after blocking the central corridor")

	var main_and_east_blocked := _find_carrier_path_avoiding(
		nav_graph,
		start,
		goal,
		[main_midpoint, east_midpoint],
		block_radius_m
	)
	_east_blocked_path_points = main_and_east_blocked.size()
	_expect(main_and_east_blocked.size() >= 2, "western carrier corridor did not survive central/eastern closures")
	_expect(
		_path_min_planar_distance(main_and_east_blocked, west_midpoint) <= block_radius_m,
		"central/eastern closures did not force the graph onto the western corridor"
	)

	var main_and_west_blocked := _find_carrier_path_avoiding(
		nav_graph,
		start,
		goal,
		[main_midpoint, west_midpoint],
		block_radius_m
	)
	_west_blocked_path_points = main_and_west_blocked.size()
	_expect(main_and_west_blocked.size() >= 2, "eastern carrier corridor did not survive central/western closures")
	_expect(
		_path_min_planar_distance(main_and_west_blocked, east_midpoint) <= block_radius_m,
		"central/western closures did not force the graph onto the eastern corridor"
	)


func _find_carrier_path_avoiding(
		nav_graph: Node,
		start: Vector3,
		goal: Vector3,
		blocked_centers: Array[Vector3],
		blocked_radius_m: float
	) -> Array[Vector3]:
	var nodes_value: Variant = nav_graph.get("_nodes")
	var node_clearance_value: Variant = nav_graph.get("_node_cl")
	var edge_starts_value: Variant = nav_graph.get("_edge_starts")
	var edge_neighbors_value: Variant = nav_graph.get("_edge_nb")
	var edge_clearance_value: Variant = nav_graph.get("_edge_cl")
	if (
		not nodes_value is PackedVector3Array
		or not node_clearance_value is PackedFloat32Array
		or not edge_starts_value is PackedInt32Array
		or not edge_neighbors_value is PackedInt32Array
		or not edge_clearance_value is PackedFloat32Array
	):
		return []
	var nodes := nodes_value as PackedVector3Array
	var node_clearance := node_clearance_value as PackedFloat32Array
	var edge_starts := edge_starts_value as PackedInt32Array
	var edge_neighbors := edge_neighbors_value as PackedInt32Array
	var edge_clearance := edge_clearance_value as PackedFloat32Array
	var blocked := PackedByteArray()
	blocked.resize(nodes.size())
	blocked.fill(0)
	var radius_squared := blocked_radius_m * blocked_radius_m
	for node_index in nodes.size():
		var node := nodes[node_index]
		for center in blocked_centers:
			var dx := node.x - center.x
			var dz := node.z - center.z
			if dx * dx + dz * dz <= radius_squared:
				blocked[node_index] = 1
				break
	var start_index := _nearest_carrier_node(nodes, node_clearance, blocked, start)
	var goal_index := _nearest_carrier_node(nodes, node_clearance, blocked, goal)
	if start_index < 0 or goal_index < 0:
		return []
	blocked[start_index] = 0
	blocked[goal_index] = 0
	var came_from := PackedInt32Array()
	came_from.resize(nodes.size())
	came_from.fill(-1)
	var visited := PackedByteArray()
	visited.resize(nodes.size())
	visited.fill(0)
	var queue: Array[int] = [start_index]
	visited[start_index] = 1
	var queue_index := 0
	while queue_index < queue.size():
		var current := queue[queue_index]
		queue_index += 1
		if current == goal_index:
			break
		for edge_index in range(edge_starts[current], edge_starts[current + 1]):
			if edge_clearance[edge_index] < 120.0:
				continue
			var neighbor := edge_neighbors[edge_index]
			if visited[neighbor] != 0 or blocked[neighbor] != 0:
				continue
			visited[neighbor] = 1
			came_from[neighbor] = current
			queue.append(neighbor)
	if visited[goal_index] == 0:
		return []
	var reversed_path: Array[Vector3] = []
	var cursor := goal_index
	while cursor >= 0:
		reversed_path.append(nodes[cursor])
		if cursor == start_index:
			break
		cursor = came_from[cursor]
	reversed_path.reverse()
	return reversed_path


func _nearest_carrier_node(
		nodes: PackedVector3Array,
		node_clearance: PackedFloat32Array,
		blocked: PackedByteArray,
		position: Vector3
	) -> int:
	var best_index := -1
	var best_distance_squared := INF
	for node_index in nodes.size():
		if blocked[node_index] != 0 or node_clearance[node_index] < 120.0:
			continue
		var distance_squared := nodes[node_index].distance_squared_to(position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_index = node_index
	return best_index


func _path_min_planar_distance(path: Array[Vector3], point: Vector3) -> float:
	var minimum := INF
	for path_point in path:
		minimum = minf(minimum, Vector2(path_point.x - point.x, path_point.z - point.z).length())
	return minimum


func _compose_map_preview(relief: Image, mobility: Image) -> Image:
	var preview := relief.duplicate()
	var vehicle_color := Color("c58d3d")
	var carrier_color := Color("76c7c7")
	for y in range(preview.get_height()):
		for x in range(preview.get_width()):
			var base: Color = preview.get_pixel(x, y)
			var mask: Color = mobility.get_pixel(x, y)
			if mask.r > 0.001:
				base = base.lerp(vehicle_color, mask.r * 0.32)
			if mask.g > 0.001:
				base = base.lerp(carrier_color, mask.g * 0.48)
			preview.set_pixel(x, y, base)
	return preview
