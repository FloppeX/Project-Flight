extends SceneTree


const ENGINE_SCRIPT: Script = preload("res://addons/simplified_flightsim/aircraft_modules/Engine/Engine.gd")
const FIXED_WING_SCENES: PackedStringArray = [
	"res://Aircraft/Aircraft_1.tscn",
	"res://Aircraft/Aircraft_2.tscn",
	"res://Aircraft/Aircraft_5.tscn",
	"res://Aircraft/Aircraft_7.tscn",
	"res://Aircraft/Aircraft_8.tscn",
	"res://Aircraft/Aircraft_14.tscn",
]
const HELICOPTER_SCENES: PackedStringArray = [
	"res://Aircraft/Aircraft_9.tscn",
	"res://Aircraft/Aircraft_10.tscn",
	"res://Aircraft/Aircraft_11.tscn",
	"res://Aircraft/Aircraft_12.tscn",
]
const EXPECTED_BASE_RATE := 0.065
const EXPECTED_VARIABLE_RATE := 0.01
const EXPECTED_RTB_THRESHOLD := 0.35
const LOW_NORMAL_POWER := 0.4
const HIGH_NORMAL_POWER := 1.0


class MockAircraft:
	extends Node3D

	var requested_energy_type := ""
	var requested_energy_amount := 0.0

	func request_energy(energy_type: String, amount: float) -> bool:
		requested_energy_type = energy_type
		requested_energy_amount += amount
		return true

	func apply_force(_force: Vector3, _position: Vector3 = Vector3.ZERO) -> void:
		pass


class MockEnergyContainer:
	extends Node

	var current_level := 0.0
	var EnergyType := "fuel"
	var MaxCapacity := 100.0
	var ContainerActive := true


class FuelAircraft:
	extends RigidBody3D

	var current_health := 100.0
	var max_health := 100.0
	var available_energy: Dictionary = {"fuel": 35.0}
	var energy_containers_by_type: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for scene_path in FIXED_WING_SCENES:
		if not _check_fixed_wing_scene(scene_path):
			return
	for scene_path in HELICOPTER_SCENES:
		if not _check_helicopter_scene(scene_path):
			return
	if not _check_engine_consumption():
		return
	if not _check_fuel_rtb_trigger():
		return
	if not _check_hangar_refuel():
		return

	print("[FixedWingFuelEnduranceSmoketest] PASS fixed_wing_models=1,2,5,7,8,14 bingo_window=14.4-15.7min reserve_at_full_power=7.8min helicopters=unchanged hangar_refuel=full")
	quit(0)


func _check_fixed_wing_scene(scene_path: String) -> bool:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return _fail("could not load %s" % scene_path)
	var aircraft := packed.instantiate()
	var engine := aircraft.get_node_or_null("Engine")
	var fuel_container := aircraft.get_node_or_null("EnergyContainer")
	var pilot := aircraft.get_node_or_null("AIPilot")
	if engine == null or fuel_container == null or pilot == null:
		aircraft.free()
		return _fail("%s is missing Engine, EnergyContainer, or AIPilot" % scene_path)
	if engine.get("FuelBaseRate") == null or engine.get("FuelRate") == null \
	or fuel_container.get("MaxCapacity") == null or pilot.get("rtb_fuel_threshold") == null:
		aircraft.free()
		return _fail("%s fuel properties are unavailable" % scene_path)
	var base_rate := float(engine.get("FuelBaseRate"))
	var variable_rate := float(engine.get("FuelRate"))
	var capacity := float(fuel_container.get("MaxCapacity"))
	var rtb_threshold := float(pilot.get("rtb_fuel_threshold"))
	if not is_equal_approx(base_rate, EXPECTED_BASE_RATE) \
	or not is_equal_approx(variable_rate, EXPECTED_VARIABLE_RATE) \
	or not is_equal_approx(rtb_threshold, EXPECTED_RTB_THRESHOLD):
		aircraft.free()
		return _fail("%s does not use the fixed-wing fuel profile" % scene_path)
	for power in [LOW_NORMAL_POWER, HIGH_NORMAL_POWER]:
		var seconds_to_bingo: float = capacity * (1.0 - rtb_threshold) \
			/ (base_rate + variable_rate * power)
		if seconds_to_bingo < 14.0 * 60.0 or seconds_to_bingo > 16.0 * 60.0:
			aircraft.free()
			return _fail("%s bingo time %.1fs is outside the 14-16 minute window" % [
				scene_path,
				seconds_to_bingo,
			])
	var full_power_reserve_s := capacity * rtb_threshold \
		/ (base_rate + variable_rate * HIGH_NORMAL_POWER)
	if full_power_reserve_s < 7.5 * 60.0:
		aircraft.free()
		return _fail("%s has insufficient fuel reserve for carrier recovery" % scene_path)
	aircraft.free()
	return true


func _check_helicopter_scene(scene_path: String) -> bool:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return _fail("could not load %s" % scene_path)
	var aircraft := packed.instantiate()
	var engine := aircraft.get_node_or_null("Engine")
	if engine == null:
		aircraft.free()
		return _fail("%s is missing Engine" % scene_path)
	if engine.get("FuelBaseRate") == null:
		aircraft.free()
		return _fail("%s FuelBaseRate is unavailable" % scene_path)
	if not is_zero_approx(float(engine.get("FuelBaseRate"))):
		aircraft.free()
		return _fail("fixed-wing base burn leaked into helicopter %s" % scene_path)
	aircraft.free()
	return true


func _check_engine_consumption() -> bool:
	var mock_aircraft := MockAircraft.new()
	var engine: Node = ENGINE_SCRIPT.new()
	root.add_child(mock_aircraft)
	mock_aircraft.add_child(engine)
	engine.set("aircraft", mock_aircraft)
	engine.set("FuelBaseRate", EXPECTED_BASE_RATE)
	engine.set("FuelRate", EXPECTED_VARIABLE_RATE)
	engine.set("is_engine_working", true)
	engine.set("current_power", 0.75)
	engine.set("target_power", 0.75)
	engine.set("visual_budget_enabled", false)
	engine.set("audio_budget_enabled", false)
	engine.call("process_physic_frame", 10.0)
	var expected_burn := (EXPECTED_BASE_RATE + EXPECTED_VARIABLE_RATE * 0.75) * 10.0
	if mock_aircraft.requested_energy_type != "fuel" \
	or not is_equal_approx(mock_aircraft.requested_energy_amount, expected_burn):
		mock_aircraft.free()
		return _fail("engine did not combine base and power-dependent fuel burn")
	mock_aircraft.free()
	return true


func _check_hangar_refuel() -> bool:
	# Load this large subsystem only after autoload initialization. Preloading it
	# with the test script compiles its class-name dependencies too early.
	var manager_script := load("res://LandCarrier/FlightDeckManager.gd") as Script
	if manager_script == null:
		return _fail("could not load FlightDeckManager")
	var manager: Node = manager_script.new()
	var aircraft := RigidBody3D.new()
	var fuel := MockEnergyContainer.new()
	fuel.name = "Fuel"
	fuel.current_level = 12.0
	aircraft.add_child(fuel)
	var battery := MockEnergyContainer.new()
	battery.name = "Battery"
	battery.EnergyType = "battery"
	battery.current_level = 37.0
	aircraft.add_child(battery)
	var captured: Array = manager.call("_capture_aircraft_energy_state", aircraft)
	var captured_by_type: Dictionary = {}
	for entry_variant in captured:
		if entry_variant is Dictionary:
			var entry := entry_variant as Dictionary
			captured_by_type[str(entry.get("energy_type", ""))] = float(entry.get("current_level", -1.0))
	var fuel_ok := is_equal_approx(float(captured_by_type.get("fuel", -1.0)), 100.0)
	var battery_ok := is_equal_approx(float(captured_by_type.get("battery", -1.0)), 37.0)
	manager.free()
	aircraft.free()
	if not fuel_ok or not battery_ok:
		return _fail("hangar servicing did not refill only fuel")
	return true


func _check_fuel_rtb_trigger() -> bool:
	var aircraft := FuelAircraft.new()
	aircraft.name = "FuelRtbAircraft"
	root.add_child(aircraft)
	var fuel := MockEnergyContainer.new()
	fuel.current_level = 35.0
	aircraft.add_child(fuel)
	aircraft.energy_containers_by_type = {"fuel": [fuel]}
	var pilot := Node.new()
	aircraft.add_child(pilot)
	pilot.set_script(load("res://AI/AIPilot.gd") as Script)
	pilot.set("aircraft", aircraft)
	pilot.set("rtb_health_threshold", 0.0)
	pilot.set("rtb_fuel_threshold", EXPECTED_RTB_THRESHOLD)
	if bool(pilot.call("_check_rtb_triggers")):
		aircraft.free()
		return _fail("fuel RTB fired at exactly the reserve threshold")
	fuel.current_level = 34.9
	aircraft.available_energy["fuel"] = 34.9
	if not bool(pilot.call("_check_rtb_triggers")):
		aircraft.free()
		return _fail("fuel RTB did not fire below the reserve threshold")
	var entered_rtb := int(pilot.get("current_state")) == 11 # AIPilot.State.RTB
	var reason_recorded := str(aircraft.get_meta("rtb_reason", "")).begins_with("Fuel low")
	aircraft.free()
	if not entered_rtb or not reason_recorded:
		return _fail("fuel threshold did not enter RTB and record its reason")
	return true


func _fail(reason: String) -> bool:
	push_error("[FixedWingFuelEnduranceSmoketest] FAIL %s" % reason)
	quit(1)
	return false
