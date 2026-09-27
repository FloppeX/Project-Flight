extends "res://Tests/CompactRecoverySortieProbe.gd"
## Prepared downwind entry, not a launch/strike test. Uses normal compact route,
## terrain, aircraft physics, clearance, final gates, wire and stow.

func _run_diagnostic_override() -> bool:
	stage = "prepared_entry"
	var side := 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--entry-side="): side = float(arg.get_slice("=", 1))
	var wind := get_first_node_in_group("atmospheric_wind")
	wind.enabled = false
	# Recorded operational carrier position; identical in every paired trial.
	carrier.position = Vector3(-142.2818, 524.6493, -2206.713)
	carrier.rotation = Vector3(0, -3.128379, 0)
	carrier.velocity = Vector3.ZERO
	carrier.hold_position()
	current_scene.get_node("LowPolyTerrainPrototype").position = Vector3(22618.79, 62, 3722.299)
	for i in 3: await physics_frame
	var craft: RigidBody3D = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	if OS.get_cmdline_user_args().has("--legacy-compact-vector"):
		craft.get_node("AIPilot").set_script(load("res://Tests/Fixtures/LegacyCompactRecoveryPilot.gd"))
	craft.freeze = true
	craft.set_meta("parking_brake", false)
	craft.set_meta("carrier_transport_mode", false)
	craft.set_meta("controls_disabled", false)
	craft.position = carrier.position + Vector3.UP * 1000.0
	current_scene.add_child(craft)
	var pilot: Node = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	for i in 3: await physics_frame
	pilot.aircraft = craft
	pilot.carrier_position = carrier.global_position
	pilot._find_approach_waypoints()
	var frame: Dictionary = pilot._get_recovery_carrier_frame()
	var forward: Vector3 = frame.forward
	var right: Vector3 = frame.right
	craft.global_position = frame.origin - forward * 450.0 + right * side * 900.0
	craft.global_position.y = float(frame.deck_y) + 260.0
	craft.global_basis = Basis.looking_at(-forward, Vector3.UP, true)
	craft.linear_velocity = -forward * 60.0
	craft.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(craft.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, craft.global_transform)
	craft.reset_physics_interpolation()
	craft.get_node("SimpleAero").set_flight_model_override_for_testing(1)
	_on_launch(pilot)
	craft.get_node("AIToggle").enable_ai()
	pilot.set_physics_process(true)
	craft.freeze = false
	craft.linear_velocity = -forward * 60.0
	PhysicsServer3D.body_set_state(craft.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, craft.linear_velocity)
	pilot.change_state(pilot.State.SEARCH)
	var started: bool = pilot.start_recovery()
	if started and not OS.get_cmdline_user_args().has("--select-arrival"):
		started = pilot._try_install_compact_recovery_route_for_side(frame, side, true, pilot.recovery_compact_pattern_max_raise_m)
	_event("PREPARED_ENTRY", {"side": side, "started": started, "position": craft.global_position,
		"velocity": craft.linear_velocity, "carrier": carrier.global_transform,
		"bank_limit": pilot.recovery_compact_turn_bank_limit_deg})
	if not started:
		_finish("prepared_route_rejected")
		return true
	stage = "recovering"
	recall_at = elapsed()
	var id := craft.get_instance_id()
	while elapsed() - recall_at < 240.0:
		_sample()
		if records[id].stowed or records[id].destroyed or records[id].unavailable: break
		await create_timer(1.0).timeout
	_finish("prepared_entry_complete")
	return true

func _finish(reason: String) -> void:
	if stage == "complete": return
	var passed: bool = records.size() == 1 and records.values().all(
		func(record): return record.caught and record.stowed and not record.destroyed)
	_event("ENTRY_RESULT", {"passed": passed, "reason": reason, "aircraft": records.values()})
	stage = "complete"
	_write_status("PASS" if passed else "FAIL", reason)
	if events != null: events.close()
	print("COMPACT_RECOVERY_ENTRY ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
