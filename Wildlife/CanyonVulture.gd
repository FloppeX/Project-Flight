extends CharacterBody3D
class_name CanyonVulture

signal killed(bird: Node3D, attacker: Node)

@export var max_health := 10.0
@export var glide_speed_mps := 16.0
@export var orbit_radius_m := 180.0
@export var orbit_direction := 1.0
@export var lifetime_s := 240.0
@export var flap_interval_min_s := 7.0
@export var flap_interval_max_s := 15.0

var orbit_center := Vector3.ZERO
var health := 10.0
var _orbit_angle := 0.0
var _age_s := 0.0
var _dead := false
var _death_elapsed_s := 0.0
var _last_attacker: Node = null
var _left_wing: Node3D
var _right_wing: Node3D
var _flap_elapsed_s := 0.0
var _flap_duration_s := 0.0
var _flap_strokes := 0
var _next_flap_s := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("wildlife")
	add_to_group("origin_shifter")
	health = max_health
	_left_wing = find_child("wing left", true, false) as Node3D
	_right_wing = find_child("wing right", true, false) as Node3D
	_rng.seed = get_instance_id() * 7919 + Time.get_ticks_msec()
	_schedule_next_flap()
	_update_wings(0.0)


func configure_soaring(center: Vector3, radius_m: float, start_angle: float, direction: float) -> void:
	orbit_center = center
	orbit_radius_m = maxf(radius_m, 30.0)
	_orbit_angle = start_angle
	orbit_direction = -1.0 if direction < 0.0 else 1.0
	_update_soaring_transform()


func _physics_process(delta: float) -> void:
	if _dead:
		_update_fall(delta)
		return
	_age_s += delta
	if _age_s >= lifetime_s:
		queue_free()
		return
	var angular_speed := glide_speed_mps / maxf(orbit_radius_m, 1.0)
	_orbit_angle = fposmod(_orbit_angle + angular_speed * orbit_direction * delta, TAU)
	_update_soaring_transform()
	_update_wings(delta)


func _update_soaring_transform() -> void:
	var radial := Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle))
	global_position = orbit_center + radial * orbit_radius_m
	global_position.y += sin(_orbit_angle * 2.0) * 5.0
	var forward := Vector3(-radial.z * orbit_direction, 0.025, radial.x * orbit_direction).normalized()
	look_at(global_position + forward, Vector3.UP, true)
	rotation.z = deg_to_rad(-10.0 * orbit_direction)


func _update_wings(delta: float) -> void:
	if not is_instance_valid(_left_wing) or not is_instance_valid(_right_wing):
		return
	var flap_degrees := 0.0
	if _flap_duration_s > 0.0:
		_flap_elapsed_s += delta
		var progress := clampf(_flap_elapsed_s / _flap_duration_s, 0.0, 1.0)
		flap_degrees = sin(progress * PI * 2.0 * float(_flap_strokes)) * 22.0
		if progress >= 1.0:
			_flap_duration_s = 0.0
			_flap_elapsed_s = 0.0
			_schedule_next_flap()
	else:
		_next_flap_s -= delta
		if _next_flap_s <= 0.0:
			_start_flap_burst(_rng.randi_range(2, 4))
	var dihedral_degrees := 4.0
	_left_wing.rotation_degrees.z = dihedral_degrees + flap_degrees
	_right_wing.rotation_degrees.z = -dihedral_degrees - flap_degrees


func _start_flap_burst(strokes: int) -> void:
	_flap_strokes = maxi(strokes, 1)
	_flap_duration_s = float(_flap_strokes) * 0.72
	_flap_elapsed_s = 0.0


func _schedule_next_flap() -> void:
	_next_flap_s = _rng.randf_range(flap_interval_min_s, flap_interval_max_s)


func take_damage(amount: float) -> void:
	take_damage_from(amount, null)


func take_damage_from(amount: float, attacker: Node) -> void:
	if _dead or amount <= 0.0:
		return
	if is_instance_valid(attacker):
		_last_attacker = attacker
	health -= amount
	if health <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	velocity = Vector3(0.0, -4.0, 0.0)
	if is_instance_valid(_left_wing):
		_left_wing.rotation_degrees.z = -35.0
	if is_instance_valid(_right_wing):
		_right_wing.rotation_degrees.z = 35.0
	killed.emit(self, _last_attacker)


func _update_fall(delta: float) -> void:
	_death_elapsed_s += delta
	velocity.y -= 9.8 * delta
	rotation.x += 1.2 * delta
	rotation.z += 0.7 * delta
	move_and_slide()
	if is_on_floor() or _death_elapsed_s >= 12.0:
		queue_free()


func apply_origin_shift(offset: Vector3) -> void:
	orbit_center -= offset
