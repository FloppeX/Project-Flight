extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var source := RigidBody3D.new()
	source.name = "TestAircraft"
	source.set_meta("pilot_roster_id", "pilot-test-13")
	source.set_meta("pilot_callsign", "Skylark")
	source.set_meta("pilot_flight_callsign", "Archer Two")
	source.set_meta("pilot_display_name", "Lt. Skylark")
	source.set_meta("pilot_identity", {"id": "pilot-test-13", "callsign": "Skylark"})
	scene.add_child(source)
	var sequence := Node.new()
	sequence.set_script(load("res://Aircraft/EjectionSequence.gd"))
	scene.add_child(sequence)
	var seat := RigidBody3D.new()
	scene.add_child(seat)
	sequence.call("_copy_pilot_identity_metadata", source, seat)
	var pilot := load("res://Models/Characters/DownedPilot.tscn").instantiate() as RigidBody3D
	pilot.set_physics_process(false)
	scene.add_child(pilot)
	sequence.call("_copy_pilot_identity_metadata", seat, pilot)
	pilot.set_meta("ejected_pilot_camera_target", true)
	pilot.set_meta("player_control_locked", true)
	pilot.add_to_group("ejected_pilots")
	pilot.add_to_group("downed_pilot")
	pilot.call("ensure_spectator_cameras")
	await process_frame
	var director := root.get_node_or_null("FlightDirector")
	if director == null:
		_fail("FlightDirector autoload is missing")
		return
	if pilot.get_meta("pilot_roster_id", "") != "pilot-test-13" \
			or pilot.get_meta("pilot_flight_callsign", "") != "Archer Two" \
			or pilot.get_meta("pilot_display_name", "") != "Lt. Skylark":
		_fail("aircraft identity did not reach the landed pilot")
		return
	if not director.call("_get_friendly_aircraft").has(pilot):
		_fail("landed pilot is missing from friendly camera selection")
		return
	director.set("current_category", 1)
	director.set("aircraft_cam_mode", 0)
	director.call("_activate_aircraft_view_now", pilot)
	for mode in range(3):
		var tripod_name: String = ["CameraCockpit", "CameraChase", "CameraCinematic"][mode]
		var expected := pilot.get_node_or_null(tripod_name + "/Camera3D") as Camera3D
		if expected == null or root.get_viewport().get_camera_3d() != expected:
			_fail("pilot mode %d did not activate its own camera" % mode)
			return
		if mode < 2:
			director.call("_cycle_aircraft_view")
		if director.get("current_viewed_aircraft") != pilot:
			_fail("camera cycling lost the pilot as selected identity")
			return
	var selected_camera := root.get_viewport().get_camera_3d()
	var seat_cockpit := load("res://Camera/CameraTripod.tscn").instantiate() as Node3D
	seat_cockpit.name = "CameraCockpit"
	seat.add_child(seat_cockpit)
	sequence.set("_pilot_body", seat)
	sequence.call("_land_pilot", Vector3(20.0, 0.0, 0.0))
	var landed_pilot: RigidBody3D = null
	for node in get_nodes_in_group("downed_pilot"):
		if node != pilot:
			landed_pilot = node as RigidBody3D
	if landed_pilot == null or landed_pilot.get_meta("pilot_roster_id", "") != "pilot-test-13":
		_fail("unwatched landing lost its pilot identity")
		return
	if not director.call("_get_friendly_aircraft").has(landed_pilot):
		_fail("unwatched landed pilot was not selectable")
		return
	if director.get("current_viewed_aircraft") != pilot \
			or root.get_viewport().get_camera_3d() != selected_camera:
		_fail("another pilot landing stole the selected camera")
		return
	var found_by_cycle := false
	for step in range(director.call("_get_friendly_aircraft").size() + 1):
		director.call("cycle_target", 1)
		if director.get("current_viewed_aircraft") == landed_pilot:
			found_by_cycle = true
			break
	if not found_by_cycle:
		_fail("normal target cycling could not select the landed pilot")
		return
	for mode in range(3):
		director.set("aircraft_cam_mode", mode)
		director.call("_activate_aircraft_view_now", landed_pilot)
		var tripod_name: String = ["CameraCockpit", "CameraChase", "CameraCinematic"][mode]
		var expected := landed_pilot.get_node_or_null(tripod_name + "/Camera3D") as Camera3D
		if expected == null or root.get_viewport().get_camera_3d() != expected:
			_fail("landed pilot mode %d has no working camera" % mode)
			return
	director.call("_take_player_control", landed_pilot)
	if bool(director.get("is_player_controlling")):
		_fail("taking control bypassed the landed pilot lock")
		return
	var model := pilot.get_node("Model") as Node3D
	model.quaternion = Quaternion.IDENTITY
	pilot.set("_phase", 0)
	pilot.set("_clearing_target", pilot.global_position + Vector3(0.0, 0.0, 20.0))
	pilot.call("_physics_process", 0.1)
	var player := model.get_node("BakedAnimationPlayer") as AnimationPlayer
	if player.assigned_animation != &"run" or pilot.global_position.z <= 0.1:
		_fail("normal clearing travel did not use the run animation")
		return
	await process_frame
	print("[DownedPilotIdentityViewsSmoketest] PASS identity=true selectable=true views=3 run=true control_locked=true")
	quit(0)


func _fail(message: String) -> void:
	push_error("[DownedPilotIdentityViewsSmoketest] " + message)
	quit(1)
