extends SceneTree


class CarrierTestDouble:
	extends CharacterBody3D

	var deck_velocity: Vector3 = Vector3.ZERO
	var yaw_rate_rad_s: float = 0.0

	func get_deck_reference_velocity_vector() -> Vector3:
		return deck_velocity

	func get_yaw_rate_rad_s() -> float:
		return yaw_rate_rad_s


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "CarrierLandingPermissivenessSmoketest"
	root.add_child(scene)
	current_scene = scene

	var carrier := CarrierTestDouble.new()
	carrier.name = "CarrierTestDouble"
	carrier.deck_velocity = Vector3(4.0, 0.0, 0.0)
	carrier.add_to_group("carrier")
	scene.add_child(carrier)

	var approach_markers: Array[Node3D] = []
	for index in range(5):
		var marker := Marker3D.new()
		marker.name = "approach_%d" % index
		marker.position = Vector3(0.0, 0.0, float(index) * 10.0)
		carrier.add_child(marker)
		approach_markers.append(marker)

	var helicopter := RigidBody3D.new()
	helicopter.name = "HelicopterVelocityRegression"
	helicopter.add_to_group("ai_aircraft")
	scene.add_child(helicopter)
	helicopter.set_meta("motion_reference_velocity", Vector3(99.0, 0.0, 0.0))
	helicopter.set_meta("carrier_deck_velocity", Vector3(99.0, 0.0, 0.0))

	var helicopter_pilot := Node.new()
	helicopter_pilot.name = "HelicopterPilot"
	helicopter.add_child(helicopter_pilot)
	helicopter_pilot.set_script(load("res://AI/HelicopterPilot.gd") as Script)
	helicopter_pilot.set("aircraft", helicopter)
	helicopter_pilot.set("_landing_on_carrier", true)

	if not _vector_near(helicopter_pilot.call("_get_deck_reference_velocity"), carrier.deck_velocity):
		_fail("helicopter landing preferred a stale deck-velocity snapshot")
		return
	carrier.deck_velocity = Vector3(11.0, 0.0, -2.0)
	if not _vector_near(helicopter_pilot.call("_get_deck_reference_velocity"), carrier.deck_velocity):
		_fail("helicopter landing did not follow a carrier speed change immediately")
		return

	if bool(helicopter_pilot.call("_should_permissively_commit_carrier_final", true, 8.0, 90.0, 25.0)) != true:
		_fail("cleared near-gate helicopter did not receive permissive final commit")
		return
	if bool(helicopter_pilot.call("_should_permissively_commit_carrier_final", true, 2.0, 90.0, 25.0)):
		_fail("permissive final commit ignored its short dwell")
		return
	if not bool(helicopter_pilot.call("_should_commit_timed_out_carrier_final", 80.0, 140.0)):
		_fail("near-carrier final timeout did not commit to descent")
		return

	var deck_manager := Node.new()
	deck_manager.name = "FlightDeckManager"
	carrier.add_child(deck_manager)
	deck_manager.set_script(load("res://LandCarrier/FlightDeckManager.gd") as Script)
	deck_manager.set("_landing_clearance_aircraft", helicopter)
	if bool(deck_manager.call("_is_helicopter_currently_landing_on_carrier", helicopter)):
		_fail("gate-phase helicopter still suppresses the clearance timeout")
		return
	if bool(deck_manager.call("_landing_clearance_aircraft_needs_carrier_constraint")):
		_fail("gate-phase helicopter stopped the carrier before final")
		return
	helicopter.set_meta("carrier_landing_final_active", true)
	if not bool(deck_manager.call("_is_helicopter_currently_landing_on_carrier", helicopter)):
		_fail("active helicopter final no longer protects its landing clearance")
		return
	if not bool(deck_manager.call("_landing_clearance_aircraft_needs_carrier_constraint")):
		_fail("active helicopter final did not constrain carrier motion")
		return
	helicopter.remove_meta("carrier_landing_final_active")

	var fixed_wing := RigidBody3D.new()
	fixed_wing.name = "FixedWingVelocityRegression"
	scene.add_child(fixed_wing)
	var fixed_wing_pilot := Node.new()
	fixed_wing.add_child(fixed_wing_pilot)
	fixed_wing_pilot.set_script(load("res://AI/AIPilot.gd") as Script)
	fixed_wing_pilot.set("aircraft", fixed_wing)
	fixed_wing_pilot.set("_approach_wp", approach_markers)
	if not bool(fixed_wing_pilot.call("_should_permissively_release_recovery_hold", 20.0, 100.0)):
		_fail("cleared fixed-wing hold did not receive its permissive release")
		return
	if bool(fixed_wing_pilot.call("_should_permissively_release_recovery_hold", 2.0, 100.0)):
		_fail("fixed-wing permissive hold release ignored its dwell")
		return
	carrier.deck_velocity = Vector3(6.0, 0.0, 1.0)
	carrier.yaw_rate_rad_s = 0.0
	if not _vector_near(fixed_wing_pilot.call("_get_carrier_velocity"), carrier.deck_velocity):
		_fail("fixed-wing recovery did not use the live carrier drive velocity")
		return
	carrier.deck_velocity = Vector3(2.0, 0.0, 7.0)
	if not _vector_near(fixed_wing_pilot.call("_get_carrier_velocity"), carrier.deck_velocity):
		_fail("fixed-wing recovery carrier velocity lagged a speed change")
		return

	print("[CarrierLandingPermissivenessSmoketest] PASS live_velocity=helicopter+fixed_wing queue_timeout=gate_only permissive_commit=helicopter+fixed_wing")
	quit(0)


func _vector_near(actual_variant: Variant, expected: Vector3) -> bool:
	if typeof(actual_variant) != TYPE_VECTOR3:
		return false
	return (actual_variant as Vector3).is_equal_approx(expected)


func _fail(reason: String) -> void:
	push_error("[CarrierLandingPermissivenessSmoketest] FAIL %s" % reason)
	quit(1)
