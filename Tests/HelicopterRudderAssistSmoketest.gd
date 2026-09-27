extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var pause_menu := root.get_node_or_null("PauseMenu")
	var aircraft := load("res://Aircraft/Aircraft_13.tscn").instantiate() as RigidBody3D
	if pause_menu == null or aircraft == null:
		_fail("menu or Aircraft_13 missing")
		return
	var old_level: int = pause_menu.get("_helicopter_rudder_assist_level")
	root.add_child(aircraft)
	await process_frame
	aircraft.freeze = true
	var controls := aircraft.get_node("ControlSteering") as AircraftModule_ControlSteering
	var aero := aircraft.get_node("SimpleAero")
	controls.set_physics_process(false)
	_check(controls._is_helicopter_controls, "Aircraft_13 did not select helicopter assist")
	var off := _sample_roll_correction(pause_menu, aircraft, controls, aero, 0, "roll_right", 32.0)
	var slow_roll := _sample_roll_correction(pause_menu, aircraft, controls, aero, 2, "roll_right", 0.0)
	var light := _sample_roll_correction(pause_menu, aircraft, controls, aero, 1, "roll_right", 32.0)
	var transition := _sample_roll_correction(pause_menu, aircraft, controls, aero, 2, "roll_right", 20.0)
	var full := _sample_roll_correction(pause_menu, aircraft, controls, aero, 2, "roll_right", 32.0)
	var left := _sample_roll_correction(pause_menu, aircraft, controls, aero, 2, "roll_left", 32.0)
	_check(absf(off) < 0.001, "OFF still commands rudder")
	_check(absf(slow_roll) < 0.001, "slow right cyclic triggered autorudder")
	_check(light < -0.07, "LIGHT does not yaw toward right cyclic")
	_check(transition < -0.05 and transition > full * 0.75, "autorudder did not fade with forward speed")
	_check(full < light * 1.5, "FULL is not stronger than LIGHT during right cyclic")
	_check(left > 0.15, "left cyclic did not reverse assisted yaw")
	controls._reset_rudder_assist_state()
	aircraft.linear_velocity = aircraft.global_basis.x * -4.0
	var slow_slide := 0.0
	for i in 18:
		slow_slide = controls._apply_rudder_assist(0.0, 1.0 / 60.0, 0.8)
	_check(absf(slow_slide) < 0.001, "slow sideways slide triggered autorudder")
	controls._reset_rudder_assist_state()
	aircraft.linear_velocity = aircraft.global_basis.z * 32.0 - aircraft.global_basis.x * 4.0
	var lateral := 0.0
	for i in 18:
		lateral = controls._apply_rudder_assist(0.0, 1.0 / 60.0)
	_check(lateral < -0.05, "forward-flight sideslip received no yaw correction")
	var manual := controls._apply_rudder_assist(0.25, 1.0 / 60.0)
	_check(absf(manual - 0.25) < 0.001, "deliberate pedals did not override assisted yaw")
	pause_menu.set("_helicopter_rudder_assist_level", old_level)
	aircraft.queue_free()
	await process_frame
	if failures.is_empty():
		print("HELICOPTER_RUDDER_ASSIST_PASS off=%.3f slow_roll=%.3f slow_slide=%.3f transition=%.3f light=%.3f full=%.3f left=%.3f lateral=%.3f manual=%.3f" % [off, slow_roll, slow_slide, transition, light, full, left, lateral, manual])
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _sample_roll_correction(pause_menu: Node, aircraft: RigidBody3D,
		controls: AircraftModule_ControlSteering, aero: Node,
		level: int, action: StringName, forward_speed: float) -> float:
	pause_menu.set("_helicopter_rudder_assist_level", level)
	controls._reset_rudder_assist_state()
	aircraft.rotation = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.linear_velocity = aircraft.global_basis.z * forward_speed
	Input.action_press(action, 1.0)
	for i in 18:
		controls._physics_process(1.0 / 60.0)
	Input.action_release(action)
	var yaw: float = aero.get("yaw_input")
	if level > 0 and forward_speed > 8.0:
		for i in 5:
			aero.call("_update_disc_tilt", 1.0, 0.0)
		var rotor_direction: Vector3 = aero.call("_get_rotor_direction")
		var lateral_thrust := rotor_direction.dot(aircraft.global_basis.x)
		_check(yaw * lateral_thrust > 0.0, "assisted yaw points away from %s rotor thrust" % action)
	return yaw

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
