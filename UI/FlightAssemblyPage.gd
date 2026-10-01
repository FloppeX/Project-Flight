extends "res://UI/OperationalUnitsPage.gd"
## The flight list stays in place while the right panel changes task.
const TOKEN = preload("res://UI/AircraftAssemblyCard.gd")
const DROP_TARGET = preload("res://UI/FlightAssemblyDropTarget.gd")
const ASSEMBLY = preload("res://AirOps/FlightAssembly.gd")
var _workspace: VBoxContainer
var _workspace_title: Label
var _workspace_hint: Label
var _notice: Label
var _mode_buttons: Dictionary = {}
var _mode := "AIRCRAFT"
var _selected_airframe := ""
var _snapshot: Array[Dictionary] = []
var _content_row: HBoxContainer
var _left_side: VBoxContainer
var _right_side: VBoxContainer
var _card_outline_cache: Dictionary = {}

func _assembly() -> Node:
	return get_node_or_null("/root/AirOpsManager/FlightAssembly")

func _build_flights_ui() -> void:
	var background := ColorRect.new()
	background.color = PAGE_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var console_header := ColorRect.new()
	console_header.color = PANEL_BG
	console_header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	console_header.offset_top = -64
	console_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(console_header)
	var console_title := _make_label("CARRIER COMMAND", 24, TEXT_COLOR)
	console_title.position = Vector2(32, -53)
	add_child(console_title)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title_label = _make_label("FLIGHT ASSEMBLY", 28, TEXT_COLOR)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	_summary_label = _make_label("AWAITING CARRIER", 13, CYAN_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	header.add_child(_summary_label)
	_subtitle_label = _make_label("ONE TOKEN = ONE AIRCRAFT   /   ONE TYPE AND LOADOUT PER FLIGHT", 12, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	column.add_child(_subtitle_label)
	_content_row = HBoxContainer.new()
	_content_row.add_theme_constant_override("separation", 20)
	_content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_content_row)
	_left_side = VBoxContainer.new()
	_left_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_side.size_flags_stretch_ratio = 1.2
	_content_row.add_child(_left_side)
	_left_side.add_child(_make_label("YOUR FLIGHTS", 14, STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left_side.add_child(scroll)
	_flight_rows = VBoxContainer.new()
	_flight_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flight_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_flight_rows)
	_right_side = VBoxContainer.new()
	_right_side.custom_minimum_size.x = 490
	_right_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_row.add_child(_right_side)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	_right_side.add_child(tabs)
	for mode in ["AIRCRAFT", "LOADOUT", "PILOTS"]:
		var button := _action(mode, func(): _mode = mode; _refresh(true))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_mode_buttons[mode] = button
		tabs.add_child(button)
	_workspace_title = _make_label("AVAILABLE AIRCRAFT", 23, TEXT_COLOR)
	_right_side.add_child(_workspace_title)
	_workspace_hint = _make_label("", 13, STATUS_COLOR)
	_workspace_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right_side.add_child(_workspace_hint)
	var workspace_scroll := ScrollContainer.new()
	workspace_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right_side.add_child(workspace_scroll)
	_workspace = VBoxContainer.new()
	_workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace.add_theme_constant_override("separation", 10)
	workspace_scroll.add_child(_workspace)
	_notice = _make_label("Drag an aircraft onto a flight, or select a token and click an empty slot.  LB / RB: main tabs", 13, STATUS_COLOR)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_notice)
	_selected_unit = "Archer"

func _action(caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 36
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", DATA_FONT)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_stylebox_override("normal", _make_style(PANEL_ALT_BG, BORDER_COLOR, 1, 8.0))
	button.add_theme_stylebox_override("hover", _make_style(Color("293735"), CYAN_COLOR, 1, 8.0))
	button.add_theme_stylebox_override("pressed", _make_style(Color("344a47"), CYAN_COLOR, 1, 8.0))
	button.pressed.connect(callback)
	return button

func _refresh(force: bool) -> void:
	var assembly := _assembly()
	if assembly == null or _workspace == null:
		return
	if not visible and not force:
		return
	if get_viewport().gui_is_dragging():
		return
	if not force and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or bool(get_node("/root/CarrierConsole").get("_cursor_a_pressed"))):
		return
	_snapshot = assembly.inventory()
	var signature := str([_snapshot, assembly.plans, _mode, _selected_unit, _selected_airframe, PilotRoster.get_carrier_roster(), get_viewport_rect().size.x >= 1600])
	if not force and signature == _last_signature:
		return
	_last_signature = signature
	_clear_children(_flight_rows)
	_clear_children(_workspace)
	var ready := 0
	var repairing := 0
	var deployed := 0
	var total := 0
	for item in _snapshot:
		if item.state == "LOST": continue
		total += 1
		if not item.editable: deployed += 1
		elif item.state == "READY": ready += 1
		elif item.seconds > 0: repairing += 1
	_summary_label.text = "%d AIRCRAFT   ·   %d READY   ·   %d REPAIRING   ·   %d OUT" % [total, ready, repairing, deployed]
	for flight in AirOpsManager.get_flight_names():
		_build_flight(flight, assembly)
	for mode in _mode_buttons:
		_mode_buttons[mode].modulate = CYAN_COLOR if mode == _mode else Color.WHITE
	match _mode:
		"AIRCRAFT": _build_pool(assembly)
		"LOADOUT": _build_loadouts(assembly)
		"PILOTS": _build_pilots(assembly)

func _build_flight(flight: String, assembly: Node) -> void:
	var target := DROP_TARGET.new()
	target.assembly = assembly
	target.flight_name = flight
	target.assigned.connect(_assign)
	target.add_theme_stylebox_override("panel", _make_style(PANEL_BG, CYAN_COLOR if flight == _selected_unit else BORDER_COLOR, 1, 12.0))
	_flight_rows.add_child(target)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override("separation", 8)
	target.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _action(flight.to_upper(), func(): _selected_unit = flight; _refresh(true))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var p: Dictionary = assembly.plan(flight)
	var members: Array[Dictionary] = []
	for item in _snapshot:
		if item.flight == flight: members.append(item)
	if assembly.plans.has(flight):
		members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return p.ids.find(a.id) < p.ids.find(b.id))
	var active := false
	for item in members:
		active = active or (not item.editable and item.state != "LOST")
	var managed: bool = assembly.plans.has(flight)
	var readiness := "AUTO" if not managed else ("HELD" if p.hold else "AVAILABLE TO AIROPS")
	var permission := _action(readiness, func(): _result(assembly.set_hold(flight, not bool(p.hold))))
	permission.disabled = not managed or active
	permission.tooltip_text = "Hold while assembling. Available flights can be launched by AirOps or tactical orders."
	header.add_child(permission)
	var type_name := "Choose an aircraft type by filling the first slot"
	if not str(p.scene).is_empty(): type_name = str(assembly.model_info(p.scene).name)
	elif not members.is_empty(): type_name = str(members[0].model.name)
	var detail := _make_label("%s  ·  %d/%d  ·  %s" % [type_name, members.size(), ASSEMBLY.MAX_SIZE, ASSEMBLY.PRESETS.get(p.loadout, p.loadout)], 12, STATUS_COLOR)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail)
	var row := _card_grid()
	column.add_child(row)
	for item in members:
		row.add_child(_token(item, true))
	for index in range(maxi(ASSEMBLY.MAX_SIZE - members.size(), 0)):
		var slot := _action("+\nADD AIRCRAFT", func():
			_selected_unit = flight
			if _selected_airframe.is_empty():
				_mode = "AIRCRAFT"
				_notice.text = "Select an aircraft from the pool, then click an empty slot."
				_refresh(true)
			else: _assign(_selected_airframe, flight))
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.custom_minimum_size = Vector2(300, 70)
		slot.disabled = active
		# Let drops over empty slots reach the flight's panel.
		slot.set_drag_forwarding(Callable(), func(at: Vector2, data: Variant): return target._can_drop_data(at, data), func(at: Vector2, data: Variant): target._drop_data(at, data))
		row.add_child(slot)

func _token(item: Dictionary, flight_card: bool = false) -> Button:
	var button := TOKEN.new()
	button.record = item
	button.pool_card = not flight_card
	button.airframe_id = str(item.id)
	button.draggable = item.editable and not item.model.helicopter
	button.selected = item.id == _selected_airframe
	button.custom_minimum_size = Vector2(300, 240) if flight_card else Vector2(240, 160)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.outline = _card_outline(str(item.model.outline))
	for pilot in PilotRoster.get_carrier_roster():
		if str(pilot.id) == str(item.pilot_id):
			button.pilot_name = str(pilot.callsign).to_upper()
			button.portrait = _get_portrait_texture(str(pilot.get("portrait_path", "")))
			break
	button.tooltip_text = "%s\nAirframe %s\nPilot: %s\n%s\nStructure: remaining airframe health\n%s" % [item.model.name, str(item.id).to_upper(), button.pilot_name, item.state, "Drag or select, then click a flight slot." if button.draggable else "Configuration available after return to hangar."]
	if item.get("payload", {}).is_empty():
		button.tooltip_text += "\nLoadout shows planned equipment; ammunition is shown once mounted."
	button.pressed.connect(func():
		_selected_airframe = str(item.id)
		if not str(item.flight).is_empty(): _selected_unit = str(item.flight)
		_refresh(true))
	return button

func _card_outline(path: String) -> Texture2D:
	if _card_outline_cache.has(path): return _card_outline_cache[path]
	var source := _get_aircraft_outline_texture(path)
	if source == null: return null
	var pixels := source.get_image()
	if pixels.is_compressed(): pixels.decompress()
	var bounds := pixels.get_used_rect()
	if bounds.has_area():
		var cropped := AtlasTexture.new()
		cropped.atlas = source
		cropped.region = Rect2(bounds)
		_card_outline_cache[path] = cropped
	else:
		_card_outline_cache[path] = source
	return _card_outline_cache[path]

func _card_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3 if get_viewport_rect().size.x >= 1600 else 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	return grid
func _build_pool(assembly: Node) -> void:
	_workspace_title.text = "AVAILABLE AIRCRAFT"
	_workspace_hint.text = "Select or drag into %s. Each silhouette is one airframe. Repairs finish automatically in the hangar." % _selected_unit.to_upper()
	var pool: Dictionary = {}
	for item in _snapshot:
		if str(item.flight).is_empty():
			if not pool.has(item.scene): pool[item.scene] = []
			pool[item.scene].append(item)
	if pool.is_empty():
		_workspace.add_child(_make_label("No unassigned aircraft aboard.", 17, DIM_COLOR))
	for model in pool:
		var items: Array = pool[model]
		var ready := 0
		var repairs := 0
		for item in items:
			if item.state == "READY": ready += 1
			if item.seconds > 0: repairs += 1
		var caption := _make_label("%s  ·  %d AIRCRAFT / %d READY / %d REPAIRING" % [items[0].model.name, items.size(), ready, repairs], 13, STATUS_COLOR)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_workspace.add_child(caption)
		if items[0].model.helicopter:
			_workspace.add_child(_make_label("UTILITY / RESCUE POOL", 11, DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
		var grid := _card_grid()
		_workspace.add_child(grid)
		for item in items: grid.add_child(_token(item))
	if not _selected_airframe.is_empty():
		var actions := HBoxContainer.new()
		_workspace.add_child(actions)
		actions.add_child(_action("ASSIGN TO " + _selected_unit.to_upper(), func(): _assign(_selected_airframe, _selected_unit)))
		actions.add_child(_action("RETURN TO POOL", func(): _result(assembly.unassign(_selected_airframe))))
		_workspace.add_child(_action("CHOOSE PILOT FOR SELECTED AIRCRAFT", func(): _mode = "PILOTS"; _refresh(true)))

func _build_loadouts(assembly: Node) -> void:
	_workspace_title.text = _selected_unit.to_upper() + " / LOADOUT"
	_workspace_hint.text = "One loadout equips the entire flight. Changing it holds the flight for review."
	var p: Dictionary = assembly.plan(_selected_unit)
	if str(p.scene).is_empty():
		_workspace.add_child(_make_label("Assign the first aircraft to choose a loadout.", 16, DIM_COLOR))
		return
	var descriptions := {"gun_only": "Guns only. External stores removed for air combat.", "rocket_strike": "Rocket pods on compatible external stations, with guns retained.", "bomb_strike": "Bomb racks on compatible external stations, with guns retained."}
	for profile in assembly.model_info(p.scene).presets:
		var button := _action(("✓  " if p.loadout == profile else "") + ASSEMBLY.PRESETS[profile], func(): _result(assembly.configure_loadout(_selected_unit, profile)))
		button.custom_minimum_size.y = 58
		_workspace.add_child(button)
		var label := _make_label(descriptions[profile], 14, STATUS_COLOR)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_workspace.add_child(label)

func _build_pilots(assembly: Node) -> void:
	_workspace_title.text = _selected_unit.to_upper() + " / PILOTS"
	_workspace_hint.text = "Select an aircraft token on the left, then choose its pilot. Reserved pilots stay with their aircraft."
	_workspace.add_child(_action("AUTO-ASSIGN AVAILABLE PILOTS TO FLIGHT", func(): _result(assembly.auto_assign_pilots(_selected_unit))))
	if _selected_airframe.is_empty():
		_workspace.add_child(_make_label("Select an aircraft to assign an individual pilot.", 15, DIM_COLOR))
		return
	_workspace.add_child(_make_label("SELECTED AIRCRAFT · " + _selected_airframe.right(5).to_upper(), 13, CYAN_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT))
	for pilot in PilotRoster.get_carrier_roster():
		var row := HBoxContainer.new()
		_workspace.add_child(row)
		var portrait := TextureRect.new()
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(48, 52)
		if ResourceLoader.exists(str(pilot.get("portrait_path", ""))): portrait.texture = load(str(pilot.portrait_path))
		row.add_child(portrait)
		var button := _action("%s  /  %s\n%s · %s" % [str(pilot.callsign).to_upper(), pilot.get("name", ""), pilot.get("skill", ""), str(pilot.status).to_upper()], func(): _result(assembly.assign_pilot(_selected_airframe, str(pilot.id))))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not PilotRoster.can_reserve_for_airframe(str(pilot.id), _selected_airframe)
		row.add_child(button)

func _assign(id: String, flight: String) -> void:
	_selected_unit = flight
	_selected_airframe = id
	_result(_assembly().assign(id, flight))

func _result(error: String) -> void:
	_notice.text = error if not error.is_empty() else "Assignment saved. Review pilots and loadout, then make the flight available to AirOps."
	_notice.modulate = RED_COLOR if not error.is_empty() else CYAN_COLOR
	_refresh(true)

func get_debug_snapshot() -> Dictionary:
	return {"kind": "flights", "layout": "assembly", "unit_count": AirOpsManager.get_flight_names().size(), "selected_unit": _selected_unit, "inventory": _snapshot, "mode": _mode}
