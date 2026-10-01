extends SceneTree

## Reproduce Archer's captured two-aircraft ingress: both heading away from a
## virtual ground platoon, with the wingman roughly 2 km from its leader.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var flight = load("res://AirOps/Flight.gd").new()
	world.add_child(flight)
	flight.set_physics_process(false)
	var platoon = load("res://Enemies/EnemyVirtualPlatoon.gd").new()
	platoon.position = Vector3(-4202.31, 482, 164.78)
	platoon.vehicle_count = 4
	world.add_child(platoon)
	var cases: Array[Dictionary] = [
		{"position": Vector3(-169.539, 1229.384, -680.978), "rotation": Vector3(-0.143717, 2.413668, -0.436268),
		"velocity": Vector3(64.578, 9.547, -62.229), "angular": Vector3(0.105276, 0.108151, 0.128362)},
		{"position": Vector3(1704.481, 1506.372, 135.527), "rotation": Vector3(-0.364896, 1.781346, -0.001487),
		"velocity": Vector3(63.114, 19.618, -13.193), "angular": Vector3(0.000115, -0.005297, 0.005617)},
	]
	for item in cases:
		var craft = load("res://Aircraft/Aircraft_5.tscn").instantiate()
		craft.freeze = true
		craft.position = item.position
		world.add_child(craft)
		craft.get_node("AIToggle").enable_ai()
		craft.get_node("ControlLandingGear").send_to_landing_gears("stow")
		craft.get_node("SimpleAero").set_flight_model_override_for_testing(1)
		var pilot = craft.get_node("AIPilot")
		pilot.set_physics_process(false)
		pilot._terrain_height_callable = func(_position: Vector3) -> float: return 482.0
		pilot.current_state = pilot.State.SEARCH
		flight.register(craft)
		item.craft = craft
		item.pilot = pilot
		item.capture_s = -1.0
		item.initial_distance = Vector2(craft.position.x - platoon.position.x, craft.position.z - platoon.position.z).length()
		craft.freeze = false
	await physics_frame
	await process_frame
	await physics_frame
	for item in cases:
		item.craft.position = item.position
		item.craft.rotation = item.rotation
		item.craft.linear_velocity = item.velocity
		item.craft.angular_velocity = item.angular
	flight.set_attack(platoon.position, null, 100.0, 300.0, platoon)
	var failed := false
	for step in range(1800):
		await physics_frame
		platoon.position.z += 6.0 / 60.0
		flight._physics_process(1.0 / 60.0)
		for item in cases:
			var pilot = item.pilot
			var craft = item.craft
			pilot.altitude_agl = craft.position.y - 482.0
			pilot._state_search(1.0 / 60.0)
			pilot._apply_controls()
			failed = failed or pilot.formation_anchor_active or pilot.formation_speed_cap_mps >= 0.0
			var to_target: Vector3 = platoon.position - craft.position
			var velocity: Vector3 = craft.linear_velocity
			var error_deg := absf(rad_to_deg(wrapf(atan2(to_target.x, to_target.z) - atan2(velocity.x, velocity.z), -PI, PI)))
			if item.capture_s < 0.0 and error_deg < 15.0:
				item.capture_s = step / 60.0
			item.final_error = error_deg
			item.final_distance = Vector2(to_target.x, to_target.z).length()
			if step % 600 == 0:
				print("ATTACK_INGRESS_SAMPLE ", JSON.stringify({"t": step / 60.0, "name": craft.name, "error_deg": error_deg,
					"distance": item.final_distance, "bank": craft.rotation_degrees.z, "target_bank": pilot._coordinated_turn_target_bank_deg}))
	for item in cases:
		var passed: bool = item.capture_s >= 0.0 and item.capture_s < 25.0 and item.final_error < 15.0 and item.final_distance < item.initial_distance - 500.0
		failed = failed or not passed
		print("ATTACK_INGRESS_CASE_%s capture_s=%.2f error_deg=%.2f distance=%.0f initial_distance=%.0f" % ["PASS" if passed else "FAIL", item.capture_s, item.final_error, item.final_distance, item.initial_distance])
	print("ATTACK_INGRESS_TURN_%s" % ("FAIL" if failed else "PASS"))
	world.free()
	quit(1 if failed else 0)
