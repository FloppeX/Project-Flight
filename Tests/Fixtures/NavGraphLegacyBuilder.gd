extends "res://AI/NavGraph.gd"
## Frozen pre-optimization builder for exact graph/order regression tests.

func _build(_cooperative: bool = false) -> void:
	var t0 := Time.get_ticks_msec()
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
	_cl_map = _build_clearance_map(cols, rows, cell)
	var cl_map := _cl_map

	# ── Pass 1: place nodes ─────────────────────────────────────────────────
	var grid_to_node := PackedInt32Array()
	grid_to_node.resize(cols * rows)
	grid_to_node.fill(-1)

	var node_gx: PackedInt32Array = []
	var node_gz: PackedInt32Array = []
	var allow_elevated_routes := _current_map_supports_elevated_routes()
	var h_ceil := TerrainNavGrid._h_min_passable + TerrainNavGrid.low_level_tolerance_m
	for gz in range(0, rows, step):
		for gx in range(0, cols, step):
			if not _cell_passable(gx, gz):
				continue
			# Basic slope check against immediate neighbours
			if not _cell_slope_ok(gx, gz):
				continue
			var wy: float = TerrainNavGrid._heights[gz * cols + gx]
			if not allow_elevated_routes and wy > h_ceil:
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

	var max_edge_sq := effective_edge_length * effective_edge_length
	var search_r    := int(effective_edge_length / effective_spacing) + 1

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


func _build_clearance_map(cols: int, rows: int, cell: float, _cooperative: bool = false) -> PackedFloat32Array:
	## BFS from every obstacle cell outward. Layered maps admit reachable shelves;
	## the original profile retains its low-canyon routing behavior.
	var cl := PackedFloat32Array()
	cl.resize(cols * rows)
	cl.fill(1e9)

	var allow_elevated_routes := _current_map_supports_elevated_routes()
	var h_ceil := TerrainNavGrid._h_min_passable + TerrainNavGrid.low_level_tolerance_m
	var queue: PackedInt32Array = []
	for gz in rows:
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
	while prev_d < dist - 0.001:
		var sample_d := minf(d, dist)
		var px := pa.x + dir.x * sample_d
		var pz := pa.z + dir.y * sample_d
		var h := TerrainNavGrid.sample_height(px, pz)
		if h <= TerrainNavGrid.IMPASSABLE * 0.5:
			return -1.0
		if _grade_exceeds_limit(prev_h, h, sample_d - prev_d):
			return -1.0
		prev_h = h
		prev_d = sample_d
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

