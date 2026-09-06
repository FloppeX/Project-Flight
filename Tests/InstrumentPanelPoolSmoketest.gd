extends Node

const AIRCRAFT_1_SCENE: PackedScene = preload("res://Aircraft/Aircraft_1.tscn")
const AIRCRAFT_2_SCENE: PackedScene = preload("res://Aircraft/Aircraft_2.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Allow the autoload to exercise both SubViewport pairs for two frames each.
	for _frame in range(8):
		await get_tree().process_frame
	var pool := get_node_or_null("/root/InstrumentPanelPool")
	_expect(pool != null, "InstrumentPanelPool autoload is missing")
	if pool == null:
		_finish(null, null)
		return
	var pooled_target_camera_count := 0
	for camera_variant in pool.find_children("*", "Camera3D", true, false):
		var pooled_camera := camera_variant as Camera3D
		if pooled_camera != null and pooled_camera.get_parent() != null \
				and pooled_camera.get_parent().name == "TargetRig":
			pooled_target_camera_count += 1
	_expect(pooled_target_camera_count == 2, "target render cameras were not limited to the two-panel pool")

	var aircraft_1 := AIRCRAFT_1_SCENE.instantiate() as RigidBody3D
	var aircraft_2 := AIRCRAFT_2_SCENE.instantiate() as RigidBody3D
	aircraft_1.freeze = true
	aircraft_2.freeze = true
	aircraft_2.position = Vector3(20.0, 0.0, 0.0)
	add_child(aircraft_1)
	add_child(aircraft_2)
	await get_tree().process_frame

	var mount_1 := aircraft_1.get_node_or_null("InstrumentPanel") as Node3D
	var mount_2 := aircraft_2.get_node_or_null("InstrumentPanel") as Node3D
	_expect(mount_1 != null and mount_2 != null, "lightweight panel mounts are missing")
	_expect(mount_1 != null and mount_1.has_method("is_pooled_instrument_panel_mount"), "Aircraft 1 still owns a live panel")
	_expect(mount_2 != null and mount_2.has_method("is_pooled_instrument_panel_mount"), "Aircraft 2 still owns a live panel")
	_expect(aircraft_1.get_node_or_null("CameraTarget/SensorOrigin") is Node3D, "Aircraft 1 target sensor marker is missing")
	_expect(aircraft_1.get_node_or_null("CameraTarget/Camera") == null, "Aircraft 1 still owns an AI target Camera3D")
	_expect(mount_1.get_node_or_null("SubViewport") == null, "AI panel mount still contains a render viewport")
	var aircraft_1_panel_mesh := aircraft_1.get_node_or_null("aircraft_1/fuselage") as MeshInstance3D
	var aircraft_1_panel_surface := -1
	var original_surface_override: Material = null
	if aircraft_1_panel_mesh != null and aircraft_1_panel_mesh.mesh != null:
		for surface_index in range(aircraft_1_panel_mesh.mesh.get_surface_count()):
			var material := aircraft_1_panel_mesh.get_surface_override_material(surface_index)
			if material == null:
				material = aircraft_1_panel_mesh.mesh.surface_get_material(surface_index)
			if material != null and material.resource_name == "Instrument panel material":
				aircraft_1_panel_surface = surface_index
				original_surface_override = aircraft_1_panel_mesh.get_surface_override_material(surface_index)
				break
	_expect(aircraft_1_panel_surface >= 0, "Aircraft 1 model panel surface is missing")

	var camera_1 := aircraft_1.get_node_or_null("CameraCockpit/Camera3D") as Camera3D
	_expect(camera_1 != null, "Aircraft 1 cockpit camera is missing")
	if camera_1 != null:
		camera_1.current = true
	mount_1.call("set_view_updates_active", true)
	await get_tree().process_frame
	var live_1 := mount_1.call("get_live_panel") as Node3D
	_expect(live_1 != null, "viewed aircraft did not check out a live panel")
	var first_panel_id := live_1.get_instance_id() if live_1 != null else 0
	if live_1 != null:
		_expect(live_1.get("aircraft") == aircraft_1, "live panel did not bind to Aircraft 1")
		_expect(live_1.get("module_layout") == mount_1.call("get_effective_module_layout"), "pooled display is not using the Aircraft 1/5 standard layout")
		_expect(live_1.global_transform.is_equal_approx(mount_1.global_transform), "live panel did not follow its Aircraft 1 mount")
		_expect(live_1.get("target_camera") is Camera3D, "pooled live panel has no target render camera")
		var panel_viewport := live_1.get_node_or_null("SubViewport") as SubViewport
		var target_viewport := live_1.get("target_viewport") as SubViewport
		_expect(panel_viewport != null and panel_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "viewed panel viewport is not active")
		_expect(target_viewport != null and target_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "viewed target-camera viewport is not active")
		var bound_mesh := live_1.get("model_panel_mesh") as MeshInstance3D
		_expect(bound_mesh == aircraft_1.get_node_or_null("aircraft_1/fuselage"), "Aircraft 1 live display did not bind its model surface")
		if DisplayServer.get_name() != "headless":
			await get_tree().process_frame
			await get_tree().process_frame
			var capture := get_viewport().get_texture().get_image()
			var capture_path := "user://instrument_panel_pool_smoketest.png"
			var capture_error := capture.save_png(capture_path) if capture != null else ERR_CANT_CREATE
			_expect(capture_error == OK, "pooled panel screenshot could not be saved")
			if capture_error == OK:
				print("[InstrumentPanelPoolSmoketest] screenshot=%s" % ProjectSettings.globalize_path(capture_path))

	mount_1.call("set_view_updates_active", false)
	await get_tree().process_frame
	_expect(mount_1.call("get_live_panel") == null, "released Aircraft 1 retained a live panel")
	if aircraft_1_panel_surface >= 0:
		_expect(
			aircraft_1_panel_mesh.get_surface_override_material(aircraft_1_panel_surface) == original_surface_override,
			"released panel left its viewport material on Aircraft 1"
		)

	var camera_2 := aircraft_2.get_node_or_null("CameraCockpit/Camera3D") as Camera3D
	if camera_2 != null:
		camera_2.current = true
	mount_2.call("set_view_updates_active", true)
	await get_tree().process_frame
	var live_2 := mount_2.call("get_live_panel") as Node3D
	_expect(live_2 != null, "Aircraft 2 did not check out the released panel")
	if live_2 != null:
		_expect(live_2.get_instance_id() == first_panel_id, "released panel instance was not reused")
		_expect(live_2.get("aircraft") == aircraft_2, "reused panel retained the old aircraft binding")
		_expect(live_2.global_transform.is_equal_approx(mount_2.global_transform), "reused panel did not move to Aircraft 2")

	var stats: Dictionary = pool.call("get_pool_stats")
	_expect(int(stats.get("capacity", 0)) == 2, "panel pool capacity is not two")
	_expect(int(stats.get("checked_out", 0)) == 1, "AI aircraft checked out extra live panels")
	_expect(int(stats.get("render_warm_count", 0)) == 2, "both pooled viewports were not render-warmed")
	_expect(bool(stats.get("render_warm_complete", false)), "pooled viewport render warmup did not complete")
	mount_2.call("set_view_updates_active", false)
	_finish(aircraft_1, aircraft_2)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(aircraft_1: Node, aircraft_2: Node) -> void:
	if aircraft_1 != null:
		aircraft_1.queue_free()
	if aircraft_2 != null:
		aircraft_2.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("INSTRUMENT_PANEL_POOL_SMOKETEST_OK capacity=2 render_warmed=2 ai_live_panels=0 target_camera=pooled reuse=true")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[InstrumentPanelPoolSmoketest] %s" % failure)
	get_tree().quit(1)
