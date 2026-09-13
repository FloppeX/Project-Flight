extends Node
## NavGraph — autoload singleton.
##
## Builds a sparse waypoint graph from the baked TerrainNavGrid heightmap.
## Saved to disk after the first build — subsequent loads are instant.
## All ground vehicles and the land carrier pathfind via find_path().
##
## Clearance: each node and edge stores the distance (m) to the nearest
## impassable cell.  Vehicles pass their required half-width so they only
## traverse edges wide enough for their body.
##   Small ground vehicle : find_path(a, b, 0.0)
##   Land carrier (~76 m) : find_path(a, b, 80.0)

signal graph_ready
signal graph_invalidated

@export var node_spacing_m:    float = 80.0   ## Grid spacing between candidate nodes
@export var max_edge_length_m: float = 180.0  ## Max edge length (~2.25 × spacing covers diagonals)
@export var max_slope_m:       float = 18.0   ## Legacy local-height tolerance used by placement/UI helpers
@export_range(1.0, 45.0, 0.5) var max_slope_degrees: float = 20.0 ## Hard route grade cap
@export var debug_print:       bool  = false
## Cold builds yield between bounded units; not a hard cap on allocations/cache IO.
@export var build_frame_budget_ms: float = 8.0

@export_group("Layered Map")
@export var layered_node_spacing_m: float = 160.0
@export var layered_max_edge_length_m: float = 250.0

# ── Graph data (populated by _build or _load) ──────────────────────────────

var _nodes:            PackedVector3Array  = []  ## Positions in the graph's build-time frame
var _node_cl:          PackedFloat32Array  = []  ## Per-node clearance (m) to nearest impassable cell
var _edge_starts:      PackedInt32Array   = []  ## _edge_starts[i] = first edge index for node i
var _edge_nb:          PackedInt32Array   = []  ## Neighbour node index (flat)
var _edge_cl:          PackedFloat32Array  = []  ## Edge clearance = min(endpoint clearances) (flat)
var _cl_map:           PackedFloat32Array  = []  ## Per-cell clearance (m), kept for edge sampling
var _is_ready:         bool               = false
var _startup_timing_stats: Dictionary = {}
var _build_stage_ms: Dictionary = {}
var _lock:             Mutex              = Mutex.new()
var _frame_lock := Mutex.new() # Never held for pathfinding or index work.
var _world_offset := Vector3.ZERO # graph position + offset = current world position
var _query_grid: Dictionary = {} # Immutable build-frame sampling data for workers.
var _build_generation: int = 0
var _initializing: bool = false
var _build_slice_started: int = 0
var _build_wait_usec: int = 0
var _build_yields: int = 0
var _build_max_slice_ms: float = 0.0

# ── Spatial index for O(1) nearest-node lookup ─────────────────────────────

const _SP_CELL: float = 240.0            ## Spatial grid cell size (> node_spacing_m)
var _sp_grid: Dictionary = {}            ## Vector2i → Array[int] of node indices

# ── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("origin_shifter")
	TerrainNavGrid.bake_invalidated.connect(_on_bake_invalidated)
	if TerrainNavGrid.is_ready():
		_init_graph()
	else:
		TerrainNavGrid.bake_complete.connect(_init_graph, CONNECT_ONE_SHOT)

func apply_origin_shift(offset: Vector3) -> void:
	if _initializing:
		_reset_graph()
		_init_graph.call_deferred()
		return
	var profile_started := FrameProfiler.begin("NavGraph.origin_shift")
	_frame_lock.lock()
	_world_offset -= offset
	_frame_lock.unlock()
	FrameProfiler.end("NavGraph.origin_shift", profile_started)

func get_world_offset() -> Vector3:
	_frame_lock.lock()
	var result := _world_offset
	_frame_lock.unlock()
	return result

func is_ready() -> bool:
	return _is_ready

func _on_bake_invalidated() -> void:
	_reset_graph()
	if not TerrainNavGrid.bake_complete.is_connected(_init_graph):
		TerrainNavGrid.bake_complete.connect(_init_graph, CONNECT_ONE_SHOT)

func rebuild_from_current_navgrid() -> void:
	_reset_graph()
	if TerrainNavGrid.is_ready():
		_init_graph()
	elif not TerrainNavGrid.bake_complete.is_connected(_init_graph):
		TerrainNavGrid.bake_complete.connect(_init_graph, CONNECT_ONE_SHOT)

func reset_until_navgrid_bakes() -> void:
	_reset_graph()
	if not TerrainNavGrid.bake_complete.is_connected(_init_graph):
		TerrainNavGrid.bake_complete.connect(_init_graph, CONNECT_ONE_SHOT)

# ── Public API ──────────────────────────────────────────────────────────────

## Synchronous path find. Returns [] if no path exists.
## min_clearance_m — required half-body clearance:
##   0.0  → any passable node/edge (small vehicles)
##   80.0 → carrier-width corridor required
func find_path(from_world: Vector3, to_world: Vector3,
		min_clearance_m: float = 0.0) -> Array[Vector3]:
	# The report collector is main-thread-only; asynchronous scheduler jobs must
	# not mutate its static dictionaries or event ring from worker threads.
	var on_main_thread := OS.get_thread_caller_id() == OS.get_main_thread_id()
	var profile_started := FrameProfiler.begin("NavGraph.find_path_main") if on_main_thread else 0
	# Results belong to the call-time frame. The scheduler rejects results when
	# that frame changed before delivery; it must not silently install stale paths.
	var offset := get_world_offset()
	var generation := _build_generation
	var result := _find_path_impl(from_world - offset, to_world - offset, min_clearance_m, generation)
	if offset != Vector3.ZERO:
		for i in result.size(): result[i] += offset
	if on_main_thread: FrameProfiler.end("NavGraph.find_path_main", profile_started)
	return result

func _find_path_impl(from_world: Vector3, to_world: Vector3,
		min_clearance_m: float, generation: int) -> Array[Vector3]:
	_lock.lock()
	if generation != _build_generation or not _is_ready or _nodes.is_empty():
		push_warning("[NavGraph] find_path called before graph is ready")
		_lock.unlock()
		return []
	var si := _nearest_node(from_world, min_clearance_m)
	var ei := _nearest_node(to_world,   min_clearance_m)
	if si < 0 or ei < 0:
		if debug_print:
			print("[NavGraph] find_path: no node near start(si=%d) or goal(ei=%d) cl=%.0fm" % [si, ei, min_clearance_m])
		_lock.unlock()
		return []
	if si == ei:
		# Both snap to the same node — just go to that node
		var snap_res: Array[Vector3] = [from_world, _nodes[si]]
		_lock.unlock()
		return snap_res
	var raw := _astar(si, ei, min_clearance_m)
	if raw.is_empty():
		print("[NavGraph] find_path: A* found no path node %d → %d, cl=%.0fm" % [si, ei, min_clearance_m])
		_lock.unlock()
		return []
	# Start from caller's position but end at the actual graph node,
	# not the raw destination which may be in impassable terrain.
	raw[0] = from_world
	var res := _simplify_path(raw, min_clearance_m)
	_lock.unlock()
	return res

func find_path_async(from_world: Vector3, to_world: Vector3, min_clearance_m: float, callback: Callable) -> void:
	NavPathScheduler.request_find_path(from_world, to_world, min_clearance_m, callback, 0, "NavGraph.find_path_async")

func has_nearby_node(world_pos: Vector3, min_clearance_m: float = 0.0) -> bool:
	var pos := world_pos - get_world_offset()
	_lock.lock()
	if not _is_ready or _nodes.is_empty():
		_lock.unlock()
		return false
	var res := _nearest_node(pos, min_clearance_m) >= 0
	_lock.unlock()
	return res

func can_anchor(world_pos: Vector3, min_clearance_m: float = 0.0, max_anchor_distance_m: float = 180.0) -> bool:
	var pos := world_pos - get_world_offset()
	_lock.lock()
	if not _is_ready or _nodes.is_empty():
		_lock.unlock()
		return false
	var terrain_y := _sample_graph_height(pos.x, pos.z)
	if terrain_y <= TerrainNavGrid.IMPASSABLE * 0.5:
		_lock.unlock()
		return false
	pos.y = terrain_y
	var anchor_idx := _nearest_node(pos, min_clearance_m)
	if anchor_idx < 0:
		_lock.unlock()
		return false
	var anchor_pos: Vector3 = _nodes[anchor_idx]
	if Vector2(anchor_pos.x - pos.x, anchor_pos.z - pos.z).length() > max_anchor_distance_m:
		_lock.unlock()
		return false
	var clearance_ok := _check_segment_clearance(pos, anchor_pos, min_clearance_m) >= min_clearance_m
	_lock.unlock()
	return clearance_ok

# ── Init (load or build) ────────────────────────────────────────────────────

func _init_graph() -> void:
	if _initializing or not TerrainNavGrid.is_ready():
		return
	_reset_graph()
	_initializing = true
	var generation := _build_generation
	var started := Time.get_ticks_usec()
	var cache := _cache_path()
	var loaded_from_cache := false
	var cache_write_ms := 0.0
	if FileAccess.file_exists(cache):
		if _load(cache):
			if debug_print:
				print("[NavGraph] Loaded from cache — %d nodes, %d edges" % [
					_nodes.size(), _edge_nb.size()])
			loaded_from_cache = true
		elif debug_print:
			print("[NavGraph] Cache invalid — rebuilding")
	if loaded_from_cache:
		_build_yields = 0
		_build_max_slice_ms = 0.0
		_build_wait_usec = 0
	if not loaded_from_cache:
		await _build(true)
		if generation != _build_generation:
			return
		var save_started := Time.get_ticks_usec()
		_save(cache)
		cache_write_ms = (Time.get_ticks_usec() - save_started) / 1000.0
	_build_slice_started = Time.get_ticks_usec()
	await _build_spatial_index(true)
	if generation != _build_generation:
		return
	_record_build_slice()
	_lock.lock()
	_is_ready = true
	_lock.unlock()
	_initializing = false
	_startup_timing_stats = {"wall_ms": (Time.get_ticks_usec() - started) / 1000.0,
		"cache_hit": loaded_from_cache, "nodes": _nodes.size(), "directed_edges": _edge_nb.size(),
		"build_stages_ms": {} if loaded_from_cache else _build_stage_ms.duplicate(),
		"yields": _build_yields, "max_build_slice_ms": _build_max_slice_ms, "cache_write_ms": cache_write_ms}
	graph_ready.emit()

func get_startup_timing_stats() -> Dictionary:
	var result := _startup_timing_stats.duplicate()
	result["building"] = _initializing
	return result

func _cache_path() -> String:
	var terrain := get_tree().get_first_node_in_group("terrain_provider") as Node3D
	var seed_val: int = 0
	var profile_id := "open_canyons"
	var height_profile_revision: int = 0
	if terrain:
		var s = terrain.get("seed")
		if s != null:
			seed_val = int(s)
		var profile_value: Variant = terrain.get("map_profile_id")
		if profile_value != null:
			profile_id = str(profile_value).validate_filename()
		if terrain.has_method("get_height_profile_revision"):
			height_profile_revision = int(terrain.call("get_height_profile_revision"))
	var origin_x_key: int = int(round(TerrainNavGrid._origin_x))
	var origin_z_key: int = int(round(TerrainNavGrid._origin_z))
	var effective_spacing := _effective_node_spacing_m()
	var effective_edge_length := _effective_max_edge_length_m()
	return "user://navgraph_%s_%d_h%d_s%.0f_l%.0f_e%.0f_g%.0f_ox%d_oz%d.bin" % [
		profile_id,
		seed_val,
		height_profile_revision,
		effective_spacing,
		effective_edge_length,
		TerrainNavGrid.bake_half_extent_m,
		TerrainNavGrid.cell_size_m,
		origin_x_key,
		origin_z_key
	]

func _reset_graph() -> void:
	_build_generation += 1
	graph_invalidated.emit()
	_initializing = false
	_startup_timing_stats.clear()
	_lock.lock()
	_nodes = PackedVector3Array()
	_node_cl = PackedFloat32Array()
	_edge_starts = PackedInt32Array()
	_edge_nb = PackedInt32Array()
	_edge_cl = PackedFloat32Array()
	_cl_map = PackedFloat32Array()
	_sp_grid.clear()
	_query_grid = {}
	_frame_lock.lock()
	_world_offset = Vector3.ZERO
	_frame_lock.unlock()
	_is_ready = false
	_lock.unlock()

# ── Build ───────────────────────────────────────────────────────────────────

func _build(cooperative: bool = false) -> void:
	_capture_query_grid()
	var generation := _build_generation
	_build_wait_usec = 0
	_build_yields = 0
	_build_max_slice_ms = 0.0
	_build_slice_started = Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	_build_stage_ms.clear()
	var stage_started := _build_work_clock_usec()
	var effective_spacing := _effective_node_spacing_m()
	var effective_edge_length := _effective_max_edge_length_m()
	if debug_print:
		print("[NavGraph] Building graph (spacing=%.0fm)…" % effective_spacing)

	var cell  := TerrainNavGrid.cell_size_m
	var step  := maxi(1, int(round(effective_spacing / cell)))
	var cols  := TerrainNavGrid._cols
	var rows  := TerrainNavGrid._rows
	var ox    := TerrainNavGrid._origin_x
	var oz    := TerrainNavGrid._origin_z

	# ── Clearance map: BFS distance to nearest impassable cell ──────────────
	if cooperative:
		var clearance := await _build_clearance_map(cols, rows, cell, true)
		if generation != _build_generation:
			return
		_cl_map = clearance
	else:
		_cl_map = await _build_clearance_map(cols, rows, cell)
	_build_stage_ms["clearance"] = (_build_work_clock_usec() - stage_started) / 1000.0
	stage_started = _build_work_clock_usec()
	var cl_map := _cl_map

	# ── Pass 1: place nodes ─────────────────────────────────────────────────
	var grid_to_node := PackedInt32Array()
	grid_to_node.resize(cols * rows)
	grid_to_node.fill(-1)

	var node_gx: PackedInt32Array = []
	var node_gz: PackedInt32Array = []
	for gz in range(0, rows, step):
		if cooperative and _build_budget_expired():
			if not await _yield_build_slice(generation):
				return
		for gx in range(0, cols, step):
			if gx < 1 or gx >= cols - 1 or gz < 1 or gz >= rows - 1:
				continue
			# The clearance-map seeds already encode the same impassable, grade,
			# and profile-height rules. Do not repeat those tests for every node.
			if cl_map[gz * cols + gx] <= 0.0:
				continue
			var wy: float = TerrainNavGrid._heights[gz * cols + gx]
			var idx := _nodes.size()
			_nodes.append(Vector3(ox + gx * cell, wy, oz + gz * cell))
			_node_cl.append(cl_map[gz * cols + gx])
			node_gx.append(gx)
			node_gz.append(gz)
			grid_to_node[gz * cols + gx] = idx

	var n := _nodes.size()
	_build_stage_ms["nodes"] = (_build_work_clock_usec() - stage_started) / 1000.0
	stage_started = _build_work_clock_usec()
	if debug_print:
		print("[NavGraph]   %d nodes placed" % n)

	# ── Pass 2: build edges ─────────────────────────────────────────────────
	# Packed undirected pairs avoid one nested Variant Array per directed edge.
	var pair_a := PackedInt32Array()
	var pair_b := PackedInt32Array()
	var pair_cl := PackedFloat32Array()
	var degrees := PackedInt32Array()
	degrees.resize(n)

	var max_edge_sq := effective_edge_length * effective_edge_length
	var search_r    := int(effective_edge_length / effective_spacing) + 1
	var offsets: Array[Vector2i] = []
	for dz in range(0, search_r + 1):
		for dx in range(-search_r, search_r + 1):
			if dz == 0 and dx <= 0:
				continue
			offsets.append(Vector2i(dx * step, dz * step))

	for i in n:
		if cooperative and i % 16 == 0 and _build_budget_expired():
			if not await _yield_build_slice(generation):
				return
		var ga_x: int = node_gx[i]
		var ga_z: int = node_gz[i]
		var pa: Vector3 = _nodes[i]

		# Nodes are row-major: only this forward half can have j > i.
		# Preserve its original traversal order for deterministic A* tie-breaking.
		for offset in offsets:
			var gb_x: int = ga_x + offset.x
			var gb_z: int = ga_z + offset.y
			if gb_x < 0 or gb_x >= cols or gb_z < 0 or gb_z >= rows:
				continue
			var j: int = grid_to_node[gb_z * cols + gb_x]
			if j < 0:
				continue
			var pb: Vector3 = _nodes[j]
			var fdx := pb.x - pa.x
			var fdz := pb.z - pa.z
			if fdx * fdx + fdz * fdz > max_edge_sq:
				continue
			var ecl := _edge_clearance(pa, pb, i, j)
			if ecl < 0.0:
				continue
			pair_a.append(i)
			pair_b.append(j)
			pair_cl.append(ecl)
			degrees[i] += 1
			degrees[j] += 1

	# ── Flatten into packed arrays ──────────────────────────────────────────
	_build_stage_ms["edges"] = (_build_work_clock_usec() - stage_started) / 1000.0
	stage_started = _build_work_clock_usec()
	_edge_starts.resize(n + 1)
	var total := 0
	for i in n:
		if cooperative and i % 2048 == 0 and _build_budget_expired():
			if not await _yield_build_slice(generation):
				return
		_edge_starts[i] = total
		total += degrees[i]
	_edge_starts[n] = total

	_edge_nb.resize(total)
	_edge_cl.resize(total)
	var cursors := _edge_starts.duplicate()
	for pair in pair_a.size():
		if cooperative and pair % 2048 == 0 and _build_budget_expired():
			if not await _yield_build_slice(generation):
				return
		var a := pair_a[pair]
		var b := pair_b[pair]
		var a_slot := cursors[a]
		var b_slot := cursors[b]
		_edge_nb[a_slot] = b
		_edge_nb[b_slot] = a
		_edge_cl[a_slot] = pair_cl[pair]
		_edge_cl[b_slot] = pair_cl[pair]
		cursors[a] += 1
		cursors[b] += 1

	_build_stage_ms["pack_edges"] = (_build_work_clock_usec() - stage_started) / 1000.0
	_record_build_slice()
	if debug_print:
		print("[NavGraph]   %d edges — built in %d ms" % [
			total / 2, Time.get_ticks_msec() - t0])

# ── Clearance map ───────────────────────────────────────────────────────────

func _build_clearance_map(cols: int, rows: int, cell: float, cooperative: bool = false) -> PackedFloat32Array:
	var generation := _build_generation
	## BFS from every obstacle cell outward. Layered maps admit reachable shelves;
	## the original profile retains its low-canyon routing behavior.
	var cl := PackedFloat32Array()
	cl.resize(cols * rows)
	cl.fill(1e9)

	var allow_elevated_routes := _current_map_supports_elevated_routes()
	var h_ceil := TerrainNavGrid._h_min_passable + TerrainNavGrid.low_level_tolerance_m
	var queue: PackedInt32Array = []
	for gz in rows:
		if cooperative and _build_budget_expired():
			if not await _yield_build_slice(generation):
				return PackedFloat32Array()
		for gx in cols:
			var h := TerrainNavGrid._heights[gz * cols + gx]
			var is_obstacle := (
				h <= TerrainNavGrid.IMPASSABLE * 0.5
				or (not allow_elevated_routes and h > h_ceil)
				or TerrainNavGrid.is_cell_near_steep_grade(gx, gz, max_slope_degrees, 1)
			)
			if is_obstacle:
				cl[gz * cols + gx] = 0.0
				queue.append(gz * cols + gx)

	const CARD: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var qi := 0
	while qi < queue.size():
		if cooperative and qi % 512 == 0 and _build_budget_expired():
			if not await _yield_build_slice(generation):
				return PackedFloat32Array()
		var idx: int = queue[qi]
		qi += 1
		var gx: int = idx % cols
		var gz: int = idx / cols
		var d: float = cl[idx] + cell
		for dir in CARD:
			var nx: int = gx + dir.x
			var nz: int = gz + dir.y
			if nx < 0 or nx >= cols or nz < 0 or nz >= rows:
				continue
			var ni: int = nz * cols + nx
			if d < cl[ni]:
				cl[ni] = d
				queue.append(ni)
	return cl


func _current_map_supports_elevated_routes() -> bool:
	var terrain := get_tree().get_first_node_in_group("terrain_provider") as Node3D
	if terrain == null:
		return false
	var profile_value: Variant = terrain.get("map_profile_id")
	return profile_value != null and str(profile_value) == "layered_badlands"


func _effective_node_spacing_m() -> float:
	return maxf(layered_node_spacing_m, TerrainNavGrid.cell_size_m) if _current_map_supports_elevated_routes() else node_spacing_m


func _effective_max_edge_length_m() -> float:
	return maxf(layered_max_edge_length_m, _effective_node_spacing_m()) if _current_map_supports_elevated_routes() else max_edge_length_m

# ── Passability helpers ─────────────────────────────────────────────────────

func _cell_passable(gx: int, gz: int) -> bool:
	var cols := TerrainNavGrid._cols
	var rows := TerrainNavGrid._rows
	if gx < 1 or gx >= cols - 1 or gz < 1 or gz >= rows - 1:
		return false
	var h: float = TerrainNavGrid._heights[gz * cols + gx]
	return h > TerrainNavGrid.IMPASSABLE * 0.5

func _cell_slope_ok(gx: int, gz: int) -> bool:
	## Check immediate neighbours for excessive slope.
	return not TerrainNavGrid.is_cell_near_steep_grade(gx, gz, max_slope_degrees, 1)

func _edge_clearance(pa: Vector3, pb: Vector3, ia: int, ib: int) -> float:
	## Walk the edge in cell_size steps and check slope + passability.
	## Returns the min clearance along the entire edge, or -1 if impassable.
	var diff := Vector2(pb.x - pa.x, pb.z - pa.z)
	var dist := diff.length()
	if dist < 0.01:
		return _node_cl[ia]
	var step_m := maxf(TerrainNavGrid.cell_size_m * 0.5, 1.0)
	var dir := diff / dist
	var prev_h := pa.y
	var prev_d := 0.0
	var min_cl := minf(_node_cl[ia], _node_cl[ib])
	var d := step_m
	var cell := TerrainNavGrid.cell_size_m
	var cols := TerrainNavGrid._cols
	var rows := TerrainNavGrid._rows
	var ox := TerrainNavGrid._origin_x
	var oz := TerrainNavGrid._origin_z
	var heights := TerrainNavGrid._heights
	var impassable := TerrainNavGrid.IMPASSABLE
	var max_grade := tan(deg_to_rad(clampf(max_slope_degrees, 0.1, 89.0)))
	while prev_d < dist - 0.001:
		var sample_d := minf(d, dist)
		var px := pa.x + dir.x * sample_d
		var pz := pa.z + dir.y * sample_d
		var fx := (px - ox) / cell
		var fz := (pz - oz) / cell
		var gx := int(fx)
		var gz := int(fz)
		if gx < 0 or gx >= cols or gz < 0 or gz >= rows:
			return -1.0
		# Same interpolation and invalid-corner fallback as sample_height().
		# Reuse its grid coordinates for the clearance lookup below.
		var index := gz * cols + gx
		var h := heights[index]
		if gx < cols - 1 and gz < rows - 1:
			var h10 := heights[index + 1]
			var h01 := heights[index + cols]
			var h11 := heights[index + cols + 1]
			if h > impassable * 0.5 and h10 > impassable * 0.5 and h01 > impassable * 0.5 and h11 > impassable * 0.5:
				h = lerp(lerp(h, h10, fx - gx), lerp(h01, h11, fx - gx), fz - gz)
		if h <= impassable * 0.5:
			return -1.0
		var run := sample_d - prev_d
		if run <= 0.001 or absf(h - prev_h) / run > max_grade:
			return -1.0
		prev_h = h
		prev_d = sample_d
		# Sample clearance at this intermediate point from the clearance map
		min_cl = minf(min_cl, _cl_map[index])
		d += step_m
	return min_cl

# ── A* ──────────────────────────────────────────────────────────────────────

func _astar(start: int, goal: int, min_cl: float) -> Array[Vector3]:
	var n := _nodes.size()
	var g_score := PackedFloat32Array()
	g_score.resize(n)
	g_score.fill(INF)
	g_score[start] = 0.0

	var came_from := PackedInt32Array()
	came_from.resize(n)
	came_from.fill(-1)

	var closed := PackedByteArray()
	closed.resize(n)
	closed.fill(0)

	var goal_pos: Vector3 = _nodes[goal]
	var open: Array = [[_nodes[start].distance_to(goal_pos), start]]

	# Penalize edges near obstacles so paths prefer open corridors.
	# An edge with exactly min_cl clearance gets a 100% distance penalty;
	# edges well beyond the required clearance get no penalty.
	var cl_penalty_range := maxf(min_cl * 2.0, 120.0)

	while not open.is_empty():
		var entry: Array = _heap_pop(open)
		var cur: int    = entry[1]

		if closed[cur]:
			continue
		closed[cur] = 1

		if cur == goal:
			return _rebuild(came_from, cur)

		var g_cur: float = g_score[cur]
		var es: int = _edge_starts[cur]
		var ee: int = _edge_starts[cur + 1]

		for e in range(es, ee):
			var nb: int = _edge_nb[e]
			if closed[nb]:
				continue
			if _edge_cl[e] < min_cl:
				continue
			var dist: float = _nodes[cur].distance_to(_nodes[nb])
			# Clearance penalty: edges near walls cost more
			var excess_cl := maxf(_edge_cl[e] - min_cl, 0.0)
			var penalty := 1.0 + 1.0 * clampf(1.0 - excess_cl / cl_penalty_range, 0.0, 1.0)
			var tg: float = g_cur + dist * penalty
			if tg < g_score[nb]:
				came_from[nb] = cur
				g_score[nb]   = tg
				_heap_push(open, [tg + _nodes[nb].distance_to(goal_pos), nb])

	return []  # no path

func _rebuild(came_from: PackedInt32Array, end: int) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var c := end
	while c >= 0:
		path.append(_nodes[c])
		c = came_from[c]
	path.reverse()
	return path

func _simplify_path(path: Array[Vector3], min_cl: float) -> Array[Vector3]:
	## Greedy line-of-sight simplification: skip intermediate waypoints when a
	## direct segment between two non-adjacent points has sufficient clearance
	## and acceptable slope.  Simplified segments require 50% MORE clearance
	## than the original path to keep shortcuts away from walls.
	## Max segment length capped at 400m so the carrier doesn't cut huge corners.
	if path.size() <= 2:
		return path
	var simplify_cl := min_cl * 1.5
	var max_seg_m := 400.0
	var result: Array[Vector3] = [path[0]]
	var i := 0
	while i < path.size() - 1:
		var best := i + 1
		for j in range(i + 2, path.size()):
			var seg_dist := Vector2(path[i].x - path[j].x, path[i].z - path[j].z).length()
			if seg_dist > max_seg_m:
				break
			var cl := _check_segment_clearance(path[i], path[j], simplify_cl)
			if cl >= simplify_cl:
				best = j
			else:
				break
		result.append(path[best])
		i = best
	return result

func _check_segment_clearance(from: Vector3, to: Vector3, min_cl: float) -> float:
	## Walk a straight segment and return the minimum clearance along it.
	## Returns -1.0 if any point is impassable or too steep.
	var diff := Vector2(to.x - from.x, to.z - from.z)
	var dist := diff.length()
	if dist < 0.01:
		return 1e9
	var step_m := maxf(float(_query_grid.cell_size) * 0.5, 1.0)
	var dir := diff / dist
	var prev_h := from.y
	var prev_d := 0.0
	var result_cl := 1e9
	var cell: float = _query_grid.cell_size
	var cols: int = _query_grid.cols
	var rows: int = _query_grid.rows
	var ox: float = _query_grid.origin_x
	var oz: float = _query_grid.origin_z
	var d := step_m
	while prev_d < dist - 0.001:
		var sample_d := minf(d, dist)
		var px := from.x + dir.x * sample_d
		var pz := from.z + dir.y * sample_d
		var h := _sample_graph_height(px, pz)
		if h <= TerrainNavGrid.IMPASSABLE * 0.5:
			return -1.0
		if _grade_exceeds_limit(prev_h, h, sample_d - prev_d):
			return -1.0
		prev_h = h
		prev_d = sample_d
		var gx := int((px - ox) / cell)
		var gz := int((pz - oz) / cell)
		if gx >= 0 and gx < cols and gz >= 0 and gz < rows:
			var cl_here: float
			if _cl_map.size() > 0:
				cl_here = _cl_map[gz * cols + gx]
			else:
				cl_here = 1e9
			result_cl = minf(result_cl, cl_here)
			if result_cl < min_cl:
				return result_cl
		else:
			return -1.0
		d += step_m
	return result_cl


func _grade_exceeds_limit(from_height: float, to_height: float, horizontal_run_m: float) -> bool:
	if horizontal_run_m <= 0.001:
		return true
	var rise_over_run := absf(to_height - from_height) / horizontal_run_m
	return rise_over_run > tan(deg_to_rad(clampf(max_slope_degrees, 0.1, 89.0)))

# ── Spatial index ───────────────────────────────────────────────────────────

func _build_spatial_index(cooperative: bool = false) -> void:
	if _query_grid.is_empty(): _capture_query_grid()
	var generation := _build_generation
	_sp_grid.clear()
	for i in _nodes.size():
		if cooperative and i % 512 == 0 and _build_budget_expired():
			if not await _yield_build_slice(generation):
				return
		var key := Vector2i(int(_nodes[i].x / _SP_CELL), int(_nodes[i].z / _SP_CELL))
		if not _sp_grid.has(key):
			_sp_grid[key] = []
		(_sp_grid[key] as Array).append(i)

func _record_build_slice() -> void:
	_build_max_slice_ms = maxf(_build_max_slice_ms, (Time.get_ticks_usec() - _build_slice_started) / 1000.0)

func _build_work_clock_usec() -> int:
	return Time.get_ticks_usec() - _build_wait_usec


func _build_budget_expired() -> bool:
	return Time.get_ticks_usec() - _build_slice_started >= int(maxf(build_frame_budget_ms, 0.1) * 1000.0)


func _yield_build_slice(generation: int) -> bool:
	_record_build_slice()
	var waiting_since := Time.get_ticks_usec()
	await get_tree().process_frame
	if generation != _build_generation:
		return false
	_build_wait_usec += Time.get_ticks_usec() - waiting_since
	_build_yields += 1
	_build_slice_started = Time.get_ticks_usec()
	return true


func _nearest_node(pos: Vector3, min_cl: float) -> int:
	var cx := int(pos.x / _SP_CELL)
	var cz := int(pos.z / _SP_CELL)
	var best := -1
	var best_sq := INF
	# Search 3×3 spatial cells; expand to 5×5 if nothing found
	for radius in [1, 2]:
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var key := Vector2i(cx + dx, cz + dz)
				if not _sp_grid.has(key):
					continue
				for i in (_sp_grid[key] as Array):
					if _node_cl[i] < min_cl:
						continue
					var ddx := _nodes[i].x - pos.x
					var ddz := _nodes[i].z - pos.z
					var sq  := ddx * ddx + ddz * ddz
					if sq < best_sq:
						best_sq = sq
						best    = i
		if best >= 0:
			break
	return best

# ── Binary min-heap ─────────────────────────────────────────────────────────

func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if (heap[i] as Array)[0] < (heap[p] as Array)[0]:
			var tmp: Array = heap[i]; heap[i] = heap[p]; heap[p] = tmp
			i = p
		else:
			break

func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var sz := heap.size()
		while true:
			var l := 2 * i + 1
			var r := 2 * i + 2
			var s := i
			if l < sz and (heap[l] as Array)[0] < (heap[s] as Array)[0]: s = l
			if r < sz and (heap[r] as Array)[0] < (heap[s] as Array)[0]: s = r
			if s == i: break
			var tmp: Array = heap[i]; heap[i] = heap[s]; heap[s] = tmp
			i = s
	return top

# ── Save / Load ─────────────────────────────────────────────────────────────

const _CACHE_VERSION := 12

func _save(path: String) -> void:
	var data := {
		"grid_origin_x": _query_grid.get("origin_x", TerrainNavGrid._origin_x),
		"grid_origin_z": _query_grid.get("origin_z", TerrainNavGrid._origin_z),
		"version":      _CACHE_VERSION,
		"node_spacing": _effective_node_spacing_m(),
		"max_edge_length": _effective_max_edge_length_m(),
		"max_slope":    max_slope_m,
		"max_slope_degrees": max_slope_degrees,
		"nodes":        _nodes,
		"node_cl":      _node_cl,
		"edge_starts":  _edge_starts,
		"edge_nb":      _edge_nb,
		"edge_cl":      _edge_cl,
		"clearance_map": _cl_map,
	}
	var bytes := var_to_bytes(data)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		push_warning("[NavGraph] Cannot write cache: " + path)
		return
	f.store_buffer(bytes)
	f.close()
	if debug_print:
		print("[NavGraph] Saved to %s (%.1f KB)" % [path, bytes.size() / 1024.0])

func _load(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return false
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var data = bytes_to_var(bytes)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if int(data.get("version", 0)) != _CACHE_VERSION:
		return false
	if absf(float(data.get("node_spacing", 0.0)) - _effective_node_spacing_m()) > 0.1:
		return false
	if absf(float(data.get("max_edge_length", 0.0)) - _effective_max_edge_length_m()) > 0.1:
		return false
	if absf(float(data.get("max_slope", 0.0)) - max_slope_m) > 0.1:
		return false
	if absf(float(data.get("max_slope_degrees", 0.0)) - max_slope_degrees) > 0.1:
		return false
	var cached_clearance: Variant = data.get("clearance_map", PackedFloat32Array())
	if not cached_clearance is PackedFloat32Array:
		return false
	if (cached_clearance as PackedFloat32Array).size() != TerrainNavGrid._cols * TerrainNavGrid._rows:
		return false
	_nodes       = data["nodes"]
	_node_cl     = data["node_cl"]
	_edge_starts = data["edge_starts"]
	_edge_nb     = data["edge_nb"]
	_edge_cl     = data["edge_cl"]
	_cl_map      = cached_clearance as PackedFloat32Array
	_capture_query_grid()
	# Older v12 caches store nodes in the cache-key's current frame. New caches
	# also retain the build-frame origin, allowing explicit saves after a rebase.
	var old_x: float = data.get("grid_origin_x", _query_grid.origin_x)
	var old_z: float = data.get("grid_origin_z", _query_grid.origin_z)
	_frame_lock.lock()
	_world_offset = Vector3(float(_query_grid.origin_x) - old_x, 0, float(_query_grid.origin_z) - old_z)
	_frame_lock.unlock()
	_query_grid.origin_x = old_x
	_query_grid.origin_z = old_z
	return true

func _capture_query_grid() -> void:
	_query_grid = {"heights": TerrainNavGrid._heights.duplicate(),
		"origin_x": TerrainNavGrid._origin_x, "origin_z": TerrainNavGrid._origin_z,
		"cols": TerrainNavGrid._cols, "rows": TerrainNavGrid._rows, "cell_size": TerrainNavGrid.cell_size_m}

func _sample_graph_height(wx: float, wz: float) -> float:
	# Same bilinear interpolation and edge/invalid-corner fallback as the baked
	# grid, but independent of its live origin while a worker is running.
	if _query_grid.is_empty(): return TerrainNavGrid.IMPASSABLE
	var cols: int = _query_grid.cols
	var rows: int = _query_grid.rows
	var heights: PackedFloat32Array = _query_grid.heights
	if cols <= 0 or rows <= 0 or heights.size() != cols * rows: return TerrainNavGrid.IMPASSABLE
	var fx: float = (wx - float(_query_grid.origin_x)) / float(_query_grid.cell_size)
	var fz: float = (wz - float(_query_grid.origin_z)) / float(_query_grid.cell_size)
	var gx := int(fx)
	var gz := int(fz)
	if gx < 0 or gx >= cols - 1 or gz < 0 or gz >= rows - 1:
		return heights[clampi(gz, 0, rows - 1) * cols + clampi(gx, 0, cols - 1)]
	var index := gz * cols + gx
	var h00 := heights[index]
	var h10 := heights[index + 1]
	var h01 := heights[index + cols]
	var h11 := heights[index + cols + 1]
	if h00 <= TerrainNavGrid.IMPASSABLE * 0.5 or h10 <= TerrainNavGrid.IMPASSABLE * 0.5 or h01 <= TerrainNavGrid.IMPASSABLE * 0.5 or h11 <= TerrainNavGrid.IMPASSABLE * 0.5:
		return h00 if h00 > TerrainNavGrid.IMPASSABLE * 0.5 else TerrainNavGrid.IMPASSABLE
	return lerp(lerp(h00, h10, fx - gx), lerp(h01, h11, fx - gx), fz - gz)
