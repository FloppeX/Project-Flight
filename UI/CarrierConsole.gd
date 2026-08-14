extends CanvasLayer

## Shared entry point and navigation for every carrier operations screen.
##
## Individual pages continue to own their presentation and data refresh logic.
## This node owns input, page selection, and mutual exclusion so only one carrier
## interface can be visible at a time.

signal opened
signal closed
signal page_changed(page_id: String)

const HEADLINE_FONT: FontFile = preload("res://UI/Fonts/ArchivoNarrow-Variable.ttf")
const DATA_FONT: FontFile = preload("res://UI/Fonts/JetBrainsMono-Variable.ttf")

const PAGE_TACTICAL := "tactical"
const PAGE_AIR_WING := "air_wing"
const PAGE_PERSONNEL := "personnel"
const PAGE_GROUND_BAY := "ground_bay"
const PAGE_CARRIER := "carrier"
const PAGE_REPLICATOR := "replicator"

const NAV_ITEMS: Array[Dictionary] = [
	{"id": PAGE_TACTICAL, "label": "TACTICAL"},
	{"id": PAGE_AIR_WING, "label": "AIR WING"},
	{"id": PAGE_PERSONNEL, "label": "PERSONNEL"},
	{"id": PAGE_GROUND_BAY, "label": "GROUND"},
	{"id": PAGE_CARRIER, "label": "CARRIER"},
	{"id": PAGE_REPLICATOR, "label": "REPLICATOR"},
]

const PAGE_DESCRIPTIONS := {
	PAGE_AIR_WING: "AIRCRAFT INVENTORY, CONDITION, LOADOUTS, AND REPAIR SCHEDULING",
	PAGE_GROUND_BAY: "GROUND VEHICLE INVENTORY, PLATOONS, CONDITION, AND DEPLOYMENT",
	PAGE_CARRIER: "CARRIER SUBSYSTEMS, DEFENSIVE WEAPONS, DAMAGE, AND STORES",
	PAGE_REPLICATOR: "CONSTRUCTION QUEUE, MATERIAL COSTS, AND FABRICATION CAPACITY",
}

const TEXT_COLOR := Color("e5e2e1")
const STATUS_COLOR := Color("c4c7c7")
const BORDER_COLOR := Color("434747")
const CYAN_COLOR := Color("76c7c7")
const AMBER_COLOR := Color("ffb000")
const DIM_COLOR := Color("7d8282")
const PANEL_BG := Color("141313")
const PANEL_ALT_BG := Color("1c1b1b")
const NAV_LEFT_RESERVE_PX := 360.0
const NAV_RIGHT_MARGIN_PX := 20.0
const NAV_MIN_TAB_WIDTH_PX := 104.0
const TOP_BAR_HEIGHT_PX := 64.0

var _root: Control
var _nav_panel: Panel
var _nav_buttons: Dictionary = {}
var _placeholder_root: Control
var _placeholder_panel: Panel
var _placeholder_title: Label
var _placeholder_subtitle: Label
var _placeholder_body: Label
var _placeholder_footer: Label

var _is_open: bool = false
var _current_page: String = PAGE_TACTICAL


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 192
	_build_ui()
	set_process_input(true)
	call_deferred("_apply_page_visibility")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("map_toggle", false):
		if event is InputEventKey and event.echo:
			return
		# The carrier console should not open over the actual pause menu.
		if not _is_open and get_tree().paused:
			return
		set_open(not _is_open)
		get_viewport().set_input_as_handled()
		return

	if not _is_open:
		return

	# Let the pause action continue to PauseMenu, but do not leave two modal
	# interfaces stacked when it opens.
	if event.is_action_pressed("pause_game", false):
		set_open(false)
		return

	if event.is_action_pressed("ui_cancel", false):
		set_open(false)
		get_viewport().set_input_as_handled()


func set_open(value: bool) -> void:
	if _is_open == value:
		if value:
			_apply_page_visibility()
		return
	_is_open = value
	_root.visible = value
	_apply_page_visibility()
	if value:
		emit_signal("opened")
	else:
		var viewport := get_viewport()
		if viewport != null:
			viewport.gui_release_focus()
		emit_signal("closed")


func is_open() -> bool:
	return _is_open


func show_page(page_id: String, open_console: bool = true) -> void:
	if not _is_valid_page(page_id):
		push_warning("CarrierConsole: Unknown page '%s'" % page_id)
		return
	var changed := _current_page != page_id
	_current_page = page_id
	if open_console and not _is_open:
		set_open(true)
	else:
		_apply_page_visibility()
	if changed:
		emit_signal("page_changed", page_id)


func get_current_page() -> String:
	return _current_page


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "CarrierConsoleRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_placeholder()
	_build_navigation()

	_root.resized.connect(_layout_ui)
	_layout_ui()
	_root.visible = false


func _build_navigation() -> void:
	_nav_panel = Panel.new()
	_nav_panel.name = "ConsoleNavigation"
	_nav_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_nav_panel.add_theme_stylebox_override("panel", _make_style(PANEL_BG, BORDER_COLOR, 0))
	_root.add_child(_nav_panel)

	for item: Dictionary in NAV_ITEMS:
		var page_id := str(item.get("id", ""))
		var button := _make_nav_button(str(item.get("label", page_id)).to_upper())
		button.pressed.connect(_on_nav_pressed.bind(page_id))
		_nav_panel.add_child(button)
		_nav_buttons[page_id] = button


func _build_placeholder() -> void:
	_placeholder_root = Control.new()
	_placeholder_root.name = "PlannedPage"
	_placeholder_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placeholder_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_placeholder_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("0e0e0e")
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_placeholder_root.add_child(backdrop)

	_placeholder_panel = Panel.new()
	_placeholder_panel.add_theme_stylebox_override("panel", _make_style(PANEL_ALT_BG, BORDER_COLOR, 1))
	_placeholder_root.add_child(_placeholder_panel)

	_placeholder_title = _make_label("", 24, TEXT_COLOR)
	_placeholder_panel.add_child(_placeholder_title)
	_placeholder_subtitle = _make_label("CARRIER OPERATIONS INTERFACE // FOUNDATION ONLINE", 13, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_placeholder_panel.add_child(_placeholder_subtitle)

	_placeholder_body = _make_label("", 17, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_placeholder_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_placeholder_panel.add_child(_placeholder_body)

	_placeholder_footer = _make_label("M / ESC: CLOSE // SELECT TACTICAL OR PERSONNEL FOR ACTIVE SYSTEMS", 12, DIM_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	_placeholder_panel.add_child(_placeholder_footer)


func _layout_ui() -> void:
	if _root == null:
		return
	var viewport_size := _root.size
	var nav_left := minf(NAV_LEFT_RESERVE_PX, maxf(viewport_size.x * 0.34, 8.0))
	var nav_width := viewport_size.x - nav_left - NAV_RIGHT_MARGIN_PX
	var minimum_nav_width := NAV_MIN_TAB_WIDTH_PX * float(NAV_ITEMS.size()) + 8.0
	if nav_width < minimum_nav_width:
		nav_width = maxf(viewport_size.x - 16.0, 1.0)
		nav_left = 8.0
	_nav_panel.position = Vector2(nav_left, 0.0)
	_nav_panel.size = Vector2(nav_width, TOP_BAR_HEIGHT_PX)
	_layout_navigation_tabs(nav_width)

	_placeholder_panel.position = Vector2(0.0, TOP_BAR_HEIGHT_PX)
	_placeholder_panel.size = Vector2(
		maxf(viewport_size.x, 1.0),
		maxf(viewport_size.y - TOP_BAR_HEIGHT_PX, 1.0)
	)
	var panel_size := _placeholder_panel.size
	_placeholder_title.position = Vector2(32.0, 24.0)
	_placeholder_title.size = Vector2(maxf(panel_size.x - 64.0, 220.0), 34.0)
	_placeholder_subtitle.position = Vector2(32.0, 60.0)
	_placeholder_subtitle.size = Vector2(maxf(panel_size.x - nav_width - 70.0, 220.0), 18.0)
	_placeholder_body.position = Vector2(panel_size.x * 0.18, panel_size.y * 0.27)
	_placeholder_body.size = Vector2(panel_size.x * 0.64, panel_size.y * 0.42)
	_placeholder_footer.position = Vector2(32.0, panel_size.y - 36.0)
	_placeholder_footer.size = Vector2(panel_size.x - 64.0, 18.0)


func _on_nav_pressed(page_id: String) -> void:
	show_page(page_id, true)


func _apply_page_visibility() -> void:
	var tactical_active := _is_open and _current_page == PAGE_TACTICAL
	var personnel_active := _is_open and _current_page == PAGE_PERSONNEL
	_set_external_page_visible("/root/WorldMapOverlay", tactical_active)
	_set_external_page_visible("/root/PilotRosterOverlay", personnel_active)

	var placeholder_active := _is_open and not tactical_active and not personnel_active
	if _placeholder_root != null:
		_placeholder_root.visible = placeholder_active
	if placeholder_active:
		_refresh_placeholder()
	_refresh_navigation()


func _set_external_page_visible(path: String, value: bool) -> void:
	var page := get_node_or_null(path)
	if page == null:
		return
	if page.has_method("set_console_visible"):
		page.call("set_console_visible", value)


func _refresh_placeholder() -> void:
	var label := _page_label(_current_page)
	var description := str(PAGE_DESCRIPTIONS.get(_current_page, "SYSTEM INTERFACE RESERVED"))
	_placeholder_title.text = "CARRIER OPERATIONS // %s" % label
	_placeholder_body.text = "%s\n\nSYSTEM PAGE RESERVED\nDATA MODEL NOT YET CONNECTED" % description


func _refresh_navigation() -> void:
	for item: Dictionary in NAV_ITEMS:
		var page_id := str(item.get("id", ""))
		var button := _nav_buttons.get(page_id) as Button
		if button == null:
			continue
		var active := _is_open and page_id == _current_page
		button.add_theme_stylebox_override(
			"normal",
			_make_tab_style(
				Color("202525") if active else PANEL_BG,
				CYAN_COLOR if active else BORDER_COLOR,
				active
			)
		)
		button.add_theme_color_override("font_color", TEXT_COLOR if active else STATUS_COLOR)


func _make_nav_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", DATA_FONT)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", STATUS_COLOR)
	button.add_theme_stylebox_override("normal", _make_tab_style(PANEL_BG, BORDER_COLOR, false))
	button.add_theme_stylebox_override("hover", _make_tab_style(Color("2a2a2a"), BORDER_COLOR, false))
	button.add_theme_stylebox_override("pressed", _make_tab_style(Color("202525"), CYAN_COLOR, true))
	return button


func _layout_navigation_tabs(nav_width: float) -> void:
	if NAV_ITEMS.is_empty():
		return
	var inner_width := maxf(nav_width - 8.0, 1.0)
	var gap := 2.0
	var tab_width := maxf(
		(inner_width - gap * float(NAV_ITEMS.size() - 1)) / float(NAV_ITEMS.size()),
		1.0
	)
	var x := 4.0
	for item: Dictionary in NAV_ITEMS:
		var button := _nav_buttons.get(str(item.get("id", ""))) as Button
		if button == null:
			continue
		button.position = Vector2(x, 8.0)
		button.size = Vector2(tab_width, TOP_BAR_HEIGHT_PX - 8.0)
		x += tab_width + gap


func _make_label(
	text: String,
	font_size: int,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	font: Font = HEADLINE_FONT
) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	return style


func _make_tab_style(background: Color, border: Color, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_bottom = 3 if selected else 1
	style.content_margin_top = 8.0
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	return style


func _is_valid_page(page_id: String) -> bool:
	for item: Dictionary in NAV_ITEMS:
		if str(item.get("id", "")) == page_id:
			return true
	return false


func _page_label(page_id: String) -> String:
	for item: Dictionary in NAV_ITEMS:
		if str(item.get("id", "")) == page_id:
			return str(item.get("label", page_id)).to_upper()
	return page_id.to_upper()
