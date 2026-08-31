extends Node

var _failures: Array[String] = []


func _ready() -> void:
	var controls := AircraftModule_ControlSteering.new()
	_expect(is_equal_approx(controls.advanced_pitch_expo, 0.35), "advanced pitch expo is not 35 percent")
	_expect(is_equal_approx(controls.advanced_roll_expo, 0.25), "advanced roll expo is not 25 percent")
	_expect(is_equal_approx(controls.advanced_yaw_expo, 0.15), "advanced rudder expo is not 15 percent")

	var pitch_small := controls.shape_advanced_fixed_wing_input(0.10, controls.advanced_pitch_expo)
	var pitch_half := controls.shape_advanced_fixed_wing_input(0.50, controls.advanced_pitch_expo)
	var roll_half := controls.shape_advanced_fixed_wing_input(0.50, controls.advanced_roll_expo)
	var pitch_full := controls.shape_advanced_fixed_wing_input(1.0, controls.advanced_pitch_expo)
	var pitch_negative := controls.shape_advanced_fixed_wing_input(-0.50, controls.advanced_pitch_expo)
	var yaw_below_deadzone := controls.shape_advanced_fixed_wing_raw_input(0.04, controls.advanced_yaw_expo, 0.05)
	var yaw_half_trigger := controls.shape_advanced_fixed_wing_raw_input(0.50, controls.advanced_yaw_expo, 0.05)
	var yaw_full_trigger := controls.shape_advanced_fixed_wing_raw_input(1.0, controls.advanced_yaw_expo, 0.05)
	var yaw_half_negative := controls.shape_advanced_fixed_wing_raw_input(-0.50, controls.advanced_yaw_expo, 0.05)

	_expect(absf(pitch_small - 0.06535) < 0.0001, "advanced pitch lost its finite center response")
	_expect(absf(pitch_half - 0.36875) < 0.0001, "advanced half-stick pitch mapping changed")
	_expect(absf(roll_half - 0.40625) < 0.0001, "advanced half-stick roll mapping changed")
	_expect(is_equal_approx(pitch_full, 1.0), "advanced full stick no longer reaches full command")
	_expect(absf(pitch_negative + pitch_half) < 0.0001, "advanced response is not symmetric")
	_expect(is_zero_approx(yaw_below_deadzone), "advanced rudder did not apply its 5 percent deadzone")
	_expect(absf(yaw_half_trigger - 0.4186) < 0.0001, "advanced half-trigger rudder mapping changed")
	_expect(is_equal_approx(yaw_full_trigger, 1.0), "advanced full trigger no longer reaches full rudder")
	_expect(absf(yaw_half_negative + yaw_half_trigger) < 0.0001, "advanced rudder response is not symmetric")
	_expect(
		controls.shape_advanced_fixed_wing_input(0.50, 0.0) == 0.50,
		"zero expo is not linear"
	)

	var pause_source := FileAccess.get_file_as_string("res://UI/PauseMenu.gd")
	_expect(
		pause_source.contains("const DEFAULT_STICK_DEADZONE_INDEX := 0"),
		"Gameplay stick deadzone does not roll out at 5 percent"
	)
	var controls_source := FileAccess.get_file_as_string(
		"res://addons/simplified_flightsim/aircraft_modules/Controls/ControlSteering.gd"
	)
	_expect(
		controls_source.contains("if advanced_fixed_wing else _shape_input"),
		"legacy Simplified/helicopter shaping is no longer isolated from Advanced"
	)

	controls.free()
	if _failures.is_empty():
		print("[FixedWingInputResponseSmoketest] PASS deadzone=5% expo=0.35/0.25/0.15 half=0.369/0.406/0.419 full=1.0")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FixedWingInputResponseSmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
