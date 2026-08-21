extends Node

var _failures: Array[String] = []


func _ready() -> void:
	var deck_manager := FlightDeckManager.new()
	_expect(
		is_equal_approx(deck_manager.launch_terrain_check_distance_m, 800.0),
		"flight-deck launch terrain reservation is not 800 m"
	)
	deck_manager.free()

	var carrier := LandCarrier.new()
	_expect(
		is_equal_approx(carrier.aircraft_launch_corridor_distance_m, 800.0),
		"carrier placement launch corridor is not 800 m"
	)
	carrier.free()

	var aircraft := RigidBody3D.new()
	aircraft.name = "LaunchSafetyAircraft"
	add_child(aircraft)
	aircraft.global_position = Vector3(0.0, 20.0, 0.0)
	aircraft.linear_velocity = Vector3(0.0, 4.0, 80.0)

	var pilot := AIPilot.new()
	aircraft.add_child(pilot)
	pilot.aircraft = aircraft
	pilot.current_state = AIPilot.State.LAUNCHING
	pilot.altitude_agl = 20.0
	pilot.terrain_ahead_distance = 50.0
	pilot.terrain_flight_path_distance = INF
	pilot._terrain_fan_clearances = PackedFloat32Array([20.0, 20.0, 20.0, 20.0, 20.0])
	pilot._terrain_fan_best_idx = 2

	aircraft.set_meta("controls_disabled", true)
	_expect(
		not pilot._check_terrain_avoidance(0.016),
		"terrain avoidance took control while the catapult still owned the aircraft"
	)

	aircraft.remove_meta("controls_disabled")
	_expect(
		not pilot._check_terrain_avoidance(0.016),
		"normal low deck-edge clearance caused an unnecessary terrain override"
	)

	pilot._terrain_fan_clearances = PackedFloat32Array([20.0, 20.0, 5.0, 20.0, 20.0])
	pilot._terrain_fan_best_idx = 0
	_expect(
		pilot._check_terrain_avoidance(0.016),
		"rising terrain did not take control immediately after catapult release"
	)

	pilot._terrain_fan_clearances = PackedFloat32Array([20.0, 20.0, 20.0, 20.0, 20.0])
	pilot._terrain_fan_best_idx = 2
	pilot.terrain_flight_path_distance = 100.0
	_expect(
		pilot._check_terrain_avoidance(0.016),
		"an imminent launch flight-path intersection did not trigger avoidance"
	)

	aircraft.free()
	if _failures.is_empty():
		print("[CarrierLaunchTerrainSafetySmoketest] PASS corridor=800m deck_owned=ignored deck_edge=stable rising=override direct_path=override")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[CarrierLaunchTerrainSafetySmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
