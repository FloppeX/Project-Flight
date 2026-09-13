extends Node

const MAIN_MENU_SCENE := preload("res://UI/MainMenu.tscn")
const INPUT_OWNER_PATHS: Array[NodePath] = [
	NodePath("/root/FlightDirector"),
	NodePath("/root/CarrierConsole"),
	NodePath("/root/PauseMenu"),
	NodePath("/root/WorldMapOverlay"),
	NodePath("/root/ScreenshotCapture"),
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_input_states: Dictionary = {}
	for node_path in INPUT_OWNER_PATHS:
		var input_owner := get_node_or_null(node_path)
		if input_owner == null:
			_fail("missing input owner %s" % node_path)
			return
		original_input_states[node_path] = [
			input_owner.is_processing_input(),
			input_owner.is_processing_unhandled_input(),
			input_owner.is_processing_unhandled_key_input(),
		]

	var menu := MAIN_MENU_SCENE.instantiate() as Node3D
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	menu.call("_show_setup_menu")
	await get_tree().process_frame

	var name_edit := menu.get("_name_edit") as LineEdit
	var carrier := menu.get("_carrier_root") as Node3D
	var camera := menu.get("_camera") as Camera3D
	if name_edit == null or carrier == null or camera == null:
		_fail("name field, carrier, or camera was not created")
		return
	if get_viewport().gui_get_focus_owner() != name_edit or not name_edit.has_selection():
		_fail("opening campaign setup did not focus and select the generated carrier name")
		return
	if not bool(menu.call("_is_name_field_focused")):
		_fail("menu did not recognize active carrier-name editing")
		return
	for node_path in INPUT_OWNER_PATHS:
		var input_owner := get_node(node_path)
		if input_owner.is_processing_input() \
				or input_owner.is_processing_unhandled_input() \
				or input_owner.is_processing_unhandled_key_input():
			_fail("%s still accepted game commands while typing" % node_path)
			return
	if "--render" not in OS.get_cmdline_user_args():
		# Synthetic keyboard delivery is deterministic with the headless test
		# viewport. A real OS window may not own keyboard focus during automation.
		var flight_director := get_node("/root/FlightDirector")
		var free_camera_was_active := bool(flight_director.get("_free_camera_active"))
		var space_event := InputEventKey.new()
		space_event.pressed = true
		space_event.keycode = KEY_SPACE
		space_event.physical_keycode = KEY_SPACE
		space_event.unicode = 32
		Input.parse_input_event(space_event)
		await get_tree().process_frame
		space_event.pressed = false
		Input.parse_input_event(space_event)
		if bool(flight_director.get("_free_camera_active")) != free_camera_was_active:
			_fail("Space toggled the free camera while the carrier name had focus")
			return
		if name_edit.text != " ":
			_fail("Space was blocked from the carrier-name field instead of being typed")
			return

	name_edit.text = "RESOLUTE"
	name_edit.text_changed.emit(name_edit.text)
	var marker := menu.call("_carrier_ship_name_marker") as Node3D
	if marker == null or marker.name != &"ShipNameMarkerRight":
		_fail("name camera did not select the carrier's right-side name marker")
		return
	if str(marker.call("get_ship_name_text")) != "RESOLUTE":
		_fail("typed carrier name did not update the hull marker")
		return

	menu.set("_elapsed", 0.0)
	menu.call("_position_exterior_camera")
	camera.fov = float(menu.call("_target_camera_fov"))
	var look_target := menu.call("_camera_look_target") as Vector3
	camera.look_at(look_target, Vector3.UP)
	menu.call("_apply_setup_screen_framing", look_target)
	var marker_screen := camera.unproject_position(marker.global_position)
	var viewport_size := get_viewport().get_visible_rect().size
	if camera.is_position_behind(marker.global_position):
		_fail("right-side carrier name ended up behind its focused camera")
		return
	if marker_screen.x < viewport_size.x * 0.58 or marker_screen.x > viewport_size.x * 0.86:
		_fail("carrier name was not framed to the right of the setup form (x=%.1f of %.1f)" % [marker_screen.x, viewport_size.x])
		return
	if camera.global_position.distance_to(marker.global_position) > 150.0:
		_fail("focused name camera remained too far away to read the hull text")
		return

	if "--render" in OS.get_cmdline_user_args():
		for _frame in range(45):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures/main_menu")
		var capture_path := "res://captures/main_menu/carrier_name_focus.png"
		var capture_error := get_viewport().get_texture().get_image().save_png(capture_path)
		if capture_error != OK:
			_fail("could not save rendered carrier-name composition")
			return
		print("[MainMenuCarrierNameSmoketest] CAPTURE %s" % ProjectSettings.globalize_path(capture_path))

	var next_control := menu.get("_primary_value_button") as Button
	next_control.grab_focus()
	await get_tree().process_frame
	for node_path in INPUT_OWNER_PATHS:
		var input_owner := get_node(node_path)
		var expected: Array = original_input_states[node_path]
		if input_owner.is_processing_input() != bool(expected[0]) \
				or input_owner.is_processing_unhandled_input() != bool(expected[1]) \
				or input_owner.is_processing_unhandled_key_input() != bool(expected[2]):
			_fail("%s input state was not restored after leaving the name field" % node_path)
			return

	menu.queue_free()
	await get_tree().process_frame
	print("[MainMenuCarrierNameSmoketest] PASS input_blocked=5 live_name=true right_side_camera=true restored=true")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	push_error("[MainMenuCarrierNameSmoketest] FAIL %s" % reason)
	get_tree().quit(1)
