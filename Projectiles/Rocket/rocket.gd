extends ProjectileNew
class_name RocketProjectile

signal tuning_impact(position: Vector3)
signal tuning_impact_detail(position: Vector3, body: Node)

const DEFAULT_ROCKET_LOOP: AudioStream = preload("res://Audio/rocket.wav")

@export var tracer_enabled: bool = false
@export var damage_amount: float = 45.0
@export var explosion_blast_radius: float = 8.0
@export var explosion_max_damage: float = 70.0
@export var explosion_min_damage: float = 25.0
@export var air_explosion_blast_radius: float = 5.0
@export var air_explosion_max_damage: float = 55.0
@export var air_explosion_min_damage: float = 15.0
@export var explosion_flash_duration: float = 0.25
@export var explosion_effect_duration: float = 2.0
@export var explosion_debris_count: int = 8
@export var explosion_knockback_impulse_at_center: float = 700.0
@export var explosion_knockback_impulse_at_edge: float = 100.0
@export var motor_acceleration_mps2: float = 500.0
@export var motor_additional_speed_mps: float = 160.0
@export var flight_wobble_accel_mps2: float = 0.8
@export var flight_wobble_frequency_hz: float = 1.2
## Smooth, zero-mean lateral acceleration unique to each rocket. Unlike the
## periodic wobble, this does not cancel into the same repeatable trajectory and
## therefore produces a small natural dispersion during flight.
@export var flight_scatter_accel_mps2: float = 0.65
## How long a small thrust/fin error tends to persist before drifting elsewhere.
@export var flight_scatter_correlation_s: float = 0.65
@export var rocket_linear_damp: float = 0.06  # Drag applied to the rocket. Exported so the CCIP predictor can read it BEFORE _ready() runs -- otherwise CCIP saw linear_damp=0 (drag-free) and over-predicted range by ~400m, which no aiming fix could correct.
@export var smoke_interval: float = 0.05
@export var rocket_loop_sound: AudioStream = DEFAULT_ROCKET_LOOP

var smoke_timer: float = 0.0
var _launch_reference_speed_mps: float = 0.0
var _flight_age_s: float = 0.0
var _wobble_phase: float = 0.0
var _wobble_mix: float = 1.0
var _scatter_accel_local: Vector2 = Vector2.ZERO
var _scatter_target_local: Vector2 = Vector2.ZERO
var _scatter_target_timer_s: float = 0.0
var _rocket_audio_player: AudioStreamPlayer3D = null
var _tuning_impact_emitted: bool = false

func _ready() -> void:
	var configured_mass: float = mass
	super._ready()
	mass = configured_mass
	damage = damage_amount
	creates_explosion = false
	continuous_cd = true
	can_sleep = false
	sleeping = false
	# Rockets have slight drag — they're slower than bullets and decelerate gently.
	linear_damp = rocket_linear_damp
	angular_damp = 2.0
	_wobble_phase = randf() * TAU
	_wobble_mix = randf_range(0.7, 1.3)
	_scatter_target_local = _sample_flight_scatter_acceleration()
	_scatter_accel_local = _scatter_target_local
	_scatter_target_timer_s = maxf(flight_scatter_correlation_s, 0.01)
	_setup_rocket_audio()

func _exit_tree() -> void:
	_emit_tuning_impact(global_position)
	if is_instance_valid(_rocket_audio_player):
		_rocket_audio_player.stop()


func _emit_tuning_impact(position: Vector3, body: Node = null) -> void:
	if _tuning_impact_emitted:
		return
	_tuning_impact_emitted = true
	tuning_impact.emit(position)
	tuning_impact_detail.emit(position, body)

func _setup_rocket_audio() -> void:
	if rocket_loop_sound == null:
		return
	if rocket_loop_sound is AudioStreamWAV:
		(rocket_loop_sound as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_rocket_audio_player = AudioStreamPlayer3D.new()
	_rocket_audio_player.stream = rocket_loop_sound
	_rocket_audio_player.volume_db = -3.0
	_rocket_audio_player.unit_size = 35.0
	_rocket_audio_player.max_distance = 1800.0
	_rocket_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_rocket_audio_player.add_to_group("3d_audio")
	add_child(_rocket_audio_player)

func fire(initial_velocity: Vector3, firing_aircraft: Node3D) -> void:
	super.fire(initial_velocity, firing_aircraft)
	if not firing_aircraft or not is_instance_valid(firing_aircraft):
		_launch_reference_speed_mps = linear_velocity.length()
		return

	linear_velocity += _get_motion_velocity(firing_aircraft)

	var platform_angular_velocity: Vector3 = _get_motion_angular_velocity(firing_aircraft)
	if platform_angular_velocity.length_squared() > 0.000001 and firing_aircraft is Node3D:
		var r_offset: Vector3 = global_position - (firing_aircraft as Node3D).global_position
		linear_velocity += platform_angular_velocity.cross(r_offset)
	_launch_reference_speed_mps = linear_velocity.length()
	_flight_age_s = 0.0
	if is_instance_valid(_rocket_audio_player) and not _rocket_audio_player.playing:
		_rocket_audio_player.play()

func _physics_process(delta: float) -> void:
	if has_impacted:
		return
	_flight_age_s += delta
	_apply_motor_acceleration(delta)
	_apply_flight_wobble(delta)
	_apply_flight_scatter(delta)
	if linear_velocity.length() > 0.1:
		look_at(global_position + linear_velocity, Vector3.UP)
	super._physics_process(delta)
	if has_impacted or is_queued_for_deletion():
		return
	_update_smoke_trail(delta)

func _apply_motor_acceleration(delta: float) -> void:
	var target_speed_mps: float = _launch_reference_speed_mps + maxf(motor_additional_speed_mps, 0.0)
	if target_speed_mps <= 0.0 or motor_acceleration_mps2 <= 0.0:
		return

	var current_speed_mps: float = linear_velocity.length()
	if current_speed_mps >= target_speed_mps:
		return

	var forward_dir: Vector3 = linear_velocity.normalized()
	if forward_dir.length_squared() < 0.001:
		forward_dir = global_transform.basis.z.normalized()
	if forward_dir.length_squared() < 0.001:
		forward_dir = Vector3.FORWARD

	var speed_step_mps: float = minf(motor_acceleration_mps2 * delta, target_speed_mps - current_speed_mps)
	linear_velocity += forward_dir * speed_step_mps

func _apply_flight_wobble(delta: float) -> void:
	if flight_wobble_accel_mps2 <= 0.0 or flight_wobble_frequency_hz <= 0.0:
		return

	var forward_dir: Vector3 = linear_velocity.normalized()
	if forward_dir.length_squared() < 0.001:
		forward_dir = global_transform.basis.z.normalized()
	if forward_dir.length_squared() < 0.001:
		return

	var right_dir: Vector3 = forward_dir.cross(Vector3.UP)
	if right_dir.length_squared() < 0.001:
		right_dir = forward_dir.cross(Vector3.RIGHT)
	if right_dir.length_squared() < 0.001:
		return
	right_dir = right_dir.normalized()
	var up_dir: Vector3 = right_dir.cross(forward_dir).normalized()

	var wobble_angle: float = _wobble_phase + _flight_age_s * TAU * flight_wobble_frequency_hz
	var wobble_axis: Vector3 = right_dir * sin(wobble_angle) + up_dir * cos(wobble_angle * _wobble_mix)
	linear_velocity += wobble_axis * flight_wobble_accel_mps2 * delta

func _apply_flight_scatter(delta: float) -> void:
	if flight_scatter_accel_mps2 <= 0.0:
		return

	var forward_dir: Vector3 = linear_velocity.normalized()
	if forward_dir.length_squared() < 0.001:
		forward_dir = global_transform.basis.z.normalized()
	if forward_dir.length_squared() < 0.001:
		return

	_scatter_target_timer_s -= delta
	var correlation_s: float = maxf(flight_scatter_correlation_s, 0.01)
	if _scatter_target_timer_s <= 0.0:
		_scatter_target_local = _sample_flight_scatter_acceleration()
		_scatter_target_timer_s += correlation_s

	# Exponential response keeps the perturbation continuous when a new random
	# target is sampled. The correlation time controls both sampling and smoothing,
	# so changing it does not introduce a second hidden tuning constant.
	var scatter_response: float = 1.0 - exp(-delta / correlation_s)
	_scatter_accel_local = _scatter_accel_local.lerp(_scatter_target_local, scatter_response)

	var right_dir: Vector3 = forward_dir.cross(Vector3.UP)
	if right_dir.length_squared() < 0.001:
		right_dir = forward_dir.cross(Vector3.RIGHT)
	if right_dir.length_squared() < 0.001:
		return
	right_dir = right_dir.normalized()
	var up_dir: Vector3 = right_dir.cross(forward_dir).normalized()
	linear_velocity += (
		right_dir * _scatter_accel_local.x
		+ up_dir * _scatter_accel_local.y
	) * delta

func _sample_flight_scatter_acceleration() -> Vector2:
	if flight_scatter_accel_mps2 <= 0.0:
		return Vector2.ZERO
	# sqrt gives uniform area density inside the acceleration disk, avoiding a
	# preference for either the centre or the maximum configured deviation.
	var angle: float = randf() * TAU
	var magnitude: float = sqrt(randf()) * flight_scatter_accel_mps2
	return Vector2(cos(angle), sin(angle)) * magnitude

func _update_smoke_trail(delta: float) -> void:
	smoke_timer += delta
	if smoke_timer >= smoke_interval:
		_emit_smoke_particle()
		smoke_timer = 0.0

func _emit_smoke_particle() -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return

	var smoke_mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.0, 1.0, 1.0)
	smoke_mesh.mesh = box_mesh
	smoke_mesh.name = "RocketSmoke_" + str(Time.get_ticks_msec())
	get_tree().current_scene.add_child(smoke_mesh)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.flags_unshaded = true
	smoke_mesh.material_override = material

	var rear_offset := global_transform.basis.z * -3.0
	smoke_mesh.global_position = global_position + rear_offset
	smoke_mesh.rotation = Vector3(
		randf() * TAU,
		randf() * TAU,
		randf() * TAU
	)

	ParticleManager.add_smoke_particle(smoke_mesh, 1.5, Vector3(1.0, 1.0, 1.0))

func _on_body_entered(body: Node) -> void:
	if has_impacted:
		return
	if is_shooter_body(body):
		return
	if is_instance_valid(_rocket_audio_player):
		_rocket_audio_player.stop()

	var damage_target: Node = find_damage_target(body)
	var hit_ground: bool = is_ground_or_terrain(body)
	var hit_aircraft: bool = _is_aircraft_target(damage_target) or _is_aircraft_target(body)
	has_impacted = true
	_emit_tuning_impact(global_position, body)

	_spawn_custom_explosion(hit_ground, hit_aircraft)
	play_impact_sound(body)

	if damage_target and damage_target.has_method("take_damage"):
		_report_damage_credit(damage_target, damage)
		damage_target.take_damage(damage)
	queue_free()

func _spawn_custom_explosion(hit_ground: bool, hit_aircraft: bool) -> void:
	if explosion_scene == null:
		return
	var explosion := explosion_scene.instantiate()
	if not (explosion is Explosion):
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = global_position
		return

	var explosion_node := explosion as Explosion
	get_tree().current_scene.add_child(explosion_node)
	explosion_node.global_position = global_position
	explosion_node.blast_radius = air_explosion_blast_radius if hit_aircraft else explosion_blast_radius
	explosion_node.max_damage = air_explosion_max_damage if hit_aircraft else explosion_max_damage
	explosion_node.min_damage = air_explosion_min_damage if hit_aircraft else explosion_min_damage
	explosion_node.flash_duration = explosion_flash_duration
	explosion_node.effect_duration = explosion_effect_duration
	explosion_node.debris_count = explosion_debris_count
	explosion_node.knockback_impulse_at_center = explosion_knockback_impulse_at_center
	explosion_node.knockback_impulse_at_edge = explosion_knockback_impulse_at_edge
	explosion_node.use_line_of_sight = false
	if is_instance_valid(shooter):
		explosion_node.source_attacker = shooter
	if hit_ground:
		explosion_node.create_scorch_mark()

func _get_motion_velocity(node: Node) -> Vector3:
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	var linear_variant: Variant = node.get("linear_velocity")
	if linear_variant is Vector3:
		return linear_variant
	var velocity_variant: Variant = node.get("velocity")
	if velocity_variant is Vector3:
		return velocity_variant
	if node.has_method("get_linear_velocity"):
		var getter_velocity_variant: Variant = node.call("get_linear_velocity")
		if getter_velocity_variant is Vector3:
			return getter_velocity_variant
	return Vector3.ZERO

func _get_motion_angular_velocity(node: Node) -> Vector3:
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	var angular_variant: Variant = node.get("angular_velocity")
	if angular_variant is Vector3:
		return angular_variant
	if node.has_method("get_angular_velocity"):
		var getter_angular_variant: Variant = node.call("get_angular_velocity")
		if getter_angular_variant is Vector3:
			return getter_angular_variant
	return Vector3.ZERO

func _is_aircraft_target(node: Object) -> bool:
	return node is Node and ((node as Node).is_in_group("aircraft") or (node as Node).is_in_group("ai_aircraft"))
