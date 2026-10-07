extends SceneTree

class FlatTerrain extends Node3D:
	func get_height(_position: Vector3) -> float:
		return 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(120.0).timeout.connect(func():
		push_error("AIRCRAFT16_LOADED_FLIGHT_FAIL timeout")
		quit(2))
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := FlatTerrain.new()
	world.add_child(ground)
	ground.add_to_group("terrain_provider")
	root.get_node("TerrainReference").terrain_node = ground
	for name in ["AirOpsManager", "FlightDirector"]:
		var manager := root.get_node_or_null(name)
		if manager:
			manager.set_process(false)
			manager.set_physics_process(false)
	var craft := load("res://Aircraft/Aircraft_16.tscn").instantiate() as RigidBody3D
	craft.position = Vector3(0, 800, 0)
	craft.freeze = true
	world.add_child(craft)
	await process_frame
	var engine := craft.get_node("Engine")
	engine.is_engine_working = true
	engine.current_power = 1.0
	engine.target_power = 1.0
	engine.throttle_input = 1.0
	var pilot := craft.get_node("AIPilot")
	craft.get_node("AIToggle").enable_ai()
	pilot.clear_air_task()
	pilot.patrol_altitude_m = 800.0
	pilot.nav_waypoint = Vector3(0, 800, 3000)
	pilot.dogfight_enabled = false
	pilot.ground_attack_enabled = false
	var route: Array[Vector3] = [Vector3(0, 800, 3000), Vector3(2500, 800, 4500)]
	pilot.set_waypoints(route, false, [90.0, 90.0])
	pilot.set_target_altitude(800.0)
	pilot.change_state(pilot.State.SEARCH)
	craft.get_node("SimpleAero").set_flight_model_override_for_testing(1)
	craft.freeze = false
	await physics_frame
	craft.linear_velocity = Vector3(0, 0, 90)
	craft.sleeping = false
	var minimum_altitude := 800.0
	var minimum_speed := 90.0
	for tick in 1800:
		await physics_frame
		if not is_instance_valid(craft) or craft.is_queued_for_deletion():
			push_error("AIRCRAFT16_LOADED_FLIGHT_FAIL aircraft destroyed")
			quit(1)
			return
		minimum_altitude = minf(minimum_altitude, craft.position.y)
		minimum_speed = minf(minimum_speed, craft.linear_velocity.length())
		if tick % 300 == 299:
			print("AIRCRAFT16_LOADED tick=", tick + 1, " mass=", craft.mass, " position=", craft.position,
				" speed=", craft.linear_velocity.length(), " pitch=", craft.rotation_degrees.x,
				" ai_pitch=", pilot.pitch_input, " aero_pitch=", craft.get_node("SimpleAero").pitch_input,
				" state=", pilot.current_state, " target_alt=", pilot.target_altitude,
				" lift=", craft.get_node("SimpleAero").get_estimated_lift_ratio())
	var okay: bool = minimum_altitude > 650.0 and craft.position.z > 1800.0 and not craft.get("_critical_damage_active")
	print("AIRCRAFT16_LOADED_FLIGHT_", "PASS" if okay else "FAIL",
		" minimum_altitude=", minimum_altitude, " minimum_speed=", minimum_speed)
	craft.queue_free()
	await process_frame
	quit(0 if okay else 1)
