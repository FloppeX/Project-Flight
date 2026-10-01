extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var craft = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	craft.freeze = true
	craft.position = Vector3(0, 1200, 0)
	world.add_child(craft)
	await process_frame
	craft.get_node("AIToggle").enable_ai()
	var pilot = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	pilot.current_state = pilot.State.SEARCH
	pilot._terrain_height_callable = func(_position: Vector3) -> float: return 0.0
	pilot.dogfight_enabled = true
	pilot.ground_attack_enabled = false
	pilot.engagement_radius_from_carrier_m = 0.0
	pilot.disengage_radius_from_carrier_m = 0.0
	var aero = craft.get_node("SimpleAero")
	aero.set_flight_model_override_for_testing(1)
	craft.get_node("ControlLandingGear").send_to_landing_gears("stow")
	craft.set_payload_mass(pilot, maxf(1653.6 - craft.mass, 0.0))
	craft.freeze = false
	# Let deferred spawn/unfreeze physics state settle before installing flight state.
	await physics_frame
	await process_frame
	await physics_frame
	craft.position = Vector3(0, 1200, 0)
	craft.rotation_degrees = Vector3(4.04, 40.11, -30.78)
	craft.linear_velocity = Vector3(62.30, -7.17, 74.22)
	craft.angular_velocity = Vector3(0.0217, -0.0161, -0.0762)
	var track = load("res://AI/VisualContactTrack.gd").new()
	track.observe(Vector3(2632.56, 761.44, -3658.99), Vector3.ZERO, 0.0)
	pilot._visual_contacts[123] = track
	var initial_heading: float = atan2(craft.global_basis.z.x, craft.global_basis.z.z)
	var load_sum := 0.0
	var load_error_sum := 0.0
	var sample_count := 0
	var failed := false
	for step in range(900):
		await physics_frame
		pilot._visual_clock_s = step / 60.0
		pilot.altitude_agl = craft.position.y
		# Reproduce the conflicting formation command being supplied each frame.
		pilot.set_formation_anchor(Vector3(-210, 1336, 5))
		pilot.set_formation_handling(0, 0, deg_to_rad(25.3), 13.5)
		pilot.set_formation_speed_guidance(109.4, 29.4)
		pilot._state_search(1.0 / 60.0)
		pilot._apply_controls()
		failed = failed or pilot.formation_anchor_active
		if step >= 300:
			load_sum += aero.get_estimated_lift_ratio()
			load_error_sum += absf(aero.get_estimated_lift_ratio() - pilot._coordinated_turn_target_g)
			sample_count += 1
		if step % 180 == 0:
			print("LOADED_TURN_SAMPLE ", JSON.stringify({"seconds":step / 60.0,"bank":craft.rotation_degrees.z,"heading":rad_to_deg(atan2(craft.global_basis.z.x,craft.global_basis.z.z)),"load_g":aero.get_estimated_lift_ratio(),"target_g":pilot._coordinated_turn_target_g,"speed":craft.linear_velocity.length(),"altitude":craft.position.y,"commands":[pilot.pitch_input,pilot.roll_input,pilot.yaw_input,pilot.throttle_input],"aero_controls":[aero.actual_pitch_control,aero.actual_roll_control,aero.actual_yaw_control],"bank_target":pilot._coordinated_turn_target_bank_deg,"aoa":aero.get_estimated_angle_of_attack_deg()}))
	var heading_change := rad_to_deg(wrapf(atan2(craft.global_basis.z.x, craft.global_basis.z.z) - initial_heading, -PI, PI))
	var average_load := load_sum / maxf(sample_count, 1)
	var average_load_error := load_error_sum / maxf(sample_count, 1)
	# The search point is below us, so a sub-1G descending turn is intentional.
	# What matters is acquiring the commanded wing load instead of half of it.
	failed = failed or heading_change < 25.0 or average_load_error > 0.15
	print("LOADED_PATROL_TURN_%s heading_change=%.1f average_load_g=%.3f load_error_g=%.3f mass=%.1f" % ["FAIL" if failed else "PASS", heading_change, average_load, average_load_error, craft.mass])
	craft.free()
	quit(1 if failed else 0)
