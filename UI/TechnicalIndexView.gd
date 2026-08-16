extends Control
## Interactive main-menu equipment reference. Gameplay scenes are instantiated
## off-tree, stripped of behaviour, and then placed in an isolated preview world.

signal exit_requested
signal mode_changed(mode: String)

const Catalog = preload("res://UI/TechnicalIndexCatalog.gd")
const MenuTypography = preload("res://UI/MenuTypography.gd")

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

var current_mode := "tech_categories"

var _category_panel: Control
var _item_panel: Control
var _item_list: VBoxContainer
var _category_heading: Label
var _preview_viewport: SubViewport
var _preview_pivot: Node3D
var _preview_model_root: Node3D
var _preview_camera: Camera3D
var _name_label: Label
var _description_label: Label
var _stats_label: Label
var _empty_preview_label: Label
var _selected_category := ""
var _dragging := false
var _preview_pitch := -0.12


func _ready() -> void:
	name = "TechnicalIndexView"
	position = Vector2.ZERO
	size = BASE_UI_SIZE
	_build_interface()
	visible = false


func open() -> void:
	visible = true
	show_categories()


func close() -> void:
	visible = false
	_clear_preview()


func show_categories() -> void:
	current_mode = "tech_categories"
	_category_panel.visible = true
	_item_panel.visible = false
	_selected_category = ""
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


func rotate_preview(delta_yaw: float) -> void:
	if is_instance_valid(_preview_pivot):
		_preview_pivot.rotation.y += delta_yaw


func current_buttons() -> Array[Button]:
	var screen := _category_panel if current_mode == "tech_categories" else _item_panel
	var buttons: Array[Button] = []
	_collect_buttons(screen, buttons)
	return buttons


func _build_interface() -> void:
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
	frame_style.bg_color = UI_SURFACE
	frame_style.border_color = UI_OUTLINE
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
	environment.background_color = Color(0.018, 0.021, 0.024, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.72, 0.78, 1.0)
	environment.ambient_light_energy = 0.68
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
	fill_light.light_color = Color(0.50, 0.62, 0.78, 1.0)
	fill_light.light_energy = 0.85
	_preview_viewport.add_child(fill_light)

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

	var rotation_hint := _make_label("DRAG TO ROTATE  //  LEFT / RIGHT", frame.position + Vector2(22.0, frame.size.y - 40.0), MenuTypography.SUPPORT_SIZE, UI_TEXT_MUTED)
	rotation_hint.add_theme_font_override("font", MenuTypography.TECH_FONT)
	rotation_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rotation_hint)

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


func _show_category(category: String) -> void:
	_selected_category = category
	current_mode = "tech_items"
	_category_panel.visible = false
	_item_panel.visible = true
	_category_heading.text = category
	for child in _item_list.get_children():
		child.free()
	var entries := Catalog.entries_for(category)
	for entry in entries:
		var button := _make_index_button(String(entry.get("name", "UNKNOWN")), Vector2.ZERO, RAIL_WIDTH - 56.0)
		button.pressed.connect(_select_entry.bind(entry))
		_item_list.add_child(button)
	_clear_selection()
	mode_changed.emit(current_mode)
	_focus_first_deferred(_item_list)


func _select_entry(entry: Dictionary) -> void:
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
	var harvested := _harvest_scene_stats(instance)
	_stats_label.text = _format_stats(entry.get("stats", {}), harvested)
	_sanitize_preview_tree(instance)
	_clear_preview()
	if not instance is Node3D:
		instance.free()
		_show_preview_error("NO 3D PREVIEW AVAILABLE")
		return
	_preview_model_root.add_child(instance)
	_preview_pivot.rotation = Vector3(_preview_pitch, -0.55, 0.0)
	var bounds_data := _calculate_preview_bounds()
	if not bool(bounds_data.get("found", false)):
		_show_preview_error("NO STATIC VISUAL AVAILABLE")
		return
	var bounds: AABB = bounds_data.get("bounds", AABB())
	(instance as Node3D).position -= bounds.get_center()
	_fit_preview_camera(bounds.size)
	_empty_preview_label.visible = false


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
	if node.get_script() != null:
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
		for child in node.get_children():
			stack.append(child as Node)
	return {"found": found, "bounds": bounds}


func _fit_preview_camera(extents: Vector3) -> void:
	var radius := maxf(extents.length() * 0.5, 0.5)
	var vertical_tangent := tan(deg_to_rad(_preview_camera.fov * 0.5))
	var viewport_aspect := float(_preview_viewport.size.x) / maxf(float(_preview_viewport.size.y), 1.0)
	var horizontal_tangent := vertical_tangent * viewport_aspect
	var half_height := maxf(extents.y * 0.5, 0.25)
	var half_width := maxf(maxf(extents.x, extents.z) * 0.5, 0.25)
	var distance := maxf(half_height / vertical_tangent, half_width / horizontal_tangent) * 1.68
	distance = maxf(distance, radius * 1.35)
	_preview_camera.near = maxf(0.01, distance - radius * 1.4)
	_preview_camera.far = maxf(1000.0, distance + radius * 8.0)
	_preview_camera.position = Vector3(0.0, radius * 0.08, distance)
	_preview_camera.look_at(Vector3.ZERO, Vector3.UP)


func _clear_selection() -> void:
	_name_label.text = ""
	_description_label.text = ""
	_stats_label.text = ""
	_clear_preview()
	_empty_preview_label.text = "SELECT AN ENTRY" if current_mode == "tech_items" else "SELECT AN EQUIPMENT CLASS"
	_empty_preview_label.visible = true


func _clear_preview() -> void:
	if not is_instance_valid(_preview_model_root):
		return
	for child in _preview_model_root.get_children():
		_preview_model_root.remove_child(child)
		child.queue_free()


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
		_preview_pivot.rotation.y += motion.relative.x * 0.009
		_preview_pitch = clampf(_preview_pitch + motion.relative.y * 0.006, -0.7, 0.7)
		_preview_pivot.rotation.x = _preview_pitch
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
