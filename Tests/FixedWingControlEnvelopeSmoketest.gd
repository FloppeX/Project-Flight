extends Node

var _failures: Array[String] = []


func _ready() -> void:
	var aero := SimpleAero.new()
	var stall_speed_mps := aero.stall_speed
	var normal_speed_mps := stall_speed_mps * 1.5

	var pitch_at_stall := aero.get_axis_control_authority_at_speed(
		stall_speed_mps,
		&"pitch",
		stall_speed_mps
	)
	var roll_at_stall := aero.get_axis_control_authority_at_speed(
		stall_speed_mps,
		&"roll",
		stall_speed_mps
	)
	var yaw_at_stall := aero.get_axis_control_authority_at_speed(
		stall_speed_mps,
		&"yaw",
		stall_speed_mps
	)
	_expect(absf(pitch_at_stall - 0.35) < 0.01, "pitch authority does not reach its stall floor")
	_expect(absf(roll_at_stall - 0.25) < 0.01, "roll authority does not reach its stall floor")
	_expect(absf(yaw_at_stall - 0.50) < 0.01, "yaw authority does not reach its stall floor")
	_expect(yaw_at_stall > pitch_at_stall and pitch_at_stall > roll_at_stall, "near-stall axis ordering is wrong")
	var pitch_deep_stall := aero.get_axis_control_authority_at_speed(
		normal_speed_mps,
		&"pitch",
		stall_speed_mps,
		1.0
	)
	var roll_deep_stall := aero.get_axis_control_authority_at_speed(
		normal_speed_mps,
		&"roll",
		stall_speed_mps,
		1.0
	)
	var yaw_deep_stall := aero.get_axis_control_authority_at_speed(
		normal_speed_mps,
		&"yaw",
		stall_speed_mps,
		1.0
	)
	_expect(yaw_deep_stall > pitch_deep_stall and pitch_deep_stall > roll_deep_stall, "deep-stall recovery authority ordering is wrong")
	_expect(roll_deep_stall <= 0.11, "ailerons retain too much authority in a deep stall")
	_expect(yaw_deep_stall >= 0.54, "rudder does not retain enough deep-stall recovery authority")

	for axis: StringName in [&"pitch", &"roll", &"yaw"]:
		var normal_authority := aero.get_axis_control_authority_at_speed(
			normal_speed_mps,
			axis,
			stall_speed_mps
		)
		_expect(absf(normal_authority - 1.0) < 0.01, "%s is not fully effective at normal speed" % axis)

	var pitch_at_vne := aero.get_high_speed_control_limit(aero.never_exceed_speed_mps, &"pitch")
	var roll_at_vne := aero.get_high_speed_control_limit(aero.never_exceed_speed_mps, &"roll")
	var yaw_at_vne := aero.get_high_speed_control_limit(aero.never_exceed_speed_mps, &"yaw")
	_expect(absf(pitch_at_vne - 0.50) < 0.01, "elevator Vne limit is wrong")
	_expect(absf(roll_at_vne - 0.68) < 0.01, "aileron Vne limit is wrong")
	_expect(absf(yaw_at_vne - 0.40) < 0.01, "rudder Vne limit is wrong")
	_expect(roll_at_vne > pitch_at_vne and pitch_at_vne > yaw_at_vne, "high-speed axis ordering is wrong")

	var normal_surface_step := aero._advance_control_surface(0.0, 1.0, 1.0, 4.0, 0.9, 0.0, 0.1)
	var stiff_surface_step := aero._advance_control_surface(0.0, 1.0, pitch_at_vne, 4.0, 0.9, 1.0, 0.1)
	_expect(normal_surface_step > stiff_surface_step * 4.0, "high-speed surface motion is not meaningfully slower")
	_expect(stiff_surface_step <= pitch_at_vne, "rate-limited elevator exceeded its position limit")

	aero.auto_rudder_strength = 0.5
	aero.roll_input = 1.0
	aero.yaw_input = 0.0
	aero._update_control_envelope(0.05, 100.0, 100.0, stall_speed_mps, 0.0, Vector3(0.0, 0.0, 100.0))
	var coordinated_roll_position := aero.actual_roll_control
	var coordinated_yaw_position := aero.actual_yaw_control
	_expect(
		absf(coordinated_yaw_position - coordinated_roll_position * aero.auto_rudder_strength) < 0.01,
		"automatic rudder does not follow actual aileron position"
	)
	aero.roll_input = -1.0
	aero._update_control_envelope(0.05, 100.0, 100.0, stall_speed_mps, 0.0, Vector3(0.0, 0.0, 100.0))
	_expect(aero.actual_yaw_control >= -0.001, "automatic rudder reversed before the aileron crossed neutral")

	var deep_control_loss := aero.get_deep_stall_control_loss(0.50, 0.55)
	_expect(deep_control_loss > 0.99, "an established stall does not fully separate the controls")
	var blended_control_speed := aero.get_control_airflow_speed(45.0, 68.0, 0.0)
	var departed_control_speed := aero.get_control_airflow_speed(45.0, 68.0, deep_control_loss)
	_expect(blended_control_speed > 55.0, "normal-flight slip assistance no longer counts total airflow")
	_expect(absf(departed_control_speed - 45.0) < 0.01, "sideways velocity still powers the controls in a deep stall")
	aero._update_control_envelope(
		0.05,
		100.0,
		100.0,
		stall_speed_mps,
		0.50,
		Vector3(0.0, 0.0, 100.0),
		deep_control_loss
	)
	_expect(aero.current_pitch_authority <= 0.121, "deep-stall elevator authority exceeds its cap")
	_expect(aero.current_roll_authority <= 0.051, "deep-stall aileron authority exceeds its cap")
	_expect(aero.current_yaw_authority <= 0.201, "deep-stall rudder authority exceeds its cap")
	_expect(
		aero.current_yaw_authority > aero.current_pitch_authority \
			and aero.current_pitch_authority > aero.current_roll_authority,
		"deep-stall recovery-control ordering is wrong"
	)
	aero._update_control_envelope(
		0.05,
		100.0,
		100.0,
		stall_speed_mps,
		0.0,
		Vector3(0.0, 0.0, 100.0),
		0.0
	)
	_expect(aero.current_pitch_authority > 0.99, "elevator authority did not return with clean airflow")
	_expect(aero.current_roll_authority > 0.99, "aileron authority did not return with clean airflow")
	_expect(aero.current_yaw_authority > 0.99, "rudder authority did not return with clean airflow")

	var normal_stress := aero.get_control_stress_for_state(100.0, 0.0, 1.0, 0.0, 0.0)
	var vne_stress := aero.get_control_stress_for_state(aero.never_exceed_speed_mps, 0.0, 1.0, 0.0, 0.0)
	var overspeed_stress := aero.get_control_stress_for_state(aero.control_stiffening_full_speed_mps, 0.0, 0.0, 0.0, 0.0)
	_expect(normal_stress < 0.01, "normal-speed control input incorrectly reports structural stress")
	_expect(vne_stress > 0.95, "full elevator near Vne does not report strong stress")
	_expect(overspeed_stress > 0.95, "overspeed does not report stress without control input")

	var feedback := AirflowFeedback.new()
	var quiet_wind := feedback.calculate_wind_intensity(20.0, aero.never_exceed_speed_mps)
	var vne_wind := feedback.calculate_wind_intensity(aero.never_exceed_speed_mps, aero.never_exceed_speed_mps)
	_expect(quiet_wind < 0.01, "base airflow is audible below its start speed")
	_expect(vne_wind > 0.95, "base airflow does not reach full intensity near Vne")
	var clean_drag_cue := feedback.calculate_drag_intensity(0.0)
	var maneuver_drag_cue := feedback.calculate_drag_intensity(4.0)
	var severe_drag_cue := feedback.calculate_drag_intensity(9.0)
	_expect(clean_drag_cue < 0.01, "clean flight incorrectly raises the maneuver-drag cue")
	_expect(maneuver_drag_cue > 0.30 and maneuver_drag_cue < 0.70, "maneuver-drag cue lacks a useful progressive middle range")
	_expect(severe_drag_cue > 0.99, "severe drag does not saturate the maneuver-drag cue")
	var dirty_drag_accel := aero.get_dirty_airflow_drag_accel_mps2(500.0, 1000.0, 2000.0, 500.0, 1000.0)
	_expect(is_equal_approx(dirty_drag_accel, 4.0), "dirty-airflow drag components are not normalized by aircraft mass")
	feedback.update_airflow_feedback(
		0.016,
		false,
		0.0,
		0.0,
		20.0,
		60.0,
		0.0,
		stall_speed_mps,
		aero.never_exceed_speed_mps,
		0.0
	)
	_expect(feedback.get_child_count() == 0, "inactive AI feedback allocated audio players")
	feedback.update_airflow_feedback(
		0.016,
		true,
		0.0,
		0.0,
		20.0,
		60.0,
		0.0,
		stall_speed_mps,
		aero.never_exceed_speed_mps,
		0.0
	)
	_expect(feedback.get_child_count() == 3, "player feedback did not create all three airflow audio layers")
	for audio_child in feedback.get_children():
		if audio_child is AudioStreamPlayer:
			_expect(
				(audio_child as AudioStreamPlayer).bus == "Master",
				"pilot airflow feedback was routed through the exterior-source cockpit filter"
			)

	feedback.free()
	aero.free()
	if _failures.is_empty():
		print(
			"[FixedWingControlEnvelopeSmoketest] PASS stall(p/r/y)=%.2f/%.2f/%.2f vne(p/r/y)=%.2f/%.2f/%.2f rate=%.2f->%.2f stress=%.2f" % [
				pitch_at_stall,
				roll_at_stall,
				yaw_at_stall,
				pitch_at_vne,
				roll_at_vne,
				yaw_at_vne,
				normal_surface_step,
				stiff_surface_step,
				vne_stress,
			]
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FixedWingControlEnvelopeSmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
