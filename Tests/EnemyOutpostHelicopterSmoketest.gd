extends Node3D

var failures: Array[String] = []
class Terrain extends Node3D:
	var ridge := false
	func get_height(point: Vector3) -> float:
		return 400.0 if ridge and point.z < -300 and point.z > -400 else 0.0
class Contact extends StaticBody3D:
	var team := 1
	# Real surface contacts need not expose an is_destroyed property.
	var health := 1000.0
	func get_team() -> int: return team
	func take_damage(amount: float) -> void: health -= amount

class DestroyedContact extends Contact:
	var is_destroyed := true

class CatapultProbe extends Node:
	var align_calls := 0
	func align_aircraft(_aircraft: RigidBody3D) -> void: align_calls += 1

func _ready() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	EnemyBaseManager.disable_for_heli_test()
	EnemyOpsManager.set_physics_process(false)
	FloatingOrigin.enabled = false
	var terrain := Terrain.new()
	add_child(terrain)
	TerrainReference.terrain_node = terrain
	var base = load("res://Tests/EnemyOutpostSmoketest.gd").TestBase.new()
	add_child(base)
	base.position = Vector3(20000, 0, 20000)
	for i in 6:
		var station := EnemyBaseManager._add_outpost(Vector3(i * 9000, 0, 0), "OP-%02d" % i, 0)
		station.add_vehicle_bay(Vector3(32, 0, 0))
		station.set_physics_process(false)
		EnemyOpsManager._evaluate_outpost_helicopters(base)
	var flights := EnemyOpsManager._get_flights(base)
	check(flights.size() == 6, "one section per outpost")
	for flight: EnemyVirtualFlight in flights:
		check(flight.aircraft_count in [2, 3], "section has two or three aircraft")
		check_mixed_section(flight)
		check(flight.role != EnemyVirtualFlight.AircraftRole.FIGHTER, "helicopters are not interceptors")
		check(flight.home_position.distance_to(base.position) > 10000, "outpost home is separate from airfield")
	check(EnemyOpsManager._count_deployed_aircraft(base) == 0, "helicopters do not consume fixed-wing quota")
	EnemyOpsManager._evaluate_outpost_helicopters(base)
	check(EnemyOpsManager._get_flights(base).size() == 6, "no duplicate sections")
	var lost_section: EnemyVirtualFlight = flights[5]
	lost_section.aircraft_count = 0
	EnemyOpsManager._clean_flights(base)
	EnemyOpsManager._evaluate_outpost_helicopters(base)
	check(EnemyOpsManager._get_flights(base).size() == 5, "lost section waits for replacement cooldown")
	EnemyBaseManager.outposts[5].helicopter_cooldown_s = 0
	EnemyOpsManager._evaluate_outpost_helicopters(base)
	check(EnemyOpsManager._get_flights(base).size() == 6, "intact outpost replaces lost section after cooldown")
	for flight in EnemyOpsManager._get_flights(base): check_mixed_section(flight)
	var section: EnemyVirtualFlight = flights[0]
	EnemyOpsManager.receive_intel("test", "air", section.home_position, 1)
	EnemyOpsManager._assess_threats()
	check(section.mission == EnemyVirtualFlight.Mission.PATROL, "air contact does not divert helicopter")
	EnemyOpsManager.receive_intel("test", "ground", section.home_position + Vector3(500, 0, 0), 1)
	EnemyOpsManager._assess_threats()
	check(section.mission == EnemyVirtualFlight.Mission.INVESTIGATE, "local ground intel sends helicopter section")
	EnemyOpsManager._known_contacts.clear()
	EnemyOpsManager._assess_threats()
	check(section.mission == EnemyVirtualFlight.Mission.PATROL, "expired intel returns patrol")
	section.position = Vector3(0, 140, 0)
	section.heading = Vector3.FORWARD
	section._begin_materialize()
	for i in section.aircraft_count:
		section._tick_materialize_step()
		await get_tree().process_frame
	check(section.vstate == EnemyVirtualFlight.VState.ACTIVE, "section materializes actual helicopters")
	var carrier := Contact.new()
	carrier.add_to_group("carrier")
	add_child(carrier)
	carrier.position = Vector3(0, 0, -700)
	var air := Contact.new()
	air.add_to_group("aircraft")
	add_child(air)
	air.position = Vector3(0, 140, -300)
	var ground := Contact.new()
	ground.add_to_group("ground_vehicles")
	add_child(ground)
	ground.position = Vector3(50, 0, -650)
	# Attach after insertion to avoid starting the full deck scenario fixture.
	var deck := Node.new()
	add_child(deck)
	deck.set_script(load("res://LandCarrier/FlightDeckManager.gd"))
	var catapult := CatapultProbe.new()
	add_child(catapult)
	deck.catapult = catapult
	var materialized_models: Array[String] = []
	for ac in section.active_aircraft:
		materialized_models.append(ac.scene_file_path)
		var pilot := ac.get_node("HelicopterPilot") as HelicopterPilot
		check(ac.get_team() == 2 and pilot.is_physics_processing(), "hostile helicopter pilot running")
		check(pilot.outpost_patrol_mode and not pilot._outpost_route.is_empty(), "physical section follows outpost route")
		check(pilot._is_valid_combat_target(carrier) and pilot._is_valid_combat_target(ground), "carrier and ground units eligible")
		check(not pilot._is_valid_combat_target(air), "aircraft excluded from attack targets")
		check(not pilot._get_combat_weapon_options().is_empty(), "authored rocket weapon is usable")
		check(pilot.engine.is_engine_working and pilot.engine.current_power > 0.3, "airborne materialization has immediate rotor lift")
		var fixed_pilot := ac.get_node("AIPilot") as AIPilot
		fixed_pilot.launch()
		check(not fixed_pilot.is_physics_processing(), "legacy fixed-wing launch cannot activate on helicopter")
		fixed_pilot.initialize(ac)
		check(not fixed_pilot.is_physics_processing() and fixed_pilot.simple_aero == null, "fixed-wing initialization rejects helicopter flight model")
		check(pilot.is_physics_processing(), "rejected fixed-wing launch preserves helicopter pilot")
		check(not deck._can_service_aircraft(ac), "carrier does not service enemy aircraft")
		ac.set_meta("arresting_engaged", true)
		check(deck._find_arrested_aircraft() == null, "carrier recovery ignores arrested enemy aircraft")
		ac.remove_meta("arresting_engaged")
		deck.start_post_arrest_recovery(ac)
		deck.request_launch_sequence(ac)
		deck._begin_parallel_catapult_launch(ac, catapult)
		check(not ac.get_meta("controls_disabled", false), "rejected enemy deck requests do not take controls")
		ac.team = 1
		ac.remove_from_group("enemies")
		check(deck._can_service_aircraft(ac), "friendly helicopter remains eligible for deck service")
		deck.request_launch_sequence(ac)
		deck._begin_parallel_catapult_launch(ac, catapult)
		check(catapult.align_calls == 0 and not ac.get_meta("controls_disabled", false), "helicopters never enter either catapult launch path")
		ac.team = 2
		ac.add_to_group("enemies")
		pilot.set_physics_process(false)
		ac.freeze = true
	check(materialized_models.has("res://Aircraft/Aircraft_13.tscn") and materialized_models.has("res://Aircraft/Aircraft_15.tscn"), "both helicopter models materialize in the patrol")
	section._scan_for_contacts(true)
	section._process_pending_reports(0.1)
	check(EnemyOpsManager._get_contact("carrier").is_empty(), "materialized helicopter preserves carrier reporting delay")
	section._process_pending_reports(15.0)
	check(not EnemyOpsManager._get_contact("carrier").is_empty() and EnemyOpsManager._get_contact("air").is_empty(), "helicopter reports surface contacts only")
	check(not EnemyOpsManager._get_contact("ground").is_empty(), "ground unit without optional destroyed flag is reported")
	carrier.remove_from_group("carrier")
	ground.remove_from_group("ground_vehicles")
	var wreck := DestroyedContact.new()
	add_child(wreck)
	wreck.add_to_group("ground_vehicles")
	wreck.position = ground.position
	EnemyOpsManager._known_contacts.clear()
	section._scan_for_contacts(true)
	section._process_pending_reports(0.1)
	check(EnemyOpsManager._get_contact("ground").is_empty(), "destroyed surface units remain excluded")
	wreck.remove_from_group("ground_vehicles")
	wreck.queue_free()
	carrier.add_to_group("carrier")
	ground.add_to_group("ground_vehicles")
	EnemyOpsManager._known_contacts.clear()
	terrain.ridge = true
	section._scan_for_contacts(true)
	section._process_pending_reports(0.1)
	check(EnemyOpsManager._get_contact("carrier").is_empty() and EnemyOpsManager._get_contact("ground").is_empty(), "terrain blocks helicopter reports")
	terrain.ridge = false
	section.active_aircraft[0].current_health = 43.0
	section.dematerialize()
	await get_tree().process_frame
	var saved_models: Array[String] = []
	for scene in section._aircraft_slots: saved_models.append(scene.resource_path)
	var saved: Dictionary = SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(SaveGameManager._encode_json_value(EnemyOpsManager.capture_save_state()))))
	var restored_bases: Array[EnemyBase] = [base]
	check(EnemyOpsManager.restore_save_state(saved, restored_bases), "manager restores helicopter sections")
	await get_tree().process_frame
	section = EnemyOpsManager._get_flights(base)[0]
	check_mixed_section(section)
	var restored_models: Array[String] = []
	for scene in section._aircraft_slots: restored_models.append(scene.resource_path)
	check(restored_models == saved_models, "save/load retains exact helicopter mix and slot order")
	check(section.get_script().resource_path.ends_with("EnemyOutpostHelicopterFlight.gd") and section.outpost_id == "OP-00", "restore retains helicopter behavior and ownership")
	section._begin_materialize()
	for i in section.aircraft_count:
		section._tick_materialize_step()
		await get_tree().process_frame
	check(is_equal_approx(section.active_aircraft[0].current_health, 43.0), "damage survives virtualization and save/load")
	var station := EnemyBaseManager.outposts[0]
	station.get_node("VehicleBay").set_destroyed_state()
	check(section.aircraft_count >= 2, "bay loss preserves airborne survivors")
	section.dematerialize()
	section.aircraft_count = 0
	EnemyOpsManager._clean_flights(base)
	station.helicopter_cooldown_s = 0
	EnemyOpsManager._evaluate_outpost_helicopters(base)
	check(EnemyOpsManager._get_flights(base).size() == 5, "destroyed bay cannot replace flight")
	print("ENEMY_OUTPOST_HELICOPTER_", "PASS" if failures.is_empty() else "FAIL", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func check_mixed_section(flight: EnemyVirtualFlight) -> void:
	var models: Array[String] = []
	for scene in flight._aircraft_slots: models.append(scene.resource_path)
	check(models.has("res://Aircraft/Aircraft_13.tscn") and models.has("res://Aircraft/Aircraft_15.tscn"), "section includes Aircraft 13 and Aircraft 15")
	check(models.all(func(path): return path in ["res://Aircraft/Aircraft_13.tscn", "res://Aircraft/Aircraft_15.tscn"]), "outpost section only uses the two enemy helicopter models")
