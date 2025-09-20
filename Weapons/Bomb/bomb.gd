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
	var bomb_projectile: BombProjectile = bomb_projectile_scene.instantiate()
	get_tree().current_scene.add_child(bomb_projectile)
	
	# Align bomb orientation to the hardpoint while preserving the bomb scene's intrinsic rotation and scale
	if hardpoint:
		var hp_tr: Transform3D = hardpoint.global_transform
		var hp_rot: Basis = hp_tr.basis.orthonormalized()
		# Capture the bomb scene's original basis decomposition (rotation + scale)
		var src_basis: Basis = bomb_projectile.global_basis
		var src_rot: Basis = src_basis.orthonormalized()
		var src_scale: Vector3 = src_basis.get_scale()
		# Compose final basis: hardpoint rotation, then bomb's local rotation, then apply bomb's scale
		var final_basis: Basis = hp_rot * src_rot
		final_basis = final_basis.scaled(src_scale)
		bomb_projectile.global_transform = Transform3D(final_basis, hp_tr.origin)
	else:
		# Fallback: keep current position and remove any inherited scale
		bomb_projectile.global_position = global_position
		bomb_projectile.global_basis = Basis.IDENTITY
		bomb_projectile.scale = Vector3.ONE
	
	# Get the aircraft from the hardpoint (parent)
	var aircraft_node: Node = get_parent()
	while aircraft_node and not (aircraft_node is RigidBody3D):
		aircraft_node = aircraft_node.get_parent()
	var aircraft: RigidBody3D = aircraft_node as RigidBody3D
	
	# Calculate drop velocity - inherit aircraft velocity for realistic ballistics
	var aircraft_velocity: Vector3 = aircraft.linear_velocity if aircraft else Vector3.ZERO
	var drop_velocity: Vector3 = Vector3.DOWN * drop_force + aircraft_velocity
	
	# Use the projectile's fire method
	bomb_projectile.fire(drop_velocity, aircraft)
	
	ammo_count -= 1
	
	# Self-destruct if enabled and empty
	if delete_when_empty and ammo_count <= 0:
		queue_free()
	
	return true
