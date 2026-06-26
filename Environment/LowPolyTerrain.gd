extends Node3D
class_name LowPolyTerrain

@export_group("Size")
@export var quads_x: int = 2778
@export var quads_z: int = 2778
@export var cell_size_m: float = 12.0
@export var seed: int = 1337

@export_group("Shape")
## Baseline plateau elevation — most of the terrain is at this height
@export var plateau_height_m: float = 300.0
## Maximum canyon depth carved below the plateau
@export var canyon_max_depth_m: float = 300.0
## Fraction of ridge-noise range that becomes flat canyon floor (wider = broader floors)
@export var canyon_floor_width: float = 0.15
## Width of the cliff transition zone (smaller = more vertical walls)
@export var canyon_cliff_width: float = 0.09
## Cliff wall steepness exponent — higher values approach true vertical cliffs
@export var canyon_cliff_power: float = 12.0
## Spatial frequency of the main canyon network
@export var main_canyon_frequency: float = 0.00018
## Spatial frequency of tributary canyons (should be 1.5–2× main)
@export var tributary_frequency: float = 0.00024
## Domain warp amplitude for organic canyon meandering
@export var canyon_warp_amplitude_m: float = 220.0
## Tributary canyons are this fraction as deep as the main canyons
@export var tributary_depth_fraction: float = 0.60
## Amplitude of surface variation on the plateau top
@export var plateau_surface_amplitude_m: float = 60.0
## Frequency of plateau surface variation
@export var plateau_surface_frequency: float = 0.0014
## Very low-frequency relief added to otherwise flat surfaces such as plateau tops
## and broad canyon floors so they read as shallow terrain instead of perfect planes.
@export var flat_surface_undulation_amplitude_m: float = 12.0
## Frequency of the broad flat-surface undulation layer.
@export var flat_surface_undulation_frequency: float = 0.00032
## Smaller-scale detail on broad flat areas so they do not read as ironed flat.
@export var flat_surface_detail_amplitude_m: float = 4.5
## Frequency of the subtle flat-surface detail layer.
@export var flat_surface_detail_frequency: float = 0.0011
## Height of visible strata bands in canyon walls
@export var strata_step_m: float = 40.0
## How strongly strata layers snap (0 = off, 1 = fully snapped)
@export var strata_strength: float = 0.28
## Fraction of each strata band that is flat shelf; remainder is a gentle slope to the next level
@export var strata_shelf_fraction: float = 0.22
## How much the strata band height varies across the map (metres)
@export var strata_height_variation_m: float = 25.0
## Global vertical offset applied to the whole terrain
@export var base_height_offset_m: float = 0.0

@export_group("Color")
## Dark reddish-brown at the canyon floor
@export var canyon_floor_color: Color = Color(0.30, 0.17, 0.09)
## Deep red sandstone on lower canyon walls
@export var canyon_wall_color: Color = Color(0.72, 0.34, 0.17)
## Orange-tan on upper canyon walls
@export var canyon_upper_color: Color = Color(0.86, 0.57, 0.34)
## Cream/tan on the flat plateau surface
@export var plateau_color: Color = Color(0.88, 0.80, 0.42)
## Per-face random micro-tint (salt & pepper, keep small)
@export var color_noise_strength: float = 0.05
## Spatial frequency of smooth color gradient patches
@export var color_patch_frequency: float = 0.0012
## Strength of the smooth color gradient (0 = off)
@export var color_patch_strength: float = 0.20
## Grey applied to steep cliff faces
@export var steep_slope_color: Color = Color(0.28, 0.27, 0.25)
## Blend strength toward grey on steep faces (0 = off, 1 = fully grey)
@export var steep_slope_strength: float = 1.0
## n.y threshold where grey begins (n.y=1 flat, n.y=0 vertical); higher = grey starts on shallower slopes
@export var steep_slope_min_ny: float = 0.88
## Width of the sand→grey transition in n.y units (smaller = sharper border, e.g. 0.05)
@export var steep_slope_band: float = 0.08

@export_group("Color Variation")
## Broad rusty ground patches on flat terrain.
@export var ground_patch_color: Color = Color(0.58, 0.31, 0.17)
@export var ground_patch_frequency: float = 0.00032
@export_range(0.0, 1.0) var ground_patch_strength: float = 0.12
## Pale dust flats that break up the orange floor without becoming noisy.
@export var pale_dust_color: Color = Color(0.89, 0.66, 0.42)
@export var pale_dust_frequency: float = 0.00046
@export_range(0.0, 1.0) var pale_dust_strength: float = 0.13
## Darker sediment in low basins and canyon floors.
@export var basin_dark_color: Color = Color(0.24, 0.12, 0.07)
@export var basin_dark_frequency: float = 0.00038
@export_range(0.0, 1.0) var basin_dark_strength: float = 0.16
## Subtle cooler tone for shadowed/distant-looking recesses.
@export var cool_shadow_color: Color = Color(0.34, 0.30, 0.27)
@export_range(0.0, 1.0) var cool_shadow_strength: float = 0.08
## Extra horizontal tinting on canyon walls, separate from geometric strata.
@export var cliff_band_dark_color: Color = Color(0.43, 0.27, 0.18)
@export_range(0.0, 1.0) var cliff_band_strength: float = 0.14
## Vertical erosion streaks on steep faces.
@export var cliff_streak_color: Color = Color(0.22, 0.15, 0.12)
@export var cliff_streak_frequency: float = 0.00075
@export_range(0.0, 1.0) var cliff_streak_strength: float = 0.15
## Deterministic per-triangle polygonal surface texture. Keep low.
@export_range(0.0, 0.2) var face_texture_strength: float = 0.035

@export_group("Output")
@export var generate_on_ready: bool = true
@export var generate_collision: bool = true
@export var double_sided: bool = true

@export_group("Quantization")
## Snap heights to multiples of this value (0 = off).
## With cell_size_m=12: 6 m gives 0°/26.6°/45° slope steps.
@export var quant_step_m: float = 3.0
## Max height diff between 4-adjacent nodes enforced by relaxation.
## 12 m = 45° cap per cell, 6 m = 26.6° cap. 0 = no limit.
@export var quant_max_step_m: float = 0.0
## Relaxation passes per chunk (more = accurate seams, slower build).
@export var quant_relax_passes: int = 0

@export_group("Cliff Shape")
## Straighten steep cliff walls along their contour to reduce rounded, organic billowing.
@export var cliff_planform_straighten_strength: float = 0.52
## Number of contour-straightening passes applied to steep walls.
@export var cliff_planform_passes: int = 3
## Distance sampled along the local wall tangent each pass.
@export var cliff_planform_sample_distance_cells: float = 1.7
## Minimum local slope (rise/run) before cliff straightening starts to apply.
@export var cliff_planform_min_slope_rise_over_run: float = 0.95
## Light tangent-direction cleanup after quantization to reduce repeating cliff washboards.
@export var cliff_washboard_suppress_strength: float = 0.24
## Number of washboard-suppression passes.
@export var cliff_washboard_passes: int = 1
## Tangent sample distance for the washboard cleanup pass.
@export var cliff_washboard_sample_distance_cells: float = 0.8
## Low-frequency contour jitter on steep walls to break long smooth artificial curves.
@export var cliff_planform_jitter_strength: float = 0.16
## Maximum contour jitter distance in grid cells.
@export var cliff_planform_jitter_offset_cells: float = 0.65
## Spatial frequency of the cliff contour jitter noise.
@export var cliff_planform_jitter_frequency: float = 0.00016

@export_group("Streaming")
@export var use_streaming: bool = true
@export var chunk_quads_x: int = 28
@export var chunk_quads_z: int = 28
@export var load_radius_chunks: int = 10
@export var unload_margin_chunks: int = 1
@export var stream_target_path: NodePath
@export var stream_update_interval_s: float = 0.25
@export var max_chunk_builds_per_update: int = 2
@export var stream_preload_ahead_m: float = 1200.0

var _mesh_node: MeshInstance3D
var _body_node: StaticBody3D
var _shape_node: CollisionShape3D
var _chunk_root: Node3D
var _shared_material: StandardMaterial3D
var _noises: Dictionary = {}

var _size_x: int = 0
var _size_z: int = 0
var _span_x: float = 0.0
var _span_z: float = 0.0
var _x0: float = 0.0
var _z0: float = 0.0
var _chunk_count_x: int = 0
var _chunk_count_z: int = 0

var _chunks: Dictionary = {} # key "x:z" -> Node3D
var _pending_builds: Array[Vector2i] = []
var _pending_set: Dictionary = {} # key "x:z" -> true
var _stream_timer: float = 0.0
var _last_center_chunk: Vector2i = Vector2i(-999999, -999999)

# Async chunk building — _build_chunk_arrays runs on WorkerThreadPool, node creation finalizes on main thread
var _async_tasks: Array = []              # [{coord, task_id, holder}]
var _building_set: Dictionary = {}        # chunk_key -> true for in-flight builds
var _discard_on_complete: Dictionary = {} # chunk_key -> true for results to throw away

# Initial load tracking — used by LoadingScreen to show chunk fill progress
var _initial_pending_total: int = 0  # size of the first pending queue, set once

func _ready() -> void:
	if not is_in_group("terrain_provider"):
		add_to_group("terrain_provider")
	if not is_in_group("terrain"):
		add_to_group("terrain")
	_ensure_nodes()
	if generate_on_ready:
		rebuild()
	set_process(use_streaming)

func _process(delta: float) -> void:
	if not use_streaming:
		return
	_stream_timer += delta
	if _stream_timer >= maxf(stream_update_interval_s, 0.01):
		_stream_timer = 0.0
		_update_streaming(false)

func rebuild() -> void:
	_ensure_nodes()
	_refresh_layout()
	_noises = _build_noises()
	_shared_material = _build_material()

	if use_streaming:
		_clear_legacy_mesh()
		_clear_chunks()
		_pending_builds.clear()
		_pending_set.clear()
		_stream_timer = 0.0
		_last_center_chunk = Vector2i(-999999, -999999)
		_update_streaming(true)
		set_process(true)
		return

	_clear_chunks()
	var mesh: ArrayMesh = _build_full_mesh()
	_mesh_node.mesh = mesh
	_mesh_node.material_override = _shared_material
	if generate_collision:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(mesh.get_faces())
		_shape_node.shape = shape
	else:
		_shape_node.shape = null
	set_process(false)

## Returns 0.0..1.0 fraction of the initial chunk fill completed.
## 1.0 once the first visible ring has fully built and all async tasks are done.
func get_chunk_load_fraction() -> float:
	if not use_streaming:
		return 1.0
	if _initial_pending_total <= 0:
		return 1.0 if not _chunks.is_empty() else 0.0
	var remaining := _pending_builds.size() + _async_tasks.size()
	return clampf(1.0 - float(remaining) / float(_initial_pending_total), 0.0, 1.0)

## True once the initial fill burst has completed (no pending or in-flight builds).
func is_initial_load_complete() -> bool:
	if not use_streaming:
		return true
	return _initial_pending_total > 0 and _pending_builds.is_empty() and _async_tasks.is_empty()

func get_height(world_pos: Vector3) -> float:
	if _noises.is_empty():
		_refresh_layout()
		_noises = _build_noises()
	var local: Vector3 = to_local(world_pos)
	if local.x < _x0 or local.x > _x0 + _span_x or local.z < _z0 or local.z > _z0 + _span_z:
		return NAN
	var h: float = _sample_height(local.x, local.z, _noises)
	if quant_step_m > 0.1:
		h = round(h / quant_step_m) * quant_step_m
	return h + global_position.y

func get_surface_color(world_pos: Vector3) -> Color:
	if _noises.is_empty():
		_refresh_layout()
		_noises = _build_noises()
	var local: Vector3 = to_local(world_pos)
	var h: float = _sample_height(local.x, local.z, _noises)
	if quant_step_m > 0.1:
		h = round(h / quant_step_m) * quant_step_m
	var face_center := Vector3(local.x, h, local.z)
	var sample_step := maxf(cell_size_m, 1.0)
	var hx0 := _sample_height(local.x - sample_step, local.z, _noises)
	var hx1 := _sample_height(local.x + sample_step, local.z, _noises)
	var hz0 := _sample_height(local.x, local.z - sample_step, _noises)
	var hz1 := _sample_height(local.x, local.z + sample_step, _noises)
	if quant_step_m > 0.1:
		hx0 = round(hx0 / quant_step_m) * quant_step_m
		hx1 = round(hx1 / quant_step_m) * quant_step_m
		hz0 = round(hz0 / quant_step_m) * quant_step_m
		hz1 = round(hz1 / quant_step_m) * quant_step_m
	var dx := Vector3(sample_step * 2.0, hx1 - hx0, 0.0)
	var dz := Vector3(0.0, hz1 - hz0, sample_step * 2.0)
	var normal := dz.cross(dx).normalized()
	if normal.y < 0.0:
		normal = -normal
	return _surface_color_for_sample(face_center, normal, _terrain_color_sample_id(local.x, local.z))

func _refresh_layout() -> void:
	_size_x = max(quads_x, 2)
	_size_z = max(quads_z, 2)
	_span_x = float(_size_x) * cell_size_m
	_span_z = float(_size_z) * cell_size_m
	_x0 = -_span_x * 0.5
	_z0 = -_span_z * 0.5
	var qx: int = max(chunk_quads_x, 1)
	var qz: int = max(chunk_quads_z, 1)
	_chunk_count_x = int(ceil(float(_size_x) / float(qx)))
	_chunk_count_z = int(ceil(float(_size_z) / float(qz)))

func _ensure_nodes() -> void:
	_mesh_node = get_node_or_null("TerrainMesh") as MeshInstance3D
	if not _mesh_node:
		_mesh_node = MeshInstance3D.new()
		_mesh_node.name = "TerrainMesh"
		add_child(_mesh_node)
		_set_owner_recursive(_mesh_node)

	_body_node = get_node_or_null("TerrainBody") as StaticBody3D
	if not _body_node:
		_body_node = StaticBody3D.new()
		_body_node.name = "TerrainBody"
		add_child(_body_node)
		_set_owner_recursive(_body_node)

	_shape_node = get_node_or_null("TerrainBody/CollisionShape3D") as CollisionShape3D
	if not _shape_node:
		_shape_node = CollisionShape3D.new()
		_shape_node.name = "CollisionShape3D"
		_body_node.add_child(_shape_node)
		_set_owner_recursive(_shape_node)

	_chunk_root = get_node_or_null("TerrainChunks") as Node3D
	if not _chunk_root:
		_chunk_root = Node3D.new()
		_chunk_root.name = "TerrainChunks"
		add_child(_chunk_root)
		_set_owner_recursive(_chunk_root)

func _clear_legacy_mesh() -> void:
	if _mesh_node:
		_mesh_node.mesh = null
	if _shape_node:
		_shape_node.shape = null

func _clear_chunks() -> void:
	# Wait for all in-flight worker tasks before clearing — prevents use-after-free on _noises.
	for task in _async_tasks:
		WorkerThreadPool.wait_for_task_completion(task.task_id)
	_async_tasks.clear()
	_building_set.clear()
	_discard_on_complete.clear()
	if not _chunk_root:
		return
	for child in _chunk_root.get_children():
		child.queue_free()
	_chunks.clear()
	_pending_builds.clear()
	_pending_set.clear()

func _update_streaming(force_refresh: bool) -> void:
	var center_local: Vector3 = _get_stream_center_local()
	var center_chunk: Vector2i = _world_to_chunk(center_local.x, center_local.z)
	var center_changed: bool = force_refresh or center_chunk != _last_center_chunk
	if center_changed:
		_refresh_chunk_targets(center_chunk)
		_last_center_chunk = center_chunk
	_build_pending_chunks()

func _refresh_chunk_targets(center_chunk: Vector2i) -> void:
	var candidates: Array[Dictionary] = []
	var radius: int = max(load_radius_chunks, 0)
	var keep_radius: int = radius + max(unload_margin_chunks, 0)

	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cx: int = center_chunk.x + dx
			var cz: int = center_chunk.y + dz
			if not _is_chunk_in_bounds(cx, cz):
				continue
			var key := _chunk_key(cx, cz)
			if _chunks.has(key) or _pending_set.has(key) or _building_set.has(key):
				continue
			var d2: int = dx * dx + dz * dz
			candidates.append({"coord": Vector2i(cx, cz), "d2": d2})

	for key in _chunks.keys():
		var c: Vector2i = _key_to_chunk(str(key))
		if abs(c.x - center_chunk.x) > keep_radius or abs(c.y - center_chunk.y) > keep_radius:
			_remove_chunk(str(key))

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["d2"]) < int(b["d2"])
	)
	for item in candidates:
		var coord: Vector2i = item["coord"]
		var key := _chunk_key(coord.x, coord.y)
		_pending_builds.push_back(coord)
		_pending_set[key] = true

func _build_pending_chunks() -> void:
	_finalize_ready_tasks()
	# Use a higher budget during initial fill (many pending chunks) to reduce pop-in delay.
	# Once steady-state, honour max_chunk_builds_per_update to avoid hitches.
	# The budget now controls how many async tasks we launch per update, not how many we build.
	var initial_fill := _pending_builds.size() > load_radius_chunks * 2
	if initial_fill and _initial_pending_total == 0:
		_initial_pending_total = _pending_builds.size()
	var budget: int = max(max_chunk_builds_per_update, 1) if not initial_fill else 16
	while budget > 0 and not _pending_builds.is_empty():
		var coord: Vector2i = _pending_builds.pop_front()
		var key := _chunk_key(coord.x, coord.y)
		_pending_set.erase(key)
		if _chunks.has(key) or _building_set.has(key):
			budget -= 1
			continue
		_building_set[key] = true
		_launch_chunk_task(coord)
		budget -= 1

func _launch_chunk_task(coord: Vector2i) -> void:
	var qx_step: int = max(chunk_quads_x, 1)
	var qz_step: int = max(chunk_quads_z, 1)
	var qx0: int = coord.x * qx_step
	var qz0: int = coord.y * qz_step
	var qx1: int = min(qx0 + qx_step, _size_x)
	var qz1: int = min(qz0 + qz_step, _size_z)
	if qx0 >= _size_x or qz0 >= _size_z:
		_building_set.erase(_chunk_key(coord.x, coord.y))
		return
	var holder := {"arrays": null}
	var task_id := WorkerThreadPool.add_task(func():
		holder["arrays"] = _build_chunk_arrays(qx0, qx1, qz0, qz1)
	)
	_async_tasks.append({coord = coord, task_id = task_id, holder = holder})

func _finalize_ready_tasks() -> void:
	var i := _async_tasks.size() - 1
	while i >= 0:
		var task: Dictionary = _async_tasks[i]
		if WorkerThreadPool.is_task_completed(task.task_id):
			WorkerThreadPool.wait_for_task_completion(task.task_id)
			_async_tasks.remove_at(i)
			var coord: Vector2i = task.coord
			var key := _chunk_key(coord.x, coord.y)
			_building_set.erase(key)
			if _discard_on_complete.erase(key):
				i -= 1
				continue
			if not _chunks.has(key):
				var arrays: Array = task.holder["arrays"]
				if arrays != null and not (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
					var chunk := _make_chunk_node(coord, arrays)
					if chunk:
						_chunk_root.add_child(chunk)
						_set_owner_recursive(chunk)
						_chunks[key] = chunk
		i -= 1

func _make_chunk_node(coord: Vector2i, arrays: Array) -> Node3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [coord.x, coord.y]
	root.set_meta("chunk_coord", coord)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = _shared_material
	root.add_child(mi)

	if generate_collision:
		var body := StaticBody3D.new()
		body.name = "Body"
		body.add_to_group("terrain")
		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(mesh.get_faces())
		shape_node.shape = shape
		body.add_child(shape_node)
		root.add_child(body)

	return root

func _build_chunk(chunk_x: int, chunk_z: int) -> Node3D:
	var qx_step: int = max(chunk_quads_x, 1)
	var qz_step: int = max(chunk_quads_z, 1)
	var qx0: int = chunk_x * qx_step
	var qz0: int = chunk_z * qz_step
	var qx1: int = min(qx0 + qx_step, _size_x)
	var qz1: int = min(qz0 + qz_step, _size_z)
	if qx0 >= _size_x or qz0 >= _size_z:
		return null

	var arrays: Array = _build_chunk_arrays(qx0, qx1, qz0, qz1)
	if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return null

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [chunk_x, chunk_z]
	root.set_meta("chunk_coord", Vector2i(chunk_x, chunk_z))

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = _shared_material
	root.add_child(mi)

	if generate_collision:
		var body := StaticBody3D.new()
		body.name = "Body"
		body.add_to_group("terrain")
		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(mesh.get_faces())
		shape_node.shape = shape
		body.add_child(shape_node)
		root.add_child(body)

	return root

func _build_chunk_arrays(qx0: int, qx1: int, qz0: int, qz1: int) -> Array:
	var vertices := PackedVector3Array()
	var normals  := PackedVector3Array()
	var colors   := PackedColorArray()

	# --- Sampled height grid with padding for seamless post-processing ---
	# Padding covers any grid-space post-process passes (cliff straightening / step relaxation)
	# so chunk edges evaluate from the same neighborhood regardless of which chunk built them.
	var use_quant: bool = quant_step_m > 0.1
	var use_cliff_planform: bool = (
		cliff_planform_straighten_strength > 0.001
		and cliff_planform_passes > 0
		and cliff_planform_sample_distance_cells > 0.05
	)
	var use_cliff_planform_jitter: bool = (
		cliff_planform_jitter_strength > 0.001
		and cliff_planform_jitter_offset_cells > 0.05
	)
	var use_cliff_washboard: bool = (
		cliff_washboard_suppress_strength > 0.001
		and cliff_washboard_passes > 0
		and cliff_washboard_sample_distance_cells > 0.05
	)
	var hgrid     := PackedFloat32Array()
	var px0: int  = 0
	var pz0: int  = 0
	var pcols: int = 0

	if use_quant or use_cliff_planform or use_cliff_planform_jitter or use_cliff_washboard:
		var cliff_planform_pad: int = int(ceil(maxf(cliff_planform_sample_distance_cells, 0.0) * float(max(cliff_planform_passes, 0)))) if use_cliff_planform else 0
		var cliff_jitter_pad: int = int(ceil(maxf(cliff_planform_jitter_offset_cells, 0.0))) if use_cliff_planform_jitter else 0
		var cliff_washboard_pad: int = int(ceil(maxf(cliff_washboard_sample_distance_cells, 0.0) * float(max(cliff_washboard_passes, 0)))) if use_cliff_washboard else 0
		var P: int  = max(max(max(max(quant_relax_passes, 0), cliff_planform_pad), cliff_jitter_pad), cliff_washboard_pad)
		px0          = max(qx0 - P, 0)
		var px1: int = min(qx1 + P, _size_x)
		pz0          = max(qz0 - P, 0)
		var pz1: int = min(qz1 + P, _size_z)
		pcols        = px1 - px0 + 1
		var prows: int = pz1 - pz0 + 1
		hgrid.resize(pcols * prows)

		for lz in range(prows):
			for lx in range(pcols):
				var wx: float = _x0 + float(px0 + lx) * cell_size_m
				var wz: float = _z0 + float(pz0 + lz) * cell_size_m
				hgrid[lz * pcols + lx] = _sample_height(wx, wz, _noises)

		if use_cliff_planform:
			_straighten_cliff_planform(hgrid, pcols, prows)

		if use_cliff_planform_jitter:
			_jitter_cliff_planform(hgrid, pcols, prows, px0, pz0, _noises)

		if use_quant:
			for i in range(hgrid.size()):
				hgrid[i] = round(hgrid[i] / quant_step_m) * quant_step_m

		if quant_relax_passes > 0 and quant_max_step_m > 0.0:
			_relax_heights(hgrid, pcols, prows)

		if use_cliff_washboard:
			_soften_cliff_washboard(hgrid, pcols, prows)

	for z in range(qz0, qz1):
		for x in range(qx0, qx1):
			var x_a: float = _x0 + float(x) * cell_size_m
			var x_b: float = x_a + cell_size_m
			var z_a: float = _z0 + float(z) * cell_size_m
			var z_b: float = z_a + cell_size_m

			var h00: float
			var h10: float
			var h01: float
			var h11: float
			if use_quant or use_cliff_planform:
				var lx: int = x - px0
				var lz: int = z - pz0
				h00 = hgrid[lz       * pcols + lx    ]
				h10 = hgrid[lz       * pcols + lx + 1]
				h01 = hgrid[(lz + 1) * pcols + lx    ]
				h11 = hgrid[(lz + 1) * pcols + lx + 1]
			else:
				h00 = _sample_height(x_a, z_a, _noises)
				h10 = _sample_height(x_b, z_a, _noises)
				h01 = _sample_height(x_a, z_b, _noises)
				h11 = _sample_height(x_b, z_b, _noises)

			var v00 := Vector3(x_a, h00, z_a)
			var v10 := Vector3(x_b, h10, z_a)
			var v01 := Vector3(x_a, h01, z_b)
			var v11 := Vector3(x_b, h11, z_b)

			var cell_id: int = z * _size_x + x
			if _should_use_alternate_diagonal(v00, v10, v01, v11, cell_id):
				_append_face(v00, v10, v01, cell_id * 2,     vertices, normals, colors)
				_append_face(v10, v11, v01, cell_id * 2 + 1, vertices, normals, colors)
			else:
				_append_face(v00, v10, v11, cell_id * 2,     vertices, normals, colors)
				_append_face(v00, v11, v01, cell_id * 2 + 1, vertices, normals, colors)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR]  = colors
	return arrays

func _build_full_mesh() -> ArrayMesh:
	var arrays: Array = _build_chunk_arrays(0, _size_x, 0, _size_z)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _append_face(
		v0: Vector3,
		v1: Vector3,
		v2: Vector3,
		tri_id: int,
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		colors: PackedColorArray) -> void:
	var n: Vector3 = _face_up_normal(v0, v1, v2)

	var face_center: Vector3 = (v0 + v1 + v2) / 3.0
	var c := _surface_color_for_sample(face_center, n, tri_id)

	vertices.push_back(v0)
	vertices.push_back(v1)
	vertices.push_back(v2)
	normals.push_back(n)
	normals.push_back(n)
	normals.push_back(n)
	colors.push_back(c)
	colors.push_back(c)
	colors.push_back(c)

func _surface_color_for_sample(face_center: Vector3, n: Vector3, sample_id: int) -> Color:
	# Altitude-based coloring — geological strata like Colorado Plateau / Grand Canyon.
	# Four color bands from canyon floor up to plateau top.
	var face_y: float = face_center.y
	var floor_y: float = base_height_offset_m + (plateau_height_m - canyon_max_depth_m)
	var top_y: float = base_height_offset_m + plateau_height_m + plateau_surface_amplitude_m * 0.5
	var height_t: float = clampf((face_y - floor_y) / maxf(top_y - floor_y, 1.0), 0.0, 1.0)

	var base_color: Color
	if height_t < 0.25:
		# Canyon floor → lower wall (dark brown to deep red)
		base_color = canyon_floor_color.lerp(canyon_wall_color, height_t / 0.25)
	elif height_t < 0.72:
		# Lower wall → upper wall (deep red to orange-tan)
		base_color = canyon_wall_color.lerp(canyon_upper_color, (height_t - 0.25) / 0.47)
	else:
		# Upper wall → plateau (orange-tan to cream)
		base_color = canyon_upper_color.lerp(plateau_color, (height_t - 0.72) / 0.28)

	# Layer broad procedural color masks before the final steep-face and tint pass.
	var flat_t: float = _smoothstep(0.74, 0.98, n.y)
	var cliff_t: float = _smoothstep(0.18, 0.82, 1.0 - n.y)
	var floor_t: float = _smoothstep(0.72, 1.0, 1.0 - height_t) * flat_t
	var plateau_t: float = _smoothstep(0.64, 1.0, height_t) * flat_t
	var wall_t: float = _smoothstep(0.20, 0.86, 1.0 - n.y) * _smoothstep(0.08, 0.55, height_t) * (1.0 - _smoothstep(0.64, 0.96, height_t))

	var ground_patch_noise := _noises.get("ground_patch") as FastNoiseLite
	if ground_patch_noise != null:
		var patch_t: float = _smoothstep(0.52, 0.86, _noise01(ground_patch_noise, face_center.x, face_center.z)) * flat_t
		base_color = base_color.lerp(ground_patch_color, patch_t * ground_patch_strength)

	var pale_dust_noise := _noises.get("pale_dust") as FastNoiseLite
	if pale_dust_noise != null:
		var dust_t: float = _smoothstep(0.54, 0.88, _noise01(pale_dust_noise, face_center.x, face_center.z)) * maxf(plateau_t, flat_t * 0.35)
		base_color = base_color.lerp(pale_dust_color, dust_t * pale_dust_strength)

	var basin_dark_noise := _noises.get("basin_dark") as FastNoiseLite
	if basin_dark_noise != null:
		var basin_t: float = _smoothstep(0.52, 0.88, _noise01(basin_dark_noise, face_center.x, face_center.z)) * floor_t
		base_color = base_color.lerp(basin_dark_color, basin_t * basin_dark_strength)

	if cool_shadow_strength > 0.0:
		var recess_t: float = clampf(floor_t * 0.45 + wall_t * 0.35 + cliff_t * 0.20, 0.0, 1.0)
		base_color = base_color.lerp(cool_shadow_color, recess_t * cool_shadow_strength)

	if cliff_band_strength > 0.0 and wall_t > 0.0:
		var local_step: float = maxf(strata_step_m, 1.0)
		var band_phase: float = fposmod(face_y - floor_y, local_step) / local_step
		var band_t: float = (1.0 - _smoothstep(0.20, 0.62, band_phase)) * wall_t
		base_color = base_color.lerp(cliff_band_dark_color, band_t * cliff_band_strength)

	var cliff_streak_noise := _noises.get("cliff_streak") as FastNoiseLite
	if cliff_streak_noise != null:
		var streak_x: float = face_center.x * 0.35 + face_center.z * 0.08
		var streak_y: float = face_y * 2.4
		var streak_t: float = _smoothstep(0.58, 0.90, _noise01(cliff_streak_noise, streak_x, streak_y)) * wall_t
		base_color = base_color.lerp(cliff_streak_color, streak_t * cliff_streak_strength)

	var steep_t: float = clampf((steep_slope_min_ny - n.y) / maxf(steep_slope_band, 0.001), 0.0, 1.0) * steep_slope_strength
	var steep_mask: float = 1.0
	if ground_patch_noise != null:
		steep_mask = lerpf(0.62, 1.0, _noise01(ground_patch_noise, face_center.x + 1700.0, face_center.z - 900.0))
	base_color = base_color.lerp(steep_slope_color, steep_t * steep_mask)

	# Large-scale colour patches: low-frequency noise sampled at the world-space face
	# centre shifts the base brightness by ±color_patch_strength. RGB only, alpha
	# untouched.
	var color_var_noise := _noises.get("color_var") as FastNoiseLite
	if color_var_noise != null:
		var patch_noise: float = color_var_noise.get_noise_2d(face_center.x, face_center.z)
		var patch_mult: float = 1.0 + patch_noise * color_patch_strength
		base_color = Color(
			clampf(base_color.r * patch_mult, 0.0, 1.0),
			clampf(base_color.g * patch_mult, 0.0, 1.0),
			clampf(base_color.b * patch_mult, 0.0, 1.0),
			base_color.a
		)

	# Per-face micro-randomness
	var tint_rand: float = _hash01(sample_id * 101 + seed * 17)
	var poly_rand: float = _hash01(sample_id * 389 + seed * 31)
	var poly_strength: float = face_texture_strength * lerpf(0.65, 1.35, clampf(wall_t + floor_t, 0.0, 1.0))
	var tint: float = 1.0 + (tint_rand * 2.0 - 1.0) * color_noise_strength + (poly_rand * 2.0 - 1.0) * poly_strength
	return Color(
		clampf(base_color.r * tint, 0.0, 1.0),
		clampf(base_color.g * tint, 0.0, 1.0),
		clampf(base_color.b * tint, 0.0, 1.0),
		1.0
	)

func _should_use_alternate_diagonal(
		v00: Vector3,
		v10: Vector3,
		v01: Vector3,
		v11: Vector3,
		cell_id: int) -> bool:
	var default_n0: Vector3 = _face_up_normal(v00, v10, v11)
	var default_n1: Vector3 = _face_up_normal(v00, v11, v01)
	var alternate_n0: Vector3 = _face_up_normal(v00, v10, v01)
	var alternate_n1: Vector3 = _face_up_normal(v10, v11, v01)

	var default_alignment: float = default_n0.dot(default_n1)
	var alternate_alignment: float = alternate_n0.dot(alternate_n1)
	if absf(alternate_alignment - default_alignment) <= 0.01:
		# Break near-ties deterministically so broad slopes do not all lean the same way.
		return _hash01(cell_id * 733 + seed * 193) >= 0.5
	return alternate_alignment > default_alignment

func _face_up_normal(v0: Vector3, v1: Vector3, v2: Vector3) -> Vector3:
	var n: Vector3 = (v2 - v0).cross(v1 - v0).normalized()
	if n.y < 0.0:
		n = -n
	return n
	
func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular = 0.05
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK
	return mat

func _build_noises() -> Dictionary:
	# Domain warp: low-frequency, low-octave — gently meanders canyon paths
	var canyon_warp := FastNoiseLite.new()
	canyon_warp.seed = seed + 7
	canyon_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	canyon_warp.frequency = maxf(main_canyon_frequency * 0.45, 0.000005)
	canyon_warp.fractal_type = FastNoiseLite.FRACTAL_FBM
	canyon_warp.fractal_octaves = 2
	canyon_warp.fractal_lacunarity = 2.0
	canyon_warp.fractal_gain = 0.5

	# Main canyon network: smooth simplex so zero-crossings form continuous channel lines
	var main_canyon := FastNoiseLite.new()
	main_canyon.seed = seed + 101
	main_canyon.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	main_canyon.frequency = maxf(main_canyon_frequency, 0.000005)
	main_canyon.fractal_type = FastNoiseLite.FRACTAL_FBM
	main_canyon.fractal_octaves = 3
	main_canyon.fractal_lacunarity = 2.0
	main_canyon.fractal_gain = 0.50

	# Tributary canyons: higher frequency, more octaves for complex branching
	var tributary := FastNoiseLite.new()
	tributary.seed = seed + 211
	tributary.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	tributary.frequency = maxf(tributary_frequency, 0.000005)
	tributary.fractal_type = FastNoiseLite.FRACTAL_FBM
	tributary.fractal_octaves = 4
	tributary.fractal_lacunarity = 2.1
	tributary.fractal_gain = 0.48

	# Plateau surface: medium frequency for rolling plateau texture
	var plateau_surface := FastNoiseLite.new()
	plateau_surface.seed = seed + 313
	plateau_surface.noise_type = FastNoiseLite.TYPE_SIMPLEX
	plateau_surface.frequency = maxf(plateau_surface_frequency, 0.000005)
	plateau_surface.fractal_type = FastNoiseLite.FRACTAL_FBM
	plateau_surface.fractal_octaves = 4
	plateau_surface.fractal_lacunarity = 2.0
	plateau_surface.fractal_gain = 0.5

	var flat_surface_undulation := FastNoiseLite.new()
	flat_surface_undulation.seed = seed + 347
	flat_surface_undulation.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	flat_surface_undulation.frequency = maxf(flat_surface_undulation_frequency, 0.000001)
	flat_surface_undulation.fractal_type = FastNoiseLite.FRACTAL_FBM
	flat_surface_undulation.fractal_octaves = 2
	flat_surface_undulation.fractal_lacunarity = 2.0
	flat_surface_undulation.fractal_gain = 0.5

	var flat_surface_detail := FastNoiseLite.new()
	flat_surface_detail.seed = seed + 359
	flat_surface_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	flat_surface_detail.frequency = maxf(flat_surface_detail_frequency, 0.000001)
	flat_surface_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	flat_surface_detail.fractal_octaves = 3
	flat_surface_detail.fractal_lacunarity = 2.0
	flat_surface_detail.fractal_gain = 0.5

	# Color variation: medium-low frequency so adjacent faces share similar tints,
	# producing smooth gradient patches rather than per-face salt-and-pepper noise.
	var color_var := FastNoiseLite.new()
	color_var.seed = seed + 521
	color_var.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	color_var.frequency = maxf(color_patch_frequency, 0.000001)
	color_var.fractal_type = FastNoiseLite.FRACTAL_FBM
	color_var.fractal_octaves = 3
	color_var.fractal_lacunarity = 2.0
	color_var.fractal_gain = 0.5

	# Strata variation: very low frequency so band heights shift gradually across the map
	var strata_var := FastNoiseLite.new()
	strata_var.seed = seed + 419
	strata_var.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	strata_var.frequency = maxf(main_canyon_frequency * 0.3, 0.000002)
	strata_var.fractal_type = FastNoiseLite.FRACTAL_FBM
	strata_var.fractal_octaves = 2
	strata_var.fractal_lacunarity = 2.0
	strata_var.fractal_gain = 0.5

	var cliff_jitter := FastNoiseLite.new()
	cliff_jitter.seed = seed + 457
	cliff_jitter.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cliff_jitter.frequency = maxf(cliff_planform_jitter_frequency, 0.000001)
	cliff_jitter.fractal_type = FastNoiseLite.FRACTAL_FBM
	cliff_jitter.fractal_octaves = 2
	cliff_jitter.fractal_lacunarity = 2.0
	cliff_jitter.fractal_gain = 0.5

	var ground_patch := FastNoiseLite.new()
	ground_patch.seed = seed + 601
	ground_patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ground_patch.frequency = maxf(ground_patch_frequency, 0.000001)
	ground_patch.fractal_type = FastNoiseLite.FRACTAL_FBM
	ground_patch.fractal_octaves = 2
	ground_patch.fractal_lacunarity = 2.0
	ground_patch.fractal_gain = 0.5

	var pale_dust := FastNoiseLite.new()
	pale_dust.seed = seed + 617
	pale_dust.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pale_dust.frequency = maxf(pale_dust_frequency, 0.000001)
	pale_dust.fractal_type = FastNoiseLite.FRACTAL_FBM
	pale_dust.fractal_octaves = 3
	pale_dust.fractal_lacunarity = 2.0
	pale_dust.fractal_gain = 0.48

	var basin_dark := FastNoiseLite.new()
	basin_dark.seed = seed + 631
	basin_dark.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	basin_dark.frequency = maxf(basin_dark_frequency, 0.000001)
	basin_dark.fractal_type = FastNoiseLite.FRACTAL_FBM
	basin_dark.fractal_octaves = 2
	basin_dark.fractal_lacunarity = 2.0
	basin_dark.fractal_gain = 0.52

	var cliff_streak := FastNoiseLite.new()
	cliff_streak.seed = seed + 647
	cliff_streak.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cliff_streak.frequency = maxf(cliff_streak_frequency, 0.000001)
	cliff_streak.fractal_type = FastNoiseLite.FRACTAL_FBM
	cliff_streak.fractal_octaves = 3
	cliff_streak.fractal_lacunarity = 2.25
	cliff_streak.fractal_gain = 0.52

	return {
		"canyon_warp": canyon_warp,
		"main_canyon": main_canyon,
		"tributary": tributary,
		"plateau_surface": plateau_surface,
		"flat_surface_undulation": flat_surface_undulation,
		"flat_surface_detail": flat_surface_detail,
		"strata_var": strata_var,
		"cliff_jitter": cliff_jitter,
		"color_var": color_var,
		"ground_patch": ground_patch,
		"pale_dust": pale_dust,
		"basin_dark": basin_dark,
		"cliff_streak": cliff_streak,
	}

func _sample_height(world_x: float, world_z: float, noises: Dictionary) -> float:
	# --- Domain warp: organically meander the canyon network ---
	var warp_noise: FastNoiseLite = noises["canyon_warp"] as FastNoiseLite
	var warp_x: float = warp_noise.get_noise_2d(world_x, world_z) * canyon_warp_amplitude_m
	var warp_z: float = warp_noise.get_noise_2d(world_x + 6000.0, world_z - 8000.0) * canyon_warp_amplitude_m
	var wx: float = world_x + warp_x
	var wz: float = world_z + warp_z

	# --- Main canyon network ---
	# absf() of smooth noise: zero-crossings become channel centers, forming a connected network
	var main_raw: float = absf((noises["main_canyon"] as FastNoiseLite).get_noise_2d(wx, wz))
	var main_carve: float = _canyon_carve(main_raw, canyon_floor_width, canyon_cliff_width, canyon_cliff_power, canyon_max_depth_m)

	# --- Tributary canyons ---
	# Slightly offset warp keeps tributaries diverging naturally from main channels
	var trib_raw: float = absf((noises["tributary"] as FastNoiseLite).get_noise_2d(wx + wz * 0.28, wz - wx * 0.22))
	var trib_depth: float = canyon_max_depth_m * clampf(tributary_depth_fraction, 0.1, 1.0)
	var trib_carve: float = _canyon_carve(trib_raw, canyon_floor_width * 0.75, canyon_cliff_width * 0.85, canyon_cliff_power, trib_depth)

	# Use the deepest carving at each point (union of all canyon networks)
	var total_carve: float = maxf(main_carve, trib_carve)
	var h: float = plateau_height_m - total_carve

	# --- Horizontal strata bands with soft slopes in cliff faces ---
	# Each band: flat shelf at its base, then a smooth slope rising to the next level.
	# Band height varies spatially via low-frequency noise for geological interest.
	var carve_frac: float = total_carve / maxf(canyon_max_depth_m, 1.0)
	if carve_frac > 0.04 and carve_frac < 0.97 and strata_step_m > 0.5:
		var strata_var_n: float = (noises["strata_var"] as FastNoiseLite).get_noise_2d(world_x, world_z)
		var local_step: float = maxf(strata_step_m + strata_var_n * strata_height_variation_m, 5.0)
		var shaped: float = _strata_with_slopes(h, local_step, strata_shelf_fraction)
		# Blending is strongest mid-wall, fades near floor and plateau rim
		var wall_t: float = 1.0 - absf(carve_frac * 2.0 - 1.0)  # peaks at 0.5 (mid-wall)
		h = lerpf(h, shaped, wall_t * clampf(strata_strength, 0.0, 1.0))

	# --- Plateau surface variation ---
	# Only applied where there is little or no carving (on the plateau)
	var plateau_blend: float = clampf(1.0 - carve_frac * 6.0, 0.0, 1.0)  # fades quickly into canyons
	var surface_var: float = (noises["plateau_surface"] as FastNoiseLite).get_noise_2d(world_x, world_z) * plateau_surface_amplitude_m
	h += surface_var * plateau_blend

	# --- Subtle undulation on broad flat surfaces ---
	# Keep this off the canyon walls and reserve it for the plateau and flat canyon floors.
	var canyon_floor_blend: float = clampf((carve_frac - 0.82) / 0.18, 0.0, 1.0)
	var flat_surface_blend: float = maxf(plateau_blend, canyon_floor_blend)
	var flat_surface_var: float = (noises["flat_surface_undulation"] as FastNoiseLite).get_noise_2d(world_x, world_z) * flat_surface_undulation_amplitude_m
	h += flat_surface_var * flat_surface_blend
	var flat_surface_detail_var: float = (noises["flat_surface_detail"] as FastNoiseLite).get_noise_2d(world_x, world_z) * flat_surface_detail_amplitude_m
	h += flat_surface_detail_var * flat_surface_blend

	return h + base_height_offset_m

# Maps canyon ridge-noise signal to a carving depth with near-vertical walls.
# signal_raw: 0 = canyon center, increases outward to plateau
# Returns: metres to carve down from plateau (0 = no carve; max_depth = deepest floor)
func _canyon_carve(signal_raw: float, floor_w: float, cliff_w: float, cliff_pow: float, max_depth: float) -> float:
	var threshold: float = floor_w + cliff_w
	if signal_raw >= threshold:
		return 0.0  # Fully on the plateau
	var t: float
	if signal_raw <= floor_w:
		t = 0.0  # Flat canyon floor
	else:
		t = _smoothstep(floor_w, threshold, signal_raw)
		t = pow(t, maxf(cliff_pow, 0.5))  # Sharpen into near-vertical wall
	return (1.0 - t) * max_depth

# Shapes height into strata bands: flat shelf at the base of each band,
# then a smooth slope up to the next band level.
# shelf_frac: 0 = all slope, 1 = all flat (pure step terraces)
func _strata_with_slopes(h: float, step: float, shelf_frac: float) -> float:
	var band: float = floor(h / step)
	var frac: float = (h - band * step) / step  # 0..1 within this band
	var sf: float = clampf(shelf_frac, 0.01, 0.99)
	var shaped: float
	if frac <= sf:
		shaped = 0.0  # flat rock shelf
	else:
		shaped = _smoothstep(sf, 1.0, frac)  # smooth ramp to next level
	return (band + shaped) * step

func _get_stream_center_local() -> Vector3:
	var target: Node3D = null
	if stream_target_path != NodePath(""):
		target = get_node_or_null(stream_target_path) as Node3D
	var viewport := get_viewport()
	var active_camera := viewport.get_camera_3d() if viewport != null else null
	if active_camera and is_instance_valid(active_camera):
		var stream_world_pos: Vector3 = active_camera.global_position
		var forward := -active_camera.global_basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			stream_world_pos += forward.normalized() * maxf(stream_preload_ahead_m, 0.0)
		return to_local(stream_world_pos)
	if not target:
		target = get_tree().get_first_node_in_group("aircraft") as Node3D
	if not target:
		target = get_tree().get_first_node_in_group("carrier") as Node3D
	if target:
		return to_local(target.global_position)
	return Vector3.ZERO

func _world_to_chunk(local_x: float, local_z: float) -> Vector2i:
	var chunk_span_x: float = float(max(chunk_quads_x, 1)) * cell_size_m
	var chunk_span_z: float = float(max(chunk_quads_z, 1)) * cell_size_m
	var cx: int = int(floor((local_x - _x0) / maxf(chunk_span_x, 0.00001)))
	var cz: int = int(floor((local_z - _z0) / maxf(chunk_span_z, 0.00001)))
	cx = clampi(cx, 0, _chunk_count_x - 1)
	cz = clampi(cz, 0, _chunk_count_z - 1)
	return Vector2i(cx, cz)

func _is_chunk_in_bounds(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < _chunk_count_x and cz < _chunk_count_z

func _chunk_key(cx: int, cz: int) -> String:
	return "%d:%d" % [cx, cz]

func _key_to_chunk(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(":")
	if parts.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))

func _remove_chunk(key: String) -> void:
	var chunk: Node3D = _chunks.get(key) as Node3D
	if chunk and is_instance_valid(chunk):
		chunk.queue_free()
	_chunks.erase(key)
	_pending_set.erase(key)
	# If a worker is still building this chunk, mark the result for discard on completion.
	if _building_set.has(key):
		_discard_on_complete[key] = true

func _set_owner_recursive(node: Node) -> void:
	var root: Node = get_tree().edited_scene_root
	if not root:
		return
	node.owner = root
	for child in node.get_children():
		_set_owner_recursive(child)

func _relax_heights(heights: PackedFloat32Array, cols: int, rows: int) -> void:
	var ms: float = quant_max_step_m
	for _p in range(quant_relax_passes):
		# Forward pass: propagate low values rightward/downward
		for gz in range(rows):
			for gx in range(cols):
				var idx: int = gz * cols + gx
				var h: float = heights[idx]
				if gx > 0:
					h = minf(h, heights[gz * cols + gx - 1] + ms)
				if gz > 0:
					h = minf(h, heights[(gz - 1) * cols + gx] + ms)
				heights[idx] = h
		# Reverse pass: propagate leftward/upward
		for gz in range(rows - 1, -1, -1):
			for gx in range(cols - 1, -1, -1):
				var idx: int = gz * cols + gx
				var h: float = heights[idx]
				if gx < cols - 1:
					h = minf(h, heights[gz * cols + gx + 1] + ms)
				if gz < rows - 1:
					h = minf(h, heights[(gz + 1) * cols + gx] + ms)
				heights[idx] = h

func _straighten_cliff_planform(heights: PackedFloat32Array, cols: int, rows: int) -> void:
	if cols < 3 or rows < 3:
		return
	var passes: int = max(cliff_planform_passes, 0)
	var strength: float = clampf(cliff_planform_straighten_strength, 0.0, 1.0)
	if passes <= 0 or strength <= 0.0:
		return

	var min_slope: float = maxf(cliff_planform_min_slope_rise_over_run, 0.001)
	var sample_dist: float = maxf(cliff_planform_sample_distance_cells, 0.1)
	var source: PackedFloat32Array = heights.duplicate()
	var dest := PackedFloat32Array()
	dest.resize(heights.size())

	for _pass in range(passes):
		for z in range(rows):
			for x in range(cols):
				var idx: int = z * cols + x
				var h: float = source[idx]
				if x == 0 or z == 0 or x == cols - 1 or z == rows - 1:
					dest[idx] = h
					continue

				var dx: float = (source[z * cols + x + 1] - source[z * cols + x - 1]) * 0.5
				var dz: float = (source[(z + 1) * cols + x] - source[(z - 1) * cols + x]) * 0.5
				var slope_rise_over_run: float = Vector2(dx, dz).length() / maxf(cell_size_m, 0.001)
				if slope_rise_over_run < min_slope:
					dest[idx] = h
					continue

				# Smooth along the cliff tangent instead of across it so walls keep their height
				# while their footprint becomes less rounded and billowy in plan view.
				var tangent := Vector2(-dz, dx)
				if tangent.length_squared() < 0.000001:
					dest[idx] = h
					continue
				tangent = tangent.normalized() * sample_dist

				var along_a: float = _sample_grid_bilinear(source, cols, rows, float(x) - tangent.x, float(z) - tangent.y)
				var along_b: float = _sample_grid_bilinear(source, cols, rows, float(x) + tangent.x, float(z) + tangent.y)
				var straightened_h: float = 0.5 * (along_a + along_b)
				var slope_t: float = clampf((slope_rise_over_run - min_slope) / maxf(min_slope * 0.75, 0.001), 0.0, 1.0)
				dest[idx] = lerpf(h, straightened_h, strength * slope_t)

		source = dest.duplicate()

	for i in range(heights.size()):
		heights[i] = source[i]

func _soften_cliff_washboard(heights: PackedFloat32Array, cols: int, rows: int) -> void:
	if cols < 3 or rows < 3:
		return
	var passes: int = max(cliff_washboard_passes, 0)
	var strength: float = clampf(cliff_washboard_suppress_strength, 0.0, 1.0)
	if passes <= 0 or strength <= 0.0:
		return

	var min_slope: float = maxf(cliff_planform_min_slope_rise_over_run, 0.001)
	var sample_dist: float = maxf(cliff_washboard_sample_distance_cells, 0.1)
	var source: PackedFloat32Array = heights.duplicate()
	var dest := PackedFloat32Array()
	dest.resize(heights.size())

	for _pass in range(passes):
		for z in range(rows):
			for x in range(cols):
				var idx: int = z * cols + x
				var h: float = source[idx]
				if x == 0 or z == 0 or x == cols - 1 or z == rows - 1:
					dest[idx] = h
					continue

				var dx: float = (source[z * cols + x + 1] - source[z * cols + x - 1]) * 0.5
				var dz: float = (source[(z + 1) * cols + x] - source[(z - 1) * cols + x]) * 0.5
				var slope_rise_over_run: float = Vector2(dx, dz).length() / maxf(cell_size_m, 0.001)
				if slope_rise_over_run < min_slope:
					dest[idx] = h
					continue

				var tangent := Vector2(-dz, dx)
				if tangent.length_squared() < 0.000001:
					dest[idx] = h
					continue
				tangent = tangent.normalized() * sample_dist

				var along_a: float = _sample_grid_bilinear(source, cols, rows, float(x) - tangent.x, float(z) - tangent.y)
				var along_b: float = _sample_grid_bilinear(source, cols, rows, float(x) + tangent.x, float(z) + tangent.y)
				# Keep the center value weighted in so this pass only trims repeating
				# zig-zagging instead of erasing the larger cliff shape.
				var softened_h: float = (along_a + along_b + h * 2.0) * 0.25
				var slope_t: float = clampf((slope_rise_over_run - min_slope) / maxf(min_slope * 0.75, 0.001), 0.0, 1.0)
				dest[idx] = lerpf(h, softened_h, strength * slope_t)

		source = dest.duplicate()

	for i in range(heights.size()):
		heights[i] = source[i]

func _jitter_cliff_planform(
		heights: PackedFloat32Array,
		cols: int,
		rows: int,
		grid_x0: int,
		grid_z0: int,
		noises: Dictionary) -> void:
	if cols < 3 or rows < 3:
		return
	var strength: float = clampf(cliff_planform_jitter_strength, 0.0, 1.0)
	var jitter_cells: float = maxf(cliff_planform_jitter_offset_cells, 0.05)
	if strength <= 0.0:
		return

	var jitter_noise: FastNoiseLite = noises.get("cliff_jitter") as FastNoiseLite
	if jitter_noise == null:
		return

	var min_slope: float = maxf(cliff_planform_min_slope_rise_over_run, 0.001)
	var source: PackedFloat32Array = heights.duplicate()
	var dest := PackedFloat32Array()
	dest.resize(heights.size())

	for z in range(rows):
		for x in range(cols):
			var idx: int = z * cols + x
			var h: float = source[idx]
			if x == 0 or z == 0 or x == cols - 1 or z == rows - 1:
				dest[idx] = h
				continue

			var dx: float = (source[z * cols + x + 1] - source[z * cols + x - 1]) * 0.5
			var dz: float = (source[(z + 1) * cols + x] - source[(z - 1) * cols + x]) * 0.5
			var slope_rise_over_run: float = Vector2(dx, dz).length() / maxf(cell_size_m, 0.001)
			if slope_rise_over_run < min_slope:
				dest[idx] = h
				continue

			var normal := Vector2(dx, dz)
			if normal.length_squared() < 0.000001:
				dest[idx] = h
				continue
			normal = normal.normalized()
			var tangent := Vector2(-normal.y, normal.x)

			var world_x: float = _x0 + float(grid_x0 + x) * cell_size_m
			var world_z: float = _z0 + float(grid_z0 + z) * cell_size_m
			var tangent_noise: float = jitter_noise.get_noise_2d(world_x, world_z)
			var normal_noise: float = jitter_noise.get_noise_2d(world_x + 4137.0, world_z - 2871.0)
			var mask_noise: float = jitter_noise.get_noise_2d(world_x - 1553.0, world_z + 5221.0)
			var jitter_offset := tangent * (tangent_noise * jitter_cells * 0.55) + normal * (normal_noise * jitter_cells * 0.22)
			var jittered_h: float = _sample_grid_bilinear(source, cols, rows, float(x) + jitter_offset.x, float(z) + jitter_offset.y)
			var slope_t: float = clampf((slope_rise_over_run - min_slope) / maxf(min_slope * 0.75, 0.001), 0.0, 1.0)
			var mask_t: float = lerpf(0.45, 1.0, mask_noise * 0.5 + 0.5)
			dest[idx] = lerpf(h, jittered_h, strength * slope_t * mask_t)

	for i in range(heights.size()):
		heights[i] = dest[i]

func _sample_grid_bilinear(heights: PackedFloat32Array, cols: int, rows: int, gx: float, gz: float) -> float:
	var x0: int = clampi(int(floor(gx)), 0, cols - 1)
	var z0: int = clampi(int(floor(gz)), 0, rows - 1)
	var x1: int = min(x0 + 1, cols - 1)
	var z1: int = min(z0 + 1, rows - 1)
	var tx: float = clampf(gx - float(x0), 0.0, 1.0)
	var tz: float = clampf(gz - float(z0), 0.0, 1.0)

	var h00: float = heights[z0 * cols + x0]
	var h10: float = heights[z0 * cols + x1]
	var h01: float = heights[z1 * cols + x0]
	var h11: float = heights[z1 * cols + x1]
	var hx0: float = lerpf(h00, h10, tx)
	var hx1: float = lerpf(h01, h11, tx)
	return lerpf(hx0, hx1, tz)


func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / maxf(edge1 - edge0, 0.00001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _noise01(noise: FastNoiseLite, x: float, y: float) -> float:
	return clampf(noise.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)

func _terrain_color_sample_id(local_x: float, local_z: float) -> int:
	var gx := int(floor((local_x - _x0) / maxf(cell_size_m, 0.001)))
	var gz := int(floor((local_z - _z0) / maxf(cell_size_m, 0.001)))
	return gx * 73856093 ^ gz * 19349663

func _hash01(v: int) -> float:
	var n: int = v
	n = n ^ (n >> 16)
	n = n * 0x7FEB352D
	n = n ^ (n >> 15)
	n = n * 0x846CA68B
	n = n ^ (n >> 16)
	var positive: int = n & 0x7FFFFFFF
	return float(positive) / 2147483647.0
