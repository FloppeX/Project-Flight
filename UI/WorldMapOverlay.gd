extends CanvasLayer

const PIXEL_FONT: FontFile = preload("res://UI/Pixel.ttf")
const MAP_MARGIN_PX: float = 24.0
const PANEL_GAP_PX: float = 18.0
const HEADER_HEIGHT_PX: float = 62.0
const LEFT_PANEL_WIDTH_PX: float = 290.0
const RIGHT_PANEL_WIDTH_PX: float = 290.0
const MIN_MAP_SIDE_PX: float = 320.0
const SECTION_GAP_PX: float = 14.0
const BUTTON_HEIGHT_PX: float = 34.0
const CAP_LOOP_HALF_SIDE_M: float = 900.0
const FLIGHT_CAP_ALTITUDE_M: float = 500.0
const FLIGHT_CAS_RADIUS_M: float = 3000.0
const PLATOON_ATTACK_RADIUS_M: float = 300.0
const PLATOON_PROTECT_RADIUS_M: float = 250.0

const VECTOR_VOID_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
const VECTOR_LOW_COLOR: Color = Color(0.03, 0.10, 0.05, 1.0)
const VECTOR_RAISED_COLOR: Color = Color(0.10, 0.28, 0.11, 1.0)
const VECTOR_HIGH_COLOR: Color = Color(0.20, 0.48, 0.21, 1.0)
const VECTOR_TEXT_COLOR: Color = Color(0.58, 1.0, 0.64, 1.0)
const VECTOR_STATUS_COLOR: Color = Color(0.84, 1.0, 0.86, 1.0)
const VECTOR_PANEL_BG: Color = Color(0.02, 0.05, 0.03, 0.96)
const VECTOR_PANEL_ALT_BG: Color = Color(0.01, 0.04, 0.02, 0.92)
const VECTOR_BORDER_COLOR: Color = Color(0.24, 0.92, 0.42, 0.92)
const VECTOR_AMBER_COLOR: Color = Color(1.0, 0.78, 0.28, 1.0)
const VECTOR_DIM_COLOR: Color = Color(0.38, 0.54, 0.42, 0.9)

enum AssetKind {
	NONE,
	FLIGHT,
	PLATOON,
}

var _root: Control
var _backdrop: ColorRect
var _header_panel: ColorRect
var _header_title: Label
var _header_subtitle: Label

var _left_panel: ColorRect
var _asset_title: Label
var _asset_scroll: ScrollContainer
var _asset_list: VBoxContainer
var _mission_title: Label
var _mission_list: VBoxContainer
var _draft_title: Label
var _draft_summary: Label
var _confirm_button: Button
var _cancel_button: Button

var _center_panel: ColorRect
var _map_frame: ColorRect
var _map_rect: TextureRect
var _map_input: Control
var _symbol_layer: Control
var _map_meta: Label
var _map_hint: Label
var _map_status: Label

var _right_panel: ColorRect
var _info_title: Label
var _info_body: Label
var _command_prompt: Label

var _map_texture: ImageTexture = null
var _map_ready: bool = false

var _asset_buttons: Array = []
var _mission_buttons: Array = []
var _mission_signature: String = ""
var _selected_asset_kind: AssetKind = AssetKind.NONE
var _selected_asset_name: String = ""
var _selected_mission_id: String = ""
var _draft_points: Array[Vector3] = []
var _ui_refresh_timer_s: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 190
	set_process(true)
	set_process_input(true)
	_build_ui()
	_rebuild_asset_buttons()
	_rebuild_mission_buttons()
	_refresh_ui(true)
	_set_open(false)
	if TerrainNavGrid.is_ready():
		call_deferred("_ensure_map_texture")
	else:
		TerrainNavGrid.bake_complete.connect(_on_navgrid_bake_complete, CONNECT_ONE_SHOT)

func _process(delta: float) -> void:
	if _root == null or not _root.visible:
		return
	_ui_refresh_timer_s -= delta
	if _ui_refresh_timer_s <= 0.0:
		_refresh_ui()
		_ui_refresh_timer_s = 0.2

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("map_toggle"):
		return
	if event is InputEventKey and event.echo:
		return
	_set_open(not _root.visible)
	get_viewport().set_input_as_handled()

func _on_navgrid_bake_complete() -> void:
	if _root.visible:
		_ensure_map_texture()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.01, 0.0, 0.95)
	_root.add_child(_backdrop)

	_header_panel = _make_panel(VECTOR_PANEL_BG)
	_root.add_child(_header_panel)
	_header_title = _make_label("TACTICAL COMMAND GRID", 28, VECTOR_TEXT_COLOR)
	_header_panel.add_child(_header_title)
	_header_subtitle = _make_label("SYS_VER 9.4.1 // PLAYER OPS UPLINK ACTIVE", 12, VECTOR_STATUS_COLOR)
	_header_panel.add_child(_header_subtitle)

	_left_panel = _make_panel(VECTOR_PANEL_BG)
	_root.add_child(_left_panel)
	_asset_title = _make_label("ASSET SELECTION", 16, VECTOR_AMBER_COLOR)
	_left_panel.add_child(_asset_title)
	_asset_scroll = ScrollContainer.new()
	_asset_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_asset_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_left_panel.add_child(_asset_scroll)
	_asset_list = VBoxContainer.new()
	_asset_list.add_theme_constant_override("separation", 8)
	_asset_scroll.add_child(_asset_list)

	_mission_title = _make_label("MISSION DIRECTIVES", 16, VECTOR_AMBER_COLOR)
	_left_panel.add_child(_mission_title)
	_mission_list = VBoxContainer.new()
	_mission_list.add_theme_constant_override("separation", 8)
	_left_panel.add_child(_mission_list)

	_draft_title = _make_label("ORDER DRAFT", 16, VECTOR_AMBER_COLOR)
	_left_panel.add_child(_draft_title)
	_draft_summary = _make_label("", 12, VECTOR_STATUS_COLOR)
	_draft_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_panel.add_child(_draft_summary)

	_confirm_button = _make_button("CONFIRM", VECTOR_TEXT_COLOR)
	_confirm_button.pressed.connect(_confirm_draft)
	_left_panel.add_child(_confirm_button)
	_cancel_button = _make_button("CANCEL", VECTOR_AMBER_COLOR)
	_cancel_button.pressed.connect(_cancel_draft)
	_left_panel.add_child(_cancel_button)

	_center_panel = _make_panel(VECTOR_PANEL_ALT_BG)
	_root.add_child(_center_panel)
	_map_frame = _make_panel(Color(0.01, 0.07, 0.03, 0.98))
	_center_panel.add_child(_map_frame)
	_map_rect = TextureRect.new()
	_map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_panel.add_child(_map_rect)
	_map_input = Control.new()
	_map_input.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_input.gui_input.connect(_on_map_gui_input)
	_center_panel.add_child(_map_input)
	_symbol_layer = preload("res://UI/WorldMapSymbolLayer.gd").new()
	_center_panel.add_child(_symbol_layer)
	_map_meta = _make_label("ZOOM: 1.0x\nELEV: TOPOGRAPHIC", 14, VECTOR_STATUS_COLOR)
	_center_panel.add_child(_map_meta)
	_map_hint = _make_label("", 12, VECTOR_STATUS_COLOR)
	_map_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_center_panel.add_child(_map_hint)
	_map_status = _make_label("", 18, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_map_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_panel.add_child(_map_status)

	_right_panel = _make_panel(VECTOR_PANEL_BG)
	_root.add_child(_right_panel)
	_info_title = _make_label("UNIT INFORMATION", 16, VECTOR_AMBER_COLOR)
	_right_panel.add_child(_info_title)
	_info_body = _make_label("", 14, VECTOR_TEXT_COLOR)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right_panel.add_child(_info_body)
	_command_prompt = _make_label("CMD> AWAITING INPUT...", 16, VECTOR_TEXT_COLOR)
	_right_panel.add_child(_command_prompt)

	_root.resized.connect(_layout_ui)
	_layout_ui()

func _layout_ui() -> void:
	if _root == null:
		return
	var size: Vector2 = _root.size
	var header_rect := Rect2(
		Vector2(MAP_MARGIN_PX, MAP_MARGIN_PX),
		Vector2(size.x - MAP_MARGIN_PX * 2.0, HEADER_HEIGHT_PX)
	)
	_header_panel.position = header_rect.position
	_header_panel.size = header_rect.size
	_header_title.position = Vector2(18.0, 10.0)
	_header_title.size = Vector2(header_rect.size.x - 36.0, 28.0)
	_header_subtitle.position = Vector2(18.0, 38.0)
	_header_subtitle.size = Vector2(header_rect.size.x - 36.0, 16.0)

	var body_top: float = header_rect.end.y + PANEL_GAP_PX
	var body_height: float = size.y - body_top - MAP_MARGIN_PX
	var left_x: float = MAP_MARGIN_PX
	var center_x: float = left_x + LEFT_PANEL_WIDTH_PX + PANEL_GAP_PX
	var right_x: float = size.x - MAP_MARGIN_PX - RIGHT_PANEL_WIDTH_PX
	var center_width: float = maxf(right_x - center_x - PANEL_GAP_PX, MIN_MAP_SIDE_PX + 48.0)

	_left_panel.position = Vector2(left_x, body_top)
	_left_panel.size = Vector2(LEFT_PANEL_WIDTH_PX, body_height)

	_center_panel.position = Vector2(center_x, body_top)
	_center_panel.size = Vector2(center_width, body_height)

	_right_panel.position = Vector2(right_x, body_top)
	_right_panel.size = Vector2(RIGHT_PANEL_WIDTH_PX, body_height)

	var left_inner_x: float = 18.0
	var left_inner_w: float = _left_panel.size.x - left_inner_x * 2.0
	var left_y: float = 16.0
	_asset_title.position = Vector2(left_inner_x, left_y)
	_asset_title.size = Vector2(left_inner_w, 20.0)
	left_y += 28.0
	var asset_height: float = clampf(_left_panel.size.y * 0.42, 180.0, 340.0)
	_asset_scroll.position = Vector2(left_inner_x, left_y)
	_asset_scroll.size = Vector2(left_inner_w, asset_height)
	_asset_list.custom_minimum_size = Vector2(left_inner_w - 12.0, 0.0)
	left_y += asset_height + SECTION_GAP_PX
	_mission_title.position = Vector2(left_inner_x, left_y)
	_mission_title.size = Vector2(left_inner_w, 20.0)
	left_y += 28.0
	var mission_height: float = clampf(_left_panel.size.y * 0.24, 120.0, 220.0)
	_mission_list.position = Vector2(left_inner_x, left_y)
	_mission_list.size = Vector2(left_inner_w, mission_height)
	left_y += mission_height + SECTION_GAP_PX
	_draft_title.position = Vector2(left_inner_x, left_y)
	_draft_title.size = Vector2(left_inner_w, 20.0)
	left_y += 24.0
	var remaining_h: float = _left_panel.size.y - left_y - BUTTON_HEIGHT_PX * 2.0 - 18.0
	_draft_summary.position = Vector2(left_inner_x, left_y)
	_draft_summary.size = Vector2(left_inner_w, maxf(remaining_h, 56.0))
	_confirm_button.position = Vector2(left_inner_x, _left_panel.size.y - BUTTON_HEIGHT_PX * 2.0 - 12.0)
	_confirm_button.size = Vector2(left_inner_w, BUTTON_HEIGHT_PX)
	_cancel_button.position = Vector2(left_inner_x, _left_panel.size.y - BUTTON_HEIGHT_PX - 6.0)
	_cancel_button.size = Vector2(left_inner_w, BUTTON_HEIGHT_PX)

	var map_side: float = minf(_center_panel.size.x - 36.0, _center_panel.size.y - 88.0)
	map_side = maxf(map_side, MIN_MAP_SIDE_PX)
	var map_pos := Vector2((_center_panel.size.x - map_side) * 0.5, 22.0)
	_map_frame.position = map_pos - Vector2(12.0, 12.0)
	_map_frame.size = Vector2(map_side + 24.0, map_side + 24.0)
	_map_rect.position = map_pos
	_map_rect.size = Vector2(map_side, map_side)
	_map_input.position = map_pos
	_map_input.size = Vector2(map_side, map_side)
	_symbol_layer.position = map_pos
	_symbol_layer.size = Vector2(map_side, map_side)
	_map_meta.position = map_pos + Vector2(14.0, 12.0)
	_map_meta.size = Vector2(180.0, 40.0)
	_map_hint.position = Vector2(map_pos.x + 14.0, map_pos.y + map_side + 18.0)
	_map_hint.size = Vector2(map_side - 28.0, 42.0)
	_map_status.position = _map_rect.position
	_map_status.size = _map_rect.size

	var right_inner_x: float = 18.0
	var right_inner_w: float = _right_panel.size.x - right_inner_x * 2.0
	_info_title.position = Vector2(right_inner_x, 16.0)
	_info_title.size = Vector2(right_inner_w, 22.0)
	_info_body.position = Vector2(right_inner_x, 48.0)
	_info_body.size = Vector2(right_inner_w, _right_panel.size.y - 96.0)
	_command_prompt.position = Vector2(right_inner_x, _right_panel.size.y - 30.0)
	_command_prompt.size = Vector2(right_inner_w, 20.0)

func _set_open(is_open: bool) -> void:
	if _root == null:
		return
	_root.visible = is_open
	if is_open:
		_ensure_map_texture()
		_refresh_ui(true)

func _ensure_map_texture() -> void:
	if _map_ready:
		_map_status.visible = false
		return
	if not TerrainNavGrid.is_ready():
		_map_status.text = "Building terrain map..."
		_map_status.visible = true
		return
	var terrain := get_tree().get_first_node_in_group("terrain_provider") as Node3D
	if terrain == null or not is_instance_valid(terrain):
		_map_status.text = "Terrain not available"
		_map_status.visible = true
		return
	_map_status.text = "Rendering terrain map..."
	_map_status.visible = true
	var img := _build_map_image(terrain)
	if img == null:
		_map_status.text = "Map render failed"
		return
	_map_texture = ImageTexture.create_from_image(img)
	_map_rect.texture = _map_texture
	_map_ready = true
	_map_status.visible = false

func _build_map_image(_terrain: Node3D) -> Image:
	var cols: int = TerrainNavGrid._cols
	var rows: int = TerrainNavGrid._rows
	if cols <= 1 or rows <= 1:
		return null
	var h_ceil: float = TerrainNavGrid._h_min_passable + TerrainNavGrid.low_level_tolerance_m
	var max_slope_m: float = NavGraph.max_slope_m if NavGraph != null else 18.0
	var raised_threshold_y: float = h_ceil + maxf(max_slope_m * 1.5, 24.0)
	var high_threshold_y: float = raised_threshold_y + maxf(max_slope_m * 3.0, 45.0)
	var img := Image.create(cols, rows, false, Image.FORMAT_RGBA8)
	for gz in range(rows):
		for gx in range(cols):
			var idx: int = gz * cols + gx
			var h: float = TerrainNavGrid._heights[idx]
			var color: Color = VECTOR_VOID_COLOR
			if h > TerrainNavGrid.IMPASSABLE * 0.5:
				color = VECTOR_LOW_COLOR
				if h >= high_threshold_y:
					color = VECTOR_HIGH_COLOR
				elif h >= raised_threshold_y:
					color = VECTOR_RAISED_COLOR
			img.set_pixel(gx, gz, color)
	return img

func _rebuild_asset_buttons() -> void:
	_clear_children(_asset_list)
	_asset_buttons.clear()
	for flight_name in AirOpsManager.get_flight_names():
		var button := _make_button("", VECTOR_TEXT_COLOR)
		button.pressed.connect(_select_asset.bind(AssetKind.FLIGHT, flight_name))
		_asset_list.add_child(button)
		_asset_buttons.append({"kind": AssetKind.FLIGHT, "name": flight_name, "button": button})
	for platoon_name in GroundOpsManager.get_platoon_names():
		var button := _make_button("", VECTOR_AMBER_COLOR)
		button.pressed.connect(_select_asset.bind(AssetKind.PLATOON, platoon_name))
		_asset_list.add_child(button)
		_asset_buttons.append({"kind": AssetKind.PLATOON, "name": platoon_name, "button": button})

func _rebuild_mission_buttons() -> void:
	_clear_children(_mission_list)
	_mission_buttons.clear()
	for spec in _get_selected_mission_specs():
		var accent: Color = spec.get("accent", VECTOR_TEXT_COLOR)
		var button := _make_button(spec.get("label", "MISSION"), accent)
		button.pressed.connect(_begin_mission_draft.bind(String(spec.get("id", ""))))
		_mission_list.add_child(button)
		_mission_buttons.append({"id": String(spec.get("id", "")), "button": button, "accent": accent})

func _refresh_ui(force_rebuild: bool = false) -> void:
	if _root == null:
		return
	if force_rebuild:
		_rebuild_asset_buttons()
	var mission_signature := _get_mission_signature()
	if force_rebuild or mission_signature != _mission_signature:
		_mission_signature = mission_signature
		_rebuild_mission_buttons()
	_refresh_asset_button_states()
	_refresh_mission_button_states()
	_refresh_info_panel()
	_refresh_draft_summary()
	_refresh_map_hint()
	_refresh_map_overlays()

func _refresh_asset_button_states() -> void:
	for entry in _asset_buttons:
		var kind: AssetKind = entry["kind"]
		var name: String = entry["name"]
		var button: Button = entry["button"]
		var status := _get_asset_status(kind, name)
		if status.is_empty():
			button.text = name.to_upper()
			button.disabled = true
			_style_button(button, VECTOR_DIM_COLOR, false, true)
			continue
		button.disabled = false
		button.text = _format_asset_button_text(status)
		var accent := VECTOR_TEXT_COLOR if kind == AssetKind.FLIGHT else VECTOR_AMBER_COLOR
		var selected: bool = kind == _selected_asset_kind and name == _selected_asset_name
		_style_button(button, accent, selected, false)

func _refresh_mission_button_states() -> void:
	var specs := _get_selected_mission_specs()
	var status := _get_selected_asset_status()
	for i in range(_mission_buttons.size()):
		var entry = _mission_buttons[i]
		var button: Button = entry["button"]
		var accent: Color = entry["accent"]
		var mission_id: String = entry["id"]
		var spec: Dictionary = specs[i] if i < specs.size() else {}
		var enabled: bool = _is_mission_enabled(spec, status)
		button.disabled = not enabled
		var selected: bool = mission_id == _selected_mission_id
		_style_button(button, accent, selected, not enabled)
	_confirm_button.disabled = not _can_confirm_draft()
	_cancel_button.disabled = _selected_mission_id.is_empty() and _draft_points.is_empty()
	_style_button(_confirm_button, VECTOR_TEXT_COLOR, false, _confirm_button.disabled)
	_style_button(_cancel_button, VECTOR_AMBER_COLOR, false, _cancel_button.disabled)

func _refresh_info_panel() -> void:
	var status := _get_selected_asset_status()
	if status.is_empty():
		_info_body.text = "No asset selected.\n\nPick a flight or platoon on the left, then choose a mission and use the map to place its target."
		_command_prompt.text = "CMD> SELECT ASSET"
		return
	_info_body.text = _format_asset_info(status)
	if _selected_mission_id.is_empty():
		_command_prompt.text = "CMD> %s READY" % _selected_asset_name.to_upper()
	elif _mission_requires_target(_selected_mission_id):
		if _draft_points.is_empty():
			_command_prompt.text = "CMD> %s: PICK MAP TARGET" % _selected_mission_id
		else:
			_command_prompt.text = "CMD> %s: %d POINT%s STAGED" % [_selected_mission_id, _draft_points.size(), "" if _draft_points.size() == 1 else "S"]
	else:
		_command_prompt.text = "CMD> %s READY TO EXECUTE" % _selected_mission_id

func _refresh_draft_summary() -> void:
	if _selected_asset_kind == AssetKind.NONE or _selected_asset_name.is_empty():
		_draft_summary.text = "Select an asset to start drafting an order."
		return
	if _selected_mission_id.is_empty():
		_draft_summary.text = "%s selected.\nChoose a mission directive to begin." % _selected_asset_name.to_upper()
		return
	var lines: Array[String] = []
	lines.append("ASSET: %s" % _selected_asset_name.to_upper())
	lines.append("MISSION: %s" % _selected_mission_id)
	if _mission_requires_target(_selected_mission_id):
		lines.append("TARGETS: %d" % _draft_points.size())
		if _mission_allows_waypoints(_selected_mission_id):
			lines.append("LMB adds route points. RMB removes the last point.")
		elif _draft_points.is_empty():
			lines.append("Click the map to place the target area.")
	else:
		lines.append("No map target required.")
	_draft_summary.text = "\n".join(lines)

func _refresh_map_hint() -> void:
	if not _map_ready and TerrainNavGrid.is_ready():
		_ensure_map_texture()
	if _selected_asset_kind == AssetKind.NONE:
		_map_hint.text = "Select a flight or platoon to issue a command."
		return
	if _selected_mission_id.is_empty():
		_map_hint.text = "Mission console armed. Choose a directive on the left."
		return
	if _mission_requires_target(_selected_mission_id):
		if _mission_allows_waypoints(_selected_mission_id):
			_map_hint.text = "%s draft: left-click to add route points, right-click to remove the last point, then confirm." % _selected_mission_id
		else:
			_map_hint.text = "%s draft: left-click the map to place the target, then confirm." % _selected_mission_id
	else:
		_map_hint.text = "%s ready. Confirm to send the order." % _selected_mission_id

func _refresh_map_overlays() -> void:
	if _symbol_layer == null:
		return
	var status := _get_selected_asset_status()
	if status.is_empty():
		_symbol_layer.call("clear_selection_focus")
		_symbol_layer.call("clear_command_draft")
		return
	var position: Vector3 = status.get("position", Vector3.ZERO)
	var selection_accent := VECTOR_TEXT_COLOR if _selected_asset_kind == AssetKind.FLIGHT else VECTOR_AMBER_COLOR
	_symbol_layer.call("set_selection_focus", position, selection_accent)
	if _selected_mission_id.is_empty() or _draft_points.is_empty():
		_symbol_layer.call("clear_command_draft")
		return
	var draft_preview := _get_draft_preview_points()
	_symbol_layer.call(
		"set_command_draft",
		position,
		draft_preview.get("points", []),
		draft_preview.get("color", VECTOR_AMBER_COLOR),
		draft_preview.get("closed_loop", false)
	)

func _select_asset(kind: AssetKind, asset_name: String) -> void:
	_selected_asset_kind = kind
	_selected_asset_name = asset_name
	_cancel_draft()
	_refresh_ui()

func _begin_mission_draft(mission_id: String) -> void:
	if _selected_asset_kind == AssetKind.NONE or _selected_asset_name.is_empty():
		return
	_selected_mission_id = mission_id
	_draft_points.clear()
	_refresh_ui()

func _confirm_draft() -> void:
	if not _can_confirm_draft():
		return
	match _selected_asset_kind:
		AssetKind.FLIGHT:
			_confirm_flight_order()
		AssetKind.PLATOON:
			_confirm_platoon_order()
		_:
			return
	_selected_mission_id = ""
	_draft_points.clear()
	_refresh_ui()

func _confirm_flight_order() -> void:
	match _selected_mission_id:
		"CAP":
			AirOpsManager.order_cap_route(_selected_asset_name, _draft_points, FLIGHT_CAP_ALTITUDE_M)
		"CAS":
			if _draft_points.is_empty():
				return
			AirOpsManager.order_cas(_selected_asset_name, _draft_points[0], FLIGHT_CAS_RADIUS_M)
		"RTB":
			AirOpsManager.order_rtb(_selected_asset_name)

func _confirm_platoon_order() -> void:
	match _selected_mission_id:
		"MOVE":
			if _draft_points.is_empty():
				return
			GroundOpsManager.order_move(_selected_asset_name, _draft_points[0])
		"ATTACK":
			if _draft_points.is_empty():
				return
			GroundOpsManager.order_attack_position(_selected_asset_name, _draft_points[0], PLATOON_ATTACK_RADIUS_M)
		"PROTECT":
			if _draft_points.is_empty():
				return
			GroundOpsManager.order_protect_position(_selected_asset_name, _draft_points[0], PLATOON_PROTECT_RADIUS_M)
		"ESCORT":
			GroundOpsManager.order_escort(_selected_asset_name)
		"HOLD":
			GroundOpsManager.order_hold(_selected_asset_name)
		"RETRIEVE":
			GroundOpsManager.retrieve(_selected_asset_name)

func _cancel_draft() -> void:
	_selected_mission_id = ""
	_draft_points.clear()
	_refresh_ui()

func _on_map_gui_input(event: InputEvent) -> void:
	if not _root.visible or not _mission_requires_target(_selected_mission_id):
		return
	if event is InputEventMouseButton and event.pressed and not event.double_click:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var world_pos := _map_to_world(mouse_event.position)
			if _mission_allows_waypoints(_selected_mission_id):
				_draft_points.append(world_pos)
			else:
				_draft_points = [world_pos]
			_refresh_ui()
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and not _draft_points.is_empty():
			_draft_points.pop_back()
			_refresh_ui()
			get_viewport().set_input_as_handled()

func _get_selected_asset_status() -> Dictionary:
	return _get_asset_status(_selected_asset_kind, _selected_asset_name)

func _get_asset_status(kind: AssetKind, asset_name: String) -> Dictionary:
	if asset_name.is_empty():
		return {}
	match kind:
		AssetKind.FLIGHT:
			return AirOpsManager.get_flight_status(asset_name)
		AssetKind.PLATOON:
			return GroundOpsManager.get_platoon_status(asset_name)
		_:
			return {}

func _get_selected_mission_specs() -> Array[Dictionary]:
	match _selected_asset_kind:
		AssetKind.FLIGHT:
			return [
				{"id": "CAP", "label": "> CAP", "accent": VECTOR_TEXT_COLOR},
				{"id": "CAS", "label": "> CAS", "accent": VECTOR_AMBER_COLOR},
				{"id": "RTB", "label": "> RTB", "accent": VECTOR_STATUS_COLOR},
			]
		AssetKind.PLATOON:
			return [
				{"id": "MOVE", "label": "> MOVE", "accent": VECTOR_TEXT_COLOR},
				{"id": "ATTACK", "label": "> ATTACK", "accent": VECTOR_AMBER_COLOR},
				{"id": "PROTECT", "label": "> PROTECT", "accent": VECTOR_STATUS_COLOR},
				{"id": "ESCORT", "label": "> ESCORT", "accent": VECTOR_TEXT_COLOR},
				{"id": "HOLD", "label": "> HOLD", "accent": VECTOR_STATUS_COLOR},
				{"id": "RETRIEVE", "label": "> RETRIEVE", "accent": VECTOR_AMBER_COLOR},
			]
		_:
			return []

func _is_mission_enabled(spec: Dictionary, status: Dictionary) -> bool:
	if spec.is_empty() or status.is_empty():
		return false
	var mission_id: String = spec.get("id", "")
	match mission_id:
		"RTB":
			return int(status.get("strength", 0)) > 0
		"RETRIEVE":
			return int(status.get("strength", 0)) > 0
		_:
			return true

func _can_confirm_draft() -> bool:
	if _selected_asset_kind == AssetKind.NONE or _selected_asset_name.is_empty() or _selected_mission_id.is_empty():
		return false
	if _mission_requires_target(_selected_mission_id):
		return not _draft_points.is_empty()
	return true

func _mission_requires_target(mission_id: String) -> bool:
	return mission_id in ["CAP", "CAS", "MOVE", "ATTACK", "PROTECT"]

func _mission_allows_waypoints(mission_id: String) -> bool:
	return mission_id == "CAP"

func _get_draft_preview_points() -> Dictionary:
	var accent := VECTOR_TEXT_COLOR if _selected_asset_kind == AssetKind.FLIGHT else VECTOR_AMBER_COLOR
	if _selected_mission_id == "CAP":
		return {
			"points": _get_cap_route_preview(_draft_points),
			"closed_loop": not _draft_points.is_empty(),
			"color": accent,
		}
	return {
		"points": _draft_points.duplicate(),
		"closed_loop": false,
		"color": accent,
	}

func _get_cap_route_preview(route_points: Array[Vector3]) -> Array[Vector3]:
	if route_points.size() != 1:
		return route_points.duplicate()
	var anchor := route_points[0]
	return [
		Vector3(anchor.x + CAP_LOOP_HALF_SIDE_M, anchor.y, anchor.z + CAP_LOOP_HALF_SIDE_M),
		Vector3(anchor.x - CAP_LOOP_HALF_SIDE_M, anchor.y, anchor.z + CAP_LOOP_HALF_SIDE_M),
		Vector3(anchor.x - CAP_LOOP_HALF_SIDE_M, anchor.y, anchor.z - CAP_LOOP_HALF_SIDE_M),
		Vector3(anchor.x + CAP_LOOP_HALF_SIDE_M, anchor.y, anchor.z - CAP_LOOP_HALF_SIDE_M),
	]

func _map_to_world(local_pos: Vector2) -> Vector3:
	var span_x: float = float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var span_z: float = float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	var u: float = clampf(local_pos.x / maxf(_map_input.size.x, 1.0), 0.0, 1.0)
	var v: float = clampf(local_pos.y / maxf(_map_input.size.y, 1.0), 0.0, 1.0)
	var world_x: float = TerrainNavGrid._origin_x + span_x * u
	var world_z: float = TerrainNavGrid._origin_z + span_z * v
	var world_y: float = TerrainNavGrid.sample_height(world_x, world_z)
	if world_y <= TerrainNavGrid.IMPASSABLE * 0.5:
		world_y = 0.0
	return Vector3(world_x, world_y, world_z)

func _format_asset_button_text(status: Dictionary) -> String:
	var name: String = String(status.get("name", "")).to_upper()
	var strength: int = int(status.get("strength", 0))
	if status.get("kind", "") == "flight":
		var mission: String = String(status.get("mission", "NONE"))
		var role: String = String(status.get("role", "STANDBY"))
		var scramble_tag: String = " SCR" if bool(status.get("is_scrambling", false)) else ""
		return "%s  FLT  %s  %d%s" % [name, role if role != "STANDBY" else mission, strength, scramble_tag]
	var objective: String = String(status.get("objective", "HOLD"))
	var queue_tag: String = " Q" if bool(status.get("queued", false)) else ""
	var bay_tag: String = "" if bool(status.get("deployed", false)) else " BAY"
	return "%s  PLT  %s  %d%s%s" % [name, objective, strength, bay_tag, queue_tag]

func _format_asset_info(status: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(status.get("name", "UNIT").to_upper())
	if status.get("kind", "") == "flight":
		lines.append("TYPE: FLIGHT")
		lines.append("MISSION: %s" % status.get("mission", "NONE"))
		lines.append("ROLE: %s" % status.get("role", "STANDBY"))
		lines.append("STATE: %s" % status.get("lead_state", "INACTIVE"))
		lines.append("STRENGTH: %d" % int(status.get("strength", 0)))
	else:
		lines.append("TYPE: PLATOON")
		lines.append("OBJECTIVE: %s" % status.get("objective", "HOLD"))
		lines.append("DEPLOYED: %s" % ("YES" if bool(status.get("deployed", false)) else "NO"))
		lines.append("QUEUED: %s" % ("YES" if bool(status.get("queued", false)) else "NO"))
		lines.append("STRENGTH: %d" % int(status.get("strength", 0)))
	var pos: Vector3 = status.get("position", Vector3.ZERO)
	lines.append("COORDS: %.0f / %.0f" % [pos.x, pos.z])
	lines.append("WAYPOINTS: %d" % _count_route_points(status))
	if not _selected_mission_id.is_empty():
		lines.append("")
		lines.append("PENDING: %s" % _selected_mission_id)
		if not _draft_points.is_empty():
			lines.append("DRAFT PTS: %d" % _draft_points.size())
	return "\n".join(lines)

func _count_route_points(status: Dictionary) -> int:
	var waypoints_variant = status.get("active_waypoints", [])
	return waypoints_variant.size() if waypoints_variant is Array else 0

func _make_panel(color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = color
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel

func _make_label(text: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	label.add_theme_constant_override("outline_size", 1)
	return label

func _make_button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_override("font", PIXEL_FONT)
	button.add_theme_font_size_override("font_size", 14)
	_style_button(button, accent, false, false)
	return button

func _style_button(button: Button, accent: Color, selected: bool, disabled: bool) -> void:
	var normal_fill := Color(0.02, 0.06, 0.03, 0.98)
	var hover_fill := Color(0.04, 0.11, 0.06, 0.98)
	var pressed_fill := Color(0.08, 0.18, 0.10, 0.98)
	if selected:
		normal_fill = accent.lerp(Color.BLACK, 0.78)
		hover_fill = accent.lerp(Color.BLACK, 0.70)
		pressed_fill = accent.lerp(Color.BLACK, 0.62)
	if disabled:
		normal_fill = Color(0.03, 0.04, 0.03, 0.8)
		hover_fill = normal_fill
		pressed_fill = normal_fill
	var border_color := accent if not disabled else VECTOR_DIM_COLOR
	button.add_theme_stylebox_override("normal", _build_button_style(normal_fill, border_color))
	button.add_theme_stylebox_override("hover", _build_button_style(hover_fill, border_color))
	button.add_theme_stylebox_override("pressed", _build_button_style(pressed_fill, border_color))
	button.add_theme_stylebox_override("disabled", _build_button_style(normal_fill, border_color.lerp(Color.BLACK, 0.45)))
	button.add_theme_color_override("font_color", accent if not disabled else VECTOR_DIM_COLOR)
	button.add_theme_color_override("font_hover_color", accent if not disabled else VECTOR_DIM_COLOR)
	button.add_theme_color_override("font_pressed_color", accent if not disabled else VECTOR_DIM_COLOR)
	button.add_theme_color_override("font_disabled_color", VECTOR_DIM_COLOR)

func _build_button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _get_mission_signature() -> String:
	var ids: Array[String] = []
	for spec in _get_selected_mission_specs():
		ids.append(String(spec.get("id", "")))
	return "%d:%s" % [int(_selected_asset_kind), "|".join(ids)]
