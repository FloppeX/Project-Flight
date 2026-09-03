extends SceneTree


class CameraControllerProbe:
	extends Node3D

	var cockpit_camera: Camera3D = null

	func switch_to_camera(_mode: int) -> void:
		if is_instance_valid(cockpit_camera):
			cockpit_camera.current = true


class CarrierCameraProbe:
	extends Node3D

	var carrier_camera: Camera3D = null

	func get_camera() -> Camera3D:
		return carrier_camera

	func get_camera_for_mode(_mode: int) -> Camera3D:
		return carrier_camera

	func activate_view_mode(_mode: int) -> Camera3D:
		return carrier_camera

	func get_view_mode_count() -> int:
		return 1

	func is_control_room_camera(camera: Camera3D) -> bool:
		return camera == carrier_camera

	func is_carrier_camera(camera: Camera3D) -> bool:
		return camera == carrier_camera


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "FlightDirectorAircraftTransitionSmoketest"
	root.add_child(scene)
	current_scene = scene

	var director := Node.new()
	director.name = "FlightDirectorAircraftTransitionProbe"
	director.set_script(load("res://AirOps/FlightDirector.gd") as Script)
	scene.add_child(director)
	await process_frame
	director.set_process(false)
	_validate_real_endpoint_scenes()

	var source := _make_aircraft("TransitionSource", Vector3.ZERO)
	var target := _make_aircraft("TransitionTarget", Vector3(5000.0, 600.0, 3000.0))
	scene.add_child(source)

	var visual_budget := root.get_node_or_null("EnemyVisualBudget")
	_expect(visual_budget != null, "EnemyVisualBudget autoload was unavailable")
	if visual_budget == null:
		_finish()
		return
	var prepared: Dictionary = visual_budget.call("prepare_ai_aircraft_for_tree_entry", target)
	_expect(bool(prepared.get("prepared", false)), "target presentation was not detached before tree entry")
	scene.add_child(target)

	var source_camera := source.get_node("CameraCockpit/Camera3D") as Camera3D
	source_camera.current = true
	director.set("current_category", 1)
	director.set("current_viewed_aircraft", source)
	director.set("friendly_index", 0)
	director.set("_ui_visible_aircraft", source)
	director.call("_set_aircraft_view_ui_enabled", source, true)

	var near_duration := float(director.call("_calculate_aircraft_transition_transfer_duration", 100.0))
	var far_duration := float(director.call("_calculate_aircraft_transition_transfer_duration", 20000.0))
	_expect(far_duration > near_duration, "far transfer did not receive a longer duration")
	_expect(far_duration <= float(director.get("aircraft_transition_max_transfer_s")) + 0.001, "far transfer exceeded its duration cap")

	var source_cockpit_local: Transform3D = director.call("_get_aircraft_cockpit_transform_local", source)
	var source_gate_local: Transform3D = director.call("_get_aircraft_transition_gate_local", source)
	_expect(source_gate_local.origin.y > source_cockpit_local.origin.y, "fallback transition gate was not above the cockpit")
	_expect(source_gate_local.origin.z < source_cockpit_local.origin.z, "fallback transition gate was not behind the +Z-facing cockpit")

	director.call("_view_aircraft", target)
	_expect(bool(director.call("is_aircraft_view_transition_active")), "aircraft-to-aircraft switch did not start a transition")
	_expect(director.get("current_viewed_aircraft") == source, "source stopped being authoritative before arrival")
	_expect(director.get("_aircraft_transition_target") == target, "pending target identity was not retained")
	_expect(bool(target.get_meta("visual_budget_presentation_staging", false)), "pending target was not staged")
	_expect(target.get_node_or_null("CameraCockpit") == null, "detached cockpit restored synchronously at transition start")
	var source_hud := source.get_node("HeadsUpDisplay") as Control
	_expect(not source_hud.visible, "source HUD remained visible over the transition camera")
	var transition_camera := director.get("_aircraft_transition_camera") as Camera3D
	_expect(is_instance_valid(transition_camera) and transition_camera.current, "temporary transition camera did not become current")

	director.call("_update_aircraft_camera_transition", 1.0 / 60.0)
	_expect(target.get_node_or_null("CameraCockpit") != null, "first staged frame did not restore the cockpit camera root")
	_expect(target.get_node_or_null("InstrumentPanel") == null, "more than one presentation root restored in the first staged frame")

	var frame_count := 1
	while bool(director.call("is_aircraft_view_transition_active")) and frame_count < 600:
		if frame_count == 30:
			target.global_position += Vector3(120.0, 15.0, -80.0)
		director.call("_update_aircraft_camera_transition", 1.0 / 60.0)
		frame_count += 1

	_expect(frame_count < 600, "transition did not complete within ten simulated seconds")
	_expect(director.get("current_viewed_aircraft") == target, "destination did not become authoritative at arrival")
	_expect(not bool(target.get_meta("visual_budget_presentation_staging", false)), "presentation staging lock remained after arrival")
	_expect(not bool(target.get_meta("visual_budget_presentation_keep_attached", false)), "presentation keep-attached lock remained after arrival")
	var target_camera := target.get_node_or_null("CameraCockpit/Camera3D") as Camera3D
	var target_hud := target.get_node_or_null("HeadsUpDisplay") as Control
	var target_panel := target.get_node_or_null("InstrumentPanel") as Node3D
	_expect(is_instance_valid(target_camera) and target_camera.current, "final handoff did not activate the destination cockpit camera")
	_expect(target_hud != null and target_hud.visible, "destination HUD was not enabled at arrival")
	_expect(target_panel != null and target_panel.visible, "destination instrument panel was not enabled at arrival")

	var helicopter := _make_aircraft("TransitionHelicopter", Vector3(1800.0, 260.0, -1300.0))
	helicopter.set_meta("is_helicopter", true)
	scene.add_child(helicopter)
	var helicopter_cockpit_local: Transform3D = director.call("_get_aircraft_cockpit_transform_local", helicopter)
	var helicopter_gate_local: Transform3D = director.call("_get_aircraft_transition_gate_local", helicopter)
	_expect(helicopter_gate_local.origin.y > helicopter_cockpit_local.origin.y, "helicopter transition gate was not above the cockpit")
	_expect(helicopter_gate_local.origin.z > helicopter_cockpit_local.origin.z, "helicopter transition gate did not lead over the nose away from the cabin")

	director.call("_view_aircraft", helicopter)
	_expect(bool(director.call("is_aircraft_view_transition_active")), "aircraft-to-helicopter switch did not start a transition")
	var helicopter_frames := _advance_transition(director)
	_expect(helicopter_frames < 600, "aircraft-to-helicopter transition did not complete")
	_expect(director.get("current_viewed_aircraft") == helicopter, "helicopter did not become authoritative at arrival")
	var helicopter_camera := helicopter.get_node_or_null("CameraCockpit/Camera3D") as Camera3D
	_expect(is_instance_valid(helicopter_camera) and helicopter_camera.current, "helicopter cockpit camera was not activated")

	var carrier := _make_carrier_camera_provider()
	carrier.position = Vector3(-2200.0, 80.0, 900.0)
	scene.add_child(carrier)
	director.call("cycle_target", 1)
	_expect(bool(director.call("is_aircraft_view_transition_active")), "helicopter-to-carrier switch did not start a transition")
	_expect(int(director.get("_aircraft_transition_target_category")) == 0, "carrier was not retained as the pending transition category")
	var carrier_frames := _advance_transition(director)
	_expect(carrier_frames < 600, "helicopter-to-carrier transition did not complete")
	_expect(int(director.get("current_category")) == 0, "carrier did not become authoritative at arrival")
	_expect(director.get("current_viewed_aircraft") == null, "aircraft authority remained after carrier arrival")
	_expect(carrier.carrier_camera.current, "carrier control-room camera was not activated")

	director.call("cycle_target", 1)
	_expect(bool(director.call("is_aircraft_view_transition_active")), "carrier-to-aircraft switch did not start a transition")
	_expect(int(director.get("_aircraft_transition_source_category")) == 0, "carrier was not retained as the transition source")
	var return_frames := _advance_transition(director)
	_expect(return_frames < 600, "carrier-to-aircraft transition did not complete")
	_expect(director.get("current_viewed_aircraft") == source, "aircraft did not become authoritative after leaving the carrier")

	if _failures.is_empty():
		print("[FlightDirectorAircraftTransitionSmoketest] PASS frames=%d near_s=%.3f far_s=%.3f staged_one_root_per_frame=true moving_target=true ui_handoff=true helicopter_frames=%d carrier_frames=%d return_frames=%d" % [
			frame_count,
			near_duration,
			far_duration,
			helicopter_frames,
			carrier_frames,
			return_frames,
		])
		quit(0)
	else:
		for failure in _failures:
			push_error("[FlightDirectorAircraftTransitionSmoketest] FAIL %s" % failure)
		quit(1)


func _make_aircraft(aircraft_name: String, position: Vector3) -> RigidBody3D:
	var aircraft := RigidBody3D.new()
	aircraft.name = aircraft_name
	aircraft.position = position
	aircraft.add_to_group("friendlies")

	var cockpit := Node3D.new()
	cockpit.name = "CameraCockpit"
	cockpit.position = Vector3(0.0, 1.5, 2.0)
	aircraft.add_child(cockpit)
	var cockpit_camera := Camera3D.new()
	cockpit_camera.name = "Camera3D"
	cockpit_camera.rotation.y = PI
	cockpit.add_child(cockpit_camera)

	var controller := CameraControllerProbe.new()
	controller.name = "CameraController"
	controller.cockpit_camera = cockpit_camera
	aircraft.add_child(controller)

	var hud := Control.new()
	hud.name = "HeadsUpDisplay"
	hud.visible = true
	aircraft.add_child(hud)

	var panel := Node3D.new()
	panel.name = "InstrumentPanel"
	panel.visible = true
	aircraft.add_child(panel)
	return aircraft


func _validate_real_endpoint_scenes() -> void:
	var helicopter_scene := load("res://Aircraft/Aircraft_11.tscn") as PackedScene
	var actual_helicopter := helicopter_scene.instantiate() as RigidBody3D \
		if helicopter_scene != null else null
	_expect(actual_helicopter != null, "Aircraft_11 helicopter scene did not instantiate")
	if actual_helicopter != null:
		_expect(bool(actual_helicopter.get_meta("is_helicopter", false)), "Aircraft_11 is missing helicopter endpoint metadata")
		_expect(actual_helicopter.get_node_or_null("CameraCockpit/Camera3D") != null, "Aircraft_11 is missing its cockpit transition destination camera")
		actual_helicopter.free()

	var commander_scene := load("res://LandCarrier/Commander.tscn") as PackedScene
	var commander := commander_scene.instantiate() as Node3D if commander_scene != null else null
	_expect(commander != null, "carrier Commander scene did not instantiate")
	if commander != null:
		_expect(commander.get_node_or_null("CameraTransitionAnchor") != null, "carrier Commander is missing its bridge transition anchor")
		commander.free()


func _make_carrier_camera_provider() -> CarrierCameraProbe:
	var provider := CarrierCameraProbe.new()
	provider.name = "TransitionCarrier"
	provider.add_to_group("carrier_cam")
	var camera := Camera3D.new()
	camera.name = "CarrierControlRoomCamera"
	camera.position = Vector3(0.0, 1.8, 0.3)
	camera.rotation.y = PI
	provider.add_child(camera)
	provider.carrier_camera = camera
	var anchor := Marker3D.new()
	anchor.name = "CameraTransitionAnchor"
	anchor.position = Vector3(0.0, 4.0, 12.0)
	provider.add_child(anchor)
	return provider


func _advance_transition(director: Node, max_frames: int = 600) -> int:
	var frames := 0
	while bool(director.call("is_aircraft_view_transition_active")) and frames < max_frames:
		director.call("_update_aircraft_camera_transition", 1.0 / 60.0)
		frames += 1
	return frames


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error("[FlightDirectorAircraftTransitionSmoketest] FAIL %s" % failure)
	quit(1)
