extends SceneTree


class FakeHelicopterPilot:
	extends Node

	var aircraft: Node3D = null
	var mission_phase: int = 3
	var _rescue_target: Node3D = null
	var passenger_capacity: int = 3
	var passenger_count: int = 0

	func command_rescue(pilot_node: Node3D) -> void:
		_rescue_target = pilot_node
		mission_phase = 4

	func can_accept_passenger() -> bool:
		return passenger_count < passenger_capacity

	func add_passenger(_pilot_node: Node3D) -> bool:
		if not can_accept_passenger():
			return false
		passenger_count += 1
		_rescue_target = null
		return true

	func finish_rescue_pickups() -> void:
		if mission_phase == 4 and _rescue_target == null:
			mission_phase = 2


class FakeFlightDeckManager:
	extends Node

	var requested_count: int = 0
	var requested_ops: Node = null
	var requested_model: String = ""

	func can_queue_ai_helicopters(_aircraft_model: String = "") -> bool:
		return true

	func queue_ai_helicopters(count: int, ops: Node, aircraft_model: String = "") -> int:
		requested_count = count
		requested_ops = ops
		requested_model = aircraft_model
		return count


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var air_ops := root.get_node_or_null("AirOpsManager")
	if air_ops == null:
		_fail("AirOpsManager autoload is unavailable")
		return
	air_ops.set("mission_tasking_enabled", false)
	air_ops.set("_downed_pilots", [])
	air_ops.set("_rescue_assignments", {})
	air_ops.set("_pending_rescue_launch_pilot", null)

	var first_pilot := _make_downed_pilot("DownedOne", "Rook 1")
	var first_helicopter := _make_rescue_helicopter("Aircraft_11_RescueOne", true)
	var first_helicopter_pilot := first_helicopter.get_node("HelicopterPilot") as FakeHelicopterPilot
	air_ops.call("request_rescue_for", first_pilot)
	if first_helicopter_pilot._rescue_target != first_pilot:
		_fail("available Aircraft_11 was not assigned to the downed pilot")
		return
	var snapshot: Array = air_ops.call("get_downed_pilot_snapshot")
	if snapshot.size() != 1 or str((snapshot[0] as Dictionary).get("status", "")) != "assigned":
		_fail("Air Ops did not expose the assigned pilot on its rescue board")
		return

	air_ops.call("notify_pilot_rescued", first_pilot, first_helicopter)
	if not (air_ops.call("get_tracked_downed_pilots") as Array).is_empty():
		_fail("rescued pilot remained on the Air Ops rescue board")
		return
	first_pilot.queue_free()
	first_helicopter.queue_free()
	await process_frame

	# A destroyed rescue helicopter can remain in the assignment dictionary until
	# the next dispatch tick. The stale value must be pruned before any typed cast.
	var stale_pilot := _make_downed_pilot("DownedStaleAssignment", "Rook Stale")
	var stale_helicopter := _make_rescue_helicopter("Aircraft_11_StaleAssignment", true)
	air_ops.call("request_rescue_for", stale_pilot)
	stale_helicopter.free()
	air_ops.call("_update_rescue_operations")
	var stale_assignments: Dictionary = air_ops.get("_rescue_assignments")
	if stale_assignments.has(stale_pilot) \
			or str(stale_pilot.get_meta("air_ops_rescue_status", "")) != "waiting":
		_fail("freed rescue helicopter assignment was not safely pruned")
		return
	air_ops.call("notify_pilot_rescued", stale_pilot)
	stale_pilot.queue_free()
	await process_frame

	# A request made with no live helicopter must remain tracked and be retried
	# when an AI rescue helicopter later becomes available.
	var waiting_pilot := _make_downed_pilot("DownedTwo", "Rook 2")
	air_ops.call("request_rescue_for", waiting_pilot)
	if (air_ops.call("get_tracked_downed_pilots") as Array).size() != 1:
		_fail("pilot was dropped when no helicopter was immediately available")
		return
	var later_helicopter := _make_rescue_helicopter("Aircraft_11_RescueTwo", true)
	var later_helicopter_pilot := later_helicopter.get_node("HelicopterPilot") as FakeHelicopterPilot
	air_ops.call("_update_rescue_operations")
	if later_helicopter_pilot._rescue_target != waiting_pilot:
		_fail("Air Ops did not retry the waiting rescue task")
		return
	air_ops.call("notify_pilot_rescued", waiting_pilot, later_helicopter)
	waiting_pilot.queue_free()
	later_helicopter.queue_free()
	await process_frame

	# FlightDeckManager reports a helicopter after retrieval. That callback must
	# consume the pending rescue target rather than trying to form a combat flight.
	var flight_deck_manager := FakeFlightDeckManager.new()
	flight_deck_manager.name = "FakeFlightDeckManager"
	root.add_child(flight_deck_manager)
	flight_deck_manager.add_to_group("flight_deck_manager")
	var launch_target := _make_downed_pilot("DownedThree", "Rook 3")
	air_ops.call("request_rescue_for", launch_target)
	if flight_deck_manager.requested_count != 1 \
			or flight_deck_manager.requested_ops != air_ops \
			or flight_deck_manager.requested_model != "Aircraft_11":
		_fail("Air Ops did not queue an Aircraft_11 through FlightDeckManager")
		return
	if air_ops.get("_pending_rescue_launch_pilot") != launch_target \
			or str(launch_target.get_meta("air_ops_rescue_status", "")) != "launching":
		_fail("queued hangar rescue was not kept as a pending Air Ops task")
		return
	var launched_helicopter := _make_rescue_helicopter("Aircraft_11_Launched", false)
	var launched_helicopter_pilot := launched_helicopter.get_node("HelicopterPilot") as FakeHelicopterPilot
	air_ops.call("notify_aircraft_launched", launched_helicopter_pilot)
	if launched_helicopter_pilot._rescue_target != launch_target:
		_fail("retrieved Aircraft_11 did not receive its pending rescue target")
		return
	if air_ops.get("_pending_rescue_launch_pilot") != null:
		_fail("pending rescue launch was not cleared after assignment")
		return
	air_ops.call("notify_pilot_rescued", launch_target, launched_helicopter)
	launch_target.queue_free()
	launched_helicopter.queue_free()
	flight_deck_manager.queue_free()
	await process_frame

	if not _verify_parked_helicopter_departure():
		return
	await process_frame

	if not _verify_starting_helicopter_inventory():
		return
	await process_frame

	if not _verify_multi_passenger_retasking(air_ops):
		return

	print("[AirOpsRescueSmoketest] PASS tracked=true freed_helicopter_pruned=true retry=true callback=true parked_takeoff=true Aircraft_11_start=3 multi_pickup=3")
	quit(0)


func _make_downed_pilot(node_name: String, callsign: String) -> Node3D:
	var pilot := Node3D.new()
	pilot.name = node_name
	pilot.set_meta("pilot_callsign", callsign)
	root.add_child(pilot)
	return pilot


func _make_rescue_helicopter(node_name: String, join_ai_groups: bool) -> Node3D:
	var helicopter := Node3D.new()
	helicopter.name = node_name
	helicopter.set_meta("is_helicopter", true)
	root.add_child(helicopter)
	if join_ai_groups:
		helicopter.add_to_group("friendlies")
		helicopter.add_to_group("ai_aircraft")
	var helicopter_pilot := FakeHelicopterPilot.new()
	helicopter_pilot.name = "HelicopterPilot"
	helicopter_pilot.aircraft = helicopter
	helicopter.add_child(helicopter_pilot)
	return helicopter


func _verify_parked_helicopter_departure() -> bool:
	var helicopter_pilot_script := load("res://AI/HelicopterPilot.gd") as Script
	if helicopter_pilot_script == null:
		_fail("HelicopterPilot script could not be loaded")
		return false
	var carrier := Node3D.new()
	carrier.name = "RescueTestCarrier"
	root.add_child(carrier)
	carrier.add_to_group("carrier")
	var helicopter := RigidBody3D.new()
	helicopter.name = "ParkedAircraft_11"
	helicopter.freeze = true
	helicopter.set_meta("parking_brake", true)
	root.add_child(helicopter)
	var helicopter_pilot: Node = helicopter_pilot_script.new() as Node
	helicopter_pilot.name = "HelicopterPilot"
	helicopter.add_child(helicopter_pilot)
	helicopter_pilot.set("aircraft", helicopter)
	helicopter_pilot.set("state", 0) # HelicopterPilot.State.IDLE
	helicopter_pilot.set("mission_phase", 3) # HelicopterPilot.MissionPhase.AT_CARRIER
	var rescue_target := Node3D.new()
	rescue_target.name = "ParkedDepartureTarget"
	root.add_child(rescue_target)
	rescue_target.global_position = Vector3(500.0, 0.0, 200.0)
	helicopter_pilot.call("command_rescue", rescue_target)
	var departed := int(helicopter_pilot.get("state")) == 1 \
			and int(helicopter_pilot.get("mission_phase")) == 4 \
			and not helicopter.freeze \
			and not bool(helicopter.get_meta("parking_brake", false))
	helicopter.queue_free()
	rescue_target.queue_free()
	carrier.queue_free()
	if not departed:
		_fail("parked rescue helicopter did not release its carrier hold for takeoff")
		return false
	return true


func _verify_starting_helicopter_inventory() -> bool:
	# Load dynamically so this standalone --script test does not resolve these
	# global classes before the project's autoload singletons have initialized.
	var carrier_manager_script := load("res://LandCarrier/CarrierManager.gd") as Script
	var flight_deck_manager_script := load("res://LandCarrier/FlightDeckManager.gd") as Script
	if carrier_manager_script == null or flight_deck_manager_script == null:
		_fail("carrier inventory scripts could not be loaded")
		return false
	var carrier_manager: Node = carrier_manager_script.new() as Node
	var flight_deck_manager: Node = flight_deck_manager_script.new() as Node
	flight_deck_manager.set("carrier_manager", carrier_manager)
	flight_deck_manager.call("_initialize_hangar_with_aircraft")
	var stored_aircraft: Array = flight_deck_manager.get("stored_aircraft")
	var utility_count := 0
	for stored_variant in stored_aircraft:
		if stored_variant is Dictionary \
				and str((stored_variant as Dictionary).get("name", "")).begins_with("Aircraft_11"):
			utility_count += 1
	if utility_count != 3:
		flight_deck_manager.free()
		carrier_manager.free()
		_fail("expected 3 starting Aircraft_11 helicopters, got %d" % utility_count)
		return false
	if stored_aircraft.size() != int(flight_deck_manager.get("max_hangar_capacity")):
		flight_deck_manager.free()
		carrier_manager.free()
		_fail("starting helicopter inventory did not preserve total hangar capacity")
		return false
	if not bool(flight_deck_manager.call("can_queue_ai_helicopters", "Aircraft_11")):
		flight_deck_manager.free()
		carrier_manager.free()
		_fail("idle deck did not report its stored Aircraft_11 as launchable")
		return false
	flight_deck_manager.set("_pending_flight_ops", carrier_manager)
	if bool(flight_deck_manager.call("can_queue_ai_helicopters", "Aircraft_11")):
		flight_deck_manager.free()
		carrier_manager.free()
		_fail("rescue launch could overwrite an existing deck launch request")
		return false
	flight_deck_manager.free()
	carrier_manager.free()
	return true


func _verify_multi_passenger_retasking(air_ops: Node) -> bool:
	air_ops.set("_downed_pilots", [])
	air_ops.set("_rescue_assignments", {})
	air_ops.set("_pending_rescue_launch_pilot", null)
	var helicopter := _make_rescue_helicopter("Aircraft_11_MultiRescue", true)
	var helicopter_pilot := helicopter.get_node("HelicopterPilot") as FakeHelicopterPilot
	var pilots: Array[Node3D] = []
	for index in range(3):
		var pilot := _make_downed_pilot("MultiDowned%d" % (index + 1), "Mako %d" % (index + 1))
		pilots.append(pilot)
		air_ops.call("request_rescue_for", pilot)
	if helicopter_pilot._rescue_target != pilots[0]:
		_fail("multi-passenger rescue did not begin with the first survivor")
		return false
	for index in range(3):
		var pilot := pilots[index]
		if not helicopter_pilot.add_passenger(pilot):
			_fail("multi-passenger helicopter rejected survivor %d" % (index + 1))
			return false
		air_ops.call("notify_pilot_rescued", pilot, helicopter)
		if index < 2 and helicopter_pilot._rescue_target != pilots[index + 1]:
			_fail("multi-passenger helicopter was not retasked to survivor %d" % (index + 2))
			return false
	if helicopter_pilot.passenger_count != 3 or helicopter_pilot.mission_phase != 2:
		_fail("full rescue helicopter did not return inbound after three pickups")
		return false
	for pilot in pilots:
		pilot.queue_free()
	helicopter.queue_free()
	return true


func _fail(reason: String) -> void:
	push_error("[AirOpsRescueSmoketest] FAIL %s" % reason)
	quit(1)
