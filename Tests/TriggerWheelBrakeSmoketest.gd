extends "res://Tests/RoughLandingDamageSmoketest.gd"

class MovingDeck extends StaticBody3D:
	func get_deck_reference_velocity_vector() -> Vector3:
		return constant_linear_velocity

func _run() -> void:
	get_tree().create_timer(180.0).timeout.connect(func():
		push_error("TRIGGER_WHEEL_BRAKE_TIMEOUT")
		get_tree().quit(1))
	for singleton in ["AirOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector"]:
		var node := get_node_or_null("/root/" + singleton)
		if node != null: node.process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	add_ground()
	if "--steering-only" in OS.get_cmdline_user_args():
		await steering_cases()
		finish()
		return
	if "--contact-only" in OS.get_cmdline_user_args():
		await airborne_case()
		await moving_deck_case()
		finish()
		return
	for number in [1,2,3,4,5,6,7,8,14,16]:
		await input_case(number)
	await helicopter_case()
	for number in [5,16]:
		var coast := await rollout_case(number, 0.0)
		var half := await rollout_case(number, 0.525)
		var full := await rollout_case(number, 1.0)
		check(coast > half + 1.0 and half > full + 1.0, "%d braking not progressive: coast=%.2f half=%.2f full=%.2f" % [number,coast,half,full])
	await steering_cases()
	await airborne_case()
	await moving_deck_case()
	finish()

func finish() -> void:
	set_triggers(0, 0)
	for failure in failures: push_error(failure)
	print("TRIGGER_WHEEL_BRAKE_%s subset=%s" % ["PASS" if failures.is_empty() else "FAIL", OS.get_cmdline_user_args()])
	get_tree().quit(0 if failures.is_empty() else 1)

func set_triggers(left: float, right: float) -> void:
	Input.action_release("yaw_left")
	Input.action_release("yaw_right")
	if left > 0.0: Input.action_press("yaw_left", left)
	if right > 0.0: Input.action_press("yaw_right", right)

func input_case(number: int) -> void:
	var craft := spawn(number)
	while not craft.runtime_initialized: await get_tree().process_frame
	var controls := craft.find_child("ControlSteering", true, false) as AircraftModule_ControlSteering
	var gear := craft.get_node("LandingGear") as AircraftModule_LandingGear
	controls.ControlActive = true
	check(controls.landing_gear == gear, "%d controller missing gear connection" % number)
	for mode in [0,1]:
		craft.get_node("SimpleAero").set_flight_model_override_for_testing(mode)
		for values in [[0.0,0.0], [1.0,0.0], [0.0,1.0], [0.03,0.03], [0.525,0.525], [1.0,1.0], [1.0,0.525], [0.525,1.0]]:
			set_triggers(values[0], values[1])
			controls._physics_process(1.0/60.0)
			var expected := 0.0
			if values[0] >= 0.525 and values[1] >= 0.525: expected = 1.0 if values[0] == 1.0 and values[1] == 1.0 else 0.5
			check(absf(gear.get_wheel_brake_input() - expected) < 0.001, "%d mode=%d trigger pair %s brake=%.3f" % [number,mode,values,gear.get_wheel_brake_input()])
			check(signf(controls.telemetry_shaped_yaw) == signf(values[0] - values[1]), "%d trigger rudder direction lost" % number)
	set_triggers(1,1)
	controls._physics_process(1.0/60.0)
	controls.ControlActive = false
	controls._physics_process(1.0/60.0)
	check(gear.get_wheel_brake_input() == 0.0, "inactive controls retained brake")
	controls.ControlActive = true
	controls._physics_process(1.0/60.0)
	for frame in 3: await get_tree().physics_frame
	check(gear.get_wheel_brake_input() == 0.0, "stopped input processing retained brake")
	for flag in [&"controls_disabled", &"carrier_transport_mode", &"arresting_engaged"]:
		controls._physics_process(1.0/60.0)
		craft.set_meta(flag, true)
		check(gear.get_wheel_brake_input() == 0.0, "brakes fought %s" % flag)
		craft.remove_meta(flag)
	controls._physics_process(1.0/60.0)
	gear.is_deployed = false
	check(gear.get_wheel_brake_input() == 0.0, "stowed gear retained brake")
	gear.is_deployed = true
	gear.damage_collapsed = true
	check(gear.get_wheel_brake_input() == 0.0, "sheared gear retained brake")
	set_triggers(0,0)
	await clear_aircraft()

func helicopter_case() -> void:
	var craft := spawn(9)
	while not craft.runtime_initialized: await get_tree().process_frame
	var controls := craft.find_child("ControlSteering", true, false) as AircraftModule_ControlSteering
	controls.ControlActive = true
	set_triggers(1,1)
	controls._physics_process(1.0/60.0)
	check(controls._is_helicopter_controls, "helicopter fixture not recognized")
	check(craft.get_node("LandingGear").get_wheel_brake_input() == 0.0, "fixed-wing wheel brakes applied to helicopter")
	set_triggers(0,0)
	await clear_aircraft()

func settled_aircraft(number: int) -> Aircraft:
	var craft := spawn(number)
	while not craft.runtime_initialized: await get_tree().process_frame
	craft.position = Vector3(0,3.0,0)
	craft.get_node("Engine").engine_stop()
	craft.get_node("SimpleAero").set_flight_model_override_for_testing(1)
	craft.freeze = false
	for frame in 180: await get_tree().physics_frame
	check(not craft._has_exploded and not bool(craft.get_meta("gear_sheared", false)), "%d could not settle on intact wheels" % number)
	return craft

func rollout_case(number: int, pressure: float) -> float:
	var craft := await settled_aircraft(number)
	var controls := craft.find_child("ControlSteering", true, false) as AircraftModule_ControlSteering
	controls.ControlActive = true
	set_triggers(pressure, pressure)
	craft.linear_velocity = Vector3(0,0,20)
	var two_second_speed := 0.0
	var minimum_forward_speed := 20.0
	for frame in 480:
		controls._physics_process(1.0/60.0)
		await get_tree().physics_frame
		if frame == 119: two_second_speed = craft.linear_velocity.length()
		minimum_forward_speed = minf(minimum_forward_speed, craft.linear_velocity.z)
	check(not craft._has_exploded and not bool(craft.get_meta("gear_sheared", false)), "%d brake damaged aircraft" % number)
	check(craft.global_basis.y.dot(Vector3.UP) > 0.95, "%d brake tipped aircraft" % number)
	if pressure == 1.0:
		check(craft.linear_velocity.length() < 0.3, "%d full brake did not stop: %.3f" % [number,craft.linear_velocity.length()])
		check(minimum_forward_speed > -0.2, "%d brake reversed the aircraft" % number)
	print("WHEEL_BRAKE_ROLLOUT aircraft=",number," pressure=",pressure," speed_2s=",two_second_speed," speed_8s=",craft.linear_velocity.length())
	set_triggers(0,0)
	await clear_aircraft()
	return two_second_speed

func steering_cases() -> void:
	var unbraked_turn := await steering_case(0.5, 0.0)
	var left_turn := await steering_case(0.9, 0.4)
	var right_turn := await steering_case(0.4, 0.9)
	check(left_turn > unbraked_turn * 0.5 and -right_turn > unbraked_turn * 0.5, "brakes suppressed existing nose-wheel steering")

func steering_case(left: float, right: float) -> float:
	var craft := await settled_aircraft(5)
	var controls := craft.find_child("ControlSteering", true, false) as AircraftModule_ControlSteering
	controls.ControlActive = true
	craft.linear_velocity = Vector3(0,0,7)
	var start_heading := craft.rotation.y
	set_triggers(left, right)
	for frame in 120:
		controls._physics_process(1.0/60.0)
		await get_tree().physics_frame
	var heading_change := angle_difference(start_heading, craft.rotation.y)
	check(absf(heading_change) > deg_to_rad(0.25), "nose wheel did not steer under braking")
	check(signf(heading_change) == signf(left-right), "nose wheel steered against trigger command")
	if minf(left,right) > 0.0: check(craft.linear_velocity.length() < 5.0, "steering prevented braking")
	print("WHEEL_BRAKE_STEERING left=",left," right=",right," turn_deg=",rad_to_deg(heading_change)," speed=",craft.linear_velocity.length())
	set_triggers(0,0)
	await clear_aircraft()
	return heading_change

func airborne_case() -> void:
	var coast := spawn(5)
	var braked := spawn(5)
	while not coast.runtime_initialized or not braked.runtime_initialized: await get_tree().process_frame
	coast.position = Vector3(-100,500,0)
	braked.position = Vector3(100,500,0)
	for craft in [coast,braked]:
		craft.get_node("SimpleAero").set_physics_process(false)
		craft.get_node("Engine").engine_stop()
		craft.find_child("ControlSteering", true, false).ControlActive = true
		craft.freeze = false
		craft.linear_velocity = Vector3(0,0,60)
	for frame in 90:
		set_triggers(0,0)
		coast.find_child("ControlSteering", true, false)._physics_process(1.0/60.0)
		set_triggers(1,1)
		braked.find_child("ControlSteering", true, false)._physics_process(1.0/60.0)
		await get_tree().physics_frame
	check(coast.linear_velocity.distance_to(braked.linear_velocity) < 0.01, "wheel brakes slowed an airborne aircraft")
	check(not braked.get_node("LandingGear").gear_has_contact.has(true), "airborne fixture contacted ground")
	print("WHEEL_BRAKE_AIRBORNE velocity_difference=",coast.linear_velocity.distance_to(braked.linear_velocity))
	set_triggers(0,0)
	await clear_aircraft()

func moving_deck_case() -> void:
	# Settle on terrain first: this fixture checks rolling brakes, not carrier
	# touchdown damage. Replace the support without dropping onto a moving deck.
	var craft := await settled_aircraft(5)
	var floor_body := host.get_node("TerrainFixture") as StaticBody3D
	floor_body.collision_layer = 0
	floor_body.collision_mask = 0
	var deck := MovingDeck.new()
	deck.add_to_group("carrier")
	deck.constant_linear_velocity = Vector3(0,0,12)
	deck.add_child(floor_body.get_child(0).duplicate())
	host.add_child(deck)
	VelocityFrame.set_reference_node(craft, deck)
	# Isolate service braking from the existing engine-off parking hold and thrust.
	var engine := craft.get_node("Engine") as AircraftModule_Engine
	engine.is_engine_working = true
	engine.current_power = 0.0
	engine.target_power = 0.0
	craft.get_node("SimpleAero").set_physics_process(false)
	var controls := craft.find_child("ControlSteering", true, false) as AircraftModule_ControlSteering
	controls.ControlActive = true
	craft.linear_velocity = Vector3(0,0,24)
	set_triggers(1,1)
	for frame in 360:
		controls._physics_process(1.0/60.0)
		await get_tree().physics_frame
		check(craft.get_node("LandingGear").get_wheel_brake_input() > 0.99, "moving-deck test lost service brake input")
		check(engine.is_engine_working, "moving-deck test substituted engine-off parking hold")
		if frame == 119:
			check(VelocityFrame.get_relative_velocity(craft).length() < 6.0, "moving-deck service brake did not slow rollout")
	var relative_speed: float = VelocityFrame.get_relative_velocity(craft).length()
	check(relative_speed < 0.3 and absf(craft.linear_velocity.z - 12.0) < 0.3, "brake stopped relative to world instead of moving deck")
	check(not craft._has_exploded and not craft._critical_damage_active and craft.global_basis.y.dot(Vector3.UP) > 0.95, "moving-deck braking damaged or tipped aircraft")
	print("WHEEL_BRAKE_MOVING_DECK relative_speed=",relative_speed," world_speed=",craft.linear_velocity.z)
	set_triggers(0,0)
	await clear_aircraft()
	deck.queue_free()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 1
