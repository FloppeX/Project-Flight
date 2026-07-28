extends Node3D
class_name CommanderWalkArea

@export var lower_floor_path: NodePath = NodePath("../CarrierModel/superstructure floor lower")
@export var upper_floor_path: NodePath = NodePath("../CarrierModel/superstructure floor upper")
@export var elevator_path: NodePath = NodePath("../CarrierModel/Superstructure elevator")
@export var commander_path: NodePath = NodePath("../Commander")
@export var spawn_reference_path: NodePath = NodePath("../CarrierModel/human")
@export var elevator_travel_m: float = 5.223
@export var elevator_speed_mps: float = 1.75
@export var elevator_trigger_delay_s: float = 0.35
@export var elevator_edge_margin_m: float = 0.2
@export var walk_edge_margin_m: float = 0.4

var _carrier: Node3D
var _lower_floor: MeshInstance3D
var _upper_floor: MeshInstance3D
var _elevator: MeshInstance3D
var _commander: CharacterBody3D
var _spawn_reference: MeshInstance3D

var _lower_triangles: Array[PackedVector2Array] = []
var _upper_triangles: Array[PackedVector2Array] = []
var _lower_floor_y: float = 0.0
var _upper_floor_y: float = 0.0
var _elevator_lower_position: Vector3 = Vector3.ZERO
var _elevator_min_xz: Vector2 = Vector2.ZERO
var _elevator_max_xz: Vector2 = Vector2.ZERO
var _elevator_top_y: float = 0.0

var _initialized: bool = false
var _initial_position_resolved: bool = false
var _active_floor: int = 0
var _elevator_at_upper: bool = false
var _elevator_moving: bool = false
var _commander_riding: bool = false
var _elevator_armed: bool = true
var _stand_time_s: float = 0.0
var _elevator_progress: float = 0.0

const FLOOR_LOWER: int = 0
const FLOOR_UPPER: int = 1


func _ready() -> void:
	_ensure_initialized()


func _physics_process(delta: float) -> void:
	if not _ensure_initialized():
		return

	if _elevator_moving:
		_update_elevator_motion(delta)
		return

	var commander_on_elevator := _is_inside_elevator_footprint(_commander.position)
	if not commander_on_elevator:
		_stand_time_s = 0.0
		if not _elevator_armed:
			_elevator_armed = true
		return

	if not _elevator_armed:
		return
	if not _is_safely_on_elevator(_commander.position):
		_stand_time_s = 0.0
		return

	# The platform can only be boarded from the floor where it is parked.
	if (_active_floor == FLOOR_UPPER) != _elevator_at_upper:
		return

	_stand_time_s += delta
	if _stand_time_s >= elevator_trigger_delay_s:
		_begin_elevator_trip()


func constrain_commander_position(current_position: Vector3, desired_position: Vector3) -> Vector3:
	if not _ensure_initialized():
		return desired_position

	if not _initial_position_resolved:
		_initial_position_resolved = true
		_active_floor = FLOOR_LOWER
		var spawn_position := _get_lower_spawn_position()
		current_position = spawn_position
		desired_position = spawn_position

	if _commander_riding:
		var riding_position := desired_position
		riding_position.x = clampf(
			riding_position.x,
			_elevator_min_xz.x + elevator_edge_margin_m,
			_elevator_max_xz.x - elevator_edge_margin_m
		)
		riding_position.z = clampf(
			riding_position.z,
			_elevator_min_xz.y + elevator_edge_margin_m,
			_elevator_max_xz.y - elevator_edge_margin_m
		)
		riding_position.y = _elevator_top_y
		return riding_position

	var floor_triangles := _lower_triangles if _active_floor == FLOOR_LOWER else _upper_triangles
	var floor_y := _lower_floor_y if _active_floor == FLOOR_LOWER else _upper_floor_y
	var result := current_position
	var current_xz := Vector2(current_position.x, current_position.z)
	var desired_xz := Vector2(desired_position.x, desired_position.z)
	var resolved_xz := _resolve_walk_movement(current_xz, desired_xz, floor_triangles)
	result.x = resolved_xz.x
	result.z = resolved_xz.y
	result.y = floor_y
	return result


func _resolve_walk_movement(
	current: Vector2,
	desired: Vector2,
	floor_triangles: Array[PackedVector2Array]
) -> Vector2:
	if _is_valid_walk_position(desired, floor_triangles):
		return desired

	# Resolve each axis separately so movement into a boundary preserves the
	# component parallel to that boundary instead of stopping completely.
	var resolved := current
	var movement := desired - current
	var try_x_first := absf(movement.x) >= absf(movement.y)
	if try_x_first:
		resolved = _try_walk_axis(resolved, Vector2(desired.x, resolved.y), floor_triangles)
		resolved = _try_walk_axis(resolved, Vector2(resolved.x, desired.y), floor_triangles)
	else:
		resolved = _try_walk_axis(resolved, Vector2(resolved.x, desired.y), floor_triangles)
		resolved = _try_walk_axis(resolved, Vector2(desired.x, resolved.y), floor_triangles)
	return resolved


func _try_walk_axis(
	current: Vector2,
	candidate: Vector2,
	floor_triangles: Array[PackedVector2Array]
) -> Vector2:
	return candidate if _is_valid_walk_position(candidate, floor_triangles) else current


func _is_valid_walk_position(point: Vector2, floor_triangles: Array[PackedVector2Array]) -> bool:
	if _is_walkable_floor_position(point, floor_triangles):
		return true
	return _platform_is_at_active_floor() and _is_inside_elevator_footprint_xz(point)


func _ensure_initialized() -> bool:
	if _initialized:
		return true

	_carrier = get_parent() as Node3D
	_lower_floor = get_node_or_null(lower_floor_path) as MeshInstance3D
	_upper_floor = get_node_or_null(upper_floor_path) as MeshInstance3D
	_elevator = get_node_or_null(elevator_path) as MeshInstance3D
	_commander = get_node_or_null(commander_path) as CharacterBody3D
	_spawn_reference = get_node_or_null(spawn_reference_path) as MeshInstance3D

	if _carrier == null or _lower_floor == null or _upper_floor == null or _elevator == null or _commander == null:
		push_warning("CommanderWalkArea: Missing authored floor, elevator, or commander node")
		set_physics_process(false)
		return false

	_lower_triangles = _extract_floor_triangles(_lower_floor)
	_upper_triangles = _extract_floor_triangles(_upper_floor)
	_lower_floor_y = _get_mesh_top_y(_lower_floor)
	_upper_floor_y = _get_mesh_top_y(_upper_floor)
	_elevator_lower_position = _elevator.position
	_update_elevator_geometry()

	if _lower_triangles.is_empty() or _upper_triangles.is_empty():
		push_warning("CommanderWalkArea: An authored walkable-floor mesh has no triangles")
		set_physics_process(false)
		return false

	if _spawn_reference != null:
		_spawn_reference.visible = false

	_initialized = true
	return true


func _begin_elevator_trip() -> void:
	_elevator_moving = true
	_commander_riding = true
	_elevator_armed = false
	_stand_time_s = 0.0
	_elevator_progress = 1.0 if _elevator_at_upper else 0.0


func _update_elevator_motion(delta: float) -> void:
	var target_progress := 0.0 if _elevator_at_upper else 1.0
	var progress_speed := elevator_speed_mps / maxf(elevator_travel_m, 0.001)
	_elevator_progress = move_toward(_elevator_progress, target_progress, progress_speed * delta)
	_elevator.position = _elevator_lower_position + Vector3.UP * (elevator_travel_m * _elevator_progress)
	_update_elevator_geometry()
	if _commander_riding:
		var commander_position := _commander.position
		commander_position.y = _elevator_top_y
		_commander.position = commander_position

	if not is_equal_approx(_elevator_progress, target_progress):
		return

	_elevator_at_upper = not _elevator_at_upper
	_active_floor = FLOOR_UPPER if _elevator_at_upper else FLOOR_LOWER
	_elevator_moving = false
	_commander_riding = false


func _platform_is_at_active_floor() -> bool:
	return (_active_floor == FLOOR_UPPER) == _elevator_at_upper


func _get_lower_spawn_position() -> Vector3:
	var spawn_position := _commander.position
	if _spawn_reference != null:
		spawn_position = _carrier.to_local(_spawn_reference.global_position)
	spawn_position.y = _lower_floor_y
	if _is_walkable_floor_position(Vector2(spawn_position.x, spawn_position.z), _lower_triangles):
		return spawn_position

	# Find the closest triangle center that also has enough clearance for the
	# commander capsule when the reference is outside the lower walk area.
	var reference_xz := Vector2(spawn_position.x, spawn_position.z)
	var best_center := Vector2.ZERO
	var best_distance_squared := INF
	for triangle in _lower_triangles:
		var center := (triangle[0] + triangle[1] + triangle[2]) / 3.0
		if not _is_walkable_floor_position(center, _lower_triangles):
			continue
		var distance_squared := center.distance_squared_to(reference_xz)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_center = center
	if best_distance_squared != INF:
		return Vector3(best_center.x, _lower_floor_y, best_center.y)

	# This should only occur if the authored floor is narrower than the configured
	# walk margin everywhere.
	var first_triangle := _lower_triangles[0]
	var fallback_center := (first_triangle[0] + first_triangle[1] + first_triangle[2]) / 3.0
	return Vector3(fallback_center.x, _lower_floor_y, fallback_center.y)


func _extract_floor_triangles(mesh_instance: MeshInstance3D) -> Array[PackedVector2Array]:
	var triangles: Array[PackedVector2Array] = []
	var mesh := mesh_instance.mesh
	if mesh == null:
		return triangles

	var mesh_to_carrier := _carrier.global_transform.affine_inverse() * mesh_instance.global_transform
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for vertex_index in range(0, vertices.size() - 2, 3):
				_add_floor_triangle(triangles, vertices, vertex_index, vertex_index + 1, vertex_index + 2, mesh_to_carrier)
		else:
			for index_offset in range(0, indices.size() - 2, 3):
				_add_floor_triangle(
					triangles,
					vertices,
					indices[index_offset],
					indices[index_offset + 1],
					indices[index_offset + 2],
					mesh_to_carrier
				)
	return triangles


func _add_floor_triangle(
	triangles: Array[PackedVector2Array],
	vertices: PackedVector3Array,
	a_index: int,
	b_index: int,
	c_index: int,
	mesh_to_carrier: Transform3D
) -> void:
	var a := mesh_to_carrier * vertices[a_index]
	var b := mesh_to_carrier * vertices[b_index]
	var c := mesh_to_carrier * vertices[c_index]
	var triangle := PackedVector2Array([
		Vector2(a.x, a.z),
		Vector2(b.x, b.z),
		Vector2(c.x, c.z),
	])
	if absf(_triangle_area_2d(triangle[0], triangle[1], triangle[2])) > 0.00001:
		triangles.append(triangle)


func _is_point_on_floor(point: Vector2, triangles: Array[PackedVector2Array]) -> bool:
	for triangle in triangles:
		if Geometry2D.is_point_in_polygon(point, triangle):
			return true
	return false


func _is_walkable_floor_position(point: Vector2, triangles: Array[PackedVector2Array]) -> bool:
	if not _is_point_on_floor(point, triangles):
		return false
	if walk_edge_margin_m <= 0.0:
		return true
	for offset in [
		Vector2(walk_edge_margin_m, 0.0),
		Vector2(-walk_edge_margin_m, 0.0),
		Vector2(0.0, walk_edge_margin_m),
		Vector2(0.0, -walk_edge_margin_m),
	]:
		var clearance_point: Vector2 = point + (offset as Vector2)
		if not _is_point_on_floor(clearance_point, triangles) and not (
			_platform_is_at_active_floor() and _is_inside_elevator_footprint_xz(clearance_point)
		):
			return false
	return true


func _triangle_area_2d(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


func _get_mesh_top_y(mesh_instance: MeshInstance3D) -> float:
	var top_y := -INF
	var mesh := mesh_instance.mesh
	if mesh == null:
		return 0.0
	var mesh_to_carrier := _carrier.global_transform.affine_inverse() * mesh_instance.global_transform
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			top_y = maxf(top_y, (mesh_to_carrier * vertex).y)
	return top_y if top_y != -INF else 0.0


func _update_elevator_geometry() -> void:
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	var top_y := -INF
	var mesh := _elevator.mesh
	if mesh == null:
		return

	var mesh_to_carrier := _carrier.global_transform.affine_inverse() * _elevator.global_transform
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point := mesh_to_carrier * vertex
			min_x = minf(min_x, point.x)
			min_z = minf(min_z, point.z)
			max_x = maxf(max_x, point.x)
			max_z = maxf(max_z, point.z)
			top_y = maxf(top_y, point.y)

	_elevator_min_xz = Vector2(min_x, min_z)
	_elevator_max_xz = Vector2(max_x, max_z)
	_elevator_top_y = top_y


func _is_inside_elevator_footprint(local_position: Vector3) -> bool:
	return _is_inside_elevator_footprint_xz(Vector2(local_position.x, local_position.z))


func _is_inside_elevator_footprint_xz(point: Vector2) -> bool:
	return (
		point.x >= _elevator_min_xz.x
		and point.x <= _elevator_max_xz.x
		and point.y >= _elevator_min_xz.y
		and point.y <= _elevator_max_xz.y
	)


func _is_safely_on_elevator(local_position: Vector3) -> bool:
	return (
		local_position.x >= _elevator_min_xz.x + elevator_edge_margin_m
		and local_position.x <= _elevator_max_xz.x - elevator_edge_margin_m
		and local_position.z >= _elevator_min_xz.y + elevator_edge_margin_m
		and local_position.z <= _elevator_max_xz.y - elevator_edge_margin_m
	)
