extends CanvasLayer
## Pause menu autoload.
## Opened by the pause_game action (Select/Back on gamepad, P on keyboard).
## Opening pauses the scene tree; closing unpauses it.
## Sub-screens: Controls reference, Codex stub.

const MENU_FONT: FontFile = preload("res://UI/Orbitron-VariableFont_wght.ttf")

const FONT_NORMAL   := 62
const FONT_SELECTED := 78
const MARGIN_X      := 150.0
const MARGIN_Y      := 80.0
const ITEM_STEP     := 96.0
const BASE_UI_SIZE  := Vector2(1280.0, 720.0)
const SUBMENU_X     := 620.0

const PAD_BUTTON_A         := 0
const PAD_BUTTON_B         := 1
const PAD_BUTTON_BACK      := 4
const PAD_BUTTON_DPAD_UP   := 11
const PAD_BUTTON_DPAD_DOWN := 12

const COLOR_WHITE   := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_DIM     := Color(1.0, 1.0, 1.0, 0.40)
const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.0)

# Controls / Codex panel colours (kept minimal for readability)
const COLOR_PANEL   := Color(0.04, 0.04, 0.04, 0.88)
const COLOR_AMBER   := Color(0.90, 0.75, 0.20, 1.0)
const COLOR_BODY    := Color(0.82, 0.82, 0.80, 1.0)

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION_AUDIO := "audio"
const SETTINGS_SECTION_GRAPHICS := "graphics"
const SETTINGS_SECTION_GAMEPLAY := "gameplay"
const GRAPHICS_SETTINGS_VERSION := 2
const DEFAULT_VIEW_DISTANCE_LEVEL := 3
const RUDDER_ASSIST_LABELS := [
	"OFF",
	"LIGHT",
	"FULL",
]
const RUDDER_ASSIST_STRENGTHS := [
	0.0,
	0.45,
	1.0,
]
const RESOLUTION_LABELS := [
	"1920 X 1080 FULLSCREEN",
	"1600 X 900 FULLSCREEN",
	"1280 X 720 FULLSCREEN",
	"2560 X 1440 FULLSCREEN",
	"3840 X 2160 FULLSCREEN",
]
const RESOLUTION_SIZES := [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]
const VIEW_DISTANCE_CHUNK_RADIUS := [2, 3, 4, 6, 8]
const VIEW_DISTANCE_CAMERA_FAR := [1800.0, 2500.0, 3500.0, 5000.0, 6500.0]

var _screens: Dictionary = {}
var _current_screen: String = ""
var _ui_root: Control = null
var _volume_slider: HSlider = null
var _graphics_buttons: Dictionary = {}
var _gameplay_buttons: Dictionary = {}
var _vsync_enabled: bool = false
var _resolution_index: int = 0
var _view_distance_level: int = DEFAULT_VIEW_DISTANCE_LEVEL
var _rudder_assist_level: int = 0
var _helicopter_rudder_assist_level: int = 1


func _ready() -> void:
	layer = 98
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_load_settings()
	_build_ui()
	if not get_tree().root.size_changed.is_connected(_layout_ui_root):
		get_tree().root.size_changed.connect(_layout_ui_root)
	_layout_ui_root()
	if not get_tree().node_added.is_connected(_on_scene_node_added):
		get_tree().node_added.connect(_on_scene_node_added)
	call_deferred("_apply_graphics_settings")


func _input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	if event.is_action_pressed("pause_game", false):
		if not visible:
			_open()
		else:
			_close()
		viewport.set_input_as_handled()
		return

	if not visible:
		return

	if _handle_pause_navigation_input(event):
		viewport.set_input_as_handled()


# ---------------------------------------------------------------------------
# Public
# ---------------------------------------------------------------------------

func _open() -> void:
	get_tree().paused = true
	visible = true
	_show_screen("main")


func _close() -> void:
	get_tree().paused = false
	visible = false
	_current_screen = ""


# ---------------------------------------------------------------------------
# Screen management
# ---------------------------------------------------------------------------

func _show_screen(name: String) -> void:
	for key: String in _screens:
		(_screens[key] as Control).visible = (key == name)
	_current_screen = name
	var first = _first_button(_screens.get(name) as Control)
	if first:
		first.grab_focus()


func _first_button(node: Node) -> Button:
	if node == null:
		return null
	if node is Button:
		return node as Button
	for child in node.get_children():
		var found = _first_button(child)
		if found:
			return found
	return null


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_ui_root = Control.new()
	_ui_root.name = "ScaledUIRoot"
	_ui_root.size = BASE_UI_SIZE
	add_child(_ui_root)

	_screens["main"]     = _build_main_screen()
	_screens["options"]  = _build_options_screen()
	_screens["gameplay"] = _build_gameplay_screen()
	_screens["graphics"] = _build_graphics_screen()
	_screens["controls"] = _build_controls_screen()
	_screens["codex"]    = _build_codex_screen()

	for s: Control in _screens.values():
		s.visible = false
		_ui_root.add_child(s)


func _layout_ui_root() -> void:
	if not is_instance_valid(_ui_root):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var ui_scale := minf(viewport_size.x / BASE_UI_SIZE.x, viewport_size.y / BASE_UI_SIZE.y)
	_ui_root.size = BASE_UI_SIZE
	_ui_root.scale = Vector2(ui_scale, ui_scale)
	_ui_root.position = Vector2.ZERO


func _build_main_screen() -> Control:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Transparent full-screen rect kept for simple style toggling.
	var overlay = ColorRect.new()
	overlay.color = COLOR_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	# Small "PAUSED" label above the items
	var title = Label.new()
	title.text = "PAUSED"
	title.position = Vector2(MARGIN_X, MARGIN_Y - 76)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.30))
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)

	var entries = [
		["Resume",   func(): _close()],
		["Options",  func(): _show_screen("options")],
		["Controls", func(): _show_screen("controls")],
		["Codex",    func(): _show_screen("codex")],
		["Restart",  func(): _on_restart()],
		["Quit",     func(): get_tree().quit()],
	]

	for i in range(entries.size()):
		var entry: Array = entries[i]
		var btn = _make_text_button(entry[0] as String, Vector2(MARGIN_X, MARGIN_Y + i * ITEM_STEP))
		btn.pressed.connect(entry[1] as Callable)
		root.add_child(btn)

	return root


func _build_options_screen() -> Control:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var overlay = ColorRect.new()
	overlay.color = COLOR_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	var panel = ColorRect.new()
	panel.color = COLOR_PANEL
	panel.position = Vector2(SUBMENU_X - 20, 60)
	panel.size = Vector2(560, 380)
	root.add_child(panel)

	var back = _make_back_button(Vector2(SUBMENU_X, 76))
	back.pressed.connect(func(): _show_screen("main"))
	root.add_child(back)

	var title = Label.new()
	title.text = "OPTIONS"
	title.position = Vector2(SUBMENU_X, 108)
	title.add_theme_color_override("font_color", COLOR_WHITE)
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 40)
	root.add_child(title)

	# Volume label
	var vol_label = Label.new()
	vol_label.text = "MASTER VOLUME"
	vol_label.position = Vector2(SUBMENU_X, 188)
	vol_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	vol_label.add_theme_font_override("font", MENU_FONT)
	vol_label.add_theme_font_size_override("font_size", 26)
	root.add_child(vol_label)

	# Slider
	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")))
	slider.position = Vector2(SUBMENU_X, 232)
	slider.size = Vector2(390, 40)
	slider.focus_mode = Control.FOCUS_ALL
	slider.value_changed.connect(_on_volume_changed)
	root.add_child(slider)
	_volume_slider = slider

	# Percentage label
	var pct_label = Label.new()
	pct_label.name = "VolumePct"
	pct_label.text = "%d%%" % roundi(slider.value * 100.0)
	pct_label.position = Vector2(SUBMENU_X + 400, 232)
	pct_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	pct_label.add_theme_font_override("font", MENU_FONT)
	pct_label.add_theme_font_size_override("font_size", 26)
	root.add_child(pct_label)
	slider.value_changed.connect(func(v: float): pct_label.text = "%d%%" % roundi(v * 100.0))

	var graphics_btn = _make_row_button("GRAPHICS >", Vector2(SUBMENU_X, 300), 500.0)
	graphics_btn.pressed.connect(func(): _show_screen("graphics"))
	root.add_child(graphics_btn)

	var gameplay_btn = _make_row_button("GAMEPLAY >", Vector2(SUBMENU_X, 356), 500.0)
	gameplay_btn.pressed.connect(func(): _show_screen("gameplay"))
	root.add_child(gameplay_btn)

	return root


func _build_gameplay_screen() -> Control:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var overlay = ColorRect.new()
	overlay.color = COLOR_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	var panel = ColorRect.new()
	panel.color = COLOR_PANEL
	panel.position = Vector2(SUBMENU_X - 20, 60)
	panel.size = Vector2(600, 390)
	root.add_child(panel)

	var back = _make_back_button(Vector2(SUBMENU_X, 76))
	back.pressed.connect(func(): _show_screen("options"))
	root.add_child(back)

	var title = Label.new()
	title.text = "GAMEPLAY"
	title.position = Vector2(SUBMENU_X, 108)
	title.add_theme_color_override("font_color", COLOR_WHITE)
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 40)
	root.add_child(title)

	var rudder_btn = _make_row_button("", Vector2(SUBMENU_X, 188), 560.0)
	rudder_btn.pressed.connect(_cycle_rudder_assist)
	root.add_child(rudder_btn)
	_gameplay_buttons["rudder_assist"] = rudder_btn

	var helicopter_rudder_btn = _make_row_button("", Vector2(SUBMENU_X, 252), 560.0)
	helicopter_rudder_btn.pressed.connect(_cycle_helicopter_rudder_assist)
	root.add_child(helicopter_rudder_btn)
	_gameplay_buttons["helicopter_rudder_assist"] = helicopter_rudder_btn

	_refresh_gameplay_button_labels()

	return root


func _build_graphics_screen() -> Control:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var overlay = ColorRect.new()
	overlay.color = COLOR_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	var panel = ColorRect.new()
	panel.color = COLOR_PANEL
	panel.position = Vector2(SUBMENU_X - 20, 60)
	panel.size = Vector2(600, 430)
	root.add_child(panel)

	var back = _make_back_button(Vector2(SUBMENU_X, 76))
	back.pressed.connect(func(): _show_screen("options"))
	root.add_child(back)

	var title = Label.new()
	title.text = "GRAPHICS"
	title.position = Vector2(SUBMENU_X, 108)
	title.add_theme_color_override("font_color", COLOR_WHITE)
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 40)
	root.add_child(title)

	var vsync_btn = _make_row_button("", Vector2(SUBMENU_X, 188), 560.0)
	vsync_btn.pressed.connect(_cycle_vsync)
	root.add_child(vsync_btn)
	_graphics_buttons["vsync"] = vsync_btn

	var resolution_btn = _make_row_button("", Vector2(SUBMENU_X, 252), 560.0)
	resolution_btn.pressed.connect(_cycle_resolution)
	root.add_child(resolution_btn)
	_graphics_buttons["resolution"] = resolution_btn

	var view_distance_btn = _make_row_button("", Vector2(SUBMENU_X, 316), 560.0)
	view_distance_btn.pressed.connect(_cycle_view_distance)
	root.add_child(view_distance_btn)
	_graphics_buttons["view_distance"] = view_distance_btn

	_refresh_graphics_button_labels()

	return root


func _on_volume_changed(value: float) -> void:
	var db := linear_to_db(maxf(value, 0.0001))
	var bus_idx := AudioServer.get_bus_index("Master")
	print("[Volume] slider=%.2f db=%.1f bus_idx=%d buses=%d" % [value, db, bus_idx, AudioServer.bus_count])
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, db)
	_save_settings()


func _cycle_vsync() -> void:
	_vsync_enabled = not _vsync_enabled
	_apply_vsync_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_resolution() -> void:
	_resolution_index = (_resolution_index + 1) % RESOLUTION_LABELS.size()
	_apply_resolution_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_view_distance() -> void:
	_view_distance_level = (_view_distance_level % 5) + 1
	_apply_view_distance_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_rudder_assist() -> void:
	_rudder_assist_level = (_rudder_assist_level + 1) % RUDDER_ASSIST_LABELS.size()
	_refresh_gameplay_button_labels()
	_save_settings()


func _cycle_helicopter_rudder_assist() -> void:
	_helicopter_rudder_assist_level = (_helicopter_rudder_assist_level + 1) % RUDDER_ASSIST_LABELS.size()
	_refresh_gameplay_button_labels()
	_save_settings()


func _refresh_graphics_button_labels() -> void:
	if _graphics_buttons.has("vsync"):
		var btn := _graphics_buttons["vsync"] as Button
		btn.text = "V-SYNC: %s" % ("ON" if _vsync_enabled else "OFF")
	if _graphics_buttons.has("resolution"):
		var btn := _graphics_buttons["resolution"] as Button
		btn.text = "RESOLUTION: %s" % RESOLUTION_LABELS[_resolution_index]
	if _graphics_buttons.has("view_distance"):
		var btn := _graphics_buttons["view_distance"] as Button
		btn.text = "VIEW DISTANCE: %d / 5" % _view_distance_level


func _refresh_gameplay_button_labels() -> void:
	_rudder_assist_level = clampi(_rudder_assist_level, 0, RUDDER_ASSIST_LABELS.size() - 1)
	_helicopter_rudder_assist_level = clampi(_helicopter_rudder_assist_level, 0, RUDDER_ASSIST_LABELS.size() - 1)
	if _gameplay_buttons.has("rudder_assist"):
		var btn := _gameplay_buttons["rudder_assist"] as Button
		btn.text = "AIRPLANE RUDDER ASSIST: %s" % RUDDER_ASSIST_LABELS[_rudder_assist_level]
	if _gameplay_buttons.has("helicopter_rudder_assist"):
		var btn := _gameplay_buttons["helicopter_rudder_assist"] as Button
		btn.text = "HELI RUDDER ASSIST: %s" % RUDDER_ASSIST_LABELS[_helicopter_rudder_assist_level]


func get_rudder_assist_level() -> int:
	return clampi(_rudder_assist_level, 0, RUDDER_ASSIST_LABELS.size() - 1)


func get_rudder_assist_strength() -> float:
	return float(RUDDER_ASSIST_STRENGTHS[get_rudder_assist_level()])


func get_helicopter_rudder_assist_level() -> int:
	return clampi(_helicopter_rudder_assist_level, 0, RUDDER_ASSIST_LABELS.size() - 1)


func get_helicopter_rudder_assist_strength() -> float:
	return float(RUDDER_ASSIST_STRENGTHS[get_helicopter_rudder_assist_level()])


func _apply_graphics_settings() -> void:
	_apply_vsync_setting()
	_apply_resolution_setting()
	_apply_view_distance_setting()


func _apply_vsync_setting() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _vsync_enabled else DisplayServer.VSYNC_DISABLED)


func _apply_resolution_setting() -> void:
	_resolution_index = clampi(_resolution_index, 0, RESOLUTION_LABELS.size() - 1)
	var target_size: Vector2i = RESOLUTION_SIZES[_resolution_index]
	var root_window := get_tree().root
	if root_window != null:
		root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root_window.content_scale_factor = 1.0
		root_window.content_scale_size = target_size
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(target_size)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	var viewport := get_viewport()
	if viewport != null:
		viewport.scaling_3d_scale = 1.0
	call_deferred("_print_resolution_debug", target_size)
	call_deferred("_layout_ui_root")


func _print_resolution_debug(target_size: Vector2i) -> void:
	var viewport := get_viewport()
	var visible_size := Vector2.ZERO
	var scale_3d := 0.0
	if viewport != null:
		visible_size = viewport.get_visible_rect().size
		scale_3d = viewport.scaling_3d_scale
	var root_window := get_tree().root
	var content_size := Vector2i.ZERO
	var content_mode := -1
	var content_aspect := -1
	var content_factor := 0.0
	var root_size := Vector2i.ZERO
	if root_window != null:
		content_size = root_window.content_scale_size
		content_mode = root_window.content_scale_mode
		content_aspect = root_window.content_scale_aspect
		content_factor = root_window.content_scale_factor
		root_size = root_window.size
	var screen_idx := DisplayServer.window_get_current_screen()
	print(
		"[Resolution] selected=", target_size,
		" window=", DisplayServer.window_get_size(),
		" root=", root_size,
		" screen=", DisplayServer.screen_get_size(screen_idx),
		" content=", content_size,
		" content_mode=", content_mode,
		" content_aspect=", content_aspect,
		" content_factor=", content_factor,
		" viewport=", visible_size,
		" 3d_scale=", scale_3d,
		" mode=", DisplayServer.window_get_mode()
	)


func _apply_view_distance_setting() -> void:
	_view_distance_level = clampi(_view_distance_level, 1, 5)
	var radius: int = VIEW_DISTANCE_CHUNK_RADIUS[_view_distance_level - 1]
	var camera_far: float = VIEW_DISTANCE_CAMERA_FAR[_view_distance_level - 1]
	_apply_view_distance_to_tree(radius, camera_far)


func _apply_view_distance_to_tree(radius: int, camera_far: float) -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	_apply_camera_far_recursive(root, camera_far)
	for terrain in get_tree().get_nodes_in_group("terrain"):
		_apply_view_distance_to_terrain(terrain as Node, radius)


func _apply_camera_far_recursive(node: Node, camera_far: float) -> void:
	if node == null:
		return
	if node is Camera3D:
		(node as Camera3D).far = camera_far
	for child in node.get_children():
		_apply_camera_far_recursive(child as Node, camera_far)


func _apply_view_distance_to_terrain(node: Node, radius: int) -> void:
	if not is_instance_valid(node):
		return
	if not ("load_radius_chunks" in node):
		return
	node.set("load_radius_chunks", radius)
	if node.has_method("_update_streaming"):
		node.call("_update_streaming", true)


func _on_scene_node_added(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).far = VIEW_DISTANCE_CAMERA_FAR[clampi(_view_distance_level, 1, 5) - 1]
	if node.is_in_group("terrain") or ("load_radius_chunks" in node):
		var radius: int = VIEW_DISTANCE_CHUNK_RADIUS[clampi(_view_distance_level, 1, 5) - 1]
		call_deferred("_apply_view_distance_to_terrain", node, radius)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		_apply_audio_setting(1.0)
		return
	var loaded_graphics_version := int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "settings_version", 0))
	var should_migrate_graphics := loaded_graphics_version < GRAPHICS_SETTINGS_VERSION
	var vol: float = cfg.get_value(SETTINGS_SECTION_AUDIO, "master_volume", 1.0)
	_apply_audio_setting(vol)
	_vsync_enabled = bool(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "vsync_enabled", _vsync_enabled))
	if should_migrate_graphics:
		_resolution_index = 0
	else:
		_resolution_index = clampi(
			int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "resolution_index", _resolution_index)),
			0,
			RESOLUTION_LABELS.size() - 1
		)
	_view_distance_level = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "view_distance_level", _view_distance_level)),
		1,
		5
	)
	_rudder_assist_level = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GAMEPLAY, "rudder_assist_level", _rudder_assist_level)),
		0,
		RUDDER_ASSIST_LABELS.size() - 1
	)
	_helicopter_rudder_assist_level = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GAMEPLAY, "helicopter_rudder_assist_level", _helicopter_rudder_assist_level)),
		0,
		RUDDER_ASSIST_LABELS.size() - 1
	)
	if should_migrate_graphics:
		_save_settings()


func _apply_audio_setting(value: float) -> void:
	var vol := clampf(value, 0.0, 1.0)
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(vol, 0.0001)))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var bus_idx := AudioServer.get_bus_index("Master")
	var vol := 1.0
	if bus_idx >= 0:
		vol = db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
	cfg.set_value(SETTINGS_SECTION_AUDIO, "master_volume", clampf(vol, 0.0, 1.0))
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "settings_version", GRAPHICS_SETTINGS_VERSION)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "vsync_enabled", _vsync_enabled)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "resolution_index", _resolution_index)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "view_distance_level", _view_distance_level)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "rudder_assist_level", _rudder_assist_level)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "helicopter_rudder_assist_level", _helicopter_rudder_assist_level)
	cfg.save(SETTINGS_PATH)


func _build_controls_screen() -> Control:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var overlay = ColorRect.new()
	overlay.color = COLOR_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	var vp = DisplayServer.screen_get_size()
	var panel_w = mini(600, vp.x - int(SUBMENU_X) - 80)
	var panel_h = vp.y - 140

	var panel = ColorRect.new()
	panel.color = COLOR_PANEL
	panel.position = Vector2(SUBMENU_X - 20, 60)
	panel.size = Vector2(panel_w, panel_h)
	root.add_child(panel)

	var back = _make_back_button(Vector2(SUBMENU_X, 76))
	back.pressed.connect(func(): _show_screen("main"))
	root.add_child(back)

	var title = Label.new()
	title.text = "CONTROLS"
	title.position = Vector2(SUBMENU_X, 108)
	title.add_theme_color_override("font_color", COLOR_WHITE)
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 40)
	root.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(SUBMENU_X, 188)
	scroll.size = Vector2(panel_w - 40, panel_h - 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", COLOR_BODY)
	rt.add_theme_font_override("normal_font", MENU_FONT)
	rt.add_theme_font_override("bold_font", MENU_FONT)
	rt.add_theme_font_size_override("normal_font_size", 20)
	rt.add_theme_font_size_override("bold_font_size", 20)
	rt.text = _controls_bbcode()
	scroll.add_child(rt)

	return root


func _build_codex_screen() -> Control:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var overlay = ColorRect.new()
	overlay.color = COLOR_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	var panel = ColorRect.new()
	panel.color = COLOR_PANEL
	panel.position = Vector2(SUBMENU_X - 20, 60)
	panel.size = Vector2(560, 320)
	root.add_child(panel)

	var back = _make_back_button(Vector2(SUBMENU_X, 76))
	back.pressed.connect(func(): _show_screen("main"))
	root.add_child(back)

	var title = Label.new()
	title.text = "CODEX"
	title.position = Vector2(SUBMENU_X, 108)
	title.add_theme_color_override("font_color", COLOR_WHITE)
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 40)
	root.add_child(title)

	var body = Label.new()
	body.text = "COMING SOON.\n\nVEHICLE AND WEAPON REFERENCE ENTRIES\nWILL APPEAR HERE."
	body.position = Vector2(SUBMENU_X, 196)
	body.size = Vector2(520, 180)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	body.add_theme_font_override("font", MENU_FONT)
	body.add_theme_font_size_override("font_size", 22)
	root.add_child(body)

	return root


# ---------------------------------------------------------------------------
# Widget helpers
# ---------------------------------------------------------------------------

func _make_text_button(label_text: String, pos: Vector2) -> Button:
	var btn = Button.new()
	btn.text = label_text.to_upper()
	btn.position = pos
	btn.custom_minimum_size = Vector2(680, FONT_SELECTED + 26)
	btn.focus_mode = Control.FOCUS_ALL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Fully transparent styleboxes — no backgrounds at all
	var empty = StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, empty)

	btn.add_theme_color_override("font_color",         COLOR_DIM)
	btn.add_theme_color_override("font_hover_color",   COLOR_WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.6))
	btn.add_theme_color_override("font_focus_color",   COLOR_WHITE)
	btn.add_theme_font_override("font", MENU_FONT)
	btn.add_theme_font_size_override("font_size", FONT_NORMAL)

	btn.focus_entered.connect(func(): btn.add_theme_font_size_override("font_size", FONT_SELECTED))
	btn.focus_exited.connect(func():  btn.add_theme_font_size_override("font_size", FONT_NORMAL))

	return btn


func _make_row_button(label_text: String, pos: Vector2, width: float) -> Button:
	var btn = Button.new()
	btn.text = label_text.to_upper()
	btn.position = pos
	btn.size = Vector2(width, 54.0)
	btn.custom_minimum_size = Vector2(width, 54.0)
	btn.focus_mode = Control.FOCUS_ALL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var empty = StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, empty)

	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.58))
	btn.add_theme_color_override("font_hover_color", COLOR_WHITE)
	btn.add_theme_color_override("font_focus_color", COLOR_WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.68))
	btn.add_theme_font_override("font", MENU_FONT)
	btn.add_theme_font_size_override("font_size", 28)

	btn.focus_entered.connect(func(): btn.add_theme_font_size_override("font_size", 32))
	btn.focus_exited.connect(func(): btn.add_theme_font_size_override("font_size", 28))

	return btn


func _make_back_button(pos: Vector2) -> Button:
	var btn = Button.new()
	btn.text = "< BACK"
	btn.position = pos
	btn.custom_minimum_size = Vector2(240, 44)
	btn.focus_mode = Control.FOCUS_ALL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var empty = StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, empty)
	btn.add_theme_color_override("font_color",         Color(1, 1, 1, 0.35))
	btn.add_theme_color_override("font_hover_color",   COLOR_WHITE)
	btn.add_theme_color_override("font_focus_color",   COLOR_WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.6))
	btn.add_theme_font_override("font", MENU_FONT)
	btn.add_theme_font_size_override("font_size", 24)
	return btn


# ---------------------------------------------------------------------------
# Controls content
# ---------------------------------------------------------------------------

func _controls_bbcode() -> String:
	var w = COLOR_WHITE.to_html(false)
	var d = Color(1, 1, 1, 0.50).to_html(false)
	return """
[color=#{w}][b]FLIGHT[/b][/color]
[color=#{d}]LEFT STICK[/color]       PITCH / ROLL
[color=#{d}]LT / RT[/color]          YAW LEFT / RIGHT
[color=#{d}]LB[/color]               THROTTLE UP
[color=#{d}]RB[/color]               THROTTLE DOWN

[color=#{w}][b]AIRCRAFT SYSTEMS[/b][/color]
[color=#{d}]B / CIRCLE[/color]       LANDING GEAR
[color=#{d}]D-PAD UP[/color]         START ENGINE
[color=#{d}]D-PAD DOWN[/color]       STOP ENGINE
[color=#{d}]D-PAD LEFT/RIGHT[/color] FLAPS DOWN / UP

[color=#{w}][b]COMBAT[/b][/color]
[color=#{d}]A / X[/color]            FIRE WEAPON
[color=#{d}]X / SQUARE[/color]       CYCLE WEAPON
[color=#{d}]D-PAD LEFT/RIGHT[/color] NEXT / PREVIOUS TARGET
[color=#{d}]L-STICK CLICK[/color]    LOCK TARGET AT HUD CENTER

[color=#{w}][b]CAMERA[/b][/color]
[color=#{d}]Y / TRIANGLE[/color]     CYCLE CAMERA VIEW
[color=#{d}]RIGHT STICK[/color]      LOOK / AIM
[color=#{d}]R-STICK CLICK[/color]    ZOOM (COCKPIT / BRIDGE)

[color=#{w}][b]SPECTATOR[/b][/color]
[color=#{d}]START / OPTIONS[/color]  TOGGLE PILOT / AI CONTROL
[color=#{d}]LB / RB[/color]          CYCLE SPECTATE TARGET
[color=#{d}]SPACE[/color]            ENTER FREE CAMERA

[color=#{w}][b]CARRIER OPS[/b][/color]
[color=#{d}]R / 1[/color]            RETRIEVE AIRCRAFT FROM HANGAR
[color=#{d}]9[/color]                RETRIEVE RESCUE HELICOPTER
[color=#{d}]S[/color]                STORE AIRCRAFT IN HANGAR
[color=#{d}]L[/color]                ORDER NEAREST AIRCRAFT TO LAND
[color=#{d}]V[/color]                DEPLOY NEXT GROUND PLATOON
[color=#{d}]B[/color]                RETRIEVE LAST PLATOON
[color=#{d}]Z[/color]                TOGGLE VEHICLE RAMP
[color=#{d}]M[/color]                CARRIER OPERATIONS CONSOLE
[color=#{d}]P / SELECT[/color]       PAUSE / THIS MENU
""".format({"w": w, "d": d})


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_restart() -> void:
	_close()
	var loading_screen: Node = get_node_or_null("/root/LoadingScreen")
	if loading_screen != null and loading_screen.has_method("begin_scenario_load"):
		loading_screen.call("begin_scenario_load")
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Pause navigation input (keyboard + gamepad)
# ---------------------------------------------------------------------------

func _handle_pause_navigation_input(event: InputEvent) -> bool:
	if _current_screen == "":
		return false

	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner: Control = viewport.gui_get_focus_owner()
	if focus_owner == null:
		var first = _first_button(_screens.get(_current_screen) as Control)
		if first:
			first.grab_focus()
			focus_owner = first

	if _is_menu_up_event(event):
		_move_focus(focus_owner, Side.SIDE_TOP)
		return true
	if _is_menu_down_event(event):
		_move_focus(focus_owner, Side.SIDE_BOTTOM)
		return true
	if _is_menu_accept_event(event):
		if focus_owner is Button:
			(focus_owner as Button).pressed.emit()
			return true
		return false
	if _is_menu_back_event(event):
		if _current_screen == "main":
			_close()
		else:
			_show_screen("main")
		return true

	return false

func _move_focus(focus_owner: Control, side: int) -> void:
	if focus_owner == null:
		return
	var next_focus: Control = focus_owner.find_valid_focus_neighbor(side)
	if next_focus:
		next_focus.grab_focus()
		return

	var buttons: Array[Button] = _buttons_in_current_screen()
	if buttons.is_empty():
		return
	var idx: int = buttons.find(focus_owner as Button)
	if idx < 0:
		buttons[0].grab_focus()
		return
	var dir: int = -1 if side == Side.SIDE_TOP else 1
	var next_idx: int = (idx + dir + buttons.size()) % buttons.size()
	buttons[next_idx].grab_focus()

func _buttons_in_current_screen() -> Array[Button]:
	var out: Array[Button] = []
	var screen: Control = _screens.get(_current_screen) as Control
	if screen == null:
		return out
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back() as Node
		if n is Button and (n as Button).visible:
			out.append(n as Button)
		for c in n.get_children():
			if c is Node:
				stack.append(c as Node)
	out.reverse()
	return out

func _is_menu_up_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).physical_keycode
		return key == KEY_UP or key == KEY_W
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_DPAD_UP
	return false

func _is_menu_down_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_down", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).physical_keycode
		return key == KEY_DOWN or key == KEY_S
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_DPAD_DOWN
	return false

func _is_menu_accept_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).physical_keycode
		return key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_A
	return false

func _is_menu_back_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).physical_keycode
		return key == KEY_ESCAPE or key == KEY_BACKSPACE
	if event is InputEventJoypadButton and event.pressed:
		var b: int = (event as InputEventJoypadButton).button_index
		return b == PAD_BUTTON_B or b == PAD_BUTTON_BACK
	return false
