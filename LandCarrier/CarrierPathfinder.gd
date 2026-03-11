class_name CarrierPathfinder

# A* pathfinding directly on the terrain heightmap.
# find_path() returns a smoothed Array[Vector3] of world-space waypoints.
# Impassable cells: NAN height (out of terrain bounds) or slope > max_slope_m.

const DIRS: Array[Vector2i] = [
	Vector2i( 1,  0), Vector2i(-1,  0), Vector2i( 0,  1), Vector2i( 0, -1),
	Vector2i( 1,  1), Vector2i( 1, -1), Vector2i(-1,  1), Vector2i(-1, -1),
]
const DIAG_COST: float = 1.4142135

static func find_path(
		terrain: Node3D,
		from_world: Vector3,
		to_world: Vector3,
		cell_size: float = 40.0,
		max_slope_m: float = 22.0,
		padding_m: float = 400.0,
		max_segment_m: float = 800.0) -> Array[Vector3]:

	# If the goal is very far, pathfind to an intermediate point in that direction.
	# This keeps the grid manageable and allows replanning each segment.
	var goal := to_world
	var direct := Vector3(to_world.x - from_world.x, 0.0, to_world.z - from_world.z)
	if direct.length() > max_segment_m:
		goal = from_world + direct.normalized() * max_segment_m

	# Build grid bounds with padding
	var min_x := minf(from_world.x, goal.x) - padding_m
	var min_z := minf(from_world.z, goal.z) - padding_m
	var max_x := maxf(from_world.x, goal.x) + padding_m
	var max_z := maxf(from_world.z, goal.z) + padding_m

	var cols := int(ceil((max_x - min_x) / cell_size)) + 1
	var rows := int(ceil((max_z - min_z) / cell_size)) + 1

	# Sample all terrain heights up front (one batch of get_height calls)
	var heights := PackedFloat32Array()
	heights.resize(cols * rows)
	for gz in range(rows):
		for gx in range(cols):
			heights[gz * cols + gx] = _sample_y(terrain, min_x + gx * cell_size, min_z + gz * cell_size)

	# Convert world positions to grid cells
	var sg := _to_grid(from_world, min_x, min_z, cell_size).clamp(Vector2i.ZERO, Vector2i(cols - 1, rows - 1))
	var eg := _to_grid(goal,       min_x, min_z, cell_size).clamp(Vector2i.ZERO, Vector2i(cols - 1, rows - 1))

	if sg == eg:
		return [goal]

	# A* — open list entries: [f_score, gx, gz]
	var open: Array = []
	var g_score: Dictionary = {}
	var came_from: Dictionary = {}

	g_score[sg] = 0.0
	open.append([_h(sg, eg), sg.x, sg.y])

	while not open.is_empty():
		open.sort_custom(func(a, b): return a[0] < b[0])
		var e = open.pop_front()
		var cur := Vector2i(e[1], e[2])

		if cur == eg:
			var path := _rebuild(came_from, cur, min_x, min_z, cell_size, terrain)
			return _smooth(path, terrain, max_slope_m)

		var cur_h: float = heights[cur.y * cols + cur.x]
		if is_nan(cur_h):
			continue

		for dir in DIRS:
			var nb: Vector2i = cur + dir
			if nb.x < 0 or nb.x >= cols or nb.y < 0 or nb.y >= rows:
				continue
			var nb_h: float = heights[nb.y * cols + nb.x]
			if is_nan(nb_h) or abs(nb_h - cur_h) > max_slope_m:
				continue
			var step: float = DIAG_COST if (dir.x != 0 and dir.y != 0) else 1.0
			# Prefer flatter routes with a small slope penalty
			var slope_penalty: float = abs(nb_h - cur_h) / max_slope_m * 0.3
			var tg: float = g_score.get(cur, INF) + step + slope_penalty
			if tg < g_score.get(nb, INF):
				came_from[nb] = cur
				g_score[nb] = tg
				open.append([tg + _h(nb, eg), nb.x, nb.y])

	# No path found — return straight shot to the intermediate goal
	print("[CarrierPathfinder] No path found from ", from_world, " to ", goal, " — falling back to straight line")
	return [goal]


# Line-of-sight smoothing: collapse stairstepped A* path into fewer waypoints
static func _smooth(path: Array[Vector3], terrain: Node3D, max_slope_m: float) -> Array[Vector3]:
	if path.size() <= 2:
		return path
	var result: Array[Vector3] = [path[0]]
	var i := 0
	while i < path.size() - 1:
		var furthest := i + 1
		for j in range(path.size() - 1, i + 1, -1):
			if _los_clear(path[i], path[j], terrain, max_slope_m):
				furthest = j
				break
		result.append(path[furthest])
		i = furthest
	return result


static func _los_clear(a: Vector3, b: Vector3, terrain: Node3D, max_slope_m: float) -> bool:
	var diff := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dist := diff.length()
	const STEP := 30.0
	if dist < STEP:
		return true
	var dir := diff / dist
	var prev_h := _sample_y(terrain, a.x, a.z)
	var d := STEP
	while d < dist:
		var p := a + dir * d
		var h := _sample_y(terrain, p.x, p.z)
		if is_nan(h) or abs(h - prev_h) > max_slope_m:
			return false
		prev_h = h
		d += STEP
	return true


static func _rebuild(came_from: Dictionary, end: Vector2i, min_x: float, min_z: float, cell_size: float, terrain: Node3D) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var c := end
	while came_from.has(c):
		var wx := min_x + c.x * cell_size
		var wz := min_z + c.y * cell_size
		var wy := _sample_y(terrain, wx, wz)
		path.append(Vector3(wx, wy if not is_nan(wy) else 0.0, wz))
		c = came_from[c]
	path.reverse()
	return path


static func _to_grid(world: Vector3, min_x: float, min_z: float, cell_size: float) -> Vector2i:
	return Vector2i(int((world.x - min_x) / cell_size), int((world.z - min_z) / cell_size))


static func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := float(a.x - b.x)
	var dz := float(a.y - b.y)
	return sqrt(dx * dx + dz * dz)


# Sample terrain world-Y at (wx, wz). Returns NAN if out of bounds.
static func _sample_y(terrain: Node3D, wx: float, wz: float) -> float:
	var h = terrain.call("get_height", Vector3(wx, terrain.global_position.y, wz))
	if typeof(h) != TYPE_FLOAT:
		return NAN
	return float(h)
