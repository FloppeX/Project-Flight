extends SceneTree

const MenuTypography = preload("res://UI/MenuTypography.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_menu_source := FileAccess.get_file_as_string("res://UI/MainMenu.gd")
	if not main_menu_source.contains("MenuTypography.SCREEN_TITLE_SIZE") \
			or not main_menu_source.contains("MenuTypography.MENU_ITEM_SIZE") \
			or not main_menu_source.contains("MenuTypography.FONT") \
			or not main_menu_source.contains("MenuTypography.TECH_FONT") \
			or not main_menu_source.contains("SYS_ID: LC-992-ALPHA // OPERATOR CONSOLE") \
			or not main_menu_source.contains("const BASE_UI_SIZE := MenuTypography.CANVAS_SIZE"):
		_fail("main menu was not wired to the shared operator-console typography profile")
		return
	if MenuTypography.CANVAS_SIZE != Vector2(1920.0, 1080.0):
		_fail("startup UI canvas did not match the 1920x1080 game viewport")
		return
	var main_menu_section := main_menu_source.get_slice("func _build_main_menu", 1).get_slice("func _build_developer_menu", 0)
	for player_entry in ["NEW CAMPAIGN", "SKIRMISH", "TECHNICAL INDEX", "SETTINGS", "QUIT"]:
		if not main_menu_section.contains(player_entry):
			_fail("main menu was missing %s" % player_entry)
			return
	for development_entry in ["FREE FLIGHT", "LANDING TEST", "CARRIER COMBAT TEST", "CONTINUE", "CREDITS"]:
		if main_menu_section.contains(development_entry):
			_fail("main menu still exposed %s as a top-level choice" % development_entry)
			return
	if not main_menu_section.contains("DEVELOPMENT SCENARIOS") or not main_menu_section.contains("OS.is_debug_build()"):
		_fail("development scenarios were not consolidated behind a debug-only submenu")
		return

	var pause_menu := root.get_node_or_null("PauseMenu")
	if pause_menu == null:
		_fail("PauseMenu autoload was unavailable")
		return
	var screens: Dictionary = pause_menu.get("_screens")
	var pause_root := pause_menu.get("_ui_root") as Control
	if pause_root == null or pause_root.size != MenuTypography.CANVAS_SIZE:
		_fail("settings menu did not use the shared 1920x1080 canvas")
		return
	var options_screen := screens.get("options") as Control
	var options_title := _find_text_control(options_screen, "SETTINGS") as Label
	var graphics_action := _find_text_control(options_screen, "GRAPHICS >") as Button
	if not _matches_typography(options_title, MenuTypography.BRAND_TITLE_SIZE):
		_fail("settings title did not match the operator-console brand scale")
		return
	if not _matches_typography(graphics_action, MenuTypography.FIELD_VALUE_SIZE, MenuTypography.TECH_FONT):
		_fail("settings action did not use the shared field-value style")
		return
	var graphics_buttons: Dictionary = pause_menu.get("_graphics_buttons")
	for setting_key in ["display_mode", "frame_limit", "anti_aliasing", "render_scale", "upscaler", "view_distance"]:
		if not graphics_buttons.has(setting_key) or not (graphics_buttons[setting_key] is Button):
			_fail("graphics menu was missing %s" % setting_key)
			return
	if screens.has("codex"):
		_fail("obsolete pause-menu Codex screen was still registered")
		return
	var root_viewport := root as Viewport
	var original_aa_index := int(pause_menu.get("_anti_aliasing_index"))
	pause_menu.set("_anti_aliasing_index", 1)
	pause_menu.call("_apply_anti_aliasing_setting")
	if root_viewport.screen_space_aa != Viewport.SCREEN_SPACE_AA_SMAA \
			or root_viewport.msaa_3d != Viewport.MSAA_DISABLED \
			or root_viewport.use_taa:
		_fail("SMAA selection did not configure the root viewport exclusively")
		return
	pause_menu.set("_anti_aliasing_index", 3)
	pause_menu.call("_apply_anti_aliasing_setting")
	if root_viewport.msaa_3d != Viewport.MSAA_4X \
			or root_viewport.screen_space_aa != Viewport.SCREEN_SPACE_AA_DISABLED \
			or root_viewport.use_taa:
		_fail("MSAA 4x selection did not configure the root viewport exclusively")
		return
	pause_menu.set("_anti_aliasing_index", original_aa_index)
	pause_menu.call("_apply_anti_aliasing_setting")

	var original_render_scale_index := int(pause_menu.get("_render_scale_index"))
	var original_upscaler_index := int(pause_menu.get("_upscaler_index"))
	pause_menu.set("_render_scale_index", 3)
	pause_menu.set("_upscaler_index", 1)
	pause_menu.call("_apply_render_scale_setting")
	if not is_equal_approx(root_viewport.scaling_3d_scale, 0.85) \
			or root_viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR:
		_fail("85 percent FSR render scaling did not reach the root viewport")
		return
	pause_menu.set("_render_scale_index", original_render_scale_index)
	pause_menu.set("_upscaler_index", original_upscaler_index)
	pause_menu.call("_apply_render_scale_setting")

	pause_menu.call("open_settings_from_main_menu")
	if pause_menu.get("_current_screen") != "options" or not pause_menu.visible or not paused:
		_fail("main-menu settings did not open directly into the shared settings screen")
		return
	pause_menu.call("_navigate_back")
	if pause_menu.visible or paused:
		_fail("backing out of main-menu settings did not return control to the main menu")
		return

	var loading_screen := root.get_node_or_null("LoadingScreen")
	if loading_screen == null:
		_fail("LoadingScreen autoload was unavailable")
		return
	var loading_root := loading_screen.get("_root") as Control
	if loading_root == null:
		_fail("loading-screen root was unavailable")
		return
	for child in loading_root.get_children():
		if child is ColorRect:
			var rect := child as ColorRect
			if rect.anchor_left == 0.0 and rect.anchor_top == 0.0 \
					and rect.anchor_right == 1.0 and rect.anchor_bottom == 1.0:
				_fail("loading splash still had a full-screen dimming overlay")
				return
	var loading_label := loading_screen.get("_label") as Label
	if not _matches_typography(loading_label, MenuTypography.FIELD_VALUE_SIZE):
		_fail("loading status did not use the shared typography")
		return

	var fps_source := FileAccess.get_file_as_string("res://tools/FPSCounter.gd")
	if fps_source.contains("Hit Assist Radius") or fps_source.contains("_hit_assist_label"):
		_fail("hit-assist radius HUD remained visible")
		return

	var radio_comms := root.get_node_or_null("RadioComms")
	if radio_comms == null:
		_fail("RadioComms autoload was unavailable")
		return
	radio_comms.call("_update_display_visibility")
	var radio_canvas := radio_comms.get("_canvas") as CanvasLayer
	if radio_canvas == null or radio_canvas.visible:
		_fail("radio dialogue panel remained visible outside gameplay")
		return
	if not bool(radio_comms.call("_is_gameplay_scene_path", "res://Main_Scene.tscn")):
		_fail("radio dialogue panel did not recognize the gameplay scene")
		return

	print("[StartingScreenTypographySmoketest] PASS canvas=%s font=%s title=%d menu=%d overlays=menu_hidden" % [
		str(MenuTypography.CANVAS_SIZE),
		MenuTypography.FONT.resource_path,
		MenuTypography.SCREEN_TITLE_SIZE,
		MenuTypography.MENU_ITEM_SIZE,
	])
	quit(0)


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


func _matches_typography(control: Control, expected_size: int, expected_font: Font = MenuTypography.FONT) -> bool:
	if control == null:
		return false
	var font := control.get_theme_font("font")
	return font != null \
		and font.resource_path == expected_font.resource_path \
		and control.get_theme_font_size("font_size") == expected_size


func _fail(reason: String) -> void:
	push_error("[StartingScreenTypographySmoketest] FAIL %s" % reason)
	quit(1)
