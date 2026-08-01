extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var console := root.get_node_or_null("CarrierConsole")
	var tactical := root.get_node_or_null("WorldMapOverlay")
	var personnel := root.get_node_or_null("PilotRosterOverlay")

	_expect(console != null, "CarrierConsole autoload is available")
	_expect(tactical != null, "WorldMapOverlay autoload is available")
	_expect(personnel != null, "PilotRosterOverlay autoload is available")
	if console == null or tactical == null or personnel == null:
		_finish()
		return

	_expect(not bool(console.call("is_open")), "console starts closed")

	var toggle_event := InputEventAction.new()
	toggle_event.action = &"map_toggle"
	toggle_event.pressed = true
	Input.parse_input_event(toggle_event)
	await process_frame
	_expect(bool(console.call("is_open")), "map_toggle opens the console")
	_expect(str(console.call("get_current_page")) == "tactical", "tactical is the default page")
	_expect(bool(tactical.call("is_console_visible")), "tactical page is visible")
	_expect(not bool(personnel.call("is_console_visible")), "personnel page is hidden")

	console.call("show_page", "personnel")
	await process_frame
	_expect(not bool(tactical.call("is_console_visible")), "tactical page hides after navigation")
	_expect(bool(personnel.call("is_console_visible")), "personnel page is visible")

	console.call("show_page", "air_wing")
	await process_frame
	_expect(not bool(tactical.call("is_console_visible")), "tactical page stays hidden on a planned page")
	_expect(not bool(personnel.call("is_console_visible")), "personnel page hides on a planned page")

	console.call("set_open", false)
	await process_frame
	_expect(not bool(console.call("is_open")), "console closes")
	_expect(not bool(tactical.call("is_console_visible")), "tactical page closes with the console")
	_expect(not bool(personnel.call("is_console_visible")), "personnel page closes with the console")
	_finish()


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("[CarrierConsoleSmokeTest] FAIL: %s" % description)


func _finish() -> void:
	if _failures.is_empty():
		print("[CarrierConsoleSmokeTest] PASS")
		quit(0)
		return
	print("[CarrierConsoleSmokeTest] %d failure(s)" % _failures.size())
	quit(1)
