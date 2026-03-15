extends RigidBody3D
class_name ProjectileNew

@export var damage: float = 10.0
@export var lifetime: float = 5.0
@export var impact_effect: PackedScene  # Explosion/impact visual
@export var creates_explosion: bool = true  # Whether this projectile explodes
@export var explosion_scene: PackedScene  # Reference to explosion scene
@export var target_mark_lifetime_s: float = 12.0
@export var target_mark_size: Vector3 = Vector3(0.3, 2.0, 0.3)

var shooter: Node3D  # Reference to whoever fired this
var last_position: Vector3 = Vector3.ZERO
var has_impacted: bool = false
var _terrain_node: Node = null

func _ready():
	mass = 0.01
	gravity_scale = maxf(gravity_scale, 0.0)
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.0
	physics_material_override.friction = 0.0
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
		# Use all layers so projectile collision works with project-specific Terrain3D setup.
		query.collision_mask = 0xFFFFFFFF
			
		var result: Dictionary = space_state.intersect_ray(query)
		if result and not has_impacted:
			global_position = result.position
			# Call _on_body_entered BEFORE setting has_impacted to avoid early return
			_on_body_entered(result.collider)
			return
		# Fallback for Terrain3D setups where physics collider/raycast may miss:
		# detect if the projectile segment crossed below terrain height data.
		var terrain := _get_cached_terrain_node()
		if terrain:
			var h_prev: float = _get_terrain_height_at_position(last_position)
			var h_curr: float = _get_terrain_height_at_position(global_position)
			if not is_nan(h_prev) and not is_nan(h_curr):
				var prev_above: bool = last_position.y >= h_prev
				var curr_above: bool = global_position.y >= h_curr
				if (not curr_above) or (prev_above and not curr_above):
					# Clamp to terrain surface and trigger impact.
					global_position.y = h_curr + 0.02
					_on_body_entered(terrain)
					return
	
	last_position = global_position

func fire(initial_velocity: Vector3, firing_aircraft: Node3D):
	shooter = firing_aircraft
	linear_velocity = initial_velocity
	
	# Disable collision with the firing entity initially.
	# Ground vehicles are CharacterBody3D, not RigidBody3D, and turret bullets can
	# otherwise spawn inside the host collider and die immediately.
	if firing_aircraft and firing_aircraft is CollisionObject3D:
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
		return

	var damage_target = find_damage_target(body)
	
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
	
	if damage_target and _supports_target_hit_mark(damage_target):
		create_bullet_scorch_mark(damage_target)
	
	# Apply damage if target has health
	if damage_target and damage_target.has_method("take_damage"):
		damage_target.take_damage(damage)
	queue_free()

func _get_cached_terrain_node() -> Node:
	if _terrain_node and is_instance_valid(_terrain_node):
		return _terrain_node
	var tagged: Node = get_tree().get_first_node_in_group("terrain_provider")
	if tagged and is_instance_valid(tagged):
		_terrain_node = tagged
		return _terrain_node
	var root: Node = get_tree().current_scene
	if not root:
		return null
	var queue: Array = [root]
	while queue.size() > 0:
		var cur: Node = queue.pop_front()
		if cur.get_class() == "Terrain3D":
			_terrain_node = cur
			return _terrain_node
		if cur is Node3D and cur.has_method("get_height"):
			_terrain_node = cur
			return _terrain_node
		for child in cur.get_children():
			queue.append(child)
	return null

func _get_terrain_height_at_position(world_pos: Vector3) -> float:
	var terrain: Node = _get_cached_terrain_node()
	if not terrain:
		return NAN
	if terrain.has_method("get_height"):
		var h = terrain.get_height(world_pos)
		if typeof(h) == TYPE_FLOAT and not is_nan(float(h)):
			return float(h)
	if "data" in terrain and terrain.data and terrain.data.has_method("get_height"):
		var h2 = terrain.data.get_height(world_pos)
		if typeof(h2) == TYPE_FLOAT and not is_nan(float(h2)):
			return float(h2)
	return NAN

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
			"res://Audio/bullet_impact_metal_heavy_01.wav",
			"res://Audio/bullet_impact_metal_heavy_02.wav",
			"res://Audio/bullet_impact_metal_heavy_03.wav",
			"res://Audio/bullet_impact_metal_heavy_04.wav",
			"res://Audio/bullet_impact_metal_heavy_05.wav",
			"res://Audio/bullet_impact_metal_heavy_06.wav",
			"res://Audio/bullet_impact_metal_heavy_07.wav",
			"res://Audio/bullet_impact_metal_heavy_08.wav"
		]
		sound_path = metal_sounds[randi() % metal_sounds.size()]
	elif is_ground_or_terrain(body):
		# Ground/terrain hit - use dirt impact sounds
		var dirt_sounds = [
			"res://Audio/bullet_impact_dirt_01.wav",
			"res://Audio/bullet_impact_dirt_02.wav",
			"res://Audio/bullet_impact_dirt_03.wav",
			"res://Audio/bullet_impact_dirt_04.wav",
			"res://Audio/bullet_impact_dirt_05.wav",
			"res://Audio/bullet_impact_dirt_06.wav",
			"res://Audio/bullet_impact_dirt_07.wav",
			"res://Audio/bullet_impact_dirt_08.wav"
		]
		sound_path = dirt_sounds[randi() % dirt_sounds.size()]
	else:
		# Default to metal sound for other objects
		sound_path = "res://Audio/bullet_impact_metal_heavy_01.wav"
	
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
	
	# Make bullet marks smaller than explosion marks, but with enough depth to project onto moving meshes.
	decal.size = target_mark_size
	
	# Position the decal slightly above the hit point
	decal.global_position = hit_pos + Vector3(0, 0.05, 0)  # Just 0.05 meters above
	
	# Make decal face straight down (simple approach)
	# Decals project along negative Y, so we want Y pointing up and Z pointing forward
	decal.global_basis = Basis.IDENTITY
	
	# Add random rotation around Y-axis only
	decal.rotate_y(randf() * TAU)
	
	decal.modulate = Color(0.8, 0.8, 0.8, 1.0)
	if aircraft_body and is_instance_valid(aircraft_body):
		aircraft_body.add_child(decal)
	else:
		get_tree().current_scene.add_child(decal)

	if target_mark_lifetime_s > 0.0:
		get_tree().create_timer(target_mark_lifetime_s).timeout.connect(func():
			if is_instance_valid(decal):
				decal.queue_free()
		)

func _supports_target_hit_mark(target: Node) -> bool:
	if not target or not is_instance_valid(target):
		return false
	if is_aircraft(target):
		return true
	if target.is_in_group("ground_vehicles"):
		return true
	return false

func find_damage_target(body: Node) -> Node:
	if body.has_method("take_damage"):
		return body
	if body is CollisionShape3D and body.get_parent() and body.get_parent().has_method("take_damage"):
		return body.get_parent()
	var node: Node = body
	while node:
		if node != body and node.has_method("take_damage"):
			return node
		node = node.get_parent()
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
	queue_free()
