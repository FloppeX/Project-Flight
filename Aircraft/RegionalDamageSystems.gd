extends Node
## Deterministic effects of regional health. Authored flight tuning is captured
## once; refreshing, loading, or taking another hit never compounds multipliers.

var model: AircraftPartDamageModel
var craft: Aircraft
var aero: Node
var engines: Array[Node] = []
var bases: Dictionary = {}
var fuel_leak_rate: float = 0.0
var pilot_wounded: bool = false
var warnings: PackedStringArray = []
var _smoke: GPUParticles3D
var _flicker_time := 0.0

func _ready() -> void:
	model = get_parent() as AircraftPartDamageModel
	craft = model.get_parent() as Aircraft
	aero = craft.get_node_or_null("SimpleAero")
	if aero != null:
		for key in ["pitch_power", "roll_power", "yaw_power", "simplified_pitch_power_override", "stability_strength", "directional_stability_strength"]:
			bases[key] = float(aero.get(key))
	for node in craft.get_children():
		if node is AircraftModule_Engine:
			engines.append(node)
	set_physics_process(false)
	set_process(false)

func fraction(zone: StringName) -> float:
	return model.get_zone_health(zone) / maxf(model.get_zone_max_health(zone), 0.001)

func refresh() -> void:
	if craft == null:
		return
	var left := fraction(&"left_wing")
	var right := fraction(&"right_wing")
	var tail := fraction(&"tail")
	var horizontal := minf(tail, fraction(&"horizontal_stabilizer"))
	var vertical := minf(tail, fraction(&"vertical_stabilizer"))
	var hull := fraction(&"fuselage")
	var cockpit := fraction(&"cockpit")
	var engine := fraction(&"engine")
	pilot_wounded = cockpit > 0.0 and cockpit < 0.35 and not bool(craft.get_meta("camera_replaced_by_ejected_pilot", false))
	var pilot_scale := 0.85 if pilot_wounded else 1.0
	var fatal_controls := model.is_zone_destroyed(&"tail") or model.is_zone_destroyed(&"left_wing") or model.is_zone_destroyed(&"right_wing") or bool(craft.get_meta("pilot_dead", false))
	if aero != null:
		var roll_scale := (0.15 + 0.85 * left + 0.15 + 0.85 * right) * 0.5
		var pitch_scale := 0.1 + 0.9 * horizontal
		var yaw_scale := 0.1 + 0.9 * vertical
		aero.pitch_power = bases.pitch_power * (0.0 if fatal_controls else pitch_scale * pilot_scale)
		aero.roll_power = bases.roll_power * (0.0 if fatal_controls else roll_scale * pilot_scale)
		aero.yaw_power = bases.yaw_power * (0.0 if fatal_controls else yaw_scale * pilot_scale)
		if float(bases.simplified_pitch_power_override) >= 0.0 or fatal_controls:
			aero.simplified_pitch_power_override = 0.0 if fatal_controls else bases.simplified_pitch_power_override * pitch_scale * pilot_scale
		aero.damage_left_lift_scale = 0.0 if left <= 0.0 else 0.45 + 0.55 * left
		aero.damage_right_lift_scale = 0.0 if right <= 0.0 else 0.45 + 0.55 * right
		aero.damage_drag_multiplier = 1.0 + (1.0 - hull) * 0.8 + (2.0 - left - right) * 0.15
		aero.damage_flap_effectiveness = (left + right) * 0.5
		if not fatal_controls:
			aero.stability_strength = bases.stability_strength * pitch_scale
			aero.directional_stability_strength = bases.directional_stability_strength * yaw_scale
	for node in engines:
		node.damage_power_factor = 0.0 if engine <= 0.0 else 0.2 + 0.8 * engine
		node.damage_disabled = engine <= 0.0
		if node.damage_disabled:
			node.current_power = 0.0
			if node.is_engine_working:
				node.engine_stop()
	fuel_leak_rate = maxf(0.5 - hull, 0.0) * 4.0
	craft.set_meta("pilot_wounded", pilot_wounded)
	var gear := craft.get_node_or_null("LandingGear")
	if gear != null:
		gear.set("damage_jammed", hull < 0.25 or bool(gear.get("damage_collapsed")))
	for node in craft.find_children("*", "Node3D", true, false):
		if not node is Hardpoint:
			continue
		var x := craft.to_local(node.global_position).x
		if absf(x) < 0.8:
			continue
		var wing := left if x > 0.0 else right
		node.damage_disabled = wing < 0.25
		if wing <= 0.0:
			node.lose_with_support()
	warnings.clear()
	if left < 0.99: warnings.append("LEFT WING LOST" if left <= 0.0 else "LEFT AILERON DEGRADED")
	if right < 0.99: warnings.append("RIGHT WING LOST" if right <= 0.0 else "RIGHT AILERON DEGRADED")
	if minf(horizontal, vertical) < 0.99: warnings.append("TAIL LOST - NO CONTROL" if tail <= 0.0 else "TAIL CONTROLS DEGRADED")
	if engine < 0.99: warnings.append("ENGINE FAILED" if engine <= 0.0 else "ENGINE POWER REDUCED")
	if bool(craft.get_meta("propeller_broken", false)): warnings.append("PROPELLER SHATTERED")
	if hull < 0.99: warnings.append("FUSELAGE DAMAGED")
	if fuel_leak_rate > 0.0: warnings.append("FUEL LEAK")
	if hull < 0.25: warnings.append("GEAR JAMMED")
	if bool(craft.get_meta("gear_sheared", false)): warnings.append("GEAR TORN OFF")
	elif bool(craft.get_meta("gear_collapsed",false)): warnings.append("GEAR COLLAPSED")
	if left < 0.4 or right < 0.4: warnings.append("FLAP LIFT REDUCED")
	if left < 0.25 or right < 0.25: warnings.append("WING STORES DISABLED")
	if pilot_wounded: warnings.append("PILOT WOUNDED")
	if cockpit < 0.75: warnings.append("COCKPIT INSTRUMENT FAULT")
	craft.set_meta("damage_warnings", warnings)
	craft.set_meta("engine_health_fraction", engine)
	craft.set_meta("fuel_leak_rate", fuel_leak_rate)
	_update_smoke(engine)
	# Fuel is charged by Aircraft inside its prepare/consume energy-budget frame.
	set_physics_process(false)
	set_process(cockpit < 0.75 and cockpit > 0.0)
	if cockpit >= 0.75:
		_set_hud_visible(true)

func consume_fuel_leak(delta: float) -> void:
	if fuel_leak_rate > 0.0:
		craft.request_energy("fuel", minf(fuel_leak_rate * delta, float(craft.available_energy.get("fuel", 0.0))))

func _process(delta: float) -> void:
	_flicker_time += delta
	# Short deterministic outages become more frequent as cockpit health falls.
	var health := fraction(&"cockpit")
	_set_hud_visible(fmod(_flicker_time, 2.0) > (0.75 - health) * 0.7)

func _set_hud_visible(value: bool) -> void:
	var hud := craft.get_node_or_null("HeadsUpDisplay") as Node3D
	if hud != null and not bool(craft.get_meta("pilot_dead", false)):
		hud.visible = value

func _update_smoke(engine: float) -> void:
	if engine >= 0.9 and _smoke == null:
		return
	if _smoke == null:
		_smoke = GPUParticles3D.new()
		_smoke.name = "EngineDamageSmoke"
		_smoke.local_coords = false
		_smoke.amount = 64
		_smoke.lifetime = 3.0
		_smoke.visibility_aabb = AABB(Vector3(-150,-150,-150),Vector3(300,300,300))
		var material := ParticleProcessMaterial.new()
		material.direction = Vector3(0,1,0)
		material.spread = 25.0
		material.gravity = Vector3(0,0.8,0)
		material.initial_velocity_min = 0.5
		material.initial_velocity_max = 1.5
		material.scale_min = 0.45
		material.scale_max = 1.4
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.12,0.13,0.14,0.6))
		gradient.set_color(1, Color(0.24,0.25,0.26,0.0))
		var texture := GradientTexture1D.new()
		texture.gradient = gradient
		material.color_ramp = texture
		_smoke.process_material = material
		var sphere := SphereMesh.new()
		sphere.radial_segments = 8
		sphere.rings = 4
		var smoke_material := StandardMaterial3D.new()
		smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke_material.vertex_color_use_as_albedo = true
		sphere.material = smoke_material
		_smoke.draw_pass_1 = sphere
		craft.add_child(_smoke)
	if not engines.is_empty():
		_smoke.global_position = engines[0].get_damage_smoke_global_position()
	else:
		var collider := craft.get_node_or_null("EngineDamageCollider") as Node3D
		if collider != null: _smoke.global_position = collider.global_position
	_smoke.amount_ratio = clampf(1.0 - engine, 0.15, 1.0)
	_smoke.emitting = engine < 0.9 and not (model.engine_attached_to_tail and model.is_zone_destroyed(&"tail"))

func get_display_state() -> Dictionary:
	var state: Dictionary = {}
	for zone: StringName in AircraftPartDamageModel.DISPLAY_ZONES:
		state[zone] = {"fraction": fraction(zone), "destroyed": model.is_zone_destroyed(zone)}
	# Older saves may have damage to one stabilizer without full tail failure.
	state[&"tail"].fraction = minf(fraction(&"tail"), minf(fraction(&"horizontal_stabilizer"), fraction(&"vertical_stabilizer")))
	return {"zones": state, "warnings": warnings, "pilot_wounded": pilot_wounded}
