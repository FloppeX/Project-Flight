extends SceneTree

class EngineStub extends Node:
	var EnergyType := "fuel"
	var FuelBaseRate := 0.05
	var FuelRate := 0.025
	var current_power := 1.0
	var is_engine_working := true

class Craft extends RigidBody3D:
	var current_health := 100.0
	var available_energy := {"fuel": 100.0}
	var energy_containers_by_type := {}
	var engines: Array[Node] = []
	func find_modules_by_type(_type: String) -> Array[Node]: return engines

class FuelTank extends Node:
	var MaxCapacity := 100.0
	var ContainerActive := true

var failures := 0
var craft_list: Array[Craft] = []

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func craft(fuel: float) -> Craft:
	var body := Craft.new()
	body.freeze = true
	body.available_energy.fuel = fuel
	root.add_child(body)
	var engine := EngineStub.new()
	body.add_child(engine)
	body.engines.append(engine)
	var tank := FuelTank.new()
	body.add_child(tank)
	body.energy_containers_by_type = {"fuel": [tank]}
	craft_list.append(body)
	return body

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var diagnostic: Variant = load("res://Tests/FullScenarioFiveAircraftRecovery.gd")
	check(diagnostic.fuel_is_exhausted({"valid": true, "current_burn_per_s": 0.0,
		"full_power_endurance_s": 0.014163}, 60.0), "stopped engine with sub-tick residual fuel counts as exhausted")
	check(not diagnostic.fuel_is_exhausted({"valid": true, "current_burn_per_s": 0.0,
		"full_power_endurance_s": 200.0}, 60.0), "switched-off fueled engine is not exhausted")
	check(not diagnostic.fuel_is_exhausted({"valid": false}, 60.0), "unknown fuel is not exhausted")
	var doubles: Variant = load("res://Tests/Fixtures/RecoverySequencingDoubles.gd")
	var carrier := Node3D.new()
	root.add_child(carrier)
	var deck: Variant = doubles.Deck.new()
	carrier.add_child(deck)
	deck.add_to_group("flight_deck_manager")
	deck.tractor_recovery_debug = false
	var predecessor := craft(100)
	var next := craft(100)
	var third := craft(100)
	var urgent := craft(15)
	deck.deck_clear = true
	check(deck.request_landing_clearance(predecessor), "first aircraft gets exclusive clearance")
	check(not deck.request_recovery_approach(next), "do not pipeline behind airborne final")
	check(not deck.request_recovery_approach(third), "third aircraft must hold")
	predecessor.set_meta("arresting_engaged", true)
	deck.deck_clear = false
	check(deck.request_recovery_approach(next), "next aircraft may prepare after predecessor catches")
	check(not deck.has_landing_clearance(next), "approach slot is not landing clearance")
	check(not deck.request_recovery_approach(third), "only one successor may prepare")
	check(not deck.request_recovery_approach(urgent), "urgent waiter cannot revoke airborne approach")
	check(deck.get_landing_queue_position(next) == 1, "approaching successor remains pinned")
	check(deck.get_landing_queue_position(urgent) == 2, "low fuel goes ahead of other waiters")
	check(deck.get_landing_queue_position(third) == 3, "plentiful fuel retains lower priority")
	var fuel: Dictionary = deck.get_recovery_fuel_snapshot(urgent)
	check(fuel.valid and absf(float(fuel.full_power_endurance_s) - 200.0) < 0.01, "real fuel burn sets conservative endurance")
	urgent.engines.append(urgent.engines[0])
	check(absf(float(deck.get_recovery_fuel_snapshot(urgent).full_power_endurance_s) - 100.0) < 0.01, "sum all engine burn rates")
	urgent.engines.pop_back()
	var budget: float = deck.get_recovery_fuel_budget_s(third)
	check(budget >= 4 * deck.recovery_slot_budget_s, "RTB budget includes existing queue")
	var pilot: Variant = doubles.Pilot.new()
	next.add_child(pilot)
	pilot.aircraft = next
	pilot.rtb_health_threshold = 0.0
	pilot.rtb_fuel_threshold = 0.35
	next.available_energy.fuel = 100.0
	check(not pilot.call("_check_rtb_triggers"), "plentiful fuel does not force early return")
	pilot.aircraft = third
	third.available_energy.fuel = 40.0
	check(pilot.call("_check_rtb_triggers") and pilot.recalled,
		"queue budget recalls above ordinary 35 percent bingo threshold")
	check(str(third.get_meta("rtb_reason", "")).contains("recovery queue"), "queue-aware fuel reason is explicit")
	pilot.aircraft = next
	pilot.call("_state_landing", 0.033)
	check(pilot.waved_off, "direct final entry cannot bypass occupied deck")
	pilot.waved_off = false
	pilot.caught = true
	pilot.call("_state_landing", 0.033)
	check(not pilot.waved_off, "actual arrest takes precedence over clearance gate")
	deck.release_landing_clearance(predecessor)
	check(not deck.has_landing_clearance(next), "releasing holder does not bypass busy stow deck")
	deck._pending_store_aircraft = predecessor
	deck.current_state = deck.DeckState.STORING_IN_HANGAR
	check(deck.request_recovery_approach(next), "approach slot persists through storage")
	check(deck.is_carrier_recovery_constraint_active(), "prepared approach keeps carrier reference stable through stow")
	deck.deck_clear = true
	deck._grant_next_landing_clearance_if_possible()
	check(deck.has_landing_clearance(next), "prepared aircraft gains final only after deck clears")
	check(not deck.has_landing_clearance(urgent), "exclusive clearance remains exclusive")
	deck.release_landing_clearance(next)
	check(deck.has_landing_clearance(urgent), "urgent waiter receives next free slot")
	deck.deck_clear = false
	deck.release_landing_clearance(urgent)
	deck.current_state = deck.DeckState.LAUNCH_IN_PROGRESS
	check(not deck.request_recovery_approach(third), "never pipeline across outbound launch")
	deck.current_state = deck.DeckState.STORING_IN_HANGAR
	check(deck.request_recovery_approach(third), "stow allows another prepared successor")
	craft_list.erase(third)
	third.free()
	deck._prune_landing_clearance_queue()
	check(not is_instance_valid(deck._recovery_approach_aircraft), "freed approach aircraft releases reservation")
	for body in craft_list: body.free()
	carrier.free()
	print("RECOVERY_SEQUENCING_SMOKETEST %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
