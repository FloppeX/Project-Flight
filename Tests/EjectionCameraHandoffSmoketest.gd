extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "EjectionCameraHandoffSmoketest"
	root.add_child(scene)
	current_scene = scene

	var source_aircraft := RigidBody3D.new()
	source_aircraft.name = "SourceAircraft"
	source_aircraft.add_to_group("aircraft")
	source_aircraft.add_to_group("friendlies")
	var cockpit_tripod := _make_tripod("CameraCockpit")
	var chase_tripod := _make_tripod("CameraChase")
	var cinematic_tripod := _make_tripod("CameraCinematic")
	source_aircraft.add_child(cockpit_tripod)
	source_aircraft.add_child(chase_tripod)
	source_aircraft.add_child(cinematic_tripod)

	var controller_script := load("res://Camera/CameraController.gd") as Script
	var detached_controller := Node.new()
	detached_controller.set_script(controller_script)
	detached_controller.set("aircraft", source_aircraft)
	detached_controller.call("_build_view_targets")
	detached_controller.free()
	var controller := Node.new()
	controller.set_script(controller_script)
	controller.name = "CameraController"
	controller.set("aircraft", source_aircraft)
	controller.set("cockpit_tripod", cockpit_tripod)
	controller.set("chase_tripod", chase_tripod)
	controller.set("cinematic_tripod", cinematic_tripod)
	source_aircraft.add_child(controller)
	scene.add_child(source_aircraft)
	await process_frame

	var ejected_pilot := RigidBody3D.new()
	ejected_pilot.name = "EjectedPilot"
	scene.add_child(ejected_pilot)
	var cockpit_global := cockpit_tripod.global_transform
	source_aircraft.remove_child(cockpit_tripod)
	ejected_pilot.add_child(cockpit_tripod)
	cockpit_tripod.global_transform = cockpit_global
	var pilot_focus := cockpit_tripod.get_node("Camera3D") as Camera3D
	controller.set("deathcam_active", true)
	chase_tripod.set_process(false)
	chase_tripod.set_physics_process(false)
	controller.call("focus_ejected_pilot", ejected_pilot, pilot_focus)

	if controller.get("aircraft") != ejected_pilot:
		_fail("camera controller kept the source aircraft reference")
		return
	if bool(controller.get("deathcam_active")) or not chase_tripod.is_processing() \
			or not chase_tripod.is_physics_processing():
		_fail("ejection did not cancel the aircraft death-camera state")
		return
	if controller.get_parent() != scene or chase_tripod.get_parent() != scene \
			or cinematic_tripod.get_parent() != scene:
		_fail("camera nodes did not detach from the source aircraft")
		return
	var view_targets: Array = controller.get("_view_targets") as Array
	if view_targets.size() != 3:
		_fail("ejected pilot did not exclusively own the three camera modes")
		return
	for target_variant in view_targets:
		var target := target_variant as Dictionary
		if target.get("aircraft", null) != ejected_pilot:
			_fail("a camera mode still targeted the source aircraft")
			return

	var flight_director := root.get_node_or_null("FlightDirector")
	if flight_director == null:
		_fail("FlightDirector autoload missing")
		return
	flight_director.call("register_aircraft", source_aircraft)
	flight_director.set("current_viewed_aircraft", source_aircraft)
	flight_director.set("player_controlled_plane", source_aircraft)
	flight_director.set("is_player_controlling", true)
	flight_director.call("replace_aircraft_with_ejected_pilot", source_aircraft, ejected_pilot)
	var active_aircraft: Array = flight_director.get("active_aircraft") as Array
	if source_aircraft in active_aircraft or ejected_pilot not in active_aircraft:
		_fail("FlightDirector retained the source aircraft after pilot takeover")
		return
	if flight_director.get("current_viewed_aircraft") != ejected_pilot:
		_fail("FlightDirector did not transfer the active view to the pilot")
		return
	if bool(flight_director.call("is_destroyed_plane_linger_active")):
		_fail("destroyed-plane linger remained active after ejection")
		return

	var sequence_script := load("res://Aircraft/EjectionSequence.gd") as Script
	var sequence := Node.new()
	sequence.set_script(sequence_script)
	sequence.name = "EjectionSequence"
	source_aircraft.add_child(sequence)
	sequence.call("_detach_sequence_from_aircraft")
	sequence.call("_retire_source_aircraft", source_aircraft)
	if sequence.get_parent() != scene or not source_aircraft.is_queued_for_deletion():
		_fail("ejection sequence did not retire its source aircraft")
		return
	if source_aircraft.is_in_group("aircraft") or source_aircraft.is_in_group("friendlies"):
		_fail("retired aircraft remained in camera-cycle groups")
		return

	await process_frame
	if is_instance_valid(source_aircraft):
		_fail("source aircraft remained in the scene after the handoff frame")
		return
	if not is_instance_valid(controller) or not is_instance_valid(ejected_pilot):
		_fail("pilot camera ownership did not survive source-aircraft deletion")
		return
	for mode in range(3):
		controller.call("switch_to_aircraft_and_mode", ejected_pilot, mode)
		if controller.call("get_current_camera") == null:
			_fail("pilot camera mode %d was unavailable after aircraft deletion" % mode)
			return

	print("[EjectionCameraHandoffSmoketest] PASS cameras=3 source_freed=true target=EjectedPilot")
	scene.free()
	quit(0)


func _make_tripod(node_name: String) -> Node3D:
	var tripod := Node3D.new()
	tripod.name = node_name
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	tripod.add_child(camera)
	return tripod


func _fail(reason: String) -> void:
	push_error("[EjectionCameraHandoffSmoketest] FAIL %s" % reason)
	quit(1)
