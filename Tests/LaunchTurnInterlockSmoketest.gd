extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	# Install scripts after entering the tree to isolate the interlock from scene setup.
	var carrier := CharacterBody3D.new()
	scene.add_child(carrier)
	carrier.set_script(load("res://LandCarrier/LandCarrier.gd"))
	var deck := Node.new()
	carrier.add_child(deck)
	var deck_script = load("res://LandCarrier/FlightDeckManager.gd")
	deck.set_script(deck_script)
	deck.set("launch_terrain_check_enabled",false)
	var aircraft := RigidBody3D.new()
	carrier.add_child(aircraft)
	deck.set("deck_aircraft",aircraft)
	deck.set("current_state",deck_script.DeckState.RETRIEVING_FROM_HANGAR)
	check(not deck.call("_has_pending_launch"),"early retrieval unnecessarily reserved a straight deck")
	aircraft.set_meta("physics_ready_for_launch",true)
	check(deck.call("_has_pending_launch"),"catapult-ready serial retrieval is invisible to launch constraint")
	check(deck.call("_launch_needs_carrier_constraint"),"catapult-ready retrieval did not request straight travel")
	carrier.set("_current_steer",0.2)
	carrier.set("_current_yaw_rate_rad_s",deg_to_rad(0.2))
	check(not deck.call("_is_carrier_turning_for_launch"),"settled launch was blocked by residual steering")
	check(not deck.call("_is_carrier_settled_for_recovery"),"launch change relaxed landing interlock")
	for rate in [-1.0,1.0]:
		carrier.set("_current_yaw_rate_rad_s",deg_to_rad(rate))
		check(deck.call("_is_carrier_turning_for_launch"),"actual deck turn was permitted")
	carrier.set("_current_yaw_rate_rad_s",0.0)
	deck.set("launch_stop_carrier_to_launch",false)
	check(deck.call("_is_carrier_turning_for_launch"),"unconstrained steering was ignored")
	deck.set("launch_stop_carrier_to_launch",true)
	aircraft.remove_meta("physics_ready_for_launch")
	check(not deck.call("_has_pending_launch"),"cleared handoff left a stale launch constraint")
	scene.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("[LaunchTurnInterlock] PASS serial_handoff residual_steer actual_rotation recovery_unchanged" if failures.is_empty() else "[LaunchTurnInterlock] FAIL")
	quit(0 if failures.is_empty() else 1)
