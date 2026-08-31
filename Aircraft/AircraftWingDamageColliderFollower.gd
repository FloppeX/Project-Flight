extends Node
class_name AircraftWingDamageColliderFollower

## Keeps the left/right localized-damage shapes aligned with folding wing
## meshes. A single mesh preserves the authored collider offset and rotates it
## with that panel. Multi-panel wings use a compact aircraft-local bounding box
## so one damage zone can continue covering the complete folded assembly.

@export var left_collider_path: NodePath = NodePath("../LeftWingDamageCollider")
@export var right_collider_path: NodePath = NodePath("../RightWingDamageCollider")
@export var left_visual_paths: Array[NodePath] = []
@export var right_visual_paths: Array[NodePath] = []
@export var fit_multi_panel_bounds: bool = false
@export var multi_panel_padding_m: Vector3 = Vector3(0.12, 0.12, 0.12)

var _aircraft: Node3D
var _left_collider: CollisionShape3D
var _right_collider: CollisionShape3D
var _left_visuals: Array[MeshInstance3D] = []
var _right_visuals: Array[MeshInstance3D] = []
var _left_collider_in_anchor: Transform3D
var _right_collider_in_anchor: Transform3D


func _ready() -> void:
	_aircraft = get_parent() as Node3D
	if _aircraft == null:
		set_process(false)
		return
	process_priority = 100
	_left_collider = get_node_or_null(left_collider_path) as CollisionShape3D
	_right_collider = get_node_or_null(right_collider_path) as CollisionShape3D
	_left_visuals = _resolve_visuals(left_visual_paths)
	_right_visuals = _resolve_visuals(right_visual_paths)
	if _left_collider == null or _right_collider == null \
			or _left_visuals.is_empty() or _right_visuals.is_empty():
		push_warning("[AircraftWingDamageColliderFollower] Missing wing collider or visual path")
		set_process(false)
		return
	if fit_multi_panel_bounds:
		_make_box_shape_unique(_left_collider)
		_make_box_shape_unique(_right_collider)
	else:
		_left_collider_in_anchor = (
			_transform_relative_to_ancestor(_aircraft, _left_visuals[0]).affine_inverse()
			* _left_collider.transform
		)
		_right_collider_in_anchor = (
			_transform_relative_to_ancestor(_aircraft, _right_visuals[0]).affine_inverse()
			* _right_collider.transform
		)
	_update_collider_poses()


func _process(_delta: float) -> void:
	_update_collider_poses()


func _update_collider_poses() -> void:
	if fit_multi_panel_bounds:
		_fit_collider_to_visuals(_left_collider, _left_visuals)
		_fit_collider_to_visuals(_right_collider, _right_visuals)
		return
	if is_instance_valid(_left_collider) and not _left_visuals.is_empty():
		_left_collider.transform = (
			_transform_relative_to_ancestor(_aircraft, _left_visuals[0])
			* _left_collider_in_anchor
		)
	if is_instance_valid(_right_collider) and not _right_visuals.is_empty():
		_right_collider.transform = (
			_transform_relative_to_ancestor(_aircraft, _right_visuals[0])
			* _right_collider_in_anchor
		)


func _fit_collider_to_visuals(collider: CollisionShape3D, visuals: Array[MeshInstance3D]) -> void:
	if collider == null or not is_instance_valid(collider) or not (collider.shape is BoxShape3D):
		return
	var combined := AABB()
	var has_bounds := false
	for visual in visuals:
		if visual == null or not is_instance_valid(visual) or visual.mesh == null:
			continue
		var visual_in_aircraft := _transform_relative_to_ancestor(_aircraft, visual)
		var source := visual.get_aabb()
		for x_index in range(2):
			for y_index in range(2):
				for z_index in range(2):
					var point := visual_in_aircraft * (source.position + Vector3(
						source.size.x * float(x_index),
						source.size.y * float(y_index),
						source.size.z * float(z_index)
					))
					if not has_bounds:
						combined = AABB(point, Vector3.ZERO)
						has_bounds = true
					else:
						combined = combined.expand(point)
	if not has_bounds:
		return
	var padding := multi_panel_padding_m.max(Vector3.ZERO)
	(collider.shape as BoxShape3D).size = combined.size + padding * 2.0
	collider.transform = Transform3D(Basis.IDENTITY, combined.get_center())


func _resolve_visuals(paths: Array[NodePath]) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for path in paths:
		var visual := get_node_or_null(path) as MeshInstance3D
		if visual != null:
			result.append(visual)
	return result


func _make_box_shape_unique(collider: CollisionShape3D) -> void:
	if collider == null or not (collider.shape is BoxShape3D):
		return
	collider.shape = collider.shape.duplicate()


func _transform_relative_to_ancestor(ancestor: Node3D, node: Node3D) -> Transform3D:
	if ancestor == null or node == null:
		return Transform3D.IDENTITY
	var result := Transform3D.IDENTITY
	var current := node
	while current != ancestor:
		result = current.transform * result
		current = current.get_parent() as Node3D
		if current == null:
			return Transform3D.IDENTITY
	return result
