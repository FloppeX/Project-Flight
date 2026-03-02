extends ProjectileNew
class_name BombProjectile

# =============================================================================
# BOMB PROJECTILE - Specialized bomb with arming delay
# =============================================================================

@export var arming_delay: float = 1.0  # Seconds before bomb can explode
@export var armed: bool = false
@export var explosion_radius: float = 30.0
@export var explosion_damage_multiplier: float = 2.0  # Multiplier for max damage

var arming_timer: float = 0.0

func _ready():
	super._ready()
	# Set base damage to match AG missile
	damage = 200.0
	# Failsafe: ensure explosion scene is loaded, matching missile behavior
	if explosion_scene == null:
		explosion_scene = load("res://Projectiles/Explosion/explosion.tscn")
	# Override the base class collision detection
	body_entered.disconnect(_on_body_entered)
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	# Update arming timer
	if not armed:
		arming_timer += delta
		if arming_timer >= arming_delay:
			arm_bomb()
	
	# Call parent physics process for tunneling detection
	super._physics_process(delta)

func arm_bomb():
	"""Arm the bomb after the delay"""
	armed = true

func _on_body_entered(body):
	if body == shooter:
		return
	if not armed:
		has_impacted = true
		queue_free()
		return
	_trigger_explosion(body)

func _trigger_explosion(hit_body: Node = null):
	# Create custom explosion with missile's damage values
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion)
		
		# Position explosion 1m above ground to avoid line-of-sight issues
		explosion.global_position = global_position + Vector3.UP * 1.0
		
		# Set explosion damage to match missile damage
		explosion.max_damage = damage * explosion_damage_multiplier
		explosion.min_damage = damage * 0.5
		explosion.blast_radius = explosion_radius
		explosion.use_line_of_sight = false
		
		
		# Always create scorch mark for missile explosions since they detonate near ground
		explosion.create_scorch_mark()
	
	# Mark as impacted and cleanup
	has_impacted = true
	queue_free()

func get_arming_status() -> Dictionary:
	"""Get bomb arming status for UI display"""
	return {
		"armed": armed,
		"arming_progress": arming_timer / arming_delay if arming_delay > 0 else 1.0,
		"time_remaining": max(0.0, arming_delay - arming_timer)
	}
