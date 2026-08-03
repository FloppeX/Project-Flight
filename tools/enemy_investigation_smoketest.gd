extends Node

var _failures: PackedStringArray = []


func _ready() -> void:
	EnemyOpsManager.set_physics_process(false)
	_reset_enemy_ops_state()

	var test_base := EnemyBase.new()
	test_base.faction_name = "Test Base"
	test_base.position = Vector3.ZERO
	EnemyOpsManager.bases.append(test_base)
	EnemyOpsManager._base_flights[test_base] = []
	EnemyOpsManager._base_platoons[test_base] = []

	var first := _make_flight("TEST-01", Vector3(0.0, 680.0, 0.0))
	var second := _make_flight("TEST-02", Vector3(10000.0, 680.0, 0.0))
	EnemyOpsManager._base_flights[test_base] = [first, second]

	# Exercise the real building-loss hook rather than inserting the first incident
	# directly into Enemy Ops.
	var building := Building.new()
	building.max_health = 1.0
	building.team = 2
	add_child(building)
	building.global_position = Vector3(2000.0, 0.0, 0.0)
	building._explosion_scene = null
	building.take_damage(1.0)
	EnemyOpsManager._service_loss_investigations()

	_check(first.mission == EnemyVirtualFlight.Mission.INVESTIGATE, "nearest fighter should receive the building-loss investigation")
	_check(second.mission == EnemyVirtualFlight.Mission.PATROL, "only one fighter flight should be retasked")
	_check(EnemyOpsManager._count_centrally_tasked_air_responses() == 1, "central response cap should hold at one flight")

	EnemyOpsManager.report_asset_loss(Vector3(2500.0, 0.0, 0.0), "gun emplacement")
	var status: Dictionary = EnemyOpsManager.get_investigation_status()
	_check(int(status.get("pending", -1)) == 0, "nearby losses should coalesce into the active investigation")
	_check(first.get_investigation_position().is_equal_approx(Vector3(2500.0, 0.0, 0.0)), "coalesced loss should update the search position")

	EnemyOpsManager.report_asset_loss(Vector3(30000.0, 0.0, 0.0), "building")
	EnemyOpsManager._service_loss_investigations()
	_check(second.mission == EnemyVirtualFlight.Mission.PATROL, "a distant queued incident must not launch a second simultaneous response")
	_check(int(EnemyOpsManager.get_investigation_status().get("pending", -1)) == 1, "distant loss should remain queued while the response slot is occupied")

	first.position = Vector3(2500.0, 680.0, 0.0)
	first.tick(1.0)
	first.tick(EnemyVirtualFlight.INVESTIGATION_SEARCH_DURATION_S + 1.0)
	_check(first.mission == EnemyVirtualFlight.Mission.PATROL, "empty investigation should time out and resume patrol")
	EnemyOpsManager._service_loss_investigations()
	_check(second.mission == EnemyVirtualFlight.Mission.INVESTIGATE, "queued incident should dispatch only after the first response finishes")
	_check(first.mission == EnemyVirtualFlight.Mission.PATROL, "completed investigator should remain on patrol")

	# A virtual interceptor should follow the assigned report, not an out-of-range
	# aircraft's exact live position.
	var intercept := _make_flight("TEST-03", Vector3(0.0, 680.0, 0.0))
	intercept.set_intercept_position(Vector3(1000.0, 680.0, 0.0))
	var far_friendly := Node3D.new()
	far_friendly.add_to_group("aircraft")
	add_child(far_friendly)
	far_friendly.global_position = Vector3(0.0, 680.0, 20000.0)
	intercept.tick(1.0)
	_check(intercept.position.x > 90.0 and absf(intercept.position.z) < 1.0, "intercept should steer toward reported position, not a globally visible friendly")

	_reset_enemy_ops_state()
	for node: Node in [building, first, second, intercept, far_friendly]:
		if is_instance_valid(node):
			node.free()
	if is_instance_valid(test_base):
		test_base.free()
	if _failures.is_empty():
		print("ENEMY_INVESTIGATION_SMOKE PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("ENEMY_INVESTIGATION_SMOKE: %s" % failure)
	print("ENEMY_INVESTIGATION_SMOKE FAIL count=%d" % _failures.size())
	get_tree().quit(1)


func _make_flight(flight_name_value: String, start_position: Vector3) -> EnemyVirtualFlight:
	var flight := EnemyVirtualFlight.new()
	flight.flight_name = flight_name_value
	flight.aircraft_count = 2
	flight.position = start_position
	flight.home_position = Vector3.ZERO
	flight.role = EnemyVirtualFlight.AircraftRole.FIGHTER
	add_child(flight)
	return flight


func _reset_enemy_ops_state() -> void:
	EnemyOpsManager.bases.clear()
	EnemyOpsManager._base_flights.clear()
	EnemyOpsManager._base_platoons.clear()
	EnemyOpsManager._known_contacts.clear()
	EnemyOpsManager._pending_loss_incidents.clear()
	EnemyOpsManager._investigation_flight_ref = null
	EnemyOpsManager._flight_next_tick_s.clear()
	EnemyOpsManager._flight_last_tick_s.clear()
	EnemyOpsManager._platoon_next_tick_s.clear()
	EnemyOpsManager._platoon_last_tick_s.clear()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
