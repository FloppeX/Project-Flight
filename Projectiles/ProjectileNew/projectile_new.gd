extends RigidBody3D
class_name ProjectileNew

@export var damage: float = 10.0
@export var lifetime: float = 5.0
@export var impact_effect: PackedScene  # Explosion/impact visual
@export var creates_explosion: bool = true  # Whether this projectile explodes
@export var explosion_scene: PackedScene  # Reference to explosion scene

var shooter: Node3D  # Reference to whoever fired this
var last_position: Vector3 = Vector3.ZERO
var has_impacted: bool = false

func _ready():
	# IMPORTANT: Enable collision detection
	contact_monitor = true
	max_contacts_reported = 10
	
	# Auto-destroy after lifetime
	get_tree().create_timer(lifetime).timeout.connect(_on_timeout)
	
	# Connect collision detection
	body_entered.connect(_on_body_entered)
	
	# Initialize last position for raycast tunneling detection
	last_position = global_position

func get_child_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null

func _physics_process(delta):
	if has_impacted:
		return
	# Raycast between last position and current position to catch tunneling
	if last_position != Vector3.ZERO:
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(last_position, global_position)
		query.exclude = [self]
		if shooter:
			query.exclude.append(shooter)
		# Use the same collision mask as the projectile
		query.collision_mask = collision_mask
			
		var result: Dictionary = space_state.intersect_ray(query)
		if result and not has_impacted:
			# Move to hit point and trigger collision
			global_position = result.position
			has_impacted = true
			_on_body_entered(result.collider)
			return
	
	last_position = global_position

func fire(initial_velocity: Vector3, firing_aircraft: Node3D):
	shooter = firing_aircraft
	linear_velocity = initial_velocity
	
	# Disable collision with the firing aircraft initially
	if firing_aircraft is RigidBody3D:
		add_collision_exception_with(firing_aircraft)
		
		# Re-enable collision after a short delay (once projectile is clear)
		get_tree().create_timer(0.2).timeout.connect(func(): 
			if firing_aircraft and is_instance_valid(firing_aircraft):
				remove_collision_exception_with(firing_aircraft)
		)

func _on_body_entered(body):
	if has_impacted:
		return
	if body == shooter:
		return  # Don't hit the aircraft that fired us
	
	# DEBUG: Print collision information (can be removed later)
	print("[ProjectileNew] Hit: ", body.name, " (", body.get_class(), ")")
	if body.has_method("take_damage"):
		print("[ProjectileNew] Target has take_damage method - applying ", damage, " damage")
	else:
		print("[ProjectileNew] Target does NOT have take_damage method")
	
	# Mark as impacted immediately to prevent duplicate hits
	has_impacted = true
	
	# Determine if we hit the ground/terrain for scorch mark
	var hit_ground = is_ground_or_terrain(body)
	
	# Create explosion effect
	if creates_explosion and explosion_scene:
		var explosion = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = global_position
		
		# Create scorch mark if we hit the ground
		if hit_ground:
			explosion.create_scorch_mark()
	
	# Fallback to old impact effect if no explosion
	elif impact_effect:
		var effect = impact_effect.instantiate()
		get_tree().current_scene.add_child(effect)
		effect.global_position = global_position
	
	# Play impact sound
	play_impact_sound(body)
	
	# Create scorch mark if we hit an aircraft
	if is_aircraft(body):
		create_bullet_scorch_mark(body)
	
	# Apply damage if target has health
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	print("[ProjectileNew] Bullet destroyed after hitting ", body.name)
	queue_free()

func play_impact_sound(body: Node) -> void:
	# Create 3D audio player for impact sound
	var audio_player = AudioStreamPlayer3D.new()
	get_tree().current_scene.add_child(audio_player)
	audio_player.global_position = global_position
	
	# Determine appropriate sound based on what we hit
	var sound_path: String = ""
	
	if is_aircraft(body):
		# Aircraft hit - use metal impact sounds
		var metal_sounds = [
			"res://Sounds/bullet_impact_metal_heavy_01.wav",
			"res://Sounds/bullet_impact_metal_heavy_02.wav",
			"res://Sounds/bullet_impact_metal_heavy_03.wav",
			"res://Sounds/bullet_impact_metal_heavy_04.wav",
			"res://Sounds/bullet_impact_metal_heavy_05.wav",
			"res://Sounds/bullet_impact_metal_heavy_06.wav",
			"res://Sounds/bullet_impact_metal_heavy_07.wav",
			"res://Sounds/bullet_impact_metal_heavy_08.wav"
		]
		sound_path = metal_sounds[randi() % metal_sounds.size()]
	elif is_ground_or_terrain(body):
		# Ground/terrain hit - use dirt impact sounds
		var dirt_sounds = [
			"res://Sounds/bullet_impact_dirt_01.wav",
			"res://Sounds/bullet_impact_dirt_02.wav",
			"res://Sounds/bullet_impact_dirt_03.wav",
			"res://Sounds/bullet_impact_dirt_04.wav",
			"res://Sounds/bullet_impact_dirt_05.wav",
			"res://Sounds/bullet_impact_dirt_06.wav",
			"res://Sounds/bullet_impact_dirt_07.wav",
			"res://Sounds/bullet_impact_dirt_08.wav"
		]
		sound_path = dirt_sounds[randi() % dirt_sounds.size()]
	else:
		# Default to metal sound for other objects
		sound_path = "res://Sounds/bullet_impact_metal_heavy_01.wav"
	
	# Load and play the sound
	var sound = load(sound_path)
	if sound:
		audio_player.stream = sound
		audio_player.volume_db = -5.0  # Slightly quieter than default
		audio_player.pitch_scale = randf_range(0.9, 1.1)  # Slight pitch variation
		audio_player.play()
		
		# Clean up audio player after sound finishes
		audio_player.finished.connect(func(): audio_player.queue_free())
		# Fallback cleanup in case finished signal doesn't fire
		get_tree().create_timer(3.0).timeout.connect(func(): 
			if audio_player and is_instance_valid(audio_player):
				audio_player.queue_free()
		)

func create_bullet_scorch_mark(aircraft_body: Node) -> void:
	# Create a bullet scorch mark on the aircraft surface
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var impact_dir: Vector3 = linear_velocity.normalized()
	if impact_dir == Vector3.ZERO:
		impact_dir = Vector3.FORWARD
	
	# Cast a ray to get precise impact point and surface normal
	var from: Vector3 = global_position - impact_dir * 1.0
	var to: Vector3 = global_position + impact_dir * 0.5
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	if shooter:
		params.exclude.append(shooter)
	
	var hit: Dictionary = space_state.intersect_ray(params)
	var hit_pos: Vector3 = global_position
	var hit_normal: Vector3 = -impact_dir
	
	if hit and hit.has("position") and hit.has("normal"):
		hit_pos = hit.position
		hit_normal = (hit.normal as Vector3).normalized()
	
	# Create bullet scorch decal
	var decal: Decal = Decal.new()
	decal.texture_albedo = load("res://Projectiles/Explosion/scorch_mark.png")
	
	# Make bullet marks smaller than explosion marks
	decal.size = Vector3(0.3, 0.02, 0.3)  # Small bullet hole
	decal.global_position = hit_pos + hit_normal * 0.005  # Slight offset to avoid z-fighting
	
	# Align decal to surface normal
	var y_axis: Vector3 = hit_normal
	var x_axis: Vector3 = y_axis.cross(Vector3.FORWARD)
	if x_axis.length() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	var basis: Basis = Basis(x_axis, y_axis, z_axis)
	
	# Add some random rotation for variation
	var random_yaw: float = randf() * TAU
	var rot: Basis = Basis(y_axis, random_yaw)
	decal.global_basis = rot * basis
	
	# Make the scorch mark darker/more visible
	decal.modulate = Color(0.8, 0.8, 0.8, 1.0)  # Slightly darker
	
	# Attach decal to the aircraft so it moves with it
	if aircraft_body and is_instance_valid(aircraft_body):
		aircraft_body.add_child(decal)
		print("[ProjectileNew] Added bullet scorch mark to aircraft")
	else:
		# Fallback: add to scene
		get_tree().current_scene.add_child(decal)
		print("[ProjectileNew] Added bullet scorch mark to scene (fallback)")

func is_aircraft(body: Node) -> bool:
	# Check if the body is an aircraft
	if body.name == "Aircraft" or "aircraft" in body.name.to_lower():
		return true
	if body.is_in_group("aircraft"):
		return true
	if body is Aircraft:
		return true
	return false

func is_ground_or_terrain(body: Node) -> bool:
	# Don't consider the Aircraft as terrain
	if body.name == "Aircraft" or "aircraft" in body.name.to_lower():
		return false
	
	# Check for Terrain3D plugin
	if body.get_class() == "Terrain3D" or "terrain3d" in body.name.to_lower():
		return true
	
	# Check for groups
	if body.is_in_group("terrain") or body.is_in_group("ground"):
		return true
	
	# Check by name
	if "ground" in body.name.to_lower() or "terrain" in body.name.to_lower():
		return true
	
	# Check if it's a StaticBody3D (typical for terrain)
	if body is StaticBody3D:
		return true
	
	# Assume anything that's not the aircraft is terrain
	if body != shooter:
		return true
	
	return false

func _on_timeout():
	print("[ProjectileNew] Bullet destroyed by timeout after ", lifetime, " seconds")
	queue_free()
