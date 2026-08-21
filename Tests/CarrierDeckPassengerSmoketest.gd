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

	# Accepting a newly computed route must not snap the carrier onto its first
	# segment. The normal drive controller will turn it over subsequent physics
	# frames, allowing deck passengers to receive the same incremental transform.
	var heading_before_order: float = carrier.rotation.y
	var route_start: Vector3 = carrier.global_position
	var route_target: Vector3 = route_start + Vector3(1000.0, 0.0, 0.0)
	carrier.call("_on_path_ready", [route_start, route_target])
	if not is_equal_approx(carrier.rotation.y, heading_before_order):
		_fail("accepting a carrier route snapped its heading before drive steering ran")
		return

	# Translation and yaw both build through acceleration on the first movement
	# frame. Use full commands so this catches either channel being assigned
	# directly in a future refactor.
	carrier.set("_current_steer", 1.0)
	var movement_delta := 0.1
	var transform_before_movement: Transform3D = carrier.global_transform
	carrier.call("_apply_drive_motion", movement_delta, carrier.max_speed, carrier.turn_speed)
	var first_speed: float = float(carrier.get("_current_planar_speed_mps"))
	var first_yaw_rate: float = absf(float(carrier.get("_current_yaw_rate_rad_s")))
	if first_speed <= 0.0 or first_speed > carrier.acceleration * movement_delta + 0.0001:
		_fail("carrier translation did not respect first-frame acceleration")
		return
	if first_yaw_rate <= 0.0 or first_yaw_rate > carrier.turn_acceleration * movement_delta + 0.0001:
		_fail("carrier rotation did not respect first-frame angular acceleration")
		return
	carrier.call("_carry_deck_passengers", carrier.global_transform, transform_before_movement)
	var accelerated_local: Transform3D = carrier.global_transform.affine_inverse() * aircraft.global_transform
	if not accelerated_local.is_equal_approx(expected_local):
		_fail("accelerating carrier motion did not preserve the aircraft's deck transform")
		return

	print("[CarrierDeckPassengerSmoketest] PASS local=%s route_heading=continuous speed_ramp=%.3f yaw_ramp=%.5f" % [
		str(actual_local),
		first_speed,
		first_yaw_rate,
	])
	quit(0)


func _fail(reason: String) -> void:
	push_error("[CarrierDeckPassengerSmoketest] FAIL %s" % reason)
	quit(1)
