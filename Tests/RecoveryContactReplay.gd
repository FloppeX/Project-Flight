extends "res://Tests/FullScenarioFiveAircraftRecovery.gd"
## Full-world, short physical replay from the last healthy logged pose.
## This restores pose/velocity, not an exact complete simulation checkpoint.

func vector(value: Variant) -> Vector3:
	var parts := str(value).trim_prefix("(").trim_suffix(")").split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

func _run_diagnostic_override() -> bool:
	stage = "contact_replay"
	var replay_time := 966.132
	var candidate_controls := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--replay-from="): replay_time = float(arg.get_slice("=", 1))
		if arg == "--capture-controls": candidate_controls = true
	var file := FileAccess.open("user://five_aircraft_recovery_pipeline_20260911.jsonl", FileAccess.READ)
	var sample: Dictionary = {}
	var row: Dictionary = {}
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty(): continue
		var item: Variant = JSON.parse_string(line)
		if not item is Dictionary or str(item.get("event", "")) != "SAMPLE": continue
		if float(item.t) < replay_time or float(item.t) > replay_time + 1.0: continue
		for candidate in item.data.aircraft:
			if candidate.name == "Aircraft_4_4":
				sample = item.data
				row = candidate
	file.close()
	if row.is_empty():
		_finish("replay_sample_missing")
		return true
	# The old trace omitted its terrain frame. Replay the relative entry geometry
	# at this seeded, legal carrier site, not a fictitious exact world checkpoint.
	var old_carrier := Transform3D(Basis.from_euler(vector(sample.carrier_rotation)), vector(sample.carrier_position))
	var frame := carrier.global_transform * old_carrier.affine_inverse()
	var replay_pose := frame * Transform3D(Basis.from_euler(vector(row.rotation)), vector(row.nav.aircraft_position))
	var replay_velocity := frame.basis * vector(row.velocity)
	var craft: RigidBody3D = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	craft.name = "RetryContactReplay"
	craft.freeze = true
	current_scene.add_child(craft)
	var pilot: Node = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	craft.global_transform = replay_pose
	var camera := Camera3D.new()
	current_scene.add_child(camera)
	camera.global_position = craft.global_position + Vector3(0, 20, 50)
	camera.look_at(craft.global_position)
	camera.make_current()
	await create_timer(3.0).timeout
	_on_launch(pilot)
	pilot.set_physics_process(false)
	craft.connect("body_shape_entered", func(_rid, body, other_shape, local_shape):
		_event("REPLAY_CONTACT", {"body": str(body.get_path()), "other_shape": other_shape,
			"local_shape": local_shape, "metadata": _collision_metadata(craft)}))
	craft.global_transform = replay_pose
	craft.freeze = false
	craft.linear_velocity = replay_velocity
	if replay_time < 960.0:
		var toggle := craft.get_node("AIToggle")
		toggle.call("enable_ai")
		pilot.set("recovery_route_capture_experimental", candidate_controls)
		pilot.set("recovery_recapture_steering_experimental", candidate_controls)
		pilot.set("recovery_capture_terrain_experimental", candidate_controls)
		pilot.set("debug_enabled", true)
		pilot.set("landing_debug_enabled", true)
		pilot.set("landing_debug_interval_s", 1.0)
		var engine := craft.get_node("Engine")
		engine.set("is_engine_working", true)
		engine.set("current_power", 1.0)
		engine.set("target_power", 1.0)
		air_ops.call("order_rtb", "Archer")
		if replay_time > 800.0:
			pilot.set("_recovery_go_around_attempt_count", 1)
			pilot.call("_start_compact_bolter_reentry")
	_event("REPLAY_BEGIN", {"source_t": replay_time, "exact_checkpoint": false,
		"terrain_frame_restored": false, "candidate_controls": candidate_controls, "position": craft.global_position,
		"velocity": craft.linear_velocity, "ground_y": craft.call("_get_ground_height_at_position", craft.global_position)})
	var reference: WeakRef = weakref(craft)
	for i in range(180 if replay_time >= 960.0 else 60 * 300):
		await physics_frame
		if not is_instance_valid(reference.get_ref()): break
		if i % 60 == 0: _sample()
	_finish("replay_complete")
	return true
