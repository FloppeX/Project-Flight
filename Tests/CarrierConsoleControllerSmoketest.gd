extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var console := root.get_node_or_null("CarrierConsole")
	var pause_menu := root.get_node_or_null("PauseMenu")
	if console == null or pause_menu == null:
		_fail("carrier console or pause menu autoload is missing")
		return
	console.call("show_page", "tactical", true)
	await process_frame
	_expect(bool(console.call("is_open")), "command screen did not open")
	var cursor_motion: Vector2 = console.call("controller_cursor_motion", Vector2(0.8, 0.0), 1.0 / 60.0, Vector2(1920, 1080))
	_expect(cursor_motion.x > 0.0 and absf(cursor_motion.y) < 0.01, "left stick does not move the cursor")
	_expect((console.call("controller_cursor_motion", Vector2(0.1, 0.0), 1.0 / 60.0, Vector2(1920, 1080)) as Vector2).is_zero_approx(), "stick deadzone does not stop cursor drift")
	var old_cursor_setting := bool(pause_menu.get("_controller_menu_cursor_enabled"))
	pause_menu.set("_controller_menu_cursor_enabled", true)
	var a_button := _button(JOY_BUTTON_A, true)
	_expect(not bool(pause_menu.call("controller_menu_cursor_claims_event", a_button)), "pause-menu cursor still claims command-screen clicks")
	pause_menu.set("_controller_menu_cursor_enabled", old_cursor_setting)

	console.call("_input", _button(JOY_BUTTON_RIGHT_SHOULDER, true))
	_expect(str(console.call("get_current_page")) == "air_wing", "right shoulder did not advance one tab")
	console.call("_input", _button(JOY_BUTTON_LEFT_SHOULDER, true))
	_expect(str(console.call("get_current_page")) == "tactical", "left shoulder did not return one tab")
	console.call("_input", _button(JOY_BUTTON_LEFT_SHOULDER, true))
	_expect(str(console.call("get_current_page")) == "replicator", "left shoulder did not wrap to the final tab")

	var nav_buttons: Dictionary = console.get("_nav_buttons")
	var personnel := nav_buttons.get("personnel") as Button
	if personnel != null and DisplayServer.get_name() != "headless" \
			and personnel.get_global_rect().has_point(root.get_mouse_position()):
		console.call("_input", a_button)
		await process_frame
		console.call("_input", _button(JOY_BUTTON_A, false))
		await process_frame
		_expect(str(console.call("get_current_page")) == "personnel", "A click did not activate the button under the cursor")
	elif personnel == null:
		_expect(false, "personnel tab button is missing")
	else:
		console.call("_input", a_button)
		_expect(bool(console.get("_cursor_a_pressed")), "A press did not start a cursor click")
		console.call("_input", _button(JOY_BUTTON_A, false))
		_expect(not bool(console.get("_cursor_a_pressed")), "A release left the cursor click held")
	if DisplayServer.get_name() != "headless":
		console.call("show_page", "tactical", true)
		await process_frame
		var tactical := root.get_node_or_null("WorldMapOverlay")
		if tactical != null:
			tactical.set("_map_zoom", 4.0)
			tactical.set("_map_view_center_uv", Vector2(0.8, 0.2))
			tactical.call("_apply_map_view")
			await process_frame
			var overview_preview := root.get_texture().get_image()
			var overview_path := "user://carrier_console_overview_preview.png"
			if overview_preview != null and overview_preview.save_png(overview_path) == OK:
				print("[CarrierConsoleControllerSmoketest] overview_screenshot=%s" % ProjectSettings.globalize_path(overview_path))

	console.call("set_open", false)
	_expect(not bool(console.call("is_open")), "command screen did not close")
	_finish()


func _button(button_index: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = pressed
	return event


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _fail(message: String) -> void:
	push_error("[CarrierConsoleControllerSmoketest] %s" % message)
	quit(1)


func _finish() -> void:
	if failures.is_empty():
		print("[CarrierConsoleControllerSmoketest] PASS stick_cursor=true shoulders=true a_click_input=true")
		quit(0)
		return
	for failure in failures:
		push_error("[CarrierConsoleControllerSmoketest] %s" % failure)
	quit(1)
