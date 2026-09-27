extends "res://Tests/Aircraft5ControlAuthorityInvestigation.gd"

class FlatTerrain extends Node3D:
	func get_height(_p: Vector3) -> float: return 0.0

func _run() -> void:
	var terrain := FlatTerrain.new()
	add_child(terrain)
	get_node("/root/TerrainReference").terrain_node = terrain
	var trials := await _spawn_trials([
		{"name":"left", "speed_mps":65.0},
		{"name":"right", "speed_mps":65.0},
		{"name":"calm", "speed_mps":65.0},
	])
	var aircraft: RigidBody3D = trials[0].aircraft
	var aero: SimpleAero = trials[0].aero
	var samples: Array[Dictionary] = []
	aero.force_audit_sample.connect(func(sample: Dictionary): samples.append(sample))
	var payload := Node.new()
	add_child(payload)
	# Match velocity, attitude, flaps and wing across a payload change.
	# Sample actual applied forces as well as the AI's estimated load.
	aircraft.global_basis = Basis.IDENTITY
	aircraft.linear_velocity = Vector3(0, 0, 55)
	aero._physics_process(1.0 / 60.0)
	var unloaded_force: Vector3 = samples.back().lift
	var initial_mass := aircraft.mass
	aircraft.call("set_payload_mass", payload, initial_mass * 0.3)
	aero._physics_process(1.0 / 60.0)
	var loaded_force: Vector3 = samples.back().lift
	_expect(unloaded_force.is_equal_approx(loaded_force), "payload must not manufacture extra lift")
	_expect(loaded_force.y / aircraft.mass < unloaded_force.y / initial_mass * 0.8, "payload must reduce upward acceleration")
	_expect(absf(aero.get_estimated_lift_ratio() - float(samples.back().load)) < 0.0001, "AI lift estimate must match applied load, including speed loss and payload")
	print("NATURAL_DEPARTURE_MASS before=%.1f after=%.1f lift_before=%.1f lift_after=%.1f" % [initial_mass, aircraft.mass, unloaded_force.y, loaded_force.y])
	aero._resolve_flaps_module()
	var flaps: Node = aero._flaps_module
	_expect(is_instance_valid(flaps), "production aircraft must expose flaps")
	if is_instance_valid(flaps):
		for deployed in [0.0, 1.0]:
			flaps.set("flap_position", deployed)
			for velocity in [Vector3(0, -5, 55), Vector3(0, 0, 30)]:
				aircraft.linear_velocity = velocity
				aero._physics_process(1.0 / 60.0)
				_expect(absf(aero.get_estimated_lift_ratio() - float(samples.back().load)) < 0.0001, "AI load must match applied lift with flaps, AoA and low-speed loss")
		flaps.set("flap_position", 0.0)
	aero.set_flight_model_override_for_testing(0)
	_expect(is_equal_approx(aero.get_lift_reference_mass_kg(), aircraft.mass), "Simplified lift must retain its existing tuning")
	aero.set_flight_model_override_for_testing(1)
	aircraft.call("clear_payload_mass", payload)
	_expect(is_equal_approx(aircraft.mass, initial_mass), "jettison must restore the original mass")
	payload.queue_free()
	for i in trials.size():
		var body: RigidBody3D = trials[i].aircraft
		var wing: SimpleAero = trials[i].aero
		body.global_basis = Basis(Vector3.BACK, deg_to_rad([-8.0, 8.0, 0.0][i]))
		body.linear_velocity = Vector3.BACK * 65.0
		body.angular_velocity = Vector3.ZERO
		wing.stability_strength = 0.0 # Match AI ownership: no passive levelling.
		wing.auto_rudder_strength = 0.0
		var pilot := load("res://AI/AIPilot.gd").new() as Node
		# Detached controller avoids unrelated navigation, sensors and target logic.
		pilot.set("aircraft", body)
		trials[i]["pilot"] = pilot
		trials[i]["peak_bank"] = 0.0
	var elapsed := 0.0
	while elapsed < 8.0:
		for trial in trials:
			var body: RigidBody3D = trial.aircraft
			var wing: SimpleAero = trial.aero
			var pilot: Node = trial.pilot
			var command := float(pilot.call("_get_departure_level_roll_input"))
			wing.roll_input = -command if pilot.get("invert_roll_sign") else command
			# Test-only forward thrust keeps this a launch-speed roll experiment.
			body.apply_central_force(body.global_basis.z * maxf(65.0 - body.linear_velocity.dot(body.global_basis.z), 0.0) * body.mass * 2.0)
		await get_tree().physics_frame
		elapsed += _physics_delta()
		for trial in trials:
			var body: RigidBody3D = trial.aircraft
			var bank := absf(rad_to_deg(atan2(body.global_basis.x.y, body.global_basis.y.y)))
			trial.peak_bank = maxf(trial.peak_bank, bank)
	for trial in trials:
		var body: RigidBody3D = trial.aircraft
		var bank := absf(rad_to_deg(atan2(body.global_basis.x.y, body.global_basis.y.y)))
		print("NATURAL_DEPARTURE_ROLL %s final=%.3f peak=%.3f" % [trial.config.name, bank, trial.peak_bank])
		_expect(bank < 2.0, "departure controller must settle both bank directions")
		if trial.config.name == "calm": _expect(trial.peak_bank < 0.1, "calm departure must not generate a wobble")
		trial.pilot.free()
	await _free_trials(trials)
	for failure in _failures: push_error(failure)
	print("NATURAL_DEPARTURE_%s" % ("PASS" if _failures.is_empty() else "FAIL"))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok: _failures.append(message)
