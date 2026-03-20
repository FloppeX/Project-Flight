extends Node

# Global particle manager - handles all types of particles independently of their creators
var particles: Array = []

func _ready():
	# Make this an autoload singleton
	set_process(true)

func _process(delta):
	# Update all particles globally
	for i in range(particles.size() - 1, -1, -1):
		var particle = particles[i]
		if not is_instance_valid(particle.mesh_instance):
			particles.remove_at(i)
			continue
			
		particle.life_time += delta
		
		# Apply particle behaviors based on type
		match particle.type:
			"smoke":
				_update_smoke_particle(particle, delta)
			"explosion":
				_update_explosion_particle(particle, delta)
			"spark":
				_update_spark_particle(particle, delta)
			_:
				_update_default_particle(particle, delta)
		
		# Remove expired particles
		if particle.life_time >= particle.max_life:
			particle.mesh_instance.queue_free()
			particles.remove_at(i)

func _update_smoke_particle(particle: Dictionary, delta: float):
	var life_progress: float = particle.life_time / particle.max_life

	# Rise upward
	if "rise_speed" in particle:
		particle.mesh_instance.global_position.y += particle.rise_speed * delta
		# Slow down rise over time
		particle.rise_speed *= (1.0 - delta * 0.3)

	# Expand uniformly over time
	if "expand" in particle and particle.expand:
		var expand_factor: float = 1.0 + life_progress * 1.2
		particle.mesh_instance.scale = particle.initial_scale * expand_factor
	else:
		var scale_factor = 1.0 - life_progress * 0.9
		particle.mesh_instance.scale = particle.initial_scale * scale_factor

	# Slow rotation
	if "yaw_speed" in particle:
		particle.mesh_instance.rotation.y += particle.yaw_speed * delta

	# Fade out
	if particle.mesh_instance.material_override:
		var alpha: float = 1.0 - life_progress * life_progress  # Quadratic fade — visible longer
		particle.mesh_instance.material_override.albedo_color.a = alpha

func _update_explosion_particle(particle: Dictionary, delta: float):
	# Scale up quickly then fade
	var life_progress = particle.life_time / particle.max_life
	var scale_factor = 1.0 + life_progress * 2.0  # Grow to 3x size
	particle.mesh_instance.scale = particle.initial_scale * scale_factor
	
	# Fade out
	if particle.mesh_instance.material_override:
		var alpha = 1.0 - life_progress
		particle.mesh_instance.material_override.albedo_color.a = alpha

func _update_spark_particle(particle: Dictionary, delta: float):
	# Move with velocity and fade
	if "velocity" in particle:
		particle.mesh_instance.global_position += particle.velocity * delta
		# Apply gravity
		particle.velocity.y -= 9.8 * delta
	
	# Fade out
	var life_progress = particle.life_time / particle.max_life
	if particle.mesh_instance.material_override:
		var alpha = 1.0 - life_progress
		particle.mesh_instance.material_override.albedo_color.a = alpha

func _update_default_particle(particle: Dictionary, delta: float):
	# Basic fade out
	var life_progress = particle.life_time / particle.max_life
	if particle.mesh_instance.material_override:
		var alpha = 1.0 - life_progress
		particle.mesh_instance.material_override.albedo_color.a = alpha

func add_particle(mesh_instance: MeshInstance3D, type: String, max_life: float, initial_scale: Vector3, extra_data: Dictionary = {}):
	var particle_data = {
		"mesh_instance": mesh_instance,
		"type": type,
		"life_time": 0.0,
		"max_life": max_life,
		"initial_scale": initial_scale
	}
	
	# Add extra data for specific particle types
	for key in extra_data:
		particle_data[key] = extra_data[key]
	
	particles.append(particle_data)

# Convenience functions for common particle types
func add_smoke_particle(mesh_instance: MeshInstance3D, max_life: float, initial_scale: Vector3):
	add_particle(mesh_instance, "smoke", max_life, initial_scale)

func add_rising_smoke(mesh_instance: MeshInstance3D, max_life: float, initial_scale: Vector3, rise_speed: float = 5.0, yaw_speed: float = 0.0):
	add_particle(mesh_instance, "smoke", max_life, initial_scale, {
		"rise_speed": rise_speed,
		"expand": true,
		"yaw_speed": yaw_speed,
	})

func add_explosion_particle(mesh_instance: MeshInstance3D, max_life: float, initial_scale: Vector3):
	add_particle(mesh_instance, "explosion", max_life, initial_scale)

func add_spark_particle(mesh_instance: MeshInstance3D, max_life: float, initial_scale: Vector3, velocity: Vector3):
	add_particle(mesh_instance, "spark", max_life, initial_scale, {"velocity": velocity})