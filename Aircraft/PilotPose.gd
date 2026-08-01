@tool
extends Node3D
## Applies a seated, forward-looking cockpit pose to the pilot rig.
## Attach to the root node of the pilot character instance.

const PilotVisualMaterials = preload("res://Models/Characters/PilotVisualMaterials.gd")

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
@export var pose_target_path: NodePath = NodePath(".")
@export var flat_shade_pilot_visual: bool = true
@export var hide_head_in_cockpit: bool = true
@export var cockpit_camera_path: NodePath = NodePath("../CameraCockpit/Camera3D")
@export var cockpit_hidden_mesh_names: PackedStringArray = PackedStringArray(["Pilot"])
@export_group("Ejection Poses")
@export var initial_pose_name: StringName = &"sitting"
@export var pose_blend_time_s: float = 0.18
@export_group("Mixamo Animation")
## Name of the animation to play in the cockpit (e.g. "mixamo.com"). Leave empty to print available names at startup.
@export var mixamo_cockpit_animation: StringName = &""
@export_group("Locomotion Animation")
## Looping run clip played while the pilot moves on the ground. Falls back to the
## procedural gait when the rig has no AnimationPlayer with this clip.
@export var locomotion_animation: StringName = &"mixamo_com"
## Ground speed the clip reads naturally at; playback speed scales relative to this.
@export var locomotion_anim_reference_speed_mps: float = 5.5
@export_group("Retargeted Locomotion")
## Optional animation-only character whose clip is retargeted onto this pilot's
## colored skeleton. This keeps the source mesh hidden and uses only its motion.
@export var locomotion_source_scene: PackedScene
@export var locomotion_source_animation: StringName = &"mixamo_com"
@export_group("Retargeted Ejection")
## Mixamo hanging animation used while the colored cockpit pilot is under canopy.
@export var parachute_source_scene: PackedScene
@export var parachute_source_animation: StringName = &"mixamo_com"
@export var parachute_animation_speed: float = 1.0

var _skeleton: Skeleton3D = null
var _ready_done: bool = false
var _foot_links: Array[Dictionary] = []
var _cockpit_camera: Camera3D = null
var _cockpit_hidden_nodes: Array[Node3D] = []
var _last_head_hidden: bool = false
var _pose_tween: Tween = null
var _anim_player: AnimationPlayer = null
var _mixamo_anim_active: bool = false
var _baked_sitting_pose_active: bool = false
var _pose_target_root: Node = null
var _locomotion_active: bool = false
var _locomotion_speed_mps: float = 0.0
var _locomotion_time_s: float = 0.0
var _locomotion_anim_playing: bool = false
var _retarget_source_root: Node = null
var _retarget_source_skeleton: Skeleton3D = null
var _retarget_source_player: AnimationPlayer = null
var _retarget_bone_pairs: Array[Dictionary] = []
var _retarget_loaded_scene: PackedScene = null
var _retarget_animation_active: bool = false

const LOCOMOTION_RETARGET_BONES := [
	["mixamorig_Hips", "root.x"],
	["mixamorig_Spine", "spine_01.x"],
	["mixamorig_Spine2", "spine_02.x"],
	["mixamorig_Neck", "neck.x"],
	["mixamorig_Head", "head.x"],
	["mixamorig_LeftShoulder", "shoulder.l"],
	["mixamorig_RightShoulder", "shoulder.r"],
	["mixamorig_LeftArm", "arm_stretch.l"],
	["mixamorig_LeftArm", "c_arm_twist_offset.l"],
	["mixamorig_RightArm", "arm_stretch.r"],
	["mixamorig_RightArm", "c_arm_twist_offset.r"],
	["mixamorig_LeftForeArm", "forearm_stretch.l"],
	["mixamorig_LeftForeArm", "forearm_twist.l"],
	["mixamorig_RightForeArm", "forearm_stretch.r"],
	["mixamorig_RightForeArm", "forearm_twist.r"],
	["mixamorig_LeftHand", "hand.l"],
	["mixamorig_RightHand", "hand.r"],
	["mixamorig_LeftUpLeg", "thigh_stretch.l"],
	["mixamorig_LeftUpLeg", "thigh_twist.l"],
	["mixamorig_RightUpLeg", "thigh_stretch.r"],
	["mixamorig_RightUpLeg", "thigh_twist.r"],
	["mixamorig_LeftLeg", "leg_stretch.l"],
	["mixamorig_LeftLeg", "leg_twist.l"],
	["mixamorig_RightLeg", "leg_stretch.r"],
	["mixamorig_RightLeg", "leg_twist.r"],
	["mixamorig_LeftFoot", "foot.l"],
	["mixamorig_RightFoot", "foot.r"],
	["mixamorig_LeftToeBase", "toes_01.l"],
	["mixamorig_RightToeBase", "toes_01.r"],
	["mixamorig_LeftHandThumb1", "thumb1.l"],
	["mixamorig_LeftHandThumb2", "c_thumb2.l"],
	["mixamorig_LeftHandThumb3", "c_thumb3.l"],
	["mixamorig_RightHandThumb1", "thumb1.r"],
	["mixamorig_RightHandThumb2", "c_thumb2.r"],
	["mixamorig_RightHandThumb3", "c_thumb3.r"],
	["mixamorig_LeftHandIndex1", "index1.l"],
	["mixamorig_LeftHandIndex1", "c_index1_base.l"],
	["mixamorig_LeftHandIndex2", "c_index2.l"],
	["mixamorig_LeftHandIndex3", "c_index3.l"],
	["mixamorig_RightHandIndex1", "index1.r"],
	["mixamorig_RightHandIndex1", "c_index1_base.r"],
	["mixamorig_RightHandIndex2", "c_index2.r"],
	["mixamorig_RightHandIndex3", "c_index3.r"],
]

const BONE_ALIASES := {
	"Abdomen": ["mixamorig_Spine", "mixamorig:Spine", "spine_01.x", "Waist", "Spine01", "DEF-spine"],
	"Torso": ["mixamorig_Spine1", "mixamorig:Spine1", "mixamorig_Spine2", "mixamorig:Spine2", "spine_02.x", "Spine01", "Spine02", "DEF-spine.002"],
	"Chest": ["mixamorig_Spine2", "mixamorig:Spine2", "Spine02", "DEF-spine.004"],
	"Neck": ["mixamorig_Neck", "mixamorig:Neck", "neck.x", "NeckTwist01", "NeckTwist02", "DEF-spine.005"],
	"Head": ["mixamorig_Head", "mixamorig:Head", "head.x", "Head", "DEF-spine.006"],
	"Shoulder.L": ["mixamorig_LeftShoulder", "mixamorig:LeftShoulder", "shoulder.l", "c_shoulder.l", "L_Clavicle", "DEF-shoulder.L"],
	"Shoulder.R": ["mixamorig_RightShoulder", "mixamorig:RightShoulder", "shoulder.r", "c_shoulder.r", "R_Clavicle", "DEF-shoulder.R"],
	"UpperArm.L": ["mixamorig_LeftArm", "mixamorig:LeftArm", "arm_fk.l", "arm.l", "arm_stretch.l", "L_Upperarm", "DEF-upper_arm.L"],
	"UpperArm.R": ["mixamorig_RightArm", "mixamorig:RightArm", "arm_fk.r", "arm.r", "arm_stretch.r", "R_Upperarm", "DEF-upper_arm.R"],
	"LowerArm.L": ["mixamorig_LeftForeArm", "mixamorig:LeftForeArm", "forearm_fk.l", "forearm.l", "forearm_stretch.l", "L_Forearm", "DEF-forearm.L"],
	"LowerArm.R": ["mixamorig_RightForeArm", "mixamorig:RightForeArm", "forearm_fk.r", "forearm.r", "forearm_stretch.r", "R_Forearm", "DEF-forearm.R"],
	"Wrist.L": ["mixamorig_LeftHand", "mixamorig:LeftHand", "hand.l", "L_Hand", "DEF-hand.L"],
	"Wrist.R": ["mixamorig_RightHand", "mixamorig:RightHand", "hand.r", "R_Hand", "DEF-hand.R"],
	"UpperLeg.L": ["mixamorig_LeftUpLeg", "mixamorig:LeftUpLeg", "thigh_fk.l", "thigh.l", "thigh_stretch.l", "L_Thigh", "DEF-thigh.L"],
	"UpperLeg.R": ["mixamorig_RightUpLeg", "mixamorig:RightUpLeg", "thigh_fk.r", "thigh.r", "thigh_stretch.r", "R_Thigh", "DEF-thigh.R"],
	"LowerLeg.L": ["mixamorig_LeftLeg", "mixamorig:LeftLeg", "leg_fk.l", "leg.l", "leg_stretch.l", "L_Calf", "DEF-shin.L"],
	"LowerLeg.R": ["mixamorig_RightLeg", "mixamorig:RightLeg", "leg_fk.r", "leg.r", "leg_stretch.r", "R_Calf", "DEF-shin.R"],
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
	_pose_target_root = _get_pose_target_root()
	if flat_shade_pilot_visual:
		PilotVisualMaterials.apply_flat_shading(_pose_target_root)

	_skeleton = _find_skeleton(_pose_target_root)
	if _skeleton == null:
		push_warning("PilotPose: No Skeleton3D found in children")
		return

	_hide_control_shapes(_pose_target_root)

	var use_imported_animation := not (_is_rigify_rig() or _is_pilot2_rig()) and (_is_mixamo_rig() or _is_arp_rig())
	if use_imported_animation and not Engine.is_editor_hint():
		_setup_mixamo_animation()
	else:
		if not Engine.is_editor_hint() and not _is_rigify_rig() and not _is_pilot2_rig():
			var bone0 := _skeleton.get_bone_name(0) if _skeleton.get_bone_count() > 0 else "none"
			print("PilotPose: unrecognised rig. bone[0]='%s', total bones=%d" % [bone0, _skeleton.get_bone_count()])
		if not _try_apply_baked_sitting_pose():
			_disable_animation_players(_pose_target_root)

	_build_foot_links()
	_ready_done = true
	process_priority = 1

	if not _mixamo_anim_active and not _baked_sitting_pose_active:
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
	_anim_player = _find_first_animation_player(_pose_target_root)
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
		_disable_animation_players(_pose_target_root)
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


func _try_apply_baked_sitting_pose() -> bool:
	if Engine.is_editor_hint() or initial_pose_name != &"sitting" or not _is_rigify_rig():
		return false
	_anim_player = _find_first_animation_player(_pose_target_root)
	if _anim_player == null:
		return false

	var pose_anim := _resolve_mixamo_anim(&"rigAction")
	if pose_anim == &"":
		var all_anims: PackedStringArray = []
		for lib in _anim_player.get_animation_library_list():
			for anim in _anim_player.get_animation_library(lib).get_animation_list():
				all_anims.append((lib + "/" + anim) if lib != "" else anim)
		if all_anims.size() == 1:
			pose_anim = StringName(all_anims[0])
	if pose_anim == &"":
		return false

	_anim_player.active = true
	_anim_player.play(pose_anim)
	_anim_player.advance(0.0)
	_anim_player.stop(true)
	_anim_player.active = false
	_baked_sitting_pose_active = true
	return true


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _mixamo_anim_active:
		_update_head_visibility(false)
		return
	if _baked_sitting_pose_active:
		_update_head_visibility(false)
		return
	if _retarget_animation_active:
		_advance_retargeted_animation(_delta)
		_update_head_visibility(false)
		return
	if _locomotion_anim_playing:
		_update_head_visibility(false)
		return
	if _locomotion_active:
		_apply_locomotion_pose(_delta)
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


func _apply_locomotion_pose(delta: float) -> void:
	if not _ready_done or _skeleton == null:
		return
	_locomotion_time_s += delta
	_skeleton.reset_bone_poses()

	var values := _get_pose_values(&"grounded")
	var speed_ratio := clampf(_locomotion_speed_mps / 5.5, 0.35, 1.25)
	var phase := _locomotion_time_s * lerpf(5.5, 8.5, speed_ratio)
	var stride := lerpf(16.0, 38.0, speed_ratio)
	var arm_swing := lerpf(10.0, 30.0, speed_ratio)
	var leg_sin := sin(phase)
	var leg_cos := cos(phase)
	var left_knee := maxf(0.0, -leg_sin) * lerpf(18.0, 48.0, speed_ratio)
	var right_knee := maxf(0.0, leg_sin) * lerpf(18.0, 48.0, speed_ratio)

	_set_rot("Abdomen", _pose_value(values, "abdomen_pitch", 5.0) + leg_cos * 1.5, 0.0, 0.0)
	_set_rot("Torso", _pose_value(values, "torso_pitch", 4.0) - leg_cos * 1.0, 0.0, 0.0)
	_set_rot("Shoulder.L", _pose_value(values, "shoulder_x", -10.0), _pose_value(values, "shoulder_y", 6.0), _pose_value(values, "shoulder_z", 0.0))
	_set_rot("Shoulder.R", _pose_value(values, "shoulder_x", -10.0), -_pose_value(values, "shoulder_y", 6.0), -_pose_value(values, "shoulder_z", 0.0))

	_set_rot("UpperLeg.L", _pose_value(values, "upper_leg_x", 0.0) + leg_sin * stride, 0.0, -_pose_value(values, "upper_leg_spread", 8.0))
	_set_rot("UpperLeg.R", _pose_value(values, "upper_leg_x", 0.0) - leg_sin * stride, 0.0, _pose_value(values, "upper_leg_spread", 8.0))
	_set_rot("LowerLeg.L", _pose_value(values, "lower_leg_x", 0.0) + left_knee, 0.0, 0.0)
	_set_rot("LowerLeg.R", _pose_value(values, "lower_leg_x", 0.0) + right_knee, 0.0, 0.0)
	_reattach_feet_to_legs()

	_set_rot("UpperArm.L", _pose_value(values, "upper_arm_x", 15.0) - leg_sin * arm_swing, _pose_value(values, "upper_arm_y", 0.0), _pose_value(values, "upper_arm_z", 38.0))
	_set_rot("UpperArm.R", _pose_value(values, "upper_arm_x", 15.0) + leg_sin * arm_swing, -_pose_value(values, "upper_arm_y", 0.0), -_pose_value(values, "upper_arm_z", 38.0))
	_set_rot("LowerArm.L", _pose_value(values, "lower_arm_x", 22.0) + maxf(0.0, leg_sin) * 18.0, _pose_value(values, "lower_arm_y", 0.0), _pose_value(values, "lower_arm_z", 0.0))
	_set_rot("LowerArm.R", _pose_value(values, "lower_arm_x", 22.0) + maxf(0.0, -leg_sin) * 18.0, -_pose_value(values, "lower_arm_y", 0.0), -_pose_value(values, "lower_arm_z", 0.0))
	_set_rot("Wrist.L", _pose_value(values, "wrist_x", 0.0), _pose_value(values, "wrist_y", 0.0), 0.0)
	_set_rot("Wrist.R", _pose_value(values, "wrist_x", 0.0), -_pose_value(values, "wrist_y", 0.0), 0.0)

	var curl := _pose_value(values, "finger_curl", 12.0)
	for side in ["L", "R"]:
		for finger in ["Index", "Middle", "Ring", "Pinky"]:
			for joint in ["1", "2", "3", "4"]:
				_set_rot("%s%s.%s" % [finger, joint, side], curl, 0.0, 0.0)
		_set_rot("Thumb1.%s" % side, curl * 0.6, 10.0, 0.0)
		_set_rot("Thumb2.%s" % side, curl * 0.8, 0.0, 0.0)
		_set_rot("Thumb3.%s" % side, curl * 0.7, 0.0, 0.0)

	_set_rot("Neck", _pose_value(values, "neck_pitch", 8.0) - leg_cos * 1.5, 0.0, 0.0)
	_set_rot("Head", _pose_value(values, "head_pitch", 0.0) + leg_cos * 1.2, 0.0, 0.0)


func set_ejection_pose(pose_name: StringName, blend_time_s: float = -1.0) -> void:
	_release_cockpit_visibility()
	_baked_sitting_pose_active = false
	set_locomotion_pose(false)
	if _mixamo_anim_active:
		_mixamo_anim_active = false
		if _anim_player != null and is_instance_valid(_anim_player):
			_anim_player.stop()
	if pose_name == &"parachute" and _start_retargeted_parachute():
		return
	var values := _get_pose_values(pose_name)
	if values.is_empty():
		return
	var duration := pose_blend_time_s if blend_time_s < 0.0 else blend_time_s
	_apply_pose_values(values, maxf(duration, 0.0))


func _release_cockpit_visibility() -> void:
	# The cockpit camera is reparented with the pilot during player ejection. It can
	# remain current all the way down, but it must no longer hide the pilot mesh.
	hide_head_in_cockpit = false
	_cockpit_camera = null
	_update_head_visibility(true)


func set_locomotion_pose(active: bool, speed_mps: float = 0.0) -> void:
	if active:
		_baked_sitting_pose_active = false
	_locomotion_active = active
	_locomotion_speed_mps = maxf(speed_mps, 0.0)
	if _mixamo_anim_active:
		_mixamo_anim_active = false
		if _anim_player != null and is_instance_valid(_anim_player):
			_anim_player.stop()
	if active:
		_start_locomotion_animation()
		set_process(true)
	else:
		_stop_locomotion_animation()
		_apply_pose()


func _start_locomotion_animation() -> void:
	if _start_retargeted_locomotion():
		return
	if _anim_player == null or not is_instance_valid(_anim_player):
		_anim_player = _find_first_animation_player(_pose_target_root)
	if _anim_player == null:
		return
	var resolved := _resolve_mixamo_anim(locomotion_animation)
	if resolved == &"":
		return
	var anim := _anim_player.get_animation(resolved)
	if anim != null and anim.loop_mode == Animation.LOOP_NONE:
		anim.loop_mode = Animation.LOOP_LINEAR
	_anim_player.active = true
	_anim_player.speed_scale = clampf(
		_locomotion_speed_mps / maxf(locomotion_anim_reference_speed_mps, 0.1),
		0.45,
		1.6
	)
	if _anim_player.current_animation != String(resolved) or not _anim_player.is_playing():
		_anim_player.play(resolved)
	_locomotion_anim_playing = true


func _stop_locomotion_animation() -> void:
	_stop_retargeted_animation()
	if not _locomotion_anim_playing:
		return
	_locomotion_anim_playing = false
	if _anim_player != null and is_instance_valid(_anim_player):
		_anim_player.stop()
		_anim_player.speed_scale = 1.0
		_anim_player.active = false


func _start_retargeted_locomotion() -> bool:
	if locomotion_source_scene == null or _skeleton == null:
		return false
	var speed_scale := clampf(
		_locomotion_speed_mps / maxf(locomotion_anim_reference_speed_mps, 0.1),
		0.45,
		1.6
	)
	return _start_retargeted_animation(locomotion_source_scene, locomotion_source_animation, speed_scale)


func _start_retargeted_parachute() -> bool:
	if parachute_source_scene == null or _skeleton == null:
		return false
	return _start_retargeted_animation(
		parachute_source_scene,
		parachute_source_animation,
		maxf(parachute_animation_speed, 0.01)
	)


func _start_retargeted_animation(source_scene: PackedScene, animation_name: StringName, speed_scale: float) -> bool:
	if not _setup_retargeted_animation(source_scene):
		return false
	var resolved := _resolve_animation_on_player(_retarget_source_player, animation_name)
	if resolved == &"":
		return false
	var animation := _retarget_source_player.get_animation(resolved)
	if animation != null and animation.loop_mode == Animation.LOOP_NONE:
		animation.loop_mode = Animation.LOOP_LINEAR
	_retarget_source_player.active = true
	_retarget_source_player.speed_scale = speed_scale
	_retarget_source_player.play(resolved)
	_retarget_source_player.advance(0.0)
	_retarget_animation_active = true
	_apply_retargeted_animation_frame()
	return true


func _stop_retargeted_animation() -> void:
	if not _retarget_animation_active:
		return
	_retarget_animation_active = false
	if _retarget_source_player != null and is_instance_valid(_retarget_source_player):
		_retarget_source_player.stop()
		_retarget_source_player.speed_scale = 1.0
	_skeleton.reset_bone_poses()


func _setup_retargeted_animation(source_scene: PackedScene) -> bool:
	if source_scene == null:
		return false
	if _retarget_loaded_scene == source_scene \
			and _retarget_source_root != null \
			and is_instance_valid(_retarget_source_root):
		return _retarget_source_skeleton != null \
			and _retarget_source_player != null \
			and not _retarget_bone_pairs.is_empty()
	_free_retarget_source()
	_retarget_source_root = source_scene.instantiate()
	if _retarget_source_root == null:
		return false
	_retarget_loaded_scene = source_scene
	add_child(_retarget_source_root)
	if _retarget_source_root is Node3D:
		(_retarget_source_root as Node3D).visible = false
	_retarget_source_skeleton = _find_skeleton(_retarget_source_root)
	_retarget_source_player = _find_first_animation_player(_retarget_source_root)
	if _retarget_source_skeleton == null or _retarget_source_player == null:
		_free_retarget_source()
		return false
	# The source player is sampled explicitly by this node, never by its own process.
	_retarget_source_root.process_mode = Node.PROCESS_MODE_DISABLED
	_retarget_bone_pairs.clear()
	for mapping in LOCOMOTION_RETARGET_BONES:
		var source_index := _retarget_source_skeleton.find_bone(String(mapping[0]))
		var target_index := _skeleton.find_bone(String(mapping[1]))
		if source_index < 0 or target_index < 0:
			continue
		_retarget_bone_pairs.append({
			"source": source_index,
			"target": target_index,
		})
	return not _retarget_bone_pairs.is_empty()


func _free_retarget_source() -> void:
	if _retarget_source_root != null and is_instance_valid(_retarget_source_root):
		_retarget_source_root.queue_free()
	_retarget_source_root = null
	_retarget_source_skeleton = null
	_retarget_source_player = null
	_retarget_loaded_scene = null
	_retarget_bone_pairs.clear()


func _advance_retargeted_animation(delta: float) -> void:
	if _retarget_source_player == null or not is_instance_valid(_retarget_source_player):
		_retarget_animation_active = false
		return
	_retarget_source_player.advance(delta)
	_apply_retargeted_animation_frame()


func _apply_retargeted_animation_frame() -> void:
	if _skeleton == null or _retarget_source_skeleton == null:
		return
	_skeleton.reset_bone_poses()
	for pair in _retarget_bone_pairs:
		var source_index := int(pair["source"])
		var target_index := int(pair["target"])
		var source_rest := _retarget_source_skeleton.get_bone_global_rest(source_index).orthonormalized()
		var source_pose := _retarget_source_skeleton.get_bone_global_pose(source_index).orthonormalized()
		var target_rest := _skeleton.get_bone_global_rest(target_index)
		# Applying the complete global rest-to-pose delta transfers both rotation and
		# joint travel. The colored rig's deformation bones are mostly siblings under
		# a control root, so rotation alone would leave knees and elbows behind.
		var motion_delta := source_pose * source_rest.affine_inverse()
		var desired_global := motion_delta * target_rest
		desired_global.basis = desired_global.basis.orthonormalized()
		var parent_index := _skeleton.get_bone_parent(target_index)
		var desired_local := desired_global
		if parent_index >= 0:
			desired_local = _skeleton.get_bone_global_pose(parent_index).affine_inverse() * desired_global
		var target_local_rest := _skeleton.get_bone_rest(target_index)
		var pose_basis := target_local_rest.basis.orthonormalized().inverse() * desired_local.basis
		_skeleton.set_bone_pose_rotation(target_index, pose_basis.orthonormalized().get_rotation_quaternion())
		_skeleton.set_bone_pose_position(target_index, desired_local.origin - target_local_rest.origin)


func _resolve_animation_on_player(player: AnimationPlayer, animation_name: StringName) -> StringName:
	if player == null:
		return &""
	if player.has_animation(animation_name):
		return animation_name
	for library_name in player.get_animation_library_list():
		var candidate := StringName(library_name + "/" + str(animation_name)) if library_name != "" else animation_name
		if player.has_animation(candidate):
			return candidate
	return &""


func _get_pose_values(pose_name: StringName) -> Dictionary:
	match pose_name:
		&"sitting":
			if _is_rigify_rig():
				# The cockpit Rigify asset stores its seated pose in a one-frame baked animation.
				# Leave procedural offsets neutral after that pose is sampled.
				return _make_pose(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
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
				# The pilot 2 GLB is a Rigify export whose useful rest is already close to seated.
				# Counteract the seated legs instead of forcing a 180-degree leg flip.
				return _make_pose(-65.0, -55.0, 15.0, 5.0, -5.0, -25.0, 0.0, 0.0, -60.0, 25.0, 0.0, 55.0, 0.0, 0.0, 0.0, 0.0, 65.0, -10.0, -8.0)
			if _is_mixamo_rig():
				# Mixamo T-pose: legs already hang down at rest (upper_leg_x=0). Arms start horizontal.
				return _make_pose(0.0, 0.0, 5.0, 5.0, -5.0, -25.0, 0.0, 0.0, 90.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 45.0, 0.0, 0.0)
			if _is_arp_rig():
				# ARP rest = T-pose. Legs already hang down. Arms at ~45° A-pose; raise toward risers.
				return _make_pose(0.0, 0.0, 5.0, 5.0, -5.0, -25.0, 0.0, 0.0, 90.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 45.0, 0.0, 0.0)
			return _make_pose(90.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 45.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
		&"grounded":
			if _is_mixamo_rig():
				# Mixamo rest = T-pose (arms horizontal); negative upper_arm_x swings them down.
				return _make_pose(0.0, 0.0, 5.0, 5.0, 4.0, -10.0, 6.0, 0.0, -75.0, 0.0, 0.0, 15.0, 0.0, 0.0, 0.0, 0.0, 12.0, 8.0, 0.0)
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


func _pose_value(values: Dictionary, key: String, fallback: float) -> float:
	return float(values.get(key, fallback))


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


func _get_pose_target_root() -> Node:
	var target := get_node_or_null(pose_target_path)
	return target if target != null else self


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
	return _skeleton != null and (
		_skeleton.find_bone("DEF-thigh.L") >= 0
		or (_skeleton.find_bone("c_pos") >= 0 and _skeleton.find_bone("thigh_fk.l") >= 0)
	)


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
	for child_variant in _pose_target_root.get_children():
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
