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
	var pilot_roster := root.get_node_or_null("PilotRoster")
	_expect(pilot_roster != null, "PilotRoster autoload is available")
	if console == null or tactical == null or personnel == null:
		_finish()
		return

	_expect(not bool(console.call("is_open")), "console starts closed")
	if pilot_roster != null:
		var roster: Array = pilot_roster.call("get_carrier_roster")
		var used_portraits: Dictionary = {}
		_expect(not roster.is_empty(), "pilot roster contains pilots")
		for pilot_variant in roster:
			var pilot: Dictionary = pilot_variant
			var portrait_path := str(pilot.get("portrait_path", ""))
			var pilot_name := str(pilot.get("name", "Pilot"))
			_expect(portrait_path != "", "%s has a portrait" % str(pilot.get("name", "Pilot")))
			_expect(ResourceLoader.exists(portrait_path), "%s portrait exists" % str(pilot.get("name", "Pilot")))
			_expect(not used_portraits.has(portrait_path), "%s portrait is unique" % str(pilot.get("name", "Pilot")))
			_expect(is_zero_approx(float(pilot.get("air_kills", -1.0))), "%s starts with zero air kills" % pilot_name)
			_expect(is_zero_approx(float(pilot.get("ground_kills", -1.0))), "%s starts with zero ground kills" % pilot_name)
			_expect(is_zero_approx(float(pilot.get("mission_time_s", -1.0))), "%s starts with zero flight time" % pilot_name)
			_expect(int(pilot.get("sorties_flown", -1)) == 0, "%s starts with zero sorties" % pilot_name)
			used_portraits[portrait_path] = true

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
