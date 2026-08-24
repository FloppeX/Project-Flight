extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "CameraFreedTargetSmoketest"
	root.add_child(scene)
	current_scene = scene

	var survivor := RigidBody3D.new()
	survivor.name = "SurvivingPlayerAircraft"
	scene.add_child(survivor)
	var fallback_camera := Camera3D.new()
	fallback_camera.name = "FallbackCockpitCamera"
	scene.add_child(fallback_camera)

	var controller := Node.new()
	controller.name = "CameraController"
	controller.set_script(load("res://Camera/CameraController.gd") as Script)
	controller.set("aircraft", survivor)
	controller.set("cockpit_camera", fallback_camera)

	var crashed_helicopter := RigidBody3D.new()
	crashed_helicopter.name = "CrashedHelicopter"
	scene.add_child(crashed_helicopter)
	var stale_reference: Variant = crashed_helicopter
	controller.set("_view_targets", [{
		"aircraft": crashed_helicopter,
		"mode": 0,
	}])
	controller.set("_current_view_index", 0)
	crashed_helicopter.free()
	if is_instance_valid(stale_reference):
		_fail("test helicopter did not become a freed reference")
		return
	if bool(controller.call("_is_ai_or_enemy_aircraft", stale_reference)):
		_fail("freed aircraft was classified as a live AI camera owner")
		return

	if controller.call("_get_camera_for", stale_reference, 0) != null:
		_fail("freed helicopter unexpectedly resolved to a camera")
		return
	if controller.call("get_current_camera") != fallback_camera:
		_fail("camera lookup did not fall back safely after pruning the crashed helicopter")
		return
	var pruned_targets: Array = controller.get("_view_targets") as Array
	if not pruned_targets.is_empty() or int(controller.get("_current_view_index")) != -1:
		_fail("freed helicopter remained in the cached camera targets")
		return

	controller.call("_switch_to_view_target", {
		"aircraft": stale_reference,
		"mode": 0,
	})
	var recovered_targets: Array = controller.get("_view_targets") as Array
	if recovered_targets.size() != 3:
		_fail("invalid-target recovery did not rebuild the surviving aircraft views")
		return
	for target_variant in recovered_targets:
		var target := target_variant as Dictionary
		if target.get("aircraft", null) != survivor:
			_fail("invalid-target recovery retained the crashed helicopter")
			return

	# A detached death-camera controller can survive the aircraft it references.
	# The all-controller pilot-landing broadcast must ignore it without hitting a
	# typed-argument error or stealing the newly landed pilot's camera.
	var orphaned_controller := Node.new()
	orphaned_controller.name = "OrphanedCameraController"
	orphaned_controller.set_script(load("res://Camera/CameraController.gd") as Script)
	var destroyed_source := RigidBody3D.new()
	scene.add_child(destroyed_source)
	orphaned_controller.set("aircraft", destroyed_source)
	destroyed_source.free()
	var landed_pilot := RigidBody3D.new()
	scene.add_child(landed_pilot)
	orphaned_controller.call("focus_ejected_pilot", landed_pilot, landed_pilot)
	if bool(orphaned_controller.get("_pilot_ejected")):
		_fail("orphaned camera controller accepted the landed-pilot handoff")
		return
	orphaned_controller.free()
	landed_pilot.free()

	print("[CameraFreedTargetSmoketest] PASS stale_target_pruned=true fallback_preserved=true orphan_handoff_ignored=true")
	controller.free()
	scene.free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("[CameraFreedTargetSmoketest] FAIL %s" % reason)
	quit(1)
