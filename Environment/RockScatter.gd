extends Node3D
class_name RockScatter

@export var area_size_m: float = 1000.0
@export var min_distance_m: float = 40.0
@export var max_instances: int = 2000
@export var max_slope_deg: float = 25.0
@export var min_scale: float = 1.0
@export var max_scale: float = 2.0
@export var rock_color: Color = Color(0.8, 0.2, 0.8)
@export var color_variation: float = 0.08
@export var seed: int = 54321
@export var variants: int = 4
@export var anchor_node_path: String = "../../LandCarrier" # if found, center scatter around this node
@export var raycast_collision_mask: int = 513

const RAYCAST_HEIGHT: float = 4000.0

# Internal state for Poisson grid
var _grid: Dictionary = {}
var _active: Array[Vector2] = []
var _points: Array[Vector2] = []
var _cell_size: float = 1.0
var _half: float = 1.0
var _min_r: float = 1.0

func _ready() -> void:
	print("[RockScatter] _ready() called")
	# Force correct area size (export value not updating in running scene)
	area_size_m = 10000.0  # Cover full 10km x 10km terrain
	min_distance_m = 80.0   # Increase spacing for larger area
	max_instances = 800     # More rocks for larger area
	min_scale = 1.0
	max_scale = 2.0
	rock_color = Color(0.8, 0.2, 0.8)
	# Wait a frame to ensure terrain is ready
	await get_tree().process_frame
	randomize()
	_create_simple_rocks()

func regenerate() -> void:
	_ensure_multimesh()
	_scatter_poisson()

func _ensure_multimesh() -> void:
	variants = clamp(variants, 1, 12)
	# Clear existing children
	for child in get_children():
		child.queue_free()

	for i in range(variants):
		var name := "MM" + str(i)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = name
		add_child(mmi)
		mmi.owner = get_tree().edited_scene_root

		mmi.multimesh = MultiMesh.new()
		mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		mmi.multimesh.instance_count = 0
		print("[RockScatter] Created ", name, " with multimesh")

func _build_rock_mesh() -> void:
	var mat := StandardMaterial3D.new()
	mat.unshaded = true
	mat.vertex_color_use_as_albedo = false
	mat.albedo_color = rock_color

	var box := BoxMesh.new()
	box.size = Vector3(4.0, 2.0, 3.0)
	var rock_mesh: Mesh = box

	# Assign per-variant materials with small tint offsets
	for i in range(variants):
		var denom: float = float(max(1, variants - 1))
		var tint: float = float(i) / denom - 0.5
		var dv := color_variation
		var m := mat.duplicate() as StandardMaterial3D
		var rc := Color(
			clamp(rock_color.r + tint * dv, 0.0, 1.0),
			clamp(rock_color.g + tint * dv, 0.0, 1.0),
			clamp(rock_color.b + tint * dv, 0.0, 1.0),
			1.0
		)
		m.albedo_color = rc
		var mesh_copy := BoxMesh.new()
		mesh_copy.size = box.size
		mesh_copy.material = m
		var node := get_node("MM" + str(i)) as MultiMeshInstance3D
		node.multimesh.mesh = mesh_copy
		print("[RockScatter] Set mesh for ", node.name, " with color ", m.albedo_color)

func _scatter_poisson() -> void:
	# Ensure meshes exist
	var first := get_node("MM0") as MultiMeshInstance3D
	if first.multimesh.mesh == null:
		_build_rock_mesh()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	_min_r = max(1.0, min_distance_m)
	_cell_size = _min_r / sqrt(2.0)
	_half = area_size_m * 0.5
	# Grid for acceleration
	_grid.clear()
	_active.clear()
	_points.clear()

	# Seed with a random point
	_add_point(Vector2(rng.randf_range(-_half, _half), rng.randf_range(-_half, _half)))

	var attempts_per_point := 30
	while _active.size() > 0 and _points.size() < max_instances:
		var a_idx := rng.randi_range(0, _active.size() - 1)
		var base := _active[a_idx]
		var placed := false
		for _i in range(attempts_per_point):
			var ang := rng.randf() * TAU
			var rad := rng.randf_range(_min_r, 2.0 * _min_r)
			var cand := base + Vector2(cos(ang), sin(ang)) * rad
			if _can_place(cand):
				_add_point(cand)
				placed = true
				break
		if not placed:
			_active.remove_at(a_idx)


	# Raycast to terrain for placement
	var space := get_world_3d().direct_space_state
	var up := Vector3.UP
	var max_slope_cos := cos(deg_to_rad(max_slope_deg))

	var transforms_per: Array = []
	for i in range(variants):
		transforms_per.append([])

	var base_origin := global_transform.origin
	if anchor_node_path != "":
		var anchor := get_node_or_null(anchor_node_path)
		if anchor and anchor is Node3D:
			base_origin = (anchor as Node3D).global_transform.origin

	var counts := PackedInt32Array()
	counts.resize(variants)
	for i in range(variants):
		counts[i] = 0

	var successful_raycasts = 0
	var failed_raycasts = 0
	for i in range(_points.size()):
		var p2 := _points[i]
		var world_xz := Vector3(base_origin.x + p2.x, 0.0, base_origin.z + p2.y)
		var ray_from := world_xz + Vector3(0, RAYCAST_HEIGHT, 0)
		var ray_to := world_xz - Vector3(0, RAYCAST_HEIGHT, 0)
		var params := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		params.collision_mask = raycast_collision_mask
		var hit := space.intersect_ray(params)
		if hit.size() == 0:
			failed_raycasts += 1
			continue
		successful_raycasts += 1
		var n: Vector3 = (hit["normal"] as Vector3).normalized()
		# Skip too-steep slopes
		if n.dot(up) < max_slope_cos:
			continue
		var pos: Vector3 = hit["position"]
		var yaw := rng.randf() * TAU
		var scale_val := rng.randf_range(min_scale, max_scale)

		# Build basis aligned loosely with up, but keep simple yaw for a low-poly vibe
		var basis := Basis()
		basis = basis.rotated(Vector3.UP, yaw)
		basis = basis.scaled(Vector3(scale_val, scale_val, scale_val))

		var tr := Transform3D(basis, pos + Vector3(0, 0.1, 0))
		var v := i % variants
		(transforms_per[v] as Array).append(tr)
		counts[v] += 1

	var total_instances := 0
	for v in range(variants):
		var node := get_node("MM" + str(v)) as MultiMeshInstance3D
		var arr := transforms_per[v] as Array
		node.multimesh.instance_count = arr.size()
		for i in range(arr.size()):
			var tr = arr[i] as Transform3D
			node.multimesh.set_instance_transform(i, tr)
		total_instances += arr.size()

	print("[RockScatter] Placed ", total_instances, " rocks across ", variants, " variants around carrier")

	# Debug visibility
	for v in range(variants):
		var node := get_node("MM" + str(v)) as MultiMeshInstance3D
		print("  Variant ", v, ": visible=", node.visible, " instances=", node.multimesh.instance_count)
		if node.multimesh.mesh:
			var mesh = node.multimesh.mesh as BoxMesh
			print("    Mesh size: ", mesh.size)
		if v == 0 and node.multimesh.instance_count > 0:
			var tr = node.multimesh.get_instance_transform(0)
			print("    First rock at: ", tr.origin, " scale: ", tr.basis.get_scale())

	# Create a simple test - just one big rock near carrier
	var test_mm = get_node("MM0")
	test_mm.multimesh.instance_count = 1
	var test_pos = base_origin + Vector3(50, 20, 0)
	var test_transform = Transform3D(Basis().scaled(Vector3(10, 10, 10)), test_pos)
	test_mm.multimesh.set_instance_transform(0, test_transform)
	print("  SIMPLE TEST: One huge purple rock at ", test_pos)

func _create_simple_rocks() -> void:
	# Center scatter on terrain center (5km, 0, 5km) instead of carrier
	var base_origin := Vector3(5000, 0, 5000)

	print("[RockScatter] Creating rocks across 10km terrain centered at: ", base_origin)

	# Generate Poisson disk points
	_generate_points()

	# Create rocks from successful raycast hits
	var main_scene = get_tree().current_scene
	var space := get_world_3d().direct_space_state
	var up := Vector3.UP
	var max_slope_cos := cos(deg_to_rad(max_slope_deg))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var rock_count = 0
	for i in range(min(_points.size(), 400)):  # Increase to 400 rocks for 10km area
		var p2 := _points[i]
		var world_xz := Vector3(base_origin.x + p2.x, 0.0, base_origin.z + p2.y)
		var ray_from := world_xz + Vector3(0, RAYCAST_HEIGHT, 0)
		var ray_to := world_xz - Vector3(0, RAYCAST_HEIGHT, 0)
		var params := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		params.collision_mask = raycast_collision_mask
		var hit := space.intersect_ray(params)

		if hit.size() == 0:
			continue

		var n: Vector3 = (hit["normal"] as Vector3).normalized()
		if n.dot(up) < max_slope_cos:
			continue

		var pos: Vector3 = hit["position"]

		# Create rock
		var rock = MeshInstance3D.new()
		rock.name = "Rock" + str(rock_count)
		main_scene.add_child(rock)

		# Create mesh and material
		rock.mesh = _create_irregular_rock_mesh(rng)

		var mat = StandardMaterial3D.new()
		mat.unshaded = true
		mat.albedo_color = Color(0.6, 0.6, 0.6)  # Gray rock color
		rock.material_override = mat

		# Position and scale
		var yaw := rng.randf() * TAU
		var scale_val := rng.randf_range(min_scale, max_scale)
		rock.position = pos + Vector3(0, 0.2, 0)  # Slight elevation
		rock.rotation_degrees = Vector3(0, rad_to_deg(yaw), 0)
		rock.scale = Vector3(scale_val, scale_val, scale_val)

		rock_count += 1

	print("[RockScatter] Placed ", rock_count, " rocks on terrain")

func _generate_points() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	_min_r = max(1.0, min_distance_m)
	_cell_size = _min_r / sqrt(2.0)
	_half = area_size_m * 0.5

	# Grid for acceleration
	_grid.clear()
	_active.clear()
	_points.clear()

	# Seed with a random point
	_add_point(Vector2(rng.randf_range(-_half, _half), rng.randf_range(-_half, _half)))

	var attempts_per_point := 30
	while _active.size() > 0 and _points.size() < max_instances:
		var a_idx := rng.randi_range(0, _active.size() - 1)
		var base := _active[a_idx]
		var placed := false
		for _i in range(attempts_per_point):
			var ang := rng.randf() * TAU
			var rad := rng.randf_range(_min_r, 2.0 * _min_r)
			var cand := base + Vector2(cos(ang), sin(ang)) * rad
			if _can_place(cand):
				_add_point(cand)
				placed = true
				break
		if not placed:
			_active.remove_at(a_idx)

func _grid_key(p: Vector2) -> Vector2i:
	return Vector2i(floor((p.x + _half) / _cell_size), floor((p.y + _half) / _cell_size))

func _can_place(p: Vector2) -> bool:
	if abs(p.x) > _half or abs(p.y) > _half:
		return false
	var k := _grid_key(p)
	for gx in range(-2, 3):
		for gy in range(-2, 3):
			var nk := Vector2i(k.x + gx, k.y + gy)
			if _grid.has(nk):
				var neighbor: Vector2 = _points[_grid[nk]]
				if neighbor.distance_to(p) < _min_r:
					return false
	return true

func _add_point(p: Vector2) -> void:
	var idx := _points.size()
	_points.append(p)
	_active.append(p)
	_grid[_grid_key(p)] = idx

func _create_irregular_rock_mesh(rng: RandomNumberGenerator) -> Mesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	# Base icosphere-like vertices for irregular shape
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	# Create a deformed cube with random vertex displacement
	var base_size := 1.5
	var corners := [
		Vector3(-1, -0.7, -1), Vector3(1, -0.7, -1), Vector3(1, -0.7, 1), Vector3(-1, -0.7, 1),  # bottom
		Vector3(-1, 0.8, -1), Vector3(1, 0.8, -1), Vector3(1, 0.8, 1), Vector3(-1, 0.8, 1)     # top
	]

	# Add random displacement to each corner
	for i in range(corners.size()):
		var displacement := Vector3(
			rng.randf_range(-0.3, 0.3),
			rng.randf_range(-0.2, 0.2),
			rng.randf_range(-0.3, 0.3)
		)
		corners[i] = (corners[i] + displacement) * base_size
		vertices.append(corners[i])

	# Add some extra vertices for more irregular shape
	for i in range(8):
		var extra_vertex := Vector3(
			rng.randf_range(-1.2, 1.2),
			rng.randf_range(-0.5, 0.6),
			rng.randf_range(-1.2, 1.2)
		) * base_size
		vertices.append(extra_vertex)

	# Create triangular faces (simplified rock shape)
	var faces := [
		# Bottom face
		[0, 1, 2], [0, 2, 3],
		# Top face
		[4, 6, 5], [4, 7, 6],
		# Sides
		[0, 4, 5], [0, 5, 1],
		[1, 5, 6], [1, 6, 2],
		[2, 6, 7], [2, 7, 3],
		[3, 7, 4], [3, 4, 0],
		# Extra irregular faces using extra vertices
		[8, 1, 2], [9, 2, 6], [10, 6, 5], [11, 5, 4],
		[12, 4, 7], [13, 7, 3], [14, 3, 0], [15, 0, 1]
	]

	# Build indices and calculate normals
	for face in faces:
		if face[0] < vertices.size() and face[1] < vertices.size() and face[2] < vertices.size():
			indices.append(face[0])
			indices.append(face[1])
			indices.append(face[2])

			# Calculate face normal
			var v0 := vertices[face[0]]
			var v1 := vertices[face[1]]
			var v2 := vertices[face[2]]
			var normal := (v1 - v0).cross(v2 - v0).normalized()

			normals.append(normal)
			normals.append(normal)
			normals.append(normal)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
