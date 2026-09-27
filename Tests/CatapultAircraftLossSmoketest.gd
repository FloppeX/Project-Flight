extends SceneTree

var aborts := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var deck := Node3D.new()
	root.add_child(deck)
	var catapult := preload("res://LandCarrier/Catapult.gd").new()
	catapult.launch_steam_enabled = false
	catapult.shuttle = Node3D.new()
	catapult.latch_marker = Marker3D.new()
	catapult.release_marker = Marker3D.new()
	deck.add_child(catapult.shuttle)
	deck.add_child(catapult.latch_marker)
	deck.add_child(catapult.release_marker)
	catapult.release_marker.position.z = 50.0
	deck.add_child(catapult)
	catapult.set_physics_process(false)
	catapult.launch_sequence_aborted.connect(func(): aborts += 1)
	for phase in ["_settling", "_moving_to_latch", "_latched", "_engine_starting", "_spooling_up", "_hold_at_power", "_launching"]:
		var aircraft := RigidBody3D.new()
		deck.add_child(aircraft)
		catapult.set("_aircraft", aircraft)
		catapult.set(phase, true)
		aircraft.free()
		var before := aborts
		catapult._physics_process(1.0 / 60.0)
		catapult._physics_process(1.0 / 60.0)
		if aborts != before + 1 or not catapult.is_available_for_launch():
			push_error("Catapult failed to abort and become available after aircraft loss in " + phase)
			quit(1)
			return
	print("CATAPULT_AIRCRAFT_LOSS_SMOKETEST_OK")
	quit(0)
