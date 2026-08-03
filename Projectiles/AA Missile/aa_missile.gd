extends ProjectileNew
class_name AAMissile

@export var max_speed_mps: float = 600.0
@export var launch_speed_mps: float = 120.0
@export var thrust_force: float = 6000.0
@export var steer_torque: float = 200.0
@export var max_turn_rate_deg_per_sec: float = 240.0
@export var lateral_damping: float = 0.9
@export var lift_coefficient: float = 0.2
@export var drag_coefficient: float = 0.1
@export var turbulence_strength: float = 1.0
@export var damage_direct_hit: float = 100.0
@export var engine_on: bool = true

# Guidance system parameters
@export var high_approach_altitude: float = 100.0  # Height above target for phase 1
@export var terminal_attack_distance: float = 100.0  # Distance to switch to phase 2
@export var lead_velocity_threshold: float = 15.0  # Min target velocity for lead prediction
@export var lead_factor: float = 0.2  # How much to lead fast-moving targets
@export var guidance_velocity_blend: float = 0.125
@export var terminal_guidance_velocity_blend: float = 0.38
@export var terminal_turn_rate_boost: float = 1.35
@export var spiral_radius_m: float = 28.0
@export var spiral_frequency_hz: float = 1.55
@export var spiral_terminal_scale: float = 0.6
@export var spiral_launch_ramp_s: float = 0.45

# Explosion parameters
@export var explosion_radius: float = 10.0  # Blast radius in meters
@export var explosion_damage_splash: float = 50.0  # Damage for standard explosion splash
@export var fuel_life_seconds: float = 4.0  # Disables after 4 seconds
@export var arming_time: float = 0.5  # Time in seconds before missile can explode
@export var engine_ignition_delay: float = 0.1  # Fast start
@export var proximity_detonation_distance: float = 10.0  # Detonate if it passes within 10m of a plane
@export var proximity_target_padding_m: float = 6.0

var target: Node3D
var smoke_particles: Array = []
var smoke_timer: float = 0.0
var smoke_interval: float = 0.05  # Emit every 3 frames at 60fps
var launch_time: float = 0.0
var is_armed: bool = false
var _spiral_phase: float = 0.0
var _spiral_direction: float = 1.0
var _spiral_radius_scale: float = 1.0

# Simple particle data structure
class SmokeParticle:
	var mesh_instance: MeshInstance3D
	var life_time: float = 0.0
	var max_life: float = 0.5
	var initial_scale: Vector3 = Vector3.ONE

func _ready():
	# Setup defaults for explosion/damage
	damage = damage_direct_hit
	if explosion_scene == null:
		explosion_scene = load("res://Projectiles/Explosion/explosion.tscn")
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 32
	can_sleep = false
	sleeping = false
	# Collision mask is set in the scene file - don't override it
	# Ensure body_entered is connected (redundant but robust)
	if not is_connected("body_entered", Callable(self, "_on_body_entered")):
		body_entered.connect(_on_body_entered)
	# Keep default collision_layer unless customized

	# Add to weather_affected group for turbulence
	add_to_group("weather_affected")
	

func set_target(t: Node3D) -> void:
	target = t

func fire_with_target(initial_velocity: Vector3, firing_aircraft: Node3D, t: Node3D) -> void:
	set_target(t)
	fire(initial_velocity, firing_aircraft)

func fire(initial_velocity: Vector3, firing_aircraft: Node3D):
	# Launch with the carrier aircraft's current velocity plus a forward rail/ejection speed.
	var launch_velocity: Vector3 = initial_velocity
	var launch_dir: Vector3 = global_transform.basis.z.normalized()
	if launch_dir.length_squared() < 0.001:
		launch_dir = Vector3.FORWARD
	launch_velocity += launch_dir * maxf(launch_speed_mps, 0.0)

	# Call parent fire method
	super.fire(launch_velocity, firing_aircraft)
	# Record launch time for arming and engine ignition delays
	launch_time = Time.get_ticks_msec() / 1000.0
	is_armed = false
	engine_on = false  # Start with engine OFF - will be enabled after ignition delay
	_spiral_phase = randf() * TAU
	_spiral_direction = -1.0 if randf() < 0.5 else 1.0
	_spiral_radius_scale = randf_range(0.95, 1.6)
	print("Missile launched - engine ignites in ", engine_ignition_delay, " seconds, arms in ", arming_time, " seconds")

func _physics_process(delta):
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_launch = current_time - launch_time

	# Arming
	if not is_armed and launch_time > 0.0:
		if time_since_launch >= arming_time:
			is_armed = true

	# Engine ignition window: on between ignition_delay and fuel_life, off otherwise
	if launch_time > 0.0:
		var in_ignition_phase: bool = time_since_launch < engine_ignition_delay
		var out_of_fuel: bool = time_since_launch > fuel_life_seconds + engine_ignition_delay
		if in_ignition_phase or out_of_fuel:
			engine_on = false
			if out_of_fuel:
				target = null  # lose lock after burnout
		else:
			engine_on = true

	# Proximity detonation (armed, each physics frame)
	if is_armed and proximity_detonation_distance > 0.0:
		_check_proximity_detonation()

	# Base projectile physics (tunneling detection etc.)
	super._physics_process(delta)
	if engine_on:
		_apply_thrust_and_lift(delta)
		_apply_guidance(delta)
		_update_smoke_trail(delta)
		_apply_drag_and_limit_speed(delta)
		_apply_lateral_damping(delta)


func _apply_thrust_and_lift(delta: float) -> void:
	var fwd: Vector3 = global_transform.basis.z
	apply_central_force(fwd * thrust_force)
	# Minimal lift - only apply when missile is pitched up and moving fast
	var up: Vector3 = global_transform.basis.y
	var speed: float = linear_velocity.length()
	if speed > 20.0:  # Only apply lift at decent speed
		var pitch_factor: float = max(0.0, up.dot(Vector3.UP))  # Only when nose is up
		var lift_mag: float = lift_coefficient * speed * pitch_factor * 0.3  # Reduced lift
		apply_central_force(up * lift_mag)

func _apply_guidance(delta: float) -> void:
	if not target or not is_instance_valid(target):
		print("No valid target for missile guidance")
		return
	
	var target_velocity: Vector3 = _get_target_velocity(target)
	
	var distance_to_target: float = global_position.distance_to(target.global_position)
	var terminal_t: float = 1.0 - clampf(distance_to_target / maxf(terminal_attack_distance, 1.0), 0.0, 1.0)
	var intercept_point: Vector3 = _predict_intercept_point(target.global_position, target_velocity)
	var lead_blend: float = clampf(lead_factor, 0.0, 1.0) * (1.0 - terminal_t * 0.65)
	var attack_point: Vector3 = target.global_position.lerp(intercept_point, lead_blend)
	if distance_to_target < terminal_attack_distance:
		attack_point = attack_point.lerp(target.global_position, terminal_t)
	attack_point += _get_spiral_guidance_offset(attack_point, distance_to_target, terminal_t)

	var to_target_vec: Vector3 = attack_point - global_position
	if to_target_vec.length_squared() < 0.01:
		return
	var to_target: Vector3 = to_target_vec.normalized()
	var fwd: Vector3 = global_transform.basis.z.normalized()
	if fwd.length_squared() < 0.001:
		fwd = linear_velocity.normalized() if linear_velocity.length_squared() > 1.0 else Vector3.FORWARD
	var dot_val: float = clamp(fwd.dot(to_target), -1.0, 1.0)
	var angle_err: float = acos(dot_val)
	
	var steer_axis: Vector3 = fwd.cross(to_target)
	if steer_axis.length() > 0.0001:
		steer_axis = steer_axis.normalized()

		var max_turn_rate_rad: float = deg_to_rad(max_turn_rate_deg_per_sec) * lerpf(1.0, maxf(terminal_turn_rate_boost, 1.0), terminal_t)
		var desired_ang_vel: Vector3 = steer_axis * minf(angle_err / maxf(delta, 0.001), max_turn_rate_rad)
		var ang_vel_blend: float = clampf(lerpf(0.18, 0.55, terminal_t), 0.0, 1.0)
		angular_velocity = angular_velocity.lerp(desired_ang_vel, ang_vel_blend)

		var torque_mag: float = steer_torque * angle_err * lerpf(0.8, 1.4, terminal_t)
		apply_torque(steer_axis * torque_mag)

	var current_speed: float = maxf(linear_velocity.length(), maxf(launch_speed_mps, 1.0))
	var desired_velocity: Vector3 = to_target * current_speed
	var velocity_blend: float = lerpf(
		clampf(guidance_velocity_blend, 0.0, 1.0),
		clampf(terminal_guidance_velocity_blend, 0.0, 1.0),
		terminal_t
	)
	linear_velocity = linear_velocity.lerp(desired_velocity, clampf(velocity_blend * delta * 60.0, 0.0, 1.0))

func _on_body_entered(body):
	if body == shooter:
		return
	if not is_armed:
		has_impacted = true
		queue_free()
		return
	_trigger_explosion(body)

func _apply_drag_and_limit_speed(delta: float) -> void:
	if drag_coefficient > 0.0:
		linear_velocity /= (1.0 + drag_coefficient * delta)
	var speed: float = linear_velocity.length()
	if speed > max_speed_mps:
		linear_velocity = linear_velocity.normalized() * max_speed_mps

func _apply_lateral_damping(delta: float) -> void:
	# Reduce sideways velocity to prevent sliding past targets
	var fwd: Vector3 = global_transform.basis.z.normalized()
	var forward_velocity: float = linear_velocity.dot(fwd)
	var forward_component: Vector3 = fwd * forward_velocity
	var lateral_component: Vector3 = linear_velocity - forward_component

	# Apply damping to lateral velocity, stronger when close to target
	var damping_strength: float = lateral_damping
	if target and is_instance_valid(target):
		var distance_to_target: float = global_position.distance_to(target.global_position)
		if distance_to_target < 150.0:
			# Increase lateral damping when approaching target
			var proximity_factor: float = clamp((150.0 - distance_to_target) / 150.0, 0.0, 1.0)
			damping_strength = lerp(lateral_damping, 0.95, proximity_factor)

	# Apply the damping
	lateral_component *= (1.0 - damping_strength * delta)
	linear_velocity = forward_component + lateral_component


func _update_smoke_trail(delta: float) -> void:
	smoke_timer += delta
	
	# Emit new smoke particle
	if smoke_timer >= smoke_interval:
		_emit_smoke_particle()
		smoke_timer = fmod(smoke_timer, maxf(smoke_interval, 0.01))

func _emit_smoke_particle() -> void:
	if ParticleManager == null:
		return
	var rear_offset: Vector3 = global_transform.basis.z * -3.0
	ParticleManager.spawn_managed_smoke(
		global_position + rear_offset,
		Vector3.ONE * 2.0,
		Color(0.95, 0.95, 0.95, 0.9),
		1.5,
		0.0,
		randf_range(-0.35, 0.35),
		false,
		"box",
		0.0,
		false
	)

func _check_proximity_detonation():
	var valid_target = null
	if target and is_instance_valid(target):
		valid_target = target

	# First cheap check: distance to locked target
	if valid_target:
		var fuse_radius: float = _get_effective_proximity_radius(valid_target)
		var segment_start: Vector3 = last_position if last_position != Vector3.ZERO else global_position
		var closest_point: Vector3 = _closest_point_on_segment(valid_target.global_position, segment_start, global_position)
		var dist = closest_point.distance_to(valid_target.global_position)
		if dist <= fuse_radius:
			_trigger_explosion(valid_target)
			return

	# Sphere-overlap query so we don't skip past aircraft at high speed
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = _get_effective_proximity_radius(valid_target)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform
	query.exclude = [self]
	query.collision_mask = collision_mask
	var results := space.intersect_shape(query)
	for r in results:
		var body := r.get("collider") as Node
		if not body or body == shooter:
			continue
		var aircraft_target: Node = _resolve_aircraft_target(body)
		if aircraft_target:
			_trigger_explosion(aircraft_target)
			return

func _get_target_velocity(node: Node3D) -> Vector3:
	if not node or not is_instance_valid(node):
		return Vector3.ZERO
	if node.has_method("get_linear_velocity"):
		return node.get_linear_velocity()
	if "linear_velocity" in node:
		return node.linear_velocity
	return Vector3.ZERO

func _predict_intercept_point(target_pos: Vector3, target_velocity: Vector3) -> Vector3:
	var rel_pos: Vector3 = target_pos - global_position
	var accel_speed_gain: float = 0.0
	if mass > 0.0:
		accel_speed_gain = thrust_force / mass * 0.35
	var missile_speed: float = clampf(
		maxf(linear_velocity.length(), launch_speed_mps) + accel_speed_gain,
		50.0,
		maxf(max_speed_mps, 50.0)
	)
	var rel_vel: Vector3 = target_velocity - linear_velocity
	var a: float = rel_vel.dot(rel_vel) - missile_speed * missile_speed
	var b: float = 2.0 * rel_pos.dot(rel_vel)
	var c: float = rel_pos.dot(rel_pos)
	var t: float = 0.0

	if absf(a) < 0.001:
		if absf(b) > 0.001:
			t = maxf(-c / b, 0.0)
	else:
		var disc: float = b * b - 4.0 * a * c
		if disc >= 0.0:
			var sqrt_disc: float = sqrt(disc)
			var t1: float = (-b - sqrt_disc) / (2.0 * a)
			var t2: float = (-b + sqrt_disc) / (2.0 * a)
			var best_t: float = INF
			if t1 > 0.0:
				best_t = minf(best_t, t1)
			if t2 > 0.0:
				best_t = minf(best_t, t2)
			if best_t < INF:
				t = best_t

	if t <= 0.0:
		t = rel_pos.length() / missile_speed
	return target_pos + target_velocity * clampf(t, 0.0, 4.0)

func _get_spiral_guidance_offset(attack_point: Vector3, distance_to_target: float, terminal_t: float) -> Vector3:
	if spiral_radius_m <= 0.0 or spiral_frequency_hz <= 0.0:
		return Vector3.ZERO

	var attack_dir: Vector3 = (attack_point - global_position).normalized()
	if attack_dir.length_squared() < 0.001:
		return Vector3.ZERO

	var spiral_right: Vector3 = attack_dir.cross(Vector3.UP)
	if spiral_right.length_squared() < 0.001:
		spiral_right = attack_dir.cross(Vector3.RIGHT)
	if spiral_right.length_squared() < 0.001:
		return Vector3.ZERO
	spiral_right = spiral_right.normalized()
	var spiral_up: Vector3 = spiral_right.cross(attack_dir).normalized()

	var current_time: float = Time.get_ticks_msec() / 1000.0
	var time_since_launch: float = maxf(current_time - launch_time, 0.0)
	var launch_ramp: float = 1.0
	if spiral_launch_ramp_s > 0.0:
		launch_ramp = clampf(time_since_launch / spiral_launch_ramp_s, 0.0, 1.0)

	var far_range: float = maxf(terminal_attack_distance * 4.0, 1.0)
	var far_weight: float = clampf(distance_to_target / far_range, 0.0, 1.0)
	var terminal_radius_scale: float = lerpf(1.0, clampf(spiral_terminal_scale, 0.0, 1.0), clampf(terminal_t, 0.0, 1.0))
	var radius_scale: float = terminal_radius_scale * lerpf(0.8, 1.0, far_weight)
	var spiral_radius: float = spiral_radius_m * _spiral_radius_scale * launch_ramp * radius_scale
	var theta: float = _spiral_phase + time_since_launch * spiral_frequency_hz * TAU * _spiral_direction

	return spiral_right * cos(theta) * spiral_radius + spiral_up * sin(theta) * spiral_radius

func _get_effective_proximity_radius(target_node = null) -> float:
	var fuse_radius: float = maxf(proximity_detonation_distance, 1.0)
	if target_node and is_instance_valid(target_node):
		fuse_radius += maxf(proximity_target_padding_m, 0.0)
	return fuse_radius

func _closest_point_on_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab: Vector3 = b - a
	var ab_len_sq: float = ab.length_squared()
	if ab_len_sq <= 0.0001:
		return a
	var t: float = clampf((point - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	return a + ab * t

func _resolve_aircraft_target(body: Node) -> Node:
	var node: Node = body
	while node:
		if node == shooter:
			return null
		if node.has_method("take_damage") and node.is_in_group("aircraft"):
			return node
		node = node.get_parent()
	return null


func _trigger_explosion(hit_body: Node = null):
	# Create custom explosion with missile's damage values
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion)
		
		explosion.global_position = global_position
		
		# Set explosion damage
		explosion.max_damage = explosion_damage_splash
		explosion.min_damage = explosion_damage_splash
		explosion.blast_radius = explosion_radius
		explosion.use_line_of_sight = false
		if explosion is Explosion:
			(explosion as Explosion).visual_preset = Explosion.VisualPreset.STANDARD
		if "source_attacker" in explosion and is_instance_valid(shooter):
			explosion.source_attacker = shooter
		
	if hit_body and hit_body.has_method("take_damage"):
		_report_damage_credit(hit_body, damage_direct_hit)
		hit_body.take_damage(damage_direct_hit)
	
	# Mark as impacted and cleanup
	has_impacted = true
	queue_free()
