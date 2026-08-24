extends SceneTree


class HealthAircraft:
	extends RigidBody3D

	var current_health: float = 100.0
	var max_health: float = 100.0
	var team: int = 1

	func get_team() -> int:
		return team


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "HealthRtbThresholdSmoketest"
	root.add_child(scene)
	current_scene = scene

	var fixed_wing := HealthAircraft.new()
	fixed_wing.name = "FixedWingHealthRtb"
	scene.add_child(fixed_wing)
	var fixed_wing_pilot := Node.new()
	fixed_wing.add_child(fixed_wing_pilot)
	fixed_wing_pilot.set_script(load("res://AI/AIPilot.gd") as Script)
	fixed_wing_pilot.set("aircraft", fixed_wing)
	fixed_wing_pilot.set("rtb_health_threshold", 0.5)

	fixed_wing.current_health = 0.0
	if bool(fixed_wing_pilot.call("_check_rtb_triggers")):
		_fail("fixed-wing returned during the deferred zero-health initialization window")
		return
	fixed_wing.current_health = 50.0
	if bool(fixed_wing_pilot.call("_check_rtb_triggers")):
		_fail("fixed-wing returned at exactly 50 percent; rule should be under 50 percent")
		return
	fixed_wing.current_health = 49.0
	if not bool(fixed_wing_pilot.call("_check_rtb_triggers")):
		_fail("fixed-wing did not trigger RTB below 50 percent")
		return
	if int(fixed_wing_pilot.get("current_state")) != 11: # AIPilot.State.RTB
		_fail("fixed-wing health trigger did not enter RTB after recovery geometry fallback")
		return
	if not bool(fixed_wing.get_meta("health_rtb_triggered", false)):
		_fail("fixed-wing health RTB metadata was not recorded")
		return

	var carrier := Node3D.new()
	carrier.name = "CarrierHealthRtbTestDouble"
	carrier.add_to_group("carrier")
	scene.add_child(carrier)

	var helicopter := HealthAircraft.new()
	helicopter.name = "HelicopterHealthRtb"
	helicopter.current_health = 50.0
	scene.add_child(helicopter)
	var helicopter_pilot := Node.new()
	helicopter_pilot.name = "HelicopterPilot"
	helicopter.add_child(helicopter_pilot)
	helicopter_pilot.set_script(load("res://AI/HelicopterPilot.gd") as Script)
	helicopter_pilot.set("aircraft", helicopter)
	helicopter_pilot.set("state", 2) # HelicopterPilot.State.LOW_LEVEL_TRANSIT
	helicopter_pilot.set("mission_phase", 0) # HelicopterPilot.MissionPhase.OUTBOUND
	helicopter_pilot.set("rtb_health_threshold", 0.5)

	if bool(helicopter_pilot.call("_check_health_rtb")):
		_fail("helicopter returned at exactly 50 percent; rule should be under 50 percent")
		return
	helicopter.current_health = 49.0
	if not bool(helicopter_pilot.call("_check_health_rtb")):
		_fail("helicopter did not trigger RTB below 50 percent")
		return
	if int(helicopter_pilot.get("mission_phase")) != 2: # MissionPhase.INBOUND
		_fail("helicopter health trigger did not enter INBOUND")
		return
	if not bool(helicopter.get_meta("health_rtb_triggered", false)):
		_fail("helicopter health RTB metadata was not recorded")
		return

	var deck_manager := Node.new()
	carrier.add_child(deck_manager)
	deck_manager.set_script(load("res://LandCarrier/FlightDeckManager.gd") as Script)
	deck_manager.call("_log_carrier_landing_once", helicopter, "helicopter touchdown")
	if not bool(helicopter.get_meta("carrier_landing_logged", false)):
		_fail("carrier touchdown did not mark its LAND event as logged")
		return

	print("[HealthRtbThresholdSmoketest] PASS initialization_zero=ignored threshold=under_50 fixed_wing=RTB helicopter=INBOUND landing_log=true")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[HealthRtbThresholdSmoketest] FAIL %s" % reason)
	quit(1)
