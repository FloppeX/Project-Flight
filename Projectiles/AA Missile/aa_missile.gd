extends ProjectileNew
class_name AAMissile

@export var max_speed_mps: float = 600.0
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

# Explosion parameters
@export var explosion_radius: float = 10.0  # Blast radius in meters
@export var explosion_damage_splash: float = 50.0  # Damage for standard explosion splash
@export var fuel_life_seconds: float = 4.0  # Disables after 4 seconds
@export var arming_time: float = 0.5  # Time in seconds before missile can explode
@export var engine_ignition_delay: float = 0.1  # Fast start
@export var proximity_detonation_distance: float = 10.0  # Detonate if it passes within 10m of a plane

var target: Node3D
var smoke_particles: Array = []
var smoke_timer: float = 0.0
var smoke_interval: float = 0.05  # Emit every 3 frames at 60fps
var launch_time: float = 0.0
var is_armed: bool = false

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
	# Call parent fire method
	super.fire(initial_velocity, firing_aircraft)
	# Record launch time for arming and engine ignition delays
	launch_time = Time.get_ticks_msec() / 1000.0
	is_armed = false
	engine_on = false  # Start with engine OFF - will be enabled after ignition delay
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
	
	# Get target velocity for lead calculation
	var target_velocity: Vector3 = Vector3.ZERO
	if target.has_method("get_linear_velocity"):
		target_velocity = target.get_linear_velocity()
	elif "linear_velocity" in target:
		target_velocity = target.linear_velocity
	
	var distance_to_target: float = global_position.distance_to(target.global_position)
	var base_target_pos: Vector3 = target.global_position
	
	# Improved lead prediction - disable when very close to prevent overshooting
	if target_velocity.length() > lead_velocity_threshold and distance_to_target > 75.0:
		var missile_speed: float = max(linear_velocity.length(), 50.0)
		var time_to_target: float = distance_to_target / missile_speed

		# Reduce lead factor based on distance - much less lead when close
		var distance_lead_factor: float = clamp(distance_to_target / 300.0, 0.05, 1.0)
		var adjusted_lead_factor: float = lead_factor * distance_lead_factor

		# Cap the lead prediction to prevent extreme overshooting
		var lead_prediction: Vector3 = target_velocity * time_to_target * adjusted_lead_factor
		var max_lead_distance: float = distance_to_target * 0.15  # Reduced from 30% to 15%
		if lead_prediction.length() > max_lead_distance:
			lead_prediction = lead_prediction.normalized() * max_lead_distance

		base_target_pos = target.global_position + lead_prediction
	
	# Progressive three-phase guidance system to prevent overshooting
	var attack_point = base_target_pos
	
	var to_target: Vector3 = (attack_point - global_position).normalized()
	var fwd: Vector3 = global_transform.basis.z.normalized()
	var dot_val: float = clamp(fwd.dot(to_target), -1.0, 1.0)
	var angle_err: float = acos(dot_val)
	
	if angle_err < 0.001:
		return
	
	var steer_axis: Vector3 = fwd.cross(to_target)
	if steer_axis.length() > 0.0001:
		steer_axis = steer_axis.normalized()
		
		# Improved distance-based steering control
		var distance_factor: float
		if distance_to_target < 100.0:
			# REDUCE steering when very close to prevent overshoot
			distance_factor = clamp(distance_to_target / 100.0, 0.1, 0.5)  # Much gentler steering when close
		else:
			# Normal steering when far
			distance_factor = clamp(distance_to_target / 200.0, 0.5, 1.0)
		
		var torque_mag: float = steer_torque * angle_err * distance_factor
		apply_torque(steer_axis * torque_mag)

	# Apply maximum turn rate limiting
	var max_angular_velocity = deg_to_rad(max_turn_rate_deg_per_sec)
	if angular_velocity.length() > max_angular_velocity:
		angular_velocity = angular_velocity.normalized() * max_angular_velocity

	# Progressive angular damping based on distance for stability
	var damping_factor: float = 0.95
	if distance_to_target < 100.0:
		# Increase damping progressively as we get closer
		var damping_strength = clamp((100.0 - distance_to_target) / 100.0, 0.0, 1.0)
		damping_factor = lerp(0.95, 0.7, damping_strength)  # Stronger damping when very close
	angular_velocity *= damping_factor

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
		smoke_timer = 0.0

func _emit_smoke_particle() -> void:
	# Create smoke particle
	var smoke_mesh = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(2.0, 2.0, 2.0)  # Reasonable size
	smoke_mesh.mesh = box_mesh
	smoke_mesh.name = "SmokeParticle_" + str(Time.get_ticks_msec())
	
	# Create bright white smoke material for visibility
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE  # Bright white for visibility
	material.flags_unshaded = true
	smoke_mesh.material_override = material
	
	# Position directly behind missile (no random offset)
	var rear_offset = global_transform.basis.z * -3.0  # 3m behind missile
	smoke_mesh.global_position = global_position + rear_offset
	
	# Add random rotation for visual variety
	smoke_mesh.rotation = Vector3(
		randf() * TAU,  # Random rotation around X axis
		randf() * TAU,  # Random rotation around Y axis
		randf() * TAU   # Random rotation around Z axis
	)
	
	# Add to scene
	get_tree().current_scene.add_child(smoke_mesh)
	
	# Register with global particle manager for independent updating
	var particle_manager = get_node_or_null("/root/ParticleManager")
	if not particle_manager:
		# Create particle manager if it doesn't exist
		particle_manager = preload("res://Effects/ParticleManager.gd").new()
		particle_manager.name = "ParticleManager"
		get_tree().root.add_child(particle_manager)
	
	particle_manager.add_smoke_particle(smoke_mesh, 1.5, Vector3(2.0, 2.0, 2.0))

func _check_proximity_detonation():
	# First cheap check: distance to locked target
	if target and is_instance_valid(target):
		var dist = global_position.distance_to(target.global_position)
		if dist <= proximity_detonation_distance:
			_trigger_explosion(target)
			return

	# Sphere-overlap query so we don't skip past aircraft at high speed
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = proximity_detonation_distance
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
		if body is RigidBody3D and body.is_in_group("aircraft"):
			_trigger_explosion(body)
			return


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
		
	if hit_body and hit_body.has_method("take_damage"):
		hit_body.take_damage(damage_direct_hit)
	
	# Mark as impacted and cleanup
	has_impacted = true
	queue_free()
