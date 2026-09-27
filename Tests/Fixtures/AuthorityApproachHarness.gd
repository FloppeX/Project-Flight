extends "res://Scenario/LandingTestMode.gd"

var variant_name := ""
var output_prefix := ""
var telemetry: FileAccess
var sample_tick := 0
var reference_speed_override := -1.0

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--authority-case="): variant_name = argument.get_slice("=", 1)
		if argument.begins_with("--authority-reference="):
			reference_speed_override = float(argument.get_slice("=", 1))
	if not variant_name in ["legacy_calm", "reduced_calm", "reduced_windy"]:
		push_error("Unknown authority comparison case")
		get_tree().quit(2)
		return
	var suite := "turn" if OS.get_cmdline_user_args().has("--landing-turn-in-matrix") else "straight"
	output_prefix = "res://captures/authority_%s_%s" % [variant_name, suite]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--authority-run="):
			output_prefix += "_" + argument.get_slice("=", 1).validate_filename()
	telemetry = FileAccess.open(output_prefix + "_samples.jsonl", FileAccess.WRITE)
	super._ready()

func _spawn_lander() -> void:
	Engine.max_fps = 0
	var wind := get_tree().get_first_node_in_group("atmospheric_wind")
	if wind == null:
		push_error("Comparison requires the real WindField")
		get_tree().quit(2)
		return
	wind.enabled = variant_name == "reduced_windy"
	wind.elapsed_s = 0.0
	super._spawn_lander()
	for attempt in _attempts.values():
		if int(attempt.spawn_index) != _spawn_index: continue
		var craft = attempt.node
		var aero: Node = craft.get_node("SimpleAero")
		aero.set_flight_model_override_for_testing(1)
		aero.progressive_control_authority_enabled = variant_name != "legacy_calm"
		if reference_speed_override > 0.0:
			aero.control_reference_speed_mps = reference_speed_override
		telemetry.store_line(JSON.stringify({"event": "ENTRY", "case": _spawn_index,
			"variant": variant_name, "entry": attempt.entry_case, "carrier_transform": _carrier().global_transform,
			"position": craft.global_position, "velocity": craft.linear_velocity, "mass": craft.mass,
			"advanced": aero.is_advanced_flight_model(), "progressive": aero.progressive_control_authority_enabled,
			"control_reference_speed_mps": aero.control_reference_speed_mps,
			"wind_enabled": wind.enabled, "wind": wind.get_velocity_at(craft.global_position)}))
	telemetry.flush()

func _sample_ga_metrics() -> void:
	super._sample_ga_metrics()
	sample_tick += 1
	if sample_tick % 6 != 0 or telemetry == null: return
	for attempt in _attempts.values():
		var craft = attempt.get("node")
		if not is_instance_valid(craft) or str(attempt.get("outcome", "")) != "": continue
		var pilot: Node = craft.get_node("AIPilot")
		var aero: Node = craft.get_node("SimpleAero")
		var air_velocity: Vector3 = craft.get_air_relative_velocity()
		var sight: Dictionary = pilot.get_landing_sight_snapshot()
		var nav: Dictionary = pilot.get_recovery_navigation_snapshot()
		var local_pose: Transform3D = _carrier().global_transform.affine_inverse() * craft.global_transform
		telemetry.store_line(JSON.stringify({"event": "SAMPLE", "case": attempt.spawn_index,
			"age": _elapsed_s - attempt.spawn_t, "state": pilot.State.keys()[pilot.current_state],
			"position": local_pose.origin, "rotation": local_pose.basis.get_euler(),
			"velocity": _carrier().global_basis.inverse() * craft.linear_velocity,
			"angular_velocity": craft.global_basis.inverse() * craft.angular_velocity,
			"air_speed": air_velocity.length(), "controls": Vector3(pilot.pitch_input, pilot.roll_input, pilot.yaw_input),
			"authority": Vector3(aero.get_axis_control_authority_at_speed(air_velocity.length(), &"pitch"),
				aero.get_axis_control_authority_at_speed(air_velocity.length(), &"roll"),
				aero.get_axis_control_authority_at_speed(air_velocity.length(), &"yaw")),
			"remaining": sight.get("remaining_m"), "track_error": sight.get("track_error_deg"),
			"lateral_error": sight.get("current_lateral_error_m"), "progress": nav.get("progress"),
			"gust_torque": aero.current_gust_torque_nm}))
	telemetry.flush()

func _log(message: String) -> void:
	print("[AuthorityComparison %s] %s" % [variant_name, message])
	if message.begins_with("TURN_IN_RESULT json=") or message.begins_with("MATRIX_RESULT json="):
		var result: Dictionary = JSON.parse_string(message.get_slice("json=", 1))
		result["authority_variant"] = variant_name
		FileAccess.open(output_prefix + "_result.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
