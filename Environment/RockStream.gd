extends Node3D
class_name RockStream

const SUPPORT_SAMPLE_DIRECTIONS := [
	Vector2(1.0, 0.0),
	Vector2(-1.0, 0.0),
	Vector2(0.0, 1.0),
	Vector2(0.0, -1.0),
	Vector2(0.70710678, 0.70710678),
	Vector2(-0.70710678, 0.70710678),
	Vector2(0.70710678, -0.70710678),
	Vector2(-0.70710678, -0.70710678),
	Vector2(0.92387953, 0.38268343),
	Vector2(-0.92387953, 0.38268343),
	Vector2(0.92387953, -0.38268343),
	Vector2(-0.92387953, -0.38268343),
	Vector2(0.38268343, 0.92387953),
	Vector2(-0.38268343, 0.92387953),
	Vector2(0.38268343, -0.92387953),
	Vector2(-0.38268343, -0.92387953),
]

@export var rock_scene_path: String = "res://Models/Rocks/Rock.glb"
@export var radius_m: float = 400.0
@export var cell_size_m: float = 25.0
## Probability [0..1] of a rock appearing in each cell
@export var density_per_cell: float = 0.42
@export var max_instances: int = 2000
@export var min_scale: float = 0.35
@export var max_scale: float = 0.95
@export_group("Distribution")
## Low-frequency mask that clusters rocks instead of spreading them evenly.
@export var detail_mask_frequency: float = 0.0011
@export_range(0.0, 1.0) var detail_mask_strength: float = 0.30
## Keep only the stronger portions of the mask so detail appears in patches.
@export_range(0.0, 1.0) var detail_cluster_threshold: float = 0.42
## Extra placement chance in lower canyon-floor areas.
@export_range(0.0, 1.0) var basin_density_bonus: float = 0.20
## Extra placement chance near gentle broken slopes and cliff bases.
@export_range(0.0, 1.0) var broken_ground_density_bonus: float = 0.18
@export var detail_seed_offset: int = 913

@export_group("Placement")
## Final placement uses the actual terrain collision surface, because the
## rendered stream mesh may be post-processed after get_height() sampling.
@export var snap_to_collision_surface: bool = true
@export var collision_snap_probe_up_m: float = 80.0
@export var collision_snap_probe_down_m: float = 140.0
## Sink rocks slightly into the terrain so tiny sampling/pivot mismatches do not leave them hovering.
@export var embed_depth_fraction_of_height: float = 0.14
## Small constant embed as an extra hedge against visible floating.
@export var embed_depth_m: float = 0.20
## Maximum terrain slope in degrees — steeper faces get no rocks
@export_range(35.0, 85.0, 1.0) var max_slope_deg: float = 55.0
## Only genuinely steep faces are excluded. Ordinary traversable hillsides
## should still receive rocks. Distance samples the local face grade.
@export var slope_sample_m: float = 3.0
## Extra clearance around each rock checked for a nearby steep face.
@export var support_check_margin_m: float = 20.0
## Number of concentric footprint rings used to find nearby cliff faces.
@export var support_check_rings: int = 2
## Limit sampled directions for streaming cost. The first 8 directions cover
## cardinal and diagonal footprint checks.
@export var support_check_direction_count: int = 8
@export var preload_margin_m: float = 100.0
## Minimum cell movement before rebuilding the rock set
@export var cells_threshold: int = 2
@export var seed: int = 12345
@export var population_budget_ms: float = 2.0

var _mmi: MultiMeshInstance3D
var _mm: MultiMesh
var _rock_mesh: Mesh
var _terrain: LowPolyTerrain
var _last_center_cell: Vector2i = Vector2i(1_000_000, 1_000_000)
var _rock_local_min_y: float = 0.0
var _rock_local_height: float = 0.0
var _rock_local_planform_radius: float = 0.5
var _detail_mask: FastNoiseLite
## Deterministic world-grid cell -> Transform3D, or null when that cell has no
## rock. Negative results are retained so empty cells are not resampled.
var _cell_cache: Dictionary = {}
var _last_candidate_evaluation_count: int = 0
var _last_reused_cell_count: int = 0
var _world_offset := Vector3.ZERO
var _pending: Array[Vector2i] = []
var _pending_index := 0
var _snap_pending: Dictionary = {}
var _snap_queue: Array = []
var _snap_index := 0
var _next_snap_msec := 0
var _last_snap_valid := false
var _dirty := false
var _visible_count := 0
var _max_slice_ms := 0.0

func _ready() -> void:
	add_to_group("origin_shifter")
	_mmi = MultiMeshInstance3D.new()
	# Slots may be repacked as cells leave. Static scenery must not interpolate
	# from a different rock's former slot position.
	_mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_mmi)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mmi.multimesh = _mm
	_rock_mesh = _load_mesh_from_scene(rock_scene_path)
	if _rock_mesh == null:
		var fallback := BoxMesh.new()
		fallback.size = Vector3(1.2, 0.7, 1.0)
		_rock_mesh = fallback
	_mm.mesh = _rock_mesh
	_cache_rock_bounds()
	_build_detail_mask()
	# Terrain lookup — find via group set in LowPolyTerrain._ready()
	_terrain = get_tree().get_first_node_in_group("terrain_provider") as LowPolyTerrain
	var grid := get_node_or_null("/root/TerrainNavGrid")
	if grid != null: grid.bake_invalidated.connect(invalidate)

func invalidate() -> void:
	_last_center_cell = Vector2i(1_000_000, 1_000_000)
	_cell_cache.clear()
	_pending.clear()
	_snap_pending.clear()
	_snap_queue.clear()
	_pending_index = 0
	_dirty = true

func apply_origin_shift(offset: Vector3) -> void:
	# The hierarchy moves the MultiMesh with the terrain. Keys, seeds, queued
	# work and local transforms remain in their original frame.
	_world_offset -= offset

func _process(_delta: float) -> void:
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("terrain_provider") as LowPolyTerrain
		if _terrain == null:
			return

	# Track the aircraft or carrier as the streaming center
	var viewport := get_viewport()
	var active_camera := viewport.get_camera_3d() if viewport != null else null
	var focus: Node3D = active_camera
	if focus == null:
		focus = get_tree().get_first_node_in_group("aircraft") as Node3D
	if focus == null:
		focus = get_tree().get_first_node_in_group("carrier") as Node3D
	if focus == null:
		return

	var center := focus.global_position
	if active_camera and is_instance_valid(active_camera):
		var forward := -active_camera.global_basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			center += forward.normalized() * minf(preload_margin_m, radius_m * 0.5)
	var stable_center := center - _world_offset
	var cell := Vector2i(int(floor(stable_center.x / cell_size_m)), int(floor(stable_center.z / cell_size_m)))
	var delta_cells := cell - _last_center_cell
	var profile_started := FrameProfiler.begin("RockStream.population")
	var started := Time.get_ticks_usec()
	if abs(delta_cells.x) >= cells_threshold or abs(delta_cells.y) >= cells_threshold:
		_last_center_cell = cell
		_queue_footprint(center)
	_process_work(started + int(maxf(population_budget_ms, 0.1) * 1000.0))
	_max_slice_ms = maxf(_max_slice_ms, (Time.get_ticks_usec() - started) / 1000.0)
	FrameProfiler.end("RockStream.population", profile_started)

func _rebuild(center: Vector3) -> void:
	# Synchronous fixture/tool entry point. Runtime only uses budgeted work.
	_queue_footprint(center)
	while _pending_index < _pending.size():
		_process_work(Time.get_ticks_usec() + 1000000)

func _queue_footprint(center_world: Vector3) -> void:
	if not is_instance_valid(_terrain) or _rock_mesh == null: return
	var center := center_world - _world_offset
	var radius := radius_m + preload_margin_m
	var cell_radius := int(ceil(radius / cell_size_m))
	var center_cell := Vector2i(int(floor(center.x / cell_size_m)), int(floor(center.z / cell_size_m)))
	var desired: Dictionary = {}
	# Square rings give near-first ordering without a per-transfer sort.
	for ring in range(cell_radius + 1):
		for gx in range(-ring, ring + 1):
			var z_values = range(-ring, ring + 1) if absi(gx) == ring else [-ring, ring]
			for gz in z_values:
				var key := center_cell + Vector2i(gx, gz)
				var point := (Vector2(key) + Vector2.ONE * 0.5) * cell_size_m
				if point.distance_squared_to(Vector2(center.x, center.z)) <= radius * radius:
					desired[key] = true
	for key in _cell_cache.keys():
		if not desired.has(key):
			_cell_cache.erase(key)
			_snap_pending.erase(key)
			_dirty = true
	_pending.clear()
	_pending_index = 0
	_last_candidate_evaluation_count = 0
	_last_reused_cell_count = 0
	for key in desired:
		if _cell_cache.has(key):
			_last_reused_cell_count += 1
		else:
			_pending.append(key)
	# Old retry entries are validated against _snap_pending when processed.

func _process_work(deadline: int) -> void:
	while _pending_index < _pending.size() and Time.get_ticks_usec() < deadline:
		var key := _pending[_pending_index]
		_pending_index += 1
		var value: Variant = _evaluate_rock_cell(key)
		_cell_cache[key] = null if _snap_pending.has(key) else value
		_last_candidate_evaluation_count += 1
		_dirty = _dirty or value is Transform3D
	if _snap_index >= _snap_queue.size() and Time.get_ticks_msec() >= _next_snap_msec:
		_snap_queue = _snap_pending.keys()
		_snap_index = 0
		_next_snap_msec = Time.get_ticks_msec() + 250
	while _snap_index < _snap_queue.size() and Time.get_ticks_usec() < deadline:
		var key: Vector2i = _snap_queue[_snap_index]
		_snap_index += 1
		if not _snap_pending.has(key): continue
		var candidate: Transform3D = _snap_pending[key]
		var point := to_global(candidate.origin)
		if _terrain.use_streaming and not _terrain.is_chunk_loaded_at_world_position(point): continue
		var embed := embed_depth_m + _rock_local_height * candidate.basis.get_scale().y * embed_depth_fraction_of_height
		var fallback := point.y + _rock_local_min_y * candidate.basis.get_scale().y + embed
		var height := _get_collision_surface_height(point.x, point.z, fallback)
		if not _last_snap_valid: continue
		candidate.origin.y += height - fallback
		_cell_cache[key] = candidate
		_snap_pending.erase(key)
		_dirty = true
	if _dirty: _upload_instances()

func _upload_instances() -> void:
	if _mm.instance_count != maxi(max_instances, 1):
		_mm.instance_count = maxi(max_instances, 1)
	_visible_count = 0
	for value in _cell_cache.values():
		if value is Transform3D:
			if _visible_count >= max_instances: break
			_mm.set_instance_transform(_visible_count, value)
			_visible_count += 1
	_mm.visible_instance_count = _visible_count
	_dirty = false

func _evaluate_rock_cell(cell_coord: Vector2i) -> Variant:
	var world_x: float = float(cell_coord.x) * cell_size_m + cell_size_m * 0.5
	var world_z: float = float(cell_coord.y) * cell_size_m + cell_size_m * 0.5
	var rng := RandomNumberGenerator.new()
	# Keep the legacy seed calculation so caching does not reshuffle the
	# established rock layout, especially in negative world coordinates.
	rng.seed = _hash2i(int(world_x / cell_size_m), int(world_z / cell_size_m)) ^ seed
	var px: float = world_x + rng.randf_range(-cell_size_m * 0.45, cell_size_m * 0.45)
	var pz: float = world_z + rng.randf_range(-cell_size_m * 0.45, cell_size_m * 0.45)
	px += _world_offset.x
	pz += _world_offset.z
	var yaw := rng.randf() * TAU
	var rock_scale := rng.randf_range(min_scale, max_scale)
	var height: float = _terrain.get_height(Vector3(px, 0.0, pz))
	if is_nan(height):
		return null
	var hx_pos: float = _terrain.get_height(Vector3(px + slope_sample_m, 0.0, pz))
	var hx_neg: float = _terrain.get_height(Vector3(px - slope_sample_m, 0.0, pz))
	var hz_pos: float = _terrain.get_height(Vector3(px, 0.0, pz + slope_sample_m))
	var hz_neg: float = _terrain.get_height(Vector3(px, 0.0, pz - slope_sample_m))
	if is_nan(hx_pos) or is_nan(hx_neg) or is_nan(hz_pos) or is_nan(hz_neg):
		return null
	var slope_x: float = absf(hx_pos - hx_neg) / maxf(slope_sample_m * 2.0, 0.001)
	var slope_z: float = absf(hz_pos - hz_neg) / maxf(slope_sample_m * 2.0, 0.001)
	var slope_amount: float = maxf(slope_x, slope_z)
	if slope_amount > tan(deg_to_rad(max_slope_deg)):
		return null
	if rng.randf() > _terrain_detail_density(px, pz, height, slope_amount):
		return null
	if not _has_stable_terrain_support(height, px, pz, rock_scale):
		return null
	var placement_height: float = _get_collision_surface_height(px, pz, height)
	var basis := Basis().rotated(Vector3.UP, yaw).scaled(Vector3(rock_scale, rock_scale, rock_scale))
	var embed: float = embed_depth_m + _rock_local_height * rock_scale * embed_depth_fraction_of_height
	var rock_y: float = placement_height - _rock_local_min_y * rock_scale - embed
	var local_pos := Vector3(px, rock_y, pz) - global_position
	var candidate := Transform3D(basis, local_pos)
	if snap_to_collision_surface and not _last_snap_valid:
		_snap_pending[cell_coord] = candidate
	return candidate


func get_streaming_diagnostics() -> Dictionary:
	return {
		"cached_cells": _cell_cache.size(),
		"evaluated_cells": _last_candidate_evaluation_count,
		"reused_cells": _last_reused_cell_count,
		"rock_instances": _visible_count,
		"pending_cells": _pending.size() - _pending_index,
		"pending_collision": _snap_pending.size(),
		"max_slice_ms": _max_slice_ms,
	}


func _hash2i(x: int, y: int) -> int:
	var n := int(x) * 374761393 + int(y) * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return n ^ (n >> 16)

func _build_detail_mask() -> void:
	_detail_mask = FastNoiseLite.new()
	_detail_mask.seed = seed + detail_seed_offset
	_detail_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_mask.frequency = maxf(detail_mask_frequency, 0.000001)
	_detail_mask.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail_mask.fractal_octaves = 3
	_detail_mask.fractal_lacunarity = 2.0
	_detail_mask.fractal_gain = 0.5

func _terrain_detail_density(px: float, pz: float, h: float, slope_amount: float) -> float:
	var mask_t: float = 1.0
	if _detail_mask != null:
		var raw: float = clampf(_detail_mask.get_noise_2d(px - _world_offset.x, pz - _world_offset.z) * 0.5 + 0.5, 0.0, 1.0)
		var clustered: float = _smoothstep(detail_cluster_threshold, 1.0, raw)
		mask_t = lerpf(1.0 - detail_mask_strength, 1.0 + detail_mask_strength, clustered)

	var basin_t: float = 0.0
	if _terrain != null:
		var floor_y: float = (_terrain.base_height_offset_m
			+ _terrain.plateau_height_m - _terrain.canyon_max_depth_m
			+ _terrain.global_position.y)
		var top_y: float = (_terrain.base_height_offset_m
			+ _terrain.plateau_height_m
			+ _terrain.plateau_surface_amplitude_m * 0.5
			+ _terrain.global_position.y)
		var height_t: float = clampf((h - floor_y) / maxf(top_y - floor_y, 1.0), 0.0, 1.0)
		basin_t = _smoothstep(0.78, 1.0, 1.0 - height_t)

	var slope_t: float = _smoothstep(0.04, 0.28, slope_amount) * (1.0 - _smoothstep(0.38, 0.75, slope_amount))
	var density: float = density_per_cell * mask_t
	density += basin_t * basin_density_bonus
	density += slope_t * broken_ground_density_bonus
	return clampf(density, 0.0, 0.95)

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / maxf(edge1 - edge0, 0.00001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _get_collision_surface_height(px: float, pz: float, fallback_h: float) -> float:
	_last_snap_valid = not snap_to_collision_surface
	if not snap_to_collision_surface:
		return fallback_h
	var world := get_world_3d()
	if world == null:
		return fallback_h
	var from := Vector3(px, fallback_h + maxf(collision_snap_probe_up_m, 1.0), pz)
	var to := Vector3(px, fallback_h - maxf(collision_snap_probe_down_m, 1.0), pz)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 0xFFFFFFFF
	var hit: Dictionary = world.direct_space_state.intersect_ray(params)
	if not hit or not hit.has("position"):
		return fallback_h
	var body = hit.get("collider")
	if body is Node:
		var body_node := body as Node
		if body_node.is_in_group("terrain") or body_node.is_in_group("ground") or "terrain" in body_node.name.to_lower():
			_last_snap_valid = true
			return float(hit.position.y)
	return fallback_h

func _has_stable_terrain_support(center_h: float, px: float, pz: float, rock_scale: float) -> bool:
	if _terrain == null:
		return false
	var rock_radius: float = _rock_local_planform_radius * rock_scale
	var outer_radius: float = rock_radius + support_check_margin_m
	var ring_count: int = maxi(support_check_rings, 1)
	var inner_radius: float = maxf(minf(rock_radius, slope_sample_m), 1.0)
	outer_radius = maxf(outer_radius, inner_radius)
	var max_grade: float = tan(deg_to_rad(max_slope_deg))
	for ring_idx in range(ring_count):
		var t: float = 1.0 if ring_count == 1 else float(ring_idx) / float(ring_count - 1)
		var sample_radius: float = lerpf(inner_radius, outer_radius, t)
		var direction_count: int = clampi(support_check_direction_count, 4, SUPPORT_SAMPLE_DIRECTIONS.size())
		var ring_min_h: float = center_h
		var ring_max_h: float = center_h
		for dir_idx in range(direction_count):
			var dir: Vector2 = SUPPORT_SAMPLE_DIRECTIONS[dir_idx]
			var sample_h: float = _terrain.get_height(Vector3(
				px + dir.x * sample_radius,
				0.0,
				pz + dir.y * sample_radius
			))
			if is_nan(sample_h):
				return false
			ring_min_h = minf(ring_min_h, sample_h)
			ring_max_h = maxf(ring_max_h, sample_h)
			# Reject only when the center-to-sample grade is cliff-like. Absolute
			# height change is intentionally allowed on ordinary long slopes.
			if absf(sample_h - center_h) / maxf(sample_radius, 0.001) > max_grade:
				return false
		# Catch a steep face crossing the sampled footprint even when the
		# candidate happens to sit near the middle of that transition.
		if (ring_max_h - ring_min_h) / maxf(sample_radius * 2.0, 0.001) > max_grade:
			return false
	return true

func _load_mesh_from_scene(path: String) -> Mesh:
	var res := ResourceLoader.load(path)
	if res == null:
		return null
	if res is PackedScene:
		var inst := (res as PackedScene).instantiate()
		var mi := _find_mesh_instance(inst)
		var mesh: Mesh = mi.mesh if mi != null else null
		inst.free()
		return mesh
	elif res is Mesh:
		return res as Mesh
	return null

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null

func _cache_rock_bounds() -> void:
	if _rock_mesh == null:
		_rock_local_min_y = 0.0
		_rock_local_height = 1.0
		return
	var aabb: AABB = _rock_mesh.get_aabb()
	_rock_local_min_y = aabb.position.y
	_rock_local_height = maxf(aabb.size.y, 0.001)
	_rock_local_planform_radius = maxf(Vector2(aabb.size.x, aabb.size.z).length() * 0.5, 0.001)
