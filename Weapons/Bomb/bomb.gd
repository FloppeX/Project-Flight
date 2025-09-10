extends Weapon
class_name Bomb

@export var bomb_projectile_scene: PackedScene
@export var drop_force: float = 0.0
@export var blast_radius: float = 10.0
@export var fire_cooldown: float = 0.5  # Minimum time between bomb drops

var hardpoint: Hardpoint
var last_fire_time: float = 0.0

func _ready():
	delete_when_empty = true
	hardpoint = get_parent() as Hardpoint
	automatic_fire = false  # Bombs are single-shot weapons
	ammo_count = 50
	weapon_name = "Bomb"  # Set weapon type name

func can_fire() -> bool:
	# Check ammo and cooldown
	var current_time = Time.get_ticks_msec() / 1000.0
	return ammo_count > 0 and (current_time - last_fire_time) >= fire_cooldown

func fire() -> bool:
	if not can_fire():
		return false
	
	# Update last fire time
	last_fire_time = Time.get_ticks_msec() / 1000.0
	
	# Create and drop bomb projectile
	var bomb_projectile = bomb_projectile_scene.instantiate()
	get_tree().current_scene.add_child(bomb_projectile)
	
	# Set position to bomb's current position
	bomb_projectile.global_position = global_position
	
	# Set bomb rotation to match hardpoint forward direction
	if hardpoint:
		var forward_dir = hardpoint.get_hardpoint_forward_direction()
		bomb_projectile.look_at(global_position + forward_dir, Vector3.UP)
	
	# Get the aircraft from the hardpoint (parent)
	var aircraft = get_parent()
	while aircraft and not (aircraft is RigidBody3D):
		aircraft = aircraft.get_parent()
	
	# Calculate drop velocity - inherit aircraft velocity for realistic ballistics
	var aircraft_velocity = aircraft.linear_velocity if aircraft else Vector3.ZERO
	var drop_velocity = Vector3.DOWN * drop_force + aircraft_velocity
	
	# Use the projectile's fire method
	bomb_projectile.fire(drop_velocity, aircraft)
	
	ammo_count -= 1
	
	# Self-destruct if enabled and empty
	if delete_when_empty and ammo_count <= 0:
		queue_free()
	
	return true
