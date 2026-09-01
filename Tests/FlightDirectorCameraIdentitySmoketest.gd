extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node.new()
	scene.name = "FlightDirectorCameraIdentitySmoketest"
	root.add_child(scene)
	current_scene = scene

	var director := Node.new()
	director.name = "FlightDirectorCameraIdentityProbe"
	scene.add_child(director)
	director.set_script(load("res://AirOps/FlightDirector.gd") as Script)

	var first := _make_friendly("FirstFriendly")
	var viewed := _make_friendly("ViewedFriendly")
	scene.add_child(first)
	scene.add_child(viewed)

	director.set("current_category", 1)
	director.set("friendly_index", 0)
	director.set("current_viewed_aircraft", viewed)
	director.set("aircraft_cam_mode", 0)
	director.call("_cycle_aircraft_view")
	if director.get("current_viewed_aircraft") != viewed:
		_fail("Y camera cycling changed aircraft when the friendly index was stale")
		return
	if int(director.get("aircraft_cam_mode")) != 1:
		_fail("Y camera cycling did not advance the camera mode")
		return
	if int(director.get("friendly_index")) != 1:
		_fail("camera cycling did not resynchronize the friendly index")
		return
	var viewed_controller := viewed.get_node_or_null("CameraController")
	var viewed_hud := viewed.get_node_or_null("HeadsUpDisplay") as Control
	var viewed_panel := viewed.get_node_or_null("InstrumentPanel") as Node3D
	if viewed_controller == null or not viewed_controller.is_processing_input():
		_fail("camera cycling did not restore right-stick input processing")
		return
	if viewed_hud == null or not viewed_hud.visible or viewed_panel == null or not viewed_panel.visible:
		_fail("camera cycling did not restore the HUD and instrument presentation")
		return

	director.call("toggle_player_control")
	if not bool(director.get("is_player_controlling")) \
	or director.get("player_controlled_plane") != viewed \
	or director.get("current_viewed_aircraft") != viewed \
	or int(director.get("current_category")) != 1:
		_fail("taking control did not preserve the viewed aircraft as camera identity")
		return

	print("[FlightDirectorCameraIdentitySmoketest] PASS y_preserves_aircraft=true camera_input=true cockpit_ui=true control_preserves_camera_identity=true")
	quit(0)


func _make_friendly(aircraft_name: String) -> RigidBody3D:
	var aircraft := RigidBody3D.new()
	aircraft.name = aircraft_name
	aircraft.add_to_group("friendlies")
	var controller := Node3D.new()
	controller.name = "CameraController"
	controller.set_process_input(false)
	aircraft.add_child(controller)
	var hud := Control.new()
	hud.name = "HeadsUpDisplay"
	hud.visible = false
	aircraft.add_child(hud)
	var panel := Node3D.new()
	panel.name = "InstrumentPanel"
	panel.visible = false
	aircraft.add_child(panel)
	return aircraft


func _fail(reason: String) -> void:
	push_error("[FlightDirectorCameraIdentitySmoketest] FAIL %s" % reason)
	quit(1)
