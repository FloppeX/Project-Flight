extends InstrumentModule
class_name WarningLightModule

var lights: Array[String] = ["ENGINE", "WEAPONS", "CONTROLS", "GEAR", "STALL"]
var light_rects: Dictionary = {}
var light_labels: Dictionary = {}


func configure(config: Dictionary) -> void:
	super.configure(config)
	if config.has("lights"):
		lights.clear()
		for light in config.get("lights"):
			lights.append(str(light).to_upper())
	_build_lights()


func update_from_aircraft(_delta: float) -> void:
	for light in lights:
		var active := false
		var color := COLOR_WARN
		match light:
			"ENGINE":
				active = not _has_working_engine()
				color = COLOR_BAD
			"WEAPONS":
				active = _weapon_count() <= 0
				color = COLOR_WARN
			"CONTROLS":
				active = _controls_warning()
				color = COLOR_BAD
			"GEAR":
				active = _gear_warning()
				color = COLOR_WARN
			"STALL":
				active = _stall_warning()
				color = COLOR_BAD
			"MISSILE":
				active = _missile_lock_warning()
				color = COLOR_BAD
			_:
				active = false
		_set_light(light, active, color)


func _build_lights() -> void:
	for child in body.get_children():
		child.queue_free()
	light_rects.clear()
	light_labels.clear()

	var row := HBoxContainer.new()
	row.name = "LightRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)

	for light in lights:
		var item := VBoxContainer.new()
		item.custom_minimum_size = Vector2(70.0, 0.0)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item)

		var rect := ColorRect.new()
		rect.name = light + "Light"
		rect.custom_minimum_size = Vector2(44.0, 14.0)
		rect.color = COLOR_MUTED
		item.add_child(rect)

		var label := Label.new()
		label.text = light
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", COLOR_TEXT)
		label.add_theme_font_size_override("font_size", 10)
		item.add_child(label)

		light_rects[light] = rect
		light_labels[light] = label


func _set_light(light: String, active: bool, color: Color) -> void:
	var rect := light_rects.get(light) as ColorRect
	if rect != null:
		rect.color = color if active else COLOR_MUTED
	var label := light_labels.get(light) as Label
	if label != null:
		label.add_theme_color_override("font_color", color if active else COLOR_TEXT)


func _has_working_engine() -> bool:
	var engine := _find_first_module_by_type("engine")
	if engine == null:
		return false
	if "is_engine_working" in engine:
		return bool(engine.get("is_engine_working"))
	if "current_power" in engine:
		return float(engine.get("current_power")) > 0.02
	return false


func _weapon_count() -> int:
	var control := _find_child_named("ControlWeapons")
	if control != null and control.has_method("get_weapon_status"):
		var status: Dictionary = control.call("get_weapon_status")
		return int(status.get("weapon_count", 0))
	return 0


func _controls_warning() -> bool:
	if aircraft == null or not is_instance_valid(aircraft):
		return false
	if aircraft.has_meta("controls_disabled") and bool(aircraft.get_meta("controls_disabled")):
		return true
	return _get_health_percent() <= 30.0


func _gear_warning() -> bool:
	var gear := _find_first_module_by_type("landing_gear")
	if gear == null:
		return false
	if ("is_deploying" in gear and bool(gear.get("is_deploying"))) or ("is_stowing" in gear and bool(gear.get("is_stowing"))):
		return true
	var low_alt := aircraft != null and is_instance_valid(aircraft) and "local_altitude" in aircraft and float(aircraft.get("local_altitude")) < 100.0
	var fast_down := aircraft != null and is_instance_valid(aircraft) and "linear_velocity" in aircraft and float(aircraft.get("linear_velocity").y) < -6.0
	var stowed := "is_stowed" in gear and bool(gear.get("is_stowed"))
	return low_alt and fast_down and stowed


func _stall_warning() -> bool:
	var aero := _find_child_with_method("get_stall_severity")
	return aero != null and float(aero.call("get_stall_severity")) > 0.25


func _missile_lock_warning() -> bool:
	var targeting := _find_child_with_method("get_target_lock_time")
	if targeting == null:
		return false
	var required := 1.0
	if "required_lock_time" in targeting:
		required = maxf(float(targeting.get("required_lock_time")), 0.001)
	return float(targeting.call("get_target_lock_time")) >= required
