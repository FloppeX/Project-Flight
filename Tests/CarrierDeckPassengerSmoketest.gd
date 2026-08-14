extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "CarrierDeckPassengerSmoketest"
	root.add_child(scene)
	current_scene = scene

	# Attach the production script after the carrier is in-tree so this focused
	# test can exercise deck carrying without running the full scenario startup.
	var carrier := CharacterBody3D.new()
	carrier.name = "LandCarrierTestDouble"
	scene.add_child(carrier)
	# Runtime loading lets project autoload globals finish registering before the
	# production carrier script is compiled by this standalone SceneTree test.
	var carrier_script := load("res://LandCarrier/LandCarrier.gd") as Script
	if carrier_script == null:
		_fail("production LandCarrier script could not be loaded")
		return
	carrier.set_script(carrier_script)
	carrier.add_to_group("carrier")
	carrier.global_transform = Transform3D(Basis.IDENTITY, Vector3(100.0, 20.0, -50.0))

	var aircraft := RigidBody3D.new()
	aircraft.name = "RetrievedDeckAircraft"
	aircraft.freeze = true
	aircraft.add_to_group("ai_aircraft")
	aircraft.set_meta("controls_disabled", true)
	aircraft.set_meta("parking_brake", true)
	aircraft.set_meta("physics_ready_for_launch", true)
	scene.add_child(aircraft)
	var expected_local := Transform3D(
		Basis(Vector3.UP, deg_to_rad(12.0)),
		Vector3(8.0, 42.0, 26.0)
	)
	aircraft.global_transform = carrier.global_transform * expected_local

	var old_carrier_transform := carrier.global_transform
	carrier.global_transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(38.0)),
		Vector3(145.0, 20.0, 10.0)
	)
	carrier.call("_carry_deck_passengers", carrier.global_transform, old_carrier_transform)
	var actual_local: Transform3D = carrier.global_transform.affine_inverse() * aircraft.global_transform
	if not actual_local.is_equal_approx(expected_local):
		_fail("retrieved aircraft did not retain its carrier-relative deck transform")
		return

	print("[CarrierDeckPassengerSmoketest] PASS local=%s" % str(actual_local))
	quit(0)


func _fail(reason: String) -> void:
	push_error("[CarrierDeckPassengerSmoketest] FAIL %s" % reason)
	quit(1)
