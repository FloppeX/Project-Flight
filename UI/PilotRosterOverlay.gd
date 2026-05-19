extends CanvasLayer

const PIXEL_FONT: FontFile = preload("res://UI/Pixel.ttf")

const PANEL_MARGIN_PX: float = 24.0
const HEADER_HEIGHT_PX: float = 62.0
const ROW_HEIGHT_PX: float = 32.0
const TABLE_PAD_PX: float = 18.0

const VECTOR_TEXT_COLOR: Color = Color(0.58, 1.0, 0.64, 1.0)
const VECTOR_STATUS_COLOR: Color = Color(0.84, 1.0, 0.86, 1.0)
const VECTOR_PANEL_BG: Color = Color(0.02, 0.05, 0.03, 0.97)
const VECTOR_ROW_BG: Color = Color(0.01, 0.04, 0.02, 0.88)
const VECTOR_ROW_ALT_BG: Color = Color(0.02, 0.07, 0.03, 0.88)
const VECTOR_BORDER_COLOR: Color = Color(0.24, 0.92, 0.42, 0.92)
const VECTOR_AMBER_COLOR: Color = Color(1.0, 0.78, 0.28, 1.0)
const VECTOR_DIM_COLOR: Color = Color(0.38, 0.54, 0.42, 0.9)

const COLUMNS: Array[Dictionary] = [
	{"title": "RANK", "width": 72.0},
	{"title": "PILOT", "width": 176.0},
	{"title": "ORIGIN", "width": 136.0},
	{"title": "LANGUAGE", "width": 150.0},
	{"title": "SKILL", "width": 116.0},
	{"title": "XP", "width": 78.0},
	{"title": "AIR", "width": 62.0},
	{"title": "GND", "width": 62.0},
	{"title": "ACE", "width": 116.0},
	{"title": "SORT", "width": 66.0},
	{"title": "TIME", "width": 86.0},
	{"title": "STATUS", "width": 142.0},
	{"title": "TEMP", "width": 112.0},
]

var _root: Control
var _backdrop: ColorRect
var _panel: ColorRect
var _header_title: Label
var _header_subtitle: Label
var _scroll: ScrollContainer
var _table: VBoxContainer
var _footer: Label
var _refresh_timer_s: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 191
	set_process(true)
	set_process_input(true)
	_ensure_input_action()
	_build_ui()
	_set_open(false)

func _process(delta: float) -> void:
	if _root == null or not _root.visible:
		return
	_refresh_timer_s -= delta
	if _refresh_timer_s <= 0.0:
		_refresh_table()
		_refresh_timer_s = 0.5

func _input(event: InputEvent) -> void:
	var pressed := event.is_action_pressed("pilot_roster_toggle")
	if not pressed and event is InputEventKey:
		var key_event := event as InputEventKey
		pressed = key_event.pressed and not key_event.echo and key_event.keycode == KEY_COMMA
	if not pressed:
		return
	_set_open(not _root.visible)
	get_viewport().set_input_as_handled()

func _ensure_input_action() -> void:
	if not InputMap.has_action("pilot_roster_toggle"):
		InputMap.add_action("pilot_roster_toggle")
		var key_event := InputEventKey.new()
		key_event.physical_keycode = KEY_COMMA
		key_event.keycode = KEY_COMMA
		InputMap.action_add_event("pilot_roster_toggle", key_event)

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.01, 0.0, 0.94)
	_root.add_child(_backdrop)

	_panel = _make_panel(VECTOR_PANEL_BG)
	_root.add_child(_panel)

	_header_title = _make_label("CARRIER PILOT ROSTER", 28, VECTOR_TEXT_COLOR)
	_panel.add_child(_header_title)
	_header_subtitle = _make_label("PERSONNEL STATUS // SORTED BY COMBAT RECORD AND EXPERIENCE", 12, VECTOR_STATUS_COLOR)
	_panel.add_child(_header_subtitle)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(_scroll)

	_table = VBoxContainer.new()
	_table.add_theme_constant_override("separation", 3)
	_table.custom_minimum_size = Vector2(_table_width(), 0.0)
	_scroll.add_child(_table)

	_footer = _make_label("COMMA: CLOSE", 12, VECTOR_DIM_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	_panel.add_child(_footer)

	_root.resized.connect(_layout_ui)
	_layout_ui()

func _layout_ui() -> void:
	if _root == null:
		return
	var size := _root.size
	var panel_pos := Vector2(PANEL_MARGIN_PX, PANEL_MARGIN_PX)
	var panel_size := Vector2(size.x - PANEL_MARGIN_PX * 2.0, size.y - PANEL_MARGIN_PX * 2.0)
	_panel.position = panel_pos
	_panel.size = panel_size
	_header_title.position = Vector2(18.0, 10.0)
	_header_title.size = Vector2(panel_size.x - 36.0, 30.0)
	_header_subtitle.position = Vector2(18.0, 40.0)
	_header_subtitle.size = Vector2(panel_size.x - 36.0, 16.0)
	_scroll.position = Vector2(TABLE_PAD_PX, HEADER_HEIGHT_PX + 14.0)
	_scroll.size = Vector2(panel_size.x - TABLE_PAD_PX * 2.0, panel_size.y - HEADER_HEIGHT_PX - 50.0)
	_footer.position = Vector2(TABLE_PAD_PX, panel_size.y - 26.0)
	_footer.size = Vector2(panel_size.x - TABLE_PAD_PX * 2.0, 18.0)

func _set_open(is_open: bool) -> void:
	if _root == null:
		return
	_root.visible = is_open
	if is_open:
		_refresh_table()
		_refresh_timer_s = 0.5

func _refresh_table() -> void:
	if _table == null:
		return
	_clear_children(_table)
	_table.add_child(_make_row(_header_values(), true, false))
	var roster := _get_sorted_roster()
	if roster.is_empty():
		var empty_row := _make_row(["", "NO PILOTS AVAILABLE", "", "", "", "", "", "", "", "", "", "", ""], false, false)
		_table.add_child(empty_row)
		return
	for i in range(roster.size()):
		_table.add_child(_make_row(_pilot_values(roster[i]), false, i % 2 == 1))

func _get_sorted_roster() -> Array[Dictionary]:
	if PilotRoster == null or not is_instance_valid(PilotRoster):
		return []
	if not PilotRoster.has_method("get_carrier_roster"):
		return []
	var roster: Array[Dictionary] = PilotRoster.get_carrier_roster()
	roster.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _pilot_sort_score(a) > _pilot_sort_score(b)
	)
	return roster

func _pilot_sort_score(pilot: Dictionary) -> float:
	var skill_score: float = {
		"ELITE": 5.0,
		"VETERAN": 4.0,
		"EXPERIENCED": 3.0,
		"ROOKIE": 2.0,
		"RECRUIT": 1.0,
	}.get(str(pilot.get("skill", "")).to_upper(), 0.0)
	return skill_score * 100000.0 \
		+ float(pilot.get("air_kills", 0.0)) * 2500.0 \
		+ float(pilot.get("ground_kills", 0.0)) * 900.0 \
		+ float(pilot.get("experience_points", 0)) \
		+ float(pilot.get("mission_time_s", 0.0)) * 0.01

func _header_values() -> Array[String]:
	var values: Array[String] = []
	for column in COLUMNS:
		values.append(str(column.get("title", "")))
	return values

func _pilot_values(pilot: Dictionary) -> Array[String]:
	var status := str(pilot.get("status", "available")).to_upper()
	var callsign := str(pilot.get("assigned_callsign", ""))
	if callsign != "":
		status = "ASSIGNED " + callsign.to_upper()
	return [
		str(pilot.get("rank", "")),
		str(pilot.get("name", "")),
		str(pilot.get("national_origin", "")),
		str(pilot.get("language", "")),
		_pretty_skill(str(pilot.get("skill", ""))),
		str(int(pilot.get("experience_points", 0))),
		_format_kills(float(pilot.get("air_kills", 0.0))),
		_format_kills(float(pilot.get("ground_kills", 0.0))),
		_format_ace(str(pilot.get("ace_status", ""))),
		str(int(pilot.get("sorties_flown", 0))),
		_format_time(float(pilot.get("mission_time_s", 0.0))),
		status,
		str(pilot.get("temperament", "")).to_upper(),
	]

func _make_row(values: Array[String], is_header: bool, alternate: bool) -> Control:
	var row := ColorRect.new()
	row.color = Color(0.03, 0.10, 0.05, 0.96) if is_header else (VECTOR_ROW_ALT_BG if alternate else VECTOR_ROW_BG)
	row.custom_minimum_size = Vector2(_table_width(), ROW_HEIGHT_PX)
	var x := 0.0
	for i in range(COLUMNS.size()):
		var column: Dictionary = COLUMNS[i]
		var label := _make_label(values[i] if i < values.size() else "", 13 if is_header else 12, VECTOR_AMBER_COLOR if is_header else VECTOR_TEXT_COLOR)
		label.position = Vector2(x + 8.0, 0.0)
		label.size = Vector2(float(column.get("width", 80.0)) - 12.0, ROW_HEIGHT_PX)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		row.add_child(label)
		x += float(column.get("width", 80.0))
	return row

func _make_panel(color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = color
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = VECTOR_BORDER_COLOR
	style.set_border_width_all(2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_label(text: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _table_width() -> float:
	var width := 0.0
	for column in COLUMNS:
		width += float(column.get("width", 80.0))
	return width

func _format_kills(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value

func _format_ace(status: String) -> String:
	return status.to_upper() if status != "" else "-"

func _format_time(seconds: float) -> String:
	var total_minutes := int(floor(maxf(seconds, 0.0) / 60.0))
	var hours := total_minutes / 60
	var minutes := total_minutes % 60
	return "%02d:%02d" % [hours, minutes]

func _pretty_skill(skill: String) -> String:
	return skill.replace("_", " ").to_upper()

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
