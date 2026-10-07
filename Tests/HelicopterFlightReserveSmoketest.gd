extends Node3D

const DECK = preload("res://LandCarrier/FlightDeckManager.gd")
const MANAGER = preload("res://LandCarrier/CarrierManager.gd")

class TestDeck extends DECK:
	func _ready() -> void: add_to_group("flight_deck_manager")
	func _physics_process(_delta: float) -> void: pass
	func _launch_next_queued_ai() -> void: pass

class TestAircraft extends RigidBody3D:
	var current_health := 100.0
	var max_health := 100.0
	func get_team() -> int: return 1

class TestHelicopterPilot extends HelicopterPilot:
	var guns := 0
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _process(_delta: float) -> void: pass
	func get_operational_resources() -> Dictionary:
		return {"fuel": 1.0, "health": 1.0, "guns": guns, "rockets": 0, "bombs": 0, "weapons_known": true}

class TestTarget extends Node3D:
	var current_health := 100.0
	func get_team() -> int: return 2

var failures: Array[String] = []

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--render-reserve"):
		get_node("/root/PauseMenu").set("_display_mode_index", 0)
		get_node("/root/PauseMenu").set("_resolution_index", 1)
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	var ops := get_node("/root/AirOpsManager")
	ops.set_process(false)
	ops.mission_tasking_enabled = false
	ops.maintain_carrier_cap = false
	var assembly: Node = ops.assembly
	assembly.set_process(false)
	assembly.plans.clear()
	for flight in ops.flights: flight.set_physics_process(false)
	var carrier := Node3D.new()
	carrier.add_to_group("carrier")
	add_child(carrier)
	var manager := MANAGER.new()
	carrier.add_child(manager)
	var deck := TestDeck.new()
	carrier.add_child(deck)
	deck.carrier_manager = manager
	deck.current_state = DECK.DeckState.IDLE
	deck.stored_aircraft.assign([_entry("reserve", 11), _entry("utility", 11), _entry("armed", 9)])
	var reserve: Dictionary = assembly.get_rescue_reserve()
	check(reserve.id == "reserve", "one utility helicopter selected for rescue")
	check(not assembly.assign("reserve", "Archer").is_empty(), "reserve cannot be assigned to a regular flight")
	check(assembly.assign("utility", "Archer").is_empty(), "second utility helicopter can join a flight")
	check(assembly.model_info("res://Aircraft/Aircraft_11.tscn").presets.has(assembly.plan("Archer").loadout), "utility aircraft uses a supported loadout")
	check(assembly.assign("armed", "Bulldog").is_empty(), "armed helicopter can join another flight")
	assembly.auto_assign_pilots("Archer")
	assembly.auto_assign_pilots("Bulldog")
	assembly.set_hold("Archer", false)
	assembly.set_hold("Bulldog", false)
	check(assembly.can_launch("Archer") and assembly.can_launch("Bulldog"), "helicopter compositions become launch ready")
	if OS.get_cmdline_user_args().has("--render-reserve"):
		get_tree().root.size = Vector2i(1600, 900)
		get_node("/root/CarrierConsole").show_page("air_wing", true)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://logs/helicopter_single_reserve.png")
		get_node("/root/CarrierConsole").set_open(false)
	var ids: Array[String] = ["utility"]
	check(deck.queue_ai_flight(1, ops, "", "res://Aircraft/Aircraft_11.tscn", ids) == 1, "exact helicopter accepted by flight launch queue")
	check(deck._pending_ai_aircraft_kind == "helicopter", "helicopter takes vertical launch path")
	check(deck.stored_aircraft[deck._select_hangar_launch_index()].metadata.airframe_id == "utility", "regular launch leaves rescue airframe in hangar")
	deck._finish_pending_ai_launch_request()
	var utility := _helicopter("utility", 11, 0)
	utility.set_meta("assembly_flight", "Archer")
	var utility_pilot := utility.get_node("HelicopterPilot") as TestHelicopterPilot
	var archer: Flight = ops.get_flight("Archer")
	ops._scrambling_flight = archer
	ops._scrambling_expected_count = 1
	ops.notify_aircraft_launched(utility_pilot)
	check(ops.get_flight_of(utility) == archer and ops._scrambling_flight == null, "utility helicopter registers and completes flight scramble")
	var route: Array[Vector3] = [Vector3(1000, 200, 0), Vector3(0, 200, 1000)]
	ops.order_patrol("Archer", route, "ground", 200.0)
	archer._apply_pending_mission_updates()
	check(utility_pilot.outpost_patrol_mode and utility_pilot._outpost_route.size() == 2, "patrol reaches helicopter route controller")
	check(archer.get_lead_state_name() == "LOW_LEVEL_TRANSIT" and archer.get_active_waypoints().size() > 0, "helicopter state and navigation are visible")
	check(archer.get_campaign_save_blocker().is_empty(), "ordinary helicopter patrol supports campaign checkpoint")
	var survivor := Node3D.new()
	add_child(survivor)
	ops._queue_rescue_helicopter(survivor)
	check(deck._pending_ai_airframe_ids == ["reserve"], "rescue queues the reserved individual")
	deck._finish_pending_ai_launch_request()
	ops._pending_rescue_launch_pilot = null
	check(ops._find_available_rescue_helicopter() == null, "rescue does not steal the patrol helicopter")
	var rescue := _helicopter("reserve", 11, 0)
	deck.stored_aircraft.remove_at(0)
	var updated: Dictionary = assembly.get_rescue_reserve()
	check(updated.id == "reserve", "reserve stays with deployed rescue aircraft")
	check(ops._find_available_rescue_helicopter() == rescue, "reserved helicopter remains available for rescue")
	var attacker := _helicopter("armed", 9, 20)
	attacker.set_meta("assembly_flight", "Bulldog")
	var attacker_pilot := attacker.get_node("HelicopterPilot") as TestHelicopterPilot
	var station := Hardpoint.new()
	station.mounted_weapon = load("res://Weapons/Guns/Hardpoint/15mm_machine_gun_hardpoint.tscn")
	attacker.add_child(station)
	var resource_pilot := HelicopterPilot.new()
	resource_pilot.aircraft = attacker
	check(int(resource_pilot.get_operational_resources().guns) > 0, "real helicopter resource report sees mounted gun ammunition")
	resource_pilot.free()
	var bulldog: Flight = ops.get_flight("Bulldog")
	ops.reassign(attacker, "Bulldog")
	var target := TestTarget.new()
	target.add_to_group("ground_vehicles")
	target.add_to_group("enemies")
	add_child(target)
	target.position = Vector3(1500, 0, 0)
	ops.report_contact(utility, target)
	check(ops.order_attack("Bulldog", target.position, 100.0), "flight accepts helicopter ground attack")
	check(attacker_pilot._commanded_attack_target == target, "reported ground target reaches helicopter attack controller")
	ops.order_rtb("Bulldog")
	check(attacker_pilot.mission_phase == HelicopterPilot.MissionPhase.INBOUND, "flight recall uses helicopter recovery")
	check(attacker_pilot._commanded_attack_target == null, "recall clears ground attack")
	var saved: Dictionary = ops.capture_save_state(deck)
	check(saved.get("rescue_reserve_id") == "reserve", "reserve identity included in campaign save")
	rescue.queue_free()
	await get_tree().process_frame
	deck.stored_aircraft.append(_entry("replacement", 11))
	check(assembly.get_rescue_reserve().get("id") == "replacement", "lost reserve replaced without stealing assigned aircraft")
	if failures.is_empty(): print("HELICOPTER_FLIGHT_RESERVE_PASS single_reserve assignment launch_ids callback patrol attack recall rescue_ownership save loss_replacement")
	for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _entry(id: String, model: int) -> Dictionary:
	return {"name": "Aircraft_%d" % model, "scene_file": "res://Aircraft/Aircraft_%d.tscn" % model, "position": Vector3.ZERO, "rotation": Vector3.ZERO, "scale": Vector3.ONE, "current_health": 100.0, "max_health": 100.0, "metadata": {"airframe_id": id}}

func _helicopter(id: String, model: int, guns: int) -> TestAircraft:
	var aircraft := TestAircraft.new()
	aircraft.name = "Aircraft_%d_%s" % [model, id]
	aircraft.scene_file_path = "res://Aircraft/Aircraft_%d.tscn" % model
	aircraft.freeze = true
	aircraft.set_meta("airframe_id", id)
	aircraft.set_meta("is_helicopter", true)
	aircraft.add_to_group("friendlies")
	aircraft.add_to_group("ai_aircraft")
	var pilot := TestHelicopterPilot.new()
	pilot.name = "HelicopterPilot"
	pilot.aircraft = aircraft
	pilot.state = HelicopterPilot.State.LOW_LEVEL_TRANSIT
	pilot.mission_phase = HelicopterPilot.MissionPhase.OUTBOUND
	pilot.guns = guns
	aircraft.add_child(pilot)
	add_child(aircraft)
	return aircraft

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
