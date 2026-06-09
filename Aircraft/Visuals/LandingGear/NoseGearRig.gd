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
@export var compression_visual_scale: float = 0.75
@export var upper_leg_compression_visual_scale: float = 0.25
@export var max_visual_compression_m: float = 0.28
@export var visual_compression_response_s: float = 0.08
@export var visual_rebound_response_s: float = 0.14
@export var linkage_compression_rotation_degrees: Vector3 = Vector3(0.0, 0.0, -12.0)
@export var connector_compression_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 16.0)
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
	_rig_ready = true
	_update_pose()

func _physics_process(delta: float) -> void:
	if not _rig_ready:
		return
	_update_pose(delta)

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
	var compression_alpha := 0.0
	if max_visual_compression_m > 0.0:
		compression_alpha = clampf(compression / max_visual_compression_m, 0.0, 1.0)
	var steering_yaw := _read_steering_yaw()
	var axis := _compression_axis_normalized()
	var upper_leg_offset := compression * maxf(upper_leg_compression_visual_scale, 0.0)
	var lower_leg_offset := compression * maxf(compression_visual_scale, 0.0) + stowed_lower_leg_retraction_m * tuck_alpha

	_front_pivot.position = _base_front_position - axis * upper_leg_offset
	_front_pivot.rotation = _base_front_rotation + _deg_vec_to_rad(stowed_rotation_degrees) * stowed_rotation_direction * main_rotation_alpha
	_lower_leg_slide.position = _base_slide_position + axis * lower_leg_offset
	_linkage_pivot.rotation = _base_linkage_rotation + Vector3(0.0, steering_yaw, 0.0) + _deg_vec_to_rad(linkage_compression_rotation_degrees) * compression_alpha + _deg_vec_to_rad(linkage_stowed_rotation_degrees) * tuck_alpha
	_connector_pivot.rotation = _base_connector_rotation + _deg_vec_to_rad(connector_compression_rotation_degrees) * compression_alpha + _deg_vec_to_rad(connector_stowed_rotation_degrees) * tuck_alpha
	_wheel_pivot.rotation = _base_wheel_rotation

	visible = deploy_progress > 0.0 or not hide_when_stowed

func _update_visual_compression(delta: float, deploy_progress: float) -> float:
	var target := _read_compression() * clampf(deploy_progress, 0.0, 1.0)
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
