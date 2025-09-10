extends RigidBody3D
class_name EnemyBox

signal destroyed(enemy)

@export var max_health: float = 50.0
@export var explosion_scene: PackedScene
@export var detection_range: float = 500.0
@export var team: int = 2
@export var turret_range: float = 400.0
@export var fire_rate: float = 2.0  # shots per second
@export var bullet_speed: float = 200.0  # m/s
@export var bullet_scene: PackedScene

var current_health: float
var detected_enemies: Array = []
var original_material: StandardMaterial3D
var blink_timer: float = 0.0
var is_blinking: bool = false
var turret_node: Node3D
var fire_timer: float = 0.0
var current_target: Node3D

func _ready():
	# Initialize health
	current_health = max_health
	
	# Add to enemy group for targeting
	add_to_group("enemies")
	add_to_group("team_" + str(team))
	
	# Store original material for blinking
	var mesh_instance = get_node("MeshInstance3D")
	if mesh_instance and mesh_instance.material_override:
		original_material = mesh_instance.material_override.duplicate()
	
	# Create turret
	create_turret()
	
	# Load bullet scene if not set
	if not bullet_scene:
		bullet_scene = load("res://Projectiles/Bullet/bullet.tscn")
	
	# Configure physics for better ground settling
	gravity_scale = 1.0
	linear_damp = 0.5  # Add some damping to help settling
	angular_damp = 0.5
	
	print("Enemy box created with ", max_health, " HP at position: ", global_position, " (Team ", team, ")")

func _physics_process(delta):
	# Help the box settle on the ground by reducing bouncing
	if linear_velocity.length() < 0.1 and angular_velocity.length() < 0.1:
		# If barely moving, increase damping to help it settle
		linear_damp = 2.0
		angular_damp = 2.0
	
	# Detection and blinking
	detect_enemies()
	update_blinking(delta)
	
	# Turret combat
	update_turret(delta)

func take_damage(damage_amount: float):
	if current_health <= 0:
		return  # Already destroyed
	
	print("Enemy box taking damage: ", damage_amount, " HP remaining: ", current_health - damage_amount)
	
	current_health -= damage_amount
	current_health = max(current_health, 0.0)
	
	if current_health <= 0:
		explode()

func explode():
	print("Enemy box exploding!")
	emit_signal("destroyed", self)
	
	# Spawn explosion effect
	var explosion_scene_resource = load("res://Projectiles/Explosion/explosion.tscn")
	if explosion_scene_resource:
		var explosion_instance = explosion_scene_resource.instantiate()
		get_parent().add_child(explosion_instance)
		explosion_instance.global_position = global_position
		print("Enemy explosion spawned at: ", global_position)
	
	# Remove the enemy
	queue_free()

func detect_enemies():
	# Find all enemies from other teams within detection range
	var enemies_in_range = []
	
	# Check aircraft group (player)
	var aircraft = get_tree().get_first_node_in_group("aircraft")
	if aircraft and aircraft.has_method("get_team") and aircraft.get_team() != team:
		var distance = global_position.distance_to(aircraft.global_position)
		if distance <= detection_range:
			enemies_in_range.append(aircraft)
	
	# Check other enemies group
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in all_enemies:
		if enemy == self:
			continue
		
		# Check if enemy is from different team
		if enemy.has_method("get_team") and enemy.get_team() != team:
			var distance = global_position.distance_to(enemy.global_position)
			if distance <= detection_range:
				enemies_in_range.append(enemy)
	
	# Update detection state
	if enemies_in_range.size() > 0 and not is_blinking:
		is_blinking = true
		print("Enemy detected! Distance: ", global_position.distance_to(enemies_in_range[0].global_position))
	elif enemies_in_range.size() == 0 and is_blinking:
		is_blinking = false
		print("No enemies in range")
	
	detected_enemies = enemies_in_range

func update_blinking(delta):
	if not is_blinking:
		# Reset to original color
		var mesh_instance = get_node("MeshInstance3D")
		if mesh_instance and original_material:
			mesh_instance.material_override = original_material
		return
	
	# Blink between red and yellow when detecting enemies
	blink_timer += delta
	var mesh_instance = get_node("MeshInstance3D")
	if mesh_instance and original_material:
		var blink_material = original_material.duplicate()
		
		if int(blink_timer * 4) % 2 == 0:  # Blink 4 times per second
			blink_material.albedo_color = Color.RED
			blink_material.emission = Color.RED
		else:
			blink_material.albedo_color = Color.YELLOW
			blink_material.emission = Color.YELLOW
		
		mesh_instance.material_override = blink_material

func get_team() -> int:
	return team

func create_turret():
	# Create turret node
	turret_node = Node3D.new()
	turret_node.name = "Turret"
	add_child(turret_node)
	
	# Position turret on top of the box
	turret_node.position = Vector3(0, 1.5, 0)  # 1.5m above center (box is 2m tall)
	
	# Create turret barrel (simple cylinder)
	var barrel_mesh = CylinderMesh.new()
	barrel_mesh.height = 2.0
	barrel_mesh.top_radius = 0.1
	barrel_mesh.bottom_radius = 0.1
	
	var barrel_instance = MeshInstance3D.new()
	barrel_instance.name = "Barrel"
	barrel_instance.mesh = barrel_mesh
	turret_node.add_child(barrel_instance)
	
	# Create turret material (dark gray)
	var turret_material = StandardMaterial3D.new()
	turret_material.albedo_color = Color(0.3, 0.3, 0.3, 1)
	barrel_instance.material_override = turret_material
	
	# Position barrel pointing forward
	barrel_instance.position = Vector3(0, 0, 1.0)  # 1m forward from turret center
	barrel_instance.rotation_degrees = Vector3(90, 0, 0)  # Rotate to point forward

func update_turret(delta):
	if not turret_node:
		return
	
	# Update fire timer
	fire_timer += delta
	
	# Find best target within turret range
	var best_target = find_best_target()
	
	if best_target:
		current_target = best_target
		
		# Track target
		track_target(best_target)
		
		# Fire if ready and in range
		if fire_timer >= (1.0 / fire_rate):
			fire_at_target(best_target)
			fire_timer = 0.0
	else:
		current_target = null

func find_best_target() -> Node3D:
	var best_target: Node3D = null
	var best_distance = turret_range
	
	# Check aircraft
	var aircraft = get_tree().get_first_node_in_group("aircraft")
	if aircraft and aircraft.has_method("get_team") and aircraft.get_team() != team:
		var distance = global_position.distance_to(aircraft.global_position)
		if distance <= turret_range and distance < best_distance:
			best_target = aircraft
			best_distance = distance
	
	# Check other enemies
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in all_enemies:
		if enemy == self:
			continue
		
		if enemy.has_method("get_team") and enemy.get_team() != team:
			var distance = global_position.distance_to(enemy.global_position)
			if distance <= turret_range and distance < best_distance:
				best_target = enemy
				best_distance = distance
	
	return best_target

func track_target(target: Node3D):
	if not target or not turret_node:
		return
	
	# Calculate target position with lead
	var target_pos = calculate_lead_position(target)
	
	# Point turret at target
	var direction = (target_pos - turret_node.global_position).normalized()
	if direction.length() > 0:
		# Calculate rotation to look at target
		var look_at_pos = turret_node.global_position + direction
		turret_node.look_at(look_at_pos, Vector3.UP)

func calculate_lead_position(target: Node3D) -> Vector3:
	# Get target position and velocity
	var target_pos = target.global_position
	var target_velocity = Vector3.ZERO
	
	# Try to get target velocity
	if target.has_method("get_linear_velocity"):
		target_velocity = target.get_linear_velocity()
	elif target.has_method("linear_velocity"):
		target_velocity = target.linear_velocity
	
	# Calculate time to intercept
	var distance = global_position.distance_to(target_pos)
	var time_to_target = distance / bullet_speed
	
	# Predict target position
	var lead_position = target_pos + (target_velocity * time_to_target)
	
	return lead_position

func fire_at_target(target: Node3D):
	if not bullet_scene or not turret_node:
		return
	
	# Create bullet
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	
	# Position bullet at turret barrel tip
	var barrel_tip = turret_node.global_position + turret_node.global_transform.basis.z * 1.0
	bullet.global_position = barrel_tip
	
	# Calculate firing direction with lead
	var target_pos = calculate_lead_position(target)
	var fire_direction = (target_pos - barrel_tip).normalized()
	var bullet_velocity = fire_direction * bullet_speed
	
	# Fire bullet
	bullet.fire(bullet_velocity, self)
	
	print("Turret fired at target! Distance: ", global_position.distance_to(target.global_position))
