extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_expect(InputMap.has_action("toggle_nightvision"), "toggle_nightvision input action is missing")
	_expect(_action_has_physical_key("toggle_nightvision", KEY_N), "N is not bound to night vision")
	var n_press := InputEventKey.new()
	n_press.physical_keycode = KEY_N
	n_press.pressed = true
	_expect(
		n_press.is_action_pressed("toggle_nightvision"),
		"an N key press does not trigger the night-vision action"
	)

	for action in InputMap.get_actions():
		if action == &"toggle_nightvision":
			continue
		_expect(
			not _action_has_physical_key(action, KEY_N),
			"N is also bound to %s" % action
		)

	if _failures.is_empty():
		print("[NightVisionInputSmoketest] PASS key=N action=toggle_nightvision conflicts=none")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[NightVisionInputSmoketest] %s" % failure)
	get_tree().quit(1)


func _action_has_physical_key(action: StringName, keycode: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
