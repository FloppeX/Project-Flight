extends Node

const DAY_NIGHT_CYCLE_SCRIPT: Script = preload("res://Environment/DayNightCycle.gd")

var _failures: PackedStringArray = []


func _ready() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = Environment.new()
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	add_child(sun)

	var cycle := Node.new()
	cycle.set_script(DAY_NIGHT_CYCLE_SCRIPT)
	cycle.set("dust_deck_grid_cells", 8)
	add_child(cycle)
	# This fixture tests authored cycle behavior independently of user preferences.
	cycle.call("apply_fixed_time_setting", false, 720)
	_expect(not bool(cycle.get("freeze_daytime")), "normal day/night cycle still starts frozen")

	cycle.set("phase_duration_s", 300.0)
	cycle.set("update_interval_s", 10.0)
	cycle.set("_t", 0.0)
	cycle.call("_process", 1.0)
	var expected_t := 1.0 / (300.0 * 4.0)
	_expect(
		absf(float(cycle.get("_t")) - expected_t) < 0.000001,
		"enabled day/night clock did not advance at the authored rate"
	)

	cycle.set("freeze_daytime", true)
	cycle.set("frozen_daytime_t", 0.25)
	cycle.call("_process", 1.0)
	_expect(
		is_equal_approx(float(cycle.get("_t")), 0.25),
		"test-mode daylight freeze no longer holds the authored daytime point"
	)

	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	for far_m in [1800.0, 2500.0, 3500.0, 5000.0, 6500.0]:
		camera.far = far_m
		cycle.call("_update", 0.25)
		var environment := world_environment.environment
		_expect(environment.fog_enabled and environment.volumetric_fog_enabled, "distance fade and volumetric atmosphere must coexist")
		_expect(environment.fog_mode == Environment.FOG_MODE_DEPTH and is_equal_approx(environment.fog_density, 1.0), "far terrain must fade completely")
		_expect(environment.fog_depth_begin > far_m * 0.4 and environment.fog_depth_end < far_m, "distance fog must preserve nearby detail and finish before clipping")
		_expect(environment.volumetric_fog_length < environment.fog_depth_end, "sky and faded terrain must share the same integrated fog depth")
		_expect(is_equal_approx(environment.fog_depth_end / far_m, 0.94), "fog must follow view-distance changes")
	camera.position.y = 6000.0
	cycle.call("_update", 0.25)
	_expect(world_environment.environment.fog_enabled, "climbing above dust must retain the distant cutoff fade")
	cycle.free()
	if _failures.is_empty():
		print("DAY_NIGHT_CYCLE_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[DayNightCycleSmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
