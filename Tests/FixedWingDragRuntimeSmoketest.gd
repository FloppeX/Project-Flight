extends Node

var _failures: Array[String] = []


func _ready() -> void:
	var untouched_body := RigidBody3D.new()
	untouched_body.name = "UntouchedBody"
	untouched_body.linear_damp_mode = RigidBody3D.DAMP_MODE_COMBINE
	untouched_body.linear_damp = 0.0
	add_child(untouched_body)

	var fixed_wing_body := RigidBody3D.new()
	fixed_wing_body.name = "FixedWingBody"
	fixed_wing_body.mass = 900.0
	fixed_wing_body.linear_damp_mode = RigidBody3D.DAMP_MODE_COMBINE
	fixed_wing_body.linear_damp = 0.0
	var aero := SimpleAero.new()
	aero.name = "SimpleAero"
	fixed_wing_body.add_child(aero)
	add_child(fixed_wing_body)
	# This smoke checks startup ownership/configuration, not flight forces. The
	# minimal RigidBody3D intentionally lacks aircraft-only feedback methods.
	aero.set_physics_process(false)

	await get_tree().process_frame
	_expect(
		fixed_wing_body.linear_damp_mode == RigidBody3D.DAMP_MODE_REPLACE,
		"SimpleAero startup did not replace project damping"
	)
	_expect(is_zero_approx(fixed_wing_body.linear_damp), "SimpleAero startup did not zero linear_damp")
	_expect(
		untouched_body.linear_damp_mode == RigidBody3D.DAMP_MODE_COMBINE,
		"a body without SimpleAero was unexpectedly changed"
	)
	_expect(is_equal_approx(aero.forward_drag_scale, 2.20), "runtime forward_drag_scale is not 2.20")

	var drag_coefficient := (
		aero.forward_drag_strength
		* aero.forward_drag_scale
		* aero.drag_base_multiplier
	)
	var clean_level_speed_mps := sqrt(6250.0 / drag_coefficient)
	_expect(
		absf(clean_level_speed_mps - 127.0) < 0.6,
		"Aircraft_5 reference ceiling %.1f m/s is outside the documented range" % clean_level_speed_mps
	)

	fixed_wing_body.queue_free()
	untouched_body.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("[FixedWingDragRuntimeSmoketest] PASS damp_mode=REPLACE scale=2.20 half_thrust=true aircraft_5_ceiling=%.1f" % clean_level_speed_mps)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FixedWingDragRuntimeSmoketest] %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
