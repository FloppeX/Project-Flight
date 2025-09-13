extends RigidBody3D
class_name EnemyAircraft

@export var max_health: float = 50.0
@export var damage_per_shot: float = 10.0
@export var fire_rate: float = 1.0  # shots per second
@export var bullet_scene: PackedScene
@export var explosion_scene: PackedScene

var current_health: float
var fire_timer: float = 0.0
var target_aircraft: Node3D

signal destroyed(enemy)

func _ready():
	current_health = max_health
	add_to_group("enemies")
	
	# Find the player aircraft
	target_aircraft = get_tree().get_first_node_in_group("aircraft")
	
	# Load bullet scene if not set
	if not bullet_scene:
		bullet_scene = load("res://Projectiles/Bullet/bullet.tscn")
	
	# Load explosion scene if not set
	if not explosion_scene:
		explosion_scene = load("res://Projectiles/Explosion/explosion.tscn")
	
	print("Enemy aircraft created with ", max_health, " HP")

func _process(delta):
	if not target_aircraft or not is_instance_valid(target_aircraft):
		return
	
	# Update fire timer
	fire_timer += delta
	
	# Check if we should fire
	if fire_timer >= (1.0 / fire_rate):
		fire_at_target()
		fire_timer = 0.0

func fire_at_target():
	if not bullet_scene or not target_aircraft:
		return
	
	# Calculate direction to target
	var direction = (target_aircraft.global_position - global_position).normalized()
	
	# Create bullet
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position + direction * 2.0  # Spawn slightly in front
	
	# Fire bullet towards target
	var bullet_velocity = direction * 100.0  # Adjust speed as needed
	bullet.fire(bullet_velocity, self)
	
	print("Enemy fired at aircraft!")

func take_damage(damage_amount: float):
	if current_health <= 0:
		return  # Already destroyed
	
	current_health -= damage_amount
	current_health = max(current_health, 0.0)
	
	print("Enemy aircraft taking damage: ", damage_amount, " HP remaining: ", current_health)
	
	if current_health <= 0:
		explode()

func explode():
	print("Enemy aircraft exploding!")
	emit_signal("destroyed", self)
	
	# Spawn explosion effect
	if explosion_scene:
		var explosion_instance = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion_instance)
		explosion_instance.global_position = global_position
		print("Enemy explosion spawned at: ", global_position)
	
	# Remove the enemy
	queue_free()





