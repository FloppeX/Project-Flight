extends SceneTree
## Guards the shared leg and foot geometry used by every seated animation while
## leaving locomotion, standing, and parachute clips untouched.

const PILOT_SCENE := preload("res://Models/Characters/pilot/CockpitPilotCharacter.tscn")
const SEATED_ANIMATIONS: Array[StringName] = [&"sit_1", &"sit_2", &"piloting"]
const EXPECTED_KNEE_BEND_DEGREES := 45.0
const EXPECTED_TOE_UP_DEGREES := 15.0
const EXPECTED_NECK_RECLINE_DEGREES := 10.0
const ANGLE_TOLERANCE_DEGREES := 0.25


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pilot := PILOT_SCENE.instantiate() as Node3D
	root.add_child(pilot)
	await process_frame
	var skeleton := _find_skeleton(pilot)
	if skeleton == null:
		_fail("canonical pilot skeleton is missing")
		return

	if not bool(pilot.call("apply_static_seated_pose")):
		_fail("could not sample the canonical static resting pose")
		return
	if not _assert_seated_geometry(skeleton, "static resting API"):
		return
	var player := pilot.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer
	if player == null or player.is_playing() or player.assigned_animation != &"piloting":
		_fail("static resting API did not retain the approved piloting sample")
		return
	var static_corrected_neck := _neck_transform(skeleton)
	var static_corrected_head := _head_position(skeleton)
	player.active = true
	player.play(&"piloting")
	player.seek(1.5, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var static_authored_neck := _neck_transform(skeleton)
	var static_authored_head := _head_position(skeleton)
	if not _assert_neck_recline(
		static_authored_neck,
		static_corrected_neck,
		static_authored_head,
		static_corrected_head,
		"static resting API"
	):
		return

	for animation_name in SEATED_ANIMATIONS:
		if not bool(pilot.call("play_baked_animation", animation_name, 1.0)):
			_fail("seated clip is missing: %s" % animation_name)
			return
		player.speed_scale = 0.0
		var seated_animation := player.get_animation(animation_name)
		for sample_fraction in [0.13, 0.42, 0.78]:
			player.seek(seated_animation.length * sample_fraction, true)
			player.advance(0.0)
			skeleton.force_update_all_bone_transforms()
			var authored_neck := _neck_transform(skeleton)
			var authored_head := _head_position(skeleton)
			pilot.call("_apply_seated_pose_corrections", animation_name)
			skeleton.force_update_all_bone_transforms()
			if not _assert_seated_geometry(
				skeleton,
				"animated %s at %.0f%%" % [animation_name, sample_fraction * 100.0]
			):
				return
			if not _assert_neck_recline(
				authored_neck,
				_neck_transform(skeleton),
				authored_head,
				_head_position(skeleton),
				"animated %s at %.0f%%" % [animation_name, sample_fraction * 100.0]
			):
				return

	for animation_name in [&"run", &"parachute", &"idle_neutral"]:
		if not bool(pilot.call("play_baked_animation", animation_name, 1.0)):
			_fail("non-seated clip is missing: %s" % animation_name)
			return
		player.speed_scale = 0.0
		var animation := player.get_animation(animation_name)
		player.seek(animation.length * 0.43, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		var before := _corrected_bone_transforms(skeleton)
		pilot.call("_apply_seated_pose_corrections", animation_name)
		skeleton.force_update_all_bone_transforms()
		if not _transforms_match(before, _corrected_bone_transforms(skeleton)):
			_fail("seated correction changed the %s clip" % animation_name)
			return

	print(
		"[PilotSeatedLegBendSmoketest] PASS "
		+ "seated_clips=3 samples=9 knee_bend=45deg toe_up=15deg neck_back=10deg "
		+ "feet_ahead=true "
		+ "run_untouched=true parachute_untouched=true idle_untouched=true"
	)
	pilot.free()
	quit(0)


func _assert_seated_geometry(skeleton: Skeleton3D, context: String) -> bool:
	skeleton.force_update_all_bone_transforms()
	for suffix in [".l", ".r"]:
		var geometry := _leg_geometry(skeleton, suffix)
		var angle := float(geometry.get("knee_bend_degrees", INF))
		if absf(angle - EXPECTED_KNEE_BEND_DEGREES) > ANGLE_TOLERANCE_DEGREES:
			_fail("%s %s knee bend is %.2f degrees" % [context, suffix, angle])
			return false
		if float(geometry.get("foot_forward_m", -INF)) <= 0.0:
			_fail("%s %s foot is not ahead of its knee" % [context, suffix])
			return false
		if float(geometry.get("foot_below_m", -INF)) <= 0.0:
			_fail("%s %s foot is not below its knee" % [context, suffix])
			return false
		var toe_up := float(geometry.get("toe_up_degrees", INF))
		if absf(toe_up - EXPECTED_TOE_UP_DEGREES) > ANGLE_TOLERANCE_DEGREES:
			_fail("%s %s toe lift is %.2f degrees" % [context, suffix, toe_up])
			return false
	return true


func _leg_geometry(skeleton: Skeleton3D, suffix: String) -> Dictionary:
	var thigh_index := skeleton.find_bone("thigh_stretch" + suffix)
	var shin_index := skeleton.find_bone("leg_stretch" + suffix)
	var foot_index := skeleton.find_bone("foot" + suffix)
	var toe_index := skeleton.find_bone("toes_01" + suffix)
	if thigh_index < 0 or shin_index < 0 or foot_index < 0 or toe_index < 0:
		return {}
	var hip := skeleton.get_bone_global_pose(thigh_index).origin
	var knee := skeleton.get_bone_global_pose(shin_index).origin
	var ankle := skeleton.get_bone_global_pose(foot_index).origin
	var toe := skeleton.get_bone_global_pose(toe_index).origin
	var upper := Vector2(knee.y - hip.y, knee.z - hip.z).normalized()
	var lower := Vector2(ankle.y - knee.y, ankle.z - knee.z).normalized()
	var foot_vector := toe - ankle
	var rest_foot := skeleton.get_bone_global_rest(foot_index)
	var rest_toe := skeleton.get_bone_global_rest(toe_index)
	var rest_foot_vector := rest_toe.origin - rest_foot.origin
	var foot_down_angle := atan2(-foot_vector.y, foot_vector.z)
	var neutral_foot_down_angle := atan2(-rest_foot_vector.y, rest_foot_vector.z)
	return {
		"knee_bend_degrees": rad_to_deg(acos(clampf(upper.dot(lower), -1.0, 1.0))),
		"foot_forward_m": ankle.z - knee.z,
		"foot_below_m": knee.y - ankle.y,
		"toe_up_degrees": rad_to_deg(neutral_foot_down_angle - foot_down_angle),
	}


func _neck_transform(skeleton: Skeleton3D) -> Transform3D:
	var neck_index := skeleton.find_bone("neck.x")
	return skeleton.get_bone_global_pose(neck_index) \
			if neck_index >= 0 else Transform3D.IDENTITY


func _head_position(skeleton: Skeleton3D) -> Vector3:
	var head_index := skeleton.find_bone("head.x")
	return skeleton.get_bone_global_pose(head_index).origin \
			if head_index >= 0 else Vector3.INF


func _assert_neck_recline(
		authored_neck: Transform3D,
		corrected_neck: Transform3D,
		authored_head: Vector3,
		corrected_head: Vector3,
		context: String
) -> bool:
	var actual_delta := (
		corrected_neck.basis.orthonormalized()
		* authored_neck.basis.orthonormalized().inverse()
	).get_rotation_quaternion()
	var expected_delta := Quaternion(
		Vector3.RIGHT,
		-deg_to_rad(EXPECTED_NECK_RECLINE_DEGREES)
	)
	var error_degrees := rad_to_deg(actual_delta.angle_to(expected_delta))
	if error_degrees > ANGLE_TOLERANCE_DEGREES:
		_fail("%s neck recline error is %.2f degrees" % [context, error_degrees])
		return false
	if corrected_head.z >= authored_head.z - 0.001:
		_fail(
			"%s head did not move rearward from the base neck joint (authored=%s corrected=%s)"
			% [context, authored_head, corrected_head]
		)
		return false
	return true


func _corrected_bone_transforms(skeleton: Skeleton3D) -> Dictionary:
	var result: Dictionary = {}
	for bone_name in [
		"neck.x", "head.x",
		"leg_stretch.l", "foot.l", "toes_01.l",
		"leg_stretch.r", "foot.r", "toes_01.r",
	]:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index >= 0:
			result[bone_name] = skeleton.get_bone_global_pose(bone_index)
	return result


func _transforms_match(before: Dictionary, after: Dictionary) -> bool:
	if before.size() != after.size():
		return false
	for bone_name in before:
		if not after.has(bone_name):
			return false
		if not (before[bone_name] as Transform3D).is_equal_approx(
			after[bone_name] as Transform3D
		):
			return false
	return true


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _fail(reason: String) -> void:
	push_error("[PilotSeatedLegBendSmoketest] FAIL %s" % reason)
	quit(1)
