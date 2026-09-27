extends SceneTree

const MenuStickNavigationGate = preload("res://UI/MenuStickNavigationGate.gd")


func _initialize() -> void:
	var gate = MenuStickNavigationGate.new()
	if gate.should_suppress(_axis(JOY_AXIS_LEFT_Y, 0.82)):
		_fail("first vertical stick deflection was suppressed")
		return
	if not gate.should_suppress(_axis(JOY_AXIS_LEFT_Y, 0.86)):
		_fail("held vertical stick generated another navigation press")
		return
	if not gate.should_suppress(_axis(JOY_AXIS_LEFT_Y, 0.68)):
		_fail("held-stick jitter below activation threshold escaped the gate")
		return
	if not gate.should_suppress(_axis(JOY_AXIS_LEFT_Y, 0.0)):
		_fail("stick release was forwarded as navigation")
		return
	if gate.should_suppress(_axis(JOY_AXIS_LEFT_Y, 0.80)):
		_fail("vertical stick did not re-arm after returning to center")
		return
	if gate.should_suppress(_axis(JOY_AXIS_LEFT_X, -0.80)):
		_fail("horizontal axis did not retain independent navigation state")
		return

	var dpad := InputEventJoypadButton.new()
	dpad.button_index = 12
	dpad.pressed = true
	if gate.should_suppress(dpad):
		_fail("D-pad input was changed by the stick gate")
		return

	for script_path in ["res://UI/MainMenu.gd", "res://UI/TitleScreen.gd", "res://UI/PauseMenu.gd"]:
		if load(script_path) == null:
			_fail("menu script failed to load: %s" % script_path)
			return

	print("MENU_STICK_NAVIGATION_PASS")
	quit(0)


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	return event


func _fail(reason: String) -> void:
	push_error("MENU_STICK_NAVIGATION_FAIL: %s" % reason)
	quit(1)
