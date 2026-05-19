extends CanvasLayer
## Pause menu autoload.
## Opened by the pause_game action (Select/Back on gamepad, P on keyboard).
## Opening pauses the scene tree; closing unpauses it.
## Sub-screens: Controls reference, Codex stub.

const MENU_FONT: FontFile = preload("res://UI/Orbitron-VariableFont_wght.ttf")

const FONT_NORMAL   := 62
const FONT_SELECTED := 78
const MARGIN_X      := 150.0
const MARGIN_Y      := 200.0
const ITEM_STEP     := 96.0

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

var _screens: Dictionary = {}
var _current_screen: String = ""


func _ready() -> void:
	layer = 98
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game", false):
		if not visible:
			_open()
		else:
			_close()
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if _handle_pause_navigation_input(event):
		get_viewport().set_input_as_handled()


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
	_screens["main"]     = _build_main_screen()
	_screens["controls"] = _build_controls_screen()
	_screens["codex"]    = _build_codex_screen()

	for s: Control in _screens.values():
		s.visible = false
		add_child(s)


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


func _build_controls_screen() -> Control:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var overlay = ColorRect.new()
	overlay.color = COLOR_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	var vp = DisplayServer.screen_get_size()
	var panel_w = mini(680, vp.x - 160)
	var panel_h = vp.y - 140

	var panel = ColorRect.new()
	panel.color = COLOR_PANEL
	panel.position = Vector2(MARGIN_X - 20, 60)
	panel.size = Vector2(panel_w, panel_h)
	root.add_child(panel)

	var back = _make_back_button(Vector2(MARGIN_X, 76))
	back.pressed.connect(func(): _show_screen("main"))
	root.add_child(back)

	var title = Label.new()
	title.text = "CONTROLS"
	title.position = Vector2(MARGIN_X, 108)
	title.add_theme_color_override("font_color", COLOR_WHITE)
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 40)
	root.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(MARGIN_X, 188)
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
	panel.position = Vector2(MARGIN_X - 20, 60)
	panel.size = Vector2(560, 320)
	root.add_child(panel)

	var back = _make_back_button(Vector2(MARGIN_X, 76))
	back.pressed.connect(func(): _show_screen("main"))
	root.add_child(back)

	var title = Label.new()
	title.text = "CODEX"
	title.position = Vector2(MARGIN_X, 108)
	title.add_theme_color_override("font_color", COLOR_WHITE)
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 40)
	root.add_child(title)

	var body = Label.new()
	body.text = "COMING SOON.\n\nVEHICLE AND WEAPON REFERENCE ENTRIES\nWILL APPEAR HERE."
	body.position = Vector2(MARGIN_X, 196)
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
[color=#{d}]M[/color]                WORLD MAP
[color=#{d}],[/color]                PILOT ROSTER
[color=#{d}]P / SELECT[/color]       PAUSE / THIS MENU
""".format({"w": w, "d": d})


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_restart() -> void:
	_close()
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Pause navigation input (keyboard + gamepad)
# ---------------------------------------------------------------------------

func _handle_pause_navigation_input(event: InputEvent) -> bool:
	if _current_screen == "":
		return false

	var focus_owner: Control = get_viewport().gui_get_focus_owner()
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
