extends Control
## Interactive main-menu equipment reference. Gameplay scenes are instantiated
## off-tree, stripped of behaviour, and then placed in an isolated preview world.

signal exit_requested
signal mode_changed(mode: String)

const Catalog = preload("res://UI/TechnicalIndexCatalog.gd")
const MenuTypography = preload("res://UI/MenuTypography.gd")
const LAND_CARRIER_SCENE_PATH := "res://LandCarrier/LandCarrier2.tscn"
const CARRIER_TREAD_SCRIPT_PATH := "res://LandCarrier/CarrierTread.gd"
const PILOT_POSE_SCRIPT_PATH := "res://Aircraft/PilotPose.gd"

const BASE_UI_SIZE := MenuTypography.CANVAS_SIZE
const RAIL_WIDTH := 480.0
const UI_PRIMARY := Color(1.0, 0.718, 0.49, 1.0)
const UI_PRIMARY_ACTIVE := Color(1.0, 0.55, 0.0, 1.0)
const UI_HAZARD := Color(1.0, 0.86, 0.28, 1.0)
const UI_SURFACE := Color(0.035, 0.039, 0.043, 0.96)
const UI_SURFACE_LOW := Color(0.047, 0.055, 0.063, 0.78)
const UI_OUTLINE := Color(0.337, 0.263, 0.204, 0.78)
const UI_TEXT := Color(0.886, 0.886, 0.898, 1.0)
const UI_TEXT_MUTED := Color(0.867, 0.757, 0.682, 0.62)
const GRID_GREEN := Color(0.25, 1.0, 0.47, 1.0)
const GRID_GREEN_MUTED := Color(0.25, 1.0, 0.47, 0.52)
const ORBIT_YAW_SPEED := 1.15
const ORBIT_PITCH_SPEED := 0.90
const ZOOM_SPEED := 0.72
const GRID_CELL_SIZE_M := 5.0
const GRID_MAJOR_SIZE_M := 25.0
const PREVIEW_CONFIGURATION_ORDER: Array[StringName] = [&"wings", &"gear", &"doors"]
const PREVIEW_CONFIGURATION_LABELS := {
	&"wings": "WINGS",
	&"gear": "GEAR",
	&"doors": "DOORS",
}
const PREVIEW_CONFIGURATION_BUTTON_NAMES := {
	&"wings": "WingsButton",
	&"gear": "LandingGearButton",
	&"doors": "DoorsButton",
}

var current_mode := "tech_categories"

var _category_panel: Control
var _item_panel: Control
var _item_list: VBoxContainer
var _category_heading: Label
var _preview_viewport: SubViewport
var _preview_pivot: Node3D
var _preview_model_root: Node3D
var _preview_camera: Camera3D
var _grid_mesh: MeshInstance3D
var _grid_plane: PlaneMesh
var _grid_material: ShaderMaterial
var _name_label: Label
var _description_label: Label
var _stats_label: Label
var _empty_preview_label: Label
var _preview_controls: Control
var _configuration_controls: Panel
var _configuration_buttons: Dictionary = {}
var _preview_animation_components: Dictionary = {}
var _preview_animation_values: Dictionary = {}
var _preview_animation_targets: Dictionary = {}
var _preview_animation_durations: Dictionary = {}
var _selected_category := ""
var _dragging := false
var _orbit_yaw := 0.55
var _orbit_pitch := 0.28
var _preview_radius := 1.0
var _preview_base_distance := 4.0
var _preview_target_y := 0.0
var _preview_zoom := 1.0
var _held_controls: Dictionary = {}


func _ready() -> void:
	name = "TechnicalIndexView"
	position = Vector2.ZERO
	size = BASE_UI_SIZE
	_build_interface()
	visible = false


func _process(delta: float) -> void:
	if not visible or current_mode != "tech_items":
		return
	var yaw_direction := (1.0 if _is_control_held(&"rotate_right") else 0.0) \
			- (1.0 if _is_control_held(&"rotate_left") else 0.0)
	var pitch_direction := (1.0 if _is_control_held(&"rotate_up") else 0.0) \
			- (1.0 if _is_control_held(&"rotate_down") else 0.0)
	if not is_zero_approx(yaw_direction) or not is_zero_approx(pitch_direction):
		rotate_preview(yaw_direction * ORBIT_YAW_SPEED * delta, pitch_direction * ORBIT_PITCH_SPEED * delta)
	var zoom_direction := (1.0 if _is_control_held(&"zoom_out") else 0.0) \
			- (1.0 if _is_control_held(&"zoom_in") else 0.0)
	if not is_zero_approx(zoom_direction):
		zoom_preview(zoom_direction * ZOOM_SPEED * delta)
	_advance_preview_configurations(delta)


func open() -> void:
	visible = true
	show_categories()


func close() -> void:
	_release_preview_controls()
	visible = false
	_clear_preview()


func show_categories() -> void:
	current_mode = "tech_categories"
	_category_panel.visible = true
	_item_panel.visible = false
	_preview_controls.visible = false
	_selected_category = ""
	_release_preview_controls()
	_clear_selection()
	mode_changed.emit(current_mode)
	_focus_first_deferred(_category_panel)


func go_back() -> bool:
	if current_mode == "tech_items":
		show_categories()
		return true
	if current_mode == "tech_categories":
		exit_requested.emit()
		return true
	return false


func rotate_preview(delta_yaw: float, delta_pitch: float = 0.0) -> void:
	_orbit_yaw = fposmod(_orbit_yaw + delta_yaw, TAU)
	_orbit_pitch = clampf(_orbit_pitch + delta_pitch, deg_to_rad(6.0), deg_to_rad(72.0))
	_apply_preview_camera()


func zoom_preview(delta: float) -> void:
	_preview_zoom = clampf(_preview_zoom + delta, 0.55, 2.2)
	_apply_preview_camera()


func current_buttons() -> Array[Button]:
	var screen := _category_panel if current_mode == "tech_categories" else _item_panel
	var buttons: Array[Button] = []
	_collect_buttons(screen, buttons)
	return buttons


func _build_interface() -> void:
	var computer_backdrop := ColorRect.new()
	computer_backdrop.name = "ComputerBackdrop"
	computer_backdrop.position = Vector2.ZERO
	computer_backdrop.size = BASE_UI_SIZE
	computer_backdrop.color = Color(0.003, 0.008, 0.006, 0.985)
	computer_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(computer_backdrop)

	_category_panel = Control.new()
	_category_panel.name = "CategoryPanel"
	_category_panel.position = Vector2(20.0, 235.0)
	_category_panel.size = Vector2(RAIL_WIDTH - 40.0, 680.0)
	add_child(_category_panel)

	var category_label := _make_label("EQUIPMENT CLASSES", Vector2(18.0, -42.0), MenuTypography.FIELD_LABEL_SIZE, UI_TEXT_MUTED)
	category_label.add_theme_font_override("font", MenuTypography.TECH_FONT)
	_category_panel.add_child(category_label)
	var categories := Catalog.categories()
	for index in range(categories.size()):
		var category := categories[index]
		var button := _make_index_button(category, Vector2(0.0, index * 64.0), RAIL_WIDTH - 40.0)
		button.pressed.connect(_show_category.bind(category))
		_category_panel.add_child(button)
	var category_back := _make_index_button("< MAIN MENU", Vector2(0.0, 410.0), RAIL_WIDTH - 40.0)
	category_back.pressed.connect(func() -> void: exit_requested.emit())
	_category_panel.add_child(category_back)

	_item_panel = Control.new()
	_item_panel.name = "ItemPanel"
	_item_panel.position = Vector2(20.0, 203.0)
	_item_panel.size = Vector2(RAIL_WIDTH - 40.0, 775.0)
	add_child(_item_panel)

	_category_heading = _make_label("", Vector2(18.0, 0.0), MenuTypography.FIELD_LABEL_SIZE, UI_PRIMARY)
	_category_heading.add_theme_font_override("font", MenuTypography.TECH_FONT)
	_category_heading.size = Vector2(400.0, 30.0)
	_item_panel.add_child(_category_heading)

	var scroll := ScrollContainer.new()
	scroll.name = "EquipmentScroll"
	scroll.position = Vector2(0.0, 40.0)
	scroll.size = Vector2(RAIL_WIDTH - 40.0, 625.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_item_panel.add_child(scroll)

	_item_list = VBoxContainer.new()
	_item_list.name = "EquipmentList"
	_item_list.custom_minimum_size = Vector2(RAIL_WIDTH - 56.0, 0.0)
	_item_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_item_list)

	var item_back := _make_index_button("< EQUIPMENT CLASSES", Vector2(0.0, 680.0), RAIL_WIDTH - 40.0)
	item_back.pressed.connect(show_categories)
	_item_panel.add_child(item_back)
	_item_panel.visible = false

	_build_preview_area()


func _build_preview_area() -> void:
	var frame := Panel.new()
	frame.name = "PreviewFrame"
	frame.position = Vector2(RAIL_WIDTH + 56.0, 196.0)
	frame.size = Vector2(BASE_UI_SIZE.x - RAIL_WIDTH - 112.0, 590.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.0, 0.008, 0.004, 1.0)
	frame_style.border_color = GRID_GREEN_MUTED
	frame_style.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", frame_style)
	add_child(frame)

	var preview_container := SubViewportContainer.new()
	preview_container.name = "RotatablePreview"
	preview_container.position = frame.position + Vector2(1.0, 1.0)
	preview_container.size = frame.size - Vector2(2.0, 2.0)
	preview_container.stretch = true
	preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_container.gui_input.connect(_on_preview_gui_input)
	add_child(preview_container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "EquipmentViewport"
	_preview_viewport.size = Vector2i(1370, 588)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_preview_viewport.own_world_3d = true
	preview_container.add_child(_preview_viewport)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.004, 0.002, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.58, 0.72, 0.64, 1.0)
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	_preview_viewport.add_child(environment_node)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	key_light.light_color = Color(1.0, 0.83, 0.67, 1.0)
	key_light.light_energy = 2.0
	key_light.shadow_enabled = true
	_preview_viewport.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(25.0, 145.0, 0.0)
	fill_light.light_color = Color(0.30, 0.82, 0.48, 1.0)
	fill_light.light_energy = 0.85
	_preview_viewport.add_child(fill_light)

	_grid_plane = PlaneMesh.new()
	_grid_plane.size = Vector2(40.0, 40.0)
	_grid_mesh = MeshInstance3D.new()
	_grid_mesh.name = "ComputerGridGround"
	_grid_mesh.mesh = _grid_plane
	_grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid_mesh.visible = false
	var grid_shader := Shader.new()
	grid_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform float grid_span_m = 40.0;
uniform float minor_spacing_m = 5.0;
uniform float major_spacing_m = 25.0;

void fragment() {
	vec2 local_metres = (UV - vec2(0.5)) * grid_span_m;
	vec2 cell = local_metres / minor_spacing_m;
	vec2 grid_width = fwidth(cell);
	vec2 grid_distance = abs(fract(cell - 0.5) - 0.5) / max(grid_width, vec2(0.0001));
	float minor_line = 1.0 - min(min(grid_distance.x, grid_distance.y), 1.0);
	vec2 major_cell = local_metres / major_spacing_m;
	vec2 major_width = fwidth(major_cell);
	vec2 major_distance = abs(fract(major_cell - 0.5) - 0.5) / max(major_width, vec2(0.0001));
	float major_line = 1.0 - min(min(major_distance.x, major_distance.y), 1.0);
	float line = max(minor_line * 0.14, major_line * 0.82);
	float fade = 1.0 - smoothstep(0.28, 0.71, length(UV - vec2(0.5)));
	vec3 green = vec3(0.12, 1.0, 0.35);
	ALBEDO = green * line;
	EMISSION = green * line * 0.72;
	ALPHA = line * fade * 0.78;
}
"""
	_grid_material = ShaderMaterial.new()
	_grid_material.shader = grid_shader
	_grid_material.set_shader_parameter("minor_spacing_m", GRID_CELL_SIZE_M)
	_grid_material.set_shader_parameter("major_spacing_m", GRID_MAJOR_SIZE_M)
	_grid_mesh.material_override = _grid_material
	_preview_viewport.add_child(_grid_mesh)

	_preview_pivot = Node3D.new()
	_preview_pivot.name = "PreviewPivot"
	_preview_viewport.add_child(_preview_pivot)
	_preview_model_root = Node3D.new()
	_preview_model_root.name = "ModelRoot"
	_preview_pivot.add_child(_preview_model_root)

	_preview_camera = Camera3D.new()
	_preview_camera.name = "PreviewCamera"
	_preview_camera.fov = 38.0
	_preview_camera.current = true
	_preview_viewport.add_child(_preview_camera)

	_empty_preview_label = _make_label("SELECT AN ENTRY", frame.position + Vector2(0.0, 268.0), MenuTypography.FIELD_VALUE_SIZE, UI_TEXT_MUTED)
	_empty_preview_label.size = Vector2(frame.size.x, 40.0)
	_empty_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_empty_preview_label)

	var rotation_hint := _make_label("GRID 5 M  //  DRAG VIEW  //  HOLD DISPLAY CONTROL", frame.position + Vector2(22.0, frame.size.y - 40.0), MenuTypography.SUPPORT_SIZE, GRID_GREEN_MUTED)
	rotation_hint.add_theme_font_override("font", MenuTypography.TECH_FONT)
	rotation_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rotation_hint)
	_build_preview_controls(frame)

	_name_label = _make_label("", Vector2(RAIL_WIDTH + 64.0, 818.0), MenuTypography.SCREEN_TITLE_SIZE, UI_PRIMARY)
	_name_label.size = Vector2(780.0, 48.0)
	add_child(_name_label)
	_description_label = _make_label("", Vector2(RAIL_WIDTH + 64.0, 870.0), MenuTypography.FIELD_VALUE_SIZE, UI_TEXT)
	_description_label.size = Vector2(760.0, 120.0)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_description_label)
	_stats_label = _make_label("", Vector2(BASE_UI_SIZE.x - 515.0, 822.0), MenuTypography.SUPPORT_SIZE, UI_TEXT)
	_stats_label.add_theme_font_override("font", MenuTypography.TECH_FONT)
	_stats_label.size = Vector2(450.0, 175.0)
	_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(_stats_label)


func _build_preview_controls(frame: Control) -> void:
	var control_panel := Panel.new()
	control_panel.name = "PreviewControls"
	control_panel.position = frame.position + frame.size - Vector2(244.0, 128.0)
	control_panel.size = Vector2(230.0, 114.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.025, 0.012, 0.90)
	panel_style.border_color = GRID_GREEN_MUTED
	panel_style.set_border_width_all(1)
	control_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(control_panel)
	_preview_controls = control_panel

	var rotate_label := _make_label("ROTATE", Vector2(14.0, 5.0), MenuTypography.SUPPORT_SIZE, GRID_GREEN_MUTED)
	rotate_label.add_theme_font_override("font", MenuTypography.TECH_FONT)
	rotate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_panel.add_child(rotate_label)
	var zoom_label := _make_label("ZOOM", Vector2(137.0, 5.0), MenuTypography.SUPPORT_SIZE, GRID_GREEN_MUTED)
	zoom_label.add_theme_font_override("font", MenuTypography.TECH_FONT)
	zoom_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_panel.add_child(zoom_label)

	var rotate_up := _make_preview_control_button("^", "RotateUpButton", Vector2(47.0, 24.0), "Rotate upward")
	_connect_hold_button(rotate_up, &"rotate_up")
	control_panel.add_child(rotate_up)
	var rotate_left := _make_preview_control_button("<", "RotateLeftButton", Vector2(15.0, 56.0), "Rotate left")
	_connect_hold_button(rotate_left, &"rotate_left")
	control_panel.add_child(rotate_left)
	var rotate_right := _make_preview_control_button(">", "RotateRightButton", Vector2(79.0, 56.0), "Rotate right")
	_connect_hold_button(rotate_right, &"rotate_right")
	control_panel.add_child(rotate_right)
	var rotate_down := _make_preview_control_button("v", "RotateDownButton", Vector2(47.0, 78.0), "Rotate downward")
	_connect_hold_button(rotate_down, &"rotate_down")
	control_panel.add_child(rotate_down)

	var zoom_out := _make_preview_control_button("-", "ZoomOutButton", Vector2(137.0, 50.0), "Zoom out")
	_connect_hold_button(zoom_out, &"zoom_out")
	control_panel.add_child(zoom_out)
	var zoom_in := _make_preview_control_button("+", "ZoomInButton", Vector2(177.0, 50.0), "Zoom in")
	_connect_hold_button(zoom_in, &"zoom_in")
	control_panel.add_child(zoom_in)
	control_panel.visible = false
	_build_configuration_controls(control_panel)


func _build_configuration_controls(rotation_controls: Control) -> void:
	_configuration_controls = Panel.new()
	_configuration_controls.name = "PreviewConfigurationControls"
	_configuration_controls.position = rotation_controls.position + Vector2(0.0, -48.0)
	_configuration_controls.size = Vector2(230.0, 42.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.025, 0.012, 0.90)
	panel_style.border_color = GRID_GREEN_MUTED
	panel_style.set_border_width_all(1)
	_configuration_controls.add_theme_stylebox_override("panel", panel_style)
	add_child(_configuration_controls)

	for index in PREVIEW_CONFIGURATION_ORDER.size():
		var kind := PREVIEW_CONFIGURATION_ORDER[index]
		var button := _make_preview_control_button(
			String(PREVIEW_CONFIGURATION_LABELS[kind]),
			String(PREVIEW_CONFIGURATION_BUTTON_NAMES[kind]),
			Vector2(8.0 + float(index) * 74.0, 6.0),
			"Toggle %s preview" % String(PREVIEW_CONFIGURATION_LABELS[kind]).to_lower(),
			Vector2(66.0, 30.0)
		)
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", MenuTypography.SUPPORT_SIZE)
		button.pressed.connect(_toggle_preview_configuration.bind(kind))
		button.visible = false
		_configuration_controls.add_child(button)
		_configuration_buttons[kind] = button
	_configuration_controls.visible = false


func _connect_hold_button(button: Button, control_name: StringName) -> void:
	button.button_down.connect(_set_control_held.bind(control_name, true))
	button.button_up.connect(_set_control_held.bind(control_name, false))


func _set_control_held(control_name: StringName, held: bool) -> void:
	_held_controls[control_name] = held


func _is_control_held(control_name: StringName) -> bool:
	return bool(_held_controls.get(control_name, false))


func _release_preview_controls() -> void:
	_held_controls.clear()


func _make_preview_control_button(
	label_text: String,
	button_name: String,
	button_position: Vector2,
	tooltip: String,
	button_size: Vector2 = Vector2(30.0, 30.0)
) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = label_text
	button.position = button_position
	button.size = button_size
	button.custom_minimum_size = button_size
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = tooltip
	button.add_theme_font_override("font", MenuTypography.TECH_FONT)
	button.add_theme_font_size_override("font_size", MenuTypography.FIELD_VALUE_SIZE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.02, 0.01, 0.94)
	normal.border_color = GRID_GREEN_MUTED
	normal.set_border_width_all(1)
	var active := normal.duplicate() as StyleBoxFlat
	active.bg_color = Color(GRID_GREEN.r, GRID_GREEN.g, GRID_GREEN.b, 0.82)
	active.border_color = GRID_GREEN
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", active)
	button.add_theme_stylebox_override("focus", active)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_color_override("font_color", GRID_GREEN)
	button.add_theme_color_override("font_hover_color", Color(0.0, 0.08, 0.025, 1.0))
	button.add_theme_color_override("font_focus_color", Color(0.0, 0.08, 0.025, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.0, 0.08, 0.025, 1.0))
	return button


func _show_category(category: String) -> void:
	_selected_category = category
	current_mode = "tech_items"
	_category_panel.visible = false
	_item_panel.visible = true
	_preview_controls.visible = true
	_release_preview_controls()
	_category_heading.text = category
	for child in _item_list.get_children():
		child.free()
	var entries := Catalog.entries_for(category)
	for entry in entries:
		var button := _make_index_button(String(entry.get("name", "UNKNOWN")), Vector2.ZERO, RAIL_WIDTH - 56.0)
		button.pressed.connect(_select_entry.bind(entry))
		_item_list.add_child(button)
	if entries.is_empty():
		_clear_selection()
	else:
		_select_entry(entries[0])
	mode_changed.emit(current_mode)
	_focus_first_deferred(_item_list)


func _select_entry(entry: Dictionary) -> void:
	_clear_preview()
	_name_label.text = String(entry.get("name", "UNKNOWN"))
	_description_label.text = String(entry.get("description", "No description available."))
	var scene_path := String(entry.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_stats_label.text = _format_stats(entry.get("stats", {}))
		_show_preview_error("SCENE UNAVAILABLE")
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_stats_label.text = _format_stats(entry.get("stats", {}))
		_show_preview_error("SCENE COULD NOT BE LOADED")
		return
	var instance := packed.instantiate()
	if instance == null:
		_stats_label.text = _format_stats(entry.get("stats", {}))
		_show_preview_error("SCENE COULD NOT BE INSTANTIATED")
		return
	_prepare_generated_preview_visuals(instance, scene_path)
	_prepare_static_cockpit_pilots(instance)
	_prepare_preview_animation_components(instance)
	var harvested := _harvest_scene_stats(instance)
	_stats_label.text = _format_stats(entry.get("stats", {}), harvested)
	_sanitize_preview_tree(instance)
	if not instance is Node3D:
		instance.free()
		_show_preview_error("NO 3D PREVIEW AVAILABLE")
		return
	_preview_model_root.add_child(instance)
	_preview_pivot.rotation = Vector3.ZERO
	var bounds_data := _calculate_preview_bounds()
	if not bool(bounds_data.get("found", false)):
		_show_preview_error("NO STATIC VISUAL AVAILABLE")
		return
	var bounds: AABB = bounds_data.get("bounds", AABB())
	(instance as Node3D).position -= bounds.get_center()
	_orbit_yaw = 0.55
	_orbit_pitch = 0.28
	_preview_zoom = 1.0
	_fit_preview_camera(bounds.size)
	_empty_preview_label.visible = false


func _prepare_generated_preview_visuals(root: Node, scene_path: String) -> void:
	if scene_path != LAND_CARRIER_SCENE_PATH:
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var node_script := node.get_script() as Script
		if node_script != null and node_script.resource_path == CARRIER_TREAD_SCRIPT_PATH:
			_build_static_track_plates(node)
		for child in node.get_children():
			stack.append(child as Node)


func _prepare_static_cockpit_pilots(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var node_script := node.get_script() as Script
		if node_script != null \
				and node_script.resource_path == PILOT_POSE_SCRIPT_PATH \
				and node.has_method("apply_static_seated_pose"):
			var pose_applied := bool(node.call("apply_static_seated_pose"))
			node.set_meta("technical_index_pilot_pose", "sitting" if pose_applied else "failed")
		for child in node.get_children():
			stack.append(child as Node)


func _prepare_preview_animation_components(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_method("prepare_technical_index_preview") \
				and node.has_method("set_technical_index_preview_fraction") \
				and node.has_method("get_technical_index_preview_fraction") \
				and node.has_method("get_technical_index_preview_duration") \
				and node.has_method("get_technical_index_preview_kind") \
				and bool(node.call("prepare_technical_index_preview")):
			var kind := StringName(node.call("get_technical_index_preview_kind"))
			if PREVIEW_CONFIGURATION_ORDER.has(kind):
				var components: Array = _preview_animation_components.get(kind, [])
				components.append(node)
				_preview_animation_components[kind] = components
				node.set_meta("technical_index_preview_component", true)
				var duration := maxf(float(node.call("get_technical_index_preview_duration")), 0.01)
				_preview_animation_durations[kind] = maxf(
					float(_preview_animation_durations.get(kind, 0.0)),
					duration
				)
				if not _preview_animation_values.has(kind):
					var initial_value := clampf(float(node.call("get_technical_index_preview_fraction")), 0.0, 1.0)
					_preview_animation_values[kind] = initial_value
					_preview_animation_targets[kind] = initial_value
		for child in node.get_children():
			stack.append(child as Node)
	_refresh_configuration_controls()


func _toggle_preview_configuration(kind: StringName) -> void:
	if not _preview_animation_components.has(kind):
		return
	var old_target := float(_preview_animation_targets.get(kind, 0.0))
	var new_target := 0.0 if old_target >= 0.5 else 1.0
	_preview_animation_targets[kind] = new_target
	var button := _configuration_buttons.get(kind) as Button
	if button != null:
		button.set_pressed_no_signal(new_target >= 0.5)


func _advance_preview_configurations(delta: float) -> void:
	for kind_variant in _preview_animation_components.keys():
		var kind := StringName(kind_variant)
		var value := float(_preview_animation_values.get(kind, 0.0))
		var target := float(_preview_animation_targets.get(kind, value))
		if is_equal_approx(value, target):
			continue
		var duration := maxf(float(_preview_animation_durations.get(kind, 1.0)), 0.01)
		value = move_toward(value, target, maxf(delta, 0.0) / duration)
		_preview_animation_values[kind] = value
		for component_variant in _preview_animation_components.get(kind, []):
			var component := component_variant as Node
			if is_instance_valid(component):
				component.call("set_technical_index_preview_fraction", value)


func _refresh_configuration_controls() -> void:
	var any_visible := false
	for kind in PREVIEW_CONFIGURATION_ORDER:
		var button := _configuration_buttons.get(kind) as Button
		if button == null:
			continue
		var available := _preview_animation_components.has(kind)
		button.visible = available
		button.set_pressed_no_signal(float(_preview_animation_targets.get(kind, 0.0)) >= 0.5)
		any_visible = any_visible or available
	if is_instance_valid(_configuration_controls):
		_configuration_controls.visible = any_visible and current_mode == "tech_items"


func _build_static_track_plates(tread: Node) -> void:
	var track_path := tread.get_node_or_null("TrackPath") as Path3D
	if track_path == null or not tread.has_method("_build_default_curve") \
			or not tread.has_method("_rebuild_track_multimesh"):
		return
	var curve_variant: Variant = tread.call("_build_default_curve")
	if not curve_variant is Curve3D:
		return
	track_path.curve = curve_variant as Curve3D
	tread.set("auto_build_path", false)
	tread.call("_rebuild_track_multimesh")


func _harvest_scene_stats(root: Node) -> Dictionary:
	var specs := [
		["MASS", ["mass"], " kg"],
		["MAX SPEED", ["max_speed", "max_forward_speed"], " m/s"],
		["MIN CONTROL SPEED", ["min_control_speed"], " m/s"],
		["MAX HEALTH", ["max_health"], ""],
		["MAX THRUST", ["max_thrust", "max_engine_force"], " N"],
		["RATE OF FIRE", ["fire_rate_hz", "rounds_per_second", "fire_rate"], " /s"],
		["MUZZLE VELOCITY", ["muzzle_velocity", "projectile_speed"], " m/s"],
		["DAMAGE", ["base_damage", "damage"], ""],
		["RANGE", ["max_range", "weapon_range"], " m"],
	]
	var out := {}
	for spec in specs:
		var value: Variant = _find_numeric_property(root, spec[1] as Array)
		if value != null:
			out[spec[0]] = _format_number(float(value)) + String(spec[2])
		if out.size() >= 4:
			break
	return out


func _find_numeric_property(root: Node, candidates: Array) -> Variant:
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		for property_data in node.get_property_list():
			var property_name := String(property_data.get("name", ""))
			if candidates.has(property_name):
				var value: Variant = node.get(property_name)
				if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
					return value
		for child in node.get_children():
			queue.append(child as Node)
	return null


func _sanitize_preview_tree(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	if node is Camera3D:
		(node as Camera3D).current = false
	if node is Light3D:
		(node as Light3D).visible = false
	if node is WorldEnvironment:
		(node as WorldEnvironment).environment = null
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	if node is CPUParticles3D:
		(node as CPUParticles3D).emitting = false
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	if node is AudioStreamPlayer2D:
		(node as AudioStreamPlayer2D).stop()
	if node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stop()
	for child in node.get_children():
		_sanitize_preview_tree(child as Node)
	if node.get_script() != null and not bool(node.get_meta("technical_index_preview_component", false)):
		node.set_script(null)


func _calculate_preview_bounds() -> Dictionary:
	var found := false
	var bounds := AABB()
	var root_inverse := _preview_model_root.global_transform.affine_inverse()
	var stack: Array[Node] = [_preview_model_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).visible:
			var mesh_node := node as MeshInstance3D
			var local_bounds: AABB = (root_inverse * mesh_node.global_transform) * mesh_node.mesh.get_aabb()
			bounds = local_bounds if not found else bounds.merge(local_bounds)
			found = true
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null \
				and (node as MultiMeshInstance3D).visible:
			var multimesh_node := node as MultiMeshInstance3D
			var local_bounds: AABB = (root_inverse * multimesh_node.global_transform) * multimesh_node.get_aabb()
			bounds = local_bounds if not found else bounds.merge(local_bounds)
			found = true
		for child in node.get_children():
			stack.append(child as Node)
	return {"found": found, "bounds": bounds}


func _fit_preview_camera(extents: Vector3) -> void:
	_preview_radius = maxf(extents.length() * 0.5, 0.5)
	var vertical_tangent := tan(deg_to_rad(_preview_camera.fov * 0.5))
	var viewport_aspect := float(_preview_viewport.size.x) / maxf(float(_preview_viewport.size.y), 1.0)
	var horizontal_tangent := vertical_tangent * viewport_aspect
	var half_height := maxf(extents.y * 0.5, 0.25)
	var horizontal_radius := maxf(Vector2(extents.x, extents.z).length() * 0.5, 0.25)
	var projected_vertical_radius := half_height * cos(_orbit_pitch) + horizontal_radius * sin(_orbit_pitch)
	_preview_base_distance = maxf(projected_vertical_radius / vertical_tangent, horizontal_radius / horizontal_tangent) * 1.68
	_preview_base_distance = maxf(_preview_base_distance, _preview_radius * 1.35)
	_preview_target_y = -_preview_radius * 0.08
	var grid_span := maxf(maxf(extents.x, extents.z) * 4.5, 8.0)
	_grid_plane.size = Vector2(grid_span, grid_span)
	_grid_material.set_shader_parameter("grid_span_m", grid_span)
	_grid_mesh.position = Vector3(0.0, -extents.y * 0.5 - maxf(grid_span * 0.002, 0.015), 0.0)
	_grid_mesh.visible = true
	_apply_preview_camera()


func _apply_preview_camera() -> void:
	if not is_instance_valid(_preview_camera):
		return
	var distance := _preview_base_distance * _preview_zoom
	_preview_camera.near = maxf(0.01, distance - _preview_radius * 1.4)
	_preview_camera.far = maxf(1000.0, distance + _preview_radius * 8.0)
	var target := Vector3(0.0, _preview_target_y, 0.0)
	var horizontal_distance := cos(_orbit_pitch) * distance
	var camera_offset := Vector3(
		sin(_orbit_yaw) * horizontal_distance,
		sin(_orbit_pitch) * distance,
		cos(_orbit_yaw) * horizontal_distance
	)
	_preview_camera.position = target + camera_offset
	_preview_camera.look_at(target, Vector3.UP)


func _clear_selection() -> void:
	_name_label.text = ""
	_description_label.text = ""
	_stats_label.text = ""
	_clear_preview()
	_empty_preview_label.text = "SELECT AN ENTRY" if current_mode == "tech_items" else "SELECT AN EQUIPMENT CLASS"
	_empty_preview_label.visible = true


func _clear_preview() -> void:
	_preview_animation_components.clear()
	_preview_animation_values.clear()
	_preview_animation_targets.clear()
	_preview_animation_durations.clear()
	_refresh_configuration_controls()
	if not is_instance_valid(_preview_model_root):
		return
	for child in _preview_model_root.get_children():
		_preview_model_root.remove_child(child)
		child.queue_free()
	if is_instance_valid(_grid_mesh):
		_grid_mesh.visible = false


func _show_preview_error(message: String) -> void:
	_empty_preview_label.text = message
	_empty_preview_label.visible = true


func _format_stats(base_variant: Variant, harvested: Dictionary = {}) -> String:
	var lines: Array[String] = []
	if base_variant is Dictionary:
		for key in (base_variant as Dictionary).keys():
			lines.append("%-20s %s" % [String(key), String((base_variant as Dictionary)[key])])
	for key in harvested.keys():
		if lines.size() >= 7:
			break
		lines.append("%-20s %s" % [String(key), String(harvested[key])])
	return "\n".join(lines)


func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		accept_event()
		return
	if event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		rotate_preview(-motion.relative.x * 0.009, -motion.relative.y * 0.006)
		accept_event()


func _make_index_button(label_text: String, button_position: Vector2, width: float) -> Button:
	var button := Button.new()
	button.position = button_position
	button.size = Vector2(width, 54.0)
	button.custom_minimum_size = Vector2(width, 54.0)
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.set_meta(&"operator_menu_label", label_text)
	button.text = "   " + label_text
	_apply_button_style(button)
	button.add_theme_font_size_override("font_size", MenuTypography.MENU_ITEM_SIZE)
	button.mouse_entered.connect(_refresh_button_indicator.bind(button))
	button.mouse_exited.connect(_refresh_button_indicator.bind(button))
	button.focus_entered.connect(_refresh_button_indicator.bind(button))
	button.focus_exited.connect(_refresh_button_indicator.bind(button))
	return button


func _refresh_button_indicator(button: Button) -> void:
	if button == null:
		return
	var label_text := String(button.get_meta(&"operator_menu_label", button.text.strip_edges()))
	var active := not button.disabled and (button.has_focus() or button.is_hovered())
	button.text = (">  " if active else "   ") + label_text


func _apply_button_style(button: Button) -> void:
	var normal := _button_style(Color.TRANSPARENT, Color.TRANSPARENT)
	var active := _button_style(UI_PRIMARY, UI_HAZARD)
	active.border_width_left = 4
	var pressed := _button_style(UI_PRIMARY_ACTIVE, UI_HAZARD)
	pressed.border_width_left = 4
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", active)
	button.add_theme_stylebox_override("focus", active)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_font_override("font", MenuTypography.TECH_FONT)
	button.add_theme_color_override("font_color", UI_TEXT)
	button.add_theme_color_override("font_hover_color", Color(0.12, 0.07, 0.025, 1.0))
	button.add_theme_color_override("font_focus_color", Color(0.12, 0.07, 0.025, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.12, 0.07, 0.025, 1.0))


func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.content_margin_left = 18.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _make_label(label_text: String, label_position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = label_text
	label.position = label_position
	label.add_theme_font_override("font", MenuTypography.FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _collect_buttons(root: Node, out: Array[Button]) -> void:
	if root == null:
		return
	if root is Button:
		var button := root as Button
		if button.visible and not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			out.append(button)
	for child in root.get_children():
		_collect_buttons(child as Node, out)


func _focus_first_deferred(root: Node) -> void:
	var button := _first_button(root)
	if button != null:
		button.call_deferred("grab_focus")


func _first_button(root: Node) -> Button:
	if root == null:
		return null
	if root is Button and (root as Button).visible and not (root as Button).disabled:
		return root as Button
	for child in root.get_children():
		var found := _first_button(child as Node)
		if found != null:
			return found
	return null
