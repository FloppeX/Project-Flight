extends Node3D

## Real airframes and SimpleAero; no dogfight AI. Fixed pitch and bank-feedback
## inputs, plus a known steady engine force. This is a transient response matrix,
## not a claim that every commanded bank/load is a sustainable trimmed turn.
var _model := 5
var _hz := 60
var _output := "user://fixed_wing_energy_bench.json"
var _record := {}
var _craft: RigidBody3D
var _aero: Node
var _bank := 0.0
var _power := 0.0
var _thrust := 0.0
var _results: Array = []
var _start_energy := 0.0
var _last_energy := 0.0
var _last_force_rate := 0.0
var _ticks := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-model="): _model = int(arg.get_slice("=", 1))
		if arg.begins_with("--bench-hz="): _hz = int(arg.get_slice("=", 1))
		if arg.begins_with("--bench-output="): _output = arg.trim_prefix("--bench-output=")
	Engine.physics_ticks_per_second = _hz
	for name_key in ["AirOpsManager", "EnemyOpsManager", "GroundOpsManager"]:
		get_node("/root/" + name_key).process_mode = Node.PROCESS_MODE_DISABLED
	call_deferred("run")

func run() -> void:
	for speed in [60.0, 100.0]:
		for bank in [0.0, 45.0, 70.0]:
			for power in [0.0, 1.0]:
				_bank = deg_to_rad(bank)
				_power = power
				_craft = load("res://Aircraft/Aircraft_%d.tscn" % _model).instantiate()
				_craft.freeze = true
				_craft.position = Vector3(0, 3000, 0)
				add_child(_craft)
				await get_tree().physics_frame
				await get_tree().physics_frame
				_craft.get_node("AIPilot").set_physics_process(false)
				_craft.set_physics_process(false) # No module dispatch, pilot, shake or engine spool.
				_aero = _craft.get_node("SimpleAero")
				_aero.set_flight_model_override_for_testing(1)
				_aero.aero_report_enabled = false
				var gear := _craft.get_node_or_null("ControlLandingGear")
				if gear != null: gear.stow_gear()
				_thrust = 0.0
				for engine in _aero._get_engine_modules_for_report():
					_thrust += engine.get_effective_power_factor()
				_craft.global_basis = Basis(Vector3.BACK, _bank)
				_craft.linear_velocity = Vector3(0, 0, speed)
				_craft.angular_velocity = Vector3.ZERO
				_record = {"model": _model, "hz": _hz, "speed_initial": speed, "bank_command": bank,
					"power": power, "duration_s": 12.0, "force_energy_delta": 0.0,
					"max_positive_lift_power": 0.0, "positive_drag_samples": 0,
					"sum_load": 0.0, "sum_abs_bank": 0.0, "trace": []}
				_ticks = 0
				_start_energy = 3000.0 + speed * speed / 19.6
				_last_energy = _start_energy
				_last_force_rate = 0.0
				_aero.force_audit_sample.connect(_sample)
				_craft.freeze = false
				_craft.linear_velocity = Vector3(0, 0, speed)
				PhysicsServer3D.body_set_state(_craft.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, _craft.linear_velocity)
				while _ticks < _hz * 12:
					await get_tree().physics_frame
				_aero.force_audit_sample.disconnect(_sample)
				_record["energy_delta"] = _last_energy - _start_energy
				_record["residual"] = _record.energy_delta - _record.force_energy_delta
				_record["mean_load"] = _record.sum_load / _ticks
				_record["mean_abs_bank"] = _record.sum_abs_bank / _ticks
				_results.append(_record.duplicate(true))
				print("ENERGY_BENCH_CASE ", JSON.stringify(_record).left(400))
				_craft.queue_free()
				await get_tree().physics_frame
	var file := FileAccess.open(_output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": "COMPLETE", "results": _results}, "\t"))
	file.close()
	get_tree().quit()

func _sample(sample: Dictionary) -> void:
	var velocity: Vector3 = sample.velocity
	if _ticks == 0:
		_record["actual_initial_speed"] = velocity.length()
		_record["spawn_valid"] = absf(velocity.length() - float(_record.speed_initial)) < 2.0
	var weight := _craft.mass * 9.8
	var engine_force := _craft.global_basis.z * _thrust * _power
	_craft.apply_central_force(engine_force)
	var energy := _craft.global_position.y + velocity.length_squared() / 19.6
	# Previous forces act across this completed interval; omit the unmatched
	# final force sample when comparing measured and integrated energy change.
	if _ticks > 0:
		_record.force_energy_delta += _last_force_rate * sample.delta
	_last_force_rate = (sample.lift + sample.drag + sample.alignment + engine_force).dot(velocity) / weight
	_last_energy = energy
	_record.max_positive_lift_power = maxf(_record.max_positive_lift_power, sample.lift.dot(velocity) / weight)
	_record.positive_drag_samples += int(sample.drag.dot(velocity) > 0.01)
	var bank := atan2(_craft.global_basis.x.y, _craft.global_basis.y.y)
	_record.sum_load += sample.load
	_record.sum_abs_bank += absf(rad_to_deg(bank))
	# Physical actuator inputs, not velocity/orientation manipulation after spawn.
	_aero.roll_input = clampf((bank - _bank) * 2.5 + _craft.angular_velocity.dot(_craft.global_basis.z) * 1.5, -1.0, 1.0)
	_aero.pitch_input = 0.0 if _bank == 0.0 else (0.25 if _bank < 1.0 else 0.6)
	_aero.yaw_input = 0.0
	_ticks += 1
	if _ticks % _hz == 0:
		_record.trace.append({"t": float(_ticks) / _hz, "speed": velocity.length(), "alt": _craft.global_position.y,
			"load": sample.load, "bank": rad_to_deg(bank), "energy": energy, "net_rate": _last_force_rate})
