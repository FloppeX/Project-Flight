extends Node

const CARRIER_SCENE := preload("res://LandCarrier/LandCarrier2.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	var carrier := CARRIER_SCENE.instantiate() as Node3D
	var manager := carrier.get_node("FlightDeckManager") as FlightDeckManager
	var elevator := carrier.get_node("Elevator") as CarrierElevator
	var elevator_2 := carrier.get_node("Elevator2") as CarrierElevator
	var carrier_model := carrier.get_node("CarrierModel") as Node3D
	var marker_1 := carrier.get_node("elevator_marker") as Marker3D
	var marker_2 := carrier.get_node("elevator_marker_2") as Marker3D
	var catapult_1 := carrier.get_node("Catapult1")
	var catapult_2 := carrier.get_node("Catapult2")
	_expect(carrier_model.scene_file_path == "res://Models/LandCarrier/Land carrier 3.glb", "carrier did not use Land carrier 3 GLB")
	_expect(elevator.position.is_equal_approx(Vector3(-8.0, 0.0, 10.0)), "elevator 1 did not map from its Blender coordinates")
	_expect(elevator_2.position.is_equal_approx(Vector3(8.0, 0.0, -10.0)), "elevator 2 did not map from its Blender coordinates")
	_expect(elevator.platform_size.is_equal_approx(Vector3(10.0, 1.0, 15.0)) and elevator_2.platform_size.is_equal_approx(Vector3(10.0, 1.0, 15.0)), "dual elevator platform dimensions are not 10 x 15 m")
	_expect(marker_1.position.is_equal_approx(elevator.position) and marker_2.position.is_equal_approx(elevator_2.position), "elevator pickup markers do not match the two platforms")
	elevator.create_elevator_components(false)
	elevator.set_initial_state()
	elevator_2.create_elevator_components(false)
	elevator_2.set_initial_state()

	manager._normalize_primary_tractorbots()
	manager._place_primary_tractorbots_at_staging_start()
	manager.call("_resolve_elevator_roles")
	manager.call("_discover_authored_catapults")

	_expect(manager.get("_catapults").size() == 2, "carrier did not discover both authored catapults")
	_expect(catapult_1.shuttle != catapult_2.shuttle, "the two catapults still share one shuttle")
	_expect(is_equal_approx((catapult_1 as Node3D).position.x, marker_1.position.x), "catapult 1 is not on elevator 1's centerline")
	_expect(is_equal_approx((catapult_2 as Node3D).position.x, marker_2.position.x), "catapult 2 is not on elevator 2's centerline")
	manager.call("_set_active_elevator", elevator, marker_1)
	_expect(manager.catapult == catapult_1, "elevator 1 did not select catapult 1")
	_expect(manager.call("_get_active_catapult_latch_marker") == catapult_1.latch_marker, "lane 1 tow target did not use catapult 1's latch")
	manager.call("_set_active_elevator", elevator_2, marker_2)
	_expect(manager.catapult == catapult_2, "elevator 2 did not select catapult 2")
	_expect(manager.call("_get_active_catapult_latch_marker") == catapult_2.latch_marker, "lane 2 tow target did not use catapult 2's latch")

	var standard_aircraft := (load("res://Aircraft/Aircraft_5.tscn") as PackedScene).instantiate() as RigidBody3D
	var four_wheel_aircraft := (load("res://Aircraft/Aircraft_9.tscn") as PackedScene).instantiate() as RigidBody3D
	var two_wheel_aircraft := (load("res://Aircraft/Aircraft_11.tscn") as PackedScene).instantiate() as RigidBody3D
	_expect(int(manager.call("_get_required_tractor_count", standard_aircraft)) == 3, "three-wheel aircraft did not request three tractorbots")
	_expect(int(manager.call("_get_required_tractor_count", four_wheel_aircraft)) == 4, "Aircraft 9 did not request all four tractorbots")
	_expect(int(manager.call("_get_required_tractor_count", two_wheel_aircraft)) == 2, "two-wheel helicopter did not request two tractorbots")
	var standard_job: Array[Node3D] = manager.call("_select_tractor_bots_for_aircraft", standard_aircraft, manager.call("_get_required_tractor_count", standard_aircraft))
	manager.call("_set_current_job_tractor_bots", standard_job)
	_expect((manager.call("_get_current_job_tractor_bots") as Array).size() == 3, "job roster expanded a three-wheel aircraft back to four tractorbots")
	standard_aircraft.free()
	four_wheel_aircraft.free()
	two_wheel_aircraft.free()

	_expect(manager.tractor_bots.size() == 8, "carrier did not retain all eight tractorbots")
	_expect(manager.tractor_setup_points.size() == 8, "carrier did not resolve eight authored child setup points")
	var expected_bottom_y := -9.5 + manager.tractor_elevator_floor_offset_m
	for i in range(manager.tractor_bots.size()):
		var bot := manager.tractor_bots[i] as Node3D
		var home_transform: Transform3D = manager.call("_get_tractor_home_transform_local", bot, i)
		_expect(is_equal_approx(bot.position.x, home_transform.origin.x), "tractor %d did not use its cached home X" % (i + 1))
		_expect(is_equal_approx(bot.position.z, home_transform.origin.z), "tractor %d did not use its cached home Z" % (i + 1))
		_expect(is_equal_approx(bot.position.y, expected_bottom_y), "tractor %d did not sit on its bottom platform" % (i + 1))

	manager.call("_select_launch_elevator")
	_expect(manager.elevator == elevator and manager.catapult == catapult_1, "first launch did not use elevator/catapult lane 1")
	var launch_bots := manager._get_primary_tractor_bots()
	_expect(launch_bots.size() == 4 and launch_bots[0].name == "TractorBot1" and launch_bots[3].name == "TractorBot4", "elevator 1 did not prefer tractorbots 1-4")
	var launch_slots := manager._get_primary_elevator_slots_local(4, -9.5)
	for i in range(launch_slots.size()):
		var expected_home: Transform3D = manager.call("_get_tractor_home_transform_local", launch_bots[i], manager.tractor_bots.find(launch_bots[i]))
		_expect(Vector2(launch_slots[i].x, launch_slots[i].z).is_equal_approx(Vector2(expected_home.origin.x, expected_home.origin.z)), "launch slot %d lost its authored home" % (i + 1))

	manager.call("_select_recovery_elevator")
	_expect(manager.elevator == elevator_2 and manager.elevator_pickup_marker == marker_2, "recovery operations did not select elevator 2")
	var recovery_bots := manager._get_primary_tractor_bots()
	_expect(recovery_bots.size() == 4 and recovery_bots[0].name == "TractorBot5" and recovery_bots[3].name == "TractorBot8", "elevator 2 did not prefer tractorbots 5-8")
	var recovery_slots := manager._get_primary_elevator_slots_local(4, -9.5)
	for i in range(recovery_slots.size()):
		var expected_home: Transform3D = manager.call("_get_tractor_home_transform_local", recovery_bots[i], manager.tractor_bots.find(recovery_bots[i]))
		_expect(Vector2(recovery_slots[i].x, recovery_slots[i].z).is_equal_approx(Vector2(expected_home.origin.x, expected_home.origin.z)), "recovery slot %d lost its authored home" % (i + 1))

	manager.call("_select_launch_elevator")
	_expect(manager.elevator == elevator_2 and manager.catapult == catapult_2, "second launch did not alternate to elevator/catapult lane 2")
	manager.call("_select_recovery_elevator")

	# A busy home bot is skipped and a bot from the other elevator fills the job.
	var requested_aircraft := RigidBody3D.new()
	var other_aircraft := RigidBody3D.new()
	var busy_bot := recovery_bots[0]
	busy_bot.set("is_active", true)
	busy_bot.set("target_aircraft", other_aircraft)
	var interchangeable: Array[Node3D] = manager.call("_select_tractor_bots_for_aircraft", requested_aircraft, 4)
	_expect(interchangeable.size() == 4, "interchangeable pool could not replace a busy tractorbot")
	_expect(not interchangeable.has(busy_bot), "busy tractorbot was assigned to a second aircraft")
	_expect(interchangeable.any(func(bot): return launch_bots.has(bot)), "other elevator did not lend an available tractorbot")
	busy_bot.set("is_active", false)
	busy_bot.set("target_aircraft", null)
	requested_aircraft.free()
	other_aircraft.free()

	var simulated_top_y := 0.0
	var top_slots := manager._get_primary_elevator_slots_local(4, simulated_top_y)
	for i in range(top_slots.size()):
		_expect(is_equal_approx(top_slots[i].x, recovery_slots[i].x), "top slot %d lost recovery-home X" % (i + 1))
		_expect(is_equal_approx(top_slots[i].z, recovery_slots[i].z), "top slot %d lost recovery-home Z" % (i + 1))
		_expect(is_equal_approx(top_slots[i].y, simulated_top_y), "top slot %d did not follow platform Y" % (i + 1))

	# Cached child markers must remain stable even after the bots have moved.
	elevator.set_technical_index_preview_fraction(1.0)
	elevator_2.set_technical_index_preview_fraction(1.0)
	(manager.tractor_bots[0] as Node3D).position += Vector3(50.0, 0.0, 50.0)
	manager._place_primary_tractorbots_at_staging_start()
	var expected_top_y := manager.tractor_elevator_floor_offset_m
	for i in range(manager.tractor_bots.size()):
		var bot := manager.tractor_bots[i] as Node3D
		var home_transform: Transform3D = manager.call("_get_tractor_home_transform_local", bot, i)
		_expect(is_equal_approx(bot.position.x, home_transform.origin.x), "deck-level tractor %d left its cached home X" % (i + 1))
		_expect(is_equal_approx(bot.position.z, home_transform.origin.z), "deck-level tractor %d left its cached home Z" % (i + 1))
		_expect(is_equal_approx(bot.position.y, expected_top_y), "deck-level tractor %d did not sit on the elevator" % (i + 1))

	carrier.free()
	if _failures.is_empty():
		print("TRACTOR_ELEVATOR_SETUP_POINTS_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[TractorElevatorSetupPointsSmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
