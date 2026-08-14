extends CanvasLayer

const WorldMapTextureBuilder = preload("res://UI/WorldMapTextureBuilder.gd")

const HEADLINE_FONT: FontFile = preload("res://UI/Fonts/ArchivoNarrow-Variable.ttf")
const DATA_FONT: FontFile = preload("res://UI/Fonts/JetBrainsMono-Variable.ttf")
const MAP_MARGIN_PX: float = 0.0
const PANEL_GAP_PX: float = 0.0
const HEADER_HEIGHT_PX: float = 64.0
const FOOTER_HEIGHT_PX: float = 38.0
const LEFT_PANEL_WIDTH_PX: float = 272.0
const RIGHT_PANEL_WIDTH_PX: float = 312.0
const MIN_MAP_SIDE_PX: float = 320.0
const SECTION_GAP_PX: float = 14.0
const BUTTON_HEIGHT_PX: float = 40.0
const ASSET_BUTTON_HEIGHT_PX: float = 48.0
const GRID_COORD_DIVISIONS: int = 8
const GRID_COORD_BAND_HEIGHT_PX: float = 18.0
const GRID_COORD_BAND_WIDTH_PX: float = 18.0
const GRID_COORD_COLUMNS: PackedStringArray = ["A", "B", "C", "D", "E", "F", "G", "H"]
const ROUTE_NODE_HIT_RADIUS_PX: float = 10.0
const ROUTE_SEGMENT_HIT_RADIUS_PX: float = 8.0
const CAP_LOOP_HALF_SIDE_M: float = 900.0
const CAP_ROUTE_PREVIEW_ENTRY_SKIP_DISTANCE_M: float = 140.0
const FLIGHT_CAP_ALTITUDE_M: float = 800.0
const FLIGHT_CAS_RADIUS_M: float = 3000.0
const PLATOON_ATTACK_RADIUS_M: float = 300.0
const PLATOON_PROTECT_RADIUS_M: float = 250.0

const VECTOR_VOID_COLOR: Color = Color("0e0e0e")
const VECTOR_LOW_COLOR: Color = Color("121a18")
const VECTOR_RAISED_COLOR: Color = Color("263735")
const VECTOR_HIGH_COLOR: Color = Color("3b5552")
const VECTOR_TEXT_COLOR: Color = Color("e5e2e1")
const VECTOR_STATUS_COLOR: Color = Color("c4c7c7")
const VECTOR_PANEL_BG: Color = Color("1c1b1b")
const VECTOR_PANEL_ALT_BG: Color = Color("121414")
const VECTOR_CONTEXT_BG: Color = Color("1b241e")
const VECTOR_BORDER_COLOR: Color = Color("434747")
const VECTOR_CONTEXT_BORDER: Color = Color("4a7b7b")
const VECTOR_CYAN_COLOR: Color = Color("76c7c7")
const VECTOR_AMBER_COLOR: Color = Color("ffb000")
const VECTOR_ERROR_COLOR: Color = Color("ffb4ab")
const VECTOR_DIM_COLOR: Color = Color("7d8282")

enum AssetKind {
	NONE,
	FLIGHT,
	PLATOON,
	CARRIER,
}

const VECTOR_CARRIER_COLOR: Color = VECTOR_CYAN_COLOR

var _root: Control
var _backdrop: ColorRect
var _header_panel: Panel
var _header_title: Label
var _header_subtitle: Label

var _left_panel: Panel
var _force_title: Label
var _carrier_button: Button
var _asset_title: Label
var _asset_scroll: ScrollContainer
var _asset_sections: VBoxContainer
var _flight_list: VBoxContainer
var _platoon_title: Label
var _platoon_list: VBoxContainer
var _mission_popup: Panel
var _mission_popup_source: Button
var _mission_title: Label
var _mission_list: VBoxContainer
var _draft_title: Label
var _draft_summary: Label
var _confirm_button: Button
var _cancel_button: Button

var _center_panel: Panel
var _map_frame: Panel
var _map_rect: TextureRect
var _mobility_rect: TextureRect
var _mobility_material: ShaderMaterial
var _fog_rect: TextureRect
var _map_input: Control
var _symbol_layer: Control
var _map_meta: Label
var _map_hint: Label
var _map_status: Label
var _grid_col_labels: Array[Label] = []
var _grid_row_labels: Array[Label] = []

var _right_panel: Panel
var _info_title: Label
var _info_body: Label
var _command_prompt: Label

var _order_bar: Panel
var _order_status: Label
var _footer_panel: Panel
var _footer_left: Label
var _footer_right: Label

var _map_texture: ImageTexture = null
var _mobility_texture: ImageTexture = null
var _map_ready: bool = false
var _map_hover_active: bool = false

var _asset_buttons: Array = []
var _mission_buttons: Array = []
var _mission_signature: String = ""
var _selected_asset_kind: AssetKind = AssetKind.NONE
var _selected_asset_name: String = ""
var _selected_mission_id: String = ""
var _draft_points: Array[Vector3] = []
var _route_drag_index: int = -1
var _ui_refresh_timer_s: float = 0.0
var _command_error_text: String = ""
var _command_error_until_ms: int = 0
var _carrier_route_signal_source: Node = null
var _fog_mask_suppressed: bool = false

func _ready() -> void:
	add_to_group("origin_shifter")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 190
	set_process(true)
	_build_ui()
	_rebuild_asset_buttons()
	_rebuild_mission_buttons()
	_refresh_ui(true)
	_set_open(false)
	if not TerrainNavGrid.bake_complete.is_connected(_on_navgrid_bake_complete):
		TerrainNavGrid.bake_complete.connect(_on_navgrid_bake_complete)
	if not NavGraph.graph_ready.is_connected(_on_navgraph_ready):
		NavGraph.graph_ready.connect(_on_navgraph_ready)
	if TerrainNavGrid.is_ready():
		call_deferred("_ensure_map_texture")
	call_deferred("_ensure_carrier_route_signal")

func apply_origin_shift(offset: Vector3) -> void:
	for i in range(_draft_points.size()):
		_draft_points[i] -= offset
	_refresh_ui()

func _input(event: InputEvent) -> void:
	if _root == null or not _root.visible or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_H and key_event.physical_keycode != KEY_H:
		return
	set_fog_mask_suppressed(not _fog_mask_suppressed)
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _root == null or not _root.visible:
		return
	_ui_refresh_timer_s -= delta
	if _ui_refresh_timer_s <= 0.0:
		_ensure_carrier_route_signal()
		_refresh_ui()
		_ui_refresh_timer_s = 0.2

func _on_navgrid_bake_complete() -> void:
	_invalidate_map_layers()
	_refresh_fog_mask()
	if _root.visible:
		call_deferred("_ensure_map_texture")


func _on_navgraph_ready() -> void:
	_invalidate_map_layers()
	if _root != null:
		call_deferred("_ensure_map_texture")


func _invalidate_map_layers() -> void:
	_map_ready = false
	_map_texture = null
	_mobility_texture = null
	if _map_rect != null:
		_map_rect.texture = null
	if _mobility_rect != null:
		_mobility_rect.texture = null

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = VECTOR_VOID_COLOR
	_root.add_child(_backdrop)

	_header_panel = _make_panel(Color("141313"), VECTOR_BORDER_COLOR, 1)
	_root.add_child(_header_panel)
	_header_title = _make_label("CARRIER COMMAND", 24, VECTOR_TEXT_COLOR)
	_header_panel.add_child(_header_title)
	_header_subtitle = _make_label("TACTICAL // PLAYER OPS UPLINK ACTIVE", 12, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_header_panel.add_child(_header_subtitle)

	_left_panel = _make_panel(VECTOR_PANEL_BG, VECTOR_BORDER_COLOR, 1)
	_root.add_child(_left_panel)
	_force_title = _make_label("FORCE SELECTION", 12, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_left_panel.add_child(_force_title)
	_carrier_button = _make_button("CARRIER", VECTOR_CARRIER_COLOR, ASSET_BUTTON_HEIGHT_PX, 16)
	_carrier_button.pressed.connect(_select_asset.bind(AssetKind.CARRIER, "Carrier", _carrier_button))
	_left_panel.add_child(_carrier_button)
	_asset_title = _make_label("FLIGHTS", 13, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_left_panel.add_child(_asset_title)
	_asset_scroll = ScrollContainer.new()
	_asset_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_asset_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_left_panel.add_child(_asset_scroll)
	_asset_sections = VBoxContainer.new()
	_asset_sections.add_theme_constant_override("separation", 10)
	_asset_scroll.add_child(_asset_sections)
	_flight_list = VBoxContainer.new()
	_flight_list.add_theme_constant_override("separation", 8)
	_asset_sections.add_child(_flight_list)
	_platoon_title = _make_label("PLATOONS", 13, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_asset_sections.add_child(_platoon_title)
	_platoon_list = VBoxContainer.new()
	_platoon_list.add_theme_constant_override("separation", 8)
	_asset_sections.add_child(_platoon_list)

	_mission_popup = _make_panel(VECTOR_CONTEXT_BG, VECTOR_CONTEXT_BORDER, 1)
	_mission_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_mission_popup.z_index = 30
	_mission_popup.visible = false
	_root.add_child(_mission_popup)
	_mission_title = _make_label("CHOOSE MISSION", 13, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_mission_popup.add_child(_mission_title)
	_mission_list = VBoxContainer.new()
	_mission_list.add_theme_constant_override("separation", 8)
	_mission_popup.add_child(_mission_list)

	_draft_title = _make_label("ORDER DRAFT", 13, VECTOR_AMBER_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_left_panel.add_child(_draft_title)
	_draft_summary = _make_label("", 14, VECTOR_STATUS_COLOR)
	_draft_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_panel.add_child(_draft_summary)

	_confirm_button = _make_button("CONFIRM", VECTOR_TEXT_COLOR)
	_confirm_button.pressed.connect(_confirm_draft)
	_confirm_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cancel_button = _make_button("CANCEL", VECTOR_AMBER_COLOR)
	_cancel_button.pressed.connect(_cancel_draft)
	_cancel_button.alignment = HORIZONTAL_ALIGNMENT_CENTER

	_center_panel = _make_panel(VECTOR_PANEL_ALT_BG, VECTOR_BORDER_COLOR, 1)
	_root.add_child(_center_panel)
	_map_frame = _make_panel(Color("161a22"), VECTOR_CONTEXT_BORDER, 1)
	_center_panel.add_child(_map_frame)
	_map_rect = TextureRect.new()
	_map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_panel.add_child(_map_rect)
	_mobility_rect = TextureRect.new()
	_mobility_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_mobility_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mobility_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_mobility_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobility_material = _make_mobility_material()
	_mobility_rect.material = _mobility_material
	_center_panel.add_child(_mobility_rect)
	_fog_rect = TextureRect.new()
	_fog_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fog_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fog_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_rect.material = _make_fog_material()
	_center_panel.add_child(_fog_rect)
	_map_input = Control.new()
	_map_input.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_input.gui_input.connect(_on_map_gui_input)
	_map_input.mouse_exited.connect(_on_map_mouse_exited)
	_center_panel.add_child(_map_input)
	_symbol_layer = preload("res://UI/WorldMapSymbolLayer.gd").new()
	_center_panel.add_child(_symbol_layer)
	_map_meta = _make_label("GRID_REF: TACTICAL\nSCALE: 1:50000", 13, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_center_panel.add_child(_map_meta)
	_map_hint = _make_label("", 13, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_map_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_center_panel.add_child(_map_hint)
	_map_status = _make_label("", 16, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
	_map_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_panel.add_child(_map_status)
	for column_name in GRID_COORD_COLUMNS:
		var col_label := _make_label(column_name, 12, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
		col_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_center_panel.add_child(col_label)
		_grid_col_labels.append(col_label)
	for row_idx in range(GRID_COORD_DIVISIONS):
		var row_label := _make_label(str(row_idx + 1), 12, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_CENTER, DATA_FONT)
		row_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_center_panel.add_child(row_label)
		_grid_row_labels.append(row_label)

	_right_panel = _make_panel(VECTOR_CONTEXT_BG, VECTOR_CONTEXT_BORDER, 1)
	_root.add_child(_right_panel)
	_info_title = _make_label("CONTEXTUAL STATUS", 13, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_right_panel.add_child(_info_title)
	_info_body = _make_label("", 16, VECTOR_TEXT_COLOR)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right_panel.add_child(_info_body)
	_command_prompt = _make_label("CMD> AWAITING INPUT...", 13, VECTOR_CYAN_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_right_panel.add_child(_command_prompt)

	_order_bar = _make_panel(VECTOR_CONTEXT_BG, VECTOR_AMBER_COLOR, 1)
	_root.add_child(_order_bar)
	_order_status = _make_label("AWAITING ORDER", 13, VECTOR_AMBER_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_order_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_order_bar.add_child(_order_status)
	_order_bar.add_child(_confirm_button)
	_order_bar.add_child(_cancel_button)

	_footer_panel = _make_panel(Color("353434"), VECTOR_BORDER_COLOR, 1)
	_root.add_child(_footer_panel)
	_footer_left = _make_label("SYSTEM ONLINE // TACTICAL GRID", 12, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_LEFT, DATA_FONT)
	_footer_left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_footer_panel.add_child(_footer_left)
	_footer_right = _make_label("GLOBAL ALERTS    RESOURCES    MISSION TIMER", 12, VECTOR_STATUS_COLOR, HORIZONTAL_ALIGNMENT_RIGHT, DATA_FONT)
	_footer_right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_footer_panel.add_child(_footer_right)

	_root.resized.connect(_layout_ui)
	_layout_ui()

func _layout_ui() -> void:
	if _root == null:
		return
	var size: Vector2 = _root.size
	var header_rect := Rect2(Vector2.ZERO, Vector2(size.x, HEADER_HEIGHT_PX))
	_header_panel.position = header_rect.position
	_header_panel.size = header_rect.size
	_header_title.position = Vector2(32.0, 8.0)
	_header_title.size = Vector2(310.0, 30.0)
	_header_subtitle.position = Vector2(32.0, 38.0)
	_header_subtitle.size = Vector2(310.0, 18.0)

	var body_top: float = header_rect.end.y
	var body_height: float = maxf(size.y - body_top - FOOTER_HEIGHT_PX, 1.0)
	var left_x: float = 0.0
	var center_x: float = left_x + LEFT_PANEL_WIDTH_PX + PANEL_GAP_PX
	var right_x: float = size.x - RIGHT_PANEL_WIDTH_PX
	var center_width: float = maxf(right_x - center_x - PANEL_GAP_PX, MIN_MAP_SIDE_PX + 48.0)

	_left_panel.position = Vector2(left_x, body_top)
	_left_panel.size = Vector2(LEFT_PANEL_WIDTH_PX, body_height)

	_center_panel.position = Vector2(center_x, body_top)
	_center_panel.size = Vector2(center_width, body_height)

	_right_panel.position = Vector2(right_x, body_top)
	_right_panel.size = Vector2(RIGHT_PANEL_WIDTH_PX, body_height)

	var left_inner_x: float = 16.0
	var left_inner_w: float = _left_panel.size.x - left_inner_x * 2.0
	var left_y: float = 18.0
	_force_title.position = Vector2(left_inner_x, left_y)
	_force_title.size = Vector2(left_inner_w, 18.0)
	left_y += 32.0
	_carrier_button.position = Vector2(left_inner_x, left_y)
	_carrier_button.size = Vector2(left_inner_w, ASSET_BUTTON_HEIGHT_PX)
	left_y += ASSET_BUTTON_HEIGHT_PX + SECTION_GAP_PX
	_asset_title.position = Vector2(left_inner_x, left_y)
	_asset_title.size = Vector2(left_inner_w, 20.0)
	left_y += 28.0
	var draft_reserved: float = 24.0 + 132.0 + SECTION_GAP_PX
	var asset_height := maxf(_left_panel.size.y - left_y - draft_reserved - SECTION_GAP_PX, 160.0)
	_asset_scroll.position = Vector2(left_inner_x, left_y)
	_asset_scroll.size = Vector2(left_inner_w, asset_height)
	_asset_sections.custom_minimum_size = Vector2(left_inner_w - 12.0, 0.0)
	left_y += asset_height + SECTION_GAP_PX
	_draft_title.position = Vector2(left_inner_x, left_y)
	_draft_title.size = Vector2(left_inner_w, 20.0)
	left_y += 24.0
	var remaining_h: float = _left_panel.size.y - left_y - 16.0
	_draft_summary.position = Vector2(left_inner_x, left_y)
	_draft_summary.size = Vector2(left_inner_w, maxf(remaining_h, 56.0))

	var map_side: float = minf(
		_center_panel.size.x - 48.0 - GRID_COORD_BAND_WIDTH_PX,
		_center_panel.size.y - 36.0 - GRID_COORD_BAND_HEIGHT_PX
	)
	map_side = maxf(map_side, MIN_MAP_SIDE_PX)
	var map_block_width: float = map_side + GRID_COORD_BAND_WIDTH_PX
	var map_pos := Vector2(
		(_center_panel.size.x - map_block_width) * 0.5 + GRID_COORD_BAND_WIDTH_PX,
		(_center_panel.size.y - map_side) * 0.5
	)
	_map_frame.position = map_pos - Vector2(8.0, 8.0)
	_map_frame.size = Vector2(map_side + 16.0, map_side + 16.0)
	_map_rect.position = map_pos
	_map_rect.size = Vector2(map_side, map_side)
	_mobility_rect.position = map_pos
	_mobility_rect.size = Vector2(map_side, map_side)
	_fog_rect.position = map_pos
	_fog_rect.size = Vector2(map_side, map_side)
	_map_input.position = map_pos
	_map_input.size = Vector2(map_side, map_side)
	_symbol_layer.position = map_pos
	_symbol_layer.size = Vector2(map_side, map_side)
	_map_meta.position = map_pos + Vector2(16.0, 14.0)
	_map_meta.size = Vector2(390.0, 62.0)
	_map_hint.position = Vector2(map_pos.x + 16.0, map_pos.y + map_side - 34.0)
	_map_hint.size = Vector2(map_side - 32.0, 24.0)
	_map_status.position = _map_rect.position
	_map_status.size = _map_rect.size
	_layout_grid_coord_labels(map_pos, map_side)

	var right_inner_x: float = 20.0
	var right_inner_w: float = _right_panel.size.x - right_inner_x * 2.0
	_info_title.position = Vector2(right_inner_x, 20.0)
	_info_title.size = Vector2(right_inner_w, 24.0)
	_info_body.position = Vector2(right_inner_x, 78.0)
	_info_body.size = Vector2(right_inner_w, _right_panel.size.y - 132.0)
	_command_prompt.position = Vector2(right_inner_x, _right_panel.size.y - 36.0)
	_command_prompt.size = Vector2(right_inner_w, 20.0)

	var order_width := minf(720.0, maxf(center_width - 80.0, 360.0))
	var order_height := 66.0
	_order_bar.position = Vector2(center_x + (center_width - order_width) * 0.5, body_top + body_height - order_height - 34.0)
	_order_bar.size = Vector2(order_width, order_height)
	var button_width := minf(160.0, order_width * 0.22)
	_cancel_button.position = Vector2(order_width - button_width - 10.0, 10.0)
	_cancel_button.size = Vector2(button_width, order_height - 20.0)
	_confirm_button.position = Vector2(_cancel_button.position.x - button_width - 10.0, 10.0)
	_confirm_button.size = Vector2(button_width, order_height - 20.0)
	_order_status.position = Vector2(20.0, 10.0)
	_order_status.size = Vector2(maxf(_confirm_button.position.x - 36.0, 120.0), order_height - 20.0)
	var hint_y := _order_bar.position.y - body_top - 32.0 if _order_bar.visible else map_pos.y + map_side - 34.0
	_map_hint.position = Vector2(map_pos.x + 16.0, hint_y)
	_map_hint.size = Vector2(map_side - 32.0, 24.0)

	_footer_panel.position = Vector2(0.0, size.y - FOOTER_HEIGHT_PX)
	_footer_panel.size = Vector2(size.x, FOOTER_HEIGHT_PX)
	_footer_left.position = Vector2(32.0, 0.0)
	_footer_left.size = Vector2(size.x * 0.52, FOOTER_HEIGHT_PX)
	_footer_right.position = Vector2(size.x * 0.52, 0.0)
	_footer_right.size = Vector2(size.x * 0.48 - 32.0, FOOTER_HEIGHT_PX)
	if _mission_popup.visible:
		_layout_mission_popup()

func _set_open(is_open: bool) -> void:
	if _root == null:
		return
	_root.visible = is_open
	if not is_open and _mission_popup != null:
		_mission_popup.visible = false
		_mission_popup_source = null
	if is_open:
		_ensure_map_texture()
		_refresh_ui(true)

func set_console_visible(is_visible: bool) -> void:
	_set_open(is_visible)

func is_console_visible() -> bool:
	return _root != null and _root.visible

func set_fog_mask_suppressed(suppressed: bool) -> void:
	_fog_mask_suppressed = suppressed
	_refresh_fog_mask()

func is_fog_mask_suppressed() -> bool:
	return _fog_mask_suppressed

func _ensure_map_texture() -> void:
	if _map_ready:
		_refresh_fog_mask()
		_map_status.visible = false
		return
	if not TerrainNavGrid.is_ready():
		_map_status.text = "Building terrain map..."
		_map_status.visible = true
		return
	if not NavGraph.is_ready():
		_map_status.text = "Building mobility network..."
		_map_status.visible = true
		return
	_map_status.text = "Rendering relief and mobility..."
	_map_status.visible = true
	var textures := WorldMapTextureBuilder.build_textures()
	var relief_texture := textures.get("relief") as ImageTexture
	var mobility_texture := textures.get("mobility") as ImageTexture
	if relief_texture == null or mobility_texture == null:
		_map_status.text = "Map render failed"
		return
	_map_texture = relief_texture
	_mobility_texture = mobility_texture
	_map_rect.texture = _map_texture
	_mobility_rect.texture = _mobility_texture
	_refresh_mobility_display()
	_refresh_fog_mask()
	_map_ready = true
	_map_status.visible = false

func _build_map_image(_terrain: Node3D) -> Image:
	return WorldMapTextureBuilder.build_image()


func _refresh_fog_mask() -> void:
	if _fog_rect == null:
		return
	if _fog_mask_suppressed:
		_fog_rect.visible = false
		return
	if not MapFogOfWar.is_initialized():
		_fog_rect.texture = null
		_fog_rect.visible = false
		return
	_fog_rect.texture = MapFogOfWar.get_mask_texture()
	_fog_rect.visible = _fog_rect.texture != null


func _make_fog_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 unknown_color : source_color = vec4(0.34, 0.36, 0.35, 1.0);

void fragment() {
	float explored = texture(TEXTURE, UV).r;
	COLOR = vec4(unknown_color.rgb, unknown_color.a * (1.0 - explored));
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _make_mobility_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 vehicle_color : source_color = vec4(0.77, 0.55, 0.24, 1.0);
uniform vec4 carrier_color : source_color = vec4(0.46, 0.78, 0.78, 1.0);
uniform float vehicle_strength : hint_range(0.0, 1.0) = 0.35;
uniform float carrier_strength : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	float vehicle_alpha = mask.r * vehicle_strength * vehicle_color.a;
	float carrier_alpha = mask.g * carrier_strength * carrier_color.a;
	float total = vehicle_alpha + carrier_alpha;
	vec3 mixed_color = (
		vehicle_color.rgb * vehicle_alpha + carrier_color.rgb * carrier_alpha
	) / max(total, 0.0001);
	COLOR = vec4(mixed_color, clamp(total, 0.0, 1.0));
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _refresh_mobility_display() -> void:
	if _mobility_material == null:
		return
	var vehicle_color := Color("c58d3d")
	var carrier_color := VECTOR_CYAN_COLOR
	var vehicle_strength := 0.32
	var carrier_strength := 0.48
	var filter_label := "ALL MOBILITY"
	match _selected_asset_kind:
		AssetKind.PLATOON:
			vehicle_strength = 0.92
			carrier_strength = 0.92
			carrier_color = vehicle_color
			filter_label = "VEHICLE MOBILITY"
		AssetKind.CARRIER:
			vehicle_strength = 0.10
			carrier_strength = 1.0
			filter_label = "CARRIER MOBILITY"
		AssetKind.FLIGHT:
			vehicle_strength = 0.18
			carrier_strength = 0.24
			filter_label = "RELIEF PRIORITY"
	_mobility_material.set_shader_parameter("vehicle_color", vehicle_color)
	_mobility_material.set_shader_parameter("carrier_color", carrier_color)
	_mobility_material.set_shader_parameter("vehicle_strength", vehicle_strength)
	_mobility_material.set_shader_parameter("carrier_strength", carrier_strength)
	if not _map_hover_active and _map_meta != null:
		_map_meta.text = (
			"GRID_REF: TACTICAL // SCALE 1:50000\n"
			+ "CYAN: CARRIER // AMBER: VEHICLE\n"
			+ "FILTER: %s" % filter_label
		)

func _rebuild_asset_buttons() -> void:
	_clear_children(_flight_list)
	_clear_children(_platoon_list)
	_asset_buttons.clear()
	for flight_name in AirOpsManager.get_flight_names():
		var button := _make_button("", VECTOR_TEXT_COLOR, ASSET_BUTTON_HEIGHT_PX, 16)
		button.pressed.connect(_select_asset.bind(AssetKind.FLIGHT, flight_name, button))
		_flight_list.add_child(button)
		_asset_buttons.append({"kind": AssetKind.FLIGHT, "name": flight_name, "button": button})
	for platoon_name in GroundOpsManager.get_platoon_names():
		var button := _make_button("", VECTOR_AMBER_COLOR, ASSET_BUTTON_HEIGHT_PX, 16)
		button.pressed.connect(_select_asset.bind(AssetKind.PLATOON, platoon_name, button))
		_platoon_list.add_child(button)
		_asset_buttons.append({"kind": AssetKind.PLATOON, "name": platoon_name, "button": button})

func _rebuild_mission_buttons() -> void:
	_clear_children(_mission_list)
	_mission_buttons.clear()
	for spec in _get_selected_mission_specs():
		var accent: Color = spec.get("accent", VECTOR_TEXT_COLOR)
		var button := _make_button(spec.get("label", "MISSION"), accent, BUTTON_HEIGHT_PX)
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
	_order_bar.visible = _can_confirm_draft()
	_layout_ui()
	_refresh_asset_button_states()
	_refresh_mission_button_states()
	_refresh_info_panel()
	_refresh_draft_summary()
	_refresh_order_status()
	_refresh_map_hint()
	_refresh_mobility_display()
	_refresh_fog_mask()
	_refresh_map_overlays()

func _refresh_asset_button_states() -> void:
	if _carrier_button != null:
		var carrier_selected := _selected_asset_kind == AssetKind.CARRIER
		var carrier_status := _get_asset_status(AssetKind.CARRIER, "Carrier")
		_carrier_button.text = _format_asset_button_text(carrier_status) if not carrier_status.is_empty() else "CARRIER"
		_carrier_button.disabled = carrier_status.is_empty()
		_style_button(_carrier_button, VECTOR_CARRIER_COLOR, carrier_selected, carrier_status.is_empty())
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
	_style_confirm_button(_confirm_button.disabled)
	_style_cancel_button(_cancel_button.disabled)

func _refresh_info_panel() -> void:
	var status := _get_selected_asset_status()
	if status.is_empty():
		_info_body.text = "No asset selected.\n\nPick the Carrier, a flight, or a platoon on the left, then choose a mission and use the map to place its target."
		_command_prompt.text = "CMD> SELECT ASSET"
		return
	_info_body.text = _format_asset_info(status)
	var command_error := _get_active_command_error()
	if not command_error.is_empty():
		_command_prompt.text = "CMD> %s" % command_error
		return
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
		_draft_summary.text = "%s selected.\nChoose a mission order to begin." % _selected_asset_name.to_upper()
		return
	var lines: Array[String] = []
	lines.append("ASSET: %s" % _selected_asset_name.to_upper())
	lines.append("MISSION: %s" % _selected_mission_id)
	if _mission_requires_target(_selected_mission_id):
		lines.append("TARGETS: %d" % _draft_points.size())
		if _mission_allows_waypoints(_selected_mission_id):
			if _selected_asset_kind == AssetKind.FLIGHT:
				if _draft_points.is_empty():
					lines.append("Click the map to place the first patrol point.")
				else:
					lines.append("Drag nodes to move them. Left-click a segment to add a node. Right-click a node to remove it.")
			else:
				lines.append("LMB adds route points. RMB removes the last point.")
		elif _draft_points.is_empty():
			lines.append("Click the map to place the target area.")
	else:
		lines.append("No map target required.")
	_draft_summary.text = "\n".join(lines)


func _refresh_order_status() -> void:
	if _order_status == null:
		return
	_order_bar.visible = _can_confirm_draft()
	if not _order_bar.visible:
		return
	var command_error := _get_active_command_error()
	if not command_error.is_empty():
		_order_status.text = "ORDER REJECTED // %s" % command_error
		_order_status.add_theme_color_override("font_color", VECTOR_ERROR_COLOR)
		return
	_order_status.add_theme_color_override("font_color", VECTOR_AMBER_COLOR)
	_order_status.text = "%s ORDER STAGED" % _selected_mission_id

func _refresh_map_hint() -> void:
	if not _map_ready and TerrainNavGrid.is_ready():
		_ensure_map_texture()
	var command_error := _get_active_command_error()
	if not command_error.is_empty():
		_map_hint.text = command_error
		return
	var status := _get_selected_asset_status()
	if _selected_asset_kind == AssetKind.NONE:
		_map_hint.text = "Select the Carrier, a flight, or a platoon to issue a command."
		return
	if _selected_asset_kind == AssetKind.FLIGHT and String(status.get("mission", "")) == "CAP" and _selected_mission_id.is_empty():
		_map_hint.text = "Selected CAP route: drag nodes to move, left-click a route segment to add a node, right-click a node to remove it."
		return
	if _selected_mission_id.is_empty():
		_map_hint.text = "Choose a mission from the menu beside the selected asset."
		return
	if _selected_asset_kind == AssetKind.FLIGHT and _selected_mission_id == "CAP":
		_map_hint.text = "Editing CAP route: drag nodes to move, left-click a segment to add a node, right-click a node to remove it, then confirm."
		return
	if _selected_mission_id == "RECON":
		if _draft_points.is_empty():
			_map_hint.text = "RECON: click on a discovered POI (yellow star) to assign the target, then confirm."
		else:
			_map_hint.text = "RECON target set. Confirm to dispatch the platoon."
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
		_symbol_layer.call("clear_selection_route")
		_symbol_layer.call("clear_command_draft")
		return
	var position: Vector3 = status.get("position", Vector3.ZERO)
	var selection_accent := VECTOR_TEXT_COLOR if _selected_asset_kind == AssetKind.FLIGHT else VECTOR_AMBER_COLOR
	_symbol_layer.call("set_selection_focus", position, selection_accent)
	var editing_flight_route: bool = _selected_asset_kind == AssetKind.FLIGHT and _selected_mission_id == "CAP" and not _draft_points.is_empty()
	if (_selected_asset_kind == AssetKind.FLIGHT and not editing_flight_route) or _selected_asset_kind == AssetKind.CARRIER:
		var mission_points_variant = status.get("mission_map_points", [])
		var mission_points: Array = mission_points_variant if mission_points_variant is Array else []
		if not mission_points.is_empty():
			_symbol_layer.call(
				"set_selection_route",
				position,
				mission_points,
				selection_accent,
				bool(status.get("mission_map_closed_loop", false))
			)
		else:
			_symbol_layer.call("clear_selection_route")
	else:
		_symbol_layer.call("clear_selection_route")
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


func _show_mission_popup(source_button: Button) -> void:
	if source_button == null or not is_instance_valid(source_button) or _mission_buttons.is_empty():
		_mission_popup.visible = false
		_mission_popup_source = null
		return
	_mission_popup_source = source_button
	_mission_title.text = "%s // CHOOSE MISSION" % _selected_asset_name.to_upper()
	_mission_popup.visible = true
	_layout_mission_popup()


func _layout_mission_popup() -> void:
	if _mission_popup == null or not _mission_popup.visible:
		return
	if _mission_popup_source == null or not is_instance_valid(_mission_popup_source):
		_mission_popup.visible = false
		_mission_popup_source = null
		return
	var popup_width := 270.0
	var mission_height := _get_mission_panel_height()
	var popup_height := 56.0 + mission_height
	_mission_popup.size = Vector2(popup_width, popup_height)
	_mission_title.position = Vector2(14.0, 12.0)
	_mission_title.size = Vector2(popup_width - 28.0, 22.0)
	_mission_list.position = Vector2(14.0, 44.0)
	_mission_list.size = Vector2(popup_width - 28.0, mission_height)
	var source_rect := _mission_popup_source.get_global_rect()
	var root_rect := _root.get_global_rect()
	var requested_y := source_rect.position.y - root_rect.position.y
	var min_y := HEADER_HEIGHT_PX + 8.0
	var max_y := maxf(_root.size.y - FOOTER_HEIGHT_PX - popup_height - 8.0, min_y)
	_mission_popup.position = Vector2(
		_left_panel.position.x + _left_panel.size.x + 8.0,
		clampf(requested_y, min_y, max_y)
	)


func _select_asset(kind: AssetKind, asset_name: String, source_button: Button) -> void:
	_clear_command_error()
	_selected_asset_kind = kind
	_selected_asset_name = asset_name
	_selected_mission_id = ""
	_draft_points.clear()
	_route_drag_index = -1
	_mission_popup.visible = false
	_mission_popup_source = null
	_refresh_ui()
	_show_mission_popup(source_button)

func _begin_mission_draft(mission_id: String) -> void:
	if _selected_asset_kind == AssetKind.NONE or _selected_asset_name.is_empty():
		return
	_clear_command_error()
	_selected_mission_id = mission_id
	_draft_points.clear()
	_route_drag_index = -1
	_mission_popup.visible = false
	_mission_popup_source = null
	_refresh_ui()

func _confirm_draft() -> void:
	if not _can_confirm_draft():
		return
	var accepted := true
	match _selected_asset_kind:
		AssetKind.FLIGHT:
			_confirm_flight_order()
		AssetKind.PLATOON:
			_confirm_platoon_order()
		AssetKind.CARRIER:
			accepted = _confirm_carrier_order()
		_:
			return
	if not accepted:
		return
	_selected_mission_id = ""
	_draft_points.clear()
	_route_drag_index = -1
	_refresh_ui()

func _confirm_flight_order() -> void:
	match _selected_mission_id:
		"CAP":
			AirOpsManager.order_cap_route(_selected_asset_name, _draft_points.duplicate(), FLIGHT_CAP_ALTITUDE_M)
		"CAS":
			if _draft_points.is_empty():
				return
			AirOpsManager.order_cas(_selected_asset_name, _draft_points[0], FLIGHT_CAS_RADIUS_M)
		"RTB":
			AirOpsManager.order_rtb(_selected_asset_name)

func _confirm_platoon_order() -> void:
	match _selected_mission_id:
		"MOVE", "RECON":
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
		"RTB":
			GroundOpsManager.order_rtb(_selected_asset_name)

func _confirm_carrier_order() -> bool:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null or not is_instance_valid(carrier):
		_set_command_error("CARRIER UNAVAILABLE")
		_refresh_ui()
		return false
	match _selected_mission_id:
		"MOVE":
			if _draft_points.is_empty():
				return false
			if carrier.has_method("set_player_patrol_waypoints"):
				var accepted: bool = bool(carrier.call("set_player_patrol_waypoints", _draft_points.duplicate()))
				if not accepted:
					var error := "CARRIER ROUTE REJECTED"
					if carrier.has_method("get_last_player_route_error"):
						error = String(carrier.call("get_last_player_route_error"))
					_set_command_error(error)
					_refresh_ui()
					return false
			else:
				_set_command_error("CARRIER ROUTING UNAVAILABLE")
				_refresh_ui()
				return false
		"HOLD":
			if carrier.has_method("hold_position"):
				carrier.call("hold_position")
			elif carrier.has_method("set_patrol_waypoints"):
				var hold_waypoints: Array[Vector3] = [carrier.global_position]
				carrier.call("set_patrol_waypoints", hold_waypoints)
	return true


func _cancel_draft() -> void:
	_clear_command_error()
	_selected_mission_id = ""
	_draft_points.clear()
	_route_drag_index = -1
	_mission_popup.visible = false
	_mission_popup_source = null
	_refresh_ui()

func _on_map_gui_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event is InputEventMouseMotion:
		_map_hover_active = true
		_update_map_hover_readout((event as InputEventMouseMotion).position)
	var status := _get_selected_asset_status()
	if _handle_selected_flight_route_input(event, status):
		return
	if not _mission_requires_target(_selected_mission_id):
		return
	if event is InputEventMouseButton and event.pressed and not event.double_click:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if _selected_asset_kind == AssetKind.FLIGHT and _selected_mission_id == "CAP" and not _draft_points.is_empty():
				return
			if _selected_mission_id == "RECON":
				var snapped := _snap_to_poi_world(mouse_event.position)
				if snapped == Vector3.INF:
					return  # click not near a POI star
				if _requires_explored_ground_target() and not _is_world_explored(snapped):
					_reject_unknown_ground_target()
					get_viewport().set_input_as_handled()
					return
				_clear_command_error()
				_draft_points = [snapped]
				_refresh_ui()
				get_viewport().set_input_as_handled()
				return
			var world_pos := _map_to_world(mouse_event.position)
			if _requires_explored_ground_target() and not _is_world_explored(world_pos):
				_reject_unknown_ground_target()
				get_viewport().set_input_as_handled()
				return
			var carrier_route_error := _get_carrier_route_point_error(world_pos)
			if not carrier_route_error.is_empty():
				_set_command_error(carrier_route_error)
				_refresh_ui()
				get_viewport().set_input_as_handled()
				return
			_clear_command_error()
			if _mission_allows_waypoints(_selected_mission_id):
				_draft_points.append(world_pos)
			else:
				_draft_points = [world_pos]
			_refresh_ui()
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and not _draft_points.is_empty():
			if _selected_asset_kind == AssetKind.FLIGHT and _selected_mission_id == "CAP":
				return
			_draft_points.pop_back()
			_refresh_ui()
			get_viewport().set_input_as_handled()


func _on_map_mouse_exited() -> void:
	_map_hover_active = false
	_refresh_mobility_display()


func _update_map_hover_readout(local_pos: Vector2) -> void:
	if _map_meta == null:
		return
	var world_pos := _map_to_world(local_pos)
	var grid_reference := _format_map_grid_reference(local_pos)
	if not _fog_mask_suppressed and not _is_world_explored(world_pos):
		_map_meta.text = "GRID %s // TERRAIN UNKNOWN\nMOBILITY DATA WITHHELD" % grid_reference
		return
	var grade_degrees := _sample_map_grade_degrees(world_pos)
	var mobility_class := WorldMapTextureBuilder.sample_world_mobility_class(world_pos.x, world_pos.z)
	var mobility_label := WorldMapTextureBuilder.mobility_class_label(mobility_class)
	_map_meta.text = (
		"GRID %s // ELEV: %.0f M // GRADE: %.0f DEG\n" % [grid_reference, world_pos.y, grade_degrees]
		+ "MOBILITY: %s" % mobility_label
	)


func _format_map_grid_reference(local_pos: Vector2) -> String:
	var map_size := _map_input.size if _map_input != null else Vector2.ONE
	var column := clampi(int(floor(local_pos.x / maxf(map_size.x, 1.0) * GRID_COORD_DIVISIONS)), 0, GRID_COORD_DIVISIONS - 1)
	var row := clampi(int(floor(local_pos.y / maxf(map_size.y, 1.0) * GRID_COORD_DIVISIONS)), 0, GRID_COORD_DIVISIONS - 1)
	return "%s%d" % [GRID_COORD_COLUMNS[column], row + 1]


func _sample_map_grade_degrees(world_pos: Vector3) -> float:
	var step := maxf(TerrainNavGrid.cell_size_m, 1.0)
	var left_h := TerrainNavGrid.sample_height(world_pos.x - step, world_pos.z)
	var right_h := TerrainNavGrid.sample_height(world_pos.x + step, world_pos.z)
	var up_h := TerrainNavGrid.sample_height(world_pos.x, world_pos.z - step)
	var down_h := TerrainNavGrid.sample_height(world_pos.x, world_pos.z + step)
	for height in [left_h, right_h, up_h, down_h]:
		if height <= TerrainNavGrid.IMPASSABLE * 0.5:
			return 0.0
	var slope_x := (right_h - left_h) / (step * 2.0)
	var slope_z := (down_h - up_h) / (step * 2.0)
	return rad_to_deg(atan(sqrt(slope_x * slope_x + slope_z * slope_z)))

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
		AssetKind.CARRIER:
			var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
			if carrier == null or not is_instance_valid(carrier):
				return {}
			var waypoints: Array[Vector3] = []
			if carrier.has_method("get_active_waypoints"):
				waypoints = carrier.call("get_active_waypoints")
			return {
				"name": "Carrier",
				"kind": "carrier",
				"position": carrier.global_position,
				"active_waypoints": waypoints,
				"mission_map_points": waypoints,
				"mission_map_closed_loop": false,
			}
		_:
			return {}

func _get_selected_mission_specs() -> Array[Dictionary]:
	match _selected_asset_kind:
		AssetKind.FLIGHT:
			return [
				{"id": "CAP", "label": "> CAP", "accent": VECTOR_TEXT_COLOR},
				{"id": "CAS", "label": "> CAS", "accent": VECTOR_AMBER_COLOR},
				{"id": "INTERDICTION", "label": "> INTERDICTION", "accent": VECTOR_STATUS_COLOR, "supported": false},
				{"id": "STRIKE", "label": "> STRIKE", "accent": VECTOR_AMBER_COLOR, "supported": false},
				{"id": "ESCORT", "label": "> ESCORT", "accent": VECTOR_TEXT_COLOR, "supported": false},
			]
		AssetKind.PLATOON:
			return [
				{"id": "MOVE", "label": "> MOVE", "accent": VECTOR_TEXT_COLOR},
				{"id": "RECON", "label": "> RECON", "accent": VECTOR_TEXT_COLOR},
				{"id": "ATTACK", "label": "> ATTACK", "accent": VECTOR_AMBER_COLOR},
				{"id": "PROTECT", "label": "> PROTECT", "accent": VECTOR_STATUS_COLOR},
				{"id": "ESCORT", "label": "> ESCORT", "accent": VECTOR_TEXT_COLOR},
				{"id": "RTB", "label": "> RTB", "accent": VECTOR_AMBER_COLOR},
				{"id": "HOLD", "label": "> HOLD", "accent": VECTOR_STATUS_COLOR},
			]
		AssetKind.CARRIER:
			return [
				{"id": "MOVE", "label": "> NAVIGATE TO", "accent": VECTOR_CARRIER_COLOR},
				{"id": "HOLD", "label": "> HOLD POSITION", "accent": VECTOR_AMBER_COLOR},
			]
		_:
			return []

func _is_mission_enabled(spec: Dictionary, status: Dictionary) -> bool:
	if spec.is_empty() or status.is_empty():
		return false
	if not bool(spec.get("supported", true)):
		return false
	var mission_id: String = spec.get("id", "")
	match mission_id:
		"RTB":
			return int(status.get("strength", 0)) > 0
		_:
			return true

func _can_confirm_draft() -> bool:
	if _selected_asset_kind == AssetKind.NONE or _selected_asset_name.is_empty() or _selected_mission_id.is_empty():
		return false
	if _mission_requires_target(_selected_mission_id):
		if _draft_points.is_empty():
			return false
		if _requires_explored_ground_target():
			for point in _draft_points:
				if not _is_world_explored(point):
					return false
		return true
	return true


func _requires_explored_ground_target() -> bool:
	if _selected_asset_kind == AssetKind.CARRIER:
		return _selected_mission_id == "MOVE"
	if _selected_asset_kind != AssetKind.PLATOON:
		return false
	return _selected_mission_id in ["MOVE", "RECON", "ATTACK", "PROTECT"]


func _is_world_explored(world_pos: Vector3) -> bool:
	return MapFogOfWar.is_initialized() and MapFogOfWar.is_world_explored(world_pos)


func _reject_unknown_ground_target() -> void:
	_set_command_error("AREA UNKNOWN — SCOUT WITH AIRCRAFT")
	_refresh_ui()


func _get_carrier_route_point_error(world_pos: Vector3) -> String:
	if _selected_asset_kind != AssetKind.CARRIER or _selected_mission_id != "MOVE":
		return ""
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null or not is_instance_valid(carrier):
		return "CARRIER UNAVAILABLE"
	if not carrier.has_method("get_player_route_point_error"):
		return ""
	return String(carrier.call("get_player_route_point_error", world_pos))


func _ensure_carrier_route_signal() -> void:
	if is_instance_valid(_carrier_route_signal_source):
		return
	var carrier := get_tree().get_first_node_in_group("carrier")
	if carrier == null or not carrier.has_signal("player_route_rejected"):
		return
	var callback := Callable(self, "_on_carrier_route_rejected")
	if not carrier.is_connected("player_route_rejected", callback):
		carrier.connect("player_route_rejected", callback)
	_carrier_route_signal_source = carrier


func _on_carrier_route_rejected(message: String) -> void:
	_set_command_error(message, 5.0)
	_refresh_ui()


func _set_command_error(message: String, duration_s: float = 3.0) -> void:
	_command_error_text = message
	_command_error_until_ms = Time.get_ticks_msec() + int(maxf(duration_s, 0.1) * 1000.0)


func _clear_command_error() -> void:
	_command_error_text = ""
	_command_error_until_ms = 0


func _get_active_command_error() -> String:
	if _command_error_text.is_empty():
		return ""
	if Time.get_ticks_msec() <= _command_error_until_ms:
		return _command_error_text
	_clear_command_error()
	return ""

func _mission_requires_target(mission_id: String) -> bool:
	return mission_id in ["CAP", "CAS", "INTERDICTION", "STRIKE", "MOVE", "RECON", "ATTACK", "PROTECT"]

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
	var preview_points: Array[Vector3] = [
		Vector3(anchor.x + CAP_LOOP_HALF_SIDE_M, anchor.y, anchor.z + CAP_LOOP_HALF_SIDE_M),
		Vector3(anchor.x - CAP_LOOP_HALF_SIDE_M, anchor.y, anchor.z + CAP_LOOP_HALF_SIDE_M),
		Vector3(anchor.x - CAP_LOOP_HALF_SIDE_M, anchor.y, anchor.z - CAP_LOOP_HALF_SIDE_M),
		Vector3(anchor.x + CAP_LOOP_HALF_SIDE_M, anchor.y, anchor.z - CAP_LOOP_HALF_SIDE_M),
	]
	var status := _get_selected_asset_status()
	if _selected_asset_kind == AssetKind.FLIGHT and not status.is_empty():
		var from_pos: Vector3 = status.get("position", anchor)
		return _rotate_cap_route_preview_to_nearest_waypoint(preview_points, from_pos)
	return preview_points

func _rotate_cap_route_preview_to_nearest_waypoint(route_points: Array[Vector3], from_pos: Vector3) -> Array[Vector3]:
	if route_points.size() <= 1:
		return route_points.duplicate()
	var best_index: int = 0
	var best_dist_sq: float = INF
	for i in range(route_points.size()):
		var point := route_points[i]
		var dx: float = point.x - from_pos.x
		var dz: float = point.z - from_pos.z
		var dist_sq := dx * dx + dz * dz
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_index = i
	if best_dist_sq <= CAP_ROUTE_PREVIEW_ENTRY_SKIP_DISTANCE_M * CAP_ROUTE_PREVIEW_ENTRY_SKIP_DISTANCE_M:
		best_index = (best_index + 1) % route_points.size()
	if best_index == 0:
		return route_points.duplicate()
	var rotated: Array[Vector3] = []
	for i in range(best_index, route_points.size()):
		rotated.append(route_points[i])
	for i in range(best_index):
		rotated.append(route_points[i])
	return rotated

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
	return String(status.get("name", "")).to_upper()

func _format_asset_info(status: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(status.get("name", "UNIT").to_upper())
	if status.get("kind", "") == "carrier":
		lines.append("TYPE: LAND CARRIER")
		var waypoints_variant = status.get("active_waypoints", [])
		var wp_count: int = waypoints_variant.size() if waypoints_variant is Array else 0
		lines.append("WAYPOINTS: %d" % wp_count)
		var pos: Vector3 = status.get("position", Vector3.ZERO)
		lines.append("COORDS: %.0f / %.0f" % [pos.x, pos.z])
		if not _selected_mission_id.is_empty():
			lines.append("")
			lines.append("PENDING: %s" % _selected_mission_id)
			if not _draft_points.is_empty():
				lines.append("TARGET STAGED")
		return "\n".join(lines)
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

func _handle_selected_flight_route_input(event: InputEvent, status: Dictionary) -> bool:
	if _selected_asset_kind != AssetKind.FLIGHT or status.is_empty():
		return false
	var route_points := _get_visible_selected_flight_route_points(status)
	if route_points.is_empty():
		return false
	var closed_loop := _is_selected_flight_route_closed_loop(status, route_points)
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _route_drag_index >= 0 and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if not _ensure_cap_route_edit_draft(status):
				return false
			_materialize_cap_draft_points_for_editing()
			if _route_drag_index < 0 or _route_drag_index >= _draft_points.size():
				return false
			var moved_point := _map_to_world(motion.position)
			moved_point.y = _draft_points[_route_drag_index].y
			_draft_points[_route_drag_index] = moved_point
			_refresh_ui()
			get_viewport().set_input_as_handled()
			return true
		return false
	if not (event is InputEventMouseButton):
		return false
	var mouse_event := event as InputEventMouseButton
	if mouse_event.double_click:
		return false
	match mouse_event.button_index:
		MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				var node_index := _find_route_node_hit_index(mouse_event.position, route_points)
				if node_index >= 0:
					if not _ensure_cap_route_edit_draft(status):
						return false
					_materialize_cap_draft_points_for_editing()
					if node_index >= 0 and node_index < _draft_points.size():
						_route_drag_index = node_index
						get_viewport().set_input_as_handled()
						return true
				var insert_index := _find_route_segment_insert_index(mouse_event.position, route_points, closed_loop)
				if insert_index >= 0:
					if not _ensure_cap_route_edit_draft(status):
						return false
					_materialize_cap_draft_points_for_editing()
					var inserted_point := _map_to_world(mouse_event.position)
					inserted_point.y = _get_flight_route_edit_altitude(status)
					_draft_points.insert(clampi(insert_index, 0, _draft_points.size()), inserted_point)
					_route_drag_index = insert_index
					_refresh_ui()
					get_viewport().set_input_as_handled()
					return true
			elif _route_drag_index >= 0:
				_route_drag_index = -1
				get_viewport().set_input_as_handled()
				return true
		MOUSE_BUTTON_RIGHT:
			if mouse_event.pressed:
				var node_index := _find_route_node_hit_index(mouse_event.position, route_points)
				if node_index >= 0:
					if not _ensure_cap_route_edit_draft(status):
						return false
					_materialize_cap_draft_points_for_editing()
					if _draft_points.size() > 1 and node_index < _draft_points.size():
						_draft_points.remove_at(node_index)
						_route_drag_index = -1
						_refresh_ui()
					get_viewport().set_input_as_handled()
					return true
	return false

func _get_visible_selected_flight_route_points(status: Dictionary) -> Array[Vector3]:
	if _selected_asset_kind != AssetKind.FLIGHT:
		return []
	if _selected_mission_id == "CAP" and not _draft_points.is_empty():
		if _draft_points.size() == 1:
			return _get_cap_route_preview(_draft_points)
		return _draft_points.duplicate()
	if String(status.get("mission", "")) != "CAP":
		return []
	return _variant_to_vector3_array(status.get("mission_map_points", []))

func _is_selected_flight_route_closed_loop(status: Dictionary, route_points: Array[Vector3]) -> bool:
	if _selected_mission_id == "CAP" and not route_points.is_empty():
		return route_points.size() >= 2
	return bool(status.get("mission_map_closed_loop", false))

func _ensure_cap_route_edit_draft(status: Dictionary) -> bool:
	if _selected_asset_kind != AssetKind.FLIGHT:
		return false
	if _selected_mission_id == "CAP":
		return true
	if String(status.get("mission", "")) != "CAP":
		return false
	var mission_points := _variant_to_vector3_array(status.get("mission_map_points", []))
	if mission_points.is_empty():
		return false
	_selected_mission_id = "CAP"
	_draft_points = mission_points
	_route_drag_index = -1
	_refresh_ui()
	return true

func _materialize_cap_draft_points_for_editing() -> void:
	if _selected_mission_id != "CAP" or _draft_points.size() != 1:
		return
	_draft_points = _get_cap_route_preview(_draft_points)

func _get_flight_route_edit_altitude(status: Dictionary) -> float:
	if not _draft_points.is_empty():
		return _draft_points[0].y
	var mission_points := _variant_to_vector3_array(status.get("mission_map_points", []))
	if not mission_points.is_empty():
		return mission_points[0].y
	return FLIGHT_CAP_ALTITUDE_M

func _find_route_node_hit_index(local_pos: Vector2, route_points: Array[Vector3]) -> int:
	var best_index: int = -1
	var best_distance: float = ROUTE_NODE_HIT_RADIUS_PX
	for i in range(route_points.size()):
		var map_point := _world_to_map_local(route_points[i])
		var dist := local_pos.distance_to(map_point)
		if dist <= best_distance:
			best_distance = dist
			best_index = i
	return best_index

func _find_route_segment_insert_index(local_pos: Vector2, route_points: Array[Vector3], closed_loop: bool) -> int:
	if route_points.size() < 2:
		return -1
	var best_index: int = -1
	var best_distance: float = ROUTE_SEGMENT_HIT_RADIUS_PX
	for i in range(route_points.size() - 1):
		var start := _world_to_map_local(route_points[i])
		var end := _world_to_map_local(route_points[i + 1])
		var dist := _distance_to_segment(local_pos, start, end)
		if dist <= best_distance:
			best_distance = dist
			best_index = i + 1
	if closed_loop:
		var loop_start := _world_to_map_local(route_points[route_points.size() - 1])
		var loop_end := _world_to_map_local(route_points[0])
		var loop_dist := _distance_to_segment(local_pos, loop_start, loop_end)
		if loop_dist <= best_distance:
			best_distance = loop_dist
			best_index = route_points.size()
	return best_index

func _world_to_map_local(world_pos: Vector3) -> Vector2:
	var span_x: float = float(TerrainNavGrid._cols - 1) * TerrainNavGrid.cell_size_m
	var span_z: float = float(TerrainNavGrid._rows - 1) * TerrainNavGrid.cell_size_m
	if span_x <= 0.0 or span_z <= 0.0:
		return Vector2.ZERO
	var u: float = (world_pos.x - TerrainNavGrid._origin_x) / span_x
	var v: float = (world_pos.z - TerrainNavGrid._origin_z) / span_z
	return Vector2(u * _map_input.size.x, v * _map_input.size.y)

## Returns the world position of the nearest discovered POI to a map click,
## or Vector3.INF if no POI is within the snap radius.
func _snap_to_poi_world(map_click: Vector2) -> Vector3:
	const SNAP_PX: float = 28.0
	var best_world := Vector3.INF
	var best_dist := SNAP_PX
	for poi_world: Vector3 in POIManager.get_active_discovered_positions():
		var mp: Vector2 = _world_to_map_local(poi_world)
		var dist := map_click.distance_to(mp)
		if dist < best_dist:
			best_dist = dist
			best_world = poi_world
	return best_world

func _distance_to_segment(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var segment := seg_b - seg_a
	var segment_len_sq := segment.length_squared()
	if segment_len_sq <= 0.001:
		return point.distance_to(seg_a)
	var t := clampf((point - seg_a).dot(segment) / segment_len_sq, 0.0, 1.0)
	var projected := seg_a + segment * t
	return point.distance_to(projected)

func _variant_to_vector3_array(points_variant) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not (points_variant is Array):
		return result
	for point in points_variant:
		if point is Vector3:
			result.append(point)
	return result

func _get_mission_panel_height() -> float:
	var mission_count: int = _get_selected_mission_specs().size()
	if mission_count <= 0:
		return 0.0
	var content_height := float(mission_count) * BUTTON_HEIGHT_PX + float(maxi(mission_count - 1, 0)) * 8.0
	return clampf(content_height, 120.0, 360.0)

func _layout_grid_coord_labels(map_pos: Vector2, map_side: float) -> void:
	var column_width: float = map_side / float(GRID_COORD_DIVISIONS)
	var row_height: float = map_side / float(GRID_COORD_DIVISIONS)
	for i in range(_grid_col_labels.size()):
		var label := _grid_col_labels[i]
		label.position = Vector2(map_pos.x + column_width * float(i), map_pos.y - GRID_COORD_BAND_HEIGHT_PX)
		label.size = Vector2(column_width, GRID_COORD_BAND_HEIGHT_PX)
	for i in range(_grid_row_labels.size()):
		var label := _grid_row_labels[i]
		label.position = Vector2(map_pos.x - GRID_COORD_BAND_WIDTH_PX, map_pos.y + row_height * float(i))
		label.size = Vector2(GRID_COORD_BAND_WIDTH_PX, row_height)

func _make_panel(color: Color, border: Color = VECTOR_BORDER_COLOR, border_width: int = 1) -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	panel.add_theme_stylebox_override("panel", style)
	return panel

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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _make_button(text: String, accent: Color, min_height: float = BUTTON_HEIGHT_PX, font_size: int = 14) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = Vector2(0.0, min_height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", DATA_FONT)
	button.add_theme_font_size_override("font_size", font_size)
	_style_button(button, accent, false, false)
	return button

func _style_button(button: Button, accent: Color, selected: bool, disabled: bool) -> void:
	var normal_fill := Color("201f1f")
	var hover_fill := Color("2a2a2a")
	var pressed_fill := Color("353434")
	if selected:
		normal_fill = Color("424b44")
		hover_fill = Color("4c5650")
		pressed_fill = Color("343d37")
	if disabled:
		normal_fill = Color("171717")
		hover_fill = normal_fill
		pressed_fill = normal_fill
	var border_color := accent if not disabled else VECTOR_DIM_COLOR
	var selected_width := 4 if selected else 1
	button.add_theme_stylebox_override("normal", _build_button_style(normal_fill, border_color, selected_width))
	button.add_theme_stylebox_override("hover", _build_button_style(hover_fill, border_color, selected_width))
	button.add_theme_stylebox_override("pressed", _build_button_style(pressed_fill, border_color, selected_width))
	button.add_theme_stylebox_override("disabled", _build_button_style(normal_fill, border_color.lerp(Color.BLACK, 0.45), 1))
	button.add_theme_color_override("font_color", VECTOR_TEXT_COLOR if not disabled else VECTOR_DIM_COLOR)
	button.add_theme_color_override("font_hover_color", accent if not disabled else VECTOR_DIM_COLOR)
	button.add_theme_color_override("font_pressed_color", VECTOR_TEXT_COLOR if not disabled else VECTOR_DIM_COLOR)
	button.add_theme_color_override("font_disabled_color", VECTOR_DIM_COLOR)


func _style_confirm_button(disabled: bool) -> void:
	var fill := Color("ffb000") if not disabled else Color("242424")
	var hover_fill := Color("ffc13d") if not disabled else fill
	var border := VECTOR_AMBER_COLOR if not disabled else VECTOR_BORDER_COLOR
	_confirm_button.add_theme_stylebox_override("normal", _build_button_style(fill, border))
	_confirm_button.add_theme_stylebox_override("hover", _build_button_style(hover_fill, border))
	_confirm_button.add_theme_stylebox_override("pressed", _build_button_style(Color("d99500"), border))
	_confirm_button.add_theme_stylebox_override("disabled", _build_button_style(fill, border))
	var text_color := Color("121414") if not disabled else VECTOR_DIM_COLOR
	_confirm_button.add_theme_color_override("font_color", text_color)
	_confirm_button.add_theme_color_override("font_hover_color", Color("121414"))
	_confirm_button.add_theme_color_override("font_pressed_color", Color("121414"))
	_confirm_button.add_theme_color_override("font_disabled_color", VECTOR_DIM_COLOR)


func _style_cancel_button(disabled: bool) -> void:
	var fill := Color("1b241e") if not disabled else Color("171717")
	var border := VECTOR_ERROR_COLOR if not disabled else VECTOR_BORDER_COLOR
	_cancel_button.add_theme_stylebox_override("normal", _build_button_style(fill, border))
	_cancel_button.add_theme_stylebox_override("hover", _build_button_style(Color("2b2221"), border))
	_cancel_button.add_theme_stylebox_override("pressed", _build_button_style(Color("3b2523"), border))
	_cancel_button.add_theme_stylebox_override("disabled", _build_button_style(fill, border))
	_cancel_button.add_theme_color_override("font_color", VECTOR_ERROR_COLOR if not disabled else VECTOR_DIM_COLOR)
	_cancel_button.add_theme_color_override("font_hover_color", VECTOR_ERROR_COLOR)
	_cancel_button.add_theme_color_override("font_pressed_color", VECTOR_ERROR_COLOR)
	_cancel_button.add_theme_color_override("font_disabled_color", VECTOR_DIM_COLOR)

func _build_button_style(fill: Color, border: Color, left_border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = left_border_width
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
