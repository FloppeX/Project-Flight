extends SceneTree


const AirTaskModel: Script = preload("res://AI/AirTask.gd")


class MockAIPilot:
	extends Node

	var assigned_kind: int = -1

	func start_recovery() -> bool:
		return true

	func assign_air_task(task: Variant) -> bool:
		assigned_kind = int(task.kind)
		return true


class MockAIToggle:
	extends Node

	var ai_active: bool = false
	var enable_count: int = 0

	func enable_ai() -> void:
		ai_active = true
		enable_count += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "FlightDirectorNearestRtbHotkeySmoketest"
	root.add_child(scene)
	current_scene = scene

	var camera := Camera3D.new()
	camera.name = "PlayerCamera"
	camera.position = Vector3.ZERO
	scene.add_child(camera)
	camera.make_current()

	var carrier := Node3D.new()
	carrier.name = "Carrier"
	carrier.position = Vector3(100.0, 0.0, 0.0)
	carrier.add_to_group("carrier")
	scene.add_child(carrier)

	var camera_near := _make_candidate("CameraNear", Vector3(5.0, 0.0, 0.0))
	var carrier_near := _make_candidate("CarrierNear", Vector3(90.0, 0.0, 0.0))
	var parked_near := _make_candidate("ParkedNear", Vector3(1.0, 0.0, 0.0))
	parked_near.set_meta("parking_brake", true)
	var helicopter_near := _make_candidate("HelicopterNear", Vector3(2.0, 0.0, 0.0))
	helicopter_near.set_meta("is_helicopter", true)
	for aircraft: RigidBody3D in [camera_near, carrier_near, parked_near, helicopter_near]:
		scene.add_child(aircraft)

	var director := Node.new()
	director.name = "FlightDirectorNearestRtbProbe"
	director.set_script(load("res://AirOps/FlightDirector.gd") as Script)
	scene.add_child(director)
	director.set_process(false)
	director.set_process_input(false)
	director.set("current_viewed_aircraft", carrier_near)
	director.set("is_player_controlling", true)
	director.set("player_controlled_plane", camera_near)

	var l_press := InputEventKey.new()
	l_press.pressed = true
	l_press.physical_keycode = KEY_L
	var shifted_l_press := InputEventKey.new()
	shifted_l_press.pressed = true
	shifted_l_press.physical_keycode = KEY_L
	shifted_l_press.shift_pressed = true
	director.call("_input", shifted_l_press)
	if (camera_near.get_node("AIPilot") as MockAIPilot).assigned_kind != -1:
		_fail("unmodified L handler intercepted the existing Shift+L command")
		return
	director.call("_input", l_press)

	var camera_near_pilot := camera_near.get_node("AIPilot") as MockAIPilot
	if camera_near_pilot.assigned_kind != AirTaskModel.Kind.RECOVER:
		_fail("L did not assign RECOVER to the camera-nearest fixed-wing")
		return
	if (carrier_near.get_node("AIPilot") as MockAIPilot).assigned_kind != -1:
		_fail("L selected the plane nearest the carrier instead of the camera")
		return
	if (parked_near.get_node("AIPilot") as MockAIPilot).assigned_kind != -1:
		_fail("L selected a carrier-owned parked plane")
		return
	if (helicopter_near.get_node("AIPilot") as MockAIPilot).assigned_kind != -1:
		_fail("L selected a helicopter instead of a fixed-wing plane")
		return
	var camera_near_toggle := camera_near.get_node("AIToggle") as MockAIToggle
	if not camera_near_toggle.ai_active or camera_near_toggle.enable_count != 1:
		_fail("L did not return the selected player-controlled plane to AI control")
		return
	if bool(director.get("is_player_controlling")) \
	or director.get("player_controlled_plane") != null:
		_fail("L left FlightDirector claiming manual control of the RTB plane")
		return
	if str(camera_near.get_meta("rtb_reason", "")) != "Player camera command (L)":
		_fail("L did not record the manual RTB reason")
		return

	l_press.echo = true
	director.call("_input", l_press)
	if camera_near_toggle.enable_count != 1:
		_fail("a held L key repeated the RTB command")
		return

	print("[FlightDirectorNearestRtbHotkeySmoketest] PASS nearest=camera fixed_wing_only=true carrier_owned_excluded=true player_control_released=true shift_l_preserved=true echo_ignored=true")
	quit(0)


func _make_candidate(aircraft_name: String, position: Vector3) -> RigidBody3D:
	var aircraft := RigidBody3D.new()
	aircraft.name = aircraft_name
	aircraft.position = position
	aircraft.add_to_group("friendlies")

	var camera_controller := Node3D.new()
	camera_controller.name = "CameraController"
	aircraft.add_child(camera_controller)

	var pilot := MockAIPilot.new()
	pilot.name = "AIPilot"
	aircraft.add_child(pilot)

	var toggle := MockAIToggle.new()
	toggle.name = "AIToggle"
	aircraft.add_child(toggle)
	return aircraft


func _fail(reason: String) -> void:
	push_error("[FlightDirectorNearestRtbHotkeySmoketest] FAIL %s" % reason)
	quit(1)
