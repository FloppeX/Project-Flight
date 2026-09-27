extends Node

class TestAircraft:
	extends RigidBody3D
	var current_health := 100.0
	var max_health := 100.0
	func get_team() -> int: return 1

class TestHardpoint:
	extends Node
	var weapon_instance: Weapon

class TestPilot:
	extends AIPilot
	var fuel_fraction := 1.0
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _process(_delta: float) -> void: pass
	func _get_energy_fraction(_kind: String) -> float: return fuel_fraction
	func start_recovery() -> bool:
		current_state = State.RTB
		return true
	func assign_air_task(task: Variant) -> bool:
		current_air_task = task
		match task.kind:
			2: current_state = State.ATTACK_POSITIONING
			3: current_state = State.DOGFIGHT
			4, 5: current_state = State.RTB
			_: current_state = State.SEARCH
		return true

var errors: Array[String] = []
var manager: Node
var scene: Node3D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	manager = get_tree().root.get_node("AirOpsManager")
	manager.mission_tasking_enabled = false
	manager.set_process(false)
	manager.auto_scramble_for_intercept_tasks = false
	manager.auto_scramble_for_strike_tasks = false
	get_tree().root.get_node("GroundOpsManager").set_process(false)
	get_tree().root.get_node("OperationsCoordinator").set_process(false)
	scene = Node3D.new()
	get_tree().root.add_child(scene)
	var carrier := Node3D.new()
	carrier.add_to_group("carrier")
	scene.add_child(carrier)
	manager._carrier = carrier
	var flights: Array = manager.flights
	for flight: Flight in flights:
		flight.set_physics_process(false)
	var striker: Flight = flights[0]
	var relief: Flight = flights[1]
	var attacker := _aircraft(striker, Vector3(100, 800, 100))
	var wingman := _aircraft(striker, Vector3(150, 800, 150))
	var pilot := attacker.find_child("AIPilot", true, false) as TestPilot
	var wingpilot := wingman.find_child("AIPilot", true, false) as TestPilot
	var bandit := Node3D.new()
	scene.add_child(bandit)
	var strike := _task("strike:1", "strike", 300.0)
	var intercept := _task("intercept:1", "intercept", 2000.0)
	intercept.target = bandit
	intercept.targets = [bandit]
	manager._tasks = [strike]
	manager._apply_task_to_flight(strike, striker, true)
	manager._tasks = [intercept, strike]
	pilot.current_state = AIPilot.State.ATTACK_BREAK_OFF
	manager._assign_flights_to_tasks()
	_check(striker.mission == Flight.Mission.CAS, "committed pull-out protected from diversion")
	pilot.current_state = AIPilot.State.SEARCH
	manager._assign_flights_to_tasks()
	_check(striker.mission == Flight.Mission.INTERCEPT, "urgent intercept diverts strike flight")
	_check(strike.flight == null and intercept.flight == striker, "one reservation after diversion")
	var replacement := _aircraft(relief, Vector3(500, 800, 500))
	var replacement_pilot := replacement.find_child("AIPilot", true, false) as TestPilot
	# Returning wingman must not receive the replacement mission.
	wingpilot.current_state = AIPilot.State.RTB
	pilot.fuel_fraction = 0.001
	manager._supervise_flight_readiness()
	_check(pilot.current_state == AIPilot.State.RTB, "low fuel recalls aircraft")
	manager._assign_flights_to_tasks()
	_check(intercept.flight == relief, "returning flight releases task to replacement")
	_check(pilot.current_state == AIPilot.State.RTB and wingpilot.current_state == AIPilot.State.RTB, "recovery never interrupted")
	var returning: Dictionary = manager.get_flight_status(striker.flight_name)
	_check(returning.phase == "RETURNING" and returning.ready_count == 0, "actual return status reconciled")
	manager.order_cap(relief.flight_name)
	_check(not manager._flight_task.has(relief), "manual order clears automatic reservation")
	manager._assign_flights_to_tasks()
	_check(relief.mission == Flight.Mission.CAP and intercept.flight == null, "automatic tasking respects player order")
	manager.release_to_automatic(relief.flight_name)
	manager._assign_flights_to_tasks()
	_check(intercept.flight == relief, "release to AirOps permits reassignment")
	# No live targets: obsolete intercept must become patrol.
	manager._tasks = []
	manager._assign_flights_to_tasks()
	_check(relief.mission == Flight.Mission.CAP, "finished mission returns to patrol")
	var coordinator := get_tree().root.get_node("OperationsCoordinator")
	var direct := OpsOrder.attack_target(bandit)
	_check(coordinator.issue_order(replacement_pilot, direct), "individual order accepted")
	manager._tasks = [intercept]
	manager._assign_flights_to_tasks()
	_check(intercept.flight == null, "individual task cannot be stolen by flight allocator")
	_check(coordinator.get_unit_status(replacement_pilot).get("order") == direct, "pilot and aircraft share order record")
	manager.order_rtb(relief.flight_name)
	_check(not coordinator.has_individual_order(replacement), "flight recall supersedes individual task")
	_check(replacement_pilot.current_state == AIPilot.State.RTB, "flight recall reaches individually tasked member")
	replacement_pilot.current_state = AIPilot.State.SEARCH
	_check(coordinator.issue_order(replacement, direct), "individual order can be assigned again")
	manager.release_to_automatic(relief.flight_name)
	_check(not coordinator.has_individual_order(replacement), "release clears individual ownership")
	replacement_pilot.current_state = AIPilot.State.RECOVERY_HOLD
	_check(not coordinator.issue_order(replacement, direct), "coordinator protects landing queue")
	replacement_pilot.current_state = AIPilot.State.SEARCH
	var weapon: Weapon = replacement_pilot.cached_hardpoints[0].weapon_instance
	weapon.weapon_name = "Bomb"
	var armed: Dictionary = manager.Readiness.aircraft_status(replacement)
	_check(not manager.Readiness.can_fill(armed, "intercept") and manager.Readiness.can_fill(armed, "strike"), "loadout suitability")
	weapon.ammo_count = 0
	manager._supervise_flight_readiness()
	_check(replacement_pilot.current_state == AIPilot.State.RTB, "weapons exhausted recalls aircraft")
	manager.order_rtb(relief.flight_name)
	var saved := relief.capture_mission_save_state()
	relief.mission_source = "automatic"
	relief.restore_mission_save_state(saved, carrier)
	_check(relief.mission_source == "player", "order ownership survives checkpoint")
	var ground := get_tree().root.get_node("GroundOpsManager")
	var platoon: GroundVehiclePlatoon = ground.get_platoon("Ember")
	ground.order_hold("Ember")
	_check(not ground.is_automatically_available(platoon), "explicit ground hold protected from rescue and escort")
	_check(coordinator.get_unit_status(platoon).order_source == "player", "ground order visible to coordinator")
	# Queued empty platoon must not be reported as recovered or stalled.
	coordinator._simulation_elapsed_s = 1000.0
	coordinator._supervise_assignments()
	_check(coordinator.get_unit_status(platoon).has("order"), "empty ordered platoon remains pending")
	_check(not coordinator.get_unit_status(platoon).order_stalled, "pending deployment not reported stalled")
	ground.release_to_automatic("Ember")
	_check(ground.is_automatically_available(platoon), "ground release restores automatic availability")
	var ground_member := Node3D.new()
	scene.add_child(ground_member)
	platoon.register_vehicle(ground_member)
	platoon.set_physics_process(false)
	platoon.set_move_objective(Vector3(1000, 0, 0))
	ground._record_order(platoon, OpsOrder.transit_to_position(Vector3(1000, 0, 0)))
	coordinator._simulation_elapsed_s += 1000.0
	coordinator._supervise_assignments()
	_check(coordinator.get_unit_status(platoon).order_stalled, "ground stalled movement detected")
	platoon.objective_type = GroundVehiclePlatoon.ObjectiveType.NONE
	coordinator._supervise_assignments()
	_check(not coordinator.get_unit_status(platoon).has("order"), "obsolete ground order removed")
	ground.order_hold("Ember")
	coordinator._simulation_elapsed_s += 1000.0
	coordinator._supervise_assignments()
	_check(not coordinator.get_unit_status(platoon).order_stalled, "standing hold does not falsely stall")
	platoon.unregister_vehicle(ground_member)
	var ground_saved: Dictionary = ground._capture_platoon_objective(platoon)
	platoon.set_meta("ops_order_source", "automatic")
	ground._restore_platoon_objective(platoon, ground_saved)
	_check(platoon.get_meta("ops_order_source") == "player", "ground order ownership survives checkpoint")
	_check(coordinator.get_unit_status(platoon).has("order"), "restored ground order resumes supervision")
	_check(coordinator.get_all_statuses().size() >= 8, "shared overview includes flights and platoons")
	var map := get_tree().root.get_node("WorldMapOverlay")
	map._selected_asset_kind = 1
	map._selected_asset_name = striker.flight_name
	var specs: Array = map._get_selected_mission_specs()
	_check(specs.any(func(spec): return spec.id == "RTB"), "flight recall available on tactical map")
	_check(specs.any(func(spec): return spec.id == "AUTO"), "release to AirOps available on tactical map")
	if "--render" in OS.get_cmdline_user_args():
		get_tree().root.get_node("CarrierConsole").show_page("air_wing")
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://captures/operations_mission_status.png")
	for error in errors: push_error(error)
	print("[OperationsMissionManagementSmoketest] %s diversion+replacement+recall+ownership+readiness+ground+save" % ("PASS" if errors.is_empty() else "FAIL"))
	get_tree().quit(0 if errors.is_empty() else 1)

func _aircraft(flight: Flight, at: Vector3) -> TestAircraft:
	var aircraft := TestAircraft.new()
	aircraft.position = at
	scene.add_child(aircraft)
	var pilot := TestPilot.new()
	pilot.name = "AIPilot"
	aircraft.add_child(pilot)
	pilot.aircraft = aircraft
	pilot.current_state = AIPilot.State.SEARCH
	var hp := TestHardpoint.new()
	aircraft.add_child(hp)
	var weapon := Weapon.new()
	weapon.weapon_name = "Autocannon"
	weapon.ammo_count = 100
	hp.add_child(weapon)
	hp.weapon_instance = weapon
	pilot.cached_hardpoints = [hp]
	flight.register(aircraft)
	return aircraft

func _task(id: String, kind: String, priority: float) -> Dictionary:
	return {"id": id, "type": kind, "priority": priority, "area": Vector3(100, 800, 100),
		"radius": 1200.0, "target": null, "targets": [], "flight": null}

func _check(passed: bool, message: String) -> void:
	if not passed: errors.append(message)


