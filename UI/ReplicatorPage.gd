class_name ReplicatorPage
extends Control

const HEADLINE_FONT: FontFile = preload("res://UI/Fonts/ArchivoNarrow-Variable.ttf")
const DATA_FONT: FontFile = preload("res://UI/Fonts/JetBrainsMono-Variable.ttf")
const CHAMBER := preload("res://LandCarrier/ReplicatorChamber.tscn")
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
const CATALOG := preload("res://LandCarrier/ReplicatorCatalog.gd")
const BLUEPRINTS: Array[Dictionary] = CATALOG.BLUEPRINTS
var _selected_blueprint_id := "kmv_explorer"
var _filter_category := "ALL"
var _quantity := 1
var _refresh_timer := 0.0
var _viewport: SubViewport
var _chamber: Node3D
var _blueprint_list: VBoxContainer
var _queue_rows: VBoxContainer
var _inventory: Label
var _resources: Label
var _detail_name: Label
var _detail_description: Label
var _detail_cost: Label
var _quantity_label: Label
var _queue_reason: Label
var _feedback_label: Label
var _camera_status: Label
var _stage_label: Label
var _progress: ProgressBar
var _queue_button: Button
var _transfer_status: Label
var _filter_buttons: Dictionary = {}
var _shield_readout: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_refresh_all()

func _manager() -> Node:
	var stores := get_tree().get_first_node_in_group("carrier_manager")
	return stores.call("get_replicator") if stores != null and stores.has_method("get_replicator") else null

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var manager := _manager()
	var state: Dictionary = manager.chamber_snapshot() if manager != null else {"phase": "idle", "progress": 0.0, "shield": 0.0, "rollout": 0.0, "stage": -1}
	var console := get_tree().root.get_node_or_null("CarrierConsole")
	var audible: bool = console != null and console.get("_replicator_page") == self
	_chamber.set_feed_state(state, audible)
	_update_chamber_labels(state)
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.35
		_refresh_all(false)

func set_console_visible(value: bool) -> void:
	visible = value
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
		_chamber.set_process(value)
	if value:
		_chamber.resume_feed()
		_refresh_all()
	elif is_instance_valid(_chamber):
		_chamber.set_feed_state({"phase": "idle", "progress": 0.0, "shield": 0.0, "rollout": 0.0, "stage": -1}, false)

func sync_monitor_preview_from(source: Control) -> void:
	_chamber.set_shield_opacity(source.get("_chamber").get_shield_opacity())
	_update_shield_readout()
	if _selected_blueprint_id != str(source.get("_selected_blueprint_id")) or _filter_category != str(source.get("_filter_category")):
		_selected_blueprint_id = str(source.get("_selected_blueprint_id"))
		_filter_category = str(source.get("_filter_category"))
		_rebuild_blueprints()
	_quantity = int(source.get("_quantity"))
	_refresh_all(false)

func adjust_shield_opacity(amount: float) -> void:
	_chamber.set_shield_opacity(_chamber.get_shield_opacity() + amount)
	_update_shield_readout()

func _update_shield_readout() -> void:
	_shield_readout.text = "SHIELD %03d%%  /  PGUP +  PGDN −" % roundi(_chamber.get_shield_opacity() * 100.0)

func get_debug_snapshot() -> Dictionary:
	var manager := _manager()
	var stores := get_tree().get_first_node_in_group("carrier_manager")
	return {"kind": "replicator", "mode": "live" if manager != null else "offline",
		"blueprint_count": BLUEPRINTS.size(), "selected_blueprint": _selected_blueprint_id,
		"known_blueprints": manager.known_blueprints.duplicate() if manager != null else CATALOG.STARTER_IDS.duplicate(),
		"queue_count": manager.queue.size() if manager != null else 0,
		"plasteel": float(stores.get("plasteel_units")) if stores != null else 0.0,
		"corium": float(stores.get("corium_units")) if stores != null else 0.0,
		"chamber": _chamber.get_debug_snapshot(), "camera_update_mode": _viewport.render_target_update_mode}

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = PAGE_BG
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := _make_margin(18, 22)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _make_label("REPLICATOR / FABRICATION CONTROL", 28, TEXT_COLOR)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	_resources = _make_label("", 14, CYAN_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	header.add_child(_resources)
	var filters := HBoxContainer.new()
	column.add_child(filters)
	for category in ["ALL", "VEHICLES", "AIRFRAMES", "ORDNANCE"]:
		var button := _make_filter_button(category)
		button.pressed.connect(_on_filter_pressed.bind(category))
		filters.add_child(button)
		_filter_buttons[category] = button
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	var library := _panel_column(body, 280)
	library.add_child(_make_label("BLUEPRINT LIBRARY", 14, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	var library_scroll := ScrollContainer.new()
	library_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	library_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	library.add_child(library_scroll)
	_blueprint_list = VBoxContainer.new()
	_blueprint_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_blueprint_list.add_theme_constant_override("separation", 8)
	library_scroll.add_child(_blueprint_list)
	_add_rule(library)
	library.add_child(_make_label("CARRIER INVENTORY", 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	_inventory = _make_label("", 10, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_inventory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	library.add_child(_inventory)
	var feed := _panel_column(body, 480, true)
	var feed_header := HBoxContainer.new()
	feed.add_child(feed_header)
	var feed_heading := _make_label("● LIVE / CHAMBER 01", 12, CYAN_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	feed_heading.size_flags_horizontal = SIZE_EXPAND_FILL
	feed_header.add_child(feed_heading)
	_shield_readout = _make_label("", 11, CYAN_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	feed_header.add_child(_shield_readout)
	var container := SubViewportContainer.new()
	container.name = "LiveChamberFeed"
	container.stretch = true
	container.size_flags_horizontal = SIZE_EXPAND_FILL
	container.size_flags_vertical = SIZE_EXPAND_FILL
	container.custom_minimum_size.y = 280
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_child(container)
	_viewport = SubViewport.new()
	_viewport.name = "ReplicatorCameraViewport"
	_viewport.size = Vector2i(960, 600)
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	_chamber = CHAMBER.instantiate()
	_viewport.add_child(_chamber)
	_update_shield_readout()
	_camera_status = _make_label("", 16, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	feed.add_child(_camera_status)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 8
	_progress.show_percentage = false
	_progress.add_theme_stylebox_override("fill", _make_style(AMBER_COLOR, Color.TRANSPARENT, 0))
	feed.add_child(_progress)
	_stage_label = _make_label("", 11, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	feed.add_child(_stage_label)
	_transfer_status = _make_label("AUTOMATIC TRANSFER / PLATFORM READY", 11, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	feed.add_child(_transfer_status)
	var details := _panel_column(body, 300)
	details.add_child(_make_label("SELECTED PATTERN", 11, CYAN_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	_detail_name = _make_label("", 25, TEXT_COLOR)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_detail_name)
	_detail_description = _make_label("", 16, STATUS_COLOR)
	_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_detail_description)
	_add_rule(details)
	_detail_cost = _make_label("", 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	details.add_child(_detail_cost)
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	details.add_child(spacer)
	details.add_child(_make_label("ORDER QUANTITY", 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	var quantity_row := HBoxContainer.new()
	details.add_child(quantity_row)
	var minus := _make_stepper_button("−")
	minus.pressed.connect(_change_quantity.bind(-1))
	quantity_row.add_child(minus)
	_quantity_label = _make_label("1", 18, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
	_quantity_label.size_flags_horizontal = SIZE_EXPAND_FILL
	quantity_row.add_child(_quantity_label)
	var plus := _make_stepper_button("+")
	plus.pressed.connect(_change_quantity.bind(1))
	quantity_row.add_child(plus)
	_queue_button = _action_button("ADD TO BUILD QUEUE")
	_queue_button.pressed.connect(_on_add_to_queue_pressed)
	details.add_child(_queue_button)
	_queue_reason = _make_label("", 10, AMBER_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_queue_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_queue_reason.custom_minimum_size.y = 44
	details.add_child(_queue_reason)
	var queue_panel := _panel_column(column, 0)
	queue_panel.add_child(_make_label("BUILD QUEUE / MATERIALS COMMITTED ON ORDER", 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	var queue_scroll := ScrollContainer.new()
	queue_scroll.custom_minimum_size.y = 100
	queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	queue_panel.add_child(queue_scroll)
	_queue_rows = VBoxContainer.new()
	_queue_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	queue_scroll.add_child(_queue_rows)
	_feedback_label = _make_label("", 11, CYAN_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	column.add_child(_feedback_label)

func _panel_column(parent: Container, width: float, expand: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = SIZE_EXPAND_FILL if expand else SIZE_FILL
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_BG, BORDER_COLOR, 1, 0))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	return column

func _action_button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 42
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", DATA_FONT)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", Color("161000"))
	button.add_theme_color_override("font_hover_color", Color("161000"))
	button.add_theme_stylebox_override("normal", _make_style(AMBER_COLOR, AMBER_COLOR, 1, 12))
	button.add_theme_stylebox_override("hover", _make_style(Color("ffc13d"), AMBER_COLOR, 1, 12))
	button.add_theme_stylebox_override("disabled", _make_style(PANEL_ALT_BG, BORDER_COLOR, 1, 12))
	return button

func _refresh_all(rebuild_library: bool = true) -> void:
	if _resources == null:
		return
	var manager := _manager()
	var stores := get_tree().get_first_node_in_group("carrier_manager")
	_resources.text = "PLASTEEL  %04d   /   CORIUM  %04d" % [int(stores.get("plasteel_units")), int(stores.get("corium_units"))] if stores != null else "CARRIER STORES OFFLINE"
	if manager != null:
		var inventory: Dictionary = manager.inventory_snapshot()
		var aircraft: Dictionary = inventory.airframes
		var kestrels := 0
		var hummingbirds := 0
		for entry: Dictionary in aircraft.airframes.values():
			kestrels += 1 if str(entry.scene) == "res://Aircraft/Aircraft_5.tscn" else 0
			hummingbirds += 1 if str(entry.scene) == "res://Aircraft/Aircraft_11.tscn" else 0
		_inventory.text = "VEHICLES  %02d BAY / %02d FIELD\n%02d / %02d CAPACITY (+%02d BUILDS)\n\nAIRCRAFT  %02d BAY / %02d TOTAL\n%02d KESTREL / %02d HUMMINGBIRD\n%02d / %02d CAPACITY (+%02d BUILDS)\n\nSTORES\n%04d BOMBS / %04d ROCKETS\n%04d 10 MM ROUNDS\n%04d 10 MM GUNS" % [inventory.stored, inventory.deployed, inventory.stored + inventory.deployed + inventory.reserved, inventory.capacity, inventory.reserved, aircraft.stored, aircraft.total, kestrels, hummingbirds, aircraft.total + aircraft.reserved, aircraft.capacity, aircraft.reserved, inventory.ordnance.bombs, inventory.ordnance.rockets, inventory.ordnance.bullets, inventory.ordnance.gun_10mm]
	else:
		_inventory.text = "CARRIER INVENTORY OFFLINE"
	if rebuild_library:
		_rebuild_blueprints()
	_refresh_detail()
	_rebuild_queue()

func _rebuild_blueprints() -> void:
	_clear_children(_blueprint_list)
	for category in _filter_buttons:
		(_filter_buttons[category] as Button).add_theme_color_override("font_color", CYAN_COLOR if category == _filter_category else STATUS_COLOR)
	for blueprint in BLUEPRINTS:
		if _filter_category != "ALL" and str(blueprint.category) != _filter_category:
			continue
		var button := Button.new()
		var manager := _manager()
		var known: bool = manager.known_blueprints.has(str(blueprint.id)) if manager != null else CATALOG.STARTER_IDS.has(str(blueprint.id))
		button.text = "%s\n%s\n%03d P / %03d C   %s" % [blueprint.name, blueprint.type, blueprint.plasteel, blueprint.corium, "AVAILABLE" if known else "LOCKED"]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 78
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", DATA_FONT)
		button.add_theme_font_size_override("font_size", 10)
		button.add_theme_stylebox_override("normal", _make_style(SELECTED_BG if blueprint.id == _selected_blueprint_id else PANEL_ALT_BG, CYAN_COLOR if blueprint.id == _selected_blueprint_id else BORDER_COLOR, 1, 8))
		button.pressed.connect(_on_blueprint_pressed.bind(str(blueprint.id)))
		_blueprint_list.add_child(button)

func _selected_blueprint() -> Dictionary:
	for blueprint in BLUEPRINTS:
		if blueprint.id == _selected_blueprint_id:
			return blueprint
	return BLUEPRINTS[0]

func _refresh_detail() -> void:
	var blueprint := _selected_blueprint()
	_detail_name.text = str(blueprint.name)
	_detail_description.text = str(blueprint.description)
	_detail_cost.text = "%d PLASTEEL\n%d CORIUM\n%s / BUILD\nOUTPUT: %d\nDELIVERY: %s" % [int(blueprint.plasteel) * _quantity, int(blueprint.corium) * _quantity, _format_duration(int(blueprint.duration_s)), int(blueprint.output_count) * _quantity, str(blueprint.destination)]
	_quantity_label.text = str(_quantity)
	var manager := _manager()
	var reason: String = manager.order_blocker(_selected_blueprint_id, _quantity) if manager != null else "CARRIER STORES OFFLINE"
	_queue_button.disabled = not reason.is_empty()
	_queue_reason.text = reason if not reason.is_empty() else ("MATERIALS RESERVED ON ORDER" if str(blueprint.category) == "ORDNANCE" else "MATERIALS AND DESTINATION SPACE RESERVED ON ORDER")
	if manager != null and not manager.queue.is_empty():
		var active_recipe := CATALOG.recipe(str(manager.queue[0].recipe))
		_transfer_status.text = "AUTOMATIC PLATFORM TRANSFER TO %s" % str(active_recipe.destination)
	else:
		_transfer_status.text = "AUTOMATIC TRANSFER / PLATFORM READY"

func _update_chamber_labels(state: Dictionary) -> void:
	_camera_status.text = str(state.phase).to_upper().replace("_", " ")
	if str(state.phase) == "ready":
		_camera_status.text = "COMPLETE / WAITING FOR DESTINATION SPACE"
	elif str(state.phase) == "stowing":
		_camera_status.text = "COMPLETE / STOWING FABRICATION ARM"
	elif str(state.phase) == "rollout":
		_camera_status.text = "AUTOMATIC PLATFORM TRANSFER"
	elif str(state.phase) == "returning":
		_camera_status.text = "EMPTY PLATFORM RETURNING"
	elif str(state.phase) == "transfer_wait":
		_camera_status.text = "TRANSFER HELD / WAITING FOR DESTINATION SPACE"
	elif not bool(state.get("powered", true)):
		_camera_status.text = "PAUSED / POWER OR REPLICATOR OFFLINE"
	if not str(state.get("delivery_blocker", "")).is_empty():
		_transfer_status.text = str(state.delivery_blocker)
	_progress.value = float(state.progress) * 100.0
	var stage := int(state.stage)
	var stages: Array = state.get("stages", CATALOG.VEHICLE_STAGES)
	_stage_label.text = "PAD CLEAR / AWAITING BUILD ORDER" if stage < 0 else "STAGE %d / 5  —  %s    %03d%%" % [stage + 1, stages[stage], int(float(state.progress) * 100.0)]

func _rebuild_queue() -> void:
	_clear_children(_queue_rows)
	var manager := _manager()
	if manager == null or manager.queue.is_empty():
		_queue_rows.add_child(_make_label("NO BUILD ORDERS / SELECT A BLUEPRINT TO BEGIN", 11, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
		return
	for index in range(manager.queue.size()):
		var order: Dictionary = manager.queue[index]
		var recipe := CATALOG.recipe(str(order.recipe))
		var row := HBoxContainer.new()
		_queue_rows.add_child(row)
		var label := _make_label("%02d  %s    %s    %03d%%" % [index + 1, str(recipe.name), str(manager.phase).to_upper() if index == 0 else "QUEUED", int(float(order.elapsed) / float(recipe.duration_s) * 100.0)], 11, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(label)
		var cancel := _make_filter_button("CANCEL")
		cancel.tooltip_text = "Refunds unbuilt materials. Completed items transfer automatically."
		cancel.disabled = index == 0 and str(manager.phase) in ["stowing", "opening", "ready", "rollout", "transfer_wait"]
		cancel.pressed.connect(_on_cancel_order_pressed.bind(int(order.id)))
		row.add_child(cancel)

func _on_filter_pressed(category: String) -> void:
	_filter_category = category
	_refresh_all()

func _on_blueprint_pressed(blueprint_id: String) -> void:
	_selected_blueprint_id = blueprint_id
	_quantity = 1
	_refresh_all()

func _change_quantity(amount: int) -> void:
	_quantity = clampi(_quantity + amount, 1, 8)
	_refresh_detail()

func _on_add_to_queue_pressed() -> void:
	var manager := _manager()
	if manager == null:
		return
	var reason: String = manager.place_order(_selected_blueprint_id, _quantity)
	_feedback_label.text = "%d BUILD(S) QUEUED / %s" % [_quantity, str(_selected_blueprint().name)] if reason.is_empty() else reason
	_quantity = 1
	_refresh_all()

func _on_cancel_order_pressed(order_id: int) -> void:
	var manager := _manager()
	if manager != null and manager.cancel_order(order_id):
		_feedback_label.text = "ORDER CANCELLED / UNBUILT MATERIALS RETURNED TO STORES"
	_refresh_all()

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
