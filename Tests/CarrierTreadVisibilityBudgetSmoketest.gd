extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var tread_scene := load("res://LandCarrier/CarrierTread.tscn") as PackedScene
	if tread_scene == null:
		_fail("CarrierTread scene could not be loaded")
		return
	var tread := tread_scene.instantiate()
	root.add_child(tread)
	await process_frame

	var track_plates := tread.get_node_or_null("TrackPlates") as MultiMeshInstance3D
	if track_plates == null or track_plates.multimesh == null:
		_fail("generated track plate MultiMesh is missing")
		return
	tread.call("set_visual_budget_enabled", false)
	tread.call("_apply_debug_mode")
	if not track_plates.visible:
		_fail("animation/debug budget hid the track plate MultiMesh")
		return
	for wheel_name in [
		"carrier track wheel",
		"carrier track wheel2",
		"carrier track wheel3",
		"carrier track wheel4",
		"carrier track wheel5",
	]:
		var wheel := tread.get_node_or_null(wheel_name) as Node3D
		if wheel == null or not wheel.visible:
			_fail("animation budget hid %s" % wheel_name)
			return
	if tread.is_physics_processing():
		_fail("off-camera animation budget did not pause tread processing")
		return

	tread.call("set_visual_budget_enabled", true)
	if not tread.is_physics_processing() or not track_plates.visible:
		_fail("visible tread did not resume animation while remaining rendered")
		return

	tread.queue_free()
	print("[CarrierTreadVisibilityBudgetSmoketest] PASS always_visible=true off_camera_animation_paused=true")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[CarrierTreadVisibilityBudgetSmoketest] FAIL %s" % reason)
	quit(1)
