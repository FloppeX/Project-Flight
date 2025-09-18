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
	
	# Apply damage if target has health
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	queue_free()

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
