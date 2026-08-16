extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node.new()
	scene.name = "FlightDirectorFreedCameraTargetSmoketest"
	root.add_child(scene)
	current_scene = scene

	# Attach production scripts after insertion so their scenario _ready() setup
	# does not obscure this focused reference-lifetime check.
	var director := Node.new()
	director.name = "FlightDirector"
	scene.add_child(director)
	director.set_script(load("res://AirOps/FlightDirector.gd") as Script)

	var stale_aircraft := RigidBody3D.new()
	stale_aircraft.name = "FreedCameraAircraft"
	scene.add_child(stale_aircraft)
	var stale_controller := Node3D.new()
	stale_controller.name = "StaleCameraController"
	scene.add_child(stale_controller)
	stale_controller.set_script(load("res://Camera/CameraController.gd") as Script)
	stale_controller.set("aircraft", stale_aircraft)
	stale_controller.add_to_group("camera_controller")

	var live_aircraft := RigidBody3D.new()
	live_aircraft.name = "LivePlayerAircraft"
	live_aircraft.add_to_group("friendlies")
	scene.add_child(live_aircraft)
	var live_controller := Node3D.new()
	live_controller.name = "LiveCameraController"
	scene.add_child(live_controller)
	live_controller.set_script(load("res://Camera/CameraController.gd") as Script)
	live_controller.set("aircraft", live_aircraft)
	live_controller.add_to_group("camera_controller")

	stale_aircraft.free()
	var selected: Node = director.call("_get_player_camera_controller") as Node
	if selected != live_controller:
		_fail("freed aircraft reference prevented selection of the live camera controller")
		return

	live_aircraft.free()
	selected = director.call("_get_player_camera_controller") as Node
	if selected != null:
		_fail("camera lookup returned a controller whose aircraft had been freed")
		return

	print("[FlightDirectorFreedCameraTargetSmoketest] PASS stale_skipped=true live_selected=true empty_safe=true")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[FlightDirectorFreedCameraTargetSmoketest] FAIL %s" % reason)
	quit(1)
