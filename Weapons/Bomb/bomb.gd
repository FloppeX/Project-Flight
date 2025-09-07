extends Weapon
class_name Bomb

@export var bomb_projectile_scene: PackedScene
@export var drop_force: float = 0.0
@export var blast_radius: float = 10.0

var hardpoint: Hardpoint

func _ready():
	delete_when_empty = true
	hardpoint = get_parent() as Hardpoint
	var automatic_fire = false 
	var ammo_count: int = 5

func fire() -> bool:
	print("=== BOMB FIRE CALLED ===")
	
	if not can_fire():
		return false
	
	print("Creating bomb projectile...")
	# Create and drop bomb projectile
	var bomb_projectile = bomb_projectile_scene.instantiate()
	get_tree().current_scene.add_child(bomb_projectile)
	
	# Set position to bomb's current position
	bomb_projectile.global_position = global_position
	print("Bomb projectile positioned at: ", bomb_projectile.global_position)
	
	# Get the aircraft from the hardpoint (parent)
	var aircraft = get_parent()
	while aircraft and not (aircraft is RigidBody3D):
		aircraft = aircraft.get_parent()
	
	# Calculate drop velocity - inherit aircraft velocity for realistic ballistics
	var aircraft_velocity = aircraft.linear_velocity if aircraft else Vector3.ZERO
	var drop_velocity = Vector3.DOWN * drop_force + aircraft_velocity
	print("Aircraft velocity: ", aircraft_velocity)
	print("Drop velocity calculated: ", drop_velocity)
	print("Using aircraft: ", aircraft.name if aircraft else "None found")
	
	# Use the projectile's fire method
	bomb_projectile.fire(drop_velocity, aircraft)
	
	ammo_count -= 1
	
	# Self-destruct if enabled and empty
	if delete_when_empty and ammo_count <= 0:
		queue_free()
	
	return true
