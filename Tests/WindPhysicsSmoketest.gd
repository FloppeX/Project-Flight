extends "res://Tests/Aircraft5ControlAuthorityInvestigation.gd"

class FlatTerrain extends Node3D:
	func get_height(_p: Vector3) -> float: return 0.0

class TestWind extends "res://Weather/WindField.gd":
	var gradient := 0.0
	var center_x := 0.0
	func get_velocity_at(p: Vector3) -> Vector3:
		return super.get_velocity_at(p) + Vector3.UP * gradient * (p.x - center_x)

func _run() -> void:
	var terrain := FlatTerrain.new()
	add_child(terrain)
	get_node("/root/TerrainReference").terrain_node = terrain
	var field := TestWind.new()
	add_child(field)
	field.set_physics_process(false)
	var position := Vector3(700, 80, -900)
	var before := field.get_velocity_at(position)
	var shift := Vector3(3000, 0, -2000)
	field.apply_origin_shift(shift)
	_expect(before.is_equal_approx(field.get_velocity_at(position - shift)), "origin shift must preserve the air mass")
	field.apply_origin_shift(-shift)
	var min_wind := Vector3(INF, INF, INF)
	var max_wind := -min_wind
	for i in 300:
		field.elapsed_s = i * 0.1
		var wind := field.get_velocity_at(position)
		min_wind = min_wind.min(wind)
		max_wind = max_wind.max(wind)
	_expect((max_wind - min_wind).length() > 0.5, "default wind must vary over time")
	field.gust_amplitude_mps = Vector3.ZERO
	field.turbulence_amplitude_mps = Vector3.ZERO
	field.prevailing_velocity_mps = Vector3.ZERO
	var trials := await _spawn_trials([{"name":"force", "speed_mps":55.0}])
	var body: RigidBody3D = trials[0].aircraft
	var aero: SimpleAero = trials[0].aero
	body.freeze = true
	body.global_basis = Basis.IDENTITY
	aero.set_physics_process(false)
	aero._wind_field = field
	field.center_x = body.global_position.x
	var samples: Array[Dictionary] = []
	aero.force_audit_sample.connect(func(sample: Dictionary): samples.append(sample))
	body.linear_velocity = Vector3(0, 0, 55)
	aero._physics_process(1.0 / 60.0)
	var calm: Dictionary = samples.back()
	field.prevailing_velocity_mps = Vector3(10, 0, 0)
	body.linear_velocity = Vector3(10, 0, 55)
	aero._physics_process(1.0 / 60.0)
	_expect(calm.lift.is_equal_approx(samples.back().lift) and calm.drag.is_equal_approx(samples.back().drag), "same air-relative velocity must produce the same forces")
	_expect(aero.current_gust_torque_nm.length() < 0.001, "uniform wind must not add differential wing torque")
	body.calculate_flight_data(1.0 / 60.0)
	_expect(absf(body.air_velocity - 55.0) < 0.001, "indicated airspeed must exclude wind")
	body.linear_velocity = Vector3(0, 0, 55)
	field.prevailing_velocity_mps = Vector3(0, 0, -10)
	aero._physics_process(1.0 / 60.0)
	var head_lift: float = samples.back().lift.length()
	var head_control := aero.current_pitch_authority
	field.prevailing_velocity_mps = Vector3(0, 0, 10)
	aero._physics_process(1.0 / 60.0)
	_expect(head_lift > samples.back().lift.length() * 1.2, "headwind must increase launch-speed lift relative to tailwind")
	_expect(head_control > aero.current_pitch_authority * 1.2, "controls must respond to airspeed")
	field.prevailing_velocity_mps = Vector3(0, 3, 0)
	aero._physics_process(1.0 / 60.0)
	_expect(samples.back().lift.y > calm.lift.y, "upgust must increase lift at this AoA")
	field.prevailing_velocity_mps = Vector3.ZERO
	field.gradient = 0.4
	aero._physics_process(1.0 / 60.0)
	var positive_moment := aero.current_gust_torque_nm.z
	field.gradient = -0.4
	aero._physics_process(1.0 / 60.0)
	_expect(absf(positive_moment) > 100.0 and positive_moment * aero.current_gust_torque_nm.z < 0.0, "mirrored wing gusts must produce opposite physical roll moments")
	print("WIND_FORCE_CHECK head_lift=%.1f differential_roll_torque=%.1f wind_range=%s" % [head_lift, positive_moment, max_wind - min_wind])
	var weather = load("res://Weather/ContinuousTurbulence.tscn").instantiate()
	add_child(weather)
	weather.set_process(false)
	weather.impulse_threshold = 0.0
	weather.gust_rate_hz = 1000.0
	var shake_before: float = body.shake_intensity
	for i in 20:
		weather.apply_continuous_turbulence(body, 1.0, null)
	_expect(weather._last_impulse_time.is_empty(), "wind-driven aircraft must not receive legacy gust impulses")
	_expect(is_equal_approx(shake_before, body.shake_intensity), "weather must not add physical camera-shake forces to wind-driven aircraft")
	weather.queue_free()
	await _free_trials(trials)
	field.gradient = 0.0
	field.prevailing_velocity_mps = Vector3(4, 0, 2)
	field.gust_amplitude_mps = Vector3(3, 1.5, 3)
	field.turbulence_amplitude_mps = Vector3(1.5, 1, 1.5)
	field.elapsed_s = 0.0
	field.set_physics_process(true)
	var calm_field := TestWind.new()
	add_child(calm_field)
	calm_field.enabled = false
	trials = await _spawn_trials([{"name":"calm", "speed_mps":65.0}, {"name":"weather", "speed_mps":65.0}])
	for i in trials.size():
		var wing: SimpleAero = trials[i].aero
		wing._wind_field = calm_field if i == 0 else field
		wing.stability_strength = 0.0
		wing.auto_rudder_strength = 0.0
		trials[i]["peak_bank"] = 0.0
		trials[i]["peak_moment"] = 0.0
	for frame in 480:
		await get_tree().physics_frame
		for trial in trials:
			var aircraft: RigidBody3D = trial.aircraft
			var wing: SimpleAero = trial.aero
			trial.peak_bank = maxf(trial.peak_bank, absf(rad_to_deg(atan2(aircraft.global_basis.x.y, aircraft.global_basis.y.y))))
			trial.peak_moment = maxf(trial.peak_moment, wing.current_gust_torque_nm.length())
	_expect(trials[0].peak_bank < 0.1 and trials[0].peak_moment < 0.001, "calm must remain calm")
	_expect(trials[1].peak_bank > 0.2 and trials[1].peak_moment > 10.0, "default turbulence must measurably rotate a free aircraft")
	for trial in trials:
		print("WIND_FREE_FLIGHT %s peak_bank=%.3f peak_moment=%.1f velocity=%s" % [trial.config.name, trial.peak_bank, trial.peak_moment, trial.aircraft.linear_velocity])
	await _free_trials(trials)
	for failure in _failures: push_error(failure)
	print("WIND_PHYSICS_%s" % ("PASS" if _failures.is_empty() else "FAIL"))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok: _failures.append(message)
