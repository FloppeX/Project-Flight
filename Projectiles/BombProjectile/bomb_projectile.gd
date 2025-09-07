extends Projectile
class_name BombProjectile

@export var explosion_radius: float = 10.0
@export var explosion_force: float = 1000.0

func _ready():
	# Override projectile defaults for bombs
	damage = 50.0  # More damage than bullets
	lifetime = 10.0  # Longer lifetime than bullets
	super._ready()

func _on_body_entered(body):
	if body == shooter:
		return
	
	# Bomb-specific explosion logic
	explode()
	
	# Let parent handle the basic impact
	super._on_body_entered(body)

func explode():
	# Create explosion area of effect
	var explosion_area = get_world_3d().direct_space_state
	# Add explosion force to nearby objects
	# Create explosion visual/audio effects
	# etc.
