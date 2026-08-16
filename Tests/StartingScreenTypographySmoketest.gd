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
	var options_title := _find_text_control(options_screen, "OPTIONS") as Label
	var graphics_action := _find_text_control(options_screen, "GRAPHICS >") as Button
	if not _matches_typography(options_title, MenuTypography.SCREEN_TITLE_SIZE):
		_fail("settings title did not match the main-menu title scale")
		return
	if not _matches_typography(graphics_action, MenuTypography.FIELD_VALUE_SIZE):
		_fail("settings action did not use the shared field-value style")
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


func _matches_typography(control: Control, expected_size: int) -> bool:
	if control == null:
		return false
	var font := control.get_theme_font("font")
	return font != null \
		and font.resource_path == MenuTypography.FONT.resource_path \
		and control.get_theme_font_size("font_size") == expected_size


func _fail(reason: String) -> void:
	push_error("[StartingScreenTypographySmoketest] FAIL %s" % reason)
	quit(1)
