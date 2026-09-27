extends SceneTree

var failures: Array[String] = []
var menu: Node
var controls: Node

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	await process_frame
	menu = root.get_node("PauseMenu")
	var director := root.get_node("FlightDirector")
	menu._open()
	menu.enter_photo_mode()
	controls = director._photo_camera_controls
	controls.set_process(false)
	var camera: Camera3D = director._free_camera
	camera.global_transform = Transform3D.IDENTITY
	camera.fov = 70.0
	_expect(paused, "photo controls keep world paused")
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	controls._process(0.1)
	_expect(camera.position.z < 0.0, "left stick forward")
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	var stopped := camera.global_position
	controls._process(0.1)
	_expect(camera.global_position.is_equal_approx(stopped), "no drift on release")
	_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	controls._process(0.1)
	_expect(camera.position.y > stopped.y, "RB raises camera")
	_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	var raised_y := camera.position.y
	_button(JOY_BUTTON_LEFT_SHOULDER, true)
	controls._process(0.1)
	_button(JOY_BUTTON_LEFT_SHOULDER, false)
	_expect(camera.position.y < raised_y, "LB lowers camera")
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	controls._process(0.1)
	_expect(camera.fov > 70.0, "LT zooms out")
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	controls._process(0.1)
	_expect(is_equal_approx(camera.fov, 70.0), "RT zooms in")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_button(JOY_BUTTON_DPAD_LEFT, true)
	controls._process(0.1)
	_expect(camera.rotation.z > 0.0, "D-pad left matches trailer roll sign")
	_button(JOY_BUTTON_DPAD_LEFT, false)
	_button(JOY_BUTTON_DPAD_RIGHT, true)
	controls._process(0.1)
	_expect(absf(camera.rotation.z) < 0.001, "D-pad right reverses roll")
	_button(JOY_BUTTON_DPAD_RIGHT, false)
	var level: int = controls.move_speed_level
	_button(JOY_BUTTON_DPAD_UP, true)
	_button(JOY_BUTTON_DPAD_UP, true)
	_expect(controls.move_speed_level == level + 1, "speed steps once per press")
	_button(JOY_BUTTON_DPAD_UP, false)
	controls._process(0.0)
	_expect(is_equal_approx(controls.move_speed, 20.0), "speed doubles")
	_button(JOY_BUTTON_DPAD_DOWN, true)
	_button(JOY_BUTTON_DPAD_DOWN, false)
	for i in 20:
		_button(JOY_BUTTON_DPAD_DOWN, true)
		_button(JOY_BUTTON_DPAD_DOWN, false)
	_expect(controls.move_speed_level == 0, "minimum speed clamp")
	for i in 30:
		_button(JOY_BUTTON_DPAD_UP, true)
		_button(JOY_BUTTON_DPAD_UP, false)
	_expect(controls.move_speed_level == 9, "maximum speed clamp")
	# Compare the complete free-camera pose against the actual trailer rig math.
	controls.move_speed_level = 4
	controls._clear_input()
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(0.2, 0.3, -0.4)), Vector3(1, 2, 3))
	var rig = load("res://Recording/RecordingCamera.gd").new()
	root.add_child(rig)
	rig.global_transform = camera.global_transform
	rig.offset = rig.global_transform
	rig.move_speed = 10.0
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	_button(JOY_BUTTON_DPAD_LEFT, true)
	controls._process(0.1)
	rig.move_camera(Vector3.RIGHT, Vector2(1, -1) * 0.14, 1.0, 0.1)
	_expect(camera.global_transform.is_equal_approx(rig.global_transform), "photo pose matches trailer free-camera motion")
	rig.free()
	controls._on_pad_connection(0, false)
	stopped = camera.global_position
	controls._process(0.1)
	_expect(camera.global_position.is_equal_approx(stopped), "disconnect clears held inputs")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.pressed = true
	menu._input(mouse)
	_expect(controls._editing, "RMB edits view")
	var motion_event := InputEventMouseMotion.new()
	motion_event.relative = Vector2(25, 15)
	menu._input(motion_event)
	var old_basis := camera.global_basis
	controls._process(0.1)
	_expect(not camera.global_basis.is_equal_approx(old_basis), "mouse aims")
	controls._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_expect(not controls._editing and controls.motion.is_zero_approx(), "focus loss clears editing")
	mouse.button_index = MOUSE_BUTTON_WHEEL_UP
	menu._input(mouse)
	_expect(is_equal_approx(camera.fov, 68.0), "wheel zoom")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	controls._process(10.0)
	_expect(is_equal_approx(camera.fov, 15.0), "minimum FOV clamp")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	controls._process(10.0)
	_expect(is_equal_approx(camera.fov, 110.0), "maximum FOV clamp")
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	stopped = camera.global_position
	_axis(JOY_AXIS_LEFT_X, 1.0)
	controls.set_process(true)
	for frame in 3: await process_frame
	_expect(paused and camera.global_position.distance_to(stopped) > 0.001, "live camera process moves while world paused")
	controls.set_process(false)
	_button(JOY_BUTTON_B, true)
	_expect(not menu.is_photo_mode_active() and not controls.active and menu.visible, "B exits to pause menu")
	menu.enter_photo_mode()
	controls.set_process(false)
	_expect(controls._pad_axes.is_empty() and not controls._editing, "reentry clears held input")
	menu.exit_photo_mode()
	menu._close()
	print("PHOTO_CAMERA_CONTROLS_SMOKETEST " + JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _axis(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	menu._input(event)

func _button(button: int, pressed_: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed_
	menu._input(event)

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
