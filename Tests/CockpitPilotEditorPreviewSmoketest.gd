extends SceneTree
## Verifies the editor shows the imported seated mesh pose, allowing
## per-aircraft placement against the real character.

const COCKPIT_PILOT_SCENE := preload("res://Aircraft/CockpitPilot.tscn")


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

	var pooled_visual := pilot.call("get_pilot_visual") as Node3D
	var player := pooled_visual.get_node_or_null("Pilot/AnimationPlayer") as AnimationPlayer \
			if pooled_visual != null else null
	if player == null:
		_fail("cockpit mount has no editor-preview pilot")
		return
	if player.assigned_animation != "rigAction":
		_fail(
			"editor preview did not retain the imported seated pose "
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
	var skeleton := pooled_visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		_fail("cockpit pilot has no visible skeleton")
		return
	var sampled_rotation_radians := 0.0
	for bone_index in range(skeleton.get_bone_count()):
		sampled_rotation_radians += skeleton.get_bone_pose_rotation(bone_index).get_angle()
	if sampled_rotation_radians < 1.0:
		_fail("editor preview left the skeleton near its rest pose")
		return

	print("[CockpitPilotEditorPreviewSmoketest] PASS clip=rigAction frozen=true")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[CockpitPilotEditorPreviewSmoketest] FAIL %s" % reason)
	quit(1)
