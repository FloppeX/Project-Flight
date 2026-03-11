extends Weapon
class_name BulletWeapon

@export var bullet_scene: PackedScene
@export var bullet_speed: float = 100.0
@export var fire_rate: float = 5.0 # Shots per second
@export var damage_per_shot: float = 10.0

var _fire_timer: float = 0.0

func _ready() -> void:
    if not bullet_scene:
        bullet_scene = load("res://Projectiles/Bullet/bullet.tscn")

func _process(delta: float) -> void:
    if _fire_timer > 0:
        _fire_timer -= delta

func fire() -> bool:
    if not can_fire() or _fire_timer > 0.0:
        return false
        
    # Reset fire rate timer
    _fire_timer = 1.0 / fire_rate
    
    # We call super to reduce ammo
    super.fire()
    
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

func _spawn_bullet(spawn_transform: Transform3D, firing_entity: Node3D) -> void:
    if not bullet_scene:
        return
        
    var bullet = bullet_scene.instantiate()
    
    # Needs to be spawned at top level so it doesn't move with the gun
    var root = get_tree().current_scene
    if not root:
        push_warning("BulletWeapon: No current scene found.")
        return
        
    root.add_child(bullet)
    
    bullet.global_transform = spawn_transform
    
    # Move it slightly forward so it doesn't collide with the barrel immediately
    bullet.global_position += -bullet.global_transform.basis.z * 1.5
    
    # Fire direction is -Z of the spawn transform
    var direction = -spawn_transform.basis.z.normalized()
    var velocity = direction * bullet_speed
    
    if bullet.has_method("fire"):
        bullet.fire(velocity, firing_entity)
    
    if "damage_amount" in bullet:
        bullet.damage_amount = damage_per_shot
        
    # Audio could also be played here
