extends SceneTree

## Full circuit with the real aircraft physics, through the Flight patrol API.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var carrier := Node3D.new()
	world.add_child(carrier)
	carrier.position = Vector3(-1200, 0, -1200)
	carrier.add_to_group("carrier")
	var craft = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	craft.freeze = true
	craft.position = Vector3(-1200, 1200, -1200)
	world.add_child(craft)
	await process_frame
	craft.get_node("AIToggle").enable_ai()
	var pilot = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	pilot.current_state = pilot.State.SEARCH
	pilot._terrain_height_callable = func(_position: Vector3) -> float: return 0.0
	craft.get_node("SimpleAero").set_flight_model_override_for_testing(1)
	craft.get_node("ControlLandingGear").send_to_landing_gears("stow")
	if "--loaded" in OS.get_cmdline_user_args():
		craft.set_payload_mass(pilot, maxf(1653.6 - craft.mass, 0.0))
	var flight = load("res://AirOps/Flight.gd").new()
	world.add_child(flight)
	flight.set_physics_process(false)
	flight.register(craft)
	craft.freeze = false
	await physics_frame
	await process_frame
	await physics_frame
	craft.position = Vector3(-1200, 1200, -1200)
	craft.rotation_degrees = Vector3(0, 45, 0)
	craft.linear_velocity = Vector3(70.71, 0, 70.71)
	craft.angular_velocity = Vector3.ZERO
	var route: Array[Vector3] = [Vector3(0,1200,0), Vector3(1800,1200,0), Vector3(1800,1200,1800), Vector3(0,1200,1800)]
	flight.set_cap_route(carrier, route, 1200.0)
	var transitions: Array[int] = [pilot.current_waypoint_index]
	var nearest: Array[float] = [INF, INF, INF, INF]
	for step in range(14400):
		await physics_frame
		pilot.altitude_agl = craft.position.y
		flight._physics_process(1.0 / 60.0)
		pilot._state_search(1.0 / 60.0)
		pilot._apply_controls()
		for i in range(route.size()):
			nearest[i] = minf(nearest[i], craft.position.distance_to(route[i]))
		if transitions.back() != pilot.current_waypoint_index:
			transitions.append(pilot.current_waypoint_index)
			print("PATROL_CIRCUIT_ADVANCE ", JSON.stringify({"t":step/60.0,"index":pilot.current_waypoint_index,"position":craft.position,"reason":pilot._route_last_advance_reason}))
		if step % 1800 == 0:
			print("PATROL_CIRCUIT_SAMPLE ", JSON.stringify({"t":step/60.0,"index":pilot.current_waypoint_index,"position":craft.position,"speed":craft.linear_velocity.length(),"debug":pilot._route_follow_debug}))
		if transitions.size() >= 9: break
	var passed := transitions.size() >= 9
	for i in range(transitions.size()):
		passed = passed and transitions[i] == i % 4
	for distance in nearest: passed = passed and distance < 800.0
	print("PATROL_CIRCUIT_%s transitions=%s nearest=%s" % ["PASS" if passed else "FAIL", transitions, nearest])
	world.free()
	quit(0 if passed else 1)
