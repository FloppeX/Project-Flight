class_name ReplicatorPage
extends Control

## Static interactive concept for the carrier Replicator page.
##
## This page deliberately owns only temporary preview state. It does not read or
## mutate CarrierManager, the hangar, the vehicle bay, save data, or weapon stores.

const HEADLINE_FONT: FontFile = preload("res://UI/Fonts/ArchivoNarrow-Variable.ttf")
const DATA_FONT: FontFile = preload("res://UI/Fonts/JetBrainsMono-Variable.ttf")

const TEXT_COLOR := Color("e5e2e1")
const STATUS_COLOR := Color("c4c7c7")
const BORDER_COLOR := Color("434747")
const CYAN_COLOR := Color("76c7c7")
const AMBER_COLOR := Color("ffb000")
const DIM_COLOR := Color("7d8282")
const PAGE_BG := Color("0e0e0e")
const PANEL_BG := Color("141313")
const PANEL_ALT_BG := Color("1c1b1b")
const SELECTED_BG := Color("202828")

const STARTING_PLASTEEL := 1000
const STARTING_CORIUM := 1000
const MAX_PREVIEW_QUANTITY := 9
const MAX_PREVIEW_QUEUE := 8

const MOCK_BLUEPRINTS: Array[Dictionary] = [
	{
		"id": "sand_sprite",
		"name": "SNA AS-20 SAND SPRITE",
		"type": "LIGHT MULTIROLE AIRFRAME",
		"category": "AIRFRAMES",
		"plasteel": 260,
		"corium": 90,
		"duration_s": 240,
		"stock": "08 IN HANGAR",
		"destination": "FLIGHT HANGAR",
		"capacity": "09 / 12 RESERVED",
		"description": "Carrier-capable fighter, attack, and reconnaissance airframe. Delivered unassigned to an available hangar slot.",
		"outline": "res://Images/Aircraft Outlines/aircraft_1.png",
	},
	{
		"id": "hummingbird",
		"name": "AD UH-8 HUMMINGBIRD",
		"type": "UTILITY ROTORCRAFT",
		"category": "AIRFRAMES",
		"plasteel": 180,
		"corium": 55,
		"duration_s": 180,
		"stock": "02 IN HANGAR",
		"destination": "FLIGHT HANGAR",
		"capacity": "09 / 12 RESERVED",
		"description": "Agile utility helicopter for rescue, reconnaissance, insertion, and routine carrier logistics.",
		"outline": "res://Images/Aircraft Outlines/aircraft_11.png",
	},
	{
		"id": "autocannon_20mm",
		"name": "20 MM AUTOCANNON ASSEMBLY",
		"type": "HARDPOINT WEAPON",
		"category": "ORDNANCE",
		"plasteel": 45,
		"corium": 35,
		"duration_s": 60,
		"stock": "03 IN STORES",
		"destination": "ORDNANCE STORES",
		"capacity": "14 / 30 PALLETS",
		"description": "Complete reusable weapon assembly for compatible aircraft hardpoints. Ammunition is fabricated separately.",
		"outline": "",
	},
	{
		"id": "ammo_20mm",
		"name": "20 MM AMMUNITION PALLET",
		"type": "STANDARD AMMUNITION BATCH",
		"category": "ORDNANCE",
		"plasteel": 30,
		"corium": 8,
		"duration_s": 35,
		"stock": "06 PALLETS",
		"destination": "ORDNANCE STORES",
		"capacity": "14 / 30 PALLETS",
		"description": "Standardized ammunition batch for autonomous loading crews. Manufactured and tracked by the pallet.",
		"outline": "",
	},
	{
		"id": "light_combat_vehicle",
		"name": "FRIENDLY LIGHT COMBAT VEHICLE",
		"type": "SIX-WHEELED GROUND VEHICLE",
		"category": "VEHICLES",
		"plasteel": 80,
		"corium": 12,
		"duration_s": 90,
		"stock": "12 IN VEHICLE BAY",
		"destination": "VEHICLE BAY",
		"capacity": "13 / 16 RESERVED",
		"description": "Carrier-deployed light combat vehicle used by ground platoons for security, escort, and local operations.",
		"outline": "",
	},
]

const STARTING_MOCK_QUEUE: Array[Dictionary] = [
	{
		"name": "20 MM AMMUNITION PALLET ×2",
		"destination": "ORDNANCE STORES",
		"remaining": "00:24 REMAINING",
		"progress": 31.0,
		"state": "FABRICATING",
		"refund_plasteel": 0,
		"refund_corium": 0,
	},
	{
		"name": "AD UH-8 HUMMINGBIRD",
		"destination": "FLIGHT HANGAR",
		"remaining": "03:00",
		"progress": 0.0,
		"state": "QUEUED",
		"refund_plasteel": 0,
		"refund_corium": 0,
	},
]

var _available_plasteel: int = STARTING_PLASTEEL
var _available_corium: int = STARTING_CORIUM
var _selected_blueprint_id: String = "sand_sprite"
var _filter_category: String = "ALL"
var _preview_quantity: int = 1
var _mock_queue: Array[Dictionary] = []

var _filter_buttons: Dictionary = {}
var _blueprint_list: VBoxContainer
var _blueprint_count_label: Label
var _plasteel_value: Label
var _corium_value: Label
var _detail_category: Label
var _detail_name: Label
var _detail_description: Label
var _detail_stock: Label
var _detail_destination: Label
var _detail_capacity: Label
var _detail_duration: Label
var _detail_outline: TextureRect
var _detail_outline_fallback: Label
var _quantity_label: Label
var _cost_label: Label
var _after_order_label: Label
var _queue_button: Button
var _queue_reason: Label
var _queue_rows: VBoxContainer
var _queue_count_label: Label
var _feedback_label: Label
var _content_split: HSplitContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	for order: Dictionary in STARTING_MOCK_QUEUE:
		_mock_queue.append(order.duplicate(true))
	_build_ui()
	_refresh_all()


func set_console_visible(value: bool) -> void:
	visible = value
	if value:
		_refresh_all()


func get_debug_snapshot() -> Dictionary:
	return {
		"kind": "replicator",
		"mode": "concept_preview",
		"blueprint_count": MOCK_BLUEPRINTS.size(),
		"visible_blueprint_count": _filtered_blueprints().size(),
		"selected_blueprint": _selected_blueprint_id,
		"filter": _filter_category,
		"quantity": _preview_quantity,
		"queue_count": _mock_queue.size(),
		"plasteel": _available_plasteel,
		"corium": _available_corium,
	}


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(_content_split):
		_content_split.split_offset = clampi(int(size.x * 0.36), 330, 500)


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = PAGE_BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var page_margin := MarginContainer.new()
	page_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_margin.add_theme_constant_override("margin_left", 24)
	page_margin.add_theme_constant_override("margin_top", 18)
	page_margin.add_theme_constant_override("margin_right", 24)
	page_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(page_margin)

	var page_column := VBoxContainer.new()
	page_column.add_theme_constant_override("separation", 9)
	page_margin.add_child(page_column)

	_build_header(page_column)
	_add_rule(page_column)
	_build_filter_row(page_column)
	_build_content(page_column)
	_build_queue(page_column)

	var footer := _make_label(
		"CONCEPT PREVIEW // SELECTIONS AND QUEUE CHANGES RESET WITH THE SESSION",
		10,
		DIM_COLOR,
		HORIZONTAL_ALIGNMENT_RIGHT,
		DATA_FONT
	)
	page_column.add_child(footer)


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 62.0
	header.add_theme_constant_override("separation", 18)
	parent.add_child(header)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 0)
	header.add_child(heading)
	var title := _make_label("MANUFACTURING CONTROL", 28, TEXT_COLOR)
	heading.add_child(title)
	var subtitle := _make_label(
		"AVAILABLE BLUEPRINTS, MATERIAL COMMITMENTS, AND FABRICATION QUEUE",
		12,
		STATUS_COLOR,
		HORIZONTAL_ALIGNMENT_LEFT,
		DATA_FONT
	)
	heading.add_child(subtitle)

	var resource_cluster := HBoxContainer.new()
	resource_cluster.add_theme_constant_override("separation", 8)
	header.add_child(resource_cluster)
	_plasteel_value = _add_resource_readout(resource_cluster, "PLASTEEL")
	_corium_value = _add_resource_readout(resource_cluster, "CORIUM")
	_add_resource_readout(resource_cluster, "FABRICATOR", "ONLINE", CYAN_COLOR)


func _add_resource_readout(
	parent: HBoxContainer,
	title: String,
	initial_value: String = "0000",
	value_color: Color = TEXT_COLOR
) -> Label:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(132.0, 54.0)
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_BG, BORDER_COLOR, 1, 12.0))
	parent.add_child(panel)
	var margin := _make_margin(8, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)
	column.add_child(_make_label(title, 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	var value := _make_label(initial_value, 15, value_color, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	column.add_child(value)
	return value


func _build_filter_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 34.0
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var caption := _make_label("DISPLAY", 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	caption.custom_minimum_size = Vector2(68.0, 30.0)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)
	for category in ["ALL", "AIRFRAMES", "ORDNANCE", "VEHICLES"]:
		var button := _make_filter_button(category)
		button.pressed.connect(_on_filter_pressed.bind(category))
		row.add_child(button)
		_filter_buttons[category] = button
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var preview_notice := _make_label(
		"● CONCEPT DATA // SYSTEMS NOT CONNECTED",
		10,
		AMBER_COLOR,
		HORIZONTAL_ALIGNMENT_RIGHT,
		DATA_FONT
	)
	preview_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(preview_notice)


func _build_content(parent: VBoxContainer) -> void:
	_content_split = HSplitContainer.new()
	_content_split.name = "ManufacturingSplit"
	_content_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_split.custom_minimum_size.y = 370.0
	_content_split.split_offset = 430
	_content_split.add_theme_constant_override("separation", 12)
	parent.add_child(_content_split)

	_build_blueprint_library(_content_split)
	_build_blueprint_detail(_content_split)


func _build_blueprint_library(parent: HSplitContainer) -> void:
	var panel := Panel.new()
	panel.custom_minimum_size.x = 330.0
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_BG, BORDER_COLOR, 1, 12.0))
	parent.add_child(panel)
	var margin := _make_margin(14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := _make_label("BLUEPRINT LIBRARY", 14, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_blueprint_count_label = _make_label("", 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	heading.add_child(_blueprint_count_label)

	var guide := HBoxContainer.new()
	column.add_child(guide)
	var identity := _make_label("PATTERN / OUTPUT", 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide.add_child(identity)
	guide.add_child(_make_label("COST", 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_blueprint_list = VBoxContainer.new()
	_blueprint_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blueprint_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_blueprint_list)


func _build_blueprint_detail(parent: HSplitContainer) -> void:
	var panel := Panel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_ALT_BG, BORDER_COLOR, 1, 16.0))
	parent.add_child(panel)
	var margin := _make_margin(18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	_detail_category = _make_label("", 10, CYAN_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	column.add_child(_detail_category)
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	_detail_name = _make_label("", 24, TEXT_COLOR)
	_detail_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(_detail_name)
	var available := _make_label("● BLUEPRINT AVAILABLE", 10, CYAN_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	available.custom_minimum_size.x = 188.0
	available.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(available)

	var overview := HBoxContainer.new()
	overview.custom_minimum_size.y = 122.0
	overview.add_theme_constant_override("separation", 16)
	column.add_child(overview)
	var outline_frame := Panel.new()
	outline_frame.custom_minimum_size = Vector2(205.0, 122.0)
	outline_frame.add_theme_stylebox_override("panel", _make_style(PAGE_BG, BORDER_COLOR, 1))
	overview.add_child(outline_frame)
	_detail_outline = TextureRect.new()
	_detail_outline.name = "BlueprintOutline"
	_detail_outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_outline.offset_left = 10.0
	_detail_outline.offset_top = 10.0
	_detail_outline.offset_right = -10.0
	_detail_outline.offset_bottom = -10.0
	_detail_outline.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_outline.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_outline.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_detail_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline_frame.add_child(_detail_outline)
	_detail_outline_fallback = _make_label("", 18, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
	_detail_outline_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_outline_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outline_frame.add_child(_detail_outline_fallback)

	var facts := VBoxContainer.new()
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.add_theme_constant_override("separation", 4)
	overview.add_child(facts)
	_detail_stock = _add_fact_line(facts, "CURRENT STOCK")
	_detail_destination = _add_fact_line(facts, "DELIVERY")
	_detail_capacity = _add_fact_line(facts, "DESTINATION CAPACITY")
	_detail_duration = _add_fact_line(facts, "BUILD TIME")

	_detail_description = _make_label("", 13, STATUS_COLOR)
	_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_description.custom_minimum_size.y = 44.0
	column.add_child(_detail_description)
	_add_rule(column)

	var order_row := HBoxContainer.new()
	order_row.add_theme_constant_override("separation", 16)
	column.add_child(order_row)
	var quantity_column := VBoxContainer.new()
	quantity_column.add_theme_constant_override("separation", 3)
	order_row.add_child(quantity_column)
	quantity_column.add_child(_make_label("QUANTITY", 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	var quantity_controls := HBoxContainer.new()
	quantity_controls.add_theme_constant_override("separation", 0)
	quantity_column.add_child(quantity_controls)
	var minus := _make_stepper_button("−")
	minus.pressed.connect(_change_quantity.bind(-1))
	quantity_controls.add_child(minus)
	var quantity_panel := Panel.new()
	quantity_panel.custom_minimum_size = Vector2(48.0, 38.0)
	quantity_panel.add_theme_stylebox_override("panel", _make_style(PAGE_BG, BORDER_COLOR, 1))
	quantity_controls.add_child(quantity_panel)
	_quantity_label = _make_label("1", 13, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
	_quantity_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quantity_panel.add_child(_quantity_label)
	var plus := _make_stepper_button("+")
	plus.pressed.connect(_change_quantity.bind(1))
	quantity_controls.add_child(plus)

	var cost_column := VBoxContainer.new()
	cost_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_column.add_theme_constant_override("separation", 2)
	order_row.add_child(cost_column)
	cost_column.add_child(_make_label("ORDER COMMITMENT", 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	_cost_label = _make_label("", 13, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	cost_column.add_child(_cost_label)
	_after_order_label = _make_label("", 10, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	cost_column.add_child(_after_order_label)

	_queue_button = Button.new()
	_queue_button.text = "ADD TO QUEUE"
	_queue_button.custom_minimum_size = Vector2(170.0, 42.0)
	_queue_button.focus_mode = Control.FOCUS_NONE
	_queue_button.add_theme_font_override("font", DATA_FONT)
	_queue_button.add_theme_font_size_override("font_size", 11)
	_queue_button.add_theme_color_override("font_color", Color("161000"))
	_queue_button.add_theme_color_override("font_hover_color", Color("161000"))
	_queue_button.add_theme_color_override("font_disabled_color", DIM_COLOR)
	_queue_button.add_theme_stylebox_override("normal", _make_style(AMBER_COLOR, AMBER_COLOR, 1, 12.0))
	_queue_button.add_theme_stylebox_override("hover", _make_style(Color("ffc13d"), AMBER_COLOR, 1, 12.0))
	_queue_button.add_theme_stylebox_override("pressed", _make_style(Color("d89000"), AMBER_COLOR, 1, 12.0))
	_queue_button.add_theme_stylebox_override("disabled", _make_style(PAGE_BG, BORDER_COLOR, 1, 12.0))
	_queue_button.pressed.connect(_on_add_to_queue_pressed)
	order_row.add_child(_queue_button)
	_queue_reason = _make_label("", 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	column.add_child(_queue_reason)


func _add_fact_line(parent: VBoxContainer, title: String) -> Label:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 21.0
	parent.add_child(row)
	var caption := _make_label(title, 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	var value := _make_label("", 10, TEXT_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	row.add_child(value)
	return value


func _build_queue(parent: VBoxContainer) -> void:
	var panel := Panel.new()
	panel.custom_minimum_size.y = 176.0
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_BG, BORDER_COLOR, 1, 12.0))
	parent.add_child(panel)
	var margin := _make_margin(12, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)

	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := _make_label("MANUFACTURING QUEUE", 14, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_queue_count_label = _make_label("", 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	heading.add_child(_queue_count_label)
	_queue_rows = VBoxContainer.new()
	_queue_rows.add_theme_constant_override("separation", 4)
	column.add_child(_queue_rows)
	_feedback_label = _make_label("", 10, CYAN_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	column.add_child(_feedback_label)


func _refresh_all() -> void:
	_refresh_resource_readouts()
	_refresh_filter_styles()
	_rebuild_blueprint_list()
	_refresh_detail()
	_rebuild_queue()


func _refresh_resource_readouts() -> void:
	_plasteel_value.text = "%s UNITS" % _format_number(_available_plasteel)
	_corium_value.text = "%s UNITS" % _format_number(_available_corium)


func _refresh_filter_styles() -> void:
	for category: String in _filter_buttons:
		var button := _filter_buttons.get(category) as Button
		if button == null:
			continue
		var active := category == _filter_category
		button.add_theme_stylebox_override(
			"normal",
			_make_style(SELECTED_BG if active else PANEL_BG, CYAN_COLOR if active else BORDER_COLOR, 1, 9.0)
		)
		button.add_theme_color_override("font_color", TEXT_COLOR if active else STATUS_COLOR)


func _rebuild_blueprint_list() -> void:
	_clear_children(_blueprint_list)
	var blueprints := _filtered_blueprints()
	_blueprint_count_label.text = "%d AVAILABLE" % blueprints.size()
	for blueprint: Dictionary in blueprints:
		var blueprint_id := str(blueprint.get("id", ""))
		var selected := blueprint_id == _selected_blueprint_id
		var button := Button.new()
		button.name = "Blueprint_%s" % blueprint_id
		button.text = "%s\n%s" % [
			str(blueprint.get("name", "PATTERN")),
			str(blueprint.get("type", "OUTPUT")),
		]
		button.tooltip_text = str(blueprint.get("description", ""))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 58.0
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", DATA_FONT)
		button.add_theme_font_size_override("font_size", 10)
		button.add_theme_color_override("font_color", TEXT_COLOR if selected else STATUS_COLOR)
		button.add_theme_color_override("font_hover_color", TEXT_COLOR)
		button.add_theme_stylebox_override(
			"normal",
			_make_style(SELECTED_BG if selected else PANEL_ALT_BG, CYAN_COLOR if selected else BORDER_COLOR, 1, 10.0)
		)
		button.add_theme_stylebox_override("hover", _make_style(Color("262929"), CYAN_COLOR, 1, 10.0))
		button.add_theme_stylebox_override("pressed", _make_style(SELECTED_BG, CYAN_COLOR, 2, 10.0))
		button.pressed.connect(_on_blueprint_pressed.bind(blueprint_id))
		_blueprint_list.add_child(button)

		var cost := _make_label(
			"%03d P  //  %03d C" % [int(blueprint.get("plasteel", 0)), int(blueprint.get("corium", 0))],
			9,
			STATUS_COLOR,
			HORIZONTAL_ALIGNMENT_RIGHT,
			DATA_FONT
		)
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		cost.position = Vector2(-172.0, 20.0)
		cost.size = Vector2(158.0, 18.0)
		button.add_child(cost)


func _refresh_detail() -> void:
	var blueprint := _selected_blueprint()
	if blueprint.is_empty():
		return
	_detail_category.text = "BLUEPRINT // %s" % str(blueprint.get("category", "PATTERN"))
	_detail_name.text = str(blueprint.get("name", "PATTERN"))
	_detail_description.text = str(blueprint.get("description", ""))
	_detail_stock.text = str(blueprint.get("stock", "—"))
	_detail_destination.text = str(blueprint.get("destination", "—"))
	_detail_capacity.text = str(blueprint.get("capacity", "—"))
	_detail_duration.text = _format_duration(int(blueprint.get("duration_s", 0)) * _preview_quantity)
	_quantity_label.text = str(_preview_quantity)

	var outline_path := str(blueprint.get("outline", ""))
	_detail_outline.texture = null
	if not outline_path.is_empty() and ResourceLoader.exists(outline_path):
		_detail_outline.texture = load(outline_path) as Texture2D
	_detail_outline.visible = _detail_outline.texture != null
	_detail_outline_fallback.visible = not _detail_outline.visible
	_detail_outline_fallback.text = _fallback_schematic_label(blueprint)

	var plasteel_cost := int(blueprint.get("plasteel", 0)) * _preview_quantity
	var corium_cost := int(blueprint.get("corium", 0)) * _preview_quantity
	_cost_label.text = "%s PLASTEEL  //  %s CORIUM" % [
		_format_number(plasteel_cost),
		_format_number(corium_cost),
	]
	_after_order_label.text = "AFTER ORDER  %s P  //  %s C" % [
		_format_number(_available_plasteel - plasteel_cost),
		_format_number(_available_corium - corium_cost),
	]

	var affordable := plasteel_cost <= _available_plasteel and corium_cost <= _available_corium
	var queue_has_space := _mock_queue.size() < MAX_PREVIEW_QUEUE
	_queue_button.disabled = not affordable or not queue_has_space
	if not affordable:
		_queue_reason.text = "INSUFFICIENT CONCEPT RESOURCES FOR THIS ORDER"
		_queue_reason.add_theme_color_override("font_color", AMBER_COLOR)
	elif not queue_has_space:
		_queue_reason.text = "PREVIEW QUEUE IS FULL"
		_queue_reason.add_theme_color_override("font_color", AMBER_COLOR)
	else:
		_queue_reason.text = "RESOURCES AND DESTINATION SPACE WOULD BE RESERVED WHEN THE ORDER IS PLACED"
		_queue_reason.add_theme_color_override("font_color", DIM_COLOR)


func _rebuild_queue() -> void:
	_clear_children(_queue_rows)
	_queue_count_label.text = "%d / %d ORDERS" % [_mock_queue.size(), MAX_PREVIEW_QUEUE]
	if _mock_queue.is_empty():
		var empty := _make_label("NO MANUFACTURING ORDERS QUEUED", 11, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
		empty.custom_minimum_size.y = 70.0
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_queue_rows.add_child(empty)
		return
	for index in range(_mock_queue.size()):
		_add_queue_row(_mock_queue[index], index)


func _add_queue_row(order: Dictionary, index: int) -> void:
	var panel := Panel.new()
	panel.custom_minimum_size.y = 45.0
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_ALT_BG, BORDER_COLOR, 1, 10.0))
	_queue_rows.add_child(panel)
	var margin := _make_margin(6, 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var identity := VBoxContainer.new()
	identity.custom_minimum_size.x = 330.0
	identity.add_theme_constant_override("separation", 0)
	row.add_child(identity)
	identity.add_child(_make_label(str(order.get("name", "ORDER")), 10, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	identity.add_child(_make_label(
		"%s  //  %s" % [str(order.get("destination", "STORES")), str(order.get("remaining", "QUEUED"))],
		9,
		DIM_COLOR,
		HORIZONTAL_ALIGNMENT_LEFT,
		DATA_FONT
	))

	var progress_column := VBoxContainer.new()
	progress_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_column.add_theme_constant_override("separation", 1)
	row.add_child(progress_column)
	var progress := ProgressBar.new()
	progress.custom_minimum_size.y = 6.0
	progress.show_percentage = false
	progress.value = float(order.get("progress", 0.0))
	progress.add_theme_stylebox_override("background", _make_style(PAGE_BG, Color.TRANSPARENT, 0))
	progress.add_theme_stylebox_override("fill", _make_style(CYAN_COLOR, Color.TRANSPARENT, 0))
	progress_column.add_child(progress)
	progress_column.add_child(_make_label(
		"%02d%% COMPLETE" % int(round(progress.value)),
		8,
		DIM_COLOR,
		HORIZONTAL_ALIGNMENT_LEFT,
		DATA_FONT
	))

	var state := _make_label(str(order.get("state", "QUEUED")), 10, CYAN_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	state.custom_minimum_size.x = 112.0
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(state)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(82.0, 30.0)
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.add_theme_font_override("font", DATA_FONT)
	cancel.add_theme_font_size_override("font_size", 9)
	cancel.add_theme_color_override("font_color", STATUS_COLOR)
	cancel.add_theme_color_override("font_hover_color", TEXT_COLOR)
	cancel.add_theme_stylebox_override("normal", _make_style(PANEL_BG, BORDER_COLOR, 1, 8.0))
	cancel.add_theme_stylebox_override("hover", _make_style(Color("262929"), AMBER_COLOR, 1, 8.0))
	cancel.add_theme_stylebox_override("pressed", _make_style(PAGE_BG, AMBER_COLOR, 1, 8.0))
	cancel.pressed.connect(_on_cancel_order_pressed.bind(index))
	row.add_child(cancel)


func _on_filter_pressed(category: String) -> void:
	_filter_category = category
	var visible := _filtered_blueprints()
	if not _contains_blueprint(visible, _selected_blueprint_id) and not visible.is_empty():
		_selected_blueprint_id = str(visible[0].get("id", ""))
		_preview_quantity = 1
	_feedback_label.text = ""
	_refresh_filter_styles()
	_rebuild_blueprint_list()
	_refresh_detail()


func _on_blueprint_pressed(blueprint_id: String) -> void:
	_selected_blueprint_id = blueprint_id
	_preview_quantity = 1
	_feedback_label.text = ""
	_rebuild_blueprint_list()
	_refresh_detail()


func _change_quantity(delta: int) -> void:
	_preview_quantity = clampi(_preview_quantity + delta, 1, MAX_PREVIEW_QUANTITY)
	_feedback_label.text = ""
	_refresh_detail()


func _on_add_to_queue_pressed() -> void:
	var blueprint := _selected_blueprint()
	if blueprint.is_empty():
		return
	var plasteel_cost := int(blueprint.get("plasteel", 0)) * _preview_quantity
	var corium_cost := int(blueprint.get("corium", 0)) * _preview_quantity
	if plasteel_cost > _available_plasteel or corium_cost > _available_corium:
		return
	if _mock_queue.size() >= MAX_PREVIEW_QUEUE:
		return
	_available_plasteel -= plasteel_cost
	_available_corium -= corium_cost
	var output_name := str(blueprint.get("name", "ORDER"))
	if _preview_quantity > 1:
		output_name += " ×%d" % _preview_quantity
	_mock_queue.append({
		"name": output_name,
		"destination": str(blueprint.get("destination", "STORES")),
		"remaining": _format_duration(int(blueprint.get("duration_s", 0)) * _preview_quantity),
		"progress": 0.0,
		"state": "QUEUED",
		"refund_plasteel": plasteel_cost,
		"refund_corium": corium_cost,
	})
	_feedback_label.text = "%s ADDED TO THE PREVIEW QUEUE" % output_name
	_preview_quantity = 1
	_refresh_resource_readouts()
	_refresh_detail()
	_rebuild_queue()


func _on_cancel_order_pressed(index: int) -> void:
	if index < 0 or index >= _mock_queue.size():
		return
	var order := _mock_queue[index]
	_available_plasteel += int(order.get("refund_plasteel", 0))
	_available_corium += int(order.get("refund_corium", 0))
	_feedback_label.text = "%s REMOVED FROM THE PREVIEW QUEUE" % str(order.get("name", "ORDER"))
	_mock_queue.remove_at(index)
	_refresh_resource_readouts()
	_refresh_detail()
	_rebuild_queue()


func _filtered_blueprints() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for blueprint: Dictionary in MOCK_BLUEPRINTS:
		if _filter_category == "ALL" or str(blueprint.get("category", "")) == _filter_category:
			result.append(blueprint)
	return result


func _selected_blueprint() -> Dictionary:
	for blueprint: Dictionary in MOCK_BLUEPRINTS:
		if str(blueprint.get("id", "")) == _selected_blueprint_id:
			return blueprint
	return {}


func _contains_blueprint(blueprints: Array[Dictionary], blueprint_id: String) -> bool:
	for blueprint: Dictionary in blueprints:
		if str(blueprint.get("id", "")) == blueprint_id:
			return true
	return false


func _fallback_schematic_label(blueprint: Dictionary) -> String:
	match str(blueprint.get("category", "")):
		"ORDNANCE":
			return "ORDNANCE\nASSEMBLY"
		"VEHICLES":
			return "GROUND\nVEHICLE"
		_:
			return "AIRFRAME"


func _make_filter_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(94.0, 30.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", DATA_FONT)
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_stylebox_override("hover", _make_style(Color("262929"), CYAN_COLOR, 1, 9.0))
	button.add_theme_stylebox_override("pressed", _make_style(SELECTED_BG, CYAN_COLOR, 1, 9.0))
	return button


func _make_stepper_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(42.0, 38.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", DATA_FONT)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", STATUS_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_stylebox_override("normal", _make_style(PAGE_BG, BORDER_COLOR, 1))
	button.add_theme_stylebox_override("hover", _make_style(Color("262929"), CYAN_COLOR, 1))
	button.add_theme_stylebox_override("pressed", _make_style(SELECTED_BG, CYAN_COLOR, 1))
	return button


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


func _make_label(
	text_value: String,
	font_size: int,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	font: Font = HEADLINE_FONT
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = align
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_style(
	background: Color,
	border: Color,
	border_width: int,
	horizontal_padding: float = 0.0
) -> StyleBoxFlat:
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


func _format_duration(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]


func _format_number(value: int) -> String:
	var sign_prefix := "-" if value < 0 else ""
	var digits := str(absi(value))
	var grouped_suffix := ""
	while digits.length() > 3:
		grouped_suffix = "," + digits.right(3) + grouped_suffix
		digits = digits.left(digits.length() - 3)
	return sign_prefix + digits + grouped_suffix
