extends "res://Tests/Aircraft5ControlAuthorityInvestigation.gd"
# Paired production-aircraft runs: direct surface commands, free rotation/translation.
class FlatTerrain extends Node3D:
	func get_height(_p: Vector3) -> float: return 0.0
func _run() -> void:
	var terrain := FlatTerrain.new()
	add_child(terrain)
	terrain.add_to_group("terrain_provider")
	get_node("/root/TerrainReference").terrain_node = terrain
	var curve := SimpleAero.new()
	curve.set_flight_model_override_for_testing(1)
	curve.progressive_control_authority_enabled = true
	for axis in [&"pitch", &"roll", &"yaw"]:
		var slow := curve.get_axis_control_authority_at_speed(30.0,axis,42.0)
		var fast := curve.get_axis_control_authority_at_speed(100.0,axis,42.0)
		if not slow < fast * 0.5: _failures.append("low-speed authority not substantially softer")
		if curve.get_axis_control_authority_at_speed(0.0,axis,42.0) > 0.001: _failures.append("control torque remains at zero airflow")
		if not is_equal_approx(slow,curve.get_axis_control_authority_at_speed(30.0,axis,32.76)):
			_failures.append("flaps spuriously boost surface authority")
		if curve.get_axis_control_authority_at_speed(70.0,axis,42.0) < 0.99:
			_failures.append("normal control power not restored by 70 m/s")
	if curve.get_progressive_rate_damping_factor(60.0,0.0) <= 0.36:
		_failures.append("damping cancels progressive control weakening")
	curve.set_flight_model_override_for_testing(0)
	if curve.get_axis_control_authority_at_speed(60.0,&"pitch",42.0) < 0.99:
		_failures.append("Simplified authority changed")
	curve.free()
	var all_results: Dictionary = {}
	for axis in ["pitch","roll","yaw"]:
		var configs: Array[Dictionary] = []
		for speed in [55.0,65.0,82.0,100.0]:
			for progressive in [false,true]:
				configs.append({"name":"%s_%d_%s" % [axis,speed,progressive],"speed_mps":speed,"progressive":progressive,"kind":"paired_speed"})
		var trials := await _spawn_trials(configs)
		for trial in trials: trial.aero.progressive_control_authority_enabled = trial.config.progressive
		await _warm_up(trials)
		var results: Array[Dictionary]
		match axis:
			"pitch": results = await _run_pull_trials(trials)
			"roll": results = await _run_roll_trials(trials)
			"yaw": results = await _run_yaw_trials(trials)
		all_results[axis] = results
		var key := "peak_pitch_rate_deg_s" if axis == "pitch" else ("peak_roll_rate_deg_s" if axis == "roll" else "peak_yaw_rate_deg_s")
		for i in range(0,results.size(),2):
			var old_rate := float(results[i][key])
			var new_rate := float(results[i+1][key])
			print("[ProgressiveControl] %s speed=%.0f old=%.2f new=%.2f deg/s" % [axis,configs[i].speed_mps,old_rate,new_rate])
			if i == 0 and new_rate >= old_rate * 0.95: _failures.append("%s launch-speed response did not soften" % axis)
			if new_rate < 1.0: _failures.append("%s lost useful control" % axis)
		await _free_trials(trials)
	var report := FileAccess.open("res://captures/progressive_control_results.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(all_results,"\t"))
	for failure in _failures: push_error(failure)
	print("[ProgressiveControl] PASS" if _failures.is_empty() else "[ProgressiveControl] FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)
