extends Node
## Slow regional weather. The graphics setting remains the render budget;
## this state controls the air, haze and the dust layer inside that budget.

@export var enabled := true
@export var automatic_hazards := true
@export var weather_change_min_s := 360.0
@export var weather_change_max_s := 600.0
@export var transition_time_s := 180.0

const DUST_SCRIPT = preload("res://Weather/DustFront.gd")
const TWISTER_SCRIPT = preload("res://Weather/Twister.gd")
const ELECTRICAL_SCRIPT = preload("res://Weather/ElectricalStorm.gd")
const REGIMES := [
	{"name": "CLEAR", "wind": 4.0, "visibility": 7200.0, "lower": 1200.0, "upper": 2000.0, "turbulence": 1.0, "dust": 0.02, "twister": 0.0, "electrical": 0.01},
	{"name": "HAZY", "wind": 7.0, "visibility": 4800.0, "lower": 1050.0, "upper": 1850.0, "turbulence": 1.25, "dust": 0.18, "twister": 0.01, "electrical": 0.02},
	{"name": "BLOWING DUST", "wind": 13.0, "visibility": 2900.0, "lower": 850.0, "upper": 1650.0, "turbulence": 1.8, "dust": 0.7, "twister": 0.08, "electrical": 0.03},
	{"name": "UNSTABLE", "wind": 10.0, "visibility": 3900.0, "lower": 950.0, "upper": 1950.0, "turbulence": 2.0, "dust": 0.22, "twister": 0.35, "electrical": 0.65},
]

var _rng := RandomNumberGenerator.new()
var _state := {"wind_x": 4.0, "wind_z": 2.0, "visibility": 7200.0,
	"lower": 1200.0, "upper": 2000.0, "turbulence": 1.0,
	"dust": 0.02, "twister": 0.0, "electrical": 0.01}
var _target: Dictionary = {}
var _regime_name := "CLEAR"
var _elapsed_s := 0.0
var _next_change_s := 0.0
var _tick_s := 0.0
var _hazard_check_s := 30.0
var _last_dust_s := -1800.0
var _last_twister_s := -3600.0
var _last_electrical_s := -1800.0
var _legacy_base_intensity := -1.0
var _legacy_max_intensity := -1.0

func _ready() -> void:
	add_to_group("weather_director")
	_rng.randomize()
	_target = _state.duplicate()
	_next_change_s = _rng.randf_range(weather_change_min_s, weather_change_max_s)
	_apply_state()

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_elapsed_s += delta
	_tick_s += delta
	if _tick_s < 0.25:
		return
	var step := _tick_s
	_tick_s = 0.0
	if _elapsed_s >= _next_change_s:
		_choose_target()
	var blend := 1.0 - exp(-step / maxf(transition_time_s, 1.0))
	for key in _state.keys():
		_state[key] = lerpf(float(_state[key]), float(_target[key]), blend)
	_apply_state()
	if automatic_hazards and _elapsed_s >= _hazard_check_s:
		_hazard_check_s = _elapsed_s + 30.0
		_try_hazards()

func _choose_target() -> void:
	var regime: Dictionary = REGIMES[_rng.randi_range(0, REGIMES.size() - 1)]
	_regime_name = str(regime.name)
	var heading := _rng.randf_range(-PI, PI)
	var speed: float = float(regime.wind) * _rng.randf_range(0.8, 1.2)
	_target = {
		"wind_x": cos(heading) * speed, "wind_z": sin(heading) * speed,
		"visibility": float(regime.visibility) * _rng.randf_range(0.85, 1.15),
		"lower": float(regime.lower) + _rng.randf_range(-80.0, 80.0),
		"upper": float(regime.upper) + _rng.randf_range(-80.0, 80.0),
		"turbulence": float(regime.turbulence), "dust": float(regime.dust),
		"twister": float(regime.twister), "electrical": float(regime.electrical),
	}
	_next_change_s = _elapsed_s + _rng.randf_range(weather_change_min_s, weather_change_max_s)

func _apply_state() -> void:
	var wind := get_tree().get_first_node_in_group("atmospheric_wind")
	if wind != null:
		wind.set("prevailing_velocity_mps", Vector3(float(_state.wind_x), 0.0, float(_state.wind_z)))
		var scale: float = float(_state.turbulence)
		wind.set("gust_amplitude_mps", Vector3(3.0, 1.5, 3.0) * scale)
		wind.set("turbulence_amplitude_mps", Vector3(1.5, 1.0, 1.5) * scale)
	var legacy := get_tree().get_first_node_in_group("weather_legacy_turbulence")
	if legacy != null:
		if _legacy_max_intensity < 0.0:
			_legacy_base_intensity = float(legacy.get("base_intensity"))
			_legacy_max_intensity = float(legacy.get("max_intensity"))
		legacy.set("base_intensity", _legacy_base_intensity * float(_state.turbulence))
		legacy.set("max_intensity", _legacy_max_intensity * float(_state.turbulence))
	var atmosphere := get_tree().get_first_node_in_group("day_night_cycle")
	if atmosphere != null:
		atmosphere.set("ambient_visibility_m", float(_state.visibility))
		atmosphere.set("dust_layer_top_m", float(_state.upper))
		atmosphere.set("dust_deck_vertical_offset_m", float(_state.lower) - float(_state.upper))

func get_snapshot() -> Dictionary:
	return {"regime": _regime_name,
		"wind_mps": Vector3(float(_state.wind_x), 0.0, float(_state.wind_z)),
		"visibility_m": float(_state.visibility),
		"dust_lower_m": float(_state.lower), "dust_upper_m": float(_state.upper),
		"turbulence": float(_state.turbulence),
		"dust_risk": float(_state.dust), "twister_risk": float(_state.twister),
		"electrical_risk": float(_state.electrical)}

func capture_save_state() -> Dictionary:
	var hazards: Array[Dictionary] = []
	for front in get_tree().get_nodes_in_group("dust_front"):
		if front.enabled and front.initialized and front.strength > 0.01:
			hazards.append({"kind": "dust", "position": front.global_position,
				"direction": front.get_travel_velocity().normalized(),
				"elapsed_s": front.elapsed_s, "severity": front.get_severity(),
				"appearance": front.capture_appearance()})
	for twister in get_tree().get_nodes_in_group("twister"):
		if twister.enabled and twister.initialized and twister.strength > 0.01:
			hazards.append({"kind": "twister", "position": twister.global_position,
				"direction": twister.get_travel_velocity().normalized(), "elapsed_s": twister.elapsed_s,
				"appearance": twister.capture_appearance()})
	for storm in get_tree().get_nodes_in_group("electrical_storm"):
		if storm.active:
			hazards.append({"kind": "electrical", "position": storm.global_position,
				"direction": storm.get_travel_velocity().normalized(), "elapsed_s": storm.get_elapsed_s(),
				"appearance": storm.capture_appearance()})
	return {"state": _state.duplicate(), "target": _target.duplicate(),
		"regime": _regime_name, "elapsed_s": _elapsed_s,
		"next_change_s": _next_change_s, "last_dust_s": _last_dust_s,
		"last_twister_s": _last_twister_s, "last_electrical_s": _last_electrical_s,
		"hazards": hazards}

func restore_save_state(saved: Dictionary) -> void:
	if saved.is_empty():
		return
	var state_variant: Variant = saved.get("state", {})
	var target_variant: Variant = saved.get("target", {})
	if state_variant is Dictionary and target_variant is Dictionary:
		for key in _state.keys():
			_state[key] = float((state_variant as Dictionary).get(key, _state[key]))
			_target[key] = float((target_variant as Dictionary).get(key, _state[key]))
	_regime_name = str(saved.get("regime", _regime_name))
	_elapsed_s = maxf(float(saved.get("elapsed_s", 0.0)), 0.0)
	_next_change_s = maxf(float(saved.get("next_change_s", _elapsed_s + 300.0)), _elapsed_s + 1.0)
	_last_dust_s = float(saved.get("last_dust_s", _elapsed_s))
	_last_twister_s = float(saved.get("last_twister_s", _elapsed_s))
	_last_electrical_s = float(saved.get("last_electrical_s", _elapsed_s))
	_hazard_check_s = _elapsed_s + 30.0
	_apply_state()
	var hazards_variant: Variant = saved.get("hazards", [])
	if not hazards_variant is Array:
		return
	for entry_variant in hazards_variant:
		if not entry_variant is Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var position: Variant = entry.get("position", Vector3.ZERO)
		var direction: Variant = entry.get("direction", Vector3.RIGHT)
		if not position is Vector3 or not direction is Vector3:
			continue
		var age := maxf(float(entry.get("elapsed_s", 0.0)), 0.0)
		match str(entry.get("kind", "")):
			"dust":
				var front := get_tree().get_first_node_in_group("dust_front") as Node3D
				if front != null:
					front.set("severity", clampi(int(entry.get("severity", 2)), 1, 5))
					var appearance: Dictionary = entry.get("appearance", {"width": front._base_dimensions.x,
						"height": front._base_dimensions.y, "depth": front._base_dimensions.z,
						"outline": [5.0, 0.035, 0.0, 0.0]})
					front.call("start_at", position, direction, appearance)
					front.set("elapsed_s", age)
					front.set("strength", smoothstep(0.0, 45.0, age) * (1.0 - smoothstep(float(front.get("lifetime_s")) - 180.0, float(front.get("lifetime_s")), age)))
			"twister":
				var twister := TWISTER_SCRIPT.new() as Node3D
				twister.name = "WeatherTwister"
				get_parent().add_child(twister)
				twister.start_at(position, direction, entry.get("appearance", twister.capture_appearance()))
				twister.elapsed_s = age
				twister.strength = smoothstep(0.0, 15.0, age) * (1.0 - smoothstep(twister.lifetime_s - 30.0, twister.lifetime_s, age))
			"electrical":
				var storm := ELECTRICAL_SCRIPT.new() as Node3D
				storm.name = "ElectricalStorm"
				get_parent().add_child(storm)
				storm.start_at(position, direction, entry.get("appearance", {"radius": 1700.0,
					"aspect": 1.0, "yaw": 0.0, "outline": [5.0, 0.12, 0.8, 0.07]}))
				storm.restore_elapsed_s(age)

func _try_hazards() -> void:
	if not TerrainNavGrid.is_ready() or GameSession.has_pending_save_state():
		return
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null or (carrier.has_method("is_initial_placement_complete") and not carrier.is_initial_placement_complete()):
		return
	if _elapsed_s - _last_dust_s > 900.0 and _rng.randf() < float(_state.dust) * 30.0 / 1500.0:
		_spawn_dust(carrier)
	if _elapsed_s - _last_twister_s > 1500.0 and _rng.randf() < float(_state.twister) * 30.0 / 2400.0:
		_spawn_twister(carrier)
	if _elapsed_s - _last_electrical_s > 900.0 and _rng.randf() < float(_state.electrical) * 30.0 / 1200.0:
		_spawn_electrical(carrier)

func _spawn_dust(carrier: Node3D) -> void:
	var front := get_tree().get_first_node_in_group("dust_front") as Node3D
	if front == null:
		front = DUST_SCRIPT.new() as Node3D
		front.name = "DustFront"
		get_parent().add_child(front)
	if bool(front.get("initialized")) and bool(front.get("enabled")) \
			and float(front.get("elapsed_s")) < float(front.get("lifetime_s")):
		return
	var direction := _wind_direction()
	var center := carrier.global_position - direction * 8500.0
	center.y = carrier.global_position.y - 550.0
	front.set("severity", clampi(roundi(2.0 + float(_state.dust) * 2.0 + _rng.randf_range(-0.5, 0.5)), 1, 5))
	front.set("enabled", true)
	front.call("start_at", center, direction)
	if front.has_meta("spawned_from_vehicle_menu"):
		front.remove_meta("spawned_from_vehicle_menu")
	_last_dust_s = _elapsed_s

func _spawn_twister(carrier: Node3D) -> void:
	for candidate in get_tree().get_nodes_in_group("twister"):
		if candidate.enabled and candidate.initialized and candidate.strength > 0.01:
			return
		if candidate.name == "WeatherTwister":
			candidate.queue_free()
	var twister := TWISTER_SCRIPT.new() as Node3D
	twister.name = "WeatherTwister"
	get_parent().add_child(twister)
	twister.start_at(carrier.global_position - _wind_direction() * 4000.0, _wind_direction())
	_last_twister_s = _elapsed_s

func _spawn_electrical(carrier: Node3D) -> void:
	for candidate in get_tree().get_nodes_in_group("electrical_storm"):
		if candidate.active:
			return
	var storm := ELECTRICAL_SCRIPT.new() as Node3D
	storm.name = "ElectricalStorm"
	get_parent().add_child(storm)
	storm.start_at(carrier.global_position - _wind_direction() * 3200.0, _wind_direction())
	_last_electrical_s = _elapsed_s

func _wind_direction() -> Vector3:
	var direction := Vector3(float(_state.wind_x), 0.0, float(_state.wind_z))
	return direction.normalized() if direction.length_squared() > 0.01 else Vector3.RIGHT
