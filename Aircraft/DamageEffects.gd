extends Node
class_name DamageEffects

## Manages progressive aircraft damage effects across 3 severity tiers.
## Attach as a child of an Aircraft node.

# Thresholds (fraction of max_health)
const TIER_1_THRESHOLD := 0.6  # Below 60%
const TIER_2_THRESHOLD := 0.4  # Below 40%
const TIER_3_THRESHOLD := 0.2  # Below 20%

# Which effect was rolled for each tier (index into the tier's pool)
var _tier1_effect := -1
var _tier2_effect := -1
var _tier3_effect := -1

# Runtime state
var _aircraft: Aircraft = null
var _engine_module: Node = null        # AircraftModule_Engine
var _aero_module: Node = null          # SimpleAero
var _gear_module: Node = null          # AircraftModule_LandingGear
var _flaps_module: Node = null         # AircraftModule_Flaps
var _hud_node: Node3D = null           # HeadsUpDisplay

# Saved original values (to know what we're degrading from)
var _original_pitch_power: float = 0.0
var _original_roll_power: float = 0.0
var _original_yaw_power: float = 0.0

# Engine sputter state (tier 3)
var _sputter_timer: float = 0.0
var _sputter_interval: float = 6.0    # seconds between sputters
var _sputter_cut_duration: float = 1.5
var _engine_is_cut := false
var _engine_cut_timer: float = 0.0

# Fuel leak state (tier 1)
var _fuel_leak_active := false

# HUD flicker state (tier 2)
var _hud_flicker_active := false
var _hud_flicker_timer: float = 0.0

# Smoke trail
var _smoke_timer: float = 0.0
var _smoke_active_tier := 0  # 0 = no smoke, 1/2/3 = tier level

# Structural roll bias (tier 3 candidate in the pool but now tier 2 uses it — actually
# let's keep the design as discussed: tier 3 gets HUD/instruments blackout)
var _roll_bias: float = 0.0
var _drag_penalty: float = 0.0


func _ready() -> void:
	# Find aircraft parent
	_aircraft = get_parent() as Aircraft
	if not _aircraft:
		push_error("DamageEffects: parent is not an Aircraft node")
		return

	# Connect to damage signal
	_aircraft.damaged.connect(_on_aircraft_damaged)

	# Cache module references (available after aircraft._ready sets up modules)
	call_deferred("_cache_modules")


func _cache_modules() -> void:
	if not _aircraft:
		return

	# Engine
	var engines := _aircraft.find_modules_by_type("engine")
	if not engines.is_empty():
		_engine_module = engines[0]

	# Landing gear
	var gears := _aircraft.find_modules_by_type("landing_gear")
	if not gears.is_empty():
		_gear_module = gears[0]

	# Flaps
	var flaps := _aircraft.find_modules_by_type("flaps")
	if not flaps.is_empty():
		_flaps_module = flaps[0]

	# SimpleAero (direct child, not a module)
	_aero_module = _aircraft.get_node_or_null("SimpleAero")

	# Cache original aero values
	if _aero_module:
		_original_pitch_power = _aero_module.pitch_power
		_original_roll_power = _aero_module.roll_power
		_original_yaw_power = _aero_module.yaw_power

	# HUD — it's usually a child of the aircraft
	for child in _aircraft.get_children():
		if child is Node3D and child.has_method("_draw_hud"):
			_hud_node = child
			break
	if not _hud_node:
		# Try by name
		_hud_node = _aircraft.get_node_or_null("HeadsUpDisplay")


func _on_aircraft_damaged(_damage_amount: float, current_health: float) -> void:
	var health_fraction: float = current_health / _aircraft.max_health

	# Check each tier threshold (only trigger once per tier)
	if _tier1_effect == -1 and health_fraction < TIER_1_THRESHOLD:
		_trigger_tier1()

	if _tier2_effect == -1 and health_fraction < TIER_2_THRESHOLD:
		_trigger_tier2()

	if _tier3_effect == -1 and health_fraction < TIER_3_THRESHOLD:
		_trigger_tier3()


# ─── TIER 1: Warning (below 60%) ─────────────────────────────────────────────

func _trigger_tier1() -> void:
	_tier1_effect = randi_range(0, 2)
	_smoke_active_tier = 1  # Thin smoke

	match _tier1_effect:
		0:
			_apply_hydraulic_failure()
		1:
			_apply_fuel_leak()
		2:
			_apply_flap_jam()


func _apply_hydraulic_failure() -> void:
	# Deploy gear and prevent retraction
	if _gear_module and _gear_module.has_method("deploy"):
		_gear_module.deploy()


func _apply_fuel_leak() -> void:
	_fuel_leak_active = true


func _apply_flap_jam() -> void:
	# Lock flaps at current position by disabling movement
	if _flaps_module:
		_flaps_module.set("is_moving", false)


# ─── TIER 2: Serious (below 40%) ─────────────────────────────────────────────

func _trigger_tier2() -> void:
	_tier2_effect = randi_range(0, 2)
	_smoke_active_tier = 2  # Medium smoke

	match _tier2_effect:
		0:
			_apply_engine_cap()
		1:
			_apply_control_damage()
		2:
			_apply_hud_flicker()


func _apply_engine_cap() -> void:
	# Max throttle capped at 70% — enforced each frame in _process
	pass


func _apply_control_damage() -> void:
	# Halve control surface effectiveness
	if _aero_module:
		_aero_module.pitch_power = _original_pitch_power * 0.5
		_aero_module.roll_power = _original_roll_power * 0.5
		_aero_module.yaw_power = _original_yaw_power * 0.5


func _apply_hud_flicker() -> void:
	_hud_flicker_active = true


# ─── TIER 3: Critical (below 20%) ────────────────────────────────────────────

func _trigger_tier3() -> void:
	_tier3_effect = randi_range(0, 2)
	_smoke_active_tier = 3  # Thick smoke

	match _tier3_effect:
		0:
			_apply_engine_sputter()
		1:
			_apply_structural_failure()
		2:
			_apply_hud_blackout()


func _apply_engine_sputter() -> void:
	# Engine randomly cuts out — handled in _process
	_sputter_timer = randf_range(2.0, 5.0)


func _apply_structural_failure() -> void:
	# Increased drag + random roll pull
	_roll_bias = randf_range(-0.3, 0.3)
	if absf(_roll_bias) < 0.15:
		_roll_bias = 0.3 if randf() > 0.5 else -0.3
	_drag_penalty = 0.3
	if _aero_module:
		_aero_module.forward_drag_strength += _drag_penalty


func _apply_hud_blackout() -> void:
	if _hud_node:
		_hud_node.visible = false


# ─── PER-FRAME UPDATES ───────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _aircraft or _aircraft.current_health <= 0:
		return

	_update_gear_lock()
	_update_flap_lock(delta)
	_update_fuel_leak(delta)
	_update_engine_cap()
	_update_engine_sputter(delta)
	_update_hud_flicker(delta)
	_update_roll_bias(delta)
	_update_smoke_trail(delta)


func _update_gear_lock() -> void:
	# Tier 1 effect 0: keep gear deployed, block stow attempts
	if _tier1_effect != 0:
		return
	if _gear_module and not _gear_module.is_deployed:
		_gear_module.deploy()


func _update_flap_lock(_delta: float) -> void:
	# Tier 1 effect 2: prevent flap movement
	if _tier1_effect != 2:
		return
	if _flaps_module:
		_flaps_module.set("is_moving", false)
		_flaps_module.set("target_flap_position", _flaps_module.get("flap_position"))


func _update_fuel_leak(delta: float) -> void:
	if not _fuel_leak_active:
		return
	# Drain fuel at 2x normal idle rate
	if _aircraft.has_method("request_energy"):
		_aircraft.request_energy("fuel", 2.0 * delta)


func _update_engine_cap() -> void:
	# Tier 2 effect 0: cap throttle at 70%
	if _tier2_effect != 0:
		return
	if _engine_module and _engine_module.current_power > 0.7:
		_engine_module.current_power = 0.7


func _update_engine_sputter(delta: float) -> void:
	# Tier 3 effect 0: randomly cut engine
	if _tier3_effect != 0:
		return

	if _engine_is_cut:
		_engine_cut_timer -= delta
		if _engine_cut_timer <= 0.0:
			# Restart engine
			_engine_is_cut = false
			if _engine_module and _engine_module.has_method("engine_start"):
				_engine_module.engine_start()
			_sputter_timer = randf_range(3.0, 8.0)
	else:
		_sputter_timer -= delta
		if _sputter_timer <= 0.0:
			# Cut engine
			_engine_is_cut = true
			_engine_cut_timer = randf_range(1.0, 2.0)
			if _engine_module:
				_engine_module.is_engine_working = false
				_engine_module.current_power = 0.0


func _update_hud_flicker(delta: float) -> void:
	if not _hud_flicker_active or not _hud_node:
		return
	_hud_flicker_timer -= delta
	if _hud_flicker_timer <= 0.0:
		_hud_node.visible = not _hud_node.visible
		if _hud_node.visible:
			_hud_flicker_timer = randf_range(0.5, 2.5)  # On duration
		else:
			_hud_flicker_timer = randf_range(0.1, 0.6)  # Off duration


func _update_roll_bias(delta: float) -> void:
	if is_zero_approx(_roll_bias):
		return
	if not _aircraft:
		return
	# Apply a constant roll torque to make the plane pull to one side
	var torque := _aircraft.global_transform.basis.z * _roll_bias * _aircraft.mass
	_aircraft.apply_torque(torque)


func _update_smoke_trail(delta: float) -> void:
	if _smoke_active_tier <= 0:
		return

	# Spawn interval and size based on tier
	var interval: float
	var puff_scale: float
	var puff_count_per_spawn: int
	match _smoke_active_tier:
		1:
			interval = 0.25
			puff_scale = 1.5
			puff_count_per_spawn = 1
		2:
			interval = 0.15
			puff_scale = 2.5
			puff_count_per_spawn = 1
		_:
			interval = 0.08
			puff_scale = 3.5
			puff_count_per_spawn = 2

	_smoke_timer -= delta
	if _smoke_timer <= 0.0:
		_smoke_timer = interval
		for i in puff_count_per_spawn:
			_spawn_damage_smoke(puff_scale)


func _spawn_damage_smoke(base_scale: float) -> void:
	var puff := MeshInstance3D.new()
	get_tree().current_scene.add_child(puff)

	# Spawn behind aircraft
	var offset := _aircraft.global_transform.basis.z * randf_range(2.0, 5.0)
	puff.global_position = _aircraft.global_position - offset + Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-0.5, 0.5),
		randf_range(-1.0, 1.0)
	)

	var sphere := SphereMesh.new()
	sphere.radial_segments = 6
	sphere.rings = 4
	var r := randf_range(0.8, 1.4)
	sphere.radius = r
	sphere.height = r * 2.0
	puff.mesh = sphere

	var s := randf_range(0.8, 1.2) * base_scale
	puff.scale = Vector3(s, s, s)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var grey := randf_range(0.15, 0.35)
	mat.albedo_color = Color(grey, grey, grey, 0.85)
	puff.material_override = mat

	ParticleManager.add_rising_smoke(puff, randf_range(2.0, 4.0), puff.scale, randf_range(2.0, 4.0), randf_range(-0.3, 0.3))


# ─── QUERY ────────────────────────────────────────────────────────────────────

## Returns a dictionary describing all active damage effects (for HUD display etc.)
func get_active_effects() -> Dictionary:
	var effects := {}
	if _tier1_effect >= 0:
		match _tier1_effect:
			0: effects["hydraulic_failure"] = true
			1: effects["fuel_leak"] = true
			2: effects["flap_jam"] = true
	if _tier2_effect >= 0:
		match _tier2_effect:
			0: effects["engine_cap"] = true
			1: effects["control_damage"] = true
			2: effects["hud_flicker"] = true
	if _tier3_effect >= 0:
		match _tier3_effect:
			0: effects["engine_sputter"] = true
			1: effects["structural_failure"] = true
			2: effects["hud_blackout"] = true
	effects["smoke_tier"] = _smoke_active_tier
	return effects
