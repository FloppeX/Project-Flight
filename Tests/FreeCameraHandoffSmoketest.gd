extends SceneTree


class StaleCameraController:
	extends Node

	var stale_camera: Camera3D

	func get_current_camera() -> Camera3D:
		return stale_camera


class OccupantPresentationProbe:
	extends Node3D

	var presentation_active: bool = false

	func is_pooled_aircraft_occupant_mount() -> bool:
		return true

	func set_presentation_active(active: bool) -> void:
		presentation_active = active
		visible = active


class ViewPresentationProbe:
	extends Node3D

	var view_updates_active: bool = false

	func set_view_updates_active(active: bool) -> void:
		view_updates_active = active


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	var director := root.get_node_or_null("FlightDirector")
	var radio_comms := root.get_node_or_null("RadioComms")
	_check(director != null, "FlightDirector autoload is unavailable")
	_check(radio_comms != null, "RadioComms autoload is unavailable")
	if director == null or radio_comms == null:
		_finish()
		return
	if bool(director.call("is_free_camera_active")):
		director.call("_toggle_free_camera")

	var aircraft := RigidBody3D.new()
	aircraft.name = "CameraHandoffAircraft"
	aircraft.add_to_group("aircraft")
	root.add_child(aircraft)
	var cockpit_tripod := Node3D.new()
	cockpit_tripod.name = "CameraCockpit"
	aircraft.add_child(cockpit_tripod)
	var source := Camera3D.new()
	source.name = "Camera3D"
	cockpit_tripod.add_child(source)
	aircraft.global_transform = Transform3D(
		Basis.from_euler(Vector3(0.17, -0.63, 0.31)),
		Vector3(1234.5, 678.25, -901.75)
	)
	cockpit_tripod.transform = Transform3D(
		Basis.from_euler(Vector3(-0.08, 0.12, -0.04)),
		Vector3(0.4, 1.6, 2.1)
	)
	source.transform = Transform3D(
		Basis.from_euler(Vector3(0.03, -0.06, 0.02)),
		Vector3(-0.15, 0.12, 0.35)
	)
	source.near = 0.025
	source.far = 6789.0
	source.fov = 83.0
	source.h_offset = 0.12
	source.v_offset = -0.08
	var canopy := Node3D.new()
	canopy.name = "CanopyProbe"
	aircraft.add_child(canopy)
	var canopy_visibility := CockpitCanopyVisibility.new()
	canopy_visibility.cockpit_camera_path = NodePath("../CameraCockpit/Camera3D")
	canopy_visibility.canopy_node_paths = [NodePath("../CanopyProbe")]
	canopy_visibility.scan_aircraft_for_hidden_materials = false
	aircraft.add_child(canopy_visibility)
	var source_pilot := OccupantPresentationProbe.new()
	source_pilot.name = "PhotoPilot"
	source_pilot.visible = false
	aircraft.add_child(source_pilot)
	var source_hud := ViewPresentationProbe.new()
	source_hud.name = "HeadsUpDisplay"
	source_hud.visible = false
	aircraft.add_child(source_hud)
	var source_panel := ViewPresentationProbe.new()
	source_panel.name = "InstrumentPanel"
	source_panel.visible = false
	aircraft.add_child(source_panel)

	var distant_aircraft := RigidBody3D.new()
	distant_aircraft.name = "DistantPhotoAircraft"
	distant_aircraft.add_to_group("aircraft")
	root.add_child(distant_aircraft)
	distant_aircraft.global_position = aircraft.global_position + Vector3(200.0, 0.0, 0.0)
	var distant_pilot := OccupantPresentationProbe.new()
	distant_pilot.name = "PhotoPilot"
	distant_pilot.visible = false
	distant_aircraft.add_child(distant_pilot)
	var distant_hud := ViewPresentationProbe.new()
	distant_hud.name = "HeadsUpDisplay"
	distant_hud.visible = false
	distant_aircraft.add_child(distant_hud)
	var distant_panel := ViewPresentationProbe.new()
	distant_panel.name = "InstrumentPanel"
	distant_panel.visible = false
	distant_aircraft.add_child(distant_panel)
	source.make_current()
	await process_frame
	_check(not canopy.visible, "canopy probe was not hidden for the cockpit camera")

	# A valid camera controller can retain a different inactive camera. It must
	# not override the camera the viewport says is actually on screen.
	var stale := Camera3D.new()
	stale.position = Vector3(-8000.0, 50.0, 9000.0)
	root.add_child(stale)
	var stale_controller := StaleCameraController.new()
	stale_controller.stale_camera = stale
	stale_controller.add_to_group("camera_controller")
	root.add_child(stale_controller)

	director.set("current_category", 1)
	director.set("current_viewed_aircraft", aircraft)
	_check(director.call("_get_current_active_camera") == source, "active-camera lookup ignored the viewport camera")
	var expected_transform := source.global_transform
	var expected_near := source.near
	var expected_far := source.far
	var expected_fov := source.fov
	director.call("_toggle_free_camera")
	var free_camera := director.get("_free_camera") as Camera3D
	_check(bool(director.call("is_free_camera_active")), "free camera did not activate")
	_check(bool(radio_comms.call("_is_free_camera_active")), "radio HUD did not detect free-camera mode")
	var radio_canvas := radio_comms.get("_canvas") as CanvasLayer
	if radio_canvas != null:
		radio_canvas.visible = true
		radio_comms.call("_update_display_visibility")
		_check(not radio_canvas.visible, "radio talk box remained visible in free-camera mode")
	else:
		_check(false, "radio talk-box canvas was unavailable")
	_check(is_instance_valid(free_camera), "free camera was not created")
	if is_instance_valid(free_camera):
		_check(free_camera.global_transform.is_equal_approx(expected_transform), "free camera did not inherit the exact world transform")
		_check(free_camera.get_meta(&"free_camera_view_source", null) == source, "free camera did not retain its cockpit visibility source")
		_check(is_equal_approx(free_camera.near, expected_near), "free camera changed the cockpit near plane")
		_check(is_equal_approx(free_camera.far, expected_far), "free camera changed the far plane")
		_check(is_equal_approx(free_camera.fov, expected_fov), "free camera changed the field of view")
		var before_idle_tick := free_camera.global_transform
		director.call("_physics_process", 0.016)
		_check(free_camera.global_transform.is_equal_approx(before_idle_tick), "idle free-camera update changed the inherited banked view")
		canopy_visibility.call("_update_canopy_visibility")
		_check(not canopy.visible, "canopy became visible at the inherited cockpit viewpoint")
		free_camera.global_position += Vector3(0.0, 0.0, 2.0)
		canopy_visibility.call("_update_canopy_visibility")
		_check(canopy.visible, "canopy remained hidden after free camera moved clear of the cockpit")

		_check(bool(director.call("begin_photo_mode_camera")), "photo mode did not adopt the existing free camera")
		_check(director.call("get_presentation_focus_aircraft") == aircraft, "photo mode did not initially focus the nearest aircraft")
		_check(source_pilot.presentation_active and source_pilot.visible, "nearest aircraft pilot was not shown in photo mode")
		_check(source_hud.visible and source_hud.view_updates_active, "nearest aircraft HUD was not shown in photo mode")
		_check(source_panel.visible and source_panel.view_updates_active, "nearest aircraft instrument panel was not shown in photo mode")
		_check(not distant_pilot.presentation_active and not distant_hud.visible and not distant_panel.visible, "distant aircraft presentation was enabled too early")
		var visual_budget := root.get_node_or_null("EnemyVisualBudget")
		if visual_budget != null:
			_check(bool(visual_budget.call("_is_unit_player_focused", aircraft, free_camera)), "visual budget did not protect the photo-mode aircraft presentation")

		free_camera.global_position = distant_aircraft.global_position
		director.call("_sync_viewed_aircraft_ui")
		_check(director.call("get_presentation_focus_aircraft") == distant_aircraft, "photo-mode presentation did not follow the closest aircraft")
		_check(distant_pilot.presentation_active and distant_pilot.visible, "new closest aircraft pilot was not shown")
		_check(distant_hud.visible and distant_hud.view_updates_active, "new closest aircraft HUD was not shown")
		_check(distant_panel.visible and distant_panel.view_updates_active, "new closest aircraft instrument panel was not shown")
		_check(not source_pilot.presentation_active and not source_hud.visible and not source_panel.visible, "previous closest aircraft presentation remained enabled")
		if visual_budget != null:
			_check(not bool(visual_budget.call("_is_unit_player_focused", aircraft, free_camera)), "visual budget retained the previous photo-mode aircraft focus")
			_check(bool(visual_budget.call("_is_unit_player_focused", distant_aircraft, free_camera)), "visual budget did not transfer protection to the new closest aircraft")

		director.call("end_photo_mode_camera")
		_check(bool(director.call("is_free_camera_active")), "photo mode incorrectly closed a pre-existing free camera")
		_check(not source_pilot.presentation_active and not distant_pilot.presentation_active, "photo mode left a pilot presentation enabled after exit")
		_check(not source_hud.visible and not source_panel.visible and not distant_hud.visible and not distant_panel.visible, "photo mode left HUD or instrument presentation visible after exit")

	director.call("_toggle_free_camera")
	_check(not bool(radio_comms.call("_is_free_camera_active")), "radio HUD retained stale free-camera state after exit")
	director.set("current_viewed_aircraft", null)
	director.set("current_category", 0)
	stale_controller.queue_free()
	stale.queue_free()
	distant_aircraft.queue_free()
	aircraft.queue_free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[FreeCameraHandoffSmoketest] PASS viewport_source=true world_transform=true projection=true bank_preserved=true cockpit_visibility=true photo_closest_presentation=true free_camera_radio_hidden=true")
		quit(0)
		return
	for failure in _failures:
		push_error("[FreeCameraHandoffSmoketest] FAIL %s" % failure)
	quit(1)
