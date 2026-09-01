extends CanvasLayer
## Pause menu autoload.
## Opened by the pause_game action (Select/Back on gamepad, P on keyboard).
## Opening pauses the scene tree; closing unpauses it.
## Sub-screens: Settings, audio, graphics, gameplay, and controls reference.

const MenuTypography = preload("res://UI/MenuTypography.gd")
const MenuTheme = preload("res://UI/MenuTheme.gd")

const FONT_NORMAL   := MenuTypography.MENU_ITEM_SIZE
const MARGIN_X      := 20.0
const MARGIN_Y      := 235.0
const ITEM_STEP     := 64.0
const BASE_UI_SIZE  := MenuTypography.CANVAS_SIZE
const SUBMENU_X     := 32.0
const OPERATOR_RAIL_WIDTH := MenuTheme.RAIL_WIDTH

const PAD_BUTTON_A         := 0
const PAD_BUTTON_B         := 1
const PAD_BUTTON_BACK      := 4
const PAD_BUTTON_DPAD_UP   := 11
const PAD_BUTTON_DPAD_DOWN := 12

const COLOR_WHITE   := MenuTheme.TEXT
const COLOR_OVERLAY := Color(0.008, 0.01, 0.012, 0.72)

# Controls reference panel colour.
const COLOR_BODY    := MenuTheme.TEXT

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION_AUDIO := "audio"
const SETTINGS_SECTION_GRAPHICS := "graphics"
const SETTINGS_SECTION_GAMEPLAY := "gameplay"
const GRAPHICS_SETTINGS_VERSION := 6
const GAMEPLAY_SETTINGS_VERSION := 1
const DEFAULT_MASTER_VOLUME := 1.0
const DEFAULT_RADIO_VOLUME := 1.0
const DEFAULT_RADIO_CAPTIONS_ENABLED := true
const DEFAULT_RADIO_CAPTION_DURATION_INDEX := 1
const DEFAULT_SHOW_FPS_ENABLED := false
const DEFAULT_STICK_DEADZONE_INDEX := 0
const DEFAULT_LOOK_SENSITIVITY_INDEX := 2
const DEFAULT_INVERT_LOOK_Y := false
const DEFAULT_CAMERA_MOTION_INDEX := 2
const DEFAULT_CAMERA_FOV_INDEX := 2
const DEFAULT_CONTROLLER_MENU_CURSOR_ENABLED := false
const DEFAULT_FLIGHT_MODEL_INDEX := 1
const MENU_CURSOR_DEADZONE := 0.18
const MENU_CURSOR_SPEED_PX_S := 1050.0
const MENU_CURSOR_TRIGGER_PRESS_THRESHOLD := 0.55
const MENU_CURSOR_TRIGGER_RELEASE_THRESHOLD := 0.35
const MENU_CURSOR_SCENES: Array[String] = [
	"res://UI/MainMenu.tscn",
]
const DEFAULT_VIEW_DISTANCE_LEVEL := 3
const DEFAULT_ENEMY_VISIBILITY_INDEX := 0
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
const FLIGHT_MODEL_LABELS := [
	"SIMPLIFIED",
	"ADVANCED",
]
const RESOLUTION_LABELS := [
	"1920 X 1080",
	"1600 X 900",
	"1280 X 720",
	"2560 X 1440",
	"3840 X 2160",
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
const ENEMY_VISIBILITY_LABELS := ["STANDARD", "ENHANCED"]
const ENEMY_VISIBILITY_START_DISTANCE_M := [1800.0, 900.0]
const ENEMY_VISIBILITY_FULL_DISTANCE_M := [5200.0, 3500.0]
const ENEMY_VISIBILITY_MAX_STRENGTH := [0.18, 0.26]
const DISPLAY_MODE_LABELS := ["WINDOWED", "BORDERLESS", "EXCLUSIVE FULLSCREEN"]
const FRAME_LIMIT_LABELS := ["UNLIMITED", "30 FPS", "60 FPS", "120 FPS", "144 FPS", "240 FPS"]
const FRAME_LIMIT_VALUES := [0, 30, 60, 120, 144, 240]
const ANTI_ALIASING_LABELS := ["OFF", "SMAA", "MSAA 2X", "MSAA 4X", "TAA"]
const RENDER_SCALE_LABELS := ["50%", "67%", "75%", "85%", "100%"]
const RENDER_SCALE_VALUES := [0.50, 0.67, 0.75, 0.85, 1.0]
const UPSCALER_LABELS := ["BILINEAR", "FSR 1"]
const RADIO_CAPTION_DURATION_LABELS := ["5 S", "9 S", "15 S", "25 S"]
const RADIO_CAPTION_DURATION_VALUES := [5.0, 9.0, 15.0, 25.0]
const STICK_DEADZONE_LABELS := ["5%", "10%", "15%", "20%", "25%"]
const STICK_DEADZONE_VALUES := [0.05, 0.10, 0.15, 0.20, 0.25]
const STICK_DEADZONE_ACTIONS := [
	&"pitch_up", &"pitch_down", &"roll_left", &"roll_right",
	&"look_left", &"look_right", &"look_up", &"look_down",
]
const LOOK_SENSITIVITY_LABELS := ["50%", "75%", "100%", "125%", "150%"]
const LOOK_SENSITIVITY_VALUES := [0.50, 0.75, 1.0, 1.25, 1.50]
const CAMERA_MOTION_LABELS := ["OFF", "REDUCED", "FULL"]
const CAMERA_MOTION_VALUES := [0.0, 0.45, 1.0]
const CAMERA_FOV_LABELS := ["60", "70", "75", "85"]
const CAMERA_FOV_VALUES := [60.0, 70.0, 75.0, 85.0]

var _screens: Dictionary = {}
var _current_screen: String = ""
var _ui_root: Control = null
var _audio_sliders: Dictionary = {}
var _audio_value_labels: Dictionary = {}
var _audio_buttons: Dictionary = {}
var _graphics_buttons: Dictionary = {}
var _gameplay_buttons: Dictionary = {}
var _master_volume: float = DEFAULT_MASTER_VOLUME
var _radio_volume: float = DEFAULT_RADIO_VOLUME
var _radio_captions_enabled: bool = DEFAULT_RADIO_CAPTIONS_ENABLED
var _radio_caption_duration_index: int = DEFAULT_RADIO_CAPTION_DURATION_INDEX
var _vsync_enabled: bool = false
var _resolution_index: int = 0
var _display_mode_index: int = 2
var _frame_limit_index: int = 0
var _anti_aliasing_index: int = 2
var _render_scale_index: int = 4
var _upscaler_index: int = 1
var _view_distance_level: int = DEFAULT_VIEW_DISTANCE_LEVEL
var _enemy_visibility_index: int = DEFAULT_ENEMY_VISIBILITY_INDEX
var _show_fps_enabled: bool = DEFAULT_SHOW_FPS_ENABLED
var _rudder_assist_level: int = 0
var _helicopter_rudder_assist_level: int = 1
var _stick_deadzone_index: int = DEFAULT_STICK_DEADZONE_INDEX
var _look_sensitivity_index: int = DEFAULT_LOOK_SENSITIVITY_INDEX
var _invert_look_y: bool = DEFAULT_INVERT_LOOK_Y
var _camera_motion_index: int = DEFAULT_CAMERA_MOTION_INDEX
var _camera_fov_index: int = DEFAULT_CAMERA_FOV_INDEX
var _controller_menu_cursor_enabled: bool = DEFAULT_CONTROLLER_MENU_CURSOR_ENABLED
var _flight_model_index: int = DEFAULT_FLIGHT_MODEL_INDEX
var _menu_cursor_device_id := -1
var _menu_cursor_a_pressed := false
var _menu_cursor_trigger_pressed := false
var _menu_cursor_context_was_active := false
var _menu_cursor_previous_mouse_mode := -1
var _opened_from_main_menu := false
var _save_button: Button = null
var _save_status_label: Label = null
var _save_feedback_until_ms: int = 0
var _photo_mode_active: bool = false
var _photo_mode_canvas_visibility: Dictionary = {}


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
	call_deferred("_apply_all_settings")


func _process(delta: float) -> void:
	if _photo_mode_active:
		_suppress_photo_mode_ui()
		return
	if visible and _current_screen == "main":
		_refresh_save_controls()
	var cursor_active := is_controller_menu_cursor_active()
	if not cursor_active:
		_deactivate_controller_menu_cursor()
		return
	if not _menu_cursor_context_was_active:
		_menu_cursor_previous_mouse_mode = Input.mouse_mode
		_menu_cursor_context_was_active = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var device_id := _active_menu_cursor_device_id()
	if device_id < 0:
		return
	var stick := Vector2(
		Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
	)
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var cursor_motion := controller_menu_cursor_motion(stick, delta, viewport_size)
	if cursor_motion.is_zero_approx():
		return
	var next_position := viewport.get_mouse_position() + cursor_motion
	next_position.x = clampf(next_position.x, 0.0, maxf(viewport_size.x - 1.0, 0.0))
	next_position.y = clampf(next_position.y, 0.0, maxf(viewport_size.y - 1.0, 0.0))
	viewport.warp_mouse(next_position)


func _input(event: InputEvent) -> void:
	_remember_menu_cursor_device(event)
	var viewport := get_viewport()
	if viewport == null:
		return
	if _photo_mode_active:
		if _is_menu_accept_event(event):
			_capture_photo()
			viewport.set_input_as_handled()
			return
		if _is_menu_back_event(event) or event.is_action_pressed("pause_game", false):
			exit_photo_mode()
			viewport.set_input_as_handled()
		return
	if event.is_action_pressed("pause_game", false):
		if not visible:
			_open()
		else:
			_close()
		viewport.set_input_as_handled()
		return

	if controller_menu_cursor_claims_event(event):
		_handle_controller_menu_cursor_input(event)
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
	_opened_from_main_menu = false
	get_tree().paused = true
	visible = true
	_show_screen("main")
	_refresh_save_controls()


func open_settings_from_main_menu() -> void:
	_opened_from_main_menu = true
	get_tree().paused = true
	visible = true
	_show_screen("options")


func get_controller_menu_cursor_enabled() -> bool:
	return _controller_menu_cursor_enabled


func is_controller_menu_cursor_active() -> bool:
	return _controller_menu_cursor_enabled and _is_menu_cursor_context_active()


func controller_menu_cursor_claims_event(event: InputEvent) -> bool:
	if not is_controller_menu_cursor_active():
		return false
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_A
	if event is InputEventJoypadMotion:
		var axis := (event as InputEventJoypadMotion).axis
		return axis == JOY_AXIS_LEFT_X or axis == JOY_AXIS_LEFT_Y or axis == JOY_AXIS_TRIGGER_RIGHT
	return false


static func controller_menu_cursor_motion(stick: Vector2, delta: float, viewport_size: Vector2) -> Vector2:
	var stick_length := minf(stick.length(), 1.0)
	if stick_length <= MENU_CURSOR_DEADZONE or delta <= 0.0:
		return Vector2.ZERO
	var strength := (stick_length - MENU_CURSOR_DEADZONE) / (1.0 - MENU_CURSOR_DEADZONE)
	var resolution_scale := maxf(viewport_size.y / BASE_UI_SIZE.y, 0.5)
	return stick.normalized() * strength * MENU_CURSOR_SPEED_PX_S * resolution_scale * delta


func _is_menu_cursor_context_active() -> bool:
	if visible:
		return true
	var current_scene := get_tree().current_scene
	if current_scene != null and MENU_CURSOR_SCENES.has(current_scene.scene_file_path):
		return true
	var carrier_console := get_node_or_null("/root/CarrierConsole")
	return carrier_console != null \
		and carrier_console.has_method("is_open") \
		and bool(carrier_console.call("is_open"))


func _remember_menu_cursor_device(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_menu_cursor_device_id = event.device


func _active_menu_cursor_device_id() -> int:
	var connected_devices := Input.get_connected_joypads()
	if connected_devices.has(_menu_cursor_device_id):
		return _menu_cursor_device_id
	if not connected_devices.is_empty():
		_menu_cursor_device_id = int(connected_devices[0])
		return _menu_cursor_device_id
	return -1


func _handle_controller_menu_cursor_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton
		_set_controller_menu_click_source(&"a", button_event.pressed)
		return
	var motion_event := event as InputEventJoypadMotion
	if motion_event.axis != JOY_AXIS_TRIGGER_RIGHT:
		return
	var trigger_pressed := _menu_cursor_trigger_pressed
	if trigger_pressed and motion_event.axis_value <= MENU_CURSOR_TRIGGER_RELEASE_THRESHOLD:
		trigger_pressed = false
	elif not trigger_pressed and motion_event.axis_value >= MENU_CURSOR_TRIGGER_PRESS_THRESHOLD:
		trigger_pressed = true
	_set_controller_menu_click_source(&"trigger", trigger_pressed)


func _set_controller_menu_click_source(source: StringName, pressed: bool) -> void:
	var was_pressed := _menu_cursor_a_pressed or _menu_cursor_trigger_pressed
	if source == &"a":
		_menu_cursor_a_pressed = pressed
	else:
		_menu_cursor_trigger_pressed = pressed
	var is_pressed := _menu_cursor_a_pressed or _menu_cursor_trigger_pressed
	if was_pressed != is_pressed:
		_emit_controller_menu_mouse_button(is_pressed)


func _emit_controller_menu_mouse_button(pressed: bool) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	mouse_event.pressed = pressed
	mouse_event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse_event.position = viewport.get_mouse_position()
	mouse_event.global_position = mouse_event.position
	viewport.push_input(mouse_event, true)


func _release_controller_menu_click() -> void:
	var was_pressed := _menu_cursor_a_pressed or _menu_cursor_trigger_pressed
	_menu_cursor_a_pressed = false
	_menu_cursor_trigger_pressed = false
	if was_pressed:
		_emit_controller_menu_mouse_button(false)


func _deactivate_controller_menu_cursor() -> void:
	_release_controller_menu_click()
	if not _menu_cursor_context_was_active:
		return
	_menu_cursor_context_was_active = false
	if _menu_cursor_previous_mouse_mode >= 0:
		Input.mouse_mode = _menu_cursor_previous_mouse_mode
	_menu_cursor_previous_mouse_mode = -1


func _close() -> void:
	if _photo_mode_active:
		exit_photo_mode()
	get_tree().paused = false
	visible = false
	_current_screen = ""
	_opened_from_main_menu = false


# ---------------------------------------------------------------------------
# Screen management
# ---------------------------------------------------------------------------

func _show_screen(name: String) -> void:
	for key: String in _screens:
		(_screens[key] as Control).visible = (key == name)
	_current_screen = name
	if name == "main":
		_refresh_save_controls()
	var first = _first_button(_screens.get(name) as Control)
	if first:
		first.grab_focus()


func _first_button(node: Node) -> Button:
	if node == null:
		return null
	if node is Button:
		var button := node as Button
		if not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			return button
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
	_screens["audio"]    = _build_audio_screen()
	_screens["gameplay"] = _build_gameplay_screen()
	_screens["graphics"] = _build_graphics_screen()
	_screens["controls"] = _build_controls_screen()

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


func _build_screen_chrome(root: Control, title_text: String, system_text: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = COLOR_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	var rail := Panel.new()
	rail.position = Vector2.ZERO
	rail.size = Vector2(OPERATOR_RAIL_WIDTH, BASE_UI_SIZE.y)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rail_style := MenuTheme.make_panel_style(MenuTheme.SURFACE, MenuTheme.OUTLINE, 0)
	rail_style.border_width_right = 1
	rail.add_theme_stylebox_override("panel", rail_style)
	root.add_child(rail)

	var title := _make_console_label(
		title_text,
		Vector2(OPERATOR_RAIL_WIDTH + 76.0, 34.0),
		MenuTypography.BRAND_TITLE_SIZE,
		MenuTheme.PRIMARY,
		MenuTypography.FONT
	)
	title.size = Vector2(1050.0, 102.0)
	title.scale = Vector2(1.10, 1.0)
	title.add_theme_color_override("font_shadow_color", Color(MenuTheme.PRIMARY.r, MenuTheme.PRIMARY.g, MenuTheme.PRIMARY.b, 0.22))
	title.add_theme_constant_override("shadow_outline_size", 8)
	root.add_child(title)

	var system_id := _make_console_label(
		system_text,
		Vector2(OPERATOR_RAIL_WIDTH + 80.0, 140.0),
		MenuTypography.BRAND_META_SIZE,
		MenuTheme.TEXT_MUTED,
		MenuTypography.TECH_FONT
	)
	root.add_child(system_id)


func _build_main_screen() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_screen_chrome(root, "PAUSED", "SYS_ID: LC-992-ALPHA // SESSION SUSPENDED")

	var entries = [
		["RESUME", func(): _close()],
		["PHOTO MODE", func(): enter_photo_mode()],
		["SAVE CAMPAIGN", func(): _on_save_campaign()],
		["SETTINGS", func(): _show_screen("options")],
		["CONTROLS", func(): _show_screen("controls")],
		["RESTART SCENARIO", func(): _on_restart()],
		["RETURN TO MAIN MENU", func(): _return_to_main_menu()],
		["QUIT TO DESKTOP", func(): get_tree().quit()],
	]
	for i in range(entries.size()):
		var entry: Array = entries[i]
		var button := _make_text_button(entry[0] as String, Vector2(MARGIN_X, MARGIN_Y + i * ITEM_STEP))
		button.pressed.connect(entry[1] as Callable)
		root.add_child(button)
		if str(entry[0]) == "SAVE CAMPAIGN":
			_save_button = button
	_save_status_label = _make_console_label(
		"",
		Vector2(OPERATOR_RAIL_WIDTH + 80.0, 216.0),
		MenuTypography.FIELD_VALUE_SIZE,
		MenuTheme.TEXT_MUTED,
		MenuTypography.TECH_FONT
	)
	_save_status_label.size = Vector2(1050.0, 90.0)
	_save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_save_status_label)
	return root


func enter_photo_mode() -> void:
	if _photo_mode_active:
		return
	var flight_director := get_node_or_null("/root/FlightDirector")
	if flight_director == null or not flight_director.has_method("begin_photo_mode_camera"):
		push_error("PauseMenu: FlightDirector photo camera is unavailable")
		return
	if not bool(flight_director.call("begin_photo_mode_camera")):
		push_error("PauseMenu: Could not activate the free camera for photo mode")
		return

	_photo_mode_active = true
	_photo_mode_canvas_visibility.clear()
	_suppress_photo_mode_ui()


func exit_photo_mode() -> void:
	if not _photo_mode_active:
		return
	_photo_mode_active = false

	var flight_director := get_node_or_null("/root/FlightDirector")
	if flight_director != null and flight_director.has_method("end_photo_mode_camera"):
		flight_director.call("end_photo_mode_camera")

	_restore_photo_mode_ui()
	visible = true
	_show_screen("main")


func is_photo_mode_active() -> bool:
	return _photo_mode_active


func _capture_photo() -> void:
	var screenshot_capture := get_node_or_null("/root/ScreenshotCapture")
	if screenshot_capture == null or not screenshot_capture.has_method("take_screenshot"):
		push_error("PauseMenu: ScreenshotCapture service is unavailable")
		return
	screenshot_capture.call("take_screenshot")


func _suppress_photo_mode_ui() -> void:
	var canvas_layers: Array[CanvasLayer] = []
	_collect_main_viewport_canvas_layers(get_tree().root, canvas_layers)
	for canvas_layer in canvas_layers:
		if not _photo_mode_canvas_visibility.has(canvas_layer):
			_photo_mode_canvas_visibility[canvas_layer] = canvas_layer.visible
		canvas_layer.visible = false


func _collect_main_viewport_canvas_layers(node: Node, result: Array[CanvasLayer]) -> void:
	if node is CanvasLayer:
		var canvas_layer := node as CanvasLayer
		if canvas_layer.get_viewport() == get_viewport():
			result.append(canvas_layer)
	for child in node.get_children():
		_collect_main_viewport_canvas_layers(child, result)


func _restore_photo_mode_ui() -> void:
	for canvas_layer_variant: Variant in _photo_mode_canvas_visibility:
		if not is_instance_valid(canvas_layer_variant) or not (canvas_layer_variant is CanvasLayer):
			continue
		var canvas_layer := canvas_layer_variant as CanvasLayer
		canvas_layer.visible = bool(_photo_mode_canvas_visibility[canvas_layer_variant])
	_photo_mode_canvas_visibility.clear()


func _refresh_save_controls() -> void:
	if not is_instance_valid(_save_button) or not is_instance_valid(_save_status_label):
		return
	var can_save := SaveGameManager.can_save_campaign()
	_save_button.disabled = not can_save
	var now_ms := Time.get_ticks_msec()
	if now_ms >= _save_feedback_until_ms:
		_save_status_label.text = SaveGameManager.get_save_status_message().to_upper()
	_save_status_label.add_theme_color_override(
		"font_color",
		MenuTheme.PRIMARY if can_save else MenuTheme.TEXT_MUTED
	)
	_save_button.tooltip_text = "Write the latest strategic checkpoint" \
		if can_save else SaveGameManager.get_save_status_message()


func _on_save_campaign() -> void:
	var result: Dictionary = SaveGameManager.request_manual_save()
	var succeeded := bool(result.get("ok", false))
	if is_instance_valid(_save_status_label):
		_save_status_label.text = str(result.get("message", "Campaign save failed")).to_upper()
		_save_status_label.add_theme_color_override(
			"font_color",
			MenuTheme.PRIMARY if succeeded else Color(1.0, 0.45, 0.30, 1.0)
		)
	_save_feedback_until_ms = Time.get_ticks_msec() + 2500


func _build_options_screen() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_screen_chrome(root, "SETTINGS", "SYS_ID: LC-992-ALPHA // SYSTEM CONFIGURATION")

	var back := _make_back_button(Vector2(SUBMENU_X, 190.0))
	back.pressed.connect(_back_from_options)
	root.add_child(back)

	var audio_btn := _make_row_button("AUDIO >", Vector2(SUBMENU_X, 264.0), OPERATOR_RAIL_WIDTH - 64.0)
	audio_btn.pressed.connect(func(): _show_screen("audio"))
	root.add_child(audio_btn)

	var graphics_btn := _make_row_button("GRAPHICS >", Vector2(SUBMENU_X, 328.0), OPERATOR_RAIL_WIDTH - 64.0)
	graphics_btn.pressed.connect(func(): _show_screen("graphics"))
	root.add_child(graphics_btn)

	var gameplay_btn := _make_row_button("GAMEPLAY >", Vector2(SUBMENU_X, 392.0), OPERATOR_RAIL_WIDTH - 64.0)
	gameplay_btn.pressed.connect(func(): _show_screen("gameplay"))
	root.add_child(gameplay_btn)

	var reset_btn := _make_row_button("RESET ALL DEFAULTS", Vector2(SUBMENU_X, 520.0), OPERATOR_RAIL_WIDTH - 64.0)
	reset_btn.pressed.connect(_reset_all_defaults)
	root.add_child(reset_btn)
	return root


func _build_audio_screen() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_screen_chrome(root, "AUDIO", "SYS_ID: LC-992-ALPHA // MIX AND RADIO")

	var back := _make_back_button(Vector2(SUBMENU_X, 190.0))
	back.pressed.connect(func(): _show_screen("options"))
	root.add_child(back)

	_build_audio_slider(root, "master", "MASTER VOLUME", 264.0, _master_volume)
	_build_audio_slider(root, "radio", "RADIO VOLUME", 366.0, _radio_volume)

	var captions_btn := _make_row_button("", Vector2(SUBMENU_X, 468.0), OPERATOR_RAIL_WIDTH - 64.0)
	captions_btn.pressed.connect(_cycle_radio_captions)
	root.add_child(captions_btn)
	_audio_buttons["captions"] = captions_btn

	var duration_btn := _make_row_button("", Vector2(SUBMENU_X, 532.0), OPERATOR_RAIL_WIDTH - 64.0)
	duration_btn.pressed.connect(_cycle_radio_caption_duration)
	root.add_child(duration_btn)
	_audio_buttons["caption_duration"] = duration_btn
	_refresh_audio_controls()
	return root


func _build_audio_slider(root: Control, key: String, label_text: String, row_y: float, value: float) -> void:
	var label := _make_console_label(label_text, Vector2(SUBMENU_X + 18.0, row_y), MenuTypography.FIELD_LABEL_SIZE, MenuTheme.TEXT_MUTED, MenuTypography.TECH_FONT)
	root.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.position = Vector2(SUBMENU_X + 18.0, row_y + 34.0)
	slider.size = Vector2(320.0, 40.0)
	slider.focus_mode = Control.FOCUS_ALL
	slider.value_changed.connect(_on_audio_volume_changed.bind(key))
	MenuTheme.apply_slider(slider)
	root.add_child(slider)
	_audio_sliders[key] = slider
	var pct_label := _make_console_label("%d%%" % roundi(value * 100.0), Vector2(SUBMENU_X + 356.0, row_y + 40.0), MenuTypography.FIELD_VALUE_SIZE, MenuTheme.TEXT, MenuTypography.TECH_FONT)
	root.add_child(pct_label)
	_audio_value_labels[key] = pct_label


func _build_gameplay_screen() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_screen_chrome(root, "GAMEPLAY", "SYS_ID: LC-992-ALPHA // CONTROL ASSISTANCE")

	var back := _make_back_button(Vector2(SUBMENU_X, 190.0))
	back.pressed.connect(func(): _show_screen("options"))
	root.add_child(back)

	var row_width := OPERATOR_RAIL_WIDTH - 64.0
	var row_y := 252.0
	var flight_model_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	flight_model_btn.pressed.connect(_cycle_flight_model)
	root.add_child(flight_model_btn)
	_gameplay_buttons["flight_model"] = flight_model_btn

	row_y += 58.0
	var rudder_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	rudder_btn.pressed.connect(_cycle_rudder_assist)
	root.add_child(rudder_btn)
	_gameplay_buttons["rudder_assist"] = rudder_btn

	row_y += 58.0
	var helicopter_rudder_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	helicopter_rudder_btn.pressed.connect(_cycle_helicopter_rudder_assist)
	root.add_child(helicopter_rudder_btn)
	_gameplay_buttons["helicopter_rudder_assist"] = helicopter_rudder_btn

	row_y += 58.0
	var deadzone_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	deadzone_btn.pressed.connect(_cycle_stick_deadzone)
	root.add_child(deadzone_btn)
	_gameplay_buttons["stick_deadzone"] = deadzone_btn

	row_y += 58.0
	var menu_cursor_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	menu_cursor_btn.pressed.connect(_cycle_controller_menu_cursor)
	root.add_child(menu_cursor_btn)
	_gameplay_buttons["controller_menu_cursor"] = menu_cursor_btn

	row_y += 58.0
	var sensitivity_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	sensitivity_btn.pressed.connect(_cycle_look_sensitivity)
	root.add_child(sensitivity_btn)
	_gameplay_buttons["look_sensitivity"] = sensitivity_btn

	row_y += 58.0
	var invert_y_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	invert_y_btn.pressed.connect(_cycle_invert_look_y)
	root.add_child(invert_y_btn)
	_gameplay_buttons["invert_look_y"] = invert_y_btn

	row_y += 58.0
	var camera_motion_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	camera_motion_btn.pressed.connect(_cycle_camera_motion)
	root.add_child(camera_motion_btn)
	_gameplay_buttons["camera_motion"] = camera_motion_btn

	row_y += 58.0
	var camera_fov_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	camera_fov_btn.pressed.connect(_cycle_camera_fov)
	root.add_child(camera_fov_btn)
	_gameplay_buttons["camera_fov"] = camera_fov_btn
	_refresh_gameplay_button_labels()
	return root


func _build_graphics_screen() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_screen_chrome(root, "GRAPHICS", "SYS_ID: LC-992-ALPHA // DISPLAY AND RENDERING")

	var back := _make_back_button(Vector2(SUBMENU_X, 190.0))
	back.pressed.connect(func(): _show_screen("options"))
	root.add_child(back)

	var row_width := OPERATOR_RAIL_WIDTH - 64.0
	var row_y := 252.0
	var vsync_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	vsync_btn.pressed.connect(_cycle_vsync)
	root.add_child(vsync_btn)
	_graphics_buttons["vsync"] = vsync_btn

	row_y += 58.0
	var display_mode_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	display_mode_btn.pressed.connect(_cycle_display_mode)
	root.add_child(display_mode_btn)
	_graphics_buttons["display_mode"] = display_mode_btn

	row_y += 58.0
	var resolution_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	resolution_btn.pressed.connect(_cycle_resolution)
	root.add_child(resolution_btn)
	_graphics_buttons["resolution"] = resolution_btn

	row_y += 58.0
	var frame_limit_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	frame_limit_btn.pressed.connect(_cycle_frame_limit)
	root.add_child(frame_limit_btn)
	_graphics_buttons["frame_limit"] = frame_limit_btn

	row_y += 58.0
	var aa_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	aa_btn.pressed.connect(_cycle_anti_aliasing)
	root.add_child(aa_btn)
	_graphics_buttons["anti_aliasing"] = aa_btn

	row_y += 58.0
	var render_scale_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	render_scale_btn.pressed.connect(_cycle_render_scale)
	root.add_child(render_scale_btn)
	_graphics_buttons["render_scale"] = render_scale_btn

	row_y += 58.0
	var upscaler_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	upscaler_btn.pressed.connect(_cycle_upscaler)
	root.add_child(upscaler_btn)
	_graphics_buttons["upscaler"] = upscaler_btn

	row_y += 58.0
	var view_distance_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	view_distance_btn.pressed.connect(_cycle_view_distance)
	root.add_child(view_distance_btn)
	_graphics_buttons["view_distance"] = view_distance_btn

	row_y += 58.0
	var enemy_visibility_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	enemy_visibility_btn.pressed.connect(_cycle_enemy_visibility)
	root.add_child(enemy_visibility_btn)
	_graphics_buttons["enemy_visibility"] = enemy_visibility_btn

	row_y += 58.0
	var fps_btn := _make_row_button("", Vector2(SUBMENU_X, row_y), row_width)
	fps_btn.pressed.connect(_cycle_show_fps)
	root.add_child(fps_btn)
	_graphics_buttons["show_fps"] = fps_btn
	_refresh_graphics_button_labels()
	return root


func _on_audio_volume_changed(value: float, key: String) -> void:
	var clamped_value := clampf(value, 0.0, 1.0)
	if key == "radio":
		_radio_volume = clamped_value
	else:
		_master_volume = clamped_value
	_refresh_audio_controls()
	_apply_audio_settings()
	_save_settings()


func _cycle_radio_captions() -> void:
	_radio_captions_enabled = not _radio_captions_enabled
	_apply_radio_settings()
	_refresh_audio_controls()
	_save_settings()


func _cycle_radio_caption_duration() -> void:
	_radio_caption_duration_index = (_radio_caption_duration_index + 1) % RADIO_CAPTION_DURATION_LABELS.size()
	_apply_radio_settings()
	_refresh_audio_controls()
	_save_settings()


func _cycle_vsync() -> void:
	_vsync_enabled = not _vsync_enabled
	_apply_vsync_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_display_mode() -> void:
	_display_mode_index = (_display_mode_index + 1) % DISPLAY_MODE_LABELS.size()
	_apply_resolution_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_resolution() -> void:
	_resolution_index = (_resolution_index + 1) % RESOLUTION_LABELS.size()
	_apply_resolution_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_frame_limit() -> void:
	_frame_limit_index = (_frame_limit_index + 1) % FRAME_LIMIT_LABELS.size()
	_apply_frame_limit_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_anti_aliasing() -> void:
	_anti_aliasing_index = (_anti_aliasing_index + 1) % ANTI_ALIASING_LABELS.size()
	_apply_anti_aliasing_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_render_scale() -> void:
	_render_scale_index = (_render_scale_index + 1) % RENDER_SCALE_LABELS.size()
	_apply_render_scale_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_upscaler() -> void:
	_upscaler_index = (_upscaler_index + 1) % UPSCALER_LABELS.size()
	_apply_render_scale_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_view_distance() -> void:
	_view_distance_level = (_view_distance_level % 5) + 1
	_apply_view_distance_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_enemy_visibility() -> void:
	_enemy_visibility_index = (_enemy_visibility_index + 1) % ENEMY_VISIBILITY_LABELS.size()
	_apply_enemy_visibility_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_show_fps() -> void:
	_show_fps_enabled = not _show_fps_enabled
	_apply_fps_counter_setting()
	_refresh_graphics_button_labels()
	_save_settings()


func _cycle_rudder_assist() -> void:
	_rudder_assist_level = (_rudder_assist_level + 1) % RUDDER_ASSIST_LABELS.size()
	_refresh_gameplay_button_labels()
	_save_settings()


func _cycle_flight_model() -> void:
	_flight_model_index = (_flight_model_index + 1) % FLIGHT_MODEL_LABELS.size()
	_refresh_gameplay_button_labels()
	_save_settings()


func _cycle_helicopter_rudder_assist() -> void:
	_helicopter_rudder_assist_level = (_helicopter_rudder_assist_level + 1) % RUDDER_ASSIST_LABELS.size()
	_refresh_gameplay_button_labels()
	_save_settings()


func _cycle_stick_deadzone() -> void:
	_stick_deadzone_index = (_stick_deadzone_index + 1) % STICK_DEADZONE_LABELS.size()
	_apply_stick_deadzone_setting()
	_refresh_gameplay_button_labels()
	_save_settings()


func _cycle_controller_menu_cursor() -> void:
	_controller_menu_cursor_enabled = not _controller_menu_cursor_enabled
	if not _controller_menu_cursor_enabled:
		_deactivate_controller_menu_cursor()
	_refresh_gameplay_button_labels()
	_save_settings()


func _cycle_look_sensitivity() -> void:
	_look_sensitivity_index = (_look_sensitivity_index + 1) % LOOK_SENSITIVITY_LABELS.size()
	_refresh_gameplay_button_labels()
	_save_settings()


func _cycle_invert_look_y() -> void:
	_invert_look_y = not _invert_look_y
	_refresh_gameplay_button_labels()
	_save_settings()


func _cycle_camera_motion() -> void:
	_camera_motion_index = (_camera_motion_index + 1) % CAMERA_MOTION_LABELS.size()
	_refresh_gameplay_button_labels()
	_save_settings()


func _cycle_camera_fov() -> void:
	_camera_fov_index = (_camera_fov_index + 1) % CAMERA_FOV_LABELS.size()
	_apply_camera_settings()
	_refresh_gameplay_button_labels()
	_save_settings()


func _refresh_audio_controls() -> void:
	_master_volume = clampf(_master_volume, 0.0, 1.0)
	_radio_volume = clampf(_radio_volume, 0.0, 1.0)
	_radio_caption_duration_index = clampi(_radio_caption_duration_index, 0, RADIO_CAPTION_DURATION_LABELS.size() - 1)
	for key in ["master", "radio"]:
		var value := _radio_volume if key == "radio" else _master_volume
		if _audio_sliders.has(key):
			(_audio_sliders[key] as HSlider).set_value_no_signal(value)
		if _audio_value_labels.has(key):
			(_audio_value_labels[key] as Label).text = "%d%%" % roundi(value * 100.0)
	if _audio_buttons.has("captions"):
		(_audio_buttons["captions"] as Button).text = "RADIO CAPTIONS: %s" % ("ON" if _radio_captions_enabled else "OFF")
	if _audio_buttons.has("caption_duration"):
		var duration_btn := _audio_buttons["caption_duration"] as Button
		duration_btn.text = "CAPTION DURATION: %s" % RADIO_CAPTION_DURATION_LABELS[_radio_caption_duration_index]
		duration_btn.disabled = not _radio_captions_enabled


func _refresh_graphics_button_labels() -> void:
	if _graphics_buttons.has("vsync"):
		var btn := _graphics_buttons["vsync"] as Button
		btn.text = "V-SYNC: %s" % ("ON" if _vsync_enabled else "OFF")
	if _graphics_buttons.has("display_mode"):
		var btn := _graphics_buttons["display_mode"] as Button
		btn.text = "DISPLAY MODE: %s" % DISPLAY_MODE_LABELS[_display_mode_index]
	if _graphics_buttons.has("resolution"):
		var btn := _graphics_buttons["resolution"] as Button
		var borderless := _display_mode_index == 1
		btn.text = "RESOLUTION: %s" % ("DESKTOP" if borderless else RESOLUTION_LABELS[_resolution_index])
		btn.disabled = borderless
	if _graphics_buttons.has("frame_limit"):
		var btn := _graphics_buttons["frame_limit"] as Button
		btn.text = "FRAME LIMIT: %s" % FRAME_LIMIT_LABELS[_frame_limit_index]
	if _graphics_buttons.has("anti_aliasing"):
		var btn := _graphics_buttons["anti_aliasing"] as Button
		btn.text = "ANTI-ALIASING: %s" % ANTI_ALIASING_LABELS[_anti_aliasing_index]
	if _graphics_buttons.has("render_scale"):
		var btn := _graphics_buttons["render_scale"] as Button
		btn.text = "RENDER SCALE: %s" % RENDER_SCALE_LABELS[_render_scale_index]
	if _graphics_buttons.has("upscaler"):
		var btn := _graphics_buttons["upscaler"] as Button
		btn.text = "UPSCALE FILTER: %s" % UPSCALER_LABELS[_upscaler_index]
		btn.disabled = _render_scale_index == RENDER_SCALE_LABELS.size() - 1
	if _graphics_buttons.has("view_distance"):
		var btn := _graphics_buttons["view_distance"] as Button
		btn.text = "VIEW DISTANCE: %d / 5" % _view_distance_level
	if _graphics_buttons.has("enemy_visibility"):
		var btn := _graphics_buttons["enemy_visibility"] as Button
		btn.text = "ENEMY VISIBILITY: %s" % ENEMY_VISIBILITY_LABELS[_enemy_visibility_index]
	if _graphics_buttons.has("show_fps"):
		var btn := _graphics_buttons["show_fps"] as Button
		btn.text = "SHOW FPS: %s" % ("ON" if _show_fps_enabled else "OFF")


func _refresh_gameplay_button_labels() -> void:
	_flight_model_index = clampi(_flight_model_index, 0, FLIGHT_MODEL_LABELS.size() - 1)
	_rudder_assist_level = clampi(_rudder_assist_level, 0, RUDDER_ASSIST_LABELS.size() - 1)
	_helicopter_rudder_assist_level = clampi(_helicopter_rudder_assist_level, 0, RUDDER_ASSIST_LABELS.size() - 1)
	_stick_deadzone_index = clampi(_stick_deadzone_index, 0, STICK_DEADZONE_LABELS.size() - 1)
	_look_sensitivity_index = clampi(_look_sensitivity_index, 0, LOOK_SENSITIVITY_LABELS.size() - 1)
	_camera_motion_index = clampi(_camera_motion_index, 0, CAMERA_MOTION_LABELS.size() - 1)
	_camera_fov_index = clampi(_camera_fov_index, 0, CAMERA_FOV_LABELS.size() - 1)
	if _gameplay_buttons.has("flight_model"):
		(_gameplay_buttons["flight_model"] as Button).text = "FLIGHT MODEL: %s" % FLIGHT_MODEL_LABELS[_flight_model_index]
	if _gameplay_buttons.has("rudder_assist"):
		var btn := _gameplay_buttons["rudder_assist"] as Button
		btn.text = "AIRPLANE RUDDER ASSIST: %s" % RUDDER_ASSIST_LABELS[_rudder_assist_level]
	if _gameplay_buttons.has("helicopter_rudder_assist"):
		var btn := _gameplay_buttons["helicopter_rudder_assist"] as Button
		btn.text = "HELI RUDDER ASSIST: %s" % RUDDER_ASSIST_LABELS[_helicopter_rudder_assist_level]
	if _gameplay_buttons.has("stick_deadzone"):
		(_gameplay_buttons["stick_deadzone"] as Button).text = "FLIGHT CONTROL DEADZONE: %s" % STICK_DEADZONE_LABELS[_stick_deadzone_index]
	if _gameplay_buttons.has("controller_menu_cursor"):
		(_gameplay_buttons["controller_menu_cursor"] as Button).text = "CONTROLLER MENU CURSOR: %s" % ("ON" if _controller_menu_cursor_enabled else "OFF")
	if _gameplay_buttons.has("look_sensitivity"):
		(_gameplay_buttons["look_sensitivity"] as Button).text = "LOOK SENSITIVITY: %s" % LOOK_SENSITIVITY_LABELS[_look_sensitivity_index]
	if _gameplay_buttons.has("invert_look_y"):
		(_gameplay_buttons["invert_look_y"] as Button).text = "INVERT LOOK Y: %s" % ("ON" if _invert_look_y else "OFF")
	if _gameplay_buttons.has("camera_motion"):
		(_gameplay_buttons["camera_motion"] as Button).text = "CAMERA MOTION: %s" % CAMERA_MOTION_LABELS[_camera_motion_index]
	if _gameplay_buttons.has("camera_fov"):
		(_gameplay_buttons["camera_fov"] as Button).text = "CAMERA FOV: %s" % CAMERA_FOV_LABELS[_camera_fov_index]


func get_rudder_assist_level() -> int:
	return clampi(_rudder_assist_level, 0, RUDDER_ASSIST_LABELS.size() - 1)


func get_flight_model_index() -> int:
	return clampi(_flight_model_index, 0, FLIGHT_MODEL_LABELS.size() - 1)


func is_advanced_flight_model() -> bool:
	return get_flight_model_index() == 1


func get_stick_deadzone() -> float:
	var index := clampi(_stick_deadzone_index, 0, STICK_DEADZONE_VALUES.size() - 1)
	return float(STICK_DEADZONE_VALUES[index])


func get_rudder_assist_strength() -> float:
	return float(RUDDER_ASSIST_STRENGTHS[get_rudder_assist_level()])


func get_helicopter_rudder_assist_level() -> int:
	return clampi(_helicopter_rudder_assist_level, 0, RUDDER_ASSIST_LABELS.size() - 1)


func get_helicopter_rudder_assist_strength() -> float:
	return float(RUDDER_ASSIST_STRENGTHS[get_helicopter_rudder_assist_level()])


func get_radio_volume() -> float:
	return clampf(_radio_volume, 0.0, 1.0)


func get_radio_captions_enabled() -> bool:
	return _radio_captions_enabled


func get_radio_caption_duration_s() -> float:
	return float(RADIO_CAPTION_DURATION_VALUES[clampi(_radio_caption_duration_index, 0, RADIO_CAPTION_DURATION_VALUES.size() - 1)])


func get_show_fps_enabled() -> bool:
	return _show_fps_enabled


func get_look_sensitivity_multiplier() -> float:
	return float(LOOK_SENSITIVITY_VALUES[clampi(_look_sensitivity_index, 0, LOOK_SENSITIVITY_VALUES.size() - 1)])


func get_invert_look_y() -> bool:
	return _invert_look_y


func get_camera_motion_scale() -> float:
	return float(CAMERA_MOTION_VALUES[clampi(_camera_motion_index, 0, CAMERA_MOTION_VALUES.size() - 1)])


func get_camera_fov() -> float:
	return float(CAMERA_FOV_VALUES[clampi(_camera_fov_index, 0, CAMERA_FOV_VALUES.size() - 1)])


func _apply_all_settings() -> void:
	_apply_audio_settings()
	_apply_graphics_settings()
	_apply_gameplay_settings()
	_refresh_audio_controls()
	_refresh_graphics_button_labels()
	_refresh_gameplay_button_labels()


func _apply_audio_settings() -> void:
	_apply_bus_volume("Master", _master_volume)
	_apply_radio_settings()


func _apply_bus_volume(bus_name: String, value: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(clampf(value, 0.0, 1.0), 0.0001)))


func _apply_radio_settings() -> void:
	_apply_bus_volume("Radio", _radio_volume)
	var radio_comms := get_node_or_null("/root/RadioComms")
	if radio_comms != null and radio_comms.has_method("apply_user_settings"):
		radio_comms.call("apply_user_settings", _radio_volume, _radio_captions_enabled, get_radio_caption_duration_s())


func _apply_gameplay_settings() -> void:
	_apply_stick_deadzone_setting()
	_apply_camera_settings()


func _apply_stick_deadzone_setting() -> void:
	_stick_deadzone_index = clampi(_stick_deadzone_index, 0, STICK_DEADZONE_VALUES.size() - 1)
	var deadzone := float(STICK_DEADZONE_VALUES[_stick_deadzone_index])
	for action: StringName in STICK_DEADZONE_ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, deadzone)


func _apply_camera_settings() -> void:
	for controller in get_tree().get_nodes_in_group("camera_controller"):
		if controller.has_method("apply_user_camera_settings"):
			controller.call("apply_user_camera_settings")
	for commander in get_tree().get_nodes_in_group("commander_camera_controller"):
		if commander.has_method("apply_user_camera_settings"):
			commander.call("apply_user_camera_settings")


func _apply_graphics_settings() -> void:
	_apply_vsync_setting()
	_apply_resolution_setting()
	_apply_frame_limit_setting()
	_apply_anti_aliasing_setting()
	_apply_render_scale_setting()
	_apply_view_distance_setting()
	_apply_enemy_visibility_setting()
	_apply_fps_counter_setting()


func _apply_vsync_setting() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _vsync_enabled else DisplayServer.VSYNC_DISABLED)


func _apply_resolution_setting() -> void:
	_resolution_index = clampi(_resolution_index, 0, RESOLUTION_LABELS.size() - 1)
	_display_mode_index = clampi(_display_mode_index, 0, DISPLAY_MODE_LABELS.size() - 1)
	var target_size: Vector2i = RESOLUTION_SIZES[_resolution_index]
	var root_window := get_tree().root
	if root_window != null:
		root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root_window.content_scale_factor = 1.0
		root_window.content_scale_size = target_size
	match _display_mode_index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(target_size)
			var screen := DisplayServer.window_get_current_screen()
			var screen_size := DisplayServer.screen_get_size(screen)
			var screen_position := DisplayServer.screen_get_position(screen)
			DisplayServer.window_set_position(screen_position + (screen_size - target_size) / 2)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(target_size)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	call_deferred("_print_resolution_debug", target_size)
	call_deferred("_layout_ui_root")


func _apply_frame_limit_setting() -> void:
	_frame_limit_index = clampi(_frame_limit_index, 0, FRAME_LIMIT_VALUES.size() - 1)
	Engine.max_fps = FRAME_LIMIT_VALUES[_frame_limit_index]


func _apply_fps_counter_setting() -> void:
	var fps_counter := get_node_or_null("/root/FPSCounter")
	if fps_counter != null and fps_counter.has_method("set_display_enabled"):
		fps_counter.call("set_display_enabled", _show_fps_enabled)


func _apply_anti_aliasing_setting() -> void:
	_anti_aliasing_index = clampi(_anti_aliasing_index, 0, ANTI_ALIASING_LABELS.size() - 1)
	_apply_anti_aliasing_to_viewport(get_viewport())
	for viewport_node in get_tree().get_nodes_in_group("settings_aa_viewport"):
		if viewport_node is Viewport:
			_apply_anti_aliasing_to_viewport(viewport_node as Viewport)


func _apply_anti_aliasing_to_viewport(viewport: Viewport) -> void:
	if viewport == null:
		return
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	match _anti_aliasing_index:
		1:
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		2:
			viewport.msaa_3d = Viewport.MSAA_2X
		3:
			viewport.msaa_3d = Viewport.MSAA_4X
		4:
			viewport.use_taa = true


func _apply_render_scale_setting() -> void:
	_render_scale_index = clampi(_render_scale_index, 0, RENDER_SCALE_VALUES.size() - 1)
	_upscaler_index = clampi(_upscaler_index, 0, UPSCALER_LABELS.size() - 1)
	var viewport := get_viewport()
	if viewport == null:
		return
	viewport.scaling_3d_scale = RENDER_SCALE_VALUES[_render_scale_index]
	viewport.scaling_3d_mode = (
		Viewport.SCALING_3D_MODE_FSR
		if _upscaler_index == 1
		else Viewport.SCALING_3D_MODE_BILINEAR
	)


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


func _apply_enemy_visibility_setting() -> void:
	_enemy_visibility_index = clampi(_enemy_visibility_index, 0, ENEMY_VISIBILITY_LABELS.size() - 1)
	var budget := get_node_or_null("/root/EnemyVisualBudget")
	if budget == null:
		return
	budget.set(
		"enemy_contrast_start_distance_m",
		float(ENEMY_VISIBILITY_START_DISTANCE_M[_enemy_visibility_index])
	)
	budget.set(
		"enemy_contrast_full_distance_m",
		float(ENEMY_VISIBILITY_FULL_DISTANCE_M[_enemy_visibility_index])
	)
	budget.set(
		"enemy_max_contrast_strength",
		float(ENEMY_VISIBILITY_MAX_STRENGTH[_enemy_visibility_index])
	)


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
	if node is Viewport and node.is_in_group("settings_aa_viewport"):
		_apply_anti_aliasing_to_viewport(node as Viewport)
	if node.is_in_group("terrain") or ("load_radius_chunks" in node):
		var radius: int = VIEW_DISTANCE_CHUNK_RADIUS[clampi(_view_distance_level, 1, 5) - 1]
		call_deferred("_apply_view_distance_to_terrain", node, radius)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		_apply_bus_volume("Master", _master_volume)
		return
	var loaded_graphics_version := int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "settings_version", 0))
	var should_migrate_graphics := loaded_graphics_version < GRAPHICS_SETTINGS_VERSION
	var loaded_gameplay_version := int(cfg.get_value(SETTINGS_SECTION_GAMEPLAY, "settings_version", 0))
	var should_migrate_gameplay := loaded_gameplay_version < GAMEPLAY_SETTINGS_VERSION
	_master_volume = clampf(float(cfg.get_value(SETTINGS_SECTION_AUDIO, "master_volume", _master_volume)), 0.0, 1.0)
	_radio_volume = clampf(float(cfg.get_value(SETTINGS_SECTION_AUDIO, "radio_volume", _radio_volume)), 0.0, 1.0)
	_radio_captions_enabled = bool(cfg.get_value(SETTINGS_SECTION_AUDIO, "radio_captions_enabled", _radio_captions_enabled))
	_radio_caption_duration_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_AUDIO, "radio_caption_duration_index", _radio_caption_duration_index)),
		0,
		RADIO_CAPTION_DURATION_LABELS.size() - 1
	)
	_vsync_enabled = bool(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "vsync_enabled", _vsync_enabled))
	_resolution_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "resolution_index", _resolution_index)),
		0,
		RESOLUTION_LABELS.size() - 1
	)
	_display_mode_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "display_mode_index", _display_mode_index)),
		0,
		DISPLAY_MODE_LABELS.size() - 1
	)
	_frame_limit_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "frame_limit_index", _frame_limit_index)),
		0,
		FRAME_LIMIT_LABELS.size() - 1
	)
	_anti_aliasing_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "anti_aliasing_index", _anti_aliasing_index)),
		0,
		ANTI_ALIASING_LABELS.size() - 1
	)
	_render_scale_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "render_scale_index", _render_scale_index)),
		0,
		RENDER_SCALE_LABELS.size() - 1
	)
	_upscaler_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "upscaler_index", _upscaler_index)),
		0,
		UPSCALER_LABELS.size() - 1
	)
	_view_distance_level = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "view_distance_level", _view_distance_level)),
		1,
		5
	)
	_enemy_visibility_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "enemy_visibility_index", _enemy_visibility_index)),
		0,
		ENEMY_VISIBILITY_LABELS.size() - 1
	)
	_show_fps_enabled = bool(cfg.get_value(SETTINGS_SECTION_GRAPHICS, "show_fps_enabled", _show_fps_enabled))
	_rudder_assist_level = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GAMEPLAY, "rudder_assist_level", _rudder_assist_level)),
		0,
		RUDDER_ASSIST_LABELS.size() - 1
	)
	_flight_model_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GAMEPLAY, "flight_model_index", _flight_model_index)),
		0,
		FLIGHT_MODEL_LABELS.size() - 1
	)
	_helicopter_rudder_assist_level = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GAMEPLAY, "helicopter_rudder_assist_level", _helicopter_rudder_assist_level)),
		0,
		RUDDER_ASSIST_LABELS.size() - 1
	)
	_stick_deadzone_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GAMEPLAY, "stick_deadzone_index", _stick_deadzone_index)),
		0,
		STICK_DEADZONE_LABELS.size() - 1
	)
	_look_sensitivity_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GAMEPLAY, "look_sensitivity_index", _look_sensitivity_index)),
		0,
		LOOK_SENSITIVITY_LABELS.size() - 1
	)
	_invert_look_y = bool(cfg.get_value(SETTINGS_SECTION_GAMEPLAY, "invert_look_y", _invert_look_y))
	_camera_motion_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GAMEPLAY, "camera_motion_index", _camera_motion_index)),
		0,
		CAMERA_MOTION_LABELS.size() - 1
	)
	_camera_fov_index = clampi(
		int(cfg.get_value(SETTINGS_SECTION_GAMEPLAY, "camera_fov_index", _camera_fov_index)),
		0,
		CAMERA_FOV_LABELS.size() - 1
	)
	_controller_menu_cursor_enabled = bool(cfg.get_value(
		SETTINGS_SECTION_GAMEPLAY,
		"controller_menu_cursor_enabled",
		_controller_menu_cursor_enabled
	))
	if should_migrate_gameplay:
		# The previous 15% default was followed by another steering deadzone and
		# a zero-slope power curve. Start the new Advanced fixed-wing response at
		# one explicit 5% Input Map deadzone instead.
		_stick_deadzone_index = DEFAULT_STICK_DEADZONE_INDEX
	if should_migrate_graphics or should_migrate_gameplay:
		_save_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION_AUDIO, "master_volume", _master_volume)
	cfg.set_value(SETTINGS_SECTION_AUDIO, "radio_volume", _radio_volume)
	cfg.set_value(SETTINGS_SECTION_AUDIO, "radio_captions_enabled", _radio_captions_enabled)
	cfg.set_value(SETTINGS_SECTION_AUDIO, "radio_caption_duration_index", _radio_caption_duration_index)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "settings_version", GRAPHICS_SETTINGS_VERSION)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "vsync_enabled", _vsync_enabled)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "resolution_index", _resolution_index)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "display_mode_index", _display_mode_index)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "frame_limit_index", _frame_limit_index)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "anti_aliasing_index", _anti_aliasing_index)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "render_scale_index", _render_scale_index)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "upscaler_index", _upscaler_index)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "view_distance_level", _view_distance_level)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "enemy_visibility_index", _enemy_visibility_index)
	cfg.set_value(SETTINGS_SECTION_GRAPHICS, "show_fps_enabled", _show_fps_enabled)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "settings_version", GAMEPLAY_SETTINGS_VERSION)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "rudder_assist_level", _rudder_assist_level)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "flight_model_index", _flight_model_index)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "helicopter_rudder_assist_level", _helicopter_rudder_assist_level)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "stick_deadzone_index", _stick_deadzone_index)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "look_sensitivity_index", _look_sensitivity_index)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "invert_look_y", _invert_look_y)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "camera_motion_index", _camera_motion_index)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "camera_fov_index", _camera_fov_index)
	cfg.set_value(SETTINGS_SECTION_GAMEPLAY, "controller_menu_cursor_enabled", _controller_menu_cursor_enabled)
	cfg.save(SETTINGS_PATH)


func _reset_all_defaults() -> void:
	_master_volume = DEFAULT_MASTER_VOLUME
	_radio_volume = DEFAULT_RADIO_VOLUME
	_radio_captions_enabled = DEFAULT_RADIO_CAPTIONS_ENABLED
	_radio_caption_duration_index = DEFAULT_RADIO_CAPTION_DURATION_INDEX
	_vsync_enabled = false
	_resolution_index = 0
	_display_mode_index = 2
	_frame_limit_index = 0
	_anti_aliasing_index = 2
	_render_scale_index = 4
	_upscaler_index = 1
	_view_distance_level = DEFAULT_VIEW_DISTANCE_LEVEL
	_enemy_visibility_index = DEFAULT_ENEMY_VISIBILITY_INDEX
	_show_fps_enabled = DEFAULT_SHOW_FPS_ENABLED
	_rudder_assist_level = 0
	_flight_model_index = DEFAULT_FLIGHT_MODEL_INDEX
	_helicopter_rudder_assist_level = 1
	_stick_deadzone_index = DEFAULT_STICK_DEADZONE_INDEX
	_look_sensitivity_index = DEFAULT_LOOK_SENSITIVITY_INDEX
	_invert_look_y = DEFAULT_INVERT_LOOK_Y
	_camera_motion_index = DEFAULT_CAMERA_MOTION_INDEX
	_camera_fov_index = DEFAULT_CAMERA_FOV_INDEX
	_controller_menu_cursor_enabled = DEFAULT_CONTROLLER_MENU_CURSOR_ENABLED
	_deactivate_controller_menu_cursor()
	_apply_all_settings()
	_save_settings()


func _build_controls_screen() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_screen_chrome(root, "CONTROLS", "SYS_ID: LC-992-ALPHA // INPUT REFERENCE")

	var panel := Panel.new()
	panel.position = Vector2(OPERATOR_RAIL_WIDTH + 56.0, 196.0)
	panel.size = Vector2(BASE_UI_SIZE.x - OPERATOR_RAIL_WIDTH - 112.0, 790.0)
	panel.add_theme_stylebox_override("panel", MenuTheme.make_panel_style(MenuTheme.SURFACE_SOLID, MenuTheme.OUTLINE, 1))
	root.add_child(panel)

	var back := _make_back_button(Vector2(SUBMENU_X, 190.0))
	back.pressed.connect(func(): _show_screen("main"))
	root.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.position = panel.position + Vector2(24.0, 24.0)
	scroll.size = panel.size - Vector2(48.0, 48.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", COLOR_BODY)
	rt.add_theme_font_override("normal_font", MenuTypography.TECH_FONT)
	rt.add_theme_font_override("bold_font", MenuTypography.TECH_FONT)
	rt.add_theme_font_size_override("normal_font_size", MenuTypography.BODY_SIZE)
	rt.add_theme_font_size_override("bold_font_size", MenuTypography.BODY_SIZE)
	rt.text = _controls_bbcode()
	scroll.add_child(rt)
	return root


# ---------------------------------------------------------------------------
# Widget helpers
# ---------------------------------------------------------------------------

func _make_console_label(text: String, pos: Vector2, font_size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_text_button(label_text: String, pos: Vector2) -> Button:
	var btn := Button.new()
	btn.text = label_text.to_upper()
	btn.position = pos
	btn.size = Vector2(OPERATOR_RAIL_WIDTH - 40.0, 54.0)
	btn.custom_minimum_size = btn.size
	btn.focus_mode = Control.FOCUS_ALL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MenuTheme.apply_operator_button(btn, FONT_NORMAL)
	return btn


func _make_row_button(label_text: String, pos: Vector2, width: float) -> Button:
	var btn := Button.new()
	btn.text = label_text.to_upper()
	btn.position = pos
	btn.size = Vector2(width, 54.0)
	btn.custom_minimum_size = Vector2(width, 54.0)
	btn.focus_mode = Control.FOCUS_ALL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	MenuTheme.apply_operator_button(btn, MenuTypography.FIELD_VALUE_SIZE)
	return btn


func _make_back_button(pos: Vector2) -> Button:
	var btn := Button.new()
	btn.text = "< BACK"
	btn.position = pos
	btn.custom_minimum_size = Vector2(240, 44)
	btn.focus_mode = Control.FOCUS_ALL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MenuTheme.apply_operator_button(btn, MenuTypography.SMALL_ACTION_SIZE)
	return btn


# ---------------------------------------------------------------------------
# Controls content
# ---------------------------------------------------------------------------

func _controls_bbcode() -> String:
	var w = COLOR_WHITE.to_html(false)
	var d = Color(1, 1, 1, 0.50).to_html(false)
	return """
[color=#{w}][b]MENUS (OPTIONAL CURSOR MODE)[/b][/color]
[color=#{d}]LEFT STICK[/color]       MOVE POINTER
[color=#{d}]A / RIGHT TRIGGER[/color] LEFT CLICK

[color=#{w}][b]FLIGHT[/b][/color]
[color=#{d}]LEFT STICK[/color]       PITCH / ROLL
[color=#{d}]LT / RT[/color]          YAW LEFT / RIGHT
[color=#{d}]LB[/color]               THROTTLE UP
[color=#{d}]RB[/color]               THROTTLE DOWN

[color=#{w}][b]AIRCRAFT SYSTEMS[/b][/color]
[color=#{d}]B / CIRCLE[/color]       LANDING GEAR
[color=#{d}]D-PAD UP[/color]         FLAPS UP / REQUEST LAUNCH

[color=#{w}][b]COMBAT[/b][/color]
[color=#{d}]A / X[/color]            FIRE WEAPON
[color=#{d}]X / SQUARE[/color]       CYCLE WEAPON
[color=#{d}]D-PAD LEFT/RIGHT[/color] PREVIOUS / NEXT RADAR TARGET
[color=#{d}]D-PAD DOWN[/color]       CLOSEST RADAR TARGET AHEAD
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


func _return_to_main_menu() -> void:
	_close()
	get_tree().change_scene_to_file("res://UI/MainMenu.tscn")


func _back_from_options() -> void:
	if _opened_from_main_menu:
		_close()
	else:
		_show_screen("main")


func _navigate_back() -> void:
	match _current_screen:
		"main":
			_close()
		"audio", "graphics", "gameplay":
			_show_screen("options")
		"options":
			_back_from_options()
		"controls":
			_show_screen("main")


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
		_navigate_back()
		return true

	return false

func _move_focus(focus_owner: Control, side: int) -> void:
	if focus_owner == null:
		return
	var next_focus: Control = focus_owner.find_valid_focus_neighbor(side)
	if next_focus:
		next_focus.grab_focus()
		return

	var controls: Array[Control] = _focusable_controls_in_current_screen()
	if controls.is_empty():
		return
	var idx: int = controls.find(focus_owner)
	if idx < 0:
		controls[0].grab_focus()
		return
	var dir: int = -1 if side == Side.SIDE_TOP else 1
	var next_idx: int = (idx + dir + controls.size()) % controls.size()
	controls[next_idx].grab_focus()

func _focusable_controls_in_current_screen() -> Array[Control]:
	var out: Array[Control] = []
	var screen: Control = _screens.get(_current_screen) as Control
	if screen == null:
		return out
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back() as Node
		if n is Control:
			var control := n as Control
			var disabled := control is BaseButton and (control as BaseButton).disabled
			if control != screen and control.visible and not disabled and control.focus_mode != Control.FOCUS_NONE:
				out.append(control)
		for c in n.get_children():
			if c is Node:
				stack.append(c as Node)
	out.sort_custom(func(a: Control, b: Control) -> bool:
		if not is_equal_approx(a.global_position.y, b.global_position.y):
			return a.global_position.y < b.global_position.y
		return a.global_position.x < b.global_position.x
	)
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
