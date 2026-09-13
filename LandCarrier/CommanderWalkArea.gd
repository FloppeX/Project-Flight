extends Node3D
class_name CommanderWalkArea

@export var lower_floor_path: NodePath = NodePath("../CarrierModel/superstructure floor lower")
@export var upper_floor_path: NodePath = NodePath("../CarrierModel/superstructure floor upper")
@export var elevator_path: NodePath = NodePath("../CarrierModel/Superstructure elevator")
@export var commander_path: NodePath = NodePath("../Commander")
@export var spawn_reference_path: NodePath = NodePath("../CarrierModel/human")
@export var bridge_spawn_path: NodePath
@export var elevator_travel_m: float = 5.223
@export var derive_elevator_travel_from_floors: bool = true
@export var elevator_speed_mps: float = 1.75
@export var elevator_trigger_delay_s: float = 0.35
@export var elevator_edge_margin_m: float = 0.2
@export var walk_edge_margin_m: float = 0.4
@export var railing_collision_path: NodePath = NodePath("../AirOpsElevatorRailingCollision")

var _carrier: Node3D
var _interior_walking: RefCounted
var _lower_floor: MeshInstance3D
var _upper_floor: MeshInstance3D
var _elevator: MeshInstance3D
var _commander: CharacterBody3D
var _spawn_reference: MeshInstance3D
var _railing_shapes: Array[CollisionShape3D] = []
var _commander_collision_center := Vector3(0.0, 0.9, 0.0)
var _commander_collision_half_size := Vector3(0.35, 0.55, 0.35)

var _lower_triangles: Array[PackedVector2Array] = []
var _upper_triangles: Array[PackedVector2Array] = []
var _lower_floor_y: float = 0.0
var _upper_floor_y: float = 0.0
var _elevator_lower_position: Vector3 = Vector3.ZERO
var _elevator_min_xz: Vector2 = Vector2.ZERO
var _elevator_max_xz: Vector2 = Vector2.ZERO
var _elevator_top_y: float = 0.0
var _resolved_elevator_travel_m: float = 0.0

var _initialized: bool = false
var _initial_position_resolved: bool = false
var _startup_anchor_active: bool = true
var _startup_settle_frames: int = 2
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
	if _ensure_initialized():
		_place_commander_at_initial_spawn()


func _physics_process(delta: float) -> void:
	if not _ensure_initialized():
		return

	# The carrier is a CharacterBody3D and can travel hundreds of metres while it
	# is hidden and finding its safe terrain start. Interior collision queries are
	# briefly one physics transform behind that motion, which used to walk the
	# nested Commander upward a little each frame until she reached the roof.
	# Keep her on the authored bridge start through that non-physical placement
	# and for two settled physics frames afterwards.
	if _startup_anchor_active:
		var placement_complete := true
		if _carrier.has_method("is_initial_placement_complete"):
			placement_complete = bool(_carrier.call("is_initial_placement_complete"))
		if not placement_complete:
			_place_commander_at_initial_spawn()
			return
		if _startup_settle_frames > 0:
			_place_commander_at_initial_spawn()
			_startup_settle_frames -= 1
			return
		_startup_anchor_active = false

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
		var spawn_position := _place_commander_at_initial_spawn()
		current_position = spawn_position
		desired_position = spawn_position

	if _commander_riding:
		return _constrain_elevator_rider(desired_position)
	if _interior_walking != null:
		# Stair treads determine height between decks. Interior queries use the
		# collision body's physics transform to avoid parent-motion height drift.
		var interior_result: Vector3 = _interior_walking.constrain(current_position, desired_position)
		if absf(interior_result.y - _upper_floor_y) < 0.05:
			_active_floor = FLOOR_UPPER
		elif absf(interior_result.y - _lower_floor_y) < 0.05:
			_active_floor = FLOOR_LOWER
		return interior_result

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


func _place_commander_at_initial_spawn() -> Vector3:
	_initial_position_resolved = true
	_active_floor = FLOOR_LOWER
	var spawn_position := _get_lower_spawn_position()
	_commander.position = spawn_position
	_commander.reset_physics_interpolation()
	return spawn_position


func _constrain_elevator_rider(desired: Vector3) -> Vector3:
	# Keep the capsule inside the platform as it arrives through the fixed upper
	# railing. A center-only margin could otherwise leave the rider inside a rail.
	var margin_x := maxf(elevator_edge_margin_m, _commander_collision_half_size.x)
	var margin_z := maxf(elevator_edge_margin_m, _commander_collision_half_size.z)
	return Vector3(
		clampf(desired.x, _elevator_min_xz.x + margin_x, _elevator_max_xz.x - margin_x),
		_elevator_top_y,
		clampf(desired.z, _elevator_min_xz.y + margin_z, _elevator_max_xz.y - margin_z)
	)


func _resolve_walk_movement(
	current: Vector2,
	desired: Vector2,
	floor_triangles: Array[PackedVector2Array]
) -> Vector2:
	if _is_valid_walk_position(desired, floor_triangles) and _is_railing_path_clear(current, desired):
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
	return candidate if (
		_is_valid_walk_position(candidate, floor_triangles)
		and _is_railing_path_clear(current, candidate)
	) else current


func _is_railing_path_clear(current: Vector2, desired: Vector2) -> bool:
	# Commander movement assigns position directly, bypassing move_and_slide().
	# Sweep its body clearance against the same boxes used by the physics world;
	# checking only the endpoint would let a long frame skip through a thin rail.
	var floor_y := _lower_floor_y if _active_floor == FLOOR_LOWER else _upper_floor_y
	var start := Vector3(current.x, floor_y, current.y) + _commander_collision_center
	var end := Vector3(desired.x, floor_y, desired.y) + _commander_collision_center
	for collision in _railing_shapes:
		if not is_instance_valid(collision) or collision.disabled:
			continue
		var box := collision.shape as BoxShape3D
		if box == null:
			continue
		var to_shape := collision.global_transform.affine_inverse() * _carrier.global_transform
		# Transform the upright body extents too, keeping this correct when the
		# carrier translates or rotates and when a rail is edited in the scene.
		var extent := (
			(to_shape.basis.x * _commander_collision_half_size.x).abs()
			+ (to_shape.basis.y * _commander_collision_half_size.y).abs()
			+ (to_shape.basis.z * _commander_collision_half_size.z).abs()
		)
		var half_size := box.size * 0.5 + extent
		var bounds := AABB(-half_size, half_size * 2.0)
		if bounds.intersects_segment(to_shape * start, to_shape * end) != null:
			return false
	return true


func _is_valid_walk_position(point: Vector2, floor_triangles: Array[PackedVector2Array]) -> bool:
	if _is_walkable_floor_position(point, floor_triangles):
		return true
	return _platform_is_at_active_floor() and _is_inside_elevator_footprint_xz(point)


func _ensure_initialized() -> bool:
	if _initialized:
		return true

	_carrier = get_parent() as Node3D
	var model := _carrier.get_node_or_null("CarrierModel")
	if model != null and model.get_script() == preload("res://LandCarrier/CarrierIslandIntegration.gd"):
		_interior_walking = preload("res://LandCarrier/CarrierInteriorWalking.gd").new(_carrier)
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
	_resolve_elevator_travel()
	_cache_railing_collision()

	if _lower_triangles.is_empty() or _upper_triangles.is_empty():
		push_warning("CommanderWalkArea: An authored walkable-floor mesh has no triangles")
		set_physics_process(false)
		return false

	if _spawn_reference != null:
		_spawn_reference.visible = false

	_initialized = true
	return true


func _cache_railing_collision() -> void:
	_railing_shapes.clear()
	var railing := get_node_or_null(railing_collision_path)
	if railing != null:
		for child in railing.get_children():
			var collision := child as CollisionShape3D
			if collision != null and collision.shape is BoxShape3D:
				_railing_shapes.append(collision)
	var body_collision := _commander.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_collision != null and body_collision.shape is CapsuleShape3D:
		var capsule := body_collision.shape as CapsuleShape3D
		_commander_collision_center = body_collision.position
		_commander_collision_half_size = Vector3(capsule.radius, capsule.height * 0.5, capsule.radius)


func _begin_elevator_trip() -> void:
	_elevator_moving = true
	_commander_riding = true
	_elevator_armed = false
	_stand_time_s = 0.0
	_elevator_progress = 1.0 if _elevator_at_upper else 0.0


func _update_elevator_motion(delta: float) -> void:
	var target_progress := 0.0 if _elevator_at_upper else 1.0
	var progress_speed := elevator_speed_mps / maxf(_resolved_elevator_travel_m, 0.001)
	_elevator_progress = move_toward(_elevator_progress, target_progress, progress_speed * delta)
	_elevator.position = _elevator_lower_position \
		+ Vector3.UP * (_resolved_elevator_travel_m * _elevator_progress)
	_update_elevator_geometry()
	if _commander_riding:
		_commander.position = _constrain_elevator_rider(_commander.position)

	if not is_equal_approx(_elevator_progress, target_progress):
		return

	_elevator_at_upper = not _elevator_at_upper
	_active_floor = FLOOR_UPPER if _elevator_at_upper else FLOOR_LOWER
	_elevator_moving = false
	_commander_riding = false


func _platform_is_at_active_floor() -> bool:
	return (_active_floor == FLOOR_UPPER) == _elevator_at_upper


func _get_lower_spawn_position() -> Vector3:
	# Explicit game-authored start takes priority over imported modelling references.
	var bridge_spawn := get_node_or_null(bridge_spawn_path) as Node3D if not bridge_spawn_path.is_empty() else null
	if bridge_spawn != null:
		var bridge_position := _carrier.to_local(bridge_spawn.global_position)
		bridge_position.y = _lower_floor_y
		if _is_walkable_floor_position(Vector2(bridge_position.x, bridge_position.z), _lower_triangles):
			return bridge_position
	var fallback_reference := _commander.position
	if _spawn_reference != null:
		var reference_position := _carrier.to_local(_spawn_reference.global_position)
		reference_position.y = _lower_floor_y
		fallback_reference = reference_position
		if _is_walkable_floor_position(
			Vector2(reference_position.x, reference_position.z),
			_lower_triangles
		):
			return reference_position

	# Imported reference markers can move outside their companion floor when a
	# modeller rescales the bridge. Preserve the scene-authored Commander start
	# when it still lies on the current floor instead of snapping to an arbitrary
	# triangle center.
	var commander_position := _commander.position
	commander_position.y = _lower_floor_y
	if _is_walkable_floor_position(
		Vector2(commander_position.x, commander_position.z),
		_lower_triangles
	):
		return commander_position

	# Find the closest triangle center that also has enough clearance for the
	# commander capsule when the reference is outside the lower walk area.
	var reference_xz := Vector2(fallback_reference.x, fallback_reference.z)
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


func _resolve_elevator_travel() -> void:
	_resolved_elevator_travel_m = maxf(elevator_travel_m, 0.001)
	if not derive_elevator_travel_from_floors:
		return
	var geometry_travel := _upper_floor_y - _elevator_top_y
	if geometry_travel <= 0.001:
		push_warning(
			"CommanderWalkArea: Could not derive positive bridge elevator travel; "
			+ "using authored %.3f m" % elevator_travel_m
		)
		return
	_resolved_elevator_travel_m = geometry_travel


func get_resolved_elevator_travel_m() -> float:
	if not _ensure_initialized():
		return maxf(elevator_travel_m, 0.001)
	return _resolved_elevator_travel_m


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
		absf(local_position.y - _elevator_top_y) < 0.25
		and local_position.x >= _elevator_min_xz.x + elevator_edge_margin_m
		and local_position.x <= _elevator_max_xz.x - elevator_edge_margin_m
		and local_position.z >= _elevator_min_xz.y + elevator_edge_margin_m
		and local_position.z <= _elevator_max_xz.y - elevator_edge_margin_m
	)
