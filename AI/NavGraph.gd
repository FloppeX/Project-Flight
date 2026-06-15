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

@export var node_spacing_m:    float = 80.0   ## Grid spacing between candidate nodes
@export var max_edge_length_m: float = 180.0  ## Max edge length (~2.25 × spacing covers diagonals)
@export var max_slope_m:       float = 18.0   ## Max height change per cell_size step along an edge
@export var debug_print:       bool  = true

# ── Graph data (populated by _build or _load) ──────────────────────────────

var _nodes:            PackedVector3Array  = []  ## World position of every node
var _node_cl:          PackedFloat32Array  = []  ## Per-node clearance (m) to nearest impassable cell
var _edge_starts:      PackedInt32Array   = []  ## _edge_starts[i] = first edge index for node i
var _edge_nb:          PackedInt32Array   = []  ## Neighbour node index (flat)
var _edge_cl:          PackedFloat32Array  = []  ## Edge clearance = min(endpoint clearances) (flat)
var _cl_map:           PackedFloat32Array  = []  ## Per-cell clearance (m), kept for edge sampling
var _is_ready:         bool               = false
var _lock:             Mutex              = Mutex.new()

# ── Spatial index for O(1) nearest-node lookup ─────────────────────────────

const _SP_CELL: float = 240.0            ## Spatial grid cell size (> node_spacing_m)
var _sp_grid: Dictionary = {}            ## Vector2i → Array[int] of node indices

# ── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("origin_shifter")
	if TerrainNavGrid.is_ready():
		_init_graph()
	else:
		TerrainNavGrid.bake_complete.connect(_init_graph, CONNECT_ONE_SHOT)

func apply_origin_shift(offset: Vector3) -> void:
	_lock.lock()
	for i in _nodes.size():
		_nodes[i] -= offset
	_build_spatial_index()
	_lock.unlock()

func is_ready() -> bool:
	_lock.lock()
	var r := _is_ready
	_lock.unlock()
	return r

func rebuild_from_current_navgrid() -> void:
	_reset_graph()
	if TerrainNavGrid.is_ready():
		_init_graph()
	elif not TerrainNavGrid.bake_complete.is_connected(_init_graph):
		TerrainNavGrid.bake_complete.connect(_init_graph, CONNECT_ONE_SHOT)

# ── Public API ──────────────────────────────────────────────────────────────

## Synchronous path find. Returns [] if no path exists.
## min_clearance_m — required half-body clearance:
##   0.0  → any passable node/edge (small vehicles)
##   80.0 → carrier-width corridor required
func find_path(from_world: Vector3, to_world: Vector3,
		min_clearance_m: float = 0.0) -> Array[Vector3]:
	_lock.lock()
	if not _is_ready or _nodes.is_empty():
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
	WorkerThreadPool.add_task(func() -> void:
		var path := find_path(from_world, to_world, min_clearance_m)
		callback.call_deferred(path)
	)

func has_nearby_node(world_pos: Vector3, min_clearance_m: float = 0.0) -> bool:
	_lock.lock()
	if not _is_ready or _nodes.is_empty():
		_lock.unlock()
		return false
	var res := _nearest_node(world_pos, min_clearance_m) >= 0
	_lock.unlock()
	return res

func can_anchor(world_pos: Vector3, min_clearance_m: float = 0.0, max_anchor_distance_m: float = 180.0) -> bool:
	_lock.lock()
	if not _is_ready or _nodes.is_empty():
		_lock.unlock()
		return false
	var pos := world_pos
	var terrain_y := TerrainNavGrid.sample_height(pos.x, pos.z)
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
	var cache := _cache_path()
	_lock.lock()
	var loaded_from_cache := false
	if FileAccess.file_exists(cache):
		if _load(cache):
			# Rebuild clearance map (needed for path simplification at query time)
			_cl_map = _build_clearance_map(TerrainNavGrid._cols, TerrainNavGrid._rows, TerrainNavGrid.cell_size_m)
			_build_spatial_index()
			if debug_print:
				print("[NavGraph] Loaded from cache — %d nodes, %d edges" % [
					_nodes.size(), _edge_nb.size()])
			_is_ready = true
			loaded_from_cache = true
		elif debug_print:
			print("[NavGraph] Cache invalid — rebuilding")
	if not loaded_from_cache:
		_build()
		_save(cache)
		_build_spatial_index()
		_is_ready = true
	_lock.unlock()
	graph_ready.emit()

func _cache_path() -> String:
	var terrain := get_tree().get_first_node_in_group("terrain_provider") as Node3D
	var seed_val: int = 0
	if terrain:
		var s = terrain.get("seed")
		if s != null:
			seed_val = int(s)
	var origin_x_key: int = int(round(TerrainNavGrid._origin_x))
	var origin_z_key: int = int(round(TerrainNavGrid._origin_z))
	return "user://navgraph_%d_s%.0f_e%.0f_g%.0f_ox%d_oz%d.bin" % [
		seed_val,
		node_spacing_m,
		TerrainNavGrid.bake_half_extent_m,
		TerrainNavGrid.cell_size_m,
		origin_x_key,
		origin_z_key
	]

func _reset_graph() -> void:
	_lock.lock()
	_nodes = PackedVector3Array()
	_node_cl = PackedFloat32Array()
	_edge_starts = PackedInt32Array()
	_edge_nb = PackedInt32Array()
	_edge_cl = PackedFloat32Array()
	_cl_map = PackedFloat32Array()
	_sp_grid.clear()
	_is_ready = false
	_lock.unlock()

# ── Build ───────────────────────────────────────────────────────────────────

func _build() -> void:
	var t0 := Time.get_ticks_msec()
	if debug_print:
		print("[NavGraph] Building graph (spacing=%.0fm)…" % node_spacing_m)

	var cell  := TerrainNavGrid.cell_size_m
	var step  := maxi(1, int(node_spacing_m / cell))
	var cols  := TerrainNavGrid._cols
	var rows  := TerrainNavGrid._rows
	var ox    := TerrainNavGrid._origin_x
	var oz    := TerrainNavGrid._origin_z

	# ── Clearance map: BFS distance to nearest impassable cell ──────────────
	_cl_map = _build_clearance_map(cols, rows, cell)
	var cl_map := _cl_map

	# ── Pass 1: place nodes ─────────────────────────────────────────────────
	var grid_to_node := PackedInt32Array()
	grid_to_node.resize(cols * rows)
	grid_to_node.fill(-1)

	var node_gx: PackedInt32Array = []
	var node_gz: PackedInt32Array = []
	var h_ceil := TerrainNavGrid._h_min_passable + TerrainNavGrid.low_level_tolerance_m

	for gz in range(0, rows, step):
		for gx in range(0, cols, step):
			if not _cell_passable(gx, gz):
				continue
			# Basic slope check against immediate neighbours
			if not _cell_slope_ok(gx, gz):
				continue
			var wy: float = TerrainNavGrid._heights[gz * cols + gx]
			# Skip high-elevation cells — carrier stays on low terrain
			if wy > h_ceil:
				continue
			var idx := _nodes.size()
			_nodes.append(Vector3(ox + gx * cell, wy, oz + gz * cell))
			_node_cl.append(cl_map[gz * cols + gx])
			node_gx.append(gx)
			node_gz.append(gz)
			grid_to_node[gz * cols + gx] = idx

	var n := _nodes.size()
	if debug_print:
		print("[NavGraph]   %d nodes placed" % n)

	# ── Pass 2: build edges ─────────────────────────────────────────────────
	var edge_lists: Array = []
	edge_lists.resize(n)
	for i in n:
		edge_lists[i] = []

	var max_edge_sq := max_edge_length_m * max_edge_length_m
	var search_r    := int(max_edge_length_m / node_spacing_m) + 1

	for i in n:
		var ga_x: int = node_gx[i]
		var ga_z: int = node_gz[i]
		var pa: Vector3 = _nodes[i]

		for dz in range(-search_r, search_r + 1):
			for dx in range(-search_r, search_r + 1):
				if dx == 0 and dz == 0:
					continue
				var gb_x: int = ga_x + dx * step
				var gb_z: int = ga_z + dz * step
				if gb_x < 0 or gb_x >= cols or gb_z < 0 or gb_z >= rows:
					continue
				var j: int = grid_to_node[gb_z * cols + gb_x]
				if j < 0 or j <= i:
					continue  # not a node, or already processed this pair
				var pb: Vector3 = _nodes[j]
				var fdx := pb.x - pa.x
				var fdz := pb.z - pa.z
				if fdx * fdx + fdz * fdz > max_edge_sq:
					continue
				var ecl := _edge_clearance(pa, pb, i, j)
				if ecl < 0.0:
					continue  # slope or impassable blocks this edge
				(edge_lists[i] as Array).append([j, ecl])
				(edge_lists[j] as Array).append([i, ecl])

	# ── Flatten into packed arrays ──────────────────────────────────────────
	_edge_starts.resize(n + 1)
	var total := 0
	for i in n:
		_edge_starts[i] = total
		total += (edge_lists[i] as Array).size()
	_edge_starts[n] = total

	_edge_nb.resize(total)
	_edge_cl.resize(total)
	for i in n:
		var s: int = _edge_starts[i]
		var el: Array = edge_lists[i]
		for k in el.size():
			_edge_nb[s + k] = (el[k] as Array)[0]
			_edge_cl[s + k] = (el[k] as Array)[1]

	if debug_print:
		print("[NavGraph]   %d edges — built in %d ms" % [
			total / 2, Time.get_ticks_msec() - t0])

# ── Clearance map ───────────────────────────────────────────────────────────

func _build_clearance_map(cols: int, rows: int, cell: float) -> PackedFloat32Array:
	## BFS from every obstacle cell outward.  Result[i] = distance (m) from
	## cell i to the nearest obstacle.  "Obstacle" includes both truly impassable
	## cells AND high-elevation cells (hills/mountains) that ground vehicles
	## cannot traverse.
	var cl := PackedFloat32Array()
	cl.resize(cols * rows)
	cl.fill(1e9)

	# Determine height ceiling: only low-level terrain is navigable.
	# This matches TerrainNavGrid.get_furthest_edge_position logic.
	var h_ceil := TerrainNavGrid._h_min_passable + TerrainNavGrid.low_level_tolerance_m

	var queue: PackedInt32Array = []
	for gz in rows:
		for gx in cols:
			var h := TerrainNavGrid._heights[gz * cols + gx]
			var is_obstacle := (
				h <= TerrainNavGrid.IMPASSABLE * 0.5
				or h > h_ceil
				or TerrainNavGrid.is_cell_near_steep_slope(gx, gz, max_slope_m)
			)
			if is_obstacle:
				cl[gz * cols + gx] = 0.0
				queue.append(gz * cols + gx)

	const CARD: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var qi := 0
	while qi < queue.size():
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
	return not TerrainNavGrid.is_cell_near_steep_slope(gx, gz, max_slope_m, 1)

func _edge_clearance(pa: Vector3, pb: Vector3, ia: int, ib: int) -> float:
	## Walk the edge in cell_size steps and check slope + passability.
	## Returns the min clearance along the entire edge, or -1 if impassable.
	var diff := Vector2(pb.x - pa.x, pb.z - pa.z)
	var dist := diff.length()
	if dist < 0.01:
		return _node_cl[ia]
	var step_m := TerrainNavGrid.cell_size_m
	var dir := diff / dist
	var prev_h := pa.y
	var min_cl := minf(_node_cl[ia], _node_cl[ib])
	var d := step_m * 0.5
	var cell := TerrainNavGrid.cell_size_m
	var cols := TerrainNavGrid._cols
	var rows := TerrainNavGrid._rows
	var ox := TerrainNavGrid._origin_x
	var oz := TerrainNavGrid._origin_z
	while d < dist:
		var px := pa.x + dir.x * d
		var pz := pa.z + dir.y * d
		var h := TerrainNavGrid.sample_height(px, pz)
		if h <= TerrainNavGrid.IMPASSABLE * 0.5:
			return -1.0
		if abs(h - prev_h) > max_slope_m:
			return -1.0
		prev_h = h
		# Sample clearance at this intermediate point from the clearance map
		var gx := int((px - ox) / cell)
		var gz := int((pz - oz) / cell)
		if gx >= 0 and gx < cols and gz >= 0 and gz < rows:
			var cl_here := _cl_map[gz * cols + gx]
			min_cl = minf(min_cl, cl_here)
		else:
			return -1.0
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
	var step_m := TerrainNavGrid.cell_size_m
	var dir := diff / dist
	var prev_h := from.y
	var result_cl := 1e9
	var cell := TerrainNavGrid.cell_size_m
	var cols := TerrainNavGrid._cols
	var rows := TerrainNavGrid._rows
	var ox := TerrainNavGrid._origin_x
	var oz := TerrainNavGrid._origin_z
	var d := step_m * 0.5
	while d < dist:
		var px := from.x + dir.x * d
		var pz := from.z + dir.y * d
		var h := TerrainNavGrid.sample_height(px, pz)
		if h <= TerrainNavGrid.IMPASSABLE * 0.5:
			return -1.0
		if abs(h - prev_h) > max_slope_m:
			return -1.0
		prev_h = h
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

# ── Spatial index ───────────────────────────────────────────────────────────

func _build_spatial_index() -> void:
	_sp_grid.clear()
	for i in _nodes.size():
		var key := Vector2i(int(_nodes[i].x / _SP_CELL), int(_nodes[i].z / _SP_CELL))
		if not _sp_grid.has(key):
			_sp_grid[key] = []
		(_sp_grid[key] as Array).append(i)

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

const _CACHE_VERSION := 6

func _save(path: String) -> void:
	var data := {
		"version":      _CACHE_VERSION,
		"node_spacing": node_spacing_m,
		"max_slope":    max_slope_m,
		"nodes":        _nodes,
		"node_cl":      _node_cl,
		"edge_starts":  _edge_starts,
		"edge_nb":      _edge_nb,
		"edge_cl":      _edge_cl,
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
	if absf(float(data.get("node_spacing", 0.0)) - node_spacing_m) > 0.1:
		return false
	if absf(float(data.get("max_slope", 0.0)) - max_slope_m) > 0.1:
		return false
	_nodes       = data["nodes"]
	_node_cl     = data["node_cl"]
	_edge_starts = data["edge_starts"]
	_edge_nb     = data["edge_nb"]
	_edge_cl     = data["edge_cl"]
	return true
