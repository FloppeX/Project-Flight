@tool
extends Node3D
class_name CockpitPilotMount

## Lightweight per-aircraft seat marker. The actual animated rig is checked out
## from CockpitPilotPool only while this aircraft is presented to the player or
## while its pilot is physically ejecting.

const PILOT_VISUAL_SCENE: PackedScene = preload(
	"res://Models/Characters/pilot/CockpitPilotCharacter.tscn"
)
const PilotAppearance := preload("res://Aircraft/PilotAppearance.gd")

@export_group("Legs")
@export var upper_leg_x: float = 0.0
@export var lower_leg_x: float = 0.0
@export var upper_leg_spread: float = 0.0
@export_range(0.0, 120.0, 1.0, "degrees") var seated_knee_bend_degrees: float = 45.0
@export_range(-30.0, 45.0, 1.0, "degrees") var seated_foot_toe_up_degrees: float = 15.0
@export_group("Torso")
@export var abdomen_pitch: float = 3.0
@export var torso_pitch: float = 2.0
@export_group("Shoulders")
@export var shoulder_x: float = 0.0
@export var shoulder_y: float = 0.0
@export var shoulder_z: float = 0.0
@export_group("Arms")
@export var upper_arm_x: float = 0.0
@export var upper_arm_y: float = 0.0
@export var upper_arm_z: float = 0.0
@export var lower_arm_x: float = 65.0
@export var lower_arm_y: float = 0.0
@export var lower_arm_z: float = 0.0
@export_group("Hands")
@export var wrist_x: float = 2.0
@export var wrist_y: float = 0.0
@export var finger_curl: float = 20.0
@export_group("Head")
@export var neck_pitch: float = 0.0
@export var head_pitch: float = 0.0
@export_range(0.0, 30.0, 1.0, "degrees") var seated_neck_recline_degrees: float = 10.0
@export_group("Cockpit Visibility")
@export var hide_head_in_cockpit: bool = true
@export var cockpit_hidden_mesh_names: PackedStringArray = PackedStringArray(["Pilot"])
@export_group("Animation")
@export var initial_pose_name: StringName = &"sitting"
@export var initial_baked_animation: StringName = &"piloting"
@export var initial_baked_animation_speed: float = 1.0
@export var defer_initial_baked_animation_until_presented: bool = true
@export var editor_preview_animation_time_s: float = 1.5
## Static passengers sample this approved cockpit clip once, rather than using
## the imported rigAction whose root is authored in a different seat space.
@export var static_seated_animation: StringName = &"piloting"
@export var static_seated_animation_time_s: float = 1.5

var _pilot_visual: Node3D = null
var _ejection_committed: bool = false
var _using_pool: bool = false
var _pilot_pool: Node = null
var _static_seated_pose_requested: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		_acquire_visual(true, false)


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or not _using_pool:
		return
	# A checked-out visual is a child of this mount. Detach and return it before
	# the aircraft/mount is destroyed, otherwise the pooled rig is destroyed too
	# and the reserve keeps a stale reference.
	_release_visual()


func is_pooled_aircraft_occupant_mount() -> bool:
	return true


func set_presentation_active(active: bool) -> void:
	if active:
		var pilot := _acquire_visual(false, false)
		if pilot != null and _static_seated_pose_requested:
			_apply_static_seated_pose_to_visual(pilot)
		elif pilot != null and pilot.has_method("set_presentation_active"):
			pilot.call("set_presentation_active", true)
		return
	if _ejection_committed:
		return
	_release_visual()


func set_ejection_pose(pose_name: StringName, blend_time_s: float = -1.0) -> void:
	_ejection_committed = true
	var pilot := _acquire_visual(false, false)
	if pilot != null and pilot.has_method("set_ejection_pose"):
		pilot.call("set_ejection_pose", pose_name, blend_time_s)


func play_baked_animation(animation_name: StringName, speed_scale: float = 1.0) -> bool:
	var pilot := _acquire_visual(false, false)
	if pilot == null or not pilot.has_method("play_baked_animation"):
		return false
	return bool(pilot.call("play_baked_animation", animation_name, speed_scale))


func apply_static_seated_pose() -> bool:
	# Passenger seat records must not check out an expensive body merely because
	# somebody boarded an aircraft that the player cannot currently see.
	_static_seated_pose_requested = true
	initial_baked_animation = &""
	var pilot := get_pilot_visual()
	if pilot == null:
		return true
	return _apply_static_seated_pose_to_visual(pilot)


func ensure_pilot_visual(animate: bool = false) -> Node3D:
	return _acquire_visual(false, animate)


func ensure_static_preview_visual() -> Node3D:
	# Off-tree equipment previews must not query the runtime pool or autoloads.
	# They own one local visual which is sampled once and then stripped of logic.
	return _acquire_visual(true, false)


func get_pilot_visual() -> Node3D:
	return _pilot_visual if _pilot_visual != null and is_instance_valid(_pilot_visual) else null


func refresh_pilot_appearance() -> void:
	var pilot := get_pilot_visual()
	if pilot != null:
		_apply_aircraft_pilot_livery(pilot)


func _acquire_visual(editor_preview: bool, animate: bool) -> Node3D:
	if _pilot_visual != null and is_instance_valid(_pilot_visual):
		# Presentation budgeting may reaffirm an already-visible cockpit every few
		# frames. Reassigning PilotPose's exported controls here invokes their
		# setters, which resets the skeleton to the procedural fallback pose. During
		# normal play the AnimationPlayer covers that reset on its next tick; while
		# photo mode is paused it remains visibly standing. A checked-out visual was
		# fully configured when acquired, so repeated activation must be idempotent.
		return _pilot_visual

	_using_pool = false
	_pilot_pool = null
	if not editor_preview:
		var pool := get_node_or_null("/root/CockpitPilotPool")
		if pool != null and pool.has_method("acquire_pilot"):
			_pilot_visual = pool.call(
				"acquire_pilot", not _static_seated_pose_requested
			) as Node3D
			_using_pool = _pilot_visual != null
			if _using_pool:
				_pilot_pool = pool
	if _pilot_visual == null:
		_pilot_visual = PILOT_VISUAL_SCENE.instantiate() as Node3D
	if _pilot_visual == null:
		return null

	_configure_visual(_pilot_visual)
	_pilot_visual.name = "PilotVisual"
	add_child(_pilot_visual)
	_pilot_visual.transform = Transform3D.IDENTITY
	_apply_aircraft_pilot_livery(_pilot_visual)
	if _static_seated_pose_requested:
		_apply_static_seated_pose_to_visual(_pilot_visual)
	elif animate and _pilot_visual.has_method("set_presentation_active"):
		_pilot_visual.call("set_presentation_active", true)
	return _pilot_visual


func _apply_static_seated_pose_to_visual(pilot: Node3D) -> bool:
	if static_seated_animation != &"" and pilot.has_method("apply_static_baked_pose"):
		if bool(pilot.call(
			"apply_static_baked_pose",
			static_seated_animation,
			maxf(static_seated_animation_time_s, 0.0)
		)):
			return true
	# Retain the inexpensive authored fallback for character variants without the
	# shared baked library.
	if not pilot.has_method("apply_static_seated_pose"):
		return false
	return bool(pilot.call("apply_static_seated_pose"))


func _configure_visual(pilot: Node3D) -> void:
	pilot.set("upper_leg_x", upper_leg_x)
	pilot.set("lower_leg_x", lower_leg_x)
	pilot.set("upper_leg_spread", upper_leg_spread)
	pilot.set(
		"seated_knee_bend_degrees",
		seated_knee_bend_degrees
	)
	pilot.set(
		"seated_foot_toe_up_degrees",
		seated_foot_toe_up_degrees
	)
	pilot.set("abdomen_pitch", abdomen_pitch)
	pilot.set("torso_pitch", torso_pitch)
	pilot.set("shoulder_x", shoulder_x)
	pilot.set("shoulder_y", shoulder_y)
	pilot.set("shoulder_z", shoulder_z)
	pilot.set("upper_arm_x", upper_arm_x)
	pilot.set("upper_arm_y", upper_arm_y)
	pilot.set("upper_arm_z", upper_arm_z)
	pilot.set("lower_arm_x", lower_arm_x)
	pilot.set("lower_arm_y", lower_arm_y)
	pilot.set("lower_arm_z", lower_arm_z)
	pilot.set("wrist_x", wrist_x)
	pilot.set("wrist_y", wrist_y)
	pilot.set("finger_curl", finger_curl)
	pilot.set("neck_pitch", neck_pitch)
	pilot.set("head_pitch", head_pitch)
	pilot.set("seated_neck_recline_degrees", seated_neck_recline_degrees)
	pilot.set("hide_head_in_cockpit", hide_head_in_cockpit)
	pilot.set("cockpit_hidden_mesh_names", cockpit_hidden_mesh_names)
	pilot.set("cockpit_camera_path", NodePath("../../CameraCockpit/Camera3D"))
	pilot.set("initial_pose_name", initial_pose_name)
	pilot.set("initial_baked_animation", initial_baked_animation)
	pilot.set("initial_baked_animation_speed", initial_baked_animation_speed)
	pilot.set(
		"defer_initial_baked_animation_until_presented",
		defer_initial_baked_animation_until_presented
	)
	pilot.set("editor_preview_animation_time_s", editor_preview_animation_time_s)


func _apply_aircraft_pilot_livery(pilot: Node3D) -> void:
	var appearance_source := _find_appearance_source()
	var livery := get_node_or_null("/root/Livery") if is_inside_tree() else null
	if appearance_source != null and appearance_source != self:
		PilotAppearance.copy_palette_metadata(appearance_source, self)
	if appearance_source != null and livery != null \
			and livery.has_method("apply_pilot_palette_to_visual"):
		livery.call("apply_pilot_palette_to_visual", appearance_source, pilot)


func _find_appearance_source() -> Node:
	var current: Node = self
	while current != null:
		if current.has_meta(PilotAppearance.META_KEY) \
				and PilotAppearance.is_valid_palette(
					current.get_meta(PilotAppearance.META_KEY)
				):
			return current
		current = current.get_parent()
	return get_parent()


func _release_visual() -> void:
	if _pilot_visual == null or not is_instance_valid(_pilot_visual):
		_pilot_visual = null
		return
	var pilot := _pilot_visual
	_pilot_visual = null
	if _using_pool:
		var pool := _pilot_pool
		if pool != null and pool.has_method("release_pilot"):
			pool.call("release_pilot", pilot)
			_using_pool = false
			_pilot_pool = null
			return
	if pilot.get_parent() != null:
		pilot.get_parent().remove_child(pilot)
	pilot.queue_free()
	_using_pool = false
	_pilot_pool = null
