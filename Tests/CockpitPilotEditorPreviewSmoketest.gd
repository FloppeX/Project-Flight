extends SceneTree
## Verifies the shared cockpit pilot freezes the runtime piloting clip into a
## seated editor pose, allowing per-aircraft placement against the real mesh.

const COCKPIT_PILOT_SCENE := preload("res://Aircraft/CockpitPilot.tscn")
const EXPECTED_PREVIEW_TIME_S := 1.5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("test must run with --editor")
		return

	var host := Node3D.new()
	root.add_child(host)
	var pilot := COCKPIT_PILOT_SCENE.instantiate()
	host.add_child(pilot)
	await process_frame

	var player := pilot.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer
	if player == null:
		_fail("cockpit pilot has no baked AnimationPlayer")
		return
	if player.assigned_animation != "piloting":
		_fail(
			"editor preview did not sample the piloting clip "
			+ "(configured=%s assigned=%s position=%.3f)"
			% [
				pilot.get("initial_baked_animation"),
				player.assigned_animation,
				player.current_animation_position,
			]
		)
		return
	if player.is_playing():
		_fail("editor preview was left playing instead of frozen")
		return
	if absf(player.current_animation_position - EXPECTED_PREVIEW_TIME_S) > 0.02:
		_fail(
			"editor preview sampled %.3fs instead of %.3fs"
			% [player.current_animation_position, EXPECTED_PREVIEW_TIME_S]
		)
		return
	var skeleton := pilot.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		_fail("cockpit pilot has no visible skeleton")
		return
	var sampled_rotation_radians := 0.0
	for bone_index in range(skeleton.get_bone_count()):
		sampled_rotation_radians += skeleton.get_bone_pose_rotation(bone_index).get_angle()
	if sampled_rotation_radians < 1.0:
		_fail("editor preview left the skeleton near its rest pose")
		return

	print(
		"[CockpitPilotEditorPreviewSmoketest] PASS clip=piloting "
		+ "time=%.2fs frozen=true" % player.current_animation_position
	)
	quit(0)


func _fail(reason: String) -> void:
	push_error("[CockpitPilotEditorPreviewSmoketest] FAIL %s" % reason)
	quit(1)
