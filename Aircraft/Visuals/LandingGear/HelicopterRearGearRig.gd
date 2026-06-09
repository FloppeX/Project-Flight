extends NoseGearRigVisual
class_name HelicopterRearGearRigVisual

@export var hip_pivot_position: Vector3 = Vector3(-1.0091758, -0.02841148, 0.0)
@export var upper_leg_attach_position: Vector3 = Vector3(1.0130721, 0.0, 0.0)
@export var use_upper_leg_origin_for_attach: bool = true
@export var hip_stowed_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 90.0)
@export var counter_rotate_upper_leg_with_hip: bool = true

var _hip_pivot: Node3D
var _base_hip_rotation: Vector3 = Vector3.ZERO


func _build_runtime_hierarchy() -> void:
	_hip_pivot = _make_pivot("GearHipPivot", hip_pivot_position, self)
	_front_pivot = _make_pivot("UpperLegCounterPivot", _get_upper_leg_attach_position(), _hip_pivot)
	_lower_leg_slide = _make_pivot("LowerLegSlide", Vector3.ZERO, _front_pivot)
	_linkage_pivot = _make_pivot("RotationLinkagePivot", linkage_pivot_position, _lower_leg_slide)
	_connector_pivot = _make_pivot("LowerConnectorArmPivot", Vector3.ZERO, _linkage_pivot)
	_wheel_pivot = _make_pivot("WheelPivot", wheel_pivot_position - linkage_pivot_position, _connector_pivot)

	_reparent_part("GearHip", _hip_pivot)
	_reparent_part("UpperLeg", _front_pivot)
	_reparent_part("LowerLeg", _lower_leg_slide)
	_reparent_part("RotationLinkage", _linkage_pivot)
	_reparent_part("LowerConnectorArm", _connector_pivot)
	_reparent_part("WheelAndAxle", _wheel_pivot)

	_base_hip_rotation = _hip_pivot.rotation
	_base_front_position = _front_pivot.position
	_base_front_rotation = _front_pivot.rotation
	_base_linkage_rotation = _linkage_pivot.rotation
	_base_connector_rotation = _connector_pivot.rotation
	_base_wheel_rotation = _wheel_pivot.rotation
	_base_slide_position = _lower_leg_slide.position


func _get_upper_leg_attach_position() -> Vector3:
	if not use_upper_leg_origin_for_attach:
		return upper_leg_attach_position
	var upper_leg := _find_child_recursive(_gear_model, "UpperLeg") as Node3D
	if upper_leg == null:
		return upper_leg_attach_position
	var upper_leg_root_space := _get_transform_to_ancestor(upper_leg, self)
	var hip_root_space := _get_transform_to_ancestor(_hip_pivot, self)
	return hip_root_space.affine_inverse() * upper_leg_root_space.origin


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

	var hip_rotation := _deg_vec_to_rad(hip_stowed_rotation_degrees) * main_rotation_alpha
	var upper_leg_counter_rotation := -hip_rotation if counter_rotate_upper_leg_with_hip else Vector3.ZERO
	_hip_pivot.rotation = _base_hip_rotation + hip_rotation
	_front_pivot.position = _base_front_position - axis * upper_leg_offset
	_front_pivot.rotation = _base_front_rotation + upper_leg_counter_rotation + _deg_vec_to_rad(stowed_rotation_degrees) * main_rotation_alpha
	_lower_leg_slide.position = _base_slide_position + axis * lower_leg_offset
	_linkage_pivot.rotation = _base_linkage_rotation + Vector3(0.0, steering_yaw, 0.0) + _deg_vec_to_rad(linkage_compression_rotation_degrees) * compression_alpha + _deg_vec_to_rad(linkage_stowed_rotation_degrees) * tuck_alpha
	_connector_pivot.rotation = _base_connector_rotation + _deg_vec_to_rad(connector_compression_rotation_degrees) * compression_alpha + _deg_vec_to_rad(connector_stowed_rotation_degrees) * tuck_alpha
	_wheel_pivot.rotation = _base_wheel_rotation

	visible = deploy_progress > 0.0 or not hide_when_stowed
