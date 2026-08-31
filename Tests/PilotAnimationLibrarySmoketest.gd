extends SceneTree
## Verifies that the baked shared animation library drives the canonical pilot.
## Run with:
##   Godot --headless --path <project> --audio-driver Dummy --script res://Tests/PilotAnimationLibrarySmoketest.gd

const PILOT_SCENE := "res://Models/Characters/pilot/PilotCharacter.tscn"
const APPROVED_RUN_ANIMATION := "res://Models/Characters/pilot/animations/approved_run_animation.tres"
const EXPECTED_CLIPS := {
	&"idle_breathing": true,
	&"idle_neutral": true,
	&"walk": true,
	&"run": true,
	&"turn_left": false,
	&"turn_right": false,
	&"sit_1": true,
	&"sit_2": true,
	&"piloting": true,
	&"salute": false,
	&"wave": false,
	&"die": false,
	&"parachute": true,
}
const ARM_CHAINS := [
	[&"c_shoulder.l", &"arm.l", &"forearm.l", &"hand.l"],
	[&"c_shoulder.r", &"arm.r", &"forearm.r", &"hand.r"],
]
const ARM_DEFORM_MIDPOINTS := [
	[&"arm_stretch.l", &"c_arm_twist_offset.l", &"forearm_stretch.l"],
	[&"forearm_twist.l", &"forearm_stretch.l", &"hand.l"],
	[&"arm_stretch.r", &"c_arm_twist_offset.r", &"forearm_stretch.r"],
	[&"forearm_twist.r", &"forearm_stretch.r", &"hand.r"],
]
const LEG_CHAINS := [
	[&"leg_stretch.l", &"foot.l", &"toes_01.l"],
	[&"leg_stretch.r", &"foot.r", &"toes_01.r"],
]
const LEG_DEFORM_MIDPOINTS := [
	[&"leg_twist.l", &"leg_stretch.l", &"foot.l"],
	[&"leg_twist.r", &"leg_stretch.r", &"foot.r"],
]
const MAX_ARM_SEGMENT_ERROR_M := 0.002
const MAX_LEG_SEGMENT_ERROR_M := 0.005
const APPROVED_RUN_KEY_TOLERANCE := 0.000001
## ARP's sleeve deformation helpers do not sit on the hierarchical control
## chain. The non-run repaired clips establish their rendered-safe envelope; the
## separately preserved run is checked byte-for-byte at the animation-key level.
const MAX_ARM_DEFORM_OFFSET_M := 0.12


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(PILOT_SCENE) as PackedScene
	if packed == null:
		_fail("canonical pilot scene did not load")
		return
	var pilot := packed.instantiate() as Node3D
	root.add_child(pilot)
	await process_frame
	# The test controls the baked player explicitly and does not need PilotPose's
	# procedural fallback to rewrite bones between seeks.
	pilot.set_process(false)

	var player := pilot.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer
	var skeleton := _find_skeleton(pilot.get_node_or_null("Pilot"))
	if player == null or skeleton == null:
		_fail("baked player or canonical skeleton is missing")
		return
	var actual_clips := player.get_animation_list()
	if actual_clips.size() != EXPECTED_CLIPS.size():
		_fail("expected %d clips, found %d: %s" % [
			EXPECTED_CLIPS.size(), actual_clips.size(), actual_clips,
		])
		return

	var summaries: PackedStringArray = []
	for clip_name: StringName in EXPECTED_CLIPS:
		if not player.has_animation(clip_name):
			_fail("missing clip: %s" % clip_name)
			return
		var animation := player.get_animation(clip_name)
		if animation == null or animation.length < 0.4:
			_fail("clip %s has invalid length" % clip_name)
			return
		var should_loop := bool(EXPECTED_CLIPS[clip_name])
		var does_loop := animation.loop_mode != Animation.LOOP_NONE
		if does_loop != should_loop:
			_fail("clip %s loop=%s, expected %s" % [clip_name, does_loop, should_loop])
			return
		if animation.get_track_count() < 50:
			_fail("clip %s has too few native tracks: %d" % [
				clip_name, animation.get_track_count(),
			])
			return
		if not _tracks_are_finite(animation):
			_fail("clip %s contains a non-finite key" % clip_name)
			return

		if not bool(pilot.call("play_baked_animation", clip_name)):
			_fail("safe baked playback did not start clip %s" % clip_name)
			return
		var start_pose := _sample_pose(player, skeleton, clip_name, 0.0)
		var pose_delta := 0.0
		var max_arm_length_error := _largest_segment_length_error(
			skeleton, ARM_CHAINS, []
		)
		var max_arm_deform_offset := _largest_segment_length_error(
			skeleton, [], ARM_DEFORM_MIDPOINTS
		)
		var max_leg_length_error := _largest_segment_length_error(
			skeleton, LEG_CHAINS, LEG_DEFORM_MIDPOINTS
		)
		for sample_fraction in [0.18, 0.37, 0.61, 0.83]:
			var sample_pose := _sample_pose(
				player, skeleton, clip_name, animation.length * sample_fraction
			)
			pose_delta = maxf(pose_delta, _largest_pose_delta(start_pose, sample_pose))
			max_arm_length_error = maxf(
				max_arm_length_error,
				_largest_segment_length_error(skeleton, ARM_CHAINS, [])
			)
			max_arm_deform_offset = maxf(
				max_arm_deform_offset,
				_largest_segment_length_error(skeleton, [], ARM_DEFORM_MIDPOINTS)
			)
			max_leg_length_error = maxf(
				max_leg_length_error,
				_largest_segment_length_error(skeleton, LEG_CHAINS, LEG_DEFORM_MIDPOINTS)
			)
		if pose_delta < 0.001:
			_fail("clip %s did not move the visible pilot skeleton (raw_track_delta=%.3f)" % [
				clip_name, _largest_track_key_delta(animation),
			])
			return
		# Parachute deliberately preserves the separately hand-authored pose route.
		# The fixed-length invariant applies to the newly imported general library.
		if clip_name not in [&"parachute", &"run"] \
				and max_arm_length_error > MAX_ARM_SEGMENT_ERROR_M:
			_fail("clip %s stretches an arm segment by %.4fm (limit %.4fm)" % [
				clip_name, max_arm_length_error, MAX_ARM_SEGMENT_ERROR_M,
			])
			return
		if clip_name not in [&"parachute", &"run"] \
				and max_arm_deform_offset > MAX_ARM_DEFORM_OFFSET_M:
			_fail("clip %s displaces an arm deform helper by %.4fm (limit %.4fm)" % [
				clip_name, max_arm_deform_offset, MAX_ARM_DEFORM_OFFSET_M,
			])
			return
		if clip_name != &"run" and max_leg_length_error > MAX_LEG_SEGMENT_ERROR_M:
			_fail("clip %s stretches a leg segment by %.4fm (limit %.4fm)" % [
				clip_name, max_leg_length_error, MAX_LEG_SEGMENT_ERROR_M,
			])
			return
		if clip_name == &"run":
			var reference_error := _approved_run_reference_error(animation)
			if reference_error != "":
				_fail(reference_error)
				return
		var root_travel := _root_translation_range(animation)
		summaries.append("%s=%.2fs loop=%s pose_delta=%.3f arm_error=%.4fm arm_deform=%.4fm leg_error=%.4fm root_span=(%.2f,%.2f,%.2f)m" % [
			clip_name, animation.length, does_loop, pose_delta,
			max_arm_length_error, max_arm_deform_offset, max_leg_length_error,
			root_travel.x, root_travel.y, root_travel.z,
		])

	print("[PilotAnimationLibrarySmoketest] PASS clips=%d\n  %s" % [
		actual_clips.size(), "\n  ".join(summaries),
	])
	pilot.free()
	quit(0)


func _approved_run_reference_error(animation: Animation) -> String:
	var source_reference := load(APPROVED_RUN_ANIMATION) as Animation
	if source_reference == null:
		return "approved run reference could not be loaded"
	var reference := source_reference.duplicate(true) as Animation
	_lock_horizontal_root_motion(reference)
	if animation.get_track_count() != reference.get_track_count():
		return "approved run track count changed from %d to %d" % [
			reference.get_track_count(), animation.get_track_count(),
		]
	if absf(animation.length - reference.length) > APPROVED_RUN_KEY_TOLERANCE:
		return "approved run length changed from %.6f to %.6f" % [reference.length, animation.length]
	for track_index in range(reference.get_track_count()):
		if animation.track_get_type(track_index) != reference.track_get_type(track_index) \
				or animation.track_get_path(track_index) != reference.track_get_path(track_index):
			return "approved run track %d identity changed" % track_index
		var expected_keys := reference.track_get_key_count(track_index)
		if animation.track_get_key_count(track_index) != expected_keys:
			return "approved run track %d key count changed" % track_index
		for key_index in range(expected_keys):
			if absf(
				animation.track_get_key_time(track_index, key_index)
				- reference.track_get_key_time(track_index, key_index)
			) > APPROVED_RUN_KEY_TOLERANCE:
				return "approved run track %d key %d time changed" % [track_index, key_index]
			var actual: Variant = animation.track_get_key_value(track_index, key_index)
			var expected: Variant = reference.track_get_key_value(track_index, key_index)
			var value_error := _animation_value_error(actual, expected)
			if value_error > APPROVED_RUN_KEY_TOLERANCE:
				return "approved run track %d key %d value changed by %.9f" % [
					track_index, key_index, value_error,
				]
	return ""


func _animation_value_error(actual: Variant, expected: Variant) -> float:
	if actual is Vector3 and expected is Vector3:
		return (actual as Vector3).distance_to(expected as Vector3)
	if actual is Quaternion and expected is Quaternion:
		var actual_quaternion := actual as Quaternion
		var expected_quaternion := expected as Quaternion
		var direct := Vector4(
			actual_quaternion.x - expected_quaternion.x,
			actual_quaternion.y - expected_quaternion.y,
			actual_quaternion.z - expected_quaternion.z,
			actual_quaternion.w - expected_quaternion.w
		).length()
		var flipped := Vector4(
			actual_quaternion.x + expected_quaternion.x,
			actual_quaternion.y + expected_quaternion.y,
			actual_quaternion.z + expected_quaternion.z,
			actual_quaternion.w + expected_quaternion.w
		).length()
		return minf(direct, flipped)
	if actual is float and expected is float:
		return absf(float(actual) - float(expected))
	return 0.0 if actual == expected else INF


func _lock_horizontal_root_motion(animation: Animation) -> void:
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		if not String(animation.track_get_path(track_index)).ends_with(":root.x"):
			continue
		if animation.track_get_key_count(track_index) <= 0:
			continue
		var anchor := animation.track_get_key_value(track_index, 0) as Vector3
		for key_index in range(animation.track_get_key_count(track_index)):
			var value := animation.track_get_key_value(track_index, key_index) as Vector3
			value.x = anchor.x
			value.z = anchor.z
			animation.track_set_key_value(track_index, key_index, value)


func _sample_pose(
		player: AnimationPlayer,
		skeleton: Skeleton3D,
		clip_name: StringName,
		time_s: float
) -> Array:
	player.active = true
	if player.current_animation != String(clip_name):
		player.play(clip_name)
		player.advance(0.0)
	player.seek(time_s, true)
	player.advance(0.0)
	var pose: Array = []
	for bone_index in range(skeleton.get_bone_count()):
		pose.append({
			"position": skeleton.get_bone_pose_position(bone_index),
			"rotation": skeleton.get_bone_pose_rotation(bone_index),
		})
	return pose


func _largest_pose_delta(first: Array, second: Array) -> float:
	var largest := 0.0
	for index in range(mini(first.size(), second.size())):
		var first_bone: Dictionary = first[index]
		var second_bone: Dictionary = second[index]
		var position_delta: float = (
			(second_bone["position"] as Vector3) - (first_bone["position"] as Vector3)
		).length()
		var rotation_delta: float = (first_bone["rotation"] as Quaternion).angle_to(
			second_bone["rotation"] as Quaternion
		)
		largest = maxf(largest, maxf(position_delta, rotation_delta))
	return largest


func _largest_segment_length_error(
		skeleton: Skeleton3D,
		chains: Array,
		midpoint_definitions: Array
) -> float:
	var largest := 0.0
	for chain in chains:
		for index in range(chain.size() - 1):
			var first_index := skeleton.find_bone(chain[index])
			var second_index := skeleton.find_bone(chain[index + 1])
			if first_index < 0 or second_index < 0:
				return INF
			var rest_length := skeleton.get_bone_global_rest(first_index).origin.distance_to(
				skeleton.get_bone_global_rest(second_index).origin
			)
			var pose_length := skeleton.get_bone_global_pose(first_index).origin.distance_to(
				skeleton.get_bone_global_pose(second_index).origin
			)
			largest = maxf(largest, absf(pose_length - rest_length))
	for midpoint_definition in midpoint_definitions:
		var midpoint_index := skeleton.find_bone(midpoint_definition[0])
		var start_index := skeleton.find_bone(midpoint_definition[1])
		var end_index := skeleton.find_bone(midpoint_definition[2])
		if midpoint_index < 0 or start_index < 0 or end_index < 0:
			return INF
		var expected_midpoint := skeleton.get_bone_global_pose(start_index).origin.lerp(
			skeleton.get_bone_global_pose(end_index).origin, 0.5
		)
		largest = maxf(
			largest,
			skeleton.get_bone_global_pose(midpoint_index).origin.distance_to(expected_midpoint)
		)
	return largest


func _root_translation_range(animation: Animation) -> Vector3:
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		var track_path := animation.track_get_path(track_index)
		if track_path.get_subname_count() == 0 or track_path.get_subname(0) != &"root.x":
			continue
		var minimum := Vector3(INF, INF, INF)
		var maximum := Vector3(-INF, -INF, -INF)
		for key_index in range(animation.track_get_key_count(track_index)):
			var value := animation.track_get_key_value(track_index, key_index) as Vector3
			minimum = minimum.min(value)
			maximum = maximum.max(value)
		return maximum - minimum
	return Vector3.ZERO


func _largest_track_key_delta(animation: Animation) -> float:
	var largest := 0.0
	for track_index in range(animation.get_track_count()):
		if animation.track_get_key_count(track_index) < 2:
			continue
		var first: Variant = animation.track_get_key_value(track_index, 0)
		for key_index in range(1, animation.track_get_key_count(track_index)):
			var value: Variant = animation.track_get_key_value(track_index, key_index)
			if first is Vector3 and value is Vector3:
				largest = maxf(largest, (value as Vector3).distance_to(first as Vector3))
			elif first is Quaternion and value is Quaternion:
				largest = maxf(largest, (value as Quaternion).angle_to(first as Quaternion))
	return largest


func _tracks_are_finite(animation: Animation) -> bool:
	for track_index in range(animation.get_track_count()):
		for key_index in range(animation.track_get_key_count(track_index)):
			var value: Variant = animation.track_get_key_value(track_index, key_index)
			if value is Vector3:
				var vector := value as Vector3
				if not is_finite(vector.x) or not is_finite(vector.y) or not is_finite(vector.z):
					return false
			elif value is Quaternion:
				var quaternion := value as Quaternion
				if not is_finite(quaternion.x) or not is_finite(quaternion.y) \
						or not is_finite(quaternion.z) or not is_finite(quaternion.w):
					return false
	return true


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
	push_error("[PilotAnimationLibrarySmoketest] FAIL %s" % reason)
	quit(1)
