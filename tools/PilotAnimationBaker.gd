extends SceneTree
## Retargets the Mixamo source FBXs onto the canonical Auto-Rig Pro pilot and
## saves the sampled native tracks as one shared AnimationLibrary resource.
## Run with:
##   Godot --headless --path <project> --script res://tools/PilotAnimationBaker.gd

const PILOT_SCENE := "res://Models/Characters/pilot/PilotCharacter.tscn"
const OUTPUT_LIBRARY := "res://Models/Characters/pilot/animations/pilot_animation_library.tres"
const SAMPLE_FPS := 30.0
## The source piloting clip bows the helmet forward by about 38 degrees, which
## reads as the pilot nodding off. Keep subtle attentive movement, compress the
## deeper part of the nod, and retain a firm safety cap.
const PILOTING_HEAD_NOD_SOFT_LIMIT_DEGREES := 8.0
const PILOTING_HEAD_NOD_EXCESS_SCALE := 0.15
const PILOTING_HEAD_NOD_HARD_LIMIT_DEGREES := 12.0
const CLIPS := [
	{"file": "Breathing Idle.fbx", "name": &"idle_breathing", "loop": true},
	{"file": "Neutral Idle.fbx", "name": &"idle_neutral", "loop": true},
	{"file": "Walking.fbx", "name": &"walk", "loop": true},
	{"file": "running.fbx", "name": &"run", "loop": true},
	{"file": "Left Turn.fbx", "name": &"turn_left", "loop": false},
	{"file": "Right Turn.fbx", "name": &"turn_right", "loop": false},
	{"file": "Sitting.fbx", "name": &"sit_1", "loop": true},
	{"file": "Sitting Idle.fbx", "name": &"sit_2", "loop": true},
	{"file": "Piloting.fbx", "name": &"piloting", "loop": true},
	{"file": "Salute.fbx", "name": &"salute", "loop": false},
	{"file": "Waving.fbx", "name": &"wave", "loop": false},
	{"file": "Dying.fbx", "name": &"die", "loop": false},
	{"file": "parachuting.fbx", "name": &"parachute", "loop": true},
]


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var packed_pilot := load(PILOT_SCENE) as PackedScene
	if packed_pilot == null:
		_fail("canonical pilot scene did not load")
		return
	var pilot := packed_pilot.instantiate() as Node3D
	root.add_child(pilot)
	await process_frame
	var target_root := pilot.get_node_or_null("Pilot") as Node3D
	var target_skeleton := _find_skeleton(target_root)
	if target_skeleton == null:
		_fail("canonical Auto-Rig Pro skeleton was not found")
		return
	# AnimationPlayer's default root_node is its parent (PilotCharacter), so the
	# track path starts at the visible Pilot branch rather than at the player.
	var skeleton_from_player := pilot.get_path_to(target_skeleton)
	var library := AnimationLibrary.new()

	for clip in CLIPS:
		var source_path := "res://Models/Characters/pilot/animations/%s" % String(clip["file"])
		var source_scene := load(source_path) as PackedScene
		if source_scene == null:
			_fail("source clip did not load: %s" % source_path)
			return
		if not bool(pilot.call("_setup_retargeted_animation", source_scene)):
			_fail("retarget setup failed: %s" % source_path)
			return
		var source_player := pilot.get("_retarget_source_player") as AnimationPlayer
		var source_skeleton := pilot.get("_retarget_source_skeleton") as Skeleton3D
		var source_animation_name := _find_motion_animation(source_player)
		if source_animation_name == &"":
			_fail("no usable animation found: %s" % source_path)
			return
		var source_animation := source_player.get_animation(source_animation_name)
		# The ARP export contains a dense control/deform finger rig that does not
		# correspond one-to-one with Mixamo's finger chains. Baking those partial
		# matches tears the glove mesh, so shared clips keep the pilot's neutral
		# finger pose while transferring the hand and all larger joints.
		var bone_pairs := _without_finger_pairs(
			pilot.get("_retarget_bone_pairs") as Array, target_skeleton
		)
		if source_animation == null or source_animation.length <= 0.0 or bone_pairs.size() < 25:
			_fail("incomplete retarget data for %s (pairs=%d)" % [source_path, bone_pairs.size()])
			return

		source_player.active = true
		source_player.play(source_animation_name)
		source_player.advance(0.0)
		pilot.set("_retarget_parachute_pose_active", StringName(clip["name"]) == &"parachute")
		var baked := _bake_clip(
			pilot,
			target_skeleton,
			skeleton_from_player,
			source_player,
			source_animation.length,
			bone_pairs,
			bool(clip["loop"]),
			StringName(clip["name"])
		)
		if baked == null:
			_fail("bake failed: %s" % source_path)
			return
		var add_error := library.add_animation(StringName(clip["name"]), baked)
		if add_error != OK:
			_fail("could not add baked clip %s (error %d)" % [clip["name"], add_error])
			return
		var hips_index := _find_mixamo_bone(source_skeleton, &"mixamorig_Hips")
		var hips_height := source_skeleton.get_bone_global_rest(hips_index).origin.y \
				if hips_index >= 0 else -1.0
		print("[PilotAnimationBaker] %s <- %s anim=%s length=%.2fs pairs=%d hips=%.3fm loop=%s" % [
			clip["name"], clip["file"], source_animation_name, source_animation.length,
			bone_pairs.size(), hips_height, bool(clip["loop"]),
		])

	var save_error := ResourceSaver.save(library, OUTPUT_LIBRARY)
	if save_error != OK:
		_fail("could not save animation library (error %d)" % save_error)
		return
	print("[PilotAnimationBaker] PASS clips=%d output=%s" % [
		library.get_animation_list().size(), ProjectSettings.globalize_path(OUTPUT_LIBRARY),
	])
	pilot.free()
	quit(0)


func _bake_clip(
		pilot: Node3D,
		target_skeleton: Skeleton3D,
		skeleton_from_player: NodePath,
		source_player: AnimationPlayer,
		length_s: float,
		bone_pairs: Array,
		looping: bool,
		clip_name: StringName
) -> Animation:
	var baked := Animation.new()
	baked.length = length_s
	baked.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	baked.step = 1.0 / SAMPLE_FPS
	var target_indexes: Array[int] = []
	for pair in bone_pairs:
		var target_index := int(pair["target"])
		if not target_indexes.has(target_index):
			target_indexes.append(target_index)
	var tracks: Dictionary = {}
	for target_index in target_indexes:
		var bone_name := target_skeleton.get_bone_name(target_index)
		var track_path := NodePath("%s:%s" % [skeleton_from_player, bone_name])
		var position_track := baked.add_track(Animation.TYPE_POSITION_3D)
		baked.track_set_path(position_track, track_path)
		baked.track_set_interpolation_type(position_track, Animation.INTERPOLATION_LINEAR)
		var rotation_track := baked.add_track(Animation.TYPE_ROTATION_3D)
		baked.track_set_path(rotation_track, track_path)
		baked.track_set_interpolation_type(rotation_track, Animation.INTERPOLATION_LINEAR)
		tracks[target_index] = {
			"position": position_track,
			"rotation": rotation_track,
		}

	var head_index := target_skeleton.find_bone("head.x")
	var piloting_head_reference_basis := Basis.IDENTITY
	var frame_count := ceili(length_s * SAMPLE_FPS) + 1
	for frame in range(frame_count):
		var time_s := minf(float(frame) / SAMPLE_FPS, length_s)
		source_player.seek(time_s, true)
		pilot.call("_apply_retargeted_animation_frame")
		if clip_name == &"piloting" and head_index >= 0:
			if frame == 0:
				piloting_head_reference_basis = (
					target_skeleton.get_bone_global_pose(head_index).basis.orthonormalized()
				)
			_limit_piloting_head_nod(
				target_skeleton, head_index, piloting_head_reference_basis
			)
		for target_index in target_indexes:
			var track_data: Dictionary = tracks[target_index]
			baked.track_insert_key(
				int(track_data["position"]),
				time_s,
				target_skeleton.get_bone_pose_position(target_index)
			)
			baked.track_insert_key(
				int(track_data["rotation"]),
				time_s,
				target_skeleton.get_bone_pose_rotation(target_index)
			)
	return baked


func _limit_piloting_head_nod(
		skeleton: Skeleton3D,
		head_index: int,
		reference_basis: Basis
) -> void:
	var current_global_basis := (
		skeleton.get_bone_global_pose(head_index).basis.orthonormalized()
	)
	var motion_euler := (current_global_basis * reference_basis.inverse()).get_euler()
	var raw_pitch_degrees := rad_to_deg(motion_euler.x)
	if raw_pitch_degrees <= PILOTING_HEAD_NOD_SOFT_LIMIT_DEGREES:
		return
	var corrected_pitch_degrees := minf(
		PILOTING_HEAD_NOD_HARD_LIMIT_DEGREES,
		PILOTING_HEAD_NOD_SOFT_LIMIT_DEGREES
			+ (raw_pitch_degrees - PILOTING_HEAD_NOD_SOFT_LIMIT_DEGREES)
			* PILOTING_HEAD_NOD_EXCESS_SCALE
	)
	motion_euler.x = deg_to_rad(corrected_pitch_degrees)
	var corrected_motion_basis := Basis(Quaternion.from_euler(motion_euler))
	var desired_global_basis := (
		corrected_motion_basis * reference_basis
	).orthonormalized()
	var parent_index := skeleton.get_bone_parent(head_index)
	var desired_local_basis := desired_global_basis
	if parent_index >= 0:
		desired_local_basis = (
			skeleton.get_bone_global_pose(parent_index).basis.inverse()
			* desired_global_basis
		).orthonormalized()
	skeleton.set_bone_pose_rotation(
		head_index, desired_local_basis.get_rotation_quaternion()
	)


func _find_motion_animation(player: AnimationPlayer) -> StringName:
	if player == null:
		return &""
	var best_name: StringName = &""
	var best_motion := -1.0
	var best_length := 0.0
	for animation_name in player.get_animation_list():
		if String(animation_name).to_upper().contains("RESET"):
			continue
		var animation := player.get_animation(animation_name)
		if animation == null:
			continue
		var motion := _animation_motion_score(animation)
		if motion > best_motion + 0.000001 \
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
				score = maxf(score, (value as Vector3).distance_to(first as Vector3))
			elif first is Quaternion and value is Quaternion:
				score = maxf(score, (value as Quaternion).angle_to(first as Quaternion))
	return score


func _without_finger_pairs(pairs: Array, target_skeleton: Skeleton3D) -> Array:
	var filtered: Array = []
	for pair in pairs:
		var target_name := String(target_skeleton.get_bone_name(int(pair["target"]))).to_lower()
		if target_name.contains("thumb") or target_name.contains("index") \
				or target_name.contains("middle") or target_name.contains("ring") \
				or target_name.contains("pinky"):
			continue
		filtered.append(pair)
	return filtered


func _find_mixamo_bone(skeleton: Skeleton3D, canonical_name: StringName) -> int:
	var bone_index := skeleton.find_bone(canonical_name)
	if bone_index >= 0:
		return bone_index
	return skeleton.find_bone(String(canonical_name).replace("mixamorig_", "mixamorig:"))


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


func _fail(reason: String) -> void:
	push_error("[PilotAnimationBaker] FAIL %s" % reason)
	quit(1)
