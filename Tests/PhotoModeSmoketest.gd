extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame

	var pause_menu := root.get_node_or_null("PauseMenu")
	var flight_director := root.get_node_or_null("FlightDirector")
	var screenshot_capture := root.get_node_or_null("ScreenshotCapture")
	_expect(pause_menu != null, "PauseMenu autoload is available")
	_expect(flight_director != null, "FlightDirector autoload is available")
	_expect(screenshot_capture != null and screenshot_capture.has_method("take_screenshot"), "ScreenshotCapture exposes photo capture")
	if pause_menu == null or flight_director == null:
		_finish()
		return

	var photo_button := _find_button_with_text(pause_menu, "PHOTO MODE")
	_expect(photo_button != null, "pause menu contains PHOTO MODE")

	var test_overlay := CanvasLayer.new()
	test_overlay.name = "PhotoModeVisibilityProbe"
	root.add_child(test_overlay)
	test_overlay.visible = true
	flight_director.set("is_player_controlling", true)

	pause_menu.call("_open")
	pause_menu.call("enter_photo_mode")
	await process_frame
	_expect(bool(pause_menu.call("is_photo_mode_active")), "photo mode becomes active")
	_expect(not pause_menu.visible, "pause menu is hidden in photo mode")
	_expect(not test_overlay.visible, "other main-viewport UI is hidden")
	_expect(bool(flight_director.call("is_photo_mode_camera_active")), "photo mode owns the free camera")
	_expect(bool(flight_director.call("is_free_camera_active")), "free camera is active")
	_expect(bool(flight_director.get("is_player_controlling")), "photo mode preserves player-control assignment")
	_expect(paused, "world remains paused in photo mode")

	var a_event := InputEventJoypadButton.new()
	a_event.button_index = 0
	a_event.pressed = true
	_expect(bool(pause_menu.call("_is_menu_accept_event", a_event)), "A is recognized as photo capture")
	var b_event := InputEventJoypadButton.new()
	b_event.button_index = 1
	b_event.pressed = true
	pause_menu.call("_input", b_event)
	await process_frame
	_expect(not bool(pause_menu.call("is_photo_mode_active")), "photo mode exits")
	_expect(pause_menu.visible, "pause menu returns after photo mode")
	_expect(test_overlay.visible, "previous UI visibility is restored")
	_expect(not bool(flight_director.call("is_photo_mode_camera_active")), "photo camera ownership is released")
	_expect(not bool(flight_director.call("is_free_camera_active")), "photo-owned free camera exits")
	_expect(bool(flight_director.get("is_player_controlling")), "player-control assignment remains restored")
	_expect(paused, "returning from photo mode stays in the pause menu")

	pause_menu.call("_close")
	flight_director.set("is_player_controlling", false)
	flight_director.call("_toggle_free_camera")
	_expect(bool(flight_director.call("is_free_camera_active")), "normal free camera can predate photo mode")
	pause_menu.call("_open")
	pause_menu.call("enter_photo_mode")
	pause_menu.call("exit_photo_mode")
	_expect(bool(flight_director.call("is_free_camera_active")), "pre-existing free camera remains active after photo mode")
	pause_menu.call("_close")
	flight_director.call("_toggle_free_camera")
	test_overlay.queue_free()
	_finish()


func _find_button_with_text(node: Node, wanted_text: String) -> Button:
	if node is Button and (node as Button).text == wanted_text:
		return node as Button
	for child in node.get_children():
		var found := _find_button_with_text(child, wanted_text)
		if found != null:
			return found
	return null


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("[PhotoModeSmoketest] FAIL: %s" % description)


func _finish() -> void:
	if _failures.is_empty():
		print("[PhotoModeSmoketest] PASS pause_menu+free_camera+ui_restore+screenshot_api")
		quit(0)
		return
	print("[PhotoModeSmoketest] %d failure(s)" % _failures.size())
	quit(1)
