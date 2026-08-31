extends SceneTree

const SIMPLE_AERO_PATH := "res://Aircraft/SimpleAero.gd"
const EXPECTED_CLEAN_LEVEL_SPEED_MPS: Array[float] = [
	107.8,
	134.5,
	119.2,
	127.0,
	127.0,
	57.8,
	160.0,
	153.4,
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var aero_source := FileAccess.get_file_as_string(SIMPLE_AERO_PATH)
	_expect(not aero_source.is_empty(), "could not read %s" % SIMPLE_AERO_PATH)
	_expect(
		"rb.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE" in aero_source,
		"fixed-wing startup does not replace project damping"
	)
	_expect(
		"rb.linear_damp = 0.0" in aero_source,
		"fixed-wing startup does not explicitly zero linear damping"
	)

	var default_drag_scale := _read_float_setting(aero_source, "forward_drag_scale", -1.0)
	var default_drag_strength := _read_float_setting(aero_source, "forward_drag_strength", -1.0)
	var default_drag_base := _read_float_setting(aero_source, "drag_base_multiplier", -1.0)
	_expect(is_equal_approx(default_drag_scale, 2.20), "default forward_drag_scale is not 2.20")
	_expect(default_drag_strength > 0.0, "default forward_drag_strength is invalid")
	_expect(default_drag_base > 0.0, "default drag_base_multiplier is invalid")

	var measured_ceilings := PackedStringArray()
	for index in EXPECTED_CLEAN_LEVEL_SPEED_MPS.size():
		var aircraft_number := index + 1
		var scene_path := "res://Aircraft/Aircraft_%d.tscn" % aircraft_number
		var scene_source := FileAccess.get_file_as_string(scene_path)
		_expect(not scene_source.is_empty(), "could not read %s" % scene_path)
		if scene_source.is_empty():
			continue
		var thrust_n := _read_float_setting(scene_source, "PowerFactor", -1.0)
		var drag_scale := _read_float_setting(scene_source, "forward_drag_scale", default_drag_scale)
		var drag_strength := _read_float_setting(scene_source, "forward_drag_strength", default_drag_strength)
		var drag_base := _read_float_setting(scene_source, "drag_base_multiplier", default_drag_base)
		var drag_coefficient := drag_scale * drag_strength * drag_base
		_expect(thrust_n > 0.0, "Aircraft_%d has invalid engine thrust" % aircraft_number)
		_expect(drag_coefficient > 0.0, "Aircraft_%d has invalid clean drag coefficient" % aircraft_number)
		if thrust_n <= 0.0 or drag_coefficient <= 0.0:
			continue
		var clean_level_speed_mps := sqrt(thrust_n / drag_coefficient)
		var expected_speed_mps := EXPECTED_CLEAN_LEVEL_SPEED_MPS[index]
		_expect(
			absf(clean_level_speed_mps - expected_speed_mps) < 0.6,
			"Aircraft_%d clean ceiling %.1f m/s differs from expected %.1f m/s" % [
				aircraft_number,
				clean_level_speed_mps,
				expected_speed_mps,
			]
		)
		measured_ceilings.append("A%d=%.1f" % [aircraft_number, clean_level_speed_mps])

	if _failures.is_empty():
		print("[FixedWingDragSmoketest] PASS scale=2.20 half_thrust=true ceilings_mps=%s" % ",".join(measured_ceilings))
		quit(0)
		return
	for failure in _failures:
		push_error("[FixedWingDragSmoketest] %s" % failure)
	quit(1)


func _read_float_setting(source: String, property_name: String, fallback: float) -> float:
	var expression := RegEx.new()
	var compile_error := expression.compile(
		"(?m)^[ \\t]*(?:@export\\s+var\\s+)?"
		+ property_name
		+ "(?:\\s*:\\s*float)?\\s*=\\s*([0-9.]+)"
	)
	if compile_error != OK:
		_failures.append("could not compile setting expression for %s" % property_name)
		return fallback
	var match_result := expression.search(source)
	if match_result == null:
		return fallback
	return float(match_result.get_string(1))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
