extends InstrumentModule
class_name TextInstrumentModule

var instrument_type: String = "speed"
var value_label: Label = null
var value_bar: ProgressBar = null


func configure(config: Dictionary) -> void:
	super.configure(config)
	instrument_type = str(config.get("instrument", instrument_type))
	_build_readout()


func _build_readout() -> void:
	for child in body.get_children():
		child.queue_free()

	value_label = Label.new()
	value_label.name = "Value"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_color_override("font_color", COLOR_TEXT)
	value_label.add_theme_font_size_override("font_size", 16)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(value_label)
	value_label.set_anchors_preset(Control.PRESET_FULL_RECT)

	value_bar = ProgressBar.new()
	value_bar.name = "Bar"
	value_bar.show_percentage = false
	value_bar.visible = instrument_type in ["fuel", "damage", "stall", "missile_lock", "flaps", "engine"]
	value_bar.anchor_left = 0.08
	value_bar.anchor_right = 0.92
	value_bar.anchor_top = 0.82
	value_bar.anchor_bottom = 0.95
	body.add_child(value_bar)


func update_from_aircraft(_delta: float) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		_set_value("--", COLOR_MUTED, 0.0)
		return

	match instrument_type:
		"speed":
			_set_value("%d\nm/s" % int(_get_number("air_velocity")), COLOR_TEXT)
		"altitude":
			_set_value("%d\nm" % int(_get_number("local_altitude")), COLOR_TEXT)
		"vertical_speed":
			var vs := 0.0
			if "linear_velocity" in aircraft:
				vs = float(aircraft.get("linear_velocity").y)
			_set_value("%+.1f\nm/s" % vs, COLOR_WARN if absf(vs) > 18.0 else COLOR_TEXT)
		"fuel":
			var fuel := _get_fuel_percent()
			_set_value("%d%%" % int(fuel), _status_color(fuel, 30.0, 12.0), fuel)
		"gear":
			_update_gear()
		"flaps":
			var flap := _get_flap_position()
			_set_value("%d%%" % int(flap * 100.0), COLOR_TEXT, flap * 100.0)
		"stall":
			var stall := _get_stall_severity()
			_set_value("%d%%" % int(stall * 100.0), COLOR_BAD if stall > 0.55 else (COLOR_WARN if stall > 0.2 else COLOR_TEXT), stall * 100.0)
		"missile_lock":
			var lock := _get_missile_lock_ratio()
			_set_value("LOCK" if lock >= 1.0 else "%d%%" % int(lock * 100.0), COLOR_TEXT if lock >= 1.0 else COLOR_WARN, lock * 100.0)
		"engine":
			var engine_power := _get_engine_power()
			_set_value("%d%%" % int(engine_power * 100.0), COLOR_TEXT if engine_power > 0.02 else COLOR_BAD, engine_power * 100.0)
		"damage":
			var health := _get_health_percent()
			_set_value("%d%%" % int(health), _status_color(health, 60.0, 30.0), health)
		"g_force":
			_set_value("%.1f g" % _get_number("local_g_force", 1.0), COLOR_TEXT)
		"weapons":
			_update_weapons()
		_:
			_set_value("--", COLOR_MUTED)


func interact(_local_pos: Vector2) -> bool:
	match instrument_type:
		"gear":
			return _toggle_gear()
		"flaps":
			return _cycle_flaps()
		"missile_lock":
			var targeting := _find_child_with_method("lock_target_to_hud_center")
			if targeting != null:
				targeting.call("lock_target_to_hud_center")
				return true
		"engine":
			var control := _find_child_named("ControlEngine")
			if control != null and control.has_method("toggle_engine"):
				control.call("toggle_engine")
				return true
		"weapons":
			var weapons := _find_child_named("ControlWeapons")
			if weapons != null and weapons.has_method("cycle_weapon_type"):
				weapons.call("cycle_weapon_type")
				return true
	return false


func _set_value(text: String, color: Color, bar_value: float = NAN) -> void:
	if value_label != null:
		value_label.text = text
		value_label.add_theme_color_override("font_color", color)
	if value_bar != null and not is_nan(bar_value):
		value_bar.value = clampf(bar_value, 0.0, 100.0)
		value_bar.modulate = color


func _get_number(property_name: String, fallback: float = 0.0) -> float:
	if property_name in aircraft:
		return float(aircraft.get(property_name))
	return fallback


func _update_gear() -> void:
	var gear := _find_first_module_by_type("landing_gear")
	if gear == null:
		_set_value("N/A", COLOR_MUTED)
		return
	if "is_deployed" in gear and bool(gear.get("is_deployed")):
		_set_value("DOWN", COLOR_TEXT)
	elif "is_stowed" in gear and bool(gear.get("is_stowed")):
		_set_value("UP", COLOR_TEXT)
	elif ("is_deploying" in gear and bool(gear.get("is_deploying"))) or ("is_stowing" in gear and bool(gear.get("is_stowing"))):
		_set_value("MOVING", COLOR_WARN)
	else:
		_set_value("UNK", COLOR_MUTED)


func _get_flap_position() -> float:
	var flaps := _find_first_module_by_type("flaps")
	if flaps != null and "flap_position" in flaps:
		return clampf(float(flaps.get("flap_position")), 0.0, 1.0)
	return 0.0


func _get_stall_severity() -> float:
	var aero := _find_child_with_method("get_stall_severity")
	if aero != null:
		return clampf(float(aero.call("get_stall_severity")), 0.0, 1.0)
	return 0.0


func _get_missile_lock_ratio() -> float:
	var targeting := _find_child_with_method("get_target_lock_time")
	if targeting == null:
		return 0.0
	var required := 1.0
	if "required_lock_time" in targeting:
		required = maxf(float(targeting.get("required_lock_time")), 0.001)
	return clampf(float(targeting.call("get_target_lock_time")) / required, 0.0, 1.0)


func _get_engine_power() -> float:
	var engine := _find_first_module_by_type("engine")
	if engine == null:
		return 0.0
	if engine.has_method("get_throttle_ratio"):
		return clampf(float(engine.call("get_throttle_ratio")), 0.0, 1.0)
	if "current_power" in engine:
		return clampf(float(engine.get("current_power")), 0.0, 1.0)
	return 0.0


func _update_weapons() -> void:
	var weapons := _find_child_named("ControlWeapons")
	if weapons == null or not weapons.has_method("get_weapon_status"):
		_set_value("N/A", COLOR_MUTED)
		return
	var status: Dictionary = weapons.call("get_weapon_status")
	_set_value("%s\nx%d" % [
		str(status.get("selected_type", "NONE")).to_upper(),
		int(status.get("weapon_count", 0)),
	], COLOR_TEXT)


func _toggle_gear() -> bool:
	var controller := _find_child_named("ControlLandingGear")
	if controller != null and controller.has_method("toggle_gear"):
		controller.call("toggle_gear")
		return true
	var gear := _find_first_module_by_type("landing_gear")
	if gear == null:
		return false
	if "is_deployed" in gear and bool(gear.get("is_deployed")) and gear.has_method("stow"):
		gear.call("stow")
		return true
	if gear.has_method("deploy"):
		gear.call("deploy")
		return true
	return false


func _cycle_flaps() -> bool:
	var flaps := _find_first_module_by_type("flaps")
	if flaps == null:
		return false
	var next := _get_flap_position() + 0.25
	if next > 1.01:
		next = 0.0
	if flaps.has_method("flap_set_position"):
		flaps.call("flap_set_position", next)
		return true
	return false
