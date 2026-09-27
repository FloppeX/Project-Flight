extends Node3D
## One local dust front. Sampling, map geometry and visuals share this moving frame.
## Root-level placement lets FloatingOrigin translate the entire front exactly once.

const VISUALS = preload("res://Weather/DustFrontVisuals.gd")
@export var automatic_start := false
@export var enabled := true
@export_range(1, 5, 1) var severity: int = 2
@export var half_width_m := 8000.0
@export var half_depth_m := 2600.0
@export var height_m := 1900.0
@export var travel_speed_mps := 14.0
@export var approach_distance_m := 6500.0
@export var extra_wind_mps := 8.0
@export var gust_mps := 3.0
@export var turbulence_mps := 2.2
@export var extinction_per_m := 3.912 / 450.0
@export var lifetime_s := 1800.0
var elapsed_s := 0.0
var initialized := false
var strength := 0.0
var _start_poll := 0.0
var _visuals: Node3D
var _damage_elapsed := 0.0

const CORE_VISIBILITY_M: Array[float] = [900.0, 450.0, 220.0, 90.0, 30.0]
const WIND_MULTIPLIER: Array[float] = [0.5, 1.0, 1.8, 3.0, 5.0]
const TURBULENCE_MULTIPLIER: Array[float] = [0.4, 1.0, 2.0, 4.0, 7.0]
const DAMAGE_FRACTION_PER_S: Array[float] = [0.0, 0.0, 0.0, 0.003, 0.05]

func get_severity() -> int:
	return clampi(severity, 1, 5)

func get_extinction() -> float:
	return extinction_per_m * 450.0 / CORE_VISIBILITY_M[get_severity() - 1]

func get_damage_fraction_per_second(world_position: Vector3, airspeed_mps: float) -> float:
	var exposure := get_intensity_at(world_position)
	return DAMAGE_FRACTION_PER_S[get_severity() - 1] * exposure * exposure \
		* clampf(airspeed_mps / 100.0, 0.45, 2.0)

func _ready() -> void:
	add_to_group("dust_front")
	process_physics_priority = -110
	_visuals = VISUALS.new()
	add_child(_visuals)
	_visuals.setup(self)

func start_at(center: Vector3, travel_direction: Vector3) -> void:
	var forward := Vector3(travel_direction.x, 0.0, travel_direction.z).normalized()
	if forward.length_squared() < 0.1:
		forward = Vector3.BACK
	global_transform = Transform3D(Basis(Vector3.UP.cross(forward), Vector3.UP, forward), center)
	elapsed_s = 0.0
	strength = 0.0
	initialized = true
	_damage_elapsed = 0.0

func _physics_process(delta: float) -> void:
	if not enabled:
		strength = 0.0
		return
	if not initialized:
		_start_poll -= delta
		if automatic_start and _start_poll <= 0.0:
			_start_poll = 1.0
			_try_start()
		return
	elapsed_s += delta
	strength = smoothstep(0.0, 45.0, elapsed_s) * (1.0 - smoothstep(lifetime_s - 180.0, lifetime_s, elapsed_s))
	global_position += get_travel_velocity() * delta
	_damage_elapsed += delta
	if _damage_elapsed >= 0.5:
		_apply_exposure_damage(_damage_elapsed)
		_damage_elapsed = 0.0

func _apply_exposure_damage(delta: float) -> void:
	if get_severity() < 4:
		return
	var wind_field := get_tree().get_first_node_in_group("atmospheric_wind")
	for candidate in get_tree().get_nodes_in_group("aircraft"):
		if not is_instance_valid(candidate) or not candidate is RigidBody3D:
			continue
		var aircraft := candidate as RigidBody3D
		if not aircraft.can_process() or aircraft.is_queued_for_deletion():
			continue
		var air_velocity := get_wind_at(aircraft.global_position)
		if wind_field != null:
			air_velocity = wind_field.get_velocity_at(aircraft.global_position)
		var speed := (aircraft.linear_velocity - air_velocity).length()
		var fraction := get_damage_fraction_per_second(aircraft.global_position, speed) * delta
		if fraction <= 0.0 or _has_overhead_shelter(aircraft):
			continue
		# Abrasion is environmental exposure, not a projectile or collision hit.
		var parts := aircraft.get_node_or_null("PartDamageModel")
		if parts != null and parts.has_method("damage_zone") and parts.has_method("get_zone_max_health"):
			parts.damage_zone(&"fuselage", parts.get_zone_max_health(&"fuselage") * fraction)
		elif aircraft.has_method("take_damage") and aircraft.get("max_health") != null:
			aircraft.take_damage(float(aircraft.get("max_health")) * fraction)

func _has_overhead_shelter(aircraft: RigidBody3D) -> bool:
	# Protect aircraft under carrier decks/roofs, including visible hangar models.
	var origin := aircraft.global_position
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 2.0, origin + Vector3.UP * 60.0)
	query.exclude = [aircraft.get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _try_start() -> void:
	# Wait for scenario terrain/carrier placement, including continued campaigns.
	if not TerrainNavGrid.is_ready() or GameSession.has_pending_save_state():
		return
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return
	if carrier.has_method("is_initial_placement_complete") and not carrier.is_initial_placement_complete():
		return
	var wind := get_tree().get_first_node_in_group("atmospheric_wind")
	var direction := Vector3(1.0, 0.0, 0.35)
	if wind != null:
		direction = wind.get("prevailing_velocity_mps")
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = Vector3.BACK
	direction = direction.normalized()
	var center := carrier.global_position - direction * (approach_distance_m + half_depth_m)
	center.y = carrier.global_position.y - 550.0
	start_at(center, direction)

func get_travel_velocity() -> Vector3:
	return global_basis.z * travel_speed_mps

func get_intensity_at(world_position: Vector3) -> float:
	if not enabled or not initialized:
		return 0.0
	var p := to_local(world_position)
	var x := p.x / maxf(half_width_m, 1.0)
	var z := p.z / maxf(half_depth_m, 1.0)
	var lobe := 1.0 + 0.035 * sin(atan2(z, x) * 5.0)
	var radial := Vector2(x, z).length() / lobe
	var top := get_top_scale(p.x, p.z)
	var y := maxf(p.y, 0.0) / maxf(height_m * top, 1.0)
	var envelope := sqrt(radial * radial + pow(y, 8.0))
	return strength * (1.0 - smoothstep(0.82, 1.0, envelope)) * smoothstep(-180.0, 0.0, p.y)

func get_top_scale(x: float, z: float) -> float:
	return 0.86 + 0.09 * sin(x / 280.0 + elapsed_s * 0.045) + 0.045 * sin(z / 350.0 - x / 1050.0 + elapsed_s * 0.03) + 0.035 * sin(x / 93.0 + z / 137.0 + elapsed_s * 0.08)

func get_wind_at(world_position: Vector3) -> Vector3:
	var intensity := get_intensity_at(world_position)
	if intensity <= 0.0:
		return Vector3.ZERO
	var p := to_local(world_position)
	var t := elapsed_s
	var level := get_severity() - 1
	var gust := sin(p.z / 260.0 - t * 0.55) * gust_mps * WIND_MULTIPLIER[level]
	var eddy := Vector3(sin(p.z / 41.0 + p.y / 53.0 + t * 1.2),
		sin(p.x / 47.0 - p.z / 61.0 + t * 1.4) * 0.65,
		sin(p.x / 59.0 + p.y / 43.0 - t * 1.1)) * turbulence_mps * TURBULENCE_MULTIPLIER[level]
	return global_basis * (Vector3(0.0, 0.0, extra_wind_mps * WIND_MULTIPLIER[level] + gust) + eddy) * intensity

func get_visibility_m(world_position: Vector3) -> float:
	# Meteorological contrast distance from the added dust's extinction.
	return minf(10000.0, 3.912 / maxf(get_extinction() * get_intensity_at(world_position), 0.00001))

func get_footprint(scale_factor: float = 1.0, future_s: float = 0.0) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in 65:
		var angle := TAU * float(i) / 64.0
		var radius := scale_factor * (1.0 + 0.035 * sin(angle * 5.0))
		points.append(to_global(Vector3(cos(angle) * half_width_m * radius, height_m * 0.2,
			sin(angle) * half_depth_m * radius)) + get_travel_velocity() * future_s)
	return points

func get_arrival_seconds(world_position: Vector3) -> float:
	var p := to_local(world_position)
	var x := absf(p.x) / maxf(half_width_m, 1.0)
	if x >= 0.95 or travel_speed_mps <= 0.0:
		return -1.0
	var leading_edge := half_depth_m * sqrt(1.0 - x * x)
	if p.z < -leading_edge:
		return -1.0
	return maxf((p.z - leading_edge) / travel_speed_mps, 0.0)
