extends RigidBody3D
class_name ProjectileNew

@export var damage: float = 10.0
@export var lifetime: float = 5.0
@export var impact_effect: PackedScene  # Explosion/impact visual
@export var creates_explosion: bool = true  # Whether this projectile explodes
@export var explosion_scene: PackedScene  # Reference to explosion scene

var shooter: Node3D  # Reference to whoever fired this
var last_position: Vector3 = Vector3.ZERO

func _ready():
	print("Projectile created at: ", global_position)
	print("Shooter: ", shooter)
	print("Creates explosion: ", creates_explosion)
	
	# IMPORTANT: Enable collision detection
	contact_monitor = true
	max_contacts_reported = 10
	
	print("Contact monitor enabled: ", contact_monitor)
	print("Max contacts: ", max_contacts_reported)
	
	# Auto-destroy after lifetime
	get_tree().create_timer(lifetime).timeout.connect(_on_timeout)
	
	# Connect collision detection
	body_entered.connect(_on_body_entered)
	
	# Debug: Check if we have collision shape
	var collision_shape = get_child_collision_shape()
	if collision_shape:
		print("Collision shape found: ", collision_shape.shape)
	else:
		print("ERROR: No collision shape found!")
	
	# Initialize last position for raycast tunneling detection
	last_position = global_position

func get_child_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null

func _physics_process(delta):
	# Raycast between last position and current position to catch tunneling
	if last_position != Vector3.ZERO:
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(last_position, global_position)
		query.exclude = [self]
		if shooter:
			query.exclude.append(shooter)
			
		var result = space_state.intersect_ray(query)
		if result:
			print("Raycast caught tunneling! Hit: ", result.collider.name)
			# Move to hit point and trigger collision
			global_position = result.position
			_on_body_entered(result.collider)
			return
	
	last_position = global_position

func fire(initial_velocity: Vector3, firing_aircraft: Node3D):
	print("Firing projectile with velocity: ", initial_velocity)
	print("From aircraft: ", firing_aircraft.name if firing_aircraft else "NULL")
	
	shooter = firing_aircraft
	linear_velocity = initial_velocity  # Use the velocity as provided - don't add more!
	
	print("Final projectile velocity: ", linear_velocity)
	
	# Disable collision with the firing aircraft initially
	if firing_aircraft is RigidBody3D:
		print("Adding collision exception with aircraft")
		add_collision_exception_with(firing_aircraft)
		
		# Re-enable collision after a short delay (once projectile is clear)
		get_tree().create_timer(0.2).timeout.connect(func(): 
			print("Re-enabling collision with aircraft")
			if firing_aircraft and is_instance_valid(firing_aircraft):
				remove_collision_exception_with(firing_aircraft)
		)

func _on_body_entered(body):
	print("Projectile hit: ", body.name, " (Type: ", body.get_class(), ")")
	print("Shooter is: ", shooter.name if shooter else "NULL")
	print("Is same as shooter? ", body == shooter)
	
	if body == shooter:
		print("Ignoring collision with shooter")
		return  # Don't hit the aircraft that fired us
	
	# Determine if we hit the ground/terrain for scorch mark
	var hit_ground = is_ground_or_terrain(body)
	print("Hit ground/terrain: ", hit_ground)
	
	# Create explosion effect
	if creates_explosion and explosion_scene:
		print("Creating explosion at: ", global_position)
		var explosion = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = global_position
		
		# Create scorch mark if we hit the ground
		if hit_ground:
			print("Creating scorch mark")
			explosion.create_scorch_mark()
	elif creates_explosion and not explosion_scene:
		print("ERROR: creates_explosion is true but no explosion_scene assigned!")
	
	# Fallback to old impact effect if no explosion
	elif impact_effect:
		print("Creating old-style impact effect")
		var effect = impact_effect.instantiate()
		get_tree().current_scene.add_child(effect)
		effect.global_position = global_position
	
	# Apply damage if target has health
	if body.has_method("take_damage"):
		print("Applying damage to: ", body.name)
		body.take_damage(damage)
	
	print("Destroying projectile")
	queue_free()

func is_ground_or_terrain(body: Node) -> bool:
	print("Checking if ground - Body: ", body.name, " Groups: ", body.get_groups())
	print("Body type: ", body.get_class())
	print("Body is Aircraft? ", body.name == "Aircraft")
	
	# Don't consider the Aircraft as terrain
	if body.name == "Aircraft" or "aircraft" in body.name.to_lower():
		print("Identified as aircraft - not terrain")
		return false
	
	# Check for Terrain3D plugin
	if body.get_class() == "Terrain3D" or "terrain3d" in body.name.to_lower():
		print("Found Terrain3D - is terrain")
		return true
	
	# Check for groups
	if body.is_in_group("terrain") or body.is_in_group("ground"):
		print("Found terrain/ground by group")
		return true
	
	# Check by name
	if "ground" in body.name.to_lower() or "terrain" in body.name.to_lower():
		print("Found terrain/ground by name")
		return true
	
	# Check if it's a StaticBody3D (typical for terrain)
	if body is StaticBody3D:
		print("Found StaticBody3D - assuming terrain")
		return true
	
	# For debugging, let's see what class the ground actually is
	print("Unknown body class: ", body.get_class())
	
	# For now, assume anything that's not the aircraft is terrain
	# You can refine this based on your scene setup
	if body != shooter:
		print("Unknown body type - assuming terrain for now")
		return true
	
	print("Not recognized as terrain")
	return false

func _on_timeout():
	print("Projectile timed out and destroyed")
	queue_free()
