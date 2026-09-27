extends Node3D
## Root-level weather source: FloatingOrigin moves this frame exactly once.
@export var enabled := true
@export var height_m := 1100.0
@export var influence_radius_m := 550.0
@export var peak_wind_mps := 60.0
@export var updraft_mps := 30.0
@export var travel_speed_mps := 8.0
@export var lifetime_s := 480.0
var elapsed_s := 0.0
var strength := 0.0
var initialized := false
var _direction := Vector3.RIGHT
var _terrain: Node3D
var _damage_timer := 0.0

func _ready() -> void:
	add_to_group("twister")
	process_physics_priority = -110
	var visuals := preload("res://Weather/TwisterVisuals.gd").new()
	add_child(visuals)
	visuals.setup(self)

func start_at(center: Vector3, direction: Vector3) -> void:
	global_transform = Transform3D(Basis.IDENTITY, center)
	_direction = Vector3(direction.x, 0, direction.z).normalized()
	if _direction.is_zero_approx():
		_direction = Vector3.RIGHT
	_terrain = get_tree().get_first_node_in_group("terrain_provider") as Node3D
	global_position.y = ground_height(global_position)
	elapsed_s = 0.0
	strength = 0.0
	_damage_timer = 0.0
	initialized = true

func ground_height(point: Vector3) -> float:
	if is_instance_valid(_terrain) and _terrain.has_method("get_height"):
		var value: Variant = _terrain.get_height(point)
		if value is float and is_finite(value):
			return value
	return global_position.y

func _physics_process(delta: float) -> void:
	if not initialized or not enabled:
		strength = 0.0
		return
	elapsed_s += delta
	strength = smoothstep(0.0, 15.0, elapsed_s) * (1.0 - smoothstep(lifetime_s - 30.0, lifetime_s, elapsed_s))
	if elapsed_s >= lifetime_s:
		enabled = false
		return
	global_position += get_travel_velocity() * delta
	global_position.y = ground_height(global_position)
	_damage_timer += delta
	if _damage_timer >= 0.5:
		_apply_debris_damage(_damage_timer)
		_damage_timer = 0.0

func get_travel_velocity() -> Vector3:
	# Gentle wandering; the map projects the current heading, not a guaranteed route.
	return _direction.rotated(Vector3.UP, sin(elapsed_s * 0.018) * 0.25) * travel_speed_mps

func get_axis_offset(height_fraction: float) -> Vector3:
	var h := clampf(height_fraction, 0.0, 1.0)
	return Vector3(sin(h * 3.0 + elapsed_s * 0.13) * 95.0 * h,
		0.0, cos(h * 4.0 - elapsed_s * 0.11) * 65.0 * h)

func get_funnel_radius(height_fraction: float) -> float:
	var h := clampf(height_fraction, 0.0, 1.0)
	return 48.0 + 210.0 * h * h + 70.0 * exp(-h * 32.0)

func _sample_frame(point: Vector3) -> Vector3:
	var p := point - global_position
	return p - get_axis_offset(p.y / maxf(height_m, 1.0))

func get_intensity_at(point: Vector3) -> float:
	if not enabled or not initialized:
		return 0.0
	var p := _sample_frame(point)
	var horizontal := Vector2(p.x, p.z).length()
	return strength * (1.0 - smoothstep(influence_radius_m * 0.3, influence_radius_m, horizontal)) \
		* smoothstep(-30.0, 0.0, p.y) * (1.0 - smoothstep(height_m * 0.8, height_m, p.y))

func get_core_intensity_at(point: Vector3) -> float:
	var p := _sample_frame(point)
	var radius := get_funnel_radius(p.y / maxf(height_m, 1.0))
	return get_intensity_at(point) * (1.0 - smoothstep(radius * 0.6, radius * 1.8, Vector2(p.x, p.z).length()))

func get_wind_at(point: Vector3) -> Vector3:
	var intensity := get_intensity_at(point)
	if intensity <= 0.0:
		return Vector3.ZERO
	var p := _sample_frame(point)
	var radial := Vector3(p.x, 0.0, p.z)
	var radius := maxf(get_funnel_radius(p.y / maxf(height_m, 1.0)), 1.0)
	var r := radial.length() / radius
	var outward := radial.normalized()
	# Finite, continuous at the axis; no singular inverse-radius forces.
	var swirl := 2.0 * r / (1.0 + r * r)
	var tangent := Vector3(-outward.z, 0.0, outward.x)
	var core := exp(-r * r * 0.5)
	var eddy := Vector3(sin(p.z / 25.0 + elapsed_s * 2.0), sin(p.x / 31.0 - elapsed_s * 1.7),
		sin(p.x / 27.0 + elapsed_s * 1.8)) * (7.0 * core)
	return (tangent * peak_wind_mps * swirl - outward * 12.0 * swirl + Vector3.UP * updraft_mps * core + eddy) * intensity

func _apply_debris_damage(delta: float) -> void:
	var candidates := get_tree().get_nodes_in_group("aircraft")
	for ai in get_tree().get_nodes_in_group("ai_aircraft"):
		if not candidates.has(ai):
			candidates.append(ai)
	for candidate in candidates:
		if not is_instance_valid(candidate) or not candidate is RigidBody3D:
			continue
		var aircraft := candidate as RigidBody3D
		if not aircraft.can_process() or aircraft.is_queued_for_deletion():
			continue
		var core := get_core_intensity_at(aircraft.global_position)
		var low := 1.0 - smoothstep(height_m * 0.35, height_m * 0.8, aircraft.global_position.y - global_position.y)
		var fraction := 0.06 * core * core * low * delta
		if fraction <= 0.0:
			continue
		var pos := aircraft.global_position
		var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 2.0, pos + Vector3.UP * 60.0)
		query.exclude = [aircraft.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		var parts := aircraft.get_node_or_null("PartDamageModel")
		if parts != null and parts.has_method("damage_zone") and parts.has_method("get_zone_max_health"):
			parts.damage_zone(&"fuselage", parts.get_zone_max_health(&"fuselage") * fraction)
		elif aircraft.has_method("take_damage") and aircraft.get("max_health") != null:
			aircraft.take_damage(float(aircraft.get("max_health")) * fraction)

func get_footprint(scale_factor: float = 1.0, future_s: float = 0.0) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in 65:
		var angle := TAU * float(i) / 64.0
		# Include the leaning upper column in the conservative map warning ring.
		points.append(global_position + Vector3(cos(angle), 0, sin(angle)) * (influence_radius_m + 100.0) * scale_factor + get_travel_velocity() * future_s)
	return points
