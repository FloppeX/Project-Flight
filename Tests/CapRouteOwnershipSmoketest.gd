extends Node

class ProbePilot extends AIPilot:
	var guided_point := Vector3.INF
	func _ready() -> void: pass
	func _navigate_to_waypoint(_delta: float) -> void:
		guided_point = nav_waypoint

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	for child in get_tree().root.get_children():
		if child != self: child.process_mode = Node.PROCESS_MODE_DISABLED
	var carrier := Node3D.new()
	add_child(carrier)
	carrier.position = Vector3(5478, 522, 6315)
	carrier.add_to_group("carrier")
	var flight := Flight.new()
	add_child(flight)
	flight.set_physics_process(false)
	var aircraft: Array[RigidBody3D] = []
	var pilots: Array[ProbePilot] = []
	for i in range(2):
		var craft := RigidBody3D.new()
		craft.freeze = true
		add_child(craft)
		craft.position = Vector3(-313, 1007, 790) if i == 0 else Vector3(5243, 1095, 2949)
		var pilot := ProbePilot.new()
		pilot.name = "AIPilot"
		craft.add_child(pilot)
		pilot.set_physics_process(false)
		pilot.aircraft = craft
		pilot.current_state = AIPilot.State.SEARCH
		pilot._terrain_height_callable = func(_point: Vector3) -> float: return 482.0
		pilot.altitude_agl = 525.0
		flight.register(craft)
		aircraft.append(craft)
		pilots.append(pilot)
	var route: Array[Vector3] = [Vector3(2287,800,-4227), Vector3(2703,800,-9881), Vector3(10297,800,-9908), Vector3(9965,800,-4005)]
	flight.set_cap_route(carrier, route, 800.0)
	flight._apply_pending_mission_updates()
	for pilot in pilots:
		check(pilot._has_assigned_patrol_route(), "each CAP member retains route intent")
		check(not pilot.current_air_task.metadata.carrier_relative and not pilot.waypoints_follow_carrier, "assigned CAP is not carrier-relative")
		check(pilot.waypoints.size() == 4 and pilot.waypoints[0].z < -4000, "wingman and lead have route fallback")
		pilot._search_return_to_cap_active = true
		pilot._state_search(1.0 / 60.0)
		check(not pilot._search_return_to_cap_active, "assigned patrol clears a latched carrier return")
		check(pilot.guided_point.z < -4000, "guidance follows chosen patrol outside carrier radius")
	flight._update_formation()
	check(pilots[1].formation_anchor_active, "CAP still supports wingman formation")
	pilots[1].clear_formation_guidance()
	pilots[1]._state_search(1.0 / 60.0)
	check(pilots[1].guided_point.z < -4000, "wingman leaving formation resumes assigned route")
	var contact := Node3D.new()
	add_child(contact)
	contact.position = (route[1] + route[2]) * 0.5
	check(pilots[0]._is_within_engagement_radius(contact, 500.0), "CAP engages near a remote route segment")
	contact.position = carrier.position
	check(not pilots[0]._is_within_engagement_radius(contact, 500.0), "remote CAP combat bounds do not remain attached to carrier")
	var shift := Vector3(20000, 0, -10000)
	pilots[0].apply_origin_shift(shift)
	contact.position = (route[1] + route[2]) * 0.5 - shift
	check(pilots[0]._is_within_engagement_radius(contact, 500.0), "floating origin preserves patrol engagement bounds")
	check(pilots[1].current_air_task.metadata.patrol_route[0] == route[0], "members do not share mutable route metadata")
	pilots[0].apply_origin_shift(-shift)
	# All patrol engagement modes retain their scope through combat and save/load.
	var ground := Node3D.new()
	add_child(ground)
	ground.add_to_group("ground_vehicles")
	ground.position = (route[1] + route[2]) * 0.5
	ground.position.y = 482.0
	for mode in ["air", "ground", "both"]:
		flight.set_cap_route(carrier, route, 800.0, mode)
		var pilot := pilots[0]
		check(pilot.ground_attack_enabled == (mode != "air"), "ground permission: " + mode)
		check(pilot._patrol_allows_air_engagement() == (mode != "ground"), "air permission: " + mode)
		check(pilot._is_valid_ground_attack_target(ground) == (mode != "air"), "ground target near patrol: " + mode)
		ground.position = carrier.position
		check(not pilot._is_valid_ground_attack_target(ground), "ground patrol never attacks at distant carrier: " + mode)
		ground.position = (route[1] + route[2]) * 0.5
		ground.position.y = 482.0
		pilot.known_enemies = [ground]
		var engaged: bool = pilot._evaluate_combat_objective(true)
		check(engaged == (mode != "air"), "patrol actually acquires permitted ground target: " + mode)
		check(pilot.current_air_task.metadata.patrol_engagement == mode, "engagement retains patrol intent: " + mode)
		pilot.known_enemies.clear()
		pilot.combat_target = null
		pilot.current_state = AIPilot.State.SEARCH
		pilot._flight_plan_name = "ground_attack"
		pilot._clear_attack_flight_plan()
		check(pilot.waypoints.is_empty(), "attack cleanup actually removed temporary route")
		pilot.clear_formation_guidance()
		pilot._state_search(1.0 / 60.0)
		check(pilot.waypoints.size() == 4 and pilot.guided_point.z < -4000, "combat exit resumes player patrol: " + mode)
		check(not pilot.waypoints_follow_carrier, "combat exit stays independent of carrier: " + mode)
		var saved := flight.capture_mission_save_state()
		flight.set_cap(carrier)
		check(flight.restore_mission_save_state(saved, carrier), "restore patrol: " + mode)
		check(flight.patrol_engagement == mode and pilots[1].current_air_task.metadata.patrol_engagement == mode, "save restores flight and wingman engagement: " + mode)
		check(flight.get_status_summary().mission == "PATROL", "unified patrol display")
	var track = preload("res://AI/VisualContactTrack.gd").new()
	track.observe(carrier.position, Vector3.ZERO, 0.0)
	pilots[0]._visual_contacts[123] = track
	pilots[0]._visual_clock_s = 1.0
	check(pilots[0]._dogfight_search_area().is_empty(), "remembered carrier contact cannot divert a remote patrol")
	track.observe((route[1] + route[2]) * 0.5, Vector3.ZERO, 0.0)
	check(not pilots[0]._dogfight_search_area().is_empty(), "Both patrol can search remembered air contact near its route")
	pilots[0].current_state = AIPilot.State.ATTACK_BREAK_OFF
	var old_task: Variant = pilots[0].current_air_task
	flight.set_cap_route(carrier, route, 800.0, "ground")
	check(pilots[0].current_air_task == old_task, "new patrol waits for committed ground attack egress")
	pilots[0].current_state = AIPilot.State.SEARCH
	flight._apply_pending_mission_updates()
	check(pilots[0].current_air_task.metadata.patrol_engagement == "ground", "pending patrol applies after egress")
	check(pilots[0]._dogfight_search_area().is_empty(), "Ground patrol does not pursue remembered air contacts")
	pilots[0]._visual_contacts.clear()
	# Changing back to a carrier CAP must restore its intended distance guard.
	flight.set_cap(carrier, 800.0)
	for pilot in pilots:
		pilot.clear_formation_guidance()
		pilot._state_search(1.0 / 60.0)
		check(not pilot._has_assigned_patrol_route() and pilot.current_air_task.metadata.carrier_relative, "carrier CAP releases route scope")
	check(pilots[0]._search_return_to_cap_active, "carrier CAP still returns an out-of-range aircraft")
	check(pilots[0].guided_point.x == carrier.position.x and pilots[0].guided_point.z == carrier.position.z, "carrier CAP return guides toward carrier")
	for failure in failures: push_error(failure)
	print("CAP_ROUTE_OWNERSHIP_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	get_tree().quit(0 if failures.is_empty() else 1)
