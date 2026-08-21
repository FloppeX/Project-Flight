extends Node

var _failures: PackedStringArray = []


func _ready() -> void:
	var aircraft := RigidBody3D.new()
	aircraft.linear_velocity = Vector3(0.0, 0.0, 55.0)
	add_child(aircraft)

	var camera_rig := CockpitCamera.new()
	camera_rig.position = Vector3(0.0, 1.4, 0.25)
	camera_rig.set_physics_process(false)
	aircraft.add_child(camera_rig)

	# Existing aircraft velocity at activation must not create a false initial jolt.
	camera_rig._physics_process(1.0 / 60.0)
	_check(camera_rig.g_force_offset.length() < 0.0001, "initial velocity sample should not move the cockpit camera")

	# Simulate a very large forward acceleration combined with a 200 ms hitch.
	# The old linear lerp could overshoot far beyond its nominal maximum here.
	aircraft.set_meta("controls_disabled", true)
	aircraft.linear_velocity = Vector3(0.0, 0.0, 255.0)
	camera_rig._physics_process(0.2)
	var launch_displacement: Vector3 = camera_rig.position - camera_rig.base_position
	_check(launch_displacement.z >= -camera_rig.max_backward_offset - 0.0001, "launch acceleration must respect the 4 cm rearward camera limit")
	_check(launch_displacement.length() <= camera_rig.max_g_offset + 0.0001, "launch acceleration must still respect the general camera limit")

	# The new rear cap must not reduce forward head travel.
	var forward_offset := camera_rig._limit_camera_offset(Vector3(0.0, 0.0, 0.15))
	_check(is_equal_approx(forward_offset.z, 0.15), "forward camera travel should remain unchanged")

	# The same cap applies laterally without suppressing the effect altogether.
	camera_rig.g_force_offset = Vector3.ZERO
	camera_rig.last_velocity = Vector3.ZERO
	aircraft.remove_meta("controls_disabled")
	aircraft.linear_velocity = Vector3(200.0, 0.0, 0.0)
	camera_rig._physics_process(0.2)
	_check(absf(camera_rig.g_force_offset.x) > 0.15, "lateral G-force motion should remain visible")
	_check(camera_rig.g_force_offset.length() <= camera_rig.max_g_offset + 0.0001, "lateral motion must respect the same 20 cm limit")

	aircraft.free()
	if _failures.is_empty():
		print("COCKPIT_CAMERA_MOTION_SMOKE PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("COCKPIT_CAMERA_MOTION_SMOKE: %s" % failure)
	print("COCKPIT_CAMERA_MOTION_SMOKE FAIL count=%d" % _failures.size())
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
