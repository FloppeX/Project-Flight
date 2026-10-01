extends SceneTree

## Paired old/new approach lineup response with real aircraft aerodynamics. revised=true selects the revised response.
## Run headless with --fixed-fps 60 --script res://Tests/ApproachLineupResponseProbe.gd.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var cases: Array[Dictionary] = []
	for revised in [false, true]:
		for bearing in [-10.0, 10.0]:
			var craft = load("res://Aircraft/Aircraft_5.tscn").instantiate()
			craft.freeze = true
			var origin := Vector3(cases.size() * 30000.0, 1800, 0)
			craft.position = origin
			world.add_child(craft)
			craft.get_node("AIToggle").enable_ai()
			var pilot = craft.get_node("AIPilot")
			pilot.set_physics_process(false)
			pilot.current_state = pilot.State.APPROACH
			pilot._terrain_height_callable = func(_position: Vector3) -> float: return 0.0
			pilot.target_speed = 65.0
			pilot.target_altitude = origin.y
			craft.get_node("SimpleAero").set_flight_model_override_for_testing(1)
			craft.get_node("ControlLandingGear").send_to_landing_gears("stow")
			var angle := deg_to_rad(bearing)
			cases.append({"craft":craft, "pilot":pilot, "origin":origin,
				"target":origin + Vector3(sin(angle), 0, cos(angle)) * 4000.0,
				"bearing":bearing, "revised":revised, "capture_s":-1.0,
				"late_error_sum":0.0, "late_samples":0, "max_bank":0.0})
			craft.freeze = false
	await physics_frame
	await process_frame
	await physics_frame
	for item in cases:
		item.craft.position = item.origin
		item.craft.rotation = Vector3.ZERO
		item.craft.linear_velocity = Vector3(0, 0, 65)
		item.craft.angular_velocity = Vector3.ZERO
	for step in range(1200):
		await physics_frame
		for item in cases:
			var craft = item.craft
			var pilot = item.pilot
			pilot.altitude_agl = craft.position.y
			pilot.nav_waypoint = item.target
			# SEARCH can receive a distant contact point directly; TRANSIT uses a carrot.
			pilot.maneuver_waypoint = item.target
			if pilot.current_state == pilot.State.TRANSIT:
				pilot._update_maneuver_waypoint()
			pilot._navigate_to_waypoint(1.0 / 60.0)
			pilot._apply_precision_horizontal_guidance(item.target, 25.0, pilot.approach_precision_bank_gain if item.revised else 1.5, 2.0, pilot.approach_precision_yaw_gain if item.revised else 2.8, pilot.approach_precision_roll_response if item.revised else 0.42, pilot.approach_precision_yaw_response if item.revised else 0.32, 1.0)
			pilot._apply_controls()
			var to_target: Vector3 = item.target - craft.position
			var velocity: Vector3 = craft.linear_velocity
			var error_deg := absf(rad_to_deg(wrapf(atan2(to_target.x, to_target.z)
				- atan2(velocity.x, velocity.z), -PI, PI)))
			if error_deg < 1.0 and item.capture_s < 0:
				item.capture_s = step / 60.0
			item.max_bank = maxf(item.max_bank, absf(craft.rotation_degrees.z))
			if step >= 900:
				item.late_error_sum += error_deg
				item.late_samples += 1
			if step % 600 == 0:
				print("APPROACH_SAMPLE ", JSON.stringify({"t":step / 60.0,
					"bearing":item.bearing,"revised":item.revised,"error":error_deg,
					"bank":craft.rotation_degrees.z,"bank_target":pilot._coordinated_turn_target_bank_deg,
					"speed":velocity.length(),"altitude":craft.position.y}))
	var failed := false
	for revised_case in cases:
		if not revised_case.revised:
			continue
		for baseline in cases:
			if baseline.revised or baseline.bearing != revised_case.bearing:
				continue
			if revised_case.capture_s > baseline.capture_s or revised_case.max_bank > 25.0:
				failed = true
				push_error("Approach must capture sooner without exceeding its bank limit")
	for item in cases:
		var late_error: float = item.late_error_sum / maxf(item.late_samples, 1)
		var passed: bool = item.capture_s >= 0 and item.capture_s <= 15.0 and late_error < 2.0
		failed = failed or not passed
		print("APPROACH_CASE_%s bearing=%.0f revised=%s capture_s=%.2f late_error=%.2f max_bank=%.1f" % [
			"PASS" if passed else "FAIL", item.bearing, item.revised, item.capture_s, late_error, item.max_bank])
	print("APPROACH_TURN_CAPTURE_%s" % ("FAIL" if failed else "PASS"))
	world.free()
	quit(1 if failed else 0)
