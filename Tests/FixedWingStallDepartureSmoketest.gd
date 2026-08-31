extends Node

var _failures: Array[String] = []


func _ready() -> void:
	var aero := SimpleAero.new()
	_expect(aero.aoa_stall_start_deg <= 20.0, "AoA stall still starts too late")
	_expect(aero.aoa_stall_full_deg <= 38.0, "AoA stall still develops too gradually")
	_expect(aero.aoa_stall_lift_loss >= 0.65, "deep AoA stall retains too much lift")
	_expect(aero.stall_lift_loss >= 0.45, "deep speed stall retains too much lift")
	_expect(aero.stall_alignment_min_factor <= 0.12, "flight-path alignment remains too strong in departure")
	_expect(aero.stall_stability_min_factor <= 0.05, "attitude stability remains too strong in departure")
	_expect(aero.stall_roll_damping_min_factor < aero.stall_pitch_damping_min_factor, "departure does not release roll damping before pitch damping")
	var aero_source := FileAccess.get_file_as_string("res://Aircraft/SimpleAero.gd")
	_expect(not aero_source.contains("rudder_opposite_roll_coupling"), "rudder-to-roll coupling was not removed")
	_expect(aero.deep_stall_pitch_authority_cap <= 0.12, "deep-stall elevator remains too effective")
	_expect(aero.deep_stall_roll_authority_cap <= 0.05, "deep-stall ailerons remain too effective")
	_expect(aero.deep_stall_yaw_authority_cap <= 0.20, "deep-stall rudder remains too effective")

	var inactive_target := aero.get_stall_departure_target(1.0, false)
	var entry_target := aero.get_stall_departure_target(aero.stall_departure_entry_severity, true)
	var full_target := aero.get_stall_departure_target(aero.stall_departure_full_severity, true)
	var full_control_loss := aero.get_deep_stall_control_loss(0.50, 0.50)
	_expect(inactive_target < 0.001, "inactive departure produces a stall moment")
	_expect(entry_target > 0.0 and entry_target < 0.2, "departure entry is abrupt instead of progressive")
	_expect(full_target > 0.99, "deep stall never reaches full departure")
	_expect(full_control_loss > 0.99, "deep stall never reaches full control separation")

	aero._update_stall_departure(0.2, 1.0, Vector3(4.0, 0.0, 50.0), 50.0)
	var built_severity := aero.current_departure_severity
	_expect(built_severity >= 0.59, "departure builds too slowly to create a decisive stall break")
	_expect(aero.current_stall_drop_direction > 0.0, "sideslip did not select a persistent wing-drop direction")
	aero._update_stall_departure(0.2, 0.0, Vector3.ZERO, 50.0)
	_expect(aero.current_departure_severity > 0.0, "departure recovery has no hysteresis")
	aero._update_stall_departure(0.2, 0.0, Vector3.ZERO, 50.0)
	_expect(aero.current_departure_severity < 0.001, "departure does not clear after a decisive recovery")
	_expect(absf(aero.current_stall_drop_direction) < 0.001, "wing-drop direction remained active after recovery")

	aero.free()
	if _failures.is_empty():
		print("[FixedWingStallDepartureSmoketest] PASS aoa=20->38 lift_loss=0.65 departure=%.2f wing_drop=stable" % built_severity)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FixedWingStallDepartureSmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
