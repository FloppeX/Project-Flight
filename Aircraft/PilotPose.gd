@tool
extends Node3D
## Applies a seated, forward-looking cockpit pose to the pilot rig.
## Attach to the root node of the pilot character instance.

@export_group("Legs")
@export var upper_leg_x: float = 66.0:
	set(v):
		upper_leg_x = v
		_apply_pose()
@export var lower_leg_x: float = 58.0:
	set(v):
		lower_leg_x = v
		_apply_pose()
@export var upper_leg_spread: float = 3.0:
	set(v):
		upper_leg_spread = v
		_apply_pose()

@export_group("Torso")
@export var abdomen_pitch: float = 3.0:
	set(v):
		abdomen_pitch = v
		_apply_pose()
@export var torso_pitch: float = 2.0:
	set(v):
		torso_pitch = v
		_apply_pose()

@export_group("Shoulders")
@export var shoulder_x: float = 0.0:
	set(v):
		shoulder_x = v
		_apply_pose()
@export var shoulder_y: float = 0.0:
	set(v):
		shoulder_y = v
		_apply_pose()
@export var shoulder_z: float = 0.0:
	set(v):
		shoulder_z = v
		_apply_pose()

@export_group("Arms")
@export var upper_arm_x: float = 0.0:
	set(v):
		upper_arm_x = v
		_apply_pose()
@export var upper_arm_y: float = 0.0:
	set(v):
		upper_arm_y = v
		_apply_pose()
@export var upper_arm_z: float = 0.0:
	set(v):
		upper_arm_z = v
		_apply_pose()
@export var lower_arm_x: float = 65.0:
	set(v):
		lower_arm_x = v
		_apply_pose()
@export var lower_arm_y: float = 0.0:
	set(v):
		lower_arm_y = v
		_apply_pose()
@export var lower_arm_z: float = 0.0:
	set(v):
		lower_arm_z = v
		_apply_pose()

@export_group("Hands")
@export var wrist_x: float = 2.0:
	set(v):
		wrist_x = v
		_apply_pose()
@export var wrist_y: float = 0.0:
	set(v):
		wrist_y = v
		_apply_pose()
@export var finger_curl: float = 20.0:
	set(v):
		finger_curl = v
		_apply_pose()

@export_group("Head")
@export var neck_pitch: float = 0.0:
	set(v):
		neck_pitch = v
		_apply_pose()
@export var head_pitch: float = 0.0:
	set(v):
		head_pitch = v
		_apply_pose()

@export_group("Cockpit Visibility")
@export var hide_head_in_cockpit: bool = true
@export var cockpit_camera_path: NodePath = NodePath("../CameraCockpit/Camera3D")
@export var cockpit_hidden_mesh_names: PackedStringArray = PackedStringArray(["Pilot"])

var _skeleton: Skeleton3D = null
var _ready_done: bool = false
var _foot_links: Array[Dictionary] = []
var _cockpit_camera: Camera3D = null
var _cockpit_hidden_nodes: Array[Node3D] = []
var _last_head_hidden: bool = false


func _ready() -> void:
	_skeleton = _find_skeleton(self)
	if _skeleton == null:
		push_warning("PilotPose: No Skeleton3D found in children")
		return

	_disable_animation_players(self)
	_build_foot_links()
	_ready_done = true
	_apply_pose()
	_cache_cockpit_visibility_nodes()
	_update_head_visibility(true)
	set_process(not Engine.is_editor_hint())


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_head_visibility(false)


func _apply_pose() -> void:
	if not _ready_done or _skeleton == null:
		return

	_skeleton.reset_bone_poses()

	# Torso stays upright and facing forward.
	_set_rot("Abdomen", abdomen_pitch, 0.0, 0.0)
	_set_rot("Torso", torso_pitch, 0.0, 0.0)
	_set_rot("Shoulder.L", shoulder_x, shoulder_y, shoulder_z)
	_set_rot("Shoulder.R", shoulder_x, -shoulder_y, -shoulder_z)

	# Legs seated with a modest knee bend.
	_set_rot("UpperLeg.L", upper_leg_x, 0.0, -upper_leg_spread)
	_set_rot("UpperLeg.R", upper_leg_x, 0.0, upper_leg_spread)
	_set_rot("LowerLeg.L", lower_leg_x, 0.0, 0.0)
	_set_rot("LowerLeg.R", lower_leg_x, 0.0, 0.0)
	_reattach_feet_to_legs()

	# Arms slightly forward, relaxed shoulders.
	_set_rot("UpperArm.L", upper_arm_x, upper_arm_y, upper_arm_z)
	_set_rot("UpperArm.R", upper_arm_x, -upper_arm_y, -upper_arm_z)
	_set_rot("LowerArm.L", lower_arm_x, lower_arm_y, lower_arm_z)
	_set_rot("LowerArm.R", lower_arm_x, -lower_arm_y, -lower_arm_z)
	_set_rot("Wrist.L", wrist_x, wrist_y, 0.0)
	_set_rot("Wrist.R", wrist_x, -wrist_y, 0.0)

	# Gentle hand curl.
	for side in ["L", "R"]:
		for finger in ["Index", "Middle", "Ring", "Pinky"]:
			for joint in ["1", "2", "3", "4"]:
				_set_rot("%s%s.%s" % [finger, joint, side], finger_curl, 0.0, 0.0)
		_set_rot("Thumb1.%s" % side, finger_curl * 0.6, 10.0, 0.0)
		_set_rot("Thumb2.%s" % side, finger_curl * 0.8, 0.0, 0.0)
		_set_rot("Thumb3.%s" % side, finger_curl * 0.7, 0.0, 0.0)

	# Looking forward.
	_set_rot("Neck", neck_pitch, 0.0, 0.0)
	_set_rot("Head", head_pitch, 0.0, 0.0)


func _set_rot(bone_name: String, x_deg: float, y_deg: float, z_deg: float) -> void:
	if _skeleton == null:
		return
	var idx: int = _skeleton.find_bone(bone_name)
	if idx < 0:
		return
	var q: Quaternion = Quaternion.from_euler(Vector3(
		deg_to_rad(x_deg),
		deg_to_rad(y_deg),
		deg_to_rad(z_deg)
	))
	_skeleton.set_bone_pose_rotation(idx, q)


func _build_foot_links() -> void:
	_foot_links.clear()
	_add_foot_link("LowerLeg.L_end", "Foot.L", "PT.L")
	_add_foot_link("LowerLeg.R_end", "Foot.R", "PT.R")


func _add_foot_link(lower_leg_end_name: String, foot_name: String, pt_name: String) -> void:
	if _skeleton == null:
		return

	var lower_leg_end_idx: int = _skeleton.find_bone(lower_leg_end_name)
	var foot_idx: int = _skeleton.find_bone(foot_name)
	if lower_leg_end_idx < 0 or foot_idx < 0:
		return

	var foot_parent_idx: int = _skeleton.get_bone_parent(foot_idx)
	if foot_parent_idx < 0:
		return

	var lower_leg_end_rest: Transform3D = _skeleton.get_bone_global_pose(lower_leg_end_idx)
	var foot_rest: Transform3D = _skeleton.get_bone_global_pose(foot_idx)
	var link: Dictionary = {
		"lower_leg_end": lower_leg_end_idx,
		"foot": foot_idx,
		"foot_parent": foot_parent_idx,
		"foot_offset": lower_leg_end_rest.affine_inverse() * foot_rest
	}

	var pt_idx: int = _skeleton.find_bone(pt_name)
	if pt_idx >= 0:
		var pt_parent_idx: int = _skeleton.get_bone_parent(pt_idx)
		if pt_parent_idx >= 0:
			var pt_rest: Transform3D = _skeleton.get_bone_global_pose(pt_idx)
			link["pt"] = pt_idx
			link["pt_parent"] = pt_parent_idx
			link["pt_offset"] = foot_rest.affine_inverse() * pt_rest

	_foot_links.append(link)


func _reattach_feet_to_legs() -> void:
	if _skeleton == null:
		return

	for link_variant in _foot_links:
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link: Dictionary = link_variant

		var lower_leg_end_idx: int = int(link.get("lower_leg_end", -1))
		var foot_idx: int = int(link.get("foot", -1))
		var foot_parent_idx: int = int(link.get("foot_parent", -1))
		if lower_leg_end_idx < 0 or foot_idx < 0 or foot_parent_idx < 0:
			continue

		var foot_offset_variant: Variant = link.get("foot_offset", Transform3D.IDENTITY)
		if not (foot_offset_variant is Transform3D):
			continue
		var foot_offset: Transform3D = foot_offset_variant

		var lower_leg_end_global: Transform3D = _skeleton.get_bone_global_pose(lower_leg_end_idx)
		var target_foot_global: Transform3D = lower_leg_end_global * foot_offset
		var foot_parent_global: Transform3D = _skeleton.get_bone_global_pose(foot_parent_idx)
		var foot_local: Transform3D = foot_parent_global.affine_inverse() * target_foot_global
		_skeleton.set_bone_pose_position(foot_idx, foot_local.origin)
		_skeleton.set_bone_pose_rotation(foot_idx, foot_local.basis.get_rotation_quaternion())

		var pt_idx: int = int(link.get("pt", -1))
		var pt_parent_idx: int = int(link.get("pt_parent", -1))
		if pt_idx < 0 or pt_parent_idx < 0:
			continue

		var pt_offset_variant: Variant = link.get("pt_offset", Transform3D.IDENTITY)
		if not (pt_offset_variant is Transform3D):
			continue
		var pt_offset: Transform3D = pt_offset_variant

		var target_pt_global: Transform3D = target_foot_global * pt_offset
		var pt_parent_global: Transform3D = _skeleton.get_bone_global_pose(pt_parent_idx)
		var pt_local: Transform3D = pt_parent_global.affine_inverse() * target_pt_global
		_skeleton.set_bone_pose_position(pt_idx, pt_local.origin)
		_skeleton.set_bone_pose_rotation(pt_idx, pt_local.basis.get_rotation_quaternion())


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child_variant in node.get_children():
		var child: Node = child_variant as Node
		if child == null:
			continue
		var result: Skeleton3D = _find_skeleton(child)
		if result != null:
			return result
	return null


func _disable_animation_players(node: Node) -> void:
	if node is AnimationPlayer:
		var ap: AnimationPlayer = node as AnimationPlayer
		ap.stop()
		if not Engine.is_editor_hint():
			ap.active = false
	for child_variant in node.get_children():
		var child: Node = child_variant as Node
		if child != null:
			_disable_animation_players(child)


func _cache_cockpit_visibility_nodes() -> void:
	_cockpit_hidden_nodes.clear()
	_cockpit_camera = get_node_or_null(cockpit_camera_path) as Camera3D
	if cockpit_hidden_mesh_names.is_empty():
		return
	for child_variant in get_children():
		var child: Node = child_variant as Node
		if child == null:
			continue
		_collect_cockpit_hidden_nodes(child)


func _collect_cockpit_hidden_nodes(node: Node) -> void:
	var node_3d: Node3D = node as Node3D
	if node_3d != null and _should_hide_node_in_cockpit(node_3d):
		_cockpit_hidden_nodes.append(node_3d)
	for child_variant in node.get_children():
		var child: Node = child_variant as Node
		if child != null:
			_collect_cockpit_hidden_nodes(child)


func _should_hide_node_in_cockpit(node: Node3D) -> bool:
	for name_variant in cockpit_hidden_mesh_names:
		var target_name: String = String(name_variant)
		if target_name.is_empty():
			continue
		if String(node.name) == target_name:
			return true
	return false


func _update_head_visibility(force: bool) -> void:
	var should_hide: bool = false
	if hide_head_in_cockpit and _cockpit_camera != null:
		should_hide = _cockpit_camera.current
	if not force and should_hide == _last_head_hidden:
		return
	_last_head_hidden = should_hide
	for node in _cockpit_hidden_nodes:
		if is_instance_valid(node):
			node.visible = not should_hide
