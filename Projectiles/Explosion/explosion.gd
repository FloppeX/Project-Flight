extends Node3D
class_name Explosion

@export var blast_radius: float = 25.0  # Much bigger explosions
@export var flash_duration: float = 1  # Increased from 0.15
@export var debris_count: int = 25  # Increased from 15
@export var effect_duration: float = 8.0  # Increased from 2.0
@export var explosion_sounds: Array[AudioStream] = []

# Damage properties
@export var max_damage: float = 100.0  # Maximum damage at center
@export var min_damage: float = 10.0   # Minimum damage at edge

var debris_particles: GPUParticles3D
var smoke_particles: GPUParticles3D
var sfx_explosion: AudioStreamPlayer3D

func _ready():
	# Only create the effects we want - NO SPHERES
	create_debris_particles()
	create_smoke_particles()
	create_fire_debris()
	setup_explosion_audio()
	
	# Start the explosion sequence
	trigger_explosion()

func setup_explosion_audio():
	sfx_explosion = AudioStreamPlayer3D.new()
	add_child(sfx_explosion)
	
	# Use explosion sounds if available, otherwise load a default one
	var selected_sound: AudioStream
	if explosion_sounds.size() > 0:
		# Randomly select one of the explosion sounds
		selected_sound = explosion_sounds[randi() % explosion_sounds.size()]
		print("Selected explosion sound: ", selected_sound.resource_path)
	else:
		# Fallback to default explosion sound
		selected_sound = load("res://Sounds/explosion_large_01.wav")
		print("Using fallback explosion sound")
	
	sfx_explosion.stream = selected_sound
	sfx_explosion.volume_db = 0.0
	sfx_explosion.max_distance = 800.0  # Realistic range - 800m
	sfx_explosion.unit_size = 50.0      # Smaller unit size for more realistic falloff
	sfx_explosion.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	sfx_explosion.add_to_group("3d_audio")  # Add to group for audio management

func create_debris_particles():
	print("Creating debris particles...")
	debris_particles = GPUParticles3D.new()
	add_child(debris_particles)
	
	# Configure the particle system
	debris_particles.emitting = false
	debris_particles.amount = debris_count
	debris_particles.lifetime = effect_duration
	debris_particles.one_shot = true
	
	# Create particle material
	var process_material = ParticleProcessMaterial.new()
	
	# Emission
	process_material.direction = Vector3(0, 1, 0)
	process_material.initial_velocity_min = 8.0   # Faster (was 3.0)
	process_material.initial_velocity_max = 15.0  # Faster (was 8.0)
	process_material.angular_velocity_min = -360.0
	process_material.angular_velocity_max = 360.0
	
	# Spread particles in all directions
	process_material.spread = 45.0
	
	# Gravity and damping
	process_material.gravity = Vector3(0, -9.8, 0)
	process_material.linear_accel_min = -2.0
	process_material.linear_accel_max = -5.0
	
	# Size and color
	process_material.scale_min = 0.2  # Bigger debris (was 0.1)
	process_material.scale_max = 0.6  # Bigger debris (was 0.3)
	process_material.color = Color.BLACK
	
	debris_particles.process_material = process_material
	
	# Simple cube mesh for debris
	var cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3(0.2, 0.2, 0.2)  # Bigger cubes
	debris_particles.draw_pass_1 = cube_mesh

func create_smoke_particles():
	print("Creating smoke particles...")
	smoke_particles = GPUParticles3D.new()
	add_child(smoke_particles)
	
	# Configure smoke
	smoke_particles.emitting = false
	smoke_particles.amount = 50  # More smoke particles (was 30)
	smoke_particles.lifetime = effect_duration
	smoke_particles.one_shot = true
	
	# Smoke material
	var process_material = ParticleProcessMaterial.new()
	
	# Emission
	process_material.direction = Vector3(0, 1, 0)
	process_material.initial_velocity_min = 2.0  # Slower rise
	process_material.initial_velocity_max = 5.0  # Slower rise
	
	# Spread
	process_material.spread = 35.0
	
	# Gravity (smoke rises)
	process_material.gravity = Vector3(0, -1.0, 0)  # Even lighter gravity
	
	# Size grows over time
	process_material.scale_min = 1.0  # Start bigger (was 0.5)
	process_material.scale_max = 3.0  # End bigger (was 1.5)
	
	# Color and transparency
	process_material.color = Color.GRAY
	process_material.color_ramp = create_smoke_gradient()
	
	smoke_particles.process_material = process_material
	
	# Use quad mesh for smoke
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(1.0, 1.0)  # Bigger smoke puffs
	smoke_particles.draw_pass_1 = quad_mesh

func create_smoke_gradient() -> Gradient:
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.5, 0.5, 0.5, 1.0))  # Solid gray at start
	gradient.add_point(1.0, Color(0.5, 0.5, 0.5, 0.0))  # Transparent at end
	return gradient

func create_fire_debris():
	print("Creating fire debris...")
	# Create several individual fire-trailing pieces
	for i in range(6):  # 6 burning debris pieces
		print("Creating fire debris piece: ", i)
		create_single_fire_debris(i)

func create_single_fire_debris(index: int):
	# Container for the debris piece and its trail
	var debris_container = Node3D.new()
	add_child(debris_container)
	debris_container.name = "FireDebris_" + str(index)
	
	print("Created debris container: ", debris_container.name)
	
	# The actual debris piece (bigger, more visible cube)
	var debris_mesh = MeshInstance3D.new()
	debris_container.add_child(debris_mesh)
	
	var cube = BoxMesh.new()
	cube.size = Vector3(0.8, 0.8, 0.8)  # Much bigger so we can see it
	debris_mesh.mesh = cube
	
	# Hot glowing material for the debris - make it VERY bright
	var debris_material = StandardMaterial3D.new()
	debris_material.emission_enabled = true
	debris_material.emission = Color.ORANGE_RED
	debris_material.emission_energy = 8.0  # Much brighter
	debris_material.albedo_color = Color.YELLOW  # Bright color
	debris_mesh.material_override = debris_material
	
	print("Debris mesh created with bright material")
	
	# Launch debris in random direction
	var launch_direction = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(0.5, 1.0),  # More upward component
		randf_range(-1.0, 1.0)
	).normalized()
	
	var launch_speed = randf_range(5.0, 10.0)  # Slower so we can see it
	var target_position = launch_direction * launch_speed
	
	print("Launch direction: ", launch_direction)
	print("Target position: ", target_position)
	
	# Animate the debris movement - slower and longer
	var debris_tween = create_tween()
	debris_tween.tween_property(debris_container, "position", target_position, 4.0)  # Slower movement
	debris_tween.tween_callback(func(): 
		print("Debris piece finished flying: ", debris_container.name)
		debris_container.queue_free()
	)

func trigger_explosion():
	print("=== TRIGGERING EXPLOSION ===")
	# Start particles
	debris_particles.restart()
	smoke_particles.restart()
	
	# Play explosion sound
	if sfx_explosion:
		sfx_explosion.play()
		print("Playing explosion sound")
	
	# Deal damage to enemies in blast radius
	deal_explosion_damage()
	
	# Create multiple flash bursts for angular effect (instead of sphere)
	create_angular_bursts()
	
	# Clean up explosion after effects finish
	get_tree().create_timer(effect_duration + 0.5).timeout.connect(cleanup_explosion)

func create_angular_bursts():
	print("Creating three rotating fire cubes...")
	
	# Create three cubes with different fire colors
	var colors = [
		{"name": "Red", "color": Color.RED, "emission": Color.ORANGE_RED},
		{"name": "Yellow", "color": Color.YELLOW, "emission": Color.YELLOW},
		{"name": "Orange", "color": Color.ORANGE, "emission": Color.ORANGE}
	]
	
	for i in range(3):
		var cube = MeshInstance3D.new()
		add_child(cube)
		cube.name = "FireCube_" + colors[i]["name"]
		
		# Create cube mesh
		var cube_mesh = BoxMesh.new()
		cube_mesh.size = Vector3(1.0, 1.0, 1.0)  # Start at reasonable size
		cube.mesh = cube_mesh
		
		# Create bright fire material
		var material = StandardMaterial3D.new()
		material.emission_enabled = true
		material.emission = colors[i]["emission"]
		material.emission_energy = 6.0
		material.albedo_color = colors[i]["color"]
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.8  # Slightly transparent so they blend
		
		cube.material_override = material
		
		# Position all cubes at center
		cube.position = Vector3.ZERO
		
		# Random rotation speeds for each axis
		var rotation_speed = Vector3(
			randf_range(-10.0, 10.0),  # X rotation speed
			randf_range(-10.0, 10.0),  # Y rotation speed
			randf_range(-10.0, 10.0)   # Z rotation speed
		)
		
		print("Created fire cube: ", cube.name, " with rotation speed: ", rotation_speed)
		
		# Create the expansion and rotation animation
		var cube_tween = create_tween()
		
		# Start small and expand quickly
		cube.scale = Vector3(0.1, 0.1, 0.1)
		cube_tween.parallel().tween_property(cube, "scale", Vector3(blast_radius * 0.8, blast_radius * 0.8, blast_radius * 0.8), flash_duration * 0.4)
		
		# Fade out the emission and transparency
		cube_tween.parallel().tween_method(set_cube_intensity.bind(cube), 6.0, 0.0, flash_duration)
		
		# Rotation animation - keep rotating throughout the explosion
		animate_cube_rotation(cube, rotation_speed, flash_duration)
		
		# Clean up when done
		cube_tween.tween_callback(cube.queue_free)

func animate_cube_rotation(cube: MeshInstance3D, rotation_speed: Vector3, duration: float):
	# Create a separate tween for continuous rotation
	var rotation_tween = create_tween()
	
	# Calculate total rotation over the duration
	var total_rotation = rotation_speed * duration
	var target_rotation = cube.rotation + total_rotation
	
	rotation_tween.tween_property(cube, "rotation", target_rotation, duration)

func set_cube_intensity(cube: MeshInstance3D, intensity: float):
	if cube and cube.material_override:
		var material = cube.material_override as StandardMaterial3D
		material.emission_energy = intensity
		material.albedo_color.a = intensity * 0.15  # Fade transparency

func cleanup_explosion():
	print("=== CLEANING UP EXPLOSION ===")
	# Remove particle systems but leave scorch mark
	if debris_particles:
		debris_particles.queue_free()
	if smoke_particles:
		smoke_particles.queue_free()

func create_scorch_mark():
	print("Creating scorch mark...")
	# Create a decal for the scorch mark
	var decal = Decal.new()
	add_child(decal)
	
	# Position slightly above ground to avoid z-fighting
	decal.position.y = 0.01
	
	# Size matches blast radius
	decal.size = Vector3(blast_radius, 0.1, blast_radius)
	
	# Random rotation for variety
	decal.rotation.y = randf() * TAU
	
	# Load your scorch mark PNG texture
	decal.texture_albedo = preload("res://Projectiles/Explosion/scorch_mark.png")

func deal_explosion_damage():
	"""Deal damage to all enemies within blast radius"""
	print("=== DEALING EXPLOSION DAMAGE ===")
	print("Blast radius: ", blast_radius)
	print("Explosion position: ", global_position)
	
	# Find all potential targets in the scene
	var potential_targets = []
	
	# Look for enemies in groups
	var enemy_groups = ["enemies", "enemy", "targets", "aircraft"]
	for group_name in enemy_groups:
		var group_members = get_tree().get_nodes_in_group(group_name)
		for member in group_members:
			if member != self and member.has_method("take_damage"):
				potential_targets.append(member)
	
	# Also check all RigidBody3D nodes (could be enemy aircraft)
	var all_bodies = get_tree().get_nodes_in_group("aircraft")
	for body in all_bodies:
		if body != self and body.has_method("take_damage"):
			if not body in potential_targets:
				potential_targets.append(body)
	
	print("Found ", potential_targets.size(), " potential targets to check")
	
	# Check distance and deal damage
	var targets_hit = 0
	for target in potential_targets:
		var distance = global_position.distance_to(target.global_position)
		print("Target ", target.name, " distance: ", distance)
		
		if distance <= blast_radius:
			# Calculate damage based on distance (closer = more damage)
			var damage_ratio = 1.0 - (distance / blast_radius)
			var damage = lerp(min_damage, max_damage, damage_ratio)
			
			print("Hitting ", target.name, " with ", damage, " damage (distance: ", distance, ")")
			target.take_damage(damage)
			targets_hit += 1
			
			# Add knockback force if target is a RigidBody3D
			if target is RigidBody3D:
				var knockback_direction = (target.global_position - global_position).normalized()
				var knockback_force = (max_damage - damage) * 100.0  # Scale force to damage
				target.apply_central_impulse(knockback_direction * knockback_force)
				print("Applied knockback to ", target.name)
	
	print("Explosion hit ", targets_hit, " targets")
	
	# Create visual blast wave
	create_blast_wave()

func create_blast_wave():
	"""Create a visual blast wave ring to show the damage area"""
	print("Creating blast wave ring...")
	
	# Create a torus-shaped blast wave
	var blast_ring = MeshInstance3D.new()
	add_child(blast_ring)
	
	# Create torus mesh for ring shape
	var torus_mesh = TorusMesh.new()
	torus_mesh.inner_radius = blast_radius * 0.8
	torus_mesh.outer_radius = blast_radius
	blast_ring.mesh = torus_mesh
	
	# Create bright blast material
	var blast_material = StandardMaterial3D.new()
	blast_material.emission_enabled = true
	blast_material.emission = Color.ORANGE_RED
	blast_material.emission_energy = 10.0
	blast_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blast_material.albedo_color = Color(1.0, 0.5, 0.0, 0.8)  # Orange with transparency
	blast_ring.material_override = blast_material
	
	# Start small and expand rapidly
	blast_ring.scale = Vector3(0.1, 0.1, 0.1)
	
	# Animate the blast wave
	var blast_tween = create_tween()
	
	# Expand quickly
	blast_tween.parallel().tween_property(blast_ring, "scale", Vector3(1.0, 0.2, 1.0), 0.3)
	
	# Fade out
	blast_tween.parallel().tween_method(set_blast_wave_alpha.bind(blast_ring), 0.8, 0.0, 0.5)
	
	# Clean up
	blast_tween.tween_callback(blast_ring.queue_free)

func set_blast_wave_alpha(blast_ring: MeshInstance3D, alpha: float):
	"""Helper function to fade the blast wave"""
	if blast_ring and blast_ring.material_override:
		var material = blast_ring.material_override as StandardMaterial3D
		material.albedo_color.a = alpha
		material.emission_energy = alpha * 10.0
