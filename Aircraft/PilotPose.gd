@tool
extends Node3D
## Poses a rigged pilot character into a seated cockpit position.
## Attach this script to the Pilot.glb instance in an aircraft scene.

@export_group("Legs")
@export var upper_leg_x: float = 75.0:
	set(v): upper_leg_x = v; _apply_pose()
@export var lower_leg_x: float = 80.0:
	set(v): lower_leg_x = v; _apply_pose()
@export var upper_leg_spread: float = 5.0:  ## Z rotation to spread knees apart
	set(v): upper_leg_spread = v; _apply_pose()

@export_group("Arms")
@export var upper_arm_x: float = 90.0:
	set(v): upper_arm_x = v; _apply_pose()
@export var upper_arm_z: float = 50.0:  ## Brings arms down from T-pose
	set(v): upper_arm_z = v; _apply_pose()
@export var lower_arm_x: float = 90.0:  ## Elbow bend
	set(v): lower_arm_x = v; _apply_pose()

@export_group("Hands")
@export var wrist_x: float = 0.0:
	set(v): wrist_x = v; _apply_pose()
@export var wrist_y: float = 0.0:
	set(v): wrist_y = v; _apply_pose()
@export var finger_curl: float = 60.0:  ## Curl fingers for grip
	set(v): finger_curl = v; _apply_pose()

@export_group("Spine")
@export var head_pitch: float = -5.0:  ## Slight forward tilt (looking at instruments)
	set(v): head_pitch = v; _apply_pose()
@export var neck_pitch: float = -3.0:
	set(v): neck_pitch = v; _apply_pose()

var _skeleton: Skeleton3D
var _ready_done := false


func _ready() -> void:
	_skeleton = _find_skeleton(self)
	if not _skeleton:
		push_warning("PilotPose: No Skeleton3D found in children")
		return

	# Stop any AnimationPlayer from overriding the pose
	var ap := _find_anim_player(self)
	if ap:
		ap.stop()
		# In-game: disable it so it doesn't play on ready
		if not Engine.is_editor_hint():
			ap.active = false

	_ready_done = true
	_apply_pose()


func _apply_pose() -> void:
	if not _ready_done or not _skeleton:
		return

	_skeleton.reset_bone_poses()

	# --- LEGS ---
	_set_rot("UpperLeg.L", upper_leg_x, 0, -upper_leg_spread)
	_set_rot("UpperLeg.R", upper_leg_x, 0, upper_leg_spread)
	_set_rot("LowerLeg.L", lower_leg_x, 0, 0)
	_set_rot("LowerLeg.R", lower_leg_x, 0, 0)

	# --- FEET (parented to Root, not legs — position them flat) ---
	# Leave feet at rest pose; they're IK targets and won't visually matter much
	# in the cockpit since legs are mostly hidden.

	# --- ARMS ---
	_set_rot("UpperArm.L", upper_arm_x, 0, upper_arm_z)
	_set_rot("UpperArm.R", upper_arm_x, 0, -upper_arm_z)
	_set_rot("LowerArm.L", lower_arm_x, 0, 0)
	_set_rot("LowerArm.R", lower_arm_x, 0, 0)

	# --- WRISTS ---
	_set_rot("Wrist.L", wrist_x, wrist_y, 0)
	_set_rot("Wrist.R", wrist_x, -wrist_y, 0)

	# --- FINGERS (curl for grip) ---
	for side in ["L", "R"]:
		for finger in ["Index", "Middle", "Ring", "Pinky"]:
			for joint in ["2", "3", "4"]:
				_set_rot("%s%s.%s" % [finger, joint, side], finger_curl, 0, 0)
		# Thumb wraps differently
		_set_rot("Thumb2.%s" % side, finger_curl * 0.5, 0, 0)
		_set_rot("Thumb3.%s" % side, finger_curl * 0.7, 0, 0)

	# --- SPINE / HEAD ---
	_set_rot("Head", head_pitch, 0, 0)
	_set_rot("Neck", neck_pitch, 0, 0)


func _set_rot(bone_name: String, x_deg: float, y_deg: float, z_deg: float) -> void:
	var idx := _skeleton.find_bone(bone_name)
	if idx >= 0:
		_skeleton.set_bone_pose_rotation(idx, Quaternion.from_euler(Vector3(
			deg_to_rad(x_deg), deg_to_rad(y_deg), deg_to_rad(z_deg))))


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_anim_player(child)
		if result:
			return result
	return null
