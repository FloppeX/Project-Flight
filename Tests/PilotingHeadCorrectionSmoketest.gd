extends SceneTree
## Verifies the baked piloting clip keeps subtle head movement without retaining
## the source animation's deep forward nod.

const PILOT_SCENE := preload("res://Models/Characters/pilot/PilotCharacter.tscn")
const SAMPLE_COUNT := 194
const MAX_DOWN_NOD_DEGREES := 12.1
const MIN_RETAINED_MOTION_DEGREES := 8.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pilot := PILOT_SCENE.instantiate()
	root.add_child(pilot)
	await process_frame
	pilot.set_process(false)
	var player := pilot.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer
	var skeleton := pilot.find_child("Skeleton3D", true, false) as Skeleton3D
	if player == null or skeleton == null:
		_fail("canonical pilot animation player or skeleton is missing")
		return
	var head_index := skeleton.find_bone("head.x")
	var animation := player.get_animation(&"piloting")
	if head_index < 0 or animation == null:
		_fail("piloting clip or head bone is missing")
		return

	player.play(&"piloting")
	player.seek(0.0, true)
	player.advance(0.0)
	var reference_basis := (
		skeleton.get_bone_global_pose(head_index).basis.orthonormalized()
	)
	var largest_down_nod := -INF
	for sample_index in range(SAMPLE_COUNT + 1):
		var time_s := animation.length * float(sample_index) / float(SAMPLE_COUNT)
		player.seek(time_s, true)
		player.advance(0.0)
		var current_basis := (
			skeleton.get_bone_global_pose(head_index).basis.orthonormalized()
		)
		var pitch_degrees := rad_to_deg(
			(current_basis * reference_basis.inverse()).get_euler().x
		)
		largest_down_nod = maxf(largest_down_nod, pitch_degrees)

	if largest_down_nod > MAX_DOWN_NOD_DEGREES:
		_fail("piloting head still nods down %.2f degrees" % largest_down_nod)
		return
	if largest_down_nod < MIN_RETAINED_MOTION_DEGREES:
		_fail("piloting head correction removed nearly all head motion")
		return
	print(
		(
			"[PilotingHeadCorrectionSmoketest] PASS max_down_nod=%.2fdeg "
			+ "subtle_motion_retained=true"
		) % largest_down_nod
	)
	pilot.free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("[PilotingHeadCorrectionSmoketest] FAIL %s" % reason)
	quit(1)
