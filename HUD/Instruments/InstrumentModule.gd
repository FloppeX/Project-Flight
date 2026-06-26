extends PanelContainer
class_name InstrumentModule

const COLOR_BG := Color(0.015, 0.025, 0.025, 0.92)
const COLOR_BORDER := Color(0.0, 0.85, 0.62, 0.65)
const COLOR_TEXT := Color(0.72, 1.0, 0.84, 1.0)
const COLOR_WARN := Color(1.0, 0.72, 0.18, 1.0)
const COLOR_BAD := Color(1.0, 0.18, 0.12, 1.0)
const COLOR_MUTED := Color(0.22, 0.34, 0.31, 1.0)

var module_id: String = ""
var module_title: String = ""
var instrument_panel: Node = null
var aircraft: Node = null
var title_label: Label = null
var body: Control = null

var _root: VBoxContainer = null


func configure(config: Dictionary) -> void:
	module_id = str(config.get("id", name))
	module_title = str(config.get("title", module_id.to_upper()))
	name = module_id.capitalize().replace(" ", "") + "Module"
	_ensure_frame()
	title_label.text = module_title


func set_context(panel: Node, aircraft_node: Node) -> void:
	instrument_panel = panel
	aircraft = aircraft_node


func set_aircraft_reference(aircraft_node: Node) -> void:
	aircraft = aircraft_node


func update_from_aircraft(_delta: float) -> void:
	pass


func interact(_local_pos: Vector2) -> bool:
	return false


func _ensure_frame() -> void:
	if _root != null:
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.border_color = COLOR_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	add_theme_stylebox_override("panel", style)

	_root = VBoxContainer.new()
	_root.name = "ModuleRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("separation", 2)

	title_label = Label.new()
	title_label.name = "Title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", COLOR_TEXT)
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.custom_minimum_size = Vector2(0.0, 16.0)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(title_label)

	body = Control.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(body)


func _find_first_module_by_type(module_type: String) -> Node:
	if aircraft == null or not is_instance_valid(aircraft):
		return null
	if aircraft.has_method("find_modules_by_type"):
		var modules: Array = aircraft.call("find_modules_by_type", module_type)
		for module in modules:
			if module != null and is_instance_valid(module):
				return module
	return null


func _find_child_named(node_name: String) -> Node:
	if aircraft == null or not is_instance_valid(aircraft):
		return null
	return aircraft.find_child(node_name, true, false)


func _find_child_with_method(method_name: String) -> Node:
	if aircraft == null or not is_instance_valid(aircraft):
		return null
	return _find_child_with_method_recursive(aircraft, method_name)


func _find_child_with_method_recursive(node: Node, method_name: String) -> Node:
	if node.has_method(method_name):
		return node
	for child in node.get_children():
		var found := _find_child_with_method_recursive(child, method_name)
		if found != null:
			return found
	return null


func _get_fuel_percent() -> float:
	if aircraft == null or not is_instance_valid(aircraft):
		return 0.0
	if not ("available_energy" in aircraft) or not ("energy_containers" in aircraft):
		return 0.0
	var available: Dictionary = aircraft.get("available_energy")
	if not available.has("fuel"):
		return 0.0
	var current_fuel := float(available.get("fuel", 0.0))
	var total_capacity := 0.0
	for container in aircraft.get("energy_containers"):
		if container == null or not is_instance_valid(container):
			continue
		if "EnergyType" in container and str(container.get("EnergyType")) == "fuel":
			total_capacity += float(container.get("MaxCapacity"))
	if total_capacity <= 0.0:
		return 0.0
	return clampf((current_fuel / total_capacity) * 100.0, 0.0, 100.0)


func _get_health_percent() -> float:
	if aircraft == null or not is_instance_valid(aircraft):
		return 0.0
	if not ("current_health" in aircraft) or not ("max_health" in aircraft):
		return 100.0
	var max_health := maxf(float(aircraft.get("max_health")), 0.001)
	return clampf(float(aircraft.get("current_health")) / max_health * 100.0, 0.0, 100.0)


func _status_color(percent: float, warn_at: float = 35.0, bad_at: float = 15.0) -> Color:
	if percent <= bad_at:
		return COLOR_BAD
	if percent <= warn_at:
		return COLOR_WARN
	return COLOR_TEXT
