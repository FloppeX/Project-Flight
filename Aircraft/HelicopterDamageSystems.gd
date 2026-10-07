extends "res://Aircraft/RegionalDamageSystems.gd"
## Shared cockpit/fuel/smoke presentation, helicopter-specific mechanical effects.
func _ready() -> void:
	model = get_parent() as AircraftPartDamageModel
	craft = model.get_parent() as Aircraft
	aero = craft.get_node("SimpleAero")
	engines.append(craft.get_node("Engine"))
	set_physics_process(false)

func refresh() -> void:
	var main := fraction(&"main_rotor")
	var lower := fraction(&"lower_rotor") if model.coaxial else main
	var tail := fraction(&"tail")
	var anti_torque := fraction(&"tail_rotor") if not model.coaxial else 1.0
	var motor := fraction(&"engine")
	var hull := fraction(&"fuselage")
	var cockpit := fraction(&"cockpit")
	pilot_wounded = cockpit > 0.0 and cockpit < 0.35 and not bool(craft.get_meta("camera_replaced_by_ejected_pilot",false))
	aero.damage_rotor_lift = 0.0 if minf(main,lower) <= 0.0 else (0.45+0.55*minf(main,lower))
	aero.damage_cyclic = aero.damage_rotor_lift * (0.85 if pilot_wounded else 1.0)
	aero.damage_engine_health = motor
	aero.damage_yaw_authority = (0.7+0.3*tail) if model.coaxial else anti_torque
	aero.damage_yaw_damping = (0.25+0.75*tail) if model.coaxial else (0.04+0.96*anti_torque)
	aero.damage_fin_stability = tail
	aero.damage_torque_imbalance = (lower-main) * 0.65 if model.coaxial else 1.0-anti_torque
	aero.damage_rotor_direction = -model.rotor.upper_rotor_direction
	aero.damage_vibration = maxf(1.0-minf(main,lower), (1.0-anti_torque)*0.3)
	aero.damage_drag = 1.0+(1.0-hull)*0.6+(1.0-tail)*0.15
	for node in engines:
		node.damage_power_factor = 0.0 if motor <= 0.0 else 0.2+motor*0.8
		node.damage_disabled = motor <= 0.0
		if motor <= 0.0:
			node.current_power = 0.0
			if node.is_engine_working: node.engine_stop()
	fuel_leak_rate = maxf(0.5-hull,0.0)*4.0
	craft.set_meta("pilot_wounded",pilot_wounded)
	craft.set_meta("engine_health_fraction",motor)
	craft.set_meta("fuel_leak_rate",fuel_leak_rate)
	var gear := craft.get_node_or_null("LandingGear")
	if gear != null: gear.damage_jammed = hull < 0.25 or gear.damage_collapsed
	warnings.clear()
	if main < 0.99 or lower < 0.99: warnings.append("MAIN ROTOR LOST" if minf(main,lower)<=0.0 else "ROTOR DAMAGED - VIBRATION")
	if minf(main,lower)>0.0 and minf(main,lower)<0.55: warnings.append("ROTOR DAMAGE WORSENING")
	if tail < 0.99: warnings.append("TAIL LOST - YAW UNSTABLE" if tail<=0.0 else "TAIL STABILITY REDUCED")
	if anti_torque < 0.99: warnings.append("TAIL ROTOR FAILED" if anti_torque<=0.0 else "YAW AUTHORITY REDUCED")
	if motor < 0.99: warnings.append("ENGINE FAILED - AUTOROTATE" if motor<=0.0 else "ENGINE POWER REDUCED")
	if cockpit < 0.75: warnings.append("COCKPIT INSTRUMENT FAULT")
	if pilot_wounded: warnings.append("PILOT WOUNDED")
	if hull < 0.99: warnings.append("FUSELAGE DAMAGED")
	if fuel_leak_rate > 0.0: warnings.append("FUEL LEAK")
	if bool(craft.get_meta("gear_sheared",false)): warnings.append("GEAR TORN OFF")
	craft.set_meta("damage_warnings",warnings)
	_update_smoke(motor)
	set_process(cockpit > 0.0 and cockpit < 0.75)
	if cockpit >= 0.75: _set_hud_visible(true)

func get_display_state() -> Dictionary:
	var zones := {}
	for zone in model.get_damage_state():
		zones[zone] = {"fraction":fraction(zone),"destroyed":model.is_zone_destroyed(zone)}
	var current_warnings := warnings.duplicate()
	if aero.rotor_energy.rpm < 0.75 and not model.is_ground_supported() and aero.rotor_energy.collective > 0.05:
		current_warnings.insert(0,"LOW ROTOR RPM - LOWER COLLECTIVE")
	return {"helicopter":true,"coaxial":model.coaxial,"zones":zones,"warnings":current_warnings,
		"pilot_wounded":pilot_wounded,"rotor_rpm":aero.rotor_energy.rpm,"autorotating":aero.rotor_energy.autorotating}
