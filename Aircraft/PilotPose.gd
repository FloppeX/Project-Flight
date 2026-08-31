@tool
extends Node3D
## Applies a seated, forward-looking cockpit pose to the pilot rig.
## Attach to the root node of the pilot character instance.

const PilotVisualMaterials = preload("res://Models/Characters/PilotVisualMaterials.gd")
const SEATED_BAKED_ANIMATIONS: Array[StringName] = [
	&"sit_1",
	&"sit_2",
	&"piloting",
]
const DEFAULT_STATIC_SEATED_ANIMATION: StringName = &"piloting"
const DEFAULT_STATIC_SEATED_TIME_S := 1.5

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
## Angle between the upper and lower leg in the cockpit's side view. Positive
## bend carries the ankle down and forward (+Z in pilot seat space), toward the
## rudder pedals.
@export_range(0.0, 120.0, 1.0, "degrees") var seated_knee_bend_degrees: float = 45.0
## Raises the toe from the rig's neutral standing foot angle. The rest-pose
## ankle-to-toe direction is the shared reference, which keeps every seated
## clip and both feet at the same visible pitch despite their imported poses.
@export_range(-30.0, 45.0, 1.0, "degrees") var seated_foot_toe_up_degrees: float = 15.0

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
## Additional backward lean applied at the base neck joint for every approved
## seated clip. Negative seat-space X rotation moves the head rearward (-Z).
@export_range(0.0, 30.0, 1.0, "degrees") var seated_neck_recline_degrees: float = 10.0

@export_group("Cockpit Visibility")
@export var pose_target_path: NodePath = NodePath(".")
@export var flat_shade_pilot_visual: bool = true
@export var hide_head_in_cockpit: bool = true
@export var cockpit_camera_path: NodePath = NodePath("../CameraCockpit/Camera3D")
@export var cockpit_hidden_mesh_names: PackedStringArray = PackedStringArray(["Pilot"])
@export_group("Ejection Poses")
@export var initial_pose_name: StringName = &"sitting"
@export var pose_blend_time_s: float = 0.18
@export_group("Baked Character Animation")
## Optional ARP-native animation started after the initial pose is prepared.
## CockpitPilot uses the shared looping piloting clip; general character scenes
## leave this empty and select animations through their gameplay state.
@export var initial_baked_animation: StringName = &""
@export var initial_baked_animation_speed: float = 1.0
## Cockpit pilots remain in their inexpensive static seated pose until the
## aircraft presentation is explicitly restored for player viewing. Editor
## previews still sample the configured animation for placement work.
@export var defer_initial_baked_animation_until_presented: bool = false
## Optional lazy library used by lightweight cockpit scenes. General character
## scenes keep their authored BakedAnimationPlayer and leave this empty.
@export_file("*.tres") var baked_animation_library_path: String = ""
## Static sample shown by tool builds so an aircraft scene can align the pilot
## against its actual runtime animation instead of the rig's standing/rest pose.
@export var editor_preview_animation_time_s: float = 0.0
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
@export_group("Parachute Pose Tuning")
## Shared editable offsets used by gameplay and the PilotPoseTuner scene. The
## resource defaults to zero offsets so the raw source clip remains the baseline.
@export var parachute_pose_settings: Resource

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
var _retarget_parachute_pose_active: bool = false
var _retarget_preview_paused: bool = false
var _baked_library_player: AnimationPlayer = null
var _baked_library_animation_active: bool = false
var _baked_bone_track_cache: Dictionary = {}

## Mixamo source bones mapped to the exported Auto-Rig Pro bones that deform the
## retained pilot mesh. The source character is never rendered.
const MIXAMO_TO_ARP_BONES := [
	["mixamorig_Hips", "root.x"],
	["mixamorig_Spine", "spine_01.x"],
	["mixamorig_Spine2", "spine_02.x"],
	["mixamorig_Neck", "neck.x"],
	["mixamorig_Head", "head.x"],
	["mixamorig_LeftShoulder", "c_shoulder.l"],
	["mixamorig_RightShoulder", "c_shoulder.r"],
	["mixamorig_LeftShoulder", "shoulder.l"],
	["mixamorig_RightShoulder", "shoulder.r"],
	["mixamorig_LeftArm", "arm.l"],
	["mixamorig_RightArm", "arm.r"],
	["mixamorig_LeftArm", "c_arm_twist_offset.l"],
	["mixamorig_RightArm", "c_arm_twist_offset.r"],
	["mixamorig_LeftArm", "arm_stretch.l"],
	["mixamorig_RightArm", "arm_stretch.r"],
	["mixamorig_LeftForeArm", "forearm.l"],
	["mixamorig_RightForeArm", "forearm.r"],
	["mixamorig_LeftForeArm", "forearm_stretch.l"],
	["mixamorig_RightForeArm", "forearm_stretch.r"],
	["mixamorig_LeftForeArm", "forearm_twist.l"],
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
]

## These ARP arm bones form a usable shoulder -> arm -> forearm -> hand
## hierarchy. They are solved from Mixamo joint directions after the torso is
## retargeted, rather than receiving proportion-dependent joint translations.
const RETARGET_ARM_TARGETS: Array[StringName] = [
	&"c_shoulder.l", &"shoulder.l", &"arm.l", &"c_arm_twist_offset.l", &"arm_stretch.l",
	&"forearm.l", &"forearm_stretch.l", &"forearm_twist.l", &"hand.l",
	&"c_shoulder.r", &"shoulder.r", &"arm.r", &"c_arm_twist_offset.r", &"arm_stretch.r",
	&"forearm.r", &"forearm_stretch.r", &"forearm_twist.r", &"hand.r",
]

## The ARP leg deformation bones are siblings under c_traj while the visible
## feet live under a separate FK chain. Copying Mixamo joint translations into
## both chains independently separates ankle from knee. Solve a fixed-length
## control chain, drive the deformation bones from it, and anchor each foot to
## the solved ankle instead.
const RETARGET_LEG_TARGETS: Array[StringName] = [
	&"thigh_stretch.l", &"thigh_twist.l", &"leg_stretch.l", &"leg_twist.l",
	&"foot.l", &"toes_01.l",
	&"thigh_stretch.r", &"thigh_twist.r", &"leg_stretch.r", &"leg_twist.r",
	&"foot.r", &"toes_01.r",
]

const PARACHUTE_GRIP_SOURCE_BONES: Array[StringName] = [
	&"mixamorig_LeftHandThumb1",
	&"mixamorig_LeftHandThumb2",
	&"mixamorig_LeftHandThumb3",
	&"mixamorig_LeftHandIndex1",
	&"mixamorig_LeftHandIndex2",
	&"mixamorig_LeftHandIndex3",
	&"mixamorig_RightHandThumb1",
	&"mixamorig_RightHandThumb2",
	&"mixamorig_RightHandThumb3",
	&"mixamorig_RightHandIndex1",
	&"mixamorig_RightHandIndex2",
	&"mixamorig_RightHandIndex3",
]

const PARACHUTE_SOURCE_ROTATION_SETTINGS := [
	[&"mixamorig_LeftShoulder", &"left_shoulder_degrees"],
	[&"mixamorig_LeftArm", &"left_upper_arm_degrees"],
	[&"mixamorig_LeftForeArm", &"left_forearm_degrees"],
	[&"mixamorig_LeftHand", &"left_hand_degrees"],
	[&"mixamorig_RightShoulder", &"right_shoulder_degrees"],
	[&"mixamorig_RightArm", &"right_upper_arm_degrees"],
	[&"mixamorig_RightForeArm", &"right_forearm_degrees"],
	[&"mixamorig_RightHand", &"right_hand_degrees"],
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

	var use_imported_animation := not (_is_arp_rig() or _is_pilot2_rig()) and _is_mixamo_rig()
	if use_imported_animation and not Engine.is_editor_hint():
		_setup_mixamo_animation()
	else:
		if not Engine.is_editor_hint() and not _is_arp_rig() and not _is_pilot2_rig():
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
	var should_start_initial_animation := not defer_initial_baked_animation_until_presented \
			or Engine.is_editor_hint()
	if initial_baked_animation != &"" and should_start_initial_animation:
		if not play_baked_animation(
			initial_baked_animation,
			maxf(initial_baked_animation_speed, 0.01)
		):
			push_warning(
				"PilotPose: initial baked animation '%s' is unavailable"
				% initial_baked_animation
			)
		elif Engine.is_editor_hint():
			_freeze_baked_animation_for_editor(editor_preview_animation_time_s)
	elif defer_initial_baked_animation_until_presented and not Engine.is_editor_hint():
		# The static pose was applied above. Do not evaluate the dense control rig
		# every frame while this cockpit is not being shown to the player.
		set_process(false)


## Samples the normal cockpit pose for a static preview. The approved baked clip
## requires SceneTree context while AnimationPlayer evaluates it; callers may
## detach the pilot and strip its scripts after this method returns.
func apply_static_seated_pose() -> bool:
	# The canonical pilot has an approved shared cockpit clip. Prefer a frozen
	# sample from it over the GLB's legacy one-frame rigAction so standalone
	# previews (including the Technical Index) match live cockpit occupants.
	if not baked_animation_library_path.is_empty() \
			and apply_static_baked_pose(
				DEFAULT_STATIC_SEATED_ANIMATION,
				DEFAULT_STATIC_SEATED_TIME_S
			):
		return true

	initial_pose_name = &"sitting"
	_pose_target_root = _get_pose_target_root()
	if flat_shade_pilot_visual:
		PilotVisualMaterials.apply_flat_shading(_pose_target_root)

	_skeleton = _find_skeleton(_pose_target_root)
	if _skeleton == null:
		return false
	_hide_control_shapes(_pose_target_root)

	var pose_applied := _try_apply_baked_sitting_pose()
	if not pose_applied:
		_disable_animation_players(_pose_target_root)
		_build_foot_links()
		_ready_done = true
		var values := _get_pose_values(&"sitting")
		if values.is_empty():
			return false
		_apply_pose_values(values, 0.0)
		pose_applied = true

	# A live cockpit camera can hide the pilot from first-person view. Static
	# equipment previews always show the complete seated figure.
	_cache_cockpit_visibility_nodes()
	for hidden_node in _cockpit_hidden_nodes:
		if is_instance_valid(hidden_node):
			hidden_node.visible = true
	_last_head_hidden = false
	set_process(false)
	return pose_applied


## Samples one frame from an approved baked seated animation, then releases the
## AnimationPlayer while retaining the sampled bone transforms. Passenger mounts
## use this to match the visible cockpit pose without evaluating an animation on
## every frame.
func apply_static_baked_pose(animation_name: StringName, time_s: float = 0.0) -> bool:
	initial_pose_name = &"sitting"
	_pose_target_root = _get_pose_target_root()
	if flat_shade_pilot_visual:
		PilotVisualMaterials.apply_flat_shading(_pose_target_root)

	_skeleton = _find_skeleton(_pose_target_root)
	if _skeleton == null:
		return false
	_hide_control_shapes(_pose_target_root)
	_ready_done = true

	if not play_baked_animation(animation_name, 1.0):
		return false
	var animation := _baked_library_player.get_animation(animation_name) \
			if _baked_library_player != null else null
	if animation == null:
		_stop_baked_library_animation(true)
		return false
	_baked_library_player.seek(clampf(time_s, 0.0, animation.length), true)
	_baked_library_player.advance(0.0)
	_apply_seated_pose_corrections(animation_name)
	# stop(true) preserves the sampled pose. Mark it as the static sitting state
	# so a pooled body can later restart the live cockpit animation cleanly.
	_baked_library_player.stop(true)
	_baked_library_player.active = false
	_baked_library_animation_active = false
	_baked_sitting_pose_active = true

	_cache_cockpit_visibility_nodes()
	for hidden_node in _cockpit_hidden_nodes:
		if is_instance_valid(hidden_node):
			hidden_node.visible = true
	_last_head_hidden = false
	set_process(false)
	return true


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
	if Engine.is_editor_hint() or initial_pose_name != &"sitting" or not _is_arp_rig():
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
	if _baked_library_animation_active:
		_apply_seated_pose_corrections(_current_baked_animation())
		_update_head_visibility(false)
		return
	if _mixamo_anim_active:
		_update_head_visibility(false)
		return
	if _baked_sitting_pose_active:
		_update_head_visibility(false)
		return
	if _retarget_animation_active:
		if not _retarget_preview_paused:
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
	# Ejection is a real presentation state even when the source aircraft was not
	# previously being viewed. Its animation must not inherit cockpit dormancy.
	set_process(true)
	_stop_baked_library_animation(false)
	_release_cockpit_visibility()
	_baked_sitting_pose_active = false
	set_locomotion_pose(false)
	if _mixamo_anim_active:
		_mixamo_anim_active = false
		if _anim_player != null and is_instance_valid(_anim_player):
			_anim_player.stop()
	if pose_name == &"parachute":
		if _start_retargeted_parachute():
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
	_stop_baked_library_animation(false)
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
	_retarget_parachute_pose_active = false
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
	_retarget_parachute_pose_active = true
	var started := _start_retargeted_animation(
		parachute_source_scene,
		parachute_source_animation,
		maxf(parachute_animation_speed, 0.01)
	)
	if not started:
		_retarget_parachute_pose_active = false
	return started


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
	_retarget_preview_paused = false
	_apply_retargeted_animation_frame()
	return true


## Plays one ARP-native clip from PilotCharacter's shared baked library. This
## resets the dense ARP control rig first, matching the runtime retargeter's
## clean rest baseline and avoiding leftover cockpit-pose controls.
func play_baked_animation(animation_name: StringName, speed_scale: float = 1.0) -> bool:
	if _skeleton == null:
		return false
	_ensure_baked_library_player()
	if _baked_library_player == null or not _baked_library_player.has_animation(animation_name):
		return false

	_stop_retargeted_animation()
	_locomotion_active = false
	_locomotion_anim_playing = false
	_mixamo_anim_active = false
	_baked_sitting_pose_active = false
	if _anim_player != null and is_instance_valid(_anim_player):
		_anim_player.stop()
		_anim_player.active = false
	_skeleton.reset_bone_poses()
	_baked_library_player.active = true
	_baked_library_player.speed_scale = maxf(speed_scale, 0.01)
	_baked_library_player.play(animation_name)
	_baked_library_player.advance(0.0)
	_apply_seated_pose_corrections(animation_name)
	_baked_library_animation_active = true
	set_process(true)
	return true


func _ensure_baked_library_player() -> void:
	if _baked_library_player != null and is_instance_valid(_baked_library_player):
		return
	_baked_library_player = get_node_or_null("BakedAnimationPlayer") as AnimationPlayer
	if _baked_library_player != null or baked_animation_library_path.is_empty():
		return
	var loaded_resource: Resource = load(baked_animation_library_path)
	var animation_library := loaded_resource as AnimationLibrary
	if animation_library == null:
		push_warning(
			"PilotPose: baked animation library could not be loaded: %s"
			% baked_animation_library_path
		)
		return
	_baked_library_player = AnimationPlayer.new()
	_baked_library_player.name = "BakedAnimationPlayer"
	_baked_library_player.add_animation_library(&"", animation_library)
	add_child(_baked_library_player)


## Starts the normal cockpit loop only while this pilot can be presented to the
## player. Ejection/locomotion animations are deliberately left alone.
func set_presentation_active(active: bool) -> void:
	if not defer_initial_baked_animation_until_presented or Engine.is_editor_hint():
		return
	if active:
		# Pooled cockpit pilots run _ready() while parked under the reserve, where
		# the aircraft cockpit camera is not in their tree. Refresh these references
		# after checkout so first-person visibility follows the borrowing aircraft.
		_cache_cockpit_visibility_nodes()
		_update_head_visibility(true)
		if initial_baked_animation == &"" or _baked_library_animation_active:
			return
		play_baked_animation(
			initial_baked_animation,
			maxf(initial_baked_animation_speed, 0.01)
		)
		return

	# Once cockpit-only visibility has been released, ejection owns this pilot.
	# A later visual-budget pass must not put that sequence back to sleep.
	if not hide_head_in_cockpit:
		return
	if not _baked_library_animation_active:
		set_process(false)
		return
	if _baked_library_player == null or not is_instance_valid(_baked_library_player):
		return
	if StringName(_baked_library_player.current_animation) != initial_baked_animation:
		# A parachute or another gameplay animation owns the pilot now.
		return
	_stop_baked_library_animation(false)
	set_process(false)


func _freeze_baked_animation_for_editor(time_s: float) -> void:
	if _baked_library_player == null or not is_instance_valid(_baked_library_player):
		return
	var animation := _baked_library_player.get_animation(
		_baked_library_player.current_animation
	)
	if animation == null:
		return
	_baked_library_player.seek(clampf(time_s, 0.0, animation.length), true)
	_baked_library_player.advance(0.0)
	_apply_seated_pose_corrections(_current_baked_animation())
	_baked_library_player.pause()
	# The sampled bones stay in place without continuously evaluating an
	# AnimationPlayer for every aircraft open in the editor.
	set_process(false)


func _current_baked_animation() -> StringName:
	if _baked_library_player == null or not is_instance_valid(_baked_library_player):
		return &""
	return StringName(_baked_library_player.current_animation)


## Normalizes every seated baked clip to the same leg, boot, and base-neck
## geometry. Auto-Rig Pro exports the weighted shin and FK foot under different
## parents, while the animated neck pitch is retained beneath a shared offset.
func _apply_seated_pose_corrections(animation_name: StringName) -> void:
	if animation_name not in SEATED_BAKED_ANIMATIONS or _skeleton == null:
		return
	_skeleton.force_update_all_bone_transforms()
	for suffix in [".l", ".r"]:
		_apply_seated_knee_bend(suffix)
	_skeleton.force_update_all_bone_transforms()
	for suffix in [".l", ".r"]:
		_apply_seated_foot_pitch(suffix)
	_skeleton.force_update_all_bone_transforms()
	_apply_seated_neck_recline(animation_name)
	_skeleton.force_update_all_bone_transforms()


func _apply_seated_knee_bend(suffix: String) -> void:
	var thigh_index := _skeleton.find_bone("thigh_stretch" + suffix)
	var shin_index := _skeleton.find_bone("leg_stretch" + suffix)
	var foot_index := _skeleton.find_bone("foot" + suffix)
	if thigh_index < 0 or shin_index < 0 or foot_index < 0:
		return

	var thigh_global := _skeleton.get_bone_global_pose(thigh_index)
	var shin_global := _skeleton.get_bone_global_pose(shin_index)
	var foot_global := _skeleton.get_bone_global_pose(foot_index)
	var thigh_vector := shin_global.origin - thigh_global.origin
	var shin_vector := foot_global.origin - shin_global.origin
	var thigh_sagittal_length := Vector2(thigh_vector.y, thigh_vector.z).length()
	var shin_sagittal_length := Vector2(shin_vector.y, shin_vector.z).length()
	if thigh_sagittal_length < 0.0001 or shin_sagittal_length < 0.0001:
		return

	# Measure both segments in the seat's side view. Zero points forward (+Z),
	# and a positive angle moves downward (-Y), so upper + 45 degrees puts the
	# feet both below and in front of the knees instead of tucking them backward.
	var upper_leg_angle := atan2(-thigh_vector.y, thigh_vector.z)
	var current_lower_leg_angle := atan2(-shin_vector.y, shin_vector.z)
	var target_lower_leg_angle := upper_leg_angle + deg_to_rad(seated_knee_bend_degrees)
	var correction_angle := wrapf(
		target_lower_leg_angle - current_lower_leg_angle,
		-PI,
		PI
	)
	if absf(correction_angle) < 0.00001:
		return
	var correction_basis := Basis(Vector3.RIGHT, correction_angle)

	var shin_parent := _skeleton.get_bone_parent(shin_index)
	var desired_shin_basis := (
		correction_basis * shin_global.basis.orthonormalized()
	).orthonormalized()
	var desired_shin_local_basis := desired_shin_basis
	if shin_parent >= 0:
		desired_shin_local_basis = (
			_skeleton.get_bone_global_pose(shin_parent).basis.inverse()
			* desired_shin_basis
		).orthonormalized()
	_skeleton.set_bone_pose_rotation(
		shin_index,
		desired_shin_local_basis.get_rotation_quaternion()
	)

	var desired_ankle_position := (
		shin_global.origin + correction_basis * shin_vector
	)
	var foot_parent := _skeleton.get_bone_parent(foot_index)
	var desired_foot_local_position := desired_ankle_position
	if foot_parent >= 0:
		desired_foot_local_position = (
			_skeleton.get_bone_global_pose(foot_parent).affine_inverse()
			* Transform3D(Basis.IDENTITY, desired_ankle_position)
		).origin
	_skeleton.set_bone_pose_position(foot_index, desired_foot_local_position)


func _apply_seated_foot_pitch(suffix: String) -> void:
	var foot_index := _skeleton.find_bone("foot" + suffix)
	var toe_index := _skeleton.find_bone("toes_01" + suffix)
	if foot_index < 0 or toe_index < 0:
		return

	var foot_global := _skeleton.get_bone_global_pose(foot_index)
	var toe_global := _skeleton.get_bone_global_pose(toe_index)
	var current_foot_vector := toe_global.origin - foot_global.origin
	var rest_foot := _skeleton.get_bone_global_rest(foot_index)
	var rest_toe := _skeleton.get_bone_global_rest(toe_index)
	var rest_foot_vector := rest_toe.origin - rest_foot.origin
	if Vector2(current_foot_vector.y, current_foot_vector.z).length() < 0.0001 \
			or Vector2(rest_foot_vector.y, rest_foot_vector.z).length() < 0.0001:
		return

	# Bone joints sit inside the boot, so a visually neutral foot does not have
	# a zero-degree ankle-to-toe vector. Use the neutral rig as calibration, then
	# lift the visible toe by the requested amount in seat space.
	var current_foot_angle := atan2(-current_foot_vector.y, current_foot_vector.z)
	var neutral_foot_angle := atan2(-rest_foot_vector.y, rest_foot_vector.z)
	var target_foot_angle := neutral_foot_angle - deg_to_rad(seated_foot_toe_up_degrees)
	var correction_angle := wrapf(
		target_foot_angle - current_foot_angle,
		-PI,
		PI
	)
	if absf(correction_angle) < 0.00001:
		return

	var correction_basis := Basis(Vector3.RIGHT, correction_angle)
	var desired_foot_basis := (
		correction_basis * foot_global.basis.orthonormalized()
	).orthonormalized()
	var foot_parent := _skeleton.get_bone_parent(foot_index)
	var desired_foot_local_basis := desired_foot_basis
	if foot_parent >= 0:
		desired_foot_local_basis = (
			_skeleton.get_bone_global_pose(foot_parent).basis.inverse()
			* desired_foot_basis
		).orthonormalized()
	_skeleton.set_bone_pose_rotation(
		foot_index,
		desired_foot_local_basis.get_rotation_quaternion()
	)


func _apply_seated_neck_recline(animation_name: StringName) -> void:
	var neck_index := _skeleton.find_bone("neck.x")
	var head_index := _skeleton.find_bone("head.x")
	if neck_index < 0 or head_index < 0:
		return
	var authored_neck_rotation: Variant = _sample_baked_bone_rotation(
		animation_name, &"neck.x"
	)
	var authored_neck_position: Variant = _sample_baked_bone_position(
		animation_name, &"neck.x"
	)
	var authored_head_rotation: Variant = _sample_baked_bone_rotation(
		animation_name, &"head.x"
	)
	var authored_head_position: Variant = _sample_baked_bone_position(
		animation_name, &"head.x"
	)
	if not authored_neck_rotation is Quaternion \
			or not authored_neck_position is Vector3 \
			or not authored_head_rotation is Quaternion \
			or not authored_head_position is Vector3:
		return

	# Restore the animation-authored local transforms before applying the offset.
	# This makes the correction idempotent when a paused/static pose is sampled
	# more than once, while preserving the clip's subtle head movement.
	_skeleton.set_bone_pose_position(neck_index, authored_neck_position as Vector3)
	_skeleton.set_bone_pose_rotation(neck_index, authored_neck_rotation as Quaternion)
	_skeleton.set_bone_pose_position(head_index, authored_head_position as Vector3)
	_skeleton.set_bone_pose_rotation(head_index, authored_head_rotation as Quaternion)
	_skeleton.force_update_all_bone_transforms()
	var neck_global := _skeleton.get_bone_global_pose(neck_index)
	var head_global := _skeleton.get_bone_global_pose(head_index)
	var correction_basis := Basis(
		Vector3.RIGHT,
		-deg_to_rad(seated_neck_recline_degrees)
	)
	var desired_neck_basis := (
		correction_basis * neck_global.basis.orthonormalized()
	).orthonormalized()
	var neck_parent := _skeleton.get_bone_parent(neck_index)
	var desired_neck_local_basis := desired_neck_basis
	if neck_parent >= 0:
		desired_neck_local_basis = (
			_skeleton.get_bone_global_pose(neck_parent).basis.inverse()
			* desired_neck_basis
		).orthonormalized()
	_skeleton.set_bone_pose_rotation(
		neck_index,
		desired_neck_local_basis.get_rotation_quaternion()
	)

	# ARP's exported head deformation bone is not a child of neck.x. Carry its
	# complete transform around the base-neck pivot explicitly so the helmet and
	# face follow the recline instead of leaving only the neck bent backward.
	var desired_head_origin := (
		neck_global.origin
		+ correction_basis * (head_global.origin - neck_global.origin)
	)
	var desired_head_basis := (
		correction_basis * head_global.basis.orthonormalized()
	).orthonormalized()
	var head_parent := _skeleton.get_bone_parent(head_index)
	var desired_head_local := Transform3D(desired_head_basis, desired_head_origin)
	if head_parent >= 0:
		desired_head_local = (
			_skeleton.get_bone_global_pose(head_parent).affine_inverse()
			* desired_head_local
		)
	_skeleton.set_bone_pose_position(head_index, desired_head_local.origin)
	_skeleton.set_bone_pose_rotation(
		head_index,
		desired_head_local.basis.orthonormalized().get_rotation_quaternion()
	)


func _sample_baked_bone_rotation(
		animation_name: StringName,
		bone_name: StringName
) -> Variant:
	if _baked_library_player == null \
			or not is_instance_valid(_baked_library_player) \
			or not _baked_library_player.has_animation(animation_name):
		return null
	var animation := _baked_library_player.get_animation(animation_name)
	if animation == null:
		return null
	var track_index := _find_baked_bone_track(
		animation_name,
		bone_name,
		Animation.TYPE_ROTATION_3D
	)
	if track_index < 0:
		return null
	return animation.rotation_track_interpolate(
		track_index,
		_baked_library_player.current_animation_position
	)


func _sample_baked_bone_position(
		animation_name: StringName,
		bone_name: StringName
) -> Variant:
	if _baked_library_player == null \
			or not is_instance_valid(_baked_library_player) \
			or not _baked_library_player.has_animation(animation_name):
		return null
	var animation := _baked_library_player.get_animation(animation_name)
	if animation == null:
		return null
	var track_index := _find_baked_bone_track(
		animation_name,
		bone_name,
		Animation.TYPE_POSITION_3D
	)
	if track_index < 0:
		return null
	return animation.position_track_interpolate(
		track_index,
		_baked_library_player.current_animation_position
	)


func _find_baked_bone_track(
		animation_name: StringName,
		bone_name: StringName,
		track_type: Animation.TrackType
) -> int:
	var cache_key := "%s|%s|%d" % [animation_name, bone_name, track_type]
	if _baked_bone_track_cache.has(cache_key):
		return int(_baked_bone_track_cache[cache_key])
	var animation := _baked_library_player.get_animation(animation_name)
	if animation == null:
		_baked_bone_track_cache[cache_key] = -1
		return -1
	var bone_path_suffix := ":" + String(bone_name)
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) == track_type \
				and String(animation.track_get_path(track_index)).ends_with(bone_path_suffix):
			_baked_bone_track_cache[cache_key] = track_index
			return track_index
	_baked_bone_track_cache[cache_key] = -1
	return -1


func stop_baked_animation(reset_to_rest: bool = true) -> void:
	_stop_baked_library_animation(reset_to_rest)


func _stop_baked_library_animation(reset_to_rest: bool) -> void:
	if _baked_library_player != null and is_instance_valid(_baked_library_player):
		_baked_library_player.stop()
		_baked_library_player.speed_scale = 1.0
		_baked_library_player.active = false
	_baked_library_animation_active = false
	if reset_to_rest and _skeleton != null:
		_skeleton.reset_bone_poses()


func _stop_retargeted_animation() -> void:
	_retarget_parachute_pose_active = false
	_retarget_preview_paused = false
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
	for mapping in MIXAMO_TO_ARP_BONES:
		var source_index := _find_mixamo_source_bone(
			_retarget_source_skeleton,
			StringName(mapping[0])
		)
		var target_index := _skeleton.find_bone(String(mapping[1]))
		if source_index < 0 or target_index < 0:
			continue
		_retarget_bone_pairs.append({
			"source": source_index,
			"target": target_index,
		})
	return not _retarget_bone_pairs.is_empty()


func _find_mixamo_source_bone(source_skeleton: Skeleton3D, canonical_name: StringName) -> int:
	if source_skeleton == null:
		return -1
	var bone_index := source_skeleton.find_bone(canonical_name)
	if bone_index >= 0:
		return bone_index
	var alternate_name := String(canonical_name).replace("mixamorig_", "mixamorig:")
	return source_skeleton.find_bone(alternate_name)


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


## Preview controls used by the standalone pilot-pose tuner. Gameplay leaves
## these untouched, so normal parachute animation playback remains automatic.
func set_retarget_preview_paused(paused: bool) -> void:
	_retarget_preview_paused = paused


func is_retarget_preview_paused() -> bool:
	return _retarget_preview_paused


func get_retarget_preview_position() -> float:
	if _retarget_source_player == null or not is_instance_valid(_retarget_source_player):
		return 0.0
	return _retarget_source_player.current_animation_position


func get_retarget_preview_length() -> float:
	if _retarget_source_player == null or not is_instance_valid(_retarget_source_player):
		return 0.0
	return _retarget_source_player.current_animation_length


func seek_retarget_preview(time_s: float) -> void:
	if _retarget_source_player == null or not is_instance_valid(_retarget_source_player):
		return
	var length := get_retarget_preview_length()
	_retarget_source_player.seek(clampf(time_s, 0.0, length), true)
	_apply_retargeted_animation_frame()


func refresh_retarget_preview() -> void:
	seek_retarget_preview(get_retarget_preview_position())


func _apply_retargeted_animation_frame() -> void:
	if _skeleton == null or _retarget_source_skeleton == null:
		return
	if _retarget_parachute_pose_active:
		_apply_parachute_source_pose_adjustments()
	_skeleton.reset_bone_poses()
	for pair in _retarget_bone_pairs:
		var source_index := int(pair["source"])
		var target_index := int(pair["target"])
		var target_bone_name := _skeleton.get_bone_name(target_index)
		if RETARGET_ARM_TARGETS.has(target_bone_name) \
				or RETARGET_LEG_TARGETS.has(target_bone_name):
			continue
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
		# Skeleton3D stores these imported bone poses as complete local transforms;
		# reset_bone_poses() restores the rest values rather than identity deltas.
		# Supplying a rest-relative delta here collapses ARP's sibling deformation
		# bones toward c_traj and visibly stretches the mesh.
		_skeleton.set_bone_pose_rotation(
			target_index,
			desired_local.basis.orthonormalized().get_rotation_quaternion()
		)
		_skeleton.set_bone_pose_position(target_index, desired_local.origin)
	_apply_retargeted_leg_chain(false)
	_apply_retargeted_leg_chain(true)
	if _retarget_parachute_pose_active:
		_apply_saved_parachute_arm_pose(false)
		_apply_saved_parachute_arm_pose(true)
	else:
		_apply_retargeted_arm_chain(false)
		_apply_retargeted_arm_chain(true)


func _apply_saved_parachute_arm_pose(right_side: bool) -> void:
	# The parachute pose predates the general Mixamo library and was tuned by hand
	# against these weighted ARP bones. Preserve that authored route instead of
	# passing it through the newer fixed-length locomotion/gesture solver.
	var source_prefix := "mixamorig_Right" if right_side else "mixamorig_Left"
	var suffix := ".r" if right_side else ".l"
	var mappings := [
		[source_prefix + "Shoulder", "shoulder" + suffix],
		[source_prefix + "Arm", "c_arm_twist_offset" + suffix],
		[source_prefix + "Arm", "arm_stretch" + suffix],
		[source_prefix + "ForeArm", "forearm_stretch" + suffix],
		[source_prefix + "ForeArm", "forearm_twist" + suffix],
		[source_prefix + "Hand", "hand" + suffix],
	]
	for mapping in mappings:
		var source_index := _find_mixamo_source_bone(
			_retarget_source_skeleton, StringName(mapping[0])
		)
		var target_index := _skeleton.find_bone(String(mapping[1]))
		if source_index < 0 or target_index < 0:
			continue
		_apply_source_motion_to_target_bone(source_index, target_index)


func _apply_source_motion_to_target_bone(source_index: int, target_index: int) -> void:
	var source_rest := (
		_retarget_source_skeleton.get_bone_global_rest(source_index).orthonormalized()
	)
	var source_pose := (
		_retarget_source_skeleton.get_bone_global_pose(source_index).orthonormalized()
	)
	var target_rest := _skeleton.get_bone_global_rest(target_index).orthonormalized()
	var desired_global := (source_pose * source_rest.affine_inverse()) * target_rest
	var parent_index := _skeleton.get_bone_parent(target_index)
	var desired_local := desired_global
	if parent_index >= 0:
		desired_local = (
			_skeleton.get_bone_global_pose(parent_index).affine_inverse()
			* desired_global
		)
	_skeleton.set_bone_pose_rotation(
		target_index,
		desired_local.basis.orthonormalized().get_rotation_quaternion()
	)
	_skeleton.set_bone_pose_position(target_index, desired_local.origin)


func _apply_retargeted_arm_chain(right_side: bool) -> void:
	var source_prefix := "mixamorig_Right" if right_side else "mixamorig_Left"
	var target_suffix := ".r" if right_side else ".l"
	var source_shoulder := _find_mixamo_source_bone(
		_retarget_source_skeleton, StringName(source_prefix + "Shoulder")
	)
	var source_arm := _find_mixamo_source_bone(
		_retarget_source_skeleton, StringName(source_prefix + "Arm")
	)
	var source_forearm := _find_mixamo_source_bone(
		_retarget_source_skeleton, StringName(source_prefix + "ForeArm")
	)
	var source_hand := _find_mixamo_source_bone(
		_retarget_source_skeleton, StringName(source_prefix + "Hand")
	)
	var source_palm := _find_mixamo_source_bone(
		_retarget_source_skeleton, StringName(source_prefix + "HandMiddle1")
	)
	var target_shoulder := _skeleton.find_bone("c_shoulder" + target_suffix)
	var target_arm := _skeleton.find_bone("arm" + target_suffix)
	var target_forearm := _skeleton.find_bone("forearm" + target_suffix)
	var target_hand := _skeleton.find_bone("hand" + target_suffix)
	var target_palm := _skeleton.find_bone("c_middle1_base" + target_suffix)
	if source_shoulder < 0 or source_arm < 0 or source_forearm < 0 or source_hand < 0 \
			or source_palm < 0 or target_shoulder < 0 or target_arm < 0 \
			or target_forearm < 0 or target_hand < 0 or target_palm < 0:
		return

	_aim_target_bone_from_source_segment(
		target_shoulder, target_arm, source_shoulder, source_arm
	)
	_aim_target_bone_from_source_segment(
		target_arm, target_forearm, source_arm, source_forearm
	)
	_aim_target_bone_from_source_segment(
		target_forearm, target_hand, source_forearm, source_hand
	)
	_aim_target_bone_from_source_segment(
		target_hand, target_palm, source_hand, source_palm, true
	)
	_apply_arm_deform_bones(right_side, target_arm, target_forearm)


func _apply_retargeted_leg_chain(right_side: bool) -> void:
	var source_prefix := "mixamorig_Right" if right_side else "mixamorig_Left"
	var suffix := ".r" if right_side else ".l"
	var source_thigh := _find_mixamo_source_bone(
		_retarget_source_skeleton, StringName(source_prefix + "UpLeg")
	)
	var source_leg := _find_mixamo_source_bone(
		_retarget_source_skeleton, StringName(source_prefix + "Leg")
	)
	var source_foot := _find_mixamo_source_bone(
		_retarget_source_skeleton, StringName(source_prefix + "Foot")
	)
	var source_toe := _find_mixamo_source_bone(
		_retarget_source_skeleton, StringName(source_prefix + "ToeBase")
	)
	var target_thigh := _skeleton.find_bone("thigh" + suffix)
	var target_leg := _skeleton.find_bone("leg" + suffix)
	var target_foot := _skeleton.find_bone("foot" + suffix)
	var target_toe := _skeleton.find_bone("toes_01" + suffix)
	if source_thigh < 0 or source_leg < 0 or source_foot < 0 or source_toe < 0 \
			or target_thigh < 0 or target_leg < 0 or target_foot < 0 or target_toe < 0:
		return

	_aim_target_bone_from_source_segment(
		target_thigh, target_leg, source_thigh, source_leg
	)
	_aim_target_bone_from_source_segment(
		target_leg, target_foot, source_leg, source_foot
	)
	_apply_leg_deform_bones(right_side, target_thigh, target_leg)
	_anchor_target_bone_to_solved_parent(target_leg, target_foot)
	_aim_target_bone_from_source_segment(
		target_foot, target_toe, source_foot, source_toe, true
	)


func _apply_leg_deform_bones(
		right_side: bool,
		target_thigh: int,
		target_leg: int
) -> void:
	var suffix := ".r" if right_side else ".l"
	var deform_links := [
		[target_thigh, _skeleton.find_bone("thigh_stretch" + suffix)],
		[target_thigh, _skeleton.find_bone("thigh_twist" + suffix)],
		[target_leg, _skeleton.find_bone("leg_stretch" + suffix)],
		[target_leg, _skeleton.find_bone("leg_twist" + suffix)],
	]
	for link in deform_links:
		var control_index := int(link[0])
		var deform_index := int(link[1])
		if control_index < 0 or deform_index < 0:
			continue
		_apply_control_motion_to_deform_bone(control_index, deform_index)


func _anchor_target_bone_to_solved_parent(
		solved_parent: int,
		target_bone: int
) -> void:
	var solved_parent_rest := _skeleton.get_bone_global_rest(solved_parent)
	var target_rest := _skeleton.get_bone_global_rest(target_bone)
	var rest_offset := solved_parent_rest.affine_inverse() * target_rest
	var desired_global_position := (
		_skeleton.get_bone_global_pose(solved_parent) * rest_offset
	).origin
	var actual_parent := _skeleton.get_bone_parent(target_bone)
	var desired_local_position := desired_global_position
	if actual_parent >= 0:
		desired_local_position = (
			_skeleton.get_bone_global_pose(actual_parent).affine_inverse()
			* Transform3D(Basis.IDENTITY, desired_global_position)
		).origin
	_skeleton.set_bone_pose_position(target_bone, desired_local_position)


func _apply_arm_deform_bones(
		right_side: bool,
		target_arm: int,
		target_forearm: int
) -> void:
	# Auto-Rig Pro exported both control bones and a separate set of weighted
	# deformation bones. The visible sleeves use the latter. Move them by the
	# already-solved ARP control-chain deltas so they stay on the same shoulder,
	# elbow, and wrist landmarks without importing Mixamo limb translations.
	var suffix := ".r" if right_side else ".l"
	var deform_links := [
		[target_arm, _skeleton.find_bone("c_arm_twist_offset" + suffix)],
		[target_arm, _skeleton.find_bone("arm_stretch" + suffix)],
		[target_forearm, _skeleton.find_bone("forearm_stretch" + suffix)],
		[target_forearm, _skeleton.find_bone("forearm_twist" + suffix)],
	]
	for link in deform_links:
		var control_index := int(link[0])
		var deform_index := int(link[1])
		if control_index < 0 or deform_index < 0:
			continue
		_apply_control_motion_to_deform_bone(control_index, deform_index)


func _apply_control_motion_to_deform_bone(control_index: int, deform_index: int) -> void:
	var control_rest := _skeleton.get_bone_global_rest(control_index).orthonormalized()
	var control_pose := _skeleton.get_bone_global_pose(control_index).orthonormalized()
	var deform_rest := _skeleton.get_bone_global_rest(deform_index).orthonormalized()
	var desired_global := (control_pose * control_rest.affine_inverse()) * deform_rest
	var parent_index := _skeleton.get_bone_parent(deform_index)
	var desired_local := desired_global
	if parent_index >= 0:
		desired_local = (
			_skeleton.get_bone_global_pose(parent_index).affine_inverse()
			* desired_global
		)
	_skeleton.set_bone_pose_rotation(
		deform_index,
		desired_local.basis.orthonormalized().get_rotation_quaternion()
	)
	_skeleton.set_bone_pose_position(deform_index, desired_local.origin)


func _aim_target_bone_from_source_segment(
		target_bone: int,
		target_child: int,
		source_bone: int,
		source_child: int,
		transfer_twist: bool = false
) -> void:
	var source_rest := _retarget_source_skeleton.get_bone_global_rest(source_bone)
	var source_child_rest := _retarget_source_skeleton.get_bone_global_rest(source_child)
	var source_from := _retarget_source_skeleton.get_bone_global_pose(source_bone).origin
	var source_to := _retarget_source_skeleton.get_bone_global_pose(source_child).origin
	var desired_direction := source_to - source_from
	var target_rest := _skeleton.get_bone_global_rest(target_bone)
	var target_child_rest := _skeleton.get_bone_global_rest(target_child)
	var rest_direction := target_child_rest.origin - target_rest.origin
	var source_rest_direction := source_child_rest.origin - source_rest.origin
	if desired_direction.length_squared() < 0.000001 \
			or rest_direction.length_squared() < 0.000001 \
			or source_rest_direction.length_squared() < 0.000001:
		return
	var desired_axis := desired_direction.normalized()
	var alignment := Quaternion(rest_direction.normalized(), desired_axis)
	var desired_global_basis := (Basis(alignment) * target_rest.basis).orthonormalized()
	if transfer_twist:
		# Hands and feet need the source roll as well as its segment direction.
		# Extract only the residual twist after the source rest segment has been
		# swung to its animated direction, then apply it about the shared axis.
		var source_swing := Quaternion(source_rest_direction.normalized(), desired_axis)
		var source_swing_basis := (
			Basis(source_swing) * source_rest.basis
		).orthonormalized()
		var source_pose_basis := (
			_retarget_source_skeleton.get_bone_global_pose(source_bone).basis.orthonormalized()
		)
		var residual_rotation := (
			source_pose_basis * source_swing_basis.inverse()
		).orthonormalized().get_rotation_quaternion()
		var source_twist := _extract_twist_about_axis(residual_rotation, desired_axis)
		desired_global_basis = (
			Basis(source_twist) * desired_global_basis
		).orthonormalized()
	var parent_index := _skeleton.get_bone_parent(target_bone)
	var desired_local_basis := desired_global_basis
	if parent_index >= 0:
		desired_local_basis = (
			_skeleton.get_bone_global_pose(parent_index).basis.inverse()
			* desired_global_basis
		).orthonormalized()
	_skeleton.set_bone_pose_rotation(
		target_bone, desired_local_basis.get_rotation_quaternion()
	)


func _extract_twist_about_axis(rotation: Quaternion, axis: Vector3) -> Quaternion:
	var unit_axis := axis.normalized()
	var vector_part := Vector3(rotation.x, rotation.y, rotation.z)
	var projected := unit_axis * vector_part.dot(unit_axis)
	var twist := Quaternion(projected.x, projected.y, projected.z, rotation.w)
	if twist.length_squared() < 0.000001:
		return Quaternion.IDENTITY
	return twist.normalized()


func _apply_parachute_source_pose_adjustments() -> void:
	if _retarget_source_skeleton == null or parachute_pose_settings == null:
		return
	for mapping in PARACHUTE_SOURCE_ROTATION_SETTINGS:
		var bone_index := _retarget_source_skeleton.find_bone(StringName(mapping[0]))
		if bone_index < 0:
			continue
		var offset_degrees: Vector3 = parachute_pose_settings.get(StringName(mapping[1]))
		if offset_degrees.is_zero_approx():
			continue
		var animated_rotation := _retarget_source_skeleton.get_bone_pose_rotation(bone_index)
		var offset_radians := Vector3(
			deg_to_rad(offset_degrees.x),
			deg_to_rad(offset_degrees.y),
			deg_to_rad(offset_degrees.z)
		)
		_retarget_source_skeleton.set_bone_pose_rotation(
			bone_index,
			animated_rotation * Quaternion.from_euler(offset_radians)
		)

	var relaxation := clampf(float(parachute_pose_settings.get("grip_relaxation")), 0.0, 1.0)
	if relaxation <= 0.0:
		return
	for bone_name in PARACHUTE_GRIP_SOURCE_BONES:
		var bone_index := _retarget_source_skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var animated_rotation := _retarget_source_skeleton.get_bone_pose_rotation(bone_index)
		var rest_rotation := (
			_retarget_source_skeleton.get_bone_rest(bone_index)
			.basis.orthonormalized().get_rotation_quaternion()
		)
		_retarget_source_skeleton.set_bone_pose_rotation(
			bone_index,
			animated_rotation.slerp(rest_rotation, relaxation)
		)


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
			if _is_arp_rig():
				# The Auto-Rig Pro export stores its seated pose in a one-frame baked animation.
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
			if _is_arp_rig():
				# The retained Auto-Rig Pro export has a seated authored pose. Counteract
				# the seated legs instead of forcing a 180-degree leg flip.
				return _make_pose(-65.0, -55.0, 15.0, 5.0, -5.0, -25.0, 0.0, 0.0, -60.0, 25.0, 0.0, 55.0, 0.0, 0.0, 0.0, 0.0, 65.0, -10.0, -8.0)
			if _is_mixamo_rig():
				# Mixamo T-pose: legs already hang down at rest (upper_leg_x=0). Arms start horizontal.
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
	# pose_target_path may point directly at the visual named in
	# cockpit_hidden_mesh_names, so include the target root itself.
	_collect_cockpit_hidden_nodes(_pose_target_root)


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
