extends Node3D
class_name RockStream

@export var rock_scene_path: String = "res://Models/Rocks/Rock.glb"
@export var radius_m: float = 400.0
@export var cell_size_m: float = 25.0
@export var density_per_cell: float = 0.4 # probability [0..1] of a rock in a cell
@export var max_instances: int = 2000
@export var min_scale: float = 0.6
@export var max_scale: float = 1.6
@export var max_slope_deg: float = 35.0
@export var update_interval_s: float = 1.5 # deprecated: no longer used for triggering updates
@export var preload_margin_m: float = 100.0
@export var cells_threshold: int = 2
@export var require_terrain_hit: bool = true
@export var raycast_collision_mask: int = 513
@export var seed: int = 12345

const RAYCAST_HEIGHT: float = 4000.0

var _mmi: MultiMeshInstance3D
var _mm: MultiMesh
var _rock_mesh: Mesh
var _last_center_cell: Vector2i = Vector2i(1_000_000, 1_000_000)
var _timer: float = 0.0

func _ready() -> void:
	_mmi = MultiMeshInstance3D.new()
	add_child(_mmi)
	_mmi.owner = get_tree().edited_scene_root
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mmi.multimesh = _mm
	_rock_mesh = _load_mesh_from_scene(rock_scene_path)
	if _rock_mesh == null:
		var fallback := BoxMesh.new()
		fallback.size = Vector3(1.0, 0.6, 0.8)
		_rock_mesh = fallback
	_mm.mesh = _rock_mesh
	# Prepopulate at current camera position to avoid visible popping on start
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_last_center_cell = Vector2i(-999999, -999999)
		_rebuild(cam.global_position)

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var center := cam.global_position
	# Project center to terrain to avoid empty areas (e.g., over carrier deck or sea)
	var grounded: Variant = _find_ground_center(center)
	if grounded is Vector3:
		center = grounded
	elif require_terrain_hit:
		# No terrain under/nearby; skip rebuild to avoid shifting clumps to one side
		return
	var cell := Vector2i(floor(center.x / cell_size_m), floor(center.z / cell_size_m))
	var delta_cells := Vector2i(cell.x - _last_center_cell.x, cell.y - _last_center_cell.y)
	if abs(delta_cells.x) < cells_threshold and abs(delta_cells.y) < cells_threshold and _mm.instance_count > 0:
		return
	_last_center_cell = cell
	_rebuild(center)

func _rebuild(center: Vector3) -> void:
	if _rock_mesh == null:
		return
	var space := get_world_3d().direct_space_state
	var up := Vector3.UP
	var max_slope_cos := cos(deg_to_rad(max_slope_deg))
	var rng := RandomNumberGenerator.new()
	var cells_radius := int(ceil(radius_m / cell_size_m))
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
			# Deterministic RNG per cell
			var h := _hash2i(int(world_x), int(world_z)) ^ seed
			rng.seed = h
			if rng.randf() > density_per_cell:
				continue
			# Random offset within the cell for natural look
			var offx := rng.randf_range(-cell_size_m * 0.5, cell_size_m * 0.5)
			var offz := rng.randf_range(-cell_size_m * 0.5, cell_size_m * 0.5)
			var xz := Vector3(world_x + offx, 0.0, world_z + offz)
			var ray_from := xz + Vector3(0, RAYCAST_HEIGHT, 0)
			var ray_to := xz - Vector3(0, RAYCAST_HEIGHT, 0)
			var params := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
			params.collision_mask = raycast_collision_mask
			var hit := space.intersect_ray(params)
			if hit.is_empty():
				continue
			var n: Vector3 = (hit["normal"] as Vector3).normalized()
			if n.dot(up) < max_slope_cos:
				continue
			var pos: Vector3 = hit["position"]
			var yaw := rng.randf() * TAU
			var s := rng.randf_range(min_scale, max_scale)
			var basis := Basis().rotated(Vector3.UP, yaw).scaled(Vector3(s, s, s))
			# Tiny offset to avoid z-fighting but keep grounded
			transforms[count] = Transform3D(basis, pos + Vector3(0, 0.02, 0))
			count += 1
			if count >= max_instances:
				break
		if count >= max_instances:
			break

	_mm.instance_count = count
	for i in range(count):
		_mm.set_instance_transform(i, transforms[i])

func _find_ground_center(around: Vector3) -> Variant:
	var space := get_world_3d().direct_space_state
	var offsets := [
		Vector3(0, 0, 0),
		Vector3(50, 0, 0), Vector3(-50, 0, 0), Vector3(0, 0, 50), Vector3(0, 0, -50),
		Vector3(100, 0, 0), Vector3(-100, 0, 0), Vector3(0, 0, 100), Vector3(0, 0, -100),
		Vector3(200, 0, 0), Vector3(-200, 0, 0), Vector3(0, 0, 200), Vector3(0, 0, -200)
	]
	for off in offsets:
		var origin := Vector3(around.x + off.x, around.y, around.z + off.z)
		var ray_from := origin + Vector3(0, RAYCAST_HEIGHT, 0)
		var ray_to := origin - Vector3(0, RAYCAST_HEIGHT, 0)
		var params := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		params.collision_mask = raycast_collision_mask
		var hit := space.intersect_ray(params)
		if not hit.is_empty():
			return hit["position"] as Vector3
	return null

func _hash2i(x: int, y: int) -> int:
	# 2D integer hash (32-bit)
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
	elif res is ArrayMesh or res is Mesh:
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
