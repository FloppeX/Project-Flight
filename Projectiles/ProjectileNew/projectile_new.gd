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
			print("[ProjectileNew] RAYCAST hit detected: ", result.collider.name, " (", result.collider.get_class(), ")")
			print("[ProjectileNew] RAYCAST collider parent: ", result.collider.get_parent().name if result.collider.get_parent() else "no parent")
			print("[ProjectileNew] Hit position: ", result.position)
			print("[ProjectileNew] Hit normal: ", result.normal)
			
			# Check if this is a collision shape and what RigidBody it belongs to
			if result.collider is CollisionShape3D:
				var rigid_body = result.collider.get_parent()
				print("[ProjectileNew] CollisionShape3D belongs to RigidBody: ", rigid_body.name if rigid_body else "none", " (", rigid_body.get_class() if rigid_body else "none", ")")
			
			global_position = result.position
			# Call _on_body_entered BEFORE setting has_impacted to avoid early return
			_on_body_entered(result.collider)
			return
	
	last_position = global_position

func fire(initial_velocity: Vector3, firing_aircraft: Node3D):
	shooter = firing_aircraft
	linear_velocity = initial_velocity
	
	print("[ProjectileNew] Fired by: ", firing_aircraft.name if firing_aircraft else "null", " (", firing_aircraft.get_class() if firing_aircraft else "null", ")")
	
	# Disable collision with the firing aircraft initially
	if firing_aircraft and firing_aircraft is RigidBody3D:
		print("[ProjectileNew] Adding collision exception with RigidBody3D shooter: ", firing_aircraft.name)
		add_collision_exception_with(firing_aircraft)
		
		# Re-enable collision after a short delay (once projectile is clear)
		get_tree().create_timer(0.2).timeout.connect(func(): 
			if firing_aircraft and is_instance_valid(firing_aircraft):
				print("[ProjectileNew] Removing collision exception with: ", firing_aircraft.name)
				remove_collision_exception_with(firing_aircraft)
		)
	else:
		print("[ProjectileNew] No collision exception added - shooter is ", firing_aircraft.get_class() if firing_aircraft else "null", " not RigidBody3D")

func _on_body_entered(body):
	if has_impacted:
		print("[ProjectileNew] BODY_ENTERED ignored - already impacted")
		return
	if body == shooter:
		print("[ProjectileNew] BODY_ENTERED ignored - hit shooter: ", body.name, " (shooter is: ", shooter.name if shooter else "null", ")")
		return  # Don't hit the aircraft that fired us
	
	# DEBUG: Print collision information (can be removed later)
	print("[ProjectileNew] BODY_ENTERED hit: ", body.name, " (", body.get_class(), ")")
	print("[ProjectileNew] Hit node parent: ", body.get_parent().name if body.get_parent() else "no parent", " (", body.get_parent().get_class() if body.get_parent() else "no parent", ")")
	
	# Check if this is a mesh collision vs designed collision shape
	if body is StaticBody3D:
		print("[ProjectileNew] WARNING: Hit StaticBody3D - this might be auto-generated mesh collision!")
	elif body is RigidBody3D:
		print("[ProjectileNew] Hit RigidBody3D - this should be the aircraft")
	elif body is CollisionShape3D:
		print("[ProjectileNew] Hit CollisionShape3D directly - unusual!")
	
	if body.has_method("take_damage"):
		print("[ProjectileNew] Target has take_damage method - applying ", damage, " damage")
	elif body.get_parent() and body.get_parent().has_method("take_damage"):
		print("[ProjectileNew] Target's PARENT has take_damage method - applying ", damage, " damage to parent")
		body.get_parent().take_damage(damage)
		return  # Don't continue with normal damage logic
	else:
		print("[ProjectileNew] Target does NOT have take_damage method (neither target nor parent)")
	
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
		var aircraft_target = find_damage_target(body)  # Get the main aircraft node
		if aircraft_target:
			create_bullet_scorch_mark(aircraft_target)
		else:
			create_bullet_scorch_mark(body)  # Fallback to original body
	
	# Apply damage if target has health
	var damage_target = find_damage_target(body)
	
	if damage_target and damage_target.has_method("take_damage"):
		damage_target.take_damage(damage)
		print("[ProjectileNew] Applied ", damage, " damage to ", damage_target.name)
	else:
		print("[ProjectileNew] No take_damage method found on target, parent, or aircraft children")
	
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
	
	# Make bullet marks smaller than explosion marks - much larger depth
	decal.size = Vector3(0.3, 2.0, 0.3)  # Much larger depth for projection
	
	# Position the decal slightly above the hit point
	decal.global_position = hit_pos + Vector3(0, 0.05, 0)  # Just 0.05 meters above
	
	# Make decal face straight down (simple approach)
	# Decals project along negative Y, so we want Y pointing up and Z pointing forward
	decal.global_basis = Basis.IDENTITY
	
	# Add random rotation around Y-axis only
	decal.rotate_y(randf() * TAU)
	
	print("[ProjectileNew] Bullet decal positioned at: ", decal.global_position)
	print("[ProjectileNew] Bullet decal basis: ", decal.global_basis)
	print("[ProjectileNew] Surface normal: ", hit_normal)
	
	# Make the scorch mark darker/more visible
	decal.modulate = Color(0.8, 0.8, 0.8, 1.0)  # Slightly darker
	
	# Attach decal to the aircraft so it moves with it
	if aircraft_body and is_instance_valid(aircraft_body):
		aircraft_body.add_child(decal)
		print("[ProjectileNew] Added bullet scorch mark to aircraft: ", aircraft_body.name, " (", aircraft_body.get_class(), ")")
		print("[ProjectileNew] Decal world position: ", decal.global_position)
		print("[ProjectileNew] Aircraft world position: ", aircraft_body.global_position)
	else:
		# Fallback: add to scene
		get_tree().current_scene.add_child(decal)
		print("[ProjectileNew] Added bullet scorch mark to scene (fallback) - aircraft_body was: ", aircraft_body)

func find_damage_target(body: Node) -> Node:
	# Smart damage target finder - handles various collision scenarios
	print("[ProjectileNew] Looking for damage target on: ", body.name, " (", body.get_class(), ")")
	
	# 1. Check if the body itself has take_damage
	if body.has_method("take_damage"):
		print("[ProjectileNew] Found take_damage on hit body: ", body.name)
		return body
	
	# 2. If we hit a CollisionShape3D, check its parent
	if body is CollisionShape3D and body.get_parent() and body.get_parent().has_method("take_damage"):
		print("[ProjectileNew] Found take_damage on CollisionShape3D parent: ", body.get_parent().name)
		return body.get_parent()
	
	# 3. If we hit a scene root (like CompleteFighterJet), search for Aircraft child
	if body.name == "CompleteFighterJet" or "aircraft" in body.name.to_lower():
		# Search children for Aircraft RigidBody3D
		for child in body.get_children():
			if child.has_method("take_damage") and (child is Aircraft or child.is_in_group("aircraft")):
				print("[ProjectileNew] Found Aircraft child with take_damage: ", child.name)
				return child
		
		# If no direct child, search recursively
		var aircraft_nodes = body.find_children("*", "Aircraft", true, false)
		for aircraft in aircraft_nodes:
			if aircraft.has_method("take_damage"):
				print("[ProjectileNew] Found Aircraft descendant with take_damage: ", aircraft.name)
				return aircraft
	
	# 4. Last resort - search for any node with take_damage in the vicinity
	var parent = body.get_parent()
	if parent:
		for sibling in parent.get_children():
			if sibling.has_method("take_damage") and (sibling is Aircraft or sibling.is_in_group("aircraft")):
				print("[ProjectileNew] Found Aircraft sibling with take_damage: ", sibling.name)
				return sibling
	
	print("[ProjectileNew] Could not find damage target for: ", body.name)
	return null

func is_aircraft(body: Node) -> bool:
	# Check if the body is an aircraft
	var target = body
	
	# If we hit a CollisionShape3D, check its parent
	if body is CollisionShape3D and body.get_parent():
		target = body.get_parent()
	
	if target.name == "Aircraft" or "aircraft" in target.name.to_lower():
		return true
	if target.is_in_group("aircraft"):
		return true
	if target is Aircraft:
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
