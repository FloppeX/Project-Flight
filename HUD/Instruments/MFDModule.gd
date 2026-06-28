extends InstrumentModule
class_name MFDModule

var available_modes: Array[String] = ["MAP", "TARGET", "WEAPONS", "DAMAGE", "SYSTEMS"]
var current_mode_index: int = 0

var mode_label: Label = null
var content_label: Label = null
var custom_view_root: Control = null
var mode_views: Dictionary = {}


func configure(config: Dictionary) -> void:
	super.configure(config)
	if config.has("modes"):
		available_modes.clear()
		for mode in config.get("modes"):
			available_modes.append(str(mode).to_upper())
	if available_modes.is_empty():
		available_modes = ["MAP"]
	current_mode_index = clampi(int(config.get("initial_mode_index", 0)), 0, available_modes.size() - 1)
	_build_mfd()
	_apply_mode_visibility()


func add_mode_view(mode: String, view: Control) -> void:
	if view == null:
		return
	var mode_key := mode.to_upper()
	mode_views[mode_key] = view
	if view.get_parent() != null:
		view.get_parent().remove_child(view)
	custom_view_root.add_child(view)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.offset_left = 0.0
	view.offset_top = 0.0
	view.offset_right = 0.0
	view.offset_bottom = 0.0
	view.custom_minimum_size = Vector2.ZERO
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_mode_visibility()


func update_from_aircraft(_delta: float) -> void:
	var mode := _current_mode()
	mode_label.text = "%s  < >" % mode
	content_label.visible = not mode_views.has(mode)
	if not content_label.visible:
		return

	match mode:
		"MAP":
			content_label.text = _map_text()
		"TARGET":
			content_label.text = _target_text()
		"WEAPONS":
			content_label.text = _weapons_text()
		"DAMAGE":
			content_label.text = _damage_text()
		"SYSTEMS":
			content_label.text = _systems_text()
		"RADAR":
			content_label.text = _target_text()
		_:
			content_label.text = mode


func interact(local_pos: Vector2) -> bool:
	if available_modes.size() <= 1:
		return false
	if local_pos.x < size.x * 0.35:
		_cycle_mode(-1)
	else:
		_cycle_mode(1)
	return true


func _build_mfd() -> void:
	for child in body.get_children():
		child.queue_free()

	if title_label != null:
		title_label.visible = false
		title_label.custom_minimum_size = Vector2.ZERO
	body.clip_contents = true

	custom_view_root = Control.new()
	custom_view_root.name = "ModeViewRoot"
	custom_view_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_view_root.anchor_left = 0.015
	custom_view_root.anchor_top = 0.015
	custom_view_root.anchor_right = 0.985
	custom_view_root.anchor_bottom = 0.985
	custom_view_root.offset_left = 0.0
	custom_view_root.offset_top = 0.0
	custom_view_root.offset_right = 0.0
	custom_view_root.offset_bottom = 0.0
	custom_view_root.clip_contents = true
	body.add_child(custom_view_root)

	mode_label = Label.new()
	mode_label.name = "Mode"
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_label.add_theme_color_override("font_color", COLOR_TEXT)
	mode_label.add_theme_color_override("font_outline_color", Color.BLACK)
	mode_label.add_theme_constant_override("outline_size", 2)
	mode_label.add_theme_font_size_override("font_size", 10)
	mode_label.anchor_left = 0.0
	mode_label.anchor_right = 1.0
	mode_label.anchor_top = 0.0
	mode_label.anchor_bottom = 0.0
	mode_label.offset_bottom = 14.0
	mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_label.z_index = 20
	body.add_child(mode_label)

	content_label = Label.new()
	content_label.name = "Content"
	content_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_label.add_theme_color_override("font_color", COLOR_TEXT)
	content_label.add_theme_font_size_override("font_size", 14)
	custom_view_root.add_child(content_label)
	content_label.set_anchors_preset(Control.PRESET_FULL_RECT)


func _cycle_mode(direction: int) -> void:
	current_mode_index = (current_mode_index + direction) % available_modes.size()
	if current_mode_index < 0:
		current_mode_index += available_modes.size()
	_apply_mode_visibility()


func _apply_mode_visibility() -> void:
	if custom_view_root == null:
		return
	var mode := _current_mode()
	for key in mode_views.keys():
		var view := mode_views[key] as Control
		if view != null:
			view.visible = str(key) == mode
	if content_label != null:
		content_label.visible = not mode_views.has(mode)


func _current_mode() -> String:
	if available_modes.is_empty():
		return ""
	return available_modes[current_mode_index].to_upper()


func _map_text() -> String:
	if aircraft == null or not is_instance_valid(aircraft):
		return "NO DATA"
	var heading := 0.0
	if aircraft is Node3D:
		var forward: Vector3 = -(aircraft as Node3D).global_transform.basis.z
		heading = fposmod(rad_to_deg(atan2(forward.x, forward.z)), 360.0)
	return "HDG %03d\nALT %dm\nSPD %dm/s" % [
		int(heading),
		int(_get_number("local_altitude")),
		int(_get_number("air_velocity")),
	]


func _target_text() -> String:
	var targeting := _find_child_with_method("target_next")
	if targeting == null or not ("current_target" in targeting):
		return "NO TARGET"
	var target: Variant = targeting.get("current_target")
	if target == null or not is_instance_valid(target):
		return "NO TARGET"
	if aircraft is Node3D and target is Node3D:
		var distance := (aircraft as Node3D).global_position.distance_to((target as Node3D).global_position)
		return "%s\n%d m" % [str((target as Node).name).to_upper(), int(distance)]
	return str((target as Node).name).to_upper()


func _weapons_text() -> String:
	var control := _find_child_named("ControlWeapons")
	if control == null or not control.has_method("get_weapon_status"):
		return "WEAPONS\nN/A"
	var status: Dictionary = control.call("get_weapon_status")
	return "%s\nCOUNT %d\nAMMO %d" % [
		str(status.get("selected_type", "NONE")).to_upper(),
		int(status.get("weapon_count", 0)),
		int(status.get("total_ammo", 0)),
	]


func _damage_text() -> String:
	return "STRUCT\n%d%%" % int(_get_health_percent())


func _systems_text() -> String:
	return "FUEL %d%%\nGEAR %s\nG %.1f" % [
		int(_get_fuel_percent()),
		_gear_text(),
		_get_number("local_g_force", 1.0),
	]


func _gear_text() -> String:
	var gear := _find_first_module_by_type("landing_gear")
	if gear == null:
		return "N/A"
	if "is_deployed" in gear and bool(gear.get("is_deployed")):
		return "DOWN"
	if "is_stowed" in gear and bool(gear.get("is_stowed")):
		return "UP"
	return "MOVING"


func _get_number(property_name: String, fallback: float = 0.0) -> float:
	if aircraft != null and is_instance_valid(aircraft) and property_name in aircraft:
		return float(aircraft.get(property_name))
	return fallback
