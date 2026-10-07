extends SceneTree

var _failures: Array[String] = []
var _settings: Node
var _render := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_render = "--render" in OS.get_cmdline_user_args()
	_settings = root.get_node("PauseMenu")
	_settings.set("_display_mode_index", 0)
	_settings.set("_resolution_index", 1)
	await process_frame
	for autoload in root.get_children():
		if autoload != _settings:
			autoload.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("FloatingOrigin").set("enabled", false)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	_settings.set("visible", true)
	_settings.set("_fixed_time_enabled", true)
	_settings.set("_opentrack_enabled", false)
	_settings.call("_refresh_gameplay_button_labels")
	for screen in ["options", "audio", "graphics", "gameplay"]:
		_settings.call("_show_screen", screen)
		await _settle()
		_check_page(screen)
		if _render:
			await _capture("settings_" + screen + "_900p")
	_settings.set("_opentrack_enabled", true)
	_settings.call("_refresh_gameplay_button_labels")
	await _settle()
	_check_page("gameplay")
	if _render:
		await _capture("settings_gameplay_tracking_900p")
	var screens: Dictionary = _settings.get("_screens")
	var scroll := (screens["gameplay"] as Control).get_node("SettingsScroll") as ScrollContainer
	var controls: HBoxContainer = _settings.get("_fixed_time_controls")
	var hour: SpinBox = _settings.get("_fixed_time_hour")
	hour.get_line_edit().grab_focus()
	await _settle()
	_expect(scroll.scroll_vertical > 0, "Focusing a lower setting did not scroll it into view")
	_expect(scroll.get_global_rect().grow(1.0).encloses(controls.get_global_rect()), "Focused clock was clipped by the scroll area")
	if _render:
		await _capture("settings_gameplay_scrolled_900p")
	# Cover the smallest offered resolution with the same content and fonts.
	_settings.set("_resolution_index", 2)
	_settings.call("_apply_resolution_setting")
	_settings.call("_refresh_graphics_button_labels")
	await _settle()
	for screen in ["graphics", "gameplay"]:
		_settings.call("_show_screen", screen)
		(screens[screen] as Control).get_node("SettingsScroll").scroll_vertical = 0
		await _settle()
		_check_page(screen)
		if _render:
			await _capture("settings_" + screen + "_720p")
	_settings.set("visible", false)
	current_scene = null
	world.queue_free()
	await process_frame
	if _failures.is_empty():
		print("[SettingsLayoutRenderedProbe] PASS categories=4 text=fits groups=no_overlap focus=scrolls resolutions=900p+720p")
		quit(0)
	else:
		quit(1)


func _settle() -> void:
	for frame in range(4):
		await process_frame


func _check_page(screen: String) -> void:
	var screens: Dictionary = _settings.get("_screens")
	var page := screens[screen] as Control
	var scroll := page.get_node("SettingsScroll") as ScrollContainer
	_expect(scroll.follow_focus, "Scroll area does not follow keyboard/controller focus")
	var columns := scroll.get_child(0) as HBoxContainer
	for column in columns.get_children():
		var previous_bottom := -1.0
		for panel: PanelContainer in column.get_children():
			_expect(panel.position.y >= previous_bottom, "Settings groups overlap: " + panel.name)
			previous_bottom = panel.position.y + panel.size.y
			var content := panel.get_child(0) as VBoxContainer
			var previous_row_bottom := -1.0
			for row: Control in content.get_children():
				if not row.visible:
					continue
				_expect(row.position.y >= previous_row_bottom, "Settings rows overlap: " + panel.name)
				previous_row_bottom = row.position.y + row.size.y
				if row is Button:
					var button := row as Button
					var font := button.get_theme_font("font")
					var text_width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
					var style := button.get_theme_stylebox("normal")
					var required_width := text_width + style.content_margin_left + style.content_margin_right
					if button.icon != null:
						required_width += button.icon.get_width() + button.get_theme_constant("h_separation")
					_expect(required_width <= button.size.x + 1.0, "Setting label clips: " + button.text)
					_expect(button.size.y >= 54.0, "Setting target is too short: " + button.text)
	_expect(columns.size.x <= scroll.size.x, "Settings overflow horizontally")
	var registry: Dictionary = {}
	if screen != "options":
		registry = _settings.get("_" + screen + "_buttons")
	for control: Control in registry.values():
		_expect(scroll.is_ancestor_of(control), "Setting was left outside its organized content area")
	if screen == "gameplay":
		var buttons: Dictionary = _settings.get("_gameplay_buttons")
		_expect(buttons["hud_color"].get_parent() == buttons["hud_brightness"].get_parent(), "HUD settings were split between groups")
		_expect(buttons["opentrack_smoothing"].disabled == not bool(_settings.get("_opentrack_enabled")), "Tracking dependency not presented correctly")


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://logs/" + name + ".png")
	_expect(result == OK, "Failed screenshot: " + name)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[SettingsLayoutRenderedProbe] " + message)
