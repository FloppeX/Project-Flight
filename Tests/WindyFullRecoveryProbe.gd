extends "res://Tests/FullScenarioFiveAircraftRecovery.gd"
## Two real hangar-to-hangar sorties, with the live scenario weather unchanged.
var wind_samples := {}

func _initialize() -> void:
	label = "windy_two_sorties"
	super._initialize()

func _run() -> void:
	# Isolate weather/recovery from combat without changing aircraft or landing gates.
	for manager_name in ["EnemyOpsManager", "EnemyBaseManager"]:
		var manager := root.get_node(manager_name)
		manager.set("_disabled_for_test", true)
		manager.set_process(false)
		manager.set_physics_process(false)
	await super._run()

func _run_diagnostic_override() -> bool:
	# The base runner already opened its event log using the command-line label.
	var wind := get_first_node_in_group("atmospheric_wind")
	if wind == null or not wind.enabled:
		_finish("wind_not_enabled")
		return true
	if OS.get_cmdline_user_args().has("--calm"): wind.enabled = false
	_event("WIND_SETUP", {"enabled": wind.enabled, "mean": wind.prevailing_velocity_mps, "gust": wind.gust_amplitude_mps, "turbulence": wind.turbulence_amplitude_mps, "stock": _stock()})
	stage = "launching"
	route_ordered = _order_route()
	var models: Array[String] = []
	for model in ["Aircraft_2", "Aircraft_5"]:
		if deck._count_stored_aircraft_for_kind("fixed_wing", model) > 0: models.append(model)
	while models.size() < 2: models.append("")
	var ordered := 0
	var launch_deadline := elapsed() + 600.0
	while records.size() < 2 and elapsed() < launch_deadline:
		if ordered < 2 and records.size() == ordered and deck._can_accept_ai_ops_launch_request():
			var queued: int = deck.queue_ai_flight(1, observer, "", models[ordered])
			_event("LAUNCH_ORDER", {"model": models[ordered], "queued": queued})
			if queued == 1: ordered += 1
		_sample()
		await create_timer(1.0).timeout
	if records.size() < 2:
		_finish("launch_timeout")
		return true
	stage = "outbound"
	var outbound_end := elapsed() + 60.0
	while elapsed() < outbound_end:
		_sample()
		await create_timer(1.0).timeout
	stage = "recovering"
	recall_at = elapsed()
	for flight in air_ops.flights:
		if flight.strength() > 0: air_ops.order_rtb(flight.flight_name)
	_event("RECALL_ALL", {"launched": records.size()})
	while elapsed() - recall_at < 900.0:
		_sample()
		var terminal := 0
		for record in records.values():
			if record.stowed or record.destroyed or record.unavailable: terminal += 1
		if terminal == 2: break
		await create_timer(1.0).timeout
	var passed := records.size() == 2 and records.values().all(func(record): return record.caught and record.stowed and not record.destroyed)
	_event("WIND_RESULT", {"passed": passed, "aircraft": records.values(), "wind_samples": wind_samples})
	_finish("two_cycles_passed" if passed else "recovery_incomplete")
	return true

func _sample() -> void:
	super._sample()
	var wind := get_first_node_in_group("atmospheric_wind")
	if wind == null: return
	var rows := []
	for id in live:
		var craft = live[id].craft.get_ref()
		if not is_instance_valid(craft) or records[id].stowed or records[id].destroyed: continue
		var velocity: Vector3 = wind.get_velocity_at(craft.global_position)
		var aero: Node = craft.get_node_or_null("SimpleAero")
		if not wind_samples.has(str(id)): wind_samples[str(id)] = {"min_speed": INF, "max_speed": 0.0, "max_gust_torque": 0.0}
		var sample: Dictionary = wind_samples[str(id)]
		sample.min_speed = minf(sample.min_speed, velocity.length())
		sample.max_speed = maxf(sample.max_speed, velocity.length())
		var torque: Vector3 = aero.current_gust_torque_nm if aero != null else Vector3.ZERO
		sample.max_gust_torque = maxf(sample.max_gust_torque, torque.length())
		rows.append({"id": id, "wind": velocity, "ground_speed": craft.linear_velocity.length(), "air_speed": craft.get_air_relative_velocity().length(), "gust_torque": torque})
	_event("WIND_SAMPLE", {"aircraft": rows}, false)


func _finish(reason: String) -> void:
	if stage == "complete": return
	var passed := records.size() == 2 and records.values().all(func(record): return record.caught and record.stowed and not record.destroyed)
	super._finish(reason)
	quit(0 if passed else 1)
