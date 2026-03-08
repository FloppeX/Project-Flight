extends Node3D
class_name Explosion

@export var blast_radius: float = 25.0  # Much bigger explosions
@export var flash_duration: float = 1  # Increased from 0.15
@export var debris_count: int = 25  # Increased from 15
@export var effect_duration: float = 8.0  # Increased from 2.0
@export var explosion_sounds: Array[AudioStream] = []
@export var use_line_of_sight: bool = true  # Do raycast LOS checks before applying damage/impulse
@export var debug_enabled: bool = false

# Damage properties
@export var max_damage: float = 100.0  # Maximum damage at center
@export var min_damage: float = 10.0   # Minimum damage at edge
@export var knockback_impulse_at_center: float = 2500.0
@export var knockback_impulse_at_edge: float = 250.0

var debris_particles: GPUParticles3D
var smoke_particles: GPUParticles3D
var sfx_explosion: AudioStreamPlayer3D

func _ready():
	# Only create the effects we want - NO SPHERES
	create_smoke_particles()
	create_fire_debris()
	setup_explosion_audio()
	
	# Start the explosion sequence — deferred so the caller can set global_position first
	call_deferred("trigger_explosion")

func setup_explosion_audio():
	sfx_explosion = AudioStreamPlayer3D.new()
	add_child(sfx_explosion)
	
	# Use explosion sounds if available, otherwise load a default one
	var selected_sound: AudioStream
	if explosion_sounds.size() > 0:
		# Randomly select one of the explosion sounds
		selected_sound = explosion_sounds[randi() % explosion_sounds.size()]
		if debug_enabled:
			print("Selected explosion sound: ", selected_sound.resource_path)
	else:
		# Fallback to default explosion sound
		selected_sound = load("res://Sounds/explosion_large_01.wav")
		if debug_enabled:
			print("Using fallback explosion sound")
	
	sfx_explosion.stream = selected_sound
	sfx_explosion.volume_db = 0.0
	sfx_explosion.max_distance = 800.0  # Realistic range - 800m
	sfx_explosion.unit_size = 50.0      # Smaller unit size for more realistic falloff
	sfx_explosion.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	sfx_explosion.add_to_group("3d_audio")  # Add to group for audio management

func create_debris_particles():
	if debug_enabled:
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

func create_smoke_particles() -> void:
	# Stub — volumetric puffs are spawned at trigger time
	smoke_particles = GPUParticles3D.new()
	smoke_particles.amount = 0
	add_child(smoke_particles)

func create_fire_debris():
	if debug_enabled:
		print("Creating fire debris...")
	# Create several individual fire-trailing pieces
	for i in range(6):  # 6 burning debris pieces
		create_single_fire_debris(i)

func create_single_fire_debris(index: int):
	# Container for the debris piece and its trail
	var debris_container = Node3D.new()
	add_child(debris_container)
	debris_container.name = "FireDebris_" + str(index)
	
	if debug_enabled:
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
	
	if debug_enabled:
		print("Debris mesh created with bright material")
	
	# Launch debris in random direction
	var launch_direction = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(0.5, 1.0),  # More upward component
		randf_range(-1.0, 1.0)
	).normalized()
	
	var launch_speed = randf_range(5.0, 10.0)  # Slower so we can see it
	var target_position = launch_direction * launch_speed
	
	if debug_enabled:
		print("Launch direction: ", launch_direction)
		print("Target position: ", target_position)
	
	# Animate the debris movement - slower and longer
	var debris_tween = create_tween()
	debris_tween.tween_property(debris_container, "position", target_position, 4.0)  # Slower movement
	debris_tween.tween_callback(func(): 
		if debug_enabled:
			print("Debris piece finished flying: ", debris_container.name)
		debris_container.queue_free()
	)

func _start_smoke_puffs() -> void:
	var puff_count := 12
	var captured_pos := global_position
	for i in range(puff_count):
		var progress := float(i) / float(puff_count - 1)
		get_tree().create_timer(i * 0.28).timeout.connect(func():
			if is_instance_valid(self):
				_spawn_smoke_puff(progress, captured_pos)
		)

func _spawn_smoke_puff(progress: float, origin: Vector3) -> void:
	print("[Smoke] spawning puff progress=", snapped(progress, 0.01), " at ", snapped(origin, Vector3.ONE))
	var puff := MeshInstance3D.new()
	get_tree().current_scene.add_child(puff)
	puff.global_position = origin + Vector3(
		randf_range(-2.5, 2.5),
		progress * 10.0,
		randf_range(-2.5, 2.5)
	)

	# Low-poly sphere for faceted irregular cloud look
	var sphere := SphereMesh.new()
	sphere.radial_segments = 6
	sphere.rings = 4
	var base_r := randf_range(1.5, 3.5)
	sphere.radius = base_r
	sphere.height = base_r * 2.0
	puff.mesh = sphere

	# Non-uniform scale for lumpy shape; later puffs are bigger (they've had time to expand)
	puff.scale = Vector3(
		randf_range(0.8, 1.6),
		randf_range(0.5, 1.0),
		randf_range(0.8, 1.6)
	) * lerp(3.0, 6.0, progress)

	# Very dark at base (near black), dark grey higher up
	var grey: float = lerp(0.05, 0.30, progress)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(grey, grey, grey, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(grey, grey * 0.8, grey * 0.6)
	mat.emission_energy = 0.4
	puff.material_override = mat

	# Animate: rise, expand sideways/flatten, slow yaw, fade out
	var puff_duration := randf_range(3.5, 5.5)
	var rise := randf_range(14.0, 24.0)
	var end_scale := puff.scale * Vector3(2.2, 0.6, 2.2)
	var end_y := puff.position.y + rise

	var t := puff.create_tween()
	t.set_parallel(true)
	t.tween_property(puff, "position:y", end_y, puff_duration)
	t.tween_property(puff, "scale", end_scale, puff_duration)
	t.tween_property(puff, "rotation:y", randf_range(-TAU * 0.3, TAU * 0.3), puff_duration)
	t.tween_method(func(a: float):
		if is_instance_valid(puff) and puff.material_override:
			(puff.material_override as StandardMaterial3D).albedo_color.a = a
	, 1.0, 0.0, puff_duration)
	t.chain().tween_callback(puff.queue_free)

func trigger_explosion():
	print("[Explosion] at ", snapped(global_position, Vector3(1,1,1)))
	if debug_enabled:
		print("=== TRIGGERING EXPLOSION ===")
	# Start smoke puffs
	_start_smoke_puffs()
	
	# Play explosion sound
	if sfx_explosion:
		sfx_explosion.play()
		if debug_enabled:
			print("Playing explosion sound")
	
	# Deal damage to enemies in blast radius (delayed to allow position/radius to be set)
	call_deferred("deal_explosion_damage")
	
	# Create multiple flash bursts for angular effect (instead of sphere)
	create_angular_bursts()
	
	# Clean up explosion after effects finish
	get_tree().create_timer(effect_duration + 0.5).timeout.connect(cleanup_explosion)

func create_angular_bursts():
	if debug_enabled:
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
		
		if debug_enabled:
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
	if debug_enabled:
		print("=== CLEANING UP EXPLOSION ===")
	# Remove particle systems but leave scorch mark
	if smoke_particles:
		smoke_particles.queue_free()

func create_scorch_mark():
	if debug_enabled:
		print("Creating scorch mark at explosion position: ", global_position)
	# Raycast to find the terrain directly below the explosion and align the decal to the surface normal
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = global_position + Vector3.UP * 5.0  # Start higher to ensure we hit terrain
	var end: Vector3 = global_position - Vector3.UP * 200.0   # Raycast straight down from explosion
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	params.exclude = [self]
	params.collision_mask = 0xFFFFFFFF  # Check all layers
	var hit: Dictionary = space_state.intersect_ray(params)
	
	if debug_enabled:
		print("Scorch raycast from ", origin, " to ", end)
		print("Hit result: ", hit.has("position"))
	
	if hit and hit.has("position") and hit.has("normal"):
		var hit_pos: Vector3 = hit.position
		var hit_normal: Vector3 = hit.normal.normalized()
		
		var decal: Decal = Decal.new()
		add_child(decal)
		decal.texture_albedo = preload("res://Projectiles/Explosion/scorch_mark.png")
		
		# Size matches blast radius - much larger depth for projection
		decal.size = Vector3(blast_radius, 10.0, blast_radius)  # Much larger depth
		
		# Position the decal slightly above the hit point
		decal.global_position = hit_pos + Vector3(0, 0.1, 0)  # Just 0.1 meter above
		
		# Make decal face straight down (simple approach)
		# Decals project along negative Y, so we want Y pointing up and Z pointing forward
		decal.global_basis = Basis.IDENTITY
		
		# Add random rotation around Y-axis only
		decal.rotate_y(randf() * TAU)
		
		if debug_enabled:
			print("Scorch decal positioned at: ", decal.global_position)
			print("Scorch decal basis: ", decal.global_basis)
			print("Surface normal: ", hit_normal)
	else:
		# Fallback: place a flat decal centered at explosion
		var decal_fallback: Decal = Decal.new()
		add_child(decal_fallback)
		decal_fallback.texture_albedo = preload("res://Projectiles/Explosion/scorch_mark.png")
		decal_fallback.size = Vector3(blast_radius, 10.0, blast_radius)
		decal_fallback.global_position = global_position + Vector3.UP * 0.02
		decal_fallback.rotation.y = randf() * TAU

func deal_explosion_damage():
	"""Deal damage to all physics bodies overlapping a sphere around the explosion."""
	if debug_enabled:
		print("=== EXPLOSION DAMAGE SYSTEM CALLED ===")
		print("Blast radius: ", blast_radius)
		print("Explosion position: ", global_position)
	
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = blast_radius
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), global_position)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	# Explicitly check default layer (1) and a common 'hittable' layer (4)
	params.collision_mask = (1 << 0) | (1 << 3)
	params.exclude = [self]
	
	if debug_enabled:
		print("Shape query parameters:")
		print("  - Position: ", global_position)
		print("  - Radius: ", sphere.radius)
		print("  - Collision mask: ", params.collision_mask)
	
	var results: Array = space_state.intersect_shape(params, 128)
	if debug_enabled:
		print("Overlap hits: ", results.size())
	
	var targets_hit: int = 0
	for hit: Dictionary in results:
		if not hit.has("collider"):
			if debug_enabled:
				print("Hit has no collider")
			continue
		var collider: Object = hit.collider
		if debug_enabled:
			print("Found collider: ", collider.get_class(), " name: ", collider.name if collider.has_method("get_name") else "no name")
		
		if not (collider is Node3D):
			if debug_enabled:
				print("Collider is not Node3D")
			continue
		var target: Node3D = collider as Node3D
		if target == self:
			continue
			
		if debug_enabled:
			print("Checking target: ", target.name)
			print("  - Has take_damage: ", target.has_method("take_damage"))
			print("  - Is RigidBody3D: ", target is RigidBody3D)
			
		if not target.has_method("take_damage") and not (target is RigidBody3D):
			# Skip things that can't take damage and won't receive impulse
			if debug_enabled:
				print("  - Skipping (no take_damage method and not RigidBody3D)")
			continue
		
		var distance: float = global_position.distance_to(target.global_position)
		if distance > blast_radius:
			continue
		
		# Optional line-of-sight check to avoid damaging through walls/terrain
		if use_line_of_sight:
			var ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position, target.global_position)
			ray_params.exclude = [self, target]
			var ray_hit: Dictionary = space_state.intersect_ray(ray_params)
			if ray_hit and ray_hit.has("collider") and ray_hit.collider != target:
				if debug_enabled:
					print("LOS blocked for ", target.name)
				continue
		
		# Damage scales with distance (closer = more)
		var damage_ratio: float = clamp(1.0 - (distance / blast_radius), 0.0, 1.0)
		var damage_amount: float = lerp(min_damage, max_damage, damage_ratio)
		if target.has_method("take_damage"):
			target.take_damage(damage_amount)
			targets_hit += 1
			if debug_enabled:
				print("Hit ", target.name, " dmg=", damage_amount, " dist=", distance)
		
		# Impulse also scales with distance
		if target is RigidBody3D:
			var body: RigidBody3D = target as RigidBody3D
			var direction: Vector3 = (body.global_position - global_position).normalized()
			var impulse_strength: float = lerp(knockback_impulse_at_edge, knockback_impulse_at_center, damage_ratio)
			body.apply_central_impulse(direction * impulse_strength)
			if debug_enabled:
				print("Applied impulse to ", body.name, " strength=", impulse_strength)
	
	if debug_enabled:
		print("Explosion hit ", targets_hit, " targets")
	
	# Create visual blast wave
	create_blast_wave()

func create_blast_wave():
	"""Create a visual blast wave ring to show the damage area"""
	if debug_enabled:
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
