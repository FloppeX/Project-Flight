extends ProjectileNew
class_name AGMissile

@export var max_speed_mps: float = 100.0
@export var thrust_force: float = 1200.0
@export var steer_torque: float = 80.0
@export var lift_coefficient: float = 0.6
@export var drag_coefficient: float = 0.5
@export var turbulence_strength: float = 6.0
@export var explosion_damage: float = 200.0
@export var engine_on: bool = true

# Guidance system parameters
@export var high_approach_altitude: float = 100.0  # Height above target for phase 1
@export var terminal_attack_distance: float = 100.0  # Distance to switch to phase 2
@export var lead_velocity_threshold: float = 15.0  # Min target velocity for lead prediction
@export var lead_factor: float = 0.2  # How much to lead fast-moving targets

# Explosion parameters
@export var explosion_radius: float = 30.0  # Blast radius in meters
@export var explosion_damage_multiplier: float = 2.0  # Multiplier for max damage (damage * this = max explosion damage)
@export var arming_time: float = 2.0  # Time in seconds before missile can explode
@export var proximity_detonation_distance: float = 3.0  # Distance from ground to detonate

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
	damage = explosion_damage
	if explosion_scene == null:
		explosion_scene = load("res://Projectiles/Explosion/explosion.tscn")
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 32
	can_sleep = false
	sleeping = false
	# Ensure we collide with enemies (layer 1) and terrain (layer 10)
	set_collision_mask(0x7fffffff)
	# Ensure body_entered is connected (redundant but robust)
	if not is_connected("body_entered", Callable(self, "_on_body_entered")):
		body_entered.connect(_on_body_entered)
	# Keep default collision_layer unless customized
	

func set_target(t: Node3D) -> void:
	target = t

func fire_with_target(initial_velocity: Vector3, firing_aircraft: Node3D, t: Node3D) -> void:
	set_target(t)
	fire(initial_velocity, firing_aircraft)

func fire(initial_velocity: Vector3, firing_aircraft: Node3D):
	# Call parent fire method
	super.fire(initial_velocity, firing_aircraft)
	# Record launch time for arming delay
	launch_time = Time.get_ticks_msec() / 1000.0
	is_armed = false
	print("Missile launched - will arm in ", arming_time, " seconds")

func _physics_process(delta):
	# Check arming status
	if not is_armed and launch_time > 0.0:
		var current_time = Time.get_ticks_msec() / 1000.0
		if (current_time - launch_time) >= arming_time:
			is_armed = true
			print("Missile armed and ready to explode")
	
	# Proximity detonation check (if armed)
	if is_armed and proximity_detonation_distance > 0.0:
		_check_proximity_detonation()
	
	# Base projectile tunneling detection
	super._physics_process(delta)
	if engine_on:
		_apply_thrust_and_lift(delta)
		_apply_guidance(delta)
	# Always update smoke trail regardless of engine state for visibility testing
	_update_smoke_trail(delta)
	_apply_drag_and_limit_speed(delta)
	_apply_turbulence(delta)

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
	
	# Two-phase missile guidance: high approach then direct attack
	var distance_to_target: float = global_position.distance_to(target.global_position)
	var base_target_pos: Vector3 = target.global_position
	
	# Apply lead prediction for fast-moving targets
	if target_velocity.length() > lead_velocity_threshold:
		var missile_speed: float = max(linear_velocity.length(), 50.0)
		var time_to_target: float = distance_to_target / missile_speed
		base_target_pos = target.global_position + (target_velocity * time_to_target * lead_factor)
	
	# Two-phase guidance system
	var attack_point: Vector3
	if distance_to_target > terminal_attack_distance:
		# Phase 1: Head to point above target for high approach
		attack_point = base_target_pos + Vector3.UP * high_approach_altitude
	else:
		# Phase 2: Within terminal distance, dive straight at target
		attack_point = base_target_pos
	
	var to_target: Vector3 = (attack_point - global_position).normalized()
	var fwd: Vector3 = global_transform.basis.z.normalized()
	var dot_val: float = clamp(fwd.dot(to_target), -1.0, 1.0)
	var angle_err: float = acos(dot_val)
	
	if angle_err < 0.001:
		return
	
	var steer_axis: Vector3 = fwd.cross(to_target)
	if steer_axis.length() > 0.0001:
		steer_axis = steer_axis.normalized()
		# Reduce steering force as we get closer to prevent overshooting
		var distance_factor: float = clamp(distance_to_target / 200.0, 0.3, 1.0)
		var torque_mag: float = steer_torque * angle_err * distance_factor
		apply_torque(steer_axis * torque_mag)
	
	# Increased angular damping for stability
	angular_velocity *= 0.95

func _on_body_entered(body):
	print("=== MISSILE HIT ===")
	print("Hit body: ", body.name, " (", body.get_class(), ")")
	print("Missile armed: ", is_armed)
	print("Body collision layer: ", body.collision_layer if body.has_method("get_collision_layer") else "N/A")
	
	# Check if missile is armed before exploding
	if not is_armed:
		print("Missile not armed yet - impact ignored")
		return
	
	print("Body has take_damage method: ", body.has_method("take_damage"))
	print("Missile damage: ", damage)
	print("Body groups: ", body.get_groups())
	
	# Trigger explosion
	_trigger_explosion(body)

func _apply_drag_and_limit_speed(delta: float) -> void:
	if drag_coefficient > 0.0:
		linear_velocity /= (1.0 + drag_coefficient * delta)
	var speed: float = linear_velocity.length()
	if speed > max_speed_mps:
		linear_velocity = linear_velocity.normalized() * max_speed_mps

func _apply_turbulence(delta: float) -> void:
	var fwd: Vector3 = global_transform.basis.z
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(fwd).normalized()
	var lateral: Vector3 = (right * (randf() - 0.5) + up * (randf() - 0.5)).normalized()
	apply_central_force(lateral * turbulence_strength)

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
		particle_manager = preload("res://ParticleManager.gd").new()
		particle_manager.name = "ParticleManager"
		get_tree().root.add_child(particle_manager)
	
	particle_manager.add_smoke_particle(smoke_mesh, 1.5, Vector3(2.0, 2.0, 2.0))

func _check_proximity_detonation():
	# Raycast downward to check distance to ground
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position
	var to: Vector3 = global_position - Vector3.UP * (proximity_detonation_distance + 2.0)
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	params.collision_mask = (1 << 0) | (1 << 9)  # Terrain layers
	
	var hit: Dictionary = space_state.intersect_ray(params)
	if hit and hit.has("position"):
		var distance_to_ground: float = global_position.distance_to(hit.position)
		if distance_to_ground <= proximity_detonation_distance:
			print("Proximity detonation triggered at ", distance_to_ground, "m from ground")
			_trigger_explosion(hit.collider if hit.has("collider") else null)

func _trigger_explosion(hit_body: Node = null):
	# Create custom explosion with missile's damage values
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion)
		
		# Position explosion 1m above ground to avoid line-of-sight issues
		explosion.global_position = global_position + Vector3.UP * 1.0
		
		# Set explosion damage to match missile damage
		explosion.max_damage = damage * explosion_damage_multiplier
		explosion.min_damage = damage * 0.5
		explosion.blast_radius = explosion_radius
		explosion.use_line_of_sight = false
		
		print("Explosion created at position: ", explosion.global_position)
		print("Explosion stats: max_damage=", explosion.max_damage, " blast_radius=", explosion.blast_radius, " LOS=", explosion.use_line_of_sight)
		
		# Always create scorch mark for missile explosions since they detonate near ground
		explosion.create_scorch_mark()
	
	# Mark as impacted and cleanup
	has_impacted = true
	queue_free()
