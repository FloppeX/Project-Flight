extends Node
## Autoload singleton (add as "TerrainNavGrid" in Project → Autoloads).
##
## Bakes a region of the terrain heightmap into a flat PackedFloat32Array once,
## then serves A* path requests to all vehicles without repeated get_height() calls.
## Requests are queued and processed one per frame to avoid physics spikes.

signal bake_complete

# --- Config (set in Inspector on the autoload node) ---
@export var cell_size_m: float = 40.0          ## Grid resolution in metres
@export var bake_half_extent_m: float = 6000.0 ## Half-side of baked square around terrain centre
@export var search_padding_m: float = 400.0    ## Extra A* search area beyond start→goal bbox
@export_range(1, 20) var rows_per_frame: int = 4 ## Terrain rows sampled per frame while baking
## Clearance radius in cells required around each path node.
## Carrier is ~76m wide; at 40m/cell use 2 so a 160m corridor is needed.
@export_range(0, 6) var body_clearance_cells: int = 3

# --- Baked grid ---
const IMPASSABLE: float = -1e6  # sentinel for out-of-bounds / NAN cells

var _heights: PackedFloat32Array
var _cols: int = 0
var _rows: int = 0
var _origin_x: float = 0.0
var _origin_z: float = 0.0
var _is_baked: bool = false

# --- Bake state ---
var _bake_terrain: Node3D = null
var _bake_gz: int = 0  # next row to bake

# --- Request queue ---
# Each entry: { from_world, to_world, max_slope_m, max_segment_m, callback }
var _queue: Array = []

# A* direction vectors (4 cardinal + 4 diagonal)
const DIRS: Array[Vector2i] = [
	Vector2i( 1,  0), Vector2i(-1,  0), Vector2i( 0,  1), Vector2i( 0, -1),
	Vector2i( 1,  1), Vector2i( 1, -1), Vector2i(-1,  1), Vector2i(-1, -1),
]
const DIAG_COST: float = 1.4142135


func _process(_delta: float) -> void:
	# Step 1: continue baking if in progress
	if _bake_terrain != null:
		_bake_rows()
		return

	# Step 2: try to start baking if not yet done
	if not _is_baked:
		_try_start_bake()
		return

	# Step 3: process one queued path request per frame
	if _queue.is_empty():
		return
	var req: Dictionary = _queue.pop_front()
	var path: Array[Vector3] = _astar(
		req.from_world, req.to_world,
		req.max_slope_m, req.max_segment_m)
	(req.callback as Callable).call(path)


## Queue an async path request. `callback` is called with Array[Vector3] when ready.
func request_path(from_world: Vector3, to_world: Vector3,
		max_slope_m: float, max_segment_m: float,
		callback: Callable) -> void:
	_queue.append({
		"from_world": from_world,
		"to_world": to_world,
		"max_slope_m": max_slope_m,
		"max_segment_m": max_segment_m,
		"callback": callback,
	})


## Sample terrain height from the baked grid. Returns IMPASSABLE if out of bounds or not yet baked.
func sample_height(wx: float, wz: float) -> float:
	if not _is_baked:
		return IMPASSABLE
	var gx := int((wx - _origin_x) / cell_size_m)
	var gz := int((wz - _origin_z) / cell_size_m)
	if gx < 0 or gx >= _cols or gz < 0 or gz >= _rows:
		return IMPASSABLE
	return _heights[gz * _cols + gx]


func is_ready() -> bool:
	return _is_baked


# --- Baking ---

func _try_start_bake() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain_provider") as Node3D
	if not is_instance_valid(terrain):
		return
	var cx: float = terrain.global_position.x
	var cz: float = terrain.global_position.z
	_origin_x = cx - bake_half_extent_m
	_origin_z = cz - bake_half_extent_m
	_cols = int(bake_half_extent_m * 2.0 / cell_size_m) + 1
	_rows = int(bake_half_extent_m * 2.0 / cell_size_m) + 1
	_heights.resize(_cols * _rows)
	_heights.fill(IMPASSABLE)
	_bake_terrain = terrain
	_bake_gz = 0
	print("[TerrainNavGrid] Starting bake: %d×%d cells at %.0fm (%.1f km²)" % [
		_cols, _rows, cell_size_m, (_cols * cell_size_m * _rows * cell_size_m) / 1e6])
		
	# Synchronous bake to avoid visual pop-in (teleport) on startup
	var original_rows_per_frame = rows_per_frame
	rows_per_frame = 9999
	_bake_rows()
	rows_per_frame = original_rows_per_frame


func _bake_rows() -> void:
	var t := _bake_terrain
	var end_gz := mini(_bake_gz + rows_per_frame, _rows)
	var ty: float = t.global_position.y
	for gz in range(_bake_gz, end_gz):
		for gx in range(_cols):
			var wx := _origin_x + gx * cell_size_m
			var wz := _origin_z + gz * cell_size_m
			var h = t.call("get_height", Vector3(wx, ty, wz))
			if typeof(h) == TYPE_FLOAT and not is_nan(float(h)):
				_heights[gz * _cols + gx] = float(h)
			# else stays IMPASSABLE
	_bake_gz = end_gz
	if _bake_gz >= _rows:
		_is_baked = true
		_bake_terrain = null
		print("[TerrainNavGrid] Bake complete (%d cells)" % [_cols * _rows])
		bake_complete.emit()


# --- A* ---

func _astar(from_world: Vector3, to_world: Vector3,
		max_slope_m: float, max_segment_m: float) -> Array[Vector3]:

	# Clip long-distance goals to max_segment_m
	var goal := to_world
	var direct := Vector3(to_world.x - from_world.x, 0.0, to_world.z - from_world.z)
	if direct.length() > max_segment_m:
		goal = from_world + direct.normalized() * max_segment_m

	# Search window in grid space
	var wx0 := minf(from_world.x, goal.x) - search_padding_m
	var wz0 := minf(from_world.z, goal.z) - search_padding_m
	var wx1 := maxf(from_world.x, goal.x) + search_padding_m
	var wz1 := maxf(from_world.z, goal.z) + search_padding_m

	var gx_min := clampi(int((wx0 - _origin_x) / cell_size_m), 0, _cols - 1)
	var gz_min := clampi(int((wz0 - _origin_z) / cell_size_m), 0, _rows - 1)
	var gx_max := clampi(int((wx1 - _origin_x) / cell_size_m), 0, _cols - 1)
	var gz_max := clampi(int((wz1 - _origin_z) / cell_size_m), 0, _rows - 1)

	var sg := _to_grid(from_world).clamp(Vector2i(gx_min, gz_min), Vector2i(gx_max, gz_max))
	var eg := _to_grid(goal).clamp(   Vector2i(gx_min, gz_min), Vector2i(gx_max, gz_max))

	if sg == eg:
		return [goal]

	# A* — open entries: [f_score, gx, gz]
	var open: Array = [[_h(sg, eg), sg.x, sg.y]]
	var g_score: Dictionary = { sg: 0.0 }
	var came_from: Dictionary = {}

	while not open.is_empty():
		open.sort_custom(func(a, b): return a[0] < b[0])
		var e: Array = open.pop_front()
		var cur := Vector2i(e[1], e[2])

		if cur == eg:
			return _smooth(_rebuild(came_from, cur), max_slope_m)

		var cur_h: float = _heights[cur.y * _cols + cur.x]
		if cur_h <= IMPASSABLE * 0.5:
			continue

		for dir in DIRS:
			var nb: Vector2i = cur + dir
			if nb.x < gx_min or nb.x > gx_max or nb.y < gz_min or nb.y > gz_max:
				continue
			if not _cell_clear(nb.x, nb.y, max_slope_m):
				continue
			var nb_h: float = _heights[nb.y * _cols + nb.x]
			var step: float = DIAG_COST if (dir.x != 0 and dir.y != 0) else 1.0
			var slope_pen: float = abs(nb_h - cur_h) / max_slope_m * 0.3
			var tg: float = g_score.get(cur, INF) + step + slope_pen
			if tg < g_score.get(nb, INF):
				came_from[nb] = cur
				g_score[nb] = tg
				open.append([tg + _h(nb, eg), nb.x, nb.y])

	print("[TerrainNavGrid] No path found — straight line fallback")
	return [goal]


func _rebuild(came_from: Dictionary, end: Vector2i) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var c := end
	while came_from.has(c):
		var wx: float = _origin_x + c.x * cell_size_m
		var wz: float = _origin_z + c.y * cell_size_m
		path.append(Vector3(wx, _heights[c.y * _cols + c.x], wz))
		c = came_from[c]
	path.reverse()
	return path


func _smooth(path: Array[Vector3], max_slope_m: float) -> Array[Vector3]:
	if path.size() <= 2:
		return path
	var result: Array[Vector3] = [path[0]]
	var i := 0
	while i < path.size() - 1:
		var furthest := i + 1
		for j in range(path.size() - 1, i + 1, -1):
			if _los_clear(path[i], path[j], max_slope_m):
				furthest = j
				break
		result.append(path[furthest])
		i = furthest
	return result


func _los_clear(a: Vector3, b: Vector3, max_slope_m: float) -> bool:
	var diff := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dist := diff.length()
	const STEP := 35.0
	if dist < STEP:
		return true
	var dir := diff / dist
	var prev_h := sample_height(a.x, a.z)
	var d := STEP
	while d < dist:
		var p := a + dir * d
		var h := sample_height(p.x, p.z)
		if h <= IMPASSABLE * 0.5 or abs(h - prev_h) > max_slope_m:
			return false
		prev_h = h
		d += STEP
	return true


# --- Public placement helpers ---

## Returns a random flat, passable world position (Y = terrain height).
## Useful for spawning vehicles at an interesting starting point.
## Returns Vector3.ZERO if nothing suitable is found within max_attempts.
func get_random_passable_position(rng: RandomNumberGenerator,
		max_slope_m: float = 15.0,
		max_attempts: int = 2000) -> Vector3:
	if not _is_baked:
		return Vector3.ZERO
	var border := body_clearance_cells + 8
	for _i in range(max_attempts):
		var gx := rng.randi_range(border, _cols - 1 - border)
		var gz := rng.randi_range(border, _rows - 1 - border)
		if _cell_clear(gx, gz, max_slope_m):
			var h: float = _heights[gz * _cols + gx]
			return Vector3(_origin_x + gx * cell_size_m, h, _origin_z + gz * cell_size_m)
	return Vector3.ZERO


## Returns the passable perimeter cell (inset by `edge_inset` cells) that is
## furthest from `from_world`. Used to send a vehicle toward the opposite edge.
func get_furthest_edge_position(from_world: Vector3, edge_inset: int = 3) -> Vector3:
	if not _is_baked:
		return from_world
	var from_gx := int((from_world.x - _origin_x) / cell_size_m)
	var from_gz := int((from_world.z - _origin_z) / cell_size_m)

	var best_sq := -1.0
	var best_gx := 0
	var best_gz := 0
	var found := false

	# Iterate the four perimeter strips at edge_inset depth
	var strips: Array[Array] = [
		[range(0, _cols),      [edge_inset]],               # top strip
		[range(0, _cols),      [_rows - 1 - edge_inset]],   # bottom strip
		[[edge_inset],         range(0, _rows)],             # left strip
		[[_cols - 1 - edge_inset], range(0, _rows)],        # right strip
	]
	for strip in strips:
		for gx in strip[0]:
			for gz in strip[1]:
				if gx < 0 or gx >= _cols or gz < 0 or gz >= _rows:
					continue
				if not _cell_clear(gx, gz, 30.0):
					continue
				var h: float = _heights[gz * _cols + gx]
				var dx := float(gx - from_gx)
				var dz := float(gz - from_gz)
				var sq := dx * dx + dz * dz
				if sq > best_sq:
					best_sq = sq
					best_gx = gx
					best_gz = gz
					found = true

	if not found:
		return from_world
	var bh: float = _heights[best_gz * _cols + best_gx]
	return Vector3(_origin_x + best_gx * cell_size_m, bh, _origin_z + best_gz * cell_size_m)


# --- Helpers ---

## Returns true only if the cell AND every cell within body_clearance_cells
## is passable and within max_slope_m of the centre cell's height.
func _cell_clear(gx: int, gz: int, max_slope_m: float) -> bool:
	var h: float = _heights[gz * _cols + gx]
	if h <= IMPASSABLE * 0.5:
		return false
	var r := body_clearance_cells
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var nx: int = gx + dx
			var nz: int = gz + dz
			if nx < 0 or nx >= _cols or nz < 0 or nz >= _rows:
				return false  # too close to bake edge
			var nh: float = _heights[nz * _cols + nx]
			if nh <= IMPASSABLE * 0.5 or abs(nh - h) > max_slope_m:
				return false
	return true


func _to_grid(world: Vector3) -> Vector2i:
	return Vector2i(int((world.x - _origin_x) / cell_size_m),
					int((world.z - _origin_z) / cell_size_m))


func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := float(a.x - b.x)
	var dz := float(a.y - b.y)
	return sqrt(dx * dx + dz * dz)
