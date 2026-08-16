extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "HelicopterDeckTouchdownHandoffSmoketest"
	root.add_child(scene)
	current_scene = scene

	var carrier := CharacterBody3D.new()
	carrier.name = "CarrierTestDouble"
	carrier.velocity = Vector3(10.0, 0.0, 0.0)
	carrier.add_to_group("carrier")
	scene.add_child(carrier)

	var deck_marker := Marker3D.new()
	deck_marker.name = "DeckMarker"
	carrier.add_child(deck_marker)

	# Attach after insertion so the full scenario-oriented _ready() setup is not
	# needed for this focused touchdown test.
	var flight_deck_manager := Node.new()
	flight_deck_manager.name = "FlightDeckManager"
	carrier.add_child(flight_deck_manager)
	flight_deck_manager.set_script(load("res://LandCarrier/FlightDeckManager.gd") as Script)
	flight_deck_manager.set("deck_marker", deck_marker)
	flight_deck_manager.add_to_group("flight_deck_manager")

	var helicopter := RigidBody3D.new()
	helicopter.name = "Aircraft_11_TouchdownRegression"
	helicopter.add_to_group("ai_aircraft")
	scene.add_child(helicopter)
	helicopter.global_position = Vector3(0.0, 2.0, 0.0)
	helicopter.linear_velocity = Vector3(10.0, 0.8, 0.0)

	for gear_name in ["LeftGearCollider", "RightGearCollider"]:
		var gear := CollisionShape3D.new()
		gear.name = gear_name
		gear.position = Vector3(-1.0 if gear_name.begins_with("Left") else 1.0, -2.0, 0.0)
		helicopter.add_child(gear)

	if not bool(flight_deck_manager.call("is_aircraft_physically_settled_on_landing_deck", helicopter)):
		_fail("deck manager did not recognize low-speed upright skid contact")
		return
	helicopter.linear_velocity.y = 1.2
	if bool(flight_deck_manager.call("is_aircraft_physically_settled_on_landing_deck", helicopter)):
		_fail("deck manager accepted excessive vertical touchdown speed")
		return
	helicopter.linear_velocity.y = 0.8
	helicopter.rotation.x = deg_to_rad(60.0)
	if bool(flight_deck_manager.call("is_aircraft_physically_settled_on_landing_deck", helicopter)):
		_fail("deck manager accepted a helicopter already tipping over")
		return
	helicopter.rotation = Vector3.ZERO

	# This is deliberately above HelicopterPilot's legacy 0.55 m/s vertical gate
	# and has no LandingGear module. The shared deck check must therefore be the
	# reason touchdown completes.
	var pilot := Node.new()
	pilot.name = "HelicopterPilot"
	helicopter.add_child(pilot)
	pilot.set_script(load("res://AI/HelicopterPilot.gd") as Script)
	pilot.set("aircraft", helicopter)
	pilot.set("state", 4) # HelicopterPilot.State.LANDING
	pilot.set("mission_phase", 2) # HelicopterPilot.MissionPhase.INBOUND
	pilot.set("_landing_on_carrier", true)
	pilot.set("destination", Vector3.ZERO)
	pilot.set("_has_destination", true)
	pilot.set("_physics_delta", 0.2)
	pilot.set("carrier_landing_touchdown_settle_time_s", 0.35)

	pilot.call("_try_finish_landing")
	if helicopter.freeze:
		_fail("touchdown secured before the settle dwell elapsed")
		return
	pilot.call("_try_finish_landing")

	if not helicopter.freeze \
			or not bool(helicopter.get_meta("parking_brake", false)) \
			or not bool(helicopter.get_meta("carrier_transport_mode", false)):
		_fail("confirmed touchdown did not engage the carrier deck hold")
		return
	if int(pilot.get("state")) != 0 or int(pilot.get("mission_phase")) != 3:
		_fail("pilot did not complete LANDING/INBOUND to IDLE/AT_CARRIER handoff")
		return

	print("[HelicopterDeckTouchdownHandoffSmoketest] PASS deck_confirmed=true settle_dwell=true secured=true")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[HelicopterDeckTouchdownHandoffSmoketest] FAIL %s" % reason)
	quit(1)
