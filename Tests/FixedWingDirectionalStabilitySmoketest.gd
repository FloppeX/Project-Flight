extends SceneTree

const AIRCRAFT_5_SCENE_PATH := "res://Aircraft/Aircraft_5.tscn"
const AIRCRAFT_14_SCENE_PATH := "res://Aircraft/Aircraft_14.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	var baseline_scene := load(AIRCRAFT_5_SCENE_PATH) as PackedScene
	var spitewing_scene := load(AIRCRAFT_14_SCENE_PATH) as PackedScene
	_expect(baseline_scene != null and spitewing_scene != null, "aircraft scenes did not load")
	if baseline_scene == null or spitewing_scene == null:
		_finish()
		return
	var baseline_aircraft := baseline_scene.instantiate() as RigidBody3D
	var spitewing := spitewing_scene.instantiate() as RigidBody3D
	_expect(baseline_aircraft != null and spitewing != null, "aircraft scenes did not instantiate")
	if baseline_aircraft == null or spitewing == null:
		_finish()
		return
	var baseline_aero := baseline_aircraft.get_node_or_null("SimpleAero")
	var aero := spitewing.get_node_or_null("SimpleAero")
	_expect(baseline_aero != null and aero != null, "SimpleAero was not found")
	if baseline_aero == null or aero == null:
		baseline_aircraft.free()
		spitewing.free()
		_finish()
		return

	_expect(is_equal_approx(float(baseline_aero.get("directional_stability_strength")), 2.4), "Aircraft_5 baseline directional stability is not 2.4")
	_expect(is_equal_approx(float(aero.get("directional_stability_strength")), 4.0), "Spitewing directional stability is not 4.0")
	_expect(is_equal_approx(float(aero.get("directional_stability_max_torque_per_mass")), 1.25), "Spitewing directional torque cap is not 1.25")

	var right_slip := Vector3(20.0, 0.0, 80.0)
	var left_slip := Vector3(-20.0, 0.0, 80.0)
	var right_torque := float(aero.call("get_directional_stability_torque_per_mass", right_slip, 0.0, 0.0))
	var left_torque := float(aero.call("get_directional_stability_torque_per_mass", left_slip, 0.0, 0.0))
	_expect(right_torque > 0.0, "right sideslip did not command a right restoring moment")
	_expect(left_torque < 0.0, "left sideslip did not command a left restoring moment")
	_expect(absf(right_torque + left_torque) < 0.001, "mirrored sideslip did not produce mirrored torque")

	var capped_torque := float(aero.call("get_directional_stability_torque_per_mass", Vector3(200.0, 0.0, 80.0), 0.0, 0.0))
	_expect(absf(capped_torque) <= 1.251, "directional stability exceeded its per-mass torque cap")
	_expect(absf(capped_torque) >= 1.249, "large sideslip did not reach the configured torque cap")

	var correcting_torque := float(aero.call("get_directional_stability_torque_per_mass", right_slip, 0.5, 0.0))
	var opposing_torque := float(aero.call("get_directional_stability_torque_per_mass", right_slip, -0.5, 0.0))
	_expect(absf(correcting_torque) < absf(right_torque), "yaw-rate damping did not soften an established correction")
	_expect(absf(opposing_torque) > absf(right_torque), "yaw-rate damping did not oppose motion away from the wind")

	var low_speed_torque := float(aero.call("get_directional_stability_torque_per_mass", Vector3(5.0, 0.0, 20.0), 0.0, 0.0))
	var departure_torque := float(aero.call("get_directional_stability_torque_per_mass", right_slip, 0.0, 1.0))
	_expect(absf(low_speed_torque) < absf(right_torque) * 0.25, "low-airflow directional stability did not fade")
	_expect(absf(departure_torque) < absf(right_torque) * 0.10, "deep-departure directional stability did not release")

	var header: PackedStringArray = aero.call("_aero_report_header").split(",")
	_expect(header.has("directional_sideslip_deg"), "flight recorder omitted directional sideslip")
	_expect(header.has("directional_stability_torque_nm"), "flight recorder omitted directional torque")

	print("[FixedWingDirectionalStabilitySmoketest] measured beta=%.1fdeg torque=%.3f cap=%.2f low=%.3f departure=%.3f" % [
		rad_to_deg(float(aero.call("get_signed_sideslip_angle_rad", right_slip))),
		right_torque,
		capped_torque,
		low_speed_torque,
		departure_torque,
	])
	baseline_aircraft.free()
	spitewing.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[FixedWingDirectionalStabilitySmoketest] PASS sign+cap+damping+airflow+departure+telemetry")
		quit(0)
		return
	for failure in _failures:
		push_error("[FixedWingDirectionalStabilitySmoketest] %s" % failure)
	quit(1)
