extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager := root.get_node_or_null("AirOpsManager")
	if manager == null:
		_fail("AirOpsManager autoload is unavailable")
		return
	manager.set("mission_tasking_enabled", false)
	await process_frame

	var flights_variant: Variant = manager.get("flights")
	if not (flights_variant is Array) or (flights_variant as Array).is_empty():
		_fail("AirOpsManager has no flights")
		return
	var flight: Node = (flights_variant as Array)[0] as Node
	var task := {
		"id": "cap:carrier",
		"type": "cap",
		"priority": 100.0,
		"target": null,
		"area": Vector3.ZERO,
		"radius": 4500.0,
		"targets": [],
		"flight": null,
	}
	manager.set("_tasks", [task])
	manager.set("_flight_task", {flight: "cap:carrier"})
	manager.set("_scrambling_flight", flight)

	# The flight deliberately has zero members, matching the retrieval/launch
	# window. Its task must remain reserved instead of triggering another flight.
	manager.call("_assign_flights_to_tasks")
	var reservations: Dictionary = manager.get("_flight_task")
	var tasks: Array = manager.get("_tasks")
	var assigned_flight: Variant = (tasks[0] as Dictionary).get("flight")
	if str(reservations.get(flight, "")) != "cap:carrier":
		_fail("pending CAP reservation was discarded")
		return
	if assigned_flight != flight:
		_fail("pending CAP flight was not reattached to its live task")
		return
	if not bool(manager.call("_task_allows_automatic_scramble", {"type": "strike"})):
		_fail("real strike tasks can no longer launch a flight")
		return
	if bool(manager.call("_task_allows_automatic_scramble", {"type": "cap"})):
		_fail("standing CAP still automatically launches at scenario start")
		return

	print("[AirOpsScrambleReservationSmoketest] PASS flight=%s startup_cap=false strike_auto_launch=true" % str(flight.get("flight_name")))
	quit(0)


func _fail(reason: String) -> void:
	push_error("[AirOpsScrambleReservationSmoketest] FAIL %s" % reason)
	quit(1)
