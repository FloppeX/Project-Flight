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
@export_group("Mixamo Animation")
## Name of the animation to play in the cockpit (e.g. "mixamo.com"). Leave empty to print available names at startup.
@export var mixamo_cockpit_animation: StringName = &""

var _skeleton: Skeleton3D = null
var _ready_done: bool = false
var _foot_links: Array[Dictionary] = []
var _cockpit_camera: Camera3D = null
var _cockpit_hidden_nodes: Array[Node3D] = []
var _last_head_hidden: bool = false
var _pose_tween: Tween = null
var _anim_player: AnimationPlayer = null
var _mixamo_anim_active: bool = false

const BONE_ALIASES := {
	"Abdomen": ["mixamorig_Spine", "mixamorig:Spine", "spine_01.x", "Waist", "Spine01", "DEF-spine"],
	"Torso": ["mixamorig_Spine1", "mixamorig:Spine1", "mixamorig_Spine2", "mixamorig:Spine2", "spine_02.x", "Spine01", "Spine02", "DEF-spine.002"],
	"Chest": ["mixamorig_Spine2", "mixamorig:Spine2", "Spine02", "DEF-spine.004"],
	"Neck": ["mixamorig_Neck", "mixamorig:Neck", "neck.x", "NeckTwist01", "NeckTwist02", "DEF-spine.005"],
	"Head": ["mixamorig_Head", "mixamorig:Head", "head.x", "Head", "DEF-spine.006"],
	"Shoulder.L": ["mixamorig_LeftShoulder", "mixamorig:LeftShoulder", "shoulder.l", "L_Clavicle", "DEF-shoulder.L"],
	"Shoulder.R": ["mixamorig_RightShoulder", "mixamorig:RightShoulder", "shoulder.r", "R_Clavicle", "DEF-shoulder.R"],
	"UpperArm.L": ["mixamorig_LeftArm", "mixamorig:LeftArm", "arm_stretch.l", "L_Upperarm", "DEF-upper_arm.L"],
	"UpperArm.R": ["mixamorig_RightArm", "mixamorig:RightArm", "arm_stretch.r", "R_Upperarm", "DEF-upper_arm.R"],
	"LowerArm.L": ["mixamorig_LeftForeArm", "mixamorig:LeftForeArm", "forearm_stretch.l", "L_Forearm", "DEF-forearm.L"],
	"LowerArm.R": ["mixamorig_RightForeArm", "mixamorig:RightForeArm", "forearm_stretch.r", "R_Forearm", "DEF-forearm.R"],
	"Wrist.L": ["mixamorig_LeftHand", "mixamorig:LeftHand", "hand.l", "L_Hand", "DEF-hand.L"],
	"Wrist.R": ["mixamorig_RightHand", "mixamorig:RightHand", "hand.r", "R_Hand", "DEF-hand.R"],
	"UpperLeg.L": ["mixamorig_LeftUpLeg", "mixamorig:LeftUpLeg", "thigh_stretch.l", "L_Thigh", "DEF-thigh.L"],
	"UpperLeg.R": ["mixamorig_RightUpLeg", "mixamorig:RightUpLeg", "thigh_stretch.r", "R_Thigh", "DEF-thigh.R"],
	"LowerLeg.L": ["mixamorig_LeftLeg", "mixamorig:LeftLeg", "leg_stretch.l", "L_Calf", "DEF-shin.L"],
	"LowerLeg.R": ["mixamorig_RightLeg", "mixamorig:RightLeg", "leg_stretch.r", "R_Calf", "DEF-shin.R"],
	"Foot.L": ["mixamorig_LeftFoot", "mixamorig:LeftFoot", "foot.l", "L_Foot", "DEF-foot.L"],
	"Foot.R": ["mixamorig_RightFoot", "mixamorig:RightFoot", "foot.r", "R_Foot", "DEF-foot.R"],
	"Index1.L": ["mixamorig_LeftHandIndex1", "mixamorig:LeftHandIndex1", "index1.l", "DEF-f_index.01.L"],
	"Index2.L": ["mixamorig_LeftHandIndex2", "mixamorig:LeftHandIndex2", "index2.l", "DEF-f_index.02.L"],
	"Index3.L": ["mixamorig_LeftHandIndex3", "mixamorig:LeftHandIndex3", "index3.l", "DEF-f_index.03.L"],
	"Index4.L": ["mixamorig_LeftHandIndex4", "mixamorig:LeftHandIndex4"],
	"Index1.R": ["mixamorig_RightHandIndex1", "mixamorig:RightHandIndex1", "index1.r", "DEF-f_index.01.R"],
	"Index2.R": ["mixamorig_RightHandIndex2", "mixamorig:RightHandIndex2", "index2.r", "DEF-f_index.02.R"],
	"Index3.R": ["mixamorig_RightHandIndex3", "mixamorig:RightHandIndex3", "index3.r", "DEF-f_index.03.R"],
	"Index4.R": ["mixamorig_RightHandIndex4", "mixamorig:RightHandIndex4"],
	"Middle1.L": ["middle1.l", "DEF-f_middle.01.L"], "Middle2.L": ["middle2.l", "DEF-f_middle.02.L"], "Middle3.L": ["middle3.l", "DEF-f_middle.03.L"],
	"Middle1.R": ["middle1.r", "DEF-f_middle.01.R"], "Middle2.R": ["middle2.r", "DEF-f_middle.02.R"], "Middle3.R": ["middle3.r", "DEF-f_middle.03.R"],
	"Ring1.L": ["ring1.l", "DEF-f_ring.01.L"], "Ring2.L": ["ring2.l", "DEF-f_ring.02.L"], "Ring3.L": ["ring3.l", "DEF-f_ring.03.L"],
	"Ring1.R": ["ring1.r", "DEF-f_ring.01.R"], "Ring2.R": ["ring2.r", "DEF-f_ring.02.R"], "Ring3.R": ["ring3.r", "DEF-f_ring.03.R"],
	"Pinky1.L": ["pinky1.l", "DEF-f_pinky.01.L"], "Pinky2.L": ["pinky2.l", "DEF-f_pinky.02.L"], "Pinky3.L": ["pinky3.l", "DEF-f_pinky.03.L"],
	"Pinky1.R": ["pinky1.r", "DEF-f_pinky.01.R"], "Pinky2.R": ["pinky2.r", "DEF-f_pinky.02.R"], "Pinky3.R": ["pinky3.r", "DEF-f_pinky.03.R"],
	"Thumb1.L": ["mixamorig_LeftHandThumb1", "mixamorig:LeftHandThumb1", "thumb1.l", "DEF-thumb.01.L"],
	"Thumb2.L": ["mixamorig_LeftHandThumb2", "mixamorig:LeftHandThumb2", "thumb2.l", "DEF-thumb.02.L"],
	"Thumb3.L": ["mixamorig_LeftHandThumb3", "mixamorig:LeftHandThumb3", "thumb3.l", "DEF-thumb.03.L"],
	"Thumb1.R": ["mixamorig_RightHandThumb1", "mixamorig:RightHandThumb1", "thumb1.r", "DEF-thumb.01.R"],
	"Thumb2.R": ["mixamorig_RightHandThumb2", "mixamorig:RightHandThumb2", "thumb2.r", "DEF-thumb.02.R"],
	"Thumb3.R": ["mixamorig_RightHandThumb3", "mixamorig:RightHandThumb3", "thumb3.r", "DEF-thumb.03.R"],
}


func _ready() -> void:
	_skeleton = _find_skeleton(self)
	if _skeleton == null:
		push_warning("PilotPose: No Skeleton3D found in children")
		return

	_hide_control_shapes(self)

	if (_is_mixamo_rig() or _is_arp_rig()) and not Engine.is_editor_hint():
		_setup_mixamo_animation()
	else:
		if not Engine.is_editor_hint() and not _is_rigify_rig() and not _is_pilot2_rig():
			var bone0 := _skeleton.get_bone_name(0) if _skeleton.get_bone_count() > 0 else "none"
			print("PilotPose: unrecognised rig. bone[0]='%s', total bones=%d" % [bone0, _skeleton.get_bone_count()])
		_disable_animation_players(self)

	_build_foot_links()
	_ready_done = true
	process_priority = 1

	if not _mixamo_anim_active:
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


func _setup_mixamo_animation() -> void:
	_anim_player = _find_first_animation_player(self)
	if _anim_player == null:
		push_warning("PilotPose: Mixamo rig detected but no AnimationPlayer found")
		return

	# Build list of all available animations
	var all_anims: PackedStringArray = []
	for lib in _anim_player.get_animation_library_list():
		for anim in _anim_player.get_animation_library(lib).get_animation_list():
			all_anims.append((lib + "/" + anim) if lib != "" else anim)
	print("PilotPose: Mixamo rig found. Available animations: ", all_anims)
	print("PilotPose: Skeleton bone count: ", _skeleton.get_bone_count(), "  first bone: ", _skeleton.get_bone_name(0) if _skeleton.get_bone_count() > 0 else "none")

	var anim_to_play: StringName = mixamo_cockpit_animation
	if anim_to_play == &"" and not all_anims.is_empty():
		# Auto-play the first available animation so the character is in pose
		anim_to_play = StringName(all_anims[0])
		print("PilotPose: mixamo_cockpit_animation not set, auto-playing '%s'" % anim_to_play)

	if anim_to_play == &"" or initial_pose_name != &"sitting":
		_disable_animation_players(self)
		return

	var resolved := _resolve_mixamo_anim(anim_to_play)
	if resolved == &"":
		push_warning("PilotPose: animation '%s' not found in AnimationPlayer" % anim_to_play)
		_disable_animation_players(self)
		return
	_anim_player.play(resolved)
	_mixamo_anim_active = true


func _resolve_mixamo_anim(anim_name: StringName) -> StringName:
	if _anim_player == null:
		return &""
	if _anim_player.has_animation(anim_name):
		return anim_name
	for lib in _anim_player.get_animation_library_list():
		var candidate := StringName(lib + "/" + str(anim_name)) if lib != "" else anim_name
		if _anim_player.has_animation(candidate):
			return candidate
	return &""


func _find_first_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_first_animation_player(child)
		if result != null:
			return result
	return null


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _mixamo_anim_active:
		_update_head_visibility(false)
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
	if _mixamo_anim_active:
		_mixamo_anim_active = false
		if _anim_player != null and is_instance_valid(_anim_player):
			_anim_player.stop()
	var values := _get_pose_values(pose_name)
	if values.is_empty():
		return
	var duration := pose_blend_time_s if blend_time_s < 0.0 else blend_time_s
	_apply_pose_values(values, maxf(duration, 0.0))


func _get_pose_values(pose_name: StringName) -> Dictionary:
	match pose_name:
		&"sitting":
			if _is_rigify_rig():
				# Rigify rest = UP for limbs. Sitting: legs horizontal (+90 hip flexion from UP).
				# Spine leans back -25deg total; neck compensates to keep head level.
				return _make_pose(100.0, 0.0, 5.0, -20.0, -5.0, 0.0, 0.0, 0.0, 150.0, 0.0, 0.0, 65.0, 0.0, 0.0, 0.0, 0.0, 20.0, 0.0, 0.0)
			return _make_pose(0.0, 0.0, 0.0, 3.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 65.0, 0.0, 0.0, 2.0, 0.0, 20.0, 0.0, 0.0)
		&"seat_firing":
			return _make_pose(70.0, 72.0, 4.0, -6.0, -10.0, -8.0, 8.0, 4.0, -12.0, 18.0, -10.0, 92.0, 8.0, -6.0, 0.0, 0.0, 55.0, -3.0, -7.0)
		&"falling":
			return _make_pose(20.0, 18.0, 10.0, 4.0, 8.0, 18.0, 28.0, -16.0, 34.0, 42.0, -28.0, 34.0, 8.0, 8.0, 6.0, 8.0, 24.0, 4.0, 8.0)
		&"parachute":
			if _is_pilot2_rig():
				# Rest pose is sitting; negative leg values counteract it to hang straight down.
				return _make_pose(-65.0, -55.0, 15.0, 5.0, -5.0, -25.0, 0.0, 0.0, -60.0, 25.0, 0.0, 55.0, 0.0, 0.0, 0.0, 0.0, 65.0, -10.0, -8.0)
			if _is_rigify_rig():
				# Rigify rest = arms UP. Parachute: legs down (+180), arms near rest (0) to reach risers.
				return _make_pose(180.0, 0.0, 10.0, 5.0, -5.0, -25.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 45.0, -10.0, -8.0)
			if _is_mixamo_rig():
				# Mixamo T-pose: legs already hang down at rest (upper_leg_x=0). Arms start horizontal.
				return _make_pose(0.0, 0.0, 5.0, 5.0, -5.0, -25.0, 0.0, 0.0, 90.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 45.0, 0.0, 0.0)
			if _is_arp_rig():
				# ARP rest = T-pose. Legs already hang down. Arms at ~45° A-pose; raise toward risers.
				return _make_pose(0.0, 0.0, 5.0, 5.0, -5.0, -25.0, 0.0, 0.0, 90.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 45.0, 0.0, 0.0)
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
	if _skeleton == null:
		return false
	return _skeleton.find_bone("mixamorig_Hips") >= 0 or _skeleton.find_bone("mixamorig:Hips") >= 0


func _is_arp_rig() -> bool:
	return _skeleton != null and _skeleton.find_bone("arm_stretch.l") >= 0


func _hide_control_shapes(node: Node) -> void:
	if node is Node3D and String(node.name).begins_with("cs_"):
		(node as Node3D).visible = false
		return
	for child in node.get_children():
		_hide_control_shapes(child)


func _is_pilot2_rig() -> bool:
	return _skeleton != null and _skeleton.find_bone("L_Thigh") >= 0 and _skeleton.find_bone("R_Thigh") >= 0


func _is_rigify_rig() -> bool:
	return _skeleton != null and _skeleton.find_bone("DEF-thigh.L") >= 0


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
	# Prefer the skeleton that is actually driving a mesh (has_skin + skeleton='..')
	var mesh_driven := _find_mesh_driven_skeleton(node)
	if mesh_driven != null:
		return mesh_driven
	# Fall back to first Skeleton3D found
	return _find_first_skeleton(node)


func _find_mesh_driven_skeleton(node: Node) -> Skeleton3D:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.skin != null and mi.skeleton != NodePath(""):
			var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
			if skel != null:
				return skel
	for child in node.get_children():
		var result := _find_mesh_driven_skeleton(child)
		if result != null:
			return result
	return null


func _find_first_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child_variant in node.get_children():
		var child: Node = child_variant as Node
		if child == null:
			continue
		var result: Skeleton3D = _find_first_skeleton(child)
		if result != null:
			return result
	return null


func _disable_animation_players(node: Node) -> void:
	if node is AnimationPlayer:
		var ap: AnimationPlayer = node as AnimationPlayer
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
