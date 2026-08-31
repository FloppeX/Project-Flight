extends SceneTree

const PILOT_SCENE := "res://Models/Characters/pilot/PilotCharacter.tscn"
const ARCHIVE_SENTINEL := "res://Models/Characters/archive/.gdignore"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not FileAccess.file_exists(ARCHIVE_SENTINEL):
		_fail("pilot archive is not protected by .gdignore")
		return

	var packed := load(PILOT_SCENE) as PackedScene
	if packed == null:
		_fail("canonical pilot scene did not load")
		return
	var pilot := packed.instantiate() as Node3D
	root.add_child(pilot)
	await process_frame

	var visible_character := pilot.get_node_or_null("Pilot") as Node3D
	if visible_character == null:
		_fail("canonical visible Pilot branch is missing")
		return
	if pilot.get_node_or_null("ParachutePlaceholder") != null:
		_fail("legacy parachute placeholder is still live")
		return
	var skeleton := _find_skeleton(visible_character)
	if skeleton == null:
		_fail("retained pilot mesh has no Skeleton3D")
		return
	if skeleton.find_bone("arm_stretch.l") < 0 or skeleton.find_bone("thigh_stretch.l") < 0:
		_fail("retained pilot is not using the expected Auto-Rig Pro export bones")
		return

	pilot.call("set_ejection_pose", &"grounded", 0.0)
	await process_frame
	if bool(pilot.get("_retarget_animation_active")):
		_fail("standing pose unexpectedly started an animation source")
		return

	pilot.call("set_ejection_pose", &"parachute", 0.0)
	await process_frame
	if not bool(pilot.get("_retarget_animation_active")):
		_fail("parachuting pose did not start the retargeted motion")
		return
	for frame in range(8):
		await process_frame
	var parachute_pairs := pilot.get("_retarget_bone_pairs") as Array
	if parachute_pairs.size() < 20:
		_fail("parachuting retarget mapped too few bones: %d" % parachute_pairs.size())
		return
	var source_root := pilot.get("_retarget_source_root") as Node3D
	if source_root == null or source_root.visible:
		_fail("parachuting motion-source character was not hidden")
		return
	var parachute_source_skeleton := pilot.get("_retarget_source_skeleton") as Skeleton3D
	var source_hips := parachute_source_skeleton.find_bone("mixamorig_Hips") \
			if parachute_source_skeleton != null else -1
	if source_hips < 0 or parachute_source_skeleton.get_bone_global_pose(source_hips).origin.y < 0.5:
		_fail("parachuting source was imported at the wrong scale")
		return
	var left_upper_arm_index := skeleton.find_bone("arm_stretch.l")
	if left_upper_arm_index < 0:
		_fail("parachuting pose arm bone is missing")
		return
	if not bool(pilot.get("_retarget_parachute_pose_active")):
		_fail("parachuting pose tuning was not active")
		return
	var pose_settings := pilot.get("parachute_pose_settings") as Resource
	if pose_settings == null:
		_fail("parachute pose settings resource is missing")
		return
	pilot.call("set_retarget_preview_paused", true)
	var clip_length := float(pilot.call("get_retarget_preview_length"))
	if clip_length < 1.0:
		_fail("parachute tuner received an invalid clip length: %.2f" % clip_length)
		return
	pilot.call("seek_retarget_preview", clip_length * 0.5)
	var original_offset: Vector3 = pose_settings.get("left_upper_arm_degrees")
	var raw_rotation := skeleton.get_bone_pose_rotation(left_upper_arm_index)
	pose_settings.set("left_upper_arm_degrees", original_offset + Vector3(7.0, 0.0, 0.0))
	pilot.call("refresh_retarget_preview")
	var adjusted_rotation := skeleton.get_bone_pose_rotation(left_upper_arm_index)
	var tuning_delta := raw_rotation.angle_to(adjusted_rotation)
	pose_settings.set("left_upper_arm_degrees", original_offset)
	pilot.call("refresh_retarget_preview")
	if tuning_delta < deg_to_rad(3.0):
		_fail("parachute tuner did not move the visible pilot arm")
		return
	pilot.call("set_retarget_preview_paused", false)

	pilot.call("set_locomotion_pose", true, 5.5)
	await process_frame
	if not bool(pilot.get("_retarget_animation_active")):
		_fail("running animation did not start the retargeted motion")
		return
	if bool(pilot.get("_retarget_parachute_pose_active")):
		_fail("parachute pose tuning leaked into the running animation")
		return
	var run_pairs := pilot.get("_retarget_bone_pairs") as Array
	if run_pairs.size() < 20:
		_fail("running retarget mapped too few bones: %d" % run_pairs.size())
		return
	var thigh_index := skeleton.find_bone("thigh_stretch.l")
	var first_rotation := skeleton.get_bone_pose_rotation(thigh_index)
	for frame in range(10):
		await process_frame
	var later_rotation := skeleton.get_bone_pose_rotation(thigh_index)
	if first_rotation.angle_to(later_rotation) < 0.01:
		_fail("running clip did not move the retained pilot skeleton")
		return
	pilot.call("set_locomotion_pose", false, 0.0)

	var cockpit := _instantiate("res://Aircraft/CockpitPilot.tscn")
	if cockpit == null or not cockpit.has_method("ensure_pilot_visual") \
			or cockpit.call("get_pilot_visual") != null:
		_fail("cockpit is not a dormant pooled-pilot mount")
		return
	if cockpit.get_node_or_null("ParachutePlaceholder") != null:
		_fail("cockpit still contains a legacy placeholder")
		return
	cockpit.free()

	var downed := _instantiate("res://Models/Characters/DownedPilot.tscn")
	var downed_model := downed.get_node_or_null("Model") if downed != null else null
	if downed_model == null or not downed_model.has_method("set_locomotion_pose"):
		_fail("downed pilot does not use the canonical animated character")
		return
	downed.free()

	var parachute := _instantiate("res://Aircraft/Visuals/Parachute.tscn")
	var parachute_pilot := parachute.get_node_or_null("PilotMount/PilotPreview/Pilot") if parachute != null else null
	if parachute_pilot == null or not parachute_pilot.has_method("set_ejection_pose"):
		_fail("parachute preview does not use the canonical pilot")
		return
	parachute.free()

	print("[PilotCharacterSmoketest] PASS rig=auto_rig_pro parachute_pairs=%d run_pairs=%d clip=%.2fs tuning_delta=%.1fdeg source_meshes=hidden" % [
		parachute_pairs.size(), run_pairs.size(),
		clip_length, rad_to_deg(tuning_delta),
	])
	pilot.free()
	quit(0)


func _instantiate(path: String) -> Node:
	var scene := load(path) as PackedScene
	return scene.instantiate() if scene != null else null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _fail(reason: String) -> void:
	push_error("[PilotCharacterSmoketest] FAIL %s" % reason)
	quit(1)
