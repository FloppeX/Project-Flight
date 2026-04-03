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
@export var density_per_cell: float = 0.4
@export var max_instances: int = 2000
@export var min_scale: float = 0.6
@export var max_scale: float = 1.6
## Sink rocks slightly into the terrain so tiny sampling/pivot mismatches do not leave them hovering.
@export var embed_depth_fraction_of_height: float = 0.14
## Small constant embed as an extra hedge against visible floating.
@export var embed_depth_m: float = 0.12
## Maximum terrain slope in degrees — steeper faces get no rocks
@export var max_slope_deg: float = 30.0
## Distance used to sample slope from neighbouring height points
@export var slope_sample_m: float = 3.0
## Extra ring around the rock footprint to check for cliff-edge overhangs.
## 15 m keeps rocks well clear of quantized cliff edges.
@export var support_check_margin_m: float = 15.0
## Maximum allowed terrain drop around a placed rock before it is rejected.
@export var max_support_drop_m: float = 0.9
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

func _ready() -> void:
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
	# Terrain lookup — find via group set in LowPolyTerrain._ready()
	_terrain = get_tree().get_first_node_in_group("terrain_provider") as LowPolyTerrain

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
			if rng.randf() > density_per_cell:
				continue

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
				continue  # Outside terrain bounds

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
			if maxf(slope_x, slope_z) > max_slope_tan:
				continue  # Too steep — cliff face, no rocks

			# Also reject placements that sit near a sharp edge within the rock's
			# footprint, otherwise the center point can be grounded while the mesh
			# visibly hangs out into empty space.
			var support_radius: float = _rock_local_planform_radius * s + support_check_margin_m
			var min_support_h: float = h
			var support_valid: bool = true
			for dir in SUPPORT_SAMPLE_DIRECTIONS:
				var sample_h: float = _terrain.get_height(Vector3(
					px + dir.x * support_radius,
					0.0,
					pz + dir.y * support_radius
				))
				if is_nan(sample_h):
					support_valid = false
					break
				min_support_h = minf(min_support_h, sample_h)
			if not support_valid:
				continue
			if h - min_support_h > max_support_drop_m:
				continue

			var basis := Basis().rotated(Vector3.UP, yaw).scaled(Vector3(s, s, s))
			var embed: float = embed_depth_m + _rock_local_height * s * embed_depth_fraction_of_height
			var rock_y: float = h - _rock_local_min_y * s - embed
			transforms[count] = Transform3D(basis, Vector3(px, rock_y, pz))
			count += 1
			if count >= max_instances:
				break
		if count >= max_instances:
			break

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
