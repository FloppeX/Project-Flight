extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pause_menu := root.get_node_or_null("PauseMenu")
	var radio_comms := root.get_node_or_null("RadioComms")
	var fps_counter := root.get_node_or_null("FPSCounter")
	if pause_menu == null or radio_comms == null or fps_counter == null:
		_fail("required settings autoloads were unavailable")
		return

	var screens: Dictionary = pause_menu.get("_screens")
	for screen_name in ["options", "audio", "graphics", "gameplay"]:
		if not screens.has(screen_name) or not (screens[screen_name] is Control):
			_fail("settings screen was missing %s" % screen_name)
			return
	var options_screen := screens["options"] as Control
	for entry_text in ["AUDIO >", "GRAPHICS >", "GAMEPLAY >", "RESET ALL DEFAULTS"]:
		if _find_text_control(options_screen, entry_text) == null:
			_fail("settings hub was missing %s" % entry_text)
			return

	var audio_sliders: Dictionary = pause_menu.get("_audio_sliders")
	var audio_buttons: Dictionary = pause_menu.get("_audio_buttons")
	for slider_key in ["master", "radio"]:
		if not audio_sliders.has(slider_key) or not (audio_sliders[slider_key] is HSlider):
			_fail("audio menu was missing %s volume" % slider_key)
			return
	for audio_key in ["captions", "caption_duration"]:
		if not audio_buttons.has(audio_key) or not (audio_buttons[audio_key] is Button):
			_fail("audio menu was missing %s" % audio_key)
			return

	var graphics_buttons: Dictionary = pause_menu.get("_graphics_buttons")
	if not graphics_buttons.has("show_fps") or not (graphics_buttons["show_fps"] is Button):
		_fail("graphics menu was missing the FPS toggle")
		return
	var gameplay_buttons: Dictionary = pause_menu.get("_gameplay_buttons")
	for gameplay_key in ["stick_deadzone", "look_sensitivity", "invert_look_y", "camera_motion", "camera_fov"]:
		if not gameplay_buttons.has(gameplay_key) or not (gameplay_buttons[gameplay_key] is Button):
			_fail("gameplay menu was missing %s" % gameplay_key)
			return

	var original_radio_volume := float(pause_menu.get("_radio_volume"))
	var original_captions := bool(pause_menu.get("_radio_captions_enabled"))
	var original_caption_duration := int(pause_menu.get("_radio_caption_duration_index"))
	var original_show_fps := bool(pause_menu.get("_show_fps_enabled"))
	var original_deadzone := int(pause_menu.get("_stick_deadzone_index"))
	var original_sensitivity := int(pause_menu.get("_look_sensitivity_index"))
	var original_invert_y := bool(pause_menu.get("_invert_look_y"))
	var original_motion := int(pause_menu.get("_camera_motion_index"))
	var original_fov := int(pause_menu.get("_camera_fov_index"))

	pause_menu.set("_radio_volume", 0.42)
	pause_menu.set("_radio_captions_enabled", false)
	pause_menu.set("_radio_caption_duration_index", 2)
	pause_menu.call("_apply_audio_settings")
	var radio_bus_index := AudioServer.get_bus_index("Radio")
	if radio_bus_index < 0 or not is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(radio_bus_index)), 0.42):
		_restore(pause_menu, original_radio_volume, original_captions, original_caption_duration,
				original_show_fps, original_deadzone, original_sensitivity, original_invert_y, original_motion, original_fov)
		_fail("radio volume did not reach the Radio bus")
		return
	if bool(radio_comms.get("captions_enabled")) or not is_equal_approx(float(radio_comms.get("message_linger_s")), 15.0):
		_restore(pause_menu, original_radio_volume, original_captions, original_caption_duration,
				original_show_fps, original_deadzone, original_sensitivity, original_invert_y, original_motion, original_fov)
		_fail("radio caption preferences did not reach RadioComms")
		return

	pause_menu.set("_show_fps_enabled", true)
	pause_menu.call("_apply_fps_counter_setting")
	if not bool(fps_counter.call("is_display_enabled")):
		_restore(pause_menu, original_radio_volume, original_captions, original_caption_duration,
				original_show_fps, original_deadzone, original_sensitivity, original_invert_y, original_motion, original_fov)
		_fail("FPS preference did not reach FPSCounter")
		return

	pause_menu.set("_stick_deadzone_index", 4)
	pause_menu.set("_look_sensitivity_index", 4)
	pause_menu.set("_invert_look_y", true)
	pause_menu.set("_camera_motion_index", 1)
	pause_menu.set("_camera_fov_index", 3)
	pause_menu.call("_apply_gameplay_settings")
	if not is_equal_approx(InputMap.action_get_deadzone("look_left"), 0.25) \
			or not is_equal_approx(float(pause_menu.call("get_look_sensitivity_multiplier")), 1.5) \
			or not bool(pause_menu.call("get_invert_look_y")) \
			or not is_equal_approx(float(pause_menu.call("get_camera_motion_scale")), 0.45) \
			or not is_equal_approx(float(pause_menu.call("get_camera_fov")), 85.0):
		_restore(pause_menu, original_radio_volume, original_captions, original_caption_duration,
				original_show_fps, original_deadzone, original_sensitivity, original_invert_y, original_motion, original_fov)
		_fail("gameplay preferences did not expose their configured runtime values")
		return

	for source_check in [
		["res://Camera/CockpitCamera.gd", "get_camera_motion_scale"],
		["res://Camera/camera_chase.gd", "get_look_sensitivity_multiplier"],
		["res://Camera/CameraController.gd", "get_camera_fov"],
		["res://LandCarrier/Commander.gd", "get_invert_look_y"],
	]:
		var source := FileAccess.get_file_as_string(source_check[0] as String)
		if not source.contains(source_check[1] as String):
			_restore(pause_menu, original_radio_volume, original_captions, original_caption_duration,
					original_show_fps, original_deadzone, original_sensitivity, original_invert_y, original_motion, original_fov)
			_fail("runtime consumer was not wired: %s" % source_check[0])
			return

	_restore(pause_menu, original_radio_volume, original_captions, original_caption_duration,
			original_show_fps, original_deadzone, original_sensitivity, original_invert_y, original_motion, original_fov)
	print("[SettingsOptionsSmoketest] PASS submenus=audio+graphics+gameplay runtime=radio+fps+input+camera")
	quit(0)


func _restore(
		pause_menu: Node,
		radio_volume: float,
		captions: bool,
		caption_duration: int,
		show_fps: bool,
		deadzone: int,
		sensitivity: int,
		invert_y: bool,
		motion: int,
		fov: int
) -> void:
	pause_menu.set("_radio_volume", radio_volume)
	pause_menu.set("_radio_captions_enabled", captions)
	pause_menu.set("_radio_caption_duration_index", caption_duration)
	pause_menu.set("_show_fps_enabled", show_fps)
	pause_menu.set("_stick_deadzone_index", deadzone)
	pause_menu.set("_look_sensitivity_index", sensitivity)
	pause_menu.set("_invert_look_y", invert_y)
	pause_menu.set("_camera_motion_index", motion)
	pause_menu.set("_camera_fov_index", fov)
	pause_menu.call("_apply_audio_settings")
	pause_menu.call("_apply_fps_counter_setting")
	pause_menu.call("_apply_gameplay_settings")


func _find_text_control(node: Node, target_text: String) -> Control:
	if node == null:
		return null
	if node is Label and (node as Label).text == target_text:
		return node as Control
	if node is Button and (node as Button).text == target_text:
		return node as Control
	for child in node.get_children():
		var found := _find_text_control(child as Node, target_text)
		if found != null:
			return found
	return null


func _fail(reason: String) -> void:
	push_error("[SettingsOptionsSmoketest] FAIL %s" % reason)
	quit(1)
