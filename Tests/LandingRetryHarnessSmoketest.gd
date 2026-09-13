extends SceneTree


func _initialize() -> void:
	var observer_script := load("res://Scenario/GoAroundTestObserver.gd") as Script
	var harness_script := load("res://Scenario/LandingTestMode.gd") as Script
	var harness := Node3D.new()
	harness.set_script(harness_script)
	var passed: bool = observer_script.LANDING_RETRY_CASES.size() == 4
	for entry in observer_script.LANDING_RETRY_CASES:
		for forced_control in ["force_height_m", "miss_wire", "suppress_automatic_miss"]:
			passed = passed and not entry.has(forced_control)
	var attempt := {
		"spawn_index": 1, "outcome": "TIMEOUT", "escape_seen": true,
		"stopped": false, "hook_armed_final_samples": 120,
		"hook_inactive_final_samples": 0, "waveoffs": 1,
	}
	harness.set("_attempts", {"test": attempt})
	var result: Dictionary = harness.call("_build_matrix_result", "landing_retry")
	passed = passed and result.success_definition.begins_with("wire catch followed by")
	passed = passed and result.cases[0].recovery_quality == "failed"
	passed = passed and result.cases[0].hook_armed_final_samples == 120
	attempt.merge({"outcome": "CAUGHT", "wire_caught": true, "stopped": true,
		"part_damage_observed": true, "part_health_loss": 0.0}, true)
	result = harness.call("_build_matrix_result", "landing_retry")
	passed = passed and result.cases[0].recovery_quality == "clean_stop"
	harness.free()
	print("LANDING_RETRY_HARNESS_SMOKETEST %s cases=4 unforced_hooks=true stopped_catch_required=true" % ("PASS" if passed else "FAIL"))
	quit(0 if passed else 1)
