extends Node3D
## A charged part of the dust layer with sparks and irregular ground strikes.

@export var duration_s := 420.0
@export var travel_speed_mps := 7.0
@export var cloud_radius_m := 1700.0
const SHAPE = preload("res://Weather/StormShape.gd")
var outline := Vector4(5.0, 0.12, 0.8, 0.07)
var axis_ratio := Vector2.ONE
var shape_yaw := 0.0
var _base_radius := 1700.0
var active := false
var _elapsed_s := 0.0
var _next_strike_s := 0.0
var _strike_age_s := -1.0
var _direction := Vector3.RIGHT
var _rng := RandomNumberGenerator.new()
var _bolt_root: Node3D
var _flash: OmniLight3D
var _sky_flash: OmniLight3D
var _impact_halo: Sprite3D
var _sky_halo: Sprite3D
var _visuals: Node3D
var _last_strike_origin := Vector3.ZERO
var _last_strike_impact := Vector3.ZERO

const STRIKE_HOLD_S := 0.5
const STRIKE_FADE_S := 1.0
const STRIKE_TOTAL_S := STRIKE_HOLD_S + STRIKE_FADE_S
const ICY_BLUE := Color(0.70, 0.88, 1.0)
const BOLT_WHITE := Color(1.0, 1.0, 1.0)

func _ready() -> void:
	add_to_group("electrical_storm")
	_rng.randomize()
	_base_radius = cloud_radius_m
	_visuals = preload("res://Weather/ElectricalStormVisuals.gd").new() as Node3D
	_visuals.name = "ChargedDustLayer"
	add_child(_visuals)
	_visuals.setup(self)
	_bolt_root = Node3D.new()
	_bolt_root.name = "LightningBolt"
	add_child(_bolt_root)
	_flash = OmniLight3D.new()
	_flash.name = "LightningFlash"
	_flash.light_color = ICY_BLUE
	_flash.light_energy = 14.0
	_flash.omni_range = 1250.0
	_flash.shadow_enabled = false
	_flash.visible = false
	add_child(_flash)
	_sky_flash = OmniLight3D.new()
	_sky_flash.name = "LightningSkyFlash"
	_sky_flash.light_color = Color(0.82, 0.93, 1.0)
	_sky_flash.light_energy = 9.0
	_sky_flash.omni_range = 1400.0
	_sky_flash.shadow_enabled = false
	_sky_flash.visible = false
	add_child(_sky_flash)
	var halo_texture := _make_halo_texture()
	_impact_halo = _make_halo("LightningImpactHalo", halo_texture, 3.0)
	_sky_halo = _make_halo("LightningSkyHalo", halo_texture, 5.0)
	_sky_halo.modulate.a = 0.45

func _make_halo_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.96, 0.99, 1.0, 0.72))
	gradient.set_color(1, Color(0.48, 0.78, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.gradient = gradient
	return texture

func _make_halo(node_name: String, texture: Texture2D, pixel_size: float) -> Sprite3D:
	var halo := Sprite3D.new()
	halo.name = node_name
	halo.texture = texture
	halo.pixel_size = pixel_size
	halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	halo.shaded = false
	halo.modulate = Color(0.78, 0.91, 1.0, 0.65)
	halo.visible = false
	add_child(halo)
	return halo

func create_appearance() -> Dictionary:
	return {"radius": _base_radius * _rng.randf_range(0.5, 1.7),
		"aspect": _rng.randf_range(0.45, 1.0), "yaw": _rng.randf_range(-PI, PI),
		"outline": SHAPE.encode_outline(SHAPE.random_outline(_rng))}

func capture_appearance() -> Dictionary:
	return {"radius": cloud_radius_m, "aspect": axis_ratio.y, "yaw": shape_yaw,
		"outline": SHAPE.encode_outline(outline)}

func start_at(center: Vector3, direction: Vector3, appearance: Dictionary = {}) -> void:
	_end_strike()
	var profile := create_appearance() if appearance.is_empty() else appearance
	cloud_radius_m = maxf(float(profile.get("radius", _base_radius)), 100.0)
	axis_ratio = Vector2(1.0, clampf(float(profile.get("aspect", 1.0)), 0.3, 1.0))
	shape_yaw = float(profile.get("yaw", 0.0))
	outline = SHAPE.decode_outline(profile.get("outline"), Vector4(5.0, 0.12, 0.8, 0.07))
	global_transform = Transform3D(Basis(Vector3.UP, shape_yaw), center)
	_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	if _direction.is_zero_approx():
		_direction = Vector3.RIGHT
	_elapsed_s = 0.0
	_next_strike_s = _rng.randf_range(5.0, 12.0)
	active = true
	_visuals.reset_shape()
	_update_cloud(0.16)

func get_travel_velocity() -> Vector3:
	return _direction * travel_speed_mps

func get_elapsed_s() -> float:
	return _elapsed_s

func restore_elapsed_s(age: float) -> void:
	_end_strike()
	_elapsed_s = clampf(age, 0.0, duration_s)
	_next_strike_s = _elapsed_s + _rng.randf_range(3.0, 12.0)
	_update_cloud(0.16)

func get_footprint(scale_factor: float = 1.0, future_s: float = 0.0) -> PackedVector3Array:
	var points := PackedVector3Array()
	var center := global_position + get_travel_velocity() * future_s
	for i in 33:
		var angle := TAU * float(i) / 32.0
		points.append(center + global_basis * get_cell_offset(angle, scale_factor))
	return points

func get_cell_offset(angle: float, fraction: float = 1.0) -> Vector3:
	var distance := cloud_radius_m * fraction * SHAPE.edge(angle, outline)
	return Vector3(cos(angle) * distance * axis_ratio.x, 0.0, sin(angle) * distance * axis_ratio.y)

func get_cell_envelope(point: Vector3) -> float:
	var p := to_local(point)
	var q := Vector2(p.x, p.z) / (axis_ratio * cloud_radius_m)
	return q.length() / SHAPE.edge(q.angle(), outline)

func _get_dust_layer_heights() -> Vector2:
	var deck_y := global_position.y
	var deck := get_tree().get_first_node_in_group("flight_deck_manager")
	if deck != null and deck.has_method("get_deck_height"):
		deck_y = float(deck.call("get_deck_height"))
	else:
		var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
		if carrier != null:
			deck_y = carrier.global_position.y
	var upper := deck_y + 2000.0
	var lower := deck_y + 1200.0
	var atmosphere := get_tree().get_first_node_in_group("day_night_cycle")
	if atmosphere != null:
		var top_value: Variant = atmosphere.get("dust_layer_top_m")
		var lower_offset: Variant = atmosphere.get("dust_deck_vertical_offset_m")
		var upper_offset: Variant = atmosphere.get("dust_deck_upper_vertical_offset_m")
		var top_m := float(top_value) if top_value is float else 2000.0
		upper = deck_y + top_m + (float(upper_offset) if upper_offset is float else 0.0)
		lower = deck_y + top_m + (float(lower_offset) if lower_offset is float else -800.0)
	return Vector2(lower, upper)

func _update_cloud(delta: float) -> void:
	var heights := _get_dust_layer_heights()
	_visuals.update_visuals(delta, heights.x, heights.y)

func _physics_process(delta: float) -> void:
	if not active:
		return
	_elapsed_s += delta
	global_position += _direction * travel_speed_mps * delta
	_update_cloud(delta)
	if _strike_age_s >= 0.0:
		_strike_age_s += delta
		if _strike_age_s >= STRIKE_TOTAL_S:
			_end_strike()
		else:
			var strength := 1.0 if _strike_age_s <= STRIKE_HOLD_S else \
				1.0 - (_strike_age_s - STRIKE_HOLD_S) / STRIKE_FADE_S
			_set_strike_strength(strength)
	if _elapsed_s >= duration_s:
		active = false
		queue_free()
		return
	if _elapsed_s >= _next_strike_s:
		_strike()
		_next_strike_s = _elapsed_s + _rng.randf_range(7.0, 18.0)

func _strike() -> void:
	_clear_bolt()
	var angle := _rng.randf_range(0.0, TAU)
	var point := global_position + global_basis * get_cell_offset(angle, sqrt(_rng.randf()) * 0.82)
	var terrain := get_tree().get_first_node_in_group("terrain_provider")
	if terrain != null and terrain.has_method("get_height"):
		var value: Variant = terrain.call("get_height", point)
		if value is float and is_finite(value):
			point.y = value
	var cloud_bottom: float = _get_dust_layer_heights().x - 65.0
	var top := Vector3(point.x + _rng.randf_range(-140.0, 140.0),
		maxf(cloud_bottom, point.y + 300.0),
		point.z + _rng.randf_range(-140.0, 140.0))
	_last_strike_origin = top
	_last_strike_impact = point
	var previous := top
	var sheath := StandardMaterial3D.new()
	sheath.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sheath.disable_fog = true
	sheath.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sheath.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sheath.albedo_color = Color(0.70, 0.88, 1.0, 0.24)
	sheath.emission_enabled = true
	sheath.emission = ICY_BLUE
	sheath.emission_energy_multiplier = 6.0
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.disable_fog = true
	core.albedo_color = BOLT_WHITE
	core.emission_enabled = true
	core.emission = BOLT_WHITE
	core.emission_energy_multiplier = 16.0
	for i in 8:
		var next := top.lerp(point, float(i + 1) / 8.0)
		if i < 7:
			next += Vector3(_rng.randf_range(-65.0, 65.0), 0.0, _rng.randf_range(-65.0, 65.0))
		_add_segment(previous, next, 11.0, sheath)
		_add_segment(previous, next, 4.0, core)
		if i == 3 or i == 5:
			var branch := next + Vector3(_rng.randf_range(-125.0, 125.0), -90.0,
				_rng.randf_range(-125.0, 125.0))
			_add_segment(next, branch, 6.0, sheath)
			_add_segment(next, branch, 2.0, core)
		previous = next
	_flash.global_position = point + Vector3.UP * 150.0
	_sky_flash.global_position = top.lerp(point, 0.16)
	_impact_halo.global_position = point + Vector3.UP * 140.0
	_sky_halo.global_position = _sky_flash.global_position
	_flash.visible = true
	_sky_flash.visible = true
	_impact_halo.visible = true
	_sky_halo.visible = true
	_strike_age_s = 0.0
	_set_strike_strength(1.0)
	_damage_near_strike(point)

func _set_strike_strength(strength: float) -> void:
	var visible_strength := clampf(strength, 0.0, 1.0)
	_flash.light_energy = 14.0 * visible_strength
	_sky_flash.light_energy = 9.0 * visible_strength
	_impact_halo.modulate.a = 0.65 * visible_strength
	_sky_halo.modulate.a = 0.45 * visible_strength
	for segment in _bolt_root.get_children():
		(segment as GeometryInstance3D).transparency = 1.0 - visible_strength

func _add_segment(start: Vector3, finish: Vector3, radius: float, material: Material) -> void:
	var delta := finish - start
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = delta.length()
	mesh.radial_segments = 4
	mesh.material = material
	var segment := MeshInstance3D.new()
	segment.mesh = mesh
	segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt_root.add_child(segment)
	segment.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, delta.normalized())), (start + finish) * 0.5)

func _damage_near_strike(point: Vector3) -> void:
	for candidate in get_tree().get_nodes_in_group("aircraft"):
		if not is_instance_valid(candidate) or not candidate is RigidBody3D:
			continue
		if candidate.global_position.distance_to(point) > 45.0:
			continue
		if candidate.has_method("take_damage") and candidate.get("max_health") != null:
			candidate.take_damage(float(candidate.get("max_health")) * 0.12)

func _clear_bolt() -> void:
	for segment in _bolt_root.get_children():
		segment.queue_free()

func _end_strike() -> void:
	_strike_age_s = -1.0
	_flash.visible = false
	_sky_flash.visible = false
	_impact_halo.visible = false
	_sky_halo.visible = false
	_clear_bolt()
