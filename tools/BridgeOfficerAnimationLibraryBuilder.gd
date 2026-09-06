extends SceneTree
## Retargets the source FBX clips onto the bridge officer's actual exported rest
## skeleton and saves those local poses as one compact runtime library.

const PILOT_POSE_SCRIPT: Script = preload("res://Aircraft/PilotPose.gd")
const DEFAULT_OFFICER_SCENE_PATH := "res://Models/Characters/Bridge officer.glb"
const DEFAULT_OUTPUT_LIBRARY_PATH := "res://Models/Characters/pilot/animations/bridge_officer_animation_library.tres"
const TARGET_SKELETON_PATH := "Pilot/root/Skeleton3D"
const SAMPLE_FPS := 30.0

const CLIPS := [
	{"file": "Breathing Idle.fbx", "name": &"idle_breathing", "loop": true},
	{"file": "Neutral Idle.fbx", "name": &"idle_neutral", "loop": true},
	{"file": "Idle 3.fbx", "name": &"idle_3", "loop": true},
	{"file": "Idle 4.fbx", "name": &"idle_4", "loop": true},
	{"file": "Idle 5.fbx", "name": &"idle_5", "loop": true},
	{"file": "Idle 6.fbx", "name": &"idle_6", "loop": true},
	{"file": "Idle 7.fbx", "name": &"idle_7", "loop": true},
	{"file": "Walking.fbx", "name": &"walk", "loop": true},
	{"file": "dance - Belly Dance.fbx", "name": &"dance_belly", "loop": false},
	{"file": "dance - Booty Hip Hop Dance.fbx", "name": &"dance_booty_hip_hop", "loop": false},
	{"file": "dance - Chicken Dance.fbx", "name": &"dance_chicken", "loop": false},
	{"file": "dance - Gangnam Style.fbx", "name": &"dance_gangnam", "loop": false},
	{"file": "dance - Hip Hop Dancing.fbx", "name": &"dance_hip_hop", "loop": false},
	{"file": "dance - Locking Hip Hop Dance.fbx", "name": &"dance_locking_hip_hop", "loop": false},
	{"file": "dance - Northern Soul Floor Combo.fbx", "name": &"dance_northern_soul", "loop": false},
]


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var officer_scene_path := DEFAULT_OFFICER_SCENE_PATH
	var output_library_path := DEFAULT_OUTPUT_LIBRARY_PATH
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--officer-scene="):
			officer_scene_path = argument.trim_prefix("--officer-scene=")
		elif argument.begins_with("--output-library="):
			output_library_path = argument.trim_prefix("--output-library=")

	var packed_officer := load(officer_scene_path) as PackedScene
	if packed_officer == null:
		_fail("officer scene did not load")
		return

	var target := Node3D.new()
	target.name = "BodyVisual"
	target.set_script(PILOT_POSE_SCRIPT)
	target.set("pose_target_path", NodePath("Pilot"))
	target.set("flat_shade_pilot_visual", false)
	target.set("hide_head_in_cockpit", false)
	target.set("initial_pose_name", &"")
	target.set("initial_baked_animation", &"")
	var officer := packed_officer.instantiate() as Node3D
	officer.name = "Pilot"
	target.add_child(officer)
	root.add_child(target)
	await process_frame

	var skeleton := target.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		_fail("officer Skeleton3D was not found")
		return
	var library := AnimationLibrary.new()
	for clip in CLIPS:
		var source_path := "res://Models/Characters/pilot/animations/%s" % String(clip["file"])
		var source_scene := load(source_path) as PackedScene
		if source_scene == null or not bool(target.call("_setup_retargeted_animation", source_scene)):
			_fail("retarget setup failed: %s" % source_path)
			return
		var source_player := target.get("_retarget_source_player") as AnimationPlayer
		var source_animation_name := _find_motion_animation(source_player)
		if source_animation_name == &"":
			_fail("source animation was not found: %s" % source_path)
			return
		var source_animation := source_player.get_animation(source_animation_name)
		var baked := _bake_clip(
			target,
			skeleton,
			source_player,
			source_animation_name,
			source_animation.length,
			bool(clip["loop"]),
			StringName(clip["name"])
		)
		if baked == null:
			_fail("bake failed: %s" % source_path)
			return
		var add_error := library.add_animation(StringName(clip["name"]), baked)
		if add_error != OK:
			_fail("could not add %s: %d" % [clip["name"], add_error])
			return

	var save_error := ResourceSaver.save(library, output_library_path)
	if save_error != OK:
		_fail("save failed: %d" % save_error)
		return
	print(
		"[BridgeOfficerAnimationLibraryBuilder] PASS clips=%d output=%s"
		% [library.get_animation_list().size(), ProjectSettings.globalize_path(output_library_path)]
	)
	target.free()
	quit(0)


func _bake_clip(
		target: Node3D,
		skeleton: Skeleton3D,
		source_player: AnimationPlayer,
		source_animation_name: StringName,
		length_s: float,
		looping: bool,
		clip_name: StringName
) -> Animation:
	skeleton.reset_bone_poses()
	var baseline := _capture_bone_poses(skeleton)
	var frame_count := ceili(length_s * SAMPLE_FPS) + 1
	var captured_frames: Array = []
	var times: Array[float] = []
	source_player.active = true
	source_player.play(source_animation_name)
	for frame_index in range(frame_count):
		var time_s := minf(float(frame_index) / SAMPLE_FPS, length_s)
		source_player.seek(time_s, true)
		source_player.advance(0.0)
		target.call("_apply_retargeted_animation_frame")
		captured_frames.append(_capture_bone_poses(skeleton))
		times.append(time_s)

	var animated_bones: Array[int] = []
	for bone_index in range(skeleton.get_bone_count()):
		var baseline_pose: Transform3D = baseline[bone_index]
		for frame in captured_frames:
			var sampled_pose: Transform3D = frame[bone_index]
			if _poses_differ(baseline_pose, sampled_pose):
				animated_bones.append(bone_index)
				break
	if animated_bones.is_empty():
		push_error("[BridgeOfficerAnimationLibraryBuilder] no motion in %s" % clip_name)
		return null

	var baked := Animation.new()
	baked.length = length_s
	baked.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	baked.step = 1.0 / SAMPLE_FPS
	for bone_index in animated_bones:
		var bone_name := skeleton.get_bone_name(bone_index)
		var track_path := NodePath("%s:%s" % [TARGET_SKELETON_PATH, bone_name])
		var position_track := baked.add_track(Animation.TYPE_POSITION_3D)
		baked.track_set_path(position_track, track_path)
		baked.track_set_interpolation_type(position_track, Animation.INTERPOLATION_LINEAR)
		var rotation_track := baked.add_track(Animation.TYPE_ROTATION_3D)
		baked.track_set_path(rotation_track, track_path)
		baked.track_set_interpolation_type(rotation_track, Animation.INTERPOLATION_LINEAR)
		for frame_index in range(captured_frames.size()):
			var pose: Transform3D = captured_frames[frame_index][bone_index]
			baked.track_insert_key(position_track, times[frame_index], pose.origin)
			baked.track_insert_key(
				rotation_track,
				times[frame_index],
				pose.basis.orthonormalized().get_rotation_quaternion()
			)
	if clip_name == &"walk" or String(clip_name).begins_with("dance_"):
		_lock_horizontal_root_motion(baked)
	print(
		"[BridgeOfficerAnimationLibraryBuilder] %s length=%.2f bones=%d tracks=%d"
		% [clip_name, length_s, animated_bones.size(), baked.get_track_count()]
	)
	return baked


func _capture_bone_poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for bone_index in range(skeleton.get_bone_count()):
		poses.append(skeleton.get_bone_pose(bone_index))
	return poses


func _poses_differ(first: Transform3D, second: Transform3D) -> bool:
	return first.origin.distance_to(second.origin) > 0.0001 \
			or first.basis.get_rotation_quaternion().angle_to(
				second.basis.get_rotation_quaternion()
			) > 0.0001


func _lock_horizontal_root_motion(animation: Animation) -> void:
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D \
				or not String(animation.track_get_path(track_index)).ends_with(":root.x"):
			continue
		var anchor := animation.track_get_key_value(track_index, 0) as Vector3
		for key_index in range(animation.track_get_key_count(track_index)):
			var value := animation.track_get_key_value(track_index, key_index) as Vector3
			value.x = anchor.x
			value.z = anchor.z
			animation.track_set_key_value(track_index, key_index, value)


func _find_motion_animation(player: AnimationPlayer) -> StringName:
	var best_name: StringName = &""
	var best_motion := -1.0
	var best_length := -1.0
	for animation_name in player.get_animation_list():
		if String(animation_name).to_upper().contains("RESET"):
			continue
		var animation := player.get_animation(animation_name)
		if animation == null:
			continue
		var motion := _animation_motion_score(animation)
		if motion > best_motion \
				or (is_equal_approx(motion, best_motion) and animation.length > best_length):
			best_name = animation_name
			best_motion = motion
			best_length = animation.length
	return best_name


func _animation_motion_score(animation: Animation) -> float:
	var score := 0.0
	for track_index in range(animation.get_track_count()):
		if animation.track_get_key_count(track_index) < 2:
			continue
		var first: Variant = animation.track_get_key_value(track_index, 0)
		for key_index in range(1, animation.track_get_key_count(track_index)):
			var value: Variant = animation.track_get_key_value(track_index, key_index)
			if first is Vector3 and value is Vector3:
				score += (value as Vector3).distance_to(first as Vector3)
			elif first is Quaternion and value is Quaternion:
				score += (value as Quaternion).angle_to(first as Quaternion)
	return score


func _fail(message: String) -> void:
	push_error("[BridgeOfficerAnimationLibraryBuilder] %s" % message)
	quit(1)
