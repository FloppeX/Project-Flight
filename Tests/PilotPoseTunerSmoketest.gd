extends SceneTree

const TUNER_SCENE := "res://tools/PilotPoseTuner.tscn"
const OUTPUT_PATH := "res://screenshots/pilot_pose_tuner.png"
const MIRROR_OUTPUT_PATH := "res://screenshots/pilot_pose_mirrored_preview.png"
const PREVIEW_SIZE := Vector2i(1600, 900)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(TUNER_SCENE) as PackedScene
	if packed == null:
		_fail("tuner scene did not load")
		return
	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var tuner := packed.instantiate() as Node3D
	if tuner == null:
		_fail("tuner scene did not instantiate")
		return
	viewport.add_child(tuner)
	for frame in range(12):
		await process_frame

	var pilot := tuner.get_node_or_null("Pilot") as Node3D
	var timeline := tuner.find_child("Timeline", true, false) as HSlider
	var save_button := tuner.find_child("SavePose", true, false) as Button
	var reload_button := tuner.find_child("ReloadSaved", true, false) as Button
	var mirror_button := tuner.find_child("MirrorLeftToRight", true, false) as Button
	var grip := tuner.find_child("GripRelaxation", true, false) as SpinBox
	var left_shoulder_x := tuner.find_child("left_shoulder_degrees_X", true, false) as SpinBox
	var left_arm_x := tuner.find_child("left_upper_arm_degrees_X", true, false) as SpinBox
	if pilot == null or timeline == null or save_button == null or reload_button == null \
			or mirror_button == null \
			or grip == null \
			or left_shoulder_x == null or left_arm_x == null:
		_fail("tuner is missing its pilot or editing controls")
		return
	if not bool(pilot.get("_retarget_animation_active")) or timeline.max_value < 1.0:
		_fail("tuner did not load the live parachute animation")
		return
	if not bool(pilot.call("is_retarget_preview_paused")):
		_fail("tuner did not pause the clip for frame editing")
		return
	mirror_button.pressed.emit()
	await process_frame
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	var mirrored_image := viewport.get_texture().get_image()
	if mirrored_image == null or mirrored_image.is_empty() \
			or mirrored_image.save_png(MIRROR_OUTPUT_PATH) != OK:
		_fail("mirrored pose preview could not be saved")
		return
	reload_button.pressed.emit()
	await process_frame
	var visible_pilot := pilot.get_node_or_null("Pilot") as Node3D
	var skeleton := _find_skeleton(visible_pilot)
	var shoulder_index := skeleton.find_bone("shoulder.l") if skeleton != null else -1
	var arm_index := skeleton.find_bone("arm_stretch.l") if skeleton != null else -1
	if shoulder_index < 0 or arm_index < 0:
		_fail("tuner's visible Auto-Rig Pro shoulder/arm was not found")
		return
	var original_shoulder_value := left_shoulder_x.value
	var original_shoulder_rotation := (
		skeleton.get_bone_global_pose(shoulder_index).basis.get_rotation_quaternion()
	)
	left_shoulder_x.value = original_shoulder_value + 8.0
	await process_frame
	var adjusted_shoulder_rotation := (
		skeleton.get_bone_global_pose(shoulder_index).basis.get_rotation_quaternion()
	)
	left_shoulder_x.value = original_shoulder_value
	await process_frame
	if original_shoulder_rotation.angle_to(adjusted_shoulder_rotation) < deg_to_rad(4.0):
		_fail("shoulder control did not update the visible pilot")
		return
	var original_value := left_arm_x.value
	var original_rotation := (
		skeleton.get_bone_global_pose(arm_index).basis.get_rotation_quaternion()
	)
	left_arm_x.value = original_value + 8.0
	await process_frame
	var adjusted_rotation := (
		skeleton.get_bone_global_pose(arm_index).basis.get_rotation_quaternion()
	)
	left_arm_x.value = original_value
	await process_frame
	if original_rotation.angle_to(adjusted_rotation) < deg_to_rad(4.0):
		_fail("tuner control did not update the visible pilot")
		return
	var settings := pilot.get("parachute_pose_settings") as Resource
	settings.set("left_shoulder_degrees", Vector3(17.0, -11.0, 8.0))
	settings.set("right_shoulder_degrees", Vector3.ZERO)
	pilot.call("refresh_retarget_preview")
	mirror_button.pressed.emit()
	await process_frame
	var mirrored_right: Vector3 = settings.get("right_shoulder_degrees")
	if mirrored_right.length() < 5.0:
		_fail("left-to-right mirror did not produce a right shoulder rotation")
		return
	reload_button.pressed.emit()
	await process_frame

	RenderingServer.force_draw(false, 0.0)
	await process_frame
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("tuner preview viewport produced no image")
		return
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		_fail("tuner preview could not be saved (error %d)" % error)
		return
	print("[PilotPoseTunerSmoketest] PASS timeline=%.2fs controls=live screenshot=%s" % [
		timeline.max_value, ProjectSettings.globalize_path(OUTPUT_PATH),
	])
	quit(0)


func _fail(reason: String) -> void:
	push_error("[PilotPoseTunerSmoketest] FAIL %s" % reason)
	quit(1)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
