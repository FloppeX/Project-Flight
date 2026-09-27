extends "res://Tests/FullStrikeSortieProbe.gd"
## Production sortie plus recovery telemetry. Overrides require explicit CLI flags.

func _on_launch(pilot: Node) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--compact-bank="):
			pilot.recovery_compact_turn_bank_limit_deg = float(arg.get_slice("=", 1))
		if arg.begins_with("--handoff-deadline="):
			pilot.recovery_final_handoff_deadline_remaining_m = float(arg.get_slice("=", 1))
	super._on_launch(pilot)

func _sample() -> void:
	super._sample()
	for id in live:
		if records[id].stowed or records[id].destroyed: continue
		var pilot: Variant = live[id].pilot.get_ref()
		if not is_instance_valid(pilot): continue
		if not pilot._is_recovery_route_state(): continue
		var geom: Dictionary = pilot._get_landing_line_geometry()
		var remaining: float = pilot._landing_remaining_to_touchdown(pilot.aircraft.global_position, geom)
		var ideal: Vector3 = pilot._landing_path_point(geom, remaining)
		var fields := {}
		for field in ["_coordinated_turn_desired_vertical_speed_mps", "_coordinated_turn_target_g",
			"_coordinated_turn_target_bank_deg",
			"_coordinated_turn_measured_g", "_coordinated_turn_nonwing_vertical_accel_mps2",
			"_coordinated_turn_target_aoa_deg", "_coordinated_turn_measured_aoa_deg",
			"_route_arc_signed_radial_error_m_debug", "_route_arc_radial_speed_mps_debug",
			"_route_arc_remaining_m", "_route_arc_capture_ready_debug", "_recovery_terrain_vs_floor_mps",
			"_route_fpv_pitch_target", "_flight_plan_legs"]:
			fields[field] = pilot.get(field)
		fields["glide_error_m"] = pilot.aircraft.global_position.y - ideal.y
		fields["remaining_m"] = remaining
		fields["entry"] = pilot._get_pre_landing_entry_assessment()
		fields["state"] = pilot.State.keys()[pilot.current_state]
		_event("RECOVERY_CONTROL", fields, false)
