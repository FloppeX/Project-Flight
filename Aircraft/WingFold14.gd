extends WingFold
class_name WingFold14

## Aircraft_14 uses the same fold timing, axis, controls, and triggers as
## Aircraft_2. Its imported wing nodes are rooted at the model origin rather
## than at their hinges, so this specialization rotates each wing about the
## top of its inboard intersection seam in aircraft-model space.

@export var left_wing_path: NodePath = NodePath("../aircraft_14/left wing")
@export var right_wing_path: NodePath = NodePath("../aircraft_14/right wing")
@export var left_wing_collider_path: NodePath = NodePath("../LeftWingDamageCollider")
@export var right_wing_collider_path: NodePath = NodePath("../RightWingDamageCollider")

var _left_rest_transform: Transform3D
var _right_rest_transform: Transform3D
var _left_hinge: Vector3
var _right_hinge: Vector3
var _left_wing_collider: CollisionShape3D
var _right_wing_collider: CollisionShape3D
var _left_collider_authored_rest: Transform3D
var _right_collider_authored_rest: Transform3D
var _left_collider_in_wing: Transform3D
var _right_collider_in_wing: Transform3D
var _collider_rest_cached: bool = false


func _cache_wing_nodes(warn_when_missing: bool) -> bool:
	_left_wing = get_node_or_null(left_wing_path) as MeshInstance3D
	_right_wing = get_node_or_null(right_wing_path) as MeshInstance3D
	if _left_wing == null or _right_wing == null:
		if warn_when_missing:
			push_warning("[WingFold14] Wing nodes not found — check Aircraft_14 GLB node names")
		return false

	_left_rest_transform = _left_wing.transform
	_right_rest_transform = _right_wing.transform
	_left_hinge = _edge_center_in_model_space(_left_wing as MeshInstance3D, true, true)
	_right_hinge = _edge_center_in_model_space(_right_wing as MeshInstance3D, false, true)
	_left_wing_collider = get_node_or_null(left_wing_collider_path) as CollisionShape3D
	_right_wing_collider = get_node_or_null(right_wing_collider_path) as CollisionShape3D
	if _left_wing_collider == null or _right_wing_collider == null:
		if warn_when_missing:
			push_warning("[WingFold14] Per-wing collision shapes were not found")
		return false
	if not _collider_rest_cached:
		_left_collider_authored_rest = _left_wing_collider.transform
		_right_collider_authored_rest = _right_wing_collider.transform
		_collider_rest_cached = true
	var aircraft_root := get_parent() as Node3D
	var left_wing_in_aircraft := _transform_relative_to_ancestor(aircraft_root, _left_wing)
	var right_wing_in_aircraft := _transform_relative_to_ancestor(aircraft_root, _right_wing)
	_left_collider_in_wing = left_wing_in_aircraft.affine_inverse() * _left_collider_authored_rest
	_right_collider_in_wing = right_wing_in_aircraft.affine_inverse() * _right_collider_authored_rest

	# Livery patterns must remain projected from the unfolded model pose.
	_left_wing.set_meta("livery_rest_transform_local", _left_rest_transform)
	_right_wing.set_meta("livery_rest_transform_local", _right_rest_transform)
	return true


func _apply_fold_pose(angle: float) -> void:
	var axis := fold_axis.normalized()
	if axis.length_squared() <= 0.0001:
		axis = Vector3.FORWARD

	_left_wing.transform = _rotation_about_hinge(_left_hinge, axis, angle) * _left_rest_transform
	_right_wing.transform = _rotation_about_hinge(_right_hinge, axis, -angle) * _right_rest_transform
	_update_wing_collider_poses()
	_set_broad_wing_collision_folded(_fold_t > 0.0)


func _update_wing_collider_poses() -> void:
	var aircraft_root := get_parent() as Node3D
	if aircraft_root == null:
		return
	if is_instance_valid(_left_wing_collider):
		_left_wing_collider.transform = (
			_transform_relative_to_ancestor(aircraft_root, _left_wing)
			* _left_collider_in_wing
		)
	if is_instance_valid(_right_wing_collider):
		_right_wing_collider.transform = (
			_transform_relative_to_ancestor(aircraft_root, _right_wing)
			* _right_collider_in_wing
		)


func _set_broad_wing_collision_folded(_is_folded_or_moving: bool) -> void:
	# Aircraft 14 has independent colliders that follow each folding panel. The
	# inherited full-span box is retained only for scene compatibility and must
	# stay disabled in every pose so it does not duplicate or bridge the wings.
	if is_instance_valid(_broad_wing_collider):
		_broad_wing_collider.disabled = true


func _transform_relative_to_ancestor(ancestor: Node3D, node: Node3D) -> Transform3D:
	if ancestor == null or node == null:
		return Transform3D.IDENTITY
	var result := Transform3D.IDENTITY
	var current: Node3D = node
	while current != ancestor:
		result = current.transform * result
		current = current.get_parent() as Node3D
		if current == null:
			return Transform3D.IDENTITY
	return result


func _rotation_about_hinge(pivot: Vector3, axis: Vector3, angle: float) -> Transform3D:
	return (
		Transform3D(Basis.IDENTITY, pivot)
		* Transform3D(Basis(axis, angle), Vector3.ZERO)
		* Transform3D(Basis.IDENTITY, -pivot)
	)


func _edge_center_in_model_space(
	wing: MeshInstance3D,
	use_min_x: bool,
	use_top_y: bool = false
) -> Vector3:
	var mesh := wing.mesh
	if mesh == null:
		return wing.position

	var points: Array[Vector3] = []
	var edge_x := INF if use_min_x else -INF
	var opposite_x := -INF if use_min_x else INF
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point := wing.transform * vertex
			points.append(point)
			if use_min_x:
				edge_x = minf(edge_x, point.x)
				opposite_x = maxf(opposite_x, point.x)
			else:
				edge_x = maxf(edge_x, point.x)
				opposite_x = minf(opposite_x, point.x)

	if points.is_empty():
		return wing.position
	var span := absf(opposite_x - edge_x)
	var edge_tolerance := maxf(span * 0.015, 0.002)
	var edge_sum := Vector3.ZERO
	var edge_count := 0
	var edge_top_y := -INF
	for point in points:
		if absf(point.x - edge_x) <= edge_tolerance:
			edge_sum += point
			edge_count += 1
			edge_top_y = maxf(edge_top_y, point.y)
	if edge_count == 0:
		return Vector3(edge_x, wing.position.y, wing.position.z)
	var edge_center := edge_sum / float(edge_count)
	if use_top_y:
		edge_center.y = edge_top_y
	return edge_center
