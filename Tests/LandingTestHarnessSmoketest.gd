extends SceneTree

const HARNESS_SCRIPT: Script = preload("res://Scenario/LandingTestMode.gd")


func _initialize() -> void:
	var harness := Node3D.new()
	harness.set_script(HARNESS_SCRIPT)
	var constants := HARNESS_SCRIPT.get_script_constant_map()
	var matrix_cases: Array = constants.get("LANDING_SIGHT_MATRIX_CASES", [])
	var turn_in_cases: Array = constants.get("TURN_IN_MATRIX_CASES", [])
	var curricula: Array = constants.get("GA_CURRICULA", [])
	var paths: Dictionary = constants.get("AIRCRAFT_SCENE_PATHS", {})
	var crash_catch_arbitration_valid := float(
		harness.get("terminal_bolter_catch_grace_s")
	) >= 0.25
	var curricula_valid := curricula.size() == 3
	for curriculum_variant in curricula:
		var curriculum := curriculum_variant as Array
		curricula_valid = curricula_valid and curriculum.size() == 6
		for case_variant in curriculum:
			var spawn_case := case_variant as Dictionary
			curricula_valid = curricula_valid \
				and not spawn_case.has("aircraft_model") \
				and float(spawn_case.get("speed_mps", 0.0)) > 0.0
	var a1_scene: PackedScene = harness.call("_load_supported_aircraft_scene", "Aircraft_1")
	var a5_scene: PackedScene = harness.call("_load_supported_aircraft_scene", "Aircraft_5")
	var a1 := a1_scene.instantiate() if a1_scene != null else null
	var a5 := a5_scene.instantiate() if a5_scene != null else null
	var a1_pilot := a1.get_node_or_null("AIPilot") if a1 != null else null
	var a5_pilot := a5.get_node_or_null("AIPilot") if a5 != null else null
	var a5_hook := a5.get_node_or_null("TailHook") as Node3D if a5 != null else null
	var cable_scene := load("res://LandCarrier/arresting_cable.tscn") as PackedScene
	var cable := cable_scene.instantiate() if cable_scene != null else null
	var airframe_override_valid := a1_pilot != null and a5_pilot != null \
		and bool(a5_pilot.get("landing_sight_vertical_capture_enabled")) \
		and bool(a5_pilot.get("landing_sight_high_miss_waveoff_enabled")) \
		and bool(a1_pilot.get("landing_sight_vertical_capture_enabled")) \
		and bool(a1_pilot.get("landing_sight_high_miss_waveoff_enabled")) \
		and is_equal_approx(float(a5_pilot.get("landing_final_pitch_gain")), 2.4) \
		and is_equal_approx(float(a5_pilot.get("landing_sight_guidance_max_climb_mps")), 1.05116057395935) \
		and is_equal_approx(float(a5_pilot.get("landing_sight_guidance_target_hook_vertical_m")), -3.0) \
		and is_equal_approx(float(a5_pilot.get("landing_sight_guidance_max_lateral_intercept_deg")), 25.0) \
		and is_equal_approx(float(a5_pilot.get("landing_sight_guidance_terminal_lateral_power")), 2.0) \
		and is_equal_approx(float(a5_pilot.get("landing_sight_guidance_terminal_lateral_accel_mps2")), 4.0) \
		and is_equal_approx(float(a1_pilot.get("landing_sight_guidance_target_hook_vertical_m")), -3.0) \
		and is_equal_approx(float(a1_pilot.get("landing_sight_guidance_terminal_lateral_power")), 2.0) \
		and is_equal_approx(float(a1_pilot.get("landing_sight_guidance_terminal_lateral_accel_mps2")), 4.0) \
		and is_equal_approx(
			float(a1_pilot.get("landing_final_pitch_gain")),
			float(a5_pilot.get("landing_final_pitch_gain")))
	var recovery_hardware_valid := a5_hook != null \
		and is_equal_approx(a5_hook.position.y, -2.1284688) \
		and is_equal_approx(a5_hook.position.z, -1.7931325) \
		and cable != null \
		and is_equal_approx(float(cable.get("max_pay_out")), 20.0)
	var turn_in_valid := turn_in_cases.size() == 6 and a5_pilot != null \
		and a5_pilot.has_method("start_quick_turn_in_recovery")
	var press_authority_valid := a5_pilot != null \
		and float(a5_pilot.get("recovery_press_max_lateral_m")) >= 290.0 \
		and float(a5_pilot.get("recovery_press_max_track_yaw_deg")) >= 25.0 \
		and float(a5_pilot.get("recovery_press_lateral_bank_limit_deg")) >= 30.0 \
		and is_equal_approx(
			float(a5_pilot.get("recovery_press_full_bank_until_remaining_m")),
			450.0
		) \
		and float(a5_pilot.get("recovery_press_rudder_correction_limit_far")) >= 0.65 \
		and float(a5_pilot.get("landing_final_outer_bank_limit_deg")) >= 30.0 \
		and is_equal_approx(
			float(a5_pilot.get("landing_final_aoa_pitch_input_limit")),
			0.16
		) \
		and is_equal_approx(
			float(a1_pilot.get("landing_final_aoa_pitch_input_limit")),
			0.16
		)
	for turn_case_variant in turn_in_cases:
		var turn_case := turn_case_variant as Dictionary
		turn_in_valid = turn_in_valid \
			and absf(float(turn_case.get("side", 0.0))) == 1.0 \
			and is_equal_approx(float(turn_case.get("rollout_behind_m", 0.0)), 1000.0) \
			and float(turn_case.get("settle_distance_m", 0.0)) >= 250.0 \
			and float(turn_case.get("roll_in_m", 0.0)) >= 300.0 \
			and float(turn_case.get("minimum_bank_deg", 0.0)) >= 60.0 \
			and float(turn_case.get("bank_limit_deg", 0.0)) >= 65.0
	var passed := matrix_cases.size() == 16 \
		and paths.has("Aircraft_1") and paths.has("Aircraft_5") \
		and a1_scene != null and a5_scene != null \
		and curricula_valid and airframe_override_valid and turn_in_valid \
		and press_authority_valid and recovery_hardware_valid \
		and crash_catch_arbitration_valid
	print("LANDING_TEST_HARNESS_SMOKETEST %s matrix_cases=%d turn_in_cases=%d curricula=%d model_specific=%s a5_override=%s turn_in=%s press_authority=%s recovery_hardware=%s crash_catch_arbitration=%s" % [
		"PASS" if passed else "FAIL", matrix_cases.size(), turn_in_cases.size(),
		curricula.size(), str(curricula_valid), str(airframe_override_valid), str(turn_in_valid),
		str(press_authority_valid), str(recovery_hardware_valid),
		str(crash_catch_arbitration_valid)])
	if a1 != null:
		a1.free()
	if a5 != null:
		a5.free()
	if cable != null:
		cable.free()
	harness.free()
	quit(0 if passed else 1)
