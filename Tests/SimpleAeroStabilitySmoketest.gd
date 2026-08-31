extends Node

var _failures: Array[String] = []


func _ready() -> void:
	var aero := SimpleAero.new()

	aero.actual_pitch_control = 0.0
	var neutral_factor := aero._get_pitch_stability_input_release_factor()
	_expect(is_equal_approx(neutral_factor, 1.0), "neutral controls did not retain full pitch stability")

	aero.actual_pitch_control = 0.1
	var correction_factor := aero._get_pitch_stability_input_release_factor()
	_expect(correction_factor > 0.75, "a small pitch correction released too much hands-off stability")

	aero.actual_pitch_control = 0.5
	var pull_factor := aero._get_pitch_stability_input_release_factor()
	_expect(pull_factor <= 0.05, "a deliberate pull did not release pitch stability")

	aero.actual_pitch_control = -1.0
	var push_factor := aero._get_pitch_stability_input_release_factor()
	_expect(is_equal_approx(push_factor, aero.pitch_stability_input_min_factor), "full nose-down input did not receive the same stability release")

	_expect(pull_factor < correction_factor and correction_factor < neutral_factor, "pitch stability release was not progressive")

	aero.free()
	if _failures.is_empty():
		print("[SimpleAeroStabilitySmoketest] PASS neutral=%.3f correction=%.3f pull=%.3f push=%.3f" % [
			neutral_factor,
			correction_factor,
			pull_factor,
			push_factor,
		])
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[SimpleAeroStabilitySmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
