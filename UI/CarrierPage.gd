class_name CarrierPage
extends Control

## Interactive presentation mockup for the Carrier command tab.
##
## All readiness, stores, capacity, alert, and doctrine values below are fictional
## concept data. This page does not read or mutate gameplay carrier state.

const HEADLINE_FONT: FontFile = preload("res://UI/Fonts/ArchivoNarrow-Variable.ttf")
const DATA_FONT: FontFile = preload("res://UI/Fonts/JetBrainsMono-Variable.ttf")
const WIREFRAME_VIEW: Script = preload("res://UI/CarrierWireframeView.gd")

const TEXT_COLOR := Color("e5e2e1")
const STATUS_COLOR := Color("c4c7c7")
const BORDER_COLOR := Color("434747")
const CYAN_COLOR := Color("76c7c7")
const BRIGHT_CYAN := Color("b9ffff")
const AMBER_COLOR := Color("ffb000")
const DIM_COLOR := Color("7d8282")
const PAGE_BG := Color("0e0e0e")
const PANEL_BG := Color("141313")
const PANEL_ALT_BG := Color("1c1b1b")
const SELECTED_BG := Color("202828")
const WARNING_BG := Color("332817")

const MOCK_SYSTEM_ORDER: Array[String] = [
	"flight", "hangar", "elevators", "island", "vehicle_bay",
	"replicator", "habitation", "defenses", "drive", "stores",
]

const MOCK_SYSTEMS: Dictionary = {
	"flight": {
		"label": "FLIGHT DECK", "region": "flight_deck", "value": "92%",
		"state": "READY // DECK CLEAR", "warning": false,
		"copy": "Launch and recovery systems are available. One returning aircraft is waiting for the recovery corridor.",
		"rows": [["Hangar", "9 / 12"], ["Launch queue", "2"], ["Recovery queue", "1"], ["Deck state", "IDLE"]],
		"event": "Terrain and turn constraints are clear. Routine deck handling remains autonomous.",
	},
	"hangar": {
		"label": "HANGAR", "region": "hangar", "value": "9 / 12",
		"state": "READY // THREE BERTHS FREE", "warning": false,
		"copy": "Aircraft storage, servicing lanes, and autonomous deck-transfer routing are available.",
		"rows": [["Aircraft stored", "9"], ["Free berths", "3"], ["Service queue", "2"], ["Transfer lanes", "CLEAR"]],
		"event": "No hangar exception requires command attention.",
	},
	"elevators": {
		"label": "ELEVATORS", "region": "elevators", "value": "2 / 2",
		"state": "READY // BOTH LIFTS AVAILABLE", "warning": false,
		"copy": "Forward and recovery elevators are available to the autonomous deck scheduler.",
		"rows": [["Forward lift", "READY"], ["Recovery lift", "READY"], ["Queued transfers", "1"], ["Interlocks", "CLEAR"]],
		"event": "The scheduler will hold conflicting launch or recovery movements automatically.",
	},
	"island": {
		"label": "ISLAND / BRIDGE", "region": "island", "value": "ONLINE",
		"state": "ONLINE // FULL COVERAGE", "warning": false,
		"copy": "Carrier command, local sensors, navigation, and tactical uplink are operating normally.",
		"rows": [["Radar state", "ACTIVE"], ["Tracked contacts", "0"], ["Tactical uplink", "STABLE"], ["Navigation", "ROUTE ACTIVE"]],
		"event": "No bridge or sensor exception requires command attention.",
	},
	"vehicle_bay": {
		"label": "VEHICLE BAY", "region": "vehicle_bay", "value": "12 / 16",
		"state": "READY // DEPLOYMENT CAPACITY AVAILABLE", "warning": false,
		"copy": "Ground vehicles are secured and four storage positions remain available for retrieval.",
		"rows": [["Vehicles stored", "12"], ["Free positions", "4"], ["Deployment queue", "1"], ["Ramp state", "CLOSED"]],
		"event": "Routine deployment and retrieval remain under platoon automation.",
	},
	"replicator": {
		"label": "REPLICATOR", "region": "replicator", "value": "ACTIVE",
		"state": "ACTIVE // TWO ORDERS QUEUED", "warning": false,
		"copy": "Fabrication capacity is available. Detailed recipes and scheduling belong on the Replicator tab.",
		"rows": [["Fabricator", "ONLINE"], ["Active orders", "1"], ["Queued orders", "2"], ["Output route", "STORES"]],
		"event": "Carrier status reports only readiness-affecting shortages and exceptions.",
	},
	"habitation": {
		"label": "HABITATION", "region": "habitation", "value": "NOMINAL",
		"state": "NOMINAL // CREW SUPPORT STABLE", "warning": false,
		"copy": "Life support, crew spaces, medical capacity, and general services are within the mock operating envelope.",
		"rows": [["Life support", "NOMINAL"], ["Medical beds", "6 FREE"], ["Crew alerts", "NONE"], ["Restricted zones", "0"]],
		"event": "Routine crew allocation remains automatic unless an exception is raised.",
	},
	"defenses": {
		"label": "DEFENSES", "region": "defenses", "value": "3 / 4",
		"state": "DEGRADED // COVERAGE REDUCED", "warning": true,
		"copy": "Starboard-forward mount is unavailable. Remaining mounts retain autonomous engagement authority.",
		"rows": [["Mounts ready", "3 / 4"], ["Tracked contacts", "0"], ["Engagement range", "1,400 m"], ["Ammunition", "NOT MODELED"]],
		"event": "Mount isolated. Mock auto-repair is waiting for 80 units of plasteel.",
	},
	"drive": {
		"label": "DRIVE / TREADS", "region": "drive", "value": "96%",
		"state": "NOMINAL // ROUTE ACTIVE", "warning": false,
		"copy": "Carrier mobility is unrestricted and the current tactical route remains valid.",
		"rows": [["Tread groups", "6 / 6"], ["Speed", "8.4 m/s"], ["Route state", "ACTIVE"], ["Safe speed", "10.0 m/s"]],
		"event": "Launch and recovery constraints may temporarily slow or hold the carrier.",
	},
	"stores": {
		"label": "STORES", "region": "stores", "value": "PL LOW",
		"state": "WATCH // PLASTEEL BELOW RESERVE", "warning": true,
		"copy": "Corium supply is healthy. Plasteel is below the mock repair reserve for the degraded defense mount.",
		"rows": [["Corium", "1,000"], ["Plasteel", "180"], ["Repair reserve", "260"], ["Forecast", "6.2 h"]],
		"event": "Detailed production scheduling remains on the Replicator tab.",
	},
}

const REPAIR_PRIORITIES: Array[String] = ["FLIGHT OPS FIRST", "DEFENSES FIRST", "MOBILITY FIRST"]
const DEFENSE_POSTURES: Array[String] = ["AUTONOMOUS", "CONSERVE", "MAX COVERAGE"]

var _wireframe_view: Control
var _system_buttons: Dictionary = {}
var _selected_system_id: String = "defenses"
var _repair_priority_index: int = 0
var _defense_posture_index: int = 0
var _schematic_selection_label: Label
var _detail_category: Label
var _detail_title: Label
var _detail_state: Label
var _detail_copy: Label
var _detail_rows: VBoxContainer
var _event_panel: Panel
var _event_copy: Label
var _repair_priority_button: Button
var _defense_posture_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_select_system(_selected_system_id)


func set_console_visible(value: bool) -> void:
	visible = value
	if _wireframe_view != null:
		_wireframe_view.call("set_console_visible", value)
	if value:
		_apply_selection_to_schematic()


func get_debug_snapshot() -> Dictionary:
	var wireframe_snapshot: Dictionary = {}
	if _wireframe_view != null:
		wireframe_snapshot = _wireframe_view.call("get_debug_snapshot")
	return {
		"kind": "carrier",
		"mode": "interactive_mockup",
		"mock_data": true,
		"telemetry_connected": false,
		"system_count": MOCK_SYSTEM_ORDER.size(),
		"selected_system": _selected_system_id,
		"repair_priority": REPAIR_PRIORITIES[_repair_priority_index],
		"defense_posture": DEFENSE_POSTURES[_defense_posture_index],
		"wireframe": wireframe_snapshot,
	}


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = PAGE_BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var page_margin := MarginContainer.new()
	page_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_margin.add_theme_constant_override("margin_left", 24)
	page_margin.add_theme_constant_override("margin_top", 14)
	page_margin.add_theme_constant_override("margin_right", 24)
	page_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(page_margin)
	var page_column := VBoxContainer.new()
	page_column.add_theme_constant_override("separation", 8)
	page_margin.add_child(page_column)
	_build_header(page_column)
	_build_alert_strip(page_column)
	_build_content(page_column)
	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 18.0
	page_column.add_child(footer)
	var footer_left := _make_label("INTERACTIVE MOCKUP // NO LIVE SIMULATION STATE IS READ OR WRITTEN", 9, AMBER_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	footer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_left)
	footer.add_child(_make_label("CYAN NOMINAL  //  AMBER DEGRADED  //  SELECT A SYSTEM FOR DETAILS", 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT))


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 58.0
	header.add_theme_constant_override("separation", 18)
	parent.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 0)
	header.add_child(heading)
	heading.add_child(_make_label("CV-01 // RESOLUTE", 28, TEXT_COLOR))
	heading.add_child(_make_label("CARRIER STATUS // INTERACTIVE MOCK DATA", 11, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	var condition := VBoxContainer.new()
	condition.add_theme_constant_override("separation", 0)
	header.add_child(condition)
	condition.add_child(_make_label("● MOCK TELEMETRY", 9, AMBER_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT))
	condition.add_child(_make_label("CONDITION AMBER // 2 MOCK EXCEPTIONS", 13, AMBER_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT))


func _build_alert_strip(parent: VBoxContainer) -> void:
	var alert_panel := Panel.new()
	alert_panel.custom_minimum_size.y = 38.0
	alert_panel.add_theme_stylebox_override("panel", _make_style(WARNING_BG, AMBER_COLOR, 1, 12.0))
	parent.add_child(alert_panel)
	var margin := _make_margin(4, 12)
	alert_panel.add_child(margin)
	var row := HBoxContainer.new()
	margin.add_child(row)
	var alert := _make_label("ACTION REQUIRED // STARBOARD-FORWARD DEFENSE MOUNT DEGRADED", 10, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	alert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alert.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(alert)
	var response := _make_label("MOCK AUTO-REPAIR WAITING ON PLASTEEL", 10, AMBER_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	response.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(response)


func _build_content(parent: VBoxContainer) -> void:
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size.y = 650.0
	content.add_theme_constant_override("separation", 12)
	parent.add_child(content)
	_build_schematic_panel(content)
	_build_detail_panel(content)


func _build_schematic_panel(parent: HBoxContainer) -> void:
	var panel := Panel.new()
	panel.name = "CarrierSchematicPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 2.35
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_BG, BORDER_COLOR, 1))
	parent.add_child(panel)
	var margin := _make_margin(10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var schematic_header := HBoxContainer.new()
	schematic_header.custom_minimum_size.y = 24.0
	column.add_child(schematic_header)
	var title := _make_label("SECTIONAL STATUS", 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	schematic_header.add_child(title)
	_schematic_selection_label = _make_label("", 9, CYAN_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	schematic_header.add_child(_schematic_selection_label)
	var viewport_frame := Panel.new()
	viewport_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_frame.custom_minimum_size.y = 390.0
	viewport_frame.add_theme_stylebox_override("panel", _make_style(Color("090d0d"), BORDER_COLOR, 1))
	column.add_child(viewport_frame)
	_wireframe_view = WIREFRAME_VIEW.new() as Control
	_wireframe_view.name = "CarrierWireframeView"
	_wireframe_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wireframe_view.offset_left = 1.0
	_wireframe_view.offset_top = 1.0
	_wireframe_view.offset_right = -1.0
	_wireframe_view.offset_bottom = -1.0
	_wireframe_view.connect("model_ready", _on_wireframe_model_ready)
	viewport_frame.add_child(_wireframe_view)
	var selection_header := HBoxContainer.new()
	selection_header.custom_minimum_size.y = 18.0
	column.add_child(selection_header)
	var selection_title := _make_label("SUBSYSTEM MAP", 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	selection_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_header.add_child(selection_title)
	selection_header.add_child(_make_label("SELECT TO HIGHLIGHT", 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT))
	var system_grid := GridContainer.new()
	system_grid.columns = 5
	system_grid.add_theme_constant_override("h_separation", 5)
	system_grid.add_theme_constant_override("v_separation", 5)
	column.add_child(system_grid)
	for system_id: String in MOCK_SYSTEM_ORDER:
		var button := _make_system_button(system_id)
		button.pressed.connect(_select_system.bind(system_id))
		system_grid.add_child(button)
		_system_buttons[system_id] = button
	var summaries := HBoxContainer.new()
	summaries.custom_minimum_size.y = 102.0
	summaries.add_theme_constant_override("separation", 5)
	column.add_child(summaries)
	_add_summary_card(summaries, "INTEGRITY", "HULL 94%", ["5 sections online", "Fire / breach: none"], CYAN_COLOR)
	_add_summary_card(summaries, "STORES", "CO 1,000 // PL 180", ["Plasteel reserve low", "Forecast: 6.2 h"], AMBER_COLOR)
	_add_summary_card(summaries, "CAPACITY", "9 / 12 AIR", ["Vehicles 12 / 16", "Recovery queue 1"], TEXT_COLOR)
	_add_summary_card(summaries, "DEFENSES", "3 / 4 READY", ["Authority: autonomous", "Ammunition not modeled"], AMBER_COLOR)


func _build_detail_panel(parent: HBoxContainer) -> void:
	var panel := Panel.new()
	panel.name = "SelectedSystemDetail"
	panel.custom_minimum_size.x = 355.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_ALT_BG, BORDER_COLOR, 1))
	parent.add_child(panel)
	var margin := _make_margin(16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	_detail_category = _make_label("", 9, AMBER_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	column.add_child(_detail_category)
	_detail_title = _make_label("", 22, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	column.add_child(_detail_title)
	_detail_state = _make_label("", 10, AMBER_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	column.add_child(_detail_state)
	_detail_copy = _make_label("", 11, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_detail_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_copy.custom_minimum_size.y = 56.0
	column.add_child(_detail_copy)
	_add_rule(column)
	column.add_child(_make_label("MOCK READOUT", 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	_detail_rows = VBoxContainer.new()
	_detail_rows.add_theme_constant_override("separation", 4)
	column.add_child(_detail_rows)
	_add_rule(column)
	_event_panel = Panel.new()
	_event_panel.custom_minimum_size.y = 82.0
	column.add_child(_event_panel)
	var event_margin := _make_margin(10)
	_event_panel.add_child(event_margin)
	var event_column := VBoxContainer.new()
	event_margin.add_child(event_column)
	event_column.add_child(_make_label("00:41 AGO // AUTOMATED MOCK REPORT", 8, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	_event_copy = _make_label("", 10, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_event_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_column.add_child(_event_copy)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	column.add_child(_make_label("COMMAND DOCTRINE // MOCK CONTROLS", 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	_repair_priority_button = _make_doctrine_button()
	_repair_priority_button.pressed.connect(_cycle_repair_priority)
	column.add_child(_repair_priority_button)
	_defense_posture_button = _make_doctrine_button()
	_defense_posture_button.pressed.connect(_cycle_defense_posture)
	column.add_child(_defense_posture_button)
	var doctrine := VBoxContainer.new()
	doctrine.add_theme_constant_override("separation", 3)
	column.add_child(doctrine)
	_add_detail_row(doctrine, "Alert threshold", "EXCEPTIONS ONLY", CYAN_COLOR)
	_add_detail_row(doctrine, "Routine execution", "AUTONOMOUS", CYAN_COLOR)


func _make_system_button(system_id: String) -> Button:
	var data := MOCK_SYSTEMS.get(system_id, {}) as Dictionary
	var button := Button.new()
	button.name = "System_%s" % system_id
	button.text = "%s\n%s" % [str(data.get("label", system_id)).to_upper(), str(data.get("value", "—"))]
	button.tooltip_text = str(data.get("state", "")) + " // MOCK DATA"
	button.custom_minimum_size = Vector2(118.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", DATA_FONT)
	button.add_theme_font_size_override("font_size", 8)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_stylebox_override("hover", _make_style(Color("262929"), CYAN_COLOR, 1, 7.0))
	button.add_theme_stylebox_override("pressed", _make_style(SELECTED_BG, CYAN_COLOR, 1, 7.0))
	return button


func _select_system(system_id: String) -> void:
	if not MOCK_SYSTEMS.has(system_id):
		return
	_selected_system_id = system_id
	var data := MOCK_SYSTEMS[system_id] as Dictionary
	var warning := bool(data.get("warning", false))
	_detail_category.text = "ATTENTION REQUIRED // MOCK DATA" if warning else "SYSTEM DETAIL // MOCK DATA"
	_detail_category.add_theme_color_override("font_color", AMBER_COLOR if warning else CYAN_COLOR)
	_detail_title.text = str(data.get("label", system_id)).to_upper()
	_detail_state.text = str(data.get("state", ""))
	_detail_state.add_theme_color_override("font_color", AMBER_COLOR if warning else CYAN_COLOR)
	_detail_copy.text = str(data.get("copy", ""))
	_event_copy.text = str(data.get("event", ""))
	_event_panel.add_theme_stylebox_override("panel", _make_style(WARNING_BG if warning else SELECTED_BG, AMBER_COLOR if warning else CYAN_COLOR, 1, 10.0))
	_clear_children(_detail_rows)
	for row_variant in data.get("rows", []):
		var row := row_variant as Array
		if row.size() >= 2:
			_add_detail_row(_detail_rows, str(row[0]), str(row[1]), TEXT_COLOR)
	_schematic_selection_label.text = "%s // %s" % [str(data.get("label", "")).to_upper(), str(data.get("state", ""))]
	_refresh_system_button_styles()
	_refresh_doctrine_controls()
	_apply_selection_to_schematic()


func _apply_selection_to_schematic() -> void:
	if _wireframe_view == null or not MOCK_SYSTEMS.has(_selected_system_id):
		return
	var data := MOCK_SYSTEMS[_selected_system_id] as Dictionary
	_wireframe_view.call("set_highlighted_region", str(data.get("region", "overview")), bool(data.get("warning", false)))


func _on_wireframe_model_ready() -> void:
	_apply_selection_to_schematic()


func _refresh_system_button_styles() -> void:
	for system_id: String in MOCK_SYSTEM_ORDER:
		var button := _system_buttons.get(system_id) as Button
		if button == null:
			continue
		var data := MOCK_SYSTEMS[system_id] as Dictionary
		var selected := system_id == _selected_system_id
		var warning := bool(data.get("warning", false))
		var border := AMBER_COLOR if warning else CYAN_COLOR if selected else BORDER_COLOR
		var background := WARNING_BG if warning and selected else SELECTED_BG if selected else PANEL_BG
		button.add_theme_stylebox_override("normal", _make_style(background, border, 1, 7.0))
		button.add_theme_color_override("font_color", AMBER_COLOR if warning else BRIGHT_CYAN if selected else STATUS_COLOR)


func _cycle_repair_priority() -> void:
	_repair_priority_index = (_repair_priority_index + 1) % REPAIR_PRIORITIES.size()
	_refresh_doctrine_controls()


func _cycle_defense_posture() -> void:
	_defense_posture_index = (_defense_posture_index + 1) % DEFENSE_POSTURES.size()
	_refresh_doctrine_controls()


func _refresh_doctrine_controls() -> void:
	if _repair_priority_button != null:
		_repair_priority_button.text = "REPAIR PRIORITY  //  %s" % REPAIR_PRIORITIES[_repair_priority_index]
	if _defense_posture_button != null:
		_defense_posture_button.text = "DEFENSE POSTURE  //  %s" % DEFENSE_POSTURES[_defense_posture_index]


func _make_doctrine_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 32.0
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", DATA_FONT)
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_color_override("font_color", STATUS_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_stylebox_override("normal", _make_style(PANEL_BG, BORDER_COLOR, 1, 8.0))
	button.add_theme_stylebox_override("hover", _make_style(SELECTED_BG, CYAN_COLOR, 1, 8.0))
	button.add_theme_stylebox_override("pressed", _make_style(PAGE_BG, CYAN_COLOR, 1, 8.0))
	return button


func _add_summary_card(parent: HBoxContainer, title: String, value: String, lines: Array[String], value_color: Color) -> void:
	var panel := Panel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_ALT_BG, BORDER_COLOR, 1))
	parent.add_child(panel)
	var margin := _make_margin(8, 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)
	column.add_child(_make_label(title + " // MOCK", 8, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	column.add_child(_make_label(value, 13, value_color, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	for line: String in lines:
		column.add_child(_make_label(line, 8, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))


func _add_detail_row(parent: Container, title: String, value: String, value_color: Color) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 20.0
	parent.add_child(row)
	var title_label := _make_label(title, 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	row.add_child(_make_label(value, 9, value_color, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT))


func _make_margin(vertical: int, horizontal: int = -1) -> MarginContainer:
	var resolved_horizontal := vertical if horizontal < 0 else horizontal
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", resolved_horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_right", resolved_horizontal)
	margin.add_theme_constant_override("margin_bottom", vertical)
	return margin


func _add_rule(parent: Container) -> void:
	var rule := ColorRect.new()
	rule.color = BORDER_COLOR
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)


func _make_label(text_value: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, font: Font = HEADLINE_FONT) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = align
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_style(background: Color, border: Color, border_width: int, horizontal_padding: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = horizontal_padding
	style.content_margin_right = horizontal_padding
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	return style


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
