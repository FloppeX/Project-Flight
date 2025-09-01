extends Weapon
class_name Bomb

@export var bomb_projectile_scene: PackedScene
@export var drop_force: float = 100.0
@export var blast_radius: float = 10.0

func _ready():
	delete_when_empty = true 

func fire() -> bool:
	if not can_fire():
		return false
	
	# Create and drop bomb projectile
	var bomb_projectile = bomb_projectile_scene.instantiate()
	get_tree().current_scene.add_child(bomb_projectile)
	bomb_projectile.global_position = global_position
	
	var drop_velocity = Vector3.DOWN * drop_force + mounted_aircraft.linear_velocity
	bomb_projectile.linear_velocity = drop_velocity
	
	ammo_count -= 1
	
	# Self-destruct if enabled and empty
	if delete_when_empty and ammo_count <= 0:
		queue_free()
	
	return true
