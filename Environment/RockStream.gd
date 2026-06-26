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
@export var density_per_cell: float = 0.28
@export var max_instances: int = 2000
@export var min_scale: float = 0.35
@export var max_scale: float = 0.95
@export_group("Distribution")
## Low-frequency mask that clusters rocks instead of spreading them evenly.
@export var detail_mask_frequency: float = 0.0011
@export_range(0.0, 1.0) var detail_mask_strength: float = 0.55
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
@export var max_slope_deg: float = 30.0
## Distance used to sample slope from neighbouring height points
@export var slope_sample_m: float = 3.0
## Extra ring around the rock footprint to check for cliff-edge overhangs.
## Keeps rocks well clear of quantized cliff edges.
@export var support_check_margin_m: float = 20.0
## Maximum allowed terrain drop around a placed rock before it is rejected.
@export var max_support_drop_m: float = 4.0
## Maximum height variation across the sampled footprint. This rejects nearby
## cliff lips even when the exact sample under the rock center is flat.
@export var max_support_height_variation_m: float = 8.0
## Number of concentric footprint rings to sample when checking cliff clearance.
@export var support_check_rings: int = 2
## Limit sampled directions for streaming cost. The first 8 directions cover
## cardinal and diagonal footprint checks.
@export var support_check_direction_count: int = 8
@export var preload_margin_m: float = 100.0
## Minimum cell movement before rebuilding the rock set
@export var cells_threshold: int = 2
@export var seed: int = 12345

var _mmi: MultiMeshInstance3D
var _mm: MultiMesh
var _rock_mesh: Mesh
var _terrain: LowPolyTerrain
var _last_center_cell: Vector2i = Vector2i(1_000_000, 1_000_000)
var _rock_local_min_y: float = 0.0
var _rock_local_height: float = 0.0
var _rock_local_planform_radius: float = 0.5
var _detail_mask: FastNoiseLite

func _ready() -> void:
	add_to_group("origin_shifter")
	_mmi = MultiMeshInstance3D.new()
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

func apply_origin_shift(_offset: Vector3) -> void:
	# Force a full rebuild on the next _process — the camera's cell will have changed
	_last_center_cell = Vector2i(1_000_000, 1_000_000)

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
	var cell := Vector2i(int(floor(center.x / cell_size_m)), int(floor(center.z / cell_size_m)))
	var delta_cells := cell - _last_center_cell
	if abs(delta_cells.x) < cells_threshold and abs(delta_cells.y) < cells_threshold and _mm.instance_count > 0:
		return
	_last_center_cell = cell
	_rebuild(center)

func _rebuild(center: Vector3) -> void:
	if _terrain == null or _rock_mesh == null:
		return

	var max_slope_tan: float = tan(deg_to_rad(max_slope_deg))
	var rng := RandomNumberGenerator.new()
	var eff_radius := radius_m + preload_margin_m
	var eff_cells_radius := int(ceil(eff_radius / cell_size_m))

	var transforms: Array[Transform3D] = []
	transforms.resize(max_instances)
	var count := 0
	var _dbg_nan := 0; var _dbg_slope := 0; var _dbg_support := 0; var _dbg_density := 0

	for gx in range(-eff_cells_radius, eff_cells_radius + 1):
		for gz in range(-eff_cells_radius, eff_cells_radius + 1):
			var world_x: float = (floor(center.x / cell_size_m) + float(gx)) * cell_size_m + cell_size_m * 0.5
			var world_z: float = (floor(center.z / cell_size_m) + float(gz)) * cell_size_m + cell_size_m * 0.5
			var dx: float = world_x - center.x
			var dz: float = world_z - center.z
			if dx * dx + dz * dz > eff_radius * eff_radius:
				continue

			# Deterministic per-cell random — same result every time for same cell
			var h_val := _hash2i(int(world_x / cell_size_m), int(world_z / cell_size_m)) ^ seed
			rng.seed = h_val

			# Random offset within cell for organic scatter
			var offx := rng.randf_range(-cell_size_m * 0.45, cell_size_m * 0.45)
			var offz := rng.randf_range(-cell_size_m * 0.45, cell_size_m * 0.45)
			var px: float = world_x + offx
			var pz: float = world_z + offz

			var yaw := rng.randf() * TAU
			var s := rng.randf_range(min_scale, max_scale)

			# Height lookup directly from terrain — no raycasts needed
			var h: float = _terrain.get_height(Vector3(px, 0.0, pz))
			if is_nan(h):
				_dbg_nan += 1; continue  # Outside terrain bounds

			# Slope check via central neighbouring samples so one-sided cliffs and
			# rim transitions are rejected more reliably.
			var hx_pos: float = _terrain.get_height(Vector3(px + slope_sample_m, 0.0, pz))
			var hx_neg: float = _terrain.get_height(Vector3(px - slope_sample_m, 0.0, pz))
			var hz_pos: float = _terrain.get_height(Vector3(px, 0.0, pz + slope_sample_m))
			var hz_neg: float = _terrain.get_height(Vector3(px, 0.0, pz - slope_sample_m))
			if is_nan(hx_pos) or is_nan(hx_neg) or is_nan(hz_pos) or is_nan(hz_neg):
				continue
			var slope_x: float = abs(hx_pos - hx_neg) / maxf(slope_sample_m * 2.0, 0.001)
			var slope_z: float = abs(hz_pos - hz_neg) / maxf(slope_sample_m * 2.0, 0.001)
			var slope_amount: float = maxf(slope_x, slope_z)
			if maxf(slope_x, slope_z) > max_slope_tan:
				_dbg_slope += 1; continue  # Too steep — cliff face, no rocks

			# Also reject placements that sit near a sharp edge within the rock's
			# footprint, otherwise the center point can be grounded while the mesh
			# visibly hangs out into empty space.
			var local_density: float = _terrain_detail_density(px, pz, h, slope_amount)
			if rng.randf() > local_density:
				_dbg_density += 1; continue

			if not _has_stable_terrain_support(h, px, pz, s):
				_dbg_support += 1; continue

			var placement_h: float = _get_collision_surface_height(px, pz, h)
			var basis := Basis().rotated(Vector3.UP, yaw).scaled(Vector3(s, s, s))
			var embed: float = embed_depth_m + _rock_local_height * s * embed_depth_fraction_of_height
			var rock_y: float = placement_h - _rock_local_min_y * s - embed
			# Store in RockStream local space so the MultiMesh stays correct after origin shifts
			var local_pos := Vector3(px, rock_y, pz) - global_position
			transforms[count] = Transform3D(basis, local_pos)
			count += 1
			if count >= max_instances:
				break
		if count >= max_instances:
			break

	pass  # placement stats: placed=%d nan=%d density=%d slope=%d support=%d

	# Build into a fresh MultiMesh and swap atomically — avoids a one-frame
	# flash to world-origin that happens when setting instance_count in-place.
	var new_mm := MultiMesh.new()
	new_mm.transform_format = MultiMesh.TRANSFORM_3D
	new_mm.mesh = _rock_mesh
	new_mm.instance_count = count
	for i in range(count):
		new_mm.set_instance_transform(i, transforms[i])
	_mm = new_mm
	_mmi.multimesh = _mm

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
		var raw: float = clampf(_detail_mask.get_noise_2d(px, pz) * 0.5 + 0.5, 0.0, 1.0)
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
			return float(hit.position.y)
	return fallback_h

func _has_stable_terrain_support(center_h: float, px: float, pz: float, rock_scale: float) -> bool:
	if _terrain == null:
		return false
	var rock_radius: float = _rock_local_planform_radius * rock_scale
	var outer_radius: float = rock_radius + support_check_margin_m
	if TerrainNavGrid.has_query_grid():
		return TerrainNavGrid.is_stable_footprint(
			px,
			pz,
			outer_radius,
			max_support_drop_m,
			max_support_height_variation_m
		)
	var ring_count: int = maxi(support_check_rings, 1)
	var inner_radius: float = maxf(minf(rock_radius, slope_sample_m), 1.0)
	outer_radius = maxf(outer_radius, inner_radius)
	var min_h: float = center_h
	var max_h: float = center_h
	for ring_idx in range(ring_count):
		var t: float = 1.0 if ring_count == 1 else float(ring_idx) / float(ring_count - 1)
		var sample_radius: float = lerpf(inner_radius, outer_radius, t)
		var direction_count: int = clampi(support_check_direction_count, 4, SUPPORT_SAMPLE_DIRECTIONS.size())
		for dir_idx in range(direction_count):
			var dir: Vector2 = SUPPORT_SAMPLE_DIRECTIONS[dir_idx]
			var sample_h: float = _terrain.get_height(Vector3(
				px + dir.x * sample_radius,
				0.0,
				pz + dir.y * sample_radius
			))
			if is_nan(sample_h):
				return false
			min_h = minf(min_h, sample_h)
			max_h = maxf(max_h, sample_h)
			if center_h - sample_h > max_support_drop_m:
				return false
			if max_h - min_h > max_support_height_variation_m:
				return false
	return true

func _load_mesh_from_scene(path: String) -> Mesh:
	var res := ResourceLoader.load(path)
	if res == null:
		return null
	if res is PackedScene:
		var inst := (res as PackedScene).instantiate()
		var mi := _find_mesh_instance(inst)
		if mi != null:
			return mi.mesh
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
