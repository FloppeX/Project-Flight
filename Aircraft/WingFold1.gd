extends Node
class_name WingFold1

## Double-fold wing animation for Aircraft_1, inspired by the Fairey Gannet.
## The middle panels fold upward and inward while the outer panels apply a
## stronger counter-rotation at the second hinge, forming a compact Z profile.
##
## The imported wing objects do not have hinge-centred origins, so the hinge
## positions are derived from their authored mesh edges and the rotations are
## applied as transforms about those points in aircraft-model space.

@export var middle_fold_angle_deg: float = 130.0
@export var outer_fold_angle_deg: float = 180.0
@export var fold_duration_s: float = 3.0
@export var hinge_axis: Vector3 = Vector3.BACK
@export var stable_poll_interval_s: float = 0.2

@export var middle_left_path: NodePath = NodePath("../aircraft_1/wing middle left")
@export var middle_right_path: NodePath = NodePath("../aircraft_1/wing middle right")
@export var outer_left_path: NodePath = NodePath("../aircraft_1/wing outer left")
@export var outer_right_path: NodePath = NodePath("../aircraft_1/wing outer right")
@export var broad_wing_collider_path: NodePath = NodePath("../WingCollider")

var _left_middle: MeshInstance3D
var _right_middle: MeshInstance3D
var _left_wing: Node3D
var _right_wing: Node3D
var _broad_wing_collider: CollisionShape3D

var _left_middle_rest: Transform3D
var _right_middle_rest: Transform3D
var _left_outer_rest: Transform3D
var _right_outer_rest: Transform3D

var _left_inner_hinge: Vector3
var _right_inner_hinge: Vector3
var _left_outer_hinge: Vector3
var _right_outer_hinge: Vector3

var _fold_t: float = 0.0
var _snapped: bool = false
var _stable_poll_timer_s: float = 0.0


func _ready() -> void:
	_broad_wing_collider = get_node_or_null(broad_wing_collider_path) as CollisionShape3D
	_left_middle = get_node_or_null(middle_left_path) as MeshInstance3D
	_right_middle = get_node_or_null(middle_right_path) as MeshInstance3D
	_left_wing = get_node_or_null(outer_left_path) as Node3D
	_right_wing = get_node_or_null(outer_right_path) as Node3D
	var left_outer := _left_wing as MeshInstance3D
	var right_outer := _right_wing as MeshInstance3D
	if _left_middle == null or _right_middle == null or left_outer == null or right_outer == null:
		push_warning("[WingFold1] Expected all four Aircraft_1 wing mesh nodes.")
		set_process(false)
		return

	_left_middle_rest = _left_middle.transform
	_right_middle_rest = _right_middle.transform
	_left_outer_rest = left_outer.transform
	_right_outer_rest = right_outer.transform

	# The Gannet-style root hinge sits on the wing's upper skin. Keeping this
	# pivot above the section stops the middle panel from rolling through the
	# fuselage as it starts to fold.
	_left_inner_hinge = _edge_center_in_model_space(_left_middle, true, true)
	_right_inner_hinge = _edge_center_in_model_space(_right_middle, false, true)
	# The counter-fold runs along the lower skin at the middle/outer seam.
	_left_outer_hinge = (
		_edge_center_in_model_space(_left_middle, false, false, true)
		+ _edge_center_in_model_space(left_outer, true, false, true)
	) * 0.5
	_right_outer_hinge = (
		_edge_center_in_model_space(_right_middle, true, false, true)
		+ _edge_center_in_model_space(right_outer, false, false, true)
	) * 0.5

	# Livery.gd projects all split meshes in one shared unfolded coordinate space.
	# Keep the pattern fixed to the authored wing surfaces while they fold.
	_left_middle.set_meta("livery_rest_transform_local", _left_middle_rest)
	_right_middle.set_meta("livery_rest_transform_local", _right_middle_rest)
	_left_wing.set_meta("livery_rest_transform_local", _left_outer_rest)
	_right_wing.set_meta("livery_rest_transform_local", _right_outer_rest)


func _process(delta: float) -> void:
	if _left_wing == null or _right_wing == null:
		return

	var stable := _snapped and (_fold_t <= 0.0 or _fold_t >= 1.0)
	if stable:
		_stable_poll_timer_s -= delta
		if _stable_poll_timer_s > 0.0:
			return
		_stable_poll_timer_s = maxf(stable_poll_interval_s, 0.02)

	var aircraft := get_parent()
	var braked := aircraft.has_meta("parking_brake") and bool(aircraft.get_meta("parking_brake"))
	var transport := aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode"))
	var should_fold := braked or transport

	if not _snapped:
		_snapped = true
		if should_fold:
			_fold_t = 1.0

	var previous_fold_t := _fold_t
	var target := 1.0 if should_fold else 0.0
	_fold_t = move_toward(_fold_t, target, delta / maxf(fold_duration_s, 0.01))
	if not is_equal_approx(previous_fold_t, _fold_t) or not stable:
		_apply_fold_pose(_smooth(_fold_t))


func set_fold_fraction_immediate(fold_fraction: float) -> void:
	_fold_t = clampf(fold_fraction, 0.0, 1.0)
	_snapped = true
	_apply_fold_pose(_smooth(_fold_t))


func prepare_technical_index_preview() -> bool:
	_ready()
	if _left_middle == null or _right_middle == null or _left_wing == null or _right_wing == null:
		return false
	set_fold_fraction_immediate(0.0)
	return true


func set_technical_index_preview_fraction(fold_fraction: float) -> void:
	set_fold_fraction_immediate(fold_fraction)


func get_technical_index_preview_fraction() -> float:
	return _fold_t


func get_technical_index_preview_duration() -> float:
	return maxf(fold_duration_s, 0.01)


func get_technical_index_preview_kind() -> StringName:
	return &"wings"


func _apply_fold_pose(fold_amount: float) -> void:
	var axis := hinge_axis.normalized()
	if axis.length_squared() <= 0.0001:
		axis = Vector3.BACK
	var middle_angle := deg_to_rad(middle_fold_angle_deg) * fold_amount
	var outer_angle := deg_to_rad(outer_fold_angle_deg) * fold_amount

	# Positive X is the left side of this model. Mirrored signs make both
	# middle panels rise, while the opposite outer rotations keep the tips
	# nearly horizontal above them.
	var left_middle_fold := _rotation_about_hinge(_left_inner_hinge, axis, middle_angle)
	var right_middle_fold := _rotation_about_hinge(_right_inner_hinge, axis, -middle_angle)
	var left_outer_counter := _rotation_about_hinge(_left_outer_hinge, axis, -outer_angle)
	var right_outer_counter := _rotation_about_hinge(_right_outer_hinge, axis, outer_angle)

	_left_middle.transform = left_middle_fold * _left_middle_rest
	_right_middle.transform = right_middle_fold * _right_middle_rest
	_left_wing.transform = left_middle_fold * left_outer_counter * _left_outer_rest
	_right_wing.transform = right_middle_fold * right_outer_counter * _right_outer_rest
	_set_broad_wing_collision_folded(_fold_t > 0.0)


func _set_broad_wing_collision_folded(is_folded_or_moving: bool) -> void:
	# The authored WingCollider is one full-span box, so it cannot represent the
	# stacked Z shape. Keep it out of the physics world until the wings are fully
	# deployed. Localized wing colliders supersede it in every pose.
	if is_instance_valid(_broad_wing_collider):
		_broad_wing_collider.disabled = _has_localized_wing_colliders() or is_folded_or_moving


func _has_localized_wing_colliders() -> bool:
	var aircraft := get_parent()
	return (
		aircraft.get_node_or_null("LeftWingDamageCollider") is CollisionShape3D
		and aircraft.get_node_or_null("RightWingDamageCollider") is CollisionShape3D
	)


func _rotation_about_hinge(pivot: Vector3, axis: Vector3, angle: float) -> Transform3D:
	return (
		Transform3D(Basis.IDENTITY, pivot)
		* Transform3D(Basis(axis, angle), Vector3.ZERO)
		* Transform3D(Basis.IDENTITY, -pivot)
	)


func _edge_center_in_model_space(
	wing: MeshInstance3D,
	use_min_x: bool,
	use_top_y: bool = false,
	use_bottom_y: bool = false
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
	var edge_bottom_y := INF
	for point in points:
		if absf(point.x - edge_x) <= edge_tolerance:
			edge_sum += point
			edge_count += 1
			edge_top_y = maxf(edge_top_y, point.y)
			edge_bottom_y = minf(edge_bottom_y, point.y)
	if edge_count == 0:
		return Vector3(edge_x, wing.position.y, wing.position.z)
	var edge_center := edge_sum / float(edge_count)
	if use_top_y:
		edge_center.y = edge_top_y
	elif use_bottom_y:
		edge_center.y = edge_bottom_y
	return edge_center


func _smooth(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)
