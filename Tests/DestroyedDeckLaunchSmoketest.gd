extends Node

const CARRIER_SCENE := preload("res://LandCarrier/LandCarrier2.tscn")
var failures: Array[String] = []
var launched := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# Run each scenario in a fresh process so carrier singleton registrations
	# and surviving airborne aircraft cannot leak into the next scenario.
	for phase in ["elevator" if "--elevator" in OS.get_cmdline_user_args() else "catapult"]:
		var carrier := CARRIER_SCENE.instantiate()
		add_child(carrier)
		await get_tree().process_frame
		await get_tree().process_frame
		var manager := carrier.get_node("FlightDeckManager") as FlightDeckManager
		var inventory := manager.stored_aircraft.size()
		launched = 0
		_expect(manager.queue_ai_flight(3, self) == 3, "three aircraft accepted")
		var destroyed := false
		for tick in 3600:
			var jobs: Dictionary = manager.get("_parallel_launch_jobs")
			if not destroyed:
				for job: Dictionary in jobs.values():
					var aircraft: Variant = job.get("aircraft")
					if not is_instance_valid(aircraft): continue
					var bots: Array = job.get("tractors", [])
					var catapult: Node = job.get("catapult")
					var ready := not bots.is_empty() if phase == "elevator" else bool(catapult.get("_moving_to_latch"))
					if ready:
						aircraft.queue_free()
						destroyed = true
						break
			if destroyed and jobs.is_empty(): break
			await get_tree().physics_frame
		_expect(destroyed, phase + ": reached destruction phase")
		_expect((manager.get("_parallel_launch_jobs") as Dictionary).is_empty(), phase + ": lanes released")
		_expect(launched == 2, phase + ": remaining queued aircraft launched")
		_expect(manager.stored_aircraft.size() == inventory - 3, phase + ": destroyed aircraft not refunded")
		_expect(manager.current_state == FlightDeckManager.DeckState.IDLE, phase + ": deck idle")
		_expect(manager.get("_pending_flight_ops") == null, phase + ": sortie owner released")
		print("[DestroyedDeckLaunch] %s destroyed=%s launched=%d jobs=%d" % [phase, destroyed, launched, (manager.get("_parallel_launch_jobs") as Dictionary).size()])
		for bot: Node3D in manager.tractor_bots:
			_expect(not bool(bot.get("is_active")), phase + ": tractor detached")
			_expect(not is_instance_valid(bot.get("target_aircraft")), phase + ": tractor target cleared")
			var home: Transform3D = manager.call("_get_tractor_home_transform_local", bot, manager.tractor_bots.find(bot))
			_expect(Vector2(bot.position.x - home.origin.x, bot.position.z - home.origin.z).length() < 1.0, phase + ": tractor returned to home elevator slot")
			var elevator: Node = manager.call("_get_home_elevator_for_bot", bot)
			_expect(manager.call("_is_elevator_physically_at_bottom_for", elevator), phase + ": elevator returned to hangar")
			_expect(bot.position.y < float(manager.call("_get_deck_local_y")) - 8.0, phase + ": tractor returned below deck")
		carrier.queue_free()
		await get_tree().process_frame
	if failures.is_empty():
		print("DESTROYED_DECK_LAUNCH_SMOKETEST_OK")
	else:
		for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func notify_aircraft_launched(_pilot: Node) -> void:
	launched += 1

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
