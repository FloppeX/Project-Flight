extends Node3D
class_name NoseGearRigVisual

@export var gear_model_path: NodePath = NodePath("Aircraft gear new")
@export var landing_gear_module_path: NodePath = NodePath("../LandingGear")
@export var steering_module_path: NodePath = NodePath("../Steering")
@export var steering_enabled: bool = true
@export var gear_index: int = 0

@export var front_pivot_position: Vector3 = Vector3(0.0, 0.0326252, 0.00375247)
@export var linkage_pivot_position: Vector3 = Vector3(0.0, -0.70711875, 0.00375247)
@export var wheel_pivot_position: Vector3 = Vector3(0.0, -0.9817924, 0.00375247)

@export var stowed_rotation_degrees: Vector3 = Vector3(90.0, 0.0, 0.0)
@export var stowed_rotation_direction: float = 1.0
@export var compression_axis: Vector3 = Vector3.UP
@export var max_visual_compression_m: float = 0.28
@export var max_visual_extension_m: float = 0.06
@export var visual_compression_response_s: float = 0.08
@export var visual_rebound_response_s: float = 0.14
@export var fallback_wheel_contact_radius_m: float = 0.2
@export var linkage_stowed_rotation_degrees: Vector3 = Vector3.ZERO
@export var connector_stowed_rotation_degrees: Vector3 = Vector3(90.0, 0.0, 0.0)
@export_range(0.05, 0.95, 0.01) var stow_tuck_phase: float = 0.45
@export var stowed_lower_leg_retraction_m: float = 0.28

@export var hide_when_stowed: bool = true

var _gear_model: Node3D
var _landing_gear_module: Node
var _steering_module: Node
var _front_pivot: Node3D
var _lower_leg_slide: Node3D
var _linkage_pivot: Node3D
var _connector_pivot: Node3D
var _wheel_pivot: Node3D
var _base_front_rotation: Vector3 = Vector3.ZERO
var _base_linkage_rotation: Vector3 = Vector3.ZERO
var _base_connector_rotation: Vector3 = Vector3.ZERO
var _base_wheel_rotation: Vector3 = Vector3.ZERO
var _base_front_position: Vector3 = Vector3.ZERO
var _base_slide_position: Vector3 = Vector3.ZERO
var _rest_wheel_axis_coordinate: float = 0.0
var _wheel_contact_radius_m: float = 0.2
var _visual_compression_m: float = 0.0
var _rig_ready: bool = false

func _ready() -> void:
	_gear_model = get_node_or_null(gear_model_path) as Node3D
	_landing_gear_module = get_node_or_null(landing_gear_module_path)
	_steering_module = get_node_or_null(steering_module_path)
	if _gear_model == null:
		push_warning("NoseGearRigVisual could not find gear model at %s" % [gear_model_path])
		return
	call_deferred("_finish_setup")

func _finish_setup() -> void:
	_build_runtime_hierarchy()
	_cache_wheel_contact_geometry()
	_rig_ready = true
	_update_pose()

func _physics_process(delta: float) -> void:
	if not _rig_ready:
		return
	# The aircraft detail budget may skip this purely visual pose calculation,
	# but it must never change this rig's visibility or transform directly. The
	# landing-gear animation remains the sole authority for stowed/deployed pose.
	if not _visual_budget_allows_update():
		return
	_update_pose(delta)


func _visual_budget_allows_update() -> bool:
	var aircraft_root := get_parent()
	if aircraft_root == null or not aircraft_root.has_meta("visual_budget_ai_detail_enabled"):
		return true
	return bool(aircraft_root.get_meta("visual_budget_ai_detail_enabled", true))

func _build_runtime_hierarchy() -> void:
	_front_pivot = _make_pivot("FrontGearPivot", front_pivot_position, self)
	_lower_leg_slide = _make_pivot("LowerLegSlide", Vector3.ZERO, _front_pivot)
	_linkage_pivot = _make_pivot("RotationLinkagePivot", linkage_pivot_position, _lower_leg_slide)
	_connector_pivot = _make_pivot("LowerConnectorArmPivot", Vector3.ZERO, _linkage_pivot)
	_wheel_pivot = _make_pivot("WheelPivot", wheel_pivot_position - linkage_pivot_position, _connector_pivot)

	_reparent_part("UpperLeg", _front_pivot)
	_reparent_part("LowerLeg", _lower_leg_slide)
	_reparent_part("RotationLinkage", _linkage_pivot)
	_reparent_part("LowerConnectorArm", _connector_pivot)
	_reparent_part("WheelAndAxle", _wheel_pivot)

	_base_front_position = _front_pivot.position
	_base_front_rotation = _front_pivot.rotation
	_base_linkage_rotation = _linkage_pivot.rotation
	_base_connector_rotation = _connector_pivot.rotation
	_base_wheel_rotation = _wheel_pivot.rotation
	_base_slide_position = _lower_leg_slide.position

func _make_pivot(node_name: String, local_position: Vector3, parent_node: Node) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	parent_node.add_child(pivot)
	pivot.owner = owner
	pivot.position = local_position
	return pivot

func _reparent_part(part_name: String, new_parent: Node3D) -> void:
	var part := _find_child_recursive(_gear_model, part_name) as Node3D
	if part == null:
		push_warning("NoseGearRigVisual could not find gear part '%s'" % [part_name])
		return
	var root_space_transform := _get_transform_to_ancestor(part, self)
	var parent_root_space_transform := _get_transform_to_ancestor(new_parent, self)
	var old_parent := part.get_parent()
	if old_parent:
		old_parent.remove_child(part)
	new_parent.add_child(part)
	part.owner = owner
	part.transform = parent_root_space_transform.affine_inverse() * root_space_transform

func _find_child_recursive(root: Node, wanted_name: String) -> Node:
	if root.name == wanted_name:
		return root
	for child in root.get_children():
		var found := _find_child_recursive(child, wanted_name)
		if found:
			return found
	return null

func _get_transform_to_ancestor(node: Node3D, ancestor: Node) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != null and parent != ancestor:
		if parent is Node3D:
			result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result

func _update_pose(delta: float = -1.0) -> void:
	var deploy_progress := _read_deploy_progress()
	var stow_alpha := 1.0 - deploy_progress
	var tuck_alpha := clampf(stow_alpha / maxf(stow_tuck_phase, 0.001), 0.0, 1.0)
	var main_rotation_alpha := clampf((stow_alpha - stow_tuck_phase) / maxf(1.0 - stow_tuck_phase, 0.001), 0.0, 1.0)
	var compression := _update_visual_compression(delta, deploy_progress)
	var steering_yaw := _read_steering_yaw()
	var axis := _compression_axis_normalized()
	var lower_leg_offset := compression + stowed_lower_leg_retraction_m * tuck_alpha

	# Compression is a pure oleo-strut telescope: the upper leg remains attached
	# to the airframe while the complete lower assembly slides into it.
	_front_pivot.position = _base_front_position
	_front_pivot.rotation = _base_front_rotation + _deg_vec_to_rad(stowed_rotation_degrees) * stowed_rotation_direction * main_rotation_alpha
	_lower_leg_slide.position = _base_slide_position + axis * lower_leg_offset
	_linkage_pivot.rotation = _base_linkage_rotation + Vector3(0.0, steering_yaw, 0.0) + _deg_vec_to_rad(linkage_stowed_rotation_degrees) * tuck_alpha
	_connector_pivot.rotation = _base_connector_rotation + _deg_vec_to_rad(connector_stowed_rotation_degrees) * tuck_alpha
	_wheel_pivot.rotation = _base_wheel_rotation

	visible = deploy_progress > 0.0 or not hide_when_stowed

func _update_visual_compression(delta: float, deploy_progress: float) -> float:
	var deploy_alpha := clampf(deploy_progress, 0.0, 1.0)
	var contact_target := _read_contact_aligned_compression()
	if not is_nan(contact_target):
		# Do not smooth a supported wheel away from the surface. Suspension motion
		# already follows the aircraft body and the measured deck contact.
		_visual_compression_m = contact_target * deploy_alpha
		return _visual_compression_m
	var target := _read_compression() * deploy_alpha
	if delta <= 0.0:
		_visual_compression_m = target
		return _visual_compression_m
	var response_s := visual_compression_response_s
	if target < _visual_compression_m:
		response_s = visual_rebound_response_s
	var alpha := 1.0
	if response_s > 0.0:
		alpha = 1.0 - exp(-delta / response_s)
	_visual_compression_m = lerpf(_visual_compression_m, target, clampf(alpha, 0.0, 1.0))
	return _visual_compression_m


func _cache_wheel_contact_geometry() -> void:
	var axis := _compression_axis_normalized()
	_rest_wheel_axis_coordinate = wheel_pivot_position.dot(axis)
	_wheel_contact_radius_m = maxf(fallback_wheel_contact_radius_m, 0.001)
	if not is_instance_valid(_wheel_pivot):
		return

	var bounds := {
		"found": false,
		"min_axis": INF,
		"max_axis": -INF,
	}
	_accumulate_wheel_axis_bounds(_wheel_pivot, axis, bounds)
	if not bool(bounds["found"]):
		return
	var min_axis: float = float(bounds["min_axis"])
	var max_axis: float = float(bounds["max_axis"])
	_rest_wheel_axis_coordinate = (min_axis + max_axis) * 0.5
	_wheel_contact_radius_m = maxf((max_axis - min_axis) * 0.5, 0.001)


func _accumulate_wheel_axis_bounds(node: Node, axis: Vector3, bounds: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var local_aabb := mesh_instance.get_aabb()
		var rig_transform := _get_transform_to_ancestor(mesh_instance, self)
		for x_side in range(2):
			for y_side in range(2):
				for z_side in range(2):
					var corner := local_aabb.position + Vector3(
						local_aabb.size.x * float(x_side),
						local_aabb.size.y * float(y_side),
						local_aabb.size.z * float(z_side)
					)
					var axis_coordinate := (rig_transform * corner).dot(axis)
					bounds["found"] = true
					bounds["min_axis"] = minf(float(bounds["min_axis"]), axis_coordinate)
					bounds["max_axis"] = maxf(float(bounds["max_axis"]), axis_coordinate)
	for child in node.get_children():
		_accumulate_wheel_axis_bounds(child, axis, bounds)


func _read_contact_aligned_compression() -> float:
	if _landing_gear_module == null or not is_instance_valid(_landing_gear_module):
		return NAN
	var contacts: Variant = _landing_gear_module.get("gear_has_contact")
	var points: Variant = _landing_gear_module.get("gear_contact_points")
	var normals: Variant = _landing_gear_module.get("gear_contact_normals")
	if typeof(contacts) != TYPE_ARRAY or typeof(points) != TYPE_ARRAY or typeof(normals) != TYPE_ARRAY:
		return NAN
	if gear_index < 0 or gear_index >= contacts.size() or gear_index >= points.size() or gear_index >= normals.size():
		return NAN
	if not bool(contacts[gear_index]):
		return NAN
	var contact_point: Variant = points[gear_index]
	var contact_normal_value: Variant = normals[gear_index]
	if typeof(contact_point) != TYPE_VECTOR3 or typeof(contact_normal_value) != TYPE_VECTOR3:
		return NAN
	var contact_normal := contact_normal_value as Vector3
	if contact_normal.length_squared() <= 0.000001:
		return NAN
	contact_normal = contact_normal.normalized()

	# Work in rig-local metres so scaled/mirrored gear instances retain the
	# authored tire radius and strut travel.
	var local_normal := (global_transform.basis.inverse() * contact_normal).normalized()
	var target_wheel_center_local := to_local(contact_point as Vector3) + local_normal * _wheel_contact_radius_m
	var target_axis_coordinate := target_wheel_center_local.dot(_compression_axis_normalized())
	return clampf(
		target_axis_coordinate - _rest_wheel_axis_coordinate,
		-maxf(max_visual_extension_m, 0.0),
		maxf(max_visual_compression_m, 0.0)
	)

func _compression_axis_normalized() -> Vector3:
	if compression_axis.length_squared() <= 0.000001:
		return Vector3.UP
	return compression_axis.normalized()

func _read_deploy_progress() -> float:
	if _landing_gear_module == null or not is_instance_valid(_landing_gear_module):
		return 1.0
	var progress: Variant = _landing_gear_module.get("_gear_animation_progress")
	if typeof(progress) == TYPE_FLOAT or typeof(progress) == TYPE_INT:
		return clampf(float(progress), 0.0, 1.0)
	var deployed: Variant = _landing_gear_module.get("is_deployed")
	return 1.0 if bool(deployed) else 0.0

func _read_compression() -> float:
	if _landing_gear_module == null or not is_instance_valid(_landing_gear_module):
		return 0.0
	var compressions: Variant = _landing_gear_module.get("gear_compressions")
	if typeof(compressions) != TYPE_ARRAY:
		return 0.0
	if gear_index < 0 or gear_index >= compressions.size():
		return 0.0
	var value: Variant = compressions[gear_index]
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return clampf(float(value), 0.0, max_visual_compression_m)
	return 0.0

func _read_steering_yaw() -> float:
	if not steering_enabled:
		return 0.0
	if _steering_module == null or not is_instance_valid(_steering_module):
		return 0.0
	var axis_value: Variant = _steering_module.get("axis_y")
	var max_angle_value: Variant = _steering_module.get("max_nose_wheel_angle")
	if not (typeof(axis_value) == TYPE_FLOAT or typeof(axis_value) == TYPE_INT):
		return 0.0
	var max_angle_deg := 45.0
	if typeof(max_angle_value) == TYPE_FLOAT or typeof(max_angle_value) == TYPE_INT:
		max_angle_deg = float(max_angle_value)
	return deg_to_rad(float(axis_value) * max_angle_deg)

func _deg_vec_to_rad(v: Vector3) -> Vector3:
	return Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z))
