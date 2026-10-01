extends Node

class ProbePilot extends AIPilot:
	func _ready() -> void: pass
	func _navigate_to_waypoint(_delta: float) -> void: pass

var failures: Array[String] = []
func check(ok: bool, description: String) -> void:
	if not ok: failures.append(description)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for child in get_tree().root.get_children():
		if child != self: child.process_mode = Node.PROCESS_MODE_DISABLED
	var carrier := Node3D.new()
	add_child(carrier)
	carrier.position = Vector3(-1200, 0, -1200)
	carrier.add_to_group("carrier")
	var craft := RigidBody3D.new()
	craft.freeze = true
	add_child(craft)
	craft.position = Vector3(-1200, 1200, -1200)
	var pilot := ProbePilot.new()
	pilot.name = "AIPilot"
	craft.add_child(pilot)
	pilot.set_physics_process(false)
	pilot.aircraft = craft
	pilot.current_state = AIPilot.State.SEARCH
	pilot._terrain_height_callable = func(_point: Vector3) -> float: return 0.0
	var flight := Flight.new()
	add_child(flight)
	flight.set_physics_process(false)
	flight.register(craft)
	var route: Array[Vector3] = [Vector3(0,1200,0), Vector3(1800,1200,0), Vector3(1800,1200,1800), Vector3(0,1200,1800)]
	flight.set_cap_route(carrier, route, 1200.0)
	flight._apply_pending_mission_updates()
	# A normal fly-by misses the exact point by more than the 120m capture sphere.
	craft.position = Vector3(200,1200,-200)
	craft.linear_velocity = Vector3(100,0,0)
	pilot._state_search(1.0/60.0)
	print("PATROL_FIRST_FLYBY index=%d debug=%s" % [pilot.current_waypoint_index, pilot._route_follow_debug])
	check(pilot.current_waypoint_index == 1, "passing the first patrol corner advances instead of demanding a return to its center")
	check(pilot._flight_plan_loop and not pilot.waypoints_follow_carrier, "assigned patrol is a fixed world loop")
	# Exercise the same miss on every corner and across two complete circuits.
	var passed_positions: Array[Vector3] = [Vector3(200,1200,-200), Vector3(2000,1200,200), Vector3(1600,1200,2000), Vector3(-200,1200,1600)]
	var velocities: Array[Vector3] = [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]
	for step in range(1,8):
		var corner := step % 4
		craft.position = passed_positions[corner]
		craft.linear_velocity = velocities[corner] * 100
		flight._physics_process(1.0/60.0)
		pilot._state_search(1.0/60.0)
		check(pilot.current_waypoint_index == (corner+1)%4, "patrol advances corner %d on circuit %d" % [corner,step/4])
	check(pilot.get_active_waypoints().size() == 4, "active map route retains the closing leg")
	# Combat cleanup must reinstall the same loop semantics.
	pilot._flight_plan_name = "ground_attack"
	pilot._clear_attack_flight_plan()
	pilot._setup_patrol_waypoints()
	check(pilot._flight_plan_loop and not pilot.waypoints_follow_carrier, "combat exit restores a fixed patrol loop")
	for failure in failures: push_error(failure)
	print("PATROL_WAYPOINT_PROGRESSION_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL",failures])
	get_tree().quit(0 if failures.is_empty() else 1)
