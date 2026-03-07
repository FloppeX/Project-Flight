extends Node3D
class_name LowPolyTerrain

@export_group("Size")
@export var quads_x: int = 180
@export var quads_z: int = 180
@export var cell_size_m: float = 28.0
@export var seed: int = 1337

@export_group("Shape")
@export var dune_amplitude_m: float = 50.0
@export var dune_frequency: float = 0.0018
@export var hill_amplitude_m: float = 95.0
@export var hill_frequency: float = 0.00085
@export var gully_depth_m: float = 70.0
@export var gully_frequency: float = 0.0038
@export var gully_width: float = 0.42
@export var gully_falloff: float = 0.24
@export var gully_profile_pow: float = 1.20
@export var gully_floor_step_m: float = 4.0
@export var gully_warp_amplitude_m: float = 260.0
@export var flat_area_strength: float = 0.65
@export var flat_area_threshold: float = 0.08
@export var flat_area_frequency: float = 0.00045
@export var flat_blend_exponent: float = 0.65
@export var flat_snap_step_m: float = 6.0
@export var flat_snap_strength: float = 0.80
@export var global_flatten_strength: float = 0.55
@export var global_flatten_scale: float = 0.12
@export var plateau_strength: float = 0.55
@export var plateau_threshold: float = 0.10
@export var terrace_step_m: float = 4.5
@export var mesa_frequency: float = 0.00016
@export var mesa_threshold: float = 0.72
@export var mesa_height_m: float = 180.0
@export var mesa_side_hardness: float = 2.8
@export var mesa_min_height_m: float = 40.0
@export var mesa_max_height_m: float = 600.0
@export var mesa_height_curve: float = 1.25
@export var mesa_ramp_until: float = 0.58
@export var mesa_ramp_fraction: float = 0.38
@export var mesa_top_variation_m: float = 18.0
@export var mesa_top_step_m: float = 10.0
@export var mesa_top_flatten_start: float = 0.82
@export var mesa_top_flatten_strength: float = 0.90
@export var base_height_offset_m: float = 0.0

@export_group("Color")
@export var sand_color: Color = Color(0.87, 0.62, 0.36, 1.0)
@export var rock_color: Color = Color(0.56, 0.42, 0.31, 1.0)
@export var slope_sand_start: float = 0.12
@export var slope_rock_full: float = 0.55
@export var color_noise_strength: float = 0.12

@export_group("Output")
@export var generate_on_ready: bool = true
@export var generate_collision: bool = true
@export var double_sided: bool = true

@export_group("Streaming")
@export var use_streaming: bool = true
@export var chunk_quads_x: int = 28
@export var chunk_quads_z: int = 28
@export var load_radius_chunks: int = 3
@export var unload_margin_chunks: int = 1
@export var stream_target_path: NodePath
@export var stream_update_interval_s: float = 0.25
@export var max_chunk_builds_per_update: int = 2

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

func get_height(world_pos: Vector3) -> float:
	if _noises.is_empty():
		_refresh_layout()
		_noises = _build_noises()
	var local: Vector3 = to_local(world_pos)
	if local.x < _x0 or local.x > _x0 + _span_x or local.z < _z0 or local.z > _z0 + _span_z:
		return NAN
	return _sample_height(local.x, local.z, _noises)

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
			if _chunks.has(key) or _pending_set.has(key):
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
	var budget: int = max(max_chunk_builds_per_update, 1)
	while budget > 0 and not _pending_builds.is_empty():
		var coord: Vector2i = _pending_builds.pop_front()
		var key := _chunk_key(coord.x, coord.y)
		_pending_set.erase(key)
		if _chunks.has(key):
			budget -= 1
			continue
		var chunk: Node3D = _build_chunk(coord.x, coord.y)
		if chunk:
			_chunk_root.add_child(chunk)
			_set_owner_recursive(chunk)
			_chunks[key] = chunk
		budget -= 1

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
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	for z in range(qz0, qz1):
		for x in range(qx0, qx1):
			var x_a: float = _x0 + float(x) * cell_size_m
			var x_b: float = x_a + cell_size_m
			var z_a: float = _z0 + float(z) * cell_size_m
			var z_b: float = z_a + cell_size_m

			var h00: float = _sample_height(x_a, z_a, _noises)
			var h10: float = _sample_height(x_b, z_a, _noises)
			var h01: float = _sample_height(x_a, z_b, _noises)
			var h11: float = _sample_height(x_b, z_b, _noises)

			var v00 := Vector3(x_a, h00, z_a)
			var v10 := Vector3(x_b, h10, z_a)
			var v01 := Vector3(x_a, h01, z_b)
			var v11 := Vector3(x_b, h11, z_b)

			var cell_id: int = z * _size_x + x
			_append_face(v00, v10, v11, cell_id * 2, vertices, normals, colors)
			_append_face(v00, v11, v01, cell_id * 2 + 1, vertices, normals, colors)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
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
	var n: Vector3 = (v2 - v0).cross(v1 - v0).normalized()
	if n.y < 0.0:
		n = -n
	var slope: float = clampf(1.0 - absf(n.y), 0.0, 1.0)
	var denom: float = maxf(slope_rock_full - slope_sand_start, 0.001)
	var slope_t: float = clampf((slope - slope_sand_start) / denom, 0.0, 1.0)
	var base_color: Color = sand_color.lerp(rock_color, slope_t)

	var tint_rand: float = _hash01(tri_id * 101 + seed * 17)
	var tint: float = 1.0 + (tint_rand * 2.0 - 1.0) * color_noise_strength
	var c := Color(
		clampf(base_color.r * tint, 0.0, 1.0),
		clampf(base_color.g * tint, 0.0, 1.0),
		clampf(base_color.b * tint, 0.0, 1.0),
		1.0
	)

	vertices.push_back(v0)
	vertices.push_back(v1)
	vertices.push_back(v2)
	normals.push_back(n)
	normals.push_back(n)
	normals.push_back(n)
	colors.push_back(c)
	colors.push_back(c)
	colors.push_back(c)

func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular = 0.05
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK
	return mat

func _build_noises() -> Dictionary:
	var dune := FastNoiseLite.new()
	dune.seed = seed
	dune.noise_type = FastNoiseLite.TYPE_SIMPLEX
	dune.frequency = maxf(dune_frequency, 0.00001)
	dune.fractal_type = FastNoiseLite.FRACTAL_FBM
	dune.fractal_octaves = 4
	dune.fractal_lacunarity = 2.0
	dune.fractal_gain = 0.5

	var hill := FastNoiseLite.new()
	hill.seed = seed + 101
	hill.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hill.frequency = maxf(hill_frequency, 0.00001)
	hill.fractal_type = FastNoiseLite.FRACTAL_FBM
	hill.fractal_octaves = 3
	hill.fractal_lacunarity = 1.95
	hill.fractal_gain = 0.55

	var gully := FastNoiseLite.new()
	gully.seed = seed + 211
	gully.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	gully.frequency = maxf(gully_frequency, 0.00001)
	gully.fractal_type = FastNoiseLite.FRACTAL_FBM
	gully.fractal_octaves = 4
	gully.fractal_lacunarity = 2.0
	gully.fractal_gain = 0.5

	var gully_secondary := FastNoiseLite.new()
	gully_secondary.seed = seed + 233
	gully_secondary.noise_type = FastNoiseLite.TYPE_SIMPLEX
	gully_secondary.frequency = maxf(gully_frequency * 1.25, 0.00001)
	gully_secondary.fractal_type = FastNoiseLite.FRACTAL_FBM
	gully_secondary.fractal_octaves = 3
	gully_secondary.fractal_lacunarity = 2.1
	gully_secondary.fractal_gain = 0.52

	var gully_warp := FastNoiseLite.new()
	gully_warp.seed = seed + 263
	gully_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	gully_warp.frequency = maxf(gully_frequency * 0.30, 0.00001)
	gully_warp.fractal_type = FastNoiseLite.FRACTAL_FBM
	gully_warp.fractal_octaves = 2

	var flat := FastNoiseLite.new()
	flat.seed = seed + 307
	flat.noise_type = FastNoiseLite.TYPE_SIMPLEX
	flat.frequency = maxf(flat_area_frequency, 0.00001)
	flat.fractal_type = FastNoiseLite.FRACTAL_FBM
	flat.fractal_octaves = 2

	var plateau := FastNoiseLite.new()
	plateau.seed = seed + 401
	plateau.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	plateau.frequency = maxf(flat_area_frequency * 1.35, 0.00001)
	plateau.fractal_type = FastNoiseLite.FRACTAL_FBM
	plateau.fractal_octaves = 2

	var macro := FastNoiseLite.new()
	macro.seed = seed + 509
	macro.noise_type = FastNoiseLite.TYPE_SIMPLEX
	macro.frequency = maxf(flat_area_frequency * 0.65, 0.00001)
	macro.fractal_type = FastNoiseLite.FRACTAL_FBM
	macro.fractal_octaves = 2

	var mesa := FastNoiseLite.new()
	mesa.seed = seed + 613
	mesa.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mesa.frequency = maxf(mesa_frequency, 0.00001)
	mesa.fractal_type = FastNoiseLite.FRACTAL_FBM
	mesa.fractal_octaves = 2
	mesa.fractal_lacunarity = 2.0
	mesa.fractal_gain = 0.5

	var mesa_top := FastNoiseLite.new()
	mesa_top.seed = seed + 719
	mesa_top.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mesa_top.frequency = maxf(mesa_frequency * 1.8, 0.00001)
	mesa_top.fractal_type = FastNoiseLite.FRACTAL_FBM
	mesa_top.fractal_octaves = 1

	var mesa_height := FastNoiseLite.new()
	mesa_height.seed = seed + 823
	mesa_height.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mesa_height.frequency = maxf(mesa_frequency * 0.65, 0.00001)
	mesa_height.fractal_type = FastNoiseLite.FRACTAL_FBM
	mesa_height.fractal_octaves = 2
	mesa_height.fractal_lacunarity = 2.1
	mesa_height.fractal_gain = 0.45

	return {
		"dune": dune,
		"hill": hill,
		"gully": gully,
		"gully_secondary": gully_secondary,
		"gully_warp": gully_warp,
		"flat": flat,
		"plateau": plateau,
		"macro": macro,
		"mesa": mesa,
		"mesa_top": mesa_top,
		"mesa_height": mesa_height
	}

func _sample_height(world_x: float, world_z: float, noises: Dictionary) -> float:
	var macro_noise: FastNoiseLite = noises["macro"] as FastNoiseLite
	var macro_signal: float = macro_noise.get_noise_2d(world_x, world_z)

	var dune: float = (noises["dune"] as FastNoiseLite).get_noise_2d(world_x, world_z) * dune_amplitude_m

	var hill_signal: float = (noises["hill"] as FastNoiseLite).get_noise_2d(world_x, world_z)
	var hill: float = pow(maxf(hill_signal, 0.0), 2.4) * hill_amplitude_m

	var gully_warp: FastNoiseLite = noises["gully_warp"] as FastNoiseLite
	var warp_x: float = gully_warp.get_noise_2d(world_x, world_z) * gully_warp_amplitude_m
	var warp_z: float = gully_warp.get_noise_2d(world_x + 7000.0, world_z - 9000.0) * gully_warp_amplitude_m
	var gully_signal_a: float = absf((noises["gully"] as FastNoiseLite).get_noise_2d(world_x + warp_x, world_z + warp_z))
	var gully_signal_b: float = absf((noises["gully_secondary"] as FastNoiseLite).get_noise_2d(world_x - warp_z * 0.5, world_z + warp_x * 0.5))
	var gully_signal: float = minf(gully_signal_a, gully_signal_b * 1.05)
	var gully_w: float = clampf(gully_width, 0.01, 0.95)
	var gully_f: float = clampf(gully_falloff, 0.01, 0.99 - gully_w)
	var gully_core: float = 1.0 - _smoothstep(gully_w, gully_w + gully_f, gully_signal)
	var gully_shape: float = pow(clampf(gully_core, 0.0, 1.0), maxf(gully_profile_pow, 0.05))
	var gully: float = -gully_shape * gully_depth_m
	if gully_floor_step_m > 0.001:
		var gully_snapped: float = round(gully / gully_floor_step_m) * gully_floor_step_m
		gully = lerpf(gully, gully_snapped, 0.65)

	var h: float = dune + hill + gully

	var global_flat_target: float = macro_signal * (dune_amplitude_m * global_flatten_scale)
	h = lerpf(h, global_flat_target, clampf(global_flatten_strength, 0.0, 1.0))

	var flat_signal: float = (noises["flat"] as FastNoiseLite).get_noise_2d(world_x, world_z)
	var flat_t_raw: float = _smoothstep(flat_area_threshold, 1.0, flat_signal)
	var flat_t: float = pow(clampf(flat_t_raw, 0.0, 1.0), maxf(flat_blend_exponent, 0.01)) * flat_area_strength
	flat_t = clampf(flat_t, 0.0, 1.0)
	var flat_target: float = macro_signal * (dune_amplitude_m * 0.10)
	h = lerpf(h, flat_target, flat_t)
	if flat_snap_step_m > 0.001:
		var flat_snapped: float = round(h / flat_snap_step_m) * flat_snap_step_m
		var snap_t: float = clampf(flat_t * flat_snap_strength, 0.0, 1.0)
		h = lerpf(h, flat_snapped, snap_t)

	var plateau_signal: float = (noises["plateau"] as FastNoiseLite).get_noise_2d(world_x, world_z)
	var plateau_t: float = _smoothstep(plateau_threshold, 1.0, plateau_signal) * plateau_strength
	if terrace_step_m > 0.001:
		var terraced: float = round(h / terrace_step_m) * terrace_step_m
		h = lerpf(h, terraced, clampf(plateau_t, 0.0, 1.0))

	var mesa_signal: float = (noises["mesa"] as FastNoiseLite).get_noise_2d(world_x, world_z)
	var mesa_blend: float = _smoothstep(mesa_threshold, mesa_threshold + 0.45, mesa_signal)
	if mesa_blend > 0.0:
		var ramp_until: float = clampf(mesa_ramp_until, 0.05, 0.95)
		var ramp_t: float = _smoothstep(0.0, ramp_until, mesa_blend)
		var cliff_t: float = _smoothstep(ramp_until, 1.0, mesa_blend)
		var cliff_shape: float = pow(cliff_t, maxf(mesa_side_hardness, 0.1))
		var ramp_fraction: float = clampf(mesa_ramp_fraction, 0.0, 1.0)
		var mesa_profile: float = clampf(ramp_t * ramp_fraction + cliff_shape * (1.0 - ramp_fraction), 0.0, 1.0)

		var height_signal: float = (noises["mesa_height"] as FastNoiseLite).get_noise_2d(world_x, world_z)
		var height_t: float = pow(clampf((height_signal + 1.0) * 0.5, 0.0, 1.0), maxf(mesa_height_curve, 0.01))
		var mesa_min_h: float = minf(mesa_min_height_m, mesa_max_height_m)
		var mesa_max_h: float = maxf(mesa_min_height_m, mesa_max_height_m)
		var variable_height: float = lerpf(mesa_min_h, mesa_max_h, height_t)
		var mesa_height_blend: float = clampf(mesa_height_m / maxf(mesa_max_h, 0.001), 0.0, 1.0)
		variable_height = lerpf(variable_height, mesa_height_m, mesa_height_blend * 0.25)

		var mesa_base: float = macro_signal * (dune_amplitude_m * 0.18)
		var mesa_top_noise: float = (noises["mesa_top"] as FastNoiseLite).get_noise_2d(world_x, world_z) * mesa_top_variation_m
		var mesa_target: float = mesa_base + variable_height * mesa_profile + mesa_top_noise

		var top_start: float = clampf(mesa_top_flatten_start, 0.0, 0.98)
		var top_t: float = _smoothstep(top_start, 1.0, mesa_blend) * clampf(mesa_top_flatten_strength, 0.0, 1.0)
		if mesa_top_step_m > 0.001:
			var mesa_snapped: float = round(mesa_target / mesa_top_step_m) * mesa_top_step_m
			mesa_target = lerpf(mesa_target, mesa_snapped, top_t)

		h = maxf(h, mesa_target)

	return h + base_height_offset_m

func _get_stream_center_local() -> Vector3:
	var target: Node3D = null
	if stream_target_path != NodePath(""):
		target = get_node_or_null(stream_target_path) as Node3D
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

func _set_owner_recursive(node: Node) -> void:
	var root: Node = get_tree().edited_scene_root
	if not root:
		return
	node.owner = root
	for child in node.get_children():
		_set_owner_recursive(child)

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / maxf(edge1 - edge0, 0.00001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _hash01(v: int) -> float:
	var n: int = v
	n = n ^ (n >> 16)
	n = n * 0x7FEB352D
	n = n ^ (n >> 15)
	n = n * 0x846CA68B
	n = n ^ (n >> 16)
	var positive: int = n & 0x7FFFFFFF
	return float(positive) / 2147483647.0
