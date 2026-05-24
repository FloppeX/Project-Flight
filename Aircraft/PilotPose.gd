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
@export_group("Ejection Poses")
@export var initial_pose_name: StringName = &"sitting"
@export var pose_blend_time_s: float = 0.18

var _skeleton: Skeleton3D = null
var _ready_done: bool = false
var _foot_links: Array[Dictionary] = []
var _cockpit_camera: Camera3D = null
var _cockpit_hidden_nodes: Array[Node3D] = []
var _last_head_hidden: bool = false
var _pose_tween: Tween = null

const BONE_ALIASES := {
	"Abdomen": ["mixamorig_Spine", "Waist", "Spine01"],
	"Torso": ["mixamorig_Spine1", "mixamorig_Spine2", "Spine01", "Spine02"],
	"Chest": ["mixamorig_Spine2", "Spine02"],
	"Neck": ["mixamorig_Neck", "NeckTwist01", "NeckTwist02"],
	"Head": ["mixamorig_Head", "Head"],
	"Shoulder.L": ["mixamorig_LeftShoulder", "L_Clavicle"],
	"Shoulder.R": ["mixamorig_RightShoulder", "R_Clavicle"],
	"UpperArm.L": ["mixamorig_LeftArm", "L_Upperarm"],
	"UpperArm.R": ["mixamorig_RightArm", "R_Upperarm"],
	"LowerArm.L": ["mixamorig_LeftForeArm", "L_Forearm"],
	"LowerArm.R": ["mixamorig_RightForeArm", "R_Forearm"],
	"Wrist.L": ["mixamorig_LeftHand", "L_Hand"],
	"Wrist.R": ["mixamorig_RightHand", "R_Hand"],
	"UpperLeg.L": ["mixamorig_LeftUpLeg", "L_Thigh"],
	"UpperLeg.R": ["mixamorig_RightUpLeg", "R_Thigh"],
	"LowerLeg.L": ["mixamorig_LeftLeg", "L_Calf"],
	"LowerLeg.R": ["mixamorig_RightLeg", "R_Calf"],
	"Foot.L": ["mixamorig_LeftFoot", "L_Foot"],
	"Foot.R": ["mixamorig_RightFoot", "R_Foot"],
	"Index1.L": ["mixamorig_LeftHandIndex1"],
	"Index2.L": ["mixamorig_LeftHandIndex2"],
	"Index3.L": ["mixamorig_LeftHandIndex3"],
	"Index4.L": ["mixamorig_LeftHandIndex4"],
	"Index1.R": ["mixamorig_RightHandIndex1"],
	"Index2.R": ["mixamorig_RightHandIndex2"],
	"Index3.R": ["mixamorig_RightHandIndex3"],
	"Index4.R": ["mixamorig_RightHandIndex4"],
}


func _ready() -> void:
	_skeleton = _find_skeleton(self)
	if _skeleton == null:
		push_warning("PilotPose: No Skeleton3D found in children")
		return

	_disable_animation_players(self)
	_build_foot_links()
	_ready_done = true
	process_priority = 1
	if OS.is_debug_build():
		var names: Array[String] = []
		for i in range(_skeleton.get_bone_count()):
			names.append(_skeleton.get_bone_name(i))
		print("[PilotPose] Skeleton bones (", _skeleton.get_bone_count(), "): ", names)
		var ul_idx := _find_bone_index("UpperLeg.L")
		if ul_idx >= 0:
			print("[PilotPose] L_Thigh rest pose: ", _skeleton.get_bone_rest(ul_idx))
			print("[PilotPose] L_Thigh global rest: ", _skeleton.get_bone_global_rest(ul_idx))
	if initial_pose_name != &"":
		var values := _get_pose_values(initial_pose_name)
		if not values.is_empty():
			_apply_pose_values(values, 0.0)
		else:
			_apply_pose()
	else:
		_apply_pose()
	_cache_cockpit_visibility_nodes()
	_update_head_visibility(true)
	set_process(not Engine.is_editor_hint())


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_apply_pose()
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


func set_ejection_pose(pose_name: StringName, blend_time_s: float = -1.0) -> void:
	var values := _get_pose_values(pose_name)
	if values.is_empty():
		return
	var duration := pose_blend_time_s if blend_time_s < 0.0 else blend_time_s
	_apply_pose_values(values, maxf(duration, 0.0))


func _get_pose_values(pose_name: StringName) -> Dictionary:
	match pose_name:
		&"sitting":
			return _make_pose(0.0, 0.0, 0.0, 3.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 65.0, 0.0, 0.0, 2.0, 0.0, 20.0, 0.0, 0.0)
		&"seat_firing":
			return _make_pose(70.0, 72.0, 4.0, -6.0, -10.0, -8.0, 8.0, 4.0, -12.0, 18.0, -10.0, 92.0, 8.0, -6.0, 0.0, 0.0, 55.0, -3.0, -7.0)
		&"falling":
			return _make_pose(20.0, 18.0, 10.0, 4.0, 8.0, 18.0, 28.0, -16.0, 34.0, 42.0, -28.0, 34.0, 8.0, 8.0, 6.0, 8.0, 24.0, 4.0, 8.0)
		&"parachute":
			if _is_pilot2_rig():
				# Rest pose is sitting; negative leg values counteract it to hang straight down.
				return _make_pose(-65.0, -55.0, 15.0, 5.0, -5.0, -25.0, 0.0, 0.0, -60.0, 25.0, 0.0, 55.0, 0.0, 0.0, 0.0, 0.0, 65.0, -10.0, -8.0)
			if _is_mixamo_rig():
				return _make_pose(180.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 135.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
			return _make_pose(90.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 45.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
		&"grounded":
			# Standing, slightly slumped, waiting for rescue. Tune visually.
			return _make_pose(0.0, 0.0, 8.0, 5.0, 4.0, -10.0, 6.0, 0.0, 15.0, 0.0, 38.0, 22.0, 0.0, 0.0, 0.0, 0.0, 12.0, 8.0, 0.0)
		_:
			return {}


func _make_pose(
	new_upper_leg_x: float,
	new_lower_leg_x: float,
	new_upper_leg_spread: float,
	new_abdomen_pitch: float,
	new_torso_pitch: float,
	new_shoulder_x: float,
	new_shoulder_y: float,
	new_shoulder_z: float,
	new_upper_arm_x: float,
	new_upper_arm_y: float,
	new_upper_arm_z: float,
	new_lower_arm_x: float,
	new_lower_arm_y: float,
	new_lower_arm_z: float,
	new_wrist_x: float,
	new_wrist_y: float,
	new_finger_curl: float,
	new_neck_pitch: float,
	new_head_pitch: float
) -> Dictionary:
	return {
		"upper_leg_x": new_upper_leg_x,
		"lower_leg_x": new_lower_leg_x,
		"upper_leg_spread": new_upper_leg_spread,
		"abdomen_pitch": new_abdomen_pitch,
		"torso_pitch": new_torso_pitch,
		"shoulder_x": new_shoulder_x,
		"shoulder_y": new_shoulder_y,
		"shoulder_z": new_shoulder_z,
		"upper_arm_x": new_upper_arm_x,
		"upper_arm_y": new_upper_arm_y,
		"upper_arm_z": new_upper_arm_z,
		"lower_arm_x": new_lower_arm_x,
		"lower_arm_y": new_lower_arm_y,
		"lower_arm_z": new_lower_arm_z,
		"wrist_x": new_wrist_x,
		"wrist_y": new_wrist_y,
		"finger_curl": new_finger_curl,
		"neck_pitch": new_neck_pitch,
		"head_pitch": new_head_pitch,
	}


func _apply_pose_values(values: Dictionary, blend_time_s: float) -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	if blend_time_s <= 0.0 or Engine.is_editor_hint():
		for key_variant in values.keys():
			set(String(key_variant), float(values[key_variant]))
		_apply_pose()
		return

	_pose_tween = create_tween()
	for key_variant in values.keys():
		var property_name := String(key_variant)
		_pose_tween.parallel().tween_property(self, property_name, float(values[key_variant]), blend_time_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_rot(bone_name: String, x_deg: float, y_deg: float, z_deg: float) -> void:
	if _skeleton == null:
		return
	var idx: int = _find_bone_index(bone_name)
	if idx < 0:
		return
	var q: Quaternion = Quaternion.from_euler(Vector3(
		deg_to_rad(x_deg),
		deg_to_rad(y_deg),
		deg_to_rad(z_deg)
	))
	_skeleton.set_bone_pose_rotation(idx, q)


func _find_bone_index(bone_name: String) -> int:
	if _skeleton == null:
		return -1

	var idx: int = _skeleton.find_bone(bone_name)
	if idx >= 0:
		return idx

	var aliases_variant: Variant = BONE_ALIASES.get(bone_name, [])
	if aliases_variant is Array:
		for alias_variant in aliases_variant:
			var alias := String(alias_variant)
			idx = _skeleton.find_bone(alias)
			if idx >= 0:
				return idx

	return -1


func _is_mixamo_rig() -> bool:
	return _skeleton != null and _skeleton.find_bone("mixamorig_Hips") >= 0


func _is_pilot2_rig() -> bool:
	return _skeleton != null and _skeleton.find_bone("L_Thigh") >= 0 and _skeleton.find_bone("R_Thigh") >= 0


func _build_foot_links() -> void:
	_foot_links.clear()
	_add_foot_link("LowerLeg.L_end", "Foot.L", "PT.L")
	_add_foot_link("LowerLeg.R_end", "Foot.R", "PT.R")


func _add_foot_link(lower_leg_end_name: String, foot_name: String, pt_name: String) -> void:
	if _skeleton == null:
		return

	var lower_leg_end_idx: int = _find_bone_index(lower_leg_end_name)
	var foot_idx: int = _find_bone_index(foot_name)
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

	var pt_idx: int = _find_bone_index(pt_name)
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
		print("[PilotPose] Disabling AnimationPlayer: ", ap.name, " autoplay='", ap.autoplay, "'")
		ap.stop(false)
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
