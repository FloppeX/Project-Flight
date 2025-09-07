extends Node3D
class_name Explosion

@export var blast_radius: float = 15.0  # Increased from 5.0
@export var flash_duration: float = 1  # Increased from 0.15
@export var debris_count: int = 25  # Increased from 15
@export var effect_duration: float = 8.0  # Increased from 2.0

var debris_particles: GPUParticles3D
var smoke_particles: GPUParticles3D

func _ready():
	print("=== EXPLOSION CREATED ===")
	# Only create the effects we want - NO SPHERES
	create_debris_particles()
	create_smoke_particles()
	create_fire_debris()
	
	# Start the explosion sequence
	trigger_explosion()

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
