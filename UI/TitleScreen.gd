extends Node3D

const MENU_FONT: FontFile = preload("res://UI/Orbitron-VariableFont_wght.ttf")
const TITLE_FONT: FontFile = preload("res://UI/Pixel.ttf")
const CARRIER_PREVIEW_SCENE: PackedScene = preload("res://Models/LandCarrier/Land carrier body.glb")
const GAME_SCENE := "res://Main_Scene.tscn"
const DEFAULT_CARRIER_NAME := "Land Carrier"
const BASE_UI_SIZE := Vector2(1280.0, 720.0)

const PAD_BUTTON_A := 0
const PAD_BUTTON_B := 1
const PAD_BUTTON_BACK := 4
const PAD_BUTTON_DPAD_UP := 11
const PAD_BUTTON_DPAD_DOWN := 12
const PAD_BUTTON_DPAD_LEFT := 13
const PAD_BUTTON_DPAD_RIGHT := 14

const DEFAULT_PRIMARY_COLOR_INDEX := 23
const DEFAULT_SECONDARY_COLOR_INDEX := 8
const PATTERN_NAMES: Array[String] = ["SOLID", "STRIPES", "CHECKS", "CAMO"]
const PATTERN_INDICES: Array[int] = [0, 1, 9, 4]

var _title_mesh: MeshInstance3D
var _camera: Camera3D
var _preview_root: Node3D
var _preview_model: Node
var _ui_root: Control
var _main_panel: Control
var _setup_panel: Control
var _message_label: Label
var _name_edit: LineEdit
var _carrier_colors: Array[Color] = []
var _carrier_color_names: Array[String] = []
var _primary_index: int = DEFAULT_PRIMARY_COLOR_INDEX
var _secondary_index: int = DEFAULT_SECONDARY_COLOR_INDEX
var _pattern_choice_index: int = 0
var _current_screen := ""
var _primary_value_button: Button
var _secondary_value_button: Button
var _pattern_value_button: Button


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_load_livery_palette()
	_build_title_scene()
	_build_ui()
	if not get_tree().root.size_changed.is_connected(_layout_ui_root):
		get_tree().root.size_changed.connect(_layout_ui_root)
	_layout_ui_root()
	_show_main_menu()


func _load_livery_palette() -> void:
	_carrier_colors.clear()
	_carrier_color_names.clear()

	var livery := get_node_or_null("/root/Livery")
	if livery != null and livery.has_method("get_preset_upper_color_count") \
			and livery.has_method("get_preset_upper_color") \
			and livery.has_method("get_preset_upper_color_name"):
		var count: int = int(livery.call("get_preset_upper_color_count"))
		for i in range(count):
			var color_variant: Variant = livery.call("get_preset_upper_color", i)
			var name_variant: Variant = livery.call("get_preset_upper_color_name", i)
			if color_variant is Color:
				_carrier_colors.append(color_variant as Color)
			else:
				_carrier_colors.append(Color.WHITE)
			_carrier_color_names.append(str(name_variant))

	if _carrier_colors.is_empty():
		_carrier_colors = [Color(0.36, 0.40, 0.44, 1.0), Color(0.90, 0.66, 0.18, 1.0)]
		_carrier_color_names = ["STEEL GREY", "AMBER"]
		_primary_index = 0
		_secondary_index = 1
	else:
		_primary_index = clampi(DEFAULT_PRIMARY_COLOR_INDEX, 0, _carrier_colors.size() - 1)
		_secondary_index = clampi(DEFAULT_SECONDARY_COLOR_INDEX, 0, _carrier_colors.size() - 1)


func _process(delta: float) -> void:
	if is_instance_valid(_title_mesh) and _title_mesh.visible:
		_title_mesh.rotation_degrees.y += 22.0 * delta
		_title_mesh.rotation_degrees.x = sin(Time.get_ticks_msec() * 0.0014) * 5.0
	if is_instance_valid(_preview_root) and _preview_root.visible:
		_preview_root.rotation_degrees.y += 10.0 * delta


func _input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if pause_menu != null and bool(pause_menu.get("visible")):
		return
	if _current_screen == "":
		return

	var focus_owner := viewport.gui_get_focus_owner()
	if focus_owner == null:
		focus_owner = _focus_first_button()

	if focus_owner is LineEdit:
		if _is_menu_back_event(event):
			_go_back()
			viewport.set_input_as_handled()
			return
		if _is_menu_accept_event(event) or _is_menu_down_event(event):
			_focus_first_button()
			viewport.set_input_as_handled()
			return
		if _is_menu_up_event(event):
			_focus_last_button()
			viewport.set_input_as_handled()
			return
		return

	if _is_menu_up_event(event):
		_move_focus(focus_owner, Side.SIDE_TOP)
		viewport.set_input_as_handled()
		return
	if _is_menu_down_event(event):
		_move_focus(focus_owner, Side.SIDE_BOTTOM)
		viewport.set_input_as_handled()
		return
	if _current_screen == "setup" and _is_menu_left_event(event):
		if _cycle_focused_setup_row(-1):
			viewport.set_input_as_handled()
			return
	if _current_screen == "setup" and _is_menu_right_event(event):
		if _cycle_focused_setup_row(1):
			viewport.set_input_as_handled()
			return
	if _is_menu_accept_event(event):
		if focus_owner is Button and not (focus_owner as Button).disabled:
			(focus_owner as Button).pressed.emit()
			viewport.set_input_as_handled()
			return
	if _is_menu_back_event(event):
		if _go_back():
			viewport.set_input_as_handled()
			return


func _build_title_scene() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.018, 0.026, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45, 1.0)
	env.ambient_light_energy = 1.15
	world.environment = env
	add_child(world)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.0, 7.5)
	_camera.fov = 62.0
	_camera.current = true
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.35, 0.0), Vector3.UP)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-30.0, -35.0, 0.0)
	key_light.light_color = Color(1.0, 0.75, 0.42, 1.0)
	key_light.light_energy = 3.2
	add_child(key_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-12.0, 145.0, 0.0)
	rim_light.light_color = Color(0.25, 0.55, 1.0, 1.0)
	rim_light.light_energy = 2.0
	add_child(rim_light)

	var text_mesh := TextMesh.new()
	text_mesh.text = "LAND CARRIER"
	text_mesh.font = TITLE_FONT
	text_mesh.font_size = 96
	text_mesh.depth = 0.45
	text_mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.92, 0.68, 0.16, 1.0)
	material.metallic = 0.35
	material.roughness = 0.28

	_title_mesh = MeshInstance3D.new()
	_title_mesh.mesh = text_mesh
	_title_mesh.material_override = material
	_title_mesh.position = Vector3(0.0, 1.15, 0.0)
	add_child(_title_mesh)
	_build_carrier_preview()


func _build_carrier_preview() -> void:
	_preview_root = Node3D.new()
	_preview_root.name = "CarrierPreview"
	_preview_root.position = Vector3(18.0, -18.0, 0.0)
	_preview_root.scale = Vector3.ONE
	_preview_root.rotation_degrees = Vector3(-4.0, -35.0, 0.0)
	_preview_root.visible = false
	add_child(_preview_root)

	_preview_model = CARRIER_PREVIEW_SCENE.instantiate()
	_preview_root.add_child(_preview_model)
	if _preview_model is Node3D:
		var model := _preview_model as Node3D
		model.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_add_preview_light_rig()


func _add_preview_light_rig() -> void:
	var front_fill := OmniLight3D.new()
	front_fill.name = "PreviewFrontFill"
	front_fill.position = Vector3(18.0, 32.0, 90.0)
	front_fill.light_color = Color(0.95, 0.98, 1.0, 1.0)
	front_fill.light_energy = 180.0
	front_fill.omni_range = 260.0
	front_fill.shadow_enabled = false
	add_child(front_fill)

	var top_key := OmniLight3D.new()
	top_key.name = "PreviewTopKey"
	top_key.position = Vector3(-70.0, 90.0, 35.0)
	top_key.light_color = Color(1.0, 0.88, 0.62, 1.0)
	top_key.light_energy = 240.0
	top_key.omni_range = 300.0
	top_key.shadow_enabled = false
	add_child(top_key)

	var side_rim := OmniLight3D.new()
	side_rim.name = "PreviewSideRim"
	side_rim.position = Vector3(95.0, 38.0, -70.0)
	side_rim.light_color = Color(0.45, 0.68, 1.0, 1.0)
	side_rim.light_energy = 180.0
	side_rim.omni_range = 280.0
	side_rim.shadow_enabled = false
	add_child(side_rim)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_ui_root = Control.new()
	_ui_root.name = "ScaledUIRoot"
	_ui_root.size = BASE_UI_SIZE
	layer.add_child(_ui_root)

	_message_label = Label.new()
	_message_label.position = Vector2(110.0, 645.0)
	_message_label.size = Vector2(900.0, 28.0)
	_message_label.add_theme_font_override("font", MENU_FONT)
	_message_label.add_theme_font_size_override("font_size", 18)
	_message_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.54))
	_ui_root.add_child(_message_label)

	_main_panel = Control.new()
	_main_panel.position = Vector2(110.0, 120.0)
	_main_panel.size = Vector2(520.0, 330.0)
	_ui_root.add_child(_main_panel)
	_build_main_menu(_main_panel)

	_setup_panel = Control.new()
	_setup_panel.position = Vector2(80.0, 40.0)
	_setup_panel.size = Vector2(520.0, 510.0)
	_ui_root.add_child(_setup_panel)
	_build_setup_menu(_setup_panel)


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
	ui_scale *= _resolution_ui_scale_compensation(viewport_size)
	_ui_root.size = BASE_UI_SIZE
	_ui_root.scale = Vector2(ui_scale, ui_scale)
	_ui_root.position = Vector2.ZERO


func _resolution_ui_scale_compensation(viewport_size: Vector2) -> float:
	var screen_size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	if screen_size.x <= 0 or screen_size.y <= 0:
		return 1.0
	var logical_to_physical := minf(
		viewport_size.x / float(screen_size.x),
		viewport_size.y / float(screen_size.y)
	)
	if logical_to_physical >= 0.98:
		return 1.0
	return clampf(logical_to_physical, 0.55, 1.0)


func _build_main_menu(parent: Control) -> void:
	var entries := [
		["CONTINUE", Callable(self, "_continue_game")],
		["NEW GAME", Callable(self, "_show_setup_menu")],
		["CODEX", Callable(self, "_show_codex_stub")],
		["OPTIONS", Callable(self, "_show_options_menu")],
		["QUIT", Callable(self, "_quit_game")],
	]
	for i in range(entries.size()):
		var btn := _make_menu_button(str(entries[i][0]), Vector2(0.0, i * 62.0), 470.0)
		btn.pressed.connect(entries[i][1] as Callable)
		if i == 0:
			btn.disabled = true
		parent.add_child(btn)


func _build_setup_menu(parent: Control) -> void:
	var title := _make_label("NEW GAME", Vector2.ZERO, 38, Color.WHITE)
	parent.add_child(title)

	var name_label := _make_label("CARRIER NAME", Vector2(0.0, 70.0), 20, Color(1.0, 1.0, 1.0, 0.66))
	parent.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.text = DEFAULT_CARRIER_NAME
	_name_edit.position = Vector2(0.0, 100.0)
	_name_edit.size = Vector2(500.0, 44.0)
	_name_edit.max_length = 32
	_name_edit.add_theme_font_override("font", MENU_FONT)
	_name_edit.add_theme_font_size_override("font_size", 24)
	parent.add_child(_name_edit)

	parent.add_child(_make_label("PRIMARY", Vector2(0.0, 165.0), 20, Color(1.0, 1.0, 1.0, 0.66)))
	_primary_value_button = _build_cycle_row(parent, Vector2(0.0, 196.0), Callable(self, "_change_primary"))

	parent.add_child(_make_label("SECONDARY", Vector2(0.0, 250.0), 20, Color(1.0, 1.0, 1.0, 0.66)))
	_secondary_value_button = _build_cycle_row(parent, Vector2(0.0, 281.0), Callable(self, "_change_secondary"))

	parent.add_child(_make_label("PATTERN", Vector2(0.0, 335.0), 20, Color(1.0, 1.0, 1.0, 0.66)))
	_pattern_value_button = _build_cycle_row(parent, Vector2(0.0, 366.0), Callable(self, "_change_pattern"))

	var start_btn := _make_menu_button("START", Vector2(0.0, 445.0), 220.0)
	start_btn.pressed.connect(_start_new_game)
	parent.add_child(start_btn)

	var back_btn := _make_small_button("< BACK", Vector2(260.0, 455.0), 180.0)
	back_btn.pressed.connect(_show_main_menu)
	parent.add_child(back_btn)
	_refresh_setup_buttons()


func _build_cycle_row(parent: Control, pos: Vector2, callback: Callable) -> Button:
	var left_btn := _make_arrow_button("<", pos)
	left_btn.pressed.connect(callback.bind(-1))
	parent.add_child(left_btn)

	var value_btn := _make_value_button(pos + Vector2(54.0, 0.0), 320.0)
	value_btn.pressed.connect(callback.bind(1))
	parent.add_child(value_btn)

	var right_btn := _make_arrow_button(">", pos + Vector2(388.0, 0.0))
	right_btn.pressed.connect(callback.bind(1))
	parent.add_child(right_btn)

	return value_btn


func _make_menu_button(text: String, pos: Vector2, width: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = Vector2(width, 58.0)
	btn.custom_minimum_size = Vector2(width, 58.0)
	btn.focus_mode = Control.FOCUS_ALL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, empty)
	btn.add_theme_font_override("font", MENU_FONT)
	btn.add_theme_font_size_override("font_size", 34)
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.60))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.20))
	return btn


func _make_small_button(text: String, pos: Vector2, width: float) -> Button:
	var btn := _make_menu_button(text, pos, width)
	btn.size = Vector2(width, 38.0)
	btn.custom_minimum_size = Vector2(width, 38.0)
	btn.add_theme_font_size_override("font_size", 22)
	return btn


func _make_arrow_button(text: String, pos: Vector2) -> Button:
	var btn := _make_small_button(text, pos, 42.0)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 30)
	return btn


func _make_value_button(pos: Vector2, width: float) -> Button:
	var btn := _make_small_button("", pos, width)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.focus_mode = Control.FOCUS_ALL
	return btn


func _make_label(text: String, pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_override("font", MENU_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _show_main_menu() -> void:
	_current_screen = "main"
	_main_panel.visible = true
	_setup_panel.visible = false
	if is_instance_valid(_title_mesh):
		_title_mesh.visible = true
	if is_instance_valid(_preview_root):
		_preview_root.visible = false
	_set_title_camera()
	_message_label.text = ""
	var first := _first_button(_main_panel)
	if first:
		first.grab_focus()


func _show_setup_menu() -> void:
	_current_screen = "setup"
	_main_panel.visible = false
	_setup_panel.visible = true
	if is_instance_valid(_title_mesh):
		_title_mesh.visible = false
	if is_instance_valid(_preview_root):
		_preview_root.visible = true
	_set_preview_camera()
	_message_label.text = ""
	_refresh_setup_buttons()
	_name_edit.grab_focus()


func _set_title_camera() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.position = Vector3(0.0, 1.0, 7.5)
	_camera.fov = 62.0
	_camera.look_at(Vector3(0.0, 0.35, 0.0), Vector3.UP)


func _set_preview_camera() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.position = Vector3(18.0, 42.0, 155.0)
	_camera.fov = 36.0
	_camera.look_at(Vector3(18.0, -12.0, 0.0), Vector3.UP)


func _continue_game() -> void:
	_message_label.text = "NO SAVE FOUND"


func _show_codex_stub() -> void:
	_message_label.text = "CODEX COMING SOON"


func _show_options_menu() -> void:
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if pause_menu == null or not pause_menu.has_method("_open"):
		_message_label.text = "OPTIONS NOT READY"
		return
	pause_menu.call("_open")
	if pause_menu.has_method("_show_screen"):
		pause_menu.call("_show_screen", "options")


func _quit_game() -> void:
	get_tree().quit()


func _change_primary(delta: int) -> void:
	_primary_index = _wrap_index(_primary_index + delta, _carrier_colors.size())
	_refresh_setup_buttons()


func _change_secondary(delta: int) -> void:
	_secondary_index = _wrap_index(_secondary_index + delta, _carrier_colors.size())
	_refresh_setup_buttons()


func _change_pattern(delta: int) -> void:
	_pattern_choice_index = _wrap_index(_pattern_choice_index + delta, PATTERN_NAMES.size())
	_refresh_setup_buttons()


func _refresh_setup_buttons() -> void:
	_refresh_color_value_button(_primary_value_button, _primary_index)
	_refresh_color_value_button(_secondary_value_button, _secondary_index)
	if _pattern_value_button != null:
		_pattern_value_button.text = PATTERN_NAMES[_pattern_choice_index]
		_apply_plain_value_style(_pattern_value_button)
	_apply_preview_livery()


func _refresh_color_value_button(button: Button, index: int) -> void:
	if button == null:
		return
	var color := _carrier_colors[index]
	button.text = _carrier_color_names[index]
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(1.0, 1.0, 1.0, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
	var readable := Color.BLACK if color.get_luminance() > 0.58 else Color.WHITE
	button.add_theme_color_override("font_color", readable)
	button.add_theme_color_override("font_hover_color", readable)
	button.add_theme_color_override("font_focus_color", readable)
	button.add_theme_color_override("font_pressed_color", readable.darkened(0.25))


func _apply_plain_value_style(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, empty)
	button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.74))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 0.68))


func _apply_preview_livery() -> void:
	if not is_instance_valid(_preview_root):
		return
	var livery := get_node_or_null("/root/Livery")
	if livery == null or not livery.has_method("set_player_livery") or not livery.has_method("apply"):
		return
	livery.call(
		"set_player_livery",
		_carrier_colors[_primary_index],
		_carrier_colors[_secondary_index],
		PATTERN_INDICES[_pattern_choice_index]
	)
	var added_carrier_group := false
	if not _preview_root.is_in_group("carrier"):
		_preview_root.add_to_group("carrier")
		added_carrier_group = true
	livery.call("apply", _preview_root)
	if added_carrier_group:
		_preview_root.remove_from_group("carrier")


func _wrap_index(value: int, size: int) -> int:
	if size <= 0:
		return 0
	return ((value % size) + size) % size


func _start_new_game() -> void:
	var session := get_node_or_null("/root/GameSession")
	if session == null or not session.has_method("configure_new_game"):
		_message_label.text = "GAME SESSION NOT READY"
		return
	session.call(
		"configure_new_game",
		_name_edit.text,
		_carrier_colors[_primary_index],
		_carrier_colors[_secondary_index],
		PATTERN_INDICES[_pattern_choice_index]
	)
	get_tree().change_scene_to_file(GAME_SCENE)


func _first_button(node: Node) -> Button:
	if node == null:
		return null
	if node is Button and not (node as Button).disabled:
		return node as Button
	for child in node.get_children():
		var found := _first_button(child)
		if found:
			return found
	return null


func _go_back() -> bool:
	if _current_screen == "setup":
		_show_main_menu()
		return true
	return false


func _cycle_focused_setup_row(delta: int) -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner := viewport.gui_get_focus_owner()
	if focus_owner == _primary_value_button:
		_change_primary(delta)
		return true
	if focus_owner == _secondary_value_button:
		_change_secondary(delta)
		return true
	if focus_owner == _pattern_value_button:
		_change_pattern(delta)
		return true
	return false


func _move_focus(focus_owner: Control, side: int) -> void:
	if focus_owner == null:
		_focus_first_button()
		return
	var next_focus := focus_owner.find_valid_focus_neighbor(side)
	if next_focus:
		next_focus.grab_focus()
		return

	var buttons: Array[Button] = _buttons_in_current_screen()
	if buttons.is_empty():
		return
	var idx := buttons.find(focus_owner as Button)
	if idx < 0:
		buttons[0].grab_focus()
		return
	var dir := -1 if side == Side.SIDE_TOP else 1
	var next_idx := (idx + dir + buttons.size()) % buttons.size()
	buttons[next_idx].grab_focus()


func _focus_first_button() -> Control:
	var buttons: Array[Button] = _buttons_in_current_screen()
	if buttons.is_empty():
		return null
	buttons[0].grab_focus()
	return buttons[0]


func _focus_last_button() -> Control:
	var buttons: Array[Button] = _buttons_in_current_screen()
	if buttons.is_empty():
		return null
	buttons[buttons.size() - 1].grab_focus()
	return buttons[buttons.size() - 1]


func _buttons_in_current_screen() -> Array[Button]:
	var out: Array[Button] = []
	var screen: Control = _current_screen_control()
	if screen == null:
		return out
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back() as Node
		if n is Button:
			var btn := n as Button
			if btn.visible and not btn.disabled and btn.focus_mode != Control.FOCUS_NONE:
				out.append(btn)
		for c in n.get_children():
			if c is Node:
				stack.append(c as Node)
	out.reverse()
	return out


func _current_screen_control() -> Control:
	if _current_screen == "main":
		return _main_panel
	if _current_screen == "setup":
		return _setup_panel
	return null


func _is_menu_up_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		return key == KEY_UP or key == KEY_W
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_DPAD_UP
	return false


func _is_menu_down_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_down", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		return key == KEY_DOWN or key == KEY_S
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_DPAD_DOWN
	return false


func _is_menu_left_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_left", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		return key == KEY_LEFT or key == KEY_A
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_DPAD_LEFT
	return false


func _is_menu_right_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_right", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		return key == KEY_RIGHT or key == KEY_D
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_DPAD_RIGHT
	return false


func _is_menu_accept_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		return key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE
	if event is InputEventJoypadButton and event.pressed:
		return (event as InputEventJoypadButton).button_index == PAD_BUTTON_A
	return false


func _is_menu_back_event(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel", false):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return (event as InputEventKey).physical_keycode == KEY_ESCAPE
	if event is InputEventJoypadButton and event.pressed:
		var button_index := (event as InputEventJoypadButton).button_index
		return button_index == PAD_BUTTON_B or button_index == PAD_BUTTON_BACK
	return false
