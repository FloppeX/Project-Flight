extends Weapon
class_name BulletWeapon

@export var bullet_scene: PackedScene
@export var bullet_speed: float = 900.0
@export var fire_rate: float = 2.5 # Shots per second
@export var damage_per_shot: float = 20.0
@export var infinite_ammo: bool = true

func _ready() -> void:
	if not bullet_scene:
		bullet_scene = load("res://Projectiles/Bullet/bullet.tscn")

func fire() -> bool:
	if not can_fire():
		return false
	var now_s: float = Time.get_ticks_msec() / 1000.0
	var cooldown_s: float = 1.0 / maxf(fire_rate, 0.01)
	var next_fire_time_s: float = float(get_meta("next_fire_time_s", 0.0))
	if now_s < float(next_fire_time_s):
		return false
		
	# Reset fire rate cooldown
	set_meta("next_fire_time_s", now_s + cooldown_s)
	
	# Turret weapons default to sustained fire instead of running dry after a short exchange.
	super.fire()
	if infinite_ammo:
		ammo_count += 1
	
	# Try to find the turret/barrel we are attached to for position and direction
	var spawn_transform = global_transform
	var firing_entity = self
	
	# Crawl up to find the Turret if we are mounted on one
	var parent = get_parent()
	while parent:
		if parent is Turret:
			spawn_transform = parent.get_next_firing_transform()
			firing_entity = parent # So bullet ignores collision with the turret base
			
			# If the turret is on a ground vehicle, let's pass that as the firing entity instead
			var grandparent = parent.get_parent()
			var greatgrandparent = grandparent.get_parent() if grandparent else null
			
			if grandparent and grandparent.has_method("get_team"):
				firing_entity = grandparent
			elif greatgrandparent and greatgrandparent.has_method("get_team"):
				firing_entity = greatgrandparent
			break
		elif parent.has_method("get_team"): # Just directly on a vehicle
			firing_entity = parent
			break
		parent = parent.get_parent()

	_spawn_bullet(spawn_transform, firing_entity)
	return true

func can_fire() -> bool:
	if infinite_ammo:
		return true
	return super.can_fire()

func _spawn_bullet(spawn_transform: Transform3D, firing_entity: Node3D) -> void:
	if not bullet_scene:
		return
		
	var bullet = bullet_scene.instantiate()
	
	# Needs to be spawned at top level so it doesn't move with the gun
	var root = get_tree().current_scene
	if not root:
		push_warning("BulletWeapon: No current scene found.")
		return
		
	# Set transform BEFORE adding to tree so _ready() visuals don't flash at the origin
	bullet.transform = spawn_transform
	root.add_child(bullet)
	bullet.global_position += bullet.global_transform.basis.z * 2.5
	
	# Fire direction is +Z of the spawn transform
	var direction = spawn_transform.basis.z.normalized()
	var velocity = direction * bullet_speed
	
	if bullet.has_method("fire"):
		bullet.fire(velocity, firing_entity)

	# Orient bullet to match its actual velocity (which includes inherited platform velocity)
	if bullet is RigidBody3D and bullet.linear_velocity.length() > 1.0:
		var vel_dir: Vector3 = bullet.linear_velocity.normalized()
		var up := Vector3.UP
		var right := up.cross(vel_dir).normalized()
		if right.length_squared() > 0.0001:
			up = vel_dir.cross(right).normalized()
			bullet.global_transform.basis = Basis(right, up, vel_dir)

	if "damage_amount" in bullet:
		bullet.damage_amount = damage_per_shot
		
	# Audio could also be played here
