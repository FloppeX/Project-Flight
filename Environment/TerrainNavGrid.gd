extends Node
## Autoload singleton (add as "TerrainNavGrid" in Project → Autoloads).
##
## Bakes a region of the terrain heightmap into a flat PackedFloat32Array once,
## then serves A* path requests to all vehicles without repeated get_height() calls.
## Requests are queued and processed one per frame to avoid physics spikes.

signal bake_complete

func _ready() -> void:
	add_to_group("origin_shifter")

func apply_origin_shift(offset: Vector3) -> void:
	_origin_x -= offset.x
	_origin_z -= offset.z
	_query_origin_x -= offset.x
	_query_origin_z -= offset.z
	_bake_center_x -= offset.x
	_bake_center_z -= offset.z
	if _bake_center_override_enabled:
		_bake_center_override_x -= offset.x
		_bake_center_override_z -= offset.z


# --- Config (set in Inspector on the autoload node) ---
@export var cell_size_m: float = 40.0          ## Grid resolution in metres
@export var bake_half_extent_m: float = 9000.0 ## Half-side of baked square around terrain centre
@export var search_padding_m: float = 400.0    ## Extra A* search area beyond start→goal bbox
@export_range(1, 20) var rows_per_frame: int = 4 ## Terrain rows sampled per frame while baking
## Clearance radius in cells required around each path node.
## Carrier is ~76m wide; at 40m/cell use 2 so a 160m corridor is needed.
@export_range(0, 8) var body_clearance_cells: int = 3
## Extra buffer in cells around steep terrain transitions/cliff bands.
## Higher values keep paths and spawn points further from sharp height changes.
@export_range(1, 8) var steep_slope_margin_cells: int = 2
## Max straight-line distance LOS smoothing may skip in metres.
## Lower = more waypoints kept, gentler turns. 0 = no smoothing.
@export var max_smooth_segment_m: float = 400.0
## Height tolerance above the terrain minimum to be considered "lowest level".
## Raise this if the lowest plateau has internal variation > 80m.
@export var low_level_tolerance_m: float = 80.0

@export_group("Query Grid")
## Finer, non-A* grid used for cheap terrain safety/footprint checks.
@export var query_grid_enabled: bool = true
@export var query_cell_size_m: float = 32.0
## Radius, in query cells, used to bake local height variation / edge risk.
@export_range(1, 4) var query_edge_radius_cells: int = 2

# --- Baked grid ---
const IMPASSABLE: float = -1e6  # sentinel for out-of-bounds / NAN cells

var _heights: PackedFloat32Array
var _cols: int = 0
var _rows: int = 0
var _origin_x: float = 0.0
var _origin_z: float = 0.0
var _bake_center_x: float = 0.0
var _bake_center_z: float = 0.0
var _is_baked: bool = false
var _h_min_passable: float = INF  # lowest height among all baked passable cells
var _bake_center_override_enabled: bool = false
var _bake_center_override_x: float = 0.0
var _bake_center_override_z: float = 0.0

var _query_heights: PackedFloat32Array
var _query_height_variation: PackedFloat32Array
var _query_max_heights: PackedFloat32Array
var _query_cols: int = 0
var _query_rows: int = 0
var _query_origin_x: float = 0.0
var _query_origin_z: float = 0.0
var _query_is_baked: bool = false

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


## Sample terrain height from the baked grid with bilinear interpolation.
## Returns IMPASSABLE if out of bounds or not yet baked.
func sample_height(wx: float, wz: float) -> float:
	if not _is_baked:
		return IMPASSABLE
	var fx := (wx - _origin_x) / cell_size_m
	var fz := (wz - _origin_z) / cell_size_m
	var gx0 := int(fx)
	var gz0 := int(fz)
	# Fall back to nearest-cell if on the edge or out of bounds
	if gx0 < 0 or gx0 >= _cols - 1 or gz0 < 0 or gz0 >= _rows - 1:
		var gx := clampi(gx0, 0, _cols - 1)
		var gz := clampi(gz0, 0, _rows - 1)
		return _heights[gz * _cols + gx]
	var tx := fx - gx0
	var tz := fz - gz0
	var h00 := _heights[gz0 * _cols + gx0]
	var h10 := _heights[gz0 * _cols + (gx0 + 1)]
	var h01 := _heights[(gz0 + 1) * _cols + gx0]
	var h11 := _heights[(gz0 + 1) * _cols + (gx0 + 1)]
	# If any corner is IMPASSABLE fall back to the base cell
	if h00 <= IMPASSABLE * 0.5 or h10 <= IMPASSABLE * 0.5 or h01 <= IMPASSABLE * 0.5 or h11 <= IMPASSABLE * 0.5:
		return h00 if h00 > IMPASSABLE * 0.5 else IMPASSABLE
	return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)


func has_query_grid() -> bool:
	return _query_is_baked


func sample_query_height(wx: float, wz: float) -> float:
	if not _query_is_baked:
		return IMPASSABLE
	return _sample_query_height_from_array(_query_heights, wx, wz, false)


func sample_query_edge_risk(wx: float, wz: float) -> float:
	if not _query_is_baked:
		return INF
	return _sample_query_height_from_array(_query_height_variation, wx, wz, true)


func sample_query_max_height(wx: float, wz: float) -> float:
	if not _query_is_baked:
		return INF
	return _sample_query_height_from_array(_query_max_heights, wx, wz, true)


func is_heightmap_safe_for_aircraft(wx: float, wz: float, max_height_variation_m: float) -> bool:
	if not _query_is_baked:
		return false
	var edge_risk: float = sample_query_edge_risk(wx, wz)
	return edge_risk < INF and edge_risk <= max_height_variation_m


func is_stable_footprint(wx: float, wz: float, radius_m: float, max_center_drop_m: float, max_height_variation_m: float) -> bool:
	if not _query_is_baked:
		return false
	var center_h: float = sample_query_height(wx, wz)
	if center_h <= IMPASSABLE * 0.5:
		return false
	var center_g := _to_query_grid(wx, wz)
	var radius_cells: int = maxi(int(ceil(maxf(radius_m, 0.0) / maxf(query_cell_size_m, 1.0))), 1)
	var min_h: float = center_h
	var max_h: float = center_h
	var sample_radius_sq: float = pow(radius_m + query_cell_size_m * 0.75, 2.0)
	for dz in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var nx: int = center_g.x + dx
			var nz: int = center_g.y + dz
			if nx < 0 or nx >= _query_cols or nz < 0 or nz >= _query_rows:
				return false
			var sample_dx: float = float(dx) * query_cell_size_m
			var sample_dz: float = float(dz) * query_cell_size_m
			if sample_dx * sample_dx + sample_dz * sample_dz > sample_radius_sq:
				continue
			var idx: int = nz * _query_cols + nx
			var h: float = _query_heights[idx]
			if h <= IMPASSABLE * 0.5:
				return false
			if center_h - h > max_center_drop_m:
				return false
			var variation: float = _query_height_variation[idx]
			if variation >= INF or variation > max_height_variation_m:
				return false
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)
			if max_h - min_h > max_height_variation_m:
				return false
	return true


func get_max_height_in_radius(wx: float, wz: float, radius_m: float) -> float:
	if not _query_is_baked:
		return IMPASSABLE
	var center_g := _to_query_grid(wx, wz)
	var radius_cells: int = maxi(int(ceil(maxf(radius_m, 0.0) / maxf(query_cell_size_m, 1.0))), 1)
	var max_h: float = -INF
	var sample_radius_sq: float = pow(radius_m + query_cell_size_m * 0.75, 2.0)
	var found := false
	for dz in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var nx: int = center_g.x + dx
			var nz: int = center_g.y + dz
			if nx < 0 or nx >= _query_cols or nz < 0 or nz >= _query_rows:
				continue
			var sample_dx: float = float(dx) * query_cell_size_m
			var sample_dz: float = float(dz) * query_cell_size_m
			if sample_dx * sample_dx + sample_dz * sample_dz > sample_radius_sq:
				continue
			var idx: int = nz * _query_cols + nx
			var h: float = _query_heights[idx]
			if h > IMPASSABLE * 0.5:
				max_h = maxf(max_h, h)
				found = true
	return max_h if found else IMPASSABLE


func is_ready() -> bool:
	return _is_baked

func set_bake_center_override(world_center: Vector3) -> void:
	_bake_center_override_enabled = true
	_bake_center_override_x = world_center.x
	_bake_center_override_z = world_center.z

func rebake_at_center(world_center: Vector3) -> void:
	set_bake_center_override(world_center)
	_reset_bake_state()

func clear_bake_center_override() -> void:
	_bake_center_override_enabled = false

func get_bake_center() -> Vector3:
	return Vector3(_bake_center_x, 0.0, _bake_center_z)

func _reset_bake_state() -> void:
	_heights = PackedFloat32Array()
	_cols = 0
	_rows = 0
	_origin_x = 0.0
	_origin_z = 0.0
	_bake_center_x = 0.0
	_bake_center_z = 0.0
	_query_heights = PackedFloat32Array()
	_query_height_variation = PackedFloat32Array()
	_query_max_heights = PackedFloat32Array()
	_query_cols = 0
	_query_rows = 0
	_query_origin_x = 0.0
	_query_origin_z = 0.0
	_query_is_baked = false
	_h_min_passable = INF
	_is_baked = false
	_bake_terrain = null
	_bake_gz = 0
	_queue.clear()


## Returns 0.0 while waiting for terrain, 0.0→1.0 while baking, 1.0 when done.
func get_bake_progress() -> float:
	if _is_baked:
		return 1.0
	if _bake_terrain == null or _rows == 0:
		return 0.0
	return float(_bake_gz) / float(_rows)


# --- Baking ---

func _try_start_bake() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain_provider") as Node3D
	if not is_instance_valid(terrain):
		return
	var cx: float = _bake_center_override_x if _bake_center_override_enabled else terrain.global_position.x
	var cz: float = _bake_center_override_z if _bake_center_override_enabled else terrain.global_position.z
	_bake_center_x = cx
	_bake_center_z = cz
	_origin_x = cx - bake_half_extent_m
	_origin_z = cz - bake_half_extent_m
	_query_origin_x = _origin_x
	_query_origin_z = _origin_z
	_cols = int(bake_half_extent_m * 2.0 / cell_size_m) + 1
	_rows = int(bake_half_extent_m * 2.0 / cell_size_m) + 1
	_heights.resize(_cols * _rows)
	_heights.fill(IMPASSABLE)
	_bake_terrain = terrain
	_bake_gz = 0
		
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
		_bake_query_grid(t)
		_is_baked = true
		_bake_terrain = null
		_h_min_passable = INF
		for h in _heights:
			if h > IMPASSABLE * 0.5:
				_h_min_passable = minf(_h_min_passable, h)
		bake_complete.emit()


func _bake_query_grid(t: Node3D) -> void:
	_query_is_baked = false
	_query_heights = PackedFloat32Array()
	_query_height_variation = PackedFloat32Array()
	_query_max_heights = PackedFloat32Array()
	_query_cols = 0
	_query_rows = 0
	if not query_grid_enabled or not is_instance_valid(t):
		return
	var q_cell: float = maxf(query_cell_size_m, 1.0)
	_query_origin_x = _bake_center_x - bake_half_extent_m
	_query_origin_z = _bake_center_z - bake_half_extent_m
	_query_cols = int(bake_half_extent_m * 2.0 / q_cell) + 1
	_query_rows = int(bake_half_extent_m * 2.0 / q_cell) + 1
	_query_heights.resize(_query_cols * _query_rows)
	_query_heights.fill(IMPASSABLE)
	var ty: float = t.global_position.y
	for gz in range(_query_rows):
		for gx in range(_query_cols):
			var wx := _query_origin_x + gx * q_cell
			var wz := _query_origin_z + gz * q_cell
			var h = t.call("get_height", Vector3(wx, ty, wz))
			if (typeof(h) == TYPE_FLOAT or typeof(h) == TYPE_INT) and not is_nan(float(h)):
				_query_heights[gz * _query_cols + gx] = float(h)
	_compute_query_height_variation()
	_query_is_baked = true


func _compute_query_height_variation() -> void:
	_query_height_variation.resize(_query_cols * _query_rows)
	_query_height_variation.fill(INF)
	_query_max_heights.resize(_query_cols * _query_rows)
	_query_max_heights.fill(-INF)
	var r: int = maxi(query_edge_radius_cells, 1)
	for gz in range(_query_rows):
		for gx in range(_query_cols):
			var idx: int = gz * _query_cols + gx
			var h: float = _query_heights[idx]
			if h <= IMPASSABLE * 0.5:
				continue
			var min_h: float = h
			var max_h: float = h
			var valid: bool = true
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var nx: int = gx + dx
					var nz: int = gz + dz
					if nx < 0 or nx >= _query_cols or nz < 0 or nz >= _query_rows:
						valid = false
						break
					var nh: float = _query_heights[nz * _query_cols + nx]
					if nh <= IMPASSABLE * 0.5:
						valid = false
						break
					min_h = minf(min_h, nh)
					max_h = maxf(max_h, nh)
				if not valid:
					break
			if valid:
				_query_height_variation[idx] = max_h - min_h
				_query_max_heights[idx] = max_h


# --- A* ---

func _astar(from_world: Vector3, to_world: Vector3,
		max_slope_m: float, max_segment_m: float) -> Array[Vector3]:

	# Clip long-distance goals to max_segment_m
	var goal := to_world
	var direct := Vector3(to_world.x - from_world.x, 0.0, to_world.z - from_world.z)
	if direct.length() > max_segment_m:
		goal = from_world + direct.normalized() * max_segment_m

	# Search window: use the full destination (not the clipped goal) so A* has
	# room to route around large obstacles even on the first segment.
	var wx0 := minf(from_world.x, to_world.x) - search_padding_m
	var wz0 := minf(from_world.z, to_world.z) - search_padding_m
	var wx1 := maxf(from_world.x, to_world.x) + search_padding_m
	var wz1 := maxf(from_world.z, to_world.z) + search_padding_m

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

	return []


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
			var seg_len := Vector2(path[j].x - path[i].x, path[j].z - path[i].z).length()
			if max_smooth_segment_m > 0.0 and seg_len > max_smooth_segment_m:
				continue  # too far — keep intermediate nodes for gentler turns
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
		var p: Vector3 = a + dir * d
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
	var h_ceil := _h_min_passable + low_level_tolerance_m
	for _i in range(max_attempts):
		var gx := rng.randi_range(border, _cols - 1 - border)
		var gz := rng.randi_range(border, _rows - 1 - border)
		var h: float = _heights[gz * _cols + gx]
		if h > h_ceil:
			continue  # skip mid/high level cells
		if _cell_clear(gx, gz, max_slope_m):
			return Vector3(_origin_x + gx * cell_size_m, h, _origin_z + gz * cell_size_m)
	return Vector3.ZERO


## Returns the passable perimeter cell (inset by `edge_inset` cells) that is
## furthest from `from_world`. Used to send a vehicle toward the opposite edge.
func get_furthest_edge_position(from_world: Vector3, edge_inset: int = 3, max_slope_m: float = 15.0) -> Vector3:
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
	var h_ceil := _h_min_passable + low_level_tolerance_m
	for strip in strips:
		for gx in strip[0]:
			for gz in strip[1]:
				if gx < 0 or gx >= _cols or gz < 0 or gz >= _rows:
					continue
				var h: float = _heights[gz * _cols + gx]
				if h > h_ceil:
					continue  # skip mid/high level cells
				if not _cell_clear(gx, gz, max_slope_m):
					continue
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


## Returns a low-level passable cell near the centre of the requested edge.
## Searches laterally around the map midpoint and then progressively inward.
func get_centered_edge_position(
		edge: String,
		edge_margin_m: float = 1800.0,
		lateral_search_m: float = 3600.0,
		inward_search_m: float = 2800.0,
		max_slope_m: float = 15.0) -> Vector3:
	if not _is_baked:
		return Vector3.ZERO

	var border := body_clearance_cells + 8
	var max_gx := _cols - 1 - border
	var max_gz := _rows - 1 - border
	if border > max_gx or border > max_gz:
		return Vector3.ZERO

	var center_gx := clampi(int(round(float(_cols - 1) * 0.5)), border, max_gx)
	var edge_margin_cells := maxi(int(round(maxf(edge_margin_m, 0.0) / cell_size_m)), border)
	var lateral_cells := maxi(int(round(maxf(lateral_search_m, 0.0) / cell_size_m)), 0)
	var inward_cells := maxi(int(round(maxf(inward_search_m, 0.0) / cell_size_m)), 0)

	var desired_gz := border
	var depth_sign := 1
	match edge.to_lower():
		"top":
			desired_gz = clampi(edge_margin_cells, border, max_gz)
			depth_sign = 1
		"bottom":
			desired_gz = clampi((_rows - 1) - edge_margin_cells, border, max_gz)
			depth_sign = -1
		_:
			return Vector3.ZERO

	var h_ceil := _h_min_passable + low_level_tolerance_m
	var best_score := INF
	var best_gx := center_gx
	var best_gz := desired_gz
	var found := false

	for depth_offset in range(inward_cells + 1):
		var gz := desired_gz + depth_sign * depth_offset
		if gz < border or gz > max_gz:
			continue
		for lateral_offset in range(-lateral_cells, lateral_cells + 1):
			var gx := center_gx + lateral_offset
			if gx < border or gx > max_gx:
				continue
			var h: float = _heights[gz * _cols + gx]
			if h > h_ceil:
				continue
			if not _cell_clear(gx, gz, max_slope_m):
				continue
			var score := absf(float(lateral_offset)) + float(depth_offset) * 0.65
			if score < best_score:
				best_score = score
				best_gx = gx
				best_gz = gz
				found = true

	if not found:
		return Vector3.ZERO

	var bh: float = _heights[best_gz * _cols + best_gx]
	return Vector3(_origin_x + best_gx * cell_size_m, bh, _origin_z + best_gz * cell_size_m)


## Returns passable candidates sampled across the requested edge band.
## Useful when callers want to evaluate several edge goals and choose the best route.
func get_edge_position_candidates(
		edge: String,
		edge_margin_m: float = 1800.0,
		lateral_spacing_m: float = 1200.0,
		inward_search_m: float = 2800.0,
		max_slope_m: float = 15.0) -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	if not _is_baked:
		return candidates

	var border := body_clearance_cells + 8
	var max_gx := _cols - 1 - border
	var max_gz := _rows - 1 - border
	if border > max_gx or border > max_gz:
		return candidates

	var edge_margin_cells := maxi(int(round(maxf(edge_margin_m, 0.0) / cell_size_m)), border)
	var inward_cells := maxi(int(round(maxf(inward_search_m, 0.0) / cell_size_m)), 0)
	var lateral_step_cells := maxi(int(round(maxf(lateral_spacing_m, cell_size_m) / cell_size_m)), 1)
	var lateral_radius_cells := maxi(lateral_step_cells / 2, 1)

	var desired_gz := border
	var depth_sign := 1
	match edge.to_lower():
		"top":
			desired_gz = clampi(edge_margin_cells, border, max_gz)
			depth_sign = 1
		"bottom":
			desired_gz = clampi((_rows - 1) - edge_margin_cells, border, max_gz)
			depth_sign = -1
		_:
			return candidates

	var h_ceil := _h_min_passable + low_level_tolerance_m
	var seen_keys := {}
	var target_gx: int = border
	while target_gx <= max_gx:
		var best_score := INF
		var best_gx := -1
		var best_gz := -1
		for depth_offset in range(inward_cells + 1):
			var gz := desired_gz + depth_sign * depth_offset
			if gz < border or gz > max_gz:
				continue
			for lateral_offset in range(-lateral_radius_cells, lateral_radius_cells + 1):
				var gx := target_gx + lateral_offset
				if gx < border or gx > max_gx:
					continue
				var h: float = _heights[gz * _cols + gx]
				if h > h_ceil:
					continue
				if not _cell_clear(gx, gz, max_slope_m):
					continue
				var score := absf(float(lateral_offset)) + float(depth_offset) * 0.65
				if score < best_score:
					best_score = score
					best_gx = gx
					best_gz = gz
		if best_gx >= 0 and best_gz >= 0:
			var key := "%d:%d" % [best_gx, best_gz]
			if not seen_keys.has(key):
				seen_keys[key] = true
				var bh: float = _heights[best_gz * _cols + best_gx]
				candidates.append(Vector3(_origin_x + best_gx * cell_size_m, bh, _origin_z + best_gz * cell_size_m))
		target_gx += lateral_step_cells

	var center_candidate := get_centered_edge_position(
		edge,
		edge_margin_m,
		maxf(lateral_spacing_m, cell_size_m),
		inward_search_m,
		max_slope_m
	)
	if center_candidate != Vector3.ZERO:
		var center_key := "%d:%d" % [
			int(round((center_candidate.x - _origin_x) / cell_size_m)),
			int(round((center_candidate.z - _origin_z) / cell_size_m))
		]
		if not seen_keys.has(center_key):
			candidates.append(center_candidate)

	return candidates


# --- Helpers ---

## Returns true if the cell is passable, has no impassable neighbours within
## body_clearance_cells, and has no steep slope to its immediate (radius-1) neighbours.
## Separating the two checks opens up interior flat areas that were previously
## rejected because a distant neighbour happened to border a plateau.
func _cell_clear(gx: int, gz: int, max_slope_m: float) -> bool:
	var h: float = _heights[gz * _cols + gx]
	if h <= IMPASSABLE * 0.5:
		return false

	# Clearance check: no impassable cell within body_clearance_cells radius.
	var r := body_clearance_cells
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var nx: int = gx + dx
			var nz: int = gz + dz
			if nx < 0 or nx >= _cols or nz < 0 or nz >= _rows:
				return false  # too close to bake edge
			if _heights[nz * _cols + nx] <= IMPASSABLE * 0.5:
				return false  # impassable cell too close

	return not is_cell_near_steep_slope(gx, gz, max_slope_m)


func is_cell_near_steep_slope(gx: int, gz: int, max_slope_m: float, radius_cells: int = -1) -> bool:
	if gx < 0 or gx >= _cols or gz < 0 or gz >= _rows:
		return true
	var h: float = _heights[gz * _cols + gx]
	if h <= IMPASSABLE * 0.5:
		return true
	var r: int = maxi(radius_cells if radius_cells >= 0 else steep_slope_margin_cells, 1)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx == 0 and dz == 0:
				continue
			var nx: int = gx + dx
			var nz: int = gz + dz
			if nx < 0 or nx >= _cols or nz < 0 or nz >= _rows:
				continue
			var nh: float = _heights[nz * _cols + nx]
			if nh <= IMPASSABLE * 0.5:
				continue
			if abs(nh - h) > max_slope_m:
				return true
	return false


func _to_grid(world: Vector3) -> Vector2i:
	return Vector2i(int((world.x - _origin_x) / cell_size_m),
					int((world.z - _origin_z) / cell_size_m))


func _to_query_grid(wx: float, wz: float) -> Vector2i:
	return Vector2i(
		int((wx - _query_origin_x) / maxf(query_cell_size_m, 1.0)),
		int((wz - _query_origin_z) / maxf(query_cell_size_m, 1.0))
	)


func _sample_query_height_from_array(values: PackedFloat32Array, wx: float, wz: float, use_max_corners: bool) -> float:
	if values.is_empty() or _query_cols <= 0 or _query_rows <= 0:
		return INF if use_max_corners else IMPASSABLE
	var q_cell: float = maxf(query_cell_size_m, 1.0)
	var fx := (wx - _query_origin_x) / q_cell
	var fz := (wz - _query_origin_z) / q_cell
	var gx0 := int(fx)
	var gz0 := int(fz)
	if gx0 < 0 or gx0 >= _query_cols - 1 or gz0 < 0 or gz0 >= _query_rows - 1:
		var gx := clampi(gx0, 0, _query_cols - 1)
		var gz := clampi(gz0, 0, _query_rows - 1)
		return values[gz * _query_cols + gx]
	var tx := fx - gx0
	var tz := fz - gz0
	var v00 := values[gz0 * _query_cols + gx0]
	var v10 := values[gz0 * _query_cols + (gx0 + 1)]
	var v01 := values[(gz0 + 1) * _query_cols + gx0]
	var v11 := values[(gz0 + 1) * _query_cols + (gx0 + 1)]
	if use_max_corners:
		return maxf(maxf(v00, v10), maxf(v01, v11))
	if v00 <= IMPASSABLE * 0.5 or v10 <= IMPASSABLE * 0.5 or v01 <= IMPASSABLE * 0.5 or v11 <= IMPASSABLE * 0.5:
		return v00 if v00 > IMPASSABLE * 0.5 else IMPASSABLE
	return lerp(lerp(v00, v10, tx), lerp(v01, v11, tx), tz)


func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := float(a.x - b.x)
	var dz := float(a.y - b.y)
	return sqrt(dx * dx + dz * dz)


# --- Debug image export ---

const _IMG_SCALE: int = 3  # pixels per grid cell — scales output to ~900×900

## Saves a PNG of the baked heightmap to user:// with the nav path overlaid.
## carrier_pos and destination are optional world-space positions (Vector3.ZERO = omit).
## max_slope_m is used to run a full preview A* from carrier to destination.
func save_debug_image(path_world: Array[Vector3] = [],
		carrier_pos: Vector3 = Vector3.ZERO,
		destination: Vector3 = Vector3.ZERO,
		max_slope_m: float = 12.0) -> void:
	if not _is_baked:
		print("[TerrainNavGrid] Cannot save image: not yet baked")
		return

	var W := _cols * _IMG_SCALE
	var H := _rows * _IMG_SCALE

	# Height range for grayscale normalisation (skip IMPASSABLE sentinels)
	var h_min := INF
	var h_max := -INF
	for h in _heights:
		if h > IMPASSABLE * 0.5:
			h_min = minf(h_min, h)
			h_max = maxf(h_max, h)
	var h_range := maxf(h_max - h_min, 1.0)

	var img := Image.create(W, H, false, Image.FORMAT_RGB8)

	# Grayscale heightmap — fill each cell as a SCALE×SCALE block
	for gz in _rows:
		for gx in _cols:
			var h: float = _heights[gz * _cols + gx]
			var col: Color
			if h <= IMPASSABLE * 0.5:
				col = Color(0.15, 0.0, 0.25)  # dark purple = impassable
			else:
				var t := (h - h_min) / h_range
				col = Color(t, t, t)
			for py in _IMG_SCALE:
				for px in _IMG_SCALE:
					img.set_pixel(gx * _IMG_SCALE + px, gz * _IMG_SCALE + py, col)

	# Full route preview: run A* from carrier to destination with no segment cap
	if carrier_pos != Vector3.ZERO and destination != Vector3.ZERO:
		print("[TerrainNavGrid] Computing full route preview for debug image…")
		var full_path: Array[Vector3] = _astar(carrier_pos, destination, max_slope_m, INF)
		if full_path.size() >= 2:
			for i in range(full_path.size() - 1):
				_img_line(img, _to_grid(full_path[i]), _to_grid(full_path[i + 1]), Color(1.0, 0.4, 0.0), 2)
		for p in full_path:
			_img_dot(img, _to_grid(p), Color(1.0, 0.7, 0.0), 2)

	# Current active A* segment in bright red on top
	for i in range(path_world.size() - 1):
		_img_line(img, _to_grid(path_world[i]), _to_grid(path_world[i + 1]), Color.RED, 2)
	for p in path_world:
		_img_dot(img, _to_grid(p), Color.RED, 3)

	# Carrier position — bright green cross
	if carrier_pos != Vector3.ZERO:
		_img_cross(img, _to_grid(carrier_pos), Color.GREEN, 5)

	# Destination — cyan cross
	if destination != Vector3.ZERO:
		_img_cross(img, _to_grid(destination), Color.CYAN, 5)

	var save_path := "user://navgrid_debug.png"
	img.save_png(save_path)
	print("[TerrainNavGrid] Debug image saved → ", save_path,
		"  (%d×%d px, %d cells, %.0fm/cell)" % [W, H, _cols * _rows, cell_size_m])


# Pixel coords from grid coords (centre of cell block)
func _gp(g: Vector2i) -> Vector2i:
	return Vector2i(g.x * _IMG_SCALE + _IMG_SCALE / 2,
					g.y * _IMG_SCALE + _IMG_SCALE / 2)


func _img_set(img: Image, px: int, py: int, col: Color) -> void:
	if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
		img.set_pixel(px, py, col)


func _img_dot(img: Image, g: Vector2i, col: Color, r: int) -> void:
	var p := _gp(g)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			_img_set(img, p.x + dx, p.y + dy, col)


func _img_cross(img: Image, g: Vector2i, col: Color, r: int) -> void:
	var p := _gp(g)
	for d in range(-r, r + 1):
		_img_set(img, p.x + d, p.y, col)
		_img_set(img, p.x, p.y + d, col)
	# Thicken the cross arms by 1px
	for d in range(-r, r + 1):
		_img_set(img, p.x + d, p.y + 1, col)
		_img_set(img, p.x + 1, p.y + d, col)


## Bresenham line in pixel space with optional half-width thickness.
func _img_line(img: Image, a: Vector2i, b: Vector2i, col: Color, thickness: int = 1) -> void:
	var pa := _gp(a)
	var pb := _gp(b)
	_bresenham(img, pa, pb, col, thickness)


## Dashed Bresenham line; dash_len is in pixels.
func _img_dashed_line(img: Image, a: Vector2i, b: Vector2i, col: Color,
		thickness: int = 1, dash_len: int = 6) -> void:
	var pa := _gp(a)
	var pb := _gp(b)
	var dx := pb.x - pa.x
	var dz := pb.y - pa.y
	var dist := int(sqrt(float(dx * dx + dz * dz)))
	if dist == 0:
		return
	var step_x := float(dx) / dist
	var step_z := float(dz) / dist
	var draw := true
	var seg := 0
	for i in range(dist + 1):
		if draw:
			var px := pa.x + int(step_x * i)
			var py := pa.y + int(step_z * i)
			for ty in range(-thickness + 1, thickness):
				for tx in range(-thickness + 1, thickness):
					_img_set(img, px + tx, py + ty, col)
		seg += 1
		if seg >= dash_len:
			seg = 0
			draw = !draw


func _bresenham(img: Image, pa: Vector2i, pb: Vector2i, col: Color, thickness: int) -> void:
	var dx := absi(pb.x - pa.x)
	var dz := absi(pb.y - pa.y)
	var sx := 1 if pa.x < pb.x else -1
	var sz := 1 if pa.y < pb.y else -1
	var err := dx - dz
	var x := pa.x
	var z := pa.y
	while true:
		for ty in range(-thickness + 1, thickness):
			for tx in range(-thickness + 1, thickness):
				_img_set(img, x + tx, z + ty, col)
		if x == pb.x and z == pb.y:
			break
		var e2 := err * 2
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
